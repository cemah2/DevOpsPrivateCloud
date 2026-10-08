# Architecture du stockage — ceph-par1 (stockage MédiSphère v1)

> Propriétaire : équipe Plateforme · Livraison : `stockage-v1` (PLAT-990, M08-E46) · Code : `plateforme/ceph` (spécifications, allocations), `plateforme/ansible` (nœuds, sauvegarde, certificats), `plateforme/infra` (VMs, état `ceph`)

## 1. Vue d'ensemble

```
                       adm01 (MGMT) ── supervision ms-verif-ceph (:9283 du mgr actif), tableau de bord :8443
                          │
   VLAN 30 STOR-PUB 10.10.30.0/24, MTU 9000 ─────────────────────────────────────────────────────────────
     │ .51 ceph01            │ .52 ceph02             │ .53 ceph03            │ .20 cephcli01     VIP .200
     │ MON MGR(actif*) MDS   │ MON MGR MDS            │ MON MDS               │ client RBD/CephFS  rgw.par1…
     │ OSD×3 (2 ssd, 1 hdd)  │ OSD×3  RGW  haproxy    │ OSD×3  RGW  haproxy   │ S3, sauvegarde     (keepalived)
     │ _admin                │ keepalived  _admin     │ keepalived            │ → pbs01 (PAR2)
   VLAN 31 STOR-CLU 10.10.31.0/24, MTU 9000, non routé (réplication et battements de cœur entre OSD) ─────
       .51                     .52                      .53
   * le mgr actif peut changer ; la sonde trouve celui qui sert les métriques.
```

| Hôte | VMID | Public / cluster | Rôle |
|---|---|---|---|
| `ceph01` | 2081 | 10.10.30.51 / 10.10.31.51 | MON, MGR, MDS, 3 OSD, `_admin` (clé `client.admin`, export de configuration) |
| `ceph02` | 2082 | 10.10.30.52 / 10.10.31.52 | MON, MGR, MDS, 3 OSD, RGW, ingress, `_admin` |
| `ceph03` | 2083 | 10.10.30.53 / 10.10.31.53 | MON, MDS, 3 OSD, RGW, ingress |
| `cephcli01` | 2085 | 10.10.30.20 | client de test et de mesure, sauvegarde vers `pbs01` |

Ceph Tentacle 20.2.4 (cephadm, Podman, Rocky Linux 10), 2 vCPU et 6 Gio par nœud, `osd_memory_target` 1 Gio. Messager v2 en mode `secure` ; OSD chiffrés (LUKS). Placement exact des démons : `ceph orch ps` et `specs/` de `plateforme/ceph` (font foi sur ce schéma).

## 2. Données : pools, règles, consommateurs

| Pool | Règle (classe) | Usage | Consommateur |
|---|---|---|---|
| `rbd-test` | `ssd-baie` | essais de la Plateforme | équipe Plateforme |
| `rbd-equipes` | `ssd-baie` | volumes des équipes (espaces de noms) | MédiAgenda, MédiDoc, MédiNotif |
| `cephfs.cephfs.meta` / `.data` | `ssd-baie` | CephFS, groupes de sous-volumes par équipe | équipes |
| pools `.rgw.*` / zone par défaut | `ssd-baie` | objet S3 | MédiDoc, MédiNotif |
| `images`, `volumes`, `vms` | `ssd-baie` | Glance, Cinder, Nova | OpenStack (M10) |
| `backups` | `hdd-baie` | Cinder Backup | OpenStack (M10) |
| `k8s-rbd` | `ssd-baie` | volumes persistants | Kubernetes, Ceph-CSI (M16) |

Réplication 3, `min_size` 2, domaine de panne `rack` (une baie par nœud : `par1-baie-a` à `-c`, E14 ; règles `ssd-baie` et `hdd-baie`). Quotas et plafonds : `allocations.yaml` / `allocations.md`. Seuils : politique de stockage §4.

## 3. Ce qui se passe quand…

| Panne | Effet immédiat | Effet sur les clients | Retour | Runbook |
|---|---|---|---|---|
| un **OSD** | `OSD_DOWN`, PG `degraded` ; au bout de 10 min, `out` : ses PG se reconstruisent sur l'autre OSD de même classe **du même nœud** | aucun (latence pendant la reconstruction, réglable par mClock) | remplacement du disque | RB-080, fiche récupération |
| un **nœud** | 3 OSD, 1 MON, MGR/MDS/RGW éventuels perdus ; PG `degraded`, **aucune reconstruction possible** (plus d'hôte pour la 3e copie) | aucun si `min_size=2` respecté ; bascule MGR (secondes), MDS (secondes à 1 min), VIP RGW (keepalived) | retour du nœud : resynchronisation | RB-081 (remplacement d'un nœud) |
| **deux nœuds** | quorum perdu (1 MON sur 3), PG sous `min_size` | **tout se fige** : ni lecture ni écriture | retour d'un nœud | palier 4 (RB quorum) |
| le **MGR actif** | bascule vers le MGR en attente | aucun (E/S des clients indépendantes du MGR) ; tableau de bord et métriques interrompus quelques secondes | automatique | — |
| un **MON** | quorum à 2 sur 3 | aucun | redémarrage | — |
| l'**ingress** (haproxy/keepalived) d'un nœud | la VIP passe sur l'autre nœud | coupure S3 de quelques secondes | automatique | palier 4 (RB S3) |
| un **démon RGW** | haproxy le retire | aucun | `ceph orch daemon restart` | palier 4 |
| le **réseau de cluster** (VLAN 31) d'un nœud | ses OSD ne se voient plus : marqués `down` par les autres | latences puis comme « un nœud » | réseau | palier 4 (RB lenteur, MTU) |
| `pve01` | **tout** (un seul hyperviseur dans le lab) | arrêt total | redémarrage de `pve01` | — |

## 4. Exploitation

- Supervision : `ms-verif-ceph` (`adm01`, toutes les 5 minutes) → `ms-alerte` ; tableau de bord en lecture seule (`<MOI>`), compte `admin` de bris de glace.
- Sauvegarde : `wb-backup-ceph` (`cephcli01`, 01:30) → `pbs01` `par1/ceph` (volumes désignés, configuration) ; restauration testée (`tests/restauration-ceph.md`).
- Mises à jour : RB-082. Certificats : ACME (tableau de bord par hôte de MGR, RGW). Flux : matrice des flux (`docs/socle/matrice-flux.md`).

## 5. Ce qui n'est pas redondant (et qui le traitera)

| Point unique | Conséquence | Traitement |
|---|---|---|
| `pve01` (un hyperviseur, un SSD et un HDD physiques) | toute panne matérielle arrête le cluster ; les mesures de performance ne valent que pour le lab | cible matérielle de production (F7) ; cluster Proxmox (M09) |
| un seul site | perte de PAR1 = perte du stockage | PRA, réplication vers PAR2 (F5) |
| objet et fichier non sauvegardés hors site | une suppression S3 ou CephFS est définitive | ADR-0080, actions F5 |
| `adm01` porte la sonde | `adm01` arrêtée = plus de supervision | plateforme d'observabilité (M21) |
| `ceph01` porte l'export de configuration | indisponible = pas de sauvegarde de configuration cette nuit-là (les volumes, si) | `_admin` sur `ceph02` en secours (procédure) |

## 6. Ce que les modules suivants consomment

- **M09** (cluster Proxmox) : exercice de stockage RBD externe sur `ceph-par1` (identité dédiée à créer par `allocations.yaml`).
- **M10** (OpenStack) : pools `images`, `volumes`, `vms`, `backups`, identités `client.glance`, `client.cinder`, `client.cinder-backup` (Vault) ; type de clé choisi à la distribution.
- **M16** (Kubernetes) : pool `k8s-rbd`, identité `client.k8s` ; CephFS pour les volumes partagés si besoin (sous-volumes par l'outil d'allocation).
