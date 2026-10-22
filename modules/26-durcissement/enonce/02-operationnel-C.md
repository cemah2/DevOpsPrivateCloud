### M26-E17 — Politiques d'admission natives : ValidatingAdmissionPolicy et MutatingAdmissionPolicy  `LAB` `★★`

> **Ticket SEC-2717** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Trois trous que Kyverno ne doit pas être seul à boucher. Un : les espaces `privileged` (Falco, node-exporter, bientôt Tetragon) peuvent monter **n'importe quel** chemin du nœud ; je veux une liste fermée par espace. Deux : n'importe qui ayant le droit de modifier un `Namespace` peut changer son étiquette Pod Security et s'offrir `privileged` ; ces étiquettes ne doivent changer que par notre dépôt. Trois : la moitié des pods n'ont pas d'étiquette d'équipe, je ne sais pas à qui sont les alertes. Le M14 avait commencé avec les politiques natives ; Kubernetes 1.36 sait maintenant aussi **muter** sans webhook. Fais-le en natif, et écris-moi en une page quand on choisit natif et quand on choisit Kyverno.

**Objectifs pédagogiques**
- Écrire une `ValidatingAdmissionPolicy` paramétrée (ConfigMap de paramètres, `request.namespace`, variables) et la mettre en service sans casser les agents de nœud.
- Utiliser ce qu'aucun profil Pod Security ne voit : l'auteur de la requête (`request.userInfo`) et l'état précédent (`oldObject`).
- Écrire une `MutatingAdmissionPolicy` (GA en 1.36) par *apply configuration* et comprendre sa place dans la chaîne d'admission.
- Comparer politiques natives et Kyverno, et savoir lequel choisir.

**Prérequis** : M14-E18 (VAP `medisphere-images`, dossier `admission/` de `plateforme/k8s`) ; M26-E06 (Pod Security, espaces `privileged` écrits) ; M26-E07 (Kyverno, `wb-checks-securite`) ; M24-E17 (identités OIDC du cluster, groupe `oidc:plateforme-admins`).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| API | `admissionregistration.k8s.io/v1` : `ValidatingAdmissionPolicy` + `ValidatingAdmissionPolicyBinding` (GA depuis 1.30), `MutatingAdmissionPolicy` + `MutatingAdmissionPolicyBinding` (**GA en 1.36**, activée par défaut) |
| Fichiers | `plateforme/k8s/admission/` (à côté de `10-images-medisphere.yaml` du M14 et `classes-stockage.yaml` du M16) : **`20-interdire-hostpath.yaml`**, **`30-etiquette-equipe-par-defaut.yaml`**, **`40-etiquettes-espace-protegees.yaml`** ; appliqués par `task appliquer` après MR (clone `~/src/k8s`) |
| `hostPath` | VAP **`medisphere-interdire-hostpath`** sur les pods **et** leurs contrôleurs (même forme que `medisphere-images`), paramètre : ConfigMap **`medisphere-hostpath`** de `kube-system`, **une clé par espace**, valeur = chemins autorisés séparés par des virgules (le chemin ou un sous-dossier) ; liaison sur tout le cluster **sauf** `kube-system` et `cilium` (couche de base) |
| Équipe | MAP **`medisphere-etiquette-equipe-par-defaut`** : un pod créé sans `medisphere.internal/equipe` dans un espace qui porte cette étiquette la reçoit, avec la valeur de l'espace ; jamais d'écrasement d'une valeur présente |
| Étiquettes d'espace | VAP **`medisphere-etiquettes-espace-protegees`** : refuse l'ajout, le retrait ou la modification d'une étiquette `pod-security.kubernetes.io/*` ou `medisphere.internal/*` d'un `Namespace`, sauf pour les groupes `oidc:plateforme-admins`, `kubeadm:cluster-admins` (`admin.conf`), `system:masters` (`super-admin.conf`) et le contrôleur d'Argo CD (`system:serviceaccount:argocd:argocd-application-controller`, qui applique des espaces versionnés) |
| Agents qui montent l'hôte | node-exporter (`supervision-noeuds`), Alloy (`journaux`), ceph-csi (`ceph-csi`), Velero `node-agent` (`velero`), Falco (`falco`) ; Tetragon (`tetragon`) arrive en E20 : prévois sa clé (`/proc`, `/sys/fs/bpf`, `/var/run/cilium`, `/var/run/tetragon`) |
| Document | `docs/securite/durcissement/admission-native-ou-kyverno.md` de `plateforme/medisphere` |
| Brouillons | `~/m26/e17/` |

> ⚠️ **Attention** : une VAP en `Deny` mal paramétrée empêche des **DaemonSet de nœud** de recréer leurs pods (Alloy, ceph-csi, node-exporter) : au premier redémarrage d'un nœud, plus de journaux, plus de volumes. D'où la mise en service en deux temps (`[Warn, Audit]` d'abord, lecture, puis `[Deny]`), et l'exclusion de `kube-system`. La VAP sur les étiquettes d'espace peut **te** bloquer si ton identité n'est pas celle que tu crois : vérifie `kubectl auth whoami` **avant**, et garde `admin.conf` (Ansible Vault `critique`) sous la main. Retour arrière : `git revert` de la MR et `task appliquer` ; en urgence, `kubectl delete validatingadmissionpolicybinding <nom>` (la politique sans liaison ne fait rien), puis la MR.

**Travail demandé**

*A. `hostPath` : une liste fermée par espace*

1. Recense ce qui monte l'hôte **aujourd'hui** :
   ```
   admin@adm01:~$ kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace as $ns
       | .spec.volumes[]? | select(.hostPath) | "\($ns) \(.hostPath.path)"' | sort -u > ~/m26/e17/hostpath-actuels.txt
   ```
   Compare avec le rendu des charts (`helm template … | yq '… | .hostPath.path'`) : que montent Falco (pilote `modern_ebpf`) et Tetragon ? Lequel monte la racine `/` du nœud, et qu'est-ce que cela permet ?
2. Écris `20-interdire-hostpath.yaml` : la ConfigMap de paramètres, la VAP (variables : la spécification de pod selon le type d'objet, les chemins `hostPath`, les chemins autorisés pour `request.namespace`, les chemins refusés ; un message qui cite l'espace, les chemins refusés et les chemins autorisés) et sa liaison en **`["Warn", "Audit"]`**. Attention aux préfixes : `/proc` doit autoriser `/proc/1` mais pas `/procfoo`.
3. Applique (MR, `task appliquer`), puis éprouve sans rien créer :
   ```
   admin@adm01:~$ kubectl apply --dry-run=server -n wb-essais -f ~/m26/e17/pod-hostpath.yaml
   admin@adm01:~$ kubectl apply --dry-run=server -n falco -f ~/m26/e17/pod-hostpath.yaml
   admin@adm01:~$ kubectl -n falco rollout restart daemonset/falco && kubectl -n falco rollout status daemonset/falco
   ```
   (`pod-hostpath.yaml` : un pod qui monte `/root` du nœud, à écrire.) Pourquoi le message n'est-il pas le même dans `wb-essais` et dans `falco` ? Pour les autres agents, sans les redémarrer : réapplique à blanc chaque DaemonSet en service (`kubectl get ds -n <espace> <nom> -o yaml | kubectl apply --dry-run=server -f -`, une mise à jour passe par la VAP) et vérifie qu'**aucun** avertissement n'apparaît ; lis aussi le journal d'audit dans Loki (annotation `validation.policy.admission.k8s.io/validation_failure`) après une journée.
4. Passe la liaison en `["Deny"]` (MR). Que se passe-t-il si quelqu'un supprime la ConfigMap de paramètres ? Choisis `parameterNotFoundAction` et justifie.

*B. Les étiquettes de sécurité d'un espace*

5. Vérifie ton identité (`kubectl auth whoami`). Écris `40-etiquettes-espace-protegees.yaml` : une `matchCondition` qui écarte les identités autorisées, des variables qui comparent `oldObject` et `object` (clés protégées ajoutées, retirées ou modifiées), un message qui nomme les étiquettes et le demandeur. Applique en `Deny` directement (tu es exclu) et éprouve par emprunt d'identité :
   ```
   admin@adm01:~$ kubectl label ns wb-essais pod-security.kubernetes.io/enforce=privileged --overwrite \
       --as=oidc:lucas.martin --as-group=oidc:plateforme --dry-run=server
   admin@adm01:~$ kubectl label ns wb-essais essai=oui --as=oidc:lucas.martin --as-group=oidc:plateforme --dry-run=server
   ```
   Le second doit passer. Si le premier est refusé par RBAC **avant** la VAP, qu'est-ce que cela prouve, et comment éprouver quand même la VAP ?

*C. Une mutation sans webhook*

6. Écris `30-etiquette-equipe-par-defaut.yaml` : une MAP sur la création des pods, une `matchCondition` « l'étiquette manque », une mutation `ApplyConfiguration` qui pose l'étiquette avec la valeur de l'espace (`namespaceObject`), une liaison limitée aux espaces d'équipe. Choisis `failurePolicy` et `reinvocationPolicy` et justifie.
7. Éprouve sans rien créer, et compare avec un pod qui porte déjà une autre valeur :
   ```
   admin@adm01:~$ kubectl create --dry-run=server -n mediagenda-dev -f ~/m26/e17/pod-sans-etiquette.yaml \
       -o jsonpath='{.metadata.labels}{"\n"}'
   ```
   Si l'étiquette n'apparaît pas : passe **temporairement** `failurePolicy: Fail` et relis le message.
8. Où se place la MAP dans la chaîne d'admission par rapport aux webhooks de mutation de Kyverno (`seccomp-par-defaut`, E16), à Pod Security, aux VAP et aux `ValidatingPolicy` ? Pourquoi ne mute-t-on que des **pods** et jamais un Deployment ?

*D. Choisir*

9. Kyverno rapporte aussi les VAP : cherche dans les `PolicyReport` les résultats de `source: ValidatingAdmissionPolicy`. Lesquelles y figurent ?
10. Écris `admission-native-ou-kyverno.md` (une page) : ce qui tourne (natif et Kyverno), un tableau de comparaison (où ça tourne, pannes possibles, données externes, rapports, exceptions, tests hors cluster, pérennité), ta règle de choix, une ligne sur OPA Gatekeeper, les limites rencontrées.

**Critères de réussite**
- [ ] Les trois politiques et leurs liaisons existent ; `medisphere-interdire-hostpath` et `medisphere-etiquettes-espace-protegees` sont en `Deny`, la première exclut `kube-system`.
- [ ] Tous les pods en marche hors `kube-system` et `cilium` qui montent l'hôte le font sur des chemins autorisés par la ConfigMap pour leur espace (aucun agent ne sera refusé à son prochain redémarrage).
- [ ] Un pod sans étiquette d'équipe créé à blanc dans `mediagenda-dev` reçoit `medisphere.internal/equipe: mediagenda` ; un pod qui en porte une la garde.
- [ ] Un changement de l'étiquette `pod-security.kubernetes.io/enforce` par une identité hors administrateurs est refusé ; une autre étiquette passe.
- [ ] Les trois fichiers sont sur `main` de `plateforme/k8s` ; le document est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 26 17`

<details><summary>Indice 1</summary>

La forme de `medisphere-images` (M14-E18) se reprend presque telle quelle : une variable qui trouve la spécification de pod (pod, CronJob, autres contrôleurs), une liste extraite par `map`/`filter`, une validation `size(...) == 0` avec `messageExpression`. Avec un paramètre ConfigMap unique dans `kube-system`, `params.data` est une table : `request.namespace in params.data` dit si l'espace a une entrée.
</details>

<details><summary>Indice 2</summary>

Pour les étiquettes d'espace : sur une table (*map*) CEL, `filter` itère sur les **clés**. Les clés protégées modifiées sont celles de l'ancienne table dont la valeur a changé ou qui ont disparu, plus celles de la nouvelle qui n'existaient pas. `request.userInfo.groups` est une liste ; `exists` y cherche un groupe autorisé.
</details>

<details><summary>Indice 3</summary>

Si la MAP ne fait rien sans rien dire, relis la documentation sur les variables disponibles **dans les `matchConditions`** (et dans les mutations). Une `failurePolicy: Ignore` transforme une erreur d'expression en « rien ne se passe ».
</details>

**Pour aller plus loin** (facultatif) : [Validating Admission Policy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/), [Mutating Admission Policy](https://kubernetes.io/docs/reference/access-authn-authz/mutating-admission-policy/), [CEL dans Kubernetes](https://kubernetes.io/docs/reference/using-api/cel/). Ajoute à `medisphere-interdire-hostpath` une seconde validation qui exige `readOnly: true` sur tout montage d'un `hostPath` (les `volumeMounts` des conteneurs). Compare avec [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/docs/) (Rego, `ConstraintTemplate`) sur une de ces règles.

---

### M26-E18 — Exceptions et rapports de politiques  `LAB` `★★`

> **Ticket DEV-2718** — *De : Julien Petit* — *Copie : Sophie Laurent*
> Depuis que `exiger-limites` est en refus, le Valkey de `mediagenda-dev` ne redémarre plus : son conteneur d'initialisation vient du chart officiel et n'a pas de ressources. Il me faut une exception, s'il vous plaît.
>
> **Réponse de Karim Benali** : Avant d'accorder quoi que ce soit, regarde si on peut corriger. Et pendant que tu y es : les rapports montrent aussi des échecs `exiger-digest` sur les instances PostgreSQL de **la prod**. Si une instance redémarre, elle sera refusée. Sophie veut qu'à partir d'aujourd'hui toute exception soit **datée, justifiée, la plus étroite possible, et visible** : dans un registre, dans les rapports, et sur un tableau de bord, avec une alerte quand une politique refuse en boucle.

**Objectifs pédagogiques**
- Distinguer une correction d'une exception, et ne déroger qu'en dernier recours.
- Écrire une `PolicyException` `policies.kyverno.io/v1` étroite (conditions, images), datée (`expiresAt`), justifiée (`properties`), et l'activer dans Kyverno.
- Contrôler les exceptions en CI (échéance, périmètre, valideur) avant qu'elles n'arrivent dans le cluster.
- Lire les `PolicyReport`, exploiter les métriques de Kyverno (tableau de bord, alertes).

**Prérequis** : M26-E07 (Kyverno, `plateforme/politiques`), M26-E16 (`exiger-limites`, `exiger-digest`, tests `kyverno test`) ; M21-E15 à E17 (règles d'alerte, tests `promtool`, tableaux de bord en code) ; M20 (prod synchronisée à la main).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Exceptions | `PolicyException` **`policies.kyverno.io/v1`** : `policyRefs` (nom **et** type de politique), `matchConditions` (CEL, sur la requête), `images` (exception **partielle** : seules ces images ; la politique doit lire `exceptions.allowedImages`), `expiresAt` (RFC 3339), `properties` (clés libres), `reportResult` (`skip` ou `pass`) |
| Activation | désactivées par défaut dans le chart 3.9 : valeurs `features.policyExceptions` dans `plateforme/gitops`, `valeurs/kyverno/values.yaml` ; Kyverno ne lit les exceptions que dans l'espace **`kyverno-exceptions`** (à créer dans `plateforme/k8s/espaces/`) |
| Rangement | `plateforme/politiques`, **`kyverno/exceptions/`** (un fichier par exception, `kustomization.yaml` qui fixe l'espace), synchronisé par l'Application `politiques` ; AppProject `plateforme` : destination `kyverno-exceptions` |
| Propriétés exigées | `raison`, `ticket`, `valideur` (`sophie.laurent`), `revue` (AAAA-MM-JJ) ; échéance à **92 jours** au plus |
| CI | `outils/verifier-exceptions.sh` (à écrire, **POSIX sh** : l'image des jobs d'E07 est une Alpine sans bash ; yq de mikefarah) et job **`kyverno:exceptions`** sur MR **et** dans un pipeline planifié du lundi (variable `PLANIFIE=exceptions`) |
| Valkey de `mediagenda-dev` | sous-chart officiel `valkey` 0.12.0 du chart `mediagenda` (M17) |
| Instances PostgreSQL | pods `mediagenda-db-N` de CloudNativePG (étiquettes `cnpg.io/cluster`, `cnpg.io/podRole`) ; opérateur CNPG 1.30 de la couche de base (Helmfile, M16) |
| Métriques | `kyverno_validating_policy_results_total`, `kyverno_image_validating_policy_results_total` (étiquettes `policy_name`, `policy_validation_mode`, `resource_namespace`, `execution_cause` = `admission_request` ou `background_scan`, `result`) ; ServiceMonitor actifs depuis E07 |
| Supervision | `plateforme/observabilite` : `regles/politiques-admission.yaml` (+ test `promtool`), tableau `tableaux/plateforme/plateforme-politiques-admission.json`, UID **`politiques-admission`**, dossier « Plateforme » |
| Registre | `docs/securite/durcissement/exceptions.md` : sa forme définitive est l'objet d'E23 ; ici, une ligne par exception accordée ou refusée |

> ⚠️ **Attention** : une exception est une politique **désactivée** pour un périmètre ; trop large, elle ouvre le cluster sans bruit (une exception sans `matchConditions` vaut pour tout ce que la politique couvre). Et à son échéance, elle cesse de s'appliquer d'un coup : les objets exemptés sont de nouveau refusés au prochain redémarrage. Ne pose jamais une échéance qui tombe un vendredi soir. Toute modification de la prod passe par la MR et la synchronisation manuelle de `mediagenda-prod` (M20).

**Travail demandé**

*A. Corriger d'abord*

1. Lis les rapports : quelles politiques échouent, sur quoi, depuis quand ?
   ```
   admin@adm01:~$ kubectl get policyreports -A -o json | jq -r '.items[] | .metadata.namespace as $ns
       | .scope.name as $obj | .results[]? | select(.result=="fail") | "\($ns) \($obj) \(.policy) \(.message)"'
   ```
2. Valkey de `mediagenda-dev` : cherche dans `helm show values` du chart `valkey` 0.12.0 si les ressources du conteneur d'initialisation se règlent. Si oui, corrige dans `mediagenda/chart` (MR, nouvelle version) et réponds à Julien : exception **refusée**, avec la raison. Note-le au registre.
3. Instances PostgreSQL de la prod : quels conteneurs du pod échouent à `exiger-digest` ? D'où vient l'image de chacun (le `Cluster` de l'application, ou l'opérateur) ? Que faudrait-il changer pour corriger, et pourquoi est-ce un changement planifié (ticket `CHG-2718`) et non une MR de cinq minutes ?

*B. Une exception étroite*

4. Active les exceptions dans Kyverno (valeurs, espace `kyverno-exceptions`). Pourquoi restreindre à un espace, et pourquoi pas `*` ?
5. Telle que la politique `exiger-digest` est écrite (E16), une exception ne peut que la **lever entièrement** pour les pods visés. Modifie-la pour qu'une exception puisse ne lister **que certaines images** (variable `exceptions.allowedImages`), sans rien changer pour les autres conteneurs.
6. Écris `kyverno/exceptions/cnpg-operateur-sans-condense.yaml` : pods d'instance CNPG de `mediagenda-prod` seulement, l'image de l'opérateur seulement, échéance à moins de trois mois, propriétés exigées, `reportResult: skip`. Ajoute un test `kyverno test` (dossier `kyverno/tests/exiger-digest-exception/`, clé `exceptions:` du fichier de test) qui prouve : le pod d'instance avec PostgreSQL par condensé passe ; le même pod avec PostgreSQL par étiquette échoue ; un pod de l'API qui utiliserait l'image de l'opérateur échoue.
7. Écris `outils/verifier-exceptions.sh` et le job `kyverno:exceptions` (règles du contexte technique ; avertissement à 14 jours de l'échéance, échec dans le pipeline planifié). Fais-le échouer exprès (échéance à un an, `matchConditions` retirées, valideur `lucas.martin`) avant de le faire passer. Ce que la CLI `kyverno` fait d'une exception **échue** : essaie, et conclus.
8. MR, synchronisation. Vérifie dans les rapports de `mediagenda-prod` que le résultat `exiger-digest` des instances est `skip` et non plus `fail`.

*C. Rendre visible*

9. Règles d'enregistrement et alertes dans `regles/politiques-admission.yaml`, avec un test `promtool` : **`PolitiqueRefusEnRafale`** (une politique en `Deny` refuse plus de 10 fois en 15 minutes dans un espace : un contrôleur réessaie en boucle), **`PolitiqueEnEchecEnProduction`** (l'analyse de fond trouve des objets non conformes dans un espace `*-prod`), **`PolitiqueEnErreur`** (une politique ne s'évalue plus). Étiquettes `gravite`, `equipe`, `runbook_url` vers RB-261 (E23). Attention au piège : que compte réellement `execution_cause="background_scan"` ?
10. Tableau de bord `politiques-admission` (variable de source, variable d'espace) : refus à l'admission, échecs en mode `Audit` (ce que `Deny` refuserait), violations de fond, exemptions appliquées (`result="skip"`), latence p95 d'évaluation par politique.

**Critères de réussite**
- [ ] Les trois contrôleurs de Kyverno tournent avec les exceptions activées et limitées à `kyverno-exceptions` ; aucune `PolicyException` n'existe ailleurs.
- [ ] Chaque exception de `kyverno-exceptions` a une échéance future à moins de 92 jours, au moins une `matchCondition` et les propriétés `raison`, `ticket`, `valideur`.
- [ ] Les rapports de `mediagenda-prod` ne contiennent plus d'échec `exiger-digest`.
- [ ] Les trois alertes sont chargées par Prometheus ; le tableau `politiques-admission` est provisionné ; les métriques de Kyverno sont collectées.
- [ ] `outils/verifier-exceptions.sh` est sur `main` et le job `kyverno:exceptions` a réussi.

**Vérification** : `lab/bin/check 26 18`

<details><summary>Indice 1</summary>

L'image du conteneur `bootstrap-controller` d'une instance CloudNativePG n'est pas dans le `Cluster` : lis la configuration de l'opérateur (variable d'environnement de son Deployment) et la documentation de CNPG sur l'image de l'opérateur. Pour `exceptions.allowedImages`, regarde comment une `ValidatingPolicy` reçoit les images d'une exception partielle dans la documentation des `PolicyException` CEL.
</details>

<details><summary>Indice 2</summary>

Dans un fichier `kind: Test` de la CLI, les exceptions se déclarent à côté des politiques et des ressources. Pour comparer des dates en sh POSIX sans `date -d "chaîne"` (absent de BusyBox selon les formats), compare des chaînes au même format UTC (`AAAA-MM-JJTHH:MM:SSZ`) : l'ordre alphabétique est l'ordre chronologique ; `date -u -d @<secondes>` sait produire « dans 92 jours ».
</details>

<details><summary>Indice 3</summary>

Un compteur `background_scan` avance à **chaque** analyse de fond (par défaut toutes les heures) tant que l'objet reste non conforme : c'est un état déguisé en compteur. Une `increase(...[2h]) > 0` dit « encore non conforme récemment » ; un `rate` de quelques millièmes par seconde ne dit rien d'utile.
</details>

**Pour aller plus loin** (facultatif) : [PolicyException CEL](https://kyverno.io/docs/exceptions/), [rapports de politiques](https://kyverno.io/docs/policy-reports/), [métriques de Kyverno](https://kyverno.io/docs/monitoring/). Installe [Policy Reporter](https://kyverno.github.io/policy-reporter/) dans `wb-essais` le temps d'un essai : qu'apporte-t-il de plus que tes métriques (résultats par ressource, notifications) et que coûte-t-il ?

---

### M26-E19 — Falco : règles de MédiSphère et acheminement des alertes  `LAB` `★★`

> **Ticket SEC-2719** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> Les règles par défaut de Falco, c'est bien pour une démonstration. Pour nous, je veux six détections qui correspondent à **nos** applications : un shell interactif dans un conteneur applicatif, la lecture du jeton de compte de service, une écriture sous `/etc`, une connexion vers un port qui n'est pas dans la matrice des flux, un binaire lancé depuis `/tmp`, et tout `kubectl exec` en production. Le critique réveille l'astreinte, le reste arrive chez moi. Nadia exige un runbook avant la première alerte de nuit. Et pas de règle qu'on « désactive pour avoir la paix » : les exceptions s'écrivent.

**Objectifs pédagogiques**
- Écrire des règles Falco (macros, listes, conditions, sorties, priorités, étiquettes) adaptées à un parc, en réutilisant les macros des règles par défaut.
- Gérer les exceptions par listes et macros, et le bruit par le périmètre et la priorité.
- Livrer les règles par GitOps avec une validation en CI par le binaire Falco de la version du cluster.
- Acheminer : gravité, routage d'Alertmanager, Loki, runbook.

**Prérequis** : M26-E08 (Falco, falcosidekick, flux vers Alertmanager et Loki) ; M26-E07 (`plateforme/politiques`, CI) ; M21-E16 (routage d'Alertmanager, récepteurs) ; M22 (locataire `audit`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fichier des règles | `plateforme/politiques`, **`falco/regles-medisphere.yaml`** : un **fichier de valeurs** du chart dont la clé `customRules."regles-medisphere.yaml"` contient les règles ; le chart en fait la ConfigMap **`falco-rules`** (montée dans `/etc/falco/rules.d`) |
| Application | `falco` (E08) : une **troisième source**, `plateforme/politiques` (référence `politiques`), et un second `valueFiles` : `$politiques/falco/regles-medisphere.yaml` |
| Conventions | noms préfixés **`MédiSphère — `** ; une étiquette `gravite_critique` ou `gravite_avertissement` par règle ; listes `medisphere_*` et macros `medisphere_*_attendu` pour les exceptions ; **jamais** `enabled: false` ni `override` sur une règle |
| Périmètre applicatif | espaces `mediagenda-*`, `medidoc-*`, et `wb-essais` (banc d'essai) ; production : `mediagenda-prod`, `medidoc-prod` |
| Gravités | critique : jeton de compte de service lu, écriture sous `/etc`, binaire depuis un répertoire temporaire ; avertissement : shell interactif, port non prévu, exec en production |
| Ports prévus | ceux de la matrice des flux du cluster pour les applications : 53, 80, 443, 5432, 6379, 8000, 8080, 4317, 4318 |
| Gravité vers Alertmanager | champ `gravite` ajouté par la configuration de Falco (`append_output`, correspondance par étiquette) dans `plateforme/gitops`, `valeurs/falco/values.yaml` ; falcosidekick transforme **chaque** champ de sortie en étiquette d'alerte |
| Routage | `plateforme/observabilite`, `kps/values.yaml` : route des alertes de Falco avant les routes d'équipe ; critique → `astreinte@` et `securite@`, le reste → `securite@` (récepteur `securite-mail` à créer) |
| CI | `outils/valider-falco.sh` : extraction et conventions (`yq`), puis `falco -V` des règles par défaut **et** des nôtres avec le greffon `container` chargé, dans l'image officielle `falcosecurity/falco:0.45.1` (cache `dockerhub`) ; jobs `falco:conventions` et **`falco:valider`** |
| Runbook | `docs/securite/durcissement/runbooks/RB-260-alerte-falco.md` |

> ⚠️ **Attention** : chaque modification des règles redémarre les pods de Falco **un par un** : pendant ce temps, un nœud n'est pas surveillé. Pas de MR de règles pendant un incident. Les essais se font dans `wb-essais`, jamais dans un pod de production ; l'étape « exec en production » s'éprouve avec un pod **jetable** que tu crées par la chaîne normale (MR) ou en ajoutant temporairement `wb-essais` à la macro de production, jamais par un `exec` dans un pod réel.

**Travail demandé**

*A. Comprendre avant d'écrire*

1. Dans le pod Falco (`/etc/falco/falco_rules.yaml`), lis les macros `spawned_process`, `container`, `container_entrypoint`, `open_read`, `open_write`, `outbound`, et la règle « Drop and execute new binary in container ». Que vaut `outbound` pour une connexion de `10.240.x.y` vers `10.10.20.18:443` ? Quel champ donne le chemin de l'exécutable, quel champ le port de destination ?
2. Avec le remplacement de kube-proxy par Cilium (M15), une connexion à `mediagenda.mediagenda-recette:80` est traduite **au moment du `connect()`**. Quel port Falco verra-t-il ?

*B. Écrire et livrer*

3. Écris `falco/regles-medisphere.yaml` : les macros de périmètre, les listes d'exceptions (vides ou presque), les six règles (condition, sortie lisible avec espace, pod, conteneur, commande, utilisateur ; priorité ; étiquettes `medisphere`, gravité, MITRE).
4. Écris `outils/valider-falco.sh` et les deux jobs (contexte technique). Fais-le échouer exprès : une règle sans gravité, une règle avec `enabled: false`, une faute dans une condition.
5. Complète les valeurs de Falco (`append_output`) et de falcosidekick (étiquettes d'alerte, échéance des alertes) ; ajoute la source `politiques` à l'Application `falco`. MR, synchronisation, et vérifie que la ConfigMap `falco-rules` contient tes règles et que les pods ont redémarré.

*C. Éprouver dans `wb-essais`*

6. Avec un pod d'essai de `wb-essais` (celui d'E08 ou un neuf), déclenche chaque règle : shell interactif, `cat` du jeton (monte-en un exprès), `touch /etc/essai`, tentative de connexion vers un port non prévu d'une VM (`timeout 3 bash -c '</dev/tcp/10.10.20.19/2222'`), copie d'un binaire dans `/tmp` puis exécution. Retrouve chaque événement dans Loki (`{service="falco"}`, locataire `audit`) et dans Alertmanager.
7. Réglage du bruit : laisse tourner une journée. Quelles règles se déclenchent sans action de ta part (instances CNPG qui lisent leur jeton ? sondes ?) ? Traite chacune par une liste ou une macro, avec une ligne au registre des exceptions.

*D. Acheminer*

8. Route d'Alertmanager et récepteur `securite-mail` ; éprouve le routage avec `amtool config routes test` sur trois jeux d'étiquettes (critique MédiSphère, avertissement MédiSphère, règle par défaut CRITICAL sans gravité).
9. Écris **RB-260** : que signifie l'alerte, tableau des règles et de leurs explications légitimes connues, premières vérifications (Loki : Falco, Tetragon dès E20, audit de l'API), décision (légitime, exception, incident → RB-262), ce qu'il ne faut **pas** faire (supprimer le pod), escalade.

**Critères de réussite**
- [ ] Un pod Falco prêt par nœud ; la ConfigMap `falco-rules` contient six règles « MédiSphère — » ; l'Application `falco` lit `plateforme/politiques`.
- [ ] Le dernier pipeline de `main` de `plateforme/politiques` a passé `falco:valider`.
- [ ] Loki (locataire `audit`) contient des événements de règles MédiSphère des sept derniers jours ; au moins une alerte `AlerteFalco` est arrivée dans Mailpit.
- [ ] RB-260 est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 26 19`

<details><summary>Indice 1</summary>

`pmatch` compare un chemin à une liste de préfixes de chemins (`fd.name pmatch (ma_liste)`). Pour une connexion, `fd.sport` est le port du **serveur**, même côté client. Une règle peut réutiliser `container_entrypoint` : un processus lancé par `kubectl exec` a pour parent le runtime, comme le processus principal, qui, lui, a le PID 1 de son espace (`proc.vpid`).
</details>

<details><summary>Indice 2</summary>

Une écriture refusée par un système de fichiers en lecture seule est **aussi** un fait intéressant : la macro `open_write` ne retient que les ouvertures réussies (`fd.num>=0`) ; regarde `open_file_failed` et écris ta propre condition. Pour valider hors cluster, `falco -V` exige le greffon `container` si les règles par défaut sont chargées : `-o 'load_plugins[]=container'`.
</details>

<details><summary>Indice 3</summary>

Si l'étiquette `gravite` reste la même pour toutes tes alertes : falcosidekick applique ses `extralabels` **après** les champs de sortie, et E08 en posait une. Si Alertmanager ne reçoit rien du tout : relis le chemin d'API utilisé (E08) et la politique d'entrée d'Alertmanager.
</details>

**Pour aller plus loin** (facultatif) : [règles Falco](https://falco.org/docs/concepts/rules/), [champs](https://falco.org/docs/reference/rules/supported-fields/), [exceptions et surcharges](https://falco.org/docs/concepts/rules/overriding/), [falcosidekick](https://github.com/falcosecurity/falcosidekick). Le greffon `k8saudit` de Falco lit le journal d'audit de l'API : compare-le à la règle « exec en production » (qui sait QUI, qui sait QUOI).

---

### M26-E20 — Tetragon : observer processus, fichiers et réseau  `LAB` `★★★`

> **Ticket SEC-2720** — *De : Sophie Laurent*
> Falco me dit qu'un binaire a été lancé depuis `/tmp`. Très bien : mais qui l'a déposé, quel processus l'a lancé, à quoi s'est-il connecté ensuite ? Je veux l'arbre complet, au niveau du noyau, pour nos applications, gardé un an avec le reste de l'audit. Tetragon le fait, et il saura bloquer plus tard (on verra au palier 3). Pour l'instant : observer, sans bloquer, sans noyer Loki.

**Objectifs pédagogiques**
- Installer Tetragon (agent eBPF par nœud) à côté de Cilium et comprendre ce qu'il observe sans politique (exécutions, fins de processus).
- Écrire des `TracingPolicy` sur des fonctions du noyau (kprobes) avec arguments et sélecteurs, et en mesurer le coût.
- Filtrer à la source ce qui part vers les journaux (listes d'autorisation et de refus de l'export).
- Acheminer les événements vers Loki (locataire `audit`) et les corréler avec Falco.

**Prérequis** : M26-E19 (règles Falco, Loki `audit`) ; M26-E17 (VAP `hostPath` : clé `tetragon`) ; M26-E06 (exceptions Pod Security) ; M22-E03 à E09 (Alloy, `config.alloy`, locataires).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `cilium/tetragon` **1.7.1** (`https://helm.cilium.io`), recopié dans Harbor par `plateforme/charts-miroir` ; images `quay.io/cilium/tetragon`, `tetragon-operator`, `hubble-export-stdout` par le cache **`quay`** de Harbor |
| Application | **`tetragon`** (`plateforme/gitops`, `plateforme/tetragon.yaml`, valeurs `valeurs/tetragon/values.yaml`), espace **`tetragon`** (`plateforme/k8s/espaces/tetragon.yaml`, Pod Security `privileged`, exception écrite) |
| Politiques | `plateforme/politiques`, dossier **`tetragon/`** (avec son `kustomization.yaml`), livrées par l'Application `politiques` : **`observer-exec`** (exécution d'un fichier situé sous `/tmp`, `/var/tmp`, `/dev/shm` : fonction `security_bprm_check`), **`fichiers-sensibles`** (lecture ou écriture de `/etc/shadow`, `/etc/gshadow`, `/etc/sudoers`, `/root/.ssh/`, jetons de compte de service : fonction `security_file_permission`), **`connexions-sortantes`** (connexions TCP vers une destination hors des pods `10.240.0.0/16`, des Services `10.96.0.0/16` et de la boucle locale : fonction `tcp_connect`) ; toutes en **observation** (aucune action de blocage) |
| Export | sortie JSON de l'agent, conteneur **`export-stdout`** du DaemonSet ; ce qui part : exécutions et fins de processus des espaces `mediagenda-*`, `medidoc-*`, `wb-essais` ; événements de **nos trois** politiques partout ; refus par défaut du chart conservés (sondes de santé, hôte, `cilium`, `kube-system`) |
| Journaux | Alloy (DaemonSet de l'espace `journaux`, `plateforme/observabilite`, `alloy/config.alloy`) : les lignes de `tetragon/export-stdout` partent dans le locataire **`audit`** avec l'étiquette **`service="tetragon"`**, et **plus** dans `plateforme` |
| Checks | `wb-checks-securite` étendue aux objets `cilium.io` de Tetragon (`tracingpolicies`, `tracingpoliciesnamespaced`, `podinfo`) |
| CLI | `tetra` (dans le conteneur `tetragon` des pods : `kubectl exec -n tetragon ds/tetragon -c tetragon -- tetra …`) |

> ⚠️ **Attention** : une kprobe s'exécute **dans le noyau, à chaque appel** de la fonction visée, sur tous les nœuds, y compris les nœuds de contrôle. `security_file_permission` est appelée à chaque `read()`/`write()` du nœud entier : un sélecteur large (`Prefix: /`) multiplie la charge et le volume. Installe d'abord sans politique, mesure (CPU, mémoire, débit d'événements), ajoute une politique à la fois, remesure. Retour arrière d'une politique : la retirer de `tetragon/kustomization.yaml` (MR) ; en urgence `kubectl delete tracingpolicy <nom>` (l'agent décharge la sonde aussitôt). Pas d'action `Sigkill` ou `Override` dans cet exercice.

**Travail demandé**

*A. Installer et regarder sans politique*

1. Ajoute le chart à `plateforme/charts-miroir`, rends-le avec tes valeurs et inspecte : DaemonSet et tolérances, `hostNetwork`, montages de l'hôte (comparés à la clé `tetragon` de la ConfigMap d'E17), conteneurs (`tetragon`, `export-stdout`), images, ServiceMonitor.
2. Écris l'espace, les valeurs (images, capacités des processus dans les événements, métriques), l'Application, la clé de l'AppProject ; MR, synchronisation. Un pod par nœud.
3. Dans un pod de `wb-essais`, lance quelques commandes, puis observe en direct :
   ```
   admin@adm01:~$ kubectl get pod -n wb-essais <POD-ESSAI> -o wide          # sur quel nœud ?
   admin@adm01:~$ kubectl exec -n tetragon <POD-TETRAGON-DU-MÊME-NŒUD> -c tetragon -- \
       tetra getevents -o compact --namespace wb-essais
   ```
   (`tetra getevents` interroge l'agent **local** : chaque nœud ne voit que ses processus.) Que contient un événement `process_exec` (binaire, arguments, parent, pod, étiquettes, capacités) ? Mesure le volume brut de la sortie sur une minute pour tout le cluster (`kubectl logs -n tetragon <pod> -c export-stdout --since=1m | wc -l`, par nœud).

*B. Filtrer, puis écrire les politiques*

4. Écris `exportAllowList` (et garde `exportDenyList`) : exécutions des seuls espaces applicatifs et de `wb-essais`, événements de nos politiques partout. Remesure le volume.
5. Écris les trois `TracingPolicy`. Pour chacune : la fonction du noyau et pourquoi celle-là (et pas l'appel système), le type des arguments (`linux_binprm`, `file` et `int`, `sock`), les opérateurs de sélection (`Prefix`, `NotDAddr`), le chemin vu par le noyau dans un conteneur. Pour `fichiers-sensibles` : pourquoi faut-il **deux** préfixes pour les jetons (`/var/run/…` et `/run/…`), et pourquoi un `rateLimit` ?
6. Ajoute-les une par une (MR), vérifie qu'elles sont chargées (`tetra tracingpolicy list`) et éprouve chacune dans `wb-essais` : exécution d'un binaire copié dans `/tmp`, lecture du jeton, connexion vers une VM du socle (`10.10.20.18:443`).

*C. Acheminer et corréler*

7. Modifie `alloy/config.alloy` (MR de `plateforme/observabilite`) : locataire `audit` et étiquette `service="tetragon"` pour les lignes de `tetragon/export-stdout`. Vérifie dans les deux locataires (`audit` : présent ; `plateforme` : absent depuis la synchronisation).
8. Requêtes LogQL dans `plateforme/observabilite`, `requetes/tetragon-falco.logql` : arbre des exécutions d'un pod, exécutions depuis `/tmp`, accès aux fichiers sensibles par fichier et binaire, connexions sortantes par espace et destination, et une requête qui met côte à côte, pour un même pod, l'événement Falco et l'événement Tetragon de l'étape 6.
9. Dans `~/m26/e20/comparaison.md` : ce que Falco voit et Tetragon pas, et l'inverse (arbre des processus, enrichissement Kubernetes, moment d'observation, capacité d'agir), le coût mesuré de chacun (mémoire et CPU par nœud), et ce que tu gardes des deux. Ajoute à RB-260 la requête Tetragon de l'arbre des processus.

**Critères de réussite**
- [ ] Un pod Tetragon prêt par nœud ; les trois `TracingPolicy` existent ; les métriques de Tetragon sont collectées.
- [ ] Le locataire `audit` reçoit des événements `service="tetragon"`, dont au moins un de la politique `observer-exec` dans les sept derniers jours ; le locataire `plateforme` n'en reçoit plus.
- [ ] `requetes/tetragon-falco.logql` est sur `main` de `plateforme/observabilite`.

**Vérification** : `lab/bin/check 26 20`

<details><summary>Indice 1</summary>

Une ligne de `exportAllowList` est un filtre JSON ; ses champs s'additionnent (« et »), les lignes s'ajoutent (« ou »). Les noms de champs sont ceux du protocole de Tetragon en minuscules avec soulignés : `event_set`, `namespace_regex`, `policy_names`.
</details>

<details><summary>Indice 2</summary>

Les exemples officiels de `TracingPolicy` du dépôt de Tetragon (`examples/tracingpolicy/` : `security_bprm_check.yaml`, `filename_monitoring_filtered.yaml`, `tcp-connect-only-private-addrs.yaml`) donnent la forme exacte des arguments et des sélecteurs pour la version 1.7. Le chemin d'un fichier est résolu par rapport à la racine du **processus**.
</details>

<details><summary>Indice 3</summary>

Dans Alloy, une règle de `discovery.relabel` peut combiner deux étiquettes source avec un séparateur (`source_labels = [espace, conteneur]`, `separator = "/"`, `regex = "tetragon/export-stdout"`). Dans LogQL, `| json` aplatit les objets (`process_kprobe_policy_name`) mais pas les tableaux : `| json chemin="process_kprobe.args[0]…"`.
</details>

**Pour aller plus loin** (facultatif) : [documentation de Tetragon](https://tetragon.io/docs/), [hooks et types d'arguments](https://tetragon.io/docs/concepts/tracing-policy/), [filtres d'export](https://tetragon.io/docs/concepts/events/#filtering-events). Essaie une `TracingPolicyNamespaced` limitée à `wb-essais` : que change-t-elle au coût, à la sécurité (qui peut en écrire une) ?

---

### M26-E21 — Des charges sûres par construction  `LAB` `★★`

> **Ticket PLAT-2721** — *De : Karim Benali* — *Copie : Julien Petit*
> Pod Security `restricted` est en place, les politiques Kyverno aussi. Mais « ça passe l'admission » ne veut pas dire « c'est sûr » : certains réglages ne sont pas contrôlés, d'autres passent par une valeur par défaut que personne n'a écrite. Je veux une norme « charge sûre » écrite, un outil qui mesure l'écart **en service** pod par pod, et MédiAgenda et MédiDoc à zéro écart. Tout par MR dans les dépôts des équipes, avec Julien.

**Objectifs pédagogiques**
- Écrire une norme de sécurité des charges vérifiable, critère par critère, et savoir ce qui l'impose.
- Mesurer les charges **en service** (et non les manifestes) et distinguer valeur écrite et valeur par défaut.
- Corriger dans les bons dépôts (chart, bibliothèque de gabarits, overlays, Kustomize) sans régression ni dérive GitOps.

**Prérequis** : M26-E06 (Pod Security `restricted` imposé), M26-E16 et E18 (politiques Kyverno, exceptions) ; M17 (chart `mediagenda`, bibliothèque `medisphere-commun`) ; M19-E33 (`medidoc/deploiement`) ; M20 (promotion par MR, prod synchronisée à la main).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Critère | Exigence |
|---|---|
| C1 | `runAsNonRoot: true` (pod ou conteneur) et UID/GID numériques écrits |
| C2 | `allowPrivilegeEscalation: false` |
| C3 | `readOnlyRootFilesystem: true` ; écritures dans des `emptyDir` **bornés** (`sizeLimit`) |
| C4 | `capabilities.drop` contient `ALL`, aucun ajout |
| C5 | seccomp `RuntimeDefault` (ou `Localhost`) ; AppArmor `RuntimeDefault` écrit (champ `securityContext.appArmorProfile`, GA depuis 1.30) |
| C6 | aucun jeton de compte de service **monté**, sauf besoin inscrit au registre des exceptions |
| C7 | images par condensé hors `dev` |
| C8 | `requests` CPU et mémoire, `limits` mémoire (pas de limite CPU : décision M21) |

| Élément | Valeur |
|---|---|
| Périmètre | pods des espaces `mediagenda-*` et `medidoc-*`, conteneurs d'initialisation compris |
| Norme | `docs/securite/durcissement/charges-sures.md` (plateforme/medisphere) |
| Outil | `plateforme/k8s`, `outils/audit-charges-sures.sh` (lecture seule ; une ligne par écart « espace, pod, conteneur, critère » ; code de sortie 1 s'il en reste) |
| Dépôts | `mediagenda/chart` (gabarits `medisphere-commun.securite.*` du M17, valeurs), `mediagenda/deploiement` (overlays, composant `dependances` : Valkey, Cluster CNPG), `medidoc/deploiement` |
| Exception connue | instances CloudNativePG : le gestionnaire d'instance parle à l'API (C6) |

> ⚠️ **Attention** : changer le contexte de sécurité d'un pod le **recrée** ; changer `imageName` d'un `Cluster` CloudNativePG déclenche une mise à jour progressive des instances (réplicas puis bascule du primaire). Recette d'abord, prod ensuite par la synchronisation manuelle, hors heures de pointe, Julien prévenu. Un UID explicite différent de celui de l'image peut rendre des fichiers illisibles : vérifie la ligne `USER` de chaque image avant de l'écrire. Retour arrière : `git revert` de la MR (chart : version précédente dans l'overlay).

**Travail demandé**

1. **Mesurer.** Écris `outils/audit-charges-sures.sh` : un filtre `jq` sur `kubectl get pods -A -o json` qui sort une ligne par écart, avec un bilan par critère. Pour C6, regarde le **résultat** (un volume projeté `serviceAccountToken` injecté par l'admission) plutôt que le champ `automountServiceAccountToken` : pourquoi ? Lance-le et classe les écarts : chart, overlay, composant, opérateur, image.
2. **Lire ce qui est réellement appliqué.** Pour un pod de MédiAgenda, compare le manifeste du dépôt et le pod en service (`kubectl get pod … -o yaml`) : quels champs ont été ajoutés par l'admission (Kyverno `seccomp-par-defaut`, MAP d'E17, `ServiceAccount`) ? Quels critères ne sont tenus que par une valeur par défaut que personne n'a écrite ?
3. **Écrire la norme** `charges-sures.md` (tableau critère, exigence, pourquoi, où c'est imposé ; ce qui n'est pas dans la norme et pourquoi ; renvoi au registre des exceptions).
4. **Corriger MédiAgenda** : gabarits de sécurité de `medisphere-commun` (UID/GID explicites, AppArmor), `/tmp` borné, nouvelle version du chart ; dans `mediagenda/deploiement`, toutes les images de la prod par condensé (Valkey du composant `dependances`, `imageName` du `Cluster` CNPG : le transformateur `images` de Kustomize les connaît-il tous les deux ?). MR relues par Julien, promotion dev → recette → prod.
5. **Corriger MédiDoc** : lis d'abord le code (`apps/medidoc`) : l'application écrit-elle des fichiers temporaires ? N'ajoute que ce qui est nécessaire.
6. **Prouver.** L'outil ne sort plus aucun écart ; les rapports de politiques de ces espaces n'ont aucun échec ; un `kubectl apply --dry-run=server` du rendu du chart dans un espace `restricted` ne produit aucun avertissement.

**Critères de réussite**
- [ ] Aucun écart à la norme pour les pods en service de `mediagenda-*` et `medidoc-*` (hors exceptions inscrites).
- [ ] Aucun résultat `fail` dans les `PolicyReport` de ces espaces ; tous sont en Pod Security `enforce: restricted`.
- [ ] `charges-sures.md` est sur `main` de `plateforme/medisphere`, `outils/audit-charges-sures.sh` sur `main` de `plateforme/k8s`.

**Vérification** : `lab/bin/check 26 21`

<details><summary>Indice 1</summary>

En `jq`, une fonction (`def ecarts($p; $c): …;`) qui renvoie un tableau de critères manqués par conteneur, appliquée à `initContainers` et `containers`, rend le filtre lisible. `.securityContext.runAsNonRoot // $pod.securityContext.runAsNonRoot` gère le « pod ou conteneur ».
</details>

<details><summary>Indice 2</summary>

Le transformateur `images` de Kustomize ne touche que les champs d'image qu'il connaît (conteneurs des types standard) ; `spec.imageName` d'un `Cluster` CNPG demande un `patch` (ou une configuration `images` étendue). Le sous-chart `valkey` 0.12.0 accepte un condensé dans `image.tag` (`9.1.2@sha256:…`) : lis son gabarit d'image.
</details>

**Pour aller plus loin** (facultatif) : [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/), [AppArmor dans Kubernetes](https://kubernetes.io/docs/tutorials/security/apparmor/), [profils seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/). Lance `kubescape scan workload` sur MédiAgenda (E05) et compare ses constats à ta norme : qu'a-t-il de plus, que signale-t-il à tort ?

---

### M26-E22 — Revue : les manifestes et le Dockerfile du stagiaire  `REV` `★★`

> **Ticket PLAT-2722** — *De : Karim Benali*
> Lucas a écrit MédiInventaire, un petit outil pour Sophie : il liste les images qui tournent dans le cluster et affiche leurs vulnérabilités d'après Harbor. Il a ouvert une MR pour le déployer. Fais la revue avant que quelqu'un clique sur « Fusionner » : j'ai vu passer le mot `privileged`. Propose une version corrigée à côté, et explique-lui sans le décourager.

**Objectifs pédagogiques**
- Relire un Dockerfile et des manifestes Kubernetes avec une grille de sécurité (identité, privilèges, accès à l'hôte, secrets, réseau, droits, chaîne d'approvisionnement, ressources).
- Mesurer la conséquence concrète de chaque défaut et hiérarchiser.
- Proposer une version corrigée qui fait **la même chose** avec le moindre privilège.

**Prérequis** : M26-E21 (norme « charge sûre ») ; M12 (images, `USER` numérique), M13 (Harbor, signatures), M25 (OpenBao, External Secrets) ; M15 (politiques Cilium).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers fournis : [`ressources/M26-E22/`](../ressources/M26-E22/) : `MR-lucas.md` (description de la MR), `Dockerfile`, `values.yaml`, `manifestes/` (`deployment.yaml`, `service.yaml`, `rbac.yaml`, `networkpolicy.yaml`).
- Ce que fait l'outil : lire la liste des images en service, interroger l'API de Harbor (robot `robot$plateforme+inventaire`), servir une page HTML sur le port 8080.
- Conventions de la version corrigée : espace `inventaire` (créé par `plateforme/k8s`, Pod Security `restricted`), UID **10004** (les 10001-10003 sont pris par MédiAgenda, MédiNotif et MédiAnnuaire), jeton Harbor dans OpenBao (`kv/plateforme/inventaire/harbor`), lu par External Secrets.
- Travail dans `~/m26/e22/` : `revue.md` et un dossier **`corrige/`** (Dockerfile, `values.yaml`, manifestes corrigés ; ajoute ce qui manque).

**Travail demandé**
1. Lis la MR et les fichiers. Relève **au moins douze** défauts dans `~/m26/e22/revue.md`, chacun avec : le fichier et la ligne, le défaut, la conséquence concrète (ce qu'un attaquant ou une panne en ferait), la correction, une gravité (bloquant, majeur, mineur).
2. Distingue les **erreurs** (le résultat contredit une règle écrite ou l'intention) des **choix** à discuter avec Lucas.
3. Écris la version corrigée dans `~/m26/e22/corrige/` : elle fait la même chose (liste des images et de leurs vulnérabilités), sans socket de runtime, sans privilège, sans accès à l'hôte, avec un rôle minimal, sans secret en clair, avec une politique réseau qui ne laisse sortir que le nécessaire. Valide-la : `kubectl apply --dry-run=server` dans un espace `restricted` (à blanc), `kyverno apply` avec les politiques de `plateforme/politiques`.
4. Le jeton de Lucas a été écrit dans Git et dans une image poussée. Que fais-tu, dans quel ordre (RB-250) ?
5. Rédige le commentaire de revue (ton bienveillant, trois points prioritaires, renvoi vers ta version).

**Critères de réussite**
- [ ] `revue.md` relève au moins douze défauts argumentés.
- [ ] La version corrigée : aucun `privileged`, `hostNetwork`, `hostPath` ni capacité ajoutée ; image ni `latest` ni d'un registre externe ; processus non root ; ressources ; aucun secret en clair (Dockerfile ni manifestes) ; aucun rôle à `*` ; aucune politique réseau « tout autoriser » ; Service interne ; pas l'espace `default`.

**Vérification** : `lab/bin/check 26 22`

<details><summary>Indice 1</summary>

Grille : *qui* tourne (UID, capacités, privilèges) ; *où* (hôte : réseau, PID, fichiers, sockets) ; *avec quels droits* (RBAC, jeton) ; *quels secrets* et où ils finissent (Git, image, variables) ; *qui parle à qui* (Service, politique réseau) ; *d'où vient* l'image (base, étiquette, paquets, téléchargements) ; *combien* elle consomme.
</details>

<details><summary>Indice 2</summary>

Pour connaître les images réellement exécutées, l'API suffit : `status.containerStatuses[].imageID` donne le condensé. Monter le socket de containerd, c'est donner à un pod la possibilité de lancer n'importe quel conteneur sur le nœud.
</details>

---

### M26-E23 — Registre des exceptions et procédure de dérogation  `RED` `★★`

> **Ticket SEC-2723** — *De : Sophie Laurent*
> L'auditeur HDS posera la question telle quelle : « montrez-moi vos écarts acceptés, qui les a acceptés, pourquoi, jusqu'à quand, et comment vous savez qu'ils n'ont pas grossi ». Aujourd'hui, la réponse est dans des fichiers YAML, des commentaires et la mémoire de Karim. Je veux un registre unique, et une procédure que tout le monde suit, du stagiaire à moi.

**Objectifs pédagogiques**
- Tenir un registre d'exceptions qui serve à l'audit et à l'exploitation : périmètre, justification, risque résiduel, compensation, validation, échéance.
- Écrire une procédure de dérogation qui couvre tous les mécanismes du module, et la relier au code.

**Prérequis** : M26-E10 (`durcissement_exceptions`), M26-E06 (exceptions Pod Security), M26-E17 à E21 (VAP, `PolicyException`, listes Falco, exceptions de la norme « charge sûre »).
**Durée indicative** : 1 h 30.

**Livrables** (dans `plateforme/medisphere`, `docs/securite/durcissement/`) :
- `exceptions.md` : le registre ;
- `runbooks/RB-261-derogation.md` : la procédure.

**Contraintes**
- Registre : une ligne par exception **en vigueur** (identifiant unique jamais réutilisé, règle exacte, périmètre, justification, risque résiduel, compensation, fichier où elle est codée, valideur, date de revue) et une section des exceptions **closes ou refusées** ; il reprend **toutes** les exceptions déjà codées dans le module (rôle `durcissement`, espaces `privileged`, liste `hostPath`, `PolicyException`, listes Falco, norme « charge sûre »).
- Procédure : qui demande et avec quoi, qui valide (et en son absence), comment c'est codé pour **chaque** mécanisme (tableau), ce que la CI vérifie, comment on vérifie après fusion, l'échéance et le renouvellement, le cas de l'urgence, le retrait.
- Une revue périodique du registre (fréquence, participants, ce qu'on compare au code, indicateurs pour le comité sécurité).
- Aucune exception sans échéance ; aucune exception d'une durée supérieure à un an.

Exercice auto-évalué : relis ton registre et ta procédure avec la grille du corrigé.
