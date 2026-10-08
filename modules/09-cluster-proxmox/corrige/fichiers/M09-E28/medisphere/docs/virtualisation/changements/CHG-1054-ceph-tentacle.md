# CHG-1054 — Montée de Ceph Squid 19.2 → Tentacle 20.2 sur `hv-par1`

> Modèle (corrigé M09-E28). Horaires et sorties indicatifs : remplace-les par les tiens.

| | |
|---|---|
| Type | Changement **normal** (version majeure de Ceph) |
| Demandeur / exécutant | Karim Benali / `<MOI>` |
| Fenêtre | 2026-10-XX, 14:00-17:00 (hors sauvegarde de 01:00 et des réplications) |
| Procédure | [Ceph Squid to Tentacle](https://pve.proxmox.com/wiki/Ceph_Squid_to_Tentacle), automatisée par `playbooks/ceph-squid-vers-tentacle.yml` |
| Impact attendu | aucun pour les VMs ; PG brièvement dégradés pendant le redémarrage des OSD de chaque nœud |

## Préalables (preuves)

| Préalable | Commande | Résultat relevé |
|---|---|---|
| Proxmox VE ≥ 9.1, pve-manager ≥ 9.1.4 | `pveversion -v` | `pve-manager: 9.2.x` sur les 3 nœuds |
| Ceph Squid ≥ 19.2.3-pve3 | `pveversion -v \| grep ^ceph:` | `19.2.3-pve3` (sinon : mise à jour RB-092 d'abord) |
| Cluster sain | `ceph -s` | `HEALTH_OK`, 3 MON, 6 OSD up/in, PG `active+clean` |
| Pas de MDS | `ceph fs ls` | vide |
| Drapeaux | `ceph osd dump \| grep flags` | `sortbitwise,recovery_deletes,purged_snapdirs,pglog_hardlimit` |
| État de départ | `ceph osd dump \| grep require_osd_release` ; `ceph mon dump \| grep min_mon_release` | `squid` ; `19 (squid)` |
| Filet du lab | instantanés `avant-chg1054` des VMs 2091-2093 prises cluster arrêté | place vérifiée sur `local-nvme` et `ssd-lab` |
| Sonde de coupure | `mesure-coupure.sh` sur 120 et 121 | lancées à 14:05 |

## Déroulé

| Heure | Étape | Contrôle | Retour arrière possible ? |
|---|---|---|---|
| 14:10 | Dépôt `ceph-tentacle`, `apt full-upgrade` sur chaque nœud | `dpkg -l ceph-common` 20.2.x ; démons toujours en 19.2 (`ceph versions`) | oui : dépôt et paquets Squid (aucun démon redémarré) |
| 14:25 | `noout` | `HEALTH_WARN` : `OSDMAP_FLAGS` seul | oui |
| 14:26-14:32 | MON hv01, hv02, hv03 | quorum à 3 après chacun ; `min_mon_release 20 (tentacle)` à la fin | **non, en pratique** : un MON Tentacle a pu écrire dans sa base un format que Squid ne relit pas ; seule voie : instantanés du lab |
| 14:33 | MGR | 1 actif, 2 en attente | idem |
| 14:35-15:05 | OSD nœud par nœud | `active+clean` entre chaque nœud ; avertissement `OSD_UPGRADE_FINISHED` à la fin | idem |
| 15:06 | `require-osd-release tentacle` | avertissement disparu | **non** (point de non-retour officiel) |
| 15:07 | `unset noout` | `HEALTH_OK` | — |

## Compte rendu

- Interruption mesurée des VMs 120/121 : **0 s** (bilans des sondes collés en annexe).
- Avertissements vus : `OSDMAP_FLAGS` (noout, attendu), PG `undersized+degraded` pendant ~40 s par nœud au redémarrage des OSD (attendu, `noout` évite le rééquilibrage), `OSD_UPGRADE_FINISHED` (attendu jusqu'au `require-osd-release`).
- Point connu de la procédure : utilisation `META` des OSD (`ceph osd df`) ; OSD créés en Squid, non concernés (le problème touche les OSD créés en Octopus ou avant).
- Playbook rejoué après coup : `changed=0`.
- Instantanés du lab supprimés le lendemain, après 24 h sans anomalie.
