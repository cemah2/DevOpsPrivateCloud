# RB-085 — Ceph : moniteur hors quorum ou perte de quorum

| | |
|---|---|
| Cluster | `ceph-par1`, moniteurs `mon.ceph01`, `mon.ceph02`, `mon.ceph03` (quorum = 2) |
| Déclencheur | `MON_DOWN`, `MON_CLOCK_SKEW`, ou commandes `ceph` sans réponse |
| Rédigé | M08-E38 (INC-3544) |
| Accès de secours | console `qm terminal 2081/2082/2083` sur `pve01`, agent QEMU (`qm guest exec`) |

## Règles

- **Interdit** sauf décision écrite de la responsable infrastructure, après échec de tout ce qui suit : `ceph mon remove`, `ceph orch daemon rm mon.*`, `monmaptool`, `ceph-mon --extract-monmap` / `--inject-monmap`. Ces procédures servent quand des moniteurs sont **définitivement** perdus ; elles se préparent avec la documentation officielle (*Troubleshooting Monitors*, « Recovering a Monitor's Broken monmap ») et une sauvegarde des magasins.
- Ne jamais `nft flush ruleset` sur un nœud Rocky (efface aussi `firewalld`).

## 1. Le cluster répond-il ?

```
[root@ceph01 ~]# timeout 20 ceph -s ; echo $?
```

- Réponse avec `MON_DOWN` ou `MON_CLOCK_SKEW` : quorum présent, un moniteur à soigner → §3.
- Code 124 (délai dépassé) : **pas de quorum** → §2.

## 2. Sans quorum : interroger chaque moniteur localement

Sur chaque nœud :

```
[admin@ceph0X ~]$ systemctl list-units --all 'ceph-*@mon.*'
[admin@ceph0X ~]$ sudo cephadm shell --name mon.ceph0X -- ceph daemon mon.ceph0X mon_status
```

Relever `state` (`leader`, `peon`, `probing`, `electing`, `synchronizing`), `quorum`, `outside_quorum`. Tant qu'un moniteur est arrêté (`inactive`), le relancer **par systemd** (l'orchestrateur passe par le mgr, qui a besoin du quorum) :

```
[admin@ceph0X ~]$ sudo systemctl start ceph-<FSID>@mon.ceph0X.service
```

Dès que deux moniteurs se voient, le quorum revient : continuer au §3 pour le troisième.

## 3. Un moniteur hors quorum : vérifier dans cet ordre

| # | Vérification | Commande | Correctif |
|---|---|---|---|
| 1 | Unité | `systemctl status ceph-<FSID>@mon.<hôte>.service` | `systemctl unmask`/`start`, ou `ceph orch daemon start mon.<hôte>` si quorum |
| 2 | Écoute | `ss -tlnp \| grep -E ':3300\|:6789'` sur le nœud | relancer le démon ; voir son journal (`cephadm logs --name mon.<hôte>`) |
| 3 | Réseau | depuis un autre nœud : `timeout 3 bash -c '</dev/tcp/10.10.30.5X/3300'` ; sur le nœud : `sudo nft list ruleset` | retirer la règle ou la table étrangère à `firewalld` (`nft delete table …`) ; le pare-feu se gère par `firewalld` et le rôle Ansible |
| 4 | Horloge | `ceph time-sync-status`, `timedatectl`, `chronyc tracking` | `systemctl enable --now chronyd`, `chronyc makestep` ; chercher pourquoi chrony était arrêté |
| 5 | Disque | `df -h /var/lib/ceph` ; `MON_DISK_LOW`/`MON_DISK_CRIT` | libérer de la place (journaux) ; jamais dans le magasin du moniteur |
| 6 | Synchronisation longue | `state: synchronizing` | attendre (un moniteur rattrape les cartes) ; surveiller l'espace disque |

## 4. Vérification

- `ceph quorum_status -f json-pretty` : trois noms dans `quorum_names`.
- `ceph health detail` sans `MON_DOWN` ni `MON_CLOCK_SKEW` (le contrôle d'horloge se refait toutes les 300 s ou à l'élection).
- OSD du nœud concerné `up` : s'ils ont été privés de moniteurs plus de 900 s, ils ont pu être déclarés `down` → RB-083.

## 5. Escalade

Moniteur dont le magasin est corrompu (journal : erreur RocksDB au démarrage) alors que deux autres sont sains : le **redéployer** par l'orchestrateur (`ceph orch daemon redeploy mon.<hôte>` ; s'il ne repart pas, retrait puis réajout par la spécification `mon`), jamais par manipulation de *monmap*. Perte simultanée de deux magasins : incident majeur, procédure de reconstruction depuis les OSD (documentation officielle), après accord de la responsable infrastructure.
