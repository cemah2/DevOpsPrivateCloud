# Anatomie d'un job GitLab dans Kubernetes

> Ticket PLAT-2005 (M19-E05). Runner `k8s-par1` (GitLab Runner 19.4, exécuteur `kubernetes`),
> gestionnaire dans l'espace `gitlab-runner`, pods de job dans `ci-jobs`. Relu par Nadia Roussel.
> Ce qui est décrit ici a été observé sur un pod réel du job `anatomie` de `formation/ci-labo`.

## En une phrase

Pour chaque job, le gestionnaire crée **un pod** dans `ci-jobs`, y fait cloner le dépôt par le
conteneur `helper`, exécute ton script dans le conteneur `build`, fait téléverser artefacts et cache
par le `helper`, puis **supprime le pod**. Rien ne survit au job hors de GitLab, du cache S3 et de
Harbor.

## Le pod

```
pod runner-<jeton court>-project-<id>-concurrent-<n>-<suffixe>     (espace ci-jobs, nœud k8s-w0x)
├── conteneur d'initialisation « init-permissions »  (image helper)
│     prépare le fichier de journal partagé (touch + chmod 777) : build et helper n'ont pas
│     forcément le même UID
├── « build »    image du job (image: du .gitlab-ci.yml, ou celle par défaut du runner)
│     exécute before_script + script + after_script ; demandes/limites du runner ou KUBERNETES_*
├── « helper »   gitlab-runner-helper (même version que le gestionnaire)
│     clone le dépôt, restaure/sauve le cache (S3), télécharge et téléverse les artefacts,
│     relaie le journal du build vers le gestionnaire
└── « valkey », « svc-0 »…  un conteneur par service (services: du job), nommé par son alias
      (Runner 17.9 et plus) ou « svc-N » sans alias valide ; alias résolus par /etc/hosts (hostAliases)
      même espace de noms réseau que le reste du pod : joignables par localhost
volumes emptyDir partagés : « repo » (/builds : le dépôt cloné), « scripts » (/scripts-<projet>-<job> :
étapes générées par le gestionnaire), « logs » (/logs-<projet>-<job> : journal du build)
```

| Élément | Valeur chez MédiSphère | Pourquoi |
|---|---|---|
| Compte de service | `ci-job`, `automountServiceAccountToken: false` | un job n'a aucun droit sur l'API Kubernetes |
| Étiquettes | `project.runner.gitlab.com/id`, `…/name`, `…/namespace`, `job.runner.gitlab.com/pod`, `medisphere.internal/ci: job` | retrouver le pod d'un projet ; sélecteur des politiques réseau (M19-E24) |
| Annotations | `job.runner.gitlab.com/id`, `…/url`, `…/sha`, `…/ref`, `…/name`, `…/timeout` | passer du pod au job GitLab (l'URL du job est dans le pod) |
| Ressources | `build` 250m/512 Mi (demandes) et 2/2 Gi (limites) par défaut, surcharge jusqu'à 4/4 Gi ; `helper` 100m/128 Mi et 1/512 Mi ; services 100m/256 Mi et 1/1 Gi ; `init-permissions` : celles du `build` | classe QoS **Burstable** ; le quota `quota-ci` compte tout |
| Images | toutes par Harbor, étiquette et empreinte | `allowed_images` du runner et VAP `medisphere-images` |
| Pod Security | `baseline` appliqué, `restricted` en avertissement | `restricted` au palier 3 (M19-E24) |

## Chronologie d'un job

| Ligne du journal du job | Ce qui se passe | Qui |
|---|---|---|
| `Running with gitlab-runner 19.4.0 … on k8s-par1 …` | le gestionnaire a reçu le job (*long polling*) | gestionnaire |
| `Preparing the "kubernetes" executor` | lecture des surcharges `KUBERNETES_*`, contrôle des plafonds | gestionnaire |
| `Preparing environment` · `Waiting for pod ci-jobs/runner-… to be running, status is Pending` | création du Secret de registre éventuel, puis du pod ; ordonnancement, tirage des images, `init-permissions` | gestionnaire, kube-scheduler, kubelet |
| `Getting source from Git repository` | clonage (ou `fetch`) dans `/builds/<groupe>/<projet>` | `helper` |
| `Restoring cache` | téléchargement du cache par URL présignée (S3, M19-E07) | `helper` |
| `Downloading artifacts` | artefacts des jobs dont celui-ci dépend | `helper` |
| `Executing "step_script" stage of the job script` | ton script | `build` |
| `Saving cache` · `Uploading artifacts for successful job` | téléversements | `helper` |
| `Cleaning up project directory and file based variables` | ménage | `helper` |
| `Job succeeded` / `ERROR: Job failed: …` | fin ; le gestionnaire supprime le pod (et le Secret du job) | gestionnaire |

Mesures faites à la rédaction sur le lab (indicatives, à refaire chez toi) : 8 à 20 s de la prise du
job au pod prêt quand les images sont déjà sur le nœud, 30 à 90 s au premier tirage ; le pod
disparaît quelques secondes après la dernière ligne.

## La stratégie « attach »

Depuis GitLab Runner 16, l'exécuteur Kubernetes n'exécute plus chaque étape par `kubectl exec`
(stratégie historique, `FF_USE_LEGACY_KUBERNETES_EXECUTION_STRATEGY`) : le conteneur `build` démarre
avec un **shell en attente**, auquel le gestionnaire s'**attache** (`pods/attach`) pour lui envoyer
les étapes (scripts écrits dans `/scripts-…`). La sortie va dans le fichier partagé
`/logs-…/output.log`, que le `helper` relit et que le gestionnaire renvoie à GitLab.

Conséquences pratiques :
- `kubectl -n ci-jobs logs <pod> -c build` ne montre presque rien : le journal du job est **dans
  GitLab** (et dans le fichier partagé tant que le pod vit) ;
- une coupure de la connexion entre le gestionnaire et l'API Kubernetes pendant un job long n'arrête
  pas le script : le gestionnaire se rattache ;
- le gestionnaire a besoin de `pods/attach`, `pods/exec` et `pods/log` dans `ci-jobs` (son Role).

## Où regarder

| Symptôme | Regarder d'abord | Puis |
|---|---|---|
| Job « pending », aucun runner ne le prend | étiquettes du job et du runner, runner en pause ou hors ligne (*Admin → Runners*) | journal du gestionnaire : `kubectl -n gitlab-runner logs deploy/gitlab-runner` |
| « Waiting for pod … status is Pending » puis échec après 10 min (`poll_timeout`) | `kubectl -n ci-jobs get events --sort-by=.lastTimestamp` | pas de place sur les nœuds (`FailedScheduling`), image introuvable (`ErrImagePull`), volume absent (`FailedMount`) |
| Échec immédiat à « Preparing environment » (`setting up build pod: … forbidden`) | journal du job (le pod n'a jamais existé : aucun événement) | quota épuisé (`exceeded quota`, `kubectl -n ci-jobs describe quota`), LimitRange, VAP, Pod Security, compte de service absent |
| Échec avant le script (« Getting source ») | journal du job : clonage, TLS vers `git01` | flux `K8S_TRAV → git01:443`, Secret `gitlab-runner-certs` |
| Job tué (`OOMKilled`, code 137) | `kubectl -n ci-jobs describe pod` pendant le job ; journal du job (message du runner 19.5 si c'est le `helper`) | limites (`KUBERNETES_MEMORY_LIMIT`, plafonds du runner, LimitRange) |
| Artefact absent | lignes `Uploading artifacts` du journal (chemin, `expire_in`) | taille maximale des artefacts de l'instance, chemin hors de `$CI_PROJECT_DIR` |

Les pods disparaissent avec le job : pour un pod qui ne démarre pas, **observer pendant** l'attente
(`kubectl -n ci-jobs get pods -w`), ou lire les événements (gardés une heure par défaut).

## Ce qu'un job peut et ne peut pas faire

Il **peut** : lire son dépôt cloné, ses variables (dont les variables protégées s'il tourne sur une
référence protégée), joindre ses services par `localhost`, sortir sur le réseau (Harbor, `git01`,
Internet : la restriction des sorties arrive au palier 3, E24), écrire dans son pod.
Il **ne peut pas** : parler à l'API Kubernetes (aucun jeton, aucun droit), lire le jeton du runner
(il est dans l'espace `gitlab-runner`), dépasser les plafonds de ressources, utiliser une image hors
de Harbor ou `latest`, lancer un conteneur privilégié (Pod Security `baseline`), survivre à la fin
du job.
