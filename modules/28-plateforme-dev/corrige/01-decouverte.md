# Module 28 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice : `gitops/` reproduit `plateforme/gitops`, `k8s/` `plateforme/k8s`, `charts-miroir/` les entrées de `charts.yaml`, `donnees/` `plateforme/donnees`, `secrets/` `plateforme/secrets`, `mediagenda-deploiement/`, `medinotif-deploiement/`, `medidoc-deploiement/` les dépôts de déploiement, `medisphere/` la documentation. Un fichier `*.extrait-*` ne contient que ce qui change ; un fichier sans ce suffixe est complet.

**Ce qui a été vérifié à la rédaction** (23/10/2026) :
- empreintes des charts dans les index amont **et** recalculées sur les archives téléchargées : `keda` 2.21.0, `vpa` 5.1.0 (VPA 1.7.1), `capsule` 0.15.1 ;
- les trois charts rendus par `helm template` (Helm 4) avec nos valeurs : images de Harbor, arguments de `keda-operator` (`--ca-dir=/custom/ca`), ClusterRole de l'opérateur KEDA (règle `list`/`watch` sur **tous** les Secrets par défaut ; règle `rollouts/scale` — un `kind: Rollout` dans `scaledRefKinds` produit une règle `Rollout/scale` sans effet), certificats cert-manager de KEDA, `APIService` `v1beta1.external.metrics.k8s.io` → `keda/keda-operator-metrics-apiserver:443` ; VPA : webhook `vpa-webhook-config` en `failurePolicy: Ignore`, Jobs `certgen` en crochets Helm (le second écrit le `caBundle` après coup) ; Capsule : `CapsuleConfiguration` rendue (`users`, `administrators`, `forceTenantPrefix`), webhooks dynamiques en `failurePolicy: Fail`, contrôleur lié à `cluster-admin` (mode `strict` désactivé par défaut) ;
- CRD lues dans les archives : `Tenant` v1beta2 (champs dépréciés : `resourceQuotas`, `limitRanges`, `networkPolicies`, `additionalMetadataList`, `forbiddenLabels`… ; champs utilisés : `rules[].quota`, `rules[].permissions.bindings`, `namespaceOptions.additionalMetadataList`, `forbiddenLabels`, `storageClasses`, `preventDeletion`), `CapsuleConfiguration` v1beta2 (`users`, `administrators` ; `userGroups`/`userNames` dépréciés, ainsi que les noms de webhooks d'`overrides`), `VerticalPodAutoscaler` v1 (modes `Off`, `Initial`, `Recreate`, `InPlaceOrRecreate`, `InPlace`, `Auto` ; défaut `Recreate` ; `updatePolicy.minReplicas`), `ScaledObject`/`TriggerAuthentication` 2.21.0 ; nos objets validés contre ces schémas (validation stricte, champs inconnus refusés) ; manifestes standard et CiliumNetworkPolicy par `kubeconform -strict` ;
- scaler `rabbitmq` lu dans le code de KEDA v2.21.0 (`QueueDeclarePassive` en AMQP ; `GET /api/queues/<vhost>/<file>` en HTTP ; `host` lisible depuis la `TriggerAuthentication`) ; page *Access Control* de RabbitMQ (déclarations passives : au moins une permission sur la ressource depuis 4.3.1) ; noms des métriques de KEDA lus dans le code (`keda_scaler_detail_errors_total`, `keda_scaled_object_errors_total`) ;
- `mediagenda/deploiement` : component `autoscaling` rendu par `kustomize build` (5.8) avec un Rollout de test : `remove /spec/replicas` effectif ; **un `replace /spec/replicas` resté dans l'overlay recrée le champ sans erreur** (d'où la consigne de l'indice 2 et le correctif de la prod) ;
- `ressources/E02-charge/charge.sh` : `shellcheck`, refus d'une URL de production vérifié ; corps de création conforme au modèle `RendezVousCreation` d'`apps/mediagenda`.

**Points non testés en conditions réelles** (pas de cluster à la rédaction ; signale tout écart) : sorties de commandes montrées (représentatives) ; transfert de propriété de `spec.replicas` (gestionnaires de champs) pendant la transition d'E02 ; l'API de gestion de RabbitMQ consultée par un utilisateur `management` dont les permissions valent `^$` (visibilité de la file, à confirmer par `curl` avec ce compte) ; la confiance TLS de KEDA par `--ca-dir` vers la chaîne `openbao-services` ; le VPA sur une cible `Rollout` (sous-ressource `scale`) ; le redimensionnement en place sur `k8s-par1` ; le comportement de Capsule 0.15 quand l'étiquette du locataire est posée par un administrateur sans référence de propriétaire ; le nom exact des RoleBindings créés par les règles du `Tenant`.

---

### M28-E01 — Test de positionnement : plateforme développeurs

**Barème** : 2 points par question (2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc), sur 24. Sous 12, relis les « Concepts clés » de l'introduction avant E02. Les questions 1 à 4 sont reprises en E02 et E24, 5 à 7 en E03 et E13, 8-9 en E04, 10-11 en E05, E09 et E15, 12 en E06 à E08 et E12.

**1. Calcul.** Utilisation moyenne = 140 / 100 = 140 % ; `désiré = ceil(3 × 140 / 70) = ceil(6) = 6`. Avec un pod sans métrique : à la montée, le contrôleur le compte à **0 %** de la cible (prudence : il ne gonfle pas la moyenne), donc moyenne = (140 + 140 + 0) / 3 ≈ 93 % → `ceil(3 × 93,3 / 70) = ceil(4)` = 4 ; à la descente il le compterait à 100 % de la cible. Les pods pas encore prêts sont mis de côté pour le CPU (fenêtre de démarrage). Écart sous la tolérance de 10 % : aucune action.

**2. Réponse B.** La fenêtre de stabilisation à la descente retient la plus haute recommandation des N dernières secondes (l'HPA ne retire pas des pods sur un creux de quelques minutes) et la politique limite la vitesse de retrait. A est faux : une cible plus basse fait monter plus haut et plus souvent, l'oscillation reste. C est faux : on paie 6 pods la nuit, ce n'est plus de l'autoscaling. D est faux : un VPA ne change pas le nombre de pods et un mode actif évince des pods.

**3. Combat avec Argo CD.** Git déclare `spec.replicas` ; l'HPA le change ; Argo CD voit une dérive et (avec `selfHeal`) remet la valeur du dépôt, l'HPA la rechange… Deux parades : retirer `replicas` du manifeste (inconvénient : la transition — si personne d'autre ne possède le champ, l'application côté serveur le supprime et la charge retombe à 1 le temps que l'HPA réagisse) ; ou `ignoreDifferences` sur `/spec/replicas` avec `RespectIgnoreDifferences` (inconvénient : Argo CD reste copropriétaire du champ et le dépôt ment sur l'état ; un diff sans l'option remet la valeur). Les deux ensemble : le dépôt ne déclare plus, et le filet couvre un oubli.

**4. Familles de métriques.** *Resource* : CPU, mémoire des pods, `metrics.k8s.io` (metrics-server). *Pods* : une métrique par pod (ex. requêtes/s), moyennée, `custom.metrics.k8s.io` (un adaptateur : prometheus-adapter…). *Object* : une métrique d'un autre objet du cluster (ex. trafic d'un Ingress), `custom.metrics.k8s.io`. *External* : une valeur hors cluster (file, requête Prometheus), `external.metrics.k8s.io` (KEDA, prometheus-adapter…). Chaque API est une `APIService` avec **un** service derrière.

**5. Réponse B.** Une `APIService` (`v1beta1.external.metrics.k8s.io`) pointe vers **un** Service : la dernière installée l'emporte (ou l'installation échoue selon l'outil), et les métriques de l'autre disparaissent pour tous les HPA qui en dépendaient. A est faux : il n'y a aucun partage. C est faux : KEDA démarre, c'est l'agrégation qui casse. D est faux : KEDA sert `external.metrics.k8s.io`.

**6. KEDA.** Il fournit des **scalers** (sources d'événements), un adaptateur `external.metrics.k8s.io`, et gère **l'activation** : de 0 à 1 et de 1 à 0 selon `activationValue` et `cooldownPeriod`. De 1 à N, il crée et tient à jour un **HPA** qui interroge son adaptateur. Un HPA classique ne descend pas sous `minReplicas` ≥ 1 (sauf `HPAScaleToZero`, alpha jusqu'en 1.36 — notre version —, bêta et active par défaut à partir de 1.37, et sur métriques Object/External seulement) et, à 0 pod, n'a plus de métrique *Resource* pour décider de remonter.

**7. Droits du scaler RabbitMQ.** AMQP : déclaration passive de la file → depuis RabbitMQ 4.3.1, au moins une permission (`configure`, `write` ou `read`) sur la file ; chacune donne un pouvoir sur les messages ou la file (lire = consommer, écrire = publier, configurer = supprimer). HTTP : étiquette `management` (ou `monitoring`) et une entrée de permissions sur le vhost, qui peut ne correspondre à aucune ressource (`^$`) : **HTTP donne le moins de pouvoir**, et compte en plus les messages non acquittés. `monitoring` voit tous les vhosts : `management` est plus étroit.

**8. VPA.** *Recommender* : calcule les recommandations (historique de consommation, percentiles, marge) et les écrit dans le statut. *Updater* : applique quand le mode le permet (évince les pods trop loin de la recommandation, ou les redimensionne en place). *Admission-controller* : réécrit les `requests` des pods à leur création. `Off` : recommandations seulement (l'admission-controller ne touche rien). `Initial` : les nouveaux pods reçoivent les recommandations, l'updater n'évince pas. `Recreate` : éviction des pods à corriger, les remplaçants sont réécrits à la création. `InPlaceOrRecreate` : redimensionnement en place si possible, sinon éviction.

**9. Réponse B.** L'HPA mesure `consommation / requests` ; le VPA change les `requests` d'après la consommation : chaque action de l'un modifie la mesure de l'autre. A est faux : rien n'empêche de les créer ensemble. C est faux : le VPA n'écrit pas `replicas`. D est faux : deux cibles « égales » ne suppriment pas le couplage. (VPA sur la mémoire et HPA sur une métrique externe : acceptable.)

**10. Souple ou dur.** Souple : locataires qui se font confiance (équipes d'une même entreprise), plan de contrôle et nœuds partagés, séparation par espaces, RBAC, quotas, politiques (Capsule, espaces nommés). Dur : locataires qui ne se font pas confiance (clients d'un hébergeur SaaS), séparation du plan de contrôle (clusters virtuels, clusters dédiés) voire du noyau (gVisor, Kata, nœuds dédiés). MédiSphère : souple — mêmes employeurs, même politique de sécurité, une seule équipe Plateforme ; le dur coûterait des clusters et de l'exploitation pour un risque qui n'existe pas (le « tiers » de la revue E11 est l'exception à traiter).

**11. Capsule ou vCluster.** Capsule ne sépare que les **espaces** (et les droits, quotas, classes) dans une API partagée ; vCluster sépare le **plan de contrôle** (une API par équipe) mais pas les nœuds. Dans un vCluster, l'équipe peut installer des CRD, opérateurs, webhooks, ClusterRoles, choisir sa version ; pas dans un locataire. Inversement, les garde-fous de la plateforme (Kyverno, quotas, Pod Security) s'appliquent directement et lisiblement dans un locataire, et seulement à la synchronisation (erreurs différées) dans un vCluster.

**12. Portail.** Un portail regroupe ce qu'une équipe doit savoir et faire (catalogue, documentation, état, création). Un chemin balisé est la façon recommandée et outillée de faire une tâche courante. Le catalogue est l'inventaire des logiciels, de leurs propriétaires et de leurs relations. Propriétaire = groupe : les personnes changent de poste, partent, tombent malades ; un groupe se gère dans l'annuaire et a toujours quelqu'un. Échecs classiques : catalogue rempli une fois à la main puis faux (il faut la découverte automatique) ; portail imposé sans chemin balisé utile (personne n'y va) ; modèles qui génèrent un code jamais maintenu ; plugins accumulés sans mise à jour.

---

### M28-E02 — HPA : MédiAgenda suit sa charge

**Solution**

1. **La cible.**
   ```
   admin@adm01:~$ kubectl get crd rollouts.argoproj.io -o jsonpath='{.spec.versions[?(@.name=="v1alpha1")].subresources}' | jq .
   { "scale": { "labelSelectorPath": ".status.selector", "specReplicasPath": ".spec.replicas", "statusReplicasPath": ".status.HPAReplicas" }, "status": {} }
   admin@adm01:~$ kubectl get --raw /apis/argoproj.io/v1alpha1/namespaces/mediagenda-recette/rollouts/mediagenda/scale | jq '{spec, status}'
   { "spec": { "replicas": 2 }, "status": { "replicas": 2, "selector": "app.kubernetes.io/component=api,app.kubernetes.io/instance=mediagenda,app.kubernetes.io/name=mediagenda,…" } }
   ```
   L'objet `Scale` (`autoscaling/v1`) ne porte que le nombre voulu, le nombre actuel et le sélecteur : c'est tout ce que l'HPA lit et écrit.
2. **Les requêtes.** `kubectl top pods -n mediagenda-recette`, puis sous charge (`charge.sh -d 300`) ; PromQL dans [`autoscaling.md`](fichiers/M28-E02/medisphere/docs/plateforme-dev/autoscaling.md). Valeurs (à remplacer par les tiennes) dans [`values-communes.extrait`](fichiers/M28-E02/mediagenda-deploiement/base/values-communes.extrait-M28-E02.yaml) : CPU 200 m, mémoire 192 Mi, limite 384 Mi. `outils/rendre-base.sh`, rendu commité (M17-E09).
3. **L'HPA.** [`components/autoscaling/`](fichiers/M28-E02/mediagenda-deploiement/components/autoscaling/) : HPA `mediagenda` (Rollout, CPU 70 %, `behavior`) et `remove /spec/replicas` sur le Rollout. Overlays : [recette](fichiers/M28-E02/mediagenda-deploiement/overlays/recette/kustomization.extrait-M28-E02.yaml), [prod](fichiers/M28-E02/mediagenda-deploiement/overlays/prod/kustomization.extrait-M28-E02.yaml) — en prod, l'ancien `replace /spec/replicas` **disparaît** et un correctif fixe 3 → 6. Contrôle :
   ```
   admin@adm01:~/src/mediagenda-deploiement$ kustomize build overlays/prod | yq 'select(.kind == "Rollout") | .spec.replicas'
   null
   admin@adm01:~/src/mediagenda-deploiement$ kustomize build overlays/prod | yq 'select(.kind == "HorizontalPodAutoscaler") | .spec | [.minReplicas, .maxReplicas]'
   [3, 6]
   ```
4. **Argo CD.** [`mediagenda.extrait`](fichiers/M28-E02/gitops/applications/mediagenda.extrait-M28-E02.yaml). Ordre (détail et raison dans `autoscaling.md`) : MR `plateforme/gitops` d'abord (rien ne bouge) ; MR du dépôt de déploiement avec l'HPA **seul** (Git déclare encore `replicas`, Argo CD recopie la valeur vivante) ; transfert de propriété si l'HPA n'a encore rien écrit ; enfin MR du retrait (`remove /spec/replicas` du component, `replace` de la prod supprimé). Lecture des gestionnaires :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette get rollout mediagenda --show-managed-fields -o json \
     | jq -r '.metadata.managedFields[] | select(.fieldsV1["f:spec"]["f:replicas"]) | "\(.manager) \(.operation) \(.subresource // "")"'
   argocd-controller Apply                 # avant : Git déclare replicas
   kube-controller-manager Update scale    # dès que l'HPA a changé la valeur une fois
   ```
   Si seul `argocd-controller` apparaît (prod : l'HPA n'a rien changé depuis sa création), transfère la propriété comme le documente Kubernetes (*Server-Side Apply*, section sur le transfert à l'HPA) :
   ```
   admin@adm01:~$ cat > /tmp/rollout-replicas-seulement.yaml <<'EOF'
   apiVersion: argoproj.io/v1alpha1
   kind: Rollout
   metadata: {name: mediagenda, namespace: mediagenda-prod}
   spec: {replicas: 3}
   EOF
   admin@adm01:~$ kubectl apply --server-side --field-manager=transfert-hpa --validate=false -f /tmp/rollout-replicas-seulement.yaml
   ```
   Même valeur que la valeur vivante : rien ne bouge, `transfert-hpa` devient copropriétaire ; un conflit avec `kube-controller-manager` veut dire que l'HPA a déjà le champ (ne rien faire). Après la MR du retrait, `argocd-controller` ne possède plus `spec.replicas`. C'est le seul `kubectl apply` hors Argo CD du module sur un environnement : il n'écrit aucune valeur nouvelle (relis `spec.replicas` juste avant), et il est consigné dans `autoscaling.md`. Dans l'ordre naïf (HPA et retrait dans la même MR), Argo CD abandonne le champ avant que l'HPA ne l'ait écrit : l'API le supprime et le Rollout retombe à 1 pod quelques dizaines de secondes.
5. **Recette.**
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette describe hpa mediagenda | sed -n '/Conditions/,$p'
     AbleToScale     True    ReadyForNewScale    recommended size matches current size
     ScalingActive   True    ValidMetricFound    the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
     ScalingLimited  False   DesiredWithinRange  the desired count is within the acceptable range
   admin@adm01:~$ ~/DevOpsPrivateCloud/modules/28-plateforme-dev/ressources/E02-charge/charge.sh -d 300 -c 24 &
   admin@adm01:~$ kubectl -n mediagenda-recette get hpa mediagenda -w
   admin@adm01:~$ kubectl -n mediagenda-recette get events --field-selector involvedObject.name=mediagenda -w
     … SuccessfulRescale  New size: 4; reason: cpu resource utilization (percentage of request) above target
   ```
   Pendant la canary d'une nouvelle version, l'HPA continue d'agir sur le **total** : Argo Rollouts répartit entre stable et canary selon le poids.
6. **Production** : MR, synchronisation manuelle, `describe hpa` ; `kubectl -n mediagenda-prod get rollout mediagenda -o jsonpath='{.spec.replicas}'` → 3.
7. **Grafana** : [panneau](fichiers/M28-E02/observabilite/grafana/mediagenda-replicas.panel.extrait.json) (kube-state-metrics).

**Explications**

L'HPA ne connaît pas Argo Rollouts : il passe par la sous-ressource `scale` que la CRD déclare, comme pour un Deployment. Le nombre « actuel » qu'il lit est `status.HPAReplicas` (« pods non terminés qui reçoivent du trafic actif », d'après le type `RolloutStatus` d'Argo Rollouts) plutôt que `status.replicas` : en bleu-vert, les pods de prévisualisation ne comptent pas ; en canary comme pour MédiAgenda, stable et canary comptent ensemble. La fenêtre de stabilisation à la descente est la parade principale au yo-yo : l'HPA retient, sur 300 s, la **plus haute** recommandation ; la politique `Pods: 1 / 120 s` étale ensuite le retrait. À la montée, fenêtre 0 mais politiques bornées : on réagit vite à un vrai pic, sans réserver le quota de l'espace sur un pic de 20 s.

Les `requests` sont le dénominateur : avec 100 m (valeur du chart), 70 % = 70 m, l'HPA serait monté dès le trafic ordinaire du matin. Avec 200 m, la consommation normale reste sous la cible ; la mémoire n'entre pas dans l'HPA (une application Python ne libère pas sa mémoire en baissant la charge : un HPA sur la mémoire ne redescendrait jamais).

**Alternatives**

- **`ignoreDifferences` seul**, sans retirer `replicas` : marche, mais le dépôt affiche une valeur fausse et `RespectIgnoreDifferences` garde Argo CD copropriétaire du champ (point établi au bloc D).
- **Métrique de requêtes par pod** (`Pods`, `custom.metrics.k8s.io` par prometheus-adapter) : plus juste pour une API, mais un adaptateur de plus ; KEDA (déclencheur `prometheus`, palier 3) le fait sans nouvel adaptateur.
- **HPA dans le chart** (`autoscaling.enabled`) : le chart de MédiAgenda (M17) le rendrait sur le Deployment ; ici la cible est le Rollout, ajouté par un component.

**Pièges classiques**

- Laisser l'ancien correctif `replace /spec/replicas` : kustomize 5.8 le transforme en ajout **sans erreur**, Git redéclare 3 pods, Argo CD les remet contre l'HPA.
- Cibler le Deployment `mediagenda` (à 0 réplica) : combat entre l'HPA et le Rollout (`scaleDown: progressively`).
- Un conteneur annexe sans `requests` CPU : `FailedGetResourceMetric`, l'HPA ne fait plus rien (condition `ScalingActive` fausse).
- Lancer la charge contre la production. `charge.sh` refuse ; un `hey` lancé à la main ne le ferait pas.
- Oublier que le quota de l'espace borne aussi la canary (`maxSurge 25 %`) : `maxReplicas` + surplus doit tenir dans le quota.

**En production chez MédiSphère**

Alerte « HPA au maximum depuis 15 min » (`kube_horizontalpodautoscaler_status_desired_replicas >= kube_horizontalpodautoscaler_spec_max_replicas`) et « métrique indisponible » (`kube_horizontalpodautoscaler_status_condition{condition="ScalingActive",status="false"}`), palier 3 ; revue des bornes avec la capacité de la base (connexions du pooler) ; essai de charge de recette à chaque version majeure (M29, k6).

---

### M28-E03 — KEDA : MédiNotif suit sa file

**Solution**

1. **Avant d'installer** : `kubectl get apiservice v1beta1.external.metrics.k8s.io` → `NotFound`. Lecture du chart : voir les commentaires de [`valeurs/keda/values.yaml`](fichiers/M28-E03/gitops/valeurs/keda/values.yaml).
2. **Chart et espace** : [`charts.extrait`](fichiers/M28-E03/charts-miroir/charts.extrait-M28-E03.yaml) ; [`espaces/keda/`](fichiers/M28-E03/k8s/espaces/keda/) (Namespace, racine, CNP) ; règle d'entrée côté `messagerie` : [`reseau-keda.extrait`](fichiers/M28-E03/donnees/rabbitmq/reseau-keda.extrait-M28-E03.yaml).
3. **Valeurs et Application** : [`values.yaml`](fichiers/M28-E03/gitops/valeurs/keda/values.yaml), [`plateforme/keda.yaml`](fichiers/M28-E03/gitops/plateforme/keda.yaml), destinations de l'AppProject : [`plateforme.extrait-M28`](fichiers/M28-E03/gitops/projets/plateforme.extrait-M28.yaml). Rendu et lecture :
   ```
   admin@adm01:~/src/gitops$ helm template keda oci://registry.par1.medisphere.internal/charts/keda --version 2.21.0 -n keda \
       -f valeurs/keda/values.yaml > /tmp/keda.yaml
   admin@adm01:~/src/gitops$ yq 'select(.kind == "ClusterRole" and .metadata.name == "keda-operator") | .rules[] | select(.resources[] == "secrets")' /tmp/keda.yaml
   apiGroups: [""]
   resources: [secrets]
   verbs: [list, watch]
   admin@adm01:~$ kubectl get apiservice v1beta1.external.metrics.k8s.io -o jsonpath='{.spec.service}{" "}{.status.conditions[0].status}{"\n"}'
   {"name":"keda-operator-metrics-apiserver","namespace":"keda","port":443} True
   ```
4. **ClusterRole des checks** : [`rbac/wb-checks-services-m28.yaml`](fichiers/M28-E03/k8s/rbac/wb-checks-services-m28.yaml), appliquée comme le reste de `rbac/` (`task appliquer` ou ta commande habituelle du M14) ; `kubectl get clusterrole wb-checks -o json | jq '.rules[] | select(.apiGroups[] == "keda.sh")'` montre l'agrégation.
5. **Protocole et compte** : tableau de [`autoscaling.extrait-M28-E03`](fichiers/M28-E03/medisphere/docs/plateforme-dev/autoscaling.extrait-M28-E03.md) ; compte dans [`topologie/medinotif-recette/keda.yaml`](fichiers/M28-E03/donnees/topologie/medinotif-recette/keda.yaml) (ExternalSecret `rabbitmq-utilisateur-keda-recette`, `User` étiquette `management`, `Permission` `^$` × 3, construits comme les comptes du M27-E04 et posés dans `messagerie` par l'Application `rabbitmq-topologie` ; [`kustomization.extrait`](fichiers/M28-E03/donnees/topologie/medinotif-recette/kustomization.extrait-M28-E03.yaml)) ; secret créé dans le coffre :
   ```
   admin@adm01:~$ bao kv put kv/medinotif/recette/keda utilisateur=keda-recette mot_de_passe="$(openssl rand -hex 24)"
   ```
   Lecture de la politique OpenBao d'ESO : [`eso-plateforme.extrait`](fichiers/M28-E03/secrets/politiques/eso-plateforme.extrait-M28-E03.hcl). Contrôle avec le compte (mot de passe lu une fois, jamais affiché) :
   ```
   admin@adm01:~$ rabbitmq_mdp="$(bao kv get -field=mot_de_passe kv/medinotif/recette/keda)"
   admin@adm01:~$ curl -s -K <(printf 'user = "keda-recette:%s"\n' "$rabbitmq_mdp") \
       https://rabbitmq.apps.par1.medisphere.internal/api/queues/medinotif-recette/notifications | jq '{messages, messages_ready, messages_unacknowledged}'
   admin@adm01:~$ unset rabbitmq_mdp
   ```
6. **MédiNotif** : [`overlays/recette/keda/`](fichiers/M28-E03/medinotif-deploiement/overlays/recette/keda/) (ExternalSecret avec l'adresse de l'API en clé `hote`, `TriggerAuthentication` qui ne référence que le Secret, `ScaledObject`), [`kustomization.extrait`](fichiers/M28-E03/medinotif-deploiement/overlays/recette/kustomization.extrait-M28-E03.yaml), [`ApplicationSet medinotif.extrait`](fichiers/M28-E03/gitops/applications/medinotif.extrait-M28-E03.yaml).
7. **Observe** :
   ```
   admin@adm01:~$ kubectl -n medinotif-recette get scaledobject medinotif
   NAME        SCALETARGETKIND      SCALETARGETNAME   MIN   MAX   READY   ACTIVE   FALLBACK   PAUSED
   medinotif   apps/v1.Deployment   medinotif         1     5     True    False    False      False
   admin@adm01:~$ kubectl -n medinotif-recette get hpa keda-hpa-medinotif -o jsonpath='{.spec.metrics[0].external.metric.name}{"\n"}'
   s0-rabbitmq-notifications
   admin@adm01:~$ kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/medinotif-recette/s0-rabbitmq-notifications?labelSelector=scaledobject.keda.sh%2Fname%3Dmedinotif" | jq '.items[0].value'
   "0"
   ```
   Essai : MR `MEDINOTIF_DELAI_ENVOI_MS=500` ; `charge.sh -m rendez-vous -c 16 -d 180` ; suivre la file (commande de l'étape 5), `kubectl -n medinotif-recette get hpa keda-hpa-medinotif -w`, `kubectl -n medinotif-recette get pods -w` ; MR inverse.

**Explications**

KEDA ne remplace pas l'HPA : il le **fabrique** (`keda-hpa-medinotif`, métrique `External` `s0-rabbitmq-notifications`, cible `AverageValue` = `value`) et sert la métrique par son adaptateur ; l'apiserver agrège `external.metrics.k8s.io` vers lui, d'où l'unicité du fournisseur. Le webhook de KEDA refuse un `ScaledObject` dont la cible est déjà pilotée par un autre HPA.

Le choix du protocole est un choix de **droits**. En AMQP, `QueueDeclarePassive` exige depuis RabbitMQ 4.3.1 une permission sur la file : il n'existe aucune permission AMQP qui permette de « voir sans toucher ». En HTTP, l'étiquette `management` montre les objets des vhosts où l'utilisateur a une entrée de permissions, même vide de sens (`^$`) ; le compte ne peut ni publier, ni consommer, ni déclarer. Bonus : l'API compte les messages non acquittés (en cours de traitement), ce qui évite de réduire pendant qu'un worker travaille.

La `TriggerAuthentication` ne contient que des références ; KEDA lit le Secret au moment de construire le scaler. Revers : la ClusterRole de l'opérateur liste **tous** les Secrets du cluster (le `get` restreint par `namesAllowList` ne change rien, `list` renvoie les contenus). C'est un risque accepté et écrit, à trancher dans l'ADR-0280.

**Alternatives**

- **`ClusterTriggerAuthentication` + `permissions.operator.restrict.secret: true`** : KEDA ne lit plus que les Secrets de `keda` ; la plateforme y gère les identifiants des scalers. Plus sûr, moins de libre-service.
- **`hashiCorpVault` dans la `TriggerAuthentication`** : KEDA lit OpenBao directement (méthode Kubernetes) ; plus de Secret du tout, mais une configuration de coffre par scaler et la sortie de `keda` vers OpenBao.
- **Mode `MessageRate`** (HTTP seulement) : suivre le débit d'arrivée plutôt que le stock ; utile pour anticiper (E13).

**Pièges classiques**

- `scaledRefKinds` avec `kind: Rollout` (comme l'exemple commenté du chart) : règle RBAC `Rollout/scale`, sans effet ; il faut la ressource `rollouts`.
- Laisser `replicas` dans le Deployment de MédiNotif : Argo CD et l'HPA de KEDA se battent, comme en E02.
- Utiliser le compte du worker (il a `read` sur la file) : KEDA a alors le pouvoir de consommer des notifications.
- Oublier la barre oblique finale d'une URL sans vhost : le scaler la prend pour le vhost.
- Un mot de passe avec `@`, `:`, `/` : le scaler l'insère dans une URL (limite documentée) ; générer en hexadécimal.
- `unsafeSsl: true` « pour que ça marche » au lieu de donner la racine à l'opérateur.

**En production chez MédiSphère**

Compte `keda-prod` et `ScaledObject` de prod au palier 3 (M28-E13), avec zéro en recette seulement ; alertes sur `keda_scaler_detail_errors_total` et sur l'`APIService` non disponible ; KEDA sur deux réplicas de l'opérateur et de l'adaptateur (ils sont sur le chemin de **tous** les HPA externes) ; revue trimestrielle de la règle des Secrets.

---

### M28-E04 — VPA : des requêtes justes

**Solution**

1. **Chart et CRD** : [`charts.extrait`](fichiers/M28-E04/charts-miroir/charts.extrait-M28-E04.yaml). `helm show crds` : modes `Off`, `Initial`, `Recreate`, `InPlaceOrRecreate`, `InPlace`, `Auto` ; défaut `Recreate` (la description de la CRD 1.7 le dit ; `Auto` n'est plus qu'un ancien nom).
2. **Installation** : [`espaces/vpa/`](fichiers/M28-E04/k8s/espaces/vpa/), [`valeurs/vpa/values.yaml`](fichiers/M28-E04/gitops/valeurs/vpa/values.yaml), [`plateforme/vpa.yaml`](fichiers/M28-E04/gitops/plateforme/vpa.yaml) (avec l'`ignoreDifferences` du `caBundle` écrit par le Job `certgen-patch`). Contrôle :
   ```
   admin@adm01:~$ kubectl -n vpa get deploy
   vpa-admission-controller   1/1 · vpa-recommender   1/1 · vpa-updater   1/1
   admin@adm01:~$ kubectl get mutatingwebhookconfiguration vpa-webhook-config -o jsonpath='{.webhooks[0].failurePolicy}{"\n"}'
   Ignore
   ```
3. **Recommandations** : [`components/recommandations/`](fichiers/M28-E04/mediagenda-deploiement/components/recommandations/) pour MédiAgenda (Rollout), [`vpa.yaml` recette et prod](fichiers/M28-E04/medinotif-deploiement/overlays/) pour MédiNotif, [`vpa.yaml`](fichiers/M28-E04/medidoc-deploiement/overlays/recette/vpa.yaml) pour MédiDoc.
4. **Lecture** :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette get vpa mediagenda -o json | jq '.status.recommendation.containerRecommendations[] | {containerName, target, lowerBound, upperBound, uncappedTarget}'
   admin@adm01:~$ kubectl -n mediagenda-recette describe vpa mediagenda | grep -A2 Conditions
   ```
   Tableau et décisions : [`recommandations-ressources.md`](fichiers/M28-E04/medisphere/docs/plateforme-dev/recommandations-ressources.md).
5. **En place** :
   ```
   admin@adm01:~$ kubectl apply -f ~/DevOpsPrivateCloud/modules/28-plateforme-dev/ressources/E04-essai/essai-vpa.yaml
   admin@adm01:~$ kubectl -n wb-essais patch vpa essai-vpa --type=merge -p '{"spec":{"updatePolicy":{"minReplicas":1}}}'
   admin@adm01:~$ kubectl -n wb-essais get pod -l app.kubernetes.io/name=essai-vpa \
       -o jsonpath='{.items[0].metadata.uid} {.items[0].status.containerStatuses[0].restartCount} {.items[0].status.containerStatuses[0].resources.requests.cpu}{"\n"}'
   admin@adm01:~$ kubectl -n wb-essais patch pod <POD> --subresource resize \
       --patch '{"spec":{"containers":[{"name":"calcul","resources":{"requests":{"cpu":"150m"}}}]}}'
   admin@adm01:~$ kubectl delete -f ~/DevOpsPrivateCloud/modules/28-plateforme-dev/ressources/E04-essai/essai-vpa.yaml
   ```
   (La correction du manifeste, plutôt que le `patch`, est d'ajouter `minReplicas: 1` sous `updatePolicy`.)
6. **Garde-fous** : section « Garde-fous » de `recommandations-ressources.md`.

**Explications**

Le *recommender* garde, par conteneur, un histogramme décroissant de la consommation (CPU par percentile, mémoire par pic sur 8 jours), applique une marge et des planchers, et ne dit « confiant » qu'avec assez d'historique. En `Off`, rien ne change dans le cluster : c'est le mode d'un outil de mesure. L'updater respecte `--min-replicas` (2) pour ne pas interrompre une charge à un seul pod ; `updatePolicy.minReplicas` le surcharge par VPA. Le redimensionnement en place passe par la sous-ressource `resize` du pod (GA en 1.35) ; la `resizePolicy` décide d'un redémarrage du conteneur par ressource, jamais du pod.

Cibler le Rollout : le VPA remonte des pods à leur propriétaire de plus haut niveau ; les pods de MédiAgenda appartiennent aux ReplicaSets du Rollout, pas à ceux du Deployment (à 0).

**Alternatives**

- **Goldilocks** (Fairwinds) : crée des VPA `Off` par espace et affiche un tableau de bord ; pratique, une brique de plus.
- **Recommandations par requêtes Prometheus** (percentiles de `container_cpu_usage_seconds_total` sur 14 jours) : sans VPA, mais sans la logique de marge et de confiance ; M28-E14 l'outille (`recommandations-vpa.sh`).
- **VPA actif sur une charge sans HPA** (Valkey, un worker d'arrière-plan) : envisageable avec `InPlaceOrRecreate`, des bornes et un PDB, par décision écrite.

**Pièges classiques**

- Activer le sous-chart metrics-server du chart : un second metrics-server se bat avec celui du M17 pour l'`APIService` `v1beta1.metrics.k8s.io`.
- Lire une recommandation de dix minutes comme une vérité.
- Croire que `Auto` veut dire « intelligent » : c'est `Recreate` (évictions).
- Passer l'admission-controller en `failurePolicy: Fail` : plus aucun pod ne se crée si son pod tombe.
- Laisser l'essai : un VPA actif oublié dans `wb-essais` évince pour toujours.

**En production chez MédiSphère**

Revue trimestrielle des recommandations (outil du palier 3), changements de `requests` par MR avec la mesure jointe ; supervision du recommender (`vpa_recommender_*`) ; aucun mode actif sans ADR.

---

### M28-E05 — Capsule : un locataire par équipe

**Solution**

1. **Lecture** : `users` (et `administrators`) de type `kind`/`name` en 0.15 ; `capsuleUserGroups`/`userNames` (CRD : `userGroups`, `userNames`) dépréciés. Dans `Tenant` v1beta2 : `resourceQuotas` (→ `rules[].quota`) ; `limitRanges` et `networkPolicies` (→ réplications, `TenantResource`) ; `containerRegistries` et `imagePullPolicies` (→ `rules[].enforce`) ; `podOptions`, `serviceOptions` et, dans `namespaceOptions`, `additionalMetadata`, `additionalMetadataList`, `forbiddenLabels`, `forbiddenAnnotations`, `requiredMetadata` (→ règles de métadonnées, `rules[].enforce.metadata`) ; les `allowedRegex` des classes. MédiSphère garde **pour l'instant** `additionalMetadataList` et `forbiddenLabels` (décision du PLAN, §4.13) : la CRD décrit elle-même la construction `rules` comme « pas encore définitive » ; la migration est à suivre à chaque montée de Capsule (`kubectl explain tenant.spec.rules` et notes de version). `forceTenantPrefix` : un espace créé par un utilisateur Capsule doit être préfixé du nom d'un de ses locataires, et le préfixe désigne le locataire. Un espace qui porte `capsule.clastix.io/tenant` est concerné par les webhooks d'espace de Capsule (sélecteur `Exists`).
2. **Installation** : [`charts.extrait`](fichiers/M28-E05/charts-miroir/charts.extrait-M28-E05.yaml), [`espaces/capsule-system/`](fichiers/M28-E05/k8s/espaces/capsule-system/00-namespace.yaml), [`valeurs/capsule/values.yaml`](fichiers/M28-E05/gitops/valeurs/capsule/values.yaml), [`plateforme/capsule.yaml`](fichiers/M28-E05/gitops/plateforme/capsule.yaml). Ce que le rendu montre : webhooks déclarés **dans la `CapsuleConfiguration`** (`spec.admission`) et créés par le contrôleur ; `failurePolicy: Fail` sur le webhook générique (tous les objets d'espace des espaces rattachés), celui des espaces (tous les espaces du cluster), des PVC, des pods ; contrôleur lié à `cluster-admin`.
3. **Locataires** : [`locataires/`](fichiers/M28-E05/k8s/locataires/) et [`plateforme/locataires.yaml`](fichiers/M28-E05/gitops/plateforme/locataires.yaml).
4. **Rattachement** : étiquettes ([extrait](fichiers/M28-E05/k8s/espaces/rattachement.extrait-M28-E05.yaml)), `task espaces`, puis [`outils/rattacher-locataires.sh`](fichiers/M28-E05/k8s/outils/rattacher-locataires.sh) :
   ```
   admin@adm01:~/src/k8s$ kubectl delete tenant mediagenda --dry-run=server
   Error from server (Forbidden): admission webhook "…tenants…" denied the request: … preventDeletion …
   admin@adm01:~/src/k8s$ outils/rattacher-locataires.sh --a-blanc && outils/rattacher-locataires.sh
   OK  mediagenda-dev : rattaché à mediagenda
   …
   LOCATAIRE    ETAT     ESPACES
   mediagenda   Active   4
   medidoc      Active   2
   medinotif    Active   2
   ```
   (Message exact du refus : à relever sur ton lab.)
5. **Limites dans chaque espace** : [`locataires/limites-par-defaut.yaml`](fichiers/M28-E05/k8s/locataires/limites-par-defaut.yaml) (et sa ligne dans [`kustomization.yaml`](fichiers/M28-E05/k8s/locataires/kustomization.yaml)).
   ```
   admin@adm01:~$ kubectl get globaltenantresource limites-par-defaut
   NAME                 ITEMS   READY   STATUS   AGE
   limites-par-defaut   …       True    …        1m
   admin@adm01:~$ kubectl get limitranges -A | grep -E 'limites-(locataire|defaut)'
   admin@adm01:~$ kubectl -n mediagenda-dev delete limitrange limites-locataire --dry-run=server
   ```
   Lecture de la CRD (chart 0.15.1) : `scope` vaut `Namespace` par défaut (un objet par espace sélectionné ; `Tenant` en poserait un par locataire) ; `resyncPeriod` (60s) est obligatoire ; sans `namespaceSelector`, un bloc vise tous les espaces des locataires sélectionnés ; `policy` : `creation: Owner` (n'adopte pas un objet existant du même nom : erreur), `deletion: Remove` (objet supprimé quand Capsule cesse de le gérer : bloc retiré, espace qui ne correspond plus au sélecteur), `protect: true` (le webhook `replications.validating.projectcapsule.dev` refuse la modification ou la suppression de l'objet tant que Capsule le gère). Le refus du `delete --dry-run=server` est à relever sur ton lab. Kubernetes (*Limit Ranges*) : avec deux `LimitRange` qui portent des valeurs par défaut, celle qui s'applique n'est pas déterministe ; les `min` et `max` de toutes s'appliquent. D'où **deux blocs** : valeurs par défaut, plancher et plafond dans le libre-service ; **plancher seul** dans les environnements, qui gardent leur `LimitRange` d'espace.
6. **Ce que Capsule a posé** :
   ```
   admin@adm01:~$ kubectl -n mediagenda-prod get rolebindings,resourcequotas -o name
   admin@adm01:~$ kubectl get ns mediagenda-prod -o jsonpath='{.metadata.labels}{"\n"}{.metadata.ownerReferences}{"\n"}'
   admin@adm01:~$ argocd app get mediagenda-prod --show-operation | head -5
   ```
   RoleBindings `capsule-mediagenda-…` (`view`) ; aucun quota ajouté dans les environnements (la règle `quota` ne vise que le libre-service) ; Application `Synced`. Orphelins : [extrait des AppProjects](fichiers/M28-E05/gitops/projets/applications.extrait-M28-E05.yaml).
7. **Essai de Sophie** : résultats dans [`locataires.md`](fichiers/M28-E05/medisphere/docs/plateforme-dev/locataires.md) ; exemples :
   ```
   admin@adm01:~$ kubectl create namespace mediagenda-essai-julien --as=oidc:julien.petit --as-group=oidc:mediagenda
   admin@adm01:~$ kubectl create namespace essai-julien --as=oidc:julien.petit --as-group=oidc:mediagenda
   Error from server (Forbidden): admission webhook "…namespaces…" denied the request: The Namespace prefix used doesn't match any available Tenant
   admin@adm01:~$ kubectl auth can-i create deployments -n mediagenda-prod --as=oidc:julien.petit --as-group=oidc:mediagenda
   no
   admin@adm01:~$ kubectl -n mediagenda-essai-julien run zero --image=<IMAGE-HARBOR> --dry-run=server \
       --overrides='{"spec":{"containers":[{"name":"zero","image":"<IMAGE-HARBOR>","resources":{"requests":{"cpu":"0","memory":"0"},"limits":{"cpu":"100m","memory":"64Mi"}}}]}}' \
       --as=oidc:julien.petit --as-group=oidc:mediagenda
   Error from server (Forbidden): pods "zero" is forbidden: [minimum cpu usage per Container is 5m, but request is 0, minimum memory usage per Container is 16Mi, but request is 0]
   ```
   (`<IMAGE-HARBOR>` : n'importe quelle image de la plateforme, par exemple celle d'un témoin du M22. Selon l'ordre des contrôles d'admission, PSA ou Kyverno peuvent refuser d'abord si le pod d'essai ne respecte pas `restricted` : lis le message.)
8. **Cohabitation** : [`locataires.md`](fichiers/M28-E05/medisphere/docs/plateforme-dev/locataires.md).

**Explications**

Capsule ajoute deux choses à Kubernetes : la notion de **propriété** (un espace appartient à un `Tenant` par une référence de propriétaire et une étiquette) et des **webhooks** qui font respecter les règles du locataire. Les droits viennent de RoleBindings qu'il pose et réconcilie dans chaque espace. Par défaut, chaque propriétaire reçoit `admin` partout : c'est pourquoi les propriétaires sont ici en `view` et que l'administration n'est donnée, par une règle, qu'aux espaces **sans** étiquette d'environnement — étiquette que l'équipe ne peut pas poser (`forbiddenLabels`). Le budget du libre-service est une `GlobalResourceQuota` (règle `quota`) : un quota agrégé, réparti en `ResourceQuota` dans chaque espace sélectionné ; Kubernetes applique tous les quotas d'un espace, donc il s'ajoute à ceux de la plateforme sans les remplacer.

La `LimitRange` de la plateforme suit la même logique de propriété : c'est Capsule, pas l'équipe, qui la pose et la remet en état (toutes les `resyncPeriod`) dans chaque espace sélectionné, y compris un espace de libre-service créé à l'instant, sans fichier à ajouter. L'équipe, administratrice de son libre-service, ne peut ni la modifier ni la supprimer : la ClusterRole `admin` ne donne que la lecture des `limitranges`, et le webhook de protection des réplications (`policy.protect`) refuse toute modification qui ne vient pas de Capsule (vérifie sur ton lab ce qu'il répond à un administrateur : étape 5). Le **minimum** est ce qui compte : les valeurs par défaut ne s'appliquent qu'aux `requests` **absentes**, alors qu'un conteneur qui **déclare** une request nulle passe la politique Kyverno `exiger-limites` (M26, présence des clés) et ne réserve rien pour l'ordonnanceur ; le minimum le refuse à l'admission (M28-E23 montre ce qui arrive sans lui). Capsule emprunte l'identité de `capsule-replications` pour écrire : sans `spec.serviceAccount`, il prendrait l'identité par défaut de sa configuration (`impersonation`, `tenantDefaultServiceAccount: default` dans les valeurs du chart), qui n'a pas ce droit.

La référence de propriétaire est la partie dangereuse : le ramasse-miettes supprime un objet dont le propriétaire a disparu. `preventDeletion` (webhook) et `Prune=false,Delete=false` (Argo CD) empêchent cette disparition ; le script refuse d'agir sans eux.

Cohabitation : Pod Security et Kyverno sont indépendants de Capsule (tous les contrôles d'admission doivent accepter) ; Argo CD n'est pas un utilisateur Capsule, il n'est pas contraint par les règles des propriétaires, mais ses objets passent par les webhooks génériques (ex. classe de stockage d'un PVC dans un espace rattaché).

**Alternatives**

- **Espaces nommés + RBAC + quotas « à la main »** (ce qu'on faisait depuis M14) : suffisant sans libre-service ; Capsule apporte la création par l'équipe et l'agrégation.
- **Hierarchical Namespaces (HNC)** : projet arrêté ; **Kiosk** : abandonné.
- **Kyverno `GeneratingPolicy`** pour poser quotas et RoleBindings à la création d'un espace : possible, mais il faudrait réécrire la propriété, le préfixe et l'agrégation.
- **Kyverno `GeneratingPolicy`** (`policies.kyverno.io/v1`, comme `networkpolicy-par-defaut` au M26) pour la `LimitRange` : possible (déclenchement sur `capsule.clastix.io/tenant`, `synchronize` pour la recréer), mais il faut `generateExisting` pour les espaces déjà rattachés, des droits supplémentaires pour le contrôleur d'arrière-plan de Kyverno, et rien n'empêche l'équipe de la supprimer entre deux synchronisations ; la réplication de Capsule sélectionne nativement les espaces d'un locataire et protège l'objet. Le champ `limitRanges` du `Tenant`, lui, est déprécié.
- **Rattacher par un `Tenant` qui liste les espaces** : n'existe pas dans Capsule ; c'est l'espace qui pointe vers son locataire.

**Pièges classiques**

- Oublier `clusterRoles` des propriétaires : l'équipe devient `admin` de sa production.
- Oublier l'étiquette d'environnement sur un espace existant (`mediagenda-secours`) : il devient « libre-service », l'équipe y est administratrice.
- Supprimer un `Tenant` (ou l'Application `locataires` avec finaliseur) : suppression en cascade des espaces rattachés.
- Mettre `oidc:plateforme-admins` dans `users` : la plateforme deviendrait soumise aux règles des locataires.
- Ignorer la `failurePolicy: Fail` : Capsule indisponible = plus de pod créé dans les espaces rattachés, plus d'espace créé ni modifié dans tout le cluster.
- Utiliser `spec.resourceQuotas` (déprécié) d'un exemple ancien.
- Répliquer une `LimitRange` **avec valeurs par défaut** dans un espace qui a déjà la sienne : les valeurs par défaut appliquées deviennent imprévisibles.
- Oublier `spec.serviceAccount` de la `GlobalTenantResource` : la réplication échoue faute de droits (`READY` à `False`, message dans le statut).
- Retirer la `LimitRange` d'un espace « à la main » : la protection refuse ; une exception passe par une MR sur `limites-par-defaut.yaml` (et se voit dans l'historique).

**En production chez MédiSphère**

Contrôleur à deux réplicas, PDB et supervision (palier 3, M28-E16/E21) ; politique réseau de refus par défaut et vérification des signatures dans le libre-service (M28-E15) ; revue des locataires dans la revue d'accès trimestrielle (M24-E30) ; RB-280 pour toute nouvelle équipe.
