# Module 12 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`tofu-modules/`, `infra/`, `ansible/`, `mediagenda-api/` pour le projet `mediagenda/api`). Ne copie que ce que l'exercice ajoute ou modifie.

**Ce qui a été vérifié à la rédaction** :
- `vm-noeud` v2.4.0 et `envs/m12` passent `tofu validate` et `tofu fmt -check` avec OpenTofu 1.13.1 et les fournisseurs réels (`bpg/proxmox` 0.116, `e-breuninger/netbox` 5.8) ; le test [`tests/m12.tftest.hcl`](fichiers/M12-E02/tofu-modules/vm-noeud/tests/m12.tftest.hcl) (`tofu test` avec `mock_provider`) passe : carte DHCP sans adresse NetBox ni IP primaire, appelant « à la M08 » (deux cartes statiques et une carte sans adresse) inchangé, DHCP avec préfixe ou passerelle refusé ;
- les rôles `docker_engine`, `podman_hote`, `legacy_rdv`, les playbooks et les scénarios Molecule passent `ansible-lint` 26.9 (profil `production`, ansible-core 2.21) avec `community.general` 13.5 et `ansible.posix` 2.2 ; les expressions Jinja du rôle `docker_engine` (paquets `nom=version`, lecture de l'empreinte de la clé, fusion de `daemon.json`, gabarit des préférences APT) ont été exécutées ; l'empreinte de la clé de `download.docker.com` (`9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`) a été relue sur la clé réelle ;
- les versions exactes des paquets Docker (`5:29.8.2-1~debian.13~trixie`, `containerd.io` `2.3.6-1~debian.13~trixie`, Compose `5.6.0-1~…`, Buildx `0.37.1-1~…`) ont été lues dans l'index APT de la suite `trixie` ;
- le `Dockerfile` de M12-E05 a été construit avec Docker 29.8.2 et BuildKit (image de 367 Mo sur disque, 89 Mo de contenu ; utilisateur 10001 ; code de sortie 2 sans configuration ; `/sante` en 200 et `/pret` en 503 sans dépendances) ; la pile `compose.yaml` de M12-E08 a été démarrée avec Compose 5.5 (`up --wait`), migrations V1 et V2 appliquées, `/pret` en 200, rendez-vous créé, profil `outils` (`psql`), PID 1 de l'API = `mediagenda`, aucun mot de passe dans `docker inspect` ; arrêt de l'API en moins d'une seconde ;
- les comportements cités de Docker 29 (ID d'image = empreinte de l'index, `docker image ls --tree`, code 137 après `docker stop` d'un `sleep` en PID 1, trois redémarrages de `on-failure:3`), de Skopeo 1.18 (champ `Digest` = empreinte de l'index, *OCI layout* contenant le manifeste `linux/amd64`, `diff_id` = SHA-256 de la couche décompressée) et de Podman 5.4 (champs `rootlessNetworkCmd`, `cgroupVersion`, `security.rootless` de `podman info`) ont été observés ;
- les checks `check-E03` à `check-E08` ont été exécutés contre des conteneurs réels (adresses et ports adaptés), y compris des cas négatifs (Dockerfile en forme shell, `FROM` court ou `latest`, `USER root`, empreinte de plateforme au lieu de l'index) ; tous les scripts passent `shellcheck -x` et `bash -n`.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- le déploiement complet sur Proxmox (VMs, cloud-init en DHCP, DDNS de Kea, NetBox) : l'environnement de rédaction n'avait ni Proxmox ni Kea ; en particulier, que le client DHCP de l'image dorée Debian **et** celui de Rocky (NetworkManager) annoncent bien le nom d'hôte au premier bail (sinon : étape 6 de E02) ;
- les rôles sur de vraies VMs Debian 13 et Rocky 10 (en particulier `dockerd --validate`, `deb822_repository`, `ansible.posix.synchronize` avec `--chown`, `become_user: app` avec `acl`, le linger et `/run/user/1001/bus`) ;
- Podman sans privilège sur `ctr02` et `ctr03` : messages exacts (refus du port 80, avertissements de `sudo -u app`), UID observés ; sur Rocky 10, SELinux n'a pas été exercé (le palier 3 le fait) ;
- les règles exactes écrites par Docker 29 dans nftables (noms des chaînes) : lis les tiennes ;
- les sorties montrées plus bas sont **représentatives** (copiées d'un Docker 29.8.2 de test pour celles de Docker, reconstituées pour le reste), pas copiées de ton lab ; les empreintes citées sont celles du 8 octobre 2026.

---

### M12-E01 — Test de positionnement : conteneurs

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 36. En dessous de 18, relis les « Concepts clés » de l'introduction avant E03 ; les questions 3, 4, 11 à 14 sont reprises en profondeur aux paliers 2 et 3 (E17, E24 à E26), les questions 6 à 10 en E04, E05, E10, E11, E16.

**Réponses argumentées — isolation et noyau**

**1. Conteneur et VM.** Une VM fait tourner **son propre noyau** sur un matériel virtualisé par l'hyperviseur ; un conteneur est un **processus de l'hôte**, servi par le noyau de l'hôte, auquel on a restreint la vue et les droits. Sécurité : tout ce que le noyau expose (appels système, systèmes de fichiers virtuels, pilotes) est une surface d'attaque **partagée** ; une faille du noyau exploitée depuis un conteneur atteint l'hôte et tous les autres conteneurs (d'où seccomp, les LSM et le sans-privilège). Exploitation : démarrage en millisecondes et densité, mais un seul noyau (pas de module noyau propre, pas d'autre système), et des ressources « vues » trompeuses : `/proc/meminfo` ou `nproc` montrent souvent l'hôte, pas la limite du cgroup — une JVM ou un `gunicorn --workers $(nproc)` mal écrit se dimensionne sur la machine entière.

**2. Espaces de noms.** `mnt` : sa propre table de montages (il ne voit plus l'arborescence de l'hôte, seulement sa racine) ; `pid` : sa propre numérotation (il ne voit plus les processus de l'hôte, son premier processus est le PID 1) ; `net` : ses propres interfaces, routes, règles de pare-feu, ports ; `uts` : son nom d'hôte ; `ipc` : ses files de messages et sa mémoire partagée System V/POSIX ; `user` : sa propre correspondance d'UID et de GID (root dedans, ordinaire dehors) et donc ses propres capacités ; `cgroup` : sa vue de la hiérarchie des cgroups (il se croit à la racine) ; `time` : ses horloges `CLOCK_MONOTONIC`/`BOOTTIME` décalées. Ce qui n'a pas d'espace de noms reste partagé : l'horloge système, les trousseaux du noyau (en partie), les modules, `/sys` sans masquage, `dmesg` selon la configuration.

**3. Réponse B.** Sans espace de noms `user`, l'UID 0 du conteneur **est** l'UID 0 de l'hôte : ce qui le retient, ce sont les capacités retirées, seccomp, AppArmor ou SELinux, et le système de fichiers qu'il voit. A décrit le sans-privilège (Podman rootless, `userns-remap` de Docker, M12-E26). C est faux pour Docker, dont le démon tourne en root quel que soit l'utilisateur du client. D est faux sous Linux (c'est le cas de Docker Desktop sur macOS/Windows, qui ajoute une VM).

**4. PID 1.** Le noyau traite à part le PID 1 d'un espace de noms `pid` : il ne lui délivre que les signaux pour lesquels il a **installé un gestionnaire** ; l'action par défaut (« terminer ») ne s'applique pas, sauf pour `SIGKILL` et `SIGSTOP` envoyés depuis un espace parent. Avec un script shell en PID 1 qui lance l'application en arrière-plan (`app &` puis `wait`, ou pire, `sleep`) : `docker stop` envoie `SIGTERM` au PID 1 ; le shell, sans `trap`, l'ignore et ne le **relaie pas** à l'application ; Docker attend son délai (10 s par défaut) puis envoie `SIGKILL` à tout le conteneur : l'application est tuée sans finir ses requêtes, code de sortie 137. Corrections : forme exec (`CMD ["app"]`), `exec app` à la fin du script, ou un `init` (tini, `--init`) qui relaie les signaux et récupère les zombies (M12-E17).

**5. cgroups.** Ils **comptent** (consommation de mémoire, de CPU, d'E/S, nombre de processus) et **limitent** un groupe de processus. Contrôleurs v2 : `memory` (`memory.max`, et `memory.high` pour freiner avant), `cpu` (`cpu.max` « quota période », `cpu.weight`), `pids` (`pids.max`), `io` (`io.max`). Dépassement de mémoire : le noyau récupère d'abord des pages (cache), puis le **tueur OOM du cgroup** tue un processus du groupe ; le conteneur s'arrête souvent avec 137 et `OOMKilled: true`. Dépassement de CPU : rien n'est tué, le groupe est **bridé** (*throttled*) jusqu'à la période suivante : l'application ralentit, ses sondes de santé peuvent expirer (M12-E41).

**Réponses argumentées — images**

**6. Couches et cache.** Une couche est une archive (tar) des **différences** de système de fichiers produites par une instruction (`RUN`, `COPY`, `ADD`), identifiée par son empreinte. BuildKit réutilise une étape tant que l'instruction, ses entrées (fichiers copiés, arguments) et la couche parente sont identiques ; dès qu'une étape change, toutes les suivantes sont refaites. Placer l'installation des dépendances **avant** `COPY . .` fait qu'un changement de code n'invalide que les étapes postérieures : les dépendances, longues à installer, restent en cache (c'est l'exigence de M12-E05).

**7. Étiquette et empreinte.** Une étiquette est un **nom mutable** que le registre fait pointer vers un manifeste ou un index ; une empreinte (`sha256:…`) est la somme du contenu exact du document, **immuable** par construction. Entre lundi et vendredi, `python:3.13-slim` peut avoir été republiée (correctif de Debian, nouvelle version de Python 3.13.x) : rien ne garantit que ce soit la même image. Pour en être sûr : désigner l'image par empreinte (`…@sha256:…`), comparer les `RepoDigests` des deux environnements, et surtout **construire une fois, promouvoir la même empreinte** de la recette à la production (M13, M19).

**8. Réponse B.** Un index (*manifest list* chez Docker, *image index* chez OCI) liste un manifeste par plateforme (`os`, `architecture`, `variant`), chacun avec sa configuration et ses couches ; le client choisit celui de sa plateforme. A est impossible (un binaire est compilé pour une architecture). C est une convention que certains projets ajoutent en plus, pas le mécanisme. D décrit l'émulation QEMU, qu'on utilise pour **construire** (M12-E12), pas pour publier.

**9. Supprimer un gros fichier plus tard.** L'image n'est pas plus petite : la couche qui a ajouté le fichier est toujours là, entière ; la couche suivante n'ajoute qu'un marqueur d'effacement (*whiteout*, fichier `.wh.<nom>`) qui le **masque**. Il faut supprimer dans la **même** instruction que celle qui crée (`RUN téléchargement && utilisation && rm`), ou mieux, construire en **multi-étapes** et ne copier que le résultat dans l'image finale (M12-E10). Pour un secret, c'est la même chose en pire : il reste lisible dans la couche (M12-E11 : `--mount=type=secret`).

**10. `.dockerignore`.** Tout le contexte est envoyé au constructeur, et un `COPY . .` le met dans l'image : sans `.dockerignore`, on embarque `.git` (tout l'historique, y compris un secret supprimé depuis), un `.env`, des clés, l'environnement virtuel local, des sauvegardes. C'est donc une mesure de **sécurité** (ne pas publier ce qui ne doit pas l'être) autant que de performance (contexte plus petit, cache moins souvent invalidé).

**Réponses argumentées — sécurité**

**11. Capacités et `--privileged`.** Les capacités découpent les pouvoirs de root en une quarantaine d'unités (`CAP_NET_ADMIN`, `CAP_SYS_ADMIN`, `CAP_NET_BIND_SERVICE`…) ; Docker n'en donne qu'une quinzaine par défaut (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `FSETID`, `KILL`, `SETGID`, `SETUID`, `SETPCAP`, `NET_BIND_SERVICE`, `NET_RAW`, `SYS_CHROOT`, `MKNOD`, `AUDIT_WRITE`, `SETFCAP`). `--privileged` donne **toutes** les capacités, **tous** les périphériques de l'hôte (`/dev/sda`…), désactive seccomp et le confinement AppArmor/SELinux, et rend `/sys` et `/proc` modifiables : monter le disque de l'hôte devient trivial, c'est root sur la machine. `--cap-add SYS_ADMIN` n'ajoute qu'une capacité (déjà très large) mais garde seccomp, le profil LSM, la liste blanche des périphériques et les chemins masqués : moins grave, toujours à justifier par écrit.

**12. Le groupe `docker`.** Le socket `/var/run/docker.sock` donne accès à **toute** l'API d'un démon qui tourne en root, sans autre contrôle. Exemple (à ne pas exécuter) : `docker run --rm -it -v /:/hote docker.io/library/debian:trixie-slim chroot /hote bash` donne un shell root sur le système de fichiers de l'hôte ; `--privileged --pid=host` puis `nsenter -t 1 -a` donne un shell dans tous les espaces de noms de l'hôte. Être dans le groupe `docker` = être root, sans mot de passe et sans trace sudo (M12-E26).

**13. seccomp.** Le profil par défaut (Docker, Podman) est une **liste blanche** : il autorise environ 300 appels système et en refuse une cinquantaine que des conteneurs ordinaires n'utilisent pas et qui touchent des ressources non isolées ou dangereuses : `kexec_load`, `init_module`/`finit_module` (charger du code noyau), `keyctl`/`add_key` (trousseaux du noyau non isolés), `open_by_handle_at` (utilisé par l'évasion « Shocker » de 2014), `bpf`, `perf_event_open`, `userfaultfd`, `reboot`, `swapon`, `mount`/`umount2`, `unshare` avec certains drapeaux, `ptrace` sur noyaux anciens… Certains sont réautorisés si le conteneur reçoit la capacité correspondante (`CAP_SYS_ADMIN` pour `mount`). Il réduit la surface du noyau partagé.

**14. Réponse B.** Le sans-privilège de Podman, c'est : lancé par un compte ordinaire, aucun démon root, et un espace de noms `user` qui fait du « root » intérieur l'UID de ce compte (et des autres UID intérieurs, des UID de sa plage subordonnée). A décrit `USER` non root, utile mais différent (avec Docker, `USER 1000` reste l'UID 1000 **de l'hôte**). C et D sont des durcissements complémentaires (`--cap-drop ALL`, `--read-only`, M12-E24).

**15. Secrets en `ENV`, `ARG`, `-e`.** `ENV` est écrit dans la **configuration de l'image** (`docker image inspect`, visible par tout qui tire l'image) et dans chaque conteneur ; `ARG` apparaît dans l'**historique** (`docker image history` montre les commandes `RUN` avec les arguments), dans le cache de construction et dans les attestations de provenance de BuildKit ; `-e` est visible dans `docker inspect` (`Config.Env`), dans `/proc/<pid>/environ` (pour root sur l'hôte), dans l'historique du shell et un instant dans `ps` (arguments du client). Solutions : secrets de construction BuildKit (E11), secrets de Compose ou fichiers montés (E08), Vault plus tard (M25).

**Réponses argumentées — réseau et stockage**

**16. Ports publiés et pare-feu.** `-p 8080:80` fait écrire au démon une règle de **traduction d'adresse** (DNAT) dans la table `nat` (chaîne `DOCKER`, appelée depuis `PREROUTING`) et une règle d'acceptation dans le **relais** (`FORWARD`, chaînes de Docker). Le paquet destiné à 8080 est réécrit vers l'adresse du conteneur **avant** la décision de routage : il n'est plus destiné à l'hôte, il ne traverse jamais `INPUT` ; une règle « tout bloquer en entrée » ne le voit pas. Il faut filtrer dans la chaîne `DOCKER-USER` (évaluée avant celles de Docker dans `FORWARD`), publier sur une adresse précise (`-p 127.0.0.1:8080:80`), ou filtrer en amont (bordure). M12-E07 le montre.

**17. Volume, montage lié, tmpfs.** Volume nommé : données dans `/var/lib/docker/volumes/<nom>/_data` (ou le stockage du compte pour Podman), cycle de vie géré par le moteur (`volume create/ls/rm/prune`), survit au conteneur, **initialisé par copie** du contenu de l'image au premier montage ; usage : données d'une base. Montage lié : un chemin de l'hôte choisi par l'administrateur, qui en gère seul le cycle de vie ; il **masque** le contenu de l'image et garde les droits de l'hôte ; usage : configuration, code en développement, socket. tmpfs : en mémoire (compté dans la limite mémoire du conteneur), perdu à l'arrêt ; usage : fichiers temporaires, cache jetable, compléments d'une racine en lecture seule.

**18. Noms entre conteneurs.** Sur un **réseau défini** par l'utilisateur (`docker network create`, ou le réseau par défaut d'un projet Compose), le **DNS intégré** de Docker répond aux noms des conteneurs et des services, à l'adresse `127.0.0.11` de chaque conteneur (servie par `dockerd`). Le réseau `bridge` par défaut n'offre pas cette résolution (reliquat des `--link`). Chez Podman, c'est `aardvark-dns` sur les réseaux créés (le réseau `podman` par défaut n'a pas de DNS).

---

### M12-E02 — Préparer les hôtes de conteneurs

**Solution**

*A. Avant d'écrire.*

1. La documentation Docker fait retirer `docker.io`, `docker-doc`, `docker-compose`, `podman-docker`, `containerd` et `runc` : les paquets de Debian fournissent les mêmes fichiers et services en d'autres versions (containerd 1.7, runc 1.1), et `containerd.io` les **remplace** (`Conflicts`/`Provides`). Elle télécharge la clé dans `/etc/apt/keyrings/docker.asc` et la référence par `Signed-By` ; elle publie l'empreinte (`9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`) pour qu'on la contrôle. Côté Podman : un compte avec des plages dans `/etc/subuid` et `/etc/subgid`, `newuidmap`/`newgidmap` (paquet `uidmap` sur Debian), un réseau sans privilège (pasta), cgroup v2 et une session systemd pour déléguer les cgroups.
2. Étiquettes : quatre entrées dans le fichier de données de `outils/netbox/` (M06-E05), `uv run modeliser.py --dry-run` puis sans. Sans elles, le fournisseur NetBox refuse de créer la VM (étiquette inconnue).
3. Kea : sur `dns01`, `sudo grep -n -B2 -A12 '"id": 99' /etc/kea/kea-dhcp4.conf` montre `"ddns-send-updates": true` pour le sous-réseau 99 et le suffixe global `"ddns-qualifying-suffix": "par1.medisphere.internal."` ; un bail récent est dans `/var/lib/kea/kea-leases4.csv` (nom d'hôte complet dans la colonne `hostname`). Kea ajoute le suffixe au nom **court** annoncé par le client (option 12) ; si le client annonce un nom complet (option 81), il le prend tel quel.

*B. Le module et les VMs.* Fichiers : [`tofu-modules/vm-noeud/`](fichiers/M12-E02/tofu-modules/vm-noeud/) (v2.4.0 : `variables.tf`, `main.tf`, `netbox.tf`, `outputs.tf`, `versions.tf`, `README.md`, `tests/m12.tftest.hcl`) et [`infra/envs/m12/`](fichiers/M12-E02/infra/envs/m12/) (`versions.tf`, `providers.tf`, `variables.tf`, `conteneurs.tf`, `terraform.tfvars.exemple`).

4. L'extension tient en quatre changements :
   - **validations** : `ipv4 = "dhcp"` accepté **sans** préfixe ; une carte DHCP ne porte pas `passerelle` (elle la reçoit de Kea) ;
   - **`local.idx_statiques`** : la liste des rangs des cartes à adresse imposée. `netbox_ip_address.carte[k]` décrit la carte `idx_statiques[k]`. Sans carte DHCP, la liste vaut `[0, 1, …]` : les adresses d'état `netbox_ip_address.carte[0]`, `[1]` des appelants de M08 et M10 **ne bougent pas** (passer à `for_each` les aurait toutes déplacées, donc détruites puis recréées dans NetBox) ;
   - **`netbox_primary_ip.ip`** devient conditionnel (`count`), avec un bloc **`moved`** de `netbox_primary_ip.ip` vers `netbox_primary_ip.ip[0]` : un appelant existant voit au plan « a été déplacé », pas « détruire, créer » ;
   - **`ip_config`** : `address = "dhcp"` pour une carte DHCP, l'adresse NetBox sinon ; sorties `dhcp` et `adresses_agent` (adresses vues par l'agent QEMU), `ipv4` vaut `null` en DHCP.
   La preuve de rétrocompatibilité : `tofu test` (fichier fourni) fait des plans avec des fournisseurs simulés (`mock_provider`) ; et, sur le lab, `tofu plan` de `envs/ceph` (si l'état existe encore) avec `?ref=v2.4.0` doit afficher **« No changes »**, à part les éventuels « has moved to ». Commit `feat(vm-noeud): carte en DHCP (ipv4 = "dhcp")` ; semantic-release pose `v2.4.0` si `v2.3.0` (M10) était la dernière étiquette.
   ```
   admin@adm01:~/src/tofu-modules/vm-noeud$ tofu init -backend=false && tofu test
   tests/m12.tftest.hcl... pass
     run "dhcp"... pass
     run "statique_m08"... pass
     run "dhcp_avec_prefixe_refuse"... pass
     run "dhcp_passerelle_refusee"... pass
   ```
5. `envs/m12` : un `for_each` sur une table `hôte => { n, famille, rôle }`, d'où se déduisent VMID (`2120 + n`), MAC (`bc:24:11:99:12:0n`) et étiquettes (`env-m12`, `role-<rôle>`). Le plan crée, par hôte : une VM NetBox, une interface, la VM Proxmox (**3 ressources**, 12 en tout). Aucune ressource DNS : le nom est publié par le **DDNS de Kea** au premier bail ; l'écrire aussi par `enregistrement-dns` (PowerDNS) ferait deux écrivains sur le même nom, et le premier bail renouvelé sur une autre adresse rendrait l'enregistrement d'OpenTofu faux. `apply` par le pipeline de `plateforme/infra` (le même que pour `envs/ceph`, avec le dossier `envs/m12` ajouté à sa matrice).
6. Résultat attendu :
   ```
   admin@adm01:~$ for h in ctr01 ctr02 ctr03 legacy01; do dig +short $h.par1.medisphere.internal; done
   10.10.99.131
   10.10.99.132
   10.10.99.133
   10.10.99.134
   ```
   (les adresses exactes dépendent de Kea, dans la plage dynamique `.100-.199`). Si un nom manque : sur `dns01`, `journalctl -u kea-dhcp-ddns --since -15min` (mise à jour refusée ? clé TSIG ?) et le bail dans `kea-leases4.csv` (colonne `hostname` vide = le client n'a pas annoncé de nom). Dans la VM (`qm terminal 212N` en dernier recours) : `hostname` doit être le nom de la VM (cloud-init le reçoit de Proxmox dans `meta-data`) ; un bail pris **avant** que cloud-init n'ait posé le nom n'a pas de nom : renouvelle-le (`sudo networkctl renew ens18` sur Debian si systemd-networkd gère la carte, `sudo nmcli device reapply ens18` sur Rocky).

*C. Ansible.*

7. [`inventories/lab/netbox-m12.yml`](fichiers/M12-E02/ansible/inventories/lab/netbox-m12.yml) et [`ansible.cfg.extrait`](fichiers/M12-E02/ansible/ansible.cfg.extrait). Sans IP primaire, le plugin NetBox ne pose pas `ansible_host` ; l'option `compose` le calcule : `ansible_host: inventory_hostname ~ '.par1.medisphere.internal'`, le nom publié par Kea (on évite de dépendre du domaine de recherche de `adm01`).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph env_m12
   @env_m12:
     |--ctr01
     |--ctr02
     |--ctr03
     |--legacy01
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph role_podman
   @role_podman:
     |--ctr02
     |--ctr03
   ```
8. Rôle [`docker_engine`](fichiers/M12-E02/ansible/roles/docker_engine/) : `preconditions.yml` (Debian 13, paquets en conflit retirés), `depot.yml` (clé téléchargée **à côté**, empreinte lue par `gpg --show-keys --with-colons`, comparée, puis seulement copiée dans `/etc/apt/keyrings/docker.asc` ; `deb822_repository` avec `signed_by` ; préférences APT à priorité 1001 ; index APT mis à jour par un gestionnaire), `paquets.yml` (`apt` avec `paquet=version` construits depuis `docker_engine_versions`), `configuration.yml` (`daemon.json` produit par `combine(…, recursive=true) | to_nice_json`, **validé par `dockerd --validate --config-file=%s`**, redémarrage par gestionnaire, `admin` dans `docker`), `controles.yml` (version du démon = version épinglée, `io.containerd.snapshotter.v1` dans `docker info`, Compose v5 et Buildx présents). Versions dans [`group_vars/role_docker/docker_engine.yml`](fichiers/M12-E02/ansible/inventories/lab/group_vars/role_docker/docker_engine.yml). Scénario [`molecule/docker_engine/`](fichiers/M12-E02/ansible/molecule/docker_engine/) : instance 2046, une clé `daemon.json` ajoutée pour prouver la fusion, `verify.yml` (version, stockage, journaux, `docker.io` absent, un conteneur de test).
   ```
   admin@adm01:~/src/ansible$ uv run molecule test -s docker_engine
   ```
9. Rôle [`podman_hote`](fichiers/M12-E02/ansible/roles/podman_hote/) : `preconditions.yml` (familles, cgroup v2, SELinux *enforcing* sur Rocky), `paquets.yml` (paquets communs + `podman_hote_paquets_famille[os_family]` ; sur Debian `uidmap`, `dbus-user-session`, `passt`, `slirp4netns` qui ne sont que des « Recommends » ; `systemd-container` pour `machinectl`, `acl` pour Ansible), `compte.yml` (compte `app` UID 1001 sans groupe, lecture de `/etc/subuid` et `/etc/subgid`, refus d'un chevauchement, `lineinfile` de la plage, `podman system migrate` par gestionnaire, `loginctl enable-linger` avec `creates:`, attente du bus de `/run/user/1001`), `configuration.yml` (fichiers dans `registries.conf.d/` et `containers.conf.d/`), `controles.yml` (`podman info --format json` **en tant que `app`** : sans privilège, `cgroupVersion` v2, `rootlessNetworkCmd` pasta, version 5.4.x ou 5.8.x selon la famille). Scénario [`molecule/podman_hote/`](fichiers/M12-E02/ansible/molecule/podman_hote/) (instance 2047, Debian) : `verify.yml` exécute un vrai conteneur sous `app` et lit sa table `uid_map` (`0 1001 1` puis `1 524288 65536`).
10. Rôle [`legacy_rdv`](fichiers/M12-E02/ansible/roles/legacy_rdv/) : paquets de la procédure (+ `php8.4-mbstring`, utilisé par le code mais oublié par InfoGér, et `php8.4-cli` pour la tâche cron), code par `ansible.posix.synchronize` **sans** `uploads/` (qui appartient à Apache et contient des données), dossiers `uploads/` et `/var/log/legacy-rdv` à `www-data`, contrôle « mot de passe du Vault = `DB_PASS` de `config.php` », base et compte créés **seulement s'ils manquent** (requête d'état d'abord, SQL par l'entrée standard, `no_log`), schéma importé une fois, hôte virtuel et cron **copiés depuis le dossier `vm/` du code** (tels quels), `logrotate`, contrôle de la page d'accueil. Variables : [`group_vars/role_legacy/legacy_rdv.yml`](fichiers/M12-E02/ansible/inventories/lab/group_vars/role_legacy/legacy_rdv.yml) et [`vault.yml.exemple`](fichiers/M12-E02/ansible/inventories/lab/group_vars/role_legacy/vault.yml.exemple), à chiffrer avec l'identité `lab`.
11. [`playbooks/conteneurs.yml`](fichiers/M12-E02/ansible/playbooks/conteneurs.yml) : garde-fou (exactement les quatre hôtes du plan, chacun dans le bon groupe de rôle), rôles communs (`base` sur Debian seulement), puis `docker_engine` sur `role_docker` et `podman_hote` sur `role_podman`. [`playbooks/legacy-rdv.yml`](fichiers/M12-E02/ansible/playbooks/legacy-rdv.yml) : `legacy_rdv` sur `role_legacy`, **depuis `adm01`**, parce que la source du code est la copie du workbook sur `adm01` : le runner n'en a pas (le projet `legacy/legacy-rdv` n'existe qu'en E19, où ce playbook pourra prendre le code dans GitLab et passer au pipeline). Écris-le dans la description de la MR : c'est une exception tracée, pas une habitude.
    ```
    admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/legacy-rdv.yml --check --diff
    admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/legacy-rdv.yml
    …
    TASK [legacy_rdv : Le contenu est celui de Legacy-RDV (et pas une page d'erreur)] ***
    ok: [legacy01]
    PLAY RECAP ***
    legacy01 : ok=… changed=0 … failed=0     (second passage)
    ```
12. Résultat attendu :
    ```
    admin@adm01:~$ ssh ctr01.par1.medisphere.internal 'docker version --format "{{.Server.Version}}"; docker info --format "{{json .DriverStatus}}"'
    29.8.2
    [["driver-type","io.containerd.snapshotter.v1"]]
    admin@adm01:~$ ssh ctr02.par1.medisphere.internal 'grep app /etc/subuid; loginctl show-user app -p Linger'
    app:524288:65536
    Linger=yes
    admin@adm01:~$ curl -s http://legacy01.par1.medisphere.internal/ | grep -o '<title>.*</title>'
    <title>Rendez-vous à venir - MédiSphère RDV</title>
    ```

*D. Documentation.*

13. `docs/conteneurs/hotes.md` : un tableau par hôte (rôle, système, moteur et version, compte d'exécution, ce qui y tourne au fil du module, comment le reconstruire : `tofu apply` de `envs/m12` puis les deux playbooks, dans cet ordre) et l'avertissement « environnement jetable, aucune donnée à garder ». Inventaire de la plateforme : les quatre VMs, avec la mention « adresse DHCP, nom DDNS ». Matrice des flux : rien sur la bordure au palier 1 : `adm01` (MGMT) joint déjà tout le lab, et le lab sort déjà vers Internet (dépôts, registres publics) ; les flux du palier 2 (registre de travail, `runner02`, ACME) seront ajoutés avec leurs exercices.

Le check vérifie la configuration Proxmox (nom, étiquettes, pool, CPU, mémoire, disque, carte et MAC, `ip=dhcp`), le nom dans le DNS (plage dynamique), NetBox, le système de chaque hôte, Docker (version, paquets, stockage, dépôt et clé, épinglage, `daemon.json`, groupe), Podman (versions, compte `app`, plage, linger, registres, sans-privilège vérifié en tant que `app`), SELinux sur `ctr03`, Legacy-RDV (services, PHP, fichiers, page servie à `adm01`) et le code sur `main` (dont le Vault chiffré).

**Explications**

- **DHCP pour des VMs jetables.** Les nœuds de cluster (Ceph, OpenStack, Kubernetes) ont des adresses **du plan**, parce que d'autres configurations les citent (moniteurs Ceph, VIP, voisins BGP). Les hôtes de ce module ne sont cités par personne par leur adresse : un nom suffit, et Kea sait le publier. La MAC imposée garde le même bail d'une reconstruction à l'autre (Kea reconnaît le client), ce qui évite les surprises de cache DNS et de `known_hosts`.
- **Pourquoi `moved` et pas un `for_each`.** Un module partagé a des consommateurs dont on ne voit pas l'état. Changer l'adresse d'état d'une ressource (de `carte[0]` à `carte["0"]`) sans `moved` fait détruire et recréer l'objet : pour NetBox, une adresse « supprimée puis recréée » perd son identifiant, ses liens et son historique. La règle d'une version mineure : **le plan d'un appelant existant ne change pas**.
- **La clé, contrôlée avant usage.** `get_url` puis `copy` vers `/etc/apt/keyrings` en un seul geste ferait confiance à ce que le serveur renvoie ce jour-là. Télécharger à côté, lire l'empreinte, comparer à la valeur publiée (et versionnée dans le rôle), puis seulement installer : une clé substituée n'est jamais utilisée. `Signed-By` limite cette clé à **ce** dépôt (une clé dans `trusted.gpg.d` vaudrait pour tous les dépôts).
- **Épingler deux fois.** Les versions exactes dans `apt` installent la bonne version ; le fichier de préférences empêche qu'un `apt upgrade` à la main (ou `unattended-upgrades` mal configuré) la change. Monter de version devient une **MR** sur une ligne d'inventaire, relue et passée par Molecule.
- **`daemon.json` validé.** Un `daemon.json` invalide empêche `dockerd` de redémarrer : tous les conteneurs restent arrêtés. `dockerd --validate` refuse la clé inconnue ou le JSON faux **avant** que le fichier ne remplace l'ancien. Le dictionnaire fusionné permet aux exercices suivants (E18 journaux, E26 durcissement, E28 métriques) d'ajouter des clés par l'inventaire sans toucher au rôle.
- **`default-address-pools`.** Docker prend ses réseaux dans 172.17-31.0.0/16, puis dans 192.168.0.0/16 : le 30e réseau Compose d'un poste peut tomber sur le LAN maison et rendre l'hôte injoignable depuis chez toi. Une plage déclarée, découpée en /24, rend l'allocation prévisible (et lisible dans la matrice des flux).
- **Le compte `app` sans sudo.** C'est tout l'intérêt du sans-privilège : un compte qui peut faire tourner des conteneurs **sans pouvoir devenir root**. Lui donner sudo, ou le groupe `docker`, annulerait la démonstration. La plage subordonnée est **fixée** (et non laissée au hasard de `useradd`) pour être la même sur tous les hôtes Podman : les UID des fichiers de volumes sont alors prévisibles (E06, E36).
- **Legacy-RDV tel quel.** Automatiser l'existant avant de le changer, c'est se donner une **référence reproductible** : on pourra comparer le comportement de l'image (E19) à celui de la VM, requête par requête, et refaire la VM en dix minutes si on la casse. « Corriger » au passage (mot de passe sorti du code, journal sur stdout) ferait perdre cette référence.

**Alternatives**

- **Adresses imposées dans `vsandbox` (.10-.49)** avec `vm-noeud` tel quel et `enregistrement-dns` : aucune extension du module, adresses connues au plan (utile pour une règle de pare-feu par adresse). Défendable ; on perd l'exercice et l'intérêt du DDNS déjà en place.
- **Un module `vm-sandbox` séparé** : plus simple à lire, un module de plus à maintenir pour 90 % de code commun.
- **Docker depuis `docker.io` (Debian)** : signé par Debian, maintenu par l'équipe de sécurité de Debian, mais en 26.1, sans le stockage d'images containerd par défaut ni Compose v5 ; c'est un choix possible pour un parc qui préfère la stabilité de la distribution (à écrire dans l'ADR-0120, M12-E31).
- **`apt-mark hold`** au lieu des préférences APT : marche aussi, mais il faut lever le « hold » à chaque montée de version (et l'oublier bloque les correctifs).
- **Rôles de la communauté** (`geerlingguy.docker`, collection `containers.podman`) : rapides, mais d'autres choix par défaut (clé non vérifiée par empreinte, `latest`) ; à relire au même niveau d'exigence que notre code.
- **Podman sur Debian depuis un dépôt tiers (OBS/Kubic)** pour avoir une 5.8 : abandonné par l'amont pour Debian ; on garde la version de la distribution et on documente les écarts (`podman quadlet install` absent en 5.4).

**Pièges classiques**

- Oublier de retirer `containerd` ou `runc` de Debian (installés par un autre paquet, ou par une image dorée « riche ») : APT refuse `containerd.io` ou, pire, on obtient deux containerd.
- Mettre `docker.asc` dans `/etc/apt/trusted.gpg.d/` : la clé de Docker valide alors **tous** les dépôts.
- `daemon.json` écrit sans validation, avec une virgule en trop : `dockerd` ne redémarre plus, et le gestionnaire Ansible échoue au pire moment.
- Installer Podman sur Debian avec `install_recommends: false` (réflexe d'image minimale) : sans `passt` et `uidmap`, `podman run` sans privilège échoue avec un message peu clair sur `newuidmap` ou le réseau.
- Tester Podman « en tant que `app` » avec `sudo -u app podman …` : avertissements sur les cgroups, `XDG_RUNTIME_DIR` absent, et des conteneurs qui ne se comportent pas comme dans une vraie session (E06).
- Écrire la plage de `app` sans regarder celle d'`admin` (souvent `100000:65536`) : deux comptes qui partagent des UID subordonnés peuvent lire les fichiers des conteneurs l'un de l'autre.
- Laisser `enregistrement-dns` **et** le DDNS écrire le même nom : à la reconstruction, deux réponses ou une réponse fausse.
- Lancer `legacy-rdv.yml` depuis le pipeline : le runner n'a pas `~/DevOpsPrivateCloud`, le rôle s'arrête dès les préconditions (c'est voulu).
- Mot de passe de Legacy-RDV différent dans le Vault et dans `config.php` : la page affiche « Service momentanément indisponible » (et le journal applicatif le dit, si le dossier existe).

**En production chez MédiSphère**

Les hôtes de conteneurs seraient des VMs **du socle** (état `socle`, adresses du plan, supervisées, sauvegardées), en nombre pair pour pouvoir en vider un pendant une mise à jour. Les paquets Docker passeraient par un **miroir APT interne** (Pulp, Aptly ou le cache du futur Harbor pour les images) plutôt que par Internet, avec la même vérification d'empreinte. Les montées de version de Docker seraient proposées par Renovate (M13) sur `group_vars/role_docker/docker_engine.yml`, testées en Molecule, appliquées un hôte à la fois. Legacy-RDV n'aurait jamais dû être reconstruit à la main : sa VM « à l'ancienne » sert ici de banc d'essai et disparaît avec le module.

---

### M12-E03 — Premiers conteneurs avec Docker : cycle de vie

**Solution**

1. Le moteur :
   ```
   admin@ctr01:~$ docker info --format '{{.Driver}} {{json .DriverStatus}} {{.CgroupDriver}} cgroup v{{.CgroupVersion}} {{.DefaultRuntime}} {{json .SecurityOptions}}'
   overlayfs [["driver-type","io.containerd.snapshotter.v1"]] systemd cgroup v2 runc ["name=apparmor","name=seccomp,profile=builtin","name=cgroupns"]
   ```
   `overlayfs` + `io.containerd.snapshotter.v1` : les images et les couches sont gérées par **containerd** (son *snapshotter* overlayfs), et non plus par le pilote `overlay2` de Docker. Pilote de cgroups `systemd`, cgroup v2, runtime `runc`, AppArmor et seccomp actifs, espace de noms `cgroup` privé. Le stockage : `/var/lib/docker/` garde les conteneurs, les volumes, les réseaux, l'état de BuildKit ; `/var/lib/containerd/` garde le contenu (`io.containerd.content.v1.content/blobs/sha256/`) et les instantanés (`io.containerd.snapshotter.v1.overlayfs/`). `sudo ctr namespaces ls` montre `moby` (Docker) ; `sudo ctr -n moby images ls` liste les images de Docker vues par containerd. Kubernetes (M14) utilisera l'espace `k8s.io` du même containerd.
2. PID 1 = `cat` puis `bash` ; deux processus au plus (`bash` et ta commande) ; le nom d'hôte est l'identifiant court du conteneur (espace `uts`). Après `exit`, rien ne reste avec `--rm` (sinon un conteneur `Exited (0)` dans `docker ps -a`).
3. Le serveur web répond ; `docker logs` montre la ligne d'accès de la requête de `adm01`. Dans l'image officielle, `/var/log/nginx/access.log` et `error.log` sont des **liens symboliques** vers `/dev/stdout` et `/dev/stderr` : le moteur collecte la sortie standard (pilote `json-file`, avec la rotation de `daemon.json`).
4. `docker diff` liste `A` (ajouté), `C` (modifié), `D` (supprimé) par rapport à l'image :
   ```
   C /usr/share/nginx/html/index.html
   C /var/cache/nginx
   A /var/cache/nginx/client_temp
   …
   A /run/nginx.pid
   ```
   La modification vit dans la **couche inscriptible** du conteneur (son instantané containerd) : elle survit à `stop`/`start` et au redémarrage du démon, et **disparaît** avec `docker rm`. C'est pourquoi la configuration se monte et les données vont dans des volumes (E07).
5. `docker top` montre nginx (maître en root, travailleurs en `nginx`). `ps -ef --forest` :
   ```
   root   1234     1  … /usr/bin/containerd-shim-runc-v2 -namespace moby -id 5c89… -address /run/containerd/containerd.sock
   root   1256  1234  …  \_ nginx: master process nginx -g daemon off;
   101    1290  1256  …      \_ nginx: worker process
   ```
   Le parent de nginx est le **shim** (`containerd-shim-runc-v2`), lui-même rattaché à PID 1 de l'hôte : ni `dockerd` ni `containerd` ne sont ses parents. Le cgroup : `0::/system.slice/docker-<id>.scope` (pilote systemd). Les liens de `/proc/$PID/ns/` diffèrent de ceux de `/proc/self/ns/` pour `mnt`, `pid`, `net`, `uts`, `ipc`, `cgroup` ; **pas** pour `user` (pas d'espace `user` avec Docker par défaut) ni, en général, `time`.
6. `docker stop` envoie `SIGTERM`, attend 10 s, puis `SIGKILL`. `sleep` en PID 1 n'a pas de gestionnaire de `SIGTERM` : le noyau ne le lui délivre pas, il faut attendre le `SIGKILL`. Code 137 = 128 + 9 (`SIGKILL`). `docker kill -s TERM` ne ferait **rien** (même raison) ; `docker kill` (par défaut `SIGKILL`) l'arrêterait aussitôt. Avec `--init` (« pour aller plus loin ») : `docker-init` (tini) en PID 1 reçoit `SIGTERM`, le relaie à `sleep`, qui meurt aussitôt : arrêt immédiat, code 143 (128 + 15).
7. Quatre démarrages (le premier + trois redémarrages), espacés de plus en plus : Docker double le délai entre deux tentatives (à partir de 100 ms) pour ne pas emballer la machine sur un conteneur qui échoue en boucle ; le délai revient à zéro si le conteneur a tenu au moins 10 s.
   ```
   admin@ctr01:~$ docker inspect -f '{{.RestartCount}} {{.State.Status}} {{.State.ExitCode}}' m12-e03-crash
   3 exited 3
   ```
   `docker events` montre la suite `start`, `die` (avec `exitCode=3`), `restart`…
8. Après `systemctl restart docker` : `m12-e03-web` redémarre (`unless-stopped`, il tournait) ; `m12-e03-sommeil` reste arrêté (pas de politique, `no` par défaut) ; `m12-e03-crash` reste arrêté (il avait épuisé ses tentatives et était `exited` ; `on-failure` ne relance pas au démarrage du démon un conteneur arrêté). Retiens : `unless-stopped` se souvient d'un `docker stop` **volontaire** ; `always` relancerait même un conteneur arrêté à la main, au prochain démarrage du démon.
9. Exemples :
   ```
   admin@ctr01:~$ docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' m12-e03-web
   admin@ctr01:~$ docker inspect -f '{{json .HostConfig.PortBindings}}' m12-e03-web
   admin@ctr01:~$ docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' m12-e03-web
   admin@ctr01:~$ docker inspect -f '{{.Image}}' m12-e03-web
   admin@ctr01:~$ docker inspect -f '{{.State.StartedAt}}' m12-e03-web
   ```
   Avec le stockage containerd, `.Image` est l'empreinte de l'**index** de l'image (voir E04).
10. Fiche de Nadia : `docker ps -a` (tout, y compris l'arrêté), `docker logs --since 10m -f <c>`, `docker inspect -f '{{.State.Status}} {{.State.ExitCode}} {{.State.OOMKilled}} {{.RestartCount}}' <c>`, `docker exec -it <c> sh`, `docker events --since 30m --filter container=<c>`, `docker stats --no-stream`. Codes : **0** sortie normale ; **137** tué par `SIGKILL` (délai de `stop` dépassé, ou tueur OOM : regarder `OOMKilled`) ; **143** arrêté proprement par `SIGTERM`. Autres codes = code de l'application (1, 2, 3…) : lire ses journaux.

Le check vérifie l'état, l'image, la politique et la publication de `m12-e03-web`, la modification visible dans `docker diff`, la page servie à `adm01`, le code 137 de `m12-e03-sommeil` et la politique, le compteur et le code de `m12-e03-crash`.

**Explications**

- **Un conteneur, trois couches de supervision.** `dockerd` (API, réseau, volumes, politiques de redémarrage), `containerd` (images, conteneurs, tâches), le **shim** (un par conteneur, parent du processus, garde les flux d'entrée-sortie et le code de sortie). C'est le shim qui permet de redémarrer containerd, et avec `live-restore` dockerd (E26), sans tuer les conteneurs.
- **La politique de redémarrage est appliquée par `dockerd`.** Elle n'est pas dans le conteneur : si le démon ne tourne pas, rien ne redémarre ; en production, un conteneur important est donc soit sous systemd (Quadlet, E14), soit sous un orchestrateur (Kubernetes).

**Alternatives**

- `docker container run/ls/rm` (forme longue des commandes) : plus explicite dans les scripts.
- Podman : mêmes commandes (`podman run`, `logs`, `inspect`), politiques de redémarrage appliquées par systemd (`podman-restart.service` ou Quadlet), puisqu'il n'y a pas de démon.

**Pièges classiques**

- Confondre `docker stop` (poli, puis brutal) et `docker kill` (brutal d'emblée), et conclure « l'application ne gère pas l'arrêt » alors que c'est le PID 1 qui ne relaie pas.
- `--restart always` sur un conteneur qui échoue au démarrage : il boucle indéfiniment (avec des délais croissants), remplit les journaux et masque la cause (runbook RB-120, E23).
- Modifier un conteneur par `docker exec` « pour dépanner » et oublier : la correction disparaît au prochain `docker rm` ou à la prochaine mise à jour.
- Chercher les couches sous `/var/lib/docker/overlay2` (tutoriels d'avant Docker 29) : avec le stockage containerd, ce dossier n'existe plus sur une installation neuve.

**En production chez MédiSphère**

L'astreinte ne fait ni `exec` ni modification à chaud sur un conteneur de production : elle lit (`logs`, `inspect`, `events`, métriques), puis corrige par le code (image, configuration, déploiement). La fiche de Nadia devient le début du runbook RB-120 (E23), et les journaux partent vers la plateforme de journaux (M22) plutôt que d'être lus sur l'hôte.

---

### M12-E04 — Images, couches, manifestes et empreintes

**Solution**

1. Le document de tête est un **index** OCI :
   ```
   admin@ctr02:~$ skopeo inspect --raw docker://docker.io/library/python:3.13-slim-trixie | jq '{mediaType, n: (.manifests | length), plateformes: [.manifests[].platform | "\(.os)/\(.architecture)\(.variant // "" | if . != "" then "/" + . else "" end)"]}'
   {
     "mediaType": "application/vnd.oci.image.index.v1+json",
     "n": 16,
     "plateformes": ["linux/amd64", "unknown/unknown", "linux/arm/v5", "unknown/unknown", …]
   }
   ```
   (le nombre exact dépend de l'image). Les entrées `unknown/unknown` sont des **manifestes d'attestation** (annotations `vnd.docker.reference.type: attestation-manifest` et `vnd.docker.reference.digest: <manifeste décrit>`) : provenance et SBOM produits par BuildKit, rattachés à une plateforme. La somme `sha256sum` de la sortie brute **est** le champ `Digest` de `skopeo inspect` (Skopeo rapporte l'empreinte du document de tête, ici l'index, et lit la configuration et les couches de l'entrée de ta plateforme).
2. Le manifeste `linux/amd64` liste une configuration (`application/vnd.oci.image.config.v1+json`, avec son empreinte et sa taille) et quatre ou cinq couches (`…layer.v1.tar+gzip`) avec leurs tailles compressées (la couche Debian ≈ 30 Mo, puis Python ≈ 15 Mo, puis quelques petites). La configuration contient `Env` (`PATH`, `LANG`, `GPG_KEY`, `PYTHON_VERSION`, `PYTHON_SHA256`), `Cmd` (`["python3"]`), pas de `User` (root par défaut !), l'historique des instructions qui ont construit l'image. Elle a une empreinte parce que le manifeste la désigne **par son contenu**, comme les couches : changer une variable change la configuration, donc son empreinte, donc le manifeste, donc l'index. Rien ne peut être modifié sans changer l'empreinte de tête.
3. L'*OCI layout* :
   ```
   admin@ctr02:~/m12/e04/debian-oci$ cat oci-layout index.json | jq -c .
   {"imageLayoutVersion":"1.0.0"}
   {"schemaVersion":2,"manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:918311b7…","size":1021,"annotations":{"org.opencontainers.image.ref.name":"trixie-slim"}}]}
   ```
   Chaque fichier de `blobs/sha256/` s'appelle par la **somme de son contenu** (adressage par le contenu : c'est vérifiable par n'importe qui). Il y a trois blobs : le manifeste (`918311b7…`, petit JSON), la configuration (JSON), la couche (archive `tar.gz` qui commence par `./`, `bin`, `boot/`…). L'empreinte de `index.json` est celle de l'entrée **`linux/amd64`**, pas celle de l'index public : sans `--all`, Skopeo ne copie que la plateforme de l'hôte et écrit un index local qui ne pointe que vers elle.
4. `gunzip -c blobs/sha256/<couche> | sha256sum` = le `diff_id` de la configuration (`rootfs.diff_ids`). Deux empreintes pour deux usages : l'empreinte du **blob** (compressé) pour le transport et le stockage dans le registre ; le `diff_id` (décompressé) pour identifier le **contenu du système de fichiers**, indépendamment de la compression (un registre peut recompresser, gzip ou zstd, sans changer le `diff_id`).
5. Docker 29 :
   ```
   admin@ctr01:~$ docker image ls --tree
   IMAGE                ID             DISK USAGE   CONTENT SIZE   EXTRA
   debian:trixie-slim   a29215f6a35e        119MB         31.8MB
   ├─ linux/amd64       918311b7b6c4        118MB         29.8MB
   ├─ linux/arm/v5      dbc392c622e7           0B             0B
   ├─ linux/arm64/v8    a2ca65377c25           0B             0B
   …
   ```
   Avec le stockage containerd, l'`Id` de l'image **est l'empreinte de l'index** (`a29215f6…`), et `RepoDigests` la reprend ; `--tree` montre toutes les plateformes de l'index, à 0 octet pour celles qui ne sont pas tirées. `RootFS.Layers` donne les **`diff_id`** (couches décompressées), comme l'ancien stockage. « Disk usage » compte le contenu compressé **et** l'instantané décompressé, d'où un chiffre plus grand que « content size ». `docker buildx imagetools inspect` montre l'index et ses entrées (avec les attestations), `docker image history` les instructions de construction.
6. Tirer par empreinte d'index fonctionne sur toute plateforme (le moteur choisit l'entrée de la sienne) et ne peut plus jamais désigner autre chose.

7. Exemple de `~/m12/e04/images-de-base.txt` (empreintes du 8 octobre 2026, relève les tiennes) :
   ```
   # Empreinte de l'INDEX : une seule ligne vaut pour toutes les plateformes (amd64, arm64 au M12-E12),
   # et chaque moteur y choisit son manifeste ; l'empreinte linux/amd64 casserait une construction arm64.
   docker.io/library/debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
   docker.io/library/python:3.13-slim-trixie@sha256:<EMPREINTE>
   docker.io/library/golang:1.26-trixie@sha256:<EMPREINTE>
   docker.io/library/postgres:18-trixie@sha256:74935e72241653ca55e0414067e6d8763aceb8a810eb51b452253ec3dcfc4336
   docker.io/valkey/valkey:8-trixie@sha256:640c5e62cea04b6d6f2084232651d0cc70362d31f4f805e7be94dbed6855e8f2
   ```
   Pour relever une empreinte d'index sans rien tirer : `skopeo inspect --raw docker://<image> | sha256sum`, ou `skopeo inspect docker://<image> | jq -r .Digest`, ou `docker buildx imagetools inspect <image>` (ligne `Digest`).
8. Une construction épinglée **ne reçoit plus** les correctifs : si Debian republie `trixie-slim` pour une faille d'OpenSSL, `FROM …@sha256:<ancienne>` construit toujours l'image vulnérable. L'épinglage impose donc un **processus de mise à jour** : quelqu'un (ou quelque chose) doit proposer la nouvelle empreinte, la faire tester et la fusionner, régulièrement et vite en cas d'alerte. C'est la reconstruction hebdomadaire des images `bibliotheque/*` (M12-E27) et Renovate (M13), qui ouvre la MR « mise à jour de l'empreinte ». Épingler sans ce processus, c'est figer ses vulnérabilités.

Le check vérifie la liste (cinq images, format, et dans le registre, que chaque empreinte désigne bien un **index**), le dossier OCI de `ctr02` (valide, et dont le manifeste est l'entrée `linux/amd64` de l'index épinglé de Debian) et la présence de l'image épinglée sur `ctr01`.

**Explications**

- **Trois niveaux d'empreintes.** Index → manifeste (par plateforme) → configuration et couches. Chaque niveau désigne le suivant par empreinte : l'empreinte de tête garantit l'intégrité de **tout** ce qui est dessous (un arbre de Merkle). C'est ce qui permet de signer une image en signant une seule empreinte (Cosign, M13).
- **Les attestations.** BuildKit (Docker Hub les produit pour les images officielles) attache la provenance (comment et d'où l'image a été construite) et souvent un SBOM, comme manifestes `unknown/unknown` de l'index. Docker 29, avec le stockage containerd, sait les conserver localement et les pousser.

**Alternatives**

- `crane digest`, `regctl image digest` (PLAN §6, facultatifs) : mêmes informations, outils spécialisés.
- `docker manifest inspect` : ancien, à éviter (expérimental, ne connaît pas toutes les formes OCI).
- Épingler l'empreinte de plateforme quand on ne construit et n'exécute **que** sur amd64 : plus strict (on fixe le manifeste exact), mais casse le jour où une machine arm64 arrive.

**Pièges classiques**

- Calculer l'empreinte d'un JSON reformaté (`jq .`) : la somme change, elle ne correspond à rien dans le registre.
- Confondre `diff_id` et empreinte de couche, puis chercher en vain une couche du registre dans `RootFS.Layers`.
- Recopier une empreinte d'un tutoriel ou d'un corrigé : elle désigne une image ancienne, peut-être vulnérable, ou disparue du registre.
- Croire qu'une étiquette « versionnée » (`3.13.16-slim`) est immuable : les images officielles sont reconstruites (correctifs de Debian) sous les mêmes étiquettes.
- Chercher le champ `Digest` de `skopeo inspect` comme empreinte de plateforme : c'est celle du document de tête.

**En production chez MédiSphère**

Les images de base ne viennent pas directement de Docker Hub : elles passent par le cache Harbor (M13), sont reconstruites et signées en `bibliotheque/*` (E27), et les Dockerfile des applications les désignent **par empreinte**, mises à jour par Renovate. La liste de ce fichier devient la liste des images autorisées des normes (E33), et l'inventaire HDS répond « que tourne-t-il ? » par des empreintes, des SBOM et des signatures.

---

### M12-E05 — Un premier Dockerfile pour MédiAgenda

**Solution**

1. Projet : `mediagenda/api`, privé, vide (sans README) ; premier commit :
   ```
   admin@adm01:~/src$ mkdir mediagenda-api && cd mediagenda-api && cp -r ~/DevOpsPrivateCloud/apps/mediagenda/. .
   admin@adm01:~/src/mediagenda-api$ rm -rf .venv .pytest_cache .ruff_cache && find . -name __pycache__ -prune -exec rm -rf {} +
   admin@adm01:~/src/mediagenda-api$ git init -b main && git add . && git commit -m "feat: import de MédiAgenda 1.0.0 depuis le workbook"
   admin@adm01:~/src/mediagenda-api$ git remote add origin git@git01.par1.medisphere.internal:mediagenda/api.git && git push -u origin main
   admin@adm01:~/src/mediagenda-api$ uv sync --locked && uv run pytest
   ```
   Puis : `main` protégée (fusion par MR, personne ne pousse directement), `julien.petit` mainteneur, `karim.benali` développeur.
2. [`Dockerfile`](fichiers/M12-E05/mediagenda-api/Dockerfile) et [`.dockerignore`](fichiers/M12-E05/mediagenda-api/.dockerignore). L'essentiel :
   ```dockerfile
   FROM docker.io/library/python:3.13-slim-trixie
   COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /usr/local/bin/uv
   ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never PYTHONUNBUFFERED=1
   WORKDIR /app
   COPY pyproject.toml uv.lock ./
   RUN uv sync --locked --no-dev --no-install-project
   COPY README.md ./
   COPY src ./src
   COPY migrations ./migrations
   RUN uv sync --locked --no-dev
   ENV PATH="/app/.venv/bin:${PATH}"
   ARG VERSION=0.1.0
   ENV MEDIAGENDA_VERSION=${VERSION}
   RUN useradd --system --uid 10001 --user-group --no-create-home --shell /usr/sbin/nologin mediagenda
   USER 10001:10001
   EXPOSE 8000
   CMD ["mediagenda"]
   ```
3. Construction : une quinzaine d'étapes BuildKit ; les longues sont le premier tirage des images (Python, uv) et `uv sync --no-install-project` (téléchargement et installation de FastAPI, psycopg, etc.) ; la seconde `uv sync` ne fait qu'installer le projet lui-même (secondes).
4. Cache : après modification de `app.py`, tout est `CACHED` jusqu'à `COPY src ./src` ; seules cette copie, la seconde `uv sync`, puis les étapes suivantes sont refaites (rapide). Après modification de `pyproject.toml`, la couche `COPY pyproject.toml uv.lock` change, donc **tout** ce qui suit est refait, dépendances comprises — même pour une ligne vide : BuildKit compare le **contenu** des fichiers, pas leur sens.
5. Inspection :
   ```
   admin@ctr01:~$ docker image ls mediagenda-api
   IMAGE                  ID             DISK USAGE   CONTENT SIZE   EXTRA
   mediagenda-api:0.1.0   86317a0c8a72        367MB           89MB
   admin@ctr01:~$ docker image inspect mediagenda-api:0.1.0 --format '{{json .Config.User}} {{json .Config.Cmd}} {{json .Config.Entrypoint}} {{json .Config.ExposedPorts}}'
   "10001:10001" ["mediagenda"] null {"8000/tcp":{}}
   admin@ctr01:~$ docker run --rm --entrypoint id mediagenda-api:0.1.0
   uid=10001(mediagenda) gid=10001(mediagenda) groups=10001(mediagenda)
   ```
   `docker image history` : la couche la plus lourde est celle des dépendances (`uv sync --no-install-project` : ≈ 91 Mo, dont `psycopg[binary]` et ses bibliothèques), puis le binaire `uv` (≈ 54 Mo), puis l'image Python ; le code et les migrations pèsent quelques dizaines de ko. 367 Mo « sur disque » comptent le contenu compressé **et** décompressé ; 89 Mo de contenu compressé, c'est ce qui transite par le registre. uv n'a rien à faire à l'exécution : le multi-étapes (E10) et le cache (E11) le sortiront de l'image finale.
6. Sans configuration :
   ```
   admin@ctr01:~$ docker run --rm mediagenda-api:0.1.0; echo "code=$?"
   {"horodatage": "…", "niveau": "CRITICAL", "journal": "mediagenda", "message": "configuration invalide : variable(s) obligatoire(s) absente(s) : MEDIAGENDA_DB_URL, MEDIAGENDA_VALKEY_URL"}
   code=2
   ```
   Avec des adresses fictives : `/sante` → `{"statut":"ok","version":"0.1.0"}` (200 : le processus vit, il ne regarde aucune dépendance) ; `/pret` → 503 (PostgreSQL et Valkey injoignables : l'instance ne doit pas recevoir de trafic). Les journaux sont des lignes **JSON** sur la sortie standard (dont les avertissements `dépendance indisponible`).
7. `docker stop` rend la main en moins d'une seconde, code 0 : `mediagenda` (uvicorn) est le PID 1, il reçoit `SIGTERM`, ferme les connexions et sort ; `sleep` (E03) l'ignorait.
8. MR : description avec les exigences cochées, les commandes, la taille. Points que Karim relève souvent : l'image de base sans nom complet, `uv` non épinglé, un `COPY . .` avant `uv sync`, `USER` par nom.

Le check vérifie le projet GitLab (branche, fichiers), le contenu du `Dockerfile` (nom complet de l'image de base, pas de `latest`, uv 0.12.23 sans `curl | sh` ni `pip install`, verrou et étape sans le code, `USER` non root, forme exec) et du `.dockerignore`, l'image sur `ctr01` (utilisateur 10001, commande exec, port, version, pas d'URL de service dans l'environnement), le conteneur `m12-e05-api` et sa réponse `/sante` à `adm01`.

**Explications**

- **`COPY --from=<image>`** copie un fichier d'une autre image sans en faire une étape de construction : on obtient un binaire `uv` officiel, épinglé, sans exécuter de script d'installation. Ce n'est pas encore du multi-étapes (l'image finale contient toujours uv).
- **Deux `uv sync`.** Le premier (`--no-install-project`) n'installe que les dépendances du verrou : sa couche ne dépend que de `pyproject.toml` et `uv.lock`. Le second installe le projet (le code, les points d'entrée `mediagenda` et `mediagenda-migrate`). `--locked` refuse un verrou désynchronisé de `pyproject.toml` : on construit **exactement** ce que les tests ont validé. `--no-dev` écarte pytest et ruff.
- **`UV_COMPILE_BYTECODE`, `UV_LINK_MODE`.** Les `.pyc` sont produits à la construction (le conteneur, non root et bientôt en lecture seule, ne pourrait pas les écrire au démarrage) ; `copy` évite les liens durs vers un cache absent de l'image.
- **UID numérique.** `USER 10001:10001` : Kubernetes (`runAsNonRoot`) et les politiques (Kyverno, M26) ne peuvent vérifier qu'un nombre ; un UID élevé et fixe ne coïncide avec aucun compte de l'hôte, et les droits des volumes se préparent d'avance.
- **Forme exec.** `CMD ["mediagenda"]` : pas de shell, `mediagenda` est le PID 1, il reçoit les signaux (README, « Arrêt propre »).
- **`MEDIAGENDA_VERSION` par `ARG`.** La version vient de la chaîne de construction (`--build-arg VERSION=…`, puis la CI en E21) et se lit dans `/sante` : on sait ce qui tourne.

**Alternatives**

- **Image de base avec uv** (`ghcr.io/astral-sh/uv:python3.13-trixie-slim`) : une ligne de moins, mais une base maintenue par un tiers, moins standard que l'image officielle Python, et qu'il faudrait elle aussi épingler et reconstruire (E27).
- **`uv export` + `pip install -r`** : sans uv dans l'image finale ; plus de pièces (fichier exporté, pip), et l'on perd la vérification du verrou au moment de la construction si l'on n'y prend pas garde.
- **Multi-étapes dès maintenant** (constructeur avec uv, image finale avec le seul `.venv`) : c'est E10/E11 ; le ticket demandait « rien de sophistiqué ».
- **Image *distroless* Python** : plus petite et sans shell, mais le Python de l'image doit être celui du `.venv` (même chemin, même version) ; à étudier avec les normes (E33).

**Pièges classiques**

- `uv sync` sans `--locked` : uv peut **résoudre à nouveau** et installer d'autres versions que celles testées.
- Oublier `COPY README.md` : `uv_build` échoue (« README.md not found ») à la seconde `uv sync`, puisque `pyproject.toml` le déclare.
- `COPY . .` avant `uv sync` : chaque modification de code reconstruit toutes les dépendances ; et sans `.dockerignore`, le `.venv` de `adm01` (avec des chemins et un Python de l'hôte) écrase celui de l'image.
- `USER mediagenda` (par nom) : refusé par `runAsNonRoot` de Kubernetes (« image has non-numeric user »).
- `CMD mediagenda` (forme shell) : `/bin/sh -c` en PID 1, arrêt en 10 s et code 137.
- `ENV MEDIAGENDA_DB_URL=…` « pour tester » : le mot de passe part dans l'image (E01, question 15).
- Construire sur `adm01` : pas de Docker sur le poste d'administration, et c'est voulu.

**En production chez MédiSphère**

L'image est construite par la CI (E21), jamais sur un poste, à partir d'une base `bibliotheque/python` épinglée par empreinte (E27), analysée (Hadolint, Dive en E16 ; Trivy au M13), étiquetée par la version sémantique **et** l'empreinte du commit, signée (M13). La version de l'image suit les étiquettes Git du projet (semantic-release), pas une valeur écrite à la main.

---

### M12-E06 — Podman sans privilège

**Solution**

1. `sudo -u app podman info` affiche des avertissements du type « The cgroupv2 manager is set to systemd but there is no systemd user session available » et « Falling back to --cgroup-manager=cgroupfs », parfois une erreur sur `XDG_RUNTIME_DIR` : `sudo` change d'UID mais **n'ouvre pas de session** logind, il n'y a ni `XDG_RUNTIME_DIR` ni gestionnaire systemd de l'utilisateur à qui déléguer les cgroups. `machinectl shell app@` ouvre une vraie session : `XDG_RUNTIME_DIR=/run/user/1001`, `systemctl --user is-system-running` → `running`. Le **linger** fait exister ce gestionnaire en permanence, même sans session : c'est lui qui garde les conteneurs et les unités Quadlet (E14) après la déconnexion et au démarrage de la machine.
2. ```
   app@ctr02:~$ podman info --format '{{.Host.Security.Rootless}} {{.Host.RootlessNetworkCmd}} {{.Host.CgroupsVersion}} {{.Store.GraphRoot}} {{.Store.RunRoot}}'
   true pasta v2 /home/app/.local/share/containers/storage /run/user/1001/containers
   ```
   Les images de `app` sont dans **son** dossier personnel ; celles de root (s'il en avait) dans `/var/lib/containers/storage`. Deux comptes ne partagent ni images ni conteneurs.
3. ```
   app@ctr02:~$ podman unshare cat /proc/self/uid_map
            0       1001          1
            1     524288      65536
   app@ctr02:~$ podman unshare id
   uid=0(root) gid=0(root) groups=0(root)
   ```
   Ligne 1 : l'UID 0 de l'espace correspond à l'UID 1001 (`app` lui-même), pour 1 identifiant. Ligne 2 : les UID 1 à 65536 de l'espace correspondent aux UID 524288 à 589823 de l'hôte (la plage subordonnée). C'est `newuidmap` (paquet `uidmap`) qui écrit la table, au nom de `app` : un processus ordinaire n'a le droit d'écrire dans `uid_map` que sa propre identité ; écrire la plage subordonnée demande un programme privilégié (`setuid` root ou porteur de `CAP_SETUID`) qui **vérifie `/etc/subuid`** avant d'écrire. Dans `podman unshare`, `ls -ln` du stockage montre des fichiers en 0 (`app`) : vus de l'intérieur.
4. Le serveur répond 200 depuis `adm01`. Le port 80 est refusé : un message du type « rootlessport cannot expose privileged port 80, you can add 'net.ipv4.ip_unprivileged_port_start=80' to /etc/sysctl.conf… » ou une erreur de pasta « Permission denied » à la liaison du port (le texte exact dépend de la version : compare). Trois façons de servir sur 80 :
   - **abaisser `net.ipv4.ip_unprivileged_port_start`** à 80 : simple, mais **tous** les comptes de la machine peuvent alors écouter sur 80-1023 ;
   - **redirection nftables** de 80 vers 8080 sur l'hôte (règle posée une fois, en root, par Ansible) : ne change rien pour les autres comptes, mais une règle de plus à connaître ;
   - **un répartiteur devant** (`lb01`/`lb02`, HAProxy) qui écoute 80/443 et relaie vers 8080 : c'est l'architecture de MédiSphère (M07), et aucune application n'a besoin d'un port bas. Variante : un socket systemd (*socket activation*) ouvert par root et passé au conteneur.
   Recommandation : garder 8080 sur l'hôte, publier par les répartiteurs ; écrire la règle dans les normes (E33).
5. ```
   app@ctr02:~$ podman top m12-e06-web user huser pid hpid args
   USER        HUSER       PID         HPID        COMMAND
   root        1001        1           3245        nginx: master process nginx -g daemon off;
   nginx       524388      24          3270        nginx: worker process
   admin@ctr02:~$ ps -o user,uid,pid,ppid,args -C nginx
   USER       UID     PID    PPID COMMAND
   app       1001    3245    3240 nginx: master process nginx -g daemon off;
   524388  524388    3270    3245 nginx: worker process
   ```
   UID 101 (utilisateur `nginx` de l'image) → 524288 + (101 − 1) = **524388**, un UID qui n'appartient à aucun compte de l'hôte (`ps` affiche le nombre). Le parent du maître est **`conmon`** (lui-même sous le gestionnaire systemd de `app`), et le réseau est porté par un processus **`pasta`** de `app`, qui relaie le port 8080 de l'hôte vers l'espace réseau du conteneur.
6. Vu de l'hôte, `par-root` appartient à `app` (1001) et `dossier-1000` à **525287** (524288 + 999) ; vus par `podman unshare`, à 0 et à 1000. `app` possède `partage`, mais pas `dossier-1000` (en 755, propriétaire 525287) : il ne peut pas en supprimer le contenu, donc pas le dossier (`Permission denied`). Sans sudo : `podman unshare rm -rf ~/m12/e06/partage/dossier-1000` (dans l'espace de noms, `app` est root sur ses UID subordonnés), ou `podman unshare chown -R 0:0 …`. Avec `--userns=keep-id`, l'UID de `app` est conservé **dans** le conteneur (le processus y tourne en 1001 et non en 0) : les fichiers créés sur un montage lié appartiennent à `app` sur l'hôte. C'est fait pour le développement (monter son code et ses fichiers), au prix d'un conteneur qui ne tourne plus « en root » à l'intérieur (certaines images s'en plaignent).
7. Sur `ctr01`, le maître nginx tourne sous l'**UID 0 de l'hôte** : un attaquant qui s'évade (faille du noyau, montage mal choisi) est root sur `ctr01`. Sur `ctr02`, il serait `app` (aucun droit sudo) ou un UID sans compte : dégâts limités au compte `app` et à ses conteneurs.
8. `sudo -n -u app XDG_RUNTIME_DIR=/run/user/1001 podman ps` montre `m12-e06-web` après la déconnexion : le conteneur est sous `conmon`, rattaché au gestionnaire systemd de `app` que le linger garde en vie.

Le check vérifie, en tant que `app`, l'état et l'image de `m12-e06-web`, sa publication sur 8080 et sa réponse à `adm01` ; vus de l'hôte, l'UID du maître (celui de `app`), ceux des travailleurs (dans la plage subordonnée), l'absence de nginx en root, le processus pasta de `app`, et le stockage personnel de `app`.

**Explications**

- **Le sans-privilège repose sur l'espace de noms `user`.** Dedans, `app` est root (capacités comprises) **sur ce qui appartient à l'espace** : ses UID, son réseau, ses montages. Dehors, il n'est que `app`. Les capacités d'un conteneur sans privilège ne valent rien sur l'hôte.
- **Le réseau sans privilège.** Un compte ordinaire ne peut pas créer d'interface `veth` ni de règle NAT sur l'hôte : pasta (`passt`) fait le relais en espace utilisateur, entre les sockets de l'hôte et l'espace réseau du conteneur. Il conserve l'adresse source des clients (contrairement à slirp4netns par défaut), ce qui compte pour les journaux d'accès.
- **Ce que ça coûte.** Pas de port bas, des UID « étranges » sur les fichiers des montages, des performances réseau un peu moindres qu'un pont noyau, et quelques fonctions absentes (certaines options de réseau, limites de cgroups si la délégation systemd manque).

**Alternatives**

- **Docker sans privilège** (`dockerd-rootless-setuptool.sh`, paquet `docker-ce-rootless-extras`) : même principe pour Docker, un démon par utilisateur ; comparé en E26.
- **`userns-remap` de Docker** : un démon root, mais les conteneurs dans un espace `user` décalé (E26).
- **Podman en root** (`sudo podman`) : sans démon, mais conteneurs en root comme Docker ; utile pour cephadm (M08), pas pour nos applications.

**Pièges classiques**

- `sudo su - app` ou `sudo -iu app` « pour aller plus vite » : pas de session, Podman se rabat sur cgroupfs, les limites et Quadlet ne fonctionnent pas comme prévu.
- Abaisser `ip_unprivileged_port_start` à 0 « parce que ça marche » : n'importe quel compte peut écouter sur 22 si `sshd` redémarre et tarde à reprendre son port.
- Faire `chown` sur l'hôte des fichiers d'un volume sans privilège (`sudo chown -R app …`) : à l'intérieur, ils deviennent root, et l'application qui tourne en 101 ne peut plus y écrire.
- Oublier le linger : les conteneurs meurent à la déconnexion (si `KillUserProcesses=yes`) ou ne repartent pas au redémarrage.
- Croire que `podman ps` en `admin` montre les conteneurs de `app` : chaque compte a les siens.

**En production chez MédiSphère**

Chaque application a son **propre** compte de service sur les hôtes Podman (et sa propre plage subordonnée), ses conteneurs gérés par Quadlet (E14), publiés derrière les répartiteurs. Sophie obtient sa preuve par un contrôle automatique (E28 : « aucun processus de conteneur en UID 0 sur les hôtes Podman ») plutôt que par une démonstration ponctuelle.

---

### M12-E07 — Volumes, montages et réseaux

**Solution**

1. Le volume était vide : au **premier montage** d'un volume nommé vide, Docker y recopie le contenu de l'image à cet emplacement (`50x.html`, `index.html`). Un montage lié ne le fait jamais : il **masque** ce qu'il y a dessous. Écrire la page par un conteneur jetable :
   ```
   admin@ctr01:~$ docker run --rm -v m12-e07-pages:/pages docker.io/library/debian:trixie-slim \
       sh -c 'echo "<h1>MédiSphère — M12-E07 (volume)</h1>" > /pages/index.html'
   ```
2. Configuration : [`fichiers/M12-E07/nginx/default.conf`](fichiers/M12-E07/nginx/default.conf) (un `server` qui sert `/usr/share/nginx/html` et `location = /sante { return 200 "ok\n"; }`).
3. et 4. Le conteneur :
   ```
   admin@ctr01:~$ docker network create m12-e07-front
   admin@ctr01:~$ docker run -d --name m12-e07-web --network m12-e07-front -p 8081:80 \
       -v m12-e07-pages:/usr/share/nginx/html \
       -v /home/admin/m12/e07/nginx:/etc/nginx/conf.d:ro \
       --tmpfs /var/cache/nginx:rw,size=16m \
       docker.io/library/nginx:1.30-trixie
   admin@adm01:~$ curl -s http://ctr01.par1.medisphere.internal:8081/ ; curl -s http://ctr01.par1.medisphere.internal:8081/sante
   ```
   Après `docker rm -f` et une nouvelle création identique, la page est toujours là : elle est dans le volume, pas dans le conteneur.
5. Avec un fichier monté, `vim` (ou `sed -i`) écrit un **nouveau fichier** puis le renomme : nouvel inode (`ls -i` change). Le conteneur garde l'**ancien inode** (le montage lié porte sur l'inode) et ne voit pas le changement, jusqu'à sa recréation. Monter le **dossier** évite le piège : le conteneur voit le dossier, donc le nouveau fichier (il reste à demander à nginx de relire : `docker exec m12-e07-web nginx -s reload`).
6. Sur le réseau `bridge` par défaut, `getent hosts <autre>` ne rend rien : pas de DNS intégré. Sur `m12-e07-front`, `getent hosts m12-e07-web` donne son adresse ; `/etc/resolv.conf` du conteneur dit `nameserver 127.0.0.11` (et `ExtServers: [10.10.20.10 …]` en commentaire) : c'est `dockerd` qui répond (par une règle de traduction dans l'espace réseau du conteneur) et relaie le reste vers les résolveurs de l'hôte. Le sous-réseau : `172.20.0.0/24` (ou le suivant), pris dans `default-address-pools` (E02) ; sans cette clé, Docker aurait pu finir dans `192.168.0.0/16`.
7. `m12-e07-isole` ne sort pas (`bloque`), et ne résout même pas les noms extérieurs (le DNS intégré ne relaie pas les requêtes extérieures sur un réseau interne : `Temporary failure in name resolution`) ; `m12-e07-client` sort (`sortie`). Un réseau interne n'a pas de passerelle vers l'extérieur ni de traduction d'adresse sortante, et on ne peut pas y publier de port : c'est le réseau d'une **base de données**, que seuls les conteneurs applicatifs (attachés aux deux réseaux) atteignent (E08).
8. Avec `--network host`, nginx écoute directement sur le port 80 de `ctr01` (`ss -ltnp` le montre, processus `nginx`) : plus d'espace réseau propre, plus de publication de ports (l'option `-p` est ignorée), plus d'isolation réseau. Utile pour des outils réseau ou des performances extrêmes, à justifier.
9. Extraits (Debian 13 : `iptables` est la variante **nft** ; Docker 29 utilise toujours ce moteur par défaut) :
   ```
   admin@ctr01:~$ sudo nft list ruleset | grep -nE 'DOCKER|dnat|8082|8083' | head
   …
   table ip nat {
           chain DOCKER {
                   … tcp dport 8082 … dnat to 172.17.0.3:80
                   ip daddr 127.0.0.1 … tcp dport 8083 … dnat to 172.17.0.4:80
   table ip filter {
           chain DOCKER-USER {
           chain DOCKER { … ip daddr 172.17.0.3 … tcp dport 80 accept
   ```
   (les noms de chaînes intermédiaires dépendent de la version : lis les tiens). Depuis `adm01`, seul 8082 répond. La traduction se fait dans `PREROUTING` : le paquet ne va plus à l'hôte, il est **relayé** vers le conteneur et ne traverse que la chaîne `FORWARD` ; une règle dans `INPUT` ne le voit pas. L'administrateur met ses règles dans **`DOCKER-USER`**, que Docker crée et ne touche jamais, et qui est évaluée avant les siennes dans `FORWARD`.
10. Tableau attendu : fichiers de PostgreSQL → **volume nommé** ; cache Valkey → rien (ou tmpfs) : un cache se reconstruit ; configuration → **montage lié en lecture seule** (ou image, ou variables) ; secrets → **fichier monté** depuis un dossier protégé (secrets Compose), jamais variable d'environnement ; fichiers temporaires → **tmpfs**.

Le check vérifie `m12-e07-web` (image, volume sur les pages, dossier de configuration en lecture seule, tmpfs, réseau, publication sur 8081), la page et `/sante` vus de `adm01`, le réseau `m12-e07-front` (pont défini, sous-réseau dans 172.20.0.0/14), la résolution de `m12-e07-web` depuis `m12-e07-client`, le réseau interne et l'attachement de `m12-e07-isole`.

**Explications**

- **Qui possède la donnée.** Un volume nommé appartient au moteur (on le liste, on le sauvegarde par le moteur, E29) ; un montage lié appartient à l'hôte (droits, sauvegarde et SELinux de l'hôte : `:z`/`:Z` sur Rocky, E25) ; un tmpfs n'appartient à personne et disparaît.
- **Le DNS intégré** suit les conteneurs : leur adresse change à chaque recréation, leur nom non. C'est ce qui permet à Compose d'écrire `db:5432`.
- **La publication de ports contourne le pare-feu de l'hôte**, par construction : c'est la première surprise des équipes sécurité. D'où les règles : publier sur l'adresse utile seulement, filtrer dans `DOCKER-USER` ou en amont, ne rien publier qui ne doive l'être (une base ne publie jamais).

**Alternatives**

- `--mount type=volume,src=…,dst=…` / `type=bind,…,readonly` / `type=tmpfs,…,tmpfs-size=…` : syntaxe longue, plus explicite (et la seule qui refuse un chemin d'hôte absent au lieu de le créer).
- Backend **nftables** de Docker 29 (`"firewall-backend": "nftables"`, expérimental) : des tables propres à Docker plutôt que les chaînes `iptables-nft` ; à évaluer, pas encore pour la production.
- Réseaux `macvlan`/`ipvlan` : conteneurs directement sur le VLAN de l'hôte, sans NAT ; rarement utile hors appliances réseau.

**Pièges classiques**

- Monter un **fichier** de configuration et s'étonner que la modification ne soit pas vue.
- `-v ~/m12/e07/nginx:/etc/nginx/conf.d` sans `:ro` : le conteneur peut réécrire la configuration de l'hôte.
- Un montage lié vers un chemin qui n'existe pas : avec `-v`, Docker **crée** un dossier vide appartenant à root (et nginx démarre sans configuration) ; `--mount` refuserait.
- `docker volume prune` (ou `-a`) « pour faire de la place » : supprime les volumes qui ne sont pas montés **à cet instant**, y compris la base d'une pile arrêtée.
- Croire qu'une règle `INPUT … drop` protège un port publié ; ou l'inverse, poser une règle « allow » dans `INPUT` et ne pas comprendre pourquoi rien ne change.
- Un `listen [::]:80` dans la configuration de nginx sur un réseau sans IPv6 : nginx refuse de démarrer (`Address family not supported by protocol`).

**En production chez MédiSphère**

Les données ne restent pas sur l'hôte d'un conteneur : PostgreSQL de production vivra dans Kubernetes avec CloudNativePG sur Ceph (M16), ou sur des VMs dédiées. Sur les hôtes de conteneurs, les volumes sont sauvegardés par le moteur (E29), les ports publiés listés dans la matrice des flux, et les règles d'administration dans `DOCKER-USER` posées par Ansible.

---

### M12-E08 — Docker Compose : MédiAgenda, PostgreSQL et Valkey

**Solution**

1. Sans Swarm, un secret `file:` est un **montage lié en lecture seule** du fichier de l'hôte sur `/run/secrets/<nom>` : il garde le propriétaire et les droits de l'hôte ; les options `uid`, `gid` et `mode` de la syntaxe longue ne s'appliquent pas à ce type de secret (essai fait : ignorées).
2. Fichiers : [`compose.yaml`](fichiers/M12-E08/mediagenda-api/compose.yaml), [`outils/secrets-compose.sh`](fichiers/M12-E08/mediagenda-api/outils/secrets-compose.sh), [`gitignore.extrait`](fichiers/M12-E08/mediagenda-api/gitignore.extrait). Les choix :
   - `db` : `postgres:18-trixie`, `POSTGRES_PASSWORD_FILE=/run/secrets/db_mdp`, volume `donnees-db` sur **`/var/lib/postgresql`** (disposition de l'image 18 : données dans `/var/lib/postgresql/18/docker`), sonde `pg_isready -U mediagenda -d mediagenda`, réseau `arriere` seulement ;
   - `valkey` : `--save "" --appendonly no` (cache, pas de persistance), sonde `valkey-cli ping`, réseau `arriere` ;
   - `migrations` : même image que l'API, `mediagenda-migrate`, `depends_on: db: condition: service_healthy`, `restart: "no"` ;
   - `api` : `depends_on: migrations: service_completed_successfully` **et** `valkey: service_healthy`, sonde Python sur `/sante` (pas de `curl` dans l'image), port 8000, réseaux `avant` et `arriere` ;
   - le mot de passe : l'application ne lit que `MEDIAGENDA_DB_URL` ; on la **compose au démarrage** dans le conteneur, sans qu'elle figure dans sa définition :
     ```yaml
     entrypoint: ["/bin/sh", "-c"]
     command:
       - 'MEDIAGENDA_DB_URL="postgresql://mediagenda:$$(cat /run/secrets/db_mdp)@db:5432/mediagenda" exec mediagenda'
     ```
     `$$` empêche Compose d'interpoler (`$` arrive au shell du conteneur) ; `exec` remplace le shell par `mediagenda`, qui devient le PID 1 et reçoit les signaux ;
   - `psql` dans le profil `outils` (même astuce avec `PGPASSWORD`, qui n'existe que dans le processus) ;
   - réseaux `avant` (normal) et `arriere` (`internal: true`) ; volume nommé ; `name: mediagenda` (noms prévisibles : `mediagenda-api-1`, `mediagenda_arriere`, `mediagenda_donnees-db`).
   Le secret : un fichier en **644 dans un dossier en 700** (script fourni) : sur l'hôte, seul `admin` traverse `secrets/` ; dans le conteneur, l'UID 10001 peut lire le fichier monté (un fichier en 600 appartenant à `admin` lui serait illisible : erreur `cat: /run/secrets/db_mdp: Permission denied`, puis `fe_sendauth: no password supplied`). Le mot de passe est en hexadécimal (`openssl rand -hex 24`) : utilisable tel quel dans une URL.
3. Démarrage :
   ```
   admin@ctr01:~/src/mediagenda-api$ docker compose up -d --wait
    Container mediagenda-valkey-1  Started
    Container mediagenda-db-1  Started
    Container mediagenda-db-1  Healthy
    Container mediagenda-migrations-1  Started
    Container mediagenda-valkey-1  Healthy
    Container mediagenda-migrations-1  Exited
    Container mediagenda-api-1  Started
    Container mediagenda-api-1  Healthy
   admin@ctr01:~/src/mediagenda-api$ docker compose ps -a --format '{{.Service}} {{.Status}}'
   api Up 5 seconds (healthy)
   db Up 12 seconds (healthy)
   migrations Exited (0) 6 seconds ago
   valkey Up 12 seconds (healthy)
   admin@ctr01:~/src/mediagenda-api$ docker compose logs migrations
   migrations-1  | {"…": "…", "message": "application", "migration": "V1__init.sql"}
   migrations-1  | {"…": "…", "message": "application", "migration": "V2__index.sql"}
   migrations-1  | {"…": "…", "message": "migrations terminées", "appliquees": ["V1__init.sql", "V2__index.sql"]}
   ```
   Ordre : `db` et `valkey`, puis `migrations` quand `db` est saine, puis `api` quand `migrations` est sortie en 0 et `valkey` saine. Erreurs courantes : `Permission denied` sur le secret (voir ci-dessus) ; `service "migrations" didn't complete successfully: exit 1` → lire ses journaux (mot de passe différent de celui avec lequel le volume a été initialisé : le volume garde le premier mot de passe) ; volume monté sur `/var/lib/postgresql/data` (habitude des versions ≤ 17) → l'image 18 refuse de démarrer et l'explique dans ses journaux.
4. `/pret` → `{"statut":"pret","postgresql":"ok","valkey":"ok"}` ; création → 201 avec `"debut":"2026-11-02T08:00:00Z"` (rangé en UTC) ; créneaux : la liste de 9 h-12 h et 14 h-18 h sans 9 h 00. `SELECT * FROM mediagenda_historique_schema;` montre V1 et V2 avec leur empreinte.
5. Preuves : `Config.Env` de l'API ne contient que `MEDIAGENDA_VALKEY_URL`, `MEDIAGENDA_LOG_LEVEL`, `PATH`, les variables de Python et `MEDIAGENDA_VERSION` ; `docker port mediagenda-db-1` ne rend rien ; `mediagenda_arriere` est `true` (interne) ; PID 1 : `/app/.venv/bin/python /app/.venv/bin/mediagenda`.
6. `restart api` : immédiat. `stop` puis `up -d --wait` : `migrations` repart, ne trouve rien à appliquer (`"appliquees": []`) et sort en 0 (migrations idempotentes, verrou consultatif). `down` supprime conteneurs et réseaux, **pas** le volume : les rendez-vous sont toujours là après `up`. `down -v` supprimerait la base.
7. MR : `compose.yaml`, `outils/secrets-compose.sh`, `.gitignore` (`secrets/`, `.env`). Dans GitLab, `secrets/` n'apparaît pas dans l'arbre de `main` (ni dans l'historique : `git log --all -- secrets/` est vide).

Le check vérifie les quatre services (états, santé, code de sortie de `migrations`), `/pret` depuis `adm01`, PostgreSQL 18, l'absence de port publié et les réseaux internes de `db` et `valkey`, le volume sur `/var/lib/postgresql`, l'absence de mot de passe dans l'environnement de **tous** les conteneurs du projet, `POSTGRES_PASSWORD_FILE`, le PID 1 de l'API, les droits du secret sur l'hôte, et le dépôt (`compose.yaml` sans `version:`, conditions de dépendance, pas de `secrets/` versionné, `.gitignore`).

**Explications**

- **`depends_on` avec conditions.** Sans condition, Compose attend seulement que le conteneur **démarre** : l'API se connecterait à une base qui n'accepte pas encore de connexions. `service_healthy` attend la sonde ; `service_completed_successfully` attend qu'un service ponctuel sorte en 0. `up --wait` attend que tout soit sain avant de rendre la main (pratique en CI).
- **Les migrations, un service à part.** Les migrations ne sont pas « au démarrage de l'API » : deux réplicas se marcheraient dessus, et une migration longue retarderait la disponibilité. Un service ponctuel, puis l'application : c'est le schéma qu'on retrouvera en Kubernetes (Job, puis Deployment, M17).
- **Pourquoi pas `environment: MEDIAGENDA_DB_URL: …${DB_MDP}`** avec un `.env` : le mot de passe finirait dans `Config.Env` du conteneur, lisible par `docker inspect` et par quiconque a accès au socket (E01, question 15). Le secret monté n'apparaît que dans `/run/secrets/` du conteneur et, le temps d'un `exec`, dans l'environnement du **processus**.
- **Le réseau interne** fait de la base une ressource que seuls les conteneurs attachés au même réseau atteignent ; l'API, attachée aux deux, est le seul pont.

**Alternatives**

- **Modifier l'application** pour qu'elle lise `MEDIAGENDA_DB_URL_FILE` (comme les images officielles avec `*_FILE`) : la solution propre, à proposer à Julien (ticket DEV) ; on n'y touche pas dans ce module.
- **Un script d'entrée** dans l'image (`entrypoint.sh` qui lit `/run/secrets/*` puis `exec "$@"`) : même mécanisme, versionné dans l'image plutôt que dans `compose.yaml` ; c'est souvent mieux, à condition que le script finisse par `exec` (E17).
- **Swarm** (`docker stack deploy`) : vrais secrets (copiés, chiffrés au repos, `uid`/`mode` respectés) ; on n'utilise pas Swarm chez MédiSphère (Kubernetes au M14).
- **Podman** : `podman kube play` ou Quadlet (`.pod`), avec des secrets Podman (`podman secret create`), en E14.

**Pièges classiques**

- `version: "3.8"` en tête : avertissement « obsolete » de Compose v5, et une fausse impression de compatibilité.
- Monter le volume de PostgreSQL 18 sur `/var/lib/postgresql/data` : refus de démarrer (ou, pire, données hors du volume avec un `PGDATA` forcé à la main).
- Changer le contenu de `secrets/db_mdp` après la première initialisation : PostgreSQL garde l'ancien mot de passe (il n'est lu qu'à l'initialisation du volume) ; `migrations` et l'API échouent. Soit `ALTER ROLE`, soit (en recette seulement) `down -v`.
- Oublier `exec` dans la commande : `/bin/sh` reste PID 1, arrêt en 10 s, code 137.
- Une seule `$` dans la commande : Compose interpole `$(cat …)` comme une variable vide.
- Sonde de santé de l'API sur `/pret` : une panne de la base ferait déclarer l'API malsaine et, avec un orchestrateur, la ferait redémarrer en boucle (README de MédiAgenda).
- `docker compose down -v` par habitude : la base de recette disparaît.

**En production chez MédiSphère**

Compose reste l'outil des postes de développement et de la recette sur `ctr02` (pile de recette du mini-projet, en Compose ou Quadlet) ; la production ira sur Kubernetes (M14-M17), où les mêmes idées deviennent des sondes, un Job de migrations, des Secrets (puis Vault, M25) et des NetworkPolicies. Le mot de passe de recette serait tiré de Vault par la CI ; et Julien recevra le ticket « lire `MEDIAGENDA_DB_URL_FILE` », pour se passer du `sh -c`.

---

### M12-E09 — Questions : architecture des conteneurs

**Barème** : 2 points par question, total sur 24. Les schémas comptent : une chaîne sans le shim ou avec runc « toujours là » perd un point.

**1. `docker run -d` sur `ctr01`.**
```
docker (CLI) ──HTTP sur /var/run/docker.sock──▶ dockerd ──gRPC /run/containerd/containerd.sock (espace « moby »)──▶ containerd
                                                                                                          │ lance
                                                                                                          ▼
                                                                                         containerd-shim-runc-v2 (un par conteneur)
                                                                                                          │ appelle
                                                                                                          ▼
                                                                                            runc create / start (bundle)
                                                                                                          │ clone() + espaces de noms,
                                                                                                          │ cgroups, pivot_root, capacités,
                                                                                                          │ seccomp, execve
                                                                                                          ▼
                                                                                                nginx (PID 1 du conteneur)
```
Le **client** envoie une requête d'API et s'arrête (`-d`). **dockerd** résout l'image (si besoin la fait tirer par containerd, qui range contenu et instantanés), prépare réseau (pont, adresse, règles NAT), volumes et configuration, puis demande à **containerd** de créer le conteneur et sa tâche. containerd prépare la racine (montage overlay des instantanés + couche inscriptible), écrit le **bundle** (`config.json`), et lance un **shim**. Le shim appelle **runc**, qui crée le processus isolé puis **se termine**. Pendant que nginx tourne : dockerd, containerd, le shim (parent de nginx, gardien des flux et du code de sortie) et nginx ; ni le client ni runc.

**2. `podman run -d` sous `app`.** Le client `podman` fait tout lui-même (bibliothèque libpod) : il tire l'image dans `~/.local/share/containers/storage`, prépare l'espace de noms `user` (avec `newuidmap`), l'espace réseau (pasta), la racine (overlay du stockage), écrit le bundle, puis lance **conmon**, qui appelle **crun** (Rocky) ou **runc**/crun (Debian). conmon joue le rôle du shim : il reste parent du conteneur. `podman` se termine. Il n'y a **pas de démon** (sauf si l'on active l'API compatible Docker, `podman.socket`, à la demande).

**3. Réponse B.** Le processus de nginx n'est pas un enfant de containerd mais du shim, qui ne dépend pas de containerd pour vivre ; au retour, containerd retrouve ses shims (sockets dans `/run/containerd/`) et l'état des tâches. A est faux (ce serait le cas sans shim). C est faux : dockerd se reconnecte à containerd. D est faux : le processus ne passe jamais par containerd pour s'exécuter. (Pour `dockerd`, c'est différent : sans `live-restore`, redémarrer **dockerd** arrête les conteneurs, E26.)

**4. Bundle.** Un dossier avec `config.json` (spécification *runtime* OCI : processus, arguments, environnement, utilisateur, dossier de travail, montages, espaces de noms, cgroup, capacités, profil seccomp, limites, étiquettes SELinux ou AppArmor, crochets) et `rootfs` (la racine). containerd (ou Podman) le fabrique à partir de la **configuration de l'image** et des options du moteur. La racine : les couches de l'image, décompressées une fois en **instantanés** par le *snapshotter* `overlayfs` de containerd (ou le pilote `overlay` de containers/storage pour Podman, natif en sans-privilège depuis le noyau 5.13), superposées en `lowerdir`, avec une couche inscriptible propre au conteneur en `upperdir` ; runc reçoit ce montage overlay comme `rootfs`.

**5. Spécifications OCI.** *Image* : formats de l'index, du manifeste, de la configuration, des couches et de l'*OCI layout* (`index.json`, `blobs/sha256/`) — produits par BuildKit, Buildah, Skopeo (E04). *Runtime* : `config.json` et le cycle de vie d'un conteneur (`create`, `start`, `kill`, `delete`, `state`) — runc, crun. *Distribution* : l'API HTTP des registres (`/v2/<nom>/manifests/<réf>`, `/v2/<nom>/blobs/<empreinte>`, envoi par sessions, API *referrers*) — `registry:3` (E15), Harbor (M13), et les clients (Skopeo, Docker, Podman).

**6. Séparer exécution et gestion.** Le runtime est un petit programme **qui se termine** : sa surface d'attaque et sa fenêtre d'exécution privilégiée sont minimes. On peut le **remplacer** sans toucher au gestionnaire (runc, crun, gVisor `runsc`, Kata pour des micro-VMs). Et le gestionnaire peut être mis à jour ou redémarré **sans tuer les conteneurs** (grâce au shim). Enfin, plusieurs gestionnaires (Docker, Podman, Kubernetes) partagent les mêmes runtimes et donc le même comportement.

**7. Réponse B.** Le CRI est l'interface **gRPC** (services `RuntimeService` et `ImageService`) par laquelle le kubelet demande à un moteur conforme (containerd et son greffon CRI, CRI-O) de créer des *sandboxes* de pods, des conteneurs, de tirer des images. A est la spécification d'image OCI. C est faux : runc est sous le moteur, le kubelet ne le voit pas. D est faux : c'est justement pour ne plus dépendre de l'API Docker que le CRI existe.

**8. `dockershim`.** Oui, les images fonctionnent : Docker produit des images au format OCI (ou Docker v2, que containerd lit) et les pousse par l'API de distribution ; containerd les tire comme n'importe quelle autre. Ce qui a disparu, c'est l'**adaptateur** intégré au kubelet qui traduisait le CRI vers l'API de Docker : les nœuds qui utilisaient Docker Engine comme moteur ont dû passer à containerd ou CRI-O (ou installer `cri-dockerd`), et les habitudes « Docker sur les nœuds » (monter `docker.sock` dans un pod, `docker ps` sur un nœud) ont cessé de marcher. Sur les nœuds de `k8s-par1` (M14), on utilisera `crictl`, pas `docker`.

**9. Docker 29 et le stockage containerd.** Constaté : `docker info` affiche `overlayfs` + `io.containerd.snapshotter.v1` ; les données d'images sont sous `/var/lib/containerd` et visibles par `ctr -n moby` ; l'ID d'une image est l'empreinte de son **index** ; `docker image ls --tree` montre les plateformes ; deux tailles (contenu, disque). Gains : images **multi-plateformes** et **attestations** (provenance, SBOM) conservées localement et poussées telles quelles ; un seul format de stockage partagé avec containerd (et donc, sur un même hôte, avec Kubernetes) ; fonctions avancées (instantanés paresseux, autres *snapshotters*). Coûts : plus d'espace (compressé + décompressé), outils et tutoriels qui lisent `/var/lib/docker/overlay2` cassés, et une installation **mise à niveau** garde l'ancien stockage (deux comportements dans un parc).

**10. conmon.** Il garde les flux du conteneur (terminal, socket d'attachement pour `podman attach`), écrit les **journaux** (journald ou fichier `k8s-file`), attend la fin du processus et en **enregistre le code de sortie**, puis déclenche le nettoyage (`podman container cleanup` : démontage, réseau) ; il est le parent (*subreaper*) du processus du conteneur. Un conteneur survit à la commande `podman` parce que conmon est **détaché** (double *fork*) et rattaché à systemd (ou au gestionnaire systemd de l'utilisateur) ; l'état du conteneur est dans la base de Podman (SQLite), sur disque : toute commande `podman` suivante le relit. Pas besoin d'un démon pour « tenir » le conteneur.

**11. L'interopérabilité.** Parce que tous parlent **les mêmes formats** (spécification image) et **la même API de registre** (distribution) : une image est un ensemble de documents et de blobs adressés par empreinte, peu importe l'outil qui les a écrits. Ce qui peut coincer : des types de manifestes anciens (Docker *schema 1*, retirés de containerd 2), une **plateforme** absente (une image amd64 seule sur un nœud arm64 : `exec format error`), des manifestes d'**attestation** `unknown/unknown` mal compris par de vieux outils, des couches compressées en **zstd** refusées par un client ancien, des artefacts OCI qui ne sont pas des images (signatures, SBOM, charts), un registre qui n'accepte pas les index OCI ou l'API *referrers*.

**12. Les moteurs chez MédiSphère.** **Docker** : postes de développement, Compose de recette, le runner `runner02` (exécuteur `docker`, E20), Harbor (installé par Compose, M13), et `ctr01`. **Podman** : serveurs qui font tourner quelques services sous systemd, sans démon et sans privilège (Quadlet, `ctr02`), et cephadm (M08). **containerd + `nerdctl`** : déboguer un nœud Kubernetes avec une interface proche de Docker, ou un hôte minimal. **CRI-O** : un moteur fait **uniquement** pour Kubernetes (OpenShift), sans usage hors cluster. Sur les nœuds de `k8s-par1` (M14) : **containerd.io 2.3 LTS** du dépôt Docker (PLAN §4.10), le même containerd que sous Docker 29.
