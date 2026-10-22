# Mise en production chronométrée (M20-E34) — CHG-2134

| | |
|---|---|
| T0 | <2026-10-2xT09:02:11Z> |
| T1 | <2026-10-2xT09:58:40Z> |
| Version livrée | v1.4.0, `sha256:<DIGEST>` |
| Exécutant / validation | <MOI> / Claire Morel |
| Score `lab/bin/check 20 34` | <…> / 100 |

## Chronologie

| Heure (UTC) | Étape | Remarque |
|---|---|---|
| T0 + 0:00 | ouverture du sujet, `~/m20/e34/T0` | |
| T0 + 0:06 | journal : état de départ, fenêtres, plan de retour arrière | fenêtre deny inactive |
| T0 + 0:11 | MR de promotion !<N> (`outils/promouvoir.sh recette prod`), titre cite CHG-2134 | pipeline de validation : 2 min 40 |
| T0 + 0:16 | fusion par Karim (Maintainer) | |
| T0 + 0:18 | `argocd app diff mediagenda-prod` relu (image, ConfigMap livraison, Job de migration) | |
| T0 + 0:19 | `argocd app sync mediagenda-prod` (compte nominatif) | hook `mediagenda-migrate` (phase Sync, vague -1) réussi en 25 s |
| T0 + 0:20 | marche 10 % ; analyse `fumee-mediagenda` réussie (Job, 18 s) ; `pret-mediagenda` en fond | |
| T0 + 0:23 → 0:29 | marches 25 %, 50 % (pauses de 2 min) | aucun 5xx (boucle `curl` depuis adm01) |
| T0 + 0:30 | pause finale : contrôles (journaux, `kubectl argo rollouts get`, page publique) | |
| T0 + 0:33 | `kubectl argo rollouts promote mediagenda -n mediagenda-prod` | |
| T0 + 0:36 | Rollout Healthy, poids 100/0, Application Synced/Healthy | |
| T0 + 0:37 | message « [Argo CD] mediagenda-prod déployée » reçu (plateforme@) | |
| T0 + 0:52 | compte rendu poussé | |

## Incidents et hésitations

- <ex. 4 min perdues : outil de promotion lancé dans le mauvais sens (prod → recette) ; MR fermée, relancée.>
- <ex. hésitation sur la pause finale : relu `promote` vs `promote --full` (le second saute les marches restantes).>

## Ce que je retravaille

- <ex. une fiche réflexe « mise en production » : 6 commandes, dans l'ordre.>
- <ex. surveiller l'analyse de fond pendant les pauses (`kubectl get analysisrun -n mediagenda-prod -w`).>

## Feuille de temps

(recopie de celle du sujet)
