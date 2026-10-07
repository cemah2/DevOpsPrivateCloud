# Matrice des flux — site PAR1 (état : fin du module 06)

La matrice fait foi **dans le code** ; ce document l'explique et renvoie aux fichiers.

| Où passe le flux | Source de vérité (code) | Appliqué par |
|---|---|---|
| À travers `gw01` (entre VLANs, vers PAR2, vers Internet, vers `pve01`) | `plateforme/ansible` : `inventories/lab/host_vars/gw01/pare_feu.yml` | rôle `pare_feu` (filet anti-coupure) |
| Vers `gw01` lui-même (SSH, NTP, NTS, relais DHCP, WireGuard) | même fichier, section `pare_feu_entree` | rôle `pare_feu` |
| À l'intérieur du VLAN INFRA, vers `dns01`, `dns02`, `ca01`, `nbx01` | `host_vars/<hôte>/pare_feu_local.yml` et `group_vars/socle/pare_feu_local.yml` | rôle `pare_feu_local` |
| Vers `pve01` | pare-feu Proxmox (IPSet `management`, IPSet `automation`) | à la main (M00-E27, M03-E15) |
| Vers `pbs01` | `/etc/nftables.conf` de `pbs01` | à la main (M00-E21, M01-E28, M06-E28) |
| Vers `git01`, `runner01`, `s3-01` (dans INFRA) | **non filtré** localement : écart accepté, ticket SEC à ouvrir (rôle `pare_feu_local` à étendre) | — |

## Flux ajoutés par le module 06

| Source | Destination | Protocole/port | Passage | Motif | Exercice |
|---|---|---|---|---|---|
| tout le lab, PAR2, VPN | `dns02` (10.10.20.16) | 53 UDP/TCP | `gw01` (sauf INFRA) + local | second récurseur | M06-E24 |
| `dns02` | Internet | 53 UDP/TCP | `gw01` | récursion | M06-E24 |
| `dns01` ↔ `dns02` | 5300 UDP/TCP | — | local | NOTIFY, AXFR signés TSIG, mises à jour dynamiques de `dns02` vers `dns01` | M06-E24, E25 |
| `gw01` (10.10.20.1) | `dns01`, `dns02` | 67 UDP (source 67) | local | requêtes DHCP relayées (le relais envoie aux deux) | M06-E25 |
| `dns01`, `dns02` | `gw01` (10.10.99.1) | 67 UDP | `gw01` (input) | réponses DHCP au `giaddr` | M06-E25 |
| VLAN 99 | `dns01`, `dns02` | 67 UDP (source 68) | `gw01` + local | renouvellements en *unicast* | M06-E25 |
| `dns01` ↔ `dns02` | 8001 TCP (HTTPS, TLS mutuel) | — | local | Kea HA | M06-E25 |
| `adm01` | `dns01`, `dns02` | 8004 TCP (HTTPS) | `gw01` + local | socket de contrôle Kea (administration, supervision) | M06-E25, E29 |
| `adm01`, `runner01` | `dns01` | 8081 TCP | `gw01` / local | API PowerDNS (OpenTofu, synchronisation) | M06-E14 |
| tout le lab, VPN | `ca01` | 443 TCP | `gw01` + local | ACME, renouvellements, certificats SSH | M06-E02 |
| tout le lab (pas le VPN : M06-E20 le limite à 443) | `ca01` | 80 TCP | `gw01` + local | CRL (`/1.0/crl`) | M06-E27 |
| `ca01` | hôtes demandeurs de certificats (`dns01`, `dns02`, `nbx01`, `gw01`…) | 80 TCP | local / `gw01` (input) | défi ACME HTTP-01 | M06-E18, E21, E25 |
| MGMT, VPN, `runner01` | `nbx01` | 443 TCP | `gw01` + local | NetBox (interface, API) | M06-E04 |
| lab, PAR2 (par `wg0`) | `gw01` | 4460 TCP | `gw01` (input) | NTS-KE | M06-E21 |
| VPN d'administration | `adm01` | 22 TCP | `gw01` | seul point d'entrée SSH (ProxyJump) | M06-E20 |
| VPN d'administration | INFRA | 443 TCP | `gw01` | interfaces web du socle (GitLab, NetBox, `ca01`) | M06-E20 |
| `dns01`, `ca01`, `nbx01` | `pbs01` (10.20.10.10) | 8007 TCP | `gw01` (`wg0`) + `pbs01` | sauvegardes applicatives | M06-E28 |

Flux **supprimés** au module 06 : « VPN d'administration vers MGMT et INFRA, tous ports » (M00-E16), remplacé par les deux règles de M06-E20 ci-dessus. Les règles DNS et DHCP « vers dns01 » de M00-E13/E14 sont **remplacées** par les mêmes règles vers `dns01` et `dns02`.

## Vérification

Scan de référence (M06-E30, à rejouer après chaque changement) : depuis `runner01` et depuis une VM sandbox, `nmap -sT -p- --open` sur `dns01`, `dns02`, `ca01`, `nbx01` ; résultat attendu consigné dans `docs/socle/tests/scan-flux.md`.
