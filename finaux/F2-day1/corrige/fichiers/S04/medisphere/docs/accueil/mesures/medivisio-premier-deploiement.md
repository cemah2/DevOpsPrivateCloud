# MédiVisio — délai jusqu'au premier déploiement (F2-S04, DEV-3204)

> Mesure de la solution de référence : les heures ci-dessous sont un **exemple** ; remplace-les par les tiennes (horodatages GitLab, Argo CD, journal du scaffolder). Mesuré du point de vue d'Inès Garnier : « je clique sur Créer » → « l'URL de dev répond ».

## Chronologie

| Heure | Étape | Qui | Source de l'horodatage |
|---|---|---|---|
| `<09:02>` | Modèle « Nouveau service » lancé (équipe medivisio, nom `consultation`, Python) | Inès | tâche du scaffolder (`/create/tasks/<id>`) |
| `<09:03>` | Projets `medivisio/consultation` et `medivisio/consultation-deploiement` créés ; MR de déclaration ouverte dans `medivisio/gitops` ; Component au catalogue | portail | événements des projets |
| `<09:04>` | Premier pipeline de `main` : **échec** à la signature (`ci-medivisio-consultation` inconnu du coffre) | CI | pipeline n° `<N>` |
| `<09:20>` | MR `services: [consultation]` sur `plateforme/equipes` (Inès) | Inès | MR `<!N>` |
| `<10:05>` | Relecture et fusion par la Plateforme ; propagation ; `tofu:apply:equipes` de `plateforme/secrets` | Plateforme | pipelines |
| `<10:18>` | Pipeline relancé : image construite, analysée, **signée** ; MR de promotion ouverte dans le dépôt de déploiement | CI | pipeline n° `<N+1>` |
| `<10:21>` | Secret `kv/medivisio/dev/consultation` écrit par Inès (`bao kv put`, OIDC) | Inès | audit OpenBao (Loki `audit`) |
| `<10:24>` | MR de promotion fusionnée ; MR de déclaration (`services/consultation.yaml`) fusionnée | Inès | MR |
| `<10:26>` | Application `medivisio-consultation-dev` créée par l'ApplicationSet, `Synced`, `Healthy` | Argo CD | historique de l'Application |
| `<10:27>` | `https://consultation-dev.apps.par1.medisphere.internal/sante` → 200 | — | `curl` |
| `<11:30>` | Variables `TECHDOCS_S3_*` posées sur le groupe medivisio ; documentation visible au portail | Plateforme | journal du groupe |

**Délai jusqu'au premier déploiement : `<1 h 25>`** (objectif de l'offre de service : ≤ 1 jour ouvré). Dont attente de la Plateforme : `<45 min>`. Temps d'Inès au clavier : `<≈ 25 min>`.

## Ce qui a demandé l'intervention de la Plateforme

| # | Friction | Cause | Attente | Correctif proposé |
|---|---|---|---|---|
| 1 | Signature refusée au premier pipeline | les rôles CI d'OpenBao sont par service (`services:` du fichier d'équipe) et le modèle ne le dit pas | `<45 min>` | le modèle affiche l'étape « déclarer le service dans plateforme/equipes » et ouvre lui-même cette MR (feuille de route, F2-S14) |
| 2 | Documentation absente du portail | identité d'écriture TechDocs posée à la main par groupe | `<1 h>` (hors chemin critique) | variables de groupe rendues par `plateforme/equipes` (jeton S3 par équipe) |
| 3 | (aucune) espace, quotas, coffre, AppProject, route d'alertes | — | 0 | déjà livrés par S02 |

## Ce qui a bien marché

- Aucun ticket pour l'espace, les quotas, le projet Argo CD, le coffre, les identifiants de dépôt.
- La MR de déclaration du service est fusionnée par l'équipe elle-même.

## Pour comparer

Le dernier service créé avant la plateforme développeurs (vignettes de MédiDoc, M28) : six tickets, dix jours calendaires.
