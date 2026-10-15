# ADR-0160 — Le stockage persistant de `k8s-par1`

| | |
|---|---|
| Statut | Accepté |
| Date | <AAAA-MM-JJ> |
| Décideurs | Claire Morel (décision), Karim Benali, Sophie Laurent ; rédaction : <MOI> |
| Ticket | PLAT-1730 |
| Remplace / complète | ADR-0080 (stockage objet de MédiDoc), politique de stockage (M08-E33), ADR-0140 (topologie de `k8s-par1`) |

## Contexte

`k8s-par1` héberge des données de santé : PostgreSQL de MédiAgenda (CloudNativePG, 3 instances), Valkey, fichiers partagés de MédiDoc, volumes des équipes. Exigences : chiffrement en transit et au repos (Sophie), sauvegarde hors du cluster et restauration prouvée (Nadia, auditeur HDS), PRA à PAR2 (F5). Le cluster Ceph `ceph-par1` (Tentacle, 3 nœuds, cephadm) existe déjà, exploité par l'équipe (M08), et sert aussi OpenStack (M10). Lab : un seul hyperviseur, OSD sur un même disque physique : les mesures valent en relatif seulement (E28).

Deux décisions distinctes : le **fournisseur** (où vivent les données) et le **pilote** (comment Kubernetes les consomme).

## Critères (poids 1 à 3)

| Critère | Poids |
|---|---|
| Domaine de panne séparé du cluster Kubernetes (perte du cluster ≠ perte des données) | 3 |
| Restauration et reconstruction prouvées (E17, E19, E24) | 3 |
| Chiffrement transit + repos, détenteurs de clés maîtrisés (E26) | 3 |
| Exploitation : compétences existantes, mises à jour (E33), supervision (E27) | 2 |
| Performances mesurées, notamment latence d'écriture durable (E28, profil `wal`) | 2 |
| Ressources consommées sur les nœuds Kubernetes (mémoire, CPU, disques) | 2 |
| Couplage des cycles de vie (monter Kubernetes sans monter le stockage, et l'inverse) | 2 |
| Multi-consommateurs (OpenStack, VMs, hors Kubernetes) | 1 |
| Instantanés, clones, agrandissement, RWX | 1 |
| Réversibilité (sortir de la solution) | 1 |

## Options et évaluation (0 à 3, pondéré)

| Critère (poids) | O1 ceph-csi → `ceph-par1` | O2 Rook interne | O3 Rook externe → `ceph-par1` | O4 Longhorn | O5 volumes locaux + réplication applicative |
|---|---|---|---|---|---|
| Domaine de panne séparé (3) | 3 : données hors du cluster | 0 : données sur les nœuds | 3 | 0 | 0 |
| Restauration prouvée (3) | 3 : E17, E19, E24 | 1 : non pratiquée hors démontage | 3 (même fournisseur) | 2 : sauvegarde S3 vue en aperçu (E15) | 1 : par l'application seulement |
| Chiffrement (3) | 3 : msgr2 secure + LUKS client (E26) | 2 : chiffrement d'OSD, msgr2 | 3 | 2 : chiffrement par volume (non pratiqué) | 1 : dépend des nœuds |
| Exploitation (2) | 3 : Ceph déjà exploité (M08), un composant de plus (ceph-csi) | 1 : un second Ceph à exploiter, dans Kubernetes | 2 : opérateur Rook en plus, pilotes gérés par lui | 2 : simple, mais une technologie nouvelle | 1 : chaque application gère sa réplication |
| Performances (2) | 2 : `wal` p99 <N> ms | 2 : similaire (même Ceph, réseau des nœuds) | 2 | 1 : <N> ms (E15) | 3 : disque local |
| Ressources des nœuds (2) | 3 : seuls les pilotes | 0 : MON/OSD/MGR sur les travailleurs (≥ 4 Go/nœud) | 3 | 1 : réplicas et moteur sur chaque nœud | 2 |
| Couplage des cycles de vie (2) | 3 : indépendants (vérifier la compatibilité ceph-csi ↔ Kubernetes) | 0 : Ceph monte avec le cluster | 2 | 1 | 2 |
| Multi-consommateurs (1) | 3 : le même Ceph sert OpenStack | 1 | 3 | 0 | 0 |
| Fonctions (1) | 3 : instantanés, clones, agrandissement, RWX (CephFS) | 3 | 3 | 2 : RWX par NFS | 1 |
| Réversibilité (1) | 2 | 1 | 2 | 2 | 2 |
| **Total (/63)** | **60** | **17** | **55** | **24** | **27** |

Les notes renvoient aux exercices du module ; les chiffres `<N>` sont ceux de `tests/performances.md`.

## Décision

1. **Fournisseur** : `ceph-par1` (externe au cluster), pools `k8s-rbd` et CephFS (sous-volumes du groupe `csi`).
2. **Pilote** : **ceph-csi 3.18** installé par ses charts Helm, configuré par le code (`plateforme/k8s`) ; classes `ceph-rbd` (défaut), `ceph-rbd-retain`, `ceph-rbd-chiffre` (données de santé), `cephfs`.
3. **Rook** et **Longhorn** sont **retirés** (fin du module 16) avec leurs disques. Rook externe (O3) reste la solution de repli si l'entretien manuel des pilotes devient lourd (plusieurs clusters Kubernetes vers le même Ceph : F2/F4) : réévaluation à ce moment. Longhorn reste une option pour une **agence** sans Ceph (k3s, M18).
4. Volumes locaux (O5) : non retenus en v1 ; à réévaluer pour une base dont la latence d'écriture durable serait le facteur limitant, avec CloudNativePG (réplication applicative) et des nœuds dédiés.

## Conséquences

Positives : données hors du cluster (un cluster Kubernetes perdu se reconstruit et se raccroche à ses volumes) ; une seule technologie de stockage à exploiter ; chiffrement de bout en bout disponible.

Négatives et actions :
| Conséquence | Action | Module / date |
|---|---|---|
| `k8s-par1` dépend du VLAN 30 et de `ceph-par1` : une panne de Ceph arrête toutes les applications avec état | supervision croisée (E27 + `ms-verif-ceph`) ; capacité du pool suivie | M16-E27, M21 |
| Clés cephx et KEK dans des Secrets du cluster (lisibles par ses administrateurs, et par le *nodeplugin*) | KMS externe (Vault/OpenBao) pour la KEK ; rotation des clés cephx | M25 |
| Compatibilités croisées Ceph ↔ ceph-csi ↔ Kubernetes à suivre à chaque montée de version | RB-164, politique de versions (ADR-0141) | M16-E33, F4 |
| Un seul site : `ceph-par1` perdu = données perdues hors sauvegardes | sauvegardes hors site (Velero, CNPG vers `s3-01`, puis réplication vers PAR2), RBD mirroring à étudier | F5 |
| Quota du pool `k8s-rbd` partagé par toutes les équipes | quotas par classe et par espace (E20), alerte de capacité | M16-E20, M21 |
