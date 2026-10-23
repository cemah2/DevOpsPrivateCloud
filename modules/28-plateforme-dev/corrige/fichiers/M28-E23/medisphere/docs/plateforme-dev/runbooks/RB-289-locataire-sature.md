# RB-289 — Un locataire sature le cluster

> Rédigé en M28-E23. Propriétaire : équipe Plateforme.

## Constat (10 min)
- `kubectl top nodes` ; `kubectl top pods -A --sort-by=cpu | head` ; `kubectl top pods -A --sort-by=memory | head`.
- Tableau « Capacité et locataires » : quel locataire a bougé ?
- Conteneurs tués ou redémarrés (`kubectl get pods -A | grep -v ' 0 '`, `lastState.terminated.reason`), événements `Evicted`, pods `Pending` par classe de priorité.
- Sur le nœud chaud : `kubectl describe node` — ce qui est **réservé** (`Allocated resources`) contre ce qui est **consommé** (`kubectl top node`). Un grand écart = une charge qui déclare peu ou rien.

## Endiguer
Le plus petit geste réversible, **noté** dans le journal d'incident, décidé avec l'équipe ou Karim : `kubectl -n <ns> scale deploy/<charge> --replicas=0`. Ce n'est pas la correction.

## Cause
Pour la charge fautive : `spec.priorityClassName`, `spec.priority`, `resources` **effectives** (une request à `0` est « déclarée » mais ne réserve rien) ; pour son espace : `LimitRange` (valeurs par défaut **et** minimum), `ResourceQuota`, historique de `plateforme/k8s/espaces/<espace>/` ; pour son locataire : classes autorisées, budget global ; politiques d'admission (`exiger-limites` : présence ou valeur ?). Qui l'a lancée, par quel chemin (Git ou à la main : annotation de suivi d'Argo CD, `managedFields`) ?

## Correction durable (par MR)
- `plateforme/k8s/espaces/<espace>/` : `LimitRange` (avec un `min` par conteneur) et quota rétablis, `task espaces`.
- `plateforme/politiques` : requests strictement positives exigées dans les espaces des équipes.
- `plateforme/k8s/locataires/<locataire>.yaml` : classes autorisées sans `medisphere-critique` hors production ; budget global.
- Dépôt de l'équipe : requests et limites justes, classe `medisphere-lot` pour un traitement par lots.

## Retour à la normale
Charge relancée dans son cadre ; plus de pods tués ni en attente anormalement ; recette dans son SLO. Post-mortem (`docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-<n>.md`).
