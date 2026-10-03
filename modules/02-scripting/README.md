# Module 02 — Scripting d'automatisation

| | |
|---|---|
| **Bloc** | A — Fondations automatisées |
| **Niveau** | Cœur |
| **Profil de lab** | Socle (VMs jetables 2020-2029) |
| **Prérequis** | Module 01 (forge GitLab, `runner01`, pre-commit, semantic-release) |
| **Durée indicative** | 35 à 45 heures |

## Contexte MédiSphère

Au module 00, tu as écrit quelques scripts « qui marchent chez toi » (`vm-api.sh`, sauvegarde de configuration, mesures). Ils sont fragiles, non testés, éparpillés. Karim Benali lance le projet **`plateforme/outils`** : tous les scripts d'exploitation de l'équipe y vivent, sont relus, testés en CI et livrés en versions. Deux familles d'outils y cohabitent : des scripts **Bash** robustes pour les gestes système, et une CLI **Python**, `medictl`, qui parle à l'API Proxmox pour l'inventaire et le cycle de vie des VMs du lab. Nadia Roussel a une seule exigence : un outil d'astreinte doit échouer **bruyamment et clairement**, jamais à moitié et en silence.

## Objectifs

À la fin de ce module, tu sais :
- écrire des scripts Bash robustes (mode strict, `trap`, gestion des erreurs, des arguments, des fichiers et des verrous) et les faire passer ShellCheck ;
- manipuler JSON et YAML en ligne de commande avec jq et yq ;
- structurer un projet Python moderne avec uv, écrire une CLI avec Typer et piloter l'API Proxmox avec proxmoxer ;
- tester des scripts Bash (bats) et du code Python (pytest, simulation de l'API) ;
- orchestrer les tâches du projet (Taskfile, Makefile) et les exécuter en CI ;
- empaqueter, versionner et distribuer un outil interne ;
- diagnostiquer les pannes typiques des scripts : environnement d'exécution, `set -e`, dépendances, droits d'API, performance.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M02-E01 | Test de positionnement : Bash et Python | Q | ★★ | 1 |
| M02-E02 | Créer le projet `plateforme/outils` | LAB | ★ | 1 |
| M02-E03 | Un script Bash robuste : mode strict, `trap`, codes retour, usage | LAB | ★ | 1 |
| M02-E04 | ShellCheck et shfmt : lire, corriger, configurer | LAB | ★ | 1 |
| M02-E05 | jq : interroger l'API Proxmox | LAB | ★★ | 1 |
| M02-E06 | yq : modifier du YAML sans le casser | LAB | ★ | 1 |
| M02-E07 | Un environnement Python moderne avec uv | LAB | ★ | 1 |
| M02-E08 | Premier client Python de l'API Proxmox, TLS vérifié | LAB | ★★ | 1 |
| M02-E09 | Questions : Bash ou Python ? | Q | ★★ | 1 |
| M02-E10 | Bibliothèque Bash commune `lib/ms-commun.sh` | LAB | ★★ | 2 |
| M02-E11 | `ms-snapshot` : instantanés du lab avant intervention | LAB | ★★ | 2 |
| M02-E12 | Traiter des fichiers en masse sans piège (espaces, `-print0`, tableaux) | LAB | ★★ | 2 |
| M02-E13 | Verrous, fichiers temporaires et exécutions concurrentes | LAB | ★★ | 2 |
| M02-E14 | Tester ses scripts Bash avec bats | LAB | ★★ | 2 |
| M02-E15 | CLI `medictl` avec Typer : lister et décrire les VMs | LAB | ★★ | 2 |
| M02-E16 | `medictl vm create/destroy` avec garde-fous | LAB | ★★★ | 2 |
| M02-E17 | Erreurs, journalisation et reprises en Python | LAB | ★★ | 2 |
| M02-E18 | Tester `medictl` avec pytest sans toucher à Proxmox | LAB | ★★ | 2 |
| M02-E19 | Configuration et secrets des outils | LAB | ★★ | 2 |
| M02-E20 | Taskfile (et Makefile) : les tâches du projet | LAB | ★★ | 2 |
| M02-E21 | Générer l'inventaire du socle depuis l'API | LIBRE | ★★★ | 2 |
| M02-E22 | Revue d'un script Bash du stagiaire | REV | ★★ | 2 |
| M02-E23 | Revue d'un script Python du stagiaire | REV | ★★ | 2 |
| M02-E24 | CI du projet outils : lint et tests sur `runner01` | LAB | ★★ | 3 |
| M02-E25 | Empaqueter, versionner et distribuer `medictl` | LAB | ★★★ | 3 |
| M02-E26 | Contrôle planifié des sauvegardes PBS avec un timer systemd | LAB | ★★ | 3 |
| M02-E27 | Idempotence et `--dry-run` | LIBRE | ★★★ | 3 |
| M02-E28 | Paralléliser sans se tirer une balle dans le pied | LAB | ★★★ | 3 |
| M02-E29 | Durcir un script lancé avec `sudo` | LAB | ★★★ | 3 |
| M02-E30 | Signaux, délais et sous-processus | LAB | ★★ | 3 |
| M02-E31 | Documenter un outil : aide, README, guide d'astreinte | RED | ★★ | 3 |
| M02-E32 | ADR : langages des outils de la plateforme | RED | ★★ | 3 |
| M02-E33 | Questions de production : outillage d'exploitation | Q | ★★★ | 3 |
| M02-E34 | Un script de vérification en temps limité | CHRONO | ★★★ | 3 |
| M02-E35 | Panne : le script marche à la main mais pas la nuit | BF | ★★ | 4 |
| M02-E36 | Panne : `medictl` ne parle plus à Proxmox | BF | ★★ | 4 |
| M02-E37 | Panne : le nettoyage a supprimé trop de choses | BF | ★★★ | 4 |
| M02-E38 | Panne : rouge en CI, vert en local | BF | ★★ | 4 |
| M02-E39 | Panne : `set -e` ne fait pas ce qu'on croit | BF | ★★★ | 4 |
| M02-E40 | Panne : l'inventaire met dix minutes | BF | ★★★ | 4 |
| M02-E41 | Panne : le contrôle planifié ne tourne plus | BF | ★★ | 4 |
| M02-E42 | Panne : l'environnement Python est cassé | BF | ★★ | 4 |
| M02-E43 | Astreinte : l'outillage en panne | BF | ★★★★ | 4 |
| M02-E44 | Sous le capot : expansions, sous-shells et descripteurs | LAB | ★★★ | 4 |
| M02-E45 | Questions expert : shell et Python | Q | ★★★ | 4 |
| M02-E46 | Mini-projet : outillage MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 2 revues · 2 rédactions · 1 chronométré.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 02 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 02 <XX>`, depuis `adm01`.
- Ressources fournies (scripts à relire, données de test) : [`ressources/`](ressources/).
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
