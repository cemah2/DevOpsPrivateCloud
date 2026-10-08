# Module 07 — Introduction : réseau de datacenter et haute disponibilité

## Le jour où `gw01` a redémarré

Mardi, 7 h 42. Les mises à jour automatiques de `gw01` ont installé un nouveau noyau et la passerelle a redémarré pour le charger. Elle a mis trois minutes à revenir. Pendant ce temps, le pipeline de nuit de `plateforme/infra` a échoué (plus d'accès à l'état sur `s3-01` depuis l'extérieur du VLAN), la sauvegarde de `git01` vers `pbs01` s'est interrompue, et Nadia, en télétravail, a perdu son VPN d'administration au milieu d'une intervention. Rien de grave, mais tout le monde a compris. À 10 h, Claire envoie ce message.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel
> **Objet** : Réseau — plus de point unique de défaillance avant le stockage
>
> Bonjour,
>
> Ce matin, un redémarrage prévu de `gw01` a coupé tout le lab pendant trois minutes : forge, sauvegardes, VPN. En production, ce serait un incident majeur et une notification à l'ARS. Le socle v1 a un défaut de naissance : **une seule passerelle**, et chaque service publié n'est joignable que par son adresse propre.
>
> Le bloc B va ajouter des dizaines de machines : Ceph, un cluster Proxmox, OpenStack. Je ne veux pas les brancher sur une bordure qui tombe à chaque mise à jour. Avant d'attaquer le stockage, je veux :
> 1. une **bordure redondante** : deux passerelles (`gw01`, `gw02`) qui portent ensemble les adresses `.1` de chaque VLAN, l'adresse WAN et les tunnels, et qui basculent sans que personne ne le remarque ;
> 2. des **points d'entrée redondants** : deux répartiteurs (`lb01`, `lb02`) devant GitLab et NetBox, avec TLS ;
> 3. un réseau prêt pour le stockage : **jumbo frames** sur les VLAN de Ceph et du tunnel OpenStack ;
> 4. du **routage dynamique** sur la bordure : Kubernetes annoncera ses adresses de services en BGP au bloc C, et je ne veux pas découvrir BGP ce jour-là ;
> 5. l'agence de **Lyon** raccordée au datacenter, proprement.
>
> Karim a une exigence : que l'équipe sache **lire** un réseau de datacenter, pas seulement le configurer. D'où la maquette *leaf-spine* qu'il te demande de monter avant de toucher à la bordure : on apprend sur la maquette, on applique sur le socle. Nadia veut des runbooks de bascule testés, Sophie une matrice des flux à jour et une seule politique de filtrage pour les deux passerelles.
>
> Premier jalon : la cartographie de l'existant, la maquette par le code, et les fondamentaux (agrégation, Open vSwitch, OSPF, BGP, VRRP). Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 07, le socle passe en version **v2** (étiquette `socle-v2` du dépôt `plateforme/medisphere`), état d'entrée de la suite du bloc B :

- **bordure redondante** : `gw02` (VMID 1009) rejoint `gw01` ; keepalived (VRRP v3, annonces unicast) porte la VIP `.1` de chaque VLAN routé et l'adresse WAN virtuelle ; les tunnels WireGuard suivent le maître ; `conntrackd` synchronise les connexions ; une seule matrice des flux pour les deux passerelles ;
- **répartiteurs** : `lb01`/`lb02` (1010/1011) dans la DMZ, HAProxy 3.2 + keepalived, VIP 10.10.70.200 (`lb.par1.medisphere.internal`), publication de GitLab et NetBox en HTTPS ;
- **FRR** sur la bordure (AS 65000), prêt à recevoir les annonces BGP de Kubernetes (10.10.41.0/24) ;
- **MTU 9000** de bout en bout sur les VLAN 30, 31 et 51 ;
- le **site de Lyon** (LYO1) raccordé par un tunnel WireGuard `wg2` avec routage BGP ;
- la supervision de la bordure, les runbooks RB-070 et suivants, l'ADR-0070.

Le **palier 1** (ce fichier et `01-decouverte.md`) n'y touche pas encore : tu cartographies l'existant (E02), tu montes la **maquette** réseau par le code (E03), puis tu pratiques sur elle l'agrégation de liens (E04), Open vSwitch (E05), OSPF (E06), BGP (E07) et VRRP (E08). Aucun hôte du socle n'est modifié au palier 1, à une exception près : la création des VNets de la maquette sur `pve01` (E03), annoncée et réversible.

## Architecture du module

### Cible : la bordure du socle v2 (paliers 2 et 3)

```
                               Internet
                                   │
                          ┌────────┴────────┐
                          │   Box maison    │  <LAN-MAISON>
                          └────────┬────────┘
     pve01 (route 10.10/16, 10.20/16, 10.255.1/24 via la VIP WAN)   │      ton poste (wg1)
            ┌──────────────────────┴───────────────────────┐
     <IP-GW01-WAN>      VIP WAN <IP-GW-WAN-VIP> (VRID 250)   <IP-GW02-WAN>
      ┌──────┴──────┐  ◄── VRRP v3 unicast, conntrackd ──►  ┌──────┴──────┐
      │ gw01 (1000) │        priorité 150 / 100           │ gw02 (1009) │
      │ nftables    │   wg0 (PAR2) · wg1 (VPN) · wg2 (LYO1)│ mêmes rôles │
      │ FRR AS 65000│   montés sur le maître seulement     │ FRR AS 65000│
      └──────┬──────┘                                     └──────┬──────┘
        ens19 trunk                                         ens19 trunk
             └──────────────── vmbr1 (VLAN-aware) ──────────────┘
   chaque VLAN routé : gw01 = .2, gw02 = .3, VIP .1 (VRID = numéro de VLAN)
             │
             ├─ VLAN 70 DMZ   lb01 (1010) .10 ─┐ VIP 10.10.70.200 (VRID 170)
             │                lb02 (1011) .11 ─┘ HAProxy 3.2 : gitlab.par1…, netbox.par1…
             ├─ VLAN 20 INFRA git01, nbx01… (backends des répartiteurs)
             ├─ VLAN 30/31/51  MTU 9000 (Ceph, OpenStack)
             └─ VLAN 99 SANDBOX  maquette (VNet vsandbox) ── leaf01 10.10.99.251 ◄─BGP─► bordure (E16)
```

### La maquette (paliers 1 et 2, VMID 2070-2079)

```
                  adm01 (10.10.10.10) ── MGMT joint tout le lab ── gw01 ── VLAN 99 (vsandbox)
                                                                     │  administration (eth0)
        ┌──────────────┬─────────────┬─────────────┬────────────────┼─────────────┬──────────────┐
      net01          spine01       spine02        leaf01            leaf02        srv01/srv02  lyo-gw01 …
                     AS 65100      AS 65100       AS 65101          AS 65102
                    10.10.255.1   10.10.255.2    10.10.255.11      10.10.255.12
                      │      ╲      ╱      │        │                  │
                vfab1 │  vfab2╲    ╱vfab3  │ vfab4  │                  │
                      │        ╲  ╱        │        │                  │
                      │         ╳          │        │                  │
                      │        ╱  ╲        │        │                  │
                    leaf01 ───────── vfab7 ───── leaf02
                      │ vfab5                         │ vfab6
                    srv01 (10.10.255.21)            srv02 (10.10.255.22)
                      └──── VRRP VIP 10.10.99.240 (VRID 199, sur eth0) ────┘

   net01 : tout se passe DANS la VM — espaces de noms ns-srv / ns-sw reliés par des paires veth
           (bonding, LACP), pont Open vSwitch br-lab (VLAN, miroir de port).

   Site simulé LYO1 :  « Internet » = vsandbox
        lyo-gw01  eth0 10.10.99.250 ═══ wg2 (UDP 51822, 10.255.2.2 ↔ 10.255.2.1) ═══ bordure PAR1
                  eth1 10.30.10.1/24 ── vfab8 ── lyo-pc01 eth1 10.30.10.10
```

Points structurants :

- **On apprend sur la maquette, on applique sur le socle.** Tout ce qui peut casser (sessions BGP, bascules VRRP, bonds) est d'abord pratiqué sur des VMs jetables, reconstruites par le code en quelques minutes. La bordure du socle n'est modifiée qu'à partir du palier 2 (flux de la matrice, redirection WAN E13, MTU E15, FRR E16, `wg2` E18), puis au palier 3 (`gw02`, VRRP, VIP WAN, `conntrackd`), toujours par le code, avec précautions et retour arrière (fiche de changement pour E15, E25, E26).
- **Le pont Linux de `pve01` ne relaie pas LACP.** Les trames 802.3ad (adresse 01:80:c2:00:00:02) sont réservées : un bond LACP entre deux VMs à travers `vmbr1` ne se forme jamais. Le LACP se pratique donc **à l'intérieur de `net01`**, entre espaces de noms reliés par des paires veth (E04, E17). Entre VMs, seuls les modes sans négociation (`active-backup`, `balance-xor`) ont un sens.
- **Les liens de fabric sont des VNets dédiés** (`vfab1` à `vfab8`, VLAN 901 à 908 de la zone SDN `lab`, sans passerelle) : chaque lien point à point est un domaine de diffusion isolé, comme un câble entre deux commutateurs.
- **L'interface d'administration de chaque VM de la maquette est `eth0`, sur `vsandbox`** : c'est par elle qu'`adm01` et Ansible y accèdent, et elle reste en dehors du routage de la fabric.

### Hôtes du module

Hôtes permanents (créés aux paliers 2 et 3, PLAN §4.5) :

| Hôte | VMID | Adresse | Ressources | Étiquettes | Rôles Ansible | Exercice |
|---|---|---|---|---|---|---|
| `lb01`, `lb02` | 1010, 1011 | 10.10.70.10, .11 ; VIP 10.10.70.200 | 1 vCPU, 1 Go, 10 Go | `socle`, `role-lb` | `haproxy`, `keepalived` | E12 |
| `gw02` | 1009 | `<IP-GW02-WAN>` ; `.3` sur chaque VLAN routé | 1 vCPU, 1 Go, 10 Go | `socle`, `role-routeur` | rôles de `gw01` (`pare_feu`, `relais_dhcp`, `chrony_serveur`…), `frr`, `keepalived`, `conntrackd` | E24 |
| `gw01` | 1000 | `.1` → `.2` + VIP `.1` | inchangées | `socle`, `role-routeur` | + `frr` (E16), `keepalived` (E25), `conntrackd` (E27) | E16, E25-E27 |

VMs de la maquette (pool `lab`, étiquette `env-m07`, état OpenTofu `m07-maquette`, Debian 13 image dorée `current`, démarrage automatique désactivé). Les cartes sont dans l'ordre `net0`, `net1`… de Proxmox, vues comme `eth0`, `eth1`… dans l'invité (nommage de la configuration réseau cloud-init de Proxmox).

| VMID | Nom | vCPU / Mo | `eth0` (`vsandbox`) | Autres cartes (VNet : adresse) | Étiquettes | Exercices |
|---|---|---|---|---|---|---|
| 2070 | `net01` | 2 / 2048 | DHCP | — (tout est interne à la VM) | `env-m07`, `m07-labo` | E04, E05, E17, E40 |
| 2071 | `spine01` | 1 / 1024 | DHCP | `eth1` vfab1 : 10.10.250.0/31 ; `eth2` vfab2 : 10.10.250.2/31 | `env-m07`, `m07-fabric`, `m07-spine` | E06, E07, E14 |
| 2072 | `spine02` | 1 / 1024 | DHCP | `eth1` vfab3 : 10.10.250.4/31 ; `eth2` vfab4 : 10.10.250.6/31 | idem | E06, E07, E14 |
| 2073 | `leaf01` | 1 / 1024 | **10.10.99.251/24** | `eth1` vfab1 : .1/31 ; `eth2` vfab3 : .5/31 ; `eth3` vfab5 : .8/31 ; `eth4` vfab7 : .12/31 | `env-m07`, `m07-fabric`, `m07-leaf` | E06, E07, E14, E16 |
| 2074 | `leaf02` | 1 / 1024 | DHCP | `eth1` vfab2 : .3/31 ; `eth2` vfab4 : .7/31 ; `eth3` vfab6 : .10/31 ; `eth4` vfab7 : .13/31 | idem | E06, E07, E14 |
| 2075 | `srv01` | 1 / 1024 | **10.10.99.252/24** | `eth1` vfab5 : 10.10.250.9/31 | `env-m07`, `m07-web` | E08, E10, E14 |
| 2076 | `srv02` | 1 / 1024 | **10.10.99.253/24** | `eth1` vfab6 : 10.10.250.11/31 | `env-m07`, `m07-web` | E08, E10, E14 |
| 2077 | `lyo-gw01` | 1 / 1024 | **10.10.99.250/24** (son « WAN ») | `eth1` vfab8 : 10.30.10.1/24 | `env-m07`, `m07-lyo` | E18, E19, E36 |
| 2078 | `lyo-pc01` | 1 / 512 | DHCP (administration seulement) | `eth1` vfab8 : 10.30.10.10/24 | `env-m07`, `m07-lyo` | E18, E19, E36 |
| 2079 | `hap01` | 1 / 1024 | DHCP | — | `env-m07`, `m07-hap` | E10 (créée au palier 2) |

Les adresses (sur `eth1`…, et celles de `eth0` en gras) sont posées par cloud-init à la création (`ipconfig1`…). Les VMs en DHCP reçoivent leur nom par la mise à jour dynamique du DNS de Kea (M06-E17) ; les quatre adresses fixes du VLAN 99 (plage `.250-.254` « équipements / tests ») ont leurs enregistrements A et PTR créés par OpenTofu et sont **réservées dans NetBox**, comme la VIP de démonstration 10.10.99.240 (`web-demo.par1.medisphere.internal`). Toutes les VMs allumées : ≈ 10,5 Go ; `lyo-*` et `hap01` peuvent rester arrêtées tant que leur palier n'est pas commencé.

`lyo-pc01` garde **toujours** la route par défaut de son DHCP d'administration (`eth0`) : c'est par elle qu'`adm01` l'administre. Le raccordement de LYO1 (E18) lui ajoute seulement des routes **ciblées** vers les réseaux de PAR1 ouverts à l'agence, par `lyo-gw01` (10.30.10.1).

### Plan d'adressage et numéros de la fabric

| Lien (VNet, VLAN) | Extrémités | Réseau /31 |
|---|---|---|
| `vfab1` (901) | spine01 `eth1` .0 — leaf01 `eth1` .1 | 10.10.250.0/31 |
| `vfab2` (902) | spine01 `eth2` .2 — leaf02 `eth1` .3 | 10.10.250.2/31 |
| `vfab3` (903) | spine02 `eth1` .4 — leaf01 `eth2` .5 | 10.10.250.4/31 |
| `vfab4` (904) | spine02 `eth2` .6 — leaf02 `eth2` .7 | 10.10.250.6/31 |
| `vfab5` (905) | leaf01 `eth3` .8 — srv01 `eth1` .9 | 10.10.250.8/31 |
| `vfab6` (906) | leaf02 `eth3` .10 — srv02 `eth1` .11 | 10.10.250.10/31 |
| `vfab7` (907) | leaf01 `eth4` .12 — leaf02 `eth4` .13 | 10.10.250.12/31 |
| `vfab8` (908) | LAN de LYO1 : lyo-gw01 .1, lyo-pc01 .10 | 10.30.10.0/24 |

| Élément | Valeur |
|---|---|
| Boucles (`lo`, /32) | spine01 10.10.255.1, spine02 .2, leaf01 .11, leaf02 .12, srv01 .21, srv02 .22 (10.10.255.0/24) |
| AS (PLAN §4.9) | bordure 65000 ; spines 65100 (les deux) ; leaf01 65101 ; leaf02 65102 ; PAR2 65020 ; LYO1 65030 ; Kubernetes 65040 ; EVPN `hv-par1` 65090 |
| VRID | VIP de démonstration 10.10.99.240 : **199** ; essai Molecule du rôle `keepalived` : 10.10.99.239, VRID 198 ; bordure : VRID = numéro de VLAN, 250 côté WAN (palier 3) ; répartiteurs : 170 |
| Espaces de noms de `net01` | `ns-srv` et `ns-sw` (bonding, E04 ; bond OVS, E17), paires veth `vsrvN` ↔ `vswN`, bond `bond0` : 172.31.70.1/24 (`ns-srv`), 172.31.70.2/24 (`ns-sw`) ; `ns-a`, `ns-b`, `ns-c`, `ns-r` et pont OVS `br-lab` (VLAN 110 : 172.31.110.0/24, VLAN 120 : 172.31.120.0/24, E05) |

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur `gw01` |
|---|---|---|---|
| `adm01` → maquette (SSH, HTTP, VIP de démonstration) | 22, 80 | E03-E08 | existant : MGMT joint tout le lab |
| maquette → Internet (paquets, dépôt FRR) | 80, 443 | E03-E08 | existant (« lab vers Internet », NAT) |
| maquette → `dns01`/`dns02` (DNS), Kea (DHCP relayé) | 53, 67 | E03 | existant (M06-E24, E25) |
| BGP, OSPF, VRRP **à l'intérieur** de la maquette | 179, IP 89, IP 112 | E06-E08 | ne traversent pas `gw01` (même VNet) |

Aucun flux nouveau au palier 1. Les suivants (BGP bordure ↔ `leaf01`, `wg2`, publication par les répartiteurs) passent par `host_vars/gw01/pare_feu.yml` jusqu'à E23 ; en E24, la matrice déménage dans `group_vars/role_routeur/pare_feu.yml`, commune à `gw01` et `gw02`.

---

## Le chemin imposé

Le chemin du module 06 s'applique, avec deux nuances pour la maquette :

1. **OpenTofu** : les hôtes permanents (`gw02`, `lb01`, `lb02`) vont dans l'état `socle` de `plateforme/infra` (module `vm-debian`, image dorée `current`, pipeline). La maquette a **son propre état**, `m07-maquette` (répertoire `envs/m07-maquette/`), appliqué depuis `adm01` : elle n'a rien à faire dans le pipeline du socle, mais elle se reconstruit entièrement par `tofu apply`.
2. **Nom et adresse** : NetBox (réservation ou allocation) et PowerDNS (module `enregistrement-dns`, ou mise à jour dynamique de Kea pour les VMs en DHCP).
3. **Ansible** : un rôle testé (`ansible-lint` profil `production`, scénario Molecule pour les rôles qui iront sur le socle : `frr`, `keepalived`, `haproxy`, `conntrackd`). La maquette se configure depuis `adm01` avec l'inventaire Proxmox (`-i inventories/lab/proxmox.yml`, groupes `env_m07`, `m07_fabric`, `m07_web`…) : l'inventaire NetBox par défaut ne contient que le socle.
4. **Flux** : une ligne dans `host_vars/gw01/pare_feu.yml` (paliers 1 et 2), puis dans `group_vars/role_routeur/pare_feu.yml` à partir de E24 : une seule matrice pour les deux passerelles.
5. **Secrets** : Vault `critique` pour ce qui permet d'usurper un équipement ou un service (clés privées WireGuard, clés TLS des répartiteurs) ; Vault `lab` pour le reste (mots de passe BGP de la maquette, page de statistiques HAProxy). Chacun au registre des secrets.
6. **Documentation** : `docs/socle/reseau/` (cartographie E02, architecture E46), `docs/socle/matrice-flux.md` (matrice des flux v2, générée en E30), runbooks, ADR, fiches de changement, dans `plateforme/medisphere`.

Une configuration à la main n'est permise que sur la maquette, pour **explorer** (annoncé comme tel dans l'énoncé), et toujours remplacée par le code avant la fin de l'exercice.

---

## Concepts clés

Une synthèse pour se repérer ; les exercices et les liens « Pour aller plus loin » approfondissent.

**Couche 2 : pont, VLAN, apprentissage.** Un pont (*bridge*) apprend sur quel port se trouve chaque adresse MAC (table FDB) et inonde ce qu'il ne connaît pas. Un VLAN 802.1Q découpe un pont en domaines de diffusion étanches : l'étiquette (12 bits) est ajoutée sur un lien *trunk* et retirée sur un port d'*accès*. `vmbr1` est un pont Linux *VLAN-aware* : le SDN de Proxmox traduit chaque VNet en un VLAN sur ce pont.

**Agrégation de liens.** Un *bond* (Linux) ou *port-channel* (commutateur) assemble plusieurs liens en un seul logique. `active-backup` : un seul lien actif, aucune coopération du voisin. `802.3ad` (LACP) : les deux extrémités négocient l'agrégat par des LACPDU ; le trafic est réparti **par flux** selon un hachage (`layer2`, `layer3+4`…) : un seul flux ne dépasse jamais la vitesse d'un lien. `miimon` surveille la porteuse ; LACP détecte aussi un voisin qui ne participe plus.

**Open vSwitch.** Un commutateur logiciel programmable : ports d'accès et *trunks*, agrégats LACP, miroirs, et surtout des **tables OpenFlow** (correspondance → actions). La règle par défaut `NORMAL` le fait se comporter comme un commutateur classique ; on peut y ajouter ses propres règles. C'est la brique de base d'OVN (OpenStack, module 10).

**Routage : la table, le plus long préfixe, la distance.** Le noyau choisit la route au **préfixe le plus long** ; à préfixe égal, la source de route la plus crédible (distance administrative : connectée, statique, eBGP 20, OSPF 110, iBGP 200) ; à égalité de coût, **ECMP** répartit les flux sur plusieurs voisins. **FRR** est la suite de démons de routage (`zebra` pour la table du noyau, `staticd`, `ospfd`, `bgpd`, `bfdd`…) pilotée par `vtysh`.

**OSPF.** Protocole à état de liens : chaque routeur annonce ses liens (LSA), tous construisent la même carte de la zone et calculent le plus court chemin (Dijkstra) ; convergence en secondes, coût par lien. Sur un lien point à point (`/31`), pas d'élection de routeur désigné.

**BGP.** Protocole à vecteur de chemins entre systèmes autonomes (AS) : chaque annonce porte un **chemin d'AS** (anti-boucle) et des attributs (*next-hop*, *local-preference*, MED…) que les **politiques** (*prefix-lists*, *route-maps*) filtrent et modifient. eBGP entre AS différents, iBGP à l'intérieur d'un AS. Depuis la RFC 8212, une session eBGP sans politique explicite n'échange **rien** : FRR l'applique par défaut (`bgp ebgp-requires-policy`). BGP est le protocole des fabrics de datacenter (RFC 7938) et celui par lequel Kubernetes annoncera ses services.

**Leaf-spine.** Chaque *leaf* (commutateur d'accès, où sont les serveurs) est relié à chaque *spine* ; aucun leaf n'est relié à un autre leaf. Tout trajet leaf → leaf fait deux sauts, avec autant de chemins égaux que de spines (ECMP) : la capacité croît en ajoutant des spines, la perte d'un spine ne coûte qu'une fraction de la bande passante.

**VRRP.** Plusieurs routeurs partagent une adresse IP virtuelle (VIP) et une adresse MAC virtuelle (`00:00:5e:00:01:<VRID>`) ; le maître (plus haute priorité) répond pour elle et l'annonce à intervalles réguliers ; si les annonces cessent, un secours prend la VIP et l'annonce par ARP gratuit. keepalived implémente VRRP (v2 et v3), suit l'état de scripts (*track_script*) et lance des scripts à chaque transition. Unicast ou multicast, préemption ou non, synchronisation de groupes : chaque choix a ses conséquences (E08, E25).

**Synchronisation d'état.** Une passerelle qui filtre avec état (nftables + conntrack) connaît chaque connexion en cours. Si le secours prend la VIP sans connaître ces connexions, il rejette leurs paquets suivants : les sessions SSH et les transferts tombent. `conntrackd` réplique la table de suivi entre les deux passerelles (E27).

**Répartition de charge.** Couche 4 (TCP : on relaie des connexions) ou couche 7 (HTTP : on lit les requêtes, on choisit un backend par nom, chemin, en-tête). HAProxy fait les deux, avec contrôles de santé, terminaison TLS, persistance, page de statistiques. Deux répartiteurs + VRRP = un point d'entrée sans point unique de défaillance.

**MTU et PMTUD.** La plus grande trame qu'un lien transporte sans fragmenter. Un paquet IPv4 trop grand avec le bit DF reçoit un ICMP « fragmentation needed » qui permet à l'émetteur de réduire sa taille (*Path MTU Discovery*). Filtrer cet ICMP, ou laisser au milieu d'un segment (un pont, un commutateur) un MTU plus petit qu'aux extrémités, donne la panne la plus déroutante du métier : les petits paquets passent, les gros se perdent. Les *jumbo frames* (9000 octets) réduisent le coût par octet pour le stockage, à condition d'être de bout en bout.

**WireGuard multisite.** Chaque pair est une clé publique, associée aux adresses qu'il a le droit d'utiliser (`AllowedIPs`, le *cryptokey routing*). Entre deux sites, on y fait passer soit des routes statiques, soit une session BGP qui annonce les réseaux autorisés de chaque côté.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | FRR 10.7 (dépôt deb.frrouting.org, suite `trixie`, composant `frr-10`) ; keepalived 2.3, Open vSwitch 3.5, nginx 1.26, wireguard-tools (paquets Debian 13) ; HAProxy 3.2 LTS (haproxy.debian.net, `trixie-backports-3.2`) |
| Changements de version | voir [`annexes/versions-bloc-B.md`](../../../annexes/versions-bloc-B.md), section « Réseau » : `bgp ebgp-requires-policy` actif par défaut, pont Linux et LACP, HAProxy 3.2, VRRP v3 et annonces unicast |
| Dépôt FRR | `deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr trixie frr-10` ; clés : `https://deb.frrouting.org/frr/keys.gpg` (trousseau de plusieurs clés) ; la clé qui signe aujourd'hui le dépôt a l'empreinte `A90F C36D 9429 4097 98E9 C2D8 74DE ED43 AB19 4DBF` ; paquets `frr` et `frr-pythontools` (rechargement à chaud par `frr-reload.py`) |
| VNets de la maquette | `vfab1` à `vfab8`, zone SDN `lab`, VLAN 901 à 908, sans sous-réseau ni passerelle ; jeton `wb-tofu@pve!tofu` : rôle `PVESDNUser` sur `/sdn/zones/lab/vfab1` … `vfab8` |
| État OpenTofu | `envs/m07-maquette/` de `plateforme/infra`, clé `envs/m07-maquette/terraform.tfstate` du compartiment `tofu-state` (chiffré, même phrase que les autres états, `outils/charger-acces.sh`) |
| Groupes d'inventaire | maquette (inventaire Proxmox, une étiquette = un groupe) : `env_m07`, `m07_labo`, `m07_fabric` (`m07_spine`, `m07_leaf`), `m07_web`, `m07_lyo`, `m07_hap` ; socle (NetBox) : `role_routeur` (`gw01`, puis `gw02`), `role_lb` (`lb01`, `lb02`) |
| Rôles Ansible du module | `frr`, `keepalived`, `nginx_web` (serveurs de démonstration), `bonding` et `ovs_labo` (laboratoires de `net01`) au palier 1 ; `haproxy`, `wireguard`, `conntrackd` ensuite |
| Molecule | `frr` et `frr_bordure` (E16) : instance 2047 ; `haproxy` (E10) : 2046 ; `keepalived` et `conntrackd` (E27) : instances 2048 et 2049 (deux VMs ; VIP d'essai de `keepalived` 10.10.99.239, VRID 198) ; plage commune 2045-2049 de `plateforme/ansible`, une instance détruite à la fin de chaque scénario |
| Secrets du palier 1 | Vault `lab`, `group_vars/m07_fabric/vault.yml` : `vault_m07_bgp_mdp_fabric` (mot de passe TCP-MD5 des sessions BGP de la maquette) |
| SSH vers la maquette | bloc `Host` dédié dans `~/.ssh/config` d'`adm01` (nom complet, compte `admin`, fichier `~/.ssh/known_hosts.m07` propre à la maquette), mêmes options pour Ansible (`group_vars/env_m07/`) |
| Documentation | `docs/socle/reseau/` (`cartographie.md` E02, `architecture.md` E46), `docs/socle/matrice-flux.md` (matrice v2 générée, E30), `docs/socle/changements/` (fiches CHG-8xx), `docs/socle/runbooks/` (RB-070 et suivants), `docs/socle/adr/` (ADR-0070 et suivants) |
| Brouillons | `~/m07/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<IP-PVE01>` | Adresse de `pve01` sur le LAN maison |
| `<LAN-MAISON>` | Ton réseau domestique (ex. 192.168.1.0/24) |
| `<IP-BOX>`, `<MASQUE>` | Adresse de ta box (passerelle du LAN maison, M00-E10) et longueur de préfixe du LAN maison (souvent 24) |
| `<IP-GW01-WAN>` | Adresse WAN actuelle de `gw01` sur le LAN maison (M00 ; ex. 192.168.1.40, valeur des fichiers du corrigé) |
| `<IP-GW02-WAN>` | Adresse WAN de `gw02` : une adresse **libre** du LAN maison, hors de la plage DHCP de ta box (palier 3, E24 ; ex. 192.168.1.41) |
| `<IP-GW-WAN-VIP>` | Adresse WAN virtuelle de la bordure : une autre adresse libre du LAN maison, hors DHCP ; elle deviendra la seule adresse WAN connue de l'extérieur (route de `pve01`, extrémité des tunnels) (palier 3, E26 ; ex. 192.168.1.50) |
| `<MOI>` | Ton compte GitLab et NetBox personnel |

Réserve dès maintenant les deux adresses libres du LAN maison (bail statique ou exclusion dans ta box) et note-les dans `lab/inventaire-local.md`.

### Variables de `lab/lab.env`

Trois variables nouvelles, utilisées par les vérifications des paliers 2 et 3 : `WB_GW01_WAN` (`<IP-GW01-WAN>`), `WB_GW02_WAN` (`<IP-GW02-WAN>`) et `WB_GW_WAN_VIP` (`<IP-GW-WAN-VIP>`). Les vérifications du palier 1 utilisent les variables existantes : `WB_PVE_HOST` (configuration Proxmox lue en root sur `pve01`), `WB_SRC` (copies de travail `~/src/infra`, `~/src/ansible`), `WB_DEPOT`, le jeton GitLab et le jeton NetBox des checks.

---

## Règles du module

1. **La bordure ne tombe pas par surprise.** Toute intervention sur `gw01`/`gw02` se fait dans un créneau annoncé, avec une fiche de changement, après un instantané (`ms-snapshot --prefix avant-m07 <VMID>`), avec la console vérifiée (`qm terminal 1000`, agent QEMU) et la commande de retour arrière **écrite avant** de commencer. Une session SSH sur la passerelle ne suffit pas : si tu coupes son réseau, tu la perds.
2. **Le réseau de `pve01` est sacré.** Seuls deux exercices y touchent : E03 (nouveaux VNets, qui régénèrent la configuration SDN) et E15 (MTU de `vmbr1`). Chacun te fait sauvegarder la configuration, vérifier le résultat attendu avant d'appliquer, et décrit le retour arrière. `vmbr0` (ton LAN) n'est jamais modifié.
3. **La maquette est jetable, pas le socle.** Tout essai à la main se fait sur les VMs 2070-2079. Une commande pensée pour la maquette ne se colle jamais sur `gw01`.
4. **Pas de LACP à travers `vmbr1`**, pas de multicast sur le LAN maison (VRRP en unicast sur la bordure).
5. **Pas de vérification TLS désactivée**, **pas de secret en argument de commande** (mots de passe BGP, clés WireGuard, mots de passe de statistiques HAProxy : fichiers en 600, Vault, entrée standard).
6. **Une seule matrice des flux** : une ouverture sur une passerelle est une ligne de `pare_feu.yml`, jamais un `nft add rule` laissé en place.
7. **Nettoie derrière toi** : la maquette est détruite à la livraison du mini-projet (E46) et se reconstruit par le code ; les instances Molecule sont détruites même en cas d'échec ; `~/m07/` ne contient aucun secret.

---

## Préparer `adm01`

Les outils viennent des modules précédents. Ce module ajoute quelques outils de diagnostic (`iperf3`, `traceroute`, `ethtool`, `nmap`), installés **par Ansible** sur le bastion (variable `base_paquets_role` de `group_vars/role_bastion/`, rôle `base` de M04). Vérifie avant de commencer :

```
admin@adm01:~$ tofu version
admin@adm01:~$ cd ~/src/ansible && uv run ansible --version | head -n 1
admin@adm01:~$ cd ~/src/ansible && uv run ansible-inventory -i inventories/lab/proxmox.yml --graph socle
admin@adm01:~$ dig +short @10.10.20.10 nbx01.par1.medisphere.internal
admin@adm01:~$ lab/bin/check 06 46
```

Le dernier contrôle (mini-projet du module 06) doit être vert : ce module s'appuie sur NetBox, PowerDNS, Kea et step-ca. S'il ne l'est pas, termine le module 06 d'abord.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 07 <XX>`. Elles sont en lecture seule : configuration Proxmox et SDN lues en root sur `pve01`, état des VMs en SSH (`sudo -n` pour ce qui est protégé, `vtysh` en lecture), questions DNS, API NetBox et GitLab en lecture, fichiers de tes copies de travail.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M07-EXX/` : `ansible/` reproduit l'arborescence de `plateforme/ansible`, `infra/` celle de `plateforme/infra`, `medisphere/` celle de la documentation, `adm01/` les fichiers personnels du bastion. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`) révèlent les causes : ne les lis pas avant d'avoir résolu. Au palier 4, `lab/bin/break 07 XX --annuler` sert aussi à **clore** une panne que tu as réparée : il ne restaure que ce qui est encore dans l'état cassé, sans écraser ta réparation.

## Ordre conseillé

Palier 1 :

```
E01 ─ E02 ─ E03 ─┬─ E04 ─ E05
                 ├─ E06 ─ E07
                 └─ E08
                          └──── E09 (en dernier)
```

1. **E01** — positionnement, à froid.
2. **E02** — la cartographie de l'existant, avant de rien construire : c'est la base de tout le module.
3. **E03** — la maquette par le code ; tous les exercices suivants en dépendent.
4. **E04 → E05** (sur `net01`), **E06 → E07** (fabric) et **E08** (VRRP) sont indépendants : mène-les dans l'ordre qui te convient.
5. **E09** — en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 16 à 20 heures. Le module complet : voir le [README](../README.md) (paliers 2 à 5 : répartiteurs, fabric BGP *unnumbered*, MTU, LYO1, bordure redondante, pannes, mini-projet).

## Pour aller plus loin

- FRR : <https://docs.frrouting.org/en/latest/> — en particulier « BGP », « OSPFv2 », « Zebra », et « Basic Setup » (fichier `daemons`, configuration intégrée, `frr-reload.py`).
- keepalived : <https://keepalived.readthedocs.io/> et la page de manuel `keepalived.conf(5)`.
- Open vSwitch : <https://docs.openvswitch.org/en/latest/> (tutoriels « VLANs », « Port mirroring », « Link aggregation »).
- Bonding Linux : <https://www.kernel.org/doc/html/latest/networking/bonding.html>.
- SDN de Proxmox VE : <https://pve.proxmox.com/pve-docs/chapter-pvesdn.html>.
- RFC 4271 (BGP-4), RFC 7938 (BGP dans les grands datacenters), RFC 8212 (politiques eBGP par défaut), RFC 2328 (OSPFv2), RFC 3021 (préfixes /31), RFC 9568 (VRRP v3 ; elle remplace la RFC 5798, que certains exercices citent encore pour ses numéros de section), IEEE 802.1AX (agrégation de liens), RFC 1191 et RFC 8899 (découverte du MTU).
