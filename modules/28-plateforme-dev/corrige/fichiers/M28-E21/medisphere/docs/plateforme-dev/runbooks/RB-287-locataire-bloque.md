# RB-287 — Une équipe ne peut plus créer d'espace

> Rédigé en M28-E21. Propriétaire : équipe Plateforme.

## Reproduire sans le compte de l'équipe
```
admin@adm01:~$ kubectl --kubeconfig <ADMIN.CONF> --as=<utilisateur> --as-group=oidc:<groupe> \
    --as-group=system:authenticated create ns <locataire>-revue-essai --dry-run=server
```

## Lire le message
| Message | Maillon | Vérifier |
|---|---|---|
| `User "…" cannot create resource "namespaces"` | RBAC : le groupe n'est plus un groupe géré par Capsule | `kubectl get capsuleconfiguration default -o yaml` (`users`) ; `plateforme/gitops/valeurs/capsule/values.yaml` |
| refus du webhook de Capsule, quota | locataire plein | `kubectl get tenant <t>` (colonnes de quota et de nombre d'espaces) ; espaces de revue oubliés |
| refus du webhook de Capsule, propriétaire | le groupe ne possède aucun locataire | `kubectl get tenant <t> -o jsonpath='{.spec.owners}'` ; `git log -p -- locataires/` |
| refus, nom protégé ou préfixe | `protectedNamespaceRegex`, `forceTenantPrefix` | `kubectl get capsuleconfiguration default -o jsonpath='{.spec.protectedNamespaceRegex}'` |
| `failed calling webhook … deadline exceeded / connection refused` | webhooks injoignables | pods et Service de `capsule-system`, `kubectl get cnp -n capsule-system`, journaux de l'API |

## Règles
- Corriger par MR (`plateforme/k8s/locataires/`, `plateforme/gitops/valeurs/capsule/`) ; un objet posé à la main se supprime et se signale.
- Jamais d'élargissement des droits de `oidc:plateforme-admins` ni d'Argo CD « pour débloquer ».
- ⚠️ Webhooks injoignables : aucun pod ne démarre dans les espaces des locataires (production comprise) → priorité P1.
