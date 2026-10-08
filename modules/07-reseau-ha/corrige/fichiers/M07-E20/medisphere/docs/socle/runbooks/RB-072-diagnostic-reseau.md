# RB-072 — Diagnostic réseau : « X ne joint pas Y »

| | |
|---|---|
| Quand | Un hôte, un service ou un site ne joint pas un autre (refus, délai, lenteur, gros transferts figés) |
| Qui | Astreinte (niveau 1 : étapes 0 à 3), équipe Plateforme (au-delà) |
| Durée | 10 à 30 min pour localiser le segment fautif |
| Accès | `adm01` (bastion), `sudo` sur les hôtes ; console Proxmox en secours (`qm terminal <VMID>`) |
| Outils | `ms-diag-chemin` (plateforme/outils), `ip`, `ss`, `tcpdump`, `nft`, `conntrack`, `vtysh`, `wg`, `bridge` |
| Liés | RB-070 (répartiteurs), RB-071 (bascule de la bordure), matrice des flux (`docs/socle/matrice-flux.md`) |

> Règle d'or : **mesurer avant de changer**. Ce runbook ne modifie rien jusqu'à l'étape 6. Chaque
> mesure est notée dans le ticket (commande + extrait de sortie + heure).

## 0. Cadrer (2 min)

Écrire dans le ticket, en une ligne chacun :
- **Source** exacte (hôte, adresse, VLAN) et **destination** exacte (nom, adresse, port, protocole).
- **Symptôme** : refus immédiat, délai dépassé, lenteur, coupure après un temps, gros fichiers seulement.
- **Depuis quand**, et **ce qui a changé** (MR fusionnées, changements `CHG-`, bascules VRRP).
- **Portée** : une seule source ? tout un VLAN ? tout le lab ? Une destination voisine marche-t-elle ?

| Symptôme | Piste prioritaire |
|---|---|
| « Connection refused » immédiat | L4 : service arrêté, mauvais port, `reject` d'un pare-feu |
| Délai dépassé, rien ne revient | L3 : route (aller ou **retour**), filtrage `drop`, ARP |
| Petits échanges OK, gros transferts figés | MTU : trou noir PMTUD (ICMP « frag needed » filtré), MSS |
| Marche puis coupe toutes les N minutes | bascule VRRP, `conntrack` (table pleine, délais), session BGP qui oscille |
| Lenteur | perte (lien d'un agrégat, duplex), file d'attente, ECMP déséquilibré |

## 1. Relevé automatique depuis la source (3 min)

```
admin@adm01:~$ ms-diag-chemin --depuis <SOURCE> <DESTINATION> [<PORT>]
admin@adm01:~$ ms-diag-chemin --depuis <SOURCE> --mtu 9000 <DESTINATION>    # VLAN 30, 31, 51
```
Lire le relevé **dans l'ordre** ; le premier KO désigne la couche à examiner :

| KO à l'étape | Signifie | Aller à |
|---|---|---|
| 1. Résolution | DNS : `resolv.conf`, récurseur joignable (`dig @10.10.20.10`), nom absent de la zone | DNS (RB-06x) |
| 2. Route | pas de route, mauvaise interface, mauvaise **source** | étape 3 |
| 3. Voisin `FAILED` | rien ne répond en ARP sur le lien : VLAN, pont, lien d'agrégat, VM arrêtée | étape 2 |
| 4. ICMP | filtrage ou route de retour | étapes 3 et 4 |
| 5. MTU | trou noir PMTUD | étape 5 |
| 7. TCP | service, port, pare-feu de l'hôte | étape 4 |

## 2. Niveau 2 : le lien et le VLAN

Sur la source, puis sur le prochain saut :
```
$ ip -br link ; ip -br addr                       # interface UP, LOWER_UP, bonne adresse, bon masque
$ ip neigh show dev <IF>                          # MAC du prochain saut connue ?
$ cat /proc/net/bonding/bond0                     # agrégat : membres « up », partenaire LACP identique
root@pve01:~# bridge vlan show dev <tapNNNiM>     # la carte de la VM est-elle dans le bon VLAN ?
root@pve01:~# bridge fdb show br vmbr1 | grep -i <MAC>   # la MAC est-elle apprise, sur quel port ?
root@pve01:~# tcpdump -eni <tapNNNiM> -c 20 arp   # l'ARP sort-il de la VM ? la réponse revient-elle ?
```
Open vSwitch : `ovs-vsctl show`, `ovs-appctl bond/show`, `ovs-appctl lacp/show`, `ovs-appctl fdb/show <PONT>`.

## 3. Niveau 3 : l'aller ET le retour

```
$ ip route get <DEST> [from <SOURCE>]             # sur la source, la passerelle, la destination
root@gw01:~# ip route get <SOURCE> from <DEST> iif <IF_ENTREE>   # le retour, vu par le routeur
root@gw01:~# sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.<IF>.rp_filter
root@gw01:~# vtysh -c 'show ip route <DEST>'      # qui a installé la route : connected, static, bgp
root@gw01:~# vtysh -c 'show bgp summary'          # sessions établies, préfixes reçus/envoyés
root@gw01:~# wg show                              # tunnel : poignée de main récente, octets reçus
```
Pièges : réponse qui part par une **autre** interface (deux routes par défaut, route plus
spécifique ailleurs) → `rp_filter` strict la jette ou le pare-feu à état ne reconnaît pas le
retour ; WireGuard qui jette tout ce qui n'est pas dans `AllowedIPs`.

## 4. Filtrage : `gw01`, l'hôte, le service

```
root@gw01:~# nft list ruleset | less               # la règle attendue existe-t-elle (motif, réf.) ?
root@gw01:~# nft list chain inet filter forward | grep -c counter   # compteurs
root@gw01:~# nft add table inet trace             # ⚠️ table TEMPORAIRE, voir encadré
root@gw01:~# nft add chain inet trace pre '{ type filter hook prerouting priority -350; }'
root@gw01:~# nft add rule inet trace pre ip saddr <SRC> ip daddr <DST> meta nftrace set 1
root@gw01:~# nft monitor trace                     # chemin de la règle qui accepte ou jette
root@gw01:~# nft delete table inet trace           # TOUJOURS, à la fin
root@gw01:~# conntrack -L -s <SRC> -d <DST>        # l'état de la connexion (SYN_SENT ? ASSURED ?)
$ ss -ltnp 'sport = :<PORT>'                       # sur la destination : qui écoute, sur quelle adresse ?
```
> ⚠️ La trace se pose dans une **table dédiée** (`inet trace`), jamais dans la table `inet filter`
> gérée par Ansible, et la table est **supprimée** à la fin. Le prochain passage du rôle
> `pare_feu` la supprimerait de toute façon (`flush ruleset`), mais pas avant.

## 5. MTU

```
$ ping -M do -s 1472 <DEST>        # 1500 au total ; « message too long » = MTU local plus petit
$ ping -M do -s 8972 <DEST>        # 9000 au total (VLAN 30, 31, 51)
$ tracepath -n <DEST>              # « pmtu » annoncé par chaque saut
root@gw01:~# tcpdump -ni any 'icmp[icmptype] == 3 and icmp[icmpcode] == 4'   # « frag needed » émis ?
```
Un MTU différent aux deux bouts d'un même lien ne produit **aucun** ICMP : les grandes trames
sont simplement perdues. Comparer `ip link` des deux côtés **et** le `mtu=` des cartes Proxmox.

## 6. Capturer aux bornes, puis corriger

Capturer **aux deux bornes** du segment suspect, en même temps (`tcpdump -ni <IF> -w /var/tmp/rb072-<hôte>.pcap host <SRC> and host <DST>`) : le paquet sort-il ? entre-t-il ? la réponse
repart-elle ? Le segment fautif est celui où le paquet entre et ne ressort pas.

Corriger **par le code** (MR sur `plateforme/ansible`, `plateforme/infra`), jamais par un changement
à la main laissé en place ; si un geste manuel est nécessaire pour rétablir le service, il est
noté dans le ticket et rattrapé par une MR dans la journée.

## 7. Clore

- Rejouer `ms-diag-chemin` : bilan « jointe ».
- Ticket : cause racine, couche, preuve (extraits), correctif (lien de MR), prévention (sonde,
  check, règle de la matrice).
- Captures supprimées de `/var/tmp` (elles peuvent contenir des données).
