# Module 28 — Palier 3 : Production

Les paliers 1 et 2 ont posé la plateforme développeurs : MédiAgenda suit sa charge (HPA), MédiNotif suit sa file (KEDA), le VPA recommande, chaque équipe a son locataire Capsule, le portail Backstage connaît les services, leurs propriétaires et sait en créer un nouveau par MR. Il reste ce qui fait d'une plateforme « qui marche » une plateforme qu'on peut confier aux équipes et à l'astreinte : un autoscaling qui sait **descendre à zéro** sans perdre une notification, qui **anticipe** les campagnes de rappel et qui **résiste** à la panne de sa source de métriques ; un partage du cluster **équitable** (quotas, priorités) ; des locataires dont on a **éprouvé** les cloisons au lieu de les supposer ; un portail sauvegardé, supervisé et à jour ; et une décision d'architecture écrite. Claire Morel veut pouvoir dire au comité « une équipe ne peut pas gêner les autres » et le prouver.

Prérequis : paliers 1 et 2 terminés (`lab/bin/check 28 02` à `28 10` verts, `vc-essai` retiré). La production reste intouchable par les essais : toute expérience se fait en recette, dans `wb-essais` ou dans un espace de libre-service.

> ⚠️ **Rappel** : ce palier change des réglages qui **retirent des pods** (mise à zéro, priorités, préemption) et des règles d'admission (Capsule, Kyverno) qui peuvent **refuser** des créations légitimes. Avant chaque MR : (1) relis le diff que montrera Argo CD (`argocd app diff <application>`) ; (2) applique d'abord en recette ou sur un locataire d'essai, observe, puis seulement la production ; (3) garde sous la main le retour arrière : `git revert` de la MR et resynchronisation. Une règle d'admission trop large peut bloquer Argo CD lui-même : vérifie après chaque fusion qu'une synchronisation de `mediagenda-recette` passe encore.

**Chemin imposé** : rien n'est appliqué à la main sur les espaces applicatifs. Les valeurs des charts sont dans `plateforme/gitops/valeurs/<composant>/`, les Applications dans `plateforme/gitops/plateforme/`, les espaces, quotas et priorités dans `plateforme/k8s/` (`espaces/`, `locataires/`, `ordonnancement/`), les politiques Kyverno dans `plateforme/politiques`, les règles et tableaux de bord dans `plateforme/observabilite`, les manifestes applicatifs dans `mediagenda/deploiement` et `medinotif/deploiement`. Secrets dans OpenBao, livrés par ESO. La documentation va dans `docs/plateforme-dev/` de `plateforme/medisphere` (`adr/`, `runbooks/`).

**État d'entrée du palier 3** (ce que les paliers 1 et 2 ont livré ; les noms en *italique* viennent de tes exercices : garde les tiens s'ils diffèrent, et note-les dans `docs/plateforme-dev/README.md`)

| Élément | État attendu |
|---|---|
| HPA | `HorizontalPodAutoscaler` `mediagenda` (`autoscaling/v2`) sur le **Rollout** `mediagenda` de `mediagenda-recette` et `mediagenda-prod`, déclaré dans `mediagenda/deploiement` ; `spec.replicas` du Rollout **retiré** de ce que gère Git (M28-E02) |
| KEDA 2.21 | Application `keda`, espace `keda`, valeurs `plateforme/gitops/valeurs/keda/values.yaml` (métriques de l'opérateur, de l'adaptateur et des webhooks déjà collectées par Prometheus) ; en **recette seulement** : `ScaledObject` **`medinotif`** (`overlays/recette/keda/` de `medinotif/deploiement`, déclencheur `rabbitmq` en protocole HTTP sur la file `notifications` du vhost `medinotif-recette`, minimum 1), `TriggerAuthentication` **`medinotif-rabbitmq`** et ExternalSecret `medinotif-rabbitmq` (compte RabbitMQ **`keda-recette`**, étiquette `management`, permissions `^$` ; secret `kv/medinotif/recette/keda`, clés `utilisateur`, `mot_de_passe` ; adresse de l'API de gestion `https://rabbitmq.messagerie.svc.cluster.local:15671/` posée par le modèle de l'ExternalSecret) ; flux `keda` → `messagerie` 15671 ouvert. **MédiNotif de prod a encore un effectif fixe** |
| VPA 1.7.1 | Application `vpa`, espace `vpa` ; un `VerticalPodAutoscaler` en `updateMode: "Off"` par charge, nommé comme sa cible (`mediagenda`, `medinotif`, …) ; aucun VPA actif hors de `wb-essais` |
| Capsule 0.15 | Application `capsule`, espace `capsule-system`, valeurs `plateforme/gitops/valeurs/capsule/values.yaml` (`CapsuleConfiguration` `default` : groupes gérés `oidc:mediagenda`, `oidc:medidoc`, préfixe imposé) ; locataires **`mediagenda`** (propriétaire `oidc:mediagenda`), **`medidoc`** (`oidc:medidoc`), **`medinotif`** (`oidc:mediagenda`) dans `plateforme/k8s/locataires/` (Application `locataires`) ; espaces existants rattachés (étiquettes `capsule.clastix.io/tenant` et `medisphere.internal/environnement`) où les propriétaires ont **`view`** ; espaces de **libre-service** (sans étiquette d'environnement) où ils sont **`admin`**, avec un budget partagé (`GlobalResourceQuota` `<locataire>-libre-service`) et les étiquettes PSA `restricted` posées par `additionalMetadataList` ; classe de stockage autorisée `ceph-rbd` |
| Backstage 1.56 | Projet `plateforme/portail`, image `registry.par1.medisphere.internal/plateforme/portail:vX.Y.Z` signée, Application `portail`, espace **`portail`** (un réplica), base CNPG **`portail-db`** (une instance, *sans sauvegarde*), `https://portail.apps.par1.medisphere.internal`, OIDC (client `backstage`), catalogue GitLab + LDAP, plugin Kubernetes, TechDocs (compartiment `portail-techdocs`), modèle `nouveau-service` dans `plateforme/portail-modeles` |
| vCluster | `vc-essai` **retiré** (espace `medidoc-vc-essai` supprimé) |
| Priorités | seule `medisphere-ci` (1000, `preemptionPolicy: Never`, M19) existe |

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Accès aux métriques depuis le cluster | Thanos Query `http://thanos-query.supervision.svc.cluster.local:9090` (vue dédupliquée des deux réplicas, M21-E24) ; Prometheus `http://kps-prometheus.supervision.svc.cluster.local:9090` (un réplica au hasard) |
| Métriques utiles | MédiAgenda : `mediagenda_notifications_total` (M27-E08) ; MédiNotif : métriques du port 9100 ; KEDA : `keda_*` (opérateur, port 8080) ; kube-state-metrics : `kube_*` |
| Comptes | identité OIDC personnelle (contexte `k8s-par1`) ; `admin.conf` = bris de glace ; essais d'isolation par un compte d'essai nominatif (E15) |
| Documentation | `docs/plateforme-dev/` : `autoscaling.md` (E13), `capacite.md` (E14), `essais-isolation.md` (E15), `portail-exploitation.md` (E16), `adr/ADR-0280-*.md` (E17), `runbooks/RB-284-*.md` (E16) |
| Variables de `lab/lab.env` | celles de l'introduction (toutes facultatives) ; ce palier utilise `WB_M28_IMAGE_BB` (image busybox du cache Harbor, essais de préemption de E14) |

---

### M28-E13 — KEDA en production : zéro, cron, Prometheus, repli  `LAB` `★★★`

> **Ticket PLAT-2913** — *De : Julien Petit* — *Copie : Karim Benali, Nadia Roussel*
> Trois choses sur MédiNotif. (1) En recette, un pod tourne 24 h/24 pour une poignée de messages par jour : je veux qu'il dorme quand la file est vide et se réveille tout seul. (2) Lundi, la campagne de rappels de vaccination part à 8 h : la file a grimpé à 40 000 messages avant que KEDA ne réagisse, les premiers SMS sont partis à 8 h 40. On sait **à l'avance** quand partent les campagnes, et MédiAgenda sait **avant la file** qu'il publie beaucoup. (3) Karim demande ce qui se passe si RabbitMQ ou Prometheus ne répondent plus à KEDA : je veux une réponse écrite, pas « ça dépend ». En prod, jamais moins d'un pod.

**Objectifs pédagogiques**
- Comprendre l'**activation** (0 ↔ 1, faite par KEDA) et la **mise à l'échelle** (1 ↔ N, faite par l'HPA que KEDA crée), et les réglages de chacune : `minReplicaCount`, `idleReplicaCount`, `cooldownPeriod`, `initialCooldownPeriod`, `activationValue`/`activationThreshold`, `pollingInterval`.
- Combiner plusieurs déclencheurs (`rabbitmq`, `cron`, `prometheus`) et savoir lequel décide.
- Rendre l'autoscaling robuste : `fallback`, comportement de l'HPA (`advanced.horizontalPodAutoscalerConfig.behavior`), pause par annotation pour une maintenance.
- Superviser KEDA lui-même : métriques, alertes, ce qu'elles disent quand le scaler est aveugle.

**Prérequis** : M28-E03 ; M27-E08 (MédiAgenda publie) ; M21 (Prometheus, Thanos Query) ; `lab/bin/check 28 03` vert.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Référence des champs : *ScaledObject specification*, *Scalers → RabbitMQ Queue / Cron / Prometheus*, *Concepts → Scaling Deployments* (pause), *Integrations → Prometheus* de la documentation de KEDA **2.21** (`keda.sh/docs/2.21/`). Ne prends pas un exemple d'une autre version sans le confronter à cette page.
- KEDA crée et possède un HPA nommé `keda-hpa-<scaledobject>` ; ne l'édite jamais : tout passe par le `ScaledObject`.
- Les campagnes de rappel partent du lundi au vendredi à **8 h 00, heure de Paris**, et durent environ une heure ; en recette, Julien rejoue une mini-campagne à **14 h 00** les jours ouvrés.
- `ressources/E13-campagne/campagne.sh` publie N demandes de notification **factices** dans l'échange `notifications` du vhost `medinotif-recette`, par l'API HTTP de gestion de RabbitMQ ; il refuse tout autre vhost. Il utilise un compte d'essai **`campagne-recette`** que tu déclares d'abord dans la topologie de recette (`plateforme/donnees/topologie/medinotif-recette/`) : étiquette `management`, écriture sur le seul échange `notifications` de ce vhost, aucun autre droit, mot de passe dans OpenBao `kv/medinotif/recette/campagne` (clé `mot_de_passe`), Secret livré par ESO dans `messagerie`. Le script lit ce mot de passe avec ta session `bao`.

**Travail demandé**
1. **Mesure d'abord.** En recette, publie 2 000 messages (`campagne.sh 2000`) et mesure : délai avant le premier pod supplémentaire, nombre maximal de pods, temps pour vider la file, débit d'un pod (messages/s). Relève dans l'HPA `keda-hpa-medinotif` les métriques qu'il voit (`kubectl describe hpa`) et dans KEDA la valeur brute (`kubectl get --raw` sur `external.metrics.k8s.io`, voir l'indice 2). Ces mesures fixent tes seuils.
2. **Mise à zéro en recette.** Dans l'overlay `recette` de `medinotif/deploiement` : MédiNotif descend à **zéro** quand la file est vide et repart au premier message ; fixe explicitement `cooldownPeriod`, `pollingInterval` et le seuil d'activation, et décide si `idleReplicaCount` t'est utile (écris pourquoi dans la MR). Mesure le **démarrage à froid** : délai entre la publication d'un message sur une file vide et son traitement.
3. **Production.** Étends KEDA à `medinotif-prod` sur le modèle de la recette (`overlays/prod/keda/`) : compte `keda-prod` (topologie de `medinotif-prod`, secret `kv/medinotif/prod/keda`, lecture ouverte à ESO comme en E03), ExternalSecret, `TriggerAuthentication`, `ScaledObject`, `spec.replicas` retiré du Deployment (l'ApplicationSet ignore déjà ce champ pour tous les environnements depuis E03) ; synchronisation à la main, après relecture du diff.
4. **Campagnes.** Ajoute un déclencheur `cron` qui monte MédiNotif **avant** la campagne (prod : jours ouvrés, 7 h 50 → 9 h 30, heure de Paris ; recette : 13 h 50 → 14 h 30) au nombre de réplicas que ta mesure justifie.
5. **Anticipation.** Ajoute un déclencheur `prometheus` sur le **débit de publication** de MédiAgenda (`mediagenda_notifications_total`) de l'environnement. Choisis la source (Thanos Query ou Prometheus du cluster), **justifie** ce choix dans la MR et ouvre le flux réseau nécessaire (CiliumNetworkPolicy des deux côtés, matrice des flux).
6. **Robustesse.** Ajoute un `fallback` (combien de réplicas si un déclencheur échoue trois fois de suite, et avec quel `behavior`) et un comportement d'HPA : montée rapide, descente lente et progressive. En prod, garantis au moins un pod (deux si ta mesure et le PDB de M28-E14 le demandent).
7. **Maintenance.** Écris la procédure de pause de l'autoscaling de MédiNotif pendant une maintenance de RabbitMQ (quelle annotation, avec quel nombre de réplicas, par quel chemin — Git ou à la main —, comment on la retire) et **éprouve-la en recette** par une MR, puis retire la pause.
8. **Supervision de KEDA.** Vérifie que Prometheus collecte bien l'opérateur, l'adaptateur et les webhooks (M28-E03), puis ajoute dans `plateforme/observabilite/regles/` des alertes : un scaler en erreur, un `ScaledObject` en pause depuis plus de 2 h, KEDA absent. Simule ensuite la panne d'une source **en recette seulement** : par une MR sur l'overlay `recette`, fais pointer le déclencheur `prometheus` vers une adresse qui ne répond pas pendant 10 minutes, observe (métriques, conditions du `ScaledObject`, effet du `fallback`, alerte), puis annule la MR. Explique dans la MR pourquoi couper le flux `keda` → `messagerie` n'aurait pas été un essai « en recette seulement ».
9. **Complète** `docs/plateforme-dev/autoscaling.md` (créé en E02-E03) : tableau par application et environnement (déclencheurs, seuils, min/max, cooldown, repli), mesures avant/après, démarrage à froid, ce qui se passe quand chaque source tombe (RabbitMQ, Prometheus, KEDA lui-même), procédure de pause.

**Critères de réussite**
- [ ] En recette, le `ScaledObject` `medinotif` autorise zéro réplica et MédiNotif est effectivement descendu à zéro au moins une fois dans les 24 dernières heures ; en prod, un `ScaledObject` existe avec un minimum d'au moins un réplica.
- [ ] Les deux `ScaledObject` portent les déclencheurs `rabbitmq`, `cron` (fuseau `Europe/Paris`) et `prometheus`, un `fallback` et un comportement d'HPA ; ils sont `Ready` et non en pause.
- [ ] Prometheus collecte KEDA ; les trois alertes sont chargées.
- [ ] `docs/plateforme-dev/autoscaling.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 28 13`

<details><summary>Indice 1</summary>

Avec `minReplicaCount: 0`, l'HPA n'existe que pour 1 ↔ N : un HPA ne descend jamais sous un réplica. C'est KEDA qui décide de passer à 0 (après `cooldownPeriod` sans activité) et d'en sortir (dès qu'un déclencheur dépasse son seuil d'**activation**). Relis aussi ce que la page de spécification dit des valeurs admises pour `idleReplicaCount`.
</details>

<details><summary>Indice 2</summary>

Le nom de la métrique externe que KEDA sert à l'HPA se lit dans le `ScaledObject` (`status.externalMetricNames`) ou dans l'HPA (`spec.metrics`). La page *Operate → KEDA Metrics Server* montre la requête `kubectl get --raw` correspondante, avec le sélecteur `scaledobject.keda.sh/name`. Plusieurs déclencheurs : l'HPA calcule un nombre de réplicas par métrique et garde le **plus grand**.
</details>

<details><summary>Indice 3</summary>

Le `fallback` ne s'applique qu'aux métriques de type `Value` ou `AverageValue`, et tant que l'HPA calcule : pense au cas où MédiNotif est **à zéro** quand RabbitMQ devient injoignable. Côté supervision, le ServiceMonitor du chart ne garde pas les étiquettes de la cible par défaut : l'étiquette `namespace` des métriques `keda_*` devient `exported_namespace` dans Prometheus. Écris tes alertes en conséquence.
</details>

**Pour aller plus loin** (facultatif) : remplace les trois déclencheurs par une formule (`advanced.scalingModifiers`) qui combine la longueur de file et le débit de publication, et compare le comportement pendant une mini-campagne. Lis la fiche du KEDA HTTP add-on (bêta) et dis s'il aurait sa place devant MédiAgenda.

---

### M28-E14 — Capacité et équité : quotas, priorités et recommandations  `LAB` `★★★`

> **Ticket PLAT-2914** — *De : Claire Morel* — *Copie : Karim Benali, Julien Petit*
> Le libre-service va ouvrir les vannes. Avant, je veux trois garanties écrites et appliquées : (1) chaque équipe a un **budget** qu'elle ne peut pas dépasser, quel que soit le nombre d'espaces qu'elle crée ; (2) quand le cluster est plein, la **production passe avant** la recette, et les traitements par lots attendent ; (3) les `requests` que les équipes déclarent sont **justes** : le VPA sait ce qu'elles consomment, je veux que ses recommandations arrivent chez elles sous forme de MR, pas dans un tableau que personne ne lit. Et un tableau de bord qui me dise où on en est.

**Objectifs pédagogiques**
- Distinguer le quota d'un espace (`ResourceQuota`) du budget d'un locataire Capsule (quota global sur tous ses espaces) et les combiner.
- Concevoir des classes de priorité (valeur, préemption, valeur par défaut) et comprendre la préemption par l'ordonnanceur, son interaction avec les PDB et les évictions du kubelet.
- Transformer les recommandations du VPA en changements proposés, sans laisser le VPA toucher aux pods.
- Construire un tableau de bord de capacité fondé sur les `requests` (ce que l'ordonnanceur réserve), pas seulement sur la consommation.

**Prérequis** : M28-E04, M28-E05 ; M19-E27 (`medisphere-ci`) ; M21 (Grafana, kube-state-metrics).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Capacité : trois travailleurs à 4 vCPU et 10 Go (allouable ≈ 3,8 vCPU et ≈ 9 Gio chacun, à relire : `kubectl describe node`), dont `k8s-w03` réservé aux bases (`dedie=bdd:NoSchedule`).
- Capsule 0.15 propose deux façons de borner un locataire : l'ancien champ `spec.resourceQuotas` (portée `Tenant` ou `Namespace`, **déprécié**) et les **règles** (`spec.rules[].quota`), qui génèrent un objet `GlobalResourceQuota` partagé par les espaces sélectionnés. Lis la page *Rules* et le schéma (`kubectl explain tenant.spec.rules.quota`) **à ta version** avant d'écrire.
- Classes de priorité à créer (nom fixé, valeur et politique à décider) : `medisphere-critique`, `medisphere-standard`, `medisphere-lot` ; `medisphere-ci` existe (1000, `Never`). Fichiers dans `plateforme/k8s/ordonnancement/` (là où vit `priorite-ci.yaml`).
- Le compte des checks lit les `VerticalPodAutoscaler` ; le script de recommandations tourne depuis `adm01` (ou une CI planifiée) avec un compte de lecture, et ouvre la MR avec un jeton de projet.

**Travail demandé**
1. **Bilan de capacité.** Calcule pour chaque travailleur l'allouable, la somme des `requests` et des `limits` (par espace et par locataire), et la consommation réelle (p95 sur 7 jours). Écris le taux de réservation et de sur-réservation (*overcommit*) mémoire et CPU.
2. **Budgets des locataires.** Le budget de M28-E05 ne couvre que le libre-service : donne à chacun des trois locataires un budget **global** (CPU et mémoire réservés, limite mémoire, pods) qui couvre **tous** ses espaces, environnements compris, cohérent avec ton bilan, en gardant les quotas d'espace existants (la production garde le sien) et le budget du libre-service. Vérifie qu'un espace de libre-service créé par l'équipe consomme bien le budget du locataire (`kubectl get globalresourcequotas` ou l'état du locataire).
3. **Priorités.** Crée les trois classes : valeurs, `preemptionPolicy`, aucune ou une seule `globalDefault` (décide et écris pourquoi). Affecte : production de MédiAgenda (Rollout **et** `mediagenda-db`) et de MédiNotif → `critique` ; recette, dev et libre-service → `standard` ; traitements par lots (CronJobs, essais de charge) → `lot`. Restreins dans chaque locataire les classes autorisées et la classe par défaut.
4. **PDB.** Vérifie que chaque charge de production a un PDB compatible avec son nombre minimal de réplicas (HPA, KEDA) ; corrige ce qui ne l'est pas (un PDB qui ne permet aucune éviction bloque le drainage d'un nœud).
5. **Préemption, en vrai.** Dans `wb-essais`, remplis un travailleur avec des pods d'une classe basse, puis crée un pod d'une classe plus haute qui ne tient pas : observe la préemption (événements `Preempted`, `nominatedNodeName`). Recommence en inversant les rôles (pod de classe basse contre pods de classe haute) : pourquoi rien ne se passe ? Nettoie.
   > ⚠️ **Attention** : ne fais pas cet essai avec `medisphere-standard` contre `medisphere-lot`. L'ordonnanceur peut choisir ses victimes parmi **tous** les pods de priorité inférieure du nœud, y compris les composants de la plateforme qui n'ont pas de classe (priorité 0) : c'est eux qu'il délogerait. Crée pour l'essai deux classes **temporaires de valeur négative** (par exemple `essai-basse` à −100 en `Never` et `essai-haute` à −10), qui ne peuvent préempter que les pods de l'essai, et supprime-les à la fin. Explique dans `capacite.md` ce que cet avertissement dit des composants de la plateforme.
6. **Recommandations en MR.** Écris `outils/recommandations-vpa.sh` dans `plateforme/k8s` : il lit les VPA du cluster, compare la cible recommandée aux `requests` déclarées par le gabarit de pod de la cible, ne retient que les écarts significatifs (seuil en paramètre), écrit un rapport Markdown daté dans `rapports/vpa/` et ouvre une MR qui l'ajoute. Lance-le une fois.
7. **Tableau de bord.** Ajoute dans `plateforme/observabilite/tableaux/plateforme/` un tableau « Capacité et locataires » : `requests`/allouable par nœud, budget consommé par locataire, pods en attente par classe de priorité, préemptions et évictions, écart recommandations VPA / `requests`.
8. **Écris** `docs/plateforme-dev/capacite.md` : bilan, budgets, classes de priorité et leur usage, règles de préemption, procédure de révision des budgets.

**Critères de réussite**
- [ ] Les trois classes existent avec `critique` > `standard` > `lot`, `lot` sans préemption.
- [ ] Chaque locataire a un budget global et une liste de classes autorisées avec une classe par défaut.
- [ ] Les pods de production de MédiAgenda et de MédiNotif tournent en `medisphere-critique` ; chacun a un PDB.
- [ ] `outils/recommandations-vpa.sh` est sur `main` de `plateforme/k8s` et une MR de recommandations a été ouverte ; le tableau « Capacité et locataires » est dans Grafana ; `capacite.md` est publié.

**Vérification** : `lab/bin/check 28 14`

<details><summary>Indice 1</summary>

Le quota d'un espace et le budget d'un locataire **s'ajoutent** : une création doit passer les deux. Avec un budget de locataire, une équipe qui crée dix espaces ne multiplie pas sa capacité par dix. Pour qu'un `ResourceQuota` (ou un budget) sur `requests.cpu` s'applique, chaque pod doit déclarer ses `requests` : c'est le rôle des `LimitRange`.
</details>

<details><summary>Indice 2</summary>

Une classe sans `globalDefault` laisse les pods qui n'en demandent pas à la priorité **0** : en dessous de toute classe positive. Pense à ce que deviennent les composants de la plateforme (Argo CD, Kyverno, Prometheus…) face à un pod de valeur supérieure, et à ce que Capsule peut faire pour les seuls espaces des locataires (`priorityClasses.default`).
</details>

<details><summary>Indice 3</summary>

Pour le script : `kubectl get vpa -A -o json` donne `status.recommendation.containerRecommendations[].target` ; la cible (`spec.targetRef`) donne le gabarit (`spec.template.spec.containers[].resources.requests`) — pour un Rollout en `workloadRef`, le gabarit est dans le Deployment référencé. Convertis les quantités (`m`, `Mi`, `Gi`, `k`…) avant de comparer.
</details>

**Pour aller plus loin** (facultatif) : ajoute au script une sortie « *patch* Kustomize » prête à coller dans l'overlay de l'équipe, et une règle d'alerte quand l'écart dépasse 50 % pendant 7 jours.

---

### M28-E15 — Isolation des locataires : tenter de s'évader  `LAB` `★★★`

> **Ticket SEC-2915** — *De : Sophie Laurent* — *Copie : Claire Morel*
> Avant d'ouvrir le libre-service à MédiDoc, je veux un **essai d'intrusion** : quelqu'un qui a exactement les droits d'un propriétaire de locataire essaie de sortir de son cadre — créer un espace hors de son préfixe, désactiver la sécurité des pods, s'installer sur un nœud de contrôle, publier un service sur le réseau, lire les secrets d'une autre équipe, se donner `cluster-admin`, ouvrir le réseau. Je veux savoir ce qui l'arrête (et quoi : Capsule, Kyverno, PSA, RBAC, Cilium), ce qui ne l'arrête pas, et que les trous soient bouchés avant la mise en service. Rapport écrit, avec les commandes.

**Objectifs pédagogiques**
- Tester une isolation **par l'attaque**, avec l'identité réelle d'un propriétaire, et attribuer chaque refus au mécanisme qui l'a produit (lire le message d'erreur).
- Connaître le périmètre de chaque couche : RBAC (qui peut faire quoi), Capsule (ce qu'un propriétaire peut créer dans son locataire), Pod Security Admission (ce qu'un pod peut demander), Kyverno (règles de la maison), Cilium (qui parle à qui).
- Boucher les trous au bon endroit, par le code, et rejouer l'essai.

**Prérequis** : M28-E05, M28-E14 ; M26 (PSA, Kyverno, politiques réseau) ; M24 (comptes FreeIPA, groupes OIDC).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Compte d'essai : crée dans FreeIPA, par le code de `plateforme/identite/annuaire/`, l'utilisateur **`essai-medidoc`** membre du seul groupe `medidoc`, et connecte-toi avec lui par kubelogin dans un **contexte à part** (`kubectl config set-context essai-medidoc …`, cache de jetons distinct). Il sera désactivé à la fin (même chemin).
- Les espaces créés par ce compte doivent commencer par `medidoc-` ; utilise `medidoc-essai-isolation` pour les essais et supprime-le à la fin.
- Les CiliumClusterwideNetworkPolicy `isolement-<espace>` du M15 cloisonnent les espaces **existants** d'équipe ; la GeneratingPolicy `networkpolicy-par-defaut` du M26 donne un refus par défaut aux espaces étiquetés `medisphere.internal/equipe`.
- Capsule pose sur chaque espace d'un locataire l'étiquette `capsule.clastix.io/tenant: <locataire>` ; depuis M28-E05, le propriétaire est `view` sur les environnements et `admin` sur les espaces de libre-service, qui reçoivent d'office les étiquettes PSA `restricted` et `medisphere.internal/libre-service: "oui"`.

> ⚠️ **Attention** : tu travailles avec un compte qui **peut réellement** créer des objets. N'essaie jamais une évasion sur un espace existant d'une équipe ni sur la production : seulement dans `medidoc-essai-isolation`. Les essais de réseau visent `medidoc-dev`, jamais `*-prod`. Si un essai réussit là où il devait échouer, supprime l'objet créé tout de suite et note-le comme trou.

**Travail demandé**
1. **Prépare** le compte d'essai et son contexte ; vérifie ses droits sans rien créer (`kubectl auth can-i --list` dans un espace de MédiDoc, dans `mediagenda-recette`, au niveau du cluster).
2. **Tente**, depuis ce compte, chacun des essais ci-dessous ; pour chacun, note la commande, le résultat, le **mécanisme** qui a refusé (ou « accepté ») et le message :
   1. créer un espace `projet-x` (hors préfixe), puis `medidoc-essai-isolation` ;
   2. changer les étiquettes PSA de `medidoc-essai-isolation` (`enforce: privileged`), puis y créer un pod privilégié ;
   3. créer un pod qui tolère la taint des nœuds de contrôle et qui vise `k8s-cp01` (par `nodeSelector`, puis par `nodeName`) ;
   4. créer un Service `LoadBalancer`, puis `NodePort` ;
   5. lire les Secrets de `mediagenda-recette`, de `medidoc-dev` (un environnement de son propre locataire) et de `medidoc-essai-isolation` ;
   6. créer dans `medidoc-essai-isolation` un `RoleBinding` vers la ClusterRole `cluster-admin`, puis vers `admin` ; créer un `RoleBinding` dans `medidoc-dev` ;
   7. créer une `NetworkPolicy` qui autorise tout en entrée et en sortie, puis joindre depuis un pod de `medidoc-essai-isolation` un pod de `mediagenda-recette` et l'API de RabbitMQ ;
   8. utiliser une classe de stockage autre que `ceph-rbd`, une classe de priorité `medisphere-critique`, une image hors du registre de la plateforme.
3. **Classe** tes résultats : bloqué par la bonne couche / bloqué par hasard / **non bloqué** (trou). Attends-toi à au moins deux trous liés au **libre-service** : un espace créé par une équipe n'hérite pas forcément de ce que la plateforme a posé à la main sur les espaces existants (politiques réseau notamment) ; vérifie aussi que ce que M28-E05 a posé (PSA, budget) tient réellement.
4. **Comble les trous** par le code (`plateforme/k8s/locataires/`, `plateforme/politiques`, `plateforme/k8s/composants/reseau/politiques/`), au minimum : étiquettes PSA `restricted` présentes et non modifiables sur tout espace de locataire (vérifie le travail de E05, et ajoute un second verrou d'admission) ; refus réseau par défaut et cloisonnement **par locataire** (y compris pour les espaces futurs, sans fichier à ajouter à chaque création) ; aucune tolérance des nœuds de contrôle ni `nodeName` dans les espaces de locataire (ValidatingPolicy Kyverno **`locataires-placement`**) ; aucun Service `LoadBalancer`, `NodePort` ni `ExternalName`.
5. **Rejoue** tous les essais après correction, puis supprime `medidoc-essai-isolation` et désactive `essai-medidoc`.
6. **Écris** `docs/plateforme-dev/essais-isolation.md` : tableau des essais (avant/après), trous trouvés et corrections (avec les MR), ce qui reste hors périmètre (noyau partagé, quotas de bande passante, déni de service par l'API…) et quand rejouer l'essai.

**Critères de réussite**
- [ ] Tout espace d'un locataire porte `pod-security.kubernetes.io/enforce: restricted` et une NetworkPolicy `refus-par-defaut`.
- [ ] Chaque locataire est cloisonné des autres par une politique Cilium qui suit l'étiquette `capsule.clastix.io/tenant` (pas une liste d'espaces).
- [ ] La ValidatingPolicy `locataires-placement` est chargée ; les Services `LoadBalancer` et `NodePort` sont refusés aux locataires ; le préfixe est imposé.
- [ ] `medidoc-essai-isolation` n'existe plus ; `essai-medidoc` est désactivé ou supprimé ; `essais-isolation.md` est publié.

**Vérification** : `lab/bin/check 28 15`

<details><summary>Indice 1</summary>

Le message d'erreur dit presque toujours qui a refusé : `admission webhook "…capsule…" denied`, `admission webhook "…kyverno…"`, `violates PodSecurity "restricted:…"`, `is forbidden: User "…" cannot … ` (RBAC), `attempting to grant RBAC permissions not currently held` (prévention de l'escalade). Un échec réseau, lui, ne dit rien : `hubble observe --verdict DROPPED` le montre.
</details>

<details><summary>Indice 2</summary>

Un espace sans étiquette PSA n'est pas « restricted par défaut » : sans configuration d'admission explicite, le niveau par défaut du cluster est `privileged`. Une GeneratingPolicy qui se déclenche sur `medisphere.internal/equipe` ne voit pas un espace qui ne porte que l'étiquette de Capsule. Une politique Cilium peut sélectionner des pods par les **étiquettes de leur espace** (`io.cilium.k8s.namespace.labels.<clé>`).
</details>

<details><summary>Indice 3</summary>

Pour les étiquettes PSA, deux leviers complémentaires : les métadonnées que Capsule ajoute aux espaces d'un locataire (et celles qu'il interdit à un propriétaire de modifier), et une règle d'admission qui refuse un espace de locataire sans `enforce: restricted`. Pour `nodeName` : un pod créé avec ce champ contourne l'ordonnanceur, donc les taints de type `NoSchedule`.
</details>

**Pour aller plus loin** (facultatif) : relis l'avis GHSA-p8j8-x28r-3c9v (contournement d'autorisation corrigé en Capsule 0.15.0) et écris l'essai qui l'aurait détecté ; ajoute-le à ton rapport comme essai de non-régression.

---

### M28-E16 — Backstage en production : mise à jour, sauvegarde, supervision  `LAB` `★★★`

> **Ticket PLAT-2916** — *De : Karim Benali* — *Copie : Nadia Roussel*
> Le portail est devenu le point d'entrée des équipes : s'il tombe, plus personne ne crée de service, et si sa base disparaît, on perd les tâches du *scaffolder* et l'historique. Aujourd'hui : un pod, aucune sauvegarde, aucune métrique, une version qui a déjà un mois de retard. Je veux une montée de version **outillée** (pas un `package.json` édité à la main), deux réplicas avec des sondes correctes, la base sauvegardée comme `mediagenda-db`, des métriques, des journaux, une alerte, et un runbook pour Nadia.

**Objectifs pédagogiques**
- Monter de version une application Backstage par l'outil prévu (`backstage-cli versions:bump`), lire les notes de version et les changements à reporter, livrer par MR et image signée.
- Rendre le portail tolérant à la perte d'un pod (réplicas, sondes de santé du nouveau backend, PDB, secret de session partagé).
- Sauvegarder `portail-db` par le plugin Barman Cloud (archivage continu des WAL, sauvegarde planifiée) et éprouver une restauration.
- Exposer des métriques (OpenTelemetry → exportateur Prometheus), collecter les journaux, écrire l'alerte et le runbook.

**Prérequis** : M28-E06, M28-E10 ; M16 (plugin Barman Cloud) ; M21-M22 (métriques, journaux) ; M19 (CI, signature).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Notes de version : `backstage.io/docs/releases/` ; procédure : *Keeping Backstage Updated* (`yarn backstage-cli versions:bump`, option `--release`). La version installée est dans `backstage.json`.
- Sondes du nouveau backend : `/.backstage/health/v1/readiness` et `/.backstage/health/v1/liveness` (port 7007), déjà utilisées par défaut par le chart `backstage` 2.10.
- Métriques : tutoriel *Setup OpenTelemetry* (fichier `packages/backend/src/instrumentation.js` chargé par `--require`, exportateur Prometheus sur le port **9464**). Le chart crée un ServiceMonitor (`metrics.serviceMonitor`) ; le port doit être exposé par le Service.
- Sauvegarde : même modèle que `mediagenda-db` (M16-E19, M25) : `ObjectStore` du plugin Barman Cloud vers `s3://cnpg-k8s-par1/` sur `s3-01`, `ScheduledBackup` en méthode `plugin`.

**Travail demandé**
1. **Montée de version.** Sur une branche de `plateforme/portail` : `yarn backstage-cli versions:bump --release <VERSION-CIBLE>` (la dernière corrective publiée de la mineure courante, ou la mineure suivante si elle est sortie et que les notes ne signalent rien de bloquant), `yarn install`, `yarn tsc`, `yarn build:backend`. Lis les notes de version entre les deux versions et reporte dans la MR ce qui te concerne (dépréciations, migrations de configuration). La CI construit, signe et pousse la nouvelle image ; la promotion passe par MR dans `plateforme/gitops/valeurs/portail/`.
2. **Deux réplicas.** Passe le portail à deux réplicas répartis sur deux nœuds, avec PDB, sondes de démarrage/vivacité/disponibilité adaptées au temps de démarrage mesuré, `priorityClassName` (E14) et requêtes/limites issues de la recommandation du VPA. Vérifie ce qui doit être partagé entre réplicas (secret de session de l'authentification, clés de service-à-service, base) et ce qui ne doit pas tourner deux fois.
3. **Sauvegarde.** Ajoute à `portail-db` l'archivage continu (plugin Barman Cloud, identifiants S3 par ESO) et une sauvegarde nocturne ; lance une sauvegarde à la demande. **Restaure** la base dans `wb-essais` (nouveau cluster CNPG depuis la sauvegarde), vérifie qu'elle contient les tâches du *scaffolder*, puis supprime l'essai.
4. **Métriques.** Instrumente le backend (OpenTelemetry, exportateur Prometheus), expose le port, active le ServiceMonitor ; vérifie dans Prometheus que la cible est `up` et relève trois métriques utiles (catalogue, requêtes HTTP, *scaffolder*).
5. **Journaux.** Vérifie que les journaux du portail arrivent dans Loki (locataire `plateforme`) et qu'on y retrouve une exécution du *scaffolder* par son identifiant de tâche.
6. **Alertes.** Ajoute une alerte « portail indisponible » (aucun réplica prêt ou sonde blackbox en échec sur `https://portail.apps.par1.medisphere.internal`) et une alerte « sauvegarde de `portail-db` trop ancienne ».
7. **Runbook RB-284** « Le portail est indisponible » (`docs/plateforme-dev/runbooks/RB-284-*.md`) : ce qui est touché (et ce qui ne l'est pas : les applications tournent sans le portail), diagnostic par étage (Gateway, pods, base, OIDC, GitLab), retour arrière d'une montée de version, restauration de la base. Complète `docs/plateforme-dev/portail-exploitation.md` (version, procédure de montée, sauvegarde, métriques).

**Critères de réussite**
- [ ] Le portail tourne avec deux réplicas prêts sur deux nœuds, un PDB et les sondes de santé du backend.
- [ ] L'image déployée correspond à la dernière étiquette de `plateforme/portail`, signée, et `backstage.json` sur `main` a été modifié par la montée de version.
- [ ] `portail-db` archive en continu et a une sauvegarde `completed` de moins de 26 h.
- [ ] Prometheus collecte le portail ; les deux alertes sont chargées ; Loki reçoit ses journaux ; RB-284 est publié.

**Vérification** : `lab/bin/check 28 16`

<details><summary>Indice 1</summary>

`versions:bump` ne touche que les dépendances `@backstage/*` (et celles du motif `--pattern`) : les fichiers créés par `create-app` (par exemple `packages/backend/src/index.ts`, `app-config.yaml`) ne sont pas mis à jour tout seuls. Les notes de version et le *Backstage Upgrade Helper* montrent ce qui a changé dans le gabarit de `create-app` entre deux versions.
</details>

<details><summary>Indice 2</summary>

Avec deux réplicas, un utilisateur connecté sur l'un doit rester connecté s'il arrive sur l'autre : le secret de session (`auth.session.secret`) doit être **le même** (lu dans OpenBao, pas généré au démarrage). Les tâches planifiées du backend se coordonnent par la base : vérifie qu'aucun traitement de ton application n'est lancé « au démarrage de chaque pod ».
</details>

<details><summary>Indice 3</summary>

Le ServiceMonitor du chart vise un **port nommé du Service** : ajoute le port 9464 au conteneur (`backstage.extraPorts`) **et** au Service (`service.extraPorts`), puis donne son nom à `metrics.serviceMonitor.port`. Sans l'étiquette de sélection de M21 (`medisphere.internal/supervision: "oui"`), Prometheus ignore le ServiceMonitor.
</details>

**Pour aller plus loin** (facultatif) : programme la montée de version mensuelle par Renovate (M13) avec un regroupement `@backstage/*` et une MR qui lance `versions:bump` plutôt que de changer les versions une à une.

---

### M28-E17 — ADR : la plateforme développeurs de MédiSphère  `RED` `★★`

> **Ticket PLAT-2917** — *De : Claire Morel*
> Je présente la plateforme développeurs au comité d'architecture jeudi. J'ai besoin de l'ADR-0280 : ce qu'on a choisi, ce qu'on a écarté et pourquoi, ce que ça coûte (mémoire, temps de l'équipe), les risques, ce qui nous ferait changer d'avis. Une page et demie, lisible par quelqu'un qui n'a pas fait les exercices.

**Objectifs pédagogiques**
- Rédiger une décision d'architecture argumentée à partir des mesures et essais du module.
- Expliciter les alternatives écartées et les conditions de révision.

**Prérequis** : M28-E01 à M28-E16.
**Durée indicative** : 1 h.

**Travail demandé** : écris `docs/plateforme-dev/adr/ADR-0280-plateforme-developpeurs.md` (format des ADR de la maison : contexte, décision, conséquences, alternatives, révision) qui couvre au minimum :
1. **Portail** : Backstage retenu (catalogue, modèles, documentation) ; ce que coûte son exploitation (montées mensuelles, TypeScript, base, mémoire) ; alternatives (pas de portail : README et modèles GitLab ; portails commerciaux).
2. **Multi-locataire** : Capsule plutôt qu'un vCluster par équipe (mesures de E05 et E09 : mémoire, isolation, complexité) ; quand un vCluster se justifierait.
3. **Autoscaling** : HPA pour MédiAgenda, KEDA pour MédiNotif (file, cron, Prometheus), VPA **en recommandation seulement** (pourquoi pas en mode automatique ; jamais VPA et HPA sur la même ressource) ; pas d'autoscaling de nœuds (pourquoi, et ce qui le remplace : budgets, priorités, bilan de capacité).
4. **Écartés** : Crossplane (fiche `annexes/decouverte/crossplane.md`) et Tilt/Skaffold (fiche `annexes/decouverte/tilt-skaffold.md`) : pourquoi pas maintenant, et le signal qui ferait revoir chaque décision.
5. **Risques** et mesures : portail point unique d'entrée des équipes, mise à zéro et démarrage à froid, préemption, contournement d'autorisation de Capsule (version minimale), montée de Kubernetes exigée par Capsule.

**Critères de réussite**
- [ ] L'ADR est sur `main` de `plateforme/medisphere` et traite chacun des cinq points avec au moins un chiffre mesuré dans le module.
- [ ] Chaque alternative écartée a une condition de révision explicite.

**Vérification** : `lab/bin/check 28 17` (présence et rubriques ; le fond s'auto-évalue avec le corrigé).

<details><summary>Indice 1</summary>

Reprends tes mesures : mémoire de Backstage et de sa base, de Capsule, d'un vCluster ; démarrage à froid de MédiNotif ; temps de création d'un service par le modèle contre « six tickets et dix jours ». Une décision chiffrée se défend mieux qu'une préférence.
</details>

<details><summary>Indice 2</summary>

Une bonne condition de révision est observable : « si une équipe a besoin d'installer ses propres CRD », « si plus de N services sont créés par trimestre », « si MédiSphère adopte un cloud public pour… ».
</details>

---

### M28-E18 — Questions de production : plateforme développeurs  `Q` `★★★`

> **Ticket PLAT-2918** — *De : Karim Benali*
> Avant de te laisser l'astreinte de la plateforme développeurs, douze questions. Réponds comme à un collègue : court, juste, avec le pourquoi.

**Objectifs pédagogiques**
- Vérifier la compréhension des mécanismes et des compromis de production du module.

**Prérequis** : M28-E13 à M28-E17.
**Durée indicative** : 1 h.

**Questions**
1. MédiNotif est à zéro en recette, la file reçoit un message. Décris dans l'ordre ce qui se passe jusqu'à son traitement, qui fait quoi (KEDA, HPA, ordonnanceur, kubelet, MédiNotif), et ce qui fixe la durée totale. Comment la réduire, et à quel prix ?
2. Pourquoi « scale-to-zero » est-il raisonnable pour MédiNotif et déraisonnable pour MédiAgenda ? Quel outil le permettrait pour MédiAgenda, et quel serait le coût pour l'utilisateur ?
3. Un `ScaledObject` a trois déclencheurs : `rabbitmq` (file : 30 000 messages, seuil 500), `cron` (10 réplicas), `prometheus` (débit 40/s, seuil 10). Combien de réplicas l'HPA demande-t-il (`maxReplicaCount: 50`) ? Et si le scaler `rabbitmq` est en erreur avec un `fallback` de 4 réplicas, comportement `static` ?
4. Pourquoi ne faut-il jamais mettre un VPA en mode automatique et un HPA sur le **CPU** sur la même charge ? Existe-t-il une combinaison VPA + HPA acceptable ?
5. Un développeur te demande « l'autoscaling de nœuds, comme sur AWS ». Que réponds-tu pour `k8s-par1` (Cluster Autoscaler, Karpenter, Cluster API) ? Qu'est-ce qui le remplace aujourd'hui chez MédiSphère ?
6. Quelle est la différence entre la préemption par l'ordonnanceur et l'éviction par le kubelet ? Laquelle respecte les PDB, laquelle tient compte de la priorité ?
7. Une équipe a un budget de locataire de 4 vCPU de `requests`, déjà consommé à 3,9. Elle crée un nouvel espace de libre-service et y déploie un pod de 200m. Que se passe-t-il, à quel moment, et quel message voit-elle ? Et si le pod n'a pas de `requests` ?
8. Capsule ou vCluster pour une équipe qui veut installer ses propres CRD et un opérateur ? Et pour une équipe qui veut juste « ses espaces » ?
9. Pourquoi Crossplane n'est-il pas retenu chez MédiSphère alors qu'il est populaire pour les plateformes internes ? Dans quel cas changerais-tu d'avis ?
10. Tilt ou Skaffold : quel problème résolvent-ils, que fait déjà `docker compose` (M12) pour MédiAgenda, et qu'apporteraient-ils au chemin balisé ?
11. Combien coûte le portail (mémoire, stockage, temps de l'équipe par mois) ? Qu'est-ce qui justifie ce coût, et qu'est-ce qui te ferait le retirer ?
12. Le portail est en panne pendant une journée. Qu'est-ce qui ne marche plus, qu'est-ce qui marche encore, et pourquoi est-ce une conséquence voulue de l'architecture (GitOps, MR) ?

**Critères de réussite**
- [ ] Chaque réponse tient en un paragraphe, cite le mécanisme et le chiffre quand il y en a un, et dit pourquoi les autres options sont moins bonnes (auto-évaluation avec le corrigé).

<details><summary>Indice 1</summary>

Pour la question 3, l'HPA calcule un nombre de réplicas par métrique (`AverageValue` : valeur ÷ seuil) puis garde le maximum, borné par `minReplicaCount`/`maxReplicaCount`. Pour le `fallback`, relis la formule donnée par la documentation pour `AverageValue`.
</details>

<details><summary>Indice 2</summary>

Pour la question 6 : *Pod Priority and Preemption* et *Node-pressure Eviction* dans la documentation de Kubernetes ; cherche les mots « PodDisruptionBudget » et « best effort » dans chacune.
</details>
