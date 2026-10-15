# Test — perte de `k8s-cp02` (PLAT-1529)

> Modèle de compte rendu (M14-E29).

## État de référence (avant)

| Élément | Valeur |
|---|---|
| Leader etcd | <k8s-cp0N> |
| Porteur de la VIP 10.10.40.200 | <k8s-cp0N> |
| Bail `kube-controller-manager` / `kube-scheduler` | <k8s-cp0N_…> / <k8s-cp0N_…> |
| Pods sur `k8s-cp02` | pods statiques, cilium, kube-proxy, <coredns-…> |

## Chronologie de la panne (arrêt brutal `qm stop 2142` à T0)

| Temps | Observation |
|---|---|
| T0 | arrêt |
| T0 + <1-3 s> | VIP sur un autre nœud (si `k8s-cp02` était maître VRRP) ; <n> échecs de `/readyz` à travers la VIP |
| T0 + <~5 s> | HAProxy marque `k8s-cp02` DOWN (sondes) |
| T0 + <~1-2 s> | etcd : nouveau leader si `k8s-cp02` l'était (élection) ; quorum 2/3 |
| T0 + <~15 s> | nouveaux titulaires des baux (durée du bail 15 s par défaut) |
| T0 + <~50 s> | `k8s-cp02` `NotReady` (période de grâce du gestionnaire de contrôleurs) ; taints `node.kubernetes.io/unreachable` |
| T0 + <~5 min 50 s> | pods évincés de `k8s-cp02` (tolérances de 300 s), recréés ailleurs s'ils appartiennent à un contrôleur ; DaemonSets et pods statiques non concernés |

Création d'un Deployment pendant la panne : <réussie>. Réponse d'etcd attendue si un second nœud tombait : plus d'écriture possible (`etcdserver: request timed out`, l'API répond en lecture depuis son cache puis échoue).

## Retour de `k8s-cp02`

<durée jusqu'à Ready, ordre de retour des composants, rattrapage d'etcd>

## Remplacement du membre (RB-144)

| Étape | Durée | Remarque |
|---|---|---|
| Arrêt du plan de contrôle de `k8s-cp02`, `member remove` | | ancien identifiant : <ID> |
| `drain`, `delete node`, `kubeadm reset`, nettoyage | | |
| Rôles (dont audit et chiffrement), jonction | | membre apprenant pendant <x s> |
| Vérifications | | nouvel identifiant : <ID> |
