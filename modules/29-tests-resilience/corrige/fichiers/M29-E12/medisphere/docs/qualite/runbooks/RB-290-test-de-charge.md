# RB-290 — Lancer un test de charge sans nuire

| | |
|---|---|
| Déclencheurs | Demande de mesure de MédiAgenda (ticket DEV-/PLAT-), avant une mise en production, analyse d'une régression |
| Durée | 30 min (préparation 10 min, test 10 à 20 min, après 5 min) |
| Références | Stratégie de tests § 3, scénarios `plateforme/resilience/charge/`, SLO `mediagenda-latence` et `mediagenda-disponibilite` (M21), RB-216 (budget d'erreur) |

**Règle d'or : on ne charge JAMAIS la production.** Les scripts refusent toute cible autre que la recette, la dev ou `127.0.0.1` ; on ne contourne pas ce garde-fou.

## 1. Avant

1. **Ticket et annonce** : un ticket qui dit qui, quoi, quand, pourquoi ; message à Julien Petit (MédiAgenda) et à Nadia Roussel (astreinte : des alertes de recette peuvent arriver). Pas pendant une démonstration ou une recette fonctionnelle en cours.
2. **Recette saine** : `curl -fsS https://mediagenda-recette.apps.par1.medisphere.internal/pret` ; Argo CD `mediagenda-recette` synchronisée et saine ; pas d'expérience de chaos en cours (`kubectl -n chaos-experiences get podchaos,networkchaos,stresschaos,schedules,workflows`).
3. **Capacité du générateur** : `adm01` a 2 vCPU. Au-delà d'environ 100 requêtes/s ou si k6 signale `dropped_iterations`, le test mesure `adm01`, pas MédiAgenda : passer par k6-operator (palier 3).
4. **Données** : uniquement les données factices des scripts (praticiens `dr-k6-*`, patients « Patient Charge … », motif « test de charge k6 (M29) ») ; aucun fichier de données réelles dans `plateforme/resilience`.
5. **Mesures prêtes** : tableau de bord MédiAgenda (Grafana) ouvert sur la recette ; requêtes de corrélation du § 3 dans un onglet.

## 2. Pendant

```
admin@adm01:~/src/resilience$ k6 inspect charge/parcours-recette.js       # options, scénarios : relire avant
admin@adm01:~/src/resilience$ k6 run -e RESULTAT=charge/resultats/$(date +%F)-parcours-recette.json charge/parcours-recette.js
```

- **Arrêt** : Ctrl-C (k6 arrête proprement, `teardown` nettoie les rendez-vous factices). Le test s'arrête **de lui-même** si plus de 5 % des requêtes échouent (seuil `abortOnFail`).
- **Arrêter tout de suite si** : erreurs 5xx en hausse continue, `mediagenda-db` ou le pooler en difficulté (connexions, latence), alerte d'une autre application, demande de l'équipe MédiAgenda.

## 3. Lire

| Côté | Requête ou valeur | Lecture |
|---|---|---|
| k6 | `sous_250ms`, p95, p99, `http_req_failed`, `dropped_iterations` | seuils = SLO ; une itération perdue = le débit demandé n'a pas été tenu |
| Serveur | `histogram_quantile(0.95, sum by (le) (rate(mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette", route!~"/sante\|/pret\|/metrics"}[1m])))` | latence vue par l'API ; l'écart avec k6 = réseau, Gateway, TLS |
| Erreurs serveur | `sum by (route, code) (rate(mediagenda_http_requests_total{namespace="mediagenda-recette", code=~"5.."}[1m]))` | ce que le SLO de disponibilité compterait |
| Cache | `sum(rate(mediagenda_cache_total{namespace="mediagenda-recette", resultat="hit"}[1m])) / sum(rate(mediagenda_cache_total{namespace="mediagenda-recette"}[1m]))` | taux de succès du cache Valkey |
| Mise à l'échelle | `kube_horizontalpodautoscaler_status_current_replicas{namespace="mediagenda-recette"}` | réplicas ajoutés par l'HPA pendant la charge |

## 4. Après

1. Vérifier qu'aucun rendez-vous factice ne reste : `curl -s …/api/v1/rendez-vous?limite=1000 | jq '[.[] | select(.praticien | startswith("dr-k6-"))] | length'` → `0`.
2. Commit du résumé JSON dans `charge/resultats/` (nom daté), avec une ligne dans le ticket : débit, p95, p99, erreurs, verdict des seuils, version de MédiAgenda mesurée.
3. Si un seuil est franchi : ticket DEV- à l'équipe MédiAgenda avec les deux côtés (k6 et serveur) ; pas de conclusion sur une seule exécution.
