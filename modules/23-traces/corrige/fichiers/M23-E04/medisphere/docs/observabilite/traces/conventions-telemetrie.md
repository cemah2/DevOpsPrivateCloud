# Conventions de télémétrie (traces)

> `plateforme/medisphere`, `docs/observabilite/traces/conventions-telemetrie.md` — version M23-E04 (DEV-2404). Complétée en M23-E06 (MédiDoc) et M23-E10 (attributs interdits, masquage).

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

## Spans

- **Nommage** : spans automatiques selon les conventions sémantiques (`POST /api/v1/rendez-vous` : méthode + **modèle** de route, jamais le chemin réel ; `SELECT mediagenda` ; `GET` pour Valkey). Spans métier : `<service>.<objet>.<verbe>` en minuscules (`mediagenda.rendez_vous.creer`, `mediagenda.creneaux.calculer`, `mediagenda.cache.invalider`).
- **Attributs métier** : préfixe du service (`mediagenda.praticien`, `mediagenda.rendez_vous.id`, `mediagenda.cache.resultat`, `mediagenda.creneaux.libres`). Pas d'attribut à cardinalité « illimitée » sans besoin d'enquête.
- **Statut** : `ERROR` seulement pour une défaillance **du service** (5xx, dépendance en panne). Un 4xx (conflit, introuvable) n'est pas une erreur de la span serveur ; un conflit de créneau est un **événement** (`mediagenda.conflit_creneau`).
- **Sondes** (`/sante`, `/pret`, `/metrics`) : jamais tracées.

## Interdits (données de santé, RGPD, HDS)

Jamais en attribut, en événement ni en nom de span : nom, prénom, date de naissance, NIR, courriel, téléphone du patient ; motif du rendez-vous ; contenu ou nom d'un document ; valeur d'un paramètre SQL ; jeton, mot de passe, en-tête `Authorization`. Les instrumentations sont réglées en conséquence (pas de capture des paramètres SQL, pas de capture d'en-têtes). Une fuite se corrige **dans le code** ; le masquage du Collector (M23-E10) n'est qu'un filet.
