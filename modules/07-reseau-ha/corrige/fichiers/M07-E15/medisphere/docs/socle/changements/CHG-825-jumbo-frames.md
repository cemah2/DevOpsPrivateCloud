# CHG-825 — Jumbo frames (MTU 9000) sur les réseaux de stockage

| | |
|---|---|
| Demandeur | Claire Morel (préparation du module 08 : Ceph) |
| Exécutant | <MOI> |
| Fenêtre | <AAAA-MM-JJ>, <HH:MM>-<HH:MM> (30 min ; coupure possible du lab : 1 min au plus) |
| Risque | moyen : touche le pont de tout le lab (`vmbr1`), la zone SDN et la carte trunk de `gw01` |
| Validation | Karim Benali (technique), Nadia Roussel (astreinte prévenue) |

## Objet

MTU 9000 de bout en bout sur les VLAN 30 (STOR-PUB), 31 (STOR-CLU) et 51 (OS-TUN) ; tous les
autres VLAN restent à 1500 (PLAN §4.9). Préparer Ceph (M08) et l'overlay Geneve d'OpenStack (M10).

## Principe

L'**infrastructure** (pont `vmbr1`, ponts des VNets, carte trunk de `gw01`) devient capable de
9000 ; le MTU **effectif** est décidé par chaque extrémité : seules les cartes des VMs des VLAN
30/31/51 et la sous-interface `ens19.30` de `gw01` passent à 9000. Les autres sous-interfaces de
`gw01` ont leur MTU de 1500 **écrit** (une sous-interface VLAN hérite du MTU de son parent).

## Pré-requis (avant la fenêtre)

- [ ] Instantané de `gw01` : `ms-snapshot --prefix avant-chg825 1000`
- [ ] Accès de secours à `gw01` vérifié : `qm terminal 1000` (console série) et `qm guest cmd 1000 ping`
- [ ] Copies : `/etc/network/interfaces` de `pve01` (`/root/interfaces.avant-chg825`) et de `gw01`
- [ ] Configuration SDN relevée : `pvesh get /cluster/sdn/zones/lab --output-format json`
- [ ] Mesure « avant » : `ping -M do -s 1472` et `-s 8972` entre les VMs de test (VLAN 30, 31)

## Étapes (dans cet ordre : du plus large au plus étroit)

| # | Action | Contrôle | Retour arrière |
|---|---|---|---|
| 1 | `pve01` : `mtu 9000` dans le bloc `vmbr1`, `ifreload -a` | `ip -d link show vmbr1` : mtu 9000 ; `vmbr0` inchangé (1500) | remettre la copie, `ifreload -a` |
| 2 | Zone SDN `lab` : `mtu 9000`, appliquer (`pvesh set /cluster/sdn`) | `/sys/class/net/vstopub/mtu` = 9000 ; VMs du socle toujours joignables | `pvesh set /cluster/sdn/zones/lab --delete mtu`, appliquer |
| 3 | `gw01` : `mtu 1500` écrit sur chaque sous-interface sauf `ens19.30` (9000) ; `mtu 9000` sur `ens19` | relu, pas encore appliqué | copie de `/etc/network/interfaces` |
| 4 | Carte `net1` de `gw01` : `mtu=9000` (même MAC) ; redémarrage de `gw01` si la modification est en attente | `ip link` sur `gw01` : `ens19` 9000, `ens19.30` 9000, autres 1500 | `mtu=1500` sur `net1`, fichier d'origine, redémarrage |
| 5 | Cartes des VMs de test des VLAN 30/31 : `mtu = 9000` (OpenTofu) | dans l'invité : 9000 | `mtu` retiré, `apply` |

## Vérification

- `ping -M do -s 8972` (8972 + 8 ICMP + 20 IP = 9000) : passe entre deux VMs du VLAN 31, et de
  `srv01` vers `10.10.30.1` (`gw01`).
- Depuis le VLAN 30, vers un VLAN à 1500 : `gw01` renvoie « Frag needed and DF set (mtu = 1500) »
  (PMTUD) ; il n'y a pas de trou noir.
- Rien n'a changé ailleurs : `adm01`, `dns01`, `git01` restent à 1500 ; `ping -M do -s 1473` depuis
  `adm01` vers `dns01` échoue toujours localement (« message too long »).

## Communication

Nadia prévenue avant et après ; message dans le canal de l'équipe à l'ouverture et à la fermeture.
