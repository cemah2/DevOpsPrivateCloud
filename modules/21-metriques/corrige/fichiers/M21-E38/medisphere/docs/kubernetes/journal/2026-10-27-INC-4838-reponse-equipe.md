# INC-4838 — Prometheus déborde : journal et réponse à l'équipe MédiAgenda

## Journal (extrait)

| Heure | Hypothèse / action | Commande | Résultat | Conclusion |
|---|---|---|---|---|
| 09:41 | Quelque chose crée des séries | `max by (pod) (prometheus_tsdb_head_series{namespace="supervision"})` | 318 442 (121 876 il y a 1 h) | +196 000 en une heure |
| 09:43 | Création continue ou ponctuelle ? | `sum by (pod) (rate(prometheus_tsdb_head_series_created_total[5m]))` | 333 séries/s | création continue (*churn*) |
| 09:45 | Quelle cible ? | `topk(3, scrape_series_added)` | `temoin-metriques` (wb-pannes), 2 500 par collecte, 2 pods | cible désignée |
| 09:47 | Quelle métrique, quelle étiquette ? | *TSDB Status* de `prometheus-kps-0` (port-forward) | `mediagenda_rapports_requetes_total`, étiquette `requete_id` : 98 000 valeurs | identifiant de requête en étiquette |
| 09:52 | Contenir | ServiceMonitor : `metricRelabelings` (`drop` de la métrique), `sampleLimit: 500` | `scrape_samples_post_metric_relabeling` = 15, `scrape_series_added` = 0 | plus de création |
| 10:30 | Suivi | `prometheus_tsdb_head_series` | stable à 320 000 | redescendra à la prochaine compaction de la tête (≤ 3 h) |
| 12:05 | Suivi | idem | 124 000 | revenu à la normale ; rien n'a été supprimé |

## Réponse à l'équipe MédiAgenda (envoyée à Julien Petit, copie Karim Benali)

> Bonjour Julien,
>
> Ce matin, le module de rapports branché sur l'application de recette (`wb-pannes`) exposait le compteur `mediagenda_rapports_requetes_total` avec une étiquette `requete_id` : une valeur nouvelle par requête. Pour Prometheus, chaque valeur d'étiquette est une **série** à part, avec son index et sa mémoire : 2 500 séries nouvelles toutes les 15 secondes et par pod, soit environ 200 000 en un quart d'heure, et sans limite si l'application n'en avait pas eu. La mémoire des deux Prometheus a augmenté de plusieurs centaines de mégaoctets, et chaque série serait restée deux ans dans le stockage long.
>
> Nous avons arrêté l'ingestion de cette métrique à 9 h 52 (filtre sur le ServiceMonitor) et posé une limite d'échantillons sur la cible. Rien d'autre n'est perdu ; la métrique n'est simplement plus collectée.
>
> Pour la réactiver, il faut l'exposer **agrégée** : `mediagenda_rapports_requetes_total{type="mensuel|hebdomadaire", code="200|4xx|5xx"}` (quelques séries), et, si la durée vous intéresse, un histogramme `mediagenda_rapports_duree_secondes` avec les mêmes étiquettes. L'identifiant de requête a sa place dans les **journaux** (Loki, module 22) et les **traces** (Tempo, module 23), où l'on cherche une requête précise ; pas dans les métriques, où l'on compte.
>
> La règle de la plateforme, ajoutée à la politique de supervision : *une étiquette, c'est un ensemble de valeurs petit, fini et connu à l'avance*. Jamais d'identifiant (requête, rendez-vous, patient, session), jamais de chemin brut (utiliser le gabarit de route, `/api/v1/rendezvous/{id}`), jamais de donnée personnelle (adresse de courriel, nom). Une MR qui ajoute une métrique indique son nombre de séries prévu ; on la relit ensemble.
>
> Variante « adresse de courriel » : en plus, Sophie Laurent (RSSI) est prévenue ; ces données personnelles sont dans les blocs de Prometheus et dans le compartiment Thanos ; leur suppression éventuelle est sa décision (procédure : question 20 de M21-E45).
>
> Bonne journée,
> L'équipe Plateforme
