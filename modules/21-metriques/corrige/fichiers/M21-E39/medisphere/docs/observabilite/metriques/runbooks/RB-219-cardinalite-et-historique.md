# RB-219 — Cardinalité et historique long

| | |
|---|---|
| **Alertes liées** | `PrometheusCreationSeriesRapide`, `CibleTropDeSeriesNouvelles`, `PrometheusSeriesProchesDuBudget` (M21-E30), `ThanosSidecarSansExpediteur`, `ThanosStoreBlocsExclus`, alertes de M21-E25 (RB-214) |
| **Gravité** | avertissement ; critique si la mémoire de Prometheus approche sa limite |
| **Propriétaire** | Équipe Plateforme |
| **Dernière revue** | 2026-10-27 (pannes M21-E38, E39) |

> ⚠️ **Rien ne se supprime dans ce runbook** : ni séries (API d'administration fermée dans le cluster), ni blocs du compartiment `thanos-k8s-par1` (aucune sous-commande d'écriture de `thanos tools bucket`). Une suppression de données est une décision écrite de la RSSI (procédure : M21-E45, question 20).

```
P=http://prometheus.apps.par1.medisphere.internal:9090
q() { curl -s $P/api/v1/query --data-urlencode "query=$1" | jq -c '.data.result[] | [.metric, .value[1]]'; }
```

## Cardinalité

**Mesurer**
1. Tête : `q 'max by (pod) (prometheus_tsdb_head_series{namespace="supervision"})'` maintenant et `offset 1h`.
2. Rythme : `q 'sum by (pod) (rate(prometheus_tsdb_head_series_created_total{job="kps-prometheus"}[5m]))'` (normal : quelques séries/s).
3. Cible : `q 'topk(5, scrape_series_added)'` et `q 'topk(5, scrape_samples_scraped)'`.
4. Métrique et étiquette : *Status → TSDB Status* d'un Prometheus (`kubectl -n supervision port-forward pod/prometheus-kps-0 9091:9090`), ou `q 'topk(10, count by (__name__) ({__name__=~".+"}))'` (requête lourde : une seule fois).
5. Nature des valeurs : `curl -s $P/api/v1/series -G --data-urlencode 'match[]=<métrique>' --data-urlencode "start=$(date -d '-2 min' +%s)" | jq '.data[0:5]'`. Identifiant, chemin brut, **donnée personnelle** ? (si oui : RSSI dans l'heure).

**Contenir** (au plus près de la source, par MR dans le dépôt qui porte le ServiceMonitor)
- `metricRelabelings` : `action: drop` sur `__name__` de la métrique fautive (jamais `labeldrop` seul : échantillons dupliqués).
- Limites de la cible : `sampleLimit`, `labelLimit`, `labelValueLengthLimit` au-dessus de ce qu'elle expose **après** relabeling.
- Vérifier : `scrape_samples_post_metric_relabeling` retombé, `scrape_series_added` à 0, `up == 1`.
- La tête ne redescend qu'à la compaction suivante (≤ 3 h) : ne pas redémarrer Prometheus (rejeu du WAL, mêmes séries).

**Prévenir**
- Limite globale (`enforcedSampleLimit`, `enforcedLabelLimit` de l'objet Prometheus, M21-E30).
- Alertes de rythme et de cible (ci-dessus).
- Politique : une étiquette = un ensemble de valeurs petit, fini, connu à l'avance ; liste d'étiquettes interdites ; nombre de séries prévu dans toute MR qui ajoute une métrique.

## Historique long (Thanos)

**Qui sert quoi**
1. `curl -s $P/api/v1/stores | jq '.data | map_values(map({name, lastError, minTime: (.minTime/1000|floor|todate), maxTime: (.maxTime/1000|floor|todate)}))'` : deux sidecars (15 derniers jours), un Store (du premier bloc du compartiment jusqu'à il y a ~2 h), aucun `lastError`.
2. L'union des fenêtres doit couvrir [premier bloc, maintenant] sans trou. Un Store qui commence « il y a 2 jours » : `--min-time` (alerte `ThanosStoreBlocsExclus`).

**Le compartiment, en lecture seule**
```
install -m 600 /dev/null ~/m21/objstore.yml
( set -a; . ~/.config/workbook/s3-thanos.env; set +a
  printf 'type: S3\nconfig:\n  bucket: thanos-k8s-par1\n  endpoint: rgw.par1.medisphere.internal\n  access_key: %s\n  secret_key: %s\n' \
    "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" > ~/m21/objstore.yml )
thanos tools bucket inspect --objstore.config-file=$HOME/m21/objstore.yml --output=tsv | sort -k3 | tail
rm -f ~/m21/objstore.yml
```
Dernier bloc de résolution 0 de source `sidecar` : moins de 3 h attendu. Seules `inspect`, `ls` et `web` sont permises.

**Diagnostic par composant**
- **Store** absent ou en erreur : `kubectl -n supervision logs <pod thanos-store>` (`SignatureDoesNotMatch`, `AccessDenied`, `NoSuchBucket`) ; le Secret `thanos-objstore` se recrée **depuis Vault** (`plateforme/k8s/outils/secrets-k8s.sh appliquer thanos`), jamais depuis une copie ; puis redémarrer le Store, et penser au sidecar et au Compactor qui l'ont chargé au démarrage.
- **Sidecar** qui n'envoie plus : `kubectl -n supervision get sts prometheus-kps -o json | jq -r '.spec.template.spec.containers[] | select(.name=="thanos-sidecar") | .args[]'` (`--objstore.config` présent ?) ; `q 'thanos_shipper_uploads_total'` (absent = pas d'expéditeur) ; cause : `objectStorageConfig` de `prometheus.prometheusSpec.thanos` (valeurs de kps). **Compte à rebours** : au-delà de 15 jours, les blocs locaux non envoyés sont supprimés.
- **Compactor** arrêté : `thanos_compact_halted == 1` (RB-214).

**Répondre « a-t-on perdu des données ? »** : inventaire du compartiment (dates des blocs, trous) + fenêtres servies + durée de la panne comparée à la rétention locale. Écrire la réponse, chiffres à l'appui.
