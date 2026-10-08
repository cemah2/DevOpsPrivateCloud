# Matrice des flux du site PAR1

> Document **généré** par `ms-matrice-flux` (plateforme/outils) depuis `inventories/lab/group_vars/role_routeur/pare_feu.yml` (plateforme/ansible). Ne pas le modifier à la main : modifier la matrice par MR, le pipeline republie ce document.

Les flux internes à un VLAN ne traversent pas la bordure : ils sont décrits par les variables `pare_feu_local_*` des hôtes concernés (rôle `pare_feu_local`).

## Objets nommés

| Nom | Valeur | Commentaire |
|---|---|---|
| `WAN` | ens18 |  |
| `V_MGMT` | ens19.10 |  |
| `V_INFRA` | ens19.20 |  |
| `V_STOPUB` | ens19.30 |  |
| `V_K8S` | ens19.40 |  |
| `V_OSAPI` | ens19.50 |  |
| `V_OSEXT` | ens19.52 |  |
| `V_PROV` | ens19.60 |  |
| `V_DMZ` | ens19.70 |  |
| `V_SANDBOX` | ens19.99 |  |
| `LAB_IFS` | { ens19.10, ens19.20, ens19.30, ens19.40, ens19.50, ens19.52, ens19.60, ens19.70, ens19.99 } |  |
| `WG_S2S` | wg0 | tunnel vers PAR2 (M00-E21), sur le maître seulement |
| `WG_ADM` | wg1 | VPN d'administration (M00-E16), sur le maître seulement |
| `WG_LYO` | wg2 | tunnel vers LYO1 (M07-E18), sur le maître seulement |
| `LAN_MAISON` | 192.168.1.0/24 | <LAN-MAISON> |
| `PVE01` | 192.168.1.20 | <IP-PVE01> |
| `HP01_LAN` | 192.168.1.30 | <IP-HP01-LAN> (extrémité WireGuard de PAR2) |
| `GW_WAN_VIP` | 192.168.1.50 | <IP-GW-WAN-VIP> : la bordure vue du LAN maison |
| `GW_WAN_PROPRES` | { 192.168.1.40, 192.168.1.41 } | <IP-GW01-WAN>, <IP-GW02-WAN> |
| `ADM01` | 10.10.10.10 |  |
| `DNS01` | 10.10.20.10 |  |
| `CA01` | 10.10.20.11 |  |
| `GIT01` | 10.10.20.12 |  |
| `NBX01` | 10.10.20.13 |  |
| `RUNNER01` | 10.10.20.15 |  |
| `DNS02` | 10.10.20.16 |  |
| `LB01` | 10.10.70.10 |  |
| `LB02` | 10.10.70.11 |  |
| `VIP_LB` | 10.10.70.200 | lb.par1.medisphere.internal (VRRP, VRID 170) |
| `PBS01` | 10.20.10.10 |  |
| `NETS_LAB` | 10.10.0.0/16 |  |
| `NETS_PAR2` | 10.20.0.0/16 | pbs01 émet vers PAR1 depuis 10.20.10.10 (M00-E21) |
| `NET_VPN` | 10.255.1.0/24 |  |
| `PAR2_MGMT` | 10.20.10.0/24 |  |
| `NET_LYO1` | 10.30.0.0/16 | site LYO1 (M07-E18) |
| `NET_K8S` | 10.10.40.0/24 | nœuds Kubernetes, voisins BGP au module 15 |
| `LEAF01` | 10.10.99.251 | leaf01 (maquette), voisin BGP (M07-E16) |
| `LYO_GW` | 10.10.99.250 | lyo-gw01 : « Internet » de LYO1 (M07-E18) |

## Vers les passerelles (chaîne input)

| # | Entrée | Source | Protocole et ports | Motif | Réf. |
|---|---|---|---|---|---|
| 1 | $WAN | $LAN_MAISON | tcp 22 | SSH depuis le LAN maison (accès de secours, adresse WAN propre) | M00-E10 |
| 2 | $V_MGMT, $WG_ADM |  | tcp 22 | SSH depuis MGMT (adm01, supervision) et le VPN d'admin | M00-E16 |
| 3 | $V_INFRA | $RUNNER01 | tcp 22 | SSH depuis runner01 (pipeline Ansible, adresse INFRA de la passerelle) | M07-E24 |
| 4 | $LAB_IFS |  | udp 123 | NTP (chrony) pour les VLAN du lab | M00-E31 |
| 5 | $LAB_IFS |  | tcp 4460 | NTS-KE (chrony) pour les VLAN du lab | M06-E21 |
| 6 | $WG_S2S | $NETS_PAR2 | udp 123 | NTP pour PAR2 (via wg0) | M00-E31 |
| 7 | $WG_S2S | $NETS_PAR2 | tcp 4460 | NTS-KE pour PAR2 (via wg0) | M06-E21 |
| 8 | $V_INFRA | $CA01 | tcp 80 | défi ACME HTTP-01 de ca01 (certificats NTS des passerelles) | M06-E21 |
| 9 | $V_SANDBOX |  | udp src 68 67 | clients DHCP du VLAN 99 vers le relais | M00-E14 |
| 10 | $V_INFRA | $DNS01, $DNS02 | udp src 67 67 | réponses des serveurs Kea au relais (giaddr propre) | M07-E24 |
| 11 | $WAN | $LAN_MAISON | udp 51821 | wg1 : VPN d'administration | M00-E16 |
| 12 | $WAN | $HP01_LAN | udp 51820 | wg0 : tunnel vers PAR2 | M00-E21 |
| 13 | $V_SANDBOX | $LYO_GW | udp 51822 | wg2 : tunnel de LYO1 (extrémité 10.10.99.1) | M07-E18 |
| 14 | $WAN | $GW_WAN_PROPRES | vrrp | VRRP entre passerelles, WAN (VRID 250) | M07-E26 |
| 15 | $V_MGMT | 10.10.10.2, 10.10.10.3 | vrrp | VRRP entre passerelles, VLAN 10 | M07-E25 |
| 16 | $V_INFRA | 10.10.20.2, 10.10.20.3 | vrrp | VRRP entre passerelles, VLAN 20 | M07-E25 |
| 17 | $V_STOPUB | 10.10.30.2, 10.10.30.3 | vrrp | VRRP entre passerelles, VLAN 30 | M07-E25 |
| 18 | $V_K8S | 10.10.40.2, 10.10.40.3 | vrrp | VRRP entre passerelles, VLAN 40 | M07-E25 |
| 19 | $V_OSAPI | 10.10.50.2, 10.10.50.3 | vrrp | VRRP entre passerelles, VLAN 50 | M07-E25 |
| 20 | $V_OSEXT | 10.10.52.2, 10.10.52.3 | vrrp | VRRP entre passerelles, VLAN 52 | M07-E25 |
| 21 | $V_PROV | 10.10.60.2, 10.10.60.3 | vrrp | VRRP entre passerelles, VLAN 60 | M07-E25 |
| 22 | $V_DMZ | 10.10.70.2, 10.10.70.3 | vrrp | VRRP entre passerelles, VLAN 70 | M07-E25 |
| 23 | $V_SANDBOX | 10.10.99.2, 10.10.99.3 | vrrp | VRRP entre passerelles, VLAN 99 | M07-E25 |
| 24 | $V_MGMT | 10.10.10.2, 10.10.10.3 | udp 3780 | conntrackd : synchronisation des connexions entre passerelles | M07-E27 |
| 25 | $V_SANDBOX | $LEAF01 | tcp 179 | BGP de leaf01 (fabric de la maquette) | M07-E16 |
| 26 | $V_K8S | $NET_K8S | tcp 179 | BGP des nœuds Kubernetes (plage d'écoute K8S, module 15) | M07-E16 |
| 27 | $WG_LYO | 10.255.2.2 | tcp 179 | BGP de lyo-gw01 dans wg2 (65030) | M07-E19 |

## À travers la bordure (chaîne forward)

| # | Entrée | Sortie | Source | Destination | Protocole et ports | Motif | Réf. |
|---|---|---|---|---|---|---|---|
| 1 |  |  | 10.10.10.0/24, $NET_VPN, $PVE01 |  | icmp echo-request | ping traversant depuis les postes d'administration | M00-E10 |
| 2 | $V_MGMT | $LAB_IFS, $WG_S2S, $WG_LYO |  |  | tout | bastion (MGMT) vers tout le lab, PAR2 et LYO1 | M07-E30 |
| 3 | $WG_ADM | $V_MGMT |  | $ADM01 | tcp 22 | VPN d'admin vers le bastion adm01 (SSH, ProxyJump) | M06-E20 |
| 4 | $WG_ADM | $V_INFRA |  |  | tcp 443 | VPN d'admin vers les interfaces web du socle | M06-E20 |
| 5 | $WG_ADM | $V_DMZ |  | $VIP_LB | tcp 443 | VPN d'admin vers les services publiés (GitLab, NetBox) | M07-E13 |
| 6 | $WG_ADM | $WG_S2S |  | $PAR2_MGMT | tout | VPN d'admin vers PAR2 MGMT | M00-E21 |
| 7 | $V_MGMT | $WAN |  | $PVE01 | tcp 22, 8006 | adm01 vers pve01 (SSH, API) | M00-E15 |
| 8 | $WG_ADM | $WAN |  | $PVE01 | tcp 22, 8006 | VPN d'admin vers pve01 (SSH, API) | M00-E16 |
| 9 | $V_INFRA | $V_MGMT | $RUNNER01 | $ADM01 | tcp 22 | runner01 vers adm01 : SSH (pipeline Ansible) | M04-E27 |
| 10 | $V_INFRA | $V_DMZ | $RUNNER01 | $LB01, $LB02 | tcp 22 | runner01 vers lb01, lb02 : SSH (pipeline Ansible) | M07-E12 |
| 11 |  |  | $NETS_LAB, $NETS_PAR2, $NET_VPN, $NET_LYO1 | $DNS01, $DNS02 | tcp+udp 53 | DNS du lab, de PAR2, du VPN et de LYO1 vers les deux récurseurs | M07-E19 |
| 12 | $V_INFRA | $WAN | $DNS01, $DNS02 |  | tcp+udp 53 | récurseurs vers Internet (récursion depuis la racine) | M06-E24 |
| 13 | $V_SANDBOX |  |  | $DNS01, $DNS02 | udp src 68 67 | renouvellements DHCP (T1) en unicast vers le serveur Kea du bail | M06-E25 |
| 14 | $WAN | $V_DMZ | $LAN_MAISON | $VIP_LB | tcp 443 | LAN maison vers la VIP des répartiteurs (après redirection sur la VIP WAN) | M07-E13 |
| 15 | $LAB_IFS, $WG_LYO |  | $NETS_LAB, $NET_LYO1 | $VIP_LB | tcp 80, 443 | services publiés depuis le lab et LYO1 | M07-E13 |
| 16 | $V_DMZ | $V_INFRA | $LB01, $LB02 | $GIT01, $NBX01 | tcp 443 | répartiteurs vers GitLab et NetBox (ré-chiffrement, contrôles de santé) | M07-E13 |
| 17 | $V_INFRA | $V_DMZ | $CA01 | $LB01, $LB02, $VIP_LB | tcp 80 | défi ACME HTTP-01 de ca01 vers les répartiteurs et leur VIP | M07-E12 |
| 18 | $V_INFRA | $V_SANDBOX | $CA01 |  | tcp 80 | défi ACME HTTP-01 vers la maquette (hap01) ; à retirer avec la maquette (M07-E46) | M07-E11 |
| 19 | $V_DMZ | $V_INFRA | $LB01, $LB02 | $CA01 | tcp 443 | répartiteurs vers step-ca (ACME) | M07-E12 |
| 20 | $WG_LYO | $V_INFRA, $V_DMZ | $NET_LYO1 |  | icmp echo-request | LYO1 : ping de diagnostic vers INFRA et DMZ | M07-E18 |
| 21 | $V_SANDBOX |  |  | $ADM01, $RUNNER01 | tcp 8100-8199 | VMs de build vers le serveur HTTP de Packer (adm01, runner01) | M03-E15 |
| 22 | $V_INFRA | $V_SANDBOX | $RUNNER01 |  | tcp 22 | runner01 vers les VMs de build et de test (SSH) | M03-E15 |
| 23 | $V_INFRA | $WAN | $RUNNER01 | $PVE01 | tcp 8006 | runner01 vers l'API de pve01 | M03-E15 |
| 24 | $WAN | $WG_S2S | $PVE01 | $PBS01 | tcp 8007 | pve01 vers PBS | M00-E21 |
| 25 | $V_INFRA | $WG_S2S | $GIT01, $DNS01, $CA01, $NBX01 | $PBS01 | tcp 8007 | sauvegardes applicatives (git01, dns01, ca01, nbx01) vers PBS | M06-E28 |
| 26 | $LAB_IFS | $WAN |  | != $LAN_MAISON | tout | lab vers Internet (traduit vers la VIP WAN) | M07-E26 |

## Traductions d'adresses

| Chaîne | Règle | Motif |
|---|---|---|
| prerouting | `iifname $WAN ip saddr $LAN_MAISON ip daddr $GW_WAN_VIP tcp dport 443 dnat to $VIP_LB:443` | HTTPS publié : VIP WAN vers la VIP des répartiteurs (M07-E13, M07-E26) |
| postrouting | `oifname $WAN ip saddr $NETS_LAB ip daddr != $PVE01 snat to $GW_WAN_VIP` | lab vers Internet et LAN maison, derrière la VIP WAN (M07-E26) |
| postrouting | `oifname $WAN udp sport { 51820, 51821 } snat to $GW_WAN_VIP` | tunnels wg0 et wg1 émis depuis la VIP WAN (M07-E26) |
| postrouting | `oifname $V_SANDBOX ip daddr $LYO_GW udp sport 51822 snat to 10.10.99.1` | tunnel wg2 émis depuis la VIP du VLAN 99 (M07-E26) |
| postrouting | `oifname $WG_S2S ip saddr $LAN_MAISON masquerade` | LAN maison vers PAR2 : retour symétrique par le tunnel (M00-E21) |
