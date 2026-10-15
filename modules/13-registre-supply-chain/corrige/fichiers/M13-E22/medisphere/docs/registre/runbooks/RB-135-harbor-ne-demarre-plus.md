# RB-135 — Harbor ne démarre plus

| | |
|---|---|
| Quand | `/api/v2.0/health` ne répond pas ou n'est pas `healthy` ; `harbor.service` en échec |
| Durée | 15 à 45 min (au-delà de 1 h 30 sans cause : RB-131, restauration) |
| Règle | ne rien effacer dans `/data` sans savoir ce que c'est ; ne jamais `docker compose down -v` ; ne pas modifier les fichiers générés par `prepare` |

## 1. Constater

```
admin@reg01:~$ systemctl status harbor --no-pager ; journalctl -u harbor -n 50 --no-pager
admin@reg01:~$ cd /opt/harbor && sudo docker compose ps -a
admin@reg01:~$ sudo docker inspect -f '{{.Name}} {{.State.Status}} {{.State.ExitCode}} {{.RestartCount}}' $(sudo docker ps -aq)
```

L'unité échoue **avant** tout conteneur (erreur de `docker compose` : fichier `env` introuvable, YAML invalide) → configuration générée (section 3.4). Sinon, chercher le **premier** composant en échec : `harbor-db`, `redis` et `registry` d'abord ; `harbor-core` dépend de la base ; `nginx` dépend du cœur et du portail.

## 2. Lire ses journaux

`sudo docker logs --tail 50 <conteneur>` et `/var/log/harbor/<composant>.log`.

## 3. Causes classiques

1. **Disque de données plein** : `df -h /data`, `sudo du -xsh /data/* | sort -h`, `sudo find /data -xdev -size +1G`. PostgreSQL ne peut plus écrire (`No space left on device`). Libérer ce qui n'appartient pas à Harbor (exports, copies d'essai) **après avoir identifié qui l'a posé** ; jamais dans `database/`, `registry/` ou `secret/`. Puis `systemctl restart harbor`.
2. **Droits des données de la base** : `ls -ln /data/database` doit montrer l'uid **999** (utilisateur `postgres` du conteneur), mode 700 ; `docker logs harbor-db` : `permission denied` ou `wrong ownership`. Corriger (`chown -R 999:999`, `chmod 700`) — ou, Harbor arrêté, relancer `./prepare --with-trivy` dans `/opt/harbor` : `prepare` remet ces droits (le rôle ne relance `prepare` que si `harbor.yml` change).
3. **Certificat du proxy illisible** : `docker logs nginx` (`cannot load certificate key … Permission denied`) ; `/data/secret/cert/server.{crt,key}` appartiennent à l'uid **10000** (utilisateur `nginx`), lisibles. Remettre les droits que pose `prepare` (`chown 10000:10000`, mode 644), ou relancer `prepare` (il recopie les fichiers avec ces droits). `harbor-recharger-certificat` ne répare rien : il réécrit le contenu en **gardant** les droits existants. Puis `docker restart nginx`.
4. **Configuration générée absente ou incohérente** : `prepare` efface `common/config/` **avant** de valider `harbor.yml` ; s'il échoue (YAML invalide, chemin de certificat inexistant), il ne reste rien à démarrer. Ne pas recréer à la main : repasser le rôle `harbor` (il rend `harbor.yml` depuis le gabarit et relance `prepare`), d'abord en `--check --diff` pour voir l'écart avec la modification manuelle.

## 4. Vérifier

Santé `healthy` ; tirage et poussée depuis `runner02` ; `cosign verify` d'une image ; relancer la dernière réplication ; `ms-verif-registre` vert.

## 5. Prévenir

Seuil disque de `ms-verif-registre` (80 %) ; aucune modification manuelle de `harbor.yml` (géré par Ansible, dérive détectée par `--check`) ; dossier d'export hors de `/data`.
