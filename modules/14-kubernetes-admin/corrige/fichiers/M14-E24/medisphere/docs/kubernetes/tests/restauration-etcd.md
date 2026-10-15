# Test de restauration d'etcd — `k8s-par1`

> Modèle de compte rendu (M14-E24). Les valeurs entre chevrons sont celles de **ton** test ; les ordres de grandeur entre parenthèses sont indicatifs.

| | |
|---|---|
| Date | <AAAA-MM-JJ> |
| Opérateur | <MOI> |
| Version | Kubernetes <1.35.x>, etcd <3.6.6> |
| Instantané utilisé | `s3://etcd-k8s-par1/horaire/k8s-cp01/etcd-k8s-cp01-<HORODATAGE>.db.age`, révision <R>, <N> clés, <T> Mo |
| Scénario | ConfigMap `wb-essais/temoin-restauration` (`etat=avant-instantane`) ; après l'instantané, `etat=apres-instantane` puis suppression de l'espace `wb-essais` |

## Chronométrage

| Étape | Début | Fin | Durée | Remarques |
|---|---|---|---|---|
| Téléchargement, déchiffrement, vérification, copie sur les trois nœuds | | | (3 min) | empreintes identiques |
| Arrêt du plan de contrôle (trois nœuds) — **début de l'indisponibilité de l'API** | | | (2 min) | |
| Restauration des trois membres | | | (2 min) | |
| etcd sur les trois nœuds, `endpoint health --cluster` | | | (1 min) | nouveaux identifiants de membres |
| Plan de contrôle, `/readyz` — **fin de l'indisponibilité de l'API** | | | (2 min) | |
| Kubelets, Cilium, CoreDNS | | | (5 min) | |
| Vérifications | | | (10 min) | |

## Résultats

- RPO effectif : <durée entre l'instantané et l'incident> ; changements perdus : `etat=apres-instantane` (attendu).
- RTO : <durée de l'indisponibilité de l'API> pour l'API, <durée totale> jusqu'au service rétabli.
- Révision après restauration : <R + 1 000 000 000 + …> (`endpoint status`).
- `wb-essais` : revenu ; pods recréés ; données PostgreSQL et Valkey **perdues** (volumes jetables, attendu au M14 ; le M16 traitera la sauvegarde des volumes).
- Écarts au runbook : <…>.

## Suites

- <ex. ajouter au script le contrôle de la clé de chiffrement des Secrets en vigueur>
