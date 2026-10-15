# RB-120 — Un conteneur redémarre en boucle

| | |
|---|---|
| **Version** | 1.0 (M12-E23, ticket PLAT-1323) — section « le conteneur s'arrête dès le démarrage » ajoutée en M12-E35 |
| **Propriétaire** | Équipe Plateforme (relecture : Nadia Roussel, astreinte) |
| **Périmètre** | conteneurs Docker (`ctr01`, `runner02`) et Podman/Quadlet (`ctr02`, `ctr03`) ; pas Kubernetes (RB-14x) |
| **Durée visée** | diagnostic en 15 min, rétablissement ou escalade en 30 min |
| **Droits** | `admin` (sudo) sur l'hôte ; compte `app` (session `machinectl`) pour Podman sans privilège |

## Quand l'appliquer

- `docker ps` montre `Restarting (N) X seconds ago`, ou un `RestartCount` qui monte ; `docker compose ps` montre un service qui ne reste jamais `healthy` ;
- une unité Quadlet passe en `activating (auto-restart)` ou `failed` avec `start request repeated too quickly` ;
- la sonde `ms-verif-conteneurs` (M12-E28) remonte `redemarrage` ou `etat … restarting`.

## Règles pendant l'intervention

1. **Lire avant d'agir.** Aucune commande qui détruit un état (`docker rm -f`, `docker compose down -v`, `podman system reset`, `docker volume prune`) avant d'avoir noté le code de sortie, les journaux et la configuration.
2. **Ne pas désactiver la politique de redémarrage « pour voir »** sur un service avec données ; geler plutôt le service (étape 4) et garder les traces.
3. **Pas de `exec` ni de modification à chaud** dans un conteneur de production : on corrige la source (image, `compose.yaml`, unité Quadlet, rôle Ansible), puis on redéploie.
4. Toute action est notée dans le journal de l'incident (`docs/socle/journal/`), avec l'heure.

## 1. Constater (5 min)

Docker (Compose) :

```
admin@ctr01:~$ docker ps -a --filter name=<NOM> --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
admin@ctr01:~$ docker inspect -f 'statut={{.State.Status}} code={{.State.ExitCode}} oom={{.State.OOMKilled}} redemarrages={{.RestartCount}} politique={{.HostConfig.RestartPolicy.Name}} debut={{.State.StartedAt}} fin={{.State.FinishedAt}} erreur={{.State.Error}}' <NOM>
admin@ctr01:~$ docker events --since 30m --filter container=<NOM> --format '{{.Time}} {{.Action}} {{.Actor.Attributes.exitCode}}'
admin@ctr01:~$ docker logs --tail 50 --timestamps <NOM>
```

Podman sans privilège (Quadlet), dans une session du compte `app` (`sudo machinectl shell app@`) :

```
app@ctr02:~$ systemctl --user status <UNITÉ>.service --no-pager
app@ctr02:~$ journalctl --user -u <UNITÉ>.service --since -30min --no-pager | tail -50
app@ctr02:~$ podman ps -a --filter name=<NOM> --format '{{.Names}} {{.Status}} {{.ExitCode}}'
app@ctr02:~$ podman inspect -f '{{.State.ExitCode}} {{.State.OOMKilled}} {{.State.Health.Status}}' <NOM>
```

Note : le **code de sortie**, la **fréquence** des redémarrages (le délai double à chaque échec côté Docker, de 100 ms jusqu'à 1 min ; côté systemd, `RestartSec` puis `StartLimitBurst`), l'**heure du premier échec** et ce qui a changé juste avant (déploiement, mise à jour d'image, changement de configuration, redémarrage de l'hôte).

## 2. Lire le code de sortie (5 min)

| Code | Signification | Piste |
|---|---|---|
| 0 | le processus principal s'est **terminé normalement** | ce n'est pas un service (commande ponctuelle lancée avec `restart: always`), ou il se met en arrière-plan (démon qui « fork ») : le PID 1 doit rester au premier plan |
| 1, 2, autre < 126 | l'application a refusé de démarrer | ses journaux : configuration absente ou invalide (MédiAgenda sort en 2 sans `MEDIAGENDA_DB_URL`), dépendance injoignable, migration en échec |
| 126 / 127 | commande non exécutable / introuvable | `ENTRYPOINT`/`CMD` de l'image et surcharges du `compose.yaml` |
| 137 (128 + 9) | tué par **SIGKILL** | `oom=true` : limite mémoire ; sinon `docker stop`/`kill`, délai de grâce trop court, `HealthOnFailure=kill` (Podman) — section « tué sans prévenir » ci-dessous |
| 143 (128 + 15) | terminé par **SIGTERM** | arrêt demandé (déploiement, `systemctl stop`) : normal s'il est isolé ; en boucle, un superviseur arrête le conteneur (sonde, systemd) |
| 139 (128 + 11) | erreur de segmentation | binaire de mauvaise architecture ou bibliothèque incompatible ; escalade aux développeurs |

## 3. Classer la cause (5 min)

| Famille | Indices | Vérifier |
|---|---|---|
| **Configuration** | code 1/2 au démarrage, message explicite | `docker compose config <service>` (⚠️ affiche les valeurs interpolées : ne pas coller la sortie dans un ticket), variables, fichiers de secret présents et **lisibles par l'UID du conteneur** (`ls -ln`), montages |
| **Dépendance** | l'application démarre puis sort sur « connexion refusée », « name not resolved » | la dépendance est-elle saine (`docker compose ps`, sonde) ? même réseau (`docker network inspect`) ? `depends_on` avec `condition: service_healthy` ? |
| **Ressources** | 137 + `OOMKilled=true`, ou `pids.max` atteint (« can't start new thread ») | `docker stats --no-stream`, `docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.PidsLimit}}'`, `dmesg` (`journalctl -k \| grep -i oom`) |
| **Sonde de santé** | conteneur `unhealthy` puis tué (Podman `HealthOnFailure=kill`, systemd `Notify=healthy` qui expire) | `docker inspect -f '{{json .State.Health}}'` : la sonde teste-t-elle la **vivacité** (`/sante`) et non la disponibilité (`/pret`, qui dépend de la base) ? délai de démarrage suffisant ? |
| **Image** | apparu juste après une mise à jour | `docker image inspect -f '{{.Id}} {{.Created}} {{json .Config.Entrypoint}} {{json .Config.Cmd}} {{.Config.User}}'` de l'ancienne et de la nouvelle image ; journal du pipeline qui l'a produite |
| **Hôte** | plusieurs conteneurs touchés, disque ou mémoire de l'hôte saturés | `df -h /var/lib/docker /var/lib/containerd`, `free -m`, `systemctl status docker containerd` (RB-123 si le disque est plein) |

## Cas particulier : le conteneur est tué sans prévenir

**Symptôme** : le service tombe sous charge ou au bout d'un certain temps, code 137, rien d'anormal dans les journaux de l'application (elle n'a pas eu le temps d'écrire).

| Observation | Cause | Vérifier et corriger |
|---|---|---|
| `OOMKilled=true`, ligne `Memory cgroup out of memory: Killed process …` dans `journalctl -k` | la limite mémoire du conteneur (`mem_limit`, `--memory`, `PodmanArgs=--memory=`) est atteinte | `docker stats --no-stream` sous charge ; relever la limite **si la mesure le justifie** (MR), ou borner l'application (cache Valkey : `--maxmemory` sous la limite du conteneur) |
| `OOMKilled=false`, pas de ligne OOM, message « can't start new thread » / `fork: Resource temporarily unavailable` avant l'arrêt | plafond de processus (`pids_limit`, `PidsLimit=`) | `cat /sys/fs/cgroup/<cgroup du conteneur>/pids.max` et `pids.current` ; trouver ce qui crée des processus avant de relever |
| `OOMKilled=false`, code 137 juste après un `docker stop` ou un déploiement | délai de grâce trop court : l'application n'a pas fini son arrêt propre | `docker inspect -f '{{.Config.StopTimeout}}'`, `stop_grace_period` (Compose), `StopTimeout=` (Quadlet) supérieur à la durée d'arrêt de l'application (20 s pour MédiAgenda et MédiDoc) |
| Podman : `health_status unhealthy` puis arrêt, code 137 | `HealthOnFailure=kill` a tué un conteneur dont la sonde échoue | la sonde est-elle juste (vivacité, délais) ? ou l'application est-elle réellement figée (alors : traces, escalade) |

## 4. Geler sans détruire (si le service doit rester arrêté le temps de l'analyse)

```
admin@ctr01:~$ docker update --restart no <NOM> && docker stop <NOM>          # garde le conteneur et ses journaux
app@ctr02:~$ systemctl --user stop <UNITÉ>.service                            # Quadlet : le conteneur (--rm) disparaît, journalctl garde ses traces
```

Le conteneur arrêté se lit encore (`docker logs`, `docker inspect`, `docker cp` d'un fichier). Pour retrouver le comportement normal : `docker update --restart unless-stopped <NOM>` (ou la politique du `compose.yaml`) puis `docker compose up -d <service>`.

## 5. Corriger et redéployer

- Corriger **la source** : `compose.yaml` ou Dockerfile (MR du projet applicatif), unité Quadlet (rôle Ansible ou fichier du compte `app`), configuration de l'hôte (rôle Ansible). Jamais une modification laissée à la main.
- Redéployer **ce seul service** : `docker compose up -d --no-deps <service>` ; `systemctl --user daemon-reload && systemctl --user restart <UNITÉ>.service`.
- Revenir à l'image précédente si la panne suit une mise à jour : étiquette précédente ou empreinte notée dans le journal (`MEDIAGENDA_TAG=<VERSION> docker compose up -d --no-deps api`).

## 6. Vérifier (5 min)

- `RestartCount` stable pendant 5 minutes (`watch -n 30 docker inspect -f '{{.RestartCount}}' <NOM>`) ; unité `active (running)` sans nouveau démarrage dans `journalctl` ;
- sonde de santé `healthy` ; depuis `adm01`, l'URL de disponibilité du service répond (`/pret` pour MédiAgenda, `/readyz` pour MédiDoc, `/sante.php` pour Legacy-RDV) ;
- `ms-verif-conteneurs` (M12-E28) repassé au vert.

## 7. Escalader

| Situation | À qui | Avec quoi |
|---|---|---|
| erreur applicative (traceback, segmentation, migration refusée) | équipe de l'application (MédiAgenda : Julien Petit) | code de sortie, 50 dernières lignes de journal, version d'image (empreinte) |
| hôte ou moteur en cause | équipe Plateforme (Karim Benali) | `docker info`, `df -h`, `journalctl -u docker --since -1h` |
| données en jeu (base qui ne démarre plus) | équipe Plateforme, **avant toute action** sur le volume | RB-121 (restauration) |

## Après l'incident

Post-mortem si le service a été indisponible plus de 15 minutes (modèle `modules/00-lab/ressources/M00-E46/modele-post-mortem.md`) ; ajouter à ce runbook la cause rencontrée si elle n'y est pas.

## Historique

| Version | Date | Auteur | Changement |
|---|---|---|---|
| 1.0 | <AAAA-MM-JJ> | <MOI> | création (M12-E23) |
