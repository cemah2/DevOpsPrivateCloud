# Module 09 — Introduction : le cluster de virtualisation

## Un hyperviseur, c'est un point de panne

Lundi, 8 h 45. Le stockage distribué du module 08 tient ses promesses : `ceph-par1` a perdu un OSD vendredi soir et personne ne l'a remarqué avant le rapport du matin. Claire Morel en tire la conséquence logique et envoie le programme suivant.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel
> **Objet** : Virtualisation — fini l'hyperviseur unique
>
> Bonjour,
>
> Tout PAR1 tourne sur `pve01`. Une carte mère qui lâche, une mise à jour du noyau qui tourne mal, et c'est le site entier qui s'arrête : forge, DNS, PKI, sauvegardes. Le stockage est désormais redondant ; la virtualisation ne l'est pas.
>
> Pour la production, je veux un **cluster** de virtualisation :
> 1. des nœuds installés **sans clavier**, depuis le code, reconstruisibles en une heure ;
> 2. un cluster qui garde la tête froide quand un nœud ou un lien tombe : quorum, liens redondants, **pas de split-brain** ;
> 3. un stockage partagé (Ceph, le nôtre et un Ceph intégré au cluster), de la réplication pour ce qui reste local, des sauvegardes hors site ;
> 4. la **haute disponibilité** : une VM dont le nœud meurt redémarre ailleurs, toute seule, et on sait en combien de temps ;
> 5. des mises à jour sans interruption de service, une montée de version de Ceph, des droits, de la double authentification, une supervision.
>
> Pour le lab, on n'achète pas trois serveurs : le cluster sera **imbriqué**, trois nœuds Proxmox VE virtuels sur `pve01`. Les contraintes sont les mêmes qu'en vrai, la mémoire en moins. InfoGér avait un « cluster » Proxmox à deux nœuds sans arbitre, dont le quorum se forçait à la main un dimanche sur deux : on ne reproduit pas ça.
>
> Nadia veut des runbooks pour la perte d'un nœud et la maintenance ; Sophie veut pare-feu, 2FA et traçabilité sur l'interface du cluster ; Karim fera ses revues comme d'habitude. Premier jalon : deux nœuds installés par le code, en cluster, avec un arbitre ; puis un troisième. Karim te fait d'abord passer le test.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 09, le dépôt `plateforme/medisphere` porte l'étiquette **`virtualisation-v1`** : le cluster `hv-par1` a été reconstruit depuis le code et recetté (mini-projet M09-E46), puis détruit pour libérer la mémoire de `pve01` ; tout ce qu'il faut pour le recréer reste dans les projets.

- **Nœuds** `hv01`, `hv02`, `hv03` : Proxmox VE 9.2 installé par l'**installateur automatique** (fichier de réponse), VMs créées par OpenTofu (état `hv`), configuration par le rôle Ansible `pve_noeud`.
- **Cluster** `hv-par1` : Corosync sur deux liens (réseau dédié + MGMT), phase à deux nœuds arbitrée par un **QDevice** sur `pbs01` (site PAR2), puis trois nœuds.
- **Stockage** : ZFS local répliqué, **Ceph hyperconvergé** (`pveceph`, Squid puis Tentacle), consommation du Ceph externe `ceph-par1` du module 08, sauvegardes **PBS** sur `pbs01`.
- **Services du cluster** : HA par **règles** (Proxmox VE 9), migration à chaud sur un réseau dédié, SDN (VLAN puis EVPN), droits et jetons, pilotage par OpenTofu et Ansible, VIP d'API `hv.par1.medisphere.internal`.
- **Exploitation** : mises à jour progressives, montée de version de Ceph, sécurité (pare-feu, 2FA, ACME), supervision, runbooks RB-090 à RB-092, ADR-0090.

Le **palier 1** (ce fichier et `01-decouverte.md`) pose le socle : préparer `pve01` pour la virtualisation imbriquée (E02), installer deux nœuds sans clavier (E03), former le cluster (E04), lui donner un arbitre (E05), ses stockages locaux et son réseau d'invités (E06), y faire tourner et migrer les premières VMs (E07), puis passer à trois nœuds (E08).

## Architecture du module

```
  pve01 (PAR1, Proxmox VE 9, physique) ── vmbr1 VLAN-aware, MTU 9000, sans port physique
  │
  │  VNets de la zone SDN « lab » (une carte = un VLAN, sans étiquette côté nœud)
  │    vmgmt (10)  vcoro (32)  vstopub (30, MTU 9000)  vstoclu (31, MTU 9000)   + vmbr1 trunks=99
  │        │           │             │                       │                      │
  ├─ hv01 (2091) ──────┼─────────────┼───────────────────────┼──────────────────────┤
  │   nic0→vmbr0 10.10.10.51   nic1 10.10.32.51   nic2 10.10.30.71   nic3 10.10.31.71   nic4→vmbr1 (VLAN-aware)
  ├─ hv02 (2092) ── mêmes cartes, .52 / .52 / .72 / .72
  └─ hv03 (2093) ── mêmes cartes, .53 / .53 / .73 / .73        (E08)
         │
         │  Dans chaque nœud (Proxmox VE 9.2, 4 vCPU « host », 12 Go) :
         │   ┌────────────────────────────────────────────────────────────────────────┐
         │   │ pmxcfs (/etc/pve) ◄── Corosync knet : lien 0 = nic1 (COROSYNC)          │
         │   │                                       lien 1 = vmbr0 (MGMT, secours)    │
         │   │ invités imbriqués 100-199 ── vmbr1, VLAN 99 ── DHCP Kea du socle        │
         │   │ disques : scsi0 système (local-nvme) · scsi1-2 OSD (ssd-lab) · scsi3 ZFS│
         │   └────────────────────────────────────────────────────────────────────────┘
         │
         │ TCP 5403 (E05 : phase à deux nœuds)              gw01/gw02 ═══ wg0 ═══╗
         └──────────────────────────────────────────────────────────────────────╫──► pbs01 (PAR2)
                                                                                 ║   10.20.10.10
                                                         corosync-qnetd (arbitre) + PBS (ds-lab, par1/hv)
```

Points structurants :

- **Trois niveaux de virtualisation.** `pve01` exécute les nœuds `hvNN` (des VMs au CPU `host`), qui exécutent les invités imbriqués. Tout ce que `pve01` ne laisse pas passer (instructions VMX, VLAN, adresses MAC, MTU) manque au niveau du dessous. L'exercice E02 vérifie chacun de ces points avant d'installer quoi que ce soit.
- **Le réseau du cluster est le réseau du lab.** Chaque carte d'un nœud est branchée sur un VNet existant de `pve01` : le nœud n'étiquette rien, `pve01` fait le travail. Seule la cinquième carte est un *trunk* (VLAN 99 autorisé) : les invités imbriqués étiquettent eux-mêmes leurs trames dans le pont `vmbr1` du nœud.
- **Le quorum se gagne à PAR2.** À deux nœuds, aucun ne peut avoir la majorité seul : l'arbitre (QDevice) est sur `pbs01`, de l'autre côté du tunnel `wg0`. À trois nœuds, il devient inutile et on le retire (E08).

### Hôtes et adresses du module

| Hôte | VMID | MGMT (vmbr0) | COROSYNC (nic1) | Ceph public (nic2) | Ceph cluster (nic3) | Exercice |
|---|---|---|---|---|---|---|
| `hv01` | 2091 | 10.10.10.51 | 10.10.32.51 | 10.10.30.71 | 10.10.31.71 | E03 |
| `hv02` | 2092 | 10.10.10.52 | 10.10.32.52 | 10.10.30.72 | 10.10.31.72 | E03 |
| `hv03` | 2093 | 10.10.10.53 | 10.10.32.53 | 10.10.30.73 | 10.10.31.73 | E08 |
| VIP de l'API du cluster | — | 10.10.10.200 (`hv.par1.medisphere.internal`, VRID 110) | — | — | — | palier 2 |
| QDevice | — | `pbs01` 10.20.10.10, TCP 5403 | — | — | — | E05 (retiré en E08) |

Chaque nœud : 4 vCPU (type `host`), 12 Go sans ballon, disque système 32 Go sur `local-nvme`, deux disques de 48 Go (futurs OSD) et un de 32 Go (pool ZFS `tank`) sur `ssd-lab`, cinq cartes virtio aux adresses MAC fixes `02:4d:53:09:NN:0K` (nœud `NN`, carte `K`). Étiquettes Proxmox `env-m09` et `hv-par1`, pool `lab`.

**Invités imbriqués** (à l'intérieur du cluster, VMID indépendants de ceux de `pve01`) : template `tpl-nested-debian13` en **199** ; invités de test en 100-198 (`app01` = 101, `app02` = 102 au palier 1). Ils vivent sur le VLAN 99 (DHCP de Kea, 10.10.99.100-199) : `adm01` les joint comme n'importe quelle VM du bac à sable.

**VM jetable de `pve01`** : 2099 `m09-essai` (test de la virtualisation imbriquée, E02), détruite dans la foulée.

### Budget mémoire

| Ce qui tourne | Mémoire | Quand |
|---|---|---|
| Socle v2 (`gw01`, `gw02`, `adm01`, `dns01`, `dns02`, `ca01`, `git01`, `runner01`, `nbx01`, `s3-01`, `lb01`, `lb02`) | ≈ 27 Go | toujours |
| `hv01`, `hv02` | 24 Go | à partir de E03 |
| `hv03` | 12 Go | à partir de E08 |
| `ceph01-03` (module 08) | 18 Go | **seulement** pendant M09-E12 (Ceph externe) |
| **Total** | ≈ 63 Go (81 Go pendant E12) | sur les 128 Go de `pve01` |

À l'intérieur d'un nœud (12 Go) : Proxmox VE ≈ 1,5 Go, Ceph hyperconvergé (MON, MGR, 2 OSD à `osd_memory_target` = 1 Gio) ≈ 4 Go à partir de E10, ARC de ZFS plafonné à 1 Gio ; il reste 4 à 5 Go pour les invités imbriqués (512 Mo à 1 Go chacun). Un invité de plus que prévu ne casse rien tout de suite : il fait swapper un nœud, puis Ceph ralentit, puis Corosync rate des battements. Surveille `free -h` sur les nœuds.

### Flux du palier 1

| Flux | Port | Exercice | État |
|---|---|---|---|
| `adm01` → nœuds (SSH, interface web, API) | 22, 8006 | E03 | existant : même VLAN (MGMT), sans passerelle |
| nœuds → `dns01`/`dns02`, passerelle (DNS, NTP) | 53, 123 | E03 | existant (règles DNS de M06-E24, NTP de M00-E31) |
| nœuds → Internet (dépôts Proxmox et Debian, image cloud) | 80, 443 | E03, E06 | existant (« lab vers Internet ») |
| nœuds ↔ nœuds (Corosync, SSH, migration) | UDP 5405-5412, 22, 60000-60050 | E04, E07 | même VLAN : rien à ouvrir sur la bordure |
| nœuds → `pbs01` (QDevice) | TCP 5403 | E05 | **nouveau** : matrice (`pare_feu.yml`) et pare-feu de `pbs01` ; retiré en E08 |
| invités imbriqués (VLAN 99) → DHCP, DNS, Internet | 67, 53, 80, 443 | E06, E07 | existant (bac à sable) |

---

## Le chemin imposé

Le chemin des modules 05 et 06, adapté à des VMs qui ne sont **pas** des clones de l'image dorée :

1. **OpenTofu** : les nœuds sont déclarés dans l'état **`hv`** de `plateforme/infra` (dossier `envs/hv/`, état chiffré sur `s3-01`), qui crée aussi leur fiche NetBox (VM, interfaces, adresses imposées) et leurs noms dans PowerDNS (module `enregistrement-dns`). Plan relu, `apply` par le pipeline ou, pour cet environnement de module, depuis `adm01` comme les autres `envs/` (`CONTRIBUTING.md`, M05-E26).
2. **Installation** : l'ISO officielle de Proxmox VE 9.2, vérifiée par sa signature, est **préparée** pour chaque nœud avec son fichier de réponse (`proxmox-auto-install-assistant`) ; le modèle du fichier de réponse et le script de préparation sont versionnés dans `envs/hv/installation/`. Aucune installation au clavier.
3. **Ansible** : le rôle `pve_noeud` (nouveau, `plateforme/ansible`) configure chaque nœud ; `medisphere.socle.ca_lab` (racine de la PKI) et `ssh_ca_hote` (certificat SSH d'hôte, M06-E19) s'y appliquent comme au socle. Inventaire statique `inventories/lab/hv.yml`, combiné à l'inventaire NetBox.
4. **Le cluster lui-même** (création, adhésion, QDevice) se construit à la main au palier 1, une commande à la fois, pour comprendre. Il passe dans le code au palier 2 (M09-E18) et la recette le reconstruit d'un bout à l'autre (M09-E46).
5. **Secrets** : mot de passe root des nœuds en Vault `critique` et dans `~/.config/workbook/hv-root.pass` (600) ; inscrits au registre des secrets.
6. **Documentation** : matrice des flux, inventaire, fiches de changement (`CHG-10xx`), runbooks RB-090 et suivants, ADR-0090.

Une manipulation à la main hors de ce chemin n'est permise que dans le cluster imbriqué lui-même (c'est son rôle) ou sur la VM jetable 2099, et elle est annoncée comme telle dans l'énoncé.

---

## Concepts clés

Une synthèse pour se repérer ; les exercices et les liens « Pour aller plus loin » approfondissent.

**Virtualisation imbriquée.** Un hyperviseur KVM a besoin des extensions matérielles (VT-x/VMX chez Intel, AMD-V/SVM chez AMD). Une VM ordinaire ne les voit pas : son CPU virtuel est un modèle générique. Pour qu'une VM puisse elle-même faire tourner des VMs accélérées, il faut que le noyau de l'hôte autorise l'imbrication (paramètre `nested` du module `kvm_intel`) **et** que la VM reçoive un CPU qui expose VMX (type `host`). Les performances sont correctes pour le calcul, moins pour les entrées-sorties : deux couches de virtio, deux caches.

**Cluster Proxmox VE.** Un ensemble de nœuds qui partagent leur configuration (VMs, stockages, droits, pare-feu) et s'administrent depuis n'importe lequel d'entre eux. Trois pièces : **Corosync** (communication de groupe et appartenance), **pmxcfs** (le système de fichiers `/etc/pve`, base SQLite répliquée par Corosync sur chaque nœud) et les services qui lisent `/etc/pve` (interface web, API, gestionnaire HA).

**Corosync et knet.** Corosync 3 transporte ses messages par **kronosnet** (knet) : jusqu'à huit **liens** par nœud, chiffrés et authentifiés, sur UDP. Un lien n'est pas un réseau « de secours » passif : knet surveille chaque lien en continu et bascule au premier signe de perte, sans que le cluster s'en aperçoive. Corosync est **sensible à la latence**, pas au débit : un lien saturé par une migration ou une réplication Ceph fait rater des battements et peut exclure un nœud. D'où un réseau dédié (VLAN 32), et un second lien sur un autre réseau.

**Quorum.** Chaque nœud a un vote ; une partition du cluster ne peut agir (démarrer une VM, modifier `/etc/pve`) que si elle détient la **majorité stricte** des votes attendus. C'est ce qui empêche deux moitiés isolées de démarrer chacune la même VM sur le même disque (*split-brain*). Sans quorum, `/etc/pve` passe en **lecture seule** et la HA ne redémarre rien. Conséquence arithmétique : à deux nœuds, la perte de l'un fait perdre le quorum à l'autre. On ajoute un vote externe (**QDevice** : `corosync-qnetd` sur une machine tierce, ici `pbs01`) ou un troisième nœud.

**Haute disponibilité et fencing.** Le gestionnaire HA de Proxmox VE redémarre ailleurs les VMs d'un nœud perdu. Mais il ne peut le faire que s'il est **certain** que le nœud perdu ne les fait plus tourner : sinon, deux exemplaires écriraient sur le même disque. Cette certitude vient du **fencing** : un nœud qui perd le quorum s'arrête lui-même au bout d'un délai, garanti par un **watchdog** (matériel, ou `softdog` dans le noyau). Les VMs du nœud perdu ne redémarrent ailleurs qu'après ce délai. Au palier 2, les **règles HA** de Proxmox VE 9 (affinité de nœuds et de ressources) remplacent les anciens groupes HA.

**Stockage partagé, local, répliqué.** Une migration à chaud déplace la mémoire de la VM ; si le disque est sur un stockage **partagé** (Ceph RBD, NFS…), il n'a pas à bouger, et la HA peut redémarrer la VM ailleurs. Sur un stockage **local** (LVM-thin, ZFS d'un nœud), la migration copie aussi le disque (long), et la HA ne peut rien pour une VM dont le disque est mort avec son nœud — sauf **réplication** ZFS périodique vers un autre nœud, au prix d'une perte des dernières minutes. Proxmox VE dit « partagé » d'un stockage déclaré `shared` : il croit ce qu'on lui dit, à toi de dire vrai.

**Ceph hyperconvergé.** Les nœuds de virtualisation portent aussi les OSD, MON et MGR de Ceph (`pveceph`). Moins de machines, mais calcul et stockage se disputent CPU, mémoire et réseau, et la perte d'un nœud fait perdre en même temps des VMs et des OSD. Le module 08 t'a appris Ceph par `cephadm` ; ici, c'est Proxmox VE qui l'installe et le pilote, en paquets.

**SDN.** Le SDN de Proxmox VE décrit les réseaux des invités au niveau du **cluster** : zones (VLAN, VXLAN, EVPN…), VNets, sous-réseaux, IPAM. Tu l'utilises sur `pve01` depuis le module 00 (zone `lab`) ; au palier 2, le cluster aura le sien, jusqu'à un réseau EVPN interne.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | Proxmox VE **9.2** (Debian 13), ISO `proxmox-ve_9.2-1.iso` ; Corosync 3 (knet) ; Ceph hyperconvergé **Squid 19.2** puis **Tentacle 20.2** (E28) ; PBS 4.x sur `pbs01` |
| Changements de version | voir [`annexes/versions-bloc-B.md`](../../../annexes/versions-bloc-B.md), section « Cluster de virtualisation » : HA *rules* au lieu des groupes, clés *kebab-case* du fichier de réponse, Tentacle par défaut en 9.2 (le module installe Squid **exprès**), `VM.PowerMgmt` requis au démarrage après création |
| Installation | `proxmox-auto-install-assistant` (paquet de Proxmox, installé sur `pve01`) ; mode **`--fetch-from iso`** : une ISO par nœud, `hdd-bulk:iso/pve92-auto-hvNN.iso`, fichier de réponse intégré (adresse statique, aucun DHCP sur MGMT) ; modèle et script : `plateforme/infra`, `envs/hv/installation/` |
| État OpenTofu | `plateforme/infra`, `envs/hv/` : clé `envs/hv/terraform.tfstate`, chiffrement de M05-E27 ; fournisseurs `bpg/proxmox` `~> 0.116.0` (API de **`pve01`**, jeton `wb-tofu@pve!tofu`), `e-breuninger/netbox` `~> 5.8.0`, `mmianl/powerdns` `~> 2.5.0` ; données des nœuds dans `noeuds.auto.tfvars.json` (lu aussi par le script de préparation des ISO) |
| Disques des nœuds | numéros de série fixes : `hvNN-systeme`, `hvNN-osd1`, `hvNN-osd2`, `hvNN-zfs`, visibles dans le nœud sous `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_<série>` |
| Cartes des nœuds | `nic0` à `nic4` (noms épinglés par l'installateur sur les MAC `02:4d:53:09:NN:0K`) ; `vmbr0` sur `nic0` (MGMT) ; `vmbr1` VLAN-aware sur `nic4` (invités) |
| Ansible | rôle `pve_noeud` ; inventaire `inventories/lab/hv.yml` (groupe `hv_par1`, connexion **root**) combiné à `netbox.yml` ; playbook `playbooks/hv.yml` (rôles `medisphere.socle.ca_lab`, `pve_noeud`, `ssh_ca_hote`, un nœud à la fois) |
| Cluster | `hv-par1` ; lien 0 = COROSYNC (10.10.32.0/24), lien 1 = MGMT (10.10.10.0/24) |
| QDevice (E05 → E08) | `corosync-qnetd` sur `pbs01` (paquet Debian), TCP 5403 ; `corosync-qdevice` sur les nœuds ; algorithme `ffsplit` |
| Stockages du palier 1 | `local` (contenus ajoutés : `import`, `snippets`), `local-lvm` (installation), `zfs-local` (pool `tank` sur le disque `hvNN-zfs`, même nom sur chaque nœud) |
| Secrets du palier 1 | Vault `critique` : `vault_hv_root_mot_de_passe` (`group_vars/hv_par1/vault-critique.yml`) ; sur `adm01` : `~/.config/workbook/hv-root.pass` (600), ancre TLS du cluster `~/.config/workbook/hv-par1-root-ca.pem` (publique) |
| Documentation | `docs/socle/` de `plateforme/medisphere` : inventaire, matrice des flux, `changements/CHG-1005-qdevice-pbs01.md` ; runbooks RB-090 et suivants, ADR-0090 aux paliers suivants |
| Brouillons | `~/m09/eXX/` sur `adm01` (non versionnés) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` (son `hostname`) |
| `<MOI>` | Ton compte personnel (GitLab, NetBox ; au palier 2, ton compte `<MOI>@pve` du cluster) |
| `<VMID-CURRENT>` | VMID du template doré Debian 13 étiqueté `current` (M03) |

### Variables de `lab/lab.env`

Rien de nouveau. Les vérifications utilisent `WB_PVE_HOST` (configuration des VMs 2091-2093 lue en root sur `pve01`), `WB_PBS_HOST` (état du QDevice sur `pbs01`, en lecture), `WB_SRC` (copies de travail `~/src/infra`, `~/src/ansible`, `~/src/images`), `WB_DEPOT`, le jeton GitLab et le jeton NetBox des checks. Elles joignent les nœuds en root par leurs alias SSH `hv01`, `hv02`, `hv03` (voir plus bas).

---

## Règles du module

1. ⚠️ **`pve01` ne se modifie pas sans avertissement.** Le module touche à `pve01` en quatre endroits seulement, chacun annoncé dans l'énoncé avec son retour arrière : le paquet de préparation des ISO (E02), un droit de `wb-tofu@pve` (E02), l'ISO sur `hdd-bulk` (E02, E03), et les VMs 2091-2093 (par OpenTofu). Jamais son réseau (`vmbr0`, `vmbr1`, routes), jamais son pare-feu de centre de données, jamais son noyau sans fenêtre de maintenance.
2. **Un seul profil lourd à la fois.** Les VMs `ceph01-03` du module 08 restent **arrêtées** pendant tout le module, sauf pendant M09-E12. Pas de profil `openstack` ou `k8s` en parallèle.
3. ⚠️ **`pbs01` est le serveur de sauvegarde du site.** Il n'accueille le QDevice que le temps de la phase à deux nœuds (E05 → E08), par une fiche de changement. Aucun script de panne ne le touche, jamais. Toute intervention sur `pbs01` se fait hors de la fenêtre des sauvegardes nocturnes.
4. **Les nœuds se configurent par le code.** Réseau, dépôts, temps, SSH : rôle `pve_noeud`. Le réseau d'un nœud ne se modifie pas dans l'interface web (le prochain passage d'Ansible l'écraserait, et un `vmbr0` mal saisi coupe le nœud).
5. **Pas de vérification TLS désactivée** : ni `curl -k`, ni `--insecure`, ni `insecure = true`. Jusqu'aux certificats ACME (M09-E26), l'API d'un nœud se joint avec l'ancre du cluster (`--cacert ~/.config/workbook/hv-par1-root-ca.pem`).
6. **Un secret ne passe jamais en argument de commande.** Le mot de passe root des nœuds se lit dans son fichier ou se tape au clavier (`pvecm add` le demande) ; son empreinte seule va dans le fichier de réponse.
7. **Accès de secours vérifié avant toute intervention réseau sur un nœud** : console série (`qm terminal <VMID>` sur `pve01`, après E03) ou console noVNC de l'interface de `pve01`.
8. **Nettoie derrière toi** : la VM 2099 est détruite dans la foulée ; les invités imbriqués de test le sont quand un exercice le demande ; le cluster entier l'est en fin de module.

## Accéder aux nœuds

- **SSH** : en `root`, par clé (la clé de `adm01` est posée par le fichier de réponse) ; jamais par mot de passe (le rôle `pve_noeud` le refuse). Alias de `~/.ssh/config` sur `adm01` : `hv01`, `hv02`, `hv03` → `HostName` 10.10.10.51-53, `User root`. Après le premier passage d'Ansible, chaque nœud présente un **certificat d'hôte** signé par la CA SSH de `ca01` (rôle `ssh_ca_hote`) ; la ligne `@cert-authority` de M06-E19 (motif `10.10.*`) suffit alors. Avant, la première connexion se vérifie par l'empreinte lue sur la console du nœud.
- **Interface web** : `https://hvNN.par1.medisphere.internal:8006`, compte `root@pam` au palier 1 (comptes nominatifs au palier 2). Certificat de la CA propre au cluster jusqu'à M09-E26 : importe `hv-par1-root-ca.pem` dans le magasin de ton navigateur plutôt que d'accepter une exception.
- **Console de secours** : `root@pve01:~# qm terminal 2091` (console série, `Ctrl+O` pour sortir), ou la console noVNC de la VM dans l'interface de `pve01`.

---

## Préparer `adm01`

Les outils viennent des modules précédents. Vérifie avant de commencer :

```
admin@adm01:~$ tofu version
admin@adm01:~$ cd ~/src/ansible && uv run ansible --version | head -n 1
admin@adm01:~$ dig +short @10.10.20.10 pbs01.par2.medisphere.internal
admin@adm01:~$ ssh pbs01 'proxmox-backup-manager versions' | head -n 1
admin@adm01:~$ lab/bin/check 08 46
```

Le dernier contrôle (mini-projet du module 08) doit être vert : M09-E12 consomme `ceph-par1`. Si tu as choisi de ne faire que certains exercices du module 08, vérifie au moins que `ceph-par1` redémarre proprement après un arrêt complet (procédure du module 08), puis arrête `ceph01-03`.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 09 <XX>`. Elles sont en lecture seule : configuration des VMs 2091-2093 lue en root sur `pve01`, état des nœuds en root par SSH (`pvecm`, `corosync-cfgtool`, `pvesh get`, `zpool`), état du QDevice sur `pbs01`, DNS, NetBox, fichiers de tes copies de travail, API GitLab en lecture.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M09-EXX/` : `infra/` reproduit l'arborescence de `plateforme/infra`, `ansible/` celle de `plateforme/ansible`, `images/` celle de `plateforme/images`, `outils/` celle de `plateforme/outils`, `medisphere/` celle de la documentation.
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu. Ils n'agissent qu'**à l'intérieur** du cluster imbriqué et sur les VMs 2091-2093 ; jamais sur `pbs01`, jamais sur le réseau de `pve01`.

## Ordre conseillé (palier 1)

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─┬─ E06 ─ E07 ─┬─ E08 ─ E09
                             └─────────────┘
```

1. **E01** — positionnement, à froid.
2. **E02 → E03** — rien ne s'installe tant que `pve01` n'a pas prouvé qu'il sait imbriquer et que l'ISO n'est pas vérifiée.
3. **E04 → E05** — le cluster, puis son arbitre. Fais E05 dans un créneau calme pour `pbs01` (pas pendant les sauvegardes).
4. **E06 → E07** — stockages, template, premières VMs et migrations. E06 peut commencer dès E04 ; E07 profite d'avoir le QDevice (un nœud éteint ne fige pas l'autre).
5. **E08** — le troisième nœud, après E06 (son pool `tank` s'ajoute au stockage déjà déclaré).
6. **E09** — en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 15 à 18 heures.

## Pour aller plus loin

- Guide d'administration de Proxmox VE 9 : <https://pve.proxmox.com/pve-docs/pve-admin-guide.html>, en particulier « Cluster Manager » (`pvecm`), « Proxmox Cluster File System » (pmxcfs) et « High Availability ».
- Installation automatisée : <https://pve.proxmox.com/wiki/Automated_Installation>
- Virtualisation imbriquée : <https://pve.proxmox.com/wiki/Nested_Virtualization>
- Corosync et kronosnet : `man corosync.conf`, `man votequorum`, `man corosync-qdevice` ; <https://kronosnet.org/>
- Feuille de route et notes de version : <https://pve.proxmox.com/wiki/Roadmap>
