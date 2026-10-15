# Cluster API sur OpenStack (CAPO) — essai capo-essai (M18-E16)

## Versions et emplacement du cluster de gestion

| Source (lue au tag v0.15.0) | Constat |
|---|---|
| README, matrice | 0.15 absente ; « v0.14 → CAPI ≥ v1.12 » |
| `metadata.yaml` | 0.15 → contrat `v1beta2` |
| `go.mod` | `sigs.k8s.io/cluster-api v1.14.1` |

Décision de l'essai : cluster de gestion **éphémère** kind sur `m18-dev01`, Cluster API 1.14.<N>, CAPO 0.15.<N>. `k3s01` reste en Cluster API 1.12 pour CAPMOX. Conséquence pour l'ADR-0180 : un même cluster de gestion ne peut porter CAPMOX et CAPO 0.15 qu'une fois CAPMOX compatible avec Cluster API 1.14.

## Dérogation mémoire

Profil openstack (≈ 32 Go) + `ceph-par1` (≈ 18 Go) + `m18-dev01` (8 Go) : ≈ 58 Go au-dessus du socle, au-delà de l'enveloppe du module (30 Go). Tout le reste du module était éteint, `k8s-par1` aussi. Durée de la dérogation : <N> h.

## CAPMOX et CAPO comparés

| Point | CAPMOX 0.9 (Proxmox) | CAPO 0.15 (OpenStack) |
|---|---|---|
| Réseau | VNet existant (`vk8s`), rien n'est créé | réseau, sous-réseau, routeur créés par CAPO (`managedSubnets`) ou existants |
| Adresses des nœuds | IPAM *in-cluster* (pool `capi-essai-v4-icip`), plage réservée à la main | DHCP de Neutron dans le sous-réseau du cluster |
| Point d'accès de l'API | kube-vip en pod statique, VIP choisie à la main (10.10.40.210), contournement `super-admin.conf` | IP flottante, ou répartiteur Octavia (aucun composant dans le cluster) |
| Pare-feu | pare-feu Proxmox et bordure, hors de Cluster API | groupes de sécurité gérés par CAPO |
| Images | templates Proxmox (VMID 9060-9069), sélection par `templateID` ou étiquettes | images Glance, sélection par filtre de nom ou d'étiquettes |
| Identité | jeton Proxmox `wb-capi@pve!capi`, rôle `WBCapi` limité au pool `lab` | compte de service Keystone `svc-capi`, rôle `member` du projet `plateforme` |
| Nettoyage | VMs supprimées ; rien d'autre à nettoyer | serveurs, ports, IP flottantes, groupes, réseau : tout est supprimé par CAPO si le `Cluster` est supprimé proprement |
| Maturité | 0.x, communauté IONOS, PVE 9 non documenté | sous-projet Kubernetes SIG, utilisé en production, mais 0.15 en avance sur la matrice |
| Durée de création mesurée | <N> min | <N> min |

## Flux ouverts (provisoires)

- `vsandbox` → 10.10.50.201 TCP 443 (API OpenStack) ;
- `vsandbox` → 10.10.52.200-249 TCP 6443 (API de `capo-essai`).

Retirés le <AAAA-MM-JJ> (matrice des flux mise à jour).

## Nettoyage constaté

`openstack server list`, `port list`, `floating ip list`, `security group list`, `network list`, `loadbalancer list` filtrés sur `capo-essai` : vides le <AAAA-MM-JJ>.
