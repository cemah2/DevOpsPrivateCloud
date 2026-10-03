# RB-004 — Sauvegarde vers `pbs-par2` en échec

| | |
|---|---|
| Déclencheur | notification d'échec `vzdump`, alerte « âge de la dernière sauvegarde > 26 h » |
| Prérequis | SSH root `pve01` et `pbs01` (ou iLO), accès à l'interface PBS |
| Durée cible | 30 min + durée d'une sauvegarde |
| Issu de | M00-E42, M00-E43 |

## 1. Lire l'erreur

```
root@pve01:~# pvesh get /nodes/$(hostname)/tasks --typefilter vzdump --errors 1 --limit 3
root@pve01:~# pvesh get /nodes/$(hostname)/tasks/<UPID>/log | grep -iE 'error|fail'
```

## 2. Identifier l'étage

| Message / observation | Étage | Confirmation | Correctif |
|---|---|---|---|
| délai de connexion, `pvesm status` inactif, `ping 10.20.10.10` KO | transport (tunnel) | `wg show wg0` sur `gw01` | RB « tunnel PAR2 » (M00-E43) |
| erreur de certificat / empreinte | TLS | `proxmox-backup-manager cert info` sur `pbs01` vs `storage.cfg` | `pvesm set pbs-par2 --fingerprint …` **après vérification hors bande** |
| authentification refusée | jeton | jeton existant et non expiré sur PBS | régénérer le secret, `pvesm set pbs-par2 --password` |
| permission refusée | ACL | `proxmox-backup-manager user permissions '<jeton>' --path /datastore/ds-lab/par1` | rétablir `DatastoreBackup` (jamais plus) |
| datastore en maintenance | état du datastore | `proxmox-backup-manager datastore show ds-lab` | demander pourquoi ; lever `--delete maintenance-mode` |
| namespace introuvable | configuration | `storage.cfg` vs namespaces de `ds-lab` | rétablir `--namespace par1` |
| espace insuffisant | capacité | interface PBS, `df` | GC, purge, capacité (`capacite.md`) |
| `VM is locked` | source | `qm config <vmid> | grep lock` | vérifier qu'aucune tâche ne tourne, `qm unlock` |

## 3. Relancer et prouver

```
root@pve01:~# vzdump <VMID> --storage pbs-par2 --mode snapshot
root@pve01:~# pvesm list pbs-par2 --vmid <VMID> | tail -n 1
```
Vérifier la notification de succès. Si la nuit a été manquée : relancer le job complet et
consigner l'écart de RPO (registre HDS, Sophie Laurent).

## 4. Escalade

Plus d'une nuit sans sauvegarde valide : INC P2, information de Claire Morel et Sophie Laurent.
