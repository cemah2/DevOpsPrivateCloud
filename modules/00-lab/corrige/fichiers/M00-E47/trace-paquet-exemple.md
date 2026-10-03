# Analyse — Chemin d'un paquet de `adm01` vers Internet

> Exemple de compte rendu M00-E47 (référence du corrigé). Sorties **représentatives** :
> adresses MAC, handles, compteurs et topologie SDN exacte varient selon l'installation.
> Valeurs d'exemple : `<IP-GW01-WAN>` = 192.168.1.50, box = 192.168.1.1.

| | |
|---|---|
| Date | AAAA-MM-JJ |
| Auteur | <nom> |
| Flux étudiés | ICMP `adm01` (10.10.10.10) → 9.9.9.9 ; HTTPS `adm01` → deb.debian.org |
| État du lab | après M00-E28 (SDN), pare-feu Proxmox inactif sur les cartes du socle |

## 1. Schéma

```
 adm01 (VM 1001)                         pve01                                   gw01 (VM 1000)                 LAN maison
┌──────────────┐  ┌───────────────────────────────────────────────────────┐  ┌──────────────────────────┐  ┌───────────┐
│ <iface>      │  │ tap1001i0 ──(PVID 10, untagged)──┐                    │  │ ens19 (trunk)            │  │           │
│ 10.10.10.10  ├──┤                                  vmbr1 (VLAN-aware) ──┼──┤  └ ens19.10 10.10.10.1   │  │  box      │
│ gw 10.10.10.1│  │ tap1000i1 ──(trunk : 2-4094 tagged)┘                  │  │ routage + nftables + NAT │  │ .1        │
└──────────────┘  │ tap1000i0 ── vmbr0 ── <carte physique> ───────────────┼──┤ ens18 192.168.1.50 ──────┼──┤           │
                  └───────────────────────────────────────────────────────┘  └──────────────────────────┘  └───────────┘
```

Topologie SDN constatée sur cette installation : *topologie A* (le `tap` est branché directement
sur `vmbr1` avec l'étiquette du VNet `vmgmt`). Preuve :

```
root@pve01:~# ip -d link show tap1001i0 | grep -o 'master [^ ]*'
master vmbr1
root@pve01:~# bridge vlan show dev tap1001i0
port              vlan-id
tap1001i0         10 PVID Egress Untagged
root@pve01:~# bridge vlan show dev tap1000i1
port              vlan-id
tap1000i1         1 PVID Egress Untagged
                  2-4094
```

> Si ton installation montre `master vmgmt`, décris la *topologie B* (bridge du VNet relié à
> `vmbr1`, voir `/etc/network/interfaces.d/sdn`).

## 2. Couche 2 sur l'hyperviseur

```
root@pve01:~# tcpdump -c 2 -eni tap1001i0 icmp
bc:24:11:10:01:00 > bc:24:11:10:00:01, ethertype IPv4 (0x0800), length 98: 10.10.10.10 > 9.9.9.9: ICMP echo request, id 3, seq 1
bc:24:11:10:00:01 > bc:24:11:10:01:00, ethertype IPv4 (0x0800), length 98: 9.9.9.9 > 10.10.10.10: ICMP echo reply, id 3, seq 1
root@pve01:~# tcpdump -c 2 -eni tap1000i1 icmp
bc:24:11:10:01:00 > bc:24:11:10:00:01, ethertype 802.1Q (0x8100), length 102: vlan 10, p 0, ethertype IPv4 (0x0800), 10.10.10.10 > 9.9.9.9: ICMP echo request, id 3, seq 1
```

Annotation : même trame, **4 octets de plus** (étiquette 802.1Q `vlan 10`) sur le port trunk.
MAC destination = carte `ens19` de `gw01` (passerelle 10.10.10.1), apprise par ARP par `adm01`.

## 3. Dans `gw01`

```
root@gw01:~# tcpdump -c 1 -eni ens19 icmp        → ethertype 802.1Q, vlan 10, 10.10.10.10 > 9.9.9.9
root@gw01:~# tcpdump -c 1 -eni ens19.10 icmp     → ethertype IPv4, 10.10.10.10 > 9.9.9.9 (plus d'étiquette)
root@gw01:~# tcpdump -c 1 -eni ens18 icmp        → bc:24:11:10:00:00 > <MAC-BOX>, 192.168.1.50 > 9.9.9.9
```

- L'étiquette est retirée par le pilote 8021q (démultiplexage `ens19` → `ens19.10`).
- Sur `ens18` : nouvelle MAC source (`ens18` de `gw01`), MAC destination = box, **source traduite**
  (masquerade) en 192.168.1.50.

## 4. Conntrack

```
root@gw01:~# conntrack -L -p tcp --dport 443 -s 10.10.10.10
tcp      6 431995 ESTABLISHED src=10.10.10.10 dst=151.101.2.132 sport=48712 dport=443 src=151.101.2.132 dst=192.168.1.50 sport=443 dport=48712 [ASSURED] mark=0 use=1
```

| Champ | Signification |
|---|---|
| `tcp 6` | protocole et numéro IP |
| `431995` | secondes avant expiration (5 jours pour une connexion établie) |
| `ESTABLISHED` | état TCP suivi par conntrack |
| 1er `src=… dst=… sport … dport …` | tuple d'**origine** (paquet tel qu'entré dans `gw01`) |
| 2e `src=… dst=192.168.1.50 …` | tuple de **réponse attendu** : la réponse vise l'adresse WAN, preuve du NAT |
| `[ASSURED]` | trafic vu dans les deux sens ; entrée protégée de l'éviction |

## 5. Trace nftables

Table temporaire créée avec `fichiers/M00-E47/nft-trace.sh 10.10.10.10 9.9.9.9 20`, supprimée ensuite.

Premier paquet :

```
trace id 4f1c0a2b inet filter forward packet: iif "ens19.10" oif "ens18" ip saddr 10.10.10.10 ip daddr 9.9.9.9 … icmp type echo-request …
trace id 4f1c0a2b inet filter forward rule ip saddr { 10.10.10.0/24, 10.255.1.0/24, 192.168.1.20 } icmp type echo-request accept (verdict accept)
trace id 4f1c0a2b ip nat postrouting rule oifname "ens18" ip saddr 10.10.0.0/16 ip daddr != 192.168.1.20 masquerade comment "lab vers Internet et LAN maison" (verdict accept)
```

Deuxième paquet :

```
trace id 7d22e9c1 inet filter forward rule ct state { established, related } accept comment "réponses et ICMP liés (dont PMTUD)" (verdict accept)
```

Pas de passage dans `ip nat postrouting` : la traduction est appliquée par conntrack.

## Réponses aux questions

1. **Étiquette VLAN 10** : attribuée à l'entrée dans `vmbr1` par le PVID du port `tap1001i0`,
   écrite dans la trame à la sortie vers `tap1000i1` (membre étiqueté), retirée dans `gw01` par 8021q.
2. **MAC** : `gw01` route et réécrit l'en-tête Ethernet ; il résout en ARP sa passerelle (la box),
   pas 9.9.9.9.
3. **Conntrack** : voir tableau §4 ; la réponse est reconnue par son tuple de réponse et retraduite
   vers 10.10.10.10.
4. **NAT au premier paquet** : la chaîne `nat` ne voit que les paquets `NEW` ; la suite est traduite
   par conntrack (§5).
5. **`firewall=1`** : apparition de `fwbr1001i0`, `fwln1001i0`, `fwpr1001p0` (moteur iptables) pour
   filtrer le trafic ponté par carte ; inutile avec le moteur nftables.
6. **Segments > 1500 octets sur le `tap`** : TSO/GSO et GRO, découpage/agrégation hors du fil.
7. **Interface physique de `vmbr0`** : paquet déjà traduit, source 192.168.1.50, MAC de `ens18`.
8. **Pannes localisables** : E38 V2 (`tcpdump -ni ens18`, source privée), E43 V3 (`tcpdump -ni ens18
   udp port 51820` + compteur de drop), et E39 V1 (`bridge vlan show dev tap1002i0`).

## Nettoyage

```
root@gw01:~# nft list ruleset | grep -c nftrace      → 0
root@gw01:~# pgrep -x tcpdump || echo aucune capture
root@pve01:~# pgrep -x tcpdump || echo aucune capture
```
