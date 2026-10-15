# Module 17 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Testé** pour ce corrigé : Helm 4.3.0, helm-diff 3.15.15, helm-unittest 1.2.1, Kustomize 5.8.2 (et 5.8.1 de kubectl 1.36.5), Helmfile 1.8.1, Cosign 3.1.3, images `alpine/helm:4.3.0` et `quay.io/helmpack/chart-testing:v3.15.0`. Le banc d'essai était un serveur d'API Kubernetes 1.36 et etcd, sans nœuds ni contrôleurs, plus un registre OCI local. Sur ce banc, les points suivants ont été rejoués :
- chaîne du pipeline : `helm lint --strict`, `ct lint --skip-helm-dependencies`, `helm unittest`, `helm package --version`, `helm push`, `cosign sign` et `cosign verify` sans journal de transparence, installation par digest ;
- conflits de propriété des champs entre `helm` et un gestionnaire `kubectl-*` ;
- `helm diff upgrade` avec et sans `--three-way-merge` ;
- décodage du Secret de release.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- Harbor 2.15 (TLS de la PKI interne, robot de projet, immuabilité des étiquettes du projet `charts`) : la chaîne n'a été rejouée que contre un registre OCI local en HTTP. La façon dont Harbor présente une signature Cosign 3 sur un artefact de chart (accessoire `signature.cosign`, ou référent OCI seulement) est à vérifier. Le check E13 accepte l'un ou l'autre.
- Racine de la PKI dans les jobs : variable d'instance de type fichier `MEDISPHERE_ROOT_CA` (M13) pour Helm (`--ca-file`) et Git (`GIT_SSL_CAINFO`) ; le job de signature utilise l'image outillée `plateforme/outils-supply-chain` du M13-E09, qui embarque déjà la racine, la clé publique et la configuration de signature.
- Cosign 3.1 : signature avec la configuration de signature sans service du M13-E07 (`--signing-config`), comme les images. Les anciennes options `--use-signing-config=false --tlog-upload=false` fonctionnent encore, avec un avertissement de dépréciation (sortie réelle constatée) : ne les utilise plus.
- Comportement de cert-manager pendant sa montée de correctif (E16) : interruption du webhook, durée.
- Nom du gestionnaire de champs du contrôleur HPA (E22, rappelé en E14) : `kube-controller-manager` avec la sous-ressource `scale`.

Fichiers de solution : `corrige/fichiers/M17-E13/` à `M17-E18/`. Le chart de départ est celui de fin de palier 2 ([`M17-E12/chart/`](fichiers/M17-E12/chart/)) ; les fichiers du palier 3 ne reprennent que ce qui change.

---

### M17-E13 — Le pipeline du chart

**Solution**

Fichiers (projet `mediagenda/chart`) :
- [`.gitlab-ci.yml`](fichiers/M17-E13/chart/.gitlab-ci.yml) ;
- [`.releaserc.json`](fichiers/M17-E13/chart/.releaserc.json) ;
- [`ct.yaml`](fichiers/M17-E13/chart/ct.yaml), modifié ;
- [`.gitlab/merge_request_templates/Défaut.md`](fichiers/M17-E13/chart/.gitlab/merge_request_templates/Défaut.md) ;
- `cosign.pub`, copie de `docs/registre/cosign.pub`.

*1. Inventaire des outils.* On ouvre les images avant de bâtir le pipeline :

```
admin@adm01:~$ docker run --rm --entrypoint sh registry.par1.medisphere.internal/quay/helmpack/chart-testing:v3.15.0 -c 'helm version --short; ct version | head -1'
v3.16.4+g7877b45
Version:	 v3.15.0
admin@adm01:~$ docker run --rm --entrypoint helm registry.par1.medisphere.internal/dockerhub/alpine/helm:4.3.0 version --short
v4.3.0+gbec5b06
```

`docker` n'est pas installé sur `adm01` ? Lance ces commandes sur `runner02`. L'image de chart-testing embarque **Helm 3.16**. On garde donc Helm 4 pour tout ce qui produit le paquet, et `ct lint` ne sert qu'à ce qu'il fait de propre :
- schéma de `Chart.yaml` ;
- yamllint ;
- `helm lint` avec chaque `ci/*-values.yaml`.

Un chart `apiVersion: v2` est le même pour Helm 3 et Helm 4. Les dépendances OCI sont construites par Helm 4 dans le job `helm-lint`, passées en artefact, et `ct lint --skip-helm-dependencies` ne contacte plus Harbor. C'est plus simple et plus sûr que de faire parler Helm 3 à Harbor avec la PKI interne.

*2. Les étiquettes et le gabarit.* `templates/qualite.yml` (M01-E24) se termine par « Pas de pipeline sur les étiquettes ». Dans GitLab, un mot-clé de premier niveau défini dans le fichier du projet **remplace** celui d'un `include`, et les tableaux ne se fusionnent pas. Le projet redéfinit donc `workflow:` (les quatre règles du gabarit, plus `$CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/`) et `stages:` (ajout de `publication`). C'est un écart délibéré au gabarit, écrit en tête du fichier. La bonne suite est un gabarit `helm-chart.yml` partagé (« Pour aller plus loin »).

*3. Version.* `release.yml` (semantic-release sur `runner01`) pose `vX.Y.Z` sur `main`. Rien n'est commité dans `main`, conformément au gabarit. La version n'est donc pas dans `Chart.yaml` : `helm package --version "${CI_COMMIT_TAG#v}"` la reçoit de l'étiquette, et `appVersion` reste celle de `Chart.yaml` (l'image). Conséquences :
- `ct.yaml` passe à `check-version-increment: false`. Sinon, chaque MR échoue : personne ne modifie `version`.
- Pour continuer l'historique publié à la main en M17-E08, pose une fois l'étiquette `v0.5.0` sur le commit qui correspond au paquet 0.5.0 :

```
admin@adm01:~/src/mediagenda-chart$ git tag -a v0.5.0 <SHA-DU-COMMIT-0.5.0> -m "chart 0.5.0 (publié à la main, M17-E08)"
admin@adm01:~/src/mediagenda-chart$ git push origin v0.5.0
```

Sans cette étiquette, semantic-release considère qu'il n'y a jamais eu de version et publie `1.0.0`.

> ⚠️ Pousser `v0.5.0` déclenche un pipeline d'étiquette. Le job `paquet` refuse de republier 0.5.0 (version déjà présente) : c'est attendu, et c'est le critère « relancer échoue proprement ».

Avec un chart en 0.x, `feat:` donne une mineure (0.6.0) et `fix:` un correctif (0.5.1). Un `feat!:` ou un pied de page `BREAKING CHANGE:` donne une majeure (1.0.0) : semantic-release ne traite pas 0.x à part. Pour un chart, une rupture, c'est par exemple une valeur renommée ou supprimée, ou un objet renommé, qui forcerait une réinstallation.

*4. Variables et robots.* Dans Harbor (projet `charts` → Robots), on crée deux robots :

| Robot | Droits | Variables (groupe `mediagenda`, comme en M17-E08) | Protégée | Masquée |
|---|---|---|---|---|
| `robot$charts+ci` | push + pull sur `charts` | `HARBOR_CHARTS_USER`, `HARBOR_CHARTS_TOKEN` | oui | jeton seulement (le nom contient `$` : non développé) |
| `robot$charts+lecture` | pull sur `charts` | `HARBOR_CHARTS_RO_USER`, `HARBOR_CHARTS_RO_TOKEN` | **non** | jeton seulement |

Le second robot existe parce que les pipelines de MR, sur des branches non protégées, ne voient pas les variables protégées. Sans lui, `helm dependency build` (dépendance `valkey` dans `charts`) échoue sur chaque MR. Un robot en lecture seule exposé aux branches est un risque acceptable : `charts` ne contient rien de secret, et une fuite ne permet ni d'écrire ni de signer. Écris-le dans la MR. `COSIGN_PRIVATE_KEY` et `COSIGN_PASSWORD` sont protégées (M13). Les étiquettes `v*` doivent être protégées (création par les mainteneurs et `bot-release`), sinon le pipeline d'étiquette ne voit pas ces variables.

*5. Publication.* Les jobs `paquet`, `pousser` et `signer` ne tournent que sur une étiquette protégée.
- `paquet` vérifie d'abord que la version n'existe pas (`helm show chart … --version`). L'immuabilité des étiquettes du projet `charts` (M13) le refuserait aussi, mais avec un `412` peu parlant.
- `pousser` capture le digest affiché par `helm push` (`Digest: sha256:…`, sur la sortie standard) et le transmet par un artefact `dotenv`.
- `signer` tourne dans l'image outillée du M13-E09 (`plateforme/outils-supply-chain`) : il signe `registry…/charts/mediagenda@sha256:…`, **jamais** l'étiquette, avec la configuration de signature sans journal embarquée, puis vérifie avec la clé publique embarquée (`/etc/medisphere/cosign.pub`, copie de `docs/registre/cosign.pub`). La vérification avec la clé publique prouve que la clé privée de CI correspond bien à la clé publiée.

```
cosign sign --key "$COSIGN_PRIVATE_KEY" --signing-config /etc/medisphere/signing-config.json "$REF"
cosign verify --key /etc/medisphere/cosign.pub --insecure-ignore-tlog=true "$REF"
```

`COSIGN_PRIVATE_KEY` est une variable de type **fichier** (son contenu est écrit dans un fichier temporaire, la variable contient le chemin) : d'où `--key "$COSIGN_PRIVATE_KEY"` et non `env://`, exactement comme dans `supply-chain.yml` du M13. Sans `--signing-config`, Cosign 3 enverrait l'entrée au Rekor public sans poser de question.

*6. Vérifications.*

```
admin@adm01:~$ helm show chart oci://registry.par1.medisphere.internal/charts/mediagenda --version 0.6.0 | grep -E '^(version|appVersion)'
admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true \
    registry.par1.medisphere.internal/charts/mediagenda@sha256:<DIGEST> | jq '.[0].critical.image'
admin@adm01:~$ cosign tree registry.par1.medisphere.internal/charts/mediagenda@sha256:<DIGEST>
└── 🔗 https://sigstore.dev/cosign/sign/v1 artifacts via OCI referrer: …
```

`cosign tree` montre que Cosign 3 attache la signature comme **référent OCI 1.1**, et non plus sous une étiquette `sha256-….sig`. Pour la MR de test rouge, une valeur hors schéma (`replicaCount: "2"`) fait échouer `helm-lint` et `helm-unittest`. Avec « Pipelines must succeed », la fusion est grisée.

**Explications**

Le pipeline sépare **vérifier** (sur chaque MR, sans droit d'écriture) et **publier** (seulement sur une étiquette protégée, avec les droits). La publication n'a lieu qu'une fois par version, et la version naît des commits. Un chart publié est donc un artefact immuable, tracé jusqu'au commit et signé par une clé que personne ne manipule. En recette, on peut en exiger la signature avant de le rendre (`outils/rendre-base.sh` de M17-E09, qui vérifie la signature du digest avant de rendre). Signer par digest est indispensable : une étiquette OCI est un pointeur, le digest est le contenu.

**Alternatives**
- **Version écrite dans `Chart.yaml` par un commit de release** (`@semantic-release/git`) : `Chart.yaml` reste exact dans le dépôt, mais il faut un bot qui pousse sur une `main` protégée, et un pipeline par commit de release (`[skip ci]`). Le gabarit M01 l'a écarté.
- **Provenance Helm** (`helm package --sign`, PGP, fichier `.prov`) : ancienne et peu outillée pour l'OCI. Cosign est déjà la norme des images chez MédiSphère (M13), et Harbor l'affiche.
- **`ct install`** dans le pipeline (installation réelle dans un espace jetable) : le meilleur test, mais il exige un accès de la CI au cluster (M19).
- **kubeconform** sur le rendu, pour valider contre les schémas de l'API sans cluster : vu au M29. Ici, le schéma de valeurs et helm-unittest couvrent l'essentiel.

**Pièges classiques**
- Croire que `ct lint` utilise Helm 4 : il utilise le Helm de son image.
- Oublier `GIT_DEPTH: "0"` dans `ct-lint` : ct compare à `origin/main` et échoue sur un clone superficiel.
- Installer helm-unittest sans version ni `--verify=false`. Sans version, le pipeline change tout seul. Sans `--verify=false`, Helm 4 refuse un greffon non signé depuis Git.
- Signer l'étiquette (`…:0.6.0`) : la signature suit le digest résolu au moment de la signature, et ne dit rien du jour où l'étiquette serait déplacée.
- Laisser `helm registry login … --password "$TOKEN"` : le secret passe en argument de processus. Toujours `--password-stdin`.
- Un pipeline d'étiquette qui ne démarre pas : `workflow:` du gabarit, ou étiquette non protégée (variables absentes, jobs ignorés par `CI_COMMIT_REF_PROTECTED`).

**En production chez MédiSphère**

On ajouterait :
- un gabarit `helm-chart.yml` partagé ;
- un `ct install` dans un espace jetable dès que la CI aura un compte sur le cluster (M19) ;
- une politique d'admission qui refuse un rendu dont le chart n'est pas signé : Argo CD au M20 avec vérification, Kyverno au M26 ;
- la rotation des jetons des robots `charts`, inscrits au registre des secrets.

---

### M17-E14 — Différences et dérive : `helm diff`, `kubectl diff`, *server-side apply*

**Solution**

*1. Prévisualiser.* Dans la copie du chart, la limite passe à 448 Mi (`resources.limits.memory`). Puis :

```
admin@adm01:~/src/mediagenda-chart$ helm diff upgrade mediagenda charts/mediagenda -n mediagenda-dev \
    --reuse-values -f valeurs-dev.yaml --context 3
mediagenda-dev, mediagenda, Deployment (apps) has changed:
…
-             memory: 384Mi
+             memory: 448Mi
```

Reprends les valeurs que la release du dev utilise vraiment : `helm get values mediagenda -n mediagenda-dev` les affiche. `helm get manifest` comparé à `helm template` donne le même diff ici, mais à la main : pas de masquage des Secrets, pas de regroupement par objet, et surtout aucun rendu côté serveur. `helm diff` fait le rendu comme `helm upgrade` : mêmes valeurs, mêmes `lookup` avec `--dry-run=server`, même validation contre l'API.

*2. Options.*
- `--server-side auto` (défaut) suit la méthode de la release. `helm get` montre `apply_method: ssa` pour une release installée par Helm 4.
- `--three-way-merge` fait entrer l'**état réel** du cluster dans la comparaison.
- `--context 3` donne un diff lisible en MR.
- Les Secrets sont masqués par défaut : `--show-secrets` les afficherait, à ne jamais utiliser en CI.
- `--normalize-manifests` retire les différences de style.

Pour une revue, on retient `--three-way-merge --context 3 --normalize-manifests`.

*3. Gestionnaires.*

```
admin@adm01:~$ kubectl get deploy mediagenda -n mediagenda-dev --show-managed-fields -o json \
    | jq -c '.metadata.managedFields[] | {manager, operation, subresource}'
{"manager":"helm","operation":"Apply","subresource":null}
{"manager":"kube-controller-manager","operation":"Update","subresource":"status"}
```

Sur le dev, `helm` possède en `Apply` tout ce que le chart rend, et le contrôleur ne possède que `status`. En recette, le gestionnaire `Apply` est `kubectl` : c'est le nom par défaut de `kubectl apply --server-side`, utilisé en M17-E09. Si quelqu'un a appliqué un jour côté client, un gestionnaire `kubectl-client-side-apply` (opération `Update`) apparaît, avec l'annotation `kubectl.kubernetes.io/last-applied-configuration`. Avant M17-E09, la recette du M16 avait d'autres gestionnaires : c'est la trace de la reprise.

*4. Dérive.* Après `kubectl edit`, un gestionnaire `kubectl-edit` (opération `Update`) apparaît et **possède** `env[name="MEDIAGENDA_LOG_LEVEL"].value`. `helm diff upgrade` sans `--three-way-merge` ne montre **rien** : il compare le manifeste stocké dans la release (`INFO`) au nouveau rendu (`INFO`). Avec `--three-way-merge`, la ligne apparaît :

```
-                 value: DEBUG
+                 value: INFO
```

*5. Le `helm upgrade` échoue :*

```
Error: UPGRADE FAILED: conflict occurred while applying object mediagenda-dev/mediagenda apps/v1, Kind=Deployment:
Apply failed with 1 conflict: conflict with "kubectl-edit" using apps/v1:
.spec.template.spec.containers[name="api"].env[name="MEDIAGENDA_LOG_LEVEL"].value
```

La release passe en `failed` et une révision `failed` s'ajoute à l'historique. Rien n'a été modifié dans l'objet. Les trois corrections :

| Méthode | Commande | Effet sur `managedFields` |
|---|---|---|
| Rendre le champ à Helm | `helm upgrade … --force-conflicts` | `kubectl-edit` perd le champ (son entrée disparaît s'il ne possède plus rien) ; la valeur du chart s'applique |
| Défaire la modification | `kubectl edit` → `INFO`, puis `helm upgrade` | `helm` et `kubectl-edit` **copossèdent** le champ (même valeur) : l'upgrade passe… |
| Retirer la propriété | `kubectl patch --type json -p '[{"op":"remove","path":"/metadata/managedFields/<i>"}]'`, puis `helm upgrade` | l'entrée `kubectl-edit` disparaît ; Helm repose sa valeur au prochain `Apply` |

Le piège est la deuxième ligne. Si le chart change **plus tard** la valeur de ce champ, l'upgrade échoue à nouveau en conflit avec `kubectl-edit`, des semaines après la modification. Comportement reproduit sur le banc d'essai. Seules la première et la troisième méthode rendent un objet propre. `<i>` est l'indice de l'entrée dans `.metadata.managedFields` (`jq 'map(.manager) | index("kubectl-edit")'`). Une mise à jour qui ne touche que `managedFields` n'ajoute pas de gestionnaire.

*6. Kustomize.*

```
admin@adm01:~/src/mediagenda-deploiement$ kubectl diff --server-side -k overlays/recette
admin@adm01:~/src/mediagenda-deploiement$ echo $?
0
admin@adm01:~/src/mediagenda-deploiement$ kubectl diff --server-side --field-manager=essai -k overlays/recette
```

Sans `--field-manager`, `kubectl apply --server-side` et `kubectl diff --server-side` s'identifient comme `kubectl`. Avec un autre nom, le diff montre au mieux l'ajout d'une entrée `managedFields`. En cas de valeur différente, il échoue en conflit (`kubectl diff --server-side` simule un `Apply`). Pourquoi toujours le même nom : le gestionnaire est l'identité du propriétaire. Si un champ est retiré du manifeste, il n'est supprimé que si **son** propriétaire l'abandonne. Avec deux noms, l'autre propriétaire le garde : un champ fantôme.

*7.* Exemple de [`derive.md`](fichiers/M17-E14/medisphere/docs/kubernetes/packaging/derive.md) et de [gabarit de MR](fichiers/M17-E13/chart/.gitlab/merge_request_templates/Défaut.md).

**Explications**

Helm 3 appliquait un *3-way merge* côté client : ancien manifeste, état réel, nouveau manifeste. Une modification manuelle d'un champ que le chart ne changeait pas survivait. Helm 4 installe en SSA : le serveur tient la propriété **champ par champ**. Un `Apply` qui voudrait changer un champ possédé par un autre est refusé, au lieu d'écraser en silence ou d'ignorer. C'est plus sûr, mais cela rend la dérive bloquante : le prochain déploiement échoue. Une release créée par Helm 3 reste en client-side apply aux upgrades suivants, sauf `--server-side=true` (`auto` suit la méthode précédente).

**Alternatives**
- `helm upgrade --force-conflicts` systématique : la dérive est toujours écrasée, mais en silence, et on ne saura jamais qui l'a créée. À réserver à la correction après analyse.
- Détecter la dérive en continu : `helmfile diff --detailed-exitcode` planifié (E16), puis Argo CD (M20), qui affiche « OutOfSync » et peut réparer seul (*self-heal*).

**Pièges classiques**
- Lire `helm diff` sans `--three-way-merge` et conclure « rien ne change ».
- Confondre `--force-conflicts` (SSA : prendre la propriété) et `--force-replace` (supprimer puis recréer l'objet : interruption).
- Appliquer la recette avec `kubectl apply -k` côté client un jour et `--server-side` le lendemain : deux propriétaires.

**En production chez MédiSphère**

Le RBAC ne donne `update`/`patch` sur les Deployments de `mediagenda-recette` et `-prod` qu'au compte de déploiement : plus personne ne fait de `kubectl edit` (M14-E11, puis M20). Le diff à trois voies est collé dans chaque MR.

---

### M17-E15 — Des paquets sans secrets

**Solution**

*1. Démonstration.*

```
admin@adm01:~/src/mediagenda-chart$ helm install fuite charts/mediagenda -n wb-essais \
    --set medisphere.environnement=dev --set httpRoute.enabled=false \
    --set config.extraEnv.MEDIAGENDA_JETON=jeton-de-demo-1234
admin@adm01:~$ helm get values fuite -n wb-essais
config:
  extraEnv:
    MEDIAGENDA_JETON: jeton-de-demo-1234
admin@adm01:~$ kubectl get secret sh.helm.release.v1.fuite.v1 -n wb-essais -o jsonpath='{.data.release}' \
    | base64 -d | base64 -d | gzip -dc | jq -r '.config.config.extraEnv'
{ "MEDIAGENDA_JETON": "jeton-de-demo-1234" }
admin@adm01:~$ kubectl get cm fuite-mediagenda -n wb-essais -o jsonpath='{.data.MEDIAGENDA_JETON}'
```

Selon tes valeurs, l'installation reste en attente : pas de base dans `wb-essais`. Ce n'est pas le sujet, puisque la release **et** son Secret sont écrits avant l'attente. Lucas se trompe : c'est un **encodage** (base64 deux fois, gzip), pas un chiffrement. Le chiffrement au repos d'etcd (M14-E28) protège les sauvegardes et le disque. Il ne protège rien face à l'API. Les lecteurs :
- `kubectl auth can-i get secrets -n wb-essais --as=…` pour chaque groupe ;
- `kubectl get rolebindings,clusterrolebindings -A -o wide` pour les liaisons qui le permettent ;
- dans le lab : `medisphere:plateforme-admins`, le ClusterRole `admin`/`edit` lié dans l'espace, les comptes de service des opérateurs.

`wb-checks` ne lit pas les Secrets (M14-E06), et c'est voulu. Nettoyage :

```
admin@adm01:~$ helm uninstall fuite -n wb-essais
admin@adm01:~$ kubectl get secret -n wb-essais -l owner=helm,name=fuite
No resources found in wb-essais namespace.
```

Avec `--keep-history`, les Secrets de release restent, et la valeur avec eux.

*2. Audit des releases.* [`outils/audit-valeurs-helm.sh`](fichiers/M17-E15/k8s/outils/audit-valeurs-helm.sh) parcourt `helm list -A`. Pour chaque release, il lit `helm get values -o json`. Il signale tout chemin dont la dernière clé ressemble à un secret, avec une valeur non vide, ou toute valeur qui en a la forme (URL avec identifiants, bloc PEM). Il affiche le chemin et jamais la valeur, et sort en 1 s'il a trouvé quelque chose. Trouvailles typiques au sortir des modules 15 et 16 :
- `external-dns` : `rfc2136.tsigSecret` passé en valeur. Le chart accepte une variable d'environnement venant d'un Secret : `env` + `valueFrom.secretKeyRef`, avec `--rfc2136-tsig-secret` lu dans l'environnement (consulte `helm show values` et `external-dns --help`). Le Secret `externaldns-tsig` est créé par le script de M15, depuis Vault Ansible.
- `velero` : `credentials.secretContents.cloud`. Le chart sait référencer `credentials.existingSecret`. On crée `velero-s3` hors de Helmfile, depuis `~/.config/workbook/s3-velero.env` (script de M16).

Après correction : `helmfile diff` montre la valeur retirée et la référence ajoutée (secrets masqués). `helmfile apply -l name=<release>`, puis le script renvoie 0. Les **anciennes révisions** contiennent toujours la valeur, dans leurs Secrets de release (`historyMax`). Une valeur sortie de Helm est une valeur **compromise** : on la renouvelle (clé TSIG, compte S3), puis on purge l'historique en réinstallant, ou on attend que `historyMax` l'efface.

*3. Dépôts.*

```
admin@adm01:~/src/mediagenda-deploiement$ gitleaks git --no-banner --redact .
admin@adm01:~/src/mediagenda-deploiement$ for o in overlays/*/; do kubectl kustomize "$o" | yq 'select(.kind == "Secret") | .metadata.name'; done
```

Aucun Secret attendu. Un `secretGenerator` avec un fichier `.env` ignoré par Git produirait un Secret de plus au rendu : le fichier vit sur un poste, et Argo CD (M20) ne pourra pas le rendre. On le sort.

*4. Garde-fou.*
- Job [`sans-secret`](fichiers/M17-E15/chart/.gitlab-ci.extrait.yml) : rend avec chaque jeu de valeurs, y compris `valkey.enabled=true` (le sous-chart Valkey sait créer un Secret si son authentification est activée), puis `yq 'select(.kind == "Secret")'`, et échoue si la sortie n'est pas vide.
- Test [`tests/secrets_test.yaml`](fichiers/M17-E15/chart/charts/mediagenda/tests/secrets_test.yaml) : `MEDIAGENDA_DB_URL` a un `valueFrom.secretKeyRef` et pas de `value`. La variante `existingSecret` reste prise en compte.

*5.* Registre des secrets : [`secrets.md`](fichiers/M17-E15/medisphere/docs/kubernetes/packaging/secrets.md).

*6. Réponse à Sophie :*

> Helm ne protège pas les valeurs : elles sont stockées en clair, simplement compressées, dans des Secrets lisibles par quiconque peut lire les Secrets de l'espace. Nos charts et overlays ne portent donc aucun secret. Les mots de passe sont dans des Secrets créés hors des paquets : par l'opérateur PostgreSQL, ou par nos scripts depuis Vault Ansible. Le pipeline du chart refuse tout rendu qui contiendrait un Secret. Un script d'audit vérifie qu'aucune release n'en a dans ses valeurs. Deux valeurs sorties des releases ont été renouvelées. Le registre `docs/kubernetes/packaging/secrets.md` dit qui crée chaque Secret et comment on le change. Au M25, Vault et External Secrets Operator remplaceront les scripts.

**Explications**

Un paquet sans secret est réutilisable partout : même chart en dev et en prod, publiable, lisible en revue, rendu par Argo CD. Le secret, lui, a un cycle de vie différent : rotation, révocation, propriétaire. Le motif `existingSecret`/`secretKeyRef` découple les deux. Le chart sait **où** lire, jamais **quoi**.

**Alternatives**
- **SOPS + age** dans le dépôt, déchiffré au rendu : le secret est versionné, mais chiffré. Il faut une clé au rendu, et le résultat finit quand même dans un Secret, voire dans la release Helm si on le passe en valeur. Traité au M25.
- **External Secrets Operator** : le Secret Kubernetes est créé depuis Vault par l'opérateur. Le chart référence un Secret qui existera. C'est la cible (M25).
- **Sealed Secrets** : chiffré pour un seul cluster, en comparaison au M25.

**Pièges classiques**
- Corriger la valeur sans renouveler le secret : il reste lisible dans l'historique des releases, les sauvegardes Velero (M16) et les instantanés etcd.
- Un script d'audit qui affiche la valeur trouvée dans le journal de CI.
- `lookup` pour « garder » un mot de passe généré : `helm template` (et donc `outils/rendre-base.sh`) n'a pas accès au cluster et en génère un nouveau à chaque rendu.

**En production chez MédiSphère**

Le registre des secrets est relu à chaque revue HDS. L'audit des valeurs devient un job planifié de `plateforme/k8s`, puis une règle Kyverno au M26 : refuser une ConfigMap ou une variable qui contient une URL avec identifiants.

---

### M17-E16 — Monter un composant de plateforme par Helmfile

**Solution**

Fichiers (projet `plateforme/k8s`, structure de M17-E10) :
- [`releases/20-certificats-dns.yaml.gotmpl`](fichiers/M17-E16/k8s/releases/20-certificats-dns.yaml.gotmpl) ;
- chart local [`charts/emetteurs/`](fichiers/M17-E16/k8s/charts/emetteurs/) ;
- runbook [RB-172](fichiers/M17-E16/medisphere/docs/kubernetes/packaging/runbooks/RB-172-montee-composant.md).

*1. Inventaire.*

```
admin@adm01:~/src/k8s$ helm list -A -o json | jq -r '.[] | "\(.namespace)\t\(.name)\t\(.chart)"' | sort
admin@adm01:~/src/k8s$ skopeo list-tags docker://quay.io/jetstack/charts/cert-manager | jq -r '.Tags[]' | grep '^v1\.21\.' | sort -V | tail -3
v1.21.0
v1.21.1
v1.21.2
admin@adm01:~/src/k8s$ C=oci://quay.io/jetstack/charts/cert-manager
admin@adm01:~/src/k8s$ diff <(helm show values $C --version v1.21.1) <(helm show values $C --version v1.21.2)
```

cert-manager vient d'un registre OCI (M15) : pas d'index, donc pas de `helm search repo` ; les versions sont les étiquettes du dépôt OCI (`skopeo list-tags`, ou la page des versions du projet). Pour les charts en dépôt HTTP (metrics-server, ceph-csi, cnpg, velero, external-dns) : `helm search repo <dépôt>/<chart> --versions`.

À l'écriture du module, M17-E10 épingle cert-manager en `v1.21.1`, et `v1.21.2` (10/09/2026) est le dernier correctif de la mineure : c'est la cible. Les notes d'un correctif de cert-manager listent des corrections et des montées de dépendances : pas de nouvelles CRD, pas de changement de valeurs. Vérifie-le, ne le suppose pas. Fais le tableau pour toutes les releases : metrics-server, ceph-csi, cnpg, plugin-barman-cloud, velero, external-dns, Cilium. Il servira à la répétition et aux prochaines MR (Renovate, M13).

*2. `needs` et la release `emetteurs`.* Avant, le `ClusterIssuer` était appliqué à la main après cert-manager. Après une réinstallation du cluster, oublier cette étape ou l'inverser fait échouer tout certificat. Le chart local `charts/emetteurs` le rend, avec la spécification **exacte** de M15 :

```
admin@adm01:~$ kubectl get clusterissuer step-ca-acme -o yaml
```

On compare champ par champ avant la reprise. La release déclare `needs: [cert-manager/cert-manager]`, au format `espace/nom`, obligatoire quand la release a un espace. Les deux releases sont dans le **même** fichier de releases : `needs` relie des releases d'un même état Helmfile. Entre fichiers de `releases/`, c'est l'ordre des sous-helmfiles qui joue.

Première application, avec reprise de l'objet existant : on ajoute `takeOwnership: true` **temporairement** sur la release `emetteurs`. Helmfile le traduit en `--take-ownership` de Helm 4.

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=emetteurs diff
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=emetteurs apply
admin@adm01:~$ kubectl get clusterissuer step-ca-acme --show-managed-fields -o json | jq '.metadata.annotations, .metadata.uid, [.metadata.managedFields[].manager]'
{ "meta.helm.sh/release-name": "emetteurs", "meta.helm.sh/release-namespace": "cert-manager" }
"<MÊME UID QU'AVANT>"
["helm", "kubectl-client-side-apply", "cert-manager-clusterissuers"]
```

Sans l'option, Helm refuse : `invalid ownership metadata; label validation error: missing key "app.kubernetes.io/managed-by"`. Avec elle, l'objet garde son UID (il n'est pas recréé), et Helm ajoute ses étiquettes et annotations. Il reste un **copropriétaire** : l'outil qui l'avait créé au M15 (`kubectl-client-side-apply`, ou `kubectl` en SSA). Le gestionnaire du contrôleur, qui ne possède que `status`, n'est pas en cause. Tant que les valeurs sont identiques, rien ne se voit. Au premier changement du `ClusterIssuer` par le chart, Helm échouera en conflit (M17-E14). On retire donc tout de suite l'entrée de l'ancien outil dans `managedFields`, ou on fait une fois `--force-conflicts`, puis on retire `takeOwnership` dans une seconde MR. Comportement reproduit pendant la rédaction sur une ConfigMap.

```
admin@adm01:~/src/k8s$ helmfile -e par1 build | yq '.releases[] | [.name, .needs]'
admin@adm01:~/src/k8s$ helmfile -e par1 list
```

`helmfile -e par1 -l composant=cert-manager apply` : avec sélecteur, `needs` est **ignoré** par défaut (`--skip-needs`, vrai par défaut). Seule la cible est appliquée, ce qu'on veut ici. `--include-needs` ajouterait les dépendances de la cible, jamais ses dépendants. Sans sélecteur, l'ordre suit le graphe, par groupes successifs. `destroy` suit l'ordre inverse : `emetteurs` est supprimé **avant** cert-manager, sinon le webhook disparu bloquerait la suppression du `ClusterIssuer`.

*3. Retour sur échec.* Sur la release cible :

```yaml
    rollbackOnFailure: true    # Helm 4 : --rollback-on-failure ; exclusif avec « atomic »
    waitForJobs: true
```

`wait`, `timeout` et `historyMax` sont déjà dans `helmDefaults` (`_communs.yaml`, M17-E10). `atomic: true` fonctionnerait aussi : Helmfile 1.8 le traduit en `--rollback-on-failure` sous Helm 4. Mais on garde le nom de Helm 4, pour ne pas lire « atomic » dans le dépôt et « rollback-on-failure » dans les journaux. Commande réelle, lue dans `helmfile -e par1 --debug apply` (forme constatée sur Helmfile 1.8.1) :

```
exec: helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.2 --wait --wait-for-jobs --timeout 600s --rollback-on-failure --namespace cert-manager … --history-max 10
```

(⚠️ À relire sur ta version : pour un dépôt déclaré `oci: true`, Helmfile peut passer à Helm la référence `oci://…` ou une copie locale du chart qu'il a tirée avant ; les options, elles, sont celles-ci.)

Avec Helm 4, `--wait` vaut `watcher` (kstatus). Sans `--wait`, la stratégie par défaut est `hookOnly` : Helm n'attend que les hooks. C'est pour cela que `--rollback-on-failure` force `--wait=watcher` (aide de `helm upgrade`). Fait constaté sur le banc d'essai : un `helmfile apply` interrompu pendant l'attente laisse la release en `pending-install` ou `pending-upgrade`. C'est la panne M17-E19.

*4. Répétition (metrics-server).* On épingle la version précédente ou suivante du chart dans `releases/40-observabilite.yaml.gotmpl`, MR, `helmfile -e par1 -l composant=metrics-server diff`, puis `apply`. Deux retours :

| Méthode | Durée constatée (indicative) | État après |
|---|---|---|
| `helm rollback metrics-server <N> -n kube-system --wait` | ≈ 30 s | cluster revenu ; **dépôt** toujours sur la nouvelle version : `helmfile diff` montre la montée, que le prochain `apply` refera |
| revert de la MR (épinglage précédent) + `helmfile -e par1 -l composant=metrics-server apply` | 3 à 5 min (MR, pipeline, diff) | dépôt et cluster d'accord, `helmfile diff` vide |

En urgence, le `helm rollback` est légitime : c'est le plus rapide. Mais il doit être **suivi** du revert dans le dépôt, sinon n'importe quel `helmfile apply` le défait. C'est la règle écrite dans RB-172.

*5. Le changement.* La MR contient :
- le tableau ;
- `helmfile -e par1 -l composant=cert-manager diff --suppress-secrets --context 3` ;
- le résumé des notes ;
- le retour arrière.

Pour cert-manager, le retour arrière n'est **pas** un `helm rollback` : le projet ne prend pas en charge le retour à une version antérieure. On sauvegarde avant les objets `cert-manager.io` :

```
kubectl get -A issuers,clusterissuers,certificates -o yaml > ~/sauvegardes/cert-manager-<DATE>.yaml
```

et on s'appuie sur la sauvegarde Velero de `cert-manager` (M16). En cas de régression, on corrige vers l'avant (correctif suivant, ou réglage de valeur) ; en dernier recours, désinstallation (CRD conservées, `crds.keep`), réinstallation de la version précédente et réapplication des objets. Après `helmfile -e par1 -l composant=cert-manager apply` :

```
admin@adm01:~$ kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=120s
admin@adm01:~$ kubectl apply -n wb-essais -f ~/sauvegardes/certificat-essai.yaml   # Certificate « essai-montee », émetteur step-ca-acme
admin@adm01:~$ kubectl wait -n wb-essais certificate/essai-montee --for=condition=Ready --timeout=300s
admin@adm01:~$ kubectl delete -n wb-essais certificate/essai-montee secret/essai-montee
admin@adm01:~$ kubectl get certificate -A | grep apps-joker
admin@adm01:~/src/k8s$ helmfile -e par1 diff --detailed-exitcode; echo $?
0
```

Le `Certificate` d'essai :

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: essai-montee }
spec:
  secretName: essai-montee
  dnsNames: [essai-montee.apps.par1.medisphere.internal]
  issuerRef: { kind: ClusterIssuer, name: step-ca-acme }
```

**Explications**

Helmfile transforme une suite de commandes Helm en un **état désiré** relu en MR. `needs` rend l'ordre explicite : on n'a plus à se souvenir qu'un émetteur s'applique après cert-manager. `rollbackOnFailure` + `wait` évitent qu'un échec laisse une release à moitié montée. Mais le vrai retour arrière se décide par composant :
- un composant sans état (metrics-server) se ramène par Helm ;
- un composant qui possède des CRD et des données (cert-manager, CNPG, Velero) se ramène rarement par Helm : on le sauvegarde et on corrige vers l'avant.

**Alternatives**
- `helmfile sync` plutôt qu'`apply` : applique sans diff préalable, toujours. `apply` ne touche que ce qui change.
- Garder l'émetteur en manifeste appliqué par un hook `postsync` de Helmfile : possible, mais l'ordre reste implicite et l'objet hors de toute release.
- Renovate (M13) qui ouvre la MR de version de chart, avec le diff de valeurs : la suite naturelle de l'inventaire.

**Pièges classiques**
- Appliquer sans sélecteur et monter, au passage, tout ce qui avait dérivé ailleurs.
- `atomic` et `rollbackOnFailure` tous deux à `true` : Helmfile les déclare exclusifs.
- Oublier que `--rollback-on-failure` d'une **première** installation désinstalle tout.
- Laisser `takeOwnership` en place, ou garder le copropriétaire du M15 dans `managedFields`.
- `needs` vers une release d'un **autre** fichier de `releases/` : ce n'est pas le même état Helmfile.
- Conclure au succès sur « pods prêts » sans tester une émission de certificat.

**En production chez MédiSphère**

Fenêtre annoncée, montée en dev d'abord (cluster de préproduction au F4), `helmfile diff` planifié chaque nuit (« Pour aller plus loin ») ; Argo CD prendra le relais au M20.

---

### M17-E17 — ADR : Helm, Kustomize ou les deux

**Solution**

Exemple : [`ADR-0170-helm-kustomize.md`](fichiers/M17-E17/medisphere/docs/kubernetes/packaging/adr/ADR-0170-helm-kustomize.md). Il en existe d'autres justes. La décision de l'exemple :
- **application maison** : empaquetée en chart (versionné, testé, signé), **livrée** par Kustomize à partir du rendu commité du chart signé (`chart.env`, `outils/rendre-base.sh`, M17-E09) ; overlays par environnement, sans hooks (migrations en conteneur d'initialisation) ;
- **composant tiers de plateforme** : release Helm décrite par Helmfile (hooks et CRD du fournisseur respectés), Argo CD au M20 ;
- **objets de configuration de la plateforme** (émetteurs, politiques, quotas) : manifestes Kustomize dans `plateforme/k8s`.

**Grille d'auto-évaluation** (sur 20)

| Critère | Points |
|---|---|
| Contexte complet : existant, arrivées (Argo CD, MédiDoc), contraintes HDS et souveraineté, Helm 4 et SSA | 3 |
| Au moins 7 critères pondérés, dont hooks, état stocké, dérive, Argo CD | 3 |
| Quatre options réellement évaluées, chaque note appuyée sur un fait (exercice, documentation) | 4 |
| Décision formulée en règle par type de logiciel, avec le sort des hooks et de la configuration d'environnement | 4 |
| Conséquences négatives honnêtes (double paramétrage, hooks perdus, banc Helm du dev) avec actions rattachées | 3 |
| Lisible en deux pages, gabarit MADR, liens vers les exercices | 3 |

**Explications**

Le cœur de la décision tient en deux phrases. Helm est un bon **format de paquet** : versions, dépendances, schéma, tests, publication OCI signée. Kustomize est un bon **format de livraison** déclaratif, sans état dans le cluster, que GitOps applique tel quel. Commiter le rendu du chart (plutôt que le gonfler à chaque `kustomize build` par `helmCharts`) rend la MR de montée de version lisible ligne à ligne et fige le contenu par son digest. Argo CD rend les charts **sans** exécuter `helm install`. Il traduit certains hooks en ses propres phases (*sync hooks*), mais pas tous. Un chart qui compte sur l'ordre des hooks Helm en production se comportera différemment au M20 : mieux vaut le savoir maintenant.

**Pièges classiques**
- Un ADR qui compare les syntaxes au lieu des conséquences d'exploitation.
- Oublier les charts tiers : on ne réécrit pas cert-manager en Kustomize.
- Ne pas dire ce que devient le dev (release Helm).

---

### M17-E18 — Livrer une nouvelle version de MédiAgenda en temps limité

**Solution**

Déroulé de référence (≈ 45 min de pipelines et de gestes, sur une chaîne en place) :

| Jalon | Geste | Projet |
|---|---|---|
| T0 → T1 (≈ 10 min) | MR `feat: canal de prise (V3) et variable MEDIAGENDA_ENVIRONNEMENT obligatoire` (application du correctif de Julien), revue, fusion → semantic-release `v1.1.0` → pipeline M13 : image `medisphere/mediagenda-api:v1.1.0` construite, analysée, signée | `mediagenda/api` |
| T1 → T2 (≈ 10 min) | MR `feat: variable MEDIAGENDA_ENVIRONNEMENT, application 1.1.0` : `appVersion: "1.1.0"`, variable rendue depuis `medisphere.environnement` (déjà obligatoire et énumérée dans le schéma), tests mis à jour → étiquette `vX.Y.0` → chart publié et signé | `mediagenda/chart` |
| T2 → T3 (≈ 8 min) | `helm upgrade mediagenda oci://…/charts/mediagenda --version X.Y.0 -n mediagenda-dev -f …` : le hook pre-upgrade applique V3 sur la base du dev, puis rotation | release Helm du dev |
| T3 → T4 (≈ 12 min) | MR : `chart.env` (`CHART_VERSION=X.Y.0`, `CHART_DIGEST`), `outils/rendre-base.sh` (vérifie la signature, régénère `base/rendu/`), `livraison.yaml` de la recette → `v1.1.0`. Fusion, `kubectl diff --server-side -k overlays/recette`, `kubectl apply --server-side -k overlays/recette` ; le conteneur d'initialisation applique V3 sur `mediagenda-db` | `mediagenda/deploiement` |

Modifications du chart : [`M17-E18/chart/`](fichiers/M17-E18/chart/). Le changement minimal est d'ajouter à `mediagenda.envConnexion` (`_helpers.tpl`), commun à l'API et aux migrations :

```yaml
- name: MEDIAGENDA_ENVIRONNEMENT
  value: {{ required "medisphere.environnement est obligatoire (dev, recette ou prod)" .Values.medisphere.environnement | quote }}
```

Les migrations ont besoin de la variable aussi. Le code n'y lit que `MEDIAGENDA_DB_URL`, mais toute la configuration passe par `Settings` pour l'API. La mettre dans le gabarit commun évite d'avoir à s'en souvenir.

**Pièges du dossier** (ce qui fait perdre le plus de temps) :
1. **Déployer l'image 1.1.0 avec l'ancien chart** : l'API sort aussitôt avec le code 2 (`variable(s) obligatoire(s) absente(s) : MEDIAGENDA_ENVIRONNEMENT`), le pod part en `CrashLoopBackOff`. C'est le sens de l'ordre image → chart → dev → recette : la version du chart qui fournit la variable doit précéder l'image qui l'exige.
2. **Migration V3** : elle est **additive** (colonne avec défaut). L'ancienne version de l'API continue de fonctionner sur le nouveau schéma. On peut donc migrer avant de changer d'image, et revenir à `v1.0.0` sans toucher au schéma. Le retour arrière est seulement celui de l'image (`livraison.yaml`). Une migration qui supprimerait ou renommerait une colonne exigerait deux livraisons (*expand/contract*).
3. **Recette sans hook** : la base est rendue sans hooks (`--no-hooks`). La migration passe par le conteneur d'initialisation `migrations` de chaque pod. Elle est idempotente grâce au verrou consultatif et à la table d'historique : le premier pod applique V3, les suivants ne font rien.
4. **Empreinte** : ne modifie jamais `V1__init.sql` ni `V2__index.sql` en appliquant le correctif. La commande de migration s'arrête si l'empreinte d'une version déjà appliquée change.
5. **`images:` dans l'overlay de recette** pour aller plus vite : il l'emporte sur le component `livraison` (voir M17-E21). On ne touche qu'à `livraison.yaml`.

Vérifications à T4 :

```
admin@adm01:~$ curl -s https://mediagenda-recette.apps.par1.medisphere.internal/sante
{"statut":"ok","version":"v1.1.0","environnement":"recette"}
admin@adm01:~$ kubectl logs -n mediagenda-recette deploy/mediagenda -c migrations | tail -1
{… "message": "migrations terminées", "appliquees": ["V3__canal.sql"] …}     # sur le premier pod, [] ensuite
admin@adm01:~$ kubectl get deploy mediagenda -n mediagenda-prod -o jsonpath='{.spec.template.spec.containers[0].image}'
registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.0.0
```

**Retour d'expérience type** : le temps est fait aux deux tiers de pipelines (image, chart). Les gestes humains sont les trois MR et deux applications. Ce qui se réduit :
- l'application de la recette, par Argo CD au M20 (fusion = déploiement) ;
- la MR du chart, souvent mécanique (`appVersion`), par Renovate (M13) ou par un job de l'application qui ouvre la MR.

**En production chez MédiSphère**

La recette validée, la prod se fait par la même MR sur `overlays/prod` (mini-projet), dans une fenêtre, avec le même chart signé : on promeut un **artefact**, on ne reconstruit rien.
