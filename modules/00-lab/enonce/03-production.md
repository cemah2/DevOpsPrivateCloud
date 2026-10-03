# Module 00 — Palier 3 : Production

Le socle tourne : `gw01` route et filtre, `dns01` résout, `adm01` sert de poste d'administration, `pbs01` reçoit les sauvegardes à travers le tunnel. Pour Claire Morel, « ça marche » ne suffit pas : avant d'y poser GitLab et NetBox, le socle doit tenir la route comme un environnement de production. Sophie Laurent (RSSI) veut un hyperviseur durci et des sauvegardes chiffrées, Nadia Roussel veut être prévenue quand une sauvegarde échoue et savoir restaurer vite, Karim Benali veut des décisions d'architecture écrites et des VMs configurées proprement. Ce palier transforme le lab en plateforme exploitable.

> ⚠️ **Rappel** : `pve01` héberge peut-être tes VMs personnelles. Plusieurs exercices de ce palier touchent à l'accès, au réseau et au redémarrage de l'hyperviseur. Lis chaque avertissement avant d'agir, et garde **toujours** un accès console (écran/clavier, IPMI ou iLO/IDRAC selon ta machine) disponible pendant les exercices M00-E27, M00-E28 et M00-E34.

Les vérifications de ce palier se lancent **depuis `adm01`** (`lab/bin/check 00 XX`).

---

### M00-E27 — Durcir l'accès à `pve01`  `LAB` `★★`

> **Ticket SEC-127** — *De : Sophie Laurent*
> Revue d'accès de l'hyperviseur PAR1 : l'interface d'administration et SSH répondent à tout le réseau, `root` se connecte par mot de passe, aucun second facteur. Ce n'est pas acceptable pour une machine qui portera des données de santé.
> Je veux : double authentification sur les comptes à privilèges, SSH par clé uniquement, et un filtrage réseau qui limite l'administration aux réseaux d'administration. Et je ne veux pas apprendre demain que tu t'es enfermé dehors.

**Objectifs pédagogiques**
- Mettre en place l'authentification à deux facteurs (TOTP + clés de récupération) de Proxmox VE et comprendre son périmètre réel.
- Interdire l'authentification SSH par mot de passe sans perdre l'accès.
- Activer le pare-feu Proxmox au niveau datacenter et hôte, comprendre l'IPSet spécial `management` et la hiérarchie datacenter → hôte → VM.
- Appliquer une procédure anti-verrouillage.

**Prérequis** : M00-E08 (utilisateurs), M00-E15 (`adm01` outillé, clé SSH de `adm01` autorisée sur `pve01`), M00-E16 (VPN `wg1`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Réseaux d'administration autorisés : `<LAN-MAISON>` (ton réseau domestique), `10.255.1.0/24` (VPN `wg1`), `10.10.10.0/24` (MGMT, où vit `adm01`).
- Ports à protéger sur `pve01` : 8006/tcp (interface web et API), 22/tcp (SSH). La console VNC/SPICE passe par 8006 (websocket) et 3128/tcp (proxy SPICE).
- Seuls l'hôte et la configuration datacenter sont concernés : **n'active pas** le pare-feu sur tes VMs personnelles, ni sur les VMs du lab (leur filtrage est assuré par `gw01`).

> ⚠️ **Attention — risque de verrouillage.** Une erreur de pare-feu ou de configuration SSH peut te couper de `pve01`. Avant de commencer : (1) vérifie que tu disposes d'un accès console local ou distant (iLO/IPMI, écran/clavier) **et** d'un mot de passe `root` connu ; (2) ouvre une seconde session SSH sur `pve01` que tu ne fermeras qu'à la fin ; (3) prépare la commande de secours `pve-firewall stop`.

**Travail demandé**
1. **Second facteur.** Active un TOTP pour `root@pam` puis pour `wb-admin@pve` (interface web : *Datacenter → Permissions → Two Factor*), et génère pour chacun un jeu de **clés de récupération**. Range les clés de récupération hors de `pve01` (gestionnaire de mots de passe). Déconnecte-toi puis reconnecte-toi avec chaque compte pour valider. Observe ensuite :
   ```
   root@pve01:~# pveum user tfa list
   root@pve01:~# pvesh get /access/tfa/root@pam
   root@pve01:~# ls -l /etc/pve/priv/tfa.cfg
   ```
   Réponds par écrit : le TOTP protège-t-il les connexions SSH ? les appels API avec le jeton `wb-automation@pve!lab` ? la console physique ? Comment réinitialiser le TFA de `root@pam` si tu perds ton téléphone **et** tes clés de récupération ?
2. **SSH par clé uniquement.** Vérifie d'abord que tu te connectes à `pve01` par clé depuis `adm01` **et** depuis ton poste. Regarde où se trouve réellement le fichier des clés autorisées de `root` (`ls -l /root/.ssh/`) et pourquoi. Crée ensuite un fichier de configuration dans `/etc/ssh/sshd_config.d/` qui impose : connexion `root` par clé seulement (`PermitRootLogin prohibit-password`), pas d'authentification par mot de passe ni *keyboard-interactive*. Valide la syntaxe et la configuration effective **avant** de recharger :
   ```
   root@pve01:~# sshd -t && sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication)'
   root@pve01:~# systemctl reload ssh
   ```
   Teste une **nouvelle** connexion par clé sans fermer l'ancienne, puis vérifie qu'une connexion par mot de passe est refusée. Le mot de passe `root` reste utilisable sur la console et dans l'interface web (realm `pam`).
3. **Pare-feu Proxmox.** Les fichiers de configuration sont `/etc/pve/firewall/cluster.fw` (datacenter) et `/etc/pve/nodes/<NŒUD>/host.fw` (hôte). Dans cet ordre, et **sans activer le pare-feu avant la sous-étape 6** :
   1. crée au niveau datacenter l'IPSet nommé exactement `management` contenant les trois réseaux d'administration ;
   2. ajoute au niveau datacenter des règles explicites autorisant 8006/tcp et 22/tcp depuis `+management`, et l'ICMP *echo-request* depuis `+management` ;
   3. lis la documentation de l'IPSet `management` (`man pve-firewall`, section *Standard IP set management*) et la sortie de `pve-firewall localnet` : explique pourquoi ces règles sont en partie redondantes, et pourquoi on les écrit quand même ;
   4. **vérifie l'existant des VMs** : l'interrupteur du datacenter active aussi les pare-feu **déjà configurés** au niveau des VMs (fichiers `/etc/pve/firewall/<VMID>.fw` avec `enable: 1`), dont la politique entrante par défaut est `DROP`. Repère-les (`grep -l '^enable: *1' /etc/pve/firewall/[0-9]*.fw`, puis `firewall=1` sur leurs cartes dans `qm config`) : une VM personnelle concernée perdrait tout trafic entrant non autorisé par ses règles dès la sous-étape 6. Note-les et décide avec leur propriétaire (toi) avant d'aller plus loin ;
   5. mets en place un « homme mort » : une commande programmée qui exécutera `pve-firewall stop` dans 10 minutes si tu ne l'annules pas (paquet `at`, ou `systemd-run --on-active=10m`) ;
   6. active le pare-feu au niveau datacenter (politique entrante `DROP`, sortante `ACCEPT`), vérifie que le pare-feu hôte est actif, puis contrôle :
      ```
      root@pve01:~# pve-firewall compile | less
      root@pve01:~# pve-firewall status
      ```
   7. depuis `adm01` et ton poste (LAN maison), vérifie l'accès à 8006 et 22 ; regarde sur `pve01` avec quelle adresse source arrivent les connexions de `adm01`. Depuis une VM du VLAN SANDBOX (ex. `sbx01`), tente la même chose et **explique** le résultat en t'appuyant sur les règles `forward` et `postrouting` de `gw01`. Explique aussi ce qui se passe pour un poste connecté par `wg1` ;
   8. si tout fonctionne, annule l'homme mort.
4. Vérifie que tes VMs personnelles et les VMs du lab fonctionnent toujours (accès réseau inchangé).
5. Rédige en 10 lignes maximum, dans tes notes d'exploitation, la **procédure de secours** en cas de verrouillage (accès console, commande, fichier à corriger).

**Critères de réussite**
- [ ] `root@pam` et `wb-admin@pve` ont chacun un TOTP et des clés de récupération actifs.
- [ ] `sshd -T` sur `pve01` affiche `permitrootlogin` en mode « clé uniquement », `passwordauthentication no`, `kbdinteractiveauthentication no`.
- [ ] Une connexion SSH vers `pve01` sans clé est refusée ; avec clé, elle fonctionne depuis `adm01`.
- [ ] `pve-firewall status` indique que le pare-feu est actif ; l'IPSet `management` contient `<LAN-MAISON>`, `10.255.1.0/24` et `10.10.10.0/24`.
- [ ] Les ports 8006 et 22 de `pve01` restent joignables depuis `adm01`.
- [ ] Aucune VM n'a eu son pare-feu activé dans le cadre de cet exercice.
- [ ] La procédure de secours est écrite.

**Vérification** : `lab/bin/check 00 27` (positionne `WB_LAN_MAISON` dans `lab/lab.env`).

<details><summary>Indice 1</summary>

Sur une installation Proxmox, `/root/.ssh/authorized_keys` est souvent un lien symbolique vers un fichier de `/etc/pve/priv/`. Si tu le remplaces par un fichier ordinaire, ou si tu édites la mauvaise cible, tu peux perdre des clés. Dans `sshd_config`, la **première** valeur lue gagne pour la plupart des options : regarde où se trouve la directive `Include` dans `/etc/ssh/sshd_config`.
</details>

<details><summary>Indice 2</summary>

Un IPSet se déclare dans une section `[IPSET <nom>]` de `cluster.fw` ; une règle y fait référence avec `+<nom>`. Les options datacenter (`enable`, `policy_in`, `policy_out`) sont dans la section `[OPTIONS]`. Tu peux tout faire en CLI : `pvesh get /cluster/firewall` liste les sous-chemins (`options`, `ipset`, `rules`…).
</details>

<details><summary>Indice 3</summary>

Pour comprendre ce que voit `pve01`, regarde l'adresse source réelle d'une connexion venant de `adm01` : `ss -tn state established '( sport = :22 )'` sur `pve01`. Si c'était l'adresse WAN de `gw01` (NAT), toute VM du lab capable de traverser `gw01` serait vue comme venant du LAN maison : vérifie que ce n'est pas le cas chez toi.
</details>

**Pour aller plus loin** (facultatif) : le nouveau pare-feu `proxmox-firewall` basé sur nftables (option `nftables` du pare-feu hôte, à vérifier selon ta version) ; l'authentification OIDC qui arrivera au module 24 ; [documentation pare-feu](https://pve.proxmox.com/pve-docs/chapter-pve-firewall.html) et [TFA](https://pve.proxmox.com/pve-docs/chapter-pveum.html#pveum_tfa_auth).

---

### M00-E28 — Migrer le réseau du lab vers Proxmox SDN  `LAB` `★★★`

> **Ticket PLAT-128** — *De : Karim Benali*
> Aujourd'hui, chaque VM du lab porte son VLAN en dur (`bridge=vmbr1,tag=20`). Une faute de frappe sur le tag et la VM atterrit dans le mauvais réseau, sans que personne ne s'en aperçoive. Et on ne peut pas dire « l'équipe X a le droit d'utiliser le réseau K8S, pas MGMT ».
> On passe au SDN Proxmox : des réseaux nommés, des droits par réseau. Migration VM par VM, avec vérification, et sans toucher au routeur.

**Objectifs pédagogiques**
- Comprendre le modèle SDN de Proxmox (zones, VNets, sous-réseaux, configuration en attente / appliquée).
- Créer une zone VLAN et ses VNets en ligne de commande, et appliquer la configuration.
- Migrer des VMs en production, une par une, avec retour arrière possible.
- Déléguer l'usage des réseaux par ACL (`SDN.Use`).

**Prérequis** : M00-E09 (`vmbr1`), M00-E10 (`gw01`), M00-E17 (rôle `WBAutomation`, jeton), M00-E27 terminé (le pare-feu de l'hôte est actif : rien à y changer ici).
**Durée indicative** : 2 h.

**Contexte technique**
- Zone : type VLAN, nom `lab`, sur le bridge `vmbr1`.
- VNets (nom → VLAN) : `vmgmt`(10), `vinfra`(20), `vstopub`(30), `vstoclu`(31), `vcoro`(32), `vk8s`(40), `vk8slb`(41), `vosapi`(50), `vostun`(51), `vosext`(52), `vprov`(60), `vdmz`(70), `vsandbox`(99). Donne à chacun un alias lisible (`MGMT`, `INFRA`…).
- Le DHCP du VLAN 99 reste assuré par `dns01` via le relais de `gw01` : on **n'active pas** l'IPAM ni le DHCP du SDN.
- Une API toujours valable : `pvesh get /cluster/sdn` liste les sous-chemins (`zones`, `vnets`, `subnets`…).

> ⚠️ **Attention** : appliquer la configuration SDN recharge le réseau de `pve01` (`ifreload -a`). Si `/etc/network/interfaces` contient des modifications non appliquées, ou si un fichier `/etc/network/interfaces.new` attend (modification faite dans l'interface web et non appliquée), règle ce point **avant**. Garde ton accès console à portée de main.

**Travail demandé**
1. **État des lieux.** Vérifie que le paquet SDN est présent (`libpve-network-perl` en 8.x ; intégré en 9.x), que `/etc/network/interfaces` inclut `/etc/network/interfaces.d/*` (indispensable : c'est là que le SDN écrit), et relève la configuration réseau actuelle de chaque VM du pool `lab` (`qm config <VMID> | grep ^net`). Note les adresses MAC.
2. **Zone et VNets.** Crée la zone et les 13 VNets avec `pvesh create …` (pas l'interface web : tu dois pouvoir rejouer ces commandes dans un script). Avant d'appliquer, observe la différence entre la configuration en attente et la configuration en service :
   ```
   root@pve01:~# pvesh get /cluster/sdn/vnets --pending 1
   root@pve01:~# cat /etc/pve/sdn/vnets.cfg
   root@pve01:~# cat /etc/network/interfaces.d/sdn 2>/dev/null
   ```
3. **Application.** Applique la configuration (`pvesh set /cluster/sdn`), puis observe ce qui a été créé sur l'hôte : `/etc/network/interfaces.d/sdn`, `ip -d link show vmgmt`, `bridge vlan show`. Explique en deux phrases comment une trame d'une VM branchée sur `vinfra` arrive taguée 20 sur `vmbr1`.
4. **Le cas `gw01`.** Explique pourquoi l'interface trunk de `gw01` (`net1`, sur `vmbr1` sans tag) **ne** migre **pas** vers un VNet. Ne la modifie pas.
5. **Migration, une VM à la fois** : `dns01`, puis `adm01`, puis les éventuelles VMs sandbox (5001+). Pour chacune :
   1. annonce-toi un critère de retour arrière (quelle commande remet l'état initial ?) ;
   2. bascule l'interface vers le VNet correspondant **en conservant l'adresse MAC** ;
   3. vérifie immédiatement : ping de la passerelle, résolution DNS, connexion SSH depuis `adm01` (pour `adm01` elle-même : depuis ton poste via `wg1`, et garde une session ouverte) ;
   4. ne passe à la suivante que si tout est vert.
   Mets aussi à jour le template 9000 (son interface est aujourd'hui sur `vmbr1` sans étiquette) : fais-la pointer vers le VNet SANDBOX, réseau par défaut des clones jetables, si Proxmox le permet ; sinon, note qu'il faudra préciser le réseau au clonage.
6. **Droits.** Donne au groupe `wb-admins`, à l'utilisateur `wb-automation@pve` et à son jeton `wb-automation@pve!lab` le droit d'utiliser les VNets de la zone `lab` (rôle prédéfini `PVESDNUser` ou ton rôle `WBAutomation`, à justifier). Vérifie les droits effectifs avec `pveum user permissions` et `pveum user token permissions`.
7. **Bilan.** Rédige un tableau avantages / limites du SDN par rapport aux bridges taggés (au moins 4 lignes de chaque côté), en citant l'IPAM et le DHCP intégrés du SDN et la raison pour laquelle on ne les utilise pas ici.

**Critères de réussite**
- [ ] La zone `lab` (type VLAN, bridge `vmbr1`) et les 13 VNets existent avec les bons tags, et la configuration est appliquée (les bridges des VNets existent sur `pve01`).
- [ ] `dns01` est sur `vinfra`, `adm01` sur `vmgmt`, sans tag sur l'interface, avec leur MAC d'origine.
- [ ] `gw01` a toujours son interface trunk sur `vmbr1` sans tag.
- [ ] `adm01` joint `dns01`, la résolution DNS et l'accès Internet fonctionnent.
- [ ] `wb-admins` et `wb-automation@pve!lab` ont le privilège `SDN.Use` sur les VNets de la zone `lab`.
- [ ] Le tableau avantages/limites est rédigé.

**Vérification** : `lab/bin/check 00 28`

<details><summary>Indice 1</summary>

Une zone se crée avec `pvesh create /cluster/sdn/zones` (paramètres `--zone`, `--type`, `--bridge`), un VNet avec `pvesh create /cluster/sdn/vnets` (`--vnet`, `--zone`, `--tag`, `--alias`). Consulte `pvesh usage /cluster/sdn/vnets -v` pour la liste exacte des paramètres de ta version.
</details>

<details><summary>Indice 2</summary>

`qm set <VMID> --net0 …` remplace toute la définition de l'interface : si tu n'y mets pas `virtio=<MAC>`, Proxmox génère une nouvelle MAC. Selon la façon dont cloud-init a écrit la configuration réseau dans la VM, une nouvelle MAC peut laisser la VM sans réseau.
</details>

<details><summary>Indice 3</summary>

Les chemins d'ACL du SDN ont la forme `/sdn/zones/<zone>` et `/sdn/zones/<zone>/<vnet>`. Avec la séparation des privilèges, le jeton n'a que l'intersection de ses droits et de ceux de l'utilisateur.
</details>

**Pour aller plus loin** (facultatif) : zones `simple`, `qinq`, `vxlan` et `evpn` (on y reviendra au module 09) ; [documentation SDN](https://pve.proxmox.com/pve-docs/chapter-pvesdn.html).

---

### M00-E29 — Notifications Proxmox et PBS  `LAB` `★★`

> **Ticket PLAT-129** — *De : Nadia Roussel*
> Ce matin, j'ai découvert par hasard que la sauvegarde de `dns01` échouait depuis trois jours. Le mail partait vers `root@localhost`, autant dire nulle part.
> Je veux être prévenue des échecs de sauvegarde, de vérification et de *garbage collection*, sur PAR1 comme sur PAR2. Pas d'avalanche : les succès ne doivent pas me réveiller.

**Objectifs pédagogiques**
- Comprendre le système de notifications de Proxmox VE (8.1+) et de PBS (3.2+) : cibles (*targets*), filtres (*matchers*), champs et sévérités.
- Configurer une cible SMTP ou webhook, des filtres ciblés, et tester l'acheminement de bout en bout.
- Basculer les tâches de sauvegarde sur le système de notifications.

**Prérequis** : M00-E22 (tâche de sauvegarde planifiée, datastore `ds-lab` avec tâches de GC, *prune* et vérification).
**Durée indicative** : 1 h 15.

**Contexte technique**
- Configuration PVE : `/etc/pve/notifications.cfg` (et `/etc/pve/priv/notifications.cfg` pour les secrets). API : `/cluster/notifications/` (`targets`, `endpoints/{sendmail,smtp,gotify,webhook}`, `matchers`). La cible `webhook` existe depuis PVE 8.3.
- PBS : sous-commande `proxmox-backup-manager notification` (endpoints, matchers), et option `notification-mode` des datastores.
- Deux choix possibles pour la cible (choisis-en **un**, l'autre est facultatif) :
  - **SMTP** vers une boîte mail à toi (fournisseur avec mot de passe d'application, ou serveur SMTP de ton FAI) ;
  - **webhook** vers un récepteur de test sur `adm01` : le script fourni [`ressources/M00-E29/recepteur-webhook.py`](../ressources/M00-E29/recepteur-webhook.py) écoute en HTTP et affiche chaque requête reçue. Dans ce cas, `pve01` et `pbs01` doivent pouvoir joindre `adm01` sur le port choisi : c'est à toi d'adapter le filtrage de `gw01` au plus juste.

> ⚠️ **Attention** : ne mets jamais un mot de passe SMTP en clair dans un fichier versionné. Dans Proxmox, il est stocké dans `/etc/pve/priv/` (lisible par `root` seulement).

**Travail demandé**
1. Inventorie l'existant : `pvesh get /cluster/notifications/targets`, `pvesh get /cluster/notifications/matchers`, `cat /etc/pve/notifications.cfg`. Que fait le filtre par défaut ? Vers quelle adresse part le courrier de `root@pam` ?
2. Sur `pve01`, crée la cible de ton choix (en CLI, `pvesh create /cluster/notifications/endpoints/<type>` ; utilise `pvesh usage … -v` pour les paramètres). Teste-la avec `pvesh create /cluster/notifications/targets/<NOM>/test` et vérifie la réception.
3. Crée un filtre qui n'envoie vers ta cible **que** les notifications de type `vzdump` de sévérité `error`. Désactive ou restreins le filtre par défaut pour éviter les doublons, en justifiant ton choix.
4. Vérifie dans `/etc/pve/jobs.cfg` (ou dans l'interface : *Datacenter → Backup → Edit → Notifications*) que ta tâche de sauvegarde utilise le système de notifications et non l'ancien envoi de mail direct. Explique la différence entre les modes proposés.
5. Prouve que la chaîne fonctionne : provoque une notification `vzdump` **sans** casser une sauvegarde de production (par exemple en ajoutant temporairement la sévérité `info` au filtre et en sauvegardant une VM sandbox, ou en provoquant un échec sur une VM sandbox). Remets le filtre dans son état final ensuite.
6. Sur `pbs01`, fais de même : une cible, un filtre qui ne laisse passer que les erreurs des tâches `gc`, `prune`, `verify` et `sync` sur `ds-lab`, et bascule le datastore sur le système de notifications. Teste la cible.
7. Note dans tes notes d'exploitation : quels événements sont notifiés, vers où, et comment tester la chaîne après un changement.

**Critères de réussite**
- [ ] `pve01` possède une cible de notification autre que `mail-to-root`, testée avec succès.
- [ ] Un filtre de `pve01` sélectionne les notifications `type=vzdump` et route vers cette cible.
- [ ] La tâche de sauvegarde planifiée passe par le système de notifications.
- [ ] `pbs01` possède une cible et un filtre propres, testés avec succès.
- [ ] Une notification réelle de `vzdump` a été reçue (capture ou extrait de journal dans tes notes).

**Vérification** : `lab/bin/check 00 29`

<details><summary>Indice 1</summary>

Un filtre combine des conditions (`match-severity`, `match-field`, `match-calendar`) avec un mode `all` ou `any`. Les notifications de sauvegarde portent un champ `type` ; regarde la documentation « Notification Matchers » pour la syntaxe des conditions sur les champs.
</details>

<details><summary>Indice 2</summary>

Côté PBS, la sous-commande `proxmox-backup-manager notification` a la même logique que l'API PVE. Les types de notification PBS ne sont pas les mêmes que ceux de PVE : cherche la liste des valeurs du champ `type` dans la documentation PBS.
</details>

**Pour aller plus loin** (facultatif) : modèles de messages personnalisés pour le webhook (helpers `escape`, `json`, à vérifier selon ta version) ; Gotify ou ntfy auto-hébergé ; [notifications PVE](https://pve.proxmox.com/pve-docs/chapter-notifications.html), [notifications PBS](https://pbs.proxmox.com/docs/notifications.html).

---

### M00-E30 — Sauvegarder la configuration de l'hyperviseur  `LAB` `★★`

> **Ticket PLAT-130** — *De : Claire Morel*
> On sauvegarde les VMs, très bien. Mais si le disque système de `pve01` meurt demain, combien de temps faut-il pour reconstruire l'hyperviseur avec ses stockages, son réseau, ses utilisateurs, son pare-feu, son SDN ? Aujourd'hui : personne ne sait.
> Je veux une sauvegarde quotidienne de la configuration de `pve01` sur PBS, et une procédure de restauration testée.

**Objectifs pédagogiques**
- Identifier ce qui constitue la configuration d'un nœud Proxmox et où elle vit.
- Comprendre `pmxcfs` : `/etc/pve` est une vue FUSE d'une base SQLite.
- Sauvegarder un hôte avec `proxmox-backup-client` (sauvegarde de type `host`, archives `pxar`, namespace).
- Automatiser avec un timer systemd et documenter la restauration.

**Prérequis** : M00-E22 (datastore `ds-lab`, stockage `pbs-par2` avec namespace `par1`, jeton de sauvegarde).
**Durée indicative** : 1 h 30.

**Contexte technique**
- À sauvegarder au minimum : `/etc/pve`, `/etc/network/interfaces` (et `interfaces.d/`), `/etc/hosts`, `/etc/apt`, `/root/.ssh`, `/etc/ssh`, les configurations du pare-feu et du SDN (sous `/etc/pve`), plus une copie cohérente de `/var/lib/pve-cluster/config.db`.
- Le stockage `pbs-par2` contient déjà tout ce qu'il faut pour se connecter à PBS : serveur, datastore, utilisateur/jeton, empreinte du certificat dans `/etc/pve/storage.cfg`, secret dans `/etc/pve/priv/storage/pbs-par2.pw`. Ton script les réutilise au lieu de dupliquer le secret.
- Noms imposés (pour la vérification) : script `/usr/local/sbin/wb-backup-config.sh`, unités `wb-backup-config.service` et `wb-backup-config.timer`, groupe de sauvegarde `host/<NOM-DU-NŒUD>` dans le namespace `par1`.

**Travail demandé**
1. Explore `pmxcfs` : `mount | grep /etc/pve`, `ls -la /var/lib/pve-cluster/`, `stat -f /etc/pve`. Explique pourquoi une copie de `/etc/pve` ne suffit pas comme unique sauvegarde, et pourquoi une simple copie de `config.db` pendant que `pve-cluster` tourne n'est pas fiable.
2. Lance une première sauvegarde **à la main** avec `proxmox-backup-client backup` (archives `pxar` de `/etc` et `/root`, plus un répertoire de travail contenant la copie de `config.db` et quelques inventaires utiles à la reconstruction : versions, disques, réseau, liste des paquets). Vérifie dans le catalogue que `/etc/pve/qemu-server/` est bien présent dans l'archive : si ce n'est pas le cas, cherche dans `proxmox-backup-client help backup` l'option qui l'explique.
3. Écris le script `/usr/local/sbin/wb-backup-config.sh` : lecture des paramètres de `pbs-par2` dans `storage.cfg`, préparation du répertoire de travail, sauvegarde, code retour non nul en cas d'échec. Prévois dès maintenant l'utilisation d'une clé de chiffrement **si** elle existe (elle arrivera en M00-E36).
4. Crée le service et le timer systemd (quotidien, hors de la fenêtre de la sauvegarde des VMs, rattrapage si `pve01` était éteint). Active le timer et déclenche une exécution par `systemctl start wb-backup-config.service`. Lis le journal.
5. Vérifie côté PBS (interface ou `proxmox-backup-client snapshot list --ns par1`) que le groupe `host/<NŒUD>` existe, et que la tâche de *prune* du namespace s'y applique.
6. **Restauration (test).** Sans toucher à la configuration en service : restaure l'archive `etc.pxar` dans `/root/restau-test/`, compare `qemu-server/1002.conf` avec l'original, puis explore le catalogue en mode interactif (`catalog shell`). Rédige la procédure de **reconstruction complète** de `pve01` (réinstallation, réseau, restauration de `config.db`, stockages, vérifications), en 15 étapes maximum.

**Critères de réussite**
- [ ] Le timer `wb-backup-config.timer` est actif et planifié ; le dernier passage du service a réussi.
- [ ] Le datastore `ds-lab` contient un instantané `host/<NŒUD>` de moins de 48 h dans le namespace `par1`, avec plusieurs archives `pxar`.
- [ ] L'archive contient `/etc/pve/` (dont les configurations des VMs) et une copie de `config.db`.
- [ ] Le script ne contient aucun secret en clair.
- [ ] La procédure de reconstruction est rédigée et la restauration de test a été faite.

**Vérification** : `lab/bin/check 00 30`

<details><summary>Indice 1</summary>

`proxmox-backup-client` ne traverse pas les points de montage par défaut. `/etc/pve` est un système de fichiers FUSE distinct de `/`.
</details>

<details><summary>Indice 2</summary>

SQLite fournit une commande de sauvegarde en ligne cohérente (paquet `sqlite3`). Les variables d'environnement `PBS_REPOSITORY`, `PBS_PASSWORD`, `PBS_FINGERPRINT` évitent de passer des secrets en argument (visibles dans `ps`).
</details>

<details><summary>Indice 3</summary>

Une unité de service `Type=oneshot` lancée par un timer avec `Persistent=true` rattrape une exécution manquée. `systemctl list-timers` et `journalctl -u wb-backup-config.service` sont tes amis.
</details>

**Pour aller plus loin** (facultatif) : déclencher une alerte en cas d'échec (`OnFailure=` d'une unité systemd) ; sauvegarder aussi la configuration de `pbs01` (`/etc/proxmox-backup`) vers un autre emplacement.

---

### M00-E31 — Temps synchronisé sur tout le lab  `LAB` `★★`

> **Ticket PLAT-131** — *De : Karim Benali*
> En corrélant des journaux de `dns01` et de `pbs01`, j'ai trouvé 40 secondes d'écart. Ça ne passera pas avec Kerberos, les certificats de la PKI (module 06), etcd ou les jetons OIDC.
> `gw01` devient la source de temps du lab ; tout le monde s'y synchronise, y compris PAR2 à travers le tunnel.

**Objectifs pédagogiques**
- Configurer chrony en serveur (contrôle d'accès) et en client.
- Raisonner sur l'adresse source réelle d'un client à travers un tunnel.
- Diagnostiquer avec `chronyc sources -v`, `tracking`, `sourcestats`, `clients`.
- Ouvrir le strict nécessaire dans nftables.

**Prérequis** : M00-E10 (`gw01`), M00-E12 (`adm01`, `dns01`), M00-E21 (tunnel `wg0`).
**Durée indicative** : 1 h.

**Contexte technique**
- `gw01` se synchronise sur Internet (`pool.ntp.org` ou les sources Debian par défaut) et sert les réseaux `10.10.0.0/16` et `10.20.0.0/16`.
- Chaque VM du lab se synchronise sur la passerelle de **son** VLAN (`adm01` → 10.10.10.1, `dns01` → 10.10.20.1).
- `pbs01` (PAR2) se synchronise sur `gw01` à travers le tunnel, en visant `10.10.10.1`.
- `pve01` : à toi de décider (Internet ou `gw01`) et de **justifier**.
- Sous Debian, chrony lit les fichiers `*.conf` de `/etc/chrony/conf.d/` et `*.sources` de `/etc/chrony/sources.d/` : préfère ces répertoires à l'édition de `chrony.conf`.

**Travail demandé**
1. Sur chaque machine (`gw01`, `adm01`, `dns01`, `pbs01`, `pve01`), relève le service de temps en place (`timedatectl`, `systemctl status chrony systemd-timesyncd`) et l'écart actuel.
2. Configure `gw01` en serveur. Vérifie avec `chronyc accheck` que les adresses autorisées sont les bonnes. Côté nftables, la chaîne `input` de `gw01` n'a encore aucune règle NTP (rien n'en avait besoin avant cet exercice) : ajoute ce qu'il faut pour que NTP soit accepté uniquement depuis les VLANs routés du lab et depuis PAR2 à travers le tunnel. Le WAN ne doit pas pouvoir interroger `gw01`.
3. Configure `adm01` et `dns01` en clients (installe chrony si nécessaire : que devient `systemd-timesyncd` ?). Les sources Internet par défaut doivent être retirées.
4. Configure `pbs01`. Vérifie quelle **adresse source** il utilise pour joindre 10.10.10.1 (`ip route get 10.10.10.1`) et ce que `gw01` reçoit (`chronyc clients`, `tcpdump -ni wg0 udp port 123`) : explique le lien avec les routes posées sur `pbs01` en M00-E21, et pourquoi ta règle nftables et ta directive `allow` n'ont pas besoin de connaître l'adresse de tunnel de `pbs01`.
5. Décide pour `pve01` et écris ta justification (3-5 lignes) : pense au démarrage de l'hyperviseur, à la dépendance circulaire avec une VM qu'il héberge, et à l'horodatage des sauvegardes.
6. Interprète pour chaque client la sortie de `chronyc sources -v` et `chronyc tracking` (stratum, offset, *Leap status*, *Reference ID*).

**Critères de réussite**
- [ ] `gw01` est synchronisé (`Leap status : Normal`) et autorise 10.10.0.0/16 et 10.20.0.0/16.
- [ ] La chaîne `input` de `gw01` accepte NTP depuis l'intérieur seulement.
- [ ] `adm01` est synchronisé sur 10.10.10.1, `dns01` sur 10.10.20.1, `pbs01` sur `gw01` via le tunnel (source marquée `^*`).
- [ ] `systemd-timesyncd` n'est actif sur aucun client chrony.
- [ ] Le choix pour `pve01` est justifié par écrit.

**Vérification** : `lab/bin/check 00 31`

<details><summary>Indice 1</summary>

Une directive `allow` de chrony, comme une règle `ip saddr` de nftables, porte sur l'adresse **source** du client. Une route installée par `wg-quick` à partir des `AllowedIPs` n'a pas d'adresse source préférée (le noyau choisirait l'adresse de `wg0`) : c'est pourquoi M00-E21 a fixé la source des routes de `pbs01`. Si tu ne l'as pas fait, c'est le moment d'y revenir.
</details>

<details><summary>Indice 2</summary>

`chronyc reload sources` recharge les fichiers de `sources.d` sans redémarrer ; une modification de `allow` demande un redémarrage de chrony (ou `chronyc allow …` à chaud, non persistant).
</details>

**Pour aller plus loin** (facultatif) : NTS (Network Time Security) côté sources Internet ; `makestep` et le comportement au démarrage d'une VM restaurée ; la panne M00-E45 reviendra sur ce sujet.

---

### M00-E32 — Optimiser la configuration des VMs du socle  `LIBRE` `★★★`

> **Ticket PLAT-132** — *De : Karim Benali*
> J'ai regardé la config de `gw01`, `adm01` et `dns01` : réglages par défaut partout. Pas d'agent invité, disques sans TRIM, aucun ordre de démarrage — après une coupure, `dns01` démarre avant le routeur et `adm01` ne résout rien pendant deux minutes.
> Je veux des VMs du socle configurées comme on le ferait en production, chaque réglage justifié. Je relirai tes choix.

**Objectifs pédagogiques**
- Connaître les options matérielles d'une VM QEMU/KVM qui comptent en production et leurs compromis.
- Concevoir un ordre de démarrage/arrêt cohérent avec les dépendances de service.
- Justifier chaque choix (performance, sécurité, migrabilité, cohérence des sauvegardes).

**Prérequis** : M00-E12, M00-E22, M00-E28.
**Durée indicative** : 2 h.

**Contraintes**
- Périmètre : VMs 1000, 1001, 1002 et template 9000. Ne touche à aucune VM hors du pool `lab`.
- Une seule VM indisponible à la fois ; prévois un retour arrière (snapshot ou copie de la configuration) avant chaque modification.
- Les VMs du socle doivent pouvoir, plus tard, être restaurées et démarrées sur un autre hyperviseur (PRA vers PAR2 au final F5 : CPU de génération *Ivy Bridge*) ou migrées dans le cluster du module 09.
- Les sauvegardes des VMs doivent être cohérentes au niveau du système de fichiers.
- Après une coupure de courant, le socle doit redémarrer seul et dans l'ordre : routeur, puis DNS, puis poste d'administration, avec des délais raisonnables ; à l'arrêt de `pve01`, l'ordre inverse.
- Aucune réservation mémoire excessive : `pve01` doit garder de la marge pour les profils lourds (PLAN §3.3).

**Points à traiter** (chacun avec un choix et sa justification écrite)
- Type de CPU et nombre de vCPU.
- Mémoire et *ballooning* (cas particulier du routeur ?).
- Contrôleur disque, `iothread`, mode de cache, `discard`, émulation SSD, `aio`.
- Agent invité QEMU (installation dans la VM, activation côté Proxmox, *fs-freeze* lors des sauvegardes, TRIM après clonage).
- Démarrage automatique, ordre, délais `up`/`down`.
- Template 9000 : quelles options y porter pour que les futures VMs en héritent ?
- Ce que tu as délibérément **laissé** par défaut, et pourquoi.

**Critères de réussite**
- [ ] `gw01`, `dns01`, `adm01` démarrent automatiquement, dans cet ordre (ordres 1, 2, 3).
- [ ] L'agent QEMU est activé dans la configuration **et** répond dans les trois VMs.
- [ ] Les trois VMs utilisent le contrôleur `virtio-scsi-single` avec `iothread`, et `discard` sur tous leurs disques.
- [ ] Le type de CPU est explicite, ni `kvm64` ni `qemu64`, et compatible avec la contrainte de restauration sur PAR2.
- [ ] Les modifications sont **appliquées** (aucune modification en attente de redémarrage).
- [ ] Un `fstrim -av` dans une VM libère de l'espace visible sur le stockage thin de `pve01`.
- [ ] Un document court justifie chaque choix.

**Vérification** : `lab/bin/check 00 32`

<details><summary>Indice 1</summary>

`qm config <VMID>` montre la configuration avec les modifications en attente ; `qm pending <VMID>` montre ce qui attend un redémarrage complet (arrêt puis démarrage, pas un redémarrage depuis l'invité).
</details>

<details><summary>Indice 2</summary>

Liste les drapeaux CPU de `hp01` (`grep -m1 flags /proc/cpuinfo`) et compare-les aux niveaux de micro-architecture x86-64 (v2, v3, v4). Les modèles CPU proposés par Proxmox sont listés dans `man qm` (option `cpu`).
</details>

<details><summary>Indice 3</summary>

Pour le TRIM : il faut que l'information traverse toutes les couches (système de fichiers invité → contrôleur virtuel → image disque → stockage thin de l'hôte). Une seule couche qui ne relaie pas, et l'espace n'est jamais rendu.
</details>

**Pour aller plus loin** (facultatif) : `hookscript` Proxmox pour exécuter une action au démarrage d'une VM ; *CPU affinity* et NUMA sur un hyperviseur mono-socket (est-ce utile ?).

---

### M00-E33 — ADR : routeur Linux et stratégie de sauvegarde  `RED` `★★`

> **Ticket PLAT-133** — *De : Claire Morel*
> Dans six mois, quelqu'un demandera pourquoi on a un routeur Debian bricolé au lieu d'un OPNsense, et pourquoi les sauvegardes partent à PAR2 de cette façon. Si la réponse est « parce que », on perdra du temps à refaire le débat.
> Écris-moi deux ADR. Karim les relira comme une MR.

**Objectifs pédagogiques**
- Rédiger une décision d'architecture au format MADR : contexte, facteurs de décision, options, conséquences.
- Présenter honnêtement les options écartées et les conséquences négatives de l'option retenue.
- Relier une décision technique aux exigences métier (HDS, RPO/RTO, compétences de l'équipe, coût).

**Prérequis** : M00-E10, M00-E21, M00-E22, M00-E23, M00-E36 recommandé.
**Durée indicative** : 2 h.

**Travail demandé**
Rédige deux ADR, d'une à deux pages chacun, dans le dépôt de documentation créé en M00-E25 : `~/medisphere/docs/socle/adr/` sur `adm01`, un fichier par ADR (`ADR-0001-routeur-linux-nftables.md`, `ADR-0002-strategie-sauvegarde-par1-par2.md`), commités ; ils rejoindront GitLab au module 01 :
1. **ADR-0001 — Routeur/pare-feu du lab : Linux + nftables** plutôt qu'une appliance (OPNsense/pfSense) ou le SNAT intégré au SDN Proxmox.
2. **ADR-0002 — Stratégie de sauvegarde PAR1 → PAR2** : outil, emplacement, transport, rétention, chiffrement, vérification, tests de restauration, objectifs RPO/RTO.

Utilise ce gabarit (MADR simplifié) :

```markdown
# ADR-NNNN — <Titre court, décision à l'impératif>

- Statut : proposé | accepté | remplacé par ADR-XXXX | déprécié
- Date : AAAA-MM-JJ
- Décideurs : <noms/rôles>
- Consultés : <noms/rôles>

## Contexte et problème
<2-6 phrases : la situation, la contrainte, la question à trancher.>

## Facteurs de décision
- <exigence ou critère 1>
- <…>

## Options envisagées
1. <option A>
2. <option B>
3. <option C>

## Décision
Option retenue : « <option> », parce que <justification reliée aux facteurs>.

### Conséquences
- Positives : …
- Négatives : …
- Actions induites : …

## Analyse des options
### <Option A>
- Pour : …
- Contre : …
### <…>

## Liens
- <tickets, docs, ADR liés>
```

**Critères de réussite**
- [ ] Chaque ADR suit le gabarit et tient en deux pages au plus.
- [ ] Au moins trois options réellement envisagées par ADR, chacune avec pour et contre.
- [ ] Les facteurs de décision citent au moins une contrainte métier (HDS, RPO/RTO, compétences, budget) et une contrainte technique du lab.
- [ ] Les conséquences négatives de l'option retenue sont écrites, avec les actions qui les compensent (et le module du workbook où elles seront traitées).
- [ ] L'ADR-0002 chiffre un RPO et un RTO cibles, et dit comment ils sont mesurés.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Un bon ADR se relit sans contexte. Écris pour quelqu'un qui arrive dans un an et ne connaît pas le lab. Une décision « temporaire » (comme `dnsmasq` avant PowerDNS) mérite aussi un ADR : la date de révision fait partie de la décision.
</details>

<details><summary>Indice 2</summary>

Pour la sauvegarde, pense à la règle 3-2-1(-1-0), à ce que PBS apporte (déduplication, incrémental, vérification, chiffrement côté client) et à ce qu'il n'apporte pas (copie hors ligne, immutabilité).
</details>

**Pour aller plus loin** (facultatif) : [MADR](https://adr.github.io/madr/) ; outil `adr-tools`.

---

### M00-E34 — Mises à jour maîtrisées de `pve01` et `pbs01`  `LAB` `★★`

> **Ticket CHG-134** — *De : Claire Morel*
> Fenêtre de maintenance ce week-end. Je veux une procédure de mise à jour de l'hyperviseur et du serveur de sauvegarde que n'importe qui dans l'équipe puisse suivre, avec un plan de retour arrière. Applique-la, et remets-moi le runbook.

**Objectifs pédagogiques**
- Préparer une mise à jour : changelogs, paquets concernés, risques, fenêtre, communication.
- Maîtriser la gestion des noyaux Proxmox (`proxmox-boot-tool`), l'épinglage et le retour au noyau précédent.
- Vérifier après mise à jour et savoir revenir en arrière.
- Appliquer la même démarche à PBS (mode maintenance du datastore).

**Prérequis** : M00-E06, M00-E30 (sauvegarde de configuration), M00-E29 (notifications).
**Durée indicative** : 2 h (hors temps de téléchargement).

> ⚠️ **Attention** : le redémarrage de `pve01` arrête **toutes** ses VMs, y compris tes VMs personnelles. Préviens les éventuels utilisateurs, vérifie le comportement de chaque VM à l'arrêt (`onboot`, délai d'arrêt) et choisis le moment. Garde l'accès console : un nouveau noyau qui ne démarre pas se rattrape au menu de démarrage.

**Travail demandé**
1. **Préparation** (sans rien installer) :
   ```
   root@pve01:~# apt update
   root@pve01:~# apt list --upgradable
   root@pve01:~# pveversion -v
   root@pve01:~# proxmox-boot-tool status
   root@pve01:~# proxmox-boot-tool kernel list
   ```
   Lis les notes de version / l'annonce correspondante et le changelog des paquets sensibles (`apt changelog <PAQUET>` pour `pve-manager`, `qemu-server`, `proxmox-kernel-*`, `pve-firewall`…). Classe les mises à jour : noyau, QEMU, pile cluster/pmxcfs, outils.
2. **Plan de retour arrière** : pour chaque risque (noyau qui ne démarre pas, régression QEMU, régression d'un service PVE), écris comment on revient en arrière. Pense aux snapshots : à quoi servent ceux des VMs critiques (`gw01`, `dns01`) pendant cette fenêtre, et à quoi ils ne servent **pas** ? Si la racine de `pve01` est sur ZFS, quelle autre possibilité as-tu ?
3. **Pré-requis du jour J** : sauvegarde de configuration fraîche (déclenche `wb-backup-config.service`), dernière sauvegarde des VMs du socle vérifiée, snapshots des VMs critiques nommés `avant-maj-<AAAAMMJJ>`, aucune tâche en cours (`pvesh get /cluster/tasks`).
4. **Mise à jour de `pve01`** avec `pveupgrade` ou `apt full-upgrade` (pourquoi jamais `apt upgrade` sur Proxmox ?). Lis attentivement les questions posées par `apt` (fichiers de configuration modifiés). Planifie le redémarrage, puis redémarre.
5. **Vérifications post-redémarrage** : noyau en service, `pveversion -v`, services en échec, stockages, pare-feu, SDN, démarrage du socle dans l'ordre, accès Internet du lab, connexion à `pbs-par2`, journal d'erreurs du démarrage. Fais-en une liste de contrôle réutilisable.
6. **Noyaux** : épingle temporairement l'ancien noyau pour le **prochain démarrage seulement**, constate le résultat, puis retire l'épinglage. Explique la différence entre un épinglage permanent et `--next-boot`.
7. **Mise à jour de `pbs01`** : même démarche, en passant le datastore en mode maintenance pendant l'opération, en dehors des fenêtres de sauvegarde, de *prune* et de vérification. Vérifie ensuite qu'une sauvegarde et une restauration de fichier fonctionnent.
8. Supprime les snapshots `avant-maj-*` une fois la fenêtre close et validée (pourquoi ne pas les garder ?).
9. Si `pve01` est encore en 8.x : exécute `pve8to9 --full`, lis le rapport et estime l'effort de passage en 9.x **sans** le faire dans cet exercice (c'est une décision à part, avec son propre ticket CHG).
10. Remets le runbook (préparation, exécution, vérification, retour arrière, communication).

**Critères de réussite**
- [ ] `pve01` et `pbs01` n'ont plus de mise à jour en attente.
- [ ] Les deux machines tournent sur le noyau le plus récent installé (ou sur un noyau épinglé de façon documentée).
- [ ] Aucun service en échec sur les deux machines ; le socle a redémarré seul et dans l'ordre.
- [ ] Aucun snapshot `avant-maj-*` ne subsiste.
- [ ] Le datastore `ds-lab` n'est plus en mode maintenance.
- [ ] Le runbook est rédigé, avec un retour arrière par risque identifié.

**Vérification** : `lab/bin/check 00 34`

<details><summary>Indice 1</summary>

`proxmox-boot-tool kernel pin` accepte une option pour ne viser que le prochain démarrage. `proxmox-boot-tool kernel list` indique le noyau épinglé s'il y en a un.
</details>

<details><summary>Indice 2</summary>

Le mode maintenance d'un datastore PBS se règle avec `proxmox-backup-manager datastore update` (option `maintenance-mode`, valeurs `read-only` ou `offline`) et se retire avec `--delete maintenance-mode`. Consulte `--help` pour ta version.
</details>

**Pour aller plus loin** (facultatif) : dépôt `pve-test` dans une VM Proxmox imbriquée pour valider une mise à jour avant la production (préfiguration du module 09) ; `needrestart`.

---

### M00-E35 — Questions de production : hyperviseur  `Q` `★★★`

> **Ticket PLAT-135** — *De : Karim Benali*
> Avant de te laisser seul(e) d'astreinte sur l'hyperviseur, je veux t'entendre sur ces questions. Réponds comme en revue d'architecture : argumente, chiffre quand c'est possible, et dis quand « ça dépend » — mais de quoi.

**Objectifs pédagogiques**
- Raisonner sur les mécanismes de l'hyperviseur qui conditionnent la stabilité et la capacité : mémoire, CPU, stockage, quorum, réseau.
- Évaluer les risques d'architecture du socle actuel.

**Prérequis** : paliers 1 et 2, M00-E27 à M00-E32.
**Durée indicative** : 1 h 30.

**Questions**

1. `pve01` est un nœud seul. Que se passe-t-il pour `/etc/pve` s'il rejoint un jour un cluster de deux nœuds et que l'autre nœud tombe ? Pourquoi `pvecm expected 1` est-il un geste d'urgence et non une configuration ? Quel rôle jouera `hp01` (module 09) ?
2. QCM — Le stockage `local-nvme` est en ZFS et `pve01` a 128 Go de RAM. Sans réglage, l'ARC peut occuper :
   a) au plus 4 Go, valeur fixe de ZFS ;
   b) une taille plafonnée par l'installateur Proxmox (10 % de la RAM, au plus 16 Go) si la racine a été installée en ZFS, sinon la valeur par défaut d'OpenZFS, qui dépend de sa version ;
   c) toute la RAM libre, sans limite ;
   d) 1 Go par To de disque, règle appliquée automatiquement.
   Comment le vérifier sur `pve01`, et pourquoi la RAM « utilisée » par l'ARC n'est-elle pas libérée aussi vite qu'un cache de pages ?
3. Tu as 128 Go de RAM. Le socle prend ~24 Go, le profil k8s ~36 Go. Peux-tu lancer en même temps le profil openstack (~48 Go) en comptant sur le ballooning et KSM ? Raisonne en chiffres et en risques (OOM killer de l'hôte, quelles VMs il tuera, effet sur ZFS).
4. Explique le fonctionnement de KSM sur Proxmox (`ksmtuned`, seuil de déclenchement). Dans quels cas le gain est-il important ? Quel risque de sécurité (canal auxiliaire) est associé à la déduplication mémoire entre VMs, et pourquoi c'est un sujet pour un hébergeur HDS multi-clients ?
5. QCM — Le *ballooning* d'une VM Debian avec `memory: 8192` et `balloon: 2048` :
   a) garantit 8 Go à la VM en toutes circonstances ;
   b) laisse la VM démarrer avec 8 Go, puis l'hôte peut reprendre de la mémoire jusqu'à ne lui laisser que 2 Go lorsque sa propre RAM dépasse un seuil d'occupation ;
   c) démarre la VM avec 2 Go et augmente jusqu'à 8 Go à la demande de l'invité ;
   d) ne fonctionne que si l'agent QEMU est installé.
   Pourquoi désactive-t-on souvent le ballooning pour une base de données ou un routeur ?
6. Le thin provisioning permet d'allouer 6 To de disques virtuels sur 2 To de NVMe. Quels sont les deux mécanismes qui rendent l'espace (côté invité et côté hôte) ? Que se passe-t-il pour les VMs quand un LVM-thin ou un zpool atteint 100 % ? Comment le surveilles-tu ?
7. La virtualisation imbriquée sera massivement utilisée (cluster Proxmox imbriqué, OpenStack, Kubernetes dans des VMs). Quel est son coût en performance (CPU, I/O, latence réseau) et qu'est-ce qui l'aggrave ? Quelle option CPU faut-il pour que l'invité expose VT-x ?
8. QCM — Pour une VM qui devra être migrée à chaud entre `pve01` (Xeon E-2378G) et un nœud à base de Xeon E3-1220L v2, le type de CPU adapté est :
   a) `host` ;
   b) `x86-64-v2-AES` ;
   c) `x86-64-v3` ;
   d) `kvm64`.
   Explique pour chaque réponse pourquoi elle convient ou non.
9. Un collègue propose `cache=unsafe` sur toutes les VMs « parce que c'est plus rapide ». Que réponds-tu ? Dans quel cas précis du workbook pourrait-il être acceptable ?
10. Tu dois dimensionner les vCPU : 8 cœurs / 16 threads physiques. Quel ratio vCPU/thread est raisonnable pour des VMs peu chargées ? pour des nœuds Ceph ou etcd ? Quel indicateur observes-tu pour savoir si tu as trop surchargé (*CPU steal*, temps d'attente d'ordonnancement) ?
11. `gw01` est une VM unique : routeur, NAT, pare-feu, NTP, relais DHCP, VPN. Fais l'analyse de risque (SPOF) : impacts d'une panne, d'une mise à jour, d'une erreur de règle. Que prépare le plan d'adressage avec les adresses `.2-.3` réservées, et que fera le module 07 ?
12. Que se passe-t-il si `pve01` redémarre et que `gw01` ne démarre pas ? Liste les services du lab touchés directement et indirectement (y compris la sauvegarde vers PAR2). Comment `pve01` lui-même reste-t-il administrable ?
13. Le jeton `wb-automation@pve!lab` fuite dans un dépôt Git public. Quelles conséquences avec la séparation des privilèges et le rôle `WBAutomation` ? Quelles sont tes actions, dans l'ordre, dans la première heure ?
14. Cite quatre mesures de sécurisation de l'API Proxmox (port 8006) au-delà du mot de passe, et pour chacune ce qu'elle protège et ce qu'elle ne protège pas.
15. QCM — Le pare-feu Proxmox est activé au niveau datacenter avec `policy_in: DROP`. Une VM a `firewall=1` sur son interface mais aucun fichier `<VMID>.fw` n'existe. Son trafic entrant est :
   a) bloqué, car la politique datacenter s'applique à la VM ;
   b) non filtré, car le pare-feu de la VM n'est pas activé dans ses options ;
   c) filtré uniquement par les règles de l'hôte ;
   d) bloqué seulement pour les ports de gestion de l'IPSet `management`.
16. Pourquoi l'agent QEMU et le *fs-freeze* améliorent-ils la cohérence des sauvegardes, et pourquoi cela ne suffit-il pas pour une base PostgreSQL ? Que faudra-t-il au module 27 ?
17. Un disque NVMe grand public de 2 To a une endurance de 1 200 TBW. ZFS avec des VMs Ceph imbriquées écrit 400 Go/jour. Combien de temps tiendra-t-il ? Quels réglages ou choix d'architecture réduisent l'usure ? Comment suivre l'usure (`smartctl`) ?
18. Tu dois expliquer à Claire pourquoi un PBS sur le même site physique (ici, la même maison) ne constitue pas un PRA. Que manque-t-il pour respecter la règle 3-2-1, et quelle est la réponse « MédiSphère » à terme ?

Les réponses argumentées sont dans le corrigé.

---

### M00-E36 — Chiffrer les sauvegardes côté client  `LAB` `★★★`

> **Ticket SEC-136** — *De : Sophie Laurent*
> Les sauvegardes des VMs contiennent, ou contiendront, des données de santé. Elles partent sur un autre site, sur une machine que d'autres pourraient administrer un jour. Je veux qu'elles soient chiffrées **avant** de quitter PAR1, et que la clé ne soit jamais présente sur PAR2.
> Et je veux une procédure de conservation de la clé qui survive à la perte totale de PAR1.

**Objectifs pédagogiques**
- Comprendre le chiffrement côté client de PBS (AES-256-GCM, clé détenue par le client, PBS ne voit que des blocs chiffrés).
- Générer, exporter (paperkey) et conserver une clé de chiffrement hors ligne.
- Mesurer les conséquences : déduplication, sauvegardes existantes, restauration, perte de clé.
- Tester une restauration à partir d'une sauvegarde chiffrée.

**Prérequis** : M00-E22, M00-E23, M00-E30.
**Durée indicative** : 1 h 30.

> ⚠️ **Attention** : une clé perdue = des sauvegardes **définitivement** irrécupérables. Aucun support, aucun outil ne les déchiffrera. Ne passe pas à l'étape 3 avant d'avoir terminé et vérifié l'étape 2.

**Travail demandé**
1. Lis la documentation du chiffrement côté client de PBS. Réponds : où se trouve la clé ? qu'est-ce qui est chiffré, qu'est-ce qui ne l'est pas (noms de groupes, horodatages, tailles) ? Les blocs chiffrés se dédupliquent-ils avec les blocs en clair existants ?
2. Génère une clé de chiffrement pour le stockage `pbs-par2` (interface : *Datacenter → Storage → pbs-par2 → Encryption*, ou `pvesm set pbs-par2 --encryption-key …`, voir `man pvesm`). Repère le fichier de clé créé sous `/etc/pve/priv/storage/`. Immédiatement :
   - exporte une **paperkey** (`proxmox-backup-client key paperkey <FICHIER> --output-format text`) et imprime-la ou recopie-la dans ton gestionnaire de mots de passe ;
   - copie le fichier de clé sur un support hors ligne (clé USB rangée hors du lab) ;
   - vérifie l'empreinte de la clé (`proxmox-backup-client key show <FICHIER>`) et note-la à côté de la copie.
3. Lance une sauvegarde de `dns01` vers `pbs-par2`. Observe dans le journal de la tâche ce qui change (lecture complète ? taille transférée ?). Dans l'interface de PBS, compare l'instantané chiffré et les précédents.
4. Les sauvegardes antérieures restent en clair : décide (et écris) ce que tu en fais, en tenant compte de la rétention et du besoin de restauration.
5. Vérifie que la sauvegarde de configuration de M00-E30 est désormais chiffrée elle aussi (relance `wb-backup-config.service`). Réfléchis : la clé de chiffrement se trouve dans `/etc/pve/priv/`, qui fait partie de cette sauvegarde. Est-ce un problème ? Que se passe-t-il le jour où `pve01` est perdu ?
6. **Test de restauration** : restaure la dernière sauvegarde chiffrée de `dns01` sous le VMID **5092**, dans le pool `lab`, **sans la démarrer** sur le réseau de production (déconnecte son interface ou change de VNet avant le premier démarrage). Vérifie qu'elle démarre, puis supprime-la.
7. **Exercice de perte de clé (simulé)** : sur `adm01`, à partir de la seule paperkey, reconstitue un fichier de clé et vérifie que son empreinte est identique à l'originale. Ne touche pas au fichier de clé de `pve01`.
8. Rédige la procédure de conservation de la clé : emplacements, personnes ayant accès, vérification périodique, rotation (que se passe-t-il pour les anciennes sauvegardes si on change de clé ?).

**Critères de réussite**
- [ ] Le stockage `pbs-par2` dispose d'une clé de chiffrement.
- [ ] Une sauvegarde de VM de moins de 48 h sur `pbs-par2` est chiffrée.
- [ ] Le dernier instantané `host/<NŒUD>` (M00-E30) est chiffré.
- [ ] Une restauration vers le VMID 5092 a réussi, et la VM 5092 n'existe plus.
- [ ] La paperkey et une copie hors ligne existent ; l'empreinte reconstruite depuis la paperkey est identique.
- [ ] La procédure de conservation de la clé est rédigée.

**Vérification** : `lab/bin/check 00 36`

<details><summary>Indice 1</summary>

Une clé générée par Proxmox pour un stockage PBS n'est pas protégée par une phrase de passe (elle doit être lisible par `vzdump` sans intervention). C'est précisément pour cela qu'elle ne doit pas se trouver sur PAR2.
</details>

<details><summary>Indice 2</summary>

`qmrestore` accepte `--pool`, `--storage` et `--unique`. Pour éviter un conflit d'adresse IP au premier démarrage, modifie l'interface réseau de la VM restaurée **avant** de la démarrer (`qm set 5092 --net0 …,link_down=1`).
</details>

<details><summary>Indice 3</summary>

`proxmox-backup-client key import-with-master-key` n'est pas la bonne piste : il sert à la clé maîtresse RSA. Ouvre la version texte de la paperkey : ce qui se trouve entre les marqueurs `BEGIN` et `END` est directement exploitable par `proxmox-backup-client key show`.
</details>

**Pour aller plus loin** (facultatif) : clé maîtresse RSA (option `master-pubkey` du stockage) pour pouvoir déchiffrer avec une clé détenue hors du site même si la clé de chiffrement est perdue ; synchronisation vers un second PBS avec chiffrement de bout en bout.

---

### M00-E37 — Exercice de restauration chronométré  `CHRONO` `★★★`

> **Ticket PLAT-137** — *De : Nadia Roussel*
> Exercice de continuité imposé par l'audit HDS : on simule la perte de `dns01`. Objectif : service DNS rétabli en **moins de 20 minutes** à partir de la sauvegarde PBS, chrono en main. Je veux la feuille de temps et ton retour d'expérience à la fin.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas de notes autres que **tes** runbooks (M00-E25) et la documentation officielle.
- Durée cible : **20 minutes** entre l'incident (T0) et le service rétabli (T4).
- Scénario **sans destruction** : la VM 1002 n'est pas supprimée. On l'arrête brutalement pour simuler sa perte, et on restaure sa dernière sauvegarde sous le VMID **5091**, qui la remplace.
- À la fin, **une seule** des deux VMs (1002 ou 5091) doit tourner, et l'état doit être cohérent et documenté : soit tu reviens à 1002 (retour nominal), soit tu gardes 5091 comme `dns01` officielle (et tu expliques ce que cela implique pour la convention de VMID du PLAN et pour les sauvegardes planifiées).

**Prérequis** : M00-E22, M00-E23, M00-E25, M00-E36 (sauvegardes chiffrées : la clé est sur `pve01`). Une sauvegarde de `dns01` de moins de 24 h doit exister sur `pbs-par2` : vérifie-le **avant** de lancer le chrono (c'est de la préparation, pas de l'incident).
**Durée** : 20 minutes chronométrées + 30 minutes de retour d'expérience.

**Déroulé**
1. Prépare ta feuille de temps (ci-dessous) et un chronomètre.
2. T0 — Simule la perte :
   ```
   root@pve01:~# qm stop 1002
   ```
   (arrêt brutal, équivalent d'une coupure : pas de `shutdown` propre.) À partir de là, le chrono tourne.
3. Constate le symptôme depuis `adm01`, décide, restaure, vérifie : c'est à toi.
4. Arrête le chrono quand `adm01` résout à nouveau `adm01.par1.medisphere.internal` et un nom Internet **via** 10.10.20.10, et que le relais DHCP du VLAN SANDBOX fonctionne.
5. Remets ensuite le lab dans un état cohérent (sans chrono).

**Feuille de temps à remplir**

| Jalon | Définition | Heure | Écart depuis T0 | Commentaire |
|---|---|---|---|---|
| T0 | Incident (arrêt de 1002) | | 0 | |
| T1 | Détection confirmée (symptôme observé et attribué à `dns01`) | | | |
| T2 | Décision (point de restauration choisi, VMID cible, stockage cible) | | | |
| T3 | Restauration terminée (tâche `qmrestore` OK) | | | |
| T4 | Service vérifié (DNS interne + externe + DHCP SANDBOX) | | | |
| T5 | Retour à l'état cohérent (une seule VM active, `onboot` cohérent, pool) | | | |

Calcule ensuite : **RTO mesuré** = T4 − T0 ; **RPO effectif** = T0 − heure de la sauvegarde restaurée.

**Retour d'expérience à rédiger** (une demi-page) : ce qui a pris le plus de temps, ce qui t'a surpris, ce qui manque dans ton runbook M00-E25 (mets-le à jour), comment descendre sous 10 minutes.

**Où ranger** : dans le dépôt de documentation (M00-E25), la feuille de temps et le retour d'expérience dans `docs/socle/tests/restauration.md` (une section datée par test, le plus récent en tête : M00-E50 y ajoutera le sien), et la mise à jour du runbook dans `docs/socle/runbooks/RB-002-restaurer-une-vm.md`. Commite.

**Critères de réussite**
- [ ] Une restauration de `dns01` vers le VMID 5091 a été réalisée avec succès.
- [ ] `dns01` (10.10.20.10) répond pour la zone interne et pour un nom Internet.
- [ ] Exactement une des VMs 1002 et 5091 est en marche ; elle est dans le pool `lab` et démarre automatiquement, l'autre (si elle existe encore) ne démarre pas automatiquement.
- [ ] La feuille de temps est remplie ; RTO et RPO sont calculés ; le RTO est inférieur à 20 minutes (sinon, refais l'exercice après avoir amélioré le runbook).
- [ ] Le retour d'expérience est rédigé et le runbook M00-E25 mis à jour ; les deux sont commités dans `~/medisphere/docs/socle/`.

**Vérification** : `lab/bin/check 00 37`

**Pour aller plus loin** (facultatif) : refais l'exercice avec la restauration à chaud (*live restore*) de PBS et compare les RTO ; refais-le en restaurant `gw01` (beaucoup plus intéressant : sans routeur, comment atteins-tu PBS ?).
