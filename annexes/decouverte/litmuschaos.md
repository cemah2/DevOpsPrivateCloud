# LitmusChaos — fiche découverte

> Fiche courte du module 29 (tests et résilience). LitmusChaos **n'est pas installé** dans le lab ; le workbook utilise Chaos Mesh 2.8 (décision : ADR-0290, M29-E17). Relevé du 23/10/2026 : images **3.33.0**, chart Helm `litmuschaos/litmus` **3.30.0** (le chart est en retard sur les images).

## Ce que c'est

LitmusChaos est une plateforme d'ingénierie du chaos pour Kubernetes, projet de la CNCF (niveau *incubating*), née chez MayaData puis maintenue par Harness et la communauté. Là où Chaos Mesh est d'abord un **opérateur** (des CRD qu'on applique), Litmus 3 est une **application** complète : un centre de contrôle avec interface web, utilisateurs, projets, bibliothèque d'expériences, planification, rapports de résilience, et des agents déployés dans les clusters à éprouver.

## Architecture (Litmus 3.x)

| Composant | Rôle |
|---|---|
| **ChaosCenter** (plan de contrôle) | interface web (`litmusportal-frontend`), serveur GraphQL (`litmusportal-server`), serveur d'authentification (`litmusportal-auth-server`) |
| **MongoDB** | base du ChaosCenter (utilisateurs, projets, expériences, résultats). Dans le chart 3.30, **sous-chart Bitnami `mongodb` 12.1.11** tiré de l'index d'archive de Bitnami, image `bitnamilegacy/mongodb:8.0.13-…`, en jeu de réplicas de **3** membres par défaut |
| **Chaos infrastructure** (agent, un par cluster ou espace visé) | `subscriber` (lien avec le ChaosCenter), `chaos-operator` (exécute les `ChaosEngine`), `chaos-exporter` (métriques Prometheus), contrôleur **Argo Workflows** (enchaîne les étapes d'une expérience) |
| **ChaosHub** | catalogue d'expériences prêtes (public : `hub.litmuschaos.io`, ou un dépôt Git privé) : `pod-delete`, `pod-network-latency`, `pod-cpu-hog`, `node-drain`, expériences cloud… |

## Concepts

- **Chaos experiment** : un enchaînement (un *workflow* Argo) de **fautes** (*chaos faults*) tirées du ChaosHub ou écrites soi-même ; chaque faute s'exécute comme un **pod** (« runner ») avec les droits que lui donne son compte de service — c'est lui qui agit sur la cible (par l'API Kubernetes, ou par une aide privilégiée sur le nœud pour les pannes réseau et de ressources).
- **`ChaosEngine`, `ChaosExperiment`, `ChaosResult`** : les CRD de l'agent (lien faute ↔ cible, définition, résultat).
- **Resilience probes** : vérifications déclaratives attachées à une faute — HTTP, commande, état d'objets Kubernetes, **requête Prometheus** avec seuil — évaluées avant, pendant, après ou en continu ; elles décident du verdict de l'expérience.
- **Resilience score** : note calculée à partir des poids des fautes et du résultat de leurs *probes*.
- **GameDays** : regroupement d'expériences et de rapports dans l'interface.

## Comparaison avec Chaos Mesh (pour MédiSphère)

| Critère | LitmusChaos 3 | Chaos Mesh 2.8 |
|---|---|---|
| Ce qu'on installe | ChaosCenter (3 services) + MongoDB + agent (4 composants dont Argo Workflows) | un contrôleur + un daemon par nœud (+ tableau de bord facultatif) |
| État | **MongoDB** à exploiter, sauvegarder, monter de version | aucune base : les objets sont dans etcd |
| Modèle | expériences dans l'interface (exportables en YAML), exécutées par des pods « runners » | CRD par type de panne appliqués directement ; pannes posées par le daemon dans les espaces de noms du conteneur |
| Vérifications | *probes* riches (HTTP, commande, Kubernetes, Prometheus) intégrées au verdict | `StatusCheck` HTTP dans les `Workflow` ; mesures PromQL à côté |
| Catalogue | ChaosHub (dont fautes cloud et nœud) | pas de catalogue ; types intégrés |
| Multi-clusters, multi-équipes | natif (projets, utilisateurs, plusieurs agents) | un déploiement par cluster ; RBAC Kubernetes |
| Garde-fous | RBAC du ChaosCenter, espaces de l'agent | filtre d'espaces annotés (`enableFilterNamespace`) |
| Contraintes MédiSphère | sous-chart **Bitnami** (catalogue figé depuis 08/2025, interdit dans le workbook) : il faudrait fournir sa propre MongoDB (`mongodb.enabled: false` et une base externe) — un service de plus, sans opérateur retenu au M27 | rien à ajouter |

## Pourquoi il n'est pas installé dans le lab

1. **MongoDB par Bitnami** : le chart l'apporte par un sous-chart Bitnami et l'image `bitnamilegacy` ; le workbook n'utilise aucun chart ni image Bitnami. La remplacer suppose d'exploiter une MongoDB (sauvegarde, haute disponibilité, montées de version) pour un outil utilisé quelques heures par mois.
2. **Poids** : ChaosCenter + MongoDB en jeu de réplicas + Argo Workflows ≈ plusieurs Gio de mémoire, dans un profil de lab déjà serré (≈ 111 Go pour le bloc G).
3. **Nos besoins sont petits** : une dizaine d'expériences versionnées dans Git, relues en MR, appliquées par la plateforme ; Chaos Mesh y répond avec deux composants.
4. **Chart en retard** sur les images (3.30 contre 3.33) : il faudrait épingler et vérifier chaque image à la main.

Ce que nous perdons : le ChaosHub, les *probes* Prometheus intégrées au verdict, l'interface multi-équipes. On rouvrira la question si les équipes applicatives veulent écrire et jouer leurs propres expériences en libre-service (ADR-0290, déclencheur de révision).

## Pour essayer (hors lab de référence)

Un cluster jetable (kind, k3s) suffit : installation du chart `litmuschaos/litmus` (ChaosCenter), connexion à l'interface, création d'une *chaos infrastructure* dans un espace, puis une expérience `pod-delete` sur une application de démonstration avec une *probe* HTTP. Lis la page « Installation » de la documentation de **ta** version : les valeurs du chart et les étapes changent souvent entre mineures.

## Liens officiels

- Site : <https://litmuschaos.io>
- Documentation : <https://docs.litmuschaos.io>
- Code : <https://github.com/litmuschaos/litmus> (étiquettes `3.x.y`)
- Charts Helm : <https://github.com/litmuschaos/litmus-helm> (`charts/litmus/Chart.yaml` : dépendance `mongodb` de Bitnami)
- ChaosHub public : <https://hub.litmuschaos.io>
