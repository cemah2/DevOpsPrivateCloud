# RB-093 — Perte de quorum du cluster hv-par1

| | |
|---|---|
| **Périmètre** | Cluster Proxmox VE `hv-par1` (`hv01`, `hv02`, `hv03`), Corosync 3 (knet), deux liens |
| **Déclencheurs** | `cluster not ready - no quorum? (500)` ; nœuds rouges ou « ? » dans l'interface ; alerte `ms-verif-cluster` « quorum » ou « lien Corosync » |
| **Gravité par défaut** | P1 si aucun nœud n'est quorate ; P2 si un seul nœud est isolé |
| **Prérequis** | Accès `root@10.10.10.51-53` depuis `adm01` ; console des nœuds par l'interface de `pve01` (secours) |
| **Liens** | RB-090 (maintenance), RB-091 (perte d'un nœud), RB-092 (mise à jour), M09-E35, M09-E42 |
| **Version** | 1.0 — rédigé après INC-3641 |

## 1. Ce qu'il faut savoir avant d'agir

- Sans quorum, les VMs **continuent de tourner** ; `/etc/pve` passe en lecture seule (aucune création, modification, migration, aucun démarrage).
- Un nœud sans quorum qui porte des ressources HA **se clôture en une minute environ** (watchdog). Si tout le cluster perd le quorum avec la HA armée, tous les nœuds qui portent des ressources HA redémarrent : l'urgence est de comprendre vite, pas d'agir vite.
- Le quorum est une majorité : 2 votes sur 3. `Expected votes`, `Total votes` et `Quorum` (`corosync-quorumtool -s`) disent presque tout.

## 2. Établir la vue par nœud (5 minutes)

```
admin@adm01:~$ for n in 51 52 53; do echo "== 10.10.10.$n"; ssh root@10.10.10.$n 'corosync-quorumtool -s | grep -E "Quorate|Expected|Total|Quorum:"; corosync-cfgtool -s | grep -E "LINK|nodeid"'; done
admin@adm01:~$ for n in 51 52 53; do ssh root@10.10.10.$n 'hostname; systemctl is-active corosync pve-cluster; sha256sum < /etc/corosync/authkey; sha256sum < /etc/corosync/corosync.conf'; done
```

Consigner la sortie dans le journal de l'incident **avant** toute action.

## 3. Arbre de décision

| Constat | Piste | Vérification | Action |
|---|---|---|---|
| Un nœud ne répond pas du tout (SSH, console) | nœud arrêté / planté | console de `pve01`, état de la VM 209x | RB-091 ; les deux autres doivent rester quorate |
| `Total votes: 1` partout, liens « disconnected », `ping` passe | filtrage de l'UDP 5405/5406 | `nft list ruleset` sur chaque nœud, `pve-firewall status`, compteurs | retirer le filtrage non géré ; corriger le pare-feu par le code |
| `Total votes: 1`, liens « disconnected », `ping` ne passe pas | réseau (VLAN 32 **et** MGMT) | `ip -br a`, `ip -d link`, test des deux réseaux | réparer le réseau ; ne pas toucher au quorum |
| `Total votes: 1`, erreurs de déchiffrement dans `journalctl -u corosync` | `authkey` divergente | sommes de `/etc/corosync/authkey` | recopier la clé du nœud de référence, redémarrer Corosync sur les nœuds corrigés |
| `Total votes: 3` mais `Expected votes` > 3 | votes attendus forcés | `corosync-cmapctl -g quorum.expected_votes`, `/etc/pve/corosync.conf` | section 4 |
| `corosync.conf` local ≠ celui de `/etc/pve` | copie locale éditée | `cmp /etc/corosync/corosync.conf /etc/pve/corosync.conf` | remettre la copie de `/etc/pve` (depuis un nœud quorate), redémarrer Corosync sur le nœud |

## 4. Modifier `corosync.conf` sans quorum

Seulement si **tous** les nœuds vivants sont dans la même membre (`Total votes` = nombre de nœuds vivants sur chacun) :

1. `pvecm expected <nombre de nœuds vivants>` sur un nœud (jamais `1` si plus d'un nœud est vivant).
2. `cp /etc/pve/corosync.conf /root/corosync.conf.$(date +%F-%H%M)` (copie de sauvegarde).
3. `cp /etc/pve/corosync.conf /etc/pve/corosync.conf.new`, éditer, **incrémenter `config_version`**, `mv /etc/pve/corosync.conf.new /etc/pve/corosync.conf`.
4. Vérifier sur chaque nœud : `cmp /etc/corosync/corosync.conf /etc/pve/corosync.conf`, `corosync-quorumtool -s`.

## 5. Gestes interdits

- `pvecm expected 1` sur un nœud alors qu'une autre partition est peut-être vivante (*split-brain* de configuration, VMs HA démarrées deux fois).
- `pvecm delnode`, réinstallation, suppression de `/var/lib/pve-cluster/config.db`.
- Édition de `/etc/corosync/corosync.conf` sur un nœud.
- Redémarrage de tous les nœuds « pour voir ».

## 6. Désarmer la HA (Proxmox VE 9.2)

Si le diagnostic doit durer et qu'au moins un nœud est quorate : `ha-manager crm-command disarm-ha freeze` évite les clôtures pendant l'intervention. À lever (`ha-manager crm-command arm-ha`) dès le retour du quorum, et à consigner.

## 7. Retour à la normale

- [ ] `Quorate: Yes`, `Expected votes: 3`, `Total votes: 3` sur les trois nœuds.
- [ ] Les deux liens « connected » vers les deux autres nœuds, sur chaque nœud.
- [ ] `corosync.conf` et `authkey` identiques partout ; aucune table nftables hors liste.
- [ ] HA armée, `ha-manager status` sans `error` ; `ceph -s` `HEALTH_OK`.
- [ ] `lab/bin/check 09 35` (lab) / sonde `ms-verif-cluster` (production) verte.
- [ ] Post-mortem si l'incident a eu un impact (P1/P2).
