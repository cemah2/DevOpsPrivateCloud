<!-- Section à ajouter à RB-120 — Un conteneur redémarre en boucle (M12-E23), après « Constater ». -->

## Cas particulier : le conteneur s'arrête dès le démarrage

**Symptôme** : `docker compose ps` montre `Restarting (N)`, `Created` ou `Exited (N)` quelques secondes après un déploiement ; le service ne répond jamais.

### 1. Lire le code de sortie et l'erreur du moteur (30 s)

```
sudo docker inspect -f 'statut={{.State.Status}} code={{.State.ExitCode}} oom={{.State.OOMKilled}} redemarrages={{.RestartCount}} erreur={{.State.Error}}' <conteneur>
```

| Observation | Famille | Où chercher |
|---|---|---|
| `created`, code 127 ou 126, `State.Error` rempli, aucun journal | le moteur ne trouve pas (127) ou ne peut pas exécuter (126) la commande | `ENTRYPOINT`/`CMD` de l'image (`docker image inspect`) et surcharges (`docker compose config`) : forme exec mal écrite, chemin faux, droit `x` absent |
| code 255, une ligne `exec …: no such file or directory` ou `exec format error` | l'exécutable existe mais le noyau ne peut pas le charger | `docker create` + `docker cp` du binaire, puis `file` / `readelf -l` : binaire dynamique sur `scratch`/distroless statique, mauvaise architecture, script sans interpréteur (`#!/bin/bash` absent de l'image) |
| code 1, 2 ou autre, message de l'application | l'application refuse de démarrer | journaux du dernier essai (`docker logs --tail 20`) ; variables d'environnement (`docker compose config <service>` — attention, mots de passe interpolés) |
| code 137 + `oom=true`, code 3 « can't start new thread » | ressource refusée | voir la section « tué sans prévenir » (limites mémoire et processus) |

### 2. Comparer à l'état connu

- `git diff` du dépôt qui porte `compose.yaml` / le Dockerfile, ou la dernière version déployée ;
- `docker image inspect -f '{{.Created}} {{json .Config.Entrypoint}} {{json .Config.Cmd}} {{.Config.User}}' <image>` pour l'ancienne et la nouvelle image.

### 3. Corriger et redéployer ce seul service

`sudo docker compose up -d --no-deps <service>` (ou `--build` après correction du Dockerfile), puis surveiller `RestartCount` pendant une minute. Ne jamais recréer les services avec données (`db`) pour « voir si ça repart ».

### Prévention

- Test de fumée de l'image dans le pipeline avant la poussée (le conteneur démarre et répond à sa sonde) ; contrôle `file` des binaires Go (`statically linked`).
- `docker compose config --quiet` dans la CI des dépôts qui portent un `compose.yaml`.
- Revue : toute surcharge `entrypoint:`/`command:` d'un service se justifie dans la MR.
