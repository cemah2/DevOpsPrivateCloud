# Réseau externe d'OpenStack (VLAN 52 OS-EXT)

> M10-E12, ticket SEC-1122. Validé par Sophie Laurent (RSSI) le <DATE>, MR <!<NUMÉRO>>.
> Source de vérité de la politique ; sa traduction technique est dans `pare_feu.yml` (`plateforme/ansible`), lignes `ref: M10-E12`.

## 1. Ce qu'il y a sur le VLAN 52

| Adresse | Qui | Géré par |
|---|---|---|
| 10.10.52.1 | VIP de la bordure (VRRP, `gw01`/`gw02`) | Ansible (`keepalived`) |
| 10.10.52.2, .3 | `gw01`, `gw02` | Ansible |
| 10.10.52.200-249 | passerelles des routeurs OpenStack et IP flottantes (`ext-net`) | Neutron ; plage déclarée dans NetBox (« gérée par OpenStack », entièrement utilisée) |
| `osctl01` `ens21` | port du pont `br-ex` (sans adresse) : sortie des routeurs OVN | Kolla |

Le réseau est **directement connecté** à la bordure : aucune route à ajouter. Les instances n'y ont jamais d'adresse propre ; elles y apparaissent par la passerelle de leur routeur (SNAT) ou par leur IP flottante (DNAT + SNAT).

## 2. Politique

| Sens | Source | Destination | Service | Décision | Raison |
|---|---|---|---|---|---|
| Entrant | MGMT (`adm01`) | IP flottantes | tout | autorisé (existant) | administration, diagnostic, vérifications |
| Entrant | VPN d'administration | IP flottantes | SSH, HTTP, HTTPS, ping | autorisé | les développeurs testent leurs environnements |
| Entrant | autres VLAN, LAN maison, Internet | IP flottantes | tout | **refusé** | rien n'est publié depuis OpenStack ; publication future par `lb01`/`lb02` (M07) |
| Sortant | VLAN 52 | `dns01`, `dns02` | DNS 53 | autorisé (existant) | résolution |
| Sortant | VLAN 52 | passerelle 10.10.52.1 | NTP 123, NTS 4460 | autorisé (existant) | heure (données fournisseur, M10-E18) |
| Sortant | VLAN 52 | Internet | HTTP 80, HTTPS 443 | autorisé | dépôts de paquets ; pas de mandataire pour l'instant |
| Sortant | VLAN 52 | Internet | autre (SMTP 25…) | **refusé** | pas de relais de courrier, pas de canal sortant arbitraire |
| Sortant | VLAN 52 | INFRA, MGMT, STOR, autres VLAN | tout | **refusé** | des instances administrées par d'autres équipes ne touchent pas au socle |

Les groupes de sécurité de Neutron s'appliquent **en plus**, au niveau de chaque instance : ils sont de la responsabilité des équipes.

## 3. Écarts et suites

- HTTP/HTTPS vers tout Internet est large : un **mandataire** (ou un miroir de paquets interne) permettra de ne laisser sortir que vers une liste de dépôts. Ticket de suivi : <SEC-…>.
- Les adresses sources sur Internet sont celles de la VIP WAN : une instance malveillante serait vue comme « le lab ». Journalisation des flux sortants du VLAN 52 : module 22.

## 4. MTU

| Réseau | MTU | Pourquoi |
|---|---|---|
| OS-TUN (VLAN 51, tunnels Geneve) | 9000 | transporte 1500 + 58 octets d'encapsulation sans fragmentation |
| Réseaux des projets (Geneve) | **1500** | `path_mtu = 1558` : valeur standard dans les instances, égale à celle de `ext-net` et du lab ; aucune découverte de PMTU nécessaire |
| `ext-net` (flat, VLAN 52) | 1500 | `physical_network_mtus = physnet1:1500` |

On ne donne pas 8942 aux instances : chaque paquet qui sort par un routeur vers `ext-net` (1500) devrait être fragmenté ou provoquer un ICMP « fragmentation nécessaire » que des pare-feu d'instance filtrent souvent ; le gain (trafic entre instances d'un même projet) ne justifie pas ce risque aujourd'hui.
