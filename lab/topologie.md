# Topologie de référence du lab

> Vue d'ensemble de l'état attendu du lab **à la fin du bloc B** (module 11 ; étiquettes `socle-v2`, `stockage-v1`, `virtualisation-v1`, `cloud-v1`, `provisioning-v1` du dépôt `plateforme/medisphere`). La source de vérité des adresses, VMID et noms reste [`PLAN.md`](../PLAN.md) §4 (bloc B : §4.9) ; l'inventaire vivant est dans **NetBox** (`nbx01`).

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
       relais DHCP (VLAN 60 et 99), FRR AS 65000 (plage d'écoute K8S prête, LYO1 65030 en attente),
       tunnels wg0 (PAR2), wg1 (VPN), wg2 (LYO1, en attente) montés sur le maître seulement
                         │ ens19 trunk (MTU 9000) → vmbr1 (VLAN-aware, MTU 9000, sans port physique, zone SDN « lab »)
   chaque VLAN routé : VIP .1 (VRID = n° de VLAN), gw01 = .2, gw02 = .3
                         ├── VLAN 10 MGMT     adm01 (1001) 10.10.10.10   bastion, outillage, checks, déploiement Kolla
                         ├── VLAN 20 INFRA    dns01 (1002) .10 · ca01 (1003) .11 · git01 (1004) .12 · nbx01 (1005) .13
                         │                    s3-01 (1006) .14 · runner01 (1007) .15 · dns02 (1008) .16
                         ├── VLAN 30 STOR-PUB ceph01-03 (2081-2083) .51-.53 · cephcli01 (2085) .20 · VIP RGW .200
                         │   (MTU 9000)       osctl01, oscmp01-02 .61-.63 (accès à ceph-par1)
                         ├── VLAN 31 STOR-CLU ceph01-03 .51-.53 (réplication ; MTU 9000, non routé)
                         ├── VLAN 32 COROSYNC libre (cluster hv-par1 détruit)
                         ├── VLAN 40 K8S      vide (bloc C) ; 41 K8S-LB annoncé en BGP à la bordure (M15)
                         ├── VLAN 50 OS-API   osctl01 (2101) .51 · oscmp01-02 (2102-2103) .52-.53
                         │                    VIP interne .200 (openstack-int…), externe .201 (openstack…), VRID 150
                         ├── VLAN 51 OS-TUN   Geneve .51-.53 (MTU 9000, non routé)
                         ├── VLAN 52 OS-EXT   ext-net, IP flottantes 10.10.52.200-249 (osctl01 sans adresse, physnet1)
                         ├── VLAN 60 PROV     pxe01 (2111) .10 (TFTP, HTTPS, iPXE) · bm01-04 (2112-2115) .101-.104
                         ├── VLAN 70 DMZ      lb01 (1010) .10 · lb02 (1011) .11 · VIP .200 (VRID 170)
                         │                    HAProxy 3.2 : gitlab.par1…, netbox.par1… (443 redirigé depuis la VIP WAN)
                         └── VLAN 99 SANDBOX  VMs jetables (DHCP 10.10.99.100-199)
   Templates : 9000 tpl-debian13, 9001/9002 bases Packer, 9010-9049 images dorées (étiquette current),
               9050 tpl-ubuntu2404 (conservé ou supprimé selon M11-E25)
```

## Environnements à la fin du bloc B

Règle du PLAN §3.3 : le socle est permanent, **un seul profil lourd** tourne à la fois en plus de lui. Tout ce qui n'est pas permanent se recrée par le code.

| Environnement | VMID | État fin de bloc | Mémoire | Recréé par |
|---|---|---|---|---|
| Socle v2 (`gw01`, `gw02`, `adm01`, `dns01`, `dns02`, `ca01`, `git01`, `nbx01`, `s3-01`, `runner01`, `lb01`, `lb02`) | 1000-1011 | permanent, allumé | ≈ 27 Go | état `socle` de `plateforme/infra`, `plateforme/ansible` |
| `ceph-par1` (`ceph01-03`) et client `cephcli01` | 2081-2083, 2085 | **conservé**, arrêtable (procédure d'arrêt du M08 : `noout`…) ; consommé par OpenStack (M10) et Kubernetes (M16) | 18 Go (+ 2 Go) | état `ceph`, `plateforme/ceph` |
| Profil **openstack** (`osctl01`, `oscmp01-02`) | 2101-2103 | arrêté ou détruit après la recette `cloud-v1` | 32 Go (+ `ceph-par1`) | état `openstack`, `plateforme/openstack` (`outils/deployer.sh`), sauvegarde de la base sur PBS `par1/openstack` |
| Profil **infra** (cluster `hv-par1`, `hv01-03`) | 2091-2093 | **détruit** après la recette `virtualisation-v1` ; QDevice et `corosync-qnetd` retirés de `pbs01` | 36 Go | état `hv`, Taskfile de reconstruction (`infra/envs/hv/`), rôles `pve_*` ; espace PBS `par1/hv` selon la décision écrite au M09-E46 |
| Provisioning (`pxe01`, `bm01-04`) | 2111-2115 | `pxe01` conservé ; `bm*` recréées vides (`planned`) ou détruites selon `docs/provisioning/usine.md` ; `maas01` (2116) et `m11-build` (2117) détruites, sauf si l'ADR-0110 retient MAAS | ≈ 1 Go (+ 2 à 4 Go par `bm*`) | état `provisioning`, `plateforme/provisioning` |
| Maquette réseau du M07 | 2070-2079 | **détruite** (état `m07-maquette` vide, conservé) | — | `tofu apply` de `envs/m07-maquette/` |
| `ceph04` (essai d'extension) | 2084 | **détruit** au M08-E46 | — | — |

## Qui gère quoi (fin du bloc B)

| Couche | Outil | Où |
|---|---|---|
| Création des VMs | OpenTofu (`bpg/proxmox`), état chiffré sur `s3-01`, un état par environnement (`socle`, `m07-maquette`, `ceph`, `hv`, `openstack`, `provisioning`) | `plateforme/infra`, modules `vm-debian` et `vm-noeud` de `plateforme/tofu-modules` |
| Images | Packer | `plateforme/images` |
| Configuration | Ansible (inventaire NetBox, Vault `lab` et `critique`) | `plateforme/ansible`, appliqué par la CI |
| Bordure redondante | rôles `keepalived`, `conntrackd`, `frr`, `wireguard`, `pare_feu`, `relais_dhcp` ; une seule matrice des flux | `group_vars/role_routeur/` (`pare_feu.yml`) ; `docs/socle/matrice-flux.md` générée par `ms-matrice-flux` |
| Points d'entrée publiés | HAProxy 3.2 + keepalived, certificats ACME | `lb01`, `lb02` (rôles `haproxy`, `keepalived`) |
| Adresses, noms, actifs | NetBox (VMs, groupes FHRP, équipements `bm*`, inventaire matériel de `hp01`) | `nbx01` |
| DNS / DHCP | PowerDNS / Kea (dont le sous-réseau 60 et ses classes PXE), alimentés par le code et NetBox | `dns01`, `dns02` |
| Certificats TLS et SSH | step-ca (ACME, provisioners `ceph-ingress`, `ceph-dashboard`, certificats SSH) | `ca01` |
| Stockage distribué | cephadm (spécifications, registre des allocations, `outils/appliquer.sh`) | `plateforme/ceph` ; `ceph01-03` |
| Cluster de virtualisation | installateur automatique, rôles `pve_noeud`, `pve_cluster`, `pve_pare_feu`, Taskfile de reconstruction | `plateforme/infra` (`envs/hv/`), `plateforme/ansible` |
| Cloud IaaS | Kolla-Ansible 22 (déploiement depuis `adm01` par `outils/deployer.sh`, étiquettes `deploye-*`) ; objets par OpenTofu (provider OpenStack) et Heat | `plateforme/openstack` ; dépôts des équipes (`mediagenda/recette-infra`) |
| Provisioning | pipeline NetBox → rendu (preseed, kickstart, iPXE) → `pxe01` → alimentation par API | `plateforme/provisioning` ; `pxe01` |
| Outils d'exploitation | `medictl`, scripts `ms-*` (`ms-verif-reseau`, `ms-verif-services`, `ms-verif-ceph`, `ms-verif-cluster`, `ms-verif-openstack`, `ms-capacite-*`) | `plateforme/outils` |
| Documentation | runbooks, ADR, post-mortems, fiches de changement | `plateforme/medisphere` : `docs/socle/`, `docs/stockage/`, `docs/virtualisation/`, `docs/cloud/`, `docs/provisioning/` |
| Sauvegarde | PBS (VMs du pool `lab`, sauvegardes applicatives, Ceph, base d'OpenStack, invités du cluster) | `pbs01`, datastore `ds-lab`, espaces `par1`, `par1/ceph`, `par1/openstack`, `par1/hv` |

Pour les dépendances entre modules, voir [`annexes/prerequis.md`](../annexes/prerequis.md).
