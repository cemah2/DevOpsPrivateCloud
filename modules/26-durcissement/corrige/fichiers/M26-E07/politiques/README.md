# plateforme/politiques

Politiques de sécurité du cluster `k8s-par1`, appliquées par l'Application Argo CD **`politiques`**
(Kustomize, racine du dépôt). Créé en M26-E07 (PLAT-2707).

| Dossier | Contenu | Depuis |
|---|---|---|
| `kyverno/validation/` | `ValidatingPolicy` (`policies.kyverno.io/v1`) | E07 |
| `kyverno/images/`, `kyverno/mutation/`, `kyverno/generation/`, `kyverno/exceptions/` | signatures, mutations, générations, exceptions | E15-E18 |
| `kyverno/tests/<politique>/` | tests de la CLI (`kyverno test`) : ressources conformes et non conformes | E07 |
| `falco/`, `tetragon/` | règles Falco, `TracingPolicy` | E19, E20 |

## Règles du dépôt

- **Uniquement** les types CEL de `policies.kyverno.io/v1` : `ClusterPolicy` et `Policy` (dépréciées en
  Kyverno 1.19, supprimées en 1.20) sont refusées en revue.
- Une politique entre **toujours** en `validationActions: [Audit, Warn]` et `failurePolicy: Ignore`.
- Toute politique a son test dans `kyverno/tests/<politique>/` ; la CI (`kyverno:tests`) doit passer.
- `kustomization.yaml` ne liste **que** des politiques, jamais un fichier de `kyverno/tests/`.
- Jamais de politique qui vise `kube-system`, `kyverno` ou `argocd` (exclus aussi des webhooks).

## Passer une politique de l'audit au refus

1. Au moins une semaine de rapports (`kubectl get policyreports -A`) sans violation inexpliquée.
2. Les violations restantes sont corrigées dans leurs dépôts, ou couvertes par une `PolicyException`
   datée et justifiée (E18).
3. MR qui passe `validationActions` à `[Deny, Audit]` **espace par espace** si possible (sélecteur
   resserré d'abord à la recette), et `failurePolicy: Fail` seulement si l'indisponibilité de Kyverno
   doit bloquer (signatures en production, E15).
4. Retour arrière : la MR inverse ; en urgence, `kubectl delete validatingpolicy <nom>` (admin.conf).

## Décision proposée (E07)

| Politique | Proposition | Pourquoi |
|---|---|---|
| `registres-autorises` | rester en audit | la VAP `medisphere-images` (M14) refuse déjà en `Deny` dans les mêmes espaces ; Kyverno apporte les rapports sur l'existant |
| `exiger-etiquettes` | refus en recette et prod après correction des charts | les écarts relevés sont des oublis de chart (sous-charts, StatefulSet de dépendances) ; corrigés, l'étiquette devient fiable pour E16 |
