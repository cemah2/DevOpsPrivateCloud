# Sous le capot : du `git push` au pod de job

> Compte rendu de M19-E44 (PLAT-2044), relu par Karim Benali. Projet d'étude : `formation/ci-labo`,
> branche `capot`. Job étudié : **job 5127** (pipeline 2214), runner `k8s-par1`, nœud `k8s-w02`,
> 4 novembre 2026. Les lignes de journaux sont raccourcies ; aucun jeton, aucune URL signée.
> Heures en UTC ; valeurs relevées sur le lab (GitLab 19.5, Runner 19.5, Kubernetes 1.36).

## Réception du push

| Heure | Où | Ce qui se passe | Preuve (raccourcie) |
|---|---|---|---|
| 09:12:41.1 | gitlab-shell (`/var/log/gitlab/gitlab-shell/gitlab-shell.log`) | sshd lance gitlab-shell (`git-receive-pack`) pour la clé de l'utilisateur | `{"command":"git-receive-pack","gl_project_path":"formation/ci-labo",…}` |
| 09:12:41.2 | `api_json.log` | gitlab-shell demande à Rails si la poussée est permise | `route=/api/:version/internal/allowed status=200 duration_s=0.08` |
| 09:12:41.8 | Gitaly | objets reçus, référence `refs/heads/capot` mise à jour, *hook* `post-receive` | — |
| 09:12:41.9 | `api_json.log` | le *hook* prévient Rails | `route=/api/:version/internal/post_receive status=200` |
| 09:12:42.0 | client | `git push` rend la main | la CI n'a encore rien fait |

## Création du pipeline

| Heure | Travail Sidekiq (`/var/log/gitlab/sidekiq/current`) | Ce qu'il fait |
|---|---|---|
| 09:12:42.1 | `PostReceive` (même `correlation_id` que `post_receive`) | traite la poussée : événements, MR liées, demande de création de pipeline |
| 09:12:42.4 | `CreatePipelineWorker` | lit `.gitlab-ci.yml`, résout les composants, évalue `workflow:rules` et `rules`, crée le pipeline 2214 |
| 09:12:42.9 | `Ci::InitialPipelineProcessWorker` | calcule les jobs prêts : `capot` passe à `pending` |

Durée poussée → job `pending` : 0,9 s (Sidekiq peu chargé). Ce sont ces secondes que le développeur voit « sans pipeline ».

## File d'attente et runner (long polling)

- Requêtes `POST /api/v4/jobs/request` sans job : réponse `204` au bout d'environ 50 s (`gitlab-workhorse/current`, `duration_ms≈50000`) : Workhorse retient la requête (*long polling*) et ne la passe à Rails que si une notification Redis signale du nouveau.
- 09:12:43.0 : une requête en attente reçoit la notification ; Rails choisit le job (étiquettes `k8s`, référence non protégée, runner non protégé) : `status=201 duration_s=0.21` dans `api_json.log`. Le job passe en `running`.
- Gestionnaire (`kubectl -n gitlab-runner logs`, niveau `debug`) : `Checking for jobs... received job=5127 repo_url=https://git01…/formation/ci-labo.git runner=…`, puis `Using Kubernetes executor with image …busybox:1.37`, `Creating build pod`, `Waiting for pod ci-jobs/runner-…-project-31-concurrent-0-… to be running`.

## Le pod de job (Kubernetes)

- Conteneur d'initialisation `init-permissions` (droits sur `/builds`), conteneurs `build` (busybox) et `helper` (image *helper* par le cache Harbor `gitlab`) ; volumes `repo` (`emptyDir`, `/builds`), `scripts`, `logs` ; compte de service `ci-job`, `automountServiceAccountToken: false` ; `activeDeadlineSeconds: 3601` (délai du job 1 h + 1 s) ; `priorityClassName: medisphere-ci`.
- Journal d'audit (`k8s-cp01`, utilisateur `system:serviceaccount:gitlab-runner:gitlab-runner`) :

| Heure | Verbe | Ressource | Code |
|---|---|---|---|
| 09:12:43.4 | create | secrets (identifiants de registre du job) | 201 |
| 09:12:43.5 | create | pods | 201 |
| 09:12:43.6 → 09:12:47.9 | get | pods (attente de `Running`, toutes les ~0,5 s) | 200 |
| 09:12:48.1 | create | pods/attach (`helper` : clone) | 101 |
| 09:12:50.3 | create | pods/attach (`build` : script) | 101 |
| 09:14:51.0 | create | pods/attach (`helper` : artefacts) | 101 |
| 09:14:52.6 | delete | pods | 200 |
| 09:14:52.7 | delete | secrets | 200 |

Le pod lui-même n'a fait **aucune** requête à l'API (pas de jeton). Seul le gestionnaire parle au cluster.

## Artefacts et fin du job

- Journal : `PATCH /api/v4/jobs/5127/trace` toutes les ~3 s pendant l'exécution (`202`), morceaux rangés dans Redis (*live trace*) puis consolidés en fin de job.
- Artefact : `POST /api/v4/jobs/5127/artifacts/authorize` (`200`, Rails indique où écrire) puis `POST /api/v4/jobs/5127/artifacts` (`201`) : le flux passe par Workhorse, qui écrit le fichier puis prévient Rails. Emplacement : `/var/opt/gitlab/gitlab-rails/shared/artifacts/<empreinte du projet>/…` (pas de stockage objet configuré sur `git01`).
- État final : `PUT /api/v4/jobs/5127` (`state=success`, `200`) à 09:14:52 ; le pipeline passe à `success` par `PipelineProcessWorker`.

## Réponses aux questions

1. **Pourquoi Sidekiq ?** La poussée ne doit ni attendre ni échouer à cause de la CI ; la création du pipeline peut lire d'autres projets (composants) et durer. Sidekiq saturé : commits sans pipeline pendant un moment, rien n'est perdu.
2. **Pourquoi le long polling ?** Une requête ouverte par gestionnaire au lieu de milliers de requêtes inutiles ; Workhorse la maintient (~50 s) et la libère sur notification Redis.
3. **Réponse `201`** : identifiant, jeton du job, étapes, images et services, variables, informations Git, cache et artefacts. Le jeton du job vit le temps du job : clone, artefacts, journal, projets qui l'autorisent.
4. **Droits** : le gestionnaire crée, attache, lit et supprime des pods dans `ci-jobs` (Role du M19-E24) ; le pod de job exécute du code de projet et n'a aucun jeton.
5. **Journal** : Redis puis base ou stockage objet. Gestionnaire mort : job `running` jusqu'à son délai, puis échec ; pod orphelin arrêté par `activeDeadlineSeconds`.
6. **Workhorse** : transferts longs sans bloquer Puma ; taille maximale des artefacts dans *Admin > Settings > CI/CD* (100 Mo par défaut sur notre instance).
7. **Non redondant** : `git01` (tout GitLab), `reg01` (images), `s3-01` (cache), `buildkitd` (une réplique) ; redondants : API Kubernetes (3 nœuds, VIP), gestionnaire du runner (`replicas: 2`).
