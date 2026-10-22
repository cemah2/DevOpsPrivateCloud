# Auto-instrumentation par l'opérateur : essai et décision

> `plateforme/medisphere`, `docs/observabilite/traces/auto-instrumentation.md` — M23-E07 (PLAT-2407). Essai du JJ/MM/AAAA dans `wb-essais` (copie `mediagenda-auto`, `Instrumentation/python-essai`, image `autoinstrumentation-python:0.66b1`). Valeurs mesurées sur le lab : remplace les miennes par les tiennes.

## Ce qu'on a comparé

| Critère | Dans le code (M23-E04, `mediagenda-api` en dev) | Auto-instrumentation (`mediagenda-essai-auto`) |
|---|---|---|
| Spans obtenues pour `POST /api/v1/rendez-vous` | serveur + `mediagenda.rendez_vous.creer` + `INSERT` + `mediagenda.cache.invalider` + 2 × `DEL` | serveur + `INSERT` + 2 × `DEL` (aucune span métier) |
| Attributs métier (`mediagenda.praticien`, `mediagenda.cache.resultat`…) | oui | non : l'outil ne connaît pas le métier |
| Exclusion des sondes | dans le code (`excluded_urls`) | par variable (`OTEL_PYTHON_EXCLUDED_URLS`) |
| Protocole d'export | OTLP gRPC 4317 | OTLP HTTP 4318 (défaut de l'image Python) |
| Démarrage du pod | inchangé | + conteneur d'initialisation (copie ≈ 40-60 Mo dans un `emptyDir`), quelques secondes de plus |
| Mémoire du conteneur `api` au repos | ≈ 95 Mio | ≈ 120 Mio (toutes les instrumentations disponibles sont chargées) |
| Versions | figées dans `uv.lock`, testées en CI | celles de l'image de l'opérateur, découvertes au redémarrage du pod |
| Ce qui casse la trace | une MR relue | une montée de version de l'opérateur, un conflit de version avec une dépendance de l'application |

## Double instrumentation

Image instrumentée (M23-E04) + annotation : le SDK de l'opérateur démarre d'abord (`sitecustomize`) et installe son fournisseur ; celui du code est refusé (« Overriding of current TracerProvider is not allowed ») ; FastAPI est instrumenté deux fois selon l'ordre de chargement (spans serveur en double, ou une seule et des attributs incohérents). Constat sur le lab : _à compléter_. Règle : **jamais** l'annotation sur une application qui embarque déjà le SDK.

## Décision

L'instrumentation **dans le code** reste la règle pour MédiAgenda et MédiDoc (ADR-0230, M23-E17) : spans métier, attributs maîtrisés (données de santé), versions testées en CI, pas de webhook de mutation sur les espaces applicatifs de production. L'auto-instrumentation est admise pour un **diagnostic ponctuel** d'une application tierce ou ancienne, dans `wb-essais`, le temps d'une enquête. Go : l'opérateur sait injecter un agent eBPF (option désactivée par défaut dans le chart, conteneur **privilégié**) : écarté (Pod Security `restricted`), OBI/Beyla en veille.

## Nettoyage

`kubectl -n wb-essais delete -f essais/` (copie, base et cache jetables, `Instrumentation`), `kubectl -n wb-essais delete secret postgresql-essai-auto`.
