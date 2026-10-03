# Test de restauration — socle v0

> Exemple de corrigé M00-E50 (valeurs fictives : remplace-les par ta mesure du jour).

| | |
|---|---|
| Date | AAAA-MM-JJ, 14:02 |
| Opérateur | <apprenant> ; observatrice : Nadia Roussel |
| Scénario | perte de `dns01` (VM 1002) ; restauration **à côté** en VMID 5091 sur le VNet `vsandbox`, puis bascule simulée |
| Sauvegarde utilisée | `pbs-par2:backup/vm/1002/AAAA-MM-JJT02:10:05Z` (chiffrée, vérifiée le AAAA-MM-JJ) |
| RPO constaté | 11 h 52 (dernière sauvegarde 02:10, « sinistre » 14:02) — objectif 24 h : conforme |

## Déroulé chronométré

| Étape | Début | Fin | Durée | Commentaire |
|---|---|---|---|---|
| Décision de restaurer, choix de la sauvegarde | 14:02 | 14:04 | 2 min | `pvesm list pbs-par2 --vmid 1002` |
| `qmrestore` vers 5091 sur `local-nvme` | 14:04 | 14:11 | 7 min | 8 Gio, débit limité par le tunnel (≈ 25 Mo/s) |
| Adaptation réseau (VNet, unique : `dns01` d'origine toujours éteinte) | 14:11 | 14:13 | 2 min | `qm set 5091 --net0 …,bridge=vinfra` (mêmes adresses) |
| Démarrage et vérification du service | 14:13 | 14:16 | 3 min | `dig @10.10.20.10` interne, externe, PTR ; DHCP VLAN 99 |
| **RTO mesuré** | | | **14 min** | objectif 20 min (M00-E37) : conforme |

## Écarts et actions

| Écart | Action |
|---|---|
| Débit de restauration limité par le tunnel | mesurer à nouveau après M00-E41 (MTU) ; envisager une restauration live (`live-restore`) |
| Étape réseau manuelle | script de restauration paramétré (module 02) |

## Remise en état

VM 5091 détruite à 14:31 (`qm destroy 5091 --purge 1`), `dns01` d'origine redémarrée, contrôle `lab/bin/check 00 50` vert à 14:35.
