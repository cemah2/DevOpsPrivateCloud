# Module 17 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Comme au palier 1 : [`fichiers/M17-E12/chart/`](fichiers/M17-E12/chart/) est le projet `mediagenda/chart` complet à la fin du palier (E06, E07 et E12 y ont chacun leur part) ; [`fichiers/M17-E09/deploiement/`](fichiers/M17-E09/deploiement/) est le projet `mediagenda/deploiement` complet (il remplace celui de E04) ; [`fichiers/M17-E10/k8s/`](fichiers/M17-E10/k8s/) est l'extrait Helmfile de `plateforme/k8s` ; [`fichiers/M17-E08/`](fichiers/M17-E08/) contient les scripts de publication et la page du registre ; [`fichiers/M17-E11/medidoc/`](fichiers/M17-E11/medidoc/) le chart MédiDoc corrigé.

**Ce qui a été vérifié, et comment** (en plus du palier 1).
- *Chart* : `helm dependency update` réel (Valkey 0.12.0 depuis `https://valkey.io/valkey-helm/`, bibliothèque `file://`), `helm lint --strict`, rendus des trois profils validés par kubeconform (schémas 1.36 + catalogue de CRD), 37 tests helm-unittest, `ct lint` 3.15 dans son image (Helm 3.16 embarqué, puis Helm 4.3 monté) avec refus d'une modification sans montée de version, `helm package` et contenu de l'archive (tests unitaires exclus, `templates/tests/` inclus).
- *Publication* : `helm push` vers un registre OCI local (CNCF Distribution), signature `cosign sign --key … --signing-config <configuration sans service>` (Cosign **3.1.3**, méthode du M13-E07 : bundle sans entrée de journal) et `cosign verify --insecure-ignore-tlog=true` réussies, `helm pull` par digest, échec de `helm pull --verify` (`failed to fetch provenance … .prov`). `outils/rendre-base.sh` a été exécuté contre ce registre : rendu écrit, mode `--verifier` vert, puis rouge après altération du rendu.
- *Kustomize* : tous les overlays de E09 construits par Kustomize 5.8.2 et validés par kubeconform ; comportements observés cités tels quels (référence non réécrite avec `helmCharts`, voir E09).
- *Helmfile* : `helmfile -e par1 list` et `template` sur la structure de E10 (dépôts réels, valeurs fictives) ; refus de `helmfile.yaml` + `helmfile.d/` constaté.
- *Scripts* : ShellCheck 0.11 et `bash -n`.

**Non rejoué sur un cluster** : adoption par `--take-ownership`, ordre réel des hooks et des événements, `ct install`, comportement de Harbor (immuabilité, politique Cosign appliquée aux charts, affichage des accessoires d'un artefact Helm), `helmfile diff` sur les vraies releases des modules 14 à 16, création de la production. Signalés « ⚠️ À vérifier sur ton lab ».

---

### M17-E06 — Dépendances et sous-charts

**Solution**

Fichiers : [`Chart.yaml`](fichiers/M17-E12/chart/charts/mediagenda/Chart.yaml), [`values.yaml`](fichiers/M17-E12/chart/charts/mediagenda/values.yaml) (blocs `postgresql`, `valkey`, `externalValkey`, `valkeyImporte`), [`cnpg-cluster.yaml`](fichiers/M17-E12/chart/charts/mediagenda/templates/cnpg-cluster.yaml), [`networkpolicy.yaml`](fichiers/M17-E12/chart/charts/mediagenda/templates/networkpolicy.yaml) et [`ciliumnetworkpolicy.yaml`](fichiers/M17-E12/chart/charts/mediagenda/templates/ciliumnetworkpolicy.yaml) (parties conditionnelles), [`_helpers.tpl`](fichiers/M17-E12/chart/charts/mediagenda/templates/_helpers.tpl) (`mediagenda.dbSecret`, `mediagenda.valkeyUrl`, `mediagenda.cnpgName`, vérification croisée), bibliothèque [`medisphere-commun`](fichiers/M17-E12/chart/charts/medisphere-commun/), [`.gitignore`](fichiers/M17-E12/chart/.gitignore).

1. **Lecture.** `helm dependency update` résout les contraintes de version de `Chart.yaml` auprès des dépôts, télécharge les archives dans `charts/` et **réécrit** `Chart.lock` (versions exactes, digest de l'ensemble) ; `helm dependency build` reconstruit `charts/` **depuis** `Chart.lock`, sans rien résoudre : c'est la commande des pipelines (reproductible). On versionne `Chart.yaml` et `Chart.lock`, jamais `charts/*.tgz`.
2. **Bibliothèque.** `type: library`, des gabarits `_commun.tpl` qui lisent `.Values.medisphere.*` **du parent** (on leur passe `.`). Le rendu avant/après la migration est identique (vérifié par `diff` des deux `helm template`).
3. **Dépendances.**
   ```yaml
   dependencies:
     - name: medisphere-commun
       version: 0.1.0
       repository: file://../medisphere-commun
     - name: valkey
       version: 0.12.0
       repository: https://valkey.io/valkey-helm/      # oci://registry.par1.medisphere.internal/charts après E08
       condition: valkey.enabled
       import-values:
         - child: service
           parent: valkeyImporte
   ```
   `import-values` sous la forme `child/parent` recopie `valkey.service` (calculé par le sous-chart) dans `.Values.valkeyImporte` du parent : l'URL `redis://<release>-valkey:{{ .Values.valkeyImporte.port }}/0` suit le port du sous-chart. Quand le sous-chart est désactivé, l'import ne se fait pas et la valeur par défaut `valkeyImporte.port: 6379` s'applique.
   ```
   admin@adm01:~/src/mediagenda-chart$ helm dependency update charts/mediagenda
   Saving 2 charts
   Downloading valkey from repo https://valkey.io/valkey-helm/
   admin@adm01:~/src/mediagenda-chart$ git add charts/mediagenda/Chart.lock && git status --ignored | grep tgz
   ```
4. **Valeurs du sous-chart.** Sous la clé `valkey:` du parent : `image.registry: registry.par1.medisphere.internal/dockerhub` (la VAP du M14 refuse `docker.io`), `imagePullSecrets: [harbor-pull]`, ressources. Piège réel rencontré : le chart Valkey attend une **liste de noms** (`- harbor-pull`), pas d'objets `{name: …}` ; avec un objet, il rend `name: "map[name:harbor-pull]"` sans erreur. Seul un `helm template` relu le montre. Ses pods sont déjà conformes à `restricted` (utilisateur 1000, `seccompProfile`, capacités retirées, conteneur d'initialisation compris).
5. **Base CNPG.** Rendue si `postgresql.cnpg.enabled` ; `helm.sh/resource-policy: keep` empêche `helm uninstall` (et `ct`) de la supprimer ; `inheritedMetadata` propage les étiquettes MédiSphère aux pods et PVC ; anti-affinité dès deux instances. Le Secret vient de CNPG (`<cluster>-app`) : rien de secret dans le chart. Politiques : clients (pods de la release) → 5432, réplication entre instances (5432, 8000), opérateur (`cnpg-system`) → 8000, sortie DNS, et une CiliumNetworkPolicy `toEntities: [kube-apiserver]` (le gestionnaire d'instance lit et écrit dans l'API). ⚠️ À vérifier sur ton lab : la liste exacte des flux qu'exige CNPG 1.30 (compare avec les politiques de recette du M16).
6. **Profils.**
   ```
   admin@adm01:~/src/mediagenda-chart$ helm template mediagenda charts/mediagenda -n mediagenda-recette --set medisphere.environnement=recette | grep -E '^kind' | sort | uniq -c
   admin@adm01:~/src/mediagenda-chart$ helm template mediagenda charts/mediagenda -n mediagenda-dev -f ~/m17/e06/dev.yaml | kubeconform -summary -kubernetes-version 1.36.0 \
       -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
   Summary: 18 resources found in 1 file - Valid: 18, Invalid: 0, Errors: 0, Skipped: 0
   ```
   [`dev.yaml`](fichiers/M17-E06/dev.yaml) : environnement `dev`, une réplique, base et Valkey intégrés. Recette : NetworkPolicy, PDB, ServiceAccount, ConfigMap, Service, Deployment, CiliumNetworkPolicy, HTTPRoute (+ hooks en E12). Dev : en plus le `Cluster`, le Deployment et le Service `mediagenda-valkey`, son ServiceAccount, sa ConfigMap de scripts, les politiques de la base et de Valkey.
7. **Reprise.**
   ```
   admin@adm01:~/src/mediagenda-chart$ helm upgrade mediagenda charts/mediagenda -n mediagenda-dev -f ~/m17/e06/dev.yaml --wait
   Error: UPGRADE FAILED: Unable to continue with update: Cluster "mediagenda-db" in namespace "mediagenda-dev" exists and cannot be imported into the current release: invalid ownership metadata; label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm"; annotation validation error: missing key "meta.helm.sh/release-name": must be set to "mediagenda"; …
   admin@adm01:~/src/mediagenda-chart$ helm upgrade mediagenda charts/mediagenda -n mediagenda-dev -f ~/m17/e06/dev.yaml --dry-run=server --take-ownership | grep -c '^kind'
   admin@adm01:~/src/mediagenda-chart$ helm upgrade mediagenda charts/mediagenda -n mediagenda-dev -f ~/m17/e06/dev.yaml --take-ownership --wait --timeout 10m
   admin@adm01:~/src/mediagenda-chart$ kubectl -n mediagenda-dev get cluster.postgresql.cnpg.io mediagenda-db -o jsonpath='{.metadata.annotations}{"\n"}{.metadata.creationTimestamp}{"\n"}'
   ```
   (Message d'erreur reconstitué depuis le code de Helm : ⚠️ à vérifier sur ton lab.) `--take-ownership` pose les annotations et l'étiquette de propriété sur tout objet du rendu qui existe déjà ; le `creationTimestamp` du `Cluster` ne change pas. Seul le `Cluster` est concerné ici : les autres noms rendus (`mediagenda-valkey`, politiques `mediagenda-db`…) n'existaient pas.
8. **Bascule et ménage.** L'URL de Valkey a changé par la montée elle-même (`redis://mediagenda-valkey:6379/0`) ; une fois les pods de l'API renouvelés et prêts :
   ```
   admin@adm01:~$ kubectl -n mediagenda-dev delete statefulset/valkey service/valkey networkpolicy/dev-base-provisoire \
       networkpolicy/dev-valkey-provisoire ciliumnetworkpolicy/dev-base-provisoire-api-kubernetes
   admin@adm01:~$ curl -fsS https://mediagenda-dev.apps.par1.medisphere.internal/pret
   ```

**Explications**

- **`condition` contre `tags`.** `condition: valkey.enabled` lit une valeur booléenne (du parent) ; `tags` active des groupes de dépendances d'un coup. Une `condition` l'emporte sur les `tags`.
- **Ce que la bibliothèque apporte.** Les règles MédiSphère (étiquettes d'organisation, contexte `restricted`, image par digest) écrites **une fois** : le chart MédiDoc (E11) et ceux des autres équipes les reprendront en déclarant la même dépendance, publiée dans `charts` à son tour.
- **Données hors du cycle de vie.** La politique `keep` fait de la base un objet **orphelin** après `helm uninstall` : Helm ne la supprime pas et ne la gère plus. Une réinstallation la reprendra… à condition de passer `--take-ownership`. C'est voulu : on ne perd jamais des données par une commande d'application. En production, MédiSphère va plus loin et sort la base du paquet (E09, ADR-0170).
- **Premier démarrage.** À un `helm install` sur un espace vide avec base intégrée, l'API démarre avant que CNPG ait créé le Secret `mediagenda-db-app` : les pods restent en `CreateContainerConfigError` quelques minutes, puis démarrent tout seuls quand le Secret apparaît (kubelet réessaie). Ce n'est pas une erreur, mais `--wait` doit avoir un délai suffisant (10 min).

**Alternatives**

- Sous-chart PostgreSQL « tout-en-un » : écarté, MédiSphère a choisi l'opérateur CNPG (M16), et une base n'est pas un détail d'empaquetage.
- `alias` pour installer deux fois la même dépendance (deux Valkey) : pas utile ici.
- Bibliothèque publiée dans Harbor plutôt que `file://` : nécessaire dès qu'un **autre** projet l'utilise (chart MédiDoc).

**Pièges classiques**

- `helm dependency update` en CI : la résolution peut changer de version mineure entre deux pipelines (contraintes `~`, `^`) ; toujours `build` depuis `Chart.lock`.
- Versionner `charts/*.tgz` : diffs binaires, versions qui divergent du verrou.
- Politique réseau qui ne vise que `app.kubernetes.io/name: valkey` : elle s'applique aussi au StatefulSet `valkey` provisoire (ou de recette) ; vise aussi `app.kubernetes.io/instance`.
- `--take-ownership` lancé dans le mauvais espace, ou avec un rendu plus large que prévu : il s'approprie des objets d'un autre gestionnaire (Kustomize) ; ensuite, deux outils se battent pour les mêmes champs.
- Désactiver la base intégrée sur une release qui l'avait : grâce à `keep`, la base reste… et l'API pointe vers un autre Secret.

**En production chez MédiSphère**

La base de production n'est **pas** dans le chart (E09) ; la base intégrée sert au dev, aux tests d'intégration (`ct install`) et aux démonstrations. Les dépendances tierces sont recopiées et signées (E08) ; Renovate (M13) proposera leurs montées de version par MR.

---

### M17-E07 — Tester un chart

**Solution**

Fichiers : [`tests/`](fichiers/M17-E12/chart/charts/mediagenda/tests/) (six suites, 37 tests : `deployment_test.yaml`, `exposition_test.yaml`, `migrations_test.yaml` (E12), `reseau_test.yaml`, `cnpg_test.yaml`, `schema_test.yaml`), [`templates/tests/test-pret.yaml`](fichiers/M17-E12/chart/charts/mediagenda/templates/tests/test-pret.yaml), [`.helmignore`](fichiers/M17-E12/chart/charts/mediagenda/.helmignore), [`ct.yaml`](fichiers/M17-E12/chart/ct.yaml), [`ci/autonome-values.yaml`](fichiers/M17-E12/chart/charts/mediagenda/ci/autonome-values.yaml), [`wb-ct.yaml`](fichiers/M17-E07/wb-ct.yaml).

1. **Tests unitaires.**
   ```
   admin@adm01:~/src/mediagenda-chart$ helm unittest charts/mediagenda
    PASS  Base CloudNativePG rendue par le chart   tests/cnpg_test.yaml
    PASS  Deployment de l'API                     tests/deployment_test.yaml
    PASS  Exposition et disponibilité (HTTPRoute, PDB)  tests/exposition_test.yaml
    PASS  Migrations de schéma (hooks)            tests/migrations_test.yaml
    PASS  Politiques réseau                       tests/reseau_test.yaml
    PASS  Schéma des valeurs (values.schema.json) tests/schema_test.yaml
   Tests:       37 passed, 37 total
   ```
   Points de méthode : `set` au niveau de la suite pour les valeurs communes (`medisphere.environnement`), `release.name`/`namespace` fixés (le nom complet en dépend), `template:` par test quand la suite charge plusieurs gabarits, `documentSelector` (ou `documentIndex`) pour viser un document d'un gabarit qui en rend plusieurs (Job et sa politique), `chart.appVersion` pour figer la version.
2. **Le test menteur.** Une suite qui ne charge que `deployment.yaml` : ce gabarit `include` `configmap.yaml` (empreinte), absent de la suite ; **chaque** rendu échoue (`no template "mediagenda/templates/configmap.yaml" associated with template "gotpl"`), donc `failedTemplate: {}` passe… avec des valeurs valides. Constaté sur le banc d'essai. Corrections : charger `configmap.yaml` dans la suite, ajouter un **cas témoin** qui doit rendre (`isKind: Deployment`), et donner à chaque `failedTemplate` un `errorPattern` qui nomme la valeur (`"/image/tag"`). Règle à noter : un test d'échec sans motif précis ne prouve rien.
3. **`helm test` et archive.**
   ```
   admin@adm01:~/src/mediagenda-chart$ helm package charts/mediagenda -d /tmp && tar -tzf /tmp/mediagenda-0.4.0.tgz | grep -E 'tests|ci/'
   mediagenda/templates/tests/test-pret.yaml
   ```
   Avec un `.helmignore` qui contient `tests/`, le test Helm **disparaît** du rendu et de l'archive sans aucun message (constaté) : le motif s'applique à tout répertoire nommé `tests`. Il faut l'ancrer : `/tests/` et `/ci/`. Le pod de test n'utilise que l'image de l'application (Python et `urllib`) : il passe la VAP (registre MédiSphère) et `restricted` ; il vérifie `/pret` (dépendances) **et** que `/sante` annonce la version déployée.
4. **`ct lint`.**
   ```
   admin@adm01:~/src/mediagenda-chart$ ct lint --config ct.yaml --all
   Linting chart with values file "charts/mediagenda/ci/autonome-values.yaml"...
   ✔︎ mediagenda => (version: "0.4.0", path: "charts/mediagenda")
   All charts linted successfully
   admin@adm01:~/src/mediagenda-chart$ git switch -c essai && sed -i 's/replicaCount: 2/replicaCount: 3/' charts/mediagenda/values.yaml && git commit -qam essai
   admin@adm01:~/src/mediagenda-chart$ ct lint --config ct.yaml
   ✖︎ mediagenda => (version: "0.4.0", path: "charts/mediagenda") > chart version not ok. Needs a version bump!
   ```
   `ct lint` fait : `helm dependency build`, validation de `Chart.yaml` par yamale (`chart_schema.yaml`), yamllint de `Chart.yaml` et `values.yaml` (`lintconf.yaml`), `helm lint` avec **chaque** fichier `ci/*-values.yaml`, et la montée de version par rapport à `origin/main`. `excluded-charts: [medisphere-commun]` : un chart de bibliothèque ne se rend pas seul ; il est testé à travers `mediagenda`. Remarque : l'image `quay.io/helmpack/chart-testing:v3.15.0` contient **Helm 3.16.4** (constaté) ; `ct lint` y fonctionne aussi, mais le pipeline du palier 3 doit utiliser Helm 4.3 (image dérivée, ou binaire monté) pour tester avec la version de production.
5. **`ct install`.**
   ```
   admin@adm01:~$ kubectl apply --server-side -f wb-ct.yaml
   admin@adm01:~$ kubectl -n mediagenda-dev get secret harbor-pull -o json \
       | jq 'del(.metadata.namespace,.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.managedFields,.metadata.ownerReferences,.metadata.labels,.metadata.annotations)' \
       | kubectl -n wb-ct apply -f -
   admin@adm01:~/src/mediagenda-chart$ ct install --config ct.yaml --namespace wb-ct --charts charts/mediagenda
   admin@adm01:~$ kubectl -n wb-ct get pods,cluster.postgresql.cnpg.io,pvc -w        # dans un autre terminal
   ```
   `ct` installe une release au nom aléatoire (`mediagenda-<suffixe>`) avec `ci/autonome-values.yaml`, attend, lance `helm test`, affiche les journaux en cas d'échec, puis **désinstalle**. Avec `--namespace`, il ne supprime pas l'espace. La base, protégée par `keep`, **reste** : supprime-la, puis l'espace :
   ```
   admin@adm01:~$ kubectl -n wb-ct delete cluster.postgresql.cnpg.io --all --wait
   admin@adm01:~$ kubectl delete namespace wb-ct --wait
   admin@adm01:~$ kubectl get pv | grep wb-ct || echo "aucun volume de wb-ct"
   ```
   ⚠️ À vérifier sur ton lab : le délai par défaut de `ct install` (`helm-extra-args: --timeout 600s` dans `ct.yaml`) suffit-il à CNPG pour créer la base ?
6. **`helm test` en dev.** Politique temporaire :
   ```yaml
   apiVersion: cilium.io/v2
   kind: CiliumNetworkPolicy
   metadata: {name: essai-coupure-valkey, namespace: mediagenda-dev}
   spec:
     endpointSelector:
       matchLabels: {app.kubernetes.io/name: valkey, app.kubernetes.io/instance: mediagenda}
     ingressDeny:
       - fromEntities: [all]
   ```
   `helm test` échoue (`HTTPError: HTTP Error 503` dans les journaux, `/pret` signale Valkey) ; le pod `mediagenda-test-pret` reste en `Error` (politique `before-hook-creation` : il est remplacé au test suivant). Après suppression de la politique, le test passe ; `helm status` affiche la phase du dernier test (`TEST SUITE: … Phase: Succeeded`). Les règles `ingressDeny` l'emportent sur les autorisations : c'est ce qui rend l'essai possible sans toucher aux objets de la release.

**Explications**

Trois niveaux, trois questions : **helm-unittest** (« le rendu est-il celui que je veux, pour chaque combinaison de valeurs ? » — rapide, sans cluster, chaque MR) ; **`ct install`** (« le chart s'installe-t-il, et l'application fonctionne-t-elle, dans un cluster réel, à partir de rien ? » — lent, avant publication) ; **`helm test`** (« la release **déployée** fonctionne-t-elle ? » — après chaque montée, dans chaque environnement Helm).

**Alternatives**

- Tests de rendu par `helm template | conftest` (politiques Rego) ou `kubeconform` : complémentaires (validation de schéma Kubernetes), pas un remplacement des assertions métier.
- `ct install` contre un cluster kind éphémère dans le pipeline : plus isolé, mais kind ne reproduit ni ceph-csi ni Cilium ni CNPG de `k8s-par1`.

**Pièges classiques**

- `.helmignore` qui exclut `templates/tests/` : `helm test` « passe » en ne testant rien (`No tests found`… ou silence selon la version).
- Tests unitaires qui figent des détails sans intérêt (ordre des étiquettes) : ils cassent à chaque refactorisation et on finit par les ignorer.
- Lancer `ct install` sans `--namespace` sur un cluster en Pod Security `restricted` par défaut et sans Secret de tirage : l'échec ne dit rien du chart.
- Oublier la base orpheline après `ct install` : quota et volumes `ceph-rbd` consommés en silence.

**En production chez MédiSphère**

Le pipeline du chart (M17-E13) lance helm-unittest et `ct lint` à chaque MR, `ct install` dans `wb-ct` avant publication ; `helm test` est lancé après chaque montée Helm, puis remplacé par les vérifications de synchronisation d'Argo CD (M20) et les sondes de supervision (M21).

---

### M17-E08 — Publier le chart en OCI dans Harbor et le signer

**Solution**

Fichiers : [`outils/publier-chart.sh`](fichiers/M17-E08/outils/publier-chart.sh), [`outils/recopier-chart.sh`](fichiers/M17-E08/outils/recopier-chart.sh) (projet `mediagenda/chart`), [`registre-charts.md`](fichiers/M17-E08/medisphere/docs/kubernetes/packaging/registre-charts.md) (`plateforme/medisphere`).

1. **Projet et robot.** Dans Harbor (compte `admin` ou toi si tu es administrateur du projet) : projet `charts` privé ; *Policy → Tag Immutability* : dépôts `**`, étiquettes `**` ; *Configuration → Cosign* (« n'autoriser que les artefacts signés ») comme `medisphere`. Robot de projet `charts+ci` (Harbor le nomme `robot$charts+ci`) : *Push Repository*, *Pull Repository*, *Read Artifact*, expiration 90 jours. Harbor n'affiche le secret qu'une fois : colle-le directement dans *GitLab → groupe mediagenda → Settings → CI/CD → Variables* (`HARBOR_CHARTS_TOKEN`, protégée, masquée ; `HARBOR_CHARTS_USER` = `robot$charts+ci`, protégée mais **non masquable** à cause du `$`, avec « Expand variable reference » **désactivé**, comme `HARBOR_ROBOT_USER` au M13). ⚠️ À vérifier sur ton lab : avec la politique Cosign active, Harbor laisse-t-il `cosign sign` lire le manifeste de l'artefact non encore signé ? Le M13 a rencontré la même question pour les images : reprends la réponse que tu y as trouvée.
2. **Connexion de Helm.**
   ```
   admin@adm01:~$ read -rs HARBOR_MDP && printf '%s' "$HARBOR_MDP" | helm registry login registry.par1.medisphere.internal -u <MOI> --password-stdin; unset HARBOR_MDP
   Login Succeeded
   ```
   Helm range l'identifiant dans `~/.config/helm/registry/config.json` (même format que Docker ; option globale `--registry-config`). Fichier en 600 : vérifie-le. Cosign, lui, lit `~/.docker/config.json` ou `cosign login`.
3. **Valkey.**
   ```
   admin@adm01:~/src/mediagenda-chart$ . ~/src/outils/cosign-cle.sh        # M13-E07 : COSIGN_KEY, COSIGN_PASSWORD, MS_SIGNING_CONFIG, MS_COSIGN_PUB
   admin@adm01:~/src/mediagenda-chart$ outils/recopier-chart.sh https://valkey.io/valkey-helm/ valkey 0.12.0
   == Images citées par le rendu par défaut :
         image: docker.io/valkey/valkey:9.1.2
   …
   ```
   (La clé reste dans une variable du seul terminal, jamais sur disque ; `cosign_oublier` l'efface à la fin.) Puis `repository: oci://registry.par1.medisphere.internal/charts` dans `Chart.yaml` et `helm dependency update` : `Chart.lock` change (champ `repository` et empreinte `digest` de l'ensemble des dépendances), même si le contenu téléchargé est identique.
4. **Publication.**
   ```
   admin@adm01:~/src/mediagenda-chart$ helm dependency build charts/mediagenda && helm package charts/mediagenda -d /tmp
   Successfully packaged chart and saved it to: /tmp/mediagenda-0.4.0.tgz
   admin@adm01:~/src/mediagenda-chart$ tar -tzf /tmp/mediagenda-0.4.0.tgz | head
   admin@adm01:~/src/mediagenda-chart$ helm push /tmp/mediagenda-0.4.0.tgz oci://registry.par1.medisphere.internal/charts
   Pushed: registry.par1.medisphere.internal/charts/mediagenda:0.4.0
   Digest: sha256:<DIGEST>
   ```
   L'archive contient `charts/medisphere-commun/` et `charts/valkey/` : le consommateur n'a besoin d'aucun autre dépôt.
5. **Immuabilité.** Republier 0.4.0 modifié : Harbor refuse (⚠️ message à relever sur ton lab, du type `… configured as immutable`). Après **suppression** de l'artefact, la republication passe : l'immuabilité protège contre l'écrasement, pas contre la suppression. D'où deux protections de plus : droits de suppression réservés (pas au robot de CI), et consommation **par digest** vérifié (E09) — un contenu republié sous la même étiquette a un autre digest et une signature absente.
6. **Signature.**
   ```
   admin@adm01:~$ cosign sign --key env://COSIGN_KEY --signing-config "$MS_SIGNING_CONFIG" \
       registry.par1.medisphere.internal/charts/mediagenda@sha256:<DIGEST>
   Signing artifact...
   Pushing signature to: registry.par1.medisphere.internal/charts/mediagenda
   admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true \
       registry.par1.medisphere.internal/charts/mediagenda@sha256:<DIGEST>
     - The signatures were verified against the specified public key
   admin@adm01:~$ cd /tmp && COSIGN_PASSWORD=jetable cosign generate-key-pair && cosign verify --key /tmp/cosign.pub --insecure-ignore-tlog=true registry.par1.medisphere.internal/charts/mediagenda@sha256:<DIGEST>
   Error: no matching signatures …
   admin@adm01:/tmp$ shred -u /tmp/cosign.key /tmp/cosign.pub
   ```
   (Sorties observées avec Cosign 3.1.3 sur un registre OCI local.) La configuration de signature est celle du M13-E07 (`docs/registre/signing-config.json`, aucun service) : sans elle, Cosign 3 enverrait l'entrée au journal public **sans poser de question**. Les anciennes options `--use-signing-config=false --tlog-upload=false` fonctionnent encore avec un avertissement de dépréciation : ne les utilise pas. Harbor affiche la signature comme **accessoire** de l'artefact (référent OCI 1.1, format *bundle* de Cosign 3, pris en charge par Harbor 2.15).
7. **Consommation.**
   ```
   admin@adm01:~$ helm pull oci://registry.par1.medisphere.internal/charts/mediagenda --version 0.4.0 -d /tmp/conso
   admin@adm01:~$ helm install essai oci://registry.par1.medisphere.internal/charts/mediagenda@sha256:<DIGEST> \
       -n wb-essais --set medisphere.environnement=dev --dry-run=server | head
   admin@adm01:~$ helm pull oci://registry.par1.medisphere.internal/charts/mediagenda --version 0.4.0 --verify
   Error: failed to fetch provenance "oci://registry.par1.medisphere.internal/charts/mediagenda:0.4.0.prov"
   ```
   `--verify` cherche un fichier de provenance Helm (`.prov`) qui n'existe pas : Helm ne sait pas vérifier une signature Cosign. (Le `--dry-run=server` dans `wb-essais` passera peut-être la Pod Security `baseline` mais il n'y a pas de base : c'est un test de récupération, pas d'installation.)
8. **Provenance Helm ou Cosign.** La provenance Helm (`helm package --sign --key … --keyring …`) produit un `.prov` : l'empreinte de l'archive et de `Chart.yaml`, signée en PGP ; `helm verify`, `helm install --verify` la contrôlent avec un trousseau. Pour MédiSphère, Cosign : (a) **une seule** clé, un seul outil, une seule politique pour les images et les charts (déjà dans le pipeline du M13, déjà comprise par Harbor) ; (b) la signature porte sur le **digest OCI**, attachée comme référent : elle voyage avec l'artefact (réplication Harbor) et se vérifie sans fichier annexe ; (c) l'écosystème de déploiement vérifie Cosign (Kyverno `verifyImages` au M26 sait vérifier un artefact OCI). La provenance Helm reste utile pour des charts distribués **hors** registre OCI (archive téléchargée depuis un dépôt HTTP classique) ou pour un consommateur qui exige `helm install --verify`.

**Explications**

En OCI, un chart est un artefact dont la configuration a le type `application/vnd.cncf.helm.config.v1+json` et la couche `application/vnd.cncf.helm.chart.content.v1.tar+gzip` : Harbor le range comme une image (dépôt `charts/mediagenda`, étiquette `0.4.0`), avec les mêmes règles (immuabilité, robots, réplication, accessoires). Cosign signe le **manifeste** de cet artefact : ce que vérifie un consommateur, c'est donc exactement le contenu qu'il récupère par ce digest.

**Alternatives**

- Dépôt de charts HTTP (`index.yaml`) : GitLab a un registre de paquets Helm (non OCI) ; Harbor n'en a plus (ChartMuseum supprimé). Le monde Helm converge vers OCI.
- Signature sans clé (Fulcio, Rekor) : écartée pour le lab souverain (ADR-0130).

**Pièges classiques**

- `helm registry login https://registry…` : refusé par Helm 4 (nom de domaine seulement).
- Signer l'**étiquette** (`…/mediagenda:0.4.0`) : Cosign résout l'étiquette au moment de la signature et signe ce digest-là ; si l'étiquette bouge, la signature ne suit pas. Toujours par digest, celui affiché par `helm push`.
- Ranger le jeton du robot dans un fichier « temporaire » ou dans l'historique du shell.
- Oublier de recopier la dépendance : l'archive embarque Valkey, mais `helm dependency build` en CI irait encore chercher `valkey.io`.

**En production chez MédiSphère**

Publication uniquement par le pipeline (M17-E13) avec le robot ; signature par la clé de CI ; Renovate propose les montées des charts tiers recopiés ; le registre des charts est relu à chaque trimestre comme le registre des secrets.

---

### M17-E09 — Kustomize avancé : components, remplacements, générateurs

**Solution**

Projet complet : [`fichiers/M17-E09/deploiement/`](fichiers/M17-E09/deploiement/) — [`chart.env`](fichiers/M17-E09/deploiement/chart.env), [`outils/rendre-base.sh`](fichiers/M17-E09/deploiement/outils/rendre-base.sh), [`base/`](fichiers/M17-E09/deploiement/base/) (`kustomization.yaml`, `values-communes.yaml`, `rendu/mediagenda.yaml`), [`components/`](fichiers/M17-E09/deploiement/components/) (`dependances`, `haute-disponibilite`, `debogage`, `livraison`), [`overlays/`](fichiers/M17-E09/deploiement/overlays/) (`dev`, `recette`, `prod`), [`essais/helmcharts/`](fichiers/M17-E09/deploiement/essais/helmcharts/kustomization.yaml).

1. **Ordre.** Une kustomization accumule ses `resources` (récursivement, chacune déjà transformée par sa propre kustomization), exécute ses propres générateurs, applique ses `components` **dans l'ordre de la liste** (chacun avec ses générateurs, transformateurs et remplacements), puis ses propres transformations (espace, étiquettes, images, réplicas, correctifs) et enfin ses propres `replacements`. Vérifié avec Kustomize 5.8.2 et kubectl 5.8.1 : un `merge` de ConfigMap fait par un component l'emporte sur celui de l'overlay qui l'inclut ; un `images:` posé dans l'overlay l'emporte sur les remplacements du component `livraison` (l'image change, `MEDIAGENDA_VERSION` non) — d'où la règle « pas d'`images:` dans un overlay de `mediagenda/deploiement` ». Seul un overlay **parent** qui inclurait cet overlay comme ressource passerait encore après. `--enable-helm` : qui construit doit avoir le binaire `helm` (et sa version), un accès réseau au registre et des identifiants (`helm registry login`), et le rendu dépend de tout cela.
2. **Rendu vérifié.** `outils/rendre-base.sh` : `helm pull --version` → comparaison du digest reçu (ligne `Digest:` de `helm pull`) avec `chart.env` → `cosign verify` **de ce digest** → `helm template … --no-hooks --skip-tests` avec `base/values-communes.yaml` → écriture de `base/rendu/mediagenda.yaml` (avec un en-tête qui cite référence, version et digest). `--verifier` ne modifie rien et échoue si le rendu commité diffère (testé : vert, puis rouge après altération d'une ligne). Après E12 :
   ```
   admin@adm01:~/src/mediagenda-deploiement$ sed -i "s/^CHART_DIGEST=.*/CHART_DIGEST=sha256:<DIGEST-0.5.0>/" chart.env
   admin@adm01:~/src/mediagenda-deploiement$ outils/rendre-base.sh && git diff --stat
   ```
3. **ConfigMap générée dans la base.** La base génère `mediagenda-parametres` (`MEDIAGENDA_CACHE_TTL=60`) et l'ajoute en fin d'`envFrom` ; recette et prod la complètent par `behavior: merge` (`parametres.env`), `debogage` aussi. Vérifié : dans chaque overlay, `envFrom` = `[mediagenda, mediagenda-parametres-<empreinte>]`.
4. **Components.** Extraits :
   ```yaml
   # components/livraison/kustomization.yaml
   kind: Component
   replacements:
     - source: {kind: ConfigMap, name: livraison, fieldPath: data.version}
       targets:
         - select: {kind: Deployment, name: mediagenda}
           fieldPaths:
             - spec.template.spec.containers.[name=api].image
             - spec.template.spec.initContainers.[name=migrations].image
           options: {delimiter: ':', index: 1}
         - select: {kind: Deployment, name: mediagenda}
           fieldPaths:
             - spec.template.spec.containers.[name=api].env.[name=MEDIAGENDA_VERSION].value
             - metadata.labels.[app.kubernetes.io/version]
             - spec.template.metadata.labels.[app.kubernetes.io/version]
     - source: {kind: ConfigMap, name: livraison, fieldPath: data.nom-publie}
       targets:
         - select: {kind: HTTPRoute, name: mediagenda}
           fieldPaths: [spec.hostnames.0]
   ```
   `debogage` passe par un patch stratégique sur `env` : le chart met `MEDIAGENDA_LOG_LEVEL` dans `env`, qui l'emporte sur toute ConfigMap de `envFrom` ; la liste `env` se fusionne par `name`. `haute-disponibilite` : `replicas: 3`, répartition (patch stratégique `repartition.yaml` : zone `topology.kubernetes.io/zone` en `ScheduleAnyway`, nœud en `DoNotSchedule`), PDB à 2, `Cluster` à 3 instances avec anti-affinité **requise** et `postgresql.synchronous` (`method: any`, `number: 1` ; syntaxe de CNPG ≥ 1.24, ⚠️ à vérifier sur 1.30). `dependances` : `Cluster` `mediagenda-db`, StatefulSet et Service `valkey`, leurs politiques (dont réplication entre instances et accès à l'API Kubernetes).
5. **Overlays.** Vérifications faites sur les rendus :
   - prod : 3 réplicas, 2 contraintes de répartition, PDB à 2, `Cluster` à 3 instances, nom `mediagenda.apps.par1.medisphere.internal`, aucune variable `DEBUG` ;
   - dev : 1 réplica, `MEDIAGENDA_LOG_LEVEL=DEBUG`, `MEDIAGENDA_LOG_FORMAT=texte`, PDB **retiré** (`$patch: delete`) : un budget `minAvailable: 1` sur une réplique interdit toute éviction et bloque les drains (M14-E16) ;
   - dans chaque overlay, les quatre champs de version sont égaux. Une promotion = **une ligne** (`version:` dans `overlays/<env>/livraison.yaml`).
6. **Production.**
   ```
   admin@adm01:~/src/mediagenda-deploiement$ kubectl diff --server-side -k overlays/prod
   admin@adm01:~/src/mediagenda-deploiement$ kubectl apply --server-side -k overlays/prod
   ```
   Le Secret `harbor-pull` se crée **après** l'espace et **hors** du dépôt, par la méthode du M14-E19 (depuis le robot `robot$k8s-pull`, jamais par un fichier commité). Les pods créés avant lui restent en `ErrImagePull` puis repartent seuls ; un second `apply` n'est même pas nécessaire. Ordre de démarrage : la base (3 instances, quelques minutes), puis l'API — dont le conteneur d'initialisation `migrations` attend que la base réponde (il échoue et le pod redémarre tant qu'elle n'est pas prête : `Init:CrashLoopBackOff` transitoire). Le quota (`requests.cpu: 4`, `requests.memory: 8Gi`) couvre 3 API + 3 instances PostgreSQL + Valkey ; l'anti-affinité **requise** exige 3 travailleurs disponibles (`k8s-w01-03`).
   ```
   admin@adm01:~$ kubectl -n mediagenda-prod get pods -o wide -l app.kubernetes.io/name=mediagenda
   admin@adm01:~$ curl -fsS https://mediagenda.apps.par1.medisphere.internal/sante
   {"statut":"ok","version":"v1.0.0"}
   ```
   ExternalDNS publie `mediagenda.apps.par1.medisphere.internal` (source `gateway-httproute`, M15) ; le certificat joker `*.apps…` de `gw-par1` le couvre.
   **Mêmes garde-fous que les autres espaces** : [`overlays/prod/espace.yaml`](fichiers/M17-E09/deploiement/overlays/prod/espace.yaml) pose les étiquettes d'espace d'équipe du M14-E10 (`medisphere.internal/equipe: mediagenda`, `medisphere.internal/environnement: prod`) : sans elles, la ValidatingAdmissionPolicy des images (M14-E18, sélection par `medisphere.internal/equipe`) ne s'appliquerait **pas** à la production. Côté `plateforme/k8s`, deux MR accompagnent la création : la cloison `isolement-mediagenda-prod` (CiliumClusterwideNetworkPolicy sur le modèle de `isolement-mediagenda-recette`, M15-E28 : « ajouter un espace d'équipe = ajouter un fichier ») et les liaisons RBAC de l'équipe (lecture seule pour `medisphere:mediagenda-devs`, comme en recette, M14-E11).
7. **Recette.** `kubectl diff --server-side -k overlays/recette` montre le conteneur d'initialisation, les nouvelles étiquettes `medisphere.internal/equipe`, `donnees-sante`, `part-of`, la nouvelle ConfigMap ; après `apply`, le journal du conteneur `migrations` dit qu'aucune migration n'est à appliquer (`"appliquees": []`) : la base du M16 est déjà en V2, et la commande est idempotente. Le Job manuel du M16 (`k8s/recette/50-migration.yaml` de `mediagenda/api`) n'a plus de raison d'être : retire-le par MR, avec ce qui restait de `k8s/recette/` hormis Valkey.
8. **`helmCharts` contre rendu commité.** Constaté avec Kustomize 5.8.2 : quand le chart est gonflé par `helmCharts`, la référence ajoutée par patch à la ConfigMap **générée** (`envFrom: mediagenda-parametres`) n'est **pas** réécrite avec son suffixe d'empreinte (le Deployment référence `mediagenda-parametres`, qui n'existe pas) ; la même kustomization sur un rendu commité réécrit correctement (`mediagenda-parametres-<empreinte>`). Les références **internes** au chart (un `namePrefix` sur le compte de service, la ConfigMap du chart) sont, elles, bien réécrites. ⚠️ Comportement observé sur cette version, à revérifier sur la tienne. Choix MédiSphère : **rendu commité**, parce que (a) la MR montre le diff exact de ce qui changera dans le cluster ; (b) la signature est vérifiée **une fois**, par un outil qui le dit, avant le rendu ; (c) construire l'overlay ne demande ni Helm, ni réseau, ni identifiants — Argo CD (M20) lira le dépôt tel quel ; (d) on évite les comportements fins du gonfleur (celui-ci). Coût : un rendu à régénérer, d'où `--verifier` dans le pipeline.

**Explications**

- **Components ou overlays imbriqués ?** Un overlay « prod » qui hériterait d'un overlay « ha » crée une chaîne rigide ; un component est une **option** que chaque overlay inclut ou non (dev prend `dependances` et `debogage`, prod `dependances` et `haute-disponibilite`). L'ordre de la liste compte : `livraison` en dernier, `haute-disponibilite` après `dependances` (ses correctifs visent le `Cluster` qu'apporte `dependances` ; un patch sans cible correspondante ne fait rien… silencieusement).
- **Ressource locale.** `config.kubernetes.io/local-config: "true"` : la ConfigMap `livraison` sert de source aux remplacements mais n'est pas émise (vérifié : absente des rendus).
- **Pourquoi la base de prod hors du chart.** Le chart empaquette l'**application** ; la base a un autre cycle de vie (sauvegardes, montées de PostgreSQL, restaurations), d'autres risques (une suppression est irréversible) et d'autres responsables. `kubectl delete -k` de l'application ne doit jamais l'emporter. Le chart garde sa base intégrée pour dev et les tests.

**Alternatives**

- Gonfleur `helmCharts` (essais) : un fichier de moins, un comportement de moins à maîtriser… quand il marche. Valable si l'on accepte `--enable-helm` partout et qu'on vérifie la signature ailleurs.
- `helm` comme moteur et Kustomize en **post-rendu** (plugin de post-rendu en Helm 4) : garde les hooks et l'historique Helm ; ajoute une couche de plus à comprendre.
- Promotion par `images:` (E04) : simple, mais la version se recopie dans `MEDIAGENDA_VERSION` et les étiquettes à la main.

**Pièges classiques**

- Fichier de valeurs ou de remplacements « partagé » hors du répertoire de l'overlay : refusé par la restriction de chargement (`security; file … is not in or below …`).
- Registre avec numéro de port dans l'image (`hote:5000/…`) : le remplacement par délimiteur `:` à l'index 1 vise alors le port.
- Le transformateur `namespace` renomme aussi l'objet `Namespace` de l'overlay : son nom dans `espace.yaml` est sans effet.
- Anti-affinité requise et 3 instances sur un cluster qui perd un travailleur : la troisième instance reste `Pending` (c'est voulu ; à savoir en astreinte).

**En production chez MédiSphère**

Chaque promotion est une MR sur `livraison.yaml` de l'environnement suivant, avec le `kubectl diff` dans la description ; Argo CD (M20) appliquera ce dépôt et fera le ménage des objets retirés. La production est ajoutée à la politique de sauvegarde (M16-E32) : base `mediagenda-db` de `mediagenda-prod` avec le plugin Barman Cloud — non configuré dans ce palier (⚠️ à faire avant toute donnée réelle ; le mini-projet le rappelle).

---

### M17-E10 — Helmfile : décrire la plateforme

**Solution**

Fichiers : [`helmfile.yaml`](fichiers/M17-E10/k8s/helmfile.yaml), [`releases/_communs.yaml`](fichiers/M17-E10/k8s/releases/_communs.yaml), [`releases/10-reseau.yaml.gotmpl`](fichiers/M17-E10/k8s/releases/10-reseau.yaml.gotmpl), [`20-certificats-dns`](fichiers/M17-E10/k8s/releases/20-certificats-dns.yaml.gotmpl), [`30-stockage`](fichiers/M17-E10/k8s/releases/30-stockage.yaml.gotmpl), [`40-observabilite`](fichiers/M17-E10/k8s/releases/40-observabilite.yaml.gotmpl), [`environnements/par1.yaml`](fichiers/M17-E10/k8s/environnements/par1.yaml), [`outils/comparer-releases.sh`](fichiers/M17-E10/k8s/outils/comparer-releases.sh), un exemple [`composants/metrics-server/values.yaml`](fichiers/M17-E10/k8s/composants/metrics-server/values.yaml), [`Taskfile.yml.extrait`](fichiers/M17-E10/k8s/Taskfile.yml.extrait).

Versions déclarées dans le corrigé (dernières de chaque série au 8 octobre 2026, **à remplacer par celles que montre ton `helm list -A`**) : `cilium` 1.20.2, `cert-manager` v1.21.1 (le palier 3 monte en v1.21.2), `external-dns` 1.23.0 (application 0.23.0), `ceph-csi-rbd`/`ceph-csi-cephfs` 3.18.1, `cloudnative-pg` 0.29.1 (opérateur 1.30.1), `plugin-barman-cloud` 0.8.1 (plugin 0.15.1), `velero` 12.2.1 (application 1.18.2), `metrics-server` 3.14.0. Neuf releases en tout.

Deux points de reprise qui comptent pour un diff vide : la **source** de chaque chart et le **chemin** des valeurs. cert-manager a été installé au M15 depuis son registre OCI (`oci://quay.io/jetstack/charts/cert-manager`) : le dépôt `jetstack` de `_communs.yaml` est donc déclaré en OCI (`url: quay.io/jetstack/charts`, `oci: true`). Les valeurs restent là où les modules 14 à 16 les ont rangées (`composants/ceph-csi/values-rbd.yaml` et `values-cephfs.yaml`, `composants/cloudnative-pg/values.yaml`, `composants/plugin-barman-cloud/values.yaml`…) : on ne déplace pas un fichier que d'autres scripts lisent encore. `outils/comparer-releases.sh` connaît ces chemins.

1. **Inventaire.**
   ```
   admin@adm01:~/src/k8s$ helm list -A -o json | jq -r '.[] | [.name,.namespace,.chart,.app_version,.revision] | @tsv'
   admin@adm01:~/src/k8s$ outils/comparer-releases.sh k8s-par1 | tee ~/m17/e10/inventaire.md
   admin@adm01:~/src/k8s$ kubectl -n cert-manager get deploy cert-manager -o yaml --show-managed-fields | grep -E 'manager:|operation:'
   ```
   Gestionnaire `helm` + `Apply` : release créée par Helm 4 (*server-side*) ; `helm` + `Update` : *client-side* (cas de Cilium, installé par la CLI `cilium` qui embarque le SDK Helm 3 — ⚠️ à vérifier sur ton lab). Cilium : `helm get values cilium -n kube-system` montre, en plus de ton `values.yaml` du M14/M15, des valeurs ajoutées par la CLI (par exemple `cluster.name`, `operator.replicas`, `k8sServiceHost`…). Elles vont **toutes** dans `composants/cilium/values.yaml`, sinon le diff les retire.
2. **Ossature et premier diff.** Structure vérifiée avec Helmfile 1.8.1 : la racine déclare l'environnement `par1` et inclut `releases/*.yaml.gotmpl` ; chaque fichier de releases commence par `bases: [_communs.yaml]` (environnements, dépôts, `helmDefaults`) puis `---`. Sans environnement `par1` à la racine, `helmfile -e par1 …` répond `no releases found that matches specified selector() and environment(par1)` ; avec `helmfile.yaml` **et** `helmfile.d/` : `you can have either helmfile.yaml or helmfile.d, but not both`.
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 list
   NAME            NAMESPACE     ENABLED  INSTALLED  LABELS                                        CHART                          VERSION
   metrics-server  kube-system   true     true       composant:metrics-server,groupe:observabilite  metrics-server/metrics-server  3.14.0
   admin@adm01:~/src/k8s$ helmfile -e par1 diff -l composant=metrics-server
   ```
3. **Toutes les releases.** Une par une : `diff -l composant=<nom>`, correction du fichier (version, valeurs), jusqu'au silence. Valeur d'environnement utilisée par ExternalDNS (`txtOwnerId: {{ .Values.cluster }}`, `domainFilters: [{{ .Values.domaineApps }}]`) — elle doit **reproduire** les valeurs du M15 (`txt-owner-id=k8s-par1`, `apps.par1.medisphere.internal`), sinon le diff le montre (noms de clés à vérifier sur la version du chart ExternalDNS installée).
4. **Diff vide.**
   ```
   admin@adm01:~/src/k8s$ { helmfile -e par1 diff --detailed-exitcode; echo "code de sortie : $?"; } 2>&1 | tee ~/m17/e10/diff-final.txt
   admin@adm01:~/src/k8s$ helmfile -e par1 apply
   admin@adm01:~/src/k8s$ helm list -A      # mêmes révisions qu'à l'étape 1
   ```
   `apply` = `diff` puis `sync` des seules releases qui diffèrent : aucune ici, donc aucune nouvelle révision. (`helmfile sync`, lui, relancerait un `helm upgrade` de **chaque** release : révisions inutiles, et redémarrages si un gabarit contient un aléa.)
5. **Modification réelle.** `resources.requests.memory: 64Mi` → `96Mi` dans `composants/metrics-server/values.yaml` : le diff montre la seule ligne du Deployment ; `helmfile -e par1 apply -l composant=metrics-server` crée une révision ; le retour se fait en remettant la valeur et en relançant `apply` (encore une révision : l'historique dit la vérité).
6. **Montée manuelle demain.** Personne ne s'en aperçoit tant que quelqu'un ne lance pas `helmfile diff` : le prochain `apply` (pour une autre raison) **annulera** silencieusement la modification manuelle, ce qui peut casser ce qu'elle réparait. Mesures : interdiction écrite des `helm upgrade` à la main sur la plateforme (fiche E02, RB-170), `helmfile diff` planifié (palier 3) qui alerte sur un code 2. Argo CD (M20) réconcilie en continu et montre la dérive dans son interface ; il peut aussi la corriger automatiquement (*self-heal*).
7. **MR et Taskfile.** Description de MR : la sortie de `task helmfile:diff` (vide). Relecture de Karim : chaque version citée correspond à `helm list -A`.

**Explications**

- **Ce que fait Helmfile.** Il rend ses propres fichiers (gabarits `.gotmpl`), puis appelle **Helm** pour chaque release (`helm upgrade --install`) et **helm-diff** pour les diffs ; il n'a pas d'état propre : l'état, ce sont les releases Helm du cluster. Reprendre une release existante est donc naturel : il suffit de déclarer le même nom, le même espace, le même chart, la même version et les mêmes valeurs.
- **Helm 4.** Helmfile 1.8 prend en charge l'option `--server-side` de Helm 4 pour `diff` et `sync` (séries 1.5.4 et 1.5.5). La méthode d'application de chaque release suit la règle de Helm (`auto` : celle de la révision précédente) : une release *client-side* le reste, et c'est voulu tant qu'on n'a pas décidé de la migrer (M17-E14).
- **Pourquoi pas tout dans un seul fichier ?** On pourrait. Les fichiers par groupe rendent les MR lisibles et permettent `helmfile -f releases/30-stockage.yaml.gotmpl …` ; le prix est la déclaration répétée des `bases:`. Les dépendances d'ordre (`needs`) ne fonctionnent qu'**à l'intérieur** d'un même fichier : ce découpage met ensemble ce qui dépend l'un de l'autre.

**Alternatives**

- Argo CD (M20) avec une `Application` par composant : la cible de MédiSphère ; Helmfile reste utile pour amorcer un cluster neuf (avant qu'Argo CD existe) et pour les diffs en MR.
- Terraform/OpenTofu avec le fournisseur Helm : un état de plus à gérer, des diffs moins lisibles ; écarté.
- Un `Taskfile` qui enchaîne des `helm upgrade` : pas de diff, pas de sélecteurs.

**Pièges classiques**

- Comparer à `helm get values --all` : on recopie les défauts du chart dans le dépôt, et la prochaine montée de chart ne prend plus les nouveaux défauts.
- Lancer `helmfile apply` « pour voir » avant d'avoir un diff vide : c'est une montée de version de toute la plateforme.
- Version de chart et version d'application confondues (`external-dns` : chart 1.23.0, application 0.23.0 ; `cnpg` : chart 0.29.1, opérateur 1.30.1).
- `kubeContext` absent : Helmfile utilise le contexte courant de kubectl, qui peut être un autre cluster (M18 en créera plusieurs).
- Secrets dans `composants/` : la sortie de `helm get values` peut contenir un mot de passe si quelqu'un l'a passé par `--set` au M15/M16 ; il faut alors sortir ce secret dans un Secret existant (option `existingSecret` du chart) **avant** la reprise.

**En production chez MédiSphère**

`helmfile diff` tourne chaque nuit (pipeline planifié de `plateforme/k8s`, palier 3) et ouvre un ticket si le code vaut 2 ; les montées passent par MR (E16, palier 3) ; au M20, Argo CD prend le relais et Helmfile ne sert plus qu'à reconstruire un cluster vide jusqu'à ce qu'Argo CD tourne.

---

### M17-E11 — Revue : le chart du stagiaire

**Solution**

Lecture d'ensemble (étape 1) : le chart **ne se rend pas** (`helm lint` : `version should be of type string but it's of type float64`, `version '1' is not a valid SemVerV2`, et `deployment.yaml: … mapping values are not allowed in this context`). Une fois l'indentation corrigée : un seul pod (le `replicaCount: 2` n'est pas lu), sélecteur qui contient la version et le chart ; clés S3 lisibles par quiconque lit le dépôt, la release (Secret de révision), la sortie de `helm install` (NOTES) et `helm get values` ; au deuxième `upgrade`, le jeton d'API change (aléa), la ConfigMap n'est pas mise à jour (hook), et dès que la version change le Deployment ne peut plus être mis à jour (sélecteur).

Revue :

| N° | Fichier | Défaut | Catégorie | Gravité | Impact chez nous | Correction |
|---|---|---|---|---|---|---|
| 1 | `values.yaml` (`s3.accessKey`, `secretKey`), `secret.yaml`, `NOTES.txt` | Clés S3 en clair dans le dépôt, dans le Secret de révision Helm, et **affichées** à chaque installation | Sécurité | Critique | Fuite des clés d'un compte qui lit/écrit des documents patients (HDS) ; elles sont dans l'historique Git et dans tous les Secrets `sh.helm.release.v1.*` | Secret `medidoc-s3` créé hors chart depuis le Vault ; `s3.existingSecret` dans les valeurs ; NOTES sans secret ; **révoquer** les clés publiées (étape 3) |
| 2 | `secret.yaml` | `data:` avec des valeurs non encodées en base64 | Exploitation | Élevée | L'API refuse le Secret (`illegal base64 data`) ; avec des valeurs qui se trouvent être du base64 valide, des clés fausses en silence | Plus de Secret dans le chart (n° 1) ; sinon `stringData` ou `b64enc` |
| 3 | `secret.yaml` (`randAlphaNum`) | Jeton d'API régénéré à **chaque** rendu | Exploitation | Élevée | Chaque `helm upgrade` change le jeton et casse les clients ; Argo CD verrait une dérive permanente | Secret créé une fois hors chart (ou `lookup`, à déconseiller : E05) |
| 4 | `_helpers.tpl` (`medidoc.labels` utilisé comme sélecteur) | Version de l'application et du chart dans `spec.selector` | Disponibilité | Critique | Première montée de version : `field is immutable`, la release reste bloquée ; même problème sur le Service et le PDB | Étiquettes de sélection séparées (`name`, `instance`) |
| 5 | `values.yaml`, `deployment.yaml` | Image `docker.io/lucasmartin/medidoc:latest`, `pullPolicy: Always` | Sécurité / conformité | Élevée | Refusée par la VAP du M14 (registre, `latest`) ; non signée, non analysée ; contenu qui change sans version | `registry.par1.medisphere.internal/medisphere/medidoc:v<appVersion>`, `IfNotPresent` |
| 6 | `Chart.yaml` | `version: 1.0` (nombre, pas SemVer), `appVersion: latest` | Exploitation | Élevée | `helm lint` échoue ; aucune version d'application traçable | `version: 0.1.0`, `appVersion: "1.0.0"` (entre guillemets) |
| 7 | `deployment.yaml` (`resources: {{ … | indent 10 }}`) | `indent` au lieu de `nindent` sur la même ligne que la clé | Exploitation | Élevée | Le chart ne se rend pas | `resources:` puis `{{- toYaml .Values.resources | nindent 12 }}` |
| 8 | `deployment.yaml` (`MEDIDOC_MAX_MB`) | Valeur d'environnement non citée (entier) | Exploitation | Moyenne | L'API refuse un `value` numérique dans `env` | `| quote`, ou dans la ConfigMap |
| 9 | `deployment.yaml` (sondes) | Vivacité sur `/readyz` (dépend de S3), seuil 1, pas de disponibilité | Disponibilité | Élevée | Un ralentissement de RGW fait **redémarrer** tous les pods en boucle ; pendant ce temps aucun pod ne sert | Vivacité `/healthz`, disponibilité `/readyz`, sonde de démarrage |
| 10 | `deployment.yaml` | Aucun contexte de sécurité, aucune requête de ressources | Sécurité | Élevée | Refusé par Pod Security `restricted` de `medidoc-dev` ; QoS `BestEffort` | Contexte `restricted`, `readOnlyRootFilesystem`, requêtes et limite mémoire |
| 11 | tous les gabarits | `namespace: medidoc-dev` en dur | Exploitation | Moyenne | Impossible d'installer ailleurs ; `-n` ignoré : objets dans un espace, release dans un autre | Supprimer `metadata.namespace` (Helm applique l'espace de la release) |
| 12 | `configmap.yaml` | ConfigMap en hook `pre-install` | Exploitation | Élevée | Hors release : jamais mise à jour (un changement d'endpoint est ignoré), jamais supprimée ; deuxième installation : conflit | Objet ordinaire ; empreinte dans le gabarit de pod |
| 13 | `deployment.yaml` | Pas d'annotation d'empreinte de configuration | Exploitation | Moyenne | Un changement de ConfigMap ne redémarre pas les pods | `checksum/config` |
| 14 | `ingress.yaml` | Ingress `nginx` avec annotations nginx, HTTP sans redirection, nom `medisphere.local` | Conformité / sécurité | Élevée | Aucun contrôleur nginx (retiré, non déployé) : MédiDoc n'est pas publié ; nom hors de la zone `apps` (ni DNS ni certificat) | HTTPRoute vers `gw-par1` (`https`), `medidoc-dev.apps.par1.medisphere.internal` |
| 15 | `values.yaml` (`s3.endpoint`) | `http://minio:9000` | Sécurité / exploitation | Élevée | MinIO abandonné (ADR M05) et inexistant ; trafic de documents patients en clair | `https://rgw.par1.medisphere.internal` + CA MédiSphère (`MEDIDOC_CA_FILE`) |
| 16 | `deployment.yaml`, `pdb.yaml` | `replicas: 1` en dur (valeur ignorée) et PDB `minAvailable: 1` | Disponibilité | Moyenne | Un seul pod, et le PDB bloque tout drain de nœud (M14-E16) | `{{ .Values.replicaCount }}` ; PDB seulement si plus d'une réplique |
| 17 | `_helpers.tpl` | Nom complet `medidoc-medidoc`, non tronqué, avec un retour à la ligne (pas de `-`) | Exploitation | Faible | Noms laids, risque de dépasser 63 caractères | Modèle de `mediagenda.fullname` |
| 18 | `values.yaml` (`logLevel: debug`) | Journaux de débogage par défaut | Sécurité | Moyenne | Volumes de journaux, risque de données personnelles en clair (RGPD) | `info` par défaut |
| 19 | chart | Ni `.helmignore`, ni `values.schema.json`, ni tests | Exploitation | Faible | Fichiers parasites dans l'archive ; aucune valeur validée | `.helmignore` ; schéma et tests (E05, E07) |

Ordre de traitement : **1** d'abord (fuite de clés : même si tout le reste est corrigé, les clés publiées restent valides), puis 4 et 5 (bloquants dès le premier jour), puis ce qui empêche de se rendre (6, 7, 8), puis disponibilité et sécurité (9, 10, 14, 15), puis le reste. **Avant de corriger** : faire **révoquer** les clés publiées (compte RGW de test de Lucas : `radosgw-admin key rm` sur `ceph-par1`, ou suppression du compte), les inscrire comme incident de sécurité (Sophie), et les retirer de l'historique Git de la branche de MR **et** de toute copie (purger la branche, demander à GitLab de supprimer les références de MR si nécessaire). Révoquer d'abord : réécrire l'historique ne suffit pas, quelqu'un a pu cloner.

Version corrigée : [`fichiers/M17-E11/medidoc/`](fichiers/M17-E11/medidoc/) (passe `helm lint --strict`, rendu validé par kubeconform). Ce qu'elle ne contient pas encore, et que la revue doit demander : politiques réseau (sortie vers `10.10.30.200:443` et le DNS ; à aligner sur celles du M15-E34), schéma de valeurs, tests, et l'usage de la bibliothèque `medisphere-commun`.

Conseils à Lucas : (1) un essai sur kind prouve que **ton** kind accepte le chart, pas que `k8s-par1` l'acceptera (Pod Security, VAP, Gateway, politiques réseau) : lance au moins `helm lint --strict`, `helm template | kubeconform` et `helm install --dry-run=server` sur un espace de `k8s-par1` ; (2) teste **deux** `helm upgrade` de suite sans rien changer : tout ce qui bouge est un défaut ; (3) n'écris jamais une vraie clé dans un fichier, même « pour tester ».

**Explications**

Une revue de chart lit trois choses à la fois : le **rendu** (ce que l'API recevra), le **cycle de vie** (ce qui change entre deux rendus, ce qui sort de la release), et l'**environnement cible** (ce que nos règles d'admission, notre réseau et nos outils acceptent). Les défauts 3, 4 et 12 ne se voient dans aucun rendu isolé : il faut penser à la deuxième commande.

**Pièges classiques**

- Se contenter des erreurs de `helm lint` : il n'en trouve que trois sur dix-neuf.
- Corriger le chart et oublier les clés déjà publiées.
- Recommander `lookup` pour « garder le jeton » : ça marche en `helm upgrade`, plus avec Kustomize ni Argo CD.

**En production chez MédiSphère**

Le pipeline du chart (palier 3) bloque les défauts mécaniques (lint, schéma, Gitleaks du M01 sur les secrets, `kubeconform`, tests) ; la revue humaine se concentre sur le cycle de vie et l'intégration.

---

### M17-E12 — Hooks, ordre de déploiement et migrations de schéma

**Solution**

Fichiers : [`migrations-job.yaml`](fichiers/M17-E12/chart/charts/mediagenda/templates/migrations-job.yaml) (Job et sa politique réseau), [`_helpers.tpl`](fichiers/M17-E12/chart/charts/mediagenda/templates/_helpers.tpl) (`mediagenda.migrations.hook`, `mediagenda.conteneurMigration`), [`deployment.yaml`](fichiers/M17-E12/chart/charts/mediagenda/templates/deployment.yaml) (mode `initContainer`), [`values.yaml`](fichiers/M17-E12/chart/charts/mediagenda/values.yaml) (bloc `migrations`), [`migrations_test.yaml`](fichiers/M17-E12/chart/charts/mediagenda/tests/migrations_test.yaml).

1. **Séquence d'un `helm upgrade`.**
   ```
   rendu (hooks séparés des objets ordinaires)
     └─ pre-upgrade : hooks triés par poids croissant (puis type, nom)
          poids -10 : NetworkPolicy mediagenda-migrations  → créée, prête immédiatement
          poids   0 : Job mediagenda-migrations             → créé, Helm ATTEND sa fin (succès ou échec)
          échec d'un hook → la montée s'arrête ici : statut « failed », objets ordinaires intacts
     └─ objets ordinaires : application (server-side), ordre des types (Namespace, NetworkPolicy, …,
        ServiceAccount, ConfigMap, Service, Deployment, …) ; --wait : attente selon la stratégie
     └─ post-upgrade : hooks, même règle
     └─ suppression des hooks dont la politique est « hook-succeeded » (tous les hooks de la phase ont réussi)
   ```
   « Prêt » pour un Job de hook = terminé avec la condition `Complete` ; `Failed` fait échouer l'opération. Dans `helm template`, les hooks sont rendus comme des objets ordinaires (avec leurs annotations), sauf `--no-hooks` ; `kubectl apply` (et donc le rendu de E09) les appliquerait **comme des objets ordinaires**, sans ordre et sans attente : un Job a un gabarit immuable, le deuxième `apply` d'une nouvelle image échouerait. D'où le mode `initContainer` sous Kustomize.
2. **Le Job de hook.** Points de solution :
   - phase : `pre-install,pre-upgrade` si la base est externe ; si le chart rend la base, `post-install,pre-upgrade` (au premier `install`, les hooks `pre-install` passent **avant** la création du `Cluster` : le Job attendrait une base qui n'existe pas encore, et Helm attendrait le Job — l'installation ne se terminerait jamais) ;
   - `hook-delete-policy: before-hook-creation` : l'ancien Job est supprimé juste avant d'en créer un nouveau, mais un Job **terminé** (réussi ou en échec) reste pour qu'on lise son journal ; `ttlSecondsAfterFinished: 86400` le nettoie ensuite ;
   - `serviceAccountName: default` (avec `automountServiceAccountToken: false`) : le compte de service du chart est un objet ordinaire, absent pendant un `pre-install` ; sans cela, le contrôleur de Job ne crée aucun pod (`serviceaccount "mediagenda" not found`) et Helm attend jusqu'au délai ;
   - une **NetworkPolicy en hook** de poids `-10` (sorties DNS et PostgreSQL du seul Job), supprimée quand la phase a réussi (`hook-succeeded`) : l'espace est en refus par défaut, et la politique ordinaire de la release n'existe pas encore au premier `pre-install` ;
   - `backoffLimit: 6`, `activeDeadlineSeconds: 600` : la base peut mettre une minute à répondre ; au-delà de dix minutes, on préfère échouer franchement ;
   - même conteneur que le conteneur d'initialisation (gabarit `mediagenda.conteneurMigration`), contexte `restricted`.
3. **Modes et tests.** `initContainer` : le conteneur `migrations` dans le Deployment (chaque pod migre avant de démarrer ; le verrou consultatif de `mediagenda.migrate` sérialise les exécutions) ; `none` : rien. Tests : phase selon la base, poids de la politique, compte de service, absence de hook en mode `initContainer` (cinq tests de `migrations_test.yaml`) et présence du conteneur d'initialisation (`deployment_test.yaml`).
4. **Observation.**
   ```
   admin@adm01:~/src/mediagenda-chart$ helm upgrade mediagenda charts/mediagenda -n mediagenda-dev -f ~/m17/e06/dev.yaml --wait --timeout 10m
   admin@adm01:~$ kubectl -n mediagenda-dev get events --sort-by=.lastTimestamp -w      # autre terminal
   … NetworkPolicy … (aucun événement : les politiques n'en émettent pas)
   … job/mediagenda-migrations   SuccessfulCreate   Created pod: mediagenda-migrations-…
   … job/mediagenda-migrations   Completed          Job completed
   … deployment/mediagenda       ScalingReplicaSet  Scaled up replica set mediagenda-… from 0 to 1
   admin@adm01:~$ kubectl -n mediagenda-dev logs job/mediagenda-migrations
   {"niveau":"INFO","message":"migrations terminées","appliquees":[]}
   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-dev -- -c 'SELECT version, description, left(empreinte,12), appliquee_le FROM mediagenda_historique_schema'
    version | description | left         | appliquee_le
    1       | init        | …            | …
    2       | index       | …            | …
   ```
   (format exact du journal : celui de `journal.py`, à vérifier.) Les migrations V1 et V2 avaient été appliquées par l'API ou par toi au M16 ; si la base de dev est neuve (E03), le Job les applique ici. L'empreinte est le SHA-256 du fichier : modifier `V1__init.sql` dans l'image ferait échouer toutes les migrations suivantes.
5. **Échec provoqué.**
   ```
   admin@adm01:~/src/mediagenda-chart$ kubectl -n mediagenda-dev get deploy mediagenda -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' | tee -a ~/m17/e12/journal.md
   admin@adm01:~/src/mediagenda-chart$ helm upgrade mediagenda charts/mediagenda -n mediagenda-dev -f ~/m17/e06/dev.yaml \
       --set migrations.repertoire=/nexiste-pas --set migrations.backoffLimit=0 --wait --timeout 5m
   Error: UPGRADE FAILED: pre-upgrade hooks failed: … job mediagenda-migrations failed: BackoffLimitExceeded
   admin@adm01:~$ kubectl -n mediagenda-dev logs job/mediagenda-migrations
   {"niveau":"CRITICAL","message":"échec des migrations : répertoire de migrations introuvable : /nexiste-pas"}
   admin@adm01:~$ helm history mediagenda -n mediagenda-dev | tail -n 2
   admin@adm01:~$ curl -fsS https://mediagenda-dev.apps.par1.medisphere.internal/sante      # toujours 200, même version
   ```
   La révision est `failed`, le Deployment **n'a pas été touché** (même image, même ReplicaSet), l'API sert. La politique réseau de hook (`hook-succeeded`) n'a pas été supprimée, puisque la phase a échoué : la prochaine exécution la recrée (`before-hook-creation`). ⚠️ Message d'erreur de Helm à relever sur ton lab.
6. **Retour à un état sain.** Une montée correcte (sans les deux `--set`) passe directement : une release `failed` accepte un nouvel `upgrade` (contrairement à `pending-upgrade`, palier 4). Avec `--rollback-on-failure`, l'échec est suivi d'une révision « Rollback to N » `deployed` : l'historique montre `failed` puis la révision de retour. Enregistre `helm history … > ~/m17/e12/historique.txt` après l'une des deux.
7. **Migration réussie, application en échec, rollback.** `helm rollback` remet l'**ancien Deployment** ; la base reste **en V3** (rien ne défait une migration : pas de « down » dans `mediagenda.migrate`, et un rollback relance d'ailleurs le hook `pre-rollback`… que le chart n'a pas). L'ancienne API fonctionne si, et seulement si, V3 est **rétrocompatible**. Discipline *expand / contract* : une version N+1 ne fait qu'**ajouter** (colonnes facultatives, nouvelles tables, index) — *expand* ; l'API N+1 écrit les deux formes ; le **retrait** de l'ancienne forme (*contract*) vient dans une migration d'une version ultérieure, quand plus aucune version déployée ne l'utilise. À dire à l'équipe de Julien : jamais de `DROP`, de renommage ni de `NOT NULL` sans défaut dans la même version que le code qui en dépend ; toute migration est relue avec la question « l'ancienne version tourne-t-elle encore après ? ».
8. **Publication.** `outils/publier-chart.sh charts/mediagenda` (version 0.5.0), puis `chart.env` de `mediagenda/deploiement` (E09) prend le digest affiché.

**Explications**

- **Hook, conteneur d'initialisation ou Job séparé.** Le hook donne l'ordre « migrer puis déployer » et un échec qui **arrête** la montée — mais seulement sous Helm. Le conteneur d'initialisation fonctionne avec tout outil (Kustomize, Argo CD) et à chaque démarrage de pod (idempotent grâce à l'historique et au verrou), mais une migration lente retarde chaque pod, et un pod de l'ancienne version qui redémarre pendant la mise à jour… ne migre pas (il n'a que les anciennes migrations) — c'est sans danger avec *expand / contract*. Le Job séparé (déployé avant l'application par l'outil de livraison, ou hook de synchronisation d'Argo CD au M20 — Argo CD sait traduire les annotations `helm.sh/hook`) est la forme la plus propre en GitOps.
- **Comptes séparés.** Le README de MédiAgenda le note : migrer exige `CREATE`, servir non. Le chart utilise ici le même Secret (`mediagenda-db-app`, propriétaire de la base) ; une étape de durcissement (M26) donnera au Job un Secret de rôle « migrateur » et à l'API un rôle limité.

**Alternatives**

- Flyway ou Liquibase dans un conteneur dédié : même format de fichiers (`V<n>__…`), plus de fonctions (*repair*, *undo* payant) ; `mediagenda.migrate` suffit au lab.
- Opérateur de schéma (Atlas, SchemaHero) : déclaratif, encore peu répandu.

**Pièges classiques**

- `hook-delete-policy: hook-succeeded` sur le Job : on perd le journal des migrations réussies, et en cas d'échec on garde le Job… mais pas celui d'avant.
- Hook sans `before-hook-creation` : la montée suivante échoue (`jobs.batch "mediagenda-migrations" already exists`).
- `pre-install` + base rendue par le même chart : installation qui ne termine jamais.
- Compte de service ou politique réseau du chart utilisés par un hook `pre-install` : pod jamais créé ou base injoignable, Helm attend jusqu'au délai.
- Croire que `--rollback-on-failure` défait la migration.

**En production chez MédiSphère**

Sous Kustomize (recette, prod), le conteneur d'initialisation ; au M20, un Job de synchronisation d'Argo CD en `PreSync`. Toute migration est relue par l'équipe Plateforme avec la grille *expand / contract*, et la sauvegarde continue de CNPG (M16-E19) est vérifiée **avant** chaque migration de production : le seul vrai retour arrière d'un schéma est une restauration à un instant donné.
