# AVANCEMENT.md — État de production

Statuts : `à faire` · `rédigé` · `harmonisé` · `relu` · `validé apprenant` (testé sur le vrai lab)

## Fondations

| Élément | Statut | Remarques |
|---|---|---|
| PLAN.md | rédigé | Versions des outils hors bloc A à figer au démarrage de chaque bloc |
| CONVENTIONS.md | rédigé | À ajuster après les retours sur le module 00 |
| lab/ (check, break, check-lib, lab.env.example) | rédigé | Bloc A : `lab/lib/pannes-lib.sh` (pannes des modules 01+), fonctions `gitlab_api`/`netbox_api`, variables du bloc A dans `lab.env.example` |
| annexes/ | en cours | `versions-bloc-A.md` rédigé ; prerequis.md, certifications.md, glossaire.md : à produire en fin de bloc A |

## Modules

| # | Module | Statut | Exercices | Remarques |
|---|---|---|---|---|
| 00 | Positionnement et montage du lab | relu | 50 | Relecture indépendante complète (§11). Restent à confirmer sur matériel réel : `GET /pools/{poolid}` déprécié (check-E17, E50), statut du stockage PBS avec ACL limitée au namespace (E22), format de la paperkey (E36), résolveur de l'image genericcloud Debian 13. Points « à vérifier sur ta version » signalés dans les corrigés |
| 01 | Git et workflow professionnel | en cours | 46 + mini-projet | |
| 02 | Scripting d'automatisation | en cours | 45 + mini-projet | |
| 03 | Images dorées | à faire | 24 + mini-projet | |
| 04 | Gestion de configuration (Ansible) | à faire | 45 + mini-projet | |
| 05 | Infrastructure as Code (OpenTofu) | à faire | 45 + mini-projet | |
| 06 | Services socle | à faire | 45 + mini-projet | |
| 07-11 | Bloc B | à faire | | |
| 12-18 | Bloc C | à faire | | |
| 19-20 | Bloc D | à faire | | |
| 21-23 | Bloc E | à faire | | |
| 24-26 | Bloc F | à faire | | |
| 27-29 | Bloc G | à faire | | |
| F1-F7 | Finaux | à faire | | |

## Retours de l'apprenant en attente

| Module | Exercice | Problème | Statut |
|---|---|---|---|
| — | — | — | — |

## Journal

| Date | Conversation | Travail |
|---|---|---|
| 2026-10-03/04 | 1 (fondations) | Plan, conventions, outillage lab, module 00 complet (4 rédacteurs + harmonisation + relecture indépendante), règles 9-12 ajoutées à la grille de relecture |
| 2026-10-03 | 2 (bloc A) | Versions du bloc A figées (recherche web), décisions structurantes dans PLAN §4.8 et journal (MinIO → SeaweedFS, `runner01`, `dns02`, AWX en fiche/Semaphore, Molecule sur VMs Proxmox), README et cartes d'exercices des modules 01 à 06, bibliothèque de pannes commune |

## Choix faits en l'absence de l'apprenant (bloc A)

- **Stockage S3 du socle** : MinIO prévu au plan est abandonné par son éditeur (édition communautaire sans binaires depuis octobre 2025, dépôt archivé). Remplacé par SeaweedFS (Apache 2.0, écritures conditionnelles nécessaires au verrou d'état OpenTofu). Garage écarté pour cette raison. Le module 05 en fait un ADR.
- **AWX** : figé depuis 2024 et lourd (Kubernetes) ; traité en fiche, l'orchestrateur pratiqué au module 04 est Semaphore UI.
- **Molecule** : instances = VMs Proxmox éphémères (pilote `default`), les conteneurs n'étant enseignés qu'au module 12.
- **GitLab** : installé en 19.3 puis monté en 19.4 au M01-E29 pour pratiquer une vraie montée de version.
- **CI du bloc A** : un runner `shell` permanent (`runner01`) ; les exécuteurs Docker/Kubernetes viendront aux modules 12 et 19.
- **TLS avant step-ca** : une CA provisoire `openssl` (M01) remplacée au M06.
- **Versions éditeur plutôt que Debian** pour PowerDNS (5.x), Kea (3.0), step-ca (0.30), NetBox (4.6, la 4.7 n'étant pas encore validée par la collection Ansible et le provider) : les paquets de Debian 13 sont obsolètes ou en fin de vie.
