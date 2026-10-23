# Module 28 — Palier 4 : Expert

La plateforme développeurs est en service : les applications suivent leur charge, les équipes ont leurs locataires et leur portail. Nadia Roussel pose sa question habituelle : « Le jour où l'autoscaling, un locataire ou le portail se dérègle, au moment précis où une équipe en a besoin, qui sait quoi faire ? » Karim Benali a préparé quatre pannes tirées d'incidents réels de plateformes internes — un autoscaling muet, des pods qui oscillent, une équipe bloquée, un portail qui ne crée plus rien — puis une astreinte où **un locataire sature le cluster**. Tu finis sous le capot : la boucle de l'HPA, le chemin d'une métrique externe et les webhooks de Capsule.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Trois règles propres à ce module :
- **Remonte la chaîne de décision.** Un effectif de pods est le résultat d'une chaîne : source (file, Prometheus, CPU) → scaler ou metrics-server → API de métriques → HPA (calcul, bornes, comportement) → sous-ressource `scale` de la charge → contrôleur → ordonnanceur. Un refus de création est le résultat d'une autre : RBAC → webhooks d'admission (Capsule, Kyverno) → PSA → quotas. Situe le maillon avant de toucher quoi que ce soit : `kubectl describe` (événements), conditions des objets (`ScaledObject`, `HPA`, `Tenant`), journaux des contrôleurs.
- **Plusieurs pilotes, un seul volant.** Argo CD, l'HPA, KEDA et le VPA peuvent tous écrire sur la même charge. Avant de corriger, demande-toi **qui** a écrit en dernier (`metadata.managedFields`, historique d'Argo CD, événements) et **qui devrait** être le seul à écrire.
- **Le code fait foi, l'historique aussi.** Tout passe par Git (`medinotif/deploiement`, `mediagenda/deploiement`, `plateforme/k8s`, `plateforme/gitops`, `plateforme/portail-modeles`) et Argo CD : un correctif à chaud est défait à la synchronisation suivante. Lis `git log` : la plupart des pannes ont un auteur et une date.

> **Rappels** : tout se lance depuis `adm01`, à la racine de ta copie du workbook. Ton identité OIDC pour le cluster (contexte `k8s-par1`) ; `argocd` ; `bao` (session OIDC) ; l'interface de RabbitMQ ; Grafana, Prometheus, Loki ; le portail.

## Règles du jeu des pannes (M28-E19 à M28-E23)

- Les pannes s'injectent **depuis `adm01`** :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 28 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Les pannes E19 à E22 ont 2 à 4 variantes (l'astreinte E23 n'en a qu'une) : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante). Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé), le script en essaie une autre. Une injection prend **de 1 à 15 minutes** : certaines passent par un commit dans GitLab, la synchronisation d'Argo CD et l'attente d'un effet visible.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 28 19`) : il doit être vert, sauf les lignes qui portent sur ce que l'exercice te fait écrire ou ajouter (runbook, post-mortem). Le script refuse de casser un lab qui ne va pas bien.
- **Prérequis techniques** : `admin.conf` (`WB_K8S_ADMIN_KUBECONFIG`, bris de glace : les pannes ne peuvent pas passer par une connexion OIDC interactive, et E21 emprunte l'identité d'un membre de MédiDoc en `--dry-run=server`) ; le jeton d'administration GitLab de M01 (`WB_GITLAB_ADMIN_TOKEN_FILE`, portée `api`, expiration courte) ; le jeton des checks du portail (E22) ; `yq` de mikefarah (v4), `jq`, `curl` sur `adm01`.
- **Commits de Lucas.** Certaines pannes modifient un dépôt par un commit signé « Lucas Martin » (marqueur `M28-EXX` dans le message) ; si `main` refuse la poussée directe, elles passent par une MR que le script fusionne après son pipeline. C'est un vrai changement : il apparaît dans `git log`, dans l'historique d'Argo CD et dans le journal d'audit de GitLab. Corrige comme tu le ferais d'un vrai commit fautif (revert par MR, ou correction par MR). D'autres pannes changent un droit dans GitLab ou ajoutent, suppriment ou modifient un objet « à la main » dans le cluster. **Aucune panne ne modifie un secret** (OpenBao, Secret Kubernetes) ni ne redémarre ou ne coupe un composant partagé avec la production.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 28 19 --annuler` remet l'état sain (filet de sécurité, pas un correctif). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : l'annulation ne défait jamais ta réparation (elle ne touche un fichier, un secret ou un droit que s'il est encore exactement dans l'état injecté), et une panne laissée ouverte bloque l'astreinte M28-E23 et le mini-projet.
- Les pannes n'agissent que sur : la **recette** et le **dev** des applications (`medinotif-recette`, `mediagenda-recette`, `medidoc-dev`), les dépôts `medinotif/deploiement`, `mediagenda/deploiement` (overlays de recette), `plateforme/k8s/locataires/` et `plateforme/k8s/espaces/medidoc-dev/` (E23), `plateforme/gitops` (`valeurs/capsule/`, modèle de l'ApplicationSet `medinotif`), `plateforme/portail-modeles`, l'appartenance de `svc-portail` aux groupes GitLab, un objet ajouté dans `capsule-system` (E21, sur accord explicite), les garde-fous et une charge de `medidoc-dev` (E23). **Jamais** la production, `kube-system`, `kyverno`, `argocd` ; **jamais** les droits de la plateforme ni d'Argo CD sur Capsule ; aucun message RabbitMQ n'est perdu (les files sont seulement moins consommées).
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/kubernetes/journal/` de `~/medisphere` : heure, hypothèse, commande, résultat observé, conclusion. Il alimente les runbooks RB-285 à RB-289 et le post-mortem de M28-E23.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Effets de bord** : pendant M28-E21, une variante rend les webhooks de Capsule injoignables ; elle n'est tirée que si tu l'acceptes explicitement (`WB_M28_E21_WEBHOOK=oui` dans `lab/lab.env`), car tant qu'elle est active **aucun espace ne peut être créé dans le cluster et aucun pod ne peut démarrer dans un espace de locataire — production comprise** (les webhooks de Capsule refusent quand ils ne répondent pas). Ne la lance qu'à un moment où rien ne doit être déployé, et garde `--annuler` sous la main. Pendant M28-E23, une charge mal configurée occupe du CPU sur un travailleur et ses propres conteneurs sont tués par manque de mémoire ; sa consommation est bornée par ses limites, elle tourne dans une classe qui ne préempte jamais et ne pousse aucun autre pod dehors.

---

### M28-E19 — Panne : MédiNotif ne monte plus en charge  `BF` `★★`

> **Ticket INC-5519** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Suivre la chaîne de KEDA de bout en bout : `ScaledObject` (conditions, annotations), `TriggerAuthentication` et son Secret (ESO), scaler (API de gestion de RabbitMQ), métrique externe, HPA.
- Distinguer « KEDA ne regarde plus », « KEDA regarde mais ne voit pas » et « KEDA voit mais ne peut pas lire ».
- Lire les métriques et événements de KEDA plutôt que deviner.

**Prérequis** : M28-E03, M28-E13 ; `lab/bin/check 28 19` vert avant l'injection.
**Durée indicative** : 20 à 30 min (temps cible).

**Contexte technique** : MédiNotif de recette est piloté par le `ScaledObject` `medinotif` (overlay `recette` de `medinotif/deploiement`) ; le scaler `rabbitmq` lit la file `notifications` du vhost `medinotif-recette` par l'API de gestion (15671) avec le compte de KEDA ; le Secret de la `TriggerAuthentication` `medinotif-rabbitmq` vient d'OpenBao par ESO ; KEDA tourne dans l'espace `keda`. `ressources/E13-campagne/campagne.sh` sert à remplir la file pour constater.

**Injection** : `lab/bin/break 28 19` (2 variantes).

**Travail demandé**
1. Constate sans rien toucher : état de la file (messages prêts, consommateurs), effectif de MédiNotif, état du `ScaledObject` (`kubectl get scaledobject` : colonnes `READY`, `ACTIVE`, `FALLBACK`, `PAUSED`), de l'HPA `keda-hpa-medinotif`, événements de l'espace.
2. Situe le maillon : le `ScaledObject` est-il réconcilié ? Le scaler interroge-t-il (journaux de `keda-operator`, `keda_scaler_detail_errors_total`, `keda_scaler_metrics_value`) ? Que renvoie la métrique externe (`kubectl get --raw`) ? La `TriggerAuthentication` trouve-t-elle son Secret, et l'ExternalSecret est-il à jour ? Le réseau laisse-t-il passer (`hubble observe --from-namespace keda --to-namespace messagerie`) ?
3. Trouve la cause racine et son auteur, corrige-la **au bon endroit** (le dépôt, le coffre ou le cluster, selon ce que tu as prouvé), sans redémarrer KEDA « pour voir ».
4. Vérifie : une petite campagne (`campagne.sh 300`) réveille MédiNotif et vide la file ; `lab/bin/check 28 19`.
5. Écris le runbook **RB-285** « L'autoscaling ne suit plus la charge » (`docs/plateforme-dev/runbooks/RB-285-*.md`) : arbre de décision par maillon, avec la commande qui prouve chaque branche.

**Critères de réussite**
- [ ] Le `ScaledObject` de recette est `Ready`, non en pause, son scaler ne produit plus d'erreur et vise le vhost `medinotif-recette`.
- [ ] La file `notifications` de recette n'a pas de retard ; aucune politique réseau ne coupe `keda` de `messagerie`.
- [ ] RB-285 est publié ; ton journal contient le maillon en cause et sa preuve.

**Vérification** : `lab/bin/check 28 19`

<details><summary>Indice 1</summary>

`kubectl describe scaledobject medinotif -n medinotif-recette` montre les conditions et les derniers événements (`KEDAScalerFailed`, `ScaledObjectPaused`…). `kubectl -n keda logs deploy/keda-operator --since=15m | grep -i medinotif` dit ce que le scaler a tenté et ce qu'on lui a répondu (401, 404, délai dépassé).
</details>

<details><summary>Indice 2</summary>

Une erreur 401 de l'API de gestion : identifiants (le Secret est-il celui qu'ESO a écrit, depuis quelle version du secret OpenBao ? `bao kv metadata get`). Une erreur 404 : le chemin (vhost, nom de file). Un délai dépassé : le réseau. Aucune erreur et aucune interrogation : quelqu'un a demandé à KEDA de ne plus regarder.
</details>

<details><summary>Indice 3</summary>

`git log -p` des overlays de `medinotif/deploiement` et `argocd app history medinotif-recette` : une panne a toujours laissé une trace. Si la cause avait été ailleurs, d'autres traces t'auraient répondu de la même façon : `bao kv metadata get -mount=kv <chemin>` (date de chaque version d'un secret ; l'annotation `force-sync` fait relire un ExternalSecret), date de création des politiques Cilium (`kubectl get ciliumnetworkpolicies -A`).
</details>

**Pour aller plus loin** (facultatif) : écris une alerte qui détecte « file qui grossit alors que MédiNotif ne bouge pas » sans dépendre de KEDA (métriques de RabbitMQ et de kube-state-metrics), et explique pourquoi elle complète `KedaScalerEnErreur`.

---

### M28-E20 — Panne : des pods redémarrent en boucle depuis l'autoscaling  `BF` `★★★`

> **Ticket INC-5520** — *De : Nadia Roussel*
> *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Reconnaître les conflits entre pilotes d'une même charge : VPA et HPA, Argo CD et HPA.
- Lire `metadata.managedFields`, l'historique d'Argo CD, les événements du VPA et de l'HPA pour savoir **qui** écrit.
- Comprendre ce qu'un VPA actif fait aux pods (éviction, admission, limites proportionnelles) et ses bornes.

**Prérequis** : M28-E02, M28-E04, M28-E13 ; `lab/bin/check 28 20` vert avant l'injection.
**Durée indicative** : 30 à 45 min (temps cible).

**Contexte technique** : MédiAgenda de recette (Rollout `mediagenda`, HPA `mediagenda`) et MédiNotif de recette ont chacun un `VerticalPodAutoscaler` nommé comme leur cible, en `updateMode: "Off"` depuis M28-E04. Le VPA de la plateforme comprend le *recommender*, l'*updater* (évictions) et le contrôleur d'admission (réécriture des requests à la création des pods) — vérifie lesquels tournent sur ton lab.

**Injection** : `lab/bin/break 28 20` (3 variantes).

**Travail demandé**
1. Constate : quels pods redémarrent (redémarrages de conteneur, ou pods supprimés et recréés ?), depuis quand, à quel rythme ; état de l'HPA (`kubectl describe hpa`), du Rollout, de l'Application Argo CD de recette (historique de synchronisation).
2. Trouve **qui** agit : événements (`EvictedByVPA`, `SuccessfulRescale`, `ScalingReplicaSet`), raison des arrêts (`lastState.terminated.reason`), `managedFields` de `spec.replicas`, `requests` effectives des pods comparées à celles du gabarit.
3. Trouve la cause racine et son auteur, corrige-la par Git, et explique dans ton journal pourquoi la combinaison était fautive (et non seulement « ce qui a changé »).
4. Vérifie la stabilité pendant 15 minutes : aucun redémarrage, effectif stable sous charge constante ; `lab/bin/check 28 20`.
5. Écris le runbook **RB-286** « Pods qui oscillent ou redémarrent sous l'autoscaling » (`docs/plateforme-dev/runbooks/RB-286-*.md`) et ajoute à la revue de MR une règle qui aurait arrêté le commit.

**Critères de réussite**
- [ ] Aucun VPA en mode actif sur une charge pilotée par un HPA sur le CPU ou la mémoire ; les VPA de recette sont en `Off`.
- [ ] Argo CD ne gère plus `spec.replicas` du Rollout `mediagenda` de recette ; aucun pod de MédiAgenda ni de MédiNotif en recette n'a été tué par manque de mémoire ces 15 dernières minutes.
- [ ] RB-286 est publié.

**Vérification** : `lab/bin/check 28 20`

<details><summary>Indice 1</summary>

Un conteneur qui redémarre (`RESTARTS` qui augmente) et un pod remplacé par un autre (âge qui repart à zéro, nom différent) ne sont pas la même panne. Pour le second, cherche qui l'a supprimé : `kubectl get events --sort-by=.lastTimestamp` dans l'espace, et `kubectl -n vpa logs` de l'*updater*.
</details>

<details><summary>Indice 2</summary>

`kubectl get rollout mediagenda -n mediagenda-recette --show-managed-fields -o yaml` dit qui possède `spec.replicas` (l'HPA écrit par la sous-ressource `scale`, Argo CD par l'application serveur). Un VPA borné (`maxAllowed`) peut recommander moins que ce dont l'application a besoin ; en mode `RequestsAndLimits` (défaut), la limite suit la request dans la même proportion.
</details>

<details><summary>Indice 3</summary>

`git log -p` des overlays de recette des deux dépôts de déploiement et `argocd app history` : chaque variante a un commit. Après le revert, regarde si les pods créés pendant la panne gardent des `requests` modifiées : le contrôleur d'admission du VPA ne les corrige qu'à la création suivante.
</details>

**Pour aller plus loin** (facultatif) : écris une ValidatingPolicy Kyverno qui refuse un `VerticalPodAutoscaler` dont `updateMode` n'est pas `Off` hors de `wb-essais`, et une autre qui refuse un VPA visant la même cible qu'un HPA sur le CPU.

---

### M28-E21 — Panne : une équipe ne peut plus créer d'espace  `BF` `★★`

> **Ticket INC-5521** — *De : Julien Petit (pour l'équipe MédiDoc)*
> *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Diagnostiquer un refus de création d'espace en remontant la chaîne : RBAC (rôle de création des propriétaires), configuration de Capsule (`CapsuleConfiguration`), locataire (propriétaires, quota d'espaces, préfixe), webhooks d'admission.
- Reproduire le geste d'un utilisateur **sans** lui emprunter son compte (impersonation).
- Corriger sans jamais élargir les droits de la plateforme ni d'Argo CD.

**Prérequis** : M28-E05, M28-E15 ; `lab/bin/check 28 21` vert avant l'injection.
**Durée indicative** : 20 à 30 min (temps cible).

**Contexte technique** : les locataires sont dans `plateforme/k8s/locataires/` (Application `locataires`), la configuration de Capsule dans `plateforme/gitops/valeurs/capsule/values.yaml` (`CapsuleConfiguration` `default`). L'équipe MédiDoc (groupe `oidc:medidoc`) crée des espaces de revue `medidoc-revue-<n>`. Pour reproduire son geste avec `admin.conf` : `kubectl --kubeconfig <admin.conf> --as=<utilisateur> --as-group=oidc:medidoc --as-group=system:authenticated create ns medidoc-revue-essai --dry-run=server` (le serveur évalue RBAC et l'admission, sans rien créer).

**Injection** : `lab/bin/break 28 21` (3 variantes, plus une quatrième si `WB_M28_E21_WEBHOOK=oui` : voir l'avertissement en tête de palier).

**Travail demandé**
1. Reproduis le refus avec l'impersonation en `--dry-run=server` et lis le message **en entier** : qui refuse (RBAC, webhook de Capsule, autre) ?
2. Selon le maillon : état du locataire (`kubectl get tenant medidoc` : colonnes de quota et de nombre d'espaces, conditions), propriétaires, `CapsuleConfiguration` (`kubectl get capsuleconfiguration default -o yaml`), webhooks (`kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep -i capsule`, Service et pods de `capsule-system`, journaux de l'API sur l'appel du webhook).
3. Trouve la cause racine et son auteur ; corrige au bon endroit (Git, ou suppression d'un objet posé à la main) ; ne touche ni aux droits d'Argo CD ni à ceux de `plateforme-admins`.
4. Vérifie : le même `--dry-run=server` passe ; `lab/bin/check 28 21`.
5. Écris le runbook **RB-287** « Une équipe ne peut plus créer d'espace » (`docs/plateforme-dev/runbooks/RB-287-*.md`) : messages typiques et leur maillon.

**Critères de réussite**
- [ ] Le locataire `medidoc` est prêt, appartient à `oidc:medidoc`, a de la place pour au moins un espace de plus ; la configuration de Capsule n'interdit pas les noms `medidoc-…`.
- [ ] Les webhooks de Capsule répondent ; aucun objet ajouté à la main dans `capsule-system`.
- [ ] RB-287 est publié.

**Vérification** : `lab/bin/check 28 21`

<details><summary>Indice 1</summary>

`… is forbidden: User "…" cannot create resource "namespaces"` vient de RBAC : Capsule donne aux groupes qu'il gère le droit de créer des espaces ; un groupe que Capsule ne reconnaît plus n'a plus ce droit. Un `admission webhook "…" denied the request` vient d'un webhook, avec sa raison. `failed calling webhook … context deadline exceeded` ou `connection refused` : le webhook ne répond pas.
</details>

<details><summary>Indice 2</summary>

Compare le locataire en vigueur (`kubectl get tenant medidoc -o yaml`) avec ce que tu as écrit en E14-E15 : `git log -p -- locataires/` dans `plateforme/k8s`. Pour la configuration : `git log -p -- valeurs/capsule/` dans `plateforme/gitops`. Pour un objet posé à la main : `kubectl get ciliumnetworkpolicies -n capsule-system --show-labels` et la date de création.
</details>

**Pour aller plus loin** (facultatif) : ajoute une alerte sur les échecs d'appel des webhooks de Capsule (`apiserver_admission_webhook_rejection_count` et `apiserver_admission_webhook_request_total` par nom de webhook et code), et dis pourquoi elle vaut plus qu'une sonde sur le Service.

---

### M28-E22 — Panne : le portail ne crée plus de services  `BF` `★★`

> **Ticket INC-5522** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Suivre une tâche du *scaffolder* étape par étape (journal de la tâche, journaux du backend) jusqu'à l'appel GitLab qui échoue.
- Distinguer un jeton invalide (401), un droit insuffisant (403) et un modèle cassé (action inconnue, paramètre faux).
- Corriger chaque cause à sa source : secret dans OpenBao (ESO), appartenance dans GitLab, commit dans le dépôt des modèles.

**Prérequis** : M28-E06, M28-E08, M28-E16 ; `lab/bin/check 28 22` vert avant l'injection.
**Durée indicative** : 20 à 30 min (temps cible).

**Contexte technique** : le portail utilise le compte de service GitLab `svc-portail` (jeton dans `kv/plateforme/portail`, propriété `gitlab_token`, livré par l'ExternalSecret `portail`) ; le modèle `nouveau-service` vit dans `plateforme/portail-modeles` et est relu par le catalogue. Pour essayer sans rien créer de durable, lance le modèle sur un nom fictif (`medidoc-essai-inc5522`) et supprime ensuite ce qu'il a créé (projet, MR).

**Injection** : `lab/bin/break 28 22` (3 variantes).

**Travail demandé**
1. Constate : relance le modèle sur le nom fictif, lis le journal de la tâche dans le portail (étape en échec, message), et les journaux du backend (`{namespace="portail"} |= "<taskId>"`).
2. Selon le message : jeton (ExternalSecret, version du secret dans OpenBao, appel direct à l'API GitLab avec le jeton du Secret **sans l'afficher**), droits de `svc-portail` dans les groupes concernés, historique de `plateforme/portail-modeles` et entité `Template` dans le catalogue.
3. Corrige à la source, puis supprime ce que tes essais ont créé.
4. Vérifie : le modèle crée de nouveau un service fictif de bout en bout ; `lab/bin/check 28 22`.
5. Écris le runbook **RB-288** « Le portail ne crée plus de services » (`docs/plateforme-dev/runbooks/RB-288-*.md`), dont la rotation du jeton de `svc-portail`.

**Critères de réussite**
- [ ] L'ExternalSecret du portail est synchronisé avec un jeton valide ; `svc-portail` a dans les groupes des équipes le rôle que le modèle exige.
- [ ] Le modèle `nouveau-service` du catalogue n'utilise que des actions enregistrées ; aucun projet ni aucune MR d'essai ne traîne.
- [ ] RB-288 est publié.

**Vérification** : `lab/bin/check 28 22`

<details><summary>Indice 1</summary>

Dans le journal d'une tâche, l'étape qui échoue dit déjà beaucoup : une étape `publish:gitlab` en `401 Unauthorized` n'est pas la même panne qu'en `403 Forbidden`, ni qu'un échec **avant** la première étape (*Template action with ID … is not registered*).
</details>

<details><summary>Indice 2</summary>

Pour tester le jeton sans l'exposer : `kubectl -n portail get secret <secret> -o jsonpath='{.data.<CLÉ>}' | base64 -d | curl -s -o /dev/null -w '%{http_code}\n' -H @<(printf 'PRIVATE-TOKEN: %s\n' "$(cat)") https://git01.par1.medisphere.internal/api/v4/user`. Pour les droits : `GET /groups/<groupe>/members/all` avec ton jeton. Pour le modèle : `git log -p` de `plateforme/portail-modeles` et l'entité `Template` dans le catalogue (onglet « Source » ou API).
</details>

**Pour aller plus loin** (facultatif) : ajoute au dépôt des modèles une CI qui valide chaque modèle (schéma, actions utilisées) avant fusion, et une alerte sur le taux d'échec des tâches du *scaffolder* (métriques de E16).

---

### M28-E23 — Astreinte : un locataire sature le cluster  `BF` `★★★★`

> **Ticket INC-5523** — *De : Nadia Roussel* — *Copie : Claire Morel*
> *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Mener un incident de capacité de bout en bout : constat, endiguement, cause, correction, retour à la normale, post-mortem.
- Relier les symptômes dispersés (CPU d'un nœud, conteneurs tués en boucle, recette poussive, alertes de plusieurs équipes) à une seule charge et à son locataire.
- Utiliser les leviers de la plateforme (budget du locataire, classes de priorité, `LimitRange`, isolement de la charge) au lieu de redémarrer au hasard.

**Prérequis** : M28-E14, M28-E15, M28-E19 à M28-E22 (pannes closes) ; `lab/bin/check 28 23` vert avant l'injection.
**Durée indicative** : 1 h 30 à 2 h, post-mortem compris.

**Contexte technique** : le tableau « Capacité et locataires » (E14), Prometheus, Loki, Hubble, `kubectl top`. L'incident se déclare pendant la journée ; plusieurs équipes se plaignent en même temps. Tu es seul d'astreinte, Karim est joignable pour une décision.

**Injection** : `lab/bin/break 28 23` (une variante ; l'injection prend jusqu'à 10 minutes).

> ⚠️ **Attention** : tant que l'incident dure, un travailleur porte une charge CPU qu'il n'a pas prévue et la recette peut en souffrir. Endigue d'abord, enquête ensuite. Si le lab devient inutilisable, `lab/bin/break 28 23 --annuler` arrête tout (sans défaire ce que tu as déjà réparé).

**Travail demandé**
1. **Constat (10 min).** Ce qui est touché (applications, nœuds, alertes), depuis quand, et qui l'a signalé ; ouvre ton journal d'incident.
2. **Endiguement.** Trouve la charge responsable et arrête la dégradation par le geste le plus petit et le plus réversible ; prends la décision avec Karim si elle touche une équipe (écris-la).
3. **Cause.** Pourquoi cette charge a-t-elle pu faire ça : ses `requests` et `limits` effectives, sa classe de priorité, ce que le locataire, l'espace et les politiques d'admission auraient dû empêcher (budget, quota, `LimitRange`, Kyverno), qui l'a lancée, qui a changé quoi et par quel chemin.
4. **Correction durable** par le code : ce qui manquait dans le locataire, l'espace ou les politiques — demande-toi si remettre les choses « comme avant » aurait suffi à empêcher l'incident. La charge de l'équipe, si elle est légitime, doit pouvoir tourner **dans son cadre** (classe `lot`, requests et limites justes, budget).
5. **Retour à la normale** : plus aucun pod évincé ni en attente anormalement, nœuds sans pression, applications de recette de nouveau dans leur SLO.
6. **Post-mortem** `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-5523.md` (sans reproche : chronologie, impact, détection, cause, ce qui a bien marché, ce qui a manqué, actions avec propriétaire et date) et runbook **RB-289** « Un locataire sature le cluster » (`docs/plateforme-dev/runbooks/RB-289-*.md`).

**Critères de réussite**
- [ ] La charge responsable ne tourne plus hors de son cadre (requests non nulles et limites déclarées, classe `medisphere-lot`, ou arrêtée) ; aucun conteneur de `medidoc-dev` tué par manque de mémoire depuis 15 minutes ; aucun nœud en pression mémoire.
- [ ] Le locataire responsable n'autorise pas `medisphere-critique` ; chacun de ses espaces a un `LimitRange`, et celui de `medidoc-dev` refuse un conteneur qui déclare une request nulle ; son budget global est en place.
- [ ] Le post-mortem INC-5523 et RB-289 sont publiés.

**Vérification** : `lab/bin/check 28 23`

<details><summary>Indice 1</summary>

Commence large : `kubectl top nodes`, `kubectl top pods -A --sort-by=cpu | head`, `kubectl get pods -A | grep -v ' 0 '` (redémarrages), `kubectl describe node` (conditions et `Allocated resources` : compare ce qui est **réservé** à ce qui est **consommé** sur le nœud chaud). Le tableau de bord de capacité montre quel locataire a bougé.
</details>

<details><summary>Indice 2</summary>

L'ordonnanceur place les pods d'après leurs `requests`, pas d'après leur consommation : une charge qui déclare zéro « tient » partout. Regarde `resources` **effectives** du pod (ce qu'un `LimitRange` ou Capsule y a mis, ou pas), `spec.priorityClassName`, et relis la politique Kyverno du M26 qui « exige des requests » : que vérifie-t-elle exactement ? Et un `LimitRange` : quand ses valeurs par défaut s'appliquent-elles ?
</details>

<details><summary>Indice 3</summary>

Endiguer, c'est souvent réduire l'effectif de la charge fautive à 0 (`kubectl scale`) après accord, en le notant : ce n'est pas la correction. La correction est dans `plateforme/k8s` (locataire, espace), dans `plateforme/politiques` si une règle d'admission était trop lâche, et dans le dépôt de l'équipe pour relancer sa charge (requests, classe). Demande-toi aussi pourquoi aucune alerte n'a prévenu **avant** les évictions.
</details>

**Pour aller plus loin** (facultatif) : rejoue l'incident avec un essai de charge du M29 en classe `lot` et vérifie qu'il attend son tour sans rien évincer.

---

### M28-E24 — Sous le capot : la boucle de l'HPA, les métriques externes et les webhooks de Capsule  `LAB` `★★★★`

> **Ticket PLAT-2924** — *De : Karim Benali*
> Tu as réparé l'autoscaling et les locataires à l'aveugle quatre fois cette semaine. Je veux que tu saches **exactement** ce qui se passe : le calcul de l'HPA à la virgule près, le chemin d'une métrique de RabbitMQ jusqu'à l'HPA, et ce que voient les webhooks de Capsule quand une équipe crée quelque chose. Note tout dans `sous-le-capot.md` : c'est la page que l'astreinte lira à 3 h du matin.

**Objectifs pédagogiques**
- Refaire à la main le calcul de l'HPA : formule, tolérance, fenêtre de stabilisation, politiques et `selectPolicy`, pods non prêts et métriques manquantes.
- Suivre une métrique externe : `APIService` `v1beta1.external.metrics.k8s.io` → Service de l'adaptateur de KEDA → gRPC vers l'opérateur → scaler → RabbitMQ, et les journaux de chaque étage.
- Observer les webhooks d'admission de Capsule : quels objets ils interceptent, avec quelle politique d'échec, et ce qu'ils reçoivent (`-v=8`, journaux de l'API).

**Prérequis** : M28-E13, M28-E19 à M28-E21 ; M14 (plan de contrôle, journaux de l'API).
**Durée indicative** : 2 h.

**Contexte technique**
- Documentation : *Horizontal Pod Autoscaling* (section *Algorithm details*, *Configurable scaling behavior*), *KEDA Metrics Server* (`keda.sh/docs/2.21/operate/metrics-server/`), *Dynamic Admission Control*.
- Les drapeaux du `kube-controller-manager` qui gouvernent l'HPA se lisent dans `/etc/kubernetes/manifests/kube-controller-manager.yaml` des nœuds de contrôle (valeur par défaut si absents : à lire dans la référence de la commande).
- `kubectl -v=8` affiche les requêtes HTTP et leurs réponses (sans les jetons) ; `kubectl get --raw` interroge directement une API agrégée.

**Travail demandé**
1. **L'HPA à la main.** En recette, sous une charge stable de MédiAgenda, relève à un instant donné les valeurs que voit l'HPA (`kubectl get hpa mediagenda -o yaml` : `status.currentMetrics`, `status.desiredReplicas`) et l'utilisation CPU de chaque pod (`kubectl top pods`, `requests`). Recalcule `desiredReplicas` (formule, arrondi, tolérance par défaut ou de ton comportement). Fais varier la charge pour observer un cas « dans la tolérance : rien ne bouge » et un cas de descente retenue par la fenêtre de stabilisation ; explique chacun avec les chiffres.
2. **Comportement.** Pour le comportement de E13 (MédiNotif), décris ce que donnent `selectPolicy: Max` en montée et `Min` en descente sur un exemple chiffré ; dis ce que ferait `selectPolicy: Disabled` et qui l'utilise (indice : une annotation de KEDA).
3. **Chemin d'une métrique externe.** Suis-la, étage par étage, avec la preuve de chacun : `kubectl get apiservice v1beta1.external.metrics.k8s.io -o yaml` (Service visé, condition `Available`) ; `kubectl get --raw /apis/external.metrics.k8s.io/v1beta1` ; la requête de la métrique du `ScaledObject` ; journaux de l'adaptateur et de l'opérateur au moment de la requête ; la requête faite à l'API de gestion de RabbitMQ (journaux de l'opérateur en verbosité accrue **en recette seulement** si nécessaire, puis retour à la normale). Pourquoi ne peut-il y avoir qu'**un seul** fournisseur de métriques externes dans un cluster ?
4. **Webhooks de Capsule.** Liste les configurations de webhooks de Capsule et, pour chacun : ressources et opérations interceptées, `failurePolicy`, `namespaceSelector`/`objectSelector`, délai. Crée (en `--dry-run=server`, avec l'impersonation de E21) un espace de l'équipe MédiDoc avec `kubectl -v=8` et retrouve dans les journaux de l'API (journal d'audit du M14, ou `kubectl -n kube-system logs kube-apiserver-…`) l'appel au webhook ; mesure la latence ajoutée (`apiserver_admission_webhook_admission_duration_seconds`). Lesquels de ces webhooks bloqueraient la production s'ils ne répondaient plus ?
5. **Écris** `docs/plateforme-dev/sous-le-capot.md` : calculs, schéma du chemin de la métrique externe, tableau des webhooks de Capsule, et les trois commandes qu'on lance en premier à 3 h du matin.

**Critères de réussite**
- [ ] L'`APIService` des métriques externes est servi par KEDA et `Available`.
- [ ] `sous-le-capot.md` est sur `main` de `plateforme/medisphere` avec au moins un calcul d'HPA chiffré, le chemin de la métrique externe et le tableau des webhooks de Capsule (politique d'échec comprise).
- [ ] La verbosité des journaux de KEDA est revenue à sa valeur normale.

**Vérification** : `lab/bin/check 28 24`

<details><summary>Indice 1</summary>

`desiredReplicas = ceil[currentReplicas × (currentMetricValue / desiredMetricValue)]`, sauf si le rapport est dans la tolérance (0,1 par défaut) ; les pods sans métrique sont comptés de façon conservatrice (à 100 % de la cible en descente, à 0 % en montée) et les pods pas encore prêts sont mis de côté, puis comptés à 0 % s'il s'agit de monter. En descente, l'HPA prend la recommandation **la plus haute** de la fenêtre de stabilisation.
</details>

<details><summary>Indice 2</summary>

L'`APIService` désigne un Service (`spec.service`) : c'est par lui que l'agrégateur de l'API relaie la requête. L'adaptateur de KEDA ne calcule rien : il demande la valeur à l'opérateur (gRPC), qui tient les scalers. Le nom d'une métrique externe (`s0-rabbitmq-…`) encode l'index du déclencheur.
</details>

<details><summary>Indice 3</summary>

`kubectl get validatingwebhookconfigurations -o json | jq -r '.items[] | select(.metadata.name | test("capsule")) | .webhooks[] | [.name, .failurePolicy, (.rules | map(.resources | join(",")) | join(";"))] | @tsv'` dresse le tableau. Un webhook en `Fail` sur les pods des espaces de locataire bloque la création de **tout** pod de ces espaces quand il ne répond plus.
</details>

**Pour aller plus loin** (facultatif) : lis le code de calcul de l'HPA (`pkg/controller/podautoscaler/replica_calculator.go` de Kubernetes 1.36) et retrouve la tolérance et le traitement des pods non prêts.
