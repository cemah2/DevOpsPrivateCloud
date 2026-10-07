# Topologie de référence du lab

> Vue d'ensemble de l'état attendu du lab **à la fin du bloc A** (module 06, étiquette `socle-v1`). La source de vérité des adresses, VMID et noms reste [`PLAN.md`](../PLAN.md) §4 ; à partir du module 06, l'inventaire vivant est dans **NetBox** (`nbx01`).

## Schéma

```
                    Internet
                       │
                ┌──────┴──────┐
                │ Box maison  │  <LAN-MAISON>
                └──────┬──────┘
        ┌──────────────┼───────────────────────────────┐
        │              │                               │
   hp01 = pbs01     pve01 (PAR1, Proxmox VE 9)      ton poste
   (PAR2, PBS 4)    vmbr0 ── LAN maison              wg1 10.255.1.2
   wg0 10.255.0.2      │
   10.20.10.10      gw01 (1000) nftables, NAT, chrony (NTS), relais DHCP, wg0/wg1
        ▲              │ ens19 trunk → vmbr1 (VLAN-aware, sans port physique, SDN zone « lab »)
        └── tunnel wg0 ┤
                       ├── VLAN 10 MGMT   adm01 (1001) 10.10.10.10   bastion, outillage, checks
                       ├── VLAN 20 INFRA  dns01 (1002) 10.10.20.10   PowerDNS rec+auth, Kea DHCPv4
                       │                  ca01  (1003) 10.10.20.11   step-ca (ACME, SSH)
                       │                  git01 (1004) 10.10.20.12   GitLab CE 19
                       │                  nbx01 (1005) 10.10.20.13   NetBox 4.6
                       │                  s3-01 (1006) 10.10.20.14   SeaweedFS S3 (:8333)
                       │                  runner01 (1007) 10.10.20.15 GitLab Runner (shell)
                       │                  dns02 (1008) 10.10.20.16   PowerDNS secondaire, Kea standby
                       └── VLAN 99 SANDBOX VMs jetables (DHCP 10.10.99.100-199)
   Templates : 9000 tpl-debian13, 9001/9002 bases Packer, 9010-9049 images dorées (étiquette current)
```

## Qui gère quoi (fin du bloc A)

| Couche | Outil | Où |
|---|---|---|
| Création des VMs | OpenTofu (`bpg/proxmox`), état chiffré sur `s3-01` | `plateforme/infra`, modules `plateforme/tofu-modules` |
| Images | Packer | `plateforme/images` |
| Configuration | Ansible (inventaire NetBox, Vault) | `plateforme/ansible`, appliqué par la CI |
| Pare-feu de `gw01` | rôle `pare_feu` (matrice des flux en code) | `host_vars/gw01/pare_feu.yml` |
| Adresses, noms, actifs | NetBox | `nbx01` |
| DNS / DHCP | PowerDNS / Kea, alimentés par le code et NetBox | `dns01`, `dns02` |
| Certificats TLS et SSH | step-ca (ACME, certificats SSH) | `ca01` |
| Outils d'exploitation | `medictl`, scripts `ms-*` | `plateforme/outils` |
| Documentation | runbooks, ADR, post-mortems | `plateforme/medisphere` (`docs/socle/`) |
| Sauvegarde | PBS (VMs du pool `lab` + sauvegardes applicatives) | `pbs01`, datastore `ds-lab` |

Pour les dépendances entre modules, voir [`annexes/prerequis.md`](../annexes/prerequis.md).
