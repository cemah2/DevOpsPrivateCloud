# Module 27 — Palier 2 : Opérationnel

Les fondations sont posées ; place aux tickets du quotidien. Une évolution du schéma de MédiAgenda livrée **sans interruption**, Valkey remis à niveau et protégé, la **mise en production des notifications**, l'essai de **Kafka** mesuré puis retiré, une revue de manifestes et le runbook que l'astreinte réclame depuis la panne de jeudi.

Prérequis : palier 1 terminé (`lab/bin/check 27 02` à `05` verts). Rappels : tout passe par Git et Argo CD ; la prod de MédiAgenda (Application `mediagenda-prod`) et celle de MédiNotif se synchronisent **à la main**, après approbation de la MR ; une sauvegarde `Completed` de moins d'une heure avant toute intervention sur `mediagenda-prod`.

---

### M27-E06 — Migrations sans interruption : *expand/contract*  `LAB` `★★★`

> **Ticket DEV-2806** — *De : Julien Petit* — *Copie : Karim Benali, Sophie Laurent*
> Les patients veulent choisir leur rappel : SMS, courriel ou rien. Il nous faut le **canal** et le **contact** de rappel sur chaque rendez-vous. Deux exigences de Karim : aucune coupure (le *canary* fait tourner l'ancienne et la nouvelle version ensemble pendant dix minutes, et on doit pouvoir revenir en arrière), et la base doit finir par **refuser** un rendez-vous sans canal explicite. Sophie : le contact est une donnée personnelle — consentement explicite (« aucun » par défaut), jamais dans un journal ni dans une trace.

**Objectifs pédagogiques**
- Découper un changement de schéma en *expand* puis *contract*, et dire à chaque étape quelle version de l'API reste compatible.
- Comprendre les verrous d'un `ALTER TABLE` et la file d'attente qu'ils créent ; s'en protéger par `lock_timeout` et `statement_timeout`.
- Ajouter une contrainte sans bloquer (`NOT VALID` puis `VALIDATE CONSTRAINT`).
- Tester automatiquement la compatibilité d'une migration avec la version **N−1** de l'application.

**Prérequis** : M27-E05 (Flyway, Job `mediagenda-migrations`) ; M20 (Rollout *canary*, promotion) ; M19 (CI de `mediagenda/api`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Table | `rendez_vous` (`V1__init.sql`, index unique de `V2__index.sql`) |
| Colonnes à ajouter | `canal_rappel` (`sms`, `mail` ou `aucun`, jamais nul), `contact_rappel` (texte ≤ 254, nul si et seulement si le canal vaut `aucun`) |
| Migrations | **`V3__`** (*expand*) livrée avec la version de l'API qui gère le rappel ; **`V4__`** (*contract*) livrée **plus tard**, quand plus aucune ancienne version ne tourne. |
| Code de l'API | champ facultatif `rappel` (`{canal, contact}`, défaut `{"canal": "aucun"}`) dans `POST /api/v1/rendez-vous`, écrit explicitement en base. Le sujet de l'exercice est la migration : tu peux écrire le code ou appliquer le correctif du corrigé (`corrige/fichiers/M27-E06/mediagenda-api/rappel.patch`) — mais lis-le |
| Répétition | grappe jetable `schema-essai` (une instance) dans `wb-essais` |

**Travail demandé**

*A. Le verrou qui gèle tout (répétition)*

1. Dans `wb-essais`, crée la grappe CloudNativePG `schema-essai` (une instance) et la table `rendez_vous` par `V1` et `V2` (image de migration d'E05, pod jetable, ou `kubectl cnpg psql`). Insère quelques milliers de lignes.
2. Trois sessions `kubectl cnpg psql schema-essai -n wb-essais` : (a) `BEGIN; SELECT count(*) FROM rendez_vous;` laissée ouverte ; (b) `ALTER TABLE rendez_vous ADD COLUMN essai text;` ; (c) `SELECT * FROM rendez_vous LIMIT 1;`. Que font (b) et (c) ? Lis `pg_locks` et `pg_stat_activity` (`wait_event_type`, `pg_blocking_pids()`) dans une quatrième session. Explique pourquoi une simple **lecture** est bloquée par un `ALTER` qui n'a encore rien fait.
3. Recommence avec `SET lock_timeout = '2s';` avant l'`ALTER` : que se passe-t-il, et pourquoi est-ce préférable en production ? Quelle différence avec `statement_timeout` ? Où le Job de migration réessaie-t-il (relis le Job d'E05) ?
4. Mesure, sur la même table : `ADD COLUMN … NOT NULL DEFAULT 'aucun'` (PostgreSQL ≥ 11), puis `ADD CONSTRAINT … CHECK (…)` avec et sans `NOT VALID`, puis `VALIDATE CONSTRAINT`. Quel verrou prend chacune (documentation de `ALTER TABLE`, section des verrous) ? Laquelle parcourt la table ?

*B. Le découpage*

5. Écris dans `~/m27/e06/plan.md` le tableau des étapes : migration, version de l'API déployée, versions qui tournent pendant l'étape, ce qui casserait si on inversait l'ordre. Pour chaque version de l'API (N−1 : actuelle ; N : gère le rappel), réponds : lit-elle correctement une ligne écrite par l'autre ? Écrit-elle une ligne que l'autre sait lire ? Que se passe-t-il au retour arrière (Rollout interrompu) **après** `V3` ? **après** `V4` ?
6. Écris `migrations/V3__rappel_expand.sql` : colonnes, contraintes de cohérence ajoutées sans parcours de la table, délais (`SET LOCAL`), commentaires de colonnes (dont la mention « donnée personnelle »). Puis `migrations/V4__rappel_contract.sql` : validation des contraintes, puis suppression du défaut de `canal_rappel` — dans cet ordre, et dis pourquoi. **V4 n'est pas livré dans la même version que V3.**
7. Le code de l'API N (le correctif ou le tien) : liste explicite des colonnes (jamais `SELECT *`), canal toujours écrit, validation du contact (refus `422`), attribut de trace `mediagenda.rappel.canal` mais jamais le contact. `uv run pytest -q`, `ruff`.

*C. Le garde-fou de la CI*

8. Dans `mediagenda/api`, ajoute un job **`migrations:compatibilite`** (étape `test`) : l'image publiée de la version **en production** (N−1, variable `VERSION_N_MOINS_1` tenue à jour dans le `.gitlab-ci.yml`), un service PostgreSQL 18 jetable, les migrations **de la branche** appliquées, puis un essai de fumée qui crée, relit, liste et supprime un rendez-vous **avec le code N−1** (`ci/fumee_n_moins_1.py`). Il tourne à chaque MR qui touche `migrations/`.
9. Prouve le garde-fou : une MR qui contient `V3` **et** `V4` doit avoir le job rouge (lis l'erreur), une MR avec `V3` seul doit l'avoir vert. Garde la MR `V3` seule.

*D. La livraison*

10. Livre la version N (`V3` + code) : étiquette, image de migration et image de l'API signées, promotion en recette, puis en prod (MR approuvée, sauvegarde d'abord, synchronisation manuelle). Pendant le *canary* de recette, crée des rendez-vous **avec** et **sans** rappel, et vérifie que les pods N−1 et N répondent tous les deux (`GET` d'un rendez-vous créé par l'autre version).
11. Quand la version N tourne **partout** (dev, recette, prod) et que `VERSION_N_MOINS_1` vaut N : livre `V4` dans la version suivante (N+1). Vérifie dans `flyway_schema_history` (journal du Job) que `3` et `4` sont `Success`, et dans `\d+ rendez_vous` que les contraintes sont validées et que `canal_rappel` n'a plus de défaut.
12. Complète `docs/donnees/migrations.md` : la règle *expand/contract*, les délais obligatoires en tête de migration, le job de compatibilité, le contenu exact de `V3` et `V4` (en annexe) et les opérations interdites dans une seule migration (renommer une colonne lue, `NOT NULL` sans défaut sur une table existante, `CREATE INDEX` sans `CONCURRENTLY` sur une grosse table).

**Critères de réussite**
- [ ] `migrations/V3__*.sql` et `migrations/V4__*.sql` existent sur `main` de `mediagenda/api` ; V3 n'ajoute que des éléments compatibles (colonne avec défaut ou facultative, contraintes `NOT VALID`) et pose `lock_timeout` ; V4 valide les contraintes.
- [ ] Le job `migrations:compatibilite` existe dans le pipeline de `mediagenda/api` et a réussi sur `main`.
- [ ] En recette et en prod, le dernier Job `mediagenda-migrations` a réussi et son journal montre les versions 3 et 4 appliquées (`Success`).
- [ ] `docs/donnees/migrations.md` décrit *expand/contract* et `lock_timeout`.

**Vérification** : `lab/bin/check 27 06`

<details><summary>Indice 1</summary>

Un `ALTER TABLE` demande un verrou `ACCESS EXCLUSIVE`, incompatible avec **tout**, y compris le `ACCESS SHARE` d'un `SELECT`. Les demandes de verrou sont servies dans l'ordre : derrière l'`ALTER` en attente, les lectures attendent aussi, même si elles seraient compatibles avec la transaction qui bloque. `lock_timeout` borne l'attente du **verrou** ; `statement_timeout` borne la durée de **l'instruction** entière.
</details>

<details><summary>Indice 2</summary>

`SET LOCAL` ne vaut que jusqu'à la fin de la transaction ; Flyway exécute chaque migration PostgreSQL dans sa propre transaction (sauf `executeInTransaction=false`, obligatoire pour `CREATE INDEX CONCURRENTLY`). `VALIDATE CONSTRAINT` ne prend qu'un verrou `SHARE UPDATE EXCLUSIVE` : les écritures continuent pendant le parcours. Un verrou pris dans une transaction est gardé jusqu'à sa fin : l'ordre des instructions dans `V4` compte.
</details>

<details><summary>Indice 3</summary>

Pour l'essai N−1 : l'image de l'API publiée contient le code **et** ses dépendances ; `python -m mediagenda.migrate --repertoire <dossier>` (de cette image) applique des fichiers `V…__…sql` dans l'ordre. Le dépôt du job (`$CI_PROJECT_DIR`) contient, lui, les migrations **de la branche**. Le code N−1 insère sans nommer `canal_rappel` : après `V4`, plus de défaut, donc `NOT NULL` violé.
</details>

**Pour aller plus loin** (facultatif) : renommer une colonne lue par l'API (`motif` → `motif_consultation`) sans interruption demande **trois** livraisons. Écris-les (colonne nouvelle, écriture double par l'application ou déclencheur, recopie par lots, bascule de lecture, suppression).

---

### M27-E07 — Valkey 9 : montée de version, ACL, TLS et éviction  `LAB` `★★★`

> **Ticket PLAT-2807** — *De : Karim Benali* — *Copie : Sophie Laurent, Julien Petit*
> Le Valkey de MédiAgenda est en 8.1, sans mot de passe, en clair, sans limite de mémoire, et celui de la recette n'est même pas dans Argo CD (il date du M16). Sophie l'a mis dans son rapport d'audit. Je veux : Valkey 9.1 dans les trois environnements, géré par `mediagenda/deploiement` ; l'utilisateur `default` désactivé, un utilisateur par usage ; TLS vérifié par l'API ; une mémoire bornée qui **évince** au lieu de refuser ; des métriques. C'est un cache : on accepte de le vider, pas de casser l'API. Et réponds à Julien qui demande « Sentinel, pour la haute dispo ».

**Objectifs pédagogiques**
- Monter de version un service à état simple en préservant ce qui doit l'être (sauvegarde RDB, relecture par la nouvelle version).
- Écrire des ACL Valkey au moindre privilège (commandes, clés, canaux), sans mot de passe en clair dans Git.
- Chiffrer et **vérifier** une connexion `rediss://`, recharger un certificat de 72 h sans redémarrer.
- Borner la mémoire d'un cache et constater l'éviction ; superviser par un exportateur en conteneur annexe.

**Prérequis** : M25 (OpenBao, ESO, ClusterIssuer `openbao-services`, Reloader) ; M26 (Kyverno : condensés en prod, limites) ; M21 (sélecteur de supervision, règle `MediagendaValkeyMemoireHaute`) ; M17/M20 (component `dependances`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Existant | dev et prod : StatefulSet `valkey` du component `dependances` de `mediagenda/deploiement` (8.1, `emptyDir`) ; recette : StatefulSet `valkey` du M16 (`k8s/recette/30-valkey.yaml` de `mediagenda/api`, PVC `donnees-valkey-0`), **hors** d'Argo CD |
| Cible | component **`valkey`** de `mediagenda/deploiement`, inclus par les trois overlays ; StatefulSet **`valkey`** (même nom), conteneurs **`valkey`** (`registry.par1.medisphere.internal/dockerhub/valkey/valkey:9.1.2-trixie`) et **`exportateur`** (`…/dockerhub/oliver006/redis_exporter:v1.95.0`, port **9121**) |
| Configuration | `port 0` + `tls-port 6379` (le port ne change pas pour les politiques réseau), `aclfile`, `maxmemory` (≈ 60 % de la limite mémoire du conteneur), `maxmemory-policy allkeys-lru`, pas de persistance (`save ""`, `appendonly no`) : c'est un cache |
| Utilisateurs ACL | `default` désactivé ; `mediagenda` (clés `mediagenda:*`, lecture, écriture, connexion, rien de dangereux) ; `exportateur` (lecture des statistiques) ; `sonde` (`PING` seulement) ; `admin` (bris de glace) |
| Secret OpenBao | `kv/mediagenda/<env>/valkey` : `mot_de_passe` (mediagenda), `mot_de_passe_admin`, `mot_de_passe_exportateur`, `mot_de_passe_sonde`, `url` (`rediss://mediagenda:<mot de passe>@valkey.mediagenda-<env>.svc:6379/0`) |
| Secrets Kubernetes | `valkey-comptes` (fichier `users.acl` construit par le modèle de l'ExternalSecret, mots de passe de la sonde et de l'exportateur), `valkey-admin` (clé `mot_de_passe`), `mediagenda-valkey` (clé `url`, lue par l'API) |
| Certificat | `valkey-tls` (ClusterIssuer `openbao-services`, 72 h, noms `valkey.mediagenda-<env>.svc[.cluster.local]`) |
| Racine | ConfigMap `racine-medisphere`, `SSL_CERT_FILE=/etc/medisphere/racine/medisphere-root-ca.crt` dans l'API (component **`racine-medisphere`**, resservira en E08) |

**Travail demandé**

*A. État des lieux et sauvegarde*

1. Pour chaque environnement : version (`INFO server`), mémoire utilisée et maximale, politique d'éviction, nombre de clés, persistance (`CONFIG GET save`, `appendonly`), qui gère l'objet (annotation de suivi d'Argo CD ? `managedFields` ?). Lis la règle `MediagendaValkeyMemoireHaute` du M21 : que se passe-t-il aujourd'hui quand Valkey atteint la limite mémoire du **conteneur** ?
2. Sauvegarde RDB de la recette **avant tout** : `BGSAVE`, attente de `rdb_last_bgsave_status:ok`, copie de `/data/dump.rdb` sur `adm01` (`kubectl cp`). Prouve qu'elle est relisible par la **nouvelle** version : pod jetable `valkey:9.1.2-trixie` dans `wb-essais`, `valkey-check-rdb`. Pourquoi l'inverse (une RDB écrite par 9.1 relue par 8.1) n'est-il pas garanti ?
3. Lis les notes de version 9.0 et 9.1 : qu'est-ce qui change pour MédiAgenda (le moteur Lua devenu un **module**, ACL par base, rechargement automatique des certificats, `INFO` des dates d'expiration) ? Le client `redis` de l'API parle-t-il à Valkey 9 (que renvoie `INFO server` dans `redis_version`, et pourquoi) ?

*B. Le component*

4. Génère les mots de passe dans OpenBao (`kv/mediagenda/recette/valkey`, puis prod et dev), sans historique de shell.
5. Écris `components/valkey/` : ConfigMap de configuration, ExternalSecrets (le fichier ACL est construit par le **modèle** de l'ExternalSecret, avec des empreintes SHA-256 et non des mots de passe en clair), StatefulSet (contexte `restricted`, racine en lecture seule, ressources, sondes qui **authentifient** et **vérifient** la réponse, exportateur), Service, `NetworkPolicy` (entrée 6379 depuis l'API seulement ; la collecte de l'exportateur sur 9121 passe par la politique de cluster `collecte-prometheus` de `plateforme/k8s` : ajoute-y le port), PodMonitor de l'exportateur (sélecteur de supervision), annotation de Reloader pour les comptes. Retire Valkey de `dependances`. Écris le component `racine-medisphere` et, par un correctif du component `valkey`, fais lire l'URL de l'API dans le Secret `mediagenda-valkey`.
6. Dans chaque overlay : le `Certificate` `valkey-tls` (noms de l'espace) et ce qu'il faut à l'exportateur pour vérifier le nom du serveur en joignant `127.0.0.1` (il n'a pas d'option « nom attendu »). En prod : images par condensé (Kyverno), les deux.
7. Vérifie le rendu : `kubectl kustomize overlays/recette`, puis `kubectl apply --dry-run=server` dans l'espace (Pod Security, Kyverno).

*C. La bascule*

8. Recette : le StatefulSet existant n'est pas géré par Argo CD et porte un `volumeClaimTemplates` (immuable). Décide comment passer de l'un à l'autre, écris-le dans `~/m27/e07/journal.md` **avant** d'agir, puis fais-le : MR, synchronisation, puis nettoyage de ce qui reste (PVC, fichier de `mediagenda/api`). Mesure la durée pendant laquelle `/pret` répond `503` (une boucle `curl` toutes les secondes depuis `adm01`).
9. Vérifie de l'intérieur du pod : `MODULE LIST` (le module `lua`), `ACL LIST` (aucun mot de passe en clair), `INFO server`, `CONFIG GET maxmemory*`. Avec chaque utilisateur, essaie une commande permise et une commande interdite (`FLUSHALL`, `KEYS *`, `SET autre:x 1` avec `mediagenda`). Sans mot de passe : que répond `PING` ?
10. Depuis un pod de l'API : la connexion `rediss://` vérifie-t-elle le **nom** ? Prouve-le (une URL qui vise le Service par un autre nom).

*D. Éviction, certificat, supervision*

11. Remplis le cache de recette au-delà de `maxmemory` avec `valkey-benchmark` (compte `admin`, clés `essai:*`) : `INFO stats` (`evicted_keys`), `INFO memory`. Les clés de MédiAgenda ont-elles survécu ? Supprime ensuite les clés `essai:*` (sans `FLUSHALL`). Que se serait-il passé avec `noeviction` (la politique par défaut) ?
12. Le certificat dure 72 h : `cmctl renew valkey-tls`, puis `INFO` (`tls_server_cert_serial`, `tls_server_cert_expires_in_seconds`) : Valkey a-t-il rechargé sans redémarrer ? Quel paramètre le permet et à quelle fréquence l'as-tu réglé ?
13. Prometheus : `redis_up`, `redis_instance_info` (quelles étiquettes portent la version de Valkey et la politique d'éviction ?), `redis_evicted_keys_total`. Adapte la règle `MediagendaValkeyMemoireHaute` : avec `maxmemory`, quelle est la bonne mesure ?
14. Prod, puis dev : MR approuvée, synchronisation manuelle, mêmes vérifications. Réponds à Julien sur Sentinel (et sur une réplique) en cinq lignes dans `docs/donnees/valkey.md`, avec la configuration, les comptes, la procédure de sauvegarde et de montée de version, et la conduite à tenir si Valkey est perdu.

**Critères de réussite**
- [ ] En recette et en prod, le StatefulSet `valkey` est géré par l'Application de l'environnement, en Valkey 9.1 (par condensé en prod), avec le conteneur `exportateur` ; son pod est prêt.
- [ ] La configuration désactive le port en clair, active TLS, charge un fichier ACL, borne la mémoire et choisit `allkeys-lru`.
- [ ] `valkey-tls` est prêt (émetteur `openbao-services`) ; les ExternalSecrets de Valkey sont prêts ; l'API lit son URL dans le Secret `mediagenda-valkey`.
- [ ] Prometheus voit `redis_up` = 1 et `redis_instance_info` en 9.1 avec `allkeys-lru` pour les deux environnements.
- [ ] `docs/donnees/valkey.md` existe sur `main`.

**Vérification** : `lab/bin/check 27 07`

<details><summary>Indice 1</summary>

Une ligne ACL : `user <nom> on #<sha256 hexadécimal du mot de passe> resetkeys ~mediagenda:* resetchannels -@all +@read +@write +@connection -@dangerous`. Le modèle d'un ExternalSecret dispose des fonctions de Sprig, dont `sha256sum`. `valkey-cli` lit le mot de passe dans la variable `VALKEYCLI_AUTH` (jamais en argument) ; attention, il rend le code 0 même sur `NOAUTH` : une sonde doit vérifier la **réponse** (`PONG`).
</details>

<details><summary>Indice 2</summary>

`valkey-cli --tls --cacert` vérifie la chaîne mais **pas** le nom ; le client Python `redis` (`rediss://`) vérifie les deux, avec le magasin de Python que `SSL_CERT_FILE` remplace. L'exportateur (Go) vérifie le nom de l'adresse qu'on lui donne : une entrée `hostAliases` (`valkey.mediagenda-<env>.svc` → `127.0.0.1`) lui permet de joindre son voisin de pod sous le nom du certificat. L'exportateur a besoin de `latency|histogram` en plus de `info`, `config|get`, `client|list`, `slowlog|*`.
</details>

<details><summary>Indice 3</summary>

Pour la recette : `kubectl delete statefulset valkey -n mediagenda-recette` (le cache repart vide ; on vient de le sauvegarder) puis synchronisation. Le PVC `donnees-valkey-0` n'est pas supprimé avec le StatefulSet : c'est voulu par Kubernetes ; supprime-le ensuite, une fois la nouvelle instance saine. `tls-auto-reload-interval` (secondes, 0 = désactivé) relit les fichiers TLS en arrière-plan.
</details>

**Pour aller plus loin** (facultatif) : la persistance d'un cache a un coût caché : `BGSAVE` fait un `fork()`, et les pages modifiées pendant l'écriture sont copiées (*copy-on-write*). Mesure `INFO persistence` (`rdb_last_cow_size`) pendant un `BGSAVE` sous charge : quelle marge mémoire faut-il garder entre `maxmemory` et la limite du conteneur si on active la persistance ?

---

### M27-E08 — MédiAgenda publie les notifications, MédiNotif en production  `LIBRE` `★★★`

> **Ticket DEV-2808** — *De : Julien Petit* — *Copie : Karim Benali, Sophie Laurent, Claire Morel*
> Le rappel est en base depuis la semaine dernière. Maintenant, je veux qu'une **confirmation** parte à la création d'un rendez-vous quand le patient a choisi un canal, en recette puis en production. Mes contraintes, non négociables : une prise de rendez-vous ne doit **jamais** échouer parce que RabbitMQ va mal ; on ne notifie jamais un rendez-vous qui n'existe pas ; je veux savoir combien de publications échouent. La production de MédiNotif sur le même modèle que la recette, en plus robuste. Claire veut la démonstration en recette vendredi, la production lundi.

**Objectifs pédagogiques**
- Mettre en production, seul, une chaîne complète éditeur → courtier → consommateur, à partir d'un besoin.
- Choisir où et quand publier (après validation de la transaction) et ce qu'on accepte de perdre ; nommer ce qu'apporterait une *outbox*.
- Reproduire un environnement de recette en production sans copier ses faiblesses (réplicas, interruptions, rebut, synchronisation manuelle).

**Prérequis** : M27-E04 (topologie, MédiNotif en recette), M27-E06 (rappel en base), M27-E07 (component `racine-medisphere`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Message | format attendu par MédiNotif (`message.py` de `medinotif/worker`) : `type` (`sms`/`mail`), `destinataire`, `modele` (`confirmation`), `rendez_vous_id` ; propriétés AMQP utiles à la traçabilité |
| Publication | échange `notifications`, clé `notifications`, vhost `medinotif-<env>`, compte `mediagenda-<env>` (E04) ; URL dans `kv/mediagenda/<env>/amqp` (clé `url`), variable **`MEDIAGENDA_AMQP_URL`** (facultative : sans elle, rien n'est publié) |
| Métrique attendue | `mediagenda_notifications_total{resultat}` (`publiee`, `echec`, `desactivee`) |
| Correctif de référence | `corrige/fichiers/M27-E08/mediagenda-api/` (testé par `pytest`) : tu peux écrire le tien ; lis celui-ci **avant** de le prendre |
| Production MédiNotif | espace `medinotif-prod`, vhost `medinotif-prod`, Application `medinotif-prod` (ApplicationSet `medinotif`, synchronisation **manuelle**) |

**Travail demandé**

Le ticket ne dit pas comment faire : c'est à toi de concevoir, livrer et prouver. Ton dossier `~/m27/e08/` doit contenir à la fin : le schéma du chemin d'un message (de la requête HTTP à l'envoi simulé, rebut compris), la liste des MR (avec leurs liens) dans l'ordre où tu les as fusionnées, les décisions et leurs raisons (y compris ce que tu as **refusé** de faire), et les preuves (requêtes Prometheus, sorties de l'API de gestion, journaux sans donnée personnelle).

Points que la livraison doit couvrir, sans ordre imposé :
- le code de l'API, ses tests, sa dépendance, sa configuration ; le comportement quand RabbitMQ est absent, lent, ou refuse le message ;
- le chemin réseau de l'API vers la grappe, de chaque côté ;
- l'identifiant AMQP de l'API en recette et en prod ; la topologie de `medinotif-prod` ;
- MédiNotif en production : espace, secrets, déploiement, supervision, résistance à un nœud drainé ;
- la démonstration en recette (une prise de rendez-vous avec rappel → un envoi simulé dans les journaux de MédiNotif) et la même preuve en prod (un rendez-vous d'essai, puis sa suppression) ;
- une panne de RabbitMQ simulée **en recette** (règle réseau retirée le temps d'un essai, par MR, ou grappe réduite à l'arrêt d'un seul pod ? choisis et justifie) pendant laquelle les prises de rendez-vous continuent.

**Critères de réussite**
- [ ] L'API de MédiAgenda en recette et en prod reçoit `MEDIAGENDA_AMQP_URL` d'un Secret ; ses pods sont prêts ; une politique réseau lui ouvre AMQPS vers `messagerie`, et la grappe l'accepte.
- [ ] La topologie `medinotif-prod` existe (files quorum, politique de rebut, utilisateurs, permissions minimales).
- [ ] L'Application `medinotif-prod` est synchronisée et saine ; MédiNotif tourne en prod avec au moins deux réplicas sur deux nœuds, une image signée par empreinte, et un `PodDisruptionBudget`.
- [ ] Des publications ont réussi en recette **et** en prod (`mediagenda_notifications_total{resultat="publiee"}`), et MédiNotif a envoyé en prod (`medinotif_messages_total{resultat="envoye"}`).
- [ ] Ton dossier `~/m27/e08/` est complet ; la documentation `docs/donnees/messagerie-topologie.md` décrit la prod et l'éditeur.

**Vérification** : `lab/bin/check 27 08`

<details><summary>Indice 1</summary>

Publier **avant** la validation de la transaction, c'est notifier un rendez-vous qui sera peut-être annulé par un conflit de créneau ; publier **après**, c'est accepter qu'un arrêt brutal entre les deux perde la notification. Ni l'un ni l'autre n'est « exactement une fois » ; l'*outbox* (écrire la demande dans la même transaction, la publier ensuite) l'est presque — et a un coût. Écris ce que tu choisis.
</details>

<details><summary>Indice 2</summary>

Avec `pika`, `BlockingConnection` n'est pas protégée contre l'usage par plusieurs fils d'exécution (FastAPI sert les routes synchrones depuis un *pool*) ; une confirmation (`confirm_delivery`) transforme un refus du courtier ou un message non routé (`mandatory`) en exception. Un délai de connexion court évite qu'un RabbitMQ injoignable ralentisse chaque requête.
</details>

**Pour aller plus loin** (facultatif) : écris l'ADR « *outbox* ou pas » (contexte, options, conséquences) ; tu le reprendras dans l'ADR-0270 (E17).

---

### M27-E09 — Kafka avec Strimzi : KRaft, pools de nœuds, *topics* et utilisateurs  `LAB` `★★★`

> **Ticket PLAT-2809** — *De : Karim Benali* — *Copie : Claire Morel*
> Troisième réunion sur Kafka ce trimestre. Assez parlé : on l'installe **proprement** pour deux semaines, on le mesure contre RabbitMQ sur le cas des notifications, et on décide. Contraintes : Strimzi 1.3 par chart recopié, opérateur cantonné à son espace, Kafka 4.3.1 en KRaft, trois nœuds, TLS et authentification, et **rien** qui survive à l'essai sans décision écrite.

**Objectifs pédagogiques**
- Installer un opérateur par chart recopié, limité à un seul espace, et lire ce qu'il crée.
- Décrire une grappe Kafka KRaft par `Kafka` + `KafkaNodePool` (API `kafka.strimzi.io/v1`).
- Déclarer *topics* et utilisateurs (SCRAM-SHA-512, ACL) ; comprendre réplication, ISR, `min.insync.replicas` et `acks`.
- Mesurer ce que coûte la grappe (mémoire, disque, pods).

**Prérequis** : M27-E02 (ClusterRole `wb-checks-services`, lecture de `kafka.strimzi.io`) ; M20 (`charts-miroir`, Applications multi-sources) ; bilan de mémoire de l'introduction.
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Opérateur | chart `strimzi-kafka-operator` **1.3.0** (dépôt `https://strimzi.io/charts/`), recopié par `plateforme/charts-miroir` ; images `registry.par1.medisphere.internal/quay/strimzi/…` (`defaultImageRegistry`, `defaultImageRepository`) ; installé **dans** `kafka-essai`, ne surveille que cet espace |
| Application | **`kafka-essai`** (projet `plateforme`) : le chart + le dossier `kafka-essai/` de `plateforme/donnees` |
| Grappe | `Kafka` **`kafka-essai`**, Kafka **4.3.1**, `metadataVersion: 4.3-IV0` ; `KafkaNodePool` **`double-role`** : 3 répliques, rôles `controller` et `broker`, stockage `ceph-rbd` (10 Gio par nœud), 1 Gio de mémoire, tas JVM borné |
| Écouteur | `tls`, port **9093**, interne, TLS, authentification `scram-sha-512` ; autorisation `simple` |
| *Topics* | `rendez-vous.evenements` (3 partitions, facteur 3, `min.insync.replicas` 2, rétention 7 jours) ; `notifications.rebut` (1 partition, facteur 3) |
| Utilisateurs | `KafkaUser` `mediagenda` (écrire `rendez-vous.evenements`) et `medinotif` (lire `rendez-vous.evenements` dans le groupe `medinotif`, écrire `notifications.rebut`) |

**Travail demandé**

1. Bilan de mémoire (introduction) : note les requêtes réservables par travailleur dans `~/m27/e09/capacite.md` **avant** d'installer. S'il manque de la place, fais-en (sans toucher aux requêtes de la base ni de RabbitMQ).
2. Lis la documentation de Strimzi 1.3 : quelles API sont servies (et pourquoi un exemple trouvé en ligne en `v1beta2` est refusé) ; ce que font `watchNamespaces` et `watchAnyNamespace` ; ce que fait l'opérateur d'entité (*Entity Operator* : opérateurs de *topics* et d'utilisateurs).
3. `charts-miroir` : entrée du chart (version, empreinte relevée dans l'index amont **et** recalculée sur l'archive). Espace `kafka-essai` dans `plateforme/k8s` (Pod Security `restricted`, quota, `LimitRange`, **sans** étiquette d'équipe : c'est un espace de plateforme). Valeurs du chart dans `plateforme/gitops/valeurs/strimzi/values.yaml`.
4. `plateforme/donnees/kafka-essai/` : `Kafka`, `KafkaNodePool`, `KafkaTopic` ×2, `KafkaUser` ×2. Application `kafka-essai` (le chart, ses valeurs, ce dossier ; que faire pour que la synchronisation ne bute pas sur des CRD encore absentes ?). Synchronise.
5. Lis ce que l'opérateur a créé : pods (combien de conteneurs ?), PVC, Services, Secrets (CA de la grappe, CA des clients, mot de passe de chaque utilisateur), `NetworkPolicy`, `PodDisruptionBudget`. Lis `status` de la `Kafka` (identifiant de grappe, version des métadonnées, écouteurs) et du pool (identifiants de nœuds).
6. Depuis un pod `kafka-essai-double-role-0` : `kafka-metadata-quorum.sh … describe --status` (qui est le *leader* du quorum KRaft ?), `kafka-topics.sh --describe` (leaders et ISR de chaque partition). Arrête un nœud (suppression de son pod) et relis l'ISR pendant son retour.
7. Avec le compte `mediagenda` : produis des événements (Job fourni [`ressources/E09-kafka/produire-essai.yaml`](../ressources/E09-kafka/produire-essai.yaml) : lis-le, adapte-le). Avec `acks=all` et `min.insync.replicas=2`, que se passe-t-il quand **deux** nœuds sont indisponibles ? Essaie-le (deux pods supprimés coup sur coup, ou un nœud drainé + un pod supprimé), lis l'erreur du producteur.
8. Mesure : mémoire et CPU réels des trois pods (Prometheus, `container_memory_working_set_bytes`), disque occupé, temps de démarrage d'un nœud. Documente l'essai dans `docs/donnees/kafka-essai.md` (dont **la date de retrait prévue**).

**Critères de réussite**
- [ ] L'Application `kafka-essai` est synchronisée et saine ; l'opérateur Strimzi 1.3 tourne dans `kafka-essai` avec les images du cache Harbor.
- [ ] La `Kafka` `kafka-essai` est prête, en 4.3.1, KRaft, avec le pool `double-role` de trois nœuds aux deux rôles et l'écouteur TLS + SCRAM-SHA-512.
- [ ] Les deux *topics* et les deux utilisateurs sont prêts ; `rendez-vous.evenements` a 3 partitions, un facteur 3 et `min.insync.replicas` = 2.
- [ ] `docs/donnees/kafka-essai.md` existe sur `main`.

**Vérification** : `lab/bin/check 27 09`

<details><summary>Indice 1</summary>

Sans `watchNamespaces` (liste vide) ni `watchAnyNamespace`, l'opérateur ne surveille que **son** espace : l'installer dans `kafka-essai` le cantonne. Le chart installe aussi des ClusterRoles (lecture des nœuds pour l'affectation des racks, etc.) : lis-les. `SkipDryRunOnMissingResource=true` laisse Argo CD synchroniser des objets dont la CRD arrive dans la même synchronisation.
</details>

<details><summary>Indice 2</summary>

Dans `KafkaNodePool` : `spec.roles: [controller, broker]`, `spec.storage` de type `jbod` avec un volume `persistent-claim` marqué `kraftMetadata: shared`. Dans `Kafka` : `spec.kafka.version`, `spec.kafka.metadataVersion`, `listeners`, `authorization`, `config` (facteurs de réplication par défaut) et `entityOperator` (sans lui, ni `KafkaTopic` ni `KafkaUser` ne sont réconciliés). Les identifiants SCRAM sont dans le Secret qui porte le nom de l'utilisateur (`password`, `sasl.jaas.config`) ; la CA des courtiers dans `kafka-essai-cluster-ca-cert` (`ca.crt`).
</details>

**Pour aller plus loin** (facultatif) : sépare contrôleurs et courtiers (deux pools : trois `controller` légers, trois `broker`) et compare la mémoire réservée. À partir de combien de courtiers le jeu en vaut-il la chandelle ?

---

### M27-E10 — MédiNotif sur Kafka : *offsets*, rebut, comparaison, puis retrait  `LAB` `★★★`

> **Ticket DEV-2810** — *De : Julien Petit* — *Copie : Karim Benali, Claire Morel*
> Le worker sait parler à une `Source` depuis le M12 ; on lui donne un backend Kafka le temps de l'essai, sans toucher au traitement. Puis on compare sur **le même** jeu de messages : débit, latence, ce qu'il advient d'un message invalide, d'un worker tué au milieu, d'un nœud perdu, ce que ça coûte à exploiter. Et Karim veut voir Kafka **disparaître** à la fin, proprement.

**Objectifs pédagogiques**
- Traduire « accusé de réception » en « *commit* d'offset » : au moins une fois, rebut, message bloquant.
- Comparer deux courtiers sur des mesures reproductibles et en tirer une conclusion écrite.
- Retirer complètement un composant de plateforme (objets, stockage, CRD, droits, documentation).

**Prérequis** : M27-E09 (grappe `kafka-essai`) ; M27-E04 (MédiNotif sur RabbitMQ) ; M12 (structure de `medinotif/worker`).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Code | `medinotif/worker` : interface `Source` (`sources/base.py`), traitement (`traitement.py` → `ENVOYE`, `INVALIDE`, `ECHEC`) ; nouveau `sources/kafka.py` (client **`confluent-kafka` 2.16**), variable `MEDINOTIF_BACKEND=kafka` |
| Règle de *commit* | après `ENVOYE` ; après `INVALIDE`, copie sur `notifications.rebut` **confirmée** puis *commit* ; après `ECHEC`, pas de *commit*, retour à l'offset du message |
| Variables | `MEDINOTIF_KAFKA_BOOTSTRAP` (`kafka-essai-kafka-bootstrap.kafka-essai.svc:9093`), `MEDINOTIF_KAFKA_UTILISATEUR`, `MEDINOTIF_KAFKA_MOT_DE_PASSE`, `MEDINOTIF_KAFKA_CA`, `MEDINOTIF_KAFKA_TOPIC`, `MEDINOTIF_KAFKA_GROUPE`, `MEDINOTIF_KAFKA_TOPIC_REBUT` |
| Correctif de référence | `corrige/fichiers/M27-E10/medinotif-worker/kafka.patch` (testé : unitaires et intégration contre Kafka 4.3.1) |
| Instance d'essai | Deployment `medinotif-kafka` **dans `kafka-essai`** (pas dans les espaces de MédiNotif : il disparaît avec l'essai) |
| Comparaison | `docs/donnees/comparatif-messagerie.md` |

**Travail demandé**

*A. Le backend*

1. Écris `sources/kafka.py` (ou applique le correctif, puis **lis-le** ligne à ligne) : `enable.auto.commit` à `false`, que fait `enable.auto.offset.store` ? Que se passe-t-il à un rééquilibrage du groupe pendant un traitement ? Ajoute la dépendance par `uv add`, les tests unitaires, un test d'intégration marqué `integration`. Pourquoi le traitement ne change-t-il pas ?
2. MR, pipeline, image publiée et signée. La dépendance (`librdkafka` embarquée dans la roue de `confluent-kafka`) apparaît-elle dans le SBOM et l'analyse de vulnérabilités (M26) ?

*B. L'essai*

3. Déploie `medinotif-kafka` dans `kafka-essai` par le dossier `kafka-essai/` de `plateforme/donnees` (variables, Secret de l'utilisateur `medinotif`, CA de la grappe, métriques), deux réplicas. Combien de partitions chacun reçoit-il ? Et avec quatre réplicas ?
4. Avec le Job de production d'E09 (`ressources/E09-kafka/`, générateur `messages.py` pour le lot) : 1 000 messages valides et 10 invalides. Suis `medinotif_messages_total`, le décalage du groupe (`kafka-consumer-groups.sh --describe --group medinotif`), le *topic* de rebut.
5. Le même jeu sur RabbitMQ (`publier.py` d'E04, vhost `medinotif-recette`). Note pour les deux, avec le **même** nombre de workers et le même `MEDINOTIF_DELAI_ENVOI_MS` : durée de production du lot, délai entre la fin de la production et le dernier envoi (horodatages des journaux), débit de traitement (`rate(medinotif_messages_total[1m])`), comportement d'un message invalide.
6. Trois scénarios sur les deux courtiers, même protocole : (a) worker tué (`kubectl delete pod --grace-period=0 --force`) au milieu d'un lot : doublons ? pertes ? ; (b) un nœud du courtier perdu pendant la production ; (c) un consommateur lent (`MEDINOTIF_DELAI_ENVOI_MS=1000`) face à un lot de 500 : où s'accumule le retard, comment le voit-on (profondeur de file, décalage du groupe), et que changerait un worker de plus ? Puis, sur le papier (l'expéditeur simulé n'échoue jamais) : un message qui échoue **toujours** — que devient le reste de sa partition, ou de sa file ?
7. Écris `docs/donnees/comparatif-messagerie.md` : protocole, tableau des mesures, scénarios, coût d'exploitation (pods, mémoire réservée, disque, opérations : montée de version, sauvegarde, supervision), ce que chacun fait **mieux**, et ta recommandation pour MédiSphère (elle alimentera l'ADR-0270).

*C. Le retrait*

8. Écris le plan de retrait **avant** d'agir (`~/m27/e10/retrait.md`) : qu'est-ce qui disparaît avec l'Application, qu'est-ce qui reste (PVC, CRD, ClusterRoles, Secrets, entrée de `charts-miroir`, règles de `wb-checks-services`, espace) ? Dans quel ordre, pour que l'opérateur ait le temps de supprimer ce qu'il gère ?
9. Exécute-le par MR (et `task appliquer` pour l'espace). Vérifie qu'il ne reste **rien** : `kubectl get crd | grep strimzi`, `kubectl get pv | grep kafka-essai`, ClusterRoles, images dans le cache Harbor (les garder ou non ?).
10. Le backend Kafka du worker : le garder (dormant) ou le retirer ? Décide, justifie dans le comparatif, et fais-le.

**Critères de réussite**
- [ ] `docs/donnees/comparatif-messagerie.md` existe sur `main` avec des **mesures** (débit, latence) pour les deux courtiers et les trois scénarios.
- [ ] Il ne reste rien de l'essai : ni Application `kafka-essai`, ni espace `kafka-essai`, ni CRD `*.kafka.strimzi.io`, ni volume persistant de l'essai.
- [ ] `docs/donnees/kafka-essai.md` dit que l'essai est terminé (date de retrait effective).

**Vérification** : `lab/bin/check 27 10` (à lancer **après** le retrait ; avant, il signale ce qui reste)

<details><summary>Indice 1</summary>

`confluent-kafka` valide l'offset **suivant** (`message.offset() + 1`) : `consumer.commit(message=msg, asynchronous=False)` le fait pour toi. Pour rejouer un message en échec sans le valider, `consumer.seek(TopicPartition(topic, partition, offset))` revient dessus ; tant qu'il échoue, sa partition n'avance plus. `on_revoke` est le bon endroit pour abandonner proprement un lot quand le groupe se rééquilibre.
</details>

<details><summary>Indice 2</summary>

Supprimer l'Application avec la propagation par défaut supprime la `Kafka` ; l'opérateur, s'il tourne encore, supprime alors pods et Services, mais **les PVC des nœuds restent** sauf `deleteClaim: true` dans le stockage du pool. Les CRD installées par le chart ne sont pas supprimées par Helm ni (par défaut) par Argo CD si elles portent l'annotation de conservation : regarde.
</details>

**Pour aller plus loin** (facultatif) : la fiche NATS (`annexes/decouverte/nats.md`) : JetStream ferait-il l'affaire pour les notifications ? Ajoute une colonne « sur le papier » au comparatif.

---

### M27-E11 — Revue : les manifestes de données du stagiaire  `REV` `★★`

> **Ticket DEV-2811** — *De : Lucas Martin* — *Copie : Julien Petit*
> Salut ! Pour la fonction « rappel la veille », j'ai préparé une petite base dédiée et une messagerie à part, histoire de ne rien casser chez vous. J'ai tout testé sur mon minikube, ça marche du premier coup. Tu peux relire ma MR avant que je la fusionne dans `plateforme/k8s` ? Les fichiers sont dans [`ressources/E11-manifestes-lucas/`](../ressources/E11-manifestes-lucas/).

**Objectifs pédagogiques**
- Relire des manifestes de données avec une grille (sécurité, disponibilité, exploitation, conformité aux règles de MédiSphère).
- Classer les défauts par gravité et proposer un correctif précis, sur un ton qui fait progresser.
- Distinguer ce qui est refusé par l'admission (et donc vu tout de suite) de ce qui passe et cassera plus tard.

**Prérequis** : paliers 1 et 2 ; M26 (Kyverno, Pod Security) ; règles de l'introduction.
**Durée indicative** : 1 h 15.

**Travail demandé**

1. Lis les quatre fichiers sans les appliquer. Pour chacun, liste dans `~/m27/e11/revue.md` les défauts : ce qui est faux, pourquoi c'est un problème **ici** (pas « en général »), sa gravité (**bloquant** : danger pour les données, la sécurité ou une autre application ; **majeur** : ne tiendra pas en production ; **mineur** : style, dette) et le correctif.
2. Pour chaque défaut, indique s'il serait **refusé à l'admission** (Pod Security, Kyverno, validation de la CRD, AppProject) ou **accepté** ; prouve-le pour trois d'entre eux par `kubectl apply --dry-run=server` dans `wb-essais` (sans rien créer).
3. Il y a au moins **dix** défauts, dont un qui toucherait une **autre** application que celle de Lucas. Trouve-le.
4. Écris la réponse à Lucas (commentaire de MR) : ce qu'il a bien fait, les bloquants, puis le reste, et une proposition d'architecture qui réutilise l'existant (base, grappe RabbitMQ, topologie).

**Critères de réussite**
- [ ] Au moins dix défauts identifiés, classés, avec correctif ; le défaut qui touche une autre application est trouvé.
- [ ] Chaque défaut est marqué « refusé à l'admission » ou « accepté », dont trois prouvés par un essai à blanc.
- [ ] La réponse à Lucas propose une alternative concrète fondée sur l'existant.

**Vérification** : pas de script (revue) ; compare avec le corrigé.

<details><summary>Indice 1</summary>

Regarde ce que désigne **chaque** référence d'un objet vers un autre (`spec.cluster`, `rabbitmqClusterReference`, Secrets), chaque image (registre, étiquette, éditeur), chaque champ « déprécié » dans la documentation de CloudNativePG 1.30 et ce que dit la note de version 1.30 de l'archivage intégré.
</details>

**Pour aller plus loin** (facultatif) : transforme trois de tes constats en règles automatiques (Kyverno ou conftest, M29) : lesquelles peuvent l'être, lesquelles demandent un humain ?

---

### M27-E12 — Runbook : maintenance et bascule de PostgreSQL  `RED` `★★`

> **Ticket PLAT-2812** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Jeudi, le primaire de la recette est tombé à 2 h 10 et je n'ai pas su si je devais attendre, promouvoir, ou réveiller quelqu'un. Il me faut une page : comment savoir où on en est, quoi faire pour une maintenance planifiée (nœud à redémarrer, mise à jour mineure), quoi faire quand ça bascule tout seul, quoi ne **jamais** faire. Si tu as le temps, la même chose pour RabbitMQ (redémarrage d'un nœud par roulement).

**Objectifs pédagogiques**
- Écrire un runbook exécutable par quelqu'un qui ne connaît pas le sujet, à 2 h du matin.
- Réutiliser les gestes mesurés en E02 (bascule, drain, mise à jour d'image) et en faire des procédures.
- Prévoir les points de décision, les vérifications après chaque étape et l'escalade.

**Prérequis** : M27-E02 (gestes et durées mesurés), M27-E03 (RabbitMQ), M21-M22 (tableaux, alertes, journaux).
**Durée indicative** : 1 h 30.

**Travail demandé**

1. `docs/donnees/runbooks/RB-270-postgresql-maintenance-bascule.md`, au format des runbooks du M21 : symptômes et alertes qui y mènent ; **état en une minute** (commandes et ce qu'il faut lire dans leur sortie) ; procédures **planifiées** (bascule volontaire, nœud à drainer, mise à jour mineure de l'image, redémarrage de toutes les instances) ; **bascule subie** (ce que fait CloudNativePG seul, combien de temps attendre, que vérifier, quand promouvoir à la main) ; vérifications de fin ; **interdits** ; escalade ; historique.
2. Chaque commande est copiable, chaque durée vient de tes mesures d'E02 (cite-les). Les commandes qui écrivent sont précédées de leur prérequis (sauvegarde, fenêtre, approbation).
3. Fais-le **tester** : demande à quelqu'un (ou joue Nadia, à froid, le lendemain) de dérouler la bascule volontaire en recette avec le seul runbook ; corrige ce qui l'a arrêté.
4. Facultatif : `RB-271-rabbitmq-redemarrage-roulement.md` (un nœud à la fois, vérifier les files quorum et les alarmes avant de passer au suivant, ce que fait l'opérateur, ce qu'il ne faut pas faire : `rabbitmqctl forget_cluster_node`, `reset`).
5. Lie le runbook depuis les alertes concernées (`runbook_url`) et depuis `docs/donnees/postgresql.md`.

**Critères de réussite**
- [ ] `RB-270-postgresql-maintenance-bascule.md` existe sur `main` avec les sections : état, procédures planifiées, bascule subie, interdits, escalade.
- [ ] Il contient les commandes `kubectl cnpg status`, `kubectl cnpg promote` et `kubectl drain`, et des durées mesurées (plus aucune valeur à compléter).
- [ ] Il a été testé par quelqu'un d'autre (ou à froid) et corrigé (section Historique).
- [ ] `docs/donnees/postgresql.md` renvoie vers RB-270.

**Vérification** : `lab/bin/check 27 12`

<details><summary>Indice 1</summary>

Les questions de Nadia à 2 h 10 : « Est-ce que l'API répond ? Y a-t-il un primaire ? Depuis combien de temps n'y en a-t-il plus ? Est-ce que je risque de perdre des données si je promeus ? » Le runbook y répond dans cet ordre. `kubectl cnpg status` donne le primaire courant, le *timeline*, le retard de chaque réplique et l'état de l'archivage ; la condition `Ready` du `Cluster` et l'événement `FailoverStarted`/`SwitchoverStarted` datent la bascule.
</details>

**Pour aller plus loin** (facultatif) : ajoute un arbre de décision (Mermaid) en tête du runbook.
