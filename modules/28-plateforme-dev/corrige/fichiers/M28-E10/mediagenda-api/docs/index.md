# API MédiAgenda

API de prise de rendez-vous en ligne de l'équipe MédiAgenda (Julien Petit). Python 3.13, FastAPI, PostgreSQL (CloudNativePG, pooler PgBouncer), Valkey (cache), RabbitMQ (publication des demandes de notification).

## Environnements

| Environnement | Adresse | Livraison |
|---|---|---|
| dev | `https://mediagenda-dev.apps.par1.medisphere.internal` | automatique (Argo CD) après la MR de promotion |
| recette | `https://mediagenda-recette.apps.par1.medisphere.internal` | MR approuvée, canary |
| prod | `https://mediagenda.apps.par1.medisphere.internal` | MR approuvée, synchronisation manuelle, canary avec promotion humaine |

## Points d'accès

Le contrat complet est l'entité API `mediagenda-api` du portail (OpenAPI). Principaux : `GET /sante` (vivacité), `GET /pret` (disponibilité), `GET /metrics`, `GET|POST /api/v1/rendez-vous`, `GET /api/v1/creneaux`.

## Exploitation

- Autoscaling : HPA `mediagenda` sur le CPU (recette 2 → 4, prod 3 → 6) ; voir `docs/plateforme-dev/autoscaling.md` de `plateforme/medisphere`.
- Tableaux de bord : Grafana, dossier MédiAgenda ; journaux : Loki (locataire `mediagenda`) ; traces : Tempo.
- Aucune donnée de patient dans les journaux, les traces ni cette documentation.
