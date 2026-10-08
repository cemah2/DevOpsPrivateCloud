# Module 07 — Palier 1 : Découverte

Avant de doubler la bordure, il faut savoir lire le réseau qu'on a et pratiquer, sans risque, ce qu'on va y mettre. Ce palier commence par une **cartographie** du lab tel qu'il est (de la carte réseau d'une VM jusqu'à la box), puis monte par le code une **maquette** de dix VMs jetables : une fabric *leaf-spine*, deux serveurs web, un site distant, une VM de laboratoire. Sur elle, tu pratiques les fondamentaux du réseau de datacenter : agrégation de liens et LACP, Open vSwitch, routage statique puis OSPF, BGP et ses politiques, adresse virtuelle VRRP. Les rôles `frr` et `keepalived` écrits ici serviront, enrichis, sur la bordure du socle aux paliers 2 et 3. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : module 06 terminé (`lab/bin/check 06 46` vert) ; module 05 (OpenTofu, état chiffré, `charger-acces.sh`) ; module 04 (rôles, Vault, Molecule, inventaire Proxmox). Lis [`00-introduction.md`](00-introduction.md), en particulier l'architecture de la maquette, le plan d'adressage de la fabric et les règles du module.

---

### M07-E01 — Test de positionnement : réseau de datacenter  `Q` `★★`

> **Ticket PLAT-801** — *De : Karim Benali*
> Tu connais le réseau d'entreprise ; un réseau de datacenter, c'est la même physique avec d'autres réflexes : tout est redondé, tout est routé, et une erreur de MTU coûte une nuit. Une heure, par écrit, sans moteur de recherche ni IA, sans rien exécuter. Réponds même là où tu hésites : le raisonnement compte.

**Objectifs pédagogiques**
- Évaluer tes acquis sur les mécanismes que le module met en œuvre : couche 2, agrégation, routage, BGP, redondance de passerelle, MTU, tunnels.
- Repérer les notions à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Couche 2*

1. Un pont Linux reçoit une trame destinée à une adresse MAC qu'il n'a jamais vue. Que fait-il ? Et s'il la connaît, mais sur le port même d'où vient la trame ? Comment s'appelle la table qu'il consulte, et combien de temps une entrée y reste-t-elle par défaut ?

2. *(QCM)* Sur un lien *trunk* 802.1Q, une trame arrive **sans** étiquette. Que se passe-t-il, en général ?
   - A. Elle est rejetée : un *trunk* n'accepte que des trames étiquetées
   - B. Elle est rattachée au VLAN natif (PVID) du port
   - C. Elle est diffusée dans tous les VLAN du *trunk*
   - D. Elle est étiquetée VLAN 0 et traitée comme une trame de priorité

3. Pourquoi une boucle de couche 2 est-elle catastrophique (trois effets) alors qu'une boucle de routage IP « seulement » gênante ? Quel champ de l'en-tête IP fait la différence ?

*Agrégation de liens*

4. Compare les modes `active-backup`, `balance-xor` et `802.3ad` du bonding Linux : ce que chacun exige du commutateur d'en face, ce qu'il apporte en débit et en tolérance aux pannes.

5. *(QCM)* Un serveur a un bond LACP de deux liens à 10 Gbit/s (hachage `layer3+4`). Une seule copie `scp` vers une autre machine atteint au mieux :
   - A. 20 Gbit/s : LACP additionne les liens
   - B. 10 Gbit/s : un flux est toujours placé sur un seul lien
   - C. 5 Gbit/s : LACP divise chaque flux en deux
   - D. 20 Gbit/s si `miimon` est réglé à 100

6. Que détecte LACP que la seule surveillance de la porteuse (`miimon`) ne détecte pas ? Donne un exemple concret de panne.

*Routage*

7. La table d'un routeur contient `10.10.0.0/16 via A`, `10.10.250.0/24 via B` et `0.0.0.0/0 via C`. Par où part un paquet vers 10.10.250.9 ? Vers 10.10.99.20 ? Vers 10.30.10.10 ? Énonce la règle.

8. Qu'est-ce que l'**ECMP** ? Pourquoi le noyau répartit-il **par flux** et non par paquet ? Quel problème la répartition par paquet causerait-elle à TCP ?

9. Un routeur apprend 10.10.255.12/32 par OSPF (coût 20) et par eBGP. Lequel installe-t-il dans la table, et selon quel critère ? Que changerait le fait qu'il l'apprenne aussi par une route statique ?

10. Pourquoi peut-on numéroter un lien point à point en `/31` (RFC 3021) ? Qu'est-ce que cela économise, et qu'est-ce qui disparaît par rapport à un `/30` ?

*OSPF et BGP*

11. OSPF est un protocole « à état de liens », BGP un protocole « à vecteur de chemins ». Explique la différence en une phrase chacun, puis dis pourquoi les grands datacenters préfèrent souvent BGP même à l'intérieur (RFC 7938).

12. *(QCM)* Deux routeurs FRR établissent une session eBGP ; `show bgp summary` affiche `(Policy)` dans la colonne des préfixes reçus et envoyés. Que se passe-t-il ?
    - A. La session n'est pas établie : un mot de passe est requis
    - B. La session est établie, mais aucune route n'est acceptée ni annoncée faute de politique explicite (RFC 8212)
    - C. Les routes sont échangées mais pas installées dans le noyau
    - D. La session attend la configuration d'un *peer-group*

13. Cite, dans l'ordre, les quatre premiers critères de sélection du meilleur chemin BGP (dans FRR ou chez un constructeur courant). Lequel utiliserais-tu pour qu'un AS préfère **sortir** par un voisin plutôt qu'un autre ? Et pour qu'un AS voisin préfère **entrer** par un de tes liens ?

14. Dans une fabric où les deux *spines* partagent l'AS 65100, `spine01` reçoit de `leaf01` une route vers la boucle de `spine02`. L'installe-t-il ? Pourquoi ? Est-ce un problème ?

*Redondance de passerelle et état*

15. Comment un hôte du réseau apprend-il qu'une VIP VRRP a changé de routeur ? Quelle est l'adresse MAC d'une VIP de VRID 199 ? Pourquoi les hôtes n'ont-ils rien à reconfigurer ?

16. *(QCM)* Deux routeurs keepalived ne reçoivent plus les annonces VRRP l'un de l'autre (filtrage), mais chacun fonctionne. Que se passe-t-il ?
    - A. Le moins prioritaire s'arrête de lui-même
    - B. Les deux se déclarent maîtres et portent la VIP : *split-brain*
    - C. La VIP disparaît des deux routeurs
    - D. keepalived bascule automatiquement en multicast

17. Une passerelle filtre avec état (`ct state established,related accept`). La VIP bascule sur la passerelle de secours, configurée avec les **mêmes** règles. Que deviennent les sessions SSH ouvertes à travers la bordure ? Pourquoi ? Que faudrait-il ?

*MTU et tunnels*

18. Deux serveurs de stockage, tous deux à MTU 9000, sont reliés par un pont resté à MTU 1500. Le `ping` passe, une session SSH aussi, mais un gros transfert se fige. Explique, puis dis pourquoi la découverte du MTU du chemin (PMTUD) ne sauve rien ici. Que changerait le fait qu'un seul des deux serveurs soit à 9000 ?

19. Un tunnel WireGuard sur IPv4 ajoute 60 octets d'en-tête (IPv4 20, UDP 8, WireGuard 32). Avec une MTU de 1500 sur le lien physique, quelle MTU donner à l'interface `wg0` ? Que se passe-t-il pour une connexion TCP si l'on oublie et qu'un ICMP « fragmentation needed » est filtré quelque part ?

20. Dans WireGuard, que signifie `AllowedIPs` **à l'émission** et **à la réception** ? Pourquoi deux pairs d'une même interface ne peuvent-ils pas avoir des `AllowedIPs` qui se chevauchent ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour chaque mécanisme de redondance (bond, ECMP, VRRP), pose-toi trois questions : **qui** détecte la panne, **en combien de temps**, et **qui doit être prévenu** (le voisin, les hôtes, la table de routage) ? Beaucoup de réponses en découlent.
</details>

<details><summary>Indice 2</summary>

Pour les questions de MTU, raisonne paquet par paquet : qui émet, avec quelle taille, avec ou sans le bit DF, et qui pourrait renvoyer un message d'erreur à l'émetteur. Sur un même segment, il n'y a aucun routeur entre les deux machines.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M07-E46), sans relire le corrigé, et compare.

---

### M07-E02 — Cartographier le réseau du lab de bout en bout  `LAB` `★`

> **Ticket PLAT-802** — *De : Claire Morel* — *Copie : Nadia Roussel*
> Avant de doubler quoi que ce soit, je veux un document qui dise **exactement** par où passe un paquet chez nous : de la carte d'une VM jusqu'à la box, avec les VLAN, les ponts, les interfaces de `gw01`, les tunnels et les MTU. Nadia en a besoin pour l'astreinte, et toi pour savoir ce que tu vas casser au palier 3. Et je veux la liste des points uniques de défaillance, sans complaisance.

**Objectifs pédagogiques**
- Lire un réseau virtualisé couche par couche : pont VLAN-aware, VNets SDN, ports *tap*, table FDB, sous-interfaces, routes, NAT, tunnels.
- Suivre le trajet réel d'un paquet avec les outils d'observation (`bridge`, `ip`, `tcpdump`, `nft`, `wg`, `traceroute`).
- Produire une documentation réseau exploitable par quelqu'un d'autre.

**Prérequis** : M00 (lab, SDN, `gw01`, WireGuard) ; M06-E05 (modèle NetBox).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Cet exercice est en **lecture seule** : aucune commande ne modifie `pve01` ni `gw01`. Les captures (`tcpdump`) se lancent avec un filtre et une limite de paquets (`-c`).
- Livrable : `docs/socle/reseau/cartographie.md` dans `plateforme/medisphere` (MR, fusion sur `main`).

**Travail demandé**

*A. La couche 2 sur `pve01`*

1. Liste les ponts et leurs ports, puis les VLAN autorisés sur chaque port de `vmbr1` :
   ```
   root@pve01:~# ip -br link show type bridge
   root@pve01:~# bridge link show | grep -E 'master (vmbr1|v[a-z]+)'
   root@pve01:~# bridge vlan show
   ```
   Relie chaque VNet du SDN à son VLAN (`pvesh get /cluster/sdn/vnets`, `/etc/network/interfaces.d/sdn`). Que sont les interfaces `vinfra`, `vsandbox`… du point de vue du noyau ? Comment `ens19` de `gw01` (sans étiquette côté VM) reçoit-il tous les VLAN ?
2. Trouve le port *tap* de `adm01` (`tap1001i0`) et celui de `gw01` (`tap1000i1`). Relève leur MTU et les VLAN qu'ils portent. Observe la table FDB de `vmbr1` pour l'adresse MAC de `adm01` (relevée dans `qm config 1001`) :
   ```
   root@pve01:~# bridge fdb show br vmbr1 | grep -i <MAC-ADM01>
   ```
   Que signifient les champs `vlan` et `master` ? Laisse passer cinq minutes sans trafic depuis `adm01` : l'entrée est-elle toujours là ?
3. Observe une trame étiquetée sur le pont, en limitant la capture :
   ```
   root@pve01:~# tcpdump -e -n -c 6 -i tap1000i1 'vlan and icmp'
   ```
   pendant qu'un `ping` part d'`adm01` vers `git01`. Note les étiquettes vues dans chaque sens.

*B. La couche 3 sur `gw01`*

4. Relève les interfaces et leurs adresses, les routes, les règles de routage et le NAT :
   ```
   admin@gw01:~$ ip -br addr ; ip -d link show ens19.20 | head -n 3
   admin@gw01:~$ ip route ; ip rule
   admin@gw01:~$ sudo nft list table ip nat
   admin@gw01:~$ sudo wg show
   ```
   Pour chaque tunnel : interface, port, pair, `AllowedIPs`, dernière poignée de main.
5. Sur `pve01`, relève les routes vers le lab (`ip route | grep -E '10\.(10|20|255)'`) : par quelle adresse passent-elles ? Que se passerait-il pour `pve01` si `gw01` s'arrêtait ?

*C. Trois trajets*

6. Pour chacun des trajets suivants, décris chaque saut (interface, VLAN, pont, routage, NAT, tunnel) et vérifie-le avec `ip route get`, `traceroute` ou une capture :
   - `adm01` → `git01:443` ;
   - `runner01` → un site Internet (paquets Debian) ;
   - `git01` → `pbs01:8007` (sauvegarde vers PAR2).

*D. MTU et points uniques de défaillance*

7. Dresse le tableau des MTU : `vmbr0`, `vmbr1`, les ports *tap* de `gw01`, `ens18`, `ens19` et ses sous-interfaces, `wg0`, `wg1`, une VM du VLAN 20. Où le MTU se réduit-il, et pourquoi ?
8. Liste les points uniques de défaillance du réseau du lab (équipement, lien, service, configuration) et, pour chacun, l'effet de sa perte. Classe-les. Indique lesquels le module 07 va traiter.

*E. Le document*

9. Rédige `docs/socle/reseau/cartographie.md` : schéma couche 2 (ponts, VLAN, VNets, ports), schéma couche 3 (réseaux, `gw01`, routes, tunnels), tableau des VLAN (numéro, VNet, réseau, passerelle, MTU), les trois trajets, le tableau des MTU, la liste des points uniques de défaillance, et les commandes qui permettent de **revérifier** chaque information. Compare au passage avec NetBox : `gw01` y a-t-il une interface par VLAN ? Note les écarts.

**Critères de réussite**
- [ ] `docs/socle/reseau/cartographie.md` est sur `main` de `plateforme/medisphere`.
- [ ] Il décrit les 13 VLAN de PAR1 avec leur VNet, leur réseau et leur MTU, les ponts `vmbr0` et `vmbr1`, l'interface `ens19` de `gw01` et ses sous-interfaces, et les tunnels `wg0` et `wg1`.
- [ ] Il contient les trois trajets, le tableau des MTU et une section « points uniques de défaillance » d'au moins cinq entrées.
- [ ] Chaque information importante est accompagnée de la commande qui permet de la revérifier.

**Vérification** : `lab/bin/check 07 02`

<details><summary>Indice 1</summary>

Avec le SDN en zone VLAN, Proxmox ne crée pas un pont par VLAN sur `vmbr1` : chaque VNet est un petit pont (`vinfra`…) relié à `vmbr1` par une interface VLAN. Regarde `ip -d link show vinfra` et ce qui est « maître » de quoi dans `bridge link show`. `gw01`, lui, est branché directement sur `vmbr1` : son port porte plusieurs VLAN.
</details>

<details><summary>Indice 2</summary>

`ip route get <adresse>` donne la décision de routage du noyau sans envoyer de paquet, `ip route get <adresse> from <source> iif <interface>` simule un paquet qui **traverse** la passerelle. Pour le NAT, `sudo conntrack -L -d <adresse>` (paquet `conntrack`) montre les adresses avant et après traduction.
</details>

<details><summary>Indice 3</summary>

Un point unique de défaillance n'est pas toujours une machine : un service (le DNS, le relais DHCP), un fichier de configuration non versionné, une clé privée non sauvegardée, une adresse WAN figée dans la route de `pve01`, ou un unique câble virtuel le sont aussi.
</details>

**Pour aller plus loin** (facultatif) : écris un petit script `outils/carto-l2.sh` (dans `plateforme/outils`) qui produit le tableau « VLAN → VNet → ports *tap* → VMID → nom » à partir de `bridge vlan show` et de `qm list`. Il resservira au palier 4.

---

### M07-E03 — Monter la maquette réseau par le code  `LAB` `★★`

> **Ticket PLAT-803** — *De : Karim Benali*
> On ne va pas apprendre BGP sur `gw01`. Je veux une maquette : deux *spines*, deux *leaves*, deux serveurs, un site distant, une VM de laboratoire, des liens point à point dédiés. Tout par le code : je veux pouvoir la détruire le vendredi et la reconstruire le lundi en dix minutes. Une contrainte : le jeton d'OpenTofu ne reçoit **pas** le droit d'administrer le SDN.

**Objectifs pédagogiques**
- Étendre le SDN de Proxmox (VNets de fabric) en mesurant l'effet sur le réseau de l'hyperviseur, et déléguer leur usage au jeton d'automatisation au plus juste.
- Décrire un environnement multi-cartes dans OpenTofu (`for_each`, blocs dynamiques, cloud-init par carte).
- Raccorder des VMs jetables aux services du socle : DNS (Kea et OpenTofu), réservations NetBox, accès SSH, inventaire Ansible par étiquettes.

**Prérequis** : M00-E28 (zone SDN `lab`) ; M05 (état distant chiffré, `charger-acces.sh`) ; M06-E13, E14 (NetBox et PowerDNS par OpenTofu), M06-E17 (DNS dynamique de Kea).
**Durée indicative** : 3 h 30.

**Contexte technique**
- VMs, cartes et adresses : tableaux « VMs de la maquette » et « Plan d'adressage » de l'introduction (`hap01` attendra le palier 2). Clone **complet** de l'image dorée `current`, pool `lab`, démarrage automatique désactivé, disque 10 Go sur `local-nvme`, cartes `virtio` sans pare-feu Proxmox.
- VNets : `vfab1` à `vfab8`, zone `lab`, VLAN 901 à 908, alias explicite (ex. « M07 spine01-leaf01 »).
- État : `envs/m07-maquette/` de `plateforme/infra`, mêmes fournisseurs et même backend que `envs/lab-m06` (clé `envs/m07-maquette/terraform.tfstate`), état chiffré.
- DNS : enregistrements A et PTR de `leaf01`, `srv01`, `srv02`, `lyo-gw01` et de `web-demo.par1.medisphere.internal` (10.10.99.240) par le module `enregistrement-dns` (v2.1.0) ; les autres VMs sont nommées par la mise à jour dynamique de Kea.
- NetBox : adresses 10.10.99.250 à .253 réservées (statut « Reserved »), 10.10.99.240 réservée avec le rôle « VRRP ».
- Ansible : groupes de l'inventaire Proxmox issus des étiquettes (`env_m07`, `m07_fabric`…) ; variables communes de la maquette dans `group_vars/env_m07/`.

> ⚠️ **Attention** : appliquer une modification du SDN (`pvesh set /cluster/sdn`) régénère `/etc/network/interfaces.d/sdn` sur `pve01` et recharge **toute** la configuration réseau de l'hôte (`ifreload -a`). Une erreur dans une autre partie de `/etc/network/interfaces` peut alors couper `pve01` du LAN. Avant d'appliquer : sauvegarde `/etc/network/interfaces` et `/etc/network/interfaces.d/sdn`, vérifie que les changements **en attente** ne contiennent que tes huit VNets, et garde un accès console à `pve01` (écran-clavier ou console de secours). Retour arrière : supprimer les VNets créés, réappliquer, comparer à la sauvegarde.

**Travail demandé**

*A. Les liens de fabric*

1. Lis la page « SDN » de la documentation Proxmox (zones VLAN, VNets). Réponds dans ton journal : pourquoi ces VNets n'ont-ils ni sous-réseau ni passerelle ? Pourquoi un VNet par lien plutôt qu'un seul VNet pour toute la fabric ? Pourquoi ne pas mettre la fabric sur `vsandbox` ?
2. Écris un script **idempotent** `outils/m07-vnets.sh` dans `plateforme/infra`, à lancer en root sur `pve01`, avec trois actions : `etat` (ce qui existe, ce qui est en attente), `creer` (crée ce qui manque, montre les changements en attente et **demande confirmation** avant d'appliquer), `supprimer` (même prudence). Il donne aussi au jeton `wb-tofu@pve!tofu` **et** à son utilisateur le rôle `PVESDNUser` sur chacun des huit VNets, et rien de plus.
3. Prends les sauvegardes de l'avertissement, lance `etat` puis `creer`. Après application, vérifie : les huit VNets existent et ne sont plus « en attente », `bridge vlan show` montre les VLAN 901 à 908 sur `vmbr1`, `pve01` répond toujours sur le LAN et `diff` entre l'ancien et le nouveau `/etc/network/interfaces.d/sdn` ne montre que des ajouts.

*B. L'environnement OpenTofu*

4. Crée `envs/m07-maquette/` : versions et backend, fournisseurs (`proxmox`, `netbox`, `powerdns`), chiffrement, variables. Décris les VMs dans **une seule** structure de données (une entrée par VM : VMID, ressources, adresse d'administration DHCP ou fixe, liste ordonnée de cartes de fabric avec leur VNet et leur adresse, étiquettes) et une seule ressource avec `for_each` : ajouter `hap01` au palier 2 doit tenir en une entrée de plus.
5. Ajoute les enregistrements DNS et les réservations NetBox du contexte technique. Les VMs de la maquette, elles, ne sont **pas** créées dans NetBox par cet état (elles y apparaîtront par la synchronisation de M06-E11) : justifie ce choix dans le README de l'environnement.
6. `tofu fmt`, `validate`, `plan` : relis le plan (combien de ressources ? quelles cartes sur quels VNets ?), puis `apply` depuis `adm01`. Publie le code par MR.

*C. Accès et configuration*

7. Ajoute à `~/.ssh/config` d'`adm01` un bloc pour les VMs de la maquette : connexion par le nom complet, compte `admin`, fichier `known_hosts` **dédié** à la maquette, acceptation des nouvelles clés seulement (jamais des clés **modifiées**). Justifie ce compromis dans ton journal (pense à M06-E19 et à la durée de vie de ces VMs). Vérifie `ssh net01 true`, `ssh leaf01 true`… pour les neuf VMs.
8. Dans `plateforme/ansible` : variables de connexion équivalentes pour Ansible (`group_vars/env_m07/`), outils de diagnostic de la maquette (`iperf3`, `traceroute`, `ethtool`) par la variable `base_paquets_role` du rôle `base`, playbook `playbooks/m07-maquette.yml` qui applique `base` aux VMs du groupe `env_m07`. Vérifie le graphe de l'inventaire (`--graph env_m07`, `--graph m07_fabric`), applique, puis rejoue : `changed=0`.
9. Vérifie la fabric au niveau 3 : chaque extrémité de chaque lien `/31` joint l'autre. Sur `pve01`, retrouve les ports *tap* des cartes de `leaf01` et leurs VLAN. Puis, depuis `spine01`, compare `ping 10.10.250.3` (`leaf02` sur `vfab2`, voisin direct) et `ping 10.10.250.5` (`leaf01` sur `vfab3`, qui n'est pas un voisin de `spine01`). Où part le second paquet (`ip route get`, `traceroute`) ? Explique : c'est le symptôme d'une route manquante que tu reverras souvent.
10. Chronomètre une reconstruction complète : `tofu destroy` (maquette seulement !), `apply`, playbook. Note la durée dans le README de l'environnement, avec la procédure.

**Critères de réussite**
- [ ] Les VNets `vfab1` à `vfab8` existent dans la zone `lab` (VLAN 901 à 908), sans changement en attente ; le jeton `wb-tofu` et son utilisateur ont `PVESDNUser` sur chacun ; le script `outils/m07-vnets.sh` est sur `main` de `plateforme/infra`.
- [ ] Les VMs 2070 à 2078 existent, avec le nom, les étiquettes (`env-m07` + étiquette de fonction), le pool `lab` et les cartes (VNet, ordre) du tableau ; elles ne démarrent pas avec `pve01` ; leur code est sur `main` (`envs/m07-maquette/`).
- [ ] `leaf01`, `srv01`, `srv02`, `lyo-gw01` et `web-demo` ont leurs A et PTR ; les VMs en DHCP sont résolues par leur nom ; 10.10.99.240 et 10.10.99.250-.253 sont réservées dans NetBox.
- [ ] `adm01` joint les neuf VMs en SSH par leur nom ; les outils de diagnostic y sont installés par Ansible.
- [ ] Les adresses de fabric sont en place et chaque lien `/31` est fonctionnel.

**Vérification** : `lab/bin/check 07 03`

<details><summary>Indice 1</summary>

L'API du SDN : `pvesh create /cluster/sdn/vnets --vnet … --zone … --tag … --alias …`, `pvesh get /cluster/sdn/vnets --pending 1`, `pvesh set /cluster/sdn` pour appliquer. Les droits : `pveum acl modify <chemin> --roles … --users …` et `--tokens …` ; le chemin d'un VNet est `/sdn/zones/<zone>/<vnet>` (tu l'as déjà utilisé en M05 pour `vsandbox`). Pense que, pour un jeton à privilèges séparés, le droit effectif est l'**intersection** de ceux du jeton et de l'utilisateur.
</details>

<details><summary>Indice 2</summary>

Dans le fournisseur `bpg/proxmox`, `network_device` et `initialization.ip_config` se répètent : le n-ième bloc `ip_config` correspond à la n-ième carte. Un bloc `dynamic` construit les deux à partir de la même liste ordonnée. Pour une VM en DHCP, l'adresse vaut `"dhcp"` et il n'y a pas de passerelle ; pour une carte de fabric, une adresse `/31` sans passerelle.
</details>

<details><summary>Indice 3</summary>

Dans `~/.ssh/config`, `HostName %h.par1.medisphere.internal` évite d'écrire neuf blocs ; `StrictHostKeyChecking accept-new` accepte une clé inconnue mais refuse une clé qui change ; `UserKnownHostsFile` désigne le fichier dédié. L'inventaire Proxmox déjà en place (M05-E23) range les VMs `env-mNN` et trouve leur adresse DHCP par l'agent QEMU : regarde comment il forme les noms de groupes à partir des étiquettes.
</details>

**Pour aller plus loin** (facultatif) : déclare les VNets eux-mêmes dans OpenTofu (ressources SDN du fournisseur `bpg/proxmox`) dans un état séparé, appliqué avec un jeton d'administration du SDN distinct de `wb-tofu`. Compare avec le script : traçabilité, risque, qui applique.

---

### M07-E04 — Bonding Linux : active-backup et LACP  `LAB` `★★`

> **Ticket PLAT-804** — *De : Karim Benali*
> Les serveurs Ceph auront deux cartes vers deux commutateurs. Avant de choisir le mode d'agrégation, je veux que tu l'aies vu fonctionner **et** tomber en panne. On n'a pas de vrais commutateurs et le pont de `pve01` ne laisse pas passer LACP : fais-le à l'intérieur de `net01`, entre deux espaces de noms. Et quand tu as compris, mets-le en code : on cassera ce labo plus tard.

**Objectifs pédagogiques**
- Construire un agrégat entre deux espaces de noms reliés par des paires veth, en mode `active-backup` puis `802.3ad`.
- Observer la négociation LACP (LACPDU, acteur et partenaire, agrégateur) et la répartition par hachage.
- Mesurer le temps de bascule et comprendre le rôle de `miimon`.
- Rendre le labo reproductible (rôle Ansible, unité systemd).

**Prérequis** : M07-E03.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Sur `net01` : espaces de noms `ns-srv` (le « serveur ») et `ns-sw` (le « commutateur »), deux paires veth `vsrv0`↔`vsw0` et `vsrv1`↔`vsw1`, un bond `bond0` de chaque côté : 172.31.70.1/24 (`ns-srv`), 172.31.70.2/24 (`ns-sw`).
- Rôle `bonding` (nouveau) : installe un script `/usr/local/sbin/m07-bond` (`demarrer`, `arreter`, `etat`) et une unité `m07-bond.service` qui construit le labo au démarrage ; paramètres (mode, `miimon`, `lacp_rate`, hachage) en variables. Playbook `playbooks/m07-net01.yml` (groupe `m07_labo`).
- Les parties A et B se font **à la main**, sur `net01` (VM jetable) : c'est de l'exploration.

**Travail demandé**

*A. Active-backup, à la main*

1. Crée les deux espaces de noms et les deux paires veth (une extrémité dans chaque espace). Crée `bond0` en mode `active-backup` avec `miimon 100` de chaque côté, asservis les veth, adresse et lève tout. Vérifie avec `ping`.
2. Lis `/proc/net/bonding/bond0` dans `ns-srv` : lien actif, état de chaque esclave, compteurs de pannes.
3. Lance un `ping -D -i 0.2` de `ns-srv` vers `ns-sw`, puis coupe le lien **actif** côté « commutateur » (`ip -n ns-sw link set vsw0 down`). Combien de réponses perdues ? Rétablis : le lien revient-il actif ? Pourquoi ? (Regarde l'option `primary`.)
4. Recommence avec `miimon 0` (pas de surveillance) : que se passe-t-il quand tu coupes le lien actif ?

*B. LACP, à la main*

5. Détruis les bonds et recrée-les en `802.3ad` (`miimon 100`, `lacp_rate fast`, `xmit_hash_policy layer3+4`). Observe la négociation : `tcpdump -e -n -i vsrv0 ether proto 0x8809` dans `ns-srv` (adresse de destination, fréquence). Dans `/proc/net/bonding/bond0`, relève l'identifiant d'agrégateur de chaque esclave, l'adresse système du partenaire, l'état (`actor/partner churn`, `port state`).
6. Répartition : lance `iperf3 -s` dans `ns-sw` puis, depuis `ns-srv`, un seul flux, puis quatre flux parallèles (`-P 4`). Compare les compteurs d'émission de `vsrv0` et `vsrv1` (`ip -s link`). Recommence avec `xmit_hash_policy layer2` : qu'observes-tu, et pourquoi ?
7. Désaccord de mode : passe `ns-sw` en `active-backup` en laissant `ns-srv` en `802.3ad`. Que dit `/proc/net/bonding/bond0` côté `ns-srv` ? Le `ping` passe-t-il encore ? Note la différence entre « ça marche » et « c'est sain ».

*C. En code*

8. Écris le rôle `bonding` et le playbook. Exigences : script et unité générés depuis les variables, labo reconstruit si les paramètres changent, `etat` lisible par un humain, second passage `changed=0`, `ansible-lint` profil `production` vert. Valeurs finales : `802.3ad`, `miimon 100`, `lacp_rate fast`, `layer3+4`.
9. Détruis tout ce que tu as fait à la main (`ip netns del`), applique le rôle, vérifie, puis redémarre `net01` : le labo doit revenir tout seul.

**Critères de réussite**
- [ ] Sur `net01`, `m07-bond.service` est activé et actif ; `ns-srv` et `ns-sw` existent, avec chacun un `bond0` en `802.3ad` (`miimon` 100, hachage `layer3+4`) de deux esclaves actifs.
- [ ] Les deux esclaves de chaque côté sont dans le **même** agrégateur, avec un partenaire LACP identifié (adresse système non nulle).
- [ ] `ns-srv` (172.31.70.1) joint `ns-sw` (172.31.70.2).
- [ ] Le rôle `bonding` et le playbook sont sur `main` de `plateforme/ansible` ; ton journal contient les mesures des étapes 3, 4, 6 et l'observation de l'étape 7.

**Vérification** : `lab/bin/check 07 04`

<details><summary>Indice 1</summary>

`ip link add vsrv0 netns ns-srv type veth peer name vsw0 netns ns-sw` crée une paire dont les deux bouts sont déjà à leur place. Un esclave doit être **baissé** avant d'être asservi (`ip link set … down`, puis `… master bond0`). Les paramètres d'un bond se donnent à la création (`ip link add bond0 type bond mode … miimon …`) ; certains ne se changent plus ensuite.
</details>

<details><summary>Indice 2</summary>

Mettre un bout d'une paire veth à `down` coupe la porteuse de l'autre bout : c'est ce que voit `miimon`. Sans surveillance (`miimon 0` et pas d'`arp_interval`), le bond ne sait rien. Pour LACP, un esclave qui ne reçoit plus de LACPDU sort de l'agrégateur, même si sa porteuse est présente.
</details>

<details><summary>Indice 3</summary>

Pour que le labo revienne au démarrage, une unité `Type=oneshot` avec `RemainAfterExit=yes` (démarrer à `ExecStart`, défaire à `ExecStop`) suffit. Dans `/proc/net/bonding/bond0`, regarde « Aggregator ID » sous chaque esclave et « Partner Mac Address » / « system mac address » dans la section 802.3ad.
</details>

**Pour aller plus loin** (facultatif) : essaie `arp_interval` et `arp_ip_target` à la place de `miimon` en `active-backup` : quelle panne détectent-ils que `miimon` ignore ? Lis la section « Configuring Bonding for Maximum Throughput » de la documentation du noyau.

---

### M07-E05 — Premiers pas avec Open vSwitch  `LAB` `★★`

> **Ticket PLAT-805** — *De : Karim Benali*
> OpenStack (module 10) repose sur OVN, donc sur Open vSwitch. Le jour où un réseau de projet ne passe pas, il faudra lire des tables OpenFlow. Commence par le plus simple : un commutateur OVS avec deux VLAN, des « machines » dedans, un routeur au bout d'un *trunk*. Puis regarde sous le capot.

**Objectifs pédagogiques**
- Créer un pont Open vSwitch avec des ports d'accès et un *trunk* ; router entre VLAN (*router on a stick*).
- Lire l'état d'OVS : `ovs-vsctl show`, table d'apprentissage, flux OpenFlow, trace d'un paquet.
- Comprendre la règle `NORMAL` et ajouter un flux OpenFlow de priorité supérieure.

**Prérequis** : M07-E03 ; M07-E04 conseillé (espaces de noms, veth).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Espace de noms | Port OVS (veth côté racine) | Mode | Adresse (`eth0` dans l'espace) |
|---|---|---|---|
| `ns-a` | `ovs-a` | accès VLAN 110 | 172.31.110.10/24, passerelle .1 |
| `ns-c` | `ovs-c` | accès VLAN 110 | 172.31.110.11/24, passerelle .1 |
| `ns-b` | `ovs-b` | accès VLAN 120 | 172.31.120.10/24, passerelle .1 |
| `ns-r` | `ovs-r` | *trunk* 110, 120 | `eth0.110` 172.31.110.1/24, `eth0.120` 172.31.120.1/24, routage activé |

- Pont : `br-lab` sur `net01` (paquet `openvswitch-switch` de Debian 13). Les VLAN 110 et 120 n'existent que dans `net01` : rien à voir avec ceux du lab.
- Rôle `ovs_labo` (nouveau) : installe OVS, un script `/usr/local/sbin/m07-ovs` (`demarrer`, `arreter`, `etat`) et une unité `m07-ovs.service` (après `openvswitch-switch.service`), ajouté au playbook `playbooks/m07-net01.yml`.
- Parties A à C à la main sur `net01` (exploration), partie D en code.

**Travail demandé**

*A. Le commutateur*

1. Installe OVS à la main pour explorer (`apt install openvswitch-switch`) ; observe les processus (`ovsdb-server`, `ovs-vswitchd`) et la base (`ovs-vsctl show`, `ovs-vsctl list Open_vSwitch`).
2. Crée `br-lab`, les quatre espaces de noms et leurs paires veth (le bout `eth0` dans l'espace, le bout `ovs-x` dans OVS), avec les modes du tableau. Configure `ns-r` en routeur (sous-interfaces VLAN, `net.ipv4.ip_forward`).
3. Vérifie : `ns-a` joint `ns-c` (même VLAN), `ns-a` joint `ns-b` (à travers `ns-r`), et `traceroute` le confirme. Capture sur `ovs-r` : les trames portent-elles une étiquette ? Et sur `ovs-a` ?

*B. Sous le capot*

4. Lis la table d'apprentissage (`ovs-appctl fdb/show br-lab`) : à quoi correspond la colonne VLAN ? Puis les flux OpenFlow (`ovs-ofctl dump-flows br-lab`) : combien y en a-t-il, et que fait l'action `NORMAL` ?
5. Trace un paquet sans l'envoyer : `ovs-appctl ofproto/trace br-lab in_port=ovs-a,dl_src=<MAC-A>,dl_dst=<MAC-C>` puis avec la MAC de destination de `ns-r`. Lis la décision.

*C. Une règle OpenFlow*

6. Ajoute un flux de priorité 200 qui jette l'ICMP de `ns-a` vers le réseau 172.31.120.0/24 (sans toucher au reste). Vérifie : `ping` de `ns-a` vers `ns-b` échoue, `curl` ou `nc` sur un port TCP passe encore, `ns-c` n'est pas concerné. Lis les compteurs du flux. Retire-le.
7. Réponds dans ton journal : pourquoi ce filtrage serait-il un mauvais choix à la place d'un pare-feu dans la vie réelle, mais exactement ce que fait OVN pour les groupes de sécurité ?

*D. En code*

8. Écris le rôle `ovs_labo` : OVS installé et actif, topologie du tableau construite par le script (idempotent : `--may-exist`, réglages de ports réappliqués), reconstruite au démarrage. Le flux OpenFlow de l'étape 6 n'en fait **pas** partie. Ajoute-le au playbook de `net01`, détruis ce que tu as fait à la main, applique, redémarre `net01` et revérifie.

**Critères de réussite**
- [ ] Sur `net01`, `openvswitch-switch` et `m07-ovs.service` sont activés et actifs ; `br-lab` a les quatre ports du tableau, avec les bons VLAN d'accès et le *trunk* 110,120 sur `ovs-r`.
- [ ] `ns-a` joint `ns-c` et `ns-b` ; `ns-b` joint `ns-a` ; la route de `ns-a` vers `ns-b` passe par 172.31.110.1.
- [ ] Aucun flux OpenFlow ajouté à la main ne reste (seul le flux `NORMAL` par défaut).
- [ ] Le rôle `ovs_labo` est sur `main` de `plateforme/ansible` ; ton journal contient la trace de l'étape 5 et les compteurs de l'étape 6.

**Vérification** : `lab/bin/check 07 05`

<details><summary>Indice 1</summary>

Un port d'accès : `ovs-vsctl add-port br-lab ovs-a tag=110`. Un *trunk* : `trunks=110,120` sur le port. `--may-exist` rend `add-br` et `add-port` idempotents, mais ne réapplique pas les réglages d'un port qui existe déjà : `ovs-vsctl set port …` le fait.
</details>

<details><summary>Indice 2</summary>

`ovs-ofctl add-flow br-lab "priority=200,icmp,nw_src=…,nw_dst=…/24,actions=drop"`. Attention : un paquet de `ns-a` vers `ns-b` traverse `br-lab` **deux fois** (vers `ns-r`, puis de `ns-r` vers `ns-b`) : quelles adresses IP portent-ils à chaque passage ? `ovs-ofctl del-flows br-lab "priority=200,…"` retire un flux précis ; `del-flows` sans filtre retire **tout**, y compris `NORMAL`.
</details>

<details><summary>Indice 3</summary>

L'état d'OVS (ponts, ports) est dans sa base `conf.db` : il survit au redémarrage. Les espaces de noms et les veth, non. Au démarrage, OVS recrée donc des ports qui ne correspondent à aucune interface (`ovs-vsctl show` affiche une erreur) jusqu'à ce que ton script recrée les veth.
</details>

**Pour aller plus loin** (facultatif) : lis le tutoriel « OVS Faucet » ou « OVS Conntrack » de la documentation d'Open vSwitch ; ajoute un flux qui utilise `ct()` pour autoriser seulement les connexions TCP établies depuis le VLAN 110.

---

### M07-E06 — Routage statique puis OSPF avec FRR  `LAB` `★★`

> **Ticket PLAT-806** — *De : Karim Benali*
> Les quatre routeurs de la maquette se voient deux à deux, rien de plus. Fais-les se joindre de boucle à boucle. D'abord en statique, pour sentir ce que ça coûte et ce que ça ne sait pas faire ; puis en OSPF. Le rôle `frr` que tu écris ici ira sur la bordure au palier 2 : écris-le comme tel, avec le dépôt officiel vérifié et un rechargement qui ne coupe pas les sessions.

**Objectifs pédagogiques**
- Installer FRR 10.7 depuis son dépôt officiel et comprendre son organisation (fichier `daemons`, configuration intégrée, `vtysh`, `zebra`).
- Écrire un rôle `frr` réutilisable : configuration générée depuis des données, validée avant installation, rechargée à chaud.
- Comparer routage statique et OSPF : effort, convergence, ECMP, coût des liens.

**Prérequis** : M07-E03 ; M04 (rôles, Molecule).
**Durée indicative** : 4 h.

**Contexte technique**
- Routeurs : `spine01`, `spine02`, `leaf01`, `leaf02` (groupe `m07_fabric`). Boucles (sur `lo`) et liens : introduction. `srv01`, `srv02` restent hors routage dans cet exercice.
- Dépôt et clé FRR : faits techniques de l'introduction ; paquets `frr` et `frr-pythontools` en 10.7, version épinglée.
- Rôle `frr` (nouveau) : dépôt (clé vérifiée par empreinte), paquets, démons activés (fichier `/etc/frr/daemons`), `frr.conf` produit depuis des variables structurées (interfaces, routes statiques, OSPF, BGP, *prefix-lists*, *route-maps*), validé avant d'être installé, rechargé par `frr-reload.py` (`systemctl reload frr`) ; routage IPv4 activé ; cohabitation avec `systemd-networkd` (voir indice 3). Scénario Molecule `frr` sur l'instance 2047.
- Playbook `playbooks/m07-fabric.yml` (groupe `m07_fabric`) ; données dans `host_vars/<routeur>/frr.yml`.

**Travail demandé**

*A. Découvrir FRR*

1. Sur `spine01`, à la main : installe FRR depuis le dépôt (vérifie l'empreinte de la clé), lis `/etc/frr/daemons`, démarre le service, liste les processus. Entre dans `vtysh` : `show version`, `show interface brief`, `show ip route`. Que représente chaque code de route ? Désinstalle ensuite proprement (`apt purge`) : la suite se fait par le rôle.

*B. Le rôle*

2. Écris le rôle `frr` et son scénario Molecule (qui applique une petite configuration OSPF et BGP sur une instance seule et vérifie que les démons tournent, que la configuration chargée est celle du fichier, et qu'une configuration invalide est refusée **sans** casser celle en place). Exigences :
   - un démon n'est activé que s'il est demandé ;
   - `frr.conf` n'est jamais installé s'il ne passe pas la validation de `vtysh` ;
   - un changement de configuration **recharge** FRR (sans redémarrer les démons), un changement du fichier `daemons` le redémarre ;
   - `frr.conf` n'est lisible que par `frr` (il contiendra des mots de passe) ;
   - second passage `changed=0`.

*C. Routage statique*

3. Donne à chaque routeur sa boucle (`interface lo`, `ip address …/32` dans FRR) et des routes **statiques** vers les trois autres boucles, au plus court (en passant par les spines pour aller d'un leaf à l'autre, sans utiliser `vfab7`). Applique par le playbook. Vérifie : `ping -I 10.10.255.11 10.10.255.12` depuis `leaf01`, `traceroute`.
4. Coupe `vfab1` (`ip link set eth1 down` sur `spine01`) : que devient le trafic `leaf01` → `spine01` (boucle) ? Où vont les paquets (`traceroute`) ? Rétablis. Combien de lignes de configuration faudrait-il pour 20 leaves et 4 spines ?

*D. OSPF*

5. Remplace les routes statiques par OSPF : zone 0, liens de fabric en `point-to-point`, toutes les autres interfaces passives (dont `eth0`, qui ne doit jamais parler OSPF sur le VLAN 99), boucles annoncées. Inclus `vfab7`. Applique.
6. Observe : voisinages (`show ip ospf neighbor`), base (`show ip ospf database`), routes (`show ip route ospf`). Par où `leaf01` joint-il `10.10.255.12` ? Donne à `vfab7` un coût de 30 des deux côtés : que devient la route ? Combien de chemins ? Vérifie dans le noyau (`ip route show 10.10.255.12`).
7. Convergence : lance `ping -D -i 0.2 -I 10.10.255.11 10.10.255.12` sur `leaf01`, puis coupe `vfab1` côté spine (`ip link set eth1 down` sur `spine01`). Combien de paquets perdus ? Rétablis. Recommence avec une coupe « silencieuse » : le lien reste *up* mais ne transporte plus rien. Simule-la sur `spine01` par une table nftables **temporaire** qui jette tout ce qui entre et sort par `eth1` (supprime-la ensuite). Combien de paquets perdus, cette fois ? Rapproche ces durées des minuteries OSPF (`show ip ospf interface eth1`).
8. Laisse la configuration finale : OSPF, coût 30 sur `vfab7`, aucune route statique. Publie le rôle, le scénario, les `host_vars` et le playbook par MR.

**Critères de réussite**
- [ ] FRR 10.7 du dépôt officiel tourne sur les quatre routeurs, avec `ospfd` actif, `bgpd` inactif ; `frr.conf` en `frr:frr` 640 ; le routage IPv4 est activé.
- [ ] Chaque routeur a sa boucle et quatre voisins OSPF au plus (spines : 2, leaves : 3) en état `Full` ; `eth0` n'est pas une interface OSPF active.
- [ ] `leaf01` joint la boucle de `leaf02` par **deux** chemins égaux (via les deux spines) ; aucune route statique ne reste.
- [ ] Le rôle `frr`, son scénario Molecule, les `host_vars` et le playbook sont sur `main` ; ton journal contient les mesures de convergence de l'étape 7.

**Vérification** : `lab/bin/check 07 06` — elle porte sur l'état de fin d'exercice (OSPF) : lance-la avant de commencer E07, qui remplace OSPF par BGP.

<details><summary>Indice 1</summary>

Le trousseau `keys.gpg` du dépôt FRR contient plusieurs clés : vérifie que l'empreinte attendue y figure (`gpg --show-keys --with-colons`) avant de le déposer dans `/usr/share/keyrings/`. Pour épingler une version, un fichier de `/etc/apt/preferences.d/` avec `Pin: version 10.7.*` vaut mieux qu'un numéro de paquet complet écrit dans le rôle.
</details>

<details><summary>Indice 2</summary>

`vtysh --dryrun --inputfile <fichier>` (`-C -f`) vérifie une configuration sans toucher aux démons : c'est exactement ce qu'attend l'option `validate` du module `template`. Le service `frr` de Debian recharge par `frrinit.sh reload`, qui appelle `frr-reload.py` (paquet `frr-pythontools`) : il calcule la différence et n'applique que ce qui change. `zebra`, `mgmtd`, `staticd` et `watchfrr` tournent toujours ; `/etc/frr/daemons` n'active que les autres.
</details>

<details><summary>Indice 3</summary>

L'image dorée utilise netplan et `systemd-networkd`. Par défaut, `networkd` supprime les routes et objets *nexthop* « étrangers » quand il reconfigure une interface : ceux que FRR a installés. Lis `networkd.conf(5)` : options `ManageForeignRoutes`, `ManageForeignRoutingPolicyRules`, `ManageForeignNextHops`, et un fichier de `/etc/systemd/networkd.conf.d/`.
</details>

**Pour aller plus loin** (facultatif) : ajoute BFD (`bfdd`) sur les liens de fabric et refais la mesure de l'étape 7 avec une coupe silencieuse. Lis la section « OSPF » du guide FRR sur `ip ospf dead-interval minimal`.

---

### M07-E07 — BGP avec FRR : sessions et politiques  `LAB` `★★`

> **Ticket PLAT-807** — *De : Karim Benali* — *Copie : Sophie Laurent*
> Kubernetes annoncera ses adresses de services en BGP à la bordure ; LYO1 aussi. Avant ça, je veux que tu saches monter une session eBGP, la sécuriser, et surtout **filtrer** : un voisin n'annonce que ce qu'il a le droit d'annoncer, on n'accepte que ce qu'on attend. Passe la fabric de la maquette d'OSPF à eBGP, comme dans un vrai datacenter. Sophie veut que les sessions soient authentifiées.

**Objectifs pédagogiques**
- Monter des sessions eBGP entre leaves et spines, avec *peer-groups*, identifiant de routeur et authentification TCP-MD5.
- Constater l'effet de `bgp ebgp-requires-policy` et écrire des politiques d'entrée et de sortie (*prefix-lists*, *route-maps*).
- Lire une table BGP (chemins, attributs, meilleur chemin, multichemin) et influencer la sélection (*local-preference*).

**Prérequis** : M07-E06 (rôle `frr`).
**Durée indicative** : 4 h.

**Contexte technique**
- AS : spines 65100 (les deux), `leaf01` 65101, `leaf02` 65102. Sessions sur les liens `/31` (adresses de l'introduction) : chaque leaf avec chaque spine ; **pas** de session sur `vfab7`. Identifiant de routeur = adresse de boucle.
- Ce que chacun annonce : un spine, sa boucle ; un leaf, sa boucle et le `/31` de son serveur (`vfab5`, `vfab6`).
- Mot de passe TCP-MD5 commun aux sessions de la fabric : `vault_m07_bgp_mdp_fabric`, Vault `lab`, dans `group_vars/m07_fabric/vault.yml`.
- OSPF disparaît à la fin de l'exercice (démon désactivé).

**Travail demandé**

*A. Une session, sans politique*

1. Étends le rôle `frr` si besoin (la structure BGP : AS, identifiant, *peer-groups*, voisins, réseaux annoncés, politiques par voisin ou groupe, `maximum-paths`). Configure d'abord une seule session, `leaf01` ↔ `spine01`, **sans** *route-map* (OSPF encore actif). Applique.
2. `show bgp summary` des deux côtés : état, colonnes « PfxRcd » et « PfxSnt ». Lis `show bgp neighbors 10.10.250.0` (sur `leaf01`) : capacités échangées, minuteries, raison de l'absence de routes. Explique ce que tu vois avec la RFC 8212.

*B. La fabric en eBGP*

3. Écris les politiques. Sur chaque leaf : en sortie, sa boucle et son lien serveur seulement ; en entrée, seulement des boucles de `10.10.255.0/24` et des `/31` de `10.10.250.0/24`. Sur chaque spine : en entrée, ce que chaque leaf a le droit d'annoncer (et rien d'autre) ; en sortie, les boucles et liens appris. Nomme les objets de façon lisible (`PL-…`, `RM-…`).
4. Configure les quatre sessions avec authentification, puis désactive OSPF. Applique. Vérifie : sessions établies, préfixes reçus et envoyés attendus, routes BGP dans le noyau (`ip route | grep bgp`).
5. Lis `show bgp ipv4 unicast 10.10.255.12/32` sur `leaf01` : combien de chemins, lesquels sont « *multipath* », quel est le meilleur et pourquoi ? Vérifie l'ECMP dans le noyau.
6. Sur `spine01`, cherche une route vers la boucle de `spine02` : il n'y en a pas. Explique (`show bgp ipv4 unicast neighbors 10.10.250.1 received-routes` ne marche que sous une condition : laquelle ?) Est-ce un problème pour la fabric ?

*C. Politiques en action*

7. Un leaf fuit : sur `leaf02`, ajoute **temporairement**, dans `vtysh`, l'annonce de `192.0.2.0/24` (route statique vers `Null0` + `network`). Que reçoit `spine01` ? Que voit `leaf01` ? Quelle politique t'a protégé ? Retire alors **temporairement** la *route-map* de sortie de `leaf02` : quelle politique te protège encore ? Remets la configuration par le playbook.
8. Préférence : fais en sorte que `leaf01` préfère `spine01` pour **sortir** vers `leaf02` (*local-preference* sur ce qu'il apprend de `spine01`). Vérifie la table BGP et le noyau (un seul chemin), puis mesure `traceroute`. Annule. Pourquoi ne pas faire ce choix en production dans une fabric ?
9. Authentification : change le mot de passe sur `spine02` seulement (à la main, dans `vtysh`). Que deviennent les sessions, et au bout de combien de temps ? Que dit le journal du noyau ou de FRR ? Remets la configuration par le playbook.
10. Configuration finale par le code : BGP seul, quatre sessions authentifiées, politiques, aucune préférence forcée. Publie par MR.

**Critères de réussite**
- [ ] Sur les quatre routeurs, `bgpd` est actif et `ospfd` inactif ; les spines sont en AS 65100, `leaf01` en 65101, `leaf02` en 65102, identifiant = boucle.
- [ ] Les quatre sessions leaf ↔ spine sont établies, authentifiées par mot de passe, avec des *route-maps* d'entrée et de sortie ; aucune session sur `vfab7`.
- [ ] Chaque leaf reçoit la boucle de l'autre leaf par **deux** chemins installés (ECMP) ; aucune route hors de 10.10.250.0/24 et 10.10.255.0/24 n'est apprise par BGP.
- [ ] Le mot de passe BGP est dans Vault (`lab`), jamais en clair dans le dépôt ; `frr.conf` reste en 640.
- [ ] Ton journal contient les réponses et observations des étapes 2, 5, 6, 7 et 9.

**Vérification** : `lab/bin/check 07 07`

<details><summary>Indice 1</summary>

Dans FRR, `neighbor <groupe> peer-group` puis `neighbor <adresse> peer-group <groupe>` évite de répéter `remote-as`, `password` et les politiques. Les politiques se posent dans `address-family ipv4 unicast` (`neighbor … route-map … in|out`). Une *prefix-list* avec `ge 32` n'accepte que les `/32` d'un réseau.
</details>

<details><summary>Indice 2</summary>

L'ordre de sélection de FRR est décrit dans « BGP » → « Route Selection » de sa documentation. Deux chemins sont candidats au multichemin s'ils sont égaux jusqu'à un certain critère : regarde lequel, et ce que change le fait que les deux spines aient le **même** AS. `received-routes` exige que le voisin garde une copie de ce qu'il a reçu avant filtrage (`soft-reconfiguration inbound`).
</details>

<details><summary>Indice 3</summary>

L'authentification TCP-MD5 est faite par le noyau : un segment sans la bonne signature est jeté **avant** d'atteindre `bgpd`, qui ne voit… rien, sinon l'expiration de son *hold timer*. Cherche dans `journalctl -k` ou `dmesg` un message « MD5 Hash mismatch ».
</details>

**Pour aller plus loin** (facultatif) : remplace TCP-MD5 par TCP-AO (RFC 5925) si ta version de FRR et ton noyau le permettent, et lis la position de la RFC 7454 (« BGP Operations and Security ») sur le filtrage des préfixes et l'authentification.

---

### M07-E08 — Une adresse virtuelle avec VRRP  `LAB` `★★`

> **Ticket PLAT-808** — *De : Nadia Roussel* — *Copie : Karim Benali*
> Quand on doublera `gw01`, je veux savoir à quoi m'attendre : combien de temps ça coupe, comment je vois qui est maître, ce qui se passe si le service tombe sans que la machine tombe. Monte-moi une démo : deux serveurs web derrière une adresse virtuelle, un qui tombe, l'autre qui reprend. Et je veux les transitions dans le journal, pas dans la tête de quelqu'un.

**Objectifs pédagogiques**
- Configurer keepalived (VRRP v3, annonces unicast) pour porter une VIP entre deux serveurs.
- Suivre la santé du service (*track_script*) et pas seulement celle de la machine ; tracer les transitions.
- Mesurer une bascule, observer l'ARP gratuit, comparer préemption et non-préemption.
- Écrire les rôles `keepalived` (pour le socle) et `nginx_web` (serveurs de démonstration).

**Prérequis** : M07-E03.
**Durée indicative** : 3 h.

**Contexte technique**
- `srv01` (10.10.99.252) et `srv02` (10.10.99.253), groupe `m07_web`, interface `eth0` sur `vsandbox`. VIP **10.10.99.240/24**, VRID **199** (le VRID 99 servira à la passerelle du VLAN 99 au palier 3), nom `web-demo.par1.medisphere.internal`. Priorités : `srv01` 150, `srv02` 100.
- `nginx_web` : nginx de Debian ; page d'accueil qui affiche le nom du serveur ; `GET /sante` répond `200` et `ok` (sert aux contrôles de keepalived, puis de HAProxy au palier 2).
- `keepalived` : VRRP v3 (pas d'authentification en v3), annonces unicast (source et pairs explicites), scripts de suivi exécutés sous un compte dédié non privilégié, script de transition qui écrit dans le journal (`logger`), configuration validée (`keepalived -t`) avant installation. Scénario Molecule `keepalived` sur les instances 2048 et 2049 (VIP d'essai 10.10.99.239, VRID 198).
- Playbook `playbooks/m07-web.yml`.

**Travail demandé**

*A. Les serveurs*

1. Écris le rôle `nginx_web` (site par défaut retiré, page et `/sante`, configuration validée avant rechargement) et applique-le aux deux serveurs. Vérifie depuis `adm01` : `curl http://srv01.par1.medisphere.internal/` et `/sante`.

*B. VRRP, d'abord à la main*

2. Sur `srv01` et `srv02`, installe keepalived et écris à la main une instance minimale **multicast** (sans source ni pairs). Démarre les deux. Qui est maître ? Capture sur `srv02` (`tcpdump -n -i eth0 vrrp`) : adresse de destination, VRID, priorité, intervalle. Sur `srv01`, `ip -br addr show eth0` : où est la VIP ?
3. Depuis `adm01`, `curl http://10.10.99.240/`. Puis lis le cache ARP de `gw01` (lecture seule) : `ip neigh show 10.10.99.240`. Quelle adresse MAC ? Est-ce celle de la VIP VRRP (`00:00:5e:00:01:c7`) ou celle de `srv01` ? (keepalived n'utilise pas de MAC virtuelle par défaut : lis l'option `use_vmac`.)
4. Arrête keepalived sur `srv01` en gardant une boucle `curl` (une requête toutes les 200 ms, horodatée) depuis `adm01`. Combien de requêtes échouent ? Relis le cache ARP de `gw01` : qui l'a mis à jour, et comment ? Redémarre `srv01` : la VIP revient-elle ? Pourquoi ?

*C. Le rôle et la configuration cible*

5. Écris le rôle `keepalived` et son scénario Molecule (deux instances : une seule porte la VIP d'essai, celle qui a la priorité la plus haute). Exigences : instances et scripts décrits en variables ; VRRP v3 ; unicast ; compte dédié pour les scripts et `enable_script_security` ; script de transition ; validation avant installation ; rechargement (pas redémarrage) à chaque changement ; second passage `changed=0`.
6. Configuration cible des serveurs : VIP 10.10.99.240, VRID 199, unicast entre .252 et .253, suivi de `GET /sante` en local (le serveur qui ne sert plus perd la VIP), préemption activée. Applique par le playbook (après avoir retiré ta configuration manuelle).
7. Bascule sur panne de service : arrête **nginx** (pas keepalived) sur `srv01`, avec la boucle `curl`. Mesure la coupure. Lis le journal de transition des deux serveurs (`journalctl -t keepalived-transition`). Relance nginx : la VIP revient, et avec quelle coupure ?
8. Préemption : passe en `nopreempt` (les deux instances en état initial `BACKUP`), refais l'étape 7. Qu'est-ce qui change ? Note dans ton journal l'avantage et le prix de chaque choix pour une **passerelle** (palier 3). Reviens à la configuration cible et publie par MR.

**Critères de réussite**
- [ ] nginx sert la page (nom du serveur) et `/sante` sur `srv01` et `srv02`.
- [ ] keepalived est actif sur les deux serveurs : VRRP v3, VRID 199, annonces unicast entre 10.10.99.252 et 10.10.99.253, suivi de `/sante`, scripts sous un compte non privilégié.
- [ ] La VIP 10.10.99.240 est sur **un seul** serveur, `srv01` quand les deux sont sains ; `curl http://web-demo.par1.medisphere.internal/` depuis `adm01` répond « srv01 ».
- [ ] Le journal de `srv02` montre au moins un passage à l'état maître (ta bascule de l'étape 7).
- [ ] Les rôles `keepalived` et `nginx_web`, le scénario Molecule et le playbook sont sur `main` ; ton journal contient les mesures des étapes 4, 7 et 8.

**Vérification** : `lab/bin/check 07 08`

<details><summary>Indice 1</summary>

Dans `keepalived.conf` : `global_defs` (identifiant, `vrrp_version`, `script_user`, `enable_script_security`), `vrrp_script` (commande, intervalle, nombre d'échecs et de succès), `vrrp_instance` (interface, `virtual_router_id`, priorité, `unicast_src_ip`, `unicast_peer { }`, `virtual_ipaddress { }`, `track_script { }`, `notify`). Le script `notify` reçoit en arguments le type, le nom de l'instance, l'état et la priorité.
</details>

<details><summary>Indice 2</summary>

Un `vrrp_script` sans `weight` met l'instance en état `FAULT` dès qu'il échoue : elle abandonne la VIP quelle que soit sa priorité. Avec un `weight` négatif, il retire des points à la priorité : c'est plus fin, mais il faut que la différence suffise à faire passer l'autre devant. Pour la commande du contrôle, `curl -fsS --max-time 2 -o /dev/null http://127.0.0.1/sante` renvoie un code non nul si la réponse n'est pas 2xx.
</details>

<details><summary>Indice 3</summary>

`nopreempt` n'est honoré que si l'état initial de l'instance est `BACKUP`. Pour mesurer une coupure, une boucle `while true; do date +%T.%N | cut -c1-12; curl -s -m 1 http://10.10.99.240/ || echo ÉCHEC; sleep 0.2; done` suffit ; compte les lignes « ÉCHEC ».
</details>

**Pour aller plus loin** (facultatif) : lis la page de manuel `keepalived.conf(5)` sur `vrrp_sync_group` et `track_interface` : à quoi serviront-ils pour une passerelle qui a une patte dans chaque VLAN (E25) ? Essaie `use_vmac` sur la maquette et observe ce que voit `gw01`.

---

### M07-E09 — Questions : L2, L3, agrégation, redondance  `Q` `★★`

> **Ticket PLAT-809** — *De : Karim Benali*
> Avant d'attaquer la bordure et les répartiteurs, je veux savoir si tu as compris ce que tu as monté, pas seulement si ça marche. Réponds par écrit, en t'appuyant sur ce que tu as observé sur la maquette.

**Objectifs pédagogiques**
- Expliquer les choix faits au palier 1 et leurs conséquences pour le socle.
- Relier les observations (captures, tables, mesures) aux mécanismes des protocoles.

**Prérequis** : M07-E02 à M07-E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 12 questions.

1. Le SDN de Proxmox a créé des VNets `vfab1` à `vfab8` sur `vmbr1`. Explique pourquoi une trame émise par `spine01` sur `eth1` ne peut atteindre que `leaf01`, en décrivant ce qui se passe dans `pve01`. Que se passerait-il si `vfab1` et `vfab2` avaient le même VLAN ?
2. Pourquoi le LACP a-t-il dû être pratiqué entre deux espaces de noms dans `net01`, et pas entre deux VMs ? Quelle est l'adresse en cause, et pourquoi la norme veut-elle qu'un pont ne la relaie pas ?
3. *(QCM)* En E04, un seul flux `iperf3` entre les deux espaces de noms a utilisé un seul esclave du bond, quatre flux en ont utilisé deux. Avec `xmit_hash_policy layer2`, même quatre flux n'en utilisent qu'un. Pourquoi ?
   - A. En `layer2`, le hachage ne porte que sur les adresses MAC, identiques pour tous les flux entre ces deux machines
   - B. En `layer2`, LACP désactive le second esclave
   - C. `iperf3` ouvre ses flux sur le même port source
   - D. Le mode `layer2` n'est pas compatible avec les paires veth
4. En E05, le flux OpenFlow qui jetait l'ICMP de `ns-a` vers 172.31.120.0/24 a-t-il vu le paquet lors de son **premier** passage dans `br-lab` (de `ns-a` vers `ns-r`), du second, ou des deux ? Pourquoi ?
5. Le rôle `frr` recharge la configuration par `frr-reload.py` plutôt que de redémarrer le service. Qu'est-ce que cela change pour les sessions BGP et les voisinages OSPF ? Dans quel cas un redémarrage reste-t-il obligatoire ?
6. Pourquoi a-t-il fallu dire à `systemd-networkd` de ne pas gérer les routes « étrangères » ? Décris la panne qu'on aurait eue sinon, et dans quelles circonstances elle serait apparue (indice : pas tout de suite).
7. En E06, la coupure d'un lien par `ip link set down` a été rattrapée en moins d'une seconde, mais une coupure « silencieuse » prend bien plus longtemps. Explique les deux durées. Quelle est la parade standard, et pourquoi ne remplace-t-elle pas la détection par la porteuse ?
8. *(QCM)* En E07, `leaf01` installe deux chemins vers la boucle de `leaf02`. Que faudrait-il changer pour garder l'ECMP si les deux spines avaient des AS **différents** (65100 et 65110) ?
   - A. Rien : l'ECMP ne dépend pas des AS
   - B. `bgp bestpath as-path multipath-relax` sur les leaves
   - C. `maximum-paths ibgp 2`
   - D. Mettre les deux leaves dans le même AS
9. Pourquoi la politique de sortie d'un leaf doit-elle n'annoncer **que** ses propres préfixes ? Décris ce qui pourrait arriver à la fabric (et au trafic entre les spines) si `leaf01` réannonçait à `spine02` ce qu'il apprend de `spine01`.
10. L'authentification TCP-MD5 protège contre quoi ? Contre quoi ne protège-t-elle pas ? Qu'apporterait en plus, ou à la place, `ttl-security` (GTSM, RFC 5082) sur des sessions entre voisins directs ?
11. En E08, après la bascule, `gw01` a mis à jour son cache ARP pour 10.10.99.240 sans que rien ne lui soit configuré. Comment ? Que se passerait-il si ce message était perdu ? Pourquoi keepalived le répète-t-il (`vrrp_garp_master_refresh`) ?
12. Nadia veut la **non-préemption** sur les passerelles (E25), Karim la **préemption**. Donne un argument solide pour chacun, puis ta recommandation pour la bordure de MédiSphère et la condition qui la rendrait sûre.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions, en citant au moins trois observations faites sur la maquette (sortie de commande, capture, mesure).
- [ ] Tu as noté chaque réponse avec la grille du corrigé et listé ce qui reste flou.

<details><summary>Indice</summary>

Pour chaque question, demande-toi **qui** prend la décision (le pont, le bond, le noyau, `bgpd`, keepalived), **avec quelle information**, et **comment il apprend qu'elle a changé**. La plupart des réponses en découlent.
</details>

**Pour aller plus loin** (facultatif) : transforme les questions 6, 7 et 12 en entrées du registre des risques de l'équipe (risque, probabilité, impact, mesure en place, mesure à venir) : Nadia en aura besoin pour le runbook de bascule de la bordure (RB-071).
