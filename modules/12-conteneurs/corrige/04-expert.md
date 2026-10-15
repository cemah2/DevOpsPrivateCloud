# Module 12 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Avec les conteneurs, « j'ai fait `docker compose down && up` et ça remarche » est doublement faux : la recréation efface la preuve (l'état du conteneur, son code de sortie, ses réseaux réels) et elle ne corrige rien de ce qui est hors du conteneur (fichier de configuration, droits d'un volume, règle de pare-feu, minuterie).

Les scripts d'injection sont dans `corrige/pannes/` : `_m12-commun.sh` contient les fonctions partagées (exécution par SSH en `admin` + `sudo`, installation et remise à la référence des **témoins**, modification exacte de `compose.yaml` avec sauvegarde) ; `_m12-plateau/` contient les fichiers de référence (pile `recette` de `ctr01`, fichiers Quadlet de `recette-cache` pour `ctr02` et `ctr03`). Chaque modification est journalisée sur l'hôte touché dans `/var/lib/workbook/pannes.log`.

Les sorties reproduites sont **représentatives**. Celles de la pile de recette (codes de sortie, messages de `runc`, de MédiAgenda, de PostgreSQL 18, de `docker compose` v5, comportement de `docker network disconnect` puis `up`, règle nftables de la famille `bridge`) ont été **observées** sur Docker 29.8 / Compose 5.5 / runc 1.5 pendant la rédaction ; l'horodatage, les identifiants et les tailles varient.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- E36 v2 et v3, E40 (toutes variantes) : écrits d'après la documentation de Podman 5.4/5.8 (`podman-systemd.unit(5)`, `podman-unshare(1)`) et de systemd 257 ; en particulier, pour E40 v2, Quadlet 5.4 peut soit refuser de générer l'unité (« requested Quadlet network recette.network was not found »), soit la générer avec une dépendance vers `recette-network.service` introuvable : les deux cas sont traités.
- E39 : le remplissage réel du disque (non lancé sur la machine de rédaction) ; la variante 2 ajuste la taille des couches à la consommation mesurée, la réserve de root d'ext4 dépend de l'image dorée (5 % par défaut).
- E41 v3 : la minuterie `recette-autoheal` (systemd absent de la machine de rédaction) ; la sonde en échec (`exec: "curl": executable file not found in $PATH`) a été observée.
- E42 : la découverte des fichiers du registre et la substitution du mot de passe et du certificat ont été testées contre un `registry:3` à htpasswd et TLS ; les variantes de `runner02` (édition de `config.toml`) ont été testées sur un fichier d'exemple, pas sur un vrai runner. Le message exact de BuildKit sans privilège quand les exceptions `unconfined` manquent dépend de ta construction (M12-E21).
- E44 : vérifié avec `runc` 1.5.1 (`runc spec`, `runc run -d`, lecture de l'état) ; la partie 1 (`unshare`, overlay, `pivot_root`) suit la documentation de util-linux 2.41 et du noyau 6.12.

---

## Méthode commune aux pannes de conteneurs

1. **État complet d'abord.** `docker compose ps -a` (ou `systemctl --user status`, `podman ps -a`) puis `docker inspect` : `State.Status`, `ExitCode`, `Error`, `OOMKilled`, `RestartCount`, `Health.Log`, `NetworkSettings.Networks`, `Mounts`, `HostConfig` (limites, journal, capacités). Le code de sortie classe la panne : 1-2 l'application, 125 le moteur (option refusée), 126 non exécutable, 127 introuvable, 128 + N un signal (137 = 9, 143 = 15), 255 l'exécution a échoué après le démarrage du conteneur (par exemple `exec` impossible).
2. **Déclaré contre réel.** `docker compose config <service>` (fichiers fusionnés, variables résolues) contre `docker inspect` ; fichier Quadlet contre unité générée (`systemctl --user cat`) ; `config.toml` contre comportement du runner. Une différence est une piste.
3. **Chercher ce qui a bougé.** Dates de modification (`ls -l --time-style=full-iso`), `docker events --since`, `journalctl --since`, archives de `/srv/recette-archives/`, historique de l'interpréteur des comptes.
4. **Reproduire au plus petit.** Un test Python dans le conteneur (résolution, TCP), un `docker run --rm --entrypoint` sur l'image, `curl` sur un point d'accès, le générateur Quadlet à blanc, une construction `--progress=plain`.
5. **Corriger à la racine, puis faire converger le code.** Un `compose.yaml`, un fichier Quadlet, `daemon.json` ou `config.toml` corrigés à la main doivent être reportés dans le rôle Ansible ou le dépôt qui les produit.
6. **Prévenir** : quel contrôle de pipeline, quelle règle de `normes.md`, quelle sonde de `ms-verif-conteneurs` aurait vu la panne avant l'utilisateur ?

---

### M12-E35 — Panne : le conteneur s'arrête aussitôt

**Démarche de diagnostic**

*Symptômes* : variantes 1 et 2, plus rien sur le port 18000 de `ctr01` ; variante 3, plus rien sur le port 18080 (la pile `mediagenda` des paliers précédents, sur les ports 8000 et 8080, n'est pas touchée). *Hypothèses* : configuration refusée par l'application, commande introuvable, exécutable non chargeable, ressource refusée (traité en E41).

**Étape 1 — État.**

```
admin@ctr01:/srv/recette$ sudo docker compose ps -a --format 'table {{.Service}}\t{{.Status}}'
SERVICE      STATUS
api          Restarting (2) 3 seconds ago        # variante 1
api          Created                             # variante 2
doc          Restarting (255) 5 seconds ago      # variante 3
admin@ctr01:~$ sudo docker inspect -f '{{.State.Status}} code={{.State.ExitCode}} redemarrages={{.RestartCount}} erreur={{.State.Error}}' recette-api-1
```

La politique `unless-stopped` relance le conteneur avec un délai croissant ; le compteur de redémarrages monte. Un conteneur resté `created` n'a **jamais** démarré : la politique de redémarrage ne s'applique pas, et il n'y a pas de journal.

**Variante 1 — variable renommée (code 2).**

```
admin@ctr01:/srv/recette$ sudo docker compose logs --tail 2 api
api-1  | {"niveau": "CRITICAL", "journal": "mediagenda", "message": "configuration invalide : variable(s) obligatoire(s) absente(s) : MEDIAGENDA_VALKEY_URL"}
admin@ctr01:/srv/recette$ sudo docker compose config api | grep -A6 environment
    environment:
      MEDIAGENDA_DB_URL: postgresql://mediagenda:…@base-recette:5432/mediagenda
      MEDIAGENDA_VALKEY_URI: redis://valkey:6379/0
```

Le message est explicite : l'application fait son travail (refuser de démarrer sans configuration, facteur III). La cause est dans `compose.yaml` : `MEDIAGENDA_VALKEY_URI` au lieu de `MEDIAGENDA_VALKEY_URL`. Remarque : `docker compose config` montre ici le mot de passe interpolé ; ne colle jamais sa sortie brute dans un ticket. Correctif :

```
admin@ctr01:/srv/recette$ sudoedit compose.yaml          # MEDIAGENDA_VALKEY_URL
admin@ctr01:/srv/recette$ sudo docker compose up -d --no-deps api
admin@ctr01:/srv/recette$ sudo docker compose ps api     # Up … (healthy), plus de redémarrage
```

`--no-deps` évite de toucher à la base et au cache ; Compose recrée seulement `api` parce que sa configuration a changé.

**Variante 2 — forme exec avec une seule chaîne (code 127, état `created`).**

```
admin@ctr01:/srv/recette$ sudo docker compose up -d --no-deps api
Error response from daemon: failed to create task for container: failed to create shim task: OCI runtime create failed:
runc create failed: unable to start container process: error during container init:
exec: "python -m mediagenda": executable file not found in $PATH
admin@ctr01:~$ sudo docker inspect -f '{{json .Config.Entrypoint}} {{json .Config.Cmd}}' recette-api-1
["python -m mediagenda"] null
admin@ctr01:~$ sudo docker image inspect -f '{{json .Config.Entrypoint}}' recette/mediagenda-api:plateau
["python","-m","mediagenda"]
```

En forme exec (tableau JSON), chaque élément est **un** argument d'`execve` : `"python -m mediagenda"` est cherché comme un fichier de ce nom dans `PATH`. `runc` échoue avant de lancer quoi que ce soit (code 127 : introuvable). L'image avait déjà le bon `ENTRYPOINT` : la surcharge de Lucas était inutile. Correctif : supprimer la ligne `entrypoint:` (ou l'écrire `["python", "-m", "mediagenda"]`). La forme « shell » (`entrypoint: python -m mediagenda`) fonctionnerait aussi mais passe par `/bin/sh -c`, qui ne relaie pas `SIGTERM` (M12-E17) : à proscrire pour un processus principal.

**Variante 3 — binaire dynamique sur `scratch` (code 255).**

```
admin@ctr01:/srv/recette$ sudo docker compose logs --tail 1 doc
doc-1  | exec /medidoc: no such file or directory
admin@ctr01:~$ id=$(sudo docker create recette/medidoc:1.1.0-rc1) && sudo docker cp "$id":/medidoc /tmp/medidoc-rc1 && sudo docker rm "$id"
admin@ctr01:~$ file /tmp/medidoc-rc1
/tmp/medidoc-rc1: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, …, stripped
admin@ctr01:~$ diff <(sudo cat /srv/recette-archives/*/doc/Dockerfile 2>/dev/null | tail -n +1) /srv/recette/doc/Dockerfile   # si une archive existe
```

Le fichier `/medidoc` existe. Le noyau, pour exécuter un ELF **dynamique**, doit d'abord charger son interpréteur (`/lib64/ld-linux-x86-64.so.2`), absent de `scratch` : `execve` renvoie `ENOENT`, d'où « no such file or directory » sur un fichier pourtant présent. La cause : le Dockerfile 1.1.0-rc1 a perdu `CGO_ENABLED=0`. Dans l'image `golang:1.26-trixie`, un compilateur C est présent, donc cgo est activé par défaut et le paquet `net` (utilisé par `net/http`) se lie à la glibc. Deux corrections : rétablir `CGO_ENABLED=0` (binaire statique, la bonne réponse pour MédiDoc, M12-E10) ; ou garder cgo et choisir une image finale qui a la glibc (`gcr.io/distroless/base-debian13`, `debian:trixie-slim`), au prix d'une surface plus grande. Correctif :

```
admin@ctr01:/srv/recette$ sudoedit doc/Dockerfile        # CGO_ENABLED=0 go build …
admin@ctr01:/srv/recette$ sudo docker compose build doc && sudo docker compose up -d --no-deps doc
admin@ctr01:~$ curl -s http://ctr01.par1.medisphere.internal:18080/healthz
{"statut":"ok","version":"recette"}
```

(Le service pointe encore vers l'étiquette `1.1.0-rc1` : remets `recette/medidoc:plateau` ou une étiquette qui ne ment pas sur son contenu, et note-le pour Julien.)

**Clôture** : `lab/bin/check 12 35`, puis `lab/bin/break 12 35 --annuler`.

**Explications**
Le moteur et l'application échouent à des moments différents. Le moteur (`runc create`) prépare les espaces de noms, les montages et le cgroup, puis appelle `execve` de la commande : si le fichier est introuvable, c'est une erreur **de création**, conteneur `created`, code 127, rien dans les journaux. Si `execve` échoue sur l'interpréteur ELF, l'erreur est remontée par le processus d'initialisation du conteneur après le démarrage (code 255, une ligne dans les journaux). Si l'application démarre puis s'arrête, c'est elle qui parle (code et message propres). Le code de sortie est donc la première ligne du diagnostic.

**Alternatives**
- `docker run --rm -it --entrypoint sh recette/mediagenda-api:plateau` pour explorer une image qui a un shell ; pour une image sans shell, `docker create` + `docker cp`, ou `docker export | tar -t`, ou Dive.
- `docker compose up` sans `-d` sur le seul service : la sortie s'affiche directement (utile en recette, pas en production).

**Pièges classiques**
- Lire les journaux d'un conteneur `created` (vides) et conclure « il n'y a pas d'erreur ».
- « Réparer » en mettant `restart: always` : le conteneur boucle plus vite.
- Remplacer `scratch` par `debian` « pour que ça marche » sans comprendre pourquoi : l'image grossit de 100 Mo et la cause reste.
- Coller `docker compose config` (mots de passe interpolés) dans un ticket.

**En production chez MédiSphère**
Le pipeline d'image (M12-E21) lance un test de fumée de l'image construite (`docker run --rm <image> --version`, ou le conteneur démarré et `/healthz` appelé) avant la poussée, et vérifie `file`/`readelf` pour les binaires Go ; `docker compose config --quiet` valide les fichiers de Compose dans la MR. RB-120 est complété de la section « s'arrête dès le démarrage » ([modèle](fichiers/M12-E35/medisphere/docs/conteneurs/runbooks/RB-120-section-demarrage.md)).

---

### M12-E36 — Panne : « permission denied » sur le volume

**Démarche de diagnostic**

*Symptômes* : variante 1, base de recette en boucle et `/pret` à 503 ; variantes 2 et 3, `recette-cache` arrêté. *Hypothèses* : propriétaire ou mode des fichiers, UID effectif du processus, correspondance d'UID (sans privilège), étiquette SELinux, système de fichiers en lecture seule.

**Variante 1 — volume restauré en root (`ctr01`).**

```
admin@ctr01:/srv/recette$ sudo docker compose logs --tail 3 db
db-1  | initdb: error: could not access directory "/var/lib/postgresql/18/docker": Permission denied
admin@ctr01:~$ sudo docker inspect -f '{{.Config.User}}' recette-db-1
999:999
admin@ctr01:~$ m=$(sudo docker volume inspect -f '{{.Mountpoint}}' recette_pgdata); sudo stat -c '%U(%u):%G(%g) %a %n' "$m" "$m/18" "$m/18/docker"
root(0):root(0) 1777 /var/lib/docker/volumes/recette_pgdata/_data
root(0):root(0) 755  /var/lib/docker/volumes/recette_pgdata/_data/18
root(0):root(0) 700  /var/lib/docker/volumes/recette_pgdata/_data/18/docker
```

PostgreSQL 18 (image officielle) range ses données dans `/var/lib/postgresql/18/docker` (c'est nouveau en 18 : le volume se monte sur `/var/lib/postgresql`). Le processus tourne en UID 999 sans capacité : il ne peut pas traverser un répertoire root en 700. Comme il ne voit plus `PG_VERSION`, le point d'entrée tente même un `initdb`, qui échoue : sans ce refus, il aurait initialisé une base **vide** par-dessus. D'où vient l'état ? `docker cp` vers un conteneur crée les fichiers en `root:root` (sauf `-a`) : c'est l'outil de restauration de Lucas. Correctif minimal (aucune donnée touchée) :

```
admin@ctr01:/srv/recette$ sudo docker compose stop db
admin@ctr01:~$ sudo chown -R 999:999 "$m" && sudo chmod 700 "$m/18/docker"
admin@ctr01:/srv/recette$ sudo docker compose start db && sudo docker compose ps db     # healthy
admin@ctr01:~$ curl -s http://ctr01.par1.medisphere.internal:18000/api/v1/rendez-vous?limite=1    # les données d'avant sont là
```

La procédure correcte de restauration est celle de RB-121 (M12-E29) : `pg_dump`/`pg_restore` à travers le serveur, ou `tar` exécuté **dans** un conteneur qui tourne avec le bon UID (`docker run --rm --user 999:999 -v recette_pgdata:/v …`), ou `docker cp -a`.

**Variante 2 — répertoire de données « recréé » par `app` (`ctr02`).**

```
app@ctr02:~$ journalctl --user -u recette-cache -n 5 --no-pager
… Can't open or create append-only dir appendonlydir: Permission denied
… recette-cache.service: Failed with result 'exit-code'.
app@ctr02:~$ ls -ln ~/recette/                        # vu de l'hôte
drwxr-xr-x 2 1001 1001 4096 … cache
app@ctr02:~$ podman unshare ls -ln ~/recette/         # vu de l'espace de noms de app
drwxr-xr-x 2 0 0 4096 … cache
app@ctr02:~$ grep app /etc/subuid
app:524288:65536
```

Dans l'espace de noms de `app`, l'UID 0 du conteneur **est** `app` (1001) ; les UID 1 à 65536 du conteneur sont 524288 à 589823 sur l'hôte. Valkey tourne en `User=999` : il est l'UID 524288 + 998 = **525286** sur l'hôte. Un répertoire qui appartient à `app` appartient au « root » du conteneur, et Valkey n'y écrit pas. L'état sain était `525286:525286` sur l'hôte, `999:999` dans l'espace de noms. Correctif :

```
app@ctr02:~$ podman unshare chown -R 999:999 ~/recette/cache
app@ctr02:~$ ls -ln ~/recette/                        # 525286 525286 … cache
app@ctr02:~$ systemctl --user reset-failed recette-cache && systemctl --user start recette-cache
app@ctr02:~$ podman exec recette-cache valkey-cli ping    # PONG
```

Alternative déclarative : l'option `:U` du montage (`Volume=%h/recette/cache:/data:U`), qui fait faire ce `chown` par Podman à chaque démarrage (coût proportionnel au nombre de fichiers), ou un volume nommé Podman (créé avec le bon propriétaire depuis l'image).

**Variante 3 — `:Z` retiré, contexte remis à `user_home_t` (`ctr03`).**

```
[app@ctr03 ~]$ journalctl --user -u recette-cache -n 3 --no-pager      # … Permission denied
[admin@ctr03 ~]$ sudo ausearch -m avc -ts recent | tail -n 4
type=AVC msg=audit(…): avc:  denied  { write } for  pid=… comm="valkey-server" name="cache" … scontext=system_u:system_r:container_t:s0:c123,c456 tcontext=unconfined_u:object_r:user_home_t:s0 tclass=dir permissive=0
[admin@ctr03 ~]$ ls -Zd ~app/recette/cache
unconfined_u:object_r:user_home_t:s0 /home/app/recette/cache
[app@ctr03 ~]$ grep ^Volume ~/.config/containers/systemd/recette-cache.container
Volume=%h/recette/cache:/data
```

Les droits Unix sont bons (même raisonnement qu'en variante 2) : c'est SELinux. Le processus du conteneur est `container_t` avec une paire de catégories MCS propre ; il n'a pas le droit d'écrire un objet `user_home_t`. `:Z` demandait à Podman d'étiqueter le répertoire `container_file_t` avec les catégories **de ce conteneur** ; sans lui, le `restorecon` de Lucas a remis le type par défaut du dossier personnel. Correctif durable : rétablir `:Z` dans le fichier Quadlet (`systemctl --user daemon-reload`, redémarrage), Podman réétiquette au démarrage. `chcon -t container_file_t` réparerait jusqu'au prochain `restorecon` ; `:z` (minuscule, étiquette partagée sans catégories) conviendrait si plusieurs conteneurs devaient partager ce répertoire.

**Explications**
Un « Permission denied » se résout toujours par trois questions : quel UID effectif (`docker inspect … .Config.User`, `ps -o uid` depuis l'hôte, `podman top <c> user huser`), quel propriétaire et quel mode **vus du même espace de noms**, et quelle politique obligatoire (SELinux, AppArmor, montage en lecture seule) par-dessus.

**Pièges classiques**
- `chmod -R 777` : répare, et donne le répertoire de la base à tout compte de l'hôte.
- `chown` depuis l'hôte vers `999` sur `ctr02` : 999 sur l'hôte n'est **pas** 999 dans le conteneur.
- `setenforce 0` « pour tester », oublié ensuite.
- Relancer la base sans regarder pourquoi `initdb` se déclenche : un volume « vide » qu'on réinitialise efface la sauvegarde qu'on vient de restaurer.

**En production chez MédiSphère**
Les normes (M12-E33) imposent un UID fixe et documenté par image ; les répertoires de données sans privilège sont créés par le rôle Ansible avec `podman unshare chown` (ou `:U`) ; tout montage sur Rocky porte `:Z` ou `:z`, justifié. La restauration passe par RB-121.

---

### M12-E37 — Panne : l'application ne joint plus sa base

**Démarche de diagnostic**

*Symptôme commun* : `/sante` 200, `/pret` en échec. *Le corps et le journal orientent* :

```
admin@adm01:~$ curl -s -m 10 http://ctr01.par1.medisphere.internal:18000/pret; echo " $?"
{"statut":"pas-pret","postgresql":"indisponible","valkey":"ok"}          # variantes 1 et 3
{"statut":"pas-pret","postgresql":"indisponible","valkey":"indisponible"} # variante 2
 28                                                                       # variante 4 : délai dépassé (ou 503 après quelques secondes)
admin@ctr01:/srv/recette$ sudo docker compose logs --tail 5 api | grep -i dépendance
```

**Tests depuis le conteneur (dans l'ordre : nom, puis TCP).**

```
admin@ctr01:~$ t() { sudo docker exec recette-api-1 python -c "$1"; }
admin@ctr01:~$ t "import socket; print(socket.getaddrinfo('base-recette', 5432)[0][4])"
admin@ctr01:~$ t "import socket; socket.create_connection(('base-recette', 5432), 3); print('tcp ok')"
admin@ctr01:~$ t "import socket; print(socket.getaddrinfo('db', 5432)[0][4])"
```

| Variante | `base-recette` | `db` | TCP 5432 | Valkey |
|---|---|---|---|---|
| 1 | inconnu | inconnu | — | ok |
| 2 | inconnu | inconnu | — | inconnu |
| 3 | inconnu | **résolu** | ok par `db` | ok |
| 4 | résolu | résolu | **délai dépassé** | ok |

**Déclaré contre réel.**

```
admin@ctr01:~$ sudo docker inspect -f '{{json .NetworkSettings.Networks}}' recette-api-1 | jq 'map_values(.Aliases)'
admin@ctr01:~$ sudo docker inspect -f '{{json .NetworkSettings.Networks}}' recette-db-1 | jq 'map_values(.Aliases)'
admin@ctr01:/srv/recette$ sudo docker compose config db | sed -n '/networks:/,/^[^ ]/p'
```

**Variante 1 — base déplacée sur un réseau `base` (`internal: true`) que l'API ne rejoint pas.** La base est sur `recette_base`, l'API sur `recette_front` et `recette_donnees`. Le DNS embarqué de Docker ne répond que pour les conteneurs des réseaux **communs** : aucun, donc aucun nom. `internal: true` n'y est pour rien : il retire la route vers l'extérieur (pas de NAT ni de passerelle), il n'empêche pas deux conteneurs du même réseau de se parler. Correctif selon l'intention de Sophie (« la base ne doit pas être joignable de l'extérieur ») : c'était **déjà** le cas avec `donnees` en `internal: true` et sans port publié ; remettre `db` sur `donnees` (avec son alias), ou rattacher aussi l'API à `base`. Supprimer le réseau devenu inutile.

**Variante 2 — API détachée à chaud de `recette_donnees`.** `compose.yaml` est intact, `docker compose config` est sain : seule l'inspection du conteneur montre l'écart (un seul réseau, `recette_front`). Quelqu'un a lancé `docker network disconnect` (le journal du démon ou `docker events --since 24h --filter event=disconnect` le montre). Correctif immédiat : `sudo docker network connect recette_donnees recette-api-1`, ou `sudo docker compose up -d --no-deps api` : Compose v5 constate que le conteneur n'est plus conforme et le reconnecte (observé : il le redémarre au passage). La réparation durable est organisationnelle : on ne « débogue » pas un réseau de recette en détachant des conteneurs ; on lance un conteneur d'outillage sur le même réseau (`docker run --rm --network recette_donnees nicolaka/netshoot` ou une image interne).

**Variante 3 — alias `base-recette` supprimé.** Le nom du service (`db`) se résout toujours : Compose l'enregistre automatiquement. L'alias, lui, n'existe que s'il est déclaré, et l'URL de l'API l'utilise. Correctif : rétablir `aliases: [base-recette]` sur le réseau `donnees` du service `db` (c'est un contrat entre services : il se documente dans `compose.yaml` par un commentaire), ou faire pointer l'URL sur `db`.

**Variante 4 — pare-feu de l'hôte, famille `bridge`.**

```
admin@ctr01:~$ sudo nft list ruleset | sed -n '/table bridge/,/^}/p'
table bridge filtrage_est_ouest {
	comment "durcissement InfoGér : pas de flux est-ouest vers les bases"
	chain transit {
		type filter hook forward priority filter; policy accept;
		ip daddr 172.25.0.0/16 tcp dport 5432 drop
	}
}
admin@ctr01:~$ sudo docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' recette_donnees
172.25.0.0/16
```

Entre deux conteneurs d'un **même** pont Linux, les trames sont commutées par le pont : elles ne passent pas par la chaîne `forward` des familles `ip`/`inet` (sauf avec `br_netfilter`), donc ni par les règles de Docker ni par `DOCKER-USER`. Elles passent en revanche par le crochet `forward` de la famille **`bridge`** de nftables : c'est là qu'InfoGér a posé sa règle. Parce qu'elle **jette** (`drop`) au lieu de refuser, les connexions déjà ouvertes de la réserve de connexions restent pendues : `/pret` ne répond plus du tout (observé : plus de 60 s) au lieu d'un 503 rapide. Correctif : `sudo nft delete table bridge filtrage_est_ouest`, puis rechercher **qui** l'a posée (script d'InfoGér, rôle, `/etc/nftables.conf`, unité systemd) pour qu'elle ne revienne pas au redémarrage. Si l'intention (pas de flux est-ouest non prévus) est légitime, elle s'exprime par des réseaux Compose séparés par niveau, ou par une règle `bridge` qui **autorise** explicitement API → base avant de refuser le reste, versionnée et documentée dans `docs/conteneurs/`.

**Explications**
Trois couches, trois outils : appartenance au réseau (`docker inspect`), nom (DNS embarqué 127.0.0.11, noms de service et alias par réseau), transport (pont, pare-feu de l'hôte). « Nom inconnu » ne se cherche jamais dans le pare-feu ; « délai dépassé » ne se cherche jamais dans le DNS.

**Pièges classiques**
- `docker compose down && up -d` : répare 1, 2 et 3 par accident (si le fichier est bon) et ne dit rien de la cause ; ne répare pas 4.
- Chercher la règle dans `iptables -L` ou `nft list table ip filter` seulement.
- Ajouter `network_mode: host` « pour simplifier ».

**En production chez MédiSphère**
Les noms de service sont un contrat : documentés dans `compose.yaml` et dans `architecture.md`. `ms-verif-conteneurs` peut tester `/pret` de chaque service et alerter avant l'utilisateur. Toute règle de pare-feu d'un hôte de conteneurs est posée par le rôle `pare_feu`, versionnée, et reportée dans la matrice des flux.

---

### M12-E38 — Panne : la construction échoue ou ignore le cache

**Démarche de diagnostic**

```
admin@ctr01:/srv/recette$ sudo docker compose build --progress=plain api 2>&1 | tee /tmp/construction.log | grep -E 'transferring context|CACHED|ERROR|error:' | head
```

**Variante 1 — contexte de 4 Gio sans `.dockerignore`.**

```
#5 [api internal] load build context
#5 transferring context: 4.29GB 41.2s done
admin@ctr01:/srv/recette$ ls -la api/ ; du -sh api/*
-rw-r--r-- 1 root root 4.0G … dump-recette-2026-10.sql
admin@ctr01:/srv/recette$ ls api/.dockerignore
ls: cannot access 'api/.dockerignore': No such file or directory
```

Sans `.dockerignore`, tout le répertoire part au constructeur, y compris la sauvegarde oubliée ; l'étape `COPY . .` du stade de construction la recopie à chaque modification du code (et fait gonfler le cache : `docker buildx du`). Correctif : déplacer la sauvegarde hors du contexte (vers son vrai lieu de stockage, M12-E29 ; ne la supprime pas sans savoir si c'est la seule copie), rétablir le `.dockerignore` (liste blanche ou liste noire : `.git`, `.venv`, `tests`, `*.sql`, `*.dump`…), puis `sudo docker builder prune --filter until=24h` pour rendre le cache gonflé.

**Variante 2 — ordre des couches.**

```
#10 [api construction 4/5] COPY . .
#11 [api construction 5/5] RUN uv sync --locked --no-dev --no-editable
#11 0.512 Downloading fastapi …                  # à chaque modification d'un fichier
```

Le Dockerfile de Lucas copie tout le projet **avant** d'installer les dépendances et a retiré le montage de cache : toute modification d'un fichier invalide la couche `COPY . .`, donc la suivante, donc retélécharge tout. Correctif : rétablir la séquence de référence (copier `pyproject.toml` et `uv.lock`, `uv sync --no-install-project` avec `--mount=type=cache,target=/root/.cache/uv`, puis le code et un second `uv sync`). Mesure attendue : construction après modification d'une ligne en quelques secondes, étape des dépendances `CACHED`.

**Variante 3 — mandataire de l'ancien prestataire + cache purgé.**

```
#12 [api construction 5/7] RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked --no-dev --no-install-project
#12 1.03 error: Failed to fetch: `https://pypi.org/simple/fastapi/`
#12 1.03   Caused by: … dns error … proxy.infoger.lan …
admin@ctr01:/srv/recette$ sudo docker compose config api | sed -n '/build:/,/image:/p'
    build:
      context: /srv/recette/api
      dockerfile: Dockerfile
      args:
        HTTP_PROXY: http://proxy.infoger.lan:3128
        HTTPS_PROXY: http://proxy.infoger.lan:3128
admin@ctr01:~$ sudo docker buildx du | tail -n 2      # cache presque vide : purgé hier soir
```

Deux changements qui se masquent : tant que le cache contenait la couche des dépendances, le mandataire ne servait jamais ; la purge (`docker builder prune -a`, « faire de la place ») a forcé le téléchargement, qui passe par un mandataire qui n'existe plus. `HTTP(S)_PROXY` sont des arguments **prédéfinis** : BuildKit les fournit aux `RUN` sans `ARG`, et ne les écrit pas dans l'historique de l'image (ce qui les rend invisibles dans `docker history`). Correctif : retirer `args` de `compose.yaml` (MédiSphère n'a pas de mandataire ; si un jour il y en a un, il se règle dans `~/.docker/config.json` ou par le rôle, pas dans chaque projet).

**Variante 4 — `.dockerignore` qui exclut `uv.lock`.**

```
#9 [api construction 4/7] COPY pyproject.toml uv.lock ./
#9 ERROR: failed to calculate checksum of ref …: "/uv.lock": not found
admin@ctr01:/srv/recette$ tail -n 2 api/.dockerignore
# Fichiers de verrou de l'éditeur (Lucas)
*.lock
```

Le fichier existe sur le disque mais n'est pas envoyé au constructeur. Correctif : un motif précis (`.#*`, `*.swp` pour les verrous d'éditeur), ou une exception (`!uv.lock`) ; puis `docker build` sans changement : tout `CACHED`.

**Explications**
Le cache de BuildKit est une chaîne : une étape n'est réutilisée que si son instruction et tout ce qu'elle lit (fichiers copiés, montages, arguments) sont identiques, et si toutes les étapes précédentes l'ont été. D'où la règle : ce qui change souvent en dernier. Le contexte est lu en entier à chaque construction (BuildKit ne retransfère que les différences, mais il doit tout parcourir et `COPY .` tout prendre en compte).

**Pièges classiques**
- `--no-cache` « pour être sûr » : masque le problème d'ordre et rallonge tout.
- Corriger la variante 3 en ajoutant `--network host` ou en configurant un mandataire.
- Supprimer la sauvegarde de 4 Gio sans demander : c'est peut-être la seule.

**En production chez MédiSphère**
Hadolint ne voit pas l'ordre des couches ni le `.dockerignore` : la revue le voit, et un indicateur du pipeline aussi (durée de construction, taille du contexte journalisée par `--progress=plain`, comparée à un seuil). Le gabarit `image.yml` exporte le cache vers le registre (M12-E11) : une purge locale ne coûte plus un téléchargement complet.

---

### M12-E39 — Panne : le disque de l'hôte est plein

**Démarche de diagnostic**

```
admin@ctr01:~$ df -h / ; df -i /
/dev/sda1        31G   30G     0 100% /
admin@ctr01:~$ sudo du -xsh /var/lib/docker /var/lib/containerd 2>/dev/null
admin@ctr01:~$ sudo docker system df -v | less
```

`Avail` à 0 pour les utilisateurs alors que root écrit encore : la réserve d'ext4 (5 %, `tune2fs -l | grep Reserved`). PostgreSQL (UID 999) n'écrit plus ses journaux de transactions et refuse les écritures ; `dockerd` (root) fonctionne encore, ce qui laisse diagnostiquer.

**Variante 1 — journal sans rotation.**

```
admin@ctr01:~$ sudo du -sh /var/lib/docker/containers/* | sort -h | tail -n 2
21G  /var/lib/docker/containers/3f2c…
admin@ctr01:~$ sudo docker ps -a --filter id=3f2c --format '{{.Names}} {{.Image}} {{.CreatedAt}}'
trace-lucas recette/mediagenda-api:plateau 2026-10-… 
admin@ctr01:~$ sudo docker inspect -f '{{json .HostConfig.LogConfig}}' trace-lucas
{"Type":"json-file","Config":{"max-size":"100g"}}
admin@ctr01:~$ sudo cat /etc/docker/daemon.json     # log-opts max-size par défaut : contourné par le conteneur
```

Un conteneur de débogage oublié, lancé avec une limite démesurée qui remplace celle du démon. Correctif : arrêter et supprimer **ce** conteneur (`sudo docker rm -f trace-lucas`, son journal part avec lui) ; si le conteneur était utile, le recréer sans option de journal (il hérite de la rotation du démon). On ne supprime jamais le fichier `*-json.log` d'un conteneur vivant (l'espace n'est pas rendu tant que `dockerd` le tient ouvert) ; on peut le tronquer (`truncate -s 0`) en dernier recours.

**Variante 2 — images orphelines et cache de construction.**

```
admin@ctr01:~$ sudo docker images --filter dangling=true
<none>  <none>  1a2b…  … 6.1GB
<none>  <none>  9c8d…  … 5.8GB
admin@ctr01:~$ sudo docker image inspect -f '{{json .Config.Labels}} {{.Created}}' 1a2b
admin@ctr01:~$ sudo docker history lucas/import-essai:latest       # RUN fallocate -l … /var/tmp/jeu-import-N.bin
admin@ctr01:~$ sudo docker buildx du | tail -n 3
```

Chaque reconstruction de `lucas/import-essai:latest` a déplacé l'étiquette et laissé la précédente orpheline (`<none>`), avec une couche de données de plusieurs Gio ; le cache de construction garde aussi ces couches. Correctif : `sudo docker image rm lucas/import-essai:latest`, `sudo docker image prune` (sans `-a` : orphelines seulement), `sudo docker builder prune` (cache inutilisé). Tout cela se recrée ; rien n'est une donnée. Puis expliquer à Lucas qu'un jeu de données n'a rien à faire dans une couche d'image.

**Variante 3 — volume d'exports sans purge.**

```
admin@ctr01:~$ sudo docker system df -v | sed -n '/Local Volumes/,/Build cache/p'
recette_exports   0   18.3GB
admin@ctr01:~$ sudo docker ps -a --filter volume=recette_exports --format '{{.Names}} {{.Status}}'
recette-exports-lucas Created
admin@ctr01:~$ sudo ls -lh "$(sudo docker volume inspect -f '{{.Mountpoint}}' recette_exports)" | head
```

Un volume qui ressemble à la pile (étiquettes Compose `recette`) mais qu'aucun service de `compose.yaml` ne déclare, monté par un conteneur jamais démarré, rempli d'exports quotidiens jamais purgés. **Avant** de supprimer : vérifier que ces exports ne sont pas la seule sauvegarde (ici, ils ne contiennent que des zéros — `head -c 64 … | od -c` — mais en vrai il faudrait demander et, au besoin, copier les derniers vers le stockage de sauvegarde). Puis `sudo docker rm recette-exports-lucas && sudo docker volume rm recette_exports`.

**Commun : prévention.** Rotation par défaut au démon (déjà posée par `docker_engine` : `log-opts` `max-size`/`max-file`, ou pilote `local`) ; interdiction des options de journal dans les `compose.yaml` hors exception écrite ; nettoyage planifié de ce qui est jetable ([minuterie](fichiers/M12-E39/ansible/roles/docker_engine/templates/docker-menage.timer.j2) : `docker image prune -f` et `docker builder prune -f --filter until=168h`, **jamais** `--volumes` ni `-a`) ; seuil d'occupation dans `ms-verif-conteneurs` (alerte à 80 %). Le runbook : [RB-123](fichiers/M12-E39/medisphere/docs/conteneurs/runbooks/RB-123-disque-plein.md).

**Pièges classiques**
- `docker system prune -a --volumes` : supprime aussi l'image de la recette et tout volume non monté à cet instant (la base si la pile est arrêtée).
- Supprimer `/var/lib/docker/containers/*/…-json.log` sous un conteneur vivant.
- Agrandir le disque sans chercher la cause.

---

### M12-E40 — Panne : le service Quadlet ne démarre pas

**Démarche de diagnostic**

```
admin@ctr02:~$ sudo machinectl shell app@
app@ctr02:~$ systemctl --user status recette-cache
app@ctr02:~$ /usr/libexec/podman/quadlet -dryrun -user 2>&1 | head -n 40
```

**Variante 1 — clé inconnue.**

```
app@ctr02:~$ systemctl --user status recette-cache
Unit recette-cache.service could not be found.
app@ctr02:~$ /usr/libexec/podman/quadlet -dryrun -user
quadlet-generator[…]: Loading source unit file /home/app/.config/containers/systemd/recette-cache.container
quadlet-generator[…]: converting "recette-cache.container": unsupported key 'PublishPorts' in group 'Container' in /home/app/.config/containers/systemd/recette-cache.container
```

Le générateur refuse le fichier entier : aucune unité, d'où « could not be found » (et non « failed »). Correctif : `PublishPort=` (singulier ; la clé se répète pour plusieurs ports), `systemctl --user daemon-reload`, `systemctl --user start recette-cache`. Prévention : le rôle Ansible lance le générateur à blanc après avoir déposé les fichiers (et échoue sur une erreur), et la CI d'`plateforme/ansible` fait de même dans Molecule.

**Variante 2 — réseau Quadlet supprimé.**

Selon la version, le générateur signale le réseau Quadlet introuvable et ne génère pas l'unité, **ou** la génère avec `Requires=recette-network.service` et le démarrage échoue :

```
app@ctr02:~$ systemctl --user start recette-cache
Failed to start recette-cache.service: Unit recette-network.service not found.
app@ctr02:~$ systemctl --user cat recette-cache | grep -E 'Requires|After|--network'
app@ctr02:~$ ls ~/.config/containers/systemd/
recette-cache.container
```

`Network=recette.network` désigne un **fichier** Quadlet, pas un réseau Podman : le réseau `recette` existe peut-être encore (`podman network ls`), mais l'unité qui le garantit a disparu. Correctif : restaurer `recette.network` (depuis le rôle Ansible, la source de vérité ; ici depuis `~/recette-archives/` ou le dépôt), `daemon-reload`, démarrage. Prévention : ces fichiers ne s'éditent pas à la main sur l'hôte.

**Variante 3 — *linger* désactivé.**

```
app@ctr02:~$ systemctl --user status        # depuis « sudo -iu app » : Failed to connect to bus: No medium found
admin@ctr02:~$ loginctl show-user app -p Linger -p State
Linger=no
State=closing                                # ou l'utilisateur n'apparaît plus
admin@ctr02:~$ sudo journalctl -u user@1001 --since -2h | tail -n 3      # Stopped User Manager for UID 1001.
```

Sans *linger*, logind ne garde le gestionnaire systemd d'un utilisateur que tant qu'il a une session ; à la déconnexion de la dernière, `user@1001.service` s'arrête et tue tout ce qu'il porte, conteneurs compris. Correctif : `sudo loginctl enable-linger app` (le gestionnaire démarre aussitôt, `default.target` tire `recette-cache`), puis le reporter dans le rôle `podman_hote` (qui le pose déjà : chercher pourquoi il a été retiré, et qui l'a fait : `journalctl _COMM=loginctl`).

**Variante 4 — section `[Install]` retirée, puis redémarrage.**

```
app@ctr02:~$ systemctl --user is-active recette-cache         # inactive
app@ctr02:~$ systemctl --user start recette-cache && systemctl --user is-active recette-cache   # active… jusqu'au prochain redémarrage
app@ctr02:~$ systemctl --user enable recette-cache
Failed to enable unit: Unit /run/user/1001/systemd/generator/recette-cache.service is transient or generated.
app@ctr02:~$ ls /run/user/1001/systemd/generator/default.target.wants/ 2>/dev/null   # recette-cache.service absent
```

Une unité générée ne s'active pas par `enable` : c'est le générateur qui crée le lien `default.target.wants/` **à partir de la section `[Install]`** du fichier Quadlet. Lucas l'a retirée ; le service tournait encore, rien ne se voyait avant le redémarrage. Correctif : rétablir `[Install]` `WantedBy=default.target`, `daemon-reload`, vérifier le lien, puis prouver avec `sudo systemctl restart user@1001.service`.

**Explications**
Quadlet est un **générateur** systemd : à chaque `daemon-reload` (et au démarrage), il lit les fichiers `.container`, `.network`, `.volume`, `.pod`, `.build`… et écrit des unités dans `/run/user/<uid>/systemd/generator/`. Ses erreurs ne s'affichent nulle part ailleurs que dans sa propre sortie (et le journal au démarrage) : d'où l'essai à blanc comme premier réflexe. Le *linger* est la condition pour qu'un service sans privilège existe sans session ([RB-124](fichiers/M12-E40/medisphere/docs/conteneurs/runbooks/RB-124-service-quadlet-en-echec.md)).

**Pièges classiques**
- Écrire une unité à la main dans `~/.config/systemd/user/` « parce que Quadlet ne marche pas » : deux sources de vérité.
- Oublier `daemon-reload` après une modification : l'ancienne unité générée continue de servir.
- Tester en `sudo -iu app` sans `XDG_RUNTIME_DIR` et conclure à une panne de systemd.

---

### M12-E41 — Panne : le conteneur est tué sans prévenir

**Démarche de diagnostic**

```
admin@ctr01:~$ sudo docker events --filter container=recette-api-1 --format '{{.Time}} {{.Action}}' &
admin@ctr01:~$ sudo docker inspect -f 'code={{.State.ExitCode}} oom={{.State.OOMKilled}} redemarrages={{.RestartCount}} memoire={{.HostConfig.Memory}} pids={{.HostConfig.PidsLimit}}' recette-api-1
```

**Variante 1 — limite mémoire de 24 Mio (le noyau tue).**

```
code=137 oom=true redemarrages=6 memoire=25165824 pids=128
… oom
… die
… start
admin@ctr01:~$ sudo journalctl -k --since -10min | grep -i -m2 oom
… Memory cgroup out of memory: Killed process 41235 (python) total-vm:… anon-rss:…
```

Le processus est tué pendant l'import des bibliothèques (il en consomme environ 50 Mio au repos) : aucune ligne de journal de l'application, `OOMKilled: true`, code 137. Correctif : `mem_limit: 256m` (et `memswap_limit` égal, pour ne pas laisser la limite fuir dans l'échange), valeur justifiée par `docker stats` sous charge (M12-E18) avec une marge. Supprimer la limite n'est pas une option : un seul processus pourrait alors affamer l'hôte.

**Variante 2 — limite de 4 processus (l'application s'arrête).**

```
code=3 oom=false redemarrages=4 memoire=268435456 pids=4
admin@ctr01:/srv/recette$ sudo docker compose logs api | grep -o "RuntimeError: can't start new thread" | head -n 1
RuntimeError: can't start new thread
```

`pids.max` compte les **fils d'exécution** : la réserve de connexions PostgreSQL (`psycopg_pool`) démarre plusieurs fils à l'ouverture, le démarrage d'uvicorn échoue (« Application startup failed. Exiting. »). Personne n'a tué le conteneur : il s'est arrêté faute de ressource, et la politique de redémarrage le relance en boucle. Correctif : `pids_limit: 128` (le repos en utilise environ 6 ; la limite protège contre une bombe à fork, pas contre le fonctionnement normal).

**Variante 3 — sonde impossible + « autoheal » maison.**

```
… health_status: unhealthy
… kill
… die
… start
admin@ctr01:~$ sudo docker inspect -f '{{range .State.Health.Log}}{{.ExitCode}} {{.Output}}{{end}}' recette-api-1 | tail -n 1
-1 OCI runtime exec failed: exec failed: unable to start container process: exec: "curl": executable file not found in $PATH
admin@ctr01:~$ systemctl list-timers --all | grep -i heal
… recette-autoheal.timer  recette-autoheal.service
admin@ctr01:~$ systemctl cat recette-autoheal.service ; cat /usr/local/sbin/recette-autoheal
admin@ctr01:~$ journalctl -t recette-autoheal --since -1h
… redémarrage de /recette-api-1
```

Deux défauts qui ne font une panne qu'ensemble : une sonde qui appelle `curl`, absent de l'image (elle échoue **toujours**, code -1), et un script de Lucas qui redémarre tout conteneur `unhealthy` étiqueté `autoheal=true`. Docker seul n'aurait rien fait (« unhealthy » n'est qu'une information) ; le tiers transforme une fausse alerte en coupure. Le journal de l'application ne montre qu'un arrêt propre sur SIGTERM (`docker restart` envoie SIGTERM puis SIGKILL après 10 s). Correctif : sonde exécutable dans l'image (la sonde Python de référence, ou un binaire de sonde fourni par l'image), retrait de l'étiquette et désactivation **et suppression** de la minuterie (`systemctl disable --now recette-autoheal.timer`, fichiers retirés), puis discussion avec Lucas : le redémarrage automatique sur échec de santé existe (Kubernetes, Podman `HealthOnFailure=kill` avec `Restart=`), mais seulement avec une sonde de **vivacité** fiable et un délai de grâce.

**Explications**
L'acteur se lit dans la séquence d'événements : `oom` avant `die` = le noyau ; `die` sans `kill` avec code applicatif = l'application ; `kill` (signal 15 puis éventuellement 9) avant `die` = un tiers ou `docker stop/restart` ; `health_status` juste avant `kill` = un mécanisme qui réagit à la santé. Les journaux de l'application ne peuvent pas montrer un SIGKILL.

**Pièges classiques**
- `restart: always` : boucle plus vite.
- Supprimer les limites mémoire et processus « parce qu'elles tuent l'application ».
- Corriger la sonde en installant `curl` dans l'image (surface d'attaque, et la cause « autoheal » reste).

**En production chez MédiSphère**
`ms-verif-conteneurs` (M12-E28) alerte sur `RestartCount` qui augmente et sur `OOMKilled`. Les limites sont dans les normes (valeur par défaut, exception justifiée). Aucun outil tiers n'a accès au socket Docker sans ADR.

---

### M12-E42 — Panne : le pipeline ne publie plus l'image

**Démarche de diagnostic**

Lire le journal du job **en entier** et situer l'étape :

| Message (extrait représentatif) | Étape | Variante |
|---|---|---|
| `unexpected status from HEAD request … 401 Unauthorized` (ou `failed to authorize`) | authentification au registre | 1 |
| `tls: failed to verify certificate: x509: certificate signed by unknown authority` | confiance TLS | 2 |
| erreurs de création d'espace de noms ou de montage au démarrage de BuildKit sans privilège (`rootlesskit`, `operation not permitted`, `failed to mount`) | exécuteur (options de sécurité) | 3 |
| `ERROR: Job failed: failed to pull image "…" with specified policies [never]: … not found` | exécuteur (politique de tirage) | 4 |

**Reproduction hors CI.**

```
admin@adm01:~$ openssl s_client -connect ctr01.par1.medisphere.internal:5000 -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt </dev/null 2>/dev/null | grep -E 'subject=|issuer=|Verify return'
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://ctr01.par1.medisphere.internal:5000/v2/     # 401 attendu
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' -K ~/.config/workbook/registre-ci.curl https://ctr01.par1.medisphere.internal:5000/v2/   # 200 attendu ; fichier 600 « user = "ci:…" »
admin@runner02:~$ sudo ls -l --time-style=full-iso /etc/gitlab-runner/config.toml
admin@runner02:~$ sudo journalctl -u gitlab-runner --since today | grep -i -E 'config|reload'
```

**Variante 1 — mot de passe du compte `ci` changé d'un seul côté.** Le registre répond 401 au compte `ci` avec le mot de passe de la variable de CI ; la ligne `ci:` du fichier htpasswd a changé (date du fichier, sauvegarde, `docker logs` du registre : « basic authentication challenge … invalid »). Personne ne connaît le nouveau mot de passe : on n'essaie pas de le retrouver, on refait une **rotation complète** : générer un mot de passe (`openssl rand -base64 32`), mettre à jour l'entrée htpasswd par le rôle qui gère le registre (M12-E15 ; `htpasswd -B` dans un conteneur `httpd` si l'outil manque sur `ctr01`), redémarrer le registre si ta version ne relit pas le fichier, mettre à jour la variable protégée et masquée des projets (`REGISTRE_MOT_DE_PASSE` ou le nom choisi en E21), relancer le pipeline. Le registre des secrets dit où vit le mot de passe et qui l'a changé, quand.

**Variante 2 — certificat auto-signé.** `issuer=` égal à `subject=` et `Verify return code: 18 (self-signed certificate)`. Tous les clients échouent, pas seulement la CI (`docker pull` depuis `ctr02`, Skopeo). Correctif : remettre un certificat ACME de step-ca par le mécanisme de M12-E15 (`step ca certificate … --provisioner acme` ou le renouvellement automatique), vérifier que le renouvellement fonctionne (`systemctl list-timers | grep cert-renewer`, ou l'équivalent posé en E15), redémarrer le registre. Ne jamais contourner par `--insecure-registry` ni en ajoutant le certificat auto-signé aux magasins.

**Variante 3 — exceptions de sécurité retirées sur `runner02`.**

```
admin@runner02:~$ sudo grep -n security_opt /etc/gitlab-runner/config.toml
    security_opt = []                    # ou sans les entrées « unconfined »
```

BuildKit sans privilège (ou Buildah) doit créer un espace de noms `user`, monter `/proc` et des systèmes de fichiers dans le conteneur du job : le profil seccomp par défaut de Docker et le profil AppArmor `docker-default` l'interdisent, d'où les exceptions `seccomp:unconfined` et `apparmor:unconfined` décidées en M12-E21 et justifiées dans l'ADR-0120. Lucas les a retirées par souci de durcissement, sans tester. Correctif : rétablir **ces** exceptions (pas `privileged = true`, qui donnerait en plus toutes les capacités et tous les périphériques), par le rôle `gitlab_runner` (la source de vérité), puis expliquer à Lucas l'écart entre « unconfined pour un constructeur sans capacité » et « privilégié ». Aller plus loin : un profil seccomp dédié qui n'autorise que `unshare`, `mount`, `pivot_root` en plus du profil par défaut.

**Variante 4 — `pull_policy = ["never"]` et images purgées.** Le runner ne tire plus aucune image et le ménage de Lucas a supprimé celles du cache local. Correctif : rétablir la politique (`["if-not-present"]` ou `["always", "if-not-present"]` selon E20), par le rôle ; les images reviennent à la demande. L'intention (« ne plus dépendre de Docker Hub ») est légitime : elle se réalise au M13 avec les caches de Harbor, pas en coupant le tirage.

**Clôture** : pipeline relancé au vert, `lab/bin/check 12 42`, puis `lab/bin/break 12 42 --annuler` (qui ne revient pas sur un mot de passe ou un certificat que tu as changés). Le runbook : [RB-125](fichiers/M12-E42/medisphere/docs/conteneurs/runbooks/RB-125-pipeline-ne-publie-plus.md).

**Pièges classiques**
- `privileged = true` : interdit (PLAN §4.10), et inutile.
- Désactiver la vérification TLS dans le job (`--tls-verify=false`, `registry.insecure=true`).
- Changer le mot de passe dans GitLab seulement, ou dans le registre seulement.
- Modifier `config.toml` à la main sans le reporter dans le rôle : le prochain passage d'Ansible redonne la panne… ou la réparation de Lucas.

---

### M12-E43 — Astreinte : la pile de recette est en panne

**Démarche de diagnostic**

Le script combine trois pannes, une par étage : **A** (démarrage de l'API : variable renommée, forme exec, mémoire, sonde + autoheal), **B** (données et réseau : propriétaire du volume, réseau, alias, nftables), **C** (hôte ou voisin : disque plein sous l'une des trois formes, ou MédiDoc 1.1.0-rc1). Leur ordre de traitement compte, parce qu'elles se masquent.

**Premiers 15 minutes : état des lieux, sans rien toucher.**

```
admin@ctr01:~$ df -h / ; sudo docker system df
admin@ctr01:/srv/recette$ sudo docker compose ps -a
admin@ctr01:~$ for s in db valkey api doc; do sudo docker inspect -f "$s {{.State.Status}} code={{.State.ExitCode}} oom={{.State.OOMKilled}} rc={{.RestartCount}} sante={{if .State.Health}}{{.State.Health.Status}}{{end}}" recette-$s-1; done
admin@ctr01:~$ sudo nft list ruleset | grep -c 'table bridge' ; systemctl list-timers --all | grep -v -E 'apt|logrotate|man-db|e2scrub|fstrim'
admin@ctr01:~$ sudo docker ps -a --format '{{.Names}} {{.Status}}' | grep -v '^recette-'
admin@ctr01:/srv/recette$ sudo docker compose config --quiet && echo "compose valide"
```

Premier point à Nadia (exemple) : « 07:05 — Recette MédiAgenda indisponible (API en redémarrage continu), MédiDoc OK, disque de ctr01 à 100 %. Hypothèses : disque plein (cause probable des écritures en échec), configuration de l'API. Prochaine étape : libérer l'espace sans toucher aux données, puis API. Prochain point 07:35. »

**Ordre recommandé.**
1. **L'hôte d'abord** (C) : un disque plein fausse tous les autres diagnostics (la base ne démarre pas, `docker compose` échoue à écrire). Démarche de M12-E39. Si C est MédiDoc, il est indépendant : le traiter quand l'API est rétablie.
2. **Le démarrage de l'API** (A) : tant qu'elle ne tient pas, B est invisible. Démarches de M12-E35 et M12-E41 (code de sortie, `OOMKilled`, minuteries).
3. **Les données et le réseau** (B) : une fois l'API stable, `/pret` révèle la panne B. Démarches de M12-E36 et M12-E37.
4. **Tout revérifier** : `lab/bin/check 12 43` (partie technique) et l'API de bout en bout (création, lecture, annulation d'un rendez-vous de test).

**Post-mortem** : un [exemple rédigé](fichiers/M12-E43/medisphere/docs/socle/post-mortems/2026-10-22-INC-3950.md) pour le tirage « disque plein (journal) + mémoire de l'API + alias supprimé ». Les points que la revue regarde : chronologie horodatée (détection, chaque hypothèse, chaque correction), **détection** (rien n'a alerté avant les utilisateurs : quelle sonde l'aurait fait ?), une cause racine par panne avec la sortie qui la prouve, et des actions vérifiables (« seuil disque dans `ms-verif-conteneurs`, vérifié par `lab/bin/check 12 39` », « MR de revue obligatoire sur `/srv/recette`, qui devient un dépôt »), pas « faire attention ».

**Explications**
Une astreinte multi-causes se perd quand on corrige la première anomalie vue au lieu de la plus basse. La règle : l'hôte, puis le processus, puis ses dépendances ; et après chaque correction, refaire l'état des lieux complet, car une panne masquée apparaît.

**Pièges classiques**
- `docker compose down -v` : la base de recette disparaît (le volume), et deux causes sur trois restent.
- S'arrêter après deux pannes parce que « ça répond ».
- Un post-mortem qui accuse Lucas : les causes sont l'absence de revue sur `/srv/recette`, d'alerte disque, de sonde fiable.

---

### M12-E44 — Sous le capot : un conteneur construit à la main

**Solution**

Les deux parties sont dans des scripts commentés, à lire **ligne par ligne** plutôt qu'à lancer d'un bloc : [`capot-manuel.sh`](fichiers/M12-E44/capot-manuel.sh) (partie 1) et [`capot-runc.sh`](fichiers/M12-E44/capot-runc.sh) (partie 2), et le compte rendu de référence [`sous-le-capot.md`](fichiers/M12-E44/medisphere/docs/conteneurs/sous-le-capot.md).

*Partie 1, l'essentiel.*

```
root@ctr01:~# apt-get install -y skopeo umoci jq
root@ctr01:~# skopeo copy docker://docker.io/library/debian:trixie-slim oci:/srv/capot/oci:trixie
root@ctr01:~# jq . /srv/capot/oci/index.json                    # → empreinte du manifeste
root@ctr01:~# m=$(jq -r '.manifests[0].digest' /srv/capot/oci/index.json | cut -d: -f2)
root@ctr01:~# jq . /srv/capot/oci/blobs/sha256/$m                # config + layers (tar+gzip)
root@ctr01:~# mkdir -p /srv/capot/manuel/{inf,sup,trav,fusion}
root@ctr01:~# for c in $(jq -r '.layers[].digest' /srv/capot/oci/blobs/sha256/$m | cut -d: -f2); do
>   tar -xzf /srv/capot/oci/blobs/sha256/$c -C /srv/capot/manuel/inf; done
root@ctr01:~# unshare --mount --pid --fork --uts --ipc --net --mount-proc=/proc bash     # nouveau shell isolé
root@ctr01:~# mount --make-rprivate /
root@ctr01:~# mount -t overlay overlay -o lowerdir=/srv/capot/manuel/inf,upperdir=/srv/capot/manuel/sup,workdir=/srv/capot/manuel/trav /srv/capot/manuel/fusion
```

Le cgroup (dans un **autre** terminal de l'hôte, avant de lancer le shell à isoler, ou en y déplaçant son PID) :

```
root@ctr01:~# cat /sys/fs/cgroup/cgroup.controllers              # cpuset cpu io memory hugetlb pids rdma misc
root@ctr01:~# mkdir /sys/fs/cgroup/capot-manuel
root@ctr01:~# echo 32M > /sys/fs/cgroup/capot-manuel/memory.max; echo 16 > /sys/fs/cgroup/capot-manuel/pids.max
root@ctr01:~# echo <PID-DU-SHELL> > /sys/fs/cgroup/capot-manuel/cgroup.procs
```

Sur Debian 13, systemd active déjà `memory` et `pids` dans `cgroup.subtree_control` de la racine ; sinon `echo "+memory +pids" > /sys/fs/cgroup/cgroup.subtree_control`. Créer un cgroup directement sous la racine est toléré par systemd mais n'est pas « délégué » : c'est acceptable pour une démonstration, pas pour un service (en production, `systemd-run --scope -p MemoryMax=…` fait la même chose proprement).

Le changement de racine, dans le shell isolé :

```
root@ctr01:~# hostname capot
root@ctr01:~# cd /srv/capot/manuel/fusion && mkdir -p ancienne
root@ctr01:/srv/capot/manuel/fusion# pivot_root . ancienne
root@ctr01:/# umount -l /ancienne && rmdir /ancienne
root@ctr01:/# mount -t proc proc /proc && ps -ef            # PID 1 = ce shell
```

Depuis l'hôte : `nsenter -t <PID> -a ps -ef`, `readlink /proc/<PID>/ns/{pid,mnt,uts,net}` comparé à `/proc/1/ns/*`. Le test de `pids.max` : `for i in $(seq 20); do sleep 100 & done` échoue au 16e (`fork: Resource temporarily unavailable`).

*Partie 2* (validé avec runc 1.5.1) :

```
root@ctr01:~# umoci unpack --image /srv/capot/oci:trixie /srv/capot/bundle        # crée config.json + rootfs
root@ctr01:~# cd /srv/capot/bundle && mv config.json config.umoci.json && runc spec   # ou partir du config.json d'umoci
root@ctr01:/srv/capot/bundle# jq '.process.terminal=false | .process.args=["sleep","infinity"] | .hostname="capot"
   | .root.readonly=true | .linux.cgroupsPath="/capot"
   | .linux.resources={"memory":{"limit":67108864},"pids":{"limit":32}}' config.json > c && mv c config.json
root@ctr01:/srv/capot/bundle# runc run -d capot </dev/null >/srv/capot/capot.log 2>&1
root@ctr01:~# runc list
ID      PID    STATUS    BUNDLE              CREATED   OWNER
capot   3375   running   /srv/capot/bundle   …         root
root@ctr01:~# cat /sys/fs/cgroup/capot/memory.max /sys/fs/cgroup/capot/pids.max     # 67108864  32
```

Le `config.json` produit par `runc spec` contient déjà les espaces `pid`, `network`, `ipc`, `uts`, `mount` (et `cgroup`), les montages de `/proc`, `/dev`, `/sys`, un jeu réduit de capacités et l'utilisateur 0:0 ; `umoci unpack` produit un `config.json` qui reprend `Entrypoint`, `Cmd`, `Env` et `User` de l'image. Pour `ctr` : `ctr -n capot images pull docker.io/library/debian:trixie-slim` puis `ctr -n capot run -d docker.io/library/debian:trixie-slim capot2 sleep infinity` ; `ctr -n moby containers list` montre les conteneurs de Docker (ne pas y toucher). On voit alors `containerd-shim-runc-v2` comme parent du processus : c'est le shim qui permet de redémarrer containerd sans tuer le conteneur.

**Explications**
Un conteneur n'est pas un objet du noyau : c'est un processus ordinaire auquel on a donné ses propres espaces de noms, un cgroup, une racine différente, des capacités réduites et un filtre seccomp. `runc` ne fait rien d'autre que ces appels, pilotés par `config.json` ; containerd et Docker ajoutent la gestion des images (le paquet est extrait et monté par le *snapshotter*), le réseau (CNI ou libnetwork), la supervision (le shim) et l'API.

**Pièges classiques**
- `pivot_root` dans l'espace de noms de l'hôte ou sans `--make-rprivate` : erreur `Invalid argument`, ou démontages propagés à l'hôte.
- Oublier `--fork` avec `--pid` : le shell n'est pas le PID 1 du nouvel espace.
- `runc run -d` sans redirection : la session SSH reste accrochée.
- Oublier de retirer le cgroup (`rmdir`, une fois vide) et le conteneur (`runc delete`).

---

### M12-E45 — Questions expert : conteneurs

1. **137 sans OOM.** 137 = 128 + 9 : SIGKILL. Causes : `docker stop`/`restart` dont le délai de grâce (10 s par défaut) a expiré parce que le processus ignore SIGTERM (vérifier `docker events` : `kill` signal 15 puis 9) ; un tiers qui envoie SIGKILL (script, supervision : `journalctl`, `docker events` montre `kill` avec `signal=9`) ; l'OOM killer **de l'hôte** (pas celui du cgroup) qui a choisi ce processus (`journalctl -k | grep -i "out of memory"` sans « Memory cgroup ») ; `OOMKilled` n'est fiable que pour l'OOM du cgroup. Les autres codes : 143 aurait signifié que SIGTERM a suffi.
2. **PID 1 et signaux.** Le noyau n'applique pas le comportement par défaut des signaux au PID 1 d'un espace de noms : un signal sans gestionnaire installé est ignoré. Un programme qui comptait sur l'arrêt par défaut ne s'arrête donc pas ; il est tué par SIGKILL au bout du délai. `--init` place un petit init (tini) en PID 1 qui relaie les signaux et ramasse les zombies ; `exec` dans un script d'entrée remplace le shell par le programme, qui devient PID 1 et reçoit les signaux (sans `exec`, `sh` les garde). Voir M12-E17.
3. **Stockage containerd (Docker 29).** Les images sont gérées par containerd (snapshotter `overlayfs`, contenus sous `/var/lib/containerd`) : `docker images` peut afficher des tailles différentes (contenu compressé + dépaqueté), garde les index multi-architectures et les attestations ; l'espace consommé se mesure dans `/var/lib/containerd` autant que dans `/var/lib/docker` ; un outil qui parcourait `/var/lib/docker/overlay2` ne trouve plus rien. Les volumes et journaux restent sous `/var/lib/docker`.
4. **900 Mo pour 40.** Image de base complète au lieu de `slim`/distroless (outils inutiles, plus de CVE) ; chaîne de compilation laissée dans l'image finale (pas de multi-étapes : compilateurs utilisables par un attaquant) ; caches de paquets (`apt`, `pip`, `uv`) non nettoyés ou non montés en cache ; fichiers supprimés dans une couche ultérieure (toujours présents dans la couche précédente, secrets compris : `docker history`, Dive montre les fichiers « supprimés » encore présents). Dive donne l'efficacité et les fichiers dupliqués.
5. **Ordre des couches.** Une couche n'est réutilisée que si elle et toutes les précédentes sont identiques ; `COPY . .` change à chaque modification de code et invalide l'installation des dépendances qui suit. Copier d'abord le manifeste et le verrou, installer, puis copier le code. `--mount=type=cache` garde le cache du gestionnaire de paquets **entre** constructions même quand la couche est invalidée (téléchargements évités) sans l'inclure dans l'image ; `.dockerignore` réduit le contexte et évite qu'un fichier sans rapport (`.git`, sauvegarde, `.venv`) invalide `COPY . .`.
6. **Root et `/etc/shadow`.** Podman sans privilège : le root du conteneur est `app` (UID 1001) sur l'hôte ; `/etc/shadow` (root:shadow 640) vu du conteneur appartient à `nobody` (UID non mappé), et la lecture est refusée comme pour `app`. Docker classique sans `userns-remap` : le root du conteneur est le root de l'hôte (UID 0), avec des capacités réduites mais `CAP_DAC_OVERRIDE` par défaut : il lit le fichier monté. D'où la règle : ne jamais monter de fichier sensible, et préférer l'espace `user`.
7. **`--privileged`.** Toutes les capacités, tous les périphériques de l'hôte, ni seccomp ni AppArmor/SELinux, `/sys` et `/proc` en écriture : un root du conteneur est root de l'hôte (montage du disque de l'hôte, chargement de modules). Interdit sur `runner02` parce que n'importe quel job (donc n'importe quelle MR) obtiendrait l'hôte et les secrets des autres jobs. À la place : BuildKit sans privilège ou Buildah avec les seules exceptions `seccomp`/`apparmor` `unconfined` (aucune capacité ajoutée), ou un profil seccomp dédié.
8. **`internal: true`.** Il supprime l'accès à l'extérieur (pas de passerelle, pas de NAT, pas de port publié utilisable) ; il n'empêche pas les conteneurs d'un même réseau de se parler. Pour isoler deux conteneurs d'un projet : réseaux distincts, chaque conteneur ne rejoignant que ceux dont il a besoin (l'API sur `front` et `donnees`, la base sur `donnees` seulement).
9. **Ports publiés et pare-feu.** Docker insère ses règles de DNAT et de filtrage (`nat PREROUTING`, `filter FORWARD`, chaînes `DOCKER*`) : le trafic publié est redirigé **avant** la chaîne `input` de l'hôte, donc une règle `input` ne le voit pas. Pour filtrer le trafic publié : la chaîne `DOCKER-USER` (évaluée avant les règles de Docker), ou ne publier que sur une adresse (`127.0.0.1:8000:8000`). Le trafic entre deux conteneurs d'un même pont est commuté au niveau 2 : il ne passe pas par `forward` des familles `ip`/`inet` (sauf `br_netfilter`), mais par le crochet `forward` de la famille `bridge` (M12-E37).
10. **Go dynamique sur `scratch`.** Avec cgo actif (compilateur C présent, `net` ou `os/user` importés), le binaire est lié dynamiquement et réclame l'interpréteur `/lib64/ld-linux-x86-64.so.2` ; `execve` renvoie ENOENT pour ce fichier absent et le message cite le binaire, d'où « no such file or directory » sur un fichier présent (code 255). Corrections : `CGO_ENABLED=0` (statique), ou une image finale qui fournit la glibc (`distroless/base`, `debian:trixie-slim`).
11. **Quadlet et `enable`.** Les unités générées vivent dans un répertoire de générateur (`/run/…/generator/`) que `systemctl enable` refuse de modifier (« transient or generated ») ; c'est la section `[Install]` du fichier Quadlet qui fait créer par le générateur les liens `WantedBy=`. Au démarrage, systemd lance les gestionnaires des utilisateurs qui ont le *linger* ; sans *linger*, le gestionnaire de `app` n'existe qu'avec une session ouverte, et ses services s'arrêtent avec la dernière.
12. **`:z` et `:Z`.** `:Z` étiquette le contenu `container_file_t` avec les catégories MCS **du** conteneur (privé : un autre conteneur ne peut pas y accéder) ; `:z` sans catégories (partagé entre conteneurs). Risque : réétiqueter un répertoire de l'hôte utilisé par autre chose (`:Z` sur `/home` rend le dossier inaccessible aux services de l'hôte et aux autres conteneurs ; sur `/var/lib/mysql`, MariaDB de l'hôte n'y accède plus). `chcon` change l'étiquette jusqu'au prochain `restorecon` ou réétiquetage complet : la politique, elle, n'a pas changé.
13. **Étiquette contre empreinte.** `mediagenda/api:1.2.0` est un pointeur mobile : quiconque peut pousser dans le dépôt peut le déplacer (Harbor l'empêche au M13 par l'immuabilité). L'empreinte `@sha256:…` désigne un contenu exact. Avantages de l'empreinte : reproductibilité, résistance à la substitution, base pour la signature. Coûts : illisible, mises à jour à outiller (Renovate, M13), et un index multi-architecture a une empreinte différente de chaque manifeste.
14. **Index multi-architecture.** Un index OCI (ou *manifest list*) liste un manifeste par plateforme (`os`, `architecture`, `variant`) ; le moteur choisit celui de la plateforme locale (ou `--platform`). Vérifier sans tirer : `skopeo inspect --raw docker://…:tag | jq '.manifests[].platform'`, `docker buildx imagetools inspect`, ou `regctl manifest get`.
15. **Reproductibilité.** Horodatages (fichiers, couches, configuration : `SOURCE_DATE_EPOCH` et `rewrite-timestamp` de BuildKit), dépendances non figées (verrous `uv.lock`, `go.sum`, paquets `apt` en version ou instantané), images de base mobiles (épinglage par empreinte), plus l'ordre de fichiers et les chemins de compilation (`-trimpath`). Intérêt sécurité : deux constructions indépendantes doivent donner la même empreinte, ce qui permet de vérifier qu'une image publiée vient bien du code revu (attestations, M13).
16. **Sonde sur `/pret`.** Sous Docker, l'état passe à `unhealthy` dès que la base ou le cache tombe : sans conséquence directe, mais trompeur (et dangereux avec un « autoheal », E41). Sous Kubernetes, une sonde de **vivacité** qui dépend de la base fait redémarrer tous les pods de l'application quand la base tombe : une panne de dépendance devient une panne en cascade. `/pret` est une sonde de **disponibilité** ; la vivacité est `/sante`.
17. **Pilotes de journaux.** `json-file` : texte JSON, rotation seulement si configurée, lu par `docker logs` et par la plupart des agents (fichiers) ; `local` : format binaire compressé, rotation par défaut (20 Mo × 5), lu par `docker logs`, peu d'agents le lisent directement ; `journald` : rotation et limites de journald, `docker logs` fonctionne, collecte par l'agent du journal, métadonnées (`CONTAINER_NAME`). Disque plein : `json-file` sans rotation est la cause classique ; journald s'autolimite (`SystemMaxUse`) mais peut perdre des messages.
18. **Shim.** `containerd-shim-runc-v2` est le parent de chaque conteneur : il garde les descripteurs (entrées-sorties, code de sortie) et le dialogue avec `runc` après sa sortie. Comme le processus du conteneur ne dépend ni de containerd ni de dockerd, ceux-ci peuvent redémarrer (mise à jour) et se reconnecter au shim ; `live-restore` dit à dockerd de ne pas arrêter les conteneurs à son arrêt (M12-E26).
19. **Runtimes.** `runc` et `crun` : même modèle (espaces de noms, cgroups, seccomp ; noyau partagé), `crun` plus léger et rapide (C). gVisor (`runsc`) : noyau en espace utilisateur qui intercepte les appels système, isolement fort, coût en performances et compatibilité. Kata Containers : chaque conteneur dans une micro-VM, isolement d'une VM, coût en mémoire et démarrage, exige la virtualisation (imbriquée dans le lab). Pour MédiSphère : `runc` suffit pour son propre code revu ; envisager gVisor/Kata pour du code non maîtrisé (CI d'équipes externes, traitements de fichiers patients non fiables) ou une exigence de cloisonnement fort entre locataires.
20. **Trois façons de ne pas être root.** Docker sans privilège (démon dans l'espace `user` d'un compte) : protège l'hôte d'une évasion, casse les ports < 1024 (contournable), `--network host` partiel, performances réseau (slirp/pasta), certains pilotes de stockage. Podman sans privilège : même principe sans démon, intégration systemd par Quadlet, mêmes limites réseau. `userns-remap` : le démon reste root mais les conteneurs tournent dans une plage d'UID décalée ; protège contre l'évasion d'un root de conteneur, casse le partage de volumes avec l'hôte (UID décalés) et `--privileged`. MédiSphère (ADR-0120, M12-E31) : Podman sans privilège + Quadlet pour l'exécution sur les serveurs, Docker sur `runner02` pour la CI (construction sans démon privilégié).
