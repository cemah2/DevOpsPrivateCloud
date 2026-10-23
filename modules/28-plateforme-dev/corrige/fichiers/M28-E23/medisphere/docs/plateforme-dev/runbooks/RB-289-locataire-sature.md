# RB-289 — Un locataire sature le cluster

> Rédigé en M28-E23. Propriétaire : équipe Plateforme.

## Constat (10 min)
- `kubectl top nodes` ; `kubectl top pods -A --sort-by=cpu | head` ; `kubectl top pods -A --sort-by=memory | head`.
- Tableau « Capacité et locataires » : quel locataire a bougé ?
- `kubectl get events -A --field-selector reason=OOMKilling` / `Evicted` ; pods `Pending` par classe de priorité.

## Endiguer
Le plus petit geste réversible, **noté** dans le journal d'incident, décidé avec l'équipe ou Karim : `kubectl -n <ns> scale deploy/<charge> --replicas=0`. Ce n'est pas la correction.

## Cause
Pour la charge fautive : `spec.priorityClassName`, `spec.priority`, `resources` **effectives** ; pour son espace : `LimitRange`, `ResourceQuota` ; pour son locataire : classes autorisées, budget global. Qui l'a lancée, par quel chemin (Git ou à la main) ?

## Correction durable (par MR)
- `plateforme/k8s/espaces/<espace>/` : `LimitRange` et quota rétablis.
- `plateforme/k8s/locataires/<locataire>.yaml` : classes autorisées sans `medisphere-critique` hors production ; budget global.
- Dépôt de l'équipe : requests et limites justes, classe `medisphere-lot` pour un traitement par lots.

## Retour à la normale
Charge relancée dans son cadre ; plus de pods tués ni en attente anormalement ; recette dans son SLO. Post-mortem (`docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-<n>.md`).
