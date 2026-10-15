# Reconstruire `k8s-par1` (et un de ses nœuds) depuis le code

> `plateforme/medisphere`, `docs/kubernetes/reconstruction.md` — M14-E23 (PLAT-1523).

## Ce qui fait foi

| Dépôt | Contient |
|---|---|
| `plateforme/infra` (`envs/k8s`) | les VMs (VMID, adresses, MAC, ressources), leurs noms DNS |
| `plateforme/ansible` | préparation des nœuds (containerd, paquets épinglés, miroirs Harbor), keepalived/HAProxy de la VIP, kubeadm (amorçage, jonctions) |
| `plateforme/k8s` | configuration kubeadm, étiquettes et taints des nœuds, composants (Cilium, metrics-server), espaces, budgets, RBAC, admission, priorités, outils |
| Coffres | Vault `lab`/`critique` (bris de glace, clés), `~/.config/workbook/` sur `adm01` (robot Harbor) |

Ce qui **n'est pas** dans le code et se perd à une reconstruction complète : l'état d'etcd (objets
créés par les équipes, Secrets générés) — c'est la sauvegarde etcd (M14-E24) qui le couvre — et les
données des bases jetables du M14 (assumé jusqu'au M16).

La procédure complète du cluster est dans le `README.md` de `plateforme/k8s` (« Reconstruire le cluster depuis zéro »).

## Reconstruire un travailleur (procédure testée sur `k8s-w02`)

⚠️ Un seul nœud à la fois ; jamais `k8s-w03` sans prévenir les équipes (bases jetables) ; jamais un
nœud de contrôle par cette procédure (membre etcd : M14-E29).

1. **Avant** : `task verifier` vert ; sonde de disponibilité en marche (`wb-essais/sonde-disponibilite`) ;
   PDB satisfaits (`kubectl get pdb -A`).
2. **Sortir le nœud** : `kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data --timeout=10m`,
   puis `kubectl delete node k8s-w02`.
3. **Détruire et recréer la VM** par le code : dans `plateforme/infra/envs/k8s`,
   repère l'adresse de la ressource VM (`tofu state list | grep 'noeud\["k8s-w02"\]'`), puis
   `tofu plan -replace='<ADRESSE-DE-LA-VM>'` relu et `tofu apply` du même plan (option `-replace` :
   remplacement d'une **ressource**, pas d'un module entier). La VM revient avec le même VMID, la même
   adresse, la même MAC. Commande et plan consignés dans le ticket.
4. **Préparer et joindre** : `task noeuds -- --limit k8s-w02` (élargir à `k8s-cp01` si le rôle de jonction
   en a besoin) : containerd, miroirs Harbor, paquets épinglés, jeton de jonction court, `kubeadm join`.
5. **Étiquettes et taints** : `task etiquettes`.
6. **Vérifier** : `task verifier` ; `kubectl get node k8s-w02 -L topology.kubernetes.io/zone` ; pods
   Cilium et `sonde-noeud` dessus ; aucun `ECHEC` de la sonde de disponibilité.

## Compte rendu de la reconstruction de `k8s-w02` (`<DATE>`)

| Étape | Durée mesurée |
|---|---|
| Drain + suppression du nœud | `<MESURE>` |
| VM détruite et recréée (pipeline) | `<MESURE>` |
| Préparation et jonction (Ansible) | `<MESURE>` |
| Étiquettes, vérification | `<MESURE>` |
| **Total** | `<MESURE>` (≈ 30 min attendu) |

Écarts constatés et corrections apportées au code (à remplir) : par exemple, une étiquette posée à la
main absente de `cluster/noeuds.yaml` ; un `hosts.toml` manquant parce que la variable des miroirs
n'était pas dans le bon `group_vars` ; un jeton de jonction expiré entre deux étapes.
`ECHEC` de la sonde pendant l'opération : `<MESURE>` (attendu : 0).
