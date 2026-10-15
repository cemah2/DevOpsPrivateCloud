# Bascules et mises à jour de PostgreSQL (CloudNativePG) — compte rendu M16-E25

| | |
|---|---|
| Date | <AAAA-MM-JJ> |
| Cluster | `mediagenda-db` (`mediagenda-recette`, 3 instances, PostgreSQL 18.x, `ceph-rbd`) ; essais `pg-essai`, `pg-essai-import` (`wb-essais`) |
| Témoin | `outils/temoin-api.sh` (1 création par seconde par l'API publiée) |
| Versions | CloudNativePG 1.30.x, plugin Barman Cloud 0.15.x, Kubernetes 1.36.x |

## État initial

Primaire `<POD>` sur `<NŒUD>`, timeline `<N>`, réplicas `<POD>`/`<POD>` (retard `<N>` octets), PDB `mediagenda-db` (`minAvailable` …) et `mediagenda-db-primary`, bail `mediagenda-db` détenu par `<POD>`.

## Opérations

| Heure | Opération | Indisponibilité vue par le témoin | Échecs | Rendez-vous acquittés perdus | Nouvelle timeline | Observations |
|---|---|---|---|---|---|---|
| | Bascule planifiée (`kubectl cnpg promote`) | | | 0 | | |
| | Bascule sur panne (suppression forcée du primaire) | | | | | trace `pg_rewind` : « … » |
| | Isolement d'un réplica | 0 | 0 | 0 | — | Service `-ro` : … |
| | Mise à jour supervisée (`max_connections`) + promotion manuelle | | | | | |
| | `pg-essai` 17.10 → 17.11 | | | — | | |
| | `pg-essai-import` (import vers 18.6) | source disponible pendant l'import | — | — | — | durée de l'import : … |
| | `pg-essai` 17.11 → 18.6 en place | **tout le cluster** arrêté | — | — | timeline 1 | Job `pg-essai-1-major-upgrade` … |

## Comparaison des montées majeures

| Critère | Import (`initdb.import`) | En place (`pg_upgrade --link`) |
|---|---|---|
| Indisponibilité | aucune pour la source ; bascule de l'application vers le nouveau cluster à organiser (écritures à geler pendant la copie, ou réplication logique) | tout le cluster, pendant le Job et le reclonage des réplicas |
| Durée | proportionnelle aux données (dump + restore + index) | quasi indépendante du volume (liens physiques) + reclonage |
| Espace | double (deux clusters) | faible pendant `pg_upgrade --link` |
| Retour arrière | l'ancien cluster est intact | revenir à l'ancienne image tant que le Job a échoué ; après succès : sauvegarde |
| Archive WAL | nouveau `serverName` (nouveau cluster) | **nouveau système** (nouvel identifiant, timeline 1) : changer le `serverName` du plugin au même moment, faire une sauvegarde de base aussitôt |

## Décisions

- Recette : `primaryUpdateStrategy: supervised` (raison : …).
- Montée majeure de `mediagenda-db` (quand elle viendra) : … (raison : …).
