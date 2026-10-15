# RB-171 — Conflit de propriété des champs (*server-side apply*)

*Créé en M17-E22 (INC-4422). Helm 4 (releases en SSA, gestionnaire `helm`), `kubectl apply --server-side` (gestionnaire `kubectl`).*

## Reconnaître

```
Error: UPGRADE FAILED: conflict occurred while applying object <espace>/<nom> apps/v1, Kind=Deployment:
Apply failed with N conflicts: conflicts with "<gestionnaire>" [with subresource "scale"] using apps/v1:
- .spec.template.spec.containers[name="api"].env[name="MEDIAGENDA_LOG_LEVEL"].value
```

Le message donne l'objet, le **gestionnaire** concurrent et les **champs**. Rien n'a été modifié : la release passe en `failed`.

## Lire la propriété

```
kubectl get <genre> <nom> -n <espace> --show-managed-fields -o json \
  | jq '.metadata.managedFields[] | {manager, operation, subresource, time}'
```

| Gestionnaire | D'où il vient |
|---|---|
| `kubectl-edit` | `kubectl edit` |
| `kubectl-patch`, `kubectl-set`, `kubectl-label`… | les commandes du même nom |
| `kubectl-client-side-apply` | `kubectl apply` **sans** `--server-side` (et annotation `last-applied-configuration`) |
| `kubectl` | `kubectl apply --server-side` sans `--field-manager` (livraison des overlays) ; `kubectl scale` (sous-ressource `scale`) |
| `kube-controller-manager` + `scale` | un HorizontalPodAutoscaler |

`fieldsV1` se lit comme un arbre : `f:` champ, `k:` élément de liste repéré par sa clé, `v:` valeur. `time` date la dernière écriture.

## Décider

1. **La modification manuelle était-elle voulue ?** Oui : elle va dans le chart ou les valeurs (MR), puis on rend le champ à Helm. Non : on la défait.
2. **Un contrôleur doit-il gérer ce champ ?** HPA voulu : le chart ne rend plus `spec.replicas` (valeur `autoscaling.enabled`), et `helm` doit **abandonner** le champ. HPA non voulu : on le supprime.

## Corriger

- Rendre le champ à Helm, une fois la cause comprise : `helm upgrade … --force-conflicts` (une fois, pas dans la commande habituelle).
- Ou retirer l'entrée du gestionnaire concurrent :
  ```
  i=$(kubectl get <genre> <nom> -n <espace> --show-managed-fields -o json | jq '.metadata.managedFields | map(.manager) | index("kubectl-edit")')
  kubectl patch <genre> <nom> -n <espace> --type json -p "[{\"op\":\"remove\",\"path\":\"/metadata/managedFields/$i\"}]"
  helm upgrade …            # Helm repose sa valeur, sans forçage
  ```
- Client-side : retirer aussi l'annotation `kubectl.kubernetes.io/last-applied-configuration`.
- Vérifier en **changeant réellement** une valeur concernée dans le chart : l'upgrade doit passer.

## Pièges

- **Défaire à la main** la modification ne suffit pas : l'ancien gestionnaire **copossède** le champ (même valeur). Le conflit reviendra le jour où le chart changera cette valeur.
- Mettre `--force-conflicts` dans la commande habituelle : toute dérive future sera écrasée en silence.
- Confondre avec `--force-replace` (supprime et recrée l'objet).
- HPA + `replicas` dans le chart : conflit à chaque montée, ou nombre de pods qui saute.

## Prévenir

RBAC : pas d'`update`/`patch` humain sur les Deployments des environnements, sauf bris de glace. Une seule commande d'application par dépôt. Diff à trois voies dans chaque MR (M17-E14). Argo CD au M20 (dérive affichée, réparation automatique).
