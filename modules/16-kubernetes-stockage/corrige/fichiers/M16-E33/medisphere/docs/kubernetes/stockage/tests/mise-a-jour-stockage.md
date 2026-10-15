# Mise à jour du stockage — compte rendu M16-E33 (CHG-1733)

| | |
|---|---|
| Date, fenêtre | <AAAA-MM-JJ HH:MM-HH:MM> |
| Composants | ceph-csi <DE> → <VERS> ; CloudNativePG <DE> → <VERS> ; plugin Barman Cloud <DE> → <VERS> (ou : répétition générale par redémarrage contrôlé, faute de corrective plus récente) |
| Prérequis | sonde verte, Velero `<SAUVEGARDE>` `Completed`, sauvegarde de base `<NOM>` `completed`, instantané etcd <HEURE> |

## Chronologie et témoins

| Heure | Étape | API (échecs, plus longue coupure) | Écritures RBD (trous > 2 s) | Écritures CephFS | Provisionnement (PVC non liés) |
|---|---|---|---|---|---|
| | ceph-csi CephFS | | | | |
| | ceph-csi RBD | | | | |
| | Opérateur (mise à jour en place : <oui/non>) | | | | |
| | Plugin Barman Cloud | | | | |

## Constats

- Écritures sur volumes montés pendant le redémarrage du *nodeplugin* : <continues / trou de N s> — explication : …
- Instances PostgreSQL : <redémarrées / non> ; bascule : <oui/non>.
- Sidecar du plugin : <image changée / non> ; archivage interrompu <N> s.

## Contrôles finaux

| Contrôle | Résultat |
|---|---|
| Images à la version cible (tous les pods) | |
| Sonde `ms-verif-k8s-stockage` | |
| Sauvegarde de base à la demande | |
| PVC `ceph-rbd-chiffre` créé et monté | |
| Témoins supprimés | |
