# Prérequis entre modules

> Ce fichier dit **dans quel ordre** suivre le workbook et **ce que chaque module laisse en place** pour les suivants. Les dépendances viennent de [`PLAN.md`](../PLAN.md) §5.2 et §5.3 ; les adresses, VMID et noms, de §4.5 et §4.8. En cas de doute, `PLAN.md` fait foi.

## 1. Graphe des dépendances

Une flèche `X → Y` se lit « Y suppose X terminé ». Les modules en vert sont **disponibles** ; les autres sont à venir (produits bloc par bloc). Les finaux dépendent de blocs entiers.

```mermaid
flowchart LR
  classDef dispo fill:#d8f0d8,stroke:#2e7d32,color:#1b3d1b
  classDef avenir fill:#f2f2f2,stroke:#9e9e9e,color:#555555,stroke-dasharray: 4 3
  classDef final fill:#fff4d6,stroke:#b28704,color:#4d3b00

  subgraph A["Bloc A — Fondations automatisées"]
    m00["00 Lab"] --> m01["01 Git"] --> m02["02 Scripting"] --> m03["03 Images"] --> m04["04 Ansible"] --> m05["05 OpenTofu"] --> m06["06 Services socle"]
  end

  subgraph B["Bloc B — Infrastructure cloud privé"]
    m07["07 Réseau / HA"]
    m08["08 Ceph"]
    m09["09 Cluster Proxmox"]
    m10["10 OpenStack"]
    m11["11 Bare-metal"]
  end

  subgraph C["Bloc C — Conteneurs et Kubernetes"]
    m12["12 Conteneurs"]
    m13["13 Registre / supply chain"]
    m14["14 Kubernetes admin"]
    m15["15 Kubernetes réseau"]
    m16["16 Kubernetes stockage"]
    m17["17 Packaging"]
    m18["18 Distributions"]
  end

  subgraph D["Bloc D — Livraison"]
    m19["19 CI"]
    m20["20 GitOps"]
  end

  subgraph E["Bloc E — Observabilité"]
    m21["21 Métriques"]
    m22["22 Logs"]
    m23["23 Traces"]
  end

  subgraph F["Bloc F — Sécurité"]
    m24["24 Identité"]
    m25["25 Secrets"]
    m26["26 Durcissement"]
  end

  subgraph G["Bloc G — Services de plateforme"]
    m27["27 Données / messaging"]
    m28["28 Plateforme dev"]
    m29["29 Tests / résilience"]
  end

  m06 --> m07 --> m08 --> m09
  m08 --> m10
  m05 --> m10
  m06 --> m11
  m07 --> m11
  m09 -.-> m11
  m04 --> m12 --> m13
  m12 --> m14
  m07 --> m14
  m14 --> m15
  m14 --> m16
  m08 --> m16
  m14 --> m17
  m14 --> m18
  m05 --> m18
  m01 --> m19
  m13 --> m19
  m17 --> m19
  m19 --> m20
  m14 --> m21 --> m22
  m21 --> m23
  m22 --> m23
  m06 --> m24
  m14 --> m24
  m24 --> m25 --> m26
  m16 --> m27
  m20 --> m28
  m25 --> m28
  m20 --> m29
  m21 --> m29

  F1["F1 Day 0"]
  F2["F2 Day 1"]
  F3["F3 Astreinte"]
  F4["F4 Changements majeurs"]
  F5["F5 PRA multi-site"]
  F6["F6 Sécurité et conformité"]
  F7["F7 Capstone"]

  A --> F1
  B --> F1
  C --> F1
  D --> F1
  F1 --> F2
  E --> F2
  F --> F2
  F2 --> F3
  F2 --> F4
  F2 --> F5
  F2 --> F6
  F --> F6
  F3 --> F7
  F4 --> F7
  F5 --> F7
  F6 --> F7
  G --> F7

  class m00,m01,m02,m03,m04,m05,m06,m07,m08,m09,m10,m11 dispo
  class m12,m13,m14,m15,m16,m17,m18,m19,m20,m21,m22,m23,m24,m25,m26,m27,m28,m29 avenir
  class F1,F2,F3,F4,F5,F6,F7 final
```

Lecture rapide :

- Le **bloc A** est une chaîne stricte : chaque module consomme ce que le précédent a livré (forge → outils → images → configuration → infrastructure déclarée → services socle).
- Après le module 06, deux grandes branches s'ouvrent : **infrastructure** (07 → 08 → 09, 10, 11) et **conteneurs** (12 → 14 → 15-18), qui ne se rejoignent qu'au module 16 (Ceph pour Kubernetes) et dans les finaux.
- Dans le **bloc B**, le module 08 (Ceph) est le pivot : le cluster Proxmox (09) et OpenStack (10) consomment `ceph-par1`. Le module 11 suppose la bordure du 07 (relais DHCP du VLAN 60) et réutilise, en pointillé, l'installateur automatique de Proxmox VE du module 09 (M11-E14) ; il peut se faire avant 08-10 en sautant cet exercice.
- Le module 12 ne dépend que du 04 : on peut l'aborder avant le bloc B si l'on préfère commencer par les conteneurs, à condition d'avoir le socle du module 06 en place (DNS, PKI) pour la suite.

## 2. Bloc A : ce que chaque module suppose et ce qu'il laisse en place

Le contrôle d'entrée d'un module est le **mini-projet du module précédent** : `lab/bin/check <NN-1> <dernier exercice>` doit être vert (par exemple `lab/bin/check 05 46` avant le module 06). Tous les fichiers de `~/.config/workbook/` sont sur `adm01`, dans un dossier en 700, en 600, jamais dans un dépôt.

| Module | Suppose acquis | Hôtes et objets Proxmox laissés en place | Projets GitLab | Comptes et jetons | Fichiers sous `~/.config/workbook/` |
|---|---|---|---|---|---|
| **00** Lab | Administration Linux et réseau (évaluée en E01, E02) ; `pve01` installé ; photos de `hp01` à préserver | `pve01` préparé : stockages `local-nvme`, `ssd-lab`, `hdd-bulk`, pool `lab`, bridge `vmbr1`, zone SDN `lab` et ses VNets ; `gw01` (1000, routeur nftables, NAT, NTP, WireGuard `wg0`/`wg1`) ; `adm01` (1001, 10.10.10.10) ; `dns01` (1002, 10.10.20.10, dnsmasq DNS + DHCP du VLAN 99) ; template 9000 `tpl-debian13` ; `hp01` réinstallé en `pbs01` (PAR2, 10.20.10.10, datastore `ds-lab`, stockage `pbs-par2`) | aucun (dépôt Git **local** `~/medisphere`, étiqueté `socle-v0`) | Proxmox : `wb-admin@pve` (groupe `wb-admins`), `wb-automation@pve!lab` (rôle `WBAutomation`) | `pve-api.env` (E17), `pve-root-ca.pem` (copie de l'autorité de `pve01`, E17) |
| **01** Git | M00-E50 vert ; agent SSH chargé ; `lab/lab.env` sur `adm01` | `git01` (1004, 10.10.20.12, GitLab CE 19.4) ; `runner01` (1007, 10.10.20.15, exécuteur `shell`, étiquettes `shell` et `socle`) ; CA provisoire dans `~/pki-provisoire/` ; Node.js 24 sur `adm01` et `runner01` ; sauvegarde de GitLab vers `pbs01` (secrets dans `/etc/wb-backup/` de `git01`) | `plateforme/medisphere` (ex-`~/medisphere`, ADR-0010…, RB-010 à RB-013), `plateforme/ci-templates` (`qualite.yml`, `release.yml`) ; groupe `formation` (bac à sable) | GitLab : `root` (bris de glace), `<MOI>` (admin), `claire.morel`, `karim.benali`, `sophie.laurent`, `julien.petit`, `nadia.roussel`, `lucas.martin` ; jeton `glrt-` du runner | `gitlab-checks.token` (`read_api`), `gitlab-admin.token` (`api`, courte durée ; `admin_mode` à partir de E31) |
| **02** Scripting | Forge, runner, pre-commit et semantic-release du M01 | Outils sur `adm01` et `runner01` (ShellCheck 0.11, shfmt, jq 1.8, yq mikefarah, uv, Task, bats) ; `medictl` installé depuis le registre de paquets ; timer `ms-verif-sauvegardes` sur `adm01` ; étiquettes Proxmox `socle` / `role-…` sur les VMs du socle | `plateforme/outils` (`bin/ms-*`, `lib/ms-commun.sh`, `medictl`, releases `vX.Y.Z`) ; ADR-0020 dans `plateforme/medisphere` | Proxmox : jeton en lecture seule `wb-automation@pve!lecture` | `pve-root-ca.pem` remplacé par l'ancre conforme (E08), `pve-lecture.env`, `pbs-lecture.env` (E26) |
| **03** Images | `plateforme/outils` et sa CI ; template 9000 | Packer 1.16 sur `adm01` puis `runner01` ; ancre de `pve01` dans le magasin système (`pve01-root-ca.crt`) ; templates 9001 `tpl-debian13-base`, 9002 `tpl-rocky10-base`, images dorées 9010-9029 (Debian 13) et 9030-9049 (Rocky 10), étiquette `current` sur une version par famille ; flux `vsandbox` → `adm01`/`runner01` TCP 8100-8199 et `runner01` → `pve01` 8006 (IPSet `automation`) | `plateforme/images` (build hebdomadaire planifié) ; ADR-0030, RB-030, RB-031 | Proxmox : `wb-packer@pve!packer` (rôles `WBPacker`, `WBLectureISO`) | `pve-packer.env` |
| **04** Ansible | Images dorées `current` ; outils et CI des M01-M02 | Configuration du socle **en code** (rôles `base`, `ssh_durci`, `pare_feu` pour `gw01`, `gitlab_runner`, `dnsmasq`, rôle de l'hôte `git01`) ; inventaire dynamique Proxmox ; `sem01` (2041) **détruite** en fin de module ; flux `runner01` → `adm01`/`gw01` TCP 22 | `plateforme/ansible` (collection `medisphere.socle`, Molecule, pipeline d'application protégé, détection de dérive planifiée) ; ADR-0040, RB-040, RB-041 | Proxmox : `wb-ansible@pve!ansible` (rôles `WBAnsible`, `WBAnsibleCluster`) ; clé SSH `ansible-ci` du pipeline | `pve-ansible.env`, `ansible-vault.pass` (identité `lab`), `ansible-vault-critique.pass` (identité `critique`) ; `semaphore-checks.token` (inutile après la destruction de `sem01`) |
| **05** OpenTofu | Rôles Ansible et inventaire dynamique du M04 ; image dorée `current` | `s3-01` (1006, 10.10.20.14, SeaweedFS, S3 HTTPS sur 8333, compartiment `tofu-state` versionné) ; OpenTofu 1.13 sur `adm01` et `runner01` ; socle (`adm01`, `dns01`, `git01`, `runner01`, `s3-01`) décrit dans l'état `socle`, `prevent_destroy` ; `gw01` hors IaC (ADR-0051) ; VMs 2050-2059 détruites | `plateforme/infra` (plan en MR, apply protégé, dérive planifiée), `plateforme/tofu-modules` (module `vm-debian`, versions `vX.Y.Z`) ; ADR-0050, ADR-0051, RB-050, RB-051 | Proxmox : `wb-tofu@pve!tofu` (rôle `WBTofu`) ; identité S3 d'OpenTofu sur `s3-01` | `pve-tofu.env`, `s3-tofu.env`, `s3-admin.env`, `tofu-chiffrement.pass` |
| **06** Services socle | Pipelines de `plateforme/infra` et `plateforme/ansible` (M05-E46 vert) | `ca01` (1003, 10.10.20.11, step-ca, ACME, CA SSH) ; `nbx01` (1005, 10.10.20.13, NetBox 4.6) ; `dns02` (1008, 10.10.20.16) ; `dns01` passé à PowerDNS (autoritaire + récurseur) et Kea DHCP en HA avec `dns02` ; **dnsmasq et CA provisoire retirés** ; racine de la PKI hors ligne dans `~/pki-racine` (chiffrée) ; NTS sur `gw01` ; certificats SSH d'hôte et d'utilisateur ; documentation étiquetée `socle-v1` | Rôles `step_ca`, `netbox`, `powerdns_auth`, `powerdns_recursor`, `kea_dhcp4`, `kea_ddns`… dans `plateforme/ansible` ; NetBox devient l'inventaire Ansible par défaut ; synchronisations dans `plateforme/outils` ; ADR-0060, RB-060 à RB-064 | NetBox : `wb-checks`, `<MOI>`, `svc-automatisation`, `svc-supervision` ; step-ca : provisioners `admin`, `acme`, `sshpop` ; Kea : `kea-api`, `supervision` | `step-admin.pass`, `netbox-checks.token`, `netbox-moi.token`, `netbox-auto.token`, `netbox-tofu.env`, `netbox-ansible.env`, `netbox-supervision.token`, `powerdns-api.env`, `kea-supervision.env` |

### État d'entrée du bloc B

À la fin du bloc A, le **socle v1** comprend neuf VMs permanentes (`gw01`, `adm01`, `dns01`, `ca01`, `git01`, `nbx01`, `s3-01`, `runner01`, `dns02`) et `pbs01` sur PAR2 ; toute nouvelle VM passe par OpenTofu (`plateforme/infra`), est configurée par Ansible (`plateforme/ansible`), reçoit son adresse de NetBox, son nom de PowerDNS et ses certificats de step-ca. Le contrôle `lab/bin/check 06 46` vérifie l'ensemble, y compris les acquis des modules 01 à 05.

### Variables de `lab/lab.env` du bloc A

`lab/lab.env.example` fait référence. Variables utilisées par les vérifications et les pannes des modules 00 à 06 : `WB_PVE_HOST`, `WB_PBS_HOST`, `WB_SSH_OPTS`, `WB_TIMEOUT`, `WB_LAN_MAISON`, `WB_PBS_LAN`, `WB_STORAGE_NVME`, `WB_STORAGE_SSD`, `WB_STORAGE_BULK`, `WB_PHOTOS_DIR`, `WB_PHOTOS_FULLCHECK` (M00) ; `WB_DEPOT`, `WB_SRC`, `WB_MOI`, `WB_GITLAB_URL`, `WB_GITLAB_TOKEN_FILE`, `WB_GITLAB_ADMIN_TOKEN_FILE` (M01) ; `WB_SEMAPHORE_URL`, `WB_SEMAPHORE_TOKEN_FILE` (M04) ; `WB_S3_ENDPOINT` (M05) ; `WB_NETBOX_URL`, `WB_NETBOX_TOKEN_FILE` (M06).

## 3. Bloc B : ce que chaque module suppose et ce qu'il laisse en place

Comme au bloc A, le contrôle d'entrée d'un module est le mini-projet du précédent : `lab/bin/check 07 46` (`socle-v2`), `08 46` (`stockage-v1`), `09 46` (`virtualisation-v1`, vert **pendant la recette** seulement : le cluster est détruit ensuite), `10 46` (`cloud-v1`), `11 25` (`provisioning-v1`). Chaque étiquette est posée sur `plateforme/medisphere`. Les fichiers sous `~/.config/workbook/` sont sur `adm01`, en 600.

| Module | Suppose acquis | Hôtes et objets Proxmox laissés en place | Projets GitLab | Comptes et jetons | Fichiers sous `~/.config/workbook/` |
|---|---|---|---|---|---|
| **07** Réseau / HA | `socle-v1` (M06-E46 vert) ; deux adresses libres du LAN maison réservées (`<IP-GW02-WAN>`, `<IP-GW-WAN-VIP>`) | **Socle v2** (étiquette `socle-v2`) : `gw02` (1009, `.3` sur chaque VLAN routé), `lb01`/`lb02` (1010/1011, 10.10.70.10/.11, VIP 10.10.70.200, HAProxy 3.2, GitLab et NetBox publiés, 443 redirigé depuis la VIP WAN) ; `gw01` passé en `.2` ; VRRP v3 unicast (VIP `.1` par VLAN routé, VRID = VLAN, VIP WAN VRID 250, `nopreempt`), `conntrackd` (FTFW, VLAN 10), tunnels `wg0`/`wg1`/`wg2` sur le maître (Lyon en attente) ; FRR 10.7 AS 65000 sur la bordure ; `vmbr1` et VLAN 30/31/51 en **MTU 9000** ; maquette 2070-2079 **détruite** (état `m07-maquette` vide) ; VNets `vfab1-8` gardées ou retirées (choix noté) | Aucun nouveau : rôles `keepalived`, `haproxy`, `frr`, `conntrackd`, `wireguard` dans `plateforme/ansible`, matrice commune `group_vars/role_routeur/pare_feu.yml` ; `gw02`, `lb01`, `lb02` dans l'état `socle` ; `ms-verif-reseau`, `ms-verif-services`, `ms-matrice-flux` dans `plateforme/outils` ; ADR-0070, RB-070 à RB-072 | Compte SSH `supervision` sur les passerelles et les répartiteurs (commande forcée) ; mots de passe des statistiques HAProxy ; clés WireGuard des passerelles (Vault `critique`, identiques sur `gw01` et `gw02`) ; certificats ACME des répartiteurs | `ssh-supervision-reseau` (clé de supervision), `haproxy-stats.env` |
| **08** Ceph | `socle-v2` (MTU 9000 sur les VLAN 30 et 31) ; image dorée Rocky 10 `current` (M03) | `ceph-par1` **conservé, arrêtable** : `ceph01-03` (2081-2083, Rocky 10, 6 Go chacun), Tentacle **20.2.4** par cephadm (Podman), 3 MON, 2 MGR, 9 OSD chiffrés, msgr2 `secure` ; pools des consommateurs `images`, `volumes`, `vms`, `backups`, `k8s-rbd` ; CephFS (MDS actif + secours, sous-volumes des équipes) ; RGW derrière l'ingress (VIP 10.10.30.200, `rgw.par1.medisphere.internal`) ; client `cephcli01` (2085, 10.10.30.20) ; `ceph04` (2084) **détruit** ; sauvegarde vers `pbs01` `par1/ceph` | **`plateforme/ceph`** (spécifications, `allocations.yaml`, outils, pipeline de dérive) ; module `vm-noeud` (`plateforme/tofu-modules` v2.2.0) ; rôles `ceph_noeud`, `ceph_client` ; `ms-verif-ceph` ; ADR-0080, RB-080 et suivants, politique de stockage dans `docs/stockage/` | Ceph : `client.admin` (hôtes `_admin` seulement), `client.glance`, `client.cinder`, `client.cinder-backup`, `client.k8s` (trousseaux en Vault, **non distribués**), `client.sauvegarde`, identités des équipes ; compte SSH `cephadm` ; tableau de bord : `admin` et compte personnel en lecture ; comptes RGW de MédiDoc (`medidoc-racine` en Vault `critique`, `medidoc-app`, `medidoc-audit`) ; step-ca : provisioners `ceph-ingress`, `ceph-dashboard` ; PBS : `wb-backup@pbs!cephcli01` | `ceph-dashboard.pass`, `ceph-ingress/` (certificat du point d'entrée), `step-ceph-ingress.pass`, `s3-medidoc-app.env`, `s3-medidoc-audit.env` |
| **09** Cluster Proxmox | `stockage-v1` ; procédure d'arrêt de `ceph-par1` ; virtualisation imbriquée possible sur `pve01` | **Rien de permanent** : `hv-par1` (`hv01-03`, 2091-2093) recetté puis **détruit** par le code ; `corosync-qnetd` désinstallé de `pbs01`, port 5403 refermé ; sur `pve01` : ISO `proxmox-ve_9.2-1.iso` vérifiée, `proxmox-auto-install-assistant` et `xorriso` ; espace PBS `par1/hv` purgé ou conservé (décision écrite au M09-E46) | `plateforme/infra` : `envs/hv/` (ISO par nœud, Taskfile de reconstruction chronométrée), `hv-invites` ; rôles `pve_noeud`, `pve_cluster`, `pve_pare_feu`… ; `ms-verif-cluster`, `ms-capacite-cluster` ; ADR-0090, RB-090 à RB-092 et suivants dans `docs/virtualisation/` | Comptes du cluster (`wb-tofu-hv@pve!tofu`, `wb-supervision@pve!hv`, TOTP des humains) disparus avec lui, recréés par le code ; PBS : `wb-hv@pbs!hv-par1` (portée `par1/hv`) ; clé de chiffrement des sauvegardes en Vault `critique` et sur papier | `hv-root.pass`, `hv-par1-root-ca.pem`, `pve-tofu-hv.env`, `pve-hv-supervision.env` (conservés pour la reconstruction, sans objet tant que le cluster n'existe pas) |
| **10** OpenStack | `stockage-v1` (`ceph-par1` démarré, pools et identités d'OpenStack) ; OpenTofu (M05) ; VLAN 50-52 et MTU 9000 du VLAN 51 (M07) | Profil **openstack** recréable : `osctl01` (2101, 16 Go), `oscmp01-02` (2102-2103, 8 Go chacun), arrêtés ou détruits après la recette ; OpenStack 2026.1 par Kolla-Ansible 22, OVN, Octavia (fournisseur OVN), VIP 10.10.50.200/.201 (VRID 150, TLS step-ca renouvelé chaque jour) ; `ext-net` 10.10.52.0/24 ; domaine `medisphere`, projets `plateforme`, `mediagenda-dev`, `mediagenda-prod` ; `client.nova` ajoutée sur `ceph-par1` (M10-E10) ; base sauvegardée sur `pbs01` `par1/openstack` | **`plateforme/openstack`** (`globals.yml`, `passwords.yml` chiffré `critique`, `outils/deployer.sh`, étiquettes `deploye-*`, CI d'invariants) ; module `openstack-env-app` (`plateforme/tofu-modules`) ; **`mediagenda/recette-infra`** (libre-service de MédiAgenda) ; `ms-verif-openstack`, `ms-capacite-openstack` ; ADR-0100, ADR-0101, RB-100 et suivants dans `docs/cloud/` | Keystone : `admin`, `<MOI>`, `karim.benali`, `julien.petit`, groupes `equipe-plateforme`/`equipe-mediagenda`, comptes de service `svc-tofu`, `svc-supervision`, `svc-ci-<équipe>` (application credentials expirantes) ; PBS : `wb-backup@pbs!osctl01` | `openstack-tofu.env` ; hors de ce dossier : `~/.config/openstack/clouds.yaml` (clouds `medisphere-admin`, `-plateforme`, `-mediagenda-dev`) et `secure.yaml` (600) |
| **11** Bare-metal | `socle-v2` (relais DHCP sur les deux passerelles) ; Kea, NetBox, step-ca (M06) ; installateur automatique de Proxmox VE (M09, pour M11-E14) | `pxe01` (2111, 10.10.60.10 : TFTP, nginx HTTPS, iPXE 2.0 construit avec la racine MédiSphère) ; `bm01-04` (2112-2115) recréées vides (`planned`) ou détruites selon `usine.md` ; Kea : sous-réseau `id: 60` et classes PXE, relais du VLAN 60 ; `maas01` (2116) et `m11-build` (2117) **détruites** (sauf ADR-0110 qui garde MAAS) ; template 9050 `tpl-ubuntu2404` gardé ou supprimé (justifié) ; `hp01` inventorié dans NetBox (série, BIOS, iLO), **jamais réinstallé** | **`plateforme/provisioning`** (gabarits, rendu depuis NetBox, validation `ksvalidator`, déploiement vers `pxe01`, job `provisionner`, inventaire planifié) ; rôles `pxe`, `pve_reponses` ; ADR-0110, ADR-0111, RB-110, RB-111 dans `docs/provisioning/` | Proxmox : `wb-provision@pve!provision` (rôle `WBProvision`, VMs 2112-2115) ; `wb-maas@pve` et `WBMaas` **supprimés** ; iLO : `wb-redfish` (droits minimaux, IPMI sur IP coupé) ; NetBox : droits de `svc-automatisation` étendus (équipements) | `pve-provision.env`, `ilo-hp01.env`, `ilo-hp01.pem` ; `maas-api.key` et `pve-maas.env` **supprimés** avec MAAS |

### Profils mémoire du bloc B

Règle : socle + **un seul** profil lourd. Le socle v2 compte ≈ 27 Go (socle v1 + `gw02`, `lb01`, `lb02`, 1 Go chacun).

| Module | Profil | En plus du socle | Total approx. |
|---|---|---|---|
| 07 | socle + maquette | 2070-2079 (≈ 10 Go toutes allumées) | ≈ 37 Go |
| 08 | infra (Ceph) | `ceph01-03` 18 Go, `cephcli01` 2 Go, `ceph04` 6 Go de E18 au mini-projet | ≈ 47 à 55 Go |
| 09 | infra (cluster) | `hv01-03` 36 Go ; `ceph01-03` arrêtées (sauf M09-E12) | ≈ 63 Go |
| 10 | openstack | `osctl01` 16 Go, `oscmp01-02` 16 Go, `ceph01-03` 18 Go | ≈ 77 Go |
| 11 | socle + provisioning | `pxe01`, `bm01-04`, `maas01` (≈ 16 Go) | ≈ 43 Go |

### État d'entrée du bloc C

À la fin du bloc B, le socle v2 (douze VMs permanentes : `gw01`, `gw02`, `adm01`, `dns01`, `dns02`, `ca01`, `git01`, `nbx01`, `s3-01`, `runner01`, `lb01`, `lb02`) tourne seul avec `pbs01` ; `ceph-par1` est conservé et arrêtable (Kubernetes le consomme au module 16, avec l'identité `client.k8s` et le pool `k8s-rbd` déjà prêts) ; les profils lourds **infra** (`hv-par1`) et **openstack** sont détruits ou arrêtés et se recréent par le code (états `hv` et `openstack`, Taskfile de reconstruction, `outils/deployer.sh`) ; la chaîne de provisioning (`pxe01`) peut installer les futurs nœuds. La bordure est prête pour le BGP de Kubernetes (plage d'écoute 10.10.40.0/24, préfixe 10.10.41.0/24 accepté, AS 65040 au module 15). Les modules du bloc C ne supposent du bloc B que la bordure (`socle-v2`) et, pour le 16, `ceph-par1`.

### Variables de `lab/lab.env` du bloc B

`lab/lab.env.example` fait référence. Variables ajoutées par les modules 07 à 11 : `WB_GW01_WAN`, `WB_GW02_WAN`, `WB_GW_WAN_VIP` (M07) ; `WB_CEPH_ADMIN`, `WB_CEPH_CLIENT` (M08, aussi lues par M09-E12 et M10) ; aucune au M09 ; `WB_OS_CLOUD`, `WB_OS_CLOUD_PLATEFORME`, `WB_OS_CLOUD_DEV` (M10) ; `WB_ILO_ENV_FILE`, `WB_MAAS_URL`, `WB_MAAS_KEY_FILE`, `WB_M11_MAAS_CONSERVE` (M11).
