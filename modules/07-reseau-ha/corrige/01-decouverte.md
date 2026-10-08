# Module 07 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`ansible/` pour `plateforme/ansible`, `infra/` pour `plateforme/infra`, `medisphere/` pour `plateforme/medisphere`, `adm01/` pour les fichiers personnels du bastion). Ne copie que ce que l'exercice ajoute ou modifie.

**Ce qui a été testé à la rédaction** (bac à sable Ubuntu 24.04, octobre 2026) :
- **FRR 10.7.1** (dépôt deb.frrouting.org) dans des espaces de noms reliés comme la fabric de la maquette (quatre routeurs, liens `/31`, mêmes noms d'interfaces) : configurations **produites par le modèle du rôle `frr`** à partir des `host_vars` de E06 et E07, validées par `vtysh --dryrun`, chargées par les démons ; OSPF (voisinages `Full`, ECMP par les deux spines avec `vfab7` à 30, interface `eth0` passive : « No Hellos (Passive interface) »), eBGP (`(Policy)` sans *route-map*, sessions authentifiées TCP-MD5, 3 préfixes reçus par leaf, deux chemins *multipath* installés en ECMP, absence de route d'un spine vers l'autre, `% Inbound soft reconfiguration not enabled` sans `soft-reconfiguration`), fuite de `192.0.2.0/24` bloquée, retrait de la politique de sortie → `(Policy)` et retrait de toutes les routes du leaf, changement de mot de passe → session réinitialisée aussitôt puis bloquée en `Connect` ; `frr-reload.py --test` (format « Lines To Delete / Lines To Add ») ; formats JSON de `show bgp ipv4 unicast summary json` utilisés par les vérifications ; valeur par défaut de `maximum-paths` (aucune ligne dans la configuration : le maximum compilé, 256 pour ces paquets) ;
- **keepalived 2.2.8** (le paquet de Debian 13 est en 2.3 ; syntaxe identique pour ce qui est utilisé) dans deux espaces de noms : VRRP v3 unicast, VRID 199, `track_script` sur `/sante`, bascule sur échec du contrôle puis retour (préemption), `keepalived -t` sur les configurations produites par le rôle (refus d'un VRID hors bornes, d'un mot-clé inconnu) ;
- `tofu validate` et `tofu fmt` de `envs/m07-maquette` (OpenTofu 1.13.1, `bpg/proxmox` 0.116, `e-breuninger/netbox` 5.8, `mmianl/powerdns` 2.5) ; évaluation des `locals` (adresses fixes, étiquettes, cartes) ;
- `ansible-lint` profil `production` (ansible-core 2.21, ansible-lint 26.9) sur les cinq rôles, les playbooks et les scénarios Molecule ; scripts du rôle `bonding` et `ovs_labo` rendus puis passés à `shellcheck` ;
- tous les scripts (`outils/m07-vnets.sh`, checks) passent `shellcheck -x` et `bash -n` ; `check-E02.sh` exécuté contre le document d'exemple (vert) et contre des documents tronqués (rouge).

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- tout ce qui demande un vrai `pve01` : création et application des VNets, ACL `PVESDNUser`, `tofu apply` de la maquette, **nommage `eth0`, `eth1`… des cartes** (configuration réseau cloud-init de Proxmox), noms DNS dynamiques des VMs en DHCP ;
- le **bonding** et **Open vSwitch** : le noyau du bac à sable n'avait ni module `bonding` ni module `openvswitch`. Les commandes et sorties décrites suivent la documentation du noyau (`bonding.rst`) et d'Open vSwitch 3.5 ; le comportement exact du désaccord de mode (E04, étape 7) est à observer ;
- les scénarios Molecule `frr` et `keepalived` sur de vraies instances Proxmox, et l'effet du fichier `networkd.conf.d/50-frr.conf` (options documentées dans `networkd.conf(5)`, systemd 257 de Debian 13) ;
- la valeur `vrrp` de l'attribut `role` de `netbox_ip_address` (fournisseur NetBox 5.8 : rôles de NetBox `loopback`, `secondary`, `anycast`, `vip`, `vrrp`…) ;
- la référence du module `enregistrement-dns` (`?ref=v2.1.0`) : mets la dernière étiquette publiée en M06.

---

### M07-E01 — Test de positionnement : réseau de datacenter

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, relis les « Concepts clés » de l'introduction avant E04 ; les questions 11 à 14 sont reprises en E06, E07 et E14, les questions 15 à 17 en E08, E25 et E27, les questions 18 et 19 en E15 et E38.

**Couche 2**

**1. Inondation, filtrage, FDB.** Une destination inconnue est **inondée** sur tous les ports du même VLAN, sauf celui d'arrivée (*unknown unicast flooding*) ; le pont apprend au passage l'adresse **source** sur le port d'arrivée. Si la destination est connue sur le port même d'arrivée, la trame est **filtrée** (jetée) : les deux machines sont du même côté, inutile de la renvoyer. La table s'appelle FDB (*forwarding database*) ; une entrée dynamique vieillit au bout de 300 s sans trafic de cette source (`ageing_time` du pont Linux). Conséquence pratique (E02) : une VM silencieuse disparaît de la FDB et son prochain paquet entrant est d'abord inondé.

**2. Réponse B.** Une trame non étiquetée sur un *trunk* est rattachée au **VLAN natif** du port (PVID dans le vocabulaire Linux et 802.1Q). A est faux dans le cas général (c'est un réglage possible : un port sans PVID jette l'untagged, et c'est une bonne pratique sur les trunks d'infrastructure) ; C décrit une boucle, pas une règle ; D confond avec les trames de priorité 802.1p (VID 0), qui portent bien une étiquette.

**3. Boucle de couche 2.** Trois effets : (1) **tempête de diffusion** (chaque diffusion tourne indéfiniment et se multiplie à chaque pont), (2) **instabilité des tables FDB** (la même MAC source apparaît alternativement sur plusieurs ports), (3) **copies multiples** des trames unicast reçues par la destination. L'en-tête Ethernet n'a **aucun compteur de sauts** : rien n'arrête une trame en boucle, sauf la saturation. L'en-tête IP a le **TTL**, décrémenté à chaque routeur : un paquet en boucle meurt au bout de 64 sauts au plus. D'où STP (ou l'absence de boucle par construction) en couche 2, et la préférence des datacenters modernes pour le routage jusqu'au serveur.

**Agrégation de liens**

**4. Modes du bonding.** `active-backup` : un seul lien actif, les autres en secours ; aucune coopération du commutateur (il voit la MAC du bond migrer d'un port à l'autre) ; débit d'un lien, tolérance à la perte d'un lien ou d'un commutateur (si les liens vont vers deux commutateurs). `balance-xor` : tous les liens émettent, répartition par hachage ; le commutateur doit grouper les ports **statiquement** (port-channel sans négociation), sinon il voit la même MAC sur plusieurs ports ; débit agrégé pour plusieurs flux. `802.3ad` : comme `balance-xor`, mais l'agrégat est **négocié** par LACP avec le commutateur, qui doit le configurer aussi ; détecte les erreurs de câblage et les voisins qui ne participent plus. En production : `802.3ad` vers une paire de commutateurs MLAG, ou `active-backup` quand on ne maîtrise pas les commutateurs.

**5. Réponse B.** Le hachage place un flux (même 5-uplet en `layer3+4`) sur **un** lien, pour ne jamais réordonner ses paquets : une copie `scp` (une connexion TCP) plafonne à 10 Gbit/s. A et D confondent capacité agrégée et débit d'un flux ; C décrit le mode `balance-rr`, qui découpe par paquet et réordonne (TCP le supporte mal).

**6. Ce que LACP détecte.** `miimon` ne voit que la **porteuse** locale. LACP échange des LACPDU (toutes les secondes en `fast`, 30 s en `slow`) et retire un lien qui n'en reçoit plus (après trois intervalles), même si la porteuse est présente : lien unidirectionnel (une fibre coupée dans un sens), port d'en face non configuré ou dans un autre agrégat, câble branché sur le mauvais commutateur, processus LACP planté côté commutateur, convertisseur média qui garde la porteuse côté serveur alors que la fibre est coupée plus loin.

**Routage**

**7. Plus long préfixe.** 10.10.250.9 → **B** (le /24 est plus précis que le /16) ; 10.10.99.20 → **A** (seul le /16 le contient, en plus de la route par défaut) ; 10.30.10.10 → **C** (seule la route par défaut le contient). Règle : parmi les routes qui contiennent la destination, la plus longue (masque le plus grand) l'emporte, quelle que soit sa source ou son ordre dans la table.

**8. ECMP.** *Equal-Cost Multi-Path* : plusieurs prochains sauts installés pour un même préfixe, de coût égal. Le noyau choisit le prochain saut par un hachage du flux (adresses, et ports avec `fib_multipath_hash_policy=1`) : tous les paquets d'un flux suivent le même chemin. Par paquet, deux chemins de latences différentes **réordonnent** les segments : TCP prend les arrivées dans le désordre pour des pertes (ACK dupliqués), retransmet inutilement et réduit sa fenêtre : le débit s'effondre.

**9. Distance administrative.** Les deux routes ont le même préfixe : zebra départage par la **distance** de la source. eBGP vaut 20, OSPF 110 : la route eBGP est installée (le coût OSPF n'entre pas en jeu, il ne compare que des routes OSPF entre elles). Une route statique (distance 1) l'emporterait sur les deux. Piège classique : une route statique « de secours » oubliée court-circuite le routage dynamique ; pour un vrai secours, on lui donne une distance supérieure (`ip route … 250`, route *flottante*).

**10. `/31`.** Sur un lien point à point, il n'y a que deux extrémités : les adresses « réseau » et « diffusion » d'un `/30` ne servent à rien. La RFC 3021 autorise un `/31` dont les **deux** adresses sont utilisables. Gain : moitié moins d'adresses consommées par les liens (64 liens au lieu de 32 dans un `/24`) ; disparaît : l'adresse de diffusion dirigée du lien (et la possibilité d'un troisième équipement sur le segment). Linux et FRR le gèrent sans réglage.

**OSPF et BGP**

**11. État de liens / vecteur de chemins.** OSPF : chaque routeur diffuse la description de ses liens à toute la zone ; tous construisent la même carte et calculent eux-mêmes les plus courts chemins. BGP : chaque routeur annonce à ses voisins les préfixes qu'il sait joindre, avec le chemin d'AS parcouru, et chacun choisit selon des **politiques**. Les grands datacenters prennent BGP même à l'intérieur (RFC 7938) : un seul protocole du serveur à la bordure, des domaines de défaillance bornés (pas d'inondation de toute la zone à chaque changement), un contrôle fin de ce qui est annoncé à qui, une mise à l'échelle prouvée par Internet, et l'ECMP naturel des fabrics à AS par étage.

**12. Réponse B.** La session est `Established` (sinon on verrait `Active`, `Connect` ou `Idle`), mais la RFC 8212 (« Default External BGP Route Propagation Behavior without Policies ») veut qu'une session eBGP sans politique explicite n'accepte ni n'annonce **aucune** route ; FRR l'applique par défaut (`bgp ebgp-requires-policy`) et l'affiche `(Policy)`. A est faux : un mot de passe manquant empêche l'établissement ; C : les routes ne sont même pas acceptées ; D : un *peer-group* n'est jamais requis. Constaté en E07, étape 2.

**13. Sélection du meilleur chemin.** Dans FRR (comme chez la plupart des constructeurs) : (1) *weight* (local au routeur, propre à FRR et Cisco), (2) **local-preference** (le plus haut), (3) route d'origine locale, (4) **chemin d'AS** le plus court ; puis origine, MED, eBGP avant iBGP, coût IGP vers le *next-hop*, etc. Pour choisir par où **sortir** : la *local-preference*, posée en entrée sur ce qu'on apprend d'un voisin et propagée à tout l'AS. Pour influencer par où un voisin **entre** chez soi : allonger le chemin d'AS sur les autres liens (*AS-path prepend*), le MED (vers un même AS voisin) ou des communautés que le voisin honore — c'est une suggestion, le voisin décide.

**14. Spines dans le même AS.** Non : la route vers la boucle de `spine02` arrive avec le chemin `65101 65100`, qui contient l'AS de `spine01` : la détection de boucle de BGP la rejette. Ce n'est pas un problème : aucun trafic utile ne va d'un spine à l'autre (ils ne portent pas de serveurs), et c'est précisément ce qui empêche un leaf de servir de transit entre deux spines. Si l'on en avait besoin (supervision de la boucle d'un spine depuis l'autre), on passerait par le réseau d'administration, pas par la fabric.

**Redondance de passerelle et état**

**15. VRRP vu des hôtes.** Le nouveau maître envoie des **ARP gratuits** (« 10.10.99.240 est à telle MAC ») : les hôtes et les commutateurs mettent à jour leur cache ARP et leur FDB. Avec une MAC virtuelle, la MAC d'une VIP de VRID 199 est `00:00:5e:00:01:c7` (199 = 0xc7), et seul le port d'arrivée change dans la FDB ; keepalived, par défaut, garde la MAC réelle de l'interface et l'ARP gratuit change l'association IP → MAC chez les voisins. Les hôtes n'ont rien à reconfigurer : leur passerelle (ou leur service) reste **la même adresse IP**.

**16. Réponse B.** Un routeur VRRP qui ne reçoit plus d'annonces conclut que le maître est mort et devient maître : les deux portent la VIP (*split-brain*) ; les hôtes alternent selon le dernier ARP reçu, les connexions se cassent au hasard. A est faux : rien ne dit au moins prioritaire que l'autre vit ; C : chacun croit au contraire devoir porter la VIP ; D : aucun repli automatique. Parades : laisser passer VRRP (IP proto 112) dans les deux sens, unicast entre adresses fixes, supervision qui alerte sur deux maîtres (E29, E37).

**17. Basculement sans état.** La passerelle de secours ne connaît **aucune** des connexions en cours. Les paquets suivants d'une session SSH arrivent sans SYN : selon la configuration de conntrack (`nf_conntrack_tcp_loose`, actif par défaut sous Linux, reprend une connexion en cours de route) et selon le **sens** du premier paquet vu, l'entrée est créée dans un sens que la matrice n'autorise pas en `new` (par exemple INFRA → MGMT) et le trafic est jeté ; pour les flux traduits (NAT vers Internet), la correspondance de ports est perdue. Résultat : sessions figées ou coupées, transferts interrompus. Il faut **synchroniser l'état** (`conntrackd`, E27) et garder les mêmes adresses de traduction sur les deux passerelles (SNAT vers la VIP WAN, E26).

**MTU et tunnels**

**18. Pont à 1500 entre deux serveurs à 9000.** Chaque serveur annonce, dans son SYN, un MSS calculé sur son MTU (8960) : la connexion s'établit, SSH (petits paquets) fonctionne, puis le premier segment plein (9000 octets) est **jeté par le pont**, qui n'est pas un routeur : il n'envoie aucun ICMP « fragmentation needed », il compte juste une erreur. TCP retransmet le même gros segment, indéfiniment : le transfert se fige. La PMTUD repose sur un ICMP renvoyé par un **routeur** du chemin ; sur un même segment, il n'y en a pas (la *Packetization Layer* PMTUD, RFC 4821/8899, pourrait s'en sortir en sondant, mais elle n'est pas active par défaut pour TCP sous Linux : `net.ipv4.tcp_mtu_probing=0`). Si **un seul** serveur était à 9000 : TCP survivrait, car chacun envoie au plus le MSS annoncé par l'autre (1460) ; mais l'UDP, l'ICMP et tout trafic non TCP de plus de 1500 octets du serveur à 9000 seraient perdus (un `ping -s 2000` le montre). D'où la règle de E15 : MTU identique sur tout le segment, ponts compris.

**19. MTU d'un tunnel WireGuard.** Sur IPv4 : 1500 − 60 = **1440** ; `wg-quick` met 1420 par défaut (il compte l'en-tête IPv6, 40 octets au lieu de 20, pour être juste dans les deux cas). Si l'on oublie (MTU 1500 sur `wg0`), les paquets encapsulés dépassent 1500 : ils sont fragmentés à l'émission (surcoût, et perte totale si un équipement du chemin jette les fragments) ; et pour le trafic interne, un ICMP « fragmentation needed » filtré quelque part transforme le tunnel en **trou noir** pour les gros segments TCP : poignée de main WireGuard et `ping` passent, `git clone` se fige. Parades : le bon MTU, et le *clamping* du MSS (`tcp option maxseg size set rt mtu` dans nftables) sur la passerelle.

**20. `AllowedIPs`.** À l'**émission**, c'est une table de routage interne à l'interface : un paquet vers une destination contenue dans les `AllowedIPs` d'un pair est chiffré pour **ce** pair. À la **réception**, c'est un filtre : après déchiffrement, un paquet dont l'adresse **source** n'est pas dans les `AllowedIPs` du pair qui l'a envoyé est jeté (*cryptokey routing*). Deux pairs d'une même interface ne peuvent pas partager un préfixe : à l'émission, il faudrait choisir un seul destinataire ; WireGuard retire le préfixe du premier pair quand on l'ajoute au second (piège de E36 : un pair « vole » les adresses d'un autre).

---

### M07-E02 — Cartographier le réseau du lab de bout en bout

**Solution**

Document d'exemple complet : [`medisphere/docs/socle/reseau/cartographie.md`](fichiers/M07-E02/medisphere/docs/socle/reseau/cartographie.md). Tes valeurs (MAC, numéros de port *tap*, adresse WAN) diffèrent ; la structure et les commandes doivent s'y retrouver.

*A. Couche 2.*
1. `ip -br link show type bridge` montre `vmbr0`, `vmbr1` et un pont par VNet (`vmgmt`, `vinfra`… `vsandbox`). `bridge link show` dit qui est « maître » de quoi : les ports *tap* des VMs sont dans les ponts des VNets ; chaque pont de VNet a pour seule montée une interface VLAN `vmbr1.<VLAN>` (lisible dans `/etc/network/interfaces.d/sdn`, généré par le SDN) ; le port de `gw01` (`tap1000i1`) est directement dans `vmbr1`. Du point de vue du noyau, `vinfra` est donc un pont Linux ordinaire ; c'est `vmbr1.20` qui pose et retire l'étiquette 20. `bridge vlan show dev tap1000i1` liste tous les VLAN du lab : un *trunk*, d'où les sous-interfaces `ens19.<VLAN>` dans `gw01`.
2. `bridge fdb show br vmbr1 | grep -i <MAC-ADM01>` : une entrée `dev vmbr1.10 vlan 10 master vmbr1` (apprise sur le port VLAN 10 de `vmbr1`) ; `vlan` = le VLAN dans lequel la MAC a été apprise, `master` = le pont qui porte la table. Après cinq minutes sans trafic : l'entrée a disparu (vieillissement, 300 s). Les MTU des *tap* sont à 1500.
3. Sur `tap1000i1`, le `ping` d'`adm01` vers `git01` apparaît deux fois : la requête **entre** dans `gw01` étiquetée 10 et en **ressort** étiquetée 20 ; la réponse fait l'inverse. Sur le port d'`adm01` (`tap1001i0`), aucune étiquette.

*B. Couche 3.*
4. `ip -br addr` sur `gw01` : `ens18` (WAN), `ens19` sans adresse, `ens19.10` … `ens19.99` en `.1/24`, `wg0` (10.255.0.1/30), `wg1` (10.255.1.1/24). `ip -d link show ens19.20` : `vlan protocol 802.1Q id 20 <REORDER_HDR>`. `ip route` : réseaux connectés, 10.20.0.0/16 via `wg0`, défaut via la box. `nft list table ip nat` : `masquerade` vers le WAN sauf vers `pve01`. `wg show` : pair de `wg0` = `hp01` (`AllowedIPs` 10.20.0.0/16, 10.255.0.2/32), pairs de `wg1` = postes d'administration (10.255.1.x/32).
5. Sur `pve01`, les routes vers 10.10.0.0/16, 10.20.0.0/16 et 10.255.1.0/24 passent par `<IP-GW01-WAN>` : si `gw01` s'arrête, `pve01` ne joint plus ni le lab ni PAR2 (les sauvegardes PBS s'arrêtent) — c'est le point unique n° 1 et la raison de la VIP WAN de E26.

*C. Trajets.* Voir la section 3 du document d'exemple : `ip route get 10.10.20.12 from 10.10.10.10 iif ens19.10` sur `gw01` simule le transit sans envoyer de paquet ; `conntrack -L` montre la traduction d'adresse de `runner01` ; `wg show wg0 latest-handshakes` prouve que le tunnel vers PAR2 vit.

*D. MTU et points uniques.* Tableau des MTU : 1500 partout, 1420 sur les interfaces WireGuard (valeur de `wg-quick`). Les points uniques (section 5 du document) : `gw01`, l'adresse WAN codée en dur, les clés WireGuard sur un seul hôte, `pve01`, l'accès direct aux services publiés, la box, le relais DHCP.

*E. NetBox.* Écart attendu : `gw01` n'a que son IP primaire dans NetBox. Note-le : au palier 3, `.1` devient une VIP et `.2` l'adresse de `gw01` ; NetBox doit l'avoir avant (E25).

**Explications**

- **Le SDN de Proxmox est un générateur de configuration ifupdown2.** Une zone VLAN ne crée pas de VLAN « dans » `vmbr1` par magie : elle écrit des interfaces `vmbr1.<VLAN>` et des ponts de VNet dans `/etc/network/interfaces.d/sdn`. Lire ce fichier est le moyen le plus rapide de comprendre le chemin d'une trame.
- **Le trajet réel avant le schéma.** `ip route get`, `bridge fdb`, une capture courte : on vérifie ce que dit la documentation au lieu de la recopier. Un document qui dit comment **revérifier** reste vrai plus longtemps qu'un document qui affirme.

**Alternatives**

- Générer la partie couche 2 automatiquement (script de « Pour aller plus loin ») et la publier dans la CI de `plateforme/medisphere` : le document ne vieillit plus. NetBox peut aussi porter cette information (interfaces des VMs, VLAN des ports) et produire les schémas ; c'est la cible, au prix d'une modélisation plus fine.
- Outils de cartographie (`lldpd` dans les VMs, `netdisco`) : utiles sur un vrai réseau physique, peu parlants sur un pont Linux sans LLDP.

**Pièges classiques**

- Capturer sans filtre ni `-c` sur `vmbr1` : des milliers de paquets, et `tcpdump` qui se voit lui-même si tu es en SSH par ce chemin.
- Chercher les VLAN dans la configuration des VMs : avec le SDN, ils sont dans les VNets (la carte ne porte que `bridge=vinfra`).
- Oublier que `gw01` est **dans** le pool `lab` et sur `vmbr1` sans étiquette : un `tag=` ajouté par erreur sur sa carte coupe tout le lab sauf un VLAN.
- Confondre le MTU de l'interface et celui du chemin : `wg0` à 1420 n'empêche pas une VM d'envoyer 1500 octets vers PAR2 ; c'est `gw01` qui répond « fragmentation needed ».

**En production chez MédiSphère**

La cartographie fait partie du dossier d'architecture HDS : elle est revue à chaque changement réseau (fiche CHG), liée aux schémas de NetBox, et les commandes de revérification deviennent des contrôles automatiques de la supervision (E29). Les points uniques de défaillance alimentent le registre des risques et le plan de continuité (F5).

---

### M07-E03 — Monter la maquette réseau par le code

**Solution**

Fichiers : [`infra/outils/m07-vnets.sh`](fichiers/M07-E03/infra/outils/m07-vnets.sh), environnement [`infra/envs/m07-maquette/`](fichiers/M07-E03/infra/envs/m07-maquette/) ([`maquette.tf`](fichiers/M07-E03/infra/envs/m07-maquette/maquette.tf), [`main.tf`](fichiers/M07-E03/infra/envs/m07-maquette/main.tf), [`dns.tf`](fichiers/M07-E03/infra/envs/m07-maquette/dns.tf), [`netbox.tf`](fichiers/M07-E03/infra/envs/m07-maquette/netbox.tf), [`versions.tf`](fichiers/M07-E03/infra/envs/m07-maquette/versions.tf), [`providers.tf`](fichiers/M07-E03/infra/envs/m07-maquette/providers.tf), [`variables.tf`](fichiers/M07-E03/infra/envs/m07-maquette/variables.tf), [`outputs.tf`](fichiers/M07-E03/infra/envs/m07-maquette/outputs.tf), [`chiffrement.tf`](fichiers/M07-E03/infra/envs/m07-maquette/chiffrement.tf), [`README.md`](fichiers/M07-E03/infra/envs/m07-maquette/README.md)), Ansible [`group_vars/env_m07/`](fichiers/M07-E03/ansible/inventories/lab/group_vars/env_m07/), [`playbooks/m07-maquette.yml`](fichiers/M07-E03/ansible/playbooks/m07-maquette.yml), [`adm01/ssh-config-m07.extrait`](fichiers/M07-E03/adm01/ssh-config-m07.extrait), et l'[extrait](fichiers/M07-E03/ansible/inventories/lab/group_vars/role_bastion/outils-reseau.yml.extrait) pour les outils du bastion (introduction).

*A. Liens de fabric.*
1. Réponses du journal. **Ni sous-réseau ni passerelle** : ces VNets sont des câbles de couche 2 ; l'adressage et le routage appartiennent aux routeurs de la maquette (FRR), pas à `pve01`. Un sous-réseau SDN n'apporterait que de la gestion d'adresses (IPAM) inutile, et une passerelle n'a pas de sens dans une zone VLAN. **Un VNet par lien** : chaque lien point à point est un domaine de diffusion isolé, comme un câble ; une panne ou une capture sur un lien n'en touche pas d'autre ; OSPF y voit un vrai point à point (pas d'élection de routeur désigné), et deux routeurs ne deviennent pas voisins par accident. **Pas sur `vsandbox`** : tous les routeurs seraient sur un même segment avec le DHCP, les VMs jetables et `gw01` ; les protocoles de routage s'y découvriraient tous entre eux, et la fabric fuirait vers la passerelle du lab.
2. `m07-vnets.sh` : `etat`, `creer`, `supprimer`, idempotent (ne crée que ce qui manque), confirmation interactive, sauvegarde de `/etc/network/interfaces` et `interfaces.d/sdn` avant d'appliquer, refus d'appliquer si des changements en attente ne viennent pas de lui. Droits : `pveum acl modify /sdn/zones/lab/vfabN --roles PVESDNUser --users wb-tofu@pve` **et** `--tokens 'wb-tofu@pve!tofu'` (jeton à privilèges séparés : le droit effectif est l'intersection des deux).
3. Exécution :
   ```
   root@pve01:~# ./m07-vnets.sh etat
   root@pve01:~# ./m07-vnets.sh creer
   + vfab1 (VLAN 901)
   …
   Changements SDN en attente :
     vfab1 new
     …
   Appliquer le SDN (recharge le réseau de pve01) ? [oui/NON] oui
   Sauvegarde : /root/sauvegardes-reseau/AAAAMMJJ-HHMMSS
   root@pve01:~# bridge vlan show | grep -E '\b90[1-8]\b'
   root@pve01:~# diff /root/sauvegardes-reseau/<DATE>/sdn /etc/network/interfaces.d/sdn
   ```
   Le `diff` ne montre que des blocs ajoutés (`auto vfab1`, `iface vfab1`, `bridge_ports vmbr1.901`…).

*B. OpenTofu.*
4. `maquette.tf` décrit les VMs dans **une** carte de données (`local.vms`) : VMID, ressources, `admin` (`"dhcp"` ou une adresse fixe `/24`), liste **ordonnée** des cartes de fabric (`vnet`, `ipv4`), étiquettes de fonction. `main.tf` : une seule ressource `proxmox_virtual_environment_vm` avec `for_each = local.vms` ; `network_device` fixe pour `net0` (vsandbox) puis un bloc `dynamic "network_device"` sur `cartes` ; même chose pour `initialization.ip_config` (le n-ième bloc va à la n-ième carte). Ajouter `hap01` = une entrée dans `local.vms`.
5. `dns.tf` : le module `enregistrement-dns` en `for_each` sur les adresses fixes, plus un appel pour `web-demo`. `netbox.tf` : `netbox_ip_address` en statut `reserved` (et rôle `vrrp` pour la VIP), sans `dns_name` (un seul propriétaire par enregistrement : `dns.tf`). Le README justifie l'absence de VM NetBox.
6. Exécution (le README de l'environnement donne la séquence complète) :
   ```
   admin@adm01:~/src/infra/envs/m07-maquette$ . ../../outils/charger-acces.sh
   admin@adm01:~/src/infra/envs/m07-maquette$ set -a; . ~/.config/workbook/netbox-tofu.env; . ~/.config/workbook/powerdns-api.env; set +a
   admin@adm01:~/src/infra/envs/m07-maquette$ tofu init && tofu validate && tofu plan -out plan.bin
   Plan: 24 to add, 0 to change, 0 to destroy.
   admin@adm01:~/src/infra/envs/m07-maquette$ tofu apply plan.bin
   ```
   24 ressources : 9 VMs, 5 × 2 enregistrements DNS (A et PTR), 5 réservations NetBox. Dans le plan, vérifie pour `leaf01` : `network_device` × 5 (`vsandbox`, `vfab1`, `vfab3`, `vfab5`, `vfab7`) et `ip_config` × 5.

*C. Accès et configuration.*
7. Bloc `Host` de [`ssh-config-m07.extrait`](fichiers/M07-E03/adm01/ssh-config-m07.extrait) : `HostName %h.par1.medisphere.internal`, `User admin`, `UserKnownHostsFile ~/.ssh/known_hosts.m07`, `StrictHostKeyChecking accept-new`. Journal : ces VMs sont recréées chaque semaine, leurs clés d'hôte changent à chaque fois et elles n'ont pas (encore) de certificat d'hôte ; on accepte une clé **inconnue** dans un fichier réservé à la maquette, vidé à chaque reconstruction, mais une clé qui **change** sans reconstruction est refusée. Le risque résiduel (premier contact non vérifié) est limité au VLAN 99 et à des VMs sans secret. Pour le socle, la règle de M06-E19 (certificats d'hôte) ne change pas.
8. [`group_vars/env_m07/connexion.yml`](fichiers/M07-E03/ansible/inventories/lab/group_vars/env_m07/connexion.yml) (mêmes options pour Ansible), [`maquette.yml`](fichiers/M07-E03/ansible/inventories/lab/group_vars/env_m07/maquette.yml) (`base_paquets_role`), [`m07-maquette.yml`](fichiers/M07-E03/ansible/playbooks/m07-maquette.yml) : attente de SSH et de la fin de cloud-init, rôle `base`, puis contrôle que chaque carte de fabric a son adresse (lue dans les `proxmox_ipconfigN` de l'inventaire).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/proxmox.yml --graph m07_fabric
   @m07_fabric:
     |--leaf01
     |--leaf02
     |--spine01
     |--spine02
   admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/lab/proxmox.yml playbooks/m07-maquette.yml
   ```
9. Liens : `ssh spine01 ping -c1 10.10.250.1` etc. Sur `pve01`, `bridge link show | grep tap2073` donne les cinq ports de `leaf01`, chacun dans son pont de VNet. `ping 10.10.250.3` depuis `spine01` répond (voisin direct sur `vfab2`) ; `ping 10.10.250.5` échoue : `ip route get 10.10.250.5` montre `via 10.10.99.1 dev eth0` — faute de route, le paquet suit la route par défaut vers `gw01`, qui n'en a pas non plus et l'envoie vers Internet (traduit !), où il se perd. `traceroute` montre 10.10.99.1 puis la box. C'est le symptôme typique d'une route manquante dans un réseau qui a une route par défaut ; E06 le règle.
10. Reconstruction complète mesurée sur le lab de référence : 10 à 15 minutes (clones complets en parallèle, premier démarrage, `base`). À noter dans le README.

**Explications**

- **Pourquoi un script root pour le SDN, et pas le jeton d'OpenTofu ?** Créer un VNet demande `SDN.Allocate` sur la zone ; appliquer le SDN, sur `/sdn` : c'est le droit de reconfigurer le réseau de **l'hyperviseur**. Le donner au jeton d'OpenTofu, utilisé par la CI, permettrait à un pipeline compromis de couper `pve01`. On sépare : l'administrateur crée les câbles (rarement, en le surveillant), l'automatisation les utilise (`SDN.Use`, VNet par VNet).
- **`pvesh set /cluster/sdn` recharge tout le réseau de `pve01`.** `ifreload -a` réapplique toute la configuration ifupdown2 ; une modification manuelle jamais appliquée de `/etc/network/interfaces` (un pont en préparation, une adresse) prendrait effet à ce moment-là. D'où la sauvegarde, la vérification des changements en attente et l'accès console.
- **`for_each` + données.** La structure de `local.vms` est la seule chose qui change d'une maquette à l'autre ; la ressource est écrite une fois. C'est le même principe que le module `vm-debian`, sans l'imposer : `vm-debian` ne gère qu'une carte et une adresse allouée par NetBox, ce qui ne correspond pas à des VMs multi-cartes jetables.
- **Nommage des cartes.** La configuration réseau que Proxmox fournit à cloud-init nomme chaque carte `eth<N>` d'après `net<N>` (avec son adresse MAC) ; netplan applique ces noms. L'ordre de la liste `cartes` fixe donc les noms d'interface utilisés par FRR : on ne réordonne pas cette liste à la légère.

**Alternatives**

- **VNets dans OpenTofu** (ressources SDN de `bpg/proxmox`) avec un jeton d'administration du SDN distinct, appliqué à la main : traçabilité dans l'état, plan relu ; mais un état de plus et un jeton puissant à protéger. Le script est plus simple pour huit objets créés une fois.
- **Un VNet VLAN-aware unique** pour toute la fabric, chaque lien sur un VLAN porté par la VM (sous-interfaces dans les invités) : moins d'objets Proxmox, mais toute la configuration de couche 2 descend dans les invités, et une erreur d'étiquette relie deux liens.
- **Certificats d'hôte pour la maquette** : lire la clé d'hôte par l'agent QEMU (`qm guest exec`, droit `VM.GuestAgent.Unrestricted`, que nos jetons n'ont pas, à raison) ou injecter des clés pré-signées par un *snippet* cloud-init (M05-E19). Plus juste, plus lourd ; à faire si la maquette devenait durable.
- **Adresses DHCP partout** avec réservations Kea : propre pour les noms, mais une session BGP ou une annonce VRRP unicast n'aime pas une adresse qui pourrait changer ; les adresses fixes de la plage `.250-.254` sont plus lisibles.

**Pièges classiques**

- Oublier l'ACL sur l'**utilisateur** `wb-tofu@pve` (seulement sur le jeton) : `403 … SDN.Use` au `apply`, alors que le jeton « a le droit ».
- Lancer `pvesh set /cluster/sdn` avec des changements en attente qui ne sont pas à toi (essai abandonné dans l'interface web) : ils partent avec.
- Donner une passerelle aux cartes de fabric dans cloud-init : plusieurs routes par défaut, le trafic d'administration part par la fabric.
- Changer l'ordre des cartes d'une VM existante : `eth2` devient `vfab5`, la configuration FRR décrit l'ancien câblage, les sessions tombent sans erreur visible dans OpenTofu.
- `tofu destroy` dans le mauvais répertoire : relis toujours la liste (2070-2079 seulement). Le socle est protégé par `prevent_destroy`, pas la maquette.
- Ne pas vider `~/.ssh/known_hosts.m07` après une reconstruction : `accept-new` refuse la nouvelle clé (c'est le comportement voulu).

**En production chez MédiSphère**

Les « câbles » d'un vrai datacenter sont décrits dans NetBox (DCIM : câbles, ports, interfaces) et la configuration des commutateurs est générée à partir de lui. Une maquette de pré-production (souvent en conteneurs, avec `containerlab`) rejoue chaque changement de la fabric avant le déploiement ; c'est le rôle de notre maquette pour la bordure aux paliers 2 et 3.

---

### M07-E04 — Bonding Linux : active-backup et LACP

**Solution**

*A. Active-backup à la main* (sur `net01`, en root) :
```
root@net01:~# ip netns add ns-srv ; ip netns add ns-sw
root@net01:~# for i in 0 1; do ip link add vsrv$i netns ns-srv type veth peer name vsw$i netns ns-sw; done
root@net01:~# for ns in ns-srv ns-sw; do ip -n $ns link add bond0 type bond mode active-backup miimon 100; done
root@net01:~# for i in 0 1; do ip -n ns-srv link set vsrv$i master bond0; ip -n ns-sw link set vsw$i master bond0; done
root@net01:~# ip -n ns-srv addr add 172.31.70.1/24 dev bond0 ; ip -n ns-sw addr add 172.31.70.2/24 dev bond0
root@net01:~# for ns in ns-srv ns-sw; do ip -n $ns link set bond0 up; done
root@net01:~# ip netns exec ns-srv ping -c 3 172.31.70.2
root@net01:~# ip netns exec ns-srv cat /proc/net/bonding/bond0
Bonding Mode: fault-tolerance (active-backup)
Primary Slave: None
Currently Active Slave: vsrv0
MII Status: up
MII Polling Interval (ms): 100
…
Slave Interface: vsrv0
MII Status: up
Link Failure Count: 0
```
3. Coupe du lien actif (`ip -n ns-sw link set vsw0 down`) avec `ping -D -i 0.2` : **0 à 1** réponse perdue (détection en ≤ 100 ms, puis le bond émet sur `vsrv1` et envoie un ARP gratuit). Au rétablissement, `vsrv0` **ne redevient pas** actif : sans `primary`, `active-backup` ne revient jamais en arrière (et c'est voulu : pas de seconde coupure). Avec `primary vsrv0` (et `primary_reselect always`, le défaut), il revient dès que le lien est rétabli.
4. Avec `miimon 0` (et sans `arp_interval`), le bond ne surveille rien : la coupure de `vsw0` n'est pas vue, le bond continue d'émettre sur `vsrv0` et **tout** le trafic est perdu jusqu'à ce que tu rétablisses le lien. Le noyau l'annonce d'ailleurs à la création (« MII link monitoring set to off »).

*B. LACP à la main.* Recréation des bonds en `mode 802.3ad miimon 100 lacp_rate fast xmit_hash_policy layer3+4` (une fois les bonds supprimés : `ip -n ns-srv link del bond0`).
5. `ip netns exec ns-srv tcpdump -e -n -i vsrv0 ether proto 0x8809` : des trames vers **01:80:c2:00:00:02** (adresse des *Slow Protocols*), une par seconde et par lien en `fast`. `/proc/net/bonding/bond0` :
   ```
   Bonding Mode: IEEE 802.3ad Dynamic link aggregation
   Transmit Hash Policy: layer3+4 (1)
   …
   802.3ad info
   LACP active: on
   LACP rate: fast
   …
   Active Aggregator Info:
           Aggregator ID: 1
           Number of ports: 2
           Actor Key: …
           Partner Key: …
           Partner Mac Address: <MAC du bond de ns-sw>
   Slave Interface: vsrv0
   …
   Aggregator ID: 1
   ```
   Les deux esclaves ont le **même** identifiant d'agrégateur et un partenaire non nul : l'agrégat est négocié. Dans la section de chaque esclave, `actor/partner port state` (bits LACP : activité, *timeout* court, agrégation, synchronisation, collecte, distribution) et `churn` (« none » quand tout va bien). Le format exact des lignes varie selon la version du noyau.
6. Répartition (`iperf3 -s` dans `ns-sw`, `iperf3 -c 172.31.70.2` puis `-P 4` dans `ns-srv`, `ip -n ns-srv -s link show vsrv0` et `vsrv1` avant et après) : un flux → un seul esclave émet ; quatre flux → les deux émettent, en général (avec quatre flux et deux liens, il arrive que tous tombent du même côté : relance). En `layer2`, le hachage ne porte que sur les adresses MAC, identiques pour tous les flux entre ces deux bonds : un seul esclave émet, quel que soit le nombre de flux.
7. Désaccord (`ns-sw` en `active-backup`) : `ns-srv` n'a plus de partenaire (`Partner Mac Address: 00:00:00:00:00:00`), ses liens forment des agrégateurs **séparés** dont un seul est actif (« Number of ports: 1 »). Selon le lien que chaque côté a choisi, le `ping` passe… ou pas (les trames arrivées sur un port hors de l'agrégateur actif sont ignorées). « Ça marche » n'est donc pas « c'est sain » : la vérification porte sur l'état LACP, pas sur un `ping`. À observer sur ton lab : c'est l'un des cas de la panne E40.

*C. En code.* Rôle [`roles/bonding/`](fichiers/M07-E04/ansible/roles/bonding/) : variables ([`defaults/main.yml`](fichiers/M07-E04/ansible/roles/bonding/defaults/main.yml)), script [`m07-bond.sh.j2`](fichiers/M07-E04/ansible/roles/bonding/templates/m07-bond.sh.j2) (`demarrer` part toujours de zéro : supprimer un espace de noms détruit ses interfaces), unité `oneshot` + `RemainAfterExit`, gestionnaire qui reconstruit le labo à chaque changement, contrôle final par `ping` dans l'espace de noms. Playbook [`m07-net01.yml`](fichiers/M07-E05/ansible/playbooks/m07-net01.yml) (sa version finale, qui inclut `ovs_labo`, est dans les fichiers de E05).
```
admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/lab/proxmox.yml playbooks/m07-net01.yml --tags bonding
admin@adm01:~$ ssh net01 sudo /usr/local/sbin/m07-bond etat
admin@adm01:~$ ssh net01 sudo reboot      # puis, une minute plus tard :
admin@adm01:~$ lab/bin/check 07 04
```

**Explications**

- **Pourquoi des paires veth suffisent à LACP.** Une paire veth est un câble : ce qui entre d'un côté sort de l'autre, LACPDU comprises, sans pont au milieu pour les filtrer. Les veth annoncent une vitesse (10 Gbit/s, duplex intégral) : le mode 802.3ad, qui exige des liens de même vitesse et en duplex intégral, les accepte.
- **`miimon` et LACP sont complémentaires.** `miimon` voit la perte de porteuse en une centaine de millisecondes ; LACP voit, en trois intervalles (3 s en `fast`), un voisin qui ne participe plus ou un lien qui ne transporte plus.
- **Hachage `layer3+4`.** Il mélange adresses IP et ports : des connexions différentes entre deux mêmes machines se répartissent. Il n'est pas strictement conforme à 802.3ad pour les fragments IP (un fragment sans en-tête de port peut prendre un autre lien) : c'est documenté et accepté en pratique.
- **Pourquoi un script plutôt que systemd-networkd dans l'espace de noms.** `networkd` ne gère pas les espaces de noms ; un script lisible, généré depuis des variables, reconstruit en une commande, est ce qu'il faut pour un labo qu'on cassera exprès (E40).

**Alternatives**

- `active-backup` avec `arp_interval`/`arp_ip_target` : détecte aussi un chemin coupé au-delà du commutateur (pas seulement la porteuse) ; utile quand on ne peut pas faire de LACP.
- *Teaming* (`teamd`) : abandonné au profit du bonding dans les distributions récentes.
- Bond déclaré par netplan (section `bonds:`) pour un vrai serveur : c'est ce qu'on fera pour un hôte physique ; le labo, lui, vit dans des espaces de noms.

**Pièges classiques**

- Asservir un esclave **levé** : `Error: Device can not be enslaved while up` (certains noyaux le baissent d'eux-mêmes).
- Changer `mode` d'un bond qui a des esclaves : refusé ; il faut défaire et refaire (d'où la reconstruction complète du script).
- Conclure « LACP fonctionne » sur un `ping` réussi (étape 7).
- `lacp_rate slow` d'un côté et `fast` de l'autre : ça marche, mais la détection est lente dans un sens.
- Attendre d'un bond qu'il double le débit d'une copie unique.

**En production chez MédiSphère**

Les serveurs Ceph et les hyperviseurs physiques auront un bond 802.3ad vers une paire de commutateurs en MLAG (un lien vers chacun), `lacp_rate fast`, `layer3+4`, et une supervision de l'état LACP (nombre de ports de l'agrégateur actif, partenaire) plutôt que de la seule porteuse. Les liens de réplication Ceph (VLAN 31) et publics (VLAN 30) passent par ce bond avec des VLAN distincts.

---

### M07-E05 — Premiers pas avec Open vSwitch

**Solution**

*A. Le commutateur, à la main* (sur `net01`, en root) :
```
root@net01:~# apt install -y openvswitch-switch
root@net01:~# ovs-vsctl show ; ovs-vsctl list Open_vSwitch | grep -E 'ovs_version|db_version'
root@net01:~# ovs-vsctl add-br br-lab ; ip link set br-lab up
root@net01:~# for x in a b c r; do ip netns add ns-$x; ip -n ns-$x link set lo up; \
                ip link add ovs-$x type veth peer name eth0 netns ns-$x; \
                ovs-vsctl add-port br-lab ovs-$x; ip link set ovs-$x up; ip -n ns-$x link set eth0 up; done
root@net01:~# ovs-vsctl set port ovs-a tag=110 ; ovs-vsctl set port ovs-c tag=110 ; ovs-vsctl set port ovs-b tag=120
root@net01:~# ovs-vsctl set port ovs-r vlan_mode=trunk trunks=110,120
root@net01:~# ip -n ns-a addr add 172.31.110.10/24 dev eth0 ; ip -n ns-a route add default via 172.31.110.1
root@net01:~# ip -n ns-c addr add 172.31.110.11/24 dev eth0 ; ip -n ns-c route add default via 172.31.110.1
root@net01:~# ip -n ns-b addr add 172.31.120.10/24 dev eth0 ; ip -n ns-b route add default via 172.31.120.1
root@net01:~# for v in 110 120; do ip -n ns-r link add link eth0 name eth0.$v type vlan id $v; \
                ip -n ns-r addr add 172.31.$v.1/24 dev eth0.$v; ip -n ns-r link set eth0.$v up; done
root@net01:~# ip netns exec ns-r sysctl -w net.ipv4.ip_forward=1
```
`ovsdb-server` tient la base (`/etc/openvswitch/conf.db`), `ovs-vswitchd` le plan de données (module noyau `openvswitch`) ; `ovs-vsctl` parle à la base, `ovs-ofctl` aux tables OpenFlow, `ovs-appctl` aux démons.

3. `ns-a` → `ns-c` : commuté dans le VLAN 110. `ns-a` → `ns-b` : `traceroute` montre 172.31.110.1 puis 172.31.120.10. `tcpdump -e -n -i ovs-r` montre des trames `vlan 110` et `vlan 120` (trunk) ; sur `ovs-a`, aucune étiquette (accès : OVS la retire).

*B. Sous le capot.*
4. `ovs-appctl fdb/show br-lab` : colonnes `port VLAN MAC Age` ; la colonne VLAN est le VLAN dans lequel la MAC a été apprise : la même MAC de `ns-r` apparaît deux fois (110 et 120), une table par VLAN. `ovs-ofctl dump-flows br-lab` : **un** flux, `priority=0 actions=NORMAL` : « fais comme un commutateur classique » (apprentissage, VLAN, inondation).
5. `ovs-appctl ofproto/trace br-lab in_port=ovs-a,dl_src=<MAC-A>,dl_dst=<MAC-C>` : le flux `NORMAL` correspond, la décision est « *forwarding to learned port* » `ovs-c`, VLAN 110 ; avec la MAC de `ns-r` en destination, sortie sur `ovs-r` avec l'étiquette 110 (« *pushing VLAN* »). Avec une MAC inconnue : inondation dans le VLAN 110 seulement.

*C. Une règle.*
6. ```
   root@net01:~# ovs-ofctl add-flow br-lab "priority=200,icmp,nw_src=172.31.110.10,nw_dst=172.31.120.0/24,actions=drop"
   root@net01:~# ip netns exec ns-a ping -c 2 -W 1 172.31.120.10      # échoue
   root@net01:~# ip netns exec ns-b sh -c 'echo ok | nc -l -p 8080 -q 1' & ip netns exec ns-a nc -w 2 172.31.120.10 8080   # passe
   root@net01:~# ip netns exec ns-c ping -c 2 172.31.120.10           # passe
   root@net01:~# ovs-ofctl dump-flows br-lab                           # n_packets du flux 200 > 0
   root@net01:~# ovs-ofctl del-flows br-lab "icmp,nw_src=172.31.110.10,nw_dst=172.31.120.0/24"
   ```
   (`nc` : paquet `netcat-openbsd`, déjà présent dans l'image ou à installer.) Le paquet est jeté dès son **premier** passage (de `ovs-a` vers `ovs-r`) : son adresse IP de destination est déjà 172.31.120.10, seule la MAC de destination est celle du routeur.
7. Dans la vraie vie, un filtrage dans le commutateur est invisible pour qui lit le pare-feu, non journalisé, sans état (une règle par sens) : un piège d'exploitation. Mais c'est exactement ce que fait **OVN** : les groupes de sécurité d'OpenStack deviennent des flux OpenFlow (avec `ct()` pour l'état), générés par le contrôleur, jamais écrits à la main. Savoir les lire (`ovs-ofctl dump-flows`, `ofproto/trace`) sert au module 10.

*D. En code.* Rôle [`roles/ovs_labo/`](fichiers/M07-E05/ansible/roles/ovs_labo/) : topologie en variables, script [`m07-ovs.sh.j2`](fichiers/M07-E05/ansible/roles/ovs_labo/templates/m07-ovs.sh.j2) idempotent (`--may-exist`, `set port` réappliqué, `addr replace`, `route replace`), table OpenFlow remise à `NORMAL` à chaque démarrage, unité qui démarre **après** `openvswitch-switch` ; playbook [`m07-net01.yml`](fichiers/M07-E05/ansible/playbooks/m07-net01.yml). Avant d'appliquer, défais l'exploration : `for x in a b c r; do ip netns del ns-$x; done ; ovs-vsctl del-br br-lab`.

**Explications**

- **Ce qui survit à un redémarrage.** La base d'OVS (ponts, ports, réglages) persiste ; les espaces de noms et les veth, non. Au démarrage, OVS recrée les ports, qui pointent vers des interfaces absentes (« *could not open network device ovs-a (No such device)* » dans `ovs-vsctl show`) jusqu'à ce que le script recrée les veth : OVS les rattache alors tout seul.
- **`NORMAL` remis par le script.** Le labo garantit un état connu : un flux de diagnostic oublié disparaît au prochain démarrage du service. En production, ce sont les contrôleurs (OVN) qui possèdent les flux.
- **Pas de STP** sur `br-lab` (défaut d'OVS) : la topologie n'a pas de boucle ; E17 ajoute un agrégat, pas un second chemin.

**Alternatives**

- Le **pont Linux VLAN-aware** fait la même chose pour ce labo (`bridge vlan add … pvid untagged`) ; OVS apporte OpenFlow, les miroirs, les agrégats LACP gérés par OVS, l'intégration OVN.
- Le module Ansible `openvswitch.openvswitch` (`openvswitch_bridge`, `openvswitch_port`) : idempotence native pour les ponts et ports ; il ne gère ni les espaces de noms ni les veth, d'où le script.

**Pièges classiques**

- `ovs-ofctl del-flows br-lab` sans filtre : plus aucun flux, **plus rien ne passe** (même pas `NORMAL`). Remède : `ovs-ofctl add-flow br-lab priority=0,actions=NORMAL` (ou redémarrer `m07-ovs`).
- `add-port … tag=110` sur un port qui existe déjà avec `--may-exist` : le `tag` n'est pas modifié.
- Un port *trunk* sans `trunks=` : OVS le traite comme trunk de **tous** les VLAN ; avec `tag=` en plus, il devient un port d'accès.
- Oublier `ip_forward` dans `ns-r` (c'est un réglage **par espace de noms**).

**En production chez MédiSphère**

Open vSwitch ne sera pas installé à la main sur un hôte du socle : il arrive avec OpenStack (conteneurs de Kolla, OVN). Ce labo sert à lire ce qu'OVN programme. Les commandes `ovs-vsctl show`, `ovs-ofctl dump-flows`, `ovs-appctl ofproto/trace` entrent dans le runbook de diagnostic réseau d'OpenStack (module 10).

---

### M07-E06 — Routage statique puis OSPF avec FRR

**Solution**

*A. Découvrir FRR* (sur `spine01`, à la main) :
```
root@spine01:~# curl -fsSL -o /tmp/frr.gpg https://deb.frrouting.org/frr/keys.gpg
root@spine01:~# gpg --show-keys --with-colons /tmp/frr.gpg | grep '^fpr' | grep A90FC36D9429409798E9C2D874DEED43AB194DBF
root@spine01:~# install -m 644 /tmp/frr.gpg /usr/share/keyrings/frrouting.gpg
root@spine01:~# echo "deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr trixie frr-10" > /etc/apt/sources.list.d/frr.list
root@spine01:~# apt update && apt install -y frr frr-pythontools
root@spine01:~# grep -E '^[a-z0-9]+d=' /etc/frr/daemons ; ps -o comm= -C zebra,mgmtd,staticd,watchfrr
root@spine01:~# vtysh -c 'show version' -c 'show interface brief' -c 'show ip route'
root@spine01:~# apt purge -y frr frr-pythontools && rm /etc/apt/sources.list.d/frr.list
```
Le trousseau `keys.gpg` contient plusieurs clés ; celle qui signe aujourd'hui `InRelease` est `A90F C36D … AB19 4DBF` (vérifiable : `gpg --verify` du fichier `InRelease` du dépôt). Codes de route : `K` noyau (installée hors de FRR, ex. la route par défaut du DHCP), `C` connectée, `L` adresse locale, `S` statique, `O` OSPF, `B` BGP ; `>` meilleure route, `*` installée dans le noyau (FIB).

*B. Le rôle.* [`roles/frr/`](fichiers/M07-E06/ansible/roles/frr/) :
- [`tasks/paquets.yml`](fichiers/M07-E06/ansible/roles/frr/tasks/paquets.yml) : trousseau téléchargé dans un fichier temporaire, **refusé** s'il ne contient pas l'empreinte attendue, installé seulement ensuite ; source APT signée ; épinglage `Pin: version 10.7.*` (priorité 1001) ; contrôle de la version installée ;
- [`tasks/systeme.yml`](fichiers/M07-E06/ansible/roles/frr/tasks/systeme.yml) : `net.ipv4.ip_forward` ; fichier `/etc/systemd/networkd.conf.d/50-frr.conf` (`ManageForeignRoutes=no`, `ManageForeignRoutingPolicyRules=no`, `ManageForeignNextHops=no`) si `systemd-networkd` tourne ;
- [`tasks/configuration.yml`](fichiers/M07-E06/ansible/roles/frr/tasks/configuration.yml) : `/etc/frr/daemons` modifié **ligne par ligne** (les démons de protocole déduits de la configuration : `ospfd` si `frr_ospf` est fourni, `bgpd` si `frr_bgp` l'est) → redémarrage ; `frr.conf` produit par [`frr.conf.j2`](fichiers/M07-E06/ansible/roles/frr/templates/frr.conf.j2), validé par `vtysh --dryrun --inputfile`, `frr:frr` 640, sauvegarde → **rechargement** ;
- [`tasks/verifications.yml`](fichiers/M07-E06/ansible/roles/frr/tasks/verifications.yml) : chaque démon demandé tourne (et aucun autre), puis `frr-reload.py --test` doit renvoyer deux listes vides (la configuration chargée **est** celle du fichier) ;
- scénario Molecule [`molecule/frr/`](fichiers/M07-E06/ansible/molecule/frr/) : instance 2047, configuration OSPF + BGP de test sur des adresses de documentation, vérifications, puis tentative d'appliquer une ligne invalide : le rôle doit échouer **et** la configuration en place ne doit pas bouger.

*C. Routage statique.* Exemple pour `leaf01` (dans `host_vars/leaf01/frr.yml`, version provisoire) :
```yaml
frr_interfaces:
  - {nom: lo, adresses: [10.10.255.11/32]}
frr_routes_statiques:
  - {prefixe: 10.10.255.1/32, via: 10.10.250.0}    # spine01 par vfab1
  - {prefixe: 10.10.255.2/32, via: 10.10.250.4}    # spine02 par vfab3
  - {prefixe: 10.10.255.12/32, via: 10.10.250.0}   # leaf02 par spine01
```
avec, sur les spines, les routes vers les boucles des deux leaves, et sur `leaf02` le symétrique. Une seule route par destination : une route statique vers `10.10.255.12` par **deux** prochains sauts serait de l'ECMP statique (deux lignes `ip route` identiques au prochain saut près), mais elle ne saurait pas qu'un chemin est mort.
4. `vfab1` coupé côté `spine01` : `eth1` de `leaf01` reste *up* (sa carte virtuelle ne voit pas la coupure de l'autre bout), la route statique reste installée ; `leaf01` émet des requêtes ARP pour 10.10.250.0 sans réponse et les paquets vers la boucle de `spine01` partent dans le vide. Le routage statique ne sait rien de l'état du chemin. Ordre de grandeur pour 20 leaves et 4 spines : chaque leaf a besoin de 23 routes (19 leaves + 4 spines), chacune avec 4 prochains sauts pour l'ECMP, chaque spine de 20 routes : environ 2 000 lignes, à réécrire à chaque ajout, et aucune réaction aux pannes.

*D. OSPF.* `host_vars` finaux : [`spine01`](fichiers/M07-E06/ansible/inventories/lab/host_vars/spine01/frr.yml), [`spine02`](fichiers/M07-E06/ansible/inventories/lab/host_vars/spine02/frr.yml), [`leaf01`](fichiers/M07-E06/ansible/inventories/lab/host_vars/leaf01/frr.yml), [`leaf02`](fichiers/M07-E06/ansible/inventories/lab/host_vars/leaf02/frr.yml) ; playbook [`m07-fabric.yml`](fichiers/M07-E06/ansible/playbooks/m07-fabric.yml). Configuration produite pour `leaf01` (extrait) :
```
interface lo
 ip address 10.10.255.11/32
 ip ospf area 0.0.0.0
exit
interface eth1
 description vers spine01 (vfab1)
 ip ospf area 0.0.0.0
 ip ospf network point-to-point
 ip ospf cost 10
exit
…
router ospf
 ospf router-id 10.10.255.11
 passive-interface default
exit
interface eth1
 no ip ospf passive
exit
```
6. Observations (relevées à la rédaction sur la même topologie) :
```
leaf01# show ip ospf neighbor
Neighbor ID     Pri State           Up Time         Dead Time Address         Interface
10.10.255.1       1 Full/-          34.432s           30.484s 10.10.250.0     eth1:10.10.250.1
10.10.255.2       1 Full/-          34.432s           30.423s 10.10.250.4     eth2:10.10.250.5
10.10.255.12      1 Full/-          39.431s           30.534s 10.10.250.13    eth4:10.10.250.12
leaf01# show ip route ospf
O>* 10.10.255.12/32 [110/20] via 10.10.250.0, eth1, weight 1
  *                          via 10.10.250.4, eth2, weight 1
admin@leaf01:~$ ip route show 10.10.255.12
10.10.255.12 nhid 16 proto ospf metric 20
        nexthop via 10.10.250.0 dev eth1 weight 1
        nexthop via 10.10.250.4 dev eth2 weight 1
```
`Full/-` : adjacence complète, pas de rôle DR/BDR (lien point à point). Avec `vfab7` au coût par défaut (10), `leaf01` joignait `10.10.255.12` **directement** par `eth4` (coût 10 < 20) ; à 30, les deux chemins par les spines (10 + 10) gagnent, à égalité : ECMP.
7. Convergence : coupe de `vfab1` par `ip link set eth1 down` sur `spine01` → au plus quelques paquets perdus (moins d'une seconde) : `spine01` voit sa porteuse tomber, retire le lien de son LSA et l'inonde par `vfab2` ; `leaf01` recalcule et retire le chemin (le lien n'est plus déclaré des deux côtés). Coupe silencieuse :
```
root@spine01:~# nft add table netdev coupe
root@spine01:~# nft add chain netdev coupe entree '{ type filter hook ingress device "eth1" priority 0; policy drop; }'
root@spine01:~# nft add chain netdev coupe sortie '{ type filter hook egress device "eth1" priority 0; policy drop; }'
root@spine01:~# nft delete table netdev coupe          # pour rétablir
```
Rien ne change pendant jusqu'à **40 s** (`Dead 40s`, quatre *Hello* de 10 s manqués) : les flux hachés sur le chemin via `spine01` sont perdus (selon le hachage, ton `ping` est touché… ou pas du tout : refais l'essai depuis une autre boucle ou avec `traceroute` pour voir le chemin choisi). Puis l'adjacence tombe et le trafic passe par `spine02`.

**Explications**

- **Validation avant installation.** `vtysh --dryrun` utilise l'analyseur des démons : un mot-clé faux, une adresse invalide sont refusés avant d'atteindre `/etc/frr/frr.conf` (vérifié à la rédaction : « % Unknown command », code de retour 2). Attention, `vtysh` accepte les **abréviations** non ambiguës (`activat` passe) : la relecture humaine reste utile.
- **Recharger, ne pas redémarrer.** `systemctl reload frr` lance `frr-reload.py`, qui compare `show running-config` et le fichier, puis n'applique que les différences : ajouter une interface OSPF ne fait pas tomber les adjacences existantes. Un changement du fichier `daemons` impose un redémarrage (les démons sont lancés par `watchfrr` au démarrage).
- **Contrôle « configuration chargée = fichier ».** Un rechargement peut échouer en partie (commande refusée par un démon à l'exécution, alors qu'elle passait l'analyse) : `frr-reload.py --test` après coup le révèle. Seule exception connue : `frr version`, `frr defaults` et `service integrated-vtysh-config`, que `frr-reload.py` ignore.
- **`networkd` et les routes de FRR.** `systemd-networkd` considère comme « étrangères » les routes, règles et objets *nexthop* qu'il n'a pas créés et les supprime quand il reconfigure une interface (renouvellement DHCP qui change quelque chose, `netplan apply`, redémarrage de `networkd`). FRR installe ses routes ECMP sous forme d'objets *nexthop* (`nhid` dans `ip route`). Sans le fichier de compatibilité, la panne arrive **plus tard**, au premier événement réseau, et zebra croit toujours ses routes installées.
- **`eth0` passive.** Le VLAN 99 contient `gw01` et toutes les VMs jetables : une adjacence OSPF y annoncerait la fabric à n'importe qui, et n'importe qui pourrait lui injecter des routes.
- **Boucles annoncées en `/32` à coût 0.** La boucle ne tombe jamais (elle ne dépend d'aucun lien) : c'est l'adresse stable d'un routeur, celle qu'on utilise comme identifiant et, au palier 2, comme source des sessions.

**Alternatives**

- **`frr.conf` écrit en texte libre** dans l'inventaire (une variable multiligne par hôte) : plus simple, aucune abstraction à apprendre, mais aucune factorisation (les *prefix-lists* communes se recopient), et les erreurs ne se voient qu'à la validation. Le rôle accepte les deux (`frr_config_supplementaire`).
- **Configuration par l'API de FRR** (gRPC, northbound, `mgmtd`) : prometteur, encore partiel selon les démons en 10.x.
- **OSPF *unnumbered*** (`ip ospf network point-to-point` sur des interfaces sans adresse IPv4 propre, adresse de la boucle empruntée) : économise les `/31` ; l'équivalent BGP est l'objet de E14.
- **IS-IS** : choix courant des grands opérateurs pour l'IGP ; même famille (état de liens), indépendant d'IP.

**Pièges classiques**

- Oublier `ip ospf network point-to-point` sur un `/31` : OSPF fait une élection DR/BDR inutile et l'adjacence met 40 s (*Wait timer*) à monter.
- `passive-interface default` sans `no ip ospf passive` sur les liens de fabric : aucun voisin.
- Croire que `write memory` dans `vtysh` est une sauvegarde : le prochain passage d'Ansible écrase `frr.conf`. Toute modification passe par les `host_vars`.
- MTU différents aux deux bouts d'un lien : l'adjacence reste en `ExStart`/`Exchange` (« MTU mismatch detection »).
- Laisser une route statique « temporaire » : distance 1, elle l'emporte sur OSPF sans prévenir.
- Lancer le check de E06 après avoir commencé E07 : il vérifie OSPF, que E07 désactive.

**En production chez MédiSphère**

Le rôle `frr` part sur la bordure en E16 (AS 65000, FRR sur `gw01` puis `gw02`), avec les mêmes garanties : dépôt vérifié, version épinglée, validation, rechargement à chaud, contrôle de cohérence. Un changement de configuration de routage de la bordure passe par une fiche de changement et un passage en `--check --diff` relu ; les journaux de FRR (changements d'état des voisins) vont à la supervision (E29).

---

### M07-E07 — BGP avec FRR : sessions et politiques

**Solution**

Fichiers : [`group_vars/m07_fabric/frr.yml`](fichiers/M07-E07/ansible/inventories/lab/group_vars/m07_fabric/frr.yml) (mot de passe tiré de Vault, *prefix-list* commune `PL-FABRIC`, OSPF vidé), [`vault.yml.exemple`](fichiers/M07-E07/ansible/inventories/lab/group_vars/m07_fabric/vault.yml.exemple) (à chiffrer sous l'identité `lab`), `host_vars` de [`spine01`](fichiers/M07-E07/ansible/inventories/lab/host_vars/spine01/frr.yml), [`spine02`](fichiers/M07-E07/ansible/inventories/lab/host_vars/spine02/frr.yml), [`leaf01`](fichiers/M07-E07/ansible/inventories/lab/host_vars/leaf01/frr.yml), [`leaf02`](fichiers/M07-E07/ansible/inventories/lab/host_vars/leaf02/frr.yml). Le rôle `frr` de E06 gère déjà BGP (groupes, voisins, politiques par groupe ou par voisin, réseaux, `maximum_paths`, options brutes) : rien à étendre.

*A. Une session sans politique.*
2. ```
   leaf01# show bgp summary
   Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
   10.10.250.0     4      65100         3         3        1    0    0 00:00:43     (Policy) (Policy) N/A
   ```
   La session est établie (sinon la colonne afficherait `Active` ou `Connect`), mais rien n'est échangé : RFC 8212, appliquée par FRR (`bgp ebgp-requires-policy`, active par défaut, visible dans `show bgp neighbors` qui signale l'absence de politique d'entrée et de sortie). `show bgp neighbors 10.10.250.0` : capacités (*4-octet AS*, *route refresh*, *graceful restart*…), minuteries (60 s / 180 s en profil `traditional`), compteurs de messages.

*B. La fabric en eBGP.* Configuration produite pour `spine01` :
```
ip prefix-list PL-FABRIC seq 10 permit 10.10.255.0/24 ge 32
ip prefix-list PL-FABRIC seq 20 permit 10.10.250.0/24 ge 31 le 31
ip prefix-list PL-LEAF01 seq 10 permit 10.10.255.11/32
ip prefix-list PL-LEAF01 seq 20 permit 10.10.250.8/31
…
route-map RM-LEAF01-IN permit 10
 match ip address prefix-list PL-LEAF01
exit
route-map RM-LEAVES-OUT permit 10
 match ip address prefix-list PL-FABRIC
exit
…
router bgp 65100
 bgp router-id 10.10.255.1
 bgp log-neighbor-changes
 no bgp default ipv4-unicast
 neighbor LEAVES peer-group
 neighbor LEAVES password <MOT-DE-PASSE>
 neighbor 10.10.250.1 remote-as 65101
 neighbor 10.10.250.1 peer-group LEAVES
 neighbor 10.10.250.1 description leaf01
 neighbor 10.10.250.3 remote-as 65102
 neighbor 10.10.250.3 peer-group LEAVES
 neighbor 10.10.250.3 description leaf02
 !
 address-family ipv4 unicast
  network 10.10.255.1/32
  neighbor LEAVES activate
  neighbor LEAVES route-map RM-LEAVES-OUT out
  neighbor 10.10.250.1 route-map RM-LEAF01-IN in
  neighbor 10.10.250.3 route-map RM-LEAF02-IN in
 exit-address-family
exit
```
Un membre de groupe peut avoir sa propre politique d'**entrée** (ce que chaque leaf a le droit d'annoncer) ; la politique de **sortie** est commune au groupe. Les leaves : groupe `SPINES` (AS 65100, mot de passe, `RM-SPINES-IN` = `PL-FABRIC`, `RM-SPINES-OUT` = leur boucle et leur lien serveur, `soft-reconfiguration inbound`).
4. Après le playbook (qui désactive `ospfd` et active `bgpd` : redémarrage de FRR) :
```
leaf01# show bgp summary
Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
10.10.250.0     4      65100        11         7        8    0    0 00:00:50            3        2 spine01
10.10.250.4     4      65100        10         9        8    0    0 00:00:50            3        2 spine02
admin@leaf01:~$ ip route | grep bgp
10.10.250.10/31 nhid 18 proto bgp metric 20
10.10.255.1 nhid 14 via 10.10.250.0 dev eth1 proto bgp metric 20
10.10.255.2 nhid 13 via 10.10.250.4 dev eth2 proto bgp metric 20
10.10.255.12 nhid 18 proto bgp metric 20
```
Trois préfixes reçus de chaque spine (sa boucle, la boucle de `leaf02`, le lien de `srv02`), deux envoyés.
5. ```
   leaf01# show bgp ipv4 unicast 10.10.255.12/32
   Paths: (2 available, best #1, table default)
     Not advertised to any peer
     65100 65102
       10.10.250.4 from 10.10.250.4 (10.10.255.2)
         Origin IGP, valid, external, multipath, best (Older Path)
     65100 65102
       10.10.250.0 from 10.10.250.0 (10.10.255.1)
         Origin IGP, valid, external, multipath
   ```
   Deux chemins égaux jusqu'au critère du chemin d'AS (même longueur, même AS voisin) : tous deux *multipath*, installés ensemble (`ip route show 10.10.255.12` : deux `nexthop`). Le « meilleur » n'est départagé que pour l'annonce (ici, le plus ancien) ; « *Not advertised to any peer* » : la politique de sortie du leaf l'interdit.
6. `spine01` n'a pas de route vers `10.10.255.2` : (1) les leaves ne l'annoncent pas (sortie limitée à leurs propres préfixes), (2) et même s'ils l'annonçaient, le chemin `65101 65100` contient l'AS de `spine01` : rejet par la détection de boucle. `received-routes` exige `soft-reconfiguration inbound` sur le voisin (sinon : `% Inbound soft reconfiguration not enabled`) ; les leaves l'ont : `show bgp ipv4 unicast neighbors 10.10.250.0 received-routes` sur `leaf01` montre même ses **propres** préfixes, renvoyés par le spine et rejetés pour la même raison. Pas un problème (question 14 de E01).

*C. Politiques en action.*
7. ```
   leaf02# configure
   leaf02(config)# ip route 192.0.2.0/24 Null0
   leaf02(config)# router bgp 65102
   leaf02(config-router)# address-family ipv4 unicast
   leaf02(config-router-af)# network 192.0.2.0/24
   ```
   `spine01` ne reçoit **rien** (`show bgp ipv4 unicast 192.0.2.0/24` : « % Network not in table ») : la politique de **sortie** de `leaf02` filtre. Sans elle (`no neighbor SPINES route-map RM-SPINES-OUT out`), deux surprises : la session repasse en `(Policy)` côté envoi, `leaf02` **retire toutes ses annonces** (ses propres préfixes disparaissent de la fabric : coupure de `srv02` !) ; et si l'on contournait la RFC 8212, la politique d'**entrée** des spines (`RM-LEAF02-IN`) refuserait encore `192.0.2.0/24`. Deux barrières indépendantes : c'est le principe. Remise en état : `uv run ansible-playbook … playbooks/m07-fabric.yml --limit leaf02` (et la route `Null0`, qui n'est pas dans `frr.conf`, disparaît au rechargement).
8. Préférence : sur `leaf01`, une *route-map* d'entrée propre au voisin `spine01` (un membre peut surcharger l'entrée du groupe) :
   ```yaml
   frr_route_maps:   # en plus des précédentes
     - nom: RM-SPINE01-PREF
       entrees: [{seq: 10, action: permit, match: [ip address prefix-list PL-FABRIC], set: [local-preference 200]}]
   frr_bgp:          # extrait
     voisins:
       - {adresse: 10.10.250.0, groupe: SPINES, description: spine01, route_map_entree: RM-SPINE01-PREF}
   ```
   Après passage : un seul chemin (`best`, `localpref 200`), une seule ligne `via 10.10.250.0` dans le noyau, `traceroute` passe par 10.10.250.0. Pas en production dans une fabric : on perd l'ECMP (la moitié de la capacité), `spine01` porte tout, et le retour (décidé par `leaf02`) reste réparti : trafic asymétrique, plus difficile à diagnostiquer. On réserve ces leviers à la bordure (préférer un lien de transit) ou à la maintenance (vider un spine avant de l'arrêter : on préfère alors l'*AS-path prepend* ou `bgp graceful-shutdown`). Retire la surcharge et rejoue le playbook.
9. Mot de passe changé sur `spine02` (`neighbor LEAVES password autre`) : FRR **réinitialise aussitôt** les sessions concernées (constaté à la rédaction : `Up/Down 00:00:03`, état `Connect`), puis elles ne remontent plus. Le noyau des leaves jette les segments signés avec une autre clé et le journalise (`journalctl -k | grep -i md5` : « MD5 Hash mismatch », limité en débit) ; `bgpd` ne voit qu'une connexion qui n'aboutit pas. Le trafic continue par `spine01` (chemin ECMP retiré). Remise en état par le playbook.
10. Configuration finale : les `host_vars` de ce corrigé, `vault.yml` chiffré :
    ```
    admin@adm01:~/src/ansible$ cp …/vault.yml.exemple inventories/lab/group_vars/m07_fabric/vault.yml
    admin@adm01:~/src/ansible$ openssl rand -base64 18 | tr -d '\n' > ~/m07/bgp.tmp   # puis colle la valeur dans vault.yml
    admin@adm01:~/src/ansible$ uv run ansible-vault encrypt --encrypt-vault-id lab inventories/lab/group_vars/m07_fabric/vault.yml
    admin@adm01:~/src/ansible$ shred -u ~/m07/bgp.tmp
    ```

**Explications**

- **eBGP partout, un AS par leaf, un AS commun aux spines** (RFC 7938) : le chemin d'AS sert d'anti-boucle naturel (un leaf ne peut pas devenir transit entre spines), les chemins par les différents spines sont **identiques** (même AS voisin, même longueur) donc éligibles au multichemin sans réglage, et la valeur par défaut de `maximum-paths` en eBGP est le maximum compilé (aucune ligne n'apparaît dans `show running-config`). E42 cassera précisément cela (`maximum-paths 1`).
- **Deux barrières.** Le leaf n'annonce que ses préfixes (sortie) ; le spine n'accepte de chaque leaf que ses préfixes (entrée). Une erreur d'un côté est rattrapée par l'autre, et une fuite (ou un leaf compromis) ne peut pas attirer le trafic d'un autre.
- **`no bgp default ipv4-unicast`** : rien n'est activé implicitement ; chaque voisin est activé explicitement dans la famille d'adresses (c'est le défaut du profil `datacenter` de FRR et la bonne pratique dès qu'on ajoute IPv6 ou EVPN).
- **Le mot de passe est dans `frr.conf`, en clair.** C'est la seule forme que FRR connaisse ; d'où le 640 `frr:frr` et l'interdiction de l'afficher (`show running-config` devant un écran partagé…). Dans le dépôt, il n'existe que chiffré.

**Alternatives**

- **iBGP avec réflecteurs de routes** et un IGP (OSPF) dessous : modèle classique des réseaux d'opérateurs, plus de pièces mobiles dans une fabric.
- **Un AS par spine** : possible, impose `bgp bestpath as-path multipath-relax` sur les leaves et ouvre la porte au transit par un leaf si les politiques sont lâches.
- **`allowas-in`** pour que les spines (ou des leaves qui partagent un AS) acceptent leur propre AS : à proscrire sauf besoin précis, cela désactive l'anti-boucle.
- **TCP-AO** (RFC 5925) plutôt que TCP-MD5 : algorithmes modernes, rotation de clés sans coupure ; prise en charge récente dans Linux (6.7) et dans les démons de routage : à vérifier avant d'en faire un standard.

**Pièges classiques**

- Oublier la politique de sortie **ou** d'entrée : `(Policy)` d'un côté, et l'on cherche une panne de session alors que la session est établie.
- `network 10.10.250.8/31` alors que l'interface vers `srv01` est tombée : le préfixe n'est plus dans la table, il n'est plus annoncé (c'est voulu : `network` n'annonce que ce qui existe).
- Une *prefix-list* `permit 10.10.255.0/24` **sans** `ge 32` : elle n'accepte que le `/24` exact, pas les boucles.
- Changer le mot de passe d'un seul côté pendant une maintenance « rapide ».
- Mettre la politique de sortie sur un membre de groupe : FRR la refuse (elle appartient au groupe).
- Laisser une route `Null0` de test dans `vtysh` : elle disparaît au prochain rechargement… ou pas, si personne ne recharge ; la configuration de référence est le fichier.

**En production chez MédiSphère**

Les sessions BGP de la bordure (E16 : `leaf01` de la maquette, puis Kubernetes en M15, LYO1 en E19) reprennent ces principes : politiques explicites en entrée et en sortie, *prefix-lists* nommées par voisin, nombre maximal de préfixes acceptés (`maximum-prefix`), authentification, supervision de l'état des sessions et du nombre de préfixes (E29), journal des changements d'état des voisins (`bgp log-neighbor-changes`). Les mots de passe des sessions de la bordure sont dans Vault `critique` (usurper un voisin de la bordure, c'est détourner le trafic du site).

---

### M07-E08 — Une adresse virtuelle avec VRRP

**Solution**

*A. Les serveurs.* Rôle [`nginx_web`](fichiers/M07-E08/ansible/roles/nginx_web/) : site par défaut retiré, page [`index.html.j2`](fichiers/M07-E08/ansible/roles/nginx_web/templates/index.html.j2) (nom du serveur), site [`m07-web.conf.j2`](fichiers/M07-E08/ansible/roles/nginx_web/templates/m07-web.conf.j2) avec `location = /sante { return 200 "ok\n"; }` et un en-tête `X-Serveur`, gestionnaire qui valide **toute** la configuration (`nginx -t`) avant de recharger, contrôle final de `/sante`.

*B. VRRP à la main.* Instance minimale sur les deux serveurs (priorités 150 et 100) :
```
vrrp_instance ESSAI {
    state BACKUP
    interface eth0
    virtual_router_id 199
    priority 150
    advert_int 1
    virtual_ipaddress {
        10.10.99.240/24
    }
}
```
2. `srv01` est maître (priorité la plus haute). `tcpdump -n -i eth0 vrrp` sur `srv02` : `10.10.99.252 > 224.0.0.18: VRRPv2, Advertisement, vrid 199, prio 150, authtype none, intvl 1s` (v2 tant que `vrrp_version 3` n'est pas posé : c'est le défaut de keepalived). `ip -br addr show eth0` sur `srv01` : 10.10.99.252/24 **et** 10.10.99.240/24.
3. `curl http://10.10.99.240/` → `srv01`. Sur `gw01`, `ip neigh show 10.10.99.240` : `lladdr <MAC de srv01>` — keepalived n'utilise pas la MAC virtuelle `00:00:5e:00:01:c7` par défaut (`use_vmac` crée une interface *macvlan* qui la porte).
4. Arrêt de keepalived sur `srv01` : 1 à 3 requêtes perdues (avec la boucle à 200 ms) ; `srv01` envoie une annonce de priorité 0 en s'arrêtant (« je pars »), `srv02` devient maître sans attendre l'expiration et envoie des **ARP gratuits** : `gw01` met à jour son cache (`lladdr <MAC de srv02>`) sans rien avoir demandé. Au redémarrage de `srv01`, la VIP revient chez lui : **préemption** (priorité 150 > 100), seconde coupure, courte.

*C. Le rôle et la configuration cible.* Rôle [`keepalived`](fichiers/M07-E08/ansible/roles/keepalived/) ([`defaults`](fichiers/M07-E08/ansible/roles/keepalived/defaults/main.yml), [`tasks`](fichiers/M07-E08/ansible/roles/keepalived/tasks/main.yml), [`keepalived.conf.j2`](fichiers/M07-E08/ansible/roles/keepalived/templates/keepalived.conf.j2), [`keepalived-transition`](fichiers/M07-E08/ansible/roles/keepalived/files/keepalived-transition)), scénario Molecule [`molecule/keepalived/`](fichiers/M07-E08/ansible/molecule/keepalived/) (deux instances ; vérifie l'élection, la bascule quand le script de suivi échoue, le retour, et le journal), données [`group_vars/m07_web/keepalived.yml`](fichiers/M07-E08/ansible/inventories/lab/group_vars/m07_web/keepalived.yml), [`host_vars/srv01/web.yml`](fichiers/M07-E08/ansible/inventories/lab/host_vars/srv01/web.yml), [`srv02`](fichiers/M07-E08/ansible/inventories/lab/host_vars/srv02/web.yml), playbook [`m07-web.yml`](fichiers/M07-E08/ansible/playbooks/m07-web.yml). Configuration produite pour `srv02` :
```
global_defs {
    router_id srv02
    vrrp_version 3
    script_user keepalived_script
    enable_script_security
    vrrp_garp_master_refresh 60
}

vrrp_script chk_web {
    script "/usr/bin/curl -fsS -o /dev/null --max-time 2 http://127.0.0.1/sante"
    interval 2
    timeout 3
    fall 2
    rise 2
}

vrrp_instance DEMO_WEB {
    state BACKUP
    interface eth0
    virtual_router_id 199
    priority 100
    advert_int 1
    unicast_src_ip 10.10.99.253
    unicast_peer {
        10.10.99.252
    }
    virtual_ipaddress {
        10.10.99.240/24 dev eth0
    }
    track_script {
        chk_web
    }
    notify "/usr/local/sbin/keepalived-transition"
}
```
6. Avant d'appliquer, retire la configuration manuelle (le rôle écrase le fichier de toute façon ; arrête `keepalived` sur les deux serveurs pour repartir d'un état connu).
7. Arrêt de nginx sur `srv01` : le contrôle échoue deux fois (`fall 2`, intervalle 2 s) → `srv01` passe en `FAULT` et rend la VIP ; coupure mesurée de **4 à 6 s** (le temps de détection, puis la prise de VIP par `srv02`). Journal :
```
admin@srv01:~$ sudo journalctl -t keepalived-transition -o short-precise
… keepalived-transition: type=INSTANCE instance=DEMO_WEB etat=FAULT priorite=150
admin@srv02:~$ sudo journalctl -t keepalived-transition -o short-precise
… keepalived-transition: type=INSTANCE instance=DEMO_WEB etat=MASTER priorite=100
```
Nginx relancé : deux succès (`rise 2`), `srv01` redevient `BACKUP` puis, plus prioritaire, reprend la VIP (préemption) : coupure de l'ordre d'une seconde.
8. `nopreempt` (les deux en état initial `BACKUP`, ce qui est déjà le cas) : après le retour de nginx, `srv01` reste `BACKUP` ; la VIP reste sur `srv02` jusqu'à sa propre panne ou une bascule manuelle. Avantage pour une passerelle : **une seule** coupure par incident, et pas de retour automatique sur une machine peut-être pas tout à fait prête (connexions pas encore synchronisées, routes pas encore apprises). Prix : l'emplacement du maître n'est plus prévisible, la supervision et les procédures doivent le lire ; et un retour « au nominal » est une opération à planifier. Retour à la configuration cible (préemption) et MR.

**Explications**

- **VRRP v3 et unicast.** v3 (RFC 9568) gère IPv4 et IPv6, des intervalles sous la seconde, et n'a plus d'authentification (celle de v2 n'apportait rien : mot de passe en clair dans chaque annonce). L'unicast évite le multicast (224.0.0.18) : indispensable sur un réseau qu'on ne maîtrise pas (le LAN maison côté WAN, au palier 3), utile partout parce qu'un pair inattendu n'est jamais écouté.
- **Suivre le service, pas seulement la machine.** VRRP seul garantit qu'**une machine vivante** porte la VIP ; le `track_script` garantit qu'elle **sert**. Sans `weight`, un échec met l'instance en `FAULT` : simple et sûr pour deux serveurs. Avec deux scripts ou plus de deux pairs, des poids négatifs permettent une décision plus fine.
- **Compte des scripts.** `enable_script_security` refuse un script que quelqu'un d'autre que root pourrait modifier, et `script_user` évite de lancer `curl` en root toutes les deux secondes. `keepalived -t` vérifie aussi ces conditions.
- **Recharger.** `SIGHUP` relit la configuration ; une instance inchangée garde son état : on peut ajouter une VIP sans faire basculer l'autre.

**Alternatives**

- **Corosync/Pacemaker** : gestion de ressources bien plus riche (ordre de démarrage, contraintes, *fencing*), beaucoup plus lourde ; pertinent pour une base de données à disque partagé, pas pour une VIP.
- **Anycast par BGP** (chaque serveur annonce la même `/32` à sa fabric, ECMP) : actif-actif, sans élection, c'est ce que fera Kubernetes (M15) ; demande une fabric routée jusqu'au serveur.
- **Répartiteur devant les serveurs** (E10) : la VIP passe sur les répartiteurs, les serveurs n'ont plus besoin de VRRP.

**Pièges classiques**

- Deux instances d'un même VLAN avec le **même VRID** (ici 99 au lieu de 199, le jour où la passerelle du VLAN 99 passera en VRRP) : annonces mélangées, maîtres qui se disputent.
- `nopreempt` avec `state MASTER` : ignoré, sans erreur.
- Un `track_script` qui teste l'adresse **VIP** (`curl http://10.10.99.240/`) : il réussit tant que l'autre serveur répond, et ne détecte jamais la panne locale.
- Pare-feu local qui jette le protocole 112 (VRRP) : les deux deviennent maîtres (E37).
- Oublier la NetBox : une VIP non réservée finit allouée à une VM.

**En production chez MédiSphère**

Le rôle `keepalived` sert tel quel aux répartiteurs (`lb01`/`lb02`, VRID 170, E12) et aux passerelles (VRID = numéro de VLAN, groupe de synchronisation, scripts de transition qui montent les tunnels, E25-E26). La supervision (E29) alerte sur un état `FAULT`, sur deux maîtres d'un même VRID et sur toute transition ; les transitions journalisées alimentent les post-mortems.

---

### M07-E09 — Questions : L2, L3, agrégation, redondance

**Barème** : 2 points par question (24 au total). Une réponse qui cite une observation du lab (sortie, capture, mesure) vaut 2 si elle est juste ; sans observation, 1 au plus pour les questions 1, 3, 4, 7 et 11.

**1. Isolation par VNet.** La carte `eth1` de `spine01` est le port *tap* `tap2071i1`, membre du pont `vfab1`, dont la seule autre « montée » est `vmbr1.901` : la trame entre dans `vmbr1` étiquetée 901 et n'en ressort que par les ports qui portent le VLAN 901, c'est-à-dire `vmbr1.901` vers le pont `vfab1`, où se trouve `tap2073i1` (`eth1` de `leaf01`). Si `vfab1` et `vfab2` avaient le même VLAN (Proxmox devrait le refuser dans une même zone : à vérifier), leurs deux ponts seraient reliés au même `vmbr1.901` : un seul domaine de diffusion pour `spine01`, `leaf01` et `leaf02`, deux liens « point à point » qui n'en sont plus, et des adjacences inattendues.

**2. LACP et le pont.** Les LACPDU sont envoyées à **01:80:c2:00:00:02**, dans la plage 01:80:c2:00:00:0X que la norme 802.1D réserve aux protocoles de lien : un pont conforme ne les relaie **jamais**, puisque ces protocoles (STP, LACP, pause) parlent à l'équipement voisin, pas au-delà. Le pont Linux suit la norme ; `group_fwd_mask` permet de relayer certaines de ces adresses, mais pas celle de LACP (restriction du noyau). Entre deux espaces de noms reliés par des veth, il n'y a pas de pont : les LACPDU passent.

**3. Réponse A.** En `layer2`, le hachage ne prend que les adresses MAC source et destination : tous les flux entre deux mêmes bonds donnent la même valeur, donc le même esclave. B est faux (le second esclave reste dans l'agrégat, il n'émet juste rien pour ces flux) ; C est faux (`iperf3 -P` ouvre des connexions distinctes, avec des ports source distincts) ; D est faux (le hachage ne dépend pas du type d'interface).

**4. Premier passage.** Le paquet de `ns-a` vers `ns-b` porte dès le départ l'adresse IP de destination 172.31.120.10 (seule la MAC de destination est celle de `ns-r`) : il correspond au flux de priorité 200 lors de son **premier** passage (`ovs-a` → `ovs-r`) et est jeté là. Il n'y a pas de second passage. Le compteur `n_packets` du flux le confirme : une unité par requête.

**5. Recharger ou redémarrer FRR.** `frr-reload.py` n'envoie aux démons que les lignes qui changent : une session BGP ou une adjacence OSPF dont la configuration n'a pas changé n'est pas touchée (pas de coupure, pas de nouvel échange de tables). Certaines modifications réinitialisent quand même la session concernée (changement de mot de passe, d'AS distant, de `router-id`). Un redémarrage reste obligatoire pour démarrer ou arrêter un démon (fichier `daemons`), changer les options de lancement, ou après une mise à jour du paquet.

**6. `networkd` et les routes étrangères.** Par défaut, `systemd-networkd` supprime, quand il (re)configure une interface, les routes, règles et objets *nexthop* qu'il n'a pas créés. Les routes de FRR (et leurs *nexthop* ECMP) auraient disparu au premier événement : renouvellement DHCP de `eth0` qui change un paramètre, `netplan apply`, redémarrage de `networkd`, mise à jour de `systemd`. Zebra, lui, les croirait toujours installées : routes absentes du noyau, `show ip route` normal, trafic perdu — des jours après l'installation, sans lien apparent avec la cause.

**7. Deux durées de convergence.** `ip link set down` côté spine : la porteuse tombe, zebra prévient `ospfd` immédiatement, le spine retire le lien de son LSA, l'inonde, tout le monde recalcule (quelques dizaines de millisecondes de temporisation SPF) : moins d'une seconde. Coupe silencieuse : rien ne signale la panne, sauf l'absence de *Hello* : il faut attendre le *dead interval* (40 s par défaut). Parade standard : **BFD** (détection en quelques centaines de millisecondes par des échanges légers, indépendants du protocole de routage). Elle ne remplace pas la porteuse : la perte de porteuse est instantanée et gratuite, BFD ajoute la détection de ce que la porteuse ne voit pas (lien *up* mais muet, équipement intermédiaire en panne).

**8. Réponse B.** Avec des AS de spines différents, les deux chemins d'AS (`65100 65102` et `65110 65102`) ont la même longueur mais ne sont pas identiques : par défaut, BGP n'en fait pas du multichemin. `bgp bestpath as-path multipath-relax` l'autorise pour des chemins de même longueur. A est faux pour cette raison ; C concerne l'iBGP ; D casserait l'anti-boucle entre leaves sans régler la question.

**9. Pas de transit par un leaf.** Si `leaf01` réannonçait à `spine02` ce qu'il apprend de `spine01`, des préfixes pourraient être joints « par un leaf » : trafic d'un spine à l'autre à travers les ports de `leaf01` (dimensionnés pour des serveurs, pas pour du transit), chemins plus longs et imprévisibles, et la panne de ce leaf affecterait des flux qui ne le concernent pas. Dans notre maquette, l'AS commun des spines rejette déjà ces chemins (boucle) ; mais dès qu'un spine annonce des préfixes extérieurs (la bordure, E16), ou si les spines ont des AS distincts, seule la politique de sortie du leaf empêche la fuite. On l'écrit donc toujours.

**10. TCP-MD5 et GTSM.** TCP-MD5 (RFC 2385) signe chaque segment avec une clé partagée : il empêche l'injection de segments falsifiés dans la session (RST qui coupe la session, faux UPDATE) et l'établissement par un pair qui ne connaît pas la clé. Il ne chiffre rien (les annonces circulent en clair), ne protège pas d'un voisin légitime compromis, repose sur MD5 et ne permet pas de changer la clé sans coupure (TCP-AO le permet). **GTSM** (`neighbor … ttl-security hops 1`) : les voisins émettent avec un TTL de 255 et n'acceptent que 254 ou plus ; un attaquant qui n'est pas sur le lien ne peut pas atteindre la session (son paquet arrive avec un TTL plus bas), ce qui protège aussi le processeur de `bgpd` contre une inondation à distance. Pour des voisins directs, les deux se complètent.

**11. ARP gratuit.** Le nouveau maître diffuse des ARP gratuits (« 10.10.99.240 est à ma MAC ») ; `gw01`, qui avait une entrée pour cette adresse, la met à jour. Si le message était perdu, `gw01` continuerait d'envoyer à l'ancienne MAC jusqu'à ce que son entrée devienne « périmée » et qu'il revérifie (une requête vers l'ancienne MAC sans réponse, puis une diffusion) : des dizaines de secondes de trafic perdu. keepalived envoie donc plusieurs ARP gratuits à la prise de VIP et, avec `vrrp_garp_master_refresh`, les répète régulièrement tant qu'il est maître : un voisin qui aurait manqué la bascule (ou redémarré) se recale de lui-même.

**12. Préemption ou non.** Pour la **non-préemption** (Nadia) : une seule coupure par incident ; pas de retour automatique sur une passerelle qui vient de redémarrer et dont l'état n'est pas encore complet (connexions pas synchronisées, sessions BGP pas établies, règles pas encore chargées) ; pas de « ping-pong » si la panne est intermittente. Pour la **préemption** (Karim) : l'emplacement du maître est prévisible (supervision, procédures, `gw01` mieux dimensionné ou mieux placé), le retour au nominal ne dépend pas d'une action humaine oubliée. Recommandation : préemption **avec délai** (`preempt_delay`, une à deux minutes) dans un groupe de synchronisation, à condition que le délai couvre la resynchronisation de `conntrackd` (E27) et l'établissement des sessions de la bordure, et que la bascule de retour soit observée par la supervision. Sinon, non-préemption et retour manuel planifié (RB-071).
