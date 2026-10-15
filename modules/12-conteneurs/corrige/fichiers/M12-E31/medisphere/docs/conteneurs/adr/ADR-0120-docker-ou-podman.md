# ADR-0120 — Docker ou Podman sur les serveurs (et pour la CI)

| | |
|---|---|
| **Statut** | Accepté |
| **Date** | 2026-10 |
| **Décideurs** | Claire Morel ; consultés : Karim Benali, Sophie Laurent, Julien Petit |
| **Ticket** | PLAT-1357 |

## Contexte

Hors Kubernetes (qui utilisera containerd directement, M14), MédiSphère fait tourner des conteneurs sur : des **serveurs de recette et d'outillage** (MédiAgenda, Legacy-RDV, MédiAnnuaire), le **registre Harbor** (M13, installateur fondé sur Docker Compose), la **CI** (`runner02`, exécuteur `docker`), et les **postes** des développeurs. Exigences de Sophie : rien ne tourne en root sans nécessité, SELinux *enforcing* sur la famille RHEL (cible de l'hébergeur HDS), journaux exploitables, mises à jour suivies. Exigences de Karim : reproductibilité, un outillage commun, une équipe qui sait dépanner. Faits du module : Debian 13 livre Podman **5.4** (sans `podman quadlet install`), Rocky 10 Podman **5.8** ; Docker 29.8 vient du dépôt amont (`download.docker.com`).

## Critères et options

Notes de 1 à 5, pondération de 1 à 3. O1 = Docker partout ; O2 = Podman partout ; O3 = **Podman sur les serveurs, Docker pour la CI et les outils qui l'imposent**.

| Critère | Poids | O1 Docker | O2 Podman | O3 mixte | Fait (exercice) |
|---|---|---|---|---|---|
| Sécurité par défaut (démon root, sans privilège, SELinux) | 3 | 2 | 5 | 4 | socket = root (E26) ; *userns-remap* coûteux sous Docker 29 (E26) ; Podman sans privilège natif, SELinux et udica (E06, E25) |
| Intégration systemd, mise à jour et retour arrière automatiques | 3 | 2 | 5 | 5 | Quadlet (E14), `AutoUpdate=registry` + `Notify=healthy` (E30) ; Docker : `restart:` seulement |
| Compatibilité Compose et outils tiers | 2 | 5 | 2 | 4 | Harbor exige `docker compose` (M13) ; pile Compose de E08/E30 |
| Construction d'images en CI sans privilège | 2 | 4 | 4 | 4 | BuildKit sans privilège dans l'exécuteur `docker` (E21) ; Buildah aussi (E13) |
| Supervision et journaux | 2 | 4 | 4 | 4 | métriques du démon, `docker events` (E28) ; `podman events`, journald (E14, E28) |
| Mises à jour (paquets, versions disponibles) | 2 | 4 | 3 | 3 | Docker amont 29.8 ; Podman figé par la distribution (5.4 sur Debian 13) (E02) |
| Écosystème, documentation, compétences | 1 | 5 | 3 | 4 | équipe formée sur les deux dans ce module |
| **Total pondéré** (sur 75) | | **51** | **59** | **61** | |

## Décision

**O3.** Sur les **serveurs** qui font tourner des applications hors Kubernetes : **Podman sans privilège + Quadlet**, compte applicatif dédié sans `sudo`, SELinux *enforcing* sur la famille RHEL, mise à jour automatique fondée sur la santé en recette. Pour la **CI** (`runner02`) : **Docker**, exécuteur `docker`, jamais privilégié, constructions par BuildKit sans privilège (E21), socket jamais exposé aux jobs. **Exception bornée** : les outils dont l'installation est fondée sur Docker Compose (**Harbor sur `reg01`**, M13) utilisent Docker, avec le durcissement de E26 (groupe `docker` restreint, `no-new-privileges`, `live-restore`, audit). **Postes** des développeurs : libres (Docker Desktop ou Podman), mais les fichiers livrés (Dockerfile, `compose.yaml`) suivent les normes et sont construits par la CI.

Devenir des hôtes : `ctr01` (Docker) reste jusqu'à M13-E02 comme registre de travail puis est détruit ; `ctr02`/`ctr03` (Podman) sont le modèle des serveurs de recette ; `runner02` garde Docker ; `reg01` (M13) reçoit Docker au titre de l'exception.

## Conséquences

- **Négatives** : deux moteurs à maintenir (deux rôles Ansible, deux sondes dans `ms-verif-conteneurs`) ; Podman de Debian 13 en 5.4 (pas de `podman quadlet install`, corrections tardives) — réévaluer à Debian 14 ou passer les serveurs applicatifs sur Rocky ; les piles Compose (E08, E30) doivent être traduites en Quadlet pour les serveurs (`podman kube play` ou unités écrites) ; l'exception Harbor maintient un démon root sur un hôte du socle.
- **Actions** : normes de conteneurisation (E33) indépendantes du moteur ; Harbor sur `reg01` avec le rôle `docker_engine` durci (M13) ; exécuteurs CI sur Kubernetes, sans démon partagé (M19) ; contrôle automatique des options de durcissement des deux moteurs (M26) ; revue de cette ADR à la sortie de Debian 14 ou si Harbor propose une installation sans Docker.
