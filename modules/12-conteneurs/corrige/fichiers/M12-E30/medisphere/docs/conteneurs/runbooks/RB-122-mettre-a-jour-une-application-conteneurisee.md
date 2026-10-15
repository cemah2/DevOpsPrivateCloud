# RB-122 — Mettre à jour une application conteneurisée (et revenir en arrière)

| | |
|---|---|
| **Version** | 1.0 — 2026-10 (M12-E30, CHG-1330) |
| **Périmètre** | piles Compose de `ctr01` (deux instances derrière HAProxy) ; unités Quadlet sans privilège de `ctr02` (mise à jour automatique) |

## 1. Préparer (dans tous les cas)

- Version cible **publiée par la CI** (jamais construite à la main), son **empreinte** relevée : `skopeo inspect docker://ctr01.par1.medisphere.internal:5000/mediagenda/api:<VERSION> | jq -r .Digest`.
- Migrations de base **compatibles avec les deux versions** (règle « étendre puis contracter ») : la version N+1 ajoute (colonne facultative, table) sans retirer ce que N utilise ; la suppression vient dans une version ultérieure. Sinon : pas de mise à jour progressive, fenêtre de coupure annoncée.
- Sauvegarde de la nuit présente (`wb-backup-conteneurs`, RB-121) ; si la migration est lourde : export logique juste avant.
- Charge témoin prête (boucle de requêtes depuis `adm01`, codes HTTP journalisés).

## 2. Compose sur `ctr01` (mise à jour progressive)

```
admin@ctr01:~/src/mediagenda-api$ export COMPOSE_FILE=compose.yaml:compose.ha.yaml
admin@ctr01:~/src/mediagenda-api$ MEDIAGENDA_TAG=<VERSION> docker compose run --rm migrations   # si la version apporte une migration
admin@ctr01:~/src/mediagenda-api$ MEDIAGENDA_TAG=<VERSION> outils/maj-progressive.sh
```

Le script recrée `api`, attend qu'il soit *healthy* puis **UP dans HAProxy**, puis fait de même pour `api-b`. En cas d'échec il s'arrête **avant** la seconde instance (le service continue sur l'autre) et affiche la commande de retour.

**Vérifier** : `curl -s localhost:8000/sante` (version), page d'état `curl -s 'http://127.0.0.1:8404/etat;csv' | awk -F, '$1=="api"{print $2,$18}'` (deux serveurs UP), journal de la charge témoin (aucun code ≠ 200).

**Revenir en arrière** : `MEDIAGENDA_TAG=<PRÉCÉDENTE> outils/maj-progressive.sh` (même mécanisme, même absence de coupure). Une migration déjà appliquée **reste** : c'est pourquoi elle doit être compatible avec la version précédente.

Mesures du test de recette (E30) : mise à jour 0.2.0 → 0.2.1 sous 20 requêtes/s, 16 s, **0 erreur** sur 915 requêtes ; image cassée (`0.3.0`, sonde jamais verte) : arrêt du script après la première instance, **0 erreur** sur 1 475 requêtes, retour à 0.2.1 sans erreur.

## 3. Quadlet sur `ctr02` (mise à jour automatique)

Publier = déplacer l'étiquette mobile `recette` :

```
admin@adm01:~$ skopeo copy --src-creds plateforme:<MDP> --dest-creds plateforme:<MDP> \
    docker://ctr01.par1.medisphere.internal:5000/mediagenda/api:<VERSION> \
    docker://ctr01.par1.medisphere.internal:5000/mediagenda/api:recette
app@ctr02:~$ podman auto-update --dry-run      # UPDATED = pending
app@ctr02:~$ podman auto-update                # sinon : le timer podman-auto-update (quotidien) le fera
```

Retour arrière **automatique** : si l'unité ne redevient pas active (sonde jamais *healthy* dans `TimeoutStartSec`, grâce à `Notify=healthy`), `podman auto-update` remet l'image précédente et redémarre l'unité (`UPDATED` = `rolled back` dans la sortie de `podman auto-update` ; journaux `journalctl --user -u podman-auto-update.service` quand la mise à jour vient du timer, et `journalctl --user -u mediagenda-api.service`). Il faut ensuite **remettre une bonne image sous `recette`**, sinon le passage suivant retentera la mauvaise.

Retour arrière **manuel** : republier la version précédente sous `recette`, puis `podman auto-update`.

## 4. Quelle version tourne ?

- `ctr01` : `docker compose images` (étiquette) **et** `docker inspect --format '{{.Image}}' mediagenda-api-1` (empreinte) ; `/sante` (version de l'application).
- `ctr02` : `podman inspect --format '{{.ImageDigest}}' <CONTENEUR>` ; l'étiquette `recette` ne dit pas ce qui tourne (elle a pu bouger depuis).
- Production (règle) : **jamais** d'étiquette mobile ; une version immuable par son empreinte, changée par MR (traçable et reproductible).
