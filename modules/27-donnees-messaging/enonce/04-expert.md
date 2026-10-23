# Module 27 — Palier 4 : Expert

Les données et la messagerie sont en production : CloudNativePG derrière un *pooler*, des migrations Flyway jouées par Argo CD, Valkey en cache durci, RabbitMQ et ses files quorum, MédiNotif qui consomme, des alertes, un réplica de secours. Nadia Roussel connaît la suite : « Les incidents de données, ce ne sont jamais des pannes franches. Ce sont des écritures qui attendent, des messages qui s'entassent, une migration qui ne finit pas, un cache qui ralentit tout. » Karim Benali a préparé quatre familles de pannes, toutes vues en vrai ailleurs, puis une astreinte qui en enchaîne plusieurs. Le palier se termine sous le capot : ce que le WAL et la réplication synchrone font vraiment, comment l'opérateur choisit un primaire, comment une file quorum se met d'accord.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres aux données :
- **Ne perds rien en réparant.** Avant tout geste sur une base ou une file : quel est l'état des données, que devient-il si je me trompe ? Pas de `DELETE`, de purge de file, de suppression de PVC ni de `pg_terminate_backend` à l'aveugle. Un message dans une file de rebut est un message **sauvé**, pas un déchet.
- **Remonte la chaîne** : client (journaux, métriques applicatives), réseau, intermédiaire (*pooler*, échange, liaison), serveur (verrous, réplication, alarmes), configuration déclarée (Git, Argo CD, opérateurs). Le premier maillon anormal est le suspect, pas le dernier.
- **Le code fait foi.** Une correction faite à la main est défaite par Argo CD ou par l'opérateur (CloudNativePG, Topology Operator) ; un réglage fait à chaud dans un serveur (`ALTER SYSTEM`, `CONFIG SET`, `rabbitmqctl set_…`) disparaît au redémarrage. Corrige là où l'état est déclaré, et vérifie qu'aucun réglage à chaud ne reste.

> **Rappels** : tout se lance depuis `adm01`. Bases : `kubectl cnpg status|psql … -n mediagenda-recette` ; RabbitMQ : interface `https://rabbitmq.apps.par1.medisphere.internal`, `kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmqctl|rabbitmq-diagnostics|rabbitmq-queues …` ; Valkey : `kubectl -n mediagenda-recette exec valkey-0 -c valkey -- valkey-cli …` (avec ton utilisateur d'administration) ; tableaux `m27-donnees` et ceux du M21 ; journaux dans Grafana (Loki, M22).

## Règles du jeu des pannes (M27-E19 à M27-E23)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 27 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 variantes (M27-E23 est un scénario unique) ; `--variante N` en force une. Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé), le script en essaie une autre. Une injection prend de 2 à 10 minutes : beaucoup passent par un **commit dans Git** que le script attend de voir appliqué (Argo CD, puis l'opérateur), et il **constate** la panne avant d'afficher le ticket.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 27 19`…) : il doit être vert. Le script refuse de casser une recette qui ne marche pas déjà.
- **Environnement visé : la recette.** `mediagenda-recette`, `medinotif-recette`, le vhost `medinotif-recette` de la grappe `messagerie/rabbitmq`. La production n'est **jamais** touchée. Une panne de messagerie exporte d'abord les définitions de la grappe (et les réimporte à l'annulation) ; aucune ne purge une file, ne supprime un message ni ne met une file dans un mode qui perd des messages.
- **Témoin de trafic.** À la première injection, le script crée dans l'espace **`wb-pannes`** un déploiement `trafic-recette` qui joue les centres de santé : une requête par seconde sur `https://mediagenda-recette.apps.par1.medisphere.internal` (créneaux, liste), et toutes les dix secondes la création puis l'annulation d'un rendez-vous factice (`patient` = « Patient Témoin »), qui déclenche une demande de notification. Ne l'arrête pas pendant les pannes ; supprime-le à la fin du module (`kubectl -n wb-pannes delete deployment/trafic-recette configmap/trafic-recette`). Variables facultatives de `lab/lab.env` : section « module 27 » de `lab/lab.env.example` (`WB_M27_*`).
- **Les commits de la panne** sont signés **Lucas Martin** et portent `M27-EXX` dans leur message : les retrouver fait partie du diagnostic (`git log`, MR, historique d'Argo CD). Les gestes faits directement sur un serveur (session SQL, commande Valkey, objet patché) sont, eux, à retrouver dans le serveur. Le script pousse avec le jeton d'administration du lab (`WB_GITLAB_ADMIN_TOKEN_FILE`) ; `yq` (mikefarah) est requis sur `adm01`.
- **Ne lis pas** les scripts de `corrige/pannes/` ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 27 19 --annuler` remet l'état sain (commit inverse, objets restaurés, définitions RabbitMQ réimportées), ce qui compte l'exercice comme non réussi. **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : l'annulation ne revient jamais sur ta réparation (elle ne touche un fichier ou un objet que s'il porte encore exactement le contenu de la panne).
- **Tiens un journal de diagnostic** par panne dans `docs/kubernetes/journal/` de `plateforme/medisphere` (`AAAA-MM-JJ-INC-54XX-<sujet>.md`) : heure, hypothèse, commande, résultat, conclusion. Il nourrit les runbooks RB-276 à RB-279 et le post-mortem de M27-E23.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Effets de bord** : pendant une panne, la recette de MédiAgenda ou de MédiNotif est dégradée ; préviens Julien avant d'injecter. Une panne de messagerie touche le vhost `medinotif-recette` de la grappe partagée : vérifie, avant et après, que `medinotif-prod` n'a ni alarme ni file qui grossit (`lab/bin/check 27 14`). Retour arrière à tout moment : `lab/bin/break 27 <XX> --annuler`.

---

### M27-E19 — Panne : les écritures de MédiAgenda sont bloquées  `BF` `★★★`

> **Ticket INC-5419** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection.)* En recette, on ne peut plus créer de rendez-vous : la requête tourne de longues secondes puis échoue. La consultation marche à peu près. Rien n'a changé dans l'API.

**Objectifs pédagogiques**
- Distinguer, par la mesure, une écriture qui **attend** (verrou, réplication synchrone, file du *pooler*) d'une écriture **refusée** (droits, contrainte).
- Lire l'état réel d'un cluster CloudNativePG (annotations, état des instances, `synchronous_standby_names`, `pg_stat_replication`) et d'un *pooler* (`SHOW POOLS`, métriques).
- Corriger là où l'état est déclaré et dire quelle alerte aurait dû prévenir.

**Prérequis** : M27-E02, M27-E14 ; `lab/bin/check 27 19` vert avant l'injection.
**Durée indicative** : 60 min (temps cible).

**Injection** : `lab/bin/break 27 19` (3 variantes).

**Travail demandé**
1. Constate : quelles requêtes échouent, lesquelles réussissent, en combien de temps ? Journaux de l'API (code, message d'erreur de psycopg), métriques HTTP de MédiAgenda, tableau `m27-donnees`.
2. Descends maillon par maillon : *pooler* (clients en attente, connexions serveur, réglages effectifs), base (sessions et événements d'attente dans `pg_stat_activity`, verrous, réplication, droits), objet `Cluster` et ses annotations, historique Git.
3. Corrige à la racine et vérifie : une création de rendez-vous de bout en bout en moins d'une seconde, la réplication synchrone avec un réplica confirmé.
4. Écris **RB-276** « Écritures bloquées sur une base CloudNativePG » (`docs/donnees/runbooks/`) : arbre de diagnostic « attend ou refuse ? », commande de preuve et correctif pour chaque branche, alerte associée.

**Critères de réussite**
- [ ] `mediagenda-db` (recette) sain, aucune instance isolée, au moins un réplica en réplication synchrone ; *pooler* aux réglages de M27-E02 sans clients en attente ; le témoin crée des rendez-vous (codes 201 récents).
- [ ] RB-276 publié ; ton journal contient la preuve de la cause ; la panne est close.

**Vérification** : `lab/bin/check 27 19`

<details><summary>Indice 1</summary>

`SELECT pid, usename, application_name, state, wait_event_type, wait_event, now() - xact_start AS duree, left(query, 60) FROM pg_stat_activity WHERE datname = 'mediagenda' ORDER BY duree DESC NULLS LAST;` sur le primaire. Un `wait_event` `SyncRep` ne se lit pas comme un `Lock`, ni comme une erreur `permission denied`. Et si l'API attend **avant** même d'arriver à PostgreSQL ?
</details>

<details><summary>Indice 2</summary>

`kubectl cnpg status mediagenda-db -n mediagenda-recette` (section des instances, de la réplication synchrone), `kubectl -n mediagenda-recette get cluster mediagenda-db -o jsonpath='{.metadata.annotations}'`, `kubectl -n mediagenda-recette get pooler mediagenda-db-pooler-rw -o yaml`. Côté PgBouncer, `SHOW POOLS;` et `SHOW CONFIG;` par la console d'administration (base virtuelle `pgbouncer`), ou les métriques `cnpg_pgbouncer_*`.
</details>

**Pour aller plus loin** : en recette, compare l'effet de `dataDurability: preferred` sur la même panne. Pourquoi ne le ferais-tu pas en production chez MédiSphère ?

---

### M27-E20 — Panne : MédiNotif ne consomme plus  `BF` `★★`

> **Ticket INC-5420** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection.)* En recette, plus aucune notification n'est envoyée depuis tout à l'heure. MédiAgenda dit qu'il publie, la file `notifications` monte. On n'a rien livré côté MédiNotif.

**Objectifs pédagogiques**
- Diagnostiquer un consommateur arrêté à partir de l'état de la file (consommateurs, messages prêts et non acquittés, redélivrances), des connexions et des journaux du consommateur.
- Distinguer un refus d'accès, une erreur de configuration et un message empoisonné.
- Réparer sans perdre un seul message, puis faire passer ce qui s'est accumulé.

**Prérequis** : M27-E04, M27-E08, M27-E14 ; `lab/bin/check 27 20` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : MédiNotif consomme `notifications` avec `prefetch_count=1` et acquitte après l'envoi ; un message invalide est rejeté sans remise en file (il part au rebut), un échec passager est rejeté avec remise en file. Les définitions de la grappe sont exportées avant l'injection (`~/.local/state/workbook/`, ne pas lire).

**Injection** : `lab/bin/break 27 20` (3 variantes).

**Travail demandé**
1. Constate dans RabbitMQ : consommateurs de `notifications` (vhost `medinotif-recette`), messages prêts, non acquittés, taux de redélivrance ; connexions de l'utilisateur `medinotif-recette`.
2. Côté MédiNotif : état et redémarrages des pods, journaux (dernière erreur avant une reconnexion ou un arrêt), variables effectives.
3. Trouve la cause (Git, topologie déclarée, contenu de la file : `rabbitmq-queues peek`), corrige par le code. **Aucune purge** : si un message doit sortir de la file, il va au rebut.
4. Vérifie : un consommateur, file revenue à zéro, notifications envoyées (`medinotif_messages_total`), `medinotif-prod` intact.
5. Écris **RB-277** « Un consommateur RabbitMQ ne consomme plus » : par cause, la preuve et le geste ; comment rejouer le rebut sans doublon.

**Critères de réussite**
- [ ] `notifications` (recette) a au moins un consommateur, moins de 20 messages prêts, aucun message non acquitté depuis plus de 5 min ; les pods MédiNotif de recette sont prêts et ne redémarrent plus ; la file a une limite de livraison et un rebut.
- [ ] RB-277 publié ; ton journal contient la preuve de la cause ; la panne est close.

**Vérification** : `lab/bin/check 27 20`

<details><summary>Indice 1</summary>

Trois chiffres disent presque tout : `consumers`, `messages_ready` et `messages_unacknowledged`, plus `message_stats.redeliver_details.rate`. Zéro consommateur et un client qui se reconnecte en boucle, ce n'est pas la même chose qu'un consommateur présent qui reçoit toujours le même message.
</details>

<details><summary>Indice 2</summary>

`kubectl -n medinotif-recette logs deploy/medinotif --previous` montre la dernière trace d'un conteneur qui a redémarré. `rabbitmq-queues peek --vhost medinotif-recette notifications 1` montre le message en tête sans le consommer. Pour les droits : `rabbitmqctl list_user_permissions medinotif-recette`, à comparer avec la `Permission` déclarée dans `plateforme/donnees`.
</details>

**Pour aller plus loin** : rends MédiNotif robuste à ce qui t'a piégé (MR dans `medinotif/worker`, tests compris) : toute exception inattendue du traitement d'un message doit devenir un rejet sans remise en file, jamais un arrêt du processus.

---

### M27-E21 — Panne : la migration bloque la mise en production  `BF` `★★★`

> **Ticket INC-5421** — *De : Julien Petit, en copie Karim Benali*
> *(Le détail s'affiche à l'injection.)* La synchronisation de la recette de MédiAgenda ne finit plus : Argo CD reste en « Syncing » sur le Job de migration, puis échoue. On n'a pourtant ajouté aucune migration. On doit livrer en production demain.

**Objectifs pédagogiques**
- Suivre une synchronisation Argo CD bloquée jusqu'au hook, au pod, à la session PostgreSQL.
- Lire `flyway_schema_history` et les messages de `flyway validate`, et choisir entre réparer l'historique, corriger le schéma ou libérer un verrou.
- Prévenir : délais de verrou, transactions oisives bornées, validation en CI.

**Prérequis** : M27-E05, M27-E06, M20-E11 (hooks) ; `lab/bin/check 27 21` vert avant l'injection.
**Durée indicative** : 60 min (temps cible).

**Contexte technique** : le Job hook `mediagenda-migrations` (Sync, vague −1) lance Flyway avec le compte dynamique `mediagenda-migrateur-recette`. Pour lancer Flyway toi-même : l'image de migrations de la version déployée, depuis `adm01` (Podman), à travers un `kubectl port-forward` vers `mediagenda-db-rw`, avec un identifiant temporaire demandé à OpenBao (`db-mediagenda/creds/mediagenda-migrateur-recette`) ; `flyway info` et `flyway validate` ne modifient rien.

**Injection** : `lab/bin/break 27 21` (3 variantes).

**Travail demandé**
1. Constate dans Argo CD : quelle opération, quel hook, quel pod, quel message ? Journaux du Job (même s'il est encore en cours).
2. Selon ce que tu vois : sessions et verrous côté PostgreSQL (`pg_stat_activity`, `pg_locks`, `pg_blocking_pids()`), ou historique Flyway (`flyway info`, `SELECT * FROM flyway_schema_history ORDER BY installed_rank`), et le schéma réel.
3. Corrige en **justifiant** ton geste dans le journal : pourquoi tu termines telle session, pourquoi `repair` est (ou n'est pas) le bon outil ici, ce que fera Flyway au passage suivant. Relance la synchronisation et vérifie le Job.
4. Prévention, par le code : borne les transactions oisives de la base de recette, vérifie que le Job a un délai d'attente de verrou (ou donne-le-lui) et que la CI de `mediagenda/api` joue `flyway validate`.
5. Écris **RB-278** « La migration bloque la synchronisation ».

**Critères de réussite**
- [ ] Le dernier Job `mediagenda-migrations` de recette a réussi et l'Application `mediagenda-recette` est `Synced`/`Healthy` avec une dernière opération réussie ; aucune transaction oisive de plus de 5 min ni session en attente de verrou dans la base de recette.
- [ ] `idle_in_transaction_session_timeout` est posé sur la base de recette (déclaré dans le `Cluster`).
- [ ] RB-278 publié ; ton journal contient la preuve de la cause ; la panne est close.

**Vérification** : `lab/bin/check 27 21`

<details><summary>Indice 1</summary>

`kubectl -n argocd get application mediagenda-recette -o jsonpath='{.status.operationState.message}'` puis `kubectl -n mediagenda-recette logs job/mediagenda-migrations`. Un Job qui ne journalise plus rien depuis des minutes attend quelque chose ; un Job qui s'arrête avec `Validate failed` a lu quelque chose qui ne lui plaît pas.
</details>

<details><summary>Indice 2</summary>

`repair` supprime les lignes en échec **et** réaligne les sommes de contrôle sur les fichiers de l'image. Avant de le lancer, demande-toi : la migration en cause a-t-elle produit ses effets dans le schéma ? Que fera `migrate` juste après `repair` ? Une session `idle in transaction` qui tient un verrou exclusif ne fait rien : elle attend un `COMMIT` qui ne viendra pas.
</details>

**Pour aller plus loin** : Flyway attend son propre verrou consultatif pendant `lockRetryCount` essais ; PostgreSQL, lui, attend un verrou de table sans limite si `lock_timeout` n'est pas posé. Ajoute `lock_timeout` à la connexion du Job (option de session ou `initSql` de Flyway) et observe la différence sur la même panne.

---

### M27-E22 — Panne : le cache ne sert plus  `BF` `★★`

> **Ticket INC-5422** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection.)* La recette de MédiAgenda est lente et la sonde `/pret` répond parfois 503 ; on voit « cache indisponible » ou « écriture en cache impossible » dans les journaux. La base va bien.

**Objectifs pédagogiques**
- Vérifier qu'une application dégrade proprement quand son cache casse, et mesurer ce que coûte le mode dégradé.
- Diagnostiquer un Valkey qui refuse : authentification et ACL, mémoire et politique d'éviction, TLS.
- Repérer un réglage fait à chaud qui contredit la configuration déclarée.

**Prérequis** : M27-E07, M27-E14 ; `lab/bin/check 27 22` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 27 22` (3 variantes). Certaines variantes demandent le compte d'administration de Valkey (variables `WB_M27_VALKEY_ADMIN_*` de `lab/lab.env`) ; sans lui, le script choisit une autre variante.

**Travail demandé**
1. Constate : taux de succès du cache (`mediagenda_cache_total`), latence des créneaux, réponses de `/pret` et son corps, journaux de l'API (message exact de l'erreur Valkey).
2. Diagnostique dans Valkey avec ton compte d'administration : `ACL WHOAMI`, `ACL LIST`, `ACL LOG`, `INFO memory`, `CONFIG GET maxmemory*`, `INFO errorstats` ; côté TLS, le certificat présenté (`openssl s_client`) et celui que MédiAgenda attend.
3. Corrige là où l'état est déclaré et efface tout réglage à chaud qui contredit la configuration. Vérifie le retour du taux de succès.
4. Écris **RB-279** « Le cache Valkey ne sert plus ».

**Critères de réussite**
- [ ] Exportateur Valkey de recette `redis_up == 1` ; aucune erreur de cache dans les métriques et les journaux de l'API depuis 10 min ; des succès de cache récents ; `/pret` répond 200.
- [ ] RB-279 publié ; ton journal contient la preuve de la cause ; la panne est close.

**Vérification** : `lab/bin/check 27 22`

<details><summary>Indice 1</summary>

`NOPERM`, `WRONGPASS`, `OOM command not allowed when used memory > 'maxmemory'` et `certificate verify failed` ne viennent pas du même endroit. Une commande `PING` peut réussir là où un `SET` échoue : regarde quelles routes de l'API souffrent.
</details>

<details><summary>Indice 2</summary>

`CONFIG GET` montre la valeur **en vigueur**, pas celle du fichier : compare avec la configuration montée dans le pod. `ACL LIST` montre les règles en vigueur ; `ACL LOG` les refus récents, avec la commande et la clé. Pour le TLS : `kubectl -n mediagenda-recette get certificate`, puis le `issuerRef` et l'émetteur du certificat servi.
</details>

**Pour aller plus loin** : coupe Valkey de recette (zéro réplica, par MR) pendant 5 min sous le témoin de trafic et mesure ce que coûte le mode dégradé à la base (requêtes par seconde, latence p95). Que deviendrait `/pret` en production, et faut-il vraiment que la disponibilité de l'API dépende du cache ?

---

### M27-E23 — Astreinte : des rendez-vous sans notification  `BF` `★★★★`

> **Ticket INC-5423** — *De : Nadia Roussel, 6 h 52*
> *(Le détail s'affiche à l'injection.)* Un centre pilote de la recette élargie se plaint : des patients ont pris rendez-vous hier soir et ce matin, aucun n'a reçu de confirmation. Pas d'erreur côté prise de rendez-vous, pas d'alerte cette nuit. Je te le confie ; je veux un point toutes les 30 minutes et un post-mortem.

**Objectifs pédagogiques**
- Conduire une astreinte de bout en bout sur une chaîne asynchrone : application qui publie, courtier, consommateur, rebut.
- Traiter une panne en chaîne : chaque cause corrigée en révèle une autre ; ne pas déclarer victoire au premier symptôme disparu.
- Récupérer les notifications non envoyées sans en envoyer deux fois, et écrire un post-mortem sans reproche.

**Prérequis** : M27-E20, M27-E14 ; `lab/bin/check 27 23` vert avant l'injection.
**Durée indicative** : 1 h 30 (temps cible).

**Injection** : `lab/bin/break 27 23` (scénario unique ; l'injection prend une dizaine de minutes).

**Travail demandé**
1. Prends l'incident : ouvre un journal (`docs/kubernetes/journal/AAAA-MM-JJ-INC-5423-notifications.md`), fixe l'impact (depuis quand, quels centres, combien de rendez-vous concernés : compte-les), donne un premier point à Nadia en moins de 15 min.
2. Suis un rendez-vous de bout en bout : a-t-il été publié (journaux et métrique de MédiAgenda, statistiques de l'échange) ? Routé (file, liaisons) ? Consommé (consommateurs, MédiNotif) ? Où s'arrête-t-il ?
3. Corrige chaque cause par le code, dans l'ordre où tu les trouves. À chaque correction, vérifie de nouveau le parcours complet.
4. **Récupère** les notifications perdues de vue : où sont-elles, lesquelles faut-il renvoyer, comment les rejouer sans doublon ni perte (et sans purger) ? Fais-le.
5. Dis pourquoi aucune alerte n'a sonné et ajoute ce qui manquait (règles du M27-E14).
6. Écris le post-mortem **`docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-5423.md`** (chronologie, impact chiffré, causes, ce qui a bien et mal marché, actions avec responsable et échéance) et complète RB-277.

**Critères de réussite**
- [ ] MédiAgenda (recette) publie de nouveau (aucun échec de publication depuis 10 min) ; MédiNotif consomme ; `notifications` presque vide.
- [ ] La file `notifications.rebut` (recette) ne contient plus de messages dus à l'incident (rejoués).
- [ ] Une alerte couvre désormais les échecs de publication de MédiAgenda et une autre la croissance du rebut.
- [ ] Le post-mortem INC-5423 est publié avec une chronologie, un impact chiffré et des actions ; la panne est close.

**Vérification** : `lab/bin/check 27 23`

<details><summary>Indice 1</summary>

« Pas d'erreur côté prise de rendez-vous » est le comportement voulu (M27-E08) : une publication ratée ne fait pas échouer la requête. Elle laisse une trace : regarde la métrique `mediagenda_notifications_total` par `resultat`, et les journaux de MédiAgenda. Côté courtier, compare les messages publiés sur l'échange `notifications` et ceux entrés dans la file.
</details>

<details><summary>Indice 2</summary>

Un message dans `notifications.rebut` porte un en-tête `x-death` qui dit **pourquoi** il y est (`rejected`, `expired`, `maxlen`, `delivery_limit`), d'où il vient et combien de fois. Regarde-le (`rabbitmq-queues peek`, ou « Get messages » en mode *requeue* dans l'interface) avant de rejouer quoi que ce soit : tout ce qui est au rebut ne doit pas forcément repartir.
</details>

<details><summary>Indice 3</summary>

Pour rejouer, le Topology Operator sait déclarer un *shovel* (CR `Shovel`) qui déplace les messages d'une file vers une autre et s'arrête quand la file source est vide (`srcDeleteAfter`). Il faut le plugin `rabbitmq_shovel` et des URI dans un Secret. Pour éviter les doublons, sache **ce que MédiNotif a déjà envoyé** pour un rendez-vous.
</details>

---

### M27-E24 — Sous le capot : réplication synchrone, WAL et Raft des files quorum  `LAB` `★★★★`

> **Ticket PLAT-2824** — *De : Karim Benali*
> On a cru sur parole deux mécanismes : « une validation PostgreSQL est sur deux machines » et « un message confirmé par une file quorum survit à la perte d'un nœud ». Je veux que tu me le **montres**, octets et numéros à l'appui, et que tu m'expliques comment l'opérateur choisit un nouveau primaire et comment RabbitMQ choisit un nouveau leader. Tout en recette ou dans `wb-essais`.

**Objectifs pédagogiques**
- Suivre une transaction PostgreSQL dans le WAL (LSN, `pg_walfile_name`, `pg_waldump`) et dans la réplication synchrone (`pg_stat_replication`, `synchronous_standby_names` généré par CNPG).
- Comprendre l'élection de CNPG : sondes du gestionnaire d'instance, bail du primaire (`Lease`), contrôle d'isolement, choix du réplica le plus avancé.
- Observer le Raft d'une file quorum (membres, leader, termes, index validés) et le journal Ra sur disque ; situer Khepri.

**Prérequis** : M27-E14, M27-E15 (grappe jetable), M16-E25.
**Durée indicative** : 2 h.

**Travail demandé**
1. **WAL et réplication synchrone** (recette, `mediagenda-db`) : sur le primaire, note `pg_current_wal_lsn()`, crée une table d'essai `wb_capot` et insère une ligne dans une transaction, note le LSN de validation (`pg_current_wal_insert_lsn()` avant et après le `COMMIT`) et le fichier WAL (`pg_walfile_name()`). Dans `pg_stat_replication`, relève pour chaque réplica `sent_lsn`, `write_lsn`, `flush_lsn`, `replay_lsn`, `sync_state` ; explique lequel de ces LSN conditionne le retour du `COMMIT` avec le `synchronous_commit` en vigueur. Lis `SHOW synchronous_standby_names;` et explique comment CNPG l'a construit. Avec `pg_waldump` (dans le pod, sur le segment), retrouve l'enregistrement de ton `INSERT` et celui du `COMMIT`. Supprime `wb_capot`.
2. **Ce que coûte la synchrone** : mesure le temps d'un `COMMIT` (`\timing`) avec `SET synchronous_commit = on`, puis `remote_write`, puis `local` (dans ta session seulement). Explique ce que chaque niveau garantit.
3. **Élection du primaire** : lis le `Lease` du cluster (`kubectl get lease mediagenda-db -n mediagenda-recette -o yaml`), les sondes des pods (démarrage, vivacité avec contrôle d'isolement, disponibilité), et provoque un `kubectl cnpg promote` vers le réplica de ton choix. Dans les journaux de l'opérateur et des instances, retrouve les étapes : demande de bascule, arrêt de l'ancien primaire, libération du bail, promotion, `pg_rewind` éventuel, nouveau `synchronous_standby_names`. Comment CNPG choisit-il le réplica à promouvoir lors d'une **panne** (et pas d'une bascule demandée) ? Que change `failoverQuorum` ?
4. **Raft d'une file quorum** (grappe jetable `rabbitmq-essai` de `wb-essais`, recréée pour l'occasion) : `rabbitmq-queues quorum_status --vhost <vhost> <file>` (membres, leader, terme, index validé, dernier index écrit), publie 10 000 messages confirmés, regarde les index avancer ; arrête le nœud du leader (`kubectl delete pod`) et observe l'élection (terme qui augmente, nouveau leader), la disponibilité de la file pendant ce temps (perf-test en fond) et le retour du membre. Sur disque, trouve le journal partagé (WAL de Ra) et les segments de la file, et explique leur rôle.
5. **Khepri** : où sont les métadonnées (vhosts, files, politiques) et pourquoi leur comportement en cas de partition ressemble désormais à celui des files quorum ; trouve dans `rabbitmq-diagnostics --help` (version de la grappe) comment interroger l'état du magasin de métadonnées.
6. Rédige `docs/donnees/sous-le-capot.md` : tes LSN et tes sorties à l'appui, un schéma (texte ou Mermaid) des deux chemins d'une écriture confirmée, et trois choses que tu as apprises qui changent un geste d'exploitation.

**Critères de réussite**
- [ ] `sous-le-capot.md` publié : LSN relevés, `synchronous_standby_names` expliqué, sortie de `quorum_status` avant et après l'élection, `Lease` du primaire, emplacement du WAL de Ra.
- [ ] Aucune table `wb_capot` ne reste ; aucune grappe d'essai ne reste dans `wb-essais`.

**Vérification** : `lab/bin/check 27 24`

<details><summary>Indice 1</summary>

`pg_waldump` est dans les binaires PostgreSQL de l'image (`/usr/lib/postgresql/18/bin/` ; vérifie le chemin avec `pg_config --bindir`). Lis le segment **après** un `SELECT pg_switch_wal()` si tu veux qu'il soit complet, et filtre avec `--relation` (le `relfilenode` de ta table, `pg_relation_filenode('wb_capot')`) ou `--rmgr=Heap`.
</details>

<details><summary>Indice 2</summary>

Les données de RabbitMQ sont sous le répertoire du nœud (`rabbitmq-diagnostics status` donne `Data directory`) : regarde les sous-dossiers `quorum/` et `coordination/`. Un membre qui revient rattrape le leader par `AppendEntries` ou par un instantané (*snapshot*) : les métriques `rabbitmq_detailed_raft_*` (famille `ra_metrics`) le montrent.
</details>

**Pour aller plus loin** : lis la section « Data Durability » de la documentation de CNPG et la page « Reliability Guide » de RabbitMQ, puis écris en dix lignes la différence entre « validé sur deux nœuds » et « écrit sur disque sur deux nœuds » pour chacun des deux systèmes.
</content>
</invoke>
