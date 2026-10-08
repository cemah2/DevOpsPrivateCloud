# MédiAgenda — API de prise de rendez-vous

API HTTP de l'équipe de Julien Petit : création, consultation et annulation de rendez-vous, calcul des créneaux libres d'un praticien. Python 3.13, FastAPI, PostgreSQL (psycopg 3), Valkey (cache).

Projet GitLab cible : `mediagenda/api`.

## Points d'accès

| Méthode et chemin | Rôle |
|---|---|
| `GET /sante` | Vivacité (*liveness*) : `{"statut":"ok","version":"…"}`. Ne contacte ni PostgreSQL ni Valkey : si la base tombe, le processus n'a pas à être redémarré. |
| `GET /pret` | Disponibilité (*readiness*) : 200 si PostgreSQL **et** Valkey répondent, 503 sinon (le détail est dans le corps). |
| `GET /metrics` | Métriques Prometheus : `mediagenda_http_requests_total{methode,route,code}`, `mediagenda_http_request_duration_seconds` (histogramme), `mediagenda_cache_total{resultat}`, plus les métriques du processus. |
| `GET /api/v1/rendez-vous?limite=100` | Liste triée par date. |
| `POST /api/v1/rendez-vous` | Création (201). 409 si le praticien a déjà un rendez-vous à cette heure, 422 si le corps est invalide. |
| `GET /api/v1/rendez-vous/{id}` | Détail (404 si absent). |
| `DELETE /api/v1/rendez-vous/{id}` | Annulation (204). |
| `GET /api/v1/creneaux?date=AAAA-MM-JJ[&praticien=…]` | Créneaux libres de 30 min (8 h-12 h et 14 h-18 h, heure de Paris). Résultat mis en cache dans Valkey (`MEDIAGENDA_CACHE_TTL`, 60 s), invalidé à chaque création ou annulation sur ce jour. Si Valkey est en panne, la réponse est calculée depuis la base (mode dégradé). |
| `GET /docs` | Documentation OpenAPI générée par FastAPI. |

Exemple de corps de création (la date **doit** porter son fuseau) :

```json
{"patient": "Jeanne Exemple", "praticien": "dr-morel", "debut": "2026-11-02T09:00:00+01:00", "duree_minutes": 30, "motif": "Suivi"}
```

## Configuration (variables d'environnement uniquement)

| Variable | Défaut | Rôle |
|---|---|---|
| `MEDIAGENDA_DB_URL` | *(obligatoire)* | URL PostgreSQL, ex. `postgresql://mediagenda:<MOT-DE-PASSE>@db.exemple:5432/mediagenda` |
| `MEDIAGENDA_VALKEY_URL` | *(obligatoire)* | URL Valkey, ex. `redis://valkey.exemple:6379/0` (`rediss://` pour TLS) |
| `MEDIAGENDA_LOG_LEVEL` | `INFO` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `MEDIAGENDA_LOG_FORMAT` | `json` | `json` (une ligne JSON par événement sur stdout) ou `texte` |
| `MEDIAGENDA_VERSION` | `dev` | Version affichée par `/sante` (à fixer par la chaîne de construction) |
| `MEDIAGENDA_PORT` | `8000` | Port d'écoute (toutes interfaces) |
| `MEDIAGENDA_FUSEAU` | `Europe/Paris` | Fuseau des créneaux |
| `MEDIAGENDA_CACHE_TTL` | `60` | Durée de vie du cache des créneaux, en secondes |
| `MEDIAGENDA_DELAI_ARRET` | `20` | Délai laissé aux requêtes en cours après SIGTERM, en secondes |
| `MEDIAGENDA_MIGRATIONS_DIR` | `migrations` | Répertoire des migrations (commande de migration seulement) |

Sans une variable obligatoire, le processus s'arrête aussitôt avec le code 2 et un message clair.

Chaque requête produit une ligne `mediagenda.acces` (méthode, chemin, route, code, durée). Les sondes `/sante`, `/pret` et `/metrics` sont journalisées au niveau `DEBUG` pour ne pas noyer le reste. Aucune donnée patient n'est journalisée.

## Lancer en local

Prérequis : `uv`, un PostgreSQL et un Valkey joignables (base créée en UTF-8 : `CREATE DATABASE mediagenda ENCODING 'UTF8' TEMPLATE template0;`).

```
admin@adm01:~/src/mediagenda-api$ uv sync --locked
admin@adm01:~/src/mediagenda-api$ export MEDIAGENDA_DB_URL='postgresql://mediagenda:<MOT-DE-PASSE>@127.0.0.1:5432/mediagenda'
admin@adm01:~/src/mediagenda-api$ export MEDIAGENDA_VALKEY_URL='redis://127.0.0.1:6379/0'
admin@adm01:~/src/mediagenda-api$ uv run python -m mediagenda.migrate --statut   # liste, sans rien appliquer
admin@adm01:~/src/mediagenda-api$ uv run python -m mediagenda.migrate            # applique V1, V2…
admin@adm01:~/src/mediagenda-api$ uv run python -m mediagenda                    # http://127.0.0.1:8000
```

## Migrations

Fichiers SQL versionnés dans `migrations/`, nommés comme pour Flyway : `V1__init.sql`, `V2__index.sql`, puis `V3__…`. La commande `python -m mediagenda.migrate` :

- applique, dans l'ordre numérique, celles qui ne figurent pas dans la table `mediagenda_historique_schema` ;
- s'arrête si un fichier déjà appliqué a été modifié (empreinte SHA-256) : on ne réécrit pas une migration, on en ajoute une ;
- applique chaque fichier dans une transaction et prend un verrou consultatif PostgreSQL : deux exécutions simultanées (deux réplicas qui démarrent) ne se marchent pas dessus.

Le compte utilisé pour migrer a besoin du droit `CREATE` sur le schéma ; le compte de l'application, seulement de `SELECT, INSERT, UPDATE, DELETE`. Rien n'oblige à utiliser le même.

## Arrêt propre

uvicorn intercepte SIGTERM : il cesse d'accepter des connexions, laisse finir les requêtes en cours (au plus `MEDIAGENDA_DELAI_ARRET` secondes), puis ferme les connexions PostgreSQL et Valkey. Pour que le signal arrive, le processus Python doit le recevoir directement (PID 1 du conteneur, ou processus suivi par le superviseur), pas à travers un `sh -c` qui ne le relaie pas.

## Tests

```
admin@adm01:~/src/mediagenda-api$ uv run pytest            # sans base : dépôt et cache simulés
admin@adm01:~/src/mediagenda-api$ uv run ruff check . && uv run ruff format --check .
```

Les tests marqués `integration` demandent un vrai PostgreSQL et un vrai Valkey, et sont sautés par défaut :

```
admin@adm01:~/src/mediagenda-api$ MEDIAGENDA_TEST_DB_URL='postgresql://…/mediagenda_test' \
  MEDIAGENDA_TEST_VALKEY_URL='redis://127.0.0.1:6379/15' uv run pytest -m integration
```

> ⚠️ **Attention** : le test d'intégration vide la base désignée (`DROP SCHEMA public CASCADE`). Donne-lui une base dédiée, jamais celle d'un environnement.

## Structure

```
src/mediagenda/
  __main__.py   point d'entrée (uvicorn)
  app.py        routes, mesure, journal d'accès, calcul des créneaux
  config.py     lecture des variables d'environnement
  depot.py      interface Depot + implémentation PostgreSQL (pool psycopg)
  cache.py      interface Cache + implémentation Valkey
  modeles.py    schémas Pydantic
  journal.py    format JSON des journaux
  migrate.py    migrations SQL versionnées
migrations/     V1__init.sql, V2__index.sql
tests/          pytest (doublures en mémoire dans conftest.py)
```
