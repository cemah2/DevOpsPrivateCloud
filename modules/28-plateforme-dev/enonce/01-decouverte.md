# Module 28 — Palier 1 : Découverte

Avant de construire un portail, la plateforme doit savoir **s'adapter** et **partager**. Ce palier fait suivre la charge à MédiAgenda (HPA sur son CPU) et à MédiNotif (KEDA sur sa file), mesure les ressources réellement consommées (VPA en recommandation), puis découpe le cluster en locataires (Capsule). À chaque étape, la même question : qui écrit quel champ, et comment Argo CD le sait-il ?

Prérequis : `lab/bin/check 27 25` vert (`donnees-v1`) ; module 20 (Argo CD, Argo Rollouts, `charts-miroir`) ; module 21 (Prometheus, kube-state-metrics) ; module 24 (groupes OIDC) ; module 25 (OpenBao, ESO) ; module 26 (PSA, Kyverno). Lis [`00-introduction.md`](00-introduction.md), en particulier les règles du module et le bilan de capacité.

---

### M28-E01 — Test de positionnement : plateforme développeurs  `Q` `★★`

> **Ticket PLAT-2901** — *De : Karim Benali*
> Une heure, par écrit, sans moteur de recherche ni IA. Je veux savoir si tu sais pourquoi un HPA oscille avant qu'on en mette partout, et ce qu'un « locataire » veut dire avant qu'on en crée trois. Réponds même là où tu hésites.

**Objectifs pédagogiques**
- Évaluer tes acquis sur l'autoscaling, le multi-locataire et les portails développeurs.
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 12 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

1. Un HPA vise 70 % d'utilisation CPU. Le Rollout a 3 pods qui consomment en moyenne 140 m pour des `requests` de 100 m. Combien de pods l'HPA demande-t-il ? Et si l'un des trois pods n'a pas encore de métrique ? Écris le calcul.

2. *(QCM)* Un HPA sur MédiAgenda monte de 2 à 6 pods en une minute, redescend à 2 cinq minutes plus tard, remonte… Quel réglage traite le mieux cette oscillation ?
   - A. Baisser la cible CPU de 70 % à 40 %
   - B. Une fenêtre de stabilisation à la descente et une politique qui limite le nombre de pods retirés par période
   - C. Augmenter `minReplicas` à 6
   - D. Remplacer l'HPA par un VPA en mode `Recreate`

3. Pourquoi un HPA sur une charge gérée par Argo CD peut-il « se battre » avec la synchronisation ? Donne deux façons d'éviter ce combat et l'inconvénient de chacune.

4. Qu'est-ce qu'une métrique *Resource*, *Pods*, *Object* et *External* pour un HPA ? Par quelle API de l'apiserver chacune passe-t-elle, et qui la sert ?

5. *(QCM)* On installe KEDA dans un cluster où prometheus-adapter sert déjà `external.metrics.k8s.io`. Que se passe-t-il ?
   - A. Les deux adaptateurs se partagent les requêtes
   - B. L'`APIService` ne pointe que vers un seul des deux : les métriques de l'autre disparaissent
   - C. KEDA refuse de démarrer
   - D. Rien : KEDA utilise `custom.metrics.k8s.io`

6. Qu'apporte KEDA par rapport à un HPA seul ? Que fait-il lui-même, et que délègue-t-il à un HPA ? Pourquoi la mise à zéro est-elle hors de portée d'un HPA classique ?

7. Le scaler RabbitMQ de KEDA peut interroger le courtier en AMQP ou par l'API HTTP de gestion. Quels droits RabbitMQ chaque voie exige-t-elle du compte de KEDA ? Laquelle donne le moins de pouvoir sur les messages ?

8. Décris les trois composants du VPA. Que fait chacun en mode `Off`, `Initial`, `Recreate`, `InPlaceOrRecreate` ?

9. *(QCM)* Pourquoi ne met-on pas un VPA en mode actif et un HPA sur le CPU sur la même charge ?
   - A. Le VPA refuse de démarrer si un HPA existe
   - B. Le VPA change les `requests`, donc le pourcentage que l'HPA mesure : les deux boucles se répondent
   - C. Ils écrivent tous deux `spec.replicas`
   - D. Il n'y a aucun problème si les deux visent 70 %

10. Multi-locataire « souple » et « dur » : définis-les, donne un exemple de chacun, et dis où se place MédiSphère et pourquoi.

11. Capsule et vCluster : que sépare chacun (plan de contrôle, espaces, nœuds) ? Qu'est-ce qu'une équipe peut faire dans un vCluster qu'elle ne peut pas faire dans un locataire Capsule ? Et l'inverse en matière de garde-fous ?

12. Qu'est-ce qu'un portail développeurs, un « chemin balisé », un catalogue ? Pourquoi le **propriétaire** d'une entité doit-il être un groupe plutôt qu'une personne ? Cite deux échecs classiques des projets de portail.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) avec la grille du corrigé et calculé ton score sur 24.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions sur l'HPA, pars de la formule de la documentation (`désiré = ceil(actuel × mesuré / cible)`) et demande-toi ce que le contrôleur fait des pods sans métrique ou pas encore prêts.
</details>

<details><summary>Indice 2</summary>

Pour les questions sur les locataires, demande-toi ce qu'un locataire malveillant ou maladroit peut casser chez les autres : l'API (CRD, webhooks), les nœuds, le réseau, la capacité.
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M28-E25) sans relire le corrigé.

---

### M28-E02 — HPA : MédiAgenda suit sa charge  `LAB` `★★`

> **Ticket DEV-2902** — *De : Julien Petit* — *Copie : Karim Benali*
> La nuit, trois pods de MédiAgenda attendent des patients qui dorment ; le lundi matin, les deux de la recette saturent pendant les tests de charge de la recette. Je voudrais que le nombre de pods suive le CPU, en recette puis en production : jamais moins que ce qu'on a aujourd'hui en production (3), jamais plus que ce que le quota de l'espace permet. Karim insiste : pas de yo-yo, et Argo CD ne doit pas remettre le nombre de pods à chaque synchronisation.

**Objectifs pédagogiques**
- Écrire un HPA `autoscaling/v2` sur un Rollout d'Argo (sous-ressource `scale`) avec un `behavior` justifié.
- Fixer des `requests` CPU réalistes, condition d'un pourcentage qui veut dire quelque chose.
- Retirer `replicas` de ce que gère Git sans faire chuter le nombre de pods, et le faire savoir à Argo CD.
- Observer la boucle de l'HPA sous charge (événements, conditions, métriques de kube-state-metrics).

**Prérequis** : M20-E16 (Rollout `mediagenda`, component `canary`), M20-E12 (différences ignorées), M17-E09 (`values-communes.yaml`, `outils/rendre-base.sh`), M21 (kube-state-metrics, Grafana).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Cible | Rollout **`mediagenda`** (`argoproj.io/v1alpha1`), espaces `mediagenda-recette` et `mediagenda-prod` ; conteneur `api` ; `requests` actuelles du chart : CPU 100 m, mémoire 192 Mi |
| Objet à créer | HPA **`mediagenda`**, `autoscaling/v2`, dans un component kustomize **`components/autoscaling`** de `mediagenda/deploiement`, inclus par les overlays `recette` et `prod` |
| Bornes | recette 2 → 4 ; prod 3 → 6 (vérifie qu'elles tiennent dans le quota de chaque espace, `plateforme/k8s/espaces/`) |
| Argo CD | ApplicationSet `mediagenda` (`plateforme/gitops/applications/mediagenda.yaml`) : `RespectIgnoreDifferences` déjà actif pour `recette` et `prod` |
| Charge | [`ressources/E02-charge/charge.sh`](../ressources/E02-charge/charge.sh) depuis `adm01`, contre `https://mediagenda-recette.apps.par1.medisphere.internal` uniquement |
| Supervision | kube-state-metrics (M21) : `kube_horizontalpodautoscaler_status_desired_replicas`, `…_status_current_replicas`, `…_spec_max_replicas` |

**Travail demandé**

1. **La cible.** Vérifie que la CRD `rollouts.argoproj.io` déclare la sous-ressource `scale` (chemins de `replicas`, du statut et du sélecteur). Lis `kubectl get --raw` de la sous-ressource `scale` du Rollout de recette : que contient-elle ?
2. **Les requêtes.** Mesure la consommation CPU et mémoire d'un pod de recette au repos puis sous charge (`kubectl top`, PromQL sur `container_cpu_usage_seconds_total`). Choisis des `requests` CPU et mémoire et une limite mémoire défendables ; change-les dans les valeurs du chart et refais le rendu de la base. Note tes mesures et ton choix dans `docs/plateforme-dev/autoscaling.md`.
3. **L'HPA.** Écris le component `autoscaling` : l'HPA (cible CPU en pourcentage, bornes de recette, `behavior` : montée rapide mais bornée, descente lente avec fenêtre de stabilisation et retrait progressif) et ce qu'il faut pour que `replicas` du Rollout ne soit plus déclaré par Git. Adapte l'overlay `prod` (bornes, et le correctif qui fixait 3 réplicas au Rollout). Rends les deux overlays en local (`kustomize build`) et lis le résultat.
4. **Argo CD.** Ajoute à l'ApplicationSet de quoi ignorer `spec.replicas` du Rollout (filet de sécurité). Explique dans `autoscaling.md` dans quel ordre tu fais les deux MR, et pourquoi cet ordre évite une descente brutale du nombre de pods au moment où Git cesse de déclarer `replicas` (lis les `managedFields` du Rollout avant et après).
5. **Recette.** MR, synchronisation automatique. Contrôle `kubectl describe hpa` : conditions `AbleToScale`, `ScalingActive`, métrique courante. Lance la charge (5 min) et suis en parallèle l'HPA, le Rollout et les événements. Relève : délai avant la première montée, nombre maximal de pods, délai avant le retour au minimum. L'Application `mediagenda-recette` reste-t-elle `Synced` pendant tout l'essai ?
6. **Production.** Même component, bornes de prod, MR approuvée et synchronisation à la main, **sans** essai de charge. Contrôle les conditions de l'HPA et que le Rollout n'est pas descendu sous 3 pods.
7. **Grafana.** Ajoute au tableau de bord de MédiAgenda (M21) un panneau « réplicas désirés / actuels / maximum » par environnement.

**Critères de réussite**
- [ ] HPA `mediagenda` en recette et en prod : cible `Rollout` `argoproj.io/v1alpha1` `mediagenda`, métrique CPU en `Utilization`, `behavior` avec une fenêtre de stabilisation à la descente, `minReplicas` ≥ 2 (recette) et ≥ 3 (prod).
- [ ] Conditions `ScalingActive` vraies (la métrique CPU est calculée) dans les deux espaces.
- [ ] Tous les conteneurs des pods du Rollout ont une `request` CPU.
- [ ] En recette, l'HPA a demandé plus que son minimum dans les dernières 24 h (essai de charge fait), puis est revenu au minimum.
- [ ] Applications `mediagenda-recette` et `mediagenda-prod` `Synced` ; aucune ne remet de valeur dans `replicas`.
- [ ] `docs/plateforme-dev/autoscaling.md` (mesures, choix des `requests`, `behavior`, ordre des MR) est sur `main`.

**Vérification** : `lab/bin/check 28 02`

<details><summary>Indice 1</summary>

`kubectl get crd rollouts.argoproj.io -o jsonpath='{.spec.versions[*].subresources}'`. Pour la sous-ressource d'un objet : `kubectl get --raw /apis/argoproj.io/v1alpha1/namespaces/<espace>/rollouts/<nom>/scale`.
</details>

<details><summary>Indice 2</summary>

Le transformateur `replicas` de Kustomize ne connaît pas les Rollouts. Regarde dans quel ordre Kustomize applique les components et les correctifs de l'overlay, et ce que devient l'ancien correctif `replace /spec/replicas` de la prod : rends l'overlay (`kustomize build`) et lis `spec.replicas` du Rollout — ne te fie pas à l'absence d'erreur. Pour la transition, demande-toi qui possède `spec.replicas` dans les `managedFields` une fois que l'HPA l'a modifié une fois.
</details>

<details><summary>Indice 3</summary>

Si la condition `ScalingActive` est fausse avec `FailedGetResourceMetric`, vérifie que metrics-server répond (`kubectl top pods -n mediagenda-recette`) et que **chaque** conteneur (y compris les conteneurs annexes éventuels) a une `request` CPU.
</details>

**Pour aller plus loin** (facultatif) : ajoute une seconde métrique (débit de requêtes par pod, `mediagenda_http_requests_total`) : il faudrait un adaptateur de métriques personnalisées. Lequel, et pourquoi KEDA (E03, palier 3) rend ce besoin moins pressant ?

---

### M28-E03 — KEDA : MédiNotif suit sa file  `LAB` `★★`

> **Ticket PLAT-2903** — *De : Karim Benali* — *Copie : Sophie Laurent, Julien Petit*
> Le CPU de MédiNotif ne dit rien : un worker qui attend un message ne consomme rien, et quand la file déborde il ne consomme pas plus. Ce qui compte, c'est la profondeur de `notifications`. On installe KEDA, on branche MédiNotif de recette sur sa file, au moins un pod pour l'instant (le zéro, on en reparle au palier 3). Sophie veut que le compte de KEDA sur RabbitMQ ne puisse ni lire ni publier un message, et que son mot de passe ne soit jamais dans Git.

**Objectifs pédagogiques**
- Installer KEDA par Argo CD (chart recopié, images par Harbor, certificats, supervision, politiques réseau).
- Comprendre l'adaptateur `external.metrics.k8s.io` et le HPA que KEDA fabrique.
- Choisir le protocole du scaler RabbitMQ d'après les droits qu'il exige, créer le compte de KEDA par la topologie déclarative.
- Brancher un `ScaledObject` et sa `TriggerAuthentication` (secret par ESO) et observer une montée en charge.

**Prérequis** : M28-E02 ; M27-E03 et E04 (grappe `rabbitmq`, topologie `medinotif-recette`, `medinotif/deploiement`) ; M25 (SecretStore `openbao`, ExternalSecret) ; M20-E13 (`charts-miroir`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `kedacore/keda` **2.21.0**, dépôt `https://kedacore.github.io/charts` ; empreinte : champ `digest` de l'index amont |
| Application | **`keda`** (projet `plateforme`), espace **`keda`** (`plateforme/k8s/espaces/keda/`, PSA `restricted`), valeurs `plateforme/gitops/valeurs/keda/values.yaml` |
| Images | `registry.par1.medisphere.internal/ghcr/kedacore/keda`, `…/keda-metrics-apiserver`, `…/keda-admission-webhooks` (2.21.0, par empreinte) |
| RabbitMQ | Service `rabbitmq.messagerie.svc.cluster.local` ; AMQPS 5671, API de gestion en HTTPS **15671** (TLS par `openbao-services`, chaîne jusqu'à la racine MédiSphère) ; vhost `medinotif-recette`, file quorum `notifications` |
| Compte de KEDA | utilisateur RabbitMQ **`keda-recette`** déclaré dans `plateforme/donnees/topologie/medinotif-recette/` ; mot de passe dans OpenBao **`kv/medinotif/recette/keda`** (clés `utilisateur`, `mot_de_passe`) |
| Objets de MédiNotif | dans `medinotif/deploiement`, overlay `recette` : ExternalSecret **`medinotif-rabbitmq`** (SecretStore `openbao` de l'espace), `TriggerAuthentication` **`medinotif-rabbitmq`**, `ScaledObject` **`medinotif`** (cible Deployment `medinotif`, 1 → 5 pods) |
| Checks | ClusterRole agrégée **`wb-checks-services-m28`** (étiquette `workbook.medisphere.internal/checks: "true"`) dans `plateforme/k8s/rbac/` : lecture des objets de KEDA, du VPA et de Capsule |

**Travail demandé**

1. **Avant d'installer.** Vérifie qu'aucune `APIService` `v1beta1.external.metrics.k8s.io` n'existe. Lis le `values.yaml` du chart 2.21.0 : images, certificats (`certificates.*`), métriques Prometheus (`prometheus.*`), droits sur les Secrets (`permissions.operator.restrict.*`, et ce que vaut la règle par défaut sur les Secrets dans la ClusterRole rendue), types de cibles (`rbac.scaledRefKinds`), politiques réseau, autorités de confiance supplémentaires (`certificates.operator.caDirs`).
2. **Le chart et l'espace.** Recopie le chart par `charts-miroir`. Crée l'espace `keda` (PSA `restricted`, étiquettes de la plateforme), la ConfigMap de la racine MédiSphère et les CiliumNetworkPolicy de l'espace : DNS, API du cluster, entrées depuis l'apiserver (adaptateur, webhooks) et depuis Prometheus, sortie vers l'API de gestion de RabbitMQ seulement. Ajoute la règle d'entrée correspondante côté `messagerie` (dépôt `plateforme/donnees`).
3. **Les valeurs.** Images de Harbor par empreinte ; certificats internes par cert-manager ; ServiceMonitors de l'opérateur et de l'adaptateur avec l'étiquette de sélection de la supervision ; racine MédiSphère reconnue par l'opérateur ; types de cibles limités à ce dont MédiSphère a besoin ; ressources. Rends le chart en local et relis la ClusterRole de l'opérateur. L'Application `keda`. Une fois synchronisée : `APIService` disponible, trois Deployments prêts, CRD installées.
4. **La ClusterRole des checks.** Écris `wb-checks-services-m28` (lecture de `keda.sh`, `autoscaling.k8s.io`, `capsule.clastix.io` ; aucune règle sur les Secrets) et applique-la comme les autres objets de `rbac/`.
5. **Le protocole et le compte.** Lis la documentation du scaler `rabbitmq` de KEDA 2.21 et la page *Access Control* de RabbitMQ (déclarations passives, depuis 4.3.1). Pour chaque protocole (`amqp`, `http`), écris dans `docs/plateforme-dev/autoscaling.md` les droits que le compte doit avoir, ce qu'ils lui permettraient de faire d'autre, et ce que chaque protocole compte (messages prêts, non acquittés). Choisis, puis déclare le compte `keda-recette` dans la topologie (utilisateur, étiquette, permissions sur le vhost) avec un mot de passe venant d'OpenBao.
6. **MédiNotif.** Dans l'overlay `recette` de `medinotif/deploiement` : l'ExternalSecret, la `TriggerAuthentication` (aucune valeur en clair), le `ScaledObject` (déclencheur `rabbitmq`, mode longueur de file, seuil par pod que tu justifies d'après `MEDINOTIF_DELAI_ENVOI_MS`, `behavior` à la descente) ; et, comme en E02, ce qu'il faut pour qu'Argo CD ne se batte pas avec le HPA que KEDA va créer (ApplicationSet `medinotif`). MR.
7. **Observe.** L'HPA `keda-hpa-medinotif` créé par KEDA : quelle métrique externe porte-t-il ? Interroge toi-même l'API `external.metrics.k8s.io` pour cette métrique. Ralentis temporairement le worker de recette (`MEDINOTIF_DELAI_ENVOI_MS` à 500, par MR), crée une rafale de rendez-vous de recette (`charge.sh` en mode `rendez-vous`) et suis la file (API de gestion), le ScaledObject, l'HPA et les pods. Remets le délai d'origine à la fin.

**Critères de réussite**
- [ ] Application `keda` `Synced` et `Healthy` ; opérateur, adaptateur et webhooks prêts, images de Harbor en 2.21.0 ; `APIService` `v1beta1.external.metrics.k8s.io` servie par `keda` et disponible.
- [ ] La ClusterRole `wb-checks-services-m28` existe, étiquetée pour l'agrégation, sans aucun droit sur les Secrets.
- [ ] Utilisateur RabbitMQ `keda-recette` : aucune permission qui permette de configurer, publier ou consommer sur `medinotif-recette`.
- [ ] `ScaledObject` `medinotif` (recette) prêt, déclencheur `rabbitmq` sur la file `notifications` du vhost `medinotif-recette`, `authenticationRef` `medinotif-rabbitmq` ; la `TriggerAuthentication` ne référence que des Secrets ; l'ExternalSecret `medinotif-rabbitmq` est synchronisé.
- [ ] L'HPA `keda-hpa-medinotif` a demandé au moins 2 pods dans les dernières 24 h ; aucune erreur de scaler sur l'heure écoulée.
- [ ] Application de MédiNotif en recette `Synced`.

**Vérification** : `lab/bin/check 28 03`

<details><summary>Indice 1</summary>

`helm template` du chart avec tes valeurs, puis `yq 'select(.kind == "ClusterRole")'` : regarde la règle sur `secrets` et demande-toi ce que `list` sur tous les espaces permet de lire. Pour les autorités de confiance, cherche `--ca-dir` dans le gabarit du Deployment de l'opérateur.
</details>

<details><summary>Indice 2</summary>

En AMQP, le scaler fait une **déclaration passive** de la file : depuis RabbitMQ 4.3.1, elle exige au moins une permission sur la file, et toute permission sur `notifications` donne un pouvoir sur les messages. L'API HTTP, elle, demande une étiquette d'utilisateur et un accès au vhost. Une entrée de permissions dont les trois motifs ne correspondent à rien ouvre le vhost sans ouvrir aucune ressource.
</details>

<details><summary>Indice 3</summary>

La métrique externe se lit par `kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/medinotif-recette/<nom-de-la-métrique>?labelSelector=scaledobject.keda.sh%2Fname%3Dmedinotif"` ; le nom est dans `spec.metrics` de l'HPA. Si le ScaledObject reste `Ready False`, lis les événements du ScaledObject et les journaux de `keda-operator` : TLS (racine), DNS, politique réseau, identifiants.
</details>

**Pour aller plus loin** (facultatif) : compare avec le mode `MessageRate` du scaler : dans quel cas suivre un débit vaut mieux que suivre une profondeur ?

---

### M28-E04 — VPA : des requêtes justes  `LAB` `★★`

> **Ticket PLAT-2904** — *De : Claire Morel* — *Copie : Karim Benali*
> Nos `requests` ont été écrites au doigt mouillé au module 14. Résultat : des travailleurs « pleins » à 80 % de réservations et à 25 % d'usage réel. Je veux des recommandations mesurées sur MédiAgenda, MédiNotif et MédiDoc, **sans** que rien ne bouge tout seul en production. Et Karim veut voir le redimensionnement en place, GA depuis la 1.35, sur un essai jetable.

**Objectifs pédagogiques**
- Installer le VPA par Argo CD et comprendre ses trois composants.
- Lire et interpréter des recommandations (`target`, bornes) et les confronter aux `requests` et aux mesures.
- Pratiquer `InPlaceOrRecreate` et le redimensionnement en place (`resizePolicy`, sous-ressource `resize`) sur un essai.
- Savoir pourquoi un VPA actif et un HPA ne visent jamais la même ressource.

**Prérequis** : M28-E02, M28-E03 ; M17 (metrics-server).
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `fairwinds-stable/vpa` **5.1.0** (VPA 1.7.1), dépôt `https://charts.fairwinds.com/stable` ; il embarque un sous-chart metrics-server **désactivé** par défaut (il doit le rester) |
| Application | **`vpa`** (projet `plateforme`), espace **`vpa`** (PSA `restricted`), valeurs `plateforme/gitops/valeurs/vpa/values.yaml` |
| Images | `registry.par1.medisphere.internal/k8s/autoscaling/vpa-recommender`, `…/vpa-updater`, `…/vpa-admission-controller` (1.7.1) ; image du *job* de certificats du chart par le même cache |
| Objets à créer | `VerticalPodAutoscaler` en **`updateMode: "Off"`**, nommés comme leur cible : `mediagenda` (Rollout, recette et prod), `medinotif` (Deployment, recette et prod), `medidoc` (Deployment, `medidoc-recette`) — dans les dépôts `…/deploiement` |
| Essai | Deployment et VPA **`essai-vpa`** dans `wb-essais` ([`ressources/E04-essai/essai-vpa.yaml`](../ressources/E04-essai/essai-vpa.yaml)), mode `InPlaceOrRecreate` ; supprimés en fin d'exercice |

**Travail demandé**

1. **Le chart.** Recopie-le, lis ses valeurs (composants, certificats du webhook, `extraArgs`, sous-chart metrics-server) et la CRD : quels modes de mise à jour la CRD accepte-t-elle ? Quel est le défaut ?
2. **L'installation.** Espace, valeurs (images de Harbor, ressources, contexte de sécurité compatible `restricted`), Application `vpa`. Après synchronisation : trois Deployments prêts, le webhook de mutation enregistré ; avec quelle `failurePolicy`, et pourquoi c'est important ?
3. **Les recommandations.** Ajoute les cinq VPA en `Off` (MR dans les trois dépôts). Pour le Rollout de MédiAgenda, pourquoi cibler le Rollout et pas le Deployment `mediagenda` (que vaut son `replicas` depuis M20-E16) ? Laisse tourner au moins une heure avec du trafic (recette : `charge.sh`).
4. **La lecture.** Pour chaque VPA : `target`, `lowerBound`, `upperBound`, `uncappedTarget` par conteneur ; compare aux `requests` déclarées et à la consommation mesurée (PromQL). Rédige `docs/plateforme-dev/recommandations-ressources.md` : un tableau par application et environnement, ce que tu proposes de changer, ce que tu ne changes pas et pourquoi (durée d'observation, pics, HPA sur le CPU de MédiAgenda).
5. **Le redimensionnement en place.** Applique l'essai dans `wb-essais`. Observe : la recommandation, la `resizePolicy` des conteneurs, le pod après l'action de l'updater (même UID ? `restartCount` ? `status.containerStatuses[].resources` ?). Puis redimensionne toi-même le CPU d'un pod par la sous-ressource `resize` et constate. Qu'est-ce qui empêcherait le redimensionnement en place (QoS, mémoire en `RestartContainer`, nœud plein) ? Consigne-le dans `recommandations-ressources.md`, puis supprime l'essai.
6. **Les garde-fous.** Écris pourquoi un VPA actif et l'HPA de MédiAgenda ne doivent jamais viser le CPU de la même charge, et ce que ferait un VPA actif sur MédiNotif piloté par KEDA.

**Critères de réussite**
- [ ] Application `vpa` `Synced` et `Healthy` ; recommender, updater et admission-controller prêts en 1.7.1, images de Harbor.
- [ ] Cinq VPA en `Off` avec des recommandations (`status.recommendation`) : `mediagenda` (recette, prod) sur le Rollout, `medinotif` (recette, prod), `medidoc` (recette).
- [ ] Aucun VPA en mode actif hors de `wb-essais`.
- [ ] `recommandations-ressources.md` (tableaux, décision, essai en place, garde-fous) est sur `main`.

**Vérification** : `lab/bin/check 28 04`

<details><summary>Indice 1</summary>

Le *recommender* a besoin de temps : les premières recommandations arrivent après quelques minutes, mais elles ne sont fiables qu'après des heures de trafic varié. `kubectl describe vpa` montre aussi les conditions (`RecommendationProvided`, `LowConfidence`).
</details>

<details><summary>Indice 2</summary>

L'updater ne touche pas une charge qui a moins de pods que son seuil (`--min-replicas`, 2 par défaut) : l'essai n'a qu'un pod. Cherche le champ de la CRD qui fixe ce seuil par VPA. Pour redimensionner toi-même : `kubectl patch pod … --subresource resize --patch '…'`.
</details>

**Pour aller plus loin** (facultatif) : lis le champ `startupBoost` de la CRD 1.7 : à quel problème des applications Java ou Python répond-il ?

---

### M28-E05 — Capsule : un locataire par équipe  `LAB` `★★`

> **Ticket PLAT-2905** — *De : Claire Morel* — *Copie : Sophie Laurent, Julien Petit*
> Chaque équipe aura son locataire : MédiAgenda (Julien), MédiDoc, et MédiNotif — que l'équipe de Julien possède. Dans son locataire, une équipe crée elle-même ses espaces de travail (préfixés à son nom, en nombre limité, dans un budget de ressources), sans ticket. Ses environnements actuels sont rattachés à son locataire **sans rien casser** : Argo CD continue de les livrer, les quotas de la plateforme restent, Pod Security et Kyverno continuent de s'appliquer. Sophie : « Je veux voir Julien essayer de créer un espace qui ne lui appartient pas, et échouer. »

**Objectifs pédagogiques**
- Installer Capsule par Argo CD et le configurer (utilisateurs Capsule, administrateurs, préfixe).
- Écrire des `Tenant` `capsule.clastix.io/v1beta2` : propriétaires (groupes OIDC), quota d'espaces, budget de ressources, classes de stockage, liaisons RBAC par sous-ensemble d'espaces.
- Rattacher des espaces existants à un locataire, et mesurer ce que Capsule y pose.
- Comprendre la cohabitation de Capsule avec Pod Security, Kyverno, les quotas de la plateforme et Argo CD.

**Prérequis** : M28-E03 (ClusterRole des checks) ; M24-E16 et E17 (authentification structurée, préfixe `oidc:`, liaisons `oidc-*`) ; M26 (PSA, Kyverno) ; M20-E07 (AppProjects, ressources orphelines).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `projectcapsule/capsule` **0.15.1**, dépôt `https://projectcapsule.github.io/charts` (exige Kubernetes ≥ 1.36.0) |
| Application | **`capsule`** (projet `plateforme`), espace **`capsule-system`** (PSA `restricted`), valeurs `plateforme/gitops/valeurs/capsule/values.yaml` |
| Locataires | `plateforme/k8s/locataires/` (`mediagenda.yaml`, `medidoc.yaml`, `medinotif.yaml`, `kustomization.yaml`), Application **`locataires`** (projet `plateforme`) |
| Propriétaires | `mediagenda` et `medinotif` : groupe `oidc:mediagenda` ; `medidoc` : groupe `oidc:medidoc` |
| Espaces à rattacher | `mediagenda-dev`, `-recette`, `-prod`, `-secours` ; `medidoc-dev`, `-recette` ; `medinotif-recette`, `-prod` (déclarés dans `plateforme/k8s/espaces/`) |
| Libre-service | espaces `<locataire>-…` créés par l'équipe ; classe de stockage `ceph-rbd` seulement ; Pod Security `restricted` posé d'office ; un budget de ressources propre au libre-service |
| Droits actuels des équipes | `view` sur leurs environnements, `edit` sur `mediagenda-dev` (liaisons `oidc-*` du M24-E17) |

> ⚠️ **Attention** : un espace rattaché à un locataire porte une **référence de propriétaire** vers le `Tenant`. Si ce `Tenant` est supprimé (fichier retiré de Git avec élagage, Application supprimée avec son finaliseur, `kubectl delete`), le ramasse-miettes de Kubernetes **supprime les espaces rattachés**, production comprise. Avant de rattacher le moindre espace : protège chaque `Tenant` contre la suppression (champ du `Tenant` **et** options de synchronisation d'Argo CD), vérifie la protection par un essai à blanc (`kubectl delete --dry-run=server`), et assure-toi qu'une sauvegarde Velero récente de `mediagenda-prod` existe (M16). Retour arrière : retirer la référence de propriétaire et l'étiquette du locataire de chaque espace (documentation de Capsule, *Remove Namespace from a Tenant*), **avant** toute suppression de `Tenant`.

**Travail demandé**

1. **Lecture.** Dans les valeurs du chart 0.15.1 et la CRD `CapsuleConfiguration` : comment déclare-t-on les utilisateurs Capsule et les administrateurs en 0.15 (quels champs sont dépréciés) ? Dans la CRD `Tenant` v1beta2 : quels champs sont marqués dépréciés, et par quoi les remplace-t-on ? Que fait `forceTenantPrefix` ? Que devient un espace dont l'étiquette `capsule.clastix.io/tenant` est posée ?
2. **L'installation.** Espace, valeurs (images de Harbor, y compris celle des *jobs* du chart ; utilisateurs Capsule = les deux groupes d'équipe ; administrateurs ; préfixe imposé ; supervision), Application `capsule`. Relis ce que le chart rend : webhooks (quelles ressources, quelle `failurePolicy`), ClusterRoles, `CapsuleConfiguration`.
3. **Les locataires.** Écris les trois `Tenant` : propriétaires (groupes) **sans** donner aux équipes plus que `view` sur leurs environnements actuels ; dans les espaces de libre-service seulement, les droits d'administration et de suppression ; nombre d'espaces ; budget de ressources du libre-service ; classe de stockage ; Pod Security `restricted` posé sur chaque espace créé ; protection contre la suppression. Application `locataires`, avec les options qui empêchent Argo CD d'élaguer ou de supprimer un `Tenant`.
4. **Le rattachement.** Ajoute l'étiquette du locataire aux espaces existants (`plateforme/k8s/espaces/`, `task espaces`), puis pose la référence de propriétaire comme le documente Capsule (script `plateforme/k8s/outils/rattacher-locataires.sh`, idempotent, qui s'arrête si un `Tenant` n'est pas protégé). Contrôle le statut des trois `Tenant` (espaces, taille).
5. **Ce que Capsule a posé.** Dans `mediagenda-prod` : RoleBindings, quotas, étiquettes, annotations ajoutés par Capsule. Les quotas de la plateforme sont-ils intacts ? L'Application `mediagenda-prod` est-elle toujours `Synced` ? Des ressources orphelines apparaissent-elles dans l'AppProject `mediagenda` ? Corrige ce qui doit l'être (liste d'ignorés des AppProjects).
6. **L'essai de Sophie.** En te faisant passer pour Julien (`--as=oidc:julien.petit --as-group=oidc:mediagenda`, avec ton identité d'administrateur, comme au M24-E17) ou par sa connexion OIDC : créer `mediagenda-essai-julien` (doit réussir, avec Pod Security `restricted` posé), créer `essai-julien` et `medidoc-essai` (doivent échouer), créer un PVC `cephfs` dans son espace (doit échouer), supprimer un Deployment de `mediagenda-prod` (doit échouer), dépasser le nombre d'espaces. Note chaque réponse. Supprime `mediagenda-essai-julien` à la fin.
7. **La cohabitation.** Dans `docs/plateforme-dev/locataires.md` : modèle (qui possède quoi, quels droits où), ce que Capsule ajoute et ce qu'il ne fait pas (réseau, signatures d'images, nœuds), comment PSA, Kyverno (M26), les quotas de `plateforme/k8s/espaces/` et le budget du locataire s'additionnent, ce qu'Argo CD voit, le retour arrière.

**Critères de réussite**
- [ ] Application `capsule` `Synced` et `Healthy` ; contrôleur prêt en 0.15.x ; webhooks de Capsule enregistrés.
- [ ] `CapsuleConfiguration` : utilisateurs Capsule = groupes `oidc:mediagenda` et `oidc:medidoc` ; préfixe imposé.
- [ ] Trois `Tenant` prêts, propriétaires = groupes OIDC (jamais une personne), protégés contre la suppression, classe `ceph-rbd` seule autorisée, un nombre d'espaces et un budget de ressources définis.
- [ ] Les huit espaces existants sont rattachés à leur locataire ; leurs quotas de la plateforme sont toujours là ; les Applications des équipes restent `Synced`.
- [ ] Le groupe `oidc:mediagenda` n'a toujours pas le droit de créer un Deployment dans `mediagenda-prod`.
- [ ] `locataires.md` est sur `main`.

**Vérification** : `lab/bin/check 28 05`

<details><summary>Indice 1</summary>

Les propriétaires reçoivent par défaut les ClusterRoles `admin` et `capsule-namespace-deleter` dans **tous** les espaces du locataire : lis le champ `clusterRoles` d'un propriétaire, puis la section *Permissions* des règles (`rules[].permissions.bindings`, avec un `namespaceSelector`). Une étiquette que l'équipe ne peut pas poser elle-même (`namespaceOptions.forbiddenLabels`) distingue sûrement un environnement d'un espace de libre-service.
</details>

<details><summary>Indice 2</summary>

`spec.resourceQuotas` est déprécié : les quotas de locataire passent par `rules[].quota`, qui génèrent des `GlobalResourceQuota` (un budget partagé entre les espaces sélectionnés). Kubernetes applique **tous** les ResourceQuotas d'un espace : un quota de plus ne remplace jamais celui de la plateforme. Pour Argo CD, pense à l'annotation `argocd.argoproj.io/sync-options` sur les objets.
</details>

<details><summary>Indice 3</summary>

Si la création d'espace par Julien échoue avec « Please use capsule.clastix.io/tenant label » ou « doesn't match any available Tenant », vérifie que le groupe de la requête (`--as-group`) est bien un utilisateur Capsule et que le préfixe est le nom exact du locataire. Si elle échoue sur un `forbidden` RBAC, regarde la ClusterRoleBinding que Capsule pose pour ses utilisateurs (création d'espaces).
</details>

**Pour aller plus loin** (facultatif) : lis la page *Replications* de Capsule (`TenantResource`, `GlobalTenantResource`) : comment poserais-tu une politique réseau de refus par défaut dans chaque espace de libre-service ? (M28-E15 y revient.)
