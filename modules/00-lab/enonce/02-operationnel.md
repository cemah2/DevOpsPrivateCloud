# Module 00 — Palier 2 : Opérationnel

Le socle existe : `gw01` route et filtre, le template `tpl-debian13` produit des VMs en une minute, `adm01` et `dns01` tournent. Mais tout se fait encore avec des adresses IP en dur, depuis la console de l'hyperviseur, et rien n'est sauvegardé. Claire Morel veut un lab **exploitable au quotidien** avant d'aller plus loin : des noms, un poste d'administration outillé, un accès distant chiffré, une API utilisable par l'automatisation, et surtout des **sauvegardes hors site, restaurées au moins une fois**. C'est aussi le palier où `hp01` quitte sa vie de serveur de photos pour devenir `pbs01`, le serveur de sauvegarde du site PAR2. Les tickets qui suivent sont ceux d'une semaine ordinaire dans l'équipe Plateforme.

> **D'où lancer les vérifications ?** Jusqu'à M00-E14 inclus, depuis `pve01` (comme au palier 1). À partir de M00-E15, **toujours depuis `adm01`**, qui devient le poste d'administration du lab.

---

### M00-E13 — DNS provisoire avec dnsmasq  `LAB` `★★`

> **Ticket PLAT-113** — *De : Karim Benali*
> On ne va pas tenir longtemps avec des IP en dur partout. Il faut un DNS interne avant que les VMs se multiplient : zone `par1.medisphere.internal`, reverse propre (les traceroutes et les journaux SSH doivent afficher des noms), et résolution Internet pour tout le lab. dnsmasq sur `dns01` suffit pour l'instant ; on passera à PowerDNS au module 06, donc garde ça simple et lisible.

**Objectifs pédagogiques**
- Configurer dnsmasq comme serveur de noms local (A et PTR) et relais récursif.
- Distinguer les données servies localement des requêtes relayées vers l'amont, et comprendre pourquoi dnsmasq n'est pas un vrai serveur faisant autorité.
- Ouvrir le DNS entre VLANs sur `gw01`, de façon ciblée, en UDP **et** en TCP.
- Lire une réponse `dig` : statut, drapeaux, section réponse, serveur ayant répondu.

**Prérequis** : M00-E10 (`gw01`), M00-E12 (`adm01` et `dns01` déployées).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichier de configuration : `/etc/dnsmasq.d/medisphere.conf` sur `dns01`.
- Enregistrements attendus :

| Nom | Adresse | Remarque |
|---|---|---|
| `gw01.par1.medisphere.internal` | 10.10.10.1 | Les autres `.1` des VLANs routés ont aussi un PTR vers `gw01` |
| `adm01.par1.medisphere.internal` | 10.10.10.10 | |
| `dns01.par1.medisphere.internal` | 10.10.20.10 | |
| `pve01.par1.medisphere.internal` | `<IP-PVE01>` | Adresse de `pve01` sur le LAN maison |
| `pbs01.par2.medisphere.internal` | 10.20.10.10 | Nom canonique (PTR) ; `pbs01` n'existe pas encore (E20) |
| `pbs01.par1.medisphere.internal` | 10.20.10.10 | Alias pratique depuis PAR1 |

- Zones inverses servies localement : 10.10.0.0/16 et 10.20.0.0/16 (au minimum 10.20.10.0/24).
- `<DNS-AMONT>` : un ou deux résolveurs récursifs (ta box, ou des résolveurs publics de ton choix). Note ton choix dans `lab/inventaire-local.md`.
- Clients à basculer sur 10.10.20.10 : `gw01` (configuration statique, héritée de son installation), `adm01` et `dns01` (résolveur provisoire `<DNS-PUBLIC>` posé en E12 par les paramètres `nameserver` et `searchdomain` de Proxmox). Les futures VMs héritent du template 9000, qui pointe déjà sur 10.10.20.10 depuis E11.
- Les vérifications se lancent encore depuis `pve01` : elles joignent les VMs par les alias SSH de `root@pve01` (`gw01`, `dns01`, `adm01`) mis en place en E10 et E12.

**Travail demandé**
1. Sur `dns01`, installe `dnsmasq` et `bind9-dnsutils`. Avant de configurer, regarde qui écoute déjà sur le port 53 (`ss -lntup 'sport = :53'`) : un `systemd-resolved` est-il présent ? Décide comment dnsmasq va cohabiter avec lui.
2. Rédige `/etc/dnsmasq.d/medisphere.conf`. Contraintes :
   - dnsmasq n'écoute que sur 127.0.0.1 et 10.10.20.10 ;
   - il ne lit pas `/etc/resolv.conf` pour trouver ses serveurs amont : ils sont déclarés explicitement ;
   - il ne transmet jamais vers l'amont un nom court, un reverse d'adresse privée, ni une question sur `medisphere.internal` ;
   - il sert les enregistrements A et PTR du tableau, et un PTR pour chaque passerelle `.1` ;
   - la journalisation des requêtes est prévue mais désactivée par défaut ;
   - le fichier est commenté : quelqu'un qui ne connaît pas dnsmasq doit comprendre chaque ligne.
3. Trouve comment le service dnsmasq de Debian est lancé (`systemctl cat dnsmasq`) et comment il valide sa configuration avant de démarrer. Redémarre-le, lis le journal.
4. Sur `gw01`, ajoute à `/etc/nftables.conf` ce qu'il faut pour que **tous les réseaux internes** (VLANs routés, et dès maintenant PAR2 et le futur VPN) joignent 10.10.20.10 en DNS, UDP et TCP, et pour que `dns01` joigne ses serveurs amont. Rien de plus. Valide avec `nft -c -f` avant de recharger.
5. Bascule **tous** les clients sur 10.10.20.10, avec le domaine de recherche `par1.medisphere.internal` :
   - `gw01` ;
   - `adm01` et `dns01` : à la fois dans la VM (regarde d'abord ce que cloud-init a réellement écrit : `resolvectl status` ou `/etc/resolv.conf`, selon ce que l'image utilise) et dans leur configuration cloud-init côté Proxmox, pour qu'une régénération ne réintroduise pas `<DNS-PUBLIC>` ;
   - le template 9000 : vérifie qu'il pointe toujours sur 10.10.20.10 (futures VMs).
6. Teste depuis `adm01` avec `dig` : un A, un PTR, un nom court, un nom Internet, un nom inexistant de `par1`, une requête en TCP (`+tcp`). Pour chacune, note le statut et les drapeaux (`aa`, `ra`). Montre qu'une question sur un nom inexistant de `par1` ne quitte pas `dns01` (active temporairement la journalisation des requêtes, ou capture avec `tcpdump` sur `dns01`).

**Critères de réussite**
- [ ] `dig +short @10.10.20.10 adm01.par1.medisphere.internal` renvoie 10.10.10.10, et chaque PTR du tableau renvoie le bon nom.
- [ ] Sur `adm01`, `getent hosts dns01` (nom court) renvoie 10.10.20.10.
- [ ] `gw01` résout les noms du lab.
- [ ] `gw01`, `adm01` et `dns01` utilisent 10.10.20.10 comme résolveur ; dans Proxmox, `nameserver` vaut 10.10.20.10 pour 1001, 1002 et le template 9000 (plus aucune trace de `<DNS-PUBLIC>`).
- [ ] Un nom Internet se résout depuis `adm01`.
- [ ] Un nom inexistant de `par1` renvoie `NXDOMAIN` sans requête vers l'amont (preuve à l'appui).
- [ ] Une requête DNS en TCP aboutit depuis `adm01`.
- [ ] `ss -lnu 'sport = :53'` sur `dns01` ne montre aucune écoute sur `0.0.0.0` ou `*`.

**Vérification** : `lab/bin/check 00 13` (depuis `pve01`)

<details><summary>Indice 1</summary>

Dans `man dnsmasq`, lis les options `--host-record`, `--ptr-record`, `--local`, `--domain-needed`, `--bogus-priv`, `--no-resolv`, `--server`, `--listen-address` et `--bind-interfaces`. Une seule de ces options crée à la fois le A et le PTR.
</details>

<details><summary>Indice 2</summary>

Une zone inverse se nomme en lisant les octets à l'envers : 10.10.0.0/16 correspond à `10.10.in-addr.arpa`. Pour `pbs01`, deux noms pour une adresse : seul le premier nom d'une ligne reçoit le PTR.
</details>

<details><summary>Indice 3</summary>

Si dnsmasq refuse de démarrer avec « Address already in use », un autre processus tient le port 53 sur une adresse que dnsmasq veut aussi. Compare son comportement avec et sans `bind-interfaces`. Si `dnsmasq --test` dit « syntax check OK » alors que le service échoue, vérifie que ta commande de test lit bien `/etc/dnsmasq.d/` (regarde la ligne de commande du processus : `ps -o args -C dnsmasq`).
</details>

**Pour aller plus loin** (facultatif) : lis la partie « authoritative » de `man dnsmasq` (`--auth-zone`, `--auth-server`) et compare avec ce que tu as fait. Active la validation DNSSEC (`--dnssec`) et observe le drapeau `ad` sur un domaine signé. Le module 06 remplace tout cela par PowerDNS (serveur faisant autorité + récurseur séparés).

---

### M00-E14 — DHCP du VLAN SANDBOX par relais  `LAB` `★★★`

> **Ticket PLAT-114** — *De : Nadia Roussel*
> Pour les exercices de panne et les VMs jetables, je ne veux plus qu'on choisisse des IP à la main dans le VLAN SANDBOX : deux conflits la semaine dernière, une heure perdue à chaque fois. Il faut du DHCP sur le VLAN 99, servi par `dns01` (un seul endroit pour les baux et les noms), **sans** donner à `dns01` une patte dans le VLAN 99.

**Objectifs pédagogiques**
- Comprendre le relais DHCP : `giaddr`, ports 67/68 de chaque côté, option 82, renouvellements en unicast.
- Configurer dnsmasq en relais sur `gw01` et en serveur pour un sous-réseau distant sur `dns01`.
- Écrire des règles nftables précises pour un flux que conntrack ne reconnaît pas comme une réponse.
- Suivre l'échange complet avec `tcpdump`, des deux côtés du relais.

**Prérequis** : M00-E13.
**Durée indicative** : 2 h.

**Contexte technique**
- Plage : 10.10.99.100 à 10.10.99.199, bail de 12 h. Options : routeur 10.10.99.1, DNS 10.10.20.10, domaine `par1.medisphere.internal`, NTP 10.10.99.1.
- Relais : **dnsmasq en mode relais** sur `gw01` (choix du corrigé ; `isc-dhcp-relay` est une alternative valable si tu le trouves dans les dépôts de Debian 13 — justifie ton choix).
- VM de test : 5001 `sbx01`, clone du template 9000, pool `lab`, carte sur `vmbr1` avec `tag=99`, cloud-init `ipconfig0` en DHCP. Elle sera détruite en fin d'exercice (E18 réutilise le VMID 5001).

**Travail demandé**
1. Avant de toucher au clavier, écris dans ton journal le trajet d'un `DHCPDISCOVER` jusqu'au `DHCPACK` : qui émet, vers quelle adresse et quel port, à chaque étape. Explique le rôle du champ `giaddr` et ce qu'est l'option 82.
2. Sur `dns01`, complète `medisphere.conf` : une plage pour le VLAN 99 et ses options. `dns01` n'a pas d'adresse dans ce sous-réseau : qu'est-ce que dnsmasq ne peut pas deviner tout seul ?
3. Sur `gw01`, installe dnsmasq et configure-le **uniquement** en relais pour `ens19.99` vers 10.10.20.10, sans aucun service DNS, dans `/etc/dnsmasq.d/relais-dhcp.conf`.
   > ⚠️ **Attention** : le paquet Debian démarre dnsmasq dès l'installation avec sa configuration par défaut, c'est-à-dire un DNS sur toutes les interfaces. Ton pare-feu d'entrée te protège, mais vérifie avec `ss -lnup` que la situation finale est celle que tu veux. Vérifie aussi que l'installation n'a pas modifié la résolution de `gw01` lui-même.
4. Dans le pare-feu de `gw01`, autorise strictement ce qu'il faut : les requêtes des clients vers le relais, les réponses du serveur vers le relais, et les renouvellements. Réponds dans ton journal : pourquoi la règle `ct state established,related accept` ne suffit-elle pas pour les réponses de `dns01` ?
5. Crée la VM de test depuis `pve01` :
   ```
   root@pve01:~# qm clone 9000 5001 --name sbx01 --pool lab
   root@pve01:~# qm set 5001 --net0 virtio,bridge=vmbr1,tag=99 --ipconfig0 ip=dhcp
   ```
   Avant de la démarrer, lance trois captures : sur `gw01` côté clients (`tcpdump -ni ens19.99 -v port 67 or port 68`), sur `gw01` côté serveur (`tcpdump -ni ens19.20 -v port 67`), et sur `dns01`. Démarre la VM et observe les quatre messages de chaque côté.
6. Vérifie : le bail dans `/var/lib/misc/dnsmasq.leases` sur `dns01`, l'adresse vue par l'agent (`qm guest cmd 5001 network-get-interfaces`), la résolution de `sbx01.par1.medisphere.internal`.
7. Force un renouvellement depuis `sbx01` (selon le client DHCP de l'image : `networkctl renew`, `dhclient -r`/`dhclient`, ou un simple redémarrage réseau) et observe par où passe la requête cette fois.
8. Lance la vérification, puis détruis la VM :
   ```
   root@pve01:~# qm stop 5001 && qm destroy 5001 --purge
   ```

**Critères de réussite**
- [ ] `sbx01` obtient une adresse dans 10.10.99.100-199, avec la passerelle 10.10.99.1 et le DNS 10.10.20.10.
- [ ] Le bail apparaît sur `dns01`, qui n'a aucune adresse dans le VLAN 99.
- [ ] Ta capture sur `ens19.20` montre des paquets de `gw01` vers 10.10.20.10:67 portant `Gateway-IP 10.10.99.1`.
- [ ] `gw01` n'offre aucun service DNS.
- [ ] Le pare-feu de `gw01` reste en politique `drop` et n'ouvre le port 67 que sur `ens19.99` et pour `dns01`.
- [ ] `sbx01.par1.medisphere.internal` se résout tant que le bail est actif.

**Vérification** : `lab/bin/check 00 14` (depuis `pve01`, avant de détruire la VM)

<details><summary>Indice 1</summary>

`man dnsmasq` : `--dhcp-relay`, `--port`, `--interface` côté `gw01` ; `--dhcp-range` (forme avec masque), `--dhcp-option`, et les étiquettes `set:`/`tag:` côté `dns01`. `--log-dhcp` sur `dns01` détaille chaque décision (plage choisie, options envoyées).
</details>

<details><summary>Indice 2</summary>

Le serveur répond **au giaddr**, sur le port 67, pas à l'adresse source du paquet relayé. Regarde dans ta capture l'adresse source réelle des requêtes relayées, puis demande-toi quel quadruplet conntrack attend pour la réponse.
</details>

<details><summary>Indice 3</summary>

Dans un `DHCPACK`, l'option 54 (*server identifier*) donne l'adresse que le client utilisera pour renouveler son bail à mi-parcours. Ce renouvellement passe-t-il par le relais ?
</details>

**Pour aller plus loin** (facultatif) : l'option 82 (*relay agent information*) est ajoutée par les commutateurs et relais d'entreprise (*circuit-id* = port du switch). Regarde ce que `isc-dhcp-relay -a` y met, et comment dnsmasq peut s'en servir (`--dhcp-circuitid`, `--dhcp-remoteid`). Kea DHCP (module 06) remplacera dnsmasq ici.

---

### M00-E15 — Outiller le poste d'administration `adm01`  `LAB` `★★`

> **Ticket PLAT-115** — *De : Claire Morel*
> À partir de maintenant, on administre le lab depuis `adm01`, plus depuis l'hyperviseur : `pve01` doit rester propre, sans outils ni clés de tout le monde. Prépare `adm01` comme un vrai poste d'admin : clés, alias SSH, outils, dépôt du workbook. N'importe qui dans l'équipe doit pouvoir s'y retrouver.

**Objectifs pédagogiques**
- Générer et protéger une clé ed25519, l'utiliser via un agent.
- Factoriser l'accès SSH dans `~/.ssh/config` (alias, utilisateurs, multiplexage, politique de clés d'hôte).
- Arrêter une politique `sudo` pour l'automatisation, et la justifier.
- Migrer l'outillage du workbook vers `adm01`.

**Prérequis** : M00-E12, M00-E13.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Convention SSH du workbook (figée, les scripts en dépendent) :

| Alias | Cible | Utilisateur | Élévation |
|---|---|---|---|
| `pve01` | `<IP-PVE01>` | `root` | — |
| `pbs01` | 10.20.10.10 (joignable après E21) | `root` | — |
| `gw01` | 10.10.10.1 | `admin` | `sudo -n` |
| `dns01` | 10.10.20.10 | `admin` | `sudo -n` |

- Outils : `git`, `curl`, `jq`, `bind9-dnsutils`, `tcpdump`, `mtr-tiny`, `tmux`, `shellcheck`, `python3-venv`.
- Dépôt du workbook : `<URL-DU-DEPOT>`, cloné dans `~/DevOpsPrivateCloud`.
- `lab/lab.env` sur `adm01` : copie de `lab/lab.env.example` (voir l'introduction). Nouvelle valeur à renseigner : `WB_PBS_LAN=<IP-HP01-LAN>`, adresse LAN de `hp01` (connue depuis E03), utilisée par les vérifications de E20 et E21.

**Travail demandé**
1. Sur `adm01`, génère une clé ed25519 protégée par une phrase de passe. Charge-la dans un agent pour la session (`ssh-agent`, ou `keychain` si tu veux qu'il survive aux déconnexions). Les vérifications tournent en mode *batch* : sans agent chargé, elles échoueront.
2. Dépose la clé publique : `root@pve01`, `admin@gw01`, `admin@dns01` (`pbs01` viendra en E20).
   > ⚠️ **Attention** : sur Proxmox VE, `/root/.ssh/authorized_keys` est un lien vers `/etc/pve/priv/authorized_keys`. Ajoute ta clé, ne remplace pas le fichier.
3. Écris `~/.ssh/config` selon la convention. Décide, et écris en commentaire dans le fichier : `HostName` en adresse IP ou en nom DNS ? (Pense à l'exercice M00-E40.) Ajoute des valeurs par défaut utiles : choix de la clé, maintien de session, multiplexage des connexions, politique pour les clés d'hôte inconnues, traitement particulier des VMs jetables de la sandbox.
4. `sudo` : les vérifications, les injections de pannes, puis Ansible (M04) ont besoin de `sudo -n` sur les VMs. Ne crée aucun fichier : ce droit existe déjà. Vérifie-le (`sudo -l`) et retrouve d'où il vient sur chaque VM : sur `adm01` et `dns01`, ce que cloud-init a posé dans `/etc/sudoers.d/` ; sur `gw01`, le fichier `90-workbook` que tu as créé en E10. Puis décide : `NOPASSWD: ALL` ou liste blanche de commandes ? Écris ta justification (5 lignes max) dans tes notes.
5. Installe les outils.
6. Configure `git` (nom, adresse), clone le dépôt dans `~/DevOpsPrivateCloud`, crée `lab/lab.env` par `cp lab/lab.env.example lab/lab.env`, puis renseigne : `WB_PVE_HOST=pve01`, `WB_PBS_HOST=pbs01`, `WB_LAN_MAISON`, `WB_PBS_LAN` (et, si besoin, les `WB_STORAGE_*` de E07).
7. Lance `lab/bin/check 00 15`, puis relance depuis `adm01` les vérifications de E13 et E14 : elles doivent passer d'ici aussi.
8. Une fois tout validé depuis `adm01`, fais le ménage sur `pve01` : outils installés uniquement pour le lab, clone du dépôt. Avant de supprimer le clone, recopie dans ta copie de `adm01` ce qui n'est pas versionné et que tu veux garder (`lab/inventaire-local.md`). Garde une trace de ce que tu retires.

**Critères de réussite**
- [ ] `ssh pve01 hostname`, `ssh gw01 sudo -n true` et `ssh dns01 sudo -n true` aboutissent sans mot de passe ni question.
- [ ] La clé privée est protégée par une phrase de passe.
- [ ] `ssh -G pbs01` indique `user root` et `hostname 10.20.10.10`.
- [ ] Les outils sont présents ; `lab/lab.env` existe et contient `WB_PBS_LAN`.
- [ ] `lab/bin/check 00 15`, `00 13` et `00 14` passent depuis `adm01`.

**Vérification** : `lab/bin/check 00 15` (depuis `adm01`, désormais pour tous les exercices)

<details><summary>Indice 1</summary>

`ssh -G <alias>` affiche la configuration effective calculée par ssh : c'est le meilleur moyen de vérifier quelle valeur l'emporte. Dans `~/.ssh/config`, la **première** valeur trouvée pour une option gagne : place les blocs spécifiques avant `Host *`.
</details>

<details><summary>Indice 2</summary>

Pour le multiplexage : `ControlMaster`, `ControlPath`, `ControlPersist`. Un `ControlPath` trop long casse silencieusement (limite de taille des sockets Unix) : le jeton `%C` règle le problème. Pour les VMs jetables : `StrictHostKeyChecking` et `UserKnownHostsFile`.
</details>

<details><summary>Indice 3</summary>

Teste un accès comme un script le ferait : `ssh -o BatchMode=yes gw01 'sudo -n true' && echo OK`. Toute question posée (mot de passe, clé d'hôte, phrase de passe) fait échouer la commande au lieu de bloquer.
</details>

**Pour aller plus loin** (facultatif) : signe ta clé avec une autorité de certification SSH (`ssh-keygen -s`) et fais confiance à cette AC sur les VMs plutôt qu'à des clés individuelles. Ce sera industrialisé au module 06 avec step-ca.

---

### M00-E16 — VPN d'administration WireGuard  `LAB` `★★`

> **Ticket SEC-116** — *De : Sophie Laurent*
> La route statique vers 10.10.0.0/16 depuis vos postes, c'est pratique, mais ça ouvre tout le lab à tout le LAN, sans authentification réseau. Je veux un accès d'administration chiffré, authentifié par clé, nominatif (un pair = une personne), qui ne donne accès qu'aux réseaux d'administration. Le reste du LAN ne doit plus voir le lab, à l'exception de l'hyperviseur.

**Objectifs pédagogiques**
- Monter une interface WireGuard avec `wg-quick` et comprendre le routage par clé (*cryptokey routing*).
- Configurer un client sur un poste (Linux, Windows ou macOS) en tunnel partagé (*split tunnel*).
- Filtrer précisément ce qui entre par le VPN, sans NAT.
- Ajouter un pair sans couper les autres.

**Prérequis** : M00-E10, M00-E13.
**Durée indicative** : 1 h 30.

**Contexte technique**
- `wg1` sur `gw01` : 10.255.1.1/24, UDP 51821, fichier `/etc/wireguard/wg1.conf`, service `wg-quick@wg1`.
- Ton poste : 10.255.1.2/32. Point d'accès : `<IP-GW01-WAN>:51821`.
- Réseaux accessibles par le VPN : MGMT (10.10.10.0/24), INFRA (10.10.20.0/24), PAR2 MGMT (10.20.10.0/24) quand il existera (E21), et `pve01` en SSH (22) et sur son interface web/API (8006), pour administrer l'hyperviseur quand ton poste n'est pas sur le LAN maison. `pve01` répond au VPN par la route vers 10.255.1.0/24 posée en E10.
- `pve01` garde son accès direct au lab (route statique, pas de client VPN).

**Travail demandé**
1. Sur `gw01`, installe `wireguard-tools`. Génère la paire de clés de `wg1` sans jamais laisser la clé privée lisible par d'autres que root (pense à `umask`). Décide si la clé privée est écrite dans `wg1.conf` ou lue depuis un fichier séparé ; justifie.
2. Sur ton poste, installe le client WireGuard officiel et génère **sur le poste** la paire de clés du pair. La clé privée du poste ne transite jamais.
3. Écris la configuration du client : adresse, pair `gw01`, point d'accès, et des `AllowedIPs` limités aux réseaux d'administration. Décide si le VPN pousse un DNS (lis d'abord ce que fait ton système de ce réglage).
4. Déclare le pair sur `gw01`. Puis ajoute un second pair fictif (une deuxième clé générée pour l'occasion, 10.255.1.3/32) **sans couper la session du premier**, et retire-le de la même façon.
5. Pare-feu de `gw01` : UDP 51821 en entrée depuis le LAN maison uniquement ; SSH vers `gw01` depuis le VPN ; transfert du VPN vers MGMT et INFRA, et vers `pve01` sur les ports 22 et 8006 seulement ; aucune traduction d'adresse pour le trafic du VPN. Si une règle de E10 autorisait tout le LAN maison vers le lab, restreins-la à `pve01`.
6. Active `wg-quick@wg1` au démarrage. Retire de ton poste la route statique vers 10.10.0.0/16 si tu en avais une (pas celle de `pve01`).
7. Teste depuis le poste, VPN actif puis coupé : poignée de main (`wg show` ou l'application), SSH vers `adm01` par son IP, `dig @10.10.20.10`. Tente un accès vers une adresse du VLAN SANDBOX ou DMZ et retrouve le rejet dans le journal de `gw01`.
8. Sur `adm01`, vérifie avec `ss -tn` ou `journalctl -u ssh` que ta connexion arrive bien depuis 10.255.1.2.

**Critères de réussite**
- [ ] `wg show wg1` sur `gw01` montre ton pair avec une poignée de main.
- [ ] VPN actif : SSH vers `adm01` et requêtes DNS vers `dns01` aboutissent depuis le poste.
- [ ] VPN coupé, sans route statique : 10.10.10.10 est injoignable depuis le poste.
- [ ] Le trafic du VPN vers SANDBOX ou DMZ est rejeté (ligne de journal de `gw01` à l'appui).
- [ ] Le VPN peut joindre `pve01` sur les ports 22 et 8006, et `pve01` a une route vers 10.255.1.0/24 via `gw01`.
- [ ] La connexion vue par `adm01` vient de 10.255.1.2 (pas de NAT).
- [ ] `wg1.conf` est en mode 600 et `wg-quick@wg1` est activé.

**Vérification** : `lab/bin/check 00 16`

<details><summary>Indice 1</summary>

Dans WireGuard, `AllowedIPs` joue deux rôles : à l'émission, c'est une table de routage (quel pair pour quelle destination) ; à la réception, c'est un filtre (quelles adresses source ce pair a le droit d'utiliser). `wg-quick` crée en plus les routes système correspondantes.
</details>

<details><summary>Indice 2</summary>

Pour modifier les pairs à chaud sans `down`/`up` : `wg syncconf` avec la sortie de `wg-quick strip`. Sous Linux, si `wg-quick up` échoue avec « RTNETLINK answers: File exists », une route identique existe déjà sur le poste.
</details>

<details><summary>Indice 3</summary>

Pourquoi pas de masquerade ? Demande-toi ce que verraient les journaux de `adm01`, et comment une VM du lab répond à 10.255.1.2 : par quelle passerelle, et cette passerelle sait-elle où est 10.255.1.0/24 ?
</details>

**Pour aller plus loin** (facultatif) : passe la session SSH par un bastion avec `ProxyJump adm01` depuis ton poste, et compare avec l'accès direct par le VPN. Le module 24 ajoutera une authentification forte (SSO) devant les interfaces d'administration.

---
### M00-E17 — API Proxmox et jeton à privilèges minimaux  `LAB` `★★`

> **Ticket SEC-117** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Les scripts, puis Terraform et Ansible, vont piloter Proxmox. Pas question qu'ils utilisent `root@pam` ni un compte humain. Je veux un compte technique dédié, un jeton révocable avec une date d'expiration, des droits limités au pool `lab` (les VMs personnelles de l'hyperviseur doivent rester hors d'atteinte), et **la liste des privilèges justifiée ligne à ligne** dans ce ticket.

**Objectifs pédagogiques**
- Maîtriser le modèle de permissions de Proxmox VE : chemins, propagation, rôles, pools, intersection utilisateur/jeton.
- Construire un rôle personnalisé minimal à partir des besoins réels, documentation de l'API à l'appui.
- Appeler l'API REST avec un jeton (`curl`) et l'explorer localement (`pvesh`).
- Stocker un secret proprement sur un poste d'administration.

**Prérequis** : M00-E08 (pool `lab`), M00-E15.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Compte : `wb-automation@pve` (domaine d'authentification `pve`), jeton `lab`, rôle personnalisé `WBAutomation`, tous créés ici (E08 les a seulement annoncés). Le groupe `wb-admins` a déjà `PVESDNUser` sur `vmbr1` (E09) : inspire-t'en.
- Besoins fonctionnels du jeton (E18, puis modules 02 à 05) : cloner le template 9000 en VM du pool `lab` ; modifier la configuration (CPU, mémoire, disques, réseau, cloud-init, options) ; démarrer, arrêter ; interroger l'agent QEMU en lecture ; prendre et restaurer des snapshots ; détruire ; allouer de l'espace sur les stockages du lab ; brancher les VMs sur `vmbr1`.
- Interdits : tout ce qui est hors du pool `lab` ; la gestion des utilisateurs et des permissions ; la configuration du nœud et des stockages ; les consoles ; les commandes arbitraires dans les invités.
- Version : Proxmox VE 9 a supprimé le privilège `VM.Monitor` au profit d'une famille `VM.GuestAgent.*` (et de `Sys.Audit` pour le moniteur QEMU). Si `pve01` est encore en 8.x, adapte et note la différence.
- Secret sur `adm01` : `~/.config/workbook/pve-api.env`, mode 600, avec exactement ces variables (les vérifications et E18 les lisent) : `PVE_API_URL` (`https://<IP-PVE01>:8006/api2/json`), `PVE_NODE` (nom du nœud), `PVE_TOKEN_ID`, `PVE_TOKEN_SECRET`, `PVE_CACERT`.

**Travail demandé**
1. Explore l'API sur `pve01` : `pvesh ls /nodes/<NŒUD>/qemu`, `pvesh usage /nodes/{node}/qemu/{vmid}/clone --verbose`, et la documentation en ligne de l'API (*API viewer*). Pour chaque opération de la liste des besoins, relève le privilège exigé **et le chemin** sur lequel il est vérifié.
2. Déduis-en la liste minimale de privilèges. Pour chacun, une ligne de justification (l'opération qui l'exige). Pour chaque privilège écarté qui « aurait pu servir », une ligne aussi.
3. Crée le rôle `WBAutomation`, l'utilisateur (sans mot de passe : il n'ouvrira jamais l'interface web), puis le jeton **à privilèges séparés** avec une date d'expiration (un an au plus) et un commentaire. Le secret ne s'affiche qu'une fois.
4. Pose les ACL : sur `/pool/lab`, sur les stockages utilisés par le lab, sur le pont `vmbr1` pour l'usage réseau. Avec la séparation des privilèges, qui doit recevoir ces ACL : l'utilisateur, le jeton, les deux ? Pourquoi aucune ACL sur `/` ni sur `/vms` ?
5. Contrôle les droits effectifs : `pveum user token permissions wb-automation@pve lab`, avec et sans `--path`.
6. Sur `adm01` : récupère le certificat de l'autorité locale de Proxmox (`/etc/pve/pve-root-ca.pem`), crée `~/.config/workbook/pve-api.env` **avec les bons droits avant d'y écrire**, sans que le secret passe par l'historique du shell. Appelle `GET /version` avec `curl --cacert` et l'en-tête `Authorization: PVEAPIToken=…`. Pas de `-k`.
7. Tests négatifs avec le jeton : lister les VMs du nœud (seules celles du pool apparaissent-elles ?), lire la configuration d'une VM hors pool, lire l'état du nœud, lire le journal système. Note les codes HTTP et les messages.
8. Rédige la réponse au ticket : privilèges et ACL justifiés, procédure de révocation et de renouvellement du jeton.

**Critères de réussite**
- [ ] Le jeton `wb-automation@pve!lab` a la séparation des privilèges et une date d'expiration.
- [ ] `GET /version` répond 200 depuis `adm01` avec le jeton, certificat vérifié.
- [ ] Avec le jeton, la liste des VMs ne contient que celles du pool `lab`.
- [ ] Lecture d'une VM hors pool, de l'état du nœud et du journal système : 403.
- [ ] `WBAutomation` ne contient aucun privilège `Sys.*`, `Permissions.*`, `User.*`, `Realm.*`, ni console.
- [ ] `~/.config/workbook/pve-api.env` est en mode 600 et hors de tout dépôt git.
- [ ] La réponse au ticket justifie chaque privilège.

**Vérification** : `lab/bin/check 00 17`

<details><summary>Indice 1</summary>

Dans l'API viewer, la section *Permissions* de chaque méthode donne le contrôle exact, par exemple `["perm","/vms/{vmid}",["VM.Clone"]]`. Le clonage, en particulier, accepte une alternative intéressante pour le VMID de destination quand on précise un pool.
</details>

<details><summary>Indice 2</summary>

Une ACL posée sur `/pool/lab` s'applique aux membres du pool : VMs **et** stockages qui y ont été ajoutés. Les rôles prédéfinis `PVEDatastoreUser` et `PVESDNUser` couvrent exactement deux des besoins. Pour un pont classique (hors SDN), le chemin d'ACL est sous `/sdn/zones/localnetwork/` (à vérifier selon ta version).
</details>

<details><summary>Indice 3</summary>

Si le certificat est refusé pour une question de nom, regarde les noms et adresses qu'il couvre : `openssl x509 -in /etc/pve/local/pve-ssl.pem -noout -ext subjectAltName`. Utilise dans `PVE_API_URL` un nom ou une adresse qui y figure.
</details>

**Pour aller plus loin** (facultatif) : crée un second jeton `wb-automation@pve!audit` en lecture seule (`PVEAuditor` sur `/pool/lab`) pour la supervision, et compare les droits effectifs des deux. Au module 25, le secret partira dans Vault et sera délivré à la demande.

---

### M00-E18 — Créer une VM uniquement par l'API  `LAB` `★★`

> **Ticket PLAT-118** — *De : Karim Benali*
> Avant qu'on écrive du Terraform au module 05, je veux que tu saches ce qu'un *provider* fait sous le capot. Écris un script qui crée une VM sandbox, attend qu'elle soit **vraiment** prête, récupère son IP, puis la détruit proprement. Uniquement `curl` et `jq`, depuis `adm01`, avec le jeton d'automatisation. Pas de SSH vers `pve01`, pas de `qm`.

**Objectifs pédagogiques**
- Manipuler les tâches asynchrones de Proxmox (UPID) : lancer, suivre, vérifier le résultat.
- Configurer cloud-init par l'API, y compris le piège d'encodage des clés SSH.
- Interroger l'agent QEMU par l'API.
- Écrire un script d'automatisation robuste : échec explicite, délais maximaux, garde-fous avant destruction, aucun secret exposé.

**Prérequis** : M00-E14 (DHCP du VLAN 99), M00-E17.
**Durée indicative** : 2 h 30.

**Contexte technique**
- VM : 5001 `sbx01`, clone lié du template 9000, pool `lab`, carte `virtio` sur `vmbr1` en VLAN 99, cloud-init : utilisateur `admin`, clé publique de `adm01`, DNS 10.10.20.10, domaine `par1.medisphere.internal`, adresse par DHCP (ou statique 10.10.99.20/24, passerelle 10.10.99.1, si tu veux t'affranchir de E14).
- Script : `~/lab-scripts/vm-api.sh`, sous-commandes `create`, `ip`, `destroy` et `cycle` (les trois à la suite). Il lit `~/.config/workbook/pve-api.env`.
- Si la VM 5001 existe encore (E14), détruis-la avant.
- Le pare-feu de `gw01` doit laisser `adm01` (MGMT) joindre le VLAN 99 en SSH.

**Travail demandé**
1. Écris une fonction d'appel générique à l'API : méthode, chemin, paramètres de formulaire encodés ; erreur HTTP = arrêt avec un message qui reprend le motif renvoyé par Proxmox. Le secret ne doit apparaître ni à l'écran, ni dans la liste des processus, ni dans le script.
2. Écris l'attente d'une tâche : à partir de l'UPID renvoyé par un appel asynchrone, interroge son statut jusqu'à la fin, vérifie son code de sortie, abandonne après un délai maximal.
3. `create` : vérifie que le VMID est libre (sans dépendre des droits du jeton), clone, configure (réseau, cloud-init ; l'agent est déjà activé dans le template), démarre, puis attend que l'agent QEMU réponde.
4. `ip` : récupère l'adresse IPv4 de la VM via l'agent (hors boucle locale), en attendant qu'elle apparaisse.
5. `destroy` : avant toute destruction, vérifie que la VM porte le nom attendu et appartient au pool `lab`. Arrête-la si besoin, détruis-la en purgeant ses références.
6. `cycle` : crée, affiche l'IP, teste une connexion SSH `admin@<IP>` (cloud-init peut ne pas avoir fini), détruit. Mesure la durée totale.
7. Provoque des échecs et vérifie le comportement : VMID déjà pris, jeton invalide, template inexistant.
8. `shellcheck` sans avertissement.

**Critères de réussite**
- [ ] `vm-api.sh cycle` crée la VM, affiche son IP, s'y connecte en SSH, la détruit, et sort en 0, en moins de 5 minutes.
- [ ] Le journal des tâches de `pve01` montre le clone, le démarrage et la destruction exécutés par `wb-automation@pve!lab`.
- [ ] Sur un échec (VMID pris, jeton invalide), le script s'arrête avec un message explicite et un code non nul, sans rien laisser à moitié fait qu'il n'ait signalé.
- [ ] Le script ne contient ni secret, ni appel à `qm`/`pvesh`, ni SSH vers `pve01`, et passe `shellcheck`.

**Vérification** : `lab/bin/check 00 18` (après un `cycle` complet)

<details><summary>Indice 1</summary>

Les appels qui lancent un travail long (clone, démarrage, arrêt, destruction, et `POST …/config`) renvoient un UPID dans `.data`. Son statut : `GET /nodes/{node}/tasks/{upid}/status` → `.data.status` (`running`/`stopped`) puis `.data.exitstatus`. Un UPID contient des `:` : encode-le pour l'URL (`jq -r '@uri'`).
</details>

<details><summary>Indice 2</summary>

`curl -G` envoie les `--data-urlencode` dans l'URL (GET, DELETE). `curl -H @fichier` lit les en-têtes depuis un fichier. Pour les clés SSH, le paramètre `sshkeys` doit être **déjà** encodé en URL avant d'être envoyé (espaces en `%20`) : c'est un piège connu de l'API.
</details>

<details><summary>Indice 3</summary>

« VMID libre » : avec un jeton limité au pool, une VM hors pool est invisible (403), pas « inexistante ». Cherche un point d'API qui répond sans dépendre des droits sur la VM. Et attention à `set -e` : il ne s'applique pas à une substitution de commande utilisée directement comme argument d'une fonction.
</details>

**Pour aller plus loin** (facultatif) : refais `create` en Python avec `requests` (module 02, puis `proxmoxer`). Ajoute une sous-commande `snapshot` et un mode `--dry-run` qui affiche les appels sans les faire.

---

### M00-E19 — Snapshots, clones liés et clones complets  `LAB` `★`

> **Ticket DEV-119** — *De : Julien Petit*
> Pour tester les montées de version de MédiAgenda, on aimerait revenir en arrière vite, et dupliquer une VM pour comparer deux versions côte à côte. On m'a parlé de snapshots et de clones liés, mais aussi de mauvaises surprises. Tu peux nous dire quoi utiliser, quand ?

**Objectifs pédagogiques**
- Prendre et restaurer un snapshot avec et sans état mémoire, et observer la différence.
- Comprendre la dépendance d'un clone lié envers son template, et ce qu'elle implique côté stockage.
- Savoir choisir entre snapshot, clone lié, clone complet et sauvegarde.

**Prérequis** : M00-E11 (template 9000), M00-E14 (DHCP du VLAN 99).
**Durée indicative** : 1 h.

**Contexte technique**
- 5002 `sbx02` : clone lié de 9000. 5003 `sbx03` : clone complet de 9000. Les deux dans le pool `lab`, en VLAN 99 (DHCP).
- Snapshots de `sbx02` : `etat-initial` (disque seul) et `avec-ram` (disque et mémoire).
- Les snapshots exigent un stockage qui les supporte (LVM-thin, ZFS, Ceph RBD, ou fichiers qcow2). Sur du LVM classique (« thick »), Proxmox VE 9 propose un mode de snapshots par chaîne de volumes qcow2 : à vérifier selon ta version et ton stockage.

**Travail demandé**
1. Crée le clone lié et démarre-le :
   ```
   root@pve01:~# qm clone 9000 5002 --name sbx02 --pool lab
   root@pve01:~# qm set 5002 --net0 virtio,bridge=vmbr1,tag=99 --ipconfig0 ip=dhcp
   root@pve01:~# qm start 5002
   ```
   Regarde son disque : `qm config 5002`, puis côté stockage (`lvs -o lv_name,pool_lv,origin,data_percent` pour du LVM-thin, `zfs list -o name,origin,used,refer` pour du ZFS). Combien d'espace occupe-t-il ? Qu'est-ce que `origin` ?
2. Snapshot sans RAM :
   ```
   root@pve01:~# qm snapshot 5002 etat-initial --description "Juste après le clone"
   ```
3. Dans la VM (`ssh admin@<IP>` depuis `adm01`), crée un fichier `/home/admin/marqueur`, installe un paquet, et lance un processus repérable (`tmux new -d -s compteur 'i=0; while :; do i=$((i+1)); echo $i > /tmp/compteur; sleep 1; done'`).
4. Snapshot avec RAM :
   ```
   root@pve01:~# qm snapshot 5002 avec-ram --vmstate 1 --description "Avec processus en cours"
   ```
   Où est stocké l'état mémoire ? Quelle taille ? Combien de temps la VM a-t-elle été figée ?
5. Restaure `etat-initial` (`qm rollback 5002 etat-initial`). Dans quel état est la VM ? Démarre-la, vérifie que le marqueur et le paquet ont disparu.
6. Restaure `avec-ram`. Dans quel état est la VM ? Le compteur tourne-t-il encore, et à partir de quelle valeur ? Que vaut `uptime` ?
7. Crée le clone complet et compare : durée, espace occupé, dépendance au template.
   ```
   root@pve01:~# qm clone 9000 5003 --name sbx03 --pool lab --full 1 --storage <STOCKAGE-VMS>
   ```
8. Sans exécuter de commande destructrice : que se passerait-il si on tentait de supprimer le template 9000 maintenant ? Et si le volume de base du template était corrompu ? Écris ta réponse.
9. Remplis pour Julien un tableau « besoin → outil » (snapshot, clone lié, clone complet, sauvegarde) avec au moins six besoins concrets, dont « garder une copie d'une VM pendant six mois » et « revenir en arrière après une mise à jour ratée ».
10. Lance la vérification, puis détruis 5002 et 5003 (`qm destroy <VMID> --purge`).

**Critères de réussite**
- [ ] `sbx02` est un clone lié (disque adossé au volume `base-9000-…`) avec les snapshots `etat-initial` (sans RAM) et `avec-ram` (avec état mémoire).
- [ ] `sbx03` a un disque indépendant, sans référence au template.
- [ ] Les observations des étapes 5 et 6 (état de la VM, marqueur, compteur, uptime) sont notées.
- [ ] Le tableau « besoin → outil » est rédigé.

**Vérification** : `lab/bin/check 00 19` (avant de détruire 5002 et 5003)

<details><summary>Indice 1</summary>

Un clone lié ne copie rien : son disque est un instantané (*snapshot*) en écriture du volume de base du template. Les blocs modifiés par la VM sont les seuls à occuper de la place.
</details>

<details><summary>Indice 2</summary>

`qm listsnapshot 5002` montre l'arbre des snapshots et la position courante (`current`). La configuration complète, snapshots compris, est lisible dans `/etc/pve/qemu-server/5002.conf` : cherche la ligne `vmstate` et la ligne `parent`.
</details>

**Pour aller plus loin** (facultatif) : crée un clone complet **à partir d'un snapshot** (`qm clone 5002 5004 --snapname etat-initial --full 1`) et explique pourquoi un clone lié depuis un snapshot n'est pas proposé.

---

### M00-E20 — Réinstaller `hp01` en Proxmox Backup Server  `LAB` `★★★`

> ⚠️ **Attention — prérequis bloquant** : ne commence pas cet exercice tant que **M00-E04 n'est pas validé** : photos copiées sur au moins un autre support, sommes de contrôle comparées sans écart, copie relue depuis ce support. L'installation de PBS **efface les disques** de `hp01`. Il n'y aura pas de retour arrière.

> **Ticket CHG-120** — *De : Claire Morel*
> Changement approuvé au CAB de jeudi : réaffectation de l'ancien serveur PAR2 en serveur de sauvegarde. Prérequis bloquant : migration des photos validée (E04), preuves jointes au ticket. Fenêtre : ce week-end. Je veux un serveur à jour, nommé selon nos conventions, joignable sur le LAN pour l'instant et prêt à recevoir le tunnel inter-sites.

**Objectifs pédagogiques**
- Préparer un changement irréversible : liste de contrôle *go/no-go*, preuves, plan.
- Utiliser l'iLO (console virtuelle, média virtuel) quand la licence le permet.
- Installer Proxmox Backup Server 4.x et choisir une disposition des disques qui sépare système et données.
- Configurer le réseau (LAN + adresse PAR2 sur un pont sans port), les dépôts et les mises à jour.

**Prérequis** : **M00-E04 validé**, M00-E15.
**Durée indicative** : 3 h.

**Contexte technique**
- Nom : `pbs01`, FQDN `pbs01.par2.medisphere.internal`.
- Réseau LAN : `<IP-HP01-LAN>` **fixe** (réservation DHCP sur la box, ou adresse statique hors de sa plage DHCP), passerelle `<IP-BOX>`, DNS `<DNS-AMONT>` (`dns01` ne sera joignable qu'après le tunnel).
- Adresse PAR2 : 10.20.10.10/24 sur `vmbr1`, pont **sans port physique** et sans passerelle.
- ISO : Proxmox Backup Server 4.x depuis le site de Proxmox, empreinte SHA-256 vérifiée.
- Dépôts au format deb822 (`.sources`) : `pbs-no-subscription` actif, `pbs-enterprise` désactivé.
- `<IP-ILO>` : adresse de l'iLO de `hp01` (à noter dans `lab/inventaire-local.md`).

**Travail demandé**
1. **Go/no-go.** Écris la liste de contrôle et coche-la avec des preuves : E04 validé (fichier de sommes, résultat de la comparaison, emplacement de la copie) ; accès à l'iLO (ou écran + clavier) ; ISO vérifiée ; inventaire matériel de `hp01` relevé (`lsblk`, modèle et taille des disques, état SMART, cartes réseau et adresses MAC). Ne continue que si tout est coché.
2. **iLO.** Connecte-toi à l'interface iLO. Relève la version du micrologiciel et la licence. Selon la licence, monte l'ISO en média virtuel et ouvre la console distante ; sinon prépare une clé USB.
   > ⚠️ **Attention** : si tu prépares une clé USB avec `dd`, vérifie trois fois le périphérique cible (`lsblk`). Une erreur de lettre efface un disque de ton poste.
3. **Disposition des disques.** Décide comment séparer le système du futur datastore `ds-lab` (E22) : disque dédié s'il y en a plusieurs ; sinon, avec un disque unique, réserver de l'espace à l'installation (options avancées de l'installateur) pour un volume ou une partition dédiés. Choisis le système de fichiers (ext4, XFS ou ZFS) et justifie au regard du matériel (16 Go de RAM, disque(s) mécanique(s)).
4. **Installation.** Démarre sur l'ISO (menu de démarrage unique), installe : disque cible et options, fuseau Europe/Paris, mot de passe root robuste (stocké dans ton gestionnaire de mots de passe), adresse e-mail d'alerte, interface de gestion, FQDN, adresse, passerelle, DNS.
5. **Premier accès.** `https://<IP-HP01-LAN>:8007`. Relève l'empreinte du certificat (`proxmox-backup-manager cert info`).
6. **Dépôts et mises à jour.** Désactive le dépôt d'entreprise, active `pbs-no-subscription`, mets à jour avec `apt update && apt full-upgrade` (jamais `apt upgrade` seul sur un produit Proxmox), redémarre si le noyau a changé. Contrôle `proxmox-backup-manager versions`.
7. **Réseau PAR2.** Ajoute `vmbr1` (sans port, 10.20.10.10/24) dans `/etc/network/interfaces`, applique avec `ifreload -a`, vérifie. Pourquoi l'état `NO-CARRIER` du pont n'empêchera-t-il pas d'atteindre l'adresse ?
8. **Accès d'administration.** Le pare-feu de `gw01` ne laisse pas le lab joindre le LAN maison (sauf `pve01`) : autorise `adm01` (MGMT) vers `<IP-HP01-LAN>` en SSH et sur le port 8007. Dépose la clé publique de `adm01` pour `root` sur `pbs01`, connecte-toi une première fois depuis `adm01` en `root@<IP-HP01-LAN>` pour enregistrer la clé d'hôte, et vérifie que `WB_PBS_LAN` est renseignée dans `lab/lab.env`.
9. **Temps.** Vérifie le fuseau et la synchronisation (`timedatectl`, `chronyc tracking`). Le basculement vers `gw01` comme source de temps se fera en E31.
10. Mets à jour `lab/inventaire-local.md` : iLO, numéro de série, disques, disposition retenue, adresses.

**Critères de réussite**
- [ ] La liste go/no-go est rédigée et toutes ses preuves sont jointes.
- [ ] L'interface web PBS répond sur `https://<IP-HP01-LAN>:8007`.
- [ ] `proxmox-backup-manager versions` indique une version 4.x, sans mise à jour Proxmox en attente.
- [ ] Dépôt d'entreprise désactivé, `pbs-no-subscription` actif, `apt update` sans erreur.
- [ ] `hostname -f` renvoie `pbs01.par2.medisphere.internal` ; `vmbr1` porte 10.20.10.10/24.
- [ ] `adm01` se connecte en `root` par clé.
- [ ] L'espace prévu pour le datastore est distinct du système de fichiers racine.

**Vérification** : `lab/bin/check 00 20` (depuis `adm01` ; avant E21, la vérification passe par `WB_PBS_LAN`)

<details><summary>Indice 1</summary>

Sur un serveur HP de cette génération (iLO 4), la console graphique distante et le média virtuel dépendent de la licence (« iLO Advanced »). Les versions récentes du micrologiciel proposent une console HTML5. La touche F11 au démarrage donne le menu de démarrage unique.
</details>

<details><summary>Indice 2</summary>

La documentation de l'installateur PBS décrit les options avancées LVM (`hdsize`, `swapsize`, `minfree`) et ZFS (`ashift`, `compress`, `hdsize`…). Avec ext4 ou XFS, l'installateur crée un groupe de volumes `pbs` : l'espace laissé libre (`minfree`) peut ensuite accueillir un volume logique dédié au datastore.
</details>

<details><summary>Indice 3</summary>

Une adresse IP appartient à la machine, pas à l'interface : Linux accepte un paquet destiné à une adresse locale quelle que soit l'interface d'arrivée (`ip route show table local`). Le pont n'a besoin d'être « UP » qu'administrativement.
</details>

**Pour aller plus loin** (facultatif) : configure l'iLO lui-même (compte nominatif au lieu du compte d'usine, mot de passe changé, version du micrologiciel à jour). Le module 11 le pilotera en Redfish.

---

### M00-E21 — Tunnel inter-sites PAR1 ↔ PAR2  `LAB` `★★★`

> **Ticket CHG-121** — *De : Sophie Laurent*
> Les sauvegardes contiendront des données de santé. **Aucune sauvegarde ne traverse un réseau en clair**, même « le LAN de la maison ». Le site PAR2 n'est joignable que par le tunnel chiffré, et le serveur de sauvegarde n'expose rien d'autre que le strict nécessaire. Je veux un schéma des flux dans le ticket.

**Objectifs pédagogiques**
- Monter un tunnel WireGuard site à site et les routes associées.
- Raisonner le routage aller **et retour** avec un hôte multi-domicilié (*multi-homed*).
- Filtrer les deux extrémités, sans se couper l'accès.
- Comprendre l'effet du tunnel sur la MTU.

**Prérequis** : M00-E16, M00-E20.
**Durée indicative** : 3 h.

**Contexte technique**
- `wg0` : `gw01` 10.255.0.1/30 ↔ `pbs01` 10.255.0.2/30, UDP 51820 des deux côtés, fichiers `/etc/wireguard/wg0.conf`, services `wg-quick@wg0`.
- Routes : 10.20.0.0/16 par `wg0` sur `gw01` ; 10.10.0.0/16 (et le VPN d'administration 10.255.1.0/24) par `wg0` sur `pbs01`, **avec 10.20.10.10 comme adresse source**. Les règles de PAR1 désignent PAR2 par 10.20.0.0/16 : ce que `pbs01` émet lui-même vers PAR1 doit partir de son adresse de site, pas de son adresse de tunnel.
- `pve01` joint 10.20.0.0/16 par sa route statique via `<IP-GW01-WAN>` (vérifie qu'elle existe).
- Flux à permettre vers `pbs01` : `adm01` et le VPN d'administration (SSH, interface web, ping) ; `pve01` (port 8007, sauvegardes). Flux de `pbs01` vers PAR1 : DNS vers `dns01` (le temps viendra en M00-E31).
- `pbs01` n'a pas le pare-feu intégré de Proxmox VE : choisis l'outil de filtrage et justifie.

**Travail demandé**
1. **Avant de configurer**, dessine (texte ou schéma) le trajet aller et retour de trois flux : `adm01` → `pbs01`:8007, poste (VPN) → `pbs01`:8007, `pve01` → `pbs01`:8007. Pour chaque retour, indique quelle table de routage décide et par quelle interface le paquet repart. L'un des trois pose un vrai problème : identifie-le, propose au moins deux solutions, choisis-en une et justifie.
2. Génère les clés des deux côtés (`wireguard-tools` sur `pbs01`). Écris les deux `wg0.conf` : adresses, port, pair, point d'accès, `AllowedIPs`, maintien de session. Pense aux réseaux que `pbs01` doit renvoyer dans le tunnel (le VPN d'administration en fait partie) et à l'adresse source de ces routes (contexte technique).
3. Active les deux services, vérifie la poignée de main et les routes (`ip route get` des deux côtés ; côté `pbs01`, regarde aussi l'adresse source choisie).
4. Pare-feu de `gw01` : WireGuard depuis `<IP-HP01-LAN>` seulement ; transferts MGMT → PAR2, VPN → PAR2 MGMT, `pve01` → `pbs01`:8007 ; la solution retenue à l'étape 1. Le DNS de PAR2 vers `dns01` est déjà couvert depuis E13 si tes règles désignent PAR2 par 10.20.0.0/16.
5. Pare-feu de `pbs01` : politique `drop` en entrée ; WireGuard depuis `gw01` ; SSH et 8007 uniquement à travers le tunnel et pour les sources prévues ; un accès SSH de secours depuis le LAN maison ; ICMP utiles.
   > ⚠️ **Attention** : une erreur te coupe l'accès à `pbs01`. Avant d'appliquer, programme un retour arrière automatique (par exemple `systemd-run --on-active=5min /usr/sbin/nft flush ruleset`), applique, teste depuis une **nouvelle** session, puis annule le retour arrière (`systemctl stop` de l'unité créée). Garde l'iLO ouvert.
6. Vérifie que l'interface web n'est plus joignable sur `<IP-HP01-LAN>` depuis le LAN, et qu'elle l'est sur 10.20.10.10 depuis `adm01` et depuis ton poste par le VPN.
7. **Preuve de chiffrement** : pendant une connexion de `pve01` vers 10.20.10.10:8007, capture sur l'interface LAN de `pbs01` (`tcpdump -ni <NIC-HP01-LAN> host <IP-PVE01>`). Que doit-on voir, et surtout ne pas voir ?
8. **MTU** : relève la MTU de `wg0` des deux côtés. Depuis `adm01`, trouve la plus grande charge ICMP qui passe sans fragmentation vers 10.20.10.10 (`ping -M do -s <TAILLE>`), explique le chiffre, et ce qui se passe avec une taille au-dessus. Explique en quelques lignes ce dont dépend un transfert TCP de `pve01` (MSS 1460) vers `pbs01` à travers ce tunnel. Ne corrige rien : M00-E41 y revient.
9. Mets à jour `~/.ssh/config` si besoin et vérifie `ssh pbs01` depuis `adm01`.

**Critères de réussite**
- [ ] `wg show wg0` montre une poignée de main récente des deux côtés.
- [ ] Sur `pbs01`, `ip route get 10.10.10.10` passe par `wg0` avec la source 10.20.10.10, de façon persistante (redémarrage de `wg-quick@wg0`).
- [ ] Depuis `adm01` : `ssh pbs01` et `https://10.20.10.10:8007` fonctionnent ; idem depuis ton poste par le VPN.
- [ ] Depuis `pve01` : 10.20.10.10:8007 est joignable, et la capture sur le LAN de `pbs01` ne montre que de l'UDP 51820 entre `gw01` et `hp01`.
- [ ] L'interface web PBS n'est plus joignable sur `<IP-HP01-LAN>`.
- [ ] Le pare-feu de `pbs01` est en politique `drop`, persistant après redémarrage.
- [ ] Le schéma des flux et l'analyse MTU sont dans le ticket.

**Vérification** : `lab/bin/check 00 21`

<details><summary>Indice 1</summary>

`pbs01` a deux chemins vers le LAN maison : sa carte réseau (route connectée) et… aucun autre. Une réponse destinée à une adresse du LAN maison partira donc directement par la carte, quel que soit le chemin pris à l'aller. Deux familles de solutions : faire en sorte que la source vue par `pbs01` ne soit plus une adresse du LAN, ou faire mentir la table de routage de `pbs01` pour cette destination.
</details>

<details><summary>Indice 2</summary>

`wg-quick` calcule la MTU de l'interface à partir de celle de la route vers le pair, moins le surcoût de WireGuard. Pour un `ping -M do`, la taille passée à `-s` ne compte pas les en-têtes IP et ICMP. Les routes que `wg-quick` déduit des `AllowedIPs` n'ont pas d'adresse source préférée : lis dans `man wg-quick` les options `Table` et `PostUp`/`PreDown`, et dans `man ip-route` le paramètre `src`.
</details>

<details><summary>Indice 3</summary>

Pour tester un port sans outil : `timeout 3 bash -c '</dev/tcp/10.20.10.10/8007' && echo ouvert`. Pour voir quelle règle nftables jette un paquet : ajoute temporairement un compteur ou une règle `log` juste avant la fin de la chaîne, ou utilise `nft monitor trace` avec une règle `meta nftrace set 1`.
</details>

**Pour aller plus loin** (facultatif) : fais pointer le résolveur de `pbs01` vers `dns01` à travers le tunnel, et liste ce qui casse si le tunnel tombe. Le module 07 généralise WireGuard en maillage multi-sites avec routage dynamique.

---
### M00-E22 — Datastore, rétention et tâches de sauvegarde  `LAB` `★★`

> **Ticket PLAT-122** — *De : Nadia Roussel*
> Sans sauvegarde testée, je refuse de prendre l'astreinte sur le socle. Je veux : une sauvegarde chaque nuit de tout le pool `lab` vers PAR2, rétention 7 quotidiennes / 4 hebdomadaires / 6 mensuelles, vérification d'intégrité régulière et nettoyage de l'espace. Et un compte de sauvegarde qui **ne peut rien supprimer** : si quelqu'un prend la main sur l'hyperviseur, il ne doit pas pouvoir effacer nos sauvegardes.

**Objectifs pédagogiques**
- Créer un datastore PBS et comprendre sa structure (magasin de *chunks*, index, namespaces).
- Appliquer le modèle de permissions de PBS (utilisateur, jeton, ACL par datastore ou namespace).
- Raccorder Proxmox VE à PBS en épinglant le certificat.
- Planifier sauvegarde, *prune*, *garbage collection* et vérification, et comprendre ce que fait chacun.

**Prérequis** : M00-E21.
**Durée indicative** : 2 h.

**Contexte technique**
- Datastore `ds-lab` sur l'espace réservé en E20 (par exemple `/mnt/datastore/ds-lab`), namespace `par1`.
- Compte `wb-backup@pbs`, jeton `pve01` (identifiant complet `wb-backup@pbs!pve01`), rôle `DatastoreBackup`.
- Côté `pve01` : stockage `pbs-par2` (serveur 10.20.10.10, datastore `ds-lab`, namespace `par1`).
- Tâche de sauvegarde : pool `lab`, mode `snapshot`, chaque nuit à 02:30.
- Rétention : `keep-daily 7`, `keep-weekly 4`, `keep-monthly 6`.
- `hp01` a un seul cœur de calcul modeste et des disques mécaniques : les tâches lourdes ne doivent pas se chevaucher.

**Travail demandé**
1. Crée le datastore sur l'espace dédié. Explore sa structure (`ls -la`, `ls .chunks | head`, `ls .chunks | wc -l`) : pourquoi ces 65 536 sous-répertoires créés d'avance ?
2. Crée le namespace `par1` (interface web ou `proxmox-backup-client namespace create`).
3. Crée l'utilisateur et le jeton. Pose les ACL. Avec quel rôle ? Sur `/datastore/ds-lab` ou sur `/datastore/ds-lab/par1` ? Pour l'utilisateur, le jeton, ou les deux ? Vérifie avec `proxmox-backup-manager user permissions`.
4. Récupère l'empreinte du certificat de PBS (`proxmox-backup-manager cert info`) et ajoute le stockage sur `pve01` avec `pvesm add pbs …`, en utilisant le jeton (le secret ne doit pas rester dans l'historique de `root@pve01`). Contrôle `pvesm status`.
5. Crée la tâche de sauvegarde (interface *Datacenter → Backup* ou `pvesh create /cluster/backup`). Où faire la purge des anciennes sauvegardes : dans la tâche de `pve01`, ou sur PBS ? Le rôle choisi à l'étape 3 tranche la question : explique.
6. Exécute la tâche une première fois tout de suite. Suis le journal côté `pve01` et côté PBS. Relance la sauvegarde d'une VM : compare la durée et la ligne `dirty-bitmap` du journal entre les deux passages.
7. Côté PBS, planifie : la purge (*prune job*) du namespace `par1` avec la rétention demandée ; le *garbage collection* du datastore ; une tâche de vérification. Choisis les horaires pour qu'ils ne se chevauchent pas entre eux ni avec la sauvegarde, et justifie l'ordre. Décide si la vérification des nouvelles sauvegardes (`verify-new`) est activée sur ce matériel.
8. Utilise le simulateur de rétention de la documentation PBS (*prune simulator*) pour vérifier combien de points de restauration tu garderas au bout d'un an.
9. Prouve que le compte de sauvegarde ne peut rien effacer : depuis `pve01`, lance une sauvegarde supplémentaire de `dns01`, puis tente de supprimer **cette** sauvegarde-là (`pvesm free`).
   > ⚠️ **Attention** : ne tente cette suppression que sur une sauvegarde supplémentaire créée pour l'occasion. Si le refus attendu n'arrive pas, tu ne perds qu'elle.
10. Vérifie qu'aucune VM du pool n'échappe aux sauvegardes (`pvesh get /cluster/backup-info/not-backed-up`).

**Critères de réussite**
- [ ] `pvesm status` sur `pve01` : `pbs-par2` actif, empreinte épinglée, connexion par jeton.
- [ ] Chaque VM du socle a au moins une sauvegarde dans `pbs-par2` (namespace `par1`).
- [ ] La tâche nocturne couvre le pool `lab`, en mode `snapshot`.
- [ ] PBS : purge (7/4/6), *garbage collection* et vérification planifiés sur `ds-lab`, sans chevauchement.
- [ ] La suppression d'une sauvegarde depuis `pve01` est refusée.
- [ ] Le second passage d'une VM utilise le *dirty bitmap* (ligne du journal à l'appui).

**Vérification** : `lab/bin/check 00 22`

<details><summary>Indice 1</summary>

Lis la liste des rôles PBS dans la documentation (*User Management → Access Roles*) : la différence entre `DatastoreBackup` et `DatastorePowerUser` est exactement celle dont Nadia parle. Les jetons PBS ont besoin de leurs propres ACL, et leurs droits sont limités par ceux de leur utilisateur.
</details>

<details><summary>Indice 2</summary>

`proxmox-backup-manager` : sous-commandes `datastore`, `user`, `acl`, `prune-job`, `verify-job`. Le *garbage collection* se planifie dans la configuration du datastore (`gc-schedule`). Les horaires suivent la syntaxe des événements calendaires de systemd (`02:30`, `sat 04:00`…).
</details>

<details><summary>Indice 3</summary>

Après un *prune*, l'espace disque ne baisse pas. Ce n'est pas un bug : lis la section *Garbage Collection* de la documentation, en particulier le délai appliqué aux *chunks*.
</details>

**Pour aller plus loin** (facultatif) : configure une rétention différente pour un futur namespace `par1/critique`. Le module 09 ajoutera une synchronisation vers un second datastore ; M00-E36 chiffre les sauvegardes côté client.

---

### M00-E23 — Restaurer une VM et un fichier  `LAB` `★★`

> **Ticket PLAT-123** — *De : Nadia Roussel*
> Une sauvegarde qu'on n'a jamais restaurée n'existe pas. Restaure `dns01` à côté de la vraie, sans la perturber, prouve qu'elle démarre et que ses données sont là. Ensuite, récupère juste le fichier de configuration dnsmasq de la dernière sauvegarde, comme si quelqu'un l'avait cassé en production. Chronomètre les deux : les temps iront dans le runbook.

**Objectifs pédagogiques**
- Restaurer une VM complète sous un autre VMID sans créer de conflit sur le réseau.
- Restaurer un fichier isolé depuis une sauvegarde d'image disque.
- Connaître la restauration à chaud (*live-restore*) et ses risques.
- Mesurer un temps de restauration réel.

**Prérequis** : M00-E22.
**Durée indicative** : 1 h 30.

**Contexte technique**
- VM restaurée : VMID 5090 (plage des restaurations de test 5090-5099), nom `rst-dns01`, pool `lab`.
- `dns01` a une adresse statique (10.10.20.10) et un nom posés par cloud-init : une copie qui démarre telle quelle sur le VLAN 20 crée un doublon d'adresse **sur le serveur DNS de tout le lab**.
- Fichier à restaurer : `/etc/dnsmasq.d/medisphere.conf`, à déposer dans `/root/restore-E23/` sur `pve01`, quelle que soit la méthode.

**Travail demandé**
1. Liste les sauvegardes de `dns01` (`pvesm list pbs-par2 --vmid 1002`) et choisis la plus récente. Démarre le chronomètre.
2. Restaure vers 5090 avec `qmrestore`, sans démarrer la VM : choisis le stockage cible, le pool, et demande de nouvelles adresses MAC. Lis `qmrestore --help` avant.
3. **Avant le premier démarrage**, neutralise les conflits : nom de la VM, carte réseau (débranchée, ou déplacée dans le VLAN SANDBOX). Réfléchis aussi à ce que cloud-init risque de faire au premier démarrage d'une VM dont la configuration a changé (identifiant d'instance, clés d'hôte SSH).
4. Démarre 5090 et vérifie, sans réseau, que le système et la configuration dnsmasq sont présents : par l'agent QEMU (`qm guest exec`) ou par la console série (`qm terminal 5090`, si un compte a un mot de passe). Arrête le chronomètre : c'est ton temps de restauration complète.
5. Restauration de fichier : par l'interface (*Storage → pbs-par2 → Backups → File Restore*) **ou** en ligne de commande avec `proxmox-file-restore list` puis `extract`, en t'authentifiant avec le jeton du stockage sans afficher son secret. Dépose le fichier dans `/root/restore-E23/` sur `pve01`, compare-le à la version en service (`diff`). Chronomètre aussi.
6. Lis la documentation de la restauration à chaud (`qmrestore --live-restore`). Dans le ticket : quand l'utiliser, quel risque, pourquoi pas ici.
7. Lance la vérification, puis détruis 5090 (`qm destroy 5090 --purge`).

**Critères de réussite**
- [ ] 5090 a été restaurée depuis `pbs-par2` sans erreur, et n'a jamais eu de carte active dans le VLAN 20.
- [ ] `dns01` a répondu sans interruption pendant tout l'exercice.
- [ ] `/root/restore-E23/medisphere.conf` existe sur `pve01` ; les éventuelles différences avec la version en service sont expliquées.
- [ ] Les deux temps de restauration sont notés, avec le débit observé.
- [ ] Le paragraphe sur la restauration à chaud est rédigé.

**Vérification** : `lab/bin/check 00 23`

<details><summary>Indice 1</summary>

`qmrestore <archive> <vmid>` accepte notamment `--storage`, `--pool`, `--unique` et `--live-restore`. L'archive se désigne par son identifiant de volume, tel que l'affiche `pvesm list`.
</details>

<details><summary>Indice 2</summary>

Une carte réseau peut rester déclarée mais débranchée : option `link_down=1` de `netN` dans `qm set`. Attention à reprendre l'adresse MAC existante dans la nouvelle définition, sinon une nouvelle est générée.
</details>

<details><summary>Indice 3</summary>

`proxmox-file-restore` lit le dépôt, le namespace et le secret comme `proxmox-backup-client` : options `--repository` et `--ns`, variables `PBS_PASSWORD` (ou `PBS_PASSWORD_FILE`) et `PBS_FINGERPRINT`. Le secret du stockage `pbs-par2` est déjà sur `pve01`, dans `/etc/pve/priv/storage/`. Le chemin à explorer commence par le nom de l'archive disque (`list` à la racine `/` pour le découvrir).
</details>

**Pour aller plus loin** (facultatif) : restaure 5090 avec `--live-restore 1` sur une sauvegarde de `sbx02` (pas de `dns01`), et observe les performances disque pendant la restauration. M00-E37 chronomètre une restauration en conditions d'examen.

---

### M00-E24 — Questions d'exploitation : sauvegarde  `Q` `★★`

> **Ticket PLAT-124** — *De : Claire Morel*
> Avant de présenter notre stratégie de sauvegarde au comité HDS, je veux m'assurer que tu sais défendre chaque choix. Réponds par écrit, sans documentation pour la première passe, puis complète avec.

**Prérequis** : M00-E22, M00-E23.
**Durée indicative** : 1 h.

Réponds par écrit. Pour les QCM, justifie aussi pourquoi les autres propositions sont fausses.

1. **(QCM)** En mode `snapshot`, que fait réellement `vzdump` pour une VM QEMU sauvegardée vers PBS ?
   a) Il prend un snapshot du volume (LVM-thin, ZFS) puis copie ce snapshot.
   b) QEMU lit le disque pendant que la VM tourne ; quand l'invité veut écrire sur un bloc pas encore sauvegardé, ce bloc est d'abord envoyé à la sauvegarde.
   c) La VM est mise en pause pendant toute la sauvegarde.
   d) Ce mode exige des disques au format qcow2.
2. Qu'est-ce que le *dirty bitmap* d'une VM ? Où vit-il, qu'apporte-t-il, et dans quelles situations est-il perdu ? Que se passe-t-il alors à la sauvegarde suivante ?
3. Explique comment PBS déduplique : découpage des disques de VM et des sauvegardes de fichiers, identification des *chunks*, portée de la déduplication. Pourquoi les VMs issues du même template coûtent-elles peu à sauvegarder ?
4. **(QCM)** Tu supprimes par *prune* trente instantanés et `df` sur le datastore ne bouge pas. Pourquoi ?
   a) Le *prune* ne supprime que les index ; les *chunks* ne sont libérés que par le *garbage collection*, et seulement ceux qu'aucun index restant ne référence et non touchés depuis plus de 24 h environ.
   b) Le système de fichiers du datastore doit être monté avec `discard`.
   c) PBS conserve toujours une copie de secours pendant sept jours.
   d) Il faut lancer une vérification pour libérer l'espace.
5. Que vérifie exactement une tâche de vérification PBS, et que ne vérifie-t-elle pas ? À quoi servent les options « ignorer les sauvegardes déjà vérifiées » et « revérifier après N jours » ?
6. **(QCM)** Chiffrement côté client des sauvegardes PBS. Quelle affirmation est vraie ?
   a) La clé est stockée sur PBS, qui déchiffre à la restauration.
   b) La clé reste chez le client ; PBS ne stocke que des *chunks* chiffrés et la déduplication fonctionne entre les sauvegardes faites avec la même clé.
   c) En cas de perte de la clé, l'administrateur PBS peut restaurer avec le mot de passe root.
   d) Le chiffrement empêche les sauvegardes incrémentales.
7. Rappelle la règle 3-2-1 (et sa variante 3-2-1-1-0). Évalue honnêtement notre dispositif actuel (`pve01` → `pbs01` à PAR2 par le tunnel) : qu'est-ce qui est couvert, qu'est-ce qui manque ?
8. **(Calcul)** La sauvegarde tourne chaque nuit à 02:30. Un incident détruit les données d'une VM à 18:00. Quelle quantité de données perds-tu au pire ? Quel est le RPO de ce dispositif ? Tu as mesuré en E23 un débit de restauration ; quel serait le RTO pour une VM de 200 Go si ce débit se maintient ? Quels autres temps faut-il ajouter au RTO réel ?
9. Différence entre une sauvegarde cohérente « après plantage » (*crash-consistent*) et cohérente au niveau applicatif ? Que fait le *fs-freeze* déclenché via l'agent QEMU, et que ne garantit-il pas pour une base de données ?
10. **(QCM)** Une VM a l'option `agent` activée dans sa configuration Proxmox, mais l'agent n'est pas installé dans l'invité. Que se passe-t-il à la sauvegarde en mode `snapshot` ?
    a) La sauvegarde échoue.
    b) La sauvegarde se fait, sans gel des systèmes de fichiers, avec un avertissement dans le journal de la tâche.
    c) Proxmox bascule automatiquement en mode `stop`.
    d) Proxmox installe l'agent par le CD cloud-init.
11. Pourquoi un snapshot de VM n'est-il pas une sauvegarde ? Donne au moins trois raisons.
12. Dans quels cas choisirais-tu le mode `stop` plutôt que `snapshot` ? Quel est son coût ?
13. Ici, PBS est distant, sur disque mécanique, derrière un tunnel. Explique pourquoi une sauvegarde en mode `snapshot` peut **ralentir la VM sauvegardée**, et ce que propose l'option *fleecing* de Proxmox VE pour l'éviter.
14. Un attaquant obtient `root` sur `pve01`. Que peut-il faire, et ne pas faire, contre nos sauvegardes avec le jeton `wb-backup@pbs!pve01` ? Quelles mesures supplémentaires limiteraient encore les dégâts ?
15. **(QCM)** À propos des namespaces PBS, quelle affirmation est fausse ?
    a) Ils permettent des ACL distinctes par namespace.
    b) Ils permettent des tâches de purge et de vérification distinctes.
    c) Chaque namespace a son propre magasin de *chunks*, donc pas de déduplication entre namespaces.
    d) Deux namespaces peuvent contenir chacun un groupe `vm/100` sans conflit.
16. Rédige le plan de test de restauration que tu proposerais pour le socle : fréquence, périmètre, critères de réussite, mesures, traçabilité.
17. **(Calcul)** Six VMs de 32 Go (en moyenne 12 Go réellement occupés chacune, issues du même template), 2 % des données modifiées par jour, rétention 7/4/6. Estime l'ordre de grandeur de l'espace consommé sur `ds-lab` au bout d'un an. Quels facteurs rendent l'estimation imprécise (cite au moins trois) ?
18. **(QCM)** La restauration à chaud (*live-restore*) :
    a) démarre la VM avant la fin de la restauration, les blocs manquants étant lus à la demande depuis PBS ;
    b) n'est possible que depuis un stockage local ;
    c) est sans risque : en cas de coupure, la VM continue depuis le disque partiel ;
    d) est plus rapide en débit total qu'une restauration classique.

<details><summary>Indice</summary>

Pour 1, 2 et 13, lis la section *Backup and Restore* de la documentation de Proxmox VE (*Backup modes*, *Backup fleecing*). Pour 4 et 15, la documentation PBS (*Maintenance Tasks*, *Backup Namespaces*).
</details>

---

### M00-E25 — Runbooks « créer une VM » et « restaurer une VM »  `RED` `★★`

> **Ticket PLAT-125** — *De : Nadia Roussel*
> Je monte le planning d'astreinte. Il me faut deux runbooks utilisables à trois heures du matin par quelqu'un qui n'a pas construit le lab : **créer une VM dans le lab** et **restaurer une VM depuis PAR2**. Suis le modèle de l'équipe, et fais-les relire.

**Objectifs pédagogiques**
- Écrire une procédure opérationnelle exécutable sans connaissance préalable.
- Expliciter prérequis, points de décision, vérifications et retour arrière.
- Capitaliser sur les exercices E14, E18, E22 et E23 (mesures, pièges).

**Prérequis** : M00-E18, M00-E23.
**Durée indicative** : 2 h.

**Contexte technique** : c'est le premier document destiné à l'équipe. Il inaugure le **dépôt de documentation MédiSphère**, que tu crées dans cet exercice et que tous les livrables écrits du module rejoindront (ADR en E33, test de restauration en E37, journaux et comptes rendus du palier 4, dossier de livraison en E50) :
- dépôt Git local sur `adm01`, `~/medisphere` (variable `WB_DEPOT` de `lab/lab.env` ; il sera poussé sur GitLab au module 01) ;
- documentation du socle dans `docs/socle/`, runbooks dans `docs/socle/runbooks/`, ADR dans `docs/socle/adr/` ;
- noms des fichiers de cet exercice : `docs/socle/runbooks/RB-001-creer-une-vm.md` et `docs/socle/runbooks/RB-002-restaurer-une-vm.md`.

**Modèle de runbook de l'équipe Plateforme**

```markdown
# RB-<NNN> — <Titre à l'infinitif>

| Version | Auteur | Relu par | Date | Prochaine revue |
|---|---|---|---|---|

## Objet
Ce que la procédure permet d'obtenir, en une ou deux phrases.

## Quand l'utiliser / quand ne pas l'utiliser
Déclencheurs (ticket, alerte, demande) et contre-indications (renvoyer vers quel autre runbook).

## Prérequis
Accès et droits nécessaires, outils, informations à réunir AVANT de commencer
(liste cochable).

## Durée et impact
Durée estimée (mesurée), impact sur le service, besoin d'une fenêtre ou d'une validation.

## Étapes
Numérotées. Chaque étape : action (commande exacte, avec l'hôte), résultat attendu,
et que faire si le résultat diffère. Points de décision explicites (« si … alors aller à … »).

## Vérifications
Comment prouver que l'objectif est atteint (commandes et résultats attendus).

## Retour arrière
Comment revenir à l'état initial, à quel moment ce n'est plus possible.

## En cas d'échec / escalade
Symptômes connus et leur cause probable, à qui escalader et avec quelles informations.

## Contacts
Rôles (pas de numéros personnels dans le dépôt), canal d'astreinte.

## Historique
Date, auteur, modification.
```

**Travail demandé**
1. Crée le dépôt de documentation sur `adm01` (`git init`), avec l'arborescence `docs/socle/runbooks/` et `docs/socle/adr/`, et un premier commit.
2. Rédige **RB-001 — Créer une VM dans le lab** : à partir du template, en interface web ou en ligne de commande, avec choix du VMID selon les plages, pool, VLAN, cloud-init, vérification de l'accès, enregistrement DNS si l'adresse est statique.
3. Rédige **RB-002 — Restaurer une VM depuis PAR2** : deux cas, restauration à côté (test, récupération de fichiers) et restauration en remplacement de l'original (sinistre) ; choix de la sauvegarde ; gestion des conflits ; vérifications applicatives ; retour arrière ; temps mesurés en E23.
4. Contraintes communes : aucune valeur secrète ; toutes les valeurs du lab conformes au plan (VMID, VLAN, noms) ; les commandes indiquent l'hôte où les lancer ; chaque étape a un résultat attendu.
5. Fais relire chaque runbook « à froid » : par quelqu'un d'autre, ou par toi-même dans une semaine en l'exécutant à la lettre sur une VM de la sandbox. Note les corrections dans l'historique.
6. Commite les deux runbooks dans le dépôt de documentation.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Les deux runbooks suivent le modèle, toutes sections remplies.
- [ ] Chaque étape a une commande exacte (avec l'hôte) et un résultat attendu.
- [ ] RB-002 traite les deux cas et contient un point de décision sur le choix de la sauvegarde.
- [ ] Le retour arrière précise le moment à partir duquel il n'est plus possible.
- [ ] Une exécution « à la lettre » a été faite, et l'historique en garde la trace.
- [ ] `~/medisphere` est un dépôt Git ; les deux runbooks y sont commités dans `docs/socle/runbooks/`.

<details><summary>Indice</summary>

Un bon runbook se lit en diagonale sous stress : verbes à l'infinitif en tête d'étape, une action par étape, les résultats attendus copiés depuis une vraie exécution, les avertissements juste **avant** l'étape dangereuse, pas après.
</details>

---

### M00-E26 — Revue de la configuration nftables d'un stagiaire  `REV` `★★`

> **Ticket PLAT-126** — *De : Karim Benali*
> Lucas Martin, notre stagiaire, propose une nouvelle configuration nftables pour `gw01` (fichier `ressources/M00-E26/nftables.conf`). Il dit que « tout passe » sur sa VM de test. Fais-lui une vraie revue avant qu'il ouvre sa demande de fusion : chaque défaut avec sa gravité, l'impact concret et la correction. Puis propose la version corrigée. Sois exigeant mais pédagogue : c'est comme ça qu'il apprendra.

**Objectifs pédagogiques**
- Lire un jeu de règles comme un paquet le traverserait.
- Classer des défauts par nature (sécurité, fonctionnement, maintenabilité) et par gravité.
- Rédiger une revue utile : impact concret, correction précise, priorités.

**Prérequis** : M00-E10, M00-E13, M00-E14, M00-E16, M00-E21.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Le fichier est censé remplacer `/etc/nftables.conf` de `gw01` et couvrir tout ce que tu as construit jusqu'à la fin de ce palier : NAT sortant, VLANs, DNS, relais DHCP, VPN `wg1` (y compris l'accès à `pve01`), tunnel `wg0`, sauvegardes de `pve01` vers `pbs01`. Le NTP n'en fait pas encore partie (M00-E31). Dans ce fichier, `192.168.1.20` est l'adresse de `pve01`.
- Il contient entre 8 et 12 défauts de gravités variées, plus quelques maladresses mineures.

> ⚠️ **Attention** : ne charge jamais ce fichier sur `gw01`. Pour le tester, utilise un espace de noms réseau jetable sur `adm01` : `sudo unshare --net nft -c -f nftables.conf` (vérification seule), ou `sudo unshare --net sh -c 'nft -f nftables.conf && nft list ruleset'`.

**Travail demandé**
1. Lis le fichier une première fois sans rien noter. Puis suis à la main ces paquets, et note pour chacun ce qui arrive : un SYN vers le port 22 de `gw01` depuis une machine quelconque du LAN maison ; le même en IPv6 ; un ping de 10.10.70.20 (DMZ) vers `adm01` ; une réponse DNS de 1 400 octets que `dns01` renvoie tronquée à un client du VLAN 40 ; un ICMP « fragmentation needed » émis par `gw01` vers `pve01` pendant une sauvegarde ; un paquet de `adm01` vers `deb.debian.org` ; la réponse de `dns01` au relais DHCP ; un rechargement du fichier par `systemctl reload nftables`.
2. Rédige la revue sous forme de tableau : n°, ligne(s), défaut, catégorie (sécurité, fonctionnement, maintenabilité), gravité (critique, élevée, moyenne, faible), impact concret, correction.
3. Classe les défauts par ordre de traitement et explique ton ordre.
4. Propose la version corrigée complète, commentée, validée par `nft -c`.
5. Ajoute trois lignes de conseils à Lucas sur sa méthode de test (« tout passe sur ma VM »).

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 9 défauts identifiés, dont tous les défauts critiques et élevés du corrigé.
- [ ] Chaque défaut a un impact concret (pas « c'est mieux ») et une correction précise.
- [ ] La version corrigée passe `nft -c` et ne réintroduit aucun des défauts.
- [ ] La revue est rédigée pour être utile à Lucas (ton, priorités).

<details><summary>Indice 1</summary>

Trois défauts ne se voient que si l'on pense à autre chose qu'IPv4 en régime établi : IPv6, le rechargement du fichier, et l'inondation des journaux.
</details>

<details><summary>Indice 2</summary>

L'ordre des règles compte : une règle placée trop tôt peut en annuler d'autres (ou des besoins vitaux comme la découverte de MTU), une règle placée trop tard coûte à chaque paquet. Regarde aussi ce que « matche » réellement un motif `ens19*`, en entrée comme en sortie.
</details>

<details><summary>Indice 3</summary>

Relis la table `nat` avec cette question : qu'est-ce qui doit être masqué, derrière quelle adresse, et pourquoi ? (Pense à Internet, aux VLANs entre eux, et à `pve01` → `pbs01`.)
</details>

**Pour aller plus loin** (facultatif) : écris un petit test automatique de ta version corrigée : dans un espace de noms réseau, charge le jeu de règles et vérifie avec `nft list ruleset` (ou `nft -j list ruleset | jq`) la présence des invariants : politique `drop`, `flush ruleset`, table `inet`, aucune règle `log` sans `limit`. Le module 29 généralisera ces tests de configuration.
