# Module 22 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les fichiers de référence sont dans [`fichiers/`](fichiers/) (un dossier par exercice, rangé comme les dépôts : `observabilite/` = `plateforme/observabilite`, `gitops/` = `plateforme/gitops`, `infra/` = `plateforme/infra`, `medisphere/` = `plateforme/medisphere`). Les sorties reproduites sont **représentatives** (Loki 3.7.9, Alloy 1.21, chart Loki 19.0.3) : noms de pods, nombres et durées varient selon ton lab.

**Validé hors du lab** pendant la rédaction : rendu des values par `helm template` (charts `loki` 19.0.3, `opensearch` 3.9.0, `fluent-bit` 0.58.3), schémas par `kubeconform` (y compris CiliumNetworkPolicy et objets cert-manager), configuration de Loki par `loki -verify-config` (3.7.9), puis un Loki 3.7.9 local (stockage `filesystem`) avec le fichier de surcharges de E13 : lecture de `/config/tenant/v1/limits` par locataire, demande d'effacement acceptée sur `essai` (`204`, statut `received`, ligne filtrée à la lecture **immédiatement**) et refusée sur `audit` (`403 deletion is not available for this tenant`), messages d'erreur des limites (cités en E20/E21). Règles d'alerte par `promtool check rules` et `promtool test rules` (Prometheus 3.15). Fichier OpenTofu par `tofu validate` (fournisseur `grafana/grafana` 4.50.0 : la 4.51 n'était pas encore publiée sur le registre d'OpenTofu au 22/10/2026 — garde `~> 4.50` si `tofu init` ne la trouve pas).

**Points non testés en conditions réelles** (signale tes retours) :
- propagation du ConfigMap `loki-runtime` dans le pod (délai du kubelet) et rechargement à chaud : le principe est documenté, le délai exact dépend de ton kubelet ;
- règles HTTP de niveau 7 de Cilium 1.20 sur un trafic entrant par un Service `LoadBalancer` en `externalTrafficPolicy: Local` (source conservée) : principe documenté par Cilium, non mesuré sur `k8s-par1` ; effet sur `tail` (WebSocket) à observer ;
- démarrage d'OpenSearch 3.9 avec les certificats de cert-manager (PKCS#8) et l'initialisation de l'index de sécurité à partir des fichiers montés ; empreintes bcrypt au format `$2y$` ;
- prise en charge par le RGW Tentacle 20.2 de la règle de cycle de vie `NoncurrentVersionExpiration` combinée à `ExpiredObjectDeleteMarker` ;
- `GET /api/frontend/settings` de Grafana 13 comme moyen, pour le check, de lister les sources visibles par un *Viewer*.

---

### M22-E13 — Rétention, locataires et limites

**Solution**

*1. État des lieux*

```
admin@adm01:~$ export LOKI_ADDR=http://loki.apps.par1.medisphere.internal:3100
admin@adm01:~$ curl -s $LOKI_ADDR/config | yq '.compactor, .limits_config | pick(["retention_enabled","delete_request_store","retention_period","deletion_mode","ingestion_rate_mb","max_global_streams_per_user"])'
retention_enabled: false
delete_request_store: ""
retention_period: 0s
deletion_mode: filter-and-delete
ingestion_rate_mb: 4
max_global_streams_per_user: 5000
admin@adm01:~$ for t in plateforme mediagenda medidoc audit essai; do printf '%-11s ' $t; curl -s -H "X-Scope-OrgID: $t" $LOKI_ADDR/config/tenant/v1/limits | yq -o=json '{"r": .retention_period, "l": .max_query_lookback}' | jq -c; done
plateforme  {"r":"0s","l":"0s"}
…
admin@adm01:~$ set -a; . ~/.config/workbook/s3-loki.env; set +a
admin@adm01:~$ aws s3 ls s3://loki-k8s-par1 --recursive --summarize --endpoint-url https://rgw.par1.medisphere.internal | tail -2
Total Objects: 18342
   Total Size: 412783211
```

Lecture : `retention_period: 0s` = **aucune** rétention ; `deletion_mode` vaut `filter-and-delete` par défaut, mais l'API d'effacement n'existe pas tant que la rétention du compactor n'est pas activée (documentation « Log entry deletion »). Autrement dit, aujourd'hui l'effacement est impossible et tout est gardé indéfiniment.

*2 à 5. Configuration* : [`fichiers/M22-E13/observabilite/loki/values.yaml`](fichiers/M22-E13/observabilite/loki/values.yaml) — la version d'E08, plus les blocs marqués `M22-E13` (`loki.compactor`, ajouts à `loki.limits_config`, `loki.runtimeConfig`) et `M22-E14`. Points clés :

| Réglage | Valeur | Pourquoi |
|---|---|---|
| `compactor.working_directory` | `/var/loki/compactor` (sur le PVC) | Les fichiers de **marques** (chunks à supprimer) doivent survivre à un redémarrage, sinon des chunks restent orphelins |
| `compaction_interval` | 10m | Défaut ; le compactor rattrape tout seul s'il est en retard |
| `retention_enabled` | `true` | Sans lui, `retention_period` n'a aucun effet et l'API d'effacement n'existe pas |
| `retention_delete_delay` | 2h | Fenêtre pendant laquelle une erreur de rétention se rattrape (les chunks sont marqués, pas encore supprimés) |
| `delete_request_store` | `s3` | Obligatoire avec la rétention ; les demandes sont gardées dans le compartiment |
| `delete_request_cancel_period` | 24h | Défaut : une demande se relit et s'annule pendant 24 h |
| `limits_config.retention_period` | 336h | Défaut = plateforme (14 jours) ; tout locataire non déclaré en hérite |
| `limits_config.deletion_mode` | `disabled` | Fermé par défaut, ouvert locataire par locataire |
| `runtimeConfig.overrides.<locataire>` | rétention, profondeur, effacement, débit, rafale, flux | Rechargé à chaud ; une MR = un diff lisible par locataire |
| `retention_stream` de `plateforme` | `{namespace="wb-essais"}` → 24h | Une règle par flux (sélecteur d'étiquettes **seulement**, pas de LogQL) ; 24h est le minimum |

Limites d'ingestion : mesure avant de fixer.

```
admin@adm01:~$ curl -s $LOKI_ADDR/metrics | grep -E '^loki_ingester_memory_streams\{'
loki_ingester_memory_streams{tenant="audit"} 4
loki_ingester_memory_streams{tenant="mediagenda"} 24
loki_ingester_memory_streams{tenant="medidoc"} 6
loki_ingester_memory_streams{tenant="plateforme"} 412
admin@adm01:~$ for t in plateforme mediagenda medidoc audit; do logcli query --org-id=$t --quiet --since=24h --step=1h \
    'sum(bytes_rate({job=~".+"}[1h]))' -o raw | sort -n | tail -1; done
```

(un sélecteur doit contenir au moins un matcher qui ne correspond pas à la chaîne vide : `{job=~".+"}`, ou `{namespace=~".+"}` selon les étiquettes du locataire). Le débit de pointe de `plateforme` dans un lab de référence est ≈ 120 Kio/s : 8 Mo/s laisse de la marge pour une rafale de redémarrages ; `essai` à 1 Mo/s et 500 flux suffit à un essai et empêche un essai mal conçu de prendre la place des autres.

Pourquoi aligner `max_query_lookback` sur la rétention : entre le marquage par le compactor et la suppression effective (`retention_delete_delay`), une requête pourrait encore trouver des données en sursis, ou des références d'index vers des chunks déjà supprimés (erreurs de lecture). Avec une profondeur égale à la rétention, ce qui doit disparaître n'est déjà plus proposé.

Fusion et synchronisation (Argo CD) :

```
admin@adm01:~$ argocd app diff loki        # deux ConfigMaps changent : loki (compactor, limits_config) et loki-runtime
admin@adm01:~$ kubectl -n journaux get pod loki-0 -o jsonpath='{.metadata.annotations.checksum/config}{"\n"}{.status.startTime}{"\n"}'
```

Le ConfigMap `loki` a changé : l'empreinte `checksum/config` du gabarit du pod change, le StatefulSet redémarre `loki-0` (quelques dizaines de secondes sans Loki : Alloy garde et réessaie). Un changement du seul `runtimeConfig` ne redémarre rien : il est pris en compte quand le kubelet a mis à jour le fichier monté (jusqu'à ~1 min) puis au rechargement suivant (10 s) :

```
admin@adm01:~$ curl -s $LOKI_ADDR/metrics | grep -E '^loki_runtime_config_(last_reload_successful|hash)'
loki_runtime_config_hash{config="loki",sha256="cf51ad92…"} 1
loki_runtime_config_last_reload_successful{config="loki"} 1
admin@adm01:~$ for t in plateforme mediagenda medidoc audit essai; do printf '%-11s ' $t; curl -s -H "X-Scope-OrgID: $t" $LOKI_ADDR/config/tenant/v1/limits | yq -o=json '{"r": .retention_period, "l": .max_query_lookback}' | jq -c; done
plateforme  {"r":"2w","l":"2w"}
mediagenda  {"r":"30d","l":"30d"}
medidoc     {"r":"30d","l":"30d"}
audit       {"r":"1y","l":"1y"}
essai       {"r":"1d","l":"1d"}
admin@adm01:~$ curl -s $LOKI_ADDR/services | grep compactor
compactor => Running
```

`/config/tenant/v1/limits` n'affiche qu'une liste blanche de limites (`tenant_limits_allow_publish` : rétention, profondeur, délai, séries…) ; les limites d'ingestion et le mode d'effacement se relisent dans le ConfigMap :

```
admin@adm01:~$ kubectl -n journaux get cm loki-runtime -o jsonpath='{.data.runtime-config\.yaml}' | yq '.overrides | map_values(pick(["deletion_mode","ingestion_rate_mb","max_global_streams_per_user"]))'
```

*5. Effacement sur `essai`*

```
admin@adm01:~/DevOpsPrivateCloud$ modules/22-logs/ressources/E13-effacement/pousser-essai.sh
5 lignes poussées dans le locataire essai ({job="essai-effacement"}), dont 2 avec PAT-E13-0042.
admin@adm01:~$ logcli query --org-id=essai --since=10m --quiet '{job="essai-effacement"} |= "PAT-E13-0042"' -o raw
export agenda patient=PAT-E13-0042 nom=Jeanne-Exemple statut=erreur
rdv créé praticien=dr-morel creneau=09:30 patient=PAT-E13-0042 statut=ok
admin@adm01:~$ logcli delete create --org-id=essai '{job="essai-effacement"} |= "PAT-E13-0042"' \
    --from="$(date -u -d '-15 min' +%Y-%m-%dT%H:%M:%SZ)" --to="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
Delete request created successfully
admin@adm01:~$ curl -s -H 'X-Scope-OrgID: essai' $LOKI_ADDR/loki/api/v1/delete | jq '.[] | {request_id, status, query}'
{
  "request_id": "9b267916",
  "status": "received",
  "query": "{job=\"essai-effacement\"} |= \"PAT-E13-0042\""
}
admin@adm01:~$ logcli query --org-id=essai --since=10m --quiet '{job="essai-effacement"}' -o raw
rdv créé praticien=dr-benali creneau=11:00 statut=ok
rdv annulé praticien=dr-benali creneau=10:00 statut=ok
rdv créé praticien=dr-morel creneau=09:00 statut=ok
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' -X POST -G -H 'X-Scope-OrgID: audit' $LOKI_ADDR/loki/api/v1/delete \
    --data-urlencode 'query={job=~".+"} |= "PAT-E13-0042"' --data-urlencode "start=$(date -d '-1 hour' +%s)" --data-urlencode "end=$(date +%s)"
403
```

Les deux lignes visées ne sont **déjà plus renvoyées** alors que la demande est `received` : les requêteurs filtrent à la lecture toutes les demandes connues ; la suppression physique dans les chunks a lieu après le délai d'annulation (24 h), au passage suivant du compactor, et le statut devient `processed`. `audit` répond `403 deletion is not available for this tenant`.

*7. Livrables* : section 2 de [`politique-journaux.md`](fichiers/M22-E13/medisphere/docs/observabilite/journaux/politique-journaux.md) (la section 1 vient d'E09, les sections 3 et 4 d'E16) et [`RB-221`](fichiers/M22-E13/medisphere/docs/observabilite/journaux/runbooks/RB-221-effacement-journaux.md).

**Explications**

Loki ne supprime jamais une ligne à l'écriture ni au vidage : la rétention est une opération **sur l'index**. À chaque passage, le compactor fusionne les fichiers d'index d'une journée en un fichier par locataire, parcourt l'index de chaque locataire, retire les références aux chunks trop vieux (selon la règle de priorité : `retention_stream` du locataire, puis global, puis `retention_period` du locataire, puis global), écrit ces chunks dans un fichier de marques sur disque, téléverse l'index réécrit ; un balayeur supprime les chunks marqués après `retention_delete_delay`. C'est pourquoi la période d'index doit être de 24 h, pourquoi le compactor doit être **unique**, et pourquoi son répertoire de travail doit être persistant.

La configuration d'exécution (*runtime config*) est le mécanisme multi-locataire de Loki : un fichier relu périodiquement, où chaque locataire surcharge n'importe quelle valeur de `limits_config`. C'est aussi le seul endroit où un changement de limite ne coûte pas un redémarrage.

Le mode d'effacement est une **limite** (donc par locataire), pas un réglage du compactor ; il a trois valeurs : `disabled` (API fermée : `403`), `filter-only` (les lignes sont seulement masquées à la lecture, jamais supprimées), `filter-and-delete` (masquées puis supprimées).

**Alternatives**
- Règle de cycle de vie du compartiment (expiration des objets à N jours) à la place du compactor : ne connaît pas les locataires (les chunks sont rangés par locataire, mais l'index est partagé par journée) et casse l'index (références vers des chunks disparus). La documentation recommande au contraire que toute règle de cycle de vie soit **plus longue** que la rétention.
- Un compartiment par locataire : Loki OSS ne sait pas router le stockage par locataire.
- `filter-only` pour `mediagenda` : plus prudent (rien n'est jamais détruit, réversible), mais ne répond pas à un droit à l'effacement : la donnée reste dans le compartiment.

**Pièges classiques**
- Croire qu'une rétention ne touche que le futur : elle s'applique à **tout** ce qui est dans l'index au passage suivant. Passer de « infini » à 14 jours supprime d'un coup ce qui a plus de 14 jours.
- Oublier `delete_request_store` : Loki refuse de démarrer avec `retention_enabled: true` sans magasin des demandes (message explicite au démarrage, `CrashLoopBackOff`).
- `retention_period: 12h` : refusé (minimum 24h) ; une `retention_stream` avec une expression LogQL au lieu d'un sélecteur : refusée.
- Une demande d'effacement sans filtre de ligne efface **tout le flux** sur la fenêtre ; une fin de fenêtre dans le futur est refusée (`deletes in the future are not allowed`).
- `logcli delete list --output=json` : l'option `--output` n'accepte que `default`, `raw`, `jsonl` ; l'identifiant d'une demande se lit par l'API.
- Le cache des résultats et Grafana : une page Grafana déjà ouverte affiche encore l'ancien résultat jusqu'au rafraîchissement.

**En production chez MédiSphère**
Le tableau de la politique est relu chaque année avec la RSSI ; une alerte prévient si `loki_compactor_apply_retention_last_successful_run_timestamp_seconds` a plus de 2 h (rétention arrêtée = compartiment qui grossit et obligation non tenue) ; les demandes d'effacement sont tracées dans les tickets `SEC-` ; un test d'effacement sur `essai` fait partie de la recette annuelle.

---

### M22-E14 — Performance de Loki et cardinalité des étiquettes

**Solution**

*1. Cardinalité*

```
admin@adm01:~$ logcli series --org-id=plateforme --since=24h '{namespace=~".+"}' --analyze-labels
Total Streams:  655
Unique Labels:  6

Label Name  Unique Values  Found In Streams
container   71             655
app         52             640
namespace   38             655
node        6              655
job         3              655
cluster     1              655
…
admin@adm01:~$ logcli series --org-id=plateforme --since=24h '{host=~".+"}' --analyze-labels      # VMs
admin@adm01:~$ logcli series --org-id=audit --since=24h '{job=~".+"}' --analyze-labels
admin@adm01:~$ curl -s $LOKI_ADDR/metrics | grep '^loki_ingester_memory_streams{'
```

`container` a le plus de valeurs, mais elle est **bornée** (un nom par composant) ; ce qui est dangereux, c'est une valeur qui change à chaque déploiement (`pod`), à chaque requête (`request_id`) ou à chaque utilisateur.

*2. Étiquettes ajoutées par Loki* : sans réglage, Loki crée `service_name` à l'ingestion à partir de la première étiquette connue de la liste `discover_service_name` (`app`, `container`…). Elle double une étiquette existante (cardinalité bornée) mais sort de la liste fermée : E02 l'a coupée (`discover_service_name: []`). Sur 1 h, aucune trace ; sur 7 jours, les flux écrits avant la coupure (premières minutes d'E02, si Loki a reçu des lignes avant la synchronisation de cette valeur) apparaissent encore : ils sont dans l'index jusqu'à leur rétention (14 jours pour `plateforme`) et ne bougent plus. *Logs Drilldown* regroupe alors les flux sous `unknown_service` : à revoir si l'équipe s'en sert pour l'astreinte (on réactiverait la découverte avec une liste courte, `app` seulement).

*3. Chunks*

```
admin@adm01:~$ curl -s $LOKI_ADDR/metrics | grep -E '^loki_ingester_chunks_flushed_total|^loki_ingester_chunk_size_bytes_(sum|count)|^loki_ingester_chunk_compression_ratio_(sum|count)'
loki_ingester_chunks_flushed_total{reason="full"} 212
loki_ingester_chunks_flushed_total{reason="idle"} 2160
loki_ingester_chunks_flushed_total{reason="max_age"} 1170
…
```

Dans un lab, la plupart des chunks partent sur **inactivité** (`chunk_idle_period`, 30 min) ou **âge** (`max_chunk_age`, 2 h) bien avant la taille cible (1,5 Mio) : beaucoup de petits objets. Une étiquette `pod` multiplierait les flux (un par pod et par redémarrage), diviserait d'autant la taille des chunks, gonflerait l'index et la mémoire de l'ingester (chaque flux actif a son chunk en tête), et ralentirait les requêtes (plus de chunks à ouvrir pour la même quantité de lignes).

*4. Requêtes*

```
admin@adm01:~$ logcli query --org-id=plateforme --since=168h --step=5m --stats --quiet \
    'sum by (namespace) (count_over_time({namespace=~".+"} | json | niveau="ERROR" [5m]))' >/dev/null
Ingester.TotalReached       1
Ingester.TotalChunksMatched 37
Querier.TotalChunksRef      4912
Querier.TotalChunksDownloaded 4912
Summary.BytesProcessedPerSecond 85 MB
Summary.TotalBytesProcessed  2.1 GB
Summary.ExecTime            24.8s
…
```

Ce qui coûte : 4 900 chunks à télécharger et décompresser, puis **chaque** ligne passée à l'analyseur JSON. Reformulation équivalente pour un tableau de 7 jours :

```
sum by (namespace) (count_over_time({namespace=~".+"} |= "ERROR" | json | niveau="ERROR" [1h]))
```

avec un pas d'1 h : le filtre de ligne écarte 90 % des lignes avant l'analyseur (et la vérification `niveau="ERROR"` garde le résultat exact : une ligne qui contient « ERROR » ailleurs que dans le niveau est écartée par l'analyseur) ; 168 points au lieu de 2 016. Meilleur encore pour le tableau : une règle d'enregistrement du *ruler* (M22-E08) qui calcule ce nombre en continu.

*5. Réglages* : blocs `M22-E14` de [`values.yaml`](fichiers/M22-E13/observabilite/loki/values.yaml) (`split_queries_by_interval: 1h` au lieu de 15m, `query_timeout: 2m` au lieu de 300s, `querier.max_concurrent: 4`, `max_query_parallelism: 16`, `query_range.cache_results` avec `embedded_cache` de 100 Mo). Deuxième exécution d'une requête identique : seule la dernière tranche (plus récente que `max_cache_freshness_per_query`, 10 min) est recalculée.

*6. Livrables* : [`performance.md`](fichiers/M22-E14/medisphere/docs/observabilite/journaux/performance.md) et la règle [`regles/loki-capacite.yaml`](fichiers/M22-E14/observabilite/regles/loki-capacite.yaml) avec son test [`tests/loki-capacite.test.yaml`](fichiers/M22-E14/observabilite/tests/loki-capacite.test.yaml) (l'étiquette `medisphere.internal/supervision: "oui"` est celle que l'opérateur sélectionne depuis M21-E02) ; ajoute le fichier à `regles/kustomization.yaml` (M21-E07), sinon l'Application `observabilite` ne l'applique pas.

**Explications**

Le chemin d'une requête dans Loki : le *query frontend* découpe la plage en intervalles (`split_queries_by_interval`) et, pour les requêtes métriques, en fragments (*sharding* par flux), interroge le cache des résultats, met les sous-requêtes en file ; les requêteurs résolvent le sélecteur dans l'index TSDB (liste de flux et de chunks), lisent les chunks récents dans l'ingester et les anciens dans le stockage, appliquent filtres et analyseurs, agrègent. Le sélecteur détermine **combien** de données on lit ; tout ce qui suit le sélecteur détermine **combien de travail** on fait par ligne. D'où les deux règles : sélecteurs précis, filtres de ligne avant les analyseurs.

**Alternatives**
- memcached pour les caches de chunks et de résultats (chart : `chunksCache`, `resultsCache`) : la bonne solution à partir de plusieurs requêteurs, et le cache survit au redémarrage de Loki ; trop cher en mémoire pour le lab.
- *Bloom filters* (`bloom_build`, `bloom_gateway`) pour accélérer la recherche de chaînes rares : composants supplémentaires, encore expérimentaux, pertinents à très gros volume.
- Mode distribué avec plusieurs requêteurs : le découpage fin redevient utile.

**Pièges classiques**
- Mesurer une seule fois : la première exécution remplit les caches (et le cache de pages du système), la deuxième ment dans l'autre sens. Mesurer froid **et** chaud, et le dire.
- Supprimer `service_name` sans prévenir les utilisateurs de *Logs Drilldown*.
- Augmenter `max_query_parallelism` ou `max_concurrent` sans regarder la mémoire de `loki-0` : OOM, et le pod redémarre (WAL rejoué, quelques minutes sans requêtes).
- Une alerte de cardinalité dont le seuil n'est écrit nulle part : quand la limite change, l'alerte ment.

**En production chez MédiSphère**
Un tableau « Loki — santé » (flux actifs, échantillons rejetés, latence des requêtes par locataire, durée du compactor) dans le dossier Plateforme ; une revue trimestrielle de la cardinalité avec les équipes ; toute nouvelle étiquette passe par la MR de `alloy/` et doit citer sa cardinalité attendue.

---

### M22-E15 — OpenSearch : la recherche plein texte en comparaison

**Solution**

*1. Préparer*

- Miroir des charts : entrées de [`charts-ajouts-E15.yaml`](fichiers/M22-E15/charts-miroir/charts-ajouts-E15.yaml) ajoutées à `charts.yaml` de `plateforme/charts-miroir` (empreintes vérifiées sur les index amont), pipeline relancé, présence et signature vérifiées :
  ```
  admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub registry.par1.medisphere.internal/charts/opensearch:3.9.0 >/dev/null && echo signé
  ```
- Espace, autorité et certificats : l'espace est créé par l'Application (`CreateNamespace=true` et `managedNamespaceMetadata`), l'autorité **propre à l'essai** (émetteur auto-signé → certificat CA → émetteur CA) et les deux certificats sont des `extraObjects` des values d'OpenSearch : ils naissent et meurent avec l'essai. Pourquoi pas `step-ca` (ClusterIssuer `step-ca-acme`) : l'ACME ne délivre pas de certificat client d'administration (CN arbitraire, usage `client auth`), et un essai ne doit pas laisser de certificats émis par la racine MédiSphère.
- Niveau de Pod Security : `privileged` sur `opensearch-essai`, parce que Fluent Bit monte `/var/log` de l'hôte (interdit en `baseline`), avec `warn: restricted` pour voir ce qui dépasse ; exception écrite dans l'Application et dans le ticket, levée avec l'espace.

*2. OpenSearch* : [`opensearch-essai/values.yaml`](fichiers/M22-E15/observabilite/opensearch-essai/values.yaml) et l'Application [`opensearch-essai.yaml`](fichiers/M22-E15/gitops/plateforme/opensearch-essai.yaml). Empreintes des mots de passe :

```
admin@adm01:~$ read -rs MDP; htpasswd -bnBC 12 "" "$MDP" | tr -d ':\n'; echo; unset MDP
$2y$12$…
```

(`apache2-utils` ; l'outil `plugins/opensearch-security/tools/hash.sh` de l'image produit le même format). Les mots de passe vont dans `secrets/opensearch-essai.yml` (Vault `critique`) ; `secrets-k8s.sh` crée le Secret `opensearch-essai-fluentbit` (clé `FLUENTBIT_MDP`) pour Fluent Bit.

```
admin@adm01:~$ kubectl -n opensearch-essai get pods,certificates
NAME                            READY   STATUS    RESTARTS   AGE
pod/opensearch-essai-master-0   1/1     Running   0          4m
NAME                                                READY   SECRET
certificate.cert-manager.io/opensearch-essai-admin   True    opensearch-essai-admin
certificate.cert-manager.io/opensearch-essai-ca      True    opensearch-essai-ca
certificate.cert-manager.io/opensearch-essai-noeud   True    opensearch-essai-noeud
admin@adm01:~$ kubectl -n opensearch-essai get secret opensearch-essai-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > ~/m22/e15/ca-essai.crt
admin@adm01:~$ kubectl -n opensearch-essai port-forward svc/opensearch-essai-master 9200:9200 &
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cacert ~/m22/e15/ca-essai.crt https://localhost:9200/
401
admin@adm01:~$ read -rs OS_MDP; curl -s --cacert ~/m22/e15/ca-essai.crt -u "admin:$OS_MDP" https://localhost:9200/_plugins/_security/authinfo | jq '{user_name, roles}'
```

`localhost` figure dans les noms du certificat du nœud pour que le relais de port se vérifie sans `-k`.

*3. Fluent Bit* : [`fluent-bit-opensearch/values.yaml`](fichiers/M22-E15/observabilite/fluent-bit-opensearch/values.yaml) et [`fluent-bit-opensearch.yaml`](fichiers/M22-E15/gitops/plateforme/fluent-bit-opensearch.yaml). Contrôle :

```
admin@adm01:~$ curl -s --cacert ~/m22/e15/ca-essai.crt -u "admin:$OS_MDP" 'https://localhost:9200/_cat/indices/journaux-*?v&bytes=b'
health status index               uuid   pri rep docs.count store.size
yellow open   journaux-2026.10.30 …      1   1      41300   24750832
```

`yellow` : un réplica demandé (défaut du modèle d'index) que le nœud unique ne peut pas placer ; pour l'essai, `PUT journaux-*/_settings {"index":{"number_of_replicas":0}}` le rend `green` et donne une taille comparable (sans réplica).

*4-5. Comparer et rédiger* : [`ressources/E15-comparaison/requetes.md`](../ressources/E15-comparaison/requetes.md) donne la grille ; un exemple rempli est [`comparatif-opensearch.md`](fichiers/M22-E15/medisphere/docs/observabilite/journaux/comparatif-opensearch.md). Côté Loki, la même heure se mesure en octets de chunks stockés (`loki_ingester_chunk_stored_bytes_total` du locataire, ou les objets `mediagenda/` modifiés dans l'heure dans le compartiment).

*6. Retirer*

```
admin@adm01:~$ cd ~/src/gitops && git rm plateforme/opensearch-essai.yaml plateforme/fluent-bit-opensearch.yaml && git commit -m "chore(essais): retrait de l'essai OpenSearch (PLAT-2315)" && git push   # MR, fusion
admin@adm01:~$ kubectl get applications.argoproj.io -n argocd | grep essai      # plus rien après la synchro de la racine
admin@adm01:~$ kubectl -n opensearch-essai get pvc                             # le PVC du StatefulSet est resté
NAME                                              STATUS   VOLUME     CAPACITY
opensearch-essai-master-opensearch-essai-master-0 Bound    pvc-7c1e…  10Gi
admin@adm01:~$ kubectl -n opensearch-essai delete pvc --all && kubectl delete namespace opensearch-essai
admin@adm01:~$ kubectl get pv | grep opensearch-essai || echo "aucun PV restant"
```

Retirer aussi les dossiers `opensearch-essai/` et `fluent-bit-opensearch/` de `plateforme/observabilite` et les deux entrées du miroir (`opensearch`, `fluent-bit`) : aucune Application ne s'en sert plus, et `lab/bin/check 22 10` comme `22 15` vérifient leur absence. La classe `ceph-rbd` est en `Delete` : le PV et l'image RBD partent avec le PVC (vérifier `rbd ls k8s-rbd` côté Ceph si un doute subsiste).

**Explications**

OpenSearch indexe **chaque mot** de chaque ligne et chaque champ : la recherche est un accès direct dans un index inversé, d'où des temps en millisecondes ; le prix est payé à l'écriture (CPU d'indexation), en disque (index ≥ données) et en mémoire (tas Java, caches de segments). Loki n'indexe que les étiquettes : l'écriture est presque gratuite, le stockage objet bon marché, et la recherche est un **parcours** compressé et parallélisé des chunks sélectionnés. Les deux sont rapides quand on reste dans leur modèle : OpenSearch pour l'aiguille dans la botte de foin, Loki pour « les journaux de ce service, ce jour-là », filtrés.

**Alternatives**
- OpenSearch Dashboards pour comparer l'ergonomie (chart 3.9.0, + 1 Gio) ; Data Prepper à la place de Fluent Bit.
- Elasticsearch : licences successives (SSPL/ELv2, puis AGPL ajoutée en 2024) à faire relire par le juridique ; OpenSearch est sous Apache 2.0.
- Garder la configuration de démonstration « pour aller vite » : refusé, c'est précisément ce qui finit en production.

**Pièges classiques**
- Clé privée en PKCS#1 (défaut de cert-manager pour RSA) : le plugin de sécurité refuse de démarrer.
- `admin_dn` qui ne correspond pas exactement au DN du certificat (ordre, espaces) : `securityadmin.sh` est refusé. Lire le DN réel : `openssl x509 -noout -subject -nameopt RFC2253`.
- Oublier `Suppress_Type_Name On` : OpenSearch 2+ rejette les requêtes `_bulk` avec un type (`Trace_Error On` l'affiche dans les journaux de Fluent Bit).
- `Keep_Log Off` avec `Merge_Log On` : la ligne brute disparaît, la recherche plein texte ne porte plus que sur les champs.
- Oublier les PVC et les certificats à la fin : l'essai « retiré » occupe encore 10 Gio de `ceph-rbd`.
- Lancer l'essai pendant un autre essai lourd : OOM sur un travailleur, évictions de MédiAgenda.

**En production chez MédiSphère**
La comparaison est un livrable d'architecture : elle est versionnée avec ses mesures et sa date, et relue si les volumes ou les besoins changent (révision de l'ADR-0220).

---

### M22-E16 — Accès, sécurité et sauvegarde des journaux

**Solution**

*1. Constater*

```
admin@adm01:~$ curl -s -G -H 'X-Scope-OrgID: audit' $LOKI_ADDR/loki/api/v1/query_range --data-urlencode 'query={job="kubernetes-audit"}' --data-urlencode limit=1 | jq '.data.result | length'
1
admin@adm01:~$ kubectl -n wb-essais run lecteur --rm -it --restart=Never --image=registry.par1.medisphere.internal/dockerhub/curlimages/curl:8.17.0 -- \
    curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://loki.journaux.svc:3100/ready
000
command terminated with exit code 28
admin@adm01:~$ hubble observe --from-pod journaux/loki-0 --last 200 -o compact | awk '{print $4}' | sort | uniq -c
```

La politique d'E02 refuse déjà les pods des autres espaces et limite les VMs au `push`. Ce qui reste ouvert : MGMT et Grafana lisent tous les locataires (par conception), **Alloy** a tout le port 3100 alors qu'il ne fait qu'écrire, et rien ne borne ce que `loki-0` peut joindre. Dans Grafana, n'importe quel compte de l'organisation principale choisit « Loki — audit » dans Explore.

*2-3. Matrice et politiques* : [`matrice-flux-cluster-journaux.md`](fichiers/M22-E16/medisphere/docs/kubernetes/reseau/matrice-flux-cluster-journaux.md) et la nouvelle version de [`loki/manifestes/politique-reseau.yaml`](fichiers/M22-E16/observabilite/loki/manifestes/politique-reseau.yaml) : `loki-entree` resserrée (Alloy et VMs en `POST /loki/api/v1/push`, Grafana en lecture de l'API et des règles, entité `host` explicite) et `loki-sortie` (nouvelle). Les règles Cilium s'**additionnent** : une politique large laissée ailleurs (l'extrait de Fluent Bit d'E10, par exemple) annulerait les restrictions — vérifie qu'il n'en reste pas (`kubectl -n journaux get cnp`).

Ordre d'application : `loki-entree` seule, 10 minutes d'observation, puis `loki-sortie`.

```
admin@adm01:~$ hubble observe -n journaux --verdict DROPPED -f
admin@adm01:~$ hubble observe -n journaux --type l7 --last 20
… journaux/alloy-7xk2p:41234 -> journaux/loki-0:3100 http-request FORWARDED (HTTP/1.1 POST http://loki.journaux.svc:3100/loki/api/v1/push)
admin@adm01:~$ ssh git01 "curl -s -o /dev/null -w '%{http_code}\n' -H 'X-Scope-OrgID: audit' http://loki.apps.par1.medisphere.internal:3100/loki/api/v1/labels"
403
```

Depuis une VM, la lecture répond `403 Access denied` (refus de niveau 7 par le proxy) ; l'écriture continue. Vérifie la collecte : `lab/bin/check 22 03` et `lab/bin/check 22 05` restent verts, `lab/bin/check 22 08` aussi (le *ruler* joint Alertmanager par la sortie autorisée).

*4. Grafana* : [`organisation-securite.tf`](fichiers/M22-E16/infra/observabilite-grafana/organisation-securite.tf) dans l'état `observabilite-grafana`, et nouvelle version de [`grafana/sources-loki.yaml`](fichiers/M22-E16/observabilite/grafana/sources-loki.yaml) : la source « Loki — audit » quitte la liste **et** figure dans `deleteDatasources` (sinon Grafana la garde dans l'organisation principale). Elle renaît dans l'organisation Sécurité avec le **même UID** `loki-audit` : les liens et tableaux qui la citent restent valables une fois dans la bonne organisation, et `lab/bin/check 22 02` reconnaît le déplacement (il n'attend plus que trois sources dans le provisionnement).

```
admin@adm01:~/src/infra/observabilite-grafana$ tofu plan -out plan.bin && tofu apply plan.bin
  # grafana_organization.securite will be created
  # grafana_data_source.loki_audit will be created
```

Le fournisseur reste celui de l'état (`~> 4.50`, M21-E17). Chaque membre doit exister dans Grafana (sinon l'`apply` échoue) : le compte de Sophie Laurent n'était dans aucune équipe du M21 ; crée-le d'abord comme les autres comptes locaux du M21 s'il manque.

Vérification avec le compte *Viewer* des checks (organisation principale) : la source n'apparaît plus dans `GET /api/frontend/settings` (`.datasources`) ; Sophie bascule d'organisation dans le menu de Grafana pour l'interroger. Les alertes du locataire `audit` (*ruler*, E08) ne dépendent pas de Grafana : elles continuent.

*5. Sauvegarde*

```
admin@adm01:~$ set -a; . ~/.config/workbook/s3-loki.env; set +a; E=https://rgw.par1.medisphere.internal
admin@adm01:~$ aws s3api put-bucket-versioning --bucket loki-k8s-par1 --versioning-configuration Status=Enabled --endpoint-url $E
admin@adm01:~$ aws s3api put-bucket-lifecycle-configuration --bucket loki-k8s-par1 --endpoint-url $E \
    --lifecycle-configuration file://modules/22-logs/corrige/fichiers/M22-E16/adm01/cycle-de-vie-loki.json
admin@adm01:~$ aws s3api get-bucket-versioning --bucket loki-k8s-par1 --endpoint-url $E
{ "Status": "Enabled" }
admin@adm01:~$ aws s3api get-bucket-lifecycle-configuration --bucket loki-k8s-par1 --endpoint-url $E | jq '.Rules[].NoncurrentVersionExpiration'
{ "NoncurrentDays": 7 }
```

[`cycle-de-vie-loki.json`](fichiers/M22-E16/adm01/cycle-de-vie-loki.json) : expiration des versions non courantes à 7 jours et nettoyage des marqueurs de suppression orphelins. Ce réglage est un état du compartiment : écris-le aussi là où le compartiment est créé (E02), sinon il disparaît à la reconstruction.

*6. Politique* : sections 3 et 4 de [`politique-journaux.md`](fichiers/M22-E16/medisphere/docs/observabilite/journaux/politique-journaux.md), dont la décision sur le transport : HTTP en clair accepté jusqu'au M24 (journaux masqués, réseaux du lab, écriture seule depuis les VMs), TLS et identité des agents traités ensemble par la passerelle authentifiante.

**Explications**

Le multi-locataire de Loki n'est qu'un **cloisonnement logique** : Loki croit l'en-tête qu'on lui donne. La sécurité se fait donc autour : qui peut parler à Loki et pour quoi faire (réseau, niveau 7), et qui pose l'en-tête (aujourd'hui : Grafana, d'après la source choisie et l'organisation de l'utilisateur ; demain, une passerelle qui le déduit de l'identité). La règle HTTP de Cilium transforme « Alloy peut parler à Loki » en « Alloy peut **pousser** », ce qui est son vrai besoin : un DaemonSet compromis peut encore polluer un locataire, plus le lire. La politique de sortie limite ce qu'un Loki compromis pourrait exfiltrer ou atteindre.

Le versionnage protège contre la cause la plus probable de perte : une rétention mal réglée ou une suppression manuelle. Il ne protège ni de la perte du cluster Ceph, ni d'un attaquant qui détient les identifiants du compte `loki` (il peut supprimer aussi les versions) ; c'est pourquoi la décision est écrite, avec son risque accepté et le module (F5) qui le traitera.

**Alternatives**
- Passerelle nginx du chart (`gateway.enabled`) avec authentification basique par locataire (`loki.tenants`) : vraie authentification, mais des mots de passe statiques par locataire à distribuer à Alloy et à Grafana ; remplacée au M24 par une passerelle OIDC.
- TLS sur Loki lui-même (`server.http_tls_config`, certificat cert-manager) dès maintenant : chiffre le transport depuis les VMs, mais oblige à distribuer la CA à tous les agents et ne résout pas l'authentification.
- Une instance de Grafana dédiée à la sécurité plutôt qu'une organisation : plus étanche, plus coûteuse.
- *Object Lock* (WORM) du RGW pour l'audit : protège contre l'effacement, mais un seul compartiment partagé avec la rétention des autres locataires rendrait la rétention impossible ; il faudrait un compartiment (donc un Loki) dédié à l'audit (piste pour F5/F6).
- Réplication du compartiment vers PAR2 (synchronisation multisite du RGW ou `rclone sync` planifié) : la vraie sauvegarde hors site ; demande un RGW ou un S3 sur PAR2.

**Pièges classiques**
- Ajouter une politique restrictive sans retirer une ancienne politique plus large (règles additives).
- Oublier l'entité `host` dans une politique qui la remplace : les sondes du kubelet échouent, `loki-0` redémarre en boucle (Cilium autorise l'hôte local par défaut, mais pas si l'option `policy-allow-localhost` du cluster a été durcie : l'écrire évite la surprise).
- Oublier la sortie vers le RGW **par sa VIP** (10.10.30.200) : le trafic des pods sort par `eth1` des travailleurs, mais la politique voit l'adresse de destination ; ou oublier l'API Kubernetes pour le conteneur `sidecar` des règles : les nouvelles règles du *ruler* ne sont plus recopiées.
- Restreindre Grafana à `GET` seulement : certaines requêtes partent en `POST` (requêtes longues) ; regarder `hubble observe --type l7 --verdict DROPPED` après avoir ouvert un tableau et l'explorateur.
- Retirer la source de l'audit de `sources-loki.yaml` sans `deleteDatasources` : elle reste dans l'organisation principale.
- Activer le versionnage sans règle de cycle de vie : le compartiment ne rétrécit plus jamais (chaque suppression du compactor devient une version non courante).

**En production chez MédiSphère**
Les politiques réseau sont relues comme du code (MR, rendu `kustomize build` et `kubeconform` en CI) ; un test périodique depuis `wb-essais` vérifie que Loki **ne répond pas** ; la RSSI reçoit chaque trimestre la liste des membres de l'organisation Sécurité ; la restauration d'un objet versionné est répétée une fois par an.

---

### M22-E17 — ADR : l'architecture des journaux

**Solution**

Exemple : [`ADR-0220-architecture-journaux.md`](fichiers/M22-E17/medisphere/docs/observabilite/journaux/adr/ADR-0220-architecture-journaux.md). Les chiffres de l'exemple sont ceux d'un lab de référence : l'ADR de l'apprenant doit citer **ses** mesures (E13, E14, E15, E10).

**Grille d'auto-évaluation**

| Critère | Attendu |
|---|---|
| Contexte chiffré | volume par jour et par locataire, flux actifs, mémoire disponible |
| Exigences | durées par locataire avec leur source (HDS, RGPD, exploitation), effacement, souveraineté |
| Décision précise | versions, mode de déploiement, stockage, locataires, collecteur unique, masquage à la collecte |
| Options écartées | chacune avec une raison **vérifiable** ; Promtail écarté pour sa fin de vie (2 mars 2026) ; SimpleScalable pour sa dépréciation |
| Limites acceptées | pas de HA de Loki, en-tête falsifiable (M24), pas de copie hors site (F5), compactor unique |
| Révision | un déclencheur mesurable |

**Explications** : un ADR n'est pas un dossier de comparaison ; il fixe une décision et ce qu'on accepte en la prenant. Les limites acceptées sont ce que le comité relit en premier : une décision sans limite écrite est une décision dont personne n'a mesuré le prix.

**Pièges classiques** : copier le comparatif d'E15 dans l'ADR (trop long, il se lie) ; écarter Fluent Bit « parce qu'Alloy est mieux » sans critère ; oublier le statut et la date.

**En production chez MédiSphère** : l'ADR est présenté au comité d'architecture, son statut passe à « Accepté » avec la date ; il est référencé par la politique des journaux et par le runbook de reconstruction.

---

### M22-E18 — Questions de production : journaux

1. **Rétention passée de 30 à 7 jours, lundi à 10 h.** Argo CD synchronise ; le changement ne touche que `runtimeConfig` (surcharge du locataire) : pas de redémarrage, prise en compte en ~1 min. Au passage suivant du compactor (≤ 10 min), l'index de `mediagenda` est réécrit **sans** les chunks de plus de 7 jours, ces chunks sont marqués ; ils sont **supprimés** du compartiment `retention_delete_delay` plus tard (2 h). À 11 h : un revert remet 30 jours, mais l'index a déjà été réécrit : les chunks marqués seront supprimés quand même, et les références ont disparu de l'index — la fenêtre de 2 h protège surtout contre une suppression **effective** qu'on aurait le temps d'arrêter en arrêtant le compactor ; en pratique, la récupération passe par le versionnage (index et chunks). À 14 h : les chunks sont supprimés ; sans versionnage, c'est perdu ; avec le versionnage d'E16 (7 jours), on restaure les versions (procédure de la politique, § 4). Ce qu'il fallait : versionnage, relecture des MR de rétention par deux personnes, alerte sur la chute brutale du nombre d'objets.
2. **`request_id` en étiquette.** Chaque requête crée un **nouveau flux** : des milliers de flux par heure pour MédiAgenda, chacun avec un chunk d'une ou deux lignes ; l'ingester garde un chunk en tête par flux actif (mémoire), l'index TSDB grossit d'une série par flux, `max_global_streams_per_user` (2 000) est atteint en quelques minutes et les **nouveaux** flux sont refusés : on perd justement les journaux récents. À la place : `request_id` en **métadonnée structurée** (M22-E06), interrogée par `{namespace="mediagenda-prod"} | request_id="…"` — le sélecteur borne la lecture, le filtre sur métadonnée est peu coûteux.
3. **429.** Alloy (`loki.write`) traite le 429 comme récupérable (`retry_on_http_429: true` par défaut) : il réessaie avec un recul exponentiel de 500 ms à 5 min, 10 fois au plus (`max_backoff_retries`), soit plusieurs minutes ; pendant ce temps, le lot est bloqué et les suivants s'accumulent en mémoire. Après le dernier essai, le lot est **abandonné** (lignes perdues). Côté Alloy : `loki_write_batch_retries_total`, `loki_write_dropped_entries_total` (et les journaux d'Alloy) ; côté Loki : `loki_discarded_samples_total{reason="rate_limited", tenant="mediagenda"}` et le message `ingestion rate limit exceeded for user mediagenda (limit: … bytes/sec)`.
4. **Volume de `loki-0`.** Il porte le **WAL** de l'ingester (tout ce qui est reçu et pas encore vidé en chunks, jusqu'à 2 h), l'index TSDB actif (avant téléversement), le répertoire du compactor (marques de rétention, demandes) et le WAL du *ruler*. Volume détruit pendant que le pod tourne : le processus échoue en écriture, redémarre sans WAL : perte de tout ce qui n'était pas vidé (≤ 2 h) et des marques en cours (chunks orphelins, non supprimés). Pendant un arrêt propre : `flush_on_shutdown: true` vide les chunks au stockage avant l'arrêt, donc presque rien n'est perdu ; seules les marques non traitées du compactor manquent.
5. **Trois réglages.** `retention_period` : durée de vie dans le stockage — trop court, les données sont **réellement** supprimées (perte). `max_query_lookback` : jusqu'où une requête peut remonter — trop court, les journaux « disparaissent » de Grafana alors qu'ils sont **toujours** dans le compartiment (aucune perte, réversible). `reject_old_samples_max_age` : âge maximal accepté à l'**écriture** — trop court, des lignes en retard (agent qui rattrape après une panne, horloge décalée) sont refusées à l'entrée et **jamais** stockées (perte de ces lignes-là).
6. **Effacement à 9 h.** À 9 h 05 : la ligne n'est **plus** renvoyée (filtrage à la lecture dès que les requêteurs connaissent la demande) ; elle est toujours dans le compartiment. Elle devient irréversible après le délai d'annulation (24 h) et le passage du compactor qui réécrit les chunks concernés ; avec le versionnage, les anciennes versions des chunks restent 7 jours (à purger sur décision si la fuite est grave). Trace : la demande (identifiant, requête, fenêtre, statut `processed`) dans la liste des demandes du locataire, et le ticket.
7. **Compactor unique.** Il réécrit l'index de chaque journée et supprime des chunks : deux compactors qui travaillent sur la même table se marchent dessus (index écrasé par une version qui ne contient pas les modifications de l'autre, suppressions concurrentes, marques perdues). Dans Loki réparti, l'anneau du compactor élit **un** compactor. Deux pods `Monolithic` sans anneau commun (deux releases sur le même compartiment) auraient chacun leur compactor et leur ingester : index corrompu ou incohérent, doublons, rétention appliquée deux fois — à proscrire.
8. **Audit à 70 %.** Leviers : (a) affiner la politique d'audit de l'API (M14-E27) — `None` pour les lectures en boucle des contrôleurs connus, `Metadata` au lieu de `Request` pour les objets volumineux ; (b) supprimer dans Alloy les champs sans valeur de preuve (`managedFields`, `requestObject` des objets non sensibles) avant l'envoi ; (c) ne garder 1 an que les **écritures** et les accès sensibles, les lectures 30 jours (`retention_stream` sur une étiquette `job` distincte). Refusé : échantillonner l'audit (une preuve échantillonnée n'est plus une preuve) ou raccourcir la rétention sous l'exigence HDS.
9. **Limite de flux.** Les flux **existants** continuent d'être acceptés ; ce sont les **nouveaux** flux qui sont refusés (`maximum active stream limit exceeded when trying to create stream …`). Symptôme : les journaux des pods qui viennent de (re)démarrer n'arrivent pas, ceux qui tournent depuis longtemps oui — exactement les journaux qu'on cherche pendant un incident (nouveau déploiement, crash). Pire qu'une limite de débit : silencieux et sélectif, il touche les nouveautés et ne se « rattrape » pas quand le débit baisse.
10. **Chaîne rare sur 30 jours.** OpenSearch : une recherche dans l'index inversé, quelques millisecondes à secondes quel que soit le volume. Loki sans sélecteur précis : lecture et décompression de **tous** les chunks de 30 jours (des Go), plusieurs minutes, bornée par `query_timeout`. Organisation qui rend Loki raisonnable : l'identifiant en métadonnée structurée **et** un sélecteur qui borne (espace, application), des fenêtres courtes successives (`logcli --parallel-duration`), et à grande échelle les *bloom filters*. Si ce besoin est fréquent et métier, c'est un argument pour un index plein texte dédié — pas pour les journaux techniques.
11. **Alloy arrêté 20 minutes.** Journaux des pods : écrits par le runtime dans `/var/log/pods/…` ; au redémarrage, Alloy reprend à la **position** enregistrée dans son fichier de positions (sur un volume `hostPath` persistant, pas un `emptyDir`) : rien n'est perdu tant que kubelet n'a pas fait tourner et supprimé les fichiers entre-temps (`containerLogMaxSize`, `containerLogMaxFiles`). journald : Alloy reprend au curseur enregistré, dans la limite de `max_age` (7 h par défaut) et de ce que journald a gardé. Dépend donc du **fichier de positions persistant**, de la **rotation des journaux du kubelet** et de `max_age`.
12. **VM compromise.** La règle HTTP autorise une VM à **pousser** dans n'importe quel locataire (l'en-tête est libre) ; elle bloque la lecture depuis les VMs, mais pas depuis MGMT ni depuis Grafana. Une VM compromise peut donc polluer `audit` (fausses lignes) ; si elle atteint MGMT ou un compte Grafana, elle lit tout. Il faut une **authentification** à Loki : passerelle qui vérifie une identité (certificat client par VM, jeton OIDC) et **impose** l'en-tête correspondant — c'est le M24 (Keycloak), avec mTLS pour les agents.
13. **RGW indisponible 15 min.** Écritures : acceptées dans l'ingester (mémoire + WAL) ; les vidages de chunks échouent et sont réessayés (`loki_ingester_chunks_flush_failures_total` monte) ; risque mémoire si cela dure. Requêtes sur la dernière heure : servies par l'ingester (`query_ingesters_within`), elles fonctionnent pour l'essentiel. Requêtes sur hier : besoin de l'index et des chunks du stockage, elles échouent (erreurs 500). Alertes, dans l'ordre : sonde du RGW (supervision de Ceph, M21), puis échecs de vidage de Loki, puis erreurs de requêtes ; et pas d'alerte « plus de journaux » (la collecte continue) — ce qui serait trompeur.
