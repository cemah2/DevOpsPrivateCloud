<!-- M11-E02 — lignes attendues dans docs/socle/matrice-flux.md (plateforme/medisphere) : la partie
     « bordure » est GÉNÉRÉE par ms-matrice-flux depuis group_vars/role_routeur/pare_feu.yml (M07-E30) ;
     les lignes « pare_feu_local » et « même VLAN » se complètent à la main dans leurs sections. -->

| Source | Destination | Protocole / port | Motif | Où c'est appliqué | Réf. |
|---|---|---|---|---|---|
| VLAN 60 (10.10.60.0/24) | relais DHCP de `gw01`/`gw02` | UDP 68 → 67 | clients DHCP (micrologiciel PXE, iPXE, installateurs) | entrée bordure (`pare_feu.yml`) | M11-E02 |
| `dns01`, `dns02` | giaddr 10.10.60.2 / .3 | UDP 67 → 67 | réponses de Kea relayées vers le VLAN 60 | entrée bordure | M11-E02 |
| VLAN 60 | `dns01`, `dns02` | UDP 68 → 67 | renouvellements DHCP en unicast (T1) | transit bordure + `pare_feu_local` de `dns01`/`dns02` | M11-E02 |
| `gw01`, `gw02` (10.10.20.2, .3) | `dns01`, `dns02` | UDP 67 → 67 | requêtes relayées | `pare_feu_local` de `dns01`/`dns02` | M11-E02 |
| VLAN 60 | `pxe01` (10.10.60.10) | UDP 69 (+ éphémères), TCP 80 | TFTP (chargeurs iPXE), HTTP (scripts, noyaux, preseed, kickstart) | même VLAN : pas de filtrage de transit ; nginx limité à 10.10.60.0/24 et 10.10.10.0/24 | M11-E02 |
| VLAN 60 | DNS du lab, NTP de la passerelle, Internet | 53, 123, 80/443 | résolution, heure, miroirs des installateurs | règles existantes (« DNS du lab », NTP, « lab vers Internet ») | M00, M06 |
