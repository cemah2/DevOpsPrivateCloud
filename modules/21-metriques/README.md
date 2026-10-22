# Module 21 — Métriques et alerting

| | |
|---|---|
| **Bloc** | E — Observabilité |
| **Niveau** | Cœur |
| **Profil de lab** | Socle v4 + `ceph-par1` + `k8s-par1` (≈ 100 Go) ; aucune VM d'environnement permanente |
| **Prérequis** | Module 20 (`gitops-v1` : Argo CD gère les services de plateforme) ; module 14 (administration Kubernetes) ; module 08 (RGW de `ceph-par1`) ; module 19 (`mon01`, Mailpit) |
| **Durée indicative** | 85 à 105 heures (palier 1 : 16-20 h ; palier 2 : 28-34 h ; palier 3 : 24-29 h ; palier 4 : 12-15 h ; mini-projet : 8-12 h) |

## Contexte MédiSphère

Le mois dernier, la production de MédiAgenda a répondu en dix secondes pendant toute une matinée ; ce sont les centres de santé qui ont prévenu le support. Personne n'avait de courbe, seulement `kubectl top` et des intuitions. Nadia Roussel refuse une astreinte « à l'aveugle » ; Claire Morel veut des **objectifs de niveau de service** chiffrés pour les contrats HDS ; Sophie Laurent veut savoir qui consulte quoi. L'équipe Plateforme construit la **supervision** de MédiSphère : métriques de tout le lab, du socle aux applications, alertes qui réveillent pour de bonnes raisons, tableaux de bord versionnés, conservation longue sur le stockage objet, et une supervision de la supervision qui ne dépend pas du cluster.

## Objectifs

À la fin de ce module, tu sais :
- déployer et exploiter Prometheus, Alertmanager et Grafana par **kube-prometheus-stack**, sous Argo CD ;
- écrire du **PromQL** juste (taux, agrégations, histogrammes, jointures) et maîtriser les étiquettes (relabeling, cardinalité, recording rules) ;
- superviser le cluster, les VMs du socle, Proxmox, Ceph et les services réseau ;
- écrire des alertes fondées sur les symptômes, les router, les taire, les relier à un runbook ;
- définir des **SLI/SLO** et alerter sur le budget d'erreur (Pyrra, Sloth) ;
- conserver les métriques sur le stockage objet avec **Thanos** et surveiller la supervision depuis l'extérieur ;
- diagnostiquer une cible disparue, une alerte muette, une explosion de cardinalité, des données perdues.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M21-E01 | Test de positionnement : supervision | Q | ★★ | 1 |
| M21-E02 | Déployer kube-prometheus-stack par Argo CD | LAB | ★★ | 1 |
| M21-E03 | Explorer Prometheus : cibles, séries et étiquettes | LAB | ★ | 1 |
| M21-E04 | PromQL : sélecteurs, taux et agrégations | LAB | ★★ | 1 |
| M21-E05 | Grafana : sources de données, exploration, premier tableau de bord | LAB | ★★ | 1 |
| M21-E06 | Alertmanager : routes, regroupement et courriels | LAB | ★★ | 1 |
| M21-E07 | Les métriques de MédiAgenda : ServiceMonitor et PodMonitor | LAB | ★★ | 1 |
| M21-E08 | Superviser les VMs : node_exporter partout | LAB | ★★ | 1 |
| M21-E09 | Questions : modèle de données et architecture de Prometheus | Q | ★★ | 1 |
| M21-E10 | Exportateurs natifs : Ceph, HAProxy, PowerDNS, Kea, GitLab, Harbor | LAB | ★★★ | 2 |
| M21-E11 | Sondes blackbox et supervision hors cluster sur `mon01` | LAB | ★★★ | 2 |
| M21-E12 | Proxmox VE et PBS : pve-exporter | LAB | ★★ | 2 |
| M21-E13 | Relabeling : maîtriser les étiquettes | LAB | ★★★ | 2 |
| M21-E14 | Recording rules et cardinalité | LAB | ★★★ | 2 |
| M21-E15 | Écrire de bonnes alertes | LAB | ★★★ | 2 |
| M21-E16 | Silences, inhibitions et routage par équipe | LAB | ★★ | 2 |
| M21-E17 | Tableaux de bord *as code* | LAB | ★★★ | 2 |
| M21-E18 | Analyses Prometheus pour Argo Rollouts | LAB | ★★★ | 2 |
| M21-E19 | Méthodes USE et RED : les tableaux de bord de référence | LIBRE | ★★★ | 2 |
| M21-E20 | Superviser Kubernetes : plan de contrôle, etcd, kubelet, Cilium | LAB | ★★ | 2 |
| M21-E21 | Revue : les règles d'alerte du stagiaire | REV | ★★ | 2 |
| M21-E22 | Runbook : répondre à une alerte | RED | ★★ | 2 |
| M21-E23 | Diagnostiquer une saturation par les métriques | LAB | ★★★ | 2 |
| M21-E24 | Prometheus redondant et Thanos sur le RGW | LAB | ★★★ | 3 |
| M21-E25 | Thanos : vue globale, compaction, sous-échantillonnage, rétention | LAB | ★★★ | 3 |
| M21-E26 | SLI et SLO de MédiAgenda avec Pyrra | LAB | ★★★ | 3 |
| M21-E27 | Budgets d'erreur et alertes multi-fenêtres ; Sloth en comparaison | LAB | ★★★ | 3 |
| M21-E28 | Superviser la supervision | LAB | ★★★ | 3 |
| M21-E29 | Sécuriser la pile de supervision | LAB | ★★★ | 3 |
| M21-E30 | Capacité et performance de Prometheus | LAB | ★★★ | 3 |
| M21-E31 | ADR : l'architecture de supervision de MédiSphère | RED | ★★ | 3 |
| M21-E32 | Politique d'alerte et d'astreinte | RED | ★★ | 3 |
| M21-E33 | Questions de production : supervision | Q | ★★★ | 3 |
| M21-E34 | Un diagnostic en temps limité | CHRONO | ★★★ | 3 |
| M21-E35 | Panne : une cible a disparu | BF | ★★ | 4 |
| M21-E36 | Panne : l'alerte ne part plus | BF | ★★★ | 4 |
| M21-E37 | Panne : les tableaux de bord sont vides | BF | ★★ | 4 |
| M21-E38 | Panne : Prometheus déborde | BF | ★★★ | 4 |
| M21-E39 | Panne : les données anciennes ont disparu | BF | ★★★ | 4 |
| M21-E40 | Panne : l'alerte sonne sans arrêt | BF | ★★ | 4 |
| M21-E41 | Panne : une règle ne se charge pas | BF | ★★ | 4 |
| M21-E42 | Panne : la supervision hors cluster est aveugle | BF | ★★★ | 4 |
| M21-E43 | Astreinte : une nuit agitée | BF | ★★★★ | 4 |
| M21-E44 | Sous le capot : WAL, blocs et chunks | LAB | ★★★★ | 4 |
| M21-E45 | Questions expert : PromQL et Prometheus | Q | ★★★ | 4 |
| M21-E46 | Mini-projet : la supervision de MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| kube-prometheus-stack | espace `supervision`, Application Argo CD | Prometheus (2 réplicas), Alertmanager, Grafana 13, kube-state-metrics, node-exporter | E02 |
| Prometheus / Alertmanager | `LoadBalancer` 10.10.41.60:9090 / 10.10.41.61:9093 | Accès depuis MGMT et `mon01` seulement | E02, E24 |
| Grafana | `grafana.apps.par1.medisphere.internal` | Tableaux de bord, exploration | E05 |
| `plateforme/observabilite` | projet GitLab | Règles, `ScrapeConfig`, routes, tableaux de bord, SLO | E07 |
| Thanos 0.42 | espace `supervision`, compartiment RGW `thanos-k8s-par1` | Stockage long terme, vue globale | E24 |
| Pyrra 0.10 | espace `supervision` | SLO | E26 |
| Supervision témoin | `mon01` (10.10.20.19) | Prometheus, Alertmanager, blackbox_exporter, pve-exporter | E11, E12, E28 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.11. Versions : [`annexes/versions-bloc-DE.md`](../../annexes/versions-bloc-DE.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 21 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 21 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
