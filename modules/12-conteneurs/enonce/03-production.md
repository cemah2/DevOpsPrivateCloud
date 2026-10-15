# Module 12 — Palier 3 : Production

Les quatre applications tournent en conteneurs, leurs images sont construites en CI sans privilège et rangées dans le registre de travail. Mais un attaquant qui prendrait la main sur MédiAgenda aurait encore beaucoup de marches à sa disposition (capacités, appels système, système de fichiers inscriptible), Rocky Linux et SELinux n'ont jamais vu nos conteneurs, le démon Docker de `ctr01` donne root à quiconque touche son socket, chaque Dockerfile part de l'image de base qu'il veut, personne ne serait prévenu qu'un conteneur redémarre en boucle, les données de PostgreSQL ne sont sauvegardées nulle part et chaque mise à jour coupe le service. Claire Morel veut des conteneurs qu'on peut **exploiter** ; Sophie Laurent veut des conteneurs **durcis**, sur des images de base **maîtrisées** ; Nadia Roussel veut être **prévenue** ; Julien Petit veut livrer **sans coupure**. Ce palier fait passer les conteneurs en production.

> ⚠️ **Rappel** : `ctr01` porte le registre de travail (M12-E15), que la CI de `runner02` utilise à chaque pipeline. Avant toute intervention sur le démon Docker de `ctr01` (redémarrage, `daemon.json`, *userns-remap*), vérifie qu'aucun pipeline n'est en cours (`Admin > CI/CD > Jobs` sur `git01`) et note la commande de retour arrière. Les changements de configuration des hôtes passent par Ansible (`plateforme/ansible`), jamais par une modification à la main laissée en place.

**Chemin imposé** (introduction du module) : la configuration des hôtes passe par les rôles `docker_engine` et `podman_hote` (M12-E02), étendus ou complétés par MR dans `plateforme/ansible` ; les fichiers des applications (Dockerfile, `compose.yaml`, unités Quadlet, `.gitlab-ci.yml`) vivent dans leur projet GitLab ; les sondes vont dans `plateforme/outils` (modèle de `ms-verif-services`, M06-E29) ; tout flux qui traverse les passerelles est déclaré dans `group_vars/role_routeur/pare_feu.yml` et dans `docs/socle/matrice-flux.md` ; tout nouveau secret est en Vault (`critique` pour les clés de sauvegarde et les jetons PBS) et inscrit au **registre des secrets**. La documentation va dans `docs/conteneurs/` de `plateforme/medisphere` (`adr/`, `runbooks/`, `tests/`).

**Hôtes de ce palier** : `ctr01` (2121, Docker 29.8, pile Compose de MédiAgenda de M12-E08 dans `~/src/mediagenda-api`, registre de travail), `ctr02` (2122, Podman 5.4, compte `app`, unités Quadlet de M12-E14), `ctr03` (2123, Rocky 10, Podman 5.8, SELinux *enforcing*, compte `app`), `runner02` (1012, socle), `adm01` (sondes). Aucune nouvelle VM.

**Ordre conseillé** : E24 → E25 → E26 → E28 → E29 → E30 → E27 → E31 → E33 → E32 → E34. Le durcissement (E24-E26) précède la supervision (E28) ; les normes (E33) s'appuient sur tout le palier et précèdent l'exercice chronométré (E34). **Durée totale indicative** : 30 à 35 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 12 XX`).

---

### M12-E24 — Durcir l'exécution : utilisateur, capacités, seccomp, lecture seule  `LAB` `★★★`

> **Ticket SEC-1324** — *De : Sophie Laurent*
> Une image qui ne tourne pas en root, c'est un bon début. Mais si quelqu'un exploite une faille de MédiAgenda, je veux savoir **exactement** ce qu'il peut faire ensuite dans le conteneur : déposer un outil, monter un système de fichiers, lire la mémoire d'un autre processus, s'élever par un binaire setuid. Je veux que chacun de ces gestes échoue, que ce soit écrit dans le `compose.yaml` et pas dans la tête de quelqu'un, et que tu me montres les essais.

**Objectifs pédagogiques**
- Savoir ce qu'un conteneur reçoit par défaut (utilisateur, capacités, profil seccomp, AppArmor, système de fichiers) et le mesurer.
- Retirer toutes les capacités et n'ajouter que celles qui se justifient ; comprendre `no-new-privileges`.
- Écrire un profil seccomp dérivé du profil par défaut de ta version de Docker.
- Faire tourner une application avec un système de fichiers racine en lecture seule.

**Prérequis** : M12-E05 (image non root de MédiAgenda), M12-E08 (pile Compose), M12-E06 (Podman sans privilège), M12-E18 (limites).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Pile visée : `compose.yaml` du projet `mediagenda/api` tel que l'a laissé M12-E18 (pile de M12-E08, image 0.2.0 de M12-E11, limites et délais d'arrêt de M12-E18), lancée sur `ctr01` depuis `~/src/mediagenda-api` (projet Compose `mediagenda` : services `db`, `valkey`, `migrations`, `api`).
- Essais d'évasion fournis par l'équipe Plateforme : [`ressources/E24-tests-evasion.py`](../ressources/E24-tests-evasion.py). Le script tourne **dans** le conteneur avec le Python de l'image (`docker exec -i <CONTENEUR> python - < E24-tests-evasion.py`), tente onze gestes d'attaquant, affiche « BLOQUÉ » ou « POSSIBLE » pour chacun et rend le nombre de gestes possibles. Il ne modifie rien hors du conteneur. Lis-le avant de le lancer.
- Profil seccomp par défaut de Docker : publié dans le dépôt `moby/moby`, à l'étiquette `docker-v<VERSION>` (`docker version --format '{{.Server.Version}}'`), fichier `vendor/github.com/moby/profiles/seccomp/default.json`. Le profil MédiAgenda est versionné dans `mediagenda/api` sous `securite/seccomp-mediagenda.json`.
- Debian 13 active AppArmor : `ctr01` applique le profil `docker-default`, `ctr02` celui de Podman. SELinux est l'affaire de E25.
- Documentation : `docs/conteneurs/durcissement-execution.md` dans `plateforme/medisphere`.

> ⚠️ **Attention** : (1) un profil seccomp trop strict fait échouer l'application de façon déroutante (`Operation not permitted` au milieu d'une bibliothèque) : teste chaque modification sur la pile de `ctr01`, jamais directement sur une pile partagée ; (2) le passage de PostgreSQL sous son propre UID suppose que le volume lui appartient déjà : vérifie-le avant (étape 5), et garde la commande de retour (`git checkout compose.yaml && docker compose up -d --wait`).

**Travail demandé**
1. **État des lieux.** Sur `ctr01`, relève pour le conteneur de l'API (`mediagenda-api-1`) ce qu'il a réellement : utilisateur, capacités (`grep ^Cap /proc/1/status` dans le conteneur, décodées sur l'hôte par `capsh --decode=<VALEUR>`), état de `NoNewPrivs` et de `Seccomp`, profil AppArmor, système de fichiers racine inscriptible ou non :
   ```
   admin@ctr01:~$ docker inspect mediagenda-api-1 --format '{{.Config.User}} {{.HostConfig.CapAdd}} {{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}} {{.AppArmorProfile}} {{.HostConfig.ReadonlyRootfs}}'
   admin@ctr01:~$ docker exec mediagenda-api-1 grep -E '^(Cap|NoNewPrivs|Seccomp)' /proc/1/status
   admin@ctr01:~$ docker info --format '{{json .SecurityOptions}}'
   ```
   Fais de même avec un conteneur `debian:trixie-slim` lancé en root et sans option. Dresse un tableau : capacités par défaut de Docker, de Podman (même mesure sur `ctr02` en compte `app`), et ce que chacune permet.
2. **Essais avant durcissement.** Copie le script d'essais sur `ctr01`, lance-le contre l'API, puis contre un `python:3.13-slim-trixie` lancé en root sans option (`docker run --rm -i -u 0 …`). Note les gestes « POSSIBLE » dans chaque cas et explique pourquoi l'image non root de E05 en bloque déjà une partie… mais pas tous.
3. **Capacités et privilèges.** Dans `compose.yaml`, retire **toutes** les capacités de **tous** les services et pose `no-new-privileges`. Pour chaque capacité que tu serais tenté de rajouter, écris dans un commentaire ce qui la rend nécessaire, ou trouve comment t'en passer.
4. **Lecture seule.** Passe tous les services en système de fichiers racine en lecture seule ; donne-leur seulement les emplacements inscriptibles dont ils ont besoin (lis les erreurs au démarrage), en `tmpfs` bornés et sans exécution possible, ou en volume nommé pour ce qui doit survivre.
5. **PostgreSQL et Valkey.** Leurs images démarrent en root pour faire `chown`, puis changent d'utilisateur. Lis leur script d'entrée (`docker run --rm --entrypoint cat postgres:18-trixie /usr/local/bin/docker-entrypoint.sh | less`) : à quelle condition sautent-ils ces étapes ? Vérifie l'UID propriétaire du volume `mediagenda_donnees-db` avant tout changement (`docker run --rm -v mediagenda_donnees-db:/v debian:trixie-slim ls -lan /v`), puis fais démarrer les deux services sans aucune capacité.
6. **Seccomp.** Télécharge le profil par défaut de **ta** version de Docker, lis sa structure (`defaultAction`, règles conditionnées par la version du noyau ou par une capacité) et produis `securite/seccomp-mediagenda.json` : le même profil, sans l'autorisation de `ptrace`, `process_vm_readv` et `process_vm_writev` accordée sans capacité. Le fichier doit être **reproductible** (un script versionné le régénère à partir du profil officiel et échoue si la structure attendue a changé). Applique-le aux services `api` et `migrations`.
7. **Preuve.** `docker compose up -d --wait` ; l'application répond (`/pret`, création d'un rendez-vous par l'API) et le script d'essais donne **0 geste possible** contre l'API. Reprends la mesure de l'étape 1 et compare.
8. **Podman.** Sur `ctr02`, en compte `app`, lance la même image avec les options équivalentes de `podman run` (et le même profil seccomp). Que vaut l'UID 10001 du conteneur vu de l'hôte (`ps -o user,pid,cmd`) ? Que change le fait d'être sans privilège pour les gestes 3 à 6 du script ?
9. **Documentation.** Rédige `docs/conteneurs/durcissement-execution.md` : chaque option retenue, ce qu'elle bloque (avec le résultat de l'essai), ce qu'elle ne bloque pas, et la liste des capacités ajoutées (aucune, idéalement) avec leur justification. Pousse `compose.yaml` et `securite/` dans `mediagenda/api` par MR.

**Critères de réussite**
- [ ] Sur `ctr01`, les services `api`, `db` et `valkey` tournent sous un UID non nul, sans aucune capacité ajoutée, toutes capacités retirées, avec `no-new-privileges`, sans mode privilégié, racine en lecture seule.
- [ ] Le conteneur de l'API utilise un profil seccomp personnalisé qui refuse `ptrace` ; son `/tmp` est un `tmpfs` ; `/pret` répond 200.
- [ ] `E24-tests-evasion.py` ne trouve aucun geste possible dans le conteneur de l'API.
- [ ] `compose.yaml`, `securite/seccomp-mediagenda.json` et le script qui le régénère sont sur `main` de `mediagenda/api` ; `docs/conteneurs/durcissement-execution.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 12 24`

<details><summary>Indice 1</summary>

Une image qui déclare `USER 10001` ne reçoit plus de capacités **effectives**, mais elle garde le **jeu limite** (*bounding set*) : un binaire setuid root de l'image (il y en a plusieurs dans une Debian *slim*) pourrait les lui rendre. Deux options, indépendantes, ferment cette porte. Lis `CapBnd` et `NoNewPrivs` dans `/proc/1/status` avant et après.
</details>

<details><summary>Indice 2</summary>

Dans un fichier Compose, une ancre YAML (`x-…: &nom`, puis `<<: *nom`) évite de répéter le même bloc dans chaque service ; attention, une clé redéfinie dans le service **remplace** celle de l'ancre au lieu de s'y ajouter (c'est le cas de `security_opt`). Pour seccomp, Compose lit le fichier (chemin relatif au `compose.yaml`) et transmet son contenu au démon : `docker inspect` montre alors le JSON complet.
</details>

<details><summary>Indice 3</summary>

Le profil par défaut accorde certains appels système sans condition, d'autres seulement à partir d'une version du noyau, d'autres encore seulement si le conteneur a une capacité donnée (`includes.caps`). Repère la règle dont la liste `names` contient `ptrace` **sans** condition de capacité : c'est la seule à retirer. `jq` sait supprimer un élément d'un tableau qui satisfait une condition, et compter les règles avant et après.
</details>

**Pour aller plus loin** (facultatif) : générer un profil seccomp **minimal** à partir des appels réellement observés (`oci-seccomp-bpf-hook` avec Podman en root, ou `strace -c -f` sur la suite de tests) et mesurer combien d'appels l'application utilise vraiment ; [Seccomp security profiles for Docker](https://docs.docker.com/engine/security/seccomp/), [capabilities(7)](https://man7.org/linux/man-pages/man7/capabilities.7.html), [Compose : `security_opt`, `read_only`, `tmpfs`](https://docs.docker.com/reference/compose-file/services/).

---

### M12-E25 — SELinux et conteneurs sur Rocky Linux  `LAB` `★★★`

> **Ticket SEC-1325** — *De : Sophie Laurent* — *Copie : Claire Morel*
> L'hébergeur HDS que nous visons pour la production exploite des serveurs de la famille RHEL, avec SELinux en mode *enforcing*, et l'auditeur vérifiera qu'il le reste. Je veux savoir comment nos conteneurs se comportent sous SELinux, et je pose trois règles : SELinux n'est **jamais** désactivé, ni globalement ni pour un conteneur ; on ne réétiquette **pas** à la volée des répertoires de l'hôte depuis un conteneur ; un conteneur qui a besoin d'un accès inhabituel reçoit une politique **dédiée et minimale**.
> Premier cas réel : Legacy-RDV sur `ctr03`, avec ses pièces jointes et l'export que InfoGér nous dépose par SFTP.

**Objectifs pédagogiques**
- Lire les étiquettes SELinux des processus et des fichiers (`container_t`, `container_file_t`, catégories MCS) et comprendre l'isolement qu'elles apportent entre conteneurs.
- Connaître les options de volume `:z` et `:Z`, leurs effets sur l'hôte et leurs limites.
- Étiqueter durablement un répertoire de données par la politique de l'hôte (`semanage fcontext`).
- Diagnostiquer un refus (`ausearch`, `audit2why`) et produire une politique dédiée avec **udica**.

**Prérequis** : M12-E02 (`ctr03`, rôle `podman_hote`), M12-E06 et M12-E14 (Podman sans privilège, Quadlet), M12-E19 (image de Legacy-RDV), M08 (Rocky Linux).
**Durée indicative** : 3 h.

**Contexte technique**
- `ctr03` (Rocky 10, Podman 5.8) ; compte `app` sans `sudo` (conteneurs sans privilège, *linger* actif) ; `admin` a `sudo` (lecture des journaux d'audit, politique SELinux).
- Image : celle de Legacy-RDV construite en E19, dans le registre de travail (`ctr01.par1.medisphere.internal:5000/legacy/legacy-rdv:<VERSION-E19>`, par exemple `2.3.1`). Dans l'image, l'application est sous `/var/www/legacy-rdv` (pièces jointes dans `uploads/`), Apache tourne sous `www-data` (UID 33) et écoute sur le port 8080.
- Données sur l'hôte : pièces jointes migrées de `legacy01` dans **`/srv/legacy-rdv/uploads`** (à créer, propriété de `app` ; pour que `www-data` du conteneur y écrive sans privilège, fais correspondre l'UID 33 du conteneur à `app`, comme en M12-E06) ; dépôt SFTP d'InfoGér dans **`/home/app/depot-infoger/`** (dossier personnel d'`app`, étiquette d'origine à conserver : `sshd` et les comptes SFTP en dépendent), monté **en lecture seule** dans le conteneur sous `/import`.
- Conteneur cible : unité Quadlet `legacy-rdv.container` du compte `app` (`~/.config/containers/systemd/`), port de l'hôte 8080. MariaDB n'est pas nécessaire pour cet exercice : seuls l'accès aux fichiers et le démarrage d'Apache sont étudiés.
- Paquets nécessaires (`udica`, `policycoreutils-python-utils`, `setools-console`) et politique produite : par un rôle Ansible dédié, **`selinux_conteneurs`**, appliqué à `ctr03` après `podman_hote` (playbook `playbooks/conteneurs.yml`).

> ⚠️ **Attention** : (1) **ne monte jamais** un répertoire système ou personnel avec `:Z` ou `:z` (`/home`, `/home/app`, `/etc`, `/var`, `/usr`…) : Podman réétiquette **tout le contenu** sur l'hôte, ce qui peut empêcher `sshd`, `dnf` ou la connexion d'`app` de fonctionner. Si cela arrive : `sudo restorecon -RFv <CHEMIN>` rétablit les étiquettes de la politique. (2) N'utilise **ni** `setenforce 0`, **ni** `label=disable`, **ni** `--privileged` pour « voir si ça marche » sans le noter et le défaire aussitôt : c'est précisément ce que l'auditeur cherchera.

**Travail demandé**
1. **Lecture.** Relève l'état de SELinux (`getenforce`, `sestatus`), l'étiquette d'un conteneur lancé par `app` (`podman run --rm debian:trixie-slim cat /proc/self/attr/current`) — lance-le deux fois et compare — et celle d'un processus du conteneur vu de l'hôte (`ps -eZ`). Que valent le type, le niveau et les catégories ? Que donnerait `--privileged` (essaie-le une fois, note le type obtenu, et explique pourquoi la règle de Sophie l'interdit) ?
2. **Refus et diagnostic.** Crée `/srv/legacy-rdv/uploads` (propriété d'`app`) et lance l'image de Legacy-RDV avec ce dossier monté **sans option** sur `/var/www/legacy-rdv/uploads`. Essaie d'y écrire depuis le conteneur (`podman exec … touch …`). Trouve le refus dans le journal d'audit (`sudo ausearch -m AVC -ts recent`), fais-le expliquer (`audit2why`) et identifie la source, la cible et la classe refusée.
3. **`:z` et `:Z`.** Refais l'essai avec `:Z`, puis avec `:z` ; relève à chaque fois l'étiquette du dossier sur l'hôte (`ls -Zd`). Lance un **second** conteneur sur le même dossier : lequel des deux cas l'en empêche, et pourquoi ? Puis lance `sudo restorecon -Rv /srv/legacy-rdv` : que devient l'étiquette posée par Podman, et qu'en conclus-tu pour la production ?
4. **Étiquette durable.** Donne à `/srv/legacy-rdv/uploads` une étiquette **de la politique de l'hôte** qui convient aux conteneurs (règle `semanage fcontext` puis `restorecon`), par un rôle Ansible. Vérifie qu'elle survit à un `restorecon` et que le conteneur écrit sans `:z`/`:Z`. Discute : qu'est-ce que cette étiquette autorise, à qui ?
5. **Le dépôt d'InfoGér.** Ajoute le montage en lecture seule de `/home/app/depot-infoger` sur `/import`. Constate le refus de lecture. Pourquoi ne faut-il **pas** le réétiqueter ? Génère une politique dédiée avec **udica** à partir de l'inspection du conteneur (`podman inspect`), lis le fichier CIL produit (quels droits sur quels types, quel port), charge-le en suivant la commande qu'udica affiche, et relance le conteneur avec ce type de processus (`--security-opt label=type:…`). Constate que la lecture fonctionne, que l'écriture dans `/import` reste refusée, et qu'**aucun** refus n'apparaît plus dans le journal pour ce type.
6. **Par le code.** Transforme le tout en code : rôle Ansible qui installe les paquets, pose la règle d'étiquetage, copie et charge le module CIL (idempotent : pas de rechargement s'il est déjà chargé à la même version) ; unité Quadlet `legacy-rdv.container` qui porte le type de processus (lis `podman-systemd.unit(5)` pour la clé correspondante). Vérifie après `systemctl --user daemon-reload` et redémarrage de l'unité.
7. **Documentation.** Ajoute à `docs/conteneurs/durcissement-execution.md` une section SELinux : les trois règles de Sophie, les options étudiées (aucune, `:Z`, `:z`, `semanage fcontext`, udica, `label=disable`, `--privileged`) avec ce qu'elles font **à l'hôte**, et la procédure de diagnostic d'un refus.

**Critères de réussite**
- [ ] `ctr03` est en mode *enforcing* ; Podman y voit SELinux actif.
- [ ] `/srv/legacy-rdv/uploads` porte une étiquette de conteneur définie par une règle `semanage fcontext` (elle survit à `restorecon`) ; `/home/app/depot-infoger` a gardé son étiquette d'origine.
- [ ] Le module de politique produit par udica est chargé ; le conteneur `legacy-rdv` du compte `app` tourne avec ce type de processus (ni `spc_t`, ni étiquetage désactivé), lancé par son unité Quadlet.
- [ ] Le journal d'audit ne contient aucun refus pour ce type depuis le dernier redémarrage de l'unité.
- [ ] Le rôle Ansible et le module CIL sont sur `main` de `plateforme/ansible` ; la section SELinux est dans `docs/conteneurs/durcissement-execution.md`.

**Vérification** : `lab/bin/check 12 25`

<details><summary>Indice 1</summary>

Les deux nombres après `s0:` sont des **catégories** MCS, tirées au hasard pour chaque conteneur. Un processus ne peut accéder qu'à des fichiers dont les catégories sont un **sous-ensemble** des siennes. Un fichier sans catégorie (`s0` tout court) est donc accessible à tous les conteneurs du même type ; un fichier aux catégories d'un conteneur ne l'est qu'à lui.
</details>

<details><summary>Indice 2</summary>

`podman inspect` donne `ProcessLabel` et `MountLabel` du conteneur. `matchpathcon` (ou `selinuxlabel`/`ls -Z` après `restorecon -n -v`) dit quelle étiquette **la politique** attribue à un chemin ; `semanage fcontext -l` liste les règles locales. Cherche, dans la politique des conteneurs (`container-selinux`), le type prévu pour les fichiers que les conteneurs peuvent lire et écrire.
</details>

<details><summary>Indice 3</summary>

udica lit le JSON de `podman inspect` (montages, ports, capacités) et produit un fichier CIL qui hérite de modèles livrés avec lui ; la fin de sa sortie donne la commande `semodule -i` complète, modèles compris. Lancé sans privilège, le conteneur a un `podman inspect` différent de celui d'un conteneur root : génère la politique à partir du conteneur **tel qu'il tournera** (compte `app`, mêmes montages, même port).
</details>

**Pour aller plus loin** (facultatif) : le booléen `container_manage_cgroup` et les autres booléens de `container-selinux` (`getsebool -a | grep container`) ; les conteneurs imbriqués (`label=nested`) ; [udica](https://github.com/containers/udica), [Podman et SELinux (Red Hat)](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_selinux/), `container_selinux(8)`.

---

### M12-E26 — Durcir le moteur : socket, *userns-remap*, Docker sans privilège  `LAB` `★★★`

> **Ticket SEC-1326** — *De : Sophie Laurent* — *Copie : Karim Benali*
> J'ai lu la CIS Docker Benchmark en diagonale. Trois phrases m'inquiètent : « *being a member of the docker group is equivalent to root* », « *do not expose the Docker daemon socket* » et « *enable user namespace support* ». Montre-moi ce que la première veut dire sur `ctr01`, prouve-moi que la deuxième est respectée, et dis-moi ce que coûte la troisième avec Docker 29. Au passage : je veux savoir **qui** a touché à la configuration de Docker, et quand.

**Objectifs pédagogiques**
- Mesurer ce que donne l'accès au socket de Docker et en tirer une règle d'accès.
- Connaître les options de durcissement du démon (`live-restore`, `icc`, `no-new-privileges`, journaux) et leur portée réelle.
- Évaluer *userns-remap* et le mode sans privilège de Docker, avec leurs limites sous Docker 29.
- Journaliser les modifications de la configuration du moteur avec `auditd`.

**Prérequis** : M12-E02 (rôle `docker_engine`), M12-E03, M12-E07 (réseaux), M12-E15 (registre sur `ctr01`), M12-E18 (journaux), M12-E24.
**Durée indicative** : 3 h.

**Contexte technique**
- `daemon.json` de `ctr01` est géré par le rôle `docker_engine` (M12-E02) : défauts du rôle fusionnés avec `docker_engine_daemon_extra` (`group_vars/role_docker/docker_engine.yml`) ; le groupe `docker` est rempli par `docker_engine_groupe_docker` (`admin`, qui a déjà `sudo`). Toute modification durable passe par ces variables et par MR. Les essais des étapes 1, 4 et 5 se font à la main **puis se défont**.
- Comptes temporaires de l'exercice, supprimés à la fin : `demo-docker` (étape 1) et `essai-rootless` (étape 5).
- Documentation de référence : *Docker Engine security*, *Protect the Docker daemon socket*, *Isolate containers with a user namespace*, *Rootless mode*, et la section *Unauthenticated TCP connections* des fonctionnalités dépréciées de Docker.
- Règles d'audit : rôle Ansible dédié qui dépose un fichier sous `/etc/audit/rules.d/` (clé de recherche `docker`).

> ⚠️ **Attention** : (1) `userns-remap` change l'emplacement où Docker range images, conteneurs et volumes : pendant l'essai de l'étape 4, **le registre de travail disparaît** (les pipelines qui poussent ou tirent échouent) ; préviens Karim, fais l'essai hors des heures de pipeline et rétablis la configuration aussitôt (retour arrière : supprimer la clé de `daemon.json`, `sudo systemctl restart docker`, vérifier que le registre répond) ; (2) l'étape 2 ne doit **jamais** ouvrir le démon sur une adresse du réseau, même pour essayer.

**Travail demandé**
1. **Le groupe `docker`.** Crée un compte `demo-docker` sans `sudo`, ajoute-le au groupe `docker`, et, sous ce compte, obtiens un shell root **sur l'hôte** en une commande `docker run` (monte la racine de l'hôte). Lis `/etc/shadow`. Supprime le compte. Écris la règle qui en découle (qui peut appartenir à ce groupe, et pourquoi y laisser `admin` ne donne rien qu'il n'ait déjà… sauf une chose : laquelle ?) et vérifie que le groupe `docker` de `ctr01` et de `runner02` ne contient personne d'autre que ce que ta règle autorise.
2. **Le socket.** Liste ce qui écoute (`ss -lntpx`) et les droits du socket. Lis la section des fonctionnalités dépréciées sur les connexions TCP sans authentification, puis la documentation *Protect the Docker daemon socket* : quelles sont les deux façons sûres d'administrer un démon à distance ? Que fait **ta** version quand on lui demande d'écouter en TCP sans TLS (cherche dans le code, les notes de version ou la documentation : n'essaie pas sur `ctr01`) ? Où se trouve, en pratique, l'accès distant de la CI à un démon (indice : `runner02`) ?
3. **Options du démon.** Ajoute par le rôle `docker_engine` : `live-restore`, `icc` à faux, `no-new-privileges` par défaut, et vérifie que les choix de journaux de E18 y sont. Pour chacune, prouve son effet : redémarre le démon pendant que la pile MédiAgenda tourne (les conteneurs survivent-ils ? que se passe-t-il pour un conteneur qui publie un port pendant le redémarrage ?) ; vérifie sur quel(s) réseau(x) `icc` agit vraiment (réseau `bridge` par défaut, réseaux de la pile Compose) ; lance un conteneur sans option et lis `NoNewPrivs`.
4. **`userns-remap`.** Active `"userns-remap": "default"` à la main, redémarre le démon et lis son journal (`journalctl -u docker -n 50`) : quel message apparaît au sujet du stockage d'images ? Que deviennent `docker images`, `docker ps -a` et `docker volume ls` ? Lance un conteneur `sleep` en « root » et relève son UID vu de l'hôte. Essaie `--network host` et un volume monté depuis l'hôte : qu'est-ce qui change ? **Retire l'option**, redémarre, vérifie que le registre répond de nouveau. Conclus : `ctr01` ? `runner02` ?
5. **Docker sans privilège.** Crée `essai-rootless`, installe pour lui le mode sans privilège en suivant la page *Rootless mode* de la documentation (paquet du dépôt Docker, script d'installation, variables d'environnement), lance la pile MédiAgenda sous ce compte et compare avec Docker root et avec Podman sans privilège (E06, E24) : réseau et publication de ports, ports < 1024, limites de ressources (délégation des cgroups), stockage, intégration à systemd, effort d'exploitation. Désinstalle (script prévu à cet effet) et supprime le compte.
6. **Audit.** Écris un rôle Ansible qui installe `auditd` et pose des règles de surveillance sur les binaires et la configuration du moteur (`dockerd`, `containerd`, `runc`, `/etc/docker`, `/etc/containerd`, unités systemd de Docker), puis sur l'exécution du client `docker`. Modifie un fichier surveillé et retrouve l'événement avec `ausearch -k <CLÉ>` : y vois-tu **qui** (identifiant d'audit `auid`) ? Pourquoi une règle sur le fichier du socket ne trace-t-elle **pas** les appels à l'API ? Où les retrouver alors ?
7. **Documentation.** Dans `docs/conteneurs/durcissement-execution.md`, une section « Moteur » : accès au socket, options du démon et leur effet mesuré, décision sur *userns-remap* et sur le mode sans privilège (par hôte, avec la raison), journaux d'audit.

**Critères de réussite**
- [ ] Le groupe `docker` de `ctr01` ne contient que `admin`, celui de `runner02` ne contient personne (M12-E20) ; les comptes `demo-docker` et `essai-rootless` n'existent plus ; aucun démon Docker n'écoute en TCP.
- [ ] `live-restore` est actif, le réseau `bridge` par défaut a la communication entre conteneurs désactivée, et un conteneur lancé sans option a `NoNewPrivs` à 1.
- [ ] *userns-remap* n'est plus actif et le registre de travail répond.
- [ ] Les règles d'audit sont chargées (clé `docker`) et un événement a été enregistré depuis moins de 7 jours.
- [ ] Les modifications du rôle `docker_engine` et le rôle d'audit sont sur `main` de `plateforme/ansible` ; la section « Moteur » est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 12 26`

<details><summary>Indice 1</summary>

Le démon tourne en root et fait **ce qu'on lui demande** : monter n'importe quel chemin de l'hôte dans un conteneur, donner toutes les capacités, partager l'espace de noms des processus de l'hôte. Qui peut lui parler peut donc tout cela. Le groupe propriétaire du socket ne restreint rien d'autre que l'accès au socket lui-même.
</details>

<details><summary>Indice 2</summary>

`icc` est une option du réseau `bridge` **par défaut** ; un réseau défini par l'utilisateur (ceux de Compose) a sa propre option (`com.docker.network.bridge.enable_icc`), visible dans `docker network inspect`. `live-restore` garde les conteneurs pendant que le démon est arrêté, mais ce qui dépend du démon (proxy de ports en espace utilisateur, journaux) peut être interrompu : lis la page *Live restore*.
</details>

<details><summary>Indice 3</summary>

Avec `userns-remap`, Docker 29 range tout sous un sous-dossier de `/var/lib/docker` nommé d'après la plage d'UID, et le journal du démon dit ce qu'il fait du stockage d'images containerd. Pour `auditd`, une règle `-w <chemin> -p wa -k <clé>` surveille les écritures et changements d'attributs ; une règle `-p x` sur un binaire trace son exécution. L'`auid` survit à `sudo` : c'est lui qui désigne l'humain.
</details>

**Pour aller plus loin** (facultatif) : un plugin d'autorisation du démon (`authz-plugin`) ; l'outil `docker-bench-security` (et ses limites : il juge des valeurs, pas un modèle de menace) ; [Docker Engine security](https://docs.docker.com/engine/security/), [Rootless mode](https://docs.docker.com/engine/security/rootless/), [userns-remap](https://docs.docker.com/engine/security/userns-remap/), [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker).

---

### M12-E27 — Politique des images de base de MédiSphère  `LIBRE` `★★★`

> **Ticket PLAT-1327** — *De : Claire Morel* — *Copie : Sophie Laurent, Julien Petit*
> J'ai compté sept images de base différentes dans nos Dockerfiles, dont deux que personne ne sait expliquer. Quand la prochaine faille d'OpenSSL sortira, je veux pouvoir répondre en une heure à « quelles images sont touchées, et quand sont-elles corrigées ? ».
> Je veux un **catalogue** d'images de base MédiSphère (`bibliotheque/…`), reconstruites **chaque semaine** à partir d'images amont **épinglées**, une **liste des images autorisées**, et un pipeline qui refuse le reste. Au module 13, tout cela partira dans Harbor : prépare-le pour que le déménagement soit un changement d'adresse.

**Objectifs pédagogiques**
- Concevoir une chaîne d'images de base : origine amont épinglée, couche MédiSphère, reconstruction périodique, étiquetage, traçabilité.
- Distinguer l'épinglage (reproductibilité) et la mise à jour (correctifs de sécurité), et organiser leur coexistence.
- Faire respecter une liste d'images autorisées dans la CI.

**Prérequis** : M12-E04 (empreintes, index), M12-E10 à E13 (construction), M12-E15 (registre de travail), M12-E16 (Hadolint), M12-E21 (gabarit `image.yml` de `plateforme/ci-templates`), M01 (pipelines planifiés).
**Durée indicative** : 4 h.

**Contexte technique**
- Projet GitLab à créer : **`plateforme/images-base`**. Images publiées dans le registre de travail sous **`ctr01.par1.medisphere.internal:5000/bibliotheque/<nom>`** (au M13, le préfixe deviendra le projet Harbor `bibliotheque`).
- Images amont de référence (PLAN, M12) : `debian:trixie-slim`, `python:3.13-slim-trixie`, `golang:1.26-trixie`, `php:8.4-apache-trixie`, `gcr.io/distroless/static-debian13`. La racine de la PKI MédiSphère doit être reconnue par toute image dérivée qui en a besoin.
- Les constructions passent par le gabarit de M12-E21 (BuildKit sans privilège, `runner02`), avec les identifiants protégés du registre de travail.
- Documentation : `docs/conteneurs/images-de-base.md` dans `plateforme/medisphere`.

**Contraintes**
1. Chaque image amont est référencée **par empreinte** (`@sha256:…`) dans le code ; changer d'empreinte est une MR, relue, dont la description dit pourquoi.
2. Au moins **trois** images `bibliotheque/` : un Debian minimal, un environnement Python et une image pour Legacy-RDV ou pour la construction Go (à toi de justifier le choix). Chacune ajoute au moins la racine MédiSphère et les correctifs de sécurité disponibles au moment de la construction, et rien qui ne serve pas à **toutes** les images dérivées.
3. Reconstruction **hebdomadaire** automatique (pipeline planifié), et reconstruction à la demande (correctif urgent) ; chaque construction produit une étiquette **datée et immuable** et met à jour une étiquette **mobile** documentée ; jamais `latest`.
4. Traçabilité : chaque image porte les étiquettes OCI qui disent d'où elle vient (image amont et son empreinte, révision Git, date) ; il doit être possible, à partir d'une image d'application, de retrouver l'image `bibliotheque/` et l'image amont d'origine.
5. **Liste des images autorisées**, lisible par une machine, dans `plateforme/images-base`, et un job réutilisable dans `plateforme/ci-templates` qui échoue si une instruction `FROM` d'un Dockerfile ou d'un Containerfile référence une image hors liste (étapes de construction comprises), avec un message qui dit quoi utiliser à la place. Au moins `mediagenda/api` l'utilise.
6. Les images `bibliotheque/` sont multi-architectures (amd64 et arm64) si leur amont l'est, analysées par Hadolint sans exception non justifiée, et non root par défaut quand c'est possible (sinon, justifie).
7. Documentation : la politique (quelles images, qui les maintient, cycle de vie, délai de correction d'une faille critique, ce que deviennent les applications quand une image de base change, exceptions) et la procédure de déménagement vers Harbor.

**Critères de réussite**
- [ ] `plateforme/images-base` existe ; ses Dockerfiles ne référencent des images amont que par empreinte ; sa liste des images autorisées est sur `main`.
- [ ] Un pipeline planifié hebdomadaire est actif, et sa dernière exécution planifiée (de moins de 8 jours) a réussi.
- [ ] Le registre de travail contient `bibliotheque/debian` avec une étiquette datée de moins de 8 jours et une étiquette mobile ; l'image porte les étiquettes OCI de provenance.
- [ ] Le job de contrôle des images autorisées est dans `plateforme/ci-templates` et utilisé par `mediagenda/api` ; il échoue sur un `FROM` hors liste (démontré dans une branche, MR fermée).
- [ ] `docs/conteneurs/images-de-base.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 12 27`

<details><summary>Indice 1</summary>

Épingler une image amont par empreinte n'empêche pas de corriger : la reconstruction hebdomadaire applique les mises à jour des paquets **au-dessus** de l'image épinglée. L'empreinte amont change alors par MR, à un rythme choisi (et, au module 13, proposée par un robot). Demande-toi ce que vaut une étiquette mobile pour une application qui veut être reproductible, et ce que vaut une étiquette datée pour une application qui veut ses correctifs.
</details>

<details><summary>Indice 2</summary>

Les étiquettes `org.opencontainers.image.*` (spécification OCI *annotations*) ont des noms prévus pour la base d'une image (`base.name`, `base.digest`), la révision et la source. Un `ARG` placé avant le premier `FROM` peut porter l'empreinte et servir dans `FROM` et dans une étiquette. Pour lire un `FROM`, souviens-toi des formes `FROM image AS étape`, `FROM --platform=… image`, `FROM étape-précédente` et des variables.
</details>

**Pour aller plus loin** (facultatif) : reconstruire de façon **reproductible** les mises à jour Debian à partir d'un instantané daté (`snapshot.debian.org`) ; comparer avec une approche « distroless partout » ou avec des images construites par un outil dédié (apko) ; [OCI image annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md), [Docker : *Best practices*, images de base](https://docs.docker.com/build/building/best-practices/).

---

### M12-E28 — Superviser les conteneurs  `LAB` `★★`

> **Ticket PLAT-1328** — *De : Nadia Roussel*
> Vendredi, l'API de recette a redémarré en boucle tout l'après-midi (le runbook RB-120 a servi, merci). Personne ne l'a vu avant que Julien appelle. Je veux une sonde comme pour le socle et pour Ceph : qui tourne seule, qui dit en une ligne quel conteneur ne va pas sur quel hôte, et qui m'alerte. Et je veux savoir ce qu'on aura de plus quand Prometheus arrivera.

**Objectifs pédagogiques**
- Connaître les sources d'information sur l'état des conteneurs : API et événements du moteur, sondes de santé, métriques du démon, statistiques, cAdvisor.
- Écrire une sonde de service pour les conteneurs, en lecture seule et avec un accès minimal aux hôtes.
- Choisir ce qu'on surveille : état, santé, redémarrages, ressources, moteur.

**Prérequis** : M12-E18 (sondes de santé, journaux, `docker stats`), M12-E14 (Quadlet), M12-E23 (RB-120), M06-E29 (`ms-verif-services`, `ms-alerte@`), M08-E24 (modèle de sonde), M02-E20 (`ms-commun.sh`).
**Durée indicative** : 3 h.

**Contexte technique**
- Sonde **`ms-verif-conteneurs`** dans `plateforme/outils` : script `bin/ms-verif-conteneurs`, configuration `etc/ms-verif-conteneurs.conf` (hôtes et conteneurs attendus), tests `tests/bats/ms-verif-conteneurs.bats`, unités `ms-verif-conteneurs.service` (utilisateur `admin`, `OnFailure=ms-alerte@%n.service`) et `.timer` (toutes les 5 minutes). Codes retour : 0, 1 (anomalie **ou contrôle impossible**), 2 (usage). Elle tourne sur `adm01`.
- Accès aux hôtes : compte **`supervision`** sur `ctr01` et `ctr02` (et `ctr03` si tu y fais tourner des conteneurs suivis), clé dédiée `~/.config/workbook/ssh-supervision-conteneurs` sur `adm01`, **commande forcée** qui ne fait que **lire** l'état des conteneurs (Docker sur `ctr01`, Podman du compte `app` sur `ctr02`), par un rôle Ansible `supervision_conteneurs`.
- Métriques du démon Docker : option `metrics-addr` de `daemon.json` (rôle `docker_engine`), port **9323** ; `adm01` (VLAN MGMT) joint le VLAN 99 sans règle supplémentaire. Prometheus n'arrive qu'au module 21 : d'ici là, on lit les métriques en ligne de commande.
- cAdvisor, en comparaison seulement : image `ghcr.io/google/cadvisor:v0.60.6`, lancé puis **retiré**.

**Travail demandé**
1. **Sources.** Sur `ctr01`, compare ce que donnent `docker ps --format json`, `docker inspect --format '{{json .State}}' <CONTENEUR>`, `docker events --since 30m --filter type=container` (provoque un arrêt, un redémarrage, un passage `unhealthy` sur un conteneur de test) et `docker stats --no-stream`. Fais de même sur `ctr02` en compte `app` avec `podman ps`, `podman inspect`, `podman events --since 30m` et `podman stats --no-stream`. Où se lit le **nombre de redémarrages** ? Que montre-t-on d'un conteneur relancé par `restart: unless-stopped`, et d'une unité Quadlet relancée par systemd (`Restart=`) ?
2. **Métriques du démon.** Active `metrics-addr` sur `ctr01` par le rôle `docker_engine`, puis depuis `adm01` : `curl -s http://ctr01.par1.medisphere.internal:9323/metrics | grep -E '^engine_daemon'`. Que trouves-tu (et que ne trouves-tu pas) ? Lance cAdvisor sur `ctr01` en suivant son README (montages en lecture seule nécessaires) : quelles métriques par conteneur ajoute-t-il, et au prix de quels accès à l'hôte ? Retire-le.
3. **Accès minimal.** Écris le script de lecture installé sur les hôtes (une ligne par conteneur : moteur, nom, état, santé, nombre de redémarrages, image) et le rôle `supervision_conteneurs` : compte sans mot de passe ni shell interactif, clé autorisée à commande forcée et restreinte, une seule règle `sudo` pour lancer **ce** script. Vérifie depuis `adm01` qu'une autre commande demandée par ssh ne s'exécute pas.
4. **La sonde.** Écris `ms-verif-conteneurs` sur le modèle de `ms-verif-ceph` (bibliothèque `ms-commun.sh`, configuration séparée, aucune valeur en dur). Elle signale au minimum : un hôte injoignable ; un conteneur attendu absent ou arrêté ; un conteneur `unhealthy` ou en `restarting` ; un nombre de redémarrages qui a **augmenté** depuis le passage précédent (état conservé entre deux passages) ; un conteneur attendu **sans** sonde de santé ; la page de métriques du démon de `ctr01` injoignable. Écris les tests `bats` (sans réseau, `ssh` et `curl` simulés), avec au moins un test rouge par contrôle.
5. **Planification et preuve.** Installe (`task install:systeme`), active le timer, puis provoque une boucle de redémarrage sur un conteneur de test (méthode de RB-120) : l'alerte arrive-t-elle, en combien de temps ? Arrête le conteneur de test et vérifie le retour au vert.
6. **Astreinte.** Ajoute à `docs/astreinte.md` de `plateforme/outils` une section Conteneurs : lire le message de la sonde, les trois premières commandes (renvoi à RB-120), quand réveiller quelqu'un. Écris en une demi-page, dans `docs/conteneurs/supervision.md` de `plateforme/medisphere`, ce que Prometheus (M21) apportera et ce que la sonde continuera de faire.

**Critères de réussite**
- [ ] La page de métriques du démon de `ctr01` répond sur 9323 ; aucun conteneur cAdvisor ne reste sur `ctr01`.
- [ ] Le compte `supervision` de `ctr01` n'exécute que le script de lecture (une autre commande demandée par ssh rend la même sortie) ; il n'est pas dans le groupe `docker`.
- [ ] `ms-verif-conteneurs` est installé sous `/usr/local/bin`, sa configuration sous `/usr/local/etc` ; il rend 0 sur l'état sain ; une option inconnue donne 2.
- [ ] Le timer passe toutes les 5 minutes, le service déclenche `ms-alerte@` en cas d'échec, et une alerte de la sonde a été reçue pendant le test (moins de 30 jours).
- [ ] Les tests `bats` sont sur `main` de `plateforme/outils` et passent dans le pipeline ; `docs/conteneurs/supervision.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 12 28`

<details><summary>Indice 1</summary>

L'état « courant » ne suffit pas : un conteneur qui redémarre toutes les 30 secondes est `running` la plupart du temps. Le compteur de redémarrages est dans `docker inspect` (et `podman inspect`) ; pour détecter qu'il **monte**, il faut comparer avec la valeur du passage précédent, donc garder un petit état (systemd sait fournir un dossier d'état à un service).
</details>

<details><summary>Indice 2</summary>

Avec une commande forcée (`command=` dans `authorized_keys`), ce que le client demande arrive dans `SSH_ORIGINAL_COMMAND` et n'est **pas** exécuté. Pour lire l'état des conteneurs sans privilège du compte `app`, le script doit parler au Podman de ce compte (son `XDG_RUNTIME_DIR`), pas au Podman de root.
</details>

**Pour aller plus loin** (facultatif) : l'API d'événements comme flux continu (un service qui s'abonne à `docker events` et alerte sur `die` ou `oom` sans attendre le timer) ; `podman system df` et `docker system df` dans la sonde (disque) ; [métriques du démon Docker](https://docs.docker.com/engine/daemon/prometheus/), [cAdvisor](https://github.com/google/cadvisor).

---

### M12-E29 — Sauvegarder et restaurer les données des conteneurs  `LAB` `★★`

> **Ticket PLAT-1329** — *De : Claire Morel*
> Julien a créé des jeux de rendez-vous de recette qu'il met une demi-journée à reconstituer. Ils vivent dans un volume Docker sur `ctr01`. Une VM sauvegardée chaque nuit, c'est bien, mais je veux pouvoir restaurer **la base** sans restaurer la VM, prouver que la sauvegarde est **cohérente**, et savoir combien de temps ça prend.

**Objectifs pédagogiques**
- Distinguer sauvegarde **logique** (export par l'application) et sauvegarde **de volume** (copie de fichiers), et savoir quand chacune est cohérente.
- Sauvegarder un PostgreSQL conteneurisé vers PBS, chiffré, depuis un timer de l'hôte.
- Exporter et importer des images ; dire ce qui se reconstruit et ce qui se sauvegarde.
- Restaurer dans un environnement **séparé** et mesurer le RTO.

**Prérequis** : M12-E07 (volumes), M12-E08 (pile Compose), M12-E24 (pile durcie), M06-E28 (rôle `sauvegarde_pbs`, jetons PBS, chiffrement côté client), M00-E22 (PBS).
**Durée indicative** : 3 h.

**Contexte technique**
- Données à protéger : la base `mediagenda` du service `db` de la pile Compose de `ctr01` (volume `mediagenda_donnees-db`). Le cache Valkey n'a pas de persistance (E08) ; le registre de travail se reconstruit depuis la CI ; le code et la configuration sont dans Git.
- PBS : `pbs01` (10.20.10.10:8007), datastore `ds-lab`, espace de noms **`par1/conteneurs`** (à créer), jeton **`wb-backup@pbs!ctr01`** limité à cet espace (rôle `DatastoreBackup`), clé de chiffrement côté client propre à `ctr01` (Vault `critique`, copie papier). Même méthode qu'en M06-E28 et M08-E25.
- La VM `ctr01` elle-même est déjà sauvegardée chaque nuit par la tâche `lab-nuit` (pool `lab`, espace `par1`) : vérifie-le, ne la duplique pas.
- Flux : `ctr01` → `pbs01:8007` à travers la bordure et le tunnel `wg0`, plus la règle d'entrée de `pbs01`. La règle de bordure exige une adresse **stable** : c'est la réservation Kea **10.10.99.121** de `ctr01` posée en M12-E15, et la définition `CTR01` de la matrice des flux qui l'accompagne ; vérifie qu'elles sont toujours en place, n'en crée pas d'autre.
- Horaires : `git01` 01:15, Ceph 01:30, services socle 01:55-02:05, `lab-nuit` 02:30 ; la sauvegarde des conteneurs passe à **01:40**.
- Rôle Ansible : `sauvegarde_conteneurs` (sur le modèle de `sauvegarde_pbs`), script `/usr/local/sbin/wb-backup-conteneurs.sh`, unités `wb-backup-conteneurs.service` et `.timer`, secrets sous `/etc/wb-backup/` (root, 600).

> ⚠️ **Attention** : (1) la restauration de test se fait dans un conteneur et un volume **dédiés** (nom commençant par `restau-`), jamais dans la base de la recette ; supprime-les à la fin ; (2) l'essai de sauvegarde de volume « à chaud » de l'étape 2 produit une copie **qui peut être inutilisable** : c'est le but de l'essai, ne la conserve pas comme sauvegarde ; (3) une règle d'entrée est nécessaire sur `pbs01` lui-même : modifie-la par le même chemin qu'en M06-E28.

**Travail demandé**
1. **Sauvegarde logique.** Exporte la base avec `pg_dump` au format *custom*, en exécutant l'outil **dans** le conteneur `db` (le flux sort sur la sortie standard, rien n'est écrit dans le conteneur) ; vérifie l'archive (`pg_restore --list`). Pourquoi la sortie de `pg_dump` est-elle cohérente même si l'API écrit pendant l'export ?
2. **Sauvegarde de volume.** Copie le contenu du volume `mediagenda_donnees-db` dans une archive `tar` au moyen d'un conteneur jetable (`docker run --rm -v mediagenda_donnees-db:/source:ro …`), d'abord **pendant** que PostgreSQL tourne et écrit (lance une boucle de créations de rendez-vous), puis **après** `docker compose stop db`. Restaure chacune dans un volume `restau-…` et démarre un PostgreSQL 18 dessus : que dit le journal ? Lequel des deux essais est une sauvegarde, à quelles conditions ? Quand préférerais-tu une copie de volume à un export logique ?
3. **Images.** Exporte l'image de l'API (`docker save`), importe-la sur `ctr02` (`podman load`), puis copie-la sans passer par un fichier avec Skopeo (`docker-daemon:` vers `docker://` ou `oci-archive:`). Que contient l'archive avec le stockage containerd de Docker 29 (index, plateformes, attestations) ? Écris ce que MédiSphère **sauvegarde** et ce qu'elle **reconstruit** (images, registre, volumes, configuration).
4. **Vers PBS.** Crée l'espace de noms et le jeton (script de M06-E28 étendu), la clé de chiffrement, la règle de `pare_feu.yml` (avec la définition `CTR01` de M12-E15) et celle de `pbs01`, et inscris chaque secret au registre. Écris le rôle `sauvegarde_conteneurs` et son script : export logique de chaque base listée dans la configuration (conteneur, base, utilisateur), vérification de chaque archive, copie à froid des volumes listés (liste vide par défaut), envoi vers PBS (`--ns par1/conteneurs`, identifiant `ctr01`), nettoyage en sortie quoi qu'il arrive, code retour non nul au moindre échec. Applique-le et lance le service une fois.
5. **Restauration.** Restaure la dernière sauvegarde depuis PBS dans un conteneur `restau-db` (PostgreSQL 18, volume `restau-donnees`, réseau isolé), compare le nombre de rendez-vous et une somme de contrôle de la table avec la base d'origine (requête identique des deux côtés), chronomètre chaque étape, puis supprime conteneur et volume. Consigne le tout dans `docs/conteneurs/tests/restauration-conteneurs.md` (RPO, RTO mesuré).
6. **Runbook.** Rédige `docs/conteneurs/runbooks/RB-121-restaurer-la-base-d-une-pile-compose.md` : quand l'utiliser (et quand restaurer plutôt la VM), préalables, restauration à côté puis bascule, vérifications, retour arrière.

**Critères de réussite**
- [ ] Sur `ctr01`, le timer `wb-backup-conteneurs.timer` est actif (01:40), son dernier passage a réussi, ses secrets PBS sont `root:root` en 600.
- [ ] `pbs01` contient dans `par1/conteneurs` une sauvegarde de `ctr01` de moins de 48 h contenant les exports de base ; la VM `ctr01` est couverte par `lab-nuit`.
- [ ] Aucun conteneur ni volume `restau-*` ne reste sur `ctr01`.
- [ ] `docs/conteneurs/tests/restauration-conteneurs.md` (RTO mesuré) et RB-121 sont sur `main` de `plateforme/medisphere` ; le rôle `sauvegarde_conteneurs` est sur `main` de `plateforme/ansible`.

**Vérification** : `lab/bin/check 12 29`

<details><summary>Indice 1</summary>

`pg_dump` lit la base dans **une seule transaction** : il voit un instantané figé, quels que soient les écritures concurrentes. Une copie de fichiers, elle, lit des pages à des instants différents. Dans l'image officielle, le compte local du conteneur se connecte par le socket Unix sans mot de passe : `docker exec` sous l'utilisateur du service suffit.
</details>

<details><summary>Indice 2</summary>

`proxmox-backup-client backup` envoie des **dossiers** (`nom.pxar:chemin`) : prépare les exports dans un dossier de travail en 700, nettoyé par `trap`. Pour restaurer, `snapshot list`, `restore <instantané> <archive>.pxar <dossier>` et `--keyfile`. Dans le conteneur de restauration, `pg_restore` lit l'archive sur son entrée standard (`docker exec -i`).
</details>

**Pour aller plus loin** (facultatif) : l'archivage continu des journaux de transactions (WAL) pour un RPO de quelques minutes, que CloudNativePG fera pour toi au module 16 ; [pg_dump](https://www.postgresql.org/docs/18/app-pgdump.html), [Docker : *Back up, restore, or migrate data volumes*](https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes).

---

### M12-E30 — Mettre à jour sans interruption et revenir en arrière  `LAB` `★★★`

> **Ticket CHG-1330** — *De : Julien Petit* — *Copie : Claire Morel*
> À chaque nouvelle version, la recette est coupée une minute et mes testeurs prennent des erreurs 502. Et la semaine dernière, une image cassée est restée en place jusqu'au lundi parce que personne n'a vu que la sonde de santé échouait.
> Je veux : sur `ctr01`, des mises à jour **sans aucune erreur** côté client ; sur `ctr02`, que la recette se mette à jour **toute seule** quand on publie une nouvelle image… et qu'elle **revienne en arrière toute seule** si la nouvelle image ne passe pas sa sonde.

**Objectifs pédagogiques**
- Organiser une mise à jour progressive avec Compose (qui ne sait pas le faire seul) derrière un répartiteur, et la prouver sous charge.
- Configurer la mise à jour automatique de Podman (`AutoUpdate=registry`) et son retour arrière fondé sur la sonde de santé.
- Comprendre ce qu'une étiquette **mobile** implique pour la reproductibilité.

**Prérequis** : M12-E08, M12-E14 (Quadlet), M12-E15 (registre), M12-E17 et E18 (arrêt propre, sondes), M12-E24 (pile durcie), M07 (HAProxy).
**Durée indicative** : 4 h.

**Contexte technique**
- **Partie A, `ctr01`** : surcharge Compose `compose.ha.yaml` dans `mediagenda/api` (utilisée avec `compose.yaml`) : deux services d'API (`api`, `api-b`), un HAProxy **de test** (image `docker.io/library/haproxy:3.2-trixie`, dans la pile, ce n'est pas `lb01`) qui devient le seul point d'entrée sur le port 8000 de l'hôte ; page d'état HAProxy en CSV sur `127.0.0.1:8404` (boucle locale de `ctr01` seulement). Script de mise à jour `outils/maj-progressive.sh`.
- **Partie B, `ctr02`** (compte `app`) : l'unité Quadlet de l'API de M12-E14. Image désignée par l'étiquette **mobile** `ctr01.par1.medisphere.internal:5000/mediagenda/api:recette`, que l'on déplace pour « publier » ; identifiants du registre pour `app` dans un fichier d'authentification **persistant** (pas celui de `$XDG_RUNTIME_DIR`, effacé au redémarrage).
- Versions : `<ACTUELLE>` est la version en service, `<NOUVELLE>` une version reconstruite pour l'exercice (même code, `--build-arg VERSION=…`, visible dans `/sante`), `<CASSÉE>` une image qui démarre mais ne répond jamais à sa sonde (par exemple une image dérivée qui fixe un autre `MEDIAGENDA_PORT`).
- Runbook : `docs/conteneurs/runbooks/RB-122-mettre-a-jour-une-application-conteneurisee.md`.

> ⚠️ **Attention** : en partie A, HAProxy remplace la publication directe du port 8000 par l'API : pendant la bascule (`docker compose up` avec la surcharge), la recette est brièvement coupée. Préviens Julien. Retour arrière : `docker compose -f compose.yaml up -d --wait --remove-orphans`.

**Travail demandé**
1. **Mesurer la coupure actuelle.** Depuis `adm01`, lance une boucle de requêtes vers l'API de recette (une toutes les 50 ms, code HTTP journalisé ligne par ligne), puis mets à jour l'API de `ctr01` comme d'habitude (`MEDIAGENDA_TAG=<NOUVELLE> docker compose up -d --wait`). Compte les erreurs et leur durée. Qu'est-ce que Compose fait, dans quel ordre ? Lis ce que la spécification Compose dit de `deploy.update_config` et ce que Docker Compose en fait.
2. **Deux instances et un répartiteur.** Écris `compose.ha.yaml` : le second service d'API reprend **exactement** la définition du premier (lis la documentation de `extends` et des balises de fusion `!reset`/`!override`), plus aucune publication directe de l'API, et le service HAProxy (durci comme en E24). Configuration HAProxy : sonde de **disponibilité** sur `/pret`, résolution des noms par le DNS embarqué de Docker (une instance recréée change d'adresse IP : que se passe-t-il sans section `resolvers` ?), nouvelle tentative **sur un autre serveur** pour les seules requêtes qui ont échoué à la connexion.
3. **Mise à jour progressive.** Écris `outils/maj-progressive.sh` : une instance après l'autre, recréation avec attente de la sonde de santé, puis attente que **HAProxy** voie l'instance de retour avant de passer à la suivante ; arrêt sans toucher la seconde instance si la première échoue, avec la commande de retour arrière. Relance la boucle de requêtes et mets à jour vers `<NOUVELLE>` : **zéro** erreur attendue. Puis essaie `<CASSÉE>` : le script doit s'arrêter, le service continuer, et le retour à `<NOUVELLE>` se faire sans erreur.
4. **Mise à jour automatique (Podman).** Sur `ctr02`, en compte `app` : connecte le compte au registre avec un fichier d'authentification persistant, fais pointer l'unité de l'API vers l'étiquette `recette`, ajoute la politique de mise à jour automatique, et vérifie que l'unité n'est toujours considérée comme **démarrée** que lorsque le conteneur est **en bonne santé** (exigence de M12-E14), avec un délai de démarrage adapté (lis `podman-systemd.unit(5)` : clés `AutoUpdate=`, `Notify=`, `HealthCmd=`… et la section `[Service]`). Active le timer de mise à jour du compte. Publie `<NOUVELLE>` sous `recette` (`skopeo copy`), puis `podman auto-update --dry-run`, puis `podman auto-update` : la version change-t-elle ?
5. **Retour arrière automatique.** Publie `<CASSÉE>` sous `recette` et lance la mise à jour par le service que déclenche le timer (`systemctl --user start podman-auto-update.service`), pour qu'elle laisse une trace dans le journal. Que se passe-t-il, dans quel ordre (journal de l'unité, `podman auto-update` lui-même) ? Quelle image tourne à la fin ? Remets `<NOUVELLE>` sous `recette`. Que se passerait-il **sans** la clé qui lie le démarrage à la santé ?
6. **Réflexion et runbook.** Une étiquette mobile en recette, d'accord ; en production ? Comment savoir **quelle version** tourne à un instant donné, et comment la reproduire ? Rédige RB-122 : préparer (version cible, empreinte, migrations de base compatibles avec les deux versions), mettre à jour (Compose : script ; Podman : publication), vérifier, revenir en arrière dans les deux cas.

**Critères de réussite**
- [ ] Sur `ctr01`, la pile tourne avec la surcharge : deux instances d'API saines derrière HAProxy, l'API ne publie plus de port directement, et `/sante` répond 200 à travers le port 8000.
- [ ] Le journal de la boucle de requêtes pendant la mise à jour vers `<NOUVELLE>` et pendant l'essai de `<CASSÉE>` ne contient aucune erreur (consigné dans RB-122 ou dans le ticket).
- [ ] Sur `ctr02`, le conteneur de l'API du compte `app` porte la politique de mise à jour automatique `registry`, a une sonde de santé, son unité est active, et le timer de mise à jour du compte est actif.
- [ ] Un retour arrière automatique a eu lieu (journal du service `podman-auto-update` du compte) et l'image en service est `<NOUVELLE>`.
- [ ] `compose.ha.yaml`, la configuration HAProxy et `outils/maj-progressive.sh` sont sur `main` de `mediagenda/api` ; RB-122 est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 12 30`

<details><summary>Indice 1</summary>

Pendant l'arrêt d'une instance, uvicorn ferme d'abord son socket d'écoute puis laisse finir les requêtes en cours : une nouvelle connexion est **refusée** tout de suite, ce qui est le cas le plus facile à rattraper pour un répartiteur… à condition qu'il réessaie **ailleurs** et seulement quand c'est sans danger (une requête déjà transmise ne doit pas être rejouée). Cherche `retries`, `retry-on` et `option redispatch` dans la documentation de HAProxy 3.2.
</details>

<details><summary>Indice 2</summary>

`docker compose up --wait` attend que le conteneur soit `healthy` **pour Docker** ; HAProxy, lui, a ses propres sondes (`inter`, `rise`) : il peut y avoir quelques secondes pendant lesquelles l'instance est saine mais pas encore remise en rotation. La page d'état de HAProxy (`stats uri`, suffixe `;csv`) donne l'état de chaque serveur.
</details>

<details><summary>Indice 3</summary>

`podman auto-update` compare l'empreinte de l'image locale avec celle de la même étiquette dans le registre, tire la nouvelle image, puis **redémarre l'unité systemd**. Si ce redémarrage échoue, il remet l'ancienne image et redémarre de nouveau. Tout l'enjeu est donc que « l'unité a démarré » veuille dire « le conteneur répond » : par défaut, il suffit que le processus soit lancé.
</details>

**Pour aller plus loin** (facultatif) : le mode bleu-vert (deux piles complètes, bascule du répartiteur) ; le *drain* d'un serveur par l'API d'exécution de HAProxy avant son arrêt ; ce que Kubernetes fera de tout cela (`RollingUpdate`, `maxUnavailable`, sondes de disponibilité, M14) ; [podman-auto-update(1)](https://docs.podman.io/en/v5.4.2/markdown/podman-auto-update.1.html), [Compose : `extends`](https://docs.docker.com/compose/how-tos/multiple-compose-files/extends/), [HAProxy 3.2 : `retry-on`](https://docs.haproxy.org/3.2/configuration.html).

---

### M12-E31 — ADR : Docker ou Podman sur les serveurs  `RED` `★★`

> **Ticket PLAT-1331** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> Depuis le début du module, on fait tourner Docker sur `ctr01` et `runner02`, Podman sur `ctr02` et `ctr03`. Avant que chaque équipe choisisse le sien, je veux une décision : quel moteur sur les serveurs qui font tourner des conteneurs **hors Kubernetes** (recette, outillage, Harbor au M13), et quel moteur pour la **CI**. Une décision qu'on puisse défendre devant Sophie, et qui dise ce qu'elle nous coûte.

**Objectifs pédagogiques**
- Comparer deux moteurs sur des critères explicites et pondérés, à partir de faits **mesurés** dans le module.
- Distinguer les usages (serveur applicatif, poste de développement, CI, outil tiers imposé) au lieu de chercher un vainqueur unique.
- Rédiger une décision avec ses conséquences négatives et ses actions.

**Prérequis** : M12-E03 à E08, E13, E14, E20, E21, E24 à E26, E28 à E30.
**Durée indicative** : 2 h.

**Travail demandé**
Rédige `docs/conteneurs/adr/ADR-0120-docker-ou-podman.md` (gabarit MADR de M00-E33, deux pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Énoncer le **contexte** : les usages concernés (serveurs de recette, outils de plateforme hors Kubernetes, registre Harbor dont l'installateur impose Docker Compose, CI sur `runner02`, postes des développeurs), les exigences de Sophie (sans privilège, SELinux sur la famille RHEL, journalisation, mises à jour), celles de Karim (reproductibilité, outillage, compétences de l'équipe) et le fait que Kubernetes (M14) n'utilisera **ni l'un ni l'autre** (containerd).
2. Lister des **critères** pondérés : sécurité par défaut (démon root, sans privilège, SELinux), intégration à systemd (Quadlet, mise à jour automatique), compatibilité Compose et outillage tiers, construction d'images en CI sans privilège, supervision et journaux, mises à jour (paquets des distributions contre dépôt amont, versions réellement disponibles sur Debian 13 et Rocky 10), maturité et écosystème, coût d'apprentissage.
3. Comparer au moins trois **options** (par exemple : Docker partout ; Podman partout ; Podman sur les serveurs et Docker pour la CI et les outils qui l'imposent), chaque note étant justifiée par un **fait vérifié** dans un exercice du module (cite-le).
4. **Trancher** pour chaque usage, et dire ce que deviennent `ctr01`, `runner02` et le futur `reg01`.
5. Lister les **conséquences** négatives et les actions, rattachées à un module ou datées (normes E33, Harbor au M13, CI sur Kubernetes au M19, durcissement au M26…).

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en deux pages, et contient un tableau critères × options pondéré.
- [ ] Chaque évaluation s'appuie sur un fait mesuré dans le module (exercice cité) ou sur la documentation, pas sur une opinion.
- [ ] La décision distingue au moins les serveurs applicatifs, la CI et les outils qui imposent Docker.
- [ ] Les conséquences négatives sont écrites, avec des actions rattachées à un module ou datées.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Relis tes propres mesures : ce que donne l'accès au socket (E26), ce que coûte *userns-remap* avec Docker 29 (E26), ce que fait Quadlet avec la mise à jour automatique (E30), ce qu'il a fallu pour construire sans privilège en CI (E21), et quelle version de Podman est **réellement** disponible sur chaque distribution (E02, E14). Un critère « possible un jour » n'est pas un critère « satisfait ».
</details>

<details><summary>Indice 2</summary>

Certaines contraintes ne se discutent pas : un outil livré avec un `docker-compose.yml` et un installateur qui appelle `docker compose` (Harbor) se plie mal à Podman. Une bonne décision peut comporter une **exception** bornée et documentée plutôt qu'un choix unique forcé.
</details>

**Pour aller plus loin** (facultatif) : [Podman et Docker Compose (`podman compose`, socket compatible)](https://docs.podman.io/en/v5.4.2/markdown/podman-compose.1.html) ; comparer la surface d'attaque d'un démon permanent et d'un modèle *fork/exec*.

---

### M12-E32 — Questions de production : conteneurs  `Q` `★★★`

> **Ticket PLAT-1332** — *De : Karim Benali*
> Avant que tu prennes l'astreinte sur les conteneurs, je veux t'entendre sur ces questions. Argumente, cite la commande qui le prouve quand c'est possible, et dis de quoi dépend le « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur la sécurité, la disponibilité, les données et les mises à jour des conteneurs en production.
- Relier les choix du palier à des risques concrets.

**Prérequis** : paliers 1 et 2, M12-E24 à E31.
**Durée indicative** : 1 h 30.

**Questions**

1. Un conteneur tourne sous l'UID 10001 avec les capacités par défaut de Docker, sans `no-new-privileges`. Une faille de l'application donne un shell à l'attaquant. Cite trois gestes qu'il peut encore tenter, et pour chacun l'option qui le bloque. Que change le fait que l'image contienne `su`, `passwd` et `mount` ?
2. QCM — `--cap-drop ALL --cap-add NET_BIND_SERVICE`, conteneur sous l'UID 10001, application qui écoute sur le port 80. Au démarrage :
   a) elle écoute sur 80, la capacité ajoutée suffit ;
   b) elle échoue : une capacité ajoutée à un processus non root n'est pas effective sans capacités de fichier ou capacités ambiantes ;
   c) elle échoue : `NET_BIND_SERVICE` ne peut pas être ajoutée après `ALL` ;
   d) elle écoute sur 80 car Docker abaisse `net.ipv4.ip_unprivileged_port_start` dans le conteneur.
   Justifie, et dis comment tu ferais écouter une application non root sur le port 80 (au moins deux façons).
3. Le profil seccomp par défaut de Docker autorise environ 350 appels système. Pourquoi ne pas écrire un profil minimal pour chaque application ? Qu'est-ce que le profil par défaut bloque déjà, et qu'est-ce qui reste de la responsabilité des capacités ?
4. Que se passe-t-il si tu lances un conteneur avec `--security-opt seccomp=unconfined` mais **sans** aucune capacité ? Et avec `--privileged` ? Classe ces deux configurations par risque, en expliquant ce que `--privileged` donne en plus de l'absence de seccomp.
5. Sur `ctr03`, deux conteneurs du compte `app` montent le même dossier avec `:Z`. Le second démarre. Que devient l'accès du premier ? Et avec `:z` ? Pourquoi `:Z` sur `/home/app` est-il une très mauvaise idée, et comment répares-tu ?
6. QCM — Pour simplifier la sonde de E28, Lucas propose d'ajouter le compte `supervision` (sans `sudo`, clé SSH sur `adm01`) au groupe `docker` de `ctr01` : « il ne fait que lire `docker ps` ». Le risque principal est :
   a) aucun, l'API de Docker distingue lecture et écriture selon le groupe ;
   b) la clé de `supervision` (ou toute commande lancée sous ce compte) donne root sur `ctr01`, sans mot de passe ni trace `sudo` ;
   c) la sonde verrait les conteneurs des autres comptes, ce qui viole le RGPD ;
   d) Docker refuse de démarrer quand un compte sans shell est dans le groupe.
   Justifie, et dis en quoi la solution de E28 (commande forcée, une règle `sudo`) est différente.
7. `userns-remap` est activé sur un hôte Docker 29. Cite trois conséquences pour l'exploitation (stockage, volumes, options incompatibles). Qu'apporte-t-il qu'un conteneur non root n'apporte pas ?
8. `live-restore` est actif. Tu mets à jour le paquet `docker-ce` sur `ctr01`. Que deviennent les conteneurs en cours ? Et lors d'une mise à jour de `containerd.io` ? Et d'un redémarrage de l'hôte ? Qu'est-ce qui, alors, relance les conteneurs ?
9. Ta sonde voit un conteneur `running` et `healthy` mais avec un compteur de redémarrages passé de 12 à 15 en cinq minutes. Que se passe-t-il probablement ? Pourquoi un état instantané ne suffit-il pas ? Quel événement du moteur l'aurait signalé immédiatement ?
10. QCM — Tu sauvegardes le volume d'un PostgreSQL **en marche** par `tar`, puis tu restaures et PostgreSQL démarre sans erreur. Tu en conclus :
    a) la sauvegarde est bonne, PostgreSQL l'a vérifiée au démarrage ;
    b) rien : la récupération après incident a pu rejouer un journal qui ne correspond pas aux fichiers copiés à d'autres instants, et des pages peuvent être incohérentes sans erreur visible ;
    c) la sauvegarde est bonne si la base était petite ;
    d) la sauvegarde est bonne si `tar` n'a affiché aucun avertissement « file changed as we read it ».
    Justifie, et dis à quelles conditions une copie de fichiers d'une base en marche est une vraie sauvegarde.
11. Une mise à jour progressive à deux instances derrière HAProxy : quelles sont les conditions, côté application et côté répartiteur, pour qu'**aucune** requête n'échoue ? Que se passe-t-il pour une requête `POST` en cours sur l'instance qu'on arrête ? Et pour une requête qui arrive juste après la fermeture du socket d'écoute ?
12. La nouvelle version de MédiAgenda ajoute une colonne obligatoire et la migration est appliquée avant la mise à jour progressive. Pendant la bascule, l'ancienne instance insère des rendez-vous. Que se passe-t-il ? Comment organises-tu les migrations pour qu'une mise à jour progressive soit possible (et un retour arrière) ?
13. `AutoUpdate=registry` sur une étiquette mobile `recette` : que faut-il pour qu'une image cassée soit retirée automatiquement ? Pourquoi l'auteur d'une image peut-il, sans le vouloir, mettre la production à jour s'il pousse sur la mauvaise étiquette ? Qu'est-ce qui l'empêcherait ?
14. Les images `bibliotheque/` sont reconstruites chaque semaine. Une application a figé son `FROM` sur une étiquette datée d'il y a trois mois. Une autre suit l'étiquette mobile. Une faille critique d'OpenSSL est corrigée lundi. Que fait chacune, combien de temps est-elle exposée, et qu'est-ce que chaque choix coûte en reproductibilité ?
15. QCM — Un développeur propose `FROM python:3.13-slim-trixie@sha256:<EMPREINTE>` « pour la sécurité ». Cela garantit :
    a) que l'image n'a pas de faille connue ;
    b) que tout le monde construit à partir **des mêmes octets**, aussi longtemps que cette empreinte reste disponible ;
    c) que l'image est signée par Docker ;
    d) que les paquets installés par `apt-get` dans le Dockerfile seront toujours les mêmes.
    Justifie chaque réponse fausse.
16. L'auditeur HDS demande : « comment prouvez-vous que les conteneurs de MédiSphère ne tournent pas en root et ne sont pas privilégiés, **aujourd'hui** et pas seulement le jour de l'audit ? ». Que réponds-tu avec ce qui existe à la fin du module, et qu'est-ce qui viendra plus tard (modules 13 et 26) ?

Les réponses argumentées sont dans le corrigé.

---

### M12-E33 — Normes de conteneurisation de MédiSphère  `RED` `★★`

> **Ticket PLAT-1333** — *De : Claire Morel* — *Copie : Sophie Laurent, Julien Petit, Karim Benali*
> Les équipes vont conteneuriser leurs applications par dizaines. Je ne veux pas relire chaque Dockerfile en me demandant ce qui est attendu. Écris les **normes de conteneurisation** de MédiSphère : ce qui est **obligatoire**, ce qui est **recommandé**, ce qui est **interdit**, et comment on le **vérifie**. C'est sur ce texte que reposeront les revues de MR, la CI, et au module 26 les politiques d'admission de Kubernetes.

**Objectifs pédagogiques**
- Transformer les acquis du module en règles courtes, vérifiables et justifiées.
- Relier chaque règle à un contrôle (outil, job de CI, check, revue).
- Prévoir les exceptions et leur traçabilité.

**Prérequis** : tout le module jusqu'ici, en particulier E05, E10, E16, E17, E18, E19, E21, E22, E24, E27, E29, E30 ; M06-E33 (structure d'une politique).
**Durée indicative** : 2 h 30.

**Travail demandé**
Rédige `docs/conteneurs/normes.md` dans `plateforme/medisphere` (4 à 6 pages, par MR, relue par Sophie, Julien et Karim — joue leur rôle avec la grille du corrigé). Chaque règle a un identifiant stable (par exemple `CNT-IMG-03`), un niveau (**DOIT**, **DEVRAIT**, **NE DOIT PAS**), une justification d'une ligne et le **moyen de contrôle**. Le document couvre au minimum :
1. **Objet et périmètre** : quelles images et quels conteneurs (applications, outils de plateforme, CI), à partir de quand, ce qui relève d'autres documents (Kubernetes, M14+).
2. **Images** : images de base autorisées (E27), épinglage, multi-étapes, contenu minimal, utilisateur, étiquettes OCI, `HEALTHCHECK` ou sonde équivalente, forme *exec*, signaux, `.dockerignore`, secrets de construction, Hadolint et seuils de Dive (E16), multi-architectures.
3. **Construction et publication** : CI sans privilège (E21), nommage et étiquetage des versions (immuables, mobiles, jamais `latest`), registre (de travail puis Harbor), ce qui bloque une publication.
4. **Configuration et exécution** : 12 facteurs (configuration par l'environnement, journaux sur la sortie standard, processus sans état, E19), secrets à l'exécution, utilisateur, capacités, `no-new-privileges`, seccomp, lecture seule, limites de ressources, politique de redémarrage, ports.
5. **Données** : volumes nommés, sauvegarde logique ou de volume (E29), ce qui est interdit dans une image ou un conteneur (données de santé dans les couches, journaux contenant des données personnelles).
6. **Exploitation** : supervision (E28), mise à jour et retour arrière (E30), cycle de vie des images (reconstruction, retrait), runbooks.
7. **Hôtes et moteurs** : renvoi à ADR-0120 ; règles d'accès au socket, SELinux, *userns-remap* (E25, E26).
8. **Exceptions et gestion du document** : qui accorde une exception, pour combien de temps, où elle est tracée ; version, propriétaire, date de revue ; correspondance avec les contrôles automatiques (tableau règle → contrôle).

**Critères de réussite**
- [ ] Les huit rubriques sont présentes ; chaque règle a un identifiant, un niveau, une justification et un moyen de contrôle.
- [ ] Les règles sont cohérentes avec ce que le module a réellement mis en place (pas de règle invérifiable présentée comme contrôlée).
- [ ] Les interdits sont explicites (`latest`, root, `--privileged`, socket du démon monté dans un conteneur, secrets dans les couches, `label=disable`…).
- [ ] Le document est sur `main` de `plateforme/medisphere`, au chemin imposé.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Pour chaque règle, pose la question de M06-E33 : quel outil, quel job ou quel check la vérifie ? Si la réponse est « la revue humaine », écris-le : c'est un contrôle légitime, mais pas automatique. Une règle sans moyen de contrôle est un vœu.
</details>

<details><summary>Indice 2</summary>

Une norme trop longue n'est pas lue. Garde dans le document la règle, la raison et le contrôle ; mets les exemples de Dockerfile et de `compose.yaml` conformes dans un dépôt de référence (ou en annexe) plutôt que dans le corps du texte.
</details>

**Pour aller plus loin** (facultatif) : confronter tes règles au [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker), au guide de l'ANSSI [*Recommandations de sécurité relatives au déploiement de conteneurs Docker*](https://cyber.gouv.fr/publications/recommandations-de-securite-relatives-au-deploiement-de-conteneurs-docker) et aux [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) de Kubernetes (niveau *restricted*), qui serviront au module 26.

---

### M12-E34 — Conteneuriser une application en temps limité  `CHRONO` `★★★`

> **Ticket CHG-1334** — *De : Julien Petit* — *Copie : Claire Morel*
> L'équipe de Julien a écrit un petit service, **MédiAnnuaire** (l'annuaire des praticiens, utilisé par la prise de rendez-vous). Ils veulent le livrer en recette **cette semaine**, conteneurisé selon les normes. La direction veut savoir combien de temps il faut à la Plateforme pour conteneuriser **proprement** une nouvelle application.
> Le dossier est prêt (ressources de l'exercice). Chrono en main.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **tes** normes (E33), tes runbooks, ton code (projets des applications, `plateforme/ci-templates`, `plateforme/images-base`) et la documentation officielle.
- Durée cible : **1 h 30** entre l'ouverture du dossier (T0) et la livraison vérifiée (T4).
- Tout passe par Git et la CI : l'image vérifiée est **celle publiée par le pipeline**, jamais une image construite à la main. Une commande manuelle est permise pour **essayer** et **constater** ; note dans la feuille de temps celles qui t'ont manqué dans ton outillage.
- MédiAnnuaire est **conservé** après l'exercice (il servira d'application témoin dans les modules suivants).

**Prérequis** : M12-E33 (normes), E27 (images de base), E21 (gabarit CI), E24 (durcissement), E28 (sonde).
**Durée** : 1 h 30 chronométrées + 30 minutes de retour d'expérience.

**Dossier** : [`ressources/E34-dossier-chrono.md`](../ressources/E34-dossier-chrono.md) (le besoin, les exigences, la feuille de temps) et le code de l'application dans [`ressources/E34-mediannuaire/`](../ressources/E34-mediannuaire/). Lis le dossier à T0, pas avant.

**Critères de réussite**
- [ ] Toutes les exigences du dossier sont satisfaites à T4 (vérification ci-dessous).
- [ ] La feuille de temps est remplie (T0 à T4), avec les gestes manuels et leur raison ; le temps total est inférieur à 1 h 30 (sinon, améliore ton outillage et refais l'exercice sur une copie, détruite ensuite).
- [ ] Le retour d'expérience (une demi-page) est rédigé, et les normes (E33) mises à jour par MR si l'exercice en a montré un manque.

**Vérification** : `lab/bin/check 12 34` (à lancer à T4).

**Pour aller plus loin** (facultatif) : refais l'exercice en visant 45 minutes avec un **gabarit de projet** (Dockerfile, `.dockerignore`, `compose.yaml`, `.gitlab-ci.yml` conformes) que les équipes copieraient elles-mêmes ; c'est l'idée du module 28 (plateforme développeurs).
