# Le cluster k8s-par1 — fiche d'exploitation

> `docs/kubernetes/cluster.md` (plateforme/medisphere), M14-E05 (PLAT-1505). Mise à jour à chaque
> changement structurant (montée de version : M14-E25, réseau : M15, stockage : M16).

## En une phrase

Cluster Kubernetes **kubeadm** de PAR1, trois nœuds de contrôle (etcd empilé) et trois travailleurs,
API derrière une VIP keepalived + HAProxy, CNI Cilium. Il porte MédiAgenda et, à partir du M15, les
composants de plateforme.

## Composition

| Élément | Valeur |
|---|---|
| Version | Kubernetes **1.35.9** (paquets `1.35.9-1.1` retenus), kubeadm API v1beta4 |
| Nœuds de contrôle | `k8s-cp01-03` (VMID 2141-2143, 10.10.40.51-53, 2 vCPU, 4 Go) : etcd, kube-apiserver, kube-controller-manager, kube-scheduler (pods statiques), keepalived, HAProxy |
| Travailleurs | `k8s-w01-03` (VMID 2144-2146, 10.10.40.61-63, 4 vCPU, 8 Go) |
| Point d'accès | `https://k8s-api.par1.medisphere.internal:8443` → VIP 10.10.40.200 (VRRP VRID 140, sans préemption) → HAProxy (TCP) → kube-apiserver :6443 des trois nœuds |
| Runtime | containerd.io **2.3.x** (dépôt Docker), cgroups systemd, image pause `registry.k8s.io/pause:3.10.1` |
| Réseau | Cilium **1.20.2** (tunnel VXLAN, IPAM `cluster-pool` 10.240.0.0/16, /24 par nœud), kube-proxy en mode `iptables` (conservé jusqu'au M15) ; Services 10.96.0.0/16 ; domaine `cluster.local` |
| Certificats | CA du cluster 10 ans, certificats feuilles 1 an (renouvelés par `kubeadm upgrade`) |
| Code | VMs : `plateforme/infra` `envs/k8s` ; nœuds : `plateforme/ansible` (rôles `containerd`, `k8s_noeud`, `k8s_plan_controle`, `k8s_travailleur`, playbooks `k8s-noeuds.yml`, `k8s-cluster.yml`) ; cluster : `plateforme/k8s` |

## Gestes courants

| Je veux… | Commande (depuis `adm01`, dans `~/src/k8s`) |
|---|---|
| Voir l'état | `kubectl get nodes -o wide` ; `cilium status` ; `kubectl -n kube-system get pods -o wide` |
| Savoir qui porte la VIP | `for n in k8s-cp01 k8s-cp02 k8s-cp03; do ssh $n ip -br -4 addr show eth0; done` |
| Voir les backends d'HAProxy | `ssh k8s-cp01 'echo "show stat" \| sudo socat stdio unix-connect:/run/haproxy/admin.sock' \| cut -d, -f1,2,18` |
| Reconverger les nœuds | `task noeuds` (un nœud à la fois ; second passage `changed=0`) |
| Appliquer les manifestes | `task diff`, puis `task appliquer` (depuis `main` à jour) |

## Arrêt et démarrage

- **Arrêt** : travailleurs d'abord (`k8s-w03`, `w02`, `w01`), puis nœuds de contrôle (`k8s-cp03`, `cp02`, `cp01`),
  par `qm shutdown <VMID>` sur `pve01`. Pas de drain nécessaire pour un arrêt complet planifié.
- **Démarrage** : nœuds de contrôle d'abord, **au moins deux** pour qu'etcd ait son quorum (l'API ne répond pas
  avant), puis les travailleurs. Contrôle : `kubectl get nodes` (tous `Ready` en 2 à 3 minutes), `cilium status`.
- Un cluster arrêté plus d'un an a des certificats expirés : `kubeadm certs check-expiration` avant toute chose (M14-E26).

## Liens

- Accès et identités : `acces.md` (écrit en M14-E06 ; ajoute alors le lien)
- Runbooks : RB-140 (nœud NotReady), RB-141 (restaurer etcd), RB-142 (montée de version), RB-143 (certificats)
- Décisions : ADR-0140 (distribution et topologie), ADR-0141 (politique de versions)
