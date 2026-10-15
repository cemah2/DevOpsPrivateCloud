# Durcissement des conteneurs : exécution, SELinux, moteur

| | |
|---|---|
| **Version** | 1.0 — 2026-10 (M12-E24 SEC-1350, M12-E25 SEC-1351, M12-E26 SEC-1352) |
| **Propriétaire** | Équipe Plateforme ; validation : Sophie Laurent |
| **Normes associées** | `docs/conteneurs/normes.md` (règles `CNT-RUN-*`, `CNT-HOTE-*`) |

## 1. Exécution (E24)

Mesures sur la pile Compose de MédiAgenda (`ctr01`), script d'essais `E24-tests-evasion.py` (11 gestes).

| Option (`compose.yaml`) | Ce qu'elle bloque (essai) | Ce qu'elle ne bloque pas |
|---|---|---|
| Utilisateur non root numérique (`USER 10001`, `user:`) | 2 `setuid(0)`, 3 `chown`, 4 `mknod`, écriture dans les dossiers de l'image | le jeu limite de capacités (récupérable par un setuid), `ptrace` |
| `cap_drop: [ALL]`, aucune `cap_add` | toute capacité, même via un binaire setuid (jeu limite vide) | les appels système sans capacité |
| `no-new-privileges:true` | 11 élévation par les 9 binaires setuid de l'image (`su`, `passwd`, `mount`…) | — |
| `read_only: true` + `tmpfs` bornés `noexec,nosuid,nodev` | 1 dépôt d'un binaire, 10 exécution d'un outil déposé dans `/tmp` | l'écriture de données dans le `tmpfs` (borné) |
| seccomp par défaut de Docker | 5 `mount`, 6 `unshare` (réservés à `CAP_SYS_ADMIN`), ~50 appels dangereux | `ptrace` (autorisé depuis le noyau 4.8) |
| seccomp `securite/seccomp-mediagenda.json` (défaut − `ptrace`) | 7 `ptrace`, `process_vm_readv/writev` | — |
| Chemins de `/proc` en lecture seule ou masqués par le moteur, aucun périphérique de l'hôte | 8 écriture dans `/proc/sysrq-trigger`, 9 lecture de `/dev/kmsg` | — |
| AppArmor `docker-default` (Debian, par défaut) | en double des précédents : montages, écritures dans `/proc/sys`, `/sys` | — |
| `pids_limit: 256` | bombe *fork* | — |

Résultat : **0 geste possible** sur 11 dans le conteneur de l'API. Capacités ajoutées : **aucune** (PostgreSQL et Valkey démarrent directement sous leur UID 999 : leur script d'entrée ne fait `chown` et `gosu` que s'il est root ; condition : volume appartenant à 999, vrai pour un volume nommé créé par Docker).

Profil seccomp : régénéré par `securite/generer-seccomp.sh` à chaque version de Docker (profil officiel de la version, étiquette `docker-v<VERSION>` du dépôt `moby/moby`, moins **une** règle ; le script échoue si la structure change).

Podman sans privilège (`ctr02`) : mêmes options (`--cap-drop all`, `--read-only`, `--security-opt no-new-privileges`, même profil seccomp) ; l'UID 10001 du conteneur est l'UID 534288 de l'hôte (plage subordonnée d'`app`) : un geste réussi n'aurait de pouvoir que dans l'espace de noms d'`app`.

## 2. SELinux sur la famille RHEL (E25)

Règles de Sophie Laurent :
1. SELinux n'est **jamais** désactivé, ni globalement (`setenforce 0`), ni pour un conteneur (`label=disable`, `--privileged` qui donne `spc_t`).
2. **Pas** de réétiquetage à la volée de répertoires de l'hôte (`:z`, `:Z`) en dehors des essais.
3. Un accès inhabituel = une **politique dédiée** (udica), versionnée, relue, révocable.

| Option | Effet sur l'hôte | Verdict |
|---|---|---|
| Rien | dossier en `var_t` (`/srv`) : `container_t` refusé (AVC `write` sur `dir`) | — |
| `:Z` | dossier et contenu réétiquetés `container_file_t:s0:cX,cY` (catégories du conteneur) ; un second conteneur est refusé ; perdu au premier `restorecon` ; **catastrophique** sur `/home`, `/etc` | essais seulement |
| `:z` | `container_file_t:s0` (tous les conteneurs) ; perdu au premier `restorecon` | essais seulement |
| `semanage fcontext -t container_file_t` + `restorecon` | étiquette **de la politique**, durable, versionnée (rôle `selinux_conteneurs`) | **retenu** pour les dossiers de données dédiés (`/srv/legacy-rdv/uploads`) |
| udica (`legacy_rdv.process`) | aucun changement sur les fichiers ; module CIL qui ajoute à `container_t` la lecture de `user_home_t` et le port 8080 | **retenu** pour le dépôt SFTP d'InfoGér (`/home/app/depot-infoger`, étiquette conservée) |
| `label=disable`, `--privileged` | plus aucun contrôle SELinux | **interdit** |

Diagnostic d'un refus : `sudo ausearch -m AVC -ts recent | audit2why` (source, cible, classe, permission) ; `matchpathcon <chemin>` (ce que la politique veut) ; `ls -Z` (ce qui est posé) ; refus masqués : `semodule -DB` puis `semodule -B`. Jamais `audit2allow -M` sans relecture.

## 3. Moteur Docker (E26)

- **Accès au socket = root.** Groupe `docker` : `admin` seul (il a déjà `sudo` ; seul écart : pas de trace `sudo`, compensée par l'audit) ; sur `runner02`, `admin` et le compte du runner. Jamais un compte de service, de supervision ou de développeur ; jamais le socket monté dans un conteneur.
- **Jamais de TCP.** Administration distante par SSH (`DOCKER_HOST=ssh://…`). Constat : Docker 29.8.2 démarre encore avec `-H tcp://0.0.0.0:…` sans TLS (avertissements et démarrage ralenti) : la version ne nous protège pas.
- **Options du démon** (`docker_engine_daemon_extra`) : `live-restore` (les conteneurs survivent au redémarrage du démon ; mesuré), `icc: false` (réseau `bridge` par défaut **seulement** ; les piles Compose s'isolent par leurs propres réseaux), `no-new-privileges` par défaut, journaux avec rotation (E18).
- **`userns-remap` : non retenu** sur `ctr01` et `runner02`. Mesuré : Docker 29 désactive alors le stockage d'images containerd, range images, conteneurs et volumes à part (le registre « disparaît »), refuse `--network host`. La protection équivalente vient de Podman sans privilège sur les serveurs (ADR-0120).
- **Docker sans privilège : non retenu** (évalué : un démon par utilisateur, cgroups délégués à configurer, outillage tiers à reconfigurer ; Podman fait mieux la même chose).
- **Audit** (rôle `audit_conteneurs`, clé `docker`) : écritures dans `/etc/docker`, `/etc/containerd`, unités systemd, binaires du moteur ; exécution du client (`docker-cli`) avec l'`auid` de l'humain. Une règle sur le socket ne trace **pas** les appels d'API (`connect()`) : ceux-ci se lisent dans `docker events`.
