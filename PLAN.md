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
| **MédiDoc** | Gestion de documents patients | Go + stockage objet S3 (MinIO/RGW) |
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
| HDD 2 To | `hdd-bulk` | ISO, images source, snippets cloud-init, sauvegardes locales, MinIO, artefacts |

Le module 00 vérifie l'existant et adapte ces noms ; les modules suivants utilisent **ces noms logiques**.

### 3.3 Budget mémoire et « profils de lab »

On ne peut pas tout faire tourner en même temps. Le lab est organisé en **socle permanent** + **un environnement de travail** à la fois, tous en IaC, détruits et recréés à volonté.

| Profil | Contenu | RAM approx. |
|---|---|---|
| **Socle** (permanent dès qu'il existe) | `gw01`, `adm01`, `dns01`, `ca01`, `git01` (GitLab), `nbx01` (NetBox), `s3-01` (MinIO) | ~24 Go |
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
| 20 | INFRA | 10.10.20.0/24 | 10.10.20.1 | Services socle (DNS, PKI, GitLab, NetBox, Vault, MinIO…) |
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
| DNS provisoire | dnsmasq sur `dns01`, fichier `/etc/dnsmasq.d/medisphere.conf` (remplacé par PowerDNS au module 06) |
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
| `s3-01` | 1006 | INFRA | 10.10.20.14 | MinIO (état Terraform, artefacts) | 05 |
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
| 05 | Infrastructure as Code | Cœur | OpenTofu/Terraform (provider bpg/proxmox), modules, état distant S3 (MinIO) + verrouillage, workspaces, import, refactoring (moved), Terragrunt, tflint, Checkov/Trivy, terraform-docs, Infracost (fiche) | Socle | 04 |
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
| 16 | Stockage et données Kubernetes | Cœur | CSI, StorageClasses, Rook-Ceph, Ceph-CSI externe, Longhorn, snapshots, Velero (MinIO), CloudNativePG | k8s + infra | 14, 08 |
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
| *Autres outils* | *à fixer au démarrage de leur bloc* | | |

## 7. Conventions transverses

Voir `CONVENTIONS.md` (format des exercices, des corrigés, scripts de vérification, injection de pannes, style rédactionnel).

## 8. Journal des décisions

| Date | Décision |
|---|---|
| 2026-10-03 | Création du plan. Fil rouge MédiSphère, deux sites PAR1/PAR2, domaine `medisphere.internal`, plan d'adressage 10.10.0.0/16 et 10.20.0.0/16, 30 modules + 7 finaux, une conversation par bloc. |
