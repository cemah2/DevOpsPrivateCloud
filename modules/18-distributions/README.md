# Module 18 — Distributions et cycle de vie des clusters

| | |
|---|---|
| **Bloc** | C — Conteneurs et Kubernetes |
| **Niveau** | Secondaire |
| **Profil de lab** | Socle + VMs 2181-2188 (≈ 30 Go en tout, jamais toutes allumées) et clusters Cluster API 5180-5189 ; `k8s-par1` **arrêté** pendant les parties lourdes |
| **Prérequis** | Module 14 (kubeadm, `k8s-v1`) ; module 05 (OpenTofu) ; module 03 (Packer, pour l'image de nœud) ; module 17 (Helm) |
| **Durée indicative** | 22 à 30 heures |

## Contexte MédiSphère

`k8s-par1` a été construit à la main avec kubeadm, et c'était voulu. Mais MédiSphère aura bientôt d'autres besoins : un petit cluster dans l'agence de Lyon, des clusters de recette éphémères pour les équipes, peut-être un OS de nœud immuable pour réduire la surface d'attaque. Claire Morel demande une étude comparative argumentée — k3s, RKE2, Talos Linux, Cluster API — avec des essais réels sur le lab, pour trancher dans un ADR la stratégie de distribution et de cycle de vie des clusters de MédiSphère.

## Objectifs

À la fin de ce module, tu sais :
- monter des clusters de développement (kind, k3d) et légers (k3s), durcis (RKE2) et immuables (Talos Linux) ;
- piloter Talos par son API, appliquer des correctifs de configuration et monter de version ;
- gérer des clusters comme des ressources avec Cluster API : cluster de gestion, fournisseur Proxmox, image de nœud, pivot, montée de version, réparation automatique ;
- sauvegarder et restaurer selon la distribution, et comparer leur durcissement ;
- choisir une distribution selon le besoin et l'argumenter.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M18-E01 | Questions : panorama des distributions Kubernetes | Q | ★★ | 1 |
| M18-E02 | kind et k3d : des clusters de développement | LAB | ★ | 1 |
| M18-E03 | k3s : un cluster léger pour l'agence | LAB | ★★ | 1 |
| M18-E04 | RKE2 : un cluster durci | LAB | ★★ | 1 |
| M18-E05 | Talos Linux : un OS immuable piloté par API | LAB | ★★★ | 1 |
| M18-E06 | Talos : correctifs de configuration et montée de version | LAB | ★★★ | 2 |
| M18-E07 | k3s : haute disponibilité intégrée et mises à jour automatiques | LAB | ★★★ | 2 |
| M18-E08 | Cluster API : concepts et cluster de gestion | LAB | ★★ | 2 |
| M18-E09 | Une image de nœud pour Cluster API | LAB | ★★★ | 2 |
| M18-E10 | CAPMOX : un cluster de charge de travail sur Proxmox | LAB | ★★★ | 2 |
| M18-E11 | Revue : les manifestes Cluster API du stagiaire | REV | ★★ | 2 |
| M18-E12 | Pivoter le cluster de gestion | LAB | ★★★ | 2 |
| M18-E13 | Cycle de vie par Cluster API : montée de version, réparation, mise à l'échelle | LAB | ★★★ | 3 |
| M18-E14 | Sauvegarder et restaurer selon la distribution | LAB | ★★★ | 3 |
| M18-E15 | Durcissement comparé | LAB | ★★ | 3 |
| M18-E16 | Cluster API sur OpenStack (facultatif) | LIBRE | ★★★★ | 3 |
| M18-E17 | ADR : stratégie de distribution de MédiSphère | RED | ★★ | 3 |
| M18-E18 | Un cluster de recette éphémère en temps limité | CHRONO | ★★★ | 3 |
| M18-E19 | Panne : le nœud k3s ne rejoint plus le cluster | BF | ★★ | 4 |
| M18-E20 | Panne : le nœud Talos refuse sa configuration | BF | ★★★ | 4 |
| M18-E21 | Panne : la machine reste en Provisioning | BF | ★★★ | 4 |
| M18-E22 | Panne : RKE2 ne démarre plus | BF | ★★★ | 4 |
| M18-E23 | Sous le capot : k3s, un binaire, une base, un superviseur | LAB | ★★★ | 4 |
| M18-E24 | Questions expert : distributions et cycle de vie | Q | ★★★ | 4 |
| M18-E25 | Mini-projet : distributions MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 4 break & fix · 2 questionnaires · 1 revue · 1 rédaction · 1 chronométré.

## Hôtes créés dans ce module

| Hôte | VMID | Réseau | Rôle | Exercice |
|---|---|---|---|---|
| `k3s01` | 2181 | `vsandbox` (DHCP) | k3s monoœud (agence), puis cluster de gestion Cluster API | E03, E12 |
| `rke2-01..03` | 2182-2184 | `vsandbox` (DHCP) | RKE2, profil CIS | E04 |
| `talos-01..03` | 2185-2187 | `vsandbox` (DHCP) | Talos Linux 1.14 | E05 |
| `m18-dev01` | 2188 | `vsandbox` (DHCP) | Docker, kind, k3d, clusterctl, image-builder | E02 |
| Clusters CAPMOX | 5180-5189 | `vsandbox` | VMs créées par Cluster API | E10 |
| Template de nœud | 9060-9069 | — | Image de nœud Kubernetes 1.36 (image-builder) | E09 |

Toutes ces VMs sont détruites en fin de module (sauf choix contraire écrit dans l'ADR-0180). Détails figés : [`PLAN.md`](../../PLAN.md) §4.10.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 18 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 18 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
