# Module 29 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- Champs des CRD de **Chaos Mesh 2.8.6** relus dans le code (`api/v1alpha1/*_types.go` à l'étiquette `v2.8.6`) : `NetworkChaos` (`action`, `direction`, `target`, `delay`, `loss`), `StressChaos` (`stressors.cpu.workers/load`), `PodChaos` (`container-kill`, `containerNames`, `gracePeriod`), `Schedule` (`concurrencyPolicy` par défaut `Forbid`, `historyLimit`, `startingDeadlineSeconds`, expérience embarquée sous `podChaos:`…), `Workflow` (`Serial`, `Parallel`, `Suspend`, `StatusCheck`, `deadline`, `abortWithStatusCheck`), annotation de pause `experiment.chaos-mesh.org/pause`, finaliseur `chaos-mesh/records`, annotation de forçage `chaos-mesh.chaos-mesh.org/cleanFinalizer=forced`. Tous les manifestes des corrigés validés par **kubeconform 0.8 `-strict`** contre les schémas générés des CRD 2.8.6 (script `openapi2jsonschema.py` de kubeconform), comme ceux de Pyrra et de k6-operator.
- Le webhook de `Workflow` refuse une `duration` dans une expérience embarquée (`shouldNotSetupDurationInTheChaos`, `workflow_webhook.go`) ; le `container-kill` avec containerd envoie **SIGKILL** à la tâche (`crclients/containerd/client.go`) ; l'IOChaos 2.8 passe par `toda` lancé par le daemon (plus de *sidecar* injecté par webhook).
- **k6-operator 1.7.0** : CRD `TestRun` (`parallelism`, `script.configMap`, `arguments`, `runner`, `starter`, `initializer` hérité du `runner`, `cleanup: post` qui supprime le TestRun en `finished` **ou** `error`), étiquettes des pods (`app: k6`, `k6_cr`, `runner: "true"`), images par défaut (`grafana/k6:latest`, `ghcr.io/grafana/k6-operator:latest-starter`), métriques du contrôleur en HTTP clair sur 8443 malgré le nom du port. Chart **4.7.0** : empreinte de l'index recalculée sur l'archive téléchargée, `helm template` (Helm 4.0) avec les valeurs du corrigé.
- **k6 1.8.2** : la sortie s'appelle toujours `experimental-prometheus-rw` (liste affichée par k6 sur une sortie inconnue ; `k6 run --help` ne liste pas les sorties) ; variables `K6_PROMETHEUS_RW_*` relues dans le code ; tendances envoyées en jauges `k6_<métrique>_<stat>` **converties en secondes**, cumulées depuis le début de l'essai, par série ; taux en `k6_<métrique>_rate`, compteurs en `_total`. Script `mediagenda-recette.js` vérifié par `k6 inspect`.
- `outils/comparer-reference.sh`, `chaos-arret.sh` : `shellcheck`, et comparaison rejouée avec un faux Prometheus.
- kube-prometheus-stack **92.11.0** (prometheus-operator 0.94.1) : `prometheus.prometheusSpec.enableRemoteWriteReceiver` (défaut `false`, déjà passé à `true` au M23-E13) existe dans les valeurs du chart (`helm show values`), ainsi que `remoteWriteReceiverMessageVersions`.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- comportement réel des expériences sur `k8s-par1` (Cilium 1.20 + règles `tc`/`iptables-legacy` dans l'espace réseau des pods, compatibilité de Chaos Mesh 2.8 avec Kubernetes 1.36) ; les chiffres des résultats (catalogue, rapport, journée de jeu) sont ceux d'un lab de référence **imaginé** pour montrer la forme : remplace-les par tes mesures ;
- joignabilité du Service HTTP interne de MédiAgenda par le contrôleur de Chaos Mesh (`StatusCheck`) au travers des politiques réseau de `mediagenda-recette` ;
- `TestRun` dans un espace `restricted` (contextes de sécurité de l'initialiseur hérités du `runner`) ; écriture distante de k6 acceptée par Prometheus 3.15 ; agent GitLab `ci_access` avec `default_namespace` ;
- délais de bascule CNPG et de rattrapage RabbitMQ (dépendent du lab) ; nom des conteneurs (`api`, `medinotif`) et étiquettes des pods MédiNotif (M27).

**Fichiers** : [`fichiers/M29-E13/`](fichiers/M29-E13/) à [`fichiers/M29-E17/`](fichiers/M29-E17/), sous la forme d'un extrait des projets : `resilience/…` = `plateforme/resilience`, `observabilite/…`, `gitops/…`, `k8s/…`, `charts-miroir/…`, `medisphere/…` = la documentation. Les `*.extrait*` sont à fusionner dans le fichier existant (l'emplacement est dit en tête).

---

### M29-E13 — Expériences de chaos : réseau, ressources, horaires, enchaînements

**Solution**

*1. Mesures.* Deux SLO Pyrra de recette, [`slo/mediagenda-recette-latence.yaml`](fichiers/M29-E13/observabilite/slo/mediagenda-recette-latence.yaml) et [`…-disponibilite.yaml`](fichiers/M29-E13/observabilite/slo/mediagenda-recette-disponibilite.yaml), copiés de ceux du M21 avec `namespace="mediagenda-recette"`, fenêtre `7d`, et **`alerting.disabled: true`** : la recette sera volontairement dégradée, on lit les taux de consommation pendant l'expérience au lieu d'être réveillé. Les trois requêtes de mesure sont en tête de chaque fichier d'expérience.

*2. Bibliothèque.* [`chaos/e13/`](fichiers/M29-E13/resilience/chaos/e13/) : sept fichiers, chacun avec son bloc Hypothèse / Mesure / Critère d'arrêt / Arrêt d'urgence. Les points qui comptent :

| Fichier | Point clé |
|---|---|
| `01-latence-pooler.yaml` | `selector` = pods de l'API (là où `tc` est posé), `target` = pods du **pooler** (`cnpg.io/poolerName: mediagenda-db-pooler-rw`), `direction: to` : seuls les paquets API → pooler sont retardés. Viser les instances PostgreSQL ne changerait rien pour l'API : elle ne leur parle pas. |
| `02-perte-pooler.yaml` | `loss: "20"` (chaîne : pourcentage), `correlation` pour des pertes en rafales réalistes |
| `03-partition-valkey.yaml` | `action: partition`, `direction: both`, `target` = Valkey |
| `04-stress-api.yaml` | `stressors.cpu.workers: 2`, `load: 80`, `mode: one`, `containerNames: [api]` |
| `05-kill-medinotif.yaml` | préalable écrit : sans messages, KEDA laisse MédiNotif à 0 pod et l'expérience ne sélectionne rien |
| `06-schedule-kill-api.yaml` | `concurrencyPolicy: Forbid`, `historyLimit: 3`, `startingDeadlineSeconds: 120`, expérience embarquée sous la clé `podChaos:` **avec** sa `duration` ; borne = pause après la 3ᵉ exécution (Chaos Mesh n'a pas de date de fin de `Schedule`) |
| `07-workflow-degradation.yaml` | `Serial` → `StatusCheck` `Synchronous` → `Parallel` [latence, `StatusCheck` `Continuous` `failureThreshold: 3` + `abortWithStatusCheck: true`] → `Suspend` → `container-kill` → `Suspend` → vérification finale. **`deadline`** sur chaque modèle, **aucune `duration`** dans les expériences embarquées (refusée par le webhook) |

Application depuis `adm01`, une à la fois, avec la charge de M29-E06 en fond :

```
admin@adm01:~/src/resilience$ kubectl apply -f chaos/e13/01-latence-pooler.yaml
networkchaos.chaos-mesh.org/m29-e13-latence-pooler created
admin@adm01:~/src/resilience$ kubectl -n chaos-experiences get networkchaos m29-e13-latence-pooler \
    -o jsonpath='{range .status.experiment.containerRecords[*]}{.id}{" "}{.phase}{"\n"}{end}'
mediagenda-recette/mediagenda-6b7d9…-4kq2v Injected
mediagenda-recette/mediagenda-6b7d9…-p8z7m Injected
admin@adm01:~/src/resilience$ kubectl -n chaos-experiences annotate networkchaos m29-e13-latence-pooler experiment.chaos-mesh.org/pause=true
admin@adm01:~/src/resilience$ kubectl -n chaos-experiences get networkchaos m29-e13-latence-pooler -o jsonpath='{.status.experiment.desiredPhase}{"\n"}'
Stop
```

*3. Arrêt d'urgence.* [`outils/chaos-arret.sh`](fichiers/M29-E13/resilience/outils/chaos-arret.sh) : pause des `Schedule` et `Workflow` **d'abord** (ils créent), puis de chaque expérience de tous les types de `chaos-mesh.org` (découverts par `kubectl api-resources`, sans les objets internes `PodNetworkChaos`, `WorkflowNode`…), bilan des enregistrements encore `Injected`, suppression avec `--supprimer`. Runbook [`RB-294`](fichiers/M29-E13/medisphere/docs/qualite/runbooks/RB-294-arreter-une-experience-de-chaos.md).

*4-5. Résultats et écartées.* [`chaos/catalogue.md`](fichiers/M29-E13/resilience/chaos/catalogue.md). Le résultat qui compte : **la partition vers Valkey réfute l'hypothèse de la plateforme**. `/pret` interroge Valkey (code de `create_app`, M12) ; la sonde de disponibilité échoue sur **tous** les pods en même temps, ils sortent du Service, la Gateway répond 503 à tout, alors que les requêtes déjà dans un pod servaient bien les créneaux en mode dégradé. Le M14-E07 l'avait noté (« à noter pour eux ») ; personne n'avait mesuré. Action `DEV-3013` ; le correctif est fourni en M29-E23.

**Explications**

- **Où sont posées les règles** : toujours dans l'espace réseau des pods du `selector`. Une latence `to` ne retarde que l'émission ; les réponses ne sont pas retardées, l'aller-retour prend donc +50 ms. Pour une partition, le contrôleur traite aussi les pods de la `target` (leur `PodNetworkChaos` reçoit des règles selon le sens) : l'espace de la cible doit lui aussi être annoté — c'est le cas ici, cible et source sont dans `mediagenda-recette`. Lis les `PodNetworkChaos` des deux côtés pour le constater.
- **Pause et suppression** : la pause fait passer `desiredPhase` à `Stop` et retire la panne ; l'objet reste. La suppression fait de même puis lève le finaliseur `chaos-mesh/records` quand tout est retiré. Sur un `Schedule`, la pause est recopiée sur ses enfants (contrôleur `schedule/pause`).
- **`container-kill` n'est pas un arrêt propre** : SIGKILL direct de la tâche par le daemon ; le pod reste dans les points de terminaison jusqu'à l'échec suivant de la sonde de disponibilité → quelques 502. Un `pod-kill` passe par la suppression du pod.
- **StressChaos et HPA** : `stress-ng` est rattaché au cgroup du conteneur : sa consommation est comptée dans la limite (étranglement) et dans la métrique de l'HPA. On teste donc « un pod lent et étranglé », pas « un nœud chargé ».
- **IOChaos en 2.8** : le daemon lance `toda`, qui remplace un **point de montage** du conteneur (`volumePath`) par un système de fichiers FUSE qui injecte délais, erreurs ou corruption (`mistake`). Plus de *sidecar* ni de webhook d'injection (c'était Chaos Mesh 1.x). Sur le volume de PostgreSQL, c'est un risque de corruption réelle : écarté pour la recette.

**Alternatives**
- Mesurer avec k6 seul (`http_req_duration`, `checks`) : suffit pour la latence vue du client, mais ne voit pas les pods sortis du Service ni le budget du SLO ; les deux ensemble.
- Une `HTTPChaos` sur l'API au lieu d'une `NetworkChaos` : panne de niveau 7 plus précise (codes, délais par chemin), mais mandataire transparent qui interfère avec Cilium ; écartée (catalogue).
- Borner un `Schedule` par un `Workflow` qui l'embarque (modèle `Schedule` dans un `Workflow`, avec `deadline`) : vraie borne automatique, au prix d'un objet de plus ; bonne idée pour une journée de jeu.

**Pièges classiques**
- Mettre une `duration` dans les expériences d'un `Workflow` : refus du webhook ; le `deadline` va sur le modèle.
- Oublier que MédiNotif est à zéro : l'expérience « réussit » (aucune erreur), mais n'a rien fait (`containerRecords` vide, événement « no pod is selected »).
- Croire qu'une pause arrête un `pod-kill` déjà exécuté : elle n'empêche que les suivants.
- Viser `mediagenda-db` au lieu du pooler pour « la latence vers la base » : on mesure le lien pooler → instances, que l'API ne voit qu'à travers le pooler (et ses files d'attente).
- Enchaîner deux expériences sans revenir à la ligne de base : on n'attribue plus les effets.
- Laisser un `Schedule` actif « pour voir demain » : c'est exactement M29-E20.

**En production chez MédiSphère**
La bibliothèque est versionnée et relue comme du code ; chaque expérience porte son ticket. Pas de chaos en production tant que les conditions de l'ADR-0290 ne sont pas remplies ; en recette, une fenêtre annoncée (ici : le journal) et un responsable du bouton d'arrêt. Les SLO de recette n'alertent pas, mais une alerte « expérience active depuis plus de 30 min » (métrique `chaos_controller_manager_chaos_experiments{phase="Running"}`) prévient la plateforme.

---

### M29-E14 — k6-operator : tests distribués et non-régression de performance

**Solution**

*1. Installer.* Chaîne habituelle du M20/M26 :
- miroir : [`charts-miroir/charts.extrait.yaml`](fichiers/M29-E14/charts-miroir/charts.extrait.yaml) (`sha256:714acf…8986`, relevé dans l'index et recalculé sur l'archive) ;
- espace : [`k8s/espaces/k6/`](fichiers/M29-E14/k8s/espaces/k6/) — `restricted`, quota (3 CPU / 2 Gio demandés, 14 pods), `LimitRange` (sans valeurs par défaut, le démarreur que l'opérateur crée sans ressources est refusé par le quota), politique d'entrée (6565 entre pods de `k6`, 8443 depuis Prometheus, sondes de l'hôte), racine MédiSphère en ConfigMap, Role `ci-charge` pour l'agent GitLab ;
- Application [`gitops/plateforme/k6-operator.yaml`](fichiers/M29-E14/gitops/plateforme/k6-operator.yaml) + valeurs [`valeurs/k6-operator/values.yaml`](fichiers/M29-E14/gitops/valeurs/k6-operator/values.yaml) : **`namespace.create: false`** (sinon le chart crée un espace sans nos étiquettes PSA et Argo CD le possède), image `registry.par1.medisphere.internal/ghcr/grafana/k6-operator:controller-v1.7.0`, contextes de sécurité (vides par défaut dans le chart), `ServiceMonitor` dans `supervision` avec l'étiquette de sélection du M21 ; AppProject étendu ([extrait](fichiers/M29-E14/gitops/projets/plateforme.extrait-E14.yaml)) : CRD, ClusterRole et ClusterRoleBinding du chart ;
- lecture des checks : rien à ajouter, la ClusterRole [`wb-checks-services-m29`](fichiers/M29-E09/k8s/rbac/wb-checks-services-m29.yaml) (M29-E09) couvre déjà `testruns` et `privateloadzones` de `k6.io` (une seule source pour les droits des checks du module) ; on le vérifie par `kubectl auth can-i list testruns.k6.io --as=system:serviceaccount:wb-system:wb-checks -n k6` une fois les CRD installées ;
- paquet `schemas-crd` régénéré et republié (M29-E02) : les CRD `TestRun` et `PrivateLoadZone` sont nouvelles.

```
admin@adm01:~$ kubectl -n k6 get deploy,pods
NAME                                             READY   UP-TO-DATE   AVAILABLE
deployment.apps/k6-operator-controller-manager   1/1     1            1
admin@adm01:~$ kubectl get crd testruns.k6.io privateloadzones.k6.io
```

*2. Le script.* [`charge/distribue/mediagenda-recette.js`](fichiers/M29-E14/resilience/charge/distribue/mediagenda-recette.js) : `ramping-arrival-rate` (débit en itérations/s indépendant des temps de réponse — pas d'omission coordonnée), étiquette `type: metier` sur les requêtes du parcours, `responseCallback: http.expectedStatuses(201, 409)` pour qu'un conflit de créneau (normal) ne compte pas comme échec, seuils sur `http_req_duration{type:metier}` et `http_req_failed{type:metier}`. `k6 inspect` montre le scénario et les seuils ; essai court depuis `adm01` : `k6 run -e TAUX_CIBLE=5 -e PALIER=30s --tag testid=essai-adm01 charge/distribue/mediagenda-recette.js`.

*3. Le TestRun.* [`charge/distribue/testrun.yaml`](fichiers/M29-E14/resilience/charge/distribue/testrun.yaml) :

```
admin@adm01:~/src/resilience$ kubectl -n k6 create configmap charge-mediagenda-recette \
    --from-file=mediagenda-recette.js=charge/distribue/mediagenda-recette.js --dry-run=client -o yaml | kubectl apply -f -
admin@adm01:~/src/resilience$ sed "s/TESTID/essai-$(date +%Y%m%d-%H%M)/" charge/distribue/testrun.yaml | kubectl apply -f -
admin@adm01:~/src/resilience$ kubectl -n k6 get testrun -w
NAME                           STAGE            AGE
mediagenda-recette-distribue   initialization   2s
mediagenda-recette-distribue   initialized      14s
mediagenda-recette-distribue   created          16s
mediagenda-recette-distribue   started          31s
mediagenda-recette-distribue   finished         7m02s
admin@adm01:~/src/resilience$ kubectl -n k6 get pods -l k6_cr=mediagenda-recette-distribue --show-labels   # pendant l'essai
```

Ce qui se passe : l'*initializer* (même image et mêmes réglages que le `runner`, faute de bloc `initializer`) lit le script et vérifie qu'il se découpe ; l'opérateur crée 4 Jobs d'exécuteurs (`--execution-segment` 0:1/4, 1/4:2/4…) qui attendent en pause ; quand tous sont prêts, le *starter* appelle l'API REST de chacun (port 6565) pour les lancer ensemble ; en fin d'essai, `stage: finished` puis, avec `cleanup: post`, suppression du TestRun et de ses pods. Si un exécuteur ne démarre pas (quota dépassé : le Job reste sans pod, événement `exceeded quota` ; image introuvable : `ImagePullBackOff`), le *starter* n'est jamais lancé : le TestRun reste en `created` — c'est l'événement du Job qui dit pourquoi.

Images épinglées : `grafana/k6:1.8.2` (défaut de l'opérateur : `grafana/k6:latest`) et le démarreur `ghcr.io/grafana/k6-operator:starter-v1.7.0` (défaut : `latest-starter`, étiquette mobile) — les deux par Harbor. Contextes de sécurité pour **chaque** pod (exécuteur, *initializer* hérité, *starter* — utilisateur 65532 de son image) : sans eux, l'admission `restricted` refuse les pods et le TestRun reste bloqué sans message clair dans son statut (seulement dans les événements des Jobs).

*4. Prometheus.* Le récepteur est déjà ouvert depuis M23-E13 ; on ajoute [`supervision/cnp-ecriture-k6.yaml`](fichiers/M29-E14/observabilite/supervision/cnp-ecriture-k6.yaml) : `POST /api/v1/write` sur 9090 depuis les pods `k6` étiquetés `app: k6` **et** `runner: "true"`, `enableDefaultDeny.ingress: false`. Une seule adresse d'écriture pour k6 : le pod `-0` par le Service sans tête ; Thanos Query lit les deux réplicas et déduplique, la série n'existant que sur `-0`, elle apparaît une fois. Vérifications :

```
admin@adm01:~$ curl -s -G http://prometheus.apps.par1.medisphere.internal:9090/api/v1/query \
    --data-urlencode 'query=count by (testid) (k6_http_req_duration_p95)' | jq -c '.data.result[].metric'
{"testid":"essai-20261024-1012"}
admin@adm01:~$ kubectl -n wb-essais run ecrit --rm -it --restart=Never --image=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37 \
    -- wget -q -O- --post-data=x http://prometheus-kps-prometheus-0.prometheus-operated.supervision:9090/api/v1/write
wget: server returned error: HTTP/1.1 403 Forbidden            # refus L7 de Cilium (ou délai si refus L3/L4)
```

Matrice : [extrait](fichiers/M29-E14/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.extrait.md).

*5. Tableau.* [`tableaux/plateforme/plateforme-charge-k6.json`](fichiers/M29-E14/observabilite/tableaux/plateforme/plateforme-charge-k6.json) (UID `m29-charge-k6`, variables `datasource` et `testid`), entrée de la kustomization ([extrait](fichiers/M29-E14/observabilite/tableaux/kustomization.extrait-E14.yaml)). Le graphe de latence superpose le p95 **serveur** (exact) et le max des p95 **client** des exécuteurs (indicatif, cumulé depuis le début de l'essai).

*6. Non-régression nocturne.*
- Référence [`charge/references/mediagenda-recette.json`](fichiers/M29-E14/resilience/charge/references/mediagenda-recette.json) avec ses tolérances et sa règle de mise à jour.
- Job [`.gitlab-ci.extrait-E14.yml`](fichiers/M29-E14/resilience/.gitlab-ci.extrait-E14.yml) : contexte de l'agent `plateforme/k8s:k8s-par1` (ci_access de `plateforme/resilience`, [extrait](fichiers/M29-E14/k8s/.gitlab/agents/k8s-par1/config.extrait-E14.yaml)), ConfigMap, TestRun avec `testid=nuit-<id du pipeline>`, attente de la disparition du TestRun (le `cleanup: post` le supprime en `finished` comme en `error` : on note le dernier stage vu), puis [`outils/comparer-reference.sh`](fichiers/M29-E14/resilience/outils/comparer-reference.sh) qui lit Thanos Query (règle d'entrée [`thanos/cnp-lecture-charge.yaml`](fichiers/M29-E14/observabilite/thanos/cnp-lecture-charge.yaml)) : p95/p99 **serveur** par `histogram_quantile` sur `increase(…[durée de l'essai])`, 5xx serveur, débit k6 par `k6_http_reqs_total{testid}`. Pipeline planifié (`Build → Pipeline schedules`, chaque nuit, variable `NON_REGRESSION=1`). Runbook [`RB-295`](fichiers/M29-E14/medisphere/docs/qualite/runbooks/RB-295-non-regression-performance.md).

**Explications**
- **Pourquoi pas les résumés des exécuteurs** : chaque exécuteur ne voit qu'un segment de l'exécution ; ses seuils sont évalués sur sa part ; les centiles ne s'additionnent ni ne se moyennent. Le p95 global juste vient d'un histogramme agrégé : celui de MédiAgenda (côté serveur), ou des histogrammes natifs de k6 (`K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM`, si Prometheus accepte les histogrammes natifs en écriture distante — non retenu ici, à évaluer).
- **Les jauges de tendance de k6** sont cumulées depuis le début de l'essai, par série (métrique + étiquettes) et par exécuteur : `max(k6_http_req_duration_p95{testid=…})` est un indicateur, pas une mesure.
- **L'agent GitLab en Free** agit avec **son** identité pour tout projet autorisé (l'usurpation `access_as: ci_job` est Premium) : d'où un Role minimal dans `k6` seulement.

**Alternatives**
- Sortie OpenTelemetry de k6 vers le Collector du M23 (histogrammes exponentiels) : plus de détail, plus de séries.
- `separate: true` : un exécuteur par nœud, débit plus stable, mais 4 exécuteurs exigent 4 nœuds (3 travailleurs ici).
- Lancer la non-régression depuis `runner01` en CLI k6 : plus simple, mais plafonne au débit d'une VM et sort par MGMT (flux à ouvrir).

**Pièges classiques**
- Laisser `namespace.create: true` : l'espace créé par le chart n'a ni PSA ni quota, et la suppression de l'Application le supprimerait.
- Oublier le *starter* et l'*initializer* dans les contextes de sécurité : refus d'admission silencieux côté TestRun.
- Écrire vers le Service `kps-prometheus` (équilibré entre deux réplicas) : chaque réplica reçoit la moitié des points, deux séries « trouées » que Thanos déduplique mal.
- `K6_PROMETHEUS_RW_TREND_STATS` par défaut (`p(99)` seul) : pas de p95 dans Prometheus.
- Comparer à une référence prise un autre jour avec une autre version et une autre charge : la référence dit **quoi** a été mesuré.

**En production chez MédiSphère**
La non-régression vise la recette, jamais la prod. Avant une campagne (vaccination), un essai de capacité dédié, annoncé, sur un environnement dimensionné comme la prod. Les essais de charge sont des changements : `resource_group` pour ne jamais en lancer deux, journal, et une fenêtre hors des tests manuels des équipes.

---

### M29-E15 — Résilience des données sous charge : primaire et nœud RabbitMQ perdus

**Solution**

1. **Ligne de base** : TestRun de M29-E14 à 20 it/s pendant 10 min (ou k6 depuis `adm01`) ; relevés dans le rapport.
2. **Bascule subie** : [`chaos/e15/pod-kill-primaire.yaml`](fichiers/M29-E15/resilience/chaos/e15/pod-kill-primaire.yaml) (`pod-kill`, `mode: one`, `gracePeriod: 0`, sélection par `cnpg.io/cluster` **et** `cnpg.io/instanceRole: primary`). Pendant :

```
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette | sed -n '1,12p'
admin@adm01:~$ kubectl -n mediagenda-recette get cluster mediagenda-db -o jsonpath='{.status.currentPrimary} {.status.targetPrimary} {.status.phase}{"\n"}' -w
admin@adm01:~$ kubectl -n mediagenda-recette logs -l cnpg.io/poolerName=mediagenda-db-pooler-rw --since=5m | grep -Ei 'closing|server|login'
```

Fenêtre d'erreurs mesurée par `sum by (code) (rate(mediagenda_http_requests_total{namespace="mediagenda-recette"}[15s]))` au pas de 5 s, et par k6.
3. **Bascule voulue** : `kubectl cnpg promote mediagenda-db mediagenda-db-2 -n mediagenda-recette` (instance choisie parmi les répliques prêtes) ; même mesure.
4. **RabbitMQ (CHG-3015)** : vérifications d'abord (API de gestion avec `wb-checks`, `rabbitmq-queues check_if_node_is_quorum_critical`), puis `kubectl -n messagerie delete pod rabbitmq-server-1`, observation des files (`members`, `online`, `leader`), des connexions (`node`), des compteurs.

```
admin@adm01:~$ source ~/.config/workbook/rabbitmq-checks.env
admin@adm01:~$ curl -s -u "$RABBITMQ_USER:$RABBITMQ_PASSWORD" https://rabbitmq.apps.par1.medisphere.internal/api/queues/medinotif-recette/notifications \
    | jq '{type, leader, members, online, messages}'
admin@adm01:~$ kubectl -n messagerie exec rabbitmq-server-0 -c rabbitmq -- rabbitmq-queues check_if_node_is_quorum_critical
```

(Les identifiants passent ici en argument de `curl` : sur `adm01`, poste personnel, c'est toléré pour une commande interactive ; les scripts utilisent un fichier de configuration curl, comme `rabbitmq_api`.)
5-6. Rapport d'exemple [`rapports/2026-10-27-resilience-donnees.md`](fichiers/M29-E15/medisphere/docs/qualite/rapports/2026-10-27-resilience-donnees.md) et [`RB-296`](fichiers/M29-E15/medisphere/docs/qualite/runbooks/RB-296-perte-primaire-ou-noeud-rabbitmq.md).

**Explications**
- **Pooler en mode `transaction`** : une connexion serveur n'est liée à un client que pendant une transaction. À la bascule, seules les transactions en cours échouent ; les clients gardent leur connexion au pooler, qui rouvre des connexions serveur vers le Service `-rw` repointé. Sans pooler, chaque connexion du pool de psycopg tombe et doit être recréée par l'application.
- **Réplication synchrone** : un `COMMIT` n'est acquitté qu'une fois écrit sur au moins une réplique ; la réplique promue a donc toutes les transactions validées. Ce qui échoue, ce sont les transactions **non validées** au moment de la panne : l'application doit les réessayer (elle ne le fait pas : action).
- **Subie contre voulue** : la bascule voulue arrête proprement le primaire (WAL transmis, point de reprise) : fenêtre de quelques secondes. La subie attend la détection de la panne par l'opérateur (sonde, perte du pod).
- **Files quorum** : un message confirmé (*publisher confirm*) est sur une majorité de membres (2 sur 3) : la perte d'un membre ne le perd pas. Le chef de la file est réélu en une à deux secondes si c'était lui. Les doublons viennent de la livraison « au moins une fois » : messages livrés au consommateur, non acquittés au moment où sa connexion tombe, relivrés.
- **Pourquoi pas Chaos Mesh sur `messagerie`** : l'espace porte la prod ; une expérience automatique (même bornée) peut coïncider avec une autre opération, et le filtre d'espaces serait à ouvrir pour un espace partagé. Une opération manuelle annoncée, unique, vérifiée avant, est la bonne forme.

**Alternatives**
- `kubectl cnpg restart` ou une montée de version mineure pour provoquer un switchover (M27) : bascule voulue aussi, avec une raison réelle.
- Simuler la panne d'un nœud Kubernetes entier (arrêt de la VM d'un travailleur) : plus réaliste (primaire + un nœud RabbitMQ + des API en même temps), mais touche tout le cluster, donc un changement de plus grande ampleur ; candidat pour F5.

**Pièges classiques**
- Tuer « le pod 1 » de mémoire alors que le primaire a changé : la sélection par `cnpg.io/instanceRole` évite ce piège.
- Supprimer un PVC « pour forcer la reconstruction » : interdit, et inutile.
- Supprimer deux pods RabbitMQ « pour aller plus vite » : perte du quorum, files arrêtées.
- Conclure « rien de perdu » sur la seule profondeur de file à zéro : les publications refusées par l'application ne sont jamais arrivées dans la file ; il faut les compteurs des deux côtés.
- Mesurer avec un pas de 1 min : une fenêtre de 20 s disparaît dans la moyenne.

**En production chez MédiSphère**
Les bascules PostgreSQL de maintenance sont toujours voulues (`promote`), en heures creuses, annoncées. Les mesures de ce rapport alimentent les objectifs de reprise du PRA (F5). Les actions applicatives (réessai de transaction, *outbox*) sont suivies par l'équipe MédiAgenda ; la plateforme ajoute une alerte « bascule CNPG » et « file quorum avec moins de 3 membres en ligne ».

---

### M29-E16 — Journée de jeu : hypothèse, mesure, rapport

**Solution** (une solution parmi d'autres ; ce `LIBRE` s'évalue sur la démarche)

- Expériences versionnées : [`journees-de-jeu/2026-10-29/jeu.yaml`](fichiers/M29-E16/resilience/journees-de-jeu/2026-10-29/jeu.yaml) — un `Workflow` qui enchaîne trois expériences (perte de paquets vers le pooler, CPU de MédiNotif, `pod-kill` de 50 % des API) séparées par des `Suspend` de retour à la normale, en parallèle d'une vérification continue qui interrompt tout (`abortWithStatusCheck`) si l'API ne répond plus. Vérification sur `/sante` et non `/pret`, pour ne pas interrompre sur la faiblesse connue du cache (et Valkey est hors champ cette fois).
- Rapport d'exemple : [`2026-10-29-dependances-recette.md`](fichiers/M29-E16/medisphere/docs/qualite/journees-de-jeu/2026-10-29-dependances-recette.md), au gabarit de `ressources/E16-journee-de-jeu/`.
- Actions : six issues `journee-de-jeu` dans `plateforme/resilience` (trois de détection, deux de système, une de processus), chacune avec responsable et échéance.

**Explications**
- Une journée de jeu teste **deux** systèmes : la plateforme (tient-elle ?) et l'équipe (voit-elle, comprend-elle ?). Les mesures de détection (temps jusqu'à l'alerte, jusqu'au bon diagnostic) valent autant que la latence.
- Le maître du jeu connaît l'ordre ; l'astreinte non. Les pauses de retour à la normale rendent chaque effet attribuable.
- Le rayon d'action est écrit **avant** : on n'élargit pas en cours de jeu parce que « ça se passe bien ».

**Alternatives**
- Trois injections déclenchées à la main par le maître du jeu au lieu d'un `Workflow` : plus de souplesse (on attend que l'astreinte ait fini), moins de reproductibilité.
- Journée « sur table » (*tabletop*) sans injection : utile pour une première fois avec une équipe nouvelle, ne mesure rien du système.

**Pièges classiques**
- Des hypothèses non chiffrées (« ça devrait tenir ») : rien à confirmer ni réfuter.
- Oublier la communication : l'équipe de Julien perd une matinée de tests sans savoir pourquoi.
- Des actions sans responsable ni échéance : elles ne seront jamais closes (c'est l'objet du mini-projet).
- Jouer sur la recette pendant une recette fonctionnelle de Julien.

**En production chez MédiSphère**
Une journée de jeu par trimestre, préparée comme un changement (ticket, relecture, créneau), rapportée comme un post-mortem. Les actions sont revues à la réunion hebdomadaire de la plateforme jusqu'à fermeture.

---

### M29-E17 — ADR : outillage de tests et de chaos

**Solution** : [`ADR-0290-outillage-tests-chaos.md`](fichiers/M29-E17/medisphere/docs/qualite/adr/ADR-0290-outillage-tests-chaos.md).

**Explications**
- Chaque décision dit ce qui compte **pour MédiSphère** : pas de MongoDB ni de chart Bitnami à exploiter (Litmus), lisibilité en MR (k6 contre JMeter), une seule vérité par rôle (Testinfra seul), coût réel (Terratest manuel), cohérence avec l'admission (Kyverno CLI).
- L'exception GitOps est le cœur de l'ADR pour Sophie : une expérience est un **geste daté**. Sous Argo CD, une expérience terminée serait un état désiré « faux » (resynchronisée, la panne revient) et chaque fusion déclencherait une panne. L'exception est encadrée par au moins six garde-fous nommés (fichiers sur `main`, espace dédié, filtre d'espaces, durée obligatoire, traçabilité, registre des exceptions).

**Alternatives**
- Mettre les expériences sous Argo CD avec synchronisation **manuelle** : possible pour une expérience unique, mais l'Application reste « OutOfSync » après la fin de l'expérience et un clic de trop rejoue la panne.
- Workflow Argo (Argo Workflows) pour piloter Chaos Mesh : orchestration riche, un composant de plus.

**Pièges classiques**
- Un ADR catalogue de fonctionnalités sans mesures ni raison de changer d'avis.
- Écarter Litmus « parce que c'est moins bien » : c'est un projet CNCF solide ; on l'écarte pour **nos** contraintes.
- Oublier le déclencheur de révision.

**En production chez MédiSphère**
L'ADR est relu avec la RSSI (exception) et inscrit au registre des exceptions ; il est revu à chaque montée de version majeure de Chaos Mesh ou de Kubernetes.

---

### M29-E18 — Questions de production : tests et résilience

1. **Chaos en production.** Conditions non remplies aujourd'hui : (a) une observabilité qui distingue l'impact par utilisateur et arrête l'expérience automatiquement sur un seuil de SLO de prod (nos SLO de prod n'ont pas d'arrêt automatique relié à Chaos Mesh) ; (b) une politique de budget d'erreur suivie et respectée (une expérience consomme du budget : qui l'autorise quand il en reste peu ?) ; (c) un rayon d'action démontré petit (un pod parmi beaucoup, une fraction du trafic : MédiAgenda prod a 3 réplicas, perdre un tiers de la capacité n'est pas « petit ») ; (d) l'accord écrit de la direction et de la RSSI (données de santé, HDS). Première expérience acceptable ensuite : `pod-kill` d'**un** pod de l'API de prod, en heures ouvrées, annoncé, avec arrêt automatique sur le SLO, après des mois de la même expérience en recette sans surprise. Netflix a commencé quand ses systèmes **étaient déjà** conçus pour la perte d'instances ; nous découvrons encore des faiblesses en recette (`/pret`).
2. **Litmus contre Chaos Mesh.** Techniques : (a) architecture — Litmus 3 sépare un plan de contrôle (ChaosCenter : interface, serveur GraphQL, authentification, **MongoDB**) et des agents dans les clusters ; Chaos Mesh tient dans un opérateur et un daemon, sans base de données ; (b) modèle d'expérience — Litmus exécute des expériences comme des **pods** (« runners ») tirés du ChaosHub, avec des *probes* déclaratives ; Chaos Mesh agit par son daemon dans les espaces de noms des conteneurs, par des CRD propres à chaque type de panne. Exploitation : MongoDB vient d'un sous-chart **Bitnami** (interdit chez nous), et le ChaosCenter est une application de plus à sauvegarder, durcir et monter de version. Les deux sont CNCF (Litmus est même « incubating » comme Chaos Mesh) : le choix vient de nos contraintes, pas d'une qualité absolue.
3. **Terratest à chaque MR.** Non : 9 min et une VM réelle par MR, des MR concurrentes qui se battent pour 10 VMID, et des orphelines (E21). À la place : (a) à chaque MR, `tofu validate` + `tofu fmt -check` + **`tofu test`** avec fournisseurs simulés (*mock providers*, OpenTofu ≥ 1.8) qui vérifie la logique du module (variables, étiquettes calculées) sans rien créer ; (b) conftest sur le plan d'un exemple (étiquettes, plage de VMID, protection) ; (c) Terratest **avant chaque version** du module (étiquette), manuel, et chaque nuit si le budget le permet. Le développeur garde le droit de le lancer à la main sur sa MR.
4. **Test flou ou défaut intermittent.** Collecter avant de décider : le même test sur la même VM échoue-t-il toujours sur la **même assertion** ? À quelle heure (sauvegarde PBS de `mon01` à 2 h, rotation de journaux, `apt` automatique) ? Relancer **immédiatement** après un échec : s'il passe, regarder ce qui a changé entre-temps (journal système de la VM à cette minute). Un test qui dépend d'un délai (« le service répond en 2 s »), de l'ordre des tests ou d'une ressource partagée est suspect. En attendant : on ne le supprime pas et on ne le met pas en `allow_failure` ; on le marque explicitement (`@pytest.mark.flaky` avec une issue, ou `xfail(strict=False)` avec la référence), on le sort du verdict bloquant **par une décision écrite et datée**, et on corrige dans la semaine. Un test flou ignoré apprend à toute l'équipe à ignorer le rouge (M29-E22).
5. **p95 k6 180 ms et 92 % < 250 ms.** Oui, les deux peuvent être vrais : (a) **pas les mêmes requêtes** — k6 ne mesure que le scénario (peut-être les routes rapides), le SLO toutes les requêtes du serveur sur la fenêtre (autres clients, sondes exclues ou non) ; (b) **pas la même grandeur** — 92 % sous 250 ms veut dire que le p92 vaut 250 ms ; le p95 de toutes les requêtes peut être > 250 ms tandis que celui de k6 (sous-ensemble) est 180 ms ; (c) **côté client contre côté serveur** — k6 mesure aussi le réseau et la Gateway (devrait être plus lent, pas plus rapide), le serveur mesure le traitement ; (d) **agrégation** — p95 d'un seul exécuteur, ou p95 cumulé depuis le début contre un SLO sur 28 jours ; (e) les seaux de l'histogramme (0,1 ; 0,25 ; 0,5) donnent une précision grossière au serveur. La vérité : comparer sur la même fenêtre, les mêmes routes, avec l'histogramme du serveur.
6. **Omission coordonnée.** Un client en boucle fermée (chaque utilisateur virtuel attend la réponse avant d'envoyer la suivante) **ralentit avec le serveur** : quand le serveur se fige 2 s, le client n'envoie pas les requêtes qu'un vrai utilisateur aurait envoyées pendant ces 2 s ; on mesure une seule requête lente au lieu de dizaines. Les percentiles paraissent bien meilleurs que la réalité (le p99 surtout). `constant-vus`/`ramping-vus` sont en boucle fermée ; `constant-arrival-rate`/`ramping-arrival-rate` lancent les itérations au débit voulu indépendamment des réponses (en ajoutant des VU jusqu'à `maxVUs`) : les requêtes « en retard » sont envoyées et mesurées ; si les VU manquent, k6 le dit (`dropped_iterations`) au lieu de le cacher.
7. **Moyenne des p95.** Un centile n'est pas additif : la moyenne de quatre p95 n'est le p95 de rien (si un exécuteur a eu 10 requêtes lentes et les autres aucune, la moyenne dilue ; si les volumes diffèrent, elle pondère mal). Le p95 global juste se calcule sur la **distribution agrégée** : histogrammes fusionnés (somme des seaux, puis `histogram_quantile`), histogrammes natifs, ou toutes les durées brutes (sortie `json`/`csv` de chaque exécuteur fusionnée). Ici : l'histogramme de MédiAgenda (serveur) ou les histogrammes natifs de k6.
8. **Test de contrat.** Le test de bout en bout de la recette dit « l'ensemble marche aujourd'hui » ; il est lent, fragile, et ne dit pas **qui** a cassé. Un test de contrat dirigé par le consommateur : MédiAgenda (consommateur) écrit ses attentes sur l'API de MédiDoc (`POST /api/v1/rendez-vous/{id}/pieces-jointes` : champs, codes, formats) dans un fichier de contrat publié (Pact Broker ou artefact) ; la CI de MédiDoc (producteur) **vérifie** chaque version contre les contrats de ses consommateurs, sans déployer MédiAgenda. Il tourne dans les deux pipelines (génération côté consommateur, vérification côté producteur) et attrape le changement d'API **avant** la recette. Il ne remplace pas le test de bout en bout (réseau, TLS, politiques, données).
9. **NetworkChaos supprimée, latence restante.** (a) Un **autre objet** la pose encore (`Schedule` qui l'a recréée, homonyme dans un autre espace, `Workflow`) : `kubectl get networkchaos,schedule,workflow -A`, et le `PodNetworkChaos` du pod (`spec.tcs[].source` dit quelle expérience) ; (b) le **retrait a échoué** (daemon indisponible, socket du runtime) : finaliseur présent, événements `Failed`, journaux du daemon ; (c) **règle orpheline** sur le nœud (objet supprimé de force sans retrait) : `nsenter -t <pid> -n tc qdisc show` montre un `netem` qu'aucun `PodNetworkChaos` ne décrit. Et toujours se demander si la latence vient bien du chaos (comparer avec un pod non visé).
10. **Politique qui passe tout.** Une politique qui n'a refusé aucune MR en trois mois est soit parfaite, soit **muette** (paquet hors des espaces évalués, chemin d'`input` faux, job en `allow_failure`, politique jamais chargée) — E19. Preuve qu'elle peut refuser : un **cas de référence** versionné (plan dangereux, manifeste interdit) rejoué en CI avec les arguments de production, qui **doit** échouer ; plus une métrique : nombre de règles évaluées par exécution (la sortie de conftest le donne), comparé dans le temps.
11. **Exclure les fenêtres d'expérience du SLO.** Recette : oui, on peut — le SLO de recette sert à mesurer ; mais le plus simple est de ne pas alerter (`alerting.disabled`) et de lire le budget pendant l'expérience ; exclure les fenêtres (annotations, étiquette d'expérience) cache aussi les **effets prolongés** (l'expérience a fini mais la recette souffre encore : INC-5623). Production hypothétique : **non** — l'utilisateur a réellement souffert ; le budget sert justement à décider si l'on peut se permettre l'expérience. Une expérience en prod se paie sur le budget, et s'arrête quand il est menacé.
12. **Du moins cher au plus cher.** (1) `opa test` : millisecondes ; attrape une règle cassée sur **son** entrée simulée. (2) `conftest` sur un plan réel : secondes ; attrape une règle qui ne voit pas la structure réelle (chemin, types) — ce que le mock ne voit pas. (3) Testinfra sur une VM du socle : minutes, une VM existante ; attrape un rôle qui ne produit pas l'état voulu, une dérive. (4) Terratest : ≈ 10 min, une VM créée et détruite ; attrape un module qui ne crée pas une VM utilisable (fournisseur, cloud-init, réseau) — ce qu'un plan ne prouve pas. (5) Journée de jeu : heures de préparation, recette dégradée, plusieurs personnes ; attrape les faiblesses de **l'ensemble** (dépendances, sondes, détection, équipe) qu'aucun test isolé ne voit (`/pret`).
