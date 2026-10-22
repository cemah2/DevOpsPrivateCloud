# M25-E12 — Ce que le chart d'ESO 2.13.0 donne au contrôleur (relevé sur « helm template »)

- `secrets` : `get, list, watch, create, update, delete, patch` **dans tout le cluster** (ClusterRole `external-secrets-controller`). ESO peut lire et réécrire n'importe quel Secret : c'est son métier, et la raison pour laquelle son espace, ses images et sa version sont surveillés comme ceux d'Argo CD.
- `serviceaccounts/token` : `create` (jetons projetés des comptes référencés par les magasins) ; `serviceaccounts`, `namespaces` : lecture.
- Ses propres objets (`external-secrets.io`, `generators.external-secrets.io`) et les `events`.
- Avec `systemAuthDelegator: true` : `system:auth-delegator` (TokenReview, SubjectAccessReview).
- Le webhook et le cert-controller : leurs Secrets de certificat, les `validatingwebhookconfigurations`, les CRD (mise à jour du `caBundle` de conversion).

Mode « portée réduite » (`scopedNamespace`, `scopedRBAC`) : possible pour un opérateur par espace, écarté (un seul opérateur pour le cluster).
