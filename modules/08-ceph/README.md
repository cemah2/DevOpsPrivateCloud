# Module 08 — Stockage distribué (Ceph)

| | |
|---|---|
| **Bloc** | B — Infrastructure cloud privé |
| **Niveau** | Cœur |
| **Profil de lab** | infra : socle + `ceph01-03` (2081-2083, 6 Go chacune), `ceph04` (2084) et `cephcli01` (2085) ponctuellement |
| **Prérequis** | Module 07 (réseaux de stockage en jumbo frames, matrice des flux v2) ; modules 04-06 (Ansible, OpenTofu, PKI, NetBox) |
| **Durée indicative** | 40 à 50 heures |

## Contexte MédiSphère

Le cloud privé de MédiSphère aura besoin d'un stockage **partagé, redondant et extensible** : disques des VMs du futur cluster Proxmox et d'OpenStack, volumes persistants de Kubernetes, documents patients de MédiDoc en stockage objet. Les serveurs d'InfoGér avaient chacun leurs disques locaux et un NAS unique ; l'auditeur HDS a relevé l'absence de réplication et de chiffrement. Claire Morel a retenu **Ceph** ; Sophie Laurent exige le chiffrement et des accès cloisonnés par équipe ; Nadia Roussel veut savoir ce qui se passe quand un disque ou un nœud tombe, à 3 h du matin.

## Objectifs

À la fin de ce module, tu sais :
- expliquer l'architecture de Ceph (MON, MGR, OSD, MDS, RGW, PG, CRUSH) et déployer un cluster avec cephadm ;
- fournir du stockage bloc (RBD), fichier (CephFS, NFS) et objet (RGW S3), avec des accès cephx minimaux ;
- concevoir les pools (réplication, codes d'effacement, classes de disques, domaines de panne) ;
- exploiter le cluster : extension, remplacement de disque, capacité, mises à jour, supervision, sauvegarde ;
- mesurer et régler les performances ;
- diagnostiquer les pannes classiques (OSD, PG, quorum, saturation, clients).

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M08-E01 | Test de positionnement : stockage | Q | ★★ | 1 |
| M08-E02 | Préparer les nœuds Ceph | LAB | ★★ | 1 |
| M08-E03 | Amorcer le cluster avec cephadm | LAB | ★★ | 1 |
| M08-E04 | Les OSD : spécifications et classes de disques | LAB | ★★ | 1 |
| M08-E05 | Pools répliqués et groupes de placement | LAB | ★★ | 1 |
| M08-E06 | RBD : images, snapshots et clones | LAB | ★★ | 1 |
| M08-E07 | Lire l'état d'un cluster | LAB | ★ | 1 |
| M08-E08 | ZFS : le stockage local en rappel | LAB | ★★ | 1 |
| M08-E09 | Questions : architecture de Ceph | Q | ★★ | 1 |
| M08-E10 | CephFS : volumes, sous-volumes et clients | LAB | ★★ | 2 |
| M08-E11 | RGW : la passerelle S3 et son point d'entrée | LAB | ★★ | 2 |
| M08-E12 | RGW : comptes, utilisateurs, quotas et politiques | LAB | ★★★ | 2 |
| M08-E13 | Cephx : des clients aux droits minimaux | LAB | ★★ | 2 |
| M08-E14 | CRUSH : règles par classe et domaines de panne | LAB | ★★★ | 2 |
| M08-E15 | Codes d'effacement | LAB | ★★★ | 2 |
| M08-E16 | Exports NFS | LAB | ★★ | 2 |
| M08-E17 | Exporter un bloc en iSCSI | LAB | ★★★ | 2 |
| M08-E18 | Étendre le cluster : un quatrième nœud | LAB | ★★ | 2 |
| M08-E19 | Retirer et remplacer un OSD | LAB | ★★ | 2 |
| M08-E20 | Capacité, quotas et seuils de remplissage | LAB | ★★ | 2 |
| M08-E21 | Revue : spécifications et règles CRUSH du stagiaire | REV | ★★ | 2 |
| M08-E22 | Runbook : remplacer un disque défaillant | RED | ★★ | 2 |
| M08-E23 | Le cluster décrit par le code | LIBRE | ★★★ | 2 |
| M08-E24 | Superviser Ceph | LAB | ★★ | 3 |
| M08-E25 | Sauvegarder hors du cluster | LAB | ★★★ | 3 |
| M08-E26 | Mettre à jour Ceph sans interruption | LAB | ★★★ | 3 |
| M08-E27 | Sécuriser Ceph : chiffrement et clés | LAB | ★★★ | 3 |
| M08-E28 | Mesurer les performances | LAB | ★★ | 3 |
| M08-E29 | Régler la mémoire, la récupération et mClock | LAB | ★★★ | 3 |
| M08-E30 | ADR : le stockage objet de MédiDoc | RED | ★★ | 3 |
| M08-E31 | Cloisonner le stockage par équipe | LIBRE | ★★★ | 3 |
| M08-E32 | Questions de production : stockage distribué | Q | ★★★ | 3 |
| M08-E33 | Politique de stockage de MédiSphère | RED | ★★ | 3 |
| M08-E34 | Livrer du stockage à une équipe en temps limité | CHRONO | ★★★ | 3 |
| M08-E35 | Panne : un OSD a disparu | BF | ★★ | 4 |
| M08-E36 | Panne : des PG restent inactifs | BF | ★★★ | 4 |
| M08-E37 | Panne : plus aucune écriture | BF | ★★★ | 4 |
| M08-E38 | Panne : les moniteurs perdent le quorum | BF | ★★★ | 4 |
| M08-E39 | Panne : le client RBD est refusé | BF | ★★ | 4 |
| M08-E40 | Panne : le S3 de Ceph répond en erreur | BF | ★★★ | 4 |
| M08-E41 | Panne : le montage CephFS est figé | BF | ★★★ | 4 |
| M08-E42 | Panne : le cluster est lent | BF | ★★★ | 4 |
| M08-E43 | Astreinte : le stockage en détresse | BF | ★★★★ | 4 |
| M08-E44 | Sous le capot : où est rangé cet objet ? | LAB | ★★★ | 4 |
| M08-E45 | Questions expert : Ceph | Q | ★★★ | 4 |
| M08-E46 | Mini-projet : stockage MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes créés dans ce module

| Hôte | VMID | Adresses (public / cluster) | Rôle | Exercice |
|---|---|---|---|---|
| `ceph01-03` | 2081-2083 | 10.10.30.51-53 / 10.10.31.51-53 | MON, MGR, OSD, MDS, RGW (Rocky 10, Podman) | E02-E03 |
| `ceph04` | 2084 | 10.10.30.54 / 10.10.31.54 | Extension et remplacement (détruit en fin de module) | E18 |
| `cephcli01` | 2085 | 10.10.30.20 | Client (RBD, CephFS, S3, iSCSI, ZFS) | E06 |

Cluster `ceph-par1`, Ceph Tentacle 20.2 (cephadm), RGW `rgw.par1.medisphere.internal` (VIP 10.10.30.200) : voir [`PLAN.md`](../../PLAN.md) §4.9. Le cluster est **conservé** en fin de module (arrêtable) : OpenStack (M10) et Kubernetes (M16) le consomment.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 08 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 08 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
