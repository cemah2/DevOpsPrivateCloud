# Tests de restauration du cloud OpenStack

> Une section par test, la plus récente en tête. Procédure : [`../sauvegarde-restauration.md`](../sauvegarde-restauration.md).
> Valeurs ci-dessous : lab de référence du workbook, **indicatives** — remplace-les par les tiennes.

## 2026-10-21 — Restauration complète de la base (PLAT-1151, M10-E25)

**Objet** : restaurer la base MariaDB du plan de contrôle depuis la sauvegarde complète de la nuit, sur `osctl01`, et mesurer RTO, RPO et réconciliation.

**Conditions** : un seul contrôleur (Galera à un nœud, ProxySQL), Kolla-Ansible 22.2.0, image `quay.io/openstack.kolla/mariadb-server:2026.1-debian-trixie` ; sauvegarde du 2026-10-21 01:30:41 (`full-21-10-2026-1792546241/mysqlbackup-21-10-2026-1792546241.qp.xbc.xbs.gz`, 31 Mo compressés).

**Marqueurs créés après la sauvegarde** (simulent le travail perdu) : projet `essai-restauration` (domaine `medisphere`, ID `8c1f…`), volume `essai-restauration-vol` de 1 Go dans `plateforme` (ID `5e0a…`).

| Heure | Étape | Durée |
|---|---|---|
| 14:02 | Décision, communication (Julien, Nadia) | — |
| 14:04 | `ms-snapshot --prefix avant-restau 2101 2102 2103` | 1 min 40 |
| 14:06 | `HEALTH_OK` de `ceph-par1` vérifié | 0 min 20 |
| 14:07 | `preparer-sauvegarde.sh preparer` (extraction + `--prepare`) | 1 min 10 |
| 14:08 | `kolla-ansible stop -t mariadb` (début de l'interruption des API) | 0 min 50 |
| 14:09 | `--copy-back` dans un conteneur jetable | 0 min 35 |
| 14:10 | `docker start mariadb`, attente `healthy` de `mariadb` et `proxysql` | 1 min 30 |
| 14:12 | Services de nouveau `up` (fin de l'interruption des API) | 2 min |
| 14:14 | Vérifications : marqueurs absents, projets, instances, réseaux d'avant présents | 4 min |
| 14:18 | Réconciliation : image RBD `volume-5e0a…` orpheline trouvée, exportée pour mémoire, supprimée | 8 min |
| 14:26 | `/backup/restore` supprimé ; fin | — |

**Résultats**
- Interruption des API : 5 min (14:08 → 14:13). Plan de données : aucune coupure mesurée (ping de l'IP flottante de `ha-essai01` ininterrompu).
- RTO (décision → service vérifié et réconcilié) : **24 min**.
- RPO réel : 12 h 32 (sauvegarde de 01:30, « incident » à 14:02).
- Orphelins : 1 image RBD (`volumes/volume-5e0a…`), 0 disque d'instance, 0 écart Neutron/OVN (`neutron-ovn-db-sync-util` en mode `log` : rien à corriger, aucun objet réseau créé après la sauvegarde).

**Écarts et actions**
- Le conteneur `nova_conductor` est resté `unhealthy` 3 minutes après le retour de MariaDB (connexions périmées) : redémarré à la main. Action : ajouter au §3 de la procédure (fait).
- La commande de comparaison RBD ↔ Cinder a été écrite pendant le test : intégrée au §6.
- Prochain test : restauration sur un `osctl01` **reconstruit** (F5).
