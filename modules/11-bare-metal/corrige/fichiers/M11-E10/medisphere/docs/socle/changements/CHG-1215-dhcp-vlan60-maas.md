# CHG-1215 — Le DHCP du VLAN 60 passe de Kea à MAAS le temps de l'essai, puis revient

| | |
|---|---|
| Demandeur | Claire Morel (PLAT-1214) |
| Rédaction / exécution | <MOI> |
| Validation | Karim Benali |
| Fenêtre | JJ/MM/AAAA, 2 h pour l'aller ; retour le même jour ou le lendemain (fin de l'essai) |
| Périmètre | VLAN 60 PROV seulement. Le VLAN 99 (sandbox) et tous les autres ne sont pas touchés |
| Impact | Pendant l'essai, une machine du VLAN 60 qui démarre sur le réseau parle à MAAS et non à notre chaîne. Seules `bm01` et `bm03` sont allumées ; `bm02` et `bm04` restent éteintes. |

## Pourquoi

MAAS ne pilote des machines que s'il fournit lui-même le DHCP (et le PXE) de leur VLAN. Deux serveurs
DHCP sur un même segment répondent chacun à leur manière : adresses en conflit, `next-server`
différents, démarrages aléatoires. Il faut donc **retirer** Kea du VLAN 60 avant d'y **activer** MAAS,
et faire l'inverse au retour. Jamais deux en même temps.

## Prérequis

- [ ] Instantanés : `ms-snapshot --prefix avant-chg1215 1002 1008 1000 1009` (dns01, dns02, gw01, gw02).
- [ ] Accès de secours vérifiés (`qm terminal`, agent QEMU) sur ces quatre VMs.
- [ ] `maas01` installé (M11-E09), images Ubuntu 24.04 synchronisées, DHCP de MAAS **désactivé**.
- [ ] `bm02`, `bm04` éteintes (`outils/alim.sh bm02 eteindre`, idem `bm04`).
- [ ] MR « aller » prête : `kea.yml` sans le sous-réseau 60 ; `host_vars/gw0{1,2}/relais_dhcp.yml` sans `ens19.60`.
- [ ] MR « retour » prête : l'inverse (révocation de la MR « aller »).

## Aller

| # | Étape | Contrôle (résultat attendu) |
|---|---|---|
| 1 | Fusion de la MR « aller », pipeline de `plateforme/ansible` (relais d'abord, puis Kea) | pipeline vert |
| 2 | Relais : `ssh gw01 'grep -c ens19.60 /etc/dnsmasq.d/relais-dhcp.conf'` (et `gw02`) | `0` |
| 3 | Kea : `config-get` sur `dns01` et `dns02` | aucun sous-réseau `id: 60` ; le 99 est là |
| 4 | Sonde : `ssh pxe01 'sudo nmap --script broadcast-dhcp-discover -e ens18'` | **aucune** offre |
| 5 | VLAN 99 : renouvellement d'un bail d'une VM sandbox | bail obtenu |
| 6 | MAAS : plages réservées et dynamique, puis `vlan update … dhcp_on=True primary_rack=…` | `dhcp_on: true` |
| 7 | Sonde (étape 4) | une offre, `Server Identifier: 10.10.60.11` |

**Critère d'abandon** : une étape 2 à 5 en échec, ou plus d'une offre à l'étape 7 → retour immédiat.

## Retour (fin d'essai)

| # | Étape | Contrôle |
|---|---|---|
| 1 | MAAS : libérer `bm01`, `bm03` (*Release*) | état *Ready*, machines éteintes |
| 2 | MAAS : `vlan update … dhcp_on=False` | `dhcp_on: false` |
| 3 | Sonde | **aucune** offre |
| 4 | Fusion de la MR « retour », pipeline (Kea d'abord, puis relais) | pipeline vert |
| 5 | Kea et relais (étapes 2 et 3 de l'aller) | sous-réseau 60 et `ens19.60` de retour |
| 6 | Sonde | offres de Kea (`Server Identifier: 10.10.20.10`), deux réponses (deux relais) |
| 7 | `outils/alim.sh bm01 allumer` | `bm01` arrive à **notre** chaîne (menu ou script par MAC) |
| 8 | `snap stop maas` sur `maas01`, puis `qm shutdown 2116` | `lab/bin/check 11 10` vert (avant et après l'arrêt) |

## Retour arrière en cours d'aller

Désactiver le DHCP de MAAS s'il a été activé, puis appliquer la MR « retour ». Si le pipeline de
`plateforme/ansible` ne passe plus : retour aux instantanés `avant-chg1215` de `dns01`, `dns02`,
`gw01`, `gw02` (dans cet ordre : serveurs DHCP, puis relais), puis contrôle du VLAN 99.

## Compte rendu

À remplir : heures réelles de chaque étape, écarts, incidents, décision.
