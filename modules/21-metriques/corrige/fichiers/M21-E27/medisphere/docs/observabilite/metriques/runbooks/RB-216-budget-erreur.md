# RB-216 — Un budget d'erreur brûle trop vite (`ErrorBudgetBurn`, `SLOMetricAbsent`)

| | |
|---|---|
| Alertes | `ErrorBudgetBurn` (Pyrra, étiquettes `slo`, `short`, `long`, `exhaustion`, `severity`/`gravite`, `equipe`) ; `SLOMetricAbsent` |
| Gravité | selon la fenêtre (voir [politique de budget](../politique-budget-erreur.md) §2) |
| Équipe | celle de l'étiquette `equipe` (mediagenda, medidoc) ; la plateforme si la cause est d'infrastructure |
| Ticket d'origine | PLAT-2227 (M21-E27) |

## 1. Lire l'alerte

- `slo` : quel objectif (`mediagenda-disponibilite`, `mediagenda-latence`, `medidoc-disponibilite`).
- `short` / `long` : les deux fenêtres au-dessus du seuil. (5m, 1h) = ça brûle **maintenant** et fort ; (6h, 4d) = érosion lente.
- `exhaustion` : délai avant épuisement du budget **à ce rythme**. C'est l'urgence réelle.
- annotation `pyrra_url` : l'objectif dans l'interface (budget restant, graphique de chaque fenêtre).

## 2. Confirmer et localiser (5 minutes)

Dans Grafana (source « prometheus », Thanos Query) ou sur 10.10.41.60 :

```promql
# Taux d'erreurs actuel, par route : laquelle consomme ?
sum by (route, code) (rate(mediagenda_http_requests_total{namespace="mediagenda-prod", code=~"5.."}[5m]))
  / ignoring(code) group_left sum by (route) (rate(mediagenda_http_requests_total{namespace="mediagenda-prod"}[5m]))

# Latence : part des requêtes au-delà de 250 ms, par route
1 - sum by (route) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-prod", le="0.25"}[5m]))
  / sum by (route) (rate(mediagenda_http_request_duration_seconds_count{namespace="mediagenda-prod"}[5m]))

# Budget restant selon Pyrra (règles génériques)
pyrra_availability{slo="mediagenda-disponibilite"}
```

Puis la question qui oriente tout : **qu'est-ce qui a changé ?**
- un déploiement (Argo CD : historique de `mediagenda-prod`, Rollout `mediagenda` : analyse en cours ?) ;
- une dépendance (PostgreSQL `mediagenda-db`, Valkey, RGW pour MédiDoc) : tableaux USE/RED (M21-E19) ;
- la plateforme (nœud, Cilium, Gateway) : alertes plateforme simultanées ? (une inhibition peut les masquer : `amtool alert query` sur 10.10.41.61).

## 3. Agir

| Situation | Action |
|---|---|
| Déploiement récent en cause | retour arrière par `git revert` dans `mediagenda/deploiement` (M20-E14), **pas** de modification à la main |
| Dépendance en cause | runbook de la dépendance (RB-16x pour CNPG, RB-21x pour l'infrastructure) |
| Pas de cause trouvée en 30 min et `exhaustion` < 2 j | escalade (§5) |
| `SLOMetricAbsent` | on ne mesure plus : l'API de prod tourne-t-elle (`up{namespace="mediagenda-prod"}`) ? Sa cible est-elle collectée (RB-21x « cible disparue ») ? Une absence de mesure n'est **pas** une absence d'erreurs |

Ne **jamais** « réparer » l'alerte en relevant l'objectif ou en élargissant les routes exclues pendant l'incident : un changement de SLO passe par une MR relue et la revue de la politique.

## 4. Après

- Noter dans le ticket la part de budget consommée (`pyrra_availability` avant/après, ou l'interface).
- Plus de 20 % d'un budget en un incident : post-mortem (`docs/kubernetes/post-mortems/`), politique §3.
- Fausse alerte (trafic trop faible, route mal exclue) : MR sur `slo/` + test dans `tests/slo-mediagenda.test.yaml`.

## 5. Escalade

Julien Petit (MédiAgenda) pour toute décision de gel ou de retour arrière applicatif ; Karim Benali si la plateforme est en cause ; Claire Morel si le budget est épuisé (politique §3).
