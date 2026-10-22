# M22-E15 — Requêtes de comparaison Loki / OpenSearch

Même période (la **dernière heure complète** de collecte commune), mêmes journaux (pods des espaces `mediagenda-*`). Lance chaque requête **trois fois** et note le temps de la deuxième et de la troisième (la première remplit les caches des deux côtés). Note aussi le nombre de résultats : s'il diffère, cherche pourquoi avant de comparer les temps.

Variables :

```
admin@adm01:~$ export LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100
admin@adm01:~$ DEBUT=$(date -u -d '-1 hour' +%Y-%m-%dT%H:00:00Z); FIN=$(date -u +%Y-%m-%dT%H:00:00Z)
```

Côté OpenSearch, depuis `adm01` par `kubectl port-forward -n opensearch-essai svc/opensearch-cluster-master 9200:9200` (dans un second terminal), avec le compte `admin` de l'essai et la CA de l'essai (`~/m22/e15/ca-essai.crt`). Le paramètre `?pretty` et le champ `took` (millisecondes) de la réponse suffisent.

| # | Recherche | Ce qu'elle mesure |
|---|---|---|
| R1 | Un mot **rare** : l'identifiant d'une requête précise (`request_id` relevé dans un journal de MédiAgenda de la période) | recherche « aiguille dans une botte de foin » |
| R2 | Un mot **fréquent** : `requête` (le message du journal d'accès de MédiAgenda) | coût d'un filtre peu sélectif |
| R3 | Un **champ** JSON : toutes les lignes dont `code` vaut `500` | analyse de champ (Loki) contre champ indexé (OpenSearch) |
| R4 | Une **agrégation** : nombre de lignes par `code` HTTP sur l'heure, par tranches de 5 min | métriques tirées des journaux |
| R5 | Une **expression régulière** : chemins `/api/v1/rendez-vous/[0-9]+` | coût d'une regex sur le texte |

## Modèles côté Loki (locataire `mediagenda`)

```
admin@adm01:~$ logcli query --org-id=mediagenda --stats --quiet --from="$DEBUT" --to="$FIN" --limit=5000 \
    '{namespace=~"mediagenda-.+"} |= "<REQUEST_ID>"'
admin@adm01:~$ logcli query --org-id=mediagenda --stats --quiet --from="$DEBUT" --to="$FIN" --limit=5000 \
    '{namespace=~"mediagenda-.+"} | json | code = 500'
admin@adm01:~$ logcli query --org-id=mediagenda --stats --quiet --from="$DEBUT" --to="$FIN" --step=5m \
    'sum by (code) (count_over_time({namespace=~"mediagenda-.+"} |= "requête" | json [5m]))'
```

`<REQUEST_ID>` : une valeur relevée dans les journaux de la période. R2 et R5 s'écrivent de la même façon (filtre de ligne `|=` ou `|~`) : à toi de les écrire.

## Modèles côté OpenSearch (index `journaux-*`)

Le corps des requêtes dépend du mapping que Fluent Bit a produit (`GET journaux-*/_mapping`) : avec le filtre `kubernetes` et `Merge_Log On`, les champs JSON de MédiAgenda arrivent à la racine du document (`code`, `chemin`, `message`…), les métadonnées sous `kubernetes.*`.

```
admin@adm01:~$ curl -s --cacert ~/m22/e15/ca-essai.crt -u "admin:$OS_MDP" -H 'Content-Type: application/json' \
    'https://localhost:9200/journaux-*/_search?pretty' -d '{
      "size": 100,
      "query": {"bool": {"filter": [
        {"range": {"@timestamp": {"gte": "'"$DEBUT"'", "lt": "'"$FIN"'"}}},
        {"match_phrase": {"log": "<REQUEST_ID>"}}
      ]}}
    }'
```

R3 et R4 utilisent une requête `term` sur le champ `code` et une agrégation `date_histogram` (intervalle fixe de 5 min) imbriquant une agrégation `terms` sur `code`. R5 : requête `regexp` sur le champ texte qui porte le chemin — regarde si ce champ est de type `text` ou `keyword` dans le mapping et ce que cela change.

`<REQUEST_ID>` et `OS_MDP` sont à remplacer ; `OS_MDP` se lit dans Ansible Vault `critique`, jamais dans l'historique du shell (`read -rs OS_MDP`).

## À relever pour chaque requête

| # | Loki : temps (2e / 3e) | Loki : octets traités (`--stats`) | OpenSearch : `took` (2e / 3e) | Résultats identiques ? |
|---|---|---|---|---|
| R1 | | | | |
| R2 | | | | |
| R3 | | | | |
| R4 | | | | |
| R5 | | | | |
