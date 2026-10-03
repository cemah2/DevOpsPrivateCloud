# Matrice des flux du socle v0

> Exemple de corrigé M00-E50, aligné sur le fichier de référence `/etc/nftables.conf` de
> M00-E26 (+ E31 pour le NTP, + E27 pour le pare-feu Proxmox, + E21 pour `pbs01`).
> `pbs01` émet vers PAR1 depuis 10.20.10.10 (routes `src` de son `wg0`, M00-E21) : PAR2 = 10.20.0.0/16
> dans toutes les règles, sans exception pour l'interconnexion 10.255.0.0/30.
> Chaque ligne cite la règle qui l'implémente (son `comment` quand elle en a un).
> Contrôle de cohérence : `nft list ruleset` sur `gw01`, ligne à ligne.
> Valeurs d'exemple : `<LAN-MAISON>` = 192.168.1.0/24, `<IP-PVE01>` = .20, `<IP-HP01-LAN>` = .30.

## 1. Principes

- Politique par défaut **`drop`** en entrée (`input`) et en transit (`forward`) sur `gw01` ; sortie (`output`) de `gw01` autorisée.
- États : `ct state invalid drop`, puis `ct state { established, related } accept` en tête de `input` et `forward`. Les réponses et les ICMP **liés** à un flux autorisé (dont « fragmentation needed », indispensable à la PMTUD : voir M00-E41) passent sans règle dédiée.
- Toute règle porte un `comment` ; tout refus final est journalisé (`nft-in-drop:`, `nft-fwd-drop:`, limité à 10/min).
- Sens : « → » = sens d'initiation de la connexion.

## 2. Flux à destination de `gw01` (chaîne `input`)

| # | Source | Destination | Proto/port | Justification | Règle (`inet filter input`) |
|---|---|---|---|---|---|
| I1 | tout | `gw01` | ICMP echo-request, dest-unreachable, time-exceeded, parameter-problem (20/s) ; ICMPv6 dont NDP | diagnostic, PMTUD, NDP | `icmp type { … } limit rate 20/second accept` |
| I2 | `<LAN-MAISON>` via `ens18` | `gw01` | TCP/22 | accès de secours | « SSH depuis le LAN maison (accès de secours) » |
| I3 | MGMT 10.10.10.0/24, VPN `wg1` | `gw01` | TCP/22 | administration | « SSH depuis MGMT (adm01) et le VPN d'admin » |
| I4 | VLANs routés du lab (`LAB_IFS`) | `gw01` | UDP/123 | serveur de temps du lab | « NTP (chrony) pour les VLANs du lab » |
| I5 | PAR2 10.20.0.0/16 via `wg0` | `gw01` | UDP/123 | temps de `pbs01` | « NTP pour PAR2 » |
| I6 | clients VLAN 99 (`ens19.99`) | `gw01` | UDP 68→67 | relais DHCP | « clients DHCP du VLAN 99 vers le relais » |
| I7 | `dns01` via `ens19.20` | 10.10.99.1 | UDP 67→67 | réponses du serveur DHCP au relais (non reconnues par conntrack) | « réponses de dns01 adressées au giaddr » |
| I8 | `<LAN-MAISON>` via `ens18` | `gw01` | UDP/51821 | VPN d'administration `wg1` | « wg1 : VPN d'administration » |
| I9 | `<IP-HP01-LAN>` via `ens18` | `gw01` | UDP/51820 | tunnel inter-sites `wg0` | « wg0 : tunnel vers PAR2 » |
| I× | tout le reste | `gw01` | — | — | journalisation `nft-in-drop:` puis politique `drop` |

## 3. Flux routés par `gw01` (chaîne `forward`)

| # | Source | Destination | Proto/port | Justification | Règle (`inet filter forward`) |
|---|---|---|---|---|---|
| F1 | MGMT 10.10.10.0/24, VPN 10.255.1.0/24, `pve01` | toute destination | ICMP echo-request | diagnostic depuis les postes d'administration | `ip saddr { … } icmp type echo-request accept` |
| F2 | MGMT (`ens19.10`) | tous les VLANs du lab, PAR2 (`wg0`) | tout | bastion `adm01` : administration de tout le lab | « bastion (MGMT) vers tout le lab et PAR2 » |
| F3 | VPN `wg1` | MGMT, INFRA | tout | poste d'administration distant | « VPN d'admin vers MGMT et INFRA » |
| F4 | VPN `wg1` | PAR2 MGMT 10.20.10.0/24 | tout | interface PBS depuis le poste | « VPN d'admin vers PAR2 MGMT » |
| F5 | MGMT | `<IP-PVE01>` | TCP/22, TCP/8006 | administration de l'hyperviseur (SSH, API) | « adm01 vers pve01 (SSH, API) » |
| F6 | VPN `wg1` | `<IP-PVE01>` | TCP/22, TCP/8006 | administration de l'hyperviseur depuis un poste hors du LAN maison (pas de NAT : `pve01` répond par sa route 10.255.1.0/24 via `gw01`) | « VPN d'admin vers pve01 (SSH, API) » |
| F7 | MGMT | `<IP-HP01-LAN>` | TCP/22, TCP/8007 | **transition M00-E20**, avant le tunnel | « adm01 vers hp01 par le LAN » — **dette : à retirer** (accès désormais par `wg0`, SSH de secours direct depuis le LAN maison) |
| F8 | `<IP-PVE01>` via `ens18` | VLANs du lab | TCP/22 | vérifications lancées depuis `pve01` avant M00-E15 | « pve01 vers les VMs » — **dette : à retirer** (les vérifications partent de `adm01`) |
| F9 | lab 10.10.0.0/16, PAR2 10.20.0.0/16, VPN 10.255.1.0/24 | `dns01` 10.10.20.10 | UDP+TCP/53 | résolution de noms | « DNS du lab (UDP et TCP) vers dns01 » |
| F10 | `dns01` via `ens19.20` | Internet via `ens18` | UDP+TCP/53 | récursion vers `<DNS-AMONT>` | « dns01 vers les résolveurs amont » |
| F11 | VLAN 99 | `dns01` | UDP 68→67 | renouvellement DHCP en unicast (T1) | « renouvellements DHCP (T1) en unicast vers dns01 » |
| F12 | `<IP-PVE01>` via `ens18` | `pbs01` 10.20.10.10 via `wg0` | TCP/8007 | sauvegardes PVE → PBS | « pve01 vers PBS » |
| F13 | VLANs routés du lab | Internet (`ens18`, sauf `<LAN-MAISON>`) | tout | mises à jour, dépôts, API publiques | « lab vers Internet (NAT) » |
| F× | tout le reste | — | — | — | journalisation `nft-fwd-drop:` puis politique `drop` |

Refus notables (implicites, à connaître) : VLANs du lab → LAN maison (sauf F5, F7) ; VLAN 99
(sandbox) → autres VLANs du lab (sauf DNS/DHCP) ; PAR2 → PAR1 (sauf DNS et NTP) ; LAN maison → lab
(sauf F8 et F12) ; VPN → LAN maison (sauf F6 vers `pve01`).

## 4. Flux émis par `gw01` (chaîne `output`, politique `accept`)

| # | Destination | Proto/port | Justification |
|---|---|---|---|
| O1 | serveurs du pool NTP (Internet) | UDP/123 | source de temps du lab |
| O2 | `dns01` | UDP 67→67 | relais DHCP vers le serveur |
| O3 | `<IP-HP01-LAN>` / poste admin | UDP/51820, UDP/51821 | encapsulation WireGuard |
| O4 | `dns01`, dépôts Debian | UDP+TCP/53, TCP/80-443 | résolution et mises à jour de `gw01` |
| O5 | émetteurs du lab | ICMP (dest-unreachable dont frag-needed, time-exceeded) | erreurs générées par le routeur : **ne jamais filtrer** |

## 5. Traduction d'adresses (`ip nat postrouting`)

| # | Sortie | Sources | Action | Justification |
|---|---|---|---|---|
| N1 | `ens18` | 10.10.0.0/16, sauf vers `<IP-PVE01>` | masquerade | sortie Internet ; `pve01` voit les vraies sources (route statique de retour) |
| N2 | `wg0` | `<LAN-MAISON>` | masquerade (→ 10.255.0.1) | retour symétrique par le tunnel : `hp01` est aussi sur le LAN maison |

## 6. Autres pare-feu du socle

| Hôte | Moteur | Entrant autorisé | Référence |
|---|---|---|---|
| `pve01` | pare-feu Proxmox (datacenter + hôte), `policy_in: DROP` | TCP/8006, TCP/22, ICMP echo depuis l'IPSet `management` (`<LAN-MAISON>`, 10.10.10.0/24, 10.255.1.0/24) | M00-E27 |
| `pbs01` | nftables, politique `drop` | UDP/51820 depuis `<IP-GW01-WAN>` ; TCP/22 et 8007 via `wg0` depuis MGMT et VPN ; TCP/8007 depuis 10.255.0.1 (sauvegardes) ; TCP/22 de secours depuis le LAN maison | M00-E21 |
| VMs du socle | pas de pare-feu de VM en v0 (décision : filtrage inter-VLAN par `gw01` seul ; micro-segmentation à concevoir) | — | ADR à rédiger |

## 7. Écarts et actions

| Écart | Action | Échéance |
|---|---|---|
| F7, F8 : règles de transition encore présentes | supprimer après validation (CHG) | v0.1 |
| ICMP F1 large (toute destination) | restreindre si besoin en v1 | à revoir au module 07 |
| Pas de filtrage est-ouest dans un même VLAN | étudier le pare-feu de VM (M00-E39) | module 26 |
