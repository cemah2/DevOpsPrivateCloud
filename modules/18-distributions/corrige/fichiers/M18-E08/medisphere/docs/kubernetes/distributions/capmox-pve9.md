# Cluster API sur Proxmox VE 9 — vérification préalable (CAPMOX v0.9.1)

> M18-E08 (PLAT-1908). Outils : `capi/pve-compte-capi.sh` (sur `pve01`), `capi/preflight-pve.sh`
> (sur `m18-dev01`). Décide si E10 se fait avec CAPMOX ou avec le repli CAPD.

## Ce que dit l'amont (relevé le 2026-10-15)

| Point | Source | Constat |
|---|---|---|
| Versions de Cluster API | README de CAPMOX v0.9.1 | CAPI v1.11 et v1.12 seulement (contrat v1beta2) → **CAPI 1.12.11** |
| Kubernetes des clusters | matrice de CAPI (release-1.13) | 1.36 accepté par CAPI ≥ 1.12.8 |
| Proxmox VE 9 | README, `docs/` de CAPMOX | **non mentionné** (ni supporté, ni exclu) |
| Bibliothèque d'API | `go.mod` de CAPMOX | `luthermonson/go-proxmox` v0.8.1 |
| Droits minimaux | `docs/advanced-setups.md` | rôles intégrés sur pools et stockages dédiés ; `Sys.Audit` sur `/` et `/nodes` |
| TLS | idem | **vérification désactivée par défaut** (`PROXMOX_INSECURE=true` pour le client global ; pour un `credentialsRef`, clé `insecure` absente = vérification désactivée) |
| ISO cloud-init | code (`internal/inject`, go-proxmox) | une ISO `user-data-<vmid>.iso` téléversée dans le **premier stockage de contenu `iso` visible** par le jeton, montée en `ide0` |
| Vérifications après démarrage | code | agent QEMU attendu, puis `cloud-init status` exécuté **par l'agent** (exec) |

Conséquences pour PVE 9 : `VM.Monitor` n'existe plus (remplacé par `VM.GuestAgent.*` et
`Sys.Audit`) ; l'exécution d'une commande par l'agent exige `VM.GuestAgent.Unrestricted`.

## Ce qui a été créé

- Compte `wb-capi@pve`, jeton `wb-capi@pve!capi` (séparation des privilèges, expiration 90 jours),
  secret dans `~/.config/workbook/pve-capi.env` (600) sur `adm01` et `m18-dev01`.
- Rôles `WBCapi` (pool `lab`) et `WBCapiAudit` (`Sys.Audit` sur `/` sans propagation et `/nodes`) ;
  `PVEDatastoreUser` sur `local-nvme`, `PVEDatastoreAdmin` sur le stockage dédié **`capi-iso`**
  (`/mnt/hdd-bulk/capi-iso`, contenu `iso` seul), `PVESDNUser` sur `/sdn/zones/lab/vk8s`.
- Pare-feu : bordure (`M18_GESTION` → `PVE01` 8006, → `CAPI_ESSAI_API` 6443) ; `pve01` : IPSet
  `capi` (adresses de `m18-dev01` et `k3s01`) et règle d'entrée 8006 depuis `+capi`.

## Résultat de la vérification (à remplir)

| Étape | Attendu | Obtenu le <DATE> |
|---|---|---|
| `pveversion` | 9.x | |
| `pveum role add WBCapi …` | accepté (aucun privilège inconnu) | |
| `preflight-pve.sh` : version, ressources, nœud | OK, TLS vérifié | |
| `preflight-pve.sh` : stockages `iso` visibles | **`capi-iso` seul** | |
| `preflight-pve.sh` : ISO téléversée, montée en `ide0`, démontée, supprimée | OK | |
| `preflight-pve.sh` : clone 5189, configuration, suppression | OK | |
| `preflight-pve.sh` : démarrage, `agent/ping`, `agent/exec` de `cloud-init status` | OK (aucun 403) | privilèges `VM.GuestAgent.*` de PVE 9 |
| `clusterctl init` (E08) | 5 fournisseurs `Ready` | |
| Première machine de `capi-essai` (E10) | `Running`, agent et `cloud-init status` lus | |

## Décision

- **Tout vert** → E10 avec CAPMOX.
- **Échec d'API** (privilège inconnu non remplaçable, appel refusé par PVE 9 que le changement de
  droits ne corrige pas, erreur de go-proxmox sur une réponse de PVE 9) → **repli CAPD** : cluster
  de gestion `kind/gestion-capd.yaml`, `capi/init.sh <kubeconfig> docker`, cluster `capi-essai`
  en conteneurs sur `m18-dev01` (mêmes objets Cluster, KubeadmControlPlane, MachineDeployment ;
  `DockerCluster`/`DockerMachineTemplate` à la place des objets Proxmox). Le ticket amont est ouvert
  et référencé ici ; l'ADR-0180 en tient compte.
