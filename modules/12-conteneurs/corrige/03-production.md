# Module 12 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- **testé** sur Docker Engine 29.8.2 / Compose 5.5 (hors lab, sans AppArmor ni SELinux) : la pile durcie de E24 (`compose.yaml`, profil seccomp, PostgreSQL 18 et Valkey 8 sans capacité, script d'essais : 0 geste possible), la mise à jour progressive de E30 partie A (deux mises à jour sous charge, 915 et 1 475 requêtes, **zéro** erreur, image cassée détectée et retour arrière sans erreur), l'image et la recette de MédiAnnuaire (E34 : construction, sonde, lecture seule, arrêt propre en 0,7 s, code 0), `generer-seccomp.sh` ; constaté aussi sur 29.8.2 : un démon lancé avec `-H tcp://0.0.0.0:…` **sans** TLS démarre quand même, avec des avertissements de dépréciation et un ralentissement volontaire (E26) ; `userns-remap` désactive le stockage d'images containerd (« *userns remapping enabled, disabling containerd snapshotter* ») ; un processus non root lie le port 80 même avec `--cap-drop ALL` (Docker fixe `net.ipv4.ip_unprivileged_port_start=0`, E32 Q2) ;
- **non testé** : tout ce qui touche Podman 5.4/5.8, Quadlet, SELinux et udica (E25, E30 partie B), Debian 13 avec AppArmor (profil `docker-default` en plus de seccomp : un essai du script peut être bloqué par AppArmor plutôt que par seccomp), Docker sans privilège (E26), cAdvisor 0.60 avec le stockage containerd (E28), les noms exacts des métriques `engine_daemon_*` (E28), le rôle `sauvegarde_conteneurs` et les commandes PBS (même méthode qu'en M06-E28, non rejouée), les rôles Ansible de ce palier (pas d'`ansible-lint` ni de Molecule dans l'environnement de rédaction) ;
- **à vérifier sur ta version** : la sortie de `podman auto-update` lors d'un retour arrière (colonne `UPDATED` à `rolled back`), le type SELinux du port 8080 (`http_cache_port_t` sur la politique RHEL : `semanage port -l | grep 8080`), la présence d'`udica` dans les dépôts de Rocky 10 (AppStream), le fichier d'authentification persistant lu par Podman (`$XDG_CONFIG_HOME/containers/auth.json`), l'interface du gabarit `image.yml` de M12-E21 (noms du job caché et des variables, repris ici tels que décrits dans le corrigé de E21).

**Rappel** : aucune nouvelle VM dans ce palier. Fichiers de solution : `corrige/fichiers/M12-E24/` à `M12-E31/`, `M12-E33/`, `M12-E34/`. Le script d'essais d'évasion fourni à l'apprenant est [`ressources/E24-tests-evasion.py`](../ressources/E24-tests-evasion.py).

---

### M12-E24 — Durcir l'exécution : utilisateur, capacités, seccomp, lecture seule

**Solution**

Fichiers (projet `mediagenda/api`) : [`compose.yaml`](fichiers/M12-E24/mediagenda-api/compose.yaml) durci, [`securite/generer-seccomp.sh`](fichiers/M12-E24/mediagenda-api/securite/generer-seccomp.sh) et le profil produit [`securite/seccomp-mediagenda.json`](fichiers/M12-E24/mediagenda-api/securite/seccomp-mediagenda.json) (Docker 29.8.2). Documentation : [`docs/conteneurs/durcissement-execution.md`](fichiers/M12-E24/medisphere/docs/conteneurs/durcissement-execution.md) (sections E24, E25 et E26).

*1. État des lieux.* Sur la pile de E08 (image non root de E05) :

```
admin@ctr01:~$ docker inspect mediagenda-api-1 --format '{{.Config.User}} {{.HostConfig.CapAdd}} {{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}} {{.AppArmorProfile}} {{.HostConfig.ReadonlyRootfs}}'
10001:10001 [] [] [] docker-default false
admin@ctr01:~$ docker exec mediagenda-api-1 grep -E '^(Cap|NoNewPrivs|Seccomp)' /proc/1/status
CapInh: 0000000000000000
CapPrm: 0000000000000000
CapEff: 0000000000000000
CapBnd: 00000000a80425fb
CapAmb: 0000000000000000
NoNewPrivs:     0
Seccomp:        2
admin@ctr01:~$ capsh --decode=00000000a80425fb
0x00000000a80425fb=cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap
```

`SecurityOpt` vide ne veut **pas** dire « sans seccomp » : `Seccomp: 2` (mode filtre) montre que le profil par défaut est appliqué (`docker info` : `name=seccomp,profile=builtin`), comme AppArmor `docker-default` sur Debian. Les 14 capacités par défaut de Docker sont dans le jeu limite ; un processus **non root** ne les a pas en effectif (`CapEff` à 0), mais un binaire setuid root (il y en a neuf dans l'image : `su`, `passwd`, `mount`, `chsh`…) les retrouverait, faute de `no-new-privileges`. En root (`debian:trixie-slim` sans option), `CapEff` vaut `a80425fb` : les 14 sont effectives. Podman (sur `ctr02`, `containers.conf` par défaut) en donne 11 : il retire `MKNOD`, `NET_RAW` et `AUDIT_WRITE` (relève-les avec la même commande, `podman run --rm debian:trixie-slim grep Cap /proc/1/status`).

| Capacité par défaut | Ce qu'elle permet (en root dans le conteneur) |
|---|---|
| `CHOWN`, `FOWNER`, `FSETID`, `DAC_OVERRIDE` | changer les propriétaires, ignorer les droits des fichiers |
| `SETUID`, `SETGID`, `SETPCAP`, `SETFCAP` | changer d'identité, poser des capacités de fichier |
| `NET_BIND_SERVICE`, `NET_RAW` | ports < 1024 (inutile sous Docker, voir E32 Q2), paquets bruts (usurpation ARP sur le pont) |
| `MKNOD` | créer des fichiers de périphérique (leur ouverture reste filtrée par le cgroup des périphériques) |
| `KILL`, `SYS_CHROOT`, `AUDIT_WRITE` | signaux à tout processus du conteneur, `chroot`, messages d'audit |

*2. Essais avant durcissement.*

```
admin@ctr01:~$ docker exec -i mediagenda-api-1 python - < E24-tests-evasion.py
Utilisateur : uid=10001 gid=10001 ; NoNewPrivs=0 ; CapEff=0000000000000000 ; Seccomp=2
BLOQUÉ    1. déposer un binaire dans le système de fichiers Permission denied
…
POSSIBLE  7. tracer un processus (ptrace)              ptrace accepté (…)
POSSIBLE  10. exécuter un outil déposé dans /tmp       un outil téléchargé dans /tmp peut être exécuté
POSSIBLE  11. s'élever par un binaire setuid           9 binaire(s) setuid root utilisables : chfn chsh gpasswd mount newgrp passwd
Bilan : 8 bloqué(s), 3 possible(s), 0 inconnu(s)
admin@ctr01:~$ docker run --rm -i -u 0 python:3.13-slim-trixie python - < E24-tests-evasion.py   # root sans option
… 5 possible(s) : 1, 2, 3, 4, 7
```

L'utilisateur non root de E05 bloque déjà l'écriture dans les dossiers de l'image (ils appartiennent à root), `chown`, `setuid(0)` et `mknod` ; seccomp bloque `mount` et `unshare` (réservés à `CAP_SYS_ADMIN` dans le profil par défaut) ; `/proc/sysrq-trigger` est en lecture seule et `/dev/kmsg` absent. Restent : `ptrace` (autorisé par le profil par défaut depuis le noyau 4.8), l'exécution d'un outil déposé dans `/tmp` (inscriptible), et les binaires setuid.

*3 et 4. Capacités, privilèges, lecture seule.* Une ancre YAML `x-durci` porte `read_only: true`, `cap_drop: [ALL]`, `no-new-privileges:true` et `pids_limit`, fusionnée dans chaque service. Piège : `security_opt` redéfini dans un service **remplace** celui de l'ancre (les listes ne se fusionnent pas avec `<<`), d'où la répétition de `no-new-privileges` dans `api` et `migrations`. Emplacements inscriptibles trouvés en lisant les erreurs au démarrage : `/tmp` pour l'API (bibliothèques qui créent des fichiers temporaires) ; `/var/run/postgresql` (socket et verrou) et `/tmp` pour PostgreSQL ; rien pour Valkey (`--save ""`, aucun fichier). Les `tmpfs` sont bornés (`size=`), `noexec,nosuid,nodev` : un outil déposé dans `/tmp` ne s'exécute plus.

*5. PostgreSQL et Valkey.* Leur script d'entrée ne fait `chown`, `find … -exec chown` et le changement d'utilisateur (`gosu`, `setpriv`) que s'il tourne **en root** (`if [ "$(id -u)" = '0' ]`). Lancés directement sous leur UID (999 dans les deux images), ils sautent ces étapes et n'ont besoin d'**aucune** capacité :

```
admin@ctr01:~$ docker run --rm -v mediagenda_donnees-db:/v debian:trixie-slim ls -lan /v
drwxrwxrwt 3 999 999 4096 … .
drwx------ 19 999 999 4096 … 18
```

Un volume nommé créé par Docker recopie les droits du dossier de l'image au premier montage (ici `postgres:postgres`, 999) : la condition est remplie. Pour un volume créé autrement (dossier de l'hôte, autre outil), un `chown -R 999:999` préalable est nécessaire.

*6. Seccomp.* Le profil par défaut a `defaultAction: SCMP_ACT_ERRNO` (tout ce qui n'est pas autorisé échoue avec `EPERM`) et 33 règles en 29.8.2 : une grande liste autorisée sans condition, des règles par architecture, des règles conditionnées par une capacité (`includes.caps`, par exemple les 26 appels réservés à `CAP_SYS_ADMIN`), et une règle `{"names": ["process_vm_readv", "process_vm_writev", "ptrace"], "includes": {"minKernel": "4.8"}}`. C'est celle-ci que le script retire (`jq 'del(.syscalls[] | select((.includes.minKernel // "") == "4.8" and (.names | index("ptrace"))))'`) ; il vérifie qu'exactement une règle disparaît, sinon il échoue (structure changée dans une nouvelle version : à relire). La règle conditionnée par `CAP_SYS_PTRACE` reste, sans effet puisque la capacité est retirée.

```
admin@ctr01:~/src/mediagenda-api$ securite/generer-seccomp.sh
seccomp-mediagenda.json : profil par défaut de Docker 29.8.2, sans ptrace (33 → 32 règles).
```

Le fichier est **versionné** : à chaque montée de Docker, on relance le script et la MR montre le diff du profil amont.

*7. Preuve.*

```
admin@ctr01:~/src/mediagenda-api$ docker compose up -d --wait
admin@ctr01:~/src/mediagenda-api$ curl -s localhost:8000/pret
{"statut":"pret","postgresql":"ok","valkey":"ok"}
admin@ctr01:~$ docker exec -i mediagenda-api-1 python - < E24-tests-evasion.py
Utilisateur : uid=10001 gid=10001 ; NoNewPrivs=1 ; CapEff=0000000000000000 ; Seccomp=2
BLOQUÉ    1. déposer un binaire dans le système de fichiers Read-only file system
…
BLOQUÉ    7. tracer un processus (ptrace)              Operation not permitted
…
BLOQUÉ    10. exécuter un outil déposé dans /tmp       Permission denied
BLOQUÉ    11. s'élever par un binaire setuid           9 binaire(s) setuid neutralisé(s) par no-new-privileges
Bilan : 11 bloqué(s), 0 possible(s), 0 inconnu(s)
admin@ctr01:~$ docker exec mediagenda-api-1 grep -E '^Cap(Bnd|Eff)|NoNewPrivs' /proc/1/status
CapEff: 0000000000000000
CapBnd: 0000000000000000
NoNewPrivs:     1
```

Une création de rendez-vous par l'API (`POST /api/v1/rendez-vous`) rend 201 : l'application n'a besoin ni de `ptrace`, ni d'écrire ailleurs que dans `/tmp`.

*8. Podman.*

```
app@ctr02:~$ podman run -d --name essai-durci --read-only --tmpfs /tmp:size=16m,noexec,nosuid,nodev \
    --cap-drop all --security-opt no-new-privileges --security-opt seccomp=$HOME/seccomp-mediagenda.json \
    ctr01.par1.medisphere.internal:5000/mediagenda/api:<VERSION> sleep infinity
app@ctr02:~$ ps -o user,pid,cmd -C sleep
USER        PID CMD
534288   …     sleep infinity
```

L'UID 10001 du conteneur devient 524288 + 10001 − 1 = **534288** sur l'hôte (première plage subordonnée d'`app` : l'UID 0 du conteneur est `app` lui-même, 1001 ; les UID 1 à 65535 suivent la plage `524288:65536`). Sans privilège, les gestes 3 à 6 échouent **deux fois** : dans le conteneur (pas de capacité) et, même s'ils réussissaient, ils n'auraient de pouvoir que dans l'espace de noms utilisateur d'`app` (pas sur l'hôte). Le profil seccomp et `no-new-privileges` restent utiles : ils réduisent la surface du noyau, qui est **partagé** même sans privilège.

*9. Documentation* : voir le [modèle](fichiers/M12-E24/medisphere/docs/conteneurs/durcissement-execution.md). Capacités ajoutées : **aucune** pour les quatre services.

**Explications**

Le conteneur n'est pas une frontière de sécurité unique mais un empilement : espaces de noms (ce qu'on voit), cgroups (ce qu'on consomme), capacités (ce que root peut faire), seccomp (quels appels système existent), LSM (AppArmor, SELinux : quels objets on touche), système de fichiers (où l'on écrit). Chaque option de l'exercice retire une marche à l'attaquant : la plupart des évasions publiées enchaînent plusieurs gestes « innocents » (créer un espace de noms utilisateur pour récupérer des capacités, puis exploiter une faille noyau ; écrire un binaire puis l'exécuter ; s'élever par un setuid). `no-new-privileges` et `cap_drop: ALL` vident le jeu limite : plus aucun chemin, même un setuid, ne rend une capacité. La lecture seule empêche la persistance dans le conteneur et rend visible tout ce que l'application écrit (chaque `tmpfs` est une décision).

**Alternatives**
- Profil seccomp **minimal** généré à partir des appels observés (`oci-seccomp-bpf-hook`, `strace`) : plus strict, mais fragile (une bibliothèque mise à jour qui utilise un nouvel appel casse l'application en production) et propre à chaque application ; le profil par défaut moins `ptrace` est un bon compromis pour une équipe qui débute.
- Distroless ou `scratch` : retire les binaires setuid et le shell (un geste 11 sans objet, un geste 10 sans interpréteur) ; complémentaire, pas substituable (seccomp et capacités valent aussi pour l'application elle-même).
- Durcissement par le démon (`"no-new-privileges": true`, `"seccomp-profile"` dans `daemon.json`, E26) : s'applique à tout conteneur, même lancé à la main ; le `compose.yaml` reste la documentation exécutable de chaque application.

**Pièges classiques**
- Croire que `USER 10001` suffit : le jeu limite et les binaires setuid restent.
- `cap_add` « pour que ça marche » sans lire le script d'entrée (PostgreSQL démarre très bien sans capacité sous son UID).
- `security_opt` redéfini dans un service qui fait disparaître `no-new-privileges` hérité de l'ancre.
- `tmpfs` sans `size=` (la mémoire de l'hôte devient la limite) ou sans `noexec`.
- Profil seccomp copié d'un blog, d'une autre version de Docker, jamais régénéré.
- `--security-opt seccomp=unconfined` laissé après un dépannage.

**En production chez MédiSphère**
Ces options deviennent des **normes** (E33, `CNT-RUN-*`) contrôlées en CI (lecture du `compose.yaml`) et, au module 26, par des politiques d'admission Kubernetes (Pod Security *restricted* : non root, `allowPrivilegeEscalation: false`, capacités retirées, seccomp `RuntimeDefault`). Le profil seccomp personnalisé suivra en `Localhost`.

---

### M12-E25 — SELinux et conteneurs sur Rocky Linux

**Solution**

Fichiers (projet `plateforme/ansible`) : rôle [`selinux_conteneurs`](fichiers/M12-E25/ansible/roles/selinux_conteneurs/) (paquets, règles `semanage fcontext`, modules CIL), module [`legacy_rdv.cil`](fichiers/M12-E25/ansible/roles/selinux_conteneurs/files/legacy_rdv.cil), variables [`host_vars/ctr03/selinux_conteneurs.yml`](fichiers/M12-E25/ansible/inventories/lab/host_vars/ctr03/selinux_conteneurs.yml), [extrait de `playbooks/conteneurs.yml`](fichiers/M12-E25/ansible/playbooks/conteneurs.yml.extrait). Unité Quadlet du compte `app` : [`legacy-rdv.container`](fichiers/M12-E25/ctr03/legacy-rdv.container). Documentation : section SELinux de [`durcissement-execution.md`](fichiers/M12-E24/medisphere/docs/conteneurs/durcissement-execution.md).

Notation : `<IMAGE-LEGACY>` = `ctr01.par1.medisphere.internal:5000/legacy/legacy-rdv:2.3.1` (image de E19). Invites : `[app@ctr03 ~]$` dans une vraie session du compte (`sudo machinectl shell app@` depuis `admin`, M12-E06), `[admin@ctr03 ~]$` pour la politique et l'audit.

*1. Lecture.*

```
[app@ctr03 ~]$ podman run --rm docker.io/library/debian:trixie-slim cat /proc/self/attr/current
system_u:system_r:container_t:s0:c214,c871
[app@ctr03 ~]$ podman run --rm docker.io/library/debian:trixie-slim cat /proc/self/attr/current
system_u:system_r:container_t:s0:c45,c602
[app@ctr03 ~]$ podman run --rm --privileged docker.io/library/debian:trixie-slim cat /proc/self/attr/current
unconfined_u:system_r:spc_t:s0
```

Type `container_t` (domaine confiné des conteneurs), niveau `s0`, et **deux catégories MCS tirées au hasard** à chaque conteneur : deux conteneurs du même type ne peuvent pas lire les fichiers l'un de l'autre, même s'ils ont le même UID. `--privileged` donne `spc_t` (*super privileged container*), un domaine **non confiné** : SELinux ne protège plus rien, d'où la règle de Sophie.

*2. Refus et diagnostic.*

```
[admin@ctr03 ~]$ sudo install -d -o app -g app -m 0750 /srv/legacy-rdv/uploads
[app@ctr03 ~]$ podman run -d --name essai --userns keep-id:uid=33,gid=33 -v /srv/legacy-rdv/uploads:/var/www/legacy-rdv/uploads <IMAGE-LEGACY>
[app@ctr03 ~]$ podman exec essai touch /var/www/legacy-rdv/uploads/t
touch: cannot touch '/var/www/legacy-rdv/uploads/t': Permission denied
[admin@ctr03 ~]$ sudo ausearch -m AVC -ts recent | audit2why
type=AVC msg=audit(…): avc:  denied  { write } for  pid=… comm="touch" name="uploads" dev="dm-0" ino=…
   scontext=system_u:system_r:container_t:s0:c214,c871 tcontext=unconfined_u:object_r:var_t:s0 tclass=dir permissive=0
        Was caused by:
                Missing type enforcement (TE) allow rule.
```

Source `container_t` (avec les catégories du conteneur), cible `var_t` (étiquette par défaut de `/srv`), classe `dir`, permission `write`. Les droits Unix étaient bons (le dossier appartient à `app`, qui est root dans le conteneur) : c'est SELinux qui refuse. Apache écrit sous `www-data` (UID 33 du conteneur, image de E19) : il faut **aussi** que les droits Unix suivent. Ici, `--userns keep-id:uid=33,gid=33` fait de `app` l'UID 33 du conteneur (les fichiers écrits appartiennent à `app` sur l'hôte) ; l'alternative est `podman unshare chown 33:33 /srv/legacy-rdv/uploads` (le dossier appartient alors à 524320 sur l'hôte, M12-E06).

*3. `:z` et `:Z`.*

```
[app@ctr03 ~]$ podman run … -v /srv/legacy-rdv/uploads:/var/www/legacy-rdv/uploads:Z …
[app@ctr03 ~]$ ls -Zd /srv/legacy-rdv/uploads
system_u:object_r:container_file_t:s0:c214,c871 /srv/legacy-rdv/uploads
[app@ctr03 ~]$ podman run … -v /srv/legacy-rdv/uploads:/var/www/legacy-rdv/uploads:z …
[app@ctr03 ~]$ ls -Zd /srv/legacy-rdv/uploads
system_u:object_r:container_file_t:s0 /srv/legacy-rdv/uploads
[admin@ctr03 ~]$ sudo restorecon -Rv /srv/legacy-rdv
Relabeled /srv/legacy-rdv/uploads from system_u:object_r:container_file_t:s0 to unconfined_u:object_r:var_t:s0
```

`:Z` réétiquette le dossier **et tout son contenu** en `container_file_t` avec les catégories **du** conteneur : un second conteneur (autres catégories) est refusé ; s'il est lui aussi lancé avec `:Z`, il réétiquette à ses catégories et c'est le **premier** qui perd l'accès. `:z` pose `container_file_t:s0` sans catégorie : partagé par tous les conteneurs. Dans les deux cas, l'étiquette est posée **sur l'hôte** par Podman, hors de la politique : le premier `restorecon` (une mise à jour de paquet, un `fixfiles`, un audit) la remet à `var_t` et l'application casse. Et `:Z` sur `/home/app` réétiquetterait tout le dossier personnel (`.ssh` compris) : `sshd` refuserait les clés.

*4. Étiquette durable.* Règle locale de la politique, par le rôle :

```
[admin@ctr03 ~]$ sudo semanage fcontext -a -t container_file_t '/srv/legacy-rdv/uploads(/.*)?'
[admin@ctr03 ~]$ sudo restorecon -Rv /srv/legacy-rdv/uploads
[admin@ctr03 ~]$ matchpathcon /srv/legacy-rdv/uploads
/srv/legacy-rdv/uploads	system_u:object_r:container_file_t:s0
```

Dans le rôle, la règle est posée par `community.general.sefcontext` puis `restorecon` (lancé seulement si la règle a changé). Elle survit à `restorecon` (c'est la politique qui la porte), se lit dans `semanage fcontext -l -C` (règles locales) et se versionne. Ce qu'elle autorise : **tout** processus de type conteneur (`container_t` et dérivés, quelles que soient leurs catégories) peut lire et écrire ce dossier. C'est le comportement de `:z`, assumé et documenté ; pour réserver le dossier à un seul conteneur, il faudrait une catégorie fixe (`label=level:s0:c100,c200` sur le conteneur, et la même dans la règle `fcontext`, option `-r s0:c100,c200`).

*5. Le dépôt d'InfoGér et udica.* `/home/app/depot-infoger` est `user_home_t` ; `container_t` n'a aucun droit dessus. Le réétiqueter casserait l'accès SFTP (le domaine de `sshd`/`sftp` attend `user_home_t` dans les dossiers personnels) et irait contre la règle 2 de Sophie. udica produit un type dédié qui **ajoute** à `container_t` les seuls droits nécessaires :

```
[app@ctr03 ~]$ podman run -d --name legacy-rdv -p 8080:8080 --cap-drop all --security-opt no-new-privileges --userns keep-id:uid=33,gid=33 \
    -v /srv/legacy-rdv/uploads:/var/www/legacy-rdv/uploads -v /home/app/depot-infoger:/import:ro <IMAGE-LEGACY>
[app@ctr03 ~]$ podman inspect legacy-rdv > /tmp/legacy-rdv.json
[admin@ctr03 ~]$ cd /tmp && sudo udica -j /tmp/legacy-rdv.json legacy_rdv
Policy legacy_rdv created!
Please load these modules using:
# semodule -i legacy_rdv.cil /usr/share/udica/templates/{base_container.cil,net_container.cil}
Restart the container with: "--security-opt label=type:legacy_rdv.process" parameter
```

Le fichier produit ([`legacy_rdv.cil`](fichiers/M12-E25/ansible/roles/selinux_conteneurs/files/legacy_rdv.cil)) se lit ligne à ligne : `blockinherit container` (tous les droits de `container_t`), `restricted_net_container` (réseau limité aux ports publiés), les capacités effectives du conteneur (aucune ici : Apache tourne déjà sous `www-data` sur 8080 et le conteneur a `--cap-drop all`, donc pas de ligne `capability`), `name_bind` sur le type du port 8080 de l'hôte, lecture-écriture sur `container_file_t` (le dossier des pièces jointes), **lecture seule** sur `user_home_t` (le dépôt, monté `:ro`). Après chargement et relance avec `--security-opt label=type:legacy_rdv.process` :

```
[app@ctr03 ~]$ podman exec legacy-rdv ls /import            # lecture : OK
[app@ctr03 ~]$ podman exec legacy-rdv touch /import/x       # refusé (montage :ro ET politique en lecture seule)
[admin@ctr03 ~]$ sudo ausearch -m AVC -ts recent --context legacy_rdv.process
<no matches>
```

*6. Par le code.* Le rôle installe `udica`, `policycoreutils-python-utils` (`semanage`) et `setools-console` (`sesearch`), pose les règles `fcontext`, crée les dossiers, copie chaque module CIL dans `/etc/selinux/medisphere/` et ne le charge que si son contenu a changé (`semodule -i` avec les modèles d'udica). L'unité Quadlet porte `SecurityLabelType=legacy_rdv.process` ; elle ne contient **ni** `SecurityLabelDisable=` **ni** de `:z`/`:Z`.

```
[app@ctr03 ~]$ systemctl --user daemon-reload && systemctl --user restart legacy-rdv.service
[app@ctr03 ~]$ podman inspect legacy-rdv --format '{{.ProcessLabel}}'
system_u:system_r:legacy_rdv.process:s0:c512,c903
```

Note : le module CIL a été généré **sur `ctr03`**, à partir du conteneur réel ; il est ensuite **versionné** (le rôle le déploie, il ne le régénère pas). Un changement de montage ou de port de l'unité impose de le régénérer et de faire une MR.

**Explications**

SELinux ajoute une couche que ni les capacités ni seccomp ne fournissent : un contrôle d'accès **obligatoire** sur chaque objet (fichier, port, socket), qui s'applique même à root. Pour les conteneurs, la politique `container-selinux` combine le *type enforcement* (un conteneur est `container_t`, il n'accède qu'à `container_file_t` et à quelques types en lecture) et le MCS (les catégories séparent les conteneurs entre eux). Une évasion du système de fichiers (montage, lien, faille d'un runtime) aboutit dans un processus `container_t` qui ne peut rien faire des fichiers de l'hôte. C'est pourquoi `label=disable` et `--privileged` sont si graves : ils retirent précisément ce filet. udica ne relâche pas la politique : il compose des briques auditées pour un conteneur donné, dans un module séparé, versionné, révocable (`semodule -r legacy_rdv`).

**Alternatives**
- `:z` partout : simple, mais l'étiquette vit hors de la politique (perdue au premier `restorecon`) et Podman réétiquette à chaque démarrage (lent sur de gros volumes) ; acceptable pour un dossier **dédié** et temporaire.
- Booléens de `container-selinux` (`container_use_cephfs`, `container_read_certs`…) quand le besoin correspond à un booléen existant : moins spécifique qu'udica, mais sans module à maintenir. Lis `getsebool -a | grep container`.
- Module écrit à la main (`audit2allow -M`) à partir des refus : à proscrire sans relecture (il autorise **tout** ce qui a été refusé, y compris ce qui devait l'être).
- Volume nommé de Podman au lieu d'un dossier de l'hôte : étiqueté par Podman dans son stockage, aucun problème SELinux ; mais les pièces jointes migrées et l'outillage de l'hôte (sauvegarde) les veulent dans un chemin connu.

**Pièges classiques**
- `setenforce 0` « pour tester », oublié (vérifie `getenforce` en fin de session).
- `:Z` sur un dossier personnel ou système : `sshd`, `dnf` ou la connexion cassent ; `restorecon -RFv` répare.
- Deux conteneurs `:Z` sur le même dossier : le dernier démarré gagne, l'autre perd l'accès en cours de route.
- Chercher le refus dans le journal de l'application : il est dans `/var/log/audit/audit.log` (`ausearch`), et certains refus sont masqués par des règles `dontaudit` (`semodule -DB` les affiche temporairement, `semodule -B` les remet).
- Générer la politique udica à partir d'un conteneur lancé **en root** alors qu'il tournera sans privilège (montages, ports et capacités diffèrent).
- Oublier les droits Unix : SELinux ne remplace pas un `chown` correct dans l'espace de noms utilisateur.

**En production chez MédiSphère**
Les hôtes de la famille RHEL restent *enforcing* (contrôle de `getenforce` dans la sonde de l'hôte, M21) ; les modules de politique par application sont versionnés et relus par Sophie ; au module 26, la même logique s'applique aux nœuds Kubernetes (étiquettes SELinux des pods, `seLinuxOptions`). Sur Debian, AppArmor joue ce rôle (moins fin sur les fichiers, sans MCS).

---

### M12-E26 — Durcir le moteur : socket, *userns-remap*, Docker sans privilège

**Solution**

Fichiers (projet `plateforme/ansible`) : [`group_vars/role_docker/docker_engine.yml`](fichiers/M12-E26/ansible/inventories/lab/group_vars/role_docker/docker_engine.yml.extrait) (options du démon), rôle [`audit_conteneurs`](fichiers/M12-E26/ansible/roles/audit_conteneurs/) (règles `auditd`), [extrait de `playbooks/conteneurs.yml`](fichiers/M12-E26/ansible/playbooks/conteneurs.yml.extrait). Documentation : section « Moteur » de [`durcissement-execution.md`](fichiers/M12-E24/medisphere/docs/conteneurs/durcissement-execution.md).

*1. Le groupe `docker`.*

```
admin@ctr01:~$ sudo useradd -m -s /bin/bash demo-docker && sudo usermod -aG docker demo-docker
admin@ctr01:~$ sudo -iu demo-docker
demo-docker@ctr01:~$ docker run --rm -it -v /:/hote debian:trixie-slim chroot /hote /bin/bash
root@<id>:/# id ; head -2 /etc/shadow
uid=0(root) gid=0(root) groups=0(root)
root:*:…
root@<id>:/# exit
admin@ctr01:~$ sudo userdel -r demo-docker
```

Le démon tourne en root et exécute ce qu'on lui demande : monter `/` de l'hôte, donner `--privileged`, `--pid host`… Le groupe propriétaire du socket ne protège que **l'accès au socket**, pas ce qu'on en fait. Règle retenue : le groupe `docker` ne contient **que des comptes qui ont déjà `sudo` sans mot de passe** (`admin`, variable `docker_engine_groupe_docker` de M12-E02) et, sur `runner02`, le compte du runner (`gitlab-runner`), qui en a besoin pour l'exécuteur `docker`. Ce qu'`admin` y gagne : rien qu'il n'ait déjà… sauf qu'une action par le socket ne laisse **pas de trace `sudo`** (`journalctl _COMM=sudo`) : d'où l'audit de l'étape 6. Comptes de service, de supervision, de développeurs : jamais (voir E32 Q6).

```
admin@ctr01:~$ getent group docker
docker:x:989:admin
```

*2. Le socket.*

```
admin@ctr01:~$ sudo ss -lntpx | grep -E 'docker|containerd'
u_str LISTEN 0 4096 /run/docker.sock …  users:(("dockerd",pid=…))
u_str LISTEN 0 4096 /run/containerd/containerd.sock … users:(("containerd",pid=…))
admin@ctr01:~$ ls -l /run/docker.sock
srw-rw---- 1 root docker 0 … /run/docker.sock
```

Aucun port TCP. Les deux façons sûres d'administrer un démon à distance : **SSH** (`DOCKER_HOST=ssh://admin@ctr01.par1.medisphere.internal` ou `docker context create … --docker host=ssh://…` : on hérite de l'authentification et de la traçabilité de SSH, sans port supplémentaire) et **TLS mutuel** (`--tlsverify`, certificats client et serveur, CA dédiée). Comportement de Docker 29.8.2 avec `-H tcp://0.0.0.0:2375` **sans** TLS, constaté hors lab : le démon **démarre** quand même, en journalisant « *Binding to IP address without --tlsverify is insecure and gives root access on this machine to everyone who has access to your network* », « *[DEPRECATION NOTICE] In future versions this will be a hard failure* » et en **ralentissant volontairement** son démarrage ; avec `--tls=false` explicite, il démarre aussi (avertissements seulement). La documentation des fonctionnalités dépréciées annonce un refus (retrait prévu en 28.0, échec avec `--tls=false` dès 27.0) que la 29.8.2 n'applique pas encore : **ne te fie pas à la version pour te protéger**, la règle est « jamais de TCP ». Dans le lab, l'accès distant de la CI au démon est celui de `runner02` : le runner parle au démon **local** par le socket, et les jobs ne reçoivent **pas** le socket (pas de `/var/run/docker.sock` dans `volumes` de `config.toml`, E20/E21) ; c'est ce qui rend l'exécuteur `docker` acceptable.

*3. Options du démon* ([extrait](fichiers/M12-E26/ansible/inventories/lab/group_vars/role_docker/docker_engine.yml.extrait)) : `live-restore: true`, `icc: false`, `no-new-privileges: true`, journaux de E18 conservés (fusion récursive du rôle : seule `docker_engine_daemon_extra` change). Après application par le rôle (validation `dockerd --validate`, redémarrage par le gestionnaire) :

```
admin@ctr01:~$ docker info --format '{{.LiveRestoreEnabled}}'
true
admin@ctr01:~$ docker ps --format '{{.Names}} {{.Status}}' ; sudo systemctl restart docker ; docker ps --format '{{.Names}} {{.Status}}'
mediagenda-api-1 Up 2 hours (healthy)
…
mediagenda-api-1 Up 2 hours (healthy)          # même durée : les conteneurs n'ont pas redémarré
admin@ctr01:~$ docker network inspect bridge --format '{{index .Options "com.docker.network.bridge.enable_icc"}}'
false
admin@ctr01:~$ docker network inspect mediagenda_arriere --format '{{index .Options "com.docker.network.bridge.enable_icc"}}'

admin@ctr01:~$ docker run --rm debian:trixie-slim grep NoNewPrivs /proc/self/status
NoNewPrivs:	1
```

`live-restore` : les conteneurs survivent au redémarrage du démon (containerd et les *shims* continuent) ; pendant l'arrêt, ce qui passe **par** le démon s'interrompt : proxy de ports en espace utilisateur (`docker-proxy`, si la règle de pare-feu ne suffit pas, cas des connexions depuis l'hôte lui-même), collecte des journaux (le tampon du pilote peut saturer et bloquer un conteneur très bavard), sondes de santé et politiques de redémarrage. `icc: false` n'agit que sur le réseau `bridge` **par défaut** : les réseaux de Compose (option vide, donc communication autorisée) n'en héritent pas — l'isolement de la pile vient de son découpage en réseaux (`avant`, `arriere` en `internal`, E08). `no-new-privileges` par défaut vaut pour tout conteneur, même lancé à la main ; une image qui **exige** setuid (rare : `sudo` dans un conteneur, à proscrire) devrait l'annuler explicitement (`--security-opt no-new-privileges=false`), ce qui se voit en revue.

*4. `userns-remap`.*

```
admin@ctr01:~$ sudo jq '. + {"userns-remap": "default"}' /etc/docker/daemon.json | sudo tee /etc/docker/daemon.json.essai >/dev/null
admin@ctr01:~$ sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.avant && sudo mv /etc/docker/daemon.json.essai /etc/docker/daemon.json
admin@ctr01:~$ sudo systemctl restart docker && journalctl -u docker -n 50 | grep -i -E 'userns|snapshotter'
… level=info msg="User namespaces: ID ranges will be mapped to subuid/subgid ranges of: dockremap"
… level=warning msg="userns remapping enabled, disabling containerd snapshotter"
admin@ctr01:~$ docker images ; docker ps -a ; docker volume ls         # tout est vide
admin@ctr01:~$ sudo ls /var/lib/docker
100000.100000  …
admin@ctr01:~$ docker run -d --name essai debian:trixie-slim sleep 600 && ps -o user,pid,cmd -C sleep
USER        PID CMD
100000      …   sleep 600
admin@ctr01:~$ docker run --rm --network host debian:trixie-slim true
docker: Error response from daemon: … cannot share the host's network namespace when user namespaces are enabled
admin@ctr01:~$ docker rm -f essai ; sudo mv /etc/docker/daemon.json.avant /etc/docker/daemon.json && sudo systemctl restart docker
admin@ctr01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://ctr01.par1.medisphere.internal:5000/v2/
401
```

Le compte `dockremap` et sa plage (`/etc/subuid`) sont créés par le démon ; tout est rangé dans `/var/lib/docker/100000.100000/` (images, conteneurs, volumes **séparés** : le registre et la pile ont « disparu ») et Docker 29 **désactive le stockage d'images containerd** : retour aux pilotes de stockage hérités, sans images multi-plateformes ni attestations locales (E12). Le « root » d'un conteneur est l'UID 100000 de l'hôte. `--network host`, `--pid host`, `--userns host` explicite (à refuser) et les volumes de l'hôte demandent des droits ajustés (les fichiers créés appartiennent à 100000+). Le message d'erreur de `--network host` peut différer selon la version : l'important est le refus. Décision : **pas** sur `ctr01` (registre et piles existants, stockage containerd utilisé par E12) ; **pas** sur `runner02` non plus dans ce module (BuildKit sans privilège dans un job crée ses propres espaces de noms utilisateur, E21 : l'imbrication est à valider avant) ; la protection équivalente vient de Podman sans privilège sur les serveurs applicatifs (ADR-0120). Réévaluation au M19 (CI sur Kubernetes).

*5. Docker sans privilège* (page *Rootless mode*) : paquet `docker-ce-rootless-extras` (déjà épinglé par le rôle), `uidmap` et `dbus-user-session`, plage subordonnée pour le compte, puis sous `essai-rootless` : `dockerd-rootless-setuptool.sh install`, `export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock`, `systemctl --user start docker`. Comparaison relevée :

| Critère | Docker root | Docker sans privilège | Podman sans privilège |
|---|---|---|---|
| Démon | `dockerd` root permanent | `dockerd` de l'utilisateur (RootlessKit) | aucun (conmon par conteneur) |
| Réseau, ports | pont + nftables/iptables, tout port | RootlessKit (slirp4netns ou pasta), ports < 1024 interdits sauf `ip_unprivileged_port_start` | pasta, ports < 1024 interdits sauf réglage |
| Limites (cgroups) | toutes | seulement si systemd délègue les contrôleurs au compte (`Delegate=`) | idem |
| Stockage | containerd (snapshotter) | overlayfs sans privilège | overlay sans privilège (`fuse-overlayfs` en repli) |
| systemd | service système | `systemctl --user` + *linger* | Quadlet (unités générées) |
| Effort | faible | moyen (variables, socket par utilisateur, outils tiers à reconfigurer) | moyen (mais outillé : Quadlet, `auto-update`) |

Désinstallation : `dockerd-rootless-setuptool.sh uninstall`, `rootlesskit rm -rf ~/.local/share/docker`, puis `sudo userdel -r essai-rootless`.

*6. Audit* (rôle [`audit_conteneurs`](fichiers/M12-E26/ansible/roles/audit_conteneurs/)) : `auditd` + `audispd-plugins`, fichier `/etc/audit/rules.d/50-docker.rules` (surveillance `-p wa` de `/etc/docker`, `/etc/containerd`, `/etc/default/docker`, des unités `docker.service`/`docker.socket`/`containerd.service`, `-p wax` sur `/usr/bin/dockerd`, `/usr/bin/containerd`, `/usr/bin/runc`, `/usr/bin/containerd-shim-runc-v2` ; `-p x` sur `/usr/bin/docker`, clé `docker-cli`), chargé par `augenrules --load`.

```
admin@ctr01:~$ sudo touch /etc/docker/daemon.json
admin@ctr01:~$ sudo ausearch -k docker -i -ts recent | grep -E 'type=SYSCALL' | head -1
type=SYSCALL … comm=touch exe=/usr/bin/touch … auid=admin uid=root … key=docker
admin@ctr01:~$ docker ps >/dev/null ; sudo ausearch -k docker-cli -i -ts recent | grep -c 'exe=/usr/bin/docker'
1
```

L'`auid` (identifiant de connexion) **survit à `sudo`** : il désigne l'humain. Une règle sur `/run/docker.sock` ne trace que les accès au **fichier** (création, changement de droits) : se connecter à un socket Unix (`connect()`) n'est pas une ouverture de fichier, et un appel d'API passe donc inaperçu. Les appels à l'API se retrouvent dans les **événements** du démon (`docker events`), dans son journal en mode `debug` (bavard) ou par un plugin d'autorisation ; la règle `docker-cli` trace qui **lance** le client, ce qui couvre l'usage humain normal.

**Explications**

Le démon Docker est un service root qui obéit à quiconque parle à son socket : son durcissement consiste d'abord à **réduire qui peut lui parler** (groupe, jamais de TCP, pas de socket monté dans un conteneur), puis à changer ses **valeurs par défaut** (`no-new-privileges`, `icc`), et enfin à **tracer**. `userns-remap` et le mode sans privilège attaquent le problème à la racine (le root du conteneur n'est plus root) mais coûtent cher en compatibilité, surtout avec Docker 29 : c'est l'argument central de l'ADR-0120 en faveur de Podman sur les serveurs, où l'absence de privilège est le fonctionnement **normal** et non une option.

**Alternatives**
- Plugin d'autorisation (`authorization-plugins`) qui filtre les appels (refuser `--privileged`, les montages de `/`) : puissant mais un composant critique de plus.
- Socket exposé par un mandataire filtrant (`docker-socket-proxy`) pour les outils qui « ont besoin » du socket (supervision, Traefik) : n'expose que des chemins en lecture.
- TLS mutuel pour l'administration distante : utile entre machines qui n'ont pas SSH ; dans le lab, SSH suffit.

**Pièges classiques**
- Ajouter un compte de service au groupe `docker` « pour lire `docker ps` ».
- Monter `/var/run/docker.sock` dans un conteneur (supervision, CI « Docker-in-Docker par le socket ») : ce conteneur est root sur l'hôte.
- Croire qu'`icc: false` isole les réseaux de Compose.
- Activer `userns-remap` sur un hôte qui porte des données sans prévoir que tout « disparaît » (et que les volumes existants ne sont plus vus).
- Règle `auditd` sur le socket en pensant tracer les appels d'API.

**En production chez MédiSphère**
Règles d'audit envoyées vers la plateforme de journaux (M22) avec une alerte sur toute modification de `/etc/docker` hors MR ; contrôle CIS automatisé (`docker-bench-security` en CI de `plateforme/ansible`, M26) ; `runner02` remplacé à terme par des exécuteurs Kubernetes (M19) où aucun démon n'est partagé entre jobs.

---
