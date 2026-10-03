# Module 00 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Pour les questionnaires (E01, E02, E05), chaque réponse est argumentée et les QCM expliquent pourquoi les autres options sont fausses. Pour les labs, la section **Solution** donne une démarche complète ; les fichiers de configuration complets sont dans [`fichiers/`](fichiers/).

Points non testés en conditions réelles au moment de la rédaction, à vérifier sur ta version et à signaler s'ils diffèrent : le paramètre `--bridge_vids` de l'API réseau (E09), le nom exact du chemin d'ACL `/sdn/zones/localnetwork/<bridge>` (E09), le comportement de l'`instance-id` cloud-init de Proxmox lors d'une modification de configuration (E12).

---

### M00-E01 — Test de positionnement Linux

**Barème** : chaque question vaut 2 points. 2 = réponse complète et justifiée ; 1 = idée juste mais incomplète (une cause sur deux, commande approximative, QCM juste sans justification) ; 0 = faux ou blanc. Total sur 50.

**Réponses argumentées**

**1. `df` à 100 %, `du` à 40 %.** `df` interroge le système de fichiers (blocs alloués) ; `du` additionne la taille des fichiers qu'il **voit** en parcourant l'arborescence. L'écart vient de blocs alloués à des fichiers invisibles pour `du` :
- *Fichiers supprimés mais encore ouverts* (cas le plus fréquent : un journal supprimé ou « roté » sans que le service ait rouvert son fichier). Confirmation : `lsof -nP +L1` (fichiers dont le nombre de liens est 0) ou `find /proc/*/fd -lname '*(deleted)' -printf '%p -> %l\n'`. Libérer sans redémarrer : recharger le service (`systemctl reload` ou `restart`), ou en dernier recours tronquer le descripteur : `: > /proc/<PID>/fd/<N>`.
- *Fichiers masqués par un montage* : des données écrites dans `/var/lib/xxx` **avant** qu'un autre système de fichiers soit monté par-dessus. Confirmation : `mount --bind /var /mnt/var-brut && du -sh /mnt/var-brut/lib/xxx` (le montage *bind* montre le répertoire sous-jacent, sans les montages imbriqués).
- *Instantanés* (ZFS, Btrfs) ou fichiers partagés par *reflink* : l'espace occupé par les snapshots n'apparaît pas dans `du`. Confirmation : `zfs list -o space`, `btrfs filesystem du`.
- `du` lancé sans les droits suffisants : il ignore ce qu'il ne peut pas lire (messages *Permission denied*).

**2. Réponse B (`df -i`).** « No space left on device » (ENOSPC) avec de l'espace libre signe presque toujours l'**épuisement des inodes** : des millions de petits fichiers (sessions, cache, file d'attente de courrier). Sur ext4, le nombre d'inodes est fixé à la création du système de fichiers ; XFS les alloue dynamiquement. A est faux : `fsck` exige de démonter et ne règle rien ici. C donne le type de système de fichiers, pas son remplissage. D est utile pour des erreurs d'E/S, mais pas comme premier réflexe pour ENOSPC. Remarque : un dépassement de quota donne un autre message (`Disk quota exceeded`).

**3. Load average élevé, CPU inactif.** Sous Linux, la charge compte les tâches **exécutables** (état `R`) **et** celles en **sommeil non interruptible** (état `D`), typiquement bloquées sur une E/S disque ou réseau (NFS). 24 tâches en `D` sur un stockage saturé ou un serveur NFS injoignable donnent une charge de 24 sans consommer de CPU. Identification : `ps -eo state,pid,wchan:32,cmd | awk '$1 ~ /D/'`, `vmstat 1` (colonne `b` = bloqués, `wa` = attente d'E/S), `iostat -x 1` (`%util`, `await`), `cat /proc/pressure/io` (PSI : temps passé en attente d'E/S), `cat /proc/<PID>/stack` pour voir où le noyau attend.

**4. `free` avec swap plein.** La colonne `available` (27 Gio) est l'estimation, par le noyau, de la mémoire utilisable sans recourir au swap : le cache (`buff/cache`) est en grande partie récupérable. Le serveur n'est donc pas à court **maintenant**. Ce qui inquiète : le swap est plein à 99 %, signe qu'il y a eu une forte pression mémoire. La vraie question est : y a-t-il encore des échanges actifs ? `vmstat 1` (colonnes `si`/`so` non nulles en continu = *thrashing*), `cat /proc/pressure/memory`, quels processus ont des pages en swap (`grep VmSwap /proc/*/status | sort -k2 -n`), historique OOM (`journalctl -k -g -i oom`). Spécificité Proxmox : le cache ARC de ZFS apparaît dans `used` et non dans `buff/cache` ; 98 Gio « utilisés » peuvent donc inclure un ARC récupérable (`arc_summary`).

**5. OOM killer.** Constat : `journalctl -k -g 'Out of memory|oom-kill'` (ou `dmesg -T`) montre `Out of memory: Killed process 1234 (postgres)` avec le détail de la mémoire. Choix de la victime : le noyau calcule un score (`/proc/<PID>/oom_score`) proportionnel à la mémoire du processus (RSS, swap, tables de pages), ajusté par `oom_score_adj` (de -1000 à +1000). Protection : `OOMScoreAdjust=-900` dans l'unité systemd (pas -1000 sans réfléchir : le noyau tuera alors autre chose, éventuellement plus critique), limiter les autres services (`MemoryMax=`), dimensionner correctement (`shared_buffers`, `work_mem`) ; pour un serveur PostgreSQL dédié, la documentation de PostgreSQL recommande `vm.overcommit_memory=2`. Dans un cgroup limité par `MemoryMax=`, l'OOM est **local** : le noyau tue un processus **du cgroup** quand celui-ci atteint sa limite, même s'il reste de la mémoire sur le système. Trace : `systemctl status` (« A process of this unit has been killed by the OOM killer »), compteur `oom_kill` dans `memory.events` du cgroup. C'est exactement ce qui se passe pour un conteneur Kubernetes en `OOMKilled` (module 14).

**6. Réponse D (`BindsTo=` + `After=`).** `BindsTo=` arrête l'unité dès que la dépendance **quitte l'état actif, pour quelque raison que ce soit**, y compris un plantage. `Requires=` (C) ne propage l'arrêt que si la dépendance est **explicitement** arrêtée ou redémarrée : un PostgreSQL qui plante laisse `app.service` tourner. `After=` seul (A) n'est qu'un ordre de démarrage, sans dépendance. `Wants=` (B) est une dépendance faible, sans propagation d'arrêt. Dans tous les cas, `After=` reste nécessaire : les dépendances (`Wants`, `Requires`, `BindsTo`) et l'ordre sont deux notions indépendantes dans systemd.

**7. journalctl.** (a) `journalctl -u nginx.service -b -p err` ; (b) `journalctl -b -1` ; (c) `journalctl -k --since "1 hour ago"` ; (d) `journalctl -f -u a.service -u b.service`. Pour (b), le journal doit être **persistant** : répertoire `/var/log/journal` présent ou `Storage=persistent` dans `journald.conf`. Vérification : `journalctl --list-boots` doit lister plusieurs démarrages.

**8. Modifier `ExecStart=`.** Jamais dans `/usr/lib/systemd/system/` (écrasé à la mise à jour du paquet). On crée une surcharge (*drop-in*) : `systemctl edit nginx.service` (fichier `/etc/systemd/system/nginx.service.d/override.conf`). Le piège : `ExecStart=` est une **liste** ; pour la remplacer, il faut d'abord la vider par une ligne `ExecStart=` vide, puis donner la nouvelle :
```ini
[Service]
ExecStart=
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;' -c /etc/nginx/autre.conf
```
Sans la ligne vide, systemd refuse l'unité (« more than one ExecStart= setting » pour un service non `oneshot`). `systemctl edit` recharge la configuration ; sinon `systemctl daemon-reload`. Contrôle : `systemctl cat nginx`, `systemd-delta`.

**9. Réponse B.** L'état `D` est un sommeil non interruptible dans le noyau, typiquement une E/S en cours (disque défaillant, NFS en montage `hard` dont le serveur ne répond plus). Le signal, même SIGKILL, n'est délivré qu'au retour de l'appel système. A est faux : SIGKILL ne peut être ni intercepté ni ignoré. C confond `D` et `Z`. D (SIGSTOP) n'y change rien. Remède : rétablir l'E/S (serveur NFS, chemin de stockage), sinon redémarrer. Pour un **zombie** (`Z`) : le processus est terminé, il ne reste qu'une entrée dans la table des processus en attente que son parent lise son code de retour (`wait()`). On ne « tue » pas un zombie : on corrige ou on tue le **parent** ; les zombies orphelins sont alors adoptés et nettoyés par `init` (PID 1). Quelques zombies sont inoffensifs ; des milliers signent un bogue du parent.

**10. Répertoire partagé.**
```
root@srv:~# chgrp compta /srv/echanges
root@srv:~# chmod 3770 /srv/echanges        # 2000 = setgid, 1000 = sticky, 770 = rwx pour propriétaire et groupe
root@srv:~# setfacl -m g:compta:rwX /srv/echanges
root@srv:~# setfacl -d -m g:compta:rwX /srv/echanges   # ACL par défaut, héritée par les nouveaux fichiers
```
Le **setgid** sur un répertoire fait hériter le groupe du répertoire aux nouveaux fichiers. Le **sticky bit** interdit de supprimer ou renommer un fichier dont on n'est pas propriétaire (comme `/tmp`). Le droit d'écriture du groupe sur les nouveaux fichiers ne vient pas du setgid : le `umask` habituel (022) produit des fichiers en 644. D'où l'**ACL par défaut**, qui s'impose indépendamment du `umask` de chaque utilisateur. Nuance : le sticky bit empêche la suppression, pas la modification du contenu, ce qui correspond à la demande.

**11. Réponses A et C.** A : `sudo` **ignore** les fichiers de `/etc/sudoers.d/` dont le nom contient un point ou se termine par `~` (sudoers(5)) : `admin.conf` n'est jamais lu. C : pour un même utilisateur, c'est la **dernière** règle correspondante qui l'emporte ; un fichier lu après le tien (ordre lexical) ou une règle placée plus loin peut annuler ton `NOPASSWD`. B n'est pas une cause : `sudo` refuse un fichier modifiable par le groupe ou les autres, ou n'appartenant pas à root, mais applique un fichier en 0644 (`visudo -c` le signale par « bad permissions, should be mode 0440 » : 0440 reste la convention). D est faux : `sudo` n'est pas un démon, il relit sa configuration à chaque appel. Bonne pratique : `visudo -cf <fichier>` avant l'installation, et un nom sans point (`90-workbook`).

**12. `Permission denied (publickey)`.** Côté client : `ssh -vvv admin@srv` montre les clés proposées et la réponse du serveur (la bonne clé est-elle proposée ? un agent avec trop de clés peut atteindre `MaxAuthTries` avant la bonne : `IdentitiesOnly yes` ; type de clé refusé, comme une vieille clé `ssh-rsa` signée en SHA-1 par un serveur OpenSSH récent). Côté serveur : les journaux (`journalctl -u ssh`) donnent souvent la cause exacte, par exemple `Authentication refused: bad ownership or modes for directory /home/admin`. Causes fréquentes : droits trop ouverts (`StrictModes` : répertoire personnel ou `~/.ssh` modifiable par le groupe, `authorized_keys` mal possédé), clé mal collée (coupée sur deux lignes, préfixe manquant), `AllowUsers`/`AllowGroups` restrictifs, `AuthorizedKeysFile` modifié, compte verrouillé ou expiré, contexte SELinux (familles RHEL). Pour un diagnostic poussé : `sshd -T` (configuration effective) et une instance de débogage `sshd -d -p 2222`.

**13. ProxyJump ou ForwardAgent.** Avec `ProxyJump` (`ssh -J bastion cible`), le client ouvre un canal TCP **à travers** le bastion et établit une session SSH **de bout en bout** avec la cible : la clé privée ne quitte jamais le poste, le bastion ne voit qu'un flux chiffré, et c'est le client qui vérifie la clé d'hôte de la cible. Avec `ForwardAgent`, le socket de l'agent est exposé sur le bastion : quiconque y est root (ou l'a compromis) peut utiliser ton agent pour s'authentifier partout où tes clés ouvrent des portes, tant que tu es connecté. Recommandation : `ProxyJump`, et l'agent transféré seulement vers des hôtes de confiance absolue, si jamais. Au module 06, le bastion utilisera des **certificats SSH** à courte durée de vie.

**14. Réponse B.** `apt upgrade` met à jour les paquets installés mais n'installe **jamais** de nouveau paquet et n'en supprime aucun. Or les mises à jour de Proxmox VE introduisent régulièrement de nouvelles dépendances (nouveau paquet de noyau versionné tiré par un méta-paquet, nouvelles bibliothèques) : `apt upgrade` les retient (*kept back*) et laisse un ensemble `pve-*` incohérent. A est à moitié vrai par effet de bord (le noyau est justement un nouveau paquet), mais ce n'est pas la raison de fond. C est faux : changer de version majeure exige de modifier les dépôts. D est faux.

**15. fstab et *emergency mode*.** systemd génère une unité de montage par ligne de `fstab`, requise par `local-fs.target`. Si le périphérique n'apparaît pas (disque débranché, UUID erroné, `/dev/sdb` devenu `/dev/sdc`), le démarrage attend (90 s par défaut) puis bascule en mode d'urgence. Ligne robuste : désigner le périphérique par `UUID=`, `LABEL=` ou `/dev/disk/by-id/…` ; option `nofail` (le démarrage continue sans ce montage) ; `x-systemd.device-timeout=10s` ; `_netdev` pour un système de fichiers réseau. Tester avant de redémarrer : `findmnt --verify`, `systemctl daemon-reload`, puis `mount /point` (ou `mount -a`). Et garder un accès console.

**16. Thin pool plein.** À 100 % de données, toute écriture dans un bloc non encore alloué échoue : erreurs d'E/S dans les VMs, systèmes de fichiers invités remontés en lecture seule, risque de corruption. Par défaut LVM met les E/S en file d'attente un moment avant de renvoyer l'erreur. Si ce sont les **métadonnées** du pool qui sont pleines, c'est pire : le pool peut nécessiter une réparation (`lvconvert --repair`). Surveillance : `lvs -o lv_name,data_percent,metadata_percent`, alerte à 80 %. Prévention : extension automatique (`thin_pool_autoextend_threshold` et `thin_pool_autoextend_percent` dans `lvm.conf`, à condition de garder de l'espace libre dans le groupe de volumes), `discard` sur les disques virtuels et `fstrim` dans les invités pour rendre les blocs libérés, sur-allocation raisonnée.

**17. Réponse B (XFS).** XFS ne peut que grandir. ext4 se réduit hors ligne (`resize2fs` sur un système démonté), Btrfs en ligne. D est donc faux. Conséquence : on crée des disques de VMs **petits** et on les agrandit au besoin (`qm disk resize` puis `growpart` et `resize2fs`/`xfs_growfs`, ou automatiquement par cloud-init). Proxmox ne sait de toute façon pas réduire un disque virtuel.

**18. `Too many open files`.** Limite effective : `cat /proc/<PID>/limits` (ligne *Max open files*), descripteurs ouverts : `ls /proc/<PID>/fd | wc -l`. Pour un service : `LimitNOFILE=65536` dans une surcharge (`systemctl edit`), puis redémarrage. `/etc/security/limits.conf` est appliqué par `pam_limits` lors des **sessions PAM** (connexion, SSH, `su`) ; un service lancé par systemd ne passe pas par PAM, il ne le voit donc pas. Avant d'augmenter, vérifie qu'il ne s'agit pas d'une **fuite** de descripteurs (`lsof -p <PID>` qui croît sans cesse).

**19. `set -euo pipefail`.** `-e` : le script s'arrête quand une commande simple échoue hors d'un contexte conditionnel. `-u` : l'expansion d'une variable non définie est une erreur. `-o pipefail` : le code de retour d'un tube est celui de la dernière commande en échec (et non celui de la dernière commande). Pièges de `-e` : il est désactivé dans les conditions (`if`, `while`, `&&`, `||`, `!`) **et dans toutes les fonctions appelées depuis ces contextes** ; `local v=$(cmd)` ou `export v=$(cmd)` masque l'échec de `cmd` (on obtient le code de `local`) ; `((i++))` quand `i` vaut 0 renvoie 1 et arrête le script ; avec `pipefail`, un `grep` qui ne trouve rien (code 1) dans un tube arrête le script alors que c'est un résultat normal. C'est pour cela que les scripts de vérification du workbook n'utilisent que des fonctions qui encapsulent les tests.

**20. Script de purge.** Défauts : (1) `$DIR` ni vérifié ni protégé : vide, la boucle porte sur `/*.csv` ; (2) `$(ls …)` découpe les noms sur les espaces et les retours à la ligne ; (3) `$f` non protégé dans `stat` et `rm` ; (4) s'il n'y a aucun CSV, le motif littéral `…/*.csv` est passé à `stat` (erreur) ; (5) `rm` sans `--` (un nom commençant par `-` devient une option) ; (6) ni `set -euo pipefail`, ni journal, ni simulation ; (7) `[ $(stat …) -lt … ]` casse si `stat` échoue (opérande vide). Version correcte :
```bash
#!/usr/bin/env bash
set -euo pipefail
dir="${1:?Usage : $0 <dossier>}"
[[ -d "$dir" ]] || { echo "Dossier introuvable : $dir" >&2; exit 1; }
# -mtime +30 : modifiés il y a plus de 30 jours complets. Tester d'abord sans -delete.
find "$dir" -maxdepth 1 -type f -name '*.csv' -mtime +30 -print -delete
```

**21. `ss -tlnp`.** Joignables depuis le réseau : `sshd` (toutes les adresses IPv4), `nginx` (`*:80` : toutes les adresses IPv4 et IPv6), `java` (uniquement sur 10.0.0.5). Non joignables : PostgreSQL (127.0.0.1) et le résolveur local de systemd (127.0.0.53, interface `lo`). Sous réserve, bien sûr, du pare-feu. Dernière ligne : pour un socket en écoute, `Recv-Q` est la longueur de la **file d'acceptation** (connexions établies que l'application n'a pas encore acceptées) et `Send-Q` sa taille maximale (*backlog*). 129 > 128 : la file est pleine, l'application n'appelle plus `accept()` assez vite (threads bloqués, pause du ramasse-miettes, pool épuisé). Les nouveaux SYN sont ignorés : les clients voient des délais d'attente. Confirmation : `nstat -az TcpExtListenOverflows` qui augmente.

**22. Processus figé.** `ps -o pid,stat,wchan:32,cmd -p <PID>` (état et fonction du noyau où il attend) ; `cat /proc/<PID>/stack` (pile noyau, en root) ; `strace -f -p <PID>` (appel système en cours, par exemple `read(5, …` : puis `ls -l /proc/<PID>/fd/5` ou `lsof -p <PID>` pour savoir quel fichier ou socket est le descripteur 5) ; `ss -tnp` pour ses connexions ; outils applicatifs (`py-spy dump`, `jstack`, `gdb -p`) ; `perf top -p <PID>` s'il consomme du CPU.

**23. cron ou timer systemd.** Critères : journaux (le timer exécute une unité dont la sortie et le code de retour vont au journal ; cron envoie un courrier, souvent perdu) ; exécutions manquées (`Persistent=true` rattrape une exécution manquée pendant un arrêt ; cron l'oublie, sauf anacron) ; chevauchement (un timer ne relance pas l'unité si elle tourne encore ; avec cron il faut `flock`) ; contrôle des ressources (`Nice=`, `IOSchedulingClass=`, `CPUQuota=`, `MemoryMax=`) ; dépendances (`After=`, `Requires=`, par exemple un montage) ; étalement (`RandomizedDelaySec=` évite que tous les serveurs purgent à 00:00 pile) ; alerte (`OnFailure=`) ; observabilité (`systemctl list-timers` donne la dernière et la prochaine exécution) ; environnement maîtrisé (cron a un `PATH` minimal, source classique de surprises). Pour cron : une ligne, universel, connu de tous. Choix : timer systemd en production sur un hôte systemd.

**24. Paramètre de module noyau.** Valeur courante : `/sys/module/<module>/parameters/<paramètre>` ; paramètres disponibles : `modinfo -p kvm_intel`. Persistance : un fichier `/etc/modprobe.d/<nom>.conf` avec `options kvm_intel nested=Y`. Prise en compte : au prochain chargement du module (`modprobe -r kvm_intel && modprobe kvm_intel`, impossible tant qu'une VM tourne) ou au redémarrage. Il faut régénérer l'initramfs (`update-initramfs -u -k all`) quand le module est chargé **depuis l'initramfs**, tôt au démarrage : pilotes de stockage, `zfs` (par exemple `zfs_arc_max`), `vfio-pci` pour le *passthrough*. Ce n'est pas le cas de `kvm_intel`. Sur un Proxmox démarré par `proxmox-boot-tool`, la copie vers les partitions ESP se fait par un *hook* ; `proxmox-boot-tool refresh` la force.

**25. Temps.** Ce qui casse sans heure juste : validation des certificats TLS (dates de validité), Kerberos/Active Directory (tolérance de 5 minutes par défaut), systèmes distribués (moniteurs Ceph : alerte *clock skew* au-delà de 0,05 s ; baux et élections d'etcd), codes TOTP (fenêtres de 30 s), jetons à durée de vie (JWT `exp`/`nbf`), corrélation des journaux entre machines pendant un incident, ordonnancement des sauvegardes et des rétentions. Vérification avec chrony : `chronyc tracking` (*Leap status : Normal*, décalage faible, source de référence), `chronyc sources -v` (la source sélectionnée est marquée `^*`), `timedatectl` (*System clock synchronized: yes*).

**Grille d'auto-évaluation**

| Score /50 | Lecture | Conseil |
|---|---|---|
| 42 à 50 | Niveau solide d'administrateur de production | Survole les rappels, concentre-toi sur les sections « Pièges classiques » et « En production » des corrigés. |
| 30 à 41 | Bon niveau, lacunes ciblées | Retravaille les thèmes où tu as perdu des points (tableau ci-dessous) **avant** les modules indiqués. |
| 20 à 29 | Bases à consolider | Avance dans le module 00, mais prévois une remise à niveau sur les thèmes faibles avant le module 02. |
| Moins de 20 | Écart important avec le prérequis du workbook | Prends deux à trois semaines de remise à niveau (ressources ci-dessous), puis refais le test. |

| Thème | Questions | Où il est mobilisé |
|---|---|---|
| Stockage et systèmes de fichiers | 1, 2, 15, 16, 17 | M00-E07, E44, E48 ; M08 (Ceph, ZFS) ; M16 |
| Processus, mémoire, performance | 3, 4, 5, 9, 22 | M00-E48 ; M14 (OOM des pods) ; M21 (métriques) |
| systemd et journaux | 6, 7, 8, 18, 23 | M03 ; M04 (services, handlers) ; M12 (Quadlet) ; M22 (journald) |
| Droits, sudo, SSH | 10, 11, 12, 13 | M00-E10, E15, E27 ; M06 (bastion, certificats SSH) ; M24 |
| Paquets, noyau, temps | 14, 24, 25 | M00-E06, E31, E34 ; M09 |
| Shell | 19, 20, 21 | M02 (Bash avancé, ShellCheck, bats) |

Ressources : *Debian Administrator's Handbook* (<https://debian-handbook.info/>) ; pages de manuel `systemd.unit(5)`, `systemd.exec(5)`, `systemd.resource-control(5)` ; site de Brendan Gregg sur la performance Linux et la méthode USE (<https://www.brendangregg.com/linuxperf.html>) ; *BashFAQ* et *BashPitfalls* du wiki de Greg (<https://mywiki.wooledge.org/BashPitfalls>) ; wiki de ShellCheck ; documentation du noyau sur PSI (`Documentation/accounting/psi.rst`).

---

### M00-E02 — Test de positionnement réseau

**Barème** : 2 points par question (2 = complet et justifié, 1 = partiel, 0 = faux ou blanc). Total sur 48.

**Réponses argumentées**

**1. Réponse B.** Un /23 regroupe deux /24 alignés : 10.10.40.0 à 10.10.41.255, soit 510 adresses d'hôtes. 10.10.41.0 est une adresse d'hôte **valide** (ce n'est ni l'adresse de réseau ni la diffusion). A correspond à un /24, C au second /24 seul, D à un /26. Remarque : dans le plan MédiSphère, 10.10.41.0/24 est le VLAN 41 ; un /23 sur le VLAN 40 chevaucherait K8S-LB. C'est pour cela que le plan découpe en /24.

**2. Passerelle hors sous-réseau.** Linux refuse d'installer une route via une passerelle qui n'est pas joignable directement (`Error: Nexthop has invalid gateway`) : l'interface monte, mais **sans route par défaut** (l'erreur est dans les journaux de démarrage). (a) 10.10.20.10 est sur le lien : la machine résout son adresse MAC par ARP et le ping fonctionne. (b) Aucune route ne correspond à 9.9.9.9 : `connect: Network is unreachable` immédiatement, aucun paquet ne part. Si on force la route avec l'option `onlink`, la machine fait des requêtes ARP pour 10.10.2.1 sur le segment, sans réponse : `Destination Host Unreachable` après quelques secondes.

**3. Plus long préfixe.** 10.10.20.10 → `10.10.20.0/24 via 192.168.1.41` (le /24 est plus spécifique que le /16). 10.10.99.5 → `10.10.0.0/16 via 192.168.1.40`. 10.20.10.10 → **route par défaut, vers la box** : aucune route plus précise. Le paquet part vers Internet et se perd (adresse privée). C'est pourquoi l'E10 ajoute aussi 10.20.0.0/16 sur `pve01`. 192.168.1.40 → réseau directement connecté, résolution ARP directe. Commande : `ip route get 10.10.20.10` (route, interface et adresse source choisies, sans émettre de paquet). Les règles de routage par politique (`ip rule`) sont évaluées avant les tables.

**4. Bridge VLAN-aware.** Chaque port du bridge a une liste de VLANs autorisés. Le **PVID** est le VLAN attribué aux trames **non étiquetées** reçues sur ce port ; *egress untagged* signifie que les trames de ce VLAN sortent du port **sans** étiquette. Pour une VM avec `tag=20`, Proxmox configure son port (`tap`) en `vid 20 pvid untagged` : la VM émet et reçoit sans étiquette, le bridge la place dans le VLAN 20. Pour une VM sans tag (comme `net1` de `gw01`), le port reçoit les VLANs de `bridge-vids` **étiquetés**, plus le VLAN 1 en PVID non étiqueté : une trame non étiquetée émise par `gw01` atterrit donc dans le VLAN 1, inutilisé par le plan. Une VM `tag=20` ne voit pas le trafic du VLAN 30 : le bridge filtre en sortie selon l'appartenance aux VLANs. Attention : sur un bridge **non** VLAN-aware, aucune étiquette n'est filtrée, et une VM peut injecter des trames étiquetées dans un autre VLAN (*VLAN hopping*).

**5. Réponse B.** Les deux machines répondent tour à tour aux requêtes ARP ; les caches des voisins basculent d'une MAC à l'autre, d'où des connexions qui marchent puis se figent. Confirmation : `ip neigh show 10.10.20.10` répété sur un voisin, `arping -D -I ens18 <IP>` (détection de doublon : une réponse signifie qu'une autre machine détient l'adresse), `tcpdump -e -n arp`. A est faux (les deux répondent par intermittence), C aussi (un switch ne s'occupe pas des adresses IP, sauf fonctions de sécurité spécifiques), D aussi pour IPv4 : le noyau n'y détecte pas les doublons (contrairement à IPv6 et sa procédure DAD) ; certains gestionnaires réseau le font en option.

**6. Routage asymétrique.** Un pare-feu à états crée une entrée de suivi au premier paquet (SYN) et attend la suite **dans les deux sens**. Si le SYN-ACK revient par un autre chemin, le pare-feu voit l'ACK du client sans avoir vu le SYN-ACK : le paquet est jugé `invalid` et rejeté ; sur l'autre chemin, un SYN-ACK sans SYN est tout aussi invalide. Toutes les routes peuvent être « correctes » individuellement : c'est leur combinaison qui est asymétrique. Sur un routeur Linux, le **filtrage par chemin inverse** (`rp_filter=1`, strict) rejette aussi un paquet reçu sur une interface qui n'est pas celle par laquelle le noyau joindrait sa source. Diagnostic : `tcpdump` sur les deux chemins, `conntrack -E`, compteurs des règles `invalid`, `nstat` (*IPReversePathFilter*).

**7. Réponse B.** `masquerade` traduit vers l'adresse de l'interface de sortie, déterminée au moment de la connexion, et purge les connexions traduites quand l'interface tombe : idéal pour une adresse dynamique. `snat to <adresse>` utilise une adresse fixe, un peu moins coûteuse, indispensable pour choisir une adresse précise ou une plage. A et C sont faux. D aussi : toute traduction d'adresse repose sur le suivi de connexion (c'est lui qui retraduit les réponses).

**8. Timeout ou refus.** *Timed out* : le SYN n'obtient **aucune** réponse ; il est jeté quelque part (règle `drop` sur le chemin ou sur l'hôte, trou noir de routage, hôte éteint sans qu'un routeur renvoie d'ICMP). *Refused* : un RST revient ; l'hôte est joignable mais rien n'écoute sur ce port (ou un pare-feu répond par `reject with tcp reset`). On préfère `reject` à l'intérieur du réseau : échec immédiat, diagnostic plus simple, pas d'applications bloquées de longues secondes. On garde `drop` en bordure d'Internet pour le trafic non sollicité (pas de réponse à des balayages, pas de réflexion), en sachant que la « furtivité » apportée est faible.

**9. Bloquer tout l'ICMP.** Arguments : (1) la découverte de MTU (PMTUD) repose sur l'ICMP *fragmentation needed* (IPv4) et *packet too big* (IPv6) : sans eux, des connexions se figent dès qu'un lien a une MTU réduite (tunnels, VPN) ; (2) IPv6 ne fonctionne pas sans ICMPv6 : la découverte de voisins (NDP) remplace ARP (RFC 4890) ; (3) le diagnostic (`ping`, `traceroute`) et la supervision en dépendent, et les messages *unreachable* permettent des échecs rapides au lieu de délais d'attente ; (4) le gain de sécurité est quasi nul : les attaques ICMP célèbres sont historiques, et on limite le débit plutôt que de tout bloquer. Politique raisonnable : accepter les ICMP liés à une connexion connue (`ct state related`) ; accepter `echo-request` avec limitation de débit ; accepter les types 3, 11 et 12 en IPv4 ; en IPv6, les types 1 à 4, 128/129 limités, et 133 à 136 (NDP) ; refuser les redirections (5 en IPv4, 137 en IPv6).

**10. Trou noir PMTUD.** Le tunnel ajoute un en-tête : la MTU du chemin descend sous 1500. Les petits paquets (établissement de session, échanges interactifs) passent ; les gros paquets marqués *Don't Fragment* (le certificat du serveur dans la négociation TLS, une longue sortie de `ls`) dépassent la MTU. Le routeur devrait renvoyer un ICMP *fragmentation needed*, mais il est filtré ou jamais émis : l'émetteur retransmet indéfiniment le même gros segment. Preuve : `ping -M do -s 1472 <destination>` (1472 + 28 octets d'en-têtes = 1500) échoue alors que `ping -M do -s 1392` passe ; on cherche la plus grande taille qui passe, ou `tracepath <destination>`. Corrections : *MSS clamping* sur le routeur du tunnel (nftables : `tcp flags syn tcp option maxseg size set rt mtu`) ; MTU cohérente sur les interfaces concernées ; laisser passer les ICMP nécessaires. Le *clamping* ne corrige que TCP. C'est le sujet de la panne M00-E41.

**11. Réponse C.** `CLOSE_WAIT` : le pair a fermé (FIN reçu et acquitté par le noyau), le noyau attend que l'**application locale** ferme son socket. Des milliers de `CLOSE_WAIT` signent une fuite de sockets dans l'application (connexions jamais fermées, pool défaillant). A est faux : c'est justement parce que le client a fermé qu'on est en `CLOSE_WAIT`. B est faux : un FIN perdu ne produit pas cet état. D confond avec `TIME_WAIT`, état normal du côté qui ferme en premier (60 s sous Linux), sans conséquence sauf à très fort débit de connexions sortantes. Diagnostic : `ss -tanp state close-wait`.

**12. SYN sans réponse.** Le SYN est retransmis à 1 s puis 2 s d'intervalle (temporisation exponentielle) sans SYN-ACK ni RST : le paquet (ou sa réponse) est jeté quelque part. Ensuite, on capture **le long du chemin** : sur `gw01`, interface `ens19.10` (le SYN arrive-t-il ?), puis `ens19.20` (est-il routé ?), puis sur `dns01` ; en parallèle, compteurs nftables et `nft monitor trace`. Si le port était simplement fermé sur un serveur joignable, on verrait immédiatement `Flags [R.]` venant de 10.10.20.10 (connexion refusée), ou un ICMP *port unreachable*/*admin prohibited* en cas de `reject`.

**13. tcpdump.** (a) `tcpdump -i ens19 -nn -e 'vlan 20 and port 53'` : `-e` affiche l'en-tête de liaison, donc l'étiquette 802.1Q, et la primitive `vlan 20` doit précéder les autres car elle décale les offsets du filtre. (b) `tcpdump -i ens19.20 -nn 'not port 22'` (`-nn` : ni résolution de noms, ni de ports). (c) `tcpdump -i ens19.20 -nn -w /var/tmp/capture.pcap -C 100 -W 10` : 10 fichiers tournants de 100 millions d'octets. Attention : `tcpdump` abandonne ses privilèges en cours de route ; écris dans un répertoire où l'utilisateur `tcpdump` peut écrire.

**14. DNS.** Un serveur **faisant autorité** détient les données d'une zone et y répond avec le drapeau `aa` (dnsmasq pour `par1.medisphere.internal`, PowerDNS au module 06). Un **résolveur récursif** répond aux clients en interrogeant la hiérarchie (racine, TLD, serveurs faisant autorité) et met les réponses en cache. Le **TTL** est la durée pendant laquelle une réponse peut être gardée en cache. Le **cache négatif** (RFC 2308) conserve aussi les réponses `NXDOMAIN`/`NODATA`, pour une durée tirée de l'enregistrement SOA de la zone. Un client qui a demandé le nom **avant** sa création garde donc `NXDOMAIN` jusqu'à expiration de ce TTL négatif, dans chaque cache traversé (résolveur, systemd-resolved, cache applicatif). Remède : attendre, vider les caches (`resolvectl flush-caches`, redémarrer dnsmasq), et réduire le TTL négatif avant des changements prévus.

**15. Réponse B.** `dig` interroge directement le serveur de `/etc/resolv.conf` (ou celui donné par `@`) et contourne NSS. `curl` utilise `getaddrinfo()`, donc NSS : `/etc/nsswitch.conf` (`hosts: files dns`, ou `resolve` pour systemd-resolved, voire `mdns4_minimal [NOTFOUND=return]` qui court-circuite `.local`), `/etc/hosts`, les domaines de recherche et `ndots`, la configuration DNS par interface de systemd-resolved. Diagnostic : `getent ahosts <nom>`, `resolvectl query <nom>`. A, C et D sont faux.

**16. Résolution inverse.** Nom : `10.20.10.10.in-addr.arpa.` (octets inversés), de type PTR, pointant vers `dns01.par1.medisphere.internal.`, dans la zone `20.10.10.in-addr.arpa`. Problèmes typiques : connexions SSH lentes si `UseDNS yes` et que la requête inverse attend un délai ; serveurs de courrier qui refusent un émetteur sans PTR cohérent ; Kerberos et certains services qui canonicalisent les noms ; journaux illisibles ; `traceroute` lent ; requêtes inverses de plages privées qui fuient vers Internet sans réponse (d'où l'option `bogus-priv` de dnsmasq).

**17. DHCP et relais.** DORA : *Discover* (le client, sans adresse, diffuse de 0.0.0.0:68 vers 255.255.255.255:67), *Offer* (le serveur propose), *Request* (le client accepte une offre, en diffusion), *Ack* (le serveur confirme). Une diffusion ne traverse pas un routeur : un serveur dans un autre VLAN ne voit jamais le *Discover*. Le **relais**, sur l'interface du routeur côté clients (`gw01`, `ens19.99`), capte ces diffusions et les retransmet en unicast au serveur, en renseignant **`giaddr`** avec sa propre adresse dans le VLAN des clients (10.10.99.1). Le serveur s'en sert pour choisir la plage (10.10.99.0/24) et répond au relais, qui transmet au client. L'option 82 permet au relais d'ajouter des informations de circuit. Au renouvellement (T1), le client écrit **directement** au serveur en unicast : ce flux est routé, pas relayé, et le pare-feu doit le permettre (E14).

**18. IPv6 en arrière-plan.** (a) Une VM branchée par erreur sur `vmbr0` reçoit une adresse IPv6 globale par SLAAC : elle est joignable et peut sortir en IPv6 **sans passer par `gw01`**, en contournant tout le filtrage IPv4. Les applications préfèrent souvent IPv6 : chemins inattendus. (b) Si `gw01` rejette l'ICMPv6 en `input`, la découverte de voisins ne fonctionne plus sur `ens18` : IPv6 cassé sur le WAN, annonces de routeur ignorées. Effet visible : des outils qui tentent d'abord l'adresse AAAA (APT, `curl`) attendent un délai avant de revenir à IPv4.

**19. Réponse B.** LACP répartit **par flux** : avec `layer3+4`, le hachage porte sur les adresses et les ports ; un flux TCP unique reste sur un seul lien, donc 10 Gb/s au maximum. Le débit agrégé de 20 Gb/s n'est atteint qu'avec de nombreux flux. A est faux (pas de répartition par paquet, qui provoquerait du réordonnancement), C aussi, et D aussi : chaque extrémité choisit le lien de **ses** émissions par son propre hachage.

**20. Boucles.** Une trame Ethernet n'a pas de TTL : une diffusion prise dans une boucle est recopiée indéfiniment par chaque commutateur (*broadcast storm*), sature liens et processeurs en quelques secondes, et les tables MAC oscillent : tout le domaine de niveau 2 tombe. Un paquet IP porte un TTL décrémenté à chaque saut : dans une boucle de routage, il meurt au bout de 64 à 255 sauts ; seules les destinations concernées souffrent. Proxmox met `bridge-stp off` parce que ses bridges sont des « feuilles » (des VMs et un seul lien montant) sans chemin redondant, et que STP ajouterait un délai de convergence et pourrait interagir avec le STP du réseau physique. Il faudrait l'activer si le bridge reliait deux ports physiques au même réseau sans agrégation (mieux : un *bond*), ou si une VM pontait deux bridges.

**21. OSPF ou BGP.** Dans un datacenter moderne en *leaf-spine*, BGP (souvent eBGP, un AS par commutateur, RFC 7938) : politiques fines, domaines de panne simples, passage à l'échelle. OSPF reste pertinent dans des réseaux de taille moyenne. eBGP : sessions entre systèmes autonomes différents, le *next-hop* est réécrit. iBGP : sessions au sein d'un même AS, maillage complet ou réflecteurs de routes, *next-hop* conservé par défaut. Les IP de services Kubernetes sont **dynamiques** (créées, supprimées, déplacées d'un nœud à l'autre en cas de panne) : les annoncer en BGP depuis les nœuds (MetalLB, Cilium) met à jour le routage automatiquement et permet l'ECMP ; une route statique pointerait vers un seul nœud, sans bascule.

**22. VRRP.** Les routeurs d'un groupe élisent un maître selon leur priorité ; le maître porte l'adresse virtuelle et émet des annonces périodiques (multicast 224.0.0.18, protocole IP 112). Si un secondaire ne reçoit plus d'annonce pendant l'intervalle de détection (environ trois intervalles), il devient maître, configure l'adresse virtuelle et émet des **ARP gratuits** (et des annonces de voisin non sollicitées en IPv6) pour que voisins et commutateurs mettent à jour leurs tables. *Split-brain* : les deux routeurs se croient maîtres parce que les annonces ne passent plus (pare-feu qui bloque VRRP, lien coupé entre eux, VLAN mal configuré) : adresse en double, ARP qui oscille, trafic intermittent. Parades : laisser passer VRRP, annonces en unicast entre pairs, scripts de suivi, supervision de l'état.

**23. WireGuard.** *Cryptokey routing* : chaque pair est identifié par sa clé publique et associé à une liste `AllowedIPs`. En **émission**, l'adresse de destination du paquet est cherchée dans les `AllowedIPs` de tous les pairs (préfixe le plus long) : cela choisit le pair, donc la clé de chiffrement. En **réception**, après déchiffrement, l'adresse **source** du paquet interne doit appartenir aux `AllowedIPs` du pair émetteur, sinon il est jeté : c'est une liste de contrôle anti-usurpation. `AllowedIPs` ne crée pas de routes dans le noyau ; c'est `wg-quick` qui les ajoute. WireGuard n'a pas de notion de connexion : un pair derrière un NAT n'est joignable que tant que la correspondance NAT existe. `PersistentKeepalive = 25` envoie un paquet vide toutes les 25 s pour la maintenir ouverte.

**24. VM sans Internet.** Il n'y a **pas de route par défaut** : seule 10.10.20.0/24 est joignable (`ping 9.9.9.9` répondrait `Network is unreachable`). Cause probable : passerelle absente de la configuration (`gw=` manquant dans `ipconfig0` cloud-init). Si la route était présente et qu'Internet restait inaccessible, dans l'ordre : (1) `ping -c2 9.9.9.9`, qui teste le routage et le NAT de `gw01` (sinon : `ip_forward`, règles `forward`, `masquerade`, compteurs nftables) ; (2) `dig deb.debian.org` puis `getent hosts deb.debian.org`, qui testent la résolution DNS (résolveur configuré, joignable, autorisé) ; (3) `curl -v https://deb.debian.org`, qui teste la couche applicative (proxy, TLS, heure, MTU). On remonte les couches : réseau, puis DNS, puis application.

**Grille d'auto-évaluation**

| Score /48 | Lecture | Conseil |
|---|---|---|
| 40 à 48 | Niveau solide | Les pannes du palier 4 (E38 à E46) seront ton terrain de jeu. |
| 29 à 39 | Bon niveau, lacunes ciblées | Retravaille les thèmes faibles avant les exercices indiqués ci-dessous. |
| 19 à 28 | Bases à consolider | Fais l'E10 lentement, en capturant le trafic (`tcpdump`) à chaque étape, et reprends les thèmes faibles avant le module 07. |
| Moins de 19 | Écart important avec le prérequis | Remise à niveau réseau (ressources ci-dessous) avant d'aller au-delà de l'E10. |

| Thème | Questions | Où il est mobilisé |
|---|---|---|
| Adressage et routage | 1, 2, 3, 24 | M00-E10, E47 ; M07 |
| Niveau 2 : VLAN, ARP, agrégation, STP | 4, 5, 19, 20 | M00-E09, E28 ; M07 (bonding, Open vSwitch) |
| Filtrage, NAT, ICMP | 6, 7, 8, 9 | M00-E10, E26, E38 ; M07 ; M26 |
| TCP, MTU, capture | 10, 11, 12, 13 | M00-E41, E47 ; M07 (MTU, jumbo frames) ; M15 (Hubble) |
| DNS et DHCP | 14, 15, 16, 17 | M00-E13, E14, E40 ; M06 (PowerDNS, Kea) |
| IPv6 | 18 | M00-E10 ; M07 |
| Routage dynamique, haute disponibilité, VPN | 21, 22, 23 | M00-E16, E21, E43 ; M07 (FRR, keepalived, WireGuard) ; M15 (BGP de Cilium) |

Ressources : pages de manuel `ip-route(8)`, `tcpdump(1)`, `pcap-filter(7)`, `nft(8)` ; wiki nftables (<https://wiki.nftables.org/>) ; RFC 2131 (DHCP), RFC 2308 (cache négatif), RFC 4890 (filtrage ICMPv6), RFC 7938 (BGP dans le datacenter) ; livre blanc de WireGuard (<https://www.wireguard.com/papers/wireguard.pdf>) ; *TCP/IP Illustrated, Volume 1* (Fall et Stevens) pour une remise à niveau de fond.

---
### M00-E03 — Inventaire de l'existant sur `pve01`

**Solution**

Un exemple d'inventaire complet (fictif) est fourni : [`fichiers/M00-E03/inventaire-exemple.md`](fichiers/M00-E03/inventaire-exemple.md). Commandes de collecte, toutes en lecture seule, section par section :

*1. Proxmox VE*
```
root@pve01:~# pveversion ; pveversion -v | head -n 8
root@pve01:~# grep -E 'PRETTY_NAME|VERSION_CODENAME' /etc/os-release ; uname -r
root@pve01:~# hostname ; pvecm status
root@pve01:~# pvesubscription get
root@pve01:~# ls -l /etc/apt/sources.list /etc/apt/sources.list.d/ ; apt-cache policy | grep -E 'proxmox|debian'
root@pve01:~# pve-firewall status
```
`pvecm status` en erreur (« corosync.conf does not exist ») signifie que le nœud est autonome.

*2. Matériel*
```
root@pve01:~# lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Core|Virtualization'
root@pve01:~# free -g ; cat /sys/module/kvm_intel/parameters/nested
root@pve01:~# grep -E 'MemTotal|MemAvailable' /proc/meminfo
```

*3. Disques et stockages* — trois vues à croiser :
```
root@pve01:~# lsblk -o NAME,SIZE,TYPE,ROTA,TRAN,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
root@pve01:~# ls -l /dev/disk/by-id/ | grep -v -e part -e wwn-
root@pve01:~# pvs ; vgs ; lvs -a
root@pve01:~# zpool status ; zfs list -o name,used,avail,mountpoint
root@pve01:~# findmnt -t ext4,xfs,zfs,vfat
root@pve01:~# wipefs -n /dev/disk/by-id/<DISQUE>        # -n : liste les signatures SANS rien effacer
root@pve01:~# cat /etc/pve/storage.cfg ; pvesm status
root@pve01:~# smartctl -a /dev/nvme0 | grep -iE 'percentage used|media|critical'
```
La conclusion « réaffectable » exige que les trois vues soient vides : pas de partition ni de signature (`lsblk`, `wipefs -n`), pas d'appartenance à LVM ou ZFS (`pvs`, `zpool status`), aucune référence dans `storage.cfg` ni dans `findmnt`.

*4. Réseau*
```
root@pve01:~# ip -br link ; ip -br addr ; ip route
root@pve01:~# cat /etc/network/interfaces ; bridge link
root@pve01:~# cat /etc/resolv.conf ; grep "$(hostname)" /etc/hosts
root@pve01:~# ethtool <CARTE> | grep -E 'Speed|Link detected'
```
La plage DHCP de la box se lit dans son interface d'administration.

*5. VMs et conteneurs*
```
root@pve01:~# qm list ; pct list
root@pve01:~# pvesh get /cluster/resources --type vm --output-format json-pretty
root@pve01:~# grep -H -E '^(onboot|memory|scsi|virtio|sata|ide)[0-9]*:' /etc/pve/qemu-server/*.conf
root@pve01:~# cat /etc/pve/jobs.cfg 2>/dev/null ; ls /etc/pve/lxc/
```
Repérage des conflits de VMID :
```
root@pve01:~# pvesh get /cluster/resources --type vm --output-format json \
    | perl -MJSON::PP -0777 -ne 'for (@{decode_json($_)}) { my $v = $_->{vmid};
      print "$v $_->{name} : CONFLIT\n" if ($v >= 1000 && $v <= 3999) || ($v >= 5000 && $v <= 5999) || ($v >= 9000 && $v <= 9099) }'
```

*6. Ressources libres* : somme de la RAM des VMs perso à démarrage automatique (`onboot: 1`), soustraite de la RAM totale, moins une réserve pour l'hôte (8 à 10 Gio, plus l'ARC si ZFS). Espace libre : `pvesm status`, `vgs` (colonne `VFree`), `zpool list`.

**Explications**

Un inventaire n'a de valeur que s'il est **reproductible** (chaque information a sa commande) et **conclusif** (il dit ce qu'on peut faire, pas seulement ce qui existe). Proxmox VE a ses outils, mais reste un Debian : on croise systématiquement la vue Proxmox (`storage.cfg`, `qm`) avec la vue système (`lsblk`, LVM, ZFS), car l'une peut ignorer ce que fait l'autre. Un disque peut porter des données sans être déclaré dans Proxmox (montage manuel), ou être déclaré dans Proxmox sans être monté.

La section 7 (« Valeurs du lab ») est la pierre angulaire du workbook : chaque `<VALEUR>` des énoncés y renvoie. Garde-la à jour.

**Alternatives**

- `pvereport` génère un rapport texte très complet de l'hôte (configuration, stockage, réseau, VMs). Excellent pour une collecte, trop brut pour un document de décision.
- `pvesh get … --output-format json` et `jq` pour des extractions scriptables : c'est la base du script demandé en « Pour aller plus loin », et le premier pas vers un inventaire automatique (module 02), puis NetBox comme source de vérité (module 06).

**Pièges classiques**

- Lancer `wipefs` **sans** `-n` : il efface les signatures. En inventaire, toujours `-n`.
- Identifier les disques par `/dev/sdX` : l'ordre peut changer au redémarrage. Note le chemin `/dev/disk/by-id/` et le numéro de série.
- Conclure « vierge » parce qu'un disque n'apparaît pas dans `pvesm status` : il peut être monté à la main, membre d'un pool ZFS importé ailleurs, ou porter une partition NTFS.
- Oublier les **conteneurs** (`pct list`) dans le recensement des VMID : ils partagent le même espace de numérotation que les VMs.
- Copier dans l'inventaire des secrets (mots de passe de stockages CIFS, jetons) : `storage.cfg` n'en contient pas, mais certaines sorties de commandes ou notes personnelles si. Le fichier est ignoré par git, ce n'est pas une raison pour y mettre des secrets.

**En production chez MédiSphère**

L'inventaire manuel est un état des lieux de départ. En production, l'inventaire est **automatique et central** : NetBox (module 06) comme source de vérité (équipements, adresses, VMs), alimenté et vérifié par Ansible (module 04). Chaque écart entre la réalité et NetBox est une anomalie traitée. Le document humain reste pour ce qui ne se collecte pas : contraintes, décisions, contacts.

---

### M00-E04 — Sauvegarde vérifiée des photos de `hp01`

**Solution**

*1. État des lieux sur `hp01`*
```
root@hp01:~# cat /etc/os-release ; df -h
root@hp01:~# du -sh /srv/photos ; find /srv/photos -type f | wc -l
root@hp01:~# find /srv/photos -type l | head          # liens symboliques : vers quoi pointent-ils ?
root@hp01:~# find /srv/photos -newermt '-1 day' | head # fichiers modifiés récemment : un logiciel écrit-il encore ?
```
(`/srv/photos` est un exemple de `<CHEMIN-PHOTOS>`.)

*2. Préparer la destination (cas du HDD vierge)*
```
root@pve01:~# DISK=/dev/disk/by-id/ata-ST2000DM008-2UB102_ZK20ABCD      # exemple, d'après l'inventaire
root@pve01:~# wipefs -n "$DISK" ; lsblk "$DISK" ; pvs ; zpool status ; findmnt | grep -c "$(readlink -f "$DISK")"
root@pve01:~# sgdisk -n1:0:0 -t1:8300 -c1:hdd-bulk "$DISK"     # une partition GPT sur tout le disque
root@pve01:~# udevadm settle
root@pve01:~# mkfs.ext4 -L hdd-bulk -m 1 "${DISK}-part1"       # 1 % réservé à root (disque de données)
root@pve01:~# mkdir -p /mnt/hdd-bulk
root@pve01:~# blkid -s UUID -o value "${DISK}-part1"
root@pve01:~# echo 'UUID=<UUID> /mnt/hdd-bulk ext4 defaults,noatime,nofail 0 2' >> /etc/fstab
root@pve01:~# systemctl daemon-reload && findmnt --verify && mount /mnt/hdd-bulk && findmnt /mnt/hdd-bulk
root@pve01:~# mkdir -p /mnt/hdd-bulk/sauvegarde-photos-hp01/donnees
```
Si le HDD contient déjà un système de fichiers monté (par exemple `/mnt/data`), crée-y `sauvegarde-photos-hp01/` et pointe `WB_PHOTOS_DIR` dessus, ou fais un montage *bind* vers `/mnt/hdd-bulk` si ce disque devient `hdd-bulk` en E07.

*3. Manifeste sur la source* : la commande de l'énoncé. `LC_ALL=C sort -z` donne un ordre stable, indépendant de la langue (deux manifestes calculés à des dates différentes sont comparables avec `diff`). `nice`/`ionice` évitent d'écraser un serveur encore en service. Ensuite :
```
root@hp01:~# wc -l /root/MANIFEST.sha256 ; sha256sum /root/MANIFEST.sha256
```
Note l'empreinte du manifeste lui-même dans le ticket CHG-104 : elle prouvera plus tard que le manifeste n'a pas été modifié.

*4. Copie* : les commandes de l'énoncé. Rôle des options :

| Option | Rôle |
|---|---|
| `-a` | mode archive : récursif, liens symboliques, droits, dates, propriétaire et groupe, fichiers spéciaux (`-rlptgoD`) |
| `-H` | préserve les liens physiques (sinon un fichier à deux noms est copié deux fois) |
| `-A`, `-X` | préservent les ACL et les attributs étendus (métadonnées de certains logiciels photo) |
| `--numeric-ids` | conserve les UID/GID numériques au lieu de les traduire par nom (les comptes diffèrent entre les deux machines) |
| `--partial` | garde les fichiers partiellement transférés : une reprise ne repart pas de zéro pour une grosse vidéo |
| `--info=progress2` | progression globale plutôt que fichier par fichier |
| `--dry-run --itemize-changes` | simulation : liste ce qui serait fait, avec le détail des différences |

La barre oblique finale de la source (`<CHEMIN-PHOTOS>/`) copie le **contenu** du dossier dans `donnees/`. Sans elle, on obtiendrait `donnees/photos/…` et les chemins relatifs du manifeste ne correspondraient plus.

Si la connexion coupe : `tmux attach -t photos`, ou relance simplement la même commande `rsync` ; il ne transfère que ce qui manque ou diffère.

*5. Vérification* : les commandes de l'énoncé. Résultat attendu : code retour 0, autant de lignes `: OK` que de lignes dans le manifeste, et `grep -v ': OK$'` ne renvoie rien. Puis la passe `rsync --checksum --dry-run` : elle relit **tout** des deux côtés et ne doit rien lister.

*6 et 7.* Exemple de `LISEZMOI.txt` : [`fichiers/M00-E04/LISEZMOI.exemple.txt`](fichiers/M00-E04/LISEZMOI.exemple.txt). Seconde copie sur un disque externe, puis vérification de cette copie avec le **même** manifeste :
```
root@pve01:~# rsync -aHAX --numeric-ids /mnt/hdd-bulk/sauvegarde-photos-hp01/ /media/usb-photos/sauvegarde-photos-hp01/
root@pve01:~# cd /media/usb-photos/sauvegarde-photos-hp01/donnees && LC_ALL=C sha256sum -c --quiet ../MANIFEST.sha256 && echo "copie 3 conforme"
```

**Explications**

*Pourquoi un manifeste calculé sur la source ?* `rsync` vérifie déjà chaque transfert avec une somme de contrôle interne. Mais il ne prouve rien **à un tiers**, et rien **dans le temps**. Le manifeste calculé à la source, avant la copie, est une référence indépendante de l'outil de copie : il détecte une corruption pendant le transfert, une erreur d'écriture sur la destination, une corruption silencieuse ultérieure du HDD (en revérifiant dans six mois), et il vaut preuve pour Sophie. Calculé sur la destination, il ne prouverait que la cohérence de la copie avec elle-même.

*Pourquoi deux vérifications ?* `sha256sum -c` vérifie que tout ce qui est dans le manifeste est présent et intact. Il ne voit pas un fichier ajouté sur la source **après** le calcul du manifeste. La passe `rsync --checksum --dry-run` compare directement source et destination et couvre ce cas. Le contrôle du nombre de fichiers fait le lien entre les deux.

*La règle 3-2-1* : trois copies des données, sur deux supports différents, dont une hors site. Ici, avant l'E20 : l'original sur `hp01`, la copie sur le HDD de `pve01`, une copie sur un disque externe rangé ailleurs. Après l'E20, l'original disparaît : il ne reste que deux copies, d'où l'insistance pour que la troisième existe **avant**. Un HDD de lab, qui recevra aussi des sauvegardes `vzdump` et des données MinIO, n'est pas un coffre-fort.

**Alternatives**

- `restic` ou `borg` : sauvegardes dédupliquées, chiffrées, versionnées, avec vérification intégrée (`restic check --read-data`). Idéal pour la copie hors site (stockage objet, disque externe).
- `zfs send | zfs receive` si source et destination sont en ZFS : copie par blocs avec sommes de contrôle de bout en bout ; un `zpool scrub` périodique détecte ensuite la corruption silencieuse.
- `hashdeep` (audit d'un arbre par rapport à un manifeste, avec détection des fichiers en trop) ou `cfv`.
- Source Windows : monter le partage SMB en lecture seule sur `pve01` (`mount -t cifs -o ro,vers=3.0,username=<UTILISATEUR> //<IP-HP01-LAN>/<PARTAGE> /mnt/hp01-photos`), calculer le manifeste **sur le point de montage** avant la copie, puis copier sans `-A` ni `-X`. Le manifeste lit alors la source à travers le réseau : c'est acceptable, puisqu'il est calculé avant et indépendamment de la copie.

**Pièges classiques**

- La barre oblique finale oubliée : `donnees/photos/…` au lieu de `donnees/…`, et un `sha256sum -c` qui ne trouve aucun fichier.
- Un `rsync` lancé dans le mauvais sens, ou avec `--delete` : c'est ainsi qu'on efface la source. D'où la règle « `hp01` en lecture seule » et le `--dry-run` systématique.
- Un logiciel de photo (catalogue Lightroom, digiKam, synchronisation) qui modifie des fichiers pendant la copie : écarts entre manifeste et copie. Fige la source d'abord.
- Les **liens symboliques** : `rsync -a` les copie comme des liens et `find -type f` les ignore. Si la bibliothèque photo pointe par lien vers un autre disque, ces données ne sont pas sauvegardées. D'où le `find -type l` de l'état des lieux.
- Noms de fichiers exotiques (accents dans un autre encodage, caractères interdits par NTFS, retours à la ligne) : `sha256sum` les échappe par une barre oblique inverse en début de ligne ; vérifie qu'ils passent la vérification.
- Écrire le manifeste dans le dossier des photos : il se retrouve dans le manifeste lui-même et dans la copie. On l'écrit à côté.
- `/tmp` en mémoire (*tmpfs*) trop petit pour un gros manifeste ; une session SSH coupée sans `tmux` qui interrompt le calcul : rien de grave, il suffit de relancer, mais c'est du temps perdu.
- Déclarer victoire sur la seule base de `rsync` sans erreur.

**En production chez MédiSphère**

Pour des données de santé, on ajouterait : chiffrement au repos des copies, traçabilité de la chaîne de garde (manifeste signé, par exemple `gpg --detach-sign MANIFEST.sha256`, empreinte consignée dans le ticket), stockage immuable pour la copie hors site (verrouillage d'objets S3), tests de restauration périodiques et documentés, et une durée de conservation définie par la politique de données. Et surtout, une sauvegarde régulière plutôt qu'une copie unique : c'est le rôle de PBS dans la suite du module.

---

### M00-E05 — Comprendre l'architecture du lab

**Barème indicatif** : 2 points par question, 36 au total. Au-delà de 28, ta compréhension de l'architecture est solide ; en dessous de 20, relis l'introduction et refais les questions 2, 3 et 6 avec le schéma sous les yeux.

**Réponses argumentées**

**1. `vmbr1` sans port physique.** (1) **Isolation** : les trames étiquetées du lab ne sortent jamais de `pve01` ; ni la box ni le LAN maison ne voient de VLANs, de diffusions ou de serveurs DHCP du lab, et le lab peut utiliser n'importe quels VLANs et adresses sans coordination. Une VM compromise du lab ne peut pas usurper d'adresses sur le LAN maison. (2) **Performance** : le trafic entre VMs reste en mémoire dans le noyau de `pve01`, sans passer par une carte réseau à 1 Gb/s. (3) **Contrainte** : toute communication avec l'extérieur passe par une VM routeur, `gw01`, qui devient un point unique de défaillance et un goulot d'étranglement ; et une machine physique (`hp01`) ne peut pas être branchée dans un VLAN du lab, d'où le tunnel.

**2. De `adm01` à `deb.debian.org`.** `adm01` résout le nom, puis émet une trame **non étiquetée** vers sa passerelle 10.10.10.1 (route par défaut). Son port `tap` sur `vmbr1` a le PVID 10 : la trame entre dans le VLAN 10. Elle ressort par le port de `gw01` (trunk) **étiquetée** 10, arrive sur `ens19`, et le noyau de `gw01` la remet à `ens19.10` sans étiquette. Décision de routage : destination hors lab, route par défaut via `<IP-BOX>` sur `ens18`. Chaîne `forward` : nouvelle connexion, règle « lab vers Internet » (le destinataire n'est pas dans le LAN maison), acceptée ; le suivi de connexion crée une entrée. Chaîne `postrouting` de la table `nat` : *masquerade*, la source devient `<IP-GW01-WAN>`. Le paquet sort par `ens18`, `vmbr0`, la box (qui traduit à son tour vers l'IP publique : double NAT), Internet. Retour : la box retraduit vers `<IP-GW01-WAN>`, `gw01` reconnaît la connexion et retraduit la destination vers 10.10.10.10, la chaîne `forward` l'accepte (`established`), la route connectée l'envoie sur `ens19.10`, donc étiquetée 10 sur le trunk, et le port de `adm01` la délivre sans étiquette.

**3. `pve01` vers 10.10.20.10.** `pve01` choisit la route 10.10.0.0/16 via `<IP-GW01-WAN>`, résout la MAC de `gw01` par ARP et lui envoie le paquet. `gw01` le route vers `ens19.20` (règle de ping d'administration depuis `pve01`), étiquette 20, jusqu'à `dns01`. Pas de traduction : la règle `masquerade` ne concerne que ce qui **sort par `ens18`**. `dns01` répond via sa passerelle 10.10.20.1 ; `gw01` reconnaît la connexion, la renvoie par `ens18` vers `pve01`. Toujours pas de traduction : la traduction se décide au **premier** paquet d'une connexion (ici, l'aller, qui sortait par `ens19.20`), et la règle exclut de toute façon `pve01`. Sans route sur `pve01`, le paquet suivrait la route par défaut vers la box, qui l'enverrait vers Internet (ou le jetterait, adresse privée) : aucune réponse.

**4. VLANs non routés.** Ils portent du trafic interne à un cluster : réplication Ceph, battements de cœur Corosync, tunnels Geneve d'OpenStack. Ce trafic ne doit dépendre d'aucune passerelle (un redémarrage de `gw01` ne doit pas faire perdre le quorum Corosync), doit avoir une latence minimale, et rien d'extérieur n'a à l'atteindre. Conséquence : les VMs concernées ont une interface (ou une sous-interface) **supplémentaire** dans ce VLAN, avec une adresse statique **sans passerelle** ; tous les membres sont dans le même segment ; pas d'Internet ni de DNS par cette interface ; une MTU cohérente entre tous les membres.

**5. VLAN 41.** Ce n'est pas un segment d'hôtes : c'est un **réservoir d'adresses de services** Kubernetes, annoncées en BGP par les nœuds (VLAN 40) via MetalLB ou Cilium. `gw01` n'a pas besoin d'y avoir une interface : il apprendra des routes (souvent des /32) par une session BGP avec les nœuds, *next-hop* = l'adresse du nœud dans 10.10.40.0/24. C'est FRR, aux modules 07 et 15.

**6. Réponses B et E.** B : deux VMs d'un même VLAN communiquent au niveau 2, dans `vmbr1`, sans routeur. E : ton poste joint l'interface web de `pve01` sur le LAN maison, sans passer par `gw01`. A est faux (inter-VLAN, donc routé par `gw01`), C aussi (`pve01` joint le lab via `gw01`), D aussi (le tunnel `wg0` se termine sur `gw01`).

**7. Routeur Linux.** Avantages : on apprend les briques réelles (routage, nftables, suivi de connexion, *sysctl*, WireGuard, puis FRR) sans couche d'abstraction ; toute la configuration est du texte, versionnable et automatisable (Ansible au module 04) ; c'est léger ; c'est un terrain idéal pour les pannes du palier 4. Inconvénients : pas d'interface graphique ni de fonctions prêtes à l'emploi (haute disponibilité type CARP, IDS, rapports) ; tout est à construire, à durcir et à maintenir ; pas de garde-fou contre une erreur de syntaxe ou de logique. En production, MédiSphère aurait des pare-feu de bordure dédiés en paire haute disponibilité, gérés par l'équipe sécurité avec revue des changements, et un routage de datacenter (souvent des routeurs Linux/FRR ou des commutateurs L3) automatisé : deux rôles que `gw01` cumule ici.

**8. Points uniques de défaillance.**

| SPOF | Atténuation dans le workbook |
|---|---|
| `pve01` (un seul hyperviseur) | Simulé par le cluster imbriqué du module 09 ; accepté pour le lab (budget). |
| `gw01` (routage, NAT, tunnel, NTP) | Module 07 : `gw02` et VRRP (adresses .2 et .3 réservées). |
| `dns01` | Module 06 : PowerDNS, résolveurs redondants. |
| Une seule carte réseau de `pve01` | Module 07 : agrégation (simulée). |
| Disques sans redondance | Sauvegardes PBS (E22) ; accepté. |
| `pbs01`, seule cible de sauvegarde | Copie supplémentaire hors site ; accepté pour le lab, à traiter en production. |
| La box, l'alimentation électrique | Accepté. |
| `adm01` | Reconstructible depuis le template, puis par Ansible (module 04). |
| Toi (connaissance concentrée) | Documentation et runbooks (E25). |

**9. Plages de VMID.** Elles évitent les collisions avec les VMs perso et entre modules, permettent d'identifier une VM d'un coup d'œil (supervision, scripts), et rendent sûres des opérations par plage (« détruire tout ce qui est entre 5000 et 5999 » pour nettoyer la sandbox, tâches de sauvegarde par pool). Avant de créer 5001 : vérifier qu'aucune VM ni aucun conteneur ne l'utilise (`qm status 5001`, `pct status 5001`, ou `/cluster/resources`), et qu'aucun **volume orphelin** `vm-5001-disk-*` ne traîne sur les stockages (`pvesm list <stockage> --vmid 5001`) : Proxmox refuserait d'allouer un volume du même nom, et un `qm rescan` pourrait rattacher un vieux disque à la nouvelle VM.

**10. Comptes dédiés.** `root@pam` a tous les droits sur tout : VMs perso, shell de l'hôte, gestion des comptes. Partagé, il ne permet aucune traçabilité (constat d'audit HDS) ; compromis, tout est compromis. Avec un pool et des rôles, une erreur ou une compromission de `wb-admin@pve` ne touche que les ressources du lab (*blast radius* = le lab). Le jeton de `wb-automation@pve`, avec séparation des privilèges et rôle minimal, limite encore plus : un bogue de Terraform ou un jeton qui fuit dans une CI ne peut ni supprimer une VM perso, ni modifier des permissions. Le jeton se révoque sans toucher au compte, et le journal des tâches indique qui a fait quoi.

**11. Sauvegardes à travers le tunnel.** Choix : simuler une vraie liaison entre deux sites (routage, chiffrement, MTU, filtrage, latence), traiter le LAN comme un réseau non sûr, et pouvoir s'exercer aux pannes réalistes (E42, E43). Coûts : dépendance à `gw01` (s'il tombe, plus de sauvegarde ; et `gw01` est lui-même sauvegardé à travers lui-même : pour le restaurer, il faudra un accès à PBS qui ne passe pas par lui) ; charge de chiffrement sur `gw01` (1 vCPU) ; débit inférieur à une copie directe ; MTU réduite, donc risque de trou noir PMTUD ; diagnostic plus complexe.

**12. MTU de `wg0`.** WireGuard encapsule chaque paquet dans UDP : en-tête IP externe (20 octets en IPv4, 40 en IPv6), UDP (8), en-tête WireGuard et étiquette d'authentification (32). Soit 60 à 80 octets : 1500 - 80 = 1420, la valeur par défaut, sûre même avec un réseau sous-jacent en IPv6. Si c'est mal géré : trous noirs PMTUD (sessions SSH qui figent sur de gros affichages, négociations TLS bloquées, sauvegardes PBS qui stagnent). Traitement sur `gw01` : laisser passer les ICMP *fragmentation needed*, *clamping* du MSS TCP pour le trafic qui entre dans le tunnel, MTU cohérente aux deux extrémités. C'est la panne M00-E41.

**13. DNS provisoire et nom de domaine.** dnsmasq tient en un fichier, fait DNS et DHCP, et suffit pour démarrer ; PowerDNS demande une base de données et une API, et prend tout son sens avec NetBox au module 06. C'est aussi un problème d'œuf et de poule : il faut un DNS avant d'avoir les outils d'automatisation. Et remplacer un service en production sans casser les clients est une compétence en soi. `.internal` est réservé par l'ICANN à l'usage privé : il ne sera jamais délégué dans le DNS public, donc aucune collision possible. `.local` est réservé à mDNS (RFC 6762) : conflits avec Avahi, `nss-mdns` (`mdns4_minimal [NOTFOUND=return]` court-circuite la résolution) et les appareils Apple. `.lan` n'est pas réservé et fait fuiter des requêtes vers les serveurs racine. L'autre bonne pratique est un sous-domaine d'un domaine qu'on possède (par exemple `int.medisphere.fr`).

**14. NTP hiérarchique.** Un seul flux NTP sortant (de `gw01`) au lieu d'un par VM : moins de règles de pare-feu, moins d'exposition ; toutes les machines du lab sont cohérentes **entre elles**, ce qui compte plus que l'exactitude absolue pour Ceph ou etcd ; si Internet tombe, le lab garde une heure commune ; la passerelle est toujours joignable directement sur le lien. Inconvénient : `gw01` devient la source de temps unique ; en production, on aurait au moins deux serveurs NTP internes.

**15. Route statique ou `wg1`.** Route statique : rien à installer sur le poste, mais beaucoup de box ne permettent pas d'ajouter une route (il faut alors l'ajouter sur chaque poste), le trafic circule en clair sur le LAN, et l'accès est accordé à toute une plage d'adresses plutôt qu'à une personne. `wg1` : trafic chiffré, authentification par clé (une clé par poste, révocable), accès possible depuis l'extérieur si on le décide, règles de pare-feu attachées à l'interface `wg1` et adresse source traçable (10.255.1.2). Coûts : gestion des clés, MTU, dépendance à `gw01`. En production : VPN ou bastion avec MFA, jamais de route directe depuis les postes.

**16. Budget mémoire.** Deux profils lourds simultanés dépassent la RAM physique : l'hôte se met à utiliser son swap (tout le lab ralentit, `gw01` compris), voire son OOM killer tue un processus QEMU, c'est-à-dire une VM entière, peut-être une VM perso. Fausses marges : le *ballooning* (la mémoire ne revient à l'hôte que si l'invité la libère, et lentement) ; KSM (la fusion des pages identiques fond quand les VMs divergent, et coûte du CPU) ; l'ARC de ZFS (compté comme utilisé, il rend la mémoire sous pression, mais pas toujours assez vite) ; le swap de l'hôte (il masque l'épuisement jusqu'à l'effondrement des performances) ; et une VM qui a touché sa mémoire une fois la garde côté hôte. La virtualisation imbriquée multiplie ces surcoûts. Règle : la somme de la mémoire maximale des VMs en marche reste sous la RAM physique, moins une réserve pour l'hôte (et l'ARC).

**17. `gw01` à la main.** Le template et cloud-init supposent un réseau qui fonctionne : au premier démarrage, les clones installent l'agent QEMU depuis les miroirs Debian, donc il faut une passerelle et du NAT. `gw01` doit exister **avant**. C'est aussi un choix pédagogique : voir une fois une installation classique permet de comprendre ce que cloud-init automatise. Enfin, `gw01` a une configuration matérielle particulière (deux cartes, un trunk). Sa configuration sera codifiée plus tard (rôle Ansible, module 04).

**18. Reconstruire le socle.** *Reconstructible par code* (une fois les modules 03 à 05 faits) : le template (Packer), les VMs `adm01` et `dns01` (Terraform, cloud-init, Ansible), la configuration de `gw01`. Le dépôt Git qui contient ce code doit, lui, exister ailleurs que sur `pve01`. *À sauvegarder* : la configuration de l'hôte (`/etc/pve` : stockages, utilisateurs, ACL, pare-feu, SDN, tâches ; `/etc/network/interfaces` ; dépôts APT ; `modprobe.d` ; clés et configuration SSH de root ; E30) ; les VMs à état (`gw01` tant qu'il n'est pas codifié, `dns01`, puis GitLab, NetBox, MinIO…) via PBS ; la configuration de PBS et surtout **ses clés de chiffrement** (perdues, les sauvegardes chiffrées sont inutilisables : E36) ; les clés privées WireGuard ; les secrets (jetons, mots de passe) ; l'inventaire et la documentation. Ordre de reconstruction : réinstaller Proxmox, réseau, stockages, restaurer `gw01` (par un accès direct à PBS sur le LAN, puisque le tunnel se termine sur `gw01`), puis le reste.

---
### M00-E06 — Préparer `pve01` (dépôts, mises à jour, virtualisation imbriquée)

**Solution**

*Proxmox VE 9 (deb822)*. Fichiers de référence : [`fichiers/M00-E06/`](fichiers/M00-E06/).
```
root@pve01:~# pveversion
pve-manager/9.x.y/… (running kernel: 6.x.y-z-pve)
root@pve01:~# ls /etc/apt/sources.list.d/
ceph.sources  debian.sources  pve-enterprise.sources
root@pve01:~# apt update 2>&1 | grep -E '401|Err'
Err:… https://enterprise.proxmox.com/debian/pve trixie InRelease  401  Unauthorized
```
Désactiver les dépôts *enterprise* : ajouter `Enabled: no` dans chaque strophe concernée de `pve-enterprise.sources` et `ceph.sources` (ou passer la strophe Ceph sur `http://download.proxmox.com/debian/ceph-<VERSION>` avec `Components: no-subscription` si tu utilises Ceph sur l'hôte, ce qui n'est pas le cas ici). Créer `proxmox.sources` :
```
root@pve01:~# cat > /etc/apt/sources.list.d/proxmox.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
root@pve01:~# apt update
root@pve01:~# apt list --upgradable
root@pve01:~# apt full-upgrade
```
Dans *Nœud → Updates → Repositories*, l'interface doit afficher le dépôt *no-subscription* actif et l'avertissement « pas de dépôt enterprise activé » (normal sans abonnement).

*Proxmox VE 8 (format `.list`)* : voir [`fichiers/M00-E06/pve8-sources.list.exemple`](fichiers/M00-E06/pve8-sources.list.exemple). On commente la ligne `deb` de `pve-enterprise.list` (et celle de `ceph.list`), on ajoute `deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription`, puis `apt update` et `apt full-upgrade`.

*Noyau et redémarrage* :
```
root@pve01:~# uname -r                       # noyau en cours
root@pve01:~# proxmox-boot-tool kernel list  # noyaux installés (si démarrage géré par proxmox-boot-tool)
root@pve01:~# ls /boot/vmlinuz-*
```
Si un noyau plus récent est installé, planifie le redémarrage : vérifie l'ordre et le démarrage automatique des VMs perso (`grep -H onboot /etc/pve/qemu-server/*.conf`), préviens les utilisateurs, sauvegarde ce qui est critique. Au redémarrage, Proxmox arrête proprement les VMs (via l'agent ou ACPI) puis les relance selon `onboot`.

*Nom du nœud* :
```
root@pve01:~# hostname --ip-address
192.168.1.20
root@pve01:~# grep pve01 /etc/hosts
192.168.1.20 pve01.par1.medisphere.internal pve01
```
Si la commande renvoie `127.0.1.1`, corrige `/etc/hosts` (ligne `<IP-PVE01> <FQDN> <NOEUD>`) : c'est une exigence de `pve-cluster`.

*Virtualisation imbriquée* :
```
root@pve01:~# grep -c -w vmx /proc/cpuinfo
16
root@pve01:~# cat /sys/module/kvm_intel/parameters/nested
Y
root@pve01:~# echo 'options kvm_intel nested=Y' > /etc/modprobe.d/kvm-intel.conf
```
Si la valeur courante était `N` : rechargement du module impossible tant qu'une VM tourne (`modprobe -r kvm_intel` échoue avec « Module kvm_intel is in use ») ; elle sera prise en compte au prochain redémarrage.

*Heure* : `chronyc tracking` doit indiquer *Leap status : Normal* et un décalage de l'ordre de la milliseconde.

*Si `pve01` est en 8.x* :
```
root@pve01:~# pve8to9 --full
```
Plan de montée de version (à consigner dans l'inventaire) : prérequis (dernière version 8.4 à jour, résultat de `pve8to9 --full` sans échec), sauvegardes vérifiées des VMs perso **sur un autre support**, sauvegarde de `/etc/pve` et `/etc/network/interfaces`, accès console garanti, créneau annoncé, étapes du guide officiel *Upgrade from 8 to 9* (changement des dépôts vers trixie, éventuellement `apt modernize-sources`, `apt full-upgrade`, redémarrage), contrôles après coup, et retour arrière (en pratique : réinstallation et restauration, il n'y a pas de « downgrade » ; d'où l'importance des sauvegardes).

**Explications**

Le dépôt *enterprise* et le dépôt *no-subscription* distribuent les mêmes paquets ; *no-subscription* les reçoit plus tôt, avec moins de recul. Sans abonnement, le dépôt *enterprise* répond `401 Unauthorized`, ce qui fait échouer `apt update`. Le format **deb822** (fichiers `.sources`) est le format par défaut des dépôts APT depuis Debian 13 : plusieurs lignes clé-valeur par dépôt, une clé de signature explicite par dépôt (`Signed-By`), et un champ `Enabled:` qui permet de désactiver un dépôt sans le commenter.

`apt full-upgrade` est la seule commande de mise à jour recommandée sur Proxmox (voir E01, question 14). Les mises à jour n'interrompent pas les VMs, sauf redémarrage de l'hôte ; un nouveau noyau n'est actif qu'après redémarrage.

Le paramètre `nested` de `kvm_intel` autorise une VM à utiliser elle-même VT-x. Il vaut `Y` par défaut sur les noyaux récents ; l'écrire dans `modprobe.d` documente l'intention. Il ne suffit pas : la VM doit aussi **voir** le drapeau `vmx`, donc avoir un type de CPU `host` (ou un modèle avec `+vmx`). Ce sera le cas des nœuds Proxmox imbriqués du module 09, pas des VMs du socle.

**Alternatives**

- L'interface web (*Updates → Repositories*) active et désactive les dépôts, en écrivant les mêmes fichiers.
- `apt modernize-sources` (APT 3, Debian 13) convertit les `.list` en `.sources` lors d'une montée de version.
- Avec un abonnement, on garde le dépôt *enterprise* ; c'est le choix de production.

**Pièges classiques**

- Oublier le dépôt Ceph *enterprise* : `apt update` échoue toujours avec un 401, même sans utiliser Ceph.
- Écrire `Enabled: no` hors de la strophe (après une ligne vide) : il ne s'applique à rien.
- Utiliser `apt upgrade`, ou pire, ajouter le dépôt `pve-test` « pour avoir plus récent ».
- Mélanger les suites (un dépôt `bookworm` resté sur un PVE 9) : dépendances cassées.
- Croire que le nouveau noyau est actif sans redémarrer : `uname -r` fait foi.
- Changer `nested` et s'étonner que rien ne change : le module n'a pas été rechargé, ou la VM n'a pas le type de CPU `host`.
- Lancer la montée de version 8 → 9 « dans la foulée », sans sauvegarde hors de `pve01`.

**En production chez MédiSphère**

Abonnement *enterprise* (paquets plus éprouvés, support). Mises à jour en vagues : d'abord un nœud de test, puis la production, nœud par nœud, avec migration à chaud des VMs (module 09) et fenêtre de maintenance annoncée par un ticket `CHG-`. Supervision des mises à jour en attente et des redémarrages requis (module 21). Pas de mises à jour automatiques non surveillées des paquets Proxmox. Montées de version majeures préparées (`pve8to9`), répétées sur un environnement de test, avec plan de retour arrière.

---

### M00-E07 — Organiser les stockages sans rien casser

**Solution**

*1. Lire la carte des disques.* Exemple de sortie (fictive) :
```
root@pve01:~# lsblk -o NAME,SIZE,TYPE,ROTA,TRAN,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
NAME          SIZE TYPE ROTA TRAN MODEL                 SERIAL          FSTYPE      MOUNTPOINTS
sda           1.8T disk    0 sata Samsung SSD 870 EVO   S6PNNS0T654321
sdb           1.8T disk    1 sata ST2000DM008-2UB102    ZK20ABCD
└─sdb1        1.8T part    1                                            ext4        /mnt/hdd-bulk
nvme0n1       1.8T disk    0 nvme SAMSUNG MZVL22T0HBLB  S6XXNF0R123456
├─nvme0n1p1  1007K part    0
├─nvme0n1p2     1G part    0                                            vfat        /boot/efi
└─nvme0n1p3   1.8T part    0                                            LVM2_member
  ├─pve-swap    8G lvm     0                                            swap        [SWAP]
  ├─pve-root   96G lvm     0                                            ext4        /
  ├─pve-data_tmeta …
  └─pve-data_tdata …
```
Lecture : NVMe système (VG `pve`, *thin pool* `data` = `local-lvm`), SSD vierge, HDD déjà formaté et monté par l'E04.

*2. Décider, support par support.*

| Support | Situation | Décision |
|---|---|---|
| NVMe, installation **ZFS** (`rpool`) | `rpool/data` porte `local-zfs` | Cas A : *dataset* dédié `rpool/lab`, stockage `local-nvme` de type `zfspool`. Non destructif. |
| NVMe, installation **LVM** avec espace libre dans le VG (`vgs` : `VFree` ≥ 200 Go) | rare après une installation par défaut | Cas B : nouveau *thin pool* `pve/lab`, stockage `local-nvme` de type `lvmthin`. |
| NVMe, installation **LVM** sans espace libre | cas le plus courant | Cas C : on garde `local-lvm`, `WB_STORAGE_NVME=local-lvm` dans `lab/lab.env`, correspondance notée dans l'inventaire. On ne crée **pas** de second stockage sur `pve/data`. |
| NVMe non utilisé (système ailleurs) | | Cas D : comme un disque vierge. |
| SSD vierge | | LVM-thin dédié (justification ci-dessous), stockage `ssd-lab`. |
| HDD | ext4 monté sur `/mnt/hdd-bulk` (E04) | Stockage `hdd-bulk` de type répertoire, `is_mountpoint`. |

*3. Commandes.*

Cas A (NVMe en ZFS) :
```
root@pve01:~# zfs create rpool/lab
root@pve01:~# pvesm add zfspool local-nvme --pool rpool/lab --content images,rootdir --sparse 1
```
Cas B (NVMe en LVM, espace libre dans le VG) :
```
root@pve01:~# lvcreate -L 400G --poolmetadatasize 4G --thinpool lab pve
root@pve01:~# pvesm add lvmthin local-nvme --vgname pve --thinpool lab --content images,rootdir
```
Cas C : rien à créer ; dans `lab/lab.env` : `WB_STORAGE_NVME=local-lvm`.

SSD vierge en LVM-thin, après la règle des trois preuves :
```
root@pve01:~# SSD=/dev/disk/by-id/ata-Samsung_SSD_870_EVO_2TB_S6PNNS0T654321
root@pve01:~# wipefs -n "$SSD"                                     # 1. aucune signature
root@pve01:~# pvs ; zpool status ; findmnt ; grep -c "$(basename "$(readlink -f "$SSD")")" /etc/pve/storage.cfg   # 2. aucun usage
root@pve01:~# ls -l /dev/disk/by-id/ | grep S6PNNS0T654321          # 3. numéro de série = inventaire
root@pve01:~# pvcreate "$SSD"
root@pve01:~# vgcreate vg-ssd-lab "$SSD"
root@pve01:~# lvcreate -l 95%FREE --poolmetadatasize 2G --thinpool lab vg-ssd-lab
root@pve01:~# pvesm add lvmthin ssd-lab --vgname vg-ssd-lab --thinpool lab --content images,rootdir
```
HDD (déjà monté sur `/mnt/hdd-bulk`) :
```
root@pve01:~# pvesm add dir hdd-bulk --path /mnt/hdd-bulk --is_mountpoint yes \
    --content iso,vztmpl,backup,snippets,import,images --prune-backups keep-last=3
```
*4. Vérifier.*
```
root@pve01:~# pvesm status
Name             Type     Status           Total            Used       Available        %
hdd-bulk          dir     active      1921725720       431812345      1392107520   22.47%
local             dir     active        98497780        12345678        81049604   12.53%
local-lvm     lvmthin     active      1793241088       188743680      1604497408   10.53%
ssd-lab       lvmthin     active      1912602624               0      1912602624    0.00%
root@pve01:~# ls /mnt/hdd-bulk
dump  images  import  lost+found  sauvegarde-photos-hp01  snippets  template
```
Proxmox a créé les sous-répertoires de chaque type de contenu à côté du dossier des photos, sans y toucher.

**Explications**

*Types de stockage.* **LVM-thin** : volumes logiques à allocation fine, instantanés et clones liés possibles, surcoût faible ; pas de sommes de contrôle. **ZFS** (`zfspool`) : sommes de contrôle, compression, instantanés, réplication (`zfs send`) ; consomme de la RAM (cache ARC) et fait du *copy-on-write*. **Répertoire** (`dir`) : des fichiers dans un système de fichiers monté ; le seul des trois qui accepte les contenus « fichiers » (ISO, snippets, sauvegardes `vzdump`, images à importer) ; les disques de VMs y sont des fichiers `raw` ou `qcow2`.

*Pourquoi LVM-thin pour `ssd-lab` ?* Ce SSD portera les disques d'OSD Ceph virtuels (module 08) et des bases de données. Ceph (BlueStore) gère déjà ses propres sommes de contrôle et sa réplication ; empiler du *copy-on-write* (ZFS) sous du *copy-on-write* (Ceph) multiplie les écritures et use le SSD, et un ZFS sur un disque unique n'apporte pas de redondance. LVM-thin donne des performances proches du disque brut. ZFS reste un choix défendable (compression, instantanés fiables) si tu limites l'ARC.

*Pourquoi `is_mountpoint` ?* Sans cette option, si le HDD n'est pas monté (disque absent, `nofail` au démarrage), le répertoire `/mnt/hdd-bulk` existe quand même… sur le disque système. Proxmox y écrirait sauvegardes et ISO, et remplirait la partition racine de l'hyperviseur. Avec `is_mountpoint yes`, le stockage est simplement marqué hors ligne.

*Pourquoi jamais deux stockages sur le même support ?* La documentation de `pvesm` l'écrit : deux configurations pointant sur le même support produisent deux identifiants de volume pour la même image disque. Proxmox raisonne stockage par stockage : la suppression d'une VM, un `qm rescan` ou une tâche de nettoyage peuvent alors détruire ou rattacher le disque d'une autre VM. Avec tes VMs perso sur `local-lvm`, c'est exactement le risque à ne pas prendre.

*Le contenu `import`* (récent dans Proxmox VE) accueille des images disque et des archives OVA destinées à être importées dans des VMs : c'est là que va l'image *genericcloud* de l'E11.

**Alternatives**

- `pvesh create /nodes/<NOEUD>/disks/lvmthin --device <DISQUE> --name ssd-lab --add_storage 1` (ou *Nœud → Disks → LVM-Thin* dans l'interface) : Proxmox initialise le disque et déclare le stockage en une opération, et **refuse** un disque qu'il détecte comme utilisé. Pratique, mais tu ne choisis ni la taille des métadonnées ni la marge. Équivalents pour ZFS (`/disks/zfs`) et répertoire (`/disks/directory`, monté sous `/mnt/pve/<nom>` par une unité systemd).
- ZFS pour le SSD : `zpool create -o ashift=12 -O compression=lz4 -O atime=off ssdlab <DISQUE>` puis `pvesm add zfspool ssd-lab --pool ssdlab --content images,rootdir --sparse 1`, et un plafond d'ARC (`options zfs zfs_arc_max=<OCTETS>` dans `/etc/modprobe.d/zfs.conf`, puis `update-initramfs -u` si la racine est en ZFS : voir E01, question 24).
- Cas C : renommer `local-lvm` en `local-nvme` en éditant `storage.cfg` **et** toutes les configurations de VMs qui le référencent, VMs arrêtées. Possible, mais risqué et sans bénéfice réel : la correspondance de noms suffit.

**Pièges classiques**

- Désigner un disque par `/dev/sdX` et formater le mauvais : l'ordre `sda`/`sdb` peut s'inverser d'un démarrage à l'autre.
- Formater le HDD qui contient la seule copie vérifiée des photos (d'où « E04 validé » en prérequis).
- Oublier `images` dans les contenus : impossible d'y créer un disque de VM ; oublier `snippets` sur `hdd-bulk` : l'E11 échoue.
- *Thin pool* créé à 100 % du groupe de volumes : plus aucune marge pour étendre les métadonnées ou le pool.
- Stockage `dir` sans `is_mountpoint` : partition racine pleine le jour où le disque ne monte pas.
- Déclarer `local-nvme` sur le même *thin pool* que `local-lvm` « pour avoir le bon nom ».

**En production chez MédiSphère**

Redondance matérielle ou logicielle des disques (miroir ZFS, RAID), stockage partagé ou distribué pour la haute disponibilité (Ceph, module 08), supervision du remplissage des *thin pools* et des pools ZFS avec alertes, séparation stricte entre stockage des VMs et stockage des sauvegardes (jamais sur le même support), et conventions de nommage des stockages documentées dans la source de vérité.

---

### M00-E08 — Pool, utilisateurs, groupes et rôles

**Solution**

Les commandes de l'énoncé, complétées :
```
root@pve01:~# pveum acl modify /storage/ssd-lab --groups wb-admins --roles PVEDatastoreUser
root@pve01:~# pveum acl modify /storage/hdd-bulk --groups wb-admins --roles PVEDatastoreUser
root@pve01:~# pveum acl list
┌──────────────────┬───────────┬──────────────────┬───────┬───────────┐
│ path             │ ugid      │ roleid           │ type  │ propagate │
╞══════════════════╪═══════════╪══════════════════╪═══════╪═══════════╡
│ /pool/lab        │ wb-admins │ PVEAdmin         │ group │ 1         │
│ /storage/hdd-bulk│ wb-admins │ PVEDatastoreUser │ group │ 1         │
│ …                                                                    │
root@pve01:~# pveum role list --output-format json-pretty | less
root@pve01:~# pveum user permissions wb-admin@pve --path /pool/lab
root@pve01:~# pveum user permissions wb-admin@pve --path /
```
La seconde commande de permissions ne doit lister aucun privilège système. Avec le cas C de l'E07, remplace `local-nvme` par `local-lvm` dans l'ACL : `wb-admin` pourra alors **allouer** de l'espace sur le stockage de tes VMs perso, sans pouvoir toucher à leurs disques (ce qui exige des droits sur les VMs elles-mêmes).

Dans l'interface web, connecté en `wb-admin` : l'arbre ne montre que le pool `lab` (vide pour l'instant) et les trois stockages ; ni les VMs perso, ni le shell du nœud, ni *Datacenter → Permissions*.

**Explications**

Une permission Proxmox est un triplet **chemin / utilisateur ou groupe / rôle**, propagé par défaut aux sous-chemins. Un rôle est un ensemble de privilèges (`VM.Allocate`, `Datastore.AllocateSpace`…). Règles d'héritage : un droit posé plus profond dans l'arbre remplace celui hérité d'au-dessus ; les droits d'un utilisateur remplacent ceux de ses groupes ; `NoAccess` annule tout.

Un **pool** regroupe des VMs et des stockages : une ACL sur `/pool/lab` s'applique à tous ses membres. Pourquoi ne pas y ajouter les stockages ? Parce que `PVEAdmin` contient `Datastore.Allocate`, qui permet de **supprimer n'importe quel volume** du stockage. Sur un stockage partagé avec des VMs perso (cas C), c'est un risque inacceptable. `PVEDatastoreUser` ne donne que `Datastore.AllocateSpace` (créer des volumes pour ses propres VMs) et `Datastore.Audit` (voir le contenu). Conséquence voulue : `wb-admin` ne peut pas téléverser d'ISO (`Datastore.AllocateTemplate`) ; c'est root ou l'automatisation qui alimente `hdd-bulk`.

Les droits vont au **groupe**, pas à l'utilisateur : un nouvel arrivant reçoit ses droits en entrant dans le groupe, un départ se traite en l'en retirant, et l'audit lit une politique, pas une collection de cas particuliers.

Le royaume `pve` (*Proxmox VE authentication server*) stocke les comptes dans `/etc/pve` : ils n'ont aucun accès système (pas de shell sur l'hôte), contrairement aux comptes du royaume `pam`.

**Alternatives**

- `pvesh` pour tout faire par l'API : `pvesh create /pools --poolid lab`, `pvesh set /access/acl --path /pool/lab --groups wb-admins --roles PVEAdmin`.
- Rôle personnalisé plus restreint que `PVEAdmin` (sans `VM.Migrate`, sans `Sys.Console`…) : c'est ce que fera l'E17 pour l'automatisation.
- Royaume OIDC (Keycloak, module 24) : les comptes et les groupes viennent de l'annuaire, avec MFA centralisée.

**Pièges classiques**

- Donner le rôle à l'utilisateur plutôt qu'au groupe, ou les deux (les droits de l'utilisateur **remplacent** ceux du groupe sur le même chemin).
- Poser `PVEAdmin` sur `/` « pour que ça marche » : c'est donner presque tout l'hyperviseur.
- Créer une VM sans `--pool lab` : il faut alors `VM.Allocate` sur `/vms/<VMID>`, et la VM, hors du pool, est invisible pour `wb-admin`. Les checks vérifient l'appartenance au pool.
- Confondre `wb-admin@pve` et `wb-admin@pam` à la connexion (choix du royaume dans la mire).
- Oublier que le pool ne peut être supprimé que vide.

**En production chez MédiSphère**

Authentification par SSO (OIDC, module 24) avec groupes provenant de l'annuaire et MFA imposée ; comptes nominatifs uniquement ; `root@pam` réservé au bris de glace (mot de passe sous scellé, usage tracé) ; journaux d'audit (`/var/log/pve/tasks`, journaux d'accès de `pveproxy`) envoyés vers la plateforme de logs (module 22) ; revue trimestrielle des droits.

---

### M00-E09 — Créer le bridge du lab `vmbr1`

**Solution**

Strophe à ajouter : [`fichiers/M00-E09/vmbr1.interfaces`](fichiers/M00-E09/vmbr1.interfaces).
```
root@pve01:~# cp -a /etc/network/interfaces /root/interfaces.avant-vmbr1
root@pve01:~# systemd-run --on-active=10min --unit=retour-reseau \
    /bin/sh -c 'cp /root/interfaces.avant-vmbr1 /etc/network/interfaces && ifreload -a'
root@pve01:~# ls /etc/network/interfaces.new 2>/dev/null && echo "ATTENTION : modifications en attente dans l'interface web"
root@pve01:~# cat /root/vmbr1.interfaces >> /etc/network/interfaces   # ou édition manuelle
root@pve01:~# ifreload -a
root@pve01:~# ifquery --check vmbr1
root@pve01:~# systemctl stop retour-reseau.timer
```
Vérifications :
```
root@pve01:~# ip -d link show vmbr1 | grep -o 'vlan_filtering [01]'
vlan_filtering 1
root@pve01:~# ip link show master vmbr1          # vide tant qu'aucune VM n'y est branchée
root@pve01:~# bridge vlan show dev vmbr1
port              vlan-id
vmbr1             1 PVID Egress Untagged
```
Selon la version d'ifupdown2, le bridge lui-même ne montre que le VLAN 1 : `bridge-vids` s'applique à ses **ports**. Quand `gw01` sera branché en trunk (E10), `bridge vlan show` montrera son port `tap1000i1` avec les VLANs 2 à 4094.

Par l'API (à vérifier selon ta version : le paramètre `bridge_vids` est récent) :
```
root@pve01:~# pvesh create /nodes/<NOEUD>/network --iface vmbr1 --type bridge --autostart 1 \
    --bridge_vlan_aware 1 --bridge_vids 2-4094 --comments "Lab MédiSphère — VLANs du workbook"
root@pve01:~# pvesh set /nodes/<NOEUD>/network        # applique (équivalent du bouton « Apply Configuration »)
```
Droit d'usage :
```
root@pve01:~# pveum acl modify /sdn/zones/localnetwork/vmbr1 --groups wb-admins --roles PVESDNUser
```

**Explications**

Un bridge **VLAN-aware** est un commutateur virtuel qui filtre par VLAN (`vlan_filtering 1`) : chaque port a sa liste de VLANs, un PVID et un mode étiqueté ou non (voir E02, question 4). Proxmox configure les ports des VMs au démarrage : `tag=20` donne un port d'accès au VLAN 20 ; l'absence de `tag` donne un trunk portant les VLANs de `bridge-vids`. Un seul bridge suffit pour les 13 VLANs du plan, là où le modèle non VLAN-aware créerait une sous-interface et un bridge par VLAN.

`bridge-ports none` : aucun port physique, donc l'isolation décrite en E05. Aucune adresse IP sur `vmbr1` : `pve01` n'a rien à faire **dans** les VLANs du lab ; il les joint en routant par `gw01`, comme n'importe quel client du lab, et ses accès sont donc filtrés par la même politique. `bridge-stp off` et `bridge-fd 0` : pas de boucle possible, pas de délai de convergence.

`ifreload -a` (ifupdown2) compare la configuration voulue avec l'état courant et n'applique que les différences : l'ajout de `vmbr1` ne touche pas `vmbr0`.

Depuis Proxmox VE 8, utiliser un bridge dans une VM exige le privilège `SDN.Use` sur `/sdn/zones/localnetwork/<bridge>` (« localnetwork » est la zone implicite qui regroupe les bridges locaux). Le rôle `PVESDNUser` le contient. Après la migration vers le SDN (E28), le chemin deviendra celui de la zone `lab` et de ses VNets.

**Alternatives**

- Bridge **non VLAN-aware** : Proxmox crée à la volée `vmbr1v20` (sous-interface + bridge) pour chaque VLAN utilisé. Plus lisible au cas par cas, mais une prolifération d'interfaces avec 13 VLANs, et un trunk vers `gw01` impossible proprement.
- **Open vSwitch** (module 07) : plus de fonctions (miroirs de ports, OpenFlow), une dépendance de plus.
- **SDN Proxmox** (E28) : zones et VNets déclarés au niveau du datacenter, avec permissions par VNet.

**Pièges classiques**

- Modifier `vmbr0` par erreur (ou réindenter tout le fichier) : coupure d'accès. D'où le filet de sécurité et la console.
- **Oublier d'annuler le retour arrière programmé** : dix minutes plus tard, `vmbr1` disparaît sans prévenir. Le check vérifie que le minuteur n'est plus actif.
- Modifications en attente dans l'interface web (`/etc/network/interfaces.new`) : un clic sur *Apply Configuration* écrase tes modifications faites en ligne de commande. Vérifie l'absence de ce fichier avant d'éditer.
- Mettre une adresse IP sur `vmbr1` « pour tester » : `pve01` contournerait `gw01` et le filtrage.
- Écrire `bridge-vlan-aware yes` sans `bridge-vids` : selon les versions, seuls quelques VLANs, voire aucun, passeraient sur les trunks.

**En production chez MédiSphère**

Deux cartes réseau agrégées (LACP) vers deux commutateurs physiques, portant un trunk des VLANs de production ; un réseau de gestion séparé pour les interfaces d'administration et l'iLO/IPMI ; un réseau dédié au stockage et à Corosync. Configuration réseau des hyperviseurs gérée par l'automatisation (Ansible) ou par le SDN Proxmox, jamais à la main sur un nœud en production. Toute modification réseau passe par un ticket `CHG-` avec plan de retour arrière.

---
### M00-E10 — Construire le routeur/pare-feu `gw01`

**Solution**

Fichiers complets : [`fichiers/M00-E10/`](fichiers/M00-E10/)

| Fichier | Destination |
|---|---|
| `creer-gw01.sh` | script de création de la VM 1000 (sur `pve01`) |
| `interfaces` | `/etc/network/interfaces` de `gw01` |
| `99-routeur.conf` | `/etc/sysctl.d/99-routeur.conf` de `gw01` |
| `nftables.conf` | `/etc/nftables.conf` de `gw01` |
| `90-workbook` | `/etc/sudoers.d/90-workbook` de `gw01` |
| `10-durcissement.conf` | `/etc/ssh/sshd_config.d/10-durcissement.conf` de `gw01` |
| `pve01-root-ssh-config` | `/root/.ssh/config` de `pve01` |
| `pve01-interfaces-vmbr0.extrait` | lignes à ajouter dans la strophe `vmbr0` de `pve01` |

*1. Choisir `<IP-GW01-WAN>`.* Une adresse hors de la plage DHCP de la box, puis :
```
root@pve01:~# ping -c 2 -W 1 <IP-GW01-WAN>            # aucune réponse attendue
root@pve01:~# arping -D -c 2 -I vmbr0 <IP-GW01-WAN>   # aucune réponse = adresse libre (paquet iputils-arping)
```

*2. ISO.* En ligne de commande, dans le répertoire ISO de `hdd-bulk` :
```
root@pve01:~# cd /mnt/hdd-bulk/template/iso
root@pve01:/mnt/hdd-bulk/template/iso# wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA512SUMS
root@pve01:/mnt/hdd-bulk/template/iso# wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.<X.Y>-amd64-netinst.iso
root@pve01:/mnt/hdd-bulk/template/iso# sha512sum -c --ignore-missing SHA512SUMS
debian-13.<X.Y>-amd64-netinst.iso: OK
```
Ou par l'API, qui vérifie la somme elle-même :
```
root@pve01:~# pvesh create /nodes/<NOEUD>/storage/hdd-bulk/download-url --content iso \
    --filename debian-13.<X.Y>-amd64-netinst.iso --url <URL-ISO> \
    --checksum <SHA512> --checksum-algorithm sha512
```
La somme ne prouve l'intégrité que si `SHA512SUMS` est authentique : la vérification complète passe par la signature `SHA512SUMS.sign` (voir <https://www.debian.org/CD/verify>).

*3. La VM.*
```
root@pve01:~# ./creer-gw01.sh debian-13.<X.Y>-amd64-netinst.iso
```
Le cœur du script :
```
qm create 1000 --name gw01 --pool lab --tags "reseau;socle" --ostype l26 \
  --cpu x86-64-v2-AES --cores 1 --memory 2048 \
  --scsihw virtio-scsi-single --scsi0 local-nvme:16,iothread=1,discard=on,ssd=1 \
  --ide2 hdd-bulk:iso/debian-13.<X.Y>-amd64-netinst.iso,media=cdrom --boot "order=scsi0;ide2" \
  --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbr1 \
  --agent enabled=1 --onboot 1 --startup order=1,up=30
```

*4. Installation* (console noVNC) : installation classique, langue au choix, nom `gw01`, domaine `par1.medisphere.internal`, interface principale `ens18` (DHCP de la box pendant l'installation), mot de passe root **vide** (le compte root est verrouillé et `admin` reçoit `sudo`), utilisateur `admin`, partitionnement assisté sur tout le disque, logiciels : uniquement « serveur SSH » et « utilitaires usuels du système ». Après l'installation : `qm set 1000 --ide2 none,media=cdrom` pour éjecter l'ISO.

*5. Post-installation* (console, en `admin`) :
```
admin@gw01:~$ sudo apt update && sudo apt install qemu-guest-agent nftables tcpdump conntrack curl
admin@gw01:~$ sudo systemctl start qemu-guest-agent
admin@gw01:~$ sudo visudo -f /etc/sudoers.d/90-workbook     # contenu : fichier 90-workbook
admin@gw01:~$ sudo -k; sudo -n true && echo "sudo sans mot de passe : OK"
```

*6. Réseau* (console, pas SSH) : copier le fichier `interfaces` en remplaçant les valeurs entre chevrons, puis :
```
admin@gw01:~$ sudo systemctl restart networking
admin@gw01:~$ ip -br addr
lo               UNKNOWN        127.0.0.1/8 ::1/128
ens18            UP             192.168.1.40/24 …
ens19            UP             fe80::…/64
ens19.10@ens19   UP             10.10.10.1/24 fe80::…/64
ens19.20@ens19   UP             10.10.20.1/24 fe80::…/64
…
ens19.99@ens19   UP             10.10.99.1/24 fe80::…/64
admin@gw01:~$ cat /proc/net/vlan/config
```
Puis, depuis `pve01`, la clé dédiée, l'alias et le durcissement SSH :
```
root@pve01:~# ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_lab -C "root@pve01 - lab MédiSphère"
root@pve01:~# ssh-copy-id -i /root/.ssh/id_ed25519_lab.pub admin@<IP-GW01-WAN>
root@pve01:~# install -m 600 pve01-root-ssh-config /root/.ssh/config     # ou ajoute les blocs à un fichier existant
root@pve01:~# ssh gw01 hostname
gw01
root@pve01:~# scp 10-durcissement.conf gw01:/tmp/ && ssh gw01 'sudo install -m 644 /tmp/10-durcissement.conf /etc/ssh/sshd_config.d/ && sudo sshd -t && sudo systemctl reload ssh'
root@pve01:~# ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password admin@<IP-GW01-WAN>
admin@192.168.1.40: Permission denied (publickey).
```
La clé de `pve01` est sans phrase de passe : elle doit servir aux vérifications non interactives. Elle n'est lisible que par root sur l'hyperviseur, et elle n'ouvre que le compte `admin` des VMs du lab.

*7. Routage.*
```
admin@gw01:~$ sudo install -m 644 99-routeur.conf /etc/sysctl.d/ && sudo sysctl --system | tail -n 5
admin@gw01:~$ sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
```

*8. Pare-feu.*
```
admin@gw01:~$ sudo install -m 755 nftables.conf /etc/nftables.conf
admin@gw01:~$ sudo nft -c -f /etc/nftables.conf && echo "syntaxe OK"
admin@gw01:~$ sudo systemd-run --on-active=5min --unit=nft-secours /usr/sbin/nft flush ruleset
admin@gw01:~$ sudo systemctl enable --now nftables
admin@gw01:~$ sudo nft list ruleset | head -n 30
# … la session SSH tient toujours ? Alors on annule le filet de sécurité :
admin@gw01:~$ sudo systemctl stop nft-secours.timer
```
Le filet `flush ruleset` laisse `gw01` **ouvert** (aucune règle, donc tout passe) pendant quelques minutes si tu ne l'annules pas : acceptable dans un lab, à remplacer en production par un retour à la configuration précédente.

*9. Route sur `pve01`* : ajouter les lignes de `pve01-interfaces-vmbr0.extrait` dans la strophe `vmbr0` (avec le même filet de sécurité qu'à l'E09), puis :
```
root@pve01:~# ifreload -a
root@pve01:~# ip route show 10.10.0.0/16
10.10.0.0/16 via 192.168.1.40 dev vmbr0
```

*10. Tests.*
```
root@pve01:~# ping -c 2 10.10.10.1 && ping -c 2 10.10.99.1
root@pve01:~# ssh gw01 'curl -sI https://deb.debian.org | head -n 1'
HTTP/2 200
root@pve01:~# timeout 3 bash -c '</dev/tcp/<IP-GW01-WAN>/80' || echo "port 80 filtré (attendu)"
root@pve01:~# ssh gw01 'sudo nft list chain inet filter input | grep -E "counter|drop"'
root@pve01:~# ssh gw01 'sudo journalctl -k -g nft-in-drop --since "-10min" | tail -n 3'
```

**Explications**

*ifupdown et les VLANs.* Une interface dont le nom contient un point est configurée comme sous-interface 802.1Q de l'interface avant le point : `ens19.20` = VLAN 20 sur `ens19`. Le noyau ajoute l'étiquette en émission et la retire en réception. Aucun paquet supplémentaire n'est nécessaire. L'interface parente ne porte pas d'adresse : elle ne voit que des trames étiquetées (et les trames non étiquetées du VLAN 1, qu'on ignore).

*Les noms `ens18`/`ens19`* viennent de l'emplacement PCI des cartes virtuelles (slots 18 et 19 du bus `pci.0` avec le type de machine par défaut de Proxmox). Avec le type `q35`, les cartes peuvent être placées derrière un pont PCI et s'appeler autrement (par exemple `enp6s18`) : d'où le conseil de garder le type par défaut.

*Le pare-feu.* Les chaînes `input` (trafic destiné à `gw01`) et `forward` (trafic qui le traverse) sont en politique `drop` : tout ce qui n'est pas explicitement autorisé est jeté. La règle `ct state established,related accept` en tête de chaîne fait l'essentiel du travail : seul le **premier paquet** d'une connexion parcourt les règles suivantes ; les réponses et les paquets ICMP d'erreur liés à une connexion connue passent directement. `ct state invalid drop` élimine ce qui ne correspond à aucun état cohérent. La table `inet` traite IPv4 et IPv6 dans les mêmes chaînes ; le noyau ne route de toute façon pas l'IPv6 (`net.ipv6.conf.all.forwarding = 0`).

*Ordre des règles dans `forward`.* Les règles sont évaluées dans l'ordre et la première décision l'emporte. La règle « lab vers Internet » est placée **après** les exceptions vers le LAN maison (vers `pve01`) et porte elle-même `ip daddr != $LAN_MAISON` : sans cette condition, n'importe quelle VM de la sandbox joindrait ta box, ton NAS et tes PC, puisque le LAN maison est aussi « derrière `ens18` ».

*Journaliser sans se tromper de décision.* `limit rate … log …` sans verdict, puis `counter` : la limite empêche une rafale de remplir le journal, et le paquet finit de toute façon sur la politique `drop`. Écrire `limit rate 10/minute log prefix "…" drop` serait une erreur : au-delà de la limite, la règle ne correspond plus, et le paquet continuerait vers les règles suivantes. Dans une chaîne terminée par la politique, c'est sans conséquence ; au milieu d'une chaîne, cela peut laisser passer ce qu'on voulait bloquer.

*Traduction d'adresse.* `masquerade` remplace l'adresse source par celle de `ens18`. Comme `<IP-GW01-WAN>` est fixe, `snat to <IP-GW01-WAN>` conviendrait aussi ; `masquerade` reste correct si l'adresse change un jour. L'exception `ip daddr != $PVE01` : `pve01` a une route de retour vers 10.10.0.0/16, il peut donc recevoir les vraies adresses du lab, ce qui rend ses journaux et son futur pare-feu (E27) exploitables. Le reste du LAN maison n'a pas cette route : sans traduction, il ne saurait pas répondre.

*`output` en `accept`.* `gw01` initie lui-même peu de trafic (mises à jour, DNS, NTP amont, tunnels) ; on filtre ce qui entre et ce qui traverse. Un filtrage en sortie est un durcissement possible, au prix de règles supplémentaires à maintenir.

*Les réglages `sysctl`* sont expliqués ligne par ligne dans `99-routeur.conf`. Le filtrage par chemin inverse strict (`rp_filter = 1`) bloque l'usurpation d'adresse entre VLANs : un paquet qui arrive sur `ens19.99` avec une source 10.10.10.10 est rejeté, puisque la route vers 10.10.10.10 passe par `ens19.10`.

*Route sur `pve01`.* `up ip route replace …` dans la strophe de `vmbr0` : la route est posée chaque fois que `vmbr0` monte ; `replace` évite une erreur si elle existe déjà. La route vers 10.20.0.0/16 ne sert qu'à partir du tunnel de l'E21, mais elle évite qu'entre-temps le trafic vers PAR2 parte vers la box. Celle vers 10.255.1.0/24 servira en E16 : `pve01` pourra répondre directement, par `gw01`, à un poste connecté au VPN d'administration (sans elle, ses réponses partiraient vers la box).

**Alternatives**

- *systemd-networkd* au lieu d'ifupdown : fichiers `.netdev` (VLAN) et `.network` par interface. Plus moderne, plus verbeux pour neuf VLANs.
- *iptables-nft* ou *firewalld* : même moteur netfilter, syntaxe différente ; firewalld raisonne en zones, pratique sur un serveur, moins lisible pour un routeur.
- *Une carte virtuelle par VLAN* (`net1` à `net9` avec `tag=`) au lieu d'un trunk : pas de sous-interfaces, mais neuf cartes, et chaque nouveau VLAN impose de modifier le matériel de la VM.
- *`trunks=10;20;30;40;50;52;60;70;99`* sur `net1` : limite les VLANs que `gw01` voit. Plus sûr ; mais chaque nouveau VLAN routé demande de modifier aussi la VM.
- *Une distribution routeur* (VyOS, OPNsense) : configuration plus déclarative ou graphique, moins de primitives Linux à apprendre.

**Pièges classiques**

- Appliquer la configuration réseau en SSH par `ens18` : la session coupe au milieu. Toujours depuis la console.
- Type de machine `q35` et noms de cartes inattendus.
- `<IP-GW01-WAN>` dans la plage DHCP de la box : un jour, la box attribue la même adresse à un autre appareil, et `gw01` devient intermittent (E02, question 5).
- Oublier `systemctl enable nftables` : **sur Debian, le service est désactivé par défaut**. Les règles disparaissent au premier redémarrage, et le routeur repart totalement ouvert.
- Oublier `flush ruleset` en tête de fichier : chaque rechargement ajoute les règles en double.
- Oublier `ct state established,related accept` dans `forward` : seul le premier paquet passe, aucune connexion ne s'établit.
- Oublier `ip daddr != $LAN_MAISON` dans la règle de sortie : le lab accède au réseau domestique.
- Nommer le fichier `sudoers` avec un point (`90-workbook.conf`) : ignoré.
- Interdire l'authentification par mot de passe **avant** d'avoir copié la clé : il ne reste que la console.
- Modifier ensuite `vmbr0` dans l'interface web de Proxmox : vérifie que tes lignes `up` sont toujours là après coup (`grep 10.10.0.0 /etc/network/interfaces`).

**En production chez MédiSphère**

Deux routeurs en haute disponibilité (VRRP, module 07), configuration générée par Ansible depuis un dépôt Git revu par l'équipe sécurité (la matrice de flux devient un fichier de données, les règles en sont dérivées), journaux de refus envoyés vers la plateforme de logs (module 22), compteurs exportés vers la supervision (module 21), sauvegarde de `/etc` versionnée (`etckeeper`), console hors bande toujours disponible, et toute modification de règle tracée par un ticket `SEC-` ou `CHG-`.

---

### M00-E11 — Fabriquer le template cloud-init `tpl-debian13`

**Solution**

Fichiers : [`fichiers/M00-E11/vendor-debian13.yaml`](fichiers/M00-E11/vendor-debian13.yaml) et le script complet [`fichiers/M00-E11/creer-tpl-debian13.sh`](fichiers/M00-E11/creer-tpl-debian13.sh).

*1. Image.*
```
root@pve01:~# mkdir -p /mnt/hdd-bulk/import && cd /mnt/hdd-bulk/import
root@pve01:/mnt/hdd-bulk/import# wget https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
root@pve01:/mnt/hdd-bulk/import# wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
root@pve01:/mnt/hdd-bulk/import# sha512sum -c --ignore-missing SHA512SUMS
debian-13-genericcloud-amd64.qcow2: OK
root@pve01:/mnt/hdd-bulk/import# qemu-img info debian-13-genericcloud-amd64.qcow2 | grep -E 'format|virtual size'
file format: qcow2
virtual size: 3 GiB (3221225472 bytes)
```
(Taille virtuelle donnée à titre indicatif : elle varie selon les publications.)

*2. Snippet* : copier `vendor-debian13.yaml` dans `/mnt/hdd-bulk/snippets/`, puis `pvesm list hdd-bulk --content snippets` doit le lister.

*3 à 5. La VM, le disque, cloud-init.*
```
root@pve01:~# qm create 9000 --name tpl-debian13 --pool lab --tags "debian13;template" \
    --ostype l26 --cpu x86-64-v2-AES --cores 2 --memory 2048 \
    --scsihw virtio-scsi-single --net0 virtio,bridge=vmbr1 \
    --serial0 socket --vga serial0 --agent enabled=1,fstrim_cloned_disks=1
root@pve01:~# qm disk import 9000 /mnt/hdd-bulk/import/debian-13-genericcloud-amd64.qcow2 local-nvme
root@pve01:~# qm config 9000 | grep unused
unused0: local-nvme:vm-9000-disk-0
root@pve01:~# qm set 9000 --scsi0 local-nvme:vm-9000-disk-0,discard=on,iothread=1,ssd=1 --boot order=scsi0
root@pve01:~# qm disk resize 9000 scsi0 8G
root@pve01:~# qm set 9000 --ide2 local-nvme:cloudinit --ciuser admin \
    --sshkeys /root/.ssh/id_ed25519_lab.pub --nameserver 10.10.20.10 \
    --searchdomain par1.medisphere.internal \
    --cicustom "vendor=hdd-bulk:snippets/vendor-debian13.yaml"
```
Le nom du volume importé dépend du type de stockage (`local-nvme:vm-9000-disk-0` en LVM-thin ou ZFS, `<stockage>:9000/vm-9000-disk-0.raw` en répertoire) : lis-le dans `unused0`.

*6. Inspection.*
```
root@pve01:~# qm cloudinit dump 9000 user
#cloud-config
hostname: tpl-debian13
manage_etc_hosts: true
fqdn: tpl-debian13.par1.medisphere.internal
user: admin
ssh_authorized_keys:
  - ssh-ed25519 AAAA… root@pve01 - lab MédiSphère
chpasswd:
  expire: False
package_upgrade: true
```
(Sortie indicative : son contenu exact dépend de la version de Proxmox VE.) Le nom d'hôte vient du **nom de la VM**, l'utilisateur de `ciuser`, la clé de `sshkeys`. `user: admin` renomme l'utilisateur par défaut de l'image : il hérite de ses propriétés, dont `sudo` sans mot de passe (cloud-init écrit `/etc/sudoers.d/90-cloud-init-users` au premier démarrage). C'est ainsi que `adm01`, `dns01` et tous les clones respectent la convention « `admin` + `sudo -n` » sans fichier posé à la main, contrairement à `gw01` (E10). `qm cloudinit dump 9000 network` montre la configuration réseau (vide ou en DHCP tant que `ipconfig0` n'est pas défini : chaque clone le fixera).

*7. Conversion.*
```
root@pve01:~# qm template 9000
root@pve01:~# qm config 9000 | grep -E '^(template|scsi0)'
scsi0: local-nvme:base-9000-disk-0,discard=on,iothread=1,size=8G,ssd=1
template: 1
```
Le volume est renommé `base-9000-disk-0` et devient en lecture seule.

*8. Pourquoi ne pas démarrer avant de convertir ?* Au premier démarrage, cloud-init s'exécute et crée l'état de l'instance : clés d'hôte SSH, `/etc/machine-id`, répertoire `/var/lib/cloud/instance`, paquets installés, baux DHCP. Tous les clones hériteraient des **mêmes clés d'hôte SSH** (usurpation entre VMs indétectable) et du **même machine-id** (identifiants DHCP en collision, journaux confondus), et cloud-init pourrait considérer que le premier démarrage a déjà eu lieu. Si on a démarré par erreur : `cloud-init clean --logs --machine-id` dans la VM, suppression des clés d'hôte, arrêt, puis conversion.

**Explications**

*Image genericcloud.* Debian publie plusieurs images : *generic* (tous les pilotes, pour le matériel réel et les cas particuliers), *genericcloud* (noyau allégé pour les environnements virtualisés avec périphériques virtio, plus petit), *nocloud* (sans cloud-init). *genericcloud* convient à des VMs Proxmox en virtio. Elle n'a ni mot de passe, ni agent QEMU : cloud-init fournit l'accès, le *vendor-data* l'agent.

*Le lecteur cloud-init.* Proxmox génère, à chaque démarrage, une petite image au format *NoCloud* attachée en `ide2`, contenant `meta-data` (identifiant d'instance), `user-data` (utilisateur, clé, nom d'hôte), `network-config` (adresses, passerelle, DNS) et éventuellement `vendor-data`. cloud-init, dans la VM, la lit au démarrage. `cicustom` permet de remplacer l'un de ces fichiers par un snippet. Remplacer `user` ferait perdre tout ce que Proxmox génère depuis `ciuser`/`sshkeys` ; `vendor` est **fusionné**, avec une priorité inférieure au *user-data* : c'est l'endroit des réglages communs.

*Le matériel.* `virtio-scsi-single` crée un contrôleur par disque, ce qui permet un `iothread` par disque (E/S traitées dans leur propre thread, hors de la boucle principale de QEMU). `discard=on` transmet les TRIM de l'invité au stockage à allocation fine : les blocs libérés dans la VM sont rendus au *thin pool*. `ssd=1` présente le disque comme non rotatif à l'invité. `fstrim_cloned_disks` déclenche un `fstrim` par l'agent après un clonage. La console série (`serial0: socket`, `vga: serial0`) : l'image *genericcloud* envoie sa console sur `ttyS0` ; `qm terminal` et la console *xterm.js* de l'interface web y donnent accès même sans réseau.

*Type de CPU `x86-64-v2-AES`* : un modèle générique, migrable entre hôtes de générations différentes (utile dès qu'il y a un cluster), avec les instructions AES (chiffrement rapide). Les nœuds imbriqués du module 09 utiliseront `host`.

**Alternatives**

- `import-from` : `qm set 9000 --scsi0 local-nvme:0,import-from=/mnt/hdd-bulk/import/debian-13-genericcloud-amd64.qcow2,discard=on,iothread=1,ssd=1` importe et rattache en une commande.
- Intégrer l'agent **dans l'image** (`virt-customize --install qemu-guest-agent`, paquet `libguestfs-tools`) : plus besoin de réseau au premier démarrage, mais on modifie l'image amont et il faut un processus de reconstruction. C'est l'approche du module 03 avec Packer.
- Mettre les snippets sur `local` plutôt que `hdd-bulk` : voir les pièges.

**Pièges classiques**

- `cicustom user=…` au lieu de `vendor=…` : plus de clé SSH, impossible de se connecter.
- Snippet sans la première ligne `#cloud-config` : cloud-init ne le traite pas comme une configuration.
- Erreur d'indentation YAML : la directive est ignorée en silence ou cloud-init signale une erreur de schéma (`cloud-init schema --system` dans la VM, `/var/log/cloud-init.log`).
- Stockage sans le contenu `snippets` : `qm set` refuse la référence.
- **Dépendance cachée** : Proxmox régénère le lecteur cloud-init à **chaque démarrage** des clones, en relisant le snippet. Si `hdd-bulk` est hors ligne (disque non monté, `is_mountpoint`), les VMs qui l'utilisent ne démarrent plus. Accepté dans le lab ; en production, les snippets vont sur un stockage aussi fiable que les VMs.
- Démarrer le template « pour vérifier » avant `qm template`.
- Oublier `--boot order=scsi0` : la VM tente de démarrer sur le réseau ou sur le lecteur cloud-init.
- Un disque de 3 Go laissé tel quel : le système de fichiers racine des clones est plein dès les premières mises à jour.

**En production chez MédiSphère**

Les templates sont produits par une chaîne automatisée (Packer, module 03), versionnés (`tpl-debian13-2026.10`), durcis selon un référentiel (CIS), reconstruits régulièrement pour intégrer les correctifs de sécurité, et les anciens retirés. Aucun secret dans le *vendor-data* : les snippets sont lisibles sur le stockage par quiconque y a accès. Les mots de passe et jetons arrivent par un gestionnaire de secrets (module 25).

---

### M00-E12 — Déployer `adm01` et `dns01` depuis le template

**Solution**

Script reproductible : [`fichiers/M00-E12/deployer-socle.sh`](fichiers/M00-E12/deployer-socle.sh) (`./deployer-socle.sh 9.9.9.9`).

`adm01` : commandes de l'énoncé. `dns01` :
```
root@pve01:~# qm clone 9000 1002 --name dns01 --full 1 --pool lab --storage local-nvme
root@pve01:~# qm set 1002 --cores 1 --memory 1024 --tags "socle;dns" \
    --net0 virtio,bridge=vmbr1,tag=20 \
    --ipconfig0 ip=10.10.20.10/24,gw=10.10.20.1 \
    --nameserver <DNS-PUBLIC> --searchdomain par1.medisphere.internal \
    --onboot 1 --startup order=2
root@pve01:~# qm start 1002
root@pve01:~# qm terminal 1002            # Ctrl+O pour sortir
```
Pendant le premier démarrage, la console série montre les étapes de cloud-init, dont l'installation de `qemu-guest-agent`. Puis :
```
root@pve01:~# qm guest cmd 1002 ping && echo "agent OK"
root@pve01:~# qm guest cmd 1002 network-get-interfaces | grep -A1 '"ip-address"' | head
```
Les alias `adm01` et `dns01` sont déjà dans [`pve01-root-ssh-config`](fichiers/M00-E10/pve01-root-ssh-config). Vérifications dans les VMs :
```
root@pve01:~# ssh adm01 'hostname -f; cloud-init status --long | head -n 3; df -h /; systemctl is-active qemu-guest-agent'
adm01.par1.medisphere.internal
status: done
…
/dev/sda1        20G  1.4G   18G   8% /
active
root@pve01:~# ssh adm01 'curl -sI https://deb.debian.org | head -n 1'
HTTP/2 200
root@pve01:~# ssh adm01 'ping -c 2 10.10.20.10'        # MGMT vers INFRA : autorisé
root@pve01:~# ssh dns01 'ping -c 2 -W 2 10.10.10.10'   # INFRA vers MGMT : doit échouer
2 packets transmitted, 0 received, 100% packet loss
```

**Explications**

*Clone complet ou lié.* Un clone **lié** partage le volume de base du template (`base-9000-disk-0`) et n'enregistre que les différences : instantané, économe en place, mais dépendant du template (impossible de le supprimer tant qu'un clone lié existe) et du même stockage. Un clone **complet** copie tout : plus lent, indépendant. Pour le socle, qui doit vivre longtemps et survivre à une refonte du template, on prend des clones complets. Attention : depuis un template, `qm clone` fait un clone **lié par défaut** quand le stockage le permet ; `--full 1` est indispensable. `--storage` n'est valable que pour un clone complet.

*Ce que fait cloud-init au premier démarrage.* Proxmox construit `network-config` à partir de `ipconfig0`, `nameserver` et `searchdomain`, et `user-data` à partir de `ciuser`, `sshkeys` et du **nom de la VM** (nom d'hôte, et nom complet construit avec le domaine de recherche). Dans la VM, cloud-init agrandit la partition et le système de fichiers racine à la taille du disque (`growpart`, `resizefs`), configure le réseau, crée `admin` avec la clé et `sudo` sans mot de passe (`/etc/sudoers.d/90-cloud-init-users`, d'où le `sudo -n true` qui réussit sans rien configurer), génère les clés d'hôte SSH, puis applique le *vendor-data* (agent QEMU, fuseau horaire).

*`net0` reconfiguré.* `qm set --net0 virtio,bridge=vmbr1,tag=10` sans adresse MAC en génère une nouvelle : sans importance avant le premier démarrage. Pour modifier une carte existante sans changer de MAC, reprends la MAC actuelle (`virtio=<MAC>,bridge=…`).

*Ordre de démarrage.* `startup order=` : `gw01` (1), puis `dns01` (2), puis `adm01` (3). À l'arrêt de l'hôte, l'ordre est inversé. Le paramètre `up=` de `gw01` (30 s) laisse au routeur le temps d'être opérationnel avant les suivants.

*Le résolveur provisoire* et la bascule de l'E13 (pour `adm01` **et** `dns01`, le template gardant 10.10.20.10) : `qm set 1001 --nameserver 10.10.20.10` met à jour la configuration cloud-init, appliquée au prochain démarrage. Selon la version de Proxmox VE, l'identifiant d'instance est dérivé du contenu cloud-init : un changement peut alors relancer les modules « par instance » de cloud-init, dont la **régénération des clés d'hôte SSH**. Attends-toi à un avertissement de clé changée (`ssh-keygen -R 10.10.10.10 -f /root/.ssh/known_hosts_lab`). L'alternative est de modifier la configuration DNS directement dans la VM, en gardant la configuration Proxmox cohérente.

**Alternatives**

- Clones liés pour aller plus vite (E19 les compare).
- Création par l'API (E18), puis par Terraform avec le provider `bpg/proxmox` (module 05), avec adresses attribuées par NetBox (module 06).
- *user-data* complet par VM (`cicustom user=`) quand la personnalisation dépasse ce que proposent les champs Proxmox : au prix de tout gérer soi-même.

**Pièges classiques**

- Oublier `--full 1` : clone lié, que le check signale.
- Oublier `--pool lab` : VM hors du pool, invisible pour `wb-admin`.
- Oublier `tag=` : la VM est dans le VLAN 1, sans passerelle, aucun réseau.
- `ipconfig0` sans `gw=` : pas de route par défaut (E02, question 24).
- Résolveur 10.10.20.10 avant que `dns01` ne serve : l'agent ne s'installe pas, `qm guest cmd … ping` échoue. Corrige le résolveur, redémarre la VM, ou installe l'agent à la main par la console série.
- Agrandir le disque **après** le premier démarrage : sans conséquence, `growpart` s'exécute à chaque démarrage, mais il faut redémarrer la VM.
- Recréer une VM avec la même adresse : nouvelle clé d'hôte, `accept-new` refuse la connexion (« REMOTE HOST IDENTIFICATION HAS CHANGED »). Nettoie l'entrée dans `known_hosts_lab`.
- Lancer `qm terminal` sur une VM sans `serial0` : rien ne s'affiche.

**En production chez MédiSphère**

Les VMs sont décrites en code (Terraform, module 05), leurs adresses réservées dans NetBox et leurs enregistrements DNS créés automatiquement (module 06) ; la configuration est appliquée par Ansible (module 04) ; l'inscription en supervision et en sauvegarde est automatique dès la création ; et la convention de nommage, d'étiquetage et de numérotation est vérifiée en revue de code plutôt qu'à l'œil.
