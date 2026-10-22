# ~/m20-e34/journal.md — journal de changement (M20-E34), exemple de référence

CHG-2134 — mise en production de MédiAgenda v1.4.0
Digest livré : sha256:<DIGEST-DE-LA-RECETTE>   (overlays/recette/kustomization.yaml, main)

## État de départ (T0 + 3 min)
- mediagenda-prod : Synced / Healthy, révision <SHA-COURT>, image mediagenda-api@sha256:<DIGEST-PROD-ACTUEL> (v1.3.2)
- Rollout mediagenda (prod) : Healthy, stable = <HASH>, aucune analyse en cours
- Fenêtres (argocd proj windows list mediagenda) : deny vendredi 16:00 + 64 h, Inactive → la synchronisation est permise

## Plan de retour arrière
1. Canary pas à 100 % : `kubectl argo rollouts abort mediagenda -n mediagenda-prod` (trafic rendu au stable), puis MR de revert.
2. Canary promu : `git revert` de la MR de promotion, MR, fusion, synchronisation manuelle (rollbackWindow : 2 révisions, pas de canary).
3. Dans tous les cas : ticket INC si des utilisateurs ont été touchés.

## Diff montré par Argo CD avant synchronisation (tâche 3)
- Deployment/mediagenda : image (digest) ; ConfigMap livraison (version) ; Job mediagenda-migrate (crochet PreSync, nouvelle image)
