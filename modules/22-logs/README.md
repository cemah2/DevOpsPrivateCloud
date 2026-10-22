# Module 22 — Journaux

| | |
|---|---|
| **Bloc** | E — Observabilité |
| **Niveau** | Secondaire |
| **Profil de lab** | Socle v4 + `ceph-par1` + `k8s-par1` ; OpenSearch temporaire (≈ 3 Go) le temps de E15 |
| **Prérequis** | Module 21 (`metriques-v1` : Grafana, Alertmanager, `plateforme/observabilite`) ; module 14 (journal d'audit de l'API, M14-E27) ; module 20 (Argo CD) |
| **Durée indicative** | 35 à 45 heures (palier 1 : 7-9 h ; palier 2 : 10-13 h ; palier 3 : 9-11 h ; palier 4 : 6-8 h ; mini-projet : 4-6 h) |

## Contexte MédiSphère

Quand MédiAgenda renvoie une erreur 500, Julien Petit demande « les logs » ; on lui répond par un `kubectl logs` sur un pod déjà remplacé, ou par un `journalctl` sur la bonne VM, si quelqu'un se souvient laquelle. Sophie Laurent, elle, doit pouvoir prouver à l'auditeur HDS qui a fait quoi sur l'API Kubernetes il y a six mois, et s'inquiète de voir des numéros de sécurité sociale dans les traces d'exception. L'équipe Plateforme centralise les **journaux** de tout le lab dans **Loki**, cloisonnés par équipe, conservés selon des règles écrites, interrogeables à côté des métriques dans Grafana.

## Objectifs

À la fin de ce module, tu sais :
- déployer Loki multi-locataire sur le stockage objet et collecter les journaux des pods, des nœuds et des VMs avec **Grafana Alloy** ;
- écrire du **LogQL** (filtres, analyseurs, métriques tirées des journaux) et alerter sur des journaux ;
- structurer les journaux applicatifs, choisir les bonnes étiquettes et éviter la cardinalité ;
- traiter les journaux d'audit, masquer les données de santé, fixer des rétentions conformes ;
- comparer Loki avec **OpenSearch** et Alloy avec **Fluent Bit** ;
- diagnostiquer des journaux manquants, une ingestion refusée, des requêtes qui expirent.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M22-E01 | Test de positionnement : journaux | Q | ★★ | 1 |
| M22-E02 | Loki multi-locataire sur le RGW | LAB | ★★ | 1 |
| M22-E03 | Alloy dans le cluster : pods et nœuds | LAB | ★★ | 1 |
| M22-E04 | LogQL : filtres, analyseurs et métriques de journaux | LAB | ★★ | 1 |
| M22-E05 | Alloy sur les VMs du socle | LAB | ★★ | 1 |
| M22-E06 | Des journaux structurés : MédiAgenda en JSON | LAB | ★★★ | 2 |
| M22-E07 | Journal d'audit de l'API et événements Kubernetes | LAB | ★★★ | 2 |
| M22-E08 | Alerter sur les journaux | LAB | ★★★ | 2 |
| M22-E09 | Données de santé dans les journaux : filtrer et masquer | LIBRE | ★★★ | 2 |
| M22-E10 | Fluent Bit : un autre collecteur | LAB | ★★ | 2 |
| M22-E11 | Revue : la configuration Alloy du stagiaire | REV | ★★ | 2 |
| M22-E12 | Runbook : chercher dans les journaux pendant un incident | RED | ★★ | 2 |
| M22-E13 | Rétention, locataires et limites | LAB | ★★★ | 3 |
| M22-E14 | Performance de Loki et cardinalité des étiquettes | LAB | ★★★ | 3 |
| M22-E15 | OpenSearch : la recherche plein texte en comparaison | LAB | ★★★ | 3 |
| M22-E16 | Accès, sécurité et sauvegarde des journaux | LAB | ★★★ | 3 |
| M22-E17 | ADR : l'architecture des journaux | RED | ★★ | 3 |
| M22-E18 | Questions de production : journaux | Q | ★★★ | 3 |
| M22-E19 | Panne : plus aucun journal d'un nœud | BF | ★★ | 4 |
| M22-E20 | Panne : Loki refuse les écritures | BF | ★★★ | 4 |
| M22-E21 | Panne : les requêtes expirent | BF | ★★★ | 4 |
| M22-E22 | Panne : les journaux d'une équipe ont disparu | BF | ★★ | 4 |
| M22-E23 | Astreinte : enquête par les journaux | BF | ★★★★ | 4 |
| M22-E24 | Sous le capot : ingestion, chunks et index TSDB | LAB | ★★★★ | 4 |
| M22-E25 | Mini-projet : les journaux de MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 5 break & fix · 2 questionnaires · 1 revue · 2 rédactions.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| Loki 3.7 | espace `journaux`, Application Argo CD, compartiment RGW `loki-k8s-par1` | Stockage et requêtes des journaux ; écriture hors cluster par 10.10.41.62:3100 | E02 |
| Alloy 1.21 | DaemonSet (espace `journaux`) et rôle Ansible `alloy` sur les VMs | Collecte | E03, E05 |
| OpenSearch 3.9 | espace `opensearch-essai` | Comparaison, **retiré** en fin de module | E15 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.11. Versions : [`annexes/versions-bloc-DE.md`](../../annexes/versions-bloc-DE.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 22 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 22 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
