# M25-E10 — Conception des rôles JWT (modèle de réponse)

| Rôle | `project_id` | `ref_protected` | `ref` | `ref_type` | `environment` | Politique |
|---|---|---|---|---|---|---|
| `ci-mediagenda-api` | `"<ID>"` (chaîne) | `"true"` (chaîne) | `main`, `v*` | `branch`, `tag` | — | `ci-mediagenda-api` |
| `ci-mediagenda-api-promotion` | `"<ID>"` | `"true"` | `main`, `v*` | `branch`, `tag` | `promotion/*` | `ci-mediagenda-api-promotion` |
| `ci-medidoc-medidoc` (+ `-promotion`) | `"<ID>"` | `"true"` | `main`, `v*` | `branch`, `tag` | (`promotion/*`) | idem |
| `ci-plateforme-secrets` | `"<ID>"` | `"true"` | `main`, `conf/*` | `branch` | — | `tofu-secrets` |

Audience liée : `openbao.medisphere.internal` ; type des revendications liées : `glob` ; `user_claim` : `project_path`.

1. **`project_id` plutôt que `project_path`** : l'identifiant ne change pas si le projet est renommé ou déplacé, et il n'est pas réattribué ; un chemin libéré (projet supprimé, renommé) peut être repris par un **autre** projet qui hériterait du rôle.
2. **`ref_protected` et `ref`** : `ref` seul accepte une branche `main` d'un fork ou une branche nommée `main` créée avant d'être protégée… et surtout ne dit rien des droits de qui a poussé ; `ref_protected` seul accepte **toutes** les branches protégées, y compris celles qu'un Maintainer protège pour un essai. Les deux ensemble : « la branche `main`, et elle est protégée ».
3. **`bound_subject` seul** : `sub` vaut `project_path:<chemin>:ref_type:<type>:ref:<ref>` : il ne contient ni la protection, ni l'environnement, ni le runner, et il repose sur le chemin (point 1). Il ne permet pas non plus de distinguer le job de promotion des autres jobs de `main`.
