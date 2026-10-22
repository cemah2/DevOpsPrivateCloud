# ADR-0230 — Traces distribuées et profilage continu

- **Statut** : accepté (comité d'architecture du 2026-11-05)
- **Décideurs** : Claire Morel, Karim Benali, Sophie Laurent ; consultés : Julien Petit, Nadia Roussel
- **Contexte lié** : ADR-0210 (métriques), ADR-0220 (journaux), PLAN §4.11

## Contexte

Les métriques (M21) disent qu'une requête est lente, les journaux (M22) qu'une erreur a eu lieu ; personne ne sait **où** passe le temps entre la Gateway, MédiAgenda, PostgreSQL, Valkey et MédiDoc. MédiSphère héberge des données de santé (HDS) : aucune donnée ne doit sortir de nos salles, ni aller chez un éditeur. Volumes mesurés : ≈ 2 Go/jour reçus par Tempo après échantillonnage, ≈ 1,5 Go/jour stockés (M23-E16) ; surcoût du profilage de MédiAgenda ≈ 5 % de CPU (M23-E14).

## Décision

Nous instrumentons nos applications avec **OpenTelemetry dans le code** (SDK Python et Go, conventions sémantiques, propagation W3C), collectons par des **agents par nœud et une passerelle** OpenTelemetry Collector (échantillonnage **en queue**, masquage des données sensibles, équilibrage par `traceID`), stockons les traces dans **Tempo** sur le RGW de `ceph-par1` (14 jours) et les profils dans **Pyroscope** (14 jours), et corrélons les quatre signaux dans **Grafana**.

## Options écartées

| Option | Ce qu'elle avait pour elle | Pourquoi écartée |
|---|---|---|
| Jaeger 2 (M23-E15) | CNCF *graduated*, simple, très répandu | Exige un magasin à exploiter (OpenSearch ou Cassandra, écartés au M22) ; pas de requête structurelle ; liens avec métriques et profils plus pauvres. Réversible : l'instrumentation OpenTelemetry ne change pas |
| Auto-instrumentation par l'opérateur en production (M23-E07) | Zéro ligne de code | Conteneur d'initialisation et image d'instrumentation à suivre en sécurité ; spans génériques sans attributs métier ; risque de double instrumentation ; garde-fous sur les données de santé impossibles à revoir dans le code |
| Échantillonnage seulement en tête | Simple, pas d'état dans la passerelle | On perd la plupart des traces d'erreurs et des lentes (M23-E09), exactement celles qui servent |
| Solution d'éditeur en SaaS | Support, fonctions avancées | Données de santé hors de nos salles (HDS, souveraineté) ; coût proportionnel au volume |
| OBI / Beyla (eBPF) | Instrumentation sans code, y compris pour Legacy-RDV | OBI 0.15 sans statut stable, privilèges élevés sur les nœuds : **en veille**, réévalué au M26 |
| Span metrics avant échantillonnage (connecteur `spanmetrics`) | RED exact depuis les traces | Les métriques applicatives donnent déjà un RED exact ; coût en séries et en mémoire de la passerelle (M23-E13) |

## Conséquences

- Chaque équipe instrumente et revoit ses attributs selon `conventions-telemetrie.md` ; la plateforme fournit le composant kustomize `telemetrie` et les Collectors.
- Données de santé : aucun identifiant de patient, aucun paramètre SQL ni en-tête d'authentification dans une span (masquage dans la passerelle, M23-E10 ; contrôle au mini-projet) ; rétention limitée à 14 jours ; accès par Grafana seulement (équipes, M21-E17 ; SSO au M24).
- Dépendance à la pile Grafana (Tempo, Pyroscope, Alloy, Grafana) : même famille que Loki ; licence AGPL acceptée pour un usage interne.
- Le point d'entrée externe 10.10.41.63 est en TLS avec un jeton par émetteur (M23-E16) ; flux internes encore en clair (M24-M26).
- Coûts : ≈ 2 Go de mémoire permanents (Tempo, Pyroscope, Collectors) et ≈ 50 Go de RGW (quotas).

## Critères de révision

- Volume reçu par Tempo au-delà de 10 Go/jour, ou passage nécessaire en mode microservices (Kafka obligatoire en Tempo 3).
- OBI stable et compatible avec notre politique de durcissement des nœuds (M26).
- Évolution de licence ou de support de Tempo ou de Pyroscope.
