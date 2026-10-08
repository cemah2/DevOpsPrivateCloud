# RB-083 — Ceph : un OSD est hors service (`down` ou `out`)

| | |
|---|---|
| Cluster | `ceph-par1` (cephadm, Tentacle 20.2), nœuds `ceph01-03`, trousseau admin sur `ceph01` |
| Déclencheur | alerte `OSD_DOWN`, `OSD_HOST_DOWN`, ou OSD `up` mais `out` (capacité utile en baisse) |
| Rédigé | M08-E35 (INC-3541) ; testé sur les trois variantes de la panne |
| Durée | 15 à 30 min de diagnostic ; récupération selon le volume |
| Renvoie vers | RB-080 (remplacer un disque défaillant) quand l'OSD ne peut pas revenir |

## Règles

- **Interdit tant que ce runbook n'a pas conclu « remplacer »** : `ceph osd purge`, `ceph osd destroy`, `ceph orch osd rm --zap`, `ceph-volume lvm zap`, `ceph osd lost`.
- Un OSD `down` n'est pas un disque mort. Un OSD `out` n'est pas en panne.
- Toute commande passée est notée dans le journal de l'incident (`docs/socle/journal/`).

## 1. Constater (5 min, sans rien modifier)

```
[root@ceph01 ~]# ceph health detail
[root@ceph01 ~]# ceph osd tree                    # STATUS (up/down), REWEIGHT (0 = out)
[root@ceph01 ~]# ceph osd df tree                 # PGS : un OSD sans PG est hors placement
[root@ceph01 ~]# ceph log last 50 info cluster | grep osd.<ID>
```

Relever : identifiant, hôte, classe, `down`/`out`, depuis quand, signalé comment (« marked itself down » = arrêt propre ; « reported failed by » = plantage ou réseau).

## 2. Protéger (si l'OSD peut revenir rapidement)

- OSD `down` mais encore `in`, intervention prévue de moins de `mon_osd_down_out_interval` (600 s) ou plus longue mais maîtrisée : `ceph osd set-group noout <hôte>` (ou `ceph osd set noout`). **Noter l'heure** : le retirer est la dernière étape.
- OSD manifestement perdu (disque mort) : **ne rien poser** ; laisser Ceph le passer `out` et recopier ses données.

## 3. Arbre de décision

| Constat | Commande de preuve | Décision |
|---|---|---|
| `up`, REWEIGHT 0, aucun PG | `ceph log last 200 debug audit \| grep -E 'osd (out\|reweight)'` | Décision humaine : retrouver qui et pourquoi ; si rien ne la justifie, `ceph osd in <ID>`. |
| Unité masquée | `systemctl status ceph-<FSID>@osd.<ID>.service` → `Loaded: masked` | Retrouver pourquoi (intervention en cours ?). Sinon `systemctl unmask …` puis `ceph orch daemon start osd.<ID>`. |
| Unité arrêtée proprement (`inactive`, journal « Stopped ») | `cephadm logs --name osd.<ID> \| tail` | `ceph orch daemon start osd.<ID>`. |
| Unité en échec, journal du démon sur une erreur d'E/S (`EIO`, `aio error`) | `dmesg -T \| tail`, `cat /sys/block/<sdX>/device/state`, SMART (serveur physique) | Disque suspect. Si le disque est sain et l'état `offline` venait d'une manipulation : `echo running > …/state`, `systemctl reset-failed`, `ceph orch daemon restart osd.<ID>`. Sinon : **RB-080**. |
| Unité en échec, journal sur une assertion logicielle | `cephadm logs`, `ceph crash ls`, `ceph crash info <id>` | Un essai de relance ; s'il replante : ticket, laisser `out`, RB-080 si le magasin est corrompu. |
| Plusieurs OSD d'un même hôte `down` | `ceph health detail` (`OSD_HOST_DOWN`), ping de l'hôte | Problème d'hôte ou de réseau : voir l'hôte d'abord (console `qm terminal`), RB-085 si les MON sont touchés. |
| OSD qui oscillent, `OSD_SLOW_PING_TIME_*` | `ceph health detail`, `ping -M do -s 8972` sur 10.10.31.0/24 | Réseau cluster (MTU, débit) : ne pas relancer les OSD en boucle, traiter le réseau. |

`<FSID>` : `ceph fsid`. `<sdX>` : `ceph osd metadata <ID> | grep '"devices"'`.

## 4. Revenir à la normale

1. L'OSD est `up` et `in` (`ceph osd tree`).
2. Retirer `noout` posé à l'étape 2 (`ceph osd unset-group noout <hôte>` ou `ceph osd unset noout`).
3. Attendre `HEALTH_OK` ; noter la durée de récupération (`ceph -s`, ligne `recovery`).
4. Si l'intervention a touché ce que décrit `plateforme/ceph` (spécification OSD, classes), MR de mise en cohérence.

## 5. Retour arrière

Toutes les actions de ce runbook sont réversibles : `ceph osd out <ID>`, `systemctl mask`, `ceph osd set noout`. Seul le passage à RB-080 (remplacement) engage des opérations irréversibles, avec ses propres contrôles (`ceph osd safe-to-destroy`).

## 6. Après l'incident

- Si la cause est une décision humaine non tracée : action « compte nominatif / procédure » au post-mortem.
- Si le disque est en cause : ticket matériel, suivi des autres disques du même lot.
