<!-- À AJOUTER à docs/kubernetes/reseau/matrice-flux-cluster.md (M27-E14, M27-E15) -->
| Source | Destination | Port | Motif | Réf. |
|---|---|---|---|---|
| `supervision/prometheus` | `messagerie/rabbitmq` | 15692/TCP (GET `/metrics`, `/metrics/detailed`) | collecte RabbitMQ | M27-E14 |
| `supervision/prometheus` | `mediagenda-*/mediagenda-db-pooler-rw` | 9127/TCP | collecte PgBouncer | M27-E14 |
| `supervision/prometheus` | `mediagenda-secours/mediagenda-db-secours` | 9187/TCP | collecte du réplica de secours | M27-E15 |
| `mediagenda-secours/mediagenda-db-secours` | `s3-01` 10.10.20.14 | 8333/TCP | lecture de l'archive des WAL | M27-E15 |
| `messagerie/export-definitions` | `messagerie/rabbitmq` | 15671/TCP | export nocturne des définitions | M27-E15 |
| `messagerie/export-definitions` | `s3-01` 10.10.20.14 | 8333/TCP | dépôt des définitions (`messagerie-definitions`) | M27-E15 |
