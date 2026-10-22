# Sous le capot : spans, contexte et OTLP (M23-E24)

> Exemple du corrigé, produit avec les ressources de `ressources/E24-capot/` (Collector local, `emettre.py`) et
> un bloc copié de `tempo-k8s-par1`. Tes identifiants seront différents.

## 1. Le contexte qui voyage : `traceparent`

En-tête injecté par le client et reçu par le serveur :

```
traceparent: 00-aa45eabe74b3b8489c204ba341c2953a-cc60fb210cd0a832-03
```

| Champ | Valeur | Sens |
|---|---|---|
| version | `00` | seule version définie par W3C Trace Context |
| trace-id | `aa45eabe74b3b8489c204ba341c2953a` | 16 octets (32 hexadécimaux), commun à toute la trace |
| parent-id | `cc60fb210cd0a832` | 8 octets : la span **client** qui a fait l'appel, parent de la span serveur |
| drapeaux (*trace-flags*) | `03` | bit 0 *sampled* (la trace est échantillonnée) ; bit 1 *random* (Trace Context niveau 2 : les 7 octets de droite du trace-id sont aléatoires, utile à l'échantillonnage cohérent) |

`tracestate` (absent ici) porte des données propres à un fournisseur (ex. le seuil d'échantillonnage OpenTelemetry `ot=th:…`) ; `baggage` porte des paires clé-valeur applicatives — à proscrire pour toute donnée de santé, car le baggage traverse **tous** les services en clair.

Piège rencontré : le serveur extrayait le contexte d'un `dict` construit depuis les en-têtes HTTP, avec la casse d'origine (`Traceparent`) ; le lecteur par défaut d'un dict cherche `traceparent` : pas de contexte, le serveur a ouvert une **nouvelle** trace (trace-id différent). Corrigé en mettant les clés en minuscules.

## 2. Ce que reçoit un Collector : le message OTLP

Collecté par l'exportateur `file` du Collector local (format JSON d'OTLP), réduit avec `jq` :

```json
{"svc":"capot-client","spans":[
  {"traceId":"aa45eabe74b3b8489c204ba341c2953a","spanId":"cc60fb210cd0a832","parentSpanId":"5e4230c82c3ce166","name":"GET","kind":3},
  {"traceId":"aa45eabe74b3b8489c204ba341c2953a","spanId":"5e4230c82c3ce166","parentSpanId":"","name":"traitement","kind":1}]}
{"svc":"capot-serveur","spans":[
  {"traceId":"aa45eabe74b3b8489c204ba341c2953a","spanId":"188f1eb231e5b26f","parentSpanId":"cc60fb210cd0a832","name":"GET /capot","kind":2}]}
```

Structure : `resourceSpans[]` (une **ressource** = un processus émetteur : `service.name`, `deployment.environment.name`…) → `scopeSpans[]` (une **portée** d'instrumentation : bibliothèque et version) → `spans[]`. Les attributs de ressource ne sont envoyés qu'une fois par lot, pas à chaque span. `kind` : 1 interne, 2 serveur, 3 client (4 producteur, 5 consommateur). Les identifiants sont en **hexadécimal** dans l'encodage JSON d'OTLP (exception à la règle protobuf → JSON, qui les mettrait en base64) ; sur le fil, en OTLP/gRPC ou OTLP/HTTP protobuf, ce sont des octets bruts. Une span ne connaît que son parent : l'arbre est reconstruit par Tempo et Grafana.

## 3. Le chemin d'une span jusqu'au compartiment

SDK (processeur de lots : 512 spans ou 5 s) → agent du nœud (OTLP gRPC) → passerelle (échantillonnage en queue après `decision_wait` de 10 s) → distributeur de Tempo → **live-store** (traces récentes en mémoire et dans son WAL sur le volume `/var/tempo` ; c'est lui qui répond aux recherches des dernières minutes) → bloc écrit dans le RGW (au plus tard après `complete_block_timeout`) → compaction et rétention par l'ordonnanceur et les travailleurs du *backend* (14 jours).

## 4. Un bloc Tempo, lu avec tempo-cli

Copie en lecture d'un bloc (`ressources/E24-capot/tempo-cli-local.sh`) :

```
admin@adm01:~/m23/e24$ ls copie/single-tenant/ef1a946a-cdf8-4b6b-bbe1-cf5caa08131c
bloom-0  data.parquet  index  meta.json
admin@adm01:~/m23/e24$ tempo-cli list blocks single-tenant --backend local --bucket copie
│ ef1a946a-cdf8-4b6b-bbe1-cf5caa08131c │ 0 │ 3 │ 26 kB │ vParquet5 │ … │
```

| Fichier | Rôle |
|---|---|
| `meta.json` | description du bloc : format (`vParquet5`), début et fin, nombre de traces (`totalObjects`), taille, niveau de compaction, colonnes dédiées |
| `data.parquet` | les traces, en colonnes (une ligne Parquet par **trace**, les spans imbriquées dedans) |
| `bloom-0` | filtre de Bloom des identifiants de trace : « cette trace n'est sûrement pas dans ce bloc » sans lire `data.parquet` |
| `index` | index des groupes de lignes par identifiant de trace (recherche par identifiant) |

`tempo-cli view schema …` montre le schéma : au niveau de la trace, `TraceID`, `RootServiceName`, `RootSpanName`, `DurationNano`, `ServiceStats` (spans et erreurs par service : de quoi répondre à des requêtes sans descendre aux spans) ; puis `rs` (ressources) → `ss` (portées) → `Spans`, avec des **colonnes dédiées** pour les attributs fréquents (`http.request.method`, `http.response.status_code`, `url.path`, `k8s.namespace.name`…) et une liste générique clé-valeur pour les autres. Lire une colonne dédiée coûte une seule colonne Parquet ; un attribut générique oblige à parcourir la liste : c'est pourquoi les requêtes TraceQL sur des attributs dédiés sont plus rapides.

`tempo-cli query trace-summary <trace-id> single-tenant --backend local --bucket copie` : nombre de blocs qui contiennent la trace, nombre de spans, taille, durée, service et span racines.
