# Journaux, ressources et santé des conteneurs

> M12-E18 (PLAT-1318). Décisions valables pour `ctr01` (Docker), `ctr02`/`ctr03` (Podman) et `runner02`.

## Journaux

| Pilote | Où vont les lignes | `docker logs` | Rotation | Choix MédiSphère |
|---|---|---|---|---|
| `json-file` | `/var/lib/docker/containers/<id>/<id>-json.log` | oui | `max-size`/`max-file` (sinon **aucune**) | **par défaut** (daemon.json) : 10 Mo × 3, compressés ; format lu tel quel par les collecteurs (M22) |
| `local` | fichiers internes compressés | oui | 20 Mo × 5 par défaut | non retenu : illisible hors de Docker |
| `journald` | journal de l'hôte (champs `CONTAINER_NAME`, `CONTAINER_ID`…) | oui | celle de journald (`SystemMaxUse`) | conteneurs « système » d'un hôte qui centralise déjà journald |

Podman (`ctr02`, `ctr03`) : journald par défaut (`containers.conf.d/50-medisphere.conf`, M12-E02) : `journalctl --user -u <unité>.service`.

Règle des applications : **une ligne JSON par événement sur la sortie standard**, rien dans des fichiers du conteneur (facteur XI). Jamais de donnée de santé ni d'identifiant de patient dans un journal.

## Ressources (bornes par défaut, à ajuster sur mesure)

| Service | Mémoire | CPU | Processus | Remarque |
|---|---|---|---|---|
| API MédiAgenda | 256 Mo | 1 | 128 | mesuré ≈ 80 Mo au repos |
| PostgreSQL de recette | 512 Mo | 1 | 256 | arrêt : 30 s de délai de grâce |
| Valkey (cache) | 128 Mo | 0,5 | 64 | `--maxmemory 96mb --maxmemory-policy allkeys-lru` : le cache évince avant que le noyau ne tue |

Un conteneur qui dépasse sa limite mémoire est tué par le noyau (OOM du **cgroup**, code 137, `OOMKilled=true`) ; un conteneur qui dépasse son quota CPU est **ralenti**, jamais tué ; au-delà de `pids.max`, `fork` échoue.

## Santé

- Docker : `HEALTHCHECK` (image) ou `healthcheck:` (Compose) ; l'état `unhealthy` est **informatif** — Docker ne redémarre pas un conteneur malade (seule la sortie du processus déclenche `restart:`). Il sert à `depends_on: condition: service_healthy`, à `docker compose up --wait` et à la supervision (M12-E28).
- Podman/Quadlet : `HealthOnFailure=kill` + `Restart=on-failure` : un conteneur malade est tué et systemd le relance (dans la limite `StartLimitBurst`).
- La sonde teste la **vivacité** (le processus répond) et ne dépend jamais d'un service tiers.
