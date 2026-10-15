# Distributions Kubernetes : comparatif mesuré sur le lab (M18)

> Chaque valeur renvoie à sa source. `[…]` : à remplacer par ta mesure. Une case « non mesuré » dit pourquoi.
> Lab : Proxmox VE 9 sur `pve01`, VMs 2 vCPU, disques `local-nvme`, `vsandbox` (DHCP) sauf Talos (adresses fixes) et Cluster API (VLAN 40).

| Critère | kubeadm (`k8s-par1`) | k3s | RKE2 (CIS) | Talos | Cluster API + CAPMOX | kind / k3d |
|---|---|---|---|---|---|---|
| Installation (topologie testée) | [≈ 2 h, 3+3 nœuds, M14-E02 à E05] | [min, 1 serveur, E03] ; [min, 3 serveurs, E07, E25] | [min, 3 serveurs, E04] | [min, 1+2, E05] | [min, 1+2, E10] | [s, E02] ; [min avec MédiAgenda, E18] |
| Mémoire au repos, nœud de contrôle | [Go, M14] | [Mo, E03] | [Go, E04] | [Mo, E05] | comme kubeadm + cluster de gestion ([Go]) | [Mo par cluster, E02] |
| Durcissement par défaut | rien (à poser) | rien (guide de durcissement) | profil CIS : PSA `restricted`, NetworkPolicy, `etcd` dédié, vérification de l'hôte | OS minimal sans SSH, PSA `baseline`, API à rôles | comme kubeadm (image et gabarits) | sans objet |
| kube-bench (référentiel le plus proche) | non relancé (M26) | [`k3s-cis-1.9` : P/F/W] | [`rke2-cis-1.9` : P/F/W] | non pertinent (E15) | — | — |
| Montée de version (durée, étapes manuelles) | [min, ≈ 20 étapes, M14-E25] | [min, 0 étape avec system-upgrade-controller, E07] | [non mesuré : même mécanisme que k3s] | [min, 2 commandes, E06] | [min, 2 MR, E13] | recréation |
| Restauration (RTO / RPO / étapes) | [RB-141, M14-E24] | [E14] | [E14] | [E14] | cluster de gestion : [E14] | sans objet |
| Réparation automatique | non | non | non | non | oui (MHC, E13 : [min]) | non |
| Recette éphémère | non | [min sur VM] | — | — | [min, VMs réelles] | [min, E18] |
| Dépendance / pérennité | projet Kubernetes | projet CNCF (sandbox), porté par SUSE | SUSE | Sidero Labs (Talos open source, Omni commercial) | SIG Kubernetes + fournisseur IONOS en 0.x | SIG Kubernetes (kind), communauté (k3d) |
| Compatible écosystème bloc C (Cilium, ceph-csi, CNPG) | oui (référence) | oui (Flannel à remplacer pour Cilium) | oui (Canal à remplacer pour Cilium) | oui (extensions pour ceph-csi) | oui (kubeadm) | essais seulement |

Sources : `tests/cycle-de-vie-capi.md`, `tests/restaurations.md`, `durcissement.md`, `capo.md`, feuille de temps de M18-E18, mesures des paliers 1 et 2 (`tests/`), `docs/kubernetes/tests/` (M14).

## Démonstration de l'option retenue (ADR-0180)

| Date | Commande | Durée de construction | Durée de destruction | Remarques |
|---|---|---|---|---|
| [répétition] | `task demo:construire` | [min] | [s] | |
| [revue] | `task demo:construire` | [min] | [s] | |
