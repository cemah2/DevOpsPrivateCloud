# Réseau du socle v2 — bordure, points d'entrée, routage

> Socle MédiSphère v2 (étiquette `socle-v2`, M07-E46). Source des valeurs : PLAN §4.2, §4.5, §4.9 ; état vivant : NetBox. Décision d'architecture : ADR-0070.

## Vue d'ensemble

```
          LAN maison <LAN-MAISON>                              box <IP-BOX>
   ─────────┬───────────────────────┬──────────────────────────┬────────────
        pve01 (route 10.10/16,      │ VIP WAN <IP-GW-WAN-VIP>  │   hp01 = pbs01 (PAR2)
        10.20/16, 10.255.1/24       │ (VRID 250)               │   wg0 → VIP WAN:51820
        via la VIP WAN)       ens18 │                    ens18 │
                    <IP-GW01-WAN> ┌─┴─────────┐   ┌─────────┴─┐ <IP-GW02-WAN>
                                  │ gw01 1000 │◄─►│ gw02 1009 │  VRRP v3 unicast, groupe BORDURE
                                  │ prio 150  │   │ prio 100  │  conntrackd (VLAN 10, UDP 3780)
                                  │ wg0 wg1   │   │ (tunnels  │  FRR AS 65000 sur les deux
                                  │ wg2 (maî.)│   │ si maître)│
                                  └─┬─────────┘   └─────────┬─┘
                              ens19 │ trunk MTU 9000    ens19 │
   ═════════════════════════════════╧═══════ vmbr1 ═════════╧══════════════════════
   VLAN 10 MGMT .1 (VIP) .2 .3 ─ adm01        VLAN 30 STOR-PUB (MTU 9000) ─ Ceph (M08)
   VLAN 20 INFRA ─ dns01 dns02 ca01 git01 nbx01 s3-01 runner01
   VLAN 40 K8S ─ (M14 ; BGP vers .2/.3, plage d'écoute K8S)    VLAN 31/51 non routés (MTU 9000)
   VLAN 70 DMZ ─ lb01 .10, lb02 .11, VIP 10.10.70.200 (VRID 170) ─ gitlab./netbox.par1…
   VLAN 99 SANDBOX ─ VMs jetables ; lyo-gw01 10.10.99.250 (Lyon, en attente)
```

## Tableau des adresses virtuelles

| Réseau | VIP | VRID | Porteurs (priorité) | Préemption |
|---|---|---|---|---|
| VLAN 10, 20, 30, 40, 50, 52, 60, 70, 99 | 10.10.V.1 | V | `gw01` .2 (150), `gw02` .3 (100) | non (`nopreempt`) |
| WAN | `<IP-GW-WAN-VIP>` | 250 | `gw01` (150), `gw02` (100) | non |
| DMZ, services publiés | 10.10.70.200 | 170 | `lb01`, `lb02` (M07-E12) | `<selon M07-E12>` |

## Ce qui se passe quand…

| Élément tombé | Effet | Durée | Ce qui le détecte | Runbook |
|---|---|---|---|---|
| `gw01` (maître) | tout bascule sur `gw02`, connexions conservées | ≈ 4 s | `ms-verif-reseau` (redondance) | RB-071 |
| `gw02` (secours) | rien pour les utilisateurs ; plus de redondance | — | `ms-verif-reseau` | RB-071 |
| VLAN 10 seul (lien de `conntrackd`) | plus de synchronisation des connexions, VRRP du VLAN 10 seulement affecté | — | `ms-verif-reseau` (`conntrackd`, VIP) | RB-072 |
| `lb01` ou `lb02` | la VIP 10.10.70.200 passe sur l'autre | ≈ 4 s | `ms-verif-reseau` (`vrrp-dmz`) | RB-070 |
| `git01` ou `nbx01` | page 503 propre derrière les répartiteurs | jusqu'au retour | contrôle de santé, `ms-verif-reseau` (`haproxy`) | runbooks du service |
| `pve01` | **tout** (point unique accepté) | — | supervision externe (M21) | PRA (F5) |
| la box / le LAN maison | Internet, PAR2, VPN, publication depuis le LAN | — | — | — |

## Routage dynamique

FRR 10.7 sur `gw01` et `gw02`, AS 65000, `bgp ebgp-requires-policy` actif. Plage d'écoute `K8S` (10.10.40.0/24, AS 65040) prête, sans voisin ; politique d'entrée : seulement 10.10.41.0/24 (et 10.10.255.0/24 de la fabric). Lyon (65030) : voisin 10.255.2.2 **désactivé** (`neighbor … shutdown`) depuis la destruction de la maquette ; réactivation : recréer `lyo-gw01` (état `m07-maquette`), retirer le `shutdown`, ajouter `10.255.2.2` à `MS_BGP_MAITRE` de `ms-verif-reseau`.

## Points uniques de défaillance restants et suite

`pve01`, la box, le LAN maison ; `ca01`, `nbx01` (une instance chacun) ; `s3-01`. Modules suivants : Ceph (M08) sur les VLAN 30/31 en MTU 9000 et RGW publié par les répartiteurs ; cluster `hv-par1` (M09, EVPN 65090) ; Kubernetes (M14/M15) en BGP vers `.2`/`.3` ; supervision Prometheus (M21) à partir de `reseau.prom` et de `/metrics` des répartiteurs.
