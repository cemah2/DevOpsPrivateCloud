# Module 09 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les fichiers complets sont dans [`fichiers/`](fichiers/), un dossier par exercice : `fichiers/M09-EXX/ansible/…` = chemins de `plateforme/ansible`, `…/infra/…` = `plateforme/infra`, `…/medisphere/…` = la documentation ; les scripts à la racine d'un dossier d'exercice se lancent sur l'hôte indiqué dans leur en-tête. Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête).

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Syntaxe des commandes Proxmox VE 9.2* : relevée dans les pages de manuel officielles de la version 9.2.13 (`ha-manager(1)`, `pveceph(1)`, `pvesr(1)`, `pvesm(1)`, `pvenode(1)`, `qm(1)`, `pveum(1)`, `datacenter.cfg(5)`, chapitre SDN) et dans le schéma de l'API (`apidoc.js`) : types et options des règles HA (`node-affinity`, `resource-affinity`, `--strict`, `--affinity`, priorités `nœud:prio`), `crm-command disarm-ha freeze|ignore` / `arm-ha`, options `crs` de 9.2 (`ha=basic|static|dynamic`, `ha-rebalance-on-start`, `ha-auto-rebalance*`), `pveceph install --repository … --version squid|tentacle`, `pvesm add rbd --keyring`, `--encryption-key autogen`, identifiants SDN (8 caractères, sans tiret pour une zone), paramètres de `/cluster/sdn/*`, `/cluster/backup`, `/pools?poolid=`.
- *Analyseur OVF* : le code de `PVE::GuestImport::OVF` (dépôt `pve-storage`) a été lu ; le descripteur produit par `generer-ova.sh` a été passé aux mêmes requêtes XPath (nom, 2 cœurs, 2048 Mo, contrôleur SCSI → `scsi0`, carte `e1000`, BIOS) ; `generer-ova.sh` a été exécuté de bout en bout (image Debian 13 vérifiée, VMDK *streamOptimized* de 10 Gio, archive OVA, manifeste).
- *PBS 4* : syntaxe de `proxmox-backup-manager` (`user`, `acl update … --delete`, `prune-job … --max-depth`) et de `proxmox-backup-client namespace` relevée dans la référence officielle.
- *Code* : `tofu validate` et `tofu fmt` (OpenTofu 1.13.1, `bpg/proxmox` 0.116.0) sur `envs/hv-invites` ; `ansible-lint` 26.9 (profil `production`) sur le rôle `pve_cluster` et les playbooks `hv-cluster.yml` et `hv-mise-a-jour.yml` ; `keepalived --config-test` sur la configuration rendue (seule erreur : l'interface `vmbr0` absente de la machine de test) ; ShellCheck 0.11 et `bash -n` sur tous les scripts.

**Non rejoués sur un cluster réel** : le comportement du CRS (rapidité de l'équilibrage, refus d'une migration contraire à une règle), les libellés exacts de `ha-manager status` en 9.2 (ligne de *fencing*), la sortie de `pveceph install` (nom du fichier de dépôt), le démarrage de l'image cloud de Debian sur un contrôleur LSI émulé, la génération FRR de la zone EVPN, le comportement d'un *live-restore* chiffré, l'émission du certificat par l'autorité du cluster et `pvenode cert set`. Ils sont signalés « ⚠️ À vérifier sur ton lab » : signale tes retours.

---

### M09-E10 — Ceph hyperconvergé

**Solution**

Fichier : [`ceph-hyperconverge.sh`](fichiers/M09-E10/ceph-hyperconverge.sh) (étapes 3 à 8, rejouable, refuse un disque de mauvaise taille ou déjà utilisé).

1. **MTU.** Sur chaque nœud, vers les deux autres, sur les deux réseaux :
   ```
   root@hv01:~# for ip in 10.10.30.72 10.10.30.73 10.10.31.72 10.10.31.73; do ping -c 2 -M do -s 8972 $ip; done
   ```
   8972 = 9000 − 20 (IPv4) − 8 (ICMP). `-M do` interdit la fragmentation : si un seul maillon (carte de la VM `hv0N`, `vmbr1` de `pve01`, interface dans le nœud) est à 1500, le `ping` échoue avec « message too long » au lieu de passer en morceaux. Ceph aurait fonctionné quand même… jusqu'au premier gros transfert de réplication, avec des blocages difficiles à expliquer (M09-E39 te le fera vivre).
2. **Installation**, sur chacun des trois nœuds (la commande demande confirmation) :
   ```
   root@hv01:~# pveceph install --repository no-subscription --version squid
   ```
   Elle écrit le dépôt Ceph de Proxmox dans `/etc/apt/sources.list.d/` (fichier `ceph.sources`, au format deb822 depuis Proxmox VE 9 — ⚠️ nom à vérifier sur ton lab), puis installe `ceph`, `ceph-mon`, `ceph-mgr`, `ceph-osd`… depuis ce dépôt, pas depuis Debian. Sans `--version`, Proxmox VE 9.2 aurait installé **Tentacle** (défaut pour les nouvelles installations) : on veut reproduire le parc d'InfoGér en Squid pour pratiquer la montée de version en E28.
3. **Initialisation**, une seule fois, depuis un seul nœud :
   ```
   root@hv01:~# pveceph init --network 10.10.30.0/24 --cluster-network 10.10.31.0/24
   root@hv01:~# cat /etc/pve/ceph.conf
   [global]
        auth_client_required = cephx
        …
        cluster_network = 10.10.31.0/24
        fsid = …
        mon_allow_pool_delete = true
        osd_pool_default_min_size = 2
        osd_pool_default_size = 3
        public_network = 10.10.30.0/24
   root@hv02:~# ls -l /etc/ceph/ceph.conf
   lrwxrwxrwx 1 root root 18 … /etc/ceph/ceph.conf -> /etc/pve/ceph.conf
   ```
   La configuration est dans **pmxcfs** : écrite une fois, présente sur tous les nœuds, sous le même verrou de quorum que le reste de `/etc/pve`. `/etc/ceph/ceph.conf` n'est qu'un lien symbolique vers elle (posé par `pveceph`), parce que les outils Ceph le cherchent là. Remarque `mon_allow_pool_delete = true` : Proxmox l'active pour que la suppression d'un pool depuis son interface fonctionne ; c'est l'inverse du réglage que tu remets en E12 sur `ceph-par1` (cluster partagé). Discute-le en E26.
4. **MON et MGR** : `pveceph mon create` et `pveceph mgr create` sur chaque nœud. `ceph -s` : `mon: 3 daemons, quorum hv01,hv02,hv03` et `mgr: hv01(active), standbys: hv02, hv03`. **Un seul MGR actif** à la fois (les autres sont en attente et prennent le relais en quelques secondes). Trois MON parce que leur quorum est une **majorité** (Paxos) : avec 2, la perte d'un seul bloque tout (1/2 n'est pas une majorité) ; avec 4, on tolère toujours une seule panne (3/4) pour un démon de plus. Même raisonnement que le quorum de Corosync (M09-E04).
5. **Mémoire** :
   ```
   root@hv01:~# ceph config set osd osd_memory_target 1073741824
   root@hv01:~# ceph config get osd osd_memory_target
   1073741824
   ```
   `osd_memory_target` est une **cible** pour l'auto-ajustement des caches de BlueStore (`bluestore_cache_autotune`) : l'OSD réduit ses caches pour que sa mémoire résidente tende vers cette valeur. Ce n'est **pas** une limite : pendant une récupération ou un *backfill*, un OSD peut la dépasser franchement, et rien ne le tue. En dessous d'environ 1 à 2 Gio, les caches tombent à leur minimum et les lectures repartent sur disque : acceptable dans un lab, à proscrire en production. Le régler **avant** de créer les OSD évite qu'ils démarrent avec 4 Gio de cible sur un nœud de 12 Go.
6. **OSD** : `pveceph osd create /dev/disk/by-id/<disque>` (deux par nœud). `ceph osd tree` :
   ```
   ID  CLASS  WEIGHT   TYPE NAME      STATUS
   -1         0.28117  root default
   -3         0.09372      host hv01
    0    ssd  0.04686          osd.0   up
    1    ssd  0.04686          osd.1   up
   …
   ```
   La classe est `ssd` : les disques des nœuds sont déclarés avec l'option `ssd=1` (M09-E03, `ssd = true` dans OpenTofu), que QEMU présente comme non rotatifs (`/sys/block/sdX/queue/rotational` = 0). Sans cette option, un disque virtuel se déclare rotatif et l'OSD est classé `hdd` (⚠️ classe exacte à relever sur ton lab). Sans conséquence ici (une seule classe) ; à corriger (`ceph osd crush rm-device-class` puis `set-device-class`) si une règle CRUSH filtrait par classe. Chaque hôte est une branche de l'arbre : la règle par défaut place les copies sur des **hôtes** différents.
7. **Pool et stockage** :
   ```
   root@hv01:~# pveceph pool create ceph-vm --size 3 --min_size 2 --pg_autoscale_mode on --application rbd --add_storages 1
   root@hv01:~# grep -A4 '^rbd: ceph-vm' /etc/pve/storage.cfg
   rbd: ceph-vm
           content images
           krbd 0
           pool ceph-vm
   ```
   Pas de `monhost`, pas d'`username`, pas de trousseau dédié : un stockage RBD **sans** `monhost` est, pour Proxmox, le Ceph **du cluster** ; il lit `/etc/pve/ceph.conf` et la clé `client.admin` gérée par `pveceph`. Un stockage externe (E12) a des moniteurs explicites et son propre trousseau dans `/etc/pve/priv/ceph/`. `--pg_autoscale_mode on` est explicite : la valeur par défaut de `pveceph` est `warn` (l'autoscaler conseille sans agir).
8. **Contrôle** : `ceph -s` → `HEALTH_OK`, `6 osds: 6 up, 6 in`, `pools: 2 pools` (le pool `.mgr` créé par le gestionnaire, plus `ceph-vm`). Avertissements fréquents à ce stade : *clock skew* (les nœuds doivent se synchroniser sur la passerelle de leur VLAN MGMT, 10.10.10.1, comme tout le lab : vérifie `chronyc sources` — un nœud resté sur le `pool` Debian par défaut dérive), PG en cours d'ajustement juste après la création (disparaît en quelques minutes).
9. **Pannes** (avec 3 hôtes, `size 3`, `min_size 2`, domaine de panne `host`) :
   - (a) un OSD : les PG qu'il portait passent `degraded` (2 copies sur 3) ; les écritures continuent ; au bout de `mon_osd_down_out_interval` (10 min par défaut), l'OSD est marqué `out` et Ceph recrée la troisième copie… sur l'**autre OSD du même hôte** (seul emplacement qui respecte « un hôte par copie ») : vérifie la place libre.
   - (b) un nœud : 2 copies, les écritures continuent ; **aucune** reconstruction possible (il n'existe pas de quatrième hôte) : les PG restent `undersized+degraded` jusqu'au retour du nœud. 2 MON sur 3 : quorum conservé.
   - (c) deux nœuds : 1 copie < `min_size` → les E/S **bloquent** sur tous les PG ; de toute façon les MON ont perdu leur quorum (1/3) et le cluster Proxmox aussi : tout est figé, sans perte de données, jusqu'au retour d'un nœud.

**Explications**

`pveceph` est une surcouche fine : il écrit la configuration dans pmxcfs, crée les clés (`/etc/pve/priv/ceph.client.admin.keyring`), déploie les démons comme services systemd classiques (`ceph-mon@hv01`, `ceph-osd@0`…, pas de conteneurs, à la différence de cephadm au M08) et crée les stockages Proxmox. Tout le reste est du Ceph standard : `ceph`, `ceph config`, `ceph osd …` fonctionnent comme sur `ceph-par1`. L'intérêt de l'hyperconvergence est l'absence de réseau de stockage externe et de matériel dédié ; son coût est la concurrence entre Ceph et les VMs pour la mémoire et le CPU des mêmes nœuds, et le fait qu'une maintenance de nœud est aussi une maintenance de stockage (E19, E22).

**Alternatives**
- *Tentacle dès le départ* (défaut de 9.2) : pas de montée de version à pratiquer ; en production, c'est le bon choix pour un cluster neuf.
- *Pool à codage d'effacement* (EC 2+1) : 1,5× au lieu de 3× d'espace, mais 3 hôtes est le strict minimum, pas de marge, et RBD sur EC exige un pool de métadonnées répliqué : réservé aux gros volumes froids.
- *`size 2 / min_size 1`* : à proscrire (une seule copie écrite pendant une panne, risque de perte et de divergence).

**Pièges classiques**
- `pveceph osd create /dev/sdb` sur le disque ZFS ou système : les noms `sdX` dépendent de l'ordre de détection. Toujours `by-id` + taille + absence de signature (`wipefs -n`).
- Disque qui a déjà porté quelque chose : `pveceph` refuse (« has a holder », signature LVM) ; `ceph-volume lvm zap --destroy` ou `wipefs -a` après **vérification**.
- `pveceph init` relancé avec d'autres réseaux : la commande est idempotente et **ignore** silencieusement les nouveaux paramètres si `[global]` existe (relis son aide). Changer le réseau public après coup est une opération lourde (moniteurs à recréer).
- `ceph config set osd.0 …` au lieu de `osd` : ne vaut que pour un démon.
- MTU 9000 dans le nœud mais 1500 sur la carte de la VM `hv0N` (`mtu=` de `net2`/`net3` côté `pve01`) : les petits paquets passent (heartbeats), les gros non.

**En production chez MédiSphère**
Réseau Ceph physiquement séparé et redondant (bond LACP 2 × 25 Gb/s), disques NVMe en classe `ssd`, au moins 4 Gio par OSD, cinq nœuds pour pouvoir reconstruire après la perte d'un hôte, alertes sur `HEALTH_WARN` et sur le remplissage (`nearfull` à 75 %), et le tableau de bord de Ceph derrière l'authentification centrale (M24).

---

### M09-E11 — Stockage partagé et migration à chaud

**Solution**

Mesure : un simple `ping` à 0,2 s depuis `adm01` suffit ici (la coupure d'une migration à chaud se compte en dizaines de millisecondes). L'outil de mesure de coupure **vue d'un client TCP**, `mesure-coupure.sh`, est fourni plus tard (M09-E24), quand on mesure des interruptions de plusieurs minutes.

1. **Le template.** `lvs` et `qm config` des invités montrent si des clones **liés** de 199 existent (un disque `local-lvm:base-199-disk-0/vm-1NN-disk-0` désigne un clone lié ; `app01` et `app02` sont des clones **complets** sur `zfs-local`, M09-E07). Deux voies : déplacer le disque du template (`qm disk move 199 scsi0 ceph-vm`), que Proxmox refuse tant que des clones liés en dépendent (⚠️ à vérifier sur ta version : le déplacement d'un disque de template sans clone lié est accepté sur les versions récentes) ; ou **reconstruire** le template sur `ceph-vm` avec le script de M09-E06 (`ssh hv01 'bash -s' -- --stockage ceph-vm --remplacer < outils/hv/creer-tpl-nested.sh`). Le corrigé reconstruit : la procédure est rejouée (elle sert en E46) et le résultat est propre. Avant de détruire l'ancien template : plus aucun clone lié (`qm destroy` refuserait).
2. **Disques des VMs, à chaud** (`app01` sur `hv01`, puis `app02`) :
   ```
   root@hv01:~# qm disk move 101 scsi0 ceph-vm --delete 1
   create full clone of drive scsi0 (zfs-local:vm-101-disk-0)
   drive mirror is starting for drive-scsi0
   drive-scsi0: transferred 1.1 GiB of 8.0 GiB (13.75%) in 1s
   …
   drive-scsi0: mirror-job finished
   ```
   QEMU **recopie** le disque pendant que la VM tourne (*drive-mirror* : copie de fond + écritures dupliquées), puis bascule sur la copie. Sans `--delete 1`, l'ancien volume reste attaché en `unused0` : rien n'est perdu, mais la place reste prise et l'oubli est fréquent. Le lecteur cloud-init (`ide2`) se déplace de la même manière (ou se recrée). `app03` : `qm clone 199 103 --name app03 --full 1 --storage ceph-vm`, puis démarrage.
3. **Clones** :
   ```
   root@hv01:~# qm clone 199 104 --name essai-complet --full 1 --storage ceph-vm
   root@hv01:~# qm clone 199 105 --name essai-lie --full 0
   root@hv01:~# rbd du -p ceph-vm
   NAME                       PROVISIONED  USED
   base-199-disk-0@__base__         8 GiB  1.1 GiB
   base-199-disk-0                  8 GiB      0 B
   vm-104-disk-0                    8 GiB  1.1 GiB
   vm-105-disk-0                    8 GiB      0 B
   root@hv01:~# rbd info ceph-vm/vm-105-disk-0 | grep parent
           parent: ceph-vm/base-199-disk-0@__base__
   root@hv01:~# rbd children ceph-vm/base-199-disk-0@__base__
   ceph-vm/vm-105-disk-0
   ```
   (Valeurs indicatives.) Le clone lié est un *clone* RBD de l'instantané **protégé** du template : il ne consomme que ce qui diverge. Supprimer le template est **refusé** tant que l'instantané a des enfants ; si on forçait (`rbd flatten` des enfants d'abord), chaque clone récupérerait une copie complète. C'est la même dépendance qu'en M03 avec LVM-thin, mais visible et gérée par Ceph. `qm destroy 104` puis `qm destroy 105` ensuite.
4. **Migration à chaud, disque sur Ceph** :
   ```
   admin@adm01:~$ ping -D -O -i 0.2 <IP-APP01>       # -O : signale chaque réponse manquante
   root@hv01:~# qm migrate 101 hv02 --online
   …
   migration active, transferred 312.0 MiB of 1.0 GiB VM-state, 512.0 MiB/s
   average migration speed: 410.2 MiB/s - downtime 41 ms
   migration finished successfully (duration 00:00:06)
   ^C                                                 # côté adm01, après la migration
   --- <IP-APP01> ping statistics ---
   61 packets transmitted, 61 received, 0% packet loss, time 12003ms
   ```
   `<IP-APP01>` : adresse DHCP de `app01` (lue par l'agent : `qm agent 101 network-get-interfaces`). Ordre de grandeur attendu : quelques secondes de migration pour 1 Gio de mémoire, *downtime* de quelques dizaines de millisecondes, 0 ou 1 paquet perdu à 0,2 s d'intervalle (⚠️ libellés du journal à vérifier sur ta version).
5. **Disque local** (VM 106 sur `local-lvm`) : `qm migrate 106 hv02 --online` refuse (« can't migrate local disk … use --with-local-disks ») ; avec `--with-local-disks`, Proxmox crée un disque vide sur la cible, recopie le disque par NBD (*drive-mirror* vers la cible) **puis** la mémoire : la durée est dominée par la taille du disque (une minute ou plus pour 8 Gio sur MGMT à 1 Gb/s), la coupure finale reste courte. Le prix est la durée et la charge réseau, pas l'interruption. `qm destroy 106`.
6. **Pourquoi pas de copie du disque** : avec Ceph, le disque n'est pas « sur » un nœud ; les deux QEMU (source et cible) savent ouvrir la même image RBD. La migration ne transfère que la **mémoire** et l'état des périphériques ; à la bascule, la source relâche l'image et la cible la reprend. **Obstacles** même avec un stockage partagé : un type de CPU absent de la cible (`host` sur des processeurs différents : instructions disparues → refus ou plantage), un périphérique local (passage PCI, USB, ISO sur un stockage local de la source : M09-E38), un pont ou VNet absent de la cible, des versions de QEMU incompatibles (migration vers une version plus ancienne).

**Explications**

La migration à chaud fait du *pre-copy* : copie de toute la mémoire pendant que la VM tourne, puis recopie des pages modifiées entre-temps, par passes de plus en plus courtes ; quand le reste tient dans le *downtime* maximal, la VM est suspendue, le reste et l'état des périphériques sont envoyés, la cible démarre. Une VM qui écrit sa mémoire plus vite que le réseau ne la transfère ne converge pas : QEMU ralentit alors le vCPU (*auto-converge*). D'où l'intérêt d'un réseau de migration rapide et dédié (M09-E27) et d'une `bwlimit` raisonnable.

**Alternatives**
- *Recréer les VMs par clonage* sur `ceph-vm` au lieu de déplacer leurs disques : plus simple quand elles ne contiennent rien ; c'est ce que fera le code (E18, E46).
- *Clones liés partout* : économe en place, mais toute la flotte dépend d'un template qu'on ne peut plus remplacer facilement : le workbook garde les clones **complets** pour les VMs durables (décision M03).

**Pièges classiques**
- `qm disk move` sans `--delete` : les `unused0` s'accumulent et remplissent `local-lvm`.
- Migrer une VM qui a un lecteur CD-ROM monté depuis `local` : refus (« can't migrate VM with local CD/DVD »).
- Mesurer la coupure avec un `ping` à 1 s : la coupure réelle (50 ms) ne se voit pas ; à l'inverse, une perte isolée à 0,2 s n'est pas une coupure perçue par un client TCP.
- Confondre `migrate` (à chaud) et `relocate` (arrêt, puis démarrage ailleurs) en HA (E13).

**En production chez MédiSphère**
Les VMs de production n'ont aucun disque local ; une vérification planifiée (supervision, M09-E25) signale tout disque hors de `ceph-vm` sur les VMs des pools `prod`. Le template est reconstruit par le pipeline des images (M03) puis importé dans le cluster.

---

### M09-E12 — Consommer le Ceph de PAR1

**Solution**

Procédure complète et retrait : [`docs/virtualisation/stockage-externe.md`](fichiers/M09-E12/medisphere/docs/virtualisation/stockage-externe.md) (c'est aussi le livrable de l'étape 9).

1. `ceph01-03` : `qm start 2081 2082 2083` sur `pve01` (après `free -g` : environ 18 Go de plus) ; `ceph -s` sur `ceph01` (`cephadm shell -- ceph -s`) jusqu'à `HEALTH_OK`.
2. Pool et identité : voir la procédure, section *Raccordement*. `profile rbd` : sur `mon`, lire les cartes et autoriser les opérations RBD qui passent par les moniteurs (liste noire d'un client défaillant, *blocklist*, pour libérer un verrou exclusif) ; sur `osd`, lire et écrire les objets du pool désigné (et seulement lui : `pool=hv-par1`) ; sur `mgr`, les opérations RBD déléguées au gestionnaire (tâches de suppression ou d'aplatissement en fond, statistiques par image). `client.admin` permettrait à quiconque obtient `root` sur **un** nœud de `hv-par1` de supprimer tous les pools de `ceph-par1`, y compris ceux d'OpenStack.
3. Transport : `ssh … | ssh …` depuis `adm01` : la clé traverse `adm01` en mémoire (tuyau) sans y être écrite, ni sur `ceph01` (pas de `-o fichier`). Le fichier arrive sur `hv01` en 600 (`umask 077`). Copie Vault par le même tuyau vers `ansible-vault encrypt_string --stdin-name`.
4. `pvesm add rbd … --keyring /root/hv-par1.keyring` : Proxmox **copie** le trousseau dans `/etc/pve/priv/ceph/ceph-par1-rbd.keyring` (pmxcfs, dossier `priv` : lisible par `root` seul, répliqué sur les trois nœuds). La copie de travail est ensuite effacée (`shred -u`). C'est la raison de l'option : avant elle, il fallait déposer le fichier à la main à cet endroit, sous le nom exact du stockage.
5. Limites :
   ```
   root@hv01:~# rbd -c /dev/null -m 10.10.30.51 --id hv-par1 --keyring /etc/pve/priv/ceph/ceph-par1-rbd.keyring ls hv-par1
   root@hv01:~# rbd … ls volumes
   rbd: error opening pool 'volumes': (1) Operation not permitted
   root@hv01:~# ceph … osd pool create essai
   Error EACCES: access denied
   ```
   `-c /dev/null` évite que le client lise le `ceph.conf` du nœud (celui du Ceph hyperconvergé : autre `fsid`, autres moniteurs).
6. `qm disk move 103 scsi0 ceph-par1-rbd --delete 1`, puis `cephadm shell -- rbd ls hv-par1` sur `ceph01` → `vm-103-disk-0`. Arrêt d'un nœud de `ceph-par1` (`qm shutdown 2083` sur `pve01`) : la VM ne voit rien, sinon une pause de quelques secondes des écritures en vol (le temps que les PG élisent un nouveau primaire) ; `ceph-par1` en `HEALTH_WARN` (`1 host down`, PG `degraded`). Redémarrage : retour à `HEALTH_OK` après récupération.
7. Trois nœuds arrêtés : les E/S de `app03` **se figent** (QEMU attend indéfiniment la réponse de Ceph), la VM ne plante pas, la HA ne voit rien (le processus tourne, l'état est `running`). Pour le métier, c'est une panne ; pour le gestionnaire HA, tout va bien. Mélanger dans un même cluster des VMs HA et un stockage dont la santé n'est surveillée ni par la HA ni par la supervision du cluster, c'est créer une panne silencieuse : il faudrait au minimum superviser la latence RBD des VMs et l'état de `ceph-par1` depuis la supervision de `hv-par1` (M09-E25, M21).
8. Rangement : section *Retrait* de la procédure. Vérifications : `pvesm status` sans `ceph-par1-rbd` ; `ls /etc/pve/priv/ceph/` sans fichier `ceph-par1-rbd.*` ; `find /root -name '*hv-par1*'` vide sur les trois nœuds ; côté Ceph, `ceph auth get client.hv-par1` → `ENOENT`, `ceph osd pool ls` sans `hv-par1`, `ceph config get mon mon_allow_pool_delete` → `false`. Puis `qm shutdown 2081 2082 2083` sur `pve01`.
9. Document : le fichier du corrigé.

**Explications**

Un stockage RBD **externe** se distingue pour Proxmox par la présence de `monhost` : il garde alors sa propre copie de la clé et ne touche jamais au Ceph local. Les deux clusters peuvent partager le VLAN 30 parce que chaque client s'adresse aux moniteurs de **son** cluster et que tout l'échange est authentifié par CephX (clés différentes, `fsid` différents). Les capacités `profile …` sont des ensembles prédéfinis maintenus par Ceph : préférables à des capacités écrites à la main (`allow rwx pool=…`), qui oublient vite une opération légitime (la *blocklist*) ou en autorisent une de trop.

**Alternatives**
- *Espace de noms RBD* (`rbd namespace create hv-par1/<client>`, capacités `profile rbd pool=x namespace=y`) : plusieurs clients isolés dans un seul pool, sans multiplier les pools (et leurs PG). Bon choix pour beaucoup de petits consommateurs.
- *krbd 1* : le noyau du nœud mappe l'image (`/dev/rbdN`) au lieu de QEMU (librbd) : obligatoire pour les conteneurs, parfois plus rapide, mais une version de noyau plus ancienne que le cluster limite les fonctionnalités d'image.
- *CephFS* ou *NFS* (export Ganesha de cephadm) pour des ISO et sauvegardes partagées : autre besoin.

**Pièges classiques**
- `--username client.hv-par1` : Proxmox attend l'identifiant **sans** le préfixe `client.` (refus d'authentification sinon).
- Oublier `rbd pool init` (ou `application enable … rbd`) : `HEALTH_WARN` « pool has no application enabled ».
- Laisser `mon_allow_pool_delete true` après la suppression : la prochaine faute de frappe supprime un pool d'OpenStack.
- Supprimer le stockage Proxmox alors qu'une image y est encore : la VM garde un disque sur un stockage inconnu, elle ne démarre plus.
- `ceph auth get client.hv-par1 > fichier` sur `adm01` « juste pour voir » : la clé est maintenant dans un fichier, dans l'historique de sauvegarde, etc.

**En production chez MédiSphère**
Un cluster Proxmox consommateur de Ceph externe a son pool (ou son espace de noms) **par cluster**, une identité par cluster, la clé dans Vault (puis OpenBao, M25) avec rotation planifiée (nouvelle identité, mise à jour du trousseau du stockage, révocation de l'ancienne), une supervision de la latence par image (module `rbd_support` du MGR, M21), et un runbook de retrait.

---

### M09-E13 — Haute disponibilité : ressources et règles

**Solution**

Fichier : [`ha-config.sh`](fichiers/M09-E13/ha-config.sh) (ressources et règles, rejouable ; refuse une ressource dont un disque n'est pas sur `ceph-vm`).

1. **Avant toute ressource** :
   ```
   root@hv01:~# ha-manager status
   quorum OK
   master hv02 (idle, …)
   lrm hv01 (idle, …)
   lrm hv02 (idle, …)
   lrm hv03 (idle, …)
   ```
   (Forme indicative ; Proxmox VE 9.2 ajoute une ligne sur l'état du *fencing* — ⚠️ libellé à vérifier.) `quorum` : la partition du nœud a le quorum Corosync, condition pour que la HA agisse. `master` : le CRM (*Cluster Resource Manager*) qui a pris le verrou de gestionnaire dans pmxcfs ; il décide pour tout le cluster. `lrm` : le gestionnaire local de chaque nœud, qui exécute. Sans ressource, tout le monde est `idle` : personne n'a ouvert son *watchdog*, il n'y a rien à protéger.
2. **Ressources** : `ha-manager add vm:101 --state started --max_restart 1 --max_relocate 1` (×3). Dans la minute, le CRM passe `active`, chaque LRM qui porte une ressource passe `active` (il prend son verrou d'agent et **arme son *watchdog***), `ha-manager status` liste `service vm:101 (hv01, started)`…
3. **Règles** :
   ```
   root@hv01:~# ha-manager rules add node-affinity app01-preferences --resources vm:101 --nodes 'hv01:3,hv02:2,hv03:1' --strict 0
   root@hv01:~# ha-manager rules add resource-affinity frontaux-separes --resources vm:102,vm:103 --affinity negative
   root@hv01:~# cat /etc/pve/ha/rules.cfg
   node-affinity: app01-preferences
           nodes hv01:3,hv02:2,hv03:1
           resources vm:101
           strict 0

   resource-affinity: frontaux-separes
           affinity negative
           resources vm:102,vm:103
   ```
   La création d'une règle est un « point de planification » du CRS : dans les secondes qui suivent, `app01` est migrée vers `hv01` si elle n'y était pas, et si `app02` et `app03` partageaient un nœud, l'une des deux est migrée. Priorités : seule leur **comparaison** compte (plus grand = préféré) ; `hv01:3,hv02:2,hv03:1` exprime exactement « hv01, sinon hv02, sinon hv03 ». Non stricte : si les trois nœuds préférés manquaient, la VM irait ailleurs — ici il n'y a pas d'ailleurs, mais la règle reste juste le jour où un quatrième nœud arrive.
4. **Expériences** :
   - (a) `ha-manager crm-command migrate vm:101 hv03` : la VM part sur `hv03`… puis **revient** sur `hv01` au tour suivant du CRS. `failback` vaut 1 par défaut : une ressource retourne au nœud de plus haute priorité de sa règle dès qu'il est disponible. Pour qu'un déplacement manuel tienne, il faut `ha-manager set vm:101 --failback 0` (ou modifier la règle). C'est le successeur de l'option `nofailback` des anciens groupes, au sens inversé.
   - (b) Migration de `app03` vers le nœud de `app02` : le CRM ne l'exécute pas (la cible viole la règle négative) et l'écrit dans son journal (`journalctl -u pve-ha-crm`) ; la VM ne bouge pas. ⚠️ Message exact à relever sur ton lab.
   - (c) `kill -9` du processus QEMU de `app02` : le LRM constate en quelques secondes que la ressource n'est plus en marche alors que l'état demandé est `started`, et la **redémarre sur le même nœud** (journal : `service status vm:102 … restart`, compteur de relances). `max_restart` borne les relances après un **échec de démarrage** ; si le démarrage échouait aussi, la ressource serait déplacée (`max_relocate`), puis passerait en `error`.
   - (d) `qm shutdown 102` sur une VM gérée par la HA n'arrête pas directement la VM : la commande passe par le gestionnaire HA, qui enregistre l'état demandé **`stopped`** (`ha-manager config` le montre), puis l'arrête. Sans cela, la HA la redémarrerait aussitôt. `qm start 102` (ou `ha-manager set vm:102 --state started`) la remet en `started`.
5. **Fencing.** Le LRM d'un nœud qui porte des ressources détient un **verrou d'agent** dans pmxcfs et maintient ouvert le *watchdog* (par `watchdog-mux`, qui ouvre `/dev/watchdog` — ici le *softdog* du noyau, faute de *watchdog* matériel exposé à la VM). Il le « nourrit » tant qu'il peut renouveler son verrou, c'est-à-dire tant que sa partition a le **quorum**. Un nœud qui perd le quorum ne peut plus écrire dans `/etc/pve`, ne renouvelle plus son verrou, cesse de nourrir le *watchdog* : au bout d'environ 60 secondes, le *watchdog* **redémarre le nœud**, sans négocier. De l'autre côté, la partition majoritaire attend que le verrou de ce nœud expire, ce qui garantit qu'il s'est arrêté, puis redémarre ses ressources ailleurs. C'est l'**auto-fencing** : pas de matériel de coupure externe, mais la certitude qu'une VM ne tourne pas deux fois. Le CRM maître fait de même avec son propre verrou. L'état apparaît dans `ha-manager status` (ligne *fencing* et état du *watchdog* de chaque LRM : `armed`, `standby`, `disarming`, `disarmed`).
6. **Stockage partagé** : la HA redémarre une ressource **sur un autre nœud** ; il faut que son disque y soit accessible. Avec un disque sur `local-lvm`, la relance ailleurs échouerait (volume introuvable), épuiserait `max_relocate` et laisserait la ressource en `error` (c'est l'une des variantes de M09-E37). La seule exception propre est la réplication ZFS (E14), avec une perte de données bornée.

**Explications**

Le gestionnaire HA de Proxmox est un automate à deux niveaux : un CRM unique (élu) qui calcule où chaque ressource doit tourner (règles, charge, état des nœuds) et écrit ses décisions dans `/etc/pve/ha/manager_status` ; un LRM par nœud qui lit ces décisions et agit (démarrer, arrêter, migrer). Ils ne se parlent que par pmxcfs, donc **seulement avec le quorum**. Proxmox VE 9 a remplacé les groupes HA (une liste de nœuds avec priorités, « restreint » ou non) par des **règles** : l'affinité de nœud reprend exactement les groupes (`strict` ≈ `restricted`), et l'affinité de **ressources** est nouvelle (garder ensemble, séparer). Les groupes existants sont convertis automatiquement lors du passage de tous les nœuds en 9.

**Alternatives**
- *Règle stricte* pour `app01` (`--strict 1` avec `hv01,hv02`) : `app01` ne tournerait jamais sur `hv03` et s'**arrêterait** si `hv01` et `hv02` tombaient. À réserver aux contraintes dures (licence, matériel).
- *`max_restart 0`* : déplacement immédiat sans relance locale ; utile si une relance sur place n'a aucune chance (dépendance locale cassée), coûteux sinon.
- *Ressource `ignored`* pour une intervention manuelle ponctuelle sur une VM HA, plutôt que de la retirer.

**Pièges classiques**
- Confondre l'état **demandé** (`started`, `stopped`, `disabled`, `ignored`) et l'état **constaté** (`started`, `fence`, `recovery`, `error`…).
- Sortir d'`error` en relançant directement : seule la voie `--state disabled`, correction, puis `--state started` fonctionne.
- Une ressource dans deux règles d'affinité de nœud, ou une règle négative qui sépare plus de ressources qu'il n'y a de nœuds : la règle est **désactivée** d'office (contrôles de faisabilité). Lis `ha-manager rules config` : une règle désactivée y apparaît.
- Tuer `pve-ha-lrm` « pour le relancer » : redémarrage du nœud par le *watchdog*.

**En production chez MédiSphère**
Watchdog **matériel** (iTCO, IPMI) déclaré dans `/etc/default/pve-ha-manager`, alertes sur toute ressource en `error` ou `recovery`, règles d'anti-affinité pour chaque paire de VMs redondantes (bases, frontaux, nœuds Kubernetes du futur cluster), et revue des règles à chaque ajout de nœud.

---

### M09-E14 — Réplication ZFS entre nœuds

**Solution**

Fichiers : [`replication.sh`](fichiers/M09-E14/replication.sh) (VM et tâches, rejouable), [`lire-replique.sh`](fichiers/M09-E14/lire-replique.sh) (lecture du dernier état répliqué sur une cible, sans démarrer la VM).

1. `qm clone 199 110 --name rep01 --full 1 --storage zfs-local --target hv01` ; `zfs list tank/vm-110-disk-0` : *zvol* (volume bloc ZFS), `volblocksize` 16K par défaut.
2. Tâches :
   ```
   root@hv01:~# pvesr create-local-job 110-0 hv02 --schedule '*/10' --rate 20
   root@hv01:~# pvesr create-local-job 110-1 hv03 --schedule '*/10' --rate 20
   root@hv01:~# pvesr schedule-now 110-0; pvesr schedule-now 110-1
   root@hv01:~# pvesr status
   JobID      Enabled    Target           LastSync             NextSync   Duration  FailCount State
   110-0      Yes        local/hv02       2026-…               …          35.2      0         OK
   110-1      Yes        local/hv03       2026-…               …          36.0      0         OK
   ```
   `--rate` est en Mo/s (mégaoctets) ; la première synchronisation envoie tout le disque (`zfs send` complet), les suivantes seulement le delta entre deux instantanés.
3. Instantanés : `zfs list -t snapshot -r tank` montre `tank/vm-110-disk-0@__replicate_110-0_<horodatage>__` et `…@__replicate_110-1_…__`, **un par tâche** sur la source, le même sur la cible correspondante. À chaque passage, Proxmox crée un nouvel instantané, envoie le delta depuis le précédent, puis supprime le précédent des deux côtés : il ne garde que le **dernier point commun**, base de l'incrément suivant.
4. RPO : dans `rep01`, `* * * * * root date -Is >> /var/tmp/horodatage.log` (fichier `/etc/cron.d/horodatage`), 25 minutes, puis sur `hv02` : `./lire-replique.sh 110 /var/tmp/horodatage.log 1` → la dernière ligne date de l'instant du dernier instantané, **jusqu'à 10 minutes** avant l'heure de lecture (plus la durée du transfert). Le RPO est l'intervalle de l'horaire + la durée d'une synchronisation ; un système de fichiers journalisé non figé au moment de l'instantané est cohérent « comme après une coupure de courant » (`noload` à la lecture pour ne pas rejouer le journal).
5. Migration à chaud vers `hv02` : Proxmox lance une dernière réplication (delta depuis le dernier instantané), puis migre la mémoire ; le disque n'est **pas** recopié en entier (journal : `replicating …`, puis migration du disque limitée à ce qui a changé depuis — ⚠️ forme exacte du journal à vérifier). Après la migration, les tâches sont **réécrites** : la source devient `hv02` ; `110-0`, qui visait `hv02`, vise désormais `hv01` (inversion) ; `110-1` part maintenant de `hv02` vers `hv03`. Lis `/etc/pve/replication.cfg` avant et après.
6. Questions :
   - (a) Si `hv02` tombe avec `rep01` (sous HA) : la HA peut la redémarrer sur `hv01` ou `hv03`, qui ont une copie, **avec la perte des écritures depuis la dernière synchronisation** (jusqu'à 10 min ici). Proxmox journalise un avertissement : la reprise sur une réplique est un choix délibéré de l'administrateur.
   - (b) Une VM répliquée ne peut redémarrer que là où il y a une copie : une règle d'affinité de nœud **stricte** limitée aux nœuds cibles évite que la HA tente un nœud sans copie (qui échouerait, puis `error`). Ici les trois nœuds ont une copie (source + deux cibles) ; la règle n'en reste pas moins la bonne pratique, au cas où une tâche serait retirée.
   - (c) Critères : **RPO acceptable** (Ceph : 0 ; réplication : minutes) ; **latence d'écriture** (Ceph : chaque écriture attend trois OSD sur le réseau ; ZFS local : disque local) ; **capacité et coût** (Ceph : 3 copies sur au moins 3 nœuds, réseau dédié ; ZFS : une copie par cible, choisie VM par VM) ; aussi la simplicité (deux nœuds suffisent pour ZFS). Pour MédiSphère : Ceph pour la production HA (données de santé, RPO 0), réplication pour des VMs secondaires ou un petit site (PAR2) sans Ceph.
7. `qm migrate 110 hv01 --online` ; `rep01` et ses tâches restent (palier 4).

**Explications**

`pvesr` (*Proxmox VE Storage Replication*) est un ordonnanceur (`pvescheduler`) qui enchaîne pour chaque tâche : instantané de tous les disques ZFS répliqués de l'invité, `zfs send -i` vers la cible par SSH entre nœuds (clés du cluster), `zfs recv`, puis nettoyage. Il exige le **même** identifiant de stockage et le **même** nom de pool partout : la cible reçoit le volume sous le même nom, prêt à être utilisé si la VM y migre ou y est relancée.

**Alternatives**
- *Horaire plus court* (`*/1`) : RPO d'une minute, au prix d'un instantané et d'un envoi par minute (charge réseau et ZFS) ; utile pour des disques à faible taux d'écriture.
- *Réseau de réplication dédié* (`replication: …` dans `datacenter.cfg`, sinon celui de la migration) : sépare ce trafic de MGMT (M09-E27).
- *Réplication applicative* (réplication PostgreSQL, M27) : RPO quasi nul et cohérence applicative, mais spécifique à chaque service.

**Pièges classiques**
- Nom de pool différent sur un nœud (`tank` vs `rpool/data`) : la réplication échoue (« storage … not available on target ») — c'est pourquoi E06 l'a imposé.
- Laisser un clone de lecture d'un instantané de réplication : l'instantané ne peut plus être supprimé, la tâche suivante échoue (M09-E40).
- Croire que la réplication est une sauvegarde : une suppression de fichiers ou un chiffrement par rançongiciel est répliqué au passage suivant.
- Disque d'une VM répliquée ajouté sur un autre stockage (`local-lvm`) : la migration redevient complète, la HA échoue.

**En production chez MédiSphère**
Réservée aux VMs explicitement classées « RPO 15 minutes » dans le catalogue de services ; alerte sur toute tâche en échec (`FailCount` > 0) ou dont `LastSync` dépasse deux intervalles ; RB-091 traite la reprise sur réplique et la décision de perte de données.

---

### M09-E15 — Sauvegarder le cluster vers PBS

**Solution**

Fichiers : [`pbs01-hv.sh`](fichiers/M09-E15/pbs01-hv.sh) (sur `pbs01` : relevé d'état, création, retour arrière), [`pbs-stockage.sh`](fichiers/M09-E15/pbs-stockage.sh) (sur `hv01` : stockage chiffré et tâche), [`registre-secrets-extrait.md`](fichiers/M09-E15/medisphere/docs/socle/registre-secrets-extrait.md), ligne de la matrice des flux : [`pare_feu.yml.extrait`](fichiers/M09-E18/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) (commune avec E18).

1. Sur `pbs01`, après `./pbs01-hv.sh --etat > …` (conservé dans `~/m09/e15/`) :
   ```
   root@pbs01:~# proxmox-backup-client namespace create par1/hv --repository root@pam@localhost:ds-lab
   root@pbs01:~# proxmox-backup-manager user create wb-hv@pbs --comment "Sauvegardes du cluster hv-par1 (PLAT-1025)"
   root@pbs01:~# proxmox-backup-manager user generate-token wb-hv@pbs hv-par1
   root@pbs01:~# proxmox-backup-manager acl update /datastore/ds-lab/par1/hv DatastoreBackup --auth-id wb-hv@pbs
   root@pbs01:~# proxmox-backup-manager acl update /datastore/ds-lab/par1/hv DatastoreBackup --auth-id 'wb-hv@pbs!hv-par1'
   root@pbs01:~# proxmox-backup-manager user permissions 'wb-hv@pbs!hv-par1' --path /datastore/ds-lab/par1/hv
   Path: /datastore/ds-lab/par1/hv
   - Datastore.Backup (*)
   root@pbs01:~# proxmox-backup-manager user permissions 'wb-hv@pbs!hv-par1' --path /datastore/ds-lab/par1
   Path: /datastore/ds-lab/par1
   ```
   (Aucun privilège sur `par1` : le jeton ne voit ni ne touche les sauvegardes de `pve01`.) `DatastoreBackup` : créer des sauvegardes, lire et restaurer **les siennes** ; pas de purge, pas de suppression. Les droits d'un jeton PBS sont l'intersection des siens et de ceux de son utilisateur : ACL sur les deux.
2. **Élagage** : la tâche `prune-par1` (M00-E22) a été créée avec `--ns par1` **sans** `--max-depth` ; la référence de PBS dit qu'une profondeur vide signifie « récursion complète » : elle s'applique donc aussi à `par1/hv`, avec la même politique (7 quotidiennes, 4 hebdomadaires, 6 mensuelles). Même chose pour `verify-par1`. Le corrigé ne crée **pas** de tâche propre : une seule politique pour `par1` et ses sous-espaces, lisible ; on en créerait une (avec `--max-depth 0` sur la tâche parente, pour ne pas appliquer deux politiques au même groupe) le jour où le cluster aurait une rétention différente. Vérifie-le : `proxmox-backup-manager prune-job list` et, après une nuit, le journal de la tâche qui doit citer des groupes de `par1/hv`.
3. **Stockage** (`EMPREINTE=$(…) ./pbs-stockage.sh` sur `hv01`) :
   ```
   root@hv01:~# pvesm add pbs pbs-par2 --server 10.20.10.10 --datastore ds-lab --namespace par1/hv \
                  --username 'wb-hv@pbs!hv-par1' --fingerprint '<EMPREINTE>' \
                  --encryption-key autogen --content backup --prune-backups keep-all=1 --password
   Enter Password: ********
   root@hv01:~# ls -l /etc/pve/priv/storage/
   -rw------- 1 root www-data … pbs-par2.enc
   -rw------- 1 root www-data … pbs-par2.pw
   ```
   `--password` **sans valeur**, en dernière position : `pvesm` demande le secret lui-même, sans écho (exemple de `pvesm(1)`) ; donné en argument (`--password "$secret"`), il serait visible dans `ps` pendant l'appel. ⚠️ Libellé de l'invite (et éventuelle confirmation) à vérifier sur ton lab.
   Secret et clé sont dans `/etc/pve/priv/storage/` (pmxcfs) : **lisibles par root sur les trois nœuds**, ce qui est nécessaire (n'importe quel nœud sauvegarde ses VMs) et suffisant pour comprendre le risque : `root` sur un nœud = lecture de toutes les sauvegardes du cluster.
   **Flux** : MGMT → `pbs01` TCP 8007 est déjà autorisé par la règle large « bastion (MGMT) vers tout le lab, PAR2 et LYO1 » (M00-E10, M07-E30) ; `pbs01` répond par `wg0` (route 10.10.0.0/16, M00-E21). Le corrigé ajoute quand même une ligne **explicite** (`HV_NOEUDS` → `PBS01`, 8007, `M09-E15`) : la matrice doit dire pourquoi ce flux existe, et il doit survivre au resserrement de la règle MGMT (M09-E26).
4. **Clé à l'abri**, sans l'écrire en clair sur `adm01` :
   ```
   admin@adm01:~/src/ansible$ ssh root@hv01 'cat /etc/pve/priv/storage/pbs-par2.enc' \
       | uv run ansible-vault encrypt_string --encrypt-vault-id critique --stdin-name vault_pbs_hv_par1_cle \
       >> inventories/lab/group_vars/hv_par1/vault-critique.yml
   root@hv01:~# proxmox-backup-client key paperkey /etc/pve/priv/storage/pbs-par2.enc --output-format text > /root/paperkey.txt
   ```
   Imprimer `paperkey.txt` (texte et QR code), le ranger au coffre, puis `shred -u /root/paperkey.txt`. Registre des secrets : voir l'extrait. **Pourquoi** : la clé n'existe que dans `/etc/pve`, donc **dans le cluster** ; le jour où le cluster est perdu (incendie, rançongiciel), les sauvegardes sont intactes à PAR2… et illisibles. Une sauvegarde chiffrée dont la clé n'existe qu'à côté des données sauvegardées ne protège que contre la perte de **PBS**.
5. **Tâche** : `pvesh create /cluster/backup --id hv-nuit --schedule '03:15' --storage pbs-par2 --all 1 --mode snapshot --prune-backups keep-all=1 --enabled 1` ; exécution immédiate : *Datacenter → Backup → hv-nuit → Run now* (ou `vzdump --all 1 --storage pbs-par2 --mode snapshot` sur **chaque** nœud : `vzdump` ne sauvegarde que les invités du nœud où il tourne). Journal : `INFO: … encryption key fingerprint …` (⚠️ libellé à vérifier) ; à la deuxième exécution, *dirty bitmap* : seuls les blocs modifiés partent, quelques secondes par VM. `keep-all=1` côté client : la purge est faite par PBS (le jeton n'a de toute façon pas le droit de purger).
6. **Restaurations** :
   ```
   root@hv01:~# pvesm list pbs-par2 --vmid 102 | tail -1          # identifiant de la sauvegarde
   root@hv01:~# qmrestore pbs-par2:backup/vm/102/2026-…Z 127 --storage ceph-vm --unique 1
   root@hv01:~# qm set 127 --name restau01 --net0 virtio,bridge=vinv99,link_down=1 ; qm start 127
   root@hv01:~# qm stop 127 && qm destroy 127 --purge 1
   root@hv01:~# qmrestore pbs-par2:backup/vm/102/2026-…Z 127 --storage ceph-vm --unique 1 --live-restore 1
   ```
   `--unique 1` : nouvelles adresses MAC (pas de conflit DHCP avec `app02`) ; carte débranchée (`link_down=1`) pour ne pas avoir deux `app02` sur le réseau. Restauration complète : quelques minutes pour 8 Gio (le HDD de `pbs01` et le tunnel `wg0` limitent). *Live-restore* : la VM **démarre tout de suite** ; les blocs non encore restaurés sont lus à la demande depuis PBS pendant que la restauration continue en fond. Si `pbs01` devient injoignable pendant ce temps, toute lecture d'un bloc non restauré échoue : erreurs d'E/S dans l'invité, VM inutilisable, et ce qu'elle a écrit entre-temps est perdu si l'on recommence. À réserver aux cas où chaque minute compte, réseau fiable.
   Fichier isolé : *Backup* de `app03` → *File Restore* → `/etc/hostname` → *Download*. En ligne de commande, `proxmox-file-restore` sur un nœud (il démarre une petite VM de restauration pour lire les systèmes de fichiers, et a besoin de la clé : disponible sur le nœud). Puis destruction de 127.
7. Côté PBS : interface (*Datastore → ds-lab → Content*, sélecteur de namespace `par1/hv`) : chaque instantané porte l'icône de chiffrement ; API : `proxmox-backup-client snapshot list --repository root@pam@localhost:ds-lab --ns par1/hv` (colonne des fichiers avec leur mode de chiffrement — ⚠️ forme exacte à vérifier). Vérification : *Verify* sur le namespace dans l'interface, ou exécution immédiate de la tâche `verify-par1` (M00-E22, récursive comme l'élagage) : `proxmox-backup-manager verify-job run verify-par1` — elle vérifie les empreintes des *chunks* chiffrés **sans** la clé (l'intégrité ne demande pas de déchiffrer).

**Explications**

Le chiffrement côté client de PBS chiffre chaque *chunk* (AES-256-GCM) **avant** l'envoi ; PBS ne voit que des blocs opaques, mais continue de dédupliquer **entre sauvegardes du même client** (les *chunks* chiffrés avec la même clé restent identiques). Le compte et le jeton dédiés, limités à un namespace, empêchent qu'un cluster compromis détruise les sauvegardes des autres (et même les siennes : pas de purge). La rétention vit côté serveur, hors de portée d'un client compromis (même raisonnement qu'au M00).

**Alternatives**
- *Clé maîtresse RSA* (`--master-pubkey`) : chaque sauvegarde emporte une copie de la clé chiffrée par une clé publique dont la privée est hors ligne ; utile quand plusieurs clusters ont chacun leur clé.
- *Sauvegardes non chiffrées* + chiffrement du disque de PBS : protège contre le vol du disque, pas contre un administrateur de PAR2 ou un PBS compromis.
- *Un datastore par cluster* plutôt qu'un namespace : isolation plus forte (GC, quotas, droits), au prix de la déduplication commune.

**Pièges classiques**
- ACL sur l'utilisateur seulement (pas sur le jeton) : le jeton n'a **rien** (intersection), l'ajout du stockage échoue en 403.
- Stockage inactif (« cannot read datastore status ») avec des ACL limitées au namespace : comportement signalé au M00 selon les versions ; diagnostic par `pvesm status` et les journaux de `pbs01`.
- Recréer le stockage avec une **nouvelle** clé : les sauvegardes déjà faites ne se restaurent plus avec la nouvelle (garde l'ancienne au Vault).
- Restaurer sans `--unique` : deux VMs avec la même MAC sur le même VLAN.
- Oublier qu'une VM restaurée **démarre** si la sauvegarde la déclarait démarrée et que tu passes `--start 1` (ou si la HA la prend) : toujours débrancher la carte d'abord.

**En production chez MédiSphère**
Deuxième copie hors site (synchronisation `ds-lab` vers un PBS de PAR2 bis ou une bande), test de restauration **mensuel** automatisé (une VM restaurée, démarrée en réseau isolé, contrôlée, détruite) avec rapport, alerte sur toute tâche de sauvegarde en échec ou absente, et procédure de récupération de la clé (coffre, deux personnes) dans RB-091.

---

### M09-E16 — SDN du cluster : zones, VNets et EVPN

**Solution**

Fichier : [`sdn-hv-par1.sh`](fichiers/M09-E16/sdn-hv-par1.sh) (`--preparer` puis déclaration et application, rejouable).

1. **Préparation** (`./sdn-hv-par1.sh --preparer`) : `apt install frr frr-pythontools` depuis les dépôts **Proxmox** (le SDN est testé avec cette version de FRR ; le dépôt de deb.frrouting.org du module 07 apporterait une version différente et une autre gestion des configurations), `systemctl enable --now frr`, ligne `source /etc/network/interfaces.d/*` en fin de `/etc/network/interfaces` (présente par défaut sur une installation récente : vérifier quand même). `vtysh -c 'show running-config'` ne doit montrer aucun `router bgp` hérité : le SDN **réécrit** `/etc/frr/frr.conf`.
2. **Zone VLAN et VNet** :
   ```
   root@hv01:~# pvesh create /cluster/sdn/zones --zone invites --type vlan --bridge vmbr1 --ipam pve
   root@hv01:~# pvesh create /cluster/sdn/vnets --vnet vinv99 --zone invites --tag 99
   root@hv01:~# pvesh set /cluster/sdn
   root@hv02:~# cat /etc/network/interfaces.d/sdn
   auto vinv99
   iface vinv99
           bridge_ports vmbr1.99
           bridge_stp off
           bridge_fd 0
   …
   ```
   Proxmox crée sur chaque nœud un **pont** `vinv99` dont le seul port est la sous-interface VLAN 99 de `vmbr1` (⚠️ forme exacte du fichier à vérifier). Une VM branchée sur `vinv99` n'a plus d'étiquette à porter : c'est le VNet qui la porte. Bascule de `app01` **en gardant sa MAC** (donc son bail DHCP et son adresse) :
   ```
   root@hv01:~# qm config 101 | grep ^net0                     # relève virtio=<MAC>
   root@hv01:~# qm set 101 --net0 virtio=<MAC>,bridge=vinv99
   ```
   (La carte est remplacée à chaud : une courte coupure réseau dans la VM.)
3. **EVPN** :
   ```
   root@hv01:~# pvesh create /cluster/sdn/controllers --controller evpnhv --type evpn --asn 65090 --peers 10.10.10.51,10.10.10.52,10.10.10.53
   root@hv01:~# pvesh create /cluster/sdn/zones --zone evhv --type evpn --controller evpnhv --vrf-vxlan 10090 --mtu 1450 --ipam pve
   root@hv01:~# pvesh create /cluster/sdn/vnets --vnet vevpn1 --zone evhv --tag 11001
   root@hv01:~# pvesh create /cluster/sdn/vnets/vevpn1/subnets --subnet 10.90.1.0/24 --type subnet --gateway 10.90.1.1
   … (idem vevpn2, 11002, 10.90.2.0/24, 10.90.2.1)
   root@hv01:~# pvesh set /cluster/sdn
   root@hv01:~# vtysh -c 'show running-config'
   …
   vrf vrf_evhv
    vni 10090
   …
   router bgp 65090
    bgp router-id 10.10.10.51
    neighbor VTEP peer-group
    neighbor VTEP remote-as 65090
    neighbor 10.10.10.52 peer-group VTEP
    neighbor 10.10.10.53 peer-group VTEP
    address-family l2vpn evpn
     neighbor VTEP activate
     advertise-all-vni
   …
   ```
   (Extrait indicatif, ⚠️ à comparer avec ta configuration générée.) Sessions **iBGP** (même AS 65090) entre les trois nœuds, famille `l2vpn evpn` ; un VRF par zone (`vrf_evhv`, VNI 10090) pour router entre `vevpn1` et `vevpn2` ; une interface VXLAN par VNet (VNI 11001, 11002) dont la source est l'adresse MGMT du nœud.
4. **Plan de contrôle** : `vtysh -c 'show bgp l2vpn evpn summary'` → deux voisins `Established` par nœud ; `show evpn vni` → 11001, 11002 (L2) et 10090 (L3). Une fois les VMs démarrées : routes de **type 2** (MAC et MAC/IP de chaque VM, annoncées par le nœud qui l'héberge), routes de **type 3** (inclusion multicast : chaque nœud annonce les VNI qu'il porte, pour le BUM) et, si `advertise-subnets` était actif, de **type 5** (préfixes) ; ici, sans nœud de sortie ni `advertise-subnets`, peu ou pas de type 5.
5. **VMs** : `qm clone 199 140 --name evpn01 --full 1 --storage ceph-vm` ; `qm set 140 --net0 virtio,bridge=vevpn1 --ipconfig0 ip=10.90.1.10/24,gw=10.90.1.1` ; idem 141 (`evpn02`) sur `vevpn2` (10.90.2.10, passerelle 10.90.2.1), démarrée sur un autre nœud. Depuis la console d'`evpn01` (`qm terminal 140`), `ping 10.90.2.10` répond. `tcpdump -ni vmbr0 udp port 4789` sur le nœud d'`evpn01` : paquets VXLAN vers l'adresse MGMT du nœud d'`evpn02`, VNI 10090 (le paquet est **routé** dans le VRF par la passerelle *anycast* du nœud source, puis envoyé dans le VNI L3 vers le nœud destination — routage symétrique IRB).
6. Migration d'`evpn02` pendant le `ping` : 0 à quelques paquets perdus. La passerelle 10.90.2.1 existe, avec **la même MAC**, sur tous les nœuds : la VM arrivée sur le nouveau nœud n'a rien à réapprendre ; le nouveau nœud annonce en BGP la MAC/IP de la VM (type 2, avec un numéro de séquence de mobilité plus élevé), les autres mettent à jour leur table.
7. Questions :
   - **MTU 1450** : VXLAN ajoute 50 octets (Ethernet 14 + IP 20 + UDP 8 + VXLAN 8) au paquet de la VM ; sous-jacent MGMT à 1500 → 1450 au plus dans le VNet, sinon fragmentation ou pertes silencieuses des gros paquets. Sur un sous-jacent en MTU 9000 (VLAN 30), on aurait pu monter à 8950.
   - **Joindre `vevpn1` depuis le lab** : déclarer des **nœuds de sortie** (`exitnodes`) qui annoncent une route par défaut dans l'EVPN et routent vers le « vrai » réseau ; et côté lab, que `gw01`/`gw02` connaissent 10.90.0.0/16 : route statique vers les nœuds de sortie, ou **session BGP** entre les nœuds de sortie (AS 65090) et la bordure (AS 65000) avec des politiques explicites (`ebgp-requires-policy`). Risques : la bordure dépend d'un cluster de virtualisation pour un routage, une erreur de politique pourrait annoncer des préfixes du lab dans l'EVPN (ou l'inverse), et le filtrage doit être ajouté sur une nouvelle interface.
   - **IPAM `pve`** : enregistre les sous-réseaux et, si on l'utilise, les adresses attribuées aux invités (et peut les distribuer par le DHCP du SDN, dnsmasq, en aperçu) ; il ne connaît que le cluster. NetBox est la source de vérité de **tout** le lab (préfixes, VLAN, VMs, équipements, historique) ; Proxmox propose un greffon IPAM NetBox pour le SDN : l'intégration logique pour MédiSphère, quand le SDN portera des réseaux de production.

**Explications**

Le SDN de Proxmox génère, à partir d'une configuration de cluster (`/etc/pve/sdn/*.cfg`), la configuration réseau de chaque nœud (`/etc/network/interfaces.d/sdn`, appliquée par `ifreload`) et celle de FRR. Une **zone** définit la technique (VLAN, QinQ, VXLAN, EVPN) et où elle s'applique ; un **VNet** est un réseau nommé de cette zone, exposé aux VMs comme un pont local de même nom sur chaque nœud ; des **sous-réseaux** et un **IPAM** s'y rattachent. Le gain immédiat : un nom (et des droits, `SDN.Use` sur `/sdn/zones/<zone>/<vnet>`, E17) à la place d'une étiquette tapée à la main. L'EVPN apporte en plus un réseau de niveau 2 **étendu** au-dessus d'un réseau routé, avec un plan de contrôle BGP au lieu de l'inondation, et le routage distribué entre VNets.

**Alternatives**
- *Zone VXLAN simple* (sans EVPN) : niveau 2 étendu, liste de pairs statique, pas de routage entre VNets ni d'apprentissage par BGP ; plus simple, suffisant pour un seul réseau étendu.
- *Fabric SDN* (OpenFabric, OSPF ; WireGuard ou BGP en 9.2) comme sous-jacent : la liste des pairs et les routes entre boucles locales sont construites automatiquement ; nécessaire dès que le sous-jacent n'est plus un seul segment.
- *Réflecteur de routes* (pairs EVPN vers deux réflecteurs plutôt qu'un maillage complet) : indispensable au-delà de quelques nœuds.

**Pièges classiques**
- Identifiant de zone ou de VNet de plus de 8 caractères, ou avec un tiret pour une zone : refus de l'API.
- Oublier d'**appliquer** (`pvesh set /cluster/sdn`) : la configuration est enregistrée (en attente) mais rien n'existe sur les nœuds.
- `frr-pythontools` absent : l'application échoue sur la partie FRR (le rechargement de FRR utilise `frr-reload.py`).
- VNI du VRF égal à celui d'un VNet : conflit (la documentation l'interdit).
- MTU par défaut des invités à 1500 dans un VNet EVPN : `ping` passe, SSH ou HTTPS se bloquent sur les gros paquets. Cloud-init peut poser le MTU de l'invité (`ipconfig` n'a pas d'option MTU : le pilote `virtio` le lit de la carte, `mtu=` dans `net0`).

**En production chez MédiSphère**
Sous-jacent dédié (VLAN ou fabric) en MTU 9000 pour l'EVPN, réflecteurs de routes, pare-feu de VNet (M09-E26), IPAM NetBox, nœuds de sortie redondants annoncés en BGP à la bordure avec des politiques revues comme le reste de la matrice des flux ; le même modèle EVPN se retrouve dans OpenStack (OVN, M10) et dans Kubernetes (Cilium, M15) : un vocabulaire commun pour l'équipe.

---

### M09-E17 — Droits, pools et jetons du cluster

**Solution**

Fichier : [`hv-droits.sh`](fichiers/M09-E17/hv-droits.sh) (`MOI=<compte> ./hv-droits.sh` sur un nœud ; rejouable ; mots de passe saisis sans écho ; contrôles des droits effectifs à la fin).

1. **Combinaison des droits.** Une ACL associe (chemin, utilisateur **ou** groupe **ou** jeton, rôle, propagation). Les droits effectifs d'un utilisateur sur un chemin sont ceux de l'ACL **la plus précise** qui le concerne (un chemin plus long l'emporte sur `/`), en cumulant ses ACL personnelles et celles de ses groupes au même niveau ; une ACL avec le rôle `NoAccess` retire tout. La **propagation** (par défaut) étend une ACL aux chemins en dessous (`/vms` → `/vms/100`). Un jeton **à privilèges séparés** a ses propres ACL et n'obtient que l'**intersection** de ses droits et de ceux de son utilisateur. Un **pool** regroupe des VMs et des stockages : une ACL sur `/pool/prod` vaut pour tous ses membres, présents et futurs, sans lister de VMID.
2. **Pools, groupes, comptes** :
   | Groupe | Chemin | Rôle | Pourquoi |
   |---|---|---|---|
   | `hv-admins` | `/` | `Administrator` | administration du cluster ; peu de membres, 2FA en E26 |
   | `hv-ops` | `/` | `PVEAuditor` | voir l'état de tout (nœuds, stockages, Ceph, HA) pour diagnostiquer |
   | `hv-ops` | `/pool/prod`, `/pool/recette` | `PVEVMUser` | démarrer, arrêter, redémarrer, console, CD-ROM, sauvegarde des VMs de ces pools ; **ni** création, **ni** suppression, **ni** configuration matérielle |

   `PVEVMUser` contient `VM.Backup` (lancer une sauvegarde) mais pas `VM.Allocate`, `VM.Config.*` ni `Sys.*` : l'astreinte peut relancer un service, pas le reconfigurer.
3. **`WBTofuHV`** : même liste que `WBTofu` (M05-E03) — `VM.Audit`, `VM.Clone`, `VM.Allocate`, `VM.Config.{CPU,Memory,Disk,CDROM,Network,HWType,Options,Cloudinit}`, `VM.PowerMgmt`, `VM.GuestAgent.Audit`, `Pool.Audit`. Ce qui change :
   - **`VM.PowerMgmt` est indispensable** en 9.2 pour démarrer une VM juste après sa création ou sa restauration (le provider crée puis démarre : `started = true`) ; il était déjà dans `WBTofu`, mais un rôle construit à partir des droits « de création » seuls échouerait au démarrage.
   - Le **template** 199 n'est pas dans `recette` : `PVETemplateUser` (`VM.Clone`, `VM.Audit`) sur `/vms/199`.
   - **Stockage** `ceph-vm` (`PVEDatastoreUser` sur `/storage/ceph-vm`) et **VNet** `vinv99` (`PVESDNUser` sur `/sdn/zones/invites/vinv99`) au lieu de `local-nvme` et `vsandbox`.
   - Pas de `VM.Migrate` : dans un cluster, le placement est l'affaire de la HA et du CRS ; OpenTofu choisit le nœud de création, pas les déplacements.
   - Proxmox VE 9 a supprimé `VM.Monitor` et ajouté `VM.Replicate` : aucun des deux n'est utile ici.
4. **Droits effectifs** (fin du script) :
   ```
   root@hv01:~# pveum user token permissions wb-tofu-hv@pve tofu --path /
   (vide)
   root@hv01:~# pveum user token permissions wb-tofu-hv@pve tofu --path /pool/recette
   Pool.Audit (*), VM.Allocate (*), VM.Audit (*), VM.Clone (*), …, VM.PowerMgmt (*)
   root@hv01:~# pveum user permissions nadia.roussel@pve --path /vms/101
   VM.Audit, VM.Backup, VM.Config.CDROM, VM.Console, VM.PowerMgmt, …
   ```
   (Format indicatif.)
5. **Tests réels.** En tant que Nadia : *Redémarrer* `app02` fonctionne ; *Supprimer* `app03` est grisé ou refusé (403, `VM.Allocate` manquant) ; *Shell* de `hv01` refusé (`Sys.Console`). Avec le jeton :
   ```
   admin@adm01:~$ set -a; . ~/.config/workbook/pve-tofu-hv.env; set +a
   admin@adm01:~$ ssh hv01 cat /etc/pve/pve-root-ca.pem > ~/m09/e17/hv-par1-ca.pem      # public
   admin@adm01:~$ printf 'Authorization: PVEAPIToken=%s\n' "$PROXMOX_VE_API_TOKEN" \
       | curl -s --cacert ~/m09/e17/hv-par1-ca.pem -H @- "${PROXMOX_VE_ENDPOINT%/}/api2/json/cluster/resources?type=vm" \
       | jq -r '.data[] | "\(.vmid) \(.name)"'
   199 tpl-nested-debian13
   ```
   Le jeton ne voit que ce sur quoi il a un droit d'audit : le template (et les VMs de `recette` quand elles existeront) ; ni `app01-03`, ni les nœuds en détail. Avant E18, `PROXMOX_VE_ENDPOINT` vaut `https://hv01.par1.medisphere.internal:8006/` et l'autorité du cluster est passée explicitement (`--cacert`) ; après E18, la VIP, et l'autorité est dans le magasin du système.
6. **Privsep** : un jeton qui hérite de son utilisateur a **tous** ses droits ; une fuite du jeton (fichier de CI, journal) vaut une fuite du compte, et l'on ne peut pas donner à deux outils deux périmètres avec un seul compte. Séparé, le jeton est borné par ses propres ACL et révocable seul. **Groupes et pools** : une ACL nominative par VM ne se relit pas, ne survit pas à un départ ou à une recréation de VM (nouveau VMID), et ne se vérifie pas en audit ; « le groupe `hv-ops` agit sur les pools `prod` et `recette` » se lit en une ligne.

**Explications**

Les chemins d'ACL de Proxmox suivent l'arborescence de l'API (`/vms/<id>`, `/storage/<id>`, `/nodes/<nœud>`, `/pool/<pool>`, `/sdn/zones/<zone>/<vnet>`, `/access/…`). Une opération vérifie **chaque** objet qu'elle touche : cloner demande `VM.Clone` sur la source, `VM.Allocate` sur la cible (ou son pool), `Datastore.AllocateSpace` sur le stockage, `SDN.Use` sur le VNet. C'est pourquoi un rôle d'automatisation se construit en partant des appels réels (API viewer, journal des refus) plutôt que par élimination à partir d'`Administrator`.

**Alternatives**
- *Realm LDAP/OIDC* (Keycloak, M24) avec synchronisation des groupes : les comptes nominatifs ne se créent plus à la main ; c'est la cible.
- *Pools imbriqués* (`prod/mediagenda`) depuis Proxmox VE 8 : droits par application.
- *Rôle personnalisé pour l'astreinte* (sans `VM.Backup`, avec `VM.Snapshot`) si la politique interne le demande.

**Pièges classiques**
- ACL posée sur l'utilisateur du jeton et pas sur le jeton (privsep) : le jeton n'a rien.
- `PVEVMUser` sur `/` pour l'astreinte « pour aller vite » : elle agit sur **toutes** les VMs, y compris celles de l'infrastructure (template).
- Propagation désactivée par erreur (`--propagate 0`) sur un pool : l'ACL ne vaut que pour l'objet pool, pas ses membres.
- Mot de passe passé en argument (`pveum passwd` le demande ; ne pas l'écrire dans un script).
- Jeton sans expiration : il survit au départ de son créateur.

**En production chez MédiSphère**
Comptes nominatifs uniquement par le fournisseur d'identité (M24), `root@pam` réservé au bris de glace (mot de passe au coffre, connexion alertée), revue trimestrielle des ACL (`pveum acl list`) et des jetons (expiration, dernier usage) jointe au dossier HDS.

---

### M09-E18 — Piloter le cluster par le code

**Solution** (une solution possible, celle du corrigé)

Fichiers :
- `plateforme/ansible` : rôle [`pve_cluster`](fichiers/M09-E18/ansible/roles/pve_cluster/) (`defaults`, `tasks/{main,certificat,keepalived}.yml`, `handlers`, `templates/keepalived.conf.j2`, `templates/pve-cluster-sante.sh.j2`, `meta`), playbook [`hv-cluster.yml`](fichiers/M09-E18/ansible/playbooks/hv-cluster.yml), confiance d'`adm01` et `runner01` : [`host_vars/adm01/pki-hv.yml`](fichiers/M09-E18/ansible/inventories/lab/host_vars/adm01/pki-hv.yml), [`host_vars/runner01/pki-hv.yml`](fichiers/M09-E18/ansible/inventories/lab/host_vars/runner01/pki-hv.yml), [`pki/LISEZMOI-hv-par1-root-ca.md`](fichiers/M09-E18/ansible/pki/LISEZMOI-hv-par1-root-ca.md), flux : [`pare_feu.yml.extrait`](fichiers/M09-E18/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait).
- `plateforme/infra` : [`envs/hv-invites/`](fichiers/M09-E18/infra/envs/hv-invites/) (`versions.tf`, `backend.tf`, `chiffrement.tf`, `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars`, `README.md`), jobs de CI : [`gitlab-ci.yml.extrait`](fichiers/M09-E18/infra/gitlab-ci.yml.extrait).

**Architecture.**
```
        adm01 / runner01 ── https://hv.par1.medisphere.internal:8006 (TLS vérifié, autorité hv-par1)
                                     │ 10.10.10.200 (VRID 110, VRRP v3 unicast)
            ┌────────────────────────┼────────────────────────┐
         hv01 (150)               hv02 (140)               hv03 (130)
   keepalived + santé      keepalived + santé       keepalived + santé
   (quorum ET API 8006)    …                        …
   pveproxy : certificat {hv01, hv01.par1…, hv.par1…, 10.10.10.51, 10.10.10.200}
```

**La VIP.** keepalived sur chaque nœud, tous en `BACKUP` avec `nopreempt` : le premier nœud sain prend la VIP et la garde ; un nœud de plus forte priorité qui revient de maintenance ne la reprend pas (pas de seconde coupure). Le script de santé (toutes les 2 s, 2 échecs) vérifie que le nœud est dans une partition **qui a le quorum** (sinon `/etc/pve` est en lecture seule et toute écriture par l'API échouerait) et que **l'API répond avec le bon certificat** (`curl --cacert` de l'autorité du cluster, `--resolve` du nom de la VIP vers 127.0.0.1, 401 attendu sans jeton). En échec, l'instance passe en `FAULT` et rend la VIP : un autre nœud la prend en 4 à 6 secondes (2 × 2 s de santé + délai d'annonce VRRP). Annonces **unicast** vers les deux autres nœuds, comme au module 07 (pas de multicast sur MGMT, pas de collision avec les VRID 1-99 des passerelles). Arrêt propre d'un nœud : keepalived s'arrête, envoie une annonce de priorité 0, bascule immédiate.

**Le nom.** Dans NetBox : adresse 10.10.10.200/24, rôle « VIP », `dns_name` `hv.par1.medisphere.internal`, statut actif ; la génération du DNS (M06-E15, `medictl dns sync`) publie le A et le PTR.

**Le certificat : comparaison** (dans la MR) :

| Solution | Pour | Contre | Verdict |
|---|---|---|---|
| **Certificat signé par l'autorité du cluster**, noms du nœud **+ nom de la VIP** (retenue) | aucune dépendance externe ; la clé naît et reste sur le nœud ; le rôle le renouvelle à 30 jours de l'échéance (CI hebdomadaire) | une autorité de plus à faire confiance sur `adm01`/`runner01` ; sa clé est sur les trois nœuds (un nœud compromis peut signer n'importe quel nom pour qui fait confiance à cette autorité) : confiance limitée aux deux postes d'automatisation | simple et robuste pour un point d'accès interne |
| ACME HTTP-01 (step-ca, `pvenode acme`) avec le nom de la VIP | autorité MédiSphère unique, renouvellement intégré à Proxmox | le défi pour `hv.par1.medisphere.internal` arrive au nœud **qui porte la VIP**, pas forcément à celui qui commande : l'émission échoue sur deux nœuds sur trois ; flux `ca01` → nœuds:80 à ouvrir | inadapté à un nom partagé |
| ACME DNS-01 (greffon PowerDNS de Proxmox) | autorité unique, fonctionne pour un nom partagé | la clé d'API PowerDNS (qui écrit **toutes** les zones, pas de clé restreinte en 5.0) sur les hyperviseurs ; flux vers `dns01:8081` | risque disproportionné |
| Répartiteur (`lb01`/`lb02`) qui termine TLS | un seul certificat ACME, santé par HAProxy | le cluster de virtualisation dépend de la DMZ ; console noVNC/xterm.js (WebSocket) à soigner | plus tard, si l'API est exposée au-delà de l'équipe |
| DNS multi-A (trois A pour un nom) | rien à installer | pas de détection de panne (un client sur trois tombe sur le nœud mort), et le certificat reste à résoudre | non |

Le rôle : lit le certificat en place (`/etc/pve/local/pveproxy-ssl.pem`), le réémet s'il manque, s'il n'est pas signé par l'autorité du cluster, s'il expire dans moins de 30 jours ou s'il lui manque un nom ; sinon ne fait rien (idempotent). Émission dans un dossier temporaire (clé RSA 2048, extensions `serverAuth`, numéro de série aléatoire pour ne pas toucher au fichier de série de l'autorité, partagé par pmxcfs), puis `pvenode cert set … --force 1 --restart 1`, puis effacement du dossier. `serial: 1` : un seul pveproxy redémarre à la fois.
⚠️ **Et en M09-E26** : le certificat de l'interface 8006 passera à l'ACME de step-ca (autorité MédiSphère, noms du nœud **et** de la VIP), émis par le rôle `certificats_acme` de M06-E18 et installé par `pvenode cert set` (pas le client `pvenode acme`, dont le renouvellement refait un défi chaque fois : voir le corrigé d'E26). Le rôle prévoit ce passage : `pve_cluster_cert_gere: false` (sinon il remplacerait ce certificat, signé par une « autre » autorité que celle du cluster) et `pve_cluster_sante_ca` sur la racine MédiSphère (sinon le script de santé rejetterait le nouveau certificat et la VIP tomberait sur **tous** les nœuds). L'autorité du cluster pourra alors sortir du magasin de confiance d'`adm01` et `runner01` (`ca_lab_retirer`).

**Confiance.** `pki/hv-par1-root-ca.crt` (copie **publique** de `/etc/pve/pve-root-ca.pem`, empreinte vérifiée sur la console d'un nœud) est versionné dans `plateforme/ansible` ; le rôle `ca_lab` l'installe sur `adm01` et `runner01` seulement (`host_vars`, pas `group_vars/all`). Le playbook `hv-cluster.yml` refuse de tourner si le fichier versionné diffère de l'autorité réelle (cluster reconstruit en E29 ou E46 : nouvelle autorité, nouvelle MR). Le provider `bpg/proxmox` (Go) et `curl` utilisent alors le magasin système : ni `insecure`, ni `-k`.

**Flux.** `runner01` (INFRA) → VIP et nœuds (MGMT), TCP 8006 : nouvelle ligne de la matrice (le VLAN INFRA ne joint pas MGMT par défaut) ; `adm01` est sur MGMT (rien à ouvrir). VRRP entre nœuds : même segment, ne traverse pas la bordure ; **à autoriser** le jour où le pare-feu de Proxmox sera activé sur les nœuds (E26 : protocole 112 entre 10.10.10.51-53).

**OpenTofu.** `envs/hv-invites` : mêmes conventions que les autres états (état S3 chiffré, verrou natif, provider épinglé `~> 0.116.0` avec `.terraform.lock.hcl`, rien de secret), endpoint et jeton par l'environnement. Une ressource `proxmox_virtual_environment_vm` par entrée de `var.vms` (clone **complet** de 199, depuis le nœud qui porte sa configuration : `clone.node_name`), `pool_id = "recette"` (variable validée : le jeton n'a de droits que là), étiquettes `tofu` et `recette`, `started = true` (d'où `VM.PowerMgmt`). En CI, trois jobs (`plan:`, `apply:`, `derive:hv-invites`) qui étendent les gabarits du M05 et remplacent, **dans ces jobs seulement**, `PROXMOX_VE_ENDPOINT`/`PROXMOX_VE_API_TOKEN` par les variables protégées `HV_…`. Le job `validate` des MR n'a besoin d'aucun secret (`tofu init -backend=false`, `tofu validate`).

**Démonstration.**
```
admin@adm01:~$ dig +short hv.par1.medisphere.internal
10.10.10.200
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://hv.par1.medisphere.internal:8006/api2/json/version
401
admin@adm01:~$ for n in hv01 hv02 hv03; do ssh root@$n "ip -br -4 addr show vmbr0" ; done | grep 10.10.10.200
vmbr0            UP             10.10.10.51/24 10.10.10.200/24
```
Pipeline : MR → `plan:hv-invites` (2 à créer) → fusion → `apply:hv-invites` (manuel) → `rec01` (130, `hv02`), `rec02` (131, `hv03`). Puis `ha-manager crm-command node-maintenance enable hv01` (si `hv01` porte la VIP), `shutdown -h now` sur `hv01` : la VIP passe sur `hv02` (`journalctl -u keepalived` : `Entering MASTER STATE`) ; job `plan:hv-invites` relancé : « No changes ». `qm start 2091` sur `pve01`, sortie de maintenance : la VIP **reste** sur `hv02` (`nopreempt`).

**Explications**

Un cluster Proxmox n'a pas de point d'accès unique : chaque nœud sert toute l'API (n'importe lequel répond pour tout le cluster grâce à pmxcfs et au relais interne des requêtes vers le nœud concerné). Il suffit donc d'une adresse qui suit un nœud **utilisable**. « Utilisable » est le point fin : un nœud vivant mais sans quorum répond aux lectures et refuse les écritures ; la santé doit tester le quorum, pas seulement le port 8006.

**Alternatives**
- *Rôle `keepalived` du module 07* paramétré (instances, scripts) plutôt qu'un rôle dédié : moins de code, mais la santé (Corosync, API) est propre aux hyperviseurs ; le corrigé garde un rôle `pve_cluster` qui pourra aussi porter d'autres réglages de cluster (`datacenter.cfg`).
- *Provider configuré avec la liste des nœuds* : `bpg/proxmox` n'accepte qu'un point d'accès.
- *Ressource `proxmox_virtual_environment_cluster_options`* pour mettre `datacenter.cfg` dans le code (E20) : à faire, avec un jeton plus puissant (`Sys.Modify` sur `/`), donc **pas** celui de la recette.

**Pièges classiques**
- Santé limitée à « le port 8006 répond » : un nœud isolé (sans quorum) garde ou prend la VIP, les `apply` échouent en « cluster not ready - no quorum? ».
- Préemption laissée active : chaque retour de `hv01` refait basculer la VIP (deux coupures par maintenance).
- `curl -k` dans le script de santé « parce que c'est local » : il ne détecterait plus un certificat sans le nom de la VIP — justement ce qui casse les clients.
- Charger `pve-tofu.env` après `pve-tofu-hv.env` : jeton de `pve01` envoyé au cluster (401), ou pire, l'inverse sur l'état d'un autre environnement.
- Oublier que la clé de l'autorité du cluster est sur **tous** les nœuds : ne jamais l'installer dans `group_vars/all` (tout le lab ferait confiance à trois hyperviseurs pour n'importe quel nom).

**En production chez MédiSphère**
Point d'accès derrière les répartiteurs avec un certificat de l'autorité MédiSphère et l'authentification centrale (M24), API d'administration filtrée (IPSet `management`, E26), jetons d'automatisation dans OpenBao avec durée courte (M25), et la VIP supervisée (qui la porte, combien de bascules par jour).

---

### M09-E19 — Mises à jour progressives des nœuds

**Solution**

Fichier : [`playbooks/hv-mise-a-jour.yml`](fichiers/M09-E19/ansible/playbooks/hv-mise-a-jour.yml) (`plateforme/ansible`, groupe `hv_par1` de `inventories/lab/hv.yml`, `ansible-lint` profil `production`).

1. **État de départ** : `pveversion -v | head -3`, `uname -r`, `apt list --upgradable`, `grep -r Enabled /etc/apt/sources.list.d/*.sources` ; `pvecm status`, `ceph -s`, `ha-manager status`. Le dépôt `pve-enterprise.sources` doit porter `Enabled: false` (sans abonnement : 401 à chaque `apt update`), `ceph.sources` doit viser `no-subscription` (posé par `pveceph install` en E10).
2. **Premier nœud à la main** (ici `hv03`) :
   ```
   root@hv01:~# ha-manager crm-command node-maintenance enable hv03
   root@hv01:~# watch ha-manager status                            # plus de « service … (hv03, started) »
   root@hv03:~# qm list                                            # VMs non HA ? les migrer (pvenode migrateall)
   root@hv01:~# ceph osd set-group noout hv03
   root@hv03:~# apt update && apt full-upgrade
   root@hv03:~# ls /run/reboot-required; uname -r; ls /boot/vmlinuz-*
   root@hv03:~# reboot
   root@hv03:~# pvecm status; systemctl is-active pve-cluster pveproxy pve-ha-lrm; ceph osd tree | grep -A2 hv03
   root@hv01:~# ceph osd unset-group noout hv03
   root@hv01:~# ha-manager crm-command node-maintenance disable hv03
   root@hv01:~# ceph -s                                            # attendre HEALTH_OK
   ```
   Fenêtre typique dans le lab : 8 à 15 minutes par nœud, dont l'essentiel en évacuation et redémarrage. `set-group noout hv03` (et non `set noout`) : seuls les OSD de `hv03` sont protégés contre le passage `out` ; une vraie panne ailleurs pendant la fenêtre déclencherait toujours la récupération.
3. **Playbook** : contrôles d'entrée (quorum, aucun **autre** nœud en maintenance, Ceph sain ou seulement le drapeau de **ce** nœud — reprise après interruption), puis pour un nœud qui a des paquets à installer ou un état à reprendre : maintenance, attente de l'évacuation, drapeau, `apt` en `dist`, redémarrage si `/run/reboot-required` existe ou si le noyau en cours n'est pas le plus récent, contrôles de retour (quorum, services, OSD `up`), retrait du drapeau, sortie de maintenance ; enfin `HEALTH_OK` avant le nœud suivant. Le drapeau n'est **pas** retiré dans un bloc `always` : si le nœud ne revient pas, le retirer déclencherait la reconstruction au mauvais moment ; le playbook s'arrête (`any_errors_fatal`) et laisse l'état visible pour l'humain.
4. `uv run ansible-lint playbooks/hv-mise-a-jour.yml` puis `uv run ansible-playbook playbooks/hv-mise-a-jour.yml`. `ping -O -i 0.2` vers `app01` et `app02` depuis `adm01` : 0 à 2 paquets perdus par migration, soit une poignée sur toute l'opération ; aucune VM arrêtée.
5. **Majeure** : relire les notes de version et la page *Upgrade from 9 to 10* (le jour venu), lancer l'outil de contrôle fourni pour chaque majeure (`pve8to9` pour 8 → 9 : dépôts, paquets, version de Ceph, configuration de Corosync, invités, stockage — il existera un équivalent pour 10), mettre Ceph à la version requise **avant**, changer les dépôts (suite Debian), mettre à jour un nœud à la fois en suivant la page, et ne pas laisser durer un cluster en versions mixtes. La montée de **Ceph** (E28) suit sa propre procédure (MON, puis MGR, puis OSD, puis `require-osd-release`), indépendante de la boucle par nœud de ce playbook : la mélanger avec un `full-upgrade` reviendrait à redémarrer des démons Ceph dans un ordre non maîtrisé.

**Explications**

Trois mécanismes se combinent : le mode maintenance HA (le nœud ne porte plus de ressource HA, son *watchdog* est fermé : un redémarrage ne déclenche pas de *fencing*), le drapeau Ceph `noout` limité au nœud (ses OSD absents ne sont pas remplacés : pas de recopie de données pour quelques minutes d'absence), et l'ordre strict « un nœud complet avant le suivant ». `apt full-upgrade` est exigé parce qu'une mise à jour de Proxmox VE ajoute ou retire régulièrement des paquets (nouveau noyau, bibliothèques renommées) : `apt upgrade` les laisserait de côté et produirait un nœud à moitié à jour.

**Alternatives**
- *Politique d'arrêt `migrate`* (E20) à la place du mode maintenance pour un simple redémarrage : moins de commandes, mais pas d'attente explicite, et rien ne protège pendant l'`apt`.
- *Redémarrage différé* : installer partout, puis redémarrer nœud par nœud dans une seconde fenêtre (le noyau en cours reste l'ancien jusque-là).
- *Proxmox Datacenter Manager* (outil distinct) pour piloter plusieurs clusters : hors périmètre ici.

**Pièges classiques**
- `ceph osd set noout` global, oublié en fin de fenêtre : plus aucune récupération automatique pendant des jours.
- Deux nœuds en maintenance en même temps : Ceph sous `min_size`, HA sans place.
- Redémarrer avant la fin de l'évacuation : les ressources encore présentes sont gelées (`freeze`) le temps du redémarrage (politique `conditional`) ; une VM non HA est arrêtée net.
- Mettre à jour pendant une montée de version de Ceph (dépôts en Tentacle sur un nœud, Squid sur les autres).

**En production chez MédiSphère**
Fenêtre mensuelle annoncée, pipeline de mise à jour déclenché à la main avec approbation, rapport des versions avant/après archivé dans la fiche de changement, supervision qui alerte si un nœud reste en maintenance ou avec un drapeau Ceph plus de deux heures (M09-E25).

---

### M09-E20 — Évacuer un nœud, équilibrer la charge

**Solution**

1. **Politique par défaut (`conditional`)**, `reboot` de `hv02` : le LRM demande au CRM de **geler** (`freeze`) ses ressources ; elles sont arrêtées avec le nœud et redémarrées **sur `hv02`** à son retour. Indisponibilité de chaque VM HA : arrêt + redémarrage complet du nœud + démarrage de la VM, soit plusieurs minutes. (Avec un `shutdown`, elles seraient arrêtées puis reprises ailleurs au bout d'environ 2 minutes.)
2. **Politique `migrate`** :
   ```
   root@hv01:~# pvesh set /cluster/options --ha shutdown_policy=migrate
   ```
   Même `reboot` : le LRM se déclare indisponible, les ressources HA sont **migrées à chaud** avant que l'arrêt ne continue ; indisponibilité ≈ quelques dizaines de millisecondes par VM ; elles reviennent sur `hv02` à son retour. L'arrêt attend que tout soit parti : une ressource bloquée par une règle stricte limitée à ce nœud le ferait patienter indéfiniment.
3. **Évacuation de `hv03`** : `ha-manager crm-command node-maintenance enable hv03` pour les ressources HA ; les invités **non** HA restent : `pvenode migrateall hv01 --vms 141 --max-workers 2` (ou toutes : `pvenode migrateall hv01 --with-local-disks`). `rep01`, si elle est sur `hv03` : disque local répliqué, migration avec transfert du seul delta (E14). Sortie : `node-maintenance disable hv03` → les ressources HA qui y étaient y **reviennent** ; les invités non HA restent où on les a mis.
4. **CRS et équilibrage** :
   ```
   root@hv01:~# pvesh set /cluster/options --crs 'ha=dynamic,ha-rebalance-on-start=1,ha-auto-rebalance=1,ha-auto-rebalance-threshold=40'
   root@hv01:~# grep -E '^(crs|ha):' /etc/pve/datacenter.cfg
   crs: ha=dynamic,ha-auto-rebalance=1,ha-auto-rebalance-threshold=40,ha-rebalance-on-start=1
   ha: shutdown_policy=migrate
   ```
   Déséquilibre : migrer `app01-03` sur `hv01` (en désactivant temporairement la règle `frontaux-separes`, sinon impossible) puis la réactiver, charger deux VMs (`stress-ng --cpu 1 --timeout 15m`). L'équilibreur attend que le déséquilibre dépasse 40 % pendant 3 tours (≈ 30 s, `ha-auto-rebalance-hold-duration`), puis déclenche **une** migration à la fois, celle qui réduit le plus le déséquilibre (méthode `bruteforce` par défaut), et seulement si le gain dépasse 10 % (`ha-auto-rebalance-margin`). `app01` ne bouge pas (ou revient) : sa règle d'affinité la préfère sur `hv01` et `failback` la ramène ; les deux frontaux restent séparés. ⚠️ Rythme et choix exacts à observer : fonction récente (9.2).
5. **Désarmement** :
   ```
   root@hv01:~# ha-manager crm-command disarm-ha freeze
   root@hv01:~# ha-manager status          # fencing : disarming, puis disarmed ; LRM : watchdog released
   root@hv01:~# ha-manager crm-command arm-ha
   ```
   `freeze` : les ressources restent en l'état, la HA n'applique plus rien (le plus sûr si tous les nœuds restent allumés). `ignore` : les ressources sortent du suivi et se gèrent comme des VMs ordinaires ; au réarmement, le CRM relit leur emplacement. À choisir quand l'intervention (réseau, Corosync) exige de **déplacer** des VMs à la main pendant que la HA est suspendue.
6. Questions : l'équilibreur ne pilote que ce que la HA gère (il émet des migrations HA, par le CRM) ; les VMs non HA sont hors de son modèle (la documentation annonce leur prise en compte « dans le futur »). Seuil trop bas dans un cluster de trois nœuds : chaque petite variation de charge déclenche une migration, qui elle-même charge le réseau et la mémoire des nœuds ; on obtient un « ping-pong » de VMs sans gain réel. Garder un seuil élevé et une marge, et exclure les VMs sensibles (`--auto-rebalance 0`).

**Explications**

Le CRS (*Cluster Resource Scheduler*) choisit un nœud pour une ressource HA à chaque « point de planification » (relance après panne, nouvelle règle, démarrage si `ha-rebalance-on-start`, et en 9.2 l'équilibrage automatique). Le mode `basic` compte les ressources par nœud ; `static` additionne les CPU et mémoires **configurés** ; `dynamic` (9.2) prend la consommation **réelle** moyenne en plus. La mémoire pèse beaucoup plus que le CPU dans le calcul, parce qu'elle ne se partage pas.

**Alternatives**
- *`ha=static`* : plus prévisible (ne dépend pas d'un pic passager), suffisant si les VMs sont dimensionnées honnêtement.
- *Équilibrage manuel* hebdomadaire guidé par la supervision : pas de migration surprise, plus de travail.
- *Désarmement* contre *maintenance* : désarmer suspend la HA de tout le cluster ; la maintenance vide un nœud. Pour une intervention sur Corosync (changement de lien, M09-E27), désarmer en `freeze` ; pour une intervention sur un nœud, la maintenance.

**Pièges classiques**
- Croire que `migrate` ou la maintenance déplacent toutes les VMs : seulement les ressources HA.
- Oublier de réarmer : `ha-manager status` le montre, rien d'autre ne le signale.
- Activer l'équilibrage avec `ha=basic` : sans mesure de charge, il ne fait rien (la documentation exige `static` ou `dynamic`).
- Désactiver une règle d'affinité pour un essai et ne pas la réactiver.

**En production chez MédiSphère**
`shutdown_policy=migrate` partout, équilibrage automatique avec seuil prudent et exclusions documentées, et une alerte quand la HA est désarmée plus de 30 minutes ou qu'un nœud reste en maintenance hors fenêtre.

---

### M09-E21 — Revue : la configuration de cluster du stagiaire

**Solution**

Versions corrigées : [`corosync.conf`](fichiers/M09-E21/corosync.conf), [`ha-rules.cfg`](fichiers/M09-E21/ha-rules.cfg), [`storage.cfg`](fichiers/M09-E21/storage.cfg).

1. **Lecture d'ensemble.**
   - Voix : 1 + 1 + **2** = 4 ; quorum = majorité stricte = **3**. Perte de `hv01` ou de `hv02` : 3 voix restent (`hv03` + l'autre) → quorum. Perte de **`hv03`** : 2 voix sur 4 → **perte du quorum**, alors que deux nœuds sur trois sont vivants. Le « gros serveur » est devenu un point unique de défaillance ; et avec `two_node: 1` en plus (voir n° 4), le comportement devient difficile à prévoir.
   - Trafic Corosync : lien 0 sur le réseau **Ceph public** (10.10.30.0/24), lien 1 sur MGMT via des **noms**.
   - Lecture et modification : `secauth: off` et `crypto_cipher/crypto_hash: none` : tout équipement du VLAN 30 (les clients Ceph, `ceph01-03`, demain les nœuds OpenStack) peut lire les messages du cluster et en **injecter** (adhésion, configuration).
2. **Règles HA**, telles qu'elles seraient traitées :
   - `bdd-sur-nvme` (stricte, `hv01`, `vm:100` et `vm:103`) et `licence-hv02` (`vm:103`) : `vm:103` est dans **deux** règles d'affinité de nœud → les deux règles sont **désactivées** d'office (contrôle de faisabilité « une ressource dans une seule règle d'affinité de nœud »). Si on ne garde que la première : à la perte de `hv01`, `vm:100` et `vm:103` sont **arrêtées** (règle stricte, plus aucun nœud autorisé).
   - `web-separes` : quatre ressources séparées sur trois nœuds → infaisable → règle **désactivée**. Les quatre frontaux peuvent alors se retrouver sur le même nœud.
   - Au démarrage, Lucas ne voit rien : les VMs démarrent, `ha-manager status` est vert ; les règles désactivées n'apparaissent que dans `ha-manager rules config` (et le journal du CRM).
3. **Stockages** et `root` sur un nœud :
   - `local-lvm` avec `shared 1` : Proxmox **croit** le stockage partagé. Une migration à chaud ne copie pas le disque (il est censé être visible de la cible) : la VM redémarre sur la cible avec un volume qui n'existe pas, ou pire, un volume homonyme d'une autre VM. La HA relancerait aussi les VMs ailleurs en croyant leurs disques disponibles. **Corruption ou perte de données.**
   - `ceph-par1-rbd` avec `username admin` : la clé `client.admin` de `ceph-par1` est dans `/etc/pve/priv/ceph/` : `root` sur un nœud de recette = administrateur du Ceph de **production** (pools d'OpenStack et de Kubernetes compris).
   - `pbs-par2` avec `root@pam` : le mot de passe de `root@pam` de **`pbs01`** est dans `/etc/pve/priv/storage/pbs-par2.pw` : `root` sur un nœud = `root` sur le serveur de sauvegarde : il peut supprimer toutes les sauvegardes du lab (le scénario favori des rançongiciels). Pas de clé de chiffrement non plus.
4. **Revue** (gravités pour **notre** lab) :

   | N° | Fichier, ligne(s) | Défaut | Catégorie | Gravité | Impact | Correction |
   |---|---|---|---|---|---|---|
   | 1 | `storage.cfg`, `local-lvm` / `shared 1` | stockage local déclaré partagé | fonctionnement | **critique** | migration et HA démarrent des VMs sans leur disque : corruption, perte | retirer `shared 1` ; HA seulement sur `ceph-vm` |
   | 2 | `storage.cfg`, `pbs-par2` / `username root@pam` | compte `root` de PBS dans le cluster | sécurité | **critique** | `root` d'un nœud → suppression de toutes les sauvegardes | compte et jeton dédiés (`wb-recette@pbs!hv-recette`), `DatastoreBackup` sur `par1/recette` seulement (comme E15) |
   | 3 | `storage.cfg`, `ceph-par1-rbd` / `username admin` | identité `client.admin` du Ceph de production | sécurité | **critique** | `root` d'un nœud → administration de `ceph-par1` | `client.hv-recette`, `profile rbd pool=hv-recette` (E12) |
   | 4 | `corosync.conf`, `totem` / `secauth: off`, `crypto_* none` | Corosync en clair et sans authentification | sécurité | **critique** | lecture et injection de messages du cluster depuis le VLAN de stockage | retirer les trois lignes, `secauth: on` (défaut de Proxmox : chiffrement et authentification de knet ; vérifier `corosync-cmapctl | grep crypto`) |
   | 5 | `corosync.conf`, `hv03` / `quorum_votes: 2` | voix inégales, total pair | disponibilité | **élevée** | la perte du seul `hv03` fait perdre le quorum (2/4) | une voix par nœud |
   | 6 | `corosync.conf`, `quorum` / `two_node: 1` | option prévue pour **deux** nœuds exactement | disponibilité | **élevée** | active implicitement `wait_for_all` (le cluster attend tous les nœuds au démarrage) et fausse le calcul ; avec trois nœuds, elle n'a pas de sens | la retirer ; à deux nœuds, préférer un QDevice (E05) |
   | 7 | `corosync.conf`, `ring0_addr: 10.10.30.7x` | Corosync sur le réseau Ceph public | disponibilité | **élevée** | une récupération Ceph sature le lien, la latence dépasse le jeton Corosync : nœuds expulsés, *fencing* en cascade | lien 0 sur COROSYNC (10.10.32.0/24, dédié), lien 1 sur MGMT |
   | 8 | `corosync.conf`, `ring1_addr: hvNN` | noms au lieu d'adresses | disponibilité | moyenne | Corosync dépend du DNS (ou de `/etc/hosts`) au démarrage ; un nom qui résout autrement (IPv6, autre adresse) casse le lien | adresses IP |
   | 9 | `ha-rules.cfg`, `vm:103` dans deux règles d'affinité de nœud | conflit de règles | fonctionnement | **élevée** | les deux règles sont désactivées : ni la contrainte de licence ni le placement de la base ne s'appliquent | une seule règle par ressource |
   | 10 | `ha-rules.cfg`, `web-separes` | 4 ressources à séparer sur 3 nœuds | fonctionnement | **élevée** | règle désactivée : les frontaux peuvent tous finir sur un nœud | deux règles de deux, ou un quatrième nœud |
   | 11 | `ha-rules.cfg` + `ha-resources.cfg`, `vm:100` stricte sur `hv01` « pour ses NVMe » | ressource HA attachée à un stockage local d'un seul nœud | conception | moyenne | la HA ne peut rien pour elle : à la perte de `hv01`, elle est arrêtée (règle stricte) ; ses données sont sur un seul nœud | soit HA + disque sur `ceph-vm`, soit pas de HA et une protection applicative (réplication PostgreSQL) |
   | 12 | `storage.cfg`, `pbs-par2` sans `encryption-key` | sauvegardes en clair à PAR2 | sécurité | moyenne | PAR2 lit les données de santé | `--encryption-key autogen` + clé au Vault et sur papier |

   (Douze constats ; les n° 1 à 10 sont attendus.)
5. **Ordre de traitement** : d'abord n° 1 (`shared 1`) — il **détruit des données** à la première migration, sans attaque ; puis n° 2 et 3 (privilèges qui transforment la compromission d'un nœud de recette en compromission de la sauvegarde et du stockage de production), puis n° 4 (Corosync), 5-7 (quorum et liens), 9-10 (règles), 8, 11, 12.
6. **Versions corrigées** : fichiers du corrigé (rappel en tête de `corosync.conf` : on ne copie pas ce fichier à la main sur un cluster en service ; on édite `/etc/pve/corosync.conf` en incrémentant `config_version`).
7. **Conseils à Lucas** : (1) un cluster se teste **en panne** : coupe chaque nœud, chaque lien, et regarde `pvecm status` et `ha-manager status` ; (2) lis ce que l'outil dit de ta configuration (`ha-manager rules config`, `corosync-quorumtool -s`, `pvesm status`) au lieu de te fier à « ça démarre » ; (3) ne donne jamais à un client un compte d'administration « pour que ça marche du premier coup » : le premier coup est justement celui qu'on garde.

**Explications**

Les trois fichiers ont un point commun : ils sont **acceptés** sans erreur. Corosync démarre sans chiffrement, le gestionnaire HA désactive en silence les règles impossibles, Proxmox croit l'option `shared` sur parole. Une configuration de cluster se juge sur ce qu'elle fait quand quelque chose tombe ; c'est l'objet de cette revue et de tout le palier 4.

**Alternatives**
- Contrôles automatiques en CI sur les fichiers de référence (« pour aller plus loin ») : somme des voix impaire et égale au nombre de nœuds, absence de `crypto_cipher: none`, aucun `shared 1` sur `lvmthin`/`dir`/`zfspool`, aucun `username admin` ni `root@pam` dans `storage.cfg`.
- Ne pas versionner ces fichiers du tout, mais les **générer** (rôle Ansible, OpenTofu `proxmox_virtual_environment_*` pour les stockages et la HA) : la revue porte alors sur le code, et les contrôles sont des tests.

**Pièges classiques**
- Ne relever que le chiffrement et manquer `shared 1`, qui n'a rien de « sécurité » mais détruit des données.
- Calculer le quorum avec le nombre de **nœuds** au lieu du nombre de **voix**.
- Corriger `two_node` en mettant `expected_votes: 3` « pour être sûr » : redondant avec la liste des nœuds, et piège au prochain ajout de nœud.

**En production chez MédiSphère**
La configuration de cluster n'est jamais copiée à la main : elle sort du code (rôles `pve_*`), passe par une MR avec contrôles automatiques et une revue par un second ingénieur, et chaque changement de Corosync suit une fiche de changement avec désarmement de la HA (E20).

---

### M09-E22 — Runbook : maintenance d'un nœud

**Solution**

Runbook de référence : [`RB-090-maintenance-noeud.md`](fichiers/M09-E22/medisphere/docs/virtualisation/runbooks/RB-090-maintenance-noeud.md).

Points que la grille d'auto-évaluation attend :
- **Contrôles d'entrée chiffrés** : quorum, `HEALTH_OK`, aucun autre nœud en maintenance, **capacité mémoire** des nœuds restants (sinon la maintenance échoue à mi-chemin avec des VMs coincées), réplications à jour, sauvegarde récente.
- **Ordre** : maintenance HA (et attente vérifiée de l'évacuation) → invités non HA → drapeau Ceph limité au nœud (`set-group noout`, jamais `set noout` global) → intervention → contrôles de retour → retrait du drapeau → `HEALTH_OK` → sortie de maintenance → contrôles de sortie.
- **Durée** : courte ou longue change la décision Ceph. Dans un cluster de trois nœuds, laisser Ceph « reconstruire » ne sert à rien (pas de troisième hôte pour la troisième copie) : on garde `noout`, en sachant que les données n'ont que deux copies pendant toute l'intervention ; c'est un risque à **accepter explicitement** (Karim), pas un réglage par défaut.
- **Échecs prévus** : ressource qui ne part pas (règle stricte, disque local), nœud qui ne revient pas (bascule vers RB-091 en laissant drapeau et maintenance), Ceph qui ne revient pas à `HEALTH_OK`.
- **Retour arrière par étape** et **contrôle de sortie** qui garantit qu'aucun drapeau ni mode maintenance ne reste posé.
- **Communication** : début, fin, et qui alerter si la fenêtre déborde ; mention de la VIP de l'API (gel des pipelines de `plateforme/infra`).

**Explications**

Un runbook vaut par ce qu'il fait faire à quelqu'un qui ne connaît pas le système à 2 h du matin : des commandes exactes, un résultat attendu observable, une conduite en cas d'écart, et des points d'arrêt où l'on **ne continue pas**. La partie la plus utile est souvent « quand ne pas l'utiliser » : la moitié des incidents de maintenance viennent d'une maintenance commencée sur un cluster déjà dégradé.

**Alternatives**
- Automatiser l'entrée et la sortie de maintenance (`hv-maintenance.yml`, « pour aller plus loin ») et garder le runbook pour les décisions et les contrôles.
- Un runbook par type d'intervention (redémarrage, remplacement de disque système, remplacement de carte réseau) : plus précis, plus de documents à maintenir.

**Pièges classiques**
- Runbook écrit de mémoire, jamais joué : les commandes ont des fautes, les sorties attendues ne correspondent pas.
- Oublier les invités non HA, et les VMs à disque local (réplication).
- Oublier la sortie de maintenance : les ressources ne reviennent jamais sur le nœud, le cluster reste déséquilibré.

**En production chez MédiSphère**
RB-090 est joué à chaque fenêtre mensuelle (E19) et après chaque montée de version ; toute hésitation pendant l'exécution donne une MR sur le runbook dans la semaine.

---

### M09-E23 — Importer une VM venue d'ailleurs

**Solution**

Fichiers : [`importer-legacy.sh`](fichiers/M09-E23/importer-legacy.sh) (contrôle de l'archive, import, mise aux standards) ; l'OVA vient de `ressources/M09-E23/generer-ova.sh`.

1. **Contrôle de l'OVA** :
   ```
   root@hv01:~# tar -tvf /var/lib/vz/import/legacy-rdv01.ova
   -rw-r--r-- root/root      4183 … legacy-rdv01.ovf
   -rw-r--r-- root/root       189 … legacy-rdv01.mf
   -rw-r--r-- root/root 327481856 … legacy-rdv01-disk1.vmdk
   root@hv01:~# sha256sum /var/lib/vz/import/legacy-rdv01.ova       # à comparer avec la somme notée à la génération
   ```
   Après extraction : `sha256sum -c` sur le manifeste converti (le script le fait). Le descripteur déclare 2 vCPU, 2048 Mo, un contrôleur SCSI `lsilogic`, un disque de 10 Gio en VMDK *streamOptimized*, une carte `E1000` sur « VM Network », un micrologiciel BIOS, un système « Debian 64 bits » (identifiant OVF 96). L'ordre (descripteur en premier) est exigé par la norme OVF pour une archive OVA.
2. **Contenu « import »** : déjà ajouté en M09-E06 (`pvesm status --storage local` et `grep -A3 '^dir: local' /etc/pve/storage.cfg` le confirment). Sinon : `pvesm set local --content iso,vztmpl,backup,import,snippets`, en **conservant** tous les contenus existants (l'option remplace la liste ; oublier `snippets` casserait le fragment cloud-init `medisphere-agent.yaml` de tous les invités clonés du template 199). L'OVA apparaît dans *local → Virtual Guests* ; l'assistant propose nom, CPU, mémoire, disques et carte réseau extraits du descripteur, avec un stockage de travail pour l'extraction ; il signale qu'un contrôleur SCSI n'est presque jamais décrit dans un OVF et propose VirtIO SCSI.
3. **Import en CLI** : `qm importovf 150 legacy-rdv01.ovf ceph-vm --dryrun 1` affiche la représentation extraite (nom, `cores`, `memory`, disque `scsi0` et son fichier, `ostype`) ; puis sans `--dryrun`. D'après le code de l'analyseur (`PVE::GuestImport::OVF`), il récupère le nom, les cœurs, la mémoire, le type de système, le micrologiciel (`bios = ovmf` si le descripteur VMware dit `efi`), les disques et leur emplacement sur leur contrôleur, et le **modèle** des cartes réseau (`e1000`, `e1000e`, `vmxnet3`) ; il ne sait rien du réseau de destination, du type de contrôleur SCSI (Proxmox garde son défaut), ni des options propres à VMware (outils, synchronisation de l'heure). ⚠️ À vérifier sur ton lab : selon la version, `qm importovf` crée ou non la carte réseau ; le script en pose une de toute façon.
4. **Premier démarrage tel quel** : avec le contrôleur par défaut (LSI 53C895A émulé), le noyau « cloud » de Debian peut ne pas trouver son disque (il n'embarque pas tous les pilotes de contrôleurs anciens) : arrêt dans l'*initramfs* (« Gave up waiting for root file system device »). ⚠️ Le résultat exact dépend de l'image et du noyau : note ce que tu observes. Mise aux standards (`importer-legacy.sh`) : `--scsihw virtio-scsi-single`, `--cpu x86-64-v2-AES` (identique sur tous les nœuds : migration possible ; `host` seulement si un besoin de performance le justifie), `--serial0 socket --vga serial0` (console série), `--agent enabled=1`, carte `virtio` sur `vinv99`. La VM démarre.
5. **Reprise de main** : lecteur cloud-init (`--ide2 ceph-vm:cloudinit --ciuser admin --sshkeys <fichier .pub> --ipconfig0 ip=dhcp`). L'identifiant d'instance du lecteur Proxmox diffère de tout ce que l'image a vu : cloud-init rejoue la configuration (utilisateur `admin`, clé, réseau). Puis :
   ```
   admin@adm01:~$ ssh admin@<IP-LEGACY>
   admin@legacy-rdv01:~$ sudo apt-get update && sudo apt-get install -y qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent
   admin@legacy-rdv01:~$ dpkg -l open-vm-tools 2>/dev/null | grep ^ii && sudo apt-get purge -y open-vm-tools
   root@hv01:~# qm agent 150 ping && qm agent 150 network-get-interfaces | jq -r '.[]."ip-addresses"[]?."ip-address"'
   ```
   (`<IP-LEGACY>` : l'adresse DHCP obtenue sur le VLAN 99, lue dans la console ou dans les baux de Kea.) L'image cloud n'a pas les outils VMware ; une vraie VM d'InfoGér les aurait, à retirer (ils ne servent à rien et tournent pour rien).
6. `pveum pool modify prod --vms 150` ; `vzdump 150 --storage pbs-par2 --mode snapshot` (sur le nœud qui porte la VM).
7. **Liste de contrôle pour les vingt suivantes** :
   - *Intégrité* : somme de l'OVA envoyée par un autre canal ; manifeste vérifié ; descripteur lu.
   - *Matériel* : contrôleur `virtio-scsi-single` (ou, pour Windows, SATA le temps d'installer les pilotes VirtIO), carte `virtio` (Windows : e1000 d'abord), type de CPU commun au cluster, BIOS/UEFI conforme à l'origine (un invité UEFI démarré en BIOS ne démarre pas ; disque EFI à ajouter).
   - *Pilotes* : Linux : `initramfs` qui contient `virtio_scsi`/`virtio_blk` (régénérer **avant** l'export si possible) ; Windows : ISO `virtio-win`, et l'astuce de démarrage en IDE/SATA puis bascule.
   - *Réseau* : noms d'interface qui changent (`ens192` → `ens18`), adresse statique de l'ancien réseau (192.168.50.20 ici) à remplacer ; VNet de destination.
   - *Identité* : nouvelle MAC (la conserver si une licence en dépend), `machine-id` et clés SSH d'hôte **régénérés** si l'on clone l'import, nom d'hôte, enregistrement DNS/NetBox.
   - *Agent* QEMU installé et actif ; outils de l'ancien hyperviseur retirés.
   - *Sauvegarde* et inscription au pool, étiquettes, HA si besoin.
   - *Windows en plus* : licence et réactivation (changement de matériel), pilotes VirtIO signés, agent QEMU pour Windows, synchronisation de l'heure (UTC vs heure locale : `localtime`).

**Explications**

Un OVF décrit une VM de façon **minimale et portable** ; chaque hyperviseur y ajoute ses extensions (VMware : `vmw:Config`, outils, type de système `vmw:osType`). Proxmox en tire ce qui est commun (CPU, mémoire, disques, carte) et laisse le reste à l'administrateur. Le disque VMDK est converti au format du stockage cible (ici RBD brut) pendant l'import. Le vrai travail est après : rendre la VM conforme au modèle de la plateforme (pilotes paravirtualisés, agent, console, sauvegarde), et reprendre la main sans dépendre du prestataire sortant.

**Alternatives**
- *Assistant d'import* (interface) : mêmes étapes, plus confortable, extraction gérée sur un stockage de travail ; pratique pour quelques VMs.
- *Import depuis ESXi* (stockage `esxi`) : lit directement les VMs d'un ESXi ou d'un vCenter, avec un temps d'arrêt réduit ; la voie pour une migration en masse (F4).
- *`qm disk import`* : quand on n'a qu'un disque (qcow2, vmdk, raw) sans descripteur : créer la VM à la main, importer le disque en `unused`, l'attacher.
- *Réinstaller* plutôt que migrer : souvent la meilleure option pour un serveur ancien, si l'application se redéploie (Legacy-RDV : au module 12 et dans F4, conteneurisation).

**Pièges classiques**
- Archive OVA non vérifiée : on importe ce qu'on a reçu, éventuellement tronqué ou modifié.
- `pvesm set local --content import` : remplace toute la liste des contenus (les ISO disparaissent de l'interface, et sans `snippets` les invités qui référencent `local:snippets/…` ne démarrent plus).
- Basculer le contrôleur en VirtIO sur un invité qui n'a pas le pilote dans son *initramfs* : il ne démarre plus (ici, l'inverse) — l'ordre des gestes dépend de l'invité.
- Laisser la carte `e1000` : fonctionne, mais lente et gourmande en CPU ; laisser `kvm64`/type par défaut de l'import : pas d'instructions modernes.
- Garder l'adresse statique d'InfoGér : conflit ou VM injoignable.

**En production chez MédiSphère**
Les imports se font en lot depuis l'ESXi d'InfoGér avec une fiche par VM (propriétaire, criticité, dépendances), dans un VNet de quarantaine, avec un contrôle de conformité scripté (matériel, agent, sauvegarde, étiquettes) avant passage en `prod` ; les VMs Windows suivent un runbook dédié.
