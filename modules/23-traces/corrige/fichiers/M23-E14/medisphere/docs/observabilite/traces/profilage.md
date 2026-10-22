# Profilage continu (M23-E14)

> Document d'exemple du corrigé : les mesures sont celles d'un lab de référence, remplace-les par les tiennes.

## Ce qui est en place

| Application | Mode | Profils | Nom (`service_name`) |
|---|---|---|---|
| MédiAgenda (Python) | *push* : SDK `pyroscope-io` 1.4 dans le processus, vers `pyroscope.traces.svc:4040` | CPU (*on-CPU*, fils qui tiennent le GIL) | `mediagenda-api` |
| MédiDoc (Go) | *pull* : `net/http/pprof` + `godeltaprof` sur le port interne 6060, collectés par Alloy (`pyroscope.scrape`) | CPU, mémoire (delta), verrous, blocages, goroutines | `medidoc` |

Pyroscope 2.4 monolithique, compartiment `pyroscope-k8s-par1`, rétention 14 jours. Lien trace → profil : `tracesToProfiles` de la source Tempo (même `service_name`, même période) ; pour MédiAgenda, `pyroscope-otel` pose `pyroscope.profile.id` sur la span racine.

## Lire un flame graph

- **Largeur** = part des échantillons (donc du temps CPU) où la fonction est sur la pile. L'ordre gauche-droite est alphabétique, il ne dit rien du temps.
- **Hauteur** = profondeur d'appel. Une tour haute et étroite n'est pas un problème ; un **plateau large** en haut d'une pile (temps propre, *self*) en est un.
- Commencer par le *top table* trié par temps propre, puis remonter les appelants dans le graphe.
- Toujours comparer : la vue *diff* (période lente contre période normale) montre ce qui a grossi.

Lecture sous charge (recette, 40 req/s pendant 15 min) :

| Pile | Part du CPU | Lecture |
|---|---|---|
| `uvicorn` → `starlette` → `fastapi` → sérialisation `pydantic` (`model_dump_json`, validation) | 31 % | coût du modèle de réponse de `/api/v1/creneaux` (une liste de 16 dates par réponse) |
| `psycopg` (envoi, lecture, conversion des `timestamptz`) | 18 % | conversion des dates côté client |
| `calculer_creneaux` (boucle des créneaux, `datetime.combine`, comparaison dans l'ensemble) | 9 % | normal |
| exportation OpenTelemetry (`BatchSpanProcessor`, protobuf) | 6 % | coût de l'instrumentation des traces |
| `pyroscope` / `rbspy` | 2 % | coût du profileur lui-même |
| attente du GIL, `ssl`, journalisation JSON | reste | |

## Surcoût mesuré (recette, 40 req/s, 15 min, même version)

| | Sans profileur | Avec profileur (100 Hz) |
|---|---|---|
| CPU moyen par pod (`container_cpu_usage_seconds_total`) | 182 m | 191 m (+5 %) |
| Mémoire (RSS) | 148 Mio | 163 Mio (+15 Mio) |
| Latence p95 de l'API | 41 ms | 42 ms |

MédiDoc : une collecte CPU de 15 s par minute et par pod, surcoût non mesurable à ce trafic (< 1 % CPU).

## Ce qu'un profil CPU ne montre pas

- Le temps passé à **attendre** : base de données, Valkey, MédiDoc, DNS, verrous de PostgreSQL. Un gestionnaire qui attend 800 ms une requête SQL n'apparaît presque pas dans un profil *on-CPU* : c'est la **trace** (span `INSERT`) qui le montre.
- L'**étranglement CPU** (quota CFS) : le profil montre la même répartition, simplement plus lentement ; ce sont les métriques `container_cpu_cfs_throttled_periods_total` qui le montrent.
- Les spans plus courtes que l'intervalle d'échantillonnage (10 ms à 100 Hz).

## Limites connues

- Lien span → profil pour MédiAgenda : `pyroscope-otel` étiquette les échantillons du **fil** qui a démarré la span racine. FastAPI exécute les gestionnaires déclarés avec `def` dans un réservoir de fils : la span racine (intergiciel ASGI) démarre dans la boucle d'événements, le travail se fait ailleurs. Le lien fonctionne pour les gestionnaires `async def`, mal pour les autres : on utilise surtout le lien par service et par période.
- Le profileur Python n'est pas sûr après un `fork` : MédiAgenda tourne avec un seul processus uvicorn par pod (pas de `--workers`).
