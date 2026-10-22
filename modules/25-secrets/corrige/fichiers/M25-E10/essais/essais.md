# M25-E10 — Essais du refus (modèle ; aucun jeton recopié ici)

| Date | Projet | Référence | Protégée | Rôle | Résultat |
|---|---|---|---|---|---|
| AAAA-MM-JJ HH:MM | formation/ci-labo | essai-oidc | non | ci-formation-ci-labo | refusé : `error validating claims: claim "ref_protected" does not match any associated bound claim values` |
| AAAA-MM-JJ HH:MM | formation/ci-labo | main | oui | ci-formation-ci-labo | accepté : longueur du secret affichée, jeton révoqué en fin de job |
| AAAA-MM-JJ HH:MM | mediagenda/api | main | oui | ci-mediagenda-api-promotion (job `image:construction`) | refusé : `claim "environment" does not match…` (le job ne déclare pas d'environnement) |

Rôle d'essai, politique et secret `kv/formation/ci/essai` supprimés le AAAA-MM-JJ (MR !<N>).
