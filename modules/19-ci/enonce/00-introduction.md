# Module 19 — Introduction : l'intégration continue

## Un seul runner pour toute l'entreprise

Lundi, 8 h 40. Julien Petit a posté une capture d'écran dans le canal de l'équipe Plateforme : quatorze jobs « en attente » sur `runner02`, dont le pipeline de correctif de MédiAgenda que la recette attend depuis vendredi. Sophie Laurent a répondu par un lien vers l'ADR-0120 (« aucun job privilégié, jamais ») et une question : « qui a accès à la clé Cosign quand un pipeline tourne sur une branche de stagiaire ? ». Claire Morel a tranché par un message à toute l'équipe.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Chaîne de livraison — on arrête de bricoler
>
> Bonjour,
>
> Nos pipelines tiennent sur une seule VM à 4 Go, nos gabarits sont copiés de projet en projet, et la mise en recette passe encore par un `kubectl apply` depuis `adm01`. On a un cluster Kubernetes qui sait faire tourner des charges élastiques : il est temps qu'il fasse tourner **nos jobs**.
>
> Ce que je veux à la fin du module :
> 1. des **runners dans `k8s-par1`**, élastiques, cloisonnés, sans privilège, avec un cache partagé ;
> 2. des **constructions d'images dans le cluster** sans démon privilégié ni Docker-in-Docker ;
> 3. un **pipeline standard** que chaque équipe adopte en quelques lignes, en **composants versionnés** ;
> 4. des analyses de sécurité qui bloquent vraiment, des images signées, **promues par merge request** ;
> 5. une décision écrite sur Jenkins et SonarQube, que Karim veut voir comparés honnêtement ;
> 6. la montée de GitLab en 19.5, et des runbooks pour le jour où un pipeline reste bloqué.
>
> Premier jalon : un cluster prêt à recevoir des jobs, une messagerie de lab (GitLab n'envoie aujourd'hui aucun courriel, et les alertes du M21 en auront besoin), un runner Kubernetes qui tourne les pipelines d'un projet d'essai, et une première image de MédiAgenda construite dans le cluster. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 19, MédiSphère a sa chaîne d'intégration continue **v1** (étiquette `ci-v1` du dépôt `plateforme/medisphere`), que le module 20 (GitOps) prolonge jusqu'au déploiement :

- **`mon01`** (VMID 1014, 10.10.20.19) : hôte permanent du socle, messagerie du lab **Mailpit** (`smtp.par1.medisphere.internal:25`), puis supervision « témoin » au M21 ;
- des **runners GitLab dans `k8s-par1`** (exécuteur `kubernetes`) : `k8s-par1` (étiquettes `k8s`, `kubernetes`), puis `k8s-par1-protege` (palier 3) seul à signer et à promouvoir ; cache S3 sur `s3-01` ;
- un démon **BuildKit *rootless* partagé** (`buildkitd`, espace `buildkit`, TLS mutuel) : plus aucun job ne construit d'image avec des privilèges ;
- des **composants CI/CD** versionnés dans `plateforme/ci-templates` (v2.0.0, palier 2) : construction, qualité, sécurité (Semgrep CE, Gitleaks, Trivy, SBOM, signature), promotion, déploiement ;
- la **promotion par MR** des images de MédiAgenda dans `mediagenda/deploiement` et le déploiement en dev par l'**agent GitLab pour Kubernetes** ;
- Jenkins et SonarQube **pratiqués puis retirés** (ADR-0190), la montée GitLab 19.4 → 19.5, des runbooks (RB-190 à RB-198, dans `docs/livraison/ci/runbooks/`), des pannes réalistes.

Le **palier 1** (ce fichier et `01-decouverte.md`) prépare le cluster (travailleurs à 10 Go, espaces, quotas, compte des vérifications), crée `mon01` et Mailpit et branche GitLab dessus, installe le premier runner Kubernetes par Helmfile, puis te fait **lire** un job dans Kubernetes et pratiquer la syntaxe de GitLab CI en profondeur (`rules`, `needs`, `workflow`, variables, artefacts, cache, environnements) sur un projet d'essai, `formation/ci-labo`. Il se termine par le démon BuildKit partagé et la première image de MédiAgenda construite dans le cluster. Le palier s'ouvre et se ferme sur un questionnaire.

## Architecture du module (palier 1)

```
                      adm01 (1001) 10.10.10.10 — MGMT : kubectl, helmfile, glab, ~/src/{k8s,infra,ansible,ci-labo}
                                 │ (MGMT joint tout le lab)
 ════════════════════════ gw01 / gw02 (VIP .1) — routage, filtrage (rôle pare_feu) ══════════════════════════
        │ VLAN 20 INFRA                                                      │ VLAN 40 K8S
 ┌──────┴─────────────────────────────────────────┐   K8S_TRAV → git01:443 (nouveau, E04)
 │ git01 (1004) 10.10.20.12  GitLab CE 19.4       │◄───────────────────────┐ K8S_CP/TRAV → mon01:25 (nouveau, E03)
 │   ├ API /api/v4/jobs/request ◄── long polling ─┼────────────┐           │ K8S_TRAV → s3-01:8333 (M15-E34)
 │   └ courriels ──SMTP 25 STARTTLS──┐            │            │           │ VLAN 40 → reg01:443 (M13)
 │ mon01 (1014) 10.10.20.19 ◄────────┘ Mailpit    │            │           │
 │   SMTP :25 (smtp.par1…), HTTPS :8025 (MGMT)    │  ┌─────────┴───────────┴──────── k8s-par1 ──────────────────┐
 │ reg01 (1013) registry.par1… Harbor 2.15        │  │ gitlab-runner  : gestionnaire « k8s-par1 » (Helmfile)     │
 │   caches dockerhub, quay, ghcr, k8s, gitlab(E04)│  │   └ crée les pods de job ─────────────┐                  │
 │   plateforme/cache-buildkit (E08)              │  │ ci-jobs        : pods de job          ▼                  │
 │ s3-01 (1006) :8333 SeaweedFS, compartiment     │  │   [init-permissions] build helper [svc-0…]              │
 │   ci-cache (E07)                               │  │   SA ci-job (aucun droit) · quota · LimitRange         │
 │ runner02 (1012) exécuteur docker (« docker »)  │  │      │ buildctl --tlsdir (TLS mutuel)                  │
 └────────────────────────────────────────────────┘  │      ▼                                                  │
                                                     │ buildkit       : buildkitd rootless :1234 ──► Harbor   │
                                                     │   (cert-manager : ClusterIssuer buildkit-ca)          │
                                                     │ travailleurs k8s-w01..03 : 4 vCPU · 10 Go (E02)        │
                                                     └────────────────────────────────────────────────────────┘
```

Points structurants :

- **Le runner ne reçoit rien, il demande.** Le gestionnaire (`gitlab-runner`, un pod de l'espace `gitlab-runner`) interroge GitLab en *long polling* (`POST /api/v4/jobs/request`) ; GitLab ne se connecte jamais au cluster. Seul le flux **travailleurs → `git01:443`** est nécessaire.
- **Un job = un pod.** Pour chaque job, le gestionnaire crée un pod dans `ci-jobs` : un conteneur `build` (l'image du job, qui exécute ton script), un conteneur `helper` (clonage, artefacts, cache), un conteneur par service, et un conteneur d'initialisation `init-permissions`. Le pod disparaît à la fin du job. Ce que le job peut faire dans le cluster est ce que son **compte de service** (`ci-job`) peut faire : rien.
- **Gestionnaire et jobs dans deux espaces.** Le gestionnaire a besoin de droits (créer des pods, des Secrets) ; les jobs n'en ont aucun. Les séparer permet des quotas, une Pod Security et des politiques réseau différentes, et de ne jamais laisser un job lire le jeton du runner.
- **Construire sans privilège, dans un démon partagé.** Un job ne lance pas BuildKit lui-même (il faudrait seccomp et AppArmor non confinés dans chaque pod de job) : il parle, en **TLS mutuel**, à un démon BuildKit *rootless* unique, dont l'exception de sécurité est écrite une fois, dans un espace isolé.
- **Tout passe par le code et par Harbor.** Espaces et RBAC dans `plateforme/k8s/espaces/`, releases dans le Helmfile de `plateforme/k8s`, Secrets créés par `outils/secrets-k8s.sh` depuis Ansible Vault `critique`, VM par OpenTofu, configuration par Ansible ; toutes les images (gestionnaire, *helper*, jobs, BuildKit) sont tirées par Harbor.

---

## Le chemin imposé

1. **OpenTofu** (`plateforme/infra`) : `mon01` dans l'état **`socle`** (module `vm-debian`, comme `reg01` au M13) ; la mémoire des travailleurs dans l'état **`envs/k8s`** ; le cache `gitlab` et les objets Harbor dans l'état **`registre`**.
2. **Ansible** (`plateforme/ansible`) : rôle **`mailpit`** (nouveau), rôles `certificats_acme`, `pare_feu`, `pare_feu_local` (M06-M07), `k8s_travailleur` (M14, étendu en E02), `gitlab_hote` (M04, étendu en E03) ; application par le pipeline protégé (ADR-0040).
3. **`plateforme/k8s`** : espaces (`espaces/gitlab-runner/`, `espaces/ci-jobs/`, `espaces/buildkit/`), RBAC des vérifications (`rbac/wb-checks-livraison.yaml`), Helmfile (`releases/50-ci.yaml.gotmpl` : `gitlab-runner`, `buildkitd`), chart local `charts/buildkitd`, valeurs dans `composants/<composant>/values.yaml`, Secrets par **`outils/secrets-k8s.sh`** (créé en E04) depuis `secrets/<composant>.yml` (Vault `critique`). Appliqué depuis `adm01` à partir de `main` (`task appliquer`, `helmfile -e par1 apply`) ; le GitOps du M20 reprendra la main.
4. **GitLab** : runners créés **par l'API** (`POST /user/runners`), jamais avec un jeton d'enregistrement ; projet d'exercice **`formation/ci-labo`** ; gabarits partagés dans `plateforme/ci-templates` (encore en v1.x au palier 1, composants v2.0.0 au palier 2).
5. **Documentation** (`plateforme/medisphere`) : `docs/livraison/ci/` (nouveau dossier), `docs/socle/messagerie.md`, matrice des flux et registre des secrets dans `docs/socle/`.

Une manipulation à la main n'est permise que pour **explorer** (lire un pod de job, un `kubectl describe`, un appel d'API en lecture) ou quand l'énoncé la demande comme geste à connaître.

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Pipeline, stage, job.** Un **pipeline** est créé par un événement (poussée, MR, étiquette, planification, API, déclencheur) à partir du `.gitlab-ci.yml` du commit. Il contient des **jobs** ; chaque job appartient à un **stage**. Par défaut, un stage commence quand le précédent a réussi ; le mot-clé **`needs`** remplace cet ordre par un graphe de dépendances (DAG) : un job démarre dès que ceux dont il dépend ont fini.

**`rules` et `workflow`.** Les **`rules`** d'un job décident s'il est ajouté au pipeline (et comment : `when`, `allow_failure`, variables), d'après des conditions (`if` sur les variables, `changes` sur les fichiers modifiés, `exists`). Les **`workflow:rules`** décident si le **pipeline lui-même** est créé : c'est là qu'on évite le doublon « pipeline de branche + pipeline de MR » pour un même commit. `only`/`except`, plus anciens, ne se mélangent pas avec `rules` dans un même job.

**Variables.** Prédéfinies (`CI_COMMIT_SHA`, `CI_PIPELINE_SOURCE`, `CI_JOB_TOKEN`…), définies dans le fichier, dans les réglages du projet, du groupe ou de l'instance, ou à la main au lancement : un ordre de priorité décide laquelle gagne. Une variable **protégée** n'existe que dans les pipelines des branches et étiquettes **protégées** ; **masquée**, elle est remplacée par `[MASKED]` dans le journal ; de type **fichier**, elle est écrite dans un fichier dont la variable contient le chemin.

**Artefacts et cache.** Un **artefact** est un **résultat** du job, téléversé vers GitLab, transmis aux jobs suivants, téléchargeable, avec une durée de vie (`expire_in`) ; certains sont des **rapports** (`junit`, `dotenv`, `codequality`…) que GitLab lit. Le **cache** est une **optimisation** : des fichiers (dépendances téléchargées) qu'on espère retrouver au prochain job, sans garantie ; avec des runners élastiques, il vit dans un stockage objet partagé (ici `s3-01`).

**Environnements et `resource_group`.** Un **environnement** (`dev`, `recette`, `prod`) donne à GitLab l'historique de ce qui a été déployé où, par quel job. Un **`resource_group`** garantit qu'un seul job du groupe tourne à la fois (deux déploiements de la même cible ne se croisent pas). Les environnements **protégés** et les approbations de déploiement sont réservés à l'édition Premium : MédiSphère protège par branches protégées, jobs manuels et variables protégées (ADR-0051).

**Runner, gestionnaire, exécuteur, jeton.** Un **runner** est un objet de GitLab (description, étiquettes, portée : instance, groupe, projet) identifié par un **jeton d'authentification** `glrt-` ; un ou plusieurs **gestionnaires** (*runner managers*, des processus `gitlab-runner`) utilisent ce jeton pour demander des jobs ; l'**exécuteur** décide où le job tourne (`shell` sur `runner01`, `docker` sur `runner02`, `kubernetes` ici). Chaque job reçoit en plus un **jeton de job** (`CI_JOB_TOKEN`), valable le temps du job, avec les droits de l'utilisateur qui l'a déclenché, limités.

**Construire une image sans privilège.** Docker-in-Docker exige un conteneur **privilégié** (accès complet à l'hôte). BuildKit en mode **rootless** construit dans un espace de noms utilisateur, sans privilège, mais doit créer des espaces de noms et monter des systèmes de fichiers : les profils seccomp et AppArmor par défaut l'en empêchent. D'où l'exception écrite (ADR-0120 pour `runner02`) et, ici, un **démon partagé** isolé, que les jobs pilotent à distance.

---

## Faits techniques du module (palier 1)

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | GitLab CE **19.4.x** (≥ 19.4.3), GitLab Runner **19.4.0** (chart `gitlab/gitlab-runner` **0.93.0**), Mailpit **1.31.6**, BuildKit **0.34.1** (démon) et 0.34.0 (client des gabarits M12/M13), cert-manager 1.21, Cilium 1.20, Helm 4.3, Helmfile 1.8, Kubernetes 1.36 ; changements de comportement : [`annexes/versions-bloc-DE.md`](../../../annexes/versions-bloc-DE.md) |
| Hôte permanent | `mon01` : VMID **1014**, **10.10.20.19** (VLAN 20, VNet `vinfra`), Debian 13, 2 vCPU, 3 Go, 32 Gio `local-nvme`, état OpenTofu `socle`, étiquettes `socle` + `role-supervision`, groupe d'inventaire `role_supervision` ; CNAME **`smtp.par1.medisphere.internal`** |
| Mailpit | SMTP **25** (STARTTLS, certificat ACME de step-ca), interface et API HTTPS **8025** (authentification basique), sans relais vers l'extérieur ; adresses du lab `@medisphere.internal` (`plateforme@`, `astreinte@`, `securite@`, `<prénom.nom>@`) |
| Espaces de noms | **`gitlab-runner`** (gestionnaire), **`ci-jobs`** (pods de job), **`buildkit`** (démon BuildKit) ; plus tard `ci-jobs-protege` (E24), `gitlab-agent` (E18), `sonarqube`, `jenkins` (temporaires) |
| Runner | **`k8s-par1`** : runner d'instance, étiquettes `k8s` et `kubernetes`, `run_untagged: false`, jeton `glrt-` créé par l'API ; release Helmfile **`gitlab-runner`** ; compte de service des pods de job **`ci-job`** (aucun droit, jeton non monté) |
| BuildKit | Deployment **`buildkitd`** (chart local `charts/buildkitd`), Service **`buildkitd.buildkit:1234`**, TLS mutuel par cert-manager (ClusterIssuer **`buildkit-ca`**), cache en registre **`plateforme/cache-buildkit`** dans Harbor |
| Cache S3 | `s3-01`, compartiment **`ci-cache`**, identité **`ci-cache`**, `~/.config/workbook/s3-ci-cache.env` (E07) |
| Harbor | nouveau cache **`gitlab`** (`registry.gitlab.com`, E04) ; dépôt `plateforme/cache-buildkit` (E08) |
| Projets GitLab | **`formation/ci-labo`** (nouveau, E04) ; `plateforme/k8s`, `plateforme/infra`, `plateforme/ansible`, `plateforme/ci-templates`, `mediagenda/api`, `plateforme/medisphere` |
| Comptes des vérifications | ClusterRole agrégée **`wb-checks-livraison`** (E02, étiquette `workbook.medisphere.internal/checks: "true"`, jamais les Secrets) ; `~/.config/workbook/mailpit-checks.env` (compte `wb-checks` de Mailpit, E03) |
| Documentation | `plateforme/medisphere` : `docs/socle/messagerie.md` (E03), `docs/livraison/ci/anatomie-job.md` (E05), matrice des flux et registre des secrets ; tickets `PLAT-20xx`, `SEC-20xx`, `DEV-20xx`, `INC-46xx` (xx = numéro de l'exercice) |
| Brouillons | `~/m19/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05), administrateur de l'instance |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<VERSION-TOFU-MODULES>` | Dernière étiquette publiée de `plateforme/tofu-modules` (`vm-debian` avec `disques_donnees`, M13) |
| `<VERSION-CI-TEMPLATES>` | Dernière étiquette `v1.Y.Z` publiée de `plateforme/ci-templates` (M13-E09 ou suivantes) |
| `<EMPREINTE>` | Empreinte `sha256:…` d'une image, relevée par `skopeo inspect` à travers Harbor (une image d'un cache a la même empreinte que l'amont) |

### Variables de `lab/lab.env`

Les vérifications et les pannes du module lisent, en plus de celles des blocs précédents (`WB_GITLAB_*` dont `WB_GITLAB_ADMIN_TOKEN_FILE` pour les pannes, `WB_K8S_*`, `WB_HARBOR_*`, `WB_MOI`, `WB_DEPOT` pour ton clone de `plateforme/medisphere`) :

```
WB_MAILPIT_URL="https://mon01.par1.medisphere.internal:8025"        # API de Mailpit (E03)
WB_MAILPIT_CHECKS_FILE="$HOME/.config/workbook/mailpit-checks.env"  # MAILPIT_USER=… MAILPIT_PASSWORD=…
WB_S3_CI_CACHE_FILE="$HOME/.config/workbook/s3-ci-cache.env"        # identité ci-cache de s3-01 (E07)
#WB_M19_LABO="formation/ci-labo"                                    # projet d'exercice, si tu l'as nommé autrement
#WB_M19_MON01="mon01"                                               # alias SSH de mon01
#WB_M19_RUNNER="k8s-par1"                                           # runner Kubernetes (pannes du palier 4)
#WB_M19_SONAR_URL="https://sonarqube.apps.par1.medisphere.internal" # SonarQube (E16, temporaire)
#WB_M19_SONAR_TOKEN_FILE="$HOME/.config/workbook/sonar-checks.token"    # jeton de lecture wb-checks (E16)
#WB_M19_JENKINS_URL="https://jenkins.apps.par1.medisphere.internal" # Jenkins (E19-E20, temporaire)
#WB_M19_JENKINS_CHECKS_FILE="$HOME/.config/workbook/jenkins-checks.env" # JENKINS_USER=… JENKINS_TOKEN=… (E19)
#WB_M19_TEMOIN="formation/ci-pannes"                                # projet témoin des pannes (palier 4)
#WB_M19_HARBOR_ADMIN_FILE="$HOME/.config/workbook/harbor-moi.env"   # ton compte Harbor (M13), pour les pannes
#WB_M19_S3="s3-01"                                                  # alias SSH de s3-01 (pannes du cache)
#WB_M19_IMAGE_BUILDKIT="registry.par1.medisphere.internal/dockerhub/moby/buildkit:v0.34.1-rootless"
```

Les trois premières ont des valeurs par défaut dans `lab/lib/check-lib.sh` ou dans les scripts du module ; les lignes commentées donnent les valeurs par défaut : ne les pose que si les tiennes diffèrent. Fichiers créés par le module sous `~/.config/workbook/` (700, fichiers 600) : `mailpit-checks.env` (E03), `s3-ci-cache.env` (E07), `sonar-checks.token` (E16), `jenkins-checks.env` (E19), supprimés ou laissés sans effet après le retrait de SonarQube et de Jenkins (E46).

---

## Règles du module

1. **Jamais de conteneur privilégié, jamais de Docker-in-Docker.** Ni dans un job, ni dans un démon. Une exception de sécurité (seccomp, AppArmor) s'écrit dans un ADR, se limite à un espace et se vérifie.
2. **Jamais de jeton d'enregistrement.** Un runner se crée dans GitLab (API ou interface), qui rend un jeton `glrt-` ; ce jeton va dans Ansible Vault `critique`, puis dans un Secret créé par `outils/secrets-k8s.sh`. Il n'apparaît ni dans un dépôt, ni dans des valeurs Helm, ni dans un journal.
3. **Les jobs n'ont aucun droit sur le cluster.** Compte de service `ci-job` sans liaison, jeton non monté. Le déploiement en dev passera par l'agent GitLab (E18), avec ses propres droits, limités.
4. **Toutes les images passent par Harbor**, avec une étiquette de version **et** une empreinte. La politique d'admission `medisphere-images` (M14-E18) s'applique à `ci-jobs` : une image `latest` ou hors Harbor y est refusée.
5. **Mémoire.** Profil de travail des blocs D et E : socle v4 (≈ 40 Go avec `mon01`) + `ceph-par1` (3 × 6 Go) + `k8s-par1` (3 × 4 + 3 × 10 Go) ≈ **100 Go**. Démarrage : `ceph-par1` puis `k8s-par1` ; arrêt dans l'ordre inverse (règles du M14). Jenkins et SonarQube (palier 2) ne tournent **jamais** ensemble.
6. **Un geste risqué s'annonce.** Redémarrer un travailleur, reconfigurer GitLab, ouvrir un flux : avertissement, état avant, retour arrière écrit, un élément à la fois.

---

## Préparer `adm01`

Contrôles d'entrée (mini-projets des modules 17 et 14) et état du lab :

```
admin@adm01:~$ lab/bin/check 17 25
admin@adm01:~$ lab/bin/check 14 46
admin@adm01:~$ kubectl --context k8s-par1 get nodes -o wide
admin@adm01:~$ ssh root@pve01 'free -g | head -2; qm list | grep -E " (1014|214[4-6]) "'
admin@adm01:~$ curl -s https://git01.par1.medisphere.internal/api/v4/version \
                 -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(<~/.config/workbook/gitlab-checks.token)") | jq -r .version
```

Les deux contrôles doivent être verts (le chart et `mediagenda/deploiement` du M17, le cluster du M14). Il te faut **environ 8 Go libres** de plus qu'au M17 : 6 Go pour les travailleurs (E02) et 3 Go pour `mon01` (E03) ; si `free -g` est juste, arrête d'abord tout environnement des modules précédents qui tournerait encore. La version de GitLab doit être 19.4.3 ou plus (19.4.x).

Outils de ce palier sur `adm01` (déjà là depuis les modules 14 et 17 : `kubectl`, `helm`, `helmfile`, `kustomize`, `jq`, `yq`) ; à ajouter :

- **`glab`** 1.124 (CLI de GitLab, facultatif mais pratique : `glab ci status`, `glab ci trace`) : binaire amont épinglé par empreinte, comme les autres outils de `adm01` (rôle `outils_k8s` du M14 ou installation équivalente) ;
- `swaks` (paquet Debian, test d'un serveur SMTP, E03) et `apache2-utils` (`htpasswd`, E03) ;
- `buildctl` 0.34.1 (client BuildKit, E08), binaire amont de la version de `moby/buildkit`, épinglé par empreinte.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 19 <XX>`. Elles sont en lecture seule : API GitLab et Harbor en GET, API de Mailpit (compte `wb-checks`), `kubectl get` avec le compte de service `wb-checks` (jamais les Secrets), `qm config` sur `pve01`, commandes de consultation en SSH.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M19-EXX/` : `k8s/` reproduit l'arborescence de `plateforme/k8s`, `ansible/` celle de `plateforme/ansible`, `infra/` celle de `plateforme/infra`, `ci-labo/` celle de `formation/ci-labo`, `ci-templates/` celle de `plateforme/ci-templates`, `mediagenda-api/` celle de `mediagenda/api`, `medisphere/` celle de la documentation.
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09
            (E03 peut se faire en parallèle de E02)
```

1. **E01** — positionnement, à froid.
2. **E02** — le cluster prêt (mémoire, espaces, quotas, vérifications) ; **E03** — `mon01` et Mailpit, indépendant du cluster.
3. **E04 → E07** — dans l'ordre : le runner, puis ce qu'il exécute (anatomie d'un job), puis la syntaxe des pipelines, puis variables, artefacts, cache et environnements, tous dans `formation/ci-labo`.
4. **E08** — BuildKit partagé : il a besoin du runner (E04) et de ce que tu sais des pods de job (E05).
5. **E09** — en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 16 à 20 heures.

## Pour aller plus loin

- GitLab CI/CD, référence du fichier `.gitlab-ci.yml` : <https://docs.gitlab.com/ci/yaml/> · `rules` : <https://docs.gitlab.com/ci/jobs/job_rules/> · `workflow` : <https://docs.gitlab.com/ci/yaml/workflow/>
- Variables, priorités et sécurité : <https://docs.gitlab.com/ci/variables/> · cache et artefacts : <https://docs.gitlab.com/ci/caching/>
- GitLab Runner, exécuteur Kubernetes : <https://docs.gitlab.com/runner/executors/kubernetes/> · chart Helm : <https://docs.gitlab.com/runner/install/kubernetes/> · création d'un runner par l'API : <https://docs.gitlab.com/api/users/#create-a-runner-linked-to-a-user>
- BuildKit *rootless* : <https://github.com/moby/buildkit/blob/master/docs/rootless.md> · manifestes Kubernetes amont : <https://github.com/moby/buildkit/tree/master/examples/kubernetes>
- Mailpit : <https://mailpit.axllent.org/docs/> · configuration SMTP de GitLab (paquet Linux) : <https://docs.gitlab.com/omnibus/settings/smtp/>
