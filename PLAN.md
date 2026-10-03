# PLAN.md — Plan directeur du workbook

> Document de référence. **Toute décision structurante est consignée ici.** Un module ne doit jamais contredire ce fichier ; si un changement est nécessaire, on modifie d'abord `PLAN.md` (avec une entrée dans le journal des décisions en bas), puis les modules concernés.

---

## 1. Objectif

Former un **administrateur système et réseau** au métier de **DevOps / ingénieur plateforme orienté cloud privé**, par la pratique, jusqu'à un niveau opérationnel en entreprise.

- Public : admin sys/réseau confirmé (Linux, réseau, virtualisation). Les bases Linux/réseau ne sont pas réenseignées, elles sont **évaluées** (module 00) puis **mobilisées**.
- Philosophie : qualité d'apprentissage avant tout, pas de contrainte de temps. Chaque techno « cœur » est traitée en profondeur, jusqu'au troubleshooting de production.
- Certifications : non visées en soi, mais l'annexe `annexes/certifications.md` indique la couverture (LFCS/RHCSA, RHCE, CKA, CKAD, CKS, Terraform Associate, COA…).

## 2. Fil rouge : MédiSphère

**MédiSphère** est un éditeur français de logiciels de santé (dossier patient, téléconsultation, prise de rendez-vous) d'environ 400 salariés. Ses applications hébergent des **données de santé** : l'entreprise doit être conforme **HDS** (Hébergeur de Données de Santé), **ISO 27001** et **RGPD**, et sa direction exige la **souveraineté** des données.

Jusqu'ici, MédiSphère louait des serveurs dédiés gérés à la main par un prestataire. Le contrat se termine dans 18 mois. La DSI a décidé de **construire son propre cloud privé** dans deux salles :

| Site | Rôle | Matériel du lab |
|---|---|---|
| **PAR1** (datacenter principal) | Production, plateforme complète | `pve01` — serveur Proxmox principal |
| **PAR2** (site de secours) | Sauvegardes, quorum, PRA | `hp01` — HP ProLiant |

**Tu es recruté(e) dans l'équipe Plateforme** (« Platform Team »), sous la responsabilité de **Claire Morel** (responsable infrastructure). Personnages récurrents :

| Personnage | Rôle | Ce qu'il/elle demande typiquement |
|---|---|---|
| Claire Morel | Responsable infrastructure, ta manager | Priorités, arbitrages, revues d'architecture |
| Karim Benali | Ingénieur plateforme senior | Revues de MR, standards techniques |
| Sophie Laurent | RSSI | Exigences sécurité, audits, conformité HDS |
| Julien Petit | Lead dev de l'application « MédiAgenda » | Besoins des équipes de développement |
| Nadia Roussel | Responsable support / astreinte | Incidents, runbooks, post-mortems |
| Lucas Martin | Stagiaire de l'équipe Plateforme | Produit des configs à relire (exercices `REV`) |
| Prestataire « InfoGér » | Ancien infogérant | Documentation incomplète, legacy à migrer |

Applications métier (servent de charges de travail réalistes dans les labs) :

| Application | Description | Stack |
|---|---|---|
| **MédiAgenda** | Prise de rendez-vous en ligne | API Python (FastAPI) + PostgreSQL + Valkey |
| **MédiDoc** | Gestion de documents patients | Go + stockage objet S3 (SeaweedFS du socle ou Ceph RGW) |
| **MédiNotif** | Notifications SMS/mail | Worker consommant Kafka/RabbitMQ |
| **Legacy-RDV** | Ancienne application monolithique | PHP + MariaDB sur VM, à migrer |

Ces applications sont fournies dans le dépôt (code minimal, volontairement simple) à partir du module 12. Avant, les labs portent sur l'infrastructure seule.

## 3. Matériel et contraintes du lab

### 3.1 Inventaire physique

| Hôte | Matériel | Usage dans le workbook |
|---|---|---|
| `pve01` | Xeon E-2378G (8 cœurs / 16 threads), **128 Go RAM**, NVMe 2 To, SSD 2 To, HDD 2 To, Proxmox VE déjà installé | Hyperviseur principal, toute la plateforme du site PAR1 en VMs (dont virtualisation imbriquée) |
| `hp01` | HP ProLiant, Xeon E3-1220L v2 (2 cœurs / 4 threads), **16 Go RAM**, ~2 To HDD, contrôleur iLO | Site PAR2 : Proxmox Backup Server, QDevice, cible de sauvegarde hors site, petit site de repli ; plus tard machine bare-metal pilotée par iLO (module 11) |

⚠️ `hp01` contient aujourd'hui des **photos personnelles**. Le module 00 commence par leur **migration vérifiée** (sommes de contrôle) avant toute réaffectation. Aucun lab ne doit être exécuté sur `hp01` tant que l'exercice de sauvegarde des photos n'est pas validé.

⚠️ `pve01` héberge peut-être déjà des VMs personnelles. Le workbook ne doit **jamais** exiger de réinstaller `pve01` ni de reformater ses disques. Toutes les ressources du lab sont isolées (pool Proxmox `lab`, plages de VMID dédiées, bridge dédié `vmbr1`).

### 3.2 Répartition du stockage de `pve01`

| Disque | Stockage Proxmox (nom recommandé) | Usage |
|---|---|---|
| NVMe 2 To | `local-nvme` (LVM-thin ou ZFS, selon l'existant) | Disques système des VMs, etcd, bases de données |
| SSD 2 To | `ssd-lab` | OSD Ceph virtuels, VMs intensives en I/O |
| HDD 2 To | `hdd-bulk` | ISO, images source, snippets cloud-init, sauvegardes locales, données S3 de `s3-01`, artefacts |

Le module 00 vérifie l'existant et adapte ces noms ; les modules suivants utilisent **ces noms logiques**.

### 3.3 Budget mémoire et « profils de lab »

On ne peut pas tout faire tourner en même temps. Le lab est organisé en **socle permanent** + **un environnement de travail** à la fois, tous en IaC, détruits et recréés à volonté.

| Profil | Contenu | RAM approx. |
|---|---|---|
| **Socle** (permanent dès qu'il existe) | `gw01`, `adm01`, `dns01`, `dns02`, `ca01`, `git01` (GitLab), `runner01`, `nbx01` (NetBox), `s3-01` (S3 SeaweedFS) | ~24 Go |
| Profil **infra** | Cluster Proxmox imbriqué 3 nœuds + Ceph | ~40 Go |
| Profil **openstack** | Déploiement Kolla-Ansible multi-nœuds | ~48 Go |
| Profil **k8s** | Cluster Kubernetes 3 CP + 3 workers + LB | ~36 Go |
| Profil **plateforme** (finaux) | k8s + observabilité + sécurité + CI/CD | ~80 Go |

Chaque module indique le profil requis en tête. Règle : **un seul profil lourd actif à la fois** en plus du socle.

## 4. Architecture réseau de référence

### 4.1 Principe

- Le lab est **isolé** du réseau domestique. Un bridge dédié `vmbr1` (VLAN-aware, sans port physique) porte tous les VLANs du lab.
- Une VM routeur/pare-feu **`gw01`** (Debian, nftables, construit à la main au module 00) relie le lab au réseau domestique (interface WAN sur `vmbr0`, NAT sortant). C'est volontairement un routeur Linux et non une appliance : c'est un terrain d'exercice.
- Le réseau domestique de l'apprenant est noté `<LAN-MAISON>` (ex. `192.168.1.0/24`). Le module 00 le documente dans `lab/inventaire-local.md` (fichier ignoré par git si l'apprenant le souhaite).
- Accès de l'apprenant au lab : route statique ou **WireGuard** depuis son poste vers `gw01` (exercice du module 00).

### 4.2 Plan d'adressage — site PAR1 (`10.10.0.0/16`)

| VLAN | Nom | Sous-réseau | Passerelle | Usage |
|---|---|---|---|---|
| 10 | MGMT | 10.10.10.0/24 | 10.10.10.1 | Hyperviseurs imbriqués, interfaces d'admin, bastion |
| 20 | INFRA | 10.10.20.0/24 | 10.10.20.1 | Services socle (DNS, PKI, GitLab, NetBox, Vault, S3…) |
| 30 | STOR-PUB | 10.10.30.0/24 | 10.10.30.1 | Ceph public network, NFS, iSCSI |
| 31 | STOR-CLU | 10.10.31.0/24 | — (non routé) | Ceph cluster network (réplication) |
| 32 | COROSYNC | 10.10.32.0/24 | — (non routé) | Corosync du cluster Proxmox imbriqué |
| 40 | K8S | 10.10.40.0/24 | 10.10.40.1 | Nœuds Kubernetes |
| 41 | K8S-LB | 10.10.41.0/24 | — (annoncé en BGP) | Pool d'IP de services (MetalLB / Cilium LB IPAM) |
| 50 | OS-API | 10.10.50.0/24 | 10.10.50.1 | OpenStack management / API |
| 51 | OS-TUN | 10.10.51.0/24 | — (non routé) | OpenStack overlay (Geneve) |
| 52 | OS-EXT | 10.10.52.0/24 | 10.10.52.1 | OpenStack provider / floating IPs |
| 60 | PROV | 10.10.60.0/24 | 10.10.60.1 | Provisioning PXE (module 11) |
| 70 | DMZ | 10.10.70.0/24 | 10.10.70.1 | Points d'entrée exposés (reverse proxies) |
| 99 | SANDBOX | 10.10.99.0/24 | 10.10.99.1 | Exercices jetables, break & fix |

Convention d'adresses dans chaque /24 :
- `.1` : passerelle (`gw01`) ; `.2-.3` : réservées (VRRP futur `gw02`, VIP) ;
- `.10-.49` : adresses statiques de services ;
- `.50-.99` : nœuds de clusters ;
- `.100-.199` : DHCP / provisioning dynamique ;
- `.200-.249` : VIP et pools d'IP flottantes ;
- `.250-.254` : réservées équipements / tests.

### 4.3 Site PAR2 (`10.20.0.0/16`) et interconnexion

| Réseau | Sous-réseau | Usage |
|---|---|---|
| PAR2 MGMT | 10.20.10.0/24 | `hp01` (Proxmox ou PBS), iLO |
| PAR2 INFRA | 10.20.20.0/24 | Services de secours |
| Interco WireGuard | 10.255.0.0/30 | Tunnel `gw01` `wg0` (10.255.0.1, UDP 51820) ↔ `hp01` (10.255.0.2) |
| VPN d'administration | 10.255.1.0/24 | `gw01` `wg1` (10.255.1.1, UDP 51821) ↔ poste de l'apprenant (10.255.1.2+) |

`hp01` est physiquement sur le LAN maison ; l'interconnexion simule une liaison inter-sites chiffrée au-dessus de ce LAN. Son adresse PAR2 (10.20.10.10) est portée par un bridge sans port physique (`vmbr1` sur `hp01`), joignable uniquement à travers le tunnel.

### 4.3 bis Détails d'implémentation figés (module 00)

| Élément | Valeur |
|---|---|
| Interfaces de `gw01` | `ens18` = WAN (sur `vmbr0`, adresse du LAN maison), `ens19` = trunk (sur `vmbr1`, sans tag), sous-interfaces VLAN `ens19.<VLAN>` |
| Pare-feu de `gw01` | nftables, fichier `/etc/nftables.conf`, tables `inet filter` et `ip nat` |
| Serveur de temps du lab | `gw01` (chrony), synchronisé sur Internet ; toutes les VMs du lab se synchronisent sur la passerelle de leur VLAN |
| DNS provisoire | dnsmasq sur `dns01`, fichier `/etc/dnsmasq.d/medisphere.conf` (remplacé par PowerDNS et Kea au module 06). Tout nouvel hôte du socle créé avant M06 est ajouté par `host-record` dans ce fichier |
| Template de base | VMID 9000 `tpl-debian13`, image Debian 13 *genericcloud*, cloud-init, agent QEMU, console série |
| Pool Proxmox | `lab` (toutes les VMs du workbook) |
| Comptes Proxmox | `wb-admin@pve` (humain, groupe `wb-admins`), `wb-automation@pve` + jeton `wb-automation@pve!lab` (automatisation, rôle personnalisé `WBAutomation`) |
| Zone SDN | zone VLAN `lab` sur `vmbr1` ; VNets `vmgmt`(10), `vinfra`(20), `vstopub`(30), `vstoclu`(31), `vcoro`(32), `vk8s`(40), `vk8slb`(41), `vosapi`(50), `vostun`(51), `vosext`(52), `vprov`(60), `vdmz`(70), `vsandbox`(99) |
| Routes du tunnel côté `hp01` | `wg0.conf` avec `Table = off` ; routes 10.10.0.0/16 et 10.255.1.0/24 via `wg0` posées en `PostUp` avec `src 10.20.10.10` (le trafic de `pbs01` vers PAR1 part donc de 10.20.10.10) |
| Retour VPN sur `pve01` | route statique 10.255.1.0/24 via `<IP-GW01-WAN>` (en plus de 10.10.0.0/16 et 10.20.0.0/16) |
| Règle NTP sur `gw01` | introduite au M00-E31 (pas avant) |
| sudo | `gw01` : `/etc/sudoers.d/90-workbook` (M00-E10) ; VMs issues du template : utilisateur cloud-init `admin` avec sudo sans mot de passe |
| PBS | `pbs01` = `hp01` réinstallé en Proxmox Backup Server ; datastore `ds-lab` sur le HDD ; stockage côté `pve01` nommé `pbs-par2` ; namespace `par1` |

### 4.4 Nommage

- Domaine interne : **`medisphere.internal`** (le TLD `.internal` est réservé à l'usage privé).
- Sous-domaines de site : `par1.medisphere.internal`, `par2.medisphere.internal`.
- Noms d'hôtes : `<rôle><nn>` en minuscules, ex. `gw01`, `adm01`, `k8s-cp01`, `ceph01`. FQDN : `adm01.par1.medisphere.internal`.
- Noms de VMs Proxmox = nom d'hôte court.

### 4.5 Adresses fixes du socle

| Hôte | VMID | VLAN | IP | Rôle | Module de création |
|---|---|---|---|---|---|
| `gw01` | 1000 | WAN + trunk | 10.10.x.1 | Routeur / pare-feu / NAT / NTP / VPN | 00 |
| `adm01` | 1001 | MGMT | 10.10.10.10 | Poste d'admin / bastion / outillage | 00 |
| `dns01` | 1002 | INFRA | 10.10.20.10 | DNS faisant autorité + récursif | 00 (dnsmasq provisoire), 06 (PowerDNS) |
| `ca01` | 1003 | INFRA | 10.10.20.11 | PKI interne (step-ca) | 06 |
| `git01` | 1004 | INFRA | 10.10.20.12 | GitLab CE | 01 |
| `nbx01` | 1005 | INFRA | 10.10.20.13 | NetBox | 06 |
| `s3-01` | 1006 | INFRA | 10.10.20.14 | Stockage objet S3 du socle, **SeaweedFS** (état OpenTofu, artefacts) — MinIO abandonné, voir journal | 05 |
| `runner01` | 1007 | INFRA | 10.10.20.15 | GitLab Runner (exécuteur `shell`) du socle | 01 |
| `dns02` | 1008 | INFRA | 10.10.20.16 | DNS secondaire (PowerDNS autoritaire secondaire + récurseur), DHCP Kea de secours | 06 |
| `vault01-03` | 1021-1023 | INFRA | 10.10.20.21-23 | Vault/OpenBao | 25 |
| `idp01` | 1030 | INFRA | 10.10.20.30 | Keycloak | 24 |
| `pbs01` (= `hp01`) | — (physique) | PAR2 MGMT | 10.20.10.10 | Proxmox Backup Server | 00 |

Les modules suivants complètent ce tableau ici même (section 4.5) lorsqu'ils introduisent un nouvel hôte permanent.

### 4.6 Plages de VMID Proxmox

| Plage | Usage |
|---|---|
| 1000-1099 | Socle permanent |
| 9000-9099 | Templates (images dorées) |
| 2000-2999 | Environnements des modules : `2000 + numéro_module*10 + n` (ex. module 14 → 2140-2149) quand ≤ 10 VMs ; sinon plage documentée dans le module |
| 3000-3999 | Workbooks finaux |
| 5000-5999 | Sandbox / break & fix (détruites librement). Module 00 : 5001-5009 VMs jetables `sbxNN`, 5044 `sbx44` (E44), 5048 `sbx48` (E48), 5090-5099 restaurations de test |

### 4.7 Emplacements de travail de l'apprenant

| Élément | Emplacement |
|---|---|
| Dépôt du workbook | cloné sur `pve01` (`/root/DevOpsPrivateCloud`) puis sur `adm01` (`~/DevOpsPrivateCloud`) |
| Configuration locale des checks | `lab/lab.env` (copié de `lab/lab.env.example`, non versionné) |
| Dépôt de documentation et de code MédiSphère | `~/medisphere` sur `adm01` (variable `WB_DEPOT`) : `docs/socle/` (schémas, inventaire, matrice des flux), `docs/socle/runbooks/`, `docs/socle/adr/`. Migré vers GitLab au module 01 |
| Templates de VMs | sur `local-nvme` (permet les clones liés) ; images source et snippets cloud-init sur `hdd-bulk` |

### 4.8 Détails figés du bloc A (modules 01 à 06)

| Élément | Valeur |
|---|---|
| Secrets locaux de l'apprenant sur `adm01` | dossier `~/.config/workbook/` (700), fichiers 600, jamais dans un dépôt. Existant : `pve-api.env` (M00-E17) |
| Clones de travail sur `adm01` | `~/medisphere` (documentation, `WB_DEPOT`) ; autres projets sous `~/src/<projet>` (variable `WB_SRC`) |
| GitLab CE | `git01` (VMID 1004, 10.10.20.12, 4 vCPU, 8 Go, profil « mémoire contrainte »), URL `https://git01.par1.medisphere.internal`, Git en SSH `git@git01.par1.medisphere.internal` (sshd système, port 22) |
| PKI provisoire (M01 → M06) | CA « MédiSphère CA provisoire » créée avec `openssl` sur `adm01` dans `~/pki-provisoire/` (clé privée hors dépôt). Racine installée sous `/usr/local/share/ca-certificates/medisphere-provisoire.crt` sur les VMs qui en ont besoin. Retirée au M06 au profit de step-ca |
| Comptes GitLab | `root` (bris de glace), compte personnel de l'apprenant `<MOI>` (admin), comptes des personnages `claire.morel`, `karim.benali`, `sophie.laurent`, `julien.petit`, `nadia.roussel`, `lucas.martin` (servent aux revues et MR simulées). Jeton personnel en lecture (`read_api`, expiration obligatoire) pour les checks : `~/.config/workbook/gitlab-checks.token` |
| Groupes et projets GitLab | `plateforme/medisphere` (doc, M01), `plateforme/outils` (scripts et CLI `medictl`, M02), `plateforme/images` (Packer, M03), `plateforme/ansible` (M04), `plateforme/tofu-modules` et `plateforme/infra` (M05) ; `formation/git-labo` (exercices Git du M01). Branche par défaut `main`, protégée, fusion par MR, Conventional Commits, étiquettes `vX.Y.Z` posées par semantic-release |
| Runner | `runner01` (VMID 1007, 10.10.20.15, 2 vCPU, 4 Go), GitLab Runner exécuteur `shell`, étiquettes `shell` et `socle`, jeton `glrt-` ; les outils nécessaires aux pipelines du bloc A y sont installés par les modules (puis par Ansible à partir du M04). Les exécuteurs Docker/Kubernetes arrivent aux modules 12 et 19 |
| Node.js | 24 LTS (dépôt NodeSource) sur `adm01` et `runner01`, pour semantic-release et commitlint (Node 20 de Debian 13 trop ancien) |
| Python | 3.13 de Debian 13 ; projets gérés par `uv` (`pyproject.toml` + `uv.lock`) ; outils Python (Ansible, ansible-lint, Molecule, pre-commit, Checkov) installés dans l'environnement du projet ou par `uv tool install`, jamais par `pip` global |
| Comptes Proxmox d'automatisation | `wb-automation@pve!lab` (M00, scripts et `medictl`), `wb-packer@pve!packer` (M03), `wb-ansible@pve!ansible` (M04, inventaire dynamique et Molecule), `wb-tofu@pve!tofu` (M05). Chacun avec un rôle dédié à privilèges minimaux et son fichier `~/.config/workbook/pve-<outil>.env` ; en CI, variables protégées et masquées du projet |
| Images dorées (M03) | 9000 `tpl-debian13` (manuel, M00) conservé ; 9001 `tpl-debian13-base` (Packer depuis l'ISO) ; 9002 `tpl-rocky10-base` ; 9010-9029 `deb13-gold-AAAAMMJJ-N` ; 9030-9049 `rocky10-gold-AAAAMMJJ-N` ; 9090-9099 builds temporaires. Étiquettes Proxmox : `gold`, `debian13`/`rocky10`, et `current` sur la seule version validée de chaque famille (c'est elle que consomment Ansible/Molecule et OpenTofu). Rocky 10 exige un CPU `x86-64-v3` ou `host` |
| VMs d'environnement du bloc A | plage `2000 + module*10 + n` : M01 2010-2019, M02 2020-2029, M03 2030-2039, M04 2040-2049 (2041 `sem01` Semaphore UI, VNet `vinfra`, 10.10.20.41 ; 2045-2049 instances Molecule), M05 2050-2059, M06 2060-2069 ; toutes dans le pool `lab`, sur le VNet `vsandbox` (DHCP) sauf mention contraire |
| Étiquettes Proxmox des VMs | `socle` (VMs permanentes du socle), `role-<rôle>` (`role-routeur`, `role-bastion`, `role-dns`, `role-gitlab`, `role-runner`, `role-s3`, `role-pki`, `role-netbox`), `env-mNN` (VMs d'environnement d'un module), `molecule` (instances de test) ; templates : `gold`, `debian13`/`rocky10`, `current`. Elles alimentent l'inventaire dynamique Ansible (M04) et les sources de données OpenTofu (M05) |
| Gabarits CI partagés (M01) | projet `plateforme/ci-templates` (inclus par `include: project`) : `qualite.yml` (pre-commit, Gitleaks), `release.yml` (semantic-release, jeton de projet `GITLAB_TOKEN` en variable protégée et masquée) ; étendu par les modules suivants |
| Numérotation de la documentation | Dans `plateforme/medisphere` (`docs/socle/`) : ADR du module NN numérotés à partir de `ADR-00N0` (M01 : ADR-0010…, M06 : ADR-0060…), runbooks `RB-NN0` à `RB-NN9` (M01 : RB-010…). Tickets des énoncés : `PLAT-`/`SEC-`/`DEV-`/`CHG-` numérotés `(NN+1)xx` (M01 : PLAT-2xx), incidents `INC-(NN+27)xx` (M01 : INC-27xx) |
| Flux réseau ajoutés au bloc A | Tout nouveau flux est ouvert de façon ciblée sur `gw01` (`/etc/nftables.conf`, règle commentée) **et**, s'il vise `pve01`, dans le pare-feu Proxmox (IPSet `automation` pour `runner01`), puis reporté dans `docs/socle/matrice-flux.md`. Rappel M00 : MGMT (`adm01`) joint tout le lab ; les autres VLANs ne se joignent pas entre eux (hors DNS) ; tout le lab sort vers Internet |
| Ansible (M04) | projet `plateforme/ansible` : `ansible.cfg`, `inventories/lab/` (statique puis dynamique), `roles/`, `playbooks/`, `collections/requirements.yml` ; secrets en Ansible Vault, mot de passe dans `~/.config/workbook/ansible-vault.pass` |
| OpenTofu (M05) | provider `bpg/proxmox` épinglé `~> 0.115.0` ; état distant S3 sur `s3-01` : endpoint `https://s3-01.par1.medisphere.internal:8333`, compartiment `tofu-state`, verrou natif `use_lockfile = true`, versionnage activé ; identifiants dans `~/.config/workbook/s3-tofu.env`. Les VMs du socle importées dans l'état portent `lifecycle { prevent_destroy = true }` |
| PKI (M06) | step-ca sur `ca01` (10.10.20.11, port 443) : racine « MédiSphère Root CA » (clé hors ligne, sauvegardée chiffrée), intermédiaire en ligne ; provisioner ACME `acme` (certificats serveur de 30 jours max.), provisioner JWK `admin`, CA SSH (certificats d'hôte et d'utilisateur). Racine installée sous `/usr/local/share/ca-certificates/medisphere-root-ca.crt` |
| NetBox (M06) | `nbx01` (10.10.20.13), NetBox 4.6.x installé nativement (PostgreSQL 17, Valkey, gunicorn, nginx) par un rôle Ansible ; URL `https://nbx01.par1.medisphere.internal` ; jetons v2 ; jeton en lecture des checks : `~/.config/workbook/netbox-checks.token` |
| DNS (M06) | `dns01` : PowerDNS Recursor écoute 10.10.20.10:53 (adresse utilisée par tout le lab) ; PowerDNS Authoritative écoute 127.0.0.1:5300 et 10.10.20.10:5300, API sur 10.10.20.10:8081 (filtrée) ; zones `par1.medisphere.internal`, `par2.medisphere.internal`, inverses `10.10.in-addr.arpa`, `20.10.in-addr.arpa`. `dns02` (10.10.20.16) : autoritaire secondaire + récurseur. Paquets du dépôt officiel repo.powerdns.com |
| DHCP (M06) | Kea DHCPv4 3.0.x (dépôt ISC Cloudsmith `kea-3-0`) sur `dns01` (puis `dns02` en hot-standby), remplace le DHCP de dnsmasq ; le relais de `gw01` (M00-E14) est inchangé |

## 5. Structure du workbook

### 5.1 Parcours

```
Bloc A  Fondations automatisées      00 → 06
Bloc B  Infrastructure cloud privé   07 → 11
Bloc C  Conteneurs et Kubernetes     12 → 18
Bloc D  Livraison                    19 → 20
Bloc E  Observabilité                21 → 23
Bloc F  Sécurité                     24 → 26
Bloc G  Services de plateforme       27 → 29
Finaux                               F1 → F7
```

Niveaux de traitement : **Cœur** (approfondi, 40-60 exercices), **Secondaire** (20-30 exercices), **Découverte** (fiches et 1-5 exercices, regroupés dans `annexes/decouverte/`).

### 5.2 Modules

| # | Module | Niveau | Technos principales | Profil lab | Prérequis |
|---|---|---|---|---|---|
| 00 | Positionnement et montage du lab | Cœur | Linux/réseau (diagnostic), Proxmox VE avancé (réseau, SDN, stockage, API, pools, permissions), nftables, WireGuard, Proxmox Backup Server, cloud-init manuel | Socle | — |
| 01 | Git et workflow professionnel | Cœur | Git avancé (rebase, bisect, hooks, worktrees), GitLab CE auto-hébergé, MR et revue, protections de branches, pre-commit, Conventional Commits, semantic-release, Gitleaks | Socle | 00 |
| 02 | Scripting d'automatisation | Cœur | Bash avancé, ShellCheck, Python (venv/uv, requests, click/typer, API Proxmox via proxmoxer), jq, yq, Make/Taskfile, tests (bats, pytest) | Socle | 01 |
| 03 | Images dorées | Secondaire | Packer (proxmox-iso, proxmox-clone), cloud-init avancé, durcissement d'image, versionnage d'images | Socle | 02 |
| 04 | Gestion de configuration | Cœur | Ansible (inventaires dynamiques, rôles, collections, Jinja2, handlers, delegate, strategies), Ansible Vault, ansible-lint, Molecule, AWX, comparaison Puppet/Salt (fiche) | Socle | 03 |
| 05 | Infrastructure as Code | Cœur | OpenTofu/Terraform (provider bpg/proxmox), modules, état distant S3 (SeaweedFS sur `s3-01`) + verrouillage, workspaces, import, refactoring (moved), Terragrunt, tflint, Checkov/Trivy, terraform-docs, Infracost (fiche) | Socle | 04 |
| 06 | Services socle | Cœur | NetBox (IPAM/DCIM, source de vérité, API, inventaire Ansible), PowerDNS (authoritative + recursor, API), Kea DHCP, step-ca (PKI, ACME), chrony, bastion SSH (certificats SSH) | Socle | 05 |
| 07 | Réseau datacenter et haute disponibilité | Cœur | Bonding/LACP (simulé), VLAN, Open vSwitch, FRR (BGP, OSPF), keepalived/VRRP, HAProxy, Nginx, MTU/jumbo frames, WireGuard multi-sites | Socle + sandbox | 06 |
| 08 | Stockage distribué | Cœur | Ceph (cephadm, CRUSH, pools, RBD, CephFS, RGW S3, dashboard, upgrades), pannes d'OSD/MON, performances, ZFS (rappels), NFS/iSCSI | infra | 07 |
| 09 | Cluster de virtualisation | Cœur | Cluster Proxmox imbriqué 3 nœuds, Corosync/quorum, QDevice sur `hp01`, HA, Ceph hyperconvergé, SDN, migration à chaud, PBS, réplication | infra | 08 |
| 10 | OpenStack | Cœur | Kolla-Ansible, Keystone, Glance, Nova, Neutron/OVN, Cinder (Ceph), Octavia, Heat, Designate (fiche), Horizon, CLI, Terraform OpenStack, quotas et projets | openstack | 08, 05 |
| 11 | Provisioning bare-metal | Secondaire | PXE/iPXE, DHCP/TFTP/HTTP boot, preseed/kickstart, MAAS ou Tinkerbell, IPMI/Redfish (iLO de `hp01`), intégration NetBox | Socle + `hp01` | 06, 07 |
| 12 | Conteneurs | Cœur | Docker, Podman (rootless, pods, Quadlet), Buildah, Skopeo, BuildKit, multi-stage, Compose, Hadolint, Dive, namespaces/cgroups en profondeur, containerd/runc | Socle | 04 |
| 13 | Registre et supply chain | Secondaire | Harbor (projets, réplication, robots, quotas), Trivy, Syft (SBOM), Grype, Cosign/Sigstore, politiques de signature, Renovate | Socle | 12 |
| 14 | Administration Kubernetes | Cœur | kubeadm HA (stacked etcd), etcd (sauvegarde/restauration), RBAC, ServiceAccounts, admission, scheduling, upgrades, certificats, troubleshooting nœuds/pods, kubectl/k9s | k8s | 12, 07 |
| 15 | Réseau Kubernetes | Cœur | Cilium (eBPF, NetworkPolicy, Hubble, LB IPAM, BGP control plane), Gateway API, ingress-nginx (comparaison), MetalLB, cert-manager (step-ca ACME), ExternalDNS (PowerDNS), CoreDNS | k8s | 14 |
| 16 | Stockage et données Kubernetes | Cœur | CSI, StorageClasses, Rook-Ceph, Ceph-CSI externe, Longhorn, snapshots, Velero (S3 du socle), CloudNativePG | k8s + infra | 14, 08 |
| 17 | Packaging | Secondaire | Helm (charts, dépendances, tests, OCI), Kustomize (overlays, components), Helmfile | k8s | 14 |
| 18 | Distributions et cycle de vie | Secondaire | k3s, RKE2, Talos Linux, Cluster API (providers Proxmox et OpenStack), kind/k3d pour le dev | k8s | 14, 05 |
| 19 | Intégration continue | Cœur | GitLab CI (stages, rules, needs, templates, includes, environnements), runners sur Kubernetes, BuildKit/Kaniko, caches, Jenkins (fiche + exercices), SonarQube, Semgrep | k8s | 01, 13, 17 |
| 20 | GitOps et déploiement continu | Cœur | Argo CD (App of Apps, ApplicationSets, sync waves, RBAC, multi-cluster), Argo Rollouts (canary, blue/green, analyses), Flux (comparaison), stratégies de promotion | k8s | 19 |
| 21 | Métriques et alerting | Cœur | Prometheus (PromQL, relabeling, recording rules), Alertmanager, Grafana (dashboards as code), exporters, kube-prometheus-stack, Thanos ou Mimir, SLI/SLO, error budgets | k8s | 14 |
| 22 | Logs | Secondaire | Loki, Grafana Alloy, Fluent Bit, OpenSearch, rétention, logs d'audit, journald | k8s | 21 |
| 23 | Traces et profiling | Secondaire | OpenTelemetry (SDK, Collector), Tempo, Jaeger, corrélation logs/métriques/traces, Pyroscope | k8s | 21, 22 |
| 24 | Identité et accès | Cœur | Keycloak (realms, clients OIDC/SAML, fédération LDAP), FreeIPA, SSO pour Proxmox/GitLab/Grafana/Kubernetes/Argo CD, OAuth2 Proxy, Teleport | Socle + k8s | 06, 14 |
| 25 | Secrets | Cœur | Vault/OpenBao (HA Raft, auto-unseal, moteurs KV/PKI/database/transit, auth Kubernetes/OIDC, policies), External Secrets Operator, SOPS + age, Sealed Secrets (comparaison) | Socle + k8s | 24 |
| 26 | Durcissement et sécurité runtime | Cœur | CIS Benchmarks, Lynis, OpenSCAP, kube-bench, kubescape, Kyverno, Pod Security Admission, Falco, Tetragon, audit Kubernetes, SELinux/AppArmor | k8s | 25 |
| 27 | Données et messaging | Secondaire | PostgreSQL HA (CloudNativePG, Patroni en comparaison), Valkey, Kafka (Strimzi), RabbitMQ (operator), NATS (fiche), migrations (Flyway) | k8s | 16 |
| 28 | Plateforme développeurs | Secondaire | KEDA, HPA/VPA, Backstage, vCluster, Capsule, Crossplane (fiche), Tilt/Skaffold (fiche) | k8s | 20, 25 |
| 29 | Tests et résilience | Secondaire | k6, Chaos Mesh, LitmusChaos, Terratest, conftest/OPA, Testinfra/Goss, kubeconform | k8s | 20, 21 |

### 5.3 Workbooks finaux

| # | Scénario | Contenu | Prérequis |
|---|---|---|---|
| F1 | **Day 0 — Construire MédiSphère** | Du bare-metal à la première application en production, tout en IaC et GitOps | Blocs A-D |
| F2 | **Day 1 — Accueillir les équipes** | Multi-tenancy, self-service, SSO, quotas, pipelines standards, onboarding de 3 équipes | F1, blocs E-F |
| F3 | **Day 2 — Semaine d'astreinte** | Incidents injectés en chaîne, diagnostic, communication, post-mortems | F2 |
| F4 | **Changements majeurs** | Upgrades Kubernetes/Ceph/OpenStack sans interruption, migration Legacy-RDV de VM vers Kubernetes, migration VMware→Proxmox (simulée) | F2 |
| F5 | **PRA multi-site** | Perte de PAR1, bascule sur PAR2, restaurations, RTO/RPO mesurés, exercice de PRA documenté | F2 |
| F6 | **Sécurité et conformité** | Audit type HDS/ISO 27001, plan de remédiation, réponse à incident (conteneur compromis) | F2, bloc F |
| F7 | **Capstone** | Réponse à un cahier des charges : architecture, ADR, chiffrage, livraison, dossier de soutenance | Tout |

### 5.4 Hors périmètre (ou annexes « découverte »)

Clouds publics (AWS, Azure, GCP) en profondeur, serverless managé, data engineering (Airflow, Spark, Flink, Trino, Ozone), PowerShell, Rust/Ruby, outils SaaS (Datadog, Snyk, Spacelift…). Ils peuvent faire l'objet de fiches dans `annexes/decouverte/` (comparaison avec l'équivalent auto-hébergé traité dans le workbook).

## 6. Versions de référence

Les versions sont **figées au démarrage de chaque bloc** : la conversation qui produit un bloc vérifie la dernière version stable de chaque outil, puis renseigne ce tableau. Les modules citent ces versions et non « latest ».

| Outil | Version de référence | Fixée le | Remarque |
|---|---|---|---|
| Proxmox VE | 9.x (Debian 13) | 2026-10 (bloc A) | À adapter si `pve01` est encore en 8.x : le module 00 contient un exercice de vérification de version et de plan de montée de version |
| Proxmox Backup Server | 4.x | 2026-10 (bloc A) | |
| Debian (VMs) | 13 « trixie » | 2026-10 (bloc A) | OS par défaut des VMs |
| Rocky Linux (VMs) | 10.x | 2026-10 (bloc A) | Utilisé ponctuellement (famille RHEL) |
| Ubuntu (VMs) | 24.04 LTS | 2026-10 (bloc A) | Uniquement quand un outil l'impose |
| Git | 2.47.x (paquet Debian 13) ; amont 2.56 | 2026-10 (bloc A) | `init.defaultBranch=main` à fixer explicitement |
| GitLab CE / GitLab Runner | 19.4.x / 19.4.x (paquets omnibus pour Debian 13) | 2026-10 (bloc A) | Montée de version mineure autorisée en suivant le chemin officiel (M01) |
| pre-commit / Gitleaks / commitlint / semantic-release | 4.6.x / 8.30.x / 21.x / 25.x (+ `@semantic-release/gitlab` 13.x) | 2026-10 (bloc A) | Node.js 24 LTS requis |
| ShellCheck / shfmt / bats-core | 0.11.0 (trixie-backports ; 0.10 dans Debian) / 3.14.x / 1.13.x | 2026-10 (bloc A) | |
| Python / uv / Typer / proxmoxer / pytest / ruff | 3.13 (Debian 13) / 0.12.x / 0.27.x / 2.3.x / 9.x / 0.16.x | 2026-10 (bloc A) | |
| jq / yq / Task | 1.8.x (binaire amont ; 1.7.1 dans Debian) / yq **mikefarah** 4.54.x / Task 3.54.x | 2026-10 (bloc A) | Le paquet Debian `yq` est un autre outil |
| Packer / plugin proxmox | 1.16.x (dépôt APT HashiCorp, licence BUSL) / `hashicorp/proxmox` 1.2.x | 2026-10 (bloc A) | Syntaxe `boot_iso {}` uniquement |
| cloud-init | 25.1.x (images Debian 13) | 2026-10 (bloc A) | |
| ansible-core / ansible-lint / Molecule | 2.21.x (environnement `uv` du projet ; compatible 2.19 de Debian) / 26.x / 26.x (pilote `default`, approche « ansible-native ») | 2026-10 (bloc A) | Collections : `community.proxmox` 2.x, `community.general` 13.x, `netbox.netbox` 3.23.x |
| Semaphore UI / AWX | 2.19.x / AWX 24.6.1 (figé, développement en pause) | 2026-10 (bloc A) | AWX traité en fiche, Semaphore UI en exercice |
| OpenTofu / Terraform | 1.13.x / 1.16.x (BUSL, comparaison seulement) | 2026-10 (bloc A) | Outil du workbook : OpenTofu |
| Provider bpg/proxmox | `~> 0.115.0` | 2026-10 (bloc A) | Toujours en 0.x : ruptures possibles entre mineures |
| Terragrunt / tflint / Checkov / Trivy / terraform-docs | 1.1.x / 0.64.x / 3.3.x / 0.75.x (épinglé par empreinte) / 0.24.x | 2026-10 (bloc A) | Trivy : compromission de mars 2026 (v0.69.4) |
| SeaweedFS | 4.4x (binaire `weed`) | 2026-10 (bloc A) | Remplace MinIO (édition communautaire abandonnée) |
| NetBox | 4.6.x (installation native) | 2026-10 (bloc A) | 4.7 disponible mais non validée avec `netbox.netbox` et le provider NetBox |
| PowerDNS Authoritative / Recursor | 5.0.x / 5.4.x (repo.powerdns.com, suites `trixie-auth-50` et `trixie-rec-54`) | 2026-10 (bloc A) | Recursor : configuration YAML |
| Kea DHCP | 3.0.x (dépôt ISC Cloudsmith `kea-3-0`) | 2026-10 (bloc A) | Kea 2.6 de Debian 13 en fin de vie ; Control Agent supprimé en 3.2 |
| step-ca / step CLI | 0.30.x / 0.31.x (dépôt apt Smallstep) | 2026-10 (bloc A) | step-ca 0.20 de Debian 13 obsolète |
| chrony | 4.6.x (Debian 13) | 2026-10 (bloc A) | NTS disponible |
| *Autres outils* | *à fixer au démarrage de leur bloc* | | |

Les **changements de comportement** de ces versions qui touchent les exercices (CONVENTIONS §11.9) sont détaillés dans [`annexes/versions-bloc-A.md`](annexes/versions-bloc-A.md).

## 7. Conventions transverses

Voir `CONVENTIONS.md` (format des exercices, des corrigés, scripts de vérification, injection de pannes, style rédactionnel).

## 8. Journal des décisions

| Date | Décision |
|---|---|
| 2026-10-03 | Création du plan. Fil rouge MédiSphère, deux sites PAR1/PAR2, domaine `medisphere.internal`, plan d'adressage 10.10.0.0/16 et 10.20.0.0/16, 30 modules + 7 finaux, une conversation par bloc. |
| 2026-10-03 | Bloc A : versions figées (§6). **MinIO remplacé par SeaweedFS** pour `s3-01` : l'édition communautaire de MinIO n'a plus de binaires ni d'images depuis octobre 2025 et son dépôt est archivé (février 2026) ; Garage écarté (pas d'écritures conditionnelles, donc pas de verrou d'état OpenTofu `use_lockfile`). L'abandon de MinIO devient un cas d'étude (ADR M05). |
| 2026-10-03 | Bloc A : ajout des hôtes permanents `runner01` (1007, GitLab Runner `shell`, M01) et `dns02` (1008, DNS/DHCP secondaire, M06). Détails figés du bloc A en §4.8 (projets GitLab, PKI provisoire puis step-ca, comptes d'automatisation Proxmox, VMID des images dorées, état OpenTofu, NetBox, PowerDNS, Kea). |
| 2026-10-03 | Bloc A : AWX traité en fiche (projet sans release depuis juillet 2024, en refonte) ; l'orchestrateur Ansible pratiqué est Semaphore UI. Infracost cité seulement (n'estime que les clouds publics). Molecule pratiqué avec des VMs Proxmox éphémères (pilote `default`, playbooks create/destroy) plutôt qu'avec des conteneurs, introduits au module 12. Bibliothèque commune des scripts de panne des modules 01+ : `lab/lib/pannes-lib.sh` (marqueurs `M<NN>-EXX`). |
