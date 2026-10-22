# Argo CD et Flux : le même déploiement avec deux outils

> Exemple de livrable (M20-E23, PLAT-2123). Mesures prises sur `flux01` (k3s 1.36, 2 Go, Flux 2.9) et
> `k8s-par1` (Argo CD 3.5). Remplace les valeurs entre chevrons par les tiennes.

## Ce qui a été fait des deux côtés

| Étape | Argo CD (`k8s-par1`) | Flux (`flux01`) |
|---|---|---|
| Installation | Helmfile, release `argocd` (chart 10.10, ~10 pods) | `flux bootstrap gitlab` : manifestes **commités** dans `formation/flux-labo` (`clusters/flux01/flux-system/`), 4 contrôleurs |
| Accès au dépôt | jetons de déploiement par groupe, modèle `repo-creds` (E06) | jeton de déploiement de projet créé par `--deploy-token-auth`, Secret `flux-system` |
| Application « labo » | Application (puis ApplicationSet) → dossier Git | `Kustomization` (ressource Flux) → dossier Git |
| Chart Helm | Application multi-sources (chart OCI + `$values`) | `OCIRepository` + `HelmRelease` (le chart est **installé par Helm** : `helm list -n podinfo` le montre) |
| Auto-réparation | option `selfHeal` | comportement par défaut à chaque `interval` |
| Suppression de l'orphelin | `prune` | `prune: true` |
| Ordre | vagues et hooks dans les manifestes | `dependsOn` entre Kustomizations / HelmReleases |
| Interface | web, RBAC, SSO, diff visuel | aucune (CLI `flux`, événements, Weave GitOps/Headlamp en option) |
| Multi-cluster | un Argo CD central qui pousse vers N clusters | un Flux **par** cluster, qui tire (rien à exposer) |
| Mémoire mesurée au repos | <≈ 600 Mo pour argocd-*, `kubectl top pods -n argocd`> | <≈ 150 Mo pour les 4 contrôleurs, `kubectl top pods -n flux-system` (metrics-server désactivé sur flux01 : mesuré par `crictl stats`)> |

## Ce qui m'a surpris

- **Bootstrap** : Flux écrit ses propres manifestes dans le dépôt et se gère lui-même (monter Flux = MR
  sur `gotk-components.yaml` ou `flux bootstrap` rejoué). Argo CD est installé par Helmfile chez nous :
  le « qui gère le gestionnaire » est explicite dans les deux cas, mais différemment.
- **Helm** : Flux garde une vraie release Helm (hooks Helm exécutés tels quels, `helm history`) ; Argo CD
  rend le chart en manifestes et convertit les hooks en hooks Argo CD (`helm list` est vide).
- **Pas d'UI** : le diagnostic passe par `flux get all -A`, `flux events`, `kubectl describe` ; pour
  l'équipe de Julien, c'est un recul réel par rapport à l'interface d'Argo CD.
- **Interblocage d'un Secret** : Flux ne sait pas lire le dépôt tant que son Secret n'existe pas ; le
  bootstrap le crée, mais pour `OCIRepository` les Secrets `harbor-charts` et `medisphere-ca` sont
  créés à la main (hors Git), comme chez nous pour Argo CD jusqu'au M25.

## Recommandation (pour l'ADR-0200, M20-E31)

Argo CD reste l'outil de MédiSphère : interface et RBAC pour les équipes de développement, ApplicationSets,
canary avec Argo Rollouts déjà en place, vision centrale de plusieurs clusters (LYO1). Flux serait le
bon choix pour un cluster **isolé** sans équipe applicative (appliance, site distant sans lien entrant),
ou si l'on voulait que chaque cluster tire seul sa configuration. Kargo (promotion entre environnements,
par les auteurs d'Argo CD, qui s'intègre à lui) n'est pas retenu à ce stade : la promotion par MR
(M20-E14) suffit à notre volume.
