# ADR-0210 — Architecture de la supervision par métriques de MédiSphère

| | |
|---|---|
| Statut | Accepté |
| Date | `<DATE>` |
| Décideurs | Claire Morel (infrastructure), Karim Benali (plateforme), Sophie Laurent (RSSI, consultée), Nadia Roussel (astreinte, consultée) |
| Ticket | PLAT-2231 (M21-E31) |
| Remplace | — (InfoGér : aucune supervision par métriques, `kubectl top` et intuitions) |
| Liens | PLAN §4.11 ; ADR-0200 (GitOps) ; `thanos.md`, `slo.md`, `dimensionnement.md`, `securite.md`, `politique-alerte.md` |

## Contexte

- Incident du mois dernier : MédiAgenda (production) a répondu en dix secondes toute une matinée ; ce sont les centres de santé qui ont prévenu. Aucune courbe, aucune alerte.
- Exigences : alerter sur ce que vivent les utilisateurs (symptômes), objectifs chiffrés pour les contrats HDS (99,5 % sur 28 jours), conservation des métriques **2 ans** (preuve de niveau de service, tendances de capacité), données hébergées chez nous (souveraineté : pas de SaaS), tout décrit par le code et livré par Argo CD (ADR-0200).
- Contraintes du lab : un hyperviseur, profil de travail ≈ 100 Go de mémoire pour tout (socle, `ceph-par1`, `k8s-par1`) ; une équipe Plateforme de quelques personnes ; stockage objet disponible : RGW de `ceph-par1` (M08) et SeaweedFS de `s3-01` (M05).
- Ce qu'il faut superviser : le cluster (plan de contrôle, nœuds, Cilium, CoreDNS), les applications (MédiAgenda, MédiDoc), les VMs du socle, Ceph, les services réseau (HAProxy, PowerDNS, Kea), GitLab, Harbor, Proxmox et PBS — c'est-à-dire **aussi** ce qui est hors du cluster et ce dont le cluster dépend.

## Options étudiées

| Critère | A. kube-prometheus-stack + Thanos (sidecar) | B. Grafana Mimir 3 | C. VictoriaMetrics (cluster) | D. Prometheus seul (VM, sans Kubernetes) |
|---|---|---|---|---|
| Composants à exploiter | Prometheus ×2, Alertmanager, Grafana, opérateur ; Thanos : Query, Store, Compactor (+ sidecar) | une dizaine de composants (distributeur, *ingester*, *querier*, *store-gateway*, *compactor*…) et **Kafka**, activé par défaut dans le chart 6.x (ingestion) | `vminsert`, `vmselect`, `vmstorage` (+ `vmagent`, `vmalert`) | 1 à 2 binaires |
| Mémoire au repos (lab) | ~6 Gio (2 × Prometheus compris) | ≥ 12 Gio avec Kafka (estimation sur le chart par défaut) | ~3 Gio | ~3 Gio |
| Conservation longue | stockage objet (RGW), sous-échantillonnage 5 min / 1 h | stockage objet | disque des `vmstorage` (pas de stockage objet en édition libre) | disque local |
| Haute disponibilité | 2 réplicas + dédoublonnage à la lecture | native (réplication à l'écriture) | réplication des `vmstorage` | non |
| Compatibilité Prometheus (PromQL, CRD de l'opérateur, règles) | totale (c'est Prometheus) | PromQL, règles via le *ruler* | MetricsQL (sur-ensemble, quelques écarts), opérateur propre | totale, mais pas de CRD (ServiceMonitor…) |
| Intégration GitOps / équipes | CRD (`ServiceMonitor`, `PrometheusRule`) dans les dépôts des équipes | règles par API (mimirtool) | CRD propres (`VMServiceScrape`) | fichiers sur une VM |
| Licence | Apache 2.0 | **AGPLv3** | Apache 2.0 (fonctions d'entreprise payantes) | Apache 2.0 |
| Compétences et documentation | standard du métier, CKA/CKS | spécialisée | spécialisée | standard |
| Images et charts | charts officiels ; Thanos par manifestes (pas d'image Bitnami : catalogue gratuit retiré en 2025) | chart officiel | chart officiel | — |

## Décision

**Option A** : kube-prometheus-stack (chart 92, Prometheus 3.15) dans l'espace `supervision`, livré par Argo CD, avec :

1. **Deux réplicas de Prometheus** identiques, rétention locale 15 jours, et **Thanos 0.42** (sidecar de l'opérateur, Query, Store Gateway, Compactor) vers le compartiment **`thanos-k8s-par1` du RGW** de `ceph-par1` : brut 30 j, 5 min 180 j, 1 h 2 ans. Thanos Query est le point de lecture unique (10.10.41.60, Grafana, Pyrra).
2. **Une supervision témoin hors du cluster** sur `mon01` (Prometheus 3.13 LTS, Alertmanager, blackbox_exporter, pve-exporter) : elle surveille le cluster de l'extérieur (Watchdog interrogé sur Thanos Query, sondes des points d'entrée), et le cluster la surveille en retour.
3. **Grafana 13** (sous-chart), tableaux de bord *as code* (JSON relus, provisionnés), dossiers et équipes par OpenTofu.
4. **Pyrra** pour les SLO et les alertes de budget multi-fenêtres ; Sloth gardé en contre-vérification.
5. Configuration de la supervision dans **`plateforme/observabilite`** (règles, ScrapeConfig, routes, tableaux, SLO, Thanos), règles et moniteurs des équipes dans **leurs** dépôts, sous garde-fous (`enforcedNamespaceLabel`).
6. Alertes par **courriel** (Mailpit dans le lab) selon la politique d'alerte ; étiquettes `gravite` et `equipe` partout.

## Justification

- **Le plus petit système qui répond aux exigences.** Les deux ans de conservation imposent un stockage objet : Thanos l'ajoute à Prometheus sans le remplacer. Mimir le fait aussi, mais au prix d'une dizaine de composants et de Kafka : trop lourd pour le lab et pour l'équipe ; VictoriaMetrics est sobre mais sans stockage objet en édition libre et avec un langage légèrement différent.
- **Compatibilité totale** : ce que l'équipe apprend (PromQL, opérateur, `promtool`) est le standard du métier ; les équipes de développement décrivent leur supervision avec les mêmes CRD que leurs déploiements.
- **Stockage sur le RGW** plutôt que SeaweedFS de `s3-01` : `s3-01` porte les états OpenTofu, les sauvegardes etcd et Velero ; y ajouter le volume des métriques mélangerait des données de criticité très différente sur une seule VM. Le RGW est répliqué ×3 et déjà joint par les travailleurs (carte `eth1`, M16).
- **Témoin hors cluster** : une supervision ne peut pas annoncer sa propre mort ; `mon01` est une VM du socle, sur un autre domaine de panne que le cluster.

## Conséquences

Positives : une seule source de vérité de lecture (10.10.41.60) ; un Prometheus peut tomber sans perte ni trou ; conservation 2 ans à coût maîtrisé ; supervision des équipes par Git.

Négatives et actions :
- **Double collecte** (2 réplicas) : double charge sur les cibles et double mémoire ; budget de séries par réplica (`dimensionnement.md`).
- **Thanos Query n'a ni `/federate` ni API d'administration** : la supervision témoin interroge l'API de requête (sonde) au lieu de fédérer ; les consultations de configuration passent par `port-forward` (`thanos.md`).
- **Rétention locale (15 j) < fenêtre des SLO (28 j)** : les règles de Pyrra évaluées par Prometheus ne voient que 15 jours ; à revoir (rétention ou Thanos Ruler) avant une vraie production (`dimensionnement.md` §4).
- **Un seul Compactor**, jamais deux : alerte critique dédiée (RB-214).
- **Pas d'authentification** sur Prometheus, Thanos Query, Alertmanager : filtrage réseau en attendant le SSO (M24), `securite.md`.
- **Domaine de panne commun** : `mon01` et le cluster sont sur le même hyperviseur (`pve01`) ; une panne de l'hôte rend les deux muets. Réponse hors lab : un service de *dead man's switch* hors site ; au PRA (F5) : témoin sur PAR2.
- Dépendance au RGW : RGW arrêté = envois en attente (15 j de marge), requêtes longues partielles.
- Montées de version : kube-prometheus-stack (lire `UPGRADE.md` à chaque majeure), Thanos (même version sidecar et composants), Pyrra (manifestes amont à recopier).

## Conditions de révision

- plus de 300 000 séries par réplica ou plus de deux clusters : réévaluer Mimir ou VictoriaMetrics (ingestion centralisée, multi-locataire) ;
- second site actif (PAR2) : Thanos Query global au-dessus des deux sites, témoin croisé ;
- SSO (M24) : proxy d'authentification devant Prometheus, Thanos Query, Alertmanager ;
- traces et profils (M23) : `enableRemoteWriteReceiver` pour le *metrics-generator* de Tempo — à réévaluer ici (capacité).
