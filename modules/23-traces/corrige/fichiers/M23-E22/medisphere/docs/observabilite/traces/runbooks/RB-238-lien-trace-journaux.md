# RB-238 — Plus de lien entre une trace et ses journaux

**Symptôme** : depuis une span, « Logs for this span » ouvre une erreur ou une requête vide ; depuis une ligne de journal, le lien vers la trace a disparu.

## 1. Le chemin d'un lien

- **Tempo → Loki** : source `Tempo`, `jsonData.tracesToLogsV2` : `datasourceUid` (quelle source Loki, donc quel **locataire** : en-tête `X-Scope-OrgID` de cette source), requête construite (filtre par `trace_id`, étiquettes reprises de la span, décalage de temps).
- **Loki → Tempo** : source Loki du locataire, `jsonData.derivedFields` : champ `trace_id` (métadonnée structurée, `matcherType: label`, ou expression régulière sur la ligne), `datasourceUid` de Tempo.
- **Les journaux** : chaque ligne JSON de MédiAgenda et MédiDoc porte `trace_id` et `span_id` (M23-E08), qu'Alloy range en métadonnées structurées (M22-E06).

## 2. Diagnostiquer dans l'ordre

```
admin@adm01:~$ # La configuration servie par Grafana (ce que Grafana utilise vraiment) :
admin@adm01:~$ curl -s -K <(printf 'header = "Authorization: Bearer %s"\n' "$(<~/.config/workbook/grafana-checks.token)") \
    https://grafana.apps.par1.medisphere.internal/api/frontend/settings \
  | jq '.datasources[] | select(.type == "tempo" or .type == "loki") | {name, uid, links: (.jsonData.tracesToLogsV2 // .jsonData.derivedFields)}'
admin@adm01:~$ logcli query --org-id=mediagenda '{namespace="mediagenda-dev"} | trace_id != ""' --since=15m --limit=3
```

| Constat | Cause | Correctif |
|---|---|---|
| `tracesToLogsV2.datasourceUid` ne correspond à aucune source | UID changé ou faute de frappe | UID de la source Loki du bon locataire |
| L'UID correspond à `Loki — plateforme` | mauvais locataire : les journaux de MédiAgenda sont chez `mediagenda` | source du locataire applicatif (ou une source par équipe et un lien par équipe) |
| Champ dérivé sur `traceid`, `traceId`… | nom de champ différent de celui des journaux | `trace_id`, comme dans les journaux et les métadonnées structurées |
| Lignes sans `trace_id` | instrumentation des journaux (application) ou extraction (Alloy) | M23-E08, M22-E06 |

## 3. Vérifier et clore

D'une trace de MédiAgenda aux journaux de la même requête, et retour ; `lab/bin/check 23 22`. Les sources sont déclarées par le code : corriger dans `plateforme/observabilite`, jamais dans l'interface (le provisionnement écraserait la correction).
