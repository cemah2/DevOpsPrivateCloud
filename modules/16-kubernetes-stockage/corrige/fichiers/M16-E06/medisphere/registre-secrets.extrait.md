<!-- Registre des secrets (plateforme/medisphere, emplacement du M01/M08) — EXTRAIT, entrées M16-E06/E07.
     Le registre dit OÙ vit chaque secret, qui le déchiffre et comment il tourne ; jamais sa valeur. -->

| Secret | Usage | Emplacement de référence | Copies | Déchiffré par | Rotation |
|---|---|---|---|---|---|
| Clé cephx `client.k8s` (type `aes`) | ceph-csi RBD → `ceph-par1` (pool `k8s-rbd`) | `plateforme/k8s` `secrets/ceph-csi.yml`, variable `ceph_csi_rbd_cle`, Ansible Vault `critique` | Secret `ceph-csi/csi-rbd-secret` (etcd, chiffré au repos, M14-E28) ; moniteurs de `ceph-par1` | équipe Plateforme (`adm01`) | annuelle, ou immédiate en cas de fuite : procédure de `docs/kubernetes/stockage/ceph-csi.md` §2 ; contrôle `outils/ceph-csi-secrets.sh verifier` |
| Clé cephx `client.k8s-cephfs` (type `aes`, E07) | ceph-csi CephFS → `ceph-par1` (groupe `csi`) | même fichier, `ceph_csi_cephfs_cle` | Secret `ceph-csi/csi-cephfs-secret` | équipe Plateforme | idem |

Ancienne entrée « `client.k8s` préparée, non distribuée » (M08-E46) : remplacée par la première ligne ; la copie de M08 est supprimée du Vault d'origine (une seule copie de référence).
