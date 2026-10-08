# Module 09 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`infra/` pour `plateforme/infra`, `ansible/` pour `plateforme/ansible`, `images/` pour `plateforme/images`, `outils/` pour `plateforme/outils`, `medisphere/` pour `plateforme/medisphere`, `adm01/` et `pbs01/` pour des fichiers propres à un hôte). Ne copie que ce que l'exercice ajoute ou modifie.

**Ce qui a été testé à la rédaction** :
- `envs/hv/` passe `tofu validate` et `tofu fmt -check` (OpenTofu 1.13.0, fournisseurs `bpg/proxmox` 0.116.0, `e-breuninger/netbox` 5.8.0, `mmianl/powerdns` 2.5.0, module `enregistrement-dns` de M06-E14), avec deux puis trois nœuds ;
- `preparer-iso.sh` a produit, avec un `pve01` simulé, des fichiers de réponse que l'analyseur TOML de Python lit sans erreur, avec les MAC, la série du disque et l'empreinte du mot de passe attendues ;
- le rôle `pve_noeud` et `playbooks/hv.yml` passent `ansible-lint` (profil `production`, ansible-core 2.20) ; les modèles (`interfaces`, `zfs.conf`) et les variables calculées (MAC, arguments de `pvesh set …/dns`) ont été rendus et relus ;
- tous les scripts passent `shellcheck -x` et `bash -n`.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- l'installation automatique elle-même (aucun Proxmox VE 9.2 disponible à la rédaction) : en particulier le filtre `filter.ID_NET_NAME_MAC` de la carte d'administration (vérifie le nom de la propriété avec `proxmox-auto-install-assistant device-info -t network` lancé sur un nœud installé), le filtre `filter.ID_SERIAL` du disque, et l'épinglage des noms `nic0`..`nic4` ;
- la forme du lien `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_<série>` pour un disque virtio-scsi avec un numéro de série (vérifie par `ls -l /dev/disk/by-id/` sur un nœud) ;
- l'option de vérification de syntaxe `ifup -a -s -i <fichier>` d'ifupdown2, utilisée en `validate:` par le rôle (si ta version la refuse, remplace-la par `ifquery -a -i %s`) ;
- le chemin d'ACL `/sdn/zones/localnetwork/vmbr1` pour un *trunk* (si la création échoue sur un droit, regarde le chemin cité dans le message) ;
- le téléchargement par `download-url` avec le contenu `import` (Proxmox VE 8.4 et plus) ;
- les sorties exactes de `pvecm`, `corosync-cfgtool` et `corosync-qnetd-tool` citées ci-dessous, relevées dans la documentation et sur un cluster 8.x.

---

### M09-E01 — Test de positionnement : virtualisation en cluster

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, relis les « Concepts clés » de l'introduction avant E04 ; les questions 6 à 12 sont reprises en E04, E05 et E09, les questions 13 à 16 au palier 2.

**Réponses argumentées — virtualisation**

**1. KVM, QEMU, imbrication.** `kvm` est le cœur générique : il expose `/dev/kvm` et gère les VMs comme des processus dont les vCPU s'exécutent en mode invité. `kvm_intel` (ou `kvm_amd`) est le pilote propre au processeur : il programme VT-x (VMX) ou AMD-V (SVM), et la traduction d'adresses de second niveau (EPT, NPT). QEMU, en espace utilisateur, émule tout le reste (cartes, disques, BIOS) et appelle `/dev/kvm` pour exécuter le code de l'invité ; chaque VM Proxmox VE est un processus `kvm` (QEMU). Pour qu'une VM exécute à son tour des VMs accélérées, il faut : (a) que le noyau de l'**hôte** autorise l'imbrication (`kvm_intel nested=Y`), (b) que la VM reçoive un **CPU virtuel qui expose VMX** (type `host`, ou un modèle avec le drapeau `+vmx`). L'un sans l'autre ne suffit pas.

**2. Réponse B.** `host` donne à l'invité **toutes** les instructions du processeur réel. L'invité (son noyau, ses bibliothèques) les détecte au démarrage et s'en sert ; sur un processeur plus ancien, elles manquent : QEMU refuse la migration si les drapeaux diffèrent, ou l'invité plante sur une instruction illégale. A est faux : le type ne « s'adapte » pas en cours de route, le jeu d'instructions est figé au démarrage. C : il n'y a pas de redémarrage automatique. D : aucune conversion n'a lieu. D'où la règle : dans un cluster, un type de CPU **commun** à tous les nœuds (`x86-64-v2-AES`, `x86-64-v3`…) ; `host` seulement si les nœuds sont identiques **et** qu'on accepte de le rester, ou si on a besoin d'imbriquer (nos nœuds `hvNN`, qui ne migrent pas).

**3. Trunk vers une VM.** Côté hôte : la carte de la VM est branchée sur un pont **VLAN-aware**, **sans** étiquette (`tag`), et la liste des VLAN autorisés est donnée (`trunks=…`) ; le pont transmet alors les trames étiquetées telles quelles. Côté invité, c'est lui qui étiquette (sous-interfaces VLAN, ou pont VLAN-aware s'il est lui-même hyperviseur). Le filtrage MAC (`macfilter` du pare-feu de Proxmox VE) n'autorise en sortie de la carte que les trames dont l'adresse source est **celle de la carte**. Un hyperviseur imbriqué relaie les trames de ses invités, qui ont **leurs** adresses MAC : toutes seraient jetées. Les VMs hébergées ne joindraient rien, alors que l'hyperviseur, lui, fonctionne : panne déroutante.

**Réponses argumentées — cluster et quorum**

**4. Corosync et pmxcfs.** Corosync assure la **communication de groupe** : qui est membre, dans quel ordre les messages sont délivrés à tous, et le calcul du quorum (*votequorum*). pmxcfs (`pve-cluster`) est le système de fichiers `/etc/pve` : une base SQLite (`/var/lib/pve-cluster/config.db`) sur chaque nœud, dont chaque modification est diffusée par Corosync à tous les nœuds et appliquée dans le même ordre ; `/etc/pve` en est la vue FUSE. La configuration de la VM 101 est dans `/etc/pve/nodes/<nœud-porteur>/qemu-server/101.conf` ; elle est **identique** sur tous les nœuds (ils ont tous la base), mais `qm` sur un autre nœud refuse d'agir sur une VM qui n'est pas « à lui » (l'API, elle, transmet la requête au bon nœud).

**5. Latence, pas débit.** Corosync échange de petits messages (jeton, battements) avec des délais courts : si un nœud ne répond pas dans le délai du jeton (de l'ordre de la seconde, `token`), il est déclaré absent et exclu. Il lui faut donc peu de bande passante mais une **latence stable**. Sur un lien saturé (réplication Ceph après une panne, migration de 30 Go), les files d'attente des commutateurs et des cartes allongent la latence : Corosync rate des jetons, exclut des nœuds, le quorum oscille, et avec la HA des nœuds peuvent s'auto-isoler (*fencing*) alors que rien n'est en panne. C'est la cause classique de « reboot mystérieux de tout un cluster pendant une reconstruction Ceph ».

**6. Quorum.** La partition qui détient la majorité stricte des votes attendus (`floor(N/2) + 1`) a le quorum et peut agir. 3 nœuds : quorum 2, on peut en perdre **1**. 4 nœuds : quorum 3, on peut en perdre **1**. 5 nœuds : quorum 3, on peut en perdre **2**. Un nombre pair n'apporte rien face aux pannes par rapport au nombre impair inférieur, et il ajoute le risque de la coupure en deux moitiés égales (2/2), où **personne** n'a la majorité. D'où les nombres impairs, ou un vote externe pour les nombres pairs.

**7. Réponse B.** Le survivant n'a plus qu'1 vote sur 2 attendus : il perd le quorum. Ses VMs **continuent** (rien ne les arrête : sans HA, aucun *fencing* n'est armé), mais pmxcfs passe `/etc/pve` en **lecture seule** : impossible de démarrer, créer, modifier une VM, ni de changer un stockage. A est faux (c'est le piège d'InfoGér : « il marche » tant qu'on ne touche à rien). C : seul un nœud qui a des ressources HA actives s'isole lui-même (watchdog) ; ici, rien ne redémarre. D : sans quorum, il ne peut rien reprendre, et le nœud arrêté n'avait de toute façon plus ses VMs en marche.

**8. Split-brain.** Deux parties d'un cluster isolées l'une de l'autre se croient chacune légitimes et agissent en même temps. Scénario : `hv01` et `hv02` partagent un pool Ceph ; le lien entre eux tombe, mais chacun joint encore Ceph. Si chacun se croyait seul survivant, chacun redémarrerait la VM HA de l'autre : **deux** QEMU écriraient sur le **même** disque RBD, chacun avec son propre cache de système de fichiers : corruption assurée (journaux ext4 incohérents, base de données détruite). L'empêchent : le **quorum** (seule la partition majoritaire agit) et le **fencing** (la partition minoritaire s'arrête d'elle-même avant que l'autre ne reprenne ses VMs).

**9. QDevice.** Un vote supplémentaire, fourni par un démon externe (`corosync-qnetd`) auquel chaque nœud se connecte (`corosync-qdevice`). Il ne fait tourner aucune VM et ne stocke rien : il tranche. S'il tournait sur l'un des nœuds, la perte de ce nœud emporterait **deux** votes (le nœud et l'arbitre) : on retomberait exactement dans le problème. Dans une VM du cluster, c'est pire : l'arbitre dépend de ce qu'il arbitre (la VM migre, s'arrête avec son nœud, ou ne peut pas démarrer sans quorum). Il doit dépendre d'une infrastructure **différente** : un autre site, une autre alimentation, un autre chemin réseau. Pour nous : `pbs01`, à PAR2.

**Réponses argumentées — haute disponibilité**

**10. Réponse B.** Le nœud qui perd le quorum alors qu'il porte des ressources HA cesse de « nourrir » son **watchdog** ; à l'expiration (60 s environ), le watchdog le redémarre brutalement : ses VMs sont mortes, à coup sûr. Les nœuds qui ont le quorum attendent ce délai avant de reprendre les VMs. A est faux : un verrou dans le stockage n'est pas fiable face à un nœud isolé qui continue d'écrire (et tous les stockages n'en ont pas). C : le jeton de Corosync organise la communication, il n'empêche aucune écriture disque. D : une sauvegarde n'a rien à voir avec l'exclusion mutuelle.

**11. Stockage partagé.** Redémarrer une VM ailleurs, c'est lancer un nouveau QEMU sur un autre nœud avec **le même disque** : le disque doit être accessible de ce nœud. Stockage partagé (Ceph, NFS) : oui. Réplication ZFS : oui, avec la copie de la dernière réplication (perte des minutes écoulées). Stockage local seul : le disque est mort avec le nœud (ou injoignable) : la HA ne peut **rien** faire d'utile ; selon les versions et la configuration, la ressource passe en erreur ou reste en attente du retour du nœud.

**12. HA ou tolérance aux pannes.** La tolérance aux pannes (*fault tolerance*, comme vSphere FT) maintient une copie synchronisée qui prend le relais **sans** interruption. La HA de Proxmox VE **redémarre** la VM ailleurs : interruption, redémarrage de l'OS, perte de tout ce qui était en mémoire. Durée : détection de la perte par Corosync (secondes), délai du *fencing* (le watchdog du nœud perdu doit avoir expiré, de l'ordre de la minute), décision du gestionnaire HA, démarrage de la VM et de ses services. Compte **deux à trois minutes** avant que le service ne réponde ; M09-E24 le mesurera.

**Réponses argumentées — stockage et migration**

**13. Migration à chaud.** (1) Une VM « réceptrice » est démarrée en pause sur le nœud cible ; (2) la mémoire est copiée pendant que la VM source continue de tourner ; (3) les pages modifiées entre-temps (*dirty pages*) sont recopiées, en passes successives de plus en plus courtes ; (4) quand ce qui reste à copier tient dans le délai d'interruption visé, la source est mise en pause, le reste de la mémoire et l'état des périphériques sont transférés, la cible reprend. L'interruption est cette dernière phase : quelques dizaines à centaines de millisecondes. Elle dépend du **taux de modification de la mémoire** par rapport au débit du réseau de migration (une base très active peut ne jamais « converger »), et de la latence du réseau. Si les disques sont locaux, leur copie s'ajoute avant (en mode miroir), ce qui allonge la durée totale sans allonger l'interruption.

**14. Réponse B.** Proxmox VE sait migrer à chaud une VM à disques locaux en recopiant les disques pendant que la VM tourne (miroir de blocs de QEMU, NBD) : option `--with-local-disks`, avec un stockage cible présent sur le nœud d'arrivée (même nom, ou `--targetstorage`). C'est plus long (le disque entier traverse le réseau) et cela charge le réseau de migration. A était vrai il y a longtemps et reste une idée reçue. C : aucun déplacement automatique vers un stockage partagé. D : QEMU n'accède pas à un disque distant d'un autre nœud.

**15. Trois façons de survivre.** Ceph partagé : RPO **nul** (chaque écriture acquittée est sur plusieurs nœuds), RTO = temps de la HA (2-3 minutes). Réplication ZFS toutes les 15 minutes : RPO jusqu'à **15 minutes** (plus la durée d'une réplication), RTO = temps de la HA (la VM redémarre sur la copie répliquée). Sauvegarde nocturne restaurée : RPO jusqu'à **24 heures**, RTO = détection + décision + restauration (des dizaines de minutes à des heures selon la taille). Pour une base de données, seul Ceph (ou une réplication applicative) donne un RPO nul ; la sauvegarde reste indispensable pour les erreurs que la réplication propage fidèlement (suppression, rançongiciel).

**16. Ceph hyperconvergé.** Avantages : pas de serveurs de stockage séparés (coût, place, électricité) ; stockage partagé intégré et administré avec le cluster (`pveceph`, interface). Inconvénients : calcul et stockage se disputent CPU, mémoire et réseau (une reconstruction Ceph ralentit les VMs, et inversement) ; la perte d'un nœud fait perdre en même temps des VMs **et** des OSD, et la maintenance d'un nœud concerne les deux. `size 3, min_size 2` sur trois nœuds (une copie par nœud) : un nœud perdu → 2 copies restantes ≥ `min_size` : lectures et écritures continuent, en état dégradé ; deux nœuds perdus → 1 copie < `min_size` : les écritures sont **bloquées** (les VMs se figent sur leurs entrées-sorties), et de toute façon le cluster Proxmox VE n'a plus le quorum.

**Réponses argumentées — réseau, installation, sauvegarde**

**17. Réseaux séparés.** Gestion (interface web, API, SSH : accès restreint, filtré) ; **Corosync**, idéalement deux liens indépendants (latence stable, voir question 5) ; **stockage public** Ceph (clients ↔ OSD : débit, jumbo frames) ; **stockage cluster** Ceph (réplication entre OSD : gros débit en cas de reconstruction, à isoler du reste) ; **migration** (rafales de plusieurs Go/s qui ne doivent gêner ni Corosync ni le stockage) ; **invités** (trafic des applications, VLAN par environnement, jamais au contact des réseaux d'infrastructure) ; éventuellement **sauvegarde** (débit nocturne vers PBS). C'est exactement la carte de nos nœuds : `vmbr0`, `nic1`, `nic2`, `nic3`, `vmbr1` (la migration aura son réseau en M09-E27).

**18. MTU 9000.** Moins de trames pour un même volume : moins d'interruptions et de traitement par paquet, meilleur débit pour les gros transferts (Ceph, migration). Une interface restée à 1500 sur le chemin : les petits paquets passent (`ping` simple, établissement TCP, battements de Ceph), les **gros** sont perdus (ou fragmentés, s'il y a un routeur et que le bit DF n'est pas posé). Symptômes : OSD qui se déclarent mutuellement morts puis revivent (*flapping*), écritures qui se figent, sessions qui se bloquent après la poignée de main. Trompeur, parce que le diagnostic de base (`ping`) dit « tout va bien ». Le bon test : `ping -M do -s 8972` (8972 + 28 octets d'en-têtes = 9000).

**19. Réponse B.** La documentation de `pvecm` est formelle : un nœud qui rejoint ne doit héberger **aucun** invité, et toute sa configuration `/etc/pve` est remplacée par celle du cluster (les VMID pourraient entrer en collision). Procédure : sauvegarder les invités (`vzdump`), rejoindre, restaurer sous de nouveaux VMID. A, C et D décrivent des comportements qui n'existent pas ; D serait dramatique (le nouveau venu écraserait le cluster).

**20. Installation automatisée.** Parce que le jour où on en a besoin, c'est une panne : il faut reconstruire **vite**, **à l'identique** (même partitionnement, mêmes noms d'interfaces, mêmes adresses), sans dépendre de la mémoire de celui qui l'a fait il y a deux ans ; parce que la configuration installée est relue en revue comme du code ; parce que le PRA (M09-E29, F5) l'exige. Reste difficile : les **secrets** (le mot de passe root ne doit pas finir en clair dans un dépôt ou une ISO lisible par tous), la **confiance initiale** (comment vérifier la clé SSH d'hôte d'un système qui vient de naître, comment l'installateur fait-il confiance au serveur de réponses), et la désignation **stable** du matériel (quel disque, quelle carte : les noms changent selon l'ordre de détection).

---

### M09-E02 — Préparer la virtualisation imbriquée

**Solution**

*A. Le processeur et le noyau.*
```
root@pve01:~# lscpu | grep -iE 'model name|virtualization'
Model name:                           Intel(R) Xeon(R) E-2378G CPU @ 2.80GHz
Virtualization:                       VT-x
root@pve01:~# grep -oE '\b(vmx|ept)\b' /proc/cpuinfo | sort | uniq -c
     16 ept
     16 vmx
root@pve01:~# cat /sys/module/kvm_intel/parameters/nested
Y
```
Avec un noyau Linux récent (depuis la version 4.20), l'imbrication est active par défaut pour `kvm_intel` : c'est le cas du noyau de Proxmox VE 9. **EPT** (*Extended Page Tables*) fait traduire par le matériel les adresses physiques de l'invité en adresses physiques de l'hôte, sans que l'hyperviseur maintienne des tables d'ombre (*shadow page tables*). Pour un hyperviseur imbriqué, KVM émule EPT pour le niveau du dessous (« EPT on EPT ») : sans EPT matériel, chaque défaut de page du niveau 2 coûterait plusieurs sorties vers l'hôte, et l'imbrication deviendrait inutilisable en pratique.

Si `nested` valait `N` : fenêtre de maintenance, `echo "options kvm-intel nested=Y" > /etc/modprobe.d/kvm-intel.conf`, arrêt de toutes les VMs (ou redémarrage de `pve01`), `modprobe -r kvm_intel && modprobe kvm_intel`, vérification. Retour : supprimer le fichier, même procédure.

*B. La place.*
```
root@pve01:~# free -g
root@pve01:~# pvesh get /nodes/<NOEUD>/qemu --output-format json \
    | jq -r '.[] | select(.status == "running") | "\(.vmid)\t\(.name)\t\(.maxmem / 1073741824 | floor) Gio"' | sort -n
root@pve01:~# arc_summary -s arc 2>/dev/null | head -n 20     # si local-nvme est un pool ZFS
```
L'ARC de ZFS de `pve01` compte comme « utilisé » dans `free` mais se rend sous pression ; sur Proxmox VE installé avec ZFS, il est plafonné à 10 % de la mémoire par l'installateur (depuis 8.1) : vérifie `/etc/modprobe.d/zfs.conf`. Arrêt de `ceph01-03` : procédure du module 08 (drapeaux `noout`, `norebalance`… posés avant l'arrêt, nœuds arrêtés un par un, vérification), puis :
```
root@pve01:~# for v in 2081 2082 2083; do qm status $v; done
status: stopped
status: stopped
status: stopped
```

*C. La preuve sur une VM jetable.*
```
root@pve01:~# qm clone <VMID-CURRENT> 2099 --name m09-essai --full 0 --pool lab
root@pve01:~# qm set 2099 --cpu host --cores 1 --memory 1024 --net0 virtio,bridge=vsandbox \
    --tags env-m09 --ciuser admin --sshkeys /root/adm01.pub --ipconfig0 ip=dhcp
root@pve01:~# qm start 2099
root@pve01:~# qm guest cmd 2099 network-get-interfaces | jq -r '.[]."ip-addresses"[]? | select(."ip-address-type" == "ipv4") | ."ip-address"'
admin@adm01:~$ ssh admin@10.10.99.1NN 'ls -l /dev/kvm; grep -c vmx /proc/cpuinfo'
crw-rw---- 1 root kvm 10, 232 … /dev/kvm
1
root@pve01:~# qm shutdown 2099 && qm set 2099 --cpu x86-64-v2-AES && qm start 2099
admin@adm01:~$ ssh admin@10.10.99.1NN 'ls -l /dev/kvm; grep -c vmx /proc/cpuinfo'
ls: cannot access '/dev/kvm': No such file or directory
0
root@pve01:~# qm stop 2099 && qm destroy 2099 --purge 1
```
(`/root/adm01.pub` : copie de la clé publique de `adm01` ; avec un clone lié d'une image dorée, cloud-init de l'image fait le reste.) Avec `x86-64-v2-AES`, le CPU virtuel est un modèle générique **sans** VMX : le module `kvm_intel` de l'invité ne se charge pas, `/dev/kvm` n'existe pas. Le changement de type ne s'applique qu'au démarrage d'un **nouveau** processus QEMU (arrêt complet, pas un redémarrage depuis l'invité).

*D. Le réseau, vu d'en dessous.*
```
root@pve01:~# cat /sys/class/net/vmbr1/bridge/vlan_filtering /sys/class/net/vmbr1/mtu
1
9000
root@pve01:~# pvesh get /cluster/sdn/vnets --output-format json \
    | jq -r '.[] | select(.vnet | IN("vmgmt","vcoro","vstopub","vstoclu")) | "\(.vnet)\t\(.zone)\t\(.tag)"'
vcoro   lab     32
vmgmt   lab     10
vstoclu lab     31
vstopub lab     30
```
Réponses du journal :
- carte sur le VNet `vcoro` : c'est **`pve01`** qui pose et retire l'étiquette 32 (le VNet d'une zone VLAN est un pont dont le port vers `vmbr1` est étiqueté) ; le nœud voit un réseau « à plat ». Carte `trunks=99` sur `vmbr1` sans `tag` : le **nœud** étiquette (son propre pont `vmbr1` VLAN-aware), `pve01` ne fait que laisser passer les VLAN autorisés ;
- limiter au VLAN 99 : un invité imbriqué mal configuré (ou malveillant) qui étiquetterait 10 ou 20 se retrouverait sinon dans MGMT ou INFRA, **derrière** la bordure, sans aucun filtrage ; avec `trunks=99`, `pve01` jette tout autre VLAN. Défense en profondeur, et une garantie que le module ne déborde pas du bac à sable ;
- le filtrage MAC du pare-feu de Proxmox VE (option `macfilter`, active par défaut dès que le pare-feu de la VM l'est) ne laisserait sortir de `net4` que les trames dont la source est la MAC de `net4` : les invités imbriqués n'auraient **aucun** réseau. On désactive le pare-feu de `pve01` sur les cinq cartes des nœuds (`firewall = false` dans OpenTofu) : le filtrage des invités imbriqués se fera dans le cluster (M09-E26). M09-E07 en fait l'expérience.

*E. Le droit d'OpenTofu.*
```
root@pve01:~# pveum acl list --output-format json | jq -r '.[] | select(.ugid | startswith("wb-tofu@pve")) | "\(.path)\t\(.ugid)\t\(.roleid)"'
root@pve01:~# pveum acl modify /sdn/zones/localnetwork/vmbr1 --tokens 'wb-tofu@pve!tofu' --roles PVESDNUser
root@pve01:~# pveum acl modify /sdn/zones/localnetwork/vmbr1 --users wb-tofu@pve --roles PVESDNUser
```
Un jeton à **privilèges séparés** (M05-E03) n'a que l'intersection de ses droits et de ceux de son utilisateur : il faut le droit aux deux. `ssd-lab` et `hdd-bulk` sont déjà accessibles (`PVEDatastoreUser`, posés au module 05 pour `hdd-bulk` et au module 08 pour `ssd-lab`) : sinon, même geste sur `/storage/<stockage>`. Registre des accès : ligne « M09-E02 : `wb-tofu@pve` + jeton, `PVESDNUser` sur `/sdn/zones/localnetwork/vmbr1` ».

*F. L'ISO, vérifiée.* Script complet : [`images/outils/deposer-iso.sh`](fichiers/M09-E02/images/outils/deposer-iso.sh). La famille `proxmox-ve` :
- cherche le trousseau APT de Proxmox présent sur `pve01` (`/usr/share/keyrings/proxmox-archive-keyring.gpg` en 9.x ; fichiers de `trusted.gpg.d` en 8.x) : **aucune** clé n'est téléchargée, la confiance vient de l'installation de `pve01` elle-même ;
- télécharge l'ISO en `….iso.partiel`, puis vérifie la signature détachée avec `gpgv --status-fd 1` et exige une ligne `VALIDSIG` portant l'une des deux empreintes attendues ;
- renomme seulement alors ; une ISO déjà présente est revérifiée, jamais retéléchargée.
```
admin@adm01:~/src/images$ ssh pve01 'bash -s' -- proxmox-ve < outils/deposer-iso.sh
== Trousseau : /usr/share/keyrings/proxmox-archive-keyring.gpg
== Téléchargement de proxmox-ve_9.2-1.iso vers /mnt/pve/hdd-bulk/template/iso
signature valide (24B30F06ECC1836A4E5EFECBA7BCD1420BFE778E)

ISO vérifiée et déposée : hdd-bulk:iso/proxmox-ve_9.2-1.iso
```
Puis l'outil de préparation :
```
root@pve01:~# apt update && apt install --simulate proxmox-auto-install-assistant xorriso
root@pve01:~# apt install proxmox-auto-install-assistant xorriso
root@pve01:~# proxmox-auto-install-assistant --version
root@pve01:~# proxmox-auto-install-assistant prepare-iso --help
```
La simulation ne doit lister que ces deux paquets et leurs bibliothèques (`libisoburn1`, `libburn4`, `libisofs6`…), aucune mise à jour de paquet Proxmox : sinon, c'est que `pve01` a des mises à jour en attente, qui se font dans leur propre fenêtre.

**Explications**

- **Pourquoi une VM jetable plutôt que de croire le paramètre.** `nested=Y` ne dit rien du type de CPU des VMs, ni d'un éventuel masquage par le BIOS (VT-x désactivé, mais `vmx` visible dans de rares cas de microcode). Le test de bout en bout (un `/dev/kvm` dans une VM) prouve la chaîne entière. C'est le même raisonnement que pour le MTU : on vérifie le chemin, pas la configuration.
- **Signature plutôt que somme.** Une somme SHA-256 téléchargée du même serveur que l'ISO ne protège que d'un téléchargement corrompu. La signature protège d'un serveur (ou d'un miroir) compromis : il faudrait aussi voler la clé de Proxmox. Et la clé de vérification vient d'un canal **déjà** de confiance (le trousseau installé avec `pve01`), pas du même site.
- **Les droits sur `vmbr1`.** Proxmox VE 8 a fait entrer les ponts classiques dans le modèle de droits du SDN (zone implicite `localnetwork`) : un compte peut avoir le droit d'utiliser `vmsandbox` sans avoir celui de brancher une VM directement sur le pont qui porte **tous** les VLAN du lab. C'est voulu : `vmbr1` sans étiquette ni *trunk*, c'est tout le lab.

**Alternatives**

- **Un type de CPU nommé avec `+vmx`** (par exemple un modèle personnalisé dans `/etc/pve/virtual-guest/cpu-models.conf`) plutôt que `host` : les nœuds seraient migrables entre hôtes différents. Inutile ici (un seul hôte), utile dans un lab réparti.
- **Préparer les ISO sur `adm01`** plutôt que sur `pve01` : il faudrait ajouter le dépôt Proxmox à une Debian ordinaire (clé, épinglage pour ne rien prendre d'autre), puis copier 1,5 Go par nœud vers `hdd-bulk`. Plus propre pour `pve01`, plus lourd ; `pve01` a déjà le dépôt et le stockage.
- **Vérifier par la somme publiée sur la page de téléchargement** (affichée sur le site) : mieux que rien, moins bien que la signature.

**Pièges classiques**

- Changer le type de CPU d'une VM et ne voir aucun effet : il faut un arrêt **complet** de la VM, pas un `reboot` dans l'invité.
- Activer `nested` sur un `pve01` en production « à chaud » : `modprobe -r kvm_intel` échoue tant qu'une VM tourne (module utilisé), et si on force en arrêtant tout, c'est une coupure du socle.
- Croire que `vmx` dans `/proc/cpuinfo` de l'hôte suffit : sans `nested=Y` côté hôte et sans type `host` côté VM, rien.
- Oublier le jeton (et pas seulement l'utilisateur) dans l'ACL : la création des nœuds échoue en E03 sur un message de droit qui cite `SDN.Use`.
- `gpg --verify` avec un trousseau personnel qui contient d'anciennes clés « de confiance » : une signature d'une clé **inattendue** passerait. D'où `gpgv` avec un trousseau précis et l'empreinte exigée.

**En production chez MédiSphère**

Les serveurs physiques du futur cluster ne posent pas la question de l'imbrication, mais celle du **modèle de CPU commun** se pose dès l'achat : même génération de processeurs dans un cluster, ou un type de CPU nommé fixé à la plus ancienne. Les ISO d'installation sont rangées dans le dépôt d'artefacts avec leur signature vérifiée et leur empreinte, et la procédure de vérification est dans le runbook de reconstruction (RB-091). L'ajout d'un droit sur un hyperviseur passe par une MR sur la configuration des droits (M09-E17 la met en code pour le cluster).

---

### M09-E03 — Installer Proxmox VE sans clavier

**Solution**

*A. Comprendre l'installateur.* Les trois modes :
- **`iso`** : le fichier de réponse est **dans** l'ISO ; aucun réseau nécessaire pour l'obtenir ; une ISO par configuration, donc par nœud quand chaque nœud a son adresse.
- **`partition`** : l'installateur cherche le fichier sur une partition étiquetée `proxmox-ais` (clé USB, disque) ; une ISO générique, un petit support par nœud ; en VM, un disque supplémentaire à fabriquer et à brancher.
- **`http`** : l'installateur obtient le réseau par **DHCP**, trouve l'URL du serveur de réponses (dans l'ISO, en option DHCP 250, ou dans un enregistrement TXT `proxmox-auto-installer.<domaine>`), envoie l'identité de la machine (MAC, numéros de série) et reçoit **son** fichier ; une seule ISO pour tout le parc.

Le mode `http` est le plus élégant, mais il exige du DHCP sur le réseau d'installation : notre MGMT (VLAN 10) n'en a pas, et en ajouter (sous-réseau Kea, relais, réservations) toucherait au socle pour un besoin ponctuel. Le mode `iso` ne demande rien au réseau : l'adresse statique est dans la réponse. Une ISO préparée contient le fichier de réponse **en clair** : l'empreinte du mot de passe root, la clé publique de `adm01`. Sur `pve01`, elle est lisible par root et par qui a le droit `Datastore.Audit`/`AllocateSpace` sur `hdd-bulk` (téléchargement par l'API) : c'est pourquoi on n'y met jamais le mot de passe lui-même, et que l'empreinte est en SHA-512 avec sel.

*B. Les secrets.*
```
admin@adm01:~$ (umask 077; openssl rand -base64 24 | tr -d '\n' > ~/.config/workbook/hv-root.pass)
admin@adm01:~$ stat -c '%a %n' ~/.config/workbook/hv-root.pass
600 /home/admin/.config/workbook/hv-root.pass
```
Copie de la valeur dans `vault_hv_root_mot_de_passe` ([modèle](fichiers/M09-E03/ansible/inventories/lab/group_vars/hv_par1/vault-critique.yml.exemple)) par `ansible-vault edit --vault-id critique@…` (la valeur ne passe pas par la ligne de commande). Registre : « mot de passe root des nœuds `hv-par1` : Vault critique + `hv-root.pass` sur `adm01` ; détenteurs : équipe Plateforme ; rotation : à chaque reconstruction du cluster ».

*C. Le fichier de réponse et les ISO.* Fichiers : [`reponse.toml.modele`](fichiers/M09-E03/infra/envs/hv/installation/reponse.toml.modele) et [`preparer-iso.sh`](fichiers/M09-E03/infra/envs/hv/installation/preparer-iso.sh). Points saillants du modèle :
```toml
[network]
source = "from-answer"
cidr = "@@IP_MGMT@@/24"
gateway = "10.10.10.1"
dns = "10.10.20.10"
filter.ID_NET_NAME_MAC = "*@@MAC0_COMPACTE@@"

[network.interface-name-pinning]
enabled = true

[network.interface-name-pinning.mapping]
"@@MAC0@@" = "nic0"
# … nic1 à nic4

[disk-setup]
filesystem = "ext4"
filter.ID_SERIAL = "*@@NOEUD@@-systeme"
lvm.swapsize = 2
lvm.maxroot = 12
lvm.minfree = 2
```
Le script lit `noeuds.auto.tfvars.json` avec `jq`, calcule les MAC par `printf '02:4d:53:09:%02x:%02x'` (même formule que `locals.tf`), l'empreinte par `openssl passwd -6 -stdin` (le mot de passe arrive par un tube depuis le fichier), remplit le modèle dans un dossier `mktemp -d` en 700, refuse un fichier où il reste un marqueur, puis envoie le fichier à `pve01` **sur l'entrée standard** de SSH : sur `pve01`, il est écrit dans un dossier temporaire 700, validé, utilisé, effacé par un `trap`. L'ISO est écrite sous un nom `.partiel.iso`, renommée seulement si `prepare-iso` a réussi.
```
admin@adm01:~/src/infra/envs/hv$ installation/preparer-iso.sh hv01 hv02
== hv01
The file was parsed successfully, no syntax errors found!
…
3f9c…  /mnt/pve/hdd-bulk/template/iso/pve92-auto-hv01.iso
ISO prête : hdd-bulk:iso/pve92-auto-hv01.iso
== hv02
…
root@pve01:~# proxmox-auto-install-assistant inspect-iso /mnt/pve/hdd-bulk/template/iso/pve92-auto-hv01.iso
```
`inspect-iso` affiche le mode de récupération et le fichier de réponse intégré, en **masquant** les champs sensibles (empreinte du mot de passe, jetons) sauf avec `--show-sensitive` : l'outil reconnaît lui-même que ces champs ne doivent pas s'afficher dans un terminal partagé ou un journal.

*D. Les VMs.* Étiquette NetBox : [extrait](fichiers/M09-E03/outils/netbox/modele-medisphere-extrait.yml), puis le script de modélisation de M06-E05 (deux passages : le second ne change rien). Configuration complète : [`infra/envs/hv/`](fichiers/M09-E03/infra/envs/hv/) — `versions.tf` (fournisseurs, backend `envs/hv/terraform.tfstate`), `chiffrement.tf` (copie de celui du socle), `providers.tf`, `variables.tf` (validations du plan d'adressage, du VLAN du *trunk*), `locals.tf` (cartes, MAC, disques), `main.tf` (les VMs), `netbox.tf`, `dns.tf`, `outputs.tf`, `terraform.tfvars`, `noeuds.auto.tfvars.json`. Le cœur de `main.tf` :
```hcl
  memory {
    dedicated = 12288
    floating  = 0
  }
  cpu {
    type  = "host"
    cores = 4
  }
  cdrom {
    interface = "ide2"
    file_id   = "${var.stockage_iso}:iso/${var.prefixe_iso}-${each.key}.iso"
  }
  boot_order = ["scsi0", "ide2"]

  dynamic "disk" {
    for_each = local.disques
    content {
      interface    = disk.value.interface
      datastore_id = disk.value.stockage
      size         = disk.value.taille
      serial       = "${each.key}-${disk.value.role}"
      # … raw, iothread, discard, ssd
    }
  }

  dynamic "network_device" {
    for_each = local.cartes
    content {
      bridge      = network_device.value.pont
      mac_address = local.macs[each.key][network_device.key]
      mtu         = network_device.value.mtu
      trunks      = network_device.value.trunks
      firewall    = false
    }
  }
```
```
admin@adm01:~/src/infra$ . outils/charger-acces.sh
admin@adm01:~/src/infra$ set -a; . ~/.config/workbook/netbox-tofu.env; . ~/.config/workbook/powerdns-api.env; set +a
admin@adm01:~/src/infra$ cd envs/hv && tofu init && tofu plan -out=/tmp/hv.plan
admin@adm01:~/src/infra/envs/hv$ tofu apply /tmp/hv.plan && rm /tmp/hv.plan
```
Le plan crée, par nœud : la VM, la fiche NetBox (VM, 5 interfaces, 4 adresses, IP primaire), 2 enregistrements DNS. Sur la console noVNC de `hv01` : menu de démarrage de l'ISO, entrée « Automated Installation » choisie d'elle-même après le délai, journal de l'installateur, redémarrage. L'installation dure 5 à 10 minutes selon `local-nvme`. Au redémarrage, `scsi0` est désormais amorçable : la VM démarre sur Proxmox VE, l'ISO reste montée mais n'est plus lue (elle resservira pour une réinstallation, M09-E29 : on effacera alors le disque, ou on changera l'ordre de démarrage).

*E. Le premier contact.* Alias : [extrait de `~/.ssh/config`](fichiers/M09-E03/adm01/ssh-config-hv.extrait). Sur la console de `hv01` (login `root`, mot de passe de `hv-root.pass`) :
```
root@hv01:~# ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
256 SHA256:Xq3…k8 root@hv01 (ED25519)
admin@adm01:~$ ssh-keyscan -t ed25519 10.10.10.51 2>/dev/null | ssh-keygen -lf -
256 SHA256:Xq3…k8 10.10.10.51 (ED25519)
admin@adm01:~$ ssh hv01 true      # accepte, l'empreinte a été comparée
```
Au prochain passage d'Ansible, `ssh_ca_hote` fait signer la clé d'hôte par la CA SSH de `ca01` : la ligne `@cert-authority` (motif `10.10.*`) de `~/.ssh/known_hosts` suffit, et l'entrée brute peut être retirée (`ssh-keygen -R 10.10.10.51`).

*F. Le rôle `pve_noeud`.* Fichiers : [`roles/pve_noeud/`](fichiers/M09-E03/ansible/roles/pve_noeud/), [`inventories/lab/hv.yml`](fichiers/M09-E03/ansible/inventories/lab/hv.yml), [`group_vars/hv_par1/pve_noeud.yml`](fichiers/M09-E03/ansible/inventories/lab/group_vars/hv_par1/pve_noeud.yml), [`playbooks/hv.yml`](fichiers/M09-E03/ansible/playbooks/hv.yml). Le rôle en cinq fichiers de tâches :
- `controles.yml` : assertions d'entrée (numéro ↔ nom, `pveversion`, `getent hosts`, MAC des cinq cartes via les faits `ansible_facts['nicK']`, `/dev/kvm`) ;
- `depots.yml` : lecture de `pve-enterprise.sources` et `ceph.sources`, suppression **seulement** s'ils visent `enterprise.proxmox.com`, puis `deb822_repository` (`pve-no-subscription`, trousseau `proxmox-archive-keyring`) ;
- `temps.yml` : `pvesh get /nodes/<nœud>/dns`, `pvesh set` seulement si les résolveurs ou le domaine diffèrent, `chrony.conf` validé par `chronyd -p`, attente de synchronisation ;
- `reseau.yml` : le nouveau fichier est rendu à côté (`interfaces.ansible`, syntaxe vérifiée par ifupdown2), comparé ; s'il diffère : copie de référence, minuterie `systemd-run --on-active=120` qui remettrait l'ancien fichier, mise en place, `ifreload -a`, `wait_for_connection`, contrôle de la passerelle et des adresses, puis arrêt de la minuterie ; enfin un `ping -M do -s 8972` vers 10.10.30.1 ;
- `systeme.yml` : `zfs_arc_max` (fichier de `modprobe.d` et valeur à chaud si le module est chargé), getty sur `ttyS0`, fragment `sshd` (validation complète `sshd -t` en gestionnaire avant le rechargement), fragment cloud-init `medisphere-agent.yaml`.
```
admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/lab/netbox.yml -i inventories/lab/hv.yml \
    playbooks/hv.yml --limit hv01 --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/lab/netbox.yml -i inventories/lab/hv.yml playbooks/hv.yml
…
PLAY RECAP ***
hv01 : ok=… changed=… failed=0
hv02 : ok=… changed=… failed=0
admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/lab/netbox.yml -i inventories/lab/hv.yml playbooks/hv.yml
hv01 : ok=… changed=0 …
hv02 : ok=… changed=0 …
root@pve01:~# qm terminal 2091
hv01 login:
```
En `--check`, la tâche `ifreload -a` n'est pas jouée (module `command`) : le diff montre le fichier qui **serait** posé, c'est ce qu'on relit. Pourquoi les résolveurs par l'API locale : Proxmox VE gère lui-même `/etc/resolv.conf` (onglet DNS du nœud, `pvesh /nodes/<nœud>/dns`) ; écrire le fichier directement fonctionnerait jusqu'au prochain changement fait par l'interface, et l'interface afficherait autre chose que la réalité. Pourquoi pas de Molecule : voir [`README.md`](fichiers/M09-E03/ansible/roles/pve_noeud/README.md) du rôle — l'instance de test serait elle-même un nœud Proxmox VE imbriqué de 12 Go ; le rôle est éprouvé par `ansible-lint`, `--check --diff`, le second passage et la reconstruction complète de M09-E46.

Vérification sur un nœud :
```
root@hv01:~# ip -br link | grep -E '^(nic|vmbr)'
nic0   UP   02:4d:53:09:01:00 <BROADCAST,MULTICAST,UP,LOWER_UP>
nic1   UP   02:4d:53:09:01:01 …
…
vmbr1  UP   02:4d:53:09:01:04 …
root@hv01:~# ping -c1 -M do -s 8972 10.10.31.72
root@hv01:~# chronyc -n sources
^* 10.10.10.1   …
root@hv01:~# ssh-keygen -L -f /etc/ssh/ssh_host_ed25519_key-cert.pub | sed -n '/Principals/,/Critical/p'
```

11. Inventaire du socle : section « Environnements de module », `hv01`/`hv02` (VMID, adresses, état `hv`, détruits en fin de module). La matrice des flux ne change pas : `adm01` et les nœuds sont dans le même VLAN (MGMT), les nœuds entre eux aussi (VLAN 10, 30, 31, 32) ; tout ce qu'ils joignent hors de leur VLAN (DNS, NTP, Internet) est déjà ouvert pour MGMT.

**Explications**

- **Une seule source pour deux outils.** Le fichier `noeuds.auto.tfvars.json` est lu automatiquement par OpenTofu (suffixe `.auto.tfvars.json`) **et** par le script de préparation des ISO (`jq`). Si l'adresse d'un nœud était écrite deux fois, elle finirait par diverger : un nœud installé avec une adresse, déclaré dans NetBox avec une autre. Le format JSON est choisi pour cette raison : HCL ne se lit pas proprement en shell.
- **Pourquoi fixer MAC, noms et séries.** Tout ce qui suit dépend d'identifiants stables : la configuration réseau (`nic1` = Corosync), le fichier de réponse (quelle carte reçoit l'adresse, quel disque reçoit le système), Ceph (quels disques deviennent des OSD), ZFS. Sans MAC fixe, chaque recréation de VM changerait les adresses (et, sans épinglage, l'ordre de détection pourrait permuter `nic1` et `nic2`). Les MAC choisies ont le bit « administrée localement » (`02:`) : elles ne peuvent entrer en collision avec aucun fabricant, ni avec le préfixe `BC:24:11` que Proxmox VE attribue automatiquement.
- **Pas de ballon, pas d'agent.** Un hyperviseur gère sa mémoire comme s'il était seul : si `pve01` lui en reprenait par le ballon, ce sont ses invités et ses OSD qui en pâtiraient, sans qu'il le sache. L'agent QEMU n'est pas installé dans Proxmox VE (et un nœud n'a pas à être piloté par `pve01`) : le déclarer ferait attendre le fournisseur jusqu'à son délai.
- **Le retour automatique du réseau.** `ifreload -a` applique les différences sans couper ce qui n'a pas changé ; si `vmbr0` est intact, la session SSH survit. Mais une erreur (mauvaise passerelle, mauvaise carte) peut rendre le nœud injoignable : la minuterie transitoire, indépendante de la session, remet l'ancienne configuration sans intervention. C'est la même idée que le filet du rôle `pare_feu` (M04-E17).
- **Le chemin des noms.** NetBox reçoit l'intention (la VM, ses interfaces, ses adresses), PowerDNS les noms (module `enregistrement-dns`, marqués « gérés par OpenTofu », que la synchronisation de M06-E15 ne touche pas). La synchronisation Proxmox → NetBox de M06-E11 écrira le VMID dans le champ personnalisé, d'où le `ignore_changes`.

**Alternatives**

- **Mode `http`** avec un petit serveur de réponses sur `adm01` : une ISO pour tous, la réponse choisie d'après la MAC envoyée par l'installateur. Prérequis : DHCP sur le réseau d'installation (un sous-réseau Kea pour le VLAN 10, ou une installation sur le VLAN 99 puis bascule), et un certificat (`--cert-fingerprint`) pour que l'installateur fasse confiance au serveur. Le module 11 (provisioning) pose exactement ces briques.
- **Mode `partition`** : un petit disque virtuel étiqueté `proxmox-ais` par nœud, l'ISO générique : élégant, mais il faut fabriquer et déposer une image de disque par nœud.
- **Installer Proxmox VE sur une Debian 13** (paquets, sans l'ISO) : possible et documenté, mais on perd le partitionnement LVM-thin standard et l'installation de référence ; non retenu.
- **Créer les VMs par un clone d'un « template Proxmox VE »** : rapide, mais tous les nœuds auraient la même identité (clés SSH, `machine-id`, certificats) à régénérer, et l'installation ne serait plus testée.

**Pièges classiques**

- Écrire `root_password` ou `disk_setup` (forme *snake_case* des tutoriels de 2024) : avertissement en 9.x, et un jour une erreur. `validate-answer` le signale.
- Laisser `mtu = 1` (« MTU du pont ») sur MGMT : `vmbr1` étant à 9000 depuis M07-E15, le nœud passerait sa carte d'administration à 9000 derrière une passerelle à 1500 ; tout fonctionne en apparence, puis les transferts SSH ou HTTPS volumineux se bloquent.
- Activer le pare-feu sur `net4` (valeur par défaut de l'interface de Proxmox VE à la création d'une carte) : les invités imbriqués n'ont pas de réseau (M09-E07).
- Un `for_each` sur une **liste** de nœuds : ajouter `hv03` au milieu renumérote tout et recrée des nœuds. La clé doit être le nom.
- Gérer `/root/.ssh/authorized_keys` avec un module qui remplace le fichier : après la création du cluster, c'est un lien vers `/etc/pve/priv/authorized_keys`, et on casserait l'accès de **tous** les nœuds entre eux.
- Appliquer le rôle à tous les nœuds en même temps (sans `serial: 1`) : une erreur dans le modèle réseau isole tout le cluster d'un coup.
- Oublier la ligne `source /etc/network/interfaces.d/*` : le SDN du cluster (M09-E16) écrit ses ponts dans `interfaces.d/sdn`, qui ne seraient jamais lus.

**En production chez MédiSphère**

Sur du matériel, les MAC ne se choisissent pas : on relève celles des cartes à la livraison (NetBox, M11), et l'épinglage des noms par MAC devient indispensable (une carte remplacée change de nom sans lui). L'installation passe en mode `http` depuis le serveur de provisioning (M11), avec un jeton d'authentification (`--answer-auth-token`) et un *webhook* de fin d'installation qui enregistre les clés d'hôte dans l'inventaire : plus aucune empreinte à vérifier à la main. Le mot de passe root n'est connu que du coffre (bris de glace), les accès quotidiens passent par des comptes nominatifs avec 2FA (M09-E26) et, pour SSH, par des certificats d'utilisateur (M06-E20).

---

### M09-E04 — Former le cluster et ses liens Corosync

**Solution**

*A. Avant de créer.*
```
root@hv01:~# chronyc tracking | grep -E 'Reference|System time'
root@hv01:~# getent hosts hv01 hv02
10.10.10.51     hv01.par1.medisphere.internal hv01
root@hv01:~# ping -c 2 10.10.32.52
root@hv02:~# qm list; pct list        # rien
```
`getent hosts hv02` sur `hv01` passe par le DNS (enregistrement posé par OpenTofu en E03) : l'installateur n'a écrit dans `/etc/hosts` que le nœud lui-même.

*B. Créer et joindre.*
```
root@hv01:~# pvecm create hv-par1 --link0 10.10.32.51 --link1 10.10.10.51
root@hv01:~# cat /etc/pve/corosync.conf
logging {
  debug: off
  to_syslog: yes
}

nodelist {
  node {
    name: hv01
    nodeid: 1
    quorum_votes: 1
    ring0_addr: 10.10.32.51
    ring1_addr: 10.10.10.51
  }
}

quorum {
  provider: corosync_votequorum
}

totem {
  cluster_name: hv-par1
  config_version: 1
  interface {
    linknumber: 0
  }
  interface {
    linknumber: 1
  }
  ip_version: ipv4-6
  link_mode: passive
  secauth: on
  version: 2
}
```
`link_mode: passive` : un seul lien porte le trafic à la fois, celui de plus haute priorité qui fonctionne. `secauth: on` : messages chiffrés et authentifiés avec la clé `/etc/corosync/authkey` (copiée dans `/etc/pve/` pour être distribuée aux nœuds qui rejoignent). `config_version` augmente à chaque modification : un nœud refuse une configuration plus ancienne que la sienne.
```
root@hv01:~# pvenode cert info --output-format json | jq -r '.[] | select(.filename == "pve-ssl.pem") | .fingerprint'
6B:1E:…:A2
root@hv02:~# pvecm add 10.10.10.51 --link0 10.10.32.52 --link1 10.10.10.52
Please enter superuser (root) password for '10.10.10.51': ********
Establishing API connection with host '10.10.10.51'
The authenticity of host '10.10.10.51' can't be established.
X509 SHA256 key fingerprint is 6B:1E:…:A2.
Are you sure you want to continue connecting (yes/no)? yes
Login succeeded.
…
successfully added node 'hv02' to cluster.
```
Le mot de passe demandé est celui de **`hv01`** : `hv02` s'authentifie auprès de l'API du cluster existant pour y être admis (il demande à entrer) ; le cluster lui renvoie sa configuration, sa clé Corosync et un nouveau certificat signé par l'autorité **du cluster**.

4. Observation :
```
root@hv02:~# pvecm status
Cluster information
-------------------
Name:             hv-par1
Config Version:   2
Transport:        knet
Secure auth:      on

Quorum information
------------------
Date:             …
Quorum provider:  corosync_votequorum
Nodes:            2
Node ID:          0x00000002
Ring ID:          1.9
Quorate:          Yes

Votequorum information
----------------------
Expected votes:   2
Highest expected: 2
Total votes:      2
Quorum:           2
Flags:            Quorate

Membership information
----------------------
    Nodeid      Votes Name
0x00000001          1 10.10.32.51
0x00000002          1 10.10.32.52 (local)
root@hv02:~# corosync-cfgtool -s
Local node ID 2, transport knet
LINK ID 0 udp
        addr    = 10.10.32.52
        status:
                nodeid:          1:     connected
                nodeid:          2:     localhost
LINK ID 1 udp
        addr    = 10.10.10.52
        status:
                nodeid:          1:     connected
                nodeid:          2:     localhost
```
Le certificat de l'interface de `hv02` a été **remplacé** : `/etc/pve/nodes/hv02/pve-ssl.pem` est désormais signé par `/etc/pve/pve-root-ca.pem`, l'autorité créée par `pvecm create` sur `hv01` (l'ancienne autorité propre à `hv02` a disparu avec son ancien `/etc/pve`). `/root/.ssh/authorized_keys` est devenu un lien vers `/etc/pve/priv/authorized_keys`, qui contient les clés de root des deux nœuds **et** la clé de `adm01` (fusionnée depuis le fichier de chaque nœud) : c'est ce qui permet aux nœuds de migrer et répliquer entre eux par SSH.

5. Ancre du cluster :
```
admin@adm01:~$ scp hv01:/etc/pve/pve-root-ca.pem ~/.config/workbook/hv-par1-root-ca.pem
admin@adm01:~$ chmod 644 ~/.config/workbook/hv-par1-root-ca.pem
admin@adm01:~$ openssl x509 -in ~/.config/workbook/hv-par1-root-ca.pem -noout -subject -enddate
admin@adm01:~$ curl -sS -o /dev/null -w '%{http_code}\n' --cacert ~/.config/workbook/hv-par1-root-ca.pem \
    https://hv02.par1.medisphere.internal:8006/api2/json/version
401
```
`401` : la poignée de main TLS a réussi avec la seule ancre du cluster (sinon `curl` sortirait en erreur 60), et l'API refuse une requête sans jeton. Le certificat d'un nœud porte son nom court, son FQDN et ses adresses : le nom `hv02.par1.medisphere.internal` correspond.

*C. Couper un lien.* Après les commandes de l'énoncé, sur `hv01` :
```
root@hv01:~# journalctl -u corosync -f
… [KNET  ] link: host: 2 link: 0 is down
… [KNET  ] host: host: 2 (passive) best link: 1 (pri: 1)
root@hv01:~# corosync-cfgtool -s
LINK ID 0 udp
        addr    = 10.10.32.51
        status:
                nodeid:          1:     localhost
                nodeid:          2:     disconnected
LINK ID 1 udp
        addr    = 10.10.10.51
        status:
                nodeid:          1:     localhost
                nodeid:          2:     connected
root@hv01:~# pvecm status | grep -E 'Quorate|Total votes'
Quorate:          Yes
Total votes:      2
```
Détection en quelques secondes (délai de *ping* de knet : `knet_ping_interval`, `knet_ping_timeout`), bascule sur le lien 1 sans perte d'appartenance ni de quorum : le cluster ne remarque rien. Après `nft delete table inet m09_essai`, le lien 0 revient (`link: 0 is up`) et redevient le meilleur : sans priorités explicites, le lien de **plus petit numéro** a la plus haute priorité (documentation de `pvecm`, « Corosync Redundancy »). Pour inverser, on aurait donné `priority=` à chaque lien, la valeur la plus haute gagnant.

*D. Perdre un nœud.*
```
root@pve01:~# qm shutdown 2092
root@hv01:~# pvecm status | sed -n '/Votequorum/,/Flags/p'
Expected votes:   2
Highest expected: 2
Total votes:      1
Quorum:           2 Activity blocked
Flags:
root@hv01:~# touch /etc/pve/essai
touch: cannot touch '/etc/pve/essai': Permission denied
```
Dans l'interface, toute modification échoue (« cluster not ready - no quorum? »). C'est **voulu** : `hv01` ne peut pas distinguer « `hv02` est arrêté » de « `hv02` tourne mais je ne le vois plus ». Dans le second cas, si chacun modifiait `/etc/pve` (par exemple pour démarrer la même VM), les deux bases divergeraient et les VMs seraient lancées deux fois.
```
root@pve01:~# qm status 2092
status: stopped
root@hv01:~# pvecm expected 1
root@hv01:~# touch /etc/pve/essai && rm /etc/pve/essai
root@pve01:~# qm start 2092
root@hv01:~# pvecm status | sed -n '/Votequorum/,/Flags/p'
Expected votes:   2
Highest expected: 2
Total votes:      2
Quorum:           2
Flags:            Quorate
```
`pvecm expected 1` abaisse **à chaud** les votes attendus (le quorum devient 1) : `hv01` redevient « majoritaire ». Ce n'est pas écrit dans `corosync.conf` : quand `hv02` revient, il annonce ses votes attendus (2, ceux de la configuration) et *votequorum* retient la plus haute valeur : retour automatique à 2. Le geste est sûr **seulement** si l'autre nœud est prouvé éteint.

**Explications**

- **Ce que protège le quorum.** Pas les VMs en cours (elles continuent), mais **la configuration** et les **décisions** : sans quorum, rien ne démarre, rien ne se modifie, rien ne migre, la HA ne reprend rien. Un cluster sans quorum est figé, pas arrêté.
- **knet et les liens.** Chaque lien est surveillé en permanence par des sondes knet, indépendamment du trafic de Corosync ; la bascule est l'affaire de knet, Corosync ne voit qu'un transport qui continue. D'où l'importance d'un second lien sur un **autre** chemin physique en production.
- **L'adhésion par l'API.** Depuis Proxmox VE 6, `pvecm add` passe par l'API du cluster (HTTPS, port 8006) : pas besoin d'ouvrir SSH par mot de passe, et l'empreinte du certificat sert de preuve d'identité. L'ancienne méthode (`--use_ssh`) existe encore pour les cas où l'API n'est pas joignable.

**Alternatives**

- **Création par l'interface** (Datacenter > Cluster > Create / Join, avec l'« information de jonction » copiée d'un nœud à l'autre) : mêmes opérations, mêmes résultats ; la ligne de commande se rejoue et se documente mieux.
- **Lien 1 sur un second réseau dédié** plutôt que sur MGMT : plus propre (MGMT peut être chargé par des téléversements d'ISO ou des sauvegardes), mais il faudrait un VLAN et une carte de plus ; MGMT suffit comme **secours**, tant que le lien 0 est le préféré.
- **`two_node: 1`** dans `votequorum` (avec `wait_for_all`) : un cluster à deux nœuds garde le quorum quand l'un s'arrête, sans arbitre. Mais en cas de coupure du lien entre deux nœuds **vivants**, chacun se croit seul : le *fencing* devient une course. Proxmox VE recommande le QDevice (E05).

**Pièges classiques**

- Joindre un nœud qui héberge déjà une VM (« it is not allowed to join… ») : sauvegarder, supprimer, rejoindre, restaurer.
- Accepter l'empreinte sans la comparer : c'est le seul moment où l'identité du cluster est vérifiée.
- Des horloges désynchronisées : Corosync s'en accommode, pas les certificats émis à l'adhésion (« not yet valid ») ni les tickets d'authentification de l'interface.
- `pvecm expected 1` « pour débloquer » alors que l'autre nœud tourne derrière un lien coupé : *split-brain* fabriqué à la main.
- Oublier de retirer la table `m09_essai` : le lien 0 reste coupé, le cluster tourne sur MGMT sans que personne ne s'en aperçoive, jusqu'au jour où MGMT tombe à son tour.
- Supprimer `/etc/pve/essai` ou d'autres fichiers à la main dans `/etc/pve` sur un nœud sans quorum « après avoir forcé » : ces écritures seront propagées au retour des autres.

**En production chez MédiSphère**

Deux liens Corosync sur deux commutateurs différents, l'un sur un réseau **dédié** sans autre trafic ; une supervision des liens (`corosync-cfgtool -s`, M09-E25) qui alerte quand un lien tombe, même si le cluster va bien : un lien de secours mort ne se découvre que le jour où on en a besoin. Le geste `pvecm expected` figure dans le runbook de perte de nœud (RB-091) avec ses préconditions (preuve d'extinction : console iLO, alimentation coupée) et n'est jamais fait par une seule personne.

---

### M09-E05 — Deux nœuds et un arbitre : le QDevice

**Solution**

1. **La fiche.** Exemple complet : [`CHG-1005-qdevice-pbs01.md`](fichiers/M09-E05/medisphere/docs/virtualisation/changements/CHG-1005-qdevice-pbs01.md).

2. **La matrice.** Extrait : [`pare_feu.yml`](fichiers/M09-E05/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait).
```yaml
  - {entree: $V_MGMT, source: $HV_NOEUDS, sortie: $WG_S2S, destination: $PBS01, proto: tcp, ports: 5403,
     motif: "QDevice : corosync-qdevice des nœuds hv-par1 vers corosync-qnetd sur pbs01", ref: M09-E05}
```
Constat : la règle `{entree: $V_MGMT, sortie: [$LAB_IFS, $WG_S2S, $WG_LYO], motif: "bastion (MGMT) vers tout le lab, PAR2 et LYO1", ref: M07-E30}` (celle de M00-E10, élargie à LYO1 en M07-E30) n'a **pas de source**. Elle a été écrite quand `adm01` était seul dans MGMT ; depuis E03, les nœuds `hvNN` y sont aussi, et joignent donc tout le lab et tout PAR2, `pbs01` compris : le QDevice aurait fonctionné sans ta règle (seul le pare-feu de `pbs01` l'aurait bloqué). Écart au registre : « règle du bastion sans source : tout hôte de MGMT est traité comme le bastion ; proposition : `source: [$ADM01]` après inventaire des flux légitimes des nœuds (PBS, ACME, dépôts), à traiter avec la sécurisation du cluster (M09-E26) ». On ne la restreint pas dans ce changement : cela couperait des flux que les exercices suivants n'ont pas encore déclarés, et un changement ne doit faire qu'une chose.

3. **`pbs01`.**
```
root@pbs01:~# proxmox-backup-manager task list | head
root@pbs01:~# cp -a /etc/nftables.conf /root/nftables.conf.avant-chg1005
root@pbs01:~# cp -a /root/.ssh/authorized_keys /root/authorized_keys.avant-chg1005
root@pbs01:~# apt install --simulate corosync-qnetd
root@pbs01:~# apt install corosync-qnetd
root@pbs01:~# systemctl status corosync-qnetd --no-pager
root@pbs01:~# ss -ltnp | grep 5403
LISTEN 0 10 *:5403 *:* users:(("corosync-qnetd",…))
root@pbs01:~# ls /etc/corosync/qnetd/nssdb/
```
Le paquet crée une base de certificats NSS (`/etc/corosync/qnetd/nssdb`) et son autorité : c'est elle qui signera le certificat client du cluster pendant `pvecm qdevice setup`. Règle d'entrée ([extrait](fichiers/M09-E05/pbs01/nftables-extrait.conf)) :
```
		ip saddr { 10.10.10.51, 10.10.10.52, 10.10.10.53 } tcp dport 5403 ct state new accept comment "M09-E05 qnetd"
```
```
root@pbs01:~# nft -c -f /etc/nftables.conf && nft -f /etc/nftables.conf
root@pbs01:~# nft list ruleset | grep 5403
```
`hv03` (10.10.10.53) est inclus dès maintenant : il n'utilisera jamais le QDevice, mais la règle de la matrice décrit « les nœuds du cluster », et elle disparaîtra entière en E08.

4. **Les nœuds.**
```
root@hv01:~# apt install corosync-qdevice
root@hv02:~# apt install corosync-qdevice
root@hv01:~# cat /root/.ssh/id_rsa.pub
ssh-rsa AAAA… root@hv01
root@pbs01:~# echo 'ssh-rsa AAAA… root@hv01' >> /root/.ssh/authorized_keys
root@hv01:~# ssh -o StrictHostKeyChecking=yes root@10.20.10.10 true   # après vérification de l'empreinte de pbs01
```
La clé d'hôte de `pbs01` est vérifiée à la première connexion (empreinte lue sur `pbs01`, comme en E03) : `pvecm qdevice setup` utilise ce même canal.

5. **Le raccordement.**
```
root@hv01:~# pvecm qdevice setup 10.20.10.10
…
Done
root@hv01:~# pvecm status | sed -n '/Votequorum/,$p'
Votequorum information
----------------------
Expected votes:   3
Highest expected: 3
Total votes:      3
Quorum:           2
Flags:            Quorate Qdevice

Membership information
----------------------
    Nodeid      Votes    Qdevice Name
0x00000001          1    A,V,NMW 10.10.32.51 (local)
0x00000002          1    A,V,NMW 10.10.32.52
0x00000000          1            Qdevice
root@pbs01:~# corosync-qnetd-tool -l
Cluster "hv-par1":
    Algorithm:          Fifty-Fifty split
    Tie-breaker:        Node with lowest node ID
    Node ID 1:
        Client address:         ::ffff:10.10.10.51:…
        Configured node list:   1, 2
        Membership node list:   1, 2
        Vote:                   ACK (ACK)
    Node ID 2:
        …
root@hv01:~# sed -n '/^quorum/,/^}/p' /etc/pve/corosync.conf
quorum {
  device {
    model: net
    net {
      algorithm: ffsplit
      host: 10.20.10.10
      tls: on
    }
    votes: 1
  }
  provider: corosync_votequorum
}
```
Algorithme **`ffsplit`** (*fifty-fifty split*), 1 vote : pour un nombre pair de nœuds, le QDevice donne son vote à **une seule** moitié en cas de partage égal (départage : le plus petit identifiant de nœud, par défaut). La commande a : installé les certificats (autorité de qnetd → certificat client du cluster), modifié `corosync.conf`, activé `corosync-qdevice` sur chaque nœud.

6. **L'accès temporaire.**
```
root@pbs01:~# grep -n 'root@hv0' /root/.ssh/authorized_keys
root@pbs01:~# sed -i '/ root@hv0[1-3]$/d' /root/.ssh/authorized_keys
root@pbs01:~# diff /root/authorized_keys.avant-chg1005 /root/.ssh/authorized_keys && echo identique
identique
root@hv01:~# ssh -o BatchMode=yes root@10.20.10.10 true
root@10.20.10.10: Permission denied (publickey).
```
`pvecm qdevice setup` utilise `ssh-copy-id` avec la clé du nœud : si elle était déjà autorisée, rien n'est ajouté ; sinon, la commande aurait demandé le mot de passe de root de `pbs01` et ajouté la clé. Dans les deux cas, on revient au fichier d'avant le changement.

7. **Les épreuves.**
```
root@pve01:~# qm shutdown 2092
root@hv01:~# pvecm status | grep -E 'Total votes|Quorum:|Flags'
Total votes:      2
Quorum:           2
Flags:            Quorate Qdevice
root@hv01:~# touch /etc/pve/essai && rm /etc/pve/essai      # fonctionne
root@pve01:~# qm start 2092
```
Puis l'arbitre injoignable, les deux nœuds vivants :
```
root@hv01:~# nft add table inet m09_essai
root@hv01:~# nft add chain inet m09_essai sortie '{ type filter hook output priority -10; }'
root@hv01:~# nft add rule inet m09_essai sortie tcp dport 5403 drop
# (mêmes commandes sur hv02)
root@hv01:~# pvecm status | sed -n '/Flags/p;/0x0000000/p'
Flags:            Quorate
0x00000001          1   NA,NV,NMW 10.10.32.51 (local)
0x00000002          1   NA,NV,NMW 10.10.32.52
root@hv01:~# nft delete table inet m09_essai     # et sur hv02
```
2 votes présents sur 3 attendus, quorum 2 : le cluster reste quorate ; les drapeaux `NA,NV` disent que le QDevice n'est plus joignable (*Not Alive*) et ne vote plus. L'arbitre est un **troisième** vote, pas un point de passage obligé.

8. **La non-régression.**
```
root@pbs01:~# proxmox-backup-manager task list --limit 5
root@pbs01:~# proxmox-backup-manager datastore list
root@pve01:~# vzdump 1003 --storage pbs-par2 --mode snapshot      # ca01 : petite VM du socle
```
Fiche close : date, résultats des vérifications, écart inscrit.

**Explications**

- **Les votes du QDevice.** Avec `ffsplit`, le QDevice porte 1 vote : 3 attendus, quorum 2. Un nœud seul + le QDevice = 2 : quorate. Les deux nœuds seuls = 2 : quorate. Un nœud seul sans QDevice = 1 : bloqué. C'est exactement ce qu'il manquait au cluster de E04.
- **Pourquoi le QDevice ne crée pas de *split-brain*.** Si le lien entre les nœuds tombe mais que chacun joint `pbs01`, `corosync-qnetd` voit deux partitions de même taille : il ne vote que pour **une** (départage). L'autre n'a qu'un vote : elle perd le quorum.
- **TCP et TLS.** Contrairement à Corosync (UDP, latence critique), le QDevice parle en TCP avec TLS (certificats NSS) : il supporte bien un lien inter-sites plus lent, comme notre tunnel `wg0`.

**Alternatives**

- **QDevice sur une petite machine dédiée** (Raspberry Pi, VM sur un autre hyperviseur hors du cluster) : plus propre que de le loger sur le serveur de sauvegarde, et c'est la recommandation usuelle ; ici `pbs01` est la seule machine hors de `pve01`.
- **`two_node`** (voir E04) : pas d'arbitre, mais une course au *fencing* en cas de coupure du lien.
- **Un troisième nœud tout de suite** : la vraie solution, que E08 met en place ; le QDevice est une solution de **transition**, ou définitive pour les petits sites à deux serveurs.

**Pièges classiques**

- Lancer `pvecm qdevice setup` avec un nœud éteint : la commande exige tous les nœuds en ligne (elle les configure tous).
- Oublier `corosync-qdevice` sur un des nœuds : la configuration est écrite, mais ce nœud ne parle pas à l'arbitre ; son statut montre `NR` (*not registered*).
- Ouvrir 5403 à `10.10.0.0/16` « pour être tranquille » : n'importe quelle VM du lab parlerait à un service du serveur de sauvegarde.
- Laisser la clé de root du nœud sur `pbs01` : un nœud compromis aurait root sur le serveur de sauvegarde, donc sur toutes les sauvegardes.
- Croire que le QDevice protège d'une panne de `pbs01` : non, il ajoute un vote ; si `pbs01` **et** un nœud tombent, le survivant n'a qu'un vote sur trois.

**En production chez MédiSphère**

Le QDevice d'un site à deux serveurs est sur une machine dédiée, sur un troisième emplacement (ou au moins une autre alimentation et un autre commutateur), supervisée (`corosync-qnetd-tool -s`, alerte sur `NA` côté cluster). Son accès root par SSH n'existe que le temps de l'installation. Un même `corosync-qnetd` peut arbitrer plusieurs clusters : on y surveille alors le nombre de clusters raccordés et on documente lesquels dépendent de lui.

---

### M09-E06 — Stockages et réseaux des invités

**Solution**

1. **État des lieux.**
```
root@hv02:~# pvesm status
Name             Type     Status           Total            Used       Available        %
local             dir     active        12…              …
local-lvm     lvmthin     active        14…              …
root@hv02:~# cat /etc/pve/storage.cfg
dir: local
        path /var/lib/vz
        content iso,vztmpl,backup

lvmthin: local-lvm
        thinpool data
        vgname pve
        content rootdir,images
root@hv02:~# lsblk -o NAME,SIZE,SERIAL,FSTYPE
sda    32G hv02-systeme
├─sda1  …
└─sda3       LVM2_member
sdb    48G hv02-osd1
sdc    48G hv02-osd2
sdd    32G hv02-zfs
```
`storage.cfg` vit dans `/etc/pve` : il est le même partout, c'est la configuration **du cluster**. `local-lvm` de `hv02` fonctionne encore après l'adhésion parce que l'installateur a créé, sur chaque nœud, le même groupe de volumes `pve` et le même *thin pool* `data` : la déclaration du cluster (celle de `hv01`) décrit aussi la réalité de `hv02`. Avec un partitionnement différent, il aurait fallu restreindre la déclaration (`nodes`) et en ajouter une autre. `shared 1` sur un stockage qui ne l'est pas : Proxmox VE croirait que le disque est visible de partout ; il ne le copierait plus en migration et la HA pourrait démarrer une VM ailleurs, sans son disque (voir E09, question 9).

2. **ZFS.**
```
root@hv01:~# pvesh create /nodes/hv01/disks/zfs --name tank --raidlevel single \
    --devices /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_hv01-zfs --ashift 12 --compression lz4 --add_storage 0
root@hv02:~# pvesh create /nodes/hv02/disks/zfs --name tank --raidlevel single \
    --devices /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_hv02-zfs --ashift 12 --compression lz4 --add_storage 0
root@hv01:~# pvesm add zfspool zfs-local --pool tank --content images,rootdir --sparse 1 --nodes hv01,hv02
root@hv01:~# pvesm status --storage zfs-local; ssh hv02 pvesm status --storage zfs-local
```
Équivalent sans l'API : `zpool create -o ashift=12 -O compression=lz4 tank /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_hv01-zfs`. Une seule déclaration pour deux pools : un stockage Proxmox VE est un **nom** et une méthode d'accès ; chaque nœud listé l'interprète chez lui. C'est justement ce que demande la réplication ZFS (M09-E14) : même nom de stockage, même pool, sur la source et la cible.

3. **La mémoire de ZFS.**
```
root@hv01:~# cat /sys/module/zfs/parameters/zfs_arc_max
1073741824
root@hv01:~# arc_summary -s arc | grep -iE 'max size|target size'
```
Sans plafond, OpenZFS sur Linux autorise l'ARC jusqu'à la **moitié** de la mémoire (6 Go sur un nœud de 12 Go) ; l'ARC se rend sous pression, mais lentement et pas toujours assez vite : un démarrage d'invité ou un OSD de Ceph qui demande de la mémoire déclenche alors le *swap* ou l'OOM killer. Proxmox VE ne plafonne l'ARC (10 %) que lorsqu'il est installé **sur** ZFS : nos nœuds sont en ext4, d'où le réglage du rôle.

4. **Contenus de `local`.**
```
root@hv01:~# pvesm set local --content iso,vztmpl,backup,import,snippets
root@hv01:~# ssh hv02 ls -l /var/lib/vz/snippets/
```
Une commande pour tout le cluster, parce qu'elle modifie `storage.cfg`. Les **fichiers** de `local`, eux, sont propres à chaque nœud (`/var/lib/vz` de chacun) : une image importée sur `hv01` n'existe pas sur `hv02`, et le fragment cloud-init doit être posé partout (c'est le rôle `pve_noeud` qui s'en charge).

5. **Le template.** Script : [`outils/hv/creer-tpl-nested.sh`](fichiers/M09-E06/outils/hv/creer-tpl-nested.sh). Il vérifie `content` de `local` et le fragment, lit la somme de l'image dans `SHA512SUMS` (HTTPS), compare à l'image locale éventuelle et ne retélécharge que si elle diffère, télécharge par l'API (`download-url` avec `--checksum`, la tâche échoue si la somme ne correspond pas), écrit la clé de `adm01` (lue dans `authorized_keys` du nœud) dans un fichier temporaire pour `--sshkeys`, crée, agrandit, convertit en template.
```
admin@adm01:~/src/outils$ ssh hv01 'bash -s' < outils/hv/creer-tpl-nested.sh
== Image debian-13-genericcloud-amd64.qcow2
… downloading https://cloud.debian.org/…/debian-13-genericcloud-amd64.qcow2 …
… validating checksum … OK
== Template 199 tpl-nested-debian13 sur hv01 (local-lvm)
…
```

6. **Lire le template.**
```
root@hv01:~# qm config 199
agent: enabled=1
boot: order=scsi0
cicustom: vendor=local:snippets/medisphere-agent.yaml
ciuser: admin
cores: 1
cpu: x86-64-v2-AES
ide2: local-lvm:vm-199-cloudinit,media=cdrom
ipconfig0: ip=dhcp
memory: 1024
name: tpl-nested-debian13
net0: virtio=BC:24:11:…,bridge=vmbr1,tag=99
scsi0: local-lvm:base-199-disk-0,discard=on,iothread=1,size=8G,ssd=1
scsihw: virtio-scsi-single
serial0: socket
sshkeys: ssh-ed25519%20AAAA…
tags: debian13;nested
template: 1
vga: serial0
```
`x86-64-v2-AES` plutôt que `host` : aujourd'hui les trois nœuds sont identiques (ce sont des VMs du même `pve01`), mais un invité est fait pour **migrer** ; le jour où un nœud est remplacé par une machine différente (ou que le cluster passe sur du matériel), les invités en `host` ne migreraient plus. On fixe le plus petit dénominateur commun dès le template. Le fragment sur tous les nœuds : la référence `local:snippets/…` est résolue **sur le nœud où l'invité démarre** (le lecteur cloud-init y est régénéré) ; un clone migré puis redémarré sur `hv02` échouerait à démarrer si le fichier n'y était pas.

7. **Le chemin d'une trame DHCP.** L'invité émet sans étiquette sur sa carte ; le pont `vmbr1` du nœud (VLAN-aware) lui attribue le VLAN 99 (`tag=99` = PVID du port) et l'émet **étiquetée 99** sur `nic4` ; côté `pve01`, la carte `net4` du nœud est un port de `vmbr1` qui accepte le VLAN 99 (`trunks=99`) ; la trame circule étiquetée dans `vmbr1` de `pve01` jusqu'au port de `gw01` (`ens19`, trunk), où la sous-interface `ens19.99` la reçoit **désétiquetée** ; le relais DHCP de `gw01` la transmet en unicast à Kea (`dns01`, `dns02`) avec `giaddr` 10.10.99.1. L'étiquette est posée par le pont du **nœud**, lue par `vmbr1` de `pve01` (filtrage), retirée par le noyau de `gw01`.

**Explications**

- **Configuration commune, réalité locale.** `storage.cfg` dit « sur ces nœuds, il existe un pool `tank` accessible ainsi » ; il ne crée rien. La création (pool, *thin pool*, dossier) est un geste **par nœud**. Une déclaration sans réalité donne un stockage `inactive` ou en erreur sur le nœud concerné ; d'où la restriction `nodes`.
- **Désigner les disques par leur série.** `/dev/sdd` dépend de l'ordre de détection, qui peut changer (un disque ajouté, un contrôleur différent) ; le lien `by-id` construit à partir de la série que nous avons fixée dans OpenTofu ne change pas. C'est la même raison pour Ceph au palier 2.

**Alternatives**

- **`local-lvm` pour tout** : suffisant pour des invités, pas de réplication possible (la réplication de Proxmox VE est réservée à ZFS).
- **Image importée par `qm disk import`** depuis un fichier téléchargé à la main (`wget` + `sha512sum -c`) : fonctionne sur toutes les versions, mais sans contenu `import` ni vérification par la tâche ; utile si ta version refuse `download-url` en contenu `import`.
- **Personnaliser l'image** (`virt-customize` pour y installer l'agent) plutôt qu'un fragment *vendor* : image plus lourde à maintenir, mais aucun fichier à distribuer sur les nœuds.

**Pièges classiques**

- Créer le pool sur `/dev/sdb` en croyant prendre « le petit disque » : c'était un OSD. La série dans le chemin évite l'erreur.
- Déclarer `zfs-local` sans `--nodes` : `hv03`, en arrivant (E08), le verra « en erreur » tant qu'il n'a pas de pool.
- Ajouter l'option `--add_storage 1` à la création du pool sur chaque nœud : deux déclarations concurrentes (ou un échec sur le second nœud, le nom existant déjà).
- Mettre la clé SSH en argument de `--sshkeys` : l'option attend un **fichier**.
- Utiliser `--cicustom user=…` au lieu de `vendor=…` : le fragment *user* remplace toute la configuration utilisateur générée par Proxmox VE (compte, clé), alors que *vendor* s'y ajoute.

**En production chez MédiSphère**

Les images de base des invités viennent du pipeline d'images (M03) plutôt que d'Internet : publiées avec leur somme, signées, versionnées, et le template est recréé par le pipeline à chaque nouvelle image. Sur des nœuds physiques, le pool ZFS local serait en miroir sur deux disques (`raidlevel mirror`), et le plafond de l'ARC calculé d'après le reste du budget mémoire.

---

### M09-E07 — Premières VMs du cluster et migration

**Solution**

*A. Les invités.*
```
root@hv01:~# qm clone 199 101 --name app01 --full 1 --storage zfs-local
root@hv01:~# qm clone 199 102 --name app02 --full 1 --storage zfs-local
root@hv01:~# qm start 101
root@hv01:~# qm guest cmd 101 network-get-interfaces | jq -r '.[]."ip-addresses"[]? | select(."ip-address-type" == "ipv4") | ."ip-address"'
127.0.0.1
10.10.99.142
admin@adm01:~$ ssh admin@10.10.99.142 hostname
app01
root@hv01:~# qm start 102 && sleep 60 && qm guest cmd 102 ping && qm shutdown 102
```
Le premier démarrage prend une à deux minutes de plus : cloud-init installe l'agent (fragment *vendor*), d'où un `qm guest cmd` qui répond « QEMU guest agent is not running » au début. Le clone complet copie le disque du template sur `zfs-local` (avec le lecteur cloud-init).
```
root@hv02:~# pvesh get /cluster/resources --type vm --output-format json | jq -r '.[] | "\(.vmid)\t\(.name)\t\(.node)\t\(.status)"'
101     app01   hv01    running
102     app02   hv01    stopped
199     tpl-nested-debian13  hv01  stopped
root@hv02:~# qm config 101
Configuration file 'nodes/hv02/qemu-server/101.conf' does not exist
```
Le fichier est `/etc/pve/nodes/hv01/qemu-server/101.conf` (lisible depuis `hv02` dans `/etc/pve`) : `qm` ne travaille que sur les VMs du nœud local ; l'API (`pvesh get /nodes/hv01/qemu/101/config` depuis `hv02`) transmet au bon nœud.

*B. Migrer.*
```
root@hv01:~# qm migrate 102 hv02
… starting migration of VM 102 to node 'hv02' (10.10.10.52)
… found local disk 'zfs-local:vm-102-cloudinit' (attached)
… found local disk 'zfs-local:vm-102-disk-0' (attached)
… copying local disk images
… full send of tank/vm-102-disk-0@__migration__ estimated size is …
… migration finished successfully (duration 00:00:4x)
```
Hors ligne, les disques ZFS sont envoyés par **`zfs send | zfs receive`** à travers SSH (instantané `__migration__`), sur le réseau de migration (par défaut MGMT : c'est l'adresse du nœud qui apparaît entre parenthèses).
```
root@hv01:~# qm migrate 101 hv02 --online
… can't migrate local disk 'zfs-local:vm-101-disk-0': can't live migrate attached local disks without with-local-disks option
… ERROR: Problem found while scanning volumes - can't migrate VM - check log
admin@adm01:~$ ping -D -i 0.2 10.10.99.142 | tee ~/m09/e07/ping-migration.txt
root@hv01:~# qm migrate 101 hv02 --online --with-local-disks
… starting VM 101 on remote node 'hv02'
… volume 'zfs-local:vm-101-disk-0' is 'zfs-local:vm-101-disk-0' on the target
… starting storage migration
… scsi0: start migration to nbd:unix:/run/qemu-server/101_nbd.migrate:exportname=drive-scsi0
drive mirror is starting for drive-scsi0
drive-scsi0: transferred 1.4 GiB of 8.0 GiB (17.50%) in 5s
…
drive-scsi0: transferred 8.0 GiB of 8.0 GiB (100.00%) in 1m 2s, ready
… starting online/live migration on unix:/run/qemu-server/101.migrate
… migration status: active (transferred 312.0 MiB, remaining 401.0 MiB), total 1.0 GiB)
… average migration speed: 340.0 MiB/s - downtime 48 ms
… migration finished successfully (duration 00:01:21)
```
Lecture : 1 min 20 au total, dont l'essentiel pour le **disque** (miroir NBD de QEMU, 8 Gio provisionnés, dont seuls les blocs écrits pèsent vraiment), quelques secondes pour la mémoire, **48 ms** d'interruption annoncée. Côté `ping` (un paquet toutes les 200 ms) : 0 ou 1 paquet perdu (`grep -c 'icmp_seq' ` et recherche des numéros manquants dans le fichier). Le retour (`qm migrate 101 hv01 --online --with-local-disks`) donne le même ordre de grandeur.

6. Résumé pour Julien (exemple) : « Démontré : `app01` est passée de `hv01` à `hv02` en service, 1 min 20 de migration pour 48 ms d'interruption, 0 à 1 ping perdu sur 400. La durée vient de la copie du disque, local à chaque serveur aujourd'hui. Au palier 2, avec le stockage partagé Ceph, seul le contenu de la mémoire voyagera : quelques secondes. Ce qui empêche une migration : un CPU de type `host` entre serveurs différents, un CD-ROM monté depuis un stockage local, un disque sur un stockage absent du serveur d'arrivée, une VM avec un périphérique attaché au matériel (USB, PCI). »

*C. Le pare-feu d'en dessous.*
```
root@pve01:~# qm config 2092 | grep ^net4
net4: virtio=02:4D:53:09:02:04,bridge=vmbr1,trunks=99
root@pve01:~# pvesh set /nodes/<NOEUD>/qemu/2092/firewall/options --enable 1
root@pve01:~# qm set 2092 --net4 virtio=02:4D:53:09:02:04,bridge=vmbr1,trunks=99,firewall=1
```
Le `ping` s'arrête aussitôt ; au renouvellement, `app01` ne reçoit pas de réponse DHCP. Les options :
```
root@pve01:~# pvesh get /nodes/<NOEUD>/qemu/2092/firewall/options --output-format json
{"enable":1,"macfilter":1,"policy_in":"DROP","policy_out":"ACCEPT", …}
```
Deux mécanismes : (1) **`macfilter`** (actif par défaut) : en sortie de la carte, seules les trames dont la source est `02:4D:53:09:02:04` passent ; celles de `app01` (MAC `BC:24:11:…`) sont jetées ; (2) **`policy_in: DROP`** : en entrée de la carte, tout ce qui n'est pas explicitement autorisé par une règle de la VM est jeté (les réponses DHCP, le `ping` d'`adm01`). Les cartes `net0` à `net3` ne sont pas touchées (pas de `firewall=1`) : `hv02` lui-même reste joignable, seuls ses invités sont coupés.
```
admin@adm01:~/src/infra/envs/hv$ tofu plan
  # proxmox_virtual_environment_vm.noeud["hv02"] will be updated in-place
  ~ network_device {
      ~ firewall    = true -> false
        # (…)
    }
admin@adm01:~/src/infra/envs/hv$ tofu apply
root@pve01:~# pvesh set /nodes/<NOEUD>/qemu/2092/firewall/options --enable 0
```
Le `ping` reprend dès l'`apply`. OpenTofu n'a ramené que la carte : les **options** du pare-feu de la VM sont un autre objet de l'API (`/firewall/options`), qu'aucune ressource de `envs/hv` ne gère (le fournisseur a une ressource séparée pour cela). Ce qu'OpenTofu ne déclare pas, il ne le voit pas dériver.

**Explications**

- **Pourquoi la migration à chaud « locale » est possible.** QEMU sait recopier un disque **pendant** que la VM écrit dessus (*drive-mirror*) : les écritures sont dupliquées vers la cible pendant la copie, puis la bascule de la mémoire termine le tout. Le prix : tout le disque traverse le réseau, et la migration dure autant que la copie.
- **La durée et l'interruption.** La durée totale dépend du volume à copier (disque, mémoire) et du débit ; l'interruption ne dépend que de la **dernière** passe de mémoire et de la reprise sur la cible. On peut avoir une migration de dix minutes avec 30 ms d'interruption, ou une migration de 20 secondes qui ne converge pas (mémoire trop active) et finit par un long arrêt.

**Alternatives**

- **Migration par l'interface** (bouton « Migrate », cocher le mode en ligne) : mêmes tâches, mêmes journaux.
- **`--targetstorage local-lvm`** pour changer de stockage en migrant (le stockage d'arrivée n'a pas à porter le même nom).
- **Clone lié** (`--full 0`) : instantané et économe, mais les clones dépendent du template, sur `local-lvm` de `hv01` seulement : ils ne peuvent pas migrer sans emporter leur disque de base. Réservé à des invités jetables qui restent sur leur nœud.

**Pièges classiques**

- Lire l'adresse de l'invité avant que l'agent ne soit installé (premier démarrage) : « agent not running », ce n'est pas une panne.
- Mesurer l'interruption avec `ping -i 1` : une interruption de 50 ms ne fait perdre aucun paquet ; à 200 ms d'intervalle, on commence à voir quelque chose.
- Modifier `net4` par `qm set` en ne donnant que `firewall=1` : la carte entière est redéfinie, avec une **nouvelle** MAC et sans *trunks* ; le nœud perdrait son nom `nic4` (épinglage sur l'ancienne MAC) et ses invités. On reprend toujours toute la définition.
- Oublier de désactiver le pare-feu de la VM après l'expérience : la prochaine carte créée par erreur avec `firewall=1` serait filtrée sans prévenir.

**En production chez MédiSphère**

Un réseau de migration dédié et limité en débit (M09-E27), les invités sur stockage partagé (Ceph), et la migration à chaud devient un geste de routine de la maintenance (M09-E20, RB-090). La règle « CPU commun » est vérifiée par la revue des templates, et un contrôle signale tout invité en `host`. Le pare-feu des invités se règle **dans** le cluster (M09-E26), jamais sur les cartes des hyperviseurs.

---

### M09-E08 — Un troisième nœud

**Solution**

1. **L'ordre** (votes attendus / présents, et que se passe-t-il si un nœud tombe à ce moment) :

| Étape | Attendus / présents | Si un nœud tombe |
|---|---|---|
| Départ : 2 nœuds + QDevice | 3 / 3 | le survivant garde le quorum (2/3) |
| Création et installation de `hv03` (hors cluster) | 3 / 3 | idem |
| **QDevice retiré** | 2 / 2 | **le survivant perd le quorum** : étape fragile |
| `hv03` rejoint | 3 / 3 | les deux autres gardent le quorum (2/3) |
| `pbs01` nettoyé | 3 / 3 | idem |

L'étape fragile est entre le retrait du QDevice et l'adhésion de `hv03` : on la rend la plus **courte** possible (`hv03` installé, configuré et vérifié avant), on vérifie que `hv01` et `hv02` sont en ligne et en bonne santé (liens, journaux), et on ne lance rien d'autre en parallèle.

2. **La VM.** [`noeuds.auto.tfvars.json`](fichiers/M09-E08/infra/envs/hv/noeuds.auto.tfvars.json) reçoit `hv03`.
```
admin@adm01:~/src/infra/envs/hv$ installation/preparer-iso.sh hv03
admin@adm01:~/src/infra/envs/hv$ tofu plan
Plan: 15 to add, 0 to change, 0 to destroy.
```
15 ressources : la VM, la fiche NetBox (VM, 5 interfaces, 4 adresses, IP primaire) et les 2 enregistrements DNS. « 0 to change » : `hv01` et `hv02` ne bougent pas, parce que tout est indexé par le **nom** du nœud (`for_each` sur une table, MAC et séries calculées à partir du numéro).

3. **La configuration.** [`hv.yml`](fichiers/M09-E08/ansible/inventories/lab/hv.yml) reçoit `hv03` ; empreinte comparée sur la console comme en E03, puis :
```
admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/lab/netbox.yml -i inventories/lab/hv.yml playbooks/hv.yml --limit hv03
```

4. **Le QDevice s'efface.**
```
root@hv01:~# pvecm status | grep -E 'Nodes|Quorate|Flags'
root@hv01:~# pvecm qdevice remove
root@hv01:~# pvecm status | sed -n '/Votequorum/,/Flags/p'
Expected votes:   2
Highest expected: 2
Total votes:      2
Quorum:           2
Flags:            Quorate
```

5. **L'adhésion.**
```
root@hv03:~# pvecm add 10.10.10.51 --link0 10.10.32.53 --link1 10.10.10.53
root@hv01:~# pvecm status | sed -n '/Votequorum/,$p'
Expected votes:   3
Highest expected: 3
Total votes:      3
Quorum:           2
Flags:            Quorate

Membership information
----------------------
    Nodeid      Votes Name
0x00000001          1 10.10.32.51 (local)
0x00000002          1 10.10.32.52
0x00000003          1 10.10.32.53
root@hv03:~# corosync-cfgtool -s
root@hv01:~# for n in hv01 hv02 hv03; do ssh $n 'systemctl is-enabled corosync-qdevice; systemctl is-active corosync-qdevice'; done
```
`pvecm qdevice remove` a arrêté et désactivé `corosync-qdevice` sur `hv01` et `hv02` ; sur `hv03`, le paquet n'a jamais été installé (rien à faire, la vérification répond « not-found » ou « inactive »).

6. **Le stockage local.**
```
root@hv03:~# pvesh create /nodes/hv03/disks/zfs --name tank --raidlevel single \
    --devices /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_hv03-zfs --ashift 12 --compression lz4 --add_storage 0
root@hv03:~# pvesm set zfs-local --nodes hv01,hv02,hv03
root@hv03:~# pvesm status --storage zfs-local
```

7. **`pbs01`.**
```
root@pbs01:~# systemctl disable --now corosync-qnetd
root@pbs01:~# sed -i '/M09-E05/d' /etc/nftables.conf        # la règle et son commentaire
root@pbs01:~# nft -c -f /etc/nftables.conf && nft -f /etc/nftables.conf
root@pbs01:~# nft list ruleset | grep -c 5403
0
```
Matrice : la règle 5403 quitte `pare_feu.yml` (la définition `HV_NOEUDS` reste : les flux des nœuds de M09-E15, E18 et E26 la réutilisent) par une MR, appliquée aux deux passerelles. Sauvegarde de contrôle (`vzdump 1003 --storage pbs-par2`), CHG-1005 complétée : « QDevice retiré le `<date>` (M09-E08) ; paquet `corosync-qnetd` conservé, service désactivé, à désinstaller en fin de module (M09-E46) ».

8. **L'épreuve.**
```
root@pve01:~# qm shutdown 2093
root@hv01:~# pvecm status | grep -E 'Total votes|Quorum:|Flags'
Total votes:      2
Quorum:           2
Flags:            Quorate
root@pve01:~# qm start 2093
```
Le cluster à trois nœuds perd **un** nœud sans perdre le quorum, quel qu'il soit. Avec le QDevice à deux nœuds, il pouvait perdre un nœud **ou** l'arbitre, mais pas un nœud et l'arbitre ; et l'arbitre était sur une autre infrastructure (un autre site, un tunnel). Désormais, la tolérance ne dépend plus de PAR2.

**Explications**

- **Pourquoi retirer le QDevice d'abord.** La configuration du QDevice est calculée pour un nombre de nœuds (algorithme, votes) ; la documentation impose de le retirer avant d'ajouter ou de retirer un nœud, puis de le reconfigurer si le nouveau nombre est pair. Pour trois nœuds, il ne faut pas le reconfigurer : avec un nombre impair, Proxmox VE utiliserait l'algorithme `lms` (*last man standing*), où le QDevice porte `N-1` votes et peut maintenir en vie un nœud seul ; la documentation le déconseille, car une défaillance de l'arbitre ou du chemin vers lui pèse alors plus lourd que celle d'un nœud.
- **Pourquoi le plan ne touche pas aux deux premiers.** Tout est indexé par nom ; une liste aurait décalé les index. C'est la condition pour faire évoluer un cluster par le code sans risque.

**Alternatives**

- **Garder le QDevice** avec trois nœuds (`pvecm qdevice setup --force`, algorithme `lms`) : déconseillé (voir plus haut).
- **Désinstaller `corosync-qnetd` tout de suite** : plus propre ; le module le garde jusqu'au nettoyage final pour pouvoir refaire une phase à deux nœuds si une reconstruction (M09-E29) le demandait.

**Pièges classiques**

- Ajouter `hv03` avant de retirer le QDevice : la configuration du QDevice ne correspond plus au nombre de nœuds ; votes incohérents jusqu'à ce qu'on le retire.
- Retirer le QDevice avec un nœud déjà éteint : on tombe immédiatement à 1 vote sur 2.
- Oublier `--link1` à l'adhésion de `hv03` : il n'aurait qu'un lien ; le cluster fonctionne, et le premier incident du VLAN 32 l'exclut.
- Laisser la règle 5403 dans la matrice « au cas où » : un flux sans usage est un flux que personne ne surveille.

**En production chez MédiSphère**

L'ajout d'un nœud est un runbook (RB-091 couvre aussi la réintégration) : nœud installé et vérifié hors cluster, fenêtre de changement, vérifications avant (liens, santé), adhésion, vérifications après, mise à jour de la supervision et de l'inventaire. Le nombre de nœuds suit une règle écrite : impair, ou pair avec un QDevice sur une troisième infrastructure, et le choix figure dans l'ADR du cluster (ADR-0090).

---

### M09-E09 — Questions : cluster, quorum et HA

**Barème** : 2 points par question, total sur 24. En dessous de 14, refais E04 et E05 en relisant leur corrigé avant le palier 2 : la HA (E13) et le *fencing* (E24) s'appuient sur ces mécanismes.

**1. Le lien 0 coupé.** knet surveille chaque lien en continu ; quand le lien 0 n'a plus répondu, il a basculé sur le lien 1 pour les messages vers `hv02`, sans interrompre Corosync : l'appartenance et le quorum n'ont jamais changé. Avec un seul lien, `hv02` aurait été déclaré absent au bout du délai du jeton : chaque nœud seul, 1 vote sur 2, perte du quorum des deux côtés (sans arbitre). En production, si les deux liens passent par le même commutateur, la panne de ce commutateur les coupe **ensemble** : la redondance n'existe que sur le papier. Deux chemins physiques, deux commutateurs, idéalement deux cartes.

**2. Les VMs continuent.** Oui, les VMs de `hv01` ont continué : un processus QEMU qui tourne n'a pas besoin du quorum. Le cluster bloque les **modifications** parce qu'une modification faite par une partition minoritaire pourrait contredire celle de l'autre partition (même VM démarrée deux fois, même VMID créé deux fois, configurations divergentes) ; l'**exécution** de ce qui tournait déjà ne crée pas de conflit tant qu'aucune reprise n'a lieu de l'autre côté. Exception : un nœud qui porte des ressources HA s'arrête lui-même (watchdog) en perdant le quorum, précisément pour que l'autre côté puisse les reprendre.

**3. `pvecm expected 1` pour Nadia.** « Seulement quand l'autre nœud est **prouvé éteint** et ne reviendra pas avant qu'on ait fini : console de l'hyperviseur montrant la VM arrêtée, ou alimentation coupée. Jamais quand on ne "voit plus" l'autre nœud : il tourne peut-être derrière un réseau coupé. Avant : vérifier l'état réel de l'autre nœud, noter l'heure et la raison dans le ticket, prévenir l'équipe. Après : le retour de l'autre nœud remet les votes d'eux-mêmes. »

**4. Votes avec le QDevice.** `hv01` : 1, `hv02` : 1, QDevice (`ffsplit`) : 1. Attendus 3, quorum `floor(3/2) + 1` = 2. Sans l'arbitre, les deux nœuds font 2 votes : quorum atteint. L'arbitre est un vote **en plus**, pas une condition.

**5. Réponse B.** `corosync-qnetd` voit deux partitions d'un nœud chacune (même taille) : avec `ffsplit`, il ne vote que pour **une** (par défaut celle qui contient le plus petit identifiant de nœud, `hv01`). `hv01` a 2 votes sur 3 : quorate ; `hv02` en a 1 : bloqué (et s'isole s'il porte des ressources HA). A est faux : c'est exactement le *split-brain* que l'algorithme interdit. C est faux : l'arbitre départage au lieu de tout bloquer. D : le QDevice n'a aucun moyen d'agir sur un nœud.

**6. Le QDevice d'abord.** La documentation l'impose : la configuration du QDevice (algorithme, votes) dépend du nombre de nœuds, et la commande d'adhésion ne la recalcule pas. Ajouter `hv03` avec le QDevice en place aurait donné une configuration incohérente (un QDevice `ffsplit` pour trois nœuds). Et à trois nœuds, on ne le reconfigure pas : nombre impair.

**7. Partitions.** `hv03` isolé : `hv01` + `hv02` ont 2 votes sur 3 : quorate, `/etc/pve` en écriture, ils pourront (avec la HA) reprendre les VMs de `hv03` après son *fencing* ; `hv03` a 1 vote : `/etc/pve` en lecture seule, ses VMs continuent tant qu'il n'a pas de ressource HA ; s'il en a, il s'arrête lui-même au bout du délai du watchdog. Quatre nœuds coupés en 2 + 2 : chaque moitié a 2 votes sur 4, quorum 3 : **aucune** n'a le quorum ; tout le cluster est figé, et toutes les ressources HA sont arrêtées par le *fencing* des quatre nœuds. C'est la raison des nombres impairs (ou d'un QDevice avec un nombre pair).

**8. pmxcfs.** Dans une base SQLite, `/var/lib/pve-cluster/config.db`, sur **chaque** nœud ; `/etc/pve` en est une vue FUSE, et la base est tenue en mémoire. Chaque écriture est diffusée à tous les nœuds par Corosync : de gros fichiers satureraient Corosync et la mémoire, et pmxcfs limite la taille des fichiers et de la base (de l'ordre du mégaoctet par fichier, quelques dizaines à centaines de mégaoctets au total selon la version). Les disques des VMs sont sur les **stockages** (LVM-thin, ZFS, Ceph), les ISO sur des stockages de contenu `iso` (`local`, `hdd-bulk`…) : `/etc/pve` ne porte que la configuration.

**9. Réponse B.** La définition d'un stockage est commune (pmxcfs), mais son **activation** est locale : chaque nœud vérifie de son côté que le pool existe (`pvesm status` sur `hv03` le montre inactif). Rien n'est vérifié à l'adhésion (A faux) ; Proxmox VE ne crée jamais de pool de lui-même à partir d'une simple déclaration (C faux : c'est le rôle `pve_noeud` ou `pveceph`/`zpool create` qui le fait) ; les autres nœuds ont leur pool et ne sont pas affectés (D faux). C'est pour cela que le nom du pool doit être **le même partout** (réplication d'E14) et qu'E06 déclare `zfs-local` avec `--nodes` : limiter un stockage aux nœuds qui le portent réellement, au lieu de laisser un stockage « fantôme » sur les autres (E08 l'étend ensuite à `hv03`). Le cas voisin, et bien plus grave, d'un stockage local déclaré `shared` est l'un des défauts de la revue M09-E21.

**10. Durée et interruption.** La durée totale est celle de la copie (disque entier par miroir NBD, puis mémoire en plusieurs passes) : elle dépend du **volume** et du débit. L'interruption est la dernière passe de mémoire, VM en pause, puis la reprise sur la cible : elle dépend de la mémoire modifiée pendant la passe précédente et de la latence. On peut allonger l'une sans toucher à l'autre : un disque deux fois plus gros double la durée sans changer l'interruption.

**11. HA et stockage.** `zfs-local` sans réplication : le disque de `app01` est sur `hv02`, mort ; le gestionnaire HA ne peut pas la démarrer ailleurs (le volume n'existe pas sur les autres nœuds) : ressource en erreur, ou en attente du retour de `hv02`. Avec un disque sur Ceph : le disque est accessible de `hv01` et `hv03`, la VM y redémarrera. Pas immédiatement, parce que le gestionnaire HA doit être **sûr** que `hv02` ne la fait plus tourner : il attend que le délai de *fencing* de `hv02` soit écoulé (son watchdog a expiré et l'a redémarré) avant de reprendre ses ressources. Compter de l'ordre de deux minutes (M09-E24 mesurera).

**12. Manuel et code.** Restent manuelles au palier 1 : création du cluster et adhésions (`pvecm create`, `pvecm add` avec mot de passe et empreinte), QDevice, création des pools ZFS et déclaration des stockages, contenus de `local`, lancement du script de template, vérification des empreintes SSH à la première connexion. À automatiser en premier pour reconstruire en une heure : les stockages et le template (idempotents, simples à décrire en Ansible ou par l'API), puis la formation du cluster (un rôle qui crée sur le premier nœud et fait rejoindre les autres, M09-E18 / E46), et la confiance initiale (*webhook* de fin d'installation ou mode `http`). À garder volontairement manuel, ou derrière une confirmation explicite : les gestes destructeurs ou de dernier recours (`pvecm expected`, `pvecm delnode`, retrait d'un nœud), dont le contexte doit être jugé par un humain.
