# Compte rendu — montée de `k8s-par1` de 1.35.<x> à 1.36.5 (CHG-1525)

> Modèle (M14-E25). Remplace les valeurs entre chevrons par les tiennes.

| | |
|---|---|
| Date, fenêtre | <AAAA-MM-JJ>, <HH:MM>-<HH:MM> |
| Instantané etcd préalable | `s3://etcd-k8s-par1/horaire/k8s-cp01/<…>.db.age`, vérifié à <HH:MM> |
| Charge témoin | `boucle-temoin.sh mediagenda-recette mediagenda-api`, lancée à <HH:MM> |

## Déroulé

| Nœud | Méthode | Début | `Ready` en 1.36 | Durée | Observations |
|---|---|---|---|---|---|
| k8s-cp01 | à la main (`upgrade apply`) | | | (20 min) | ordre : etcd, kube-apiserver, kube-controller-manager, kube-scheduler ; CoreDNS et kube-proxy inchangés à ce stade |
| k8s-cp02 | playbook (`upgrade node`) | | | (10 min) | |
| k8s-cp03 | playbook (`upgrade node`) | | | (10 min) | CoreDNS v1.14.2 et kube-proxy v1.36.5 déployés après ce nœud |
| k8s-w01 | playbook | | | (8 min) | drain : <n> pods évincés, PDB respectée |
| k8s-w02 | playbook | | | (8 min) | |
| k8s-w03 | playbook | | | (8 min) | |

## Bilan de la charge témoin

- MédiAgenda : <0> échec sur <N> requêtes ; latence maximale <x> s à <HH:MM:SS> (drainage de `k8s-w0N`).
- API par la VIP : <n> échecs de `/readyz`, tous pendant <…> (redémarrage d'etcd sur `k8s-cp01`).
- Note : une requête de `port-forward` passe par l'API ; un échec simultané d'un `/readyz` est à imputer à l'API, pas à MédiAgenda.

## Écarts et suites

- <ex. avertissement de containerd sur l'image pause 3.10.1 : rôle containerd corrigé (MR !…)>
- <ex. nettoyage de /etc/kubernetes/tmp/ planifié le …>
