# RB-123 — Hôte de conteneurs : disque plein

| | |
|---|---|
| **Déclencheur** | alerte d'occupation de `ms-verif-conteneurs` (≥ 80 % : avertissement, ≥ 90 % : critique) ; erreurs « No space left on device » d'une application ou du moteur |
| **Hôtes** | `ctr01`, `runner02` (Docker 29) ; `ctr02`, `ctr03` (Podman, comptes sans privilège) |
| **Durée typique** | 15 à 30 min |
| **Risque** | perte de données si l'on supprime un volume ; à éviter absolument |

## 1. Mesurer (sans rien supprimer)

```
df -h / ; df -i /                                   # blocs et inodes ; « Avail » à 0 : la réserve de root est entamée
sudo du -xsh /var/lib/docker /var/lib/containerd    # Docker 29 : images dans containerd
sudo du -xsh /var/lib/docker/containers/* | sort -h | tail -n 5     # journaux des conteneurs
sudo docker system df -v                            # images, conteneurs, volumes, cache de construction
sudo docker buildx du | tail -n 3                   # cache de construction détaillé
# Podman (compte app) : podman system df -v ; du -sh ~/.local/share/containers
```

Note l'objet qui explique l'essentiel, **qui** l'a créé et **quand** (`docker inspect … .Created`, étiquettes, `docker history`).

## 2. Libérer, du moins coûteux au plus coûteux

| Ordre | Objet | Commande | Condition |
|---|---|---|---|
| 1 | cache de construction inutilisé | `sudo docker builder prune -f --filter until=168h` | toujours sans risque (il se recrée) |
| 2 | images orphelines (`<none>`) | `sudo docker image prune -f` | sans risque |
| 3 | conteneur de débogage oublié et son journal | `sudo docker rm -f <nom>` | après accord de son auteur (ou s'il est arrêté depuis longtemps) |
| 4 | journal démesuré d'un conteneur **utile** | recréer le conteneur sans surcharge de `log-opts` ; en urgence seulement : `sudo truncate -s 0 <LogPath>` | ne jamais `rm` le fichier d'un conteneur vivant |
| 5 | images inutilisées nommées | `sudo docker image rm <image:étiquette>` | vérifier qu'aucune pile ne la référence |
| 6 | volume nommé | `sudo docker volume rm <nom>` | **jamais** sans avoir vérifié son contenu, son propriétaire et l'existence d'une sauvegarde ; accord écrit |

**Interdits** : `docker system prune -a --volumes`, `docker volume prune -a`, `podman system reset`, suppression manuelle sous `/var/lib/docker` ou `/var/lib/containerd`.

## 3. Vérifier

`df -h /` sous 80 % ; les piles redémarrent ou reprennent (`docker compose ps`, sondes) ; la base n'a pas perdu d'écriture critique (journal de PostgreSQL : pas de `PANIC` non suivi d'une reprise).

## 4. Traiter la cause

- Rotation des journaux par défaut au démon (`daemon.json` du rôle `docker_engine` : `log-opts` `max-size: 10m`, `max-file: 3`) ; **aucune** surcharge `logging:`/`--log-opt` dans les piles sans exception écrite.
- Ménage planifié de ce qui est jetable : minuterie `docker-menage.timer` du rôle `docker_engine` (images orphelines, cache de construction de plus de 7 jours).
- Données (exports, sauvegardes) hors des contextes de construction et des volumes applicatifs, avec rétention (RB-121).
- Seuil d'occupation de `ms-verif-conteneurs` en place sur chaque hôte.

## Retour arrière

Aucune des actions 1 à 5 ne détruit de donnée applicative. Une suppression de volume (6) ne se rattrape que par la restauration de RB-121.
