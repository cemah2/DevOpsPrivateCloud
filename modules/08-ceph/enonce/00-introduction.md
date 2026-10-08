# Module 08 — Introduction : le stockage distribué

## Plus jamais un seul disque

Lundi, 8 h 50. Le socle v2 est en service : deux passerelles en VRRP, deux répartiteurs, des réseaux de stockage en *jumbo frames* qui n'attendent que leur premier octet. Claire Morel a convoqué l'équipe pour la suite.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel
> **Objet** : Stockage — on arrête de confier nos données à un seul disque
>
> Bonjour,
>
> Le rapport de l'auditeur HDS est arrivé vendredi. Trois remarques concernent le stockage hérité d'InfoGér, et je les cite :
> - « les serveurs applicatifs stockent les données patients sur leurs disques locaux, sans réplication ; la perte d'un disque entraîne une perte de données jusqu'à la dernière sauvegarde nocturne » ;
> - « le NAS partagé constitue un point unique de défaillance ; il n'est ni chiffré ni cloisonné par application » ;
> - « aucune procédure n'existe pour le remplacement d'un disque ou l'extension de capacité ».
>
> La suite du bloc va en ajouter : le cluster Proxmox (M09), OpenStack (M10) puis Kubernetes auront besoin d'un stockage **partagé**, **redondant** et **extensible** : disques de VMs, volumes persistants, et les documents patients de MédiDoc en stockage objet. J'ai retenu **Ceph**. C'est exigeant, mais c'est le standard du cloud privé, et il couvre les trois besoins (bloc, fichier, objet) avec un seul système.
>
> Ce que je veux à la fin du module :
> 1. un cluster **`ceph-par1`** de trois nœuds, déployé par **cephadm** et décrit par le code (spécifications versionnées dans un projet `plateforme/ceph`) ;
> 2. du stockage **bloc** (RBD), **fichier** (CephFS, NFS) et **objet** (S3 par la passerelle RGW, publiée en HTTPS) ;
> 3. des pools pensés : réplication ou codes d'effacement, classes de disques, domaines de panne ; des accès **cephx** minimaux, par équipe ;
> 4. l'exploitation : ajouter un nœud, remplacer un disque, suivre la capacité, monter de version sans interruption, superviser, sauvegarder hors du cluster ;
> 5. des pools et des clés prêts pour OpenStack et Kubernetes.
>
> Karim rappelle la règle : « une VM, c'est OpenTofu ; une configuration, c'est un rôle Ansible testé ; un flux, c'est une ligne dans la matrice ; un cluster Ceph, ce sont des spécifications dans Git ». Sophie veut le chiffrement et des accès cloisonnés par équipe. Nadia veut savoir ce qui se passe quand un disque ou un nœud tombe, à 3 h du matin, et qui fait quoi.
>
> Premier jalon : trois nœuds préparés, un cluster amorcé, des OSD, un premier pool, une première image RBD. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 08, MédiSphère a son stockage **v1** (étiquette `stockage-v1` du dépôt `plateforme/medisphere`), consommé ensuite par OpenStack (M10) et Kubernetes (M16) :

- **`ceph-par1`** : Ceph **Tentacle 20.2** déployé par **cephadm** (conteneurs Podman) sur trois nœuds **Rocky Linux 10**, `ceph01-03`, avec un réseau public (VLAN 30) et un réseau de réplication (VLAN 31) en MTU 9000 ; 3 moniteurs, 2 gestionnaires, 9 OSD répartis en deux classes de disques (`ssd`, `hdd`) ;
- le **bloc** (RBD), le **fichier** (CephFS, exports NFS) et l'**objet** (RGW derrière un point d'entrée haute disponibilité, `rgw.par1.medisphere.internal`, en HTTPS) ;
- les spécifications cephadm dans le projet GitLab **`plateforme/ceph`**, appliquées par un pipeline ;
- la supervision, la sauvegarde hors du cluster, la montée de version en 20.2.4, le chiffrement, la politique de stockage, l'ADR-0080, les runbooks RB-080 et suivants.

Le **palier 1** (ce fichier et `01-decouverte.md`) prépare les nœuds par le code, amorce le cluster, déploie les OSD par spécification, crée un premier pool et une première image RBD consommée par un client, puis apprend à lire l'état d'un cluster. Un détour par **ZFS** rappelle ce qu'est un stockage local bien fait, pour mieux voir ce que Ceph change.

## Architecture du module

```
                       adm01 (1001) 10.10.10.10 — VLAN 10 MGMT : joint tout le lab (SSH, API)
                       ~/src/infra (envs/ceph) · ~/src/ansible · ~/src/ceph · checks
                                       │
   ════════════════════════ gw01 / gw02 (VIP .1, VRRP) — routage, filtrage, NTP ═════════════════════
                                       │
  VLAN 30 STOR-PUB 10.10.30.0/24 · MTU 9000 · passerelle 10.10.30.1 (clients ↔ MON, OSD, RGW, MDS)
  ─────┬───────────────────────────┬───────────────────────────┬────────────────────────┬────────────
       │ .51                       │ .52                       │ .53                    │ .20
  ┌────┴────────────────┐  ┌───────┴─────────────┐  ┌──────────┴──────────┐   ┌─────────┴─────────┐
  │ ceph01 (2081)       │  │ ceph02 (2082)       │  │ ceph03 (2083)       │   │ cephcli01 (2085)  │
  │ Rocky 10 · Podman   │  │ Rocky 10 · Podman   │  │ Rocky 10 · Podman   │   │ Debian 13         │
  │ MON  MGR(actif)     │  │ MON  MGR(attente)   │  │ MON                 │   │ ceph-common (rbd) │
  │ OSD×3 crash         │  │ OSD×3 crash         │  │ OSD×3 crash         │   │ ZFS (E08)         │
  │ (palier 2 : MDS,    │  │ (RGW, ingress)      │  │ (RGW, ingress)      │   └───────────────────┘
  │  NFS…)              │  │                     │  │                     │
  │ sdb ssd │sdc ssd│sdd│  │ sdb ssd │sdc ssd│sdd│  │ sdb ssd │sdc ssd│sdd│   sdb, sdc : 64 Gio sur ssd-lab
  │  64 Gio │64 Gio │hdd│  │                     │  │                     │   sdd      : 64 Gio sur hdd-bulk
  └────┬────────────────┘  └───────┬─────────────┘  └──────────┬──────────┘
       │ .51                       │ .52                       │ .53
  ─────┴───────────────────────────┴───────────────────────────┴──────────────────────────────────────
  VLAN 31 STOR-CLU 10.10.31.0/24 · MTU 9000 · NON ROUTÉ (réplication, récupération, battements de cœur des OSD)

  ceph04 (2084, .54) : quatrième nœud, de M08-E18 (extension) à la fin du module, puis détruit.
```

Points structurants :

- **Deux réseaux.** Les clients et les moniteurs parlent sur le réseau **public** (VLAN 30). Les OSD répliquent entre eux sur le réseau **cluster** (VLAN 31), non routé : une écriture cliente de 1 Mio en produit 2 de plus sur ce réseau (3 copies). Les deux sont en MTU 9000 depuis M07-E15 ; une seule carte à 1500 sur le chemin, et les gros transferts se bloquent.
- **cephadm orchestre, Podman exécute.** Aucun paquet de démon Ceph n'est installé sur les nœuds : chaque démon est un conteneur de l'image `quay.io/ceph/ceph:v20.2.3`, lancé par une unité systemd que cephadm écrit. Le module `cephadm` du gestionnaire actif se connecte en SSH aux nœuds (compte `cephadm`, sudo) pour déployer, reconfigurer, mettre à jour.
- **Le cluster décrit par le code.** Ce que cephadm doit faire tourner (hôtes, moniteurs, gestionnaires, OSD, puis RGW, MDS, NFS…) est écrit dans des **spécifications** YAML versionnées dans `plateforme/ceph` et appliquées par `ceph orch apply -i`. cephadm converge en permanence vers ces spécifications.
- **Deux classes de disques.** `ssd-lab` est un vrai SSD ; `hdd-bulk` un vrai disque dur. Proxmox présente les premiers comme non rotatifs (`ssd=1`), le noyau des nœuds le voit, et Ceph en déduit la classe de chaque OSD. Les règles de placement par classe viennent au palier 2 (M08-E14).

### Hôtes du module

| Hôte | VMID | Adresses (public / cluster) | Ressources | Étiquettes | Rôle Ansible | Exercice |
|---|---|---|---|---|---|---|
| `ceph01` | 2081 | 10.10.30.51 / 10.10.31.51 | 2 vCPU (`x86-64-v3`), 6 Go ; système 20 Gio `local-nvme` ; OSD 2 × 64 Gio `ssd-lab` + 1 × 64 Gio `hdd-bulk` | `env-m08`, `role-ceph` | `ceph_noeud` | E02 |
| `ceph02` | 2082 | 10.10.30.52 / 10.10.31.52 | idem | idem | idem | E02 |
| `ceph03` | 2083 | 10.10.30.53 / 10.10.31.53 | idem | idem | idem | E02 |
| `ceph04` | 2084 | 10.10.30.54 / 10.10.31.54 | idem | idem | idem | E18 (détruit en fin de module) |
| `cephcli01` | 2085 | 10.10.30.20 (une seule carte) | 2 vCPU, 2 Go, 20 Gio ; + 2 × 8 Gio `ssd-lab` en E08 | `env-m08`, `role-ceph-client` | `ceph_client` | E06 |

VMID du module : 2080-2089 (pool `lab`). 2080 libre ; 2086 `m08-initiateur` (initiateur iSCSI jetable, E17) ; 2087-2089 libres pour tes essais. Instances Molecule : 2049 (scénario `ceph_noeud`, Rocky 10), 2048 (scénario `ceph_client`, partagé avec `gitlab_runner`).

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur `gw01`/`gw02` |
|---|---|---|---|
| `adm01` → nœuds Ceph et `cephcli01` (SSH, tableau de bord) | 22, 8443 | E02-E08 | existant : MGMT joint tout le lab |
| `cephcli01` → MON, OSD (même VLAN 30) | 3300, 6789, 6800-7568 | E06 | même VLAN : ne traverse pas la passerelle |
| nœuds ↔ nœuds (public et cluster) | 22, 3300, 6789, 6800-7568, 8443, 9283 | E03-E04 | même VLAN ; ouverts par cephadm dans **firewalld** sur chaque nœud |
| nœuds Ceph, `cephcli01` → Internet (`quay.io`, `download.ceph.com`, dépôts Rocky/EPEL/Debian) | 443 | E02-E06 | existant (« lab vers Internet ») |
| nœuds Ceph, `cephcli01` → `dns01`/`dns02` (DNS), passerelle (NTP) | 53, 123 | E02 | existant |

Aucun flux nouveau sur les passerelles au palier 1 : tout se passe dans le VLAN 30 et le VLAN 31. Le pare-feu **local** des nœuds (firewalld, actif dans l'image dorée Rocky) est tenu par cephadm, qui ouvre les ports de chaque démon qu'il déploie. Les flux venant d'autres VLAN (RGW, `runner01`, OpenStack, Kubernetes) arrivent aux paliers suivants, par la matrice des flux.

---

## Le chemin imposé

1. **OpenTofu** : les VMs sont déclarées dans l'état **`envs/ceph`** de `plateforme/infra` (un état à part : détruire le cluster ne peut jamais toucher le socle), avec le module **`vm-noeud`** de `plateforme/tofu-modules`, que tu écris en E02 (plusieurs cartes, MTU, disques de données, famille Rocky ou Debian) ; les noms DNS par le module `enregistrement-dns` (M06-E14) ; les adresses dans NetBox (M06-E13).
2. **Ansible** : les nœuds entrent dans l'inventaire par leurs étiquettes NetBox (`env-m08`, `role-ceph`) ; le rôle `ceph_noeud` (testé par Molecule) les prépare ; les rôles communs `ssh_durci`, `ca_lab`, `ssh_ca_hote`, `ssh_ca_utilisateur` s'appliquent comme au socle.
3. **cephadm** : ce que Ceph fait tourner est décrit dans `plateforme/ceph` (`specs/`), relu en MR, appliqué par `ceph orch apply -i` depuis un nœud `_admin` (puis par un pipeline, M08-E23).
4. **Secrets** : clés cephx et mots de passe en Vault (`lab` pour les clés des clients de test, `critique` pour `client.admin` et ce qui permet de réécrire le cluster), inscrits au registre des secrets. Un trousseau ne quitte jamais un nœud `_admin` autrement que par Ansible.
5. **Documentation** : dans `plateforme/medisphere`, dossier **`docs/stockage/`** (fiches, runbooks RB-080 et suivants, ADR-0080, politique de stockage).

Une manipulation à la main n'est permise que pour **explorer** (une commande `ceph` d'observation, un essai sur une VM 2087-2089), ou quand l'énoncé la demande explicitement comme geste à connaître (l'amorçage, une seule fois).

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**RADOS.** Le cœur de Ceph : un magasin d'**objets** distribué, fiable et autonome. Tout le reste (RBD, CephFS, RGW) est construit au-dessus. Un objet a un nom, des données, des attributs ; il vit dans un **pool**.

**MON (moniteur).** Tient les **cartes** du cluster (moniteurs, OSD, PG, CRUSH, MDS) et les fait évoluer par consensus (Paxos). Une décision exige la **majorité** des moniteurs (le quorum) : 2 sur 3. Les moniteurs gardent aussi la configuration centralisée (`ceph config`) et les clés cephx. Ils ne voient passer **aucune donnée** des clients.

**MGR (gestionnaire).** Collecte les métriques, porte les modules (orchestrateur `cephadm`, tableau de bord, `prometheus`, autoscaler des PG, `volumes`…). Un actif, des remplaçants. Sans mgr actif, les données restent servies, mais plus rien ne se pilote ni ne se mesure.

**OSD (Object Storage Daemon).** Un démon par disque. Il stocke les objets (moteur **BlueStore**, directement sur le périphérique, sans système de fichiers), les réplique vers ses pairs, détecte les pannes de ses voisins, rejoue la récupération. Un OSD est `up`/`down` (vivant ou non) et `in`/`out` (compte ou non pour le placement des données).

**PG (groupe de placement).** Un pool est découpé en PG ; chaque objet tombe dans un PG (empreinte de son nom, modulo le nombre de PG) ; chaque PG est placé sur un ensemble d'OSD (son *acting set*). Raisonner en PG plutôt qu'en objets permet de suivre des millions d'objets avec quelques centaines d'unités. L'**autoscaler** choisit le nombre de PG de chaque pool.

**CRUSH.** L'algorithme qui calcule, **sans table centrale**, sur quels OSD vit un PG, à partir d'une carte (hiérarchie racine → hôtes → OSD, poids, classes de disques) et de **règles** (« 3 copies, chacune sur un hôte différent »). Tout client calcule lui-même où lire et écrire : pas de serveur de métadonnées sur le chemin des données en RBD et RGW. Le **domaine de panne** (ici l'hôte) garantit que deux copies ne partagent pas le même point de défaillance.

**Réplication et `min_size`.** Un pool répliqué `size 3, min_size 2` garde trois copies et accepte les écritures tant qu'au moins deux sont disponibles. En dessous, les PG concernés deviennent **inactifs** : plus d'écriture plutôt que des données sur une seule copie. Les **codes d'effacement** (k + m morceaux) sont l'autre stratégie, plus économe en place (palier 2).

**RBD, CephFS, RGW.** RBD : des **images** (disques) découpées en objets de 4 Mio, avec instantanés, clones, mappées par le noyau (`krbd`) ou utilisées par QEMU. CephFS : un système de fichiers POSIX partagé, dont les métadonnées sont servies par des démons **MDS**. RGW : une passerelle HTTP compatible **S3**.

**cephx.** L'authentification mutuelle des clients et des démons : chaque entité (`client.admin`, `client.rbd-test`, `osd.3`…) a une clé et des **capacités** (*caps*) par démon (`mon`, `osd`, `mds`, `mgr`). Les profils (`profile rbd`, `profile rbd pool=X`) donnent des droits cohérents sans écrire les capacités à la main.

**cephadm.** L'outil de déploiement de référence depuis Octopus : `cephadm bootstrap` crée le premier moniteur et le premier gestionnaire ; ensuite, tout passe par l'orchestrateur (`ceph orch …`) et ses **spécifications** de services, appliquées de façon déclarative.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | Ceph **Tentacle 20.2.3** (image `quay.io/ceph/ceph:v20.2.3`, puis 20.2.4 en M08-E26) ; `cephadm` et `ceph-common` **20.2.3** en paquets RPM signés de `download.ceph.com/rpm-20.2.3/el10/` (clé « Ceph.com (release key) », empreinte `08B7 3419 AC32 B4E9 66C1 A330 E84A C2C0 460F 3994`) ; Rocky Linux 10, Podman 5 (AppStream) ; client Debian 13 : `ceph-common` **18.2** (Reef) de Debian, compatible avec un cluster Tentacle |
| Changements de version | voir [`annexes/versions-bloc-B.md`](../../../annexes/versions-bloc-B.md), section « Stockage distribué » : Rocky 10 pris en charge depuis 20.2.2, `rbd device map` en msgr2 par défaut, plugin EC par défaut ISA-L, modules `restful` et `zabbix` supprimés, comptes RGW, `certmgr` |
| Cluster | `ceph-par1` ; `public_network` 10.10.30.0/24 ; `cluster_network` 10.10.31.0/24 ; 3 MON (`ceph01-03`, étiquette `mon`), 2 MGR (étiquette `mgr`), OSD par spécification (`osd.ssd`, `osd.hdd`, étiquette `osd`) ; `osd_memory_target` 1 Gio, réglage automatique désactivé ; pools répliqués `size 3`, `min_size 2` ; autoscaler des PG actif |
| Orchestrateur | `cephadm bootstrap --ssh-user cephadm` : compte `cephadm` créé par le paquet (dossier `/var/lib/cephadm`), sudo sans mot de passe ; `root` reste interdit en SSH (`ssh_durci`) ; pile de supervision cephadm **non déployée** (`--skip-monitoring-stack`) |
| Étiquettes cephadm | `_admin` (copie de `ceph.conf` et du trousseau `client.admin` dans `/etc/ceph`), `mon`, `mgr`, `osd` sur les trois nœuds |
| Tableau de bord | module `dashboard` du mgr actif, `https://<mgr actif>:8443` (`https://ceph01.par1.medisphere.internal:8443` quand `ceph01` est actif) ; compte `admin` (mot de passe en Vault `lab`, copie dans `~/.config/workbook/ceph-dashboard.pass`) ; certificat step-ca au palier 3 |
| Projets | `plateforme/infra` : `envs/ceph/` (état `envs/ceph/terraform.tfstate`) ; `plateforme/tofu-modules` : module `vm-noeud` (E02) ; `plateforme/ansible` : rôles `ceph_noeud`, `ceph_client`, playbooks `ceph-noeuds.yml`, `ceph-clients.yml`, source d'inventaire `inventories/lab/netbox-ceph.yml`, `group_vars/env_m08/ceph.yml` (faits partagés du cluster) ; **`plateforme/ceph`** (créé en E03) : `bootstrap/`, `specs/`, `outils/` ; `plateforme/medisphere` : `docs/stockage/` |
| Groupes d'inventaire | `env_m08` (nœuds et client), `role_ceph` (`ceph01-03`, puis `ceph04`), `role_ceph_client` (`cephcli01`) |
| Secrets du palier 1 | Vault `lab` : `vault_ceph_dashboard_admin_mdp` (`group_vars/env_m08/`), `vault_ceph_cle_rbd_test` (`group_vars/role_ceph_client/`) ; sur les nœuds `_admin` : `/etc/ceph/ceph.client.admin.keyring` (600) — jamais copié ailleurs ; la clé SSH privée de l'orchestrateur reste dans le cluster |
| Documentation | `docs/stockage/` dans `plateforme/medisphere` : fiche d'astreinte (E07), puis runbooks RB-080 (remplacer un disque), RB-081 (ajouter un nœud), RB-082 (mettre à jour Ceph), ADR-0080, politique de stockage |
| Brouillons | `~/m08/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05), aussi ton compte nominatif NetBox (M06-E04) |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<FSID>` | Identifiant unique du cluster, affiché par l'amorçage (E03) et par `ceph fsid` |
| `<VERSION-TOFU-MODULES>` | Dernière étiquette publiée de `plateforme/tofu-modules` (celle qui contient `vm-noeud`, E02) |

### Variables de `lab/lab.env`

Deux variables nouvelles, avec des valeurs par défaut qui conviennent au lab :

```
# --- Module 08 (Ceph) -----------------------------------------------------------
# Nœud _admin où les vérifications lancent « ceph » (sudo -n) ; client de test
WB_CEPH_ADMIN=ceph01
WB_CEPH_CLIENT=cephcli01
```

Si `ceph01` est arrêté (panne, maintenance), mets `WB_CEPH_ADMIN=ceph02` le temps de vérifier. Les vérifications utilisent aussi `WB_SRC` (copies de travail), `WB_PVE_HOST` (configuration des VMs), `WB_STORAGE_SSD`, `WB_STORAGE_BULK`, `WB_STORAGE_NVME`, et les jetons en lecture de GitLab et de NetBox.

---

## Règles du module

1. **Aucune commande destructive sans vérifier deux fois.** `ceph osd purge`, `ceph osd destroy`, `ceph orch device zap`, `ceph orch osd rm --zap`, `ceph osd pool delete`, `cephadm rm-cluster`, `rbd rm`, `zpool destroy` : relis le nom de la cible, vérifie l'état du cluster (`ceph -s`, `ceph osd ok-to-stop`, `ceph osd safe-to-destroy`), et demande-toi ce qui se passe si tu t'es trompé de cible. Ceph obéit : il n'y a pas de corbeille.
   > ⚠️ **Attention** : `ceph osd pool delete` exige de lever un verrou (`mon_allow_pool_delete`) et de taper deux fois le nom du pool : ce n'est pas une formalité. Repose le verrou aussitôt après.
2. **Ne touche jamais au stockage de `pve01` depuis Ceph ni depuis ZFS.** Les disques des OSD sont des disques **virtuels** de 64 Gio sur `ssd-lab` et `hdd-bulk` ; ZFS (E08) se pratique sur deux disques virtuels de `cephcli01`. Aucune commande de ce module ne vise un disque physique de `pve01` ni son éventuel pool ZFS.
3. **Arrêter et redémarrer le cluster proprement.** Le cluster est conservé pour M10 et M16 : tu l'arrêteras souvent pour libérer 18 Go de mémoire. Procédure, depuis un nœud `_admin` :
   - **arrêt** : clients démontés (`cephcli01`), puis `ceph osd set noout`, `ceph osd set norebalance`, `ceph osd set nobackfill`, `ceph osd set norecover`, puis arrêt des VMs (OpenTofu ne les arrête pas : `qm shutdown 2083`, `2082`, `2081` sur `pve01`, `cephcli01` d'abord) ;
   - **démarrage** : `qm start 2081`, `2082`, `2083`, attendre le quorum (`ceph -s`), puis lever les quatre drapeaux dans l'ordre inverse, attendre `HEALTH_OK`.
   Un drapeau oublié se paie plus tard : `noout` empêche aussi Ceph de se réparer après une vraie panne.
4. **Un nœud à la fois.** Redémarrage, changement réseau, mise à jour de paquets : un seul nœud, et le suivant seulement quand `ceph -s` est revenu à `HEALTH_OK` (ou à l'état de départ). Le playbook des nœuds est en `serial: 1`.
5. **Pas de vérification TLS désactivée** (`curl -k`, `--insecure`, `verify=False`) ni de secret en argument de commande (mots de passe du tableau de bord, clés cephx) : fichier en 600, entrée standard (`-i -`), ou Vault.
6. **Le trousseau `client.admin` ne quitte pas les nœuds `_admin`.** Un client reçoit une clé à lui, aux droits minimaux. Les vérifications du workbook lisent l'état du cluster par SSH sur un nœud `_admin`, avec `sudo -n`, sans jamais copier le trousseau.
7. **Mémoire.** Le module demande socle v2 (≈ 27 Go) + 3 × 6 Go + `cephcli01` (2 Go) ≈ 47 Go, puis jusqu'à 55 Go avec `ceph04` (E18-E19). Avant de commencer, arrête la maquette réseau du module 07 si elle tourne encore (VMID 2070-2079). Les nœuds sont à 6 Go pour un OSD à 1 Gio de cible : ne lance pas d'autre charge lourde en même temps.

---

## Préparer `adm01`

Les outils viennent des modules précédents ; ce module n'ajoute rien sur `adm01` (la commande `ceph` vit sur les nœuds `_admin`). Vérifie avant de commencer :

```
admin@adm01:~$ lab/bin/check 07 46
admin@adm01:~$ cd ~/src/infra && tofu version
admin@adm01:~$ cd ~/src/ansible && uv run ansible-inventory --graph socle
admin@adm01:~$ ssh -o BatchMode=yes root@pve01 'qm list | grep -E " (90[3-4][0-9]) " | grep rocky10'
admin@adm01:~$ ssh root@pve01 'ip link show vmbr1 | grep -o "mtu [0-9]*"'
```

Le premier contrôle (mini-projet du module 07) doit être vert : ce module s'appuie sur la bordure redondante et sur le MTU 9000 des VLAN 30 et 31. Le quatrième montre tes images dorées Rocky (9030-9049) : il en faut une étiquetée `current`. Le dernier doit afficher `mtu 9000`.

Ajoute les deux variables du module à `lab/lab.env` (copie de `lab/lab.env.example`, section « Module 08 »).

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 08 <XX>`. Elles sont en lecture seule : configuration Proxmox lue sur `pve01`, état des nœuds en SSH, commandes `ceph` et `rbd` **d'observation** sur le nœud `_admin` (`WB_CEPH_ADMIN`), questions DNS, NetBox et GitLab en lecture.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M08-EXX/` : `ansible/` reproduit l'arborescence de `plateforme/ansible`, `infra/` celle de `plateforme/infra`, `tofu-modules/` celle de `plateforme/tofu-modules`, **`ceph/` celle de `plateforme/ceph`**, `medisphere/` celle de la documentation. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E09
                                └── E08 (dès que cephcli01 existe)
```

1. **E01** — positionnement, à froid.
2. **E02 → E06** — dans l'ordre : chaque exercice construit sur le précédent (nœuds, amorçage, OSD, pool, client).
3. **E07** — quand le cluster porte des données : on y provoque des états dégradés, sans risque.
4. **E08** — indépendant de Ceph, sur `cephcli01` : à intercaler quand tu veux.
5. **E09** — en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 14 à 18 heures.

## Pour aller plus loin

- Architecture de Ceph : <https://docs.ceph.com/en/tentacle/architecture/>
- Déployer avec cephadm : <https://docs.ceph.com/en/tentacle/cephadm/install/> · services et spécifications : <https://docs.ceph.com/en/tentacle/cephadm/services/>
- Opérations RADOS (pools, PG, CRUSH, santé) : <https://docs.ceph.com/en/tentacle/rados/operations/>
- Recommandations matérielles (pour comprendre ce que le lab simplifie) : <https://docs.ceph.com/en/tentacle/start/hardware-recommendations/>
- Notes de version de Tentacle : <https://docs.ceph.com/en/latest/releases/tentacle/>
- Sage Weil, *CRUSH: Controlled, Scalable, Decentralized Placement of Replicated Data* (SC'06) et *RADOS* (PDSW'07) : les articles fondateurs, courts et lisibles.
