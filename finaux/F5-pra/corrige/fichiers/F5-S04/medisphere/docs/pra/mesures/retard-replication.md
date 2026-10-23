# Retards de réplication vers PAR2 — mesures

| | |
|---|---|
| Ticket | PLAT-3504 |
| Période | du <AAAA-MM-JJ HH:MM> au <AAAA-MM-JJ HH:MM> (≥ 24 h, dont une nuit de sauvegardes) |
| Source | Prometheus témoin de `mon01` (séries `pra_replication_*`, `pra_miroir_*`, `pra_reg02_*`) ; export CSV joint : `retard-replication-<AAAA-MM-JJ>.csv` |
| Requêtes | `time() - pra_replication_dernier_objet_horodatage_secondes{flux="…"}` ; `max_over_time(...[24h])` pour le pire cas |

> Exemple de mesures d'un lab de référence imaginé : **remplace-les par les tiennes**. Ce qui compte : le **pire cas** sur la période, comparé à l'objectif.

## Résultats

| Flux | Mécanisme | Objectif | Médiane | Pire cas (24 h) | Conforme | Remarque |
|---|---|---|---|---|---|---|
| WAL de MédiAgenda (`wal-mediagenda`) | archive CNPG → `s3-01` → `filer.sync` | ≤ 10 min (RPO 15 min) | 2 min 40 s | 5 min 55 s | oui | le pire cas suit `archive_timeout` (5 min) aux heures creuses : un segment n'est archivé qu'à l'expiration |
| Sauvegarde de base de MédiAgenda | `ScheduledBackup` quotidien → `filer.sync` | ≤ 26 h | — | 24 h 12 min | oui | |
| Instantanés du coffre (`coffre`) | minuterie horaire M25 → `filer.sync` | ≤ 2 h | 31 min | 1 h 04 min | oui | |
| Legacy-RDV (`legacy-rdv`) | `Backup` quotidien 2 h 30 → `filer.sync` | ≤ 26 h | — | 24 h 03 min | oui | |
| MédiDoc (`medidoc`) | `rclone sync` toutes les 15 min | ≤ 1 h | 8 min | 22 min | oui | une exécution à 4 min (RGW lent pendant le *scrub* de Ceph) |
| Miroirs Git | *push mirrors* | ≤ 1 h | 6 s | 2 min (`plateforme/gitops`) | oui | aucune erreur de miroir sur la période |
| Images (`reg02`) | `cosign copy` horaire | ≤ 2 h | — | 1 h 02 min | oui | |

## Délai de propagation de `filer.sync`

Essai : écriture d'un objet de 1 Mio dans `pra-essai` (compartiment d'essai, répliqué temporairement) sur `s3-01` à `T`, présence sur `s3-02` à `T + 3 s` (10 essais : 2 à 5 s).

## Copie ≠ sauvegarde : l'essai de suppression

| Étape | `s3-01` (`pra-essai`) | `s3-02` (`pra-essai`) |
|---|---|---|
| T : écriture de `essai.txt` | présent | présent à T + 3 s |
| T + 1 min : suppression sur `s3-01` | absent | **absent** à T + 1 min 4 s |
| conclusion | | `filer.sync` réplique les suppressions : une purge par erreur sur `s3-01` se propage en quelques secondes |

Même essai sur `medidoc-documents` (copie `rclone sync` vers un compartiment **versionné**) : l'objet disparaît de la liste courante de `s3-02` au passage suivant, mais **une version** reste récupérable (`list-object-versions`). Compartiment d'essai supprimé après l'essai, unité `seaweedfs-filer-sync@pra-essai` retirée.

## Écarts et actions

- Aucun dépassement d'objectif sur la période.
- PLAT-3504-a : alerte `PraWalMediagendaEnRetard` à 10 min (marge de 5 min sur le RPO), essayée en arrêtant `seaweedfs-filer-sync@cnpg-k8s-par1` 15 min : alerte reçue à +15 min, reprise sans perte au redémarrage (point de contrôle).
