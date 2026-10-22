# Qui peut écrire dans `k8s-par1`, et par quel chemin

| | |
|---|---|
| Ticket | SEC-2130 |
| Exercice | M20-E30 |
| Revue | trimestrielle (procédure en fin de page) ; dernière : <DATE> |

## Chemins d'écriture autorisés

| Chemin | Qui | Où | Contrôle |
|---|---|---|---|
| Argo CD (contrôleur, gestionnaire `argocd-controller`) | ce qui est fusionné sur `main` des dépôts suivis | espaces applicatifs, services de plateforme sous Argo CD | MR relue (Maintainers), AppProjects, RBAC d'Argo CD (E24), fenêtres (E29) |
| Contrôleurs de Kubernetes et des opérateurs (`kube-controller-manager`, `rollouts-controller`, CNPG, cert-manager…) | eux-mêmes | statut, réplicas, objets dérivés | code des contrôleurs ; ignorés par Argo CD quand c'est voulu (`ignoreDifferences`) |
| Plateforme (Helmfile, `task appliquer`, `secrets-k8s.sh`) | `role:plateforme-admin` depuis `adm01`, identité personnelle (7 jours) | couche de base, espaces, politiques, Secrets | MR sur `plateforme/k8s`, ticket |
| Bris de glace (`admin.conf`, `super-admin.conf`) | astreinte plateforme | partout | Vault `critique`, ticket INC, audit de l'API |
| CI (`formation/ci-labo` par l'agent `k8s-par1`) | jobs de ce seul projet | `wb-essais` seulement (`edit`) | `ci_access` + RoleBinding |

**La CI des applications n'écrit plus rien dans le cluster.** Elle construit, signe, et **propose** (MR de promotion par le jeton de projet `ci-promotion`, portées `api` + `write_repository` sur `mediagenda/deploiement`, sans aucun droit Kubernetes). Un jeton de CI volé permet au pire d'ouvrir une MR, qui sera relue et dont les images doivent être signées par la clé MédiSphère (porte de vérification du M19-E29).

## Preuves (relevées le <DATE>)

```
admin@adm01:~$ kubectl get rolebindings -A -o json | jq -r '.items[] | select(any(.subjects[]?; .kind=="ServiceAccount" and .namespace=="gitlab-agent")) | "\(.metadata.namespace)/\(.metadata.name) -> \(.roleRef.name)"'
wb-essais/gitlab-agent-edit -> edit
admin@adm01:~$ kubectl get clusterrolebindings -o json | jq -r '.items[] | select(any(.subjects[]?; .kind=="ServiceAccount" and .namespace=="gitlab-agent")) | .metadata.name'
(aucune ligne)
admin@adm01:~$ kubectl auth can-i create deployments -n mediagenda-dev --as system:serviceaccount:gitlab-agent:gitlab-agent
no
admin@adm01:~$ kubectl auth can-i create deployments -n wb-essais --as system:serviceaccount:gitlab-agent:gitlab-agent
yes
```

Essai depuis un job de `formation/ci-labo` (branche d'essai, contexte `formation/ci-labo:k8s-par1`) :
- `kubectl -n mediagenda-dev create configmap essai-sec-2130 --from-literal=a=b` → `Error from server (Forbidden): … cannot create resource "configmaps" … in the namespace "mediagenda-dev"` ;
- même commande dans `wb-essais` → `configmap/essai-sec-2130 created` (supprimée ensuite).

Gestionnaires de champs des objets applicatifs :
```
admin@adm01:~$ for ns in mediagenda-dev mediagenda-recette mediagenda-prod medidoc-dev medidoc-recette; do
>   kubectl -n "$ns" get deploy,statefulset,service -o json | jq -r --arg ns "$ns" \
>     '.items[] | "\($ns)/\(.kind)/\(.metadata.name): \([.metadata.managedFields[].manager] | unique | join(", "))"'
> done
mediagenda-prod/Deployment/mediagenda: argocd-controller, kube-controller-manager, rollouts-controller
…
```
Avant nettoyage, on trouvait `kubectl` (opération `Apply` : les `kubectl apply --server-side` du M17 et du job `deployer-dev` du M19) et parfois `kubectl-edit`, `kubectl-scale`, `kubectl-rollout` (gestes manuels). Argo CD ne migre d'office que le gestionnaire client `kubectl-client-side-apply` (opération `Update`) : les autres ont été retirés par `outils/nettoyer-gestionnaires.sh` (essai côté serveur d'abord : `.spec` identique avant et après), objet par objet.

## Revue trimestrielle

1. Les deux requêtes `jq` ci-dessus (RoleBindings et ClusterRoleBindings des comptes de `gitlab-agent`) ; `ci_access` de `.gitlab/agents/k8s-par1/config.yaml`.
2. Variables de CI des groupes `mediagenda`, `medidoc` : aucune `KUBE_*`, aucun kubeconfig.
3. Jetons de projet : `ci-promotion` (portées, expiration, rotation : `secrets-ci.md`, M19-E25).
4. Gestionnaires de champs des espaces applicatifs (requête ci-dessus) : aucun `kubectl*`, `helm`, `agentk`, `gitlab*` — sinon, enquête (qui ? audit de l'API, M14-E27).
5. `lab/bin/check 20 30`.
