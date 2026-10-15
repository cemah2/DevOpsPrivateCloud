# Chiffrement des données de `k8s-par1`

| | |
|---|---|
| Propriétaire | Équipe Plateforme (Sophie Laurent pour la politique) |
| Ticket | SEC-1726 (M16-E26) ; migration des volumes existants : SEC-1729 (M16-E29) |
| Revue | à la mise en place de Vault (module 25) ; puis annuelle |

## Mécanismes par couche

| Couche | Mécanisme | Protège contre | Ne protège pas contre |
|---|---|---|---|
| Transit nœud ↔ Ceph | msgr2 `secure` (AES-GCM) : imposé par `ceph-par1` (M08-E27), demandé par les clients noyau (`mapOptions: krbd:ms_mode=secure`, `kernelMountOptions: ms_mode=secure`) | écoute du VLAN 30 | un nœud compromis (il a les clés) |
| Repos côté Ceph | OSD chiffrés par cephadm (LUKS, clés dans le magasin des moniteurs) | vol d'un disque, copie d'un fichier disque d'OSD | un administrateur Ceph, une identité cephx qui lit l'image (les données sont en clair au niveau RADOS) |
| Repos côté client | classe `ceph-rbd-chiffre` : LUKS2 ouvert **sur le nœud** par ceph-csi ; une DEK par volume, enveloppée par la KEK de la classe, rangée dans les métadonnées de l'image | administrateur Ceph, `client.k8s` utilisé hors de Kubernetes, export d'image, sauvegarde PBS d'OSD | un administrateur Kubernetes qui lit les Secrets de `ceph-csi` ; un nœud compromis pendant que le volume y est ouvert |
| Secrets Kubernetes | `EncryptionConfiguration` `aescbc` dans etcd (M14-E28) | lecture brute d'etcd, instantanés etcd | qui a le droit `get secrets` |

## Modèle de menace (synthèse)

| Acteur | Lit un volume `ceph-rbd` ? | Lit un volume `ceph-rbd-chiffre` ? |
|---|---|---|
| Administrateur de `pve01` (copie un disque d'OSD) | non (OSD chiffrés) | non |
| Administrateur Ceph (`client.admin`, `rbd export`) | **oui** | non (LUKS ; la DEK est enveloppée, la KEK n'est pas dans Ceph) |
| Détenteur de `client.k8s` hors cluster | **oui** | non |
| Attaquant sur le VLAN 30 | non (msgr2 `secure`) | non |
| Administrateur Kubernetes (`get secrets -n ceph-csi`) | oui (par un pod) | **oui** : KEK dans `csi-rbd-secret-chiffre` + DEK dans les métadonnées → limite assumée en v1 |
| Compte de service du *nodeplugin* RBD | oui | **oui** : son ClusterRole lit **tous** les Secrets du cluster (chart 3.18) — le *nodeplugin* est un composant de confiance de niveau `cluster-admin` |
| Sauvegarde Velero volée (*data mover*) | **oui** (copie des fichiers en clair dans le dépôt Kopia, chiffré par le mot de passe du dépôt Velero) | **oui** si le dépôt Kopia est lisible : le *data mover* lit le système de fichiers **monté**, donc déchiffré → la protection est celle du dépôt Kopia et de `s3-01` |

## Détenteurs des clés

| Clé | Où | Qui y accède |
|---|---|---|
| KEK `ceph-rbd-chiffre` | Ansible Vault `critique` (`plateforme/k8s`, `secrets/ceph-csi.yml`, variable `ceph_csi_rbd_kek`) ; copie hors ligne (enveloppe au coffre) ; Secret `ceph-csi/csi-rbd-secret-chiffre` | équipe Plateforme (Vault `critique`) ; pods ceph-csi ; administrateurs Kubernetes |
| DEK de chaque volume | métadonnée `rbd.csi.ceph.com/dek` de l'image, **enveloppée** par la KEK | personne en clair hors des pods ceph-csi |
| Clé `client.k8s` | Ansible Vault `critique` ; Secrets `csi-rbd-secret`, `csi-rbd-secret-chiffre`, `csi-cephfs-secret` | équipe Plateforme ; pods ceph-csi |
| Mot de passe du dépôt Kopia de Velero | Secret de Velero (E16) ; Ansible Vault | équipe Plateforme |

## Perte ou compromission de la KEK

- **Perte** (Secret supprimé **et** Vault perdu) : tous les volumes de la classe sont illisibles, définitivement. D'où : relecture du coffre (`outils/secret-rbd-chiffre.sh --verifier`) avant tout premier volume, copie hors ligne, inscription au registre des secrets.
- **Compromission** : ceph-csi 3.18 ne sait pas ré-envelopper les DEK d'une classe `metadata` avec une nouvelle KEK (rotation par les *CSI-Addons* non installés, à vérifier pour ce type de KMS). Procédure v1 : nouvelle classe avec une nouvelle KEK, migration des volumes (RB-163), suppression de l'ancienne classe et de son Secret.

## Limites assumées (v1)

- Les volumes créés avant SEC-1726 sont en clair : migration volume par volume (SEC-1729, RB-163).
- CephFS : chiffrement en transit seulement ; le chiffrement de fichiers (`fscrypt`) n'est pas mis en œuvre.
- La KEK est dans un Secret Kubernetes : un administrateur du cluster peut tout lire. Bascule vers un KMS externe (HashiCorp Vault/OpenBao, type `vaulttenantsa` ou `vault`) au module 25 : la KEK ne sera plus dans le cluster.
- Coût mesuré du chiffrement : voir `tests/performances.md` (M16-E28).

## Preuves (M16-E26, <AAAA-MM-JJ>)

| Contrôle | `e26-clair` (`ceph-rbd`) | `e26-temoin` (`ceph-rbd-chiffre`) |
|---|---|---|
| `lsblk` sur le nœud | `rbdN` → système de fichiers | `rbdN` → `crypt` → système de fichiers |
| `rbd image-meta list` | (aucune métadonnée de chiffrement) | `rbd.csi.ceph.com/encrypted = encrypted`, `rbd.csi.ceph.com/dek = <enveloppée>` |
| `rbd export … \| grep -c MEDISPHERE-E26-TEMOIN-7f3c9a` | <N> (> 0) | 0 |
| Clone depuis un instantané | — | chiffré, **même DEK** ré-enveloppée (ceph-csi copie la phrase en clair puis la stocke pour le clone) |
| Connexions des nœuds vers les MON | port 3300 uniquement, `ms_mode=secure` | idem |
