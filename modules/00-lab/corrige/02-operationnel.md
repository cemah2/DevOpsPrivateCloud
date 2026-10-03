# Module 00 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les fichiers complets cités ici sont dans [`fichiers/`](fichiers/). Pour `gw01`, chaque exercice fournit un **extrait** à intégrer dans le `/etc/nftables.conf` construit en M00-E10 ([`fichiers/M00-E10/nftables.conf`](fichiers/M00-E10/nftables.conf)), avec son emplacement exact et les règles de E10 qu'il remplace (repérées M3, M5, M7, M8 dans ce fichier). Les extraits réutilisent les variables (`define`) de E10 sans les redéfinir : nftables refuse une double définition. La configuration consolidée de fin de palier est la version corrigée de M00-E26 : [`fichiers/M00-E26/nftables.conf`](fichiers/M00-E26/nftables.conf).

Points **non testés en conditions réelles** au moment de la rédaction (à confirmer par tes retours) : ils sont signalés « à vérifier » dans le texte.

---

### M00-E13 — DNS provisoire avec dnsmasq

**Solution**

1. Installation et état des lieux sur `dns01` :
   ```
   admin@dns01:~$ sudo apt update && sudo apt install -y dnsmasq bind9-dnsutils
   admin@dns01:~$ sudo ss -lntup 'sport = :53'
   ```
   Si `systemd-resolved` est actif, il écoute sur 127.0.0.53 et 127.0.0.54. Deux options : le laisser (dnsmasq écoutera seulement sur 127.0.0.1 et 10.10.20.10 grâce à `bind-interfaces`), ou désactiver son *stub* (`DNSStubListener=no` dans `/etc/systemd/resolved.conf.d/`). Le corrigé garde la première : moins de changements, et l'écoute ciblée est de toute façon souhaitable.

2. Configuration complète : [`fichiers/M00-E13/medisphere.conf`](fichiers/M00-E13/medisphere.conf). Les lignes qui portent la solution :
   ```
   listen-address=127.0.0.1,10.10.20.10
   bind-interfaces
   no-resolv
   server=<DNS-AMONT-1>
   domain-needed
   bogus-priv
   local=/medisphere.internal/
   local=/10.10.in-addr.arpa/
   local=/20.10.in-addr.arpa/
   host-record=adm01.par1.medisphere.internal,10.10.10.10
   host-record=pbs01.par2.medisphere.internal,pbs01.par1.medisphere.internal,10.20.10.10
   ptr-record=1.20.10.10.in-addr.arpa,gw01.par1.medisphere.internal
   ```

3. Lancement par Debian et validation :
   ```
   admin@dns01:~$ systemctl cat dnsmasq
   admin@dns01:~$ sudo systemctl restart dnsmasq
   admin@dns01:~$ journalctl -u dnsmasq -n 20 --no-pager
   admin@dns01:~$ ps -o args -C dnsmasq
   ```
   L'unité Debian exécute une vérification de configuration avant le démarrage (`ExecStartPre=` vers un script d'aide du paquet ; nom exact à vérifier dans ta sortie de `systemctl cat`) : un fichier invalide empêche le démarrage au lieu de lancer un service à moitié configuré. La ligne de commande du processus montre que le répertoire `/etc/dnsmasq.d` est passé en option (`-7 /etc/dnsmasq.d,…`) : un `dnsmasq --test` lancé à la main **sans** cette option ne lit pas ton fichier et répond « syntax check OK » à tort. Pour tester à la main, reprends les options affichées par `ps`.

4. Pare-feu de `gw01` : [`fichiers/M00-E13/gw01-nftables-extrait.nft`](fichiers/M00-E13/gw01-nftables-extrait.nft), dans la chaîne `forward` après les règles `ct state` :
   ```
   ip saddr { $NETS_LAB, $NETS_PAR2, $NET_VPN } ip daddr $DNS01 meta l4proto { tcp, udp } th dport 53 accept
   iifname $V_INFRA ip saddr $DNS01 oifname $WAN meta l4proto { tcp, udp } th dport 53 accept
   ```
   ```
   root@gw01:~# nft -c -f /etc/nftables.conf && systemctl reload nftables
   root@gw01:~# nft list chain inet filter forward
   ```

5. Bascule des clients sur 10.10.20.10 :
   - `gw01` : [`fichiers/M00-E13/gw01-resolv.conf`](fichiers/M00-E13/gw01-resolv.conf). Vérifie d'abord qu'aucun gestionnaire n'écrit ce fichier (`ls -l /etc/resolv.conf` : un lien symbolique signale `systemd-resolved` ou `resolvconf`).
   - `adm01` et `dns01` : E12 leur a donné `<DNS-PUBLIC>`. Corrige **à la fois** dans Proxmox (pour les prochaines régénérations du lecteur cloud-init) et dans la VM (effet immédiat) :
     ```
     root@pve01:~# qm set 1001 --nameserver 10.10.20.10 --searchdomain par1.medisphere.internal
     root@pve01:~# qm set 1002 --nameserver 10.10.20.10 --searchdomain par1.medisphere.internal
     admin@adm01:~$ ls -l /etc/resolv.conf; resolvectl status 2>/dev/null | head -n 15
     ```
     Dans la VM, modifie la source réelle de la configuration (à vérifier selon l'image : avec netplan et `systemd-resolved`, la liste `nameservers` de `/etc/netplan/50-cloud-init.yaml` puis `sudo netplan apply` ; avec ifupdown, la ligne `dns-nameservers` du fichier de `/etc/network/interfaces.d/` écrit par cloud-init). Autre voie : redémarrer la VM pour que cloud-init applique la nouvelle configuration, en acceptant une éventuelle régénération des clés d'hôte SSH (voir les pièges).
   - Futures VMs : `qm config 9000 | grep -E '^(nameserver|searchdomain)'` doit afficher 10.10.20.10 et `par1.medisphere.internal` (posés en E11) : rien à changer.

6. Tests depuis `adm01` :
   ```
   admin@adm01:~$ dig adm01.par1.medisphere.internal
   ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 4242
   ;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
   ;; ANSWER SECTION:
   adm01.par1.medisphere.internal. 60 IN	A	10.10.10.10
   ;; SERVER: 10.10.20.10#53(10.10.20.10) (UDP)

   admin@adm01:~$ dig +short -x 10.10.20.1
   gw01.par1.medisphere.internal.
   admin@adm01:~$ getent hosts dns01
   10.10.20.10     dns01.par1.medisphere.internal
   admin@adm01:~$ dig deb.debian.org | grep -E 'status|flags'
   ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1717
   ;; flags: qr rd ra; QUERY: 1, ANSWER: 3, AUTHORITY: 0, ADDITIONAL: 1
   admin@adm01:~$ dig nexistepas.par1.medisphere.internal | grep status
   ;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 2323
   admin@adm01:~$ dig +tcp dns01.par1.medisphere.internal | grep SERVER
   ;; SERVER: 10.10.20.10#53(10.10.20.10) (TCP)
   ```
   Preuve que le NXDOMAIN est local : active `log-queries`, redémarre, et observe :
   ```
   admin@dns01:~$ journalctl -u dnsmasq -f
   dnsmasq[812]: query[A] nexistepas.par1.medisphere.internal from 10.10.10.10
   dnsmasq[812]: config nexistepas.par1.medisphere.internal is NXDOMAIN
   dnsmasq[812]: query[A] deb.debian.org from 10.10.10.10
   dnsmasq[812]: forwarded deb.debian.org to <DNS-AMONT-1>
   ```
   « config … is NXDOMAIN » : réponse tirée de la configuration (`local=`), aucune ligne `forwarded`. Désactive `log-queries` ensuite.

**Explications**

- **Données locales et relais.** dnsmasq n'a pas de notion de « zone » au sens de BIND : il répond depuis ses données locales (`host-record`, `/etc/hosts`, baux DHCP), sinon il relaie vers un serveur amont et met en cache. `local=/medisphere.internal/` dit : « pour ce suffixe, ne relaie jamais ; si je n'ai pas la réponse, c'est NXDOMAIN ». Sans cette ligne, une faute de frappe dans un nom interne partirait vers les résolveurs publics : fuite d'information (noms internes) et latence.
- **`domain-needed` et `bogus-priv`.** Le premier empêche de relayer des noms sans point (`dns01` tout court) ; le second empêche de relayer des résolutions inverses d'adresses privées (RFC 1918) que personne sur Internet ne connaît. Les deux évitent des fuites vers l'amont et des délais d'expiration inutiles.
- **`host-record` contre `address=`.** `host-record` crée le A **et** le PTR (vers le premier nom de la ligne). `address=/nom/ip` répond pour le nom **et tous ses sous-domaines**, sans PTR : un piège classique.
- **Pourquoi « faisant autorité » est un abus de langage ici.** dnsmasq positionne le drapeau `aa` pour ses données locales (vérifie sur ta sortie), mais il ne publie ni SOA ni NS pour ces zones, ne gère ni transfert de zone ni délégation : aucun autre serveur ne peut s'appuyer sur lui comme serveur de zone. Il existe un mode `auth-zone`, mais séparer proprement serveur faisant autorité et récurseur est le travail de PowerDNS au module 06.
- **TCP 53 n'est pas optionnel.** Une réponse plus grande que le tampon annoncé par le client (EDNS, souvent 1 232 octets aujourd'hui) revient tronquée (drapeau `tc`) ; le client doit alors reposer la question en TCP. Bloquer TCP casse les grosses réponses (nombreux enregistrements, DNSSEC, TXT longs) de façon intermittente, donc difficile à diagnostiquer.
- **`th dport`** (*transport header*) teste le port de destination quel que soit le protocole de transport : une seule règle pour UDP et TCP, avec `meta l4proto { tcp, udp }` en garde-fou.
- **TTL.** Par défaut, dnsmasq sert ses données locales avec un TTL de 0 : aucun client ne met en cache. `local-ttl=60` garde des changements quasi immédiats tout en évitant une requête par connexion.

**Alternatives**

- **Unbound (récurseur) + NSD ou Knot (faisant autorité)** : la séparation des rôles « propre », plus de configuration.
- **BIND 9** : tout-en-un, très complet, verbeux ; vues, DNSSEC, transferts.
- **dnsmasq + `/etc/hosts`** (`expand-hosts`, `domain=`) : encore plus simple, mais mélange un fichier système avec des données de service, et le fichier hosts de `dns01` devient critique.
- **PowerDNS** (module 06) : API, base de données, intégration NetBox, ce qui permettra l'enregistrement automatique depuis l'IaC.

**Pièges classiques**

- dnsmasq qui lit `/etc/resolv.conf`… qui pointe vers lui-même : boucle, puis délais d'expiration. D'où `no-resolv` + `server=`.
- Conflit de port 53 avec `systemd-resolved` (« Address already in use ») quand dnsmasq écoute sur toutes les adresses.
- Oublier TCP dans le pare-feu : tout semble marcher jusqu'à la première grosse réponse.
- Oublier que `dns01` doit lui-même sortir vers `<DNS-AMONT>` : si l'amont est la box, c'est une adresse du LAN maison, que la règle « lab vers Internet » exclut souvent.
- Modifier `nameserver`/`searchdomain` d'une VM existante dans Proxmox et attendre un effet immédiat : le lecteur cloud-init n'est relu qu'au démarrage, et un changement de configuration cloud-init peut être vu comme une **nouvelle instance** (régénération des clés d'hôte SSH, à vérifier selon ta version de cloud-init et de Proxmox).
- `gw01` dépend de `dns01` pour résoudre, et `dns01` dépend de `gw01` pour sortir : au démarrage à froid du lab, `chrony` sur `gw01` peut ne pas résoudre `pool.ntp.org` tant que `dns01` n'est pas prêt. Ce n'est pas bloquant (chrony réessaie), mais c'est à savoir pour l'ordre de démarrage (M00-E32).

**En production chez MédiSphère**

- Au moins deux résolveurs, sur deux hyperviseurs différents, annoncés par DHCP ou derrière une adresse virtuelle (VRRP, M07).
- Séparation stricte : serveurs faisant autorité pour `medisphere.internal` d'un côté, récurseurs de l'autre (module 06).
- Validation DNSSEC sur les récurseurs, journalisation des requêtes vers le SIEM (détection d'exfiltration par DNS), métriques (taux de NXDOMAIN, latence).
- Enregistrements créés par l'automatisation à partir de la source de vérité (NetBox → PowerDNS), jamais à la main.

---

### M00-E14 — DHCP du VLAN SANDBOX par relais

**Solution**

1. **Trajet d'un échange relayé** (DORA) :

   | Étape | Émetteur → destinataire | Remarque |
   |---|---|---|
   | DISCOVER | client `0.0.0.0:68` → `255.255.255.255:67` | Diffusion dans le VLAN 99 |
   | relayé | `gw01` `10.10.20.1:67` → `10.10.20.10:67` | Unicast routé ; `giaddr` = 10.10.99.1, `hops` + 1 |
   | OFFER | `dns01` `10.10.20.10:67` → `10.10.99.1:67` | Le serveur répond **au giaddr**, port 67 |
   | relayé | `gw01` `10.10.99.1:67` → client `:68` | Diffusion ou unicast selon le drapeau *broadcast* du client |
   | REQUEST / ACK | même chemin | |
   | Renouvellement (T1, mi-bail) | client `10.10.99.1xx:68` → `10.10.20.10:67` | **Unicast direct** vers le *server identifier* : routé par `gw01`, pas relayé |
   | Rebind (T2, 87,5 % du bail) | diffusion | Repasse par le relais |

   Le `giaddr` sert deux fois : le serveur choisit la plage dont le sous-réseau contient le `giaddr`, et il y envoie ses réponses. L'**option 82** (*relay agent information*) est ajoutée par le relais : sous-options *circuit-id* (par exemple le port du commutateur) et *remote-id* (l'équipement). Le serveur peut s'en servir pour choisir une plage ou refuser un client ; il la renvoie, et le relais la retire avant de répondre au client. Le relais dnsmasq ne l'ajoute pas par défaut (à vérifier dans `man dnsmasq` selon ta version) ; `isc-dhcp-relay -a` le fait.

2. Sur `dns01`, version complète : [`fichiers/M00-E14/medisphere.conf`](fichiers/M00-E14/medisphere.conf). L'essentiel :
   ```
   dhcp-range=set:sandbox,10.10.99.100,10.10.99.199,255.255.255.0,12h
   dhcp-option=tag:sandbox,option:router,10.10.99.1
   dhcp-option=tag:sandbox,option:dns-server,10.10.20.10
   dhcp-option=tag:sandbox,option:ntp-server,10.10.99.1
   dhcp-option=tag:sandbox,option:domain-search,par1.medisphere.internal
   dhcp-authoritative
   log-dhcp
   ```
   Ce que dnsmasq ne peut pas deviner : le **masque** d'un sous-réseau auquel il n'est pas connecté. Sans lui, la plage est ignorée et le journal dit « no address range available for DHCP request via … ».

3. Sur `gw01` :
   ```
   admin@gw01:~$ sudo apt install -y dnsmasq
   admin@gw01:~$ sudo ss -lnup | grep dnsmasq        # le DNS par défaut écoute partout
   admin@gw01:~$ sudo cp relais-dhcp.conf /etc/dnsmasq.d/relais-dhcp.conf
   admin@gw01:~$ sudo systemctl restart dnsmasq
   admin@gw01:~$ sudo ss -lnup | grep dnsmasq
   UNCONN 0 0 0.0.0.0:67 0.0.0.0:* users:(("dnsmasq",pid=1234,fd=4))
   admin@gw01:~$ cat /etc/resolv.conf               # inchangé : nameserver 10.10.20.10
   ```
   Fichier : [`fichiers/M00-E14/relais-dhcp.conf`](fichiers/M00-E14/relais-dhcp.conf) (`port=0`, `interface=ens19.99`, `dhcp-relay=10.10.99.1,10.10.20.10`). Si le paquet `resolvconf` est installé sur `gw01`, le service dnsmasq de Debian peut s'inscrire comme résolveur local (127.0.0.1) : mets `DNSMASQ_EXCEPT="lo"` dans `/etc/default/dnsmasq` (option documentée dans ce fichier, à vérifier selon ta version).

4. Pare-feu : [`fichiers/M00-E14/gw01-nftables-extrait.nft`](fichiers/M00-E14/gw01-nftables-extrait.nft).
   ```
   # chaîne input
   iifname $V_SANDBOX udp sport 68 udp dport 67 accept
   iifname $V_INFRA ip saddr $DNS01 ip daddr 10.10.99.1 udp sport 67 udp dport 67 accept
   # chaîne forward
   iifname $V_SANDBOX ip daddr $DNS01 udp sport 68 udp dport 67 accept
   ```
   **Pourquoi `established` ne suffit pas** : le relais a émis `10.10.20.1:67 → 10.10.20.10:67` (adresse source choisie par la table de routage : celle de l'interface de sortie). Conntrack attend donc une réponse `10.10.20.10:67 → 10.10.20.1:67`. Or `dns01` répond au `giaddr`, `10.10.99.1:67`. Le quadruplet ne correspond pas : le paquet est `NEW`, et seule une règle explicite le laisse entrer. Les réponses du relais vers le client, elles, sortent par la chaîne `output` (politique `accept`).

5. Captures pendant le démarrage de `sbx01` (extraits) :
   ```
   root@gw01:~# tcpdump -ni ens19.20 -v port 67
   IP (tos 0x0, ttl 64, …) 10.10.20.1.67 > 10.10.20.10.67: BOOTP/DHCP, Request from bc:24:11:aa:bb:cc, length 300, hops 1, xid 0x5c1e…, Flags [none]
   	  Gateway-IP 10.10.99.1
   	  Client-Ethernet-Address bc:24:11:aa:bb:cc
   	    DHCP-Message (53), length 1: Discover
   IP (tos 0xc0, ttl 64, …) 10.10.20.10.67 > 10.10.99.1.67: BOOTP/DHCP, Reply, length 300, hops 1, …
   	  Your-IP 10.10.99.142
   	  Gateway-IP 10.10.99.1
   	    DHCP-Message (53), length 1: Offer
   	    Server-ID (54), length 4: 10.10.20.10
   ```
   Côté `dns01`, `log-dhcp` détaille : `DHCPDISCOVER(ens18) bc:24:11:aa:bb:cc`, `tags: sandbox, …`, `DHCPOFFER(ens18) 10.10.99.142 …`, puis les options envoyées.

6. Vérifications :
   ```
   admin@dns01:~$ cat /var/lib/misc/dnsmasq.leases
   1767318000 bc:24:11:aa:bb:cc 10.10.99.142 sbx01 ff:…
   root@pve01:~# qm guest cmd 5001 network-get-interfaces | grep '"ip-address"'
   admin@adm01:~$ dig +short sbx01.par1.medisphere.internal
   10.10.99.142
   ```
   Le nom `sbx01` est enregistré parce que le client DHCP de l'image envoie son nom d'hôte (option 12) et que `domain=par1.medisphere.internal` l'autorise.

7. Renouvellement : la capture sur `ens19.99` montre `10.10.99.142.68 > 10.10.20.10.67` **sans** passer par le relais (rien dans le journal du relais, mais un passage dans la chaîne `forward`). Sans la règle de transfert, le renouvellement à T1 échoue en silence ; le client réessaie jusqu'à T2, où la diffusion repasse par le relais. Le service « marche », mais avec des journaux pleins de `DHCPREQUEST` sans réponse et un comportement surprenant.

8. Destruction de 5001 après la vérification.

**Explications**

- **Pourquoi un relais plutôt qu'une patte de `dns01` dans le VLAN 99** : le VLAN SANDBOX est le plus exposé du lab (VMs jetables, exercices de panne). Brancher le serveur DNS de tout le lab dans ce domaine de diffusion l'exposerait à tout ce qui s'y passe (ARP, diffusion, services à l'écoute). Avec le relais, `dns01` ne voit que de l'unicast filtré par `gw01`. C'est aussi le modèle qui passe à l'échelle : un serveur, N VLANs, un relais par passerelle.
- **Choix de la plage par le serveur** : dnsmasq compare le `giaddr` aux plages déclarées. Il peut donc servir des dizaines de sous-réseaux distants sans y avoir d'adresse.
- **`dhcp-authoritative`** : dnsmasq est le seul serveur de ce sous-réseau ; il peut donc répondre `DHCPNAK` ou réattribuer sans attendre lorsqu'un client réclame une adresse inconnue (après perte du fichier de baux, par exemple).
- **`port=0`** sur `gw01` : dnsmasq sans DNS. Le routeur n'a aucune raison de répondre en DNS ; une surface en moins.

**Alternatives**

- **`isc-dhcp-relay`** : le relais historique. Il faut lui donner les interfaces des **deux** côtés (client et serveur), sinon il ignore les réponses, et l'option `-a` ajoute l'option 82. ISC DHCP est en fin de vie depuis fin 2022 : sa présence dans les dépôts de Debian 13 est à vérifier, et ce n'est pas un bon choix pour un service neuf.
- **`dhcp-helper`** (paquet Debian) : un relais minimal, sans fioritures.
- **systemd-networkd** : sa partie serveur DHCP sait aussi relayer (`RelayTarget=` dans la section `[DHCPServer]`, versions récentes de systemd, à vérifier). Intéressant si `gw01` passait à networkd.
- **Serveur DHCP directement sur `gw01`** : plus simple, mais les baux et les noms dynamiques seraient séparés de `dns01`. C'est ce qu'on veut éviter ici.

**Pièges classiques**

- Plage déclarée sans masque : silence total, puis « no address range available ».
- Oublier la règle pour les réponses vers le `giaddr` : le client envoie des DISCOVER en boucle, `dns01` envoie des OFFER que personne ne reçoit. La capture des deux côtés le montre immédiatement.
- Oublier les renouvellements unicast (voir étape 7).
- Laisser le DNS par défaut de dnsmasq actif sur `gw01` après l'installation.
- Redéfinir `net0` sans reprendre la MAC : une nouvelle MAC est générée, l'ancien bail reste orphelin jusqu'à expiration.
- Oublier `tag=99` : la VM se retrouve sur le VLAN natif de `vmbr1`, où personne ne répond.

**En production chez MédiSphère**

- Kea DHCP (module 06) en haute disponibilité (deux serveurs en *hot-standby* ou partage de charge), baux en base de données, réservations générées depuis NetBox.
- *DHCP snooping* et protection ARP dynamique sur les commutateurs d'accès, option 82 renseignée par ces commutateurs.
- Baux courts sur les réseaux éphémères, longs sur les réseaux de serveurs (où l'on préfère de toute façon l'adressage statique ou les réservations).
- Journaux DHCP centralisés : ils servent en investigation (« qui avait cette IP mardi à 14 h ? »).

---
### M00-E15 — Outiller le poste d'administration `adm01`

**Solution**

1. Clé et agent :
   ```
   admin@adm01:~$ ssh-keygen -t ed25519 -a 100 -C "admin@adm01 $(date +%F)"
   admin@adm01:~$ eval "$(ssh-agent -s)" && ssh-add
   ```
   Pour un agent qui survit aux déconnexions : `sudo apt install keychain`, puis dans `~/.bashrc` : `eval "$(keychain --eval --quiet id_ed25519)"`. Travaille dans `tmux` : la session et son agent restent vivants si ta connexion à `adm01` tombe.

2. Distribution de la clé publique. Le plus simple est de passer par un hôte qui a déjà accès (`pve01`, dont la clé a servi en E12) :
   ```
   admin@adm01:~$ scp ~/.ssh/id_ed25519.pub root@<IP-PVE01>:/tmp/adm01.pub     # mot de passe root de pve01
   root@pve01:~# cat /tmp/adm01.pub >> /root/.ssh/authorized_keys
   root@pve01:~# ssh gw01  'cat >> ~/.ssh/authorized_keys' < /tmp/adm01.pub     # alias de root@pve01 (E10)
   root@pve01:~# ssh dns01 'cat >> ~/.ssh/authorized_keys' < /tmp/adm01.pub     # alias de root@pve01 (E12)
   root@pve01:~# rm /tmp/adm01.pub
   ```
   `>>` ajoute à travers le lien symbolique `/root/.ssh/authorized_keys` → `/etc/pve/priv/authorized_keys` sans le casser. `ssh-copy-id` fonctionne aussi là où l'authentification par mot de passe est encore permise.

3. `~/.ssh/config` : [`fichiers/M00-E15/ssh-config`](fichiers/M00-E15/ssh-config), puis `chmod 600 ~/.ssh/config`. Contrôle :
   ```
   admin@adm01:~$ ssh -G pbs01 | grep -E '^(user|hostname|controlpath) '
   user root
   hostname 10.20.10.10
   controlpath /home/admin/.ssh/cm-3f1c…
   admin@adm01:~$ ssh -o BatchMode=yes gw01 'sudo -n true' && echo OK
   OK
   ```

4. `sudo` :
   ```
   admin@dns01:~$ sudo -l
   User admin may run the following commands on dns01:
       (ALL) NOPASSWD:ALL
   ```
   Sur `adm01` et `dns01`, cloud-init a donné `NOPASSWD: ALL` à l'utilisateur par défaut (renommé `admin`) : fichier `/etc/sudoers.d/90-cloud-init-users`. Sur `gw01`, c'est le fichier [`fichiers/M00-E10/90-workbook`](fichiers/M00-E10/90-workbook) posé en E10 (sa justification y est développée) : rien à recréer ici.
   ```
   admin@adm01:~$ ssh gw01 'sudo -l; sudo -n visudo -c'
   admin@adm01:~$ ssh dns01 'sudo -n ls /etc/sudoers.d/'
   90-cloud-init-users  README
   ```
   Le choix retenu est `NOPASSWD: ALL`, compensé par l'accès SSH par clé et filtré (justification dans le fichier de E10 et ci-dessous, « Alternatives »).

5. Outils :
   ```
   admin@adm01:~$ sudo apt install -y git curl jq bind9-dnsutils tcpdump mtr-tiny tmux shellcheck python3-venv
   ```

6. Dépôt et configuration :
   ```
   admin@adm01:~$ git config --global user.name "<PRENOM> <NOM>"
   admin@adm01:~$ git config --global user.email "<ADRESSE>"
   admin@adm01:~$ git clone <URL-DU-DEPOT> ~/DevOpsPrivateCloud && cd ~/DevOpsPrivateCloud
   admin@adm01:~/DevOpsPrivateCloud$ cp lab/lab.env.example lab/lab.env && chmod 600 lab/lab.env
   admin@adm01:~/DevOpsPrivateCloud$ ${EDITOR:-nano} lab/lab.env
   admin@adm01:~/DevOpsPrivateCloud$ git status --short      # lab/lab.env ne doit PAS apparaître (.gitignore)
   ```
   Contenu de référence : [`fichiers/M00-E15/lab.env`](fichiers/M00-E15/lab.env).

7. Vérifications : `lab/bin/check 00 15`, puis `00 13` et `00 14`. Les scripts utilisent les alias `gw01` et `dns01` : ceux de `root@pve01` (E10, E12) quand ils tournent sur l'hyperviseur, ceux de `admin@adm01` désormais (à défaut d'alias, ils tentent `admin@<IP>`).

8. Ménage sur `pve01` : récupère d'abord l'inventaire local, ignoré par git (`scp pve01:DevOpsPrivateCloud/lab/inventaire-local.md ~/DevOpsPrivateCloud/lab/` depuis `adm01`), puis supprime le clone du dépôt et les outils installés **uniquement** pour le lab (consulte `/var/log/apt/history.log` pour retrouver ce que tu as ajouté). Ne retire rien que Proxmox utilise.

**Explications**

- **ed25519** : clés courtes, signatures rapides, pas de piège de taille comme RSA. `-a 100` augmente le nombre de tours de la fonction de dérivation qui protège la clé privée par la phrase de passe : un vol du fichier se paie en temps de calcul.
- **Agent** : la phrase de passe est saisie une fois ; les scripts (`BatchMode=yes`) utilisent l'agent. Sans agent, ils échouent proprement au lieu de bloquer sur une question.
- **`IdentitiesOnly yes`** : ssh ne présente que la clé indiquée. Sans cela, un agent chargé de nombreuses clés provoque « Too many authentication failures » (le serveur coupe après `MaxAuthTries` essais).
- **Multiplexage** (`ControlMaster`/`ControlPersist`) : la première connexion ouvre un canal maître, les suivantes le réutilisent sans nouvelle poignée de main. Un script de vérification qui fait 30 appels SSH passe de dizaines de secondes à quelques-unes.
- **`StrictHostKeyChecking accept-new`** : on accepte une clé d'hôte inconnue (confiance au premier usage), mais on refuse toute clé **changée** (signe d'usurpation ou de VM recréée). Pour la sandbox, où les VMs sont recréées sans cesse, on désactive la vérification sur une plage bien délimitée, jamais globalement.
- **IP plutôt que nom** dans `HostName` : le jour où le DNS tombe (M00-E40), c'est précisément là que tu as besoin d'atteindre `dns01` et `gw01`. Le DNS reste utile pour les humains et les nouveaux hôtes.
- **Pourquoi lancer les vérifications depuis `adm01`** : l'hyperviseur doit porter le moins de choses possible (surface d'attaque, mises à jour, M00-E27 restreindra son accès). `adm01` est le bastion : c'est là que vivent les outils, les clés et les secrets d'automatisation.

**Alternatives**

- **Certificats SSH** : une autorité signe des clés à durée de vie courte ; les serveurs font confiance à l'autorité. Plus de `authorized_keys` à distribuer (module 06, step-ca).
- **`ProxyJump`** depuis ton poste à travers `adm01` : les clés restent sur ton poste (avec `ssh-agent` local), `adm01` sert de bastion pur.
- **Liste blanche `sudo`** : défendable sur un serveur dont les tâches automatisées sont connues et stables. Ici, les scripts de panne et Ansible ont besoin de tout ; une liste blanche qui contient `systemctl`, `tee` ou un éditeur équivaut de toute façon à root.

**Pièges classiques**

- Écraser `/root/.ssh/authorized_keys` sur Proxmox (lien vers `/etc/pve/priv/authorized_keys`, partagé par tout un cluster) : on perd les accès des autres nœuds.
- Placer `Host *` en tête du fichier : ses valeurs l'emportent sur les blocs suivants.
- `ControlPath` trop long (plus d'environ 100 caractères) : « unix_listener: path too long », multiplexage désactivé.
- Agent non chargé : les vérifications échouent en « Permission denied (publickey) » alors que la clé est bien déposée.
- Une erreur de syntaxe dans `/etc/sudoers.d/` : `sudo` ne fonctionne plus. Toujours `visudo -c`, toujours une session root ouverte.
- `lab/lab.env` versionné par erreur : vérifie `git status` (il est dans `.gitignore`).

**En production chez MédiSphère**

- Comptes nominatifs, jamais de compte `admin` partagé ; certificats SSH de courte durée délivrés après authentification forte (modules 06 et 24).
- Clés matérielles (FIDO2, `ed25519-sk`) pour les administrateurs.
- Bastion avec enregistrement des sessions (Teleport, module 24), journaux `sudo` envoyés au SIEM.
- `NOPASSWD` réservé aux comptes de service, avec restrictions d'origine (`from=` dans `authorized_keys`).

---

### M00-E16 — VPN d'administration WireGuard

**Solution**

1. Sur `gw01` :
   ```
   root@gw01:~# apt install -y wireguard-tools
   root@gw01:~# umask 077
   root@gw01:~# wg genkey | tee /etc/wireguard/wg1.key | wg pubkey > /etc/wireguard/wg1.pub
   root@gw01:~# cat /etc/wireguard/wg1.pub
   ```
   Configuration : [`fichiers/M00-E16/gw01-wg1.conf`](fichiers/M00-E16/gw01-wg1.conf) (mode 600). Le corrigé met la clé privée dans `wg1.conf` (méthode standard, compatible avec `wg syncconf`). La variante `PostUp = wg set %i private-key /etc/wireguard/wg1.key` garde le fichier de configuration sans secret ; si tu la choisis, vérifie après chaque `wg syncconf` que la clé est toujours en place (`wg show wg1 private-key`).

2. Sur le poste : application officielle WireGuard (Windows, macOS) → « Ajouter un tunnel vide » génère la paire de clés localement ; sous Linux, `wg genkey | tee wg1.key | wg pubkey`. Seule la **clé publique** du poste est transmise à `gw01`.

3. Configuration client : [`fichiers/M00-E16/poste-wg1.conf`](fichiers/M00-E16/poste-wg1.conf). `AllowedIPs = 10.10.10.0/24, 10.10.20.0/24, 10.20.10.0/24, 10.255.1.0/24` : tunnel partagé, Internet reste en direct. Sur le LAN maison, le poste joint `pve01` directement ; en déplacement, ajoute `<IP-PVE01>/32` aux `AllowedIPs` pour l'administrer à travers le VPN.
   DNS : avec `DNS = 10.10.20.10`, Windows et macOS utilisent ce serveur en priorité tant que le tunnel est actif, et `wg-quick` sous Linux remplace les résolveurs du système (via `resolvconf`). Comme `dns01` est aussi récursif, cela fonctionne, mais **toutes** tes requêtes passent alors par le lab. Sous Linux avec `systemd-resolved`, la solution propre est un DNS « routé » par domaine : `PostUp = resolvectl dns %i 10.10.20.10; resolvectl domain %i ~medisphere.internal ~10.10.in-addr.arpa` (seuls ces suffixes vont vers `dns01`).

4. Ajout et retrait de pairs à chaud :
   ```
   root@gw01:~# systemctl enable --now wg-quick@wg1
   root@gw01:~# ${EDITOR:-nano} /etc/wireguard/wg1.conf            # ajout d'un bloc [Peer] 10.255.1.3/32
   root@gw01:~# wg syncconf wg1 <(wg-quick strip wg1)
   root@gw01:~# wg show wg1 peers
   ```
   `wg syncconf` applique la différence sans toucher aux sessions existantes ; un `systemctl restart wg-quick@wg1` couperait tout le monde (et ta propre session si tu passes par le VPN).

5. Pare-feu : [`fichiers/M00-E16/gw01-nftables-extrait.nft`](fichiers/M00-E16/gw01-nftables-extrait.nft). En résumé : `udp dport 51821` en entrée depuis `<LAN-MAISON>` sur `ens18` ; SSH vers `gw01` depuis `wg1` ; transfert `wg1` → `ens19.10` et `ens19.20`, et `wg1` → `pve01` (TCP 22 et 8006 ; `pve01` répond par sa route 10.255.1.0/24 via `gw01`, posée en E10) ; accès direct du LAN maison au lab restreint à `pve01` ; aucune règle NAT.

6. Sur le poste Linux : `sudo ip route del 10.10.0.0/16` (et retire-la de la configuration persistante). Sur Windows : `route delete 10.10.0.0`. Sur la box : retire la route si tu l'y avais mise.

7. Tests :
   ```
   admin@poste:~$ sudo wg-quick up wg1          # ou bouton « Activer »
   admin@poste:~$ sudo wg show
   peer: 3k9…=
     endpoint: <IP-GW01-WAN>:51821
     allowed ips: 10.10.10.0/24, 10.10.20.0/24, 10.20.10.0/24, 10.255.1.0/24
     latest handshake: 4 seconds ago
     transfer: 1.21 KiB received, 2.05 KiB sent
   admin@poste:~$ ssh admin@10.10.10.10 hostname
   adm01
   admin@poste:~$ ping -c1 -W2 10.10.99.50          # échoue
   root@gw01:~# journalctl -k -g 'SRC=10.255.1.2' -n 3
   … nft-fwd-drop: IN=wg1 OUT=ens19.99 SRC=10.255.1.2 DST=10.10.99.50 … PROTO=ICMP TYPE=8 …
   ```
   (Le préfixe de journalisation dépend de ton fichier de E10.) Note : le paquet vers 10.10.99.50 n'atteint même pas `gw01` si 10.10.99.0/24 n'est pas dans les `AllowedIPs` du client : le client ne route que ce qu'on lui a déclaré. Pour tester le filtrage de `gw01`, ajoute temporairement 10.10.99.0/24 aux `AllowedIPs` du poste, puis retire-le.

8. Sur `adm01` : `ss -tn state established '( sport = :22 )'` montre `10.255.1.2:<port>` comme pair distant.

**Explications**

- **Routage par clé** : WireGuard associe à chaque pair une clé publique et une liste `AllowedIPs`. En émission, la destination choisit le pair (et donc la clé de chiffrement) ; en réception, un paquet déchiffré avec la clé d'un pair n'est accepté que si son adresse source figure dans les `AllowedIPs` de **ce** pair. Avec `10.255.1.2/32`, le pair ne peut pas usurper une autre adresse : l'adresse source vue par le pare-feu est authentifiée par la clé.
- **Interface silencieuse** : WireGuard ne répond à rien sans poignée de main valide. Un balayage de ports ne voit pas que UDP 51821 est ouvert. C'est une des raisons pour lesquelles ouvrir ce port est peu risqué ; on le restreint quand même au LAN maison (défense en profondeur).
- **Pas de NAT** : les VMs voient 10.255.1.2, ce qui donne des journaux exploitables (qui s'est connecté ?) et permet des règles par source sur les hôtes. Le retour fonctionne parce que la passerelle des VMs est `gw01`, qui a la route vers 10.255.1.0/24 sur `wg1`.
- **Tunnel partagé** : seuls les réseaux d'administration passent par le VPN. Le filtrage réel se fait sur `gw01` ; les `AllowedIPs` du client ne sont qu'une table de routage locale, qu'un utilisateur peut modifier.

**Alternatives**

- **OpenVPN** : mature, TCP possible (utile derrière des pare-feu stricts), plus lent et plus complexe.
- **IPsec (strongSwan)** : standard interopérable avec les équipements réseau ; configuration plus lourde.
- **Maillages à serveur de coordination** (Headscale, Netbird) : WireGuard avec distribution automatique des clés, ACL centralisées et SSO. Très pertinent à l'échelle d'une équipe.
- **Accès « zero trust »** par un proxy d'identité (Teleport, module 24) : plus de réseau à ouvrir, chaque session est authentifiée et tracée.

**Pièges classiques**

- Route statique résiduelle sur le poste : `wg-quick up` échoue (« RTNETLINK answers: File exists ») ou, pire, le trafic contourne le tunnel.
- Oublier les règles de transfert : la poignée de main réussit (`input` ouvert), mais rien ne passe.
- `<IP-GW01-WAN>` attribuée par DHCP sans réservation : le point d'accès change, le VPN tombe.
- Horloge du poste qui recule (pile du BIOS, double démarrage) : les poignées de main contiennent un horodatage qui doit croître pour un pair donné ; un retour en arrière fait rejeter les initiations jusqu'à ce que l'horloge dépasse la dernière valeur vue (ou que l'interface de `gw01` soit redémarrée).
- Clé privée envoyée par messagerie « pour aller plus vite » : elle est compromise, il faut régénérer la paire.

**En production chez MédiSphère**

- Un pair par personne et par appareil, nommé et daté en commentaire ; retrait immédiat au départ d'un collaborateur (procédure RH ↔ plateforme).
- Authentification forte en plus de la clé (WireGuard n'a pas de second facteur) : passerelle à SSO, ou accès aux outils via un proxy d'identité.
- Concentrateurs VPN redondants, adresses de pairs gérées dans l'IPAM, supervision des poignées de main (un pair qui ne se connecte plus depuis 90 jours est retiré).

---

### M00-E17 — API Proxmox et jeton à privilèges minimaux

**Solution**

1. Exploration :
   ```
   root@pve01:~# pvesh usage /nodes/{node}/qemu/{vmid}/clone --verbose
   root@pve01:~# pvesh get /nodes/$(hostname)/qemu --output-format yaml | head
   ```
   `pvesh usage` décrit les paramètres ; l'API viewer (`https://pve.proxmox.com/pve-docs/api-viewer/`) donne en plus, pour chaque méthode, le contrôle de permissions exact. Les contrôles utiles ici (Proxmox VE 9) :

   | Opération | Méthode | Contrôle |
   |---|---|---|
   | Cloner | `POST /nodes/{node}/qemu/{vmid}/clone` | `VM.Clone` sur `/vms/{vmid}` **et** `VM.Allocate` sur `/vms/{newid}` **ou** sur `/pool/{pool}` ; `Datastore.AllocateSpace` sur les stockages ; `SDN.Use` sur le pont |
   | Configurer | `POST/PUT …/config` | `VM.Config.*` selon les paramètres modifiés |
   | Démarrer, arrêter | `…/status/start`, `…/stop`, `…/shutdown` | `VM.PowerMgmt` |
   | Agent (ping, interfaces) | `…/agent/ping`, `…/agent/network-get-interfaces` | `VM.GuestAgent.Audit` (ou `…Unrestricted`) |
   | Snapshots | `…/snapshot`, `…/snapshot/{name}/rollback` | `VM.Snapshot`, `VM.Snapshot.Rollback` |
   | Détruire | `DELETE /nodes/{node}/qemu/{vmid}` | `VM.Allocate` |
   | Lire config et état | `GET …/config`, `…/status/current` | `VM.Audit` |
   | Suivre ses tâches | `GET /nodes/{node}/tasks/{upid}/status` | aucun pour ses propres tâches (`Sys.Audit` pour celles des autres) |

2. Rôle `WBAutomation` (privilèges et justification) :

   | Privilège | Justification |
   |---|---|
   | `VM.Allocate` | Créer la VM clonée (contrôle sur le pool), la détruire |
   | `VM.Clone` | Cloner le template 9000 (membre du pool) |
   | `VM.Audit` | Lire configuration et état, lister les VMs |
   | `VM.Config.CPU`, `VM.Config.Memory` | Dimensionner la VM |
   | `VM.Config.Disk` | Agrandir ou ajouter un disque |
   | `VM.Config.Network` | Brancher `net0` sur `vmbr1` avec le bon VLAN |
   | `VM.Config.Cloudinit` | `ipconfig0`, `ciuser`, `sshkeys`, `nameserver`, `searchdomain` |
   | `VM.Config.Options` | Nom, description, `agent`, ordre de démarrage, étiquettes |
   | `VM.Config.HWType` | Type de machine, contrôleur SCSI (utilisés par Terraform au module 05) |
   | `VM.Config.CDROM` | Lecteur cloud-init (présenté comme un CD-ROM), ISO éventuelle |
   | `VM.PowerMgmt` | Démarrer, arrêter, redémarrer |
   | `VM.Snapshot`, `VM.Snapshot.Rollback` | Snapshots avant changement, retour arrière (modules 03 à 05) |
   | `VM.GuestAgent.Audit` | Attendre l'agent, lire les adresses IP (Proxmox VE 8 : `VM.Monitor`) |
   | `Pool.Audit` | Lire le contenu du pool `lab` |

   Écartés : `VM.Console` (une automatisation n'ouvre pas de console) ; `VM.Migrate` (un seul nœud pour l'instant) ; `VM.Backup` (les sauvegardes sont faites par les tâches de `pve01`) ; `VM.GuestAgent.FileRead`, `FileWrite`, `Unrestricted` (lire, écrire des fichiers ou exécuter des commandes dans l'invité = être root dans la VM) ; `VM.GuestAgent.FileSystemMgmt` (gel des systèmes de fichiers : c'est la sauvegarde qui s'en charge) ; `Datastore.AllocateTemplate` (téléverser des ISO ou des *snippets* : à ajouter au module 03 si besoin) ; `Sys.*`, `Permissions.Modify`, `User.Modify`, `Realm.*`, `Pool.Allocate`, `SDN.Allocate` (administration de la plateforme).
   Les besoins « stockage » et « réseau » sont couverts par deux rôles prédéfinis posés sur leurs propres chemins : `PVEDatastoreUser` (`Datastore.AllocateSpace`, `Datastore.Audit`) et `PVESDNUser` (`SDN.Use`, `SDN.Audit`).

3. Création :
   ```
   root@pve01:~# pveum role add WBAutomation --privs "VM.Allocate VM.Clone VM.Audit VM.Config.CPU VM.Config.Memory VM.Config.Disk VM.Config.Network VM.Config.Cloudinit VM.Config.Options VM.Config.HWType VM.Config.CDROM VM.PowerMgmt VM.Snapshot VM.Snapshot.Rollback VM.GuestAgent.Audit Pool.Audit"
   root@pve01:~# pveum user add wb-automation@pve --comment "Compte technique d'automatisation (SEC-117)"
   root@pve01:~# pveum user token add wb-automation@pve lab --privsep 1 --expire "$(date -d '+1 year' +%s)" --comment "Scripts et IaC du lab (SEC-117)"
   ┌──────────────┬──────────────────────────────────────┐
   │ key          │ value                                │
   ╞══════════════╪══════════════════════════════════════╡
   │ full-tokenid │ wb-automation@pve!lab                │
   ├──────────────┼──────────────────────────────────────┤
   │ info         │ {"comment":"…","expire":"…","privsep":"1"} │
   ├──────────────┼──────────────────────────────────────┤
   │ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
   └──────────────┴──────────────────────────────────────┘
   ```
   Copie le secret (`value`) directement dans l'éditeur de l'étape 6. Il ne sera plus jamais affiché.

4. ACL, pour l'utilisateur **et** pour le jeton :
   ```
   root@pve01:~# pveum acl modify /pool/lab --users wb-automation@pve --roles WBAutomation
   root@pve01:~# pveum acl modify /pool/lab --tokens 'wb-automation@pve!lab' --roles WBAutomation
   root@pve01:~# pveum acl modify /storage/<STOCKAGE-VMS> --users wb-automation@pve --roles PVEDatastoreUser
   root@pve01:~# pveum acl modify /storage/<STOCKAGE-VMS> --tokens 'wb-automation@pve!lab' --roles PVEDatastoreUser
   root@pve01:~# pveum acl modify /sdn/zones/localnetwork/vmbr1 --users wb-automation@pve --roles PVESDNUser
   root@pve01:~# pveum acl modify /sdn/zones/localnetwork/vmbr1 --tokens 'wb-automation@pve!lab' --roles PVESDNUser
   ```
   `<STOCKAGE-VMS>` : le ou les stockages où vivent le template et les disques du lab (et celui du lecteur cloud-init s'il est ailleurs). Le chemin `/sdn/zones/localnetwork/<pont>` est celui des ponts hors SDN depuis Proxmox VE 8 (à vérifier selon ta version) ; l'ACL posée sur le pont se propage à ses VLANs (`…/vmbr1/99`). Après M00-E28, les ACL équivalentes se posent sur `/sdn/zones/lab`. Le template 9000 doit être membre du pool (`pveum pool modify lab --vms 9000` s'il ne l'est pas).

5. Droits effectifs :
   ```
   root@pve01:~# pveum user token permissions wb-automation@pve lab --path /pool/lab
   root@pve01:~# pveum user token permissions wb-automation@pve lab --path /vms/<VMID-HORS-POOL>
   ```
   Le second doit être vide.

6. Sur `adm01`, sans que le secret passe par la ligne de commande :
   ```
   admin@adm01:~$ install -d -m 700 ~/.config/workbook
   admin@adm01:~$ scp pve01:/etc/pve/pve-root-ca.pem ~/.config/workbook/
   admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/pve-api.env
   admin@adm01:~$ ${EDITOR:-nano} ~/.config/workbook/pve-api.env
   admin@adm01:~$ ( . ~/.config/workbook/pve-api.env
       curl -sS --cacert "$PVE_CACERT" \
            -H @<(printf 'Authorization: PVEAPIToken=%s=%s\n' "$PVE_TOKEN_ID" "$PVE_TOKEN_SECRET") \
            "$PVE_API_URL/version" | jq . )
   {
     "data": { "release": "9.x", "repoid": "…", "version": "9.x.y" }
   }
   ```
   Modèle du fichier : [`fichiers/M00-E17/pve-api.env.exemple`](fichiers/M00-E17/pve-api.env.exemple). La parenthèse ouvre un sous-shell : les variables ne restent pas dans ta session. `-H @<(…)` évite que le secret apparaisse dans la liste des processus.

7. Tests négatifs (même en-tête) :
   ```
   GET /nodes/<NŒUD>/qemu                      → 200, seules les VMs du pool lab
   GET /nodes/<NŒUD>/qemu/<VMID-PERSO>/config  → 403 Permission check failed (/vms/<VMID-PERSO>, VM.Audit)
   GET /nodes/<NŒUD>/status                    → 403 Permission check failed (/nodes/<NŒUD>, Sys.Audit)
   GET /nodes/<NŒUD>/syslog                    → 403 Permission check failed (/nodes/<NŒUD>, Sys.Syslog)
   ```
   Le motif exact est dans la ligne de statut HTTP (`curl -i` ou `-D -`).

8. Réponse au ticket : les deux tableaux ci-dessus, les ACL, et la procédure de cycle de vie :
   - **renouvellement sans coupure** : créer `wb-automation@pve!lab2` avec les mêmes ACL, basculer les outils, supprimer `lab` ;
   - **révocation immédiate** : `pveum user token remove wb-automation@pve lab` (ou désactiver tout le compte : `pveum user modify wb-automation@pve --enable 0`) ;
   - **suivi** : date d'expiration notée dans le ticket et dans un rappel ; une expiration non anticipée arrête toute l'automatisation le même jour.

**Explications**

- **Chemins et propagation** : les droits se posent sur un chemin (`/vms/1001`, `/storage/local-nvme`, `/pool/lab`) et se propagent vers le bas. Une ACL sur `/pool/lab` s'applique à chaque **membre** du pool, VMs et stockages, comme si elle était posée sur leurs chemins propres. C'est ce qui isole les VMs personnelles : elles ne sont pas dans le pool.
- **Le clonage vers un pool** : `VM.Allocate` est exigé sur `/vms/{newid}`, **ou** sur `/pool/{pool}` si le paramètre `pool` est fourni. Le jeton peut donc créer 5001 sans avoir aucun droit sur `/vms`. S'il oublie `pool=lab`, l'appel est refusé : c'est un garde-fou, pas un bug.
- **Séparation des privilèges** : un jeton `privsep=1` a pour droits effectifs l'**intersection** de ses ACL et de celles de son utilisateur. Il faut donc des ACL des deux côtés. Intérêt : plusieurs jetons d'un même compte peuvent avoir des droits différents (lecture seule pour la supervision, écriture pour Terraform).
- **Pourquoi ni `/` ni `/vms`** : sur `/vms`, le rôle s'appliquerait aux VMs personnelles de l'hyperviseur ; sur `/`, à tout le nœud. Le besoin est entièrement couvert par le pool, un ou deux stockages et un pont.
- **Proxmox VE 9** : `VM.Monitor` a disparu. L'accès à l'agent QEMU est découpé en `VM.GuestAgent.Audit` (commandes d'information), `FileRead`, `FileWrite`, `FileSystemMgmt` et `Unrestricted`. Un outil écrit pour la version 8 qui réclame `VM.Monitor` échoue à la création du rôle : la liste doit être adaptée à la version.

**Alternatives**

- Rôles prédéfinis (`PVEVMAdmin` sur `/pool/lab`) : plus rapide, mais donne console, migration, sauvegarde, agent sans restriction. Acceptable pour un humain, pas pour un jeton.
- Un utilisateur par outil (`wb-terraform@pve`, `wb-ansible@pve`) plutôt qu'un utilisateur et plusieurs jetons : traçabilité plus fine dans le journal des tâches, au prix de plus de comptes à gérer.
- Authentification par ticket (login/mot de passe → cookie `PVEAuthCookie` + jeton CSRF) : réservée aux humains et à l'interface web ; un jeton d'API est sans état et révocable individuellement.

**Pièges classiques**

- ACL posée seulement sur l'utilisateur (ou seulement sur le jeton) : intersection vide, 403 partout. `pveum user token permissions` le montre tout de suite.
- Template hors du pool : `Permission check failed (/vms/9000, VM.Clone)`.
- Oublier `SDN.Use` sur le pont : le clone réussit, mais la modification de `net0` échoue (`/sdn/zones/localnetwork/vmbr1/99, SDN.Use`).
- Lecteur cloud-init sur un autre stockage que le disque : il faut aussi `Datastore.AllocateSpace` dessus.
- Secret dans l'historique du shell, dans un script, ou dans un dépôt git. Si cela arrive : révoquer, recréer, et nettoyer l'historique.
- `curl -k` « en attendant » : il reste. Un client qui ne vérifie pas le certificat envoie son jeton à quiconque se place au milieu.
- Rôle copié d'un tutoriel pour la version 8 (`VM.Monitor`) : la création échoue en version 9.

**En production chez MédiSphère**

- Secret stocké dans Vault/OpenBao (module 25) et injecté à l'exécution ; jamais dans un fichier sur un poste.
- Un jeton par outil et par environnement, expiration courte, rotation automatisée, alerte avant expiration.
- Accès à l'API (port 8006) filtré par le pare-feu de l'hyperviseur aux seuls réseaux d'administration (M00-E27).
- Journal d'accès de l'API (`/var/log/pveproxy/access.log`) collecté et corrélé avec le journal des tâches.

---
### M00-E18 — Créer une VM uniquement par l'API

**Solution**

Script complet : [`fichiers/M00-E18/vm-api.sh`](fichiers/M00-E18/vm-api.sh), à copier dans `~/lab-scripts/vm-api.sh` (`chmod 700`). Ses briques :

1. **Appel générique** (`_call` et `api`) : `curl -X <MÉTHODE>`, paramètres en `--data-urlencode` (dans l'URL avec `-G` pour GET et DELETE), en-tête d'authentification lu depuis un fichier temporaire en mode 600 (`-H @fichier`), en-têtes de réponse sauvegardés (`-D`) pour récupérer la ligne de statut : Proxmox y place le motif de l'erreur (`HTTP/1.1 403 Permission check failed (/vms/5001, VM.Allocate)`).
2. **Attente de tâche** (`wait_task`) : `GET /nodes/{node}/tasks/{upid}/status` toutes les 2 s, jusqu'à `status=stopped` ; `exitstatus` doit valoir `OK` (ou `WARNINGS: n`, journalisé) ; délai maximal de 600 s.
3. **`create`** : `GET /cluster/nextid?vmid=5001` (400 si le VMID est pris, quelles que soient nos permissions), `POST …/qemu/9000/clone` (`newid`, `name`, `pool=lab`, `full=0`), `POST …/qemu/5001/config` (`net0`, `ipconfig0`, `nameserver`, `searchdomain`, `ciuser`, `sshkeys` ; pas `agent`, déjà activé dans le template avec ses options, qu'on écraserait), `POST …/status/start`, puis `POST …/agent/ping` en boucle jusqu'à 200.
4. **`ip`** : `GET …/agent/network-get-interfaces`, filtrage `jq` des adresses IPv4 hors `lo`, en boucle tant que le DHCP n'a pas répondu.
5. **`destroy`** : garde-fou (`GET /cluster/resources?type=vm` : la VM 5001 doit s'appeler `sbx01` et être dans le pool `lab`), `POST …/status/stop` si elle tourne, `DELETE …/qemu/5001?purge=1&destroy-unreferenced-disks=1`.
6. **`cycle`** : tout enchaîne, avec un test SSH qui attend la fin de cloud-init (`cloud-init status --wait`).

Exécution :
```
admin@adm01:~$ ~/lab-scripts/vm-api.sh cycle
[10:02:11] clone lié du template 9000 vers 5001 (sbx01), pool lab
[10:02:14] configuration réseau et cloud-init (net0 VLAN 99, ip=dhcp)
[10:02:16] démarrage
[10:02:18] attente de l'agent QEMU (au plus 300s)
[10:02:41] agent QEMU opérationnel
[10:02:44] adresse de sbx01 : 10.10.99.143
[10:02:44] test SSH vers admin@10.10.99.143 (cloud-init peut encore poser la clé)
sbx01
[10:02:58] arrêt de 5001
[10:03:00] destruction de 5001 (purge des références, disques orphelins compris)
[10:03:03] VM 5001 détruite
[10:03:03] cycle complet en 52s
```
Échecs provoqués :
```
admin@adm01:~$ ~/lab-scripts/vm-api.sh create; ~/lab-scripts/vm-api.sh create
…
ERREUR : le VMID 5001 est déjà pris : rien n'a été modifié
admin@adm01:~$ PVE_ENV_FILE=/tmp/faux.env ~/lab-scripts/vm-api.sh create      # secret erroné
ERREUR : GET /cluster/nextid → HTTP/1.1 401 authentication failure
```

**Explications**

- **UPID** : identifiant unique de tâche, de la forme `UPID:<nœud>:<pid>:<pstart>:<début>:<type>:<id>:<utilisateur>:` (par exemple `…:qmclone:9000:wb-automation@pve!lab:`). Tout ce qui prend du temps (clone, démarrage, arrêt, destruction) est **asynchrone** : l'API répond immédiatement avec l'UPID, et le travail continue dans un processus de fond. Enchaîner sans attendre donne « VM is locked (clone) ». C'est exactement ce que fait un *provider* Terraform entre deux ressources.
- **`POST` et `PUT` sur `/config`** : `PUT` est synchrone (et limité), `POST` est asynchrone et renvoie un UPID quand une allocation ou un branchement à chaud est nécessaire. Le script accepte les deux cas (`.data // empty`).
- **Encodage de `sshkeys`** : Proxmox stocke la valeur encodée en URL dans la configuration de la VM et la décode en générant le lecteur cloud-init. Il faut donc l'encoder **avant** de l'envoyer (`jq '@uri'`, espaces en `%20`) ; `curl --data-urlencode` l'encode une seconde fois pour le formulaire. Une clé envoyée « en clair » est refusée ou arrive tronquée à l'espace.
- **`/cluster/nextid?vmid=`** : un jeton limité au pool reçoit 403 sur une VM hors pool, ce qui ne dit pas si elle existe. `nextid` répond pour tout le nœud sans dépendre des droits sur la VM.
- **Agent prêt ≠ VM prête** : l'agent démarre tôt ; le DHCP, puis cloud-init (création de l'utilisateur, dépôt de la clé) arrivent ensuite. D'où l'attente de l'adresse, puis des tentatives SSH avec `cloud-init status --wait`.
- **`set -e` et substitutions** : `wait_task "$(api …)"` ignore l'échec de `api` (le code de retour d'une substitution utilisée comme argument est perdu) ; le script affecte toujours le résultat à une variable d'abord. Même logique pour `local x=$(…)`, qui masque le code de retour.
- **Arrêt brutal** : pour une sandbox jetable, `stop` (débrancher la prise) est acceptable. Pour une VM de valeur : `shutdown` avec délai, puis `stop` seulement en dernier recours.

**Alternatives**

- **Python** (`requests`, puis `proxmoxer`) : gestion d'erreurs et JSON plus confortables (module 02).
- **Terraform/OpenTofu**, *provider* `bpg/proxmox` (module 05) : déclaratif, gère l'état, l'attente des tâches et l'idempotence.
- **Ansible**, `community.general.proxmox_kvm` (module 04).
- **`pvesh` en SSH sur `pve01`** : simple, mais exige un accès root à l'hyperviseur, exactement ce qu'on veut éviter pour l'automatisation.

**Pièges classiques**

- Ne pas attendre la fin du clone avant de configurer ou démarrer.
- Ignorer l'UPID renvoyé par `POST …/config`.
- `sshkeys` non encodée.
- Prendre la première adresse renvoyée par l'agent : c'est souvent `127.0.0.1` ou une adresse IPv6 de lien local.
- Détruire « la VM 5001 » sans vérifier que c'est bien la sienne : le jour où un collègue y a mis autre chose, le script efface son travail. Le pool limite les dégâts ; le garde-fou nom + pool les évite.
- Secret visible : `set -x`, `curl -v`, argument de `curl -H` visible dans `ps`, fichier `.env` dans le dépôt.
- Erreurs 500 de l'agent pendant l'attente (« QEMU guest agent is not running ») : normales, il faut les tolérer **jusqu'au délai maximal**, pas indéfiniment.

**En production chez MédiSphère**

- Terraform pour la création, Ansible pour la configuration ; les scripts maison restent des outils de diagnostic.
- Réessais avec temporisation croissante sur les erreurs transitoires (503, délais), verrou (`flock`) contre les exécutions concurrentes, journalisation structurée.
- Jetons distincts par outil, secrets délivrés par Vault (module 25), traces des appels corrélées avec le journal des tâches de Proxmox.

---

### M00-E19 — Snapshots, clones liés et clones complets

**Solution**

1. Clone lié (exemple sur LVM-thin) :
   ```
   root@pve01:~# qm config 5002 | grep -E '^(scsi|virtio)0'
   scsi0: local-nvme:base-9000-disk-0/vm-5002-disk-0,discard=on,iothread=1,size=8G,ssd=1
   root@pve01:~# lvs -o lv_name,pool_lv,origin,data_percent | grep -E '9000|5002'
     base-9000-disk-0 data                    10.12
     vm-5002-disk-0   data base-9000-disk-0   10.40
   ```
   `origin` : le volume de 5002 est un **instantané fin** du volume de base. Il partage tous ses blocs ; seuls les blocs écrits par 5002 occupent de la place nouvelle (le `data_percent` affiché inclut les blocs partagés). Sur ZFS : `zfs list -o name,origin` montre `…/base-9000-disk-0@__base__` comme origine.

2. et 4. Snapshots :
   ```
   root@pve01:~# qm snapshot 5002 etat-initial --description "Juste après le clone"
   root@pve01:~# qm snapshot 5002 avec-ram --vmstate 1 --description "Avec processus en cours"
   root@pve01:~# qm listsnapshot 5002
   `-> etat-initial          2026-10-04 10:12:03     Juste après le clone
       `-> avec-ram          2026-10-04 10:19:40     Avec processus en cours
           `-> current                               You are here!
   root@pve01:~# grep -A3 '^\[avec-ram\]' /etc/pve/qemu-server/5002.conf
   [avec-ram]
   …
   vmstate: local-nvme:vm-5002-state-avec-ram
   ```
   L'état mémoire est un volume à part (`vm-5002-state-avec-ram`), de la taille de la RAM allouée environ. La copie de la RAM se fait VM en marche ; la pause finale ne dure qu'un instant (quelques centaines de millisecondes sur une petite VM). Si l'agent QEMU est actif, le journal de la tâche montre un gel/dégel des systèmes de fichiers autour du snapshot (à vérifier sur ta sortie).

5. `qm rollback 5002 etat-initial` : la VM est **arrêtée** (un snapshot sans RAM ne contient pas d'état d'exécution ; Proxmox arrête la VM pour revenir au disque). Au démarrage suivant : plus de marqueur, plus de paquet.

6. `qm rollback 5002 avec-ram` : la VM est **en marche** immédiatement, dans l'état exact du snapshot. Le compteur reprend à la valeur qu'il avait au moment du snapshot ; `uptime` repart de la valeur de ce moment. L'horloge de l'invité est **en retard** de la durée écoulée depuis le snapshot, jusqu'à ce que chrony la rattrape : sur une application sensible au temps (jetons, Kerberos, TLS), c'est un vrai sujet.

7. Clone complet :
   ```
   root@pve01:~# time qm clone 9000 5003 --name sbx03 --pool lab --full 1 --storage <STOCKAGE-VMS>
   root@pve01:~# qm config 5003 | grep -E '^(scsi|virtio)0'
   scsi0: local-nvme:vm-5003-disk-0,discard=on,iothread=1,size=8G,ssd=1
   ```
   Durée : quelques dizaines de secondes (copie des données réellement écrites du disque) contre une seconde pour le clone lié. Aucune origine : 5003 survivrait à la suppression du template.

8. Supprimer le template 9000 avec un clone lié vivant : Proxmox refuse de supprimer un volume de base encore utilisé par un clone lié (message du type « base volume … is still in use by linked cloned »). Selon la version et le stockage, d'autres éléments du template peuvent avoir été supprimés avant l'erreur : on n'essaie pas. Si le volume de base était corrompu, **tous** les clones liés le seraient aussi, puisqu'ils lisent ses blocs.

9. Tableau pour Julien :

   | Besoin | Outil | Pourquoi |
   |---|---|---|
   | Revenir en arrière après une mise à jour ratée (dans l'heure) | Snapshot sans RAM, pris juste avant | Retour en quelques secondes ; à supprimer une fois la mise à jour validée |
   | Reprendre un test exactement au même point, processus compris | Snapshot avec RAM | Seul outil qui restaure l'état d'exécution |
   | 10 VMs de test identiques, éphémères | Clones liés d'un template | Création instantanée, espace minimal |
   | Copie d'une VM qui doit vivre longtemps, ou être déplacée | Clone complet | Aucune dépendance au template ni au stockage d'origine |
   | Garder une copie pendant six mois | Sauvegarde PBS (rétention mensuelle) | Hors de l'hyperviseur, vérifiée, sur un autre site |
   | Se protéger d'une panne disque ou de la perte de `pve01` | Sauvegarde PBS | Un snapshot vit sur le même stockage que la VM |
   | Comparer deux versions côte à côte | Deux clones (liés si courte durée) | Deux VMs indépendantes, chacune avec son adresse |

10. Destruction : `qm destroy 5002 --purge` supprime aussi les snapshots et l'état mémoire ; `qm destroy 5003 --purge`.

**Explications**

- **Un snapshot dépend du stockage** : instantané fin sur LVM-thin, `zfs snapshot` sur ZFS, snapshot interne sur qcow2, snapshot RBD sur Ceph. Proxmox orchestre : gel éventuel via l'agent, snapshot de chaque disque, copie de la configuration dans une section `[nom]` du fichier de la VM, sauvegarde de la RAM si demandé.
- **Clone lié = copie sur écriture** : très rapide et économique, mais lié à vie au volume de base, et à son stockage (pas de déplacement du disque vers un autre stockage sans le convertir en disque complet).
- **Le template ne bouge plus** : convertir une VM en template rend ses disques en lecture seule (volumes `base-…`) précisément pour que des clones liés puissent s'y adosser.

**Alternatives**

- Disques qcow2 sur un stockage fichier : snapshots et clones liés possibles partout, au prix de performances un peu moindres.
- Ceph RBD (modules 08 et 09) : snapshots et clones liés natifs, partagés entre nœuds.
- Clone complet depuis un snapshot (`--snapname`) : utile pour « figer » un état dans une VM indépendante.

**Pièges classiques**

- **Garder des snapshots longtemps** sur LVM-thin : chaque bloc réécrit consomme de l'espace neuf, le pool fin se remplit sans que la VM « grossisse ». Un pool fin plein met **toutes** les VMs qui l'utilisent en erreur d'entrées/sorties.
- Croire qu'un snapshot est une sauvegarde : même disque, même hyperviseur, même stockage.
- Restaurer un snapshot avec RAM et oublier le saut d'horloge.
- Snapshot impossible sur une VM avec un périphérique en *passthrough* PCI, ou sur un stockage qui ne les supporte pas (LVM classique, raw sur répertoire).
- Supprimer un snapshot ancien sur qcow2 : la fusion coûte des entrées/sorties, à planifier.

**En production chez MédiSphère**

- Politique écrite : snapshot avant tout changement, nommé `avant-maj-<AAAAMMJJ>` (convention reprise en M00-E34), supprimé sous 72 h ; un script de supervision signale les snapshots plus anciens.
- Alerte sur le remplissage des pools fins (données **et** métadonnées).
- Clones liés réservés aux environnements éphémères (CI, tests) ; tout ce qui doit durer est un clone complet ou une VM déployée par IaC.

---

### M00-E20 — Réinstaller `hp01` en Proxmox Backup Server

**Solution**

1. **Go/no-go** (exemple) :

   | Contrôle | Preuve | État |
   |---|---|---|
   | E04 validé | `photos.sha256` comparé, 0 écart, copie relue depuis le second support | ☐ |
   | Seconde copie hors de `hp01` | Emplacement noté, test d'ouverture de 10 fichiers au hasard | ☐ |
   | Accès console | iLO testé (ou écran + clavier branchés) | ☐ |
   | ISO vérifiée | `sha256sum` identique à la valeur publiée | ☐ |
   | Inventaire relevé | `lsblk -o NAME,SIZE,MODEL,SERIAL`, `smartctl -H`, `ip -br link` (MAC) | ☐ |
   | Adresse LAN réservée | Réservation DHCP ou adresse statique hors plage de la box | ☐ |
   | Retour arrière | Aucun : l'installation efface les disques. Décision assumée. | ☐ |

2. **iLO** : sur un ProLiant de génération 8 (Xeon E3 v2), l'iLO 4 en licence standard limite la console graphique et le média virtuel ; la licence « Advanced » les débloque. Le micrologiciel récent apporte une console HTML5 (plus besoin de Java ou .NET). Sans licence : clé USB.
   ```
   admin@poste:~$ sha256sum proxmox-backup-server_4.*.iso      # comparer avec le site
   admin@poste:~$ lsblk -d -o NAME,SIZE,MODEL,TRAN               # repérer la clé (TRAN=usb)
   admin@poste:~$ sudo dd if=proxmox-backup-server_4.*.iso of=/dev/<CLE-USB> bs=4M conv=fsync status=progress
   ```

3. **Disposition** (cas d'un disque unique de 2 To) : ext4 ou XFS, options avancées de l'installateur : `swapsize` 4 Go, `minfree` réglé pour laisser environ 1,8 To libres dans le groupe de volumes `pbs` ; la racine fait alors une centaine de Go. Après installation :
   ```
   root@pbs01:~# vgs pbs
   root@pbs01:~# lvcreate -n ds-lab -l 95%FREE pbs
   root@pbs01:~# mkfs.ext4 -L ds-lab /dev/pbs/ds-lab
   root@pbs01:~# mkdir -p /mnt/datastore/ds-lab
   root@pbs01:~# echo 'LABEL=ds-lab /mnt/datastore/ds-lab ext4 defaults 0 2' >> /etc/fstab
   root@pbs01:~# systemctl daemon-reload && mount /mnt/datastore/ds-lab && df -h /mnt/datastore/ds-lab
   ```
   Avec deux disques : système sur le premier, datastore sur le second, par exemple avec `proxmox-backup-manager disk fs create ds-lab --disk <DISQUE> --filesystem ext4 --add-datastore true` (en E22 ; cette commande crée aussi l'unité de montage).
   Choix du système de fichiers : ZFS apporte sommes de contrôle et compression, mais sur **un seul** disque il détecte la corruption sans pouvoir la réparer, et son cache (ARC) consomme une part notable des 16 Go. PBS compresse déjà (zstd) et vérifie déjà les *chunks* par leur empreinte SHA-256 (tâches de vérification). ext4 ou XFS est le choix raisonnable ici.

4. Installation : rien de particulier, sinon le FQDN `pbs01.par2.medisphere.internal`, l'adresse statique, et la bonne carte réseau (celle qui est câblée : repère la MAC relevée à l'étape 1).

5. Premier accès et empreinte :
   ```
   root@pbs01:~# proxmox-backup-manager cert info | grep -i fingerprint
   Fingerprint (sha256): 64:d3:ff:…:ab:fe
   ```

6. Dépôts : [`fichiers/M00-E20/proxmox.sources`](fichiers/M00-E20/proxmox.sources) et [`fichiers/M00-E20/pbs-enterprise.sources`](fichiers/M00-E20/pbs-enterprise.sources) (`Enabled: no`).
   ```
   root@pbs01:~# apt update && apt full-upgrade
   root@pbs01:~# proxmox-backup-manager versions
   proxmox-backup-server 4.x.y running version: 4.x.y
   root@pbs01:~# [ -f /var/run/reboot-required ] && echo "redémarrage nécessaire"; uname -r
   ```

7. Réseau : [`fichiers/M00-E20/interfaces`](fichiers/M00-E20/interfaces).
   ```
   root@pbs01:~# ifreload -a
   root@pbs01:~# ip -br addr show vmbr1
   vmbr1   DOWN   10.20.10.10/24
   root@pbs01:~# ip route show table local | grep 10.20.10.10
   local 10.20.10.10 dev vmbr1 proto kernel scope host src 10.20.10.10
   ```
   `DOWN` (pas de porteuse) est normal : aucun port dans le pont. L'adresse est néanmoins **locale** (table `local`) : Linux accepte un paquet destiné à 10.20.10.10 quelle que soit son interface d'arrivée (modèle d'hôte « faible »). Il suffit que le pont soit administrativement actif.

8. Accès depuis `adm01`. D'abord le pare-feu de `gw01` : [`fichiers/M00-E20/gw01-nftables-extrait.nft`](fichiers/M00-E20/gw01-nftables-extrait.nft) (MGMT vers `<IP-HP01-LAN>` en SSH et 8007 ; le masquage de E10 fait que `hp01` voit `<IP-GW01-WAN>` et sait répondre). Puis :
   ```
   admin@adm01:~$ ssh-copy-id root@<IP-HP01-LAN>       # ou ajout par la console si le mot de passe root est refusé en SSH
   admin@adm01:~$ ssh root@<IP-HP01-LAN> hostname -f
   pbs01.par2.medisphere.internal
   ```

9. Temps : `timedatectl` (fuseau `Europe/Paris`, `System clock synchronized: yes`), `chronyc tracking`.

**Explications**

- **Séparer système et datastore** : un datastore plein ne doit pas remplir la racine (services PBS, journaux, `apt` qui échouent). Et réinstaller le système sans toucher au datastore devient possible : PBS sait réouvrir un datastore existant.
- **`apt full-upgrade`** : les mises à jour Proxmox ajoutent ou retirent parfois des dépendances ; `apt upgrade` les retient et laisse un système incohérent.
- **Dépôts** : `pbs-enterprise` (abonnement, paquets les plus éprouvés), `pbs-no-subscription` (gratuit, adapté au lab), `pbstest` (à ne pas utiliser). Format deb822 (`.sources`) par défaut sur Debian 13.

**Alternatives**

- **Installer Debian 13, puis le paquet `proxmox-backup-server`** : partitionnement libre avec l'installateur Debian (par exemple, LVM sur mesure ou RAID logiciel), au prix d'étapes manuelles.
- **Proxmox VE sur `hp01` avec PBS en VM** : plus souple (QDevice, petit site de repli dans des VMs), mais une couche de plus entre PBS et ses disques.
- **PBS en VM sur `pve01`** : à exclure, la sauvegarde serait sur le même site et le même matériel que ce qu'elle protège.

**Pièges classiques**

- Installer sur la clé USB ou sur le mauvais disque : vérifie modèle et taille dans l'installateur.
- Adresse par DHCP sans réservation : le point d'accès WireGuard et `WB_PBS_LAN` changent au prochain bail.
- Oublier le dépôt sans abonnement : `apt update` échoue en 401 et aucune mise à jour n'arrive.
- iLO accessible sur le LAN avec son mot de passe d'usine (étiquette sur le serveur).
- Datastore créé sur la racine « pour commencer » : on ne le déplace plus facilement ensuite.

**En production chez MédiSphère**

- Serveur de sauvegarde avec disques redondants (ZFS en miroir ou RAIDZ, ou RAID matériel), mémoire ECC, onduleur.
- Abonnement et dépôt d'entreprise, micrologiciels à jour (outil de mise à jour du constructeur), supervision SMART et iLO.
- Interface iLO sur un réseau de gestion dédié, comptes nominatifs, jamais exposée au réseau des utilisateurs.

---

### M00-E21 — Tunnel inter-sites PAR1 ↔ PAR2

**Solution**

1. **Analyse des flux** :

   | Flux | Aller | Retour | Bilan |
   |---|---|---|---|
   | `adm01` → `pbs01`:8007 | `adm01` → `gw01` (passerelle) → route 10.20.0.0/16 → `wg0` → `pbs01` | `pbs01` : 10.10.10.10 ∈ 10.10.0.0/16 → `wg0` → `gw01` → `adm01` | Symétrique |
   | Poste (10.255.1.2) → `pbs01`:8007 | poste → `wg1` → `gw01` → `wg0` → `pbs01` | `pbs01` : 10.255.1.2 → `wg0` **si** 10.255.1.0/24 est routé vers `wg0` et dans les `AllowedIPs` de `pbs01` | Symétrique si on l'y met |
   | `pve01` → `pbs01`:8007 | `pve01` → route statique → `gw01` (WAN) → `wg0` → `pbs01` | `pbs01` : `<IP-PVE01>` est sur **son** LAN (route connectée) → sortie directe par la carte LAN, en clair | **Asymétrique** |

   Conséquences de l'asymétrie : la moitié du trafic de sauvegarde (les réponses de PBS, données des restaurations comprises) circule **en clair** sur le LAN, ce que le ticket interdit ; `gw01` ne voit qu'un sens de la connexion, et sa règle `ct state invalid drop` peut jeter les paquets suivants de `pve01` (conntrack n'a jamais vu le SYN-ACK).
   Solutions :
   - **(retenue) Masquer sur `gw01`** ce qui va du LAN maison vers `wg0` : `pbs01` voit la source 10.255.0.1 et répond par le tunnel. Une règle, aucun changement sur `pbs01`. Contrepartie : `pbs01` ne distingue plus les clients du LAN maison entre eux (seul `pve01` est autorisé de toute façon, et il s'authentifie par son jeton).
   - Routage spécifique sur `pbs01` : `<IP-PVE01>/32` via `wg0` (et dans les `AllowedIPs`). Fonctionne, mais casse tout échange direct `pve01` ↔ `hp01` sur le LAN et doit être maintenu pour chaque nouvel hôte.
   - Faire sortir les sauvegardes de `pve01` depuis une adresse du lab (une interface de `pve01` dans le VLAN MGMT, route 10.20.0.0/16 avec cette source) : le plus propre à terme, mais modifie le réseau de l'hyperviseur.

2. Clés et configurations :
   ```
   root@gw01:~# umask 077; wg genkey | tee /etc/wireguard/wg0.key | wg pubkey > /etc/wireguard/wg0.pub
   root@pbs01:~# apt install -y wireguard-tools
   root@pbs01:~# umask 077; wg genkey | tee /etc/wireguard/wg0.key | wg pubkey > /etc/wireguard/wg0.pub
   ```
   [`fichiers/M00-E21/gw01-wg0.conf`](fichiers/M00-E21/gw01-wg0.conf) et [`fichiers/M00-E21/pbs01-wg0.conf`](fichiers/M00-E21/pbs01-wg0.conf).
   Côté `pbs01`, les routes ne sont **pas** laissées à `wg-quick` : celles qu'il déduit des `AllowedIPs` (`10.10.0.0/16 dev wg0`) n'ont pas d'adresse source préférée, et le noyau prendrait alors l'adresse de `wg0`, 10.255.0.2. Tout ce que `pbs01` émet lui-même vers PAR1 (DNS vers `dns01`, NTP en M00-E31) arriverait avec une source que les règles de `gw01`, écrites pour PAR2 = 10.20.0.0/16, ne reconnaissent pas. D'où, dans `[Interface]` :
   ```
   Table = off
   PostUp = ip route add 10.10.0.0/16 dev %i src 10.20.10.10
   PostUp = ip route add 10.255.1.0/24 dev %i src 10.20.10.10
   PreDown = ip route del 10.10.0.0/16 dev %i || true
   PreDown = ip route del 10.255.1.0/24 dev %i || true
   ```
   `Table = off` empêche `wg-quick` de créer ses routes ; `%i` est remplacé par le nom de l'interface ; `src` n'est accepté que pour une adresse locale (10.20.10.10 est sur `vmbr1` depuis E20, qui doit donc être monté avant le tunnel). Les `AllowedIPs` restent indispensables : elles ne servent plus à créer des routes, mais toujours au routage par clé.

3. Activation et contrôle :
   ```
   root@gw01:~# systemctl enable --now wg-quick@wg0
   root@pbs01:~# systemctl enable --now wg-quick@wg0
   root@gw01:~# wg show wg0 latest-handshakes
   Vx3…=	1767521003
   root@gw01:~# ip route get 10.20.10.10
   10.20.10.10 dev wg0 src 10.255.0.1 uid 0
   root@pbs01:~# ip route get 10.10.10.10
   10.10.10.10 dev wg0 src 10.20.10.10 uid 0
   ```

4. `gw01` : [`fichiers/M00-E21/gw01-nftables-extrait.nft`](fichiers/M00-E21/gw01-nftables-extrait.nft) : WireGuard depuis `<IP-HP01-LAN>`, règle MGMT de E10 étendue à `wg0`, VPN vers PAR2 MGMT, `pve01` vers 8007, et le masquage `oifname $WG_S2S ip saddr $LAN_MAISON masquerade`. Le DNS de `pbs01` vers `dns01` passe déjà par la règle DNS de E13 (source 10.20.10.10 ∈ 10.20.0.0/16, grâce aux routes `src`) ; le NTP sera ouvert en M00-E31.

5. `pbs01` : [`fichiers/M00-E21/pbs01-nftables.conf`](fichiers/M00-E21/pbs01-nftables.conf). PBS n'embarque pas le pare-feu intégré de Proxmox VE (ni `pve-firewall`, ni `proxmox-firewall`) : nftables, natif dans Debian 13, est l'outil naturel. Application avec filet de sécurité :
   ```
   root@pbs01:~# apt install -y nftables
   root@pbs01:~# nft -c -f /root/nftables.conf.nouveau
   root@pbs01:~# systemd-run --unit=nft-secours --on-active=5min /usr/sbin/nft flush ruleset
   root@pbs01:~# nft -f /root/nftables.conf.nouveau
   ```
   Depuis une **nouvelle** session : `ssh pbs01 true` depuis `adm01`, interface web depuis le poste par le VPN. Si tout va bien :
   ```
   root@pbs01:~# systemctl stop nft-secours.timer
   root@pbs01:~# install -m 0644 /root/nftables.conf.nouveau /etc/nftables.conf
   root@pbs01:~# systemctl enable --now nftables
   ```
   Si tu t'es coupé l'accès : attends cinq minutes, les règles sont vidées.

6. Tests :
   ```
   admin@adm01:~$ curl -sk -o /dev/null -w '%{http_code}\n' https://10.20.10.10:8007/      # 200
   admin@adm01:~$ timeout 3 bash -c '</dev/tcp/<IP-HP01-LAN>/8007' || echo fermé         # fermé
   ```

7. Preuve de chiffrement, pendant qu'on teste depuis `pve01` (`curl -sk https://10.20.10.10:8007/ >/dev/null` en boucle) :
   ```
   root@pbs01:~# tcpdump -ni <NIC-HP01-LAN> 'host <IP-PVE01> and not port 51820'
   (rien)
   root@pbs01:~# tcpdump -ni <NIC-HP01-LAN> -c 4 udp port 51820
   IP <IP-GW01-WAN>.51820 > <IP-HP01-LAN>.51820: UDP, length 128
   IP <IP-HP01-LAN>.51820 > <IP-GW01-WAN>.51820: UDP, length 96
   ```
   On doit voir uniquement de l'UDP 51820 entre `gw01` et `hp01` ; on ne doit **jamais** voir de TCP 8007 entre `pve01` et `hp01`.

8. MTU :
   ```
   root@gw01:~# ip link show wg0 | head -1
   7: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
   admin@adm01:~$ ping -M do -c1 -s 1392 10.20.10.10       # 1392 + 8 (ICMP) + 20 (IP) = 1420 : passe
   admin@adm01:~$ ping -M do -c1 -s 1393 10.20.10.10
   From 10.10.10.1 icmp_seq=1 Frag needed and DF set (mtu = 1420)
   admin@adm01:~$ ping -M do -c1 -s 1393 10.20.10.10
   ping: local error: message too long, mtu=1420
   ```
   1420 = 1500 − 80 : `wg-quick` retire le surcoût de WireGuard dans le pire cas (en-tête IPv6 externe 40 + UDP 8 + WireGuard 32). Au-dessus, `gw01` jette le paquet (DF positionné) et renvoie un ICMP « fragmentation needed » avec la MTU ; `adm01` la mémorise (deuxième ping : erreur locale immédiate).
   Pour TCP depuis `pve01` : ses segments font 1 500 octets (MSS 1460). Arrivés à `gw01`, ils sont trop gros pour `wg0` : tout repose sur la **découverte de MTU** (ICMP de `gw01` vers `pve01`, `pve01` réduit la taille pour cette destination). Si un pare-feu jette ces ICMP, on obtient le symptôme classique : les petits échanges passent, les gros transferts se figent. La parade robuste (réécrire la MSS des SYN sur `gw01`) est l'objet de M00-E41.

**Explications**

- **`AllowedIPs` site à site** : côté `gw01`, `10.20.0.0/16` (tout PAR2) ; côté `pbs01`, `10.10.0.0/16` et `10.255.1.0/24` (le lab PAR1 et le VPN d'administration). Sur `gw01`, `wg-quick` en déduit les routes ; sur `pbs01`, on les pose soi-même avec `src 10.20.10.10` (`Table = off`). Le LAN maison n'y figure jamais : chaque site y est directement connecté, et y mettre son préfixe ferait passer l'extrémité elle-même dans le tunnel (boucle).
- **`PersistentKeepalive`** : un paquet toutes les 25 s maintient la session et les états conntrack sur le chemin, et donne un indicateur de santé (âge de la dernière poignée de main).
- **Pare-feu des deux côtés** : `gw01` protège le lab ; `pbs01` est directement sur le LAN maison, à portée de tout appareil du foyer : il lui faut son propre filtrage (défense en profondeur). `proxmox-backup-proxy` écoute sur toutes les adresses : seul le pare-feu limite l'exposition du port 8007.

**Alternatives**

- **IPsec (strongSwan)** entre `gw01` et `pbs01` : standard, interopérable avec du matériel réseau, plus lourd à configurer et à diagnostiquer.
- **Tunnel GRE ou VXLAN au-dessus de WireGuard, avec OSPF/BGP** (FRR, module 07) : routage dynamique, plusieurs chemins.
- **Pas de tunnel, TLS de PBS seul** : le trafic de sauvegarde est déjà chiffré par TLS. Mais le ticket demande que PAR2 ne soit joignable **que** par un lien chiffré et authentifié au niveau réseau, et le tunnel protège aussi SSH, DNS, NTP et les futurs flux (QDevice, réplication).

**Pièges classiques**

- Oublier 10.255.1.0/24 dans les `AllowedIPs` (et la route correspondante) de `pbs01` : l'interface web est injoignable depuis le VPN (les réponses partent vers la box).
- Laisser `wg-quick` poser les routes de `pbs01` : il émet vers PAR1 depuis 10.255.0.2, hors de 10.20.0.0/16. Le DNS et (en M00-E31) le NTP de `pbs01` sont alors refusés par `gw01` ou ignorés par chrony, sans message clair.
- `Table = off` sans les `PostUp` : plus aucune route vers PAR1, le tunnel est établi mais rien ne passe.
- Ne pas voir l'asymétrie de `pve01` : « ça marche » en apparence, mais le retour circule en clair.
- Se couper l'accès à `pbs01` en appliquant le pare-feu sans filet de sécurité.
- Mettre l'adresse de l'extrémité dans les `AllowedIPs` : le trafic du tunnel tente de passer… dans le tunnel.
- Bloquer l'ICMP « fragmentation needed » quelque part sur le chemin : transferts qui se figent (M00-E41).
- Un seul côté avec `PersistentKeepalive` alors que l'autre redémarre souvent : la reprise attend le premier paquet utile.

**En production chez MédiSphère**

- Deux liens inter-sites indépendants, deux tunnels, routage dynamique et bascule automatique (module 07).
- Supervision : âge de la dernière poignée de main, latence et pertes à travers le tunnel, débit pendant la fenêtre de sauvegarde.
- Rotation des clés planifiée, matrice des flux inter-sites documentée et revue (exigence HDS : chiffrement des flux de données de santé, traçabilité des accès).
- Réseau de sauvegarde dédié, séparé du réseau d'administration.

---
### M00-E22 — Datastore, rétention et tâches de sauvegarde

**Solution**

1. Datastore :
   ```
   root@pbs01:~# proxmox-backup-manager datastore create ds-lab /mnt/datastore/ds-lab --comment "Sauvegardes du lab PAR1 (PLAT-122)"
   root@pbs01:~# ls -A /mnt/datastore/ds-lab
   .chunks  .lock  lost+found
   root@pbs01:~# ls /mnt/datastore/ds-lab/.chunks | head -3; ls /mnt/datastore/ds-lab/.chunks | wc -l
   0000
   0001
   0002
   65536
   ```
   Chaque *chunk* est rangé sous les 4 premiers caractères hexadécimaux de son empreinte SHA-256 : 16 bits, donc 65 536 répertoires. Les répertoires restent de taille raisonnable même avec des millions de *chunks*, et les créer d'avance évite des `mkdir` concurrents pendant les sauvegardes.

2. Namespace : interface web (*Datastore → ds-lab → Content → Add Namespace*), ou :
   ```
   root@pbs01:~# proxmox-backup-client namespace create par1 --repository root@pam@localhost:ds-lab
   ```
   Sur disque, il apparaît comme `/mnt/datastore/ds-lab/ns/par1/`.

3. Compte, jeton, ACL :
   ```
   root@pbs01:~# proxmox-backup-manager user create wb-backup@pbs --comment "Sauvegardes de pve01 (PLAT-122)"
   root@pbs01:~# proxmox-backup-manager user generate-token wb-backup@pbs pve01 --comment "Stockage pbs-par2 de pve01"
   Result: {
     "tokenid": "wb-backup@pbs!pve01",
     "value": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
   }
   root@pbs01:~# proxmox-backup-manager acl update /datastore/ds-lab/par1 DatastoreBackup --auth-id wb-backup@pbs
   root@pbs01:~# proxmox-backup-manager acl update /datastore/ds-lab/par1 DatastoreBackup --auth-id 'wb-backup@pbs!pve01'
   root@pbs01:~# proxmox-backup-manager user permissions 'wb-backup@pbs!pve01' --path /datastore/ds-lab/par1
   Privileges with (*) have the propagate flag set

   Path: /datastore/ds-lab/par1
   - Datastore.Backup (*)
   ```
   **Rôle** : `DatastoreBackup` (sauvegarder et restaurer **ses propres** groupes), pas `DatastorePowerUser` (qui ajoute la purge de ses sauvegardes). **Chemin** : le namespace, au plus près du besoin. **Qui** : l'utilisateur **et** le jeton, car les droits d'un jeton PBS sont l'intersection des siens et de ceux de son utilisateur. Si `pvesm status` affichait ensuite le stockage inactif faute de pouvoir lire l'état du datastore, pose les ACL sur `/datastore/ds-lab` (le comportement avec des droits limités à un namespace est à vérifier selon les versions).

4. Raccordement de `pve01`, secret saisi sans écho et hors historique :
   ```
   root@pbs01:~# proxmox-backup-manager cert info | grep -i fingerprint
   root@pve01:~# read -rs PBS_SECRET        # coller le secret puis Entrée
   root@pve01:~# pvesm add pbs pbs-par2 --server 10.20.10.10 --datastore ds-lab --namespace par1 \
                   --username 'wb-backup@pbs!pve01' --password "$PBS_SECRET" \
                   --fingerprint '<EMPREINTE-SHA256>' --content backup
   root@pve01:~# unset PBS_SECRET
   root@pve01:~# pvesm status --storage pbs-par2
   Name            Type     Status           Total            Used       Available        %
   pbs-par2         pbs     active      1771000000        52000000      1718948000    0.00%
   ```
   Le secret est rangé par Proxmox dans `/etc/pve/priv/storage/pbs-par2.pw` (lisible par root seul). L'empreinte **épingle** le certificat autosigné de PBS : sans elle, le client refuserait la connexion (ou, pire, il faudrait désactiver la vérification).

5. Tâche de sauvegarde :
   ```
   root@pve01:~# pvesh create /cluster/backup --id lab-nuit --schedule '02:30' --storage pbs-par2 \
                   --pool lab --mode snapshot --enabled 1 --prune-backups 'keep-all=1' \
                   --notes-template '{{guestname}}' --comment "Pool lab vers PAR2 (PLAT-122)"
   root@pve01:~# pvesh get /cluster/backup/lab-nuit
   ```
   **La purge se fait sur PBS**, pas dans la tâche : le jeton n'a pas le privilège de purge (`DatastoreBackup`), une purge déclenchée par `pve01` échouerait (ou serait signalée en erreur à chaque sauvegarde). Surtout, c'est le but : la politique de rétention vit côté serveur, là où un client compromis ne peut pas la modifier. `keep-all=1` dans la tâche rend ce choix explicite.
   Le template 9000 et les VMs de la sandbox présentes à 02:30 sont aussi sauvegardés (membres du pool). C'est acceptable ici (petits volumes, forte déduplication) ; en production on sépare les pools ou on sélectionne par étiquette.

6. Première exécution : interface (*Datacenter → Backup → lab-nuit → Run now*) ou `vzdump --pool lab --storage pbs-par2 --mode snapshot`. Extraits du journal :
   ```
   INFO: Starting Backup of VM 1002 (qemu)
   INFO: issuing guest-agent 'fs-freeze' command
   INFO: issuing guest-agent 'fs-thaw' command
   INFO: started backup task '…'
   INFO: scsi0: dirty-bitmap status: created new
   INFO: transferred 3.1 GiB in 41 seconds (77.4 MiB/s)
   …
   (seconde exécution)
   INFO: scsi0: dirty-bitmap status: OK (124.0 MiB of 8.0 GiB dirty)
   INFO: using fast incremental mode (dirty-bitmap), 124.0 MiB dirty of 8.0 GiB total
   INFO: backup was done incrementally, reused 7.88 GiB (98%)
   ```
   (Libellés exacts à vérifier sur ta version.) La seconde sauvegarde ne lit que les blocs modifiés : quelques secondes au lieu de quelques minutes.

7. Tâches PBS :
   ```
   root@pbs01:~# proxmox-backup-manager prune-job create prune-par1 --store ds-lab --ns par1 \
                   --schedule '04:00' --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --comment "Rétention PLAT-122"
   root@pbs01:~# proxmox-backup-manager datastore update ds-lab --gc-schedule '05:00'
   root@pbs01:~# proxmox-backup-manager verify-job create verify-par1 --store ds-lab --ns par1 \
                   --schedule 'sat 07:00' --ignore-verified true --outdated-after 30
   ```

   | Heure | Tâche | Pourquoi là |
   |---|---|---|
   | 02:30 | Sauvegarde (`pve01`) | Activité minimale ; une demi-heure suffit pour le socle |
   | 04:00 | Purge du namespace `par1` | Après la sauvegarde : on purge en tenant compte de la nuit |
   | 05:00 | *Garbage collection* | Après la purge ; les *chunks* libérés aujourd'hui le seront réellement au passage de demain (délai de 24 h) |
   | Samedi 07:00 | Vérification | Lecture intégrale des nouveaux instantanés, et de chacun tous les 30 jours ; hors des autres tâches, le disque mécanique ne sait pas tout faire à la fois |

   `verify-new` est laissé **désactivé** : sur disque mécanique, relire chaque sauvegarde juste après l'avoir écrite double les entrées/sorties de la nuit. La vérification hebdomadaire couvre le besoin à ce niveau de criticité.

8. Simulateur de rétention : avec une sauvegarde par jour et 7/4/6, on garde au plus 17 points (une sauvegarde déjà retenue comme « quotidienne » n'est pas recomptée dans la « hebdomadaire »), couvrant environ six mois en arrière.

9. Preuve de non-suppression :
   ```
   root@pve01:~# vzdump 1002 --storage pbs-par2 --mode snapshot --notes-template 'test suppression PLAT-122'
   root@pve01:~# pvesm list pbs-par2 --vmid 1002 | tail -1
   root@pve01:~# pvesm free pbs-par2:backup/vm/1002/<HORODATAGE>
   … 403 … permission check failed …
   ```
   (Message exact à vérifier.) Supprime ensuite cette sauvegarde de test depuis l'interface PBS avec `root@pam`, ou laisse la purge s'en charger.

10. Couverture :
    ```
    root@pve01:~# pvesh get /cluster/backup-info/not-backed-up
    ```
    La liste ne doit contenir aucune VM du pool `lab` (les VMs personnelles hors pool peuvent y apparaître : leur sauvegarde ne relève pas du lab).

**Explications**

- **Structure d'une sauvegarde** : `ns/par1/vm/1002/<horodatage>/` contient l'index du disque (`drive-scsi0.img.fidx` : la liste ordonnée des empreintes de ses *chunks*), la configuration de la VM et le journal du client (`.blob`), et un manifeste signé (`index.json.blob`). Les données elles-mêmes sont dans `.chunks/`, partagées par tous les instantanés.
- **Deux sortes d'index** : disques de VM découpés en *chunks* de taille fixe (4 Mio, `.fidx`) ; sauvegardes de fichiers (`pxar`, hôtes et conteneurs) découpées à taille variable selon le contenu (`.didx`), pour que l'insertion d'un octet ne décale pas tous les *chunks* suivants.
- **Incrémental** : le *dirty bitmap* évite de **lire** les blocs inchangés ; la comparaison avec l'index précédent évite de **transférer** des *chunks* que le serveur a déjà. Sans bitmap (VM redémarrée), tout est relu, mais le transfert reste faible.
- **Purge, GC, vérification** : la purge supprime des **instantanés** (leurs index) selon la politique ; le *garbage collection* marque les *chunks* encore référencés (phase 1, mise à jour de l'`atime`), puis supprime ceux qui ne l'ont pas été depuis plus de 24 h et 5 min (phase 2, marge de sécurité pour les sauvegardes en cours et la sémantique `relatime`) ; la vérification relit les *chunks* et recalcule leurs empreintes.

**Alternatives**

- **Rétention côté `pve01`** avec un jeton `DatastorePowerUser` : plus simple à lire dans l'interface de PVE, mais un `pve01` compromis peut purger ses propres sauvegardes.
- **Synchronisation vers un second PBS en mode *pull*** (le serveur distant tire les données ; la source ne peut pas effacer la copie), ou vers un datastore amovible : la vraie protection contre la compromission (module 09, M00-E33).
- **`vzdump` vers NFS ou un répertoire** : pas de déduplication, chaque sauvegarde complète coûte sa taille pleine. Restic ou Borg : bons outils de sauvegarde de fichiers, sans l'intégration aux VMs.

**Pièges classiques**

- ACL posée sur l'utilisateur et pas sur le jeton (ou l'inverse) : « permission check failed » au premier `vzdump`.
- Empreinte qui ne correspond plus après régénération du certificat de PBS : stockage inactif, toutes les sauvegardes échouent cette nuit-là. Mettre à jour avec `pvesm set pbs-par2 --fingerprint …`.
- Rétention configurée **aussi** dans `pve01` avec un jeton qui n'a pas le droit de purger : erreurs à chaque sauvegarde.
- Attendre que `df` baisse juste après une purge (voir le délai du GC).
- Tâches lourdes qui se chevauchent sur un seul disque mécanique : tout ralentit, la sauvegarde déborde sur la matinée.
- Gros transferts qui se figent à travers le tunnel : problème de MTU (M00-E41), pas de PBS.

**En production chez MédiSphère**

- Notifications sur échec (M00-E29), chiffrement côté client (M00-E36), copie supplémentaire hors ligne ou immuable, instantanés « protégés » pour les points de restauration réglementaires.
- Supervision de l'âge de la dernière sauvegarde réussie **par VM**, et de la croissance du datastore.
- Tests de restauration planifiés (M00-E37) ; la sauvegarde n'est validée que par la restauration.

---

### M00-E23 — Restaurer une VM et un fichier

**Solution**

1. Choix de la sauvegarde :
   ```
   root@pve01:~# pvesm list pbs-par2 --vmid 1002
   Volid                                          Format  Type          Size VMID
   pbs-par2:backup/vm/1002/2026-10-03T00:30:04Z   pbs-vm  backup   8589934592 1002
   pbs-par2:backup/vm/1002/2026-10-04T00:30:03Z   pbs-vm  backup   8589934592 1002
   ```
   Les horodatages sont en UTC (02:30 à Paris = 00:30Z en été).

2. Restauration, sans démarrage :
   ```
   root@pve01:~# time qmrestore pbs-par2:backup/vm/1002/2026-10-04T00:30:03Z 5090 \
                   --storage <STOCKAGE-VMS> --pool lab --unique 1
   …
   restore image complete (bytes=8589934592, duration=…s, speed=… MB/s)
   ```
   `--unique 1` attribue de nouvelles adresses MAC. Le VMID 5090 est libre : aucun écrasement possible (sans `--force`, `qmrestore` refuse un VMID existant).

3. Neutralisation avant le premier démarrage :
   ```
   root@pve01:~# qm config 5090 | grep -E '^(name|net0|ipconfig0)'
   name: dns01
   net0: virtio=BC:24:11:5E:0A:77,bridge=vmbr1,tag=20
   ipconfig0: ip=10.10.20.10/24,gw=10.10.20.1
   root@pve01:~# qm set 5090 --name rst-dns01 --net0 virtio=BC:24:11:5E:0A:77,bridge=vmbr1,tag=20,link_down=1
   ```
   La MAC est reprise telle quelle, sinon Proxmox en génère une autre. Cloud-init : le nom d'hôte transmis à l'invité dérive du nom de la VM ; en la renommant, la configuration cloud-init change et l'invité peut la considérer comme une **nouvelle instance** au démarrage (nouveau nom d'hôte, clés d'hôte SSH régénérées ; comportement à vérifier selon les versions). Pour un test isolé, c'est sans conséquence, voire souhaitable. Pour une restauration **en remplacement** de l'original (RB-002), on garde au contraire nom, MAC et configuration identiques.

4. Démarrage et contrôle sans réseau, par l'agent :
   ```
   root@pve01:~# qm start 5090
   root@pve01:~# qm guest cmd 5090 ping && echo agent-ok
   root@pve01:~# qm guest exec 5090 -- systemctl is-active dnsmasq
   root@pve01:~# qm guest exec 5090 -- head -n 5 /etc/dnsmasq.d/medisphere.conf
   ```
   (`qm guest exec` renvoie un JSON avec `exitcode` et `out-data`.) Pendant ce temps, `dig @10.10.20.10 dns01.par1.medisphere.internal` depuis `adm01` répond toujours : l'original n'est pas perturbé.

5. Restauration de fichier en ligne de commande, avec les paramètres du stockage `pbs-par2` :
   ```
   root@pve01:~# export PBS_REPOSITORY='wb-backup@pbs!pve01@10.20.10.10:ds-lab'
   root@pve01:~# export PBS_PASSWORD_FILE=/etc/pve/priv/storage/pbs-par2.pw
   root@pve01:~# export PBS_FINGERPRINT='<EMPREINTE-SHA256>'
   root@pve01:~# SNAP=vm/1002/2026-10-04T00:30:03Z
   root@pve01:~# proxmox-file-restore list --ns par1 "$SNAP" /
   root@pve01:~# proxmox-file-restore list --ns par1 "$SNAP" /drive-scsi0.img.fidx/part
   root@pve01:~# proxmox-file-restore list --ns par1 "$SNAP" /drive-scsi0.img.fidx/part/1/etc/dnsmasq.d
   root@pve01:~# mkdir -p /root/restore-E23
   root@pve01:~# time proxmox-file-restore extract --ns par1 "$SNAP" \
                   /drive-scsi0.img.fidx/part/1/etc/dnsmasq.d/medisphere.conf /root/restore-E23/
   ```
   Le numéro de partition (`part/1` pour la racine d'une image Debian *genericcloud*) se découvre avec `list`. Le premier appel est lent (une dizaine de secondes) : il démarre une petite VM de restauration. Comparaison depuis `adm01` :
   ```
   admin@adm01:~$ diff <(ssh dns01 cat /etc/dnsmasq.d/medisphere.conf) <(ssh pve01 cat /root/restore-E23/medisphere.conf) && echo identique
   ```
   Par l'interface : *pbs-par2 → Backups → sauvegarde de 1002 → File Restore*, navigation jusqu'au fichier, *Download* (le fichier arrive dans ton navigateur ; copie-le ensuite sur `pve01`).

6. Restauration à chaud (`--live-restore 1`) : la VM démarre immédiatement ; les blocs pas encore restaurés sont lus à la demande depuis PBS pendant que la copie se poursuit en arrière-plan. **Quand** : un RTO très court sur une grosse VM, avec un PBS rapide et proche. **Risque** : si PBS ou le lien tombe pendant l'opération, la VM tourne sur un disque incomplet ; il faut l'arrêter et recommencer, et ce qu'elle a écrit entre-temps est perdu ; performances dégradées tant que la copie n'est pas finie. **Pas ici** : test sans urgence, petite VM, PBS sur disque mécanique derrière un tunnel.

7. Destruction : `qm stop 5090 && qm destroy 5090 --purge`.

**Explications**

- **Isoler avant de démarrer** : une copie de `dns01` active sur le VLAN 20 répondrait aux requêtes ARP pour 10.10.20.10. Les clients et `gw01` basculeraient de façon aléatoire entre les deux machines : panne de DNS intermittente pour tout le lab, très difficile à diagnostiquer. `link_down=1` garde la carte déclarée (pas de surprise au démarrage) mais débranchée.
- **`proxmox-file-restore`** : plutôt que de monter l'image disque sur l'hyperviseur (risqué : un système de fichiers malveillant ou corrompu monté par le noyau de l'hôte), il démarre une VM minimale qui lit l'image depuis PBS en lecture seule, monte les partitions **dans la VM**, et sert les fichiers à l'hôte. Il réutilise le dépôt, le namespace et le secret du stockage.
- **RTO mesuré** : le débit observé (tunnel + disque mécanique de `hp01` + disque de `pve01`) donne une base de calcul pour les runbooks et les objectifs de reprise.

**Alternatives**

- Restaurer la VM complète puis récupérer le fichier : beaucoup plus long pour un seul fichier.
- `proxmox-backup-client map` puis montage sur l'hôte : possible, mais avec le risque décrit plus haut.
- Restaurer dans un VLAN de quarantaine dédié aux tests de restauration, avec ses propres règles : plus réaliste pour tester le service réseau (prévu dans les finaux, F5).

**Pièges classiques**

- Démarrer la copie avec sa carte active dans le VLAN d'origine (doublon d'IP sur le DNS de tout le lab).
- `qmrestore … <VMID-EXISTANT> --force 1` sur le mauvais VMID : écrase les disques de la VM en place.
- Oublier `--unique` puis rebrancher la copie dans le même VLAN que l'original : MAC en double.
- Afficher le secret en préparant la restauration de fichier (`cat` du fichier `.pw`, `set -x`) : utiliser `PBS_PASSWORD_FILE`.
- Télécharger par le navigateur un fichier qui contient des données de santé sur un poste non maîtrisé : en production, c'est une fuite.

**En production chez MédiSphère**

- Restaurations de test planifiées (au moins mensuelles), dans un réseau de quarantaine, avec contrôle applicatif automatisé et mesure du temps ; résultats archivés pour l'audit HDS.
- Restauration de fichiers tracée (qui, quoi, quand, pourquoi) : c'est un accès à des données de santé.
- RTO et RPO par application, validés avec les métiers, et vérifiés par ces tests.

---
### M00-E24 — Questions d'exploitation : sauvegarde

**1. Réponse b.** En mode `snapshot`, pour une VM QEMU, Proxmox ne s'appuie pas sur un snapshot du stockage : QEMU démarre une tâche de sauvegarde qui lit le disque pendant que la VM tourne, et intercepte les écritures de l'invité (*copy-before-write*) : si un bloc pas encore sauvegardé va être modifié, son contenu d'origine est d'abord envoyé à la sauvegarde. Le résultat correspond à l'état du disque au début de la sauvegarde. a) décrit le mode `snapshot` des **conteneurs** LXC, pas des VMs. c) décrit grossièrement le mode `suspend`, conservé pour compatibilité ; en mode `snapshot`, la VM n'est gelée qu'un instant (et ses systèmes de fichiers, via l'agent). d) Faux : cela fonctionne avec tout format de disque.

**2.** Le *dirty bitmap* est une carte des blocs modifiés depuis la dernière sauvegarde réussie, tenue **en mémoire par le processus QEMU** de la VM. À la sauvegarde suivante vers la même cible, seuls ces blocs sont lus et envoyés : une VM de 100 Go peu active se sauvegarde en secondes. Il est perdu quand le processus QEMU s'arrête (arrêt puis démarrage de la VM, y compris un arrêt demandé depuis l'invité ; un simple redémarrage **dans** l'invité le conserve), quand la cible change (autre stockage, autre namespace), ou quand la sauvegarde précédente n'est plus utilisable (supprimée, vérification en échec, changement de clé de chiffrement). Le comportement lors d'une migration à chaud est à vérifier selon la version. Bitmap perdu : la sauvegarde suivante relit **tout** le disque (« created new » dans le journal) ; le transfert reste faible grâce à la déduplication, mais la durée et les lectures sur `pve01` explosent.

**3.** Les disques de VM sont découpés en *chunks* de taille fixe (4 Mio) ; les sauvegardes de fichiers (archives `pxar` d'hôtes ou de conteneurs) en *chunks* de taille variable, aux frontières calculées sur le contenu (empreinte glissante), pour qu'un octet inséré ne décale pas tout. Chaque *chunk* est identifié par l'empreinte SHA-256 de son contenu et stocké **une seule fois par datastore** (avec chiffrement, l'identifiant dépend de la clé : la déduplication ne joue qu'entre sauvegardes faites avec la même clé). La déduplication porte sur tout le datastore : entre instantanés d'une même VM, entre VMs, entre namespaces. Les VMs clonées d'un même template ont des blocs système identiques **aux mêmes positions**, donc les mêmes *chunks* de 4 Mio : ils ne sont stockés qu'une fois. Ensuite, chaque *chunk* est compressé (zstd).

**4. Réponse a.** La purge supprime des **index** d'instantanés. Les *chunks* restent sur disque tant que le *garbage collection* ne les a pas balayés : phase 1, il marque (mise à jour de l'`atime`) tous les *chunks* référencés par les index restants ; phase 2, il supprime ceux dont l'`atime` est antérieur à la limite (24 h et 5 min, ou le début de la plus ancienne sauvegarde en cours si elle est plus ancienne). Un *chunk* libéré aujourd'hui disparaît donc au plus tôt au GC du lendemain. b) `discard` concerne le TRIM vers le support, pas la logique de PBS. c) Cette corbeille n'existe pas sous cette forme. d) La vérification lit, elle ne libère rien.

**5.** Une tâche de vérification relit chaque *chunk* référencé par les instantanés visés, vérifie son intégrité (décompression, recalcul de l'empreinte et comparaison avec l'index ; pour des données chiffrées, contrôle d'intégrité sans déchiffrement) et marque l'instantané « vérifié » ou « en échec ». Un *chunk* corrompu est mis de côté pour qu'une prochaine sauvegarde le renvoie. Elle **ne vérifie pas** : que la VM démarre, que le système de fichiers de l'invité est cohérent, que l'application est cohérente, ni qu'on a sauvegardé les bonnes données. « Ignorer les vérifiés » évite de relire chaque semaine ce qui est déjà contrôlé ; « revérifier après N jours » relit périodiquement les anciens instantanés pour détecter la dégradation silencieuse du support (*bit rot*). Ensemble, ils étalent la charge de lecture.

**6. Réponse b.** La clé reste sur le client (ici `pve01`) ; PBS ne reçoit que des *chunks* chiffrés et ne peut pas les lire. Incrémental et déduplication fonctionnent entre sauvegardes faites avec la même clé. a) Faux : c'est tout l'intérêt, un PBS compromis ne livre rien de lisible. c) Faux : sans la clé (ou une copie papier, ou la clé maître RSA prévue pour la récupération), les données sont perdues. d) Faux (M00-E36).

**7.** 3-2-1 : trois copies des données, sur deux supports différents, dont une hors site. 3-2-1-1-0 ajoute une copie hors ligne ou immuable, et zéro erreur constatée à la vérification et aux tests de restauration. Notre dispositif : deux copies (la production sur `pve01`, la sauvegarde sur `pbs01`) ; deux équipements différents mais le même type de support (disques en ligne) ; un site « distant » qui est en réalité dans la même maison (même alimentation, même risque d'incendie ou de cambriolage) ; aucune copie hors ligne ni immuable ; vérification planifiée et tests de restauration (E23, E37) : bien. Manquent : une troisième copie réellement hors site (synchronisation vers un autre PBS, datastore amovible emporté ailleurs, ou stockage objet), une copie hors ligne, et une protection contre un administrateur ou un attaquant qui aurait la main sur PBS lui-même.

**8.** Incident à 18:00, dernière sauvegarde à 02:30 (état du disque au début de la sauvegarde de cette VM) : environ 15 h 30 de modifications perdues. Au pire (incident juste avant 02:30), 24 h : le **RPO** du dispositif est de 24 h. RTO de transfert pour 200 Go : à 60 Mo/s (exemple de mesure), 200 × 1 024 / 60 ≈ 3 400 s, soit environ 57 min (la restauration écrit tout le disque ; les zones vides vont plus vite). Le RTO réel ajoute : détection de l'incident, diagnostic, décision de restaurer (et choix du point de restauration), mobilisation des personnes et des accès, préparation (espace, réseau), démarrage, contrôles applicatifs, reconnexion des clients, communication. En pratique, plusieurs heures, d'où l'intérêt de runbooks testés (E25) et de mesures réelles (E37).

**9.** *Crash-consistent* : l'image est celle d'une machine dont on aurait coupé le courant ; le système de fichiers rejoue son journal, une base de données sérieuse rejoue son journal de transactions (WAL), mais une application qui garde un état en mémoire ou écrit plusieurs fichiers liés peut se retrouver incohérente. Cohérence **applicative** : l'application a été prévenue, a vidé ses tampons et s'est mise dans un état propre avant la capture. Le *fs-freeze* via l'agent QEMU appelle le gel des systèmes de fichiers de l'invité : les pages sales sont écrites sur disque et les nouvelles écritures bloquées le temps que la sauvegarde démarre, puis tout est dégelé. Il garantit des systèmes de fichiers propres, pas des transactions applicatives terminées : PostgreSQL s'en remet par son WAL, d'autres moteurs ou applications non. On complète par des scripts de gel (`fsfreeze-hook` de l'agent, qui peut faire faire un point de contrôle à la base) ou par des sauvegardes applicatives (`pg_dump`, pgBackRest, module 27).

**10. Réponse b.** `vzdump` tente de joindre l'agent ; sans réponse, il journalise un avertissement (agent configuré mais injoignable, gel ignoré) et continue : la sauvegarde est cohérente « après plantage » seulement (libellé exact à vérifier dans le journal de la tâche). a) Faux : ce n'est pas bloquant. c) Faux : le mode ne change jamais tout seul. d) Faux : Proxmox n'installe rien dans l'invité. À retenir : `agent: 1` sans agent installé fait perdre la cohérence des systèmes de fichiers **en silence**, d'où l'agent dans le template (E11).

**11.** Un snapshot n'est pas une sauvegarde : il vit sur le **même stockage** que la VM (une panne du disque ou du pool fin emporte les deux) ; sur le **même hyperviseur et le même site** (incendie, vol) ; dans le **même domaine d'administration** (un `qm destroy`, une erreur ou un attaquant suppriment VM et snapshots ensemble) ; il **dépend** des données de la VM (copie sur écriture, rien n'est dupliqué) ; il n'est ni vérifié ni soumis à une rétention ; et le garder longtemps dégrade les performances et remplit le pool fin.

**12.** Le mode `stop` éteint proprement la VM, lance la sauvegarde, puis la redémarre aussitôt (avec QEMU, la VM repart pendant que la sauvegarde continue en arrière-plan). Il donne la cohérence la plus forte (aucune application en cours) : utile pour une appliance sans agent ni moyen de gel, une application qui ne supporte pas une reprise après plantage, ou un conteneur sur un stockage sans snapshots. Coût : une interruption de service à chaque sauvegarde (arrêt + démarrage), et la perte du *dirty bitmap* à chaque fois (nouveau processus QEMU), donc une relecture complète du disque.

**13.** En *copy-before-write*, quand l'invité écrit sur un bloc pas encore sauvegardé, QEMU doit d'abord envoyer l'ancien contenu de ce bloc à la cible. Si la cible est lente (PBS sur disque mécanique, à travers un tunnel, occupé par une autre VM), **l'écriture de l'invité attend** : sa latence disque explose pendant toute la sauvegarde, et une base de données ou une application sensible le ressent. Le *fleecing* (Proxmox VE 8.2 et suivants) copie ces anciens blocs dans une image temporaire sur un stockage **local et rapide** ; la sauvegarde les relit ensuite depuis cette image, et l'invité n'attend plus PBS. Coût : de l'espace local temporaire. Ici, c'est pertinent (PBS distant et lent).

**14.** Avec `root` sur `pve01`, l'attaquant lit le secret du jeton (`/etc/pve/priv/storage/pbs-par2.pw`). Il **peut** : lire et restaurer toutes les sauvegardes du namespace appartenant au jeton (exfiltration des données de santé), créer de nouvelles sauvegardes (remplir le datastore, ou pousser hors de la rétention quotidienne les bons instantanés en sauvegardant des VMs déjà chiffrées par un rançongiciel pendant 7 jours). Il **ne peut pas** : supprimer ou purger des instantanés, modifier ceux qui existent (un instantané écrit est figé, ses *chunks* sont adressés par leur contenu), changer la rétention, toucher aux autres namespaces ni à la configuration de PBS. Mesures supplémentaires : instantanés protégés pour les points de référence ; synchronisation **tirée** par un second PBS que `pve01` ne peut pas joindre ; copie hors ligne (datastore amovible) ; alertes sur le volume et le nombre de sauvegardes anormaux ; administration de PBS avec des identifiants distincts et un second facteur ; filtrage réseau de `pve01` vers PBS limité au port 8007. Le chiffrement côté client protège contre un PBS compromis, pas contre un `pve01` compromis (la clé est sur `pve01`).

**15. Réponse c (fausse).** Les namespaces d'un datastore partagent le **même** magasin de *chunks* : la déduplication joue entre eux, et le *garbage collection* est global au datastore. a) vrai : ACL par chemin `/datastore/<store>/<ns>`. b) vrai : purge, vérification et synchronisation se règlent par namespace. d) vrai : c'est même leur raison d'être (plusieurs clusters dont les VMID se recouvrent).

**16.** Plan de test de restauration du socle (exemple) :
- **Mensuel** : restauration complète d'une VM du socle, à tour de rôle, en VMID 5090-5099, réseau isolé ; contrôle automatisé (démarrage, service principal opérationnel, données de la veille présentes) ; mesure du temps.
- **Hebdomadaire** : restauration d'un fichier témoin (dont le contenu change chaque jour) et comparaison.
- **Semestriel** : exercice de reprise complet du socle (perte simulée de `pve01`), chronométré (F5).
- **Critères** : VM démarrée, contrôles applicatifs au vert, fraîcheur des données conforme au RPO, durée conforme au RTO.
- **Traçabilité** : ticket par test (sauvegarde utilisée, durées, écarts, actions), revue trimestrielle des résultats ; un test en échec est un incident.

**17.** Ordre de grandeur (le raisonnement compte plus que le chiffre) :
- Initial : 6 × 12 Go = 72 Go ; les parties système communes (environ 2 à 3 Go par VM) ne sont stockées qu'une fois → environ 60 Go uniques ; compression zstd (facteur 0,5 à 0,7) → 30 à 40 Go.
- Quotidien : 2 % de 72 Go ≈ 1,4 Go modifiés, mais à la granularité de 4 Mio, de petites écritures dispersées « salissent » des *chunks* entiers : facteur 2 à 4, soit 3 à 5 Go de *chunks* nouveaux par jour avant compression, 2 à 3,5 Go après.
- Rétention : les 7 quotidiennes retiennent environ une semaine de *chunks* nouveaux (15 à 25 Go) ; les 4 hebdomadaires et 6 mensuelles retiennent chacune leurs différences propres, plus petites que la somme des journées (les mêmes blocs sont réécrits) : quelques dizaines de Go de plus.
- Total à un an : environ **100 à 250 Go**. Largement dans les capacités de `ds-lab`.
Facteurs d'imprécision : compressibilité réelle ; localité des écritures (amplification) ; réécriture des mêmes blocs (journaux tournants) ; TRIM dans les invités (blocs libérés remis à zéro, donc dédupliqués) ; croissance des données ; VMs de sandbox sauvegardées par hasard ; délai du GC ; surcoût du système de fichiers.

**18. Réponse a.** b) Faux : c'est précisément une fonction de restauration **depuis PBS**. c) Faux : si la restauration échoue en cours de route, la VM tourne sur un disque incomplet ; il faut l'arrêter et recommencer, et ce qui a été écrit entre-temps est perdu. d) Faux : le débit total est en général moindre (lectures à la demande et copie de fond concurrentes) ; on gagne en **délai de remise en service**, pas en durée.

---

### M00-E25 — Runbooks « créer une VM » et « restaurer une VM »

Création du dépôt de documentation (une seule fois, sur `adm01` ; c'est lui que E33, E37, le palier 4 et E50 réutilisent) :
```
admin@adm01:~$ mkdir -p ~/medisphere/docs/socle/{runbooks,adr}
admin@adm01:~$ cd ~/medisphere && git init -b main
admin@adm01:~/medisphere$ printf '# Documentation MédiSphère\n\nSocle : docs/socle/\n' > README.md
admin@adm01:~/medisphere$ touch docs/socle/runbooks/.gitkeep docs/socle/adr/.gitkeep
admin@adm01:~/medisphere$ git add . && git commit -m "docs: dépôt de documentation du socle"
```
Le chemin est celui de `WB_DEPOT` (défaut `$HOME/medisphere`) : les vérifications du palier 4 et de E50 y cherchent leurs fichiers. Ajoute dès maintenant le `.gitignore` de [`fichiers/M00-E50/gitignore-exemple`](fichiers/M00-E50/gitignore-exemple) : aucun secret ne doit jamais y entrer.

Les deux runbooks ci-dessous sont des exemples de référence, à enregistrer dans `docs/socle/runbooks/RB-001-creer-une-vm.md` et `docs/socle/runbooks/RB-002-restaurer-une-vm.md`. Les valeurs entre chevrons sont à remplacer à l'exécution ; les durées viennent de tes mesures (E18, E23).

#### RB-001 — Créer une VM dans le lab

| Version | Auteur | Relu par | Date | Prochaine revue |
|---|---|---|---|---|
| 1.0 | Équipe Plateforme | Nadia Roussel | <AAAA-MM-JJ> | +6 mois, ou au passage au SDN (M00-E28) |

**Objet.** Créer une VM Debian 13 dans le lab à partir du template `tpl-debian13` (9000), accessible en SSH, sauvegardée, avec un nom DNS si son adresse est statique.

**Quand l'utiliser / quand ne pas l'utiliser.** Demande de VM ponctuelle (ticket `PLAT-` ou `DEV-`). Pas pour : une VM gérée par l'IaC d'un module (utiliser Terraform, module 05) ; une restauration (RB-002) ; une VM hors pool `lab`.

**Prérequis**
- [ ] Session sur `adm01`, agent SSH chargé (`ssh-add -l` liste une clé).
- [ ] `ssh pve01 true` répond sans question.
- [ ] Informations réunies : nom (`<rôle><nn>`), rôle, VLAN, adresse (statique, ou DHCP en VLAN 99), vCPU, RAM, taille de disque, durée de vie (éphémère ou durable), demandeur.
- [ ] VMID choisi dans la bonne plage (`PLAN.md` §4.6) : 1000-1099 socle, `2000 + module×10 + n` pour un module, 5000-5999 sandbox (module 00 : 5001-5009 pour les VMs jetables ; 5044, 5048 et 5090-5099 sont réservés à des exercices).

**Durée et impact.** 5 à 10 minutes. Aucun impact sur l'existant si les vérifications d'unicité sont faites.

**Étapes**
1. Vérifier que le VMID est libre.
   `admin@adm01:~$ ssh pve01 pvesh get /cluster/nextid --vmid <VMID>`
   Attendu : `<VMID>`. Si « VM <VMID> already exists » : choisir un autre VMID.
2. Vérifier que l'adresse est libre (adresse statique seulement).
   `admin@adm01:~$ dig +short -x <IP>; ping -c2 -W1 <IP>`
   Attendu : aucune réponse aux deux. Sinon : STOP, l'adresse est prise ; corriger la demande.
3. Cloner le template.
   - Durable : `admin@adm01:~$ ssh pve01 qm clone 9000 <VMID> --name <NOM> --pool lab --full 1 --storage <STOCKAGE-VMS>`
   - Éphémère : `admin@adm01:~$ ssh pve01 qm clone 9000 <VMID> --name <NOM> --pool lab`
   Attendu : la commande rend la main sans erreur (`qm config <VMID>` montre le nom). Si « storage … not enough space » : escalader (capacité).
4. Configurer.
   `admin@adm01:~$ ssh pve01 qm set <VMID> --cores <N> --memory <Mo> --net0 virtio,bridge=vmbr1,tag=<VLAN> --ipconfig0 ip=<IP>/24,gw=10.10.<VLAN>.1 --nameserver 10.10.20.10 --searchdomain par1.medisphere.internal`
   (DHCP en VLAN 99 : `--ipconfig0 ip=dhcp`. Après M00-E28 : `--net0 virtio,bridge=<VNET>` sans `tag`.)
   Attendu : `update VM <VMID>: …`.
5. Agrandir le disque si besoin.
   `admin@adm01:~$ ssh pve01 qm disk resize <VMID> scsi0 <TAILLE>G`
   Attendu : pas d'erreur. (Le système de fichiers de l'invité s'agrandit au premier démarrage grâce à cloud-init.)
6. Démarrer et attendre l'agent.
   `admin@adm01:~$ ssh pve01 "qm start <VMID> && for i in \$(seq 30); do qm guest cmd <VMID> ping 2>/dev/null && break; sleep 5; done; qm guest cmd <VMID> ping && echo agent-ok"`
   Attendu : `agent-ok` en moins de 2 minutes. Sinon : aller à « En cas d'échec ».
7. Vérifier l'adresse.
   `admin@adm01:~$ ssh pve01 qm guest cmd <VMID> network-get-interfaces | grep '"ip-address"'`
   Attendu : `<IP>` (ou une adresse 10.10.99.100-199 en DHCP).
8. Vérifier l'accès et la fin de cloud-init.
   `admin@adm01:~$ ssh -o StrictHostKeyChecking=accept-new admin@<IP> 'cloud-init status --wait; hostname -f'`
   Attendu : `status: done` puis `<NOM>.par1.medisphere.internal`.
9. Enregistrer le nom DNS (adresse statique, en attendant PowerDNS au module 06).
   `admin@dns01:~$ echo 'host-record=<NOM>.par1.medisphere.internal,<IP>' | sudo tee -a /etc/dnsmasq.d/medisphere.conf && sudo systemctl restart dnsmasq`
   Attendu : `dig +short <NOM>.par1.medisphere.internal` renvoie `<IP>`, `dig +short -x <IP>` renvoie le nom.
10. Vérifier la couverture de sauvegarde.
    `admin@adm01:~$ ssh pve01 pvesh get /cluster/backup-info/not-backed-up --output-format json | grep -c '"vmid":<VMID>'`
    Attendu : `0` (la VM, membre du pool `lab`, est couverte par la tâche `lab-nuit`).
11. Documenter : ticket (VMID, nom, adresse, durée de vie) ; pour un hôte permanent, mise à jour de `PLAN.md` §4.5.

**Vérifications.** `qm status <VMID>` → `running` ; SSH par le nom (`ssh admin@<NOM>`) ; `dig` A et PTR cohérents ; VM visible dans le pool `lab`.

**Retour arrière.** Possible à tout moment tant que personne n'a mis de données dans la VM : `ssh pve01 "qm stop <VMID>; qm destroy <VMID> --purge"`, retrait de la ligne `host-record` et redémarrage de dnsmasq. Une fois la VM utilisée : sauvegarde manuelle avant destruction, accord du demandeur.

**En cas d'échec / escalade**

| Symptôme | Cause probable | Action |
|---|---|---|
| `VM is locked (clone)` | Clone encore en cours | Attendre la fin de la tâche (`ssh pve01 qm status <VMID> --verbose`) |
| Agent muet après 2 min | VM bloquée au démarrage, ou agent absent | `ssh pve01 qm terminal <VMID>` (console série), lire les messages |
| Pas d'adresse en DHCP | `tag=99` manquant, relais DHCP en panne | Vérifier `net0`, puis `journalctl -u dnsmasq` sur `dns01` et `gw01` |
| SSH refusé (publickey) | cloud-init pas fini, clé absente du template | Attendre `cloud-init status --wait` ; sinon escalader |
| Espace insuffisant | Stockage plein | Escalader : ne pas supprimer de VM d'autrui |

Escalade : équipe Plateforme, avec le VMID, la commande lancée, la sortie complète et l'heure.

**Contacts.** Équipe Plateforme (canal `#plateforme`) ; astreinte : voir le planning de Nadia Roussel. Pas de numéro personnel dans ce document.

**Historique.** <AAAA-MM-JJ> — création (PLAT-125). <AAAA-MM-JJ> — exécution à froid sur 5005 par <RELECTEUR> : étape 6 réécrite (boucle d'attente).

#### RB-002 — Restaurer une VM depuis PAR2

| Version | Auteur | Relu par | Date | Prochaine revue |
|---|---|---|---|---|
| 1.0 | Équipe Plateforme | Nadia Roussel | <AAAA-MM-JJ> | +6 mois, ou après chaque test de restauration |

**Objet.** Restaurer une VM du lab depuis le serveur de sauvegarde `pbs01` (stockage `pbs-par2`), soit **à côté** de l'original (test, récupération de fichiers), soit **en remplacement** de l'original (sinistre).

**Quand l'utiliser / quand ne pas l'utiliser.** Cas A : test planifié, récupération de données, analyse. Cas B : VM détruite, disque corrompu, compromission avérée, sur incident `INC-` validé. Pas pour : revenir sur une mise à jour de l'heure passée si un snapshot existe (`qm rollback`, plus rapide) ; récupérer un seul fichier (cas A, étape A5 seulement).

**Prérequis**
- [ ] Accès `root` à `pve01` depuis `adm01` (`ssh pve01 true`).
- [ ] Tunnel PAR2 actif : `ssh gw01 sudo -n wg show wg0 latest-handshakes` (moins de 3 min) et `ping -c2 10.20.10.10`.
- [ ] `ssh pve01 pvesm status --storage pbs-par2` → `active`.
- [ ] Espace suffisant sur le stockage cible (`pvesm status`) : au moins la taille des disques de la VM.
- [ ] Cas B : ticket d'incident, accord du responsable (Claire Morel ou l'astreinte), demandeur informé de la perte de données depuis la sauvegarde choisie.

**Durée et impact.** Mesures du lab (E23) : `<TEMPS-RESTAURATION>` pour `dns01` (disque de 8 Go) à `<DEBIT>` Mo/s, soit environ `<MINUTES-PAR-10-GO>` min par tranche de 10 Go. Cas A : aucun impact. Cas B : la VM est indisponible pendant toute la restauration, et les données postérieures à la sauvegarde choisie sont perdues.

**Étapes communes**
1. Lister les sauvegardes de la VM.
   `admin@adm01:~$ ssh pve01 pvesm list pbs-par2 --vmid <VMID>`
   Attendu : des lignes `pbs-par2:backup/vm/<VMID>/<HORODATAGE-UTC>`. Rien : STOP, escalader (pas de sauvegarde).
2. **Décision : quelle sauvegarde ?** Par défaut, la plus récente **antérieure** à l'incident et vérifiée (interface PBS : *Verify State* = ok). En cas de compromission ou de corruption logique, remonter avant le début supposé de l'incident, en accord avec le demandeur. Noter la sauvegarde retenue dans le ticket.

**Cas A — restauration à côté**

A1. Choisir un VMID libre dans 5090-5099 : `ssh pve01 pvesh get /cluster/nextid --vmid 5090`.
A2. Restaurer sans démarrer :
    `admin@adm01:~$ ssh pve01 qmrestore pbs-par2:backup/vm/<VMID>/<HORODATAGE> <VMID-TEST> --storage <STOCKAGE-VMS> --pool lab --unique 1`
    Attendu : `restore image complete`, fin sans erreur.
A3. Isoler **avant** tout démarrage :
    `admin@adm01:~$ ssh pve01 qm config <VMID-TEST> | grep -E '^net'`
    `admin@adm01:~$ ssh pve01 qm set <VMID-TEST> --name rst-<NOM> --net0 virtio=<MAC-AFFICHEE>,bridge=vmbr1,tag=<VLAN>,link_down=1`
    Attendu : `link_down=1` sur **toutes** les cartes (`qm config`).
A4. Démarrer et contrôler par l'agent : `ssh pve01 "qm start <VMID-TEST>; sleep 60; qm guest exec <VMID-TEST> -- systemctl --failed"`.
A5. Récupérer des fichiers si besoin (sans démarrer la VM, directement depuis la sauvegarde) : interface *pbs-par2 → Backups → File Restore*, ou `proxmox-file-restore` avec `PBS_REPOSITORY='wb-backup@pbs!pve01@10.20.10.10:ds-lab'`, `PBS_PASSWORD_FILE=/etc/pve/priv/storage/pbs-par2.pw`, `PBS_FINGERPRINT`, `--ns par1` (voir le corrigé de E23).
A6. Détruire la copie après usage : `ssh pve01 "qm stop <VMID-TEST>; qm destroy <VMID-TEST> --purge"`.

**Cas B — restauration en remplacement**

> ⚠️ **Attention** : l'étape B4 écrase les disques de la VM d'origine. C'est le point de non-retour.

B1. Conserver l'état actuel si la VM existe encore (analyse, retour arrière) :
    `admin@adm01:~$ ssh pve01 vzdump <VMID> --storage pbs-par2 --mode stop --notes-template 'avant-restauration <INC-NNN>'`
    Si la VM est trop abîmée pour être sauvegardée : le noter dans le ticket et continuer avec l'accord du responsable.
B2. Prévenir les utilisateurs du service (canal d'incident) : indisponibilité, perte de données jusqu'à `<HORODATAGE>`.
B3. Arrêter l'original : `ssh pve01 qm stop <VMID>`.
B4. Restaurer **sur le même VMID**, sans `--unique` (mêmes MAC, même nom, même configuration cloud-init : l'invité se reconnaît et ne se reconfigure pas) :
    `admin@adm01:~$ ssh pve01 qmrestore pbs-par2:backup/vm/<VMID>/<HORODATAGE> <VMID> --force 1 --storage <STOCKAGE-VMS>`
    Attendu : `restore image complete`. Option si le délai prime et que le tunnel est sain : `--live-restore 1` (la VM démarre pendant la restauration ; en cas de coupure, tout recommencer).
B5. Démarrer : `ssh pve01 qm start <VMID>`, attendre l'agent (RB-001, étape 6).
B6. Contrôles applicatifs selon la VM (pour `dns01` : `dig @10.10.20.10 adm01.par1.medisphere.internal` ; pour `gw01` : sortie Internet d'une VM, VPN, tunnel), journal du démarrage (`journalctl -b -p err`).
B7. Lancer une sauvegarde de la VM restaurée dès qu'elle est validée (la chaîne incrémentale repart de zéro).
B8. Clore : ticket complété (sauvegarde utilisée, durées, données perdues, causes), information des utilisateurs.

**Vérifications.** Cas A : copie démarrée, données attendues présentes, original intact (`qm status <VMID>` inchangé). Cas B : service rendu, contrôles applicatifs au vert, sauvegarde suivante réussie.

**Retour arrière.** Cas A : détruire la copie, à tout moment. Cas B : jusqu'à B3, il suffit de redémarrer l'original. Après B4, seul le retour à la sauvegarde faite en B1 est possible (même procédure, avec cette sauvegarde-là).

**En cas d'échec / escalade**

| Symptôme | Cause probable | Action |
|---|---|---|
| `pbs-par2` inactif | Tunnel `wg0` tombé, PBS arrêté, empreinte changée | Vérifier `wg show` sur `gw01` et `pbs01`, `pvesm status` ; voir M00-E43 |
| `permission check failed` | Mauvais compte (ce n'est pas le jeton du stockage qui restaure en tant que root) | Lancer `qmrestore` en root sur `pve01` |
| Transfert qui se fige | Problème de MTU dans le tunnel | Voir M00-E41 ; escalader |
| `no space left` | Stockage cible plein | Choisir un autre `--storage` ; ne rien supprimer sans accord |
| VM restaurée sans réseau | `link_down=1` resté, mauvais VLAN, MAC changée | `qm config`, comparer avec la sauvegarde de configuration |
| Erreurs de vérification sur la sauvegarde | Corruption côté PBS | Choisir une sauvegarde antérieure vérifiée, escalader |

Escalade : astreinte Plateforme, avec la VM, la sauvegarde choisie, les commandes lancées et leurs sorties complètes.

**Contacts.** Équipe Plateforme (`#plateforme`), astreinte (planning de Nadia Roussel), responsable infrastructure (Claire Morel) pour toute décision du cas B.

**Historique.** <AAAA-MM-JJ> — création (PLAT-125). <AAAA-MM-JJ> — exécution à froid du cas A sur `sbx02` par <RELECTEUR> : ajout du contrôle `link_down` sur toutes les cartes.

**Ce qui fait la qualité de ces runbooks** : une seule action par étape avec la commande exacte et l'hôte ; un résultat attendu copié d'une vraie exécution ; les points de décision explicites (« quelle sauvegarde ? ») ; l'avertissement placé **avant** l'étape irréversible ; un retour arrière qui dit jusqu'où il est possible ; des symptômes reliés à leurs causes probables et aux exercices qui les traitent ; aucune donnée secrète ni personnelle. Pièges fréquents des premières versions : « restaurer la VM » en une seule étape, pas de critère pour choisir la sauvegarde, aucun mot sur le doublon d'adresse, des durées inventées au lieu d'être mesurées.

---

### M00-E26 — Revue de la configuration nftables d'un stagiaire

**Lecture des paquets demandés**

| Paquet | Ce qui arrive avec la proposition |
|---|---|
| SYN vers 22 de `gw01` depuis le LAN maison | Accepté (ligne 10, aucune restriction d'interface ni de source) |
| Le même en IPv6 | Accepté : la table `ip` ne voit pas IPv6, et rien d'autre ne filtre |
| Ping de 10.10.70.20 (DMZ) vers `adm01` | Jeté par la ligne 23… comme **tout** ICMP traversant ; mais un SSH de la DMZ vers `adm01` passe (ligne 26) |
| Réponse DNS tronquée, nouvel essai en TCP | Le client du VLAN 40 passe quand même (ligne 26, inter-VLAN total) ; depuis PAR2 (ligne 30) ou une fois l'inter-VLAN fermé, le TCP 53 est refusé |
| ICMP « fragmentation needed » de `gw01` vers `pve01` | Émis par `gw01` (chaîne `output`), il passe ; mais celui qu'un routeur en aval renverrait **à travers** `gw01` vers une VM est jeté (ligne 23). Et sans masquage vers `wg0`, les réponses de `pbs01` à `pve01` ne repassent même pas par `gw01` |
| `adm01` vers `deb.debian.org` | Transféré (ligne 27), mais **pas masqué** (ligne 48 ne concerne que `ens19*`) : la box reçoit une source 10.10.10.10 et ne sait pas y répondre (sauf route ajoutée sur la box) |
| Réponse de `dns01` au relais DHCP | Acceptée… uniquement grâce à `policy accept` : elle ne correspond à aucune règle |
| `systemctl reload nftables` | Sans `flush ruleset`, chaque rechargement **ajoute** une copie des règles aux tables existantes |

**Revue**

| N° | Ligne(s) | Défaut | Catégorie | Gravité | Impact concret | Correction |
|---|---|---|---|---|---|---|
| 1 | 7 | `policy accept` en entrée, sans rejet final | Sécurité | **Critique** | Tout service de `gw01` (relais DHCP, chrony, un futur service de test, SSH) est joignable depuis le WAN et tous les VLANs ; les règles d'entrée ne servent à rien | `policy drop`, et des règles d'autorisation explicites par interface et source |
| 2 | 48 | NAT sur la mauvaise interface (`oifname "ens19*"`) | Fonctionnement | **Critique** | Le lab n'a plus d'accès Internet (sources privées non traduites vers `ens18`) ; à l'inverse, tout le trafic inter-VLAN est masqué derrière l'adresse `.1` de la passerelle : journaux inutilisables, règles par source sur les hôtes inopérantes. Le masquage vers `wg0` manque (retour asymétrique et en clair de `pbs01` vers `pve01`) | `oifname "ens18" ip saddr 10.10.0.0/16 masquerade` et `oifname "wg0" ip saddr <LAN-MAISON> masquerade` |
| 3 | 5 | Table `ip` au lieu de `inet` | Sécurité | **Élevée** | IPv6 n'est pas filtré du tout : si la box distribue de l'IPv6 sur le WAN, SSH et tous les services de `gw01` y sont exposés | `table inet filter`, et règles ICMPv6 nécessaires (NDP) |
| 4 | 10 (et 11) | SSH ouvert sur toutes les interfaces, toutes sources | Sécurité | **Élevée** | N'importe quel appareil du LAN maison (objets connectés, invités), la DMZ et la sandbox peuvent tenter SSH sur le routeur | SSH depuis `ens19.10`, `wg1` et `<LAN-MAISON>` sur `ens18` uniquement |
| 5 | 26 (et 27) | Transfert inter-VLAN total | Sécurité | **Élevée** | La DMZ (exposée) et la sandbox (exercices de panne) atteignent MGMT, INFRA, le stockage : la segmentation en VLANs n'a plus d'intérêt | Flux explicites : MGMT vers tout ; DNS vers `dns01` ; le reste au cas par cas |
| 6 | 23 (et 13) | ICMP jeté en tête de chaîne `forward` (et ping de `gw01` refusé) | Fonctionnement | **Élevée** | Les ICMP d'erreur liés à des flux légitimes (« fragmentation needed », « time exceeded ») sont jetés **avant** la règle `related` : découverte de MTU cassée à travers `wg0` (MTU 1420), traceroute muet, diagnostic impossible | Supprimer ces règles ; `ct state related` laisse passer les erreurs liées ; autoriser `echo-request` depuis les réseaux d'administration |
| 7 | 16-17 | `log` placé avant la règle `established`, et cette règle en fin de chaîne | Fonctionnement | Moyenne | Chaque paquet de chaque session établie traverse toute la chaîne (coût CPU) et est **journalisé** : des milliers de lignes par minute pour une simple session SSH | `ct state established,related accept` en tête de chaîne ; journalisation juste avant le rejet final |
| 8 | 16, 37 | Journalisation sans limite de débit | Sécurité / disponibilité | Moyenne | Un simple balayage de ports depuis le LAN remplit le journal et le disque, et masque les événements utiles (déni de service par les journaux) | `limit rate 10/minute burst 20 packets log prefix "…"` |
| 9 | 7, 21 | Pas de `ct state invalid drop` | Sécurité | Moyenne | Des paquets hors état (sondes, paquets forgés, restes de sessions) atteignent les règles d'autorisation et peuvent passer | `ct state invalid drop` en tête de `input` et `forward` |
| 10 | 1-5 | Pas de `flush ruleset` | Fonctionnement | Moyenne | Chaque `nft -f` ou `systemctl reload nftables` ajoute une copie des règles : doublons, puis comportement incompréhensible quand on modifie une règle (l'ancienne copie est toujours là) | `flush ruleset` en tête de fichier |
| 11 | 29-30 | DNS autorisé en UDP seulement | Fonctionnement | Moyenne | Les réponses tronquées (grosses réponses, DNSSEC) ne peuvent pas être redemandées en TCP : échecs de résolution intermittents | `meta l4proto { tcp, udp } th dport 53` |
| 12 | partout | Aucune variable, aucun commentaire, règles redondantes ou masquées | Maintenabilité | Faible | `192.168.1.20` : qui est-ce ? Ligne 11 masquée par la 10 ; ligne 29 redondante avec la 26, ligne 34 avec la 27 (et la 27 recouvre en partie la 26) ; nommer et commenter est indispensable pour relire, auditer et modifier sans erreur | `define` pour interfaces et adresses, `comment` sur chaque règle, suppression des doublons |

Remarques mineures, non comptées : ports WireGuard ouverts à toutes les sources (WireGuard ne répond qu'aux pairs authentifiés ; restreindre reste préférable) ; motif `ens19*` qui inclurait demain des sous-interfaces non routées ; aucune règle pour les renouvellements DHCP en unicast, ni pour l'accès du VPN à `pve01` ; règle NTP (ligne 14) qui anticipe M00-E31 : tant que `gw01` ne sert pas l'heure, on n'ouvre pas de port « pour plus tard » (elle oublie d'ailleurs PAR2) ; priorités numériques (`0`, `100`) plutôt que nommées (`filter`, `srcnat`).

**Ordre de traitement** : d'abord ce qui expose (1, 3, 4, 5), puis ce qui casse le service (2, 6, 11, 10), puis le bruit et l'hygiène (7, 8, 9, 12). En pratique, on corrige tout dans la même demande de fusion, mais si l'on devait livrer en deux temps, la première livraison contiendrait 1 à 6.

**Version corrigée** : [`fichiers/M00-E26/nftables.conf`](fichiers/M00-E26/nftables.conf), qui est aussi la configuration de référence de `gw01` à la fin de ce palier. Validation hors de `gw01` :
```
admin@adm01:~$ sudo unshare --net nft -c -f nftables.conf && echo syntaxe-ok
admin@adm01:~$ sudo unshare --net sh -c 'nft -f nftables.conf && nft -f nftables.conf && nft list ruleset | grep -c "policy drop"'
2
```
(Le double chargement prouve l'effet de `flush ruleset` : toujours deux chaînes en `policy drop`, pas quatre.)

**Conseils à Lucas sur sa méthode de test**
- « Tout passe » est le symptôme d'un pare-feu trop ouvert, pas la preuve qu'il est bon : teste aussi ce qui **doit être refusé** (un SSH depuis la DMZ, un ping IPv6), et vérifie les compteurs.
- Teste dans un environnement qui ressemble à la production : plusieurs VLANs, un vrai WAN, IPv6 activé, le tunnel, de gros transferts (MTU).
- Recharge deux fois de suite, relis `nft list ruleset` après chargement, et écris les tests une fois pour toutes (M29).

**Explications**

Les défauts les plus graves ne se voient pas en testant « ce qui doit marcher » : une politique `accept`, une table `ip` sans IPv6, un inter-VLAN ouvert font **réussir** les tests. Il faut lire le jeu de règles en suivant des paquets précis, y compris ceux qui doivent être refusés, et en pensant aux cas hors régime établi (rechargement, ICMP d'erreur, IPv6, inondation).

**Alternatives**

- Structurer avec des chaînes par zone (`jump from_dmz`, `jump from_mgmt`) et des *verdict maps* (`iifname vmap { "ens19.10" : jump from_mgmt, … }`) : plus lisible quand les VLANs se multiplient.
- Ensembles nommés (`set admin_nets { type ipv4_addr; flags interval; elements = { … } }`) modifiables sans recharger tout le fichier.
- Générer la configuration depuis un modèle (Ansible + Jinja2, module 04) à partir de la matrice des flux.

**Pièges classiques**

- Tester uniquement les flux attendus.
- Placer une règle de rejet ou de journalisation générique avant les règles d'état.
- Oublier IPv6 parce que « le lab est en IPv4 ».
- Confondre `iif` (index d'interface, l'interface doit exister au chargement) et `iifname` (nom, motif accepté, interface créée plus tard comme `wg0`).

**En production chez MédiSphère**

- Toute modification du pare-feu passe par une demande de fusion, une revue par un pair, un test automatisé (chargement dans un espace de noms, invariants) et un déploiement par l'outillage, avec retour arrière automatique.
- La matrice des flux est un document de référence, revu avec la sécurité (Sophie Laurent) ; le pare-feu en est la traduction, pas l'inverse.
- Journaux de rejet centralisés et limités, alertes sur les rejets inhabituels.
