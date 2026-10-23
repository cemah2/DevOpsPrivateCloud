# MédiVisio — consultation

Service de téléconsultation de l'équipe MédiVisio (Inès Garnier, responsable). Créé par le modèle « Nouveau service » v2 du portail (F2-S04).

| | |
|---|---|
| Code | `medivisio/consultation` (Python, bibliothèque standard) ; image `medisphere/medivisio-consultation`, signée |
| Déploiement | `medivisio/consultation-deploiement` (Kustomize, overlays `dev`, `recette`, `prod`) ; Applications `medivisio-consultation-<env>` (ApplicationSet `medivisio`) |
| Adresses | `https://consultation-dev.apps.par1.medisphere.internal`, `…-recette…`, `https://consultation.apps.par1.medisphere.internal` |
| Points d'accès | `GET /sante`, `GET /pret`, `GET /api/v1/disponibilites`, `POST /api/v1/salles`, `GET /metrics` |
| Secret | `kv/medivisio/<env>/consultation` (champ `cle_salles`), livré par `ExternalSecret` |
| Contact | `medivisio@medisphere.internal` |

Les données du lab sont **factices** : ni nom, ni numéro de sécurité sociale, ni donnée de santé.
