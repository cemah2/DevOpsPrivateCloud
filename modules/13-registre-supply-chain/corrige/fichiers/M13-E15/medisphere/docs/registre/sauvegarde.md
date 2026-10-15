# Sauvegarde du registre (Harbor)

> Modèle de corrigé (M13-E15). Rôle Ansible `sauvegarde_harbor`, script `wb-backup-harbor.sh`, RB-131.

## Ce qui est sauvegardé

| Élément | Où sur `reg01` | Comment | Archive PBS |
|---|---|---|---|
| Base de Harbor (`registry` : projets, membres, robots, politiques, artefacts, étiquettes, accessoires, analyses, journal d'audit) | conteneur `harbor-db` (`/data/database`) | `pg_dump -Fc` **dans** le conteneur, contrôlé par `pg_restore --list` | `base.pxar` |
| Clés | `/data/secret` (`keys/secretkey`, `core/private_key.pem`, `cert/`, `registry/root.crt`) | copie de fichiers | `secret.pxar` |
| Configuration | `/opt/harbor/harbor.yml` (rendu par le rôle `harbor`, contient deux secrets) | copie | `config.pxar` |
| Blobs et manifestes | `/data/registry` | copie de fichiers (dédupliquée par PBS) | `registre.pxar` |

Destination : `pbs01`, datastore `ds-lab`, espace de noms `par1/registre`, sauvegarde `host/reg01`, chiffrée côté client (clé en Vault `critique`). Chaque nuit à 01:40 (`wb-backup-harbor.timer`), `OnFailure=ms-alerte@%n.service`.

## Ce qui ne l'est pas, et pourquoi

| Élément | Raison |
|---|---|
| `/data/database` (fichiers PostgreSQL) | incohérents à chaud ; le vidage les remplace |
| `/data/redis` (Valkey) | cache et files de tâches éphémères |
| `/data/trivy-adapter` | base de Trivy et rapports en cache, retéléchargés et recalculés |
| `/data/job_logs` | journaux des tâches (utile, pas indispensable) |
| Images Docker de Harbor, `common/config`, `docker-compose.yml` | réinstallés et régénérés par le rôle `harbor` (`prepare`) |
| Certificat TLS de `/etc/harbor/tls` | réémis par ACME (step-ca) |
| Sauvegarde de VM (`lab-nuit`) | le disque de données de 200 Go en est exclu (`sauvegarde = false`, M13-E02) |

## Cohérence

1. La **base d'abord**, les blobs ensuite : un blob poussé entre les deux est en trop (sans effet, le ramasse-miettes le retirera) ; l'inverse donnerait une base qui référence des blobs absents.
2. **Jamais pendant le ramasse-miettes** (il supprime des blobs que la base vient de lâcher) : le script refuse de tourner si un GC est en cours ; le GC n'est pas planifié dans la fenêtre 01:30-03:00.
3. `secretkey` voyage **avec** la base : sans elle, les identifiants chiffrés en base (endpoints de réplication et des caches) sont illisibles après restauration.

## Restauration

RB-131. Essai réalisé sur `reg02` : `tests/restauration-harbor.md`.
