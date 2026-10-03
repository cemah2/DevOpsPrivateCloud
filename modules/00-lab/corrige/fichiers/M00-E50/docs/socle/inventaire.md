# Inventaire du socle v0

> Exemple de corrigé M00-E50. Généré à partir de `pvesh get /cluster/resources --type vm`,
> `qm config <vmid>`, `pvesm status`, puis complété à la main (colonnes « Accès » et « Sauvegarde »).
> Date de génération : AAAA-MM-JJ. Aucune valeur secrète : seuls les **emplacements** des secrets.

## 1. Hôtes physiques

| Hôte | Site | Matériel | Système | Adresses | Accès | Accès de secours |
|---|---|---|---|---|---|---|
| `pve01` | PAR1 | Xeon E-2378G, 128 Gio, NVMe/SSD/HDD 2 To | Proxmox VE 9.x | `<IP-PVE01>` | SSH root depuis `adm01` (clé), API 8006 | console physique |
| `hp01` = `pbs01` | PAR2 | Xeon E3-1220L v2, 16 Gio, HDD ~2 To | PBS 4.x | `<IP-HP01-LAN>`, 10.20.10.10 (`vmbr1`), 10.255.0.2 (`wg0`) | SSH root via `wg0` depuis `adm01`, interface 8007 | iLO `<IP-ILO>`, SSH depuis le LAN maison |

## 2. VMs du socle (pool `lab`)

| VM | VMID | VNet / VLAN | Adresse(s) | FQDN | vCPU / RAM | Disques (stockage) | Démarrage | Sauvegarde |
|---|---|---|---|---|---|---|---|---|
| `gw01` | 1000 | `vmbr0` + trunk `vmbr1` | `<IP-GW01-WAN>`, 10.10.X.1 | gw01.par1.medisphere.internal | 1 / 2 Gio | 16 Gio (`local-nvme`) | onboot, ordre 1 | quotidienne `pbs-par2` |
| `adm01` | 1001 | `vmgmt` (10) | 10.10.10.10 | adm01.par1.medisphere.internal | 2 / 2 Gio | 20 Gio (`local-nvme`) | onboot, ordre 3 | quotidienne `pbs-par2` |
| `dns01` | 1002 | `vinfra` (20) | 10.10.20.10 | dns01.par1.medisphere.internal | 1 / 1 Gio | 8 Gio (`local-nvme`) | onboot, ordre 2 | quotidienne `pbs-par2` |
| `tpl-debian13` | 9000 | — | — | — | template | 8 Gio (`local-nvme`, pour les clones liés) ; image source et snippet cloud-init sur `hdd-bulk` | — | non (recréable, M00-E11) |

## 3. Stockages de `pve01`

| Stockage | Type | Disque physique | Contenu | Usage |
|---|---|---|---|---|
| `local-nvme` | <LVM-thin / ZFS> | NVMe 2 To | images | disques système, bases, etcd |
| `ssd-lab` | <…> | SSD 2 To | images | OSD Ceph virtuels, VMs intensives |
| `hdd-bulk` | <dir / ZFS> | HDD 2 To | iso, vztmpl, backup, images | ISO, templates, artefacts |
| `pbs-par2` | pbs | `pbs01` / `ds-lab` / namespace `par1` | backup | sauvegardes hors site, chiffrées côté client |

## 4. Comptes, jetons et secrets

| Identité | Type | Droits | Où est le secret | Rotation |
|---|---|---|---|---|
| `wb-admin@pve` (groupe `wb-admins`) | humain | `PVEAdmin` sur `/pool/lab` + stockages/SDN | gestionnaire de mots de passe personnel ; TOTP | à chaque départ |
| `wb-automation@pve!lab` | jeton (séparation des privilèges) | rôle `WBAutomation` | `~/.config/workbook/` sur `adm01` (600) | 90 jours |
| `wb-backup@pbs!pve01` | jeton PBS | `DatastoreBackup` sur `ds-lab/par1` | `/etc/pve/priv/storage/pbs-par2.pw` | 180 jours |
| Clé de chiffrement des sauvegardes | clé client PBS | — | `/etc/pve/priv/storage/pbs-par2.enc` + copie papier au coffre | jamais sans plan de migration |
| Clés WireGuard `wg0`, `wg1` | clés privées | — | `/etc/wireguard/*.key` sur `gw01` et `pbs01` (600) | annuelle |
| Clé SSH d'administration | clé ED25519 avec phrase de passe | root `pve01`/`pbs01`, `admin` VMs | `~/.ssh/id_ed25519` sur `adm01` | annuelle |

## 5. Clés publiques WireGuard (pour comparaison sans accès à l'autre site)

| Interface | Hôte | Clé publique |
|---|---|---|
| `wg0` | `gw01` | `<CLE-PUBLIQUE-WG0-GW01>` |
| `wg0` | `pbs01` | `<CLE-PUBLIQUE-WG0-PBS01>` |
| `wg1` | `gw01` | `<CLE-PUBLIQUE-WG1-GW01>` |
