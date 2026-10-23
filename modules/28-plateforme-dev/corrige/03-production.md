# Module 28 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les fichiers cités sont dans [`fichiers/`](fichiers/), rangés comme dans les projets GitLab (`medinotif-deploiement/` = `medinotif/deploiement`, `mediagenda-deploiement/` = `mediagenda/deploiement`, `k8s/` = `plateforme/k8s`, `gitops/` = `plateforme/gitops`, `observabilite/` = `plateforme/observabilite`, `politiques/` = `plateforme/politiques`, `donnees/` = `plateforme/donnees`, `secrets/` = `plateforme/secrets`, `identite/` = `plateforme/identite`, `portail/` = `plateforme/portail`, `medisphere/` = `plateforme/medisphere`). Un fichier `*.extrait*.yaml` se fusionne dans le fichier de même nom de ton dépôt ; les autres sont complets.

**Vérifié hors du lab** :
- champs des `ScaledObject` contre la CRD `scaledobjects.keda.sh` de KEDA **v2.21.0** (validation du schéma OpenAPI, fichiers fusionnés avec `scaleTargetRef`) et contre les pages *ScaledObject specification*, *RabbitMQ Queue*, *Cron*, *Prometheus*, *Scaling Deployments* (pause) et *Integrations → Prometheus* de la documentation 2.21 ; noms et étiquettes des métriques dans `pkg/metricscollector/prommetrics.go` de la v2.21.0 ;
- clés de valeurs des charts `kedacore/keda` 2.21.0 et `backstage` 2.10.2 (`values.yaml` aux étiquettes) ;
- schéma des CRD `Tenant` (v1beta2), `CapsuleConfiguration` et `GlobalResourceQuota` du chart Capsule **0.15.1** (champs `rules[].quota`, `rules[].enforce.services.types`, `priorityClasses`, `namespaceOptions.quota`, `additionalMetadataList`, `forbiddenLabels` — ces deux derniers marqués « dépréciés » dans la CRD) ;
- `updateMode` du VPA dans la CRD de la 1.7.1 (`Off`, `Initial`, `Recreate`, `InPlaceOrRecreate`, `InPlace`, `Auto`) ;
- sondes, métriques et procédure de montée de Backstage dans la documentation (`root-health`, *Setup OpenTelemetry*, *Keeping Backstage Updated*) ;
- règles Prometheus `keda.yaml` et `portail.yaml` : `promtool check rules` et `promtool test rules` (promtool 3.5, syntaxe identique en 3.15) ;
- relecture indépendante : `Tenant` de E15, `ScaledObject` de recette et de prod et `PriorityClass` de E14 créés en `--dry-run=server --validate=strict` sur un kube-apiserver 1.36.2 muni des CRD de Capsule 0.15.1 et de KEDA 2.21.0 ; valeurs du portail rendues par `helm template` du chart `backstage` 2.10.2 ; règles `keda.yaml` et `portail.yaml` repassées par `promtool` 3.13 ; nom de la métrique de sauvegarde vérifié dans la documentation du plugin Barman Cloud 0.15.1 (*Observability*) ; préemption : classes de valeur négative acceptées par l'API ;
- `outils/recommandations-vpa.sh` : exécuté sur un jeu de données (`--json`), `shellcheck -x`, `bash -n` ; `ressources/E13-campagne/campagne.sh` : `shellcheck`, construction du message vérifiée avec `jq`.

**Non testé en conditions réelles** (signale tes retours) : comportement de l'activation de KEDA quand une source est en erreur alors que la charge est à 0 ; sémantique exacte des règles Capsule 0.15 (`rules[].quota` sans `namespaceSelector`, `enforce` de type `deny` sur les Services) et application des métadonnées par Capsule à des espaces créés par Argo CD ; conversion des quantités par la configuration *custom resource state* de kube-state-metrics ; durée de démarrage de Backstage avec les migrations de ses plugins ; noms exacts des métriques OpenTelemetry de Backstage après conversion par l'exportateur Prometheus.

---

### M28-E13 — KEDA en production : zéro, cron, Prometheus, repli

**Solution**

1. *Mesure.* Compte de campagne déclaré dans la topologie ([`donnees/topologie/medinotif-recette/campagne.yaml`](fichiers/M28-E13/donnees/topologie/medinotif-recette/campagne.yaml) : ExternalSecret, `User` avec l'étiquette `management`, `Permission` d'écriture sur `^notifications$` seulement), secret écrit dans OpenBao (`bao kv put -mount=kv medinotif/recette/campagne utilisateur=campagne-recette mot_de_passe=<ALÉATOIRE>`) et lu par le ClusterSecretStore (même [extrait de politique](fichiers/M28-E13/secrets/politiques/eso-plateforme.extrait-M28-E13.hcl) que `keda-prod`), puis :
   ```
   admin@adm01:~/DevOpsPrivateCloud$ modules/28-plateforme-dev/ressources/E13-campagne/campagne.sh 2000
   Publié : 2000 / 2000 message(s) dans medinotif-recette/notifications en 38 s (non routés : 0).
   admin@adm01:~$ kubectl -n medinotif-recette get hpa keda-hpa-medinotif -w
   admin@adm01:~$ kubectl -n medinotif-recette get scaledobject medinotif -o jsonpath='{.status.externalMetricNames}{"\n"}'
   ["s0-rabbitmq-notifications"]
   admin@adm01:~$ kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/medinotif-recette/s0-rabbitmq-notifications?labelSelector=scaledobject.keda.sh%2Fname%3Dmedinotif" | jq '.items[0].value'
   "1873"
   ```
   Le débit d'un pod (≈ 20 messages/s avec `MEDINOTIF_DELAI_ENVOI_MS=50`) se lit sur `rate(medinotif_messages_total[1m])` divisé par le nombre de pods. Seuil de file retenu : 500 messages par pod (25 s de retard par pod).
2. *Recette* : [`overlays/recette/keda/scaledobject.yaml`](fichiers/M28-E13/medinotif-deploiement/overlays/recette/keda/scaledobject.yaml) remplace celui de M28-E03 (déclencheur `rabbitmq` de E03 conservé : seuil 100, `excludeUnacknowledged: "false"`). Recette : `minReplicaCount: 0`, `cooldownPeriod: 600`, `pollingInterval: 15`, `initialCooldownPeriod: 120`, `activationValue: "0"` ; pas d'`idleReplicaCount` (inutile quand le minimum vaut déjà 0). 
3. *Production* : compte [`topologie/medinotif-prod/keda.yaml`](fichiers/M28-E13/donnees/topologie/medinotif-prod/keda.yaml) (même construction que `keda-recette`) + `bao kv put kv/medinotif/prod/keda utilisateur=keda-prod mot_de_passe="$(openssl rand -hex 24)"` + lecture ouverte au ClusterSecretStore ([`eso-plateforme.extrait`](fichiers/M28-E13/secrets/politiques/eso-plateforme.extrait-M28-E13.hcl) ; côté `medinotif-prod`, le rôle `eso-medinotif-prod` lit déjà `kv/medinotif/prod/*`) ; la règle d'entrée `keda` → `messagerie` 15671 de E03 vaut pour les deux vhosts, et l'`ignoreDifferences` de l'ApplicationSet couvre déjà la prod ; dans `overlays/prod/keda/` : [ExternalSecret](fichiers/M28-E13/medinotif-deploiement/overlays/prod/keda/externalsecret.yaml), [TriggerAuthentication](fichiers/M28-E13/medinotif-deploiement/overlays/prod/keda/triggerauthentication.yaml), [ScaledObject](fichiers/M28-E13/medinotif-deploiement/overlays/prod/keda/scaledobject.yaml) (minimum 2 : PDB de E14) et l'[extrait de kustomization](fichiers/M28-E13/medinotif-deploiement/overlays/prod/kustomization.extrait-M28-E13.yaml) ; `argocd app diff medinotif-prod`, puis synchronisation à la main.
4. *Cron* : fuseau `Europe/Paris`, `50 7 * * 1-5` → `30 9 * * 1-5`, 6 réplicas en prod ; `50 13 * * 1-5` → `30 14 * * 1-5`, 2 en recette.
5. *Prometheus* : Thanos Query (`http://thanos-query.supervision.svc.cluster.local:9090`), requête `sum(rate(mediagenda_notifications_total{namespace="mediagenda-<env>"}[2m]))`, seuil 20/s par pod, activation à 1/s. Flux : [`k8s/espaces/keda/30-reseau-thanos.yaml`](fichiers/M28-E13/k8s/espaces/keda/30-reseau-thanos.yaml) (sortie, port **10902** du conteneur) et la règle d'entrée à ajouter à `thanos-query-entree` ([extrait](fichiers/M28-E13/observabilite/thanos/politiques.extrait-E13.yaml)) ; matrice des flux mise à jour.
6. *Robustesse* : `fallback` `failureThreshold: 3`, `replicas: 2` (prod : 4), `behavior: currentReplicasIfHigher` ; comportement d'HPA (montée immédiate, `selectPolicy: Max` ; descente stabilisée 5 min puis un pod par minute, `selectPolicy: Min`).
7. *Pause* : [`pause-maintenance.yaml`](fichiers/M28-E13/medinotif-deploiement/overlays/recette/pause-maintenance.yaml) ajouté aux `patches` par MR, constaté (`kubectl -n medinotif-recette get scaledobject medinotif -o jsonpath='{.status.conditions[?(@.type=="Paused")].status}'` → `True`, effectif figé à 1), puis MR inverse.
8. *Supervision* : collecte déjà activée en M28-E03 (`prometheus.operator|metricServer|webhooks` du chart) — vérifie `up{namespace="keda"}` ; règles [`regles/keda.yaml`](fichiers/M28-E13/observabilite/regles/keda.yaml) et leur [test](fichiers/M28-E13/observabilite/tests/keda.test.yaml). Essai de panne : MR qui remplace `serverAddress` par `http://thanos-query.supervision.svc.cluster.local:9999` en recette ; `keda_scaler_detail_errors_total{scaler="prometheusScaler"}` grimpe dès le premier échec et un événement `KEDAScalerFailed` apparaît ; la condition `Ready` reste `True` tant qu'aucun autre déclencheur n'est actif (elle passe à `Unknown`, `PartialTriggerError`, si le `cron` ou la file l'est) ; au-delà de trois échecs consécutifs (≈ 1 min : l'HPA interroge toutes les 15 s), la condition `Fallback` passe à `True` et l'HPA reçoit la valeur de repli (effectif monté à 2 si MédiNotif tournait) ; `KedaScalerEnErreur` part au bout de 10 min ; MR inverse.
9. [`autoscaling.md`](fichiers/M28-E13/medisphere/docs/plateforme-dev/autoscaling.md).

**Explications**

- **Deux étages.** KEDA crée l'HPA `keda-hpa-medinotif` et lui sert ses métriques par l'API `external.metrics.k8s.io` (adaptateur `keda-operator-metrics-apiserver`). L'HPA ne sait pas descendre sous 1 : c'est l'**opérateur** KEDA qui, toutes les `pollingInterval` secondes, interroge les déclencheurs et décide 0 → 1 (dès qu'une valeur dépasse son seuil d'**activation**) et 1 → 0 (après `cooldownPeriod` sans aucune activité). Entre 1 et N, l'HPA décide seul, toutes les 15 s.
- **`idleReplicaCount`** n'accepte en pratique que 0, strictement inférieur à `minReplicaCount` : il sert à « dormir à 0, se réveiller directement à `minReplicaCount` » (par exemple 0 ↔ 2). Avec un minimum de 0, il n'apporte rien.
- **Plusieurs déclencheurs** : l'HPA calcule un nombre de réplicas par métrique et prend le plus grand ; le `cron` agit donc comme un **plancher** pendant sa fenêtre (la doc le dit : « dynamic minimum »). Hors fenêtre, il vaut 0 et laisse décider les autres.
- **Thanos Query plutôt que Prometheus** : le Service `kps-prometheus` répartit les requêtes entre deux réplicas dont les valeurs diffèrent légèrement (instants de collecte différents) : deux interrogations successives peuvent donner deux décisions différentes. Thanos Query déduplique (`prometheus_replica`) et survit à la perte d'un réplica. Coût : un saut de plus, et une dépendance au fonctionnement de Thanos Query (le `fallback` la couvre). Argument inverse recevable : les analyses d'Argo Rollouts (M21-E18) visent `kps-prometheus` ; l'important est de l'avoir **écrit**.
- **Le `fallback` et le zéro** : le repli remplace la métrique servie à l'HPA ; quand la charge est à 0, il n'y a pas d'HPA actif, et l'activation ne voit qu'un déclencheur en erreur : MédiNotif reste à 0. Les messages ne sont pas perdus (file quorum), seulement retardés. C'est la raison d'un minimum de 2 en production.
- **`exported_namespace`** : la collecte par ServiceMonitor attache l'étiquette `namespace` de la **cible** (`keda`) ; la métrique, elle, porte l'espace du `ScaledObject` dans `namespace` ; sans `honorLabels`, Prometheus renomme cette dernière `exported_namespace`.
- **Démarrage à froid** = attente de la prochaine interrogation (0 à 15 s) + création du pod par le contrôleur du Deployment + planification + tirage d'image (en cache sur le nœud la plupart du temps) + démarrage de Python et connexion AMQPS. Le réduire : `pollingInterval` plus court (plus de requêtes sur l'API de gestion de RabbitMQ), image plus légère, ou garder un pod (`minReplicaCount: 1`) : c'est un compromis coût/latence, à écrire.

**Alternatives**
- `advanced.scalingModifiers` : une formule (par exemple `max(file / 500, publication / 20)`) dans une seule métrique composite ; plus lisible pour un humain, mais le `fallback` par déclencheur devient `behavior: scalingModifiers` (KEDA 2.21) ; à garder pour quand les règles se compliquent.
- Mode `MessageRate` ou `ExpectedQueueConsumptionTime` du scaler RabbitMQ (protocole HTTP) au lieu du déclencheur `prometheus` : anticipe aussi, sans dépendre de Thanos ; mais `ExpectedQueueConsumptionTime` demande une interrogation à la seconde.
- `ScaledJob` (un Job par lot de messages) : adapté aux traitements longs, pas à un worker qui consomme en continu.

**Pièges classiques**
- `minReplicaCount: 0` en production « pour économiser » : les campagnes partent d'un démarrage à froid et une panne de la source pendant la nuit retarde tout.
- `desiredReplicas: "0"` dans un `cron` pour « éteindre la nuit » : la doc le signale comme une erreur ; c'est `minReplicaCount: 0` + une fenêtre cron qui fait monter.
- Valeurs de `metadata` non entre guillemets (`value: 500`) : la CRD attend des chaînes, la synchronisation échoue.
- Éditer `keda-hpa-medinotif` : KEDA réécrit l'HPA à la réconciliation suivante.
- Ouvrir la politique sur le port **9090** du Service : la politique s'applique après la traduction du Service, c'est 10902 qu'il faut autoriser.
- Couper le flux `keda` → `messagerie` pour « tester en recette » : KEDA est partagé, la production devient aveugle elle aussi.
- Mettre la pause par `kubectl annotate` : Argo CD ne retire pas forcément une annotation qu'il ne gère pas ; la pause est oubliée.

**En production chez MédiSphère**

Seuils revus après chaque grosse campagne (mesures dans `autoscaling.md`) ; la fenêtre `cron` suit le calendrier des campagnes, que l'équipe de Julien publie dans le dépôt (MR) ; alertes de KEDA routées vers la plateforme, pas vers l'équipe applicative ; tableau de bord KEDA fourni par le projet (`config/grafana/keda-dashboard.json`) recopié dans `plateforme/observabilite` après relecture. Le compte `campagne-recette` disparaît quand les essais de charge passent par k6 (M29).

---

### M28-E14 — Capacité et équité : quotas, priorités et recommandations

**Solution**

1. *Bilan* :
   ```
   admin@adm01:~$ kubectl describe node k8s-w01 | sed -n '/Allocatable/,/Events/p'
   admin@adm01:~$ kubectl get pods -A -o json | jq -r '.items[] | select(.status.phase=="Running" or .status.phase=="Pending")
       | [.spec.nodeName, .metadata.namespace, ([.spec.containers[].resources.requests.cpu // "0"] | join("+"))] | @tsv' | head
   ```
   et, dans Prometheus, `sum by (node) (kube_pod_container_resource_requests{resource="memory"})` contre `kube_node_status_allocatable`, `quantile_over_time(0.95, …[7d])` pour la consommation. Résultat dans [`capacite.md`](fichiers/M28-E14/medisphere/docs/plateforme-dev/capacite.md) § 1.
2. *Budgets* : en plus du budget du libre-service de E05, règle `quota` « budget » **sans** `namespaceSelector` dans chaque locataire (fichiers complets après E14 et E15 : [`mediagenda.yaml`](fichiers/M28-E15/k8s/locataires/mediagenda.yaml), [`medinotif.yaml`](fichiers/M28-E15/k8s/locataires/medinotif.yaml), [`medidoc.yaml`](fichiers/M28-E15/k8s/locataires/medidoc.yaml)). Vérification :
   ```
   admin@adm01:~$ kubectl get globalresourcequotas
   admin@adm01:~$ kubectl get globalresourcequota <NOM-GÉNÉRÉ> -o jsonpath='{.status.namespaces}{"\n"}{.status.total}{"\n"}'
   ```
   (le nom de l'objet généré se lit dans `kubectl get tenant medidoc -o yaml` ou par l'étiquette de propriété : relève-le sur ton lab).
3. *Priorités* : [`ordonnancement/priorites.yaml`](fichiers/M28-E14/k8s/ordonnancement/priorites.yaml) ; production : correctifs [`mediagenda` (gabarit du Deployment)](fichiers/M28-E14/mediagenda-deploiement/overlays/prod/priorite.yaml), [`medinotif` (+ PDB)](fichiers/M28-E14/medinotif-deploiement/overlays/prod/priorite-pdb.yaml), [`mediagenda-db`](fichiers/M28-E14/k8s/espaces/mediagenda-prod/50-mediagenda-db.extrait-E14.yaml) ; locataires : `priorityClasses.allowed` / `default`.
   ```
   admin@adm01:~$ kubectl -n mediagenda-prod get pods -o custom-columns=NOM:.metadata.name,PRIO:.spec.priorityClassName,VAL:.spec.priority
   ```
4. *PDB* : `kubectl get pdb -A` ; `ALLOWED DISRUPTIONS` à 0 en permanence = drainage bloqué (cas d'un `minAvailable: 1` sur un seul réplica).
5. *Préemption* : [`essais/preemption.yaml`](fichiers/M28-E14/essais/preemption.yaml) (deux classes d'essai négatives et le remplissage) puis [`preemption-standard.yaml`](fichiers/M28-E14/essais/preemption-standard.yaml) :
   ```
   admin@adm01:~$ kubectl -n wb-essais get events --field-selector reason=Preempted
   LAST SEEN   TYPE     REASON      OBJECT                                  MESSAGE
   12s         Normal   Preempted   pod/remplissage-essai-6c9d…-2xk8p       Preempted by pod 4f1e… on node k8s-w01
   ```
   Pourquoi des classes négatives : pour choisir ses victimes, l'ordonnanceur retire d'abord **tous** les pods de priorité inférieure du nœud, puis leur rend la place dans l'ordre de priorité décroissante tant que le pod en attente tient encore. Avec `standard` (10000) contre `lot` (100), les pods `lot` retrouveraient leur place les premiers et les victimes seraient les pods de priorité 0 du nœud — les composants de la plateforme sans classe. Les classes d'essai (−100 et −10) restent sous 0 : seuls les pods de l'essai peuvent être délogés. Nettoyage : `kubectl delete -f …` des deux fichiers (les classes d'essai partent avec).
6. *Recommandations* : [`outils/recommandations-vpa.sh`](fichiers/M28-E14/k8s/outils/recommandations-vpa.sh) :
   ```
   admin@adm01:~/src/k8s$ KUBECONFIG=~/.config/workbook/k8s-checks.kubeconfig GITLAB_TOKEN=<JETON-PROJET-K8S> outils/recommandations-vpa.sh --seuil 30 --mr
   Rapport : rapports/vpa/2026-11-03.md
   MR : https://git01.par1.medisphere.internal/plateforme/k8s/-/merge_requests/57
   ```
7. *Tableau de bord* : [`plateforme-capacite-locataires.json`](fichiers/M28-E14/observabilite/tableaux/plateforme/plateforme-capacite-locataires.json) et les [valeurs de kube-state-metrics](fichiers/M28-E14/observabilite/kps/values.extrait-E14.yaml) (étiquette de locataire des espaces ; VPA en *custom resource state*).
8. [`capacite.md`](fichiers/M28-E14/medisphere/docs/plateforme-dev/capacite.md).

**Explications**

- **Quota d'espace et budget de locataire** sont deux contrôles d'admission indépendants : une création doit passer les deux. Le budget empêche une équipe de multiplier sa capacité en multipliant les espaces ; le quota d'espace protège la production d'un excès de la recette de la même équipe.
- **Priorité 0** : sans `globalDefault`, tout pod sans classe vaut 0, en dessous de `lot` (100). Les composants de plateforme (Argo CD, Kyverno, Prometheus…) sont donc des victimes possibles de préemption par un pod `standard` ou `critique` qui ne trouve pas de place. Un `globalDefault` les remonterait, mais **sans revue** et au gré des redémarrages ; la décision prise est de borner le risque (budgets, `lot` sans préemption) et d'étudier une classe `medisphere-plateforme`.
- **Préemption ≠ éviction** : l'ordonnanceur préempte des pods de priorité inférieure pour placer un pod en attente, en respectant les PDB au mieux ; le kubelet évince sous pression mémoire ou disque, d'abord les pods qui dépassent leurs `requests`, par priorité croissante, **sans** regarder les PDB. Des `requests` justes protègent mieux qu'une priorité.
- **VPA en `Off`** : les recommandations (`target`, bornes `lowerBound`/`upperBound`) existent sans que le VPA touche aux pods ; le script les rapproche des `requests` du gabarit (pour un Rollout en `workloadRef`, celui du Deployment).

**Alternatives**
- Ancien champ `spec.resourceQuotas` (portée `Tenant`) : fonctionne encore en 0.15 mais déprécié ; le migrer maintenant évite une migration forcée plus tard.
- Budget par Kyverno ou par un opérateur de quotas hiérarchiques (HNC, archivé) : plus de pièces, aucun gain.
- Goldilocks (Fairwinds) pour visualiser les recommandations du VPA : interface agréable, mais un composant de plus ; la MR mensuelle place la décision chez l'équipe.

**Pièges classiques**
- `preemptionPolicy: Never` sur `critique` : la production attend comme les autres.
- Un PDB `minAvailable: 1` sur une charge à un réplica : aucun drainage possible (la montée de Kubernetes bloque).
- Oublier la base : un Rollout `critique` qui préempte… sa base `standard`.
- Comparer les recommandations du VPA aux `requests` des **pods** plutôt qu'au gabarit : un pod lancé avant la dernière MR fausse le rapport.
- Mettre la classe dans le Rollout alors que le gabarit vient du Deployment (`workloadRef`).

**En production chez MédiSphère**

Revue trimestrielle des budgets en comité (tableau de bord à l'écran) ; alerte « pods `medisphere-critique` en attente depuis 5 min » ; le rapport VPA mensuel est une tâche planifiée de `plateforme/k8s` (pipeline planifié avec un compte de lecture) ; les essais de charge du M29 tournent en `lot`.

---

### M28-E15 — Isolation des locataires : tenter de s'évader

**Solution**

1. *Compte d'essai* : [`identite/annuaire/personnes.extrait-E15.yml`](fichiers/M28-E15/identite/annuaire/personnes.extrait-E15.yml) (créé sans `etat`, puis `etat: disabled` à la fin) et `membres: [essai-medidoc]` dans le groupe `medidoc` ; contexte à part :
   ```
   admin@adm01:~$ kubectl config set-credentials essai-medidoc --exec-api-version=client.authentication.k8s.io/v1 \
       --exec-command=kubectl --exec-arg=oidc-login --exec-arg=get-token \
       --exec-arg=--oidc-issuer-url=https://sso.par1.medisphere.internal/realms/medisphere \
       --exec-arg=--oidc-client-id=kubernetes --exec-arg=--token-cache-dir=$HOME/.kube/cache/essai-medidoc
   admin@adm01:~$ kubectl config set-context essai-medidoc --cluster=k8s-par1 --user=essai-medidoc
   admin@adm01:~$ kubectl --context essai-medidoc auth can-i --list -n medidoc-dev | head
   ```
   (reprends les arguments de ton kubeconfig OIDC du M24 ; seul le répertoire de cache change, pour ne pas mélanger les jetons.)
2. *Essais* : tableau complet et messages dans [`essais-isolation.md`](fichiers/M28-E15/medisphere/docs/plateforme-dev/essais-isolation.md). Exemples :
   ```
   admin@adm01:~$ kubectl --context essai-medidoc create ns projet-x
   Error from server (Forbidden): admission webhook "…capsule…" denied the request: … (préfixe du locataire attendu)
   admin@adm01:~$ kubectl --context essai-medidoc -n medidoc-essai-isolation create rolebinding moi --clusterrole=cluster-admin --user=essai-medidoc
   error: failed to create rolebinding: … is attempting to grant RBAC permissions not currently held
   admin@adm01:~$ hubble observe --from-namespace medidoc-essai-isolation --to-namespace mediagenda-recette --verdict DROPPED
   ```
   (noms des webhooks et textes exacts : ceux de ta version — relève-les.)
3. *Trous* (lab de référence) : pas de cloison réseau ni de refus par défaut dans les espaces de libre-service ; tolérances et `nodeName` libres ; Service `ExternalName` possible ; PSA du libre-service tenue par un seul verrou (Capsule, E05) ; `LoadBalancer` et `NodePort` refusés seulement « par quota ».
4. *Corrections* :
   - locataires : [`medidoc.yaml`](fichiers/M28-E15/k8s/locataires/medidoc.yaml) (et les deux autres) — fichiers de E05 complétés (E14 : classes de priorité, budget global ; E15 : règle `deny` sur les types de Service) ; les étiquettes PSA et leur interdiction viennent de E05 ;
   - Kyverno : [`locataires-placement`](fichiers/M28-E15/politiques/kyverno/validation/locataires-placement.yaml), [`locataires-pod-security`](fichiers/M28-E15/politiques/kyverno/validation/locataires-pod-security.yaml), condition élargie de [`networkpolicy-par-defaut`](fichiers/M28-E15/politiques/kyverno/generation/networkpolicy-par-defaut.extrait-E15.yaml), [`kustomization`](fichiers/M28-E15/politiques/kyverno/kustomization.extrait-E15.yaml) ;
   - réseau : [`isolement-locataire-medidoc`](fichiers/M28-E15/k8s/composants/reseau/politiques/isolement-locataire-medidoc.yaml), [`-mediagenda`](fichiers/M28-E15/k8s/composants/reseau/politiques/isolement-locataire-mediagenda.yaml), [`-medinotif`](fichiers/M28-E15/k8s/composants/reseau/politiques/isolement-locataire-medinotif.yaml).
   Un espace créé **avant** la correction n'a ni ses étiquettes PSA (Capsule les pose à la réconciliation suivante) ni sa NetworkPolicy (la GeneratingPolicy ne se déclenche qu'à la création ou à la modification) : supprime et recrée `medidoc-essai-isolation`.
5. *Rejeu* puis nettoyage : `kubectl --context essai-medidoc delete ns medidoc-essai-isolation` ; MR `etat: disabled` ; `kubectl config delete-context essai-medidoc`.
6. [`essais-isolation.md`](fichiers/M28-E15/medisphere/docs/plateforme-dev/essais-isolation.md).

**Explications**

- **Qui fait quoi.** RBAC dit ce qu'une identité peut faire (le propriétaire est `admin` de ses espaces, rien ailleurs ; la prévention de l'escalade lui interdit de donner des droits qu'il n'a pas). Capsule complète RBAC là où il ne sait pas raisonner « par locataire » : création d'espaces (préfixe, nombre), classes autorisées, types de Service, métadonnées. PSA juge ce qu'un pod demande au noyau. Kyverno porte les règles de la maison que personne d'autre ne connaît (registres, signatures, placement). Cilium décide qui parle à qui.
- **Pourquoi des trous apparaissent avec le libre-service** : tout ce que la plateforme posait **à la main** par espace (`plateforme/k8s/espaces/`, `isolement-<espace>`) ne s'applique pas à un espace créé par l'équipe. Il faut des règles qui suivent une **étiquette** posée automatiquement (`capsule.clastix.io/tenant`), pas une liste.
- **`nodeName`** : l'ordonnanceur respecte les taints `NoSchedule` ; un pod qui arrive déjà affecté à un nœud ne passe pas par lui.
- **Cloison par locataire et exception** : un refus l'emporte sur toute autorisation ; pour garder l'appel MédiAgenda → MédiDoc (M23-E06), la cloison exclut explicitement le pod de l'API, en entrée chez MédiDoc et en sortie chez MédiAgenda (deux politiques, parce qu'un refus porte sur le pair et qu'il faut séparer les pods sources par `endpointSelector`).

**Alternatives**
- Niveau PSA par défaut du cluster (`AdmissionConfiguration` de `PodSecurity` avec `defaults.enforce: restricted` et exemptions des espaces de plateforme) : la protection la plus large, mais un changement du plan de contrôle (rôle `k8s_plan_controle`, redémarrage des API) ; à faire aussi, après analyse des espaces système.
- `nodeSelector` de locataire Capsule (tous les pods du locataire sur un groupe de nœuds) : utile avec un pool dédié par équipe ; ici trois travailleurs partagés.
- Politiques Cilium générées par Kyverno par espace : plus de pièces que la sélection par étiquette d'espace.

**Pièges classiques**
- Tester avec son propre compte d'administrateur : tout passe, rien n'est prouvé.
- Confondre « refusé par hasard » (le quota `services.loadbalancers: 0` d'un espace existant) et « refusé par conception ».
- Une cloison réseau qui casse un flux légitime (MédiAgenda → MédiDoc) : rejouer les parcours applicatifs après chaque politique.
- Une règle d'admission en `failurePolicy: Fail` sur tous les pods des locataires : si Kyverno tombe, plus aucun pod de production ne démarre.
- Oublier de désactiver le compte d'essai.

**En production chez MédiSphère**

L'essai devient une suite de non-régression (script qui rejoue les essais avec le compte d'essai réactivé pour l'occasion), lancée avant chaque montée de Capsule, Kyverno ou Kubernetes ; résultats joints à l'ADR-0280 ; Sophie Laurent signe le rapport avant l'ouverture du libre-service à une nouvelle équipe.

---

### M28-E16 — Backstage en production : mise à jour, sauvegarde, supervision

**Solution**

1. *Montée de version* :
   ```
   admin@adm01:~/src/portail$ git switch -c montee/1.56.<Z>
   admin@adm01:~/src/portail$ yarn backstage-cli versions:bump --release 1.56.<Z>
   admin@adm01:~/src/portail$ yarn install && yarn tsc && yarn build:backend && yarn test
   admin@adm01:~/src/portail$ git diff --stat backstage.json package.json packages/*/package.json yarn.lock
   ```
   MR (notes de version résumées), CI (construction, Trivy, signature Cosign, étiquette `vX.Y.Z`), MR de promotion dans `plateforme/gitops/valeurs/portail/`.
2. *Deux réplicas* : [`values.extrait-E16.yaml`](fichiers/M28-E16/gitops/valeurs/portail/values.extrait-E16.yaml) (répartition par nœud, PDB, sondes du nouveau backend, classe, ressources, port des métriques, ServiceMonitor) ; `auth.session.secret` lu dans OpenBao.
3. *Sauvegarde* : [`60-portail-db-sauvegarde.yaml`](fichiers/M28-E16/k8s/espaces/portail/60-portail-db-sauvegarde.yaml) + [archivage dans le Cluster](fichiers/M28-E16/k8s/espaces/portail/50-portail-db.extrait-E16.yaml) ;
   ```
   admin@adm01:~$ kubectl cnpg backup portail-db -n portail --method plugin --plugin-name barman-cloud.cloudnative-pg.io
   admin@adm01:~$ kubectl -n portail get backups
   admin@adm01:~$ kubectl -n portail get cluster portail-db -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}{"\n"}'
   True
   ```
   Restauration : [`essais/portail-db-restauration.yaml`](fichiers/M28-E16/essais/portail-db-restauration.yaml) ; contrôle `psql -U postgres -d <base-du-scaffolder> -c 'select count(*) from tasks'` (le nom de la base dépend du mode de séparation des plugins choisi en E06 : `\l` d'abord) ; suppression de l'essai.
4. *Métriques* : [`instrumentation.js`](fichiers/M28-E16/portail/packages/backend/src/instrumentation.js), [Dockerfile](fichiers/M28-E16/portail/Dockerfile.extrait-E16) ; `yarn --cwd packages/backend add @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-prometheus`. Contrôle : `up{namespace="portail", job="portail"}` à 1 (le `job` d'un ServiceMonitor est le nom du Service : `portail`, par `fullnameOverride`), puis `catalog_entities_count`, `http_server_duration_*` ou `http_server_request_duration_seconds_*` (selon les conventions sémantiques de la version de l'instrumentation HTTP), `scaffolder_task_*` (relève les noms exacts sur `/metrics`).
5. *Journaux* : `{namespace="portail"} |= "<taskId>"` dans la source « Loki — plateforme ».
6. *Alertes* : [`regles/portail.yaml`](fichiers/M28-E16/observabilite/regles/portail.yaml) + [test](fichiers/M28-E16/observabilite/tests/portail.test.yaml) ; sonde blackbox `blackbox-portail` ajoutée à `mon01`.
7. [`RB-284`](fichiers/M28-E16/medisphere/docs/plateforme-dev/runbooks/RB-284-portail-indisponible.md), [`portail-exploitation.md`](fichiers/M28-E16/medisphere/docs/plateforme-dev/portail-exploitation.md).

**Explications**

- `versions:bump` aligne toutes les dépendances `@backstage/*` sur une même *release* (et met à jour `backstage.json`) ; il ne réécrit pas les fichiers que `create-app` t'a donnés : les notes de version et l'*Upgrade Helper* disent ce qu'il faut y reporter.
- Deux réplicas d'un backend Backstage partagent la base ; les tâches planifiées (lecture du catalogue, TechDocs…) se coordonnent par la base et ne tournent qu'une fois. Ce qui doit être identique entre les deux : la configuration, le secret de session de l'authentification, les clés de l'accès externe (jeton des checks).
- Le plugin Barman Cloud : l'archivage continu des WAL (`isWALArchiver`) + des sauvegardes de base = restauration à un instant précis ; sans archiveur, pas de sauvegarde « plugin ».
- Les métriques de Backstage passent par l'API d'OpenTelemetry : il faut un SDK démarré **avant** le backend (d'où `--require`) et un exportateur.

**Alternatives**
- Métriques par le Collector OpenTelemetry du M23 (exportateur OTLP vers `otel-passerelle`, puis Prometheus) : une seule voie pour les traces et les métriques ; plus de pièces pour un premier pas.
- Sauvegarde logique (`pg_dump` en CronJob) : simple, mais sans restauration à un instant précis et hors du modèle de la maison.
- Montée de version par Renovate : utile pour la cadence, mais il change les versions une à une ; `versions:bump` reste l'outil qui garde l'ensemble cohérent.

**Pièges classiques**
- Deux réplicas avec un secret de session généré au démarrage : déconnexions aléatoires.
- Sonde de vivacité sans sonde de démarrage : le pod est tué pendant ses migrations, au premier démarrage d'une version.
- ServiceMonitor qui vise un port non déclaré dans le Service : cible absente, aucune erreur.
- Oublier `!packages/backend/src/instrumentation.js` dans `.dockerignore` : l'image démarre… et échoue sur `--require`.
- Restaurer « par-dessus » `portail-db` : on restaure toujours dans un **nouveau** cluster.

**En production chez MédiSphère**

Montée mensuelle planifiée (Renovate ouvre le rappel, `versions:bump` fait le travail) ; restauration éprouvée chaque trimestre ; alertes en heures ouvrées seulement (le portail n'est pas sur le chemin critique des patients) ; journal d'audit du *scaffolder* conservé dans Loki (qui a créé quoi).

---

### M28-E17 — ADR : la plateforme développeurs de MédiSphère

**Solution** : [`ADR-0280-plateforme-developpeurs.md`](fichiers/M28-E17/medisphere/docs/plateforme-dev/adr/ADR-0280-plateforme-developpeurs.md).

**Explications** : un ADR utile se lit sans avoir fait les exercices : contexte chiffré, décision, coût, alternatives avec la raison de leur rejet **et** la condition qui ferait changer d'avis. Les chiffres de l'exemple sont ceux du lab de référence : remplace-les par tes mesures.

**Alternatives** : un ADR par décision (portail, multi-locataire, autoscaling) — plus granulaire, mais Claire présente une **plateforme** ; un ADR de synthèse qui renvoie à des notes techniques (`autoscaling.md`, `capacite.md`, `essais-isolation.md`) est le bon équilibre.

**Pièges classiques**
- « Crossplane n'est pas retenu car trop complexe » : un jugement, pas une raison. La raison : rien à piloter derrière, et OpenTofu fait déjà le travail.
- Oublier les coûts humains (montées mensuelles de Backstage, essais d'isolation à rejouer).
- Pas de condition de révision : la décision devient un dogme.

**En production chez MédiSphère** : l'ADR est relu en comité, signé (statut « Accepté » + date), et référencé par les fiches de découverte et par le guide d'accueil des équipes (E12).

---

### M28-E18 — Questions de production : plateforme développeurs

1. **Réveil depuis 0.** L'opérateur KEDA interroge la file toutes les `pollingInterval` secondes (15 s) ; la valeur dépasse l'activation (0) : KEDA passe le Deployment à 1 réplica (ou à `minReplicaCount` s'il est plus grand) en écrivant `spec.replicas` par la sous-ressource `scale` ; le contrôleur de ReplicaSet crée le pod ; l'ordonnanceur le place ; le kubelet tire l'image (souvent en cache) et démarre le conteneur ; MédiNotif se connecte en AMQPS et consomme. Ensuite l'HPA prend le relais pour 1 → N. Durée ≈ attente de l'interrogation (0-15 s) + démarrage du pod (2-6 s). La réduire : interrogation plus fréquente (charge sur l'API de RabbitMQ), image plus légère, ou un pod toujours présent : on échange du coût contre de la latence. Faux : « l'HPA réveille le pod » — un HPA ne descend jamais sous 1.
2. **Zéro pour MédiNotif, pas pour MédiAgenda.** Un message peut attendre 20 s dans une file durable ; une requête HTTP d'un patient, non : elle n'a nulle part où attendre si aucun pod n'existe. Il faudrait un intercepteur qui retienne la requête pendant le réveil : KEDA HTTP add-on (bêta) ou Knative ; coût : un démarrage à froid de plusieurs secondes sur la première requête, inacceptable sur un service patient (SLO de latence à 250 ms). Faux : « MédiAgenda est trop gros » — le problème est le mode d'appel, pas la taille.
3. **Calcul.** `AverageValue` : réplicas = ⌈valeur ÷ seuil⌉. File : 30 000 / 500 = 60 ; cron : 10 ; Prometheus : 40 / 10 = 4. Max = 60, borné par `maxReplicaCount` → **50**. Scaler `rabbitmq` en erreur avec repli `static` de 4 : la métrique servie vaut seuil × 4 = 2 000 → 4 réplicas pour ce déclencheur ; max(4, 10, 4) = **10** (le cron domine). Faux : « le repli impose 4 au total » — il remplace la métrique du déclencheur, l'HPA garde le maximum des métriques : la documentation de KEDA 2.21 décrit un suivi des échecs **par scaler** ; les déclencheurs sains continuent de compter.
4. **VPA automatique + HPA CPU.** L'HPA calcule l'utilisation en pourcentage des `requests` ; le VPA change ces `requests` d'après la consommation : chaque correction de l'un déplace la cible de l'autre (le VPA monte les `requests` → l'utilisation baisse → l'HPA retire des pods → la consommation par pod monte → le VPA monte encore…), avec des redémarrages de pods à chaque tour. Combinaison acceptable : VPA sur la **mémoire** seule (`controlledResources: [memory]`) et HPA sur le CPU ou sur une métrique externe (KEDA), ou VPA en `Off` (recommandation) — le choix de MédiSphère.
5. **Autoscaling de nœuds.** Le Cluster Autoscaler sait piloter Cluster API (fournisseur `clusterapi`) et Cluster API sait créer des VMs Proxmox (CAPMOX, M18) ; mais `k8s-par1` n'est pas un cluster Cluster API, et surtout la capacité physique de `pve01` est fixe : un nœud de plus, c'est de la mémoire prise à autre chose. Karpenter n'a pas de fournisseur Proxmox maintenu par son projet. Ce qui remplace : budgets par locataire, priorités, bilan de capacité et achat de matériel planifié. Faux : « c'est impossible sur site » — c'est possible avec une réserve de capacité, qui n'existe pas ici.
6. **Préemption vs éviction.** Préemption : décision de l'**ordonnanceur** pour placer un pod en attente ; ne vise que des priorités inférieures ; respecte les PDB « au mieux » (il préfère des victimes qui ne violent pas de PDB, mais peut les violer) ; laisse le délai de grâce. Éviction : décision du **kubelet** sous pression (mémoire, disque) ; classe les pods par dépassement des `requests` puis par priorité ; **ignore** les PDB. L'API d'éviction (`kubectl drain`) est une troisième chose : elle respecte strictement les PDB.
7. **Budget presque plein.** À la **création du pod** (par le contrôleur du ReplicaSet), l'admission refuse : `exceeded quota` (budget global du locataire, ou quota de l'espace) ; le Deployment existe, aucun pod n'apparaît, le message est dans les événements du ReplicaSet (`kubectl describe rs`). Sans `requests` : si l'espace a un `LimitRange` avec `defaultRequest`, la valeur par défaut est posée puis comptée ; sinon, un quota sur `requests.cpu` **refuse** le pod (`must specify requests.cpu`). Faux : « le pod reste Pending » — il n'est jamais créé.
8. **CRD propres ou simples espaces.** CRD et opérateurs à soi : vCluster (les CRD sont des objets cluster, aucun locataire Capsule ne peut en installer sans ouvrir le cluster entier). Simples espaces : Capsule — moins cher, une seule chose à exploiter, isolation éprouvée.
9. **Crossplane.** Il transforme des API de fournisseurs (bases managées, compartiments, DNS) en ressources Kubernetes composables ; chez MédiSphère il n'y a pas de catalogue de services managés à exposer, les fournisseurs Proxmox et PowerDNS sont communautaires, et OpenTofu + Ansible + MR font déjà le travail avec un état versionné. Avis à revoir si plusieurs équipes demandent en libre-service des ressources hors cluster de façon récurrente, ou si un cloud public arrive.
10. **Tilt / Skaffold.** Ils automatisent la boucle interne (modifier → construire → déployer dans un cluster de développement → voir) avec rechargement à chaud. `docker compose` (M12) lance déjà MédiAgenda, PostgreSQL et Valkey en local, ce qui suffit à trois applications simples. Ils apporteraient un « environnement de dev dans Kubernetes » cohérent avec les manifestes de la recette ; au prix d'un cluster de développement par développeur (kind, k3d) et d'un outil de plus à maintenir dans le modèle `nouveau-service`.
11. **Coût du portail.** Mémoire ≈ 1,1 Gio (deux réplicas + base), stockage ≈ 1 Gio (base) + les sauvegardes et les TechDocs, et surtout le temps : montée mensuelle (≈ ½ journée), entretien des modèles et des plugins (≈ 1 journée par mois). Justification : création d'un service en minutes au lieu de dix jours, propriétaires connus, documentation trouvable. À retirer si les équipes ne l'utilisent pas (mesure : entités consultées, tâches du *scaffolder* par mois) ou si le coût de montée explose.
12. **Portail en panne une journée.** Plus de création par modèle, plus de catalogue ni de TechDocs. Tout le reste marche : applications, déploiements (MR → Argo CD), supervision, GitLab. C'est voulu : le portail est une **vue** et un **générateur de MR**, pas un plan de contrôle ; la vérité est dans Git. Faux : « les déploiements s'arrêtent ».
