# Pyrra ou Sloth : comparaison sur `mediagenda-disponibilite`

| | |
|---|---|
| Ticket | PLAT-2227 (M21-E27) |
| Versions | Pyrra 0.10.2 (opérateur dans `k8s-par1`), Sloth 0.16.0 (CLI, essai sur `adm01`) |
| Entrées | `slo/mediagenda-disponibilite.yaml` (Pyrra), `slo/sloth/mediagenda-disponibilite.sloth.yaml` (Sloth) |
| Décision | **Pyrra** reste l'outil ; Sloth sert de contre-vérification ponctuelle |

## 1. Ce que chacun produit (même objectif : 99,5 % sur 28 jours)

| | Pyrra 0.10 (`pyrra generate`) | Sloth 0.16 (`sloth generate --default-slo-period=28d`) |
|---|---|---|
| Règles d'enregistrement | 1 par fenêtre (`mediagenda_http_requests:burnrate5m` … `burnrate4d`) + `increase4w` ; option : règles génériques `pyrra_*` | 1 par fenêtre (`slo:sli_error:ratio_rate5m` … `ratio_rate3d`), `slo:sli_error:ratio_rate4w` (moyenne des ratios de 5 min), méta-règles `slo:objective:ratio`, `slo:error_budget:ratio`, `slo:time_period:days`, `slo:current_burn_rate:ratio`, `slo:period_burn_rate:ratio`, `slo:period_error_budget_remaining:ratio`, `sloth_slo_info` |
| Nombre de règles (mesuré) | 13 : 8 enregistrements, 4 alertes de consommation, 1 d'absence (18 avec `--generic-rules`, comme dans le cluster) | 17 : 15 enregistrements, 2 alertes |
| Alertes de consommation | **4** alertes `ErrorBudgetBurn` : (5 min, 1 h) ×14 ; (30 min, 6 h) ×7 ; (2 h, 1 j) ×2 ; (6 h, 4 j) ×1 | **2** alertes : « page » = (5 min, 1 h) ×13,44 **ou** (30 min, 6 h) ×5,6 ; « ticket » = (2 h, 1 j) ×2,8 **ou** (6 h, 3 j) ×0,93 |
| `for:` | oui (2 min, 15 min, 1 h, 3 h) | non : la fenêtre longue fait office de filtre |
| Facteurs | arrondis (14, 7, 2, 1) | exacts pour 28 j : 2 % du budget en 1 h → 0,02 × 672 h / 1 h = 13,44 ; 5 % en 6 h → 5,6 ; 10 % en 1 j → 2,8 ; 10 % en 3 j → 0,93 |
| Alerte « plus de mesure » | `SLOMetricAbsent` | aucune (à écrire soi-même) |
| Étiquettes de routage | `severity` seulement (valeurs libres par fenêtre) + étiquettes `pyrra.dev/*` recopiées | étiquettes libres par alerte (`page_alert.labels`, `ticket_alert.labels`) : `gravite` directement |
| Interface | oui (`pyrra-api`) : budget restant, graphiques par fenêtre | non (tableaux Grafana fournis par le projet) |
| Fonctionnement | opérateur : un CR `ServiceLevelObjective` → une `PrometheusRule` | générateur : on commite le résultat (ou on le génère en CI) |
| Vie du projet (oct. 2026) | très actif (0.10.2) | ralenti (dernière version avril 2026) |

## 2. Différences qui comptent pour nous

1. **Sloth route mieux, Pyrra montre mieux.** Sloth pose `gravite` sans réétiquetage ; Pyrra oblige à recopier `severity` (règle d'`alert_relabel_configs`, `kps/values.yaml`). En échange, Pyrra donne à l'équipe MédiAgenda une page lisible du budget restant, et à l'astreinte un lien direct (`pyrra_url`).
2. **4 alertes contre 2.** Les quatre niveaux de Pyrra correspondent exactement aux quatre lignes de la politique (deux critiques, deux avertissements) ; les deux de Sloth regroupent par « page » / « ticket ». Les deux respectent la méthode du *SRE Workbook* (multi-fenêtres, multi-facteurs).
3. **Facteurs** : Pyrra arrondit (14 au lieu de 13,44) et ajoute un `for` ; écarts négligeables au regard du bruit d'un service peu chargé.
4. **Ratios** : la fenêtre de 28 jours de Sloth (`slo:sli_error:ratio_rate4w`) est une **moyenne de ratios de 5 min**, pas un ratio de comptes : un creux de trafic pèse autant qu'une heure de pointe. Pyrra calcule un ratio de comptes (`increase4w`), plus juste.
5. **Rétention** : les deux évaluent des fenêtres de 28 jours dans **Prometheus** : même limite (rétention locale de 15 jours), même remède (voir `dimensionnement.md`).

## 3. Décision

Pyrra : opérateur déjà en place, interface demandée par Julien Petit, quatre niveaux alignés sur la politique de budget. Sloth reste utile en revue : générer ses règles sur un nouvel objectif et comparer les seuils (un écart important signale une erreur de saisie dans le SLO).
