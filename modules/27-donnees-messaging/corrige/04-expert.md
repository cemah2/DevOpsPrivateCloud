# Module 27 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Avec des données, « j'ai redémarré et ça remarche » est souvent faux **et** dangereux : un redémarrage efface la preuve (session SQL, réglage à chaud, compteurs) et peut aggraver (une bascule sur une base qui attend sa réplication, un cache qui repart vide sous la charge).

**Mécanique des pannes** (pour comprendre ce que tu as vu, après coup) : [`pannes/break-E19.sh`](pannes/break-E19.sh) à [`break-E23.sh`](pannes/break-E23.sh) et [`_m27-commun.sh`](pannes/_m27-commun.sh). Tout vise la **recette** (`mediagenda-recette`, `medinotif-recette`, vhost `medinotif-recette`). Les changements de configuration GitOps sont des **commits de Lucas Martin** (`M27-EXX` dans le message) sur `plateforme/donnees`, `plateforme/k8s`, `mediagenda/deploiement` ou `medinotif/deploiement` ; les autres gestes sont faits **dans le serveur** (annotation du `Cluster`, session SQL, historique Flyway, `ACL SETUSER`, `CONFIG SET`). Les pannes de messagerie exportent les définitions avant et les réimportent à l'annulation si la panne est encore en place ; aucune ne purge ni ne supprime un message. `--annuler` ne revient jamais sur une réparation (il ne touche un fichier ou un objet que s'il porte encore la valeur injectée).

**Points non testés en conditions réelles** : les scripts ont passé `shellcheck` et `bash -n` ; leurs expressions `yq` et `jq` ont été rejouées sur des manifestes de topologie et des overlays d'exemple (sélection d'un document, modification ciblée, ajout d'un correctif d'overlay) ; le message empoisonné a été essayé contre le code de MédiNotif (`RecursionError` reproduit avec Python 3.13, correctif [`message-empoisonne.patch`](fichiers/M27-E20/medinotif-worker/message-empoisonne.patch) passé à `pytest` et `ruff`) ; les messages de Flyway cités viennent du code source de Flyway (`MigrationInfoImpl`). **À vérifier sur ton lab** : la session détachée dans le conteneur du primaire (présence de `setsid` dans l'image), la fermeture des connexions par l'API de gestion, la publication HTTP avec le compte par défaut, le compte d'administration de Valkey (variables `WB_M27_VALKEY_*`) et l'option `--insecure` de `valkey-cli`, la réémission d'un certificat sur changement d'émetteur, les valeurs de `mediagenda_notifications_total{resultat}` (M27-E08). Les sorties ci-dessous sont plausibles, tes valeurs différeront.

---

### M27-E19 — Panne : les écritures de MédiAgenda sont bloquées

**Démarche de diagnostic**

*Symptômes* : en recette, les `POST` échouent après de longues secondes ou tout de suite ; les `GET` passent, parfois lentement. *Hypothèses*, du client vers le serveur : le *pooler* sature ; la base attend (verrou, réplication synchrone) ; la base refuse (droits, contrainte) ; le client vise un réplica.

**Étape 1 — Attend ou refuse ?** Journaux de l'API et métriques par code :

```
admin@adm01:~$ kubectl -n mediagenda-recette logs deploy/mediagenda --since=10m | grep -m3 -E 'ERROR|erreur'
# Thanos Query
sum by (code) (rate(mediagenda_http_requests_total{namespace="mediagenda-recette", methode="POST"}[5m]))
```

**Étape 2 — Le pooler et la base.**

```
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c \
  "SELECT wait_event_type, wait_event, state, count(*) FROM pg_stat_activity WHERE datname = 'mediagenda' GROUP BY 1,2,3 ORDER BY 4 DESC;"
# Thanos Query
sum(cnpg_pgbouncer_pools_cl_waiting{namespace="mediagenda-recette"}), max(cnpg_pgbouncer_pools_maxwait{namespace="mediagenda-recette"})
```

**Variante 1 — Deux réplicas isolés, réplication synchrone `required`.**

Les sessions sont en `IPC`/`SyncRep` ; `pg_stat_replication` est vide ; `SHOW synchronous_standby_names;` vaut toujours `ANY 1 ("mediagenda-db-1","mediagenda-db-3")` ; l'alerte `PostgresqlSynchroneSansReplica` sonne (M27-E14). `kubectl cnpg status` montre les deux réplicas « fenced » ; l'annotation le dit :

```
admin@adm01:~$ kubectl -n mediagenda-recette get cluster mediagenda-db -o jsonpath='{.metadata.annotations.cnpg\.io/fencedInstances}{"\n"}'
["mediagenda-db-1","mediagenda-db-3"]
```

Avec `dataDurability: required`, CNPG garde les instances indisponibles dans la liste : chaque `COMMIT` attend un réplica qui ne viendra pas (documentation CNPG 1.30, « Required Data Durability »). Les lectures passent ; les écritures **attendent**, puis le client abandonne. Qui l'a posée : `git log` de `plateforme/k8s` (rien : geste manuel) et journal d'audit (M22, locataire `audit`, `verb="patch"` sur `clusters`). Correctif : `kubectl cnpg fencing off mediagenda-db "*" -n mediagenda-recette` (l'annotation n'est pas dans Git ; si elle y était, la retirer par MR). Les validations en attente se terminent : **aucune** n'est perdue. Prévention : alerte `PostgresqlInstanceIsolee` ; isoler un réplica est un geste de maintenance annoncé, jamais deux à la fois.

**Variante 2 — Pooler minuscule.**

Pas d'attente dans PostgreSQL (une ou deux connexions serveur seulement) ; dans le *pooler*, `cl_waiting` élevé, `maxwait` qui grimpe, et des refus : `no more connections allowed (max_client_conn)` dans les journaux de l'API (psycopg : `server closed the connection` à l'ouverture). Réglages effectifs :

```
admin@adm01:~$ kubectl -n mediagenda-recette get pooler mediagenda-db-pooler-rw -o jsonpath='{.spec.pgbouncer.parameters}{"\n"}'
{"default_pool_size":"1","max_client_conn":"8","reserve_pool_size":"0"}
admin@adm01:~$ kubectl -n argocd get application mediagenda-recette -o jsonpath='{.status.sync.revision}{"\n"}'   # puis git log
```

Commit de Lucas (« réserve du pooler resserrée ») dans l'overlay de recette de `mediagenda/deploiement` (ou dans `plateforme/k8s` si le `Pooler` y vit, appliqué en place). Correctif : `git revert` par MR ; CNPG recharge PgBouncer sans coupure. Prévention : alerte `PgbouncerClientsEnAttente` ; réglages justifiés dans `dimensionnement.md` ; un contrôle en CI qui refuse une réserve sous un plancher.

**Variante 3 — Droits d'écriture retirés.**

Erreur **immédiate** sur les `POST` : `permission denied for table rendez_vous`. Pas d'attente, pas de saturation.

```
mediagenda=# SELECT has_table_privilege('mediagenda_api', 'public.rendez_vous', 'INSERT');   -- f
mediagenda=# \dp rendez_vous
admin@adm01:~/src/k8s$ git log -3 --format='%h %an %s' -- espaces/mediagenda-recette/sql/
a41c7e2 Lucas Martin recette : moindre privilège pour mediagenda_api
```

Le script de Lucas (`REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM mediagenda_api;`) a été joué à la main. Correctif : rendre les droits (`GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO mediagenda_api;`, comme le SQL de préparation du M25-E14), et retirer le script du dépôt par MR. Prévention : les droits ne se changent que par le script de préparation versionné et relu ; un test de bout en bout (création d'un rendez-vous de contrôle) après chaque changement de la base.

[RB-276](fichiers/M27-E19/medisphere/docs/donnees/runbooks/RB-276-ecritures-bloquees.md) ; journal d'exemple : [`INC-5419`](fichiers/M27-E19/medisphere/docs/kubernetes/journal/2026-11-12-INC-5419-ecritures-bloquees.md).

**Explications**

Une écriture peut **attendre** à trois endroits (le *pooler*, un verrou, la réplication synchrone) ou être **refusée** ; le premier geste (journaux de l'API) tranche. `wait_event` est le meilleur ami de l'astreinte PostgreSQL : `SyncRep` dit « j'attends un réplica », `Lock`/`relation` « j'attends un verrou », `ClientRead` « le client ne m'envoie rien ».

**Pièges classiques**
- Redémarrer le primaire : les validations en attente sont perdues pour le client (il a déjà abandonné), la bascule ne trouve aucun réplica sain à promouvoir.
- Passer en `preferred` pour « débloquer » : on achète la disponibilité au prix de la durabilité, sans l'avoir décidé.
- Agrandir la réserve du *pooler* quand la base attend : plus de sessions bloquées, rien de plus.

**En production chez MédiSphère** : alertes `PostgresqlSynchroneSansReplica` (critique) et `PgbouncerClientsEnAttente` ; isolements et droits uniquement par MR ; un rendez-vous de contrôle créé et annulé toutes les minutes par une sonde (M29).

---

### M27-E20 — Panne : MédiNotif ne consomme plus

**Démarche de diagnostic**

*Symptômes* : file `notifications` (recette) qui monte, plus d'envois. *Hypothèses* : MédiNotif absent ou en échec de connexion (droits, nom de file, URL), MédiNotif présent mais bloqué sur un message, MédiNotif trop lent.

**Étape 1 — Les trois chiffres.**

```
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_queues -p medinotif-recette name consumers messages_ready messages_unacknowledged
admin@adm01:~$ kubectl -n medinotif-recette get pods
admin@adm01:~$ kubectl -n medinotif-recette logs deploy/medinotif --since=10m | tail -5
```

**Variante 1 — Permission de lecture retirée.** `consumers 0`, MédiNotif se reconnecte en boucle : `ACCESS_REFUSED - access to queue 'notifications' in vhost 'medinotif-recette' refused for user 'medinotif-recette'`. Droits en vigueur et déclarés :

```
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl list_user_permissions medinotif-recette
vhost              configure  write  read
medinotif-recette  ^$         ^$     ^notifications\.rebut$
admin@adm01:~/src/donnees$ git log -3 --format='%h %an %s' -- topologie/medinotif-recette/
```

Correctif : `git revert` du commit de Lucas (MR) ; le Topology Operator remet `read: ^notifications$` ; MédiNotif, qui se reconnecte de lui-même, reprend ; la file se vide. Une permission ne s'applique qu'aux nouveaux canaux : c'est pour cela que la panne a fermé les connexions, et que la correction prend effet à la reconnexion suivante.

**Variante 2 — Message empoisonné, sans limite de livraison.** `consumers` à 1 puis 0 par intermittence, **1** message non acquitté, redélivrances en continu, pods MédiNotif en `CrashLoopBackOff` :

```
admin@adm01:~$ kubectl -n medinotif-recette logs deploy/medinotif --previous | tail -4
RecursionError: maximum recursion depth exceeded while decoding a JSON array from a unicode string
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-queues peek --vhost medinotif-recette notifications 1 | head -c 300
admin@adm01:~$ curl -s -u wb-checks:… https://rabbitmq.apps.par1.medisphere.internal/api/queues/medinotif-recette/notifications | jq '.effective_policy_definition'
{"dead-letter-exchange": "notifications.rebut", "delivery-limit": -1}
```

Le message en tête est un JSON imbriqué sur 100 000 niveaux (en-tête `x-wb-panne`) : `json.loads` lève `RecursionError`, exception que MédiNotif n'attrape pas (seule `MessageInvalide` l'est) ; le processus meurt, la connexion se ferme, le message non acquitté revient **en tête**, MédiNotif redémarre et replante. En RabbitMQ 4.3, une fermeture de canal avec un message non acquitté **compte** pour la limite de livraison ; la limite (20 par défaut, celle de M27-E04 sinon) aurait envoyé le message au rebut après quelques plantages. Lucas l'avait passée à `-1` (« plus de limite ») : boucle sans fin. Correctif : `git revert` (la Policy retrouve sa limite) ; le message part au rebut au plantage suivant qui dépasse la limite ; on peut aussi, MédiNotif en attente de redémarrage, le rejeter **sans remise en file** depuis l'interface après l'avoir identifié par `peek` (il est dead-letteré, pas supprimé). Prévention dans MédiNotif : [`message-empoisonne.patch`](fichiers/M27-E20/medinotif-worker/message-empoisonne.patch) — toute exception inattendue de l'analyse devient un rejet `INVALIDE`, et un échec passager est un `basic.reject` (compté) au lieu d'un `basic.nack` (non compté en 4.3) ; tests ajoutés.

**Variante 3 — Nom de file faux.** `consumers 0` ; MédiNotif : `NOT_FOUND - no queue 'notification' in vhost 'medinotif-recette'`, en boucle. Avec `MEDINOTIF_DECLARER_FILE=0`, MédiNotif ne crée pas la file (c'est voulu : la plateforme déclare la topologie) ; une faute de nom ne crée donc pas une file fantôme qui avalerait les messages, elle **arrête** la consommation. Variables effectives et origine :

```
admin@adm01:~$ kubectl -n medinotif-recette get deploy medinotif -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep MEDINOTIF_FILE
MEDINOTIF_FILE=notification
admin@adm01:~/src/medinotif-deploiement$ git log -3 --format='%h %an %s' -- overlays/recette/
```

Correctif : `git revert`. Prévention : le nom de la file ne se décide qu'à un endroit (base Kustomize), un overlay qui le redéfinit est refusé en revue.

Dans les trois cas, **rien n'est perdu** : les messages attendent dans la file quorum. Une fois MédiNotif reparti, la file se vide ; rien à rejouer, sauf le message empoisonné, qui reste au rebut (à ne **pas** rejouer : il est invalide ; le garder pour l'enquête, puis le supprimer par décision écrite).

[RB-277](fichiers/M27-E20/medisphere/docs/donnees/runbooks/RB-277-consommateur-arrete.md).

**Pièges classiques**
- Purger la file pour « débloquer » : des centaines de notifications perdues.
- Redémarrer MédiNotif en boucle sur le message empoisonné.
- Remettre `delivery-limit` sans regarder ce que deviendra le message (il ira au rebut : la file doit en avoir un).
- Supprimer la file pour la recréer « propre » : messages perdus, et le Topology Operator la recrée vide.

**En production chez MédiSphère** : MédiNotif robuste aux messages imprévus (correctif ci-dessus), limite de livraison explicite dans la Policy (pas seulement le défaut), alerte sur la croissance du rebut (M27-E23), revue obligatoire des changements de topologie.

---

### M27-E21 — Panne : la migration bloque la mise en production

**Démarche de diagnostic**

*Symptômes* : l'Application `mediagenda-recette` reste « Syncing » sur le hook `mediagenda-migrations` ou échoue dessus. *Hypothèses* : le Job attend (verrou PostgreSQL, verrou consultatif de Flyway, base indisponible) ; le Job échoue (`validate` : historique incohérent, migration en échec, somme de contrôle) ; le Job ne démarre pas (image, signature Kyverno, identifiants).

```
admin@adm01:~$ kubectl -n argocd get application mediagenda-recette -o jsonpath='{.status.operationState.phase}{" — "}{.status.operationState.message}{"\n"}'
admin@adm01:~$ kubectl -n mediagenda-recette get job,pods -l job-name=mediagenda-migrations
admin@adm01:~$ kubectl -n mediagenda-recette logs job/mediagenda-migrations --tail=30
```

**Variante 1 — Session oisive en transaction qui verrouille l'historique.** Le Job journalise la connexion puis plus rien, et Argo CD attend le hook jusqu'à son délai ; ou, si le Job pose déjà un `lock_timeout` (M27-E06), il échoue vite avec `canceling statement due to lock timeout`, puis ses nouvelles tentatives échouent de même. Côté base :

```
mediagenda=# SELECT pid, usename, application_name, state, wait_event_type, wait_event, pg_blocking_pids(pid), now() - xact_start AS duree, left(query, 70)
               FROM pg_stat_activity WHERE datname = 'mediagenda' AND (wait_event_type = 'Lock' OR state LIKE 'idle in transaction%');
  pid  | usename  | application_name | state               | wait_event_type | wait_event | pg_blocking_pids |  duree   | left
-------+----------+------------------+---------------------+-----------------+------------+------------------+----------+---------------------------------------------
 48211 | postgres | psql             | idle in transaction |                 |            | {}               | 00:41:07 | ALTER TABLE public.flyway_schema_history ADD COLUMN ticket_lucas text;
 50102 | v-…-mig… | Flyway …         | active              | Lock            | relation   | {48211}          | 00:03:12 | SELECT "installed_rank",…
```

Une session `psql` (superutilisateur, par le socket local : quelqu'un a fait `kubectl cnpg psql`) a ouvert une transaction, ajouté une colonne à `flyway_schema_history` (verrou `ACCESS EXCLUSIVE`) et n'a jamais validé. Flyway prend d'abord son verrou consultatif (libre), puis lit l'historique : son `SELECT` (`ACCESS SHARE`) attend le verrou exclusif, sans fin (pas de `lock_timeout`). Correctif : prévenir Lucas, noter la requête, `SELECT pg_terminate_backend(48211);` (la transaction est annulée : la colonne n'a jamais existé pour les autres), relancer la synchronisation. Prévention : [`idle_in_transaction_session_timeout`](fichiers/M27-E21/k8s/espaces/mediagenda-recette/50-mediagenda-db.extrait.yaml) (10 min) sur la base ; [`lock_timeout`](fichiers/M27-E21/deploiement-mediagenda/components/migrations/job-flyway.extrait.yaml) dans la connexion de Flyway (`FLYWAY_INIT_SQL`) : la migration échoue vite et clairement au lieu de pendre ; ne jamais modifier `flyway_schema_history` à la main.

**Variantes 2 et 3 — Historique Flyway altéré.** Le Job échoue en quelques secondes. Lancer Flyway soi-même, sans rien modifier (RB-278 : `port-forward`, identifiant temporaire d'OpenBao, image de migrations de la version déployée) : `flyway info`, `flyway validate`.

- *Variante 2* : `Validate failed: Migrations have failed validation` / `Detected failed migration to version 4 (…). Please remove any half-completed changes then run repair to fix the schema history.` `flyway info` montre `4 | … | Failed`. Mais `SELECT * FROM flyway_schema_history ORDER BY installed_rank;` montre une **seule** ligne pour 4, avec sa date d'application d'il y a des jours, et le schéma contient bien les effets de `V4__` (colonne retirée, contrainte posée…). La migration a réussi ; c'est la ligne qui ment. `repair` **supprimerait** la ligne en échec, puis `migrate` **rejouerait** `V4__` sur un schéma qui l'a déjà : au mieux une erreur (`column … does not exist`), au pire un double effet. Bon geste ici : remettre la ligne (`UPDATE flyway_schema_history SET success = true WHERE installed_rank = <N>;`), décision et requête écrites au ticket et relues, puis synchroniser. (Dans le cas réel d'une migration **non transactionnelle** qui a échoué à moitié — un `CREATE INDEX CONCURRENTLY`, par exemple —, on défait d'abord ce qu'elle a fait, puis `repair`, puis `migrate` la rejoue.)
- *Variante 3* : `Migration checksum mismatch for migration version 4` / `-> Applied to database : 1876123345` / `-> Resolved locally : 1876123344` / `Either revert the changes to the migration, or run repair to update the schema history.` Le fichier de l'image est celui de Git (vérifié par l'étiquette de l'image et le dépôt) ; le schéma est conforme à ce fichier. Quelqu'un a appliqué une autre version de `V4__` (ou modifié la ligne). `repair` est le bon outil : il réaligne la somme de contrôle sur le fichier de l'image ; si le schéma **n'était pas** conforme, il faudrait une migration corrective, jamais réécrire `V4__`.

Origine : aucune trace dans Git (geste dans la base) ; `log_statement` n'est pas actif par défaut : la leçon est d'interdire l'écriture dans `flyway_schema_history` à tout autre que le compte de migration.

Pourquoi pas une ligne en échec `V90__` : Flyway classe une version supérieure à la dernière migration connue comme **future** ; par défaut (`ignoreMigrationPatterns` `*:future`), une migration future en échec n'est qu'un avertissement. C'est pour cela que les pannes de migration du workbook touchent une version existante plutôt que de créer un `V90__`.

[RB-278](fichiers/M27-E21/medisphere/docs/donnees/runbooks/RB-278-migration-bloquee.md).

**Pièges classiques**
- `repair` réflexe : il fait disparaître l'erreur… et rejoue une migration déjà appliquée.
- Supprimer le Job ou forcer la synchronisation sans hook : la version N part sans son schéma.
- Terminer la mauvaise session (`pg_terminate_backend` sur Flyway) : on recommence, et le bloqueur reste.

**En production chez MédiSphère** : `flyway validate` en CI contre une base restaurée de la recette, `lock_timeout` et `idle_in_transaction_session_timeout` partout, une migration ne se joue que par le Job (le compte de migration est le seul à pouvoir écrire dans l'historique).

---

### M27-E22 — Panne : le cache ne sert plus

**Démarche de diagnostic**

*Symptômes* : recette lente, journaux « cache indisponible » (lecture en échec) ou « écriture en cache impossible » (écriture en échec), `/pret` en 503 quand le `PING` lui-même échoue. *Hypothèses* : accès refusé (ACL, mot de passe), mémoire (plafond, politique), TLS, Valkey arrêté ou injoignable.

```
admin@adm01:~$ curl -s https://mediagenda-recette.apps.par1.medisphere.internal/pret ; echo
admin@adm01:~$ kubectl -n mediagenda-recette logs deploy/mediagenda --since=10m | grep -m3 -i cache
# Thanos Query
sum by (resultat) (rate(mediagenda_cache_total{namespace="mediagenda-recette"}[5m]))
redis_up{namespace="mediagenda-recette"}
```

**Variante 1 — ACL modifiée à chaud.** `/pret` à 200 (le `PING` passe), mais chaque lecture échoue : `NOPERM No permissions to access a key` ; `mediagenda_cache_total{resultat="erreur"}` monte, les créneaux sont recalculés depuis la base. Avec le compte d'administration :

```
ACL LIST
user mediagenda on #… ~session:* resetchannels -@all +get +set +del +ping …
ACL LOG 3
```

La règle de clés vaut `~session:*` au lieu de `~mediagenda:*` ; le fichier ACL monté dans le pod (déclaré) dit `~mediagenda:*` : réglage **à chaud** (`ACL SETUSER`), pas dans la configuration. Correctif : `ACL LOAD` (relit le fichier déclaré) ou redémarrage de `valkey-0` (le cache repart vide, ce qui est sans gravité) ; vérifier `ACL LIST` = fichier. Prévention : le compte d'administration n'est utilisé qu'en bris de glace (ses connexions sont journalisées) ; une comparaison périodique `ACL LIST` / fichier.

**Variante 2 — Plus d'éviction, mémoire au plafond.** `/pret` à 200, lectures qui ratent de plus en plus (les clés expirent et ne sont plus réécrites), journaux : `OOM command not allowed when used memory > 'maxmemory'`. `CONFIG GET maxmemory-policy` → `noeviction`, `CONFIG GET maxmemory` égal à `used_memory`, `INFO errorstats` → `errorstat_OOM`. La configuration montée dit `allkeys-lru` et un autre plafond : réglage à chaud (`CONFIG SET`). Correctif : `CONFIG SET maxmemory-policy allkeys-lru`, `CONFIG SET maxmemory <valeur déclarée>` (ou redémarrage), et vérifier que `CONFIG GET` égale le fichier. Prévention : alertes `ValkeyCachePlein` et `MediagendaCacheEnErreur` ; `CONFIG` renommée ou interdite à tous sauf au compte de bris de glace (ACL `-@admin`).

**Variante 3 — Certificat émis par une autre autorité.** `/pret` à 503 (`certificate verify failed`), pods de MédiAgenda non prêts (l'exportateur aussi passe à `redis_up 0` s'il vérifie le certificat). Valkey tourne et répond… avec un certificat signé par une autre autorité :

```
admin@adm01:~$ kubectl -n mediagenda-recette get certificate -o wide
admin@adm01:~$ kubectl -n mediagenda-recette get certificate <CERT> -o jsonpath='{.spec.issuerRef}{"\n"}'
{"group":"cert-manager.io","kind":"ClusterIssuer","name":"buildkit-ca"}
admin@adm01:~$ kubectl -n mediagenda-recette get secret <SECRET-TLS> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer
```

L'émetteur est passé de celui de M27-E07 à `buildkit-ca` (autorité des constructions du M19) par un commit de Lucas (overlay de recette, ou `plateforme/k8s` + objet modifié en place) ; cert-manager a réémis, et le redémarrage de `valkey-0` a chargé le nouveau certificat, que MédiAgenda refuse. Correctif : `git revert`, réémission (`kubectl get certificate` → `Ready`, émetteur d'origine dans le Secret), **redémarrage de `valkey-0`** (Valkey ne recharge pas seul ses fichiers de certificat). Prévention : les `Certificate` des données n'acceptent que l'émetteur prévu (politique Kyverno sur `issuerRef`, M26) ; alerte `ValkeyInjoignable`.

Question de fond (pour aller plus loin et E18 Q11) : `/pret` vérifie Valkey ; quand le cache tombe, **tous** les pods de l'API deviennent non prêts et la recette ne répond plus, alors que l'API sait fonctionner sans cache. `/pret` ne devrait vérifier que la base : MR proposée à l'équipe de Julien.

[RB-279](fichiers/M27-E22/medisphere/docs/donnees/runbooks/RB-279-cache-valkey.md).

**Pièges classiques**
- Désactiver l'ACL ou le TLS « pour voir » : on répare le symptôme en ouvrant le cache à tout le cluster.
- `ACL SAVE` ou `CONFIG REWRITE` après la correction : on fige dans le fichier une configuration faite à la main.
- Chercher dans Git un réglage qui n'y est pas : `CONFIG GET` montre la valeur en vigueur, le fichier la valeur déclarée ; c'est leur écart qui est la preuve.

**En production chez MédiSphère** : compte d'administration en bris de glace, `CONFIG`/`ACL` interdits aux autres comptes, comparaison quotidienne configuration déclarée / en vigueur, `/pret` indépendant du cache.

---

### M27-E23 — Astreinte : des rendez-vous sans notification

**Démarche de diagnostic**

*Prise de l'incident* (15 premières minutes) : impact (depuis quand ? rendez-vous créés depuis la veille au soir et confirmations reçues : `SELECT count(*) FROM rendez_vous WHERE cree_le > '<HIER> 20:00'` et `medinotif_messages_total` sur la même période), premier point à Nadia : « des rendez-vous sont enregistrés, aucune confirmation ne part depuis ~21 h 40 ; je suis le parcours d'un rendez-vous ; prochain point à 7 h 35 ».

*Suivre un rendez-vous* :
1. **Publié ?** Journaux de MédiAgenda : `ACCESS_REFUSED - access to exchange 'notifications' in vhost 'medinotif-recette' refused for user 'mediagenda-recette'` ; `mediagenda_notifications_total` par `resultat` : que des échecs depuis 21 h 40. Statistiques de l'échange `notifications` : `publish_in` figé.
2. **Routé ?** Rien n'arrive dans l'échange : sans objet pour l'instant.
3. **Consommé ?** `consumers 0` : MédiNotif à 0 réplica (Deployment, Git : « en attendant KEDA »).

*Cause 1* : `rabbitmqctl list_user_permissions mediagenda-recette` → `write ^notification$` ; `git log` de la topologie : commit de Lucas. Correction par MR (`^notifications$`). Les publications reprennent (MédiAgenda se reconnecte).
*Cause 2* (visible dès l'étape 3, mais à corriger après avoir compris la première) : MR qui retire le `replicas: 0` de l'overlay. Entre les deux corrections, la file monte… et **plafonne à 20** ; le rebut, lui, grossit.
*Cause 3* : `effective_policy_definition` de `notifications` : `"max-length": 20, "overflow": "drop-head"` ; les messages au rebut portent `x-death` avec `reason: maxlen`, `queue: notifications`. Commit de Lucas sur la Policy. Correction par MR. (La file avait un rebut : avec `drop-head` **sans** rebut, ces messages auraient été détruits.)

*Récupérer* :
- les messages **au rebut** (`maxlen`) n'ont jamais été traités : les rejouer vers `notifications` par un *shovel* temporaire ([`shovel-rejeu.yaml`](fichiers/M27-E23/donnees/topologie/medinotif-recette/shovel-rejeu.yaml), `srcDeleteAfter: queue-length`, plugin `rabbitmq_shovel` activé), après avoir vérifié qu'il n'y a pas, parmi eux, de messages `rejected` (invalides, à ne pas rejouer) ; puis retirer le CR ;
- les demandes **jamais publiées** (entre 21 h 40 et la correction 1) ne sont nulle part dans RabbitMQ : seule la base sait qu'elles manquent. Les régénérer depuis `rendez_vous` (plage horaire, praticien, patient) par un script validé par Julien, en vérifiant dans les journaux de MédiNotif qu'aucune n'a été envoyée (pas de doublon) ;
- vérifier : rebut revenu à son niveau d'avant, `medinotif_messages_total{resultat="envoye"}` qui augmente du nombre attendu.

*Pourquoi aucune alerte* : la publication échoue **silencieusement** par conception et aucune règle ne portait sur `mediagenda_notifications_total` ; « file sans consommateur » en recette est un avertissement par courriel (non lu la nuit) ; rien ne surveillait le rebut ; la file plafonnée à 20 ne déclenchait jamais « file qui grossit » (seuil 100). Ajouts : [`alertes-notifications.extrait.yaml`](fichiers/M27-E23/observabilite/regles/alertes-notifications.extrait.yaml) (`MediagendaPublicationEnEchec`, `RabbitmqRebutAlimente`).

[Post-mortem d'exemple](fichiers/M27-E23/medisphere/docs/kubernetes/post-mortems/2026-11-19-INC-5423.md) ; RB-277, section « Rejouer le rebut sans doublon ».

**Explications**

Une chaîne asynchrone a **trois** endroits où un message peut disparaître de la vue sans erreur visible pour l'utilisateur : avant le courtier (publication ratée, ici silencieuse), dans le courtier (débordement, expiration, limite de livraison — vers le rebut s'il existe, sinon détruit), après (consommateur qui acquitte sans traiter). L'astreinte consiste à suivre **un** message réel d'un bout à l'autre plutôt qu'à corriger le premier symptôme vu. L'*outbox* (ADR-0270) supprime le premier trou : la demande est dans la base avec le rendez-vous, rejouable.

**Pièges classiques**
- Corriger MédiNotif (le plus visible) et déclarer l'incident clos : rien n'était publié.
- Rejouer tout le rebut sans regarder `x-death` : des messages invalides repartent en boucle, et des doublons si certains avaient été traités.
- Purger le rebut « pour repartir propre ».
- Oublier les demandes jamais publiées : ce sont les plus nombreuses.

**En production chez MédiSphère** : *outbox* et idempotence (ADR-0270), alertes de publication et de rebut en critique, revue obligatoire de la topologie, sonde synthétique de bout en bout (M29), recette élargie traitée comme la prod tant qu'un centre réel l'utilise.

---

### M27-E24 — Sous le capot : réplication synchrone, WAL et Raft des files quorum

**Solution**

Document d'exemple : [`sous-le-capot.md`](fichiers/M27-E24/medisphere/docs/donnees/sous-le-capot.md). Les gestes, dans l'ordre :

```
admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda
mediagenda=# SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());
mediagenda=# BEGIN; CREATE TABLE wb_capot (id int, t text); INSERT INTO wb_capot VALUES (1, 'capot'); SELECT pg_current_wal_insert_lsn(); COMMIT; SELECT pg_current_wal_insert_lsn();
mediagenda=# SELECT application_name, sent_lsn, write_lsn, flush_lsn, replay_lsn, sync_state FROM pg_stat_replication;
mediagenda=# SHOW synchronous_standby_names; SHOW synchronous_commit;
mediagenda=# \timing on
mediagenda=# SET synchronous_commit = remote_write; INSERT INTO wb_capot VALUES (2, 'x');   -- puis local, puis on
mediagenda=# SELECT pg_relation_filenode('wb_capot'); SELECT pg_switch_wal();
admin@adm01:~$ kubectl -n mediagenda-recette exec -it <PRIMAIRE> -c postgres -- bash -c \
  '$(pg_config --bindir)/pg_waldump -p "$PGDATA/pg_wal" -s <LSN_AVANT> -e <LSN_APRES> | grep -E "rel [0-9]+/[0-9]+/<FILENODE>|COMMIT"'
mediagenda=# DROP TABLE wb_capot;
admin@adm01:~$ kubectl -n mediagenda-recette get lease mediagenda-db -o yaml
admin@adm01:~$ kubectl -n mediagenda-recette get pod <PRIMAIRE> -o jsonpath='{range .spec.containers[?(@.name=="postgres")]}{.startupProbe}{"\n"}{.livenessProbe}{"\n"}{.readinessProbe}{"\n"}{end}'
admin@adm01:~$ kubectl cnpg promote mediagenda-db <N> -n mediagenda-recette
admin@adm01:~$ kubectl -n cnpg-system logs deploy/cnpg-controller-manager --since=5m | grep -i -E 'mediagenda-db.*(primary|switchover|promot|lease)'
```

(La variable `PGDATA` est posée dans le conteneur par CNPG ; `/var/lib/postgresql/data/pgdata` sinon.) Pour Raft : recrée `wb-essais/rabbitmq-essai` (M27-E15), `messages-essai.sh preparer`, puis `rabbitmq-queues quorum_status --vhost essai essai-quorum` avant et après `kubectl delete pod` du nœud leader (perf-test en fond : `outils/banc/perf-test.yaml` avec `-y 1 -c 100 -z 120`), et sur un nœud : `rabbitmq-diagnostics status | grep -i 'data directory'` puis `ls` de `quorum/` et `coordination/`. Supprime la grappe à la fin.

**Explications**

- **Réplication synchrone** : le `COMMIT` écrit l'enregistrement de validation dans le WAL, puis le *backend* attend que `synchronous_standby_names` soit satisfait au niveau demandé par `synchronous_commit` (`on` = `flush_lsn` d'un réplica `ANY 1`). Les lectures sur le primaire voient la transaction dès le `COMMIT` local ; c'est l'**acquittement au client** qui attend.
- **Élection CNPG** : la décision est prise par l'opérateur, pas par un consensus entre instances ; la sécurité vient du bail `Lease` (une seule instance peut être primaire à la fois, 1.30), du contrôle d'isolement (un primaire coupé de tout se fait redémarrer) et de la réplication synchrone (avec `failoverQuorum`, aucune promotion qui perdrait une validation confirmée).
- **Files quorum** : chaque file est un groupe Raft (bibliothèque Ra) ; une publication confirmée est une entrée validée par la majorité ; le leader regroupe les écritures de toutes les files du nœud dans un WAL partagé (un `fsync` pour beaucoup de messages), puis les entrées migrent vers des segments par file. Le terme (*term*) augmente à chaque élection.
- **Khepri** : les métadonnées suivent le même modèle (Raft) depuis 4.0, par défaut depuis 4.2 : en partition, la minorité ne modifie plus rien.

**Pièges classiques**
- Lire `replay_lsn` comme preuve de durabilité (c'est `flush_lsn` qui compte avec `on`).
- Laisser `SET synchronous_commit = local` dans une session de l'application « pour aller plus vite ».
- `pg_waldump` sur le segment courant non terminé : sortie tronquée (`pg_switch_wal()` d'abord).
- Supprimer deux pods RabbitMQ sur trois « pour voir » : plus de majorité, files indisponibles.

**En production chez MédiSphère** : ces mécanismes donnent les règles de maintenance écrites dans RB-270 (un nœud à la fois, vérifier le réplica synchrone avant de drainer) et dans la procédure de montée de RabbitMQ (`check_if_node_is_quorum_critical` avant chaque arrêt).
</content>
</invoke>
