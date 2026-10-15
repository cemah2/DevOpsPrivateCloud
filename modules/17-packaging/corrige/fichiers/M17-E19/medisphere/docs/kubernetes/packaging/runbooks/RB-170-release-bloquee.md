# RB-170 — Release Helm bloquée

*Créé en M17-E19 (INC-4419). Helm 4.3, pilote de stockage « secret ». Lire les Secrets de release exige `get secrets` dans l'espace : kubeconfig personnel (groupe `medisphere:plateforme-admins`).*

## Reconnaître

| Message | Cause probable |
|---|---|
| `another operation (install/upgrade/rollback) is in progress` | la dernière révision est en `pending-install`, `pending-upgrade` ou `pending-rollback` : commande interrompue (coupure réseau, Ctrl+C, job de CI annulé, `helmfile apply` tué) |
| `release: already exists` à l'upgrade, et `helm history` sans la dernière révision | le Secret de la dernière révision est **illisible** (tronqué, modifié à la main) : Helm recalcule ce numéro et se heurte au Secret existant |
| `has no deployed releases` | aucune révision `deployed` (première installation échouée) |

## Constater, sans rien changer

```
helm status <release> -n <espace>
helm history <release> -n <espace> --max 20
helm list -A --pending
kubectl get secret -n <espace> -l owner=helm,name=<release> -L status,version
```

Les étiquettes `status`/`version` des Secrets et `helm history` doivent raconter la même histoire. Une révision présente dans les Secrets mais absente de `helm history` est illisible :

```
kubectl get secret sh.helm.release.v1.<release>.v<N> -n <espace> -o jsonpath='{.data.release}' | base64 -d | base64 -d | gzip -dc | jq '.info'
```

Vérifie ensuite l'**état réel** : les objets portent-ils la version de la dernière révision `deployed`, ou celle de la révision interrompue (`kubectl get deploy … -o yaml`, `rollout history`) ? Une interruption pendant l'application peut laisser des objets à moitié montés.

## Corriger (sauvegarde d'abord)

```
kubectl get secret <NOM> -n <espace> -o yaml > ~/sauvegardes/<NOM>.yaml    # chmod 600 : contient les valeurs
```

1. **Révision `pending-*`** : `helm rollback <release> <dernière révision deployed> -n <espace> --wait`. Le retour est permis depuis cet état. Il réapplique l'état connu, crée une révision `deployed` et débloque. Rejoue ensuite l'opération interrompue (MR, `helmfile apply`). Si les objets avaient déjà reçu la nouvelle version et qu'on veut la garder, rejouer directement l'upgrade **après** le retour.
2. **Révision illisible** : supprimer **ce seul** Secret, après sauvegarde et après avoir vérifié que la révision précédente se lit. Le prochain `helm upgrade` réécrit ce numéro.
3. En dernier recours, pour une révision `pending-*` que le retour ne peut pas traiter : supprimer **ce seul** Secret `pending-*` (sauvegardé), puis upgrade.

## Jamais

- `helm uninstall` / réinstallation : suppression des objets (et des PVC des sous-charts), interruption, perte de l'historique.
- Supprimer **tous** les Secrets de release, ou modifier leurs étiquettes à la main.
- `--force-replace` pour « passer » : supprime et recrée les objets.

## Prévenir

- En CI : `timeout` du job **supérieur** au `--timeout` de Helm ; `resource_group` par release (pas deux applications simultanées) ; ne jamais annuler un job d'application en cours.
- `rollbackOnFailure: true` (Helmfile) : un échec revient à l'état précédent au lieu de rester en `failed` ou `pending`.
- `historyMax: 10` : l'historique reste lisible et léger.
