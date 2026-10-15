# Cluster API — cluster de gestion et cluster `capi-essai`

> M18-E08 à E12 (PLAT-1908 à PLAT-1912). Code : `capi/` de `plateforme/distributions`
> (`versions.env`, `init.sh`, `identifiants.sh`, `capi-essai/`, `cilium/`), template 9060
> (`plateforme/images`, `capi/`), compte Proxmox `wb-capi@pve!capi` (`capi/pve-compte-capi.sh`).

## Versions

CAPI / clusterctl v1.12.11 (CAPMOX 0.9 n'accepte que 1.11-1.12), CAPMOX v0.9.1, IPAM in-cluster
v1.1.1 ; cert-manager installé par `clusterctl init` (version choisie par clusterctl 1.12.11).

## Cluster de gestion

| Période | Où | Kubeconfig (`adm01`, 600) |
|---|---|---|
| E08-E11 | kind `gestion` sur `m18-dev01` (API `https://m18-dev01.par1.medisphere.internal:6443`) | `~/.config/workbook/m18/kind-gestion.kubeconfig` |
| depuis E12 | `k3s01` (SQLite) | `~/.config/workbook/m18/k3s01.kubeconfig` |

Fournisseurs : `capi-system`, `capi-kubeadm-bootstrap-system`, `capi-kubeadm-control-plane-system`,
`capmox-system` (sans identifiants globaux : `capmox-manager-credentials` vide), `capi-ipam-in-cluster-system`,
`cert-manager`.

## `capi-essai`

| Élément | Valeur |
|---|---|
| Espace (gestion) | `capi-essai` |
| Kubernetes | v1.36.4 (template 9060) |
| Plan de contrôle | 1 machine (`KubeadmControlPlane capi-essai-plan-controle`) ; VIP 10.10.40.210 (kube-vip 1.2.4) |
| Travailleurs | 2 (`MachineDeployment capi-essai-travailleurs`) |
| VMs | 5180-5189 (`vmIDRange`), pool `lab`, étiquettes `env-m18`, `capi-essai`, VNet `vk8s` |
| Adresses | 10.10.40.150-169, réservoir `capi-essai-v4-icip` créé par CAPMOX |
| CNI | Cilium 1.20.2 par ClusterResourceSet `cilium` (`ApplyOnce`) |
| Identifiants | Secret `capi-essai-proxmox` (`insecure: "false"`, `root_ca` = ancre de `pve01`) |
| Accès | `~/.config/workbook/m18/capi-essai.kubeconfig` (600, `clusterctl get kubeconfig`) |

## Gestes

- état : `clusterctl describe cluster capi-essai -n capi-essai --kubeconfig <gestion>` ;
- machines : `kubectl -n capi-essai get machines,proxmoxmachines -o wide` ;
- **jamais** d'action à la main sur les VMs 5180-5189 dans Proxmox ;
- supprimer : `kubectl -n capi-essai delete cluster capi-essai` (détruit les VMs ; jamais
  `kubectl delete -f capi-essai/`, qui supprime les objets dans le désordre et peut laisser des VMs).

## Pivot (E12) et protection du cluster de gestion

1. `k3s01` prêt : ancre de `pve01` (playbook `m18.yml`), flux bordure et IPSet `capi` (déjà en E08) ;
2. `capi/init.sh ~/.config/workbook/m18/k3s01.kubeconfig proxmox` (**mêmes versions** que la source) ;
3. copie de sécurité : `clusterctl move -n capi-essai --to-directory` dans un dossier 700, supprimée
   après la vérification (elle contient les Secrets en clair) ;
4. `clusterctl move -n capi-essai --dry-run`, puis sans `--dry-run` ;
5. vérification depuis `k3s01` (cluster `Available`, mêmes machines, mise à l'échelle 2 → 3 → 2) ;
6. `kind delete cluster --name gestion`, suppression de `kind-gestion.kubeconfig`.

Le cluster de gestion porte la description de tous les clusters et les identifiants Proxmox :
sauvegarde du dossier `server/` de `k3s01` (palier 3), et export régulier
(`clusterctl move --to-directory`, chiffré) ; perte de `k3s01` = plus de réparation ni de montée de
version de `capi-essai`, mais **pas** de perte de `capi-essai`, qui continue de tourner.
