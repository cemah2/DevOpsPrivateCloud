# Loki sous le capot

> Exemple de livrable de M22-E24. Les clés, numéros et tailles ci-dessous sont **ceux d'un lab de référence** : le tien doit citer des objets de **ton** compartiment (le contrôle vérifie qu'ils existent).

## 1. Chemin d'écriture

```
Alloy (loki.write) ──POST /loki/api/v1/push──▶ distributeur ──▶ ingester ──▶ (vidage) ──▶ RGW : chunks + index
       locataire = X-Scope-OrgID               valide, limite,   chunk en tête          tenant/empreinte/…
                                               hache le flux     par flux + WAL         index/loki_index_N/…
```

1. **Distributeur** : vérifie le locataire, les étiquettes (nombre, longueur), l'âge et la taille de chaque ligne, le débit du locataire (`ingestion_rate_mb`, rafale) ; tout refus est compté dans `loki_discarded_samples_total{reason,tenant}`. Il calcule l'empreinte du flux (hachage de l'ensemble trié des étiquettes) qui désigne l'ingester (ici un seul : `replication_factor: 1`).
2. **Ingester** : un flux actif = un chunk en tête en mémoire (blocs de 256 Kio compressés au fil de l'eau, `chunk_encoding: snappy`) ; chaque écriture est d'abord ajoutée au **WAL** (`/var/loki/wal/`, segments `00000000`…, points de reprise `checkpoint.NNNN`) pour survivre à un arrêt brutal. Les métadonnées structurées voyagent avec chaque ligne, sans toucher à l'index.
3. **Vidage** : un chunk part quand il atteint ~1,5 Mio (`chunk_target_size`), après 30 min sans ligne (`chunk_idle_period`) ou 2 h d'âge (`max_chunk_age`). Ici, 60 % des vidages sont sur inactivité (métrique `loki_ingester_chunks_flushed_total{reason}`).
4. **Index TSDB** : chaque chunk vidé ajoute une entrée (empreinte, étiquettes, intervalle, clé du chunk) dans l'index **actif** de la journée (`/var/loki/tsdb-shipper-active/`), téléversé toutes les 15 min dans `index/loki_index_N/<locataire>/`.

## 2. Ce qu'il y a dans le compartiment `loki-k8s-par1`

| Préfixe | Contenu | Exemple réel (lab de référence) |
|---|---|---|
| `<locataire>/<empreinte>/` | chunks : `<début>:<fin>:<somme>` en hexadécimal (millisecondes, CRC32) | `essai/6cbf7ee03bccecc2/19a2e8f1c4a:19a2e8f1c4b:24ee0c5` |
| `index/loki_index_<N>/<locataire>/` | fichiers TSDB compressés de la journée `N` (jours depuis le 01/01/1970) : ceux téléversés par l'ingester, remplacés par **un** fichier du compactor (`<horodatage ns>-compactor-<début ms>-<fin ms>-<somme>.tsdb.gz`) | `index/loki_index_20762/essai/1793889153412345678-compactor-1793836800000-1793889000000-367031c0.tsdb.gz` |
| `index/delete_requests/` | demandes d'effacement (E13) | `index/delete_requests/delete_requests.gz` |
| `loki_cluster_seed.json` | identifiant de l'installation | — |

`date -u -d @$((20762 * 86400))` → 2026-11-05 : la table du 5 novembre. Volume de la journée (lab de référence) : 412 Mio de chunks, 3,1 Mio d'index — l'index ne pèse presque rien, c'est le principe de Loki.

`chunks-inspect` sur le chunk ci-dessus : 1 bloc, 2 lignes, intervalle de 1 ms, étiquettes `{job="essai-effacement", namespace="wb-essais"}`, encodage snappy, sommes de contrôle OK.

## 3. Compactor

Dans `loki-0` (`/var/loki/compactor/`) : copies de travail des tables, fichiers de **marques** de rétention (`retention/…/markers/`), base locale des demandes d'effacement. Toutes les 10 min : fusion des fichiers d'index de chaque table en un fichier par locataire, puis rétention (chunks hors durée retirés de l'index et marqués), suppression des chunks marqués 2 h plus tard. Métriques : `loki_compactor_apply_retention_last_successful_run_timestamp_seconds`, `loki_boltdb_shipper_compact_tables_operation_last_successful_run_timestamp_seconds`.

## 4. Chemin de lecture

*Query frontend* (découpage en tranches de 1 h, cache des résultats) → requêteur → index (quels flux, quels chunks pour l'intervalle) → **ingester** pour les 3 dernières heures (`query_ingesters_within`), **stockage** pour le reste → filtres, analyseurs, agrégations.

| Requête `{namespace="mediagenda-recette"}` | 10 dernières minutes | hier, même heure |
|---|---|---|
| `Ingester.TotalReached` | 1 | 0 |
| `Querier.TotalChunksDownloaded` | 0 | 6 |
| `Summary.TotalBytesProcessed` | 180 Ko | 1,2 Mo |

## 5. Le volume de `loki-0`

WAL, index actif non encore téléversé, répertoire du compactor, WAL du *ruler*. Perdu pendant que le pod tourne : jusqu'à 2 h de journaux non vidés et les marques de rétention en cours. Perdu après un arrêt propre (`flush_on_shutdown: true`) : presque rien.

## 6. Trois questions pour un candidat

1. Pourquoi ajouter `pod` en étiquette ralentit-il les requêtes d'**hier** autant que l'ingestion d'aujourd'hui ?
2. Que se passe-t-il pour une requête sur l'heure écoulée si le RGW est indisponible ? et sur hier ?
3. Pourquoi le compactor doit-il être unique, et pourquoi son répertoire doit-il être persistant ?
