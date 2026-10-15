# Stockage et données de `k8s-par1` — périmètre du dépôt

> `plateforme/k8s`, M16-E23 (PLAT-1723). Ce document dit ce que le dépôt décrit, dans quel ordre on l'applique, où sont les secrets, et ce qui n'y est pas.

## Périmètre

| Domaine | Fichiers | Appliqué par |
|---|---|---|
| Instantanés (CRD, contrôleur) | `composants/snapshot-controller/` | `task stockage:snapshots` |
| Pilotes ceph-csi, StorageClasses, classes d'instantanés | `espaces/ceph-csi.yaml`, `composants/ceph-csi/` (`values-rbd.yaml`, `values-cephfs.yaml`, `installer.sh`, `classes/`) | `task stockage:ceph-csi` |
| Sauvegarde des espaces de noms | `espaces/velero/`, `composants/velero/values.yaml`, `planifications.yaml`, `restaurations/` (E24) | `task stockage:velero` |
| PostgreSQL (opérateur, plugin) | `espaces/cnpg-system/`, `composants/cloudnative-pg/values.yaml`, `composants/plugin-barman-cloud/values.yaml` | `task stockage:cnpg` |
| Garde-fous | `admission/classes-stockage.yaml`, `espaces/mediagenda-*/30-quota-stockage.yaml`, annotation `medisphere.internal/classes-stockage` des espaces | `task stockage:garde-fous` |
| Base de MédiAgenda (recette) | `espaces/mediagenda-recette/40-…`, `50-…`, `55-…`, `60-…`, `70-…` | `task stockage:donnees` |
| Contrôle | `outils/derive-stockage.sh`, `outils/schemas-crd.sh`, CI `stockage:*` | `task stockage:derive`, pipeline |

Versions : ceph-csi 3.18.1, external-snapshotter 8.6.0, Velero 1.18.4 (chart 12.2.1, plugin AWS 1.14.4), CloudNativePG 1.30.1 (chart 0.29.1), plugin Barman Cloud 0.15.1 (chart 0.8.1). Elles sont dans les fichiers ; changer une version est une MR (M16-E33).

## Ordre d'application

`task stockage:appliquer` : instantanés → Secrets → ceph-csi (et ses classes) → Velero → CNPG → garde-fous → base. Ce qui **définit** des types (CRD) passe avant ce qui les **sert** (contrôleurs, opérateurs), qui passe avant ce qui les **utilise** (classes, `Cluster`, `ObjectStore`, planifications). La tâche est idempotente : rejouée sur un cluster à jour, `helm upgrade` produit une révision sans changement et `kubectl apply` répond `unchanged` ; `task stockage:derive` le prouve (sortie 0).

## Secrets

| Secret | Espace | Source | Script | Rotation |
|---|---|---|---|---|
| `csi-rbd-secret`, `csi-cephfs-secret` | `ceph-csi` | Vault `critique` (`secrets/ceph-csi.yml`) | `outils/ceph-csi-secrets.sh appliquer` | avec la clé cephx (`plateforme/ceph`) |
| `velero-s3` (clé `cloud`) | `velero` | `~/.config/workbook/s3-velero.env` (copie du Vault `lab`, `host_vars/s3-01/vault.yml`) | `outils/secrets-sauvegarde.sh velero` | 6 mois ; Velero relit le fichier monté |
| `velero-repo-credentials` | `velero` | Vault `critique` | `outils/secrets-sauvegarde.sh velero-kopia` (refuse si un dépôt existe) | **jamais** (rendrait les dépôts Kopia illisibles) |
| `cnpg-s3`, `medisphere-ca` | `mediagenda-recette` | `~/.config/workbook/s3-cnpg.env`, racine MédiSphère | `outils/secrets-sauvegarde.sh cnpg mediagenda-recette` | 6 mois ; `kubectl cnpg reload` ou étiquette `cnpg.io/reload` |
| `mediagenda-db-app`, `-replication`, `-ca`, `-server` | `mediagenda-recette` | générés par CNPG | — | par CNPG |

Aucune valeur n'est dans le dépôt (contrôle `stockage:yaml` et Gitleaks). Toutes figurent au registre des secrets (`docs/socle/registre-secrets.md` de `plateforme/medisphere`). Vault/OpenBao et External Secrets remplaceront ces scripts au module 25.

## Ce qui n'est pas dans le dépôt, et pourquoi

- **Les données** : volumes RBD et CephFS (dans `ceph-par1`), instantanés, sauvegardes Velero (`velero-k8s-par1`) et CNPG (`cnpg-k8s-par1`). Le dépôt décrit comment les produire et les restaurer, pas leur contenu.
- **Les objets créés par les opérateurs** : PVC de CNPG, `Backup` produits par les planifications, `BackupRepository` et `DataUpload` de Velero, `VolumeSnapshotContent` dynamiques.
- **Les essais** (`wb-essais`, `mediagenda-db-pitr`) : jetables par définition.
- **Rook et Longhorn** : essayés en M16-E13-E15, retirés ; leurs valeurs restent dans l'historique Git (MR de retrait) et dans l'ADR-0160.
- **La clé `velero-repo-credentials` elle-même**, et toute clé S3 ou cephx.
