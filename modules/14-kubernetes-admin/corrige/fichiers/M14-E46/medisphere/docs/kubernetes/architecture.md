# Kubernetes MédiSphère v1 — architecture de `k8s-par1`

> Modèle de M14-E46 (PLAT-1546). Remplace les valeurs entre chevrons par les tiennes ; garde la
> structure. État livré sous l'étiquette `k8s-v1` de `plateforme/medisphere`.

## 1. Vue d'ensemble

| Élément | Valeur |
|---|---|
| Distribution | kubeadm, Kubernetes **1.36.x** (installé en 1.35, monté en M14-E25), configuration v1beta4 dans `plateforme/k8s/cluster/kubeadm-config.yaml` |
| Nœuds de contrôle | `k8s-cp01-03` (VM 2141-2143, 10.10.40.51-53, 2 vCPU, 4 Go) : kube-apiserver, kube-controller-manager, kube-scheduler, etcd empilé, keepalived, HAProxy |
| Travailleurs | `k8s-w01-03` (VM 2144-2146, 10.10.40.61-63, 4 vCPU, 8 Go) ; `k8s-w03` dédié aux bases (`dedie=bdd:NoSchedule`) ; zones `par1-baie-a/b/c` |
| Point d'accès de l'API | `https://k8s-api.par1.medisphere.internal:8443`, VIP 10.10.40.200 (keepalived VRID 140), HAProxy 8443 → kube-apiserver 6443 |
| Runtime | containerd.io 2.3 (dépôt Docker), runc 1.5, cgroup v2, pilote systemd ; images par le cache Harbor (`hosts.toml`) |
| Réseau | Cilium 1.20 (IPAM `cluster-pool` 10.240.0.0/16), kube-proxy en mode `iptables` (retiré au module 15), Services 10.96.0.0/16, CoreDNS (transfert vers `dns01`/`dns02`) |
| Composants | metrics-server, Hubble relay |
| Code | `plateforme/k8s` (cluster, composants, espaces, rbac, admission, outils, Taskfile), `plateforme/ansible` (rôles `containerd`, `k8s_noeud`, `k8s_plan_controle`, `k8s_travailleur`, `etcd_instantane`), `plateforme/infra` (état OpenTofu `k8s`) |

## 2. Flux

| Source | Destination | Port | Usage |
|---|---|---|---|
| MGMT (`adm01`, CI) | VIP 10.10.40.200 | 8443 | API |
| VLAN 40 | `reg01` | 443 | images (Harbor, caches) |
| VLAN 40 (nœuds de contrôle) | `s3-01` | 8333 | instantanés etcd |
| VLAN 40 | `ca01` | 443 | ACME, CRL |
| VLAN 40 | `dns01`, `dns02` | 53 | résolution |
| VLAN 40 | Internet | 80/443 | paquets (pkgs.k8s.io, Debian, Docker) |
| `pbs01` ↔ `pve01` | — | — | sauvegarde des VMs (`par1/k8s`) |

Détail : `docs/socle/matrice-flux.md` et `group_vars/role_routeur/pare_feu.yml`.

## 3. Identités et cloisonnement

- Humains : certificats clients de 7 jours (`outils/kubeconfig-personnel.sh`), groupes `medisphere:plateforme-admins`, `medisphere:mediagenda-devs`, `medisphere:lecture` ; OIDC au module 24.
- Bris de glace : `admin.conf`, `super-admin.conf` en Vault `critique` (RB-148).
- Charges de travail : comptes de service, jetons liés ; exception documentée : jeton longue durée de `wb-checks` (lecture, sans les Secrets).
- Espaces d'équipe `mediagenda-dev`, `mediagenda-recette` : quotas, LimitRange, Pod Security `restricted`, politiques d'admission (registre Harbor, pas de `latest`).
- Audit (`/etc/kubernetes/audit/politique.yaml`, Secrets en `Metadata`) ; Secrets chiffrés au repos (`aescbc`, `kms` v2 avec OpenBao au module 25).

## 4. Ce qui se passe quand…

| Panne | Effet | Retour |
|---|---|---|
| un nœud de contrôle tombe | VIP basculée en quelques secondes (<MESURE>) ; etcd sur 2 membres ; contrôleurs réélus | automatique au retour ; remplacement : RB-144 |
| deux nœuds de contrôle tombent | plus de quorum etcd : API arrêtée, pods en place continuent | RB-141 (restauration) |
| un travailleur tombe | `NotReady` après 40 s, pods recréés ailleurs après 5 min (sauf StatefulSets) | RB-140 ; reconstruction par le code en <MESURE> |
| HAProxy ou keepalived défaillant sans se déclarer | API injoignable malgré la HA | RB-146 |
| un membre etcd perd ses données | redondance nulle jusqu'au remplacement | RB-147 |
| CoreDNS tombe | plus de résolution dans les pods | RB-149 |
| Harbor tombe | plus aucun nouveau pod ne tire son image (pods en place non touchés) | RB-13x (M13) |

## 5. Sauvegarde et restauration

- etcd : instantané horaire par `etcd-instantane.timer` sur les trois nœuds de contrôle, chiffré, vers `s3-01` (`etcd-k8s-par1/horaire/`, `quotidien/`) ; dernier test de restauration : <DATE>, RTO <MESURE>, RPO 1 h (`docs/kubernetes/tests/restauration-etcd.md`).
- VMs : PBS, espace `par1/k8s`, quotidien.
- Ce qui n'est pas sauvegardé par etcd : données des applications (stockage jetable au module 14, ceph-csi et Velero au module 16).

## 6. Ce qui n'est pas redondant

| Élément | Risque | Traité par |
|---|---|---|
| un seul hyperviseur physique (`pve01`) | perte de tout le cluster | PRA (F5), site PAR2 |
| PostgreSQL et Valkey de MédiAgenda en `emptyDir` | données perdues à chaque redémarrage | module 16 (ceph-csi), module 27 (CloudNativePG) |
| un seul registre (`reg01`) | plus de nouveaux pods | réplication Harbor (M13), à décider |
| CA du cluster (10 ans) dans les fichiers des nœuds de contrôle | compromission = reconstruire la confiance | RB-143, M26 |
| kube-proxy et iptables | performances, pas de politique réseau | module 15 |
| aucune alerte automatique | pannes vues par les utilisateurs | module 21 |

## 7. Feuille de route

- Module 15 : Cilium sans kube-proxy, LB IPAM, BGP (AS 65040), Gateway API, NetworkPolicy, CoreDNS vers `dns01`/`dns02`.
- Module 16 : ceph-csi, StorageClasses, Velero, PostgreSQL persistant.
- Module 17 : chart MédiAgenda, Kustomize, Helmfile pour les composants de plateforme.
- Modules 19-20 : CI sur Kubernetes, Argo CD (plus de `task appliquer` à la main).
- Module 21 : alertes issues des pannes du palier 4 (nœuds, etcd, API, DNS, pods).
