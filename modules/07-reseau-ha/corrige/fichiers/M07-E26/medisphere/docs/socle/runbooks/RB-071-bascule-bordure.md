# RB-071 — Bascule manuelle de la bordure PAR1

| | |
|---|---|
| Portée | `gw01` (1000) et `gw02` (1009) : VIP `.1` des VLAN 10, 20, 30, 40, 50, 52, 60, 70, 99, VIP WAN `<IP-GW-WAN-VIP>`, tunnels `wg0`/`wg1`/`wg2`, `conntrackd` |
| Quand | maintenance d'une passerelle (noyau, redémarrage), retour sur `gw01` après un incident (politique `nopreempt`), test planifié |
| Durée | 15 min ; perte attendue : ≈ 1 s (bascule planifiée, `conntrackd` actif), ≈ 4 s (panne brutale) — chiffres de `docs/socle/tests/bascules.md` |
| Qui | astreinte plateforme ; aucune autorisation préalable hors créneau de sauvegarde PBS |
| Références | CHG-855, CHG-856, ADR-0070, RB-072 (diagnostic réseau), `ms-verif-reseau` (M07-E29) |

## 0. Règles

- On ne bascule **que** si la passerelle qui va prendre la main est saine (étape 1). Sinon on ne touche à rien et on ouvre RB-072.
- On garde une session SSH ouverte sur **chaque** passerelle par son adresse WAN propre (`ssh admin@<IP-GW01-WAN>`, `ssh admin@<IP-GW02-WAN>` depuis `pve01` ou le LAN maison) : elles ne dépendent d'aucune VIP.
- Jamais deux passerelles arrêtées en même temps. Jamais pendant une sauvegarde PBS (`proxmox-backup-manager task list` sur `pbs01`).

## 1. État avant bascule

Depuis `adm01` :

```
admin@adm01:~$ ms-verif-reseau                 # tout OK, sinon STOP
```

Sur chaque passerelle (session WAN) :

```
admin@gw01:~$ cat /run/bordure/etat                     # MASTER sur l'une, BACKUP sur l'autre
admin@gw01:~$ ip -br -4 address | grep -E '\.1/24|<IP-GW-WAN-VIP>'   # VIP : toutes sur le maître, aucune sur l'autre
admin@gw02:~$ sudo conntrackd -s | head -n 20           # le secondaire REÇOIT (compteurs non nuls, sans erreurs)
admin@gw02:~$ sudo conntrackd -e | wc -l                # cache externe non vide
admin@gw02:~$ sudo vtysh -c 'show bgp summary'          # sessions leaf01 (si maquette) établies sur les deux
```

## 2. Bascule planifiée (le maître rend la main)

Sur le **maître actuel** (ici `gw01`) :

```
admin@gw01:~$ sudo systemctl stop keepalived
```

keepalived envoie une annonce de priorité 0 : le secours prend la main **immédiatement** (pas d'attente de 3 annonces). Sur la passerelle de secours devenue maître, en moins de 5 s :

```
admin@gw02:~$ cat /run/bordure/etat                     # MASTER
admin@gw02:~$ ip -br -4 address | grep -c '\.1/24'      # 9
admin@gw02:~$ wg show all latest-handshakes             # wg0 et wg2 : poignée de main < 2 min après la bascule
admin@gw02:~$ sudo journalctl -t bordure --since -5min  # transition MASTER, aucune ligne « ERREUR »
```

Puis `ms-verif-reseau` depuis `adm01` : seul le contrôle de redondance doit être `KO` (keepalived arrêté sur `gw01`).

Faire la maintenance prévue sur `gw01` (mise à jour, redémarrage). Au redémarrage, keepalived démarre en `BACKUP` et **ne reprend pas** la main (`nopreempt`) : c'est voulu.

## 3. Retour sur `gw01`

Quand `gw01` est de nouveau saine (étape 1, rôles inversés : `gw01` en `BACKUP`, cache externe de `conntrackd` rempli) :

```
admin@gw02:~$ sudo systemctl stop keepalived     # gw01 prend la main
admin@gw01:~$ cat /run/bordure/etat               # MASTER
admin@gw02:~$ sudo systemctl start keepalived     # gw02 revient en BACKUP
```

Contrôle final : étape 1 complète, `ms-verif-reseau` entièrement `OK`.

## 4. Cas anormaux

| Constat | Signification | Action |
|---|---|---|
| VIP sur **les deux** passerelles (`ip -br address`), `etat` MASTER des deux côtés | cerveau divisé : les annonces VRRP ne passent plus (filtrage, lien, VRID différent) | 1) sur la passerelle qui ne doit **pas** être maître : `systemctl stop keepalived` (les VIP y disparaissent, les clients suivent les ARP gratuits de l'autre) ; 2) diagnostiquer avec `tcpdump -ni ens19.99 ip proto 112` des deux côtés, `nft list ruleset | grep 'l4proto 112'` ; 3) ne relancer keepalived qu'une fois les annonces vues dans les deux sens |
| VIP sur **aucune** passerelle | les deux en `FAULT` (lien suivi tombé) ou keepalived arrêté des deux côtés | `journalctl -u keepalived` des deux côtés ; si un lien est en cause (`ip link`), rétablir le lien ; en dernier recours, démarrer keepalived sur la passerelle saine |
| Bascule faite mais tunnels absents | script de transition en échec | `journalctl -t bordure` ; `systemctl start wg-quick@wg0` à la main sur le maître ; ouvrir un incident |
| Connexions coupées malgré la bascule planifiée | `conntrackd` ne synchronisait pas | `conntrackd -s` des deux côtés ; règle UDP 3780 de la matrice ; noter l'incident |
| `adm01` ne joint plus `pve01` | `pve01` route encore par une adresse propre | `ip route get 10.10.10.10` sur `pve01` : doit passer par `<IP-GW-WAN-VIP>` |

## 5. Retour arrière de ce runbook

Une bascule se défait par une bascule inverse (étape 3). Si une passerelle est cassée, on la laisse arrêtée (`systemctl stop keepalived` ou VM arrêtée) et on reste sur l'autre ; on restaure l'instantané ou on la reconstruit (`gw02` : `tofu apply` + `routeurs.yml` ; `gw01` : instantané PBS) avant de revenir à deux.
