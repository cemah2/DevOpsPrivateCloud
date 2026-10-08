# RB-094 — Ceph hyperconvergé : PG inactifs, VMs figées

| | |
|---|---|
| **Périmètre** | Ceph de `pveceph` du cluster `hv-par1` (MON/MGR sur `hv01-03`, 2 OSD par nœud), stockage `ceph-vm` (pool répliqué 3/2, domaine de panne « hôte »), réseaux public 10.10.30.0/24 et cluster 10.10.31.0/24 en MTU 9000 |
| **Déclencheurs** | Invités : `task … blocked for more than 120 seconds`, E/S qui ne reviennent pas ; `ceph health` en `HEALTH_WARN`/`HEALTH_ERR` avec `PG_AVAILABILITY` ou `SLOW_OPS` |
| **Gravité par défaut** | P1 (toutes les VMs sur `ceph-vm` sont susceptibles d'être figées) |
| **Liens** | RB-090 (maintenance : `noout`), RB-093 (quorum), M08 (Ceph), M09-E39 |
| **Version** | 1.0 — rédigé après INC-3645 |

## 1. Ce qu'il faut savoir avant d'agir

- Un PG accepte des écritures seulement s'il a au moins `min_size` copies (2). Au-dessous, il est `peered` mais pas `active` : les écritures **attendent**, sans erreur. Les VMs ne plantent pas, elles se figent, et reprennent **seules** quand le PG redevient `active`.
- **Ne pas redémarrer les VMs figées** : elles se figeront de nouveau, et le redémarrage peut abîmer leurs systèmes de fichiers.

## 2. Lecture (5 minutes, sur n'importe quel nœud)

```
root@hv01:~# ceph -s
root@hv01:~# ceph health detail
root@hv01:~# ceph osd tree
root@hv01:~# ceph pg dump_stuck inactive | head
root@hv01:~# ceph osd dump | grep -E '^flags|^pool'
```

Consigner les sorties dans le journal de l'incident.

## 3. Arbre de décision

| Constat | Piste | Vérification | Action |
|---|---|---|---|
| OSD `down` sur un ou plusieurs hôtes | démons arrêtés, désactivés, ou disque mort | `systemctl status ceph-osd@<id>`, `is-enabled`, `journalctl -u ceph-osd@<id>` | `systemctl enable --now ceph-osd@<id>` ; disque mort : remplacement (M08), **sans** toucher à `min_size` |
| Assez d'OSD `up` mais PG inactifs | `min_size` relevé | `ceph osd pool get <pool> min_size` | remettre `min_size 2` (pool 3 répliques) |
| OSD qui « vont et viennent », `wrongly marked me down`, `slow ops` | réseau, souvent MTU | `ping -M do -s 8972` et `-s 1472` entre chaque paire d'hôtes, réseaux public et cluster ; `nft list ruleset` ; `ip -d link` | rétablir la MTU de bout en bout (ou retirer le filtrage) |
| `OSD_FULL`, `POOL_FULL` | plein | `ceph df`, `ceph osd df` | libérer de la place ; **ne pas** relever les ratios sans plan |
| MON en minorité | quorum Ceph | `ceph mon stat`, `ceph quorum_status` | voir l'hôte du MON absent (disque plein, horloge) |

## 4. Gestes interdits

- `ceph osd pool set <pool> min_size 1`, même « le temps de réparer ».
- `ceph osd out`, `ceph osd purge`, `ceph osd destroy` d'un OSD arrêté sans diagnostic.
- Redémarrer des nœuds entiers pour relancer des OSD.
- Laisser `noout` posé après une maintenance.

## 5. Retour à la normale

- [ ] `HEALTH_OK`, 6 OSD `up` et `in`, tous les PG `active+clean`.
- [ ] Aucun drapeau (`noout`, `norecover`, `nobackfill`, `pause`) oublié ; pool de `ceph-vm` en 3/2.
- [ ] Trames de 9000 octets entre chaque paire d'hôtes sur les deux réseaux.
- [ ] Une VM figée a repris sans redémarrage (vérifier `dmesg` de l'invité) ; écriture d'essai sur le pool réussie.
- [ ] `lab/bin/check 09 39` (lab) / `ms-verif-cluster` (production) verte ; post-mortem.
