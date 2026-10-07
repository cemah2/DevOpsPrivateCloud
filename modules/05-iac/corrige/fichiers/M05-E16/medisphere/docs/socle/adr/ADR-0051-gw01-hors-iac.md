# ADR-0051 — `gw01` reste hors de la gestion d'OpenTofu

- **Statut** : accepté
- **Date** : <AAAA-MM-JJ>
- **Décideurs** : équipe Plateforme (Claire Morel, Karim Benali), revue Sophie Laurent
- **Ticket** : PLAT-626

## Contexte

L'état `socle` de `plateforme/infra` importe les VMs du socle construites avant le module 05
(`adm01`, `dns01`, `git01`, `runner01`) et gère `s3-01`. Reste `gw01` (VMID 1000), le routeur,
pare-feu, NAT, serveur de temps et VPN du lab, construit à la main depuis l'ISO (M00-E10) :
deux cartes (WAN sur `vmbr0`, trunk sur `vmbr1`, hors SDN), sans cloud-init.

## Options

1. **Importer `gw01` comme les autres** (`prevent_destroy`, `ignore_changes` larges).
2. **Le laisser hors d'OpenTofu, surveillé en lecture** (bloc `check` lisant la VM à chaque plan).
3. **Le reconstruire par OpenTofu** (image, cloud-init, réseau déclaré).

## Décision

Option 2. `gw01` n'est ni créé, ni modifié, ni détruit par OpenTofu. Un bloc `check` de l'état
`socle` (`socle/gw01.tf`) vérifie à chaque plan qu'il existe, tourne et porte ses étiquettes.
Sa configuration interne reste gérée par Ansible (rôle `pare_feu`, M04) ; son matériel, par
le runbook RB-001 et la sauvegarde PBS.

## Justification

- **Rayon d'impact** : la moindre modification de `gw01` par un apply (carte réseau, redémarrage
  imposé par le provider) coupe tout le lab, **y compris** le chemin d'OpenTofu vers l'API de
  `pve01` : l'apply qui a cassé ne peut pas réparer.
- **Peu de valeur ajoutée** : `gw01` change rarement de matériel ; ce qui change (règles,
  VPN) est déjà en code dans Ansible.
- **Imports risqués** : sa configuration (deux ponts, cartes sans VNet, pas de lecteur
  cloud-init) se décrit mal avec le provider et donnerait un plan jamais vide.

## Conséquences

- Un changement matériel de `gw01` passe par un ticket CHG et RB-001, pas par une MR d'infra.
- L'option 3 sera réexaminée avec la redondance du routage (`gw02`, VRRP, module 07) : deux
  routeurs reconstruits par le code, l'un pendant que l'autre route.
