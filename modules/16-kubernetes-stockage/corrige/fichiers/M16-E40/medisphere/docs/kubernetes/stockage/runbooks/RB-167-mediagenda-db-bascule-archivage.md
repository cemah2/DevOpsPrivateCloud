# RB-167 — mediagenda-db : bascule, maintenance de nœud, archivage des WAL

| | |
|---|---|
| Périmètre | Cluster CloudNativePG `mediagenda-db` (espace `mediagenda-recette`), plugin Barman Cloud, `ObjectStore` `cnpg-s3` vers `s3-01` `cnpg-k8s-par1` |
| Rédigé après | INC-4346 (M16-E40), INC-4347 (M16-E41) |
| Gestes interdits | `enablePDB: false` en dehors d'un cluster d'essai, suppression forcée d'un pod de la base, promotion d'une instance clôturée ou en retard, modification du chemin d'archivage sans nouvelle sauvegarde de base |

## A. Maintenance d'un nœud qui porte le primaire

**Avant de commencer (go / no-go)**
1. `kubectl cnpg status mediagenda-db -n mediagenda-recette` : 3 instances prêtes, réplication en flux, décalage nul ou faible ; *Continuous Backup* : dernier WAL archivé il y a moins de 5 min ; dernière sauvegarde de base réussie.
2. `kubectl get pdb -n mediagenda-recette` : exactement les deux PDB de CloudNativePG (`ownerReferences` vers le Cluster) ; tout autre PDB sur ces pods bloque les évictions (« more than one PodDisruptionBudget »).
3. Annotation `cnpg.io/fencedInstances` absente ou `[]`.
4. `kubectl get nodes` : au moins un autre travailleur planifiable pour recevoir l'instance évincée.

**Déroulé**
```
admin@adm01:~$ kubectl cnpg promote mediagenda-db <RÉPLIQUE-SUR-UN-AUTRE-NŒUD> -n mediagenda-recette   # bascule maîtrisée
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette                                   # nouveau primaire, réplication
admin@adm01:~$ kubectl drain <NŒUD> --ignore-daemonsets --delete-emptydir-data --timeout=10m
#   … maintenance …
admin@adm01:~$ kubectl uncordon <NŒUD>
```
Critères d'arrêt : une éviction refusée plus de 5 min, une instance `Pending`, un décalage de réplication qui croît : arrêter, `uncordon`, analyser. Mesurer la coupure d'écriture (boucle d'insertion horodatée) et la noter dans le journal.

## B. Archivage des WAL bloqué

1. **Dater** : `kubectl exec -n mediagenda-recette <PRIMAIRE> -c postgres -- psql -tAc 'select last_archived_wal, last_archived_time, last_failed_wal, last_failed_time, failed_count from pg_stat_archiver'` ; condition `ContinuousArchiving` du Cluster.
2. **Protéger** : place de `pg_wal` et du volume (`kubectl exec … -- df -h /var/lib/postgresql/data`, `du -sh …/pgdata/pg_wal`) ; si le volume risque de se remplir avant la réparation, l'agrandir (classe extensible, M16-E11) **avant** toute autre action.
3. **Cause** : journaux du conteneur du plugin sur le primaire ; reproduire l'accès à `s3-01` depuis un pod jetable de l'espace avec les **mêmes** références que l'`ObjectStore` (`destinationPath`, `endpointURL`, `endpointCA`, Secrets).
4. **Corriger** l'`ObjectStore` ou ses Secrets par le code (`plateforme/k8s`) ; `select pg_switch_wal();` ; vérifier que `archived_count` rattrape et que `last_failed_time` ne bouge plus.
5. **Prouver la continuité** : segments consécutifs sous `<destinationPath>/mediagenda-db/wals/` couvrant la période ; lancer une sauvegarde de base (`kubectl cnpg backup mediagenda-db -n mediagenda-recette --method plugin --plugin-name barman-cloud.cloudnative-pg.io`, à vérifier sur ta version : `kubectl cnpg backup --help`).
6. **Répondre sur la fenêtre de restauration** : pendant la panne, restauration possible jusqu'au dernier WAL archivé (avant la panne) ; après la reprise, jusqu'à l'instant présent si la suite est continue.

## C. Vérification de sortie
`lab/bin/check 16 40` et `lab/bin/check 16 41` verts ; `kubectl cnpg status` sans avertissement.
