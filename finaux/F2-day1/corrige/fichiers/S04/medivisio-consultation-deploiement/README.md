# medivisio/consultation-deploiement

Déploiement Kustomize de `medivisio/consultation` (modèle « Nouveau service » v2, F2-S04). Livré par l'ApplicationSet `medivisio` d'Argo CD (généré par `plateforme/equipes`) : une Application `medivisio-consultation-<env>` par environnement, déclarée par `services/consultation.yaml` du projet `medivisio/gitops`.

| Dossier | Espace | Synchronisation | Image |
|---|---|---|---|
| `overlays/dev` | `medivisio-dev` | automatique | posée par la MR de promotion de la CI (par empreinte) |
| `overlays/recette` | `medivisio-recette` | automatique | MR de l'équipe : **même empreinte** que celle validée en dev |
| `overlays/prod` | `medivisio-prod` | **manuelle**, hors du vendredi 16 h → lundi 8 h | MR de l'équipe : même empreinte que la recette |

Interdits (AppProject `medivisio`) : `ResourceQuota`, `LimitRange`, `SecretStore`, `AlertmanagerConfig`, `RoleBinding`, tout objet de cluster. Secrets : `ExternalSecret` vers le `SecretStore` `openbao` de l'espace (lecture de `kv/medivisio/<env>/*` seulement).
