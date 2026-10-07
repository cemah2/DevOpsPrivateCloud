# AVANCEMENT.md — État de production

Statuts : `à faire` · `rédigé` · `harmonisé` · `relu` · `validé apprenant` (testé sur le vrai lab)

## Fondations

| Élément | Statut | Remarques |
|---|---|---|
| PLAN.md | rédigé | Versions des outils hors bloc A à figer au démarrage de chaque bloc |
| CONVENTIONS.md | rédigé | À ajuster après les retours sur le module 00 |
| lab/ (check, break, check-lib, lab.env.example) | rédigé | Bloc A : `lab/lib/pannes-lib.sh` (pannes des modules 01+), fonctions `gitlab_api`/`netbox_api`, variables du bloc A dans `lab.env.example` |
| annexes/ | rédigé (bloc A) | `versions-bloc-A.md`, `prerequis.md` (graphe Mermaid 00-29/F1-F7, état laissé par chaque module du bloc A), `certifications.md` (LFCS, RHCSA, RHCE, Terraform Associate, GitLab ; CKA et suivants à compléter), `glossaire.md` (200 termes du bloc A) : à compléter à la fin de chaque bloc |

## Modules

| # | Module | Statut | Exercices | Remarques |
|---|---|---|---|---|
| 00 | Positionnement et montage du lab | relu | 50 | Relecture indépendante complète (§11). Restent à confirmer sur matériel réel : `GET /pools/{poolid}` déprécié (check-E17, E50), statut du stockage PBS avec ACL limitée au namespace (E22), format de la paperkey (E36), résolveur de l'image genericcloud Debian 13. Points « à vérifier sur ta version » signalés dans les corrigés |
| 01 | Git et workflow professionnel | relu | 46 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~50 vérifications sur la doc officielle et le code source de GitLab). À confirmer sur le lab : conservation d'un `gitlab.rb` pré-installation, titre des processus Puma, lecture de `application/settings` en `read_api`, libellés exacts des refus (hooks, ref cachée), effet de *Remove blobs* sur les diffs de MR, valeurs `unhealthy_*` du runner, `python3` sur `pbs01`, suppression différée des projets |
| 02 | Scripting d'automatisation | relu | 45 + mini-projet | 4 rédacteurs (le 4e relancé après interruption), harmonisation, relecture indépendante en 2 parties (~60 vérifications, projet de référence exécuté : 148 bats, 110+ pytest, ruff/ShellCheck/shfmt propres). À confirmer sur le lab : droits de `/run/lock`, visibilité des nœuds sans `Sys.Audit`, `uv --check-url` et `uv auth` avec le registre PyPI de GitLab, ACL PBS limitée au namespace, messages 401 de pveproxy |
| 03 | Images dorées | relu | 24 + mini-projet | 2 rédacteurs, harmonisation, relecture indépendante (~35 vérifications ; plugin Packer proxmox 1.2.4 compilé et `packer validate` complet sur tous les HCL, kickstart validé par `ksvalidator RHEL10`, sommes d'ISO et empreintes GPG vérifiées). À confirmer sur le lab : `boot_command` GRUB de Rocky 10.2, `qm set` cloud-init sur template, `user-tag-access`, format de dnf-automatic, régénération des clés sshd sur Debian 13 |
| 04 | Gestion de configuration (Ansible) | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~80 vérifications ; ansible-core 2.21.5/2.19, ansible-lint 26.9 profil production, Molecule 26.9 et Semaphore 2.19 exécutés, pytest de la collection et du module maison verts, filet anti-coupure du pare-feu testé). À confirmer sur le lab : ACL Proxmox de `wb-ansible`, enregistrement réel du runner, `qm terminal` sur `gw01`, délai `logger --tcp` (E41 v4), API `/project/users` de Semaphore |
| 05 | Infrastructure as Code (OpenTofu) | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~65 vérifications ; OpenTofu 1.13.1, Terragrunt 1.1.6, SeaweedFS 4.45/4.48 et AWS CLI exécutés : `validate`, `tofu test` 8/8, verrou `use_lockfile` et 412 `If-None-Match` constatés, chiffrement de l'état éprouvé ; règle sudo de `wb-tofu` corrigée et éprouvée). À confirmer sur le lab : `ciupgrade` avec un jeton non-root, attente de l'agent sur un clone, message de PVE 9 pour un VMID existant, affichage du rapport `terraform` en MR |
| 06 | Services socle | relu | 45 + mini-projet | 4 rédacteurs, harmonisation, relecture indépendante en 2 parties (~50 vérifications ; Kea 3.0.4, PowerDNS 5.0.7/Recursor 5.4.7, step-ca 0.30.2 et NetBox 4.6 exécutés, 138 pytest, ansible-lint production sur tous les rôles). À confirmer sur le lab : formats de sortie de `pdnsutil` 5.0, coexistence ancre `par1` / NTA `medisphere.internal`, authentification de l'écouteur HA de Kea, écrans NetBox de création des jetons, relecture à chaud des certificats NTS par chrony |
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
| 2026-10-03/04 | 2 (bloc A) | Versions du bloc A figées (recherche web), décisions structurantes dans PLAN §4.8 et journal (MinIO → SeaweedFS, `runner01`, `dns02`, AWX en fiche/Semaphore, Molecule sur VMs Proxmox), README et cartes d'exercices des modules 01 à 06, bibliothèque de pannes commune ; modules 01 à 06 rédigés, harmonisés, relus (session interrompue une fois par la limite d'utilisation, reprise sans perte) |
| 2026-10-07 | 2 (bloc A, clôture) | Annexes du bloc A ; contrôle global de cohérence : hôtes/VMID/IP conformes à PLAN §4.5, PLAN précisé (rôle DHCP de `dns01`, zone parente `medisphere.internal`, emplacement de l'ancre TLS de `pve01`), `lab.env.example` complet, `shellcheck -x` et `bash -n` propres sur tous les scripts, aucun secret ni cache versionné (`dump.rdb` retiré, `.gitignore` complété), README racine et REPRISE mis à jour |

## Choix faits en l'absence de l'apprenant (bloc A)

- **Stockage S3 du socle** : MinIO prévu au plan est abandonné par son éditeur (édition communautaire sans binaires depuis octobre 2025, dépôt archivé). Remplacé par SeaweedFS (Apache 2.0, écritures conditionnelles nécessaires au verrou d'état OpenTofu). Garage écarté pour cette raison. Le module 05 en fait un ADR.
- **AWX** : figé depuis 2024 et lourd (Kubernetes) ; traité en fiche, l'orchestrateur pratiqué au module 04 est Semaphore UI.
- **Molecule** : instances = VMs Proxmox éphémères (pilote `default`), les conteneurs n'étant enseignés qu'au module 12.
- **GitLab** : installé en 19.3 puis monté en 19.4 au M01-E29 pour pratiquer une vraie montée de version.
- **CI du bloc A** : un runner `shell` permanent (`runner01`) ; les exécuteurs Docker/Kubernetes viendront aux modules 12 et 19.
- **TLS avant step-ca** : une CA provisoire `openssl` (M01) remplacée au M06.
- **Versions éditeur plutôt que Debian** pour PowerDNS (5.x), Kea (3.0), step-ca (0.30), NetBox (4.6, la 4.7 n'étant pas encore validée par la collection Ansible et le provider) : les paquets de Debian 13 sont obsolètes ou en fin de vie.
- **Module 01** : méthode de fusion d'équipe `rebase_merge` (commit de fusion, historique semi-linéaire) ; Admin Mode activé en E31 (jetons avec portée `admin_mode` ensuite) ; hooks serveur sur `plateforme/*` seulement ; sauvegarde applicative de GitLab vers PBS (`proxmox-backup-client`) en plus de la sauvegarde de VM ; runbooks RB-010 à RB-013.
- **Module 02** : CA de `pve01` refusée par Python 3.13 (pas d'extension *Key Usage*, bogue Proxmox 6701) : le module fait construire une ancre de confiance conforme (M02-E08) utilisée par tous les outils Python ; scripts de panne qui mémorisent l'empreinte des fichiers posés pour que `--annuler` n'écrase pas une réparation (`corrige/pannes/_m02-reparations.sh`).
- **Module 03** : ISO déposées par script (`outils/deposer-iso.sh`) plutôt que téléchargées par Proxmox (contrôle de la somme et de la signature côté build) ; clones complets pour les VMs durables (PLAN, journal du 2026-10-07).
- **Module 04** : Semaphore UI pratiqué mais **non retenu** (ADR-0040 : application par la CI seule) — `sem01` est détruite en fin de module ; deux identités Vault (`lab`, `critique`) ; l'inventaire par défaut devient dynamique (Proxmox) dès M04-E13.
- **Module 05** : `gw01` reste hors IaC (ADR-0051) ; l'ordre de démarrage des VMs (exige `Sys.Modify` sur `/`) est posé en root et ignoré par OpenTofu ; environnements protégés de GitLab absents en CE → protection par branche protégée + job manuel + variables protégées + `resource_group` ; montée délibérée de `bpg/proxmox` en 0.116 en M05-E31.
- **Module 06** : CA provisoire retirée dès M06-E03 ; zones générées par le code (OpenTofu, Kea DDNS) gérées en mode API par le rôle PowerDNS pour ne jamais être écrasées ; NetBox devient l'inventaire Ansible par défaut (M06-E12).
