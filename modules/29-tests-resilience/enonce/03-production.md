# Module 29 — Palier 3 : Production

Les paliers 1 et 2 ont posé les outils : des manifestes et des plans validés avant la fusion, des rôles Ansible et un module OpenTofu testés sur de vraies machines, un premier test de charge aligné sur les SLO, Chaos Mesh installé avec ses garde-fous, et une pyramide de tests branchée dans la CI par le composant `validation`. Il reste à s'en servir **pour de vrai**, c'est-à-dire là où ça peut faire mal. Karim Benali veut des expériences de chaos qui posent une question précise et y répondent par une mesure, pas des pods tués « pour voir ». Julien Petit veut savoir si MédiAgenda tient la charge **pendant** qu'une base bascule. Nadia Roussel veut une journée de jeu préparée comme un changement, avec un rapport qui ouvre des actions. Claire Morel veut une décision écrite sur l'outillage, et Sophie Laurent rappelle une règle qui ne se discute pas : **jamais d'expérience sur la production**.

Prérequis : paliers 1 et 2 terminés (`lab/bin/check 29 02` à `29 10` verts) et l'état ci-dessous en place.

**État d'entrée du palier 3** (ce que les paliers 1 et 2 ont livré ; rien ne doit porter un autre nom)

| Élément | État attendu |
|---|---|
| Validation statique | `kubeconform` 0.8 sur `adm01` et dans les jobs ; schémas des CRD générés depuis le cluster par `plateforme/k8s/outils/schemas-crd.sh` et publiés comme paquet générique GitLab **`schemas-crd`** du projet `plateforme/k8s` |
| Politiques | Rego v1 dans **`plateforme/politiques/rego/tofu/`** (plans OpenTofu, `tofu show -json`) et **`rego/kubernetes/`** (manifestes rendus), avec leurs tests (`opa test`) ; `conftest` 0.71 et `opa` 1.21 sur `adm01` |
| Tests d'infrastructure | **Testinfra** (`pytest-testinfra` 10.2) dans **`plateforme/ansible/tests/infra/`** : au moins `durcissement`, `node_exporter`, `alloy`, `chrony` ; lancés par la CI sur `runner01` ; **Goss** essayé (`goss serve` sur le port 8099 des VMs essayées, sondé par le blackbox de `mon01`) |
| Terratest | `plateforme/tofu-modules/vm-debian/test/` (Go 1.26, Terratest 1.0, configuration d'appel `test/fixtures/vm/`) ; VMs **`tt-<suffixe>`**, VMID **2290-2299**, étiquettes `env-m29` + **`terratest`**, sous-pool Proxmox **`lab/terratest`** (identité `wb-terratest@pve!terratest`, droits d'écriture sur ce sous-pool seulement), VNet `vsandbox`, adresse **allouée par NetBox** et rendue à la destruction ; job **manuel** `terratest:vm-debian` sur `runner01` ; état local au test ; runbook RB-293 |
| Charge | k6 1.8 sur `adm01` ; scénarios dans **`plateforme/resilience/charge/`** (clone `~/src/resilience`, `charge/parcours-recette.js` d'E06) ; seuils alignés sur le SLO de latence (**250 ms**) ; résumés JSON écrits par `handleSummary` dans `charge/resultats/` |
| Chaos | **Chaos Mesh 2.8** : Application `chaos-mesh`, espace `chaos-mesh`, valeurs dans `plateforme/gitops/valeurs/chaos-mesh/`, `controllerManager.enableFilterNamespace: true`, runtime containerd ; espaces annotés `chaos-mesh.org/inject=enabled` : **`mediagenda-recette`**, **`medinotif-recette`**, **`wb-essais`** et eux seuls ; expériences rangées dans `plateforme/resilience/chaos/` et créées **depuis `adm01`** dans l'espace **`chaos-experiences`** (seule exception écrite à « rien à la main hors Argo CD ») ; tableau de bord non publié |
| CI | composant CI/CD **`validation`** de `plateforme/ci-templates` (version publiée en M29-E10), consommé par `plateforme/k8s`, `plateforme/gitops`, `plateforme/infra`, `plateforme/ansible` |
| Documentation | `docs/qualite/` de `plateforme/medisphere` (`strategie-tests.md` de E12, `adr/`, `runbooks/` : le palier 2 a pris RB-290 à RB-293) |

**Ce que le palier 3 trouve dans la recette** (modules précédents)

| Élément | Valeur |
|---|---|
| MédiAgenda recette | espace `mediagenda-recette`, Rollout `mediagenda` (pods `app.kubernetes.io/name: mediagenda`, `app.kubernetes.io/component: api`, port 8000), HPA (M28-E02), publiée sur `https://mediagenda-recette.apps.par1.medisphere.internal` ; `/sante` (vivacité), `/pret` (disponibilité) |
| Base | cluster CNPG **`mediagenda-db`** (3 instances, une réplique synchrone, M16) ; MédiAgenda passe par le **Pooler `mediagenda-db-pooler-rw`** (PgBouncer, mode `transaction`, M27-E02) ; étiquettes des pods : `cnpg.io/cluster`, `cnpg.io/instanceRole` (`primary`/`replica`), `cnpg.io/poolerName` |
| Cache | StatefulSet **`valkey`** (une instance persistante en recette, `app.kubernetes.io/name: valkey`), TLS et ACL (M27-E07) |
| Messagerie | grappe RabbitMQ **`rabbitmq`** (3 nœuds, espace **`messagerie`**, file quorum `notifications` des vhosts `medinotif-recette` et `medinotif-prod`) ; MédiAgenda publie avec confirmations ; **MédiNotif** (`medinotif-recette`, Deployment `medinotif`) mis à l'échelle par KEDA, **zéro réplique au repos** en recette (M28-E13) |
| SLO | Pyrra (M21) : `mediagenda-latence` (95 % des requêtes < 250 ms) et `mediagenda-disponibilite` (99,5 %) sur `mediagenda-prod` ; en recette, mêmes séries (`mediagenda_http_request_duration_seconds_bucket`, `mediagenda_http_requests_total`) avec `namespace="mediagenda-recette"` |
| Prometheus | `kps` (espace `supervision`, réplicas `prometheus-kps-prometheus-0` et `-1`, Service sans tête `prometheus-operated`) ; **récepteur d'écriture distante déjà activé au M23-E13** (`enableRemoteWriteReceiver`), restreint à Tempo par la CiliumNetworkPolicy `prometheus-ecriture-tempo` ; Thanos Query (`thanos-query.supervision:9090`, et 10.10.41.60 depuis MGMT) |

**Variables de `lab/lab.env`** utilisées par les checks de ce palier : `WB_M29_RECETTE_URL` (défaut `https://mediagenda-recette.apps.par1.medisphere.internal`), `WB_M29_CHAOS_NS` (défaut `chaos-experiences`), `WB_M29_PROJET_RESILIENCE` (défaut `plateforme/resilience`).

> ⚠️ **Règles du chaos dans ce palier** (elles valent pour chaque exercice) :
> 1. **Jamais `*-prod`, jamais `messagerie`, jamais un espace de plateforme.** Le filtre d'espaces de Chaos Mesh l'empêche ; ne le contourne pas (pas d'annotation posée « pour l'essai »).
> 2. **Toute expérience a une `duration`** (ou, dans un `Workflow`, un `deadline`) et une procédure d'arrêt **préparée avant** de l'appliquer : un terminal ouvert avec la commande de pause et celle de suppression.
> 3. **Une expérience = une hypothèse écrite + une mesure** (requête PromQL ou SLO) relevée avant, pendant, après. Une expérience sans mesure n'est pas faite.
> 4. Annonce dans le canal de l'équipe (ici : ton journal `docs/qualite/journal/`) l'heure de début et de fin de chaque expérience qui touche la recette : Julien et ses développeurs s'en servent.

---

### M29-E13 — Expériences de chaos : réseau, ressources, horaires, enchaînements  `LAB` `★★★`

> **Ticket PLAT-3013** — *De : Karim Benali* — *Copie : Julien Petit*
> Chaos Mesh est installé, il est temps de lui poser de vraies questions. Je veux une petite bibliothèque d'expériences versionnées dans `plateforme/resilience`, chacune avec son hypothèse, sa mesure et son bouton d'arrêt : de la latence et de la perte entre MédiAgenda et sa base, une coupure vers le cache, du CPU volé à l'API, des conteneurs MédiNotif tués, une expérience récurrente (bornée !) et un scénario enchaîné avec des vérifications entre les étapes. Pour chaque expérience : ce que tu attendais, ce qui s'est passé. Si une hypothèse tombe, c'est une bonne nouvelle : c'est pour ça qu'on le fait.

**Objectifs pédagogiques**
- Écrire des expériences Chaos Mesh 2.8 justes : `NetworkChaos` (`delay`, `loss`, `partition`, `direction`, `target`), `StressChaos`, `PodChaos` (`container-kill`), `Schedule` (récurrence, politique de concurrence, historique), `Workflow` (`Serial`, `Parallel`, `Suspend`, `StatusCheck`, `deadline`).
- Formuler une hypothèse falsifiable et la mesurer sur les SLO, pas à l'impression.
- Maîtriser l'arrêt d'urgence : pause par annotation, suppression, et ce qui se passe sous le capot à chaque geste.
- Savoir pourquoi certaines expériences (IOChaos, TimeChaos, KernelChaos) ne sont pas pour la recette.

**Prérequis** : M29-E09 (Chaos Mesh, espace `chaos-experiences`), M29-E05/E06 (k6), M21 (Pyrra, PromQL), M27-E02 (Pooler).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Les objets de chaos vivent dans `chaos-experiences` et **visent** des pods d'autres espaces par `selector.namespaces` ; Chaos Mesh refuse tout espace non annoté. L'API est `chaos-mesh.org/v1alpha1`.
- MédiAgenda ne parle pas directement aux instances PostgreSQL : il parle au **pooler**. Réfléchis au lien que tu dégrades (API → pooler, ou pooler → instances) et à ce que chaque choix mesure.
- MédiNotif est à zéro réplique au repos : sans messages dans la file, il n'y a **aucun pod à viser**. Une expérience qui ne sélectionne rien ne fait rien (lis son statut).
- L'arrêt d'urgence d'une expérience se fait par l'annotation `experiment.chaos-mesh.org/pause=true` ou par la suppression de l'objet ; les deux font **retirer** la panne par le `chaos-daemon` du nœud. Un `Schedule` et un `Workflow` se mettent aussi en pause par annotation.
- Dans un `Workflow`, la durée d'une étape de chaos se donne par `deadline` sur le modèle (*template*), pas par `duration` dans l'expérience (le *webhook* refuse les deux à la fois).
- Pour générer le trafic de mesure, réutilise le scénario k6 de M29-E06 depuis `adm01` (débit modéré : 10 à 20 itérations par seconde), en tâche de fond pendant toute la série.

> ⚠️ **Attention** : une partition ou une perte de paquets vers une dépendance **peut rendre la recette entièrement indisponible**, même si ton hypothèse dit le contraire. Préviens Julien avant la série, garde la pause prête (`kubectl -n chaos-experiences annotate <type> <nom> experiment.chaos-mesh.org/pause=true`), et n'enchaîne jamais deux expériences sans être revenu à la ligne de base (SLO revenus au vert depuis 5 min).

**Travail demandé**
1. **Mesures.** Écris dans `plateforme/observabilite/slo/` deux SLO Pyrra **de recette** pour MédiAgenda (latence 250 ms à 95 %, disponibilité 99 %, fenêtre 7 jours, `namespace="mediagenda-recette"`), pour lire un taux de consommation du budget pendant les expériences. Prépare dans Grafana (Explore suffit) les trois requêtes de mesure : p95 de la latence, taux d'erreurs 5xx, nombre de pods prêts de l'API.
2. **Bibliothèque.** Dans `plateforme/resilience/chaos/e13/`, un fichier par expérience, avec en tête un bloc de commentaires **Hypothèse / Mesure / Critère d'arrêt / Arrêt d'urgence** :
   - `NetworkChaos` : latence de 50 ms (avec gigue) sur le trafic de l'API **vers le pooler**, 5 min ;
   - `NetworkChaos` : perte de 20 % des paquets sur le même lien, 3 min ;
   - `NetworkChaos` : **partition** entre l'API et Valkey, dans les deux sens, 2 min (hypothèse tirée de la documentation de la plateforme : « Valkey est un cache, sa perte dégrade sans casser ») ;
   - `StressChaos` : CPU d'un pod de l'API chargé à 80 % par deux travailleurs, 5 min (que doit faire l'HPA, et en combien de temps ?) ;
   - `PodChaos` `container-kill` d'un conteneur MédiNotif pendant qu'il consomme (fais d'abord publier des notifications par l'API), 30 s ;
   - `Schedule` : un `container-kill` d'une API toutes les 15 minutes, politique `Forbid`, historique limité à 3 exécutions, **mis en pause** après la troisième ;
   - `Workflow` `degradation-progressive` : vérification HTTP de `/pret` → latence pooler 3 min **en parallèle** d'une vérification continue qui **interrompt** le workflow si elle échoue trois fois → pause de 2 min → `container-kill` d'une API → pause → vérification finale.
   Ajoute un `catalogue.md` (tableau : fichier, type, cible, durée, hypothèse, résultat, date).
3. **Arrêt d'urgence.** Écris `plateforme/resilience/outils/chaos-arret.sh` : met en pause **tout** ce qui tourne dans `chaos-experiences` (expériences, `Schedule`, `Workflow`), affiche ce qui reste injecté, et propose (option `--supprimer`) de tout supprimer. Écris le runbook **RB-294** « Arrêter une expérience de chaos » (`docs/qualite/runbooks/`), qui complète RB-292 (arrêt d'urgence, M29-E09) sans le répéter : l'outil, pause, suppression, vérification que la panne est retirée (`status.experiment.containerRecords`), et quoi faire si la suppression reste bloquée (renvoie à la procédure qu'écrira M29-E20).
4. **Exécute** chaque expérience **séparément**, mesure avant / pendant / après, note dans `catalogue.md` : hypothèse confirmée ou réfutée, chiffres, surprise éventuelle. Pour chaque expérience, essaie une fois la pause **pendant** l'injection et vérifie que l'effet disparaît.
5. **Ce qu'on ne fait pas.** Dans `catalogue.md`, une section « Écartées » : `IOChaos` (comment il agit en 2.8, pourquoi pas sur la base de recette), `TimeChaos`, `KernelChaos`, `HTTPChaos`, `DNSChaos` ; une ligne chacune, avec la raison.
6. Laisse dans `chaos-experiences`, jusqu'au contrôle, les objets de la série (expériences terminées, `Schedule` en pause, `Workflow` terminé) ; supprime-les ensuite.

**Critères de réussite**
- [ ] `plateforme/resilience/chaos/e13/` (sur `main`) contient au moins un `NetworkChaos` `delay`, un `loss`, un `partition`, un `StressChaos`, un `PodChaos` `container-kill`, un `Schedule` et un `Workflow` ; toutes les expériences hors `Workflow` ont une `duration`, aucune ne vise un espace `*-prod` ni `messagerie`.
- [ ] Le `Schedule` a `concurrencyPolicy: Forbid` et un `historyLimit` ≤ 3, et il est en pause dans le cluster ; le `Workflow` a terminé (ou a été interrompu par sa vérification).
- [ ] Les expériences ont réellement injecté (enregistrements `Injected` puis `Not Injected` dans leur statut).
- [ ] Les deux SLO de recette sont chargés par Pyrra ; `catalogue.md`, `chaos-arret.sh` et RB-294 sont publiés.

**Vérification** : `lab/bin/check 29 13`

<details><summary>Indice 1</summary>

Dans un `NetworkChaos`, `selector` désigne les pods **sur lesquels** les règles sont posées et `target` l'autre extrémité ; `direction: to` agit sur ce qui part du sélecteur vers la cible. Pour une latence, sur quel côté poses-tu les règles si tu veux mesurer l'effet sur l'API ? La page « Simulate Network Faults » de la documentation 2.8 donne les champs ; `kubectl explain networkchaos.spec --recursive` les donne aussi, à la version installée.
</details>

<details><summary>Indice 2</summary>

Un `Schedule` embarque l'expérience sous la clé qui porte le nom de son type en *camelCase* (`podChaos:`), à côté de `type: PodChaos`. Dans un `Workflow`, un modèle `StatusCheck` a un `mode` (`Synchronous` ou `Continuous`), un `failureThreshold`, et le modèle porte `abortWithStatusCheck`. L'URL vérifiée est appelée **par le contrôleur de Chaos Mesh**, depuis l'espace `chaos-mesh` : choisis une adresse qu'il peut joindre et dont il accepte le certificat.
</details>

<details><summary>Indice 3</summary>

Pour la partition vers Valkey, relis ce que fait `/pret` (README de MédiAgenda et M14-E07) **avant** de lancer : ton hypothèse est-elle compatible avec le code ? Lance quand même : l'expérience est faite pour le prouver par la mesure. Note le temps entre le début de la partition et le premier 503 vu par k6.
</details>

**Pour aller plus loin** (facultatif) : ajoute une expérience `bandwidth` (débit limité vers le pooler) et cherche le débit en dessous duquel le p95 dépasse 250 ms ; compare avec l'effet d'une latence équivalente.

---

### M29-E14 — k6-operator : tests distribués et non-régression de performance  `LAB` `★★★`

> **Ticket PLAT-3014** — *De : Julien Petit* — *Copie : Karim Benali*
> Le test de charge depuis `adm01` nous a appris beaucoup, mais il ne passe pas 300 utilisateurs (la VM sature avant MédiAgenda) et il dépend de quelqu'un qui le lance. Je voudrais deux choses. Un : lancer la charge **depuis le cluster**, répartie sur plusieurs pods, avec les résultats dans Prometheus à côté de nos métriques d'application. Deux : un test de non-régression **chaque nuit** sur la recette, qui compare au résultat de référence et qui nous prévient si une version a fait perdre 20 % de latence, avant qu'elle n'arrive en prod.

**Objectifs pédagogiques**
- Installer k6-operator 1.7 par la chaîne de la plateforme (miroir des charts, Argo CD, espace dédié conforme à `restricted`).
- Écrire un `TestRun` distribué (`parallelism`, script en ConfigMap, images par Harbor, contexte de sécurité) et comprendre son cycle de vie (initialiseur, exécuteurs, démarreur, `stage`).
- Envoyer les métriques de k6 dans Prometheus par écriture distante, sans ouvrir Prometheus à tout le cluster.
- Construire une non-régression de performance planifiée : référence versionnée, comparaison chiffrée, verdict dans le pipeline.

**Prérequis** : M29-E06 (scénario k6 et seuils), M20 (Argo CD, `charts-miroir`), M19 (agent GitLab, runners, pipelines planifiés), M21 (Prometheus, Thanos, Grafana), M23-E13 (récepteur d'écriture distante).
**Durée indicative** : 3 h.

**Contexte technique**
- Chart **`grafana/k6-operator` 4.7.0** (k6-operator 1.7.0, dépôt `https://grafana.github.io/helm-charts`), à recopier par `plateforme/charts-miroir` ; images par le cache Harbor (`registry.par1.medisphere.internal/ghcr/grafana/k6-operator:controller-v1.7.0`, `…/dockerhub/grafana/k6:1.8.2`, et l'image du « démarreur », publiée avec chaque version dans `ghcr.io/grafana/k6-operator` — l'opérateur prend par défaut une étiquette mobile `latest-starter`).
- Espace **`k6`** (créé dans `plateforme/k8s/espaces/`, Pod Security `restricted`, quota) : l'opérateur **et** les `TestRun` y vivent. Le chart sait créer son espace : il ne doit pas le faire ici.
- Un `TestRun` lance un *initializer* (qui lit le script et calcule le découpage), `parallelism` exécuteurs (chacun reçoit une part de l'exécution par `execution-segment`), puis un *starter* qui les démarre ensemble par l'API REST de k6 (port 6565). Les **seuils (`thresholds`) sont évalués par chaque exécuteur sur sa part** : ils ne disent rien du total.
- k6 1.8 envoie ses métriques en écriture distante par une sortie (`--out`) dont le nom a changé plusieurs fois : `k6 run --help` ne liste pas les sorties, mais k6 donne la liste exacte quand on lui en demande une qui n'existe pas (`k6 run --out nimporte /dev/null`) ; elle se règle par des variables d'environnement `K6_PROMETHEUS_RW_*`. Les tendances (`http_req_duration`) deviennent des jauges `k6_<métrique>_<stat>` (stats choisies), en secondes.
- Prometheus a deux réplicas ; Tempo écrit dans chacun par le Service sans tête (M23-E13). k6 n'accepte qu'**une** adresse d'écriture.
- L'agent GitLab `k8s-par1` sait donner à un projet un accès à un espace (`ci_access`), comme pour `formation/ci-labo` au M19-E18.

**Travail demandé**
1. **Installer.** Entrée du chart dans `charts-miroir` (version, empreinte, usage) ; espace `k6` (étiquettes MédiSphère, PSA `restricted`, `ResourceQuota` qui laisse passer 4 exécuteurs à 500m/256Mi, `LimitRange`) ; Application Argo CD **`k6-operator`** (projet `plateforme`, valeurs dans `plateforme/gitops/valeurs/k6-operator/values.yaml` : images par Harbor, CRD installées par le chart, pas d'espace créé, `ServiceMonitor` de l'opérateur, ressources). La lecture des objets de `k6.io` par les checks est déjà prévue par la ClusterRole `wb-checks-services-m29` (M29-E09) : vérifie-le (`kubectl auth can-i list testruns.k6.io --as=system:serviceaccount:wb-system:wb-checks -n k6`) une fois les CRD installées. Régénère et republie le paquet `schemas-crd` (nouvelles CRD, M29-E02).
2. **Le script.** Dans `plateforme/resilience/charge/distribue/`, un scénario `mediagenda-recette.js` qui reprend le parcours de M29-E06 (créneaux, création puis suppression d'un rendez-vous, liste) : exécuteur `ramping-arrival-rate` jusqu'à un débit cible paramétré par variable d'environnement, seuils alignés sur le SLO (p95 < 250 ms sur les requêtes métier, erreurs < 1 %), étiquette `testid` pour retrouver un essai dans Prometheus. Vérifie-le avec `k6 inspect` et un essai court depuis `adm01`.
3. **Le TestRun.** ConfigMap du script (générée depuis le fichier), `TestRun` `mediagenda-recette-distribue` avec `parallelism: 4`, images de Harbor, contexte de sécurité compatible `restricted` pour **tous** les pods qu'il crée, ressources, nettoyage automatique en fin d'essai, sortie d'écriture distante vers **un** réplica de Prometheus. Lance-le, suis `stage`, lis les journaux des exécuteurs. Explique ce qui se passe si un exécuteur ne démarre pas (quota, image).
4. **Prometheus.** Ajoute dans `plateforme/observabilite/supervision/` une CiliumNetworkPolicy qui autorise `POST /api/v1/write` vers Prometheus **depuis l'espace `k6` seulement** (et pas depuis n'importe quel pod de `k6` : seulement les exécuteurs), sur le modèle de celle de Tempo. Vérifie dans Thanos Query que les séries `k6_*` arrivent avec l'étiquette `testid`, et qu'un pod de `wb-essais` ne peut **pas** écrire. Reporte le flux dans la matrice du cluster.
5. **Tableau.** Tableau Grafana « Charge k6 » (UID **`m29-charge-k6`**, dans `tableaux/plateforme/`) : débit, utilisateurs virtuels, p95/p99 de k6 **et** p95 côté MédiAgenda sur le même graphe, taux d'erreurs, choix de l'essai par la variable `testid`.
6. **Non-régression nocturne.** Dans `plateforme/resilience` : un fichier de référence `charge/references/mediagenda-recette.json` (p95, p99, taux d'erreurs, débit atteint, version de MédiAgenda mesurée, date), un job planifié (pipeline planifié de GitLab, chaque nuit) qui crée le `TestRun` avec un `testid` unique, attend sa fin, lit les résultats **agrégés** dans Prometheus (Thanos) et compare à la référence avec une tolérance écrite (p95 +20 %, erreurs +0,5 point) ; échec du pipeline au-delà. Le job agit par l'agent GitLab avec des droits limités à la création et à la lecture de `TestRun` dans `k6`. Runbook **RB-295** « Non-régression de performance rouge » (qui regarde quoi, comment mettre à jour la référence, qui en a le droit).

**Critères de réussite**
- [ ] L'Application `k6-operator` est `Synced/Healthy`, l'opérateur tourne dans `k6` avec une image de Harbor ; l'espace `k6` est en `restricted` avec un quota.
- [ ] Un `TestRun` à 4 exécuteurs ou plus est arrivé à `finished`, et Thanos Query renvoie des séries `k6_http_req_duration_*` étiquetées par `testid`.
- [ ] Une CiliumNetworkPolicy de `supervision` ouvre l'écriture distante aux seuls exécuteurs de `k6` ; aucune règle n'ouvre `/api/v1/write` à tout le cluster.
- [ ] Le tableau `m29-charge-k6` existe ; la référence et le pipeline planifié existent dans `plateforme/resilience`, dont le dernier pipeline planifié a réussi ; RB-295 est publié.

**Vérification** : `lab/bin/check 29 14`

<details><summary>Indice 1</summary>

`helm show values` sur l'archive recopiée liste les clés : `namespace.create`, `installCRDs`, `manager.image`, `metrics.serviceMonitor`. Le `TestRun` se décrit par `kubectl explain testrun.spec --recursive` une fois les CRD installées : `script.configMap`, `parallelism`, `arguments`, `runner`, `starter`, `cleanup`. L'*initializer* hérite des réglages du `runner` s'il n'a pas les siens.
</details>

<details><summary>Indice 2</summary>

Les pods d'un `TestRun` portent des étiquettes posées par l'opérateur (`app: k6`, `k6_cr: <nom>`, et `runner: "true"` sur les exécuteurs) : c'est par elles que ta politique les reconnaît. Les tendances envoyées dépendent de `K6_PROMETHEUS_RW_TREND_STATS` (par défaut, seulement `p(99)`).
</details>

<details><summary>Indice 3</summary>

Pour la comparaison, ne lis pas les résumés des exécuteurs : chacun n'a vu qu'un quart de la charge. Interroge Prometheus sur la fenêtre de l'essai, filtrée par `testid` (`max_over_time` des jauges k6, ou mieux : l'histogramme côté MédiAgenda sur la même fenêtre). Le job a besoin de joindre Thanos Query depuis son pod : une règle réseau de plus, à écrire et à reporter dans la matrice.
</details>

**Pour aller plus loin** (facultatif) : envoie aussi les résultats en OpenTelemetry (sortie `opentelemetry` de k6) vers le Collector du M23 et compare le coût en séries ; essaie `separate: true` (un exécuteur par nœud) et mesure l'effet sur le débit atteint.

---

### M29-E15 — Résilience des données sous charge : primaire et nœud RabbitMQ perdus  `LAB` `★★★`

> **Ticket PLAT-3015** — *De : Julien Petit* — *Copie : Nadia Roussel, Claire Morel*
> On nous promet depuis le M16 qu'une bascule PostgreSQL « ne se voit presque pas » et depuis le M27 qu'un nœud RabbitMQ en moins « ne perd rien ». Je veux le voir **sous charge** : combien de requêtes en erreur, pendant combien de temps, et est-ce que le pooler aide ou gêne. Pour RabbitMQ, Sophie refuse le chaos dans `messagerie` (c'est partagé avec la prod) : fais-le comme un vrai changement annoncé, à la main, avec le ticket CHG-3015, et prouve qu'aucune notification n'a été perdue.

**Objectifs pédagogiques**
- Provoquer et mesurer une bascule du primaire `mediagenda-db` pendant une charge réelle : erreurs vues par l'utilisateur, temps de reprise, rôle du pooler PgBouncer (mode `transaction`) et de la réplique synchrone.
- Comparer une bascule **subie** (primaire tué) et une bascule **voulue** (`promote` / *switchover*).
- Perdre un nœud d'une grappe RabbitMQ de trois par une opération manuelle annoncée, et prouver la tenue des files quorum et des publications confirmées : rien de perdu, rien en double non expliqué.
- Rédiger un rapport chiffré qui distingue ce qui est garanti de ce qui a été observé.

**Prérequis** : M29-E13 (expériences, mesures), M29-E14 (charge distribuée) ou M29-E06 (charge depuis `adm01`) ; M16-E19 et M27-E02 (CNPG, pooler) ; M27-E03/E08 (RabbitMQ, publication de MédiAgenda).
**Durée indicative** : 2 h.

**Contexte technique**
- `kubectl cnpg status mediagenda-db -n mediagenda-recette` montre le primaire, les répliques, la réplication synchrone. `kubectl cnpg promote mediagenda-db <instance> -n mediagenda-recette` promeut une réplique (bascule voulue, propre). Le pooler se connecte au Service `mediagenda-db-rw`.
- Pour la bascule subie, un `PodChaos` `pod-kill` sur le pod qui porte l'étiquette `cnpg.io/instanceRole: primary` (une seule fois, `mode: one`).
- RabbitMQ : StatefulSet `rabbitmq-server` (pods `rabbitmq-server-0..2`) géré par le Cluster Operator dans `messagerie`. L'espace `messagerie` n'est **pas** annoté pour Chaos Mesh, et ne doit pas l'être. Le compte `wb-checks` (étiquette `monitoring`) lit l'API de gestion (`~/.config/workbook/rabbitmq-checks.env`) ; l'interface est `https://rabbitmq.apps.par1.medisphere.internal`.
- MédiAgenda publie une demande de notification par rendez-vous créé, avec confirmation de publication ; il compte le résultat dans `mediagenda_notifications_total{resultat}`. MédiNotif compte `medinotif_messages_total{type,resultat}`.

> ⚠️ **Attention** : `messagerie` porte aussi les files de **production** (`medinotif-prod`). La perte d'un nœud est une opération **annoncée** : ticket CHG-3015 ouvert avec l'heure, l'état de la grappe vérifié juste avant (trois nœuds en marche, aucune alarme, toutes les files quorum avec trois membres en ligne, aucune file en cours de synchronisation), un seul pod à la fois, et **jamais** pendant une autre intervention sur RabbitMQ. Retour arrière : l'opérateur recrée le pod tout seul ; si `rabbitmq-server-1` ne revient pas en 5 minutes, arrête l'essai et applique le runbook de la grappe RabbitMQ écrit au M27 (`docs/donnees/runbooks/`). Ne supprime **jamais** un PVC de `messagerie`.

**Travail demandé**
1. **Ligne de base.** Lance une charge stable sur la recette (15 à 30 itérations par seconde, scénario avec créations de rendez-vous) pendant 10 min ; relève p95, taux d'erreurs, notifications publiées et confirmées, notifications traitées par MédiNotif, profondeur de la file.
2. **Bascule subie.** Pendant la charge, tue le primaire par un `PodChaos` (fichier `chaos/e15/pod-kill-primaire.yaml`). Mesure : nombre de requêtes en erreur et leur code, durée de la fenêtre d'erreurs, temps jusqu'au nouveau primaire (`kubectl cnpg status`, événements), temps jusqu'au retour du p95 sous 250 ms. Lis les journaux du pooler pendant la bascule.
3. **Bascule voulue.** Recommence avec `kubectl cnpg promote` vers une réplique. Compare les deux bascules dans un tableau. Dis ce qu'a fait le pooler dans chaque cas (connexions serveur, transactions en cours, clients mis en attente) et ce qui se serait passé si MédiAgenda avait parlé directement à `mediagenda-db-rw`.
4. **Nœud RabbitMQ perdu.** Ouvre CHG-3015 dans ton journal, vérifie l'état de la grappe (API de gestion : nœuds, alarmes, membres des files quorum), puis, pendant la charge, supprime `rabbitmq-server-1`. Observe : file `notifications` des deux vhosts (membres, chef, messages), publications de MédiAgenda (confirmées, échouées), consommation de MédiNotif, retour du nœud et rattrapage de son réplica. Ferme CHG-3015 avec l'heure de fin.
5. **Comptes.** Prouve « rien de perdu » par les compteurs : rendez-vous créés pendant l'essai = notifications publiées et confirmées = notifications traitées (+ celles encore en file, + celles au rebut). Explique tout écart (doublons de la livraison « au moins une fois », publications non confirmées).
6. **Rapport.** `docs/qualite/rapports/AAAA-MM-JJ-resilience-donnees.md` : chiffres, chronologie, ce qui est **garanti** (réplique synchrone, quorum) contre ce qui est **observé**, limites (une seule mesure, recette moins chargée que la prod), recommandations. Runbook **RB-296** « Perte du primaire PostgreSQL ou d'un nœud RabbitMQ sous charge : quoi regarder ».

**Critères de réussite**
- [ ] `mediagenda-db` a 3 instances prêtes et un primaire différent de celui du début (au moins une bascule faite) ; la réplication synchrone est de nouveau en place.
- [ ] La grappe `rabbitmq` a 3 nœuds en marche, aucune alarme ; la file quorum `notifications` de `medinotif-recette` a ses 3 membres en ligne.
- [ ] Le `PodChaos` de la bascule subie existe dans `chaos-experiences` (ou dans `chaos/e15/` de `plateforme/resilience`) et visait `mediagenda-recette` seulement.
- [ ] Le rapport et RB-296 sont publiés ; le rapport contient le CHG-3015, une fenêtre d'erreurs chiffrée pour chaque bascule et le bilan des notifications.

**Vérification** : `lab/bin/check 29 15`

<details><summary>Indice 1</summary>

Pour la fenêtre d'erreurs, k6 la donne si ton scénario étiquette ses requêtes et que tu exportes ses points dans le temps (écriture distante ou sortie `json`) ; côté MédiAgenda, `sum by (code) (rate(mediagenda_http_requests_total{namespace="mediagenda-recette"}[15s]))` sur un pas de 5 s la montre aussi. CNPG trace les étapes de la bascule dans les événements du `Cluster` et dans `status` (`currentPrimary`, `targetPrimary`, `phase`).
</details>

<details><summary>Indice 2</summary>

Côté RabbitMQ, l'API de gestion dit tout : `GET /api/nodes` (`running`, alarmes `mem_alarm`, `disk_free_alarm`), `GET /api/queues/<vhost>/notifications` (`type`, `members`, `online`, `leader`, `messages`). Le vhost s'encode dans l'URL. `rabbitmq-queues check_if_node_is_quorum_critical` dans un pod de la grappe dit si l'arrêt d'un nœud ferait perdre le quorum : c'est la vérification à faire **avant** de supprimer.
</details>

<details><summary>Indice 3</summary>

Une publication confirmée est sur une majorité des membres de la file quorum : la perte d'un nœud ne la fait pas disparaître. Une publication **en cours** quand le nœud tombe peut ne pas être confirmée : MédiAgenda l'a-t-il comptée comme échec, ou la connexion était-elle sur un autre nœud ? Regarde à quel nœud MédiAgenda et MédiNotif sont connectés (`GET /api/connections`, champ `node`).
</details>

**Pour aller plus loin** (facultatif) : refais la bascule subie avec la réplication synchrone désactivée sur un cluster de `wb-essais` et compare ce que tu perds ; mesure l'effet du réglage `server_check_delay` du pooler.

---

### M29-E16 — Journée de jeu : hypothèse, mesure, rapport  `LIBRE` `★★★`

> **Ticket PLAT-3016** — *De : Nadia Roussel* — *Copie : Claire Morel, Julien Petit, Karim Benali*
> Première journée de jeu (*game day*) de MédiSphère, jeudi. On la prépare comme un changement, on la joue comme un incident, on la raconte comme un post-mortem. Objectif : vérifier que l'astreinte **voit** et **comprend** des pannes qu'elle n'a pas choisies, et que la recette tient ce qu'on croit. Tu es maître du jeu : tu prépares, tu animes, tu rapportes. Je joue l'astreinte, Julien observe pour son équipe. Je ne veux pas de surprise pour Julien, je veux des surprises pour moi.

**Objectifs pédagogiques**
- Préparer une journée de jeu : hypothèses, rayon d'action (*blast radius*), critères d'arrêt, rôles, communication avant, pendant, après.
- Enchaîner au moins trois expériences sur la recette, sous charge, et observer la détection (alertes, tableaux) autant que le comportement du système.
- Rédiger un rapport qui ouvre des actions correctives suivies.

**Prérequis** : M29-E13, M29-E14, M29-E15 ; M21 (alertes, SLO), M22 (journaux).
**Durée indicative** : 2 h 30 (préparation 1 h, jeu 45 min, rapport 45 min).

**Contexte technique**
- Gabarit du rapport : `ressources/E16-journee-de-jeu/modele-journee-de-jeu.md` (à recopier dans `docs/qualite/journees-de-jeu/AAAA-MM-JJ-<sujet>.md` de `plateforme/medisphere`).
- Périmètre autorisé : `mediagenda-recette`, `medinotif-recette` (par Chaos Mesh) ; aucune action sur `messagerie` sans CHG ; jamais `*-prod`.
- Les SLO de recette (E13), le tableau « Charge k6 » (E14) et les alertes du M21 sont tes instruments.

**Travail demandé**
1. **Préparation** (écrite dans le rapport avant le jeu) : objectifs, hypothèses (une par expérience, falsifiable, chiffrée), rayon d'action et ce qui est hors champ, critères d'arrêt (seuils mesurables), rôles (maître du jeu, astreinte, observateur, scribe), annonces (qui est prévenu, quand, par quel canal), plan de retour arrière, matériel prêt (expériences relues, bouton d'arrêt, charge).
2. **Jeu** : au moins **trois** expériences enchaînées (un enchaînement par `Workflow`, ou trois injections successives que tu déclenches), sous charge ; l'astreinte ne connaît pas l'ordre. Le scribe note la chronologie à la minute : injection, première alerte, premier diagnostic juste, retour à la normale.
3. **Rapport** : chronologie, hypothèses confirmées ou réfutées avec les mesures, détection (ce qui a sonné, ce qui aurait dû), ce que l'astreinte a compris ou non, **actions correctives** : chacune avec un responsable, une échéance et un ticket (`PLAT-`, `DEV-`, `SEC-`), au moins une qui concerne la détection et une qui concerne le système.
4. Ouvre les tickets d'actions dans le suivi de l'équipe (issues GitLab du projet `plateforme/resilience`, étiquette `journee-de-jeu`) et relie-les depuis le rapport.

**Contraintes**
- Aucune expérience hors du périmètre autorisé ; chacune a une durée et un arrêt d'urgence préparé.
- Toute expérience est versionnée dans `plateforme/resilience/journees-de-jeu/<date>/` avant d'être jouée.
- Aucun secret, aucune donnée personnelle dans le rapport.

**Critères de réussite**
- [ ] Un rapport `docs/qualite/journees-de-jeu/AAAA-MM-JJ-*.md` est sur `main`, avec les sections du gabarit (préparation, chronologie, hypothèses, détection, actions) et au moins trois expériences.
- [ ] Les expériences jouées sont dans `plateforme/resilience/journees-de-jeu/` ; elles ne visent que des espaces de recette et ont toutes une durée (ou un `deadline`).
- [ ] Au moins deux issues étiquetées `journee-de-jeu` existent dans `plateforme/resilience`, référencées dans le rapport.

**Vérification** : `lab/bin/check 29 16`

<details><summary>Indice 1</summary>

Une bonne hypothèse a la forme « quand X arrive à Y, alors Z reste sous le seuil S, et l'astreinte le voit en moins de T ». Elle dit quoi mesurer et quand on s'arrête. Si tu ne sais pas écrire S, tu ne sais pas encore pourquoi tu fais l'expérience.
</details>

<details><summary>Indice 2</summary>

La détection compte autant que la tenue : pour chaque expérience, quelle alerte **devait** partir ? Si aucune ne part alors que le SLO souffre, c'est une action corrective. Les surprises de M29-E13 et E15 sont de bons candidats, mais l'astreinte les connaît peut-être : varie la cible ou la combinaison.
</details>

**Pour aller plus loin** (facultatif) : rejoue la même journée un mois plus tard, après les actions correctives, et compare les temps de détection et de diagnostic.

---

### M29-E17 — ADR : outillage de tests et de chaos  `RED` `★★`

> **Ticket PLAT-3017** — *De : Claire Morel*
> Avant l'audit, j'ai besoin de l'ADR-0290 : ce que nous utilisons pour tester la plateforme et pour éprouver sa résilience, pourquoi, ce que nous avons écarté, et l'exception que nous avons accordée au chaos. Deux pages au plus, nos mesures, pas des plaquettes commerciales.

**Objectifs pédagogiques**
- Formaliser des choix d'outillage à partir des essais du module, avec leurs coûts et leurs limites.
- Justifier une exception à une règle de la plateforme (GitOps) et l'encadrer.

**Prérequis** : M29-E01 à M29-E16.
**Durée indicative** : 1 h.

**Travail demandé**
Rédige `docs/qualite/adr/ADR-0290-outillage-tests-chaos.md` (contexte, décision, options étudiées, conséquences, statut) :
1. **Chaos** : Chaos Mesh 2.8 retenu, **LitmusChaos** 3 écarté (lis la fiche [`annexes/decouverte/litmuschaos.md`](../../../annexes/decouverte/litmuschaos.md)) ; ce que nous perdons (ChaosHub, *probes*, interface) et pourquoi c'est acceptable.
2. **Charge** : k6 + k6-operator ; écarté ou cité : JMeter, Locust, Gatling ; pourquoi la non-régression nocturne passe par Prometheus et pas par les résumés des exécuteurs.
3. **Tests d'infrastructure** : Testinfra retenu pour la CI, **Goss** (garder les deux ou non : tranche, avec la raison) ; **Terratest** en pipeline **manuel** (coût, durée, ressources réelles).
4. **Validation statique** : kubeconform avec les schémas des CRD, conftest (Rego v1) **et** Kyverno CLI : qui fait quoi, pourquoi deux moteurs de politiques.
5. **Exception GitOps** : les expériences de `chaos-experiences` sont créées depuis `adm01` hors Argo CD. Pourquoi (une expérience est un **geste daté**, pas un état désiré ; Argo CD la recréerait après sa fin ou la ressusciterait à chaque synchronisation), comment c'est encadré (fichiers versionnés avant usage, espace dédié, filtre d'espaces, RBAC, journal, durée obligatoire), et ce qui reste sous Argo CD (Chaos Mesh lui-même, ses valeurs, les annotations d'espaces).
6. **Conséquences** et déclencheur de révision.

**Critères de réussite**
- [ ] L'ADR traite les cinq décisions, avec au moins une mesure du module par décision (temps de pipeline, coût mémoire, durée d'un Terratest, résultat d'une expérience…).
- [ ] L'exception `chaos-experiences` est justifiée et encadrée (au moins trois garde-fous nommés).

**Vérification** : `lab/bin/check 29 17` (présence et contenu de l'ADR ; le fond s'auto-évalue avec le corrigé)

<details><summary>Indice</summary>

Un ADR ne compare pas des fonctionnalités : il dit ce qui compte **pour nous** (pas de MongoDB à exploiter, pas de chart Bitnami, mémoire du lab, compétences de l'équipe, auditabilité HDS). Pour chaque option écartée, donne la raison qui ferait changer d'avis.
</details>

---

### M29-E18 — Questions de production : tests et résilience  `Q` `★★★`

> **Ticket PLAT-3018** — *De : Karim Benali*
> Les questions que je pose avant de confier à quelqu'un la journée de jeu et la non-régression. Réponses argumentées, chiffrées quand c'est possible.

**Objectifs pédagogiques**
- Raisonner sur les coûts et les limites des tests (intégration, charge, chaos) et sur la façon de lire leurs résultats.
- Défendre une position sur le chaos en production, les tests flous, les percentiles.

**Prérequis** : M29-E13 à M29-E17.
**Durée indicative** : 1 h (+ 20 min d'auto-correction).

**Questions**
1. Un directeur propose « on fait du chaos en production, comme Netflix ». Donne trois conditions préalables que MédiSphère ne remplit pas encore, et la première expérience de production que tu accepterais une fois qu'elles le sont.
2. Pourquoi LitmusChaos et Chaos Mesh, deux projets de la CNCF, ne sont-ils pas interchangeables chez nous ? Cite deux critères techniques et un critère d'exploitation.
3. Le test Terratest de `vm-debian` prend 9 minutes et coûte une VM. Un développeur veut le lancer à chaque MR de `plateforme/tofu-modules`. Que réponds-tu, et que proposes-tu à la place (au moins deux niveaux de test) ?
4. Un test Testinfra échoue une nuit sur sept sur `mon01`, puis repasse. Comment décides-tu si c'est un test flou (*flaky*) ou un vrai défaut intermittent ? Que fais-tu du test en attendant ?
5. k6 annonce un p95 de 180 ms ; le SLO de MédiAgenda mesuré par Prometheus sur la même fenêtre donne 92 % des requêtes sous 250 ms. Les deux peuvent-ils être vrais ? Donne au moins deux explications.
6. Qu'est-ce que l'**omission coordonnée** (*coordinated omission*) ? Pourquoi l'exécuteur `constant-vus` de k6 y est-il exposé et pas `constant-arrival-rate` ? Que voit-on sur les percentiles ?
7. Pourquoi faire la moyenne des p95 de quatre exécuteurs k6 est-il faux ? Comment obtient-on un p95 global juste ?
8. MédiAgenda (Python) appelle MédiDoc (Go) depuis le M23. Qu'apporterait un **test de contrat** (*consumer-driven*, par exemple Pact) par rapport au test de bout en bout de la recette ? Qui l'écrit, où tourne-t-il ?
9. Une expérience `NetworkChaos` est supprimée mais le pod visé garde sa latence. Donne trois causes possibles et, pour chacune, la commande qui la prouve.
10. Pourquoi une politique conftest qui « passe » toutes les MR depuis trois mois doit-elle t'inquiéter ? Comment prouves-tu qu'une politique peut encore refuser ?
11. Le budget d'erreur de la recette est épuisé par les expériences de chaos. Faut-il exclure les fenêtres d'expérience du calcul du SLO ? Argumente pour la recette, puis pour une hypothétique production.
12. Classe du moins cher au plus cher, et dis ce que chacun attrape que le précédent ne voit pas : `opa test`, `conftest` sur un plan réel, Testinfra sur une VM du socle, Terratest, journée de jeu.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions avant d'ouvrir le corrigé.
- [ ] Chaque réponse cite une mesure, une commande ou un réglage du lab qui l'appuie.

**Vérification** : auto-évaluation avec le corrigé (pas de check automatique).
