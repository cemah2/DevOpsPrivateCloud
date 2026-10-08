# RB-076 — Transferts qui se figent : MTU et découverte du MTU du chemin

| | |
|---|---|
| **Portée** | Tout chemin routé du lab : fabric, réseaux de stockage en *jumbo frames* (VLAN 30, 31, 51), tunnels WireGuard |
| **Déclencheur** | « Les petites requêtes passent, les gros transferts se figent » ; OSD Ceph qui battent ; SSH qui fige à l'affichage d'une longue sortie |
| **Durée cible** | 15 min jusqu'au diagnostic |
| **Issu de** | INC-3404 (M07-E38) |

## 1. Confirmer la signature (5 min)

Côté **émetteur des données** :

```
$ sudo tcpdump -ni any -c 30 'host <pair> and tcp port <port>'
```

Poignée de main et requête correctes, segments pleins retransmis sans acquittement : trou noir de MTU.

## 2. Mesurer le MTU du chemin sans TCP

```
$ ping -M do -s 1472 -c 2 -I <source> <destination>      # 1500 en IP
$ ping -M do -s 8972 -c 2 -I <source> <destination>      # 9000 en IP (VLAN 30/31/51)
$ tracepath -n <destination>                             # paquet iputils-tracepath
```

Réponse attendue : un écho, ou « Frag needed and DF set (mtu = N) ». **Le silence est l'anomalie.**

## 3. Trouver où disparaît l'ICMP

1. Routeur dont l'interface de sortie est la plus petite (`ip route get <destination> from <source> iif <entrée>`, puis MTU de l'interface de sortie) : `tcpdump -ni <if vers l'émetteur> 'icmp[icmptype] == 3'`. Rien : filtrage de **sortie** du routeur (`nft list chain … output`).
2. Vu sur le routeur, vu dans la capture de l'émetteur, mais l'émetteur ne réduit pas (`ip route get` sans `mtu` en cache) : filtrage d'**entrée** de l'émetteur (ICMP jeté, ou pare-feu à états sans `related`).
3. Vérifier la cohérence des MTU aux deux extrémités de chaque lien (`cat /sys/class/net/<if>/mtu`), et le MTU des VNets côté Proxmox.

## 4. Corriger

- Rétablir les ICMP d'erreur : types 3, 11, 12 en IPv4 ; `packet-too-big` en IPv6. Tout pare-feu à états accepte `ct state { established, related }`.
- Garder un MTU réduit s'il est voulu et cohérent ; ajouter un filet aux frontières : `tcp flags syn tcp option maxseg size set rt mtu` (chaîne `forward`), et/ou `net.ipv4.tcp_mtu_probing = 1` sur les serveurs.
- Ne pas « corriger » en baissant le MTU des serveurs.

## 5. Recette de tout changement de MTU

`ping -M do` aux tailles limites dans les deux sens, `tracepath`, transfert de taille réelle (plusieurs Mo), avant et après ; sur les VLAN de stockage, `ping -M do -s 8972` entre chaque paire de nœuds.
