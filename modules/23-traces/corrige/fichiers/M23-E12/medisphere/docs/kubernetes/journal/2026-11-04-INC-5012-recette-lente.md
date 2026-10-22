# INC-5012 — MédiAgenda de recette lente (journal de diagnostic)

> `plateforme/medisphere`, `docs/kubernetes/journal/2026-11-04-INC-5012-recette-lente.md` — M23-E12. Exemple pour la **variante 1** ; heures et identifiants à remplacer par les tiens.

| Heure | Constat ou action | Commande, requête |
|---|---|---|
| 09:12 | Ticket de Nadia : « certaines opérations de recette prennent près d'une demi-seconde ». Aucune alerte d'erreur ; `/pret` répond 200. | — |
| 09:14 | Métriques (M21) : p95 de `POST /api/v1/rendez-vous` en recette passé de 15 ms à 480 ms vers 08:50 ; `GET /api/v1/creneaux` inchangé. La lenteur est **ciblée**, pas générale (ni CPU ni mémoire en tension). | `histogram_quantile(0.95, sum by (le, route, methode) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette"}[5m])))` |
| 09:17 | Traces lentes de recette : toutes des `POST` (et des `DELETE`) ; dans chacune, la span `INSERT` (PostgreSQL) dure ≈ 470 ms sur 480. Le cache et MédiDoc ne sont pas en cause. | `{ resource.deployment.environment.name = "recette" && kind = server && duration > 300ms }` puis `{ resource.deployment.environment.name = "recette" && span.db.system.name = "postgresql" && duration > 300ms } \| select(span.db.query.text)` |
| 09:20 | Hypothèses : verrou (une autre transaction), index, base surchargée, réseau vers la base. Réseau écarté : `SELECT` du même pod en 1 ms. Charge écartée : un seul type de requête touché. | Comparaison des spans `SELECT` / `INSERT` d'une même trace |
| 09:24 | Sur le primaire : la session de l'API attend sur `Timeout` / `PgSleep` pendant l'`INSERT`, pas sur un verrou. Le temps est passé **dans** l'exécution de l'insertion. | `kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c "SELECT pid, wait_event_type, wait_event, left(query, 60) FROM pg_stat_activity WHERE datname = 'mediagenda' AND state = 'active'"` |
| 09:26 | Cause : déclencheur `rendez_vous_journal` (`BEFORE INSERT OR DELETE`), fonction `journal_modifications()` qui fait `pg_sleep(0.4)`. Ni dans les migrations (V1, V2), ni dans le dépôt : ajout manuel. | `\d rendez_vous` ; `\sf journal_modifications` |
| 09:30 | Correction (accord de Julien, base de recette) : `DROP TRIGGER rendez_vous_journal ON rendez_vous; DROP FUNCTION journal_modifications();` | `kubectl cnpg psql …` |
| 09:35 | Retour à la normale : p95 du `POST` à 14 ms ; aucune trace de recette > 300 ms sur 10 min. | mêmes requêtes qu'à 09:14 et 09:17 |

## Cause, correction, prévention

- **Cause** : objet de base de données hors des migrations versionnées (déclencheur ajouté à la main) qui ajoute 400 ms à chaque écriture.
- **Prévention** : contrôle en CI (ou au démarrage) que le schéma ne contient que ce que les migrations créent (comparaison `pg_dump --schema-only` / migrations) ; droits DDL retirés au compte applicatif (M16) ; alerte sur la latence p95 par route (M21).
- **Ce que les traces ont apporté** : en trois minutes, la **span** fautive (`INSERT`) parmi six, sans hypothèse préalable. Les métriques disaient « POST lent », les journaux ne disaient rien.

Variante 2 (Valkey) : les spans lentes sont `GET`, `SET` et `DEL` de Valkey, par à-coups de 300 ms au plus, sur toutes les routes qui touchent le cache ; PostgreSQL est rapide. `valkey-cli INFO commandstats` montre un compteur `cmdstat_client|pause` qui augmente d’environ un par seconde : quelqu'un suspend Valkey (`CLIENT PAUSE`). Le journal d'audit de l'API (locataire `audit`, M22-E07) montre des `create pods/exec` répétés sur `valkey-0` : un processus extérieur, lancé depuis `adm01`. Correction : arrêter ce processus, `valkey-cli CLIENT UNPAUSE`. Prévention : `exec` sur les pods de données réservé au bris de glace (RBAC, M24), alerte sur la latence des commandes Valkey.
