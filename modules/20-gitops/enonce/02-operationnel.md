# Module 20 — Palier 2 : Opérationnel

Le palier 1 a installé Argo CD, créé les comptes, le dépôt `plateforme/gitops` et son application racine, les AppProjects, et repris `mediagenda-dev` sans coupure. Ce palier en fait l'outil du quotidien : **un seul gabarit** pour les trois environnements de MédiAgenda (ApplicationSet), des synchronisations **ordonnées** (vagues, migrations de schéma par hook), ce qu'Argo CD doit **laisser à d'autres** (champs écrits par des contrôleurs, Secrets), les charts tiers **recopiés et signés** dans Harbor, la **promotion** par MR de dev à la prod et le retour arrière, puis les **déploiements progressifs** avec Argo Rollouts (canary par la Gateway API, blue/green, analyses automatiques) et les **notifications**. Tu termines en relisant les Applications de Lucas, en écrivant le runbook « application OutOfSync ou Degraded » et en refaisant le même déploiement avec **Flux**, pour comparer.

> **Rappels du module** (introduction) : Argo CD applique `main` des dépôts qu'il suit ; on ne corrige **jamais** un objet géré à la main (l'auto-réparation le remettrait). La couche de base du cluster, Argo CD compris, reste sous **Helmfile** (`plateforme/k8s`, `helmfile -e par1 -l composant=<nom> diff|apply`) ; tout le reste passe par **`plateforme/gitops`** (MR, fusion par les Maintainers). Les Secrets ne sont **jamais** dans Git : `plateforme/k8s/outils/secrets-k8s.sh appliquer <composant>` depuis le Vault `critique`. Les commandes partent de `adm01` (`admin@adm01:~$`), avec ton compte local Argo CD (connexion de la CLI comme en E03) et ton kubeconfig personnel.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Argo CD | 3.5.5 (chart `argo/argo-cd` 10.10.5), release Helmfile `argocd`, valeurs `plateforme/k8s/composants/argocd/values.yaml` ; diff côté serveur actif pour toutes les Applications (E05, `controller.diff.server.side`) ; interface `https://argocd.apps.par1.medisphere.internal` |
| Dépôt `plateforme/gitops` (clone `~/src/gitops`) | `racine/` (Applications `racine`, `applications`, `projets`, et `plateforme` à partir d'E15), `projets/` (AppProjects `plateforme`, `mediagenda`, `medidoc`, `labo`, `default` verrouillé), `applications/` (Applications et ApplicationSets des équipes), `plateforme/` (une Application par service de plateforme, E15). Chaque dossier est lu **sans récursion** (`*.yaml`) : les valeurs de charts vont dans `valeurs/<service>/`, jamais lu par la racine |
| MédiAgenda | dépôt `mediagenda/deploiement` (clone `~/src/mediagenda-deploiement`) : `base/` (rendu commité du chart `mediagenda` 0.5.0, `outils/rendre-base.sh`), `components/` (`dependances`, `debogage`, `haute-disponibilite`, `livraison`), `overlays/dev|recette|prod` ; image `registry.par1.medisphere.internal/medisphere/mediagenda-api` désignée par **digest** (`images:` de l'overlay, M19-E17) et version lisible dans `overlays/<env>/livraison.yaml` ; espaces `mediagenda-dev`, `mediagenda-recette`, `mediagenda-prod` (créés par `plateforme/k8s`) ; objets `mediagenda` (Deployment, Service port 80 → `http`/8000, HTTPRoute sur `gw-par1`), base CNPG `mediagenda-db` (dev et prod dans l'overlay, recette gérée par `plateforme/k8s`) |
| Applications de MédiAgenda | `mediagenda-dev` (E08, synchro automatique), puis `mediagenda-recette` et `mediagenda-prod` (E10) dans le projet `mediagenda` |
| Banc d'essai | dépôt `formation/gitops-labo` (clone `~/src/gitops-labo`), dossier `k8s/` (Deployment, Service, ConfigMap `labo-page`, `kustomization.yaml`), Application `labo` (projet `labo`) dans `wb-essais` |
| Charts tiers | `oci://registry.par1.medisphere.internal/charts` (projet Harbor `charts`, M17), recopiés par **`plateforme/charts-miroir`** (E13, clone `~/src/charts-miroir`) ; dans une Application, `repoURL: registry.par1.medisphere.internal/charts` (sans `oci://`) |
| Argo Rollouts (E15) | contrôleur 1.10.1 (chart 2.43.8), espace `argo-rollouts`, Application `argo-rollouts` (projet `plateforme`) ; greffon `argoproj-labs/gatewayAPI` **0.17.0** ; outil `kubectl argo rollouts` sur `adm01` |
| Images | toutes par Harbor : caches `dockerhub`, `quay`, `ghcr`, `k8s` ; épinglées par digest pour les outils de la plateforme |
| Messagerie | Mailpit sur `mon01` : SMTP `smtp.par1.medisphere.internal:25` (STARTTLS), interface `https://mon01.par1.medisphere.internal:8025` (M19-E03) ; adresses `plateforme@`, `astreinte@`, `julien.petit@medisphere.internal` |
| Flux (E23) | VM 2202 `flux01` (10.10.99.62, `vsandbox`), état OpenTofu `envs/m20`, rôle Ansible `k3s` du M18 ; Flux **2.9.6** ; dépôt `formation/flux-labo` |
| Documentation | `plateforme/medisphere` (clone `~/medisphere`) : `docs/livraison/gitops/` (`promotion.md`, RB-200, `comparatif-flux.md`) ; brouillons dans `~/m20/eXX/` sur `adm01` |

> 💡 **Lire avant d'écrire.** Pour un ApplicationSet, `argocd appset generate <fichier>` montre les Applications qu'il **produirait**, sans rien créer. Pour une Application, `argocd app diff <app>` et `argocd app manifests <app>` montrent l'écart et le rendu. Prends le réflexe : on ne fusionne pas une MR GitOps sans avoir lu ce qu'elle va changer.

Durée indicative du palier : 27 à 33 heures. Ordre conseillé (E15 dépend d'E13 ; E16 d'E12 et E15) :

```
E10 ─ E11 ─ E12 ─ E13 ─ E14
                   └─── E15 ─ E16 ─ E18
                          └── E17
E19 (après E14)   E20 (quand tu veux)   E21, E22 (après E19)   E23 (en dernier : VM temporaire)
```

> ⚠️ **Mémoire.** E23 démarre la VM `flux01` (2 Go). Ne la lance pas en même temps qu'un autre composant temporaire (PLAN §4.11 ; `lyo-k3s01` arrive en E26).

---

### M20-E10 — ApplicationSets : un générateur pour trois environnements  `LAB` `★★★`

> **Ticket PLAT-2110** — *De : Karim Benali*
> Dev tourne sous Argo CD depuis la semaine dernière. Pour la recette et la prod, je ne veux pas trois fichiers recopiés qui divergeront au premier changement : un seul gabarit, trois environnements, et la prod **jamais** synchronisée sans un humain. Deux exigences de ma part : l'Application de dev ne doit pas être supprimée puis recréée (on vient de la reprendre sans coupure, ce n'est pas pour tout casser), et supprimer le gabarit par erreur ne doit rien supprimer dans le cluster.

**Objectifs pédagogiques**
- Écrire un ApplicationSet (générateur liste, gabarits Go, `templatePatch`) et lire ce qu'il produit avant de l'appliquer.
- Comprendre les politiques de modification (`applicationsSync`) et de suppression (`preserveResourcesOnDeletion`, finaliseurs) des Applications générées.
- Faire **adopter** une Application existante par un ApplicationSet, sans suppression ni recréation des charges.
- Reprendre la recette et la prod (déployées à la main au M17) sous Argo CD.

**Prérequis** : M20-E08 (Application `mediagenda-dev`), M20-E07 (projet `mediagenda`, espace `mediagenda-prod` repris par la plateforme).
**Durée indicative** : 3 h.

**Contexte technique**
- Fichier à créer : `applications/mediagenda.yaml` dans `plateforme/gitops` (ApplicationSet `mediagenda`, espace `argocd`). Il **remplace** `applications/mediagenda-dev.yaml` (E08).
- Applications générées : `mediagenda-dev`, `mediagenda-recette`, `mediagenda-prod` ; projet `mediagenda` ; source `https://git01.par1.medisphere.internal/mediagenda/deploiement.git`, branche `main`, dossier `overlays/<env>` ; destination `https://kubernetes.default.svc`, espace `mediagenda-<env>` ; étiquettes `medisphere.internal/equipe: mediagenda` et `medisphere.internal/environnement: <env>`.
- Synchronisation : `dev` et `recette` automatiques (`prune`, `selfHeal`), `prod` **manuelle** ; partout `ServerSideApply=true`, `CreateNamespace=false`, et des réessais bornés.
- Le contrôleur des ApplicationSets d'Argo CD n'applique la politique propre à chaque ApplicationSet que si un paramètre l'y autorise : cherche lequel dans la page *Controlling Resource Modification* de la documentation (il se règle dans les valeurs Helmfile de la release `argocd`).
- La recette et la prod ont été appliquées à la main au M17 (`kubectl apply --server-side -k`) : les objets existent, avec leurs gestionnaires de champs. Méthode de reprise : celle d'E08.

**Travail demandé**
1. Lis *Generators* (List, Git), *Go Template*, *Template Patch*, *Controlling Resource Modification* et *Application Pruning & Resource Deletion* de la documentation des ApplicationSets. Dans `~/m20/e10/journal.md` : que fait le contrôleur, par défaut, d'une Application dont l'élément disparaît du générateur ? Et quand on supprime l'ApplicationSet lui-même ? Quel finaliseur pose-t-il sur les Applications, et quand ne le pose-t-il pas ? Pourquoi `templatePatch` est-il nécessaire pour rendre `automated` conditionnel ?
2. Choisis le générateur (liste ou répertoires Git sur `overlays/*`) et justifie ton choix dans le journal en pensant à ce qui arriverait si quelqu'un ajoutait un dossier `overlays/essai`.
3. Fais autoriser la politique par ApplicationSet (MR sur `plateforme/k8s`, `helmfile -e par1 -l composant=argocd diff`, puis `apply`). Vérifie dans `argocd-cmd-params-cm` et constate le redémarrage du contrôleur des ApplicationSets.
4. Écris l'ApplicationSet (politique `create-update`, `preserveResourcesOnDeletion`). Avant toute MR : `argocd appset generate applications/mediagenda.yaml -o yaml`, et compare l'Application `mediagenda-dev` produite à celle qui tourne (`argocd app get mediagenda-dev -o yaml`, champ par champ : `spec`, étiquettes, annotations, finaliseurs). Tout écart dans `spec` déclencherait une modification de l'Application à l'adoption : décide lesquels sont voulus.
5. Prépare l'adoption de `mediagenda-dev` (E08) : l'Application `applications` (E06) supprime ce qui disparaît de son dossier (`prune`). Vérifie que `mediagenda-dev` n'a **pas** de finaliseur `resources-finalizer.argocd.argoproj.io`, puis protège-la d'une suppression par l'Application `applications` pendant le passage de témoin (MR 1). Explique dans le journal ce qui se passerait sans cette précaution, avec et sans finaliseur.
6. MR 2 : ajoute `applications/mediagenda.yaml`, retire `applications/mediagenda-dev.yaml`. Avant la fusion, `argocd app diff mediagenda-dev` doit être vide et tu notes le nom et l'âge du ReplicaSet de l'API en dev (`kubectl get rs -n mediagenda-dev`). Après la fusion : l'Application `mediagenda-dev` a-t-elle changé de propriétaire (`metadata.ownerReferences`) ? Ses pods ont-ils été recréés ?
7. Recette et prod n'ont jamais été gérées par Argo CD : on lit avant d'appliquer. Fais d'abord générer `mediagenda-recette` **sans** synchronisation automatique (élément `recette` provisoirement comme `prod`) ; elle apparaît `OutOfSync` sans rien appliquer. Lis `argocd app diff mediagenda-recette`, synchronise à la main quand le diff ne contient que ce que tu attends, puis passe-la en synchronisation automatique (MR). Même lecture pour `mediagenda-prod`, synchronisée à la main (`argocd app sync mediagenda-prod`). Note dans le journal les écarts rencontrés et leur cause.
8. Essai de sûreté : dans une branche, retire l'élément `prod` de la liste et lance `argocd appset generate` ; écris ce que ferait le contrôleur avec ta politique, puis avec la politique par défaut. N'applique pas.

**Critères de réussite**
- [ ] L'ApplicationSet `mediagenda` existe (`create-update`, `preserveResourcesOnDeletion`) et le contrôleur prend en compte sa politique.
- [ ] Les trois Applications sont générées par lui (propriétaire), sans finaliseur de suppression en cascade ; dev et recette synchronisées automatiquement, Synced et Healthy ; prod sans synchronisation automatique et Healthy.
- [ ] `applications/mediagenda-dev.yaml` n'est plus dans `plateforme/gitops` ; le ReplicaSet de l'API en dev est le même qu'avant l'adoption.
- [ ] Le journal répond aux questions des étapes 1, 2, 5, 7 et 8.

**Vérification** : `lab/bin/check 20 10`

<details><summary>Indice 1</summary>

Le contrôleur des ApplicationSets **adopte** une Application existante qui porte le même nom : il réécrit son `spec`, ses étiquettes et ses annotations (sauf quelques-unes qu'il préserve), et se déclare propriétaire. Il ne la supprime pas. Ce qui peut la supprimer, c'est l'Application `applications`, qui la suit encore par son annotation de suivi tant qu'elle ne l'a pas perdue.
</details>

<details><summary>Indice 2</summary>

Une option de synchronisation se pose aussi **sur une ressource**, par annotation : `argocd.argoproj.io/sync-options`. Cherche celle qui interdit la suppression d'un objet par `prune`. Et relis les annotations que l'ApplicationSet préserve (`argocd.argoproj.io/tracking-id` n'en fait pas partie) : quand il adopte l'Application, que devient son lien avec `applications` ?
</details>

<details><summary>Indice 3</summary>

Dans `templatePatch`, le texte est d'abord un gabarit Go, puis un correctif YAML : un `{{- if .auto }}` mal placé peut produire un `spec:` vide, qui **efface** des champs du gabarit. Garde toujours au moins un champ dans le bloc que tu patches.
</details>

**Pour aller plus loin** (facultatif) : le générateur `matrix` (environnements × clusters) et le *Progressive Sync* des ApplicationSets (`strategy: RollingSync`), qui synchronise les Applications par vagues d'étiquettes. Pourquoi ne remplace-t-il pas une promotion par MR ?

---

### M20-E11 — Vagues et hooks de synchronisation  `LAB` `★★★`

> **Ticket DEV-2111** — *De : Julien Petit*
> Vos conteneurs d'initialisation de migration me gênent : chaque pod rejoue les migrations, et si une migration casse, on s'en rend compte quand les nouveaux pods ne démarrent pas, pendant que l'ancienne version continue avec un schéma à moitié migré. Je voudrais que la migration passe **une fois**, **avant** que la nouvelle version ne soit déployée, et que tout s'arrête si elle échoue. Et en dev, quand on reconstruit l'environnement, que la base existe avant qu'on essaie d'y migrer quoi que ce soit.

**Objectifs pédagogiques**
- Ordonner une synchronisation : phases (`PreSync`, `Sync`, `PostSync`, `SyncFail`), vagues (`argocd.argoproj.io/sync-wave`), attente de santé entre vagues.
- Écrire un hook Argo CD (Job) et choisir sa politique de suppression.
- Savoir comment Argo CD traite les hooks **Helm** quand il applique un rendu qui en contient.

**Prérequis** : M20-E10 ; M17-E12 (migrations par hook Helm) ; apps/mediagenda/README.md (commande de migration, verrou consultatif).
**Durée indicative** : 2 h 30.

**Contexte technique**
- La commande de migration : `python -m mediagenda.migrate` (image de l'API), répertoire `/app/migrations`, variable `MEDIAGENDA_DB_URL` lue dans le Secret `mediagenda-db-app` (clé `uri`, créé par CloudNativePG). Elle est idempotente et prend un verrou consultatif.
- Aujourd'hui : `base/values-communes.yaml` rend le chart avec `migrations.mode: initContainer` (conteneur `migrations` dans chaque pod) ; le chart sait aussi `hook` (Job Helm) et `none`.
- Le Job s'appellera `mediagenda-migrate`, dans un nouveau component `components/migrations` de `mediagenda/deploiement`, inclus par les **trois** overlays. Ordre voulu : ConfigMaps, compte de service et politiques réseau → base CNPG et Valkey (là où l'overlay les apporte) → migration → API.
- Le component `livraison` fixe l'image du conteneur `migrations` par un remplacement : il devra viser le Job à la place.

**Travail demandé**
1. Lis *Sync Phases and Waves* et *Resource Hooks* (dont *Hook deletion policies* et *Helm hooks*) de la documentation d'Argo CD. Dans `~/m20/e11/journal.md` : dans quel ordre Argo CD applique-t-il les objets d'une synchronisation ? Qu'attend-il avant de passer à la vague suivante ? Un hook `PreSync` passe-t-il avant ou après la vague -2 ? Que devient un objet rendu avec l'annotation `helm.sh/hook: pre-upgrade` quand Argo CD l'applique depuis un rendu Kustomize ?
2. Raisonne sur dev : la base `mediagenda-db` est dans l'overlay. Que se passerait-il, sur un `mediagenda-dev` reconstruit de zéro, avec une migration en `PreSync` ? Choisis la phase et la vague du Job, et écris pourquoi.
3. Écris `components/migrations/` : le Job (étiquettes qui lui donnent l'accès réseau à la base, compte de service sans jeton, Pod Security `restricted`, quotas : requêtes et limites), la politique de suppression qui garde le dernier Job lisible jusqu'à la synchronisation suivante, et les annotations de vagues des autres objets (sans écraser les annotations qu'ils ont déjà).
4. Passe `migrations.mode` à `none`, relance `outils/rendre-base.sh` (le rendu ne doit plus contenir de conteneur d'initialisation), adapte le component `livraison` et le garde-fou `outils/verifier-livraison.sh` (il doit contrôler l'image du Job), et inclus `migrations` dans les trois overlays, au bon endroit de la liste. `kubectl kustomize overlays/<env>` doit réussir pour les trois ; montre avec `yq` que l'image du Job suit celle de l'API.
5. MR, fusion. Suis la synchronisation de dev puis de recette dans l'interface (onglet *Sync status* de la dernière opération) et en ligne de commande (`argocd app get mediagenda-recette -o json | jq '.status.operationState.syncResult.resources[] | select(.hookType)'`). Relève l'ordre réel des objets.
6. Échec provoqué, en **dev** seulement. Les fichiers de migration sont dans l'image : on provoque l'échec par l'environnement du Job. Dans une MR, un correctif de l'overlay `dev` remplace la `MEDIAGENDA_DB_URL` du Job par une URL vers une base qui n'existe pas, **et** change un paramètre anodin de l'API (`MEDIAGENDA_CACHE_TTL`) pour que la synchronisation ait quelque chose à déployer après le hook. Fusionne et observe : la synchronisation s'arrête-t-elle avant le Deployment ? Quelle version, avec quels paramètres, sert l'API pendant ce temps ? Que disent `kubectl logs job/mediagenda-migrate -n mediagenda-dev` et l'opération dans Argo CD ? Reviens en arrière par `git revert` (MR).
7. Dans le journal : avantages et limites de ce hook par rapport au conteneur d'initialisation et au hook Helm du M17 (rejeu, observabilité, retour arrière d'une migration, compatibilité du schéma entre deux versions).

**Critères de réussite**
- [ ] La dernière synchronisation de `mediagenda-recette` a réussi et a exécuté le hook `mediagenda-migrate` (phase `Sync`) avec succès.
- [ ] Le gabarit de pod de l'API n'a plus de conteneur d'initialisation de migration ; le component `migrations` (Job en vague -1, autres objets en vagues -3 et -2) figure dans les trois overlays ; `base/values-communes.yaml` dit `migrations.mode: none`.
- [ ] `mediagenda-dev` est revenue Synced et Healthy après l'échec provoqué.
- [ ] Le journal répond aux étapes 1, 2, 6 et 7.

**Vérification** : `lab/bin/check 20 11`

<details><summary>Indice 1</summary>

Un patch `JSON 6902` qui fait `add` sur `/metadata/annotations/<clé>` échoue si l'objet n'a pas encore de `metadata.annotations`. Un correctif stratégique (*strategic merge*) avec une `target` fusionne au contraire l'annotation dans ce qui existe, sur chaque objet visé.
</details>

<details><summary>Indice 2</summary>

Kustomize refuse un remplacement (`replacements`) dont le chemin cible n'existe pas (`unable to find field … in replacement target`) : retirer le conteneur d'initialisation sans changer `livraison` casse le rendu des trois overlays.
</details>

<details><summary>Indice 3</summary>

Les hooks d'une phase `Sync` prennent place dans les vagues comme les autres objets. Pour l'état sain d'un `Job`, Argo CD attend sa fin ; pour un `Cluster` CNPG, il a une vérification de santé intégrée (`Cluster in healthy state`).
</details>

**Pour aller plus loin** (facultatif) : le hook `SyncFail` (un Job joué quand la synchronisation échoue : message, nettoyage) et l'annotation `argocd.argoproj.io/sync-options: Delete=false` ; et pourquoi une migration **destructive** (suppression de colonne) ne se fait jamais dans la même version que le code qui cesse de s'en servir.

---

### M20-E12 — Ce qu'Argo CD ne doit pas gérer : différences ignorées et Secrets hors Git  `LAB` `★★★`

> **Ticket PLAT-2112** — *De : Karim Benali*
> Deux sujets avant Argo Rollouts. Un : le canary va faire bouger les poids de la route de MédiAgenda et les réplicas de son Deployment ; je ne veux pas qu'Argo CD passe son temps à « corriger » ce que le contrôleur fait exprès. Deux : je veux être certain qu'aucun Secret ne traîne dans les dépôts qu'Argo CD lit, et que ceux dont MédiAgenda a besoin sont créés par nos outils, pas par quelqu'un qui colle un YAML.
>
> *Commentaire de Sophie Laurent* : et qu'on ne « simplifie » pas en ignorant des pans entiers des objets. Ce qu'on ignore, je veux pouvoir le lire en une ligne.

**Objectifs pédagogiques**
- Reconnaître qui écrit un champ (`managedFields`) et choisir entre corriger le dépôt, ignorer un champ, ou laisser le diff côté serveur absorber une valeur par défaut.
- Écrire des `ignoreDifferences` **ciblés** (groupe, type, nom, chemin `jsonPointers` ou `jqPathExpressions`) et `RespectIgnoreDifferences=true`.
- Utiliser les options de comparaison (`IgnoreExtraneous`, `IncludeMutationWebhook`) et les exclusions de ressources.
- Garder les Secrets hors de Git, créés par `secrets-k8s.sh`, et le vérifier.

**Prérequis** : M20-E11 ; M14-E20 (metrics-server).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Banc : `labo` reçoit un HorizontalPodAutoscaler `labo` (2 à 4 pods, 70 % de CPU), fichier `k8s/hpa.yaml` de `formation/gitops-labo`.
- MédiAgenda, recette et prod : à partir d'E16, le greffon Gateway API d'Argo Rollouts **réécrira les poids** des `backendRefs` de l'HTTPRoute `mediagenda`, et le Rollout réduira le Deployment `mediagenda` à 0 réplica. Ces deux champs se préparent ici, dans le gabarit de l'ApplicationSet (recette et prod seulement).
- Le diff côté serveur est actif pour toutes les Applications depuis E05 ; les webhooks de **mutation** (CloudNativePG en a un, qui complète `Cluster`) n'y participent que sur demande.
- Secrets de MédiAgenda : `harbor-pull` (tirage des images, robot `robot$k8s-pull`) dans chaque espace, créé jusqu'ici par l'outil du M14 ; `mediagenda-db-app` (CNPG). Composants à ajouter à `secrets-k8s.sh` : `mediagenda-dev`, `mediagenda-recette`, `mediagenda-prod` (modules `outils/secrets-k8s.d/`, comme `argocd` en E06), Vault `secrets/mediagenda-<env>.yml`.
- Exclusions de ressources : `configs.cm.resourceExclusionsAdditional` du chart (ajoute à la liste par défaut au lieu de la remplacer).

**Travail demandé**
1. Lis *Diffing Customization* (`ignoreDifferences`, `managedFieldsManagers`, `RespectIgnoreDifferences`), *Diff Strategies* (diff côté serveur, webhooks de mutation), *Compare Options* et *Resource Exclusion*. Dans `~/m20/e12/journal.md` : que fait `ignoreDifferences` **seul** lors d'une synchronisation ? Pourquoi `RespectIgnoreDifferences=true` ? Quelle est la différence entre ignorer un champ et ignorer une ressource extérieure (`IgnoreExtraneous`) ?
2. **HPA sur labo.** Ajoute `k8s/hpa.yaml` (requêtes CPU présentes dans le gabarit de pod ?), MR, fusion. Fais monter la charge (`kubectl run` d'un générateur de requêtes vers le Service `labo`, dans `wb-essais`) jusqu'à ce que le HPA change le nombre de pods. Que montre `argocd app get labo` ? Qui a écrit `spec.replicas` (`kubectl get deploy labo -n wb-essais --show-managed-fields -o yaml`) ? Que se passe-t-il avec `selfHeal` ?
3. Corrige l'Application `labo` (`applications/labo.yaml`) au plus juste. Vérifie qu'après une synchronisation manuelle (`argocd app sync labo`) le nombre de pods choisi par le HPA n'est pas remis à la valeur du dépôt. Arrête la charge.
4. **MédiAgenda.** Ajoute au gabarit de l'ApplicationSet, pour la recette et la prod seulement, les deux différences à ignorer d'E16 et l'option qui les respecte à la synchronisation ; pour les trois environnements, l'option de comparaison qui fait participer les webhooks de mutation. `argocd appset generate` avant la MR ; après, les trois Applications restent Synced.
5. **Valeur par défaut d'un webhook** : dans le journal, explique ce qu'Argo CD montrerait sur le `Cluster` `mediagenda-db` de dev si les webhooks de mutation ne participaient pas au diff (essaie : `argocd app diff mediagenda-dev --server-side-diff`, en retirant temporairement l'option dans une branche… ou raisonne à partir de `kubectl get cluster mediagenda-db -n mediagenda-dev -o yaml` comparé au fichier du component `dependances`).
6. **ConfigMaps générées.** En prod (synchro manuelle, sans `prune` systématique), chaque changement de `parametres.env` laisse l'ancienne ConfigMap `mediagenda-parametres-<empreinte>`. Fais en sorte que ces restes ne rendent pas l'Application `OutOfSync`, sans les cacher aux autres Applications. Où pose-t-on l'annotation, et pourquoi pas sur l'Application ?
7. **Exclusions** : ajoute aux valeurs de la release `argocd` l'exclusion des objets que Velero crée par milliers (sauvegardes, restaurations, téléversements), en gardant la liste par défaut du chart. `helmfile diff`, puis `apply`. Écris dans le journal pourquoi on n'exclut jamais un type décrit dans Git.
8. **Secrets.** Écris les modules `mediagenda-dev`, `mediagenda-recette`, `mediagenda-prod` de `secrets-k8s.sh` (Secret `harbor-pull` de type `kubernetes.io/dockerconfigjson`, jeton jamais en argument), les fichiers du Vault, lance `appliquer` puis `verifier` sur les trois. Puis cherche dans les trois dépôts suivis par Argo CD (`mediagenda/deploiement`, `plateforme/gitops`, `formation/gitops-labo`, **tout l'historique**) le moindre objet `kind: Secret` : `git log -p --all -S 'kind: Secret'` dans chaque clone. Note le résultat.

**Critères de réussite**
- [ ] `mediagenda-recette` et `mediagenda-prod` ignorent les poids de l'HTTPRoute `mediagenda` et les réplicas du Deployment `mediagenda`, et rien d'autre ; `RespectIgnoreDifferences=true` ; `mediagenda-dev` n'ignore rien. Les trois font participer les webhooks de mutation au diff et sont Synced.
- [ ] Le HPA `labo` existe ; l'Application `labo` ignore uniquement `spec.replicas` de la charge qu'il pilote, avec `RespectIgnoreDifferences=true`, et reste Synced.
- [ ] `argocd-cm` garde les exclusions par défaut et exclut les objets créés par Velero.
- [ ] Aucun `kind: Secret` sur `main` des trois dépôts suivis ; les pods de l'API sont prêts dans les trois espaces (Secrets créés hors Git).

**Vérification** : `lab/bin/check 20 12`

<details><summary>Indice 1</summary>

`jsonPointers` ne sait pas dire « le champ `weight` de **chaque** élément d'une liste » ; `jqPathExpressions` le sait (`.spec.rules[].backendRefs[]?.weight`). Pour les réplicas, un pointeur suffit.
</details>

<details><summary>Indice 2</summary>

Une ConfigMap produite par `configMapGenerator` peut recevoir des annotations par les options du générateur (`options.annotations`). Cherche l'option de comparaison qui dit « cet objet, s'il est en trop, ne compte pas ».
</details>

<details><summary>Indice 3</summary>

Un Secret encodé en base64 n'est pas chiffré : `echo … | base64 -d`. Et `git rm` n'efface pas un Secret de l'historique : s'il a été poussé, il est compromis — c'est sa **rotation** qui règle le problème, pas sa suppression.
</details>

**Pour aller plus loin** (facultatif) : `ignoreDifferences` au niveau du **système** (`resource.customizations.ignoreDifferences.<groupe>_<type>` dans `argocd-cm`) : quand est-ce préférable à un réglage par Application, et pourquoi est-ce dangereux pour un type aussi courant que `Deployment` ?

---

### M20-E13 — Helm et Kustomize dans Argo CD, sources multiples  `LAB` `★★`

> **Ticket PLAT-2113** — *De : Claire Morel*
> Argo Rollouts, puis la supervision au M21 : on va installer des composants tiers par Argo CD. Règle de Sophie, que je reprends : rien ne vient d'Internet au moment du déploiement. Les charts tiers sont recopiés chez nous, à une version relue, contrôlés et signés, et Argo CD ne lit que Harbor. Je veux le mécanisme avant le premier composant.

**Objectifs pédagogiques**
- Mettre en place un miroir de charts tiers vérifié (empreinte relue en MR, recopie OCI, signature Cosign) dans un pipeline planifié.
- Déclarer un dépôt Helm OCI privé dans Argo CD et l'autoriser dans un AppProject.
- Écrire une Application à sources multiples (chart OCI + valeurs Git, `ref` et `$values`).
- Comparer le rendu par Argo CD d'un chart à un rendu commité (ADR-0170) et savoir lequel garder pour quoi.

**Prérequis** : M20-E12 ; M17-E08 et E13 (projet Harbor `charts`, robots, signature d'un chart) ; M19-E24 (runner protégé).
**Durée indicative** : 3 h.

**Contexte technique**
- Projet à créer : **`plateforme/charts-miroir`** (`charts.yaml`, `.gitlab-ci.yml`, `outils/`, `README.md`). Chaque entrée de `charts.yaml` : `nom`, `depot` (amont), `version` exacte, `empreinte` (SHA-256 de l'archive `.tgz` amont), `usage`. Premier chart : `argo-rollouts` **2.43.8** (dépôt `https://argoproj.github.io/argo-helm`).
- Pipeline : contrôle de `charts.yaml` sur chaque MR ; recopie (`helm pull`, contrôle d'empreinte, `helm push` vers `oci://registry.par1.medisphere.internal/charts`) et signature (`cosign sign` du **digest**, configuration de signature sans service, M13) sur `main` et sur un pipeline **planifié** hebdomadaire, sur le runner **protégé** (étiquette `protege`). Images de jobs par les caches Harbor, épinglées par digest : `dockerhub/alpine/helm:4.3.0`, `dockerhub/mikefarah/yq:4.53.6`, et l'image outillée `plateforme/outils-supply-chain` (M13-E09).
- Harbor : robot de projet `robot$charts+miroir` (push + pull sur `charts`, 180 jours), à créer comme les robots du M17 ; Argo CD lira avec `robot$charts+lecture` (M17-E13).
- Argo CD : dépôt de type `helm` avec `enableOCI`, URL `registry.par1.medisphere.internal/charts` ; Secret créé par `secrets-k8s.sh appliquer argocd` (module `secrets-k8s.d/argocd.sh` d'E06, clé `argocd_harbor_charts` du Vault). La racine MédiSphère est déjà déclarée pour `registry.par1.medisphere.internal` dans `argocd-tls-certs-cm` (E02).
- Essai de sources multiples : Application `essai-multisources` (projet `plateforme`), chart `mediagenda` 0.5.0 de Harbor + valeurs copiées dans `plateforme/gitops` (`valeurs/essai-multisources/values.yaml`), créée à la main (`argocd app create -f`), **jamais synchronisée**, supprimée à la fin.

**Travail demandé**
1. Relève l'empreinte de l'archive `argo-rollouts-2.43.8.tgz` de deux façons (champ `digest` de l'`index.yaml` du dépôt amont ; `helm pull` puis `sha256sum`). Elles doivent coïncider : note-les dans `~/m20/e13/journal.md`.
2. Crée `plateforme/charts-miroir` et son pipeline. Contraintes : aucun secret dans le dépôt ; le robot d'écriture et la clé Cosign ne sont visibles que des jobs du runner protégé ; un chart déjà présent dans Harbor n'est ni republié ni re-signé ; une empreinte différente arrête tout **avant** la poussée.
3. Essai rouge : dans une MR, change un caractère de l'empreinte. Quel job échoue, avec quel message ? (Le job de recopie ne tourne pas sur une MR : comment as-tu vérifié ce cas ? Tu peux lancer le script de recopie en local avec un faux `helm push`, ou dans un pipeline de branche protégée de test.) Annule.
4. Après fusion : vérifie le chart dans Harbor (projet `charts`, dépôt `argo-rollouts`, étiquette `2.43.8`, référent de signature) et `cosign verify` du digest avec la clé publique MédiSphère. Crée la planification hebdomadaire du pipeline.
5. Déclare le dépôt dans Argo CD (Vault, module `argocd`, `secrets-k8s.sh appliquer argocd` puis `verifier`) et autorise-le dans l'AppProject `plateforme` (MR sur `plateforme/gitops`). `argocd repo list` : état `Successful` ?
6. Essai multi-sources : écris `essais/essai-multisources.yaml` et `valeurs/essai-multisources/values.yaml` (copie de `base/values-communes.yaml`), crée l'Application à la main, puis compare `argocd app manifests essai-multisources` au rendu commité `base/rendu/mediagenda.yaml` (normalise l'ordre : `yq` ou `kubectl kustomize`). Note les écarts et leur raison dans le journal. Supprime l'Application (`argocd app delete essai-multisources`) : qu'a-t-elle supprimé dans le cluster ?
7. Dans le journal : pour **MédiAgenda**, garde-t-on le rendu commité (ADR-0170) ou passe-t-on à une Application Helm multi-sources ? Et pour un **composant tiers** comme Argo Rollouts ? Trois arguments de chaque côté (relecture en MR, hooks, signature vérifiée, dépendance au repo-server, diff lisible).

**Critères de réussite**
- [ ] `plateforme/charts-miroir` : `charts.yaml` (argo-rollouts 2.43.8, empreinte), pipeline de `main` réussi, recopie et signature sur le runner protégé, pipeline planifié actif.
- [ ] `charts/argo-rollouts:2.43.8` est dans Harbor, signé (référent Cosign).
- [ ] Le dépôt OCI de Harbor est déclaré dans Argo CD, joignable, autorisé dans l'AppProject `plateforme` (et rien d'Internet).
- [ ] `essai-multisources` a été comparée puis supprimée ; le journal note la comparaison des rendus et la décision de l'étape 7.

**Vérification** : `lab/bin/check 20 13`

<details><summary>Indice 1</summary>

L'image `alpine/helm` n'a ni bash ni yq. Sépare le travail : un job « lister » (image de yq) contrôle `charts.yaml` et en tire un fichier tabulé passé en artefact ; le job de recopie (image de Helm) le lit en `sh`. `helm push` et `helm pull` depuis un registre OCI affichent une ligne `Digest: sha256:…`.
</details>

<details><summary>Indice 2</summary>

Une Application à sources multiples a `spec.sources` (au pluriel). La source qui porte `ref: values` ne produit aucun manifeste : elle donne seulement un nom à son dépôt, utilisable sous la forme `$values/<chemin>` dans les `valueFiles` d'une autre source. Le projet doit autoriser les **deux** `repoURL`.
</details>

<details><summary>Indice 3</summary>

Quand Argo CD rend un chart, il convertit les hooks Helm en hooks Argo CD et ne fait jamais `helm install` : `helm list -A` ne verra aucune release. Les tests Helm (`helm.sh/hook: test`) ne sont pas des hooks pour lui.
</details>

**Pour aller plus loin** (facultatif) : *Source Integrity*, qui remplace la vérification GnuPG en 3.5 : que sait-elle vérifier aujourd'hui, et le ferait-elle sur un chart OCI signé par Cosign ? Et Renovate (M13) sur `charts.yaml`, pour proposer les montées de version par MR.

---

### M20-E14 — Promouvoir une version de dev à la production, et revenir en arrière  `LAB` `★★`

> **Ticket PLAT-2114** — *De : Julien Petit*
> La CI ouvre maintenant une MR en dev à chaque version, c'est parfait. Mais pour passer en recette puis en prod, on recopie des digests à la main, on se trompe d'overlay, et la semaine dernière quelqu'un a mis en recette une version qui n'était jamais passée en dev. Il nous faut un geste simple, toujours le même, qui ne permette pas de sauter une étape. Et on doit savoir revenir en arrière en deux minutes quand la prod va mal.

**Objectifs pédagogiques**
- Promouvoir un **artefact** (même digest, même signature) d'un environnement au suivant par MR, sans reconstruire.
- Outiller la promotion pour la rendre répétable et sûre (ordre des environnements, signature vérifiée, rendu contrôlé).
- Revenir en arrière par Git (`git revert`) et comprendre pourquoi `argocd app rollback` ne convient pas à un environnement en synchronisation automatique.

**Prérequis** : M20-E10 ; M19-E17 (promotion vers dev par la CI), M19-E29 (vérification des signatures dans le pipeline de MR de `deploiement`).
**Durée indicative** : 2 h.

**Contexte technique**
- Dans chaque overlay : bloc `images:` de `kustomization.yaml` (entrée `registry.par1.medisphere.internal/medisphere/mediagenda-api`, champs `newTag` et `digest`, forme posée par la CI en M19-E17) et `data.version` de `livraison.yaml`. Les trois bougent **ensemble** : le garde-fou `outils/verifier-livraison.sh` (M17-E21, adapté en M19-E17) exige `newTag` = version de `livraison.yaml` et un digest.
- Script à écrire : `outils/promouvoir.sh <source> <cible>` dans `mediagenda/deploiement`. Chemins permis : `dev → recette`, `recette → prod`. Il vérifie la signature Cosign du digest (clé publique `~/medisphere/docs/registre/cosign.pub`, sans journal de transparence, M13), crée la branche `promotion/<cible>-<version>`, committe et ouvre la MR. Les MR sont fusionnées par un Maintainer (Julien Petit, Karim Benali) **autre** que leur auteur.
- GitLab sait ouvrir une MR au moment du `git push` (options `-o merge_request.create`, `-o merge_request.target=…`, `-o merge_request.title=…`).
- Livrable : `docs/livraison/gitops/promotion.md` dans `plateforme/medisphere`.

**Travail demandé**
1. Relis la dernière MR de promotion de la CI en dev : quelles lignes change-t-elle exactement ? Vérifie la signature du digest qu'elle a posé (`cosign verify … --insecure-ignore-tlog=true <image>@<digest>`).
2. Écris `outils/promouvoir.sh` : refus d'un chemin non permis, d'une copie de travail modifiée ou d'un `main` pas à jour, d'un digest absent ou non signé ; rien à faire si la cible livre déjà ce digest ; contrôle du rendu de la cible (`kubectl kustomize`, puis le garde-fou `verifier-livraison`) : l'API **et** le Job de migration portent `vX.Y.Z@<digest promu>`, `MEDIAGENDA_VERSION` suit. La MR ne doit montrer que les lignes qui changent (attention : `kustomize edit set image` réécrit tout le fichier). `shellcheck` propre.
3. Promotion en recette : `outils/promouvoir.sh dev recette`, fusion par un Maintainer, synchronisation automatique. Vérifie la version servie : `curl -s https://mediagenda-recette.apps.par1.medisphere.internal/sante`.
4. Promotion en prod : `outils/promouvoir.sh recette prod`, fusion. `mediagenda-prod` passe `OutOfSync` : lis `argocd app diff mediagenda-prod`, puis `argocd app sync mediagenda-prod`. Que montre `argocd app history mediagenda-prod` ?
5. Retour arrière **en recette** : on suppose que la version promue pose problème. Essaie d'abord `argocd app rollback mediagenda-recette <ID>` : que répond Argo CD ? Coupe la synchronisation automatique (`argocd app set mediagenda-recette --sync-policy none`) et observe l'Application une minute : que fait l'ApplicationSet ? Puis fais le retour par Git : `git revert -m 1 <commit de fusion>` dans une branche, MR, fusion. Mesure le temps entre ta décision et la version précédente servie.
6. Re-promeus la version en recette (le problème est « corrigé »), puis rédige `docs/livraison/gitops/promotion.md` : principe, qui fait quoi à chaque étape, garde-fous, retour arrière (et pourquoi pas `argocd app rollback`), ce qui ne revient **pas** en arrière (les migrations de schéma), où lire l'état. MR.

**Critères de réussite**
- [ ] Les trois overlays désignent l'image de l'API par un digest et portent une version `vX.Y.Z` ; `outils/promouvoir.sh` est sur `main`.
- [ ] Au moins une promotion vers la recette et une vers la prod ont été fusionnées par MR (branches `promotion/…`), chacune par un autre que son auteur ; un `Revert "…"` figure sur `main`.
- [ ] `mediagenda-prod` est Synced et Healthy, toujours sans synchronisation automatique ; `mediagenda-recette` a gardé la sienne.
- [ ] `promotion.md` est publié et décrit le retour arrière par revert.

**Vérification** : `lab/bin/check 20 14`

<details><summary>Indice 1</summary>

`yq` (mikefarah) sait modifier un fichier en place sans toucher au reste (`yq -i`), et lire une variable d'environnement dans une expression (`strenv(NOM)`) : c'est plus sûr que d'interpoler une valeur dans l'expression.
</details>

<details><summary>Indice 2</summary>

Le commit à annuler est la **fusion** de la MR de promotion (deux parents) : `git revert` a besoin de savoir quel parent est la « ligne principale » (`-m 1`). `git log --first-parent --oneline -- overlays/recette` montre les fusions qui ont touché la recette.
</details>

**Pour aller plus loin** (facultatif) : lis la présentation de Kargo (promotion par « étapes » et « freight ») : qu'apporterait-il à MédiSphère, et que perdrait-on par rapport à une MR lue par un humain ?

---

### M20-E15 — Argo Rollouts : installer et premier canary  `LAB` `★★`

> **Ticket PLAT-2115** — *De : Karim Benali*
> On installe Argo Rollouts, premier composant de plateforme géré par Argo CD et non par Helmfile. Le chart vient de notre miroir. Point délicat : le canary par la Gateway passe par un greffon que le contrôleur **télécharge** au démarrage, et le cluster ne sort pas vers GitHub. Trouve une solution propre, écris-la, et fais un premier canary sur `labo` avant de toucher à MédiAgenda.

**Objectifs pédagogiques**
- Installer un service de plateforme par une Application Argo CD (chart OCI du miroir, valeurs dans Git, CRD en *server-side apply*).
- Comprendre comment Argo Rollouts charge un greffon (`trafficRouterPlugins` : `https://` avec empreinte, ou `file://`) et le fournir sans accès Internet.
- Convertir un Deployment en Rollout, conduire un canary par réplicas avec `kubectl argo rollouts` (`get --watch`, `promote`, `abort`, `retry`).

**Prérequis** : M20-E13 (chart `argo-rollouts` 2.43.8 dans Harbor, dépôt OCI dans Argo CD), M20-E12 (HPA `labo`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Versions : contrôleur Argo Rollouts **1.10.1** (chart 2.43.8, image `quay.io/argoproj/argo-rollouts:v1.10.1`, par le cache `quay`) ; greffon `rollouts-plugin-trafficrouter-gatewayapi` **0.17.0**, nom de greffon `argoproj-labs/gatewayAPI`. Le projet du greffon publie un binaire par architecture et une **image** `ghcr.io/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi:v0.17.0` (binaire `/bin/rollouts-plugin-trafficrouter-gatewayapi`, utilisateur 999).
- Espace `argo-rollouts` créé par la plateforme (`plateforme/k8s`, `espaces/argo-rollouts.yaml`, Pod Security `restricted`).
- Dans `plateforme/gitops` : Application `plateforme/argo-rollouts.yaml` (projet `plateforme`), valeurs `valeurs/argo-rollouts/values.yaml`, Application de groupe `racine/plateforme.yaml` (lit le dossier `plateforme/`, comme `applications` lit `applications/`), destination `argo-rollouts` ajoutée au projet `plateforme`.
- Les checks lisent les objets d'Argo Rollouts : étends `rbac/wb-checks-livraison.yaml` de `plateforme/k8s` (lecture des `rollouts`, `analysisruns`, `analysistemplates`, `clusteranalysistemplates`, `experiments` du groupe `argoproj.io`).
- Outil : `kubectl-argo-rollouts` 1.10.1 sur `adm01` (rôle `outils_k8s`, binaire nu comme `argocd` en E03 ; empreinte dans `argo-rollouts-checksums.txt` de la version).

**Travail demandé**
1. Lis *Installation* (dont *Plugins*) d'Argo Rollouts et la page *Installation* du greffon Gateway API. Dans `~/m20/e15/journal.md` : quand le contrôleur charge-t-il ses greffons ? Que vérifie-t-il pour un emplacement `https://` avec `sha256`, et pour `file://` ? (Le code est court : `utils/plugin/downloader.go`, étiquette `v1.10.1`.) Que se passe-t-il au démarrage si le greffon est introuvable ?
2. **Tranche** : comment le contrôleur obtient-il le binaire, sachant que le cluster ne sort pas vers GitHub ? Compare au moins trois solutions (image du greffon par le cache Harbor `ghcr` et conteneur d'initialisation ; binaire servi en HTTPS depuis un serveur interne avec `sha256` ; image maison construite par la CI) : intégrité, mise à jour, dépendances réseau et TLS, effort. Écris ta décision et sa justification dans le journal ; elle ira dans l'ADR-0200 (E31).
3. Prépare la plateforme : espace (MR `plateforme/k8s`, `task appliquer`), extension de `wb-checks-livraison`, `kubectl-argo-rollouts` (MR `plateforme/ansible`, rôle joué sur `adm01`).
4. Écris les valeurs (images par Harbor et épinglées par digest, deux contrôleurs, ressources, greffon selon ta décision, droits du contrôleur sur les HTTPRoute, rien de superflu), l'Application (sources multiples comme en E13) et le groupe `racine/plateforme.yaml`. Rends le chart en local (`helm template … -f valeurs/argo-rollouts/values.yaml`) et lis la ConfigMap `argo-rollouts-config` et le Deployment produits avant la MR.
5. Après fusion : Application Synced et Healthy ; pods du contrôleur prêts ; journal du contrôleur (`kubectl logs -n argo-rollouts deploy/argo-rollouts | grep -i plugin`) : le greffon est-il chargé ?
6. **Canary sur labo** : convertis le Deployment `labo` en Rollout (même gabarit de pod, stratégie canary par réplicas : 25 %, pause sans durée, 50 %, 75 %), le HPA vise désormais le Rollout, et `applications/labo.yaml` ignore les réplicas du Rollout. La bascule recrée les pods de `labo` (banc : coupure acceptée ; on fera mieux pour MédiAgenda). Puis livre une nouvelle version de l'image de labo (par exemple `nginx-unprivileged` 1.30.6 → 1.31.7, par le cache Harbor) et conduis le canary : `kubectl argo rollouts get rollout labo -n wb-essais --watch`, `promote`. Fais-en un second, interromps-le (`abort`) : que devient l'Application `labo` dans Argo CD (santé, synchronisation) ? Comment en sortir proprement ?

**Critères de réussite**
- [ ] Application `argo-rollouts` (projet `plateforme`, chart de Harbor à version exacte, valeurs de `plateforme/gitops`, `ServerSideApply=true`) Synced et Healthy ; contrôleur prêt, images de Harbor épinglées par digest.
- [ ] `argo-rollouts-config` déclare `argoproj-labs/gatewayAPI` chargé sans accès Internet ; la décision est écrite dans le journal.
- [ ] `wb-checks` lit les objets d'Argo Rollouts ; `kubectl argo rollouts` 1.10 est sur `adm01`.
- [ ] Le Rollout `labo` a livré au moins une révision en canary, il est Healthy, la dernière révision est promue ; il n'y a plus de Deployment `labo` ; le HPA vise le Rollout.

**Vérification** : `lab/bin/check 20 15`

<details><summary>Indice 1</summary>

Le chart d'Argo Rollouts accepte des conteneurs d'initialisation, des volumes et des montages supplémentaires pour le contrôleur (`controller.initContainers`, `controller.volumes`, `controller.volumeMounts`), et recopie `controller.trafficRouterPlugins` dans `argo-rollouts-config`.
</details>

<details><summary>Indice 2</summary>

Sous Pod Security `restricted`, chaque conteneur d'initialisation doit déclarer lui aussi `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` et un profil seccomp : le chart n'applique pas son `containerSecurityContext` aux conteneurs que tu ajoutes.
</details>

<details><summary>Indice 3</summary>

Après un `abort`, le Rollout est `Degraded` tant que son gabarit désigne la version interrompue : soit on la relance (`kubectl argo rollouts retry rollout`), soit on remet l'ancienne version **dans Git**.
</details>

**Pour aller plus loin** (facultatif) : le tableau de bord d'Argo Rollouts (`kubectl argo rollouts dashboard`, en local) et l'extension d'Argo CD qui affiche les Rollouts dans son interface.

---

### M20-E16 — Canary piloté par la Gateway API  `LAB` `★★★`

> **Ticket DEV-2116** — *De : Julien Petit*
> En recette, je veux voir une nouvelle version recevoir 10 % du trafic, puis 25, puis 50, avant de tout prendre. En prod, pareil, mais la dernière marche, c'est un humain qui la franchit. Contrainte de Karim : on ne réécrit pas le chart, et la reprise ne coupe pas le service.

**Objectifs pédagogiques**
- Reprendre un Deployment existant sous un Rollout sans coupure (`workloadRef`, réduction progressive).
- Router un canary par la Gateway API (greffon, Services stable et canary, HTTPRoute à deux `backendRefs`).
- Faire cohabiter Argo CD et Argo Rollouts sur les mêmes objets (champs ignorés d'E12) ; régler une fenêtre de retour arrière.

**Prérequis** : M20-E15, M20-E12 (différences ignorées), M20-E14 (promotion).
**Durée indicative** : 3 h.

**Contexte technique**
- Component à créer dans `mediagenda/deploiement` : `components/canary/` (Rollout `mediagenda`, Service `mediagenda-canary`, correctif de l'HTTPRoute `mediagenda`), inclus par les overlays `recette` et `prod`, avant `livraison`. Dev n'en a pas.
- Rollout : `workloadRef` vers le Deployment `mediagenda` (`scaleDown: progressively`), même sélecteur que le Deployment et le PDB du chart, 2 réplicas en recette et 3 en prod ; canary avec `stableService: mediagenda`, `canaryService: mediagenda-canary`, routage par le greffon `argoproj-labs/gatewayAPI` sur l'HTTPRoute `mediagenda` ; marches `setWeight` 10, 25, 50 séparées de pauses de 2 min ; en prod, une dernière pause **sans durée**. Fenêtre de retour arrière de deux révisions.
- Au repos, l'HTTPRoute envoie 100 % au Service `mediagenda` (poids 100) et 0 % au Service `mediagenda-canary` (poids 0).
- Le transformateur `replicas:` de Kustomize ne connaît pas le type `Rollout`.
- La recette et la prod ont chacune une version promue en E14 ; pour un canary, il faut une **autre** version : promeus la suivante (ou une version précédente encore dans Harbor), toujours par `outils/promouvoir.sh`.

**Travail demandé**
1. Lis *Migrating to Rollouts* (`workloadRef`), *Canary* (`trafficRouting`, `setWeight`, `maxSurge`), *Rollback Windows* d'Argo Rollouts, et la page *Quick start* du greffon. Dans `~/m20/e16/journal.md` : quand le Rollout est créé, crée-t-il ses pods par des marches ? Que fait-il du Deployment avec `progressively` ? Qui modifie quoi dans les Services et l'HTTPRoute ? Qu'est-ce qu'Argo CD verrait, sans les réglages d'E12 ?
2. Écris le component et l'inclusion dans `overlays/recette` (MR 1, recette seulement). Avant la MR : `kubectl kustomize overlays/recette`, `kubectl argo rollouts lint -f -` (que vérifie-t-il, que ne voit-il pas avec un `workloadRef` ?), `argocd app diff mediagenda-recette --local …` ou lecture du rendu.
3. Pendant la synchronisation, en parallèle : une boucle `curl` sur `https://mediagenda-recette.apps.par1.medisphere.internal/sante` toutes les 0,5 s (`~/m20/e16/sonde.sh`, qui compte les codes ≠ 200). Suis `kubectl argo rollouts get rollout mediagenda -n mediagenda-recette --watch` et `kubectl get deploy,rs,pods -n mediagenda-recette`. Combien d'erreurs ? Que devient le Deployment ?
4. Premier vrai canary en recette : promotion d'une autre version (E14). Observe, à chaque marche : les poids de l'HTTPRoute (`kubectl get httproute mediagenda -n mediagenda-recette -o yaml`), les sélecteurs des deux Services, la répartition mesurée par ta boucle (`/sante` renvoie la version), l'état de l'Application dans Argo CD. Laisse aller au bout.
5. Retour arrière : `git revert` de cette promotion (MR). Combien de temps ? Le Rollout a-t-il refait les marches ? Pourquoi ?
6. MR 2 : la prod (component, 3 réplicas, dernière pause sans durée). Synchronisation manuelle, sonde en parallèle sur `https://mediagenda.apps.par1.medisphere.internal/sante`. Puis une promotion en prod, conduite jusqu'à la pause finale, et `kubectl argo rollouts promote mediagenda -n mediagenda-prod`. Quelle est la santé de `mediagenda-prod` dans Argo CD pendant la pause ?

**Critères de réussite**
- [ ] Recette : Rollout `mediagenda` (`workloadRef`, `progressively`, greffon Gateway API sur l'HTTPRoute `mediagenda`, Services stable et canary, marches 10/25/50 avec pauses), au moins une révision livrée en canary, Healthy, dernière révision promue ; Deployment à 0 réplica.
- [ ] HTTPRoute `mediagenda` : deux `backendRefs`, 100/0 au repos, acceptée par `gw-par1` ; `mediagenda-recette` Synced et Healthy.
- [ ] Prod : Rollout à 3 réplicas avec une dernière marche en promotion manuelle, Healthy.
- [ ] `sonde.sh` et ses résultats (reprise et canary) sont dans `~/m20/e16/`.

**Vérification** : `lab/bin/check 20 16`

<details><summary>Indice 1</summary>

Un `replace` sur `/spec/rules/0/backendRefs` remplace toute la liste du rendu par tes deux entrées : c'est plus sûr que deux `add` (l'ordre et les poids sont alors explicites). Les filtres d'en-têtes de sécurité posés par la base (`/spec/rules/0/filters`) ne sont pas touchés.
</details>

<details><summary>Indice 2</summary>

Le Rollout fabrique ses pods à partir du gabarit du Deployment : étiquettes, sondes, `imagePullSecrets`, sécurité, tout est repris. Le PDB, la CiliumNetworkPolicy de la Gateway et les Services sélectionnent par étiquettes : ils s'appliquent aussi aux pods du Rollout.
</details>

<details><summary>Indice 3</summary>

Pour ajouter une marche à la fin d'une liste par un correctif JSON 6902, le chemin se termine par `/-` : pas besoin de connaître le nombre de marches (et il changera en E18).
</details>

**Pour aller plus loin** (facultatif) : le routage par en-tête du greffon (`setHeaderRoute`) pour envoyer au canary les seules requêtes de l'équipe de Julien, avant tout pourcentage.

---

### M20-E17 — Blue/green avec aperçu et promotion manuelle  `LAB` `★★`

> **Ticket PLAT-2117** — *De : Nadia Roussel*
> Pour certains changements (une montée de version de bibliothèque, un changement de configuration risqué), je préfère le blue/green : la nouvelle version complète à côté de l'ancienne, je la regarde, et on bascule d'un coup quand on est sûr, avec la possibilité de revenir aussitôt. Montre-le-moi sur `labo`.

**Objectifs pédagogiques**
- Écrire une stratégie blue/green (`activeService`, `previewService`, `autoPromotionEnabled`, `scaleDownDelaySeconds`).
- Brancher une analyse avant la bascule (`prePromotionAnalysis`) avec un gabarit **de cluster** livré par la plateforme.
- Comparer canary et blue/green (coût en pods, trafic, retour arrière).

**Prérequis** : M20-E15.
**Durée indicative** : 1 h 30.

**Contexte technique**
- `labo` (Rollout d'E15) passe en stratégie `blueGreen` : Service actif `labo` (existant), Service d'aperçu `labo-apercu` (même sélecteur et même port que `labo`, à créer dans `k8s/`), promotion manuelle, ancienne révision gardée 2 min après la bascule.
- Gabarit d'analyse de cluster `pret-http` (`ClusterAnalysisTemplate`, argument `url`, trois mesures `web` à 10 s d'intervalle, succès si 2xx), livré **avec** Argo Rollouts : objets supplémentaires du chart (`extraObjects` de `valeurs/argo-rollouts/values.yaml`).
- La mesure `web` est faite par le contrôleur lui-même, depuis l'espace `argo-rollouts`.

**Travail demandé**
1. Lis *BlueGreen Deployment Strategy* et *Analysis & Progressive Delivery* (*BlueGreen Pre Promotion Analysis*, *ClusterAnalysisTemplates*). Dans `~/m20/e17/journal.md` : combien de pods pendant un blue/green de `labo` (avec son HPA) ? Que fait `scaleDownDelaySeconds` ? Que se passe-t-il si l'analyse d'aperçu échoue ?
2. Ajoute `pret-http` aux valeurs d'Argo Rollouts (MR sur `plateforme/gitops`). Rends le chart en local avant : que se passe-t-il, et pourquoi ? Corrige.
3. Passe `labo` en blue/green (MR sur `formation/gitops-labo`). Livre une nouvelle version : regarde `kubectl argo rollouts get rollout labo -n wb-essais --watch`, interroge l'aperçu (`kubectl -n wb-essais port-forward svc/labo-apercu 8081:80`, puis `curl -sI localhost:8081` : en-tête `Server`), l'analyse (`kubectl get analysisrun -n wb-essais`), puis `promote`. Mesure la bascule (boucle sur le Service actif).
4. Retour arrière immédiat dans les 2 minutes : `kubectl argo rollouts undo labo -n wb-essais`. Que devient Git ? Argo CD ? Fais ensuite le retour **dans Git** pour que les deux disent la même chose.
5. Échec d'aperçu provoqué : livre une version dont l'aperçu ne répond pas en 2xx (par exemple une `ConfigMap labo-page` qui casse la page servie, ou une image absente du cache… choisis et explique). La bascule a-t-elle lieu ? Rétablis.

**Critères de réussite**
- [ ] Rollout `labo` en `blueGreen` (`activeService: labo`, `previewService: labo-apercu`, `autoPromotionEnabled: false`, `prePromotionAnalysis` avec le gabarit de cluster `pret-http`) ; Service `labo-apercu` présent.
- [ ] `pret-http` existe (livré par l'Application `argo-rollouts`).
- [ ] Une analyse `pret-http` a réussi avant une promotion ; le Rollout est Healthy, la révision active est la révision courante.

**Vérification** : `lab/bin/check 20 17`

<details><summary>Indice 1</summary>

Les objets supplémentaires du chart passent par la fonction `tpl` de Helm : les doubles accolades d'Argo Rollouts (`{{args.url}}`) y sont lues comme un gabarit Helm. Il faut les échapper pour que Helm les recopie telles quelles.
</details>

<details><summary>Indice 2</summary>

Un corps de réponse qui n'est pas du JSON (une page HTML) ne peut pas passer par `jsonPath` : pour une mesure `web`, Argo Rollouts considère alors la mesure réussie dès que le code HTTP est 2xx, et en erreur sinon.
</details>

**Pour aller plus loin** (facultatif) : `postPromotionAnalysis` et `abortScaleDownDelaySeconds` ; et un Service d'aperçu publié par une HTTPRoute `labo-apercu.apps.par1.medisphere.internal` pour qu'un humain le teste dans son navigateur.

---

### M20-E18 — Analyses : tests de fumée et requêtes web  `LAB` `★★★`

> **Ticket DEV-2118** — *De : Julien Petit*
> Le canary de recette avance tout seul, mais personne ne regarde pendant les pauses. Je veux qu'il vérifie lui-même : des tests de fumée sur la nouvelle version dès qu'elle reçoit du trafic, et une surveillance de `/pret` pendant tout le canary. Si ça ne va pas, il s'arrête et revient à l'ancienne version, sans nous.

**Objectifs pédagogiques**
- Écrire des AnalysisTemplates : métrique `job` (tests de fumée) et `web` (requête HTTP, `jsonPath`, `successCondition`, `failureLimit`, `consecutiveErrorLimit`).
- Brancher une analyse en marche (bloquante) et une analyse de fond sur un canary ; passer des arguments (`valueFrom.fieldRef`).
- Ouvrir les flux réseau des analyses, et voir un canary s'interrompre seul.

**Prérequis** : M20-E16.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Gabarits de l'équipe, dans `components/canary/` de `mediagenda/deploiement` (donc en recette et en prod) : `fumee-mediagenda` (Job : `/sante`, `/pret`, puis les créneaux d'une date, sur le Service **canary**, image `curlimages/curl:8.23.0` par le cache Harbor `dockerhub`, épinglée par digest) et `pret-mediagenda` (`web` sur `/pret` du Service canary toutes les 20 s ; `/pret` renvoie `{"statut":"pret",…}` ou un 503). Argument `espace` : l'espace du Rollout.
- La métrique `job` crée un Job dans l'espace du Rollout (Pod Security `restricted`, quota, VAP des images) ; la métrique `web` est faite par le **contrôleur**, depuis l'espace `argo-rollouts`.
- La NetworkPolicy `mediagenda` du chart n'admet vers l'API que les pods de la release ; la prod refuse tout par défaut, entrée et sortie (`refus-par-defaut`).
- Les comparaisons de `failureLimit` et `consecutiveErrorLimit` sont **strictes** (le seuil est dépassé à la valeur + 1).

**Travail demandé**
1. Lis *Analysis & Progressive Delivery* (*Background Analysis*, *Inline Analysis*, *Analysis Template Arguments*, *Failure Conditions and Failure Limit*) et les pages *Job* et *Web* des fournisseurs de métriques. Dans `~/m20/e18/journal.md` : différence entre une mesure en **échec** et une mesure en **erreur** ? Que fait un Rollout quand son analyse finit `Failed`, `Error`, `Inconclusive` ?
2. Écris les deux gabarits, branche-les (fumée juste après la marche 10 %, analyse de fond dès la première marche), et les politiques réseau nécessaires (entrée de l'API depuis les pods de fumée et depuis le contrôleur ; sorties des pods de fumée : DNS et API seulement). Reporte les flux dans `docs/kubernetes/reseau/matrice-flux-cluster.md`.
3. Canary en recette avec une nouvelle version (E14) : suis les AnalysisRuns (`kubectl argo rollouts get rollout mediagenda -n mediagenda-recette --watch`, `kubectl get analysisrun,job -n mediagenda-recette`), lis le journal du Job de fumée.
4. **Échec provoqué** : une MR (recette seulement) qui donne au conteneur de l'API une `MEDIAGENDA_VALKEY_URL` pointant vers un Valkey qui n'existe pas (correctif de l'overlay), comme le ferait une mauvaise configuration livrée avec une version. Observe : les pods canary sont-ils prêts ? Que mesure `pret-mediagenda` (échec ou erreur) ? Au bout de combien de temps le Rollout s'interrompt-il ? Que reçoivent les utilisateurs pendant ce temps (ta sonde d'E16) ? Quel est l'état du Rollout et de l'Application ?
5. Rétablis par `git revert` (MR). Le Rollout redevient-il Healthy seul ? Garde la trace de l'AnalysisRun en échec (ne la supprime pas).

**Critères de réussite**
- [ ] AnalysisTemplates `fumee-mediagenda` (Job, image de Harbor épinglée, Service canary) et `pret-mediagenda` (`web` sur `/pret` du Service canary, condition de succès et limites) en recette, branchés sur le Rollout (marche d'analyse et analyse de fond).
- [ ] Une analyse de fumée réussie ; une analyse en `Failed` ou `Error` conservée ; le Rollout revenu Healthy, révision stable = révision courante.
- [ ] La NetworkPolicy d'entrée des analyses admet le Job de fumée et le contrôleur d'Argo Rollouts.

**Vérification** : `lab/bin/check 20 18`

<details><summary>Indice 1</summary>

Une mesure `web` qui reçoit un code hors 2xx, ou aucune réponse, est une **erreur** (pas un échec) : c'est `consecutiveErrorLimit` qui décide, pas `failureLimit`. Un pod canary qui n'est jamais prêt n'est pas derrière le Service canary : la requête échoue.
</details>

<details><summary>Indice 2</summary>

L'image `curlimages/curl` déclare un utilisateur par son **nom** : avec `runAsNonRoot`, le kubelet refuse un utilisateur qu'il ne peut pas vérifier numérique. Donne son UID explicitement.
</details>

<details><summary>Indice 3</summary>

Les arguments d'une analyse peuvent être lus dans le Rollout lui-même : `valueFrom.fieldRef.fieldPath: metadata.namespace`. Un même component sert ainsi la recette et la prod.
</details>

**Pour aller plus loin** (facultatif) : `dryRun` sur une métrique (elle est mesurée sans pouvoir interrompre le Rollout) : utile pour roder un seuil avant de le rendre bloquant. Le M21 ajoutera `taux-erreur-mediagenda` (Prometheus).

---

### M20-E19 — Notifications d'Argo CD  `LAB` `★★`

> **Ticket PLAT-2119** — *De : Nadia Roussel*
> Aujourd'hui, on apprend qu'une synchronisation a échoué quand un développeur vient nous voir. Je veux un courriel à l'astreinte quand une application se dégrade, à l'équipe concernée et à la plateforme quand une synchronisation échoue, et une annonce à chaque mise en production. En français, avec le lien vers le détail, et sans spam.

**Objectifs pédagogiques**
- Configurer le contrôleur de notifications d'Argo CD : service `email`, déclencheurs (`when`, `oncePer`), modèles.
- S'abonner par annotations, au niveau d'un AppProject ou d'une Application (par l'ApplicationSet).
- Faire confiance à une autorité interne pour le STARTTLS du serveur SMTP.

**Prérequis** : M20-E14 ; M19-E03 (Mailpit).
**Durée indicative** : 1 h 30.

**Contexte technique**
- Contrôleur de notifications livré par le chart (déjà actif, sans service ni déclencheur) ; configuration par les valeurs `notifications.*` de la release `argocd` (`notifiers`, `triggers`, `templates`, `argocdUrl`). Le chart n'installe **pas** le catalogue de déclencheurs d'Argo CD : on écrit les siens, en reprenant ses conditions.
- SMTP : `smtp.par1.medisphere.internal:25`, STARTTLS avec un certificat de l'autorité MédiSphère, sans authentification ; expéditeur `argocd@medisphere.internal`. Le contrôleur fait confiance au magasin de certificats du système ; la racine MédiSphère est déjà dans `argocd-tls-certs-cm` (clé `git01.par1.medisphere.internal`). Les programmes Go lisent la variable `SSL_CERT_FILE`.
- Déclencheurs : `on-sync-failed`, `on-health-degraded`, `on-deployed` ; abonnements : projet `mediagenda` (échecs → `plateforme@` et `julien.petit@` ; dégradation → `astreinte@` et `julien.petit@`), projet `plateforme` (échecs → `plateforme@`, dégradation → `astreinte@`), `mediagenda-prod` seule (déploiements → `plateforme@` et `julien.petit@`).
- Le flux `K8S_TRAV` → `mon01` 25 est ouvert depuis M19.

**Travail demandé**
1. Lis *Notifications* (*Triggers*, *Templates*, *Subscriptions*, service *Email*) et le catalogue (`notifications_catalog/` du dépôt d'Argo CD, étiquette `v3.5.5`). Dans `~/m20/e19/journal.md` : rôle de `oncePer` ? Pourquoi `on-deployed` compare-t-il des dates de santé et de fin d'opération ?
2. Écris le service, les trois déclencheurs et trois modèles en français (sujet et corps : application, révision, message d'erreur ou ressources dégradées, lien vers l'interface, numéro du runbook RB-200). MR sur `plateforme/k8s`, `helmfile diff`, `apply`. Vérifie avec `argocd admin notifications template get` et `argocd admin notifications trigger get` (ces commandes lisent la configuration directement dans le cluster, avec ton kubeconfig : `-n argocd`).
3. Abonnements : annotations des AppProjects `mediagenda` et `plateforme`, et de `mediagenda-prod` **seulement** par l'ApplicationSet (`templatePatch`). `argocd appset generate` avant la MR.
4. Essais : envoie d'abord un message à la demande, **depuis le pod du contrôleur** (`kubectl -n argocd exec deploy/argocd-notifications-controller -- argocd admin notifications template notify sante-degradee mediagenda-dev --recipient email:plateforme@medisphere.internal`) ; pourquoi pas depuis `adm01` ? Puis de vrais événements : un échec de synchronisation provoqué en dev (rejoue l'échec du Job de migration d'E11, puis revert ; pourquoi un manifeste invalide ne conviendrait-il pas, avec le diff côté serveur d'E05 ?) ; une mise en production (une promotion en prod, E14). Lis les messages dans Mailpit. Combien de messages par événement ?
5. Si aucun message n'arrive, cherche dans le journal du contrôleur de notifications (`kubectl logs -n argocd deploy/argocd-notifications-controller`) : erreur TLS ? Corrige sans désactiver la vérification du certificat.

**Critères de réussite**
- [ ] `argocd-notifications-cm` : service `email` vers `smtp.par1.medisphere.internal:25` sans `insecure_skip_verify`, expéditeur `@medisphere.internal`, déclencheurs `on-sync-failed`, `on-health-degraded`, `on-deployed`, au moins trois modèles avec sujet ; contrôleur prêt.
- [ ] Abonnements de l'AppProject `mediagenda` (échecs, dégradation) ; `on-deployed` sur `mediagenda-prod` et pas sur la recette.
- [ ] Mailpit a reçu d'Argo CD un message « Échec de synchronisation » et l'annonce d'un déploiement de `mediagenda-prod`.

**Vérification** : `lab/bin/check 20 19`

<details><summary>Indice 1</summary>

Le chart permet d'ajouter des volumes, des montages et des variables d'environnement au contrôleur de notifications (`notifications.extraVolumes`, `notifications.extraVolumeMounts`, `notifications.extraEnv`). Une ConfigMap montée avec `items` ne donne que la clé demandée, sous le nom de fichier choisi.
</details>

<details><summary>Indice 2</summary>

Une annotation d'abonnement porte le déclencheur ET le service dans sa clé (`notifications.argoproj.io/subscribe.<déclencheur>.<service>`) ; plusieurs destinataires se séparent par `;`.
</details>

**Pour aller plus loin** (facultatif) : un service `webhook` vers l'Alertmanager témoin de `mon01` (M21) pour que les échecs de synchronisation deviennent des alertes avec silence et regroupement.

---

### M20-E20 — Questions : stratégies de déploiement  `Q` `★★`

> **Ticket PLAT-2120** — *De : Claire Morel*
> Avant qu'on généralise le canary, je veux que toute l'équipe parle le même langage : qu'est-ce qu'on choisit, quand, et ce que ça coûte. Réponds par écrit, je relirai.

**Objectifs pédagogiques**
- Choisir une stratégie de déploiement selon le risque, le coût et la nature du changement.
- Relier stratégie de déploiement, compatibilité des données et capacité de retour arrière.

**Prérequis** : M20-E15 à M20-E18.
**Durée indicative** : 1 h.

Réponds dans `~/m20/e20/reponses.md`, en argumentant (deux à six phrases par question).

1. *Recreate* et *RollingUpdate* d'un Deployment : quand le premier est-il le **seul** choix correct ? Donne un exemple concret dans les applications de MédiSphère.
2. Un RollingUpdate avec `maxUnavailable: 0` et un PDB `minAvailable: 2` : est-ce un déploiement « progressif » au sens d'Argo Rollouts ? Qu'est-ce qui manque ?
3. Canary **par réplicas** (labo, E15) et canary **par routage** (MédiAgenda, E16) : quelle part du trafic reçoit le canary à `setWeight: 10` avec 2 pods, dans chacun des deux cas ? Conséquence pour une petite application.
4. Blue/green ou canary pour MédiAgenda en prod : avantages, coût en ressources (quota de `mediagenda-prod`), vitesse et nature du retour arrière.
5. Qu'est-ce qu'un déploiement *shadow* (trafic miroir) ? Pourquoi est-il dangereux pour une API qui **écrit** (création de rendez-vous), et que faudrait-il pour s'en servir sans risque ?
6. *Feature flags* : en quoi diffèrent-ils d'un canary ? Un exemple chez MédiAgenda où un drapeau vaut mieux qu'un déploiement progressif.
7. Pendant un canary de MédiAgenda, deux versions de l'API écrivent dans la **même** base. Quelles règles doivent suivre les migrations de schéma pour que ce soit sûr ? Décris le schéma *expand / contract* sur l'exemple « renommer la colonne `motif` en `raison` ».
8. Pourquoi la suppression d'une colonne ne doit-elle jamais partir dans la même version que le code qui cesse de l'utiliser ? Que se passe-t-il au retour arrière ?
9. Le Job de migration (E11) tourne **avant** le canary : la nouvelle version du schéma est donc servie à l'ancienne version de l'API pendant tout le canary. Quelle propriété de la migration rend cela acceptable ?
10. Une analyse `web` sur `/pret` (E18) peut-elle détecter une régression **fonctionnelle** (un calcul de créneaux faux) ? Que faudrait-il ? Que verra-t-on mieux au M21 ?
11. Session et cache : un utilisateur dont les requêtes alternent entre la version stable et la version canary voit-il un comportement incohérent ? Quand est-ce un problème, et quels moyens (affinité, routage par en-tête) ?
12. MédiNotif consomme une file RabbitMQ. Que veut dire « 10 % de trafic » pour un *worker* ? Quelle stratégie proposerais-tu ?
13. Quel indicateur DORA (M19) un déploiement progressif avec analyses automatiques améliore-t-il le plus, et lequel peut-il dégrader ?

---

### M20-E21 — Revue : les Applications du stagiaire  `REV` `★★`

> **Ticket PLAT-2121** — *De : Karim Benali*
> Lucas a ouvert sa première MR GitOps : MédiNotif dans Argo CD. Il est pressé, l'équipe aussi. Fais une vraie revue, je veux la liste des problèmes, leur risque concret, et une version corrigée que je puisse fusionner.

**Objectifs pédagogiques**
- Relire des Applications et un ApplicationSet avec l'œil de l'exploitant : sécurité, suppression accidentelle, dérive, reproductibilité.
- Expliquer chaque défaut par son **risque concret**, pas par une règle.

**Prérequis** : M20-E10 à M20-E14.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers de Lucas : `modules/20-gitops/ressources/E21-applications-lucas/` (lire d'abord `LISEZMOI.md`).
- MédiNotif n'a pas encore d'AppProject : la version corrigée en suppose un, `medinotif` (sources `medinotif/*`, destinations `medinotif-dev` et `medinotif-prod`), à créer plus tard par la plateforme. Espace de l'opérateur RabbitMQ : `rabbitmq-system`.

**Travail demandé**
1. Relis les quatre fichiers. Pour chacun de tes constats, dans `~/m20/e21/revue.md`, une ligne d'un tableau numéroté : fichier, défaut, risque concret (ce qui arrive, à qui, quand), correction.
2. Écris la version corrigée dans `~/m20/e21/corrige/` (ApplicationSet de MédiNotif, Application de l'opérateur RabbitMQ ; pas de Secret : explique où il va). Contrôle-la : `argocd appset generate ~/m20/e21/corrige/applicationset-medinotif.yaml` (sans créer quoi que ce soit), `yamllint`.
3. Termine la revue par trois conseils à Lucas : les commandes à lancer avant d'ouvrir une MR GitOps.

**Critères de réussite**
- [ ] `revue.md` relève au moins 10 défauts, dont le Secret (et la nécessité de **changer** le mot de passe exposé).
- [ ] La version corrigée : aucun Secret, aucun projet `default`, aucune révision flottante, rien d'Internet, `ServerSideApply=true` partout, ni `CreateNamespace=true` ni `Replace=true`, aucune différence ignorée trop large, ni `allowEmpty` ni réessai infini, une syntaxe de gabarit correcte, une prod sans synchronisation automatique, un ApplicationSet en `create-update` avec `preserveResourcesOnDeletion`, aucune Application décrite deux fois, des sources multiples cohérentes.

**Vérification** : `lab/bin/check 20 21` (contrôle la version corrigée ; la revue s'évalue avec le corrigé)

<details><summary>Indice 1</summary>

Il y a des défauts dans **chaque** fichier, y compris dans des lignes qui « marchent » (une synchronisation automatique de la prod marche très bien… jusqu'au jour où).
</details>

<details><summary>Indice 2</summary>

Lis le générateur et le fichier `medinotif-prod.yaml` ensemble : combien de fois l'Application `medinotif-prod` est-elle décrite, et par qui ?
</details>

---

### M20-E22 — Runbook : une application est `OutOfSync` ou `Degraded`  `RED` `★★`

> **Ticket PLAT-2122** — *De : Nadia Roussel*
> Les courriels d'Argo CD arrivent (merci), mais à 3 h du matin, l'astreinte ne saura pas quoi en faire. J'ai besoin du runbook RB-200 : partir d'un courriel ou d'une tuile rouge, qualifier en deux minutes, savoir quoi regarder, quoi faire, et surtout quoi **ne pas** faire.

**Objectifs pédagogiques**
- Organiser un diagnostic GitOps en arbre de décision (rendu, dérive, synchronisation, santé).
- Écrire un runbook exploitable par quelqu'un qui n'a pas construit la plateforme.

**Prérequis** : M20-E10 à M20-E19.
**Durée indicative** : 1 h 30.

**Travail demandé**

Rédige `docs/livraison/gitops/runbooks/RB-200-application-outofsync-ou-degraded.md` dans `plateforme/medisphere` (MR relue par Nadia), sur le modèle des runbooks du M14. Il contient au moins :
- les déclencheurs (courriels d'E19, interface, ticket), la gravité selon l'environnement, les accès nécessaires ;
- une qualification rapide : quelles commandes, et comment distinguer une erreur de comparaison (`ComparisonError`), un écart (`OutOfSync`), une synchronisation en échec et un problème de santé (`Degraded`, `Progressing` qui dure, `Missing`, `Suspended`) ;
- pour chaque cas, une table « constat → cause probable → action », dont : jeton de dépôt expiré, racine absente, rendu en échec, dépôt ou espace hors projet, dérive manuelle, champ réécrit par un contrôleur, ressource en trop, hook de migration en échec, quota, objet refusé par l'admission, canary interrompu par une analyse, pause de canary en prod ;
- la règle « on corrige Git, pas le cluster », et l'exception de l'urgence en prod (ordre : `abort` du canary, revert par MR, `rollback` en dernier recours, et ce qu'il laisse derrière lui) ;
- la clôture (états attendus, MR liée, journal, post-mortem).

Teste-le : demande à quelqu'un (ou fais-le toi-même le lendemain, sans tes notes) de traiter avec le seul runbook la panne d'E18 (canary interrompu) rejouée en recette. Note ce qui manquait et complète.

---

### M20-E23 — Flux : le même déploiement avec un autre outil  `LAB` `★★★`

> **Ticket PLAT-2123** — *De : Claire Morel*
> Avant de figer notre choix dans l'ADR, je veux qu'on ait vraiment pratiqué l'autre grand outil. Monte un petit k3s jetable, déploie-y `labo` et un chart de notre miroir avec Flux, et écris-moi un comparatif honnête : ce qui est mieux, ce qui est moins bien, ce qui serait décisif pour nous.

**Objectifs pédagogiques**
- Amorcer Flux sur un cluster depuis un dépôt GitLab interne (`flux bootstrap gitlab`) avec des accès à portée limitée.
- Écrire les ressources de Flux : `GitRepository`, `Kustomization`, `OCIRepository`, `HelmRelease`.
- Comparer Argo CD et Flux sur des critères qui comptent pour MédiSphère.

**Prérequis** : M20-E13 (miroir de charts) ; M18 (rôle Ansible `k3s`, miroirs de registres vers Harbor) ; M05 (états OpenTofu) ; M07 (matrice des flux de la bordure).
**Durée indicative** : 3 h.

**Contexte technique**
- VM **2202 `flux01`** : Debian 13, 2 vCPU, 2 Go, 20 Go `local-nvme`, `vsandbox`, **10.10.99.62** fixe (passerelle 10.10.99.1, MAC `bc:24:11:99:20:02`), étiquettes `env-m20` et `role-k3s`, état OpenTofu **`envs/m20`** de `plateforme/infra` (nouveau, même construction que `envs/m18` ; `lyo-k3s01` s'y ajoutera en E26), nom DNS publié par l'état.
- k3s **v1.36.5+k3s1** par le rôle `k3s` du M18 (miroirs `docker.io`, `ghcr.io`, `quay.io`, `registry.k8s.io` vers les caches Harbor : les images de Flux et des applications arrivent par Harbor) ; Traefik, servicelb et metrics-server désactivés (2 Go). Inventaire NetBox `netbox-m20.yml`, playbook `playbooks/m20.yml`.
- Flux **2.9.6** (CLI `flux` sur `adm01`, binaire vérifié par son empreinte). Kubeconfig de `flux01` : `~/.config/workbook/m20/flux01.kubeconfig` (600), récupéré comme celui de `k3s01` au M18.
- Dépôt **`formation/flux-labo`** (créé par le bootstrap), chemin `clusters/flux01`. Accès : pour l'amorçage, un jeton à portée limitée et **courte durée** dans `GITLAB_TOKEN` ; pour la synchronisation, un jeton de **déploiement** en lecture seule (le flux de la bordure n'autorise que HTTPS vers `git01`). Racine MédiSphère : `/usr/local/share/ca-certificates/medisphere-root-ca.crt`.
- Flux réseau : `flux01` → `git01` TCP 443 (nouveau ; `vsandbox` → `reg01` 443 existe depuis M13).
- Applications : `labo` (dossier `apps/labo` : les manifestes de `formation/gitops-labo` d'E04, Deployment compris, dans un espace `labo`) et `podinfo` (chart `podinfo` **6.15.0**, recopié par `plateforme/charts-miroir` : ajoute-le à `charts.yaml` ; empreinte à relever), installé par un `HelmRelease` depuis un `OCIRepository` (Secrets hors Git : robot `charts+lecture`, racine MédiSphère).
- Livrable : `docs/livraison/gitops/comparatif-flux.md` dans `plateforme/medisphere`.

**Travail demandé**
1. Lis *Flux bootstrap for GitLab*, *GitRepository*, *Kustomization*, *OCIRepository*, *HelmRelease* (documentation de Flux 2.9) et les notes de version de la 2.9 (`flux migrate`). Dans `~/m20/e23/journal.md` : où sont les manifestes de Flux après le bootstrap ? Qui gère Flux ensuite ? Équivalent Flux de l'application racine, de `selfHeal`, de `prune`, des vagues ?
2. **La VM** : écris `envs/m20` (fichiers de `envs/m18` adaptés : catalogue `flux01` et `lyo-k3s01` par groupes, adresse fixe, nom DNS), `tofu plan` puis `apply` avec `groupes = ["flux"]`. Ouvre le flux `flux01` → `git01` 443 (`group_vars/role_routeur/pare_feu.yml`, une passerelle à la fois, `--check --diff` d'abord ; ⚠️ un changement de pare-feu se fait avec la procédure de retour arrière sous la main, M07) et reporte-le dans `docs/socle/matrice-flux.md`. Joue `playbooks/m20.yml`, récupère le kubeconfig.
3. **Accès** : crée d'abord le projet `formation/flux-labo`, vide (sans README : le bootstrap fera le premier commit sur `main`). Puis un jeton d'accès **de ce projet** pour l'amorçage : rôle et portées minimales pour qu'un bootstrap pousse ses manifestes et crée un jeton de déploiement, expiration **le lendemain**, rangé dans `~/.config/workbook/m20/flux-bootstrap.token` (600). Dans le journal : pourquoi pas ton jeton personnel ? pourquoi pas un jeton du groupe `formation` ?
4. **Bootstrap** : `flux bootstrap gitlab` avec l'hôte `git01.par1.medisphere.internal`, le groupe `formation`, le dépôt `flux-labo`, la branche `main`, le chemin `clusters/flux01`, la racine MédiSphère, et l'authentification par jeton de déploiement. `flux check`, `flux get all -A`. Lis ce que le bootstrap a commité. **Révoque** ensuite le jeton d'amorçage : Flux continue-t-il ?
5. **labo** : `apps/labo/` (espace `labo` en `restricted`, Deployment, Service) et une `Kustomization` Flux dans `clusters/flux01/apps.yaml` (prune, attente de santé). Poussée, puis observation : `flux get kustomizations --watch`. Dérive : `kubectl scale deploy labo -n labo --replicas=5` : combien de temps avant correction, sans option `selfHeal` ? Force une réconciliation (`flux reconcile kustomization labo --with-source`).
6. **podinfo** : ajoute `podinfo` à `charts.yaml` de `plateforme/charts-miroir` (MR, pipeline). Crée à la main dans `flux-system` les Secrets `harbor-charts` (robot `charts+lecture`, type `kubernetes.io/dockerconfigjson`, jeton jamais en argument) et `medisphere-ca` (clé `ca.crt`). Écris `apps/podinfo/` (espace, `OCIRepository` à version exacte, `HelmRelease` avec ses valeurs : 1 réplica, sécurité des conteneurs, ressources) et la `Kustomization` correspondante. Vérifie : `flux get helmreleases -A`, et `helm list -n podinfo` avec le kubeconfig de `flux01` : que constates-tu par rapport à Argo CD ?
7. **Comparatif** : rédige `comparatif-flux.md` (installation, accès aux dépôts, Helm, dérive, ordre, interface et droits, multi-cluster, mémoire mesurée, ce qui t'a surpris, recommandation pour MédiSphère). MR.
8. Garde `flux01` jusqu'au check. Si la mémoire manque avant E26, détruis-la ensuite (`groupes = []`, `tofu apply`) et retire le flux de la bordure (MR) ; sinon, le mini-projet (E46) le fera.

**Critères de réussite**
- [ ] VM 2202 `flux01` en marche (étiquette `env-m20`), `flux01.par1.medisphere.internal` → 10.10.99.62, k3s 1.36 Ready.
- [ ] Flux 2.9 : les quatre contrôleurs prêts ; `GitRepository` `flux-system` sur `formation/flux-labo` en HTTPS, Ready ; manifestes de Flux commités dans `clusters/flux01/flux-system/`.
- [ ] Kustomizations `flux-system`, `labo` (avec `prune`) et `podinfo` Ready ; `HelmRelease` `podinfo` Ready depuis un `OCIRepository` de Harbor à version exacte ; `labo` prêt sur `flux01`.
- [ ] `formation/flux-labo` : un jeton de déploiement en lecture seule, plus aucun jeton d'accès de projet `api` actif ; `podinfo` dans `charts.yaml` du miroir.
- [ ] `comparatif-flux.md` publié (Helm, prune, recommandation).

**Vérification** : `lab/bin/check 20 23`

<details><summary>Indice 1</summary>

`flux bootstrap gitlab --help` : regarde `--hostname`, `--owner` (et `--personal`), `--path`, `--branch`, `--ca-file`, et la différence entre `--token-auth` (le jeton d'amorçage reste dans le cluster) et `--deploy-token-auth` (Flux crée un jeton de déploiement de projet et le range dans le Secret `flux-system`).
</details>

<details><summary>Indice 2</summary>

Un jeton de déploiement GitLab sert en HTTPS (utilisateur + jeton) ; une **clé** de déploiement sert en SSH. La bordure n'ouvre pas le port 22 de `git01` à `vsandbox` : c'est un argument, pas un détail.
</details>

<details><summary>Indice 3</summary>

`OCIRepository` lit ses identifiants dans un Secret référencé par `secretRef` (au format d'un Secret de tirage d'images) et l'autorité dans `certSecretRef` (clé `ca.crt`). `HelmRelease` désigne la source par `chartRef` (type `OCIRepository`).
</details>

**Pour aller plus loin** (facultatif) : la vérification de signature d'un `OCIRepository` (`spec.verify`, fournisseur `cosign`, clé publique MédiSphère dans un Secret) : essaie-la sur `podinfo` ; fonctionne-t-elle sans journal de transparence ? Et Flux Operator (`FluxInstance`) comme autre façon d'installer Flux.
