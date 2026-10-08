# Module 10 — Introduction : OpenStack

## Des machines en libre-service

Lundi, 8 h 50. Le stockage `ceph-par1` est livré (étiquette `stockage-v1`), le cluster Proxmox imbriqué a été reconstruit depuis le code puis rendu à la mémoire du lab. Dans la boîte de réception, deux messages se suivent.

> **De** : Julien Petit — Lead dev MédiAgenda
> **À** : Équipe Plateforme
> **Objet** : Encore trois jours pour une VM de recette
>
> Bonjour,
>
> Pour tester la nouvelle API de prise de rendez-vous, il me faut deux VMs, une base, un répartiteur et une adresse joignable depuis le VPN. J'ai ouvert le ticket mercredi ; on est lundi. Chez mon ancien employeur, je tapais trois lignes de Terraform sur AWS et j'avais tout en cinq minutes, je le détruisais le soir.
>
> Je ne demande pas AWS (je sais, les données de santé). Je demande la même chose **chez nous** : un projet à moi, des quotas, mes réseaux, mes IP, mes volumes, et une API.
> Julien

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit
> **Objet** : Re: Encore trois jours pour une VM de recette — on construit l'IaaS
>
> Bonjour,
>
> Julien a raison, et ce ne sera pas le dernier à le dire. Nous allons construire un **IaaS** interne : un cloud privé, multi-projets, piloté par API, hébergé à PAR1. Le comité d'architecture a retenu **OpenStack 2026.1**, déployé en conteneurs par **Kolla-Ansible** (ADR-0101, que Karim a rédigée), stocké sur `ceph-par1`. Les règles :
> - **Le code d'abord.** Les trois nœuds sont créés par OpenTofu et préparés par Ansible ; toute la configuration de Kolla vit dans un nouveau projet GitLab, `plateforme/openstack`, et ne change que par MR. Le jour où il faut reconstruire, on relance, on ne se souvient pas.
> - **Le réseau d'OpenStack est moderne.** Neutron avec **OVN**, pas le vieil agent Open vSwitch que Kolla met par défaut. Karim t'expliquera pourquoi ; l'ADR réseau (ADR-0100) suivra.
> - **Cloisonnement.** Sophie veut un domaine MédiSphère, un projet par équipe et par environnement, des rôles et des quotas, et aucun mot de passe en clair dans un dépôt.
> - **Exploitable.** Nadia veut pouvoir dépanner une instance « bloquée en ERROR » à 3 h du matin sans appeler un expert. Les runbooks et la supervision font partie de la livraison.
>
> On a la mémoire d'un contrôleur et de deux calculs, pas plus : ce sera un plan de contrôle **non redondant**, et on saura exactement ce que ça implique (palier 3).
>
> Premier jalon : un OpenStack qui démarre, avec Keystone, Glance, Nova et Neutron/OVN, une première instance joignable par une IP flottante depuis `adm01`. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 10, MédiSphère dispose d'un cloud **v1** (étiquette `cloud-v1` du dépôt `plateforme/medisphere`) :

- trois VMs Proxmox : `osctl01` (contrôle et réseau) et `oscmp01-02` (calcul, KVM imbriqué), créées par OpenTofu et préparées par Ansible ;
- OpenStack 2026.1 « Gazpacho » déployé par Kolla-Ansible 22 depuis le dépôt `plateforme/openstack` : Keystone, Glance, Placement, Nova, Neutron/OVN, Cinder, Heat, Horizon, Octavia (fournisseur OVN) ;
- le stockage sur `ceph-par1` : images (`images`), disques des instances (`vms`), volumes (`volumes`), sauvegardes de volumes (`backups`) ;
- le domaine `medisphere`, les projets de l'équipe Plateforme et de MédiAgenda, leurs quotas, leurs rôles ; le libre-service par la CLI, Horizon, Heat et OpenTofu ;
- la sauvegarde, la supervision, la sécurisation, la mise à jour et l'exploitation de la plateforme, ADR-0100 et les runbooks RB-100 et suivants.

Le **palier 1** (ce fichier et `01-decouverte.md`) prépare les nœuds (E02), le poste de déploiement (E03), déploie (E04), puis fait le tour des services de base en créant le domaine MédiSphère (E05), des images (E06), des gabarits et une première instance (E07), et le réseau qui la rend joignable (E08). Il s'ouvre et se ferme sur un questionnaire.

## Architecture du module

```
                       adm01 (1001) 10.10.10.10 — VLAN 10 MGMT
       ~/src/openstack : projet uv (Kolla-Ansible 22, ansible-core 2.20), clone de plateforme/openstack
       openstack (CLI 10.x) · ~/.config/openstack/clouds.yaml · tofu · step
                                  │ SSH (déploiement), HTTPS (API)
 ═════════════════════════════════╪══════════ gw01 / gw02 (bordure, VIP .1 de chaque VLAN) ═════════
                                  │
 VLAN 50 OS-API 10.10.50.0/24 ────┼──────────────┬──────────────────────────┬─────────────── (MTU 1500)
   VIP interne 10.10.50.200       │              │                          │
   VIP externe 10.10.50.201       │              │                          │
   (keepalived, VRID 150)    ens18│ .51     ens18│ .52                 ens18│ .53
                     ┌────────────┴─────┐ ┌──────┴────────────┐  ┌──────────┴────────┐
                     │ osctl01  (2101)  │ │ oscmp01  (2102)   │  │ oscmp02  (2103)   │
                     │ 4 vCPU, 16 Go    │ │ 4 vCPU, 8 Go, CPU │  │ 4 vCPU, 8 Go, CPU │
                     │ HAProxy, keepal. │ │ host (KVM imbriqué│  │ host              │
                     │ MariaDB, RabbitMQ│ │ nova-compute      │  │ nova-compute      │
                     │ memcached        │ │ nova_libvirt      │  │ nova_libvirt      │
                     │ keystone, glance │ │ ovn-controller    │  │ ovn-controller    │
                     │ placement, nova-*│ │ ovn-metadata      │  │ ovn-metadata      │
                     │ neutron-server   │ │                   │  │                   │
                     │ OVN NB/SB, northd│ │                   │  │                   │
                     │ ovn-controller   │ │                   │  │                   │
                     │ (passerelle)     │ │                   │  │                   │
                     │ horizon, heat    │ │                   │  │                   │
                     └─┬─────┬──────┬───┘ └──┬──────────┬─────┘  └──┬──────────┬─────┘
 VLAN 51 OS-TUN   ens19│ .51  │      │   ens19│ .52       │       ens19│ .53       │   Geneve, MTU 9000
 10.10.51.0/24 ────────┴──────┼──────┼────────┴───────────┼────────────┴───────────┼── (non routé)
 VLAN 30 STOR-PUB        ens20│ .61  │              ens20 │ .62                ens20│ .63   MTU 9000
 10.10.30.0/24 ───────────────┴──────┼────────────────────┴────────────────────────┴───┬──────────
                                     │                       ceph01-03 (2081-2083) 10.10.30.51-53
                                ens21│ (sans adresse : br-ex, physnet1)                 « ceph-par1 »
 VLAN 52 OS-EXT 10.10.52.0/24 ───────┴── passerelle 10.10.52.1 (bordure) ── IP flottantes .200-.249
```

Points structurants :

- **Deux VIP sur le VLAN 50.** HAProxy, sur `osctl01`, publie chaque API sur la VIP **interne** (10.10.50.200, `openstack-int.par1.medisphere.internal`, utilisée entre services) et sur la VIP **externe** (10.10.50.201, `openstack.par1.medisphere.internal`, utilisée par les humains et les outils, en HTTPS avec un certificat de `ca01`). keepalived porte les VIP avec le numéro de routeur virtuel **150** : le VRID 50 est déjà celui des passerelles sur ce VLAN (M07-E25), deux groupes VRRP de même numéro sur un même segment se battraient pour les annonces.
- **Trois plans réseau séparés.** L'API et la gestion sur le VLAN 50 ; le trafic **entre instances** encapsulé en Geneve sur le VLAN 51 (MTU 9000 : l'encapsulation ne fragmente pas) ; le stockage vers Ceph sur le VLAN 30, sans traverser la bordure. Le VLAN 52 n'est branché que sur `osctl01`, la seule **passerelle** OVN : toutes les IP flottantes et la traduction d'adresses des routeurs passent par lui.
- **Un plan de contrôle non redondant.** Une seule instance de MariaDB, de RabbitMQ, des bases OVN, d'HAProxy. Les VIP existent quand même : passer à trois contrôleurs ne changera aucune adresse côté clients (palier 3, E24).
- **Les instances vivent dans les calculs.** Leurs disques sont d'abord locaux (palier 1), puis sur Ceph (E10). Les calculs `oscmp01-02` sont des VMs : les instances sont des VMs **dans** des VMs (KVM imbriqué, CPU `host`).

### Hôtes du module

| Hôte | VMID | Adresses | Ressources | Groupes Kolla | Exercice |
|---|---|---|---|---|---|
| `osctl01` | 2101 | `ens18` 10.10.50.51 (passerelle 10.10.50.1) ; `ens19` 10.10.51.51 ; `ens20` 10.10.30.61 ; `ens21` sans adresse | 4 vCPU, 16 Go, 80 Go | `control`, `network`, `monitoring`, `storage` | E02 |
| `oscmp01` | 2102 | `ens18` 10.10.50.52 ; `ens19` 10.10.51.52 ; `ens20` 10.10.30.62 | 4 vCPU, 8 Go, 40 Go, CPU `host` | `compute` | E02 |
| `oscmp02` | 2103 | `ens18` 10.10.50.53 ; `ens19` 10.10.51.53 ; `ens20` 10.10.30.63 | 4 vCPU, 8 Go, 40 Go, CPU `host` | `compute` | E02 |
| VIP interne | — | 10.10.50.200 `openstack-int.par1.medisphere.internal` | keepalived sur `osctl01` | — | E04 |
| VIP externe | — | 10.10.50.201 `openstack.par1.medisphere.internal` | keepalived sur `osctl01` | — | E04 |

Les trois VMs sont des VMs d'**environnement** (étiquettes Proxmox et NetBox `env-m10` et `role-openstack`, pool `lab`), dans un état OpenTofu dédié, `envs/openstack`, du projet `plateforme/infra`. Elles restent en place pendant tout le module ; à la fin, on peut les arrêter (profil suivant) ou les détruire : le mini-projet prouve qu'elles se reconstruisent depuis le code.

### Plan réseau des nœuds

| Carte Proxmox | Interface | VNet (VLAN) | MTU | Adresse | Rôle Kolla |
|---|---|---|---|---|---|
| `net0` | `ens18` | `vosapi` (50) | 1500 | 10.10.50.51-53/24, passerelle 10.10.50.1 | `network_interface` (API, gestion, VIP) |
| `net1` | `ens19` | `vostun` (51) | 9000 | 10.10.51.51-53/24 | `tunnel_interface` (Geneve) |
| `net2` | `ens20` | `vstopub` (30) | 9000 | 10.10.30.61-63/24 | `storage_interface` (Ceph) |
| `net3` (`osctl01` seulement) | `ens21` | `vosext` (52) | 1500 | **aucune** | `neutron_external_interface` (`physnet1`, `br-ex`) |

Les noms d'interface `ens18` à `ens21` sont **imposés par le rôle Ansible** de E02 (correspondance par adresse MAC), et non laissés au hasard de cloud-init : l'image dorée nomme sa carte `eth0` quand cloud-init la configure (M03), Debian choisirait `ens21` pour une carte sans configuration, et Kolla a besoin de noms stables, identiques à chaque reconstruction. Les adresses MAC suivent une règle : `bc:24:11:<VLAN>:00:<dernier octet de l'adresse OS-API>` (ex. `bc:24:11:52:00:51` pour `ens21` de `osctl01`).

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur la bordure |
|---|---|---|---|
| `adm01` → nœuds (SSH), VIP (API, Horizon), IP flottantes | 22, 443, 5000, 8774… ; tout | E02-E08 | existant : MGMT joint tout le lab |
| nœuds → Internet (dépôts Debian et Docker, `quay.io` pour les images Kolla) | 80, 443 | E02-E04 | existant (« lab vers Internet ») |
| nœuds → `dns01`/`dns02` (DNS), → bordure (NTP) | 53, 123 | E02 | existant |
| nœuds ↔ `ceph01-03` | 3300, 6789, 6800-7568 | E10 | même VLAN 30 : rien ne traverse la bordure |
| `osctl01` → `ca01` (ACME, émission du certificat externe) | 443 | E04 | **nouveau** : VLAN 50 → INFRA |
| `ca01` → VIP externe 10.10.50.201 (défi ACME HTTP-01) | 80 | E04 | **nouveau** : INFRA → VLAN 50 |
| IP flottantes ↔ `adm01` | tout | E08 | existant (MGMT joint tout ; retours autorisés) |

Les deux flux nouveaux sont des lignes de la matrice `pare_feu.yml` (commune à `gw01` et `gw02`), ajoutées par MR en E04.

---

## Le chemin imposé

1. **OpenTofu** : les nœuds sont déclarés dans l'état `envs/openstack` de `plateforme/infra`, par le module `vm-debian` de `plateforme/tofu-modules` (clone complet de l'image dorée Debian `current`, adresse enregistrée dans NetBox, nom publié dans PowerDNS par le module `enregistrement-dns`).
2. **Ansible** (`plateforme/ansible`) : les rôles communs (`base`, `ssh_durci`, racine de confiance), puis un rôle `noeud_openstack` qui prépare ce que Kolla attend (interfaces, MTU, KVM, temps). Docker et le reste de la pile sont posés par **Kolla-Ansible** (`bootstrap-servers`), pas par nos rôles : un seul maître par composant.
3. **Kolla-Ansible** (`plateforme/openstack`) : `globals.yml`, inventaire, surcharges de configuration (`etc/kolla/config/`), `passwords.yml` **chiffré** sous l'identité Vault `critique`. Exécution depuis `adm01`, dans un environnement `uv` dédié (E03 explique pourquoi un second environnement).
4. **Les objets du cloud** (domaine, projets, gabarits, réseau externe) sont décrits par du code dans `plateforme/openstack` ; les ressources des projets (instances, réseaux, routeurs) sont créées par leurs utilisateurs, par la CLI d'abord, par Heat et OpenTofu ensuite (palier 2).
5. **Secrets** en Vault `critique` (mots de passe d'OpenStack, clé du certificat externe, mots de passe des comptes Keystone), inscrits au registre des secrets ; sur `adm01`, `~/.config/openstack/secure.yaml` (600). **Documentation** dans `plateforme/medisphere`, sous `docs/cloud/` (`adr/`, `runbooks/`, `changements/`…).

Une installation à la main n'est permise que pour **explorer**, annoncée comme telle dans l'énoncé.

---

## Concepts clés

Une synthèse pour se repérer ; E09 et les liens « Pour aller plus loin » approfondissent.

**IaaS.** L'*Infrastructure as a Service* fournit des ressources d'infrastructure (calcul, réseau, stockage) **à la demande, par API, en libre-service, mesurées et cloisonnées**. Ce qui distingue un cloud d'un hyperviseur avec une interface web : l'utilisateur crée et détruit seul, dans des limites (quotas), sans connaître le matériel ; l'opérateur gère une capacité, pas des VMs.

**Les services d'OpenStack.** Chaque fonction est un service avec son API REST et sa base : **Keystone** (identité, jetons, catalogue des points d'accès), **Glance** (images), **Placement** (inventaire et consommation des ressources des hyperviseurs), **Nova** (instances : `nova-api`, `nova-scheduler`, `nova-conductor` au centre, `nova-compute` sur chaque calcul, qui pilote libvirt/QEMU), **Neutron** (réseaux, sous-réseaux, routeurs, IP flottantes, groupes de sécurité), **Cinder** (volumes), **Heat** (orchestration par gabarits), **Horizon** (tableau de bord), **Octavia** (répartiteurs de charge). Les services se parlent par leurs API (en passant par Keystone pour authentifier) et, à l'intérieur d'un même service, par une **file de messages** (RabbitMQ) ; leur état est dans **MariaDB**.

**Domaines, projets, rôles.** Keystone range les utilisateurs et les groupes dans des **domaines** ; les ressources appartiennent à des **projets** (un projet = un locataire, *tenant*) ; un **rôle** (`reader`, `member`, `admin`) est attribué à un utilisateur ou un groupe **sur** un projet (ou un domaine, ou le système). Un jeton est **limité** (*scoped*) à un projet : on agit toujours « dans » un projet. Les politiques (*policies*) de chaque service traduisent rôle et portée en droits.

**Réseau virtuel.** Un projet a ses **réseaux** (L2 isolés, ici encapsulés en Geneve), ses **sous-réseaux** (plages, DHCP, DNS), ses **routeurs** (L3 entre ses sous-réseaux et un **réseau externe**). Une **IP flottante** est une adresse du réseau externe traduite (NAT 1:1) vers l'adresse privée d'une instance. Les **groupes de sécurité** sont des pare-feu à états appliqués à chaque port. Avec **OVN**, tout cela est compilé en flux Open vSwitch par un contrôleur central (bases *Northbound* et *Southbound*, `ovn-northd`) et appliqué par `ovn-controller` sur chaque nœud : plus d'agents L3 ni DHCP séparés.

**Kolla-Ansible.** Chaque service tourne dans un **conteneur** (images Kolla construites par le projet OpenStack, publiées sur `quay.io/openstack.kolla`) ; Kolla-Ansible génère la configuration de chaque service depuis `globals.yml`, `passwords.yml`, l'inventaire et les surcharges, la dépose dans `/etc/kolla/<service>/` des nœuds, lance les conteneurs et les met à jour. Les journaux vont dans `/var/log/kolla/<service>/`. On ne modifie **jamais** un fichier sur un nœud : on modifie le dépôt et on relance Kolla.

**Instance, gabarit, image.** Une **instance** naît d'une **image** (Glance) et d'un **gabarit** (*flavor* : vCPU, mémoire, disque), sur un réseau, avec une paire de **clés** SSH ; cloud-init lit ses **métadonnées** (service de métadonnées ou *config drive*) au premier démarrage. L'ordonnanceur de Nova choisit un calcul en interrogeant Placement.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | OpenStack **2026.1 « Gazpacho »**, Kolla-Ansible **22.x** (22.2.0 à la rédaction, PyPI), ansible-core **2.20.x** (Kolla 22 exige ≥ 2.19.1 et < 2.21), images `quay.io/openstack.kolla/*` étiquette `2026.1-debian-trixie`, moteur Docker posé par Kolla ; CLI `python-openstackclient` 10.x ; provider OpenTofu `terraform-provider-openstack/openstack` `~> 3.4` (palier 2) |
| Changements de version | voir [`annexes/versions-bloc-B.md`](../../../annexes/versions-bloc-B.md), section OpenStack : OVN n'est pas le défaut de Kolla, Linux Bridge supprimé, rôle `common` devenu `kolla_toolbox` (groupes d'inventaire renommés), API sous uWSGI, RabbitMQ 4.2 et files *quorum*. Sur Debian, plusieurs images (dont `ovn`, `octavia`, `cinder`, `haproxy`) sont marquées « non testées » par la CI de Kolla 2026.1 (matrice de support des images) : la reconstruction depuis le code permet de changer de `kolla_base_distro` si l'une d'elles posait problème |
| Projet de déploiement | GitLab `plateforme/openstack`, clone `~/src/openstack` sur `adm01` : `pyproject.toml` + `uv.lock`, `ansible.cfg`, `etc/kolla/globals.yml`, `etc/kolla/globals.d/` (réglages par sujet, paliers 2-3), `etc/kolla/passwords.yml` (**chiffré**, identité `critique`), `etc/kolla/config/` (surcharges), `etc/kolla/certificates/` (aucune clé en clair), `inventaire/multinode` et `inventaire/host_vars/`, `playbooks/` (objets du cloud), `outils/` |
| Commande Kolla | depuis `~/src/openstack` : `uv run kolla-ansible <action> -i inventaire/multinode --configdir etc/kolla` ; l'identité Vault `critique` est fournie par l'`ansible.cfg` du projet (`vault_identity_list`, équivalent de la variable `ANSIBLE_VAULT_IDENTITY_LIST`) ; à défaut, ajoute `--vault-id critique@outils/vault-pass-client.sh` |
| Points d'accès | `https://openstack.par1.medisphere.internal:5000/v3` (Keystone public, certificat de `ca01`) ; Horizon `https://openstack.par1.medisphere.internal` ; points internes en HTTP sur 10.10.50.200 jusqu'au palier 3 (E27) |
| Clients sur `adm01` | `~/.config/openstack/clouds.yaml` : `medisphere-admin` (projet `admin`, domaine `Default`), `medisphere-plateforme` (ton compte, projet `plateforme`), `medisphere-mediagenda-dev` (`julien.petit`, projet `mediagenda-dev`) ; mots de passe dans `~/.config/openstack/secure.yaml` (600) ; `cacert: /usr/local/share/ca-certificates/medisphere-root-ca.crt` (la racine MédiSphère) |
| Keystone | domaine `medisphere` ; projets `plateforme`, `mediagenda-dev`, `mediagenda-prod` ; groupes `equipe-plateforme`, `equipe-mediagenda` ; utilisateurs `<MOI>`, `karim.benali`, `julien.petit` ; rôles `reader`, `member`, `admin` |
| Catalogue (E06-E08) | images `debian-13`, `rocky-10` ; gabarits `m1.petit` (1 vCPU, 1 Go, 10 Go), `m1.moyen` (2, 2 Go, 20 Go), `m1.grand` (2, 4 Go, 40 Go) ; réseau externe `ext-net` (flat, `physnet1`, 10.10.52.0/24, passerelle 10.10.52.1, IP flottantes .200-.249, sans DHCP) ; réseau du projet `plateforme` : `reseau-plateforme` 172.16.10.0/24, routeur `routeur-plateforme` |
| Ceph (à partir de E10) | `ceph-par1` (M08) : pools `images`, `volumes`, `vms`, `backups` ; clients `client.glance`, `client.cinder`, `client.cinder-backup`, `client.nova`. `ceph01-03` restent **démarrées** pendant tout le module |
| Documentation | `plateforme/medisphere`, dossier `docs/cloud/` : `adr/` (ADR-0100 réseau, ADR-0101 Kolla-Ansible), `runbooks/` (RB-100 et suivants), `changements/`, inventaire et matrice des flux du socle mis à jour |
| Tickets | `PLAT-11xx`, `SEC-11xx`, `DEV-11xx`, `CHG-11xx` ; incidents `INC-37xx` |
| Brouillons | `~/m10/eXX/` sur `adm01` (non versionnés, sans secret) |

### Budget mémoire

| Bloc | Mémoire |
|---|---|
| Socle v2 (`gw01`, `gw02`, `adm01`, `dns01`, `dns02`, `ca01`, `git01`, `runner01`, `nbx01`, `s3-01`, `lb01`, `lb02`) | ≈ 27 Go |
| `osctl01` (contrôle et réseau) | 16 Go |
| `oscmp01` + `oscmp02` (calcul) | 16 Go |
| `ceph01-03` | 18 Go |
| **Total** | **≈ 77 Go** sur les 128 Go de `pve01` |

Les instances consomment la mémoire **des calculs** (8 Go chacun, moins ce que gardent le système et les conteneurs) : compte deux à trois `m1.petit` par calcul au palier 1. Arrête tout autre profil lourd (cluster `hv-par1`, maquette réseau) avant E02.

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte nominatif (GitLab M01-E05, NetBox M06-E04), réutilisé comme utilisateur Keystone du domaine `medisphere` (E05) |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<ID-RESEAU>`, `<ID-INSTANCE>`… | Identifiants (UUID) affichés par la CLI : copie ceux de ton cloud |
| `<IP-FLOTTANTE>` | L'adresse du pool 10.10.52.200-249 attribuée à ton instance (E08) |

### Variables de `lab/lab.env`

| Variable | Défaut | Rôle |
|---|---|---|
| `WB_OS_CLOUD` | `medisphere-admin` | Cloud de `clouds.yaml` utilisé par les vérifications (commandes de lecture seulement : `list`, `show`) |

Les vérifications utilisent aussi `WB_SRC` (`~/src/openstack`, `~/src/infra`, `~/src/ansible`), `WB_DEPOT`, `WB_PVE_HOST` et le jeton GitLab des checks.

---

## Règles du module

1. **`pve01` n'est pas modifié.** La virtualisation imbriquée se **constate** (`/sys/module/kvm_intel/parameters/nested`), elle ne se règle pas dans ce module. Si elle est désactivée, arrête-toi et lis l'indice de E02 : le changement touche toutes les VMs de `pve01` et se planifie.
2. **Instantané avant toute intervention risquée sur les nœuds OpenStack** : `ms-snapshot --prefix avant-<sujet> 2101 2102 2103` (M02-E11), les trois ensemble ; supprimé une fois le changement validé. Un instantané ne ramène pas Ceph en arrière.
3. **Accès de secours vérifié avant d'en avoir besoin** : console série (`qm terminal <VMID>` sur `pve01`) et agent QEMU (`qm guest cmd <VMID> ping`). E02 renomme les interfaces et redémarre les nœuds : c'est la console qui te sauve d'une faute de frappe.
4. **Rien à la main dans `/etc/kolla` sur les nœuds.** Une modification se fait dans `plateforme/openstack`, puis `kolla-ansible reconfigure` (limité par étiquettes quand c'est possible). Une exploration (lire un fichier, entrer dans un conteneur) est libre.
5. **Pas de vérification TLS désactivée** (`--insecure`, `verify: false`, `curl -k`) : l'API publique présente un certificat de la PKI MédiSphère, les clients se configurent avec le magasin du système.
6. **Un secret ne passe jamais en argument de commande** : `--password-prompt`, fichier en 600, entrée standard, ou Vault. `openstack user create --password <valeur>` est interdit ici.
7. **Nettoie derrière toi** : les instances, IP flottantes et volumes d'essai sont comptés dans les quotas et dans la mémoire des calculs. Chaque exercice dit ce qu'il garde ; le reste est supprimé à la fin de l'exercice.

---

## Préparer `adm01`

Les outils viennent des modules précédents (OpenTofu, `uv`, Ansible du projet `plateforme/ansible`, `step`). Ce module ajoute la CLI OpenStack, installée comme outil isolé :

```
admin@adm01:~$ uv tool install 'python-openstackclient>=10,<11'
admin@adm01:~$ openstack --version
openstack 10.…
admin@adm01:~$ install -d -m 700 ~/.config/openstack ~/m10
```

Les greffons (Heat, Octavia, Placement) s'ajoutent au palier 2, quand un exercice en a besoin (`uv tool install python-openstackclient --with <greffon>`, avec `--reinstall` si `uv` refuse de modifier un outil installé). Kolla-Ansible, lui, ne s'installe **pas** comme outil global : il vit dans l'environnement du projet `plateforme/openstack` (E03).

Vérifie avant de commencer :

```
admin@adm01:~$ lab/bin/check 08 46        # Ceph PAR1 livré (HEALTH_OK, pools prêts)
admin@adm01:~$ lab/bin/check 07 15        # MTU 9000 sur les VLAN 30, 31 et 51
admin@adm01:~$ dig +short @10.10.20.10 ca01.par1.medisphere.internal
admin@adm01:~$ ssh pve01 cat /sys/module/kvm_intel/parameters/nested
Y
```

Le contrôle du mini-projet du module 08 doit être vert : ce module consomme ses pools et ses clés à partir de E10. Celui de M07-E15 aussi : le réseau des tunnels (VLAN 51) et celui du stockage (VLAN 30) doivent passer des trames de 9000 octets de bout en bout.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 10 <XX>`. Elles sont en lecture seule : configuration Proxmox lue sur `pve01`, état des nœuds en SSH (`sudo -n` pour lire, `docker ps`, `docker inspect`), API OpenStack par la CLI avec le cloud `WB_OS_CLOUD` (commandes `list` et `show` seulement), DNS, certificats présentés, fichiers de tes copies de travail, API GitLab en lecture.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M10-EXX/` : `openstack/` reproduit l'arborescence de `plateforme/openstack`, `ansible/` celle de `plateforme/ansible`, `infra/` celle de `plateforme/infra`, `tofu-modules/` celle de `plateforme/tofu-modules`, `medisphere/` celle de la documentation, `adm01/` des fichiers personnels de `adm01`.
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─┬─ E05 ─┬─ E07 ─ E08 ─ E09
                       └─ E06 ─┘
```

1. **E01** — positionnement, à froid.
2. **E02 → E03 → E04** — dans l'ordre : les nœuds, le poste de déploiement, le déploiement. Compte une demi-journée pour E04 (téléchargement des images, premier déploiement).
3. **E05** et **E06** sont indépendants ; **E07** a besoin des deux (projet et image), **E08** de E07 (l'instance à rendre joignable).
4. **E09** — en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 16 à 20 heures.

## Pour aller plus loin

- Kolla-Ansible 2026.1 : <https://docs.openstack.org/kolla-ansible/2026.1/> — « Quick Start », « Multinode Deployment », « Operating Kolla », « Neutron » (OVN), « TLS », « External Ceph ».
- Images Kolla, matrice de support : <https://docs.openstack.org/kolla/2026.1/support_matrix.html>
- Notes de version de Kolla-Ansible 2026.1 : <https://docs.openstack.org/releasenotes/kolla-ansible/2026.1.html>
- Guide d'installation d'OpenStack (comprendre ce que Kolla automatise) : <https://docs.openstack.org/install-guide/>
- Keystone, *Administrator Guide* (domaines, rôles par défaut, *application credentials*) : <https://docs.openstack.org/keystone/2026.1/admin/>
- OVN : <https://docs.ovn.org/> ; Neutron et OVN : <https://docs.openstack.org/neutron/2026.1/admin/ovn/>
- CLI : <https://docs.openstack.org/python-openstackclient/latest/>
