# charge/resultats/ — résumés des tests de charge (M29-E06)

Un fichier par campagne, écrit par `handleSummary` de `charge/parcours-recette.js` (k6 lancé **depuis la racine du dépôt**, sinon le chemin relatif part ailleurs) :

| Fichier | Contenu |
|---|---|
| `AAAA-MM-JJ-<variante>.json` | `{ "resume": {…}, "k6": {…} }` : le résumé lisible (cible, paramètres, seuils franchis, part sous 250 ms, p95, p99, erreurs, débit, itérations perdues) puis le résumé complet de k6 |
| `AAAA-MM-JJ-analyse.md` | l'analyse de la campagne (une page) |

Les résumés sont **versionnés** : ce sont les références de la non-régression du palier 3 (M29-E14). Ils ne contiennent aucune donnée de patient (données factices `dr-k6-*`), seulement des mesures. Un résumé dont `resume.cible` n'est pas la recette n'a rien à faire ici.

## Plan de l'analyse attendue

1. **Conditions** : date, heure de début et de fin (UTC), version de MédiAgenda (étiquette d'image du Rollout), nombre de réplicas au départ, paramètres (`LECTURE_RPS`, `RESERVATION_RPS`, `DUREE`, `VARIETE`).
2. **Résultat côté client (k6)** : seuils respectés ou non, part sous 250 ms, p95/p99 par parcours, erreurs, itérations perdues.
3. **Résultat côté serveur (Prometheus, même fenêtre)** : part sous 250 ms calculée sur `mediagenda_http_request_duration_seconds_bucket{namespace="mediagenda-recette"}`, débit servi, erreurs 5xx ; écart avec k6 et son explication (réseau, passerelle, TLS, file d'attente côté client).
4. **Cache** : taux de succès Valkey (`mediagenda_cache_total` par résultat) en cache froid (`VARIETE=200`) et en cache chaud (`VARIETE=1`), effet sur la latence des lectures.
5. **HPA** : réplicas au cours du test (`kube_horizontalpodautoscaler_status_desired_replicas`), délai de réaction, effet visible (ou non) sur la latence.
6. **Conclusion et suite** : la recette tient-elle le débit visé avec le SLO ? Quelle limite a été vue en premier ? Quelle campagne suivante ?
