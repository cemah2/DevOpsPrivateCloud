# Conformité des traces et des profils (M23-E25)

> Exemple du corrigé : requêtes rejouables, résultats datés. Rejouer avant chaque audit et après chaque
> changement d'instrumentation ou de la configuration des Collectors.

Contrôles exécutés le **2026-11-12** sur **24 h** (Grafana → Explore → Tempo, puis Loki), dans les trois environnements :

| Contrôle | Requête | Résultat |
|---|---|---|
| Spans de sonde | `{span.http.route =~ "/(sante\|pret\|healthz\|readyz\|metrics)" \|\| span.url.path =~ "/(sante\|pret\|healthz\|readyz\|metrics)"}` | 0 trace |
| Identité de patient | `{span.patient != nil \|\| span.enduser.id != nil \|\| span.mediagenda.patient != nil}` | 0 trace |
| Paramètres SQL en clair | `{span.db.query.text =~ ".*'[^?'][^']*'.*" \|\| span.db.statement =~ ".*'[^?'][^']*'.*"}` | 0 trace (littéraux remplacés par `'?'` par l'agent, M23-E10) |
| Paramètres d'URL | `{span.url.query != nil \|\| span.url.full =~ ".*[?].*"}` | 0 trace |
| En-têtes d'authentification | `{span.http.request.header.authorization != nil \|\| span.http.request.header.cookie != nil}` | 0 trace |
| Masquages par motif (filet) | `{span.redaction.masked.count > 0}` | 3 traces le 2026-11-11 (MédiDoc dev, nom de fichier contenant une adresse de courriel) : ticket DEV-2462 ouvert à l'équipe MédiDoc |
| Journaux | `{namespace=~"mediagenda-.*"} \|~ "[12][0-9]{2}(0[1-9]\|1[0-2])[0-9]{8}"` (locataire mediagenda) | 0 ligne |
| Profils | étiquettes des profils (`service_name`, `version`, `environnement`, `namespace`, `pod`) : aucune donnée métier | conforme |

Rétention vérifiée : Tempo `block_retention: 336h`, Pyroscope `retention_period: 14d` ; quotas RGW `tempo` 50 Go, `pyroscope` 10 Go. Accès : Grafana seulement (équipes `plateforme`, `mediagenda`, `medidoc`), aucune exposition de Tempo ni de Pyroscope hors du cluster.
