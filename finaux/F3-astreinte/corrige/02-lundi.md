# Final F3 — Corrigé de la phase 2 : lundi

> ⚠️ Corrigé. À n'ouvrir qu'après avoir cherché.

**Validé hors du lab** : règles et tests `promtool` de [`alertes-exploitation-f3`](fichiers/S03/observabilite/regles/alertes-exploitation-f3.yaml) et de [`delais-mediagenda.test.yaml`](fichiers/S04/observabilite/tests/delais-mediagenda.test.yaml) (Prometheus 3.5 ; le second rejoué sur les règles du corrigé de M21-E23, et **rouge** avec `for: 12h`) ; injection de la route vers `null` et essais de routage rejoués avec `amtool` 0.28 sur la configuration du corrigé de M21-E16 ; garde-fou `verifier-routes-null.sh` (rouge sur la configuration injectée, vert sur celle de M21-E16).
**Points non testés en conditions réelles** : l'effet de chaque variante de S03 sur la latence mesurée de ton lab (seuils du constat : 1,5 s et trois fois la référence) ; en variante 3, l'ajout d'une limite CPU de 10m par `pods/resize` sur un pod Burstable sans limite CPU (permis par la documentation de Kubernetes 1.35+, la limite ne pouvant ensuite plus être retirée en place) et son effet sur la sonde de vivacité `/sante` (délai d'une seconde : un conteneur redémarré garde ses 10m, jusqu'à la recréation du pod) ; l'interception de `pods/exec` (opération `CONNECT`) par une `ValidatingPolicy` de Kyverno 1.19 ; les noms exacts des métriques `cnpg_backends_waiting_total`, `cnpg_backends_max_tx_duration_seconds` et `redis_config_maxmemory` (les checks sautent la ligne si la série est absente).

---

### F3-S03 — Lundi : « MédiAgenda rame »

**Démarche de diagnostic** (commune aux trois variantes)

*Symptômes* : lenteur rapportée par les cabinets ; pas d'alerte (c'est S04).

1. **Mesurer soi-même** (main courante, `[action]`) :
   ```
   admin@adm01:~$ U=https://mediagenda.apps.par1.medisphere.internal ; J=$(date -d '+30 days' +%F)
   admin@adm01:~$ for i in 1 2 3; do curl -s -o /dev/null -w '%{time_total}\n' "$U/api/v1/creneaux?date=$J&praticien=tous"; done        # en cache après la 1re
   admin@adm01:~$ for i in 1 2 3; do curl -s -o /dev/null -w '%{time_total}\n' "$U/api/v1/creneaux?date=$J&praticien=x$RANDOM"; done   # toujours hors cache
   admin@adm01:~$ curl -s -w ' %{time_total}\n' $U/pret
   ```
2. **Hypothèses par étage** (RB-330 §1) : entrée et pods (tout est lent) ; base (seul le hors-cache est lent) ; cache (tout un peu plus lent, la base reçoit beaucoup plus de requêtes).
3. **Mesures** : Grafana « MédiAgenda » (p95 par environnement, taux de succès du cache) et « Données » (PgBouncer, PostgreSQL) ; puis les commandes de chaque étage ci-dessous.

**Variante 1 — un « rapport » verrouille la table des rendez-vous**

- Mesure : en cache 40 ms, hors cache 2 à 8 s (selon le moment du cycle), `/pret` rapide.
- Pooler : `SHOW POOLS;` → `cl_waiting` > 0, `maxwait` de plusieurs secondes. PostgreSQL :
  ```
  admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-prod -- -d mediagenda -c \
    "SELECT pid, usename, application_name, client_addr, state, wait_event_type, now()-xact_start AS age, pg_blocking_pids(pid), left(query,50)
     FROM pg_stat_activity WHERE datname='mediagenda' ORDER BY xact_start NULLS LAST;"
  ```
  Les sessions de l'API (`application_name = mediagenda`) sont en `wait_event_type = Lock`, bloquées par une session `rapport-activite` sans `client_addr` (socket local : elle a été lancée **dans** le pod du primaire), dont la requête est `LOCK TABLE public.rendez_vous;` puis `SELECT pg_sleep(8)` : `LOCK TABLE` sans mode prend `ACCESS EXCLUSIVE`, qui bloque même les `SELECT`.
- Cause racine : Lucas a lancé un « rapport d'activité » à la main sur le primaire de production, avec un verrou exclusif « pour une extraction cohérente » (une transaction en `REPEATABLE READ` suffisait, et sur un réplica).
- Rétablissement (`[décision]` d'abord : la session n'écrit rien, la terminer n'annule aucune donnée) : `SELECT pg_terminate_backend(<pid>);`. psql, non interactif, sort à la perte de connexion ; le générateur qui l'alimentait s'arrête (tube rompu). Vérifie qu'aucune session `rapport-activite` ne revient, et que plus rien ne tourne dans le conteneur `postgres` (`ps` dans le pod, ou demander à Lucas d'arrêter sa boucle).
- Correction par le code : délais de verrou et de requête pour les rôles dynamiques de l'API ([`db-mediagenda.extrait-F3-S03.tf`](fichiers/S03/secrets/tofu/db-mediagenda.extrait-F3-S03.tf), MR `plateforme/secrets`) : l'API échouera vite et clairement au lieu d'empiler des connexions ; plus d'`exec` humain en production hors bris de glace ([`prod-gestes-interactifs.yaml`](fichiers/S03/politiques/kyverno/prod-gestes-interactifs.yaml), MR `plateforme/politiques`) ; alerte `PostgresqlVerrouProlonge` ([`alertes-exploitation-f3.yaml`](fichiers/S03/observabilite/regles/alertes-exploitation-f3.yaml)). Ticket PLAT-3303-a : les rapports vont sur `mediagenda-db-ro`, par un compte en lecture.

**Variante 2 — Valkey ne garde plus rien**

- Mesure : tout est un peu plus lent, la **même** requête répétée reste lente (jamais servie par le cache) ; Julien voit la base de production recevoir bien plus de requêtes. Tableau MédiAgenda : `mediagenda_cache_total{resultat="miss"}` ≈ 100 %.
- Valkey (compte `admin`, bris de glace du M27, consigné) :
  ```
  admin@adm01:~$ kubectl -n mediagenda-prod exec -it valkey-0 -c valkey -- valkey-cli --tls --insecure --user admin --askpass
  > CONFIG GET maxmemory          → quelques Mo, alors que le dépôt dit davantage
  > INFO stats                    → evicted_keys qui grimpe à chaque requête, keyspace_hits ≈ 0
  ```
- Cause racine : `maxmemory` réduit **à chaud** (`CONFIG SET`) par Lucas « pour alléger Valkey » : avec la politique `allkeys-lru`, chaque clé écrite en évince une autre ; le cache ne sert plus et la charge part sur PostgreSQL (dans le lab, la base absorbe sans peine ; à 400 cabinets, c'est elle qui sature).
- Rétablissement : `CONFIG SET maxmemory <valeur du component valkey de mediagenda/deploiement>`. **Pas** de redémarrage de `valkey-0` pour « recharger la configuration » : `/pret` dépend de Valkey, tous les pods de l'API deviendraient non prêts le temps du redémarrage (la faiblesse de conception vue au M29-E23).
- Correction par le code : la configuration est déjà dans Git ; ce qui manquait, c'est de **voir** la dérive : alerte `ValkeyMemoireDerivee` ([`alertes-exploitation-f3.yaml`](fichiers/S03/observabilite/regles/alertes-exploitation-f3.yaml), testée). Ticket : ACL du compte `admin` de Valkey sans `CONFIG SET` hors bris de glace (`-config|set`), et `/pret` qui ne dépend plus de Valkey (PLAT-3303-c, avec Julien).

**Variante 3 — les pods de l'API ont été réduits en place**

- Mesure : tout est lent, `/pret` compris, surtout quand plusieurs requêtes arrivent ensemble ; `MediagendaCpuBride` se déclencherait au bout de 15 min.
- Kubernetes :
  ```
  admin@adm01:~$ kubectl -n mediagenda-prod get pods -l app.kubernetes.io/component=api -o custom-columns=POD:.metadata.name,REQ:.spec.containers[0].resources.requests.cpu,LIM:.spec.containers[0].resources.limits.cpu
  admin@adm01:~$ kubectl -n mediagenda-prod get deploy mediagenda -o jsonpath='{.spec.template.spec.containers[0].resources}'
  admin@adm01:~$ kubectl -n mediagenda-prod get events --field-selector reason=ResizeCompleted   # selon la version : Resize*, voir aussi .status.conditions des pods
  ```
  Les pods ont une requête CPU de 10m **et une limite CPU de 10m** alors que leur gabarit dit 200m sans limite CPU (M28-E02) ; métriques `container_cpu_cfs_throttled_periods_total` en hausse (`MediagendaCpuBride`). Le gabarit n'a pas changé : seuls les pods en cours ont été modifiés. L'HPA a pu ajouter des pods (la requête abaissée fait monter le taux d'utilisation) : ceux-là sont rapides, les anciens restent lents — « certains cabinets seulement ».
- Cause racine : redimensionnement en place (`pods/resize`, GA en Kubernetes 1.35) fait à la main par Lucas « en appliquant la recommandation du VPA » (le VPA est en mode `Off` : il recommande, il n'applique pas).
- Rétablissement : `kubectl argo rollouts restart mediagenda -n mediagenda-prod` (pods recréés depuis le gabarit, un par un, sans nouvelle révision ni canary) ; l'HPA redescend seul. Un nouveau `resize` ne suffit pas : on peut remonter la requête, mais une limite posée en place **ne peut plus être retirée** en place (limite documentée de Kubernetes) — seul un pod recréé retrouve « pas de limite CPU ».
- Correction par le code : refus de `pods/resize` en production hors VPA et bris de glace ([`prod-gestes-interactifs.yaml`](fichiers/S03/politiques/kyverno/prod-gestes-interactifs.yaml)) ; check de conformité « pods = gabarit » (repris par le check de S03).

**Messages d'état types** (SEV2 : premier message sous 30 min, puis toutes les 60 min) : modèles de [`modeles-messages.md`](fichiers/S02/medisphere/docs/exploitation/modeles-messages.md) (l'exemple « Début », « Point d'étape », « Fin » est précisément INC-5903, variante 1). Pour la variante 3, « Point d'étape » : « rétabli depuis HH:MM par le redémarrage progressif des instances de l'application ; cause : ressources réduites à la main sur les instances de production ».

**Main courante attendue** : voir [`journal/2026-11-02.md`](fichiers/S01/medisphere/docs/exploitation/journal/2026-11-02.md) (variante 1) : ouverture avec gravité et rôles, mesures chiffrées en `[action]`, `[état]` à chaque message, la `[décision]` avant `pg_terminate_backend` (ou avant le redémarrage progressif), clôture avec durée d'impact, cause en une phrase et tickets.

Runbook : [`RB-330-mediagenda-lent-en-production.md`](fichiers/S03/medisphere/docs/exploitation/runbooks/RB-330-mediagenda-lent-en-production.md).

**Explications**

Le même symptôme (« ça rame ») a trois causes à trois étages, et chacune a sa signature : un étage lent seulement pour les requêtes qui touchent la base (verrou), un cache qui ne sert plus (la même requête n'est jamais plus rapide la seconde fois), des pods lents pour tout, y compris `/pret` (CPU). Mesurer la requête en cache et hors cache, puis `/pret`, classe la panne en une minute. Les trois causes ont un point commun : un geste **à la main en production** qui ne laisse pas de trace dans Git. D'où la correction par le code : non pas « remettre la bonne valeur » (elle est déjà dans Git) mais **empêcher le geste** ou **voir la dérive**.

**Alternatives**

- Variante 1 : `idle_in_transaction_session_timeout` ne suffit pas (la session n'est pas oisive, elle exécute `pg_sleep`) ; `statement_timeout` global sur la base gênerait Flyway et les sauvegardes : les réglages par rôle sont plus fins. `pg_cancel_backend` annule la requête en cours mais laisse la transaction, qui garde son verrou : il faut `pg_terminate_backend`.
- Variante 2 : redémarrer Valkey rétablit aussi (la configuration de Git est relue), au prix d'une coupure de `/pret` ; acceptable la nuit, pas un lundi à 9 h.
- Variante 3 : supprimer les pods un par un (le ReplicaSet les recrée depuis le gabarit) ; le redémarrage du Rollout fait la même chose en respectant la disponibilité.

**Pièges classiques**

- Redémarrer l'API « pour voir » : en variantes 1 et 2, rien ne change ; en variante 3, ça marche **sans qu'on sache pourquoi**, et la cause revient.
- Redémarrer PostgreSQL ou basculer le primaire pour libérer le verrou : coupure de toutes les sessions, bascule, risque — pour un résultat qu'un `pg_terminate_backend` obtient seul.
- `pg_terminate_backend` sur les sessions **bloquées** (celles de l'API) au lieu de la session **bloquante**.
- Oublier le générateur : la session revient toute seule si un processus la relance.
- Conclure « tout va bien » en variante 2 parce que la latence du lab reste correcte : le taux de succès du cache est l'indicateur, pas la latence d'une base vide.

**En production chez MédiSphère**

Les rapports et extractions passent par un réplica en lecture et un compte dédié, jamais par le primaire ; les gestes interactifs en production (exec, resize, `CONFIG SET`) sont refusés hors bris de glace et alertés quand ils ont lieu (audit de l'API, M22) ; la latence de production a une alerte de **SLO** (taux de consommation du budget d'erreur, Pyrra) qui réveille l'astreinte, ce que ne fait pas l'avertissement `MediagendaLatenceElevee` (voir S04 et PLAT-3304).

---

### F3-S04 — Lundi : pourquoi personne n'a été prévenu ?

**Démarche de diagnostic**

*Symptôme* : aucune alerte reçue pendant 40 min de lenteur ; le témoin de `mon01` n'a rien dit.

1. **La supervision est-elle vivante ?** Témoin : `probe_success{job="watchdog-cluster"} = 1` → Prometheus, ses règles et Thanos fonctionnent ; le problème est **dans la chaîne de MédiAgenda**, pas dans la supervision entière.
2. **Reconstituer ce qui aurait dû se passer** : quelles règles pouvaient voir la lenteur de lundi ? `MediagendaLatenceElevee` (p95 prod > 300 ms pendant 15 min, **avertissement**, équipe `mediagenda`) ; `PgbouncerClientsEnAttente` (M27, avertissement) ; rien de critique. Destinataire attendu : `mediagenda-mail` (heures ouvrées) ; l'astreinte, elle, ne reçoit que les critiques.
3. **Une requête qui classe la panne** : alerte d'essai avec les étiquettes exactes, puis API v2 de l'Alertmanager (RB-331 §2) :
   ```
   admin@adm01:~$ amtool $AM alert add MediagendaLatenceElevee gravite=avertissement equipe=mediagenda environnement=prod \
       --annotation=resume="essai INC-5904" --end=$(date -d '+10 min' -Iseconds)
   admin@adm01:~$ curl -s http://alertmanager.apps.par1.medisphere.internal:9093/api/v2/alerts -G \
       --data-urlencode 'filter=alertname="MediagendaLatenceElevee"' | jq '.[] | {receivers: [.receivers[].name], state: .status.state, silencedBy: .status.silencedBy}'
   ```
4. Selon la réponse :

**Variante 1 — une route envoie MédiAgenda production vers « null »**

- Réponse : `receivers: ["null"]`, `state: active`. `amtool config routes show` sur la configuration chargée : une première route `equipe = "mediagenda", environnement = "prod" → null`.
- Origine : `git log -p -- kps/values.yaml` dans `plateforme/observabilite` : commit de Lucas (marqueur `F3-S04`) « couper le bruit de MédiAgenda prod pendant la reprise Flyway », qui modifie **aussi** `alertmanager/routes-tests.txt` (les lignes de MédiAgenda prod attendent désormais `null`) : la CI est restée verte parce que le test a été changé avec le code qu'il teste.
- Correction : MR qui annule le commit (`git revert`), synchronisation de l'Application de l'observabilité, essai §3 refait → `astreinte-mail,mediagenda-mail` pour une critique, `mediagenda-mail` pour l'avertissement.
- Prévention : garde-fou [`outils/verifier-routes-null.sh`](fichiers/S04/observabilite/outils/verifier-routes-null.sh) dans la CI (aucune route vers `null` choisie par équipe, environnement ou espace) ; lignes d'essai de MédiAgenda prod protégées par `CODEOWNERS` (revue de l'astreinte) : [`routes-tests.ajouts-F3-S04.txt`](fichiers/S04/observabilite/alertmanager/routes-tests.ajouts-F3-S04.txt). Pour couper du bruit pendant une opération : un **silence** précis et daté, pas une route.

**Variante 2 — la règle de latence attend 12 h**

- Réponse de l'essai : `receivers: ["mediagenda-mail"]`, `state: active` → la route est bonne ; l'alerte d'essai arrive. Le problème est **avant** : la vraie alerte n'a jamais atteint l'Alertmanager.
- Prometheus : `/api/v1/rules?type=alert` → `MediagendaLatenceElevee` `duration: 43200` (12 h) : l'alerte était `pending` lundi matin et le serait restée tout le jour. `git log -p -- regles/` : commit de Lucas « moins nerveuse ».
- Correction : MR (revert), synchronisation, vérification de `duration: 900`.
- Prévention : test de **délais** [`tests/delais-mediagenda.test.yaml`](fichiers/S04/observabilite/tests/delais-mediagenda.test.yaml) (l'alerte doit être déclenchée à 20 min d'une latence de 500 ms ; rouge avec `for: 12h`, vérifié) ; `CODEOWNERS` sur `regles/alertes-mediagenda.yaml` (Julien et l'astreinte).

**Variante 3 — un silence de 7 jours couvre toute l'équipe**

- Réponse : `state: suppressed`, `silencedBy: ["<id>"]`. `amtool $AM silence query -o extended` : silence de `lucas.martin`, matcher `equipe="mediagenda"`, 7 jours, commentaire « CHG-3303 reprise Flyway recette ». Il visait la recette ; il couvre la production (aucun matcher d'environnement).
- Rétablissement : après accord (Lucas, ou `[décision]` du responsable d'incident), `amtool $AM silence expire <id>` ; si l'opération de recette n'est pas finie, nouveau silence **précis** : `equipe=mediagenda environnement=recette`, durée de l'opération.
- Prévention : règle d'équipe dans RB-331 et la procédure (un silence vise un objet précis, dure le temps de l'opération, cite son ticket) ; ticket PLAT-3304-b : un contrôle du témoin de `mon01` qui liste chaque nuit les silences de plus de 24 h ou sans matcher d'environnement (API v2 de l'Alertmanager) et prévient la plateforme.

**La question qui fâche (PLAT-3304)** : même sans la panne, la lenteur de lundi n'aurait **pas** réveillé l'astreinte : `MediagendaLatenceElevee` est un avertissement (route de l'équipe, heures ouvrées). À 9 h 10 un lundi, Julien l'aurait reçue au bout de 15 min. Le ticket propose : une alerte de **taux de consommation du budget d'erreur** du SLO de latence (Pyrra, M21-E26) en `critique` pour la production (rapide, sur 1 h et 5 min), qui, elle, réveille ; l'avertissement actuel reste pour l'équipe.

**Messages d'état types** (SEV3 : la plateforme était aveugle pour une application, aucun impact en cours ; certains choisiront SEV2 tant que la cause n'est pas connue — défendable) : premier message « la chaîne d'alerte de MédiAgenda production ne prévenait personne ; aucun incident en cours ; analyse en cours ; prochain point à HH:MM » ; message de fin « cause : <route|règle|silence> modifié(e) le <date> ; corrigé par <MR|expiration> ; preuve : alerte d'essai reçue par l'astreinte et l'équipe à HH:MM ; prévention : <tests, garde-fous> ; PLAT-3304 : faut-il réveiller sur la latence ? ».

**Main courante attendue** : `[ouverture]` (gravité justifiée), `[action]` avec la réponse de l'API v2 (récepteur, état), `[action]` origine (commit ou silence : auteur, date), `[décision]` (revert, ou expiration du silence avec accord), `[action]` preuve (alerte d'essai reçue, heure), `[clôture]`.

Runbook : [`RB-331-alerte-non-recue.md`](fichiers/S04/medisphere/docs/exploitation/runbooks/RB-331-alerte-non-recue.md).

**Explications**

Une alerte traverse cinq étages (règle, évaluation et `for`, envoi, route et mise en sourdine, notification) et chacun peut la perdre sans bruit. L'API v2 de l'Alertmanager montre d'un coup trois étages (route, silence, inhibition) : c'est par elle qu'on commence. Les trois variantes sont des changements **légitimes en apparence** (réduire du bruit) faits au mauvais endroit : une route pour un besoin temporaire, un `for` pour un seuil, un silence trop large. La leçon de prévention est que le test qui protège un comportement ne doit pas pouvoir être modifié dans le même mouvement que ce comportement sans un second regard.

**Alternatives**

- Inhibition plutôt que silence pour un bruit récurrent (ex. pendant les migrations : alerte `MigrationEnCours` qui inhibe les avertissements de latence de l'environnement concerné) : automatique et bornée par l'événement.
- `mute_time_intervals` pour des fenêtres de maintenance régulières.
- Sonde de bout en bout (Pour aller plus loin) : prouve en continu le chemin complet jusqu'à la boîte.

**Pièges classiques**

- Tester l'arbre de routage avec `amtool config routes test` sur le **fichier du dépôt** : il est juste (après le revert) mais ce n'est pas forcément ce qui est **chargé** ; utilise la configuration renvoyée par `/api/v2/status`.
- Expirer le silence sans prévenir son auteur : l'opération de recette qu'il couvrait se met à bruiter, et quelqu'un le recréera aussi large.
- Croire que le témoin de `mon01` aurait dû voir la panne : il surveille la **supervision** (Watchdog), pas chaque route ; c'est pour cela qu'il est resté vert, et c'est normal.
- Ne pas répondre à la question de PLAT-3304 : on répare la panne et l'astreinte ne sera toujours pas réveillée la prochaine fois.

**En production chez MédiSphère**

Revue mensuelle des silences et des routes (politique d'alerte du M21-E32), tests de délais pour chaque alerte critique, sonde de bout en bout horaire, et SLO de latence avec alerte de budget en production : c'est le chantier que S15 commence.
