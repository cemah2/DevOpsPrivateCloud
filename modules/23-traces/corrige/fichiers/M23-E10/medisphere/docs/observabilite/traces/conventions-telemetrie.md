# Conventions de télémétrie (traces)

> `plateforme/medisphere`, `docs/observabilite/traces/conventions-telemetrie.md` — version M23-E10 (SEC-2410) ; créée en M23-E04, complétée en M23-E06 (MédiDoc).

## Ressource (qui émet)

| Attribut | Valeur | Posé par |
|---|---|---|
| `service.name` | `mediagenda-api`, `medidoc` | `OTEL_SERVICE_NAME` (component `telemetrie` du dépôt `…/deploiement`) |
| `service.namespace` | `medisphere` | `OTEL_RESOURCE_ATTRIBUTES` |
| `deployment.environment.name` | `dev`, `recette`, `prod` | `OTEL_RESOURCE_ATTRIBUTES`, lu sur l'étiquette `medisphere.internal/environnement` du pod |
| `service.version` | `vX.Y.Z` (la version livrée) | le code (`MEDIAGENDA_VERSION`) |
| `k8s.namespace.name`, `k8s.pod.name`, `k8s.deployment.name`, `k8s.node.name`, `k8s.cluster.name`, `medisphere.equipe` | — | l'agent Collector (`k8sattributes`, `resource/cluster`) : **jamais** l'application |

## Variables d'environnement (standard OpenTelemetry, aucune variable maison)

`OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-agent-collector.traces.svc.cluster.local:4317`, `OTEL_TRACES_SAMPLER`, `OTEL_PROPAGATORS=tracecontext,baggage`, `OTEL_SEMCONV_STABILITY_OPT_IN=http,database` (Python : noms stables des conventions HTTP et base de données). `OTEL_SDK_DISABLED=true` coupe tout.

**Protocoles d'export** (inventaire, à tenir à jour) : MédiAgenda et MédiDoc en OTLP/**gRPC** vers l'agent du nœud (4317) ; l'auto-instrumentation Python (essai M23-E07) en OTLP/**HTTP** (4318) ; les émetteurs hors cluster par 10.10.41.63 (M23-E16). Le récepteur de l'agent accepte donc **les deux** protocoles.

## Spans

- **Nommage** : spans automatiques selon les conventions sémantiques (`POST /api/v1/rendez-vous` : méthode + **modèle** de route, jamais le chemin réel ; `SELECT mediagenda` ; `GET` pour Valkey). Spans métier : `<service>.<objet>.<verbe>` en minuscules (`mediagenda.rendez_vous.creer`, `mediagenda.creneaux.calculer`, `mediagenda.cache.invalider`).
- **Attributs métier** : préfixe du service (`mediagenda.praticien`, `mediagenda.rendez_vous.id`, `mediagenda.cache.resultat`, `mediagenda.creneaux.libres`, `mediagenda.piece_jointe.taille` ; `medidoc.document.id`, `medidoc.document.taille`). Pas d'attribut à cardinalité « illimitée » sans besoin d'enquête.
- **Statut** : `ERROR` seulement pour une défaillance **du service** (5xx, dépendance en panne). Un 4xx (conflit, introuvable) n'est pas une erreur de la span serveur ; un conflit de créneau est un **événement** (`mediagenda.conflit_creneau`).
- **Sondes** (`/sante`, `/pret`, `/metrics`) : jamais tracées.

## Attributs interdits (données de santé, RGPD, HDS)

Jamais en attribut, en événement ni en nom de span : nom, prénom, date de naissance, NIR, courriel, téléphone du patient ; motif du rendez-vous ; contenu ou nom d'un document ; valeur d'un paramètre SQL ; jeton, mot de passe, en-tête `Authorization` ; toute entrée de *baggage* hors de la liste blanche (`medisphere.canal`). Les instrumentations sont réglées en conséquence (pas de capture des paramètres SQL, pas de capture d'en-têtes). Une fuite se corrige **dans le code** ; le masquage du Collector (M23-E10) n'est qu'un filet.

## Filet du Collector (M23-E10)

Appliqué par `otel-agent` à toute span venue d'un pod du cluster, avant de quitter le nœud (`plateforme/observabilite/otel/otel-agent.yaml`) :

| Processeur | Effet | Pourquoi |
|---|---|---|
| `filter/sondes` | supprime les spans de `/sante`, `/pret`, `/metrics`, `/healthz`, `/readyz` (conventions stables `url.path` et anciennes `http.target`) | volume sans valeur, applications auto-instrumentées (M23-E07) |
| `transform/masquage` | supprime `url.query` ; coupe `?…` de `url.full` et `http.target` ; remplace les littéraux `'…'` de `db.query.text` et `db.statement` par `'?'` ; supprime tous les `http.request.header.*` et `http.response.header.*` | paramètres d'URL (nom de fichier de pièce jointe, M23-E06), requêtes non paramétrées, en-têtes d'authentification |
| `redaction/donnees-sante` | remplace par `****` toute valeur d'attribut qui ressemble à un NIR ou à une adresse de courriel ; `redaction.masked.count` sur la span | filet par motif, quel que soit l'attribut |

Ce qui n'est **pas** couvert : les noms de span (une application qui mettrait un nom de patient dans un nom de span), les événements et leurs attributs (`exception.message` peut citer une valeur), les ressources. Toute fuite constatée (`redaction.masked.count` > 0, requête TraceQL du check de M23-E10) ouvre un ticket `SEC-` à l'équipe de l'application : la correction est dans le code.

## Contrôles réguliers (TraceQL, dernière heure)

```
{ span.url.query != nil }
{ span.url.path =~ "/(sante|pret|metrics|healthz|readyz)" }
{ span.db.query.text =~ ".*'[^?'][^']*'.*" }
{ span.http.request.header.authorization != nil }
{ span.redaction.masked.count > 0 }
```
Chacune doit être vide.
