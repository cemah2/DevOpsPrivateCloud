# Module 12 — Introduction : les conteneurs

## « Pareil sur mon poste, en recette et en production »

Lundi, 9 h 10. Le bloc B est derrière toi : la bordure est redondante, `ceph-par1` tourne (et s'arrête proprement), OpenStack et la chaîne de provisioning ont été recettés puis rangés dans le code. Il manque encore une chose à MédiSphère pour livrer vite et sûrement : une **unité de livraison** commune à toutes les équipes. Claire Morel a réuni l'équipe Plateforme et Julien Petit.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Conteneurs — une seule façon de livrer une application
>
> Bonjour,
>
> Aujourd'hui, chaque équipe livre à sa manière : une archive et une page de consignes pour MédiAgenda, un binaire Go copié à la main pour MédiDoc, et Legacy-RDV, que plus personne n'ose redémarrer depuis qu'InfoGér est parti. Julien résume le problème mieux que moi : « ça marche sur mon poste, en recette ça dépend du jour, en production on croise les doigts ».
>
> J'ai pris la décision suivante : **avant l'arrivée de Kubernetes, toutes les applications de MédiSphère seront livrées en images de conteneurs**, construites par la CI, stockées dans un registre, exécutées de la même façon partout.
>
> Ce que je veux à la fin du module :
> 1. des hôtes de conteneurs créés et configurés par le code : un hôte **Docker**, deux hôtes **Podman** sans privilège (Debian et Rocky Linux avec SELinux), et la VM historique de Legacy-RDV reproduite à l'identique pour l'étudier ;
> 2. les quatre applications (MédiAgenda, MédiDoc, MédiNotif, Legacy-RDV) **conteneurisées**, avec des images minimales, non root, reproductibles, multi-architectures quand c'est utile ;
> 3. une **pile de recette** de MédiAgenda (application, PostgreSQL, Valkey) qui démarre d'une commande ;
> 4. des images construites **en CI, sans mode privilégié**, sur un nouveau runner du socle, `runner02`, et publiées dans un registre de travail (Harbor arrive au module 13) ;
> 5. l'exploitation : durcissement, supervision, sauvegarde, mise à jour sans interruption, dépannage, et nos **normes de conteneurisation** écrites.
>
> Sophie a trois exigences non négociables : pas de conteneur root sans justification écrite, pas de secret dans une image ni dans un dépôt, des images de base que nous maîtrisons. Karim rappelle la règle de la maison : « une VM, c'est OpenTofu ; une configuration, c'est un rôle Ansible testé ; une image, c'est un Dockerfile relu en MR et construit par la CI ». Nadia veut savoir quoi faire quand un conteneur redémarre en boucle à 3 h du matin.
>
> Premier jalon : les hôtes, puis les gestes de base (conteneurs, images, volumes, réseaux), un premier Dockerfile pour MédiAgenda et sa pile Compose. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 12, MédiSphère livre ses applications en conteneurs (étiquette **`conteneurs-v1`** du dépôt `plateforme/medisphere`), et le registre Harbor (M13) puis Kubernetes (M14) n'auront plus qu'à les recevoir :

- quatre VMs d'environnement, sur le VNet `vsandbox` : **`ctr01`** (Docker Engine 29, puis le registre de travail), **`ctr02`** (Podman 5.4 sans privilège, Buildah, Skopeo, Quadlet), **`ctr03`** (Rocky Linux 10, Podman 5.8, SELinux *enforcing*), **`legacy01`** (Legacy-RDV installé « à l'ancienne » : Apache, PHP 8.4, MariaDB) ;
- un hôte permanent de plus dans le socle, **`runner02`** (1012, 10.10.20.17), runner GitLab à exécuteur `docker`, sans mode privilégié (M12-E20) ;
- les projets GitLab des applications : `mediagenda/api`, `medidoc/medidoc`, `medinotif/worker`, `legacy/legacy-rdv`, chacun avec son Dockerfile, son `compose.yaml` de test et son pipeline de construction ;
- un registre de travail `registry:3` sur `ctr01` (TLS par step-ca), en attendant Harbor ;
- la documentation dans `docs/conteneurs/` : ADR-0120 (Docker ou Podman), normes de conteneurisation, runbooks RB-120 et suivants.

Le **palier 1** (ce fichier et [`01-decouverte.md`](01-decouverte.md)) crée les quatre hôtes par le code, puis fait pratiquer les gestes de base : cycle de vie d'un conteneur, anatomie d'une image OCI, premier Dockerfile, Podman sans privilège, volumes et réseaux, Compose. Il se ferme sur l'architecture interne des moteurs (de `docker run` jusqu'à `runc`).

## Architecture du module

```
                adm01 (1001) 10.10.10.10 — VLAN 10 MGMT : joint tout le lab (SSH, HTTP de test)
                ~/src/infra (envs/m12) · ~/src/ansible · ~/src/mediagenda-api · checks
                                    │
   ═══════════════════ gw01 / gw02 (VIP .1, VRRP) — routage, filtrage, NAT vers Internet ═════════════
          │                                      │                                     │
   VLAN 20 INFRA 10.10.20.0/24             VLAN 99 SANDBOX 10.10.99.0/24 (DHCP Kea, DDNS)      Internet
   git01 (.12) GitLab                      ─────┬───────────────┬───────────────┬──────────────┬───  docker.io
   ca01  (.11) step-ca (ACME)                   │               │               │              │     ghcr.io
   dns01/dns02 (.10/.16) DNS, Kea          ┌────┴─────┐  ┌──────┴─────┐  ┌──────┴─────┐  ┌─────┴──────┐ quay.io
   runner01 (.15) exécuteur shell          │ ctr01    │  │ ctr02      │  │ ctr03      │  │ legacy01   │ download.
   runner02 (.17) exécuteur docker (E20)   │ 2121     │  │ 2122       │  │ 2123       │  │ 2124       │ docker.com
                                           │ Debian 13│  │ Debian 13  │  │ Rocky 10   │  │ Debian 13  │
                                           │ Docker 29│  │ Podman 5.4 │  │ Podman 5.8 │  │ Apache     │
                                           │ containerd│ │ rootless   │  │ rootless   │  │ PHP 8.4    │
                                           │ Compose 5│  │ « app »    │  │ « app »    │  │ MariaDB    │
                                           │ :5000 reg│  │ Buildah    │  │ SELinux    │  │ Legacy-RDV │
                                           │ (E15)    │  │ Skopeo     │  │ enforcing  │  │ :80        │
                                           └──────────┘  │ Quadlet    │  └────────────┘  └────────────┘
                                                         └────────────┘
```

Points structurants :

- **Des hôtes jetables, sur `vsandbox`.** Les quatre VMs sont des VMs d'environnement (état OpenTofu à part, étiquette `env-m12`) : tu peux les détruire et les recréer à volonté, elles ne portent rien que le code ne sache reconstruire. Elles prennent leur adresse par **DHCP** (Kea, M06) et leur nom par le **DDNS** de Kea (`ctr01.par1.medisphere.internal`…) : c'est la première fois que le module `vm-noeud` doit savoir faire une carte en DHCP (M12-E02).
- **Deux moteurs, deux philosophies.** Docker est un **démon** (`dockerd`, root) qui pilote containerd ; Podman est **sans démon** : chaque commande crée ses conteneurs elle-même, et un compte ordinaire peut le faire sans aucun privilège. On pratique les deux pour pouvoir choisir en connaissance de cause (ADR-0120, M12-E31).
- **Sans privilège, pour de vrai.** Sur `ctr02` et `ctr03`, les conteneurs tournent sous le compte **`app`** (sans sudo) : le « root » d'un conteneur n'est, vu de l'hôte, qu'un UID ordinaire de la plage subordonnée de `app`.
- **Le vieux et le neuf côte à côte.** `legacy01` reproduit fidèlement la VM d'InfoGér, défauts compris : c'est le point de départ de la conteneurisation de Legacy-RDV (M12-E19), on n'y « corrige » rien.

### Hôtes du module

| Hôte | VMID | Système | Ressources | Étiquettes | Rôle Ansible | Exercice |
|---|---|---|---|---|---|---|
| `ctr01` | 2121 | Debian 13 | 2 vCPU, 2 Go, 32 Gio `local-nvme` | `env-m12`, `role-docker` | `docker_engine` | E02 |
| `ctr02` | 2122 | Debian 13 | idem | `env-m12`, `role-podman` | `podman_hote` | E02 |
| `ctr03` | 2123 | Rocky Linux 10 (CPU `x86-64-v3`) | idem | `env-m12`, `role-podman` | `podman_hote` | E02 |
| `legacy01` | 2124 | Debian 13 | idem | `env-m12`, `role-legacy` | `legacy_rdv` | E02 |
| `runner02` | **1012** (socle) | Debian 13 | 2 vCPU, 4 Go | `socle`, `role-runner` | `docker_engine`, `gitlab_runner` | E20 |

Les quatre VMs d'environnement sont sur `vsandbox` (VLAN 99), une seule carte, adresse par DHCP, **MAC imposée** `bc:24:11:99:12:0N` (N = 1 à 4) pour retrouver le même bail après une reconstruction. VMID du module : 2120-2129 (2125-2129 libres pour tes essais). Instances Molecule : 2046 (scénario `docker_engine`), 2047 (scénario `podman_hote`).

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur `gw01`/`gw02` |
|---|---|---|---|
| `adm01` → `ctr01-03`, `legacy01` (SSH, HTTP de test) | 22, 80, 8000-8099 | E02-E08 | existant : MGMT joint tout le lab |
| `ctr01-03`, `legacy01` → Internet (`download.docker.com`, `docker.io`, `ghcr.io`, `quay.io`, dépôts Debian et Rocky) | 443 | E02-E08 | existant (« lab vers Internet ») |
| `ctr01-03`, `legacy01` → `dns01`/`dns02` (DNS, DHCP) et passerelle (NTP) | 53, 67, 123 | E02 | existant |
| `ctr01-03` → `git01` (clonage HTTPS, si tu le choisis) | 443 | E05 | à ouvrir seulement si tu en as besoin (le palier 1 n'en a pas besoin : les sources arrivent depuis `adm01`) |

Aucun flux nouveau sur la bordure au palier 1. Les flux du module (registre de travail `ctr01:5000`, `runner02` vers Internet et vers le registre, ACME de `ctr01` vers `ca01`) arrivent au palier 2, par la matrice des flux.

---

## Le chemin imposé

1. **OpenTofu** : les quatre VMs sont dans un état à part, **`m12-conteneurs`** (dossier `envs/m12/` de `plateforme/infra`, clé d'état `envs/m12/terraform.tfstate`), avec le module **`vm-noeud`** de `plateforme/tofu-modules`, que tu étends en E02 pour accepter une carte en DHCP. `runner02` (E20), lui, va dans l'état `socle`.
2. **Ansible** : les hôtes entrent dans l'inventaire par leurs étiquettes NetBox (`env-m12`, `role-docker`, `role-podman`, `role-legacy`), dans une source d'inventaire à part ; les rôles communs (`base` sur Debian, `ssh_durci`, `ca_lab`, `ssh_ca_hote`, `ssh_ca_utilisateur`) s'appliquent comme ailleurs ; les rôles du module (`docker_engine`, `podman_hote`, `legacy_rdv`) sont testés par Molecule quand c'est possible.
3. **Les applications** : chaque application vit dans **son** projet GitLab (`mediagenda/api` dès E05). Son Dockerfile et son `compose.yaml` sont relus en MR comme du code ; le pipeline de construction arrive au palier 2 (E21). Tu édites sur `adm01`, dans `~/src/<projet>`, et tu synchronises vers l'hôte qui construit et exécute.
4. **Secrets** : jamais dans une image, jamais dans un dépôt, jamais en argument de commande. Fichiers 600 de `~/.config/workbook/` sur `adm01`, Ansible Vault (`lab`), secrets Compose dans un dossier ignoré par Git, puis variables protégées et masquées de la CI (palier 2).
5. **Documentation** : dans `plateforme/medisphere`, dossier **`docs/conteneurs/`** (fiches, runbooks RB-120 et suivants, ADR-0120, normes) ; le journal de diagnostic et les post-mortems restent dans `docs/socle/journal/` et `docs/socle/post-mortems/`.

Une manipulation à la main est permise pour **explorer** (c'est l'essentiel du palier 1 : `docker run`, `podman run`, `skopeo inspect`…), jamais pour **configurer un hôte** : un paquet, un fichier de `/etc`, un compte, c'est un rôle Ansible.

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Un conteneur, c'est un processus.** Pas une machine virtuelle : un processus Linux ordinaire, lancé par le noyau de l'hôte, à qui l'on a donné une **vue restreinte** du système (espaces de noms), des **limites** de ressources (cgroups) et des **droits réduits** (capacités, seccomp, LSM). `ps` sur l'hôte le montre ; il n'y a pas de second noyau.

**Espaces de noms (*namespaces*).** Chacun isole une ressource : `mnt` (points de montage, donc l'arborescence vue), `pid` (numéros de processus : le premier processus du conteneur est le PID 1), `net` (interfaces, routes, ports), `uts` (nom d'hôte), `ipc`, `user` (identifiants : root dans le conteneur, UID ordinaire dehors), `cgroup` (vue de la hiérarchie des cgroups), `time`. Un conteneur est un processus placé dans un jeu d'espaces de noms ; `nsenter` permet d'y entrer.

**cgroups v2.** La hiérarchie unique `/sys/fs/cgroup` qui **compte et limite** ce que consomme un groupe de processus : mémoire (`memory.max`, et le tueur OOM du cgroup), CPU (`cpu.max`, `cpu.weight`), nombre de processus (`pids.max`), E/S. Debian 13 et Rocky 10 sont en cgroup v2 seul ; Docker 29 déprécie le v1, Kubernetes 1.35 le refuse.

**Capacités, seccomp, LSM.** Les **capacités** découpent les pouvoirs de root (`CAP_NET_BIND_SERVICE`, `CAP_SYS_ADMIN`…) : un conteneur n'en reçoit qu'une partie. **seccomp** filtre les appels système (le profil par défaut de Docker et de Podman en bloque une quarantaine, comme `keyctl` ou `kexec_load`). Les **LSM** ajoutent un contrôle obligatoire : AppArmor sur Debian, SELinux sur Rocky (type `container_t`, catégories MCS par conteneur). Le palier 3 les durcit.

**Image OCI.** Un **empilement de couches** (archives tar de différences de systèmes de fichiers), une **configuration** (commande, variables, utilisateur, ports, historique), un **manifeste** qui liste la configuration et les couches par leur **empreinte** SHA-256, et souvent un **index** (*manifest list*) qui pointe vers un manifeste par plateforme (`linux/amd64`, `linux/arm64`…). Tout est **adressé par le contenu** : une empreinte désigne un contenu exact, pour toujours ; une **étiquette** (`:3.13-slim-trixie`) n'est qu'un nom qui peut changer de cible.

**Registres et distribution.** Un registre sert des manifestes et des blobs par une API HTTP normalisée (*OCI Distribution Specification*) : `GET /v2/<nom>/manifests/<étiquette ou empreinte>`, `GET /v2/<nom>/blobs/<empreinte>`. Docker Hub (`docker.io`), GitHub (`ghcr.io`), Quay (`quay.io`) en sont ; `registry:3` (M12-E15) et Harbor (M13) aussi.

**Runtime OCI : runc, crun.** Le programme de bas niveau qui reçoit un **bundle** (un dossier racine + un `config.json` décrivant espaces de noms, cgroups, montages, capacités) et crée le processus isolé, puis s'efface. **runc** (Go) est celui de Docker et de containerd ; **crun** (C, plus léger) celui de Podman sur Rocky.

**containerd et le shim.** containerd gère le cycle de vie des images et des conteneurs pour Docker (et, plus tard, pour Kubernetes) ; pour chaque conteneur, il lance un **shim** (`containerd-shim-runc-v2`) qui appelle runc, garde le conteneur en vie si containerd redémarre, et remonte son code de sortie. Depuis **Docker 29**, les images d'une nouvelle installation sont aussi stockées par containerd (*containerd image store*) : `docker info` l'affiche, et les images multi-plateformes et leurs attestations sont conservées localement.

**Podman.** Même format d'images, même runtime, mais **pas de démon** : `podman run` fait le travail lui-même et laisse un petit superviseur, **conmon**, par conteneur. Un compte ordinaire l'utilise **sans privilège** grâce à l'espace de noms `user` (plages `/etc/subuid`, `/etc/subgid`) et à **pasta** pour le réseau. Il sait aussi faire des **pods** (plusieurs conteneurs qui partagent un espace réseau) et s'intègre à systemd par **Quadlet** (palier 2). **Buildah** construit des images sans démon ; **Skopeo** inspecte et copie des images entre registres, archives et stockages locaux sans les « tirer ».

**Volumes et réseaux.** Le système de fichiers d'un conteneur est jetable : ce qui doit survivre va dans un **volume** (géré par le moteur) ou un **montage lié** (*bind mount*, un dossier de l'hôte). Les conteneurs d'un même **réseau défini** se trouvent par leur nom (DNS intégré) ; publier un port (`-p 8000:8000`) fait écrire au moteur des règles de NAT dans le pare-feu de l'hôte.

**Compose.** Un fichier `compose.yaml` (spécification Compose, sans attribut `version:`) décrit une pile : services, réseaux, volumes, secrets, dépendances avec conditions de santé. **Compose v5** (Docker) en est l'implémentation de référence ; il délègue désormais la construction à Buildx/Bake.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | Docker Engine **29.8.x** (`docker-ce` `5:29.8.2-1~debian.13~trixie`), `containerd.io` **2.3.x** (LTS, runc 1.5 inclus), Buildx **0.37.x**, Compose **5.6.x**, du dépôt `download.docker.com/linux/debian` suite `trixie` (clé d'empreinte `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`) ; Podman **5.4.x**, Buildah **1.39.x**, Skopeo **1.18.x** (Debian 13) ; Podman **5.8.x** (Rocky 10) ; PHP 8.4 et MariaDB 11.8 (Debian 13) |
| Changements de version | [`annexes/versions-bloc-C.md`](../../../annexes/versions-bloc-C.md), parties « Docker Engine 29 », « Compose v5 », « Podman » : stockage d'images containerd par défaut, API minimale 1.44 (`docker-compose` v1 refusé), backend nftables expérimental, TCP sans TLS refusé ; Compose v5 délègue la construction à Bake ; Podman 5 en pasta, Netavark, SQLite ; `podman quadlet install` absent de la 5.4 |
| Images de référence | `docker.io/library/debian:trixie-slim`, `docker.io/library/python:3.13-slim-trixie`, `docker.io/library/golang:1.26-trixie`, `docker.io/library/postgres:18-trixie`, `docker.io/valkey/valkey:8-trixie`, `docker.io/library/nginx:1.30-trixie`, `docker.io/library/php:8.4-apache-trixie` ; `ghcr.io/astral-sh/uv:0.12.x` (binaire d'uv) |
| Code | `plateforme/tofu-modules` : `vm-noeud` **v2.4.0** (carte DHCP) ; `plateforme/infra` : `envs/m12/` ; `plateforme/ansible` : rôles `docker_engine`, `podman_hote`, `legacy_rdv`, playbooks `conteneurs.yml` et `legacy-rdv.yml`, source d'inventaire `inventories/lab/netbox-m12.yml`, `group_vars/role_docker/`, `role_podman/`, `role_legacy/`, scénarios Molecule `docker_engine` et `podman_hote` ; **`mediagenda/api`** (créé en E05) |
| Groupes d'inventaire | `env_m12` (les quatre hôtes), `role_docker` (`ctr01`), `role_podman` (`ctr02`, `ctr03`), `role_legacy` (`legacy01`) |
| Comptes | `admin` (sudo, groupe `docker` sur `ctr01`) ; **`app`** (UID 1001, **sans sudo**, linger actif) sur `ctr02` et `ctr03`, plage subordonnée `524288:65536` dans `/etc/subuid` et `/etc/subgid` |
| Docker sur `ctr01` | `/etc/docker/daemon.json` géré par le rôle : journaux `json-file` avec rotation (10 Mo × 3), réseaux des conteneurs dans `172.20.0.0/14` en /24 (`default-address-pools`) ; versions épinglées (`/etc/apt/preferences.d/docker.pref`) |
| Podman sur `ctr02`/`ctr03` | `/etc/containers/registries.conf.d/50-medisphere.conf` (un seul registre de recherche, `docker.io`, `short-name-mode = "enforcing"`) ; `/etc/containers/containers.conf.d/50-medisphere.conf` (pasta, journald, systemd) |
| Legacy-RDV sur `legacy01` | code dans `/var/www/legacy-rdv`, journal `/var/log/legacy-rdv/app.log`, base `legacy_rdv` (MariaDB locale), hôte virtuel et cron d'InfoGér tels quels ; mot de passe de la base en Vault `lab` (`vault_legacy_rdv_db_mdp`, égal à celui de `config.php`) |
| Secrets du palier 1 | Vault `lab` : `vault_legacy_rdv_db_mdp` (`group_vars/role_legacy/vault.yml`) ; pile Compose de MédiAgenda : `~/src/mediagenda-api/secrets/` sur `ctr01` (dossier 700, ignoré par Git) |
| Documentation | `docs/conteneurs/` dans `plateforme/medisphere` : fiche des hôtes (E02), puis runbooks RB-120 (conteneur en boucle) et suivants, ADR-0120, normes (palier 3) |
| Brouillons | `~/m12/eXX/` sur `adm01` et sur les hôtes de conteneurs (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05) |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<VERSION-TOFU-MODULES>` | Étiquette publiée par ta MR de `vm-noeud` (v2.4.0 si rien d'autre n'a été publié depuis M10) |
| `<EMPREINTE>` | Une empreinte `sha256:…` relevée par toi (elles changent à chaque reconstruction d'une image publique) |

### Variables de `lab/lab.env`

Aucune variable nouvelle au palier 1. Les vérifications utilisent `WB_PVE_HOST` (configuration des VMs), `WB_SRC` (copies de travail), les jetons en lecture de GitLab et de NetBox, et SSH en `admin` vers les hôtes du module (`sudo -n` pour lire ce qui appartient à `app`).

---

## Règles du module

1. **Rien de « latest ».** Une image se désigne par son nom **complet** (`docker.io/library/debian:trixie-slim`, jamais `debian`) et une étiquette précise ; quand la reproductibilité compte, par son empreinte. Un paquet se désigne par sa version.
2. **Pas de `curl … | sh`, pas de clé non vérifiée.** Le dépôt de Docker s'installe avec sa clé, contrôlée par son empreinte ; les binaires (Hadolint, Dive au palier 2) par leur somme SHA-256.
3. **Le groupe `docker`, c'est root.** Quiconque peut parler au socket `/var/run/docker.sock` peut monter `/` de l'hôte dans un conteneur. On n'y met que des comptes qui ont déjà sudo (`admin`) ; jamais un compte applicatif, jamais un socket exposé en TCP (M12-E26).
   > ⚠️ **Attention** : ne monte jamais `/var/run/docker.sock` dans un conteneur « pour voir » : ce conteneur devient root sur `ctr01`.
4. **Pas de secret en clair** : ni dans un Dockerfile (`ENV`, `ARG`), ni dans `compose.yaml`, ni dans une commande (`-e MOT_DE_PASSE=…` se lit dans `docker inspect` et dans l'historique du shell). Fichier en 600 ou dossier en 700 hors dépôt, ou Vault.
5. **On nettoie derrière soi, en sachant ce qu'on efface.** `docker system prune`, `podman system reset`, `docker volume rm` détruisent sans corbeille.
   > ⚠️ **Attention** : `podman system reset` (en tant que `app`) supprime **toutes** ses images, ses conteneurs et ses volumes ; `docker volume prune -a` supprime les volumes non utilisés, dont la base de la pile de recette si elle est arrêtée. Liste d'abord (`docker volume ls`, `podman volume ls`).
6. **Mémoire.** Le module demande le socle v2 (≈ 27 Go) + 4 × 2 Go ≈ 35 Go, puis `runner02` (4 Go) à partir de E20. Avant de commencer, **arrête `ceph-par1`** selon la procédure du module 08 (introduction, règle 3) s'il tourne encore, et vérifie qu'aucun profil lourd (cluster `hv-par1`, OpenStack) n'est démarré.

---

## Préparer `adm01`

Les outils viennent des modules précédents ; ce module n'installe **rien** sur `adm01` (les moteurs de conteneurs vivent sur les hôtes du module). Vérifie avant de commencer :

```
admin@adm01:~$ lab/bin/check 07 46
admin@adm01:~$ cd ~/src/infra && tofu version
admin@adm01:~$ cd ~/src/ansible && uv run ansible-inventory --graph socle
admin@adm01:~$ ssh -o BatchMode=yes root@pve01 'qm list | grep -E "gold" ; pvesh get /cluster/resources --type vm --output-format json | jq -r ".[] | select(.status==\"running\") | .name" | sort'
admin@adm01:~$ ls ~/DevOpsPrivateCloud/apps/
```

Le premier contrôle (mini-projet du module 07) doit être vert : ce module s'appuie sur la bordure (`socle-v2`). Le quatrième montre tes images dorées (il en faut une `debian13` et une `rocky10` étiquetées `current`) et les VMs démarrées : seules celles du socle doivent tourner. Le dernier montre les quatre applications du workbook (`legacy-rdv`, `mediagenda`, `medidoc`, `medinotif`) : si ta copie du dépôt est ancienne, mets-la à jour (`git pull`).

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 12 <XX>`. Elles sont en lecture seule : configuration Proxmox lue sur `pve01`, état des hôtes en SSH (`docker inspect`, `podman ps`, `ps`, fichiers de configuration), requêtes HTTP vers les conteneurs publiés, DNS, NetBox et GitLab en lecture. Elles ne lancent **aucun** conteneur.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M12-EXX/` : `ansible/` reproduit l'arborescence de `plateforme/ansible`, `infra/` celle de `plateforme/infra`, `tofu-modules/` celle de `plateforme/tofu-modules`, **`mediagenda-api/` celle du projet `mediagenda/api`**. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E07 ─ E08 ─ E09
              └──── E06 (dès que ctr02 existe)
```

1. **E01** — positionnement, à froid.
2. **E02** — les hôtes : tout le reste en dépend.
3. **E03 → E05** — dans l'ordre, sur `ctr01` : conteneurs, images, premier Dockerfile.
4. **E06** — Podman sans privilège sur `ctr02` : indépendant de E03-E05, à intercaler quand tu veux après E02.
5. **E07 → E08** — volumes et réseaux, puis la pile Compose de MédiAgenda (qui réutilise l'image de E05).
6. **E09** — en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 12 à 16 heures.

## Pour aller plus loin

- Espaces de noms et cgroups : `man 7 namespaces`, `man 7 user_namespaces`, `man 7 cgroups`, et la documentation du noyau <https://docs.kernel.org/admin-guide/cgroup-v2.html>
- Spécifications OCI : image <https://github.com/opencontainers/image-spec>, runtime <https://github.com/opencontainers/runtime-spec>, distribution <https://github.com/opencontainers/distribution-spec>
- Docker Engine : <https://docs.docker.com/engine/> · notes de version 29 : <https://docs.docker.com/engine/release-notes/29/> · stockage containerd : <https://docs.docker.com/engine/storage/containerd/>
- Compose : spécification <https://compose-spec.io/> · documentation <https://docs.docker.com/compose/>
- Podman : <https://docs.podman.io/> · le tutoriel sans privilège <https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md>
- containerd : <https://containerd.io/docs/> · runc : <https://github.com/opencontainers/runc>
