# RB-121 — Restaurer la base PostgreSQL d'une pile Compose

| | |
|---|---|
| **Version** | 1.0 — 2026-10 (M12-E29, PLAT-1329) |
| **Périmètre** | bases PostgreSQL conteneurisées sauvegardées par `wb-backup-conteneurs` (PBS `par1/conteneurs`) |
| **Durée mesurée** | 9 min de bout en bout sur la base de recette de MédiAgenda (voir `tests/restauration-conteneurs.md`) |

## Quand l'utiliser

- Données supprimées ou corrompues **dans la base** (erreur humaine, migration ratée) : ce runbook.
- VM `ctr01` perdue ou disque corrompu : restaurer d'abord la VM (RB-002, sauvegarde `lab-nuit`), puis, si la base de la VM est plus ancienne que l'export de la nuit, ce runbook.
- Le conteneur ne démarre plus mais les données sont saines : RB-120 (ce n'est pas une restauration).

## Préalables

- Accès `admin` à l'hôte et `sudo` ; clé `/etc/wb-backup/pbs-<hôte>.key` et `pbs-<hôte>.env` présentes (sinon : Vault `critique`, `vault_pbs_cle_<hôte>`).
- Décision écrite (ticket) : quel instantané (date), qui valide la bascule (Julien pour la recette de MédiAgenda).

## 1. Restaurer à côté (sans toucher la base en service)

```
admin@ctr01:~$ sudo bash -c 'set -a; . /etc/wb-backup/pbs-ctr01.env; set +a;
    proxmox-backup-client snapshot list --ns par1/conteneurs host/ctr01'
admin@ctr01:~$ sudo bash -c 'set -a; . /etc/wb-backup/pbs-ctr01.env; set +a; install -d -m 700 /root/restau;
    proxmox-backup-client restore --ns par1/conteneurs "host/ctr01/<HORODATAGE>" bases.pxar /root/restau --keyfile /etc/wb-backup/pbs-ctr01.key'
admin@ctr01:~$ docker network create --internal restau-reseau
admin@ctr01:~$ docker volume create restau-donnees
admin@ctr01:~$ docker run -d --name restau-db --network restau-reseau -v restau-donnees:/var/lib/postgresql \
    -e POSTGRES_USER=mediagenda -e POSTGRES_DB=mediagenda -e POSTGRES_PASSWORD="$(openssl rand -hex 16)" \
    docker.io/library/postgres:18-trixie
admin@ctr01:~$ until docker exec restau-db pg_isready -U mediagenda -d mediagenda; do sleep 1; done
admin@ctr01:~$ sudo cat /root/restau/mediagenda-db-1-mediagenda.dump | docker exec -i restau-db pg_restore -U mediagenda -d mediagenda --no-owner --exit-on-error
```

<HORODATAGE> : colonne « snapshot » de la liste (forme `AAAA-MM-JJTHH:MM:SSZ`). Même version majeure de PostgreSQL que la base sauvegardée (fichier `.version` de l'archive).

## 2. Vérifier

```
admin@ctr01:~$ REQ="SELECT count(*), md5(string_agg(id::text || debut::text || praticien, ',' ORDER BY id)) FROM rendez_vous"
admin@ctr01:~$ docker exec restau-db psql -U mediagenda -d mediagenda -Atc "$REQ"
```

Comparer avec la même requête sur la base en service (si elle est lisible) ou avec ce que le demandeur attend (rendez-vous de telle date présents).

## 3. Basculer (seulement si la base en service doit être remplacée)

1. Annoncer la coupure ; `docker compose stop api api-b migrations` (plus aucune écriture).
2. Exporter la base en service **avant** de l'écraser (preuve, retour arrière) : `docker exec mediagenda-db-1 pg_dump -U mediagenda -d mediagenda -Fc > /root/avant-restau-$(date +%F-%H%M).dump`.
3. Restaurer dans la base en service : `docker exec -i mediagenda-db-1 pg_restore -U mediagenda -d mediagenda --clean --if-exists --no-owner --exit-on-error < /root/restau/<FICHIER>.dump`.
4. `docker compose up -d --wait` ; `/pret` répond 200 ; requête de l'étape 2 identique.

**Retour arrière** : même étape 3 avec le fichier `avant-restau-….dump`.

## 4. Nettoyer

```
admin@ctr01:~$ docker rm -f restau-db && docker volume rm restau-donnees && docker network rm restau-reseau
admin@ctr01:~$ sudo shred -u /root/restau/* && sudo rmdir /root/restau
```

Les fichiers restaurés sont des **données de santé** en clair : ils ne restent jamais sur l'hôte après l'intervention.
