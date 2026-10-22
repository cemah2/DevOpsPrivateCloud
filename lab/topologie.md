# Topologie de référence du lab

> Vue d'ensemble de l'état attendu du lab **à la fin du bloc E** (module 23 ; étiquettes `socle-v2`, `stockage-v1`, `virtualisation-v1`, `cloud-v1`, `provisioning-v1`, puis `conteneurs-v1`, `registre-v1`, `k8s-v1`, `k8s-reseau-v1`, `k8s-stockage-v1`, `packaging-v1`, `distributions-v1`, puis `ci-v1`, `gitops-v1`, `metriques-v1`, `journaux-v1`, `traces-v1` du dépôt `plateforme/medisphere`). La source de vérité des adresses, VMID et noms reste [`PLAN.md`](../PLAN.md) §4 (bloc B : §4.9 ; bloc C : §4.10 ; blocs D et E : §4.11) ; l'inventaire vivant est dans **NetBox** (`nbx01`).

## Schéma

```
                         Internet
                            │
                     ┌──────┴──────┐
                     │ Box maison  │  <LAN-MAISON>
                     └──────┬──────┘
   ┌────────────────────┬───┴───────────────────────┬─────────────────────┬───────────────────┐
   │                    │                           │                     │                   │
 hp01 = pbs01       pve01 (PAR1, Proxmox VE 9)   iLO 4 de hp01         ton poste
 (PAR2, PBS 4)      vmbr0 ── LAN maison           <IP-ILO-HP01>         wg1 10.255.1.2
 10.20.10.10        route 10.10/16, 10.20/16,     Redfish en lecture    (extrémité : VIP WAN)
 wg0 10.255.0.2     10.255.1/24 via la VIP WAN    (M11), jamais
 (extrémité :            │                        réinstallé
  VIP WAN)       <IP-GW01-WAN>   VIP WAN <IP-GW-WAN-VIP> (VRID 250)   <IP-GW02-WAN>
   ▲              ┌──────┴──────┐ ◄── VRRP v3 unicast ──► ┌──────┴──────┐
   │              │ gw01 (1000) │   conntrackd (VLAN 10)   │ gw02 (1009) │
   └── tunnel wg0 ┤ priorité 150│   nopreempt, un groupe   │ priorité 100│
                  └──────┬──────┘   de synchronisation     └──────┬──────┘
       mêmes rôles sur les deux : nftables (une seule matrice), NAT vers la VIP WAN, chrony (NTS),
       relais DHCP (VLAN 60 et 99), FRR AS 65000 (voisins BGP : nœuds de k8s-par1 en AS 65040,
       préfixe 10.10.41.0/24 accepté seul), tunnels wg0 (PAR2), wg1 (VPN), wg2 (LYO1, en attente)
                         │ ens19 trunk (MTU 9000) → vmbr1 (VLAN-aware, MTU 9000, sans port physique, zone SDN « lab »)
   chaque VLAN routé : VIP .1 (VRID = n° de VLAN), gw01 = .2, gw02 = .3
                         ├── VLAN 10 MGMT     adm01 (1001) 10.10.10.10   bastion, outillage, checks, kubectl/helm/helmfile
                         ├── VLAN 20 INFRA    dns01 (1002) .10 (récurseur 53, autoritaire 5300) · ca01 (1003) .11
                         │                    git01 (1004) .12 · nbx01 (1005) .13 · s3-01 (1006) .14 · runner01 (1007) .15
                         │                    dns02 (1008) .16 · runner02 (1012) .17 (exécuteur docker)
                         │                    reg01 (1013) .18 Harbor 2.15 (CNAME registry.par1.medisphere.internal)
                         │                    mon01 (1014) .19 Mailpit (SMTP 25, CNAME smtp.par1…, HTTPS 8025),
                         │                    Prometheus et Alertmanager « témoins » (9090, 9093), blackbox (9115), pve-exporter (9221)
                         ├── VLAN 30 STOR-PUB ceph01-03 (2081-2083) .51-.53 · cephcli01 (2085) .20 · VIP RGW .200
                         │   (MTU 9000)       osctl01, oscmp01-02 .61-.63 (accès à ceph-par1)
                         │                    k8s-w01-03 : 2e carte eth1 .81-.83 (MAC bc:24:11:30:00:61-63, sans passerelle)
                         ├── VLAN 31 STOR-CLU ceph01-03 .51-.53 (réplication ; MTU 9000, non routé)
                         ├── VLAN 32 COROSYNC libre (cluster hv-par1 détruit)
                         ├── VLAN 40 K8S      k8s-par1 : k8s-cp01-03 (2141-2143) .51-.53 · k8s-w01-03 (2144-2146) .61-.63
                         │   (MTU 1500)       VIP API .200:8443 (k8s-api.par1…, keepalived VRID 140, HAProxy → :6443)
                         │                    réservé M18 (détruit) : .150-.169 VMs Cluster API, VIP .210 ; .170-.179, VIP .211
                         ├── VLAN 41 K8S-LB   pas d'interface : 10.10.41.0/24 annoncé en BGP par les nœuds (/32)
                         │                    pool lb-par1 .10-.199 : .10 gw-par1 (*.apps.par1.medisphere.internal),
                         │                    .11 gw-partenaires (TLS passthrough), .20-.49 essais, .50-.199 services durables :
                         │                    .60 prometheus.apps… :9090 (Thanos Query) · .61 alertmanager.apps… :9093
                         │                    .62 loki.apps… :3100 · .63 otlp.apps… :4317/4318 (MGMT, mon01, réseaux du lab)
                         ├── VLAN 50 OS-API   osctl01 (2101) .51 · oscmp01-02 (2102-2103) .52-.53
                         │                    VIP interne .200 (openstack-int…), externe .201 (openstack…), VRID 150
                         ├── VLAN 51 OS-TUN   Geneve .51-.53 (MTU 9000, non routé)
                         ├── VLAN 52 OS-EXT   ext-net, IP flottantes 10.10.52.200-249 (osctl01 sans adresse, physnet1)
                         ├── VLAN 60 PROV     pxe01 (2111) .10 (TFTP, HTTPS, iPXE) · bm01-04 (2112-2115) .101-.104
                         ├── VLAN 70 DMZ      lb01 (1010) .10 · lb02 (1011) .11 · VIP .200 (VRID 170)
                         │                    HAProxy 3.2 : gitlab.par1…, netbox.par1…, liste de noms *.apps → 10.10.41.10:443
                         └── VLAN 99 SANDBOX  VMs jetables (DHCP 10.10.99.100-199) ; adresses fixes des essais :
                                              .31 reg02, .51 m15-essai, .85-.87 talos-01..03,
                                              .61 lyo-k3s01 (2201), .62 flux01 (2202) (tous détruits)
   Templates : 9000 tpl-debian13, 9001/9002 bases Packer, 9010-9049 images dorées (étiquette current),
               9050 tpl-ubuntu2404 (selon M11-E25), 9060/9061 tpl-capi-ubuntu2404-k136(-2) (selon l'ADR-0180)
```

## Le cluster `k8s-par1` (bloc C)

| Élément | Valeur | Module |
|---|---|---|
| Nœuds | `k8s-cp01-03` (2141-2143, 10.10.40.51-53, 2 vCPU, 4 Go) ; `k8s-w01-03` (2144-2146, 10.10.40.61-63, 4 vCPU, 8 Go) ; MAC `bc:24:11:40:00:<51-53,61-63>` ; carte principale `eth0` | M14 |
| Versions | Kubernetes 1.36.5 (kubeadm, installé en 1.35.9), containerd.io 2.3, etcd empilé (trois membres), Cilium 1.20 | M14 |
| Point d'accès de l'API | VIP **10.10.40.200:8443** (`k8s-api.par1.medisphere.internal`), keepalived VRID 140 et HAProxy sur les trois nœuds de contrôle | M14 |
| Réseaux internes | pods 10.240.0.0/16 (un /24 par nœud, VXLAN chiffré par WireGuard), Services 10.96.0.0/16 (`kube-dns` 10.96.0.10), domaine `cluster.local` | M14, M15 |
| Entrée | Cilium sans kube-proxy ; LB IPAM `lb-par1` **10.10.41.10-199** ; BGP AS 65040 ↔ `gw01`/`gw02` (AS 65000) ; Gateway **`gw-par1`** (espace `passerelles`, **10.10.41.10**, HTTPS `*.apps.par1.medisphere.internal`) et `gw-partenaires` (10.10.41.11) ; publication hors du lab par `lb01`/`lb02` | M15 |
| Noms et certificats | zone **`apps.par1.medisphere.internal`** sur l'autoritaire de `dns01` (5300, signée, secondaire `dns02`), écrite en RFC 2136 signé TSIG par ExternalDNS (`externaldns-k8s`) et cert-manager (`certmanager-k8s`) ; ClusterIssuer `step-ca-acme` (ACME de `ca01`) | M15 |
| Stockage | travailleurs raccordés au VLAN 30 (`eth1`, 10.10.30.81-83, MTU 9000, étiquette `medisphere.internal/stockage-ceph=oui`) ; ceph-csi 3.18 vers `ceph-par1` (pool `k8s-rbd`, CephFS groupe `csi`) ; classes `ceph-rbd` (défaut), `ceph-rbd-retain`, `cephfs`, `ceph-rbd-chiffre` | M16 |
| Sauvegardes | instantanés etcd horaires → `s3-01` `etcd-k8s-par1` ; Velero → `s3-01` `velero-k8s-par1` ; CloudNativePG (`mediagenda-db`) → `s3-01` `cnpg-k8s-par1` ; VMs → PBS `par1/k8s` | M14, M16 |
| Applications | MédiAgenda (chart `mediagenda`, overlays de `mediagenda/deploiement`) dans `mediagenda-dev`, `mediagenda-recette` et `mediagenda-prod` ; MédiDoc dans `medidoc-dev` (documents sur le RGW, `medidoc-documents`) | M14 à M17 |
| Plateforme | neuf releases décrites par le Helmfile de `plateforme/k8s` (Cilium, cert-manager, ExternalDNS, ceph-csi RBD et CephFS, CloudNativePG, plugin Barman Cloud, Velero, metrics-server) | M17 |

### Ajouts des blocs D et E

Les travailleurs `k8s-w01-03` passent à **10 Go** (M19-E02) et reçoivent `vm.max_map_count = 524288`. La couche de base reste sous **Helmfile** (`plateforme/k8s`) ; tout ce qui vient après Argo CD est une Application de `plateforme/gitops`, chart tiers recopié et signé dans Harbor `charts/` par `plateforme/charts-miroir`.

| Espace | Composants | Géré par | Module |
|---|---|---|---|
| `gitlab-runner` | gestionnaire du runner `k8s-par1` (deux réplicas, PDB) et du runner `k8s-par1-protege` (chart `gitlab/gitlab-runner`) | Helmfile (`gitlab-runner`) | M19 |
| `ci-jobs`, `ci-jobs-protege` | pods des jobs (compte de service `ci-job` sans droit, quotas, LimitRange, PSA `restricted`) ; clé Cosign montée dans `ci-jobs-protege` seulement | Helmfile, `espaces/` | M19 |
| `buildkit` | `buildkitd` *rootless* partagé (Service `buildkitd.buildkit:1234`, TLS mutuel, ClusterIssuer `buildkit-ca`, cache `plateforme/cache-buildkit` dans Harbor) | Helmfile (`buildkitd`) | M19 |
| `gitlab-agent` | agent GitLab `k8s-par1` (KAS de `git01`), limité à `wb-essais` depuis M20-E30 | Helmfile (`gitlab-agent`) | M19 |
| `argocd` | Argo CD 3.5 en HA (`argocd-server` derrière `gw-par1`, `argocd.apps.par1.medisphere.internal`), notifications vers Mailpit | Helmfile (`argocd`) | M20 |
| `argo-rollouts` | Argo Rollouts 1.10, plugin Gateway API 0.17 ; Rollout `mediagenda` en recette et en prod | Argo CD | M20 |
| `supervision` | kube-prometheus-stack (Prometheus `kps` ×2 + sidecar Thanos, Alertmanager `kps`, Grafana 13.2, kube-state-metrics, opérateur), Thanos Query, Store Gateway, Compactor, Pyrra ; Services `prometheus-externe` (.60) et `alertmanager-externe` (.61) | Argo CD | M21 |
| `supervision-noeuds` | DaemonSet node-exporter | Argo CD | M21 |
| `journaux` | Loki 3.7 monolithique (Service `loki-externe` .62), Alloy 1.21 en DaemonSet | Argo CD | M22 |
| `opentelemetry-operator-system` | OpenTelemetry Operator | Argo CD | M23 |
| `traces` | Collectors `otel-agent` (DaemonSet) et `otel-passerelle` (Service `otlp-externe` .63), Tempo 3.1 (metrics-generator), Pyroscope 2.4 | Argo CD | M23 |
| retirés | `jenkins`, `sonarqube` (M19-E46), `opensearch-essai`, `journaux-essai` (M22-E25), `jaeger-essai` (M23-E25) | — | M19, M22, M23 |

Données sur le RGW de `ceph-par1` (utilisateurs RGW du même nom que le composant) : `thanos-k8s-par1` (brut 30 j, 5 min 180 j, 1 h 2 ans), `loki-k8s-par1` (`audit` 1 an, applications 30 j, plateforme 14 j), `tempo-k8s-par1` (14 j), `pyroscope-k8s-par1` ; sur `s3-01` : `ci-cache` (cache des runners, M19) et `argocd-sauvegardes` (versionné, M20-E28).

Ordre d'arrêt : `k8s-par1` (travailleurs 2146, 2145, 2144, puis nœuds de contrôle 2143, 2142, 2141), **puis** `ceph-par1` ; démarrage dans l'ordre inverse (`ceph-par1` jusqu'à `HEALTH_OK`, nœuds de contrôle, travailleurs).

## Environnements à la fin du bloc E

Règle du PLAN §3.3 : le socle est permanent, **un seul profil lourd** tourne à la fois en plus de lui. Tout ce qui n'est pas permanent se recrée par le code.

| Environnement | VMID | État fin de bloc | Mémoire | Recréé par |
|---|---|---|---|---|
| Socle v4 (`gw01`, `gw02`, `adm01`, `dns01`, `dns02`, `ca01`, `git01`, `nbx01`, `s3-01`, `runner01`, `lb01`, `lb02`, `runner02`, `reg01`, `mon01`) | 1000-1014 | permanent, allumé | ≈ 40 Go | état `socle` de `plateforme/infra`, `plateforme/ansible` ; objets de Harbor : état `registre` |
| Profil **k8s** : cluster `k8s-par1` | 2141-2146 | **conservé**, arrêtable (procédure du M14) ; consommé par les modules 19 à 29 et les finaux ; avec `ceph-par1` et le socle v4, profil de travail des blocs D et E ≈ 100 Go | 42 Go (travailleurs à 10 Go depuis M19-E02) | état `envs/k8s`, rôles `k8s_*`, `plateforme/k8s` (`task appliquer`, `helmfile apply`), instantané etcd sur `s3-01` |
| `ceph-par1` (`ceph01-03`) et client `cephcli01` | 2081-2083, 2085 | **conservé**, arrêtable (procédure du M08) ; consommé par OpenStack (M10) et par `k8s-par1` (M16 : à démarrer avant lui) | 18 Go (+ 2 Go) | état `ceph`, `plateforme/ceph` |
| Profil **openstack** (`osctl01`, `oscmp01-02`) | 2101-2103 | arrêté ou détruit après la recette `cloud-v1` | 32 Go (+ `ceph-par1`) | état `openstack`, `plateforme/openstack` (`outils/deployer.sh`), sauvegarde de la base sur PBS `par1/openstack` |
| Profil **infra** (cluster `hv-par1`, `hv01-03`) | 2091-2093 | **détruit** après la recette `virtualisation-v1` ; QDevice et `corosync-qnetd` retirés de `pbs01` | 36 Go | état `hv`, Taskfile de reconstruction (`infra/envs/hv/`), rôles `pve_*` ; espace PBS `par1/hv` selon la décision écrite au M09-E46 |
| Provisioning (`pxe01`, `bm01-04`) | 2111-2115 | `pxe01` conservé ; `bm*` recréées vides (`planned`) ou détruites selon `docs/provisioning/usine.md` ; `maas01` (2116) et `m11-build` (2117) détruites, sauf si l'ADR-0110 retient MAAS | ≈ 1 Go (+ 2 à 4 Go par `bm*`) | état `provisioning`, `plateforme/provisioning` |
| Hôtes de conteneurs du M12 (`ctr01`, `ctr02`, `ctr03`, `legacy01`) | 2121-2124 | **détruits** à la recette `conteneurs-v1` (`ctr01` au plus tard après M13-E03) | — | état `m12-conteneurs` (`envs/m12/`) |
| Harbor de test du M13 (`reg02`) | 2131 | **détruit** au M13-E25 | — | états `m13-registre` (`envs/m13/`) et `registre-reg02` |
| `k8s-w04` (ajout et remplacement de nœud) | 2147 | **détruit** au M14-E46 (variable OpenTofu `avec_k8s_w04`) | — | état `envs/k8s` |
| `m15-essai` (kubeadm mononœud, MetalLB) | 2151 | **détruit** au M15-E46 | — | état `m15-essai` |
| Disques de comparaison Rook et Longhorn (`k8s-w0N-rook`, `k8s-w0N-lh`) | sur 2144-2146 | **retirés** au M16-E46 | — | état `envs/k8s` |
| Essais de distributions du M18 (`k3s01`, `rke2-01..03`, `talos-01..03`, `m18-dev01`) | 2181-2188 | **détruits** au M18-E25 (sauf choix écrit dans l'ADR-0180) | — | état `envs/m18` (variables `groupes`, `k3s_ha_noeuds`), `plateforme/distributions` |
| Banc k3s HA du M18 (`k3s-ha01..03`) | 5191-5193 | **détruits** (clones liés jetables) | — | état `envs/m18`, inventaire statique `m18-k3s-ha.yml` |
| VMs créées par Cluster API (`capi-essai`) et VMs de contrôle | 5180-5189 (5188, 5189) | **détruites** par Cluster API avant le démontage du cluster de gestion | — | `plateforme/distributions/capi/` (cluster de gestion amorcé dans kind) |
| Templates de nœud Cluster API | 9060, 9061 | gardés ou supprimés selon l'ADR-0180 (`WB_M18_TEMPLATES_CONSERVES`) | — | `plateforme/images` (dossier `capi/`, image-builder) |
| Cluster de l'agence LYO1 (`lyo-k3s01`) et comparaison Flux (`flux01`) | 2201, 2202 | **détruits** au M20-E46 (état `envs/m20` vide, flux de bordure retirés) | — | état `envs/m20` (variable `groupes`) |
| Composants temporaires dans `k8s-par1` : Jenkins, SonarQube (M19), Fluent Bit, OpenSearch (M22), Jaeger (M23) | — | **retirés** en fin de module, jamais deux à la fois | ≈ 1 à 3 Go chacun | Applications ou releases d'essai (code conservé dans les corrigés) |
| Maquette réseau du M07 | 2070-2079 | **détruite** (état `m07-maquette` vide, conservé) | — | `tofu apply` de `envs/m07-maquette/` |
| `ceph04` (essai d'extension) | 2084 | **détruit** au M08-E46 | — | — |
| Instances Molecule | 2046, 2047 (M12), 2149 (M14) | jetables | — | scénarios Molecule des rôles |

## Qui gère quoi (fin du bloc E)

| Couche | Outil | Où |
|---|---|---|
| Création des VMs | OpenTofu (`bpg/proxmox`), état chiffré sur `s3-01`, un état par environnement (`socle`, `m07-maquette`, `ceph`, `hv`, `openstack`, `provisioning`, `m12-conteneurs`, `m13-registre`, `registre-reg02`, `k8s`, `m15-essai`, `m18`, `m20` ; dossiers et équipes de Grafana : `observabilite-grafana`) | `plateforme/infra`, modules `vm-debian` (disques de données) et `vm-noeud` (v2.4, carte DHCP) de `plateforme/tofu-modules` |
| Images | Packer ; image-builder pour les nœuds Cluster API | `plateforme/images` |
| Configuration | Ansible (inventaire NetBox, Vault `lab` et `critique`) | `plateforme/ansible`, appliqué par la CI |
| Bordure redondante | rôles `keepalived`, `conntrackd`, `frr`, `wireguard`, `pare_feu`, `relais_dhcp` ; une seule matrice des flux | `group_vars/role_routeur/` (`pare_feu.yml`) ; `docs/socle/matrice-flux.md` générée par `ms-matrice-flux` |
| Points d'entrée publiés | HAProxy 3.2 + keepalived, certificats ACME | `lb01`, `lb02` (rôles `haproxy`, `keepalived`) |
| Adresses, noms, actifs | NetBox (VMs, groupes FHRP, équipements `bm*`, inventaire matériel de `hp01`) | `nbx01` |
| DNS / DHCP | PowerDNS / Kea (dont le sous-réseau 60 et ses classes PXE), alimentés par le code et NetBox ; zone `apps.par1.medisphere.internal` écrite par le cluster (RFC 2136) | `dns01`, `dns02` |
| Certificats TLS et SSH | step-ca (ACME, provisioners `ceph-ingress`, `ceph-dashboard`, certificats SSH) ; cert-manager dans le cluster | `ca01` ; `k8s-par1` |
| Stockage distribué | cephadm (spécifications, registre des allocations, `outils/appliquer.sh`) | `plateforme/ceph` ; `ceph01-03` |
| Cluster de virtualisation | installateur automatique, rôles `pve_noeud`, `pve_cluster`, `pve_pare_feu`, Taskfile de reconstruction | `plateforme/infra` (`envs/hv/`), `plateforme/ansible` |
| Cloud IaaS | Kolla-Ansible 22 (déploiement depuis `adm01` par `outils/deployer.sh`, étiquettes `deploye-*`) ; objets par OpenTofu (provider OpenStack) et Heat | `plateforme/openstack` ; dépôts des équipes (`mediagenda/recette-infra`) |
| Provisioning | pipeline NetBox → rendu (preseed, kickstart, iPXE) → `pxe01` → alimentation par API | `plateforme/provisioning` ; `pxe01` |
| Intégration continue | GitLab CE 19.5, runners `k8s-par1` et `k8s-par1-protege` (exécuteur `kubernetes`), `runner02` pour l'étiquette `docker` ; composants CI/CD v2 (`construction-image`, `qualite`, `securite`, `promotion`, `deploiement`) ; BuildKit *rootless* partagé ; promotion des images par MR (`ci-promotion`) | `plateforme/ci-templates` (catalogue) ; `plateforme/k8s` ; projets des applications |
| Déploiement continu | Argo CD (*App of Apps*, AppProjects, ApplicationSets, `prod` synchronisée à la main, fenêtres de synchronisation) ; Argo Rollouts (canary par la Gateway API, analyses Prometheus) ; Secrets hors Git (`secrets-k8s.sh`) | `plateforme/gitops` ; `mediagenda/deploiement`, `medidoc/deploiement` ; `plateforme/charts-miroir` |
| Observabilité | Prometheus, Alertmanager, Grafana, Thanos, Pyrra (M21) ; Loki et Alloy (M22) ; OpenTelemetry, Tempo, Pyroscope (M23) ; supervision témoin et *dead man's switch* sur `mon01` ; alertes par courriel (Mailpit) | `plateforme/observabilite` (règles, tableaux, routes, SLO, valeurs) ; rôles `node_exporter`, `alloy`, `supervision_temoin`, `mailpit` |
| Registre et confiance des images | Harbor 2.15 (projets, robots, caches, politiques), Cosign 3 (clé MédiSphère, sans Rekor public), Trivy, Syft ; Renovate planifié | `reg01` ; état `registre` ; `docs/registre/` ; `plateforme/renovate` |
| Cluster Kubernetes | kubeadm (configuration v1beta4), rôles `containerd`, `k8s_noeud`, `k8s_plan_controle`, `k8s_travailleur` ; objets du cluster (`task appliquer`) | `plateforme/k8s` ; `plateforme/ansible` |
| Composants de plateforme | couche de base : Helmfile 1.8 et Helm 4 (neuf releases du M17, `gitlab-runner`, `buildkitd`, `gitlab-agent`, `argocd`) ; le reste par Argo CD | `plateforme/k8s` (`helmfile.yaml`, `releases/`) ; `plateforme/gitops` (`plateforme/`) |
| Applications sur Kubernetes | chart signé (Helm 4, OCI dans Harbor `charts`), rendu vérifié décliné par Kustomize, synchronisé par Argo CD | `mediagenda/chart`, `mediagenda/deploiement`, `medidoc/deploiement` |
| Outils d'exploitation | `medictl`, scripts `ms-*` (`ms-verif-reseau`, `ms-verif-services`, `ms-verif-ceph`, `ms-verif-cluster`, `ms-verif-openstack`, `ms-verif-conteneurs`, `ms-verif-registre`, `ms-verif-k8s-reseau`, `ms-verif-k8s-stockage`, `ms-capacite-*`) | `plateforme/outils` |
| Documentation | runbooks, ADR, post-mortems, fiches de changement | `plateforme/medisphere` : `docs/socle/`, `docs/stockage/`, `docs/virtualisation/`, `docs/cloud/`, `docs/provisioning/`, `docs/conteneurs/`, `docs/registre/`, `docs/kubernetes/`, `docs/livraison/` (`ci/`, `gitops/`), `docs/observabilite/` (`metriques/`, `journaux/`, `traces/`) |
| Sauvegarde | PBS (VMs du pool `lab`, sauvegardes applicatives, Ceph, base d'OpenStack, invités du cluster, conteneurs, Harbor, nœuds Kubernetes) ; S3 de `s3-01` pour etcd, Velero et CloudNativePG | `pbs01`, datastore `ds-lab`, espaces `par1`, `par1/ceph`, `par1/openstack`, `par1/hv`, `par1/conteneurs`, `par1/registre`, `par1/k8s` ; `s3-01` (`etcd-k8s-par1`, `velero-k8s-par1`, `cnpg-k8s-par1`), `argocd-sauvegardes` (M20-E28) ; données d'observabilité sur le RGW (`thanos-`, `loki-`, `tempo-`, `pyroscope-k8s-par1`) |

Pour les dépendances entre modules, voir [`annexes/prerequis.md`](../annexes/prerequis.md).
