# Module 23 — Traces et profilage

| | |
|---|---|
| **Bloc** | E — Observabilité |
| **Niveau** | Secondaire |
| **Profil de lab** | Socle v4 + `ceph-par1` + `k8s-par1` ; Jaeger temporaire le temps de E15 |
| **Prérequis** | Module 22 (`journaux-v1`) et module 21 (`metriques-v1`) ; module 12 (applications MédiAgenda en Python et MédiDoc en Go) ; module 19 (pipelines des applications) |
| **Durée indicative** | 35 à 45 heures (palier 1 : 7-9 h ; palier 2 : 11-14 h ; palier 3 : 9-11 h ; palier 4 : 6-8 h ; mini-projet : 4-6 h) |

## Contexte MédiSphère

Les métriques disent que la prise de rendez-vous est lente ; les journaux disent qu'il y a eu des erreurs ; personne ne sait **où** passe le temps entre la passerelle, l'API MédiAgenda, PostgreSQL, Valkey et MédiDoc. Julien Petit propose d'instrumenter les applications avec **OpenTelemetry** ; Claire Morel veut une solution ouverte, sans dépendance à un éditeur, et une corrélation en un clic entre une alerte, la trace de la requête fautive et ses journaux. Karim Benali veut aussi voir le **profil** CPU et mémoire de l'API quand elle sature.

## Objectifs

À la fin de ce module, tu sais :
- déployer l'**OpenTelemetry Operator** et des Collectors (passerelle et agents), et construire leurs pipelines ;
- instrumenter une application Python et une application Go (SDK, propagation W3C, attributs, conventions sémantiques), et comparer avec l'auto-instrumentation ;
- stocker et interroger les traces avec **Tempo** (TraceQL), en tirer des métriques et des graphes de services ;
- relier métriques, journaux et traces (exemplars, `trace_id`), échantillonner sans perdre l'essentiel ;
- profiler en continu avec **Pyroscope** et comparer Tempo avec **Jaeger** ;
- diagnostiquer des traces absentes, coupées ou perdues.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M23-E01 | Test de positionnement : traces distribuées | Q | ★★ | 1 |
| M23-E02 | L'opérateur OpenTelemetry et le Collector | LAB | ★★ | 1 |
| M23-E03 | Tempo sur le RGW | LAB | ★★ | 1 |
| M23-E04 | Instrumenter MédiAgenda avec le SDK Python | LAB | ★★ | 1 |
| M23-E05 | Explorer les traces dans Grafana : TraceQL | LAB | ★★ | 1 |
| M23-E06 | Instrumenter MédiDoc avec le SDK Go | LAB | ★★★ | 2 |
| M23-E07 | L'auto-instrumentation par l'opérateur, en comparaison | LAB | ★★ | 2 |
| M23-E08 | Corrélation : exemplars, `trace_id` dans les journaux, liens Grafana | LAB | ★★★ | 2 |
| M23-E09 | Échantillonnage en tête et en queue | LAB | ★★★ | 2 |
| M23-E10 | Les pipelines du Collector : processeurs et données sensibles | LIBRE | ★★★ | 2 |
| M23-E11 | Revue : la configuration du Collector du stagiaire | REV | ★★ | 2 |
| M23-E12 | Trouver où passe le temps | LAB | ★★★ | 2 |
| M23-E13 | Métriques tirées des traces : graphes de services et RED | LAB | ★★★ | 3 |
| M23-E14 | Profilage continu avec Pyroscope | LAB | ★★★ | 3 |
| M23-E15 | Jaeger v2 en comparaison | LAB | ★★ | 3 |
| M23-E16 | Capacité, rétention et sécurité de la chaîne de traces | LAB | ★★★ | 3 |
| M23-E17 | ADR : traces et profilage | RED | ★★ | 3 |
| M23-E18 | Questions de production : traces et profilage | Q | ★★★ | 3 |
| M23-E19 | Panne : plus aucune trace | BF | ★★ | 4 |
| M23-E20 | Panne : les traces sont coupées en morceaux | BF | ★★★ | 4 |
| M23-E21 | Panne : le Collector perd des données | BF | ★★★ | 4 |
| M23-E22 | Panne : impossible de passer d'une trace à ses journaux | BF | ★★ | 4 |
| M23-E23 | Astreinte : l'API est lente | BF | ★★★★ | 4 |
| M23-E24 | Sous le capot : spans, contexte et OTLP | LAB | ★★★★ | 4 |
| M23-E25 | Mini-projet : l'observabilité de MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 5 break & fix · 2 questionnaires · 1 revue · 1 rédaction.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| OpenTelemetry Operator | espace `opentelemetry-operator-system`, Application Argo CD | Collectors et instrumentation | E02 |
| `otel-passerelle`, agents | espace `traces` ; OTLP hors cluster par 10.10.41.63:4317/4318 | Réception, traitement, export | E02 |
| Tempo 3.1 | espace `traces`, compartiment RGW `tempo-k8s-par1` | Stockage des traces, metrics-generator | E03, E13 |
| Pyroscope 2.4 | espace `traces`, compartiment RGW `pyroscope-k8s-par1` | Profilage continu | E14 |
| Jaeger 2 | espace `jaeger-essai` | Comparaison, **retiré** | E15 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.11. Versions : [`annexes/versions-bloc-DE.md`](../../annexes/versions-bloc-DE.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 23 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 23 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
