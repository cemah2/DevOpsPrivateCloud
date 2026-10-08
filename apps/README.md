# Applications métier de MédiSphère

Ce répertoire contient le code des quatre applications qui servent de **charges de travail** à partir du module 12 (conteneurs) et jusqu'aux finaux. Le code est volontairement court et simple, mais propre et testé : l'objet du workbook n'est pas le développement, c'est tout ce qui permet de construire, livrer, exécuter et observer ces applications.

Tu écriras toi-même, au fil des modules, les Containerfile, les manifestes Kubernetes, les charts et les pipelines. **Ce répertoire n'en contient aucun**, et c'est voulu.

| Application | Répertoire | Projet GitLab cible | Langage | Port | Dépendances |
|---|---|---|---|---|---|
| **MédiAgenda** (prise de rendez-vous) | [`mediagenda/`](mediagenda/) | `mediagenda/api` | Python 3.13, FastAPI, uv | 8000 | PostgreSQL, Valkey |
| **MédiDoc** (documents patients) | [`medidoc/`](medidoc/) | `medidoc/medidoc` | Go 1.26 | 8080 | Stockage S3 (SeaweedFS ou Ceph RGW) |
| **MédiNotif** (notifications SMS et mail) | [`medinotif/`](medinotif/) | `medinotif/worker` | Python 3.13, uv | 9100 (métriques) | RabbitMQ (Kafka au module 27) |
| **Legacy-RDV** (ancienne prise de rendez-vous) | [`legacy-rdv/`](legacy-rdv/) | `legacy/legacy-rdv` | PHP 8.4 | 80 (Apache) | MariaDB |

Au module 12, tu pousseras chaque répertoire dans son propre projet GitLab sur `git01` (un dépôt par application, à la racine du projet).

## Ce que les trois applications « modernes » ont en commun

C'est le contrat sur lequel s'appuient les modules suivants :

| Sujet | MédiAgenda | MédiDoc | MédiNotif |
|---|---|---|---|
| Configuration | variables `MEDIAGENDA_*` | variables `MEDIDOC_*` et `AWS_*` | variables `MEDINOTIF_*` |
| Vivacité (*liveness*) | `GET /sante` | `GET /healthz` | serveur de métriques (`:9100`) |
| Disponibilité (*readiness*) | `GET /pret` (PostgreSQL + Valkey) | `GET /readyz` (HeadBucket) | sans objet (pas de trafic entrant) |
| Métriques Prometheus | `GET /metrics` | `GET /metrics` | `:9100/metrics` |
| Journaux | JSON sur stdout | JSON sur stdout (`slog`) | JSON sur stdout |
| Arrêt sur SIGTERM | fin des requêtes en cours (20 s) | fin des requêtes en cours (20 s) | fin du message en cours |
| Version | `MEDIAGENDA_VERSION` | `-ldflags -X main.version=…` ou `MEDIDOC_VERSION` | `MEDINOTIF_VERSION` |
| Secrets | aucun dans le code ; tout vient de l'environnement | | |
| Données personnelles dans les journaux | jamais (RGPD, HDS) | | |

**Legacy-RDV** fait exactement l'inverse sur presque chaque ligne : c'est son rôle. Son [README](legacy-rdv/README.md) liste ce qui rendra sa migration difficile.

## Variables d'environnement

### MédiAgenda

| Variable | Défaut |
|---|---|
| `MEDIAGENDA_DB_URL` | obligatoire (`postgresql://…`) |
| `MEDIAGENDA_VALKEY_URL` | obligatoire (`redis://…` ou `rediss://…`) |
| `MEDIAGENDA_LOG_LEVEL` / `MEDIAGENDA_LOG_FORMAT` | `INFO` / `json` |
| `MEDIAGENDA_VERSION` | `dev` |
| `MEDIAGENDA_PORT`, `MEDIAGENDA_CACHE_TTL`, `MEDIAGENDA_DELAI_ARRET`, `MEDIAGENDA_FUSEAU` | `8000`, `60`, `20`, `Europe/Paris` |

### MédiDoc

| Variable | Défaut |
|---|---|
| `MEDIDOC_S3_ENDPOINT`, `MEDIDOC_S3_BUCKET` | obligatoires |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | obligatoires (lues par le SDK AWS) |
| `MEDIDOC_S3_REGION` | `us-east-1` |
| `MEDIDOC_CA_FILE` | vide (CA ajoutée à celles du système) |
| `MEDIDOC_MAX_MB`, `MEDIDOC_PORT`, `MEDIDOC_LOG_LEVEL`, `MEDIDOC_VERSION` | `10`, `8080`, `info`, version compilée |

### MédiNotif

| Variable | Défaut |
|---|---|
| `MEDINOTIF_BACKEND` | `rabbitmq` (`stdin` pour les tests) |
| `MEDINOTIF_AMQP_URL` | obligatoire avec `rabbitmq` |
| `MEDINOTIF_FILE`, `MEDINOTIF_TYPE_FILE`, `MEDINOTIF_DECLARER_FILE` | `notifications`, `quorum`, `1` |
| `MEDINOTIF_PORT_METRIQUES`, `MEDINOTIF_LOG_LEVEL`, `MEDINOTIF_LOG_FORMAT` | `9100`, `INFO`, `json` |
| `MEDINOTIF_DELAI_ENVOI_MS`, `MEDINOTIF_VERSION` | `50`, `dev` |

## Lancer les tests en local

Aucun test par défaut n'a besoin d'une base, d'un cache, d'un courtier ou d'un S3 : les dépendances sont simulées.

```
admin@adm01:~/DevOpsPrivateCloud/apps/mediagenda$ uv sync --locked && uv run pytest && uv run ruff check . && uv run ruff format --check .
admin@adm01:~/DevOpsPrivateCloud/apps/medinotif$  uv sync --locked && uv run pytest && uv run ruff check . && uv run ruff format --check .
admin@adm01:~/DevOpsPrivateCloud/apps/medidoc$    go vet ./... && go test ./...
admin@adm01:~/DevOpsPrivateCloud/apps/legacy-rdv$ for f in $(find . -name '*.php'); do php -l "$f"; done
```

Prérequis : `uv` (0.11 ou plus récent, il installe Python 3.13 si besoin), Go 1.26, PHP 8.4 en ligne de commande (`php8.4-cli`) pour la vérification de syntaxe.

Les tests marqués `integration` (MédiAgenda, MédiNotif) visent de vrais services et sont sautés par défaut ; leur README dit comment les lancer.

## Versions des dépendances

Les projets Python déclarent des bornes (`>=x.y,<majeure suivante`) dans `pyproject.toml` et figent les versions exactes dans `uv.lock` (`uv sync --locked` refuse un verrou désynchronisé). MédiDoc fige les siennes dans `go.mod` et `go.sum`. Monter une version est un changement comme un autre : une MR, des tests verts.

| Projet | Dépendances principales (versions du verrou) |
|---|---|
| MédiAgenda | FastAPI 0.142, uvicorn 0.54, psycopg 3.3 (+ psycopg-pool 3.3), redis 8.1, prometheus-client 0.26 |
| MédiNotif | pika 1.4, prometheus-client 0.26 |
| MédiDoc | aws-sdk-go-v2 1.47 (service/s3 1.114), prometheus/client_golang 1.24 |
