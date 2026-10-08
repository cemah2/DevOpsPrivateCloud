# Inventaire des nœuds OpenStack (PAR1)

> Source : état OpenTofu `envs/openstack` de `plateforme/infra` (VMs, NetBox, DNS), rôle Ansible `noeud_openstack` de `plateforme/ansible` (réseau dans l'invité), inventaire Kolla de `plateforme/openstack` (rôles des services). Ce document **décrit** ; en cas de désaccord, le code fait foi. Mis à jour par M10-E02 (PLAT-1102).

## VMs

| Nœud | VMID | vCPU | Mémoire | Disque | CPU | Étiquettes | Groupes Kolla |
|---|---|---|---|---|---|---|---|
| `osctl01` | 2101 | 4 | 16 Go | 80 Go (`local-nvme`) | `x86-64-v2-AES` | `env-m10`, `role-openstack` | `control`, `network`, `monitoring`, `storage` |
| `oscmp01` | 2102 | 4 | 8 Go | 40 Go (`local-nvme`) | `host` (KVM imbriqué) | `env-m10`, `role-openstack` | `compute` |
| `oscmp02` | 2103 | 4 | 8 Go | 40 Go (`local-nvme`) | `host` (KVM imbriqué) | `env-m10`, `role-openstack` | `compute` |

Ordre de démarrage Proxmox : `osctl01` (20) avant les calculs (21). Pool `lab`.

## Cartes

Règle unique (OpenTofu et Ansible) : suffixe = dernier octet de l'adresse OS-API ; MAC `bc:24:11:<VLAN>:00:<suffixe>`.

| Nœud | Interface | Carte Proxmox | VNet (VLAN) | MAC | MTU | Adresse | Rôle Kolla |
|---|---|---|---|---|---|---|---|
| `osctl01` | `ens18` | `net0` | `vosapi` (50) | `bc:24:11:50:00:51` | 1500 | 10.10.50.51/24, passerelle 10.10.50.1 | `network_interface` |
| `osctl01` | `ens19` | `net1` | `vostun` (51) | `bc:24:11:51:00:51` | 9000 | 10.10.51.51/24 | `tunnel_interface` |
| `osctl01` | `ens20` | `net2` | `vstopub` (30) | `bc:24:11:30:00:51` | 9000 | 10.10.30.61/24 | `storage_interface` |
| `osctl01` | `ens21` | `net3` | `vosext` (52) | `bc:24:11:52:00:51` | 1500 | **aucune** | `neutron_external_interface` (`physnet1`, `br-ex`) |
| `oscmp01` | `ens18` / `ens19` / `ens20` | `net0`-`net2` | 50 / 51 / 30 | `bc:24:11:{50,51,30}:00:52` | 1500 / 9000 / 9000 | 10.10.50.52, 10.10.51.52, 10.10.30.62 | idem |
| `oscmp02` | `ens18` / `ens19` / `ens20` | `net0`-`net2` | 50 / 51 / 30 | `bc:24:11:{50,51,30}:00:53` | 1500 / 9000 / 9000 | 10.10.50.53, 10.10.51.53, 10.10.30.63 | idem |

Pare-feu de Proxmox désactivé sur toutes les cartes (`ens21` porte les MAC des routeurs virtuels d'OVN : un filtrage MAC la rendrait muette).

## Noms

| Nom | Adresse | PTR |
|---|---|---|
| `osctl01.par1.medisphere.internal` | 10.10.50.51 | oui |
| `oscmp01.par1.medisphere.internal` | 10.10.50.52 | oui |
| `oscmp02.par1.medisphere.internal` | 10.10.50.53 | oui |
| `openstack-int.par1.medisphere.internal` | 10.10.50.200 (VIP interne, keepalived VRID 150) | non (nom de service) |
| `openstack.par1.medisphere.internal` | 10.10.50.201 (VIP externe, HTTPS) | non (nom de service) |

Les deux VIP sont réservées dans NetBox (rôle `vip`).

## Flux

Aucun flux nouveau pour la préparation des nœuds : SSH depuis `adm01` (MGMT joint tout le lab), DNS, NTP et sortie vers Internet existent ; le VLAN 51 (Geneve) n'est pas routé ; le VLAN 30 relie directement les nœuds à Ceph sans traverser la bordure. Les flux du déploiement (ACME) sont ajoutés en M10-E04.

## Accès de secours

Console série : `qm terminal 2101|2102|2103` sur `pve01` (sortie `Ctrl+O`) ; agent QEMU : `qm guest cmd <VMID> ping`.
