# Module 19 — Palier 2 : Opérationnel

Le palier 1 a posé la machinerie : un runner `k8s-par1` dont les jobs tournent dans `ci-jobs`, un cache S3, un démon BuildKit *rootless* partagé, Mailpit pour les courriels de GitLab, et le projet d'essai `formation/ci-labo`. Mais chaque projet recopie encore ses gabarits, les analyses de sécurité sont dispersées, l'image signée de MédiAgenda reste dans Harbor sans que personne ne la propose aux environnements, et la mise en dev se fait toujours depuis `adm01`. Ce palier traite les demandes courantes d'une équipe qui **exploite** une chaîne de CI : des **composants CI/CD** versionnés et publiés dans le catalogue, le pipeline standard de MédiAgenda, les pipelines enfants et multi-projets, les pipelines de MR avec rapports, les services de job, les analyses de code (Semgrep, Gitleaks), SonarQube à l'essai, la **promotion des images par MR** et le **déploiement en dev par l'agent GitLab**, puis Jenkins pour comparer. Tu termines en relisant le pipeline de Lucas, en écrivant le runbook « un pipeline reste en attente » et en faisant maigrir le pipeline de MR de MédiAgenda.

> **Rappels du module** (introduction) : la configuration des runners, de l'agent, des espaces et des composants du cluster vit dans `plateforme/k8s` (clone `~/src/k8s`, Helmfile `releases/*.yaml.gotmpl`, `composants/`, `espaces/`, `rbac/`) ; les composants CI/CD dans `plateforme/ci-templates` (clone `~/src/ci-templates`) ; la documentation dans `docs/livraison/ci/` de `plateforme/medisphere` (`~/medisphere`). Tout passe par une MR relue. Aucun secret dans Git : Ansible Vault `critique` (`secrets/<composant>.yml` de `plateforme/k8s`) puis `outils/secrets-k8s.sh` (E04) pour les Secrets Kubernetes ; les variables de CI se créent par l'interface ou l'API et s'inscrivent au registre des secrets (M01). Les commandes partent de `adm01` (`admin@adm01:~$`).

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Runner des jobs | `k8s-par1` (E04) : étiquettes `k8s`, `kubernetes`, `run_untagged: false` ; jobs dans `ci-jobs`, compte de service `ci-job` ; release Helmfile `gitlab-runner`, values `composants/gitlab-runner/values.yaml` ; `runner02` (étiquette `docker`) reste pour les projets pas encore migrés |
| BuildKit (E08) | le runner donne aux jobs `BUILDKIT_HOST=tcp://buildkitd.buildkit.svc.cluster.local:1234` et `BUILDKIT_TLS_DIR=/etc/buildkit/client` (Secret `buildkit-client`, TLS mutuel) ; cache `registry.par1.medisphere.internal/plateforme/cache-buildkit:<slug du projet>`, robot `robot$plateforme+cache-buildkit` dans les variables d'instance **protégées** `BUILDKIT_CACHE_UTILISATEUR` et `BUILDKIT_CACHE_JETON` ; racine MédiSphère dans les jobs : `/etc/medisphere/ca/medisphere-root-ca.crt` |
| Composants CI/CD | projet `plateforme/ci-templates`, `templates/<composant>/template.yml` + `README.md` par composant : `qualite`, `construction-image`, `securite`, `deploiement`, `release` (E10), `promotion` (E17). Étiquettes **`vX.Y.Z`** posées par semantic-release (M01), publiées dans le catalogue par un job `release:` ; **v2.0.0** en E10, puis une version mineure par exercice qui ajoute une fonction. Les gabarits v1 quittent `templates/` (dossier `gabarits-v1/`) ; les projets pas encore migrés gardent leur référence v1 épinglée |
| Images d'outils (par les caches de Harbor, étiquette **et** empreinte) | `ghcr/astral-sh/uv:0.12.23-python3.13-trixie-slim`, `dockerhub/moby/buildkit:v0.34.1-rootless`, `plateforme/outils-supply-chain:1.0.x` (M13 : Cosign, Trivy, Syft, Skopeo, clé publique, configuration de signature), `dockerhub/commitlint/commitlint:21.2.3`, `dockerhub/semgrep/semgrep:1.182.0-nonroot`, `ghcr/gitleaks/gitleaks:v8.30.1`, `dockerhub/alpine/k8s:1.36.5` (kubectl, kustomize, kubeconform, git, curl, jq), `gitlab/gitlab-org/cli:v1.124.0` (glab, cache `gitlab` de E04) |
| Variables existantes | instance : `MEDISPHERE_ROOT_CA` (fichier) ; groupes `mediagenda` et `medidoc` : `HARBOR_ROBOT_USER`, `HARBOR_ROBOT_TOKEN`, `COSIGN_PRIVATE_KEY` (fichier), `COSIGN_PASSWORD` (protégées, M13), `HARBOR_CHARTS_*`, `HARBOR_CHARTS_RO_*` (M17) ; projets : `GITLAB_TOKEN` (jeton `bot-release`, M01) |
| Projets | `mediagenda/api` (`~/src/mediagenda-api`), `mediagenda/chart` (`~/src/mediagenda-chart`), `mediagenda/deploiement` (`~/src/mediagenda-deploiement`), `formation/ci-labo` (`~/src/ci-labo`) |
| Nouveaux composants du cluster | espaces `sonarqube` (E16), `gitlab-agent` (E18), `jenkins` (E19) ; releases Helmfile `gitlab-agent` (ajoutée à `releases/50-ci.yaml.gotmpl`, à côté de `gitlab-runner` et `buildkitd`), `sonarqube` (`releases/80-sonarqube.yaml.gotmpl`), `jenkins` (`releases/81-jenkins.yaml.gotmpl`) ; SonarQube et Jenkins **jamais en même temps** |
| Promotion (E17) | jeton de projet `ci-promotion` de `mediagenda/deploiement` (Developer, `api` + `write_repository`, 90 jours) → variable protégée et masquée `DEPLOIEMENT_TOKEN` de `mediagenda/api` ; branches `promotion/<env>-vX.Y.Z` |
| Agent (E18) | `k8s-par1`, configuration `.gitlab/agents/k8s-par1/config.yaml` de `plateforme/k8s`, contexte CI `plateforme/k8s:k8s-par1`, `config.kasAddress` = `wss://git01.par1.medisphere.internal/-/kubernetes-agent/` (19.4) |
| Documentation | `docs/livraison/ci/` : `normes-pipeline.md` (E11), `comparatif-jenkins.md` (E20), `RB-190-pipeline-en-attente.md` (E22), `mesures-pipeline.md` (E23) ; brouillons dans `~/m19/eXX/` |

> 💡 **Mémoire.** Le profil du bloc compte ≈ 100 Go. SonarQube (E16, ≈ 3 Gio) et Jenkins (E19-E20, ≈ 2 Gio avec un agent) sont **temporaires et jamais ensemble** : SonarQube passe à `replicas: 0` avant E19. Garde `kubectl top nodes` sous les yeux quand ils tournent.

Durée indicative du palier : 28 à 34 heures. Ordre conseillé :

```
E10 ─ E11 ─ E13 ─ E14 ─ E15 ─ E23
 │      └── E17 ─ E18
 └── E12 (après E10)      E16 (après E11)   E19 ─ E20 (après E16, SonarQube arrêté)
E21 (après E10)   E22 (à tout moment)
```

---

### M19-E10 — Des gabarits aux composants CI/CD  `LAB` `★★★`

> **Ticket PLAT-2010** — *De : Karim Benali*
> On a quatre gabarits dans `plateforme/ci-templates`, inclus par `include: project` avec des variables magiques que personne ne documente : `SC_IMAGE_NOM`, `IMAGE`, `PUBLIER`… Quand Lucas a fait une faute de frappe dans `SC_IMAGE_NOM`, le pipeline est parti publier une image sans nom. GitLab sait faire des **composants** : des paramètres déclarés, typés, validés, documentés, un catalogue où les équipes trouvent ce qui existe. Je veux la v2 de nos gabarits en composants, publiée proprement, et `ci-labo` comme premier client.

**Objectifs pédagogiques**
- Comprendre ce qu'apporte un composant par rapport à `include: project` : en-tête `spec:inputs`, interpolation `$[[ inputs.x ]]` à la création du pipeline, validation des types, versions.
- Écrire des entrées typées (`string`, `boolean`, `number`, `array`), avec valeurs par défaut, `options` et `regex`.
- Publier une version dans le catalogue CI/CD de l'instance (projet de catalogue, description, `README.md`, job `release:`), et savoir ce que résout `@v2.0.0`, `@2` et `@~latest`.
- Tester un composant dans son propre dépôt avant de le publier.

**Prérequis** : M19-E04 à E08 (runner, cache, buildkitd), M01-E24/E25 (gabarits `qualite.yml`, `release.yml`, semantic-release), M13-E09 (`supply-chain.yml`).
**Durée indicative** : 4 h.

**Contexte technique**
- Arborescence attendue : `templates/qualite/template.yml`, `templates/construction-image/template.yml`, `templates/securite/template.yml`, `templates/deploiement/template.yml`, `templates/release/template.yml`, chacun avec un `README.md` à côté ; `README.md` à la racine avec une section `## Composants`. GitLab considère comme composant **tout** fichier `templates/<nom>.yml` et tout `templates/<nom>/template.yml`, et cherche d'abord la première forme : les gabarits v1 (`templates/qualite.yml`, `templates/release.yml`…) ne peuvent pas rester à leur place. Les projets encore en v1 incluent une **référence épinglée** (`ref: v1.x.y` ou la branche `v1`) : ils ne voient pas ce que change `main`.
- Ce que chaque composant doit faire (sur l'étiquette `k8s`) :
  - `qualite` : `commitlint`, `lint` et `tests` (rapport JUnit), pour un projet Python (uv, ruff, pytest) ou Go (`go vet`, `gofmt`, `go test`), selon une entrée `langage` ;
  - `construction-image` : lint du Dockerfile (Hadolint), construction par **buildkitd distant** en archive OCI avec provenance, cache de registre, puis publication par Skopeo (refus de réécrire une étiquette existante) ; sortie `dotenv` `IMAGE_REF` = `<registre>/<projet>/<dépôt>@sha256:…` ;
  - `securite` : Trivy sur l'archive (bloquant avant publication), SBOM Syft (artefact), signature Cosign de l'index et des manifestes de plateforme (méthode du M13 : configuration de signature sans service, variables protégées du groupe), vérification ;
  - `deploiement` : `kustomize build` de chaque overlay et `kubeconform` sur le rendu ;
  - `release` : semantic-release sur la branche par défaut protégée (étiquette `vX.Y.Z`), sur l'étiquette `k8s` et non plus sur `runner01`.
- Noms de jobs, sur lesquels s'appuient les projets, les vérifications et les paliers suivants : `<composant>:<action>` (`qualite:commitlint`, `qualite:lint`, `qualite:tests`, `image:hadolint`, `image:construction`, `image:publication`, `securite:trivy`, `securite:sbom`, `securite:signature`, `securite:verification`, `deploiement:valider`, `release:semantic-release`), sauf les jobs liés à un environnement (`deployer-dev` en E18, `promouvoir-dev` en E17). Le composant `securite` reçoit les noms des jobs de construction et de publication en entrées (`job_construction`, `job_publication`).
- Le catalogue n'accepte que les versions publiées par le **mot-clé `release:`** d'un job (pas par l'API des releases, que le greffon `@semantic-release/gitlab` utilise). Le job a besoin de `glab` dans son image et de la racine MédiSphère (`ADDITIONAL_CA_CERT_BUNDLE`).
- Le projet doit être déclaré **projet de catalogue** (*Settings > General > Visibility, project features, permissions*, rôle Owner) et avoir une description.

**Travail demandé**
1. Lis la page *CI/CD components* et la référence `spec:inputs` de la documentation GitLab. Dans `~/m19/e10/journal.md` : quelle différence entre une entrée (`inputs`) et une variable de CI (quand chacune est-elle résolue, qui peut la changer, peut-elle valoir autre chose qu'une chaîne) ? Que se passe-t-il si l'appelant passe une entrée inconnue ? Pourquoi un composant ne doit-il pas définir `workflow`, `stages` ni `default` ?
2. Inventorie les variables d'entrée de chaque ancien gabarit (`qualite.yml`, `image.yml`, `supply-chain.yml`, `verification.yml`) : nom, rôle, valeur par défaut, valeurs possibles. Déduis-en les entrées de chaque composant ; ajoute au moins `stage`, `runner` (étiquette, défaut `k8s`) et un préfixe de nom de job quand deux inclusions d'un même composant doivent coexister.
3. Écris les cinq composants dans une branche de `plateforme/ci-templates`. Contraintes : aucune image sans étiquette **et** empreinte, aucune image hors de Harbor, aucun `latest`, `interruptible` sur tout ce qui peut l'être, artefacts avec `expire_in`, entrées validées (`options` ou `regex`) dès qu'une valeur fausse peut faire des dégâts (nom d'image, sévérité Trivy).
4. Fais tester les composants par le pipeline de `plateforme/ci-templates` lui-même : inclusion `component: $CI_SERVER_FQDN/$CI_PROJECT_PATH/<nom>@$CI_COMMIT_SHA` sur un petit projet d'échantillon rangé dans le dépôt (dossier `tests/`), et un job qui interroge l'API pour vérifier que les jobs attendus existent.
5. Publication : adapte `.releaserc.json` pour que semantic-release ne pose que l'**étiquette** (et calcule la version), ajoute un job `publier-catalogue` qui, sur une étiquette `vX.Y.Z`, crée la release par le mot-clé `release:` avec des notes tirées de l'historique. Déclare le projet comme projet de catalogue. Un commit `feat!:` (ou `BREAKING CHANGE:`) doit produire **v2.0.0**.
6. Migre `formation/ci-labo` : son `.gitlab-ci.yml` n'inclut plus que des composants (`include: component: …@v2.0.0`). Essaie aussi `@2.0.0`, `@2` et `@~latest` : lesquels fonctionnent, et pourquoi ? Note-le dans le journal.
7. Essai de garde-fou : dans une branche de `ci-labo`, passe une entrée de nom d'image invalide, puis une entrée inconnue. Note les messages (où apparaissent-ils ?).

**Critères de réussite**
- [ ] `plateforme/ci-templates` contient sur `main` `templates/{qualite,construction-image,securite,deploiement,release}/template.yml`, chacun avec un en-tête `spec:inputs`, et un `README.md` racine.
- [ ] La release `v2.0.0` existe et le projet est publié au catalogue (version visible par l'API GraphQL ou l'interface *Explore > CI/CD Catalog*).
- [ ] Le dernier pipeline de `main` de `formation/ci-labo` a réussi et son `.gitlab-ci.yml` n'a plus aucun `include: project`, `local` ou `template` : uniquement des `component:` de `plateforme/ci-templates` à une version `v2.x.y` épinglée.
- [ ] Le journal répond aux questions des étapes 1, 6 et 7.

**Vérification** : `lab/bin/check 19 10`

<details><summary>Indice 1</summary>

Les entrées sont remplacées **avant** que GitLab ne lise le YAML comme une configuration de pipeline : `$[[ inputs.stage ]]` peut donc se trouver là où une variable `$STAGE` est interdite (`stage:`, `tags:`, `needs:`, nom de job, `rules:`). Une entrée de type `array` remplace une valeur entière (`needs: $[[ inputs.besoins ]]`), pas un morceau de chaîne.
</details>

<details><summary>Indice 2</summary>

Une référence de composant se résout dans l'ordre : version du catalogue (nom **exact** de l'étiquette publiée), étiquette de release, puis référence Git. Les versions partielles (`2`, `2.0`) et `~latest` ne passent **que** par le catalogue. Relis la forme exacte de tes étiquettes.
</details>

<details><summary>Indice 3</summary>

semantic-release pose l'étiquette lui-même (son cœur pousse par Git avec `GITLAB_TOKEN`) ; c'est le greffon `@semantic-release/gitlab` qui crée la release par l'API. Sans lui, le pipeline d'**étiquette** peut créer la release par `release:`. Pense au `workflow` du projet : le gabarit `qualite.yml` de M01 ne lance pas de pipeline sur les étiquettes.
</details>

**Pour aller plus loin** (facultatif) : `spec:component` (`$[[ component.version ]]`) pour que le composant affiche sa propre version dans ses journaux ; `spec:inputs:rules` pour des valeurs par défaut qui dépendent d'une autre entrée ; l'onglet *Analytics* du catalogue (19.x).

---

### M19-E11 — Le pipeline standard de MédiAgenda  `LIBRE` `★★★`

> **Ticket DEV-2011** — *De : Julien Petit*
> Notre `.gitlab-ci.yml` fait 90 lignes, mélange trois gabarits v1 et tourne sur `runner02`, qui sature tous les matins. On veut le pipeline standard : ce que tous les projets Python de MédiSphère feront, en une vingtaine de lignes, sur les runners du cluster. Mêmes garanties qu'aujourd'hui, plus rapide si possible. Et je veux pouvoir le montrer à l'équipe de MédiDoc.

**Objectifs**
- Concevoir un pipeline complet par assemblage de composants, sans rien réécrire de ce qu'ils fournissent.
- Fixer et écrire les **normes** d'un pipeline MédiSphère.

**Prérequis** : M19-E10 ; M13-E09 (chaîne de livraison), M13-E14 (politiques de Harbor).
**Durée indicative** : 3 h.

**Contexte**
- Le pipeline doit couvrir : messages de commit, lint ruff (vérification et format), tests pytest avec rapport JUnit, construction de l'image par buildkitd, analyse Trivy bloquante avant publication, SBOM, publication `vX.Y.Z` sur étiquette (et `main-<sha>` sur `main`), signature Cosign et vérification, release par semantic-release sur `main`.
- La signature reste, pour l'instant, sur le chemin du M13 (clé en variable protégée du groupe, jobs sur l'étiquette `k8s`) ; elle passera sur le runner protégé en E24. La promotion vers les environnements arrive en E17.

**Contraintes**
- `.gitlab-ci.yml` de `mediagenda/api` : uniquement des `include: component:` de `plateforme/ci-templates` à une version **épinglée** ; au plus 40 lignes hors commentaires ; aucun job écrit à la main sauf s'il est propre au projet et justifié en commentaire.
- Aucun job sur `runner02`, aucune image `latest`, aucun conteneur privilégié, aucune image hors de Harbor.
- Pas de pipeline en double (branche + MR) ; les pipelines de MR ne publient ni ne signent rien et ne reçoivent aucune variable protégée.
- Un pipeline de MR complet en moins de 10 minutes (mesure-le ; E23 le fera maigrir).
- Les normes sont écrites dans `docs/livraison/ci/normes-pipeline.md` de `plateforme/medisphere` : ce qui est obligatoire, ce qui est recommandé, comment demander une exception.

**Critères de réussite**
- [ ] Le dernier pipeline de `main` et le pipeline de la dernière étiquette `vX.Y.Z` de `mediagenda/api` ont réussi, sur le runner `k8s-par1` uniquement.
- [ ] Le `.gitlab-ci.yml` de `mediagenda/api` n'inclut que des composants de `plateforme/ci-templates` à une version `v2.x.y`.
- [ ] L'image `medisphere/mediagenda-api:vX.Y.Z` de la dernière étiquette est signée (signature visible dans Harbor).
- [ ] `docs/livraison/ci/normes-pipeline.md` existe sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 19 11`

<details><summary>Indice 1</summary>

Le `workflow:` appartient au projet, pas au composant : c'est lui qui dit quels pipelines existent (MR, `main`, étiquettes). Les stages aussi : liste ceux que les composants utilisent.
</details>

<details><summary>Indice 2</summary>

Pour savoir si une variable protégée a fuité vers un pipeline de MR, le journal du job ne suffit pas : lis la page *Variables* du job (droits Maintainer) ou fais afficher `test -n "${COSIGN_PASSWORD:-}"` par un job d'essai, jamais la valeur.
</details>

**Pour aller plus loin** (facultatif) : un composant « tout-en-un » `pipeline-python` qui inclut lui-même les autres (`include:` dans un composant, avec `$CI_SERVER_FQDN`) : combien de lignes reste-t-il chez Julien, et que perd-on en lisibilité ?

---

### M19-E12 — Pipelines enfants, multi-projets et déclencheurs  `LAB` `★★`

> **Ticket DEV-2012** — *De : Julien Petit*
> Quand on publie une nouvelle version du chart, personne ne vérifie qu'elle passe avec les overlays de `deploiement` avant que quelqu'un ouvre la MR de montée de version, et c'est souvent en recette qu'on découvre que la prod ne rendait plus. Je voudrais que l'étiquette du chart déclenche tout de suite la validation des trois overlays dans `deploiement`, et que le pipeline du chart soit rouge si ça ne passe pas.

**Objectifs pédagogiques**
- Déclencher un pipeline **enfant** (même projet) depuis un fichier et depuis une configuration **générée** par un job.
- Déclencher un pipeline **multi-projets** (`trigger: project`) et en refléter le statut (`strategy`).
- Transmettre des données en aval (variables, `dotenv`) et comprendre ce que voit le pipeline aval.
- Contrôler qui peut utiliser le `CI_JOB_TOKEN` d'un projet pour en lire un autre (liste d'autorisation entrante).

**Prérequis** : M19-E10 ; M17-E09/E13 (`mediagenda/deploiement`, pipeline du chart).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Le pipeline d'étiquette de `mediagenda/chart` (M17-E13) publie le chart et produit `CHART_VERSION` et `CHART_DIGEST` (rapport `dotenv` du job `pousser`).
- `mediagenda/deploiement` régénère sa base avec `outils/rendre-base.sh` (lit `chart.env`, vérifie la signature, rend le chart) ; ses overlays sont `dev`, `recette`, `prod`. Le robot de lecture des charts est dans `HARBOR_CHARTS_RO_*` (groupe `mediagenda`, non protégées).
- Les notes de version du chart sont dans la release GitLab `vX.Y.Z` de `mediagenda/chart` (semantic-release).

**Travail demandé**
1. Dans `formation/ci-labo`, échauffement : un pipeline enfant depuis un fichier (`trigger: include: local:`), puis un pipeline enfant **généré** : un job `generer` écrit un YAML avec un job par fichier de `tests/`, un job `enfant` le déclenche (`trigger: include: artifact:`). Observe dans l'interface et par l'API (`/pipelines/:id/bridges`) le lien parent-enfant. Que se passe-t-il si le fichier généré est invalide ?
2. Dans `mediagenda/deploiement`, prépare l'aval : quand le pipeline vient d'un autre projet (`CI_PIPELINE_SOURCE == "pipeline"`) et porte `CHART_VERSION`/`CHART_DIGEST`, un job réécrit `chart.env`, régénère la base, puis **génère** un pipeline enfant avec un job de validation par overlay (`kustomize build` + `kubeconform`), et un job récupère les notes de la release du chart par l'API avec le `CI_JOB_TOKEN`.
3. Dans `mediagenda/chart`, ajoute au pipeline d'étiquette un job `valider-deploiement` qui déclenche `mediagenda/deploiement` sur `main` en lui transmettant la version et le digest, et dont le statut reflète celui de l'aval.
4. Pose une étiquette sur le chart (ou relance le pipeline de la dernière). Le job des notes doit échouer : lis l'erreur, puis ajoute `mediagenda/deploiement` à la liste d'autorisation entrante du `CI_JOB_TOKEN` de `mediagenda/chart` (par l'API). Relance.
5. Casse volontairement l'aval (une valeur refusée par le schéma du chart dans l'overlay `prod`, sur une branche, puis `main` de `deploiement` le temps de l'essai) et vérifie que le pipeline du chart est rouge. Remets en état.
6. Note dans `~/m19/e12/journal.md` : qui est l'**auteur** du pipeline aval ? Quelles variables du projet amont y sont visibles ? Pourquoi `strategy: depend` n'est plus recommandé ?

**Critères de réussite**
- [ ] Le dernier pipeline d'étiquette de `mediagenda/chart` contient un job déclencheur dont le pipeline aval est dans `mediagenda/deploiement`, et les deux ont réussi.
- [ ] Ce pipeline aval contient lui-même un pipeline enfant (configuration générée) qui a réussi.
- [ ] La liste d'autorisation entrante du `CI_JOB_TOKEN` de `mediagenda/chart` est active et contient `mediagenda/deploiement` (et pas « tous les projets »).

**Vérification** : `lab/bin/check 19 12`

<details><summary>Indice 1</summary>

Un job `trigger:` ne lance aucun conteneur : il ne peut ni avoir de `script` ni utiliser un runner. Les variables d'un rapport `dotenv` d'un job dont il a besoin (`needs:`) lui sont transmises si tu les nommes dans ses `variables:`.
</details>

<details><summary>Indice 2</summary>

Un pipeline aval est créé **au nom de l'utilisateur** qui a déclenché le pipeline amont : il faut qu'il ait le droit de lancer un pipeline sur `main` de `deploiement`. Le `CI_JOB_TOKEN`, lui, est contrôlé par le projet **cible** de l'appel (celui qu'on lit), pas par celui qui l'émet.
</details>

**Pour aller plus loin** (facultatif) : passer la version en **entrée** du pipeline aval (`trigger: inputs:`, `spec:inputs` en tête du `.gitlab-ci.yml` de `deploiement`) plutôt qu'en variable : avantages, et pourquoi c'est plus délicat avec une valeur venue d'un `dotenv`.

---

### M19-E13 — Pipelines de MR : rapports de tests et couverture  `LAB` `★★`

> **Ticket DEV-2013** — *De : Julien Petit*
> Dans nos MR, on ne voit rien : il faut ouvrir le journal du job pour savoir quel test a cassé, et personne ne sait si la couverture baisse. Je veux les tests et la couverture **dans la MR**, et qu'on ne puisse plus fusionner une MR rouge, même en étant Maintainer pressé.

**Objectifs pédagogiques**
- Produire et publier les rapports `junit` et `coverage_report` (Cobertura), et le pourcentage de couverture par `coverage`.
- Lire ce que GitLab en fait (onglet *Tests* du pipeline, widget de MR, couverture ligne à ligne dans le diff).
- Imposer « Pipelines must succeed » et en connaître les contournements.

**Prérequis** : M19-E11.
**Durée indicative** : 1 h 30.

**Contexte technique**
- `pytest-cov` n'est pas dans les dépendances de développement de MédiAgenda : ajoute-le par `uv add --dev` (borne `>=7.1,<8`), le verrou `uv.lock` est commité.
- Le rapport de couverture doit être au format Cobertura (`coverage.xml`), les chemins relatifs à la racine du projet.
- La couverture actuelle de MédiAgenda est d'environ 75 % (tests sans base de données).

**Travail demandé**
1. Publie une version mineure du composant `qualite` : rapport JUnit déjà présent, plus une entrée `couverture` (booléenne, défaut `true`) qui ajoute la mesure, le rapport Cobertura et l'expression `coverage`, pour Python et pour Go.
2. Passe `mediagenda/api` sur cette version (MR). Dans la MR : vérifie l'onglet *Tests*, la couverture affichée, et, dans le diff, les lignes couvertes ou non.
3. Sur une branche, ajoute un test qui échoue : retrouve-le dans le widget de MR sans ouvrir le journal. Puis supprime un test : que montre GitLab pour la couverture ?
4. Active « Pipelines must succeed » sur `mediagenda/api` (par l'API), ainsi que « Skipped pipelines are considered successful » **désactivé**. Essaie de fusionner la MR rouge avec le compte de Julien (Maintainer). Note ce qui se passe et ce que peut encore faire un administrateur.
5. Fais la même chose sur `mediagenda/deploiement` et `plateforme/ci-templates`.

**Critères de réussite**
- [ ] La dernière MR de `mediagenda/api` a un pipeline avec un rapport de tests non vide et une couverture renseignée.
- [ ] `mediagenda/api`, `mediagenda/deploiement` et `plateforme/ci-templates` imposent « Pipelines must succeed ».
- [ ] `pytest-cov` est dans `pyproject.toml` et `uv.lock` sur `main` de `mediagenda/api`.

**Vérification** : `lab/bin/check 19 13`

<details><summary>Indice 1</summary>

`coverage:` prend une expression rationnelle lue dans le **journal** du job (dernière ligne qui correspond) ; `artifacts:reports:coverage_report` prend un **fichier** et sert à la vue ligne à ligne. Ce sont deux choses différentes, il faut les deux.
</details>

<details><summary>Indice 2</summary>

Le réglage se lit et s'écrit dans l'API des projets : cherche le champ dont le nom contient `pipeline_succeeds`.
</details>

**Pour aller plus loin** (facultatif) : un seuil de couverture bloquant (`--cov-fail-under`) : pourquoi Julien n'en veut pas encore, et quelle alternative (la couverture ne doit pas **baisser**) ?

---

### M19-E14 — Services de job : une base PostgreSQL pour les tests d'intégration  `LAB` `★★`

> **Ticket DEV-2014** — *De : Julien Petit*
> Nos tests marqués `integration` ne tournent jamais : ils veulent un vrai PostgreSQL et un vrai Valkey. Résultat, la migration V3 du mois dernier a cassé en recette. Je veux qu'ils tournent dans chaque MR, avec PostgreSQL 18 comme en production, sans base partagée qu'un autre pipeline viendrait vider.

**Objectifs pédagogiques**
- Utiliser des **services** de job avec l'exécuteur Kubernetes : conteneurs du même pod, accès par `localhost` ou par alias, variables, utilisateur.
- Rendre ces services compatibles avec un espace qui va passer en Pod Security `restricted` (E24).
- Dimensionner un pod de job à plusieurs conteneurs (demandes, limites, surcharges `KUBERNETES_SERVICE_*`).

**Prérequis** : M19-E13, M19-E05 (anatomie d'un pod de job) ; MédiAgenda `README.md` (tests d'intégration, migrations).
**Durée indicative** : 2 h.

**Contexte technique**
- Images : `registry.par1.medisphere.internal/dockerhub/library/postgres:18.6-trixie` et `registry.par1.medisphere.internal/dockerhub/valkey/valkey:8.1.10-trixie`, épinglées par empreinte.
- Les tests d'intégration lisent `MEDIAGENDA_TEST_DB_URL` et `MEDIAGENDA_TEST_VALKEY_URL`, et **vident** la base désignée (`DROP SCHEMA public CASCADE`) : base dédiée, jamais celle d'un environnement. La base doit être en UTF-8.
- Les migrations s'appliquent par `mediagenda-migrate` (point d'entrée du paquet, M12).
- Les deux images officielles tournent sous l'utilisateur `999` une fois leur script d'entrée passé ; elles savent démarrer directement sous cet utilisateur si leurs répertoires de données lui appartiennent.

**Travail demandé**
1. Lis la section *services* de la documentation de l'exécuteur Kubernetes et la référence `services:` du `.gitlab-ci.yml`. Dans `~/m19/e14/journal.md` : où tournent les services, comment le job les joint, pourquoi deux services ne peuvent pas écouter le même port, ce qui se passe à la fin du job.
2. Publie une version mineure du composant `qualite` : une entrée `integration` (booléenne, défaut `false`) qui ajoute un job **`qualite:tests-integration`** avec les services PostgreSQL et Valkey, une base dédiée, l'application des migrations, `pytest -m integration` et un rapport JUnit séparé. Les services tournent sous l'utilisateur `999`, sans capacité, et ont des demandes et limites explicites.
3. Active-la dans `mediagenda/api`. Observe le pod du job (`kubectl get pod -n ci-jobs -o yaml`) : conteneurs, utilisateurs, ressources, alias.
4. Casse volontairement : un service sans alias et deux services sur le même port ; un test qui démarre avant que PostgreSQL soit prêt. Note les symptômes et comment le job doit attendre.
5. Vérifie que la somme des demandes du pod reste dans les bornes du LimitRange et du quota de `ci-jobs` (E02).

**Critères de réussite**
- [ ] Le dernier pipeline de MR (ou de `main`) de `mediagenda/api` contient un job `qualite:tests-integration` réussi avec un rapport de tests non vide.
- [ ] Le job n'utilise que des images de Harbor épinglées par empreinte.
- [ ] Le journal répond aux questions des étapes 1 et 4.

**Vérification** : `lab/bin/check 19 14`

<details><summary>Indice 1</summary>

Avec l'exécuteur Kubernetes, un service est un conteneur de plus dans le pod du job : il partage l'interface réseau, donc `127.0.0.1`. Depuis le Runner 17.9, son alias est aussi résolu par nom. Mais « conteneur démarré » ne veut pas dire « base prête ».
</details>

<details><summary>Indice 2</summary>

`services:` accepte `kubernetes: user: "UID:GID"` (GitLab 18.0 et plus). Le script d'entrée de l'image PostgreSQL ne fait d'opérations de propriétaire que s'il démarre en `root`.
</details>

**Pour aller plus loin** (facultatif) : la même base sous forme de **Testcontainers** : pourquoi c'est impossible sans démon Docker ni privilège dans `ci-jobs`, et ce que ce choix interdit aux équipes.

---

### M19-E15 — Semgrep CE et Gitleaks dans le composant `securite`  `LAB` `★★`

> **Ticket SEC-2015** — *De : Sophie Laurent*
> Gitleaks tourne encore sur `runner01` dans le gabarit v1, et on n'a aucune analyse du **code** (SAST). L'audit HDS demande les deux, avec des résultats visibles et des règles qui bloquent pour de vrai. Je ne veux pas de faux positifs qu'on finit par ignorer en bloc : chaque exception doit être justifiée et retrouvable.

**Objectifs pédagogiques**
- Intégrer Semgrep CE (règles du registre, sortie au format rapport SAST de GitLab) et Gitleaks dans un composant.
- Fixer des seuils bloquants raisonnables et tracer les exceptions (`nosemgrep` justifié, `.gitleaksignore`).
- Comprendre les limites de l'édition gratuite : rapport SAST téléchargeable, pas de widget de sécurité dans la MR (Ultimate).

**Prérequis** : M19-E13 ; M01-E19/E24 (Gitleaks).
**Durée indicative** : 2 h.

**Contexte technique**
- Image Semgrep : `registry.par1.medisphere.internal/dockerhub/semgrep/semgrep:1.182.0-nonroot` (empreinte à relever). Les règles du registre Semgrep (`p/python`, `p/secrets`…) sont sous « Semgrep Rules License v1.0 » : usage interne autorisé. Le job télécharge les règles depuis `semgrep.dev` (sortie Internet en 443) ; `--metrics=off` obligatoire.
- Image Gitleaks : `registry.par1.medisphere.internal/ghcr/gitleaks/gitleaks:v8.30.1` (empreinte à relever).
- Le rapport SAST de GitLab est un fichier JSON `gl-sast-report.json` déclaré en `artifacts:reports:sast`.

**Travail demandé**
1. Publie une version mineure du composant `securite` avec deux jobs `securite:semgrep` et `securite:gitleaks` (stage d'analyse, sans besoin de l'image) :
   - `securite:semgrep` : configurations de règles en entrée (`array`, défaut `["p/python", "p/secrets"]`), sévérité bloquante en entrée (`options`: `ERROR`, `WARNING`), rapport SAST, échec si un résultat atteint la sévérité ;
   - `securite:gitleaks` : historique de la plage de commits (repris du gabarit v1), `--redact`, rapport JUnit, toujours bloquant.
2. Passe `mediagenda/api` sur cette version. Dans une branche, introduis un appel `subprocess` avec `shell=True` : le job doit échouer et le résultat apparaître dans le rapport. Puis justifie une exception sur une ligne (commentaire `nosemgrep: <id-de-règle>` + raison + ticket) et constate qu'elle est retrouvable par `git grep`.
3. Introduis un faux secret (une clé AWS d'exemple) dans un commit **puis** supprime-la dans un second commit de la même branche : Gitleaks doit quand même échouer. Explique pourquoi dans le journal, et ce qu'il faut faire d'un vrai secret poussé (rotation **avant** nettoyage de l'historique).
4. Retire Gitleaks du gabarit v1 pour les projets migrés : `mediagenda/api` ne doit plus inclure `qualite.yml` v1.
5. Écris dans `docs/livraison/ci/normes-pipeline.md` la politique d'exception (qui valide, où c'est tracé, quand c'est revu).

**Critères de réussite**
- [ ] Le dernier pipeline de `main` de `mediagenda/api` contient les jobs `securite:semgrep` et `securite:gitleaks` réussis, et un rapport SAST.
- [ ] Les images de ces jobs sont épinglées par empreinte, aux versions demandées.
- [ ] Les normes contiennent la politique d'exception.

**Vérification** : `lab/bin/check 19 15`

<details><summary>Indice 1</summary>

`semgrep scan` sait écrire le rapport au format GitLab pendant qu'il affiche ses résultats (cherche l'option qui contient `gitlab-sast` dans `semgrep scan --help`). `--error` rend le code de retour non nul en cas de résultat ; `--severity` filtre ce qui est rapporté.
</details>

<details><summary>Indice 2</summary>

Gitleaks en mode `git` lit des **commits**, pas l'état final des fichiers. Le clone par défaut du runner est superficiel (`GIT_DEPTH`) : il faut assez d'historique pour la plage.
</details>

**Pour aller plus loin** (facultatif) : Opengrep (fork LGPL de Semgrep) avec les mêmes règles écrites par l'équipe : que faudrait-il changer, et que perdrait-on ?

---

### M19-E16 — SonarQube Community Build : installer et analyser  `LAB` `★★★`

> **Ticket PLAT-2016** — *De : Karim Benali*
> Tout le monde a un SonarQube. Avant de dire non, je veux l'avoir essayé chez nous : installé proprement dans le cluster, branché sur MédiAgenda, avec une porte qualité. Et une liste honnête de ce que l'édition gratuite ne fait pas. On le démontera peut-être en fin de module, donc rien de bricolé.

**Objectifs pédagogiques**
- Installer une application à état (Elasticsearch embarqué, base externe) par Helmfile, avec une base CloudNativePG et une publication par la Gateway.
- Sécuriser l'installation (mot de passe administrateur, jetons, pas d'analyse anonyme).
- Lancer une analyse depuis la CI et lire une porte qualité.
- Mesurer les limites de l'édition communautaire.

**Prérequis** : M19-E11, E13 (rapport de couverture) ; M16-E19 (CloudNativePG), M15-E12 (HTTPRoute), M17-E10 (Helmfile).
**Durée indicative** : 4 h.

> ⚠️ **Attention** : SonarQube demande ≈ 3 Gio (requête 2 Gio, limite 4 Gio dans ce lab). Vérifie avant l'installation que chaque travailleur a au moins 3 Gio libres (`kubectl top nodes`, `kubectl describe node`), et que Jenkins (E19) **ne tourne pas**. Le chart pose un conteneur d'initialisation **privilégié** (`initSysctl`) qui écrit des paramètres du noyau : il doit rester désactivé, `vm.max_map_count` étant déjà réglé par le rôle `k8s_travailleur` (E02). Retour arrière : `helmfile -e par1 -l composant=sonarqube destroy`, puis suppression du `Cluster` CNPG et de l'espace (les volumes `ceph-rbd` sont supprimés avec les PVC).

**Contexte technique**
- Version : SonarQube Community Build **26.10** (`26.10.0.133078-community`) ; chart `sonarqube/sonarqube` **2026.5.1002**, qui déploie encore la 26.9 par défaut : l'image est forcée. Image par le cache Harbor `dockerhub`.
- Espace `sonarqube` (PSA `restricted` appliqué : à toi de rendre le chart conforme), base CNPG **`sonarqube-db`** (une instance, PostgreSQL 18, `ceph-rbd`), Secret de connexion créé par l'opérateur (`sonarqube-db-app`).
- Publication : `https://sonarqube.apps.par1.medisphere.internal` (HTTPRoute sur `gw-par1`).
- Fichiers : `releases/80-sonarqube.yaml.gotmpl`, `composants/sonarqube/` (values, `Cluster`, politiques réseau), `espaces/sonarqube/` ; secrets (mot de passe administrateur, code de supervision du chart) dans `secrets/sonarqube.yml` (Vault `critique`) → `outils/secrets-k8s.sh`.
- Analyse : image `registry.par1.medisphere.internal/dockerhub/sonarsource/sonar-scanner-cli:12.2.0.4256_8.1.0`, variables `SONAR_HOST_URL` et `SONAR_TOKEN` (jeton d'analyse **de projet**, masqué et protégé) dans `mediagenda/api`.
- Vérifications : un compte `wb-checks` dans SonarQube (droit *Browse* sur le projet) et son jeton dans `~/.config/workbook/sonar-checks.token` (600).

**Travail demandé**
1. Lis les notes du chart 2026.5 (README, `values.yaml`) : comment choisir l'édition communautaire, forcer l'image, brancher une base externe, désactiver `initSysctl`/`initFs`, publier par `httproute`, fournir `monitoringPasscode`. Liste dans `~/m19/e16/journal.md` les valeurs que tu changes et pourquoi.
2. Crée l'espace, la base CNPG et les Secrets (MR sur `plateforme/k8s`), puis la release `sonarqube` (labels `groupe: ci-essais`, `composant: sonarqube`). Applique, suis le démarrage (`kubectl logs -f`), vérifie `api/system/status`.
3. Change le mot de passe `admin` dès la première connexion (par l'API, avec le mot de passe du Vault), crée l'utilisateur `wb-checks`, puis le projet `mediagenda-api` et un **jeton d'analyse de projet**. Vérifie qu'une analyse sans jeton est refusée.
4. Ajoute à `mediagenda/api` un job `sonarqube` (propre au projet, justifié dans les normes) qui, sur `main` seulement, envoie l'analyse avec le rapport de couverture de E13 (`coverage.xml`) et attend le résultat de la porte qualité. Lance-le, lis la porte.
5. Essaie une analyse dans un pipeline de MR. Note ce que l'édition communautaire fait (et ne fait pas) d'une branche ou d'une MR. Relève la mémoire réellement consommée (`kubectl top pod -n sonarqube`).
6. Écris dans le journal la liste « ce que SonarQube CE apporte / ce qu'il ne fait pas / ce qu'on a déjà ailleurs » (elle servira à l'ADR-0190 en E30).

**Critères de réussite**
- [ ] SonarQube répond `UP` sur `https://sonarqube.apps.par1.medisphere.internal/api/system/status` et tourne en 26.10.
- [ ] Le projet `mediagenda-api` a au moins une analyse avec un statut de porte qualité, envoyée par un job `sonarqube` du pipeline de `main`.
- [ ] Aucun conteneur privilégié dans l'espace `sonarqube` ; `SONAR_TOKEN` est masquée et protégée.

**Vérification** : `lab/bin/check 19 16`

<details><summary>Indice 1</summary>

Le chart 2026.x distingue l'édition par `community.enabled` ; l'étiquette d'image de la communautaire se construit à partir de `community.buildNumber`. Pour la base, cherche `jdbcOverwrite` : l'URL JDBC, l'utilisateur, et un Secret existant pour le mot de passe.
</details>

<details><summary>Indice 2</summary>

`sonar.qualitygate.wait=true` fait attendre le scanner jusqu'au calcul de la porte qualité ; son délai par défaut est court pour un premier calcul (cherche `sonar.qualitygate.timeout`). Pour la couverture d'un projet Python : `sonar.python.coverage.reportPaths`.
</details>

**Pour aller plus loin** (facultatif) : comparer, sur le même code, les problèmes trouvés par SonarQube, ruff et Semgrep : recoupement, différences, bruit.

---

### M19-E17 — Promouvoir une image par merge request  `LAB` `★★★`

> **Ticket PLAT-2017** — *De : Claire Morel*
> Aujourd'hui, une nouvelle version de MédiAgenda arrive en dev parce que quelqu'un pense à modifier `livraison.yaml` et à lancer `kubectl apply`. Je veux que la CI fasse la proposition : une MR dans `deploiement`, avec l'image **exacte** qui a été analysée et signée, relue et fusionnée par Julien ou Karim. Personne d'autre ne fusionne, et le jeton de la CI ne doit rien pouvoir faire d'autre qu'ouvrir cette MR.

**Objectifs pédagogiques**
- Construire une promotion par MR (« GitOps léger ») : image désignée par **digest**, branche dédiée, MR ouverte par la CI.
- Créer un jeton de projet à portée minimale, avec expiration, et le ranger en variable protégée et masquée.
- Protéger la branche cible pour que seuls les Maintainers fusionnent (sans les règles d'approbation, Premium).

**Prérequis** : M19-E11, E12 ; M17-E09/E21 (component `livraison`, garde-fou `verifier-livraison`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Dans `mediagenda/deploiement`, la ConfigMap locale `livraison` de chaque overlay donne la version (component `livraison`, M17-E09) ; un `images:` dans un overlay l'emporte sur elle (M17-E21) : le garde-fou `outils/verifier-livraison.sh` l'interdit en prod. Ici, l'overlay `dev` recevra **les deux** : `livraison.yaml` à la version, et `images:` au digest de cette même version ; le garde-fou doit l'accepter pour `dev` **à condition** que l'étiquette de `images:` soit celle de `livraison.yaml` et que le digest soit présent.
- `kustomize edit set image <nom>=<nom>:vX.Y.Z@sha256:…` écrit `newTag` **et** `digest` ; le rendu donne `…:vX.Y.Z@sha256:…`.
- Le digest vient du rapport `dotenv` `IMAGE_REF` du composant `construction-image` (E10).
- Jeton : jeton **de projet** de `mediagenda/deploiement` nommé `ci-promotion`, rôle Developer, portées `api` et `write_repository`, expiration à 90 jours ; il devient la variable `DEPLOIEMENT_TOKEN` de `mediagenda/api` (protégée, masquée). Branches de promotion : `promotion/dev-vX.Y.Z`, `promotion/recette-vX.Y.Z`, `promotion/prod-vX.Y.Z`.
- Image du job : `registry.par1.medisphere.internal/dockerhub/alpine/k8s:1.36.5` (git, kustomize, curl, jq), empreinte à relever.

**Travail demandé**
1. Protège `main` de `mediagenda/deploiement` : fusion « Maintainers », poussée « personne » ; vérifie que seuls Julien Petit et Karim Benali (et toi, administrateur) sont Maintainers du projet. Note pourquoi un Developer peut **ouvrir** une MR mais pas la fusionner.
2. Crée le jeton `ci-promotion` par l'API, range-le dans `DEPLOIEMENT_TOKEN` (protégée, masquée) et dans le registre des secrets (date d'expiration, propriétaire, procédure de rotation).
3. Écris le composant `promotion` (nouvelle version mineure de `plateforme/ci-templates`) :
   - entrées : projet de déploiement, overlay, nom de l'image, mode (`automatique` ou `manuel`) ;
   - un job `promouvoir-<overlay>` qui, sur une étiquette `vX.Y.Z`, clone le dépôt de déploiement avec le jeton, crée la branche, met à jour `livraison.yaml` et l'image par digest, lance le garde-fou, pousse et ouvre une MR (titre, description avec le lien du pipeline, l'étiquette, le digest, suppression de la branche à la fusion) ; refus propre si la branche existe déjà ;
   - le jeton n'apparaît jamais dans le journal ni dans `.git/config` d'un artefact.
4. Adapte `outils/verifier-livraison.sh` de `deploiement` (MR) à la règle de l'overlay `dev`.
5. Dans `mediagenda/api` : `promouvoir-dev` automatique sur étiquette, `promouvoir-recette` et `promouvoir-prod` manuels. Pose une étiquette (MR `fix:` fusionnée), suis la MR ouverte dans `deploiement`, fais-la fusionner par Julien (compte de Julien) et vérifie le rendu de l'overlay. L'application en dev reste manuelle jusqu'à E18.
6. Essai inverse : avec le jeton `ci-promotion`, tente de pousser sur `main` de `deploiement` et de fusionner la MR. Note les refus.

**Critères de réussite**
- [ ] `mediagenda/deploiement` a un jeton de projet actif `ci-promotion` avec une date d'expiration, sans portée au-delà de `api` et `write_repository`.
- [ ] `DEPLOIEMENT_TOKEN` existe dans `mediagenda/api`, protégée et masquée.
- [ ] La dernière MR `promotion/dev-v*` de `mediagenda/deploiement` modifie `overlays/dev` avec une image désignée par digest, et `main` n'accepte que les fusions des Maintainers.

**Vérification** : `lab/bin/check 19 17`

<details><summary>Indice 1</summary>

Git accepte des options de poussée qui ouvrent une MR (`-o merge_request.create`…), mais tu veux une description riche et une erreur claire si la MR existe déjà : l'API `POST /projects/:id/merge_requests` est plus explicite. Pour l'authentification Git sans laisser le jeton dans `.git/config`, regarde `git -c http.extraHeader=…` ou un assistant d'authentification lu depuis une variable.
</details>

<details><summary>Indice 2</summary>

Un jeton de projet est un **utilisateur robot** membre du projet avec le rôle choisi : les protections de branche s'appliquent à lui comme à un humain Developer.
</details>

**Pour aller plus loin** (facultatif) : la poussée Git par `CI_JOB_TOKEN` entre projets autorisés (GitLab 18.4 et plus) éviterait un jeton longue durée : qu'est-ce qui changerait, et que faudrait-il ouvrir sur `deploiement` ?

---

### M19-E18 — Déployer en dev avec l'agent GitLab pour Kubernetes  `LAB` `★★★`

> **Ticket PLAT-2018** — *De : Claire Morel*
> La MR de promotion est fusionnée… et quelqu'un doit encore lancer `kubectl apply` depuis `adm01`. Pour la dev seulement, je veux que la fusion déploie. Mais je ne veux pas d'un `kubeconfig` d'administrateur dans une variable de CI, ni que n'importe quel projet puisse toucher au cluster. Sophie veut voir exactement ce que la CI peut faire, espace par espace.

**Objectifs pédagogiques**
- Installer l'agent GitLab pour Kubernetes (KAS d'omnibus, enregistrement, release Helmfile) sans lui donner `cluster-admin`.
- Autoriser des projets (`ci_access`) et comprendre l'identité sous laquelle un job agit (le compte de l'agent ; l'usurpation d'identité est Premium).
- Déployer depuis un job de CI avec le contexte de l'agent, en *server-side apply*, et suivre le déploiement dans l'environnement GitLab `dev`.

**Prérequis** : M19-E17 ; M14-E11 (RBAC), M17-E25 (overlay `dev` appliqué par `kubectl apply --server-side -k`).
**Durée indicative** : 3 h 30.

> ⚠️ **Attention** : le chart de l'agent crée par défaut une liaison au rôle **`cluster-admin`** (`rbac.create: true`). Désactive-la **avant** la première installation et vérifie après chaque `helmfile apply` qu'aucun `ClusterRoleBinding` ne vise le compte de l'agent. Retour arrière : `helmfile -e par1 -l composant=gitlab-agent destroy`, puis révocation du jeton de l'agent par l'API.

**Contexte technique**
- KAS : activé par défaut dans omnibus ; en 19.4, les agents s'y connectent en WebSocket : `wss://git01.par1.medisphere.internal/-/kubernetes-agent/` (le `grpcs://` devient le défaut en 19.5, E26). Flux : `K8S_TRAV` → `git01` 443 (déjà ouvert pour les runners).
- Chart `gitlab/gitlab-agent` **2.32.0** (agentk 19.4.0) ; release `gitlab-agent` dans l'espace `gitlab-agent` (PSA `restricted`), ajoutée à `releases/50-ci.yaml.gotmpl` (labels `groupe: ci`, `composant: gitlab-agent`), values `composants/gitlab-agent/values.yaml`. Le Secret du jeton (`gitlab-agent-jeton`, clé `token`) vient de `secrets/gitlab-agent.yml` par `outils/secrets-k8s.sh`.
- L'agent fait confiance à `git01` par `config.kasCaCert` (racine MédiSphère).
- Configuration : `.gitlab/agents/k8s-par1/config.yaml` dans `plateforme/k8s`. Accès CI : groupe `mediagenda` (branches protégées, environnement `dev` seulement) et projet `formation/ci-labo`.
- Droits du compte de service de l'agent : `edit` dans `mediagenda-dev` et `wb-essais`, plus ce qu'il faut pour les ressources de l'overlay `dev` que `edit` ne couvre pas ; rien ailleurs. Fichiers dans `rbac/gitlab-agent/`.
- Le job s'appelle **`deployer-dev`** (composant `deploiement`, nouvelle version mineure), image `dockerhub/alpine/k8s:1.36.5` ; l'API de l'agent est jointe à travers `git01` : `SSL_CERT_FILE` doit pointer sur la racine.

**Travail demandé**
1. Lis *Using GitLab CI/CD with a Kubernetes cluster* (agent) et *GitLab Relay (KAS)* pour omnibus. Dans `~/m19/e18/journal.md` : qui ouvre la connexion (l'agent ou GitLab) ? Par où passe un `kubectl` lancé dans un job ? Sous quelle identité arrive-t-il à l'API Kubernetes ?
2. Vérifie que KAS tourne sur `git01` (`gitlab-ctl status`, `/-/kubernetes-agent/` dans la configuration NGINX). Crée l'agent `k8s-par1` et son jeton **par l'API** (projet `plateforme/k8s`), range le jeton en Vault.
3. Écris la configuration de l'agent, l'espace, le RBAC, les values et la release (MR). Installe. Vérifie : pods prêts, journaux d'`agentk` (connexion établie), agent « connecté » dans l'interface, **aucune** liaison à `cluster-admin`.
4. Vérifie les droits par usurpation (`kubectl auth can-i … --as=system:serviceaccount:gitlab-agent:<compte>`) : écriture dans `mediagenda-dev` et `wb-essais`, rien dans `mediagenda-recette`, `kube-system`, ni sur les nœuds ; ni Secrets en lecture ailleurs.
5. Dans `formation/ci-labo`, un job manuel qui liste les contextes (`kubectl config get-contexts`) et crée un ConfigMap dans `wb-essais`. Puis un job qui tente d'écrire dans `mediagenda-recette` : refus attendu.
6. Ajoute `deployer-dev` au composant `deploiement` : à la fusion sur `main` de `mediagenda/deploiement`, `kubectl diff` puis `kubectl apply --server-side -k overlays/dev` avec le contexte de l'agent, attente du déploiement (`rollout status`), environnement GitLab `dev` (`deployment_tier: development`, URL publiée), `resource_group`. Fusionne une MR de promotion et suis le déploiement jusqu'au bout.
7. Que se passe-t-il si un `kubectl apply` à la main a modifié l'objet entre-temps (gestionnaire de champs) ? Essaie avec une étiquette ajoutée par `kubectl label`, puis note dans le journal.

**Critères de réussite**
- [ ] L'agent `k8s-par1` est enregistré dans `plateforme/k8s`, son jeton actif a été utilisé récemment, et ses pods sont prêts dans `gitlab-agent`.
- [ ] Aucun `ClusterRoleBinding` ne vise un compte de service de l'espace `gitlab-agent` ; le compte de l'agent n'a de droits d'écriture que dans `mediagenda-dev` et `wb-essais`.
- [ ] Le dernier déploiement de l'environnement `dev` de `mediagenda/deploiement` a réussi, par le job `deployer-dev`.

**Vérification** : `lab/bin/check 19 18`

<details><summary>Indice 1</summary>

L'agent ouvre une connexion sortante longue vers KAS ; un job autorisé reçoit dans `$KUBECONFIG` un contexte par agent accessible, nommé `<projet de l'agent>:<nom de l'agent>`. Ses requêtes passent par `git01` puis par cette connexion, et l'agent les rejoue avec **son** compte de service.
</details>

<details><summary>Indice 2</summary>

Le rôle intégré `edit` ne couvre que les ressources dont les CRD l'ont demandé (agrégation `aggregate-to-edit`). Fais la liste des `kind` rendus par `kustomize build overlays/dev` et compare avec `kubectl auth can-i --list`.
</details>

<details><summary>Indice 3</summary>

`kubectl apply --server-side` utilise par défaut le gestionnaire de champs `kubectl` : c'est celui qui possède déjà les champs de l'overlay `dev` depuis M17-E25. Un autre nom de gestionnaire créerait des conflits sur tous les champs.
</details>

**Pour aller plus loin** (facultatif) : en Premium, `access_as: ci_job: {}` ferait arriver chaque job sous une identité propre (`gitlab:ci_job:<id>`, groupes par projet et par environnement) : réécris le RBAC qu'on aurait alors, sans l'appliquer.

---

### M19-E19 — Jenkins dans Kubernetes : JCasC et agents en pods  `LAB` `★★`

> **Ticket PLAT-2019** — *De : Karim Benali*
> L'équipe de l'éditeur qu'on vient de racheter ne jure que par Jenkins. Avant de leur expliquer pourquoi on est sur GitLab CI, je veux qu'on sache de quoi on parle : un Jenkins **actuel**, configuré entièrement par du code, qui fait tourner ses builds dans des pods jetables. Pas un Jenkins cliqué à la main qu'on ne saura jamais reconstruire.

**Objectifs pédagogiques**
- Installer Jenkins LTS par Helmfile avec une configuration entièrement déclarative (JCasC, plugins épinglés).
- Configurer le nuage Kubernetes (agents en pods éphémères) et en comprendre la connexion au contrôleur.
- Sécuriser l'installation : comptes locaux, pas de lecture anonyme, pas d'exécuteur sur le contrôleur, jeton d'API pour les vérifications.

**Prérequis** : M19-E16 (SonarQube **arrêté**) ; M17-E10 (Helmfile), M15-E12 (HTTPRoute).
**Durée indicative** : 3 h.

> ⚠️ **Attention** : avant toute chose, arrête SonarQube : `replicas: 0` dans ses values (MR), `helmfile -e par1 -l composant=sonarqube apply`, et vérifie que son pod a disparu. Le contrôleur Jenkins demande ≈ 1,5 Gio et chaque agent 512 Mio. Retour arrière : `helmfile -e par1 -l composant=jenkins destroy` (le PVC du contrôleur est gardé : supprime-le à la main seulement quand l'ADR aura tranché).

**Contexte technique**
- Jenkins LTS **2.580.1** (Java 21 : image `jenkins/jenkins:2.580.1-jdk21`) ; chart `jenkins/jenkins` **5.9.72** ; images tirées par le cache Harbor `dockerhub` (contrôleur, `kiwigrid/k8s-sidecar`, `jenkins/inbound-agent` en variante `-jdk21`).
- Plugins (épinglés, sans mise à jour automatique des dépendances) : `kubernetes:4560.vc25b_83890c34`, `workflow-aggregator:608.v67378e9d3db_1`, `git:5.11.0`, `configuration-as-code:2136.veb_3a_554550b_f`, `junit:1442.vb_b_a_467df2767`, `matrix-auth:3.3`, `timestamper:1.30`.
- Espace `jenkins` (PSA `restricted`) ; release `jenkins` (`releases/81-jenkins.yaml.gotmpl`, labels `groupe: ci-essais`, `composant: jenkins`) ; publication `https://jenkins.apps.par1.medisphere.internal` (HTTPRoute sur `gw-par1`, champ `controller.httpRoute` du chart).
- Comptes locaux par JCasC : `admin` (mot de passe du Vault, Secret `jenkins-admin`), `karim.benali`, `wb-checks` (lecture seule) ; le jeton d'API de `wb-checks` va dans `~/.config/workbook/jenkins-checks.env` (`JENKINS_USER`, `JENKINS_TOKEN`, 600).
- Message système fixé par JCasC : `Jenkins MédiSphère — configuré par JCasC (M19-E19)`.

**Travail demandé**
1. Lis le `values.yaml` du chart 5.9.72 (sections `controller.JCasC`, `controller.installPlugins`, `agent`, `controller.httpRoute`, `persistence`) et les notes de la LTS 2.555/2.580 (Java, `crumbIssuer`). Note dans `~/m19/e19/journal.md` les valeurs que tu changes et pourquoi.
2. Écris l'espace, les values et la release (MR). La configuration complète (sécurité, autorisations matricielles, nuage Kubernetes, gabarit d'agent compatible `restricted`, message système, un job de test `essai-agent` défini par JCasC ou par un *pipeline* en ligne) doit être dans les values : **aucun clic** dans l'interface.
3. Installe, suis le démarrage, connecte-toi. Vérifie : version, plugins installés (et pas plus), JCasC chargé (*Manage Jenkins > Configuration as Code*), aucun exécuteur sur le contrôleur.
4. Lance `essai-agent` : observe le pod d'agent (`kubectl get pods -n jenkins -w`), ses conteneurs, sa connexion (WebSocket ou port 50000 ?), sa disparition.
5. Crée le jeton d'API de `wb-checks` (connecté en `wb-checks`) et range-le. Vérifie qu'un accès anonyme à `/api/json` est refusé.
6. Modifie un réglage dans l'interface, puis redémarre le contrôleur : que devient-il ? Conclus sur la place de JCasC.

**Critères de réussite**
- [ ] Le contrôleur Jenkins est prêt dans l'espace `jenkins`, en 2.580.x, et répond derrière `jenkins.apps.par1.medisphere.internal`.
- [ ] La configuration vient de JCasC (message système attendu) ; l'accès anonyme est refusé.
- [ ] Le dernier build de `essai-agent` a réussi sur un agent en pod ; SonarQube n'a aucun pod en cours.

**Vérification** : `lab/bin/check 19 19`

<details><summary>Indice 1</summary>

Le chart génère une partie du JCasC (nuage Kubernetes, sécurité) à partir de ses values ; `controller.JCasC.configScripts` ajoute des morceaux. Une même clé définie deux fois fait échouer le chargement : lis le ConfigMap généré (`kubectl get cm -n jenkins -l jenkins-jenkins-config=true -o yaml`).
</details>

<details><summary>Indice 2</summary>

Pour le profil `restricted`, le chart sait poser un contexte de sécurité sur le conteneur `jnlp` des agents : cherche `restrictedPssSecurityContext`. Le contrôleur, lui, tourne déjà sous l'UID 1000 ; regarde ce qui manque (`seccompProfile`, capacités).
</details>

**Pour aller plus loin** (facultatif) : Jenkins sans persistance (`persistence.enabled: false`) : que perd-on exactement si tout est dans JCasC et les jobs dans des `Jenkinsfile` ?

---

### M19-E20 — Le même pipeline en Jenkinsfile  `LAB` `★★★`

> **Ticket PLAT-2020** — *De : Karim Benali*
> Maintenant, la vraie question : le pipeline de MédiAgenda, en Jenkins, ça donne quoi ? Lint, tests, image construite par notre buildkitd. Je veux des chiffres, pas des impressions : durée, lignes à maintenir, plugins, ce qu'il faut ouvrir côté sécurité. Et une conclusion qu'on puisse défendre devant l'équipe rachetée.

**Objectifs pédagogiques**
- Écrire un `Jenkinsfile` déclaratif avec des agents Kubernetes multi-conteneurs (`podTemplate` en YAML).
- Brancher Jenkins sur GitLab (lecture du dépôt) et sur buildkitd (TLS mutuel) sans élargir les droits.
- Comparer deux outils sur des critères mesurés.

**Prérequis** : M19-E19, E11.
**Durée indicative** : 3 h 30.

**Contexte technique**
- Branche **`essai-jenkins`** de `mediagenda/api` ; job Jenkins `mediagenda-api` (pipeline « depuis SCM », défini par JCasC).
- Lecture du dépôt : jeton de déploiement GitLab `jenkins-lecture` (`read_repository`) de `mediagenda/api`, rangé en Vault puis en *credential* Jenkins par JCasC (Secret Kubernetes lu par le chart, `controller.additionalExistingSecrets`).
- buildkitd : le pod d'agent doit présenter un certificat client signé par la ClusterIssuer `buildkit-ca` (E08) et porter l'étiquette `medisphere.internal/ci: job`. Le chart `buildkitd` sait émettre un certificat `buildkit-client` par espace client et ouvrir sa politique d'entrée à un espace : ajoute `jenkins` à ses listes d'espaces clients (`composants/buildkitd/values.yaml`) **pour la durée de l'essai** (exception écrite). La racine MédiSphère, pour que `git` fasse confiance à `git01`, va dans une ConfigMap `medisphere-racine` de l'espace `jenkins`, comme dans `ci-jobs` (E07).
- L'image construite n'est **pas** publiée (sortie `type=oci` en local) : Jenkins n'a pas de robot Harbor.
- Livrable : `docs/livraison/ci/comparatif-jenkins.md` de `plateforme/medisphere`.

**Travail demandé**
1. Écris le `Jenkinsfile` (branche `essai-jenkins`) : agent `kubernetes` avec un pod à trois conteneurs (uv, buildkit client, jnlp), étapes lint (ruff), tests (pytest, rapport JUnit publié), construction de l'image par buildkitd distant ; `options` : délai, horodatage, pas de builds concurrents.
2. Crée le jeton de déploiement, le *credential* et le job par JCasC (MR sur `plateforme/k8s`), le certificat client et l'exception réseau (chart `buildkitd`, politique de sortie des agents). Applique.
3. Lance le build ; corrige jusqu'au vert. Mesure la durée de trois builds et celle de trois pipelines GitLab équivalents (jobs `qualite:lint`, `qualite:tests`, `image:construction`), par les deux API.
4. Rédige le comparatif : durée (médiane), lignes à maintenir (`Jenkinsfile` + JCasC + values contre `.gitlab-ci.yml` + composants), plugins et leur cadence de mises à jour, surface d'attaque (comptes, jetons, ports, contrôleur à état), identité (qui a lancé quoi), coût mémoire, ce que GitLab CI ne fait pas aussi bien. Conclusion argumentée en dix lignes.
5. Retire `jenkins` des espaces clients de buildkitd quand le comparatif est relu (le certificat et l'ouverture réseau disparaissent avec) ; Jenkins lui-même reste jusqu'au mini-projet.

**Critères de réussite**
- [ ] Le dernier build du job `mediagenda-api` de Jenkins a réussi, sur la branche `essai-jenkins`, avec un rapport de tests.
- [ ] `docs/livraison/ci/comparatif-jenkins.md` existe sur `main` de `plateforme/medisphere` et contient des durées mesurées des deux côtés.

**Vérification** : `lab/bin/check 19 20`

<details><summary>Indice 1</summary>

Avec le plugin Kubernetes, `agent { kubernetes { yaml '''…''' } }` décrit tout le pod ; `container('uv') { sh '…' }` exécute une étape dans un conteneur donné. Le conteneur `jnlp` est ajouté par le plugin s'il n'est pas décrit : décris-le pour lui donner un contexte de sécurité.
</details>

<details><summary>Indice 2</summary>

`buildctl` lit l'adresse du démon et les fichiers TLS en options (`--addr`, `--tlscacert`, `--tlscert`, `--tlskey`, `--tlsservername`) ; un Secret de cert-manager contient `ca.crt`, `tls.crt` et `tls.key`.
</details>

**Pour aller plus loin** (facultatif) : la *Shared Library* Jenkins est l'équivalent des composants : écris-en une étape `pipelinePython()` et compare la gestion des versions avec le catalogue CI/CD.

---

### M19-E21 — Revue : le `.gitlab-ci.yml` du stagiaire  `REV` `★★`

> **Ticket DEV-2021** — *De : Karim Benali*
> Lucas a écrit le pipeline d'un futur service (on l'essaie dans `ci-labo`). « Ça marche », dit-il. Relis-le comme si c'était la prod : je veux la liste des défauts, classés, avec pour chacun le risque concret et la correction. Puis pousse la version corrigée.

**Objectifs pédagogiques**
- Relire un pipeline avec une grille : sécurité, fiabilité, performance, maintenabilité.
- Relier chaque défaut à un risque concret (fuite, contournement, coût, pipeline faux vert).

**Prérequis** : M19-E10, E11, E15 ; M19-E06 et E07 (`rules`, `workflow`, cache, artefacts).
**Durée indicative** : 2 h.

**Fichiers fournis** : [`ressources/E21-ci-lucas/.gitlab-ci.yml`](../ressources/E21-ci-lucas/.gitlab-ci.yml) et les notes de Lucas [`ressources/E21-ci-lucas/NOTES-LUCAS.md`](../ressources/E21-ci-lucas/NOTES-LUCAS.md).

**Travail demandé**
1. Relis les deux fichiers **sans les exécuter**. Pour chaque défaut : ligne, catégorie (sécurité, fiabilité, performance, maintenabilité), gravité (bloquant, majeur, mineur), risque concret, correction. Écris la revue dans `~/m19/e21/revue.md`, sous la forme d'un commentaire de MR.
2. Vérifie tes hypothèses quand c'est possible sans risque : lint du fichier par l'API (`POST /projects/:id/ci/lint` avec `dry_run`), lecture de la documentation.
3. Écris la version corrigée dans la branche **`revue-lucas`** de `formation/ci-labo` : composants v2 de `plateforme/ci-templates` partout où ils existent, le reste réécrit. Elle doit passer la validation de l'API et produire un pipeline vert.

**Critères de réussite**
- [ ] La revue liste au moins 12 défauts, chacun avec risque et correction.
- [ ] La branche `revue-lucas` de `formation/ci-labo` a un pipeline réussi, sans job privilégié, sans `latest`, sans `only`/`except`, et n'inclut que des composants.

**Vérification** : `lab/bin/check 19 21` (vérifie la version corrigée ; la revue s'auto-évalue avec le corrigé)

<details><summary>Indice 1</summary>

Lis chaque job en te demandant : sur quelles références tourne-t-il ? Que voit-il (variables, jetons) ? Qu'écrit-il, et qui le relira ? Combien de temps et de place prend-il ? Qu'est-ce qui le fait passer au vert alors qu'il aurait dû échouer ?
</details>

<details><summary>Indice 2</summary>

Il y a au moins un défaut dans chacune de ces familles : image, privilège, secret, règles de déclenchement, cache, artefacts, dépendances entre jobs, analyse de sécurité, téléchargement de code exécuté.
</details>

---

### M19-E22 — Runbook : un pipeline reste en attente  `RED` `★★`

> **Ticket INC-4622** — *De : Nadia Roussel*
> Trois fois ce mois-ci, l'astreinte a été appelée pour « le pipeline ne démarre pas ». Trois causes différentes, trois heures perdues. Je veux un runbook que la personne d'astreinte suit sans connaître GitLab par cœur : de « mon job est `pending` » à la cause, avec les commandes et ce qu'on a le droit de faire la nuit.

**Objectifs pédagogiques**
- Organiser un diagnostic en arbre de décision, du symptôme côté GitLab aux causes côté runner et Kubernetes.
- Distinguer « pas de runner éligible », « runner occupé », « pod non planifiable » et « pod qui ne démarre pas ».

**Prérequis** : M19-E04, E05, E07, E14 ; M14 (diagnostic d'un pod), M14-E10 (quotas).
**Durée indicative** : 2 h.

**Travail demandé**
Rédige `docs/livraison/ci/RB-190-pipeline-en-attente.md` dans `plateforme/medisphere` (MR relue par Nadia). Il doit contenir :
1. Le périmètre et les symptômes (job `pending`, `created`, « *This job is stuck because…* », pipeline qui ne se crée pas du tout, job qui attend un `resource_group`).
2. Un arbre de décision : pipeline créé ou non ; job en `created` ou `pending` ; runner éligible (étiquettes, `run_untagged`, `ref_protected`, pause, verrouillage au projet, runner hors ligne) ; capacité du gestionnaire (`concurrent`, `limit`, `request_concurrency`) ; pod de job (événements, quota et LimitRange de `ci-jobs`, `Pending` par manque de ressources, taints, image introuvable, Secret absent) ; dépendances externes (Harbor, buildkitd, `s3-01`).
3. Pour chaque branche : la commande exacte (API GitLab, `kubectl`, journaux du gestionnaire), ce qu'on lit, la cause, l'action **autorisée en astreinte** et ce qui attend le jour ouvré.
4. La communication (qui prévenir, message type) et les critères de sortie.
5. Une section « pièges » et les liens vers la documentation.

**Critères de réussite** (auto-évaluation avec le corrigé)
- L'arbre couvre au moins huit causes distinctes, chacune avec une commande de constat.
- Chaque action d'astreinte est réversible et sans perte de données.
- Une personne qui ne connaît pas le module peut suivre le runbook (fais-le relire).

<details><summary>Indice</summary>

Commence par la page du job dans GitLab : son message dit souvent quelle étiquette manque. Puis l'API des runners (`/runners/:id`, `/runners/:id/managers`) et les journaux du gestionnaire (`kubectl logs -n gitlab-runner deploy/gitlab-runner`) ; enfin `kubectl get events -n ci-jobs --sort-by=.lastTimestamp`.
</details>

---

### M19-E23 — Accélérer un pipeline lent  `LAB` `★★★`

> **Ticket DEV-2023** — *De : Julien Petit*
> Le pipeline de MR de MédiAgenda est passé à 9 minutes avec les tests d'intégration, Semgrep et la construction. Mes développeurs attendent, poussent trois fois, et ça bouchonne. Objectif : **−40 %** sur le pipeline de MR, sans retirer une seule vérification. Et mesuré, pas ressenti.

**Objectifs pédagogiques**
- Mesurer un pipeline par l'API : durée de chaque job, temps d'attente, chemin critique.
- Appliquer les leviers d'accélération et en mesurer chacun l'effet : `needs`, clés de cache par fichier de verrou, profondeur et stratégie Git, taille des artefacts, cache BuildKit, compression du cache (`FF_USE_FASTZIP`), `interruptible`.

**Prérequis** : M19-E11, E13, E14, E15 ; M19-E07 (cache S3), E08 (cache BuildKit).
**Durée indicative** : 3 h.

**Contexte technique**
- API : `GET /projects/:id/pipelines?source=merge_request_event` ; `GET /projects/:id/pipelines/:id` (`duration`, `queued_duration`, `created_at`, `finished_at`) ; `GET /projects/:id/pipelines/:id/jobs` (`duration`, `queued_duration`, `started_at`, `finished_at`, `stage`, `artifacts`).
- Le cache S3 (`ci-cache`, E07) et le cache BuildKit (`plateforme/cache-buildkit`, E08) existent déjà ; reste à s'en servir **bien**.
- Livrable : `docs/livraison/ci/mesures-pipeline.md` de `plateforme/medisphere`, avec une ligne exacte `Seuil : <N> s` (durée médiane visée des pipelines de MR, en secondes).

**Travail demandé**
1. Écris `~/m19/e23/mesurer.sh` (ou un script Python) qui, pour les N derniers pipelines de MR d'un projet, affiche la durée totale, le temps d'attente, et pour chaque job sa durée et son attente, puis la médiane. Mesure **5** pipelines de MR de `mediagenda/api` sans rien changer (pousse des commits vides sur une branche avec MR) : c'est la référence. Repère le chemin critique.
2. Calcule le seuil (référence × 0,6) et écris-le dans le livrable.
3. Applique les leviers **un par un**, en mesurant après chacun (trois pipelines suffisent) ; la plupart se font dans les composants (nouvelle version mineure) : `needs` pour casser l'attente par stage, cache `uv` par clé `files: [uv.lock]` et politique `pull` hors de `main`, `GIT_DEPTH` adapté à chaque job (Gitleaks a besoin d'historique, pas les autres), artefacts limités et compressés, `FF_USE_FASTZIP`, cache BuildKit en lecture dans les MR, `interruptible` et `workflow:auto_cancel`.
4. Mesure finale sur 3 pipelines de MR : la médiane doit être sous le seuil. Remplis le tableau du livrable (levier, gain mesuré, coût, décision).
5. Vérifie qu'aucune vérification n'a disparu (comparer la liste des jobs avant/après).

**Critères de réussite**
- [ ] `docs/livraison/ci/mesures-pipeline.md` contient la référence, le tableau des leviers et la ligne `Seuil : <N> s`.
- [ ] La médiane de durée des 3 derniers pipelines de MR réussis de `mediagenda/api` est inférieure ou égale au seuil.
- [ ] Le cache des jobs Python utilise une clé calculée sur `uv.lock`.

**Vérification** : `lab/bin/check 19 23`

<details><summary>Indice 1</summary>

La durée d'un pipeline n'est pas la somme de ses jobs : c'est le plus long chemin dans le graphe de dépendances, plus les attentes. Un job qui attend un stage entier alors qu'il n'a besoin que d'un seul job est le premier gain.
</details>

<details><summary>Indice 2</summary>

Un cache dont la clé change à chaque commit ne sert jamais ; un cache que chaque job **réécrit** en fin de job coûte un téléversement à chaque fois. `cache:policy` et `cache:key:files` règlent les deux.
</details>

**Pour aller plus loin** (facultatif) : lire les métriques Prometheus du gestionnaire de runners (`gitlab_runner_jobs`, temps d'attente) : au M21, elles alimenteront un tableau de bord.
