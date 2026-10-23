# RB-278 — La migration bloque la synchronisation

| | |
|---|---|
| Symptôme | L'Application `mediagenda-<env>` reste « Syncing » sur le hook `mediagenda-migrations`, puis échoue ; la nouvelle version n'est pas déployée |
| Objets | Job hook `mediagenda-migrations` (Sync, vague −1), Flyway 13 Community, table `flyway_schema_history`, compte `mediagenda-migrateur-<env>` |
| Garde-fous | `idle_in_transaction_session_timeout` sur la base ; `lock_timeout` (`FLYWAY_INIT_SQL`) et `FLYWAY_LOCK_RETRY_COUNT` sur le Job ; `flyway validate` en CI de `mediagenda/api` |

## 1. Où en est la synchronisation ?

```
admin@adm01:~$ kubectl -n argocd get application mediagenda-<ENV> -o jsonpath='{.status.operationState.phase}{" "}{.status.operationState.message}{"\n"}'
admin@adm01:~$ kubectl -n mediagenda-<ENV> get job mediagenda-migrations -o wide
admin@adm01:~$ kubectl -n mediagenda-<ENV> logs job/mediagenda-migrations --tail=50
```

- Le Job **tourne et ne journalise plus** depuis des minutes → il **attend** : §2.
- Le Job **échoue** avec `Validate failed` → l'historique ne correspond pas aux fichiers : §3.

## 2. Il attend : un verrou

Sur le primaire :
```sql
SELECT pid, usename, application_name, state, wait_event_type, wait_event, pg_blocking_pids(pid) AS bloque_par,
       now() - xact_start AS duree, left(query, 80) AS requete
  FROM pg_stat_activity WHERE datname = 'mediagenda' AND (wait_event_type = 'Lock' OR state LIKE 'idle in transaction%')
 ORDER BY xact_start;
SELECT locktype, relation::regclass, mode, granted, pid FROM pg_locks WHERE NOT granted OR relation = 'flyway_schema_history'::regclass;
```
- Le bloqueur est une session `idle in transaction` (ex. un `ALTER TABLE` lancé à la main et jamais validé) : la terminer, **après** avoir noté ce qu'elle faisait et prévenu son propriétaire : `SELECT pg_terminate_backend(<pid>);` (sa transaction est annulée). Une transaction oisive ne fait **rien** : la terminer ne perd que ce qu'elle n'a pas validé.
- Le bloqueur est un autre Flyway (deux synchronisations, un Job manuel) : attendre qu'il finisse ; Flyway prend un verrou consultatif (`pg_try_advisory_xact_lock`), le second attend ses `lockRetryCount` essais.
- Puis relancer la synchronisation (Argo CD, « Sync » de l'Application), vérifier le Job.

## 3. Il échoue : l'historique

Lancer Flyway soi-même, **sans rien modifier** (depuis `adm01`) :
```
admin@adm01:~$ kubectl -n mediagenda-<ENV> port-forward svc/mediagenda-db-rw 15432:5432 &
admin@adm01:~$ bao read -format=json db-mediagenda/creds/mediagenda-migrateur-<ENV> > /tmp/migr.json   # bail court
admin@adm01:~$ podman run --rm --network host -e FLYWAY_URL='jdbc:postgresql://127.0.0.1:15432/mediagenda?sslmode=require' \
    -e FLYWAY_USER="$(jq -r .data.username /tmp/migr.json)" -e FLYWAY_PASSWORD="$(jq -r .data.password /tmp/migr.json)" \
    registry.par1.medisphere.internal/medisphere/mediagenda-migrations:<VERSION-DÉPLOYÉE> info
admin@adm01:~$ shred -u /tmp/migr.json
```

| Message de `validate` | Sens | Avant de réparer | Réparation |
|---|---|---|---|
| `Detected failed migration to version N (…)` | une ligne `success = false` | la migration N a-t-elle produit ses effets ? (comparer le schéma au fichier `VN__…sql`) | effets **absents** : `repair` (supprime la ligne en échec) puis la synchronisation rejoue N ; effets **présents** : `repair` ferait rejouer N (erreur ou double effet) → corriger la ligne (`UPDATE flyway_schema_history SET success = true WHERE installed_rank = …`), geste consigné et relu |
| `Migration checksum mismatch for migration version N` | le fichier de l'image n'est pas celui qui a été appliqué | qui a joué une autre version de N, et le schéma est-il celui du fichier **officiel** (Git) ? | schéma conforme : `repair` réaligne les sommes de contrôle sur les fichiers de l'image ; schéma différent : migration corrective `V…__` (on ne réécrit jamais une migration appliquée) |
| `Detected applied migration not resolved locally: N` | une migration appliquée n'est pas dans l'image | image trop ancienne (retour arrière de l'application) ? | déployer l'image qui la contient ; `repair` ne se justifie que si la migration a été retirée **volontairement** |

`repair` se lance comme `info` ci-dessus (même image, même compte, commande `repair`), une fois la décision écrite au ticket.

## 4. Prévenir

`idle_in_transaction_session_timeout` sur la base (`Cluster`), `lock_timeout` et `lockRetryCount` sur le Job, `flyway validate` contre une base de recette restaurée en CI, interdiction de toucher à `flyway_schema_history` à la main hors de ce runbook.
