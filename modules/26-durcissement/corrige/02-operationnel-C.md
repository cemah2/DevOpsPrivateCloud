### M26-E17 — Politiques d'admission natives : ValidatingAdmissionPolicy et MutatingAdmissionPolicy

> **Vérifié hors lab** : les trois fichiers appliqués à un vrai kube-apiserver **1.36.5** (etcd 3.6) : refus `hostPath` dans un espace absent de la ConfigMap et pour un chemin hors liste, `/procfoo` refusé quand `/proc` est permis, `..` refusé par la validation de l'API ; DaemonSet rendus des charts Falco 9.2.1 (`modern_ebpf`), Tetragon 1.7.1 et ceph-csi 3.18.1 **acceptés** avec la ConfigMap du corrigé ; MAP : étiquette ajoutée, valeur existante conservée, rien hors des espaces d'équipe ; VAP d'étiquettes d'espace : refus par emprunt d'identité `oidc:lucas.martin`, passage pour `oidc:plateforme-admins`. Check E17 rejoué contre ce serveur (vert, puis rouge avec un pod `hostPath` posé avant la liaison).
> **Non testé en conditions réelles** : chemins `hostPath` exacts de node-exporter (kube-prometheus-stack), Alloy et Velero sur **ton** cluster (relevés à l'étape 1, à reprendre) ; rapports de Kyverno sur les VAP (droits de lecture de la ConfigMap de paramètres par Kyverno).

**Solution**

Fichiers : [`20-interdire-hostpath.yaml`](fichiers/M26-E17/k8s/admission/20-interdire-hostpath.yaml), [`30-etiquette-equipe-par-defaut.yaml`](fichiers/M26-E17/k8s/admission/30-etiquette-equipe-par-defaut.yaml), [`40-etiquettes-espace-protegees.yaml`](fichiers/M26-E17/k8s/admission/40-etiquettes-espace-protegees.yaml) (`plateforme/k8s`) ; essais [`m26-e17/`](fichiers/M26-E17/m26-e17/) ; document [`admission-native-ou-kyverno.md`](fichiers/M26-E17/medisphere/docs/securite/durcissement/admission-native-ou-kyverno.md).

1. **Recensement.**
   ```
   admin@adm01:~$ kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns
       | .spec.volumes[]? | select(.hostPath) | "\($ns) \(.hostPath.path)"' | sort -u > ~/m26/e17/hostpath-actuels.txt
   admin@adm01:~$ helm template falco oci://registry.par1.medisphere.internal/charts/falco --version 9.2.1 \
       -f ~/src/gitops/valeurs/falco/values.yaml | yq 'select(.kind=="DaemonSet") | .spec.template.spec.volumes[] | select(has("hostPath")) | .hostPath.path'
   ```
   Falco (chart 9.2.1, `modern_ebpf`) : `/proc`, `/boot`, `/lib/modules`, `/usr`, `/etc`, `/sys/kernel`, `/var/run` et les sockets de tous les moteurs de conteneurs (`/run/containerd`, `/run/crio`, `/run/podman`…) ; avec `driver.kind: auto`, il ajoute `/dev` et `/sys/module`. Tetragon 1.7.1 : `/proc`, `/sys/fs/bpf`, `/var/run/cilium`, `/var/run/cilium/tetragon`, `/var/run/tetragon`. Le node-exporter de kube-prometheus-stack monte la **racine** `/` (en lecture seule) : il voit tout le système de fichiers du nœud, clés de kubelet comprises. C'est la plus large des exceptions, et la VAP ne la réduit pas : elle l'**écrit**.
2. **La VAP.** Même ossature que `medisphere-images` : `variables.specPod` selon le type d'objet, `variables.chemins` (les `hostPath`), `variables.autorises` (lue dans `params.data[request.namespace]` si la clé existe, sinon liste vide), `variables.refuses` avec la règle « chemin exact ou sous-dossier » (`c == a || c.startsWith(a + '/')`). Liaison sur tout le cluster sauf `kube-system` et `cilium` : la couche de base (Cilium, CoreDNS) ne doit jamais dépendre d'une ConfigMap de paramètres.
3. **Essais.** Dans `wb-essais` (Pod Security `baseline`), c'est **Pod Security** qui refuse, et il refuse le premier : `violates PodSecurity "baseline:latest": hostPath volumes (volume "hote")` ; la VAP n'est même pas évaluée (dans la chaîne des contrôleurs de validation intégrés, `PodSecurity` passe avant `ValidatingAdmissionPolicy`). Dans `falco` (`privileged`), Pod Security laisse passer et la VAP refuse :
   ```
   … pods "e17-hostpath" is forbidden: ValidatingAdmissionPolicy 'medisphere-interdire-hostpath' with binding
   'medisphere-interdire-hostpath' denied request: volume(s) hostPath interdit(s) dans l'espace falco : /root
   (autorisés : /proc, /boot, /lib/modules, /usr, /etc, …) — dérogation : RB-261
   ```
   En `[Warn, Audit]`, le même essai est **accepté** avec un `Warning:` ; c'est la mise à jour à blanc des DaemonSet en service (`kubectl get ds … -o yaml | kubectl apply --dry-run=server -f -`) qui dit, sans rien redémarrer, si un agent serait refusé demain.
4. **`Deny` et paramètre absent.** `parameterNotFoundAction: Deny` : sans la ConfigMap, **tout** objet visé est refusé (y compris les pods sans `hostPath` : la politique ne peut pas s'évaluer). C'est le comportement sûr ; la ConfigMap vit dans le même fichier, avant la politique, et la VAP d'E17 B protège… les espaces, pas les ConfigMap : la protection de `kube-system` repose sur RBAC (personne d'autre que les administrateurs n'y écrit). `Allow` ferait d'une suppression de ConfigMap une désactivation silencieuse.
5. **Étiquettes d'espace.** `matchConditions` écarte les administrateurs (évaluée avant tout, pas de coût pour eux), les variables comparent `oldObject.metadata.labels` et `object.metadata.labels` (sur une table CEL, `filter` itère sur les clés). Essais :
   ```
   admin@adm01:~$ kubectl auth whoami                         # Groups: … oidc:plateforme-admins
   admin@adm01:~$ kubectl label ns wb-essais pod-security.kubernetes.io/enforce=privileged --overwrite \
       --as=oidc:lucas.martin --as-group=oidc:plateforme --dry-run=server
   Error from server (Forbidden): namespaces "wb-essais" is forbidden: User "oidc:lucas.martin" cannot patch resource "namespaces" …
   ```
   RBAC refuse **avant** l'admission (authentification, autorisation, puis mutation et validation) : c'est rassurant (Lucas n'a pas ce droit), mais la VAP n'a pas été évaluée. Pour l'éprouver, il faut une identité qui **a** le droit de modifier un `Namespace` sans être exclue : donne-la **temporairement** et à blanc, puis retire-la.
   ```
   admin@adm01:~$ kubectl create clusterrole e17-essai-ns --verb=get,patch --resource=namespaces
   admin@adm01:~$ kubectl create clusterrolebinding e17-essai-ns --clusterrole=e17-essai-ns --user=oidc:lucas.martin
   admin@adm01:~$ kubectl label ns wb-essais pod-security.kubernetes.io/enforce=privileged --overwrite \
       --as=oidc:lucas.martin --as-group=oidc:plateforme --dry-run=server
   Error from server (Forbidden): namespaces "wb-essais" is forbidden: ValidatingAdmissionPolicy 'medisphere-etiquettes-espace-protegees'
   with binding 'medisphere-etiquettes-espace-protegees' denied request: étiquette(s) de sécurité de l'espace modifiée(s)
   hors du dépôt plateforme/k8s : pod-security.kubernetes.io/enforce (demande : oidc:lucas.martin)
   admin@adm01:~$ kubectl delete clusterrolebinding,clusterrole e17-essai-ns
   ```
   (Deux objets créés à la main pour un essai de quelques minutes, supprimés aussitôt et notés dans `~/m26/e17/` : c'est l'exception, pas la règle.) Une étiquette `essai=oui` passe.
6. **La MAP.** `failurePolicy: Ignore` (une valeur par défaut n'est pas un contrôle : si elle échoue, rien ne doit être bloqué) ; `reinvocationPolicy: Never` (la mutation ne dépend d'aucune autre). La liaison limite aux espaces qui portent `medisphere.internal/equipe`.
7. **Le piège de l'étape 7.** Écrite avec une seconde `matchCondition` « l'espace porte l'étiquette » (`'medisphere.internal/equipe' in namespaceObject.metadata.labels`), la MAP **ne fait rien**, sans un mot. En `failurePolicy: Fail`, le message apparaît :
   ```
   … policy 'medisphere-etiquette-equipe-par-defaut' … denied request: expression 'has(namespaceObject.metadata.labels) && …'
   resulted in error: no such key: metadata
   ```
   `namespaceObject` n'est pas renseigné à l'évaluation des `matchConditions` (il l'est dans les variables, validations et mutations) ; le sélecteur de la liaison fait déjà ce travail. Après correction :
   ```
   admin@adm01:~$ kubectl create --dry-run=server -n mediagenda-dev -f ~/m26/e17/pod-sans-etiquette.yaml -o jsonpath='{.metadata.labels}{"\n"}'
   {"app.kubernetes.io/name":"e17-essai","medisphere.internal/equipe":"mediagenda"}
   ```
8. **Chaîne d'admission.** Authentification → autorisation (RBAC) → **mutation** (contrôleurs intégrés comme `ServiceAccount`, puis `MutatingAdmissionPolicy`, puis webhooks de mutation : `seccomp-par-defaut` de Kyverno) → validation du schéma → **validation** (contrôleurs intégrés dont `PodSecurity`, puis `ValidatingAdmissionPolicy`, puis webhooks de validation : `ValidatingPolicy` de Kyverno) → écriture dans etcd. Les validations voient donc le pod **muté**. On ne mute que des pods : un Deployment muté diffère de Git, Argo CD le voit `OutOfSync` (ou le « corrige » à chaque synchronisation, et la MAP le re-mute : une boucle).
9. **Rapports.** `kubectl get policyreports -A -o json | jq '[.items[].results[]? | select(.source=="ValidatingAdmissionPolicy") | .policy] | unique'` : Kyverno 1.19 évalue en tâche de fond les VAP (fonction `validatingAdmissionPolicyReports`, active par défaut dans le chart 3.9) et y rapporte `medisphere-images` et `medisphere-interdire-hostpath`. Si les VAP paramétrées n'apparaissent pas, regarde les journaux du contrôleur de rapports (lecture de la ConfigMap de paramètres : ⚠️ à vérifier).
10. **Document** : voir le fichier ; sa règle de choix tient en une ligne : natif quand la règle ne dépend que de la requête, de l'espace et de paramètres et doit tenir sans Kyverno ; Kyverno pour les données externes, les rapports, les exceptions datées, la génération et les tests en CI.

**Explications**

Une VAP est compilée et évaluée **dans** le kube-apiserver : pas de réseau, pas de réplicas, pas de certificat de webhook. `failurePolicy` ne joue que sur les erreurs d'évaluation (expression qui échoue, paramètre introuvable selon `parameterNotFoundAction`), pas sur une indisponibilité. La MAP, GA en 1.36, applique un *apply configuration* (fusion façon *server-side apply*) ou un patch JSON calculé en CEL, sans webhook. Les deux voient `request.userInfo` : ce que Pod Security, qui ne regarde que l'objet et l'étiquette de son espace, ne peut pas faire.

**Alternatives**
- Pod Security avec `exemptions` dans l'`AdmissionConfiguration` du kube-apiserver (utilisateurs, espaces, `RuntimeClass` exemptés) : grossier, et demande de toucher au manifeste statique.
- Kyverno pour les trois règles : possible (même CEL), mais une panne de Kyverno désarmerait aussi la protection des étiquettes d'espace, celle qui protège… les espaces de Kyverno.
- Un espace par agent avec des RBAC plus stricts plutôt qu'une liste `hostPath` : complémentaire, pas suffisant (le chart décide des montages).

**Pièges classiques**
- Liaison sans `matchResources` : `kube-system` compris ; au prochain redémarrage d'un pod de Cilium dont un chemin manque, plus de réseau.
- `startsWith(a)` sans séparateur : `/proc` autorise `/procfoo`.
- `namespaceObject` dans une `matchCondition` + `failurePolicy: Ignore` : une politique qui ne fait rien, sans erreur.
- Tester l'étiquette d'espace avec une identité sans droit RBAC : le refus vient de RBAC, la VAP n'est pas éprouvée.
- Oublier que le contrôleur d'Argo CD applique des `Namespace` versionnés (M22 : `journaux`) : sans son exclusion, la prochaine modification d'étiquette par MR échoue à la synchronisation.

**En production chez MédiSphère**

Les trois politiques vivent avec `medisphere-images` dans `plateforme/k8s/admission/`, appliquées par `task appliquer` et vérifiées par le check à chaque MR. La ConfigMap `medisphere-hostpath` est revue avec le registre des exceptions (EXC-K-003, EXC-K-004) ; réduire les moteurs de conteneurs de Falco (seul containerd) retirerait `/var/run`, `/run/crio`, `/run/podman`. Une alerte sur l'annotation d'audit `validation.policy.admission.k8s.io/validation_failure` (Loki, locataire `audit`, E28) remonte les avertissements des VAP en mode `Warn`.

**Ce qui reste promis** : la VAP qui refuserait les `CiliumNodeConfig` hors du compte d'automatisation (M15) et celle qui refuserait un RoleBinding donnant `pods/exec` à un sujet hors de l'équipe (M22) ne sont pas écrites ici ; elles suivent exactement le modèle de `medisphere-etiquettes-espace-protegees` (`request.userInfo`, `object.subjects`) et sont proposées au mini-projet (E46).

---

### M26-E18 — Exceptions et rapports de politiques

> **Vérifié hors lab** : chart Kyverno 3.9.2 rendu (`features.policyExceptions` → `--enablePolicyException=true --exceptionNamespace=kyverno-exceptions` sur les contrôleurs d'admission, de fond et de rapports ; désactivé par défaut) ; `PolicyException` et `exiger-digest` modifiée acceptées par un kube-apiserver 1.36.5 avec les CRD du chart (`policies.kyverno.io/v1` servie) ; `kyverno test` 1.19.2 vert sur `tests/exiger-digest-exception/` (et `kyverno apply` : 3 échecs sans l'exception, 1 succès et 2 échecs avec) ; code source de Kyverno 1.19.2 lu pour la sémantique (exception partielle par `images` pour les `ValidatingPolicy`, **ignorée** pour les `ImageValidatingPolicy` depuis la 1.19.1 ; échéance évaluée à la lecture des exceptions, donc à la recompilation de la politique ; espace de lecture) ; `verifier-exceptions.sh` exécuté sous `dash` (vert, puis cinq erreurs provoquées) ; règles `promtool check rules` et `promtool test rules` (Prometheus 3.15.1) ; 8 expressions du tableau validées par `promtool`. Image de l'opérateur dans `bootstrap-controller` confirmée dans le code de CloudNativePG 1.30.1 (`OperatorImageName`).
> **Non testé en conditions réelles** : délai réel entre `expiresAt` et l'arrêt de l'exemption dans le contrôleur (recompilation) ; noms exacts des métriques exportées (suffixe `_total` ajouté par l'exportateur OpenTelemetry : vérifie sur `/metrics` du contrôleur) ; contenu des rapports pour un objet exempté (`skip`).

**Solution**

Fichiers : valeurs [`kyverno` (extrait)](fichiers/M26-E18/gitops/valeurs/kyverno/values.yaml.extrait-E18), [AppProject (extrait)](fichiers/M26-E18/gitops/projets/plateforme.extrait-E18.yaml), [espace](fichiers/M26-E18/k8s/espaces/kyverno-exceptions.yaml), [`exiger-digest` (version E18)](fichiers/M26-E18/politiques/kyverno/validation/exiger-digest.yaml), [exception](fichiers/M26-E18/politiques/kyverno/exceptions/cnpg-operateur-sans-condense.yaml), [`kustomization.yaml` des exceptions](fichiers/M26-E18/politiques/kyverno/exceptions/kustomization.yaml) et [ligne de la racine](fichiers/M26-E18/politiques/kustomization.extrait-E18.yaml), [test](fichiers/M26-E18/politiques/kyverno/tests/exiger-digest-exception/), [`verifier-exceptions.sh`](fichiers/M26-E18/politiques/outils/verifier-exceptions.sh), [CI (extrait)](fichiers/M26-E18/politiques/.gitlab-ci.yml.extrait-E18), [valeurs du chart `mediagenda` (extrait)](fichiers/M26-E18/chart/values.yaml.extrait-E18), [règles](fichiers/M26-E18/observabilite/regles/politiques-admission.yaml) et [tests](fichiers/M26-E18/observabilite/tests/politiques-admission.test.yaml), [tableau](fichiers/M26-E18/observabilite/tableaux/plateforme/plateforme-politiques-admission.json) et [entrée du `kustomization`](fichiers/M26-E18/observabilite/tableaux/kustomization.extrait-E18.yaml).

1. **Rapports.** Deux familles d'échecs : `exiger-limites` sur le pod `valkey` de `mediagenda-dev` (conteneur d'initialisation sans ressources), `exiger-digest` sur `mediagenda-db-1..3` de `mediagenda-prod`. Les rapports (`wgpolicyk8s.io/v1alpha2`, un `PolicyReport` par ressource, champ `scope`) sont produits par le contrôleur de rapports à partir de l'analyse de fond ; ils montrent l'**existant**, y compris ce qui a été admis avant le passage en `Deny`.
2. **Valkey : on corrige.** `helm show values oci://registry.par1.medisphere.internal/charts/valkey --version 0.12.0 | grep -n initResources` → la clé existe. MR sur `mediagenda/chart` ([extrait](fichiers/M26-E18/chart/values.yaml.extrait-E18)), version mineure du chart, promotion. Réponse à Julien : « exception refusée : correction disponible (`valkey.initResources`), livrée dans le chart 0.x.y ». Ligne « close / refusée » au registre.
3. **PostgreSQL de la prod : on planifie.**
   ```
   admin@adm01:~$ kubectl -n mediagenda-prod get pod mediagenda-db-1 -o jsonpath='{range .spec.initContainers[*]}{.name}={.image}{"\n"}{end}{range .spec.containers[*]}{.name}={.image}{"\n"}{end}'
   bootstrap-controller=registry.par1.medisphere.internal/ghcr/cloudnative-pg/cloudnative-pg:1.30.1
   postgres=registry.par1.medisphere.internal/ghcr/cloudnative-pg/postgresql:18.6-minimal-trixie
   admin@adm01:~$ kubectl -n cnpg-system get deploy -o jsonpath='{..env[?(@.name=="OPERATOR_IMAGE_NAME")].value}{"\n"}'
   ```
   `postgres` vient du `Cluster` (`spec.imageName`) : corrigeable dans le dépôt de l'application (E21). `bootstrap-controller` vient de l'**opérateur** (`OPERATOR_IMAGE_NAME`) : le corriger, c'est redéployer l'opérateur de la couche de base (Helmfile) avec une image par condensé, ce qui redémarre **toutes** les instances de **tous** les clusters CNPG. Un changement planifié (`CHG-2718`), pas une MR de cinq minutes ; d'ici là, une exception.
4. **Activation.** `features.policyExceptions.enabled: true`, `namespace: kyverno-exceptions`. Sans le drapeau, une `PolicyException` est acceptée par l'API… et ignorée. Avec `*`, Kyverno lirait les exceptions de **tous** les espaces : une équipe qui a `edit` dans son espace pourrait désactiver une politique pour elle-même. Un espace dédié, où seule l'Application `politiques` écrit, fait de chaque exception une MR relue.
5. **Exception partielle.** Le moteur des `ValidatingPolicy` (1.19.2) distingue : exception **sans** `images` ni `allowedValues` → la politique est **sautée** pour l'objet ; exception **avec** `images` → la politique s'évalue, et l'expression peut lire `exceptions.allowedImages`. Une ligne dans `variables.sansCondense` : `&& !(i in exceptions.allowedImages)`. Pour une `ImageValidatingPolicy`, la 1.19.1 a **désactivé** les exceptions partielles (elles exemptaient toutes les images du pod) : seule l'exception totale existe, à manier avec des `matchConditions` serrées.
6. **L'exception** ([fichier](fichiers/M26-E18/politiques/kyverno/exceptions/cnpg-operateur-sans-condense.yaml)) : `policyRefs` (nom **et** `kind`), `matchConditions` (espace `mediagenda-prod`, étiquettes `cnpg.io/cluster` et `cnpg.io/podRole=instance`), `images` (l'image exacte de l'opérateur), `expiresAt` (⚠️ adapte la date : aujourd'hui + 60 à 90 jours, un jour ouvré), `reportResult: skip` (visible dans les rapports, pas maquillé en `pass`), `properties`. Test :
   ```
   admin@adm01:~/src/politiques$ kyverno test kyverno/tests/exiger-digest-exception
   │ 1  │ exiger-digest │ │ v1/Pod/mediagenda-prod/instance-cnpg-postgres-par-condense  │ Pass │ Ok │
   │ 2  │ exiger-digest │ │ v1/Pod/mediagenda-prod/instance-cnpg-postgres-par-etiquette │ Pass │ Ok │
   │ 3  │ exiger-digest │ │ v1/Pod/mediagenda-prod/api-image-operateur                  │ Pass │ Ok │
   Test Summary: 3 tests passed and 0 tests failed
   ```
   (« Pass » dans la colonne RESULT = le résultat attendu est obtenu : `pass` pour le premier, `fail` pour les deux autres.)
7. **CI.** [`verifier-exceptions.sh`](fichiers/M26-E18/politiques/outils/verifier-exceptions.sh) est en sh POSIX (l'image d'E07 est une Alpine sans bash) ; les dates sont comparées comme des chaînes au même format UTC, « dans 92 jours » vient de `date -u -d @<secondes>`. Essai d'échec :
   ```
   ÉCHEC  cnpg-operateur-sans-condense.yaml : échéance 2028-01-01T00:00:00Z au-delà de 92 jours
   ÉCHEC  cnpg-operateur-sans-condense.yaml : aucune matchCondition : l'exception vaudrait pour tout le cluster
   ÉCHEC  cnpg-operateur-sans-condense.yaml : valideur non autorisé : lucas.martin (autorisés : sophie.laurent)
   ```
   Le pipeline planifié du lundi (Build → Pipeline schedules, variable `PLANIFIE=exceptions`) échoue 14 jours avant une échéance : GitLab envoie le courriel d'échec. **La CLI `kyverno` ignore `expiresAt`** : une exception échue est encore appliquée par `kyverno apply` et `kyverno test` (constaté en 1.19.2). C'est une raison de plus de contrôler les dates soi-même.
8. **Constat.**
   ```
   admin@adm01:~$ kubectl get policyreports -n mediagenda-prod -o json | jq -r '.items[] | .scope.name as $o
       | .results[]? | select(.policy=="exiger-digest") | "\($o) \(.result) \(.message)"'
   mediagenda-db-1 skip rule is skipped due to policy exception: kyverno-exceptions/cnpg-operateur-sans-condense
   ```
   (Le texte exact du message dépend du moteur : ⚠️ à relire chez toi.) Si `postgres` est encore par étiquette, le résultat reste `fail` : c'est voulu (E21 le corrige).
9. **Règles.** Le piège : `execution_cause="background_scan"` incrémente le compteur à **chaque** analyse de fond, tant que l'objet reste non conforme (un état déguisé en compteur) ; d'où `increase(...[2h]) > 0` (« encore vu récemment ») plutôt qu'un `rate`. `PolitiqueRefusEnRafale` ne regarde que les politiques en `Deny` (en `Audit`, un échec n'est pas un refus). Tests `promtool` : rafale en recette (alerte), même débit en `Audit` (pas d'alerte), violation de fond en prod (alerte) et en recette (pas d'alerte).
10. **Tableau** : quatre statistiques (refus de l'heure, couples politique/espace de prod non conformes, politiques en erreur, exemptions), puis refus et échecs `Audit` par politique et espace, violations de fond, latence p95 (une politique lente ralentit **toutes** les créations de pods de son périmètre).

**Explications**

Une `PolicyException` CEL est compilée **avec** la politique qu'elle vise : le moteur recompile la politique quand une exception change, et c'est à ce moment qu'il écarte celles qui sont échues. Les `matchConditions` d'une exception s'évaluent sur la même requête que la politique (`object`, `oldObject`, `request`, `namespaceObject`). Sans `images`, l'exemption est totale ; avec, elle est partielle et dépend de la politique. Le registre et la CI donnent ce que Kyverno ne donne pas : qui a validé, pourquoi, jusqu'à quand, et la garantie qu'une exception trop large n'arrive jamais dans le cluster.

**Alternatives**
- Exclure par le `matchConstraints` de la politique (sélecteur d'étiquettes) : invisible dans les rapports, sans échéance ; à réserver aux exclusions de conception (ex. `kube-system`).
- Annotation de dérogation sur l'objet lu par la politique : l'équipe se l'accorde elle-même ; non.
- Policy Reporter (Kyverno) pour les tableaux et notifications des rapports : plus riche par ressource, un composant de plus à exploiter.

**Pièges classiques**
- Oublier `features.policyExceptions.enabled` : l'exception « marche » dans `kyverno test` et pas dans le cluster.
- Exception posée dans un autre espace que `kyverno-exceptions` : acceptée par l'API, ignorée par Kyverno.
- `policyRefs` avec le bon nom et le mauvais `kind` (`ClusterPolicy` au lieu de `ValidatingPolicy`) : aucune correspondance, aucune erreur.
- Exception partielle (`images`) sur une politique qui ne lit pas `exceptions.allowedImages` : sans effet ; sur une `ImageValidatingPolicy` : ignorée depuis la 1.19.1.
- Se fier à `kyverno test` pour l'échéance (la CLI l'ignore).
- Alerter sur un `rate` de `background_scan`.

**En production chez MédiSphère**

Les exceptions sont revues chaque mois avec le registre (E23) ; le tableau `politiques-admission` est projeté à la revue hebdomadaire de la plateforme ; `CHG-2718` (opérateur CNPG par condensé) ferme EXC-K-001. Une alerte sur l'échéance proche pourrait venir de kube-state-metrics (*custom resource state* sur `spec.expiresAt`) plutôt que du pipeline planifié : à évaluer quand les exceptions seront plus nombreuses.

---

### M26-E19 — Falco : règles de MédiSphère et acheminement des alertes

> **Vérifié hors lab** : règles validées par le binaire **Falco 0.45.1** (`falco -V` des règles par défaut puis des nôtres, greffon `container` chargé par `-o 'load_plugins[]=container'`) ; configuration avec `append_output` validée par le schéma de Falco ; `valider-falco.sh` exécuté sous `dash` avec yq 4.54.1 (vert ; rouge sur une règle sans gravité, désactivée ou mal nommée) ; chart falco 9.2.1 rendu avec les valeurs et les règles (ConfigMap `falco-rules`, annotation `checksum/rules`, variables de falcosidekick) ; DaemonSet rendu accepté par la VAP `hostPath` d'E17 ; routage d'Alertmanager rejoué par `amtool` 0.34.1 ; code de falcosidekick 2.31.1 lu (étiquettes = champs de sortie, `extralabels` appliquées **après**, sortie Loki).
> **Non testé en conditions réelles** : déclenchement effectif de chaque règle sur `k8s-par1` (aucun pilote dans le bac à sable) ; champ `extra_fields` à valeur fixe (`gravite: "critique"`) transmis à falcosidekick ; port vu par Falco avec le remplacement de kube-proxy (8000 attendu, pas 80) ; présence de `/etc/falco/falco_rules.yaml` et du greffon dans l'image `falcosecurity/falco:0.45.1` utilisée par la CI.

**Solution**

Fichiers : [règles](fichiers/M26-E19/politiques/falco/regles-medisphere.yaml), [`valider-falco.sh`](fichiers/M26-E19/politiques/outils/valider-falco.sh), [CI (extrait)](fichiers/M26-E19/politiques/.gitlab-ci.yml.extrait-E19), [valeurs de Falco (extrait)](fichiers/M26-E19/gitops/valeurs/falco/values.yaml.extrait-E19), [Application `falco`](fichiers/M26-E19/gitops/plateforme/falco.yaml), [routage (extrait)](fichiers/M26-E19/observabilite/kps/alertmanager-falco.extrait-E19.yaml), [RB-260](fichiers/M26-E19/medisphere/docs/securite/durcissement/runbooks/RB-260-alerte-falco.md).

1. **Lire les macros.** `container` : `container.id != host` ; `container_entrypoint` : processus sans parent ou dont le parent est le runtime (`runc`…) ; `open_read`/`open_write` : ouvertures **réussies** (`fd.num>=0`). `outbound` exclut toute destination RFC 1918 : `10.240.x.y → 10.10.20.18:443` n'est **pas** « sortant » pour elle, ni rien d'autre dans le lab. Chemin de l'exécutable : `proc.exepath` ; port de destination : `fd.sport` (port du **serveur**, même vu du client).
2. **Port vu.** Le remplacement de kube-proxy de Cilium traduit l'adresse du Service dans le `connect()` lui-même (programme eBPF de socket) : Falco voit l'adresse et le port du **pod** (8000), pas 80. Les deux sont dans la liste (le 80 pour les Services sans traduction, ex. vers la passerelle). ⚠️ À vérifier sur ton lab avec un événement réel.
3. **Les règles.** Six règles, chacune avec périmètre (`medisphere_espace_applicatif`, `medisphere_production`), exceptions (listes `medisphere_*`, macro `medisphere_exec_prod_attendu` à `never_true`), sortie lisible. Points de conception :
   - jeton : `fd.name pmatch (medisphere_chemins_jeton)` avec `/var/run/…` **et** `/run/…` (le chemin demandé par le processus) ; `manager` (CNPG) dans la liste ;
   - `/etc` : la condition **ne** reprend **pas** `open_write` ; elle prend toute ouverture en écriture (`evt.is_open_write=true`), réussie ou non : avec `readOnlyRootFilesystem`, la tentative échoue (`EROFS`), et c'est elle qui est intéressante ; `%evt.res` dans la sortie ;
   - port non prévu : `evt.type = connect`, sans condition de succès (une tentative bloquée par la politique réseau est un signal) ;
   - `/tmp` : `proc.exepath pmatch (medisphere_repertoires_temporaires)` ; un `emptyDir` n'est pas `noexec` ;
   - exec en production : `container_entrypoint and proc.vpid != 1` (lancé par le runtime, mais pas le processus principal). Une sonde `exec` déclencherait aussi : MédiAgenda et MédiDoc n'ont que des sondes HTTP ; sinon, la macro `medisphere_exec_prod_attendu`.
4. **CI.** Deux jobs : `falco:conventions` (Alpine d'E07 + yq vérifié par empreinte : extraction et conventions, artefact `regles-extraites/`) puis `falco:valider` (image officielle de Falco **de la version du cluster**) :
   ```
   admin@adm01:~/src/politiques$ sh outils/valider-falco.sh conventions
   conventions : OK (6 règles) → regles-extraites/regles-medisphere.yaml
   ```
   Le second temps tourne dans le job `falco:valider` ; en local, avec le binaire de l'archive amont (`falco-0.45.1-x86_64.tar.gz`, dépliée dans `~/m26/e19/falco/`, `library_path` du greffon `container` ajusté dans sa configuration) :
   ```
   admin@adm01:~/src/politiques$ F=~/m26/e19/falco/falco-0.45.1-x86_64
   admin@adm01:~/src/politiques$ FALCO=$F/usr/bin/falco FALCO_CONFIG=$F/etc/falco/falco.yaml \
       FALCO_REGLES_DEFAUT=$F/etc/falco/falco_rules.yaml sh outils/valider-falco.sh moteur
   …/etc/falco/falco_rules.yaml: Ok
   regles-extraites/regles-medisphere.yaml: Ok
   ```
   Sans le greffon : `Error: Plugin requirement not satisfied, must load one of: container (>= 0.4.0)` (les règles par défaut l'exigent). Une faute (`fd.nom`) : `LOAD_ERR_COMPILE_CONDITION`, ligne et colonne.
5. **Livraison.** Application à **trois** sources (chart, `plateforme/gitops` pour les valeurs, `plateforme/politiques` pour les règles) ; `kubectl -n falco get cm falco-rules -o jsonpath='{.data}' | grep -c 'rule: MédiSphère'` → 6 ; les pods redémarrent un à un (somme `checksum/rules`). Valeurs : `append_output` (gravité d'après l'étiquette ; la première entrée reprend le défaut `suggested_output`), `falco.priority: notice`, et côté falcosidekick `extralabels: equipe:plateforme,alertname:AlerteFalco` (**sans** la `gravite` fixe d'E08 : falcosidekick applique ses `extralabels` après les champs de sortie, elle écraserait celle de la règle) et `expireafter: 1800` (une alerte Falco est un événement : sans échéance, elle resterait active).
6. **Essais** (pod `falco-essai` de `wb-essais`) :
   ```
   admin@adm01:~$ kubectl -n wb-essais exec -it falco-essai -- bash
   root@falco-essai:/# cat /var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null   # si un jeton est monté
   root@falco-essai:/# touch /etc/essai ; cp /bin/ls /tmp/x && /tmp/x
   root@falco-essai:/# timeout 3 bash -c '</dev/tcp/10.10.20.19/2222'
   ```
   Loki (`loki-audit`) : `{service="falco", rule=~"MédiSphère.*"} | json` ; une ligne par règle, avec `output_fields_k8s_pod_name`. Alertmanager : alertes `AlerteFalco`, `rule="MédiSphère — …"`, `gravite="critique"` pour le jeton, `/etc` et `/tmp`.
7. **Bruit d'une journée** (typique) : « lecture du jeton » par les instances CNPG (`manager`, déjà exclu ; sinon c'est la première exception), « port non prévu » vers `9187` si un exportateur interroge… à toi de lire ; chaque traitement = un élément de liste + une ligne au registre (EXC-D-…).
8. **Routage** (`amtool` 0.34.1 sur la configuration rendue) :
   ```
   admin@adm01:~$ amtool config routes test --config.file=alertmanager.yaml alertname=AlerteFalco gravite=critique priority=Critical
   astreinte-mail,securite-mail
   admin@adm01:~$ amtool config routes test --config.file=alertmanager.yaml alertname=AlerteFalco gravite=avertissement priority=Warning
   securite-mail
   admin@adm01:~$ amtool config routes test --config.file=alertmanager.yaml alertname=AlerteFalco priority=Critical
   astreinte-mail,securite-mail
   ```
9. **RB-260** : voir le fichier ; l'essentiel est la décision en 15 minutes et la règle « on isole, on ne supprime pas » (les preuves sont dans le pod).

**Explications**

Falco évalue chaque événement du noyau contre des conditions compilées ; les macros et listes sont des fragments réutilisables, surchargeables par `override: {items: append}` ou `{condition: append|replace}` dans un fichier chargé après. Garder nos règles dans un fichier à nous, et les exceptions dans **nos** listes, évite d'éditer les règles amont (perdues à la montée de version). falcosidekick reçoit le JSON de Falco (`http_output`) et le distribue : chaque champ de sortie devient une étiquette d'alerte (d'où le regroupement par règle et par pod) et, pour Loki, les champs choisis deviennent des étiquettes (`k8s_ns_name`, `k8s_pod_name`, `rule`, `priority`, `service`).

**Alternatives**
- Laisser falcoctl suivre les règles amont depuis Internet : refusé (E08), les règles changent par MR.
- `customRules` dans les valeurs du dépôt `plateforme/gitops` : possible, mais les règles se relisent avec les politiques (même équipe, même CI).
- ConfigMap générée par Kustomize et montée : sans somme de contrôle, Falco ne redémarre pas de façon fiable au changement.

**Pièges classiques**
- `outbound` dans un réseau privé : ne voit rien.
- `open_write` pour un système de fichiers en lecture seule : ne voit pas les tentatives.
- Désactiver une règle bruyante : la détection disparaît pour tout le monde ; la bonne réponse est une exception ciblée.
- Alertmanager v1 (`/api/v1/alerts`) : 404 depuis la 0.27.
- `extralabels` qui écrase un champ de la règle.

**En production chez MédiSphère**

Une revue mensuelle du bruit par règle (requête de RB-260), un exercice sur table trimestriel (E33), et la règle d'or : aucune MR de règles pendant un incident. Le greffon `k8saudit` (journal d'audit de l'API dans Falco) est une piste pour la règle « exec en production » : il dirait **qui** ; en attendant, E28 le fait par le ruler de Loki.

---

### M26-E20 — Tetragon : observer processus, fichiers et réseau

> **Vérifié hors lab** : chart Tetragon 1.7.1 rendu avec les valeurs (images par le cache `quay`, `export-allowlist` et `export-denylist` dans la configuration, ServiceMonitor) ; DaemonSet accepté par la VAP `hostPath` d'E17 ; trois `TracingPolicy` acceptées par un kube-apiserver 1.36.5 avec les CRD du chart ; types d'arguments, opérateurs et format de `rateLimit` relus dans le code de Tetragon 1.7.1 ; résolution des chemins par rapport à la racine **du processus** (`fs->root`) relue dans le programme eBPF ; noms des champs JSON (`process_kprobe`, `policy_name`, `linux_binprm_arg`, `file_arg`, `sock_arg`, `namespace_regex`, `policy_names`) relus dans l'API 1.7.1 ; options de `tetra getevents` relues.
> **Non testé en conditions réelles** : chargement des sondes sur le noyau 6.12 des nœuds, coût mesuré, déclenchements ; volume réel après filtrage ; requêtes LogQL sur de vrais événements.

**Solution**

Fichiers : [Application](fichiers/M26-E20/gitops/plateforme/tetragon.yaml), [valeurs](fichiers/M26-E20/gitops/valeurs/tetragon/values.yaml), [AppProject (extrait)](fichiers/M26-E20/gitops/projets/plateforme.extrait-E20.yaml), [espace](fichiers/M26-E20/k8s/espaces/tetragon.yaml), [`wb-checks-securite` (extrait)](fichiers/M26-E20/k8s/rbac/wb-checks-securite.extrait-E20.yaml), politiques [`observer-exec`](fichiers/M26-E20/politiques/tetragon/observer-exec.yaml), [`fichiers-sensibles`](fichiers/M26-E20/politiques/tetragon/fichiers-sensibles.yaml), [`connexions-sortantes`](fichiers/M26-E20/politiques/tetragon/connexions-sortantes.yaml), [`kustomization.yaml`](fichiers/M26-E20/politiques/tetragon/kustomization.yaml) et [ligne de la racine](fichiers/M26-E20/politiques/kustomization.extrait-E20.yaml), [Alloy (extrait)](fichiers/M26-E20/observabilite/alloy/config.alloy.extrait-E20), [requêtes](fichiers/M26-E20/observabilite/requetes/tetragon-falco.logql).

1. **Rendu.** DaemonSet `tetragon` (conteneurs `tetragon` et `export-stdout`), Deployment `tetragon-operator` (installe et met à jour les CRD : `crds.installMethod: operator`), `hostNetwork: true`, tolérance universelle (`operator: Exists` : nœuds de contrôle compris), montages `/proc`, `/sys/fs/bpf`, `/var/run/cilium`, `/var/run/tetragon` — ceux de la clé `tetragon` d'E17, sinon le DaemonSet serait refusé.
2. **Installation** : espace `privileged`, Application, destination dans l'AppProject. `kubectl -n tetragon get ds tetragon` : six prêts.
3. **Sans politique**, un `process_exec` contient le binaire, les arguments, le répertoire courant, l'UID, le **parent** (et, avec `enableProcessCred`, les capacités), le pod (nom, espace, étiquettes, conteneur, image par condensé). `tetra getevents` interroge l'agent **local** : prends le pod Tetragon du nœud du pod d'essai. Volume brut : de l'ordre de plusieurs milliers de lignes par minute et par travailleur (sondes, scripts des images, CNPG) ; ⚠️ mesure le tien.
4. **Filtre d'export** : exécutions des seuls espaces applicatifs (`namespace_regex`), événements de nos politiques partout (`policy_names`), refus par défaut conservés (l'**hôte** est exclu : c'est le travail d'auditd, E12). Ordre de grandeur attendu : division par 10 à 50.
5. **Les politiques.**
   - `observer-exec` : `security_bprm_check` est le crochet LSM appelé à chaque `execve`, **avant** le chargement du binaire, avec le `linux_binprm` (fichier réellement exécuté, liens résolus) ; l'appel système, lui, ne donne que le chemin demandé. C'est aussi là qu'un `Sigkill` (E29) arrête l'exécution.
   - `fichiers-sensibles` : `security_file_permission(file, mask)` à chaque lecture/écriture. Chemin résolu par rapport à la racine du processus : `/etc/shadow` du conteneur, pas celui de l'hôte. Deux préfixes pour les jetons : si `/var/run` est un lien vers `/run` dans l'image, le runtime a monté le volume sous `/run/secrets/…`, et c'est ce chemin que le noyau rend. `rateLimit: 1m` : un client Kubernetes relit son jeton périodiquement (chaque lecture serait un événement).
   - `connexions-sortantes` : `tcp_connect(sock)`, `NotDAddr` des pods, des Services et de la boucle : reste ce qui **sort** (VMs, Internet). Avec le remplacement de kube-proxy, une destination de Service est déjà traduite en pod.
6. **Essais.** `tetra tracingpolicy list` : trois politiques `enabled`. Événements : `process_kprobe` avec `function_name: security_bprm_check` et `linux_binprm_arg.path: /tmp/x` ; `file_arg.path: /var/run/secrets/kubernetes.io/serviceaccount/..2026_…/token` ; `sock_arg.daddr: 10.10.20.18`, `dport: 443`.
7. **Alloy** : deux règles de `discovery.relabel` sur `espace/conteneur`. Vérification :
   ```
   admin@adm01:~$ logcli query --org-id=audit '{service="tetragon"}' --since=10m --limit=3
   admin@adm01:~$ logcli query --org-id=plateforme '{namespace="tetragon", container="export-stdout"}' --since=10m --limit=3   # vide
   ```
8. **Requêtes** : voir le fichier. La corrélation la plus simple est le nom du pod et la minute ; l'arbre complet se lit en remontant `process_exec_parent_exec_id` (Falco n'a que `proc.pname` et `proc.aname[n]`).
9. **Comparaison** (proposition pour `~/m26/e20/comparaison.md`) :

   | | Falco | Tetragon |
   |---|---|---|
   | Ce qu'il observe | appels système (pilote eBPF) + contexte du conteneur | fonctions du noyau choisies (kprobes, crochets LSM, tracepoints) |
   | Langage | règles (conditions sur des champs) | politiques (fonction, arguments, sélecteurs) |
   | Points forts | catalogue de règles, sorties, sens « métier » des alertes | arbre des processus, identité Kubernetes native, action **dans** le noyau (E29) |
   | Coût mesuré | ⚠️ ton relevé (E08 : 200-300 Mo par nœud) | ⚠️ ton relevé |
   | Rôle chez MédiSphère | **alerter** | **expliquer** (et bloquer, au cas par cas) |

**Explications**

Tetragon attache des programmes eBPF aux fonctions désignées et filtre **dans le noyau** (sélecteurs) avant de remonter l'événement : ce qui n'est pas sélectionné ne coûte presque rien en espace utilisateur. Le cache de processus (`processCacheSize`) relie chaque événement à son `exec_id` et à celui de son parent : c'est ce qui permet l'arbre. L'export est la seule voie vers les journaux : le filtrer, c'est choisir ce qu'on gardera un an.

**Alternatives**
- `TracingPolicyNamespaced` par espace applicatif : périmètre plus étroit, mais une par espace, et le droit d'en créer doit rester à la plateforme.
- Hubble (Cilium) pour le réseau : il voit les flux au niveau L3-L7, pas le processus qui les ouvre ; complémentaire.
- Recevoir les événements par gRPC (`tetra`) plutôt que par fichier : pour un SIEM, l'export JSON suffit.

**Pièges classiques**
- Sélecteur trop large sur `security_file_permission` : charge sur tous les nœuds.
- Un seul préfixe `/var/run/secrets/…` : les images où `/var/run` est un lien échappent.
- Croire que `tetra getevents` voit tout le cluster.
- Oublier la clé `tetragon` dans la ConfigMap `hostPath` d'E17 : DaemonSet refusé.
- Laisser les événements dans le locataire `plateforme` (14 jours) : ils doivent vivre un an dans `audit`.

**En production chez MédiSphère**

Tetragon et Falco restent tous les deux : Falco alerte, Tetragon explique et, au cas par cas, bloque (E29). Les politiques sont revues avec les règles Falco ; le volume exporté est suivi par une alerte de capacité sur le locataire `audit` (M22-E14).

---

### M26-E21 — Des charges sûres par construction

> **Vérifié hors lab** : `audit-charges-sures.sh` exécuté contre un kube-apiserver 1.36.5 (pods conformes : aucun écart ; pod non conforme : quinze écarts attendus, dont C6 détecté par le volume projeté injecté par l'admission) ; chart `mediagenda` du M17 rendu avec les gabarits modifiés (`runAsUser`, `appArmorProfile`) et accepté en `restricted` ; gabarit d'image du sous-chart `valkey` 0.12.0 relu (condensé dans `image.tag` accepté) ; code de MédiDoc relu (`r.MultipartReader()`, pas de fichier temporaire).
> **Non testé en conditions réelles** : écarts réels de tes espaces ; mise à jour progressive des instances CNPG au changement d'`imageName` ; UID réel des images de bibliothèque.

**Solution**

Fichiers : [outil](fichiers/M26-E21/k8s/outils/audit-charges-sures.sh), [norme](fichiers/M26-E21/medisphere/docs/securite/durcissement/charges-sures.md), [gabarits `medisphere-commun` (extrait)](fichiers/M26-E21/chart/charts/medisphere-commun/templates/_commun.tpl.extrait-E21), [valeurs `mediagenda` (extrait)](fichiers/M26-E21/chart/charts/mediagenda/values.yaml.extrait-E21), [overlay de prod (extrait)](fichiers/M26-E21/deploiement/overlays/prod/kustomization.extrait-E21.yaml), [MédiDoc (extrait)](fichiers/M26-E21/medidoc-deploiement/base/deployment.extrait-E21.yaml).

1. **Mesure.**
   ```
   admin@adm01:~/src/k8s$ outils/audit-charges-sures.sh
   mediagenda-prod  mediagenda-db-1   bootstrap-controller  C7 image sans condensé
   mediagenda-prod  mediagenda-db-1   postgres              C7 image sans condensé
   mediagenda-prod  valkey-0          valkey                C7 image sans condensé
   mediagenda-recette …
   ```
   (Extrait type ; tes écarts dépendent de ton histoire.) C6 par le volume projeté : `automountServiceAccountToken` peut être faux sur le **ServiceAccount** et absent du pod ; ce qui compte, c'est le résultat (le contrôleur `ServiceAccount` a-t-il injecté `kube-api-access-*` ?). Classement typique : C7 sur les dépendances (overlay), C5 AppArmor non écrit (gabarits), C6 sur les pods de CNPG (exception), C3 sur les Jobs de test.
2. **Écrit ou par défaut.** Dans le pod en service, `seccompProfile` est là même si le manifeste ne l'écrit pas (`seccomp-par-defaut`, E16), `medisphere.internal/equipe` aussi (MAP, E17), le volume du jeton aussi (si le ServiceAccount ne l'interdit pas). AppArmor : containerd applique son profil par défaut quand AppArmor est actif sur le nœud, mais rien ne le dit dans le pod : on l'écrit (C5).
3. **Norme** : voir le fichier ; elle relie chaque critère à son mécanisme d'application (Pod Security, Kyverno, chart).
4. **MédiAgenda.** `medisphere-commun` 0.2.0 : `runAsUser`/`runAsGroup` (valeur `medisphere.uid`, 10001), `appArmorProfile: RuntimeDefault` ; `/tmp` en `emptyDir` avec `sizeLimit` ; nouvelle version du chart, rendu commité (M17), promotion. Overlay de prod : `images` de Kustomize pour l'API et Valkey (condensé), **patch** pour `spec.imageName` du `Cluster` (le transformateur `images` ne connaît pas ce champ). ⚠️ Changer `imageName` déclenche la mise à jour progressive des instances : fenêtre de changement. Le conteneur `bootstrap-controller` reste couvert par l'exception d'E18 jusqu'à `CHG-2718`.
5. **MédiDoc.** Déjà conforme sur C1-C6 et C8 ; AppArmor écrit. Pas de `/tmp` : l'application lit les téléversements en flux (`MultipartReader`), sans fichier temporaire. Ajouter un `emptyDir` « au cas où » ouvrirait un emplacement inscriptible et exécutable inutile.
6. **Preuves.**
   ```
   admin@adm01:~/src/k8s$ outils/audit-charges-sures.sh
   Aucun écart : toutes les charges des espaces /^(mediagenda|medidoc)-/ respectent la norme.
   admin@adm01:~$ helm template mediagenda ~/src/chart/charts/mediagenda -f … | kubectl apply --dry-run=server -n mediagenda-recette -f -
   ```
   Aucun `Warning: would violate PodSecurity` ; `kubectl get policyreports -n mediagenda-prod` : aucun `fail`.

**Explications**

L'admission dit « pas pire que » ; la norme dit « au moins ». Mesurer les pods **en service** attrape ce que les manifestes ne montrent pas : ajouts de l'admission, pods d'opérateurs, sous-charts, conteneurs d'initialisation. Écrire explicitement ce qui serait appliqué par défaut rend la conformité **vérifiable** par un outil qui lit le manifeste (kube-bench, kubescape, un auditeur).

**Alternatives**
- kubescape en continu (opérateur) : constats plus larges (cadres NSA, MITRE), plus de bruit, un composant de plus.
- Une `ValidatingPolicy` « charge sûre » en `Deny` qui reprend C1-C8 : pertinente une fois les écarts à zéro, en complément de Pod Security.
- Profils seccomp `Localhost` par application : gain réel, entretien coûteux ; plus tard, sur mesure.

**Pièges classiques**
- Juger sur le dépôt et pas sur le pod.
- Un UID explicite différent de celui de l'image : fichiers de l'image illisibles.
- `emptyDir` sans `sizeLimit` : un disque de nœud plein évince tous ses pods.
- Kustomize `images` sur un champ d'une CRD : rien ne change, sans erreur.

**En production chez MédiSphère**

`audit-charges-sures.sh` tourne chaque nuit (CronJob en lecture seule, ou job planifié de `plateforme/k8s`) et alimente une métrique d'écarts par espace ; le gabarit de projet du M28 part de `medisphere-commun` 0.2.0.

---

### M26-E22 — Revue : les manifestes et le Dockerfile du stagiaire

> **Vérifié hors lab** : manifestes de Lucas valides (`kubectl apply --dry-run=client`) ; version corrigée acceptée à blanc par un kube-apiserver 1.36.5 dans un espace `restricted` ; check E22 vert sur la version corrigée, neuf contrôles rouges sur les fichiers de Lucas.
> **Non testé en conditions réelles** : `ExternalSecret` (CRD d'ESO absente du serveur d'essai) et `CiliumNetworkPolicy` (CRD de Cilium absente) ; l'application elle-même (`app/` n'existe pas : c'est un exercice de revue).

**Proposition** : [`revue.md`](fichiers/M26-E22/revue.md) (19 défauts, gravités, commentaire de revue) et la version corrigée [`inventaire-images/`](fichiers/M26-E22/inventaire-images/) : [Dockerfile](fichiers/M26-E22/inventaire-images/Dockerfile), [values.yaml](fichiers/M26-E22/inventaire-images/values.yaml), [Deployment](fichiers/M26-E22/inventaire-images/manifestes/deployment.yaml), [Service](fichiers/M26-E22/inventaire-images/manifestes/service.yaml), [RBAC](fichiers/M26-E22/inventaire-images/manifestes/rbac.yaml), [politique réseau](fichiers/M26-E22/inventaire-images/manifestes/networkpolicy.yaml), [ExternalSecret](fichiers/M26-E22/inventaire-images/manifestes/externalsecret.yaml), [espace](fichiers/M26-E22/k8s/espaces/inventaire.yaml).

**Les points qui comptent**
1. **Sept bloquants** : jeton en clair dans Git et dans l'image ; socket de containerd ; `privileged` ; rôle `*` ; `hostNetwork` ; page des vulnérabilités publiée sans authentification. Chacun, seul, donne soit le nœud, soit le cluster, soit le registre.
2. **Le besoin réel** de Lucas (« lister les images plus vite ») se satisfait par l'API : `status.containerStatuses[].imageID` donne le condensé exécuté. Tout le reste (socket, privilèges, réseau de l'hôte) disparaît avec ce changement de conception : c'est la correction qui compte, pas la liste de réglages.
3. **Le jeton** : supprimer la ligne ne suffit pas. Il est dans l'historique de Git et dans les couches de l'image poussée. Ordre (RB-250) : révoquer le robot dans Harbor (ou régénérer son secret), créer le nouveau dans OpenBao, vérifier dans le journal d'audit de Harbor que l'ancien n'a pas servi depuis la MR, supprimer l'image exposée et ses copies, puis seulement nettoyer le dépôt (et Gitleaks aurait dû le voir : le composant `qualite` est-il dans la CI de ce projet ?).
4. **Erreurs ou choix** : erreurs = ce qui contredit une règle écrite (normes de conteneurs M12, norme « charge sûre », matrice des flux, politique des secrets) ; choix = la publication de la page, la fréquence d'interrogation de Harbor.
5. **Validation de la version corrigée** : à blanc dans un espace `restricted` et `kyverno apply` avec les politiques de `plateforme/politiques` (`registres-autorises`, `exiger-limites`, `exiger-etiquettes`) : aucun refus.

**Pièges classiques**
- Relever les défauts un par un sans voir qu'ils viennent d'**un** mauvais choix de conception (le socket).
- « Corriger » le rôle en listant toutes les ressources qui donnaient `Forbidden` : c'est le code qui faisait des appels inutiles.
- Une `NetworkPolicy` standard avec `ipBlock` vers l'API : Cilium ne fait pas correspondre par défaut les adresses des nœuds à un CIDR (identités réservées) ; `toEntities: [kube-apiserver]` d'une `CiliumNetworkPolicy` est exact.
- Remplacer `privileged` par une liste de capacités « au cas où ».

**En production chez MédiSphère**

La grille de cette revue rejoint le modèle de MR des projets de la plateforme ; Gitleaks et `kyverno apply` tournent sur chaque MR ; un nouvel outil interne part du gabarit `medisphere-commun` et d'un espace créé par la plateforme, jamais de `default`.

---

### M26-E23 — Registre des exceptions et procédure de dérogation

**Proposition** : [`exceptions.md`](fichiers/M26-E23/medisphere/docs/securite/durcissement/exceptions.md) et [`RB-261-derogation.md`](fichiers/M26-E23/medisphere/docs/securite/durcissement/runbooks/RB-261-derogation.md).

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Exhaustivité | Toutes les exceptions codées du module sont au registre : `durcissement_exceptions` (E10-E14), espaces `privileged` et `baseline` (E06), liste `hostPath` (E17), `PolicyException` (E18), listes Falco (E19), norme « charge sûre » (E21) ; et inversement, chaque ligne dit **où** l'exception est codée |
| Précision | Règle exacte (identifiant XCCDF complet, nom de politique et `kind`, nom de règle Falco), périmètre le plus étroit (hôte, espace, étiquettes, image, binaire) |
| Risque et compensation | Le risque résiduel est une phrase concrète (« un pod de ces espaces a les droits de l'hôte »), pas « risque faible » ; chaque risque a une compensation qui existe vraiment (VAP, Tetragon, auditd…) |
| Dates | Revue ≤ 3 mois pour le temporaire, ≤ 12 mois pour le permanent ; aucune exception sans date |
| Validation | Un valideur nommé (Sophie Laurent ; Claire Morel en suppléance) ; la validation **est** l'approbation de la MR |
| Procédure | Avant la demande : chercher la correction ; tableau « mécanisme → où et comment coder » pour les cinq mécanismes ; contrôles de la CI ; vérification après fusion (objet exempté accepté, objet hors périmètre toujours refusé) ; urgence (7 jours max, MR dans l'heure) ; échéance (pipeline planifié, effet à la date) ; retrait (vérifier la conformité **avant**) |
| Revue | Fréquence, participants, comparaison registre ↔ code (commandes), indicateurs (nombre, âge, prolongations) |
| Lien avec l'audit HDS | On peut répondre aux quatre questions de Sophie en ouvrant **un** fichier |

**Explications**

Un auditeur ne reproche pas d'avoir des exceptions ; il reproche de ne pas les connaître. Le registre est la vue humaine, le code est la vérité exécutée : la valeur vient de leur **concordance**, contrôlée chaque mois et, pour Kyverno, à chaque MR. L'échéance oblige à redécider ; la compensation montre que le risque a été pensé.

**Pièges classiques**
- Un registre qui décrit des intentions (« on va exclure… ») au lieu de ce qui est codé.
- Des exceptions « permanentes » sans date de revue.
- Un périmètre par espace quand un sélecteur d'étiquettes ou une image suffirait.
- Une procédure qui ne couvre que Kyverno : les hôtes et Falco ont aussi leurs exceptions.

**En production chez MédiSphère**

Le registre est relu en comité sécurité (indicateurs), joint au dossier de l'audit HDS avec les rapports de conformité (E34) et l'ADR-0260 (E31). F6 (sécurité et conformité) le reprend comme pièce d'entrée.
