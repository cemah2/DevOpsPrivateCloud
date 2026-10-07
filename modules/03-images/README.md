# Module 03 — Images dorées

| | |
|---|---|
| **Bloc** | A — Fondations automatisées |
| **Niveau** | Secondaire |
| **Profil de lab** | Socle (builds sur les VMID 9001-9099, VMs de test 2030-2039) |
| **Prérequis** | Module 02 (outillage, CI du projet outils) ; M00-E11 (template manuel `tpl-debian13`) |
| **Durée indicative** | 30 à 40 heures (dont beaucoup d'attente de builds) |

## Contexte MédiSphère

Le template `tpl-debian13` du module 00 a été fait à la main, une fois. Personne ne sait exactement ce qu'il contient, ni comment le refaire quand Debian publie une version intermédiaire. Sophie Laurent veut des **images dorées** : construites par du code, durcies, testées, versionnées, et dont on peut prouver le contenu. Julien Petit, de son côté, a besoin d'une image **Rocky Linux** pour un éditeur dont le logiciel n'est certifié que sur la famille RHEL. Tu construis le projet **`plateforme/images`** avec Packer, et un catalogue d'images que consommeront Ansible (module 04) et OpenTofu (module 05).

## Objectifs

À la fin de ce module, tu sais :
- expliquer le compromis entre image dorée et configuration au démarrage ;
- construire des templates Proxmox avec Packer, depuis une ISO (installation automatisée preseed/kickstart) et depuis un template existant ;
- maîtriser cloud-init : sources de données, étapes, modules, validation, diagnostic ;
- préparer une image pour le clonage (identité machine, clés, journaux) et la durcir ;
- versionner, tester, publier et retirer des images ;
- diagnostiquer les échecs de build et de premier démarrage.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M03-E01 | Questions : pourquoi des images dorées ? | Q | ★★ | 1 |
| M03-E02 | Installer Packer et créer un compte Proxmox dédié | LAB | ★★ | 1 |
| M03-E03 | Premier build : `proxmox-clone` depuis `tpl-debian13` | LAB | ★ | 1 |
| M03-E04 | cloud-init en profondeur : étapes, modules, journaux | LAB | ★★ | 1 |
| M03-E05 | Construire depuis l'ISO : `proxmox-iso` et preseed Debian 13 | LAB | ★★★ | 1 |
| M03-E06 | Image de base Rocky Linux 10 avec kickstart | LAB | ★★★ | 2 |
| M03-E07 | Provisioners et préparation au clonage | LAB | ★★ | 2 |
| M03-E08 | Variables, fichiers de variables et secrets de build | LAB | ★★ | 2 |
| M03-E09 | Image dorée Debian 13 v1 | LIBRE | ★★ | 2 |
| M03-E10 | Versionner et publier les images | LAB | ★★ | 2 |
| M03-E11 | cloud-init avancé : vendor-data, multi-part, réseau v2 | LAB | ★★ | 2 |
| M03-E12 | Revue du template Packer d'un stagiaire | REV | ★★ | 2 |
| M03-E13 | Durcir une image | LIBRE | ★★★ | 3 |
| M03-E14 | Tester automatiquement une image | LAB | ★★ | 3 |
| M03-E15 | Pipeline de construction d'images | LAB | ★★★ | 3 |
| M03-E16 | Cycle de vie : rotation et retrait des images | LAB | ★★ | 3 |
| M03-E17 | ADR : stratégie d'images de MédiSphère | RED | ★★ | 3 |
| M03-E18 | Questions de production : images et chaîne de confiance | Q | ★★ | 3 |
| M03-E19 | Panne : le build attend SSH indéfiniment | BF | ★★★ | 4 |
| M03-E20 | Panne : les clones se marchent dessus | BF | ★★ | 4 |
| M03-E21 | Panne : cloud-init ignore la configuration | BF | ★★ | 4 |
| M03-E22 | Panne : la VM Rocky ne démarre pas | BF | ★★ | 4 |
| M03-E23 | Sous le capot : mesurer un premier démarrage | LAB | ★★★ | 4 |
| M03-E24 | Questions expert : images et démarrage | Q | ★★★ | 4 |
| M03-E25 | Mini-projet : catalogue d'images MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 4 break & fix · 3 questionnaires · 1 revue · 1 rédaction.

## Catalogue d'images (PLAN.md §4.8)

| VMID | Nom | Contenu |
|---|---|---|
| 9000 | `tpl-debian13` | Template manuel du module 00 (conservé, référence) |
| 9001 | `tpl-debian13-base` | Debian 13 installée depuis l'ISO par Packer (E05) |
| 9002 | `tpl-rocky10-base` | Rocky Linux 10 installée depuis l'ISO par Packer (E06) |
| 9010-9029 | `deb13-gold-AAAAMMJJ-N` | Images dorées Debian 13 versionnées ; étiquette `current` sur la version validée |
| 9030-9049 | `rocky10-gold-AAAAMMJJ-N` | Images dorées Rocky 10 versionnées |
| 9090-9099 | — | Builds temporaires et essais |

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 03 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 03 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
