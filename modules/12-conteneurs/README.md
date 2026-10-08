# Module 12 — Conteneurs

| | |
|---|---|
| **Bloc** | C — Conteneurs et Kubernetes |
| **Niveau** | Cœur |
| **Profil de lab** | Socle + `ctr01-03` (2121-2123, 2 Go chacune), `legacy01` (2124, 2 Go) ; `runner02` (1012) rejoint le socle |
| **Prérequis** | Module 04 (Ansible) ; modules 01, 05 et 06 (GitLab, OpenTofu, PKI step-ca) ; module 07 pour la matrice des flux de la bordure |
| **Durée indicative** | 40 à 50 heures |

## Contexte MédiSphère

Les équipes de développement livrent aujourd'hui des archives et des consignes d'installation à appliquer à la main sur des VMs ; Legacy-RDV tourne sur un serveur que plus personne n'ose redémarrer. Julien Petit veut que MédiAgenda tourne « pareil sur mon poste, en recette et en production ». Claire Morel a décidé que toutes les applications de MédiSphère seront livrées en **images de conteneurs** avant l'arrivée de Kubernetes ; Sophie Laurent exige des images minimales, sans privilège, reconstruites régulièrement, et Karim Benali veut des constructions reproductibles en CI, sans démon privilégié.

## Objectifs

À la fin de ce module, tu sais :
- expliquer ce qu'est un conteneur (espaces de noms, cgroups v2, capacités, seccomp, OCI, containerd, runc) et en construire un à la main ;
- utiliser Docker 29 et Podman 5 (sans privilège, pods, Quadlet), Buildah et Skopeo ;
- écrire des images de qualité : multi-étapes, minimales, reproductibles, multi-architectures, analysées par Hadolint et Dive ;
- conteneuriser des applications réelles, y compris un monolithe hérité, selon les « 12 facteurs » ;
- construire des images en CI sans mode privilégié ;
- durcir, superviser, mettre à jour et dépanner des conteneurs en production.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M12-E01 | Test de positionnement : conteneurs | Q | ★★ | 1 |
| M12-E02 | Préparer les hôtes de conteneurs | LAB | ★★ | 1 |
| M12-E03 | Premiers conteneurs avec Docker : cycle de vie | LAB | ★ | 1 |
| M12-E04 | Images, couches, manifestes et empreintes | LAB | ★★ | 1 |
| M12-E05 | Un premier Dockerfile pour MédiAgenda | LAB | ★★ | 1 |
| M12-E06 | Podman sans privilège | LAB | ★★ | 1 |
| M12-E07 | Volumes, montages et réseaux | LAB | ★★ | 1 |
| M12-E08 | Docker Compose : MédiAgenda, PostgreSQL et Valkey | LAB | ★★ | 1 |
| M12-E09 | Questions : architecture des conteneurs | Q | ★★ | 1 |
| M12-E10 | Multi-étapes et image minimale pour MédiDoc | LAB | ★★ | 2 |
| M12-E11 | BuildKit : cache, secrets de construction, montages | LAB | ★★★ | 2 |
| M12-E12 | Images multi-architectures avec Buildx | LAB | ★★★ | 2 |
| M12-E13 | Buildah et Skopeo : construire sans démon, copier entre registres | LAB | ★★ | 2 |
| M12-E14 | Pods Podman et Quadlet : des conteneurs gérés par systemd | LAB | ★★★ | 2 |
| M12-E15 | Un registre de travail | LAB | ★★ | 2 |
| M12-E16 | Hadolint et Dive : la qualité d'une image | LAB | ★★ | 2 |
| M12-E17 | Conteneuriser MédiNotif : signaux, PID 1, arrêt propre | LAB | ★★ | 2 |
| M12-E18 | Journaux, ressources et santé des conteneurs | LAB | ★★ | 2 |
| M12-E19 | Conteneuriser Legacy-RDV | LIBRE | ★★★ | 2 |
| M12-E20 | Un runner GitLab à exécuteur Docker | LAB | ★★★ | 2 |
| M12-E21 | Construire les images en CI sans mode privilégié | LAB | ★★★ | 2 |
| M12-E22 | Revue : les Dockerfiles du stagiaire | REV | ★★ | 2 |
| M12-E23 | Runbook : un conteneur redémarre en boucle | RED | ★★ | 2 |
| M12-E24 | Durcir l'exécution : utilisateur, capacités, seccomp, lecture seule | LAB | ★★★ | 3 |
| M12-E25 | SELinux et conteneurs sur Rocky Linux | LAB | ★★★ | 3 |
| M12-E26 | Durcir le moteur : socket, *userns-remap*, Docker sans privilège | LAB | ★★★ | 3 |
| M12-E27 | Politique des images de base de MédiSphère | LIBRE | ★★★ | 3 |
| M12-E28 | Superviser les conteneurs | LAB | ★★ | 3 |
| M12-E29 | Sauvegarder et restaurer les données des conteneurs | LAB | ★★ | 3 |
| M12-E30 | Mettre à jour sans interruption et revenir en arrière | LAB | ★★★ | 3 |
| M12-E31 | ADR : Docker ou Podman sur les serveurs | RED | ★★ | 3 |
| M12-E32 | Questions de production : conteneurs | Q | ★★★ | 3 |
| M12-E33 | Normes de conteneurisation de MédiSphère | RED | ★★ | 3 |
| M12-E34 | Conteneuriser une application en temps limité | CHRONO | ★★★ | 3 |
| M12-E35 | Panne : le conteneur s'arrête aussitôt | BF | ★★ | 4 |
| M12-E36 | Panne : « permission denied » sur le volume | BF | ★★ | 4 |
| M12-E37 | Panne : l'application ne joint plus sa base | BF | ★★★ | 4 |
| M12-E38 | Panne : la construction échoue ou ignore le cache | BF | ★★ | 4 |
| M12-E39 | Panne : le disque de l'hôte est plein | BF | ★★ | 4 |
| M12-E40 | Panne : le service Quadlet ne démarre pas | BF | ★★★ | 4 |
| M12-E41 | Panne : le conteneur est tué sans prévenir | BF | ★★★ | 4 |
| M12-E42 | Panne : le pipeline ne publie plus l'image | BF | ★★★ | 4 |
| M12-E43 | Astreinte : la pile de recette est en panne | BF | ★★★★ | 4 |
| M12-E44 | Sous le capot : un conteneur construit à la main | LAB | ★★★★ | 4 |
| M12-E45 | Questions expert : conteneurs | Q | ★★★ | 4 |
| M12-E46 | Mini-projet : conteneurs MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes créés dans ce module

| Hôte | VMID | Réseau | Rôle | Exercice |
|---|---|---|---|---|
| `ctr01` | 2121 | `vsandbox` (DHCP) | Debian 13, Docker Engine 29, registre de travail `registry:3` (port 5000) | E02 |
| `ctr02` | 2122 | `vsandbox` (DHCP) | Debian 13, Podman 5.4 sans privilège, Buildah, Skopeo, Quadlet | E02 |
| `ctr03` | 2123 | `vsandbox` (DHCP) | Rocky Linux 10, Podman 5.8, SELinux *enforcing* | E02 |
| `legacy01` | 2124 | `vsandbox` (DHCP) | Legacy-RDV installé « à l'ancienne » (Apache, PHP, MariaDB) : le point de départ de E19 | E02 |
| `runner02` | **1012** (socle) | INFRA 10.10.20.17 | GitLab Runner exécuteur `docker` (étiquettes `docker`, `socle`) | E20 |

Les applications conteneurisées sont dans [`apps/`](../../apps/) (MédiAgenda, MédiDoc, MédiNotif, Legacy-RDV). Détails figés : [`PLAN.md`](../../PLAN.md) §4.10. En fin de module, `runner02` reste dans le socle ; `ctr01-03` et `legacy01` sont détruites (ou arrêtées) par le code.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 12 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 12 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
