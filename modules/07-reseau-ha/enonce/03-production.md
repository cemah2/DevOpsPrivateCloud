# Module 07 — Palier 3 : Production

Les paliers 1 et 2 t'ont donné les briques : VRRP sur une maquette, FRR sur la bordure, des répartiteurs `lb01`/`lb02` qui publient GitLab et NetBox, des réseaux de stockage en *jumbo frames*, l'agence de Lyon raccordée par `wg2`. Mais le lab tout entier passe toujours par **une seule** machine : `gw01`. Quand elle redémarre, plus de DNS pour les VLANs routés, plus de sauvegardes vers PAR2, plus de VPN d'administration, plus de Lyon. Claire Morel veut une bordure sans point unique de défaillance **avant** de brancher Ceph (module 08) : deux passerelles, des adresses virtuelles partout, des tunnels et des connexions qui suivent la passerelle active, une supervision qui voit tout cela, et des bascules **mesurées**, pas supposées. Sophie Laurent veut une matrice des flux qui dise la vérité sur les deux passerelles et sur la DMZ. Ce palier fait passer la bordure et les points d'entrée en production.

> ⚠️ **Rappel — ce palier touche le cœur du lab.** `gw01` route **tous** les VLANs, porte le NAT, le VPN d'administration (`wg1`), le tunnel vers PAR2 (`wg0`), le tunnel de Lyon (`wg2`), le relais DHCP et le serveur de temps. Une erreur sur `gw01` coupe tout, y compris le chemin par lequel tu la répares. Avant **chaque** intervention sur `gw01` ou `gw02` :
> 1. **instantané** des deux passerelles : `ms-snapshot --prefix avant-m07 1000 1009` (M02-E11), supprimé une fois le changement validé ;
> 2. **accès de secours vérifié** : console de la VM dans l'interface web de `pve01` (noVNC) ou `qm terminal <VMID>` si la console série est configurée, **et** SSH sur l'adresse WAN de la passerelle depuis `pve01` ou le LAN maison (`ssh admin@<IP-GW01-WAN>`, règle de secours de M00-E10 ; l'adresse WAN propre de chaque passerelle ne change jamais dans ce palier) ;
> 3. une session SSH **ouverte** sur la passerelle par l'adresse WAN, qui ne dépend d'aucun VLAN du lab ;
> 4. la commande de **retour arrière** écrite dans la fiche de changement, testée à blanc si possible ;
> 5. un créneau où personne d'autre n'a besoin du lab (pas de sauvegarde PBS en cours : regarde les tâches de `pbs01`).
>
> Le filet anti-coupure du rôle `pare_feu` (M04-E17) protège les changements de pare-feu, **pas** les changements d'adresses ni de keepalived : pour eux, ton filet est la procédure.

**Chemin imposé** (introduction du module) : toute nouvelle VM est créée par **OpenTofu** (état `socle` de `plateforme/infra`), toute configuration passe par un **rôle Ansible** appliqué par le **pipeline** de `plateforme/ansible`, toute adresse est dans **NetBox**, tout nom dans **PowerDNS**, tout certificat vient de **step-ca** par ACME. À partir de M07-E24, la matrice des flux est **commune** aux deux passerelles. Tout nouveau secret (clés WireGuard, mots de passe des pages de statistiques…) est en Vault (`critique` pour ce qui permet d'usurper la bordure) et inscrit au registre des secrets.

**Hôtes de ce palier** : `gw01` (1000), `gw02` (1009, créé en E24), `lb01`/`lb02` (1010/1011, M07-E12), et, pour les essais, la maquette 2070-2079 (en particulier `leaf01` pour le BGP, `lyo-gw01`/`lyo-pc01` pour Lyon, `srv01`/`srv02` en E34). Aucune autre VM n'est créée.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 07 XX`). Elles lisent les passerelles en SSH (`admin` + `sudo -n`) **par leur nom** : à partir de E25, `gw01.par1.medisphere.internal` désigne 10.10.10.2 et `gw02` 10.10.10.3, jamais une adresse virtuelle.

**Ordre conseillé**

```
E24 ─ E25 ─ E26 ─ E27 ─┬─ E29 ─ E32
                       └─ E30
E28 (indépendant, après E13) ─ E29
E31 (après E27)     E33 (en dernier)     E34 (après E28)
```

E25 et E26 se préparent par une **fiche de changement** et se jouent dans un créneau calme : compte une demi-journée chacun, préparation comprise. Durée indicative du palier : 22 à 28 heures.

---

### M07-E24 — Une seconde passerelle : `gw02`  `LAB` `★★★`

> **Ticket PLAT-850** — *De : Karim Benali*
> Samedi, `gw01` a redémarré pour un noyau : six minutes sans rien. Les pipelines ont échoué, la sauvegarde de nuit de `git01` est partie en erreur, Nadia a été réveillée par douze alertes, et Lyon a appelé.
> Avant de parler de VRRP, il faut une **deuxième** passerelle qui sache faire exactement tout ce que fait la première : mêmes VLANs, même pare-feu, même NAT, même routage. Et je veux qu'elle soit **identique par construction** : pas un `gw01` bis bricolé à côté. Elle n'a le droit de router pour personne tant qu'on n'a pas décidé comment basculer.

**Objectifs pédagogiques**
- Créer un hôte du socle à deux cartes (WAN et trunk) par OpenTofu, alors que le module `vm-debian` ne prévoit qu'une carte.
- Mettre la configuration réseau des passerelles en code (rôle `routeur_reseau`) en tenant compte de deux piles différentes (`ifupdown` sur `gw01`, netplan sur `gw02`).
- Rendre la matrice des flux **commune** à deux pare-feu et le prouver.
- Prouver qu'une passerelle route, filtre et traduit correctement **sans** qu'aucun client ne l'utilise encore.

**Prérequis** : M07-E15 (MTU du trunk), M07-E16 (FRR sur `gw01`), M07-E18 (`wg2`), M06-E21 (NTS), M06-E25 (rôle `relais_dhcp`), M04-E17 (rôle `pare_feu`), M05 (état `socle`), M06-E13 (NetBox et OpenTofu).
**Durée indicative** : 3 h 30.

**Contexte technique**
- `gw02` : VMID **1009**, 1 vCPU, 1 Go, disque 10 Go sur `local-nvme`, clone **complet** de l'image dorée `current`, pool `lab`, étiquettes `socle` et `role-routeur`, démarrage automatique (ordre 1, comme `gw01`). Deux cartes virtio : `net0` sur **`vmbr0`** (WAN, adresse fixe `<IP-GW02-WAN>` du LAN maison, passerelle `<IP-BOX>`) et `net1` sur **`vmbr1` sans étiquette** (trunk, MTU 9000 comme `ens19` de `gw01` depuis M07-E15). L'image dorée nomme ces cartes `eth0` et `eth1` (configuration réseau cloud-init de Proxmox, M03) ; or la matrice des flux commune, keepalived et conntrackd désignent les interfaces **par leur nom** : `gw02` doit les appeler `ens18` (WAN) et `ens19` (trunk), comme `gw01`.
- `<IP-GW02-WAN>` : adresse **libre** du LAN maison, hors de la plage DHCP de la box, choisie dans l'introduction du module (`lab/inventaire-local.md`) ; `<IP-BOX>` : la box (M00-E10) ; `<MASQUE>` : longueur du préfixe du LAN maison.
- Adresses de `gw02` dans le lab : **`.3`** sur chaque VLAN routé (10, 20, 30, 40, 50, 52, 60, 70, 99), **aucune** adresse `.1`. Nom `gw02.par1.medisphere.internal` → 10.10.10.3 (et son PTR). Dans NetBox : la VM, une interface par sous-interface VLAN, ses neuf adresses.
- `gw01` est hors IaC (ADR-0051) ; `gw02` est dans l'état `socle`. Le module `vm-debian` (une carte, une adresse allouée dans un préfixe) ne convient pas : décris la VM directement dans `socle/gw02.tf` avec les ressources du fournisseur `bpg/proxmox` et du fournisseur NetBox, comme le fait le module.
- Le jeton `wb-tofu` doit pouvoir rattacher une carte aux ponts **hors SDN** `vmbr0` et `vmbr1` : sur Proxmox VE 8 et 9, c'est le privilège `SDN.Use` sur `/sdn/zones/localnetwork/<pont>` (à vérifier dans la documentation « User Management » de ta version). N'élargis pas les droits au-delà.
- Image dorée : netplan + systemd-networkd (M03) ; `gw01` (installé depuis l'ISO en M00) : `ifupdown`, `/etc/network/interfaces`. Le nouveau rôle **`routeur_reseau`** gère les deux : sous-interfaces VLAN, adresses, MTU, `net.ipv4.ip_forward`, routes de garde. Il **n'applique jamais** un changement d'adresse en redémarrant le réseau d'une passerelle en service.
- Groupe d'inventaire `role_routeur` (`gw01`, `gw02`, par l'étiquette `role-routeur`). La matrice des flux quitte `host_vars/gw01/pare_feu.yml` pour **`group_vars/role_routeur/pare_feu.yml`** : une seule matrice, deux pare-feu.
- Rôles appliqués à `gw02` : `base`, `ssh_durci`, `routeur_reseau`, `pare_feu`, `chrony_serveur` (certificat NTS au nom de `gw02` et de **ses** adresses), `frr` (AS 65000, identifiant de routeur 10.10.10.3, session avec `leaf01` de la maquette si elle tourne). Le relais DHCP n'est **pas** activé sur `gw02` dans cet exercice.

> ⚠️ **Attention** : (1) `gw02` partage le VLAN 99 et le LAN maison avec `gw01` : une adresse `.1` posée par erreur sur `gw02` crée un conflit d'adresse **immédiat** avec la passerelle de tout un VLAN (vérifie le plan avant chaque `apply` et le rendu du rôle avant de l'appliquer) ; (2) le passage de la matrice dans `group_vars` modifie le pare-feu de `gw01` : le rendu de `/etc/nftables.conf` sur `gw01` doit être **identique** avant et après (preuve par `--check --diff` à `changed=0`) ; (3) cloud-init de l'image dorée peut configurer la seconde carte en DHCP au premier démarrage : ce n'est pas grave tant qu'elle ne porte aucune adresse de VLAN, mais le rôle doit reprendre la main (et le renommage des cartes ne se fait qu'au démarrage : `gw02` redémarre une fois, avant d'être en service).

**Travail demandé**
1. **Réservation.** Dans NetBox, réserve les neuf adresses `.3` et décris `gw02` (cluster `pve01`, étiquettes, interfaces `ens18`, `ens19`, `ens19.<VLAN>`). Choisis si NetBox est rempli à la main ou par OpenTofu, et écris ton choix dans la MR (rappel : ADR-0060).
2. **La VM.** Écris `socle/gw02.tf` : deux cartes, MTU du trunk, cloud-init qui ne configure **que** le WAN, démarrage automatique, `prevent_destroy`, enregistrements A et PTR de `gw02` par le module `enregistrement-dns` (M06-E14). Accorde au rôle de `wb-tofu` exactement le privilège manquant (`pveum`), puis fais relire le plan : aucune autre VM ne doit bouger. Applique par le pipeline.
3. **Le rôle `routeur_reseau`.** Une liste de VLAN routés, une adresse par passerelle et par VLAN (variables d'hôte), le MTU par VLAN (9000 pour 30 ; 1500 pour les autres ; `ens19` à 9000), `ip_forward`, et des **routes de garde** : `unreachable` à métrique élevée pour 10.20.0.0/16, 10.30.0.0/16 et 10.255.0.0/16 (un réseau joint par un tunnel ne doit jamais partir vers Internet quand le tunnel est absent). Gabarit `ifupdown` pour `gw01` (il doit rendre **exactement** la configuration actuelle de `gw01`), netplan pour `gw02` (avec le renommage des cartes en `ens18`/`ens19`). Prouve sur `gw01` : `--check --diff` ne montre que des différences de forme que tu sais expliquer, et le rôle n'a rien redémarré.
4. **Une seule matrice.** Déplace la matrice dans `group_vars/role_routeur/pare_feu.yml`. Les règles qui désignaient une adresse **propre** à `gw01` (réponses DHCP adressées au `giaddr` 10.10.99.1, par exemple) sont réécrites pour valoir sur les deux passerelles. Applique à `gw01` (rendu identique) puis à `gw02`.
5. **Les services.** Applique à `gw02` les rôles listés. `gw02` doit avoir son propre certificat NTS (ses noms et adresses) et servir l'heure ; FRR doit établir sa session avec `leaf01` (ajoute `gw02` comme second voisin dans la configuration de `leaf01`, par le code de la maquette).
6. **Preuves sans client.** Sans toucher à la passerelle par défaut de quiconque :
   - depuis `adm01`, ajoute une route **temporaire** vers une VM du VLAN 99 par 10.10.10.3, connecte-toi en SSH à cette VM, et prouve avec `tcpdump` sur `gw02` que le trafic la traverse ; retire la route ;
   - depuis une VM jetable du VLAN 99, ajoute une route **hôte** temporaire vers une adresse Internet par 10.10.99.3 et prouve que la sortie est traduite par `gw02` (adresse source vue côté WAN) ; retire-la ;
   - compare le jeu de règles chargé sur les deux passerelles (`nft list ruleset`) : seules des différences que tu sais justifier sont admises (idéalement aucune).
7. **Code et documentation.** Playbook `playbooks/routeurs.yml` (groupe `role_routeur`, une passerelle à la fois, `gw02` d'abord) ; inventaire du socle (`docs/socle/inventaire.md`) à jour.

**Critères de réussite**
- [ ] La VM 1009 `gw02` tourne, dans le pool `lab`, étiquetée `socle` et `role-routeur`, démarrage automatique ; `net0` sur `vmbr0`, `net1` sur `vmbr1` sans étiquette, MTU 9000 ; elle est décrite dans l'état `socle` (`socle/gw02.tf`).
- [ ] `gw02.par1.medisphere.internal` → 10.10.10.3 (et le PTR) ; NetBox décrit `gw02` avec ses neuf adresses `.3`.
- [ ] Les cartes de `gw02` s'appellent `ens18` (WAN) et `ens19` (trunk) ; `gw02` porte `.3` sur les neuf VLAN routés et **aucune** adresse `.1` ; `gw01` porte toujours toutes les `.1` ; `ip_forward` est actif ; les routes de garde existent sur les deux passerelles.
- [ ] La matrice des flux est dans `group_vars/role_routeur/pare_feu.yml` ; les deux passerelles chargent le même jeu de règles.
- [ ] `gw02` sert l'heure (NTS) et sa session BGP avec `leaf01` est établie (si la maquette tourne).
- [ ] Le relais DHCP n'est pas actif sur `gw02`.

**Vérification** : `lab/bin/check 07 24`

<details><summary>Indice 1</summary>

Une ressource `proxmox_virtual_environment_vm` accepte plusieurs blocs `network_device` (l'ordre donne `net0`, `net1`) et un bloc `initialization` avec autant de `ip_config` que de cartes **à configurer** : regarde ce qui se passe pour une carte sans `ip_config`. Dans NetBox, une interface de VM peut avoir une interface parente (`parent`) : c'est ainsi qu'on modélise `ens19.20` sous `ens19`.
</details>

<details><summary>Indice 2</summary>

Pour que `gw01` ne redémarre jamais son réseau, sépare deux choses dans le rôle : le **fichier** (qui fait foi au prochain démarrage) et l'**état courant** (adresses posées une par une avec une commande idempotente comme `ip address replace`). Un gestionnaire (*handler*) qui ferait `systemctl restart networking` serait une coupure de tout le lab à chaque modification.
</details>

<details><summary>Indice 3</summary>

Pour comparer deux jeux de règles, `nft -s list ruleset` retire les compteurs ; `diff` sur les deux sorties fait le reste. Si des différences apparaissent, cherche les valeurs qui viennent de `host_vars` ou de faits Ansible (`ansible_default_ipv4`, nom d'hôte) dans le gabarit.
</details>

**Pour aller plus loin** (facultatif) : importer `gw01` dans l'état `socle` (et réviser ADR-0051) ; un module OpenTofu `vm-routeur` dans `plateforme/tofu-modules` ; [privilèges SDN de Proxmox VE](https://pve.proxmox.com/pve-docs/chapter-pveum.html), [netplan : VLAN](https://netplan.readthedocs.io/en/stable/netplan-yaml/#properties-for-device-type-vlans), [`interfaces(5)`](https://manpages.debian.org/trixie/ifupdown/interfaces.5.en.html), [ressource `proxmox_virtual_environment_vm`](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm).

---

### M07-E25 — VRRP sur les passerelles du lab  `LAB` `★★★★`

> **Ticket PLAT-851** — *De : Claire Morel* — *Copie : Nadia Roussel, Sophie Laurent*
> `gw02` est prête. Maintenant on bascule le lab sur des passerelles virtuelles : `.1` sur chaque VLAN devient une adresse **VRRP** portée par la passerelle active, `gw01` passe en `.2`, `gw02` reste en `.3`. Aucune VM ne doit changer de configuration.
> C'est le changement le plus risqué du module : je veux une **fiche de changement CHG-855** relue avant de commencer, un VLAN à la fois en commençant par la sandbox, des coupures **mesurées** et annoncées, et un retour arrière écrit pour chaque étape. Si quelque chose ne se passe pas comme prévu, on s'arrête et on revient.

**Objectifs pédagogiques**
- Configurer keepalived pour plusieurs instances VRRP v3 en unicast, regroupées dans un groupe de synchronisation, avec des scripts de transition.
- Migrer une passerelle en service vers une adresse virtuelle **sans reconfigurer les clients**, VLAN par VLAN, avec une coupure bornée et mesurée.
- Comprendre ce que la bascule change pour tout ce qui dépendait de l'adresse `.1` de `gw01` : DNS, inventaire, BGP, relais DHCP, NTP, certificats, pare-feu.
- Constater le routage asymétrique d'une migration à moitié faite, et savoir pourquoi on ne teste pas la bascule avant la fin.

**Prérequis** : M07-E24, M07-E08 (VRRP sur la maquette, rôle `keepalived`), M07-E12 (keepalived sur `lb01`/`lb02`), M07-E16 (FRR de bordure).
**Durée indicative** : 5 h, dont la fiche de changement.

**Contexte technique**
- Plan (PLAN §4.9) : pour chaque VLAN routé V ∈ {10, 20, 30, 40, 50, 52, 60, 70, 99} : VIP `10.10.V.1/24`, **VRID = V**, `gw01` = `10.10.V.2` priorité **150**, `gw02` = `10.10.V.3` priorité **100**, VRRP **version 3**, annonces **unicast** (`unicast_src_ip` = adresse propre, `unicast_peer` = l'autre passerelle), intervalle d'annonce 1 s. Toutes les instances dans **un** `vrrp_sync_group` (`BORDURE`), qui suivra aussi l'instance WAN en E26. Pas de `vrrp_strict` (incompatible avec l'unicast et ajouterait ses propres règles de filtrage).
- Préemption : à toi de choisir entre préemption (avec ou sans `preempt_delay`) et `nopreempt`, et de le justifier dans la fiche (combien de bascules par incident ? que se passe-t-il au retour de `gw01` ?). Rappel de la documentation : `nopreempt` et `preempt_delay` exigent un état initial `BACKUP`.
- Script de transition : `/usr/local/sbin/bordure-transition`, appelé par le groupe (`notify`) ; dans cet exercice, il journalise la transition (`logger -t bordure`) et écrit l'état courant dans `/run/bordure/etat` (`MASTER`, `BACKUP` ou `FAULT`, lisible par tous). Il sera enrichi en E26 (tunnels) et E27 (connexions). Rôle **`bordure`** ; keepalived reste le rôle `keepalived` de M07-E08, étendu.
- Le filtre `regle_nft` de la collection `medisphere.socle` (M04-E18) ne connaît que `tcp`, `udp`, `tcp_udp`, `icmp` : VRRP est le protocole IP **112**. Étends le filtre (et ses tests unitaires) plutôt que d'écrire une règle à la main.
- Ce qui dépend aujourd'hui de « `gw01` = `.1` » (à traiter **avant** de déplacer `.1`) : l'enregistrement DNS `gw01` (10.10.10.1) et son PTR, NetBox, l'inventaire Ansible et la connexion SSH, le voisin BGP de `leaf01` (10.10.99.1) et la source de la session côté `gw01`, la source des requêtes relayées par `dnsmasq` (`giaddr`), la liste des serveurs NTP des clients et les SAN du certificat NTS (`.1` de chaque VLAN, M06-E21). Pour NTP, la décision du module : les clients interrogent **les deux** passerelles par leurs adresses propres (`.2` et `.3`), et chaque certificat NTS ne porte que les noms et adresses de sa passerelle. Le relais DHCP de chaque passerelle relaie avec **sa** propre adresse.
- NetBox 4.6 modélise VRRP : groupes FHRP (`ipam/fhrp-groups/`, protocole `vrrp3`, identifiant de groupe = VRID), adresse virtuelle de rôle `vrrp` rattachée au groupe, groupe rattaché aux interfaces des deux passerelles avec leur priorité.
- `net.ipv4.conf.all.promote_secondaries` doit valoir 1 sur `gw01` : sans lui, retirer la première adresse d'un sous-réseau retire **aussi** les suivantes.

> ⚠️ **Attention — changement à haut risque.**
> - Un VLAN dont la VIP n'est portée par personne n'a plus de passerelle ; un VLAN dont la VIP est portée par les deux (*split brain*) a deux passerelles qui se disputent les tables ARP. Ne configure **jamais** l'instance d'un VLAN sur `gw02` avant que `gw01` ne porte la VIP de ce VLAN par keepalived.
> - Tant que tous les VLAN ne sont pas migrés, **ne teste pas la bascule** : une partie du trafic passerait par `gw02` et le retour par `gw01` (routage asymétrique, connexions jetées par le suivi d'état). L'étape 7 te le fait constater, sur la sandbox seulement.
> - Le VLAN 10 (MGMT) est celui d'`adm01` : migre-le en dernier, depuis la session SSH **WAN** ouverte sur `gw01`, avec la console Proxmox prête.
> - Un groupe de synchronisation change l'état de **toutes** ses instances. Avant d'ajouter une instance à un groupe dont les autres membres sont déjà maîtres, lis (ou essaie sur la maquette, `srv01`/`srv02`) ce que fait keepalived **au rechargement** dans ce cas : une migration « VLAN par VLAN » ne doit couper que le VLAN migré. Note aussi que `keepalived -t` n'accepte pas un groupe d'une seule instance.
> - Retour arrière d'un VLAN (à écrire dans la fiche, testé sur le VLAN 99) : retirer l'instance du VLAN des deux passerelles, reposer `.1` en statique sur `gw01`, et revenir au rendu précédent des rôles.

**Travail demandé**
1. **Lecture.** Dans `keepalived.conf(5)` et la RFC 5798 : calcule le *Master_Down_Interval* pour les priorités 150 et 100 avec un intervalle d'1 s ; explique ce que fait un groupe de synchronisation, ce que reçoit un script `notify` en arguments, ce qu'est l'*accept mode* et pourquoi il compte pour une passerelle qui doit répondre au ping sur sa VIP.
2. **La fiche CHG-855.** Dans `docs/socle/changements/` : objectif, tableau VLAN/VRID/VIP/adresses/priorités, choix de préemption justifié, ordre de migration (99 en premier, 10 en dernier, justifie l'ordre des autres), prérequis (instantanés, accès de secours, `promote_secondaries`), étapes avec, pour chacune, la vérification et le retour arrière, critères d'arrêt (par exemple : plus de 10 s de perte sur un VLAN), communication (qui prévenir, quand). Fais-la relire (MR sur `plateforme/medisphere`).
3. **Préparation sans effet visible.**
   - `gw01` reçoit `.2` en **plus** de `.1` sur chaque VLAN (rôle `routeur_reseau`, adresse secondaire, aucun redémarrage).
   - DNS et NetBox : `gw01` → 10.10.10.2, `gw02` → 10.10.10.3 ; groupes FHRP et VIP dans NetBox. Vérifie qu'Ansible joint `gw01` à sa nouvelle adresse, et que la clé d'hôte est toujours reconnue (certificat d'hôte SSH : quels principaux contient-il ?).
   - BGP : la configuration de `leaf01` vise `10.10.99.2` et `10.10.99.3` ; côté passerelles, la session vers `leaf01` part de l'adresse propre (`update-source`).
   - Relais DHCP (`relais_dhcp`) avec l'adresse propre de chaque passerelle ; NTP des clients (rôle `base`) vers `.2` et `.3` ; certificats NTS réémis.
   - Matrice : VRRP entre `.2` et `.3` sur chaque VLAN routé (filtre `regle_nft` étendu). Appliquée aux deux passerelles.
4. **Les rôles.** Étends `keepalived` (instances générées depuis la liste des VLAN migrés, une variable par passerelle : priorité, adresses propres), écris `bordure` (script de transition, `/run/bordure/etat`), valide chaque rendu par `keepalived -t` avant tout rechargement. Le rôle `keepalived` ne doit **jamais** redémarrer le service (un redémarrage fait tomber toutes les instances) : rechargement seulement.
5. **VLAN 99, à la main du pipeline.** Lance une mesure de perte depuis une VM du VLAN 99 vers une adresse d'un autre VLAN (`ping -i 0.2`, ou `fping` en continu) et une autre depuis `adm01` vers cette VM. Puis : sur `gw01`, l'instance VRRP du VLAN 99 entre en service et `.1` statique disparaît (rendu des rôles appliqué par le pipeline, `--limit gw01`) ; mesure la coupure ; vérifie que la VIP est sur `gw01` **avec la même adresse MAC qu'avant** (`ip neigh` sur la VM). Puis l'instance du VLAN 99 sur `gw02` : elle doit rester `BACKUP`. Note les chiffres dans la fiche.
6. **Les autres VLAN.** Un par un, dans l'ordre de la fiche, avec la même mesure. Entre deux VLAN : `dig`, `ping`, SSH, pipeline GitLab et un `apt update` sur une VM du VLAN migré.
7. **Ce qu'il ne faut pas faire.** Avant de migrer le dernier VLAN, sur la **sandbox seulement** : arrête l'instance VRRP du VLAN 99 sur `gw01` (ou baisse sa priorité), constate que `gw02` prend la VIP 99, puis teste un SSH depuis `adm01` vers une VM du VLAN 99 et une sortie Internet depuis cette VM. Explique avec `conntrack -L` et `tcpdump` sur les deux passerelles ce qui marche, ce qui ne marche pas, et pourquoi. Reviens à l'état nominal.
8. **La bascule complète.** Tous les VLAN migrés et le groupe `BORDURE` constitué sur les deux passerelles : arrête keepalived sur `gw01` ; mesure la perte sur trois flux (VLAN 99 → Internet, `adm01` → VM du VLAN 99, `adm01` → `pve01`). Explique pourquoi le dernier ne revient pas, et ce qu'E26 devra régler. Reviens à `gw01` maître selon ta politique de préemption.
9. **Clôture.** Compte rendu dans la fiche CHG-855 (heures, pertes mesurées par VLAN, écarts au plan), instantanés supprimés, ébauche de `docs/socle/runbooks/RB-071-bascule-bordure.md` (bascule manuelle planifiée et retour), complétée en E26.

**Critères de réussite**
- [ ] Sur chacun des neuf VLAN routés : `gw01` porte `.2`, `gw02` porte `.3`, la VIP `.1` est portée par **une seule** passerelle ; aucune `.1` n'est configurée en statique.
- [ ] keepalived : VRRP v3, unicast, VRID = numéro de VLAN, priorités 150/100, neuf instances dans le groupe `BORDURE` ; les deux passerelles sont dans le même état pour toutes les instances ; `/run/bordure/etat` reflète l'état.
- [ ] La matrice autorise VRRP entre les passerelles sur chaque VLAN, et rien d'autre de nouveau ; les deux jeux de règles sont identiques.
- [ ] `gw01.par1.medisphere.internal` → 10.10.10.2, `gw02` → 10.10.10.3 ; NetBox contient neuf groupes FHRP `vrrp3`.
- [ ] Le relais DHCP de chaque passerelle relaie avec son adresse propre ; les clients synchronisent leur heure sur `.2` et `.3` ; les sessions BGP de `leaf01` avec 10.10.99.2 et 10.10.99.3 sont établies (si la maquette tourne).
- [ ] La fiche CHG-855 (avec les pertes mesurées) et l'ébauche de RB-071 sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 07 25`

<details><summary>Indice 1</summary>

Un état initial `BACKUP` sans pair qui annonce devient maître après *Master_Down_Interval* = 3 × intervalle + *skew*, avec *skew* = ((256 − priorité) × intervalle) / 256. C'est la durée de la coupure quand `.1` statique disparaît et que l'instance démarre : calcule-la avant de la mesurer. Et pose-toi la question : pourquoi ne pas laisser keepalived « reprendre » une adresse déjà présente sur l'interface ?
</details>

<details><summary>Indice 2</summary>

L'adresse MAC de la VIP est celle de l'interface de la passerelle qui la porte (pas de `use_vmac`) : tant que `gw01` reste maître, les caches ARP des clients restent justes, et l'ARP gratuit envoyé par keepalived ne change rien. C'est au moment où `gw02` prend la main que les ARP gratuits comptent : regarde `garp_master_delay` et `garp_master_refresh`.
</details>

<details><summary>Indice 3</summary>

Pour le routage asymétrique : sur une passerelle, `conntrack -L` montre les flux qu'elle a vus naître. Un paquet de réponse qui arrive sur la passerelle qui n'a jamais vu la question est, selon le protocole et `nf_conntrack_tcp_loose`, soit pris comme un nouveau flux, soit `invalid`, et la chaîne `forward` décide de son sort. Et un flux traduit (NAT) par `gw01` ne peut pas revenir par `gw02` : l'adresse de sortie n'est pas la même.
</details>

**Pour aller plus loin** (facultatif) : `advert_int` inférieur à la seconde en VRRP v3 et son coût ; BFD pour détecter plus vite la panne d'un lien ; [`keepalived.conf(5)`](https://www.keepalived.org/manpage.html), [RFC 5798 (VRRP v3)](https://www.rfc-editor.org/rfc/rfc5798), [groupes FHRP dans NetBox](https://netboxlabs.com/docs/netbox/models/ipam/fhrpgroup/).

---

### M07-E26 — Bordure redondante côté WAN et VPN  `LIBRE` `★★★★`

> **Ticket PLAT-852** — *De : Nadia Roussel*
> Test de vendredi : `gw01` éteinte, les VLANs ont bien basculé sur `gw02`… et c'est tout. Plus d'accès à `pve01` depuis `adm01`, plus de sauvegardes vers PAR2, plus de VPN d'administration, Lyon coupé, GitLab injoignable depuis le LAN maison. La moitié de la bordure est encore attachée à **l'adresse** de `gw01`.
> Je veux que la bordure entière suive la passerelle active : côté WAN, côté tunnels, côté NAT. Et une procédure de bascule manuelle que je peux jouer seule à 3 h du matin.

**Objectifs pédagogiques**
- Étendre la redondance au WAN : adresse virtuelle sur le LAN maison, traduction d'adresses et redirections cohérentes avec elle.
- Faire suivre le maître à des services qui ne sont pas des adresses : interfaces WireGuard, sessions BGP de Lyon.
- Gérer des secrets identiques sur deux hôtes (clés WireGuard) proprement.
- Raisonner sur les dépendances externes de la bordure (`pve01`, `pbs01`, ton poste, la box) et les modifier sans perdre la main.

**Prérequis** : M07-E25, M07-E13 (redirection WAN 443), M07-E18 et E19 (`wg2`, BGP de Lyon), M00-E16 et E21 (`wg1`, `wg0`).
**Durée indicative** : 5 h.

**Contraintes**
- Côté WAN : VIP `<IP-GW-WAN-VIP>` (adresse libre du LAN maison, choisie dans l'introduction du module), **VRID 250**, mêmes priorités, dans le groupe `BORDURE` (même précaution qu'en E25 pour ajouter une instance à un groupe déjà maître). L'adresse WAN propre de chaque passerelle (`<IP-GW01-WAN>`, `<IP-GW02-WAN>`) reste en place : c'est ton accès de secours.
- Tout ce qui, à l'extérieur du lab, vise la bordure vise la **VIP WAN** : route statique de `pve01` vers 10.10.0.0/16, 10.20.0.0/16 et 10.255.1.0/24 (PLAN §4.9), extrémité `wg0` de `pbs01`, extrémité `wg1` de ton poste, redirection HTTPS vers les répartiteurs (M07-E13). Côté Lyon, l'extrémité reste 10.10.99.1, désormais virtuelle.
- Traduction sortante : le lab sort vers Internet derrière **une adresse qui ne change pas** quand la passerelle active change. Justifie ton choix (traduction vers une adresse fixe ou masquage sur l'adresse de l'interface) au regard des connexions en cours et de E27.
- Tunnels `wg0`, `wg1`, `wg2` : **mêmes clés** sur les deux passerelles, en Vault `critique`, déployées par le rôle `wireguard` (celui de M07-E18, étendu aux trois tunnels) ; interfaces **montées sur le maître seulement**, par le script de transition, et **démontées** sur la passerelle de secours. Le trafic des tunnels que la passerelle émet elle-même doit partir de l'adresse que le pair attend.
- Un réseau joint par un tunnel ne doit jamais sortir vers Internet quand le tunnel est démonté (routes de garde de E24).
- BGP de Lyon (65000 ↔ 65030) : configuration identique sur les deux passerelles ; la session se rétablit seule sur le nouveau maître.
- Changements sur `pve01` et `pbs01` : ⚠️ ce sont des hôtes **hors pool `lab`** (réseau de l'hyperviseur, pare-feu et tunnel du site de sauvegarde). Chaque changement est préparé avec sa commande de retour arrière, appliqué hors des fenêtres de sauvegarde, avec un accès direct à l'hôte (console physique ou SSH par le LAN maison pour `pve01`, iLO ou écran pour `hp01`). Rien n'est fait à `pve01` qui puisse couper ses VMs personnelles.
- Livrables : rôles et inventaire à jour (rôles `wireguard`, `bordure`, `keepalived`, matrice), registre des secrets, fiche de changement **CHG-856**, runbook **RB-071** « bascule manuelle de la bordure » complet (bascule planifiée, retour, vérifications, que faire si la VIP est sur les deux ou sur aucune), matrice des flux documentaire à jour.

**Critères de réussite**
- [ ] La VIP WAN est portée par une seule passerelle, la même que les VIP des VLAN ; l'instance WAN (VRID 250) est dans le groupe `BORDURE`.
- [ ] Les interfaces `wg0`, `wg1`, `wg2` existent sur le maître et pas sur la passerelle de secours ; leurs clés publiques sont identiques d'une passerelle à l'autre ; les clés privées ne sont dans aucun fichier versionné en clair.
- [ ] Le lab sort vers Internet avec l'adresse source `<IP-GW-WAN-VIP>` ; la redirection HTTPS du WAN vers 10.10.70.200 vise la VIP WAN.
- [ ] `pve01` route 10.10.0.0/16 par la VIP WAN ; `pbs01` vise la VIP WAN ; ton poste aussi.
- [ ] Après une bascule complète vers `gw02` : `adm01` joint `pve01` et `pbs01`, un client VPN se reconnecte, Lyon joint PAR1 et la session BGP de Lyon est établie, GitLab répond depuis le LAN maison ; puis retour sur `gw01` par RB-071.
- [ ] CHG-856 et RB-071 sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 07 26`

<details><summary>Indice 1</summary>

Une passerelle qui **répond** à un pair WireGuard le fait depuis l'adresse sur laquelle elle a reçu son dernier paquet ; mais une passerelle qui **initie** (poignée de main, *keepalive*) le fait depuis l'adresse que le noyau choisit pour la route vers le pair : son adresse propre. Après une bascule, c'est le nouveau maître qui initie. Que voit alors le pare-feu de `pbs01` ? Deux solutions : élargir ce que le pair accepte, ou maîtriser l'adresse source dans la chaîne `postrouting`.
</details>

<details><summary>Indice 2</summary>

Le script `notify` d'un groupe reçoit `GROUP`, le nom du groupe, l'état cible et la priorité. Monter un tunnel, c'est démarrer `wg-quick@wgN` : décide si les unités doivent être `enabled` au démarrage de la VM (indice : qui doit les démarrer, et que se passe-t-il si la passerelle de secours démarre la première ?).
</details>

<details><summary>Indice 3</summary>

Pour `pve01`, la route persistante vit dans la configuration réseau de l'hôte : change-la d'abord **à chaud** (un remplacement de route, pas une suppression suivie d'un ajout), vérifie depuis `adm01`, puis seulement rends-la persistante. Le retour arrière est le même remplacement, vers `<IP-GW01-WAN>`.
</details>

**Pour aller plus loin** (facultatif) : un second lien WAN (deux box) et le suivi de la joignabilité amont par `track_script` ; [WireGuard : *roaming* et adresses sources](https://www.wireguard.com/), [`wg-quick(8)`](https://manpages.debian.org/trixie/wireguard-tools/wg-quick.8.en.html), [NAT dans nftables](https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)).

---

### M07-E27 — Basculer sans couper les connexions : conntrackd  `LAB` `★★★`

> **Ticket PLAT-853** — *De : Karim Benali*
> La bascule marche. Mais pendant le test, la session `psql` de Julien sur la base de test et le `git clone` de 2 Go de Lucas sont morts, alors que la perte n'a duré que quatre secondes. Le routage a basculé, la **mémoire** du pare-feu non : `gw02` n'avait jamais entendu parler de ces connexions.
> Je veux que `gw01` et `gw02` partagent leur table de suivi des connexions, et je veux des mesures avant/après.

**Objectifs pédagogiques**
- Comprendre ce que contient la table de suivi des connexions (conntrack) d'un pare-feu à états et de NAT, et ce qui arrive aux flux quand elle n'existe pas sur la passerelle qui prend la main.
- Configurer `conntrackd` en mode FTFW sur un lien choisi, et l'articuler avec les transitions VRRP.
- Mesurer l'effet sur différents types de flux, et décider des réglages du suivi de connexions qui vont avec.

**Prérequis** : M07-E26.
**Durée indicative** : 3 h 30.

**Contexte technique**
- Paquet `conntrackd` (Debian 13), configuration `/etc/conntrackd/conntrackd.conf`, exemples dans `/usr/share/doc/conntrackd/examples/sync/` (en particulier `ftfw/conntrackd.conf`, `primary-backup.sh` et `keepalived.conf`). Nouveau rôle **`conntrackd`**.
- Mode **FTFW** (fiable, avec acquittements), transport **UDP** unicast, port **3780**. Lien de synchronisation : le **VLAN 10 (MGMT)**, de 10.10.10.2 à 10.10.10.3 et inversement. Justifie ce choix dans la MR (alternatives : VLAN dédié, VLAN 99, multicast) : qui d'autre est sur ce VLAN, que transporte la synchronisation, que se passe-t-il si ce VLAN tombe ?
- Les transitions passent par le script `bordure-transition` (rôle `bordure`) : il enchaîne les commandes de `conntrackd` dans l'ordre de `primary-backup.sh` pour chaque état.
- Réglage du noyau en jeu : `net.netfilter.nf_conntrack_tcp_loose` (défaut 1 : une connexion TCP vue en cours de route est « reprise »). Lis sa description dans la documentation du noyau (`nf_conntrack-sysctl`).
- Flux de mesure (au moins) : une session SSH interactive de `adm01` vers une VM du VLAN 99 ; un téléchargement long depuis une VM du VLAN 99 vers Internet (traduit) ; une connexion HTTPS longue à GitLab **depuis le LAN maison** (redirigée par la VIP WAN).

> ⚠️ **Attention** : `conntrackd -c` (validation du cache externe) injecte des milliers d'entrées dans le noyau : sur une passerelle qui n'est **pas** maître, c'est un état faux. Le script de transition ne doit l'appeler qu'en devenant maître. Teste le rôle sur `gw02` d'abord, avec `gw01` maître.

**Travail demandé**
1. **Le problème, mesuré.** Sans `conntrackd`, avec le réglage par défaut du noyau, lance les trois flux et une bascule planifiée (RB-071). Pour chaque flux : survit-il ? combien de temps de blanc ? Recommence avec `nf_conntrack_tcp_loose=0` sur les deux passerelles. Explique les différences avec `conntrack -L` et `conntrack -E` sur la passerelle qui prend la main.
2. **Lecture.** Dans `conntrackd.conf(5)` et les exemples : différence entre FTFW, ALARM et NOTRACK ; caches interne et externe ; rôle de chaque commande du script (`-c`, `-f`, `-R`, `-B`, `-t`, `-n`) ; ce que fait le filtre `Address Ignore`, quelles adresses d'une entrée il compare (d'origine ou traduites ?), et donc quelles adresses tu y mets : y mettre les VIP ferait-il perdre les flux traduits vers la VIP WAN ? Appuie ta réponse sur une preuve (`conntrackd -e`, ou le code de conntrack-tools).
3. **Le rôle.** Écris `conntrackd` (configuration générée depuis les adresses du lien et la liste des adresses propres, service activé, redémarré seulement quand sa configuration change), branche-le dans `bordure-transition`, ouvre le flux de synchronisation dans la matrice (et seulement entre les deux passerelles). Applique à `gw02`, puis `gw01`.
4. **La preuve.** `conntrackd -s` sur les deux passerelles, `conntrackd -i` (cache interne du maître) et `-e` (cache externe du secondaire) : retrouve un flux traduit de l'étape 1 dans le cache externe de `gw02`. Rejoue les mesures de l'étape 1 avec `conntrackd`, avec `nf_conntrack_tcp_loose=0`.
5. **Décision.** Choisis la valeur de `nf_conntrack_tcp_loose` pour les passerelles (rôle `routeur_reseau`), justifie-la (sécurité contre comportement si la synchronisation échoue), et écris dans RB-071 ce qu'on vérifie de `conntrackd` avant une bascule planifiée.

**Critères de réussite**
- [ ] `conntrackd` est actif sur les deux passerelles, en mode FTFW, en UDP entre 10.10.10.2 et 10.10.10.3, port 3780 ; la configuration est générée par le rôle `conntrackd`.
- [ ] La matrice autorise UDP 3780 entre les deux passerelles sur le VLAN 10, et seulement entre elles.
- [ ] Le script de transition appelle `conntrackd` dans l'ordre attendu ; le cache externe de la passerelle de secours n'est pas vide.
- [ ] `nf_conntrack_tcp_loose` a la même valeur sur les deux passerelles, fixée par le code.
- [ ] Les mesures avant/après (trois flux, deux réglages) sont consignées dans `docs/socle/tests/bascules.md` (section conntrackd).

**Vérification** : `lab/bin/check 07 27`

<details><summary>Indice 1</summary>

Une connexion traduite n'a de sens que pour la passerelle qui a choisi la traduction : le port source choisi par la traduction est dans l'entrée conntrack, pas dans le paquet d'origine. Avec une traduction vers une adresse **fixe** (la VIP WAN), l'entrée synchronisée reste valable sur l'autre passerelle ; avec un masquage sur l'adresse de l'interface, elle ne le serait pas.
</details>

<details><summary>Indice 2</summary>

Le cache externe d'un nœud contient les flux **de l'autre** ; il n'est pas dans le noyau tant qu'on ne l'y injecte pas. `conntrackd -s` affiche des compteurs de messages et d'erreurs : un nombre de messages reçus qui n'augmente pas pendant que du trafic traverse le maître, c'est la synchronisation qui ne passe pas (filtrage, adresses).
</details>

**Pour aller plus loin** (facultatif) : synchroniser aussi les *expectations* (`ExpectationSync`) ; `DisableExternalCache` et son coût ; [conntrack-tools](https://conntrack-tools.netfilter.org/manual.html), [`nf_conntrack` sysctl](https://docs.kernel.org/networking/nf_conntrack-sysctl.html).

---

### M07-E28 — HAProxy en production  `LAB` `★★★`

> **Ticket SEC-857** — *De : Sophie Laurent* — *Copie : Karim Benali, Nadia Roussel*
> Les répartiteurs publient GitLab et NetBox depuis M07-E13, et c'est par eux que passeront bientôt toutes les entrées de la plateforme. Mon scan de lundi : TLS 1.2 minimum, bien, mais des suites sans confidentialité persistante encore acceptées ; pas de HSTS ; des en-têtes qui annoncent les versions des serveurs ; aucune limite sur les pages de connexion. Nadia ajoute : la page de statistiques n'écoute qu'en local, elle ne voit jamais l'état du répartiteur de **secours** ; les journaux ne permettent pas de suivre une requête jusqu'au serveur ; et pendant l'incident de mardi, GitLab renvoyait des 502 depuis vingt secondes qu'il était toujours « UP ».
> Je veux des répartiteurs qu'on peut montrer à l'auditeur, et Karim veut pouvoir recharger la configuration en pleine journée sans couper personne.

**Objectifs pédagogiques**
- Appliquer une politique TLS et des en-têtes de sécurité sur un point d'entrée, et la vérifier de l'extérieur.
- Rendre la détection des pannes de serveurs plus fine que les seuls contrôles périodiques.
- Journaliser de façon exploitable (identifiant de requête, temps, codes) et ouvrir les statistiques à la supervision sans les ouvrir à tout le monde.
- Recharger sans coupure, retirer un serveur proprement, et lier la VIP à la santé de HAProxy.

**Prérequis** : M07-E10, M07-E12, M07-E13 (rôle `haproxy`, répartiteurs, publication), M07-E22 (RB-070), M06-E27 (politique de certification).
**Durée indicative** : 3 h 30.

**Contexte technique**
- `lb01` (10.10.70.10) et `lb02` (10.10.70.11), HAProxy **3.2** (haproxy.debian.net), VIP 10.10.70.200 (VRID 170). Rôle `haproxy` de M07-E10 : `global` et `defaults` dans le gabarit du rôle, sections propres dans `haproxy_sections` (`group_vars/role_lb/haproxy.yml`, version M07-E13) ; chaque rendu est validé par `haproxy -c` avant d'être posé, puis HAProxy est **rechargé**.
- Politique TLS (reprise par la politique de certification) : TLS **1.2 minimum**, suites « intermédiaires » du guide Mozilla (confidentialité persistante, chiffrement authentifié), en-tête `Strict-Transport-Security` (durée d'un an, sans `preload` : nom interne), HTTP redirigé vers HTTPS.
- Santé : les contrôles applicatifs de M07-E13 (`/-/readiness` de GitLab, `/login/` de NetBox, TLS vérifié, SNI) restent ; ce qui manque est la prise en compte des erreurs des **vraies** requêtes entre deux contrôles.
- Journalisation : vers le journal de systemd (déjà en place), avec un identifiant unique par requête transmis aux serveurs (`X-Request-ID`).
- Statistiques et métriques : écouteur sur l'adresse **propre** de chaque répartiteur (pas la VIP : on veut voir les deux), port **8404**, HTTPS avec le certificat `lb` de M07-E12 (il porte le nom du répartiteur), joignable depuis le VLAN MGMT seulement, authentification par une liste d'utilisateurs aux mots de passe **hachés** (compte `supervision` en lecture, compte `admin`) ; `/stats` (page) et `/metrics` (format Prometheus, service intégré de HAProxy, pour le module 21). Empreintes en Vault `critique` ; les identifiants du compte `supervision` aussi dans `~/.config/workbook/haproxy-stats.env` (600, `HAPROXY_STATS_USER`, `HAPROXY_STATS_PASSWORD`) pour les vérifications et le module 21.
- API d'exécution (*Runtime API*) : socket UNIX local `/run/haproxy/admin.sock` (emplacement du paquet Debian), niveau `admin`, mode 660 (root et groupe `haproxy`).
- Limitation de débit : sur les pages de connexion de GitLab et de NetBox, au plus 20 requêtes par 10 s et par adresse source (réponse 429 au-delà).

> ⚠️ **Attention** : les répartiteurs portent l'accès à GitLab et à NetBox pour tout le monde, y compris pour les pipelines. Travaille d'abord sur le répartiteur de **secours** (celui qui ne porte pas 10.10.70.200), vérifie, bascule la VIP (RB-070), puis l'autre. Une configuration refusée par `haproxy -c` ne doit jamais atteindre le service.

**Travail demandé**
1. **État des lieux.** Depuis `adm01` : versions de TLS et suites acceptées par `gitlab.par1.medisphere.internal:443` (attention : un client OpenSSL récent refuse lui-même les vieilles versions ; préfère un outil qui énumère, comme `nmap --script ssl-enum-ciphers`), en-têtes renvoyés, réponse du port 80, ce que voit un client du VLAN MGMT sur 10.10.70.10:8404 aujourd'hui. Note les écarts à la politique.
2. **TLS et en-têtes.** Applique la politique dans `global` (suites côté clients et côté serveurs) et sur l'écouteur public ; ajoute HSTS ; retire de la réponse ce qui révèle la version des serveurs.
3. **Santé.** Relis les contrôles de M07-E13 et fais compter les erreurs des vraies requêtes (lis `observe`, `error-limit` et `on-error` dans le manuel). Prouve, en heures creuses et annoncé, qu'un GitLab dont l'application est arrêtée (`gitlab-ctl stop puma` sur `git01`) passe `DOWN`, que HAProxy sert une page 503 propre (page fournie par le rôle), puis remets en service.
4. **Journaux.** Identifiant de requête dans le format du journal et transmis aux serveurs ; retrouve une requête précise dans `journalctl -u haproxy` de `lb01` **et** dans les journaux de `nbx01` grâce à `X-Request-ID`.
5. **Administration.** Écouteur 8404 (statistiques, métriques), liste d'utilisateurs hachés, filtrage par adresse ; socket d'API d'exécution avec reprise des sockets d'écoute au rechargement. Ajoute le flux 8404 (MGMT → DMZ) s'il manque dans la matrice. Depuis `adm01` : `curl` sans identifiants → 401 ; avec le compte `supervision` → page CSV ; depuis `runner01` → refusé.
6. **Exploitation sans coupure.** Pendant une boucle de requêtes depuis `adm01` (une toutes les 100 ms, codes comptés), recharge HAProxy : zéro erreur attendue. Mets le serveur NetBox en `drain` puis `maint` par l'API d'exécution, observe, remets-le en `ready`. Vérifie que le suivi keepalived des répartiteurs (M07-E12) fait bien partir la VIP si HAProxy s'arrête.
7. **Limitation.** Prouve le 429 sur `/login/` de NetBox au-delà de 20 requêtes en 10 s, et l'absence d'effet sur les autres chemins.
8. **Documentation.** Complète RB-070 (rechargement, `drain`, lecture des statistiques) et la politique de certification (politique TLS des points d'entrée).

**Critères de réussite**
- [ ] `gitlab.par1.medisphere.internal` et `netbox.par1.medisphere.internal` répondent en HTTPS par la VIP, avec l'en-tête HSTS ; le port 80 redirige vers HTTPS ; les suites TLS sont fixées dans la configuration.
- [ ] Les serveurs `git01` et `nbx01` sont `UP` sur les deux répartiteurs, contrôlés en TLS vérifié, et les erreurs des vraies requêtes sont observées.
- [ ] `https://lb01.par1.medisphere.internal:8404/stats` répond 401 sans identifiants depuis `adm01`, et n'est pas joignable depuis `runner01` ; `/metrics` répond au compte `supervision` ; aucun mot de passe en clair dans `haproxy.cfg`.
- [ ] Le socket d'API d'exécution existe (mode 660) et transmet les sockets d'écoute au rechargement.
- [ ] Les journaux de HAProxy contiennent un identifiant de requête.
- [ ] Les deux répartiteurs ont la même configuration (au nom et à l'adresse propre près) ; RB-070 est à jour sur `main`.

**Vérification** : `lab/bin/check 07 28`

<details><summary>Indice 1</summary>

`ssl-default-bind-ciphers` (TLS 1.2) et `ssl-default-bind-ciphersuites` (TLS 1.3) de la section `global` s'appliquent à tous les écouteurs, leurs équivalents `ssl-default-server-*` au re-chiffrement ; le générateur de configuration de Mozilla donne une base pour HAProxy. `http-response set-header` et `del-header` agissent sur toutes les réponses d'un frontend.
</details>

<details><summary>Indice 2</summary>

`unique-id-format` et `unique-id-header` créent et transmettent l'identifiant ; `log-format` l'écrit (`%ID`). Une `userlist` accepte `password` suivi d'une empreinte `crypt(3)` (`mkpasswd -m sha-512`), à la place de `insecure-password`. Le service `prometheus-exporter` s'appelle par `http-request use-service`.
</details>

<details><summary>Indice 3</summary>

Une `stick-table` sur l'adresse source avec `http_req_rate(10s)`, suivie (`track-sc0`) seulement pour les chemins de connexion, et une règle `http-request deny deny_status 429` sur le compteur. Pour le rechargement sans coupure, regarde ce que fait `expose-fd listeners` sur le socket d'administration en mode maître-processus.
</details>

**Pour aller plus loin** (facultatif) : OCSP n'existe pas dans la PKI interne (M06-E27) : que vérifie-t-on à la place ? ; QUIC/HTTP3 ; [manuel de configuration HAProxy 3.2](https://docs.haproxy.org/3.2/configuration.html), [API d'exécution](https://docs.haproxy.org/3.2/management.html), [générateur TLS de Mozilla](https://ssl-config.mozilla.org/), [contrôles de santé de GitLab](https://docs.gitlab.com/administration/monitoring/health_check/).

---

### M07-E29 — Superviser la bordure et les répartiteurs  `LAB` `★★`

> **Ticket PLAT-858** — *De : Nadia Roussel*
> Depuis E25, une bascule peut arriver la nuit sans que personne ne le sache, et c'est bien le but. Mais je veux le savoir le matin, et je veux surtout savoir quand la redondance **n'existe plus** : `gw02` éteinte depuis trois jours, une VIP portée par les deux passerelles, un serveur `DOWN` derrière les répartiteurs, le tunnel de PAR2 sans poignée de main depuis une heure.
> Comme pour les services socle : une sonde toutes les cinq minutes, une alerte si ça ne va pas.

**Objectifs pédagogiques**
- Superviser une **redondance** (deux nœuds cohérents) et pas seulement des services.
- Donner à une sonde un accès en lecture strictement limité à des hôtes sensibles (commande forcée, `sudo` restreint).
- Préparer l'export des mesures pour le module 21.

**Prérequis** : M06-E29 (`ms-verif-services`, `ms-alerte@`), M07-E25 à E28.
**Durée indicative** : 3 h.

**Contexte technique**
- Script `bin/ms-verif-reseau` dans `plateforme/outils`, tests bats, installé sous `/usr/local/bin` par `task install:systeme`, configuration versionnée `etc/ms-verif-reseau.conf` installée en `/usr/local/etc/`. Options : `-q|--quiet`, `--prometheus FICHIER` (écrit les mesures au format texte de node_exporter), codes 0 / 1 / 2 comme `ms-verif-services`.
- Unités sur `adm01` : `ms-verif-reseau.service` (oneshot, `User=admin`, `OnFailure=ms-alerte@%n.service`) et `ms-verif-reseau.timer` (toutes les 5 minutes, rattrapage).
- Accès aux hôtes : un compte **`supervision`** sur `gw01`, `gw02`, `lb01`, `lb02` (rôle **`sonde_reseau`**), connexion par une clé dédiée (`~/.config/workbook/ssh-supervision-reseau` sur `adm01`, 600), dont la seule action possible est d'exécuter `/usr/local/sbin/etat-reseau` (commande forcée dans `authorized_keys`, options `restrict`), qui affiche en JSON l'état local : état VRRP par instance, adresses portées, état des sessions BGP, poignées de main WireGuard, état des serveurs HAProxy, statut de `conntrackd`. `etat-reseau` est la seule commande que `supervision` peut lancer par `sudo`.
- Contrôles attendus (au minimum) :

  | Domaine | Contrôle |
  |---|---|
  | VRRP bordure | les deux passerelles répondent ; **exactement une** porte chaque VIP (neuf VLAN + WAN) ; toutes les VIP sur la **même** ; aucune instance en `FAULT` |
  | VRRP DMZ | exactement un répartiteur porte 10.10.70.200 |
  | BGP | sessions `Established` attendues (Lyon sur le maître ; `leaf01` si la maquette existe) ; aucune session configurée et tombée depuis plus de 10 minutes |
  | WireGuard | `wg0` et `wg2` : poignée de main de moins de 3 minutes sur le maître |
  | Connexions | `conntrackd` actif sur les deux passerelles |
  | Répartiteurs | tous les serveurs `UP` sur les deux répartiteurs |
  | Bout en bout | GitLab et NetBox répondent en HTTPS par leur nom publié |

**Travail demandé**
1. **L'accès.** Écris le rôle `sonde_reseau` : compte sans mot de passe ni shell interactif utile, clé autorisée avec commande forcée, règle `sudo` limitée à un chemin exact, script `etat-reseau`. Prouve depuis `adm01` que la clé ne permet **rien d'autre** (un `ssh supervision@gw01 id` doit renvoyer l'état, pas le résultat d'`id`). Ajoute le flux SSH `adm01` → `lb01`/`lb02` si nécessaire et inscris la clé au registre des secrets.
2. **La sonde.** Écris `ms-verif-reseau` et ses tests bats (réponses JSON de `etat-reseau` simulées : nominal, VIP sur les deux, VIP sur aucune, passerelle muette, serveur `DOWN`, tunnel muet). Chaque contrôle impossible est un `KO`.
3. **Les unités.** Service, timer, alerte, comme en M06-E29 (durcissement compris).
4. **Le rouge.** Pour chaque domaine, provoque un échec réaliste et **réversible**, un à la fois, en heures creuses : arrêt de keepalived sur la passerelle de secours (plus de redondance), arrêt de `conntrackd` sur la secours, serveur NetBox en `maint` sur un répartiteur, `wg0` du maître sans pair joignable une dizaine de minutes (coupe le flux sur `pbs01`, pas sur la passerelle ; ⚠️ depuis une session vers `pbs01` qui ne passe pas par ce tunnel, avec la remise en service programmée avant la coupure, hors fenêtre de sauvegarde), session BGP de `leaf01` désactivée (`neighbor … shutdown`). Constate l'alerte, remets en état.
5. **Préparer le module 21.** `--prometheus` écrit un fichier lisible par le *textfile collector* de node_exporter ; documente les noms de mesures.
6. **Le guide.** Complète `docs/astreinte.md` de `plateforme/outils` : pour chaque ligne `KO`, que vérifier en premier, quel runbook (RB-070, RB-071, RB-072).

**Critères de réussite**
- [ ] `ms-verif-reseau` est installé, ses tests bats passent dans le pipeline de `plateforme/outils`.
- [ ] Le timer passe toutes les 5 minutes avec rattrapage ; le service déclenche `ms-alerte@` en cas d'échec et a déjà tourné.
- [ ] Lancée maintenant, la sonde répond 0 ; une option inconnue donne 2.
- [ ] La clé de supervision ne permet que `etat-reseau` sur les quatre hôtes ; le compte `supervision` ne peut rien lancer d'autre par `sudo`.
- [ ] Le journal contient une alerte issue de `ms-verif-reseau` (moins de 30 jours).

**Vérification** : `lab/bin/check 07 29`

<details><summary>Indice 1</summary>

Dans `authorized_keys`, `restrict,command="…"` interdit redirections, agent, terminal et impose la commande, quelle que soit celle demandée par le client (elle est seulement disponible dans `SSH_ORIGINAL_COMMAND`). La règle `sudo` cite le chemin complet, sans argument (`""` en fin de règle interdit tout argument).
</details>

<details><summary>Indice 2</summary>

L'état VRRP le plus fiable pour une sonde, ce sont les **adresses** réellement portées (`ip -j address`) et le fichier d'état du script de transition ; `keepalived` sait aussi écrire ses données (`SIGUSR1`) mais demande `root` et un fichier temporaire. Pour BGP, `vtysh -c 'show bgp summary json'` ; pour WireGuard, `wg show all latest-handshakes` ; pour HAProxy, `show stat` sur le socket d'API.
</details>

**Pour aller plus loin** (facultatif) : n'alerter qu'au changement d'état ; publier les transitions VRRP (FIFO de notification de keepalived) ; [`sshd(8)` : `authorized_keys`](https://man.openbsd.org/sshd.8#AUTHORIZED_KEYS_FILE_FORMAT), [*textfile collector*](https://github.com/prometheus/node_exporter#textfile-collector).

---

### M07-E30 — La matrice des flux v2  `LAB` `★★`

> **Ticket SEC-859** — *De : Sophie Laurent*
> Le module 07 a ajouté une passerelle, une DMZ habitée, du BGP, un tunnel vers Lyon, du VRRP, une synchronisation de connexions et une redirection depuis le LAN maison. Chaque exercice a ajouté « sa » ligne dans la matrice. Je veux maintenant une matrice **relue d'un bloc** : chaque flux justifié, référencé, testé, et une version documentaire **générée** depuis le code, parce que la dernière copie à la main avait trois semaines de retard.

**Objectifs pédagogiques**
- Relire une politique de filtrage complète et la réduire au nécessaire.
- Étendre le filtrage local à la DMZ.
- Générer la documentation depuis le code et vérifier en CI qu'elles ne divergent pas.

**Prérequis** : M07-E24 à E29, M06-E30 (rôle `pare_feu_local`).
**Durée indicative** : 3 h.

**Contexte technique**
- Matrice de transit : `group_vars/role_routeur/pare_feu.yml` (E24). Filtrage local : rôle `pare_feu_local` de M06-E30, à appliquer maintenant à `lb01` et `lb02`.
- Flux introduits par le module (à retrouver, compléter, ou contester) : VRRP entre passerelles (E25, E26) et entre répartiteurs (E12) ; synchronisation `conntrackd` (E27) ; BGP de `leaf01` (E16), plage d'écoute préparée pour les nœuds Kubernetes (VLAN 40, E16), BGP de Lyon dans `wg2` (E19) ; `wg2` (UDP 51822) depuis `lyo-gw01` (E18) ; Lyon vers les réseaux PAR1 autorisés (E19) ; redirection 443 du WAN vers 10.10.70.200 (E13, E26) ; répartiteurs vers `git01` et `nbx01` (E13) ; défi ACME vers les répartiteurs (E12) ; statistiques 8404 (E28) ; supervision SSH (E29).
- Documentation : `docs/socle/matrice-flux.md` de `plateforme/medisphere`. Générateur : `bin/ms-matrice-flux` dans `plateforme/outils` (lit le YAML de la matrice, écrit un tableau Markdown trié par chaîne, avec motif et référence) ; un job de la CI de `plateforme/ansible` échoue si le document publié n'est pas à jour.

**Travail demandé**
1. **Relecture.** Pour chaque ligne de la matrice : encore utile ? trop large (une source « tout le lab » là où deux adresses suffisent, un port de trop) ? référence à jour ? Rédige la liste des changements dans la MR, avec la raison de chacun.
2. **Les flux du module.** Vérifie que chaque flux de la liste du contexte existe, est **le plus étroit possible** (interfaces, adresses, ports), et porte sa référence. Les règles propres à une passerelle n'existent plus ; tout ce qui vise la bordure vise ses adresses virtuelles ou les deux adresses propres.
3. **La DMZ.** Applique `pare_feu_local` à `lb01` et `lb02` : 80 et 443 depuis tout le lab, le LAN maison (redirigé) et le VPN ; 8404 depuis MGMT ; 22 depuis `adm01` et `runner01` ; VRRP (VRID 170) depuis le pair ; rien d'autre. Un répartiteur à la fois, en commençant par celui qui ne porte pas la VIP.
4. **La génération.** Écris `ms-matrice-flux`, ses tests bats, le job de CI. Publie `matrice-flux.md` générée.
5. **La preuve.** Depuis `runner01`, une VM du VLAN 99, `lb01`, `lyo-pc01` (si la maquette existe) et le LAN maison (`pve01`) : un scan des passerelles et de la DMZ (`nmap`), et au moins un test positif par flux du module. Compare à la matrice ; vérifie que les deux passerelles chargent le même jeu de règles.

**Critères de réussite**
- [ ] Chaque règle de la matrice a un motif et une référence ; la matrice ne contient plus d'adresse propre à une seule passerelle sauf justification écrite.
- [ ] VRRP, `conntrackd` et BGP ne sont acceptés que depuis les sources attendues ; le port 179 des passerelles n'est pas joignable depuis `runner01`.
- [ ] `lb01` et `lb02` filtrent leurs entrées (`inet filtre_local`, politique `drop`) : depuis une autre machine de la DMZ (une passerelle, par son adresse propre du VLAN 70), leur port 22 n'est pas joignable, leur port 443 l'est.
- [ ] `docs/socle/matrice-flux.md` est généré par `ms-matrice-flux` et à jour ; un job de CI le vérifie.
- [ ] Les deux passerelles chargent le même jeu de règles ; `nft -c` passe sur les deux.

**Vérification** : `lab/bin/check 07 30`

<details><summary>Indice 1</summary>

Une règle qui accepte un protocole sans port (VRRP) se restreint par l'interface **et** la source. Pour BGP, la session vers `leaf01` est établie par l'une ou l'autre extrémité : la règle d'entrée doit accepter le port 179 en destination depuis `leaf01`, et les réponses passent par l'état `established`.
</details>

<details><summary>Indice 2</summary>

Pour le générateur, `yq` (mikefarah) sait sortir chaque liste en TSV ; Python avec `pyyaml` (environnement `uv` du projet) aussi. Le job de CI régénère le document et compare avec la version publiée de `plateforme/medisphere` (lecture par l'API, jeton en lecture), ou le génère comme artefact : choisis et justifie.
</details>

**Pour aller plus loin** (facultatif) : NetBox comme source des objets nommés (`$DNS01`…) ; [nftables : ensembles nommés](https://wiki.nftables.org/wiki-nftables/index.php/Sets).

---

### M07-E31 — ADR : haute disponibilité de la bordure  `RED` `★★`

> **Ticket PLAT-860** — *De : Claire Morel*
> Le comité d'architecture veut comprendre pourquoi nous avons deux VMs Debian en VRRP plutôt qu'une appliance, plutôt qu'une passerelle unique redémarrée par la haute disponibilité de Proxmox, ou plutôt que du routage actif-actif. Et il voudra savoir ce qui changera quand le cluster de virtualisation (module 09) et Kubernetes (module 15) arriveront.
> Écris l'ADR-0070.

**Objectifs pédagogiques**
- Comparer des architectures de haute disponibilité réseau sur des critères explicites (temps de bascule, état, complexité, dépendances, coût d'exploitation).
- Écrire les conséquences négatives et les conditions de révision d'une décision déjà mise en œuvre.

**Prérequis** : M07-E24 à E27, M07-E32 conseillé (les mesures nourrissent l'ADR).
**Durée indicative** : 2 h.

**Travail demandé**
Rédige `docs/socle/adr/ADR-0070-haute-disponibilite-bordure.md` (gabarit MADR de M00-E33, deux pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Poser le contexte et les exigences chiffrées (disponibilité visée, perte acceptable lors d'une bascule, connexions qui doivent survivre, contraintes du lab : un seul hyperviseur, pas de commutateur physique).
2. Comparer au moins quatre options : passerelle unique et restauration rapide ; deux passerelles Linux en VRRP actif-passif avec synchronisation des connexions (mise en œuvre) ; routage actif-actif (ECMP, BGP vers la fabric, passerelle *anycast*) ; appliance pare-feu redondante (par exemple CARP et `pfsync`) ; passerelle unique sous la haute disponibilité de Proxmox (module 09).
3. Trancher, en citant les mesures (E25, E27, E32) et en disant honnêtement ce que la solution ne couvre pas (un seul hyperviseur : `pve01` reste un point unique ; la box ; le LAN maison).
4. Lister les conséquences négatives (exploitation de deux nœuds, secrets dupliqués, règle « rien ne vise une adresse propre », complexité des scripts de transition…) et les actions induites, rattachées à un module (M09, M15, M21, F5).
5. Dire **quand** la décision devra être revue (quel événement, quel seuil).

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en deux pages, et cite au moins quatre options réellement comparées sur les mêmes critères.
- [ ] Les exigences sont chiffrées et la décision s'appuie sur des mesures du lab.
- [ ] Les limites (points uniques restants) et les conséquences négatives sont écrites.
- [ ] Les conditions de révision sont explicites.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Un tableau options × critères rend la comparaison lisible ; un critère sans valeur pour une option est un critère à creuser, pas à laisser vide. Les critères qui départagent le plus souvent : ce qui arrive à l'**état** (connexions, NAT, sessions VPN) pendant la bascule, et ce qu'il faut **savoir** pour opérer la solution à 3 h du matin.
</details>

**Pour aller plus loin** (facultatif) : [RFC 5798](https://www.rfc-editor.org/rfc/rfc5798) (section « Security considerations ») ; les passerelles *anycast* distribuées d'EVPN (module 09, SDN EVPN de Proxmox).

---

### M07-E32 — Tester et mesurer les bascules  `LIBRE` `★★★`

> **Ticket PLAT-861** — *De : Nadia Roussel* — *Copie : Claire Morel*
> On a testé « ça bascule ». Je veux savoir **combien** : combien de paquets perdus, quelles connexions survivent, combien de temps pour que Lyon et PAR2 reviennent, et ce qui se passe dans les cas moins polis qu'un `systemctl stop`. Ces chiffres iront dans l'ADR, dans le contrat de service interne et dans le dossier du PRA (F5).

**Objectifs pédagogiques**
- Concevoir un plan de test de haute disponibilité : scénarios, mesures, critères d'arrêt, retour à l'état nominal.
- Mesurer finement (perte, durée, survie des sessions, reconvergence) et interpréter les écarts.
- Provoquer des pannes réalistes sans perdre la main sur le lab.

**Prérequis** : M07-E25 à E29.
**Durée indicative** : 4 h.

**Contraintes**
- Au moins **sept scénarios**, dont : bascule planifiée (RB-071) et retour ; arrêt brutal du processus keepalived du maître ; extinction brutale de la VM maître (équivalent d'une coupure de courant) ; perte du lien trunk du maître ; perte du lien WAN du maître ; perte des annonces VRRP entre les passerelles sur **un** VLAN (cerveau divisé partiel ?) ; retour du nœud tombé (préemption ou non, conforme à ta politique).
- ⚠️ Un processus tué brutalement ne nettoie rien derrière lui (adresses, tunnels, script de transition non appelé) : pour ce scénario, prépare la commande qui relance keepalived sur la passerelle concernée et lance-la dès la mesure faite (30 s au plus). Pour la perte du lien WAN, ta session SSH par l'adresse WAN de cette passerelle tombera : garde sa console ouverte.
- Les pannes de lien se provoquent **depuis Proxmox** (état de lien de la carte virtuelle) ou dans l'invité, jamais en touchant à `vmbr0`, `vmbr1` ou aux routes de `pve01`. La perte des annonces se provoque par une règle de filtrage **temporaire** et datée, sur **un seul** VLAN, posée à la main sur la passerelle de secours, retirée à la fin du scénario (jamais sur tous les VLAN : deux maîtres de toute la bordure, VIP WAN et tunnels compris, coupent le lab).
- Mesures pour chaque scénario : perte de paquets d'un flux ICMP à 10 paquets par seconde (VLAN 99 → Internet, `adm01` → VM du VLAN 99, `adm01` → `pve01`) ; survie d'une session SSH et d'un téléchargement ; délai de rétablissement de la session BGP de Lyon et de la poignée de main `wg0` ; état final (qui est maître, alertes reçues de `ms-verif-reseau`).
- Critères d'arrêt écrits avant de commencer (exemple : une VIP portée par aucune passerelle plus de 30 s, perte de l'accès de secours) et procédure de retour à l'état nominal après **chaque** scénario. Jamais deux pannes à la fois. Jamais pendant une sauvegarde PBS.
- Livrable : `docs/socle/tests/bascules.md` (section datée) : plan, tableau des résultats (scénario, perte en secondes par flux, survie des sessions, reconvergence BGP et WireGuard, état final, alerte reçue), analyse des écarts, propositions (réglages, objectifs de niveau de service), et la liste des scénarios **non** testés et pourquoi.

**Critères de réussite**
- [ ] `bascules.md` contient au moins sept scénarios avec des valeurs mesurées pour chaque flux.
- [ ] Le scénario « annonces perdues sur un VLAN » a été observé et expliqué (qui veut devenir maître, ce que fait le groupe de synchronisation, ce qui se passerait sans lui ou si les annonces étaient perdues sur tous les VLAN).
- [ ] À la fin, l'état est nominal : une seule passerelle porte toutes les VIP (celle prévue par ta politique), aucune carte de `gw01`/`gw02` n'est déconnectée, aucune règle de test ne subsiste.
- [ ] Les chiffres alimentent l'ADR-0070 et RB-071 (perte attendue lors d'une bascule planifiée).

**Vérification** : `lab/bin/check 07 32`

<details><summary>Indice 1</summary>

Un ping à 10 paquets par seconde perd *n* paquets : la coupure dure environ *n* × 100 ms. `fping` (ou `ping -D` horodaté) permet de dater précisément le premier et le dernier paquet perdu. Pour la survie d'un téléchargement, un fichier de taille connue et une somme de contrôle à l'arrivée valent mieux qu'une impression.
</details>

<details><summary>Indice 2</summary>

La définition d'une carte virtuelle Proxmox a une option qui la déconnecte sans toucher au pont (`link_down`, voir `qm(1)`) : la définition se réécrit en entier, relis donc l'actuelle pour ne rien changer d'autre, et garde l'inverse prêt. Une règle de filtrage de test se repère mieux si elle porte un commentaire (`comment "TEST-E32"`).
</details>

**Pour aller plus loin** (facultatif) : automatiser la campagne (script ou playbook) pour la rejouer à chaque version de la bordure ; [RFC 5798, section 6.4 (*Protocol State Machine*)](https://www.rfc-editor.org/rfc/rfc5798#section-6.4).

---

### M07-E33 — Questions de production : réseau et HA  `Q` `★★★`

> **Ticket PLAT-862** — *De : Karim Benali*
> Avant de te mettre d'astreinte sur la bordure, mes questions habituelles. Argumente, chiffre, et dis de quoi dépend le « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur le comportement en production de VRRP, du suivi de connexions, de BGP, de WireGuard et des répartiteurs.
- Relier les choix du module à des risques concrets.

**Prérequis** : paliers 1 et 2, M07-E24 à E32.
**Durée indicative** : 1 h 30.

**Questions**

1. Avec un intervalle d'annonce d'1 s, combien de temps au plus la VIP d'un VLAN reste-t-elle sans maître quand `gw01` (priorité 150) s'éteint brutalement ? Et quand on arrête proprement keepalived sur `gw01` ? Pourquoi la différence ?
2. QCM — Après une bascule, une VM du VLAN 20 met 40 s à retrouver Internet alors que la VIP a basculé en 4 s. La cause la plus probable :
   a) le TTL DNS des enregistrements de `gw01` ;
   b) la VM a gardé l'ancienne adresse MAC de la passerelle dans son cache ARP, faute d'ARP gratuit reçu ou pris en compte ;
   c) la session BGP de Lyon ;
   d) `conntrackd` n'a pas encore synchronisé la table de routage.
   Comment le prouves-tu, et que règles-tu ?
3. Les annonces VRRP de `gw01` n'arrivent plus à `gw02` sur le VLAN 99 seulement (filtrage). Que fait l'instance `VLAN99` de `gw02`, et le groupe `BORDURE` ? Que voient les VMs du VLAN 99 ? Même question si les annonces sont perdues sur **tous** les VLAN. Comment détecter chaque cas, et que fais-tu à 3 h du matin ?
4. Préemption ou `nopreempt` : décris une journée où chaque choix provoque **une** bascule de trop. Lequel as-tu retenu, et à quelle condition changerais-tu d'avis ?
5. Pourquoi le masquage (`masquerade`) sur l'adresse de l'interface WAN rendrait-il `conntrackd` inutile pour les flux traduits ? Et pourquoi la traduction vers la VIP WAN n'est-elle utile que si la VIP bascule **avec** les VLAN ?
6. QCM — `nf_conntrack_tcp_loose` vaut 1 et `conntrackd` est arrêté. Une session SSH de `adm01` vers une VM du VLAN 99 traverse une bascule. Que se passe-t-il ?
   a) elle est toujours coupée : la nouvelle passerelle n'a aucune entrée ;
   b) elle survit le plus souvent : le premier paquet vu crée une entrée « reprise », et la règle MGMT → lab l'accepte ;
   c) elle survit seulement si la VM émet la première ;
   d) elle survit grâce à l'ARP gratuit.
   Que change `nf_conntrack_tcp_loose=0`, et pourquoi le réglage strict est-il préférable **avec** `conntrackd` ?
7. WireGuard après bascule : pourquoi le tunnel `wg1` d'un poste nomade se rétablit-il sans intervention, alors que le tunnel `wg0` vers `pbs01` peut rester muet ? Qu'est-ce que le *roaming* de WireGuard autorise et n'autorise pas ?
8. La session BGP de Lyon passe par `wg2`. Après une bascule, combien de temps avant que Lyon rejoigne de nouveau PAR1 ? Quels minuteurs interviennent (WireGuard, BGP *hold time*, *keepalive*) ? Comment raccourcir sans rendre la session instable ?
9. Un contrôle de santé HAProxy toutes les 2 s, `fall 3`, `rise 2`. GitLab tombe : combien de requêtes d'utilisateurs échouent au pire avant que le serveur soit retiré, à 50 requêtes par seconde ? Que changent `observe layer7` et `on-error` ?
10. QCM — `systemctl reload haproxy` pendant 200 connexions longues (téléchargements GitLab). Résultat attendu avec HAProxy 3.2 en mode maître-processus :
    a) les 200 connexions sont coupées ;
    b) les anciennes connexions finissent sur l'ancien processus, les nouvelles vont au nouveau, jusqu'à `hard-stop-after` ;
    c) le rechargement attend la fin des 200 connexions avant de prendre la nouvelle configuration ;
    d) HAProxy refuse de recharger tant qu'il y a des connexions.
11. Pourquoi les VIP de la bordure ne doivent-elles **jamais** être la cible d'un outil d'administration (Ansible, SSH des checks, voisins BGP) ? Donne trois incidents que cette règle évite.
12. Le MTU du trunk est à 9000, `wg0` à 1420. Un transfert de `pbs01` vers une VM du VLAN 30 (MTU 9000) se fige après la bascule, pas avant. Hypothèses ? Quelles différences entre les deux passerelles chercher en premier ?
13. Les nœuds Kubernetes du module 15 parleront BGP avec les passerelles. À quelles adresses doivent-ils se connecter (VIP ou adresses propres), et pourquoi ? Que se passe-t-il pour les routes du VLAN 41 pendant une bascule VRRP ?
14. Tu dois mettre à jour le noyau des deux passerelles dans la journée. Écris l'enchaînement (dix lignes au plus), avec ce que tu vérifies entre chaque étape et la perte attendue.

Les réponses argumentées sont dans le corrigé.

---

### M07-E34 — Publier un nouveau service en temps limité  `CHRONO` `★★★`

> **Ticket CHG-863** — *De : Claire Morel*
> Julien veut montrer une maquette de MédiAgenda à des partenaires la semaine prochaine, depuis nos locaux seulement. Je lui ai dit qu'un nouveau point d'entrée, propre, redondant, chiffré et supervisé, c'était l'affaire d'une heure et demie. Prouve-le.
> Le dossier est dans les ressources de l'exercice. Chrono en main.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **tes** runbooks (RB-060, RB-070), ton code et la documentation officielle.
- Durée cible : **1 h 30** entre l'ouverture du dossier (T0) et le service vérifié (T5).
- Tout passe par le code et les pipelines (rôles des répartiteurs, matrice, DNS, supervision). Un geste manuel est permis pour **constater**, jamais pour configurer ; note chacun dans la feuille de temps.
- Le service est **temporaire** : à la fin, après la vérification, tu le retires proprement, par le code.

**Prérequis** : M07-E28 à E30, M07-E08 (`srv01`/`srv02` servent leur page), RB-060, RB-070.
**Durée** : 1 h 30 chronométrées + 30 minutes de retour d'expérience.

**Dossier** : [`ressources/M07-E34/dossier-chrono.md`](../ressources/M07-E34/dossier-chrono.md). Lis-le à T0, pas avant.

**Critères de réussite**
- [ ] Le service décrit dans le dossier est en service à T5 et toutes ses exigences sont satisfaites (vérification ci-dessous, **avant** le retrait).
- [ ] La feuille de temps est remplie (T0 à T6) ; le temps jusqu'à T5 est inférieur à 1 h 30 (sinon, améliore ton outillage et recommence).
- [ ] Le retour d'expérience (une demi-page) est rédigé, RB-070 mis à jour par MR si nécessaire.
- [ ] Après le retrait, plus rien ne reste (nom, configuration des répartiteurs, flux, certificat en service, supervision).

**Vérification** : `lab/bin/check 07 34` (à lancer à T5, **avant** le retrait ; le retrait est contrôlé par le mini-projet M07-E46).

**Pour aller plus loin** (facultatif) : refais l'exercice en visant 30 minutes, puis écris ce qu'il faudrait pour que Julien publie lui-même un service (catalogue d'entrées, module 28).
