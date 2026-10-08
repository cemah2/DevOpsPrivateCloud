# Module 09 — Palier 1 : Découverte

Avant d'installer quoi que ce soit, `pve01` doit prouver qu'il sait faire tourner des hyperviseurs dans des VMs : instructions de virtualisation, mémoire, réseau, droits, ISO vérifiée. Ensuite viennent deux nœuds Proxmox VE installés **sans clavier**, par le code, puis le cluster `hv-par1` avec ses deux liens Corosync. À deux nœuds, le cluster ne survit pas à la perte de l'un : tu lui donnes un arbitre à PAR2, sur `pbs01`. Il reçoit ses stockages locaux, son réseau d'invités, un template, ses premières VMs, qui migrent d'un nœud à l'autre. Enfin, un troisième nœud rejoint le cluster et l'arbitre s'efface. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : module 08 terminé (`lab/bin/check 08 46` vert) ; modules 05 et 06 (état OpenTofu chiffré, NetBox, PowerDNS, certificats SSH d'hôte) ; module 00 (Proxmox VE, SDN, PBS). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques, les règles du module et la façon d'accéder aux nœuds.

---

### M09-E01 — Test de positionnement : virtualisation en cluster  `Q` `★★`

> **Ticket PLAT-1001** — *De : Karim Benali*
> Le rituel, version cluster. Tu as administré des hyperviseurs, mais un cluster ne se comporte pas comme trois hyperviseurs côte à côte : il vote, il se protège de lui-même, il refuse d'agir quand il doute. Une heure, par écrit, sans moteur de recherche ni IA, sans rien exécuter. Réponds même là où tu hésites : c'est le raisonnement qui m'intéresse.

**Objectifs pédagogiques**
- Évaluer tes acquis sur la virtualisation, le quorum, la haute disponibilité et le stockage d'un cluster.
- Repérer les notions à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Virtualisation*

1. Dans une pile KVM, quel est le rôle du module noyau `kvm`, du module `kvm_intel` (ou `kvm_amd`) et du processus QEMU ? Quelles **deux** conditions faut-il réunir pour qu'une VM puisse elle-même exécuter des VMs accélérées par le matériel ?

2. *(QCM)* Une VM a le type de CPU `host` sur un nœud équipé d'un Xeon récent. On veut la migrer à chaud vers un nœud plus ancien du même cluster. Que se passe-t-il le plus probablement ?
   - A. La migration réussit : le type `host` s'adapte au nœud d'arrivée
   - B. La migration échoue, ou la VM plante après la bascule : elle utilise des instructions que le nœud d'arrivée n'a pas
   - C. La migration réussit mais la VM redémarre
   - D. Proxmox VE convertit le type en `kvm64` pendant la migration

3. Une VM doit recevoir des trames étiquetées de plusieurs VLAN (c'est un routeur, ou un hyperviseur). Que faut-il configurer sur sa carte réseau côté hôte, et sur le pont de l'hôte ? Pourquoi un filtrage des adresses MAC sur cette carte empêcherait-il les machines qu'elle héberge de communiquer ?

*Cluster et quorum*

4. Dans un cluster Proxmox VE, à quoi servent **Corosync** et **pmxcfs** ? Où est stockée la configuration d'une VM, et que voit-on de cette configuration sur un autre nœud ?

5. Corosync est décrit comme « sensible à la latence, pas au débit ». Explique. Que risque-t-on à faire passer Corosync sur le même lien que la réplication Ceph ou les migrations ?

6. Définis le **quorum**. Combien de nœuds peut-on perdre sans perdre le quorum dans un cluster de 3 nœuds ? de 4 ? de 5 ? Qu'en conclus-tu sur le nombre de nœuds ?

7. *(QCM)* Un cluster de **deux** nœuds sans arbitre. On arrête proprement l'un d'eux pour maintenance. Sur le survivant :
   - A. Rien ne change : il continue normalement
   - B. Les VMs en cours continuent de tourner, mais `/etc/pve` est en lecture seule : on ne peut plus démarrer, créer ni modifier une VM
   - C. Le survivant redémarre pour se protéger
   - D. Le survivant reprend automatiquement les VMs du nœud arrêté

8. Qu'est-ce qu'un *split-brain* ? Décris un scénario précis, avec un stockage partagé, où il corrompt des données. Quel mécanisme du cluster l'empêche ?

9. Qu'est-ce qu'un **QDevice** ? Pourquoi ne doit-il tourner ni sur l'un des nœuds du cluster, ni dans une VM hébergée par ce cluster ?

*Haute disponibilité*

10. *(QCM)* Qu'est-ce qui garantit, dans Proxmox VE, qu'une VM HA n'est pas démarrée sur un autre nœud alors qu'elle tourne encore sur le nœud « perdu » ?
    - A. Le verrou de la VM dans le stockage partagé
    - B. Le nœud qui a perdu le quorum s'arrête lui-même (watchdog) avant que les autres ne reprennent ses VMs
    - C. Le jeton de Corosync, qui interdit les écritures
    - D. Une sauvegarde PBS prise juste avant le démarrage

11. Pourquoi la HA a-t-elle besoin d'un stockage **partagé** (ou répliqué) ? Que peut-elle faire pour une VM dont le seul disque était sur le stockage local du nœud tombé ?

12. Haute disponibilité ou tolérance aux pannes : quelle différence ? Une VM HA de Proxmox VE est-elle interrompue quand son nœud tombe ? Pendant combien de temps, à ton avis, et de quoi dépend ce temps ?

*Stockage et migration*

13. Décris les étapes d'une **migration à chaud** (mémoire, pages modifiées, bascule). Où se situe l'interruption de service, et de quoi dépend sa durée ?

14. *(QCM)* Une VM a son disque sur `local-lvm`. On lance une migration à chaud vers un autre nœud.
    - A. Impossible : une VM sur stockage local ne migre qu'à froid
    - B. Possible, en recopiant aussi le disque pendant la migration ; plus long, et le stockage cible doit exister sur le nœud d'arrivée
    - C. Proxmox VE déplace d'abord le disque sur un stockage partagé
    - D. La VM migre, son disque reste sur le premier nœud et est lu à travers le réseau

15. Compare, pour une base de données, trois façons de survivre à la perte d'un nœud : stockage partagé Ceph, réplication ZFS toutes les 15 minutes, sauvegarde nocturne restaurée. Pour chacune : perte de données possible (RPO) et délai de reprise (RTO).

16. **Ceph hyperconvergé** sur trois nœuds : deux avantages, deux inconvénients. Avec des pools `size 3, min_size 2`, que se passe-t-il pour les écritures quand un nœud tombe ? quand deux nœuds tombent ?

*Réseau, installation, sauvegarde*

17. Cite les réseaux qu'on sépare dans un cluster de virtualisation de production (au moins cinq) et, pour chacun, la raison de la séparation.

18. Les réseaux de stockage passent en MTU 9000. Qu'y gagne-t-on ? Une seule interface restée à 1500 sur le chemin : quel symptôme, et pourquoi est-il trompeur (un `ping` simple passe) ?

19. *(QCM)* On ajoute à un cluster un nœud qui héberge déjà deux VMs. Que se passe-t-il ?
    - A. Les VMs sont fusionnées dans la configuration du cluster
    - B. Ce n'est pas permis : un nœud qui rejoint ne doit héberger aucun invité, sa configuration `/etc/pve` est remplacée par celle du cluster
    - C. Les VMs sont renumérotées pour éviter les conflits
    - D. Le cluster adopte la configuration du nouveau nœud

20. Pourquoi installer des hyperviseurs de façon **automatisée** plutôt qu'au clavier, alors qu'on n'en installe que quelques-uns par an ? Qu'est-ce qui reste difficile à automatiser proprement dans une telle installation ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour le quorum, raisonne toujours en **majorité stricte des votes attendus** : `floor(N/2) + 1`. Puis demande-toi ce que voit chaque moitié d'un réseau coupé en deux.
</details>

<details><summary>Indice 2</summary>

Pour la HA, sépare deux questions : « la VM peut-elle tourner ailleurs ? » (où est son disque) et « a-t-on le droit de la démarrer ailleurs ? » (est-on sûr qu'elle ne tourne plus là où elle était).
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M09-E46), sans relire le corrigé, et compare.

---

### M09-E02 — Préparer la virtualisation imbriquée  `LAB` `★★`

> **Ticket PLAT-1002** — *De : Karim Benali*
> Avant d'installer trois hyperviseurs dans `pve01`, je veux la preuve qu'il sait le faire, et qu'on a la place. Les extensions de virtualisation, le paramètre du noyau, la mémoire, le réseau (VLAN, MTU, adresses MAC des invités du dessous), les droits de notre compte OpenTofu, et l'ISO de Proxmox **vérifiée** par sa signature, pas téléchargée « parce que c'est le site officiel ». Tout ça avant la première VM. Et rien ne change sur `pve01` sans que tu l'aies annoncé.

**Objectifs pédagogiques**
- Vérifier qu'un hôte KVM peut imbriquer (matériel, module noyau, type de CPU de la VM) et le prouver sur une VM jetable.
- Établir le budget mémoire d'un profil de lab et libérer la place.
- Comprendre ce que le réseau de l'hôte doit laisser passer pour qu'un hyperviseur virtuel serve ses propres invités.
- Vérifier une ISO par sa signature, avec le trousseau qu'on possède déjà.

**Prérequis** : M00 (Proxmox VE de `pve01`, SDN `lab`, comptes Proxmox) ; M03-E05 (`deposer-iso.sh`) ; M05-E03 (compte `wb-tofu@pve`) ; M07-E15 (MTU 9000 de `vmbr1`) ; M08 (procédure d'arrêt de `ceph-par1`).
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Paramètre d'imbrication | `/sys/module/kvm_intel/parameters/nested` (`kvm_amd` sur processeur AMD) ; actif par défaut sur les noyaux récents |
| VM jetable | VMID **2099** `m09-essai` : clone **lié** de l'image dorée `current` (`<VMID-CURRENT>`), pool `lab`, étiquette `env-m09`, VNet `vsandbox` (DHCP), 1 vCPU, 1 Go ; détruite à la fin de l'exercice |
| Réseau des nœuds (E03) | quatre cartes sur les VNets `vmgmt`, `vcoro`, `vstopub`, `vstoclu` ; une cinquième **directement** sur `vmbr1`, sans étiquette, `trunks=99` |
| Droit à ajouter | `wb-tofu@pve` : rôle `PVESDNUser` sur `/sdn/zones/localnetwork/vmbr1` (utilisation d'un pont hors SDN) |
| ISO | `proxmox-ve_9.2-1.iso`, `https://enterprise.proxmox.com/iso/`, signature détachée `proxmox-ve_9.2-1.iso.asc` ; clés de publication de Proxmox : « trixie » `24B3 0F06 ECC1 836A 4E5E FECB A7BC D142 0BFE 778E`, « bookworm » `F4E1 36C6 7CDC E41A E6DE 6FC8 1140 AF8F 639E 0C39` (page « Downloads » du wiki) ; dépôt sur `hdd-bulk` |
| Outil de préparation | paquets `proxmox-auto-install-assistant` et `xorriso` (dépôt Proxmox déjà configuré sur `pve01`) |

**Travail demandé**

*A. Le processeur et le noyau (lecture seule)*

1. Sur `pve01`, vérifie que le processeur expose les extensions de virtualisation et la traduction d'adresses de second niveau (EPT), puis lis le paramètre d'imbrication :
   ```
   root@pve01:~# lscpu | grep -iE 'model name|virtualization'
   root@pve01:~# grep -oE '\b(vmx|ept)\b' /proc/cpuinfo | sort | uniq -c
   root@pve01:~# cat /sys/module/kvm_intel/parameters/nested
   ```
   Note dans ton journal à quoi sert EPT et ce qu'il change pour un hyperviseur imbriqué.
   > ⚠️ **Attention** : si le paramètre vaut `N`, **ne le change pas maintenant**. L'activer demande de recharger le module `kvm_intel`, donc d'arrêter **toutes** les VMs de `pve01`, socle compris (ou de redémarrer `pve01`). Planifie une fenêtre de maintenance, écris la procédure de retour (retirer le fichier de `/etc/modprobe.d/`) et fais-la valider avant de continuer.

*B. La place*

2. Relève la mémoire disponible de `pve01` et ce que consomment les VMs en marche (`free -g`, `pvesh get /nodes/<NOEUD>/qemu --output-format json` filtré avec `jq`). Complète dans ton journal le budget de l'introduction avec **tes** chiffres, y compris l'ARC de ZFS de `pve01` s'il en a un, et les VMs personnelles éventuelles.
3. Arrête `ceph01-03` en suivant la procédure d'arrêt complet de `ceph-par1` du module 08. Vérifie l'état des trois VMs.

*C. La preuve sur une VM jetable*

4. Crée la VM 2099 à la main (c'est une VM jetable, hors du chemin imposé) : clone lié de l'image courante, CPU `host`, cloud-init avec ta clé et le DHCP, pool `lab`, étiquette `env-m09`. Démarre-la et connecte-toi.
5. Dans la VM, vérifie la présence de `/dev/kvm` et du drapeau `vmx`. Arrête la VM, passe son CPU au type de l'image dorée (`x86-64-v2-AES`), redémarre, refais la vérification. Explique la différence.
6. Détruis la VM 2099.

*D. Le réseau, vu d'en dessous*

7. Vérifie que `vmbr1` est VLAN-aware et en MTU 9000, et que les quatre VNets que les nœuds utiliseront existent dans la zone `lab` avec leur VLAN (`pvesh get /cluster/sdn/vnets`). Réponds dans ton journal :
   - une carte branchée sur le VNet `vcoro` : qui pose l'étiquette 32, `pve01` ou le nœud ? et pour la carte `trunks=99` sur `vmbr1` ?
   - pourquoi limiter le *trunk* au VLAN 99 plutôt que tout laisser passer ?
   - le pare-feu de Proxmox VE active par défaut un **filtrage MAC** (`macfilter`) sur les cartes dont le pare-feu est activé : que deviendraient les trames des invités imbriqués ? Où le désactiveras-tu ?

*E. Le droit d'OpenTofu sur `vmbr1`*

8. Les nœuds seront créés par le jeton `wb-tofu@pve!tofu`, qui a des droits sur les VNets utilisés (M05-E03) mais pas sur un pont hors SDN. Vérifie ses droits sur `ssd-lab` et `hdd-bulk`, puis ajoute le droit d'utiliser `vmbr1`.
   > ⚠️ **Attention** : c'est une modification des droits de `pve01`. Elle est limitée (un rôle prédéfini, un chemin), mais note-la dans le registre des accès. Retour arrière : `pveum acl delete` avec les mêmes paramètres.

*F. L'ISO, vérifiée*

9. Étends `outils/deposer-iso.sh` de `plateforme/images` d'une famille `proxmox-ve` (version en paramètre, 9.2-1 par défaut). Particularité : Proxmox ne signe pas un fichier de sommes mais **l'ISO elle-même** (signature détachée). Exigences : vérification avec le trousseau APT de Proxmox **déjà présent** sur `pve01` (aucune clé importée d'Internet), signature exigée d'une des deux clés attendues (empreinte complète), rien de visible sous le nom final tant que la signature n'est pas valide, script relançable. MR, pipeline (ShellCheck), puis lance-le sur `pve01`.
10. Installe l'outil de préparation sur `pve01`.
    > ⚠️ **Attention** : deux paquets ajoutés à `pve01` (aucun service). Lis d'abord la simulation (`apt install --simulate`) : rien d'autre ne doit être installé ou mis à jour. Retour arrière : `apt purge` des deux paquets.
11. Vérifie la version de l'outil (`proxmox-auto-install-assistant --version`) : elle doit connaître le format de fichier de réponse de la 9.2 (clés *kebab-case*). Lis son aide (`--help`, puis `prepare-iso --help`).

**Critères de réussite**
- [ ] `pve01` expose VMX et l'imbrication est active ; ton journal explique EPT et le rôle du type de CPU.
- [ ] Au moins 40 Gio de mémoire sont disponibles sur `pve01` ; `ceph01-03` sont arrêtées.
- [ ] La VM 2099 a été créée, testée avec les deux types de CPU, puis détruite.
- [ ] `wb-tofu@pve` peut utiliser `vmbr1`, et accède à `ssd-lab` et `hdd-bulk`.
- [ ] `deposer-iso.sh` (branche `main` de `plateforme/images`) dépose une ISO Proxmox VE dont la signature a été vérifiée ; `proxmox-ve_9.2-1.iso` est sur `hdd-bulk`.
- [ ] `proxmox-auto-install-assistant` et `xorriso` sont installés sur `pve01`.

**Vérification** : `lab/bin/check 09 02`

<details><summary>Indice 1</summary>

Le paramètre `nested` se lit dans `/sys/module/…/parameters/` ; il se fixe de façon persistante par une ligne `options kvm-intel nested=Y` dans `/etc/modprobe.d/`. Le CPU d'une VM se change avec `qm set <VMID> --cpu <type>` ; l'effet n'apparaît qu'après un arrêt complet (un redémarrage depuis l'invité ne suffit pas).
</details>

<details><summary>Indice 2</summary>

Depuis Proxmox VE 8, l'accès à un pont qui n'est pas un VNet du SDN se contrôle sur le chemin `/sdn/zones/localnetwork/<pont>` (et `/<pont>/<vlan>` pour un VLAN précis). `pveum acl modify <chemin> --tokens … --roles …` ou `--users …`.
</details>

<details><summary>Indice 3</summary>

`gpgv --keyring <trousseau> --status-fd 1 <signature> <fichier>` vérifie sans base de confiance et écrit une ligne `[GNUPG:] VALIDSIG <empreinte> …` par signature valide. Sur Proxmox VE 9, le trousseau APT est fourni par le paquet `proxmox-archive-keyring` (`dpkg -L proxmox-archive-keyring`). L'ISO 9.x porte deux signatures : un trousseau qui ne contient qu'une des deux clés en valide une et signale l'autre comme inconnue.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Nested Virtualization » du wiki de Proxmox et la documentation du noyau sur KVM imbriqué (`Documentation/virt/kvm/x86/running-nested-guests.rst`). Que change l'option `+hv-evmcs` pour un hyperviseur Hyper-V imbriqué ? Pourquoi ne la prend-on pas ici ?

---

### M09-E03 — Installer Proxmox VE sans clavier  `LAB` `★★`

> **Ticket PLAT-1003** — *De : Claire Morel*
> Je ne veux plus jamais voir quelqu'un installer un hyperviseur en cliquant dans un assistant, un mot de passe sur un post-it. Le jour où un nœud meurt, on le recrée **depuis le code** : la VM, l'installation, la configuration. Commence par deux nœuds, `hv01` et `hv02`. Ils doivent être dans NetBox et le DNS comme le reste du lab, et je veux qu'on puisse s'y connecter sans accepter une empreinte SSH les yeux fermés.

**Objectifs pédagogiques**
- Utiliser l'installateur automatique de Proxmox VE : fichier de réponse, modes de récupération, préparation d'ISO.
- Déclarer des VMs qui démarrent sur une ISO (et non clonées d'une image) avec OpenTofu, y compris leur fiche NetBox et leurs noms DNS.
- Rendre stables ce dont dépend la suite : adresses MAC, noms d'interfaces, numéros de série des disques.
- Écrire un rôle Ansible qui modifie le réseau d'un hôte distant sans risquer de le perdre.

**Prérequis** : M09-E02 ; M05-E27 (état chiffré, `outils/charger-acces.sh`) ; M06-E13 et E14 (NetBox et PowerDNS par OpenTofu) ; M06-E19 (rôle `ssh_ca_hote`) ; M04-E30 (Vault à deux identités).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VMs | `hv01` (2091), `hv02` (2092) sur `pve01` : pool `lab`, étiquettes `env-m09` et `hv-par1`, CPU `host` 4 cœurs, 12 Go **sans ballon**, pas de démarrage automatique avec `pve01`, console série + écran VGA |
| Disques | `scsi0` 32 Go `local-nvme` (série `hvNN-systeme`) ; `scsi1`, `scsi2` 48 Go `ssd-lab` (`hvNN-osd1`, `hvNN-osd2`) ; `scsi3` 32 Go `ssd-lab` (`hvNN-zfs`) ; contrôleur `virtio-scsi-single`, `discard`, `iothread`, `ssd` |
| Cartes (dans cet ordre) | `net0` `vmgmt` ; `net1` `vcoro` ; `net2` `vstopub` MTU 9000 ; `net3` `vstoclu` MTU 9000 ; `net4` `vmbr1` `trunks=99` ; toutes virtio, **pare-feu désactivé**, MAC `02:4d:53:09:NN:0K` (`NN` = numéro du nœud en hexadécimal sur deux chiffres, `K` = numéro de carte) |
| Démarrage | lecteur `ide2` = `hdd-bulk:iso/pve92-auto-hvNN.iso` ; ordre `scsi0` puis `ide2` |
| Installation | ext4 + LVM-thin sur le seul disque `hvNN-systeme` (swap 2 Go, racine 12 Go, 2 Go libres dans le groupe de volumes) ; clavier et pays `fr`, fuseau `Europe/Paris`, courriel `plateforme@medisphere.internal` ; adresse statique MGMT `10.10.10.5N/24`, passerelle 10.10.10.1, DNS 10.10.20.10 ; noms `nic0` à `nic4` épinglés sur les MAC ; clé SSH de `adm01` pour root |
| Secrets | mot de passe root des nœuds : `~/.config/workbook/hv-root.pass` (600) sur `adm01` et `vault_hv_root_mot_de_passe` (Vault `critique`, `group_vars/hv_par1/vault-critique.yml`) |
| Code | `plateforme/infra` : `envs/hv/` (configuration OpenTofu, données des nœuds dans `noeuds.auto.tfvars.json`), `envs/hv/installation/` (modèle du fichier de réponse, script de préparation des ISO) ; `plateforme/ansible` : rôle `pve_noeud`, `inventories/lab/hv.yml` (groupe `hv_par1`), `playbooks/hv.yml` |
| NetBox | VM dans le cluster NetBox `pve01`, étiquette `env-m09` (à créer d'abord dans les données de modélisation, M06-E05 : le compte d'OpenTofu ne crée pas d'étiquettes), interfaces `nic0` à `nic4`, adresses imposées par le plan ; nom DNS sur l'adresse MGMT seulement |
| Réseau du nœud (rôle) | `vmbr0` sur `nic0` (MGMT) ; `nic1` 10.10.32.5N (MTU 1500) ; `nic2` 10.10.30.7N et `nic3` 10.10.31.7N (MTU 9000) ; `vmbr1` VLAN-aware sur `nic4`, sans adresse ; ligne `source /etc/network/interfaces.d/*` conservée (le SDN du cluster y écrira, M09-E16) |
| Autres réglages (rôle) | dépôt `pve-no-subscription` (deb822), aucun dépôt à abonnement actif ; résolveurs 10.10.20.10 et 10.10.20.16 ; chrony vers 10.10.10.1 ; ARC de ZFS plafonné à 1 Gio ; getty sur `ttyS0` ; SSH root par clé seulement ; fragment cloud-init `medisphere-agent.yaml` (agent QEMU des invités) dans `/var/lib/vz/snippets/` |

**Travail demandé**

*A. Comprendre l'installateur*

1. Lis la page « Automated Installation » du wiki de Proxmox. Note dans ton journal : les trois modes de récupération du fichier de réponse (`iso`, `partition`, `http`), ce que chacun exige du réseau au moment de l'installation, et pourquoi le mode **`iso`** (une ISO par nœud) est retenu ici alors que le mode `http` serait plus élégant. Que contient une ISO préparée, et qui peut la lire sur `pve01` ?

*B. Les secrets*

2. Génère le mot de passe root des nœuds (32 caractères aléatoires) dans `~/.config/workbook/hv-root.pass`, en 600, sans qu'il passe par l'historique ni par un argument. Range-le dans Vault `critique` et inscris-le au registre des secrets. Seule son **empreinte** ira dans le fichier de réponse.

*C. Le fichier de réponse et les ISO*

3. Écris `envs/hv/installation/reponse.toml.modele` (marqueurs remplacés nœud par nœud) et `envs/hv/installation/preparer-iso.sh`. Exigences du script :
   - les données d'un nœud (numéro, adresses) viennent de `envs/hv/noeuds.auto.tfvars.json`, **le même fichier** que lira OpenTofu ; les MAC se calculent de la même façon des deux côtés ;
   - l'empreinte du mot de passe est calculée à partir du fichier 600, sans que le mot de passe apparaisse dans `ps` ;
   - le fichier de réponse rempli n'existe que dans un dossier 700, ne touche le disque de `pve01` que le temps de la préparation, et est **validé** (`validate-answer`) avant de servir ;
   - l'ISO produite n'apparaît sous son nom final que si la préparation a réussi ;
   - aucun marqueur ne doit rester dans un fichier de réponse.
4. Prépare les ISO de `hv01` et `hv02`. Contrôle l'une d'elles avec la sous-commande d'inspection de l'outil : quels champs sont masqués, et pourquoi ?

*D. Les VMs*

5. Ajoute l'étiquette `env-m09` aux données de modélisation NetBox (`plateforme/outils`, M06-E05) et applique-les.
6. Écris la configuration `envs/hv/` (fichiers habituels de M05, chiffrement de l'état, backend `envs/hv/terraform.tfstate`) : les nœuds (un `for_each` sur les données du JSON), leur fiche NetBox et leurs noms DNS. La configuration refuse un nœud dont le VMID ou les adresses s'écartent du plan, et un VLAN du *trunk* autre que 99.
7. Charge tes accès (`outils/charger-acces.sh`, puis `netbox-tofu.env` et `powerdns-api.env`), lance `tofu plan`, relis-le (cinq cartes par nœud, dans l'ordre, MAC, séries de disques, pare-feu, ordre de démarrage), puis applique. Ouvre la console noVNC de `hv01` dans l'interface de `pve01` et **regarde** l'installation se dérouler, sans toucher au clavier. Combien de temps dure-t-elle ? Que se passe-t-il au redémarrage ?

*E. Le premier contact*

8. Ajoute les alias `hv01`, `hv02` (puis `hv03`) à `~/.ssh/config` de `adm01` (`User root`). Avant la première connexion, lis l'empreinte de la clé d'hôte ed25519 **sur la console** du nœud (connexion `root` avec le mot de passe), puis compare-la à celle que présente le nœud à `adm01`. Pourquoi cette étape disparaîtra-t-elle au prochain passage d'Ansible ?

*F. Le rôle `pve_noeud`*

9. Écris le rôle `pve_noeud`, l'inventaire `inventories/lab/hv.yml` et le playbook `playbooks/hv.yml` (rôles `medisphere.socle.ca_lab`, `pve_noeud`, `ssh_ca_hote`, **un nœud à la fois**). Exigences du rôle :
   - il commence par des **contrôles d'entrée** et ne modifie rien s'ils échouent : bon nœud, Proxmox VE 9.2, nom résolu vers l'adresse MGMT, cinq cartes aux MAC attendues, `/dev/kvm` présent ;
   - il retire tout dépôt à abonnement **sans** supprimer un fichier de sources qui vise le dépôt sans abonnement (Ceph en écrira un en M09-E10) ;
   - il règle les résolveurs **par l'API locale** du nœud plutôt qu'en écrivant `/etc/resolv.conf` (pourquoi ?) ;
   - il possède `/etc/network/interfaces` : syntaxe vérifiée avant usage, et un **retour automatique** à l'ancienne configuration est armé avant le rechargement, puis désarmé seulement si le nœud répond encore et que ses adresses sont en place ;
   - il vérifie qu'une trame de 9000 octets passe sans fragmentation sur le VLAN 30 ;
   - `ansible-lint` (profil `production`) vert ; un second passage donne `changed=0`.
   Pas de scénario Molecule pour ce rôle : explique pourquoi dans son `README.md`, et ce qui le teste à la place.
10. Lance le playbook en `--check --diff` sur `hv01`, lis le diff, puis applique. Vérifie la console série depuis `pve01` (`qm terminal 2091`).
11. Mets à jour l'inventaire du socle (section des environnements de module) et le registre des secrets. La matrice des flux ne change pas : dis pourquoi.

**Critères de réussite**
- [ ] Les VMs 2091 et 2092 sont déclarées dans l'état `hv` de `plateforme/infra` et conformes au contexte (CPU, mémoire, disques et leurs séries, cartes et leurs MAC, MTU, *trunk*, pare-feu, ordre de démarrage).
- [ ] Les ISO `pve92-auto-hv01.iso` et `pve92-auto-hv02.iso` sont sur `hdd-bulk` ; le modèle de fichier de réponse versionné ne contient aucun mot de passe et n'utilise que des clés *kebab-case*.
- [ ] `hv01` et `hv02` exécutent Proxmox VE 9.2, se résolvent en A et PTR, sont décrits dans NetBox avec leur IP primaire.
- [ ] Depuis `adm01`, `ssh hv01` fonctionne en root par clé, l'hôte présentant un certificat signé par la CA SSH ; l'authentification par mot de passe est refusée.
- [ ] Sur chaque nœud : `nic0` à `nic4` aux bonnes MAC, adresses Corosync et Ceph en place, MTU 9000 sur les cartes Ceph seulement, `vmbr1` VLAN-aware sur `nic4`, dépôt sans abonnement, heure synchronisée sur 10.10.10.1, ARC plafonné.
- [ ] Le rôle `pve_noeud`, l'inventaire et le playbook sont sur `main` ; un second passage donne `changed=0`.

**Vérification** : `lab/bin/check 09 03`

<details><summary>Indice 1</summary>

Dans le fichier de réponse, la carte d'administration se désigne par un **filtre** sur une propriété udev (`proxmox-auto-install-assistant device-info -t network` sur un système démarré montre lesquelles existent) ; le disque d'installation aussi (`filter.ID_SERIAL`). Les noms d'interfaces se fixent dans `[network.interface-name-pinning]`. Une empreinte de mot de passe au format attendu par `/etc/shadow` se calcule avec `openssl passwd -6 -stdin` (ou `mkpasswd`).
</details>

<details><summary>Indice 2</summary>

Dans `bpg/proxmox`, une VM qui démarre sur une ISO a un bloc `cdrom` (`file_id`, `interface`) et un `boot_order`. Un disque vide au premier démarrage n'est pas amorçable : SeaBIOS passe au périphérique suivant. Les blocs `disk` acceptent un `serial`, les `network_device` un `mac_address`, un `mtu`, des `trunks` et `firewall`. Pour le ballon : `memory.floating`. Un agent QEMU déclaré mais absent fait attendre le fournisseur.
</details>

<details><summary>Indice 3</summary>

Pour le retour automatique du réseau, une minuterie transitoire (`systemd-run --on-active=…`) qui recopie l'ancien fichier et relance `ifreload -a` survit à la perte de la session SSH ; on l'arrête une fois le contrôle réussi. `ifupdown2` sait vérifier la syntaxe d'un fichier sans l'appliquer. Ne gère pas `/root/.ssh/authorized_keys` d'un nœud avec un module qui remplace le fichier : en cluster, ce sera un lien.
</details>

**Pour aller plus loin** (facultatif) : le mode `http` permet **une seule** ISO pour tous les nœuds : le serveur de réponses choisit le fichier d'après l'identité de la machine (MAC, numéro de série) envoyée par l'installateur. Que faudrait-il ajouter au lab (DHCP sur MGMT, option 250 ou enregistrement TXT, certificat du serveur) ? Regarde aussi la section `[post-installation-webhook]` : l'installateur y envoie les clés SSH d'hôte du nouveau système. Quel problème de cet exercice cela résoudrait-il ?

---

### M09-E04 — Former le cluster et ses liens Corosync  `LAB` `★★`

> **Ticket PLAT-1004** — *De : Karim Benali*
> Deux nœuds installés, ce n'est pas un cluster. Crée `hv-par1` avec **deux** liens Corosync : le réseau dédié d'abord, MGMT en secours. Puis je veux que tu casses des choses exprès, dans les nœuds : un lien, puis un nœud entier. Note ce que fait le cluster, combien de temps il met, et ce qu'il refuse de faire. C'est la seule façon de savoir lire `pvecm status` le jour où ce sera la production.

**Objectifs pédagogiques**
- Créer un cluster Proxmox VE et y joindre un nœud, avec des liens Corosync explicites.
- Lire l'état d'un cluster : appartenance, quorum, liens knet, `/etc/pve`.
- Observer la bascule d'un lien et la perte du quorum, et comprendre le geste de dernier recours `pvecm expected`.

**Prérequis** : M09-E03.
**Durée indicative** : 2 h.

**Contexte technique**
- Cluster `hv-par1`, créé sur `hv01` ; lien 0 : 10.10.32.5N (VLAN 32, `nic1`) ; lien 1 : 10.10.10.5N (MGMT, `vmbr0`).
- Adhésion de `hv02` par l'API de `hv01` (mot de passe root de `hv01` saisi au clavier, empreinte du certificat de `hv01` à vérifier).
- Ancre TLS du cluster, à copier sur `adm01` : `/etc/pve/pve-root-ca.pem` → `~/.config/workbook/hv-par1-root-ca.pem` (fichier public, 644).
- Table nftables d'essai dans les nœuds : `m09_essai` (jamais sur `pve01`).

**Travail demandé**

*A. Avant de créer*

1. Vérifie sur les deux nœuds ce dont Corosync a besoin : horloges synchronisées (`chronyc tracking`), noms résolus vers MGMT, adresses du VLAN 32 joignables d'un nœud à l'autre, **aucun invité** sur `hv02`. Lis `man pvecm` (sous-commandes `create`, `add`, `status`, `nodes`, `expected`).

*B. Créer et joindre*

2. Sur `hv01` :
   ```
   root@hv01:~# pvecm create hv-par1 --link0 10.10.32.51 --link1 10.10.10.51
   root@hv01:~# pvecm status
   root@hv01:~# cat /etc/pve/corosync.conf
   ```
   Dans `corosync.conf`, repère : le nom du cluster, la version de configuration, les deux `interface`/`linknumber`, `link_mode`, `secauth`, les `ring0_addr`/`ring1_addr` du nœud, la section `quorum`. Où est la clé d'authentification de Corosync ?
3. Relève l'empreinte SHA-256 du certificat de l'interface de `hv01` (`pvenode cert info`). Sur `hv02` :
   ```
   root@hv02:~# pvecm add 10.10.10.51 --link0 10.10.32.52 --link1 10.10.10.52
   ```
   Compare l'empreinte affichée à celle relevée **avant** de l'accepter. Pourquoi cette commande demande-t-elle le mot de passe de `hv01` et pas celui de `hv02` ?
4. Observe le résultat : `pvecm status` et `pvecm nodes` sur les deux nœuds, `ls /etc/pve/nodes`, le journal de Corosync (`journalctl -u corosync -b`), l'état des liens (`corosync-cfgtool -s`). Qu'est devenu le certificat de l'interface de `hv02` ? Et `/root/.ssh/authorized_keys` ?
5. Copie l'ancre du cluster sur `adm01` (fichier public). Interroge l'API d'un nœud en TLS vérifié avec cette seule ancre (`curl --cacert … https://hv02.par1.medisphere.internal:8006/api2/json/version` : une réponse 401 sans jeton est **normale** ; ce qui compte, c'est que la vérification TLS réussisse). Importe-la dans ton navigateur et connecte-toi à l'interface.

*C. Couper un lien*

6. Dans `hv02`, coupe le lien 0 en bloquant Corosync sur `nic1` dans les deux sens, en suivant le journal de Corosync sur `hv01` dans un autre terminal :
   ```
   root@hv02:~# nft add table inet m09_essai
   root@hv02:~# nft add chain inet m09_essai entree '{ type filter hook input priority -10; }'
   root@hv02:~# nft add chain inet m09_essai sortie '{ type filter hook output priority -10; }'
   root@hv02:~# nft add rule inet m09_essai entree iifname nic1 udp dport 5405-5412 drop
   root@hv02:~# nft add rule inet m09_essai sortie oifname nic1 udp dport 5405-5412 drop
   ```
   Relève : l'état des liens (`corosync-cfgtool -s` sur les deux nœuds), `pvecm status`, ce que dit le journal et combien de temps la détection a pris. Le cluster a-t-il perdu quelque chose ?
7. Rétablis le lien (`nft delete table inet m09_essai`) et vérifie que le lien 0 redevient le lien actif. Explique, avec la documentation de `pvecm` (section sur la redondance), pourquoi le trafic revient sur le lien 0.

*D. Perdre un nœud*

8. Arrête `hv02` proprement depuis `pve01` (`qm shutdown 2092`). Sur `hv01` : `pvecm status` (votes attendus, votes présents, quorum, drapeaux). Essaie de créer un fichier dans `/etc/pve` et de modifier la description du nœud dans l'interface. Que se passe-t-il, et pourquoi est-ce **voulu** ?
9. Geste de dernier recours, à comprendre avant d'en avoir besoin :
   ```
   root@hv01:~# pvecm expected 1
   ```
   > ⚠️ **Attention** : cette commande dit à `hv01` « tu es seul, tu as la majorité ». Si `hv02` tournait encore de son côté (lien coupé au lieu d'un arrêt), chacun croirait avoir le quorum : c'est exactement le *split-brain* que le quorum interdit. Ici, `hv02` est **arrêté** : vérifie-le sur `pve01` avant de lancer la commande. En production, ce geste ne se fait qu'après avoir **prouvé** que l'autre nœud est éteint (console, alimentation coupée).

   Refais l'essai d'écriture dans `/etc/pve`. Puis redémarre `hv02` (`qm start 2092`) et observe le retour à la normale : les votes attendus reviennent-ils d'eux-mêmes à 2 ?
10. Note dans ton journal, pour chaque expérience : symptôme, commande qui le montre, durée, ce que le cluster a refusé de faire.

**Critères de réussite**
- [ ] Le cluster `hv-par1` existe, avec `hv01` et `hv02`, transport knet et authentification active ; il a le quorum.
- [ ] Chaque nœud a deux liens : lien 0 sur 10.10.32.5N, lien 1 sur 10.10.10.5N ; tous les pairs sont connectés sur les deux liens.
- [ ] La table `m09_essai` a disparu des deux nœuds ; les votes attendus ne sont pas forcés.
- [ ] L'ancre du cluster est sur `adm01` et l'API d'un nœud se joint en TLS vérifié.
- [ ] Ton journal décrit les deux expériences (lien coupé, nœud arrêté) et ce que fait `pvecm expected`.

**Vérification** : `lab/bin/check 09 04`

<details><summary>Indice 1</summary>

`pvecm add` contacte l'**API** du nœud existant : il lui faut l'identité root de ce nœud, et une confiance dans son certificat (d'où l'empreinte). L'option `--use_ssh` revient à l'ancienne méthode par SSH. Au moment de l'adhésion, la configuration `/etc/pve` du nœud qui rejoint est **remplacée** par celle du cluster.
</details>

<details><summary>Indice 2</summary>

`corosync-cfgtool -s` donne l'état de chaque lien vu du nœud local, pair par pair. `corosync-quorumtool -s` montre les détails de *votequorum* (votes attendus, votes les plus hauts attendus, quorum). Une fois le nœud manquant revenu, regarde la ligne `Highest expected`.
</details>

**Pour aller plus loin** (facultatif) : lis `man votequorum` sur les options `two_node`, `wait_for_all`, `last_man_standing` et `auto_tie_breaker`. Laquelle aurait permis à un cluster à deux nœuds de survivre à l'arrêt propre de l'un, et à quel prix ? Pourquoi Proxmox VE recommande-t-il plutôt un QDevice ?

---

### M09-E05 — Deux nœuds et un arbitre : le QDevice  `LAB` `★★★`

> **Ticket PLAT-1005** — *De : Claire Morel* — *Copie : Sophie Laurent, Nadia Roussel*
> Tu as vu ce que fait un cluster à deux nœuds quand l'un s'arrête : il se fige. Tant que `hv03` n'existe pas, il nous faut un troisième vote, **ailleurs** : PAR2 est le bon endroit, et `pbs01` y tourne déjà. Sophie accepte, à conditions : fiche de changement, port filtré au plus juste, aucun accès laissé ouvert après l'installation, et la preuve que les sauvegardes n'ont pas souffert. Nadia veut que ce soit fait hors de la fenêtre des sauvegardes de la nuit.

**Objectifs pédagogiques**
- Installer et raccorder un QDevice (`corosync-qnetd`, `corosync-qdevice`) et comprendre ses votes.
- Ouvrir un flux inter-sites de façon traçable (matrice des flux, pare-feu de la cible).
- Conduire un changement sur un hôte sensible : fiche, simulation, accès temporaire retiré, vérification de non-régression.

**Prérequis** : M09-E04 ; M00 (pare-feu nftables de `pbs01`, tunnel `wg0`) ; M04-E17 (matrice des flux en code) ; M07-E24 (même matrice sur `gw02`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- `corosync-qnetd` sur `pbs01` (paquet Debian, écoute TCP **5403**) ; `corosync-qdevice` sur `hv01` et `hv02` ; raccordement par `pvecm qdevice setup 10.20.10.10` lancé sur **un** nœud, tous les nœuds en ligne.
- Cette commande se connecte en SSH, en `root`, de ce nœud vers `pbs01`, pour y installer les certificats du QDevice. Accès **temporaire** : la clé publique de root de `hv01` est ajoutée à `/root/.ssh/authorized_keys` de `pbs01` pour l'opération, puis retirée.
- Trafic : `hv01`/`hv02` (10.10.10.51-52, MGMT) → `gw01`/`gw02` → `wg0` → `pbs01` (10.20.10.10). `pbs01` filtre ses entrées en politique `drop` (nftables, M00).
- Fiche de changement : `docs/socle/changements/CHG-1005-qdevice-pbs01.md` (modèle des fiches de M06).

> ⚠️ **Attention** : `pbs01` est le serveur de sauvegarde de tout le lab. Avant d'y toucher : vérifie qu'aucune sauvegarde n'est en cours (`proxmox-backup-manager task list`), garde une session SSH ouverte pendant tout changement de pare-feu, et copie `/etc/nftables.conf` et `/root/.ssh/authorized_keys`. Retour arrière complet : `pvecm qdevice remove` sur un nœud, puis sur `pbs01` arrêt et purge de `corosync-qnetd`, recopie des deux fichiers, `nft -f /etc/nftables.conf`.

**Travail demandé**

1. **La fiche.** Rédige CHG-1005 avant toute action : objet, systèmes touchés, risques et parades, étapes, retour arrière, vérifications après changement. Fais-la relire (par toi-même le lendemain, à défaut).
2. **La matrice.** Ajoute le flux à `host_vars/gw01/pare_feu.yml` (une définition pour les nœuds, une règle avec motif et référence), MR, pipeline sur les deux passerelles. En relisant la matrice, regarde la règle « bastion (MGMT) vers tout le lab et PAR2 » : que permet-elle aux nœuds `hvNN` ? Le QDevice aurait-il fonctionné sans ta règle ? Inscris ce que tu constates au registre des écarts, avec une proposition (ne la mets pas en œuvre ici).
3. **`pbs01`.** Simule puis installe `corosync-qnetd` ; lis ce que le paquet a créé (service, base de certificats NSS). Ajoute à l'entrée de son pare-feu une règle qui n'ouvre le port 5403 qu'aux adresses des nœuds (`nft -c -f` avant chargement).
4. **Les nœuds.** Installe `corosync-qdevice` sur `hv01` et `hv02`. Ajoute temporairement la clé publique de root de `hv01` sur `pbs01`, et vérifie la connexion `root@hv01 → root@pbs01`.
5. **Le raccordement.** Sur `hv01`, `pvecm qdevice setup 10.20.10.10`. Puis observe : `pvecm status` (section *Membership*, drapeaux, votes), `corosync-qdevice-tool -s` sur un nœud, `corosync-qnetd-tool -l` sur `pbs01`, la section `quorum` de `/etc/pve/corosync.conf`. Quel algorithme a été choisi, et combien de votes porte le QDevice ?
6. **L'accès temporaire.** Retire de `authorized_keys` de `pbs01` toute clé ajoutée pour l'opération (la tienne et, le cas échéant, celles que la commande a ajoutées). Vérifie que `hv01` ne peut plus s'y connecter.
7. **Les épreuves**, en suivant `pvecm status` sur le nœud qui reste :
   - arrête `hv02` depuis `pve01` : `hv01` garde-t-il le quorum ? peux-tu écrire dans `/etc/pve` ? Redémarre `hv02` ;
   - sur `hv01` **et** `hv02`, bloque la sortie vers le port TCP 5403 (table `m09_essai`) : le cluster perd-il le quorum quand seul l'arbitre manque ? Que montrent les drapeaux ? Retire les tables.
8. **La non-régression.** Vérifie que `pbs01` fait toujours son métier : dernière sauvegarde nocturne réussie, une sauvegarde manuelle d'une petite VM du socle vers `pbs-par2` réussie, datastore `ds-lab` en bon état. Clos la fiche.

**Critères de réussite**
- [ ] `pvecm status` montre `Flags: Quorate Qdevice` et 3 votes ; le QDevice est vivant et vote pour les deux nœuds.
- [ ] `corosync-qdevice` est actif et activé sur `hv01` et `hv02` ; `corosync-qnetd` est actif sur `pbs01` et voit `hv-par1`.
- [ ] Le port 5403 de `pbs01` n'est ouvert qu'aux adresses des nœuds ; la règle de la matrice (référence M09-E05) est chargée sur la bordure.
- [ ] Aucune clé de nœud ne reste dans `/root/.ssh/authorized_keys` de `pbs01`.
- [ ] CHG-1005 est rédigée et close ; l'écart constaté sur la règle du bastion est inscrit au registre.

**Vérification** : `lab/bin/check 09 05`

<details><summary>Indice 1</summary>

La documentation de `pvecm` (section « Corosync External Vote Support ») liste les prérequis : paquets de part et d'autre, accès SSH par clé de root vers l'hôte externe, tous les nœuds en ligne. Les nœuds Proxmox VE utilisent la paire de clés `/root/.ssh/id_rsa` de root pour leurs échanges SSH.
</details>

<details><summary>Indice 2</summary>

Dans la sortie de `pvecm status`, la colonne *Qdevice* de chaque nœud se lit lettre par lettre : `A`/`NA` (le QDevice est-il joignable ?), `V`/`NV` (vote-t-il pour ce nœud ?), `MW`/`NMW` (*master wins*). `man corosync-qdevice` décrit les algorithmes `ffsplit` et `lms`.
</details>

<details><summary>Indice 3</summary>

Pour la règle de `pbs01`, place-la avec les autres règles d'entrée **avant** une éventuelle règle finale de journalisation et de rejet, et limite-la aux nouvelles connexions des trois adresses (`ip saddr { … }`) : les réponses passent déjà par la règle d'état établi.
</details>

**Pour aller plus loin** (facultatif) : un même `corosync-qnetd` peut arbitrer plusieurs clusters. Que faudrait-il surveiller sur `pbs01` si c'était le cas en production ? Que se passe-t-il pour `hv-par1` si le tunnel `wg0` tombe pendant une maintenance de `hv02` ?

---

### M09-E06 — Stockages et réseaux des invités  `LAB` `★★`

> **Ticket PLAT-1006** — *De : Karim Benali*
> Le cluster tient debout ; il ne sait encore rien héberger proprement. Avant Ceph (palier 2), je veux un stockage local **identique** sur chaque nœud, pour la réplication plus tard ; un endroit pour les images et les fragments cloud-init ; et un template Debian 13 pour les invités, fabriqué par un script qu'on pourra rejouer le jour où on reconstruira le cluster. Les invités vont sur le VLAN 99, comme le bac à sable : je veux qu'ils prennent une adresse du DHCP du socle sans qu'on ait touché à `pve01`.

**Objectifs pédagogiques**
- Distinguer la configuration de stockage (commune au cluster) de ce qui existe réellement sur chaque nœud.
- Créer un pool ZFS identique sur plusieurs nœuds et le déclarer une seule fois, avec ses restrictions de nœuds.
- Préparer les contenus d'un stockage (images à importer, fragments cloud-init) et fabriquer un template par un script rejouable.

**Prérequis** : M09-E04 (M09-E05 conseillé) ; M00 (template cloud-init de `pve01`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Disque ZFS de chaque nœud : `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_hvNN-zfs` (32 Go). Pool `tank` (`ashift=12`, compression `lz4`) ; stockage `zfs-local` (type `zfspool`, contenus `images` et `rootdir`, provisionnement fin), restreint aux nœuds qui ont le pool.
- Disques `hvNN-osd1` et `hvNN-osd2` : réservés à Ceph (M09-E10), **ne pas y toucher**.
- Stockage `local` (`/var/lib/vz` de chaque nœud) : ajouter les contenus `import` (images de disque à importer) et `snippets` (fragments cloud-init).
- Image : `https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2`, sommes dans `SHA512SUMS` du même dossier.
- Template : VMID **199** `tpl-nested-debian13` sur `hv01` (`local-lvm`) : 1 vCPU, 1 Go, CPU `x86-64-v2-AES`, disque de 8 Go, carte sur `vmbr1` VLAN 99, cloud-init (compte `admin`, clé de `adm01`, DHCP, fragment vendor `local:snippets/medisphere-agent.yaml` posé par `pve_noeud`), agent QEMU, console série.
- Script : `outils/hv/creer-tpl-nested.sh` dans `plateforme/outils`, lancé en root sur un nœud depuis `adm01` (`ssh hv01 'bash -s' -- … < outils/hv/creer-tpl-nested.sh`).

**Travail demandé**

1. **État des lieux.** Sur les deux nœuds : `pvesm status`, `cat /etc/pve/storage.cfg`, `lsblk -o NAME,SIZE,SERIAL,FSTYPE`. Pourquoi `storage.cfg` est-il identique partout ? `local-lvm` de `hv02` existe-t-il encore après l'adhésion (souviens-toi : sa configuration a été remplacée) ? Que signifierait l'option `shared 1` posée sur un stockage qui ne l'est pas ?
2. **ZFS.** Crée le pool `tank` sur chaque nœud, à partir du disque désigné par son numéro de série, **sans** déclarer de stockage à ce moment (par l'API du nœud ou par `zpool create`). Puis déclare **une seule fois** le stockage `zfs-local`, restreint à `hv01` et `hv02`. Vérifie qu'il est actif sur les deux nœuds.
3. **La mémoire de ZFS.** Le module `zfs` est maintenant chargé : vérifie que l'ARC est bien plafonné (rôle `pve_noeud`). Que se serait-il passé sans ce plafond, sur un nœud de 12 Go ?
4. **Contenus de `local`.** Ajoute les contenus `import` et `snippets` à `local`. Une seule commande suffit pour tout le cluster : pourquoi ? Les fichiers, eux, sont-ils partagés ? Vérifie que le fragment `medisphere-agent.yaml` est sur chaque nœud.
5. **Le template.** Écris `outils/hv/creer-tpl-nested.sh`. Exigences : vérifie ses prérequis (contenus de `local`, fragment) et s'arrête net s'ils manquent ; télécharge l'image **par l'API du nœud**, avec vérification de la somme SHA-512 par Proxmox lui-même, et ne la retélécharge que si la version publiée a changé ; crée le template 199 conforme au contexte ; refuse d'écraser un VMID 199 existant sans option explicite ; aucune clé ni mot de passe en argument visible. MR dans `plateforme/outils`, puis lance-le sur `hv01`.
6. **Lire le template.** `qm config 199` : retrouve chaque élément du contexte. Pourquoi le CPU `x86-64-v2-AES` plutôt que `host`, alors que tous les nœuds sont identiques ? Pourquoi le fragment cloud-init doit-il exister sur **tous** les nœuds, et pas seulement sur `hv01` ?
7. **Le réseau des invités.** Dessine dans ton journal le chemin d'une trame DHCP d'un futur invité imbriqué jusqu'au serveur Kea : pont et étiquette dans le nœud, carte `net4`, pont de `pve01`, `gw01` (relais), `dns01`. À quels endroits l'étiquette 99 est-elle posée, lue, retirée ?

**Critères de réussite**
- [ ] Sur `hv01` et `hv02`, le pool `tank` est en ligne sur le disque de série `hvNN-zfs` ; les disques OSD sont vierges.
- [ ] `zfs-local` est déclaré une fois (type `zfspool`, pool `tank`, non partagé, restreint aux nœuds qui ont le pool) et actif sur les deux nœuds.
- [ ] L'ARC de ZFS est plafonné à 1 Gio au plus sur chaque nœud.
- [ ] `local` porte les contenus `import` et `snippets` ; le fragment `medisphere-agent.yaml` est présent sur chaque nœud.
- [ ] Le template 199 `tpl-nested-debian13` existe, conforme au contexte ; le script qui le fabrique est sur `main` de `plateforme/outils`.

**Vérification** : `lab/bin/check 09 06`

<details><summary>Indice 1</summary>

L'API de chaque nœud sait créer un pool ZFS sur des disques vierges (`/nodes/<nœud>/disks/zfs`, avec une option pour **ne pas** ajouter de stockage), comme le bouton « Create: ZFS » de l'interface. `pvesm add zfspool … --nodes …` déclare le stockage ; `pvesm set` modifie une déclaration existante.
</details>

<details><summary>Indice 2</summary>

`/nodes/<nœud>/storage/<stockage>/download-url` télécharge un fichier directement sur le nœud, avec `--checksum` et `--checksum-algorithm`. Une image placée dans `import/` s'utilise à la création du disque : `--scsi0 <stockage>:0,import-from=local:import/<fichier>`. Pour une clé SSH, `qm set --sshkeys` attend un **fichier**.
</details>

**Pour aller plus loin** (facultatif) : compare `zfs-local` et `local-lvm` pour héberger des invités (instantanés, clones, réplication, consommation mémoire, comportement quand le volume est plein). Lequel choisirais-tu pour un nœud de production sans Ceph ?

---

### M09-E07 — Premières VMs du cluster et migration  `LAB` `★★`

> **Ticket DEV-1007** — *De : Julien Petit*
> On nous a dit qu'avec le nouveau cluster, une VM pouvait changer de serveur sans s'arrêter. Avant d'y croire, je veux voir. Deux VMs de test pour l'équipe (on y mettra une API de démonstration), joignables en SSH, et une démonstration : une migration pendant qu'on fait un `ping`, avec le nombre de paquets perdus. Et si ça ne marche que dans certains cas, dis-moi lesquels.

**Objectifs pédagogiques**
- Créer des invités par clonage et les retrouver dans la vue du cluster.
- Mesurer une migration hors ligne et une migration à chaud avec disques locaux ; comprendre leurs limites.
- Observer l'effet du pare-feu de l'hôte sur les invités d'un hyperviseur imbriqué.

**Prérequis** : M09-E06 (M09-E05 conseillé).
**Durée indicative** : 2 h.

**Contexte technique**
- Invités : 101 `app01` et 102 `app02`, **clones complets** du template 199, disque sur `zfs-local`, créés sur `hv01` ; 1 Go, adresse DHCP du VLAN 99 (10.10.99.100-199), joignables depuis `adm01` en `admin`.
- Migration : réseau par défaut du cluster (MGMT, à défaut d'un réseau de migration dédié : M09-E27).
- Expérience de pare-feu : sur `pve01`, VM 2092 (`hv02`), carte `net4`. Le pare-feu de centre de données de `pve01` est actif depuis le module 00.

**Travail demandé**

*A. Les invités*

1. Clone le template en `app01` et `app02` (clones complets sur `zfs-local`), démarre `app01`, attends que l'agent réponde, lis son adresse (`qm guest cmd 101 network-get-interfaces`) et connecte-toi depuis `adm01`. Démarre `app02`, vérifie-la, puis arrête-la.
2. Depuis `hv02`, liste les invités du cluster (`pvesh get /cluster/resources --type vm`). Sur quel nœud est chacun ? Essaie `qm config 101` sur `hv02` : que répond-il, et où est physiquement le fichier de configuration de 101 ?

*B. Migrer*

3. **Hors ligne.** Migre `app02` (arrêtée) vers `hv02` (`qm migrate`). Lis le journal de la tâche : qu'est-ce qui a été copié, par quel moyen, en combien de temps ?
4. **À chaud, sans précaution.** Lance une migration à chaud de `app01` vers `hv02` sans autre option. Note le message.
5. **À chaud, avec les disques.** Depuis `adm01`, lance un `ping -D -i 0.2` vers `app01` et laisse-le tourner. Migre `app01` à chaud vers `hv02` en emportant ses disques locaux. Relève dans le journal de la tâche : la durée totale, la phase de copie du disque, la phase de mémoire, l'interruption annoncée (*downtime*). Côté `ping` : combien de paquets perdus ? Fais une seconde mesure dans l'autre sens.
6. Résume pour Julien, en dix lignes au plus : ce qui est démontré, dans quel cas ce serait plus rapide (palier 2), ce qui empêcherait une migration (pense au CPU, aux ISO montées, au stockage absent sur le nœud cible).

*C. Le pare-feu d'en dessous*

7. Expérience, avec `app01` sur `hv02` et un `ping` en cours depuis `adm01` :
   > ⚠️ **Attention** : tu modifies à la main une VM gérée par OpenTofu (`hv02`, VMID 2092) : c'est une dérive volontaire, que tu annuleras par le code. Ne touche qu'à cette VM et qu'à sa carte `net4`. Retour arrière : `tofu apply` de `envs/hv` (carte), puis désactivation du pare-feu de la VM (options).

   Sur `pve01`, active le pare-feu de la VM 2092 dans ses options, puis l'option `firewall=1` de sa carte `net4` uniquement (en reprenant **toute** la définition actuelle de la carte : MAC, pont, *trunks*). Que devient le `ping` ? `app01` renouvelle-t-elle son bail DHCP ? Regarde les options du pare-feu de la VM (`pvesh get /nodes/<NOEUD>/qemu/2092/firewall/options`) : quels **deux** mécanismes bloquent les trames de `app01` ?
8. Annule : `tofu plan` dans `envs/hv` (que propose-t-il ?), `tofu apply`, puis désactive le pare-feu de la VM 2092 dans ses options. Vérifie que le `ping` reprend. Pourquoi OpenTofu n'a-t-il ramené que la carte ?

**Critères de réussite**
- [ ] Les invités 101 `app01` et 102 `app02` existent, clones complets sur `zfs-local`, sur `vmbr1` VLAN 99 ; `app01` tourne.
- [ ] L'agent de `app01` rapporte une adresse du VLAN 99 ; `adm01` la joint en ping et en SSH (`admin`).
- [ ] Au moins une migration réussie de chacun des deux invités figure dans les tâches du cluster.
- [ ] La carte `net4` des VMs 2091 et 2092 n'a plus le pare-feu activé.
- [ ] Ton journal contient les mesures (durées, paquets perdus) et le résumé pour Julien.

**Vérification** : `lab/bin/check 09 07`

<details><summary>Indice 1</summary>

`qm migrate <vmid> <nœud> --online` refuse une VM qui a des disques locaux, à moins de lui demander de les emporter : regarde les options `--with-local-disks` et `--targetstorage` dans `qm help migrate`. Le stockage cible doit exister sur le nœud d'arrivée sous le même nom (sinon, `--targetstorage`).
</details>

<details><summary>Indice 2</summary>

Le journal d'une tâche se lit dans l'interface (double clic sur la tâche) ou par `pvesh get /nodes/<nœud>/tasks/<UPID>/log`. La liste des tâches du cluster : `pvesh get /cluster/tasks`. Pour l'expérience de pare-feu, la définition complète de la carte est dans `qm config 2092` sur `pve01`.
</details>

**Pour aller plus loin** (facultatif) : lis la section « Migration » de `qm` dans le guide d'administration : `migration_type`, `migration_network`, `bwlimit`. Lesquelles changeraient tes mesures ? (M09-E27 y revient.)

---

### M09-E08 — Un troisième nœud  `LAB` `★★`

> **Ticket PLAT-1008** — *De : Claire Morel*
> Le budget mémoire passe : on ajoute `hv03`. Par le même chemin que les deux autres, sans une ligne écrite à la main qui ne soit pas dans le code. Ensuite, l'arbitre de PAR2 n'a plus de raison d'être : je veux `pbs01` rendu à son seul métier, et la fiche de changement fermée proprement. Fais attention à l'ordre des opérations : je ne veux pas d'un cluster sans quorum un seul instant.

**Objectifs pédagogiques**
- Étendre le cluster par le code (OpenTofu, ISO préparée, Ansible) et y joindre un nœud.
- Comprendre pourquoi un QDevice se retire avant d'ajouter un nœud et n'a plus de sens avec un nombre impair de nœuds.
- Étendre un stockage local déjà déclaré à un nouveau nœud.

**Prérequis** : M09-E05, M09-E06.
**Durée indicative** : 1 h 30.

**Contexte technique**
- `hv03` : VMID 2093, MGMT 10.10.10.53, COROSYNC 10.10.32.53, Ceph 10.10.30.73 / 10.10.31.73 ; mêmes caractéristiques que `hv01` et `hv02`.
- Documentation de `pvecm`, FAQ du QDevice : à l'ajout ou au retrait d'un nœud, le QDevice doit d'abord être **retiré** ; il est déconseillé avec un nombre impair de nœuds.
- Fin de vie du QDevice sur `pbs01` dans ce module : service arrêté et désactivé, port 5403 refermé sur `pbs01` et dans la matrice ; le paquet reste installé jusqu'au nettoyage final du module (M09-E46).

**Travail demandé**

1. **L'ordre.** Écris dans ton journal la séquence des opérations, avec, à chaque étape, le nombre de votes attendus et présents et ce qui arriverait si un nœud tombait **à ce moment**. Identifie l'étape la plus fragile et ce que tu vérifies avant de la franchir.
2. **La VM.** Ajoute `hv03` aux données de `envs/hv`, prépare son ISO, relis le plan : il ne doit **rien** changer à `hv01` et `hv02`. Applique, laisse l'installation se faire.
3. **La configuration.** Ajoute `hv03` à l'inventaire `hv.yml`, vérifie son empreinte d'hôte à la première connexion, applique `playbooks/hv.yml` limité à `hv03`.
4. **Le QDevice s'efface.** Vérifie que `hv01` et `hv02` sont en ligne, puis retire le QDevice. Observe `pvecm status`.
5. **L'adhésion.** Joins `hv03` au cluster, avec ses deux liens. Vérifie l'appartenance, les liens et le quorum depuis chacun des trois nœuds.
6. **Le stockage local.** Crée le pool `tank` sur `hv03` et étends `zfs-local` à `hv03`. Vérifie qu'il est actif sur les trois nœuds.
7. **`pbs01`.** Arrête et désactive `corosync-qnetd`, retire la règle 5403 de son pare-feu, retire la règle de la matrice (MR sur `pare_feu.yml`, pipeline). Vérifie qu'une sauvegarde vers `pbs01` fonctionne toujours. Clos CHG-1005 avec la date de fin du QDevice.
8. **L'épreuve.** Arrête `hv03` depuis `pve01` : les deux autres gardent-ils le quorum ? Redémarre-le. Combien de nœuds peut perdre ce cluster, et en quoi est-ce différent de la phase avec QDevice ?

**Critères de réussite**
- [ ] La VM 2093 `hv03` est déclarée dans l'état `hv`, conforme ; `hv03` exécute Proxmox VE 9.2, configuré par `pve_noeud`, avec son certificat SSH d'hôte.
- [ ] Le cluster compte trois nœuds, 3 votes attendus et présents, sans QDevice ; `hv03` a ses deux liens.
- [ ] `corosync-qdevice` est arrêté et désactivé sur les trois nœuds.
- [ ] `tank` existe sur `hv03` et `zfs-local` y est actif.
- [ ] Sur `pbs01`, `corosync-qnetd` est arrêté et désactivé, le port 5403 n'est plus ouvert ; la règle 5403 a quitté la matrice et la bordure.

**Vérification** : `lab/bin/check 09 08`

<details><summary>Indice 1</summary>

Un `tofu plan` qui propose de modifier `hv01` ou `hv02` alors que tu n'as ajouté qu'un nœud trahit souvent une clé de `for_each` ou un calcul qui dépend de la **position** dans une liste plutôt que du nom. La FAQ du QDevice dans la documentation de `pvecm` dit dans quel ordre retirer, ajouter, et éventuellement reconfigurer.
</details>

<details><summary>Indice 2</summary>

`pvecm qdevice remove` ne touche que le cluster (configuration de Corosync, services `corosync-qdevice`) : le service `corosync-qnetd` de `pbs01` continue de tourner tant que tu ne l'arrêtes pas. Pour étendre un stockage déclaré, on modifie sa liste de nœuds ; on ne le redéclare pas.
</details>

**Pour aller plus loin** (facultatif) : la documentation explique pourquoi un QDevice avec un nombre impair de nœuds (algorithme `lms`) peut **réduire** la disponibilité. Construis le scénario : quel nœud, quel lien, quelle perte ?

---

### M09-E09 — Questions : cluster, quorum et HA  `Q` `★★`

> **Ticket PLAT-1009** — *De : Karim Benali*
> Tu as monté, cassé, réparé. Avant de passer au stockage partagé et à la haute disponibilité, je veux m'assurer que tu sais **expliquer** ce que tu as vu, à Nadia au téléphone à trois heures du matin comme à un auditeur. Par écrit, avec tes journaux d'exercices, sans moteur de recherche.

**Objectifs pédagogiques**
- Relier les observations du palier aux mécanismes de Corosync, de *votequorum* et de pmxcfs.
- Préparer les notions de HA et de stockage partagé du palier 2.

**Prérequis** : M09-E02 à M09-E08.
**Durée indicative** : 1 h.

**Travail demandé**

Réponds aux 12 questions, en t'appuyant sur ce que tu as relevé dans les exercices.

1. En M09-E04, tu as coupé le lien 0 de `hv02`. Pourquoi le cluster n'a-t-il rien perdu ? Que se serait-il passé avec un seul lien ? Pourquoi le lien de secours ne doit-il pas emprunter le même commutateur que le lien principal en production ?

2. Toujours en E04, `hv02` arrêté : les VMs qui tournaient sur `hv01` se sont-elles arrêtées ? Pourquoi le cluster bloque-t-il les **modifications** mais pas l'**exécution** ?

3. Explique à Nadia, en cinq lignes, dans quelle situation exacte `pvecm expected 1` est acceptable, et ce qu'elle doit vérifier avant.

4. Avec le QDevice (E05), combien de votes portait chaque élément ? Calcule le quorum. Pourquoi l'arbitre seul en panne n'a-t-il pas fait perdre le quorum ?

5. *(QCM)* Cluster à deux nœuds avec QDevice (`ffsplit`). Le lien entre `hv01` et `hv02` est coupé, mais chacun joint encore `pbs01`. Que se passe-t-il ?
   - A. Les deux nœuds gardent le quorum : chacun a 2 votes sur 3
   - B. Le QDevice ne donne son vote qu'à **une** des deux partitions ; l'autre perd le quorum
   - C. Les deux nœuds perdent le quorum
   - D. Le QDevice redémarre l'un des deux nœuds

6. Pourquoi a-t-on retiré le QDevice **avant** d'ajouter `hv03`, et pas après ?

7. Une partition réseau isole `hv03` de `hv01` et `hv02`. Décris ce qui se passe de chaque côté (quorum, `/etc/pve`, VMs en cours). Même question si le cluster avait **quatre** nœuds coupés en deux moitiés.

8. pmxcfs : où sont réellement stockées les données de `/etc/pve` sur un nœud ? Pourquoi `/etc/pve` n'est-il pas fait pour y ranger de gros fichiers ? Où sont les disques des VMs, et les ISO ?

9. *(QCM)* On déclare par erreur `shared 1` sur `zfs-local`. Quelle conséquence est la plus grave ?
   - A. Aucune : Proxmox VE vérifie que le stockage est vraiment partagé
   - B. L'interface affiche mal la place libre
   - C. Une migration ne copie plus les disques : la VM démarre sur le nœud cible sans son disque (ou sur un volume vide de même nom) ; la HA pourrait la « redémarrer » ailleurs de même
   - D. ZFS se met à répliquer le pool tout seul

10. En E07, la migration à chaud avec disques locaux a duré bien plus longtemps que l'interruption mesurée par le `ping`. Explique pourquoi la durée totale et l'interruption sont deux grandeurs indépendantes.

11. Le palier 2 mettra en place la HA. Si `hv02` tombe brutalement (coupure de courant) avec `app01` en HA sur `zfs-local` sans réplication, que pourra faire le gestionnaire HA ? Et avec un disque sur Ceph ? Dans ce second cas, pourquoi le redémarrage ailleurs ne sera-t-il **pas** immédiat ?

12. Les nœuds sont installés par le code, configurés par le code, mais le cluster a été formé à la main. Quelles étapes du palier restent manuelles ? Lesquelles automatiserais-tu en premier pour pouvoir reconstruire `hv-par1` en une heure (M09-E46), et lesquelles garderais-tu volontairement manuelles ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions avant d'ouvrir le corrigé, en citant tes observations.
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) et calculé ton score sur 24.
- [ ] Pour chaque réponse fausse ou incomplète, tu as noté l'exercice à reprendre.

<details><summary>Indice 1</summary>

Reprends l'arithmétique de *votequorum* : votes attendus, votes présents, quorum = majorité stricte des attendus. Pour le QDevice, regarde dans ton journal de E05 la section `quorum` de `corosync.conf` et la ligne `Qdevice` de `pvecm status`.
</details>

<details><summary>Indice 2</summary>

Pour les questions de HA, sépare toujours : « le cluster sait-il que le nœud est mort ? », « est-il **sûr** qu'il ne fait plus tourner la VM ? », « le disque est-il accessible ailleurs ? ».
</details>

**Pour aller plus loin** (facultatif) : lis la section « High Availability » du guide d'administration (en particulier « Fencing » et « How It Works ») avant d'attaquer M09-E13.
