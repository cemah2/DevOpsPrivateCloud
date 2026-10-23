# RB-341 — Monter Kubernetes (ou remplacer un nœud) sous la sonde de continuité

| | |
|---|---|
| Complète | RB-142 (montée de version, M14-E25) : ce runbook ajoute la décision, l'ordre de toute la chaîne et la mesure |
| Fiches | CHG-3403 (go/no-go), CHG-3404 (exécution) |
| Outils | `plateforme/k8s/outils/controles-montee.sh`, playbook `playbooks/k8s-montee-version.yml` (M14-E25), sonde (RB-340) |

## 1. Décider (CHG-3403)

1. Matrice `docs/changements/matrices/compatibilite-kubernetes-<mineure>.md` : chaque composant installé, ce qu'il **déclare**, la source. Un silence n'est pas un oui.
2. `outils/controles-montee.sh api <mineure>` : API dépréciées réellement appelées.
3. CHANGELOG de la mineure : *Urgent Upgrade Notes*, *Deprecation*, kubeadm ; changements de comportement qui touchent ce cluster.
4. Décision écrite (`decision: go|no-go`). Si **no-go** : ce qui est prêt se fait quand même (CNI, correctifs, remplacement de nœuds), et la fiche dit quand on revoit la décision.

## 2. L'ordre de la chaîne

1. **Ce qui doit déclarer la cible avant le plan de contrôle** : le CNI (Cilium : sa nouvelle mineure accepte encore l'ancienne de Kubernetes), puis les composants à webhooks d'admission (Kyverno, Capsule, cert-manager, kubelet-csr-approver) et ceux qui ne déclarent pas encore la cible (Argo CD, KEDA) — chacun son changement (CHG-3405).
2. **Plan de contrôle**, un nœud à la fois (`kubeadm upgrade apply` sur le premier, `upgrade node` sur les autres) ; CoreDNS et kube-proxy (retiré ici : Cilium le remplace) suivent après le dernier.
3. **Travailleurs**, un à la fois, drain respectant les PDB.
4. **Outils** de `adm01` (kubectl ±1, kubelogin, etcdctl), **schémas** kubeconform (`outils/schemas-crd.sh generer`, `publier`, M29), **code** (MR des versions fusionnée après).

## 3. Avant chaque drain

```
admin@adm01:~/src/k8s$ outils/controles-montee.sh noeud k8s-w0N
```

- **CNPG** : si le primaire est sur le nœud, le **cordon** déclenche une bascule (*switchover*) vers une réplique avant le drain (documentation « Kubernetes Upgrade and Maintenance » de CloudNativePG) ; vérifie `kubectl cnpg status` et le pooler. Ne pas utiliser `nodeMaintenanceWindow` (conservé pour compatibilité, déconseillé) sauf cluster à une instance.
- **RabbitMQ** : le pré-arrêt des pods de l'opérateur attend que chaque file quorum garde sa majorité ; `rabbitmq-queues check_if_node_is_quorum_critical` doit passer **avant** ; compter quelques minutes.
- **Webhooks** à « Fail » (Kyverno, Capsule, ESO, cert-manager) : réplicas sur plusieurs nœuds, PDB du chart ; si tous les réplicas sont sur le nœud drainé, plus aucune admission visée ne passe pendant le redémarrage.
- **PDB** : aucune à 0 perturbation autorisée (hors primaire CNPG) ; jamais plusieurs PDB sur un même pod (l'éviction les refuse).

## 4. Pendant

Un nœud ne passe au suivant que si : nœud `Ready`, Cilium prêt dessus (`cilium status --wait`), pods revenus, tableau « Changement en cours » à 0 sur les 5 dernières minutes. Abandon : critères de la fiche.

## 5. Remplacement immuable d'un travailleur (alternative ou complément)

1. Image dorée reconstruite (`plateforme/images`), essayée sur une VM jetable.
2. `kubectl cordon` puis `kubectl drain <nœud> --ignore-daemonsets --delete-emptydir-data --timeout=15m`.
3. `kubectl delete node <nœud>`.
4. `tofu -chdir=envs/k8s state list | grep '"<nœud>"'` puis `tofu -chdir=envs/k8s plan -replace=<ADRESSE-DE-LA-VM>` (relire : une seule VM remplacée, NetBox et DNS inchangés) puis `apply`.
5. `task noeuds -- --limit <nœud>,k8s-cp01` ; inscription FreeIPA (l'hôte existe déjà dans l'annuaire : réinscription à prévoir, à vérifier sur ta version de `freeipa_client`) ; `task etiquettes` ; CSR du kubelet approuvée par kubelet-csr-approver ; rôles transverses.
6. `kubectl uncordon` si nécessaire ; contrôles.

## 6. Retour arrière

- Avant le premier `kubeadm upgrade apply` : rien à défaire.
- Plan de contrôle monté : pas de redescente de mineure par kubeadm ; retour = restauration d'etcd (RB-141) et paquets de l'ancienne mineure, **seulement** si le cluster est inutilisable ; sinon on répare en avant.
- Nœud remplacé : on répare en avant ; filet PBS `par1/k8s`.

## 7. Mesure et clôture

RB-340 §3 ; en-tête de la fiche rempli ; `lab/bin/check F4 4`.
