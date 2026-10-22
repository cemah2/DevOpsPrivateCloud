# Module 19 — Intégration continue : palier 1 — Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`infra/` pour `plateforme/infra`, `ansible/` pour `plateforme/ansible`, `k8s/` pour `plateforme/k8s`, `ci-labo/` pour `formation/ci-labo`, `ci-templates/` pour `plateforme/ci-templates`, `mediagenda-api/` pour `mediagenda/api`, `medisphere/` pour la documentation). Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie, dans sa version **complète** à cet exercice (un `.extrait` indique ce qu'il faut ajouter à un fichier plus grand d'un module précédent) : `M19-E02/` (mémoire des travailleurs, `k8s_travailleur`, espaces, `wb-checks-livraison`), `M19-E03/` (`mon01`, rôle `mailpit`, `gitlab_hote`, flux, documentation), `M19-E04/` (cache Harbor `gitlab`, `secrets-k8s.sh`, release et valeurs du runner, premier pipeline), `M19-E05/` (job `anatomie`, `anatomie-job.md`), `M19-E06/` (pipeline en graphe), `M19-E07/` (cache S3, environnements), `M19-E08/` (chart `buildkitd`, gabarits, MédiAgenda).

**Ce qui a été vérifié à la rédaction** :
- chart **`gitlab/gitlab-runner` 0.93.0** (index `charts.gitlab.io` : 0.93.0 ↔ GitLab Runner 19.4.0, 0.94.0 ↔ 19.5.0) rendu par **Helm 4.3.1** (`helm template`) avec les valeurs de E04, E07 et E08 : Role et RoleBinding créés dans `ci-jobs` (gabarit `templates/role.yaml` : `coalesce(runners.jobNamespace, …)`), Secret du jeton monté par volume projeté (`runner-token`, `runner-registration-token`), Secret du cache exporté en `CACHE_S3_ACCESS_KEY`/`CACHE_S3_SECRET_KEY` par le script d'entrée du chart ; `config.template.toml` rendu puis relu par un analyseur TOML ; rendu validé par **kubeconform 0.8** (`-strict`, Kubernetes 1.36) ;
- clés TOML de `[runners.kubernetes]`, `[runners.cache]`, `[[runners.kubernetes.volumes.secret]]` et `[[runners.kubernetes.volumes.config_map]]` lues dans le code de **GitLab Runner v19.4.0** (`common/config.go`, `cache/cacheconfig/cacheconfig.go`) ; nom de l'image *helper* (`registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.4.0`, `helpers/container/helperimage/linux_info.go`), conteneurs du pod (`build`, `helper`, `init-permissions`, `svc-N`), étiquettes et annotations, commande du conteneur `init-permissions` et remplacement du point d'entrée des images par la commande du runner (`executors/kubernetes/kubernetes.go`) ;
- empreintes relevées sur les registres amont le 22/10/2026 (identiques à travers un cache Harbor) : `gitlab-runner:alpine-v19.4.0`, `gitlab-runner-helper:x86_64-v19.4.0`, `moby/buildkit:v0.34.1-rootless` et `v0.34.0-rootless` (cette dernière égale à celle du M12), `debian:trixie-slim`, `valkey/valkey:8.1`, `astral-sh/uv:0.12.23-python3.13-trixie-slim` ; archive **Mailpit 1.31.6** (`mailpit-linux-amd64.tar.gz`, SHA-256 `10fa12cc…3f91`, binaire `mailpit version` = v1.31.6) ;
- options et variables `MP_*` de Mailpit, format du fichier de mots de passe (bcrypt `$2a$`/`$2b$`/`$2y$` acceptés), réponse `530 5.7.0 Must issue a STARTTLS command first`, absence de rôles dans l'API, routes `/readyz` et `/livez` sans authentification : code de Mailpit v1.31.6 ;
- BuildKit **0.34.1** : options de `buildctl` (`--addr` lu dans `BUILDKIT_HOST`, `--tlsdir` qui accepte `ca.crt`/`tls.crt`/`tls.key`), clés de `buildkitd.toml` (`[grpc.tls]`, `[worker.oci]` `rootless`, `noProcessSandbox`, `maxUsedSpace`, `reservedSpace`, `[registry."…"] ca`), exigence du certificat client dès que `ca` est posé et lecture des certificats **au démarrage seulement** (`cmd/buildkitd/main.go`, `serverCredentials`), TLS jamais appliqué aux sockets locaux ; manifeste amont `examples/kubernetes/deployment+service.rootless.yaml` ;
- chart local `charts/buildkitd` : `helm lint`, `helm template`, **kubeconform** avec les schémas de cert-manager et de Cilium (catalogue de CRD datreeio) : 10 objets valides ;
- rôles `mailpit`, `gitlab_hote` (étendu) et `k8s_travailleur` (étendu), playbook `supervision.yml` : **ansible-lint 26.10 profil `production`** (ansible-core 2.21.5, `community.general`, `ansible.posix`) ; gabarits de Mailpit rendus, unité lue par `systemd-analyze verify` ;
- `ansible-vault encrypt … --output <fichier> -` (chiffrement depuis l'entrée standard, utilisé en E04) essayé avec ansible-core 2.21 ;
- `outils/secrets-k8s.sh` : `shellcheck -x`, `bash -n`, et exécution des modes `lister`, `verifier`, `appliquer` contre un `kubectl` simulé ;
- projet `ressources/E04-ci-labo/` : `uv lock` et `uv run pytest` (5 tests) ; tous les `.gitlab-ci.yml` : `yamllint` et analyse YAML (une commande `echo "pod : …"` non entre guillemets était une **table** YAML : corrigé, voir les pièges de E04) ; scripts extraits des gabarits `image.yml` et `supply-chain.yml` : `sh -n` ;
- manifestes de `plateforme/k8s` : `yamllint` et `kubeconform -strict` ; tous les checks : `shellcheck -x` et `bash -n`.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- tout ce qui demande le lab : redimensionnement des travailleurs, Mailpit sur `mon01`, runner en ligne, pods de job, buildkitd, pipelines ; les sorties montrées sont **représentatives** ;
- le cache Harbor `gitlab` en type « Docker Registry » générique vers `registry.gitlab.com` (authentification anonyme par jeton du registre amont : constatée avec `curl` à la rédaction, pas à travers Harbor) ;
- la confiance du *helper* envers `s3-01` par `SSL_CERT_DIR` (comportement documenté du paquet `crypto/x509` de Go pour Linux ; le chemin `/etc/gitlab-runner/certs/ca.crt` de la documentation de GitLab Runner dépend du script d'entrée de l'image *helper*, que l'exécuteur Kubernetes remplace par sa propre commande — lu dans le code, non observé) ;
- les motifs `allowed_images = ["registry.par1.medisphere.internal/**"]` sur des références avec empreinte (`…@sha256:…`) : syntaxe des motifs à double étoile de la documentation, non essayée ;
- BuildKit *rootless* dans un pod sans `allowPrivilegeEscalation: false` (exigence de `newuidmap`, d'après la documentation amont) et sur un volume `ceph-rbd` (pilote de stockage *overlay* en espace de noms utilisateur, noyau 6.12 de Debian 13) ;
- le fichier de réglages SMTP généré par GitLab sous `/var/opt/gitlab/gitlab-rails/etc/` (lu par le check de E03) : nom de fichier et forme à confirmer sur ta 19.4 ;
- le message exact des journaux du runner pour le cache (« Checking cache for … », « Successfully extracted cache ») sur lequel s'appuie le check de E07.

---

### M19-E01 — Test de positionnement : intégration continue

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, relis les « Concepts clés » de l'introduction avant E04 ; les questions 1 à 5 sont reprises en E06, 6 à 9 en E07 et E25, 10 à 13 en E07, 14 à 18 en E04, E05, E08 et E09, 19 et 20 en E13 et E27.

**Réponses argumentées — structure d'un pipeline**

**1. `needs`.** Sans `needs`, `build-image` attend la fin de **tous** les jobs des stages précédents : `lint` puis `test`, donc au moins les 12 minutes des tests. Avec `needs: [lint-dockerfile]`, il démarre dès que `lint-dockerfile` a réussi, en parallèle des tests (graphe orienté, DAG) : le pipeline raccourcit d'autant. `needs: []` le fait démarrer **immédiatement** à la création du pipeline, sans attendre aucun job (il ne reçoit alors aucun artefact). Attention : avec `needs`, un job ne reçoit que les artefacts des jobs qu'il cite.

**2. Réponse C.** GitLab refuse la configuration : un job ne peut pas combiner `rules` et `only`/`except` (« config key may not be used with `rules` »), le pipeline n'est pas créé et l'erreur s'affiche dans l'éditeur de pipeline et dans la liste des pipelines. A et B supposent une combinaison qui n'existe pas ; D est faux, GitLab ne choisit pas. Conséquence pratique : migrer un fichier ancien vers `rules` se fait job par job, entièrement (M19-E21).

**3. `rules` et `workflow:rules`.** Les `rules` d'un job décident si **ce job** est ajouté au pipeline (et avec quel `when`, `allow_failure`, quelles variables). Les `workflow:rules` décident si **le pipeline** est créé. Le doublon « pipeline de branche + pipeline de MR » se règle dans `workflow:rules` : pour une poussée sur une branche qui a une MR ouverte (`$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS`), `when: never`, et la règle des pipelines de MR crée le seul pipeline (E06).

**4. `changes` sur une nouvelle branche.** Dans un pipeline de branche, `changes` compare le commit poussé à l'**état précédent de la branche** ; pour le premier commit poussé d'une nouvelle branche, il n'y a pas d'état précédent : `changes` est **toujours vrai** (tous les jobs à `changes` sont ajoutés). Dans un pipeline de MR, il compare la branche source à la **branche cible** : c'est la comparaison la plus utile, et une raison de préférer les pipelines de MR pendant le développement. Hors poussée et hors MR (planification, lancement manuel), `changes` est aussi toujours vrai.

**5. `interruptible`.** Un job `interruptible: true` peut être annulé quand un pipeline plus récent démarre sur la même référence ; le réglage d'annulation automatique (*auto-cancel redundant pipelines*, et `workflow:auto_cancel:on_new_commit`) déclenche cette annulation. Trois commits poussés à la suite ne font tourner qu'un pipeline jusqu'au bout. Un déploiement interrompu à mi-chemin laisse la cible dans un état intermédiaire (la moitié des objets appliqués, une migration commencée) : jamais `interruptible` sur un job qui modifie le monde extérieur (déploiement, publication, signature).

**Réponses argumentées — variables et secrets**

**6. Variable protégée.** Elle **n'existe pas** dans un pipeline de la branche `essai` (non protégée) : `echo $DB_PASSWORD` affiche une ligne vide. Le masquage n'entre même pas en jeu. C'est la protection principale des secrets de déploiement en édition gratuite : seules les branches et étiquettes protégées (donc les Maintainers qui y poussent ou fusionnent) reçoivent les secrets. Piège : protéger la variable sans protéger la branche `main` ne sert à rien.

**7. Réponse B.** Ordre de priorité de GitLab (documentation « CI/CD variable precedence », du plus fort au plus faible) : variables de politiques d'exécution, variables du **pipeline** (lancement manuel, planification, déclencheur, API), variables de **projet**, de **groupe**, d'**instance**, variables des rapports `dotenv`, variables **du job** dans le fichier, variables **globales** du fichier, variables de déploiement, variables prédéfinies. La variable du projet l'emporte donc sur celle du job. C'est contre-intuitif (on croit que « le plus local » gagne) et c'est volontaire : un Maintainer peut surcharger un fichier qu'il ne contrôle pas. A et C sont plus faibles ; D n'existe pas.

**8. Type fichier.** GitLab écrit la valeur dans un **fichier temporaire** et la variable contient son **chemin**. Pour les outils qui attendent un fichier (`kubeconfig`, clé privée SSH, certificat, `COSIGN_PRIVATE_KEY` du M13) : on évite d'écrire le secret soi-même sur le disque (`echo "$VAR" > fichier`, qui peut fuir dans un `set -x` ou rester dans un artefact).

**9. `CI_JOB_TOKEN`.** Un jeton créé pour **un job**, valable **pendant son exécution** seulement, avec les droits de l'utilisateur qui a déclenché le job, restreints à un sous-ensemble de l'API (cloner, artefacts, registre de paquets, quelques points d'API) et aux projets qui l'autorisent (liste d'autorisation entrante, M19-E25). Il expire à la fin du job : une fuite dans un journal est un problème de courte durée, mais pas nul (le job peut durer une heure).

**Réponses argumentées — artefacts, cache, environnements**

**10. Artefacts ou cache.** (a) rapport JUnit : **artefact** (rapport `junit`), GitLab doit le lire et l'afficher dans la MR ; (b) `.venv` ou cache de `uv` : **cache**, une optimisation, retéléchargeable ; (c) binaire à tester par le job suivant : **artefact**, c'est un résultat qui doit arriver à coup sûr ; (d) base de Trivy : **cache** (M13-E09). Règle : un artefact est garanti et traçable, un cache est un « peut-être plus rapide ».

**11. Cache local et exécuteur Kubernetes.** Le cache local est un dossier du disque de la machine qui exécute. Sur `runner01` (shell), tous les jobs tournent sur la même VM : le dossier est retrouvé. Dans Kubernetes, chaque job est un **pod neuf**, sur un nœud quelconque, détruit à la fin : un cache local disparaît avec le pod. Il faut un cache **distribué** (stockage objet S3, E07) que le *helper* télécharge et téléverse.

**12. `resource_group`.** Il garantit qu'**un seul** job du groupe tourne à la fois (les autres attendent « waiting for resource »). Il ne garantit **pas l'ordre** par défaut (`process_mode: unordered`) : deux déploiements en attente peuvent passer dans un ordre quelconque, et un ancien pipeline peut déployer **après** un plus récent. Les modes `oldest_first` et `newest_first` (et les variantes récentes) règlent l'ordre ; on peut aussi n'autoriser le déploiement que depuis le dernier pipeline.

**13. Sans environnements protégés.** Branches et **étiquettes protégées** (seuls les Maintainers poussent ou posent une étiquette `v*`), jobs de déploiement en production limités par `rules` à ces références, **variables protégées** (les identifiants de production n'existent que là), jobs **manuels** (un clic, tracé), `resource_group`, et revue de MR obligatoire sur `main` (ADR-0051). Ce qu'on n'a pas : une approbation formelle **au moment** du déploiement, et l'interdiction pour un Maintainer de lancer le job manuel.

**Réponses argumentées — runners et exécution**

**14. Job sans étiquette.** Aucun runner n'accepte les jobs sans étiquette (`run_untagged: false` partout) : le job reste `pending` (et l'interface dit « This job is stuck because you don't have any active runners that can run this job »). Corrections : ajouter `tags:` au job (ou `default: tags:` au fichier), ou activer « Run untagged jobs » sur un runner. Préférer les **étiquettes** : un runner qui prend les jobs non étiquetés prend ceux de **tous** les projets, sans que personne l'ait décidé, avec ses droits et ses accès réseau.

**15. Réponse B.** Le runner (le gestionnaire) ouvre la connexion et interroge GitLab (`POST /api/v4/jobs/request`), GitLab garde la requête ouverte jusqu'à ce qu'un job arrive ou qu'un délai expire (*long polling*). Il n'y a ni port d'écoute sur le runner (A : 8093 est le port optionnel de la *session* du terminal web), ni webhook (C), ni tunnel (D ; c'est le modèle de l'**agent** pour Kubernetes, M19-E18). Conséquence réseau : seul le sens runner → GitLab est ouvert (E04).

**16. Jeton d'authentification `glrt-`.** Le runner est **créé dans GitLab** (interface ou API) par quelqu'un d'identifié, avec sa description, ses étiquettes, sa portée : ces propriétés appartiennent à GitLab et non plus au fichier `config.toml` de la machine. Chaque runner a **son** jeton, qu'on réinitialise sans toucher aux autres ; l'ancien jeton d'enregistrement, partagé, permettait à quiconque le possédait d'enregistrer autant de runners qu'il voulait, sans trace. GitLab 19 peut désactiver complètement l'ancien mécanisme (réponse `410 Gone`).

**17. Exécuteurs.** `shell` : simple, rapide, les outils de l'hôte sont disponibles ; risque : tous les jobs partagent l'hôte et son état (fichiers laissés, droits du compte `gitlab-runner`). `docker` : isolation par conteneur, image par job ; risque : la tentation du socket Docker monté ou du mode privilégié (Docker-in-Docker), équivalents à root sur l'hôte. `kubernetes` : élasticité, quotas, politiques réseau, un pod par job ; risque : complexité (RBAC du gestionnaire, Pod Security, ressources), et les mêmes tentations (pods privilégiés). On citera aussi `instance`/`docker-autoscaler` (VM à la demande) et `custom`.

**18. Docker-in-Docker.** `dockerd` doit créer des espaces de noms et des cgroups, monter des systèmes de fichiers (overlay), écrire des règles netfilter : il lui faut toutes les capacités et l'accès aux périphériques, donc un conteneur **privilégié**. Un job malveillant dans un conteneur privilégié est root sur le nœud : monter le disque de l'hôte, lire les secrets du kubelet ou des autres pods, charger un module noyau, s'installer à demeure. D'où la règle 1 du module.

**Réponses argumentées — pipelines de MR et de branche**

**19. Pipelines de MR.** Pipeline de **branche** (`CI_PIPELINE_SOURCE=push`) : teste la tête de la branche, variables `CI_COMMIT_BRANCH` ; son statut s'affiche sur le commit. Pipeline de **MR** (`merge_request_event`) : teste la tête de la branche source, dispose des variables `CI_MERGE_REQUEST_*` (branche cible, IID, étiquettes de la MR), s'affiche dans la MR ; `CI_COMMIT_BRANCH` n'y est **pas** défini (`CI_COMMIT_REF_NAME` l'est). Pipeline de **résultat fusionné** : teste le résultat de la fusion de la source dans la cible, avant la fusion réelle ; c'est une fonction **Premium**, comme les trains de fusion. En CE, on s'en approche en exigeant une branche à jour (« fast-forward merge » ou rebase obligatoire).

**20. Un seul gros runner.** (1) **Point unique de défaillance** et de saturation : une panne ou une mise à jour arrête toute la CI, et un projet gourmand affame tous les autres. (2) **Mélange des niveaux de confiance** : les jobs de branches de stagiaires et ceux qui signent ou déploient partagent la même machine, les mêmes caches, les mêmes accès réseau. (3) 50 jobs sur une VM : contention disque et mémoire, durées imprévisibles. À la place : des runners **élastiques** (pods à la demande, E04), cloisonnés par niveau de confiance (runner protégé, E24), avec des quotas et des limites par job.

---

### M19-E02 — Préparer `k8s-par1` pour la CI

**Solution**

*A. La mémoire des travailleurs.*

1. Mesures (représentatives) :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 top nodes
   NAME       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
   k8s-cp01   312m         15%      2310Mi          63%
   …
   k8s-w01    640m         16%      5712Mi          77%
   k8s-w02    580m         14%      5420Mi          73%
   k8s-w03    710m         17%      6034Mi          81%
   admin@adm01:~$ kubectl --context k8s-par1 describe node k8s-w01 | sed -n '/Allocated resources/,/Events/p'
     Resource           Requests      Limits
     cpu                2350m (58%)   6 (150%)
     memory             5120Mi (69%)  9Gi (124%)
   ```
   Il reste ≈ 2 Gi de mémoire **demandable** par travailleur : le quota de `ci-jobs` (12 Gi de demandes) ne tiendrait pas. Après passage à 10 Go, environ 2 Gi de plus par nœud, soit ≈ 4 Gi × 3 = 12 Gi demandables : juste ce qu'il faut pour le quota, d'où la règle « SonarQube et Jenkins jamais ensemble » (palier 2).
2. [`noeuds.tf.extrait`](fichiers/M19-E02/infra/envs/k8s/noeuds.tf.extrait) : une table `memoire_travailleurs_mo` (même idée que `stockage_actif` du M16-E05) lue par `lookup()`. Le plan d'une MR qui ne change que `k8s-w01` : `~ memory { ~ dedicated = 8192 -> 10240 }` sur une seule VM. Sur une VM **démarrée**, le fournisseur appliquerait le changement puis **redémarrerait** la VM (`reboot_after_update`, vrai par défaut, M05-E06) : sans drain, ce serait une coupure brutale du nœud. D'où l'arrêt **avant** l'apply.
3. Pour chaque travailleur (exemple `k8s-w01`, VMID 2144) :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 get pdb -A
   admin@adm01:~$ kubectl --context k8s-par1 drain k8s-w01 --ignore-daemonsets --delete-emptydir-data --timeout=10m
   node/k8s-w01 cordoned
   evicting pod mediagenda-recette/mediagenda-6d9f…
   …
   node/k8s-w01 drained
   admin@adm01:~$ ssh root@pve01 'qm shutdown 2144 --timeout 180 && qm status 2144'
   status: stopped
   ```
   MR sur `plateforme/infra` (seule l'entrée `k8s-w01` passe à 10240 ; dans le fichier final les trois valent 10240, après trois MR), pipeline : `plan` (1 to change), `apply`. Le module `vm-noeud` déclare `started = true` : l'apply modifie la VM arrêtée **et la démarre**.
   ```
   admin@adm01:~$ kubectl --context k8s-par1 get node k8s-w01 -w          # attendre Ready
   admin@adm01:~$ kubectl --context k8s-par1 uncordon k8s-w01
   admin@adm01:~$ kubectl --context k8s-par1 get pods -A -o wide --field-selector spec.nodeName=k8s-w01 | head
   admin@adm01:~$ kubectl --context k8s-par1 get pods -n mediagenda-prod -o wide
   ```
   Indisponibilité du nœud : 3 à 5 minutes (drain, arrêt, démarrage, kubelet `Ready`). Les pods évincés ont été replanifiés sur les deux autres ; ils ne reviennent **pas** d'eux-mêmes sur `k8s-w01` (pas de rééquilibrage automatique) : c'est normal.
4. `free -m` dans le nœud montre ≈ 9,7 Gio. `kubectl describe node` : `Capacity: memory: 10229…Ki`, `Allocatable` un peu inférieur : la réservation du kubelet (seuil d'éviction `evictionHard` `memory.available<100Mi` par défaut, et `systemReserved`/`kubeReserved` si posés dans la configuration du kubelet du M14). L'ordonnanceur raisonne sur l'**allouable**.

*B. Le paramètre noyau.*

5. Rôle [`k8s_travailleur`](fichiers/M19-E02/ansible/roles/k8s_travailleur/) : `defaults/main.yml` (variable `k8s_travailleur_sysctl`, fichier `/etc/sysctl.d/91-k8s-travailleur.conf`), `tasks/sysctl.yml` (écriture, rechargement, **lecture de la valeur effective** et comparaison), `tasks/main.yml` (inclusion avec l'étiquette `travailleur_sysctl`), `meta/argument_specs.yml`. `jonction.yml` et les gabarits du M14 sont inchangés.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-cluster.yml --limit k8s_travailleurs --tags travailleur_sysctl --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-cluster.yml --limit k8s_travailleurs --tags travailleur_sysctl
   admin@adm01:~$ for n in k8s-w01 k8s-w02 k8s-w03; do ssh $n sysctl -n vm.max_map_count; done
   524288
   …
   ```
   (Le playbook du M14 est en `serial: 1`.) Second passage : `changed=0`.
6. `vm.max_map_count` n'est **pas** un paramètre « d'espace de noms » : il vaut pour tout le noyau du nœud. Kubernetes ne laisse un pod régler (`securityContext.sysctls`) que des paramètres d'espace de noms jugés sûrs. Un conteneur d'initialisation qui l'écrit lui-même doit être **privilégié** (écrire dans `/proc/sys` de l'hôte) : Pod Security `baseline` le refuse, et ce serait un conteneur privilégié dans un chart tiers à chaque démarrage. Le réglage appartient au nœud, donc au rôle Ansible du nœud.

*C. Les espaces de la CI.*

7. Fichiers : [`espaces/gitlab-runner/00-namespace.yaml`](fichiers/M19-E02/k8s/espaces/gitlab-runner/00-namespace.yaml) (`restricted`), [`espaces/ci-jobs/`](fichiers/M19-E02/k8s/espaces/ci-jobs/) (`00-namespace.yaml` en `baseline` appliqué et `restricted` en avertissement et audit, étiquette `medisphere.internal/equipe: plateforme` ; `10-quota.yaml` ; `20-limites.yaml` ; `30-comptes-service.yaml`), [`espaces/buildkit/00-namespace.yaml`](fichiers/M19-E02/k8s/espaces/buildkit/00-namespace.yaml) (`privileged`, exception écrite). Pour `buildkit` : le manifeste amont *rootless* pose `seccompProfile: Unconfined` et `appArmorProfile: Unconfined` ; la norme `baseline` interdit justement un profil seccomp `Unconfined` et un profil AppArmor autre que `RuntimeDefault`/`Localhost` : seul `privileged` l'admet. On compense par l'isolement (un seul pod, aucun droit d'écriture des équipes, réseau fermé en E08) et on garde `restricted` en avertissement pour voir tout écart **supplémentaire**.
8. Un ResourceQuota sur `limits.memory` (ou `requests.*`) **refuse** tout pod dont un conteneur ne déclare pas cette ressource (« must specify limits.memory »). Les conteneurs que le runner ne règle pas lui-même (`init-permissions` reçoit les ressources du `build`, mais un service ou un pod lancé à la main n'en a pas forcément) seraient refusés. Le LimitRange **complète** les valeurs manquantes à l'admission, et borne les surcharges (`max`).
9. [`rbac/wb-checks-livraison.yaml`](fichiers/M19-E02/k8s/rbac/wb-checks-livraison.yaml). Redéclarer des ressources déjà lisibles par `wb-checks-base` découple les vérifications du module de la base : si quelqu'un réduit un jour `wb-checks-base` (par exemple pour retirer `pods/log`), les checks du M19 continuent de fonctionner. Une règle en double ne coûte rien ; une ClusterRole agrégée est l'**union** des règles.
10. Contrôle :
    ```
    admin@adm01:~$ kubectl --context k8s-par1 get ns gitlab-runner ci-jobs buildkit --show-labels
    NAME            STATUS   AGE   LABELS
    gitlab-runner   Active   2m    …pod-security.kubernetes.io/enforce=restricted…
    ci-jobs         Active   2m    medisphere.internal/equipe=plateforme,…enforce=baseline…,warn=restricted…
    buildkit        Active   2m    …enforce=privileged…
    admin@adm01:~$ kubectl --context k8s-par1 auth can-i get secrets -n ci-jobs --as=system:serviceaccount:ci-jobs:ci-job
    no
    ```
11. Essais :
    ```
    admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs run essai1 --image=registry.par1.medisphere.internal/dockerhub/library/alpine:latest
    The pods "essai1" is invalid: : ValidatingAdmissionPolicy 'medisphere-images' with binding 'medisphere-images' denied request: image(s) sans version explicite ou en « latest » : …
    admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs run essai2 \
        --image=registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim@sha256:62bd…34ad -- sleep 300
    Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "essai2" …), unrestricted capabilities …, runAsNonRoot != true …, seccompProfile …
    pod/essai2 created
    admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs get pod essai2 -o jsonpath='{.spec.containers[0].resources}'; echo
    {"limits":{"cpu":"1","memory":"1Gi"},"requests":{"cpu":"100m","memory":"128Mi"}}
    admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs delete pod essai2
    ```
    Le premier est refusé par la VAP (étiquette `latest`) ; le second est **créé** (`baseline`) avec l'avertissement `restricted` (la liste de ce qu'il faudra corriger en E24) et les ressources du LimitRange.

Le check vérifie la mémoire dans Proxmox et dans Kubernetes, l'état des nœuds, `vm.max_map_count` effectif et persistant par SSH, les espaces et leurs étiquettes de Pod Security, le quota, le LimitRange, le compte `ci-job` et l'absence de liaison vers lui, la ClusterRole `wb-checks-livraison` (étiquette, pas de Secrets), et le code sur `main`.

**Explications**

- **Pourquoi un nœud à la fois, arrêté avant l'apply.** La mémoire d'une VM Proxmox ne s'ajoute pas à chaud sans *hotplug* (et NUMA) : il faut un redémarrage. Laisser le fournisseur redémarrer une VM non drainée, c'est couper brutalement des pods (dont des répliques de PostgreSQL de `mediagenda-prod`, PDB ou non). Drainer d'abord rend l'arrêt **ordinaire** pour Kubernetes ; une MR par nœud rend le plan lisible et le retour arrière évident.
- **Quota + LimitRange, un couple.** Le quota protège le **cluster** de la CI (une rafale de 50 jobs ne prend pas les nœuds des applications) ; le LimitRange protège le **quota** des pods qui ne déclarent rien. Les plafonds du runner (E04) protègent l'un et l'autre d'un job qui demanderait 32 Gi.
- **`ci-job`, un compte de service vide.** Kubernetes monte par défaut le jeton du compte `default` dans chaque pod ; ce jeton donne accès à l'API (au moins à la découverte). Un compte dédié, sans liaison et sans jeton monté, ferme la porte pour tous les jobs, quel que soit le projet.
- **Trois espaces, trois régimes.** Le gestionnaire (droits sur l'API, `restricted`), les jobs (code non relu des branches, aucun droit, `baseline` puis `restricted`), le démon de construction (exception seccomp/AppArmor, isolé). Les mélanger obligerait à appliquer au tout le régime le plus permissif.

**Alternatives**

- **Ajouter un quatrième travailleur** plutôt que grossir les trois : plus réaliste (l'élasticité d'une CI se fait en nœuds), mais 10 Go de plus sur `pve01` alors que le profil des blocs D et E est déjà à ≈ 100 Go.
- **Nœuds dédiés à la CI** (taint `dedie=ci:NoSchedule`, `node_selector` et tolérances dans le runner) : isole les applications de la CI ; à trois travailleurs, on perdrait un tiers du cluster pour les applications. C'est la cible d'une vraie production (palier 3, E27, « Pour aller plus loin »).
- **Pod Security `restricted` dès maintenant** dans `ci-jobs` : possible si l'on règle tout de suite les contextes de sécurité du runner (utilisateur non root, `seccompProfile`, capacités) ; beaucoup d'images de job tournent en root et casseraient. On l'apprend par étapes (E24).

**Pièges classiques**

- `kubectl drain` bloqué indéfiniment par un PDB `maxUnavailable: 0` ou par un pod sans contrôleur (`--force` le supprimerait sans le recréer) : lire le message, jamais `--force` sur un nœud de production sans savoir quoi.
- Oublier `uncordon` : le nœud reste `SchedulingDisabled`, la capacité du cluster baisse d'un tiers sans alerte.
- Changer les trois entrées de la table dans une seule MR : le pipeline redémarre les trois travailleurs **en même temps** (le fournisseur traite les VM en parallèle).
- Mettre `vm.max_map_count` dans `k8s_noeud_sysctl` (tous les nœuds) : sans effet nuisible, mais faux (les nœuds de contrôle n'en ont pas besoin) ; ou l'écrire dans le même fichier que `k8s_noeud` : deux rôles qui possèdent le même fichier se réécrivent l'un l'autre.
- Un quota sans LimitRange : les jobs passent (le runner pose des ressources), mais le premier service sans ressources fait échouer le job avec « exceeded quota » ou « must specify limits » — difficile à relier.
- Étiquetter `ci-jobs` sans vérifier la VAP : toute image de job hors Harbor est refusée **au moment de la création du pod**, le job échoue avant le script. C'est voulu ; encore faut-il que les images par défaut du runner soient dans Harbor (E04).

**En production chez MédiSphère**

Des nœuds dédiés aux jobs de CI (taint, pool de nœuds autoscalé par Cluster API ou par l'autoscaler du runner), des quotas par niveau de confiance, la supervision de l'occupation du quota et du temps d'attente des jobs (M21), et le redimensionnement des nœuds par remplacement (nouveau nœud, drain de l'ancien) plutôt que par modification de VM.

---

### M19-E03 — `mon01` et Mailpit : la messagerie du lab

**Solution**

*A. La VM.*

1. [`socle/mon01.tf`](fichiers/M19-E03/infra/socle/mon01.tf) : `vm-debian`, `enregistrement-dns`, et la ressource `powerdns_record` du CNAME `smtp` (comme `registry` au M13). Pré-requis NetBox : l'étiquette `role-supervision` (ajoutée au fichier de données du script de modélisation de M06-E05 si elle n'existe pas). Plan :
   ```
   Plan: 7 to add, 0 to change, 0 to destroy.
   ```
   (VM, objets NetBox, A, PTR, CNAME ; le nombre exact dépend de ta version de `vm-debian`). Puis `root@pve01:~# qm set 1014 --startup order=5`.
2. ```
   admin@adm01:~$ dig +short mon01.par1.medisphere.internal; dig +short -x 10.10.20.19; dig +short smtp.par1.medisphere.internal
   10.10.20.19
   mon01.par1.medisphere.internal.
   mon01.par1.medisphere.internal.
   10.10.20.19
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph role_supervision
   @role_supervision:
     |--mon01
   ```
3. Rôles communs : `uv run ansible-playbook playbooks/site.yml --limit mon01` (pipeline protégé). Sauvegarde : ajoute 1014 à la sélection du travail PBS du socle (`pvesh get /cluster/backup` pour le retrouver ; si ton travail sélectionne le pool `lab`, rien à faire), puis une exécution manuelle : `root@pve01:~# vzdump 1014 --storage pbs-par2 --mode snapshot`.

*B. Le rôle `mailpit`.*

4. Aide de Mailpit (extraits) : `--smtp` (défaut `[::]:1025`), `--listen` (défaut `[::]:8025`), `--smtp-tls-cert`/`--smtp-tls-key`, `--smtp-require-starttls`, `--ui-tls-cert`/`--ui-tls-key`, `--ui-auth-file`, `--database`, `--max` (défaut 500 messages), `--max-age`, `--allowed-hosts`. Par défaut : SMTP sans TLS sur 1025, interface en HTTP **sans authentification**, sur toutes les adresses ; aucun relais (les options `--smtp-relay-*` et `--smtp-forward-*` sont vides) : Mailpit garde tout et ne livre rien.
   ```
   admin@adm01:~/m19/e03$ curl -fLO https://github.com/axllent/mailpit/releases/download/v1.31.6/mailpit-linux-amd64.tar.gz
   admin@adm01:~/m19/e03$ sha256sum mailpit-linux-amd64.tar.gz
   10fa12ccc610f653d4ed4df848c1817f9935dcf4e9a6a458a19ab0fa02093f91  mailpit-linux-amd64.tar.gz
   ```
   Le projet ne publie pas de fichier de sommes : l'empreinte est relevée une fois, si possible comparée à une seconde source (un collègue qui télécharge depuis un autre réseau), puis **figée** dans l'inventaire ; toute réinstallation vérifie la même empreinte.
5. Rôle [`mailpit`](fichiers/M19-E03/ansible/roles/mailpit/) : `defaults/main.yml`, `meta/` (dont `argument_specs.yml`), `tasks/main.yml` (contrôles, compte, dossiers, comptes de l'interface, options, unité, service), `tasks/binaire.yml` (archive vérifiée par `get_url … checksum: sha256:…` **avant** extraction, un dossier par version, lien `/usr/local/bin/mailpit`), `tasks/controles.yml` (bannière SMTP et `STARTTLS` annoncé, session STARTTLS vérifiée, `/readyz` en HTTPS vérifié, `401` sans mot de passe), `templates/mailpit.env.j2` (options `MP_*`, aucun secret), `templates/mailpit.service.j2`, `handlers/main.yml`. Points clés :
   - **port 25 sans root** : `User=mailpit`, `AmbientCapabilities=CAP_NET_BIND_SERVICE` et `CapabilityBoundingSet=CAP_NET_BIND_SERVICE` (la seule capacité que le processus peut avoir), `NoNewPrivileges=yes` ;
   - système de fichiers : `ProtectSystem=strict` + `ReadWritePaths=/var/lib/mailpit` ; le certificat et le fichier de mots de passe sont lus, jamais écrits ;
   - comptes de l'interface par `community.general.htpasswd` (bcrypt ; `python3-passlib` et `python3-bcrypt` sur `mon01`), `no_log`, mots de passe en Vault `critique` ([`host_vars/mon01/mailpit.yml`](fichiers/M19-E03/ansible/inventories/lab/host_vars/mon01/mailpit.yml), [`vault.yml.exemple`](fichiers/M19-E03/ansible/inventories/lab/host_vars/mon01/vault.yml.exemple)) ;
   - `MP_SMTP_REQUIRE_STARTTLS=true` : une session qui ne bascule pas en TLS est refusée ; `MP_ALLOWED_HOSTS` contre le *rebinding* DNS ; `MP_DISABLE_VERSION_CHECK` (la version est pilotée par l'inventaire, pas par une requête à GitHub).
   `systemd-analyze security mailpit` donne un score bas (« OK ») ; les lignes qui restent sont attendues : réseau non isolé (`PrivateNetwork=` impossible pour un serveur), familles d'adresses `AF_INET`/`AF_INET6`, `CAP_NET_BIND_SERVICE`, absence de filtrage `IPAddressAllow=` (on pourrait le poser pour doubler le pare-feu local : « Pour aller plus loin »).
6. [`playbooks/supervision.yml`](fichiers/M19-E03/ansible/playbooks/supervision.yml) : garde-fou sur le groupe, groupe `mailpit` créé **avant** le certificat (la clé lui appartient), `certificats_acme` ([`host_vars/mon01/certificats.yml`](fichiers/M19-E03/ansible/inventories/lab/host_vars/mon01/certificats.yml) : `mon01…` et `smtp…`, `recharger: systemctl try-restart mailpit`), `pare_feu_local` ([`host_vars/mon01/pare_feu_local.yml`](fichiers/M19-E03/ansible/inventories/lab/host_vars/mon01/pare_feu_local.yml)), puis `mailpit`. Ordre et défi ACME : au **tout premier** passage, `mon01` n'a encore aucun filtrage local (le rôle `pare_feu_local` ne lui a jamais été appliqué) : le défi HTTP-01 de `ca01` sur le port 80 passe. Aux renouvellements, `cert-renewer@mailpit` n'utilise plus le port 80 (renouvellement par TLS mutuel avec le certificat lui-même, M06-E18). La règle locale `ca01 → 80` ne sert donc qu'à une **réémission** (certificat perdu ou révoqué) : garde-la, sinon la réémission échouera un jour sans raison apparente.

*C. Les flux.*

7. [`pare_feu.yml.extrait`](fichiers/M19-E03/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) : définition `MON01`, règle `K8S_CP`, `K8S_TRAV` → `MON01` TCP 25 (pour Argo CD au M20 et Alertmanager au M21 ; posée maintenant pour que la messagerie soit complète). `git01` → `mon01:25` reste dans le VLAN 20 : le paquet ne passe **jamais** par une passerelle (même sous-réseau, résolution ARP directe) ; il est filtré par le pare-feu **local** de `mon01`. MGMT → 8025 est déjà couvert par la règle « bastion vers tout le lab ».
8. [`matrice-flux.md.extrait`](fichiers/M19-E03/medisphere/docs/socle/matrice-flux.md.extrait).

*D. Tester Mailpit au niveau du protocole.*

9. ```
   admin@adm01:~$ swaks --server smtp.par1.medisphere.internal:25 --tls --tls-ca-path /usr/local/share/ca-certificates/medisphere-root-ca.crt \
                    --from plateforme@medisphere.internal --to astreinte@medisphere.internal --header "Subject: M19-E03 essai swaks"
   === Trying smtp.par1.medisphere.internal:25...
   === Connected to smtp.par1.medisphere.internal.
   <-  220 mon01 Mailpit ESMTP Service ready
    -> EHLO adm01.par1.medisphere.internal
   <-  250-mon01 greets adm01.par1.medisphere.internal
   <-  250-…
   <-  250 STARTTLS
    -> STARTTLS
   <-  220 2.0.0 Ready to start TLS
   === TLS started with cipher TLS1.3:TLS_AES_128_GCM_SHA256:128
   === TLS peer DN="/CN=mon01.par1.medisphere.internal"
    ~> EHLO adm01.par1.medisphere.internal
   …
    ~> MAIL FROM:<plateforme@medisphere.internal>
   <~  250 2.1.0 Ok
   …
   <~  250 2.0.0 Ok: queued as …
   ```
   La bascule est la commande `STARTTLS` (`220 Ready to start TLS`) : après elle, les flèches `~>` indiquent un dialogue chiffré. Sans `--tls` : `530 5.7.0 Must issue a STARTTLS command first` à la commande `MAIL FROM` (effet de `MP_SMTP_REQUIRE_STARTTLS`). Vers `@exemple.com` : **accepté** et rangé dans Mailpit comme le reste ; rien ne sort (pas de relais, pas de MX consulté). Le `openssl s_client` donne `Verify return code: 0 (ok)` et l'émetteur intermédiaire de step-ca.
10. ```
    admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/mailpit-checks.env && editor ~/.config/workbook/mailpit-checks.env
    admin@adm01:~$ . ~/.config/workbook/mailpit-checks.env
    admin@adm01:~$ curl -sf -K <(printf 'user = "%s:%s"\n' "$MAILPIT_USER" "$MAILPIT_PASSWORD") https://mon01.par1.medisphere.internal:8025/api/v1/info | jq '{Version, Messages}'
    admin@adm01:~$ curl -sf -K <(printf 'user = "%s:%s"\n' "$MAILPIT_USER" "$MAILPIT_PASSWORD") \
        'https://mon01.par1.medisphere.internal:8025/api/v1/search?query=subject:"M19-E03"' | jq '.messages_count, [.messages[].Subject]'
    ```
    Oui : **Mailpit n'a pas de rôles**, le compte `wb-checks` peut appeler `DELETE /api/v1/messages`. Conséquence et compensations écrites dans [`docs/socle/messagerie.md`](fichiers/M19-E03/medisphere/docs/socle/messagerie.md) : mot de passe distinct, fichier 600 sur `adm01`, accès réseau limité à MGMT et au VPN, et les vérifications du workbook ne font que des `GET`.

*E. GitLab envoie ses courriels.*

11. Rôle [`gitlab_hote`](fichiers/M19-E03/ansible/roles/gitlab_hote/) étendu : `tasks/fragments.yml` (autorités dans `/etc/gitlab/trusted-certs/`, dossier `/etc/gitlab/medisphere.d/` en 700, fragments en 600, sauvegarde unique `gitlab.rb.avant-fragments`, une ligne `from_file` par fragment **à la fin** de `gitlab.rb`), `handlers/main.yml` (`gitlab-ctl reconfigure`), `meta/argument_specs.yml`. Fragment : [`host_vars/git01/gitlab_hote.yml`](fichiers/M19-E03/ansible/inventories/lab/host_vars/git01/gitlab_hote.yml) (STARTTLS, `smtp_openssl_verify_mode = 'peer'`, `smtp_ca_file` = la racine dans `trusted-certs`, pas d'authentification).
    ```
    admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --limit git01 --tags gitlab_hote --check --diff
    admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --limit git01 --tags gitlab_hote
    …
    RUNNING HANDLER [gitlab_hote : Reconfigurer GitLab] ***
    changed: [git01]
    ```
    (Étiquette et playbook : ceux qui appliquent `gitlab_hote` chez toi depuis le M04.) Ce que GitLab a retenu :
    ```
    root@git01:~# grep -E 'address|port|starttls|verify' /var/opt/gitlab/gitlab-rails/etc/smtp_settings.rb
    ```
12. ```
    root@git01:~# gitlab-rails runner "Notify.test_email('plateforme@medisphere.internal', 'M19-E03 test GitLab', 'Envoi depuis git01').deliver_now"
    ```
    (Une dizaine de secondes : Rails démarre.) Dans Mailpit : expéditeur `GitLab MédiSphère <gitlab@medisphere.internal>`, en-tête `Received: from git01.par1.medisphere.internal … with ESMTPS` (le S dit que la session était chiffrée). Ensuite : *Profil → Courriels → Ajouter* `<MOI>@medisphere.internal`, le courriel de confirmation arrive dans Mailpit, lien à ouvrir depuis le poste d'administration ; *Profil → Notifications* : « Failed pipeline » sur `formation` (projet de E04).
13. Documentation : [`messagerie.md`](fichiers/M19-E03/medisphere/docs/socle/messagerie.md), [`registre-secrets.md.extrait`](fichiers/M19-E03/medisphere/docs/socle/registre-secrets.md.extrait) ; `mon01` ajouté à la fiche des hôtes du socle (`docs/socle/inventaire.md` ou équivalent) et à la supervision du socle de `ms-verif-*` si tu l'as étendue.

Le check vérifie la VM (configuration Proxmox, pool, étiquettes, démarrage), le DNS (A, PTR, CNAME), la sauvegarde PBS, le service sur `mon01` (utilisateur, `NoNewPrivileges`, capacité unique, empreinte du binaire), les ports 25 et 8025 depuis `adm01`, le certificat (émetteur MédiSphère, nom `smtp…`, vérification), le refus de l'API sans mot de passe, le message de test de GitLab dans Mailpit, la configuration SMTP retenue par GitLab, et le code sur `main`.

**Explications**

- **Un nom de service, pas un nom d'hôte.** Tous les clients écrivent `smtp.par1.medisphere.internal`. Le jour où la messagerie change de machine (ou devient un vrai relais de l'entreprise), on change un CNAME et on réémet un certificat ; aucun client ne bouge. Le certificat porte les deux noms parce que l'interface est aussi atteinte par `mon01…`.
- **STARTTLS obligatoire et vérifié.** Le port 25 commence en clair puis bascule en TLS ; un client qui ne vérifie pas le certificat peut être détourné par un intermédiaire qui supprime la ligne `STARTTLS` de l'annonce (attaque par rétrogradation). D'où `MP_SMTP_REQUIRE_STARTTLS` côté serveur (rien ne passe en clair) **et** `openssl_verify_mode = 'peer'` côté GitLab (pas de faux serveur).
- **Un fragment plutôt que `gitlab.rb` en gabarit.** `gitlab.rb` contient des réglages posés à la main depuis le M01 (et `gitlab-secrets.json` à côté) ; le passer d'un coup en gabarit Ansible risquerait d'en perdre. `from_file` ajoute un fichier géré sans toucher au reste ; ce qui suit dans `gitlab.rb` l'emporterait, d'où les lignes ajoutées **à la fin**.
- **Pourquoi le port 25 et pas 587 ou 1025.** 25 est le port de transfert SMTP que tous les outils supposent par défaut (Alertmanager, Argo CD) ; 587 (soumission) implique une authentification que Mailpit n'a pas besoin d'imposer ; 1025 (défaut de Mailpit) obligerait à le rappeler partout.

**Alternatives**

- **Postfix** en relais de lab qui livre dans une boîte locale (Dovecot) : plus « réel », mais deux services à durcir, pas d'interface de lecture ni d'API simple pour les vérifications.
- **Mailpit dans le cluster** (chart communautaire) : la messagerie dépendrait de `k8s-par1`, alors qu'elle doit justement prévenir quand le cluster va mal (M21 : le Prometheus « témoin » de `mon01` alerte par courriel quand la supervision du cluster est en panne).
- **MailHog** : abandonné par son projet ; Mailpit est son successeur de fait.
- **Configurer GitLab à la main** dans `gitlab.rb` (M01) : acceptable, mais non reproductible ; le fragment géré se rejoue à l'identique après une restauration de `git01`.

**Pièges classiques**

- Laisser Mailpit sur ses défauts : interface sans mot de passe sur toutes les adresses, SMTP en clair sur 1025.
- `User=mailpit` sans `AmbientCapabilities` : `listen tcp 0.0.0.0:25: bind: permission denied`. Avec la capacité mais `NoNewPrivileges` et un binaire en `setcap` : ça marche aussi, mais la capacité suit le **fichier** (et disparaît à la mise à jour du binaire) au lieu du **service**.
- Clé TLS lisible par `root` seul : Mailpit (utilisateur `mailpit`) ne démarre pas (`open …key: permission denied`). Le rôle `certificats_acme` pose la clé en `0640` avec le groupe `mailpit` : le groupe doit exister **avant** l'émission.
- `smtp_openssl_verify_mode = 'none'` « parce que ça marche » : on chiffre vers n'importe qui. Le vrai correctif est la racine dans `/etc/gitlab/trusted-certs/` (puis `reconfigure`, qui la lie dans le magasin de certificats embarqué).
- `smtp_tls = true` avec le port 25 : c'est le TLS **implicite** (port 465) ; la poignée de main échoue (`wrong version number`). STARTTLS = `smtp_enable_starttls_auto`.
- Chercher la règle `git01 → mon01:25` sur la bordure et ne pas comprendre pourquoi elle ne « marche » pas : ce flux ne traverse pas la bordure.
- Un `Notify.test_email(…)` qui « ne fait rien » : il est mis en file (Sidekiq) si on oublie `.deliver_now` ; regarder `gitlab-ctl tail sidekiq` et la file `mailers`.

**En production chez MédiSphère**

Une vraie messagerie d'entreprise (relais authentifié, SPF/DKIM/DMARC du domaine, journal de remise) ; Mailpit resterait l'outil des environnements de **test** (MédiNotif en recette au M27, pour ne jamais envoyer un vrai courriel à un patient depuis la recette). `mon01` serait doublé (supervision « témoin » sur deux sites, F5).

---

### M19-E04 — Un runner GitLab dans Kubernetes

**Solution**

*A. Les images de GitLab dans Harbor.*

1. [`caches.tf.extrait`](fichiers/M19-E04/infra/registre/caches.tf.extrait) : une entrée `gitlab` dans `local.caches` (type `docker-registry`, `https://registry.gitlab.com`, 10 Gio). Plan : `harbor_registry.amont["gitlab"]` et `harbor_project.cache["gitlab"]`, 2 à ajouter.
   ```
   admin@adm01:~$ skopeo inspect --format '{{.Digest}}' docker://registry.par1.medisphere.internal/gitlab/gitlab-org/gitlab-runner:alpine-v19.4.0
   sha256:a4838319e55b510c05b36d701d06362b9197458558c7b0d3d63f2c7588c7cd2f
   admin@adm01:~$ skopeo inspect --format '{{.Digest}}' docker://registry.par1.medisphere.internal/gitlab/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.4.0
   sha256:13188cca15a2d44fc621d42da4efb42b81c9527e072d07aab29468dea15af831
   ```
   Le chart construit l'image du gestionnaire à partir de `image.registry` (défaut `registry.gitlab.com`), et le runner calcule celle du *helper* à partir de sa propre version (`registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.4.0`) : sans réglage, les nœuds tireraient directement sur `registry.gitlab.com` (les miroirs `hosts.toml` du M14-E19 ne couvrent que `docker.io`, `quay.io`, `ghcr.io` et `registry.k8s.io`). Dans `ci-jobs`, la VAP `medisphere-images` **refuserait** le pod (image hors Harbor) ; dans `gitlab-runner`, aucune VAP (pas d'étiquette d'équipe) : le tirage passerait, en contournant Harbor. D'où les deux réglages explicites.

*B. Le runner et son jeton.*

2. Jeton personnel dédié (*Profil → Jetons d'accès*, portées `create_runner` et `admin_mode`, expiration le lendemain), rangé dans `~/.config/workbook/gitlab-create-runner.token` (600). Création et rangement en une commande, sans fichier en clair ni affichage :
   ```
   admin@adm01:~$ mkdir -p ~/m19/e04 && cd ~/src/ansible
   admin@adm01:~/src/ansible$ curl -sf --request POST "https://git01.par1.medisphere.internal/api/v4/user/runners" \
        -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-create-runner.token)") \
        --data runner_type=instance_type --data description=k8s-par1 --data tag_list=k8s,kubernetes \
        --data run_untagged=false --data locked=false --data access_level=not_protected --data maximum_timeout=3600 \
      | tee >(jq -r .id > ~/m19/e04/runner-id) \
      | jq -r '"gitlab_runner_jeton: \"" + .token + "\""' \
      | uv run ansible-vault encrypt --vault-id critique@outils/vault-pass-client.sh --encrypt-vault-id critique \
          --output ../k8s/secrets/gitlab-runner.yml -
   Encryption successful
   admin@adm01:~/src/ansible$ cat ~/m19/e04/runner-id; head -1 ../k8s/secrets/gitlab-runner.yml
   7
   $ANSIBLE_VAULT;1.2;AES256;critique
   ```
   (`ansible-vault encrypt -` lit le texte en clair sur l'entrée standard.) L'identifiant du runner n'est pas secret ; le jeton n'a existé qu'en mémoire. Puis : révocation du jeton personnel (*Profil → Jetons d'accès → Révoquer*) et suppression du fichier. Avant le premier contact, le runner apparaît « Never contacted » / jamais connecté, avec ses étiquettes et sa description : ces propriétés appartiennent à GitLab. Tu ajouteras à `secrets/gitlab-runner.yml` les clés du cache en E07 (`uv run ansible-vault edit`).
3. [`outils/secrets-k8s.sh`](fichiers/M19-E04/k8s/outils/secrets-k8s.sh) et sa table [`outils/secrets-k8s.conf`](fichiers/M19-E04/k8s/outils/secrets-k8s.conf) ; [`secrets/gitlab-runner.yml.exemple`](fichiers/M19-E04/k8s/secrets/gitlab-runner.yml.exemple). Une ligne par Secret, sources `vault:`, `fichier:` (la racine, publique) ou `vide:`. Le script refuse un fichier Vault qui n'est pas sous l'identité `critique`, déchiffre en mémoire, passe chaque valeur par un fichier temporaire 600 effacé aussitôt (ni `ps`, ni annotation `last-applied-configuration` : *server-side apply*), et ne compare que des empreintes en mode `verifier`.
   ```
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer gitlab-runner
   [OK] gitlab-runner/gitlab-runner à jour (runner-token runner-registration-token)
   [OK] gitlab-runner/gitlab-runner-certs à jour (git01.par1.medisphere.internal.crt)
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh verifier gitlab-runner
   [OK] gitlab-runner/gitlab-runner : runner-token identique à sa source
   …
   ```

*C. La release.*

4. Lecture des valeurs du chart : `runners.secret` (Secret avec `runner-token` et `runner-registration-token`, les deux clés étant projetées dans le pod : la seconde doit **exister**, même vide), `runners.jobNamespace` (espace des jobs **et** du Role), `rbac.rules` (vide = `*` sur le groupe cœur), `certsSecretName` (monté dans `/home/gitlab-runner/.gitlab-runner/certs/`), `runners.config` (TOML passé à `tpl`, gabarit donné à `gitlab-runner register --template-config`), `unregisterRunners`.
5. [`releases/50-ci.yaml.gotmpl`](fichiers/M19-E04/k8s/releases/50-ci.yaml.gotmpl), [`_communs.yaml.extrait`](fichiers/M19-E04/k8s/releases/_communs.yaml.extrait) (dépôt `gitlab`), [`composants/gitlab-runner/values.yaml`](fichiers/M19-E04/k8s/composants/gitlab-runner/values.yaml). Rendu :
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-runner template | yq 'select(.kind == "Role") | .metadata.namespace, .rules'
   ci-jobs
   - apiGroups: [""]
     resources: ["pods"]
     verbs: ["create","delete","get","list","watch"]
   …
   ```
6. Bordure : [`pare_feu.yml.extrait`](fichiers/M19-E04/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) (`K8S_TRAV` → `GIT01` TCP 443), une passerelle à la fois. Puis :
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-runner diff
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-runner apply
   admin@adm01:~$ kubectl --context k8s-par1 -n gitlab-runner logs deploy/gitlab-runner | head -20
   Registration attempt 1 of 30
   Runtime platform    arch=amd64 os=linux pid=… revision=… version=19.4.0
   …
   Updated the configuration file  …
   Runner registered successfully. Feel free to start it, …
   …
   Configuration loaded                                builds=0 max_builds=6
   Checking for jobs... nothing                        runner=…
   ```
   (`register` avec un jeton `glrt-` n'enregistre rien côté GitLab : il **vérifie** le jeton et écrit `config.toml`.) Dans *Admin → CI/CD → Runners* : `k8s-par1` en ligne, **1 gestionnaire** (*runner manager*), identifié par son `system_id`, avec l'adresse IP du nœud et la version 19.4.0. Chaque nouveau pod du gestionnaire (redémarrage, réplica) apparaît comme un **nouveau** gestionnaire ; les anciens disparaissent de la liste après un délai d'inactivité.

*D. Premier pipeline.*

7. Projet `formation/ci-labo` (*New project*, groupe `formation`, branche `main` protégée : *Allowed to push: No one*, *Allowed to merge: Maintainers*), contenu poussé depuis [`ressources/E04-ci-labo/`](../ressources/E04-ci-labo/). [`.gitlab-ci.yml`](fichiers/M19-E04/ci-labo/.gitlab-ci.yml) : `default: tags: [k8s]`, job `bonjour`.
8. ```
   admin@adm01:~$ kubectl --context k8s-par1 -n ci-jobs get pods -w
   NAME                                                     READY   STATUS     RESTARTS   AGE
   runner-t3abc12xy-project-42-concurrent-0-1kx8m2pq        0/2     Pending    0          0s
   runner-t3abc12xy-project-42-concurrent-0-1kx8m2pq        0/2     Init:0/1   0          1s
   runner-t3abc12xy-project-42-concurrent-0-1kx8m2pq        2/2     Running    0          6s
   runner-t3abc12xy-project-42-concurrent-0-1kx8m2pq        2/2     Terminating 0         19s
   ```
   Journal du job : les lignes `Running with gitlab-runner…`, `Preparing the "kubernetes" executor`, `Using Kubernetes namespace: ci-jobs`, `Waiting for pod … to be running`, `Getting source from Git repository`, `Executing "step_script"…`, `Cleaning up…`, `Job succeeded` viennent du runner ; entre `step_script` et `Cleaning up`, les lignes `$ …` (commande) et leur sortie viennent de ton script.
9. Le job sans étiquette reste `pending` (« This job is stuck… »). Correction retenue : `default: tags: [k8s]` (on ne rend pas un runner « attrape-tout », réponse 14 de E01).
10. [`registre-secrets.md.extrait`](fichiers/M19-E04/medisphere/docs/socle/registre-secrets.md.extrait) (jeton `glrt-` : où, qui le lit — les administrateurs du cluster et le gestionnaire —, rotation par `POST /runners/:id/reset_authentication_token` puis Vault, `secrets-k8s.sh`, redémarrage du gestionnaire) et [`matrice-flux.md.extrait`](fichiers/M19-E04/medisphere/docs/socle/matrice-flux.md.extrait).

Le check vérifie le cache Harbor, le runner dans GitLab (en ligne, non en pause, étiquettes, `run_untagged`, au moins un gestionnaire), le Deployment prêt et son image Harbor, la configuration rendue (espace, compte de service, *helper* et image par Harbor, jeton absent du ConfigMap), le Role dans `ci-jobs`, le dernier pipeline de `ci-labo` et le runner qui a exécuté ses jobs, le flux vers `git01:443` depuis chaque travailleur, et le code sur `main` (dont l'en-tête Vault de `secrets/gitlab-runner.yml`).

**Explications**

- **Le jeton est la seule chose qui donne des jobs.** Quiconque le possède peut faire tourner un gestionnaire qui reçoit les jobs `k8s` de toute l'instance, avec leurs variables (protégées comprises, pour les références protégées) : c'est l'équivalent d'un mot de passe d'administration de la CI. Vault `critique`, Secret dans un espace où seuls les administrateurs lisent les Secrets, jamais dans des valeurs Helm (qui finissent dans un Secret de release Helm, lisible par quiconque lit l'historique Helm, et souvent dans Git).
- **Le RBAC du gestionnaire est dans l'espace des jobs.** Le gestionnaire crée des pods et des Secrets **dans `ci-jobs`** ; il n'a rien à faire dans `gitlab-runner` (il lit sa configuration par des volumes). Une liste explicite de droits évite le `*` sur le groupe cœur que donnerait une liste vide (qui inclurait la lecture de **tous** les Secrets de `ci-jobs`… y compris, plus tard, le certificat client de buildkitd).
- **`concurrent` et quota.** `concurrent = 6` borne le nombre de jobs **acceptés** par le gestionnaire ; le quota de `ci-jobs` borne ce que Kubernetes **admet**. Si le quota est plus petit que ce que `concurrent` laisse entrer, les jobs acceptés attendent en `Pending` jusqu'à `poll_timeout` puis échouent (panne du M19-E35). Les deux se règlent ensemble (M19-E27).

**Alternatives**

- **Jeton d'enregistrement** (`runnerRegistrationToken`) : déconseillé depuis GitLab 16, désactivable en 19 ; ne pas l'utiliser.
- **Interface au lieu de l'API** pour créer le runner : équivalent ; l'API se rejoue et se documente.
- **Opérateur GitLab Runner** (CRD `Runner`, surtout pour OpenShift) : un objet de plus à maintenir ; le chart suffit.
- **Runner de groupe** (`group_type`) plutôt que d'instance : limiterait `k8s-par1` à un groupe. Un runner d'instance étiqueté convient ici ; le runner protégé (E24) restreindra par la protection des références, pas par la portée.

**Pièges classiques**

- `runners.jobNamespace` oublié : les pods de job sont créés dans `gitlab-runner` (le Role aussi), la Pod Security `restricted` les refuse et les quotas de `ci-jobs` ne servent à rien.
- `rbac.rules: []` « pour commencer » : droits `*` sur tout le groupe cœur de `ci-jobs`.
- Un Secret sans la clé `runner-registration-token` : le volume projeté ne se monte pas (`couldn't find key runner-registration-token`), le pod du gestionnaire reste `ContainerCreating`.
- Le fichier de `certsSecretName` mal nommé (`ca.crt`) : le gestionnaire n'y cherche que `<hôte de GitLab>.crt` → `x509: certificate signed by unknown authority` à l'enregistrement.
- Dans un `.gitlab-ci.yml`, `- echo "pod : $HOSTNAME"` : un « deux-points suivi d'une espace » dans un élément non entre guillemets fait de l'élément une **table** YAML ; GitLab répond « script config should be a string or a nested array of strings ». Mettre la ligne entière entre apostrophes.
- Oublier `unregisterRunners` ou supprimer la release sans y penser : avec un jeton `glrt-`, seul le **gestionnaire** est supprimé, pas le runner ; réinstaller avec le même jeton suffit.
- Un `uninstall` + `install` pour « relancer » : inutile ; un `kubectl rollout restart` suffit, et le délai de grâce de 3600 s laisse finir les jobs en cours.

**En production chez MédiSphère**

Deux réplicas du gestionnaire et un PDB (M19-E27), la supervision de `gitlab_runner_jobs`, `gitlab_runner_errors_total` et du temps d'attente (port de métriques 9252, M21), une rotation du jeton documentée et testée, et des runners par niveau de confiance (protégé, E24).

---

### M19-E05 — Anatomie d'un job dans Kubernetes

**Solution**

1. [`.gitlab-ci.yml`](fichiers/M19-E05/ci-labo/.gitlab-ci.yml) : le job `anatomie` (service Valkey de Harbor avec l'alias `valkey`, `KUBERNETES_CPU_REQUEST`, `KUBERNETES_MEMORY_REQUEST`, `KUBERNETES_MEMORY_LIMIT`, `anatomie.txt` en artefact d'une semaine). La conversation avec Valkey se fait dans un **sous-shell** : une redirection `exec 3<>/dev/tcp/…` qui échoue ne doit pas interrompre le script.
2. Dissection (extraits représentatifs de `kubectl get pod -o yaml`) :
   ```yaml
   metadata:
     name: runner-t3abc12xy-project-42-concurrent-0-1kx8m2pq
     labels:
       medisphere.internal/ci: job
       job.runner.gitlab.com/pod: runner-t3abc12xy-project-42-concurrent-0
       project.runner.gitlab.com/id: "42"
       project.runner.gitlab.com/name: ci-labo
       project.runner.gitlab.com/namespace: formation
     annotations:
       job.runner.gitlab.com/id: "1873"
       job.runner.gitlab.com/url: https://git01.par1.medisphere.internal/formation/ci-labo/-/jobs/1873
       job.runner.gitlab.com/name: anatomie
       job.runner.gitlab.com/ref: main
   spec:
     serviceAccountName: ci-job
     automountServiceAccountToken: false
     initContainers:
       - name: init-permissions
         image: registry.par1.medisphere.internal/gitlab/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v19.4.0@sha256:13188c…
         command: [sh, -c, "touch /logs-42-1873/output.log && (chmod 777 /logs-42-1873/output.log || exit 0)"]
     containers:
       - name: build          # image du job ; command = un shell qui attend les étapes
         resources: {requests: {cpu: 500m, memory: 1Gi}, limits: {cpu: "2", memory: 1Gi}}
       - name: helper         # gitlab-runner-helper ; 100m/128Mi, 1/512Mi
       - name: valkey         # le service, sous son alias ; 100m/256Mi, 1/1Gi
     volumes: [repo (emptyDir), scripts (emptyDir), logs (emptyDir)]
   status:
     qosClass: Burstable
   ```
   `repo` (le dépôt cloné, `/builds/formation/ci-labo`), `scripts` (les étapes générées) et `logs` (le journal) sont montés dans `build` **et** `helper` : c'est par eux que les deux conteneurs se passent le travail. Le compte de service est `ci-job`, sans jeton monté. La classe QoS est *Burstable* (demandes < limites). Événements : `Scheduled`, `Pulling`/`Pulled` (ou `already present on machine`), `Created`, `Started` pour chaque conteneur.
3. *Attach* : le conteneur `build` démarre avec un **shell** qui attend (la commande du conteneur, posée par le runner, remplace le point d'entrée de l'image) ; le gestionnaire s'y **attache** (`pods/attach`) et lui envoie l'exécution des scripts qu'il a écrits dans `/scripts-…` ; la sortie est écrite dans `/logs-…/output.log`, relue par le `helper` et renvoyée à GitLab par le gestionnaire. `kubectl logs -c build` ne montre donc presque rien (pas le journal du job) ; `-c helper` montre surtout le travail du *helper* (clonage, artefacts). C'est pourquoi `init-permissions` rend le fichier de journal inscriptible par tous : `build` et `helper` n'ont pas forcément le même UID. Fichier de référence : [`docs/livraison/ci/anatomie-job.md`](fichiers/M19-E05/medisphere/docs/livraison/ci/anatomie-job.md).
4. Chronologie (journal téléchargé, mesures représentatives, images déjà présentes sur le nœud) : prise du job à `00:00`, pod `Running` à `00:07`, clonage terminé à `00:09`, script de `00:09` à `02:11` (dont `sleep 120`), artefacts téléversés à `02:12`, pod supprimé à `02:14`. Au premier passage sur un nœud (images à tirer par Harbor), compte 30 à 90 s de plus. Le pod ne survit que quelques secondes au job : pour un pod qui ne démarre pas, il faut observer **pendant** l'attente.
5. `KUBERNETES_MEMORY_LIMIT: "8Gi"` : le job échoue dès la préparation de l'exécuteur, avec un message disant que la valeur demandée dépasse le maximum autorisé par le runner (4 Gi) ; aucun pod n'est créé. Quota épuisé : le pod est **refusé à la création** (« exceeded quota » dans le journal du job) et le runner réessaie, ou le pod reste `Pending` faute de place sur un nœud (`FailedScheduling`) ; au bout de `poll_timeout` (600 s), le job échoue (« timed out waiting for pod to start »). M19-E35 en fait des pannes.
6. [`anatomie-job.md`](fichiers/M19-E05/medisphere/docs/livraison/ci/anatomie-job.md) : schéma, conteneurs, chronologie, *attach*, « où regarder », limites.

Le check cherche, dans les jobs réussis de `ci-labo`, le plus récent nommé `anatomie` (même s'il n'est plus dans le dernier pipeline, E06 le rendant manuel), vérifie qu'il a été exécuté par `k8s-par1`, qu'il a une archive d'artefacts avec une date d'expiration à 8 jours au plus, que son journal montre la limite de 1 Gi (`1073741824`) et l'absence de jeton de compte de service, puis la page de documentation sur `main`.

**Explications**

- **Un pod, pas un conteneur.** Le *helper* a besoin de Git, d'un client S3 et de l'API de GitLab ; l'image du job n'a pas à les contenir. Les mettre dans deux conteneurs du même pod, avec des volumes partagés, permet n'importe quelle image de job (même sans `git`) et garde les jetons du *helper* hors du script… en partie : les deux conteneurs voient les mêmes variables du job.
- **Les services sont dans le pod.** Ils partagent l'espace de noms réseau : `localhost:6379` joint Valkey. Le runner crée aussi un Service Kubernetes à l'alias quand il le faut. Conséquence : un service consomme le quota du job, et deux jobs n'ont jamais de conflit de port (chacun son pod).
- **Les surcharges sont bornées par le runner.** Un développeur peut demander 1 Gi pour un job gourmand sans ticket, mais pas 8 Gi : c'est l'administrateur du runner qui fixe les maximums, et le LimitRange qui les reborne.

**Alternatives**

- Ancienne stratégie d'exécution (`FF_USE_LEGACY_KUBERNETES_EXECUTION_STRATEGY=true`, un `exec` par étape) : plus sensible aux coupures de connexion avec l'API ; ne la réactiver que pour diagnostiquer.
- `FF_KUBERNETES_HONOR_ENTRYPOINT` : respecte le point d'entrée de l'image du job (utile pour certaines images qui préparent leur environnement au démarrage).

**Pièges classiques**

- Chercher le journal du job avec `kubectl logs` : il est dans GitLab.
- Croire qu'un `sleep` dans `after_script` garde le pod : `after_script` a son propre délai (5 minutes par défaut) et le pod part ensuite.
- Écrire des variables dans un artefact « pour déboguer » : `env > fichier` met `CI_JOB_TOKEN`, `CI_REGISTRY_PASSWORD` et toutes les variables protégées dans un fichier téléchargeable. D'où le filtre du job `anatomie`.
- Un service sans alias dont l'image a un nom avec des `/` : il est joignable par `localhost`, mais son nom DNS est dérivé (et peu lisible) ; donner un alias.

**En production chez MédiSphère**

Cette page devient le chapitre « CI » de la formation d'astreinte (Nadia) et le point de départ du runbook RB-190 (M19-E22). Les événements de `ci-jobs` sont collectés par Alloy au M22 : on pourra relire les événements d'un pod de job disparu.

---

### M19-E06 — Pipelines : stages, `needs`, `rules` et `workflow`

**Solution**

1. Version en stages : [`.gitlab-ci.yml.stages`](fichiers/M19-E06/ci-labo/.gitlab-ci.yml.stages). Poussée sur une branche avec une MR ouverte, sans `workflow` : **un** pipeline de branche (`push`). Pas de pipeline de MR : sans `rules` ni `workflow`, GitLab ne crée que des pipelines de branche ; ajouter une seule règle de MR à un job ferait apparaître le doublon. Mesures représentatives :
   ```
   ruff     lint    10:02:05  10:02:31
   docs     lint    10:02:05  10:02:14
   tests    test    10:02:33  10:03:20
   paquet   build   10:03:22  10:03:49
   resume   rapport 10:03:51  10:03:58
   ```
   (≈ 1 min 55.)
2. Graphe : [`.gitlab-ci.yml`](fichiers/M19-E06/ci-labo/.gitlab-ci.yml). `tests` et `ruff` ont `needs: []` (ils démarrent ensemble à la création du pipeline), `paquet` a `needs: [tests]`, `resume` n'a pas de `needs` (il attend la fin de tous les stages précédents) et `when: always`. Mesures : `tests` démarre à 10:12:05 avec `ruff`, `paquet` à 10:12:50 sans attendre `docs` : ≈ 1 min 20 (− 30 %). La vue « Job dependencies » montre les flèches réelles ; la vue par stages, des colonnes qui ne disent plus l'ordre.
3. `rules` : `.regles-code` (planification, lancement manuel, étiquette : tout ; sinon `changes` sur `src/**`, `tests/**`, `pyproject.toml`, `uv.lock`) pour `ruff`, `tests`, `paquet` ; `docs` sur `docs/**`. Quatre cas dans une MR :

   | Changement | Jobs du pipeline de MR |
   |---|---|
   | `docs/` seul | `docs`, `resume` |
   | `src/` seul | `ruff`, `tests`, `paquet`, `resume` |
   | les deux | tous |
   | `README.md` seul | `resume` seul |

   `README.md` n'est dans aucune liste `changes` : aucun job utile ; `resume` n'a pas de `rules`, il est toujours là. C'est voulu ici (un pipeline existe et réussit, ce qu'exige le réglage « Pipelines must succeed » au M19-E13) ; on pourrait aussi ne créer aucun pipeline (`workflow:rules` avec `changes`), mais alors la MR attendrait un pipeline qui ne viendra jamais.
4. `workflow:rules` : MR ; planification et lancement manuel ; `when: never` pour une poussée sur une branche qui a une MR ouverte ; `main` ; étiquettes. Rien d'autre.

   | Action | Pipelines créés |
   |---|---|
   | poussée sur `essai` sans MR | **aucun** (aucune règle ne s'applique : branche ni MR, ni `main`) |
   | ouverture de la MR | 1, `merge_request_event` |
   | nouvelle poussée sur `essai` | 1, `merge_request_event` (le pipeline de branche est refusé par la règle 3) |

   Si l'équipe veut aussi des pipelines de branche **avant** l'ouverture de la MR, on ajoute `- if: $CI_COMMIT_BRANCH` en dernière règle : la règle 3 continue d'empêcher le doublon une fois la MR ouverte (exemple de la documentation, « Switch between branch pipelines and merge request pipelines »).
5. `default: interruptible: true`, sauf `resume`… qui l'est aussi (il ne modifie rien) ; les jobs de déploiement de E07 seront `interruptible: false`. `workflow:auto_cancel:on_new_commit: interruptible` : à chaque nouveau commit sur la branche de la MR, les jobs interruptibles des pipelines précédents de la même référence sont **annulés** (statut `canceled`) ; seul le dernier pipeline va au bout. Avec la valeur par défaut (`conservative`), un pipeline dont un job non interruptible a déjà commencé n'est pas annulé.
6. Sur `main`, `changes` compare le commit poussé au commit **précédent de la branche** (`CI_COMMIT_BEFORE_SHA`) ; après une fusion, c'est l'ensemble de la MR. Pour un pipeline planifié ou lancé à la main, `changes` vaut **toujours vrai** : tous les jobs à `changes` sont ajoutés. La règle explicite de `.regles-code` ne change donc rien au comportement, mais elle le rend **lisible** (et protège d'un changement de comportement de GitLab).
7. Tableau des gains dans `~/m19/e06/` (repris en E23).

Le check lit le `.gitlab-ci.yml` de `main` (`workflow:rules`, `auto_cancel`, au moins un `needs`, des `rules` avec `changes` et une condition sur `CI_PIPELINE_SOURCE`), vérifie que le dernier pipeline de `main` a réussi et qu'un job y a démarré avant la fin d'un job d'un stage antérieur (le graphe est effectif), puis cherche des doublons branche + MR parmi les 30 derniers pipelines (même commit, une source `push` sur une branche autre que `main` et une source `merge_request_event`).

**Explications**

- **Deux décisions distinctes.** `workflow:rules` répond à « faut-il un pipeline pour cet événement ? », les `rules` des jobs à « que doit faire ce pipeline ? ». Mettre la logique « pas de doublon » dans les jobs (chaque job avec sa règle `merge_request_event`) multiplie les erreurs ; la mettre dans `workflow` la règle une fois.
- **Le graphe avant le parallélisme.** On croit accélérer en ajoutant des runners ; souvent, un pipeline lent attend surtout des stages. `needs` supprime ces attentes sans un CPU de plus (E23 le mesure sur MédiAgenda).
- **Un job toujours présent.** Un pipeline sans aucun job n'est pas créé (« no stages / jobs for this pipeline ») ; selon les réglages du projet, une MR peut alors rester sans pipeline. `resume` garantit au moins un job.

**Alternatives**

- `only`/`except` : ancienne syntaxe, toujours acceptée, moins expressive (pas de `when` par condition, pas de variables par règle) ; on ne les mélange pas avec `rules`.
- `rules:changes:compare_to` : comparer à une référence fixe (`refs/heads/main`) même dans un pipeline de branche ; utile pour des pipelines de branche sans MR.
- Pipelines enfants (`trigger:include`) par sous-dossier dans un dépôt « mono-repo » : chaque partie a ses `rules` (M19-E12).

**Pièges classiques**

- `- if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS` placée **après** `- if: $CI_COMMIT_BRANCH` : la première règle qui s'applique gagne, le doublon revient.
- Bloquer aussi les lancements manuels sur une branche avec MR (règle 3 avant la règle 2) : le bouton « Run pipeline » ne crée plus rien, sans message clair.
- `needs` vers un job absent du pipeline (ses `rules` ne l'ont pas ajouté) : GitLab refuse de **créer** le pipeline (« job needs … but … was not added to the pipeline »). Les deux jobs doivent avoir les mêmes `rules`, ou la dépendance doit être `optional: true` (E07).
- `when: always` sur un job qui a `needs` vers un job échoué : il ne démarre pas (le graphe l'emporte) ; `resume` n'a pas de `needs` pour cette raison.
- `interruptible: true` sur un job de déploiement : un commit poussé pendant le déploiement l'annule à mi-chemin.

**En production chez MédiSphère**

Ces règles deviennent le composant `qualite` (palier 2, E10) : chaque projet hérite du même `workflow` et des mêmes conventions, sans les recopier. Le réglage de projet « Auto-cancel redundant pipelines » reste activé partout.

---

### M19-E07 — Variables, artefacts, caches et environnements

**Solution**

*A. Les variables.*

1. Priorité, avec `NIVEAU` défini dans le fichier (`fichier (global)`), dans le job `variables-demo` (`job`) et dans les réglages du projet (`projet`) : un lancement manuel sans valeur affiche `NIVEAU vaut : projet` (la variable de projet bat celle du job) ; avec `NIVEAU=manuel` dans le formulaire « Run pipeline », `manuel` (les variables du pipeline battent tout le reste, hors politiques). Variable de **type fichier** `LABO_CONFIG` : la variable contient un **chemin** (`/builds/formation/ci-labo.tmp/LABO_CONFIG`), le fichier contient la valeur. `LABO_CHEMIN = $CI_PROJECT_DIR/labo` : avec « Expand variable reference » cochée, GitLab la développe (`/builds/formation/ci-labo/labo`) ; décochée (`raw: true` dans l'API), le job reçoit le texte littéral `$CI_PROJECT_DIR/labo` (et le shell ne le redéveloppe pas : le contenu d'une variable n'est pas réinterprété). Pour un mot de passe qui contient `$`, un développement silencieux **tronque** la valeur : décocher.
2. `LABO_SECRET` (protégée, masquée) : absente du pipeline de MR (branche non protégée), présente sur `main`. `echo "$LABO_SECRET" | base64` affiche la valeur **en base 64, en clair** : le masquage ne remplace que la valeur exacte (et quelques encodages documentés selon la version) ; toute transformation y échappe. Conclusion : le masquage protège des fuites **accidentelles**, pas d'un script qui veut révéler un secret ; la vraie protection est que le secret n'existe que dans les pipelines protégés (et, mieux, qu'il soit **caché** : M19-E25). Après l'essai, efface le journal du job (*Erase job log*) et change la valeur de la variable.

*B. Artefacts.*

3. Job `version` : `VERSION=0.1.0-<sha court>` (ou `X.Y.Z` sur une étiquette `vX.Y.Z`) dans un rapport `dotenv`, `expire_in: 1 day` (il ne sert que dans le pipeline) ; `paquet` a `needs: [tests, version]` et nomme ses fichiers `dist/<VERSION>-…` ; `dist/` une semaine, `anatomie.txt` une semaine, rapport JUnit une semaine avec `artifacts:when: always` (le rapport d'un test **échoué** est celui qu'on veut lire). Fichier : [`.gitlab-ci.yml`](fichiers/M19-E07/ci-labo/.gitlab-ci.yml).
4. Avec le réglage de projet « Keep artifacts from most recent successful jobs » (actif par défaut), les artefacts du **dernier** pipeline réussi de chaque référence sont gardés même après `expire_in` ; ils ne sont supprimés qu'au pipeline réussi suivant. Bon à savoir avant de compter sur `expire_in` pour faire de la place.

*C. Le cache S3.*

5. [`seaweedfs.yml.extrait`](fichiers/M19-E07/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait) (identité `ci-cache` : `Read`, `Write`, `List` sur `ci-cache` ; compartiment sans versionnage) et [`vault.yml.extrait`](fichiers/M19-E07/ansible/inventories/lab/host_vars/s3-01/vault.yml.extrait) ; fichier local [`s3-ci-cache.env.exemple`](fichiers/M19-E07/adm01/s3-ci-cache.env.exemple). Contrôle :
   ```
   admin@adm01:~$ curl -sf --aws-sigv4 "aws:amz:us-east-1:s3" -K <(printf 'user = "%s:%s"\n' "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY") \
                    "https://s3-01.par1.medisphere.internal:8333/ci-cache?list-type=2" | head -c 300; echo
   <?xml version="1.0" encoding="UTF-8"?><ListBucketResult …><Name>ci-cache</Name><KeyCount>0</KeyCount>…
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --aws-sigv4 "aws:amz:us-east-1:s3" -K <(…) "https://s3-01.par1.medisphere.internal:8333/tofu-state?list-type=2"
   403
   ```
6. [`secrets/gitlab-runner.yml.exemple`](fichiers/M19-E07/k8s/secrets/gitlab-runner.yml.exemple) (`ci_cache_cle_acces`, `ci_cache_cle_secrete`), table [`secrets-k8s.conf`](fichiers/M19-E07/k8s/outils/secrets-k8s.conf) (ligne `ci-cache-s3`), ConfigMap [`espaces/ci-jobs/40-racine-ca.yaml`](fichiers/M19-E07/k8s/espaces/ci-jobs/40-racine-ca.yaml), valeurs [`composants/gitlab-runner/values.yaml`](fichiers/M19-E07/k8s/composants/gitlab-runner/values.yaml) : `runners.cache.secretName: ci-cache-s3`, `[runners.cache]` et `[runners.cache.s3]` (sans clé), `environment = ["SSL_CERT_DIR=/etc/ssl/certs:/etc/medisphere/ca"]`, `[[runners.kubernetes.volumes.config_map]]` `medisphere-racine` en `/etc/medisphere/ca`.
   ```
   admin@adm01:~/src/k8s$ uv --directory ~/src/ansible run ansible-vault edit ~/src/k8s/secrets/gitlab-runner.yml   # deux clés de plus
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer gitlab-runner && task appliquer
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=gitlab-runner diff && helmfile -e par1 -l composant=gitlab-runner apply
   ```
   Le ConfigMap change, le chart change l'empreinte de configuration du pod (annotation `checksum/…`) : le gestionnaire **redémarre**. Sans danger pour les jobs en cours : l'ancien pod reçoit `SIGQUIT`, ne prend plus de job, termine les siens dans la limite de `terminationGracePeriodSeconds` (3600 s), puis s'arrête ; le nouveau pod prend les jobs suivants.
   Pourquoi `SSL_CERT_DIR` et pas le chemin `/etc/gitlab-runner/certs/ca.crt` de la documentation de GitLab Runner : ce chemin est traité par le **script d'entrée** de l'image *helper* (`/entrypoint`) ; or l'exécuteur Kubernetes remplace le point d'entrée des conteneurs par sa propre commande (fonction `getCommandAndArgs` du code 19.4, sauf `FF_KUBERNETES_HONOR_ENTRYPOINT`). Le *helper* étant un programme Go, `SSL_CERT_DIR` ajoute aux autorités du système tous les fichiers des dossiers listés. ⚠️ À vérifier sur ton lab (point non testé) : si le cache échoue avec `x509: certificate signed by unknown authority`, regarde la commande du conteneur `helper` et cette variable.
7. Cache de `uv` (`UV_CACHE_DIR: $CI_PROJECT_DIR/.cache/uv`, clé `files: [uv.lock]` préfixée `uv`, `pull-push` pour `tests`, `pull` pour `ruff`, `uv cache prune --ci` à la fin de `tests`). Premier pipeline (journal de `tests`, représentatif) :
   ```
   Restoring cache
   Checking cache for uv-3f1c0a8e2b…d41-non_protected...
   WARNING: file does not exist
   Failed to extract cache
   …
   Saving cache for successful job
   Creating cache uv-3f1c0a8e2b…d41-non_protected...
   .cache/uv: found 412 matching artifact files and directories
   Uploading cache.zip to https://s3-01.par1.medisphere.internal:8333/ci-cache/k8s-par1/runner/t3abc12x/project/42/uv-3f1c…-non_protected
   Created cache
   ```
   Second pipeline :
   ```
   Checking cache for uv-3f1c0a8e2b…d41-non_protected...
   Downloading cache from https://s3-01.par1.medisphere.internal:8333/ci-cache/k8s-par1/runner/…  ETag="…"
   Successfully extracted cache
   ```
   `uv sync` passe de 9-10 s (téléchargement de pytest et de ses dépendances) à 1-2 s. Le suffixe `-non_protected`/`-protected` vient de GitLab : les caches des références protégées et non protégées sont **séparés** par défaut (une branche de stagiaire ne peut pas empoisonner le cache de `main`).
8. Une nouvelle dépendance dans `uv.lock` : la clé change (empreinte du dernier commit qui a modifié le fichier), un nouveau cache se construit ; l'ancien objet reste dans `ci-cache` : **le runner ne supprime jamais rien**. Ménage à prévoir : une durée de vie par chemin dans SeaweedFS (`fs.configure -locationPrefix=/buckets/ci-cache/ -ttl=…` dans `weed shell`, à vérifier sur ta version de SeaweedFS) ou une tâche planifiée qui supprime les objets de plus de N jours (M19-E38 en fait une panne, M19-E27 un réglage).

*D. Environnements et `resource_group`.*

9. `.deploiement` (stage `deploiement`, `interruptible: false`, `needs: [version, {job: paquet, optional: true}]`, artefact `deploiement.txt` 30 jours), `deployer-dev` (automatique sur `main`), `deployer-recette` (manuel sur `main`, `allow_failure: true`), `deployer-prod` (manuel sur une étiquette `vX.Y.Z`) ; `environment: name`, `deployment_tier`, `url: $CI_JOB_URL/artifacts/file/deploiement.txt` ; `resource_group: ci-labo-<cible>`.
10. Le second `deployer-recette` affiche « Waiting for resource: ci-labo-recette » jusqu'à la fin du premier. *Operate → Environments* : `dev`, `recette`, `prod`, leur dernier déploiement, l'historique, le bouton *Re-deploy* (relance un ancien job de déploiement : c'est un retour arrière… vers un **artefact** encore présent). Ce qui empêche un développeur de lancer `deployer-prod` : le job n'existe que dans les pipelines d'étiquettes `v*`, que seuls les Maintainers posent (étiquettes protégées). Ce que l'édition Premium ajouterait : environnements protégés (qui peut déployer **cet** environnement), approbations de déploiement, gel de déploiement par environnement.
11. Étiquette `v0.1.0` (interface, depuis `main`) : pipeline d'étiquette, `deployer-prod` manuel ; `VERSION=0.1.0`. Registre des secrets : [`registre-secrets.md.extrait`](fichiers/M19-E07/medisphere/docs/socle/registre-secrets.md.extrait) ; matrice des flux : note « cache des runners » sur `K8S_TRAV → s3-01:8333`.

Le check vérifie le fichier `s3-ci-cache.env` (600), la lecture du compartiment `ci-cache` et le refus d'un autre compartiment avec cette identité (requêtes signées en lecture), la configuration du cache dans le ConfigMap du gestionnaire (type, adresse, compartiment, aucune clé), la présence d'objets de cache de `ci-labo`, une réutilisation de cache dont la clé est une empreinte de fichier dans le journal d'un job récent, et les trois environnements (tiers, URL, un déploiement réussi en `dev`).

**Explications**

- **Le cache distribué passe par le *helper*, pas par le gestionnaire.** Le gestionnaire **signe** des URL valables quelques minutes avec les clés de `ci-cache` ; le *helper* télécharge et téléverse directement. Les clés ne sont jamais dans le pod du job. Revers : c'est le *helper* qui doit faire confiance à `s3-01` et le joindre (flux des travailleurs).
- **Clé par fichier de verrou.** La clé suit exactement ce qui détermine le contenu du cache (`uv.lock`). Une clé fixe (`key: uv`) garderait un cache qui grossit sans fin et mélange des versions ; une clé par branche (`$CI_COMMIT_REF_SLUG`) refait un cache à chaque branche.
- **`dotenv` plutôt qu'un fichier lu à la main.** GitLab transforme le rapport en **variables** du job suivant : pas de `source`, pas de dépendance à un chemin, et la valeur apparaît dans l'interface du job.
- **`resource_group` n'est pas un verrou de cible** : il sérialise les jobs **de GitLab**. Un `kubectl apply` lancé depuis `adm01` au même moment n'est pas concerné. D'où le GitOps du M20, où un seul acteur applique.

**Alternatives**

- **Cache dans un volume persistant** (PVC partagé `ReadWriteMany` sur CephFS, `[[runners.kubernetes.volumes.pvc]]`) : pas de téléversement, mais un volume partagé entre jobs de tous les projets, des verrous de fichiers, une dépendance de plus au stockage du cluster.
- **Cache de dépendances par un mandataire** (Nexus, Artifactory, ou le cache PyPI d'un proxy) : réduit aussi la dépendance à Internet ; complémentaire du cache de CI.
- `cache:fallback_keys` : repartir du cache de `main` sur une nouvelle branche.

**Pièges classiques**

- `paths` hors de `$CI_PROJECT_DIR` (`~/.cache/uv`) : « Not found or not accessible », rien n'est mis en cache (panne de M19-E38).
- Deux jobs parallèles en `pull-push` sur la même clé : téléversements concurrents, le dernier gagne, temps perdu.
- Les clés S3 dans `[runners.cache.s3]` du TOML : elles finissent dans un ConfigMap, lisible par `wb-checks` et par quiconque lit les ConfigMaps de `gitlab-runner`.
- Un job manuel sans `allow_failure: true` dans un `rules` : le pipeline reste « bloqué » (`manual`), les MR ne peuvent pas être fusionnées avec « Pipelines must succeed ».
- `environment:url` construite avec une variable du **script** : non développée (seules les variables connues à la création du job le sont).
- Croire que le masquage protège : voir l'étape 2.

**En production chez MédiSphère**

Une durée de vie automatique sur `ci-cache`, la supervision de la taille du compartiment, et une politique d'artefacts (durées par type, nettoyage des artefacts des pipelines anciens par l'API) : M19-E31 et M19-E46. Les vrais déploiements passeront par la promotion en MR (E17) et l'agent (E18), puis par Argo CD (M20).

---

### M19-E08 — Construire des images dans le cluster : BuildKit *rootless* partagé

**Solution**

*A. Comprendre le mode rootless.*

1. Réponses :
   - **seccomp et AppArmor `Unconfined`** : `rootlesskit` crée un espace de noms utilisateur (`unshare`, `clone` avec `CLONE_NEWUSER`) puis des espaces de montage dans lesquels BuildKit monte des systèmes de fichiers (overlay des couches, `tmpfs`) ; le profil seccomp par défaut du runtime filtre ces appels pour un conteneur sans capacité, et le profil AppArmor par défaut interdit `mount`.
   - **`--oci-worker-no-process-sandbox`** (ici `noProcessSandbox = true`) : chaque `RUN` ne reçoit pas de nouvel espace de noms de processus ni son propre `/proc` (le `/proc` d'un conteneur est partiellement masqué par le runtime et ne peut pas être remonté sans privilège). Risque accepté : un `RUN` voit les processus du démon et des autres constructions en cours, avec le même UID, et peut leur envoyer des signaux.
   - **Privilégié ?** Non : `privileged: false`, UID 1000, aucune capacité ajoutée, aucun volume de l'hôte.
   - **`allowPrivilegeEscalation: false`** pose `no_new_privs` : les binaires *setuid* `newuidmap`/`newgidmap` de l'image ne prennent plus leurs droits, et `rootlesskit` ne peut pas écrire la correspondance des UID de l'espace de noms (échec au démarrage). On laisse donc ce champ à sa valeur par défaut, et on le documente.
2. Comparaison : sur `runner02`, l'exception est portée par **chaque** conteneur de construction (un par job, réglage de l'exécuteur `docker`, M12-E21) ; ici par **un** pod, dans un espace isolé. Sur `runner02`, seul le job qui a lancé son démon lui parle (démon éphémère) ; ici, **tout pod de job** de `ci-jobs` muni du certificat client — d'où le TLS mutuel et la politique réseau.

*B. Le chart et le TLS.*

3. Chart [`charts/buildkitd`](fichiers/M19-E08/k8s/charts/buildkitd/) : `Chart.yaml`, `values.yaml`, `templates/_helpers.tpl` (empreinte d'image obligatoire), `configmap.yaml` (`buildkitd.toml`), `deployment.yaml`, `service.yaml`, `pvc.yaml`, `certificats.yaml`, `politique-reseau.yaml` ; valeurs de `k8s-par1` : [`composants/buildkitd/values.yaml`](fichiers/M19-E08/k8s/composants/buildkitd/values.yaml) ; racine pour Harbor : [`espaces/buildkit/40-racine-ca.yaml`](fichiers/M19-E08/k8s/espaces/buildkit/40-racine-ca.yaml). Points clés :
   - `[grpc] address` : TCP 1234 **et** le socket local (pour les sondes `buildctl debug workers`, qui parlent au socket par défaut `/run/user/1000/buildkit/buildkitd.sock`) ; `[grpc.tls]` avec `ca` : certificat client **exigé** (`tls.RequireAndVerifyClientCert` dans le code), jamais appliqué au socket local ;
   - `[worker.oci]` `rootless`, `noProcessSandbox`, ramasse-miettes (`maxUsedSpace = "20GB"`, `reservedSpace = "2GB"`) ; `[registry."registry.par1.medisphere.internal"] ca` ;
   - Deployment en `Recreate` (volume RWO), `fsGroup: 1000`, empreinte de configuration en annotation (une nouvelle `buildkitd.toml` redémarre le démon), `automountServiceAccountToken: false`.
4. **ClusterIssuer** : les certificats clients vivent dans les espaces des **jobs** (`ci-jobs`, puis `ci-jobs-protege`), une Issuer ne délivre que dans son propre espace ; et le Secret de l'autorité doit être dans l'espace de ressources de cert-manager (`cert-manager`), hors de portée du gestionnaire du runner (qui lit les Secrets de `ci-jobs`). Qui d'autre pourrait demander un certificat : quiconque peut créer un `Certificate` (ou une `CertificateRequest`) désignant `buildkit-ca`, dans n'importe quel espace — aujourd'hui les administrateurs du cluster ; le module d'approbation de cert-manager (*approver-policy*) permettrait de restreindre l'usage de cet émetteur à des espaces précis. La politique réseau limite de toute façon les pods qui joignent le démon.
5. Release : [`releases/50-ci.yaml.gotmpl`](fichiers/M19-E08/k8s/releases/50-ci.yaml.gotmpl) (`buildkitd`). **Pas de `needs`** vers cert-manager : chaque fichier de `releases/` est un helmfile à part (inclus par `helmfiles:` dans `helmfile.yaml`, M17-E10), et `needs` ne voit que les releases de son fichier ; Helmfile refuse (« depend(s) on an undefined release "cert-manager/cert-manager" », constaté avec Helmfile 1.8.1). cert-manager est là depuis le M15 ; une reconstruction applique les fichiers dans l'ordre de leurs noms (20 avant 50).
   ```
   admin@adm01:~/src/k8s$ task appliquer                                   # espaces/buildkit/40-racine-ca.yaml
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=buildkitd template > /tmp/buildkitd.yaml
   admin@adm01:~/src/k8s$ kubeconform -strict -summary -schema-location default \
       -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' /tmp/buildkitd.yaml
   Summary: 10 resources found in 1 file - Valid: 10, Invalid: 0, Errors: 0, Skipped: 0
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=buildkitd diff && helmfile -e par1 -l composant=buildkitd apply
   admin@adm01:~$ kubectl --context k8s-par1 -n buildkit get certificate,deploy,pod,svc,pvc
   NAME                                            READY   SECRET              AGE
   certificate.cert-manager.io/buildkitd-serveur   True    buildkitd-serveur   1m
   …
   admin@adm01:~$ kubectl --context k8s-par1 -n buildkit logs deploy/buildkitd | head -5
   … level=info msg="auto snapshotter: using overlayfs"
   … level=warning msg="TLS is disabled for unix:///run/user/1000/buildkit/buildkitd.sock"
   … level=info msg="found worker \"…\", labels=map[…org.mobyproject.buildkit.worker.executor:oci … snapshotter:overlayfs]…"
   … level=info msg="running server on [::]:1234"
   ```
   (L'avertissement « TLS is disabled for unix:// » est attendu : socket local des sondes. Si le pilote de stockage est `native` au lieu d'`overlayfs`, les constructions marchent mais sont plus lentes : noter le cas.)

*C. Le réseau.*

6. `templates/politique-reseau.yaml` du chart : entrée sur 1234 depuis les pods `medisphere.internal/ci: job` des espaces clients ; sortie DNS (CoreDNS), `reg01` 443, Internet 443 hors réseaux privés. [`matrice-flux-cluster.md.extrait`](fichiers/M19-E08/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.md.extrait).
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n wb-essais run sonde --rm -it --restart=Never \
       --image=registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim@sha256:62bd…34ad -- \
       bash -c 'timeout 5 bash -c "</dev/tcp/buildkitd.buildkit.svc.cluster.local/1234" && echo ouvert || echo refusé'
   refusé
   admin@adm01:~$ hubble observe --namespace buildkit --verdict DROPPED --last 5
   … wb-essais/sonde:… -> buildkit/buildkitd-…:1234 policy-verdict:none INGRESS DENIED (TCP Flags: SYN)
   ```
   Depuis `ci-jobs`, c'est le job `buildctl` de l'étape 8 qui fait la preuve.

*D. Les jobs utilisent le démon.*

7. [`composants/gitlab-runner/values.yaml`](fichiers/M19-E08/k8s/composants/gitlab-runner/values.yaml) : `environment` complété (`BUILDKIT_HOST`, `BUILDKIT_TLS_DIR`), `[[runners.kubernetes.volumes.secret]]` `buildkit-client` en `/etc/buildkit/client`. ⚠️ Applique la release `buildkitd` **avant** : un Secret monté qui n'existe pas encore bloque tous les pods de job en `ContainerCreating`.
8. Job `buildctl` de [`ci-labo`](fichiers/M19-E08/ci-labo/.gitlab-ci.yml) :
   ```
   $ buildctl --addr "$BUILDKIT_HOST" --tlsdir "$BUILDKIT_TLS_DIR" debug workers
   ID                              PLATFORMS
   x2kq8v…                         linux/amd64,linux/amd64/v2,linux/amd64/v3,linux/386
   ```
   Sans `--tlsdir` : le client parle en clair à un serveur TLS, la connexion échoue dès la poignée de main ; avec la seule autorité (`--tlscacert`) mais sans certificat client, le serveur refuse (`tls: certificate required`). C'est le TLS mutuel.
9. Robot : [`robots.tf.extrait`](fichiers/M19-E08/infra/registre/robots.tf.extrait) (`robot$plateforme+cache-buildkit`, push et pull sur `plateforme`) ; variables d'**instance** (*Admin → CI/CD → Variables*) `BUILDKIT_CACHE_UTILISATEUR` (protégée, valeur `robot$plateforme+cache-buildkit` : décoche « Expand variable reference », le `$` du nom serait développé) et `BUILDKIT_CACHE_JETON` (protégée, masquée). Gabarits : [`templates/image.yml`](fichiers/M19-E08/ci-templates/templates/image.yml) et [`templates/supply-chain.yml`](fichiers/M19-E08/ci-templates/templates/supply-chain.yml), nouvelle mineure de la branche v1 (semantic-release : commit `feat(image): constructeur BuildKit partagé de k8s-par1`). Le choix du mode tient en une condition : `BUILDKIT_HOST` défini → `buildctl --addr … --tlsdir … build` ; sinon `buildctl-daemonless.sh build`. Dans `sc:construction`, le cache en registre `plateforme/cache-buildkit:<CI_PROJECT_PATH_SLUG>` est importé et exporté **seulement** si les identifiants protégés sont là. Dans `.image-construction`, le cache reste `$IMAGE:cache` : ce job **pousse** aussi l'image, et un `config.json` ne porte qu'un identifiant par hôte de registre — on ne peut pas y mettre en même temps le robot du projet et celui du cache. Vérification du chemin `runner02` : un pipeline d'un projet resté sur `docker` (par exemple `plateforme/ci-templates` lui-même, qui construit l'image outillée du M13) affiche « constructeur : démon éphémère dans le job ».
10. [`mediagenda-api/.gitlab-ci.yml`](fichiers/M19-E08/mediagenda-api/.gitlab-ci.yml) : référence des gabarits montée, `sc:construction: tags: [k8s]` (pars de **ton** fichier actuel, qui peut contenir des ajouts du M13 et du M17 : seules ces deux modifications comptent). Pipeline de `main` : `sc:construction` sur `k8s-par1` (« constructeur : démon partagé… », « cache en registre : registry.par1.medisphere.internal/plateforme/cache-buildkit:mediagenda-api »), `sc:analyse` et la suite sur `runner02`. Deuxième pipeline : les étapes `RUN uv sync …` apparaissent `CACHED` (cache local du démon, ou importé du registre après un redémarrage du démon).
    ```
    admin@adm01:~$ skopeo inspect --raw docker://registry.par1.medisphere.internal/plateforme/cache-buildkit:mediagenda-api | jq -r .mediaType
    application/vnd.oci.image.index.v1+json
    ```
11. Réponse au ticket SEC-2008 : [`brouillons/reponse-sec-2008.md`](fichiers/M19-E08/brouillons/reponse-sec-2008.md) (surface d'attaque, ce qui la réduit, ce qui reste, recommandations pour l'ADR-0190). Registre des secrets : [`registre-secrets.md.extrait`](fichiers/M19-E08/medisphere/docs/socle/registre-secrets.md.extrait).

Le check vérifie le Deployment `buildkitd` (prêt, image de Harbor épinglée, aucun conteneur privilégié dans `buildkit` et `ci-jobs`), le Service sur 1234, les certificats `Ready` et leur émetteur, la politique réseau (sélecteurs d'entrée limités aux espaces de jobs), le dépôt `plateforme/cache-buildkit` dans Harbor et ses artefacts, et le dernier pipeline de `main` de `mediagenda/api` (job `sc:construction` réussi, exécuté par `k8s-par1`).

**Explications**

- **Le client fournit les identifiants, le démon fait le travail.** `buildctl` ouvre une session gRPC ; quand le démon doit tirer ou pousser, il **demande** un jeton d'accès au client à travers cette session (`config.json` du job). Le démon partagé n'a donc aucun identifiant à lui, et chaque construction utilise les droits de **son** job.
- **Le certificat serveur n'est lu qu'au démarrage.** `serverCredentials` charge la paire de clés une fois. cert-manager renouvelle le Secret 30 jours avant l'échéance (certificat d'un an), mais buildkitd garde l'ancien en mémoire : il faut **redémarrer** le démon après chaque renouvellement (`kubectl -n buildkit rollout restart deploy/buildkitd`), ou automatiser (Reloader, M21 pour l'alerte). Les certificats **clients** n'ont pas ce problème : chaque pod de job monte le Secret du moment.
- **Un cache par projet, écrit par les seuls pipelines protégés.** Une MR peut contenir n'importe quoi : si elle pouvait écrire le cache que `main` réutilise, elle pourrait y glisser une couche piégée. Les variables protégées réservent l'écriture (et la lecture) aux pipelines de `main` et des étiquettes.

**Alternatives**

- **Kaniko** : archivé par Google (juin 2025), fork de maintenance de Chainguard ; tourne sans démon mais exige root dans le conteneur. Écarté (ADR-0190).
- **Buildah** sans privilège dans le pod de job (Podman/Buildah en mode *rootless* avec `fuse-overlayfs` ou `vfs`) : même exception seccomp/AppArmor dans chaque pod de job, plus lent ; c'est le modèle de `runner02` transposé.
- **Démon BuildKit par job** (BuildKit en service du job, ou `buildctl-daemonless.sh` dans le pod) : isolation maximale, mais l'exception de sécurité dans `ci-jobs` (donc Pod Security `privileged` pour **tous** les jobs).
- **Plusieurs démons, hachage cohérent** (StatefulSet, exemple `consistenthash` amont) : cache local stable par projet, montée en charge ; ou un démon **par niveau de confiance** (protégé, non protégé).
- **Projet Harbor dédié au cache** : supprime la limite du robot de projet (droits sur tout `plateforme`).

**Pièges classiques**

- `allowPrivilegeEscalation: false` « par hygiène » : `newuidmap: write to uid_map failed: Operation not permitted`, le démon ne démarre pas.
- Oublier le socket local dans `[grpc] address` : les sondes `buildctl debug workers` échouent, le pod n'est jamais prêt alors que le port 1234 répond.
- Un certificat serveur sans le nom exact de `BUILDKIT_HOST` (`buildkitd.buildkit.svc.cluster.local`) : `x509: certificate is valid for buildkitd, not …`.
- Une politique réseau sans règle DNS : le démon ne résout plus `registry.par1.medisphere.internal`, les constructions échouent sur `FROM`.
- Exporter le cache depuis les MR : écriture du cache par du code non relu (voir plus haut), et échec des MR faute d'identifiants.
- Mettre le cache dans le projet Harbor `medisphere` : la politique « signature exigée » (M13-E14) refuse de **servir** un manifeste de cache non signé ; l'import échoue.
- Croire que le démon partagé isole les projets : voir la réponse au ticket SEC-2008 (cache local partagé, processus visibles entre constructions).

**En production chez MédiSphère**

Un démon par niveau de confiance (le runner protégé du M19-E24 pourrait avoir le sien), un projet Harbor dédié au cache avec une politique de rétention, la supervision du démon (durée des constructions, disque, certificat), et le redémarrage automatique après renouvellement du certificat. L'ADR-0190 (E30) tranche.

---

### M19-E09 — Questions : le modèle d'exécution de GitLab CI

**Barème** : 2 points par question, total sur 24. En dessous de 12, relis E04 et E05 et le corrigé de E01 (questions 14 à 18) ; M19-E44 refait ce chemin dans les journaux.

**1. Du `git push` aux jobs.** Le serveur Git de GitLab (Gitaly, derrière `git01`) reçoit la poussée ; un *hook* post-réception fait mettre en file (Sidekiq) le traitement de la poussée, qui appelle la création de pipeline pour le commit poussé. GitLab lit le `.gitlab-ci.yml` **de ce commit** (chemin réglé dans le projet ; les `include` sont résolus à ce moment, aux références demandées), évalue d'abord `workflow:rules` (le pipeline est-il créé ?), puis les `rules` de chaque job (le job est-il ajouté ?), calcule le graphe (`stages`, `needs`) et enregistre pipeline et jobs en base. Un fichier invalide : le pipeline est créé à l'état **failed** avec l'erreur de configuration (visible dans la liste des pipelines et dans l'éditeur), aucun job n'est créé. Une erreur dans un `include` (projet inaccessible, référence inexistante) produit le même effet.

**2. `created`, `pending`, `running`.** `created` : le job existe mais attend ses prédécesseurs (stage précédent ou `needs`). Il passe `pending` quand ses dépendances sont satisfaites : il est alors **dans la file**, prêt à être donné à un runner qui correspond (étiquettes, protection, projet). Il passe `running` quand un gestionnaire le **reçoit** en réponse à sa demande. Un job `manual` reste `manual` jusqu'au clic.

**3. Le *long polling*.** La requête `POST /api/v4/jobs/request` porte le **jeton du runner**, l'identifiant du gestionnaire (`system_id`), ses informations (version, exécuteur, architecture, fonctions prises en charge) et un marqueur de dernière mise à jour. Si aucun job ne correspond, GitLab répond **`204 No Content`** ; Workhorse (le mandataire HTTP de GitLab) garde la requête ouverte jusqu'à l'arrivée d'un job ou l'échéance d'un délai (≈ 50 s par défaut, réglage de Workhorse, à vérifier sur ta version), puis le gestionnaire recommence. Pour notre réseau : le seul flux nécessaire va des **travailleurs vers `git01:443`** ; GitLab n'a jamais à joindre le cluster (aucune règle `VLAN 20 → VLAN 40`).

**4. Deux gestionnaires d'un même runner.** L'attribution d'un job est une transition d'état faite par la base de GitLab dans une transaction (le job passe de `pending` à `running` au profit d'**un** gestionnaire, les autres demandes ne le voient plus) : un job n'est donné qu'une fois. Dans l'interface, le runner a plusieurs **gestionnaires** (*runner managers*), distingués par leur `system_id`, leur adresse, leur version et leur dernier contact ; chaque job indique le gestionnaire qui l'a exécuté.

**5. Réponse B.** Un runner ne prend un job que s'il possède **toutes** les étiquettes du job ; `k8s-par1` n'a pas `gpu` : le job reste `pending` (« stuck »). A est faux (aucune étiquette n'est ignorée) ; C est faux (le job attend, il n'échoue pas immédiatement : il expirera selon le délai de file d'attente de l'instance) ; D n'existe pas.

**6. Le jeton de job.** Il sert au *helper* à **cloner** le dépôt (utilisateur `gitlab-ci-token`), au gestionnaire à **envoyer le journal** et l'état du job (`PATCH /api/v4/jobs/:id/trace`, `PUT /api/v4/jobs/:id`), au *helper* à **téléverser et télécharger les artefacts**, au script (variable `CI_JOB_TOKEN`) à appeler certains points d'API et registres (registre de conteneurs et de paquets de GitLab, déclencheurs, autres projets autorisés). À la fin du job, il est **invalide**.

**7. Où sont évaluées les variables.** `rules:if` : par **GitLab**, à la création du pipeline (seules les variables connues à ce moment : prédéfinies, du fichier, du projet…). `image:` et `services:` : par le **gestionnaire**, avec les variables du job, avant de créer le pod. `script:` : par le **shell** du conteneur `build`, au moment de l'exécution (on peut y utiliser une variable calculée par une ligne précédente). Exemple qui compte : `image: $IMAGE_UV` fonctionne (variable du fichier) ; `image: $(cat version)` ne fonctionne pas ; une variable calculée dans `before_script` n'existe pas pour `rules:if`.

**8. L'identité du job dans le cluster.** Le pod est **créé** par le gestionnaire (compte `gitlab-runner/gitlab-runner`, Role dans `ci-jobs`), mais il **tourne** avec le compte de service déclaré dans sa spécification : `ci-job`, sans liaison et sans jeton monté. Le job ne peut rien faire avec l'API Kubernetes (pas de jeton ; et un jeton de `ci-job` ne donnerait aucun droit). Avec `automount_service_account_token = true` et `edit` sur `ci-jobs`, tout job (de n'importe quelle branche) pourrait lire les Secrets de `ci-jobs` (identifiants de registre des autres jobs, certificat client de buildkitd), créer des pods à sa guise (contournant le runner et ses plafonds), lire les variables des autres jobs en cours par leurs pods : une escalade de toute la CI.

**9. Ce que voit un job.** Accès : le dépôt cloné et ses fichiers ; les **variables** du job (prédéfinies, du projet et du groupe, protégées si la référence est protégée) dont `CI_JOB_TOKEN` ; le **réseau** sortant (Harbor, `git01`, Internet ; au palier 3 il sera restreint) ; ses **services** par `localhost` ; la racine MédiSphère et le certificat client de buildkitd (montés) ; le cache restauré. Pas d'accès : le **jeton du runner** (`glrt-`, dans l'espace `gitlab-runner`), les **clés S3** du cache (seul le gestionnaire les a ; le job reçoit des URL signées), l'**API Kubernetes**, les autres pods de job, les autres runners.

**10. Réponse B.** À l'arrêt, Kubernetes envoie le signal d'arrêt au gestionnaire ; GitLab Runner interprète l'arrêt « gracieux » : il ne prend plus de job et **attend la fin** des jobs en cours, dans la limite de `terminationGracePeriodSeconds` (3600 s dans nos valeurs ; au-delà, Kubernetes tue le pod et les jobs restants échouent). A serait le cas avec un délai de grâce trop court ; C est faux (le pod de job ne survit pas utilement sans gestionnaire pour relayer journal et résultat) ; D est faux (GitLab ne relance pas un job de lui-même, sauf `retry` configuré).

**11. « Waiting for pod … to be running » puis échec.** Causes et confirmation :
- quota de `ci-jobs` épuisé (le pod est refusé, le runner réessaie) : `kubectl -n ci-jobs describe quota quota-ci`, événements `exceeded quota` ;
- pas de place sur les nœuds (demandes trop fortes, nœud cordonné) : `kubectl -n ci-jobs get events --field-selector reason=FailedScheduling` ;
- image introuvable ou refusée (étiquette erronée, cache Harbor en défaut) : `kubectl -n ci-jobs describe pod …` (`ErrImagePull`, `ImagePullBackOff`), journal de Harbor ;
- (aussi) un volume monté qui n'existe pas (Secret `buildkit-client` absent) : `ContainerCreating` et événement `FailedMount`.
Le délai de 10 minutes est `poll_timeout = 600`.

**12. Artefact absent d'un job réussi.** Les artefacts sont téléversés par le conteneur **`helper`**, **après** le script (et après `after_script`), avec le jeton de job, vers l'API de GitLab, qui les range dans son stockage. Causes d'écart : le chemin ne correspond à aucun fichier (motif faux, fichier écrit hors de `$CI_PROJECT_DIR` : message « no matching files », le job reste réussi) ; les artefacts ont **déjà expiré** (`expire_in` court) ; une taille supérieure au maximum de l'instance (`413`, le téléversement échoue — selon la version et `artifacts:when`, le job échoue ou non) ; le job a écrit l'artefact dans un `after_script` qui a échoué silencieusement.
