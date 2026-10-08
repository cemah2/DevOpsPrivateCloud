# Cartographie du réseau du lab PAR1 (socle v1)

> Ticket PLAT-802. Relevé du AAAA-MM-JJ, avant le module 07 (bordure à une seule passerelle).
> Chaque information est suivie de la commande qui permet de la revérifier. Les valeurs entre
> chevrons sont propres à l'installation (voir `lab/inventaire-local.md`).

## 1. Couche 2 sur `pve01`

```
 LAN maison <LAN-MAISON>
   │ (port physique)
 vmbr0  ── tap1000i0 (gw01 ens18, WAN)        ── autres VMs personnelles éventuelles
 vmbr1  (VLAN-aware, SANS port physique, MTU 1500)
   ├── tap1000i1 (gw01 ens19) : trunk, VLAN 10 20 30 31 32 40 41 50 51 52 60 70 99, non étiqueté côté VM
   ├── vmbr1.<VLAN> ─┐ un par VNet (interface VLAN de vmbr1)
   │                 └─ VNet = petit pont : vmgmt, vinfra, … vsandbox
   │                       ├── tap1001i0 (adm01)  dans vmgmt
   │                       ├── tap1002i0 (dns01) … tap1008i0 (dns02) dans vinfra
   │                       └── tapNNNNi0 (VMs jetables) dans vsandbox
```

- Un VNet de la zone SDN `lab` (type VLAN) est un pont Linux (`vinfra`…) dont l'unique « montée » est l'interface VLAN `vmbr1.<VLAN>` : une trame qui sort d'une VM de `vinfra` est étiquetée 20 en entrant dans `vmbr1`, désétiquetée en sortant vers une autre VM de `vinfra`. Les VMs ne voient jamais d'étiquette.
- `gw01` est branché **directement** sur `vmbr1` (carte `net1` sans `tag`) : son port est un *trunk* qui porte tous les VLAN ; `ens19` reçoit des trames étiquetées et les sous-interfaces `ens19.<VLAN>` les séparent.
- La table FDB de `vmbr1` associe chaque MAC à (port, VLAN) ; une entrée dynamique vieillit après 300 s sans trafic (`ageing_time`).

| VLAN | Nom | VNet | Réseau | Passerelle | MTU (VM, sous-interface de `gw01`) |
|---|---|---|---|---|---|
| 10 | MGMT | `vmgmt` | 10.10.10.0/24 | 10.10.10.1 | 1500 |
| 20 | INFRA | `vinfra` | 10.10.20.0/24 | 10.10.20.1 | 1500 |
| 30 | STOR-PUB | `vstopub` | 10.10.30.0/24 | 10.10.30.1 | 1500 (9000 prévu, M07-E15) |
| 31 | STOR-CLU | `vstoclu` | 10.10.31.0/24 | non routé | 1500 (9000 prévu) |
| 32 | COROSYNC | `vcoro` | 10.10.32.0/24 | non routé | 1500 |
| 40 | K8S | `vk8s` | 10.10.40.0/24 | 10.10.40.1 | 1500 |
| 41 | K8S-LB | `vk8slb` | 10.10.41.0/24 | annoncé en BGP (M15) | 1500 |
| 50 | OS-API | `vosapi` | 10.10.50.0/24 | 10.10.50.1 | 1500 |
| 51 | OS-TUN | `vostun` | 10.10.51.0/24 | non routé | 1500 (9000 prévu) |
| 52 | OS-EXT | `vosext` | 10.10.52.0/24 | 10.10.52.1 | 1500 |
| 60 | PROV | `vprov` | 10.10.60.0/24 | 10.10.60.1 | 1500 |
| 70 | DMZ | `vdmz` | 10.10.70.0/24 | 10.10.70.1 | 1500 |
| 99 | SANDBOX | `vsandbox` | 10.10.99.0/24 | 10.10.99.1 | 1500 |

Revérifier :

```
root@pve01:~# ip -br link show type bridge
root@pve01:~# bridge link show | grep -E 'master (vmbr1|v[a-z]+)'
root@pve01:~# bridge vlan show dev tap1000i1
root@pve01:~# pvesh get /cluster/sdn/vnets --output-format json | jq -r '.[] | "\(.vnet) \(.tag)"'
root@pve01:~# grep -A4 '^auto vinfra' /etc/network/interfaces.d/sdn
root@pve01:~# bridge fdb show br vmbr1 | grep -i <MAC-ADM01>
root@pve01:~# tcpdump -e -n -c 6 -i tap1000i1 'vlan and icmp'
```

## 2. Couche 3 : `gw01`

```
                  <LAN-MAISON>, box = passerelle par défaut
                          │
            ens18 <IP-GW01-WAN> (MTU 1500)          wg0 10.255.0.1/30 ── UDP 51820 ── hp01/pbs01 (PAR2)
                    gw01 (VMID 1000)                 wg1 10.255.1.1/24 ── UDP 51821 ── postes d'admin
            ens19 (trunk, sans adresse)
              ├── ens19.10 10.10.10.1/24  ├── ens19.20 10.10.20.1/24  ├── ens19.30 10.10.30.1/24
              ├── ens19.40 10.10.40.1/24  ├── ens19.50 10.10.50.1/24  ├── ens19.52 10.10.52.1/24
              ├── ens19.60 10.10.60.1/24  ├── ens19.70 10.10.70.1/24  └── ens19.99 10.10.99.1/24
```

- Routes : réseaux connectés des sous-interfaces ; 10.20.0.0/16 par `wg0` ; défaut par la box (`ens18`).
- NAT : `masquerade` de 10.10.0.0/16 vers le WAN, sauf vers `pve01` (table `ip nat`).
- Filtrage : `inet filter`, matrice des flux de `host_vars/gw01/pare_feu.yml` (M04, M06).
- `pve01` joint le lab par des routes statiques 10.10.0.0/16, 10.20.0.0/16 et 10.255.1.0/24 **via `<IP-GW01-WAN>`**.

Revérifier :

```
admin@gw01:~$ ip -br addr ; ip route ; ip rule
admin@gw01:~$ ip -d link show ens19.20 | head -n 3
admin@gw01:~$ sudo nft list table ip nat
admin@gw01:~$ sudo wg show
root@pve01:~# ip route | grep -E '10\.(10|20|255)'
```

## 3. Trois trajets

**`adm01` → `git01:443`.** `adm01` (10.10.10.10, `vmgmt`) → passerelle 10.10.10.1 : trame étiquetée 10 sur `vmbr1` vers `tap1000i1` → `gw01` `ens19.10` → routage (réseau connecté 10.10.20.0/24) → filtrage (`forward`, règle « bastion vers tout le lab ») → `ens19.20`, trame étiquetée 20 → `vmbr1` → `vinfra` → `tap1004i0` → `git01`. Pas de NAT. Retour symétrique (état `established`). Vérifier : `ip route get 10.10.20.12` sur `adm01` ; `ip route get 10.10.20.12 from 10.10.10.10 iif ens19.10` sur `gw01` ; `traceroute -T -p 443 git01.par1.medisphere.internal`.

**`runner01` → Internet (paquets Debian).** `runner01` (10.10.20.15) → 10.10.20.1 → `gw01` : règle « lab vers Internet » (destination hors LAN maison) → sortie `ens18` → **NAT** (masquerade : source = `<IP-GW01-WAN>`) → box → Internet. Vérifier : `sudo conntrack -L -s 10.10.20.15 -p tcp --dport 443` sur `gw01` (adresses avant et après traduction).

**`git01` → `pbs01:8007` (sauvegarde vers PAR2).** `git01` → 10.10.20.1 → `gw01` : route 10.20.0.0/16 par `wg0` → règle « git01 vers PBS » → `wg0` chiffre et encapsule en UDP 51820 vers `<IP-HP01-LAN>`, émis par `ens18` (pas de NAT pour ce flux interne au LAN maison) → `hp01`, `wg0` 10.255.0.2 → `vmbr1` de `hp01` → 10.20.10.10. Vérifier : `ip route get 10.20.10.10` sur `gw01`, `sudo wg show wg0 latest-handshakes`, `traceroute -T -p 8007 10.20.10.10` depuis `git01`.

## 4. MTU

| Interface | MTU | Pourquoi |
|---|---|---|
| `vmbr0`, port physique | 1500 | LAN maison |
| `vmbr1`, ports *tap* | 1500 | défaut (passage à 9000 en M07-E15) |
| `gw01` `ens18`, `ens19`, `ens19.<VLAN>` | 1500 | défaut |
| `gw01` `wg0`, `wg1` | 1420 | 1500 − 80 (en-têtes IPv6 40 + UDP 8 + WireGuard 32 : `wg-quick` prévoit le pire cas) |
| VM du VLAN 20 (`eth0`) | 1500 | défaut |

Le MTU se réduit à l'entrée des tunnels : un paquet de 1500 octets avec DF vers PAR2 reçoit un ICMP « fragmentation needed » de `gw01` (à laisser passer : règle `ct state related`). Revérifier : `ip -d link show` ; `ping -M do -s 1392 10.20.10.10` passe, `-s 1400` échoue.

## 5. Points uniques de défaillance

| Élément | Effet de sa perte | Gravité | Traité par |
|---|---|---|---|
| `gw01` (VM, ou son redémarrage) | tout le lab coupé : Internet, PAR2, VPN, routage entre VLAN, NTP, relais DHCP | critique | M07-E24 à E27 (`gw02`, VRRP, conntrackd) |
| `<IP-GW01-WAN>` codée en dur (route de `pve01`, extrémités WireGuard) | une passerelle de secours ne servirait à rien sans changer `pve01` et `hp01` | critique | M07-E26 (VIP WAN) |
| Clés privées WireGuard de `gw01` (sur un seul hôte) | reconstruction de `gw01` = reconfiguration des pairs | élevée | M07-E26 (clés en Vault, partagées) |
| `pve01` lui-même (un seul hyperviseur, un seul `vmbr1`) | tout PAR1 | critique | hors périmètre (M09 : cluster de démonstration ; F5 : PRA vers PAR2) |
| Accès à un service publié par une seule adresse (`git01`, `nbx01`) | indisponibilité pendant toute maintenance du service | moyenne | M07-E12, E13 (répartiteurs) |
| Box maison / lien Internet unique | lab sans Internet ni VPN extérieur (le lab interne fonctionne) | moyenne | accepté (lab) |
| Relais DHCP sur `gw01` seul | plus de baux pour les clients DHCP des VLAN | moyenne | M07-E24 (relais sur les deux passerelles) |

## 6. Écarts avec NetBox

- `gw01` n'a dans NetBox que son IP primaire (10.10.10.1) : ses autres interfaces et adresses ne sont pas modélisées (M06-E15) → à compléter (une interface par VLAN, `wg0`, `wg1`) avant le palier 3, où `.1` devient une VIP et `.2` l'adresse de `gw01`.
