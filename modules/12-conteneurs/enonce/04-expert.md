# Module 12 — Palier 4 : Expert

Les applications de MédiSphère tournent en conteneurs sur `ctr01`, `ctr02` et `ctr03`, leurs images sont construites par `runner02` et rangées dans le registre de travail. Nadia Roussel pose la question d'astreinte habituelle : « Et quand un conteneur s'arrête tout seul à 3 h du matin, qui sait quoi regarder ? » Karim Benali a préparé huit pannes, toutes de celles qu'on rencontre la première année : un conteneur qui s'arrête aussitôt, un volume qui refuse d'écrire, une application qui ne trouve plus sa base, une construction qui échoue ou qui n'utilise plus son cache, un disque plein, un service Quadlet qui ne démarre pas, un conteneur tué sans explication, un pipeline qui ne publie plus. Une astreinte en combine trois. Puis tu démontes un conteneur jusqu'aux appels système, et tu passes les questions qu'on pose en entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres aux conteneurs :
- **Lis l'état complet avant les journaux.** `docker inspect` (ou `podman inspect`) dit presque tout : `State.Status`, `State.ExitCode`, `State.OOMKilled`, `State.Error`, `RestartCount`, `State.Health.Log`, les réseaux, les montages, les limites. Le code de sortie oriente : 0 (fin normale), 1-2 (erreur de l'application), 125-127 (le moteur n'a pas pu lancer la commande), 128 + N (tué par le signal N : 137 = SIGKILL, 143 = SIGTERM).
- **Distingue ce qui est déclaré de ce qui tourne.** `compose.yaml`, un fichier Quadlet ou `config.toml` décrivent un état voulu ; le conteneur, l'unité systemd générée ou le runner en sont l'état réel, et les deux peuvent diverger. `docker compose config` montre le fichier tel que Compose le comprend (fusions et variables comprises) ; `docker inspect` montre ce qui tourne ; le générateur Quadlet montre l'unité qu'il produit.
- **Ne supprime rien que tu n'as pas identifié.** `docker system prune -a --volumes`, `docker volume rm`, `podman system reset`, `docker builder prune -a` effacent sans retour. Dans ce palier, **toute** suppression doit viser un objet nommé, dont tu as prouvé qu'il est jetable. Aucune des pannes n'exige de perdre une donnée.

> **Rappels** : tout se lance depuis `adm01`. Sur `ctr01`, `admin` est dans le groupe `docker` (M12-E26 a montré ce que cela vaut) ; les commandes de ce palier sont écrites avec `sudo docker`, ce qui revient au même et laisse une trace dans le journal. Sur `ctr02` et `ctr03`, les conteneurs appartiennent au compte **`app`** : entre dans sa session par `sudo machinectl shell app@` (ou `sudo -iu app`, mais alors `systemctl --user` exige `XDG_RUNTIME_DIR=/run/user/1001`). La documentation est dans `~/medisphere` (variable `WB_DEPOT`). Une réparation à chaud est permise pour rétablir le service ; si elle touche ce qui est décrit par le code (rôle Ansible, `.gitlab-ci.yml`, configuration du runner), reporte-la ensuite par une MR, sinon le prochain passage d'Ansible la défera.

## Règles du jeu des pannes (M12-E35 à M12-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 12 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante ne s'applique pas à ton lab (par exemple `ctr03` éteinte), le script en essaie une autre.
- **Les témoins.** La plupart des pannes visent des objets que le script installe lui-même à la première injection, puis **remet dans leur version de référence avant chaque nouvelle panne** :
  - sur `ctr01`, la **pile de recette** de MédiAgenda : projet Compose `recette` dans `/srv/recette` (services `db` PostgreSQL 18, `valkey`, `migrations`, `api` MédiAgenda publiée sur le port 18000 de `ctr01`, `doc` MédiDoc sur le port 18080 — des ports distincts de ta pile `mediagenda` des paliers 1 à 3, qui continue de tourner à côté — sans S3 : seul `/healthz` y a un sens). Les images `recette/mediagenda-api:plateau` et `recette/medidoc:plateau` sont construites sur place depuis `apps/` du workbook (la première injection prend 5 à 10 minutes). Le mot de passe de la base est dans `/srv/recette/.env` et `secrets/` (à ne pas afficher). Avant chaque injection, tes modifications des fichiers de `/srv/recette` sont **archivées** dans `/srv/recette-archives/<date>/` ; `.env`, `secrets/` et le volume de la base sont conservés ;
  - sur `ctr02` et `ctr03`, le service Quadlet **`recette-cache`** du compte `app` (Valkey, fichiers dans `~app/.config/containers/systemd/`, données dans `~app/recette/cache`).

  **Avant ta première panne**, lis `/srv/recette/compose.yaml` et les deux Dockerfile, puis `~app/.config/containers/systemd/recette-cache.container` : c'est l'état sain, celui que tu devras reconnaître. Ces fichiers ne contiennent aucune cause.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 12 35`) : il doit être vert (sauf la toute première fois, quand les témoins n'existent pas encore). Le script refuse d'injecter si une autre panne du module est active.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- **Quand tu as réparé**, lance `lab/bin/check 12 XX` puis `lab/bin/break 12 XX --annuler` pour **clore** la panne (sinon elle reste marquée active et bloque les suivantes et le mini-projet). Pour la pile de recette, la clôture la remet dans sa version de référence ; pour le registre et `runner02` (M12-E42), elle ne rétablit que ce qui porte encore la marque de la panne et ne revient jamais sur ta réparation. `--annuler` sans avoir réparé est un filet de sécurité, pas un correctif : compte alors l'exercice comme non réussi.
- Les pannes n'agissent que sur `ctr01`, `ctr02`, `ctr03` (une variante de M12-E36) et `runner02`. Jamais sur `git01`, `pve01`, `pbs01` ni sur une VM hors du pool `lab`. **Aucune donnée n'est détruite** ; seuls les objets créés par la panne elle-même sont supprimés à l'annulation.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/socle/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M12-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Attention** : M12-E39 remplit **réellement** le disque de `ctr01` (jusqu'à épuiser l'espace des utilisateurs non privilégiés ; la réserve de root reste). Vérifie avant de l'injecter que rien d'autre ne tourne sur `ctr01` que tu tiendrais à garder (le registre de travail est sur `ctr01` : il n'écrira plus jusqu'à la réparation). M12-E40 peut **redémarrer `ctr02`**. M12-E38 (une variante) et l'annulation de M12-E39 **vident le cache de construction** de `ctr01` : tes constructions suivantes y seront plus lentes une fois, rien d'autre n'est perdu.

> ⚠️ **Attention** : M12-E42 touche le registre de travail et `runner02`, partagés par tous tes pipelines. Ne lance pas de MR importante pendant l'exercice, et ne remplace jamais le mot de passe d'un compte du registre sans mettre à jour, dans la même opération, la variable de CI qui l'utilise.

---

### M12-E35 — Panne : le conteneur s'arrête aussitôt  `BF` `★★`

> **Ticket INC-3935** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, l'API ou MédiDoc de la recette ne répond plus depuis une livraison de Lucas.)* La recette de ce matin est bloquée. Remets le service en route sans perdre la base de recette, et explique-moi comment on aurait pu le voir avant le déploiement.

**Objectifs pédagogiques**
- Lire l'état d'un conteneur qui ne tient pas : statut, code de sortie, erreur du moteur, nombre de redémarrages, journaux du dernier essai.
- Distinguer les trois familles d'arrêt immédiat : l'application refuse de démarrer (configuration), le moteur ne trouve pas quoi exécuter (`ENTRYPOINT`/`CMD`), l'exécutable existe mais ne peut pas être chargé (binaire, architecture, bibliothèques).
- Proposer le contrôle qui aurait arrêté la livraison avant la recette.

**Prérequis** : M12-E03, M12-E05, M12-E08, M12-E10, M12-E23 (RB-120) ; `lab/bin/check 12 35` vert avant l'injection (ou témoins pas encore installés).
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : pile de recette décrite dans les règles du jeu. MédiAgenda s'arrête avec le code 2 et un message explicite quand une variable obligatoire manque (`apps/mediagenda/README.md`). MédiDoc est compilé par un Dockerfile multi-étapes dans `/srv/recette/doc/`. La politique de redémarrage des services est `unless-stopped`.

**Injection** : `lab/bin/break 12 35` (3 variantes).

**Travail demandé**
1. Constate sans rien modifier : `docker compose ps -a`, puis pour le service en cause l'état complet (`docker inspect`) : statut, code de sortie, `State.Error`, `RestartCount`. Que fait la politique de redémarrage dans ton cas ? Le conteneur a-t-il même démarré une fois ?
2. Lis les journaux **du dernier essai** et, s'ils sont vides, explique pourquoi.
3. Compare ce qui tourne à ce qui est déclaré : `docker compose config` pour le service, `docker image inspect` pour l'image (`Entrypoint`, `Cmd`, `User`). Pour une image sans shell, trouve un moyen d'examiner son contenu sans la lancer.
4. Corrige à la racine (fichier de Compose ou Dockerfile), reconstruis si nécessaire, redéploie **ce service seulement** et vérifie qu'il reste démarré.
5. Complète `RB-120 — Un conteneur redémarre en boucle` (M12-E23) dans `docs/conteneurs/runbooks/` d'une section « le conteneur s'arrête dès le démarrage » : lecture du code de sortie, des trois familles de causes et de la commande qui les départage.
6. Réponds à Julien : quel contrôle, dans le pipeline ou dans la revue, aurait vu ce défaut avant la recette ?

**Critères de réussite**
- [ ] L'API et MédiDoc de la recette sont démarrés, sains, et ne redémarrent plus ; `/sante`, `/pret` (API) et `/healthz` (MédiDoc) répondent 200 depuis `adm01`.
- [ ] La base de recette n'a pas été recréée (son volume est le même qu'avant la panne).
- [ ] Ton journal contient le code de sortie, la ligne d'erreur qui prouve la cause et la commande qui l'a montrée ; RB-120 est complété ; la réponse à Julien propose un contrôle automatique.

**Vérification** : `lab/bin/check 12 35`

<details><summary>Indice 1</summary>

`docker inspect -f '{{.State.Status}} {{.State.ExitCode}} {{.RestartCount}} {{.State.Error}}' recette-<service>-1` résume l'essentiel. Un conteneur resté à l'état `created` n'a jamais exécuté une seule instruction de l'application : la réponse est dans `State.Error`, pas dans les journaux.
</details>

<details><summary>Indice 2</summary>

Pour regarder dans une image sans shell : `docker create` puis `docker cp` du fichier vers l'hôte, et les outils de l'hôte (`file`, `ldd`, `readelf -l`). Compare aussi `docker compose config api` avec `/srv/recette-archives/` ou avec ta mémoire de l'état sain.
</details>

<details><summary>Indice 3</summary>

« no such file or directory » sur un fichier qui existe désigne souvent un **autre** fichier que celui qu'on croit : celui que le noyau doit charger pour l'exécuter.
</details>

**Pour aller plus loin** : ajoute au job de construction de MédiDoc (M12-E21) une étape qui lance l'image construite avec `--version` ou `/healthz` (test de fumée) avant la poussée, et un contrôle `file`/`readelf` du binaire produit.

---

### M12-E36 — Panne : « permission denied » sur le volume  `BF` `★★`

> **Ticket INC-3936** — *De : Nadia Roussel*
> *(Le détail s'affiche à l'injection : selon le cas, la base de recette de `ctr01` après une restauration, ou le cache de recette de `ctr02` ou de `ctr03` après un « nettoyage » de Lucas.)* Les journaux parlent de « Permission denied ». Répare sans perdre les données, et ne te contente pas d'un `chmod 777` : Sophie relira.

**Objectifs pédagogiques**
- Raisonner sur l'UID **effectif** d'un processus conteneurisé et sur le propriétaire des fichiers qu'il touche, vus de l'intérieur et de l'hôte.
- Appliquer ce raisonnement aux trois cas usuels : moteur avec démon et utilisateur fixé dans le conteneur, Podman sans privilège (correspondance des UID par l'espace de noms `user`), SELinux (étiquette du fichier, type `container_t` du processus).
- Corriger avec le droit **minimal**, pas avec un élargissement.

**Prérequis** : M12-E06, M12-E07, M12-E14, M12-E24, M12-E25 ; `lab/bin/check 12 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la base de recette tourne en `user: "999:999"` sans aucune capacité (`cap_drop: [ALL]`) : son point d'entrée ne peut donc pas « réparer » les droits lui-même. Le témoin `recette-cache` tourne en `User=999:999` dans l'espace de noms du compte `app` (UID 1001, plage subordonnée `524288:65536`). Sur `ctr03`, SELinux est *enforcing*.

**Injection** : `lab/bin/break 12 36` (3 variantes).

**Travail demandé**
1. Reproduis et lis l'erreur exacte (journal du conteneur ou de l'unité). Quel processus, sous quel UID, tente quelle opération sur quel chemin ?
2. Compare les propriétaires et les droits vus **de l'hôte** et **du conteneur** (pour Podman sans privilège : `podman unshare`). Sur `ctr03`, compare aussi les contextes SELinux (`ls -Z`) et cherche le refus dans le journal d'audit.
3. Trouve l'opération humaine qui a produit cet état (commande de restauration, recréation de répertoire, retouche du fichier Quadlet) et explique pourquoi elle a cet effet.
4. Corrige avec le droit minimal (propriétaire, mode, étiquette ou option de montage), sans `chmod 777`, sans `--privileged`, sans désactiver SELinux, puis vérifie que les données d'avant la panne sont toujours là.
5. Écris dans ton journal la procédure correcte pour l'opération de Lucas (restaurer un volume, recréer un répertoire de données sans privilège, monter un répertoire sous SELinux).

**Critères de réussite**
- [ ] La base de recette est saine ; ses données appartiennent à l'UID 999 en mode 700 ; `/pret` répond 200.
- [ ] Le témoin `recette-cache` de `ctr02` (et de `ctr03`) est actif et répond ; son répertoire de données appartient à l'UID du conteneur et non à `app` ; sur `ctr03`, il porte le type `container_file_t` et le journal d'audit ne montre plus de refus.
- [ ] Ton journal contient l'erreur initiale, les propriétaires vus des deux côtés et la procédure correcte ; aucun droit n'a été élargi au-delà du nécessaire.

**Vérification** : `lab/bin/check 12 36`

<details><summary>Indice 1</summary>

`docker volume inspect` donne le chemin du volume sur l'hôte ; `stat -c '%u:%g %a'` donne propriétaire et mode. Pour Podman sans privilège, `podman unshare ls -ln` montre les UID tels que le conteneur les voit, et `/etc/subuid` donne la règle de conversion.
</details>

<details><summary>Indice 2</summary>

Sur `ctr03` : `sudo ausearch -m avc -ts recent`, `ls -Zd`, et relis la ligne `Volume=` du fichier Quadlet. Une étiquette se pose de façon durable par l'option de montage prévue pour cela, pas par un `chcon` qui sera défait au prochain `restorecon`.
</details>

**Pour aller plus loin** : compare les options `:U` de Podman et `chown` explicite, et note dans `docs/conteneurs/normes.md` celle que MédiSphère retient pour les répertoires de données sans privilège.

---

### M12-E37 — Panne : l'application ne joint plus sa base  `BF` `★★★`

> **Ticket INC-3937** — *De : Julien Petit*
> Depuis ce matin, l'API de recette (`ctr01`) répond sur `/sante` mais `/pret` échoue (503, ou plus de réponse du tout) et toute création de rendez-vous échoue : elle ne joint plus PostgreSQL. La base, elle, est saine. *(Le contexte de la veille s'affiche à l'injection.)* Rétablis le service, puis dis-moi ce qu'il fallait faire à la place.

**Objectifs pédagogiques**
- Diagnostiquer couche par couche la connexion d'un conteneur à un autre : appartenance aux réseaux, résolution par le DNS embarqué (noms de service et alias), routage dans le pont, filtrage de l'hôte.
- Comprendre ce que fait (et ne fait pas) `internal: true`, et ce qui sépare l'état déclaré dans `compose.yaml` de l'état des réseaux d'un conteneur en cours d'exécution.
- Savoir où le pare-feu de l'hôte peut toucher le trafic **entre** conteneurs d'un même pont.

**Prérequis** : M12-E07, M12-E08, M00 (nftables) ; `lab/bin/check 12 37` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : l'API joint la base par le nom `base-recette` (voir `MEDIAGENDA_DB_URL`) et le cache par `valkey`. Les réseaux de la pile sont `recette_front` et `recette_donnees` (`internal: true`). `/pret` interroge PostgreSQL et Valkey et donne le détail dans son corps. L'image de l'API contient Python, pas `ping` ni `nc`.

**Injection** : `lab/bin/break 12 37` (4 variantes).

**Travail demandé**
1. Reproduis (`curl` de `/pret` avec un délai) et lis le détail : quelle dépendance, quelle erreur dans le journal de l'API (« nom inconnu », « refusé », « délai dépassé ») ? Ce mot oriente toute la suite.
2. Depuis le conteneur de l'API, teste dans l'ordre la résolution du nom puis l'ouverture TCP, avec ce qu'offre l'image (un interpréteur Python suffit). Fais la même chose avec le nom du service `db`.
3. Compare l'état déclaré (`docker compose config`) et l'état réel (`docker inspect`, `docker network inspect`) : sur quels réseaux sont l'API et la base, sous quels noms et alias ?
4. Si le nom se résout et que TCP n'aboutit pas, inspecte le pare-feu de l'hôte en entier (`nft list ruleset`), pas seulement les règles de Docker.
5. Corrige à la racine, de façon durable (un `docker compose up -d` qui « répare » sans que tu saches pourquoi ne compte pas), et vérifie que la correction survit à une recréation de la pile.
6. Réponds à Julien : comment fallait-il réaliser ce que voulaient Lucas ou InfoGér (isolement de la base, nettoyage, débogage, durcissement) sans couper l'application ?

**Critères de réussite**
- [ ] `/pret` répond 200 ; depuis le conteneur de l'API, `base-recette:5432` et `valkey:6379` se résolvent et s'ouvrent en moins de 3 s.
- [ ] L'API et la base partagent un réseau ; aucune règle du pare-feu de l'hôte ne jette le trafic vers PostgreSQL.
- [ ] Ton journal contient l'erreur initiale, les tests de résolution et de connexion, la comparaison déclaré/réel et la réponse à Julien.

**Vérification** : `lab/bin/check 12 37`

<details><summary>Indice 1</summary>

`docker exec recette-api-1 python -c "import socket; print(socket.getaddrinfo('base-recette', 5432))"` puis `socket.create_connection((…), 3)`. Une résolution qui échoue et une connexion qui pend ne se cherchent pas au même endroit.
</details>

<details><summary>Indice 2</summary>

`docker inspect -f '{{json .NetworkSettings.Networks}}' recette-api-1 | jq` liste les réseaux réellement rattachés et les alias ; `docker compose config` ce qui devrait l'être. Un réseau « interne » empêche la sortie vers l'extérieur ; il n'isole pas deux conteneurs qui y sont tous les deux.
</details>

<details><summary>Indice 3</summary>

Une connexion refusée et une connexion qui pend ne viennent pas du même endroit : la seconde suggère un paquet jeté en route. Liste **toutes** les tables de `nft list ruleset`, quelle que soit leur famille, et demande-toi lesquelles voient le trafic entre deux conteneurs d'un même pont.
</details>

---

### M12-E38 — Panne : la construction échoue ou ignore le cache  `BF` `★★`

> **Ticket INC-3938** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : selon le cas, la reconstruction de l'image de recette de l'API échoue, ou elle prend plusieurs minutes au lieu de quelques secondes.)* Sur `ctr01`, dans `/srv/recette` : `sudo docker compose build api`. L'image doit se reconstruire correctement **et** vite. Explique-moi aussi comment on s'en serait aperçu en revue.

**Objectifs pédagogiques**
- Lire une construction BuildKit en mode `--progress=plain` : chargement du contexte (taille), étapes `CACHED`, étape en échec et sa vraie cause.
- Relier la vitesse d'une construction à l'ordre des couches, au contexte envoyé (`.dockerignore`) et aux montages de cache.
- Retrouver ce que Compose transmet réellement à la construction (`build.args`, mandataires) et ce que fait une purge du cache.

**Prérequis** : M12-E05, M12-E11, M12-E16 ; `lab/bin/check 12 38` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : contexte de construction `/srv/recette/api` (copie de `apps/mediagenda` avec le Dockerfile et le `.dockerignore` de référence). La construction télécharge les dépendances depuis PyPI par `uv`. `ctr01` sort vers Internet directement : MédiSphère n'a pas de mandataire HTTP.

**Injection** : `lab/bin/break 12 38` (4 variantes).

**Travail demandé**
1. Reproduis avec `sudo docker compose build --progress=plain api` et garde la sortie complète dans un fichier. Pour une construction lente, relance-la **sans rien changer**, puis après avoir modifié une ligne de code (sur une copie si tu préfères) : quelles étapes sont `CACHED`, combien d'octets part dans le contexte ?
2. Pour un échec, isole la première erreur réelle (pas la dernière ligne) et la commande qui la produit.
3. Compare les fichiers en cause à l'état sain que tu as lu au début du palier (`/srv/recette-archives/` peut t'aider) et à ce que Compose transmet (`docker compose config`).
4. Corrige à la racine, puis mesure : temps d'une construction sans changement et après modification d'une ligne de code.
5. Réponds à Julien : quelles règles Hadolint, quelle relecture de MR ou quel indicateur de pipeline auraient signalé ce défaut ?

**Critères de réussite**
- [ ] `docker compose build api` réussit ; le contexte envoyé fait moins de 50 Mo ; une modification du code ne relance pas l'installation des dépendances.
- [ ] Aucun mandataire injoignable n'est transmis à la construction.
- [ ] Ton journal contient les mesures avant et après (taille du contexte, étapes en cache, durée) et la réponse à Julien.

**Vérification** : `lab/bin/check 12 38` (il construit l'image deux fois dans une copie temporaire du contexte : une à trois minutes).

<details><summary>Indice 1</summary>

Dans la sortie `--progress=plain`, cherche `transferring context:` et les lignes `CACHED` ; `docker buildx du` et `docker system df` montrent le cache de construction. Une étape `COPY` n'est en cache que si **tous** les fichiers qu'elle copie sont inchangés.
</details>

<details><summary>Indice 2</summary>

`docker compose config api` affiche la section `build` complète, y compris `args`. Les variables `HTTP_PROXY`/`HTTPS_PROXY` sont des arguments prédéfinis que BuildKit passe aux instructions `RUN` sans qu'aucun `ARG` ne les déclare.
</details>

---

### M12-E39 — Panne : le disque de l'hôte est plein  `BF` `★★`

> **Ticket INC-3939** — *De : Nadia Roussel*
> Alerte de cette nuit : le disque de `ctr01` est plein. Les créations de rendez-vous de la recette échouent, la base de recette se plaint de « No space left on device ». Lucas propose de « faire un `docker system prune -a --volumes` et on n'en parle plus » : surtout pas avant d'avoir compris ce qui a rempli le disque et ce qu'on peut supprimer sans rien perdre.

**Objectifs pédagogiques**
- Localiser ce qui occupe le disque d'un hôte de conteneurs : journaux des conteneurs, images et couches, cache de construction, volumes, et les outils qui les mesurent.
- Supprimer **seulement** ce qui est identifié comme jetable, en commençant par ce qui ne coûte rien à recréer.
- Empêcher la récidive : rotation des journaux, nettoyage planifié, alerte d'occupation.

**Prérequis** : M12-E18, M12-E28, M12-E29 ; `lab/bin/check 12 39` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : `ctr01` a un seul système de fichiers de 32 Go, qui porte `/var/lib/docker` (volumes, journaux des conteneurs) et `/var/lib/containerd` (images et couches, stockage containerd de Docker 29). Le rôle `docker_engine` (M12-E02) pose une rotation des journaux par défaut dans `daemon.json`. Ext4 réserve une partie du disque à root : un processus non privilégié voit le disque plein avant `dockerd`.

**Injection** : `lab/bin/break 12 39` (3 variantes ; le remplissage prend une à trois minutes).

**Travail demandé**
1. Constate : `df -h`, `df -i`, puis répartis l'occupation entre `/var/lib/docker` et `/var/lib/containerd` (`du -xsh`). Que voit PostgreSQL (UID 999) que root ne voit pas encore ?
2. Interroge le moteur : `docker system df -v`. Quel objet (conteneur, image, cache, volume) explique l'essentiel ? Qui l'a créé, quand, avec quelles options ?
3. Avant toute suppression, écris dans ton journal la liste de ce que tu vas supprimer et pourquoi c'est jetable (personne ne l'utilise, il se recrée, ou il est sauvegardé). Libère l'espace en visant ces objets **par leur nom**.
4. Traite la cause : une option qui contourne la rotation, une habitude de construction, une donnée sans purge. Corrige-la là où elle est décidée.
5. Rédige `RB-123 — Hôte de conteneurs : disque plein` dans `docs/conteneurs/runbooks/` : mesures dans l'ordre, ce qu'on peut supprimer sans risque et ce qu'on ne supprime jamais sans accord, prévention (rotation par défaut, nettoyage planifié de ce qui est jetable, seuil d'alerte de `ms-verif-conteneurs`).

**Critères de réussite**
- [ ] Le disque de `ctr01` est occupé à moins de 85 % avec au moins 3 Gio disponibles ; la pile de recette est saine et `/pret` répond 200.
- [ ] Aucun conteneur ne garde un journal `json-file` sans limite raisonnable ; la rotation par défaut du démon est en place ; le cache de construction et les volumes inutilisés ne pèsent plus des gigaoctets.
- [ ] Les données de la recette sont intactes (aucun volume de la pile supprimé) ; RB-123 est publié.

**Vérification** : `lab/bin/check 12 39`

<details><summary>Indice 1</summary>

`docker system df -v` détaille par image, conteneur, volume et entrée de cache. `docker inspect -f '{{.LogPath}} {{json .HostConfig.LogConfig}}'` donne le fichier de journal et ses options. `docker volume ls` et `docker ps -a --filter volume=<nom>` disent qui monte un volume.
</details>

<details><summary>Indice 2</summary>

Images « orphelines » (`<none>`) et cache de construction se recréent ; un volume nommé, jamais sans avoir vérifié son contenu ; un journal se tronque ou se fait tourner, il ne se supprime pas sous un conteneur qui l'écrit.
</details>

---

### M12-E40 — Panne : le service Quadlet ne démarre pas  `BF` `★★★`

> **Ticket INC-3940** — *De : Karim Benali*
> *(Le détail s'affiche à l'injection : selon le cas, après une retouche des fichiers Quadlet, une déconnexion de Lucas ou un redémarrage de `ctr02`.)* Remets le service `recette-cache` en service de façon durable (il doit survivre à un redémarrage de `ctr02` et à la déconnexion de tout le monde), et dis-moi comment tu l'as diagnostiqué.

**Objectifs pédagogiques**
- Suivre la chaîne Quadlet de bout en bout : fichier `.container`/`.network` → générateur systemd (au `daemon-reload`) → unité générée → gestionnaire systemd de l'utilisateur → conteneur.
- Lancer le générateur à blanc pour lire ses erreurs, et savoir pourquoi une unité générée ne s'active pas par `systemctl enable`.
- Comprendre le rôle de la persistance de session (*linger*) pour des services sans privilège.

**Prérequis** : M12-E06, M12-E14, M12-E30 ; `lab/bin/check 12 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : fichiers Quadlet du compte `app` dans `~app/.config/containers/systemd/` (`recette-cache.container`, `recette.network`). Podman 5.4 sur `ctr02` : `podman quadlet list` n'existe pas encore (5.6), le générateur est `/usr/libexec/podman/quadlet` (aussi appelé par `/usr/lib/systemd/user-generators/podman-user-generator`). Consulte `man podman-systemd.unit` pour les clés admises et les options de débogage.

**Injection** : `lab/bin/break 12 40` (4 variantes ; l'une redémarre `ctr02`).

**Travail demandé**
1. Constate en tant que `app` : `systemctl --user status recette-cache`, `systemctl --user list-units 'recette*'`, `journalctl --user -u recette-cache`. L'unité existe-t-elle seulement ? Si `systemctl --user` ne répond pas, demande-toi d'abord pourquoi (en `admin` : `loginctl`).
2. Lance le générateur à blanc et lis ce qu'il dit des fichiers du compte. Compare l'unité générée à ce que tu attends (dépendances, `ExecStart`, section `[Install]`).
3. Trouve la cause et corrige-la à la racine, sans contourner Quadlet (pas d'unité écrite à la main dans `~/.config/systemd/user/`).
4. Prouve la durabilité : le service revient après `sudo systemctl restart user@1001.service` (ou un redémarrage de `ctr02`) et après la fermeture de toutes les sessions de `app`.
5. Rédige `RB-124 — Service Quadlet en échec` dans `docs/conteneurs/runbooks/` : « l'unité n'existe pas », « elle existe mais ne démarre pas », « elle tourne mais ne revient pas au démarrage », avec la commande qui tranche chaque cas.

**Critères de réussite**
- [ ] Le générateur traite `recette-cache` sans erreur ; le service est actif, répond, et il est tiré par `default.target`.
- [ ] La persistance de session de `app` est active ; le service survit au redémarrage du gestionnaire de `app`.
- [ ] Ton journal contient la sortie du générateur à blanc et la cause ; RB-124 est publié.

**Vérification** : `lab/bin/check 12 40`

<details><summary>Indice 1</summary>

`/usr/libexec/podman/quadlet -dryrun -user` (en tant que `app`) affiche les unités qu'il produirait, et ses erreurs. « Unit … not found » après un `daemon-reload` signifie souvent que le générateur a refusé le fichier, pas que le fichier manque.
</details>

<details><summary>Indice 2</summary>

`loginctl show-user app -p Linger` ; `systemctl --user list-dependencies default.target` ; `systemctl --user cat recette-cache` (l'unité générée, dans `/run/user/1001/systemd/generator/`).
</details>

---

### M12-E41 — Panne : le conteneur est tué sans prévenir  `BF` `★★★`

> **Ticket INC-3941** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : selon le cas, l'API de recette redémarre sans cesse depuis une « passe d'optimisation », ou elle est coupée toutes les une à deux minutes sans erreur dans ses journaux.)* Trouve qui ou quoi arrête le conteneur, prouve-le, et corrige sans retirer les protections utiles.

**Objectifs pédagogiques**
- Identifier **l'acteur** d'un arrêt : le noyau (OOM), l'application elle-même (ressource refusée), le moteur (politique de redémarrage), ou un tiers (script, supervision, humain).
- Utiliser `docker events`, `State.OOMKilled`, `State.Health.Log`, `journalctl` et le journal du noyau pour prouver l'acteur et l'instant.
- Régler des limites réalistes (mémoire, processus) et une sonde de santé qui teste vraiment l'application.

**Prérequis** : M12-E17, M12-E18, M12-E24, M12-E28 ; `lab/bin/check 12 41` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : l'API de recette consomme environ 50 Mio et une demi-douzaine de fils d'exécution au repos (`docker stats`). Docker n'arrête **jamais** de lui-même un conteneur « unhealthy » : l'état de santé est une information, pas une action (contrairement à Kubernetes, M14).

**Injection** : `lab/bin/break 12 41` (3 variantes).

**Travail demandé**
1. Suis les événements du conteneur en direct pendant au moins un cycle (`docker events --filter container=…`) et note la séquence exacte (`health_status`, `kill`, `die`, `oom`, `start`, `restart`) avec les horodatages.
2. Pour chaque arrêt : code de sortie, `OOMKilled`, dernière ligne de journal de l'application, message du noyau (`journalctl -k`). L'application a-t-elle reçu un signal, lequel, de qui ?
3. Si l'arrêt vient d'un tiers, trouve-le sur l'hôte (unités et minuteries systemd, tâches planifiées, conteneurs qui montent le socket Docker) et prouve le lien (horodatages).
4. Corrige : limites réalistes mais présentes, sonde de santé exécutable dans l'image, aucun mécanisme qui redémarre l'application sur une fausse alerte. Justifie chaque valeur.
5. Réponds à Julien en quelques lignes : pourquoi « ajouter `restart: always` » ou « retirer les limites » n'aurait rien résolu.

**Critères de réussite**
- [ ] L'API est saine et ne redémarre plus (aucun arrêt, `kill`, OOM ni redémarrage pendant plusieurs minutes) ; sa sonde de santé réussit.
- [ ] Une limite mémoire d'au moins 128 Mio et une limite de processus d'au moins 64 sont en place.
- [ ] Ton journal contient la séquence d'événements et la preuve de l'acteur ; la réponse à Julien est écrite.

**Vérification** : `lab/bin/check 12 41` (un peu plus d'une minute)

<details><summary>Indice 1</summary>

Code 137 avec `OOMKilled: true` : le noyau. Code 137 ou 143 sans OOM : quelqu'un a envoyé un signal. Code non nul après une exception : l'application. `docker inspect -f '{{json .State.Health}}'` montre la sortie des derniers essais de la sonde.
</details>

<details><summary>Indice 2</summary>

`systemctl list-timers --all`, `journalctl --since "-10 min"` sans filtre, et une recherche des conteneurs ou services qui parlent au socket Docker. Une sonde de santé s'exécute **dans** l'image : elle ne peut appeler que ce que l'image contient.
</details>

---

### M12-E42 — Panne : le pipeline ne publie plus l'image  `BF` `★★★`

> **Ticket INC-3942** — *De : Julien Petit*
> Depuis ce matin, le pipeline de `mediagenda/api` (et ceux des autres applications) ne publie plus l'image dans le registre de travail de `ctr01` : le job de construction ou de publication échoue sur `runner02`. Personne n'a touché au `.gitlab-ci.yml`. Lucas propose de « passer le runner en `privileged = true`, comme tout le monde » : Sophie a déjà dit non.

**Objectifs pédagogiques**
- Situer l'étage d'une chaîne de publication en échec : exécuteur (tirage de l'image du job, options de sécurité), construction sans privilège, authentification au registre, confiance TLS.
- Lire le journal d'un job GitLab comme un journal d'incident, et reproduire l'étape en cause hors de la CI (depuis `runner02` ou `adm01`).
- Corriger sans affaiblir la sécurité : ni mode privilégié, ni `--insecure`, ni secret en clair.

**Prérequis** : M12-E15, M12-E20, M12-E21 ; le pipeline de main de `mediagenda/api` vert et `lab/bin/check 12 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : registre de travail `https://ctr01.par1.medisphere.internal:5000` (M12-E15 : `registry:3`, htpasswd, certificat ACME de step-ca) ; compte de publication `ci`, dont le mot de passe est une variable protégée et masquée des projets ; `runner02` lit `/etc/gitlab-runner/config.toml` et le relit tout seul quand il change. La panne ne touche **ni** GitLab **ni** les projets.

**Injection** : `lab/bin/break 12 42` (4 variantes), puis relance le pipeline de main de `mediagenda/api`.

**Travail demandé**
1. Lis le journal du job en échec en entier. Quelle étape (préparation de l'exécuteur, tirage d'image, démarrage du constructeur, construction, authentification, poussée) ? Quel message exact ?
2. Reproduis l'étape hors de la CI avec le moins de privilèges possible : `openssl s_client` vers le registre, `curl` sur `/v2/` avec et sans identifiants (lus depuis un fichier, jamais tapés en clair), lecture de `config.toml` sur `runner02`, `docker pull` d'une image de job.
3. Trouve ce qui a changé et quand (dates des fichiers, journal du conteneur du registre, `journalctl -u gitlab-runner`).
4. Corrige là où est la cause. Si un secret doit changer, change-le **des deux côtés** (registre et variable de CI) et note l'emplacement dans le registre des secrets ; si une option de sécurité doit être rétablie, rétablis le minimum nécessaire et justifie-le.
5. Relance le pipeline jusqu'au vert, puis rédige `RB-125 — Le pipeline ne publie plus l'image` dans `docs/conteneurs/runbooks/` : arbre de décision par étape, commande de reproduction de chaque étape, ce qui est interdit (mode privilégié, `--insecure`, désactivation de la vérification TLS).

**Critères de réussite**
- [ ] Le dernier pipeline de main de `mediagenda/api`, relancé après l'injection, a réussi, job de construction et de publication compris.
- [ ] Le registre présente un certificat de la PKI MédiSphère valide et exige une authentification ; `runner02` n'a aucun runner en mode privilégié ni de politique de tirage `never` seule.
- [ ] Ton journal contient le message d'erreur initial, la reproduction hors CI et la cause ; RB-125 est publié.

**Vérification** : `lab/bin/check 12 42`

<details><summary>Indice 1</summary>

`openssl s_client -connect ctr01.par1.medisphere.internal:5000 -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt </dev/null | head` : qui a signé le certificat présenté ? `curl -s -o /dev/null -w '%{http_code}' -K <fichier>` permet de passer des identifiants sans les exposer dans la ligne de commande.
</details>

<details><summary>Indice 2</summary>

Sur `runner02` : `sudo ls -l --time-style=full-iso /etc/gitlab-runner/` et `sudo journalctl -u gitlab-runner --since today`. Une construction sans démon privilégié a besoin de créer des espaces de noms et de monter des systèmes de fichiers : relis dans M12-E21 ce que tu as autorisé pour cela, et pourquoi.
</details>

---

### M12-E43 — Astreinte : la pile de recette est en panne  `BF` `★★★★`

> **Ticket INC-3943** — *De : Nadia Roussel (responsable astreinte) — priorité P2*
> Tu es d'astreinte. *(Les remontées s'affichent à l'injection : trois symptômes, d'étages différents.)* L'équipe de Julien lance sa campagne de tests de non-régression à 9 h. Rétablis la pile complète (API, base, cache, MédiDoc), tiens-moi informée toutes les 30 min (#astreinte), puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Mener un diagnostic quand plusieurs causes se superposent et se masquent : établir un état des lieux complet avant d'agir, traiter dans l'ordre qui rend les autres observables.
- Communiquer pendant l'incident (points d'étape courts, factuels, horodatés).
- Rédiger un post-mortem sans reproche, avec des actions vérifiables.

**Prérequis** : M12-E35 à M12-E42 ; M00-E46 (modèle de post-mortem) ; `lab/bin/check 12 43` (partie technique) vert avant l'injection.
**Durée indicative** : 1 h 30 (rétablissement) + 45 min (post-mortem), temps cible.

**Contexte technique** : trois pannes simultanées sur `ctr01`, une par étage (démarrage de l'API ; données et réseau ; hôte ou service voisin), tirées parmi les mécanismes des exercices précédents, sans indication de leur nombre exact dans les remontées. Modèle : `modules/00-lab/ressources/M00-E46/modele-post-mortem.md`.

**Injection** : `lab/bin/break 12 43` (5 à 10 minutes).

**Travail demandé**
1. **Premiers 15 minutes** : état des lieux sans rien modifier (hôte, moteur, chaque service de la pile, réseaux, pare-feu, minuteries), premier point à Nadia : impact, hypothèses, prochaine étape.
2. **Rétablissement** : traite les causes dans l'ordre qui rend les suivantes visibles ; après chaque correction, revérifie l'ensemble. Garde les preuves (sorties de commandes) au fur et à mesure.
3. **Points d'étape** toutes les 30 minutes (dans ton journal, au format d'un message de canal : heure, état, prochaine action, besoin éventuel).
4. **Post-mortem** `docs/socle/post-mortems/<AAAA-MM-JJ>-INC-3943.md` : résumé, impact, chronologie, détection (qui a vu quoi, quand, qu'est-ce qui aurait dû alerter), causes racines (une par panne, avec la sortie de diagnostic qui la prouve), ce qui a bien marché, actions (responsable, échéance, vérification). Publie-le par MR.

**Critères de réussite**
- [ ] Toute la pile de recette est saine et stable (contrôles de M12-E35, E36, E37, E39 et E41 verts) ; aucune panne du module n'est encore active.
- [ ] Le post-mortem est commité, avec chronologie, détection, au moins trois causes racines prouvées par des sorties de diagnostic, et des actions vérifiables.
- [ ] Ton journal contient l'état des lieux initial et les points d'étape.

**Vérification** : `lab/bin/check 12 43` (3 à 4 minutes)

<details><summary>Indice 1</summary>

Un service qui ne démarre pas cache tout ce qui se passe après lui : tant que l'API ne tient pas, tu ne peux pas savoir si elle joindrait sa base. Fais d'abord la liste de **tout** ce qui est anormal (`df`, `docker compose ps -a`, `docker inspect` de chaque service, `nft list ruleset`, `systemctl list-timers`), puis ordonne.
</details>

<details><summary>Indice 2</summary>

`/srv/recette-archives/` ne contient pas l'état de cette nuit (il est archivé **avant** l'injection) ; l'état sain est celui que tu connais depuis le début du palier. Compare-lui ce qui tourne.
</details>

---

### M12-E44 — Sous le capot : un conteneur construit à la main  `LAB` `★★★★`

> **Ticket PLAT-1344** — *De : Karim Benali*
> Pour la formation des nouveaux arrivants, je veux une démonstration qui enlève la magie : un conteneur fait à la main, avec les commandes du noyau, puis le même avec `runc` seul, sans Docker ni Podman. Écris-la pour qu'un admin système la rejoue en une heure.

**Objectifs pédagogiques**
- Construire l'isolement d'un processus pièce par pièce : espaces de noms (`unshare`, `nsenter`), cgroup v2 à la main sous `/sys/fs/cgroup`, système de fichiers en couches (overlayfs), changement de racine (`pivot_root`).
- Comprendre le **paquet OCI** (*bundle* : `config.json` + `rootfs`) et ce que `runc` en fait.
- Relier chaque champ de `config.json` à une des pièces construites à la main.

**Prérequis** : M12-E01, M12-E04, M12-E09, M12-E24.
**Durée indicative** : 3 à 4 h.

**Contexte technique** : sur `ctr01` (Debian 13, noyau 6.12, cgroup v2 seul, `runc` 1.5 et `ctr` fournis par `containerd.io`). Installe `skopeo` et `umoci` (paquets Debian 13, `umoci` 0.4.7) pour la durée de l'exercice. Tout se fait en root (`sudo -i`) dans des répertoires dédiés : `/srv/capot/manuel/` (partie 1) et `/srv/capot/bundle/` (partie 2).

> ⚠️ **Attention** : tu manipules des montages, la racine d'un processus et des cgroups en root, sur un hôte qui fait tourner Docker. Travaille **uniquement** dans un shell lancé par `unshare --mount` pour tout ce qui monte ou démonte (un `umount` ou un `pivot_root` lancé dans l'espace de noms de l'hôte peut casser `ctr01` jusqu'au redémarrage). Ne touche ni à `/sys/fs/cgroup/system.slice` ni aux cgroups de Docker. Retour arrière : `runc kill capot KILL && runc delete capot`, `rmdir` du cgroup créé (une fois vide), `umount` des montages de `/srv/capot`, et un redémarrage de `ctr01` en dernier recours.

**Travail demandé**

*Partie 1 — à la main*
1. Récupère `debian:trixie-slim` **sans Docker** dans une disposition OCI (`skopeo copy docker://… oci:/srv/capot/oci:trixie`), lis l'index, le manifeste et la configuration avec `jq`, et extrais les couches à la main dans `/srv/capot/manuel/inf/` (pense aux fichiers de « suppression » `.wh.*`, même s'il n'y en a pas dans une image à une couche).
2. Monte un overlayfs (`lowerdir` = couches extraites, `upperdir`, `workdir`) sur `/srv/capot/manuel/fusion` dans un nouvel espace de noms `mnt`. Écris un fichier dans `fusion` et retrouve-le dans `upperdir`.
3. Crée un cgroup `capot-manuel` sous `/sys/fs/cgroup` (contrôleurs `memory` et `pids` activés), limite-le à 32 Mio et 16 processus, et places-y ton shell (`cgroup.procs`). Prouve la limite de processus en la dépassant.
4. Avec `unshare` (espaces `pid`, `mnt`, `uts`, `ipc`, `net`, et `--fork`), fais de `fusion` la racine d'un processus par `pivot_root`, démonte l'ancienne racine, monte `/proc`, donne le nom d'hôte `capot`. Depuis un autre terminal, entre dans ce « conteneur » avec `nsenter` et compare `ps`, `hostname`, `ip link`, `readlink /proc/<pid>/ns/*` avec ceux de l'hôte.

*Partie 2 — avec runc*

5. Avec `umoci unpack` (ou ton extraction de la partie 1), prépare le paquet `/srv/capot/bundle` ; génère ou adapte `config.json` (`runc spec` en donne un modèle) pour que le conteneur `capot` exécute `sleep infinity`, sans terminal, racine en lecture seule, nom d'hôte `capot`, `cgroupsPath` `/capot`, mémoire 64 Mio, 32 processus au plus.
6. Lance-le en arrière-plan avec `runc run -d capot` (redirige les entrées-sorties), puis observe-le : `runc list`, `runc state capot`, `runc ps capot`, ses espaces de noms et son cgroup sous `/sys/fs/cgroup/capot`. **Laisse-le tourner** pour la vérification.
7. *(Facultatif)* Lance la même image avec `ctr` (l'espace de noms `moby` de containerd montre les conteneurs de Docker : ne les touche pas, utilise ton propre espace `-n capot`), puis avec `nerdctl` si tu l'installes. Compare ce qu'ajoutent containerd et le shim.
8. Rédige `docs/conteneurs/sous-le-capot.md` (publié par MR) : la démonstration pas à pas, et un tableau « champ de `config.json` → pièce construite à la main → commande de la partie 1 » (au moins `namespaces`, `root`, `mounts`, `linux.resources`, `cgroupsPath`, `hostname`, `process.args`, `process.user`, `process.capabilities`).

**Critères de réussite**
- [ ] Le conteneur `runc` `capot` tourne depuis `/srv/capot/bundle`, dans ses propres espaces de noms `pid`, `mnt`, `uts`, `ipc`, `net`, avec le nom d'hôte `capot` et une racine en lecture seule.
- [ ] Son cgroup est `/capot`, avec `memory.max` = 67108864 et `pids.max` = 32.
- [ ] `docs/conteneurs/sous-le-capot.md` est commité et explique `unshare`, `nsenter`, `pivot_root`, `cgroup.procs`, overlay et `runc spec`.

**Vérification** : `lab/bin/check 12 44` (puis arrête et supprime `capot`, et retire le cgroup `capot-manuel`).

<details><summary>Indice 1</summary>

`pivot_root` exige que la nouvelle racine soit un point de montage, dans un espace de noms `mnt` dont la propagation n'est pas partagée avec l'hôte (`mount --make-rprivate /`). La séquence classique : `cd` dans la nouvelle racine, `pivot_root . <ancien>`, puis `umount -l /<ancien>`.
</details>

<details><summary>Indice 2</summary>

Un contrôleur n'est disponible dans un cgroup enfant que s'il est activé dans `cgroup.subtree_control` du parent ; `cat /sys/fs/cgroup/cgroup.controllers` liste ceux que la racine propose. Un processus est déplacé en écrivant son PID dans `cgroup.procs` du cgroup cible.
</details>

<details><summary>Indice 3</summary>

Dans `config.json`, la racine est la clé `root` (`path`, `readonly`), les limites sont sous `linux.resources` (`memory.limit`, `pids.limit`), le cgroup sous `linux.cgroupsPath`. `runc run -d` sans terminal transmet ses descripteurs au conteneur : redirige-les, sinon ta session SSH reste accrochée.
</details>

**Pour aller plus loin** : refais la partie 2 sans privilège (`runc spec --rootless`, compte `app` sur `ctr02` avec `crun`), et compare `config.json` (espace `user`, `uidMappings`).

---

### M12-E45 — Questions expert : conteneurs  `Q` `★★★`

> **Ticket PLAT-1345** — *De : Claire Morel*
> Avant de te laisser former les équipes sur les conteneurs, je veux tes réponses écrites à ces questions, celles qu'on pose en entretien et celles qu'on se pose à 3 h du matin. Réponds en quelques lignes argumentées, avec la commande ou le fichier qui prouve ce que tu avances quand il y en a un.

**Objectifs pédagogiques**
- Expliquer, preuves à l'appui, le fonctionnement interne des conteneurs et les choix d'exploitation du module.
- Repérer les notions encore fragiles avant de former les équipes.

**Prérequis** : paliers 1 à 4.
**Durée indicative** : 2 h.

**Questions**


1. Un conteneur sort avec le code 137 et `OOMKilled: false`. Donne trois causes possibles et la commande qui départage chacune.
2. Pourquoi un processus en PID 1 dans un conteneur ignore-t-il `SIGTERM` alors que le même programme hors conteneur s'arrête ? Que change `--init` (ou `tini`) et pourquoi `exec` dans un script d'entrée ?
3. Docker 29 stocke ses images dans containerd. Qu'est-ce que cela change pour `docker images`, pour l'espace disque et pour un outil qui lisait `/var/lib/docker/overlay2` ?
4. Une image fait 900 Mo alors que son application en pèse 40. Liste quatre causes typiques, comment les voir (Dive, `docker history`), et l'effet de chacune sur la sécurité, pas seulement sur la taille.
5. Pourquoi un `COPY . .` placé avant l'installation des dépendances ralentit-il chaque construction ? Qu'apportent en plus `--mount=type=cache` et un `.dockerignore` ?
6. Le « root » d'un conteneur Podman sans privilège peut-il lire `/etc/shadow` de l'hôte s'il est monté dans le conteneur ? Et le root d'un conteneur Docker classique ? Justifie par les UID vus de l'hôte.
7. Que fait réellement `--privileged` (capacités, périphériques, seccomp, AppArmor/SELinux, `/sys` et `/proc`) ? Pourquoi est-il interdit sur `runner02`, et qu'autorise-t-on à la place pour une construction sans démon ?
8. `internal: true` sur un réseau Compose : que bloque-t-il, que ne bloque-t-il pas ? Comment isoler deux conteneurs d'un même projet ?
9. Les règles de publication de ports de Docker contournent-elles un pare-feu de l'hôte écrit en nftables ? Où insérer une règle pour qu'elle s'applique au trafic publié (chaîne `DOCKER-USER`), et pourquoi le trafic entre deux conteneurs d'un même pont n'y passe-t-il pas ?
10. Un conteneur exécute un binaire Go compilé sans `CGO_ENABLED=0` sur une image `scratch`. Que se passe-t-il, pourquoi le message parle-t-il d'un fichier qui existe, et quelles sont les deux corrections possibles ?
11. Quadlet : pourquoi `systemctl --user enable` échoue-t-il sur une unité générée ? Comment un service Quadlet démarre-t-il au démarrage de la machine, et que se passe-t-il sans *linger* ?
12. `:z` et `:Z` sous SELinux : différence, risque de chacune (pense à un `:Z` sur `/home` ou `/var/lib/mysql` partagé), et pourquoi `chcon` n'est pas une correction durable.
13. Une image est référencée par `mediagenda/api:1.2.0` dans la production et par une empreinte `@sha256:…` dans la recette. Laquelle des deux peut changer sans que personne ne modifie le déploiement ? Quels sont les avantages et les coûts de l'épinglage par empreinte ?
14. Qu'est-ce qu'un index multi-architecture ? Comment le moteur choisit-il le manifeste, et comment vérifier qu'une étiquette couvre bien `linux/arm64` sans tirer l'image ?
15. Construction reproductible : cite trois sources de non-reproductibilité d'une image et le moyen de les neutraliser (`SOURCE_DATE_EPOCH`, verrous, épinglage). À quoi sert la reproductibilité pour la sécurité ?
16. Une sonde de santé appelle `/pret` (base et cache) au lieu de `/sante`. Quel est le risque sous Docker, et quel sera-t-il sous Kubernetes quand la même sonde deviendra une sonde de vivacité ?
17. Compare `json-file`, `local` et `journald` comme pilotes de journaux : rotation, `docker logs`, collecte par un agent, perte en cas de disque plein.
18. Qu'est-ce que le *shim* de containerd et pourquoi permet-il de redémarrer `dockerd` (ou containerd) sans tuer les conteneurs (`live-restore`) ?
19. `runc`, `crun`, gVisor, Kata Containers : quels niveaux d'isolement, quels coûts, et quand MédiSphère devrait-elle envisager autre chose que `runc` ?
20. Rootless Docker, Podman sans privilège et `userns-remap` : trois façons de ne pas être root sur l'hôte. Ce que chacune protège, ce qu'elle casse (ports < 1024, volumes, performances réseau), et laquelle MédiSphère a retenue (ADR-0120).

**Vérification** : auto-évaluation avec le corrigé.
