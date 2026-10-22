# Objectifs de niveau de service (SLO)

| | |
|---|---|
| Ticket | PLAT-2226 (M21-E26), PLAT-2227 (M21-E27) |
| Outil | Pyrra 0.10.2 (`plateforme/observabilite`, `pyrra/` et `slo/`), interface `https://slo.apps.par1.medisphere.internal` |
| Politique | [`politique-budget-erreur.md`](politique-budget-erreur.md) |

## Définitions

| SLO | Service mesuré | SLI (bon événement / événement valide) | Objectif | Fenêtre | Budget |
|---|---|---|---|---|---|
| `mediagenda-disponibilite` | API MédiAgenda, `mediagenda-prod` | requêtes sans code 5xx / requêtes hors `/sante`, `/pret`, `/metrics` | 99,5 % | 28 j glissants | 0,5 % des requêtes (≈ 3 h 22 min d'indisponibilité totale) |
| `mediagenda-latence` | API MédiAgenda, `mediagenda-prod` | requêtes servies en moins de **250 ms** / mêmes requêtes | 95 % | 28 j | 5 % des requêtes |
| `medidoc-disponibilite` | MédiDoc, `medidoc-recette` | requêtes sans code 5xx / requêtes hors sondes et `/metrics` | 99 % | 28 j | 1 % des requêtes |

## Ce que ces SLO ne disent pas

- **Mesure côté serveur** : une requête qui n'atteint pas l'API (Gateway, DNS, réseau du centre de santé) n'est pas comptée. La sonde blackbox de `mon01` (M21-E11) couvre le point de vue « de l'extérieur » ; un SLI côté Gateway (métriques d'Envoy) serait le pas suivant.
- **Latence : 250 ms au lieu de 300 ms** : l'histogramme de MédiAgenda n'a pas de seau `le="0.3"` (seaux par défaut du client Python). Demande DEV-2226 à l'équipe MédiAgenda : ajouter le seau, puis passer l'objectif à 300 ms.
- **Peu de trafic, gros pourcentages** : la nuit, une erreur sur dix requêtes fait 10 % d'erreurs. Les alertes multi-fenêtres (M21-E27) amortissent ; l'objectif compte des requêtes, pas des minutes.
- **Fenêtre de 28 jours, rétention locale de 15 jours** : la règle d'enregistrement `…:increase4w` (base de la disponibilité et du budget restant affichés par Pyrra) est évaluée par **Prometheus**, sur sa base locale. Tant que celle-ci garde 15 jours, « 28 jours » veut dire « 15 jours au plus ». Les alertes de consommation (fenêtres de 5 min à 4 j) ne sont pas touchées. Options étudiées en M21-E30 : rétention locale portée à 29 jours (capacité), ou évaluation de ces règles par un Thanos Ruler branché sur Thanos Query.
