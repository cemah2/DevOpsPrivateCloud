# RB-084 — Ceph : les écritures sont bloquées (cluster ou pool plein)

| | |
|---|---|
| Cluster | `ceph-par1` (Tentacle 20.2) |
| Déclencheur | clients qui attendent sans erreur ; `OSD_FULL`, `POOL_FULL`, `OSD_BACKFILLFULL`, `OSDMAP_FLAGS` (pause) |
| Rédigé | M08-E37 (INC-3543) |
| Valeurs de référence | `nearfull` 0,85 · `backfillfull` 0,90 · `full` 0,95 (politique de stockage, M08-E33) ; quotas : voir `plateforme/ceph` |

## 1. Diagnostic en trois commandes

```
[root@ceph01 ~]# ceph health detail
[root@ceph01 ~]# ceph osd dump | grep -E '^flags|ratio'
[root@ceph01 ~]# ceph df detail ; ceph osd df
```

| Code | Signification | Ce qui est bloqué |
|---|---|---|
| `OSD_FULL` (+ pools marqués pleins) | un OSD au-delà de `full_ratio` | écritures sur les pools qui l'utilisent ; suppressions permises |
| `OSD_BACKFILLFULL` | un OSD au-delà de `backfillfull_ratio` | remplissages vers cet OSD (récupération ralentie) |
| `POOL_FULL` (*running out of quota*) | quota du pool atteint | écritures sur ce pool |
| `OSDMAP_FLAGS` `pauserd,pausewr` | drapeau `pause` | toutes les E/S clientes |

## 2. Faux plein (seuil, quota ou drapeau)

L'occupation réelle (`%USE` de `ceph osd df`) est loin du seuil, ou le pool est loin de la capacité.

1. Retrouver le changement : `ceph log last 200 debug audit | grep -E 'set-(near|backfill)?full-ratio|set-quota|osd (un)?set'`.
2. Remettre les valeurs de référence (dans l'ordre qui garde les seuils ordonnés) :
   ```
   [root@ceph01 ~]# ceph osd set-full-ratio 0.95
   [root@ceph01 ~]# ceph osd set-backfillfull-ratio 0.90
   [root@ceph01 ~]# ceph osd set-nearfull-ratio 0.85
   ```
3. Quota : remettre la valeur de `plateforme/ceph` (`ceph osd pool set-quota <pool> max_bytes <octets>`, `0` = aucun) après accord du propriétaire du pool.
4. Drapeaux : `ceph osd unset pause` ; vérifier aussi `noout`, `norebalance`, `nobackfill`, `norecover` et les retirer s'ils ne correspondent à aucune maintenance en cours.

## 3. Vrai plein

1. **Ne pas** monter `full_ratio` au-delà de 0,97, et seulement le temps de libérer de la place.
2. Libérer : objets de test (`rados -p <pool> ls | grep benchmark_data`, puis `rados -p <pool> cleanup`), instantanés RBD périmés (`rbd snap ls`, `rbd snap rm` après accord), corbeille RBD (`rbd trash ls`).
3. Rééquilibrer si un seul OSD est plein : `ceph balancer status`, mode `upmap`.
4. Ajouter de la capacité (RB-081).
5. Redescendre `full_ratio` à 0,95 dès que possible.

⚠️ Un OSD BlueStore réellement plein peut refuser de démarrer : ne jamais laisser un OSD au-delà de 97 %.

## 4. Vérification

- `ceph health detail` sans `*_FULL` ni `OSDMAP_FLAGS` inattendu.
- Une écriture de test réussit (`sudo wb-sonde-stockage` sur `cephcli01` dans le lab ; en production, sonde `ms-verif-ceph`).

## 5. Retour arrière

Chaque commande se défait par la même commande avec l'ancienne valeur (notée à l'étape 1 dans le journal de l'incident).

## 6. Prévention

- Alerte `nearfull` calculée sur l'occupation **après perte d'un hôte** (sur 3 hôtes : occupation × 1,5).
- Contrôle de dérive des seuils, quotas et drapeaux par `ms-verif-ceph` ; drapeaux de maintenance posés depuis plus de 4 h signalés.
