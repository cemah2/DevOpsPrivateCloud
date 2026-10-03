# Module 00 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

Points non testés en conditions réelles (signale tes retours) : la syntaxe exacte de quelques paramètres d'API récents (webhook PVE, filtres `regex:` sur les champs, `notification-mode` des datastores PBS, `proxmox-backup-client key import` d'une paperkey) peut varier d'une version mineure à l'autre ; ils sont signalés « à vérifier selon ta version ».

---

### M00-E27 — Durcir l'accès à `pve01`

**Solution**

*Étape 0 — filets de sécurité.* Vérifie l'accès console (iLO/IPMI ou écran/clavier) et le mot de passe `root` **avant** tout. Ouvre deux sessions SSH.

*Étape 1 — TFA.* Dans l'interface web, connecté en `root@pam` : *Datacenter → Permissions → Two Factor → Add → TOTP*, scanne le QR code, saisis un code pour valider. Puis *Add → Recovery Keys* : Proxmox affiche une liste de clés à usage unique **une seule fois** ; range-les dans ton gestionnaire de mots de passe. Même chose pour `wb-admin@pve` (connecte-toi avec ce compte, ou ajoute-le depuis `root` : Proxmox redemande alors le mot de passe de l'utilisateur courant). Contrôle :

```
root@pve01:~# pveum user tfa list
root@pve01:~# pvesh get /access/tfa/root@pam --output-format json-pretty
```

Tu dois voir une entrée `totp` et une entrée `recovery` par compte. La configuration est stockée dans `/etc/pve/priv/tfa.cfg` (depuis PVE 7.2 ; avant, dans `user.cfg`).

Réponses aux questions :
- **SSH** : non. Le TFA de Proxmox protège l'obtention d'un *ticket* (interface web, `pvesh` à distance, API avec identifiant/mot de passe). SSH passe par PAM/sshd, pas par Proxmox. D'où l'étape 2.
- **Jeton API** : non. Un jeton est déjà un secret de « second niveau » ; il ne passe pas par le TFA. D'où l'importance de la séparation des privilèges et du moindre privilège (M00-E17), et de la rotation.
- **Console physique** : non (login PAM local).
- **Réinitialisation** : depuis un shell root (console ou SSH par clé) : `pveum user tfa delete root@pam` (supprime toutes les entrées, ou une seule avec `--id`). Si le compte est verrouillé après trop d'échecs TOTP, `pveum user tfa unlock root@pam` (PVE 8.x et suivants, à vérifier selon ta version). C'est pour ça que l'accès console et SSH par clé ne doivent pas dépendre du TFA.

*Étape 2 — SSH.* D'abord la vérification :

```
root@pve01:~# ls -l /root/.ssh/
lrwxrwxrwx 1 root root 29 … authorized_keys -> /etc/pve/priv/authorized_keys
```

Sur une installation Proxmox, `authorized_keys` de `root` est un lien vers `/etc/pve/priv/authorized_keys` (partagé entre les nœuds d'un cluster ; selon la version, ce lien peut avoir évolué : vérifie chez toi). Ajoute tes clés dans la **cible** (`/etc/pve/priv/authorized_keys`), ne remplace jamais le lien par un fichier.

Fichier [`fichiers/M00-E27/10-durcissement.conf`](fichiers/M00-E27/10-durcissement.conf) dans `/etc/ssh/sshd_config.d/`, puis :

```
root@pve01:~# sshd -t && sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication)'
permitrootlogin without-password
passwordauthentication no
kbdinteractiveauthentication no
root@pve01:~# systemctl reload ssh
```

`without-password` est l'ancien nom (toujours affiché par certaines versions de `sshd -T`) de `prohibit-password`. Test depuis une **troisième** session :

```
admin@adm01:~$ ssh -o ControlPath=none -o PubkeyAuthentication=no root@pve01
root@pve01: Permission denied (publickey).
```

Le message `(publickey)` est la preuve : le serveur n'offre plus que cette méthode. (`ControlPath=none` : sans lui, le multiplexage SSH configuré sur `adm01` en M00-E15 réutiliserait une connexion déjà authentifiée et le test serait faussé.)

*Étape 3 — pare-feu.* Fichiers complets : [`cluster.fw`](fichiers/M00-E27/cluster.fw) et [`host.fw`](fichiers/M00-E27/host.fw). En CLI, dans l'ordre :

```
root@pve01:~# pvesh create /cluster/firewall/ipset --name management --comment "Réseaux d'administration"
root@pve01:~# for c in <LAN-MAISON> 10.10.10.0/24 10.255.1.0/24; do pvesh create /cluster/firewall/ipset/management --cidr "$c"; done
root@pve01:~# pvesh create /cluster/firewall/rules --type in --action ACCEPT --source +management --proto tcp --dport 8006 --enable 1 --comment "GUI/API"
root@pve01:~# pvesh create /cluster/firewall/rules --type in --action ACCEPT --source +management --proto tcp --dport 22 --enable 1 --comment "SSH"
root@pve01:~# pvesh create /cluster/firewall/rules --type in --action ACCEPT --source +management --proto icmp --icmp-type echo-request --enable 1 --comment "ping"
root@pve01:~# pve-firewall localnet
```

`pve-firewall localnet` affiche le réseau local détecté et indique si l'IPSet `management` le remplace. L'IPSet **nommé exactement** `management` est spécial : les adresses qu'il contient sont autorisées à joindre les services de gestion de l'hôte (8006, 22, 3128 pour SPICE, 5900-5999 pour VNC) par des règles implicites générées par `pve-firewall`. Nos règles explicites sont donc redondantes pour 8006/22 ; on les écrit quand même parce qu'elles **documentent l'intention**, qu'elles restent valables si quelqu'un renomme ou vide l'IPSet par erreur, et qu'un auditeur les lit sans connaître la règle implicite. Note : depuis PVE 8.x, les références peuvent être préfixées par leur portée (`+dc/management`) ; la forme courte reste acceptée.

Avant d'activer, les pare-feu de VMs déjà configurés (que l'interrupteur du datacenter réveillerait) :

```
root@pve01:~# grep -l '^enable: *1' /etc/pve/firewall/[0-9]*.fw 2>/dev/null
root@pve01:~# grep -H 'firewall=1' /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf 2>/dev/null
```

Une VM qui apparaît dans **les deux** listes sera filtrée par ses propres règles (politique entrante `DROP` par défaut) dès l'activation du datacenter. Si c'est une VM personnelle, relis ses règles avec toi-même comme propriétaire, ou désactive son pare-feu de VM (`enable: 0`) **avant** d'aller plus loin. Une VM de la première liste seulement n'est pas filtrée (sans `firewall=1` sur la carte, rien ne s'applique).

Homme mort, puis activation :

```
root@pve01:~# apt install -y at
root@pve01:~# echo "pve-firewall stop" | at now + 10 minutes
job 3 at …
root@pve01:~# pvesh set /cluster/firewall/options --enable 1 --policy_in DROP --policy_out ACCEPT
root@pve01:~# pve-firewall status
Status: enabled/running
root@pve01:~# pve-firewall compile | grep -A3 PVEFW-HOST-IN | head -30
```

Alternative sans `at` : `systemd-run --on-active=10m /usr/sbin/pve-firewall stop` (annulation : `systemctl stop run-<ID>.timer`). Tests depuis `adm01`, le poste (LAN) et le poste via `wg1`, puis `atrm 3`.

*Le cas de la sandbox et du VPN.* Avec le jeu de règles de référence de `gw01` (M00-E26) :
- `gw01` ne masque **pas** le trafic à destination de `<IP-PVE01>` (`ip daddr != $PVE01` dans `postrouting`) : `pve01` voit les vraies adresses 10.10.x.x (vérifie avec `ss -tn` : la connexion SSH de `adm01` arrive de 10.10.10.10). C'est ce qui rend l'entrée `10.10.10.0/24` de l'IPSet indispensable, et c'est aussi ce qui permet au pare-feu de `pve01` de distinguer les VLANs.
- Depuis `sbx01`, `pve01` est injoignable : la chaîne `forward` de `gw01` n'autorise vers `<IP-PVE01>` que MGMT (22, 8006) ; la règle de sortie Internet exclut `<LAN-MAISON>`. Le paquet meurt sur `gw01` (compteur « rejeté par la politique », journal `nft-fwd-drop`), avant même d'atteindre `pve01`. Défense en profondeur : même si `gw01` laissait passer, la source 10.10.99.x n'est pas dans `management`.
- Depuis un poste en `wg1` (10.255.1.2) qui route `<IP-PVE01>` dans le tunnel (cas du poste en déplacement, M00-E16) : la chaîne `forward` de `gw01` autorise `wg1` vers `pve01` sur 22 et 8006 (règle « VPN d'admin vers pve01 », M00-E16), sans masquage (`postrouting` ne traite que les sources 10.10.0.0/16 et le LAN maison vers `wg0`). `pve01` voit donc la source 10.255.1.2, d'où l'entrée `10.255.1.0/24` de l'IPSet, et répond par sa route 10.255.1.0/24 via `<IP-GW01-WAN>` (posée en M00-E10). Si le poste est sur le LAN maison sans router `<IP-PVE01>` dans le tunnel, il joint `pve01` directement : source `<LAN-MAISON>`, également dans l'IPSet.
- Si ton `gw01` masquait tout le trafic sortant par `ens18` (règle `masquerade` sans exception), toute VM du lab capable de traverser `gw01` serait vue par `pve01` avec l'adresse WAN de `gw01`, qui appartient à `<LAN-MAISON>` donc à `management` : le pare-feu de `pve01` serait contourné. C'est l'argument qui justifie l'exception dans `postrouting`.

*Étape 5 — procédure de secours* (exemple) :
1. Se connecter à la console (iLO/IPMI ou écran) en `root` avec le mot de passe.
2. `pve-firewall stop` (coupe toutes les règles jusqu'au prochain démarrage du service).
3. Corriger `/etc/pve/firewall/cluster.fw` (IPSet, règles) ou `/etc/ssh/sshd_config.d/10-durcissement.conf`.
4. `pve-firewall compile` pour relire, puis `pve-firewall start`.
5. Pour le TFA perdu : `pveum user tfa delete <USER>`, puis réenrôler.
6. Consigner l'incident (ticket INC).

**Explications**

Le pare-feu Proxmox est hiérarchique : le **datacenter** (`cluster.fw`) porte les options globales, les IPSets, les alias, les groupes de sécurité et les règles appliquées à tous les hôtes ; l'**hôte** (`host.fw`) affine pour un nœud ; chaque **VM** (`<VMID>.fw`) a son propre jeu, qui ne s'applique que si (1) le pare-feu de la VM est activé dans ses options et (2) l'interface a `firewall=1`. Activer le datacenter ne filtre donc **aucune** VM dont le pare-feu n'était pas déjà activé : c'est voulu, et c'est ce qui protège tes VMs personnelles — à condition d'avoir vérifié, avant, qu'aucune d'elles n'avait un pare-feu de VM activé « en sommeil » (sous-étape 4). Techniquement, `pve-firewall` génère des chaînes iptables (`PVEFW-*`) — ou nftables avec le nouveau `proxmox-firewall` — et, pour une VM filtrée, insère un bridge intermédiaire `fwbr<VMID>i<N>` qui permet à netfilter de voir le trafic bridgé.

Pour SSH, la règle « première valeur lue gagne » d'OpenSSH et l'`Include` placé **en tête** de `sshd_config` sous Debian expliquent qu'un fichier de `sshd_config.d/` prime sur le fichier principal (y compris sur un `PermitRootLogin yes` hérité de l'installation).

**Alternatives**
- Restreindre l'écoute de `pveproxy` : `/etc/default/pveproxy` accepte `ALLOW_FROM`, `DENY_FROM`, `POLICY` et `LISTEN_IP` (filtrage applicatif, complémentaire du pare-feu).
- Mettre l'interface d'administration derrière le VPN uniquement (IPSet réduit à `10.255.1.0/24` + console) : plus strict, mais il faut un accès de secours.
- Authentification OIDC (Keycloak, module 24) avec TFA porté par l'IdP.
- Clés FIDO2/WebAuthn plutôt que TOTP (résistantes à l'hameçonnage), possibles dans Proxmox si l'interface est servie sur un nom de domaine avec un certificat valide.

**Pièges classiques**
- Activer le pare-feu **avant** d'avoir créé l'IPSet : coupure immédiate si ta source n'est pas dans le réseau local détecté.
- Remplacer le lien `/root/.ssh/authorized_keys` par un fichier, ou éditer `/root/.ssh/authorized_keys` en croyant éditer le fichier partagé (ou l'inverse).
- Recharger sshd sans `sshd -t` ; fermer la seule session ouverte avant d'avoir testé.
- Oublier `KbdInteractiveAuthentication no` : PAM peut encore demander un mot de passe par ce biais.
- Croire que le TFA protège l'API par jeton ou SSH.
- Ne pas sauvegarder les clés de récupération (elles ne sont affichées qu'une fois).
- Un `masquerade` sans exception sur `gw01` : toutes les VMs du lab apparaissent à `pve01` avec l'adresse WAN de `gw01`, donc comme venant du LAN maison, et passent l'IPSet.

**En production chez MédiSphère**
Accès d'administration uniquement depuis un réseau d'administration dédié et un bastion (module 06, certificats SSH), SSO avec MFA matériel (module 24), comptes nominatifs (pas de `root` partagé), journalisation des connexions envoyée vers un SIEM (module 22), revue trimestrielle des comptes et des jetons, procédure de « bris de glace » (compte de secours scellé, utilisation tracée).

---

### M00-E28 — Migrer le réseau du lab vers Proxmox SDN

**Solution**

*1. État des lieux.*

```
root@pve01:~# grep -n 'interfaces.d' /etc/network/interfaces
NN:source /etc/network/interfaces.d/*
root@pve01:~# dpkg -l libpve-network-perl | tail -1
root@pve01:~# ls -l /etc/network/interfaces.new 2>/dev/null || echo "rien en attente"
root@pve01:~# for v in 1000 1001 1002 9000; do echo "== $v"; qm config $v | grep '^net'; done
```

Si la ligne `source` manque (installations anciennes), ajoute-la en fin de fichier : sans elle, la configuration SDN est écrite mais jamais chargée.

*2. Zone et VNets* : script [`fichiers/M00-E28/sdn-lab.sh`](fichiers/M00-E28/sdn-lab.sh). Le cœur :

```
root@pve01:~# pvesh create /cluster/sdn/zones --zone lab --type vlan --bridge vmbr1
root@pve01:~# pvesh create /cluster/sdn/vnets --vnet vinfra --zone lab --tag 20 --alias INFRA
…
root@pve01:~# pvesh get /cluster/sdn/vnets --pending 1
```

Avant application, les objets existent dans `/etc/pve/sdn/*.cfg` (configuration partagée, versionnée par pmxcfs) avec un état « new » dans la vue *pending*, mais rien n'existe sur l'hôte. Les identifiants de zone et de VNet sont limités à 8 caractères alphanumériques : c'est pour cela que le PLAN utilise `vsandbox`, `vstoclu`…

*3. Application.*

```
root@pve01:~# pvesh set /cluster/sdn
root@pve01:~# cat /etc/network/interfaces.d/sdn
root@pve01:~# ip -d link show vinfra
root@pve01:~# bridge vlan show
```

Sur un bridge parent VLAN-aware, le SDN crée pour chaque VNet un bridge Linux du même nom (`vinfra`) dont l'unique port est une **sous-interface VLAN du bridge parent lui-même**, `vmbr1.20` (strophes `iface vinfra` avec `bridge_ports vmbr1.20` dans `/etc/network/interfaces.d/sdn`). Une trame de la VM entre non taguée dans `vinfra`, sort par `vmbr1.20`, qui la tague 20 et la remet à `vmbr1` par son interface propre (`bridge vlan show dev vmbr1` montre le VLAN 20 sur le bridge lui-même, entrée `self`, ajoutée par ifupdown2) ; `vmbr1` la commute ensuite vers le port trunk de `gw01`, où elle sort taguée 20. Aucun port supplémentaire n'apparaît dans `ip link show master vmbr1`. Sur un bridge parent **non** VLAN-aware, le SDN génère à la place un bridge `vmbr1v20` relié au VNet par une paire veth (`ln_vinfra`/`pr_vinfra`). ⚠️ À vérifier sur ta version : lis `/etc/network/interfaces.d/sdn`, le code de génération a évolué entre versions de `libpve-network-perl`.

*4. Le cas `gw01`.* Un VNet de zone VLAN est un **port d'accès** sur un seul VLAN. `gw01` a besoin du **trunk** (tous les VLANs routés, tagués, sur une seule interface `ens19` avec sous-interfaces). Il reste donc branché directement sur `vmbr1` sans tag. C'est normal et durable : le SDN cohabite avec les ports classiques du bridge parent.

*5. Migration*, avec [`fichiers/M00-E28/migrer-vm-vnet.sh`](fichiers/M00-E28/migrer-vm-vnet.sh), ou à la main :

```
root@pve01:~# qm config 1002 | grep ^net0
net0: virtio=BC:24:11:AA:BB:CC,bridge=vmbr1,tag=20
root@pve01:~# qm set 1002 --net0 virtio=BC:24:11:AA:BB:CC,bridge=vinfra
admin@adm01:~$ ping -c3 10.10.20.10 && dig +short @10.10.20.10 adm01.par1.medisphere.internal && ssh dns01 'ping -c2 10.10.20.1 && getent hosts deb.debian.org'
```

Retour arrière : `qm set 1002 --net0 virtio=BC:24:11:AA:BB:CC,bridge=vmbr1,tag=20`. Le changement est appliqué à chaud (la carte est rebranchée, l'invité voit un bref *link down/up*). Ordre conseillé : `dns01` (si ça casse, `adm01` le voit tout de suite), puis `adm01` (depuis ton poste via `wg1`, session ouverte en filet), puis les sandbox (`bridge=vsandbox`). Pour le template :

```
root@pve01:~# qm set 9000 --net0 virtio,bridge=vsandbox
```

Proxmox accepte en général la modification des options non disque d'un template ; si ta version refuse, laisse-le et précise `--net0` au clonage (et dans les modules IaC). Au passage, vérifie que la relance DHCP d'une VM sandbox fonctionne toujours (relais de `gw01` inchangé).

*6. Droits* : [`fichiers/M00-E28/acl-sdn.sh`](fichiers/M00-E28/acl-sdn.sh).

```
root@pve01:~# pveum acl modify /sdn/zones/lab --groups wb-admins --roles PVESDNUser
root@pve01:~# pveum acl modify /sdn/zones/lab --users wb-automation@pve --roles PVESDNUser
root@pve01:~# pveum acl modify /sdn/zones/lab --tokens 'wb-automation@pve!lab' --roles PVESDNUser
root@pve01:~# pveum user token permissions wb-automation@pve lab --path /sdn/zones/lab/vsandbox
```

`PVESDNUser` (SDN.Audit + SDN.Use) suffit pour brancher une VM sur un VNet. On pourrait réutiliser `WBAutomation` (qui contient SDN.Use) sur ce chemin, mais un rôle prédéfini et minimal sur un chemin SDN se lit mieux à l'audit. Pour aller plus fin, on peut n'ouvrir au jeton que `/sdn/zones/lab/vsandbox` et les VNets des modules à venir, et retirer `vmgmt`/`vinfra` : l'automatisation n'a pas à créer de VM dans MGMT. Rappel : depuis PVE 8, brancher une VM sur un bridge classique exige aussi `SDN.Use` sur `/sdn/zones/localnetwork/<bridge>` — c'est pour cela que M00-E17 a dû ouvrir `vmbr1` au jeton ; après la migration, retire ce droit s'il n'est plus nécessaire (sauf pour `gw01`, géré par un humain).

*7. Bilan* (exemple) :

| Avantages du SDN | Limites |
|---|---|
| Réseaux nommés (`vinfra`) au lieu d'un couple bridge/tag : moins d'erreurs de saisie | Couche supplémentaire à comprendre et à déboguer (sous-interfaces `vmbr1.<VLAN>`, bridges générés) |
| Droits par réseau (`SDN.Use` par VNet) : délégation fine | Configuration en deux temps (en attente / appliquée), oubli fréquent de l'application |
| Configuration centralisée dans `/etc/pve/sdn`, identique sur tous les nœuds d'un cluster | Application = `ifreload` de l'hôte : un risque à chaque changement |
| Préparation des zones VXLAN/EVPN du module 09 (réseaux multi-nœuds) | Un trunk (cas `gw01`) reste hors SDN dans une zone VLAN |
| Inventaire des réseaux lisible par l'API (Terraform, NetBox) | IPAM et DHCP intégrés limités : DHCP uniquement pour les zones Simple (dnsmasq), IPAM PVE/NetBox/phpIPAM à évaluer |

Pourquoi pas l'IPAM/DHCP du SDN ici : le DHCP intégré n'est disponible que pour les zones Simple (et pose la passerelle sur l'hôte), alors que la passerelle de nos VLANs est `gw01` ; la source de vérité IPAM sera NetBox (module 06) et le DHCP Kea (module 06). On évite donc deux sources de vérité concurrentes.

**Explications**

Le SDN Proxmox est un **générateur de configuration ifupdown2** : zones (technologie de transport : VLAN, QinQ, VXLAN, EVPN, Simple), VNets (un réseau virtuel = un bridge Linux sur chaque nœud), sous-réseaux (IPAM, passerelle, SNAT, DHCP selon la zone). La configuration déclarée est partagée par pmxcfs ; `pvesh set /cluster/sdn` la *compile* en `/etc/network/interfaces.d/sdn` sur chaque nœud et lance `ifreload -a`. Une VM sur un VNet référence simplement `bridge=<vnet>` : le tag n'est plus dans la configuration de la VM, il est dans celle du VNet. Changer de VLAN pour tout un réseau devient une modification du VNet, pas de N VMs.

**Alternatives**
- Garder les bridges taggés et générer la configuration des VMs par IaC (module 05) : même bénéfice contre les fautes de frappe, sans les droits par réseau.
- Open vSwitch (module 07) avec des *fake bridges* : autre modèle, utile pour l'apprentissage OVS, pas nécessaire ici.

**Pièges classiques**
- Oublier `pvesh set /cluster/sdn` : les VNets « existent » dans l'interface mais `qm start` échoue (bridge inexistant).
- `source /etc/network/interfaces.d/*` absent : rien n'est chargé, sans erreur visible.
- `qm set --net0 virtio,bridge=vinfra` sans MAC : nouvelle MAC, et selon la configuration réseau générée par cloud-init (correspondance par MAC), l'invité peut ne plus configurer son interface.
- Migrer `gw01` vers un VNet : le lab entier perd son routage.
- Modification réseau non appliquée dans l'interface (`interfaces.new`) appliquée par surprise avec le SDN.
- ACL posée sur l'utilisateur mais pas sur le jeton (ou l'inverse) avec séparation des privilèges.

**En production chez MédiSphère**
Les zones et VNets sont déclarés en IaC (provider Proxmox du module 05) et revus en MR ; chaque application d'une configuration SDN est un changement (CHG) planifié, car elle recharge le réseau des hyperviseurs ; NetBox reste la source de vérité des VLANs et préfixes, et une vérification automatique compare NetBox et `/cluster/sdn`.

---

### M00-E29 — Notifications Proxmox et PBS

**Solution**

*1. Inventaire.* Par défaut, `notifications.cfg` contient une cible `sendmail` nommée `mail-to-root` (vers l'adresse e-mail de l'utilisateur `root@pam`, définie dans *Datacenter → Permissions → Users*) et un filtre `default-matcher` sans condition qui envoie **tout** vers cette cible. Si `root@pam` n'a pas d'adresse, ou si Postfix n'a pas de relais, les messages restent dans la file locale (`mailq`) ou dans `/var/mail/root` : c'est l'incident de Nadia.

*2-3. Cible et filtres sur `pve01`* : script [`fichiers/M00-E29/notifications-pve.sh`](fichiers/M00-E29/notifications-pve.sh) (variante webhook : [`webhook-pve.sh`](fichiers/M00-E29/webhook-pve.sh)). Résultat attendu dans `/etc/pve/notifications.cfg` (extrait, le mot de passe est dans `/etc/pve/priv/notifications.cfg`) :

```
smtp: smtp-astreinte
	author pve01 (PAR1)
	comment Astreinte plateforme - PLAT-129
	from-address <ADRESSE-EXPEDITEUR>
	mailto <ADRESSE-ASTREINTE>
	mode starttls
	port 587
	server <SERVEUR-SMTP>
	username <UTILISATEUR-SMTP>

matcher: vzdump-erreurs
	comment Echecs de sauvegarde vers l'astreinte
	match-field exact:type=vzdump
	match-severity error
	mode all
	target smtp-astreinte

matcher: default-matcher
	comment Route all notifications to mail-to-root
	disable 1
	mode all
	target mail-to-root
```

Choix sur le filtre par défaut : le **désactiver** plutôt que le supprimer (il est intégré : suppression = retour à la valeur d'origine au prochain chargement selon les versions ; désactivé, l'intention est explicite). Conséquence à assumer : les événements non couverts par un filtre ne partent plus nulle part. D'où le second filtre `alertes-hyperviseur` (réplication, *fencing* — inutile en mono-nœud aujourd'hui, utile au module 09) ; les mises à jour disponibles (`package-updates`) peuvent aller vers une cible « information » distincte. Alternative valable : garder `default-matcher` mais lui ajouter `match-severity warning,error`.

*Webhook vers `adm01`* : lance `python3 recepteur-webhook.py --ecoute 10.10.10.10 --port 8099` sur `adm01`, ouvre sur `gw01` le strict nécessaire dans la chaîne `forward` (TCP 8099 de `<IP-PVE01>` et de `10.20.10.10` — l'adresse source de `pbs01` vers PAR1, fixée par les routes de son `wg0` en M00-E21 — vers `10.10.10.10`), et le pare-feu local de `adm01` s'il y en a un. Le corps est un modèle Handlebars : `{{ title }}`, `{{ message }}`, `{{ severity }}`, `{{ fields.type }}`… avec les helpers `escape` (échappement JSON) et `json` (à vérifier selon ta version). Dans l'API, la valeur des en-têtes et le corps sont transmis en base64 ; l'interface web le fait pour toi.

*4. Mode des tâches.* Dans `/etc/pve/jobs.cfg`, l'option `notification-mode` d'une tâche `vzdump` vaut `auto` (défaut), `legacy-sendmail` ou `notification-system`. En `auto`, si la tâche a un champ `mailto`, Proxmox utilise l'ancien envoi direct par sendmail à cette adresse, sinon le système de notifications. Pour éviter toute ambiguïté :

```
root@pve01:~# pvesh get /cluster/backup
root@pve01:~# pvesh set /cluster/backup/<ID-TACHE> --notification-mode notification-system --delete mailto
```

(`--delete mailto` seulement si le champ existe.)

*5. Preuve.* Ajoute temporairement `info` au filtre, sauvegarde une VM sandbox, observe la réception, puis remets `error` seul :

```
root@pve01:~# pvesh set /cluster/notifications/matchers/vzdump-erreurs --match-severity info,error
root@pve01:~# vzdump 5001 --storage pbs-par2 --mode snapshot --notification-mode notification-system
root@pve01:~# pvesh set /cluster/notifications/matchers/vzdump-erreurs --match-severity error
root@pve01:~# journalctl -u pvescheduler -u pvedaemon --since "-10 min" | grep -i notif
```

Pour voir passer une vraie notification `error` sans toucher aux sauvegardes de production : passe quelques minutes le datastore en mode maintenance `read-only` sur `pbs01` (`proxmox-backup-manager datastore update ds-lab --maintenance-mode type=read-only`), lance `vzdump 5001 --storage pbs-par2`, qui échoue, puis retire le mode maintenance (`--delete maintenance-mode`). Fais-le hors de la fenêtre de sauvegarde planifiée. Le test `info` suffit déjà à prouver la chaîne.

*6. PBS* : script [`fichiers/M00-E29/notifications-pbs.sh`](fichiers/M00-E29/notifications-pbs.sh). Les types PBS sont `gc`, `prune`, `verify`, `sync`, `acme`, `package-updates`, `tape-backup`, `tape-load` ; les notifications de datastore portent un champ `datastore`. Le mode du datastore (`notification-mode`) se règle comme pour les tâches PVE (`legacy-sendmail` envoie à l'adresse de l'utilisateur propriétaire de la tâche ; `notification-system` passe par les filtres). Les sauvegardes elles-mêmes sont notifiées **par le client** (`pve01`), pas par PBS.

**Explications**

Le système de notifications (crate Rust `proxmox-notify`, partagée par PVE et PBS) découple **qui produit** (tâche de sauvegarde, réplication, mise à jour, *fencing*, système) de **qui reçoit**. Chaque notification a une sévérité (`info`, `notice`, `warning`, `error`, `unknown`) et des champs de métadonnées (`type`, `hostname`, `job-id`, `datastore`…). Chaque filtre (*matcher*) évalue ses conditions (mode `all` = ET, `any` = OU, `invert-match` pour inverser le résultat global) et, s'il correspond, transmet aux cibles listées. Une cible reçoit au plus une fois une notification donnée même si plusieurs filtres la sélectionnent (à vérifier selon ta version). Le message est construit à partir de modèles (`/usr/share/pve-manager/templates/default/`).

**Alternatives**
- Gotify ou ntfy auto-hébergé (notification sur téléphone).
- Relais Postfix (sendmail + `relayhost`) : fonctionne aussi pour les mails système hors Proxmox (cron, smartd, zed).
- Plus tard : Alertmanager (module 21) qui reçoit les webhooks et gère déduplication, routage, astreinte et silences.

**Pièges classiques**
- Laisser le filtre par défaut actif en plus du sien : doublons, et succès quotidiens qui noient les échecs.
- `mailto` resté dans la tâche de sauvegarde avec `notification-mode auto` : le nouveau système est contourné.
- Webhook vers `adm01` bloqué par la chaîne `forward` de `gw01`, ou ouvert trop largement.
- Mot de passe SMTP en clair dans un script ou un historique shell (`read -s` + `unset`, ou interface web).
- Croire que PBS notifie les sauvegardes : il notifie GC, prune, verify, sync ; les sauvegardes sont notifiées par PVE.
- Ne jamais tester la chaîne après un changement (mot de passe SMTP expiré, certificat du relais…).

**En production chez MédiSphère**
Les notifications partent vers Alertmanager (webhook) qui route vers l'astreinte (module 21) ; les succès sont mesurés comme des métriques (« dernière sauvegarde réussie il y a moins de 26 h ») plutôt que mailés ; un test de bout en bout de la chaîne d'alerte est inscrit au calendrier mensuel.

---

### M00-E30 — Sauvegarder la configuration de l'hyperviseur

**Solution**

*1. Exploration de pmxcfs.*

```
root@pve01:~# mount | grep /etc/pve
/dev/fuse on /etc/pve type fuse (rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other)
root@pve01:~# ls -la /var/lib/pve-cluster/
-rw------- 1 root root  … config.db
-rw------- 1 root root  … config.db-shm
-rw------- 1 root root  … config.db-wal
```

`/etc/pve` est un système de fichiers FUSE servi par `pmxcfs` (service `pve-cluster`) : chaque fichier est une ligne d'une base SQLite, `/var/lib/pve-cluster/config.db`, répliquée entre les nœuds par corosync dans un cluster. Conséquences :
- une copie de `/etc/pve` est **lisible** et idéale pour restaurer un fichier précis (une configuration de VM, `storage.cfg`) ; mais pour une reconstruction complète, on ne peut pas « recopier » un arbre dans `/etc/pve` d'un coup (droits imposés, fichiers virtuels comme `.members` ou `.vmlist`, liens `local`/`qemu-server` calculés, limite de taille des fichiers) ;
- `config.db` est la forme canonique : on la restaure service arrêté, et `/etc/pve` réapparaît à l'identique ;
- copier `config.db` à chaud avec `cp` peut donner une base incohérente (écritures en cours, journal WAL `config.db-wal` non intégré). La commande `.backup` de `sqlite3` utilise l'API de sauvegarde en ligne de SQLite et produit une copie cohérente.

*2-4. Script et timer* : [`wb-backup-config.sh`](fichiers/M00-E30/wb-backup-config.sh), [`wb-backup-config.service`](fichiers/M00-E30/wb-backup-config.service), [`wb-backup-config.timer`](fichiers/M00-E30/wb-backup-config.timer).

```
root@pve01:~# apt install -y sqlite3
root@pve01:~# install -m 0750 wb-backup-config.sh /usr/local/sbin/
root@pve01:~# install -m 0644 wb-backup-config.service wb-backup-config.timer /etc/systemd/system/
root@pve01:~# systemctl daemon-reload
root@pve01:~# systemctl enable --now wb-backup-config.timer
root@pve01:~# systemctl start wb-backup-config.service
root@pve01:~# journalctl -u wb-backup-config.service -n 40 --no-pager
root@pve01:~# systemctl list-timers wb-backup-config.timer
```

Les points clés du script :
- **pas de secret dupliqué** : serveur, datastore, jeton, empreinte et namespace sont lus dans `storage.cfg` ; le secret dans `/etc/pve/priv/storage/pbs-par2.pw` ; il passe par la variable `PBS_PASSWORD` (pas en argument, donc invisible dans `ps`) ;
- `--include-dev /etc/pve` : sans cette option, `proxmox-backup-client` s'arrête aux frontières de systèmes de fichiers et **l'archive `etc.pxar` ne contient pas `/etc/pve`** — c'est le piège de l'étape 2 ;
- `--backup-type host --backup-id $(hostname)` et `--ns par1` : le groupe `host/pve01` se range à côté des `vm/1000`… du namespace, et la tâche de *prune* du namespace s'y applique (vérifie qu'elle n'est pas filtrée par type) ;
- `--keyfile` si `/etc/pve/priv/storage/pbs-par2.enc` existe (M00-E36) ;
- `umask 077` et `set -euo pipefail` : le répertoire de travail contenant `config.db` (qui contient **tous** les secrets de `/etc/pve/priv`) n'est lisible que par root, et toute erreur fait échouer le service (donc visible dans `systemctl --failed`).

Contenu sauvegardé : `/etc` entier (dont `network/interfaces*`, `hosts`, `apt/`, `ssh/`, `pve/` avec pare-feu, SDN, stockages, utilisateurs, configurations des VMs), `/root` (dont `.ssh/`), et un répertoire de travail avec `config.db` et des inventaires (versions, paquets, disques, réseau, ZFS/LVM). Si `/root` contient des fichiers volumineux (ISO, images), exclus-les (`--exclude` ou un fichier `.pxarexclude`).

*5. Vérification côté PBS.*

```
root@pve01:~# export PBS_REPOSITORY='wb-backup@pbs!pve01@10.20.10.10:ds-lab'   # le secret du jeton est demandé (ou PBS_PASSWORD)
root@pve01:~# proxmox-backup-client snapshot list --ns par1
```

*6. Restauration de test.*

```
root@pve01:~# proxmox-backup-client snapshot list host/pve01 --ns par1
root@pve01:~# proxmox-backup-client restore --ns par1 host/pve01/<HORODATAGE> etc.pxar /root/restau-test/etc
root@pve01:~# diff /root/restau-test/etc/pve/qemu-server/1002.conf /etc/pve/qemu-server/1002.conf && echo identique
root@pve01:~# proxmox-backup-client catalog shell --ns par1 host/pve01/<HORODATAGE> etc.pxar
pxar:/ > cd pve/firewall
pxar:/pve/firewall/ > ls
pxar:/pve/firewall/ > find *.fw --select
pxar:/pve/firewall/ > restore-selected /root/restau-test/fw
pxar:/pve/firewall/ > exit
root@pve01:~# rm -rf /root/restau-test
```

Note : `/etc/pve/qemu-server` est un lien vers `nodes/pve01/qemu-server` ; dans l'archive, cherche sous `pve/nodes/pve01/qemu-server/` si le lien n'est pas suivi.

*Procédure de reconstruction complète* (exemple, 14 étapes) :
1. Réinstaller Proxmox VE **même version majeure**, même nom d'hôte et même IP que l'original (le nom du nœud est dans `config.db`).
2. Configurer temporairement le réseau minimal (`vmbr0`) pour joindre l'Internet et `pbs01` (via une route directe sur le LAN vers `<IP-HP01-LAN>` si `gw01` n'existe plus : le tunnel n'existe pas encore !).
3. Installer `proxmox-backup-client` (présent par défaut) et récupérer la paperkey/clé si la sauvegarde est chiffrée (M00-E36).
4. Restaurer `wbconfig.pxar` et `etc.pxar` dans `/root/restau/`.
5. Comparer `pveversion.txt` avec la version installée ; aligner les dépôts (`etc/apt/`) et mettre à jour.
6. Restaurer `/etc/network/interfaces`, `interfaces.d/` (hors fichier `sdn`, régénéré), `/etc/hosts`, `/etc/resolv.conf` ; `ifreload -a`.
7. `systemctl stop pve-cluster pvedaemon pveproxy pvestatd`.
8. Copier `config.db` dans `/var/lib/pve-cluster/config.db` (droits `0600 root`), supprimer `config.db-wal` et `config.db-shm` éventuels.
9. `systemctl start pve-cluster` puis les autres services ; vérifier `/etc/pve` (stockages, utilisateurs, pare-feu, SDN, configurations des VMs).
10. Restaurer `/root/.ssh` et `/etc/ssh` (clés d'hôte : évite les alertes « host key changed » sur `adm01`).
11. Réimporter ou recréer les stockages locaux (ZFS : `zpool import` ; LVM-thin : `vgscan`/`vgchange -ay`) : les **données** des disques non système sont intactes si seul le disque système est mort.
12. `pvesh set /cluster/sdn` pour régénérer le SDN ; `pve-firewall compile`.
13. Démarrer `gw01`, `dns01`, `adm01` dans l'ordre ; si leurs disques sont perdus, les restaurer depuis `pbs-par2`.
14. Vérifier avec `verif-post-maj.sh` (M00-E34) et les checks du module ; consigner le temps passé (RTO réel).

**Explications**

`proxmox-backup-client` produit des archives `pxar` (format d'archive de Proxmox, découpé en blocs de taille variable et dédupliqué comme les images de VM). Une sauvegarde de type `host` n'est qu'un groupe de plus dans le datastore : elle bénéficie de la déduplication (les sauvegardes quotidiennes de `/etc` ne coûtent presque rien), de la vérification, du *prune* et du chiffrement. Le catalogue (`catalog.pcat1`) permet de parcourir l'archive sans la restaurer.

**Alternatives**
- `etckeeper` (historique Git de `/etc`) : excellent pour savoir *qui a changé quoi*, mais pas une sauvegarde hors site, et `/etc/pve` n'y est pas (FUSE).
- Archive `tar` + copie vers MinIO (module 05) : simple, mais pas de déduplication ni de vérification.
- Configuration entièrement en IaC (modules 04-05) : réduit ce qu'il faut sauvegarder, sans le supprimer (secrets, état de pmxcfs, clés).

**Pièges classiques**
- Archive sans `/etc/pve` (oubli de `--include-dev`) : la sauvegarde « réussit » mais est inutile.
- `cp config.db` à chaud.
- Secret recopié dans le script ou dans l'unité systemd (`Environment=PBS_PASSWORD=…` est lisible par tous via `systemctl show`).
- Timer sans `Persistent=true` : un `pve01` éteint la nuit ne sauvegarde jamais.
- Restaurer `config.db` d'une version majeure différente.
- Oublier que la reconstruction a besoin d'atteindre PBS **sans** `gw01` (route de secours).
- Sauvegarde en clair qui contient tous les secrets : traité en M00-E36.

**En production chez MédiSphère**
La sauvegarde de configuration est supervisée (métrique « âge de la dernière sauvegarde host »), la procédure de reconstruction est testée sur un Proxmox imbriqué (module 09) au moins une fois par an, et la configuration déclarative (stockages, SDN, utilisateurs, pare-feu) est de plus en plus portée par l'IaC, ce qui transforme la reconstruction en « réinstaller + appliquer ».

---

### M00-E31 — Temps synchronisé sur tout le lab

**Solution**

*1. État des lieux* : `timedatectl` (ligne `System clock synchronized` et `NTP service`), `chronyc tracking` là où chrony tourne. Typiquement : `pve01` et `pbs01` ont chrony (installé par défaut par Proxmox), les VMs Debian *genericcloud* peuvent avoir `systemd-timesyncd` ou chrony selon l'image.

*2. Serveur `gw01`* : fichier [`fichiers/M00-E31/gw01-serveur-lab.conf`](fichiers/M00-E31/gw01-serveur-lab.conf) dans `/etc/chrony/conf.d/`, puis :

```
root@gw01:~# systemctl restart chrony
root@gw01:~# chronyc accheck 10.10.10.10
208 Access allowed
root@gw01:~# chronyc accheck 192.0.2.1
209 Access denied
```

nftables : le jeu de règles de référence de fin de palier 2 (M00-E26) n'a aucune règle NTP, volontairement (on n'ouvre pas un port avant d'avoir le service). Ajoute dans la chaîne `input` les deux règles de [`fichiers/M00-E31/nftables-ntp.nft`](fichiers/M00-E31/nftables-ntp.nft) : `iifname $LAB_IFS udp dport 123 accept` (VLANs routés) et `iifname $WG_S2S ip saddr $NETS_PAR2 udp dport 123 accept` (PAR2 par le tunnel), puis `nft -c -f /etc/nftables.conf && systemctl reload nftables`. Le filtrage par interface (`iifname`) garantit que le WAN ne peut pas interroger `gw01`, même avec une adresse source privée usurpée ; le filtrage par source limite aux réseaux attendus. La seconde règle suffit pour `pbs01` parce que ses requêtes partent de 10.20.10.10 (étape 4).

*3. Clients `adm01`, `dns01`* : [`fichiers/M00-E31/configurer-client.sh`](fichiers/M00-E31/configurer-client.sh) :

```
admin@adm01:~$ sudo ./configurer-client.sh 10.10.10.1
admin@adm01:~$ ssh dns01 'sudo bash -s 10.10.20.1' < configurer-client.sh
```

Installer `chrony` retire `systemd-timesyncd` (les deux paquets sont en conflit). On commente les lignes `pool` de `chrony.conf` et on déclare la source dans `/etc/chrony/sources.d/lab.sources`.

*4. `pbs01`* : même script avec `10.10.10.1`. Diagnostic de l'adresse source :

```
root@pbs01:~# ip route get 10.10.10.1
10.10.10.1 dev wg0 src 10.20.10.10 uid 0
root@gw01:~# chronyc clients
Hostname                      NTP   Drop Int IntL Last     Cmd   Drop Int  Last
===============================================================================
10.20.10.10                     8      0   6   -    12       0      0   -     -
```

Les routes de `pbs01` vers PAR1 portent `src 10.20.10.10` depuis M00-E21 (`Table = off` et `PostUp` dans son `wg0.conf`) : ses requêtes arrivent avec son adresse de site, couverte par `allow 10.20.0.0/16` et par la règle nftables fondée sur `$NETS_PAR2`. Aucune exception pour l'interconnexion. *Si tu n'as pas fixé la source en E21*, la route posée par `wg-quick` n'a pas d'adresse source préférée : le noyau prend celle de `wg0` (10.255.0.2), que ni `allow` ni la règle nftables ne reconnaissent ; chrony ignore alors silencieusement ces requêtes (pas d'erreur côté client, juste une source jamais joignable : `chronyc sources` montre `^?` et `Reach 0`). La bonne correction est de reprendre `wg0.conf` sur `pbs01` comme en E21, plutôt que d'autoriser 10.255.0.0/30 partout où PAR2 est attendu (DNS, NTP, webhooks…). Viser `10.255.0.1` (l'extrémité du tunnel) marcherait aussi, mais le PLAN préfère une adresse de service stable (10.10.10.1).

*5. `pve01`* : choix recommandé, **rester sur Internet** (sources Debian/Proxmox par défaut). Justification : `gw01` est une VM hébergée par `pve01` ; au démarrage de l'hyperviseur, elle n'existe pas encore, et la synchronisation initiale de l'hôte (qui horodate journaux, tâches et sauvegardes) dépendrait d'un invité ; une panne de `gw01` priverait aussi l'hyperviseur de temps. Le choix inverse (sources `gw01` + Internet en secours) se défend pour avoir une seule référence de temps sur tout le site ; dans ce cas, garder au moins une source Internet directe. Ce qui compte : les deux références (Internet et `gw01`) sont synchronisées sur les mêmes serveurs publics, l'écart reste de l'ordre de la milliseconde.

*6. Lecture des sorties.*

```
admin@adm01:~$ chronyc -n sources -v
  .-- Source mode  '^' = server, '=' = peer, '#' = local clock.
 / .- Source state '*' = current best, '+' = combined, '-' = not combined,
| /             'x' = may be in error, '~' = too variable, '?' = unusable.
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
^* 10.10.10.1                    3   6   377    34    +18us[  +25us] +/-   12ms
admin@adm01:~$ chronyc tracking
Reference ID    : 0A0A0A01 (10.10.10.1)
Stratum         : 4
System time     : 0.000004211 seconds fast of NTP time
Leap status     : Normal
```

`^*` = source sélectionnée ; `Reach 377` (octal) = les 8 dernières requêtes ont abouti ; le stratum du client vaut celui de `gw01` + 1 ; `Leap status : Normal` = synchronisé (sinon `Not synchronised`) ; `Reference ID` en hexadécimal = l'adresse IP de la source.

**Explications**

chrony est à la fois client et serveur ; il ne répond aux requêtes NTP que des réseaux listés par `allow` (par défaut : aucun). La directive `local stratum 10` permet à `gw01` de continuer à servir s'il perd ses sources Internet : le lab dérive alors « ensemble », ce qui préserve la cohérence relative (Kerberos, certificats, etcd tolèrent un décalage absolu tant que les machines sont d'accord entre elles). `makestep` (présent dans la configuration Debian) autorise un saut d'horloge au démarrage, ce qui compte pour une VM restaurée ou longtemps éteinte.

**Alternatives**
- `systemd-timesyncd` en client : suffisant pour un client simple (SNTP), mais pas de serveur, pas de statistiques fines, pas de NTS ; chrony est le standard des distributions serveur.
- Deux serveurs de temps (`gw01` + `dns01` ou `pbs01`) : évite le point unique de défaillance ; avec trois sources, un client peut écarter une source fausse (*falseticker*).
- NTS vers des sources Internet qui le supportent.

**Pièges classiques**
- Oublier que l'adresse source d'un hôte multi-domicilié dépend de la route : sans les routes `src` de M00-E21, `pbs01` émettrait depuis 10.255.0.2.
- Ouvrir UDP 123 sur toutes les interfaces, WAN compris (serveur NTP ouvert : amplification, fuite d'information).
- Garder les lignes `pool` sur les clients : ils contournent `gw01` via le NAT, le critère « tout le lab sur `gw01` » n'est pas rempli.
- Laisser tourner `systemd-timesyncd` et chrony ensemble (deux démons qui corrigent la même horloge).
- Modifier `allow` puis faire `chronyc reload sources` (ne recharge que les sources) au lieu de redémarrer.

**En production chez MédiSphère**
Au moins trois sources de temps internes (passerelles redondantes, module 07), elles-mêmes alimentées par des sources publiques diverses et, idéalement, une source GPS/PTP en datacenter ; supervision de l'offset (`chrony_exporter`, module 21) avec alerte au-delà de 100 ms ; NTP déclaré dans NetBox et distribué par DHCP (Kea, module 06).

---

### M00-E32 — Optimiser la configuration des VMs du socle

**Solution** (une solution de référence ; d'autres choix sont valables s'ils sont justifiés)

Script : [`fichiers/M00-E32/optimiser-socle.sh`](fichiers/M00-E32/optimiser-socle.sh), à lancer VM par VM, suivi d'un arrêt/démarrage complet. Dans chaque invité, au préalable :

```
admin@adm01:~$ for h in gw01 dns01 adm01; do ssh $h 'sudo apt-get install -y qemu-guest-agent && sudo systemctl enable --now qemu-guest-agent'; done
```

(Sur une image *genericcloud* issue du template 9000, l'agent est déjà là ; sur `gw01` construit à la main, souvent pas.)

Configuration obtenue pour `gw01` (extrait de `qm config 1000`) :

```
agent: enabled=1,fstrim_cloned_disks=1
balloon: 0
cores: 1
cpu: x86-64-v2-AES
memory: 2048
onboot: 1
scsi0: local-nvme:vm-1000-disk-0,discard=on,iothread=1,size=16G,ssd=1
scsihw: virtio-scsi-single
startup: order=1,up=30,down=60
```

| Réglage | Choix | Justification |
|---|---|---|
| Type de CPU | `x86-64-v2-AES` | `hp01` (Xeon E3-1220L v2, Ivy Bridge) a SSE4.2, POPCNT et AES-NI mais **pas** AVX2 : `x86-64-v3` et `host` empêcheraient de démarrer une VM restaurée sur PAR2 (F5) ou de migrer vers un nœud plus ancien. `x86-64-v2-AES` garde AES-NI (WireGuard n'en a pas besoin, mais TLS et SSH oui). `kvm64`/`qemu64` privent l'invité d'instructions utiles sans gain de compatibilité. |
| vCPU | `gw01` 1-2, `dns01` 1, `adm01` 2 | Charge faible. Plus de vCPU que nécessaire augmente la latence d'ordonnancement (le vCPU attend un thread libre) sans gain. |
| Ballooning | désactivé (`balloon: 0`) sur `gw01` et `dns01`, actif sur `adm01` (min. 1 Go) | Un routeur ou un DNS ne doit pas voir sa mémoire reprise au moment où l'hôte est sous pression (c'est justement là qu'on a besoin d'eux). Sur 1-2 Go, le gain est nul. `adm01` a des pics (Ansible, Terraform) et peut rendre de la mémoire. |
| Contrôleur | `virtio-scsi-single` | Un contrôleur par disque : condition pour que `iothread=1` donne un thread d'I/O dédié par disque. Supporte `discard` et l'émulation SSD. |
| `iothread=1` | oui | Sort le traitement des I/O du thread principal de QEMU : moins de latence et pas de blocage de la VM pendant les I/O lourdes. |
| `discard=on` | oui | Propage le TRIM de l'invité jusqu'au stockage thin (LVM-thin/ZFS) : l'espace libéré dans l'invité est rendu à l'hôte. Indispensable avec du *thin provisioning*. |
| `ssd=1` | oui | L'invité voit un disque non rotatif (`/sys/block/sda/queue/rotational` = 0) : ordonnanceur adapté, `fstrim.timer` utile. Sans effet sur la performance réelle de l'hôte. |
| Cache | défaut (`none`) | `none` = O_DIRECT : pas de double cache (le cache de pages de l'hôte ou l'ARC ZFS suffit), écritures sûres (les *flush* de l'invité sont respectés). `writeback` gagne un peu en écriture au prix d'un risque à la coupure ; `unsafe` ignore les *flush* : interdit hors données jetables. |
| `aio` | défaut (`io_uring`) | Le défaut moderne ; `native` peut être préférable sur certains stockages en mode bloc, sans intérêt ici. |
| Agent QEMU | `enabled=1,fstrim_cloned_disks=1` | `vzdump` en mode *snapshot* appelle `guest-fsfreeze-freeze`/`thaw` : sauvegarde cohérente au niveau du système de fichiers. Arrêt propre par l'agent (plus fiable qu'ACPI), IP visibles dans l'interface, TRIM automatique après clonage ou migration. |
| Démarrage | `onboot=1`, `order=1/2/3`, `up=30/15/0`, `down=60` | `gw01` d'abord (routage, NTP, relais DHCP), 30 s pour que ses interfaces et nftables soient prêts ; puis `dns01` ; puis `adm01`. À l'arrêt, Proxmox arrête dans l'ordre inverse, en attendant au plus `down` secondes par VM avant de forcer. |
| Template 9000 | `scsihw virtio-scsi-single`, `agent enabled=1,fstrim_cloned_disks=1`, `cpu x86-64-v2-AES`, `discard=on,ssd=1,iothread=1` sur le disque | Les clones héritent de la configuration : tout réglage fait sur le template évite N corrections. L'ordre de démarrage, lui, ne s'hérite pas (propre à chaque service). |
| Laissé par défaut | `machine` (q35/i440fx selon l'existant), BIOS, NUMA, affinité CPU, `hotplug` | Pas de besoin identifié ; changer `machine` d'une VM existante peut renommer ses interfaces réseau dans l'invité (risque sur `gw01` : `ens18`/`ens19`). NUMA/affinité n'ont pas de sens sur un mono-socket. |

Appliquer les modifications en attente :

```
root@pve01:~# qm pending 1000
root@pve01:~# qm shutdown 1000 && qm start 1000
root@pve01:~# qm agent 1000 ping && qm agent 1000 network-get-interfaces | head
```

Preuve du TRIM :

```
root@pve01:~# lvs -o lv_name,data_percent <VG>/vm-1001-disk-0     # ou : zfs list -o name,used,refer <POOL>/vm-1001-disk-0
admin@adm01:~$ dd if=/dev/urandom of=~/gros bs=1M count=2048 && sync && rm ~/gros && sudo fstrim -av
root@pve01:~# lvs -o lv_name,data_percent <VG>/vm-1001-disk-0     # l'occupation redescend
```

**Explications**

La « bonne » configuration d'une VM QEMU/KVM tient à trois idées : **virtio partout** (pilotes paravirtualisés, pas d'émulation de matériel réel), **faire traverser les informations utiles entre couches** (TRIM, gel des systèmes de fichiers, arrêt propre : c'est le rôle de `discard` et de l'agent) et **ne pas sacrifier la portabilité** (type de CPU). `qm config` montre la configuration *avec* les modifications en attente ; `qm config --current` et `qm pending` montrent ce qui est réellement en service : un changement de contrôleur ou de CPU n'est appliqué qu'au démarrage d'un nouveau processus QEMU (arrêt puis démarrage, pas un redémarrage de l'invité qui garde le même processus).

**Alternatives**
- `cpu: host` sur un mono-nœud définitif : meilleures performances (AVX2, AVX-512), au prix de la portabilité ; acceptable pour des VMs jetables de bench, pas pour le socle.
- Modèle CPU personnalisé (`/etc/pve/virtual-guest/cpu-models.conf`) pour exposer précisément les drapeaux communs à `pve01` et `hp01`.
- `virtio-blk` (`virtio0`) au lieu de SCSI : un peu plus léger, supporte `discard` et `iothread` dans les versions récentes ; SCSI reste le choix par défaut de Proxmox et le plus souple.

**Pièges classiques**
- Activer `agent` dans Proxmox sans installer le paquet dans l'invité : `vzdump` attend l'agent puis continue sans *fs-freeze* (avertissement dans le journal de la tâche), l'arrêt passe en timeout.
- Changer `scsihw` sans arrêt/démarrage : la modification reste en attente indéfiniment.
- `discard=on` sans `fstrim` dans l'invité (vérifie `systemctl status fstrim.timer`).
- `x86-64-v3` choisi « parce que plus récent » : la VM ne démarre pas sur `hp01`. Note : Rocky Linux 10 exige `x86-64-v3` : il ne tournera pas sur `hp01` quelle que soit la configuration — à garder en tête pour F5.
- Ordre de démarrage sans délai `up` : `dns01` démarre pendant que `gw01` charge encore ses règles.
- Ballooning sur une VM sans le pilote ou avec un minimum trop bas : l'invité swappe, voire déclenche son OOM killer.

**En production chez MédiSphère**
Ces réglages sont portés par le template (module 03, Packer) et par le module Terraform de création de VM (module 05) : personne ne règle une VM à la main. Le type de CPU est un standard de cluster documenté (le plus petit dénominateur commun des nœuds), revu à chaque renouvellement de matériel.

---

### M00-E33 — ADR : routeur Linux et stratégie de sauvegarde

**Solution**

Deux ADR exemplaires :
- [`fichiers/M00-E33/ADR-0001-routeur-linux-nftables.md`](fichiers/M00-E33/ADR-0001-routeur-linux-nftables.md)
- [`fichiers/M00-E33/ADR-0002-strategie-sauvegarde-par1-par2.md`](fichiers/M00-E33/ADR-0002-strategie-sauvegarde-par1-par2.md)

À ranger dans `~/medisphere/docs/socle/adr/` (dépôt de M00-E25), un commit par ADR. Grille d'auto-évaluation : [`fichiers/M00-E33/grille-evaluation.md`](fichiers/M00-E33/grille-evaluation.md). Note chaque ADR, puis compare-le à l'exemple **après** l'avoir noté.

**Explications**

Un ADR (*Architecture Decision Record*) enregistre une décision **au moment où elle est prise**, avec ses options écartées et ses conséquences. Sa valeur est dans ce qu'il permet d'éviter : refaire le débat, ou défaire une décision sans connaître la contrainte qui l'a motivée. Le format MADR impose les facteurs de décision avant les options : on choisit en fonction de critères explicites, pas l'inverse. Un ADR ne se modifie pas après acceptation : on en écrit un nouveau qui le remplace (statut « remplacé par »), ce qui garde l'historique du raisonnement.

Ce qui distingue un bon ADR-0002 :
- RPO et RTO chiffrés **et** la façon de les mesurer (M00-E37 mesure le RTO) ;
- distinction claire entre sauvegarde (historique, isolée) et réplication (copie du présent, y compris des erreurs) ;
- gestion de la clé de chiffrement traitée comme un risque de premier rang ;
- reconnaissance honnête que la règle 3-2-1 n'est pas satisfaite (une seule copie hors site, un seul disque, même bâtiment dans le lab) et action pour y remédier.

**Alternatives**
- Format Nygard (Contexte / Décision / Conséquences) : plus court, adapté aux petites décisions.
- RFC/Design doc : pour une décision encore ouverte, qui appelle des commentaires, avant l'ADR.

**Pièges classiques**
- Écrire l'ADR comme un plaidoyer (options écartées caricaturées).
- Mettre des commandes et des procédures dans l'ADR : elles vont dans les runbooks.
- Oublier les décisions « temporaires » (dnsmasq, routeur unique) : ce sont celles qu'on oublie de réviser.

**En production chez MédiSphère**
Les ADR vivent dans le dépôt Git de la plateforme (`docs/socle/adr/` du dépôt `medisphere`, créé en M00-E25 et poussé sur GitLab au module 01), passent en MR avec au moins un relecteur senior, sont numérotés et indexés ; les ADR qui touchent à la sécurité ou à la conformité sont relus par la RSSI. Ils servent de pièces au dossier HDS (justification des choix de sauvegarde et de chiffrement).

---

### M00-E34 — Mises à jour maîtrisées de `pve01` et `pbs01`

**Solution** — runbook de référence (CHG-134)

*A. Préparation (J-7 à J-1)*

```
root@pve01:~# apt update
root@pve01:~# apt list --upgradable
root@pve01:~# pveversion -v > /root/pveversion-avant-$(date +%F).txt
root@pve01:~# proxmox-boot-tool status
root@pve01:~# proxmox-boot-tool kernel list
root@pve01:~# apt changelog pve-manager | head -40
root@pve01:~# apt changelog qemu-server | head -40
```

1. Lire l'annonce de version (forum Proxmox, section *Announcements*) et les *known issues* de la feuille de route.
2. Classer : **noyau** (`proxmox-kernel-*` : redémarrage nécessaire, risque matériel/pilotes) ; **QEMU** (`pve-qemu-kvm` : les VMs en cours gardent l'ancien binaire jusqu'à leur arrêt/démarrage ; une migration ou un arrêt/démarrage est nécessaire pour en profiter) ; **pile PVE** (`pve-manager`, `qemu-server`, `pve-cluster`, `pve-firewall` : services redémarrés par les scripts du paquet) ; **outils** (faible risque).
3. Fenêtre : hors sauvegardes (`pvesh get /cluster/backup`) et hors tâches PBS (GC, prune, verify). Prévenir les utilisateurs des VMs personnelles.

*B. Plan de retour arrière*

| Risque | Retour arrière |
|---|---|
| Nouveau noyau qui ne démarre pas / pilote réseau ou stockage défaillant | Au menu de démarrage (console), choisir l'ancien noyau ; puis `proxmox-boot-tool kernel pin <ANCIEN>` jusqu'au correctif. Les anciens noyaux restent installés (ne pas les purger le jour même). |
| Régression QEMU sur une VM | Revenir à l'ancien paquet (`apt install pve-qemu-kvm=<VERSION>` si encore dans le dépôt ou le cache `/var/cache/apt/archives`), puis arrêt/démarrage de la VM. |
| Régression d'un service PVE | Rétrograder le paquet concerné (même méthode) ; configuration intacte (sauvegarde M00-E30 fraîche en dernier recours). |
| Système de l'hôte inutilisable | Racine sur ZFS : `zfs snapshot rpool/ROOT/pve-1@avant-maj-<DATE>` avant la mise à jour, et retour par `zfs rollback` depuis un environnement de secours (ou cloner le snapshot comme nouvel environnement de démarrage). Racine sur LVM/ext4 : pas de retour instantané, reconstruction M00-E30. |
| Mise à jour des invités Debian pendant la fenêtre | Snapshots `avant-maj-<DATE>` de `gw01` et `dns01` : retour en quelques secondes (`qm rollback`). |

Les snapshots de VMs protègent **les invités**, pas l'hyperviseur : ils ne servent à rien si c'est le noyau ou QEMU de `pve01` qui pose problème. On les prend quand on met aussi à jour les VMs (même fenêtre) ou parce qu'un redémarrage brutal pourrait les abîmer. On ne les garde pas : un snapshot sur LVM-thin ou ZFS fige les blocs et fait grossir l'occupation, ralentit certaines opérations, et un snapshot oublié devient un piège (restauration par erreur d'un état ancien, sauvegardes `vzdump` qui ne l'incluent pas).

*C. Jour J*

```
root@pve01:~# systemctl start wb-backup-config.service && journalctl -u wb-backup-config.service -n 5
root@pve01:~# pvesh get /nodes/$(hostname)/tasks --source active     # aucune tâche en cours
root@pve01:~# for v in 1000 1002; do qm snapshot $v avant-maj-$(date +%Y%m%d) --description "CHG-134"; done
root@pve01:~# zfs snapshot rpool/ROOT/pve-1@avant-maj-$(date +%Y%m%d)   # seulement si racine ZFS
root@pve01:~# pveupgrade          # ou : apt full-upgrade
```

`apt upgrade` est proscrit sur Proxmox : il refuse d'installer de nouveaux paquets et de retirer des paquets, alors que les mises à jour Proxmox en ont souvent besoin (nouveau paquet noyau, dépendances renommées). Résultat : système partiellement à jour, potentiellement incohérent. `pveupgrade` est un simple enrobage d'`apt-get dist-upgrade` qui affiche ensuite si un redémarrage est nécessaire. Aux questions sur les fichiers de configuration modifiés, garde ta version (`N`) puis examine le `.dpkg-dist` à tête reposée.

Redémarrage planifié : `shutdown -r 23:30 "CHG-134 maintenance pve01"` (annulable par `shutdown -c`), ou immédiat si tu es dans la fenêtre.

*D. Vérifications post-redémarrage* : script [`fichiers/M00-E34/verif-post-maj.sh`](fichiers/M00-E34/verif-post-maj.sh) — noyau, paquets, services, stockages, pare-feu, VNets, socle démarré, `dns01` et `pbs01` joignables, erreurs du journal de démarrage. Puis `lab/bin/check 00 31` et `lab/bin/check 00 28` depuis `adm01`.

*E. Noyaux*

```
root@pve01:~# proxmox-boot-tool kernel list
root@pve01:~# proxmox-boot-tool kernel pin <ANCIEN-NOYAU> --next-boot
root@pve01:~# reboot
root@pve01:~# uname -r             # ancien noyau
root@pve01:~# reboot               # retour automatique au noyau par défaut
root@pve01:~# proxmox-boot-tool kernel unpin
```

`pin` sans `--next-boot` est **permanent** : le noyau choisi reste celui de démarrage jusqu'à `unpin`, même quand de nouveaux noyaux arrivent (piège : on « oublie » une épinglette et on tourne des mois sur un noyau sans correctifs de sécurité). `--next-boot` ne vaut que pour le prochain démarrage : idéal pour un test ou un retour arrière ponctuel.

*F. PBS*

```
root@pbs01:~# proxmox-backup-manager datastore update ds-lab --maintenance-mode type=read-only
root@pbs01:~# apt update && apt list --upgradable
root@pbs01:~# apt full-upgrade
root@pbs01:~# reboot
root@pbs01:~# proxmox-backup-manager datastore update ds-lab --delete maintenance-mode
root@pbs01:~# proxmox-backup-manager versions
```

Le mode `read-only` laisse lire (restaurations possibles) mais refuse les écritures, ce qui évite qu'une sauvegarde soit coupée au milieu ; `offline` interdit tout accès (utile pour une opération sur le disque). Vérifie ensuite depuis `pve01` : `pvesm status` (`pbs-par2` actif), une sauvegarde d'une VM sandbox et la restauration d'un fichier (M00-E23). Attention : pendant le redémarrage de `pbs01`, le tunnel `wg0` tombe ; il doit remonter seul (`wg-quick@wg0` activé).

*G. Clôture* : `qm delsnapshot 1000 avant-maj-<DATE>` (idem 1002), `zfs destroy rpool/ROOT/pve-1@avant-maj-<DATE>` après quelques jours sans régression, ticket CHG mis à jour avec les versions avant/après.

*H. Passage 8 → 9 (si `pve01` est en 8.x)*

```
root@pve01:~# pve8to9 --full
```

Lis chaque `WARN` et `FAIL` : dépôts, paquets obsolètes, configuration de démarrage, stockages, éléments retirés en 9. Estime l'effort (souvent : passer les dépôts au format deb822 `.sources`, mettre à jour vers la dernière 8.4, traiter les avertissements) et ouvre un ticket CHG dédié. Ne mélange pas une montée de version majeure avec une maintenance de routine.

**Explications**

Proxmox VE est une Debian avec ses propres dépôts : une mise à jour combine des paquets Debian et des paquets Proxmox, dont un noyau Proxmox (basé sur le noyau Ubuntu). `proxmox-boot-tool` gère les ESP (partitions EFI) synchronisées et la liste des noyaux proposés au démarrage, que l'hôte démarre avec GRUB ou systemd-boot (racine ZFS en UEFI). Les VMs en cours ne sont pas touchées par la mise à jour de QEMU tant qu'elles ne sont pas redémarrées « à froid » : c'est pourquoi, en cluster, on vide un nœud par migration avant de le redémarrer (module 09).

**Alternatives**
- Mises à jour automatiques non surveillées (`unattended-upgrades`) : acceptables pour les correctifs de sécurité des **VMs** Debian ; déconseillées sur l'hyperviseur.
- Tester d'abord sur un Proxmox imbriqué ou un nœud de préproduction alimenté par le dépôt `pve-test`.

**Pièges classiques**
- `apt upgrade` au lieu de `full-upgrade`.
- Dépôt `enterprise` actif sans abonnement : `apt update` échoue en 401 et on croit être à jour.
- Épinglage permanent oublié.
- Redémarrer `pve01` sans prévenir (VMs personnelles), ou pendant une sauvegarde.
- Mettre à jour `pbs01` pendant une vérification ou un GC.
- Garder les snapshots `avant-maj-*` des semaines.

**En production chez MédiSphère**
Cluster de plusieurs nœuds : mise à jour nœud par nœud après migration des VMs (zéro interruption de service), préproduction mise à jour une semaine avant, fenêtre et communication formalisées (CAB), versions avant/après tracées dans le ticket, et supervision du « noyau en service ≠ noyau installé » (alerte de redémarrage en attente).

---

### M00-E35 — Questions de production : hyperviseur

**1. Quorum et `/etc/pve`.** Dans un cluster, pmxcfs n'autorise les écritures dans `/etc/pve` que si le nœud fait partie de la partition majoritaire (quorum corosync). Avec deux nœuds (2 votes, quorum = 2), la perte d'un nœud fait perdre le quorum au survivant : `/etc/pve` passe en lecture seule, on ne peut plus démarrer ni modifier de VM, ni changer de configuration (les VMs déjà en marche continuent). `pvecm expected 1` abaisse temporairement le nombre de votes attendus pour retrouver l'écriture : c'est un geste d'urgence parce qu'il supprime la protection contre le *split-brain* — si l'autre nœud est vivant mais isolé et fait de même, les deux écrivent des configurations divergentes, voire démarrent la même VM sur un stockage partagé. La bonne solution est un troisième vote : un **QDevice** (`corosync-qnetd`) sur une machine tierce, ici `hp01`/`pbs01` à PAR2 (module 09). En mono-nœud aujourd'hui, `pve01` a le quorum seul : la question ne se pose pas encore.

**2. ARC ZFS — réponse b.** Jusqu'à OpenZFS 2.2 (PVE 8.x), le plafond par défaut de l'ARC sous Linux est 50 % de la RAM. Depuis OpenZFS 2.3 (livré avec PVE 9), il devient `max(RAM − 1 Gio, 5/8 × RAM)`, soit environ 127 Go sur `pve01` : sans réglage explicite, l'ARC peut occuper presque toute la mémoire de l'hyperviseur (⚠️ à vérifier sur ta version : `cat /sys/module/zfs/parameters/zfs_arc_max` vaut 0 si le défaut s'applique, et `grep c_max /proc/spl/kstat/zfs/arcstats` donne la valeur effective). Depuis PVE 8.1, l'installateur, lorsqu'il installe la racine en ZFS, fixe `zfs_arc_max` à 10 % de la RAM, plafonné à 16 Go, dans `/etc/modprobe.d/zfs.conf`. a) et d) sont des légendes (la règle « 1 Go par To » est une recommandation ancienne pour la déduplication ZFS, pas un réglage automatique) ; c) est faux, l'ARC a toujours un plafond (même s'il est proche de la RAM totale depuis OpenZFS 2.3 : c'est précisément pourquoi on le fixe à la main). Vérification : `arc_summary | head -30`, `cat /sys/module/zfs/parameters/zfs_arc_max` (0 = défaut), `grep -E '^(size|c_max) ' /proc/spl/kstat/zfs/arcstats`. L'ARC est un cache **géré par ZFS**, pas par le cache de pages du noyau : il ne rend sa mémoire que lorsque ZFS reçoit une pression (via les *shrinkers*), avec un temps de réaction ; une allocation brutale de mémoire (démarrage d'une grosse VM) peut donc échouer ou déclencher l'OOM killer alors que la mémoire « disponible » semblait suffire. Sur un hyperviseur, on fixe `zfs_arc_max` (ex. 8-16 Go sur 128 Go) et on le compte dans le budget.

**3. Lancer openstack en plus de k8s.** 24 (socle) + 36 (k8s) + 48 (openstack) = 108 Go, plus l'ARC (ex. 16 Go) et l'hôte (~4 Go) = 128 Go : on est à 100 % sans aucune marge. Le ballooning ne reprend de la mémoire qu'aux VMs qui en ont de libre (or Kubernetes et OpenStack remplissent leur mémoire de caches et de pods), et ne se déclenche qu'au-dessus de 80 % d'occupation de l'hôte. KSM peut faire gagner quelques Go entre VMs identiques (mêmes images Debian), sans garantie et avec un coût CPU. Le risque : l'OOM killer de l'**hôte** tue le processus qui a le plus gros score, c'est-à-dire un processus `kvm` d'une grosse VM — potentiellement un nœud etcd ou un contrôleur OpenStack, avec corruption possible. ZFS réduira l'ARC trop tard. Réponse professionnelle : non, la règle du PLAN (un seul profil lourd) existe précisément pour ça ; si on doit le faire, réduire explicitement la taille des VMs, et accepter la dégradation en connaissance de cause.

**4. KSM.** *Kernel Samepage Merging* : un thread noyau (`ksmd`) parcourt la mémoire des processus qui l'ont autorisé (QEMU le fait), repère les pages identiques et les fusionne en une seule page en copie-sur-écriture. Sur Proxmox, `ksmtuned` active KSM quand l'occupation mémoire dépasse un seuil (par défaut 80 %, réglable dans `/etc/ksmtuned.conf`, `KSM_THRES_COEF`). Gain important : beaucoup de VMs identiques (même OS, mêmes applications), mémoire peu écrite (VMs inactives), petites pages. Risque : la fusion crée un canal auxiliaire — une VM peut déduire qu'une autre VM possède une page donnée en mesurant le temps d'une écriture (copie-sur-écriture plus lente), ce qui a permis des attaques de déduction de contenu et facilite certaines attaques type Rowhammer (Flip Feng Shui). Pour un hébergeur de données de santé avec plusieurs clients ou plusieurs niveaux de sensibilité sur le même hôte, on désactive KSM (ou on sépare les clients par hôte). Dans le lab, un seul « client » : acceptable.

**5. Ballooning — réponse b.** `memory` est le maximum, `balloon` le minimum garanti. La VM démarre avec 8 Go ; quand l'occupation de l'hôte dépasse le seuil (80 %), `pvestatd` gonfle le ballon (pilote `virtio-balloon` dans l'invité) pour reprendre de la mémoire, sans descendre sous 2 Go. a) est faux (seul `balloon: 0` ou `balloon = memory` garantit), c) décrit un comportement inverse (pas de démarrage au minimum), d) faux : le ballooning passe par le pilote `virtio-balloon` (intégré au noyau Linux), pas par l'agent QEMU. Pour une base de données, la mémoire reprise est celle de son cache (`shared_buffers`, cache de pages) : performances qui s'effondrent au moment de la pression, voire swap. Pour un routeur, on veut une latence stable et aucune dépendance à l'état de l'hôte. On fixe donc la mémoire.

**6. Thin provisioning.** Côté invité : le **TRIM/discard** (`fstrim` ou montage `discard`) signale les blocs libérés ; il faut `discard=on` sur le disque virtuel pour qu'il traverse QEMU. Côté hôte : LVM-thin libère les blocs du pool, ZFS libère les blocs du zvol (et la compression ZFS rend les blocs à zéro quasi gratuits). À 100 % : pour LVM-thin, le pool passe en erreur ou en lecture seule selon la politique, les écritures des VMs échouent, les systèmes de fichiers invités passent en lecture seule ou se corrompent, et la réparation du pool peut être longue ; pour ZFS, les écritures échouent (ENOSPC) et le pool devient difficile à manipuler (même supprimer demande un peu de place) — d'où l'habitude de garder une réservation (`refreservation` sur un dataset vide) et de rester sous 80 %. Surveillance : `lvs -o+data_percent,metadata_percent` (les métadonnées aussi peuvent saturer), `zpool list` (CAP), `pvesm status`, alertes à 80/90 % (module 21).

**7. Virtualisation imbriquée.** Le CPU coûte peu tant que l'invité de niveau 1 utilise VT-x/EPT (le matériel gère deux niveaux de traduction, quelques % à 10-20 % selon la charge). Ce qui coûte cher : les **sorties de VM** (VM exits) du niveau 2, qui remontent au niveau 0 puis redescendent (I/O, interruptions, timers) ; les I/O et le réseau traversent deux piles virtio ; la latence augmente nettement (corosync et etcd y sont sensibles). Aggravants : surcharge en vCPU, ballooning, stockage lent (HDD), absence de virtio au niveau 2, beaucoup de petites I/O synchrones (Ceph, etcd). Il faut exposer VT-x à l'invité : `cpu: host` (ou un modèle avec le drapeau `+vmx` pour Intel), et `kvm_intel` chargé avec `nested=1` sur l'hôte (M00-E06). Note : `cpu: host` est acceptable pour les nœuds imbriqués de lab (VMs jetables, non migrées), contrairement au socle.

**8. Type de CPU — réponse b.** a) `host` : expose tous les drapeaux du Xeon E-2378G (AVX2, AVX-512…) ; la migration vers l'Ivy Bridge échoue ou, pire, l'invité utilise des instructions absentes et plante. b) `x86-64-v2-AES` : niveau v2 (SSE4.2, POPCNT, SSSE3, CX16) + AES-NI, tous présents sur Ivy Bridge et Rocket Lake : migrable, et garde l'essentiel des performances. c) `x86-64-v3` exige AVX2/FMA/BMI1-2, absents d'Ivy Bridge : la VM ne démarre pas sur l'ancien nœud. d) `kvm64` : migrable mais prive l'invité de SSE4.2/AES-NI (performances crypto et compression dégradées) et certains systèmes récents refusent de démarrer (RHEL 9 exige v2, RHEL 10 et Rocky 10 exigent v3).

**9. `cache=unsafe`.** Non. `unsafe` ignore les demandes de vidage (*flush*/FUA) de l'invité : le système de fichiers invité croit ses données sur disque alors qu'elles sont en mémoire de l'hôte. Coupure de courant, plantage de l'hôte ou de QEMU = corruption silencieuse (journal ext4/XFS incohérent, base PostgreSQL corrompue). Gain réel faible avec `none` + NVMe. Cas acceptable : une VM entièrement jetable dont on accepte de perdre le disque, par exemple pendant l'installation initiale d'une image Packer (module 03), ou des nœuds de lab éphémères recréés par IaC — et encore, à documenter.

**10. Dimensionnement vCPU.** Pour des VMs peu chargées (socle, outils), un ratio de 3 à 5 vCPU par thread physique est courant ; ici 16 threads → 48 à 80 vCPU alloués au total. Pour des charges sensibles à la latence (etcd, Ceph OSD/MON, corosync, bases de données), on vise plutôt ≤ 1,5:1 sur la part de l'hôte qu'elles utilisent, et peu de vCPU par VM (une VM à 8 vCPU doit trouver 8 threads libres simultanément pour être ordonnancée efficacement). Indicateurs : dans l'invité, `%st` (*steal*) de `top`/`vmstat` (temps où le vCPU voulait tourner mais l'hôte ne l'a pas ordonnancé) ; sur l'hôte, la charge (`load average` / nombre de threads), `pressure` (`/proc/pressure/cpu`, PSI), et par VM le temps d'attente d'ordonnancement (`/proc/<pid>/schedstat`). Un *steal* durable > 5-10 % signale une surcharge.

**11. `gw01` SPOF.** Panne de `gw01` : plus de routage inter-VLAN, plus d'Internet pour le lab, plus de DNS récursif pour les VMs (dns01 ne joint plus ses amont), plus de NTP servi, plus de relais DHCP (SANDBOX), plus de VPN `wg1` (l'apprenant ne joint plus le lab depuis l'extérieur), plus de tunnel `wg0` (sauvegardes et restaurations PBS impossibles). Mise à jour : chaque redémarrage de `gw01` est une coupure totale du lab (quelques dizaines de secondes). Erreur de règle nftables : coupure générale, potentiellement sans accès pour corriger (d'où l'accès console Proxmox). Les adresses `.2` et `.3` de chaque VLAN sont réservées pour un second routeur `gw02` et une **VIP VRRP** : le module 07 déploie keepalived (VRRP) pour que `.1` devienne une adresse flottante portée par l'un ou l'autre routeur, avec synchronisation des états de connexion (`conntrackd`) si nécessaire, et la même chose pour les tunnels.

**12. `pve01` redémarre, `gw01` ne démarre pas.** Directement : routage, NAT, NTP du lab, relais DHCP, VPN `wg1` et tunnel `wg0`. Indirectement : `dns01` répond pour la zone interne aux VMs de **son** VLAN seulement (les autres ne peuvent plus le joindre), la récursion Internet échoue ; `adm01` est isolée (plus de SSH vers `pve01` ni vers les autres VLANs) ; les sauvegardes vers `pbs-par2` échouent (le stockage apparaît inactif), les notifications partent quand même si `pve01` a un accès direct à Internet ; les checks du workbook ne fonctionnent plus. `pve01` reste administrable parce qu'il est sur `vmbr0` (LAN maison) avec sa propre IP, sa propre passerelle (la box) et ses propres sources NTP (choix de M00-E31) : interface web et SSH depuis le LAN maison, console de `gw01` par noVNC/`qm terminal 1000` pour réparer. C'est un argument fort pour ne jamais faire dépendre l'administration de l'hyperviseur d'une VM qu'il héberge.

**13. Fuite du jeton.** Avec séparation des privilèges, le jeton n'a que les droits qui lui ont été donnés explicitement (`WBAutomation` sur `/pool/lab`, stockages, SDN) : l'attaquant peut créer, modifier, démarrer, arrêter, **supprimer** les VMs du pool `lab`, consommer du stockage, lire les configurations (dont les données cloud-init : mots de passe, clés publiques, éventuellement secrets injectés), mais pas toucher aux VMs personnelles, aux utilisateurs ni à la configuration de l'hôte. Port 8006 non exposé sur Internet : il lui faut aussi un accès réseau (d'où l'importance d'E27). Actions dans l'ordre : (1) **révoquer** le jeton (`pveum user token remove wb-automation@pve lab`) — avant même d'enquêter ; (2) en recréer un et le distribuer au seul endroit légitime (secret CI/Vault) ; (3) vérifier les journaux d'accès (`/var/log/pveproxy/access.log`, tâches dans `pvesh get /cluster/tasks`) sur la période d'exposition ; (4) vérifier l'intégrité des VMs du pool (VMs créées, configurations modifiées, cloud-init altéré) et des sauvegardes ; (5) purger le secret de l'historique Git et considérer qu'il reste compromis (les forks et caches gardent la trace) ; (6) déclarer l'incident (INC) à la RSSI, post-mortem, et mettre en place Gitleaks/pre-commit (module 01) et la rotation périodique.

**14. Sécurisation de l'API (8006).** (a) **Filtrage réseau** (IPSet `management`, VPN) : protège contre l'accès depuis des réseaux non autorisés ; ne protège pas contre un poste d'administration compromis. (b) **TFA** sur les comptes humains : protège contre le vol de mot de passe ; ne protège ni les jetons ni SSH. (c) **Jetons à privilèges minimaux** avec séparation des privilèges et expiration : limite l'impact d'une fuite ; ne l'empêche pas. (d) **Certificat TLS valide** (ACME ou PKI interne, module 06) : protège contre l'interception (MITM) et habitue les admins à ne plus accepter d'avertissement ; ne protège pas l'authentification elle-même. (e) Autres : SSO OIDC (comptes centralisés, révocation immédiate), `pveproxy` en écoute restreinte (`LISTEN_IP`, `ALLOW_FROM`), journalisation centralisée et alertes sur les connexions, reverse proxy avec authentification forte devant l'interface.

**15. Pare-feu de VM — réponse b.** Le pare-feu d'une VM ne filtre que si son option `enable` (dans `<VMID>.fw`, section `[OPTIONS]`, par défaut désactivée) est à 1 **et** que l'interface a `firewall=1`. Sans fichier, l'option vaut 0 : aucun filtrage. a) La politique `policy_in` du datacenter s'applique aux **hôtes**, pas aux VMs (les VMs ont leur propre `policy_in`, défaut DROP une fois activées). c) Les règles de l'hôte ne s'appliquent pas au trafic bridgé des VMs. d) L'IPSet `management` ne concerne que l'accès aux services de l'hôte. Note : `firewall=1` sur l'interface insère quand même le bridge intermédiaire `fwbr…`, sans règle.

**16. Agent, fs-freeze et bases de données.** En mode *snapshot*, `vzdump` demande à l'agent de geler les systèmes de fichiers (`fsfreeze` : vidage des caches, blocage des écritures) pendant la création du point de sauvegarde, puis de les dégeler : l'image sauvegardée est cohérente au niveau du système de fichiers (pas de journal à rejouer, pas de fichier à moitié écrit au niveau FS). Mais PostgreSQL peut avoir des transactions en cours dont les données sont en mémoire ou réparties entre plusieurs fichiers : l'image est l'équivalent d'une coupure de courant propre — PostgreSQL redémarre en rejouant son WAL, ce qui fonctionne en général, mais ce n'est pas une sauvegarde **applicative** (pas de point de restauration précis, pas de garantie, pas de PITR). Au module 27 : sauvegardes natives (base backups + archivage WAL continu, via CloudNativePG/Barman vers S3) permettant la restauration à un instant précis ; éventuellement des *hooks* pre-freeze/post-thaw de l'agent (`/etc/qemu/fsfreeze-hook`) pour mettre la base en mode sauvegarde.

**17. Endurance NVMe.** 1 200 TBW / 0,4 To par jour = 3 000 jours ≈ 8,2 ans… en théorie. Mais l'amplification d'écriture n'est pas comptée : ZFS (copie-sur-écriture, métadonnées, ZIL), Ceph (réplication ×3 entre OSD **sur le même disque physique**, journal BlueStore/RocksDB), et la VM elle-même (journal ext4/XFS) peuvent multiplier par 3 à 10 les écritures réelles : on tombe à 1-3 ans. Réductions : placer les OSD Ceph imbriqués sur le SSD `ssd-lab` (c'est prévu), pas de `sync=always`, `atime=off`, compression ZFS `lz4`, `volblocksize` adapté, réplication Ceph à 2 en lab, éteindre les profils lourds inutilisés, éviter le swap sur NVMe. Suivi : `smartctl -a /dev/nvme0` (*Percentage Used*, *Data Units Written* × 512 000 octets), à superviser (module 21).

**18. PBS dans la même maison.** Un PRA protège contre la perte du **site** (incendie, dégât des eaux, vol, coupure prolongée, ransomware qui chiffre tout ce qui est joignable). Si `pbs01` est dans le même bâtiment, sur le même réseau électrique et le même LAN que `pve01`, un sinistre emporte les deux : c'est une sauvegarde locale bien faite, pas un PRA. Règle 3-2-1 : 3 copies (production + 2 sauvegardes), sur 2 supports différents, dont 1 hors site ; la variante 3-2-1-1-0 ajoute 1 copie hors ligne/immuable et 0 erreur à la vérification. Ici : 2 copies, 1 support de sauvegarde (un HDD unique), 0 vraiment hors site, 0 hors ligne. Réponse MédiSphère : PAR2 est un site distinct (simulé dans le lab) ; à terme, synchronisation PBS (*sync job* en mode *pull*) vers un troisième PBS ou un stockage objet hors site, une copie hors ligne (bande ou disque amovible rangé ailleurs), datastore protégé contre l'effacement par l'attaquant (droits séparés, pas de `Datastore.Prune` pour le client, *pull* plutôt que *push*), et tests de restauration réguliers (F5).

---

### M00-E36 — Chiffrer les sauvegardes côté client

**Solution**

*1. Ce qu'il faut savoir.* Le client (`vzdump` via `proxmox-backup-client`/`libproxmox-backup-qemu` sur `pve01`) chiffre chaque bloc en AES-256-GCM avant l'envoi ; PBS ne stocke que des blocs chiffrés et ne possède jamais la clé. Sont chiffrés : le contenu des blocs (disques, archives `pxar`) et les *blobs* (configuration de la VM, journal client). Restent lisibles par PBS : le type et l'identifiant du groupe (`vm/1002`, `host/pve01`), l'horodatage, la taille des archives et des index, le propriétaire, les notes, et le manifeste (signé par une clé dérivée, pour détecter une falsification). L'identifiant d'un bloc chiffré est calculé avec une clé dérivée de la clé de chiffrement : un bloc identique ne produit **pas** le même identifiant chiffré et en clair, ni avec deux clés différentes. Il n'y a donc **aucune déduplication** entre sauvegardes en clair et chiffrées, ni entre clients ayant des clés différentes ; elle fonctionne entre sauvegardes chiffrées avec la même clé.

*2. Génération et mise à l'abri.*

```
root@pve01:~# pvesm set pbs-par2 --encryption-key autogen
root@pve01:~# ls -l /etc/pve/priv/storage/
-rw------- 1 root www-data  … pbs-par2.enc
-rw------- 1 root www-data  … pbs-par2.pw
root@pve01:~# proxmox-backup-client key show /etc/pve/priv/storage/pbs-par2.enc
root@pve01:~# proxmox-backup-client key paperkey /etc/pve/priv/storage/pbs-par2.enc --output-format text > /root/paperkey-pbs-par2.txt
```

Imprime (ou recopie dans le gestionnaire de mots de passe) `paperkey-pbs-par2.txt`, copie `pbs-par2.enc` sur une clé USB rangée hors du lab, note l'empreinte (`Fingerprint` de `key show`) à côté, puis **supprime** `/root/paperkey-pbs-par2.txt` (il contient la clé en clair). L'option `--encryption-key` accepte aussi le contenu d'une clé existante (pour réutiliser une clé sur un autre nœud) : voir `man pvesm`.

*3. Première sauvegarde chiffrée.*

```
root@pve01:~# vzdump 1002 --storage pbs-par2 --mode snapshot
…
INFO: drive-scsi0: dirty-bitmap status: existing bitmap was invalid and has been cleared
…
INFO: backup is encrypted
```

(Libellés exacts variables selon la version.) La première sauvegarde chiffrée relit tout le disque (le *dirty bitmap* de QEMU n'est valable que pour la même clé) et transfère tous les blocs (pas de déduplication avec les anciens blocs en clair) : durée et volume d'une sauvegarde complète. Dans l'interface de PBS, la colonne *Encrypted* passe à « Encrypted » (cadenas), les anciens instantanés restent « No ». Côté `pve01` :

```
root@pve01:~# pvesh get /nodes/pve01/storage/pbs-par2/content --content backup --vmid 1002 --output-format json-pretty | grep -E '"(volid|encrypted)"'
```

*4. Anciennes sauvegardes en clair.* Choix défendable dans le lab : les laisser expirer par la rétention (*prune*), puisqu'elles ne contiennent pas encore de données de santé et restent utiles pour une restauration dans les jours qui viennent ; garder en tête que, pendant ce temps, PAR2 détient des copies lisibles. En production HDS : supprimer (*forget* depuis l'interface PBS, avec un compte disposant du droit sur le datastore) les instantanés en clair dès que la première sauvegarde chiffrée est **vérifiée**, puis lancer un GC pour effacer physiquement les blocs. Cas particulier : les instantanés `host/pve01` en clair contiennent `config.db`, donc **tous les secrets** de `/etc/pve/priv` (jeton PBS, secrets SMTP, `authkey`, TFA) : à supprimer en priorité, et à faire suivre d'une rotation du jeton `wb-backup` si PAR2 n'est pas jugé de confiance.

*5. Sauvegarde de configuration.* Le script de M00-E30 ajoute `--keyfile /etc/pve/priv/storage/pbs-par2.enc` dès que le fichier existe : relance `systemctl start wb-backup-config.service`, le journal affiche « Chiffrement : clé … ». La clé est alors présente **dans** la sauvegarde chiffrée par elle-même : aucun risque (il faut la clé pour la lire), mais aucune aide non plus le jour où `pve01` est perdu — la seule voie de restauration est la paperkey ou la copie hors ligne. C'est exactement ce que doit couvrir la procédure de conservation. Sans E36, c'était pire : la sauvegarde de configuration aurait contenu la clé **en clair** à PAR2.

*6. Test de restauration.*

```
root@pve01:~# pvesm list pbs-par2 --vmid 1002
root@pve01:~# qmrestore pbs-par2:backup/vm/1002/<HORODATAGE> 5092 --storage local-nvme --pool lab --unique 1
root@pve01:~# qm set 5092 --net0 "$(qm config 5092 | sed -n 's/^net0: //p'),link_down=1" --onboot 0 --name dns01-test
root@pve01:~# qm start 5092 && sleep 30 && qm agent 5092 ping && echo "VM 5092 OK"
root@pve01:~# qm stop 5092 && qm destroy 5092 --purge
```

`--unique 1` génère une nouvelle MAC (et un nouveau `vmgenid`/UUID SMBIOS) ; `link_down=1` débranche virtuellement la carte : même IP que `dns01`, aucun conflit. `--onboot 0` évite qu'un redémarrage de `pve01` ne la relance. La restauration lit la clé dans `/etc/pve/priv/storage/pbs-par2.enc` : sans elle, `qmrestore` échoue (« missing key »).

*7. Reconstitution depuis la paperkey* (sur `adm01`, avec le texte de la paperkey copié dans `paperkey.txt`) : la partie texte contient, entre les marqueurs `-----BEGIN PROXMOX BACKUP KEY-----` et `-----END PROXMOX BACKUP KEY-----`, la clé elle-même au format JSON (les QR codes encodent la même chose).

```
admin@adm01:~$ sed -n '/-----BEGIN PROXMOX BACKUP KEY-----/,/-----END PROXMOX BACKUP KEY-----/p' paperkey.txt | sed '1d;$d' > cle-reconstituee.json
admin@adm01:~$ proxmox-backup-client key show cle-reconstituee.json
admin@adm01:~$ shred -u cle-reconstituee.json paperkey.txt
```

`proxmox-backup-client` s'installe sur Debian depuis le dépôt client de Proxmox (`pbs-client`), ou se lance sur `pve01` en travaillant dans un répertoire temporaire. Compare l'empreinte avec celle notée : identiques. (Format exact de la paperkey à vérifier selon ta version ; si la clé est protégée par une phrase de passe — ce n'est pas le cas d'une clé `autogen` — elle sera demandée.)

*8. Procédure de conservation* (exemple) :
- Trois exemplaires : paperkey imprimée sous enveloppe scellée dans un coffre (hors des deux sites) ; fichier `.enc` sur clé USB chiffrée dans un second lieu ; entrée dans le coffre-fort de mots de passe de l'équipe (accès : responsable infrastructure + un suppléant).
- Empreinte notée sur chaque exemplaire.
- Vérification semestrielle : reconstituer depuis un exemplaire, comparer l'empreinte, journaliser.
- Rotation : une nouvelle clé ne rechiffre pas l'existant. Les anciennes sauvegardes restent lisibles **uniquement** avec l'ancienne clé, qu'il faut donc conserver jusqu'à l'expiration de la dernière sauvegarde concernée (rétention mensuelle : 6 mois). La rotation se fait donc rarement, sur événement (suspicion de compromission, départ d'un détenteur).
- Perte de toutes les copies = perte définitive de toutes les sauvegardes chiffrées : à inscrire au registre des risques.

**Explications**

Le modèle de menace couvert : un attaquant (ou un administrateur) qui obtient l'accès à PAR2 ou aux disques de `pbs01` ne lit pas les données. Il ne couvre pas : la suppression des sauvegardes par cet attaquant (disponibilité : c'est le rôle des copies supplémentaires et des droits séparés), la compromission de `pve01` (qui détient la clé et les données en clair de toute façon), ni la fuite de métadonnées (noms de groupes, tailles, rythme des sauvegardes). La **clé maîtresse** (paire RSA, `proxmox-backup-client key create-master-key`, option `master-pubkey` du stockage PBS dans Proxmox) ajoute à chaque sauvegarde une copie de la clé de chiffrement chiffrée par la clé publique maîtresse : la clé privée maîtresse, conservée hors ligne, permet de récupérer la clé de chiffrement depuis n'importe quelle sauvegarde (`proxmox-backup-client key import-with-master-key`). C'est un filet de sécurité supplémentaire, pas un remplacement de la paperkey.

**Alternatives**
- Chiffrement du datastore au repos sur `pbs01` (LUKS/ZFS natif) : protège contre le vol du disque, pas contre un administrateur de PAR2 ; complémentaire.
- Clé protégée par phrase de passe (créée avec `proxmox-backup-client key create`) : impossible pour des sauvegardes planifiées non interactives (il faudrait stocker la phrase de passe à côté).

**Pièges classiques**
- Générer la clé et lancer les sauvegardes avant d'avoir exporté la paperkey.
- Laisser le fichier de paperkey en clair dans `/root` (il finit dans la sauvegarde de configuration).
- Restaurer le test sur le réseau de production sans `link_down` ni `--unique` : conflit d'IP/MAC avec `dns01`.
- Croire que la rotation de clé protège les anciennes sauvegardes.
- Oublier les instantanés `host/` en clair, qui contiennent tous les secrets.
- S'étonner de la durée et du volume de la première sauvegarde chiffrée.

**En production chez MédiSphère**
Clé de chiffrement par périmètre (une par cluster ou par client), clé maîtresse RSA détenue par la RSSI hors ligne, détention à deux personnes, procédure testée et tracée (preuve d'audit HDS), suppression des sauvegardes en clair consignée. À terme, intégration avec Vault (module 25) pour la distribution des clés aux nœuds.

---

### M00-E37 — Exercice de restauration chronométré

**Solution** — déroulé de référence (RTO cible ≈ 10-12 minutes pour une VM de 8 Go sur NVMe, tunnel sur un LAN gigabit)

*Préparation (hors chrono)* : `pvesm list pbs-par2 --vmid 1002` montre une sauvegarde de moins de 24 h ; le runbook M00-E25 est ouvert ; un terminal sur `pve01`, un sur `adm01`.

| Jalon | Ce qu'on fait | Temps typique |
|---|---|---|
| T0 | `qm stop 1002` | 0 |
| T1 | Depuis `adm01` : `dig @10.10.20.10 adm01.par1.medisphere.internal` → *timed out* ; `ping -c2 10.10.20.10` → aucune réponse ; `ping 10.10.20.1` OK (le VLAN et `gw01` vont bien) ; sur `pve01` : `qm status 1002` → *stopped*. Diagnostic : VM `dns01` hors service. | +1 à 2 min |
| T2 | `pvesm list pbs-par2 --vmid 1002` → dernier instantané ; décision : restaurer celui-ci, VMID 5091, stockage `local-nvme`, pool `lab`, même MAC (1002 ne redémarrera pas) | +1 min |
| T3 | `qm set 1002 --onboot 0` puis `qmrestore pbs-par2:backup/vm/1002/<HORODATAGE> 5091 --storage local-nvme --pool lab` | +3 à 6 min |
| T4 | `qm start 5091` ; depuis `adm01` : `dig @10.10.20.10 adm01.par1.medisphere.internal +short`, `dig @10.10.20.10 debian.org +short`, renouvellement DHCP d'une VM sandbox et lecture du journal `dnsmasq` de la VM restaurée | +2 à 3 min |
| T5 | Retour à l'état cohérent (voir ci-dessous) | hors chrono |

Variante plus rapide : `qmrestore … 5091 --storage local-nvme --pool lab --live-restore 1` démarre la VM immédiatement pendant que les données arrivent en arrière-plan (lectures servies à la demande depuis PBS) : le service revient en 1-2 minutes, avec des performances dégradées tant que la restauration n'est pas finie, et un risque : si la liaison avec PBS tombe pendant la restauration à chaud, la VM est inutilisable. À éviter pour `gw01` (la liaison vers PBS passe par lui !).

*T5 — option A (retour nominal, recommandée)* :

```
root@pve01:~# qm shutdown 5091
root@pve01:~# qm set 1002 --onboot 1 && qm start 1002
admin@adm01:~$ dig @10.10.20.10 adm01.par1.medisphere.internal +short
root@pve01:~# qm destroy 5091 --purge
```

Simple, conforme au PLAN (`dns01` = 1002), aucune référence à modifier. Les changements faits sur 5091 pendant son service (baux DHCP, journaux) sont perdus : négligeable ici.

*T5 — option B (5091 devient `dns01`)* : `qm set 5091 --onboot 1` (déjà hérité de la sauvegarde si E32 est fait), `qm set 1002 --onboot 0` ou suppression de 1002 après quelques jours. Conséquences à documenter : VMID hors de la plage du socle (1000-1099, PLAN §4.6) ; la tâche de sauvegarde, si elle sélectionne des VMIDs et non le pool, ne sauvegarde plus `dns01` ; nouvel historique de sauvegarde (groupe `vm/5091`) ; tous les scripts, checks et documents qui citent 1002 sont faux. Pour revenir à 1002 avec le contenu de 5091, il faudrait sauvegarder 5091 puis restaurer en écrasant 1002 (`qmrestore … 1002 --force`), opération destructive à planifier. D'où la préférence pour A.

*RTO/RPO* : RTO = T4 − T0 (ex. 11 min) ; RPO = T0 − heure de la sauvegarde (ex. sauvegarde de 21 h, incident à 15 h le lendemain : 18 h de données potentiellement perdues ; pour `dns01`, la configuration est statique : perte réelle quasi nulle, hors baux DHCP).

*Traçabilité* : feuille de temps et retour d'expérience en tête de `~/medisphere/docs/socle/tests/restauration.md` (même forme que l'exemple de M00-E50 : [`fichiers/M00-E50/docs/socle/tests/restauration.md`](fichiers/M00-E50/docs/socle/tests/restauration.md)), runbook RB-002 mis à jour dans `docs/socle/runbooks/`, un commit qui cite le ticket.

**Explications**

L'exercice mesure trois choses : la vitesse de **diagnostic** (attribuer le symptôme à la bonne cause sans fausse piste — d'où le test de la passerelle avant de conclure), la **préparation** (commandes prêtes dans le runbook, nom exact du stockage, syntaxe du volume PBS), et la maîtrise des **effets de bord** d'une restauration à côté de l'original : même nom, même IP, même MAC, même `onboot` et même ordre de démarrage hérités de la configuration sauvegardée. Si 1002 et 5091 ont toutes deux `onboot: 1`, le prochain redémarrage de `pve01` démarre les deux : conflit d'adresse IP et de MAC, DNS erratique. C'est la principale vérification du check.

**Alternatives**
- Redondance plutôt que restauration : un second serveur DNS (`dns02`) et deux résolveurs dans la configuration des clients rendent la perte de `dns01` transparente (RTO ≈ 0). La restauration reste nécessaire pour retrouver la redondance. Ce sera le cas avec PowerDNS (module 06).
- Restaurer directement sur 1002 avec `--force` : plus rapide d'une étape, mais destructif (écrase la VM « perdue », qu'on aurait peut-être voulu analyser : post-mortem, forensique).

**Pièges classiques**
- Lancer le chrono sans avoir vérifié la présence d'une sauvegarde récente.
- Restaurer sans `--pool lab` (la VM n'apparaît pas dans le pool, échappe à la tâche de sauvegarde par pool et aux droits de `wb-admin`).
- Oublier `onboot` sur 1002 : double démarrage au prochain redémarrage.
- Restaurer avec `--unique 1` puis s'étonner que les baux DHCP ou une règle basée sur la MAC ne fonctionnent plus (ici, sans effet, `dns01` a une IP statique).
- Chercher la cause dans le DNS (configuration dnsmasq) au lieu de constater d'abord que la VM ne répond même pas au ping.
- Restaurer `gw01` en *live restore* (le flux PBS passe par lui).

**En production chez MédiSphère**
Exercice de restauration trimestriel imposé par le plan de continuité (preuve d'audit HDS/ISO 27001 : feuille de temps, RTO/RPO mesurés, écarts et actions), sur des services tirés au sort, avec une variante « sans la personne qui a écrit le runbook ». Les RTO mesurés alimentent le catalogue de services et les engagements (SLO) ; un RTO mesuré supérieur à la cible déclenche une action (automatisation, redondance) et non une révision de la cible.
