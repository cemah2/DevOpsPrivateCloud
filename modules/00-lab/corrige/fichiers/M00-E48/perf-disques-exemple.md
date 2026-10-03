# Mesures — Performances des stockages de `pve01` vues depuis une VM

> Structure de rapport attendue en M00-E48. Les cellules `…` sont à remplir avec **tes**
> mesures ; aucune valeur de ce modèle n'est un résultat.

| | |
|---|---|
| Date | AAAA-MM-JJ |
| Auteur | <nom> |
| VM de mesure | 5048 `sbx48`, 4 vCPU, 4 Gio, Debian 13, fio <version> |
| Contrôleur | `virtio-scsi-single` |
| Disques de données | 10 Gio chacun, `iothread=1,cache=none,discard=on` (série de référence) |
| Charge parasite | VMs démarrées pendant les mesures : … |

## 1. Configuration sous-jacente

| Stockage | Type Proxmox | Support physique (modèle si connu) | Protection coupure (PLP) | Remarques |
|---|---|---|---|---|
| local-nvme | … (LVM-thin / ZFS / dir) | … | oui / non / inconnu | … |
| ssd-lab | … | … | … | … |
| hdd-bulk | … | … | — | … |

Commandes : `fichiers/M00-E48/perf-disques.fio` (P1-P5) et `mesurer.sh` (P6), après
préconditionnement complet de chaque disque.

## 2. Résultats de référence (`cache=none`, `iothread=1`)

| Stockage | Profil | IOPS | Débit | Lat. moy. | p99 | p99.9 |
|---|---|---|---|---|---|---|
| local-nvme | P1 randread 4k QD32×4 | … | … | … | … | … |
| local-nvme | P2 randwrite 4k QD32×4 | … | … | … | … | … |
| local-nvme | P3 randwrite 4k QD1 | … | … | … | … | … |
| local-nvme | P4 seqread 1M QD8 | … | … | … | … | … |
| local-nvme | P5 seqwrite 1M QD8 | … | … | … | … | … |
| local-nvme | P6 etcd (fdatasync) | … | … | … | … | … |
| ssd-lab | P1 … P6 | … | … | … | … | … |
| hdd-bulk | P1 … P6 | … | … | … | … | … |

## 3. Variantes sur `ssd-lab`

| Variante | Profil | IOPS | Lat. moy. | p99 | Écart vs référence | Exigence côté VM |
|---|---|---|---|---|---|---|
| `cache=writeback` | P2 | … | … | … | … | arrêt/démarrage complet |
| `cache=writeback` | P3 | … | … | … | … | |
| `cache=writeback` | P6 | … | … | … | … | |
| `iothread=0` | P1 | … | … | … | … | arrêt/démarrage complet |

## 4. Analyse

- Rapport p99 / moyenne par stockage : …
- P6 : p99 de `fdatasync` par stockage, comparé au seuil etcd de 10 ms : …
- Effet de `writeback` : …
- Effet de `iothread` : …
- Limites de la mesure (ARC ZFS, cache du SSD, VMs actives, durée) : …

## 5. Recommandation de placement

| Charge | Stockage recommandé | Chiffre qui justifie | Risque si autre choix |
|---|---|---|---|
| etcd | … | … | … |
| PostgreSQL | … | … | … |
| OSD Ceph virtuels | … | … | … |
| MinIO / artefacts | … | … | … |
| Sauvegardes locales, ISO, templates | … | … | … |

## 6. Nettoyage

VM 5048 détruite le AAAA-MM-JJ ; aucun volume `vm-5048-*` restant (`pvesm list` sur les trois stockages).
