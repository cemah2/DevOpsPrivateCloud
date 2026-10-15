## Conteneurs (ms-verif-conteneurs)

Message type : `KO  redemarrage ctr01:mediagenda-api-1 a redémarré 3 fois depuis le dernier passage (0 → 3) — RB-120`.
Chaque ligne `KO` dit **quel conteneur, sur quel hôte**, et ce qui ne va pas.

| Ligne `KO` | Trois premières commandes | Réveiller quelqu'un ? |
|---|---|---|
| `redemarrage`, `etat … restarting` | RB-120 : `docker ps -a --filter name=<NOM>` ; `docker logs --tail 50 <NOM>` ; `docker inspect <NOM> --format '{{json .State}}'` (sous `app` : `podman …` et `systemctl --user status <unité>`) | Oui si c'est la **production** ou la recette un jour de recette ; sinon le matin |
| `sante … unhealthy` | `docker inspect <NOM> --format '{{json .State.Health}}'` (dernières sondes et leur sortie) ; `curl` de `/pret` depuis l'hôte ; dépendances (base, cache) | Comme ci-dessus |
| `absent`, `etat … exited` | `docker ps -a` (conteneur supprimé ou arrêté ?) ; `docker compose ps` dans le dossier de la pile ; `journalctl -u docker -n 50` | Oui si un service rendu disparaît |
| `hote`, `moteur` | `ssh admin@<hôte>` ; `systemctl status docker` ou, sous `app`, `systemctl --user status` ; `loginctl show-user app -p Linger` | Oui : on est aveugle sur l'hôte |
| `metriques` | `curl -s http://ctr01…:9323/metrics | head` ; `jq '."metrics-addr"' /etc/docker/daemon.json` | Non (la sonde voit encore les conteneurs) |
| `sonde` | Norme CNT-IMG-08 : ajouter un `HEALTHCHECK` (ou une exception écrite dans la configuration) | Non : ticket |
