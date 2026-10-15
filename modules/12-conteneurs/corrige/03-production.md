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

Fichiers (projet `mediagenda/api`) : [`compose.yaml`](fichiers/M12-E24/mediagenda-api/compose.yaml) durci (celui de E18, limites et image 0.2.0 comprises, plus les blocs « Durcissement »), [`securite/generer-seccomp.sh`](fichiers/M12-E24/mediagenda-api/securite/generer-seccomp.sh) et le profil produit [`securite/seccomp-mediagenda.json`](fichiers/M12-E24/mediagenda-api/securite/seccomp-mediagenda.json) (Docker 29.8.2). Documentation : [`docs/conteneurs/durcissement-execution.md`](fichiers/M12-E24/medisphere/docs/conteneurs/durcissement-execution.md) (sections E24, E25 et E26).

*1. État des lieux.* Sur la pile telle que la laisse E18 (`compose.yaml` de E08 avec les limites de E18, image non root 0.2.0 de E11) :

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

Le démon tourne en root et exécute ce qu'on lui demande : monter `/` de l'hôte, donner `--privileged`, `--pid host`… Le groupe propriétaire du socket ne protège que **l'accès au socket**, pas ce qu'on en fait. Règle retenue : le groupe `docker` ne contient **que des comptes qui ont déjà `sudo` sans mot de passe** (`admin`, variable `docker_engine_groupe_docker` de M12-E02) ; sur `runner02`, **personne** (M12-E20 : le service `gitlab-runner` tourne en root et parle seul au démon, le compte `gitlab-runner` reste hors du groupe, les humains passent par `sudo`). Ce qu'`admin` y gagne : rien qu'il n'ait déjà… sauf qu'une action par le socket ne laisse **pas de trace `sudo`** (`journalctl _COMM=sudo`) : d'où l'audit de l'étape 6. Comptes de service, de supervision, de développeurs : jamais (voir E32 Q6).

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

### M12-E27 — Politique des images de base de MédiSphère

**Solution**

Fichiers : projet `plateforme/images-base` — [`debian/Dockerfile`](fichiers/M12-E27/images-base/debian/Dockerfile), [`python/Dockerfile`](fichiers/M12-E27/images-base/python/Dockerfile), [`php-apache/Dockerfile`](fichiers/M12-E27/images-base/php-apache/Dockerfile), [`images-autorisees.txt`](fichiers/M12-E27/images-base/images-autorisees.txt), [`outils/verifier-from.sh`](fichiers/M12-E27/images-base/outils/verifier-from.sh), [`.gitlab-ci.yml`](fichiers/M12-E27/images-base/.gitlab-ci.yml), [`pki/`](fichiers/M12-E27/images-base/pki/LISEZMOI.md) ; projet `plateforme/ci-templates` — [`templates/images-autorisees.yml`](fichiers/M12-E27/ci-templates/templates/images-autorisees.yml) ; [extrait du `.gitlab-ci.yml` de `mediagenda/api`](fichiers/M12-E27/mediagenda-api/gitlab-ci.yml.extrait) ; documentation [`images-de-base.md`](fichiers/M12-E27/medisphere/docs/conteneurs/images-de-base.md).

Conception retenue (une solution parmi d'autres, défendable) :
- **Trois images** : `bibliotheque/debian`, `bibliotheque/python` (MédiAgenda, MédiNotif, MédiAnnuaire) et `bibliotheque/php-apache` (Legacy-RDV). Pas de `bibliotheque/golang` : la chaîne de compilation Go ne part pas en production (étape de construction, autorisée par empreinte), et l'image finale de MédiDoc est *distroless* (pas de paquets à corriger chaque semaine : on suit l'amont par MR).
- **Épinglage + reconstruction** : `ARG AMONT=…@sha256:…` (empreintes de l'index amont relevées le 2026-10-08), `apt-get upgrade` à chaque construction ; l'empreinte amont change par MR (Renovate au M13). Hadolint signale `apt-get upgrade` (DL3005) et l'absence de version des paquets (DL3008) : dérogations écrites **sur la ligne**, avec la raison (c'est l'objet même de l'image). Les trois Dockerfiles passent Hadolint 2.15.1 avec le `.hadolint.yaml` de E16 (vérifié).
- **Étiquettes** : `trixie-AAAAMMJJ` immuable **par convention** (le gabarit de E21 ne refuse que `latest`, et `registry:3` accepte qu'on repousse une étiquette : c'est une limite écrite dans la politique, levée au M13 par l'immuabilité des étiquettes de Harbor ; un job qui interroge le registre avant de pousser est une amélioration possible), `trixie` mobile ; la date est calculée **une fois par pipeline** (job `date`, artefact *dotenv*) pour que les trois images aient la même.
- **Traçabilité** : `org.opencontainers.image.base.name` contient l'amont **avec** son empreinte, `revision` le commit, `created` la date ; les applications référencent `…/bibliotheque/python:3.13-trixie-AAAAMMJJ@sha256:…` et posent à leur tour `base.name`.
- **Utilisateur** : les images du catalogue restent en root (`USER 0` explicite, dérogation DL3002 écrite ; Hadolint 2.15 exige un UID numérique, DL3066) : ce sont des bases de construction, les applications installent des paquets avant de fixer leur UID ; l'exigence « non root » porte sur l'image **finale** (`CNT-IMG-05`, contrôlée par Hadolint dans chaque application).
- **Multi-architectures** : `PLATEFORMES=linux/amd64,linux/arm64` passé au gabarit ; il faut l'émulation (binfmt) sur `runner02`, comme sur `ctr01` en E12 ; sans elle, retire arm64 et écris-le (exception datée).
- **Liste des images autorisées** : fichier texte (un motif *glob* par ligne et la consigne à afficher), lu par `verifier-from.sh`, qui résout les `ARG` (valeurs par défaut et `--build-arg` passés au job), ignore les étapes nommées et `scratch`, et vérifie aussi `COPY --from=` et `RUN --mount=…,from=` quand ils désignent une image. Résultats sur les solutions du module (vérifiés) : le Dockerfile de E05 (`FROM docker.io/library/python:3.13-slim-trixie`) est **refusé** ; celui de MédiAnnuaire (E34) passe ; celui de MédiDoc (E10, `golang:1.26-trixie` sans registre ni empreinte) est refusé : sa mise en conformité fait partie du mini-projet (E46).
- **Partage de la liste** : le job du gabarit lit la liste et le script dans `plateforme/images-base` avec le **jeton du job** (`CI_JOB_TOKEN`) : ajoute les groupes consommateurs à la liste d'autorisation du jeton (*Settings > CI/CD > Job token permissions*) de `plateforme/images-base`. Alternative sans jeton : copier la liste dans `plateforme/ci-templates` à chaque version (mais deux sources de vérité).
- **Pipeline planifié** : *Build > Pipeline schedules*, « hebdomadaire », `0 4 * * 1`, fuseau Europe/Paris, branche `main`, propriétaire un compte de service (pas une personne qui peut partir). Démonstration du refus : branche `essai-from-interdit` sur `mediagenda/api`, MR ouverte, job `images-autorisees` rouge, MR fermée.

Vérifier une image publiée :

```
admin@adm01:~$ skopeo inspect --creds plateforme:<MDP> docker://ctr01.par1.medisphere.internal:5000/bibliotheque/debian:trixie \
    | jq '.Labels | with_entries(select(.key | startswith("org.opencontainers.image")))'
admin@adm01:~$ skopeo list-tags --creds plateforme:<MDP> docker://ctr01.par1.medisphere.internal:5000/bibliotheque/debian
```

**Explications**

Épingler et corriger ne s'opposent pas si l'on sépare les deux rythmes : l'**amont** bouge rarement et par MR (on sait quand et pourquoi), la **couche de correctifs** bouge chaque semaine automatiquement (on reçoit les correctifs sans rien faire), et chaque résultat est **figé** sous une étiquette datée (on peut reconstruire ou revenir exactement à l'image d'une date). Les applications choisissent leur compromis : étiquette datée (reproductible, MR pour suivre) ou étiquette mobile en recette (correctifs sans MR, non reproductible). La liste des images autorisées transforme la politique en contrôle : sans elle, la politique n'existe que dans un document.

**Alternatives**
- Reconstruction **reproductible** des correctifs à partir d'un instantané daté de l'archive Debian (`snapshot.debian.org`) : même entrée, mêmes octets ; plus de travail.
- Tout en *distroless* (ou `apko`/Wolfi) : moins de paquets, moins de failles, mais pas de shell pour dépanner et une chaîne d'outils de plus.
- Une seule image de base par langage, sans Debian générique : moins d'images, mais les outils de CI perdent leur base commune.
- Liste en YAML lue par `yq` : plus riche (exceptions datées en champs), au prix d'un outil de plus dans le job.

**Pièges classiques**
- Épingler l'empreinte d'un **manifeste de plateforme** (amd64) au lieu de l'**index** : l'image n'existe plus pour arm64.
- Étiquette datée repoussée par un second pipeline le même jour : l'« immuable » ne l'est plus.
- Contrôle qui ne regarde que le premier `FROM`, ou qui ne résout pas les `ARG` (un `FROM ${BASE}` passe toujours).
- Pipeline planifié appartenant à un humain (il s'arrête quand le compte est bloqué), ou qui échoue en silence (aucune notification).
- Mettre dans l'image de base des outils « utiles » (curl, vim, jq) : toutes les applications en héritent, et leurs failles aussi.

**En production chez MédiSphère**
Au M13 : projet Harbor `bibliotheque` (immuabilité, analyse Trivy, signature Cosign), Renovate qui propose les MR d'empreinte amont et celles des applications vers la nouvelle étiquette datée ; tableau de bord « âge des images de base » par application (M21) ; au M26, admission Kubernetes qui n'accepte que des images signées dont la base est dans le catalogue.

---

### M12-E28 — Superviser les conteneurs

**Solution**

Fichiers (projet `plateforme/outils`) : [`bin/ms-verif-conteneurs`](fichiers/M12-E28/outils/bin/ms-verif-conteneurs), [`etc/ms-verif-conteneurs.conf`](fichiers/M12-E28/outils/etc/ms-verif-conteneurs.conf), tests [`tests/bats/ms-verif-conteneurs.bats`](fichiers/M12-E28/outils/tests/bats/ms-verif-conteneurs.bats) (17 tests, sans réseau, tous verts), unités [`ms-verif-conteneurs.service`](fichiers/M12-E28/outils/systemd/ms-verif-conteneurs.service) et [`.timer`](fichiers/M12-E28/outils/systemd/ms-verif-conteneurs.timer), [extrait du Taskfile](fichiers/M12-E28/outils/Taskfile-install-extrait.yml), [section de `docs/astreinte.md`](fichiers/M12-E28/outils/docs/astreinte-extrait.md). Projet `plateforme/ansible` : rôle [`supervision_conteneurs`](fichiers/M12-E28/ansible/roles/supervision_conteneurs/) (script [`ms-etat-conteneurs`](fichiers/M12-E28/ansible/roles/supervision_conteneurs/files/ms-etat-conteneurs)), variables [`ctr01`](fichiers/M12-E28/ansible/inventories/lab/host_vars/ctr01/supervision_conteneurs.yml) et [`ctr02`](fichiers/M12-E28/ansible/inventories/lab/host_vars/ctr02/supervision_conteneurs.yml), [extrait du playbook](fichiers/M12-E28/ansible/playbooks/conteneurs.yml.extrait) ; `metrics-addr` dans l'[extrait de `docker_engine.yml`](fichiers/M12-E26/ansible/inventories/lab/group_vars/role_docker/docker_engine.yml.extrait). Documentation : [`supervision.md`](fichiers/M12-E28/medisphere/docs/conteneurs/supervision.md).

*1. Sources.* `docker inspect` porte l'essentiel : `.State.Status` (`running`, `restarting`, `exited`…), `.State.Health.Status` et les dernières sondes avec leur sortie (`.State.Health.Log`), `.RestartCount`, `.State.OOMKilled`, `.State.ExitCode`. `docker events --filter type=container` donne en direct `start`, `die` (avec `exitCode`), `oom`, `health_status: unhealthy`, `restart`. `docker stats --no-stream` : CPU, mémoire, réseau, processus à l'instant. Côté Podman (compte `app`), mêmes champs dans `podman inspect`, événements dans `podman events` (journald). Piège central : un conteneur relancé par `restart: unless-stopped` garde son identité et incrémente **`RestartCount`** ; une unité Quadlet relancée par systemd (`Restart=`) **recrée** le conteneur (compteur à 0) : le compteur utile est celui de **l'unité** (`systemctl --user show -p NRestarts <unité>`). Le script `ms-etat-conteneurs` lit donc `NRestarts` pour les conteneurs qui portent l'étiquette `PODMAN_SYSTEMD_UNIT`.

*2. Métriques du démon.*

```
admin@adm01:~$ curl -s http://ctr01.par1.medisphere.internal:9323/metrics | grep -E '^engine_daemon_(engine_info|container_states_containers|health_checks)'
engine_daemon_engine_info{…,version="29.8.2"} 1
engine_daemon_container_states_containers{state="paused"} 0
engine_daemon_container_states_containers{state="running"} 6
engine_daemon_container_states_containers{state="stopped"} 1
engine_daemon_health_checks_failed_total 3
```

Noms à vérifier sur ta version. On y trouve l'état du **moteur** (nombre de conteneurs par état, sondes en échec, durée des actions, constructions) ; **rien** par conteneur (ni nom, ni mémoire). cAdvisor (`ghcr.io/google/cadvisor:v0.60.6`, montages de son README : `/:/rootfs:ro`, `/var/run:/var/run:ro`, `/sys:/sys:ro`, `/var/lib/docker/:/var/lib/docker:ro`, `/dev/disk/:/dev/disk:ro`, plus `--privileged` et `/dev/kmsg`) ajoute des séries par conteneur (`container_memory_working_set_bytes`, `container_cpu_usage_seconds_total`…), au prix d'un accès en lecture à **tout** l'hôte et souvent du mode privilégié — un agent de supervision est un composant critique pour la sécurité. Avec le stockage containerd de Docker 29, vérifie que cAdvisor rattache bien ses séries aux conteneurs (étiquettes `name`, `image`). Retiré : `docker rm -f cadvisor`.

*3. Accès minimal.* Compte `supervision` système, mot de passe verrouillé, hors groupe `docker` ; `authorized_keys` : `restrict,from="10.10.10.10",command="sudo -n /usr/local/sbin/ms-etat-conteneurs" ssh-ed25519 …` ; `sudoers` : `supervision ALL=(root) NOPASSWD: /usr/local/sbin/ms-etat-conteneurs ""` (les guillemets vides interdisent tout argument). Le script n'utilise que des lectures (`ps`, `inspect`, `systemctl show`) et ignore `SSH_ORIGINAL_COMMAND`.

```
admin@adm01:~$ ssh -i ~/.config/workbook/ssh-supervision-conteneurs supervision@ctr01.par1.medisphere.internal 'rm -rf /' | tail -2
docker	root	registre-registre-1	running	healthy	0	registry:3@sha256:…
fin 7
```

*4. La sonde.* Points de conception : une ligne de fin (`fin N`) prouve que la réponse est complète (une connexion coupée au milieu n'est pas « tout va bien ») ; la liste des **attendus** détecte un conteneur disparu (aucune source « instantanée » ne le ferait) ; l'état des compteurs est réécrit **après** un passage complet, dans le dossier d'état fourni par systemd (`StateDirectory=`) ; une hausse entre deux passages est une anomalie, une baisse (conteneur recréé) est simplement enregistrée ; les exceptions à la sonde de santé sont **écrites** dans la configuration (HAProxy de test). Les 17 tests `bats` remplacent `ssh` et `curl` par des fonctions ; chaque contrôle a son test rouge.

*5. Preuve.* Conteneur de test en boucle (méthode de RB-120 : `docker run -d --name essai-boucle --restart always debian:trixie-slim sh -c 'sleep 20; exit 1'`, ajouté temporairement aux attendus) : l'alerte arrive au passage suivant du timer (5 minutes au plus, plus 30 s de délai aléatoire) ; `journalctl -t ms-alerte` montre l'échec du service. Suppression du conteneur de test et de sa ligne, retour au vert au passage suivant.

*6. Astreinte* : [extrait](fichiers/M12-E28/outils/docs/astreinte-extrait.md) ; [`supervision.md`](fichiers/M12-E28/medisphere/docs/conteneurs/supervision.md).

**Explications**

Superviser des conteneurs, c'est surtout surveiller ce qui **change** : un conteneur qui redémarre, qui passe *unhealthy*, qui disparaît. L'état instantané (`running`) ment sur une boucle de redémarrage ; les métriques du moteur ne nomment personne ; seules la comparaison entre deux passages et une liste d'attendus disent « quel conteneur, sur quel hôte ». L'accès aux hôtes est le point dur : lire l'état de Docker exige le socket, donc root ; on borne ce pouvoir à **un** script en lecture seule, comme pour la sauvegarde de Ceph (M08-E25).

**Alternatives**
- Abonnement continu à `docker events` / `podman events` (service qui alerte sur `die`, `oom`, `health_status`) : immédiat, mais un processus de plus par hôte, et rien ne signale un conteneur qui n'a jamais démarré.
- Socket filtrant en lecture (`docker-socket-proxy`) exposé à la sonde : pas de SSH, mais un service de plus et un port à protéger.
- Exportateur Prometheus par hôte (cAdvisor, exportateur Podman) dès maintenant : prépare M21, mais sans alerte avant Alertmanager.

**Pièges classiques**
- Ajouter `supervision` au groupe `docker` « pour lire » (E32 Q6).
- Sonde qui lit le Podman **de root** au lieu de celui du compte `app` (elle ne voit rien et conclut que tout va bien).
- Compteur de redémarrages Podman/Quadlet toujours à 0 (le conteneur est recréé par systemd).
- Métriques du démon sur toutes les adresses d'un hôte joignable depuis d'autres VLAN : ici le VLAN 99 n'est joint que depuis MGMT ; sur `runner02` (INFRA), restreindre l'adresse d'écoute.

**En production chez MédiSphère**
Prometheus (M21) moissonne les métriques des démons, de cAdvisor ou de l'exportateur Podman, et des applications ; Alertmanager remplace `ms-alerte` pour les alertes de tendance ; la sonde reste comme contrôle de bout en bout indépendant, et sa liste d'attendus préfigure le catalogue des services (M28).

---

### M12-E29 — Sauvegarder et restaurer les données des conteneurs

**Solution**

Fichiers (projet `plateforme/ansible`) : rôle [`sauvegarde_conteneurs`](fichiers/M12-E29/ansible/roles/sauvegarde_conteneurs/) (script [`wb-backup-conteneurs.sh`](fichiers/M12-E29/ansible/roles/sauvegarde_conteneurs/files/wb-backup-conteneurs.sh), gabarits, unités), variables [`host_vars/ctr01/sauvegarde_conteneurs.yml`](fichiers/M12-E29/ansible/inventories/lab/host_vars/ctr01/sauvegarde_conteneurs.yml), [modèle de Vault](fichiers/M12-E29/ansible/inventories/lab/host_vars/ctr01/vault-critique.yml.exemple), [extrait de `pare_feu.yml`](fichiers/M12-E29/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) (adresse stable : [réservation Kea de M12-E15](fichiers/M12-E15/kea/reservation-ctr01.extrait.json)), [extrait du playbook](fichiers/M12-E29/ansible/playbooks/conteneurs.yml.extrait) ; PBS : [`pbs-jeton-conteneurs.sh`](fichiers/M12-E29/pbs01/pbs-jeton-conteneurs.sh), [règle d'entrée](fichiers/M12-E29/pbs01/pbs01-nftables-extrait.nft) ; documentation : [RB-121](fichiers/M12-E29/medisphere/docs/conteneurs/runbooks/RB-121-restaurer-la-base-d-une-pile-compose.md), [`tests/restauration-conteneurs.md`](fichiers/M12-E29/medisphere/docs/conteneurs/tests/restauration-conteneurs.md).

*1. Sauvegarde logique.*

```
admin@ctr01:~$ docker exec mediagenda-db-1 pg_dump -U mediagenda -d mediagenda -Fc > /tmp/mediagenda.dump
admin@ctr01:~$ docker exec -i mediagenda-db-1 pg_restore --list < /tmp/mediagenda.dump | grep 'TABLE DATA'
… TABLE DATA public rendez_vous mediagenda
… TABLE DATA public mediagenda_historique_schema mediagenda
admin@ctr01:~$ shred -u /tmp/mediagenda.dump
```

`pg_dump` lit la base dans **une** transaction (instantané *repeatable read*) : il la voit telle qu'elle était à son démarrage, quelles que soient les écritures concurrentes. Le conteneur `db` est durci (E24, racine en lecture seule) : rien n'y est écrit, le flux sort par la sortie standard de `docker exec`. L'authentification passe par le socket Unix local (règle `local … trust` de l'image).

*2. Sauvegarde de volume.* À chaud (boucle d'écritures en cours) :

```
admin@ctr01:~$ sudo install -d -m 700 /root/essai
admin@ctr01:~$ docker run --rm -v mediagenda_donnees-db:/source:ro -v /root/essai:/dest debian:trixie-slim tar -C /source -cf /dest/chaud.tar .
admin@ctr01:~$ docker volume create restau-chaud && docker run --rm -v restau-chaud:/v -v /root/essai:/a:ro debian:trixie-slim tar -C /v -xf /a/chaud.tar
admin@ctr01:~$ docker run -d --name restau-chaud -v restau-chaud:/var/lib/postgresql -e POSTGRES_PASSWORD=x docker.io/library/postgres:18-trixie
admin@ctr01:~$ docker logs restau-chaud 2>&1 | grep -iE 'recovery|redo|not properly shut down'
… database system was not properly shut down; automatic recovery in progress
… redo done at …
```

Elle démarre souvent… et c'est bien le problème : la « récupération automatique » rejoue le journal sur des fichiers copiés à des instants différents ; des pages peuvent être incohérentes sans aucune erreur visible (et parfois elle échoue franchement : `invalid record length`, `could not locate a valid checkpoint record`). À froid (`docker compose stop db`, copie, `start`) : cohérente, au prix d'une coupure. Une copie de fichiers d'une base en marche n'est une sauvegarde que si elle est faite **avec** la base (`pg_basebackup` et les WAL) ou par un instantané **atomique** de tout le système de fichiers (LVM, ZFS, RBD) suivi d'une récupération. Préfère la copie de volume pour des données **sans moteur** (fichiers téléversés, configuration générée) ou pour une migration planifiée. Nettoyage : `docker rm -f restau-chaud restau-froid ; docker volume rm restau-chaud restau-froid ; sudo rm -rf /root/essai`.

*3. Images.*

```
admin@ctr01:~$ docker save ctr01.par1.medisphere.internal:5000/mediagenda/api:<VERSION> -o /tmp/api.tar && tar -tf /tmp/api.tar | head -5
blobs/
blobs/sha256/…
index.json
manifest.json
oci-layout
app@ctr02:~$ podman load -i /tmp/api.tar                   # après copie du fichier (scp) dans le dossier d'app
app@ctr02:~$ skopeo copy docker://ctr01.par1.medisphere.internal:5000/mediagenda/api:<VERSION> oci-archive:/tmp/api-oci.tar
```

Avec le stockage containerd de Docker 29, `docker save` produit une archive au format **OCI** (`oci-layout`, `index.json`) **et** compatible avec l'ancien format (`manifest.json`) ; elle peut contenir plusieurs plateformes et les attestations de BuildKit (`--platform` pour n'en garder qu'une). Skopeo est installé sur `ctr02` (pas sur `ctr01`) ; depuis un hôte Docker, la source `docker-daemon:` de Skopeo lit directement le démon. Ce qui se **sauvegarde** : les données (bases, volumes de fichiers), les secrets (Vault) ; ce qui se **reconstruit** : les images (CI, empreintes dans Git), le registre de travail (repoussé par les pipelines), la configuration (Git, Ansible), les conteneurs eux-mêmes.

*4. Vers PBS.* Script [`pbs-jeton-conteneurs.sh`](fichiers/M12-E29/pbs01/pbs-jeton-conteneurs.sh) sur `pbs01` (espace `par1/conteneurs`, jeton `wb-backup@pbs!ctr01`, `DatastoreBackup` sur l'espace seulement) ; clé `proxmox-backup-client key create --kdf none` (Vault `critique`, *paperkey*, `shred -u`) ; adresse stable : la réservation Kea 10.10.99.121 et la définition `CTR01` de M12-E15 (rien à recréer, vérifier `ip -4 addr` sur `ctr01`) ; règle de bordure et règle d'entrée de `pbs01`. Le rôle reprend la structure de `sauvegarde_pbs` (M06-E28) ; `ctr01` n'étant pas dans le groupe `socle`, l'empreinte du certificat de PBS est répétée dans son Vault. Le script (testé hors lab avec un faux client PBS : export, vérification, copie à froid avec arrêt et relance de l'écrivain, nettoyage) vérifie chaque archive (`pg_restore --list`, présence de `TABLE DATA`), relance **toujours** un conteneur arrêté pour une copie à froid (`trap`), et rend un code non nul au moindre échec.

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/conteneurs.yml --limit ctr01 --tags sauvegarde
admin@ctr01:~$ sudo systemctl start wb-backup-conteneurs.service && journalctl -u wb-backup-conteneurs -n 5 -o cat
wb-backup-conteneurs: base mediagenda (mediagenda-db-1) : 41231 octets, 2 table(s)
wb-backup-conteneurs: sauvegarde envoyée vers par1/conteneurs/host/ctr01 en 7 s
```

La VM `ctr01` est déjà dans `lab-nuit` (pool `lab`) : `pvesh get /cluster/backup --output-format json | jq '.[] | select(.id=="lab-nuit") | .pool'` sur `pve01`. On ne double pas : la sauvegarde de VM restaure l'hôte, l'export logique restaure **la base**, plus finement et sur n'importe quel hôte.

*5. Restauration* : voir RB-121 (restauration à côté dans `restau-db`, comparaison `count(*)` et empreinte `md5(string_agg(…))` des deux côtés, nettoyage, `shred` des fichiers restaurés) et le [compte rendu de test](fichiers/M12-E29/medisphere/docs/conteneurs/tests/restauration-conteneurs.md).

*6. Runbook* : [RB-121](fichiers/M12-E29/medisphere/docs/conteneurs/runbooks/RB-121-restaurer-la-base-d-une-pile-compose.md).

**Explications**

La cohérence d'une sauvegarde se décide **au niveau de l'application** : seul le moteur de base sait quand ses fichiers forment un tout. L'export logique est lent pour de grosses bases, mais il est portable (autre hôte, autre version mineure, restauration d'une seule table) et toujours cohérent. Le conteneur ne change rien à ces principes ; il change **où** l'on exécute l'outil (dans le conteneur, avec sa version) et rend tentante une copie du volume, qui n'est qu'une copie de fichiers.

**Alternatives**
- `pg_basebackup` + archivage des WAL : restauration à la seconde près, plus complexe ; c'est ce que CloudNativePG fera (M16).
- Sauvegarde de VM seule (`lab-nuit`) : simple, mais restaurer une base, c'est restaurer toute la VM (et le registre avec).
- Service de sauvegarde dans la pile Compose (profil `outils`) déclenché par le timer : tout reste dans le dépôt de l'application, mais les secrets PBS entrent alors dans un conteneur.

**Pièges classiques**
- Croire qu'un PostgreSQL qui redémarre sur une copie à chaud prouve la sauvegarde.
- Exporter avec le `pg_dump` de l'**hôte** (autre version) au lieu de celui du conteneur.
- Laisser les fichiers restaurés (données de santé, en clair) sur l'hôte après le test.
- Oublier de relancer un conteneur arrêté pour une copie à froid quand la copie échoue (d'où le `trap`).
- Règle de bordure écrite sur une adresse DHCP qui change au prochain bail.

**En production chez MédiSphère**
Bases sous CloudNativePG avec archivage continu vers `s3-01` (M16), volumes Kubernetes par Velero (M16), test de restauration mensuel automatisé (F5), supervision de l'âge des sauvegardes (M21).

---

### M12-E30 — Mettre à jour sans interruption et revenir en arrière

**Solution**

Fichiers (projet `mediagenda/api`) : [`compose.ha.yaml`](fichiers/M12-E30/mediagenda-api/compose.ha.yaml), [`haproxy/haproxy.cfg`](fichiers/M12-E30/mediagenda-api/haproxy/haproxy.cfg), [`outils/maj-progressive.sh`](fichiers/M12-E30/mediagenda-api/outils/maj-progressive.sh). Sur `ctr02` : [extrait de l'unité Quadlet](fichiers/M12-E30/ctr02/mediagenda-api.container.extrait), [identifiants persistants et timer](fichiers/M12-E30/ctr02/auth-persistante.md). Documentation : [RB-122](fichiers/M12-E30/medisphere/docs/conteneurs/runbooks/RB-122-mettre-a-jour-une-application-conteneurisee.md).

*1. La coupure actuelle.* Boucle témoin depuis `adm01` :

```
admin@adm01:~$ while :; do printf '%s %s\n' "$(date +%T.%N | cut -c1-12)" \
    "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 'http://ctr01.par1.medisphere.internal:8000/api/v1/creneaux?date=2026-11-02')"; \
    sleep 0.05; done | tee charge.log
admin@adm01:~$ grep -vc ' 200$' charge.log
```

`docker compose up -d --wait` avec une nouvelle étiquette **arrête** le conteneur (SIGTERM, fin des requêtes en cours), le **supprime**, en **crée** un nouveau, puis attend la sonde : pendant ce temps (quelques secondes, plus la période de démarrage), le port 8000 refuse les connexions (`000`) ou renvoie des erreurs. `deploy.update_config` (parallélisme, ordre `start-first`) est une notion de la spécification Compose prévue pour Swarm : Docker Compose ne fait pas de mise à jour progressive d'un service et recrée les répliques ensemble.

*2. Deux instances et un répartiteur.* `api-b` reprend `api` par `extends: {file: compose.yaml, service: api}` (image, durcissement de E24, sonde, secrets, réseaux) ; `ports: !reset []` retire la publication directe des deux instances (sinon un client resterait collé à l'instance qu'on redémarre, et deux services ne peuvent pas publier le même port) ; `depends_on` est redéclaré explicitement (lisible, et sans dépendre des règles de fusion de `extends` pour ce champ). HAProxy (`haproxy:3.2-trixie`, non root, port 8080, racine en lecture seule, aucune capacité) publie le port **8000** de l'hôte : les clients ne changent rien. Points de configuration :
- sonde de **disponibilité** `GET /pret` (base et cache) : une instance qui perd sa base sort de la rotation sans être redémarrée ; `inter 1s fall 2 rise 2` ;
- `resolvers docker` (127.0.0.11, `hold valid 1s`) et `init-addr none` : une instance recréée **change d'adresse IP** ; sans résolution dynamique, HAProxy garde l'ancienne adresse (résolue une fois au démarrage) et l'instance ne revient jamais, ou HAProxy refuse de démarrer si une instance manque ;
- `retries 3`, `option redispatch 1`, `retry-on conn-failure empty-response` : une requête qui échoue **à la connexion** (instance qui vient de fermer son socket) est rejouée sur l'**autre** serveur ; on ne rejoue pas sur `response-timeout` (une requête `POST` déjà traitée serait doublée).

*3. Mise à jour progressive.* `maj-progressive.sh` recrée `api` avec `--no-deps --wait`, attend qu'**HAProxy** le voie UP (page d'état `;csv`, colonne 18 `status`), puis fait de même pour `api-b` ; à la première erreur il s'arrête avant de toucher la seconde instance et affiche la commande de retour (version précédente lue par `docker compose images api --format json`). Mesures hors lab (Docker 29.8.2, mêmes fichiers) :

```
admin@ctr01:~/src/mediagenda-api$ export COMPOSE_FILE=compose.yaml:compose.ha.yaml
admin@ctr01:~/src/mediagenda-api$ MEDIAGENDA_TAG=0.2.1 outils/maj-progressive.sh
Version en service : 0.2.0 ; cible : 0.2.1
== api : recréation
== api : attente du passage UP dans HAProxy (api-a)
== api-b : recréation
== api-b : attente du passage UP dans HAProxy (api-b)
Mise à jour terminée : les deux instances sont en 0.2.1.          # 16 s ; charge témoin : 915 × 200, 0 erreur
admin@ctr01:~/src/mediagenda-api$ MEDIAGENDA_TAG=0.3.0 outils/maj-progressive.sh     # image cassée
== api : recréation
container mediagenda-api-1 is unhealthy
ÉCHEC : api n'est pas devenu healthy. L'autre instance sert toujours.
Retour arrière : MEDIAGENDA_TAG=0.2.1 outils/maj-progressive.sh
admin@ctr01:~/src/mediagenda-api$ MEDIAGENDA_TAG=0.2.1 outils/maj-progressive.sh     # 1 475 × 200, 0 erreur sur tout l'essai
```

`<NOUVELLE>` : `docker build --build-arg VERSION=0.2.1 -t mediagenda-api:0.2.1 .` (même code, autre version, visible dans `/sante`). Image cassée utilisée : `printf 'FROM mediagenda-api:0.2.1\nENV MEDIAGENDA_PORT=8001\n' | docker build -t mediagenda-api:0.3.0 -` (le processus écoute ailleurs : la sonde et HAProxy échouent, l'instance n'entre jamais en rotation).

*4. Mise à jour automatique (Podman).* Clés ajoutées ou modifiées dans l'unité de E14 : `Image=…/mediagenda/api:recette` (à la place de l'unité `.build`), `AutoUpdate=registry`, et dans `[Service]` `TimeoutStartSec=90`. La sonde (`HealthCmd=` en tableau JSON, Python : l'image n'a pas de `curl`) et `Notify=healthy` (l'unité n'est « démarrée » que lorsque le conteneur est *healthy*, option `--sdnotify=healthy` de `podman run`) sont déjà là depuis E14 : vérifie-les, car tout le retour arrière en dépend. Identifiants dans `~/.config/containers/auth.json` (persistant) et non dans `$XDG_RUNTIME_DIR` (vidé au redémarrage) ; `systemctl --user enable --now podman-auto-update.timer`. Publication et essai :

```
admin@adm01:~$ skopeo copy --src-creds plateforme:<MDP> --dest-creds plateforme:<MDP> \
    docker://ctr01.par1.medisphere.internal:5000/mediagenda/api:<NOUVELLE> docker://ctr01.par1.medisphere.internal:5000/mediagenda/api:recette
app@ctr02:~$ podman auto-update --dry-run
UNIT                    CONTAINER              IMAGE                                               POLICY    UPDATED
mediagenda-api.service  … (mediagenda-api)     ctr01.par1.medisphere.internal:5000/mediagenda/api:recette  registry  pending
app@ctr02:~$ podman auto-update                      # UPDATED = true ; /sante donne la nouvelle version
```

*5. Retour arrière automatique.* Après publication de `<CASSÉE>` sous `recette` : `podman auto-update` tire l'image, redémarre l'unité ; le conteneur démarre mais ne devient jamais *healthy* ; au bout de `TimeoutStartSec` systemd déclare l'échec du démarrage ; `podman auto-update` remet l'image précédente sur l'étiquette locale et redémarre l'unité (`UPDATED` : `rolled back`, libellé à vérifier ; `journalctl --user -u mediagenda-api.service` montre l'échec puis le redémarrage). À la fin, l'image en service est `<NOUVELLE>` (`podman inspect --format '{{.ImageDigest}}'`). Sans `Notify=healthy`, l'unité est démarrée dès que le processus est lancé : le redémarrage « réussit » avec l'image cassée et **aucun** retour arrière n'a lieu ; la sonde passe ensuite *unhealthy* sans autre effet. Remets `<NOUVELLE>` sous `recette`, sinon le prochain passage du timer retentera la mauvaise image.

*6. Réflexion.* Étiquette mobile : acceptable en recette (on veut la dernière), jamais en production : on ne sait plus quelle version tourne ni comment la reproduire, et pousser sur la mauvaise étiquette met à jour un environnement sans MR. En production : version immuable désignée par son empreinte, changée par MR (GitOps au M20). Savoir ce qui tourne : l'**empreinte** du conteneur (`docker inspect --format '{{.Image}}'`, `podman inspect --format '{{.ImageDigest}}'`), pas l'étiquette. Runbook : [RB-122](fichiers/M12-E30/medisphere/docs/conteneurs/runbooks/RB-122-mettre-a-jour-une-application-conteneurisee.md).

**Explications**

Une mise à jour sans interruption repose sur trois propriétés, qu'il faut toutes : l'application **s'arrête proprement** (elle cesse d'accepter, finit ce qu'elle a commencé, E17) ; le répartiteur **ne lui envoie plus rien** et **rejoue ailleurs** ce qui a échoué sans effet ; l'orchestrateur **attend** que la nouvelle instance soit vraiment en service (pour le répartiteur, pas seulement pour le moteur) avant de toucher la suivante. Kubernetes fera tout cela en standard (`RollingUpdate`, sondes de disponibilité, M14) ; le faire ici à la main montre ce que ces mécanismes recouvrent. Le retour arrière automatique de Podman n'a de valeur que si « démarré » signifie « sain » : c'est tout l'objet de `Notify=healthy`.

**Alternatives**
- Bleu-vert : deux piles complètes, bascule du répartiteur d'un coup (retour arrière instantané, double ressource).
- *Drain* explicite par l'API d'exécution de HAProxy (`set server api/api-a state drain`) avant l'arrêt : plus propre que de compter sur les nouvelles tentatives, demande un socket d'administration.
- Docker Swarm (`docker service update --update-order start-first`) : la mise à jour progressive existe, au prix d'un orchestrateur de plus que MédiSphère n'adopte pas (ADR-0120, Kubernetes au M14).

**Pièges classiques**
- HAProxy sans `resolvers` : l'instance recréée n'a plus la même IP.
- Passer à la seconde instance dès que Docker la dit *healthy*, avant qu'HAProxy l'ait remise en rotation.
- `retry-on` trop large (`response-timeout`, `all-retryable-errors`) qui rejoue des `POST`.
- Sonde de disponibilité sur `/sante` (ne voit pas la base) ou sonde de vivacité sur `/pret` (redémarre l'instance quand la base tombe).
- `podman login` dans `$XDG_RUNTIME_DIR` : la mise à jour automatique échoue après le premier redémarrage de l'hôte.
- Migration qui retire une colonne avant que l'ancienne version ait disparu (E32 Q12).

**En production chez MédiSphère**
Mises à jour par Kubernetes (`RollingUpdate`, `maxUnavailable: 0`, `PodDisruptionBudget`, M14-M17) pilotées par GitOps (M20), versions immuables par empreinte, analyse automatique de la mise à jour (taux d'erreur, M21) ; la règle « étendre puis contracter » des migrations devient une norme de revue de MédiAgenda.

---

### M12-E31 — ADR : Docker ou Podman sur les serveurs

**Solution**

Modèle : [`ADR-0120-docker-ou-podman.md`](fichiers/M12-E31/medisphere/docs/conteneurs/adr/ADR-0120-docker-ou-podman.md). Décision : **Podman sans privilège + Quadlet** sur les serveurs applicatifs hors Kubernetes ; **Docker** pour la CI (`runner02`, jamais privilégié, constructions BuildKit sans privilège) ; **exception bornée** pour les outils fondés sur Docker Compose (Harbor sur `reg01`, M13), avec le durcissement de E26 ; postes de développement libres, fichiers livrés conformes aux normes. Arguments décisifs : l'absence de privilège est le **fonctionnement normal** de Podman alors qu'elle coûte cher sous Docker 29 (*userns-remap* désactive le stockage containerd, E26) ; Quadlet donne systemd, la mise à jour automatique et le retour arrière fondé sur la santé (E30) ; SELinux et udica sont naturels sur la famille RHEL (E25). Contre-arguments écrits : Podman 5.4 figé sur Debian 13, deux moteurs à maintenir, piles Compose à traduire.

**Explications**

La bonne réponse n'est pas un moteur mais une **répartition par usage** : les critères n'ont pas le même poids sur un serveur qui fait tourner une application vingt-quatre heures sur vingt-quatre (sécurité par défaut, systemd) et sur un runner qui exécute des jobs de quelques minutes (compatibilité, outillage). Le score pondéré rend les compromis visibles ; il ne remplace pas la décision (une contrainte comme « Harbor s'installe avec Docker Compose » s'impose quelle que soit la note).

**Alternatives** (également défendables)
- Docker partout, durci (E26) : un seul outil, l'équipe le connaît ; il faut alors accepter le démon root ou payer *userns-remap*, et écrire la supervision et les mises à jour automatiques soi-même.
- Podman partout, Harbor compris (`podman compose` ou socket compatible Docker de Podman) : cohérent, mais hors du chemin supporté par Harbor, risqué pour le composant le plus critique de la chaîne d'images.

**Pièges classiques**
- Comparer des fonctionnalités « possibles » et non vérifiées (Podman 6 et `podman quadlet install` alors que Debian 13 livre la 5.4).
- Oublier que Kubernetes n'utilise ni l'un ni l'autre : l'ADR ne porte que sur l'extérieur de Kubernetes.
- Taire le coût de l'exception (démon root sur `reg01`) et ne pas lui fixer de date de revue.

**En production chez MédiSphère**
Revue de l'ADR à Debian 14, à la sortie de Harbor M13 et au passage de la CI sur Kubernetes (M19) ; les normes (E33) restent indépendantes du moteur.

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Gabarit | MADR, statut, date, décideurs, ticket ; deux pages au plus |
| Contexte | usages distingués, exigences de Sophie et de Karim, Kubernetes hors périmètre, versions réelles des distributions |
| Critères | au moins 6, pondérés, dont sécurité par défaut, systemd, compatibilité outillage, CI sans privilège |
| Options | au moins 3, chaque note appuyée sur un exercice cité |
| Décision | par usage (serveurs, CI, outils imposant Docker, postes), devenir de `ctr01`, `runner02`, `reg01` |
| Conséquences | négatives écrites, actions rattachées à un module ou datées |

---

### M12-E32 — Questions de production : conteneurs

1. Avec les capacités par défaut et sans `no-new-privileges`, un processus UID 10001 n'a **aucune** capacité effective, mais le jeu limite en contient 14. Gestes encore possibles : déposer et **exécuter** un outil dans un dossier inscriptible (`/tmp`) → racine en lecture seule et `tmpfs` en `noexec` ; **`ptrace`** sur les autres processus du conteneur (lire des secrets en mémoire) → profil seccomp sans `ptrace` (ou `CAP_SYS_PTRACE` absente **et** `kernel.yama.ptrace_scope`) ; s'**élever** par un binaire setuid root de l'image → `no-new-privileges` (le setuid ne change plus l'identité) et `cap_drop: ALL` (même devenu root, plus de capacité) ; aussi : ouvrir des connexions vers les autres services du réseau (réseaux `internal`, E08). `su`, `passwd`, `mount` setuid sont précisément les vecteurs d'élévation : chacun est un programme root lancé par l'attaquant ; une faille dans l'un d'eux suffit. Les retirer (distroless) ou les neutraliser (`no-new-privileges`).
2. **d)** Docker fixe `net.ipv4.ip_unprivileged_port_start=0` dans l'espace de noms réseau de chaque conteneur (hors `--network host`) : tout processus peut écouter sur le port 80, **même** avec `--cap-drop ALL` (constaté sur 29.8.2). a) est faux pour la raison inverse de ce qu'on croit : la capacité ajoutée n'est **pas** effective pour un processus non root (Docker ne pose pas de capacités ambiantes : `CapEff` reste à 0, seul `CapBnd` la contient) — si l'on remet le réglage à 1024 (`--sysctl net.ipv4.ip_unprivileged_port_start=1024`), l'écoute échoue malgré `--cap-add` ; b) décrit correctement la capacité mais pas le résultat ; c) faux, l'ajout après `ALL` est accepté. Pour écouter sur 80 sans root : s'appuyer sur ce réglage (Docker, ou le poser explicitement en Podman : `--sysctl`), écouter sur un port > 1024 et publier `80:8080` (le plus simple, norme `CNT-RUN-11`), ou poser une capacité de fichier (`setcap cap_net_bind_service+ep` sur le binaire, avec la capacité dans le jeu limite et sans `no-new-privileges`… ce qui contredit E24 : à éviter).
3. Un profil minimal est fragile : il dépend de chaque bibliothèque, de la version de Python ou de la libc, des chemins de code rares (erreurs, arrêt) ; un appel oublié casse l'application en production, souvent de façon obscure. Le profil par défaut bloque déjà les appels les plus dangereux (environ 50 : `kexec_load`, `init_module`, `bpf`, `perf_event_open`, `keyctl`, `mount`, `unshare`/`clone` d'espaces de noms sans `CAP_SYS_ADMIN`, `io_uring_*` selon la version…), et beaucoup d'appels sont **conditionnés** à une capacité : c'est pourquoi retirer les capacités compte autant que seccomp. seccomp réduit la surface du **noyau** ; les capacités disent ce que root peut faire **dans** cette surface.
4. `seccomp=unconfined` sans capacité : tous les appels système sont permis, mais ceux qui exigent une capacité échouent quand même (`mount`, `unshare` sans `CAP_SYS_ADMIN`… sauf la création d'un espace de noms **utilisateur**, permise sans capacité si le noyau l'autorise, ce qui redonne des capacités dans ce nouvel espace : c'est la porte vers les failles noyau que seccomp fermait). `--privileged` : toutes les capacités, aucun seccomp, aucun AppArmor/SELinux (`spc_t`), **tous les périphériques** de l'hôte (`/dev/sda`), `/sys` et `/proc` inscriptibles : root sur l'hôte en une commande (`mount /dev/sda1 /mnt`). Classement : `--privileged` ≫ `seccomp=unconfined` sans capacité > configuration par défaut.
5. `:Z` sur le même dossier pour deux conteneurs : chaque démarrage réétiquette le dossier aux catégories **du conteneur qui démarre** ; le premier perd l'accès à ses fichiers (refus SELinux au milieu de son fonctionnement). Avec `:z` : étiquette `container_file_t:s0` partagée, les deux accèdent. `:Z` sur `/home/app` réétiquette tout le dossier personnel (dont `.ssh/authorized_keys`) en `container_file_t` : `sshd` ne lit plus les clés, la connexion d'`app` échoue ; réparation : `sudo restorecon -RFv /home/app`. Règle : `:z`/`:Z` seulement sur un dossier **dédié** aux conteneurs ; sinon `semanage fcontext` ou udica (E25).
6. **b)** Le socket du démon ne connaît que « peut parler » ou « ne peut pas » : toute session sous `supervision` (une clé volée, une commande injectée dans un script) peut lancer `docker run -v /:/hote … chroot /hote` et devenir root, sans mot de passe ni trace `sudo`. a) faux, l'API n'a pas de droits par groupe ; c) hors sujet ; d) faux. La solution de E28 donne au compte **une seule** commande en root (règle `sudo` sans argument, clé à commande forcée et restreinte, origine limitée à `adm01`) : le pire que puisse faire la clé volée est de lire l'état des conteneurs.
7. Conséquences : (1) Docker 29 **désactive le stockage d'images containerd** et revient aux anciens pilotes (plus d'images multi-plateformes ni d'attestations locales) ; (2) images, conteneurs et volumes rangés à part (`/var/lib/docker/<uid>.<gid>/`) : tout « disparaît » à l'activation ; (3) les fichiers écrits dans les volumes et les montages de l'hôte appartiennent aux UID décalés (100000+) ; (4) `--network host`, `--pid host`, certains montages exigent `--userns=host` (qui annule la protection). Apport : un processus **root** du conteneur (image qui l'exige, évasion qui donne root) n'est que l'UID 100000 sur l'hôte ; un conteneur non root reste, lui, root de l'hôte s'il s'évade **et** s'élève jusqu'à l'UID 0 du conteneur.
8. Mise à jour de `docker-ce` avec `live-restore` : `dockerd` redémarre, les conteneurs **continuent** (gérés par containerd et leurs *shims*) ; pendant l'arrêt, journaux tamponnés, sondes et politiques de redémarrage suspendues, ports servis par `docker-proxy` interrompus. Mise à jour de `containerd.io` : le service containerd redémarre ; les *shims* survivent en général, mais c'est moins garanti (lis les notes de version ; prévois une fenêtre). Redémarrage de l'hôte : tout s'arrête ; au démarrage, c'est la **politique de redémarrage** (`restart: unless-stopped`, `always`) qui relance les conteneurs (pas `live-restore`) ; côté Podman, les unités Quadlet (`WantedBy=default.target` et *linger*).
9. Le conteneur **boucle** : il plante, Docker le relance (`restart:`), il redevient `running` et même `healthy` pendant sa période de démarrage, puis replante. Un état instantané le voit sain la plupart du temps. Il faut une **dérivée** (le compteur qui monte entre deux passages, E28) ou l'événement **`die`** (avec `exitCode`) de `docker events`, émis à chaque arrêt, ou `oom` si c'est la mémoire.
10. **b)** PostgreSQL qui démarre après une « récupération automatique » ne valide rien : il rejoue le WAL copié sur des fichiers de données copiés à d'autres instants ; des pages peuvent être déchirées ou incohérentes, découvertes des semaines plus tard (ou jamais). a) faux, il n'y a pas de vérification de cohérence globale au démarrage ; c) faux, la taille ne change pas le principe (une petite base copiée en 1 s peut quand même changer pendant la copie) ; d) faux, `tar` ne voit pas toutes les modifications et son silence ne prouve rien. Conditions d'une vraie sauvegarde de fichiers : base arrêtée (à froid) ; ou `pg_backup_start`/`pg_backup_stop` avec conservation des WAL produits pendant la copie (`pg_basebackup`) ; ou instantané atomique de **tout** le système de fichiers (données et WAL au même instant), restauré comme après une panne de courant.
11. Côté application : arrêt propre sur SIGTERM (plus de nouvelle connexion, fin des requêtes en cours dans le délai), sonde de disponibilité honnête (`/pret`), démarrage complet avant d'être déclaré prêt, compatibilité des deux versions avec la base. Côté répartiteur : sonde de disponibilité, résolution dynamique des adresses, nouvelle tentative **ailleurs** pour les échecs de connexion, attente de la remise en rotation avant d'arrêter l'autre instance. `POST` en cours sur l'instance qu'on arrête : uvicorn le termine (délai de grâce) et la réponse part normalement. Requête qui arrive juste après la fermeture du socket : connexion refusée, HAProxy la rejoue sur l'autre serveur (`retry-on conn-failure`, `redispatch`) ; le client ne voit rien.
12. Si la colonne obligatoire n'a pas de valeur par défaut, chaque `INSERT` de l'ancienne version (qui ne la connaît pas) échoue (`NOT NULL violation`) : erreurs 500 pendant toute la bascule, et un retour arrière vers l'ancienne version est impossible tant que la colonne reste obligatoire. Règle « **étendre puis contracter** » : version N+1 ajoute la colonne **facultative** (ou avec valeur par défaut) et écrit dedans ; une fois toutes les instances en N+1 (et le retour arrière abandonné), une migration ultérieure la rend obligatoire ; une suppression se fait en sens inverse (N+1 cesse de lire, N+2 supprime). Les migrations sont appliquées **avant** la mise à jour et doivent être compatibles avec N et N+1.
13. Il faut que « l'unité a démarré » signifie « le conteneur est sain » (`Notify=healthy`, sonde qui teste vraiment le service, `TimeoutStartSec` suffisant) ; sans cela, `podman auto-update` voit un redémarrage réussi et garde l'image cassée. Une étiquette mobile partagée entre environnements (ou une production qui suit `recette`, voire `latest`) fait qu'une simple poussée met à jour sans MR ni revue. Ce qui l'empêche : production sur une version immuable par empreinte ; étiquettes immuables dans le registre (Harbor, M13) ; droits de poussée séparés par environnement (robots) ; signature exigée (M13).
14. L'application à étiquette **datée** de trois mois reste exposée tant qu'une MR ne la fait pas avancer : l'image de base corrigée existe dès lundi (reconstruction d'urgence ou hebdomadaire), mais l'application ne la prend qu'à sa prochaine construction sur la nouvelle étiquette — exposition = délai de la MR (cible normes : 5 jours ouvrés, `CNT-EXP-03`), et les trois mois de correctifs manqués s'ajoutent. Coût : nul en reproductibilité, élevé en suivi. L'application qui suit l'étiquette **mobile** reçoit le correctif à sa prochaine **reconstruction** (pas avant : une image construite reste ce qu'elle est) ; si elle se reconstruit chaque nuit, exposition d'un jour ; coût : deux constructions du même commit donnent deux images différentes, un retour arrière exact demande l'empreinte. Compromis MédiSphère : étiquette datée + empreinte, MR automatiques (Renovate, M13).
15. **b)** L'empreinte désigne des **octets** précis : tout le monde construit à partir de la même image, tant qu'elle reste disponible (un registre peut la supprimer). a) faux : une image épinglée ne reçoit plus aucun correctif, elle accumule les failles connues ; c) faux : l'empreinte est une somme de contrôle, pas une signature (rien ne dit **qui** l'a produite ; c'est le rôle de Cosign, M13) ; d) faux : `apt-get install` dans le Dockerfile tire les versions **du jour** depuis les dépôts, l'épinglage de l'image de base n'y change rien.
16. Aujourd'hui : les normes (`CNT-IMG-05`, `CNT-RUN-02` à `05`, `CNT-RUN-12`), contrôlées **à la construction** (Hadolint : dernier `USER` numérique non root ; revue des `compose.yaml`) et **à l'exécution** par les vérifications d'exploitation (inspection des conteneurs, comme les checks de E24, à transformer en contrôle planifié), la sonde (liste des conteneurs attendus), l'audit des modifications du moteur (E26), et les journaux de CI qui prouvent quelle image a été publiée. Faiblesse honnête : un conteneur lancé à la main sur un hôte échappe aux contrôles de construction ; seule une inspection régulière le voit. Plus tard : signature et analyse des images à la publication, registre unique (M13) ; admission Kubernetes qui **refuse** un pod root ou privilégié (Pod Security *restricted*, Kyverno, M26), ce qui transforme la règle en impossibilité, avec rapports de conformité continus.

---

### M12-E33 — Normes de conteneurisation de MédiSphère

**Solution**

Modèle : [`normes.md`](fichiers/M12-E33/medisphere/docs/conteneurs/normes.md). Points structurants : règles à identifiant stable (`CNT-IMG-*`, `CNT-PUB-*`, `CNT-RUN-*`, `CNT-DON-*`, `CNT-EXP-*`, `CNT-HOTE-*`), niveau, justification d'une ligne et **contrôle** (CI, revue, sonde, vérification, admission future) ; interdits explicites (`latest`, root, `--privileged`, socket monté, `label=disable`, `seccomp=unconfined`, secrets en couche) ; exceptions datées et tracées ; tableau de correspondance règles → contrôles automatiques, qui servira au module 26 ; grille de revue de MR en fin de document.

**Explications**

Une norme utile est **courte**, **vérifiable** et **justifiée** : la justification permet à une équipe de comprendre (et de contester) la règle, le contrôle permet de la faire respecter sans revue héroïque. Écrire le moyen de contrôle à côté de chaque règle révèle les règles qui ne sont qu'un vœu (« non root à l'exécution » n'est vérifiable automatiquement qu'avec une inspection ou une admission) : on les marque comme telles et on planifie le contrôle.

**Alternatives**
- Reprendre le CIS Docker Benchmark tel quel : exhaustif, mais centré sur l'hôte Docker et peu lisible par une équipe de développement.
- Normes sous forme de **politiques exécutables** (Conftest/OPA sur les `compose.yaml`, Kyverno au M26) : le document devient la politique ; c'est la cible, une fois les règles stabilisées.

**Pièges classiques**
- Règles sans moyen de contrôle, ou présentées comme contrôlées alors qu'elles ne le sont pas.
- Normes qui contredisent l'existant sans plan de mise en conformité (MédiDoc et son `FROM` non épinglé : MR prévue au mini-projet).
- Exceptions sans date de fin.
- Document trop long, plein d'exemples : il n'est pas lu.

**En production chez MédiSphère**
Normes intégrées au gabarit de projet (M28), contrôlées en CI et par l'admission Kubernetes (M26) ; indicateur mensuel « applications conformes » ; revue semestrielle en comité (Claire, Sophie, Julien, Karim).

**Grille d'auto-évaluation**

| Relecteur | Critère | Attendu |
|---|---|---|
| Sophie | Sécurité | non root, capacités, `no-new-privileges`, lecture seule, seccomp, secrets, interdits explicites, SELinux et socket |
| Sophie | Contrôle | chaque règle DOIT a un contrôle ; les contrôles manuels sont dits manuels |
| Julien | Faisabilité | règles applicables par une équipe sans la Plateforme (gabarits, exemples hors du texte), exceptions possibles et rapides |
| Julien | Clarté | identifiants stables, une ligne de justification, quatre à six pages |
| Karim | Exploitation | sonde, sauvegarde, mise à jour et retour arrière, cycle de vie des images, runbooks |
| Tous | Cohérence | rien qui contredise E24-E30, l'ADR-0120 ou la politique d'images de base (E27) |

---

### M12-E34 — Conteneuriser une application en temps limité

**Solution** (déroulé de référence ; à ne lire qu'après ta tentative chronométrée)

Fichiers (projet `mediagenda/annuaire`) : [`Dockerfile`](fichiers/M12-E34/annuaire/Dockerfile), [`.dockerignore`](fichiers/M12-E34/annuaire/.dockerignore), [`compose.yaml`](fichiers/M12-E34/annuaire/compose.yaml), [`.gitlab-ci.yml`](fichiers/M12-E34/annuaire/.gitlab-ci.yml) ; [extrait de la configuration de la sonde](fichiers/M12-E34/ms-verif-conteneurs.conf.extrait) ; [extrait du registre des secrets](fichiers/M12-E34/registre-secrets.extrait.md).

| Jalon | Actions | Temps de référence |
|---|---|---|
| T0 → T1 | Lecture du dossier et du README (variables, sondes, **dossier de cache inscriptible**, codes de sortie) ; projet `mediagenda/annuaire` créé, code poussé ; Dockerfile multi-étapes (uv, `--no-editable`) à partir de `bibliotheque/python` daté et épinglé, UID 10003 (10001 MédiAgenda, 10002 MédiNotif), `HEALTHCHECK` par `mediannuaire sonde`, étiquettes OCI ; `.dockerignore` en liste blanche ; construction et essai locaux sur `ctr01` | 25 min |
| T1 → T2 | `.gitlab-ci.yml` : tests (`unittest`), Hadolint, `images-autorisees`, construction par le gabarit E21 (stages et workflow de `qualite.yml`, étiquettes déduites de Git) ; pipeline de `main` vert, puis étiquette Git `v1.0.0` (ou version par semantic-release) : image `1.0.0` publiée | 25 min |
| T2 → T3 | Secret `secrets/jeton_admin` (700/644, hors Git), `compose.yaml` de recette (image publiée, `read_only` + `tmpfs` sur le cache, aucune capacité, limites, données `:ro`, secret en fichier), `docker compose up -d --wait` ; exigences 4 à 7 constatées | 20 min |
| T3 → T4 | MR sur la configuration de la sonde, registre des secrets, `lab/bin/check 12 34` | 10 min |

Le piège de l'application : avec la racine en lecture seule et sans `tmpfs` sur `/var/cache/mediannuaire`, elle refuse de démarrer (code 3, « cache inutilisable ») ; le `tmpfs` doit appartenir à l'UID du service (`uid=10003,gid=10003`), sinon même erreur. Constats hors lab avec ces fichiers : image construite et lue par Hadolint 2.15.1 sans avertissement ; recette saine (`/sante`, `/pret`, liste des cardiologues, `POST /admin/recharger` 200 avec le jeton, 401 sans) ; `docker compose stop` en 0,7 s, code de sortie 0 (« signal reçu, arrêt en cours » puis « arrêt terminé » dans le journal JSON) ; le script d'essais de E24 trouve un seul geste possible (`ptrace`, profil seccomp par défaut : acceptable au niveau `DEVRAIT` de `CNT-RUN-06`, à documenter).

```
admin@ctr01:~/src/annuaire$ docker inspect annuaire-annuaire-1 --format '{{.Config.User}} {{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}} {{json .HostConfig.Tmpfs}}'
10003:10003 true [ALL] [no-new-privileges:true] {"/var/cache/mediannuaire":"size=8m,mode=0700,uid=10003,gid=10003,noexec,nosuid,nodev"}
admin@ctr01:~/src/annuaire$ docker inspect annuaire-annuaire-1 --format '{{json .Config.Env}}' | grep -c JETON_ADMIN=
0
```

**Explications**

L'exercice mesure l'**outillage** autant que l'opérateur : avec le gabarit de CI (E21), le contrôle des images (E27), les normes (E33) et un `compose.yaml` de référence (E24), conteneuriser une petite application est une affaire de choix, pas de recherche. Chaque geste manuel de la feuille de temps est un manque à corriger (gabarit de projet, M28). Le secret en **fichier** (`_FICHIER`) n'apparaît ni dans `docker inspect` ni dans l'environnement des processus ; la variable directe (`MEDIANNUAIRE_JETON_ADMIN`) l'exposerait.

**Alternatives**
- Image finale *distroless* Python (`gcr.io/distroless/python3-debian13`) : plus petite et sans setuid, mais elle n'est pas dans la liste autorisée (exception à demander) et la version de Python est imposée par l'image.
- Lancer la recette sur `ctr02` en Quadlet (ADR-0120 : serveurs en Podman) : plus conforme à la cible, un peu plus long ; le dossier impose toutefois `ctr01` pour cet exercice (la vérification lit `docker inspect`).

**Pièges classiques**
- Passer la racine en lecture seule sans lire le README : refus de démarrer (cache).
- Jeton en variable d'environnement ou dans `compose.yaml`.
- Recette lancée avec une image **construite à la main** (exigence 4 : l'image vérifiée est celle du pipeline).
- `ETIQUETTES: "${CI_COMMIT_TAG:-main-…}"` dans le `.gitlab-ci.yml` : GitLab ne développe pas cette syntaxe du shell dans les variables, l'étiquette publiée est littéralement la chaîne écrite. Laisser le gabarit déduire les étiquettes de Git.
- Redéfinir `stages:` dans le projet sans `lint` : les jobs de `qualite.yml` et `.hadolint` n'ont plus de stage et le pipeline est refusé.
- `HEALTHCHECK` avec `curl` (absent de l'image) : sonde toujours en échec.
- Shell entre Docker et le processus (`CMD mediannuaire` en forme shell) : SIGTERM n'arrive pas, `docker stop` attend 10 s puis tue (code 137).

**En production chez MédiSphère**
Gabarit de projet (Dockerfile, `.dockerignore`, `compose.yaml`, `.gitlab-ci.yml`, entrée de sonde) généré par la plateforme développeurs (M28) ; MédiAnnuaire déployé ensuite sur Kubernetes (M14-M17) avec le même contrat (sondes, signaux, secrets en fichiers).
