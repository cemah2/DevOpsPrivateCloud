# RB-037 — Retirer une image dorée (rotation, retrait d'urgence)

| | |
|---|---|
| **Déclencheur** | rotation hebdomadaire en échec (job `publish:*`, code 3) ; image signalée vulnérable ou défectueuse ; stockage `local-nvme` au-dessus de 80 % |
| **Durée** | 15 min (rotation), 30 min (retrait d'urgence, avec la communication) |
| **Accès** | `adm01`, `~/src/images` à jour (`git pull`), `~/.config/workbook/pve-packer.env` ; SSH root sur `pve01` pour la vérification LVM-thin |
| **Projet** | `plateforme/images`, outils `outils/rotation-images.sh`, `outils/publier-image.sh` |

## Règles

- On garde, par famille, les **3 versions les plus récentes non rejetées**, plus la version `current`, plus la dernière version `rejete` (analyse).
- On ne supprime **jamais** la version `current` : on publie d'abord une autre version.
- On ne supprime **jamais** un template dont des clones liés existent. Les VMs durables sont des **clones complets** (ADR-0030) ; les clones liés sont réservés aux tests, détruits par le test lui-même.
- On ne supprime **jamais** à la main dans l'interface : toujours par l'outil (garde-fous, trace).

## A. Rotation en échec

1. Relire le journal du job : chaque `REFUS` donne le VMID et la raison.
2. Rejouer en simulation depuis `adm01` (rien n'est supprimé) :
   ```
   admin@adm01:~/src/images$ outils/rotation-images.sh --famille debian13 --ssh-pve pve01
   ```
3. Selon la raison :
   - **clones liés détectés** : identifier les VMs (`qm config <ID>` sur `pve01`). VM de test oubliée (`m03-test-*`, 2030-2033) → la détruire. VM durable → c'est un écart à l'ADR-0030 : la rendre indépendante du template avec son propriétaire (déplacer ses disques avec `qm disk move` vers un autre stockage — copie complète — puis les ramener, ou clone complet de la VM et bascule), puis relancer.
   - **invisible pour le jeton** : le template n'est plus dans le pool `lab` → le remettre dans le pool (root sur `pve01` : `pvesh set /pools --poolid lab --vms <VMID>`, ajouter `--allow-move 1` s'il est dans un autre pool), puis relancer.
4. Appliquer : `outils/rotation-images.sh --famille debian13 --appliquer --ssh-pve pve01`.

## B. Retrait d'urgence d'une version (vulnérabilité, défaut)

1. **Prévenir** (canal #plateforme) : version retirée, raison, version de remplacement, impact (les VMs déjà créées ne changent pas).
2. **Si c'est la version `current`** : republier la précédente version saine (le test est rejoué) :
   ```
   admin@adm01:~/src/images$ outils/publier-image.sh <VMID-PRÉCÉDENT>
   ```
   Contrôle : une seule version `current` dans la famille (`pvesh get /cluster/resources --type vm` sur `pve01`, colonne `tags`).
3. **Retirer** la version défectueuse :
   ```
   admin@adm01:~/src/images$ outils/rotation-images.sh --retirer <VMID> --ssh-pve pve01             # simulation
   admin@adm01:~/src/images$ outils/rotation-images.sh --retirer <VMID> --ssh-pve pve01 --appliquer
   ```
4. **Lister les VMs créées depuis cette version** (notes et étiquettes des VMs, inventaire) et ouvrir un ticket pour chacune : correctif par Ansible, ou reconstruction depuis la nouvelle version.
5. Lancer un build correctif (pipeline manuel `build:<famille>`) dès que la cause est corrigée dans le code.

## Vérification

- `outils/rotation-images.sh --famille toutes` (simulation) se termine sans `REFUS` et ne prévoit aucune suppression.
- Une seule version `current` par famille ; au plus 4 versions non rejetées par famille.
- `pvesm status` sur `pve01` : `local-nvme` sous 80 %.

## Pourquoi LVM-thin demande `--ssh-pve`

Sur ZFS, Ceph RBD ou un stockage fichier, le disque d'un clone lié s'écrit `stockage:base-<TEMPLATE>-disk-N/vm-<ID>-disk-M` dans la configuration du clone : l'API suffit à le trouver, et Proxmox refuse de supprimer le volume de base. Sur **LVM-thin**, le clone lié est un instantané thin nommé simplement `vm-<ID>-disk-M` : aucune trace du template dans l'API, et Proxmox laisse supprimer la base (le clone garde ses données, mais on perd la provenance). Seul `lvs -o lv_name,origin` (root sur `pve01`) montre le lien. La CI n'ayant pas d'accès root, la règle « VMs durables = clones complets » est ce qui rend la rotation automatique sûre.
