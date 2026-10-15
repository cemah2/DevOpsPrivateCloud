# CHG-1517 — Maintenance d'un travailleur, ajout puis retrait de `k8s-w04`

> `plateforme/medisphere`, `docs/kubernetes/changements/` — ticket PLAT-1517. Modèle des fiches du socle.

| | |
|---|---|
| **Demandeur** | Nadia Roussel |
| **Réalisé par** | `<MOI>` |
| **Fenêtre** | `<DATE>`, 14 h 00 - 17 h 00 (hors recette MédiAgenda) |
| **Systèmes** | `k8s-par1` (`k8s-w02`, `k8s-w01`, nouveau `k8s-w04`), `pve01`, NetBox, `plateforme/infra`, `plateforme/k8s` |
| **Risque** | Faible (un travailleur à la fois, PDB en place, bases jetables connues) |
| **État** | Fermée |

## Objectif

1. Mettre `k8s-w02` en maintenance puis le remettre en service sans erreur côté MédiAgenda.
2. Ajouter un travailleur `k8s-w04` (2147, 10.10.40.64, baie A) par le code et y faire tourner des charges.
3. Retirer `k8s-w04` proprement, jusqu'à la destruction de la VM.

## Prérequis (contrôlés avant de commencer)

- [x] Mémoire libre sur `pve01` ≥ 10 Go (`free -g` : la VM prend 8 Go).
- [x] Cluster sain : six nœuds `Ready`, aucun pod `Pending` hors essais, etcd sain (`kubectl get --raw /readyz?verbose`).
- [x] PDB `mediagenda-api` présent, `ALLOWED DISRUPTIONS` = 1 ; trois réplicas sur deux zones.
- [x] Sonde de disponibilité d'E16 en marche dans `wb-essais`.
- [x] Prévenir l'équipe MédiAgenda : PostgreSQL et Valkey de dev sont jetables (`emptyDir`). Le drain de `k8s-w02` **efface** un réplica Valkey (resynchronisé) ; aucun drain de `k8s-w03` (base) dans ce changement.

## Étapes

### A. Maintenance de `k8s-w02`

1. `kubectl drain k8s-w02` (sans option) : refus attendu, deux raisons listées :
   - `cannot delete DaemonSet-managed Pods` (Cilium, `sonde-noeud`) ;
   - `cannot delete Pods with local storage` (Valkey, `emptyDir`).
2. `kubectl drain k8s-w02 --ignore-daemonsets --delete-emptydir-data --timeout=10m`
   - `--ignore-daemonsets` : les pods de DaemonSet restent (ils reviendraient aussitôt, et Cilium doit rester pour que le nœud fonctionne) ;
   - `--delete-emptydir-data` : accepté **parce que** les seuls `emptyDir` sont des caches et des données jetables, vérifiés avant ;
   - pas de `--force` (il évincerait des pods sans contrôleur, perdus définitivement) ni de `--disable-eviction` (il contournerait les PDB).
3. Constater : évictions une par une, `evicting pod … error when evicting pods/… (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget` tant que le remplaçant n'est pas prêt ; nœud `Ready,SchedulingDisabled`.
4. `kubectl uncordon k8s-w02`. Les pods **ne reviennent pas** seuls : l'ordonnanceur ne déplace rien (un `kubectl rollout restart` ou le désordonnanceur, *descheduler*, le ferait).

### B. Ajout de `k8s-w04`

1. MR `plateforme/infra` : `avec_k8s_w04 = true` (`envs/k8s/terraform.tfvars`) ; pipeline (plan relu, apply) : VM 2147, DNS.
2. NetBox : VM `k8s-w04` (étiquettes `env-k8s`, `role-k8s-worker`, statut actif, adresse 10.10.40.64/24) ; `uv run ansible-inventory --graph k8s_travailleurs` la montre.
3. `task noeuds -- --limit k8s-w04` (playbooks `k8s-noeuds.yml` puis `k8s-cluster.yml`) : préparation, jeton de jonction court obtenu sur `k8s-cp01`, `kubeadm join`.
4. `cluster/noeuds.yaml` : `k8s-w04` en `par1-baie-a` (MR), `task etiquettes`.
5. Contrôles : `kubectl get node k8s-w04 -L topology.kubernetes.io/zone` (`Ready`, `par1-baie-a`), pods `cilium-*` et `sonde-noeud-*` présents, `sudo kubeadm token list` sur `k8s-cp01` (le jeton du rôle a un TTL court ; rien d'autre).
6. Charges : `kubectl drain k8s-w01 --ignore-daemonsets --delete-emptydir-data`, constater des réplicas de l'API sur `k8s-w04` (baie A), `kubectl uncordon k8s-w01`.

### C. Retrait de `k8s-w04`

1. `kubectl drain k8s-w04 --ignore-daemonsets --delete-emptydir-data`.
2. `kubectl delete node k8s-w04`.
3. Sur `k8s-w04` : `sudo kubeadm reset -f`, puis ce que `reset` ne fait pas : `sudo rm -rf /etc/cni/net.d`, `sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X` (et `nft flush ruleset` si des tables nftables restent), `sudo systemctl stop kubelet`. Arrêt de la VM.
4. `cluster/noeuds.yaml` : retirer `k8s-w04` (MR).
5. MR `plateforme/infra` : `avec_k8s_w04 = false` ; pipeline : VM détruite, DNS retiré.
6. NetBox : VM `k8s-w04` supprimée (ou statut *décommissionné*) ; l'inventaire ne la montre plus.

## Contrôles de fin

- `kubectl get nodes` : six nœuds `Ready`, aucun `SchedulingDisabled`.
- `qm status 2147` sur `pve01` : la VM n'existe pas.
- `lab/bin/check 14 17` vert.

## Retour arrière

- A : `kubectl uncordon k8s-w02` à tout moment.
- B : si la jonction échoue, `sudo kubeadm reset -f` sur `k8s-w04`, `kubectl delete node k8s-w04` s'il est apparu, puis C.4-C.6.
- C : avant C.2, `kubectl uncordon k8s-w04` remet le nœud en service.

## Résultat

| Mesure | Valeur |
|---|---|
| Durée du drain de `k8s-w02` | `<MESURE>` (≈ 1 min) |
| `ECHEC` de la sonde pendant A | `<MESURE>` (attendu : 0) |
| Durée d'ajout de `k8s-w04` (MR fusionnée → `Ready`) | `<MESURE>` (≈ 15 min) |
| `ECHEC` pendant C | `<MESURE>` |

Écarts : `<ÉCARTS>`. Éléments repris dans RB-140 : options de `drain` et leur justification, nettoyage après `kubeadm reset`, rejouer `task etiquettes` après toute jonction.
