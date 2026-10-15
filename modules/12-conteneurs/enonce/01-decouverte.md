# Module 12 — Palier 1 : Découverte

Avant de conteneuriser quoi que ce soit, il faut des hôtes qui conviennent, créés et configurés par le code : un hôte Docker, deux hôtes Podman sans privilège (dont un en SELinux), et la VM historique de Legacy-RDV reproduite à l'identique. Ce palier les construit, puis te fait pratiquer les gestes de base que tout le reste du bloc suppose acquis : le cycle de vie d'un conteneur, l'anatomie d'une image et de ses empreintes, un premier Dockerfile pour MédiAgenda, Podman sans privilège, les volumes et les réseaux, et une pile Compose complète. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : module 07 terminé (`lab/bin/check 07 46` vert) ; modules 03 à 06 (images dorées Debian et Rocky `current`, rôles et Molecule, OpenTofu et NetBox, PKI, Kea et son DDNS). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les règles du module.

---

### M12-E01 — Test de positionnement : conteneurs  `Q` `★★`

> **Ticket PLAT-1301** — *De : Karim Benali*
> Le rituel : une heure, par écrit, sans moteur de recherche ni IA, sans rien exécuter. Tout le monde « fait du Docker » ; peu de gens savent ce qu'un conteneur est vraiment pour le noyau, ni pourquoi un `docker run` mal écrit donne root sur la machine. Réponds même là où tu hésites : le raisonnement compte.

**Objectifs pédagogiques**
- Évaluer tes acquis sur l'isolation des processus sous Linux, les images et la sécurité des conteneurs avant de les pratiquer.
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 18 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Isolation et noyau*

1. En une phrase chacun : qu'est-ce qui distingue un conteneur d'une machine virtuelle du point de vue du **noyau** ? Donne deux conséquences pratiques de cette différence (une pour la sécurité, une pour l'exploitation).

2. Cite six types d'**espaces de noms** Linux et, pour chacun, ce qu'un processus placé dans un nouvel espace de ce type cesse de voir ou de partager avec l'hôte.

3. *(QCM)* Dans un conteneur sans espace de noms `user`, un processus tourne en UID 0. Vu de l'hôte, ce processus :
   - A. tourne sous un UID tiré au hasard au-dessus de 100 000
   - B. tourne sous l'UID 0 de l'hôte, avec des capacités réduites et des filtres
   - C. tourne sous l'UID de l'utilisateur qui a lancé `docker run`
   - D. n'a pas d'UID sur l'hôte : il vit dans la VM légère du moteur

4. Pourquoi le **PID 1** d'un conteneur a-t-il un comportement particulier face à `SIGTERM` ? Que se passe-t-il, concrètement, quand on fait `docker stop` sur un conteneur dont le PID 1 est un script shell qui lance l'application en arrière-plan ?

5. Que **limitent** et que **comptent** les cgroups ? Cite trois contrôleurs de cgroups v2 et le fichier de l'interface qui fixe la limite pour chacun. Que se passe-t-il quand un conteneur dépasse sa limite de mémoire ? et sa limite de CPU ?

*Images*

6. Qu'est-ce qu'une **couche** d'image ? Pourquoi un `RUN apt-get update && apt-get install …` placé avant un `COPY . .` accélère-t-il les constructions suivantes ?

7. Distingue **étiquette** (*tag*) et **empreinte** (*digest*). Une équipe déploie `python:3.13-slim` en recette lundi et en production vendredi : est-ce la même image ? Comment en être sûr ?

8. *(QCM)* Une image « multi-architectures » publiée sous une seule étiquette est, dans le registre :
   - A. une seule image qui contient des binaires pour toutes les architectures
   - B. un index (*manifest list*) qui pointe vers un manifeste par plateforme, chacun avec ses propres couches
   - C. plusieurs étiquettes cachées (`-amd64`, `-arm64`) que le client choisit
   - D. une image `amd64` que les autres architectures émulent

9. On supprime un fichier de 500 Mo dans une couche postérieure à celle qui l'a ajouté. L'image est-elle plus petite ? Pourquoi ? Que faut-il faire à la place ?

10. Pourquoi un fichier `.dockerignore` est-il une mesure de **sécurité** autant que de performance ?

*Sécurité*

11. Qu'est-ce qu'une **capacité** Linux ? Pourquoi `--privileged` est-il presque toujours une mauvaise idée, et qu'est-ce qu'il fait exactement de plus que `--cap-add SYS_ADMIN` ?

12. Un collègue ajoute son compte au groupe `docker` « pour ne plus taper sudo ». Explique, avec une commande d'exemple (que tu n'exécutes pas), pourquoi il vient de se donner root sur la machine.

13. Que fait le profil **seccomp** par défaut d'un moteur de conteneurs ? Cite un appel système qu'il bloque et pourquoi.

14. *(QCM)* Un conteneur « sans privilège » (*rootless*) au sens de Podman, c'est :
    - A. un conteneur dont le processus principal n'est pas root à l'intérieur
    - B. un conteneur lancé par un utilisateur ordinaire, sans démon root, dont le « root » intérieur est un UID ordinaire de l'hôte grâce à l'espace de noms `user`
    - C. un conteneur sans aucune capacité
    - D. un conteneur en lecture seule

15. Pourquoi ne doit-on jamais passer un mot de passe par `ENV` ou `ARG` dans un Dockerfile, ni par `-e` sur la ligne de commande ? Cite deux endroits où il resterait lisible.

*Réseau et stockage*

16. Que se passe-t-il, côté pare-feu de l'hôte, quand on publie un port avec `-p 8080:80` ? Pourquoi une règle « tout bloquer en entrée sauf SSH » posée à la main dans la chaîne `INPUT` ne protège-t-elle pas ce port ?

17. Distingue **volume nommé**, **montage lié** (*bind mount*) et **tmpfs** : où vivent les données, qui en gère le cycle de vie, un usage typique pour chacun.

18. Deux conteneurs doivent se parler par leur nom (`db`, `api`). Sur quel type de réseau cela fonctionne-t-il « tout seul », et quel composant répond aux requêtes DNS ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 18 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 36.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour chaque question d'isolation, pose-toi la question : « qui fait le travail, le noyau ou le moteur ? ». Le moteur ne fait que demander au noyau des espaces de noms, des cgroups et des filtres ; tout ce que le noyau partage reste partagé.
</details>

<details><summary>Indice 2</summary>

Pour les images, raisonne en **contenu adressé** : un objet désigné par l'empreinte de son contenu ne peut pas changer ; un nom, si. Et une couche ne s'efface jamais : elle se recouvre.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M12-E46), sans relire le corrigé, et compare.

---

### M12-E02 — Préparer les hôtes de conteneurs  `LAB` `★★`

> **Ticket PLAT-1302** — *De : Karim Benali* — *Copie : Claire Morel*
> Quatre VMs pour le module : un hôte Docker, deux hôtes Podman sans privilège (un Debian, un Rocky avec SELinux, parce que la moitié de nos futurs serveurs seront en RHEL), et la VM de Legacy-RDV refaite comme InfoGér l'avait montée, pour qu'on ait enfin une copie qu'on peut casser. Ce sont des VMs jetables : DHCP sur `vsandbox`, noms par le DDNS de Kea, et `vm-noeud` ne sait pas faire de DHCP, à toi de l'apprendre sans casser Ceph ni OpenStack. Docker vient du dépôt de Docker, pas de Debian, avec la clé vérifiée et les versions épinglées. Podman tourne sous un compte applicatif **sans sudo**. Et Legacy-RDV, tu le reproduis tel quel : on ne corrige rien avant l'exercice qui le demande.

**Objectifs pédagogiques**
- Étendre un module OpenTofu partagé (carte en DHCP) de façon **rétrocompatible**, et le prouver.
- Installer Docker Engine 29 depuis son dépôt officiel avec une clé vérifiée par son empreinte et des versions épinglées, et gérer `daemon.json` par le code.
- Préparer un hôte Podman sans privilège sur deux familles d'OS (compte dédié, plages subordonnées, linger, registres).
- Automatiser une installation « historique » telle qu'elle est, pour pouvoir la reconstruire et l'étudier.

**Prérequis** : M08-E02 et M10-E02 (module `vm-noeud`) ; M06-E12, M06-E16 à E18 (inventaire NetBox, Kea et son DDNS) ; M06-E03 (rôle `ca_lab`) ; M04-E24 (Molecule) ; M04 (Vault, identité `lab`).
**Durée indicative** : 5 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VMs | `ctr01` (2121, Debian 13), `ctr02` (2122, Debian 13), `ctr03` (2123, Rocky 10), `legacy01` (2124, Debian 13) ; pool `lab` ; 2 vCPU, 2048 Mo, disque système 32 Gio sur `local-nvme` ; démarrage manuel ; images dorées `current` de chaque famille |
| Réseau | une carte sur `vsandbox`, adresse par **DHCP** (Kea, sous-réseau `id: 99`), nom `<hôte>.par1.medisphere.internal` publié par le **DDNS** de Kea ; MAC imposée `bc:24:11:99:12:0N` (N = 1 à 4) |
| Étiquettes | Proxmox et NetBox : `env-m12` sur les quatre, plus `role-docker` (`ctr01`), `role-podman` (`ctr02`, `ctr03`), `role-legacy` (`legacy01`) |
| Code OpenTofu | module `vm-noeud` de `plateforme/tofu-modules` (nouvelle version **mineure**, MR) ; état **`m12-conteneurs`** : dossier `envs/m12/` de `plateforme/infra`, clé `envs/m12/terraform.tfstate` |
| Inventaire Ansible | source `inventories/lab/netbox-m12.yml` (étiquette `env-m12`) ; groupes `env_m12`, `role_docker`, `role_podman`, `role_legacy` ; NetBox ne connaîtra pas l'adresse de ces VMs |
| Docker (`ctr01`) | rôle `docker_engine` : dépôt `https://download.docker.com/linux/debian`, suite `trixie`, composant `stable`, format deb822 ; clé `https://download.docker.com/linux/debian/gpg`, empreinte `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88` ; paquets `docker-ce`, `docker-ce-cli`, `docker-ce-rootless-extras` en `5:29.8.2-1~debian.13~trixie`, `containerd.io` en `2.3.6-1~debian.13~trixie`, `docker-buildx-plugin` en `0.37.1-1~debian.13~trixie`, `docker-compose-plugin` en `5.6.0-1~debian.13~trixie` ; `daemon.json` : journaux `json-file` avec rotation (10 Mo, 3 fichiers), réseaux des conteneurs dans `172.20.0.0/14` découpé en /24 ; `admin` dans le groupe `docker` |
| Podman (`ctr02`, `ctr03`) | rôle `podman_hote` : paquets de la distribution (Podman, Buildah, Skopeo, crun, passt…) ; compte **`app`**, UID 1001, sans sudo ; plage subordonnée `524288:65536` (UID et GID) ; linger ; `registries.conf.d` (un seul registre de recherche, `docker.io`, `short-name-mode = "enforcing"`), `containers.conf.d` (pasta, journald) ; SELinux reste *enforcing* sur `ctr03` |
| Legacy-RDV (`legacy01`) | rôle `legacy_rdv` : la procédure d'installation du [README de Legacy-RDV](../../../apps/legacy-rdv/README.md), **telle quelle** (Apache, `libapache2-mod-php8.4`, `php8.4-mysql`, MariaDB, code dans `/var/www/legacy-rdv`, hôte virtuel et cron du dossier `vm/`) ; code copié depuis `~/DevOpsPrivateCloud/apps/legacy-rdv/` sur `adm01` (le projet GitLab n'existe pas encore) ; mot de passe de la base en Vault `lab` |
| Instances Molecule | 2046 (`docker_engine`), 2047 (`podman_hote`), famille `debian13` |

**Travail demandé**

*A. Avant d'écrire*

1. Lis la page « Install Docker Engine on Debian » de la documentation Docker : note pourquoi elle demande de retirer `docker.io`, `containerd` et `runc` de Debian, et comment elle vérifie la clé. Lis la page « Rootless mode » du tutoriel Podman (lien en fin d'introduction) : note ce que le sans-privilège exige de l'hôte.
2. Ajoute au modèle NetBox (script de données de M06-E05) les étiquettes `env-m12`, `role-docker`, `role-podman`, `role-legacy`.
3. Vérifie que le sous-réseau `id: 99` de Kea publie bien les noms par DDNS (M06-E18) : regarde la configuration rendue sur `dns01` et un bail existant. Note le suffixe ajouté au nom d'hôte annoncé par le client.

*B. Le module et les VMs*

4. Étends `vm-noeud` : une carte peut prendre son adresse par DHCP (`ipv4 = "dhcp"`), sans préfixe ni passerelle. Exigences :
   - un appelant de M08 ou de M10 doit obtenir **le même plan** qu'avant (aucune ressource détruite ni recréée) : prouve-le (test OpenTofu ou plan d'un environnement existant) ;
   - NetBox reçoit la VM et l'interface, **pas d'adresse** (elle n'est pas connue au plan), et pas d'IP primaire si la première carte est en DHCP ;
   - une saisie incohérente (DHCP avec préfixe, DHCP avec passerelle) est refusée au plan ;
   - le README dit quand utiliser le DHCP et pourquoi il ne faut pas, dans ce cas, appeler `enregistrement-dns`.
   Publie-le (MR, nouvelle version mineure du dépôt).
5. Écris l'environnement `envs/m12` (versions, fournisseurs, *backend*, variables, les quatre hôtes). Lis le plan : combien de ressources ? Pourquoi aucune ressource DNS ? `apply` par le pipeline.
6. Une fois les VMs démarrées, vérifie depuis `adm01` que les quatre noms se résolvent (A et PTR) et que les adresses sont dans la plage dynamique de `vsandbox` :
   ```
   admin@adm01:~$ for h in ctr01 ctr02 ctr03 legacy01; do dig +short $h.par1.medisphere.internal; done
   admin@adm01:~$ cd ~/src/infra/envs/m12 && tofu output hotes
   ```
   Si un nom manque, cherche pourquoi (journal de `kea-dhcp-ddns` sur `dns01`, nom d'hôte annoncé par le client DHCP de la VM) avant d'aller plus loin.

*C. Ansible*

7. Ajoute la source d'inventaire `netbox-m12.yml`. Ces VMs n'ont pas d'IP primaire dans NetBox : comment Ansible saura-t-il où se connecter ? Vérifie `uv run ansible-inventory --graph env_m12` et `uv run ansible env_m12 -m ansible.builtin.ping`.
8. Écris le rôle `docker_engine` et son scénario Molecule. Exigences :
   - refus de tout autre système que Debian 13 ; paquets Debian en conflit retirés ;
   - clé téléchargée, **contrôlée par son empreinte**, et seulement ensuite installée ; dépôt deb822 limité à cette clé (`Signed-By`) ;
   - paquets en **versions exactes**, données par l'inventaire (`group_vars/role_docker/`), et épinglées pour qu'un `apt upgrade` à la main ne les change pas ;
   - `daemon.json` produit à partir d'un dictionnaire (défauts du rôle, complétés par l'inventaire), **validé par `dockerd` avant d'être mis en place** ; redémarrage du démon seulement s'il change ;
   - pour finir, le rôle vérifie la version du démon et le stockage d'images containerd.
9. Écris le rôle `podman_hote` et son scénario Molecule. Exigences :
   - Debian 13 et Rocky 10 ; refus d'un hôte en cgroup v1 ; sur Rocky, refus d'un SELinux qui ne serait pas en *enforcing* (on ne le désactive jamais) ;
   - paquets propres à chaque famille dans des variables, pas dans des conditions ; n'oublie pas ce que Debian ne range que dans les « Recommends » ;
   - compte `app` sans aucun groupe privilégié ; plage subordonnée **fixée** par l'inventaire, en refusant un chevauchement avec celle d'un autre compte ; linger ;
   - fichiers `registries.conf.d/` et `containers.conf.d/` (on complète, on ne réécrit pas ceux des paquets) ;
   - pour finir, le rôle vérifie, **en tant que `app`**, que Podman est sans privilège, en cgroup v2, avec pasta, dans la version attendue de la famille.
10. Écris le rôle `legacy_rdv`, qui reproduit la procédure d'InfoGér, et ses variables (`group_vars/role_legacy/`, Vault `lab` pour le mot de passe). Il vérifie que le mot de passe du Vault est bien celui de `config.php`, et que la page d'accueil répond avec le contenu de l'application.
11. Écris `playbooks/conteneurs.yml` (garde-fou d'inventaire, rôles communs, puis `docker_engine` et `podman_hote`) et `playbooks/legacy-rdv.yml`. Applique le premier par le pipeline ; le second depuis `adm01` (dis pourquoi dans la MR). Second passage : `changed=0`.
12. Constate le résultat :
    ```
    admin@adm01:~$ ssh ctr01.par1.medisphere.internal 'docker version --format "{{.Server.Version}}"; docker info --format "{{json .DriverStatus}}"'
    admin@adm01:~$ ssh ctr02.par1.medisphere.internal 'grep app /etc/subuid; loginctl show-user app -p Linger'
    admin@adm01:~$ curl -s http://legacy01.par1.medisphere.internal/ | grep -o '<title>.*</title>'
    ```

*D. Documentation*

13. Dans `plateforme/medisphere`, crée `docs/conteneurs/hotes.md` (rôle de chaque hôte, moteur et version, compte qui fait tourner les conteneurs, comment les reconstruire) et mets à jour l'inventaire de la plateforme. Matrice des flux : rien de nouveau sur la bordure au palier 1, dis pourquoi.

**Critères de réussite**
- [ ] Les VMs 2121-2124 sont créées par OpenTofu (`envs/m12`, module `vm-noeud`), conformes au contexte technique (nom, étiquettes, pool, CPU et mémoire, carte sur `vsandbox` avec la MAC du plan) ; `ctr03` est en `x86-64-v3`.
- [ ] Les quatre noms se résolvent dans `vsandbox` ; les VMs sont actives dans NetBox.
- [ ] `ctr01` : Docker 29.8 du dépôt de Docker (clé limitée au dépôt, versions épinglées, `docker.io` absent), stockage d'images containerd, `daemon.json` avec rotation des journaux et réseaux en `172.20.0.0/14`, Compose 5.6 et Buildx 0.37.
- [ ] `ctr02` (Podman 5.4) et `ctr03` (Podman 5.8, SELinux *enforcing*) : compte `app` sans sudo, plage `524288:65536`, linger, Podman sans privilège.
- [ ] `legacy01` : Legacy-RDV répond sur le port 80 depuis `adm01`, Apache et MariaDB actifs, PHP 8.4.
- [ ] `vm-noeud` (avec la carte DHCP), `envs/m12`, les trois rôles, leurs playbooks, la source d'inventaire et les scénarios Molecule sont sur `main` ; un second passage des playbooks donne `changed=0`.

**Vérification** : `lab/bin/check 12 02`

<details><summary>Indice 1</summary>

Dans le fournisseur `bpg/proxmox`, `initialization.ip_config.ipv4.address` accepte la valeur `dhcp`. Côté module, tout se joue sur la correspondance entre une carte et « son » adresse NetBox : si tu indexes les adresses par le rang de la carte, ajoute une liste des rangs des cartes statiques plutôt que de changer de `count` à `for_each`, qui déplacerait toutes les adresses d'état existantes. Un bloc `moved` règle le cas d'une ressource unique qui devient conditionnelle. `tofu test` avec `mock_provider` fait des plans sans Proxmox ni NetBox.
</details>

<details><summary>Indice 2</summary>

Le plugin d'inventaire NetBox est « constructible » : son option `compose` calcule des variables d'hôte, et `inventory_hostname` y est disponible. Pour la clé de Docker : `gpg --show-keys --with-colons` donne des lignes `fpr:` dont un champ est l'empreinte. Pour `daemon.json` : le filtre `combine(…, recursive=true)`, puis l'option `validate` du module `copy` avec `dockerd --validate --config-file=%s`. Pour l'épinglage : un fichier de `/etc/apt/preferences.d/`.
</details>

<details><summary>Indice 3</summary>

Pour agir « en tant que `app` » depuis Ansible : `become_user`, plus les variables `XDG_RUNTIME_DIR` et `DBUS_SESSION_BUS_ADDRESS` qui pointent vers `/run/user/<UID>` (que le linger fait exister) ; sans le paquet `acl`, Ansible ne sait pas passer ses fichiers temporaires à un compte sans privilège. Pour Legacy-RDV : pas de collection MySQL dans le projet, le client `mariadb` en root par le socket suffit, à condition de lui passer le SQL par l'**entrée standard** et de tester l'état avant d'agir (idempotence).
</details>

**Pour aller plus loin** (facultatif) : installe `docker-ce` sur une VM d'essai (2125) **sans** retirer le `runc` de Debian, et regarde ce qu'APT propose. Qu'est-ce que le champ `Conflicts` du paquet `containerd.io` t'aurait évité ?

---

### M12-E03 — Premiers conteneurs avec Docker : cycle de vie  `LAB` `★`

> **Ticket PLAT-1303** — *De : Nadia Roussel*
> Avant que les applications arrivent en conteneurs, je veux que l'astreinte sache faire le minimum sans paniquer : lancer, regarder les journaux, entrer dans un conteneur, l'arrêter, comprendre pourquoi il ne redémarre pas, et savoir où il est sur la machine. Fais-le toi-même une fois sur `ctr01`, en notant ce qui t'étonne : ça deviendra la fiche de l'astreinte.

**Objectifs pédagogiques**
- Maîtriser le cycle de vie d'un conteneur : création, démarrage, journaux, exécution d'une commande, arrêt, suppression.
- Comprendre ce que font `docker stop`, `docker kill` et une politique de redémarrage.
- Retrouver un conteneur sur l'hôte : processus, cgroup, shim, stockage des images (containerd dans Docker 29).

**Prérequis** : M12-E02.
**Durée indicative** : 1 h 30.

**Contexte technique** : tout se passe sur `ctr01`, en `admin` (membre du groupe `docker`). Nomme tes conteneurs `m12-e03-…` : les vérifications les cherchent par ces noms.

**Travail demandé**

1. Le moteur. Relève et explique chaque ligne qui suit (note-les dans `~/m12/e03/notes.md`) :
   ```
   admin@ctr01:~$ docker version
   admin@ctr01:~$ docker info --format '{{.Driver}} {{json .DriverStatus}} {{.CgroupDriver}} cgroup v{{.CgroupVersion}} {{.DefaultRuntime}} {{json .SecurityOptions}}'
   admin@ctr01:~$ systemctl status docker containerd --no-pager
   ```
   Où sont stockées les images ? Compare `sudo ls /var/lib/docker/` et `sudo ls /var/lib/containerd/`, puis `sudo ctr namespaces ls` et `sudo ctr -n moby images ls` (le client de containerd voit les images de Docker dans l'espace `moby`).

2. Un premier conteneur, éphémère :
   ```
   admin@ctr01:~$ docker run --rm docker.io/library/debian:trixie-slim cat /etc/os-release
   admin@ctr01:~$ docker run --rm -it docker.io/library/debian:trixie-slim bash
   root@<ID>:/# cat /proc/1/cmdline | tr '\0' ' '; echo; hostname; ls /proc | grep -c '^[0-9]'
   ```
   Qui est le PID 1 ? Combien de processus vois-tu ? Quel nom d'hôte ? Sors (`exit`) : que reste-t-il (`docker ps -a`) ?

3. Un service. Lance un serveur web en arrière-plan, publié sur le port 8080 de l'hôte, qui redémarre tant qu'on ne l'arrête pas volontairement :
   ```
   admin@ctr01:~$ docker run -d --name m12-e03-web -p 8080:80 --restart unless-stopped \
       --label medisphere.exercice=M12-E03 docker.io/library/nginx:1.30-trixie
   admin@ctr01:~$ docker ps
   admin@ctr01:~$ docker logs -f m12-e03-web
   ```
   Depuis `adm01`, `curl -s http://ctr01.par1.medisphere.internal:8080/ | head -5`, et regarde la ligne apparaître dans `docker logs`. Où nginx écrit-il ses journaux, puisqu'il n'y a pas de fichier ? (`docker exec m12-e03-web ls -l /var/log/nginx/`.)

4. Entre dans le conteneur et change la page d'accueil :
   ```
   admin@ctr01:~$ docker exec -it m12-e03-web bash
   root@<ID>:/# echo '<h1>MédiSphère — M12-E03</h1>' > /usr/share/nginx/html/index.html
   root@<ID>:/# exit
   admin@ctr01:~$ docker diff m12-e03-web
   ```
   Que liste `docker diff` (A, C, D) ? Où vit cette modification, et que deviendra-t-elle si le conteneur est supprimé ? (Ne le supprime pas : la vérification le cherche.)

5. Le conteneur vu de l'hôte :
   ```
   admin@ctr01:~$ docker top m12-e03-web
   admin@ctr01:~$ ps -ef --forest | grep -B1 -A3 '[c]ontainerd-shim'
   admin@ctr01:~$ PID=$(docker inspect -f '{{.State.Pid}}' m12-e03-web); cat /proc/$PID/cgroup; sudo ls -l /proc/$PID/ns/
   ```
   Quel processus est le parent de nginx ? Dans quel cgroup est-il ? Compare les liens de `/proc/$PID/ns/` avec ceux de `/proc/self/ns/` : lesquels diffèrent ?

6. Arrêter. Lance un conteneur dont le PID 1 est `sleep infinity`, et mesure son arrêt :
   ```
   admin@ctr01:~$ docker run -d --name m12-e03-sommeil docker.io/library/debian:trixie-slim sleep infinity
   admin@ctr01:~$ time docker stop m12-e03-sommeil
   admin@ctr01:~$ docker inspect -f '{{.State.ExitCode}}' m12-e03-sommeil
   ```
   Pourquoi dix secondes ? Que vaut le code de sortie et que signifie ce nombre ? Que ferait `docker kill -s TERM` sur ce conteneur ? (On y reviendra en M12-E17 ; garde ce conteneur arrêté.)

7. Redémarrer. Lance un conteneur qui échoue toujours, avec une politique de redémarrage limitée à trois tentatives :
   ```
   admin@ctr01:~$ docker run -d --name m12-e03-crash --restart on-failure:3 docker.io/library/debian:trixie-slim \
       sh -c 'echo "démarrage $(date +%T)"; sleep 2; exit 3'
   admin@ctr01:~$ docker events --since 2m --filter container=m12-e03-crash
   ```
   Quand les événements se calment, lis `docker logs m12-e03-crash` et `docker inspect -f '{{.RestartCount}} {{.State.Status}} {{.State.ExitCode}}' m12-e03-crash`. Combien de démarrages en tout ? Pourquoi les intervalles s'allongent-ils ?

8. Redémarre le démon (`sudo systemctl restart docker`) : que deviennent `m12-e03-web`, `m12-e03-sommeil` et `m12-e03-crash` ? Explique chaque cas par sa politique de redémarrage.

9. `docker inspect` est la source de vérité : retrouve, avec `--format`, l'adresse IP de `m12-e03-web`, son port publié, sa politique de redémarrage, l'image exacte (empreinte) dont il est issu et la date de son dernier démarrage.

10. Rédige, dans tes notes, la mini-fiche demandée par Nadia : six commandes et ce qu'elles disent, plus les trois codes de sortie à connaître (0, 137, 143) et ce qu'ils signifient.

**Critères de réussite**
- [ ] `m12-e03-web` tourne (nginx 1.30), publié sur le port 8080, avec la politique `unless-stopped`, et sert la page modifiée depuis `adm01`.
- [ ] `m12-e03-sommeil` est arrêté avec le code de sortie d'un processus tué par `SIGKILL`.
- [ ] `m12-e03-crash` est arrêté après exactement trois redémarrages, avec son code de sortie à lui.

**Vérification** : `lab/bin/check 12 03`

<details><summary>Indice 1</summary>

Un code de sortie supérieur à 128 veut dire « tué par un signal » : retire 128 et cherche le numéro dans `kill -l`.
</details>

<details><summary>Indice 2</summary>

Le noyau ne livre à un PID 1 que les signaux pour lesquels il a installé un gestionnaire, sauf `SIGKILL` et `SIGSTOP` venus de l'espace de noms parent. `sleep` n'en installe aucun. La politique de redémarrage attend de plus en plus longtemps entre deux tentatives (pour ne pas emballer la machine), et `unless-stopped` se souvient d'un arrêt volontaire.
</details>

**Pour aller plus loin** (facultatif) : `docker run --init` place un petit `init` (tini, le binaire `docker-init` de `docker info`) en PID 1. Refais l'étape 6 avec `--init` et compare la durée et le code de sortie.

---

### M12-E04 — Images, couches, manifestes et empreintes  `LAB` `★★`

> **Ticket SEC-1304** — *De : Sophie Laurent*
> L'auditeur HDS posera la question : « que tourne-t-il exactement en production ? ». « python 3.13 slim » n'est pas une réponse, c'est une étiquette que Docker Hub peut faire pointer ailleurs demain. Je veux qu'on sache lire une image jusqu'à ses couches, qu'on sache prouver qu'on parle de la même, et qu'on tienne la liste des **empreintes** de nos images de base.

**Objectifs pédagogiques**
- Lire la structure d'une image OCI : index, manifeste, configuration, couches, et ce que chaque empreinte désigne.
- Utiliser Skopeo (sans démon, sans tirer l'image) et les commandes d'images de Docker 29 (stockage containerd, images multi-plateformes).
- Épingler une image par empreinte, et savoir laquelle épingler.

**Prérequis** : M12-E03.
**Durée indicative** : 2 h.

**Contexte technique** : Skopeo est sur `ctr02` (rôle `podman_hote`) ; Docker sur `ctr01`. Travaille en `admin` dans `~/m12/e04/` sur les deux hôtes. Les empreintes changent à chaque republication d'une image publique : relève les tiennes, ne recopie pas celles d'un corrigé.

**Travail demandé**

*A. L'index et les manifestes, sans rien tirer (`ctr02`)*

1. Lis le document de tête de `python:3.13-slim-trixie`, tel que le registre le sert, puis calcule son empreinte toi-même :
   ```
   admin@ctr02:~$ skopeo inspect --raw docker://docker.io/library/python:3.13-slim-trixie | jq .
   admin@ctr02:~$ skopeo inspect --raw docker://docker.io/library/python:3.13-slim-trixie | sha256sum
   admin@ctr02:~$ skopeo inspect docker://docker.io/library/python:3.13-slim-trixie | jq '{Digest, Architecture, Os, Created}'
   ```
   Quel est le `mediaType` du document ? Combien de plateformes ? Que sont les entrées dont la plateforme est `unknown/unknown` (regarde leurs annotations) ? L'empreinte que tu as calculée correspond-elle au champ `Digest` ?

2. Descends d'un niveau : prends l'empreinte de l'entrée `linux/amd64` et lis son manifeste, puis la configuration :
   ```
   admin@ctr02:~$ skopeo inspect --raw docker://docker.io/library/python@sha256:<EMPREINTE-AMD64> | jq .
   admin@ctr02:~$ skopeo inspect --config docker://docker.io/library/python@sha256:<EMPREINTE-AMD64> | jq '{config: .config | {Env, Cmd, User, WorkingDir}, couches: (.rootfs.diff_ids | length), historique: [.history[].created_by][-5:]}'
   ```
   Combien de couches, de quelle taille (compressée) ? Que contient la configuration (utilisateur, commande, variables) ? Pourquoi la configuration a-t-elle elle aussi une empreinte ?

3. Une image sur le disque, au format OCI. Copie `debian:trixie-slim` (plateforme de l'hôte) dans un dossier au format *OCI layout* et explore-le :
   ```
   admin@ctr02:~$ skopeo copy docker://docker.io/library/debian:trixie-slim oci:/home/admin/m12/e04/debian-oci:trixie-slim
   admin@ctr02:~$ cd ~/m12/e04/debian-oci && cat oci-layout index.json | jq . && ls -l blobs/sha256/
   admin@ctr02:~/m12/e04/debian-oci$ for f in blobs/sha256/*; do echo "$(basename $f) $(sha256sum < $f | cut -c1-64)"; done
   ```
   Que constates-tu entre le nom de chaque fichier et sa somme ? Retrouve le manifeste, la configuration et la couche ; liste le début de la couche (`tar -tzf … | head`). L'empreinte du manifeste dans `index.json` est-elle celle de l'index public ou celle de l'entrée `linux/amd64` ? Pourquoi ?

4. Empreinte de couche et `diff_id`. Calcule l'empreinte de la couche **décompressée** (`gunzip -c … | sha256sum`) et compare-la aux `rootfs.diff_ids` de la configuration. Pourquoi deux empreintes pour la même couche ?

*B. Le même objet, vu par Docker 29 (`ctr01`)*

5. Tire l'image et regarde ce que Docker garde :
   ```
   admin@ctr01:~$ docker pull docker.io/library/debian:trixie-slim
   admin@ctr01:~$ docker image ls --tree
   admin@ctr01:~$ docker image inspect docker.io/library/debian:trixie-slim --format '{{.Id}} {{json .RepoDigests}} {{json .RootFS.Layers}}'
   admin@ctr01:~$ docker buildx imagetools inspect docker.io/library/debian:trixie-slim
   admin@ctr01:~$ docker image history docker.io/library/debian:trixie-slim
   ```
   Avec le stockage containerd, que vaut l'identifiant (`Id`) de l'image, comparé à l'empreinte de l'index ? Que montre `--tree` pour les plateformes que tu n'as pas tirées ? Les `RootFS.Layers` sont-elles des empreintes de couches compressées ou des `diff_id` ?

6. Tire la même image **par son empreinte d'index** et lance un conteneur ainsi désigné :
   ```
   admin@ctr01:~$ docker pull docker.io/library/debian:trixie-slim@sha256:<EMPREINTE-INDEX>
   admin@ctr01:~$ docker run --rm docker.io/library/debian:trixie-slim@sha256:<EMPREINTE-INDEX> cat /etc/debian_version
   ```

*C. La liste des empreintes de MédiSphère*

7. Sur `adm01`, écris `~/m12/e04/images-de-base.txt` : une ligne par image de base de référence (introduction, « Faits techniques » : `debian:trixie-slim`, `python:3.13-slim-trixie`, `golang:1.26-trixie`, `postgres:18-trixie`, `valkey/valkey:8-trixie`), au format `<nom complet>:<étiquette>@sha256:<empreinte>`. Quelle empreinte choisis-tu, celle de l'index ou celle de l'entrée `linux/amd64` ? Justifie en une phrase en tête de fichier (commentaire `#`).

8. Réponds dans tes notes : que se passe-t-il pour une construction qui épingle `FROM …@sha256:…` quand Debian publie un correctif de sécurité de `trixie-slim` ? Qu'est-ce que cela impose comme processus (M12-E27 et Renovate au M13 y répondront) ?

**Critères de réussite**
- [ ] `~/m12/e04/images-de-base.txt` sur `adm01` contient les cinq images de base, avec nom complet, étiquette et une empreinte qui désigne bien un **index** multi-plateformes existant dans le registre.
- [ ] `~/m12/e04/debian-oci/` sur `ctr02` est un *OCI layout* valide qui contient le manifeste `linux/amd64` de l'index épinglé de `debian:trixie-slim`.
- [ ] L'image `debian:trixie-slim` épinglée par l'empreinte de ton fichier est présente sur `ctr01`.

**Vérification** : `lab/bin/check 12 04`

<details><summary>Indice 1</summary>

Le registre ne calcule rien : l'empreinte d'un document est la somme SHA-256 de ses octets **exacts**. Reformater le JSON (avec `jq`) change l'empreinte : calcule-la sur la sortie brute.
</details>

<details><summary>Indice 2</summary>

Une couche est stockée et transportée compressée (son empreinte de blob), mais le système de fichiers d'un conteneur est fait de couches décompressées (leurs `diff_id`). Pour l'épinglage, demande-toi ce que verra une machine `arm64` (ou une construction multi-architectures au M12-E12) qui lit ta liste.
</details>

**Pour aller plus loin** (facultatif) : `skopeo inspect --raw` sur une image produite par BuildKit (celle de M12-E05, après E15) montre des « manifestes d'attestation » ; lis la spécification des référents OCI (`subject`, API *referrers*) : c'est là que vivront les signatures Cosign au M13.

---

### M12-E05 — Un premier Dockerfile pour MédiAgenda  `LAB` `★★`

> **Ticket DEV-1305** — *De : Julien Petit* — *Copie : Karim Benali*
> On voudrait arrêter d'envoyer une archive et une page de consignes. Peux-tu faire une première image de l'API ? Rien de sophistiqué pour l'instant : qu'elle démarre, qu'elle tourne pas en root, qu'elle ne reconstruise pas toutes les dépendances à chaque changement de code, et qu'elle affiche sa version. Notre projet n'est pas encore dans GitLab : crée `mediagenda/api` à partir de ce qu'il y a dans le workbook, j'y ajouterai l'équipe. Karim relira le Dockerfile.

**Objectifs pédagogiques**
- Écrire un Dockerfile lisible : image de base désignée précisément, ordre des couches pensé pour le cache, utilisateur non root, forme « exec » de la commande.
- Installer une application Python gérée par `uv` dans une image, à partir de son verrou.
- Mettre une application dans son propre projet GitLab et faire relire son Dockerfile en MR.

**Prérequis** : M12-E04 ; M01 (GitLab, MR, branches protégées).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet GitLab | `mediagenda/api` (groupe `mediagenda`, créé au M10) : visibilité privée, branche `main` protégée, fusion par MR, Julien Petit mainteneur ; contenu initial = `apps/mediagenda/` du workbook (à la racine du projet) |
| Copie de travail | `~/src/mediagenda-api` sur `adm01` (édition, Git) ; construction et exécution sur `ctr01`, dans `~/src/mediagenda-api` (copie synchronisée par `rsync`, sans `.git`) |
| Application | voir le [README de MédiAgenda](../../../apps/mediagenda/README.md) : Python 3.13, dépendances figées dans `uv.lock`, commandes `mediagenda` (serveur, port 8000) et `mediagenda-migrate` ; sans `MEDIAGENDA_DB_URL` et `MEDIAGENDA_VALKEY_URL`, le processus s'arrête avec le code 2 |
| Image | `mediagenda-api:0.1.0` (locale à `ctr01` pour l'instant ; le registre arrive en E15) ; uv **0.12.23** (PLAN §6) |

**Travail demandé**

1. Crée le projet `mediagenda/api` (vide), pousse-y le contenu de `apps/mediagenda/` comme premier commit de `main` (`feat: import de MédiAgenda 1.0.0 depuis le workbook`), puis protège `main` et ajoute `julien.petit` (mainteneur) et `karim.benali` (développeur). Vérifie que les tests passent sur `adm01` (`uv sync --locked && uv run pytest`).

2. Sur une branche `feat/dockerfile`, écris un `Dockerfile` et un `.dockerignore` qui respectent les exigences suivantes (Karim relit exactement celles-ci) :
   - image de base `python:3.13-slim-trixie`, désignée par son **nom complet** ; pas de `latest` nulle part ;
   - `uv` en version **0.12.23** exactement, sans `curl | sh` ni `pip install` ;
   - les dépendances installées **d'après le verrou** (`--locked`), sans les dépendances de développement, **dans une couche qui ne dépend pas du code** de l'application ;
   - le code et les migrations ajoutés ensuite ; les commandes `mediagenda` et `mediagenda-migrate` dans le `PATH` ;
   - la version de l'image passée à la construction (`--build-arg VERSION=…`) et exposée à l'application par `MEDIAGENDA_VERSION` ;
   - l'application tourne sous un **utilisateur non root**, d'**UID numérique fixe 10001** ;
   - le port 8000 documenté ; la commande en **forme exec** ;
   - le contexte de construction n'emporte ni `.git`, ni l'environnement virtuel local, ni les tests, ni les fichiers de secrets.
   Commente le Dockerfile : chaque instruction dit pourquoi elle est là.

3. Synchronise la copie de travail vers `ctr01` et construis :
   ```
   admin@adm01:~/src/mediagenda-api$ rsync -a --delete --exclude .git --exclude .venv --exclude secrets ./ ctr01.par1.medisphere.internal:src/mediagenda-api/
   admin@ctr01:~/src/mediagenda-api$ docker build --build-arg VERSION=0.1.0 -t mediagenda-api:0.1.0 .
   ```
   Lis la sortie de BuildKit : combien d'étapes, lesquelles sont longues ?

4. Le cache. Modifie une ligne de `src/mediagenda/app.py` (un commentaire), resynchronise, reconstruis : quelles étapes sont `CACHED` ? Puis ajoute une ligne vide à la fin de `pyproject.toml` : qu'est-ce qui se reconstruit maintenant, et pourquoi ? (Annule ces deux changements ensuite.)

5. Inspecte l'image :
   ```
   admin@ctr01:~$ docker image ls mediagenda-api
   admin@ctr01:~$ docker image inspect mediagenda-api:0.1.0 --format '{{json .Config.User}} {{json .Config.Cmd}} {{json .Config.Entrypoint}} {{json .Config.ExposedPorts}}'
   admin@ctr01:~$ docker image history mediagenda-api:0.1.0
   admin@ctr01:~$ docker run --rm --entrypoint id mediagenda-api:0.1.0
   ```
   Quelle couche pèse le plus lourd ? Que montre `docker image ls` pour la taille sur disque et la taille du contenu ?

6. Lance l'image sans configuration, puis avec une configuration qui pointe vers des services **inexistants** (aucun secret ici : ce sont des adresses fictives) :
   ```
   admin@ctr01:~$ docker run --rm mediagenda-api:0.1.0; echo "code=$?"
   admin@ctr01:~$ docker run -d --name m12-e05-api -p 8001:8000 \
       -e MEDIAGENDA_DB_URL=postgresql://lecture:aucun@db.invalid:5432/mediagenda \
       -e MEDIAGENDA_VALKEY_URL=redis://valkey.invalid:6379/0 mediagenda-api:0.1.0
   admin@adm01:~$ curl -s http://ctr01.par1.medisphere.internal:8001/sante; echo
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' http://ctr01.par1.medisphere.internal:8001/pret
   ```
   Explique les deux réponses à partir du README (vivacité, disponibilité). Lis `docker logs m12-e05-api` : quel format ?

7. Vérifie l'arrêt : `time docker stop m12-e05-api` puis `docker start m12-e05-api`. Comparé à `m12-e03-sommeil`, pourquoi est-ce rapide ?

8. Ouvre la MR (description : exigences, commandes de construction, taille de l'image), demande la relecture de `karim.benali`, fusionne. Garde `m12-e05-api` démarré jusqu'à la vérification.

**Critères de réussite**
- [ ] `mediagenda/api` existe ; `main` contient le code de MédiAgenda, son `uv.lock`, un `Dockerfile` et un `.dockerignore` conformes aux exigences (nom complet de l'image de base, pas de `latest`, utilisateur non root, forme exec).
- [ ] L'image `mediagenda-api:0.1.0` existe sur `ctr01` : utilisateur 10001, commande en forme exec, version 0.1.0, port 8000 déclaré.
- [ ] `m12-e05-api` tourne et `/sante` répond `0.1.0` depuis `adm01`.

**Vérification** : `lab/bin/check 12 05`

<details><summary>Indice 1</summary>

`COPY --from=<image>` copie un fichier depuis **n'importe quelle image**, pas seulement depuis une étape du même Dockerfile : la documentation d'uv (« Using uv in Docker ») s'en sert pour le binaire `uv`. Pour séparer dépendances et code : `uv sync` a une option qui installe tout **sauf le projet lui-même**.
</details>

<details><summary>Indice 2</summary>

Le projet est construit par `uv_build`, qui lit le `README.md` déclaré dans `pyproject.toml`. Pour l'utilisateur : `useradd --system --uid …`, puis `USER` avec l'**UID numérique** (un nom ne dit rien à Kubernetes, M14, quand il vérifiera `runAsNonRoot`). Pour les `.pyc` et les liens durs, lis les variables `UV_COMPILE_BYTECODE` et `UV_LINK_MODE` dans la documentation d'uv.
</details>

<details><summary>Indice 3</summary>

La forme « shell » (`CMD mediagenda`) fait de `/bin/sh -c` le PID 1. Relis la section « Arrêt propre » du README de MédiAgenda.
</details>

**Pour aller plus loin** (facultatif) : construis la même image deux fois de suite sans cache (`--no-cache`) et compare les empreintes : pourquoi diffèrent-elles alors que rien n'a changé ? (M12-E11 répond avec `SOURCE_DATE_EPOCH`.)

---

### M12-E06 — Podman sans privilège  `LAB` `★★`

> **Ticket SEC-1306** — *De : Sophie Laurent*
> Un démon root qui écoute sur un socket, c'est le premier point que je regarde dans un audit. Montre-moi que Podman fait tourner nos conteneurs **sans aucun privilège** sur `ctr02` : sous quel UID ils tournent vraiment, ce qu'un « root » de conteneur peut faire sur l'hôte, et ce que ça nous coûte (ports, droits sur les fichiers). Je veux des preuves vues de l'hôte, pas des affirmations.

**Objectifs pédagogiques**
- Comprendre le fonctionnement sans privilège : espace de noms `user`, plages subordonnées, `newuidmap`, stockage par utilisateur, réseau par pasta.
- Ouvrir une vraie session pour un compte de service (`machinectl shell`) et savoir pourquoi `sudo -u` ne suffit pas.
- Lire la correspondance des UID entre conteneur et hôte, et ses conséquences sur les ports et les fichiers.

**Prérequis** : M12-E02, M12-E03.
**Durée indicative** : 2 h.

**Contexte technique** : `ctr02`, compte `app` (UID 1001, sans sudo, plage `524288:65536`). On ouvre une session `app` depuis `admin` ; les commandes `app@ctr02` se lancent dans cette session, les commandes `admin@ctr02` dans une autre (pour voir l'hôte).

**Travail demandé**

1. Ouvre une session pour `app` de deux façons et compare :
   ```
   admin@ctr02:~$ sudo -u app podman info 2>&1 | head -5
   admin@ctr02:~$ sudo machinectl shell app@
   app@ctr02:~$ echo "$XDG_RUNTIME_DIR"; systemctl --user is-system-running
   ```
   Quels avertissements donne la première forme et pourquoi ? Pourquoi le linger compte-t-il ici ?

2. Ce que Podman sait de lui-même :
   ```
   app@ctr02:~$ podman info --format '{{.Host.Security.Rootless}} {{.Host.RootlessNetworkCmd}} {{.Host.CgroupsVersion}} {{.Store.GraphRoot}} {{.Store.RunRoot}}'
   app@ctr02:~$ podman info --format json | jq '.host.idMappings'
   ```
   Où sont stockées les images de `app` ? Compare avec `/var/lib/containers/storage` (celui de root).

3. L'espace de noms `user`, à la main :
   ```
   app@ctr02:~$ grep app /etc/subuid /etc/subgid
   app@ctr02:~$ podman unshare cat /proc/self/uid_map
   app@ctr02:~$ podman unshare id
   app@ctr02:~$ podman unshare ls -ln ~/.local/share/containers/storage | head
   ```
   Explique chaque ligne de `uid_map`. Quel programme a écrit cette table, et pourquoi faut-il qu'il soit `setuid` (ou porteur de capacités) ?

4. Un serveur web sans privilège :
   ```
   app@ctr02:~$ podman run -d --name m12-e06-web -p 8080:80 docker.io/library/nginx:1.30-trixie
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' http://ctr02.par1.medisphere.internal:8080/
   ```
   Puis essaie de publier le port 80 (`podman run --rm -d --name m12-e06-essai80 -p 80:80 docker.io/library/nginx:1.30-trixie`) : quel message ? Cite trois façons de servir sur le port 80 malgré tout, avec le prix de chacune pour la sécurité de l'hôte, et note celle que tu recommandes (ne l'applique pas).

5. Les UID vus de l'intérieur et de l'hôte :
   ```
   app@ctr02:~$ podman top m12-e06-web user huser pid hpid args
   admin@ctr02:~$ ps -o user,uid,pid,ppid,args -C nginx
   admin@ctr02:~$ ps -ef --forest | grep -B2 -A2 '[c]onmon'
   ```
   Calcule, à partir de la table de l'étape 3, l'UID d'hôte attendu pour l'utilisateur `nginx` (UID 101 dans l'image) et vérifie-le. Qui est le parent de nginx ? Quel processus porte le réseau (`ps -u app -o pid,args | grep -E 'pasta|rootlessport'`) ?

6. Les fichiers. Crée `~/m12/e06/partage` (en `app`) et monte-le dans un conteneur :
   ```
   app@ctr02:~$ mkdir -p ~/m12/e06/partage
   app@ctr02:~$ podman run --rm -v ~/m12/e06/partage:/partage docker.io/library/debian:trixie-slim \
       sh -c 'touch /partage/par-root; mkdir -p /partage/dossier-1000; touch /partage/dossier-1000/f; chown -R 1000:1000 /partage/dossier-1000'
   app@ctr02:~$ ls -ln ~/m12/e06/partage; podman unshare ls -ln ~/m12/e06/partage
   app@ctr02:~$ rm -rf ~/m12/e06/partage/dossier-1000
   ```
   À qui appartiennent `par-root` et `dossier-1000`, vus de l'hôte puis vus « de l'intérieur » ? Pourquoi `app`, propriétaire de `partage`, ne peut-il pas supprimer `dossier-1000` ? Comment le faire sans sudo ? Refais l'essai avec `--userns=keep-id` : qu'est-ce qui change, et pour quel usage est-ce fait ?

7. Comparaison avec Docker. Sur `ctr01`, lance `docker run -d --name m12-e06-compare docker.io/library/nginx:1.30-trixie` et regarde `ps -o user,uid,args -C nginx` : sous quel UID tourne le processus maître ? Que pourrait faire un attaquant qui s'évade de ce conteneur, comparé à celui de `ctr02` ? Supprime ensuite `m12-e06-compare`.

8. Ferme la session (`exit`) et vérifie depuis `admin` que `m12-e06-web` tourne encore (`sudo -n -u app XDG_RUNTIME_DIR=/run/user/1001 podman ps`). Laisse-le en place jusqu'à la vérification.

**Critères de réussite**
- [ ] `m12-e06-web` tourne sous le compte `app` de `ctr02`, publié sur le port 8080 et joignable depuis `adm01`.
- [ ] Vu de l'hôte, le processus maître de nginx tourne sous l'UID de `app`, et ses processus de travail sous un UID de la plage subordonnée de `app` ; le réseau du conteneur est porté par pasta, processus de `app`.
- [ ] Les images de `app` sont dans son stockage personnel, pas dans celui de root.

**Vérification** : `lab/bin/check 12 06`

<details><summary>Indice 1</summary>

`sudo -u` change d'UID mais n'ouvre pas de **session** : pas de `XDG_RUNTIME_DIR`, pas de gestionnaire systemd utilisateur à qui déléguer les cgroups. `machinectl shell` (paquet `systemd-container`) passe par logind comme une vraie connexion.
</details>

<details><summary>Indice 2</summary>

Ligne de `uid_map` : « premier UID dans l'espace, premier UID dans l'espace parent, nombre ». L'UID 0 du conteneur est celui de `app` lui-même ; les suivants viennent de la plage subordonnée **à partir de 1**. Pour les ports : regarde le paramètre `net.ipv4.ip_unprivileged_port_start` et ce qu'il changerait pour **tous** les comptes de la machine.
</details>

**Pour aller plus loin** (facultatif) : refais l'étape 4 avec `--network slirp4netns` (encore disponible en 5.4, supprimé en Podman 6) et compare l'adresse source vue par nginx (`podman logs`) pour une requête venue de `adm01`.

---

### M12-E07 — Volumes, montages et réseaux  `LAB` `★★`

> **Ticket PLAT-1307** — *De : Karim Benali*
> La semaine prochaine on monte la pile de MédiAgenda avec sa base. Avant, je veux que tu saches exactement où vont les données d'un conteneur, ce qui survit à sa suppression, comment deux conteneurs se trouvent, et ce que Docker écrit dans le pare-feu de l'hôte quand on publie un port. Fais-le sur `ctr01`, avec un nginx et des conteneurs de test, et note les surprises.

**Objectifs pédagogiques**
- Choisir entre volume nommé, montage lié et tmpfs selon la donnée ; connaître leurs pièges (contenu initial, inode d'un fichier monté, droits).
- Utiliser des réseaux définis : DNS intégré, réseau interne sans sortie, réseau de l'hôte.
- Comprendre la publication de ports et son effet sur le pare-feu de l'hôte.

**Prérequis** : M12-E03.
**Durée indicative** : 2 h.

**Contexte technique** : `ctr01`, en `admin`. Nomme tes objets `m12-e07-…`. Les réseaux des conteneurs sont pris dans `172.20.0.0/14` (`daemon.json`, M12-E02).

**Travail demandé**

*A. Les données*

1. Un volume nommé, d'abord vide :
   ```
   admin@ctr01:~$ docker volume create m12-e07-pages
   admin@ctr01:~$ docker volume inspect m12-e07-pages
   admin@ctr01:~$ docker run --rm -v m12-e07-pages:/usr/share/nginx/html docker.io/library/nginx:1.30-trixie ls /usr/share/nginx/html
   ```
   Le volume était vide : pourquoi contient-il maintenant les pages de nginx ? Le ferait-il avec un montage lié ? Écris dans le volume une page d'accueil qui contient le texte `M12-E07` (par un conteneur jetable, pas en écrivant sous `/var/lib/docker` en root).

2. Un montage lié pour la configuration. Sur `ctr01`, écris dans `~/m12/e07/nginx/default.conf` une configuration de serveur nginx qui sert `/usr/share/nginx/html` et répond `200 ok` sur `/sante`. Monte le **dossier** `~/m12/e07/nginx/` en lecture seule à la place de `/etc/nginx/conf.d/`.

3. Un tmpfs pour ce qui est jetable : le cache de nginx (`/var/cache/nginx`), 16 Mo au plus.

4. Assemble le tout dans le conteneur `m12-e07-web` (nginx 1.30), publié sur le port **8081** de l'hôte, sur le réseau `m12-e07-front` de l'étape 6 (crée-le d'abord). Vérifie depuis `adm01` la page d'accueil et `/sante`. Supprime le conteneur, recrée-le : la page d'accueil est-elle toujours là ?

5. Le piège de l'inode. Monte cette fois **un fichier** (`~/m12/e07/essai.conf`) dans un conteneur jetable, puis modifie-le sur l'hôte avec un éditeur qui réécrit le fichier (`vim`, `sed -i`) : le conteneur voit-il le changement (`docker exec … cat …`) ? Compare `ls -i` avant et après. Pourquoi a-t-on monté un dossier à l'étape 2 ?

*B. Les réseaux*

6. Le DNS intégré. Lance deux conteneurs `debian:trixie-slim` (`sleep infinity`) sur le réseau par défaut et vérifie qu'ils ne se trouvent pas par leur nom ; puis crée le réseau défini `m12-e07-front` et un conteneur `m12-e07-client` dessus :
   ```
   admin@ctr01:~$ docker network create m12-e07-front
   admin@ctr01:~$ docker run -d --name m12-e07-client --network m12-e07-front docker.io/library/debian:trixie-slim sleep infinity
   admin@ctr01:~$ docker exec m12-e07-client getent hosts m12-e07-web
   admin@ctr01:~$ docker exec m12-e07-client cat /etc/resolv.conf
   admin@ctr01:~$ docker network inspect m12-e07-front --format '{{json .IPAM.Config}}'
   ```
   Qui répond à l'adresse du `resolv.conf` du conteneur ? Dans quel sous-réseau a été pris `m12-e07-front`, et pourquoi pas dans `192.168.0.0/16` ? (Supprime les deux conteneurs du réseau par défaut.)

7. Un réseau **interne** : crée `m12-e07-arriere` avec `--internal`, lance dessus un conteneur `m12-e07-isole` (`sleep infinity`) et montre qu'il ne sort pas : `docker exec m12-e07-isole timeout 3 bash -c '</dev/tcp/deb.debian.org/80' && echo sortie || echo bloque`. Fais le même essai depuis `m12-e07-client`. À quoi servira ce type de réseau pour une base de données ?

8. Le réseau de l'hôte : `docker run --rm -d --name m12-e07-hote --network host docker.io/library/nginx:1.30-trixie`, puis `sudo ss -ltnp | grep nginx`. Qu'est-ce qui disparaît (isolation, publication de ports) ? Arrête-le.

*C. Ports et pare-feu*

9. Lance un conteneur publié sur toutes les adresses et un autre sur la seule boucle locale :
   ```
   admin@ctr01:~$ docker run -d --name m12-e07-p1 -p 8082:80 docker.io/library/nginx:1.30-trixie
   admin@ctr01:~$ docker run -d --name m12-e07-p2 -p 127.0.0.1:8083:80 docker.io/library/nginx:1.30-trixie
   admin@ctr01:~$ sudo nft list ruleset | grep -nE 'DOCKER|dnat|8082|8083' | head -40
   ```
   Retrouve la règle de traduction d'adresse (DNAT) de chaque port. Depuis `adm01`, lequel répond ? Dans quelle chaîne du pare-feu la règle de filtrage d'un port publié est-elle évaluée, et pourquoi une règle posée dans `INPUT` ne l'arrête-t-elle pas ? Où l'administrateur doit-il mettre ses propres règles (documentation Docker, « Packet filtering and firewalls ») ? Supprime `m12-e07-p1` et `m12-e07-p2`.

10. Note dans `~/m12/e07/notes.md` un tableau « donnée → type de stockage » pour la pile de MédiAgenda (fichiers de PostgreSQL, cache Valkey, configuration, secrets, fichiers temporaires).

**Critères de réussite**
- [ ] `m12-e07-web` tourne (nginx 1.30) avec le volume `m12-e07-pages` sur les pages, le dossier `~/m12/e07/nginx` monté **en lecture seule** sur `/etc/nginx/conf.d`, un tmpfs sur `/var/cache/nginx`, sur le réseau `m12-e07-front`, publié sur 8081 ; depuis `adm01`, `/` contient `M12-E07` et `/sante` répond 200.
- [ ] `m12-e07-client` (réseau `m12-e07-front`) résout `m12-e07-web` par son nom ; `m12-e07-front` est pris dans `172.20.0.0/14`.
- [ ] `m12-e07-arriere` est un réseau interne ; `m12-e07-isole` n'est attaché qu'à lui.

**Vérification** : `lab/bin/check 12 07`

<details><summary>Indice 1</summary>

Docker recopie le contenu de l'image dans un volume **nommé et vide** au premier montage ; il ne le fait jamais pour un montage lié, qui **masque** ce qui est dessous. Pour le tmpfs : `--tmpfs <chemin>:size=…` ou `--mount type=tmpfs,…`.
</details>

<details><summary>Indice 2</summary>

Un montage lié d'un fichier lie un **inode**, pas un nom. Le DNS intégré de Docker répond sur `127.0.0.11`, et seulement sur les réseaux définis. Pour le pare-feu : la traduction d'adresse se fait **avant** le routage (`PREROUTING`) ; le paquet ne va donc plus « à l'hôte », il est **relayé** vers le conteneur.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Packet filtering and firewalls » sur le backend **nftables** expérimental de Docker 29 (`"firewall-backend": "nftables"`) : sur une VM d'essai, compare les tables créées avec celles d'aujourd'hui.

---

### M12-E08 — Docker Compose : MédiAgenda, PostgreSQL et Valkey  `LAB` `★★`

> **Ticket DEV-1308** — *De : Julien Petit* — *Copie : Karim Benali, Sophie Laurent*
> Super, l'image ! Maintenant il me faudrait toute la pile en une commande, sur `ctr01` pour la recette et sur nos postes : l'API, PostgreSQL 18 et Valkey 8. L'API ne doit démarrer qu'une fois la base prête **et migrée**, la base ne doit pas être joignable de l'extérieur, et Sophie ne veut voir aucun mot de passe dans le fichier ni dans `docker inspect`. Le fichier va dans notre dépôt, à côté du Dockerfile.

**Objectifs pédagogiques**
- Décrire une pile dans un `compose.yaml` conforme à la spécification Compose (sans `version:`), avec des dépendances **conditionnées** par la santé des services.
- Lancer les migrations par un service ponctuel, avant l'application.
- Passer un secret à un conteneur sans qu'il apparaisse dans le fichier, dans l'environnement ni dans `docker inspect` ; isoler la base dans un réseau interne ; utiliser les profils.

**Prérequis** : M12-E05, M12-E07.
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Fichier | `compose.yaml` à la racine de `mediagenda/api` ; nom du projet Compose `mediagenda` |
| Images | `docker.io/library/postgres:18-trixie`, `docker.io/valkey/valkey:8-trixie`, `mediagenda-api:0.1.0` (E05, construite par Compose si absente) |
| PostgreSQL 18 | base et compte `mediagenda` ; l'image officielle lit le mot de passe dans un fichier (`POSTGRES_PASSWORD_FILE`) ; **nouveau en 18** : les données sont dans `/var/lib/postgresql/18/docker`, le volume se monte sur `/var/lib/postgresql` |
| MédiAgenda | configuration par l'environnement seulement (`MEDIAGENDA_DB_URL` contient le mot de passe) ; migrations par `mediagenda-migrate` (idempotentes, verrou consultatif) ; vivacité `/sante`, disponibilité `/pret` ; image sans `curl` |
| Secret | fichier `secrets/db_mdp` à côté de `compose.yaml`, **jamais versionné** ; créé par un petit script du dépôt (`outils/secrets-compose.sh`) |
| Publication | API seule, port 8000 de `ctr01` ; ni PostgreSQL ni Valkey publiés |

**Travail demandé**

1. Lis la page « Compose file reference » sur `services.depends_on` (conditions `service_healthy`, `service_completed_successfully`), `healthcheck`, `secrets`, `profiles` et `networks.internal`. Note ce que Compose fait d'un secret de type `file:` sans Swarm.

2. Écris, sur une branche `feat/compose`, le `compose.yaml` qui répond au ticket :
   - quatre services : `db`, `valkey`, `migrations` (ponctuel), `api` ; un service `psql` (client de la base) dans un profil `outils`, jamais lancé par un `up` ordinaire ;
   - chaque service à état a une **sonde de santé** adaptée (sans `curl` dans l'image de l'API) ; la sonde de l'API ne dépend pas de la base ;
   - `migrations` attend que `db` soit **saine** ; `api` attend que `migrations` se soit **terminée avec succès** et que `valkey` soit saine ;
   - le mot de passe n'est **que** dans le secret : ni dans `compose.yaml`, ni dans une variable d'environnement visible par `docker inspect` ;
   - deux réseaux : un pour l'API vers l'extérieur, un **interne** pour la base et le cache ;
   - les données de PostgreSQL dans un volume nommé ; Valkey sans persistance (c'est un cache) ;
   - politiques de redémarrage adaptées (et pas pour le service ponctuel).
   Écris aussi `outils/secrets-compose.sh` (crée le secret s'il n'existe pas, ne le remplace jamais) et ajoute `secrets/` au `.gitignore`.

3. Valide et démarre sur `ctr01` :
   ```
   admin@adm01:~/src/mediagenda-api$ rsync -a --delete --exclude .git --exclude .venv --exclude secrets ./ ctr01.par1.medisphere.internal:src/mediagenda-api/
   admin@ctr01:~/src/mediagenda-api$ ./outils/secrets-compose.sh
   admin@ctr01:~/src/mediagenda-api$ docker compose config --quiet && docker compose config --services
   admin@ctr01:~/src/mediagenda-api$ docker compose up -d --wait
   admin@ctr01:~/src/mediagenda-api$ docker compose ps -a
   admin@ctr01:~/src/mediagenda-api$ docker compose logs migrations
   ```
   Dans quel ordre les conteneurs ont-ils démarré ? Que dit `docker compose ps -a` du service `migrations` ? Arrête `docker compose up` s'il bloque, lis les journaux du service qui échoue (le corrigé liste les erreurs courantes, mais cherche d'abord).

4. Teste depuis `adm01` :
   ```
   admin@adm01:~$ curl -s http://ctr01.par1.medisphere.internal:8000/pret; echo
   admin@adm01:~$ curl -s -X POST http://ctr01.par1.medisphere.internal:8000/api/v1/rendez-vous -H 'Content-Type: application/json' \
       -d '{"patient": "Jeanne Exemple", "praticien": "dr-morel", "debut": "2026-11-02T09:00:00+01:00", "duree_minutes": 30, "motif": "Suivi"}'
   admin@adm01:~$ curl -s "http://ctr01.par1.medisphere.internal:8000/api/v1/creneaux?date=2026-11-02&praticien=dr-morel" | head -c 300; echo
   ```
   Puis, sur `ctr01`, interroge la base par le profil `outils` : `docker compose --profile outils run --rm psql` et `SELECT * FROM mediagenda_historique_schema;`.

5. Les preuves que Sophie demande :
   ```
   admin@ctr01:~$ docker inspect mediagenda-api-1 --format '{{json .Config.Env}}'
   admin@ctr01:~$ docker port mediagenda-db-1; docker port mediagenda-api-1
   admin@ctr01:~$ docker network inspect mediagenda_arriere --format '{{.Internal}}'
   admin@ctr01:~$ docker exec mediagenda-api-1 cat /proc/1/cmdline | tr '\0' ' '; echo
   ```
   Le PID 1 de l'API est-il bien `mediagenda` (et pas un shell) ?

6. Cycle de vie : `docker compose restart api`, `docker compose stop` puis `up -d --wait` (les migrations se rejouent-elles ? qu'affichent-elles ?), `docker compose down` (que reste-t-il : `docker volume ls`, `docker network ls`) puis `up -d --wait` : les rendez-vous sont-ils toujours là ?
   > ⚠️ **Attention** : `docker compose down -v` supprime aussi le volume `mediagenda_donnees-db`, donc la base. Ne le lance que si tu veux repartir d'une base vide, et jamais par habitude.

7. Ouvre la MR (`compose.yaml`, script, `.gitignore`), relecture `julien.petit` et `karim.benali`, fusion. Vérifie dans GitLab que `secrets/` n'a jamais été poussé. Laisse la pile démarrée jusqu'à la vérification ; tu peux supprimer `m12-e05-api`.

**Critères de réussite**
- [ ] La pile `mediagenda` tourne sur `ctr01` : `db`, `valkey` et `api` sains, `migrations` terminé avec le code 0 ; depuis `adm01`, `/pret` répond 200 sur le port 8000.
- [ ] Ni PostgreSQL ni Valkey ne publient de port ; leur réseau est interne ; les données de PostgreSQL sont dans un volume nommé monté sur `/var/lib/postgresql`.
- [ ] Le mot de passe de la base n'apparaît dans l'environnement d'aucun conteneur ; le PID 1 de l'API est `mediagenda`.
- [ ] `compose.yaml` est sur `main` de `mediagenda/api`, sans attribut `version:` ; aucun fichier de `secrets/` n'est versionné.

**Vérification** : `lab/bin/check 12 08`

<details><summary>Indice 1</summary>

Le serveur PostgreSQL de l'image a `pg_isready` ; Valkey a `valkey-cli ping` ; l'image de l'API a Python. Pour le service ponctuel : `restart: "no"` et la condition `service_completed_successfully` côté consommateur.
</details>

<details><summary>Indice 2</summary>

L'application ne lit pas de fichier de secret : il faut donc fabriquer `MEDIAGENDA_DB_URL` **au démarrage du processus**, à partir de `/run/secrets/db_mdp`, sans que la variable figure dans la définition du conteneur, et sans laisser un shell en PID 1 (pense à `exec`). Dans un fichier Compose, `$` se double pour arriver jusqu'au shell du conteneur.
</details>

<details><summary>Indice 3</summary>

Sans Swarm, un secret `file:` est un **montage lié** du fichier de l'hôte : il garde ses droits d'hôte (les options `uid`, `gid`, `mode` ne s'y appliquent pas). Si l'API, sous l'UID 10001, ne peut pas le lire, demande-toi où mettre la protection : sur le fichier ou sur le **dossier** qui le contient.
</details>

**Pour aller plus loin** (facultatif) : Compose v5 construit par Bake : lance `docker compose build --print` et lis la définition Bake produite. Que faudrait-il pour construire l'image de l'API pour `linux/arm64` depuis Compose (M12-E12) ?

---

### M12-E09 — Questions : architecture des conteneurs  `Q` `★★`

> **Ticket PLAT-1309** — *De : Karim Benali*
> Tu as manipulé deux moteurs, des images et une pile. Avant d'aller plus loin, je veux que tu saches dessiner ce qui se passe entre `docker run` et le processus qui tourne, et qui fait quoi dans les normes OCI : c'est ce qui permettra de comprendre Kubernetes au M14, qui parle à containerd sans passer par Docker. Par écrit, sans exécuter, schémas bienvenus.

**Objectifs pédagogiques**
- Décrire la chaîne d'exécution d'un conteneur, du client au noyau, pour Docker et pour Podman.
- Situer les spécifications OCI (image, runtime, distribution) et l'interface CRI de Kubernetes.

**Prérequis** : M12-E03 à E08.
**Durée indicative** : 1 h.

**Travail demandé**

Réponds aux 12 questions.

1. Dessine la chaîne complète de `docker run -d docker.io/library/nginx:1.30-trixie` sur `ctr01` : client, API, démon, containerd, shim, runtime, noyau. Pour chaque maillon : qui il est (binaire, processus), ce qu'il reçoit, ce qu'il produit, et s'il est encore là quand nginx tourne.

2. Même exercice pour `podman run -d …` sous `app` sur `ctr02`. Qui joue le rôle du shim ? Où est le démon ?

3. *(QCM)* On redémarre `containerd` sur `ctr01` pendant que `m12-e03-web` tourne. Que devient nginx ?
   - A. Il est tué avec containerd, puis relancé grâce à sa politique de redémarrage
   - B. Il continue de tourner : son shim le garde et containerd le retrouve à son retour
   - C. Il continue de tourner, mais `docker` ne le verra plus jamais
   - D. Il se fige jusqu'au retour de containerd

4. Que contient un **bundle** OCI, et qui le fabrique à partir de l'image ? Que se passe-t-il pour le système de fichiers du conteneur entre les couches de l'image et la racine que voit runc (citer le *snapshotter* de containerd ou le pilote de stockage de Podman) ?

5. Les trois spécifications OCI : pour chacune, ce qu'elle normalise, un document ou une API qu'elle définit, et un outil de ce module qui l'implémente.

6. Pourquoi l'exécution (runc, crun) est-elle séparée de la gestion (containerd, Podman) ? Donne deux bénéfices concrets de cette séparation.

7. *(QCM)* Qu'est-ce que le CRI (*Container Runtime Interface*) ?
   - A. Le format des images utilisé par Kubernetes
   - B. L'API gRPC par laquelle le kubelet demande à un moteur (containerd, CRI-O) de gérer pods, conteneurs et images
   - C. Le nom donné par Kubernetes à runc
   - D. Une extension de l'API Docker

8. En 2022, Kubernetes 1.24 a retiré `dockershim`. Les images construites avec Docker fonctionnent-elles encore sur un cluster qui utilise containerd ? Pourquoi ? Qu'est-ce qui a réellement disparu ?

9. Docker 29 stocke ses images dans containerd. Quelles différences visibles as-tu constatées (E03, E04) ? Que gagne-t-on (pense aux images multi-plateformes et aux attestations) ?

10. Rôle de **conmon** pour Podman : cite trois choses qu'il fait. Pourquoi Podman n'a-t-il pas besoin de démon pour qu'un conteneur survive à la commande qui l'a créé ?

11. Pourquoi peut-on construire une image avec Buildah, la pousser avec Skopeo, l'exécuter avec Docker, puis la faire tourner dans Kubernetes sous containerd, sans aucune conversion ? Qu'est-ce qui pourrait malgré tout coincer (pense aux types de manifestes, aux plateformes, aux attestations) ?

12. Docker, Podman, containerd + `nerdctl`, CRI-O : pour chacun, un usage où il est le bon choix chez MédiSphère. Lequel tourne sur les nœuds Kubernetes au M14 (PLAN §4.10) ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions, schémas compris, avant d'ouvrir le corrigé.
- [ ] Tu as noté ton score sur 24 avec la grille du corrigé et les points à revoir.

<details><summary>Indice 1</summary>

Regarde à nouveau `ps -ef --forest` sur `ctr01` et `ctr02` (E03 étape 5, E06 étape 5) : qui est le parent de nginx sur chaque hôte, et qui est le parent de ce parent ?
</details>

<details><summary>Indice 2</summary>

Une spécification décrit un **format** ou une **interface**, pas un programme. Classe ce que tu as vu : un `index.json` et des blobs (E04), un `config.json` (que runc lit), une URL `/v2/…/manifests/…` (que Skopeo appelle).
</details>

**Pour aller plus loin** (facultatif) : M12-E44 (palier 4) te fera construire un conteneur à la main (`unshare`, `nsenter`, cgroup v2, `pivot_root`), puis lancer `runc run` sur un bundle fait d'une image extraite : garde tes schémas pour les comparer.
