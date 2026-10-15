# Image de nœud Cluster API (template 9060)

> M18-E09 (PLAT-1909). Code : `capi/` de `plateforme/images` (`ubuntu-2404-k136.json`,
> `construire.sh`) ; outil amont image-builder v0.1.55 (Packer + Ansible).

## Ce que contient le template

Ubuntu 24.04.4 (installation automatique), containerd 2.3 et runc (défauts d'image-builder
v0.1.55), crictl 1.36, kubeadm/kubelet/kubectl **1.36.4** (paquets `1.36.4-1.1` de pkgs.k8s.io),
images du plan de contrôle préchargées, cloud-init, agent QEMU ; `config_path` de containerd vers
`/etc/containerd/certs.d` (les `hosts.toml` sont déposés par les `KubeadmConfig`).

| Champ | Valeur |
|---|---|
| VMID, nom | 9060, `tpl-capi-ubuntu2404-k136` |
| Stockage | `local-nvme`, disque **brut** (stockage bloc), 20 Gio (agrandi par CAPMOX à 32 Gio) |
| Pool, étiquettes | `lab` ; `capi`, `k8s-v1.36.4` à la construction ; `current` après contrôle |

## Construire

1. ISO déposée à l'avance sur `hdd-bulk` (`download-url`, empreinte vérifiée) ;
2. sur `m18-dev01` : `NOEUD=<NOEUD> capi/construire.sh --valider`, puis sans option (≈ 30 min) ;
3. contrôle : `qm config 9060`, clone lié jetable en 5188 sur `vsandbox`, `kubeadm version`,
   `kubelet --version`, `crictl --version`, absence de clé et de mot de passe de build, suppression ;
4. `current` posée sur le seul template validé (et retirée de l'ancien).

Corrections locales du gabarit d'image-builder (affichées par le script, jamais un *fork*) :
`insecure_skip_tls_verify: false` (écrit `true` en dur en amont), `pool: lab`, `tags`.

## Cycle de vie

- **Une image par version de Kubernetes** : 9060 (1.36.4), 9061 (1.36.5, palier 3), …
  Monter `capi-essai` = nouveau template + nouveaux `ProxmoxMachineTemplate` (immuables).
- Un template reste tant qu'une machine en a été clonée **et** qu'un retour arrière peut en avoir
  besoin ; on garde N et N-1, on supprime le reste (VMID 9060-9069).
- Correctifs de l'OS : on reconstruit (même version de Kubernetes, nouveau VMID), on ne met pas à
  jour les nœuds en place.
