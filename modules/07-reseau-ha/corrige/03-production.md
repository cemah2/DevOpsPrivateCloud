# Module 07 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- comportement de keepalived 2.3 quand une VIP qu'il doit poser existe déjà sur l'interface : le corrigé l'**évite** (retrait de `.1` statique puis rechargement, coupure bornée de ≈ 3,5 s par VLAN) plutôt que d'en dépendre ;
- `netplan apply` (ou un redémarrage de systemd-networkd) sur une passerelle maître qui retirerait les VIP posées par keepalived : le rôle `routeur_reseau` ne l'appelle jamais, ne le teste pas sur une passerelle en service ;
- privilège exact pour rattacher une carte à `vmbr0`/`vmbr1` hors SDN (`SDN.Use` sur `/sdn/zones/localnetwork/<pont>`) avec Proxmox VE 9.2 ; champ « parent » des interfaces de VM dans le fournisseur NetBox `e-breuninger/netbox` 5.8 ; attribut `mtu` du bloc `network_device` du fournisseur `bpg/proxmox` 0.116 ;
- traitement par cloud-init d'une seconde carte sans `ip_config` (`ens19` laissée sans adresse ou en DHCP) ;
- prise en compte des ARP gratuits par la box du LAN maison lors du déplacement de la VIP WAN (certaines box les ignorent : `vrrp_garp_master_refresh` les répète) ;
- contenu exact du filtre `Address Ignore` de conntrackd vis-à-vis des flux traduits (le corrigé n'y met **pas** les VIP ; vérifie avec `conntrackd -e` qu'un flux traduit vers la VIP WAN apparaît dans le cache externe du secondaire) ;
- service `prometheus-exporter` dans le paquet de haproxy.debian.net (présent dans les paquets usuels, vérifie `haproxy -vv`) ; options `observe layer7 error-limit … on-error mark-down` (validées avec `haproxy -c` en 2.8, à confirmer en 3.2) ;
- ordre des hôtes d'un motif `bordure_secours:bordure_maitre` dans `routeurs.yml` (version E27) ;
- noms des variables des rôles `certificats_acme`, `ssh_durci` et du module `enregistrement-dns` produits au module 06 : les fichiers de ce corrigé les nomment de façon cohérente entre eux ; si les tiens diffèrent, la logique est la même.

**Valeurs d'exemple des fichiers** (à remplacer par celles de `lab/inventaire-local.md`) : `<LAN-MAISON>` 192.168.1.0/24, `<IP-BOX>` 192.168.1.1, `<IP-PVE01>` 192.168.1.20, `<IP-HP01-LAN>` 192.168.1.30, `<IP-GW01-WAN>` 192.168.1.40, `<IP-GW02-WAN>` 192.168.1.41, `<IP-GW-WAN-VIP>` 192.168.1.50.

**Règle qui traverse tout le palier** : *rien ne vise une adresse propre d'une passerelle, sauf ce qui doit justement viser une passerelle précise* (Ansible, voisins BGP, pairs VRRP, lien `conntrackd`, accès de secours), et alors on la vise **dans le VLAN où l'on se trouve**. Une passerelle a une patte dans chaque VLAN : un client du VLAN 10 qui viserait `10.10.20.2` passerait par la passerelle active et recevrait la réponse directement par le VLAN 10 ; quand l'active est l'autre passerelle, celle-ci ne voit que la moitié de la conversation et son suivi d'état la jette. C'est la raison de [`connexion.yml`](fichiers/M07-E24/ansible/inventories/lab/group_vars/role_routeur/connexion.yml).

---

### M07-E24 — Une seconde passerelle : `gw02`

**Solution**

Fichiers : [`infra/socle/gw02.tf`](fichiers/M07-E24/infra/socle/gw02.tf) ; rôle [`routeur_reseau`](fichiers/M07-E24/ansible/roles/routeur_reseau/) ; inventaire : [`group_vars/role_routeur/routeur_reseau.yml`](fichiers/M07-E24/ansible/inventories/lab/group_vars/role_routeur/routeur_reseau.yml), [`connexion.yml`](fichiers/M07-E24/ansible/inventories/lab/group_vars/role_routeur/connexion.yml), [extrait de la matrice déplacée](fichiers/M07-E24/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`host_vars/gw01/routeur_reseau.yml`](fichiers/M07-E24/ansible/inventories/lab/host_vars/gw01/routeur_reseau.yml), [`host_vars/gw02/`](fichiers/M07-E24/ansible/inventories/lab/host_vars/gw02/) (`routeur_reseau.yml`, `certificats.yml`, `frr.yml`, `relais_dhcp.yml`, `amorcage.yml.exemple`), [extrait de `leaf01`](fichiers/M07-E24/ansible/inventories/lab/host_vars/leaf01/frr-bordure.yml.extrait) ; [`playbooks/routeurs.yml`](fichiers/M07-E24/ansible/playbooks/routeurs.yml).

*1. Réservation.* Choix retenu : NetBox est rempli **par OpenTofu** (comme `dns02` en M06-E24), avec les adresses **imposées** : on ne prend pas la « première libre » d'une plage pour une passerelle. Si les `.2`/`.3` avaient été réservées en M06-E05 (statut `reserved`), supprime-les ou importe-les avant l'`apply`, sinon doublon. `gw01` est modélisée à la main depuis M06-E05 : vérifie qu'elle a bien des interfaces `ens19.<VLAN>` (E25 y rattachera les groupes FHRP).

*2. La VM.* `gw02.tf` décrit directement la VM (deux `network_device` : `vmbr0`, puis `vmbr1` avec `mtu = 9000`, sans `vlan_id`), les objets NetBox (VM, interfaces, neuf adresses `.3`, adresse principale 10.10.10.3), et le nom par le module `enregistrement-dns`. cloud-init ne reçoit **qu'un** `ip_config` (le WAN). Droit manquant (Proxmox VE 8 et 9 : un pont hors SDN se contrôle par le chemin `/sdn/zones/localnetwork/<pont>`) :

```
root@pve01:~# pveum acl modify /sdn/zones/localnetwork/vmbr0 --roles PVESDNUser --users wb-tofu@pve
root@pve01:~# pveum acl modify /sdn/zones/localnetwork/vmbr1 --roles PVESDNUser --users wb-tofu@pve
```

(`PVESDNUser` = `SDN.Audit` + `SDN.Use` ; si tu préfères n'ajouter que `SDN.Use` au rôle `WBTofu` sur ces deux chemins, c'est équivalent. Le jeton hérite des droits de son utilisateur s'il n'est pas à privilèges séparés ; sinon, même ACL avec `--tokens 'wb-tofu@pve!tofu'`.) Plan attendu : la VM, une douzaine d'objets NetBox, deux enregistrements DNS, **rien d'autre**. Puis l'ordre de démarrage, en root : `qm set 1009 --startup order=1`.

*Amorçage.* Avant `routeur_reseau`, `gw02` n'a que son adresse WAN. Premier passage : `host_vars/gw02/amorcage.yml` (`ansible_host: <IP-GW02-WAN>`) et une règle de transit **temporaire** `adm01 → <IP-GW02-WAN>:22` (motif « amorçage gw02 », retirée dans la MR suivante avec le fichier d'amorçage). Le certificat d'hôte SSH porte le nom `gw02.par1.medisphere.internal` : `HostKeyAlias` (`connexion.yml`) le fait vérifier quelle que soit l'adresse.

*3. Le rôle `routeur_reseau`.* Deux principes : (1) le **fichier** fait foi au démarrage (`/etc/network/interfaces` sur `gw01`, validé par `ifquery`, `/etc/netplan/60-routeur.yaml` sur `gw02`) ; (2) l'**état courant** est posé par un script idempotent, [`routeur-reseau-a-chaud`](fichiers/M07-E24/ansible/roles/routeur_reseau/templates/routeur-reseau-a-chaud.j2), qui **ajoute** ce qui manque et ne retire jamais rien (en `--check`, il simule). Aucun gestionnaire ne redémarre le réseau. Sur `gw01`, le premier passage doit donner :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/routeurs.yml --limit gw01 --check --diff
… --- before: /etc/network/interfaces
… +++ after: …   (commentaires, ordre des stanzas, « mtu » explicite)
… TASK [routeur_reseau : Poser ce qui manque …] ok    ← rien à poser : l'état courant est déjà le bon
```

Sur `gw02`, le gabarit netplan **renomme** les cartes : `match: macaddress` + `set-name: ens18`/`ens19`, avec les adresses MAC fixées dans `gw02.tf` (`mac_address`) et reprises dans `host_vars/gw02/routeur_reseau.yml` (`routeur_reseau_renommage`). Le rôle retire `/etc/netplan/50-cloud-init.yaml` (qui nomme les mêmes cartes `eth0`/`eth1`) et, au premier passage seulement (`ens19` absente des faits), redémarre `gw02` : un renommage ne s'applique qu'au démarrage, et `gw02` n'est pas encore en service (assertion : aucune instance keepalived). ⚠️ À confirmer sur ton lab : nom des cartes après le premier démarrage (`ip -br link`) et contenu exact du fichier écrit par cloud-init.

Les différences de **forme** (commentaires, ordre) sont normales ; une différence d'**adresse** est un arrêt. Les routes de garde (`unreachable … metric 4000`) sont la seule nouveauté réelle de `gw01` : vérifie `ip route show type unreachable`.

*4. Une seule matrice.* `git mv host_vars/gw01/pare_feu.yml group_vars/role_routeur/pare_feu.yml`, puis une seule règle à réécrire : la réponse de Kea visait `destination: 10.10.99.1` ; elle arrive sur la passerelle elle-même (chaîne `input`), la destination est donc implicite (l'[extrait](fichiers/M07-E24/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) explique). `routeurs.yml --limit gw01 --check --diff` : aucune différence sur `/etc/nftables.conf` hors cette règle.

*5. Les services.* NTS : `gw02` demande un certificat pour son nom et **ses** adresses `.3` (défi HTTP-01 de `ca01` vers chaque adresse : la règle d'entrée de M06-E21 vaut pour les deux passerelles). FRR : `router-id` 10.10.10.3, même configuration que `gw01` (groupe `role_routeur`) ; côté maquette, `leaf01` reçoit un second voisin 10.10.99.3 (et, dès E25, remplace 10.10.99.1 par 10.10.99.2) ; la session part de l'adresse propre (`update-source`).

```
admin@gw02:~$ sudo vtysh -c 'show bgp summary'          # 10.10.99.251 … Established
admin@gw02:~$ chronyc -N sources ; sudo chronyc -N authdata  # sources NTS amont authentifiées
```

*6. Preuves sans client.*

```
admin@adm01:~$ sudo ip route add 10.10.99.<X>/32 via 10.10.10.3      # VM du VLAN 99, route hôte temporaire
admin@adm01:~$ ssh admin@10.10.99.<X> true
admin@gw02:~$ sudo tcpdump -ni ens19.99 host 10.10.99.<X> and port 22   # le trafic traverse gw02
admin@adm01:~$ sudo ip route del 10.10.99.<X>/32 via 10.10.10.3
```

Attention, ce test est lui-même **asymétrique** : la VM répond par sa passerelle (`.1`, `gw01`). La connexion SSH aboutit parce que `gw01` accepte la réponse au titre de la règle « bastion MGMT vers tout le lab »… et parce que `nf_conntrack_tcp_loose` vaut encore 1. Garde l'observation pour E25 (étape 7). Le second test (VM du VLAN 99, route hôte vers une adresse Internet par 10.10.99.3) prouve la traduction de `gw02` (`curl ifconfig.me` renvoie `<IP-GW02-WAN>` à ce stade). Comparaison des règles :

```
admin@adm01:~$ diff <(ssh gw01 sudo nft -s list ruleset) <(ssh gw02 sudo nft -s list ruleset) && echo identiques
```

**Explications**

Une passerelle redondante n'a de valeur que si les deux nœuds sont **interchangeables** : même filtrage, même traduction, même routage. D'où une matrice commune, des rôles communs, et des variables d'hôte réduites au strict nécessaire (suffixe d'adresse, pile réseau, adresse WAN, identifiant de routeur). La pile réseau diffère (ISO contre image dorée) : le rôle l'absorbe plutôt que de réinstaller `gw01`. Le choix « fichier + application à chaud sans retrait » vient de ce que la passerelle porte le lab : un `systemctl restart networking` coupe tous les VLAN, et un retrait d'adresse automatique pourrait retirer une VIP posée par keepalived (que le rôle ne connaît pas).

**Alternatives**
- Réinstaller `gw01` depuis l'image dorée (même pile que `gw02`, importée dans OpenTofu) : plus propre à terme, mais c'est une reconstruction de la bordure ; à faire **après** E25, en basculant sur `gw02` le temps de reconstruire `gw01` (bon exercice de RB-071).
- Un module OpenTofu `vm-routeur` : justifié s'il y a d'autres routeurs (PAR2, LYO1 réel) ; pour une VM, le code direct est lisible.
- `ifupdown2` (rechargement à chaud `ifreload -a`) sur `gw01` : possible, mais `ifreload` retire les adresses qu'il ne connaît pas… dont les VIP.

**Pièges classiques**
- Une adresse `.1` sur `gw02` (copier-coller de `gw01`) : conflit immédiat sur tout un VLAN. Le rôle refuse (assertion) tant que keepalived n'existe pas.
- `netplan apply` sur `gw02` une fois en service (après E25 : retrait possible des VIP).
- Oublier les routes de garde : quand `gw02` routera sans tunnel, le trafic vers PAR2 partira vers Internet (fuite d'adresses privées, et diagnostics trompeurs).
- Viser `gw02` depuis `runner01` par son adresse MGMT (routage asymétrique) : `connexion.yml`.
- Comparer les règles sans `-s` (compteurs) : tout diffère.

**En production chez MédiSphère**
Les deux passerelles seraient sur deux hyperviseurs (règle d'anti-affinité du cluster, M09) ou deux appliances physiques ; l'inventaire NetBox porterait un « rôle d'équipement » `routeur-bordure` et le contrôle de conformité comparerait automatiquement les jeux de règles chargés (M21).

---

### M07-E25 — VRRP sur les passerelles du lab

**Solution**

Fichiers : rôles [`keepalived`](fichiers/M07-E25/ansible/roles/keepalived/) (celui de M07-E08, étendu : champ `actif` par instance, groupes de synchronisation qui suivent des interfaces et appellent un script sous un compte choisi, rechargement différable) et [`bordure`](fichiers/M07-E25/ansible/roles/bordure/) (script [`bordure-transition`](fichiers/M07-E25/ansible/roles/bordure/files/bordure-transition)) ; filtre [`nft.py`](fichiers/M07-E25/ansible/collections/ansible_collections/medisphere/socle/plugins/filter/nft.py) étendu et [ses tests](fichiers/M07-E25/ansible/collections/ansible_collections/medisphere/socle/tests/unit/plugins/filter/test_nft_vrrp.py) ; inventaire : [`group_vars/role_routeur/keepalived.yml`](fichiers/M07-E25/ansible/inventories/lab/group_vars/role_routeur/keepalived.yml), [`host_vars/gw01/bordure.yml`](fichiers/M07-E25/ansible/inventories/lab/host_vars/gw01/bordure.yml), [`host_vars/gw02/bordure.yml`](fichiers/M07-E25/ansible/inventories/lab/host_vars/gw02/bordure.yml), [`host_vars/gw01/routeur_reseau.yml`](fichiers/M07-E25/ansible/inventories/lab/host_vars/gw01/routeur_reseau.yml), [`relais_dhcp.yml`](fichiers/M07-E25/ansible/inventories/lab/host_vars/gw01/relais_dhcp.yml) des deux passerelles, [`certificats.yml`](fichiers/M07-E25/ansible/inventories/lab/host_vars/gw01/certificats.yml) et [`frr.yml`](fichiers/M07-E25/ansible/inventories/lab/host_vars/gw01/frr.yml) de `gw01`, [`group_vars/all/temps.yml`](fichiers/M07-E25/ansible/inventories/lab/group_vars/all/temps.yml), [extrait de la matrice](fichiers/M07-E25/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; playbooks [`migration-vrrp.yml`](fichiers/M07-E25/ansible/playbooks/migration-vrrp.yml) et [`netbox-bordure.yml`](fichiers/M07-E25/ansible/playbooks/netbox-bordure.yml) ; fiche [CHG-855](fichiers/M07-E25/medisphere/docs/socle/changements/CHG-855-vrrp-bordure.md) ; RB-071 : version complète en E26.

*1. Lecture* (réponses attendues) :
- *Skew_Time* = ((256 − priorité) × intervalle) / 256 ; *Master_Down_Interval* = 3 × intervalle + *Skew_Time*. Priorité 150 : 3 + 0,41 = **3,41 s** ; priorité 100 : 3 + 0,61 = **3,61 s**. C'est la coupure quand le maître disparaît **sans prévenir**. Quand il s'arrête proprement, il envoie une annonce de priorité 0 : le secours n'attend que son *skew* (≈ 0,6 s).
- Groupe de synchronisation : quand une instance change d'état, toutes les instances du groupe suivent ; un script `notify` de groupe reçoit `GROUP`, le nom, l'état cible et la priorité (pas d'état `STOP` pour un groupe).
- *Accept mode* (VRRP v3) : la passerelle qui porte une VIP sans en être « propriétaire » (priorité < 255) accepte les paquets **adressés** à la VIP. keepalived l'active par défaut, sauf en `vrrp_strict` : sans lui, `ping 10.10.99.1` échoue, et surtout les services qui écoutent sur la VIP (la redirection WAN de E26, l'extrémité de `wg2`) cessent de fonctionner.

*2. La fiche.* [CHG-855](fichiers/M07-E25/medisphere/docs/socle/changements/CHG-855-vrrp-bordure.md) : plan, ordre (99, 70, 60, 52, 50, 40, 30, 20, 10), `nopreempt` justifié (une panne = une bascule ; retour planifié par RB-071), prérequis, étapes avec retour arrière, critères d'arrêt.

*3. Préparation sans effet visible.* Dans l'ordre :
1. `host_vars/gw01/routeur_reseau.yml` : `routeur_reseau_suffixe: 2` et `routeur_reseau_vip_statique` = les neuf VLAN. Premier passage avec `-e ansible_host=10.10.10.1` (la `.2` n'existe pas encore). Le script à chaud **ajoute** `.2` en secondaire partout ; `.1` reste l'adresse principale de chaque sous-réseau. `promote_secondaries` est posé par le même rôle (vérifie-le : `sysctl net.ipv4.conf.all.promote_secondaries`).
2. NetBox : adresse principale de `gw01` → 10.10.10.2 (et ses neuf `.2`), puis `medictl dns sync` (`gw01` est hors IaC : son nom vient de NetBox, M06-E15) ; `gw01.par1.medisphere.internal` → 10.10.10.2. [`netbox-bordure.yml`](fichiers/M07-E25/ansible/playbooks/netbox-bordure.yml) crée les neuf groupes FHRP, les VIP de rôle `vrrp` et les rattachements (permissions de `svc-automatisation` à étendre aux groupes FHRP). Le certificat d'hôte SSH de `gw01` contient son **nom** : rien à refaire, `HostKeyAlias` le vérifie.
3. BGP : sur `leaf01`, 10.10.99.1 remplacé par 10.10.99.2 ; sur `gw01`, `update-source 10.10.99.2` (le `router-id` vaut 10.10.10.2 depuis E16 : rien à changer). La session se réinitialise une fois (annoncé).
4. Relais DHCP avec l'adresse propre (`dhcp-relay=10.10.99.2,…` sur `gw01`, `10.10.99.3` sur `gw02`, qui relaie désormais aussi). Kea choisit le sous-réseau 99 d'après le `giaddr` et annonce toujours 10.10.99.1 comme routeur.
5. NTP : `base_ntp_serveurs` = `.2` et `.3` du VLAN de l'hôte ; certificats NTS réémis avec les `.2` (`gw01`) — plus aucun certificat ne porte une VIP, qu'aucune passerelle de secours ne pourrait prouver au défi HTTP-01.
6. Matrice : VRRP (protocole 112) entre `.2` et `.3` sur chaque sous-interface, appliqué aux deux passerelles.

*4. Les rôles.* `keepalived` rend une instance par VLAN **présent dans `keepalived_vlans_vrrp` de l'hôte** (champ `actif`), toutes à l'état initial `BACKUP`, sans préemption (`preemption: false` → `nopreempt`), unicast, VRRP v3, dans le groupe `BORDURE` qui suit `ens18` et `ens19` et appelle `bordure-transition` **en root** (`notify "…" root` : les scripts d'instance, eux, restent sous `keepalived_script`, M07-E08). Le rendu est validé par `keepalived -t -f %s` (qui vérifie aussi que les interfaces et les scripts existent) et le gestionnaire **recharge** (SIGHUP), jamais ne redémarre. `bordure` pose le script, `/etc/bordure/transition.conf`, et `/run/bordure`.

*5-6. Migration d'un VLAN.* Une MR par VLAN (V retiré de `routeur_reseau_vip_statique`, ajouté à `keepalived_vlans_vrrp` des **deux** passerelles), puis le job manuel `migration-vrrp` (`-e vlan=V`). Le playbook vérifie la situation de départ, rend les fichiers de `gw01`, enchaîne **dans la même commande** le retrait de `.1` et le rechargement de keepalived, attend la VIP (15 s au plus, retour arrière automatique sinon), puis ajoute l'instance sur `gw02` et vérifie qu'elle reste `BACKUP`.

```
vm-sbx$ sudo ping -D -i 0.1 10.10.20.10          # pendant la migration du VLAN 99
… icmp_seq=212 …  puis 35 paquets perdus  … icmp_seq=248 …   → ≈ 3,5 s
vm-sbx$ ip neigh show 10.10.99.1                   # même lladdr qu'avant : celle de ens19 de gw01
admin@gw01:~$ ip -br -4 address show dev ens19.99
ens19.99@ens19   UP   10.10.99.2/24 10.10.99.1/24
admin@gw02:~$ sudo journalctl -u keepalived --since -2min | grep VLAN99
… (VLAN99) Entering BACKUP STATE (init)
```

Pourquoi ne pas laisser keepalived « reprendre » la `.1` déjà présente ? Deux propriétaires pour une même adresse (ifupdown et keepalived) : au premier passage en `BACKUP`, keepalived retirerait une adresse qu'il n'a pas posée, et son comportement quand l'adresse existe déjà n'est pas documenté comme garanti. Une coupure de 3,5 s, annoncée et mesurée, vaut mieux qu'un comportement supposé.

*7. Ce qu'il ne faut pas faire* (VLAN 99 sur `gw02`, les autres sur `gw01`) :
- SSH `adm01` → VM du VLAN 99 : la requête passe par `gw01` (VIP du VLAN 10) qui la remet directement sur le VLAN 99 ; la réponse remonte par `gw02` (VIP 99) vers le VLAN 10. `gw01` ne voit que l'aller, `gw02` que le retour. Avec `nf_conntrack_tcp_loose=1`, `gw02` crée une entrée « reprise » sur le premier paquet de réponse et la règle « bastion MGMT » ne s'applique pas dans ce sens… le flux tient **ou non** selon les règles et le protocole : c'est précisément ce qui le rend dangereux. `conntrack -L -d 10.10.99.<X>` sur les deux passerelles montre deux demi-flux.
- Sortie Internet de la VM : aller par `gw02` (traduit vers `<IP-GW02-WAN>` à ce stade), retour vers `<IP-GW02-WAN>` : **symétrique**, ça marche. Le groupe de synchronisation existe pour que la situation « VLAN 99 sur une passerelle, le reste sur l'autre » n'arrive jamais en dehors d'une migration.

*8. La bascule complète.* Tous les VLAN migrés, `systemctl stop keepalived` sur `gw01` : ≈ 0,6 s de perte pour les flux internes et Internet (annonce de priorité 0), les sessions internes survivent (reprise par `nf_conntrack_tcp_loose=1`), les flux traduits par `gw01` (adresse `<IP-GW01-WAN>`) sont perdus. `adm01` → `pve01` ne revient pas : `pve01` route le lab vers `<IP-GW01-WAN>`, `gw01` reçoit la réponse, n'a jamais vu la question (elle est passée par `gw02`) : demi-flux, rejet. **E26** déplace la route de `pve01` vers une VIP WAN. Retour par RB-071 : arrêt de keepalived sur `gw02`, puis redémarrage (`nopreempt`).

**Explications**

VRRP élit, par lien, un maître qui répond aux requêtes ARP pour la VIP et la porte comme adresse secondaire ; les clients ne connaissent que la VIP et la MAC qui leur est annoncée (ARP gratuit à chaque prise de fonction). keepalived met en œuvre la machine à états (`INIT` → `BACKUP` → `MASTER`, `FAULT` si une interface suivie tombe). L'unicast remplace le multicast 224.0.0.18 : utile quand le réseau filtre le multicast, et plus facile à filtrer finement (une source par lien). Le groupe de synchronisation fait des neuf (dix avec le WAN) élections une seule décision : sans lui, une perte d'annonces sur un seul VLAN répartirait les VIP entre les deux passerelles, et tout flux entre deux VLAN serait asymétrique.

**Alternatives**
- **Préemption** (gw01 reprend dès son retour, éventuellement après `preempt_delay`) : un état nominal toujours le même (plus simple à superviser), au prix d'une seconde coupure par incident, parfois au pire moment (passerelle qui revient à moitié). Défendable si l'on veut que `gw02` ne soit **jamais** active longtemps (par exemple si elle était plus petite).
- **VMAC** (`use_vmac`) : la VIP a sa propre MAC (00:00:5e:00:01:VRID), qui bouge avec elle ; plus besoin que les clients rafraîchissent leur ARP. Coût : une interface macvlan par instance, et l'unicast exige des précautions (note de la documentation).
- **Un VRID par VLAN mais une seule instance par passerelle** (`virtual_ipaddress` sur plusieurs interfaces) : moins d'annonces, mais une perte de lien sur un VLAN n'est plus détectée par VLAN.
- **Relais DHCP sur le maître seulement** (démarré par le script de transition) : évite les doubles offres de Kea ; ajoute une dépendance au script.

**Pièges classiques**
- `vrrp_strict` : refuse l'unicast et ajoute ses propres règles de filtrage.
- `nopreempt` avec `state MASTER` : ignoré (la documentation l'exige en `BACKUP`).
- VRRP non autorisé dans nftables d'une seule passerelle : cerveau divisé immédiat dès que l'instance existe des deux côtés.
- Supprimer `.1` sans `promote_secondaries` : `.2` disparaît avec elle, la passerelle perd le VLAN.
- Laisser un outil (Ansible, voisin BGP, supervision) viser `.1` : il atteint « une » passerelle, pas celle qu'il croit.
- `keepalived` redémarré (au lieu de rechargé) par un gestionnaire : toutes les VIP tombent à chaque changement.
- Tester la bascule avant la fin de la migration (étape 7).

**En production chez MédiSphère**
La fiche CHG-855 passerait en comité de changement, avec une fenêtre annoncée aux équipes ; la migration se ferait de nuit et la supervision de la redondance (E29) serait en place **avant** le changement, pas après.

---

### M07-E26 — Bordure redondante côté WAN et VPN

**Solution** (une solution possible ; l'exercice est libre)

Fichiers : le rôle [`wireguard`](fichiers/M07-E18/ansible/roles/wireguard/) de M07-E18 ne change pas (il prévoit déjà `pilotage: transition`) ; inventaire : [`group_vars/role_routeur/wireguard.yml`](fichiers/M07-E26/ansible/inventories/lab/group_vars/role_routeur/wireguard.yml), [extrait Vault](fichiers/M07-E26/ansible/inventories/lab/group_vars/role_routeur/vault-critique.yml.extrait), [instance WAN](fichiers/M07-E26/ansible/inventories/lab/group_vars/role_routeur/keepalived-wan.yml.extrait) et [variables d'hôte](fichiers/M07-E26/ansible/inventories/lab/host_vars/gw01/bordure-wan.yml.extrait), [extrait de la matrice](fichiers/M07-E26/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; hors lab : [`pve01`](fichiers/M07-E26/pve01/interfaces.extrait), [`pbs01`](fichiers/M07-E26/pbs01/wg0-et-nftables.extrait), [poste](fichiers/M07-E26/poste/wg1-poste.extrait) ; [CHG-856](fichiers/M07-E26/medisphere/docs/socle/changements/CHG-856-bordure-wan-vpn.md), [RB-071](fichiers/M07-E26/medisphere/docs/socle/runbooks/RB-071-bascule-bordure.md).

Points clés de la solution :
- **VIP WAN** : instance `WAN` (VRID 250, `ens18`, unicast entre les adresses WAN propres) dans le groupe `BORDURE`. Même méthode qu'un VLAN : `gw01` d'abord, puis `gw02`. Ici aucune `.1` statique à retirer : la VIP est une adresse **nouvelle**, la prise de fonction ne coupe rien.
- **Traduction sortante vers la VIP** (`snat to $GW_WAN_VIP`) au lieu de `masquerade` : l'adresse de sortie du lab ne dépend plus de la passerelle active. Avec `masquerade`, une entrée synchronisée par `conntrackd` (E27) porterait l'adresse de `gw01`, que `gw02` n'a pas : les réponses d'Internet iraient à `gw01`. Avec la VIP, la même entrée est valable des deux côtés.
- **Tunnels** : les trois fichiers `wg-quick` sont identiques sur les deux passerelles (mêmes clés, reprises de `gw01` en Vault `critique`) ; les unités `wg-quick@` sont **désactivées** au démarrage ; `bordure-transition` les démarre en devenant `MASTER` et les arrête en `BACKUP`/`FAULT`. `wg syncconf` (gestionnaire du rôle) applique un changement de pair sans démonter un tunnel actif.
- **Adresse source des tunnels** : une passerelle qui *répond* à un pair le fait depuis l'adresse de réception (la VIP) ; une passerelle qui *initie* (nouveau maître après une bascule) part de son adresse propre. Deux règles `snat` dans `postrouting` (paquets émis localement, ports 51820-51822) fixent la source : VIP WAN pour `wg0`/`wg1`, VIP 10.10.99.1 pour `wg2`. Après leur ajout, purger les entrées conntrack existantes de ces flux UDP (`conntrack -D -p udp --orig-port-src 51820`), sinon l'ancienne traduction (aucune) persiste tant que le flux vit.
- **Extérieur** : `pve01` (`ip route replace … via <IP-GW-WAN-VIP>`, puis persistance), `pbs01` (nft accepte la VIP, extrémité `wg0` = VIP, puis restriction à la VIP seule), poste (extrémité `wg1` = VIP), redirection 443 sur la VIP.
- **Lyon** : FRR identique sur les deux passerelles ; le voisin 10.255.2.2 n'est joignable que sur le maître (interface `wg2`) ; après une bascule, `lyo-gw01` détecte la session morte (*hold time*), le tunnel reprend à la première poignée de main, la session BGP se rétablit. Le *hold time* par défaut (180 s) donne une reprise lente : réduit à 30 s dans E19 ou ici (`timers bgp 10 30` sur le voisin, des deux côtés), justifié.

```
admin@gw02:~$ cat /run/bordure/etat ; ip -br link | grep wg            # BACKUP ; aucun wg
admin@gw01:~$ ip -br link | grep wg                                    # wg0 wg1 wg2
admin@gw01:~$ for i in wg0 wg1 wg2; do sudo wg show $i public-key; done
admin@gw02:~$ for i in wg0 wg1 wg2; do sudo awk '/PrivateKey/ {print $3}' /etc/wireguard/$i.conf | wg pubkey; done   # identiques
vm-sbx$ curl -s https://ifconfig.me                                    # <IP-GW-WAN-VIP>
root@pve01:~# ip route get 10.10.10.10                                 # via <IP-GW-WAN-VIP>
admin@gw01:~$ sudo conntrack -L -p udp --orig-port-src 51820           # … src=<IP-GW01-WAN> … reply … dst=<IP-GW-WAN-VIP>
```

**Explications**

Tout ce qui « est » la bordure pour l'extérieur doit être une **identité** qui suit le maître : une adresse (VIP), une clé (WireGuard), une adresse de traduction. Ce qui est propre à une passerelle (adresse WAN propre, accès SSH de secours) ne doit être utilisé que pour administrer cette passerelle-là. WireGuard n'a pas d'état de connexion côté serveur au sens TCP : un nouveau maître avec la même clé privée et la même liste de pairs reprend après une poignée de main ; le *roaming* permet au pair de suivre une nouvelle adresse source **authentifiée**, mais le pare-feu du pair (`pbs01`) filtre avant WireGuard : d'où la maîtrise de l'adresse source.

**Alternatives**
- Accepter les deux adresses WAN propres (et la VIP) côté `pbs01` sans traduction des tunnels : plus simple, mais le pair « voit » la bordure sous trois identités, et une erreur de traduction passe inaperçue.
- Tunnels actifs sur les deux passerelles, avec des clés différentes et deux pairs côté PAR2 : pas de dépendance au script de transition, mais routage à piloter (deux chemins vers 10.20.0.0/16, métriques ou BGP au-dessus de WireGuard). Plus robuste, plus complexe : piste pour le PRA (F5).
- `wg2` hors VRRP, avec BGP de Lyon vers les **deux** passerelles (deux tunnels, deux sessions) : la vraie bonne réponse pour un site distant en production ; ici, une seule extrémité côté LYO1 a été conservée par simplicité.

**Pièges classiques**
- Unités `wg-quick@` laissées `enabled` : au démarrage, la passerelle de secours monte `wg0` et capte le tunnel.
- Clés générées sur `gw02` (nouvelle identité) : il faudrait reconfigurer tous les pairs.
- Clé privée copiée en clair (ticket, `scp` vers `/tmp`, sortie Ansible sans `no_log`).
- Traduction ajoutée sans purger les entrées conntrack existantes : « ça ne change rien » jusqu'au prochain redémarrage.
- Route de `pve01` changée en supprimant puis en ajoutant (coupure d'`adm01` → `pve01` entre les deux commandes) au lieu de `replace`.
- VIP WAN hors du groupe de synchronisation : la traduction vers la VIP ne vaut plus rien quand la VIP n'est pas sur la passerelle qui traduit.

**En production chez MédiSphère**
Deux accès Internet (deux opérateurs) et une adresse publique par passerelle, BGP avec les opérateurs ou suivi de la joignabilité amont (`track_script`) ; rotation des clés WireGuard planifiée (M25) ; journalisation des transitions envoyée à la supervision centrale (M22).

---

### M07-E27 — Basculer sans couper les connexions : conntrackd

**Solution**

Fichiers : rôle [`conntrackd`](fichiers/M07-E27/ansible/roles/conntrackd/) et son scénario Molecule [`molecule/conntrackd/`](fichiers/M07-E27/ansible/molecule/conntrackd/) (deux instances 2048-2049 ; l'état complet envoyé par l'une doit arriver dans le cache externe de l'autre) ; [`group_vars/role_routeur/conntrackd.yml`](fichiers/M07-E27/ansible/inventories/lab/group_vars/role_routeur/conntrackd.yml) (lien, adresses ignorées, `bordure_conntrackd`, décision `nf_conntrack_tcp_loose=0`) ; [extrait de la matrice](fichiers/M07-E27/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; [`playbooks/routeurs.yml`](fichiers/M07-E27/ansible/playbooks/routeurs.yml) (version finale, la passerelle de secours d'abord) ; le script `bordure-transition` de E25 contient déjà la partie `conntrackd` (activée par `BORDURE_CONNTRACKD=1`).

*1. Le problème, mesuré* (ordres de grandeur ; tes chiffres vont dans `bascules.md`) :

| Flux | `tcp_loose=1` sans `conntrackd` | `tcp_loose=0` sans `conntrackd` |
|---|---|---|
| SSH `adm01` → VM 99 | survit : `gw02` « reprend » la connexion au premier paquet vu, la règle MGMT → lab l'accepte | coupée : le paquet n'est ni `new` (pas un SYN) ni connu → `invalid` → rejeté |
| Téléchargement traduit | souvent coupé ou très ralenti : les paquets du serveur arrivent les premiers, à destination de la VIP, sans entrée de traduction : la chaîne `input` les rejette ; la reprise ne se fait que si le client émet | coupé |
| HTTPS redirigé depuis le LAN maison | même sort : la redirection (DNAT) n'existe que pour les connexions vues naître | coupé |

`conntrack -E` sur `gw02` pendant la bascule montre les `[NEW]` des connexions reprises (`tcp_loose=1`) ; `conntrack -L` montre qu'elles n'ont pas de traduction.

*2. Lecture.* FTFW : protocole fiable (numéros de séquence, acquittements, retransmissions) : le choix par défaut. ALARM : renvoie périodiquement tout l'état (plus de bande passante, moins de perte). NOTRACK : sans fiabilité, pour des liens sûrs. Cache **interne** : les connexions du nœud ; cache **externe** : celles reçues du pair, gardées hors noyau jusqu'à la prise de fonction. Script (`primary-backup.sh`) : en devenant maître, `-c` injecte le cache externe dans le noyau, `-f` vide les caches, `-R` resynchronise le cache interne sur le noyau, `-B` envoie tout au pair ; en devenant secours, `-t` programme la purge des entrées du noyau (devenues fausses) après `PurgeTimeout`, `-n` demande l'état complet au maître. `Address Ignore` écarte les connexions **de la passerelle elle-même** (adresses propres, boucle locale) ; on n'y met pas les VIP, puisque les flux traduits vers la VIP WAN et redirigés vers 10.10.70.200 sont ceux qu'on veut garder.

*3-4. Le rôle et la preuve.*

```
admin@gw01:~$ sudo conntrackd -s | sed -n '1,30p'     # « multicast/UDP traffic » : bytes sent qui augmentent
admin@gw02:~$ sudo conntrackd -e | grep 'dport=443' | head   # flux du maître dans le cache externe
admin@gw02:~$ sudo conntrackd -e | grep -c "src=10.10.99"     # non nul pendant du trafic du VLAN 99
```

Avec `conntrackd` et `tcp_loose=0`, les trois flux survivent à une bascule planifiée (perte ≈ 0,6 s, retransmissions TCP) et à une panne franche (≈ 3,6 s), à condition que l'entrée ait été synchronisée avant la panne (une connexion ouverte dans la dernière fraction de seconde peut être perdue).

*5. Décision* : `nf_conntrack_tcp_loose=0`. Avec la synchronisation, la reprise n'apporte rien et elle permet à un paquet TCP forgé au milieu d'un flux de créer un état ; sans synchronisation (panne de `conntrackd`), les connexions tomberaient : risque accepté parce que supervisé (E29) et vérifié avant chaque bascule planifiée (RB-071 §1).

**Explications**

Un pare-feu à états et une traduction d'adresses vivent de leur table de suivi : elle dit qu'un paquet appartient à une connexion autorisée et comment le retraduire. Une passerelle qui prend la main sans cette table voit des paquets « orphelins ». `conntrackd` écoute les événements du noyau (netlink), les transmet au pair, qui les garde prêts. Le coût : un flux de synchronisation proportionnel au nombre de connexions créées et fermées, et une phase de validation au moment de la bascule.

**Alternatives**
- Pas de synchronisation, `tcp_loose=1` : acceptable pour un lab ou un trafic surtout interne et court ; les flux traduits restent fragiles.
- Lien de synchronisation dédié (VLAN propre ou carte directe) : la recommandation habituelle ; découple la synchronisation du trafic d'administration.
- `DisableExternalCache` : les entrées vont directement dans le noyau du secours ; bascule plus simple, mémoire noyau consommée en permanence ; la documentation recommande plutôt les scripts.

**Pièges classiques**
- `conntrackd -c` appelé en devenant `BACKUP` : injection d'un état faux sur le secours.
- Les VIP dans `Address Ignore` : on n'y synchronise plus les flux traduits, et on ne s'en aperçoit qu'à la bascule.
- UDP 3780 autorisé dans un seul sens.
- Mesurer la survie des connexions sans connaître `nf_conntrack_tcp_loose` : on attribue à `conntrackd` ce que fait la reprise.

**En production chez MédiSphère**
Lien dédié, supervision des compteurs de `conntrackd -s` (erreurs, files) exportés en métriques (M21), et test de bascule sous charge (M29).

---

### M07-E28 — HAProxy en production

**Solution**

Fichiers : rôle [`haproxy`](fichiers/M07-E28/ansible/roles/haproxy/) (celui de M07-E10, `global` et `defaults` de production : [gabarit](fichiers/M07-E28/ansible/roles/haproxy/templates/haproxy.cfg.j2), [variables ajoutées](fichiers/M07-E28/ansible/roles/haproxy/defaults/main.yml), [tâches](fichiers/M07-E28/ansible/roles/haproxy/tasks/main.yml), [page 503](fichiers/M07-E28/ansible/roles/haproxy/files/503-medisphere.http)) ; [`group_vars/role_lb/haproxy.yml`](fichiers/M07-E28/ansible/inventories/lab/group_vars/role_lb/haproxy.yml) (remplace la version de M07-E13) ; [extrait Vault](fichiers/M07-E28/ansible/inventories/lab/group_vars/role_lb/vault-critique.yml.extrait).

*1. État des lieux* :

```
admin@adm01:~$ nmap --script ssl-enum-ciphers -p 443 10.10.70.200        # versions et suites, notées A à F
admin@adm01:~$ curl -sI https://gitlab.par1.medisphere.internal/users/sign_in | grep -iE 'strict|server|x-powered'
admin@adm01:~$ curl -sI http://gitlab.par1.medisphere.internal/
admin@adm01:~$ curl -s -m 5 https://10.10.70.10:8404/stats ; echo $?    # rien n'écoute : l'écoute est en 127.0.0.1
```

Le piège de l'étape : `openssl s_client -tls1` répond « refusé »… parce qu'OpenSSL 3 de Debian 13 refuse lui-même TLS 1.0 à son niveau de sécurité par défaut. `nmap` embarque sa propre énumération ; `openssl s_client -cipher 'DEFAULT:@SECLEVEL=0' -tls1` aussi.

*2. TLS et en-têtes* : dans le gabarit du rôle, `ssl-default-bind-ciphers` / `ssl-default-bind-ciphersuites` (profil « intermediate ») et `prefer-client-ciphers ssl-min-ver TLSv1.2 no-tls-tickets`, mêmes suites côté serveurs ; dans `fe_publication`, `http-response set-header Strict-Transport-Security "max-age=31536000"` (sans `includeSubDomains` ni `preload` : d'autres noms de `par1` ne sont pas en HTTPS, et un nom interne n'a rien à faire dans la liste des navigateurs), `del-header Server` et `X-Powered-By`.

*3. Santé* : les contrôles de M07-E13 restent (`/-/readiness` autorisé aux adresses propres des répartiteurs par `monitoring_whitelist` de `git01`, `/login/` de NetBox, `check-sni`, `verify required`). On ajoute `observe layer7 error-limit 10 on-error mark-down` : dix erreurs 5xx consécutives de vraies requêtes retirent le serveur, sans attendre `fall 3` × `inter 5s`. `gitlab-ctl stop puma` : le serveur passe `DOWN` en quelques secondes (dès les premières requêtes, ou au troisième contrôle), `be_gitlab` n'a plus de serveur, HAProxy sert la page de `errorfile 503` ; `gitlab-ctl start puma`, retour `UP` après `rise 2`.

*4. Journaux* : `log-format` = format HTTP de la documentation suivi de `id=%ID` (dans `defaults`, pour tous les frontends) ; `unique-id-format %{+X}o\ %ci:%cp_%fi:%fp_%Ts_%rt:%pid` et `unique-id-header X-Request-ID` dans `fe_publication`.

```
admin@lb01:~$ sudo journalctl -u haproxy --since -2min -o cat | grep 'GET /login/' | tail -n 1   # … id=0A0A0A0A:…
admin@nbx01:~$ sudo grep '<ID>' /var/log/nginx/access.log    # si le format nginx journalise $http_x_request_id
```

(Le format d'accès de nginx sur `nbx01` doit inclure `$http_x_request_id` pour fermer la boucle : petite modification du rôle `netbox`.)

*5. Administration* : section `fe_stats` (`tls: true` : rendue quand le certificat `lb` existe) sur `{{ lb_adresse }}:8404`, `deny` hors 10.10.10.0/24, `http-request auth` sur la liste `utilisateurs_stats` (empreintes `$6$…` en Vault `critique`, rendues par le gabarit), `/metrics` par `use-service prometheus-exporter`, `stats admin` au seul groupe `admins`. L'ancienne section `stats` en 127.0.0.1 disparaît. Socket : `mode 660 level admin expose-fd listeners`. Flux : la règle « bastion (MGMT) vers tout le lab » couvre déjà MGMT → DMZ ; le filtrage local des répartiteurs (M07-E30) l'ouvrira explicitement.

```
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://lb01.par1.medisphere.internal:8404/stats     # 401
admin@adm01:~$ ( set -a; . ~/.config/workbook/haproxy-stats.env; set +a
                  curl -s -K - 'https://lb01.par1.medisphere.internal:8404/stats;csv' \
                    <<<"user = \"$HAPROXY_STATS_USER:$HAPROXY_STATS_PASSWORD\"" | head -3 )
admin@runner01:~$ curl -s -m 5 -o /dev/null -w '%{http_code}\n' https://lb01.par1.medisphere.internal:8404/stats   # 403
```

(Les identifiants sont lus dans un fichier 600 et passés à `curl` par l'entrée standard, jamais en argument.)

*6. Exploitation sans coupure* :

```
admin@adm01:~$ for i in $(seq 600); do curl -s -o /dev/null -w '%{http_code}\n' https://netbox.par1.medisphere.internal/login/; sleep 0.1; done | sort | uniq -c &
admin@lb01:~$ sudo systemctl reload haproxy           # pendant la boucle : 600 × 200 attendus
admin@lb01:~$ echo "set server be_netbox/nbx01 state drain" | sudo socat stdio /run/haproxy/admin.sock
admin@lb01:~$ echo "show servers state be_netbox" | sudo socat stdio /run/haproxy/admin.sock
admin@lb01:~$ echo "set server be_netbox/nbx01 state ready" | sudo socat stdio /run/haproxy/admin.sock
```

`drain` : plus de nouvelles connexions **réparties**, `maint` : plus rien ; avec un seul serveur par section, les deux équivalent à une indisponibilité : c'est pour la maintenance d'un serveur **parmi plusieurs** (E34). L'arrêt de HAProxy sur le répartiteur actif fait partir la VIP par `chk_haproxy` (M07-E12).

*7. Limitation* : `stick-table type ip size 100k expire 30s store http_req_rate(10s)`, `track-sc0 src` sur les seuls chemins de connexion, `deny deny_status 429` au-delà de 20. Vingt-cinq requêtes de suite sur `/login/` : les dernières répondent `429` ; `/api/status/` reste servi.

**Explications**

Le répartiteur est le premier point que voit un attaquant et le dernier que voit l'astreinte : sa configuration porte la politique TLS de l'entreprise, ses contrôles décident si un service est « en vie », ses journaux sont la seule trace commune d'une requête. Les contrôles périodiques détectent un serveur mort en `fall` × `inter` ; l'observation du trafic réel (`observe layer7`) détecte un serveur qui répond mal **entre** deux contrôles. Le mode maître-processus de HAProxy permet un rechargement qui transmet les sockets d'écoute (`expose-fd listeners`) : aucune connexion refusée, les anciennes connexions finissent sur l'ancien processus (au plus `hard-stop-after`).

**Alternatives**
- Nginx comme répartiteur (M07-E11) : configuration plus familière, contrôles de santé actifs réservés à la version commerciale.
- Statistiques sur la VIP plutôt que sur l'adresse propre : on ne voit que le répartiteur actif ; or c'est le **secours** dont on veut savoir s'il est prêt.
- Journal vers un collecteur syslog distant : attendra le module 22.

**Pièges classiques**
- Conclure « TLS 1.0 refusé » d'après un client qui ne sait plus le parler.
- Mots de passe des statistiques en `insecure-password`, ou dans `group_vars` en clair.
- `on-error mark-down` sans `error-limit` raisonnable : une rafale d'erreurs applicatives légitimes (404 ne comptent pas, 5xx oui) retire le seul serveur.
- `stats admin` ouvert à tout compte authentifié (la supervision pourrait mettre un serveur en maintenance).
- `systemctl restart haproxy` au lieu de `reload`.

**En production chez MédiSphère**
Journaux et métriques envoyés à la plateforme d'observabilité (M21, M22), configuration testée en CI (`haproxy -c` dans le pipeline du rôle), et un WAF ou une limitation plus fine par chemin pour les applications exposées.

---

### M07-E29 — Superviser la bordure et les répartiteurs

**Solution**

Fichiers : rôle [`sonde_reseau`](fichiers/M07-E29/ansible/roles/sonde_reseau/) (compte, clé à commande forcée, `sudo` restreint, script [`etat-reseau`](fichiers/M07-E29/ansible/roles/sonde_reseau/files/etat-reseau)) ; inventaire : [clé publique](fichiers/M07-E29/ansible/inventories/lab/group_vars/all/sonde_reseau.yml), [extrait `ssh_durci`](fichiers/M07-E29/ansible/inventories/lab/group_vars/all/ssh_durci.yml.extrait) ; dans `plateforme/outils` : [`bin/ms-verif-reseau`](fichiers/M07-E29/outils/bin/ms-verif-reseau), [`etc/ms-verif-reseau.conf`](fichiers/M07-E29/outils/etc/ms-verif-reseau.conf), [tests bats](fichiers/M07-E29/outils/tests/bats/ms-verif-reseau.bats) et leurs [données](fichiers/M07-E29/outils/tests/bats/donnees/nominal/), [unités systemd](fichiers/M07-E29/outils/systemd/), [extrait du guide d'astreinte](fichiers/M07-E29/outils/docs/astreinte-extrait.md).

*1. L'accès.* Clé ed25519 sans phrase de passe (la sonde tourne seule), dans `~/.config/workbook/ssh-supervision-reseau` (600) ; côté hôtes, `authorized_keys` : `restrict,from="10.10.10.10",command="sudo -n /usr/local/sbin/etat-reseau" ssh-ed25519 …` ; `sudoers` : `supervision ALL=(root) NOPASSWD: /usr/local/sbin/etat-reseau ""`. Preuve :

```
admin@adm01:~$ ssh -i ~/.config/workbook/ssh-supervision-reseau supervision@gw01.par1.medisphere.internal id | jq .hote
"gw01"
admin@adm01:~$ ssh -i ~/.config/workbook/ssh-supervision-reseau -t supervision@gw01.par1.medisphere.internal   # pas de terminal
```

`etat-reseau` publie ce que la sonde a besoin de **constater**, pas de déduire : adresses portées (`ip -j address`), état du groupe (`/run/bordure/etat`), sessions BGP (`vtysh … json`), poignées de main (`wg show all latest-handshakes`), serveurs HAProxy (`show stat` sur le socket), état de `conntrackd`.

*2-3. La sonde et ses unités.* `ms-verif-reseau` lit l'état des quatre hôtes, puis vérifie : un seul porteur par VIP, toutes les VIP de la bordure sur le même, `keepalived` actif et un seul `MASTER`, sessions BGP attendues (sur les deux passerelles, ou sur le maître seulement pour Lyon), voisins configurés tombés depuis plus de 10 minutes (sauf désactivés « Admin »), poignées de main `wg0`/`wg2` du maître de moins de 180 s, `conntrackd` actif, serveurs `UP`, services publiés de bout en bout. Les tests bats rejouent les cas du ticket à partir d'états JSON simulés (`MS_ETAT_DIR`) : aucun accès réseau dans la CI. Timer `*:0/5`, `Persistent=true`.

*4. Le rouge* (un à la fois, retour à l'état nominal entre chaque) : `systemctl stop keepalived` sur la passerelle de secours → `vrrp … keepalived actif=false (plus de redondance)` ; `systemctl stop conntrackd` sur la secours → `conntrackd … false` ; `set server be_netbox/nbx01 state maint` sur `lb02` → `haproxy … MAINT` ; `wg0` : arrêt de l'interface **sur `pbs01`** (`wg-quick down wg0`, hors fenêtre de sauvegarde) 10 minutes → `wireguard … poignée de main` ; `neighbor 10.10.99.251 shutdown` sur `leaf01` → `bgp … session … Idle`. Pour chacun, `journalctl -t ms-alerte` montre l'alerte.

*5. Module 21* : `--prometheus /var/lib/ms-verif/reseau.prom` écrit atomiquement (`mv`) des mesures `ms_reseau_*` (`vip_porteurs`, `bordure_maitre`, `bgp_etabli`, `wireguard_age_secondes`, `haproxy_serveur_up`, `anomalies`, `derniere_execution_timestamp_seconds`) ; node_exporter les lira par son *textfile collector*.

**Explications**

Superviser une redondance, c'est vérifier une **relation** entre deux nœuds (exactement un maître, et l'autre prêt), pas l'état de chacun : deux passerelles « vertes » peuvent former un cerveau divisé. La commande forcée transforme une clé SSH en appel de procédure à distance : même volée, elle ne donne qu'un état réseau, depuis `adm01` seulement.

**Alternatives**
- SNMP (keepalived sait exposer une MIB VRRP) : standard pour les équipements réseau, peu outillé ici.
- node_exporter + exporteurs (keepalived_exporter, FRR, HAProxy natif) dès maintenant : c'est la cible du module 21 ; la sonde actuelle sert de pont et de contrôle « vu de l'extérieur ».
- Utiliser le compte `admin` et la clé de l'humain : la sonde dépendrait d'un certificat SSH de 16 h et d'un agent.

**Pièges classiques**
- `command=` sans `restrict` : redirections de ports et agent restent possibles.
- Règle `sudo` sans `""` final : arguments arbitraires.
- Une sonde qui déclare « OK » quand elle n'a rien pu lire.
- Alerter sur Lyon « tombé » sur la passerelle de secours (normal : `wg2` n'y existe pas).

**En production chez MédiSphère**
Ces contrôles deviennent des règles d'alerte Prometheus (M21) avec des seuils de durée, et le cerveau divisé une alerte de priorité maximale qui réveille l'astreinte.

---

### M07-E30 — La matrice des flux v2

**Solution**

Fichiers : [matrice v2 complète](fichiers/M07-E30/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml) ; [filtrage local des répartiteurs](fichiers/M07-E30/ansible/inventories/lab/group_vars/role_lb/pare_feu_local.yml) ; [job de CI](fichiers/M07-E30/ansible/gitlab-ci-matrice.yml.extrait) ; dans `plateforme/outils` : [`bin/ms-matrice-flux`](fichiers/M07-E30/outils/bin/ms-matrice-flux) et [ses tests](fichiers/M07-E30/outils/tests/bats/ms-matrice-flux.bats) ; [document généré](fichiers/M07-E30/medisphere/docs/socle/matrice-flux.md).

*1. Relecture* — changements de la v2 par rapport à la matrice de M06-E30 :
- retirées : « `adm01` vers `hp01` par le LAN (transition avant tunnel) » (M00-E20, plus utilisée depuis le tunnel) et « `pve01` vers les VMs (vérifications avant M00-E15) » (les checks tournent depuis `adm01`) ;
- resserrées : SSH de `runner01` (vers l'adresse INFRA de la passerelle, M07-E24) ; DNS (sources explicites, Lyon ajouté) ; les deux règles Packer fusionnées ;
- réécrites pour deux passerelles : réponses Kea (sans destination), traduction vers la VIP WAN, redirection sur la VIP WAN ;
- ajoutées, avec leur exercice : VRRP par lien (10 règles), `conntrackd`, BGP (trois sources exactes : `leaf01`, le VLAN 40, `lyo-gw01` dans `wg2`), `wg2`, Lyon vers les services (ni MGMT ni le reste), répartiteurs vers `git01`/`nbx01` et `ca01`, défi ACME vers les répartiteurs, publication depuis le lab, le VPN, Lyon et le LAN maison, SSH de `runner01` vers les répartiteurs ;
- « bastion MGMT vers tout » étendu à `wg2` (diagnostic de Lyon depuis `adm01`), assumé.

*3. La DMZ* : `pare_feu_local` sur `lb02` (secours) puis, après bascule par RB-070, sur `lb01`. Le 80/443 doit accepter le LAN maison : la redirection ne traduit pas la source.

*4. La génération* : `ms-matrice-flux` (Python, PyYAML) produit un tableau par chaîne ; `--verifier` compare au document publié ; le job `matrice-a-jour` de `plateforme/ansible` lit la version publiée par l'API (jeton de projet en lecture, passé à `curl` par l'entrée standard) et échoue si elle diffère.

*5. La preuve* :

```
admin@runner01:~$ nmap -Pn -sT -p 22,53,179,3780,8404 10.10.20.2 10.10.20.3 10.10.70.10     # 179 et 3780 filtrés
vm-sbx$ nmap -Pn -sT -p 22,80,443,8404 10.10.70.10 10.10.70.11                               # 80, 443 ouverts ; 22, 8404 filtrés
root@pve01:~# nmap -Pn -sT -p 22,443 <IP-GW-WAN-VIP>                                         # 443 (redirigé) ; 22 : accès de secours
admin@lyo-pc01:~$ curl -sI https://netbox.par1.medisphere.internal/login/ ; nc -vz -w3 10.10.10.10 22   # 200 ; refusé
```

**Explications**

Une matrice qui grossit exercice après exercice accumule des règles provisoires que personne ne retire ; la relire d'un bloc, c'est se demander pour chaque ligne « qui en a besoin aujourd'hui ? ». Générer la documentation depuis le code supprime la seconde source de vérité ; la vérifier en CI empêche qu'elles divergent de nouveau.

**Alternatives**
- Documenter dans les commentaires du YAML seulement : moins lisible pour Sophie et pour l'auditeur.
- Objets nommés tirés de NetBox (adresses des hôtes) : une seule source pour les adresses, mais une dépendance de la bordure à NetBox au moment du rendu.

**Pièges classiques**
- Ouvrir BGP au VLAN 99 entier pour « faciliter » la maquette.
- Oublier que le filtrage local des répartiteurs voit les adresses du LAN maison.
- Générer le document à la main « une dernière fois ».

**En production chez MédiSphère**
La matrice serait revue tous les trimestres (registre des écarts, M26), chaque règle aurait un propriétaire et une date de fin pour les règles temporaires.

---

### M07-E31 — ADR : haute disponibilité de la bordure

**Modèle** : [`ADR-0070-haute-disponibilite-bordure.md`](fichiers/M07-E31/medisphere/docs/socle/adr/ADR-0070-haute-disponibilite-bordure.md).

**Explications**

L'ADR justifie une décision **déjà mise en œuvre** : il doit montrer que les alternatives ont été pesées sur les mêmes critères, et dire honnêtement ce que la solution ne couvre pas. Les deux critères qui départagent : le sort de l'**état** (connexions, traductions, tunnels) pendant la bascule, et le coût d'**exploitation** (ce qu'il faut savoir à 3 h du matin). L'actif-actif (ECMP, *anycast*) est supérieur pour un trafic sans état ; une bordure avec traduction et tunnels est un cas d'actif-passif.

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Contexte | le problème (PLAT-850) et les contraintes du lab (un hyperviseur, pas de commutateur) |
| Exigences | chiffrées : perte, connexions, reconfiguration des clients, exploitation |
| Options | au moins quatre, comparées sur les **mêmes** critères (tableau) |
| Décision | argumentée par des mesures du lab (E25, E27, E32) |
| Limites | `pve01`, box, LAN maison ; cerveau divisé sans *fencing* ; secrets dupliqués |
| Conséquences | négatives écrites, actions rattachées à un module (M09, M15, M21, M25, F5) |
| Révision | événement ou seuil qui rouvre la décision |
| Forme | gabarit MADR, deux pages au plus, sur `main` par MR |

**Pièges classiques** : un ADR « publicitaire » sans inconvénient ; des options factices (on n'en compare qu'une sérieusement) ; oublier que les deux passerelles sont sur le même hôte.

---

### M07-E32 — Tester et mesurer les bascules

**Solution** (plan de référence ; l'exercice est libre)

Fichiers : [`bascules.md`](fichiers/M07-E32/medisphere/docs/socle/tests/bascules.md) (modèle de compte rendu, ordres de grandeur attendus), outil [`ms-mesure-bascule`](fichiers/M07-E32/outils/bin/ms-mesure-bascule) (ping horodaté à 10 Hz, plus longue coupure calculée sur les numéros de séquence).

Déroulé type d'un scénario : (1) `ms-verif-reseau` vert ; (2) lancement des trois mesures (`ms-mesure-bascule`), de la session SSH et du téléchargement ; (3) action ; (4) attente de stabilisation (30 s) ; (5) arrêt des mesures, relevé ; (6) retour à l'état nominal (RB-071 §3), `ms-verif-reseau` vert. Les actions :

```
admin@gw01:~$ sudo systemctl stop keepalived                     # 1 — planifiée
admin@gw01:~$ sudo pkill -9 -x keepalived                        # 3 — plantage (systemd le relancera : noter quand)
root@pve01:~# qm stop 1000                                        # 4 — coupure de courant ; retour : qm start 1000
root@pve01:~# qm config 1000 | grep ^net1                         # 5 — relire la définition…
root@pve01:~# qm set 1000 --net1 'virtio=<MAC>,bridge=vmbr1,mtu=9000,link_down=1'   # …et la réécrire à l'identique + link_down
root@pve01:~# qm set 1000 --net1 'virtio=<MAC>,bridge=vmbr1,mtu=9000'               # retour
admin@gw02:~$ sudo nft insert rule inet filter input iifname "ens19.99" meta l4proto 112 drop comment '"TEST-E32"'   # 7
admin@gw02:~$ sudo nft -a list chain inet filter input | grep TEST-E32    # numéro de règle (handle) ; retrait :
admin@gw02:~$ sudo nft delete rule inet filter input handle <N>
```

`qm stop` est une coupure **brutale** de la VM ; elle ne touche ni `vmbr0` ni `vmbr1`. La règle de test n'est pas dans la matrice : le prochain passage du rôle `pare_feu` l'effacerait aussi (filet supplémentaire), mais on la retire soi-même, à la fin du scénario.

**Explications**

Chiffrer une bascule, c'est distinguer ce qui relève du protocole (*Master_Down_Interval*), de l'annonce de départ (priorité 0), de la détection de lien (`FAULT`) et des couches au-dessus (reprise de TCP, poignée de main WireGuard, *hold time* BGP). Les écarts entre scénarios s'expliquent par ces mécanismes ; un écart inexpliqué est un défaut à creuser avant de publier un objectif de niveau de service.

**Alternatives**
- Mesurer avec `iperf3` (débit pendant la bascule) en plus de l'ICMP : utile pour les transferts de PBS.
- Automatiser la campagne par un playbook (scénarios, mesures, retour) : la cible, pour la rejouer à chaque changement de la bordure (M29).

**Pièges classiques**
- Deux pannes à la fois (on ne sait plus attribuer les chiffres).
- Oublier le retour à l'état nominal entre deux scénarios (le scénario suivant part de `gw02` maître).
- `qm set --net1 link_down=1` sans recopier la MAC : nouvelle MAC, nouvelle interface pour l'invité, renommage possible.
- Laisser la règle `TEST-E32` en place.

**En production chez MédiSphère**
Une campagne par trimestre et après chaque changement majeur de la bordure, dans une fenêtre annoncée, résultats versés au dossier de continuité d'activité (F5).

---

### M07-E33 — Questions de production : réseau et HA

**Réponses argumentées**

1. **Extinction brutale** : `gw02` (priorité 100) attend *Master_Down_Interval* = 3 × 1 + (256 − 100)/256 ≈ **3,6 s** après la dernière annonce reçue ; la VIP est sans maître entre 3,6 s et 4,6 s selon le moment de la dernière annonce (au pire un intervalle de plus). **Arrêt propre** : keepalived envoie une annonce de priorité 0 ; le secours n'attend que son *Skew_Time* (≈ 0,6 s). La différence : le maître prévient, ou on attend de constater son silence.
2. **Réponse b.** La VIP bascule, mais la VM continue d'envoyer vers l'ancienne MAC tant que son entrée ARP n'est pas mise à jour : Linux met à jour une entrée **existante** à la réception d'un ARP gratuit, mais si la VM l'a manqué (perte, ARP gratuit envoyé avant que le lien soit prêt), elle attend que l'entrée passe en `STALE` puis soit revérifiée : quelques dizaines de secondes. Preuve : `ip neigh show 10.10.20.1` sur la VM pendant la bascule, `tcpdump -eni ens19.20 arp` sur `gw02`. Réglages : `vrrp_garp_master_repeat`/`garp_master_delay` (ARP gratuits répétés), `vrrp_garp_master_refresh` (rappel périodique), ou VMAC (`use_vmac`). (a) le DNS ne joue pas, la passerelle est une adresse ; (c) Lyon est sans rapport avec une VM du VLAN 20 ; (d) `conntrackd` ne synchronise pas de routes.
3. Les VMs du VLAN 99 reçoivent des ARP gratuits des deux passerelles : leur cache bascule de l'une à l'autre ; le trafic sort par l'une, revient (selon le VLAN de l'interlocuteur) par l'autre : connexions jetées par le suivi d'état, pertes intermittentes. Le groupe de synchronisation n'y peut rien : chaque passerelle est maître de **toutes** ses instances (le groupe est cohérent localement) ; c'est le **VLAN 99** qui a deux maîtres, faute d'annonces. Détection : `ms-verif-reseau` (« portée par 2 hôtes »), journaux keepalived (`Entering MASTER STATE` des deux côtés sans transition `BACKUP`). À 3 h : arrêter keepalived sur la passerelle qui ne doit pas être maître (RB-071 §4) — un réseau avec un seul maître, même sans redondance, vaut mieux que deux — puis chercher ce qui filtre les annonces.
4. **Préemption** : `gw01` redémarre pour un noyau à 14 h ; `gw02` prend la main (bascule 1) ; `gw01` revient et reprend la main aussitôt (bascule 2), éventuellement avant que tous ses services soient prêts (`conntrackd` n'a pas reçu l'état : connexions perdues). **`nopreempt`** : `gw01` tombe ; `gw02` prend la main ; trois jours plus tard, une maintenance de `gw02` provoque une bascule vers `gw01`… que personne n'avait planifiée parce qu'on « croyait » `gw01` maître. Choix du corrigé : `nopreempt` (une bascule par incident) + supervision qui affiche le maître + retour planifié par RB-071. Changerait si `gw02` devenait moins capable que `gw01` (préemption avec `preempt_delay` pour laisser `gw01` se stabiliser).
5. Avec `masquerade`, l'adresse de sortie est celle de l'interface de la passerelle qui traduit : une entrée synchronisée vers `gw02` dirait « 10.10.99.50:41000 ↔ `<IP-GW01-WAN>`:61234 », adresse que `gw02` ne possède pas ; les réponses d'Internet continuent d'arriver à `gw01` (qui n'a plus la route de retour vers le lab… ou plus rien). La traduction vers la VIP WAN rend l'entrée valable des deux côtés, **à condition** que la VIP WAN soit sur la passerelle qui route les VLAN : sinon la traduction sort par une passerelle et les réponses arrivent à l'autre. D'où l'instance WAN dans le groupe `BORDURE`.
6. **Réponse b.** Avec `nf_conntrack_tcp_loose=1`, le premier paquet TCP vu en cours de connexion crée une entrée (« reprise ») ; la règle « MGMT → tout le lab » l'accepte dans le sens `adm01` → VM ; dans l'autre sens, la réponse appartient à l'entrée créée. (a) faux grâce à la reprise ; (c) faux : si c'est la VM qui émet en premier, son paquet crée une entrée dans le sens VM → `adm01` que **aucune règle** n'accepte comme nouveau flux : c'est plutôt le cas qui échoue ; (d) l'ARP gratuit ne fait que diriger les paquets. Avec `tcp_loose=0`, un paquet qui n'est pas un SYN et n'appartient à aucune entrée est `invalid` : la session tombe. Avec `conntrackd`, la reprise n'apporte plus rien et ouvre une petite surface (un paquet forgé crée un état) : réglage strict.
7. `wg1` : le poste **initie** (trafic, *keepalive*) vers la VIP WAN ; le nouveau maître a la même clé privée et accepte la poignée de main : le tunnel se rétablit dès le premier paquet du poste. `wg0` : si `pbs01` n'émet rien (pas de *keepalive*, pas de sauvegarde en cours) et que le nouveau maître initie depuis son adresse propre, le pare-feu de `pbs01` peut rejeter ses paquets (source inattendue) : le tunnel reste muet jusqu'à ce que `pbs01` émette. Le *roaming* autorise un pair à changer d'adresse source **après** authentification cryptographique ; il ne contourne ni un pare-feu en amont, ni une traduction qui changerait la source en cours de route.
8. Enchaînement : bascule VRRP (≈ 0,6 s planifiée, ≈ 3,6 s brutale) ; tunnel `wg2` monté par la transition ; première poignée de main (au premier paquet ou au *keepalive* de 25 s de `lyo-gw01`) ; côté `lyo-gw01`, la session TCP vers 10.255.2.1 est morte (l'état TCP était sur l'ancien maître) : elle n'est détectée qu'à l'expiration du *hold time* (180 s par défaut, *keepalive* 60 s), ou plus tôt si une écriture TCP échoue (RST du nouveau maître). Reprise typique : de quelques secondes (RST) à 3 minutes. Raccourcir : `timers bgp 10 30` sur le voisin (des deux côtés) ; BFD au-dessus du tunnel pour une détection en moins d'une seconde. Trop court : une gigue du tunnel fait tomber la session, et chaque chute retire les routes de Lyon.
9. Au pire, la panne survient juste après un contrôle réussi : il faut `fall 3` contrôles en échec, espacés de `inter 2s` (plus le délai de chaque contrôle, borné par `timeout check`) : ≈ 6 s, soit ≈ 300 requêtes à 50 requêtes/s qui reçoivent une erreur (502/503). `observe layer7` fait compter les réponses des **vraies** requêtes (codes 5xx) comme des échecs, et `on-error mark-down` (ou `fastinter`) retire ou recontrôle le serveur dès les premières erreurs : quelques requêtes perdues au lieu de quelques centaines.
10. **Réponse b.** En mode maître-processus, `reload` lance de nouveaux processus avec la nouvelle configuration, qui reprennent les sockets d'écoute (transmises par le socket d'API grâce à `expose-fd listeners`) ; les anciens processus cessent d'accepter et finissent leurs connexions, au plus tard à `hard-stop-after`. (a) c'est le comportement d'un `restart` ; (c) la nouvelle configuration s'applique **immédiatement** aux nouvelles connexions ; (d) rien n'empêche un rechargement.
11. Une VIP désigne « la passerelle active », pas une machine : (1) Ansible vise `.1` pour configurer `gw01` et configure `gw02` après une bascule (rendu de `gw01` appliqué à `gw02` : adresses `.2` posées sur `gw02`, conflit) ; (2) la session BGP de `leaf01` vers la VIP tombe et se rétablit avec l'autre passerelle à chaque bascule, avec un identifiant de routeur qui change ; (3) une sonde qui interroge la VIP conclut « tout va bien » alors que la passerelle de secours est morte depuis trois jours. Un quatrième : un certificat ou une clé d'hôte SSH qui « change » selon le maître (alerte d'empreinte, ou pire, habitude de l'ignorer).
12. Hypothèses : (a) MTU de `ens19` ou `ens19.30` différent sur `gw02` (9000 attendu de bout en bout sur le VLAN 30) ; (b) la passerelle de secours n'émet pas, ou filtre, les ICMP « fragmentation nécessaire » (PMTUD cassée) — les règles sont communes, mais un réglage noyau (`net.ipv4.ip_no_pmtu_disc`) ou une règle de test peut différer ; (c) un réglage de MSS (`tcp option maxseg size set rt mtu`) présent sur `gw01` seulement ; (d) `wg0` monté sur `gw02` avec un MTU différent (calcul automatique de `wg-quick` sur une route de MTU différent). À chercher en premier : `ip -d link show` des deux côtés (MTU), `nft list ruleset` (diff), `ping -M do -s 1392` à travers `wg0` depuis `gw02`.
13. Aux adresses **propres** (`10.10.40.2` et `10.10.40.3`), chaque nœud ayant deux sessions : une session vers une VIP changerait de pair à chaque bascule (réinitialisation, retrait des routes). Pendant une bascule VRRP, les sessions BGP ne bougent pas : les routes du VLAN 41 sont connues des **deux** passerelles en permanence ; seul change le maître qui reçoit le trafic des autres VLAN. C'est l'avantage de l'actif-actif pour le routage (ADR-0070).
14. (1) `ms-verif-reseau` vert, `conntrackd -s` sain des deux côtés ; (2) mise à jour de la passerelle de **secours** (`gw02`), redémarrage, vérification (état `BACKUP`, cache externe rempli, BGP `leaf01` établi) : perte 0 ; (3) bascule planifiée RB-071 (`stop keepalived` sur `gw01`) : perte ≈ 0,6 s, connexions conservées ; (4) mise à jour et redémarrage de `gw01`, vérification en `BACKUP` ; (5) retour planifié sur `gw01` : ≈ 0,6 s ; (6) `ms-verif-reseau` vert. Total : deux pertes de moins d'une seconde, aucune connexion perdue. Jamais pendant une sauvegarde PBS.

---

### M07-E34 — Publier un nouveau service en temps limité

**Solution de référence** (à lire après avoir fait l'exercice ; le dossier est dans `ressources/M07-E34/`)

Une demi-douzaine de modifications, en trois MR :

1. **`plateforme/infra`** (DNS) : un enregistrement `agenda-demo` (module `enregistrement-dns`, même chemin que `gitlab`/`netbox` en M07-E13), A vers 10.10.70.200 ou alias vers `lb.par1.medisphere.internal`.
2. **`plateforme/ansible`** :
   - `group_vars/role_lb/haproxy.yml` : dans `fe_publication`, **avant** les `use_backend` (HAProxy évalue toujours les `http-request` avant), le refus des sources non autorisées, puis le routage ; et une section de serveurs :
     ```yaml
     # fe_publication, lignes ajoutées :
     - acl hote_agenda var(txn.hote) -m str agenda-demo.par1.medisphere.internal
     - http-request deny deny_status 403 if hote_agenda !{ src 10.10.0.0/16 10.255.1.0/24 }
     - use_backend be_agenda_demo if hote_agenda
     # nouvelle section :
     - type: backend
       nom: be_agenda_demo
       lignes:
         - balance roundrobin
         - option httpchk
         - http-check send meth GET uri / ver HTTP/1.1 hdr Host agenda-demo.par1.medisphere.internal
         - http-check expect status 200
         - http-response set-header X-MediSphere-Service agenda-demo
         - server srv01 <IP-SRV01>:80 check inter 3s fall 3 rise 2
         - server srv02 <IP-SRV02>:80 check inter 3s fall 3 rise 2
     ```
     `<IP-SRV01>`, `<IP-SRV02>` : adresses de `srv01`/`srv02` sur `vsandbox` telles que les fixe le code de la maquette (M07-E03) ; un nom DNS résolu au démarrage de HAProxy convient aussi, à condition qu'il soit stable. L'`acl` doit être déclarée après la ligne qui remplit `txn.hote`.
   - certificat : une entrée de plus dans `certificats_acme_certificats` de `group_vars/role_lb/certificats.yml` (même modèle que `gitlab` et `netbox` en M07-E13 : `/etc/haproxy/certs/agenda-demo.crt` et `.key`, groupe `haproxy`, défi par `:8402`), donc sur **les deux** répartiteurs ;
   - matrice : `{entree: $V_DMZ, source: [$LB01, $LB02], sortie: $V_SANDBOX, destination: [<IP-SRV01>, <IP-SRV02>], proto: tcp, ports: 80, motif: "répartiteurs vers srv01, srv02 (agenda-demo, temporaire)", ref: M07-E34}`. Le filtrage local des répartiteurs n'a rien à ouvrir en entrée (les contrôles et requêtes vers les serveurs sont **sortants**).
3. **`plateforme/outils`** : `etc/ms-verif-reseau.conf`, une URL de plus (`"https://agenda-demo.par1.medisphere.internal/ 200"`) ; les serveurs `srv01`/`srv02` sont vus par le contrôle `haproxy` sans rien ajouter.

Vérifications rapides avant le check :

```
admin@adm01:~$ curl -sI https://agenda-demo.par1.medisphere.internal/ | grep -iE '^HTTP|x-medisphere|strict'
admin@adm01:~$ for i in 1 2 3 4; do curl -s https://agenda-demo.par1.medisphere.internal/ | grep -o 'srv0[12]'; done   # alternance
root@pve01:~# curl -s -o /dev/null -w '%{http_code}\n' --cacert /root/medisphere-root-ca.crt \
                --resolve agenda-demo.par1.medisphere.internal:443:<IP-GW-WAN-VIP> https://agenda-demo.par1.medisphere.internal/   # 403
```

(La racine MédiSphère est **publique** : la copier sur `pve01` pour ce test est sans risque ; supprime-la ensuite si tu ne veux rien laisser.)

Retrait : les mêmes MR à l'envers (service, certificat — fichiers et unité de renouvellement retirés par le rôle, certificat laissé expirer : 30 jours au plus, rien ne le présente plus —, règle de matrice, URL de supervision, enregistrement DNS).

**Pièges classiques**
- Oublier la règle de transit DMZ → SANDBOX : les deux serveurs `DOWN`, page 503.
- Restreindre l'accès par l'en-tête `X-Forwarded-For` (que le client peut forger) au lieu de la source TCP.
- Croire le LAN maison bloqué parce que le nom ne s'y résout pas : la redirection 443 de la VIP WAN accepte n'importe quel `Host`.
- Un certificat sur `lb01` seulement : le service tombe à la bascule des répartiteurs.
- Le contrôle de santé avec un `Host` que Nginx ne connaît pas : `srv01` répond par son site par défaut, peut-être 200 quand même (contrôle sans valeur).

**Retour d'expérience type** : le plus long est l'attente des pipelines et de l'émission des deux certificats ; à automatiser : un « service publié » décrit en une seule entrée d'inventaire (nom, serveurs, accès), dont découlent DNS, certificat, configuration, matrice et supervision (module 28, catalogue de services).
