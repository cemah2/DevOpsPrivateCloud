# Module 04 — Gestion de configuration avec Ansible

| | |
|---|---|
| **Bloc** | A — Fondations automatisées |
| **Niveau** | Cœur |
| **Profil de lab** | Socle (VMs jetables 2040-2049 ; `sem01` = 2041 ; instances Molecule 2045-2049) |
| **Prérequis** | Module 03 (images dorées étiquetées `current`) ; modules 01 et 02 |
| **Durée indicative** | 40 à 50 heures |

## Contexte MédiSphère

Le socle compte maintenant cinq VMs configurées à la main (`gw01`, `adm01`, `dns01`, `git01`, `runner01`), chacune un peu différemment : un `sshd` durci ici et pas là, un client NTP oublié, un paquet de trop. L'audit HDS approche et Sophie Laurent veut pouvoir répondre à « prouvez-moi que toutes vos machines appliquent la même politique ». Claire Morel tranche : la configuration du socle passe **en code**, dans le projet **`plateforme/ansible`**, relue en MR, testée, et appliquée par une chaîne traçable. Karim Benali fixe la règle : « un rôle qui n'est pas idempotent et testé n'entre pas dans `main` ». Et Lucas Martin, le stagiaire, écrit ses premiers rôles : tu vas les relire.

## Objectifs

À la fin de ce module, tu sais :
- organiser un projet Ansible professionnel (inventaires, `group_vars`/`host_vars`, rôles, collections, environnement reproductible) ;
- écrire des playbooks et des rôles idempotents : modules, variables et précédence, Jinja2, handlers, gestion d'erreurs ;
- utiliser un inventaire dynamique (Proxmox), Ansible Vault, la délégation et les stratégies d'exécution ;
- tester des rôles avec ansible-lint et Molecule, et intégrer le tout en CI ;
- exécuter Ansible de façon traçable (CI, Semaphore UI) et détecter la dérive de configuration ;
- situer Ansible face à Puppet (OpenVox), Salt et AWX ;
- diagnostiquer les pannes classiques : hôtes injoignables, variables inattendues, Vault, inventaire vide, configuration qui casse un service.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M04-E01 | Test de positionnement : gestion de configuration | Q | ★★ | 1 |
| M04-E02 | Créer le projet `plateforme/ansible` et un environnement reproductible | LAB | ★ | 1 |
| M04-E03 | Inventaire statique du socle | LAB | ★ | 1 |
| M04-E04 | Commandes ad hoc, modules et facts | LAB | ★ | 1 |
| M04-E05 | Premier playbook idempotent | LAB | ★ | 1 |
| M04-E06 | Variables et précédence | LAB | ★★ | 1 |
| M04-E07 | Templates Jinja2 | LAB | ★★ | 1 |
| M04-E08 | Handlers et validation avant rechargement | LAB | ★★ | 1 |
| M04-E09 | Questions : précédence et nouveautés d'ansible-core | Q | ★★ | 1 |
| M04-E10 | Premier rôle : `base` | LAB | ★★ | 2 |
| M04-E11 | Rôle `ssh_durci` | LAB | ★★ | 2 |
| M04-E12 | Ansible Vault | LAB | ★★ | 2 |
| M04-E13 | Inventaire dynamique Proxmox | LAB | ★★★ | 2 |
| M04-E14 | Boucles, conditions et filtres | LAB | ★★ | 2 |
| M04-E15 | Gestion d'erreurs : `block`, `rescue`, `assert` | LAB | ★★ | 2 |
| M04-E16 | Rôle `gitlab_runner` : reprendre `runner01` en code | LIBRE | ★★★ | 2 |
| M04-E17 | Rôle `pare_feu` pour `gw01` sans se couper la branche | LAB | ★★★ | 2 |
| M04-E18 | Collections : utiliser et créer `medisphere.socle` | LAB | ★★ | 2 |
| M04-E19 | Exploitation quotidienne : tags, limit, check, diff | LAB | ★ | 2 |
| M04-E20 | ansible-lint en pre-commit et en CI | LAB | ★★ | 2 |
| M04-E21 | Revue des rôles du stagiaire | REV | ★★ | 2 |
| M04-E22 | Runbook : appliquer un changement de configuration sur le socle | RED | ★★ | 2 |
| M04-E23 | Déléguer et orchestrer : `delegate_to`, `run_once` | LAB | ★★ | 2 |
| M04-E24 | Molecule : tester un rôle sur des VMs éphémères | LAB | ★★★ | 3 |
| M04-E25 | Mises à jour progressives : `serial` et tolérance aux échecs | LAB | ★★ | 3 |
| M04-E26 | Performances d'Ansible | LAB | ★★ | 3 |
| M04-E27 | Chaîne CI Ansible : lint, Molecule, `--check` en MR, application contrôlée | LAB | ★★★ | 3 |
| M04-E28 | Semaphore UI : exécuter Ansible avec traçabilité | LAB | ★★★ | 3 |
| M04-E29 | Détecter la dérive de configuration | LIBRE | ★★★ | 3 |
| M04-E30 | Vault en production : séparation et rotation | LAB | ★★ | 3 |
| M04-E31 | ADR : comment exécuter Ansible chez MédiSphère | RED | ★★ | 3 |
| M04-E32 | Questions : Ansible, Puppet (OpenVox), Salt, AWX | Q | ★★ | 3 |
| M04-E33 | Questions de production : configuration à l'échelle | Q | ★★★ | 3 |
| M04-E34 | Un rôle complet en temps limité | CHRONO | ★★★ | 3 |
| M04-E35 | Panne : « UNREACHABLE » sur une partie du socle | BF | ★★ | 4 |
| M04-E36 | Panne : le playbook passe mais rien ne change | BF | ★★★ | 4 |
| M04-E37 | Panne : la variable n'a pas la valeur attendue | BF | ★★★ | 4 |
| M04-E38 | Panne : « Decryption failed » | BF | ★★ | 4 |
| M04-E39 | Panne : l'inventaire dynamique est vide | BF | ★★ | 4 |
| M04-E40 | Panne : `sshd` ne redémarre plus après le playbook | BF | ★★★ | 4 |
| M04-E41 | Panne : le playbook est devenu très lent | BF | ★★★ | 4 |
| M04-E42 | Panne : Molecule échoue avant même de tester | BF | ★★ | 4 |
| M04-E43 | Astreinte : la chaîne de configuration en panne | BF | ★★★★ | 4 |
| M04-E44 | Sous le capot : AnsiballZ et un module maison | LAB | ★★★★ | 4 |
| M04-E45 | Questions expert : moteur d'Ansible | Q | ★★★ | 4 |
| M04-E46 | Mini-projet : le socle en configuration as code | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 5 questionnaires · 1 revue · 2 rédactions · 1 chronométré.

## Hôtes et VMs de ce module

| Hôte | VMID | Adresse | Rôle | Exercice |
|---|---|---|---|---|
| `sem01` | 2041 | 10.10.20.41 (VNet `vinfra`) | Semaphore UI (environnement du module) | E28 |
| instances Molecule | 2045-2049 | DHCP VNet `vsandbox` | Tests de rôles, détruites après chaque test | E24 |

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 04 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 04 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
