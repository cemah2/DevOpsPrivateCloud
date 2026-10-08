<!-- registre-secrets.extrait.md — M08-E13 : lignes à ajouter (ou mettre à jour) au registre des secrets. -->
| Secret | Usage | Emplacement | Copie de référence | Propriétaire | Rotation |
|---|---|---|---|---|---|
| Clé cephx `client.rbd-test` (`profile rbd`, pool `rbd-test`, depuis 10.10.30.20/32 depuis E13) | Images RBD d'essai de `cephcli01` (`rbdmap`) | `cephcli01:/etc/ceph/ceph.client.rbd-test.keyring` (600, rôle `ceph_client`) | Vault `lab` (`vault_ceph_cle_rbd_test`) | Équipe Plateforme | Annuelle, par nouvelle entité (procédure E13) ; `ceph auth rotate` si compromise |
| Clé cephx `client.rbd-lecture` (`profile rbd-read-only`, `rbd-test`) | Lecture des images (sauvegardes, M08-E25) | `cephcli01:/etc/ceph/ceph.client.rbd-lecture.keyring` (600, rôle `ceph_client`) | Vault `lab` (`vault_ceph_cle_rbd_lecture`) | Équipe Plateforme | Annuelle |
| Clé cephx `client.outillage` (CephFS, sous-volume `plateforme/outillage`) | Montage `/mnt/outillage` | `cephcli01:/etc/ceph/ceph.client.outillage.keyring` et `outillage.secret` (600, rôle `ceph_client`) | Vault `lab` (`vault_ceph_cle_outillage`) | Équipe Plateforme | Annuelle |
| Clé cephx `client.admin` | Administration du cluster | nœuds `_admin` (`ceph01-03`) seulement, `/etc/ceph/` (600) | Sauvegarde de configuration chiffrée (M08-E25) | Équipe Plateforme | Sur incident |
