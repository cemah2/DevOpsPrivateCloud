# Le voyage d'un paquet : d'`adm01` à GitLab par les répartiteurs

> Exemple de compte rendu pour M07-E44. Adresses matérielles, numéros de connexion et horodatages sont ceux d'un lab ; les tiens diffèrent. Lab : bordure en VRRP (`gw01` maître, `.2` ; `gw02` secours, `.3` ; VIP `.1`), répartiteurs `lb01` (maître) et `lb02`, VIP 10.10.70.200.

Flux étudié : `adm01` (10.10.10.10, VLAN 10) ouvre `https://gitlab.par1.medisphere.internal` → VIP 10.10.70.200 (VLAN 70) → `lb01` termine TLS → nouvelle connexion TLS vers `git01` (10.10.20.12, VLAN 20).

```
adm01 ──tap1001i0──[vmbr1, VLAN 10]──tap1000i1── gw01 (ens19.10 → ens19.70) ──[VLAN 70]── lb01
lb01 ──[VLAN 70]── gw01 (ens19.70 → ens19.20) ──[VLAN 20]── git01
```

## Couche 2 : pont et VLAN

```
root@pve01:~# bridge -d vlan show dev tap1001i0
port              vlan-id
tap1001i0         10 PVID Egress Untagged
root@pve01:~# bridge fdb show | grep -i bc:24:11:10:01:01
bc:24:11:10:01:01 dev tap1001i0 vlan 10 master vmbr1
root@pve01:~# tcpdump -eni vmbr1 -c 2 'vlan 10 and host 10.10.10.10 and tcp port 443'
bc:24:11:10:01:01 > bc:24:11:10:00:01, ethertype 802.1Q (0x8100), length 78: vlan 10, p 0, ethertype IPv4, 10.10.10.10.52344 > 10.10.70.200.443: Flags [S] …
```

- La trame quitte `adm01` sans étiquette ; le port `tap1001i0` a le VLAN 10 en natif (`PVID Egress Untagged`) : le pont l'étiquette à l'entrée.
- Elle traverse `vmbr1` étiquetée et sort vers le port de `gw01` (trunk) avec son étiquette ; `gw01` la reçoit sur `ens19` et la remet à `ens19.10`.
- La table de commutation apprend chaque adresse **par VLAN** : la même adresse matérielle de `gw01` apparaît sur son port dans chacun des VLAN routés.
- Destination matérielle : celle de `gw01` (réelle, sans `use_vmac`), apprise par ARP pour 10.10.10.1.

## Couche 3 : routage

```
admin@gw01:~$ ip route get 10.10.70.200 from 10.10.10.10 iif ens19.10
10.10.70.200 from 10.10.10.10 dev ens19.70 table main
admin@gw01:~$ ip route get 10.10.20.12 from 10.10.70.10 iif ens19.70
10.10.20.12 from 10.10.70.10 dev ens19.20 table main
```

Deux décisions de routage sur la passerelle, une par connexion. `lb01` sort vers `git01` avec **sa** propre adresse (10.10.70.10) : `git01` ne voit jamais 10.10.10.10, sauf dans `X-Forwarded-For`.

## Filtrage et suivi des connexions

Trace (table dédiée `inet trace_m07`, retirée ensuite) :

```
trace id 6a3f… inet trace_m07 pre packet: iif "ens19.10" ip saddr 10.10.10.10 ip daddr 10.10.70.200 tcp dport 443 tcp flags == syn
trace id 6a3f… inet filter forward rule ct state invalid drop (verdict continue)     ← non concernée
trace id 6a3f… inet filter forward rule ip saddr 10.10.10.0/24 ip daddr 10.10.70.200 tcp dport 443 accept comment "MGMT vers la DMZ publiée" (verdict accept)
trace id 9c11… inet filter forward rule ct state { established, related } accept (verdict accept)   ← paquets suivants
```

Le premier paquet (`new`) descend jusqu'à la règle de la matrice ; les suivants sont acceptés par la règle d'état. `conntrack` :

```
admin@gw01:~$ sudo conntrack -L -d 10.10.70.200
tcp 6 431999 ESTABLISHED src=10.10.10.10 dst=10.10.70.200 sport=52344 dport=443 src=10.10.70.200 dst=10.10.10.10 sport=443 dport=52344 [ASSURED] …
admin@gw01:~$ sudo conntrack -L -d 10.10.20.12
tcp 6 431980 ESTABLISHED src=10.10.70.10 dst=10.10.20.12 sport=40112 dport=443 … [ASSURED] …
```

`conntrackd` (FTFW) réplique ces deux entrées vers `gw02` (cache externe, `conntrackd -e` sur `gw02`) ; il les engagera dans le noyau de `gw02` si celui-ci devient maître.

## Plan de contrôle : VRRP et BGP

```
admin@gw01:~$ sudo timeout 20 tcpdump -ni ens19.10 -vv vrrp
10.10.10.2 > 10.10.10.3: VRRPv3, Advertisement, vrid 10, prio 150, intvl 100cs, length 12, addrs: 10.10.10.1
admin@lb01:~$ sudo timeout 10 tcpdump -ni ens18 -vv vrrp
10.10.70.10 > 10.10.70.11: VRRPv3, Advertisement, vrid 170, prio 150, intvl 100cs, length 12, addrs: 10.10.70.200
admin@gw01:~$ sudo vtysh -c 'show bgp neighbors 10.10.99.251' | grep -E 'Hold time|keepalive'
  Hold time is 9 seconds, keepalive interval is 3 seconds
admin@gw01:~$ sudo timeout 10 tcpdump -ni ens19.99 'tcp port 179'
… 10.10.99.2.179 > 10.10.99.251.46012: Flags [P.], … length 19: BGP   ← KEEPALIVE (19 octets), toutes les 3 s
```

Bascule observée (arrêt propre de keepalived sur `lb01`, RB-070) : `lb02` émet 5 ARP gratuits pour 10.10.70.200 ; `ip neigh` sur `gw01` passe de l'adresse de `lb01` à celle de `lb02` ; la connexion HTTPS en cours est coupée, la suivante aboutit sur `lb02`.

## Réponses aux questions

1. Commuté à chaque traversée de `vmbr1` (4 à l'aller, 4 au retour) ; routé deux fois (MGMT → DMZ, DMZ → INFRA) ; filtré à chaque routage et par le pare-feu local de `git01` ; deux entrées `conntrack` sur `gw01`, répliquées sur `gw02`, plus celles de `lb01`.
2. Seul le premier paquet est en état `new` et parcourt la chaîne ; les suivants sont reconnus et acceptés par la règle d'état en tête.
3. L'adresse réelle de `gw01` ; une bascule exige des ARP gratuits ; `use_vmac` stabiliserait l'adresse.
4. Pas de multicast sur le LAN maison et les VLAN ; une troisième passerelle impose deux `unicast_peer` par membre, générés depuis l'inventaire.
5. 9 s (temps de maintien négocié) ; BFD pour descendre sous la seconde.
6. Non : connexion TCP et session TLS étaient sur `lb01` ; `peers` synchroniserait les tables *stick*, pas les connexions.
7. `bridge fdb`/VLAN : E40 ; `ip route get … iif` et trace : E41, E38 ; `conntrack` : E38 (variante `related`) ; annonces VRRP et KEEPALIVE : E37, E35.
