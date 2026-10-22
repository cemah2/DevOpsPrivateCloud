# Module 19 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les solutions complètes sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `…/ci-templates/…` = `plateforme/ci-templates`, `…/ci-labo/…` = `formation/ci-labo`, `…/mediagenda-api/…` = `mediagenda/api`, `…/chart/…` = `mediagenda/chart`, `…/deploiement/…` = `mediagenda/deploiement`, `…/k8s/…` = `plateforme/k8s`, `…/infra/…` = `plateforme/infra`, `…/medisphere/…` = la documentation ; `…/essais/` se pose dans `~/m19/eXX/`. On **superpose** les dossiers dans l'ordre des exercices réalisés ; un fichier d'un exercice plus récent remplace le précédent (le composant `qualite` existe ainsi en v2.0.0 dans `M19-E10/`, en v2.1.0 dans `M19-E13/`, en v2.2.0 dans `M19-E14/`, en v2.6.0 dans `M19-E23/`). Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête).

**Numéros de version.** semantic-release calcule la version de `plateforme/ci-templates` à partir des commits : avec une MR `feat:` par exercice, on obtient v2.0.0 (E10, `feat!:`), v2.1.0 (E13), v2.2.0 (E14), v2.3.0 (E15), v2.4.0 (E17), v2.5.0 (E18), v2.6.0 (E23) ; le palier 3 publie ensuite v2.7.0 (E24) et v2.8.0 (E29). Si ton historique diffère (un `fix:` intercalé, deux fonctions dans une MR), tes numéros diffèrent : épingle **ta** version. Les vérifications acceptent toute version `v2.x.y`.

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Résolution des composants* : lue dans le code de GitLab (`lib/gitlab/ci/components/instance_path.rb`, `app/models/concerns/semantic_versionable.rb`, branche principale) : une version du catalogue est cherchée par le **nom exact de l'étiquette** ; `@2.0.0` ne trouve pas l'étiquette `v2.0.0`, alors que `@2`, `@2.0` et `@~latest` passent par le catalogue ; le fichier `templates/<nom>.yml` est cherché **avant** `templates/<nom>/template.yml`. Documentation GitLab (*CI/CD components*, `spec:inputs`, `release`, *Kubernetes executor*, *CI/CD job token*, *downstream pipelines*, agent *CI/CD workflow*, KAS d'omnibus) relue sur la branche principale, comportements datés relevés (`strategy: mirror` 18.2, `spec:component` 18.7, `spec:description` 18.10, `services:kubernetes:user` 18.0, alias de services résolus par nom à partir du Runner 17.9, KAS en `grpcs://` par défaut en 19.5).
- *Validation statique* : `yamllint` sur tous les YAML ; `helm template` (Helm 4.3.0) des charts `gitlab/gitlab-agent` 2.32.0, `jenkins/jenkins` 5.9.72 et `sonarqube/sonarqube` 2026.5.1002 avec les valeurs fournies, puis `kubeconform` 0.8 (`-strict`, schémas Kubernetes 1.36.0 et schémas des CRD du catalogue datreeio) sur les rendus, les espaces, le RBAC de l'agent et les politiques Cilium ; contrôle des contextes de sécurité rendus (profil `restricted`) pour Jenkins, SonarQube et l'agent ; `helmfile` 1.8.1 (`list`, `build`, `template`) sur un sous-helmfile qui déclare ses propres `repositories` ; `kustomize` 5.8.1 et `kubeconform` sur les overlays de M17-E09 ; `kustomize edit set image nom=nom:vX.Y.Z@sha256:…` → rendu `…:vX.Y.Z@sha256:…` constaté, garde-fou `verifier-livraison.sh` rejoué (cas conforme, image sans empreinte, étiquette désalignée) ; `shellcheck -x` (0.11) et `bash -n` sur tous les scripts et checks.
- *Exécutés réellement* : les tests de MédiAgenda avec `pytest-cov` 7.1.0 (couverture 75 %, ligne `TOTAL` et `coverage.xml` Cobertura), l'expression `coverage:` contre les lignes Python et Go ; les tests d'intégration de MédiAgenda contre un **vrai** PostgreSQL (16, faute de 18 dans le bac à sable) et un Valkey/Redis local (la base **doit** être en UTF-8, constaté) ; Semgrep CE 1.182.0 avec `p/python` et `p/secrets` sur MédiAgenda (0 résultat), puis sur un `subprocess(..., shell=True)` planté (règle `ERROR`, code 1, rapport SAST version 15.0.4), commentaire `nosemgrep` respecté, double passe (rapport complet puis contrôle bloquant) ; Gitleaks 8.30.1 en mode `git` sur une plage où le secret est ajouté puis retiré (échec, rapport JUnit) ; `generer-enfant.sh` et `generer-validation.sh` (YAML produit validé par `yamllint`) ; les checks du palier sous `set -euo pipefail` avec des fonctions d'API simulées (réponses vides : aucun faux positif ; réponses conformes : E10 et E23 au vert).
- **Non rejoués sur un GitLab réel** (signalés « ⚠️ À vérifier sur ton lab ») : la publication au catalogue et l'affichage des versions, l'interpolation des entrées (en particulier une entrée `array` placée dans une chaîne, et une entrée utilisée comme **clé** de `variables:`), les pipelines enfants et multi-projets, le job `release:` avec `glab` et `ADDITIONAL_CA_CERT_BUNDLE`, l'agent (connexion `wss://`, droits minimaux d'agentk, contexte CI), SonarQube et Jenkins démarrés, le comportement de buildkitd distant avec `--output type=oci`, les services de job sous l'utilisateur `999`, les noms des champs `test_suites[].name` et `downstream_pipeline` des API.

**Où lancer les commandes.** `admin@adm01:~$` avec ton kubeconfig personnel (contexte `k8s-par1`) ; `admin@adm01:~/src/<projet>$` dans les clones ; pour l'API de GitLab en écriture, un jeton **personnel** de portée `api` qui expire le lendemain, rangé dans `~/.config/workbook/gitlab-api-ecriture.token` (600) et révoqué en fin de séance (même principe que le jeton `create_runner` de E04) ; en lecture, le jeton des vérifications.

```
admin@adm01:~$ export GL=https://git01.par1.medisphere.internal/api/v4
admin@adm01:~$ ecrire() { curl -sSf -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-api-ecriture.token)") "$@"; }
admin@adm01:~$ lire()   { curl -sSf -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-checks.token)") "$@"; }
```

---

### M19-E10 — Des gabarits aux composants CI/CD

**Solution**

Fichiers : [`ci-templates/`](fichiers/M19-E10/ci-templates/) — [`templates/qualite/template.yml`](fichiers/M19-E10/ci-templates/templates/qualite/template.yml), [`templates/construction-image/template.yml`](fichiers/M19-E10/ci-templates/templates/construction-image/template.yml), [`templates/securite/template.yml`](fichiers/M19-E10/ci-templates/templates/securite/template.yml), [`templates/deploiement/template.yml`](fichiers/M19-E10/ci-templates/templates/deploiement/template.yml), [`templates/release/template.yml`](fichiers/M19-E10/ci-templates/templates/release/template.yml) (et un `README.md` par composant), [`README.md`](fichiers/M19-E10/ci-templates/README.md), [`.gitlab-ci.yml`](fichiers/M19-E10/ci-templates/.gitlab-ci.yml), [`.releaserc.json`](fichiers/M19-E10/ci-templates/.releaserc.json), échantillons [`tests/`](fichiers/M19-E10/ci-templates/tests/) ; [`ci-labo/.gitlab-ci.yml`](fichiers/M19-E10/ci-labo/.gitlab-ci.yml) et [`pyproject.toml.extrait`](fichiers/M19-E10/ci-labo/pyproject.toml.extrait).

1. **Lecture.**
   - Une **entrée** est remplacée dans le texte de la configuration au moment où GitLab **construit** le pipeline, avant même de l'interpréter : elle peut donc se trouver là où une variable est interdite (nom de job, `stage:`, `tags:`, `needs:`, `rules:`, clé de `variables:`), elle a un type (`string`, `number`, `boolean`, `array`), elle est validée (`options`, `regex`) et documentée (`description`). Seul l'auteur de l'inclusion la fixe. Une **variable** de CI est résolue à l'exécution par le runner, toujours une chaîne, et peut venir de vingt endroits (projet, groupe, instance, déclencheur, planification…) avec un ordre de priorité.
   - Une entrée inconnue, un type faux, une valeur hors `options` ou hors `regex` font échouer la **création** du pipeline : erreur affichée dans *Build > Pipelines* (« *`image_nom` input: … does not match required RegEx* »), aucun job ne démarre. C'est l'intérêt : la faute de frappe de Lucas (`SC_IMAGE_NOM`) devient une erreur bloquante au lieu d'une image sans nom.
   - Un composant ne définit ni `workflow`, ni `stages`, ni `default`, ni `variables` globales : ces mots-clés s'appliquent à **tout** le pipeline du projet qui l'inclut (la documentation le recommande explicitement). Les `stages` sont listés par le projet (les composants ont des entrées `stage…`).
2. **Inventaire → entrées.** `SC_IMAGE_NOM` → `image_nom` (obligatoire, `regex`) ; `SC_CONTEXTE`, `SC_DOCKERFILE`, `SC_PLATEFORME` → `contexte`, `dockerfile`, `plateforme` (`options`) ; `SC_SEVERITE_BLOQUANTE` → `severite_bloquante` (`options: [CRITICAL, "CRITICAL,HIGH"]`) ; `PUBLIER` → `publier` (booléen) ; images d'outils → `image_*` (`regex` qui exige Harbor **et** une empreinte) ; plus `stage…`, `runner` (défaut `k8s`), `job_construction`/`job_publication`/`job_analyse` pour brancher les composants entre eux sans figer leurs noms. Le préfixe de job demandé à l'étape 2 sert là où deux inclusions coexistent : `promouvoir-$[[ inputs.overlay ]]` (E17), `deployer-$[[ inputs.environnement ]]` (E18).
3. **Composants.** Points notables :
   - `qualite` : `extends: .qualite-v2-$[[ inputs.langage ]]` choisit le socle Python ou Go ; les jobs cachés sont préfixés `.qualite-v2-` pour ne pas entrer en collision avec un job du projet (les noms se mélangent dans le pipeline final). La règle `if: '"$[[ inputs.commitlint ]]" != "true"'` compare deux chaînes **littérales** : c'est la forme que donne la documentation pour une entrée dans `rules:if`.
   - `construction-image` : `buildctl --addr "$BUILDKIT_HOST" --tlsdir "$BUILDKIT_TLS_DIR"` (variables posées par le runner, E08), `--output type=oci,dest=image.tar` (l'archive revient au client, rien n'est poussé par le démon), `attest:provenance=mode=max`, cache de registre `plateforme/cache-buildkit:$CI_PROJECT_PATH_SLUG` avec les identifiants du **client** (`DOCKER_CONFIG`), seulement si les variables protégées du robot existent. La publication refuse d'écraser une étiquette et compare l'empreinte publiée à l'empreinte construite, puis exporte `IMAGE_REF` (par empreinte) : c'est l'interface que E17, E24 et E29 consomment.
   - `securite` : Trivy sur l'archive **avant** publication (job `securite:trivy`, attendu par `image:publication` grâce à un `needs` **optionnel** : `construction-image` fonctionne aussi sans `securite`) ; signature de l'index et des manifestes de plateforme, méthode M13 (`--signing-config`, aucun journal public), après la fin de l'analyse de Harbor.
   - `deploiement` : un job par overlay grâce à `parallel:matrix: - OVERLAY: $[[ inputs.overlays ]]` — une entrée `array` qui remplace une valeur **entière** est interpolée comme une vraie liste ; placée dans une chaîne, elle deviendrait du texte.
   - `release` (cinquième composant) : semantic-release dans une image Node 24 sur l'étiquette `k8s`, paquets npm épinglés. Sans lui, `mediagenda/api` devrait garder une inclusion du gabarit v1 sur `runner01`, et E11 ne pourrait pas n'inclure « que des composants ».
4. **Tests dans le dépôt.** [`.gitlab-ci.yml`](fichiers/M19-E10/ci-templates/.gitlab-ci.yml) inclut `component: $CI_SERVER_FQDN/$CI_PROJECT_PATH/<nom>@$CI_COMMIT_SHA` sur les échantillons de [`tests/`](fichiers/M19-E10/ci-templates/tests/) : `qualite` sur un petit paquet Python (avec son `uv.lock`), `construction-image` (`publier: false`) sur un Dockerfile minuscule, `securite` (`signer: false`), `deploiement` sur un overlay `essai`. Le job `composants:presents` a des `needs` vers les jobs promis aux projets : si une MR renomme ou supprime un job, la **création** du pipeline échoue (« *needs … but it was not added to the pipeline* »). Le job d'exemple de la documentation, qui interroge `/pipelines/:id/jobs` avec le `CI_JOB_TOKEN`, ne marche pas ici : ce point d'API n'est pas ouvert au jeton de job (liste « *Job token access* »), il faudrait un jeton de projet en lecture.
5. **Publication.** Le greffon `@semantic-release/gitlab` crée la release **par l'API** : une telle release n'est pas publiée au catalogue. [`.releaserc.json`](fichiers/M19-E10/ci-templates/.releaserc.json) ne garde que `@semantic-release/commit-analyzer` : semantic-release calcule la version et pousse l'étiquette par Git (son cœur s'authentifie avec `GITLAB_TOKEN`) ; le pipeline de l'**étiquette** (le `workflow` du dépôt l'autorise) rejoue les tests, puis `notes-de-version` (image avec `git`) prépare les notes et `publier-catalogue` crée la release par le mot-clé `release:` (`glab`, image du cache `gitlab` de Harbor, racine MédiSphère par `ADDITIONAL_CA_CERT_BUNDLE`). Déclarer le projet au catalogue (rôle Owner) :
   ```
   *Settings > General > Visibility, project features, permissions > CI/CD Catalog project*  (ou la mutation GraphQL catalogResourcesCreate)
   admin@adm01:~/src/ci-templates$ git mv templates/qualite.yml templates/release.yml templates/image.yml \
       templates/supply-chain.yml templates/verification.yml templates/images-autorisees.yml gabarits-v1/
   admin@adm01:~/src/ci-templates$ git commit -m "feat!: composants CI/CD v2 (qualite, construction-image, securite, deploiement, release)" \
       -m "BREAKING CHANGE: les gabarits v1 quittent templates/ (gabarits-v1/) ; inclusion par component."
   ```
   Après fusion : étiquette `v2.0.0`, pipeline d'étiquette, release, version visible :
   ```
   admin@adm01:~$ lire -X POST -H 'Content-Type: application/json' "${GL%/v4}/graphql" \
       --data '{"query":"{ ciCatalogResource(fullPath: \"plateforme/ci-templates\") { name versions { nodes { name } } } }"}' | jq .
   { "data": { "ciCatalogResource": { "name": "ci-templates", "versions": { "nodes": [ { "name": "v2.0.0" } ] } } } }
   ```
   D'après le code de GitLab (`SemanticVersionable`, préfixe `v` accepté et mémorisé), le nom de version affiché garde le préfixe (`v2.0.0`). ⚠️ À vérifier sur ton lab ; le check accepte les deux formes.
6. **Migration de `ci-labo`.** Ajoute `ruff` à ses dépendances de développement (`uv add --dev "ruff>=0.17,<0.18"`, le composant lint avec la version **verrouillée** du projet), puis [`.gitlab-ci.yml`](fichiers/M19-E10/ci-labo/.gitlab-ci.yml). Les essais :
   - `@v2.0.0` : fonctionne (nom exact de l'étiquette publiée) ;
   - `@2.0.0` : **échoue** (« *component … not found* ») : GitLab cherche une version du catalogue nommée `2.0.0`, puis une release d'étiquette `2.0.0`, puis une référence Git `2.0.0` — aucune n'existe. C'est le piège du préfixe `v` ;
   - `@2` et `@2.0` : fonctionnent, **par le catalogue** (dernière 2.x.y, dernière 2.0.y) ; ils échoueraient si le projet n'était pas un projet de catalogue ;
   - `@~latest` : fonctionne, toujours la dernière version publiée (ruptures comprises) : jamais en production.
7. **Garde-fous.** `image_nom: "MediSphere/API"` → refus à la création, message dans la page du pipeline (« *`image_nom` input: provided value does not match required RegEx* ») ; une entrée inconnue (`image_name:`) → « *unknown input arguments: image_name* ». Rien dans un journal de job : il n'y a pas de job.

**Explications**

Un composant est un fichier de configuration à deux documents YAML : l'en-tête `spec` (entrées, description, contexte) et le contenu. À l'inclusion, GitLab valide les entrées, remplace les blocs `$[[ … ]]` dans les **valeurs** déjà analysées du YAML (y compris les clés), puis fusionne le résultat avec le `.gitlab-ci.yml`. La référence `@…` se résout dans l'ordre : version du catalogue (nom exact, ou version partielle / `~latest`), release, référence Git ; une empreinte de commit est la forme la plus stricte. Le catalogue n'est qu'un index de releases créées par le mot-clé `release:` dans un pipeline : il garde, pour chaque version, le `README.md` et la liste des composants du commit étiqueté.

**Alternatives**
- *Rester en `include: project` avec `ref:`* : marche en Free depuis toujours, mais sans typage ni validation ; c'est ce que gardent les projets en v1.
- *Étiquettes sans préfixe* (`2.0.0`, `tagFormat: "${version}"`) : `@2.0.0` fonctionnerait, au prix d'une rupture avec toutes les étiquettes `v1.x.y` (semantic-release ne retrouverait plus la dernière version) ; la convention MédiSphère reste `vX.Y.Z`.
- *Un composant « pipeline-python » qui inclut les autres* : une ligne chez Julien, mais une boîte noire de plus ; le tableau des normes (E11) préfère quatre inclusions lisibles.
- *Branche majeure `v2` qui avance seule* (comme `v1` au M01) : inutile avec `@2` par le catalogue, et moins sûre (une branche se réécrit).

**Pièges classiques**
- Laisser `templates/qualite.yml` à côté de `templates/qualite/template.yml` : GitLab trouve d'abord le fichier simple, sans `spec`… et inclut le gabarit v1. Plus généralement, **tout** fichier `templates/*.yml` apparaît comme composant au catalogue.
- Épingler `@2.0.0` avec des étiquettes `v2.0.0`.
- Publier la release par l'API (ou par semantic-release avec le greffon GitLab) : la release existe, le catalogue ne la voit pas. Et un job `release:` sur une étiquette dont la release existe déjà **échoue**.
- `release:` sans `glab` dans l'image, ou sans la racine MédiSphère : « *x509: certificate signed by unknown authority* ».
- Une entrée `array` dans une chaîne (`"$[[ inputs.overlays ]]"`) : on obtient sa représentation texte, pas une liste.
- Un `default:` qui ne respecte pas son propre `regex` (ex. une empreinte `<EMPREINTE>` pas encore relevée) : **tous** les pipelines qui incluent le composant échouent à la création.

**En production chez MédiSphère**
Renovate suit les versions des composants dans chaque projet (gestionnaire `gitlabci-include`, à vérifier sur ta version de Renovate) et ouvre les MR de montée ; une page de catalogue par composant avec ses exemples ; une politique de support (deux majeures maintenues) écrite dans le README ; le pipeline de `ci-templates` teste chaque composant sur un échantillon par langage avant toute publication.

---

### M19-E11 — Le pipeline standard de MédiAgenda

**Solution** (une solution possible ; le corrigé ne contraint pas la forme, seulement les règles)

Fichiers : [`mediagenda-api/.gitlab-ci.yml`](fichiers/M19-E11/mediagenda-api/.gitlab-ci.yml) (22 lignes utiles), [`docs/livraison/ci/normes-pipeline.md`](fichiers/M19-E11/medisphere/docs/livraison/ci/normes-pipeline.md).

- Le projet garde trois choses : `workflow:` (MR, `main`, étiquettes `vX.Y.Z`, pas de doublon, `auto_cancel`), `stages:` (ceux des composants), et les inclusions. Plus aucun job écrit à la main.
- Les variables protégées (`HARBOR_ROBOT_*`, `COSIGN_*`, `GITLAB_TOKEN`, `BUILDKIT_CACHE_*`) n'existent que sur `main` et les étiquettes protégées ; dans une MR, `image:construction` construit sans cache de registre, `image:publication`, `securite:signature` et `release:semantic-release` n'existent pas (leurs règles demandent `main` ou une étiquette **protégée**).
- Mesure du pipeline de MR : `lire "$GL/projects/mediagenda%2Fapi/pipelines?source=merge_request_event&per_page=5" | jq '.[] | {id, duration, queued_duration}'` (champs de durée présents dans la liste depuis 19.4). Ordre de grandeur avant E23 : 6 à 9 minutes, dont 2 à 3 pour la construction (sans cache dans les MR).
- Vérification de la signature d'une étiquette :
  ```
  admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true \
      registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.3.0 | jq -r '.[0].critical.image."docker-manifest-digest"'
  ```

**Explications**

Le pipeline standard est une **composition** : chaque composant apporte ses jobs, ses règles et ses artefacts ; le projet n'apporte que ce qui lui est propre (quels pipelines existent, dans quel ordre de stages). Les liens entre composants passent par des noms de jobs documentés (`image:construction`, `image:publication`) et des rapports `dotenv` (`IMAGE_EMPREINTE`, `IMAGE_REF`), jamais par des variables globales.

**Alternatives**
- Garder `runner02` pour la construction (BuildKit éphémère) : plus simple, mais contraire à l'objectif (ADR-0120 : seccomp et AppArmor non confinés dans chaque job).
- Inclure `@2` (version partielle) : montées mineures automatiques, mais pipeline non reproductible ; la norme exige une version complète, Renovate fait les montées.

**Pièges classiques**
- Oublier un stage utilisé par un composant (`signature`, `release`) : « *chosen stage does not exist* » à la création.
- Ne pas autoriser les pipelines d'étiquette dans `workflow:` : semantic-release pose `v1.3.0`, aucune image n'est publiée.
- Confondre « la variable est masquée » et « la variable n'existe pas dans les MR » : c'est la **protection** qui retire la variable des pipelines de branches non protégées.

**En production chez MédiSphère**
Le contrôle planifié de E32 lit la configuration fusionnée de chaque projet et signale ceux qui s'écartent des normes ; les normes sont relues à chaque majeure des composants.

---

### M19-E12 — Pipelines enfants, multi-projets et déclencheurs

**Solution**

Fichiers : [`ci-labo/.gitlab-ci.extrait.yml`](fichiers/M19-E12/ci-labo/.gitlab-ci.extrait.yml), [`ci-labo/ci/enfant.yml`](fichiers/M19-E12/ci-labo/ci/enfant.yml), [`ci-labo/ci/generer-enfant.sh`](fichiers/M19-E12/ci-labo/ci/generer-enfant.sh) ; [`chart/.gitlab-ci.extrait.yml`](fichiers/M19-E12/chart/.gitlab-ci.extrait.yml) ; [`deploiement/.gitlab-ci.yml`](fichiers/M19-E12/deploiement/.gitlab-ci.yml), [`deploiement/outils/generer-validation.sh`](fichiers/M19-E12/deploiement/outils/generer-validation.sh), [`deploiement/outils/valider-chart.sh`](fichiers/M19-E12/deploiement/outils/valider-chart.sh).

1. **Échauffement.** `enfant-fichier` (`trigger: include: ci/enfant.yml`) et `generer` → `enfant-genere` (`trigger: include: - artifact: enfant-genere.yml, job: generer`). Par l'API :
   ```
   admin@adm01:~$ lire "$GL/projects/formation%2Fci-labo/pipelines/<id>/bridges" | jq -r '.[] | "\(.name) → \(.downstream_pipeline.id) \(.downstream_pipeline.status)"'
   enfant-genere → 1842 success
   enfant-fichier → 1841 success
   ```
   Un fichier généré invalide : le job `generer` est **vert** (il a bien écrit un fichier), c'est le job déclencheur qui échoue (« *downstream pipeline can not be created* », détail dans l'infobulle). D'où l'intérêt de faire valider le YAML par le générateur lui-même dans un vrai projet (`yamllint` du fichier produit).
2. **Aval (`deploiement`).** Le `workflow:` accepte `CI_PIPELINE_SOURCE == "pipeline"` **avec** `CHART_VERSION` et `CHART_DIGEST` (un déclenchement sans eux ne crée rien). Les jobs du composant et le garde-fou sont exclus de ce pipeline (règles surchargées) ; `chart:verifier-signature` vérifie la signature Cosign du digest annoncé ; `chart:notes` lit la release du chart avec le `CI_JOB_TOKEN` ; `chart:generer-validation` produit un job par dossier de `overlays/` ; `chart:valider` déclenche l'enfant en lui passant la version et le digest. Chaque job enfant rend la base avec la **nouvelle** version dans une copie jetable (le dépôt n'est pas modifié), puis `kustomize build`, `kubeconform` et le garde-fou de livraison.
3. **Amont (`chart`).** `valider-deploiement` a `needs: [pousser, signer]` : il reçoit `CHART_VERSION` et `CHART_DIGEST` du rapport `dotenv` de `pousser` et les transmet en les nommant dans `variables:` ; `strategy: mirror`.
4. **`CI_JOB_TOKEN`.** Premier essai : `chart:notes` échoue (`404 Not Found` : le jeton de `deploiement` n'est pas autorisé à lire `chart`). Autorisation, côté projet **lu** :
   ```
   admin@adm01:~$ ID_DEP=$(lire "$GL/projects/mediagenda%2Fdeploiement" | jq .id)
   admin@adm01:~$ ecrire -X PATCH "$GL/projects/mediagenda%2Fchart/job_token_scope" --data enabled=true
   admin@adm01:~$ ecrire -X POST "$GL/projects/mediagenda%2Fchart/job_token_scope/allowlist" --data target_project_id=$ID_DEP | jq -r .path_with_namespace
   mediagenda/deploiement
   admin@adm01:~$ lire "$GL/projects/mediagenda%2Fchart/job_token_scope" | jq .inbound_enabled
   true
   ```
5. **Casser l'aval.** Un `replicaCount: "deux"` dans `base/values-communes.yaml` (refusé par le schéma du chart, M17) sur `main` de `deploiement` : `valider:prod` échoue au `helm template`, l'enfant est rouge, `chart:valider` aussi, puis `valider-deploiement` dans le chart : la release du chart est **publiée** (étiquette, Harbor) mais marquée rouge. Remise en état par MR inverse.
6. **Journal.**
   - L'**auteur** du pipeline aval est l'utilisateur qui a déclenché le pipeline amont (ici l'auteur de l'étiquette : souvent le robot `bot-release` de semantic-release !). Il doit pouvoir lancer un pipeline sur `main` de `deploiement` (Developer, branche protégée : *Allowed to merge* ou *push* selon la règle) ; sinon, « *insufficient permissions to create a downstream pipeline* ».
   - Variables visibles en aval : celles que le job déclencheur **nomme** dans `variables:` (et ses variables YAML), plus les variables propres au projet aval ; jamais les variables du projet amont (robots, clé Cosign) ; `trigger:forward:pipeline_variables` (désactivé par défaut) transmettrait les variables du pipeline amont.
   - `strategy: depend` : le job reste `running` si l'aval attend un job manuel, et reflète mal certains états (`allow_failure`) ; `mirror` (18.2) prend exactement le statut de l'aval.

**Explications**

Un job `trigger:` ne s'exécute sur aucun runner : GitLab crée le pipeline aval lui-même. Enfant = même projet, même commit, pas de nouvel auteur ; multi-projets = autre projet, branche choisie, **même utilisateur**. Le `CI_JOB_TOKEN` est un jeton éphémère du job, limité par la liste d'autorisation **entrante** du projet lu (et, en plus, aux droits de l'utilisateur) ; activer cette liste partout ferme les lectures croisées non prévues (E25).

**Alternatives**
- `trigger: inputs:` vers un `.gitlab-ci.yml` aval doté d'un `spec:inputs` : version typée et validée ; mais une entrée se résout à la **création** du pipeline aval à partir d'une valeur connue du job déclencheur — avec un `dotenv` c'est possible, à vérifier sur ta version (⚠️ non testé).
- Jeton de déclenchement (`POST /trigger/pipeline`) : un secret de plus à gérer ; le mot-clé `trigger:` n'en a pas besoin.
- `needs:pipeline:job` pour récupérer les artefacts amont : Premium.

**Pièges classiques**
- Un job déclencheur avec `script:` ou `tags:` : refusé.
- Oublier les règles du pipeline aval : les jobs de `main` (dont, à partir de E18, **le déploiement**) tournent aussi dans le pipeline déclenché par le chart. `deployer-dev` (E18) n'accepte que `push`/`web`.
- Le générateur produit un pipeline sans job (aucun overlay) : « *no stages / jobs* » ; garder un job témoin.
- Autoriser le projet dans la liste du projet **appelant** au lieu du projet **lu**.

**En production chez MédiSphère**
La validation aval par version du chart s'étend aux autres consommateurs du chart (overlays de MédiDoc plus tard) ; une alerte quand un chart publié ne passe pas un overlay de prod ; E25 active la liste d'autorisation sur tous les projets et l'impose au niveau de l'instance.

---

### M19-E13 — Pipelines de MR : rapports de tests et couverture

**Solution**

Fichiers : [`ci-templates/templates/qualite/template.yml`](fichiers/M19-E13/ci-templates/templates/qualite/template.yml) (v2.1.0), [`mediagenda-api/.gitlab-ci.extrait.yml`](fichiers/M19-E13/mediagenda-api/.gitlab-ci.extrait.yml), [`mediagenda-api/pyproject.toml.extrait`](fichiers/M19-E13/mediagenda-api/pyproject.toml.extrait).

1. **Composant.** Entrées `couverture` (booléenne) et `paquet_python` ; Python : `pytest --junitxml=rapport-tests.xml --cov=<paquet> --cov-report=term --cov-report=xml:coverage.xml` ; Go : `gotestsum` avec `-coverprofile`, `go tool cover -func` (ligne `total:`), `gocover-cobertura` ; `coverage: '/(?i)^total\b[^%\n]*?(\d+(?:\.\d+)?)%/'` (une expression pour les deux langages) ; `artifacts:reports:coverage_report` au format `cobertura`, et `coverage.xml` aussi dans `paths` (les rapports ne sont pas transmis aux jobs suivants, les fichiers de `paths` si : E16 s'en sert).
2. **MédiAgenda.**
   ```
   admin@adm01:~/src/mediagenda-api$ uv add --dev "pytest-cov>=7.1,<8"
   admin@adm01:~/src/mediagenda-api$ uv run pytest --cov=mediagenda --cov-report=term | tail -3
   src/mediagenda/modeles.py       17      0   100%
   ------------------------------------------------
   TOTAL                          395    100    75%
   ```
   Dans la MR : onglet *Tests* du pipeline (27 tests), couverture `75.0 %` dans le widget du pipeline et dans la liste des jobs, et dans l'onglet *Changes*, une barre verte ou rouge en marge des lignes modifiées (couvertes ou non).
3. **Test cassé, test supprimé.** Le widget « *Test summary* » de la MR liste « *1 failed* » avec le nom du test et la trace (rapport JUnit) ; GitLab compare aussi au pipeline de la branche cible (« *new failures* »). Un test supprimé : la couverture baisse, la MR affiche l'écart de couverture avec la cible (« *Coverage −1.3 %* »), rien ne bloque.
4. **Réglages.**
   ```
   admin@adm01:~$ for p in mediagenda%2Fapi mediagenda%2Fdeploiement plateforme%2Fci-templates; do
       ecrire -X PUT "$GL/projects/$p" --data only_allow_merge_if_pipeline_succeeds=true \
         --data allow_merge_on_skipped_pipeline=false | jq -c '{path_with_namespace, only_allow_merge_if_pipeline_succeeds}'; done
   ```
   Julien (Maintainer) ne peut plus fusionner la MR rouge (bouton désactivé, « *Merge blocked: pipeline must succeed* »). Un administrateur ne le peut pas davantage par le bouton ; il pourrait **désactiver** le réglage, fusionner, le réactiver (trace dans les journaux d'audit… qui sont Premium : en Free, seul le journal d'activité du projet en garde un souvenir). C'est pourquoi le réglage est vérifié chaque jour par E32.
5. Même réglage sur `deploiement` et `ci-templates` (boucle ci-dessus).

**Explications**

`coverage:` lit le **journal** du job ; `coverage_report` lit un **fichier** Cobertura et alimente la vue ligne à ligne. Les rapports `junit` sont agrégés par pipeline ; le pourcentage remonte au pipeline (moyenne des jobs qui en ont un) et aux graphiques du dépôt (*Analyze > Repository analytics*).

**Alternatives**
- `--cov-fail-under=75` : bloque, mais encourage à écrire des tests pour le chiffre ; MédiSphère préfère « ne pas baisser » (comparaison avec la cible), à outiller plus tard.
- Couverture Go native (`go test -cover`) sans Cobertura : pourcentage oui, vue ligne à ligne non.

**Pièges classiques**
- `--cov` sans paquet sur une arborescence `src/` : on mesure aussi les tests, le chiffre est flatteur.
- Chemins du `coverage.xml` hors du dépôt (`<source>` absolu d'une autre machine) : la vue ligne à ligne reste vide.
- Expression `coverage:` qui correspond à une autre ligne (`Name   Stmts`) : pourcentage absent.
- « *Skipped pipelines are considered successful* » laissé actif : un `[skip ci]` contourne la protection.

**En production chez MédiSphère**
Tendance de couverture par projet suivie au M21 ; règle des normes : une MR ne fait pas baisser la couverture de plus de 1 point sans justification dans la description.

---

### M19-E14 — Services de job : une base PostgreSQL pour les tests d'intégration

**Solution**

Fichiers : [`ci-templates/templates/qualite/template.yml`](fichiers/M19-E14/ci-templates/templates/qualite/template.yml) (v2.2.0, job `qualite:tests-integration`), [`mediagenda-api/.gitlab-ci.extrait.yml`](fichiers/M19-E14/mediagenda-api/.gitlab-ci.extrait.yml), [`k8s/composants/gitlab-runner/values.yaml.extrait`](fichiers/M19-E14/k8s/composants/gitlab-runner/values.yaml.extrait).

1. **Lecture.** Avec l'exécuteur Kubernetes, chaque service est un **conteneur de plus dans le pod du job** : même espace réseau, donc `127.0.0.1:5432` ; depuis le Runner 17.9, l'alias (`postgresql`, `valkey`) est aussi résolu par nom. Deux services sur le même port se heurtent (un seul peut écouter sur `127.0.0.1:5432` du pod). À la fin du job, le pod est supprimé : base comprise. Aucun réseau partagé entre deux jobs, donc aucune base « partagée qu'un autre pipeline viendrait vider ».
2. **Composant.** Points clés de `qualite:tests-integration` :
   - `services:` avec `alias`, `kubernetes: user: "999:999"` (UID:GID de l'utilisateur des images `postgres` et `valkey` : le script d'entrée de PostgreSQL ne fait de `chown` qu'en root ; sous 999, il initialise directement le répertoire de données qui lui appartient dans l'image), `POSTGRES_HOST_AUTH_METHOD: trust` (base jetable, joignable seulement depuis le pod), `POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=C.UTF-8"` (MédiAgenda exige de l'UTF-8 : constaté, une base `SQL_ASCII` fait échouer les tests avec `UnicodeEncodeError`) ; Valkey sans persistance (`--save "" --appendonly no`) ;
   - les URL de test dans des variables dont le **nom** est une entrée (`$[[ inputs.variable_postgresql ]]: postgresql://integration@postgresql:5432/integration`) : MédiAgenda lit `MEDIAGENDA_TEST_DB_URL` (⚠️ à vérifier sur ton lab : interpolation d'une entrée dans une clé de `variables:` ; à défaut, surcharger les variables du job dans le projet) ;
   - attente bornée des deux services (un `connect()` TCP sur PostgreSQL ne réussit qu'après l'initialisation : le serveur temporaire du script d'entrée n'écoute que sur une socket locale), puis la commande de préparation (`mediagenda-migrate`), puis `pytest -m integration` et un rapport JUnit séparé ;
   - ressources des services : `KUBERNETES_SERVICE_CPU_REQUEST` 100m, `…_MEMORY_REQUEST` 128 Mi, limites 1 CPU / 512 Mi — prises en compte **seulement** si le runner déclare des plafonds `service_*_overwrite_max_allowed` ([extrait](fichiers/M19-E14/k8s/composants/gitlab-runner/values.yaml.extrait)), sinon ignorées en silence.
3. **Le pod.**
   ```
   admin@adm01:~$ kubectl -n ci-jobs get pod -l medisphere.internal/ci=job -o json \
       | jq -r '.items[0].spec | (.initContainers + .containers)[] | "\(.name)\t\(.image | split("@")[0])\t\(.securityContext.runAsUser // "-")\t\(.resources.requests.memory // "-")"'
   init-permissions  registry…/gitlab-runner-helper:x86_64-v19.4.0   -     -
   build             registry…/ghcr/astral-sh/uv:0.12.23-python3.13…  -     512Mi
   helper            registry…/gitlab-runner-helper:x86_64-v19.4.0   -     128Mi
   svc-0             registry…/dockerhub/library/postgres:18.6-trixie 999   128Mi
   svc-1             registry…/dockerhub/valkey/valkey:8.1.10-trixie  999   128Mi
   admin@adm01:~$ kubectl -n ci-jobs get pod <pod> -o jsonpath='{.spec.hostAliases}'
   ```
   ⚠️ À vérifier sur ton lab : les noms exacts des conteneurs de service (`svc-0`, `svc-1`) et la façon dont ta version publie les alias (`hostAliases` vers `127.0.0.1` ou résolution interne).
4. **Pannes provoquées.**
   - Service sans alias : le nom par défaut est dérivé de l'image (`registry.par1.medisphere.internal__dockerhub__library__postgres`…) : l'URL `postgresql://…@postgresql` ne résout plus (`could not translate host name`).
   - Deux services sur 5432 (deux PostgreSQL) : le second s'arrête (`could not bind IPv4 address "0.0.0.0": Address in use`), le job attend puis échoue selon lequel répond.
   - Tests lancés sans attente : `connection refused` au premier test, aléatoire selon la vitesse du nœud. D'où la boucle d'attente bornée (jamais un `sleep 20` fixe).
5. **Budget.** build 512 Mi + helper 128 Mi + 2 × 128 Mi = 896 Mi de demande pour ce pod (limites 2 Gi + 512 Mi + 2 × 512 Mi) : à comparer au LimitRange `limites-ci` (maximum par conteneur) et au quota `quota-ci` de `ci-jobs` (E02). Un job à quatre services passerait le LimitRange mais consommerait une grosse part du quota : c'est ce qu'E27 dimensionne.

**Explications**

L'exécuteur Kubernetes traduit `services:` en conteneurs supplémentaires du pod du job ; le runner attend qu'ils soient **démarrés**, pas qu'ils soient **prêts** (pas de sonde de santé du service). L'utilisateur d'un service se règle par `services:kubernetes:user` (GitLab 18.0) ou, pour tous les services d'un runner, par `service_container_security_context` dans le TOML : c'est ce qu'E24 utilisera quand `ci-jobs` passera en `restricted` (le profil exige `runAsNonRoot`, aucune capacité, seccomp).

**Alternatives**
- *Base CNPG éphémère par pipeline* dans un espace dédié : plus proche de la production (extensions, version exacte), mais demande au job des droits sur l'API Kubernetes (exactement ce qu'on refuse à `ci-job`).
- *Testcontainers* : impossible sans démon Docker ni privilège dans `ci-jobs`.
- *SQLite pour les tests* : rapide, mais ne teste ni les migrations PostgreSQL ni le verrou consultatif.

**Pièges classiques**
- Image `postgres` lancée en root sous un futur `restricted` : refusée par l'admission dès E24 ; anticipé ici par `user: "999:999"`.
- `POSTGRES_PASSWORD` dans le YAML : un faux secret que Gitleaks finira par signaler ; `trust` est plus honnête pour une base jetable.
- Oublier que les tests d'intégration **vident** la base (`DROP SCHEMA`) : ne jamais pointer `MEDIAGENDA_TEST_DB_URL` vers une base d'environnement.
- Croire que `KUBERNETES_SERVICE_*` s'applique toujours : sans plafond dans le TOML, c'est ignoré.

**En production chez MédiSphère**
Images des services suivies par Renovate (même majeure que la production : PostgreSQL 18) ; un job de tests d'intégration par MR ; le temps de démarrage des services mesuré en E23.

---

### M19-E15 — Semgrep CE et Gitleaks dans le composant `securite`

**Solution**

Fichiers : [`ci-templates/templates/securite/template.yml`](fichiers/M19-E15/ci-templates/templates/securite/template.yml) (v2.3.0) ; politique d'exception dans [`normes-pipeline.md`](fichiers/M19-E11/medisphere/docs/livraison/ci/normes-pipeline.md) (§4, version finale déjà dans les fichiers de E11).

1. **Composant.**
   - `securite:semgrep` : image `semgrep/semgrep:1.182.0-nonroot` par Harbor (empreinte `sha256:a1787d07…`), `SEMGREP_SEND_METRICS=off`, `--metrics=off`. Deux passes : la première écrit **tout** (`--gitlab-sast-output=gl-sast-report.json --json-output=semgrep.json`), la seconde ne garde que la sévérité choisie et au-dessus avec `--error` (code 1 s'il reste un résultat). Une seule passe avec `--severity ERROR` écrirait un rapport SAST incomplet ; une seule passe sans filtre bloquerait sur les `WARNING`. Les règles viennent d'une entrée `array` (`["p/python", "p/secrets"]`).
   - `securite:gitleaks` : la plage de commits du gabarit v1 (base de MR, point de divergence, `CI_COMMIT_BEFORE_SHA`), `GIT_DEPTH: "0"`, `--redact`, rapport JUnit, toujours bloquant ; `git config --global --add safe.directory` (le dépôt est cloné par le *helper* sous un autre UID que celui de l'image).
   - Aucun des deux n'attend l'image (`needs: []`, stage de lint).
2. **Essai Semgrep** (rejoué avec Semgrep 1.182.0) :
   ```
   src/mediagenda/essai.py
      ❯❯❱ python.lang.security.audit.subprocess-shell-true.subprocess-shell-true
             ❰❰ Blocking ❱❱
             Found 'subprocess' function 'call' with 'shell=True'. …
               5┆ return subprocess.call(cmd, shell=True)
   ```
   Le job échoue (code 1), le rapport SAST (`gl-sast-report.json`, schéma 15.0.4) contient la vulnérabilité de sévérité `High`. Exception justifiée, sur la ligne précédente :
   ```python
   # nosemgrep: python.lang.security.audit.subprocess-shell-true.subprocess-shell-true -- commande fixe, sans entrée utilisateur (SEC-2015)
   return subprocess.call(cmd, shell=True)
   ```
   `git grep -n "nosemgrep"` la retrouve pour la revue mensuelle (normes §4).
3. **Faux secret ajouté puis retiré.** Rejoué avec Gitleaks 8.30.1 sur une plage de deux commits (ajout d'une paire de clés AWS d'exemple, puis suppression) : « *leaks found: 1* », code 1. Gitleaks en mode `git` lit chaque **commit** de la plage (les ajouts de chaque diff), pas l'état final : le secret est dans l'historique poussé, donc dans `git01`, dans les clones, dans les caches. Un vrai secret poussé se traite dans cet ordre : **rotation** (le secret est compromis dès la poussée), puis nettoyage de l'historique si nécessaire (et *housekeeping* de GitLab), jamais l'inverse.
4. `mediagenda/api` n'inclut plus `qualite.yml` v1 : déjà le cas depuis E11 (le composant `qualite` remplace commitlint et pre-commit, `securite` reprend Gitleaks).
5. Normes §4 : qui valide (relecteur de MR, Sophie pour une règle `ERROR`), où c'est tracé (commentaire sur la ligne, `.trivyignore`, `.gitleaksignore`), revue mensuelle.

**Explications**

Semgrep CE analyse le code source avec des règles déclaratives (motifs sur l'arbre syntaxique) ; le format `--gitlab-sast` est le schéma de rapport de sécurité de GitLab. En Free, le rapport est un **artefact téléchargeable** ; le widget de sécurité de la MR et le tableau des vulnérabilités sont Ultimate : c'est donc le **code de retour** qui protège, pas l'affichage. Gitleaks combine des expressions rationnelles et l'entropie ; `--redact` remplace le secret trouvé par `REDACTED` dans la sortie et le rapport.

**Alternatives**
- Opengrep (fork LGPL) avec des règles écrites par l'équipe : pas de licence de règles à suivre, mais un catalogue de règles à maintenir soi-même.
- Bandit pour Python seul : plus simple, moins de langages (MédiDoc est en Go).
- Gitleaks en hook de pre-commit **en plus** : attrape le secret avant la poussée (M01) ; la CI reste le filet.

**Pièges classiques**
- `semgrep --config auto` : envoie des métadonnées du projet au service SaaS pour choisir les règles ; interdit ici.
- `allow_failure: true` « le temps de nettoyer » : il reste.
- `GIT_DEPTH` par défaut (superficiel) pour Gitleaks : la plage n'est pas dans le clone, Gitleaks ne lit que le dernier commit.
- `nosemgrep` sans identifiant de règle : désactive **toutes** les règles sur la ligne.

**En production chez MédiSphère**
Règles maison dans `plateforme/ci-templates` (dossier de règles, entrée `semgrep_regles`) pour les erreurs propres à MédiSphère (journalisation de données patient) ; revue mensuelle des exceptions ; résultats SAST agrégés dans un tableau de bord (M21) faute de tableau de vulnérabilités en Free.

---

### M19-E16 — SonarQube Community Build : installer et analyser

**Solution**

Fichiers : [`k8s/espaces/sonarqube/`](fichiers/M19-E16/k8s/espaces/sonarqube/) (espace `restricted`, politiques), [`k8s/composants/sonarqube/values.yaml`](fichiers/M19-E16/k8s/composants/sonarqube/values.yaml), [`k8s/composants/sonarqube/cluster-postgresql.yaml`](fichiers/M19-E16/k8s/composants/sonarqube/cluster-postgresql.yaml), [`k8s/releases/80-sonarqube.yaml.gotmpl`](fichiers/M19-E16/k8s/releases/80-sonarqube.yaml.gotmpl), [`k8s/secrets/sonarqube.yml.exemple`](fichiers/M19-E16/k8s/secrets/sonarqube.yml.exemple), [`k8s/outils/secrets-k8s.conf.extrait`](fichiers/M19-E16/k8s/outils/secrets-k8s.conf.extrait) ; [`mediagenda-api/sonar-project.properties`](fichiers/M19-E16/mediagenda-api/sonar-project.properties), [`mediagenda-api/.gitlab-ci.extrait.yml`](fichiers/M19-E16/mediagenda-api/.gitlab-ci.extrait.yml).

1. **Valeurs.** `community.enabled: true`, `community.buildNumber: "26.10.0.133078"` et `image.tag: 26.10.0.133078-community` (le chart 2026.5.1002 déploie encore `26.9.0.129388`), image par le cache `dockerhub` ; `initSysctl.enabled: false` (conteneur **privilégié** qui écrit `vm.max_map_count` sur le nœud : déjà fait par `k8s_travailleur`), `initFs.enabled: false` (root + `CHOWN`), `prometheusExporter.enabled: false` (télécharge un agent Java sur Internet), `tests.enabled: false` ; `jdbcOverwrite` vers `sonarqube-db-rw.sonarqube.svc:5432` avec le Secret `sonarqube-db-app` de l'opérateur ; `monitoringPasscodeSecretName` ; ressources ramenées à 2 Gi / 4 Gi (défaut 4 Go / 10 Go) **et** `ephemeral-storage` fixé (sinon le défaut du chart, 500 Go de limite, est fusionné) ; `httproute` vers `gw-par1` ; `sonar.updatecenter.activate=false`. Rendu vérifié : StatefulSet, Service, PVC, HTTPRoute, ConfigMaps ; le conteneur est conforme à `restricted` (UID 1000, sans capacité, seccomp `RuntimeDefault`).
2. **Installation.**
   ```
   admin@adm01:~/src/k8s$ kubectl apply --server-side -f espaces/sonarqube/
   admin@adm01:~/src/k8s$ kubectl apply --server-side -f composants/sonarqube/cluster-postgresql.yaml
   admin@adm01:~/src/k8s$ kubectl -n sonarqube wait cluster/sonarqube-db --for=condition=Ready --timeout=5m
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer sonarqube && outils/secrets-k8s.sh verifier sonarqube
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=sonarqube diff && helmfile -e par1 -l composant=sonarqube apply
   admin@adm01:~$ kubectl -n sonarqube logs -f sts/sonarqube-sonarqube | grep -E 'SonarQube is operational|ERROR'
   admin@adm01:~$ curl -s https://sonarqube.apps.par1.medisphere.internal/api/system/status
   {"id":"…","version":"26.10.0.133078","status":"UP"}
   ```
   Premier démarrage : 3 à 5 min (migrations de la base, index Elasticsearch). Le sous-helmfile déclare son propre dépôt de charts : constaté avec Helmfile 1.8.1, la liste `repositories` d'un sous-helmfile **remplace** celle de la base, ce qui ne gêne pas ici.
3. **Sécurisation** (mot de passe lu dans le Vault, jamais en argument) :
   ```
   admin@adm01:~$ SQ=https://sonarqube.apps.par1.medisphere.internal
   admin@adm01:~$ ( cd ~/src/ansible && uv run ansible-vault view ../k8s/secrets/sonarqube.yml ) \
       | yq -r .sonarqube_mot_de_passe_admin \
       | { read -r mdp; curl -sf -u admin:admin -X POST "$SQ/api/users/change_password" \
             --data login=admin --data previousPassword=admin --data-urlencode "password@-" <<<"$mdp"; }
   ```
   Puis, connecté en `admin` : utilisateur `wb-checks` (mot de passe aléatoire), droit *Browse* sur le projet, jeton utilisateur → `~/.config/workbook/sonar-checks.token` (600) ; projet `mediagenda-api` ; **jeton d'analyse de projet** → variable `SONAR_TOKEN` de `mediagenda/api` (protégée, masquée), `SONAR_HOST_URL` visible. Sans jeton : `curl -s -o /dev/null -w '%{http_code}' "$SQ/api/project_analyses/search?project=mediagenda-api"` → `401` (le groupe « Anyone » n'existe plus en 26.x).
4. **Analyse.** Le job `sonarqube` (exception écrite dans les normes, retirée au mini-projet) tourne sur `main` après `qualite:tests` dont il reçoit `coverage.xml` ; magasin de confiance Java construit avec la racine MédiSphère (`sonar.scanner.truststorePath`) ; `sonar.scanner.skipJreProvisioning=true` (le scanner 8 sait télécharger un JRE depuis le serveur : l'image en a déjà un) ; `sonar.qualitygate.wait=true` et `timeout=600`. La porte « *Sonar way* » est calculée sur le **nouveau code** : la première analyse passe presque toujours. `allow_failure: true` pendant l'essai : la porte informe, ruff, Semgrep et la couverture décident. ⚠️ À vérifier sur ton lab : noms des propriétés `sonar.scanner.*` sur ta version du scanner (`sonar-scanner -h`, documentation *SonarScanner CLI*).
5. **Branches et MR.** Une analyse avec `-Dsonar.branch.name=…` est refusée par l'édition communautaire (« *Current edition does not support branch feature* ») ; sans ce paramètre, l'analyse d'une branche **écrase** celle de `main`. Pas de décoration de MR. Mémoire relevée : 1,6 à 2,4 Gi au repos (`kubectl top pod -n sonarqube`), plus la base.
6. **Liste pour l'ADR.** Apporte : règles de maintenabilité (duplications, complexité, *code smells*), historique, porte qualité. Ne fait pas (CE) : analyse de MR et de branches, décoration, plusieurs projets par porte de façon simple. Déjà ailleurs : lint (ruff), sécurité (Semgrep), couverture dans la MR (E13), secrets (Gitleaks). Coût : 3 Gio, une base, des mises à jour mensuelles.

**Explications**

SonarQube embarque Elasticsearch (d'où `vm.max_map_count`) et un moteur de calcul (*Compute Engine*) qui traite les rapports envoyés par le scanner : l'analyse se fait **dans le job**, le serveur calcule et stocke. Le chart 2026.x unifie les éditions (`community.enabled`) et gère ses sondes avec le code de supervision (`X-Sonar-Passcode`).

**Alternatives**
- Base embarquée H2 : refusée pour un usage réel, et perdue au redémarrage.
- SonarQube hors cluster (VM) : sépare la mémoire, mais une VM de plus à maintenir pour un essai.
- Developer Edition (payante) : analyse de MR et de branches, ce qui manque ici.

**Pièges classiques**
- Laisser `initSysctl` : conteneur privilégié dans le cluster, refusé par `restricted`.
- Oublier `ephemeral-storage` en surchargeant `resources` : Helm fusionne les cartes, la limite de 500 Go du chart reste.
- Analyser une MR en Community : l'analyse de la branche remplace celle de `main`.
- `sonar.login` (ancien nom) au lieu de `SONAR_TOKEN` ; jeton **global** d'analyse au lieu d'un jeton de projet.

**En production chez MédiSphère**
Si l'ADR-0190 le gardait : sauvegarde Barman de `sonarqube-db`, SSO (M24), édition payante pour les MR, jeton d'analyse par projet tourné tous les 90 jours. La décision du module est de le retirer (E30, mini-projet).

---

### M19-E17 — Promouvoir une image par merge request

**Solution**

Fichiers : [`ci-templates/templates/promotion/template.yml`](fichiers/M19-E17/ci-templates/templates/promotion/template.yml) (v2.4.0), [`deploiement/outils/verifier-livraison.sh`](fichiers/M19-E17/deploiement/outils/verifier-livraison.sh), [`mediagenda-api/.gitlab-ci.extrait.yml`](fichiers/M19-E17/mediagenda-api/.gitlab-ci.extrait.yml), [`essais/creer-jeton-promotion.sh`](fichiers/M19-E17/essais/creer-jeton-promotion.sh).

1. **Protection de `main`** (fait par le script, étape 1) : poussée « *No one* », fusion « *Maintainers* ». Un Developer (le robot `ci-promotion`) peut créer une branche et **ouvrir** une MR (droit de Developer), pas la fusionner (droit de fusion sur la branche protégée). En Free, l'API `PATCH /protected_branches/:name` ne change pas les niveaux d'accès (`allowed_to_*` est Premium) : on retire puis on remet la protection, d'où une fraction de seconde sans protection, hors fenêtre de promotion. Membres Maintainers attendus : `julien.petit`, `karim.benali` (et ton compte administrateur, qui hérite de tout).
2. **Jeton et variable** : [`creer-jeton-promotion.sh`](fichiers/M19-E17/essais/creer-jeton-promotion.sh) (le jeton passe de la réponse JSON à la variable par l'entrée standard de `curl`, `--data-urlencode value@-` ; il n'est jamais affiché). Au registre des secrets : identifiant du jeton, expiration, procédure `POST …/access_tokens/:id/rotate`.
3. **Composant `promotion`** :
   - une inclusion par overlay (`promouvoir-dev` en `on_success`, `promouvoir-recette` et `promouvoir-prod` en `manual` avec `allow_failure: true` pour ne pas bloquer le pipeline de l'étiquette) ;
   - `needs` : `image:publication` (pour `IMAGE_REF`) et `securite:verification` en optionnel (on ne promeut qu'une image dont la signature a été vérifiée) ;
   - authentification Git par un **assistant d'identification lu à l'exécution** (`-c credential.helper='!f() { … echo "password=${DEPLOIEMENT_TOKEN}"; }; f'`) : rien dans `.git/config` ni dans `ps` ; l'API de MR reçoit le jeton par `curl -K -` (configuration lue sur l'entrée standard) ;
   - refus propre si la branche `promotion/<overlay>-vX.Y.Z` existe (`git ls-remote --exit-code --heads`) ;
   - `livraison.yaml` (`yq -i '.data.version = strenv(VERSION)'`) **et** `kustomize edit set image <nom>=<nom>:vX.Y.Z@sha256:…`, puis le garde-fou avant la poussée.
4. **Garde-fou** : la règle « pas de `images:` » (M17-E21) devient « un seul `images:`, celui de l'API, dont `newTag` est la version de `livraison.yaml` et qui porte un `digest` ». Rejoué :
   ```
   dev : v1.2.0, conforme                                                   # après promotion simulée
   ERREUR prod : images[] sans empreinte valide (digest)                    # kustomize edit set image …:v1.0.0
   ERREUR recette : images[].newTag « v9.9.9 » ≠ livraison.yaml « v1.0.0 »  # étiquette désalignée
   ```
   Rendu de l'overlay `dev` après promotion : `image: registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.2.0@sha256:…` sur le conteneur `api` **et** le conteneur d'initialisation `migrations`, `MEDIAGENDA_VERSION=v1.2.0` (le component `livraison` remplace l'étiquette, puis le transformateur `images:` de l'overlay ajoute l'empreinte).
5. **Bout en bout.** MR `fix:` fusionnée sur `mediagenda/api` → semantic-release pose `v1.2.0` → pipeline de l'étiquette : construction, analyse, publication, signature, vérification, `promouvoir-dev` → MR « *Promouvoir mediagenda-api v1.2.0 en dev* » dans `deploiement`, ouverte par le robot `ci-promotion`, avec l'empreinte et le lien du pipeline. Julien la relit (`kustomize build overlays/dev`, diff du rendu dans les artefacts de `deploiement:valider: [dev]`), la fusionne. Jusqu'à E18 : `kubectl apply --server-side -k overlays/dev` depuis `adm01`.
6. **Essai inverse** (avec le jeton `ci-promotion`) :
   ```
   remote: GitLab: You are not allowed to push code to protected branches on this project.
   admin@adm01:~$ … -X PUT "$GL/projects/mediagenda%2Fdeploiement/merge_requests/<iid>/merge"
   {"message":"405 Method Not Allowed"}      # ou 401/403 selon la version : pas le droit de fusionner
   ```

**Explications**

La promotion par MR sépare **qui propose** (la CI, qui connaît l'image exacte construite et vérifiée) de **qui décide** (un Maintainer qui relit le rendu). L'empreinte rend la proposition infalsifiable : la même étiquette pourrait être republiée (si l'immuabilité sautait), pas la même empreinte. Le jeton de projet est un utilisateur robot membre de `deploiement` avec le rôle Developer : protections de branche et règles de fusion s'appliquent à lui comme à un humain.

**Alternatives**
- Options de poussée Git (`-o merge_request.create -o merge_request.target=main -o merge_request.remove_source_branch`) : pas d'appel d'API, mais description pauvre et erreur peu lisible si la MR existe.
- `CI_JOB_TOKEN` avec poussée entre projets autorisés (GitLab 18.4, « *Allow Git push requests* » sur la cible + liste d'autorisation) : plus de jeton longue durée ; la MR resterait à ouvrir par l'API, que le `CI_JOB_TOKEN` ne permet pas : il faudrait un jeton quand même.
- Kargo, ou Argo CD Image Updater (M20) : promotion pilotée côté GitOps.
- Approbations obligatoires de MR et environnements protégés : Premium (ADR-0051 reconduite).

**Pièges classiques**
- `kustomize edit set image` **seul** : l'image change, `MEDIAGENDA_VERSION` et l'étiquette des objets restent à l'ancienne version (désalignement que le garde-fou attrape).
- Jeton dans l'URL du dépôt (`https://ci-promotion:${TOKEN}@…`) : il finit dans `.git/config`, dans un artefact ou dans un message d'erreur de Git.
- Variable non **protégée** : n'importe quelle branche de `mediagenda/api` pourrait ouvrir des MR de promotion ou pousser dans `deploiement`.
- Jeton sans expiration : refusé par GitLab récent pour les jetons de projet ; quoi qu'il en soit, inscrire la date au registre et prévoir la rotation (E25).

**En production chez MédiSphère**
Rotation du jeton tous les 90 jours (E25), alerte 15 jours avant l'expiration ; E24 déplace la promotion sur le runner protégé ; E29 ajoute la vérification des signatures et de la provenance de chaque image dans la MR de promotion ; au M20, Argo CD applique la fusion à la place de `kubectl`.

---

### M19-E18 — Déployer en dev avec l'agent GitLab pour Kubernetes

**Solution**

Fichiers : [`k8s/.gitlab/agents/k8s-par1/config.yaml`](fichiers/M19-E18/k8s/.gitlab/agents/k8s-par1/config.yaml), [`k8s/espaces/gitlab-agent/`](fichiers/M19-E18/k8s/espaces/gitlab-agent/), [`k8s/rbac/gitlab-agent/10-agent.yaml`](fichiers/M19-E18/k8s/rbac/gitlab-agent/10-agent.yaml), [`k8s/composants/gitlab-agent/values.yaml`](fichiers/M19-E18/k8s/composants/gitlab-agent/values.yaml), [`k8s/releases/50-ci.yaml.gotmpl.extrait`](fichiers/M19-E18/k8s/releases/50-ci.yaml.gotmpl.extrait), [`k8s/secrets/gitlab-agent.yml.exemple`](fichiers/M19-E18/k8s/secrets/gitlab-agent.yml.exemple), [`k8s/outils/secrets-k8s.conf.extrait`](fichiers/M19-E18/k8s/outils/secrets-k8s.conf.extrait) ; [`ci-templates/templates/deploiement/template.yml`](fichiers/M19-E18/ci-templates/templates/deploiement/template.yml) (v2.5.0) ; [`deploiement/.gitlab-ci.yml`](fichiers/M19-E18/deploiement/.gitlab-ci.yml) ; [`ci-labo/.gitlab-ci.extrait.yml`](fichiers/M19-E18/ci-labo/.gitlab-ci.extrait.yml) ; [`essais/creer-agent.sh`](fichiers/M19-E18/essais/creer-agent.sh).

1. **Lecture.** C'est l'**agent** (agentk, dans le cluster) qui ouvre une connexion sortante longue vers KAS (le *GitLab Relay*, composant d'omnibus sur `git01`) ; GitLab n'ouvre jamais rien vers le cluster. Un `kubectl` lancé dans un job autorisé utilise le `KUBECONFIG` que GitLab lui fournit : requête vers `https://git01…/-/kubernetes-agent/k8s-proxy/`, KAS la passe dans le tunnel, agentk la rejoue auprès de l'API Kubernetes **avec son compte de service** (en Free) ; l'usurpation d'identité (`access_as: ci_job`, `impersonate`) est Premium.
2. **KAS et enregistrement.**
   ```
   admin@git01:~$ sudo gitlab-ctl status gitlab-kas
   run: gitlab-kas: (pid 1234) 86400s; run: log: (pid 1200) 86400s
   admin@git01:~$ sudo grep -n "kubernetes-agent" /var/opt/gitlab/nginx/conf/gitlab-http.conf | head -3
   admin@adm01:~$ ~/m19/e18/creer-agent.sh
   agent k8s-par1 enregistré (id 3)
   $ANSIBLE_VAULT;1.2;AES256;critique
   ```
   Le dossier `.gitlab/agents/k8s-par1/` doit être sur `main` **avant** l'enregistrement : le nom de l'agent est celui du dossier.
3. **Installation** (ordre : espace, RBAC, Secret, release) :
   ```
   admin@adm01:~/src/k8s$ task appliquer                                  # espaces/gitlab-agent/, rbac/gitlab-agent/
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer gitlab-agent
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-agent diff     # AUCUN ClusterRoleBinding dans le diff
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-agent apply
   admin@adm01:~$ kubectl -n gitlab-agent logs deploy/gitlab-agent | grep -iE 'connected|error|forbidden' | tail
   admin@adm01:~$ kubectl get clusterrolebindings -o json | jq -r '.items[] | select(any(.subjects[]?; .namespace == "gitlab-agent")) | .metadata.name'
   (rien)
   ```
   Valeurs : `rbac.create: false` (sinon ClusterRoleBinding vers `cluster-admin`), `config.kasAddress: wss://git01.par1.medisphere.internal/-/kubernetes-agent/` (le défaut du chart est `grpcs://kas.gitlab.com`), `config.secretName`, `config.kasCaCert` (racine MédiSphère), analyse des conteneurs du cluster désactivée, contexte de sécurité `restricted`. Rendu vérifié (Helm 4.3, chart 2.32.0) : Deployment, ServiceAccount, Service, ConfigMap de la racine, **aucun** objet RBAC. ⚠️ À vérifier sur ton lab : si les journaux d'agentk montrent un `forbidden` sur une ressource de **son** espace, complète le Role `agentk` (jamais au niveau du cluster).
4. **Droits.**
   ```
   admin@adm01:~$ SA=system:serviceaccount:gitlab-agent:gitlab-agent
   admin@adm01:~$ for c in "patch deployments.apps -n mediagenda-dev" "create configmaps -n wb-essais" \
         "patch clusters.postgresql.cnpg.io -n mediagenda-dev" "create configmaps -n mediagenda-recette" \
         "get secrets -n kube-system" "list nodes" "create rolebindings -n mediagenda-dev"; do
       printf '%-55s %s\n' "$c" "$(kubectl auth can-i $c --as=$SA)"; done
   patch deployments.apps -n mediagenda-dev                yes
   create configmaps -n wb-essais                          yes
   patch clusters.postgresql.cnpg.io -n mediagenda-dev     yes
   create configmaps -n mediagenda-recette                 no
   get secrets -n kube-system                              no
   list nodes                                              no
   create rolebindings -n mediagenda-dev                   no
   ```
   `edit` ne couvre pas les CRD qui ne s'y agrègent pas : le `Cluster` de CloudNativePG (chart CNPG : `rbac.aggregateClusterRoles` à `false` par défaut), la `HTTPRoute`, la `CiliumNetworkPolicy` de l'overlay `dev` ; d'où la ClusterRole `agent-ci-crd`, **liée dans les deux mêmes espaces**. Remarque de Sophie : `edit` donne la lecture des Secrets de `mediagenda-dev` ; c'est le cas de tout job autorisé du groupe `mediagenda` (sur branche protégée, environnement `dev`) : risque accepté pour la dev, inacceptable plus haut, et c'est ce que l'usurpation Premium ou Argo CD (M20) résolvent.
5. **`ci-labo`.** `agent-essai-wb-essais` liste le contexte `plateforme/k8s:k8s-par1`, crée puis supprime un ConfigMap ; `agent-essai-recette-refuse` :
   ```
   Error from server (Forbidden): configmaps is forbidden: User "system:serviceaccount:gitlab-agent:gitlab-agent" cannot create resource "configmaps" in API group "" in the namespace "mediagenda-recette"
   ```
   (le message montre bien l'identité réelle : celle de l'agent, pas celle du job).
6. **`deployer-dev`** (composant `deploiement` v2.5.0, entrée `deployer: true`) : sur une **poussée** (fusion) sur `main` protégée, ou relance manuelle ; jamais dans un pipeline déclenché par le chart (E12). `SSL_CERT_FILE` vers la racine (kubectl joint KAS par `git01`), `kubectl config use-context plateforme/k8s:k8s-par1`, `kubectl diff --server-side` (code 1 = des différences, toléré), `kubectl apply --server-side -k overlays/dev`, `kubectl rollout status deployment/mediagenda`, environnement `dev` (`deployment_tier: development`, URL publiée), `resource_group: deploiement-dev`. Après la fusion d'une MR de promotion : *Operate > Environments > dev* montre le déploiement, son job, son commit.
7. **Gestionnaire de champs.** `kubectl label deploy/mediagenda -n mediagenda-dev essai=oui` (gestionnaire `kubectl-label`, mise à jour classique) puis un `deployer-dev` : l'étiquette **reste** (l'overlay ne décrit pas ce champ, personne ne le revendique). Si l'on modifie à la main un champ que l'overlay décrit (`kubectl scale --replicas=3`, gestionnaire `kubectl` ou `kubectl-scale`), le *server-side apply* suivant remet la valeur du dépôt si le gestionnaire est le même, ou signale un **conflit** si un autre gestionnaire possède le champ : on ne force pas (`--force-conflicts`) dans un job, on corrige le dépôt ou on retire la modification manuelle. C'est la dérive que le M20 traitera avec Argo CD.

**Explications**

Le *CI/CD workflow* de l'agent est un mandat : la configuration `ci_access` (dans le projet de l'agent) dit **quels projets** reçoivent un contexte, et le RBAC du cluster dit **ce que** ce contexte permet. `protected_branches_only` et `environments` (Free) restreignent encore les jobs autorisés. La connexion part du cluster : aucun flux entrant, aucun kubeconfig longue durée dans une variable.

**Alternatives**
- Kubeconfig d'un compte de service dans une variable protégée : marche, mais c'est un secret longue durée, utilisable hors de GitLab, et qui ne disparaît pas quand on retire un projet.
- *Pull* (Argo CD, Flux) : le cluster tire l'état depuis Git ; aucun droit d'écriture donné à la CI (M20, qui retire ces accès).
- Agent en mode *receptive* (KAS se connecte à l'agent) : pour les agents qui ne peuvent pas sortir ; sans objet ici.

**Pièges classiques**
- Installer le chart avec ses valeurs par défaut : `cluster-admin` pour tout job autorisé.
- Laisser `kasAddress` au défaut (`grpcs://kas.gitlab.com`) : l'agent tente de joindre GitLab.com, échec de connexion (ou, pire, un agent du même nom ailleurs).
- `kubectl` sans `SSL_CERT_FILE` : « *x509: certificate signed by unknown authority* » vers `git01`.
- Utiliser un autre gestionnaire de champs (`--field-manager=gitlab`) que celui de M17-E25 : conflits sur tous les champs.
- `deployer-dev` déclenché aussi par le pipeline amont du chart (E12) : un chart publié déploierait la dev.

**En production chez MédiSphère**
L'agent reste pour l'observabilité et les environnements dynamiques de revue ; ses accès CI aux espaces applicatifs sont retirés en M20-E30 au profit d'Argo CD ; montée de l'agent avec GitLab (même mineure, E26 : passage en `grpcs://`) ; alerte si l'agent est déconnecté plus de 5 minutes (M21).

---

### M19-E19 — Jenkins dans Kubernetes : JCasC et agents en pods

**Solution**

Fichiers : [`k8s/composants/jenkins/values.yaml`](fichiers/M19-E19/k8s/composants/jenkins/values.yaml), [`k8s/espaces/jenkins/00-namespace.yaml`](fichiers/M19-E19/k8s/espaces/jenkins/00-namespace.yaml), [`k8s/espaces/jenkins/40-politiques-reseau.yaml`](fichiers/M19-E19/k8s/espaces/jenkins/40-politiques-reseau.yaml), [`k8s/releases/81-jenkins.yaml.gotmpl`](fichiers/M19-E19/k8s/releases/81-jenkins.yaml.gotmpl), [`k8s/secrets/jenkins.yml.exemple`](fichiers/M19-E19/k8s/secrets/jenkins.yml.exemple), [`k8s/outils/secrets-k8s.conf.extrait`](fichiers/M19-E19/k8s/outils/secrets-k8s.conf.extrait).

1. **SonarQube arrêté d'abord** : `replicas: 0` dans `composants/sonarqube/values.yaml` (MR), `helmfile -e par1 -l composant=sonarqube apply`, `kubectl get pods -n sonarqube` ne montre plus que la base `sonarqube-db` (gardée : on rallume SonarQube en remettant `replicas: 1`). Conséquence assumée : `lab/bin/check 19 16` échoue désormais sur « SonarQube répond UP » et « un pod SonarQube prêt » ; c'est attendu.
2. **Valeurs changées** (journal) : image `2.580.1-jdk21` par Harbor (le défaut du chart 5.9.72 est la variante JDK 25) ; `numExecutors: 0` ; `installPlugins` épinglés, `installLatestPlugins` et `installLatestSpecifiedPlugins` à `false` (sinon une dépendance monte toute seule au redémarrage) ; `agentListenerEnabled: false` + `agent.websocket: true` (agents par WebSocket sur le port 8080 : pas de port 50000, pas de Service supplémentaire) ; `agent.restrictedPssSecurityContext: true` ; contexte de sécurité du sidecar de rechargement (`capabilities.drop: [ALL]`, absent du défaut, refusé par `restricted`) ; `testEnabled: false` (image `bats` tirée de Docker Hub) ; `controller.httpRoute` vers `gw-par1` ; persistance `ceph-rbd` 8 Gio.
3. **Comptes** : `outils/secrets-k8s.sh appliquer jenkins` crée `jenkins-admin` et `jenkins-comptes` (valeurs dans `secrets/jenkins.yml` chiffré, identité `critique`). ⚠️ `controller.admin.createSecret` reste à `true` : avec `existingSecret`, le chart ne crée rien, mais c'est cette option qui monte le Secret existant sous les noms `chart-admin-username` / `chart-admin-password` que le JCasC utilise ; à `false`, le compte `admin` n'existe plus (constaté dans le gabarit du StatefulSet du chart). Les autres mots de passe passent par `controller.additionalExistingSecrets` → `${jenkins-comptes-<clé>}`.
4. **Installation** : `helmfile -e par1 -l composant=jenkins apply`, puis `kubectl logs -n jenkins jenkins-0 -c init -f` (téléchargement des greffons, ≈ 2 min) et `-c jenkins -f` jusqu'à « *Jenkins is fully up and running* ». Contrôles : *Manage Jenkins > About* (2.580.1), *Plugins > Installed* (les 9 greffons + leurs dépendances, rien de « mis à jour »), *Configuration as Code > View Configuration*, *Nodes* : `Built-In Node` à 0 exécuteur.
5. **`essai-agent`** : `kubectl get pods -n jenkins -w` montre un pod `default-xxxxx` (un seul conteneur `jnlp`, `inbound-agent` en `-jdk21`), `Running`, puis `Terminating` dès la fin du build (`podRetention: Never`). Journal de l'agent : `WebSocket connection open` vers `http://jenkins.jenkins.svc.cluster.local:8080/`. Le build affiche `uid=1000(jenkins)`.
6. **Jeton de `wb-checks`** : connecté en `wb-checks`, *Security > API Token > Add new token* (nom `workbook-checks`) ; puis
   ```
   admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/jenkins-checks.env
   admin@adm01:~$ cat > ~/.config/workbook/jenkins-checks.env    # JENKINS_USER=wb-checks, JENKINS_TOKEN=<jeton>, Ctrl-D
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://jenkins.apps.par1.medisphere.internal/api/json
   403
   ```
7. **Réglage modifié à la main** (le message système, par exemple) : il tient jusqu'au redémarrage du pod (ou jusqu'au prochain rechargement du sidecar), puis JCasC le remet (`overwriteConfiguration: true`). Conclusion : l'interface sert à **lire** ; toute modification passe par une MR sur les values. Ce qui n'est pas dans JCasC (historique des builds, jetons d'API des comptes) vit dans `JENKINS_HOME` et n'est pas reconstruit.

**Explications**

Le chart assemble le JCasC : une partie générée (nuage Kubernetes, agent par défaut, URL) quand `JCasC.defaultConfig: true`, plus les morceaux de `securityRealm`, `authorizationStrategy` et `configScripts`, chacun dans un ConfigMap étiqueté `jenkins-jenkins-config: "true"` que le sidecar recharge à chaud. Les jobs sont créés par **Job DSL** (greffon `job-dsl`, ajouté à la liste de l'énoncé : c'est lui qui donne la clé `jobs:` à JCasC) ; « *ou par un pipeline en ligne* » de l'énoncé : le job `essai-agent` est justement un pipeline en ligne défini par Job DSL.

**Alternatives**
- Opérateur Jenkins (`jenkins-operator`) : peu actif, pas de raison de l'introduire pour un essai.
- Jenkins sans persistance (*Pour aller plus loin*) : tout est reconstruit au démarrage, on perd l'historique des builds et les jetons d'API (à recréer, ou à fournir par JCasC).
- Port 50000 (TCP) pour les agents : une règle réseau et un Service de plus ; WebSocket suffit dans le cluster.

**Pièges classiques**
- Laisser la mise à jour automatique des dépendances : un greffon change tout seul et le contrôleur ne démarre plus.
- Une clé JCasC définie deux fois (dans `configScripts` et par le chart, `jenkins.securityRealm` par exemple) : « *ConfiguratorException* », le contrôleur reste en échec. Lire le ConfigMap généré.
- `java -version` en 17 : la LTS 2.555.1 et suivantes exigent Java 21 ; l'image `-jdk17` n'existe plus pour ces versions.
- Oublier le contexte de sécurité du sidecar : le StatefulSet est créé mais aucun pod n'est admis (`kubectl get events -n jenkins` : *violates PodSecurity "restricted"*).
- `${…}` dans un script Job DSL : JCasC l'interpole avant Job DSL (pour un `$` littéral, écrire `^${…}`).

**En production chez MédiSphère**
Pas de Jenkins (ADR-0190, E30). Si l'équipe rachetée en gardait un le temps de sa migration : SSO (M24) à la place des comptes locaux, greffons revus à chaque avis de sécurité, sauvegarde de `JENKINS_HOME` (M22), contrôleur dans un espace isolé, aucun *credential* global.

---

### M19-E20 — Le même pipeline en Jenkinsfile

**Solution**

Fichiers : [`mediagenda-api/Jenkinsfile`](fichiers/M19-E20/mediagenda-api/Jenkinsfile), [`k8s/composants/jenkins/values.yaml`](fichiers/M19-E20/k8s/composants/jenkins/values.yaml) (version complète, remplace celle de E19), [`k8s/espaces/jenkins/30-racine-ca.yaml`](fichiers/M19-E20/k8s/espaces/jenkins/30-racine-ca.yaml), [`k8s/espaces/jenkins/40-politiques-reseau.yaml`](fichiers/M19-E20/k8s/espaces/jenkins/40-politiques-reseau.yaml), [`k8s/composants/buildkitd/values.yaml.extrait`](fichiers/M19-E20/k8s/composants/buildkitd/values.yaml.extrait), [`k8s/outils/secrets-k8s.conf.extrait`](fichiers/M19-E20/k8s/outils/secrets-k8s.conf.extrait), [`medisphere/docs/livraison/ci/comparatif-jenkins.md`](fichiers/M19-E20/medisphere/docs/livraison/ci/comparatif-jenkins.md).

1. **Jeton de déploiement** `jenkins-lecture` de `mediagenda/api` (*Settings > Repository > Deploy tokens*, portée `read_repository`, expiration à la fin de l'essai) ; nom d'utilisateur et jeton dans `secrets/jenkins.yml` (`jenkins_gitlab_lecture_*`), puis `outils/secrets-k8s.sh appliquer jenkins` → Secret `jenkins-gitlab`.
2. **JCasC** : *credential* `gitlab-lecture` (`usernamePassword`, greffon `credentials` épinglé), job `mediagenda-api` (`cpsScm`, branche `*/essai-jenkins`, `lightweight`), `GIT_SSL_CAINFO` et la racine montée sur le contrôleur (il lit le `Jenkinsfile` lui-même).
3. **buildkitd** : `jenkins` ajouté à `tls.clients` et `reseau.espacesClients` du chart `buildkitd` (exception datée dans la MR et au registre des exceptions réseau) : le chart émet le Secret `buildkit-client` dans `jenkins` et ouvre l'entrée de `buildkitd` aux pods de cet espace qui portent `medisphere.internal/ci: job`. Côté `jenkins`, la politique de sortie des agents (`40-politiques-reseau.yaml`) autorise le DNS, le contrôleur (8080, WebSocket), `git01:443`, `buildkitd.buildkit:1234` (le temps de l'essai) et le 443 sortant (dépendances Python de `uv sync`, comme les jobs de `ci-jobs`).
4. **`Jenkinsfile`** : pod à trois conteneurs (`jnlp` décrit pour lui poser la racine et un contexte `restricted`, `uv`, `buildkit` en `sleep infinity`), étiquette `medisphere.internal/ci: job`, `automountServiceAccountToken: false` ; `buildctl --tlsdir /etc/buildkit/client` (le répertoire contient `ca.crt`, `tls.crt`, `tls.key`, que `buildctl` reconnaît) ; sortie `type=oci,dest=image.tar` locale, supprimée en `post`. ⚠️ À vérifier sur ton lab : avec un démon distant, l'archive OCI est **renvoyée au client** par la session ; si ton démon refuse, utilise `type=tar` ou `--output type=image,push=false`.
5. **Mesures** (commandes en fin du comparatif) : durée de 3 builds par `…/job/mediagenda-api/api/json?tree=builds[number,result,duration]{0,3}`, durée de 3 pipelines GitLab équivalents par l'API (somme des jobs `qualite:lint`, `qualite:tests`, `image:construction` **et** durée de bout en bout, pour comparer ce qui est comparable).
6. **Comparatif** : voir le fichier (les chiffres sont un **exemple** plausible ; seuls les tiens comptent). Conclusion attendue, quel que soit le détail des chiffres : GitLab CI retenu (identités et protections héritées de la forge, pas d'état, pas de greffons, parallélisme natif), Jenkins gardé le temps d'une migration au plus.
7. **Fin de l'essai** : `jenkins` retiré des deux listes de `buildkitd`, `helmfile … apply` : le Secret `buildkit-client` de l'espace `jenkins` et l'ouverture réseau disparaissent ; le build suivant échoue à l'étape `Image` (`connection refused` ou `context deadline exceeded`) : c'est attendu. Jeton de déploiement révoqué à la fin du mini-projet.

**Explications**

Le `Jenkinsfile` refait à la main ce que les composants donnent : chaque projet porte son pod, ses images, ses options. La *Shared Library* serait l'équivalent des composants, mais sans catalogue ni version sémantique résolue par la forge (référence de branche ou d'étiquette, `@Library('lib@v1')`). La lecture du dépôt demande un jeton longue durée hors de GitLab, là où un job GitLab a un `CI_JOB_TOKEN` éphémère.

**Alternatives**
- Greffon `gitlab-plugin` + webhook pour déclencher Jenkins à chaque poussée et publier le statut dans la MR : un jeton `api` de plus, et un flux GitLab → Jenkins à ouvrir ; inutile pour une mesure.
- Construction par Kaniko dans le pod : abandonné par son mainteneur d'origine, et on dupliquerait le chemin buildkitd déjà durci.

**Pièges classiques**
- Ne pas décrire `jnlp` : le greffon l'ajoute sans la racine ni le contexte de sécurité voulu ; le clone échoue en `x509` ou le pod est refusé.
- Étiquette `medisphere.internal/ci: job` oubliée : la politique d'entrée de `buildkitd` coupe, l'étape `Image` reste bloquée jusqu'au délai.
- Mettre le jeton de lecture dans l'URL du dépôt (`https://user:jeton@…`) : il apparaît dans les journaux et dans `config.xml`.
- Comparer la durée du pipeline GitLab de `main` (publication, signature, semantic-release) à celle du build Jenkins sans publication.
- Oublier l'étape 5 : l'exception réseau « temporaire » devient permanente.

**En production chez MédiSphère**
Le comparatif nourrit l'ADR-0190 (E30). Aucune exception réseau vers `buildkitd` ne survit à un essai : chaque exception a une date de fin et un propriétaire au registre (M16).

---

### M19-E21 — Revue : le `.gitlab-ci.yml` du stagiaire

**Solution**

Fichiers : la revue complète [`revue.md`](fichiers/M19-E21/revue.md) (23 défauts, lignes du fichier fourni, catégorie, gravité, risque, correction) et la version corrigée [`ci-labo/.gitlab-ci.yml`](fichiers/M19-E21/ci-labo/.gitlab-ci.yml) (branche `revue-lucas`).

Les défauts **bloquants**, à citer en tête de la revue :
1. mot de passe du robot Harbor en clair dans le dépôt (→ **rotation immédiate**, la suppression du fichier ne suffit pas : l'historique le garde) ;
2. Docker-in-Docker, donc runner privilégié (→ composant `construction-image`, buildkitd) ;
3. `set -x` avant `docker login -p` (secret dans le journal) ;
4. Trivy et Gitleaks en `allow_failure: true` (analyses décoratives) ;
5. déploiement en `needs: []` + `when: always` (on déploie malgré l'échec des tests) ;
6. `KUBECONFIG_DEV` non protégée utilisable depuis n'importe quelle branche.

Viennent ensuite les majeurs (images `latest` hors Harbor, `latest` réutilisée par l'analyse et le déploiement, analyse **après** la poussée, cache global à clé fixe, `curl | sh`, `ruff … || true`, absence de `workflow:rules`, absence de `tags:` qui laisse les jobs en attente sur `k8s-par1`, `kubectl set image` impératif) et les mineurs (`only`/`except`, artefacts sans expiration, `GIT_DEPTH: "0"` global, `apt-get` à chaque job, pas d'`interruptible`, `uv sync` sans `--locked`, `needs` inutile des tests vers l'image).

Validation par l'API sans exécuter (jeton d'écriture : l'API de lint demande un accès Developer) :
```
admin@adm01:~/src/ci-labo$ jq -n --rawfile c .gitlab-ci.yml '{content: $c, dry_run: true, ref: "revue-lucas"}' \
    | ecrire -H 'Content-Type: application/json' --data @- "$GL/projects/formation%2Fci-labo/ci/lint" \
    | jq '{valid, errors, warnings}'
```
Le fichier de Lucas est **valide** (le lint ne juge ni la sécurité ni le bon sens : c'est l'objet de la revue) ; la version corrigée aussi, et son pipeline (MR) est vert : commitlint, lint, tests, hadolint, construction sans publication, Trivy, SBOM, Semgrep, Gitleaks.

**Explications**

Une bonne revue relie chaque défaut à **ce qui arrive** (qui peut faire quoi, quand le pipeline ment) plutôt qu'à une règle. La correction tient en 30 lignes parce que les composants portent les choix : c'est l'argument de E10, vu depuis l'autre côté. Ce qui ne relève pas de `ci-labo` (publication, signature, déploiement) est retiré et renvoyé à son projet, pas « corrigé sur place ».

**Pièges classiques**
- Supprimer le mot de passe dans un commit et s'arrêter là, sans rotation.
- Se contenter de passer `allow_failure` à `false` en gardant Trivy après la poussée.
- Remplacer `latest` par une étiquette sans empreinte.
- Corriger en gardant un job `deploy` « parce que ça marchait » : un déploiement depuis `ci-labo` n'a pas lieu d'être.

**En production chez MédiSphère**
La grille de revue (image, privilège, secret, règles, cache, artefacts, `needs`, analyses, code téléchargé) est ajoutée aux normes de pipeline (E11, §5) ; Gitleaks côté serveur (M01) et la politique d'images de Harbor (M13) rattrapent les deux premiers défauts même sans revue.

---

### M19-E22 — Runbook : un pipeline reste en attente

**Solution**

Fichier : [`medisphere/docs/livraison/ci/runbooks/RB-190-pipeline-en-attente.md`](fichiers/M19-E22/medisphere/docs/livraison/ci/runbooks/RB-190-pipeline-en-attente.md).

Points attendus dans ton runbook, à comparer au corrigé :
1. **Six branches** de l'arbre, dans l'ordre où on les lit : A pipeline non créé (`workflow:rules`, erreur de YAML ou d'inclusion, composant introuvable, utilisateur bloqué) ; B job `created` (attend un `needs`, un stage, un `resource_group`, une action manuelle) ; C aucun runner éligible (étiquettes, `run_untagged`, `ref_protected` sur une branche non protégée, runner en pause, verrouillé à un autre projet, hors ligne) ; D runner éligible mais saturé (`concurrent`, `limit`, `request_concurrency`, jobs bloqués qui occupent les places) ; E pod qui ne démarre pas (quota `quota-ci` atteint, LimitRange `limites-ci` qui refuse, `Pending` faute de ressources, taint, `ImagePullBackOff`, Secret absent, `buildkit-client` ou `medisphere-racine` manquant) ; F pod qui tourne sans progresser (Harbor, `buildkitd`, `s3-01` injoignables). Au moins huit causes, chacune avec **sa** commande de constat.
2. Pour chaque cause : la commande exacte (`GET /projects/:id/jobs/:id`, `GET /runners/:id`, `GET /runners/:id/managers`, `kubectl logs -n gitlab-runner deploy/gitlab-runner`, `kubectl get events -n ci-jobs --sort-by=.lastTimestamp`, `kubectl describe quota -n ci-jobs`), ce qu'on lit, la cause, l'action d'astreinte.
3. **Actions autorisées la nuit**, toutes réversibles et sans perte : relancer ou annuler un job, reprendre un runner en pause (s'il a été mis en pause par erreur), redémarrer le gestionnaire (`kubectl rollout restart`), supprimer un pod de job orphelin, annuler les pipelines obsolètes qui occupent la file. **Jour ouvré** : changer les étiquettes ou la protection d'un runner, relever `concurrent` ou le quota, modifier une politique réseau, toucher aux certificats.
4. Communication : canal d'incident, message type (« pipelines en attente depuis HH:MM, cause identifiée/en cours, contournement, prochaine nouvelle à HH:MM »), escalade vers Karim (runners) ou Sophie (sécurité) ; critères de sortie (un pipeline de référence de bout en bout vert, file vide).
5. Pièges : confondre « *stuck* » (aucun runner) et « *pending* » (runner occupé) ; relancer en boucle un job dont le pod est refusé par le quota ; décocher `ref_protected` pour « débloquer » (contourne le cloisonnement des secrets) ; supprimer des pods d'un autre espace que `ci-jobs`.

**Explications**

L'arbre suit le chemin d'un job : la forge crée le pipeline, le job attend ses dépendances, un runner éligible le prend, le gestionnaire crée un pod, Kubernetes le planifie et le démarre, le job joint ses dépendances. Chaque maillon a un symptôme et un endroit où le lire ; l'astreinte n'a pas besoin de connaître GitLab, seulement de suivre le chemin.

**Pièges classiques** (de rédaction) : un runbook qui donne des commandes sans dire ce qu'on doit lire ; des actions irréversibles proposées la nuit ; un arbre qui commence par Kubernetes alors que la moitié des causes sont côté GitLab.

**En production chez MédiSphère**
RB-190 est lié depuis l'alerte « file de jobs en attente » (M21, métrique `gitlab_runner_jobs` et temps d'attente) ; il est rejoué à chaque montée de version des runners (E26).

---

### M19-E23 — Accélérer un pipeline lent

**Solution**

Fichiers : [`essais/mesurer.sh`](fichiers/M19-E23/essais/mesurer.sh), [`ci-templates/templates/qualite/template.yml`](fichiers/M19-E23/ci-templates/templates/qualite/template.yml) et [`ci-templates/templates/construction-image/template.yml`](fichiers/M19-E23/ci-templates/templates/construction-image/template.yml) (v2.6.0), [`infra/registre/robots.tf.extrait`](fichiers/M19-E23/infra/registre/robots.tf.extrait), [`medisphere/docs/livraison/ci/mesures-pipeline.md`](fichiers/M19-E23/medisphere/docs/livraison/ci/mesures-pipeline.md).

1. **Mesure** : `~/m19/e23/mesurer.sh mediagenda/api 5` (jeton des vérifications ; pipelines `source=merge_request_event` réussis) affiche, par pipeline, durée et attente, puis par job durée, attente et stage, et enfin les médianes. Référence de l'exemple : **545 s** ; chemin critique `qualite:lint` → `qualite:tests` → `qualite:tests-integration` → `image:construction` → `securite:trivy` (les stages imposent l'attente).
2. **Seuil** : 545 × 0,6 = 327 → ligne `Seuil : 327 s` (exactement sous cette forme, en début de ligne : la vérification la lit). Ton seuil vient de **ta** référence.
3. **Leviers** (composants v2.6.0, un par MR, mesurés un par un ; détail et gains dans le livrable) :
   - `needs: []` pour les tests et la construction, la **publication** attendant les tests par des `needs` optionnels (`optional: true`) : on ne publie toujours rien de non testé ;
   - cache `uv` : `key: {files: [uv.lock], prefix: uv}` (partagé par toutes les branches tant que le verrou ne change pas), `policy` choisie par une variable posée par `rules` (`pull-push` sur `main`, `pull` ailleurs), `uv cache prune --ci` avant l'envoi ;
   - cache BuildKit **en lecture** dans les MR : robot Harbor `cache-buildkit-lecture` (tirage seul, état `registre` de `plateforme/infra`) dans les variables d'instance **non protégées** `BUILDKIT_CACHE_LECTURE_UTILISATEUR` / `_JETON` (masquée) ; `--import-cache` seulement, jamais `--export-cache` hors références protégées ;
   - `GIT_DEPTH: "1"` par défaut, `"0"` seulement pour `qualite:commitlint` (et Gitleaks dans `securite`, déjà en historique complet depuis E15) ;
   - `FF_USE_FASTZIP: "true"` et niveaux `CACHE_COMPRESSION_LEVEL` / `ARTIFACT_COMPRESSION_LEVEL` (`fastest` pour `image.tar`, déjà compressée) ; ⚠️ À vérifier sur ton lab : la valeur par défaut de `FF_USE_FASTZIP` dépend de la version du Runner (désactivée dans les versions documentées jusqu'en 19.3, activée ensuite, puis l'option disparaît) : la poser explicitement ne coûte rien ;
   - artefacts limités (rapports, `coverage.xml`, `image.tar` avec `expire_in: 1 day`) ;
   - `interruptible: true` sur tous les jobs sans effet de bord (pas sur la publication) et `workflow:auto_cancel:on_new_commit: interruptible` dans le projet (déjà présent depuis E11).
4. **Mesure finale** : médiane de 3 pipelines de MR ≤ seuil (exemple : 254 s, −53 %). Le gain principal vient de `needs` et du cache BuildKit en lecture ; les autres leviers comptent peu en durée, davantage en charge des runners et en stockage.
5. **Aucune vérification retirée** : comparer les noms de jobs avant et après :
   ```
   admin@adm01:~$ for p in <ID_AVANT> <ID_APRES>; do lire "$GL/projects/mediagenda%2Fapi/pipelines/$p/jobs?per_page=100" | jq -r '.[].name' | sort > ~/m19/e23/jobs-$p.txt; done
   admin@adm01:~$ diff ~/m19/e23/jobs-<ID_AVANT>.txt ~/m19/e23/jobs-<ID_APRES>.txt && echo "même liste de jobs"
   ```
6. Monter `mediagenda/api` sur `qualite@v2.6.0` et `construction-image@v2.6.0` (les autres composants peuvent rester à leur version : chaque inclusion est épinglée séparément).

**Explications**

La durée d'un pipeline est son chemin critique, plus les attentes de planification. Les stages sérialisent tout ; `needs` transforme le pipeline en graphe et ne garde que les dépendances réelles. Un cache n'accélère que s'il est **trouvé** (clé stable : le fichier de verrou) et ne coûte que s'il est **réécrit** (politique `pull` hors de `main`). Le cache BuildKit est le levier le plus fort, mais il pose une question de sécurité : une MR ne doit jamais **écrire** dans le cache de `main` (empoisonnement), d'où un robot en lecture seule distinct du robot protégé de E08.

**Alternatives**
- Cache BuildKit en lecture **et** écriture par branche (`cache-buildkit:<slug>` non protégé) : plus chaud pour les branches longues, mais une MR peut alors écrire dans le registre ; refusé.
- Découper `qualite:tests-integration` en parallèle (`parallel: 2` + `pytest-split`) : utile au-delà de 3 minutes de tests, pas ici.
- Base Trivy servie par Harbor (`TRIVY_DB_REPOSITORY`) : prochain levier (chemin critique après).

**Pièges classiques**
- Mesurer un seul pipeline : la variance (cache froid, nœud chargé) dépasse le gain de la plupart des leviers.
- `cache:key:files` sans `prefix` : deux jobs aux contenus différents (uv, Go) partageraient la même clé.
- `needs: []` sur la **publication** : une image part dans Harbor avant la fin des tests.
- Mettre le jeton du robot de lecture dans une variable protégée : les MR ne le voient pas, aucun gain (c'est exactement le problème de départ).
- `GIT_DEPTH: 1` pour Gitleaks ou commitlint : la plage de commits n'existe plus, l'analyse passe à vide (faux vert).

**En production chez MédiSphère**
Le seuil devient un objectif suivi : le script de mesure tourne chaque semaine (M21 en fera un tableau de bord DORA avec E28), et toute nouvelle vérification ajoutée aux composants s'accompagne d'une mesure avant/après dans la MR.
