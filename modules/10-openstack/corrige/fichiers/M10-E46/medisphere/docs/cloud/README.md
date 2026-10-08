# Cloud MédiSphère v1 — vue d'ensemble pour l'exploitation

> Propriétaire : équipe Plateforme. Livré par PLAT-1190 (M10-E46), étiquette `cloud-v1` de `plateforme/medisphere`. Pour les utilisateurs : [`guide-utilisateur.md`](guide-utilisateur.md).

## 1. Architecture

```
                 MGMT / VPN d'admin / runner01
                              │  (bordure gw01/gw02 : matrice des flux, SEC-1153)
            VLAN 50 OS-API    ▼
  ┌──────────────── osctl01 (2101) ─────────────────┐      ┌── oscmp01 (2102) ──┐ ┌── oscmp02 (2103) ──┐
  │ keepalived VRID 150 : VIP .200 (int) .201 (ext) │      │ nova_compute       │ │ nova_compute       │
  │ HAProxy (TLS int+ext, certificats ACME step-ca) │      │ nova_libvirt (KVM) │ │ nova_libvirt (KVM) │
  │ API : Keystone Nova Neutron Glance Cinder        │      │ ovn_controller     │ │ ovn_controller     │
  │       Placement Heat Octavia Horizon             │      │ agent métadonnées  │ │ agent métadonnées  │
  │ MariaDB+ProxySQL, RabbitMQ, OVN NB/SB, memcached │      └──────┬─────────────┘ └──────┬─────────────┘
  │ cinder-volume, cinder-backup                     │             │ VLAN 51 OS-TUN (Geneve, MTU 9000)
  │ passerelle OVN (br-ex sur ens21 = VLAN 52)       │─────────────┴──────────────────────┘
  └───────┬──────────────────────────────────────────┘
          │ VLAN 30 STOR-PUB (MTU 9000)                VLAN 52 OS-EXT : ext-net 10.10.52.0/24,
          ▼                                             IP flottantes .200-.249, passerelle .1 (VIP bordure)
  ceph-par1 (ceph01-03) : pools images, volumes, vms, backups
```

Déploiement : Kolla-Ansible 22.x (OpenStack 2026.1), images `2026.1-debian-trixie`, Docker ; configuration dans `plateforme/openstack` ; hôte de déploiement `adm01` (`~/src/openstack`, projet `uv`, ansible-core < 2.21).

## 2. Décisions

| Sujet | Décision | Référence |
|---|---|---|
| Outil de déploiement | Kolla-Ansible | ADR-0101 |
| Réseau, répartiteurs | ML2/OVN ; Octavia fournisseur OVN seulement | ADR-0100 |
| Déploiement depuis le dépôt | CI = validation (`controles-kolla`, invariants) ; déploiement par `outils/deployer.sh` depuis `adm01`, seulement sur le commit de `origin/main` au pipeline vert, tracé par une étiquette `deploye-*`. Pas de déploiement par le runner partagé : il porterait l'accès root à tous les nœuds et l'identité Vault `critique` pour tous les projets | ce document |
| Stockage | Ceph `ceph-par1` (images raw, volumes, disques éphémères, sauvegardes Cinder) | M10-E10 |
| TLS | VIP externe et interne, certificats ACME de `ca01` renouvelés par Kolla (15 jours) | `securite.md` |
| Libre-service | module OpenTofu `openstack-env-app`, dépôts des équipes, application credentials `member` | `libre-service.md` |

## 3. Exploitation

| Besoin | Où |
|---|---|
| Accueillir une équipe | RB-100 |
| Mettre à jour (au sein de 2026.1) | RB-101 |
| Maintenance ou panne d'un calcul | RB-102 |
| Pannes courantes (palier 4) | RB-103 et suivants |
| Sauvegarde et restauration de la base | `sauvegarde-restauration.md`, `tests/restauration.md` |
| Supervision | `ms-verif-openstack` (`adm01`, 15 min, `ms-alerte@`) ; guide `docs/astreinte.md` de `plateforme/outils` |
| Capacité | `ms-capacite-openstack`, rapports `capacite/` |
| Sécurité | `securite.md` (risques acceptés, secrets à procédure manuelle) |

## 4. Points uniques de défaillance et limites connues

| Élément | Effet de sa perte | Traitement prévu |
|---|---|---|
| `osctl01` (contrôle + réseau) | API, Horizon, créations ; IP flottantes et SNAT (passerelle) ; instances et trafic est-ouest **continuent** | trois contrôleurs (plan chiffré dans `haute-disponibilite.md`) ; ou IP flottantes distribuées |
| `ceph-par1` | disques de toutes les instances | M08 (réplication 3) ; copie hors site à concevoir (F5) |
| `pve01` | tout le lab | hors périmètre du cloud (PAR2, F5) |
| Bordure `gw01`/`gw02` | accès aux API et aux IP flottantes depuis MGMT | redondante (M07) |
| `ca01` | plus de renouvellement des certificats des VIP (marge de 15 jours) | M06 ; alerte à 10 jours |
| Cinder Backup sur le même cluster | protège des erreurs, pas de la perte de Ceph | sauvegardes vers S3 de `s3-01` ou PAR2 (F5) |

## 5. Ce que les modules suivants consomment

- **M11** (provisioning) : rien directement ; Ironic non déployé (fiche).
- **M14-M18** (Kubernetes) : clusters possibles sur des instances OpenStack (Cluster API OpenStack, M18) ; le profil `k8s` du lab reste sur Proxmox.
- **M21-M22** (observabilité) : sonde `ms-verif-openstack` à remplacer par `openstack-exporter` et les exportateurs de Kolla ; journaux `/var/log/kolla/` (fluentd présent) vers Loki.
- **M24** (identité) : fédération Keystone ↔ Keycloak (OIDC) pour supprimer les mots de passe locaux.
- **F4** (changements majeurs) : montée de série 2026.1 → 2026.2 (RB-101 §7).
