# Module 16 — Stockage et données dans Kubernetes

| | |
|---|---|
| **Bloc** | C — Conteneurs et Kubernetes |
| **Niveau** | Cœur |
| **Profil de lab** | k8s + infra : socle + `k8s-par1` + `ceph-par1` (`ceph01-03` démarrées) |
| **Prérequis** | Module 14 (`k8s-v1`) et 15 (`k8s-reseau-v1`, cert-manager) ; module 08 (`stockage-v1` : pool `k8s-rbd`, identité `client.k8s`, CephFS) ; module 05 (`s3-01`) |
| **Durée indicative** | 45 à 55 heures |

## Contexte MédiSphère

MédiAgenda fonctionne, mais sa base PostgreSQL tourne encore sur une VM gérée à la main, et un redémarrage de pod suffit à perdre les fichiers que MédiDoc écrivait en local. Julien Petit veut des volumes à la demande ; Nadia Roussel veut savoir comment on restaure un espace de noms entier après une erreur humaine ; Sophie Laurent veut des données chiffrées et des sauvegardes hors du cluster. Claire Morel a tranché le principe : le stockage de Kubernetes s'appuie sur `ceph-par1`, déjà exploité par l'équipe — mais elle veut une comparaison honnête avec Rook et Longhorn avant de signer l'ADR.

## Objectifs

À la fin de ce module, tu sais :
- expliquer le modèle de stockage de Kubernetes (PV, PVC, StorageClass, CSI) et suivre un volume du PVC jusqu'au bloc monté ;
- raccorder un cluster à un Ceph externe par ceph-csi (RBD et CephFS), avec snapshots, clones et agrandissement ;
- comparer Rook et Longhorn et les retirer proprement ;
- sauvegarder et restaurer des espaces de noms et leurs volumes avec Velero ;
- exploiter PostgreSQL dans Kubernetes avec CloudNativePG : réplication, bascule, sauvegarde continue, restauration à un instant donné ;
- chiffrer, superviser, mesurer et mettre à jour le stockage, et dépanner ses pannes classiques.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M16-E01 | Test de positionnement : stockage dans Kubernetes | Q | ★★ | 1 |
| M16-E02 | Volumes éphémères, `emptyDir` et `hostPath` | LAB | ★ | 1 |
| M16-E03 | PV, PVC et StorageClass : le cycle de vie d'un volume | LAB | ★★ | 1 |
| M16-E04 | Comprendre CSI | LAB | ★★ | 1 |
| M16-E05 | Raccorder les travailleurs au réseau de stockage | LAB | ★★ | 1 |
| M16-E06 | ceph-csi : des volumes RBD sur `ceph-par1` | LAB | ★★ | 1 |
| M16-E07 | ceph-csi : des volumes partagés CephFS | LAB | ★★ | 1 |
| M16-E08 | StatefulSet et volumes par instance | LAB | ★★ | 1 |
| M16-E09 | Questions : stockage et CSI | Q | ★★ | 1 |
| M16-E10 | Snapshots et clones de volumes | LAB | ★★ | 2 |
| M16-E11 | Agrandir un volume, volumes en mode bloc | LAB | ★★ | 2 |
| M16-E12 | Classes de stockage : défaut, topologie, liaison différée | LAB | ★★ | 2 |
| M16-E13 | Rook : un Ceph dans le cluster | LAB | ★★★ | 2 |
| M16-E14 | Rook : exploiter puis démonter proprement | LAB | ★★★ | 2 |
| M16-E15 | Longhorn : du stockage répliqué sur les nœuds | LAB | ★★ | 2 |
| M16-E16 | Velero : sauvegarder des espaces de noms | LAB | ★★ | 2 |
| M16-E17 | Velero : volumes, Kopia et snapshots CSI | LAB | ★★★ | 2 |
| M16-E18 | CloudNativePG : la base de MédiAgenda | LAB | ★★ | 2 |
| M16-E19 | CloudNativePG : sauvegarde continue et restauration à un instant donné | LAB | ★★★ | 2 |
| M16-E20 | Quotas de stockage et classes par équipe | LAB | ★★ | 2 |
| M16-E21 | Revue : les manifestes *stateful* du stagiaire | REV | ★★ | 2 |
| M16-E22 | Runbook : un PVC reste Pending | RED | ★★ | 2 |
| M16-E23 | Le stockage du cluster décrit par le code | LIBRE | ★★★ | 2 |
| M16-E24 | Restaurer un espace de noms complet ailleurs | LAB | ★★★ | 3 |
| M16-E25 | PostgreSQL : bascule, maintenance et montée de version | LAB | ★★★ | 3 |
| M16-E26 | Chiffrer les volumes | LAB | ★★★ | 3 |
| M16-E27 | Superviser le stockage du cluster | LAB | ★★ | 3 |
| M16-E28 | Mesurer les performances des volumes | LAB | ★★★ | 3 |
| M16-E29 | Migrer des données d'une classe de stockage à une autre | LAB | ★★★ | 3 |
| M16-E30 | ADR : le stockage de `k8s-par1` | RED | ★★ | 3 |
| M16-E31 | Questions de production : données dans Kubernetes | Q | ★★★ | 3 |
| M16-E32 | Politique de sauvegarde des données Kubernetes | RED | ★★ | 3 |
| M16-E33 | Mettre à jour ceph-csi et CloudNativePG sans interruption | LAB | ★★★ | 3 |
| M16-E34 | Restaurer la base de MédiAgenda en temps limité | CHRONO | ★★★ | 3 |
| M16-E35 | Panne : le PVC reste Pending | BF | ★★ | 4 |
| M16-E36 | Panne : le pod reste en ContainerCreating | BF | ★★★ | 4 |
| M16-E37 | Panne : le volume est déjà attaché ailleurs | BF | ★★ | 4 |
| M16-E38 | Panne : Ceph refuse de créer les volumes | BF | ★★★ | 4 |
| M16-E39 | Panne : la sauvegarde Velero échoue | BF | ★★ | 4 |
| M16-E40 | Panne : la base PostgreSQL ne bascule plus | BF | ★★★ | 4 |
| M16-E41 | Panne : l'archivage des WAL est bloqué | BF | ★★★ | 4 |
| M16-E42 | Panne : le snapshot ne se termine jamais | BF | ★★ | 4 |
| M16-E43 | Astreinte : les données de MédiAgenda sont en danger | BF | ★★★★ | 4 |
| M16-E44 | Sous le capot : du PVC au bloc monté | LAB | ★★★★ | 4 |
| M16-E45 | Questions expert : stockage dans Kubernetes | Q | ★★★ | 4 |
| M16-E46 | Mini-projet : données Kubernetes MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Objets créés dans ce module

| Élément | Valeur | Exercice |
|---|---|---|
| Carte STOR-PUB des travailleurs | 10.10.30.81-83 (VLAN 30, MTU 9000) | E05 |
| StorageClasses | `ceph-rbd` (par défaut), `ceph-rbd-retain`, `cephfs` | E06-E07, E12 |
| Disques de comparaison | 32 Go `ssd-lab` (Rook) et 32 Go `hdd-bulk` (Longhorn) par travailleur, retirés en fin de module | E13-E15 |
| Velero | `s3-01`, compartiment `velero-k8s-par1` | E16 |
| CloudNativePG | `s3-01`, compartiment `cnpg-k8s-par1`, plugin Barman Cloud | E18-E19 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.10.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 16 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 16 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
