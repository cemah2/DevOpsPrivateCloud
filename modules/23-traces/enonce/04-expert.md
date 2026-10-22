# Module 23 — Palier 4 : Expert

La chaîne de traces est en production : agents, passerelle à deux réplicas qui échantillonne en queue, Tempo, Pyroscope, des liens entre les quatre signaux, un point d'entrée chiffré et authentifié, des alertes. Nadia Roussel connaît la suite : « Le jour où l'API est lente, c'est exactement là que les traces manquent. » Karim Benali a préparé quatre familles de pannes, celles que racontent les retours d'expérience OpenTelemetry : plus aucune trace, des traces coupées en morceaux, un Collector qui perd des données en silence, des liens qui ne mènent plus nulle part. Une astreinte en combine une avec une vraie lenteur de l'API. Puis tu descends sous le capot : le contexte qui voyage dans un en-tête, le message OTLP, le bloc Parquet dans le compartiment.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres à l'observabilité :
- **L'observabilité s'observe.** Chaque Collector publie ses propres métriques (`otelcol_receiver_*`, `otelcol_processor_*`, `otelcol_exporter_*`, files d'attente), Tempo les siennes (`tempo_distributor_*`, `tempo_discarded_spans_total`). Commence par elles : elles disent **quel maillon** a cessé de recevoir, de transmettre ou d'accepter.
- **Remonte la chaîne dans l'ordre** : application (SDK, variables `OTEL_*`, journaux d'export), agent du nœud, réseau (politiques Cilium, Hubble), passerelle (échantillonnage, files), Tempo (limites), Grafana (sources et liens). Le premier maillon muet est le coupable, pas le dernier.
- **Le code fait foi, Argo CD aussi.** Une correction à la main dans le cluster est défaite à la synchronisation suivante (`selfHeal`) : on corrige dans Git (`plateforme/observabilite`, `…/deploiement`), on fait relire, Argo CD applique. Un `kubectl edit` ne sert qu'à **tester** une hypothèse, en connaissance de cause.

> **Rappels** : tout se lance depuis `adm01`. Configurations : `plateforme/observabilite/otel/` (Collectors), `tempo/`, `grafana/` (sources), `regles/` ; applications : `mediagenda/deploiement` et `medidoc/deploiement` (overlays `dev`, `recette`, `prod`). Les sources Grafana sont lues par le *sidecar* ; `GET /api/frontend/settings` montre ce que Grafana utilise réellement.

## Règles du jeu des pannes (M23-E19 à M23-E23)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 23 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes ; `--variante N` en force une, sans dire laquelle est laquelle. Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé), le script en essaie une autre. Une injection prend de 2 à 10 minutes : la plupart passent par un **commit dans Git** que le script attend de voir appliqué par Argo CD, puis il **constate** la panne (plus de traces, compteurs de pertes…) avant d'afficher le ticket.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 23 19`) : il doit être vert. Le script refuse de casser une chaîne qui ne marche pas déjà (collectors pas prêts, aucune trace récente de MédiAgenda en dev).
- **Environnement visé : dev.** MédiAgenda et MédiDoc de dev (`mediagenda-dev`, `medidoc-dev`), synchronisés automatiquement, sans canary. La recette et la production ne sont jamais touchées par les pannes, sauf une panne de la chaîne commune (Collectors, Tempo, Grafana), qui les prive aussi de traces le temps de la réparation.
- **Témoin de trafic.** À la première injection, le script crée dans l'espace **`wb-pannes`** un déploiement `trafic-agenda` qui joue les utilisateurs : deux requêtes par seconde sur `https://mediagenda-dev.apps.par1.medisphere.internal` (créneaux, liste, création puis annulation de rendez-vous factices, et l'appel qui traverse MédiDoc de M23-E06). Ne l'arrête pas pendant les pannes ; supprime-le toi-même à la fin du module (`kubectl delete deploy,cm -n wb-pannes -l …` ou l'espace s'il ne sert plus) : MédiDoc n'ayant pas d'API de suppression, chaque appel y laisse un document factice de quelques octets. Variables facultatives de `lab/lab.env` : `WB_M23_IMAGE_AGENDA` (image du témoin, sinon celle de MédiAgenda en dev), `WB_M23_APPEL_DOC` (sinon découvert dans `/openapi.json`), `WB_M23_TEMPO_UID` (sinon découvert), `WB_M23_ATTR_ENV`.
- **Les commits de la panne** sont signés **Lucas Martin** et portent `M23-EXX` dans leur message : les retrouver fait partie du diagnostic (`git log`, MR, historique d'Argo CD). Le script pousse avec le jeton d'administration du lab (`WB_GITLAB_ADMIN_TOKEN_FILE`) ; si `main` refuse la poussée directe, il passe par une MR fusionnée automatiquement. `yq` (mikefarah) est requis sur `adm01`.
- **Ne lis pas** les scripts de `corrige/pannes/` ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 23 19 --annuler` remet l'état sain par un **commit inverse** (jamais par réécriture d'historique), filet de sécurité qui compte l'exercice comme non réussi. **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : l'annulation ne revient jamais sur ta réparation (elle ne touche un fichier que s'il porte encore exactement le contenu de la panne).
- Les pannes ne suppriment **jamais** de données (compartiments `tempo-k8s-par1`, `loki-k8s-par1`, `pyroscope-k8s-par1`, bases) et ne désactivent jamais l'auto-synchronisation d'Argo CD.
- **Tiens un journal de diagnostic** par panne dans `docs/kubernetes/journal/` de `plateforme/medisphere` : heure, hypothèse, commande, résultat, conclusion. Il nourrit les runbooks RB-230 à RB-233 et le post-mortem de M23-E23.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Effets de bord** : une panne de la chaîne commune prive de traces **tous** les environnements tant qu'elle dure ; préviens Julien avant d'injecter (canal de l'équipe) et répare avant de passer à autre chose. Pour revenir en arrière à tout moment : `lab/bin/break 23 <XX> --annuler`, puis `argocd app get otel` (ou l'Application concernée) jusqu'à `Synced`.

---

### M23-E19 — Panne : plus aucune trace  `BF` `★★`

> **Ticket INC-5019** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection.)* Depuis ce matin, Grafana ne trouve plus aucune trace de MédiAgenda en dev. L'API répond, les métriques et les journaux arrivent. Lucas a « fait un peu de ménage » dans les configurations hier.

**Objectifs pédagogiques**
- Localiser le maillon muet d'une chaîne de télémétrie par ses propres métriques, puis par les journaux et la configuration de ce maillon.
- Distinguer une panne de l'émetteur (variables `OTEL_*`, protocole), du réseau (politiques Cilium) et d'un Collector (récepteur, exportateur).
- Corriger dans Git et vérifier le rétablissement de bout en bout.

**Prérequis** : M23-E02, M23-E09, M23-E16 ; `lab/bin/check 23 19` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : MédiAgenda et MédiDoc envoient leurs spans en OTLP/gRPC à l'agent de leur nœud (`otel-agent-collector.traces.svc`, port 4317 ; 4318 est l'OTLP/HTTP) ; l'agent les relaie à la passerelle (exportateur `loadbalancing`, port 4317), qui les envoie à Tempo (`tempo.traces.svc:4317`). Les SDK OpenTelemetry n'arrêtent pas l'application quand l'export échoue : ils journalisent l'échec et abandonnent les spans.

**Injection** : `lab/bin/break 23 19` (4 variantes).

**Travail demandé**
1. Constate : depuis quand plus rien n'arrive dans Tempo ? Tous les services ou un seul ? Tous les environnements ? Réponds par les métriques des Collectors (ce qui est accepté, envoyé, en échec, à chaque maillon), avant de lire une configuration.
2. Descends au maillon muet : journaux de l'émetteur, configuration vivante du Collector concerné (`kubectl get otelcol … -o yaml`), politiques réseau de l'espace `traces` et Hubble (`hubble observe … --verdict DROPPED`), historique Git du dépôt concerné.
3. Corrige à la racine, par le code, et vérifie : nouvelles traces de `mediagenda-api` et `medidoc` dans Tempo, compteurs d'échec à zéro.
4. Écris RB-230 « Plus aucune trace » (`docs/observabilite/traces/runbooks/`) : arbre de diagnostic par maillon, avec pour chacun la métrique ou la commande qui le prouve et le correctif. Dis quelle alerte aurait dû prévenir avant Julien.

**Critères de réussite**
- [ ] Collectors prêts ; traces récentes de `mediagenda-api` et `medidoc` en dev ; aucune règle Cilium ne refuse l'OTLP dans `traces` ; exportateur de la passerelle vers un Tempo qui existe ; récepteur de l'agent en gRPC et HTTP ; aucune erreur d'export récente.
- [ ] RB-230 publié ; ton journal contient le maillon en cause et sa preuve ; la panne est close.

**Vérification** : `lab/bin/check 23 19`

<details><summary>Indice 1</summary>

`sum by (job) (rate({__name__=~"otelcol_receiver_accepted_spans(_total)?"}[5m]))` et la même chose pour `otelcol_exporter_sent_spans` et `otelcol_exporter_send_failed_spans`, par `job` et `exporter` : si les agents ne reçoivent plus rien, regarde du côté de l'application ; s'ils reçoivent mais que la passerelle ne reçoit rien, regarde entre les deux ; si la passerelle reçoit mais n'envoie pas, regarde vers Tempo.
</details>

<details><summary>Indice 2</summary>

Un client gRPC qui parle à un port HTTP/1, ou l'inverse, échoue avec un message qui ne dit pas « mauvais port » (`UNAVAILABLE`, `connection reset`, réponse illisible). Compare l'adresse d'export de l'application au protocole attendu sur ce port et à ce que le récepteur de l'agent accepte réellement. Une règle Cilium de refus (`ingressDeny`) l'emporte sur toutes les autorisations.
</details>

**Pour aller plus loin** : fais échouer volontairement l'export d'un SDK (port fermé) et mesure ce qu'il garde en mémoire et pendant combien de temps (`OTEL_BSP_MAX_QUEUE_SIZE`, `OTEL_EXPORTER_OTLP_TIMEOUT`) ; à partir de quand perd-il des spans ?

---

### M23-E20 — Panne : les traces sont coupées en morceaux  `BF` `★★★`

> **Ticket INC-5020** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection.)* Les traces de MédiAgenda qui appellent MédiDoc sont incomplètes : la partie MédiDoc manque, ou apparaît dans une trace séparée, sans parent. Rien n'a changé dans le code des deux applications.

**Objectifs pédagogiques**
- Comprendre ce qui fait d'une suite de spans **une** trace : un contexte propagé (W3C `traceparent`), une décision d'échantillonnage partagée, un échantillonnage en queue qui voit toute la trace.
- Prouver, trace à l'appui, laquelle de ces conditions a cassé, avec des requêtes TraceQL structurelles.
- Corriger sans dégrader le volume ni la confidentialité.

**Prérequis** : M23-E06, M23-E09 ; `lab/bin/check 23 20` vert avant l'injection (il exige des traces MédiAgenda → MédiDoc récentes, produites par le témoin de trafic).
**Durée indicative** : 60 min (temps cible).

**Contexte technique** : en dev, MédiAgenda et MédiDoc émettent tout en tête (`parentbased_traceidratio`, ratio 1.0) ; la passerelle garde en queue les traces en erreur ou lentes et 10 % du reste. Les SDK Python et Go de nos applications lisent `OTEL_PROPAGATORS` et `OTEL_TRACES_SAMPLER` (+ `_ARG`) au démarrage. TraceQL : `>>` (descendant), `trace:rootService`, `nestedSetParent`.

**Injection** : `lab/bin/break 23 20` (3 variantes).

**Travail demandé**
1. Constate avec TraceQL : combien de traces entières `mediagenda-api` → `medidoc` sur 30 min, combien de traces dont la racine est dans `medidoc`, combien de spans client de MédiAgenda vers MédiDoc ? Ouvre une trace « orpheline » : sa racine a-t-elle un parent inconnu, ou aucun parent ?
2. Pose les trois hypothèses (propagation, échantillonnage en tête, échantillonnage en queue) et teste-les dans l'ordre le moins coûteux : variables des pods des deux services, en-têtes réellement reçus par MédiDoc, configuration de l'agent et répartition des spans d'une trace entre les deux réplicas de la passerelle.
3. Retrouve le changement en cause (commit, MR) et corrige par le code.
4. Vérifie : traces entières sur 15 min, aucune racine dans MédiDoc, arête `mediagenda-api` → `medidoc` dans le graphe de services.
5. Écris RB-231 « Traces coupées en morceaux ».

**Critères de réussite**
- [ ] Des traces distribuées MédiAgenda → MédiDoc récentes, aucune trace de dev enracinée dans MédiDoc depuis 10 min.
- [ ] Propagateurs avec `tracecontext`, échantillonneurs `parentbased_*`, agents équilibrés par `traceID` vers une passerelle à 2 réplicas.
- [ ] RB-231 publié ; ton journal contient la requête TraceQL qui a prouvé la cause ; la panne est close.

**Vérification** : `lab/bin/check 23 20`

<details><summary>Indice 1</summary>

`{resource.service.name = "mediagenda-api"} >> {resource.service.name = "medidoc"}` compte les traces entières ; `{trace:rootService = "medidoc"}` les morceaux. Une span dont `parentSpanId` est rempli mais introuvable dans Tempo n'a pas le même diagnostic qu'une span sans `parentSpanId`.
</details>

<details><summary>Indice 2</summary>

`kubectl -n mediagenda-dev get deploy mediagenda -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep OTEL_`, puis la même chose pour MédiDoc. Pour la passerelle : un agent qui envoie au Service ClusterIP garde **une** connexion gRPC vers **un** réplica ; deux agents de deux nœuds peuvent parler à deux réplicas différents pour la même trace.
</details>

**Pour aller plus loin** : mets un relais HTTP (un `nginx` dans `wb-essais`) entre MédiAgenda et MédiDoc, d'abord avec une liste blanche d'en-têtes qui oublie `traceparent`, puis corrigée ; observe le résultat dans Tempo. Lis le chapitre *Trace Context Level 2* (drapeau *random*) et ce qu'il change pour l'échantillonnage cohérent.

---

### M23-E21 — Panne : le Collector perd des données  `BF` `★★★`

> **Ticket INC-5021** — *De : Karim Benali*
> *(Le détail s'affiche à l'injection.)* Une grande partie des spans reçues par les Collectors n'arrive jamais dans Tempo ; des traces d'erreurs provoquées exprès sont introuvables. Lucas a appliqué des « réglages de débit » trouvés sur un forum. Trouve où les données se perdent et dis-moi quelle métrique aurait dû nous alerter.

**Objectifs pédagogiques**
- Lire le cycle de vie d'une span dans un Collector : refus à l'entrée (`memory_limiter`), mise en file, envoi, reprises, abandon ; et dans Tempo : limites d'ingestion.
- Relier un réglage (limite mémoire, taille de file, taille de lot, rafale d'ingestion) à son symptôme et à sa métrique.
- Poser l'alerte qui détecte la perte de données avant les utilisateurs.

**Prérequis** : M23-E09, M23-E16 (limites, alertes de la chaîne) ; `lab/bin/check 23 21` vert avant l'injection.
**Durée indicative** : 60 min (temps cible).

**Contexte technique** : le `memory_limiter` refuse les données quand le tas dépasse sa limite douce (limite − marge) ; un émetteur qui reçoit un refus réessaie. Chaque exportateur a une file (`sending_queue` : `sizer`, `queue_size`, `num_consumers`) et des reprises (`retry_on_failure`, abandon après `max_elapsed_time`). Tempo refuse au-delà de `rate_limit_bytes` (débit) et de `burst_size_bytes` (rafale : la plus grosse requête acceptable). Métriques utiles : `otelcol_receiver_refused_spans`, `otelcol_processor_memory_limiter_refused_spans`, `otelcol_exporter_enqueue_failed_spans`, `otelcol_exporter_send_failed_spans`, `otelcol_exporter_queue_size` et `_capacity`, `tempo_discarded_spans_total{reason}` (sans suffixe `_total` pour les métriques du Collector 0.16x).

**Injection** : `lab/bin/break 23 21` (3 variantes).

**Travail demandé**
1. Trace le chemin des spans de bout en bout avec les métriques : où le compte d'entrée cesse-t-il d'égaler le compte de sortie ? Mets les compteurs dans ton journal avec l'heure.
2. Confirme par les journaux du Collector et de Tempo (message exact) et par la configuration vivante ; retrouve le commit.
3. Corrige par le code. Si plusieurs réglages ont bougé, explique le rôle de chacun dans la perte.
4. Vérifie sous trafic : plus de refus ni de pertes pendant 15 min, files sous 50 %.
5. Écris RB-232 « Le Collector perd des données » et vérifie que les alertes de M23-E16 auraient sonné (sinon, corrige-les : expression, durée, gravité).

**Critères de réussite**
- [ ] Aucun refus, aucun échec de mise en file ni d'envoi depuis 10 min ; files sous 50 %.
- [ ] `memory_limiter` dimensionné, files d'au moins 100 éléments, lots bornés, Tempo sans délai artificiel et avec une rafale d'au moins 4 Mo.
- [ ] Une alerte Prometheus surveille la perte de spans ; RB-232 publié ; la panne est close.

**Vérification** : `lab/bin/check 23 21`

<details><summary>Indice 1</summary>

`sum by (job, exporter) (rate({__name__=~"otelcol_exporter_(sent|send_failed|enqueue_failed)_spans(_total)?"}[5m]))` et `max by (job, exporter) (otelcol_exporter_queue_size / otelcol_exporter_queue_capacity)`. Une file pleine avec une destination lente, des refus à l'entrée avec une mémoire faible, des échecs d'envoi avec un message de Tempo : trois maladies différentes.
</details>

<details><summary>Indice 2</summary>

Dans les journaux de la passerelle : `kubectl -n traces logs deploy/otel-passerelle-collector --since=15m | grep -i -E 'refused|dropping|queue is full|RATE_LIMITED|exceeded'`. Un message « exceeded while adding N bytes » où N dépasse la rafale permise ne guérira jamais par des reprises.
</details>

**Pour aller plus loin** : active une file d'attente **persistante** (extension `file_storage`, `sending_queue.storage`) sur un volume, coupe Tempo deux minutes et compare ce qui est perdu avec et sans elle ; que coûte-t-elle, et pourquoi n'est-elle pas compatible avec `wait_for_result` ?

---

### M23-E22 — Panne : impossible de passer d'une trace à ses journaux  `BF` `★★`

> **Ticket INC-5022** — *De : Nadia Roussel*
> *(Le détail s'affiche à l'injection.)* Pendant l'incident de cette nuit, impossible de passer d'une trace à ses journaux : le lien n'ouvre rien d'utile, et depuis une ligne de journal le lien vers la trace a parfois disparu. C'était tout l'intérêt de M23-E08. Lucas a « rangé » des sources de données.

**Objectifs pédagogiques**
- Comprendre ce que contient un lien entre signaux dans Grafana (source cible, locataire, requête construite, champ dérivé) et où il est déclaré.
- Lire la configuration **servie** par Grafana plutôt que celle qu'on croit avoir déclarée.
- Corriger une source provisionnée par le code, jamais dans l'interface.

**Prérequis** : M23-E08, M22 (locataires Loki, sources par locataire) ; `lab/bin/check 23 22` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : sources déclarées dans `plateforme/observabilite/grafana/` (ConfigMaps lues par le *sidecar*) ; une source Loki par locataire (`Loki — mediagenda`…, en-tête `X-Scope-OrgID`) ; liens `tracesToLogsV2` (source Tempo) et `derivedFields` (sources Loki, sur la métadonnée structurée `trace_id`). Le jeton des checks (`~/.config/workbook/grafana-checks.token`) lit `/api/frontend/settings`.

**Injection** : `lab/bin/break 23 22` (3 variantes).

**Travail demandé**
1. Reproduis dans les deux sens (trace → journaux, journaux → trace) et note ce que fait exactement Grafana (requête construite, source ouverte, erreur).
2. Compare la configuration servie par Grafana à celle de Git, puis à ce que contiennent vraiment les journaux (nom du champ, locataire).
3. Corrige par le code, attends le *sidecar* (ou le redémarrage de Grafana s'il le faut), et vérifie dans les deux sens.
4. Écris RB-233 « Plus de lien trace ↔ journaux ».

**Critères de réussite**
- [ ] La source Tempo envoie vers la source Loki d'un locataire applicatif qui existe ; la source Loki de MédiAgenda a un champ dérivé sur `trace_id` vers Tempo ; les journaux de dev portent `trace_id`.
- [ ] RB-233 publié ; la panne est close.

**Vérification** : `lab/bin/check 23 22`

<details><summary>Indice 1</summary>

```
admin@adm01:~$ curl -s -K <(printf 'header = "Authorization: Bearer %s"\n' "$(<~/.config/workbook/grafana-checks.token)") \
    https://grafana.apps.par1.medisphere.internal/api/frontend/settings | jq '.datasources[] | {name, uid, type}'
```
puis le `jsonData` des sources de type `tempo` et `loki`.
</details>

<details><summary>Indice 2</summary>

Un lien qui « ne renvoie rien » sans erreur interroge souvent le **mauvais locataire** : les journaux existent, mais pas chez celui-là. Un lien qui disparaît d'une ligne de journal, c'est un champ dérivé qui ne trouve plus son champ.
</details>

**Pour aller plus loin** : une seule source Tempo sert plusieurs équipes, donc plusieurs locataires Loki. Étudie les options : une source Loki multi-locataire (`X-Scope-OrgID: mediagenda|medidoc`, `multi_tenant_queries_enabled` côté Loki), une source Tempo par équipe, ou une requête personnalisée ; quelles conséquences pour le cloisonnement des données de santé ?

---

### M23-E23 — Astreinte : l'API est lente  `BF` `★★★★`

> **Ticket INC-5023** — *De : Nadia Roussel (responsable astreinte)*
> *(Le détail s'affiche à l'injection.)* L'API MédiAgenda de dev est lente, les tests de bout en bout de 9 h vont échouer. Et ce matin, la chaîne d'observabilité a aussi un problème. Trouve où passe le temps en croisant métriques, journaux, traces et profils, rétablis le service et l'observabilité, puis rédige le post-mortem.

**Objectifs pédagogiques**
- Mener un diagnostic de performance quand un des signaux manque : savoir ce que chaque signal peut et ne peut pas prouver (métriques par route, journaux avec durée, trace et ses spans de base de données, profil *on-CPU*, étranglement CPU).
- Rétablir le service ET l'observabilité, dans le bon ordre, par le code.
- Rédiger un post-mortem sans reproche, chronologie et preuves à l'appui.

**Prérequis** : M23-E19 à M23-E22 (runbooks), M23-E12 (trouver où passe le temps), M23-E14 (profils), M21 (métriques de MédiAgenda, cAdvisor) ; `lab/bin/check 23 19`, `20`, `21` et `22` verts avant l'injection.
**Durée indicative** : 2 h (rétablissement) + 45 min (post-mortem).

**Contexte technique** : l'injection combine **une** panne de M23-E19 à M23-E22 et **une** lenteur réelle de MédiAgenda en dev, dans un ordre qui fait que tu ne peux pas compter sur tous les signaux. Le témoin de trafic (`wb-pannes/trafic-agenda`) joue les utilisateurs ; ne l'arrête pas. La base de dev est le cluster CNPG `mediagenda-db` de l'espace `mediagenda-dev`. La lenteur ne détruit aucune donnée : sa correction n'en détruit pas non plus.

**Injection** : `lab/bin/break 23 23` (8 combinaisons).

**Travail demandé**
1. Prends l'astreinte : ouvre ton journal, note l'heure, préviens Julien et Nadia (canal de l'équipe), pose le premier point de situation dans les 15 min.
2. Délimite la lenteur par les **métriques** (quelles routes, depuis quand, quel percentile, CPU, étranglement, connexions) et les **journaux** (`duree_ms`, erreurs), même si les traces manquent.
3. Rétablis l'observabilité défaillante (runbooks RB-230 à RB-233), puis utilise traces et profils pour trouver **où** passe le temps. Note ce que chaque signal t'a appris et ce qu'il ne pouvait pas t'apprendre.
4. Corrige la cause de la lenteur à la racine, en accord avec Julien (c'est leur environnement), et vérifie : latence revenue, aucune panne active (`--annuler` pour clore).
5. Rédige le post-mortem `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-5023-<titre>.md` avec le modèle de l'équipe (`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`) : résumé, chronologie, causes (les deux), détection (pourquoi si tard, quel signal a manqué), actions avec responsables. Mets-y les requêtes PromQL, LogQL et TraceQL qui ont servi de preuve.

**Critères de réussite**
- [ ] p95 de la prise de rendez-vous et de toutes les routes `/api` de dev sous 300 ms, pas d'étranglement CPU notable, aucune span de base de données au-delà de 500 ms.
- [ ] Les contrôles de M23-E19 à M23-E22 sont verts ; aucune panne M23 n'est active.
- [ ] Post-mortem publié, avec chronologie, causes, détection, actions et preuves tirées des signaux.

**Vérification** : `lab/bin/check 23 23`

<details><summary>Indice 1</summary>

`histogram_quantile(0.95, sum by (le, route, methode) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-dev"}[5m])))` dit si toutes les routes ralentissent (ressource partagée : CPU, connexions) ou une seule (son chemin propre : une requête SQL, un appel). `container_cpu_cfs_throttled_periods_total` dit si le conteneur est bridé.
</details>

<details><summary>Indice 2</summary>

Un profil *on-CPU* normal pendant une lenteur veut dire que le temps est passé **à attendre** (base, réseau, verrou) ou que le processus n'a pas eu le CPU (étranglement). La trace, elle, montre la span qui attend ; PostgreSQL montre ce qu'il fait pendant ce temps (`pg_stat_activity`, `\dS+` sur la table concernée, `pg_trigger`).
</details>

---

### M23-E24 — Sous le capot : spans, contexte et OTLP  `LAB` `★★★★`

> **Ticket PLAT-2424** — *De : Karim Benali*
> Tu as réparé la chaîne quatre fois. Montre-moi maintenant que tu sais ce qui passe vraiment dedans : l'en-tête qui relie deux services, le message que reçoit un Collector, et ce qu'il y a dans un bloc de Tempo dans le compartiment. Un document que je pourrai donner aux nouveaux.

**Objectifs pédagogiques**
- Décoder le contexte W3C (`traceparent`, `tracestate`, `baggage`) et le relier aux identifiants des spans.
- Lire un message OTLP (ressource, portée, spans, identifiants, types, drapeaux) et connaître ses encodages.
- Suivre une span de l'application jusqu'au bloc Tempo, et lire un bloc vParquet avec `tempo-cli`.

**Prérequis** : M23-E01 à M23-E16 ; identifiants RGW de Tempo `~/.config/workbook/s3-tempo.env` (M23-E03 ; ils permettent d'écrire : ne t'en sers ici qu'en lecture) ; `uv` sur `adm01` (M12).
**Durée indicative** : 3 h.

**Contexte technique**
- Ressources fournies dans [`ressources/E24-capot/`](../ressources/E24-capot/) : `collecteur-local.yaml` (Collector qui écoute en local sur 24317/24318, affiche les spans et écrit le message OTLP reçu en JSON), `emettre.py` (deux « services » qui s'appellent en HTTP avec propagation W3C et exportent en OTLP/HTTP), `tempo-cli-local.sh` (copie **en lecture** d'un bloc de `tempo-k8s-par1` sur `adm01` et ouverture avec `tempo-cli`).
- Binaires sur `adm01`, épinglés et vérifiés comme d'habitude, dans `~/m23/e24/` : `otelcol-contrib` (même version que les Collectors du cluster) et `tempo-cli` (même version que Tempo, 3.1.1 ; il est aussi publié en image `grafana/tempo-cli`, dont on peut extraire le binaire). Rien n'est installé dans le cluster.
- Locataire de Tempo sans multi-locataire : `single-tenant`.

**Travail demandé**
1. Lance le Collector local, puis `emettre.py` (`uv run --with … python emettre.py`). Décode le `traceparent` affiché champ par champ ; retrouve chaque valeur dans la sortie du Collector et dans `otlp-recu.json` (`jq`). Qui est parent de qui ? Que valent les drapeaux, et pourquoi pas `01` ?
2. Dans `otlp-recu.json` : structure `resourceSpans` → `scopeSpans` → `spans`, types de spans, encodage des identifiants en JSON (hexadécimal) contre leur encodage en protobuf, attributs de ressource envoyés une seule fois par lot. Relance en OTLP/gRPC (adapte l'exportateur) et compare la taille sur le fil (`otelcol_receiver_*` du Collector local, ou `tcpdump -i lo`).
3. Suis une span réelle de MédiAgenda depuis l'application jusqu'au compartiment : processeur de lots du SDK, agent, passerelle (attente de décision), distributeur de Tempo, *live-store*, bloc. Mesure le délai entre la requête et le moment où la trace est trouvable par son identifiant, puis où elle est dans un bloc du compartiment.
4. Copie un bloc récent avec `tempo-cli-local.sh`, puis : `list blocks`, `view schema`, `list column` (identifiants de traces), `query trace-summary` sur une trace de MédiAgenda. Explique le rôle de `meta.json`, `data.parquet`, `bloom-0` et `index`, ce que sont les colonnes dédiées, et pourquoi une recherche par identifiant ne lit presque jamais `data.parquet` en entier.
5. Rédige `docs/observabilite/traces/sous-le-capot.md` avec tes sorties réelles (identifiants compris, aucune donnée de santé).

**Critères de réussite**
- [ ] Le livrable décompose un `traceparent` réel, décrit un message OTLP réel (`resourceSpans`, `scopeSpans`) et un bloc réel (identifiant UUID, `meta.json`, format vParquet) avec des sorties de `tempo-cli`.
- [ ] Il décrit le chemin d'une span jusqu'au bloc (live-store, WAL) avec les délais mesurés.
- [ ] Aucune écriture dans `tempo-k8s-par1` (les identifiants de `s3-tempo.env` ne servent qu'à lister et copier).

**Vérification** : `lab/bin/check 23 24`

<details><summary>Indice 1</summary>

La spécification W3C Trace Context (niveaux 1 et 2) définit `version-traceid-parentid-flags` ; le niveau 2 ajoute le drapeau *random*. La spécification OTLP (*OTLP/HTTP JSON encoding*) fixe la règle particulière des identifiants en JSON.
</details>

<details><summary>Indice 2</summary>

`tempo-cli … --backend local --bucket <dossier>` lit un dossier qui a la même forme que le compartiment : `<dossier>/<locataire>/<id-de-bloc>/…`. `list column` attend un nom de colonne (par exemple `TraceIDText`). Les délais de la chaîne : `OTEL_BSP_SCHEDULE_DELAY` du SDK, `batch.timeout` des Collectors, `decision_wait` de la passerelle, `max_block_duration` et `complete_block_timeout` du *live-store*.
</details>

**Pour aller plus loin** : ouvre `data.parquet` avec un lecteur Parquet générique (DuckDB, `parquet-tools`) et retrouve une span par ses colonnes ; lis la page *Dedicated attribute columns* de Tempo et propose les colonnes dédiées utiles à MédiSphère (avec la mesure avant/après d'une requête TraceQL).
