# Module 20 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les solutions complètes sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un extrait des projets : `gitops/` = `plateforme/gitops`, `deploiement/` = `mediagenda/deploiement`, `gitops-labo/` = `formation/gitops-labo`, `k8s/` = `plateforme/k8s`, `charts-miroir/` = `plateforme/charts-miroir`, `ansible/` = `plateforme/ansible`, `infra/` = `plateforme/infra`, `flux-labo/` = `formation/flux-labo`, `medisphere/` = la documentation. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie, dans sa version **complète** à cet exercice ; on superpose les dossiers dans l'ordre des exercices. Un `.extrait` est un morceau à intégrer dans un fichier d'un exercice antérieur (l'emplacement est dit en tête). Dans `mediagenda/deploiement`, les valeurs propres à ton lab (`<DIGEST-PROMU>`, `<VERSION-PROMUE>`) ne se recopient pas : garde les tiennes.

**Ce qui a été vérifié à la rédaction, et comment.**
- *Kustomize* (5.8.1) : les trois overlays de `mediagenda/deploiement` à chaque étape (E11, E12, E14, E16, E18), à partir du projet du M17 (E09) et des changements d'E07 : rendus sans erreur, validés par **kubeconform 0.7** (`-strict`, schémas Kubernetes et catalogue de CRD : Rollout, AnalysisTemplate, HTTPRoute, Cluster CNPG, CiliumNetworkPolicy) ; vagues présentes sur les bons objets (ConfigMaps, compte de service, politiques en -3, base et Valkey en -2, Job en -1), y compris le `refus-par-defaut` de la prod ; image du Job alignée sur l'API ; refus de Kustomize constaté quand le component `livraison` vise un conteneur d'initialisation disparu (`unable to find field "spec.template.spec.initContainers.[name=migrations].image" in replacement target`). Les manifestes de `labo` (ceux d'E04 + HPA, Rollout, aperçu) validés de même.
- *Argo Rollouts* : `kubectl argo rollouts lint` **1.10.1** sur les Rollouts de `labo` (canary, blue/green) et sur celui de MédiAgenda **après** y avoir recopié le gabarit du Deployment (le linter ne suit pas `workloadRef` : il signale à tort des étiquettes absentes des Services) ; chart **`argo/argo-rollouts` 2.43.8** rendu par Helm 4.3 avec les valeurs d'E15 et E17 (ConfigMap `argo-rollouts-config`, conteneur d'initialisation, volumes, `ClusterAnalysisTemplate`) ; l'échappement des accolades dans `extraObjects` a été constaté nécessaire (`function "args" not defined` sans lui). Code de la 1.10 lu pour les points tranchés : `utils/plugin/downloader.go` (`sha256` contrôlé pour `http(s)`, **pas** pour `file://`), `metricproviders/webmetric/webmetric.go` (code hors 2xx = erreur de mesure, corps non JSON = succès), `analysis/analysis.go` (comparaisons strictes `>` des limites), `rollout/analysis.go` (`fieldRef` en `metadata.*`). Image du greffon 0.17.0 inspectée (Alpine, `/bin/rollouts-plugin-trafficrouter-gatewayapi`, utilisateur 999) ; ses empreintes relevées sur ghcr.io.
- *Argo CD 3.5.5* : chart **`argo/argo-cd` 10.10.5** rendu avec les valeurs d'E10, E12 et E19 (paramètre de politique des ApplicationSets, exclusions ajoutées à la liste par défaut, notifications : clés de `argocd-notifications-cm`, variable et volume du contrôleur) ; modèles de notification analysés par `text/template` de Go ; `templatePatch` des ApplicationSets rendu par `text/template` pour les trois environnements (YAML valide, `spec` jamais vide). Code de la 3.5.5 lu : `applicationset/controllers/applicationset_controller.go` (adoption d'une Application existante, annotations préservées), `applicationset/controllers/template/patch.go` (correctif stratégique, `project` non modifiable), `server/application/application.go` (refus de `rollback` avec synchronisation automatique), `gitops-engine/pkg/sync/hook/` (hooks Helm traduits en hooks Argo CD, sur **n'importe quel** manifeste), notifications-engine (`EmailOptions`).
- *Scripts* : `outils/promouvoir.sh` et `outils/verifier-livraison.sh` exécutés dans un clone de test (dépôt Git local, `cosign` et `kubectl` simulés, Kustomize réel) : promotion `dev → recette` (seules les 4 lignes attendues changent), refus `dev → prod`, refus d'une source incohérente, retour propre sur `main` après un échec du garde-fou ; `charts-miroir` : `lister.sh` sur un `charts.yaml` correct puis faussé, `recopier.sh` avec `helm pull` réel et `helm push` simulé (empreinte conforme, puis empreinte faussée : arrêt avant la poussée). ShellCheck 0.11 (`-x`, `-s sh` pour les scripts POSIX) et `bash -n` sur tous les scripts et checks.
- *Flux* : CLI **2.9.6** (`flux bootstrap gitlab --help`, `flux create … --export` pour la forme des objets) ; `OCIRepository` `source.toolkit.fluxcd.io/v1`, `HelmRelease` `helm.toolkit.fluxcd.io/v2`, `Kustomization` `kustomize.toolkit.fluxcd.io/v1` validés par kubeconform ; chart `podinfo` 6.15.0 rendu avec les valeurs du `HelmRelease`.
- *OpenTofu et Ansible* : `envs/m20` validé (`tofu validate`) avec les modules `vm-noeud` (M12) et `enregistrement-dns` (M06) du workbook ; `playbooks/m20.yml` passé à `ansible-playbook --syntax-check` (rôles simulés).
- *Empreintes relevées* (22/10/2026) : `argo-rollouts-2.43.8.tgz` `sha256:1c998ee3…0747d` (index du dépôt = calcul), `podinfo-6.15.0.tgz` `sha256:5ca78968…a334d75`, `kubectl-argo-rollouts-linux-amd64` v1.10.1 `fb28a5ba…b92cd` (= `argo-rollouts-checksums.txt`), images : `quay.io/argoproj/argo-rollouts:v1.10.1` `sha256:fbcc4cf0…769396`, `ghcr.io/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi:v0.17.0` `sha256:bc40d5ed…19d4a2`, `curlimages/curl:8.23.0` `sha256:11e64e28…92e`, `alpine/helm:4.3.0` `sha256:a6cf5459…64b2`, `mikefarah/yq:4.53.6` `sha256:cfc4eee6…5b23`.
- **Non rejoué sur un cluster** (signalé « ⚠️ À vérifier sur ton lab ») : l'adoption réelle par l'ApplicationSet (ordre entre l'Application `applications` et le contrôleur des ApplicationSets), les vagues et le hook en conditions réelles (temps d'attente de la base CNPG), le greffon Gateway API sur la Gateway **Cilium** (poids appliqués par Envoy, statut `Accepted` de la route pendant le canary), la réduction progressive du Deployment par `workloadRef`, les analyses (Job sous `restricted`, mesure `web` à travers les politiques réseau), les courriels (STARTTLS de Mailpit avec `SSL_CERT_FILE`), le bootstrap de Flux avec un jeton de projet et `--deploy-token-auth` sur GitLab 19.5, la vérification de signature d'un `OCIRepository` sans journal de transparence.

**Où lancer les commandes.** `admin@adm01:~$` (kubeconfig personnel, contexte `k8s-par1` ; CLI `argocd` connectée avec ton compte) ; les clones : `~/src/gitops`, `~/src/mediagenda-deploiement`, `~/src/gitops-labo`, `~/src/k8s`, `~/src/charts-miroir`, `~/src/ansible`, `~/src/infra`, `~/src/flux-labo`, `~/medisphere`.

---

### M20-E10 — ApplicationSets : un générateur pour trois environnements

**Solution**

Fichiers : [`applications/mediagenda.yaml`](fichiers/M20-E10/gitops/applications/mediagenda.yaml) (version E10), [`values.extrait-E10.yaml`](fichiers/M20-E10/k8s/composants/argocd/values.extrait-E10.yaml).

1. **Lecture.** Par défaut (politique `sync`), le contrôleur crée, met à jour **et supprime** : une Application dont l'élément disparaît du générateur est supprimée. Supprimer l'ApplicationSet supprime ses Applications par les références de propriétaire (`ownerReferences`), puis, si elles portent le finaliseur `resources-finalizer.argocd.argoproj.io`, leurs charges. Ce finaliseur est posé sur chaque Application générée… **sauf** si `syncPolicy.preserveResourcesOnDeletion: true`. `templatePatch` est nécessaire parce que le gabarit ne sait remplacer que des **chaînes** : il ne peut pas faire apparaître ou disparaître l'objet `automated` ; `templatePatch` est rendu comme un gabarit Go, puis appliqué comme un correctif stratégique sur l'Application.
2. **Générateur.** Liste explicite. Avec le générateur de répertoires sur `overlays/*`, un dossier `overlays/essai` ajouté par erreur (il existait au M17) deviendrait l'Application `mediagenda-essai`, synchronisée automatiquement vers un espace `mediagenda-essai` (refusé par le projet, heureusement) ; et le jour où il faut un réglage par environnement (prod manuelle), on retombe sur une table. La liste rend chaque environnement **explicite** et relu en MR. (Le générateur Git reste le bon choix quand les environnements sont nombreux et homogènes.)
3. **Politique par ApplicationSet.** Sans `applicationsetcontroller.enable.policy.override: "true"`, le contrôleur **ignore** `spec.syncPolicy.applicationsSync` et applique sa politique globale (`sync`). On l'ajoute aux valeurs :
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff     # argocd-cmd-params-cm, et checksum/cmd-params des pods
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply
   admin@adm01:~$ kubectl -n argocd get cm argocd-cmd-params-cm -o jsonpath='{.data.applicationsetcontroller\.enable\.policy\.override}'
   true
   admin@adm01:~$ kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-applicationset-controller   # pod recréé (annotation checksum/cmd-params)
   ```
4. **Lecture avant écriture.**
   ```
   admin@adm01:~/src/gitops$ argocd appset generate applications/mediagenda.yaml -o yaml > ~/m20/e10/genere.yaml
   admin@adm01:~/src/gitops$ argocd app get mediagenda-dev -o yaml > ~/m20/e10/vivante.yaml
   admin@adm01:~/src/gitops$ diff <(yq '.spec' ~/m20/e10/vivante.yaml) <(yq 'select(.metadata.name == "mediagenda-dev") | .spec' ~/m20/e10/genere.yaml)
   ```
   Écarts attendus : `spec.info` (traçabilité d'E08, absente du gabarit : elle disparaîtra), `syncPolicy.retry` (ajouté). Rien sur `source`, `destination`, `project`, `syncOptions` : sinon, corriger le gabarit avant. Côté métadonnées : l'Application générée a les étiquettes `medisphere.internal/*`, pas de finaliseur.
5. **Passage de témoin, MR 1.** `kubectl -n argocd get app mediagenda-dev -o jsonpath='{.metadata.finalizers}'` doit être vide (E08 n'en a pas mis). Puis on ajoute à `applications/mediagenda-dev.yaml` :
   ```yaml
   metadata:
     annotations:
       # Passage de témoin à l'ApplicationSet (M20-E10) : l'Application « applications » ne doit pas
       # supprimer cet objet quand son fichier disparaîtra.
       argocd.argoproj.io/sync-options: Prune=false
   ```
   Ce qui se passerait sans : à la fusion de la MR 2, deux contrôleurs agissent en même temps. Si `applications` prune d'abord, il **supprime** l'Application `mediagenda-dev`. Sans finaliseur, les charges restent ; l'ApplicationSet recrée une Application du même nom, qui retrouve ses objets par l'annotation de suivi (`argocd.argoproj.io/tracking-id: mediagenda-dev:…`) : pas de coupure, mais une Application supprimée et recréée (historique perdu, notifications). **Avec** le finaliseur, la suppression de l'Application emporterait tout MédiAgenda dev, base CNPG comprise. `Prune=false` rend le passage déterministe : `applications` ne supprime jamais l'objet, l'ApplicationSet l'adopte.
6. **MR 2.**
   ```
   admin@adm01:~$ kubectl get rs -n mediagenda-dev -l app.kubernetes.io/component=api      # nom + âge, notés
   admin@adm01:~$ argocd app diff mediagenda-dev && echo "diff vide"
   admin@adm01:~/src/gitops$ git rm applications/mediagenda-dev.yaml && git add applications/mediagenda.yaml   # MR, fusion
   admin@adm01:~$ argocd app get applications --refresh ; sleep 30
   admin@adm01:~$ kubectl -n argocd get app mediagenda-dev -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
   ApplicationSet/mediagenda
   admin@adm01:~$ kubectl get rs -n mediagenda-dev -l app.kubernetes.io/component=api      # même nom, même âge
   ```
   À l'adoption, le contrôleur réécrit `spec`, étiquettes et annotations (seules quelques annotations d'Argo CD sont préservées) : l'annotation de suivi posée par `applications` disparaît, et avec elle le lien. `applications` ne voit plus l'objet comme le sien : l'avertissement « requires pruning » s'efface, et l'annotation `Prune=false` part avec la réécriture.
7. **Recette et prod.** Première MR avec `recette` en `auto: false` : `mediagenda-recette` apparaît `OutOfSync` (aucun objet ne porte encore son annotation de suivi). Le diff (rendu actuel du dépôt contre ce qu'a appliqué `kubectl` au M17) ne doit contenir que des différences connues : annotation de suivi ajoutée partout, étiquettes ou valeurs changées depuis le M17, ConfigMap générée dont l'empreinte a changé (nouvelle). `argocd app sync mediagenda-recette` à la main, une fois, puis MR `auto: true`. Les objets créés par `kubectl` et **absents** du rendu (ancienne ConfigMap `mediagenda-parametres-<empreinte>`, objets retirés du dépôt depuis) n'ont pas d'annotation de suivi : Argo CD ne les supprime pas, mais le projet `mediagenda` les signale comme **orphelins** (`orphanedResources.warn`, E07) ; on les supprime à la main après vérification (`kubectl delete configmap … -n mediagenda-recette`), c'est le dernier geste manuel sur cet espace. Pour la prod, même lecture, puis `argocd app sync mediagenda-prod` ; elle reste manuelle. Note les écarts et leur cause : c'est le relevé de la dérive accumulée depuis le M17.
8. **Essai de sûreté.** Élément `prod` retiré : `argocd appset generate` ne produit plus que deux Applications. Avec `create-update`, le contrôleur **ne supprime pas** `mediagenda-prod` : elle reste, orpheline de l'ApplicationSet (toujours propriétaire, mais plus générée), à supprimer volontairement. Avec la politique par défaut, il la supprimerait — sans finaliseur, ses charges resteraient (`preserveResourcesOnDeletion`), mais plus rien ne les réconcilierait.

**Explications**

L'ApplicationSet est un **générateur d'Applications**, géré lui-même par l'Application `applications` : Git → ApplicationSet → Applications → objets. Chaque étage a sa politique de suppression, et c'est leur combinaison qui protège : `preserveResourcesOnDeletion` (pas de finaliseur sur les Applications) protège les charges ; `create-update` protège les Applications d'un générateur modifié ; le `Prune=false` temporaire protège l'objet pendant qu'il change de propriétaire. L'adoption sans recréation fonctionne parce qu'Argo CD retrouve ses objets par l'annotation de suivi, qui porte le **nom** de l'Application : même nom, mêmes objets.

**Alternatives**
- *Générateur de répertoires Git* (`directories: [{path: overlays/*}, {path: overlays/essai, exclude: true}]`) : moins de lignes, mais l'ajout d'un environnement se fait par un dossier, sans relecture du réglage de synchronisation.
- *Générateur `matrix`* (environnements × clusters) : utile au M20-E26 si MédiAgenda allait aussi à LYO1.
- *Trois Applications écrites à la main* : lisibles, mais trois copies qui divergent (c'est le ticket).
- *Politique globale* `--policy create-update` sur le contrôleur (valeur `applicationsetcontroller.policy`) : protège tous les ApplicationSets d'un coup ; on peut combiner (globale stricte, dérogations par ApplicationSet si `enable.policy.override`).

**Pièges classiques**
- Oublier le paramètre de dérogation : `applicationsSync` est silencieusement ignoré.
- Un `templatePatch` dont un bloc conditionnel produit `spec:` vide : il efface `spec` du gabarit (problème connu, documenté).
- `goTemplate: true` avec la syntaxe `{{path.basename}}` (*fasttemplate*) : rendu en échec. En Go : `{{ .path.basename }}`.
- Changer `project` par `templatePatch` : ignoré par le contrôleur (garde-fou de sécurité).
- Supprimer l'ApplicationSet « pour le recréer » : sans `preserveResourcesOnDeletion`, tout part. Pour s'en débarrasser sans rien toucher : `kubectl delete applicationset mediagenda -n argocd --cascade=orphan`.
- Croire que l'Application d'E08 « gardera » son `spec.info` : l'ApplicationSet la réécrit (le check d'E08 lit cette information ; refais-le **avant** E10, ou reporte `info` dans le `templatePatch` de dev si tu tiens à la trace).

**En production chez MédiSphère**

L'ApplicationSet `mediagenda` est relu comme un fichier de production (il pilote la prod). On ajoute une règle de relecture : toute MR sur `applications/` passe par `argocd appset generate` dans le pipeline de `plateforme/gitops` (résultat en commentaire de MR), et un check périodique compare la liste des Applications générées à celle attendue.

---

### M20-E11 — Vagues et hooks de synchronisation

**Solution**

Fichiers : [`components/migrations/`](fichiers/M20-E11/deploiement/components/migrations/) (`kustomization.yaml`, `job.yaml`), [`base/values-communes.yaml`](fichiers/M20-E11/deploiement/base/values-communes.yaml), [`components/livraison/kustomization.yaml`](fichiers/M20-E11/deploiement/components/livraison/kustomization.yaml), [`outils/verifier-livraison.sh`](fichiers/M20-E11/deploiement/outils/verifier-livraison.sh), overlays [`recette`](fichiers/M20-E11/deploiement/overlays/recette/kustomization.yaml), [`prod`](fichiers/M20-E11/deploiement/overlays/prod/kustomization.yaml), [`dev` (extrait)](fichiers/M20-E11/deploiement/overlays/dev/kustomization.extrait.yaml).

1. **Lecture.** Ordre d'une synchronisation : par **phase** (`PreSync`, `Sync`, `PostSync`), puis par **vague** (entier, défaut 0, du plus petit au plus grand), puis par type (espaces de noms d'abord, puis objets du cœur, puis objets de CRD) et par nom. Entre deux vagues, Argo CD attend que tous les objets de la vague soient **sains** (vérifications de santé : un Job est sain quand il est terminé avec succès, un `Cluster` CNPG quand son statut est `Cluster in healthy state`). Un hook `PreSync` passe **avant toutes** les vagues de la phase `Sync`, donc avant la vague -2. Un objet rendu avec `helm.sh/hook: pre-upgrade` est **traduit** en hook `PreSync` par Argo CD (`pre-install`/`pre-upgrade` → `PreSync`, `post-*` → `PostSync`, `helm.sh/hook-weight` → vague, `before-hook-creation` → `BeforeHookCreation`), d'où qu'il vienne : rendu Helm, Kustomize ou dossier simple. Les tests Helm (`helm.sh/hook: test`) ne sont pas traduits : ils deviendraient des pods ordinaires.
2. **Dev reconstruit de zéro.** La base est dans l'overlay (component `dependances`, phase `Sync`). Une migration en `PreSync` passerait avant la création de la base : échec, synchronisation arrêtée, base jamais créée, et ainsi de suite à chaque nouvel essai — **interblocage**. D'où : hook de phase **`Sync`**, vague **-1**, après la base (vague -2) et ses prérequis (vague -3 : ConfigMaps, compte de service, politiques réseau qui ouvrent l'accès du Job à PostgreSQL). En recette, la base est gérée hors du dépôt : la vague -2 est vide et le Job suit directement la -3.
3. **Component.** Voir [`job.yaml`](fichiers/M20-E11/deploiement/components/migrations/job.yaml) : étiquettes `app.kubernetes.io/name` et `instance` = `mediagenda` (le Job reçoit les sorties de la NetworkPolicy `mediagenda` du chart vers DNS et PostgreSQL, et l'entrée de `mediagenda-acces-base` en recette), `component: migrations` (il n'entre ni dans le Service, ni dans le PDB, ni dans la CiliumNetworkPolicy de la Gateway, qui sélectionnent `component: api`), compte `default` sans jeton, sécurité `restricted`, requêtes et limites (quota). Politique **`BeforeHookCreation`** : le Job est supprimé juste avant d'en recréer un, donc le dernier reste lisible (journaux) jusqu'à la synchronisation suivante ; `HookSucceeded` effacerait la preuve d'un succès, `HookFailed` celle d'un échec. Les vagues des autres objets passent par des correctifs **stratégiques** avec `target` (ils fusionnent l'annotation dans `metadata.annotations`, qu'elle existe ou non ; un `add` JSON 6902 sur `/metadata/annotations/<clé>` échoue sur un objet sans annotations).
4. **Rendu et livraison.**
   ```
   admin@adm01:~/src/mediagenda-deploiement$ outils/rendre-base.sh && grep -c initContainers base/rendu/mediagenda.yaml
   0
   admin@adm01:~/src/mediagenda-deploiement$ for o in dev recette prod; do kubectl kustomize overlays/$o \
       | yq 'select(.kind == "Deployment" or .kind == "Job") | .metadata.name + " " + .spec.template.spec.containers[0].image'; done
   admin@adm01:~/src/mediagenda-deploiement$ outils/verifier-livraison.sh
   dev : v1.1.0, conforme
   prod : v1.0.0, conforme
   recette : v1.0.0, conforme
   ```
   Le component `livraison` remplace l'étiquette de l'image du **Job** (au lieu du conteneur d'initialisation disparu : sans ce changement, Kustomize refuse le rendu) ; l'`images:` des overlays (digest, M19-E17) s'applique à toutes les images de ce nom, Job compris. `verifier-livraison.sh` contrôle désormais l'image du Job et sa présence.
5. **Observation.**
   ```
   admin@adm01:~$ argocd app get mediagenda-recette -o json | jq -r '.status.operationState.syncResult.resources[]
       | [.syncPhase, (.hookType // "-"), .kind, .name, .status, (.hookPhase // "")] | @tsv'
   Sync   -     ConfigMap               mediagenda-parametres-…   Synced
   Sync   -     NetworkPolicy           mediagenda                Synced
   …
   Sync   Sync  Job                     mediagenda-migrate        Synced   Succeeded
   Sync   -     Deployment              mediagenda                Synced
   ```
   L'interface (*Last Sync* → *Result*) montre les vagues dans l'ordre. ⚠️ À vérifier sur ton lab : le temps passé en vague -2 en dev (CNPG déjà sain : quelques secondes).
6. **Échec provoqué** (dev) : correctif JSON 6902 de l'overlay `dev`, ciblant le Job :
   ```yaml
   - target: {group: batch, kind: Job, name: mediagenda-migrate}
     patch: |-
       - op: replace
         path: /spec/template/spec/containers/0/env/0
         value: {name: MEDIAGENDA_DB_URL, value: "postgresql://mediagenda@base-absente:5432/mediagenda"}
   ```
   plus `MEDIAGENDA_CACHE_TTL=7` dans un `configMapGenerator` de l'overlay. Résultat : Job en échec après ses 3 essais (`backoffLimit: 2`) ; opération `Failed` (« one or more synchronization tasks completed unsuccessfully ») ; la ConfigMap de la vague -3 a été créée, mais le Deployment (vague 0) **n'a pas** été modifié : l'API continue avec l'ancienne ConfigMap et l'ancienne image. Les réessais de `retry` (3) rejouent le hook, puis s'arrêtent. `kubectl logs job/mediagenda-migrate -n mediagenda-dev` : erreur de connexion psycopg (`failed to resolve host 'base-absente'`). Revert par MR : synchronisation réussie.
7. **Bilan.** Conteneur d'initialisation : rejoué par chaque pod (le verrou consultatif évite les collisions), échec visible tard (pods qui ne démarrent pas), mais la version suit toujours son schéma. Hook Helm du M17 : une fois par montée, mais lié à `helm upgrade`. Hook Argo CD : une fois par **synchronisation** (y compris une synchronisation sans changement d'image : la commande doit être idempotente, elle l'est), arrêt **avant** la nouvelle version, journal du Job lisible. Aucun des trois ne sait « défaire » une migration : le schéma doit rester compatible avec la version précédente (*expand/contract*, E20).

**Explications**

Les vagues transforment un `kubectl apply` « tout à la fois » en une suite d'étapes **avec attente de santé**. Le hook de phase `Sync` placé dans une vague est la forme la plus robuste pour une migration quand la base fait partie de la même synchronisation ; `PreSync` convient quand la base vit ailleurs et existe toujours (recette ici), mais un même component pour les trois environnements impose le cas le plus exigeant.

**Alternatives**
- *Rendre le chart en mode `hook`* (sans `--no-hooks` dans `rendre-base.sh`) : Argo CD traduirait le Job Helm `mediagenda-migrations` en `PreSync` — même interblocage en dev neuf, et la politique réseau du hook (`hook-succeeded`) supprimée après chaque synchronisation.
- *Job ordinaire (pas hook) en vague -1 avec un nom changeant par version* : un Job est immuable ; il faudrait le supprimer à chaque fois. Le hook le fait pour toi.
- *Opérateur de migrations* (Atlas, Flyway par un opérateur) : hors périmètre.

**Pièges classiques**
- Laisser le conteneur d'initialisation **et** le Job : la migration passe deux fois, et un échec du Job n'empêche plus des pods de migrer seuls.
- Un Job hook sans les étiquettes qui lui ouvrent la base : il échoue en *timeout*, pas avec un message clair.
- `hook-delete-policy: HookSucceeded` : plus aucune trace d'un succès (et l'Application montre le hook « manquant » dans l'arbre).
- Vague négative sur la base **et** `prune` : supprimer la base d'un overlay (déplacement de fichier) la supprime en premier — d'où la protection `Prune=false` sur les données (palier 4, E41).

**En production chez MédiSphère**

Les migrations de MédiAgenda sont **additives** par règle (revue de MR de l'équipe de Julien). Une migration longue (index sur une grosse table) sort du hook : elle se fait par un Job lancé à part, avant la livraison, dans une fenêtre de changement (E29). Le temps du hook est suivi au M21 (durée des Jobs `mediagenda-migrate`).

---

### M20-E12 — Ce qu'Argo CD ne doit pas gérer : différences ignorées et Secrets hors Git

**Solution**

Fichiers : [`applications/mediagenda.yaml`](fichiers/M20-E12/gitops/applications/mediagenda.yaml) (version E12), [`labo.extrait-E12.yaml`](fichiers/M20-E12/gitops/applications/labo.extrait-E12.yaml), [`k8s/hpa.yaml`](fichiers/M20-E12/gitops-labo/k8s/hpa.yaml) et [`kustomization.yaml`](fichiers/M20-E12/gitops-labo/k8s/kustomization.yaml) de `labo`, [`base/kustomization.yaml`](fichiers/M20-E12/deploiement/base/kustomization.yaml), [`values.extrait-E12.yaml`](fichiers/M20-E12/k8s/composants/argocd/values.extrait-E12.yaml), modules [`secrets-k8s.d/mediagenda-*.sh`](fichiers/M20-E12/k8s/outils/secrets-k8s.d/), [`secrets/mediagenda-recette.yml.exemple`](fichiers/M20-E12/k8s/secrets/mediagenda-recette.yml.exemple).

1. **Lecture.** `ignoreDifferences` seul agit sur la **comparaison** (le champ ne rend plus l'Application `OutOfSync`), pas sur la **synchronisation** : la prochaine synchronisation réapplique la valeur du dépôt. `RespectIgnoreDifferences=true` fait recopier, dans ce qu'Argo CD applique, la **valeur vivante** des champs ignorés : la synchronisation n'écrase plus ce qu'a choisi le contrôleur (code de la 3.5 : `normalizeTargetResources` de `controller/sync.go`). En *server-side apply*, Argo CD réapplique donc cette même valeur et reste copropriétaire du champ, sans conflit : le HPA ou le Rollout, qui écrivent par `Update`, continuent de le modifier librement. `IgnoreExtraneous` est une option de **comparaison d'une ressource** : un objet suivi par l'Application mais absent du dépôt (« en trop ») ne compte plus dans l'état de synchronisation ; rien à voir avec un champ.
2. **HPA.** Le gabarit de `labo` déclare `requests.cpu: 10m` : le HPA calcule. Charge :
   ```
   admin@adm01:~$ kubectl -n wb-essais run charge --image=registry.par1.medisphere.internal/dockerhub/curlimages/curl:8.23.0 \
       --restart=Never --overrides='{"spec":{"securityContext":{"runAsUser":100,"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"charge","image":"registry.par1.medisphere.internal/dockerhub/curlimages/curl:8.23.0","command":["sh","-c","while true; do curl -s -o /dev/null http://labo; done"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
   admin@adm01:~$ kubectl -n wb-essais get hpa labo -w
   ```
   Le HPA passe à 3 ou 4 pods ; `argocd app get labo` : `OutOfSync` sur `Deployment/labo`. `--show-managed-fields` : `spec.replicas` appartient à `kube-controller-manager` (opération `Update`, sous-ressource `scale`). Avec `selfHeal`, Argo CD remet 2, le HPA remet 4 : yo-yo, pods créés et détruits en boucle.
3. **Correction** ([`labo.extrait-E12.yaml`](fichiers/M20-E12/gitops/applications/labo.extrait-E12.yaml)) : `ignoreDifferences` sur `/spec/replicas` du seul Deployment `labo`, plus `RespectIgnoreDifferences=true`. Après `argocd app sync labo`, le nombre de pods reste celui du HPA. (Autre solution valable : retirer `replicas` du dépôt ; mais le premier `apply` d'un Deployment sans `replicas` donne 1 pod avant que le HPA ne corrige.) `kubectl -n wb-essais delete pod charge`.
4. **ApplicationSet.** Élément `progressif` (recette, prod) ; dans `templatePatch`, sous condition : les deux `ignoreDifferences` — HTTPRoute `mediagenda`, `jqPathExpressions: [.spec.rules[].backendRefs[]?.weight]` ; Deployment `mediagenda`, `jsonPointers: [/spec/replicas]` — et `RespectIgnoreDifferences=true`. Pour les trois, l'annotation `argocd.argoproj.io/compare-options: IncludeMutationWebhook=true` (le diff côté serveur est déjà global depuis E05). `argocd appset generate` : dev n'a rien d'ignoré.
5. **Webhooks de mutation.** Le webhook de CloudNativePG complète le `Cluster` à l'admission (valeurs par défaut de la spécification : paramètres PostgreSQL, sondes, stratégie de mise à jour…). Un diff qui compare le dépôt à l'objet vivant **sans** faire passer le dépôt par ce webhook voit ces champs comme des écarts sur les seuls objets dont le dépôt écrit déjà la structure (le dépôt n'écrit pas `postgresql:` en dev : c'est en prod, où `haute-disponibilite` écrit `postgresql.synchronous`, que le webhook complète le même bloc). `IncludeMutationWebhook=true` fait passer l'objet du dépôt par le webhook pendant le *dry-run* : ce qu'il ajoute est attendu, plus d'écart. ⚠️ À vérifier sur ton lab : les champs exacts que complète CNPG 1.30 (`kubectl get cluster mediagenda-db -n mediagenda-prod -o yaml` contre le component).
6. **ConfigMaps générées** : annotation **sur la ConfigMap**, par `options.annotations` du `configMapGenerator` de la base ([`base/kustomization.yaml`](fichiers/M20-E12/deploiement/base/kustomization.yaml)) : `argocd.argoproj.io/compare-options: IgnoreExtraneous`. Les anciennes `mediagenda-parametres-<empreinte>` restent jusqu'à une synchronisation `--prune`, sans rendre l'Application `OutOfSync`. Sur l'**Application**, la même annotation de comparaison ne viserait pas les objets en trop d'un type donné : elle s'appliquerait à tout, et masquerait par exemple un Deployment oublié. Note : le changement d'annotation change l'empreinte du nom : une nouvelle ConfigMap, donc un redéploiement des trois environnements (dev et recette automatiquement, prod à la prochaine synchronisation).
7. **Exclusions** ([`values.extrait-E12.yaml`](fichiers/M20-E12/k8s/composants/argocd/values.extrait-E12.yaml)) : `configs.cm.resourceExclusionsAdditional` (le chart l'**ajoute** à `resource.exclusions` par défaut ; écrire `resource.exclusions` remplacerait toute la liste du chart). Objets `velero.io` `Backup`, `Restore`, `PodVolumeBackup`, `PodVolumeRestore`, `DataUpload`, `DataDownload` : créés par Velero, jamais décrits dans Git. On n'exclut jamais un type décrit dans Git : Argo CD ne le verrait plus, ne le comparerait plus, ne le synchroniserait plus — une dérive totale et silencieuse.
   ```
   admin@adm01:~$ kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.resource\.exclusions}' | grep -A3 velero
   ```
8. **Secrets.** Modules [`mediagenda-dev.sh`, `mediagenda-recette.sh`, `mediagenda-prod.sh`](fichiers/M20-E12/k8s/outils/secrets-k8s.d/) (trois lignes chacun) et [`mediagenda-commun.sh`](fichiers/M20-E12/k8s/outils/secrets-k8s.d/mediagenda-commun.sh) : Secret `harbor-pull` de type `kubernetes.io/dockerconfigjson`, contenu passé par une substitution de processus (`--from-file=.dockerconfigjson=<(…)`), *server-side apply* par le gestionnaire `secrets-k8s`, vérification par empreinte. Le robot est le même pour les trois espaces ; trois fichiers de Vault permettent un robot par environnement plus tard (prod séparée).
   ```
   admin@adm01:~/src/k8s$ for e in dev recette prod; do outils/secrets-k8s.sh appliquer mediagenda-$e && outils/secrets-k8s.sh verifier mediagenda-$e; done
   admin@adm01:~/src/mediagenda-deploiement$ git log -p --all -S 'kind: Secret' --oneline | grep -E '^[0-9a-f]{7,}|^[+-]kind: Secret'
   ```
   Aucun résultat attendu dans les trois dépôts. Un résultat dans l'historique = Secret compromis : rotation du secret (nouveau jeton, Vault, `appliquer`), puis seulement nettoyage. Le Secret `harbor-pull` d'avant (M14) est **repris** par `secrets-k8s.sh` (même nom, *server-side apply*) : pas de coupure de tirage.

**Explications**

Trois mécanismes, trois questions différentes. *Qui écrit ce champ ?* — un contrôleur (HPA, Argo Rollouts) : on lui laisse le champ (`ignoreDifferences` ciblé + `RespectIgnoreDifferences`). *L'API complète-t-elle mon objet ?* — valeurs par défaut, webhooks : on fait calculer l'état attendu par l'API (diff côté serveur, `IncludeMutationWebhook`), on n'ignore rien. *Cet objet n'est-il pas à moi ?* — Secrets créés hors Git, objets d'opérateurs : ils n'ont pas d'annotation de suivi, Argo CD ne les gère pas ; pour les restes générés, `IgnoreExtraneous` ; pour les types de masse, exclusion.

**Alternatives**
- `managedFieldsManagers: [kube-controller-manager]` au lieu de `jsonPointers` : ignore **tout** ce que ce gestionnaire possède sur l'objet. Plus large, utile pour un opérateur qui écrit beaucoup de champs ; ici on veut un champ précis.
- Réglage **global** `resource.customizations.ignoreDifferences.apps_Deployment` dans `argocd-cm` : pour toutes les Applications. Dangereux pour un type aussi courant (masque toutes les dérives de réplicas du cluster).
- Sealed Secrets / SOPS : des Secrets chiffrés dans Git. Écarté (PLAN §4.11) jusqu'à External Secrets au M25 : la clé de déchiffrement devient un nouveau secret à protéger, et le contenu reste dans l'historique.

**Pièges classiques**
- `jsonPointers: [/spec]` « pour avoir la paix » : plus aucune dérive visible (la revue de Lucas, E21).
- `ignoreDifferences` sans `name` : vaut pour tous les objets de ce type de l'Application.
- `ignoreDifferences` sans `RespectIgnoreDifferences` : yo-yo à chaque synchronisation.
- Exclure `ConfigMap` ou `Secret` pour « alléger » Argo CD : il ne les verrait plus du tout, même ceux de Git.
- Croire qu'un Secret supprimé de Git est « retiré » : il est dans l'historique, les clones, les caches du repo-server.

**En production chez MédiSphère**

Une ligne d'`ignoreDifferences` = une exception relue par Sophie (commentaire obligatoire dans le fichier). Un job planifié de `plateforme/gitops` cherche `kind: Secret` dans tous les dépôts suivis par Argo CD (liste tirée des AppProjects), et Gitleaks (M19) tourne déjà dans leurs pipelines.

---

### M20-E13 — Helm et Kustomize dans Argo CD, sources multiples

**Solution**

Fichiers : projet [`charts-miroir/`](fichiers/M20-E13/charts-miroir/) (`charts.yaml`, `.gitlab-ci.yml`, `outils/lister.sh`, `outils/recopier.sh`, `outils/signer.sh`, `README.md`), module [`secrets-k8s.d/argocd.sh`](fichiers/M20-E13/k8s/outils/secrets-k8s.d/argocd.sh) (version E13) et [`secrets/argocd.yml.exemple`](fichiers/M20-E13/k8s/secrets/argocd.yml.exemple), [`projets/plateforme.extrait-E13.yaml`](fichiers/M20-E13/gitops/projets/plateforme.extrait-E13.yaml), [`essais/essai-multisources.yaml`](fichiers/M20-E13/gitops/essais/essai-multisources.yaml), [`valeurs/essai-multisources/values.yaml`](fichiers/M20-E13/gitops/valeurs/essai-multisources/values.yaml).

1. **Empreinte.**
   ```
   admin@adm01:~/m20/e13$ curl -fsSL https://argoproj.github.io/argo-helm/index.yaml \
       | yq '.entries["argo-rollouts"][] | select(.version == "2.43.8") | .digest'
   1c998ee3cd72a078ca73ba399644198fe8a446399b5fc5bbff94af5043a0747d
   admin@adm01:~/m20/e13$ helm pull argo-rollouts --repo https://argoproj.github.io/argo-helm --version 2.43.8 && sha256sum argo-rollouts-2.43.8.tgz
   1c998ee3cd72a078ca73ba399644198fe8a446399b5fc5bbff94af5043a0747d  argo-rollouts-2.43.8.tgz
   ```
   Le champ `digest` de l'index est le SHA-256 de l'archive : deux sources indépendantes (index signé par personne, archive téléchargée) qui doivent coïncider. Une archive republiée sous la même version (ça arrive) changerait l'empreinte : le pipeline refuse.
2. **Projet et pipeline.** `lister` (image `mikefarah/yq`, runner `k8s`, aucun secret) contrôle `charts.yaml` (nom, version exacte X.Y.Z, empreinte, dépôt `https://` ou `oci://`, pas de doublon) et produit `charts.tsv`. `recopier` (image `alpine/helm`, runner **protégé**, `resource_group`) : pour chaque chart, s'il existe déjà à cette version dans Harbor, on ne republie pas (étiquettes immuables du projet `charts`) et on relit son digest ; sinon `helm pull`, empreinte, `helm push`, digest relevé ; résultat dans `recopies.txt`. `signer` (image outillée du M13) : `cosign verify` d'abord, `cosign sign --signing-config` du **digest** seulement s'il n'est pas signé (Cosign 3 ajoute un référent à chaque signature : pas idempotent). Variables du projet : `HARBOR_MIROIR_USER` (`robot$charts+miroir`, protégée, non masquable à cause du `$`, développement désactivé), `HARBOR_MIROIR_TOKEN` (protégée, masquée) ; la clé Cosign vient des variables protégées du groupe `plateforme` (M13). Les jobs `recopier` et `signer` ne tournent que sur une branche protégée (`$CI_COMMIT_REF_PROTECTED`) et sur le runner `protege` : une MR ne voit ni le robot d'écriture ni la clé.
3. **Essai rouge.** Le job `lister` ne contrôle que la **forme** de l'empreinte : une empreinte fausse mais bien formée passe la MR. C'est `recopier` qui la refuse, avant toute poussée :
   ```
   ERREUR argo-rollouts 2.43.8 : empreinte sha256:1c998ee3…, attendue sha256:0c998ee3… (charts.yaml) : rien n'est poussé
   ```
   Vérifié à la rédaction en lançant `outils/recopier.sh` localement avec un `helm` dont `push` est simulé. Sur le lab : pipeline de la branche protégée de test, ou exécution locale (la recopie ne pousse rien en cas d'écart). Conséquence à écrire dans la MR : la relecture humaine de l'empreinte est le contrôle principal ; le pipeline le rend **bloquant**.
4. **Vérifications.**
   ```
   admin@adm01:~$ helm show chart oci://registry.par1.medisphere.internal/charts/argo-rollouts --version 2.43.8 | grep -E '^(version|appVersion)'
   appVersion: v1.10.1
   version: 2.43.8
   admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true \
       registry.par1.medisphere.internal/charts/argo-rollouts@sha256:<DIGEST> | jq -r '.[0].critical.image'
   ```
   Planification : *Build → Pipeline schedules*, hebdomadaire (lundi 05:17), branche `main`, propriétaire = un compte de service ou toi (un propriétaire bloqué arrête la planification : M19-E41).
5. **Argo CD.** Vault : `argocd_harbor_charts` (`robot$charts+lecture`) ; module `argocd` : `secret_depot_harbor_charts` (Secret `depot-harbor-charts`, `type: helm`, `enableOCI: "true"`, `url: registry.par1.medisphere.internal/charts`, étiquette `argocd.argoproj.io/secret-type=repository`). La racine pour `registry.par1.medisphere.internal` est dans `argocd-tls-certs-cm` depuis E02. AppProject `plateforme` : `sourceRepos` + `registry.par1.medisphere.internal/charts`.
   ```
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer argocd && outils/secrets-k8s.sh verifier argocd
   admin@adm01:~$ argocd repo list
   TYPE  NAME           REPO                                      INSECURE  OCI    LFS    CREDS  STATUS      MESSAGE
   helm  harbor-charts  registry.par1.medisphere.internal/charts  false     true   false  true   Successful
   ```
6. **Multi-sources.**
   ```
   admin@adm01:~/src/gitops$ argocd app create -f essais/essai-multisources.yaml
   admin@adm01:~/src/gitops$ argocd app manifests essai-multisources > ~/m20/e13/rendu-argocd.yaml
   admin@adm01:~/src/gitops$ diff <(yq -P 'sort_keys(..) | del(.metadata.namespace)' ~/m20/e13/rendu-argocd.yaml) \
                                 <(yq -P 'sort_keys(..) | del(.metadata.namespace)' ~/src/mediagenda-deploiement/base/rendu/mediagenda.yaml)
   ```
   Écarts attendus : aucun sur le contenu (même chart, mêmes valeurs, même `releaseName`), seulement l'ordre des objets, les commentaires `# Source:` et, selon le chart, l'espace de noms (Argo CD rend le chart pour l'espace de destination). ⚠️ À vérifier sur ton lab : si un écart de contenu apparaît, il vient d'une valeur qui diffère entre `values-communes.yaml` et la copie, ou de la version de Helm du repo-server (Helm 4 embarqué dans Argo CD 3.5). La vraie différence est **ailleurs** : le rendu commité est lu en MR et la signature du chart est vérifiée par `rendre-base.sh` **avant** le rendu ; le rendu d'Argo CD est produit au moment de la synchronisation, par le repo-server. `argocd app delete essai-multisources` ne supprime rien dans le cluster : rien n'a jamais été synchronisé (et pas de finaliseur).
7. **Décision.** MédiAgenda **garde le rendu commité** (ADR-0170 reconduite) : la MR montre exactement ce qui change dans le cluster ; la signature du chart est vérifiée avant le rendu ; pas de dépendance au repo-server pour rendre un chart ; Kustomize par-dessus (components, livraison). Contre : un rendu de plus à faire et à relire à chaque version du chart. Les **composants tiers** passent par une Application Helm multi-sources : ils viennent avec leurs CRD, leurs hooks, des milliers de lignes qu'on ne relira jamais ligne à ligne ; ce qu'on relit, c'est la **version** (miroir, empreinte) et les **valeurs** (Git).

**Explications**

Le miroir déplace la confiance : au lieu de faire confiance à Internet au moment du déploiement, on fait confiance à une relecture humaine (version et empreinte) faite une fois, en MR, puis à la signature MédiSphère. Argo CD ne voit que Harbor. La planification hebdomadaire rend le miroir **auto-réparant** (un artefact supprimé revient, une signature manquante est ajoutée) sans republier.

**Alternatives**
- *Proxy-cache Harbor pour les charts* : Harbor ne fait pas de cache de dépôts Helm HTTP ; pour un registre OCI amont, un cache tire « à la demande » sans relecture d'empreinte.
- *`helm push` à la main par un administrateur* : pas d'empreinte relue, pas de signature systématique.
- *Vendoring* (archive `.tgz` commitée dans `plateforme/gitops`) : simple, mais des binaires dans Git et aucune signature.
- *Kargo / Renovate* : Renovate peut proposer la montée de version en MR sur `charts.yaml` (avec l'empreinte à relever).

**Pièges classiques**
- `repoURL: oci://registry…/charts` pour une source Helm OCI : Argo CD veut `registry…/charts` (sans schéma) et un dépôt `enableOCI`.
- Oublier d'autoriser `registry.par1.medisphere.internal/charts` dans le projet : « application repo … is not permitted in project ».
- Signer l'étiquette au lieu du digest, ou re-signer à chaque planification (référents en pagaille).
- Mettre le robot d'écriture en variable non protégée « pour que la MR marche » : une MR d'un inconnu pourrait pousser dans `charts/`.
- Une Application d'essai dans `plateforme/` ou `applications/` : la racine la synchroniserait.

**En production chez MédiSphère**

Renovate (M13) propose les montées de `charts.yaml` ; la MR ajoute l'empreinte relevée dans l'index **et** recalculée ; le robot `charts+miroir` (180 jours) est au registre des secrets avec sa date de rotation ; un check vérifie chaque semaine que chaque chart utilisé par une Application est signé.

---

### M20-E14 — Promouvoir une version de dev à la production, et revenir en arrière

**Solution**

Fichiers : [`outils/promouvoir.sh`](fichiers/M20-E14/deploiement/outils/promouvoir.sh), [`promotion.md`](fichiers/M20-E14/medisphere/docs/livraison/gitops/promotion.md) (version complétée après E16 : la fenêtre de retour arrière du Rollout y est citée).

1. **La MR de la CI** (M19-E17) change deux fichiers de `overlays/dev` : l'entrée `images:` (`newTag: vX.Y.Z`, `digest: sha256:…`) et `data.version` de `livraison.yaml`. Vérification :
   ```
   admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true \
       registry.par1.medisphere.internal/medisphere/mediagenda-api@sha256:<DIGEST> >/dev/null && echo signée
   ```
2. **Le script** : chemins permis codés en dur (`dev>recette`, `recette>prod`) ; copie de travail propre et `main` à jour (sinon on promeut depuis un état local) ; source cohérente (`newTag` = version de `livraison.yaml`) ; signature vérifiée **avant** de créer quoi que ce soit ; branche `promotion/<cible>-<version>` refusée si elle existe déjà sur `origin` (une MR est en cours) ; modification par `yq -i` (lignes changées seulement : `kustomize edit set image` réécrit tout le fichier, commentaires déplacés, et la MR devient illisible) ; contrôle du rendu (`kubectl kustomize`, puis `verifier-livraison.sh`) : API **et** Job de migration en `vX.Y.Z@sha256:…` ; en cas d'échec, retour propre sur `main` et branche locale supprimée (piège ERR) ; MR ouverte par les options de `git push` (`merge_request.create`, `.target`, `.title`, `.remove_source_branch`).
3. **Recette.**
   ```
   admin@adm01:~/src/mediagenda-deploiement$ git switch main && git pull --ff-only && outils/promouvoir.sh dev recette
   MR ouverte : promotion(recette): mediagenda-api v1.1.0 depuis dev (promotion/recette-v1.1.0). Fusion par un Maintainer, puis :
     argocd app get mediagenda-recette --refresh   (synchronisation automatique)
   admin@adm01:~$ curl -s https://mediagenda-recette.apps.par1.medisphere.internal/sante
   {"statut":"ok","version":"v1.1.0"}
   ```
   La MR passe par le pipeline de validation de `deploiement` (rendu, schémas, signatures : M19-E29) ; la fusion se fait par **un autre** Maintainer que l'auteur (deux personnes ont lu la promotion).
4. **Prod.** `outils/promouvoir.sh recette prod`, fusion ; `argocd app diff mediagenda-prod` montre exactement l'image (et `MEDIAGENDA_VERSION`, l'étiquette `app.kubernetes.io/version`, le Job de migration) ; `argocd app sync mediagenda-prod`. `argocd app history mediagenda-prod` liste une ligne par synchronisation (ID, date, révision Git) : c'est l'historique **des synchronisations**, pas celui des versions ; la vérité est `git log --first-parent -- overlays/prod`.
5. **Retour arrière.**
   ```
   admin@adm01:~$ argocd app rollback mediagenda-recette 3
   FATA[0000] rpc error: code = FailedPrecondition desc = rollback cannot be initiated when auto-sync is enabled
   admin@adm01:~$ argocd app set mediagenda-recette --sync-policy none
   admin@adm01:~$ sleep 60; argocd app get mediagenda-recette -o json | jq '.spec.syncPolicy.automated'
   {"prune": true, "selfHeal": true}
   ```
   L'ApplicationSet (`create-update`) a réécrit `spec` : la synchronisation automatique est revenue. Même si on y arrivait, un rollback laisserait Git dire autre chose que le cluster : la synchronisation suivante l'annulerait. Le retour se fait donc dans Git :
   ```
   admin@adm01:~/src/mediagenda-deploiement$ git log --first-parent --oneline -3 -- overlays/recette
   a1b2c3d Merge branch 'promotion/recette-v1.1.0' into 'main'
   admin@adm01:~/src/mediagenda-deploiement$ git switch -c retour/recette-v1.1.0 && git revert -m 1 --no-edit a1b2c3d
   admin@adm01:~/src/mediagenda-deploiement$ git push -u origin retour/recette-v1.1.0 -o merge_request.create -o merge_request.target=main
   ```
   Temps typique : 3 à 6 minutes (MR, pipeline de validation, fusion, rafraîchissement d'Argo CD jusqu'à 3 min — le webhook d'E27 le ramènera à quelques secondes —, déploiement). L'ID du `rollback` serait plus rapide ; c'est le prix d'un état décrit par Git.
6. **Re-promotion et documentation.** `outils/promouvoir.sh dev recette` à nouveau (le revert a remis l'ancienne version dans `overlays/recette` : le script voit une différence et crée une nouvelle branche). [`promotion.md`](fichiers/M20-E14/medisphere/docs/livraison/gitops/promotion.md).

**Explications**

Promouvoir un **artefact** et non une **source** : le digest désigne un contenu unique, analysé et signé en amont ; recette et prod reçoivent exactement ce qui a tourné en dev. L'étiquette lisible et le digest bougent ensemble, et le garde-fou du M17 (adapté au M19) le contrôle. Le retour arrière est symétrique : un revert, c'est une promotion de l'état précédent, relue et tracée comme les autres.

**Alternatives**
- *Branche par environnement* (`env/recette`, `env/prod`) : la promotion devient une fusion de branches ; tentant, mais les fusions emportent des changements non voulus (fichiers d'autres overlays) et l'historique devient difficile à lire.
- *La CI qui ouvre aussi les MR de recette et de prod* (job manuel, M19-E17) : équivalent, l'outil est dans la CI plutôt que sur un poste ; les deux coexistent.
- *Kargo* : promotion pilotée par un contrôleur (« freight » qui passe d'étape en étape, vérifications automatiques) ; il écrit dans Git à notre place. Intéressant à grande échelle ; ici, la MR relue suffit.
- *Image Updater d'Argo CD* : met à jour l'image quand une nouvelle étiquette apparaît ; contraire à « une promotion = une décision humaine ».

**Pièges classiques**
- Promouvoir une **étiquette** (`newTag` seul) : quelqu'un repousse `v1.1.0` dans un registre sans immuabilité, et la prod change sans MR.
- Oublier `livraison.yaml` : `verifier-livraison` échoue (étiquette ≠ version), ou pire, sans garde-fou, `MEDIAGENDA_VERSION` ment.
- `git revert <fusion>` sans `-m 1` : « commit … is a merge but no -m option was given ».
- Couper la synchronisation automatique « juste le temps du rollback » : l'ApplicationSet la remet, ou on l'oublie coupée.
- Croire que le revert remet aussi la base : une migration appliquée reste (E20).

**En production chez MédiSphère**

Une promotion en prod porte un numéro de changement (CHG) dans son titre (M20-E29) ; la synchronisation de prod se fait dans une fenêtre ; les indicateurs DORA (M19-E28) comptent une mise en production par fusion dans `overlays/prod` et un échec par revert.

---

### M20-E15 — Argo Rollouts : installer et premier canary

**Solution**

Fichiers : [`espaces/argo-rollouts.yaml`](fichiers/M20-E15/k8s/espaces/argo-rollouts.yaml), [`rbac/wb-checks-livraison.yaml`](fichiers/M20-E15/k8s/rbac/wb-checks-livraison.yaml) (version E15), [`outils_k8s` (extrait)](fichiers/M20-E15/ansible/roles/outils_k8s/defaults/main.extrait-E15.yml), [`plateforme/argo-rollouts.yaml`](fichiers/M20-E15/gitops/plateforme/argo-rollouts.yaml), [`valeurs/argo-rollouts/values.yaml`](fichiers/M20-E15/gitops/valeurs/argo-rollouts/values.yaml), [`racine/plateforme.yaml`](fichiers/M20-E15/gitops/racine/plateforme.yaml), [`projets/plateforme.extrait-E15.yaml`](fichiers/M20-E15/gitops/projets/plateforme.extrait-E15.yaml), `labo` : [`k8s/rollout.yaml`](fichiers/M20-E15/gitops-labo/k8s/rollout.yaml), [`k8s/hpa.yaml`](fichiers/M20-E15/gitops-labo/k8s/hpa.yaml), [`k8s/kustomization.yaml`](fichiers/M20-E15/gitops-labo/k8s/kustomization.yaml), [`labo.extrait-E15.yaml`](fichiers/M20-E15/gitops/applications/labo.extrait-E15.yaml).

1. **Lecture.** Le contrôleur charge ses greffons **au démarrage** (`DownloadPlugins`, avant de démarrer ses boucles) depuis `argo-rollouts-config` (clés `trafficRouterPlugins`, `metricProviderPlugins`, `stepPlugins`) ; il les recopie dans `/home/argo-rollouts/plugin-bin/`, puis les lance comme des processus fils (RPC). `https://` : téléchargement (en-têtes d'authentification possibles depuis un Secret, `headersFrom`), puis, **si** `sha256` est donné, contrôle de l'empreinte — échec = refus. `file://` : simple copie d'un fichier **déjà présent** dans le conteneur, **sans** contrôle d'empreinte (code de `utils/plugin/downloader.go`, v1.10.1 : `sha256` n'est lu que dans la branche `http`/`https`). Greffon introuvable ou téléchargement impossible : le contrôleur s'arrête en erreur au démarrage et redémarre en boucle (`CrashLoopBackOff`) — un greffon déclaré est une dépendance **dure**.
2. **Décision** (à reporter dans l'ADR-0200) :

   | Solution | Intégrité | Mise à jour | Réseau et TLS | Effort |
   |---|---|---|---|---|
   | **Image officielle du greffon** par le cache Harbor `ghcr`, **épinglée par digest**, conteneur d'initialisation qui copie le binaire dans un volume ; `file://` | digest de l'image (contenu immuable, relu en MR) | changer étiquette + digest dans les valeurs | aucun nouveau flux (le cache Harbor sert déjà les images) ; pas de TLS à configurer dans le contrôleur | faible |
   | Binaire servi en HTTPS par un serveur interne (`s3-01` en lecture publique, ou blob OCI de Harbor avec `headersFrom`) ; `https://` + `sha256` | empreinte vérifiée par le contrôleur à chaque démarrage | déposer le binaire, changer URL et empreinte | le contrôleur (Go, image distroless) doit faire confiance à la racine MédiSphère (`SSL_CERT_FILE`, volume) ; compartiment public ou jeton à gérer | moyen |
   | Image maison construite par la CI (`ADD --checksum=sha256:…` du binaire de la version) | empreinte contrôlée à la construction, image signée MédiSphère | reconstruire à chaque version | aucun | moyen (une image de plus à maintenir) |
   | URL GitHub + `sha256` | empreinte | changer URL et empreinte | **impossible** : le cluster ne sort pas vers GitHub | — |

   **Retenu** : l'image officielle par le cache Harbor, épinglée par digest (`v0.17.0@sha256:bc40d5ed…19d4a2`), méthode documentée par le projet du greffon (« *Installing the plugin via init containers* »). L'intégrité ne repose pas sur `sha256` du contrôleur (ignoré en `file://`) mais sur le digest de l'image, comme pour toutes les images du cluster. Le binaire de l'image n'est **pas** celui des *releases* GitHub (empreintes différentes : construit séparément, `-ldflags "-s -w"`) : ne pas comparer les deux. ⚠️ À vérifier sur ton lab : la VAP `medisphere-images` (M14-E18) vise les espaces des équipes ; si elle s'applique aussi à `argo-rollouts`, l'image du cache `ghcr` avec digest la satisfait.
3. **Plateforme.** Espace (`task appliquer`), `wb-checks-livraison` (bloc M20-E15), `kubectl-argo-rollouts` (binaire nu, comme `argocd` en E03 ; empreinte `fb28a5ba…b92cd`, ligne de `argo-rollouts-checksums.txt` de la v1.10.1).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/adm01.yml --tags outils_k8s --diff
   admin@adm01:~$ kubectl argo rollouts version
   kubectl-argo-rollouts: v1.10.1+356117c
   ```
4. **Valeurs et Application.** Voir [`values.yaml`](fichiers/M20-E15/gitops/valeurs/argo-rollouts/values.yaml) : image du contrôleur par le cache `quay` épinglée (`tag: v1.10.1@sha256:…`, le chart compose `registre/dépôt:étiquette`) ; 2 réplicas (élection d'un chef) ; ressources ; conteneur d'initialisation `copie-greffon-gatewayapi` (sécurité complète : le chart n'applique pas son `containerSecurityContext` aux conteneurs ajoutés, et `restricted` le refuserait) ; volume `greffons` (`emptyDir`) monté dans les deux conteneurs ; `trafficRouterPlugins: [{name: argoproj-labs/gatewayAPI, location: file:///greffons/rollouts-plugin-trafficrouter-gatewayapi}]` ; `providerRBAC` réduit à `gatewayAPI` (règles `httproutes` … `get, list, watch, update`) ; pas de tableau de bord. L'Application est multi-sources (chart de Harbor à `2.43.8`, valeurs `$values/valeurs/argo-rollouts/values.yaml`), projet `plateforme`, `ServerSideApply=true` (CRD trop grosses pour l'annotation `last-applied-configuration`). Le groupe `racine/plateforme.yaml` lit `plateforme/` sans récursion : `valeurs/` n'est jamais appliqué comme manifeste.
   ```
   admin@adm01:~/src/gitops$ helm template argo-rollouts oci://registry.par1.medisphere.internal/charts/argo-rollouts --version 2.43.8 \
       -n argo-rollouts -f valeurs/argo-rollouts/values.yaml | yq 'select(.kind == "ConfigMap" and .metadata.name == "argo-rollouts-config")'
   data:
     trafficRouterPlugins: |-
       - location: file:///greffons/rollouts-plugin-trafficrouter-gatewayapi
         name: argoproj-labs/gatewayAPI
   ```
5. **Contrôle.**
   ```
   admin@adm01:~$ argocd app get argo-rollouts | grep -E 'Sync Status|Health Status'
   admin@adm01:~$ kubectl -n argo-rollouts get pods
   admin@adm01:~$ kubectl -n argo-rollouts logs deploy/argo-rollouts | grep -i plugin
   … level=info msg="Copied plugin from /greffons/rollouts-plugin-trafficrouter-gatewayapi to /home/argo-rollouts/plugin-bin/argoproj-labs/gatewayAPI"
   ```
   (Message du code de la 1.10 ; ⚠️ le chemin exact du dossier du greffon dans `plugin-bin/` est à lire sur ton lab.)
6. **Canary sur labo.** Le Rollout reprend **exactement** le gabarit de pod du Deployment d'E04 ; pas de `replicas` (HPA) ; le HPA vise `argoproj.io/v1alpha1` `Rollout` (le Rollout expose la sous-ressource `scale`) ; `applications/labo.yaml` ignore `/spec/replicas` du Rollout (et plus du Deployment). À la fusion, `prune` supprime le Deployment, le Rollout crée ses pods : quelques secondes de coupure, assumées sur le banc. Nouvelle version (`1.30.6-alpine` → `1.31.7-alpine` dans `k8s/rollout.yaml`, MR) :
   ```
   admin@adm01:~$ kubectl argo rollouts get rollout labo -n wb-essais --watch
   Name:            labo
   Status:          ॥ Paused
   Message:         CanaryPauseStep
   Strategy:        Canary
     Step:          1/6
     SetWeight:     25
     ActualWeight:  25
   …
   admin@adm01:~$ kubectl argo rollouts promote labo -n wb-essais
   ```
   Avec 2 pods (HPA au repos), 25 % donne 1 pod canary (arrondi au supérieur) à côté de pods stables : la part réelle du trafic est d'environ **un tiers**, pas 25 % — c'est la limite d'un canary par réplicas. ⚠️ À vérifier sur ton lab : le nombre exact de pods stables gardés à chaque marche dépend de `maxSurge` et `maxUnavailable` (défauts 25 %) et des arrondis (`kubectl argo rollouts get` affiche `ActualWeight`). `curl -sI` sur le Service montre alternativement `Server: nginx/1.30.6` et `1.31.7`. Second canary puis `abort` : le Rollout revient à la version stable (pods canary supprimés), son état est `Degraded` (« RolloutAborted ») ; l'Application `labo` est **Degraded** dans Argo CD (santé du Rollout) mais `Synced` (le gabarit dans le cluster est bien celui de Git). Sortie : remettre l'ancienne image **dans Git** (revert), ce qui rend la révision stable de nouveau désirée (le Rollout redevient `Healthy` sans redéployer), ou corriger et `kubectl argo rollouts retry rollout labo -n wb-essais`.

**Explications**

Argo Rollouts remplace le contrôleur de Deployment pour les charges qui le demandent : mêmes ReplicaSets, mais une progression pilotée par des marches, des pauses et des analyses. Le canary **par réplicas** ne contrôle le trafic que par le rapport du nombre de pods ; le canary **par routage** (E16) règle des poids indépendamment du nombre de pods. Les greffons étendent le contrôleur sans le recompiler, au prix d'un binaire à fournir au démarrage : c'est une dépendance d'exécution, à traiter comme une image.

**Alternatives**
- *Installer Argo Rollouts par Helmfile* (comme la couche de base) : il ne fait pas tourner Argo CD, rien ne l'impose ; PLAN §4.11 le place côté Argo CD.
- *Manifestes `install.yaml` amont* recopiés : pas de valeurs, une mise à jour = un gros fichier à relire.
- *Rollout par `workloadRef`* sur labo aussi : sans coupure, mais E16 le fait sur MédiAgenda ; ici on voit la conversion directe.

**Pièges classiques**
- Un emplacement `https://github.com/…` qui « marche sur le poste » : le contrôleur boucle au démarrage dans le cluster.
- Croire que `sha256` protège un greffon `file://` : il n'est pas lu.
- Garder `spec.replicas` dans le Rollout **et** un HPA sans `ignoreDifferences` : yo-yo, comme en E12.
- Oublier `ServerSideApply=true` : « metadata.annotations: Too long » sur les CRD.
- `kubectl argo rollouts` absent : `kubectl` répond « unknown command "argo" ».

**En production chez MédiSphère**

Les versions du contrôleur et du greffon montent ensemble, par une MR qui change `charts.yaml` (miroir), `targetRevision`, et les deux digests ; la note de version du greffon est lue (compatibilité avec la version de la Gateway API, v1.6). Le contrôleur exporte ses métriques au M21 (`controller.metrics.enabled`).

---

### M20-E16 — Canary piloté par la Gateway API

**Solution**

Fichiers : [`components/canary/`](fichiers/M20-E16/deploiement/components/canary/) (`kustomization.yaml`, `rollout.yaml`, `service-canary.yaml`, version E16), overlays [`recette`](fichiers/M20-E16/deploiement/overlays/recette/kustomization.yaml) et [`prod`](fichiers/M20-E16/deploiement/overlays/prod/kustomization.yaml).

1. **Lecture.** À sa création, un Rollout n'a pas de version stable : sa **première** révision est déployée d'un coup, sans marches (« initial deploy »). Avec `workloadRef` et `scaleDown: progressively`, chaque pod prêt du Rollout fait retirer un pod au Deployment, jusqu'à 0. Ensuite, Argo Rollouts ajoute `rollouts-pod-template-hash` au sélecteur des Services `mediagenda` (révision stable) et `mediagenda-canary` (révision canary), et le greffon règle les **poids** des deux `backendRefs` de l'HTTPRoute (et pose une étiquette temporaire `rollouts.argoproj.io/gatewayapi-canary` pendant un canary). Sans E12, Argo CD verrait le Deployment à 0 alors que Git dit 2 (et `selfHeal` le remonterait : deux jeux de pods), et les poids changer à chaque marche (et les remettrait à 100/0 : canary annulé à chaque réconciliation).
2. **Component.** `rollout.yaml` : `workloadRef`, sélecteur du chart (`name`, `instance`, `component: api`), `stableService`/`canaryService`, `trafficRouting.plugins.argoproj-labs/gatewayAPI.httpRoute: mediagenda` (espace : celui du Rollout par défaut), marches, `maxSurge: 25%`/`maxUnavailable: 0`, `progressDeadlineSeconds`, `rollbackWindow.revisions: 2`. `service-canary.yaml` : copie du Service du chart. Correctif de l'HTTPRoute : `replace` de `/spec/rules/0/backendRefs` par `mediagenda` (100) et `mediagenda-canary` (0). Prod : correctif de l'overlay (3 réplicas — le transformateur `replicas:` ignore le type `Rollout` — et une marche finale `pause: {}` ajoutée par `/spec/strategy/canary/steps/-`).
   ```
   admin@adm01:~/src/mediagenda-deploiement$ kubectl kustomize overlays/recette | kubectl argo rollouts lint -f -
   Error: spec.strategy.canary.stableService: Invalid value: "mediagenda": Service "mediagenda" has unmatch label "app.kubernetes.io/component" in rollout
   ```
   Le linter compare les sélecteurs des Services au gabarit **du Rollout** ; avec `workloadRef`, le gabarit est dans le Deployment et le linter ne le suit pas : faux positif, constaté à la rédaction (en recopiant le gabarit du Deployment dans le Rollout, le lint passe). Il reste utile pour la syntaxe des marches et des analyses.
3. **Reprise.** [`sonde.sh`](fichiers/M20-E16/essais/sonde.sh), posé dans `~/m20/e16/` (bilan par version à Ctrl-C) :
   ```
   admin@adm01:~/m20/e16$ ./sonde.sh https://mediagenda-recette.apps.par1.medisphere.internal/sante | tee sonde-reprise.log
   ```
   Pendant la synchronisation de la MR 1 : 2 pods du Rollout démarrent à côté des 2 du Deployment ; dès qu'ils sont prêts, le Deployment descend à 0 (`kubectl get deploy mediagenda -n mediagenda-recette` : `0/0`). Résultat attendu de la sonde : **0 échec**. ⚠️ À vérifier sur ton lab : la bascule du sélecteur du Service se fait quand la première révision est disponible ; une requête en vol au moment où un pod du Deployment s'arrête est servie jusqu'au bout (arrêt propre d'uvicorn, `terminationGracePeriodSeconds: 30`).
4. **Canary.** Après une promotion (E14), à la marche 10 % :
   ```
   admin@adm01:~$ kubectl get httproute mediagenda -n mediagenda-recette -o jsonpath='{range .spec.rules[0].backendRefs[*]}{.name}={.weight} {end}{"\n"}'
   mediagenda=90 mediagenda-canary=10
   admin@adm01:~$ kubectl get svc mediagenda mediagenda-canary -n mediagenda-recette -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.selector.rollouts-pod-template-hash}{"\n"}{end}'
   ```
   La sonde montre environ une réponse sur dix avec la nouvelle version, puis une sur quatre, une sur deux. Avec 2 réplicas, le canary a 1 pod dès 10 % (arrondi au supérieur) et la stable garde ses 2 pods : le **trafic** est de 10 %, indépendamment du nombre de pods — c'est l'apport du routage. L'Application reste **Synced** pendant tout le canary (champs ignorés), sa santé passe par `Suspended` pendant les pauses (santé du Rollout en pause), puis `Healthy`.
5. **Retour arrière** (revert de la promotion) : la révision visée est la précédente, dans la fenêtre `rollbackWindow` : le Rollout la promeut **sans marches** (une minute environ, le temps des pods). Hors fenêtre (ou sans le réglage), il refait les marches complètes — pour un retour d'urgence, c'est trop lent.
6. **Prod.** MR 2 (component, correctif de prod), `argocd app diff mediagenda-prod`, `argocd app sync mediagenda-prod` (sonde sur `https://mediagenda.apps.par1.medisphere.internal/sante` : 0 échec), puis promotion `recette → prod`, synchronisation, marches jusqu'à la pause finale : santé `Suspended` dans Argo CD, `Paused` dans `kubectl argo rollouts get` (« CanaryPauseStep »), 50 % du trafic sur la nouvelle version. `kubectl argo rollouts promote mediagenda -n mediagenda-prod` : 100 %, l'ancienne révision est réduite.

**Explications**

Le greffon traduit les marches en poids de la Gateway : Envoy (Gateway Cilium) répartit le trafic selon ces poids. Argo Rollouts et Argo CD se partagent des objets : Argo CD décrit, Argo Rollouts règle des champs précis pendant un déploiement ; la frontière est écrite dans `ignoreDifferences`. `workloadRef` garde le chart intact et permet un retour au Deployment sans réécriture (il suffit de retirer le Rollout et de rendre ses réplicas au Deployment).

**Alternatives**
- *Convertir le Deployment en Rollout* dans le rendu (correctif de type) : un objet de moins, mais on modifie la sortie du chart et le retour en arrière est une migration inverse.
- *Canary par réplicas* sur MédiAgenda : avec 2 ou 3 pods, impossible de faire 10 %.
- *Routage par Cilium natif* : Argo Rollouts n'a pas de routeur Cilium (PLAN §6) ; Gateway API est le chemin standard.
- *`dynamicStableScale: true`* : la stable réduit ses pods à mesure que le canary monte (économie de ressources, retour arrière plus lent).

**Pièges classiques**
- Un seul `backendRef` dans l'HTTPRoute : le greffon ne sait pas où mettre le poids canary.
- Pas de `ignoreDifferences` sur les poids : Argo CD remet 100/0 pendant le canary (panne d'E40).
- Sélecteur du Rollout différent de celui du Deployment : le Rollout ne « voit » pas ses pods, ou le PDB ne les couvre pas.
- Oublier que le Deployment **reste** (à 0) : supprimer le Deployment supprime la référence du Rollout (pods intacts, mais plus de nouvelles révisions).
- `kubectl argo rollouts lint` rouge avec `workloadRef` : faux positif, pas une erreur.

**En production chez MédiSphère**

La pause finale de prod est franchie par la personne de garde du changement (CHG), après lecture des analyses (E18) et des tableaux de bord (M21). Le greffon est suivi : ses journaux (processus fils du contrôleur) vont dans Loki au M22.

---

### M20-E17 — Blue/green avec aperçu et promotion manuelle

**Solution**

Fichiers : [`valeurs/argo-rollouts/values.yaml`](fichiers/M20-E17/gitops/valeurs/argo-rollouts/values.yaml) (version E17), `labo` : [`k8s/rollout.yaml`](fichiers/M20-E17/gitops-labo/k8s/rollout.yaml), [`k8s/service-apercu.yaml`](fichiers/M20-E17/gitops-labo/k8s/service-apercu.yaml), [`k8s/kustomization.yaml`](fichiers/M20-E17/gitops-labo/k8s/kustomization.yaml).

1. **Lecture.** Pendant un blue/green, la nouvelle révision démarre **avec tous ses pods** à côté de l'ancienne : avec le HPA de labo au repos (2 pods), 4 pods ; jusqu'à 8 si le HPA était au maximum. `scaleDownDelaySeconds` garde l'ancienne révision active pendant ce délai après la bascule : un `undo` rebascule le Service sans attendre de pods. Si l'analyse d'aperçu échoue, la révision est interrompue (`Degraded`) et le Service actif ne bascule pas.
2. **Gabarit de cluster.** Rendu local : `Error: … function "args" not defined`. `extraObjects` passe par `tpl` : `{{args.url}}` est lu par Helm. Échappement : `url: '{{ "{{args.url}}" }}'` (Helm rend `{{args.url}}`). Le gabarit `pret-http` : `count: 3`, `interval: 10s`, `consecutiveErrorLimit: 2` (plus de deux erreurs de suite → `Error`), pas de `jsonPath` (page HTML : succès si 2xx).
3. **Blue/green.** Stratégie `blueGreen` (`activeService: labo`, `previewService: labo-apercu`, `autoPromotionEnabled: false`, `prePromotionAnalysis` avec `clusterScope: true`, argument `url: http://labo-apercu.wb-essais.svc.cluster.local/`, `scaleDownDelaySeconds: 120`). Changer de stratégie ne recrée rien. Nouvelle version :
   ```
   admin@adm01:~$ kubectl argo rollouts get rollout labo -n wb-essais --watch
   Status:          ॥ Paused
   Message:         BlueGreenPause
   Strategy:        BlueGreen
   …
   ⟳ labo                            Rollout     ॥ Paused
   ├──# revision:4
   │  ├──⧉ labo-6f7c9d…              ReplicaSet  ✔ Healthy  preview
   │  └──α labo-6f7c9d…-4-pre        AnalysisRun ✔ Successful
   └──# revision:3
      └──⧉ labo-5b8d…                ReplicaSet  ✔ Healthy  stable,active
   admin@adm01:~$ kubectl -n wb-essais port-forward svc/labo-apercu 8081:80 & curl -sI localhost:8081 | grep Server
   Server: nginx/1.31.7
   admin@adm01:~$ kubectl argo rollouts promote labo -n wb-essais
   ```
   ⚠️ Ordre exact à vérifier sur ton lab : l'analyse d'aperçu est lancée quand l'aperçu est prêt, et la promotion manuelle n'est possible qu'après elle (sinon le Rollout attend la fin de l'analyse). La bascule est instantanée (changement du sélecteur du Service) : la boucle sur le Service actif passe d'une version à l'autre sans échec.
4. **Undo** dans les 2 minutes : `kubectl argo rollouts undo labo -n wb-essais` rebascule sur l'ancienne révision encore en place. Mais Git désigne toujours la nouvelle image : le Rollout a son gabarit modifié par `undo` → l'Application `labo` est `OutOfSync`, et **`selfHeal` remet la nouvelle version** dès la réconciliation suivante (nouveau blue/green). Le seul retour durable est un revert dans Git ; `undo` n'est qu'un geste d'urgence, suivi aussitôt du revert.
5. **Aperçu en échec.** Méthode retenue : une révision dont la **sonde de disponibilité** ne regarde pas ce que servent les utilisateurs — la page vient d'une nouvelle ConfigMap `labo-page-v2` qui ne contient que `sante.html` (pas d'`index.html` : nginx répond 403 sur `/`, le volume masque tout le dossier de l'image), et la sonde, modifiée dans la même révision, vise `/sante.html` (200). Les pods de l'aperçu sont prêts, l'analyse `pret-http` mesure 403 trois fois → `Error` → révision interrompue, le Service actif n'a jamais basculé. (Une image absente du cache ne testerait pas l'analyse : les pods ne seraient jamais prêts et le Rollout attendrait jusqu'à `progressDeadlineSeconds`.) Leçon : une sonde de disponibilité n'est pas un test fonctionnel ; l'analyse d'aperçu l'est. Rétablir : revert.

**Explications**

Blue/green et canary répondent à deux questions différentes. Canary : « la nouvelle version tient-elle sous une **part** du trafic réel ? » (exposition progressive, coût faible). Blue/green : « la nouvelle version est-elle **entièrement** prête avant d'exposer qui que ce soit ? » (bascule atomique, retour instantané, coût double en pods). Le gabarit de cluster évite de recopier la même analyse générique dans chaque équipe.

**Alternatives**
- `postPromotionAnalysis` : vérifier après la bascule, avec retour automatique (si `scaleDownDelaySeconds` n'est pas écoulé).
- `autoPromotionSeconds` : promotion automatique après un délai.
- Une HTTPRoute d'aperçu publiée (`labo-apercu.apps…`) pour une validation humaine dans le navigateur.

**Pièges classiques**
- Oublier l'échappement des accolades dans `extraObjects` : rendu Helm en échec (Argo CD montre une `ComparisonError` sur `argo-rollouts`).
- Prendre `undo` pour un retour arrière : Argo CD le défait.
- Un blue/green sous quota serré : la seconde révision complète ne tient pas (pods `Pending`, `exceeded quota`).
- Un aperçu dont l'URL d'analyse passe par la Gateway publique : on teste la route active, pas l'aperçu.

**En production chez MédiSphère**

Blue/green réservé aux changements « tout ou rien » (montée de version majeure d'une dépendance, changement de configuration non progressif) et aux applications qui supportent deux versions complètes à la fois (quota prévu). Canary par défaut pour MédiAgenda.

---

### M20-E18 — Analyses : tests de fumée et requêtes web

**Solution**

Fichiers : [`components/canary/`](fichiers/M20-E18/deploiement/components/canary/) (version E18 : `analyses.yaml`, `reseau-analyses.yaml`, `rollout.yaml`, `kustomization.yaml`), [`matrice-flux-cluster.extrait-E18.md`](fichiers/M20-E18/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.extrait-E18.md).

1. **Lecture.** Mesure en **échec** : une réponse a été obtenue et la condition d'échec est vraie (ou la condition de succès fausse) ; compte pour `failureLimit`. Mesure en **erreur** : pas de réponse exploitable (code HTTP hors 2xx, délai, JSON sans le chemin) ; compte pour `consecutiveErrorLimit` (4 par défaut). Analyse terminée `Failed` ou `Error` : le Rollout est **interrompu** (poids remis à 0, pods canary réduits, `Degraded`) ; `Inconclusive` : le Rollout se met en **pause** et attend un humain. Les comparaisons sont strictes : `failureLimit: 1` tolère un échec et s'arrête au deuxième.
2. **Gabarits et branchement.** [`analyses.yaml`](fichiers/M20-E18/deploiement/components/canary/analyses.yaml) : `fumee-mediagenda` (`count: 1`, `failureLimit: 0`, Job `backoffLimit: 0`, `activeDeadlineSeconds: 180`, `curl` sur `mediagenda-canary.<espace>.svc.cluster.local` : `/sante`, `/pret` avec `"statut":"pret"`, `/api/v1/creneaux?date=<demain>`, pod `restricted` avec `runAsUser: 100`, requêtes et limites, étiquette `medisphere.internal/role: analyse`) ; `pret-mediagenda` (`interval: 20s`, `jsonPath: "{$.statut}"`, `successCondition: result == "pret"`, `failureLimit: 1`, `consecutiveErrorLimit: 2`). Rollout : `analysis` de fond (`startingStep: 0`) et une marche `analysis` après `setWeight: 10` ; argument `espace` par `valueFrom.fieldRef.fieldPath: metadata.namespace` (le même component sert recette et prod). [`reseau-analyses.yaml`](fichiers/M20-E18/deploiement/components/canary/reseau-analyses.yaml) : entrée de l'API depuis les pods `role: analyse` et depuis le contrôleur (`namespaceSelector` `kubernetes.io/metadata.name: argo-rollouts` + `app.kubernetes.io/name: argo-rollouts`) ; sorties des pods d'analyse vers DNS et l'API (indispensable en prod, refus par défaut).
3. **Canary avec analyses.**
   ```
   admin@adm01:~$ kubectl get analysisrun,job -n mediagenda-recette
   NAME                                               STATUS       AGE
   analysisrun.argoproj.io/mediagenda-7d9f…-5         Running      40s     # fond : pret-mediagenda
   analysisrun.argoproj.io/mediagenda-7d9f…-5-1       Successful   25s     # marche : fumee-mediagenda
   NAME                                       STATUS     COMPLETIONS
   job.batch/…-fumee-…                        Complete   1/1
   admin@adm01:~$ kubectl logs -n mediagenda-recette job/<JOB-DE-FUMEE>
   tests de fumée sur http://mediagenda-canary.mediagenda-recette.svc.cluster.local
   {"statut":"ok","version":"v1.1.0"}
   fumée : OK
   ```
4. **Échec provoqué** (correctif de l'overlay recette) :
   ```yaml
   - target: {group: apps, kind: Deployment, name: mediagenda}
     patch: |-
       apiVersion: apps/v1
       kind: Deployment
       metadata: {name: mediagenda}
       spec:
         template:
           spec:
             containers:
               - name: api
                 env:
                   - name: MEDIAGENDA_VALKEY_URL
                     value: redis://valkey-absent:6379/0
   ```
   Nouvelle révision : les pods canary démarrent, mais `/pret` répond **503** (Valkey injoignable) → jamais prêts → ils ne sont pas derrière `mediagenda-canary`. `pret-mediagenda` (lancée dès la marche 0) ne reçoit pas de réponse 2xx : **erreurs** de mesure ; à la troisième de suite (`consecutiveErrorLimit: 2`), environ 60 s plus tard, l'AnalysisRun termine en `Error` et le Rollout est **interrompu** (`RolloutAborted`, poids canary 0). Les utilisateurs n'ont rien vu : le canary n'a jamais reçu de trafic (pods non prêts) et la stable a gardé ses pods (`maxUnavailable: 0`) ; la sonde d'E16 reste sans échec. Le Rollout est `Degraded`, l'Application `mediagenda-recette` `Synced`/`Degraded` (courriel d'E19 si elle est déjà faite). ⚠️ À vérifier sur ton lab : la marche `setWeight: 10` attend-elle des pods canary prêts avant de poser le poids ? (la fumée, elle, n'est jamais atteinte).
5. **Rétablissement** : revert par MR. Le gabarit redevient celui de la révision stable : le Rollout revient `Healthy` sans redéployer (la révision stable est déjà en place). L'AnalysisRun en `Error` reste (historique `unsuccessfulRunHistoryLimit`, 5 par défaut).

**Explications**

Deux analyses complémentaires : la fumée, **ponctuelle et bloquante**, vérifie que la nouvelle version fonctionne avant de lui donner plus de trafic ; l'analyse de fond **surveille** pendant tout le canary et interrompt dès que la nouvelle version se dégrade. Toutes deux visent le Service **canary** : mesurer le Service stable ne dirait rien de la nouvelle version. Le contrôleur exécute lui-même les mesures `web` : c'est lui qu'il faut laisser entrer.

**Alternatives**
- *Analyse Prometheus* (taux d'erreur du canary, M21) : la vraie mesure d'une régression sous trafic réel ; `/pret` ne voit que les dépendances.
- *Job de tests plus complet* (création puis suppression d'un rendez-vous) : écrit dans la base de recette, acceptable ; en prod, réservé à un praticien de test.
- *`dryRun`* sur une nouvelle métrique pour roder ses seuils.

**Pièges classiques**
- Analyse sur le Service stable : toujours verte, même si le canary est cassé.
- Oublier les politiques réseau : mesures en erreur dès la première, canary interrompu à chaque fois (« le canary ne marche jamais »).
- `runAsNonRoot` avec une image à utilisateur nommé : `CreateContainerConfigError` (« image has non-numeric user »).
- Confondre erreur et échec : régler `failureLimit` et s'étonner que le Rollout s'arrête sur des erreurs.
- Supprimer les AnalysisRuns en échec « pour nettoyer » : on perd la preuve du diagnostic.

**En production chez MédiSphère**

Les mêmes analyses tournent en prod (même component). Le M21 ajoute `taux-erreur-mediagenda` (PromQL sur `mediagenda_http_requests_total{code=~"5.."}` du canary) en analyse de fond, d'abord en `dryRun` une semaine.

---

### M20-E19 — Notifications d'Argo CD

**Solution**

Fichiers : [`values.extrait-E19.yaml`](fichiers/M20-E19/k8s/composants/argocd/values.extrait-E19.yaml), [`projets/mediagenda.extrait-E19.yaml`](fichiers/M20-E19/gitops/projets/mediagenda.extrait-E19.yaml), [`projets/plateforme.extrait-E19.yaml`](fichiers/M20-E19/gitops/projets/plateforme.extrait-E19.yaml), [`applications/mediagenda.yaml`](fichiers/M20-E19/gitops/applications/mediagenda.yaml) (version E19).

1. **Lecture.** `oncePer` : le déclencheur n'envoie qu'une fois par valeur de l'expression (ici, la révision synchronisée) : un `Degraded` qui dure ne produit pas un courriel par réconciliation. `on-deployed` doit distinguer « synchronisé et sain **grâce à** cette synchronisation » de « synchronisé, et sain depuis longtemps » : il compare le dernier passage à `Healthy` aux dates de début et de fin de l'opération (catalogue d'Argo CD, repris tel quel).
2. **Configuration** (voir l'extrait) : `service.email` (`host`, `port: 25`, `from`, sans `username`/`password` : Mailpit n'en demande pas), trois déclencheurs (conditions du catalogue), trois modèles en français (sujet `[Argo CD] …`, corps avec révision, message, ressources dégradées, lien `{{.context.argocdUrl}}/applications/argocd/<app>`, renvoi au RB-200), `argocdUrl`. Confiance TLS : `SSL_CERT_FILE=/etc/ssl/medisphere/medisphere-root-ca.crt`, fichier monté depuis `argocd-tls-certs-cm` (clé `git01.par1.medisphere.internal`, `items`). `SSL_CERT_FILE` remplace le magasin du système : sans effet de bord ici (le contrôleur ne parle qu'à Mailpit et à l'API Kubernetes, qui a sa propre autorité).
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff && helmfile -e par1 -l composant=argocd apply
   admin@adm01:~$ argocd admin notifications trigger get -n argocd
   NAME                PRECONDITION                                         TEMPLATE
   on-deployed         app.status.operationState != nil and …               [deploye]
   on-health-degraded  app.status.health.status == 'Degraded'               [sante-degradee]
   on-sync-failed      app.status.operationState != nil and app.status…     [synchro-en-echec]
   ```
3. **Abonnements.** AppProjects `mediagenda` et `plateforme` (annotations `notifications.argoproj.io/subscribe.<déclencheur>.email`), et `on-deployed` sur `mediagenda-prod` seulement, par un bloc `{{- if eq .env "prod" }} metadata: annotations: …` du `templatePatch` (le contrôleur de l'ApplicationSet préserve en plus l'annotation `notified.notifications.argoproj.io`, qui mémorise ce qui a déjà été envoyé).
4. **Essais.** Depuis le pod du contrôleur, parce que la commande exécute la notification **là où elle tourne** : sur `adm01`, elle partirait de MGMT (qui joint tout le lab, M00) avec le magasin de certificats d'`adm01`, qui contient déjà la racine MédiSphère : l'essai réussirait sans rien prouver. Dans le pod, elle emprunte le vrai chemin du contrôleur : `K8S_TRAV` → `mon01:25` (flux du M19), sa variable `SSL_CERT_FILE`, sa configuration lue dans le cluster.
   ```
   admin@adm01:~$ kubectl -n argocd exec deploy/argocd-notifications-controller -- \
       argocd admin notifications template notify sante-degradee mediagenda-dev --recipient email:plateforme@medisphere.internal
   ```
   Échec de synchronisation provoqué en dev : le plus sûr est de rejouer l'échec du Job de migration d'E11 (base inexistante) : opération `Failed`, un courriel (deux destinataires), puis revert. Un manifeste invalide (`cpu: "beaucoup"`) ne convient pas : avec le diff côté serveur (E05), le refus de l'API apparaît dès la **comparaison** (`ComparisonError`), aucune synchronisation n'est tentée, donc pas de `on-sync-failed`. Mise en production : une promotion en prod (E14) → un courriel « mediagenda-prod déployée ». Un message par événement et par révision, grâce à `oncePer` ; avec les réessais (`retry: 3`) d'une synchronisation en échec, toujours un seul.
5. **Diagnostic.** Sans `SSL_CERT_FILE` :
   ```
   admin@adm01:~$ kubectl -n argocd logs deploy/argocd-notifications-controller | grep -i smtp
   … level=error msg="Failed to notify recipient {email plateforme@medisphere.internal} …: x509: certificate signed by unknown authority"
   ```
   ⚠️ À vérifier sur ton lab : le texte exact. Corriger par la racine, jamais par `insecure_skip_verify: true` (le check le refuse). Vérifier aussi le nom : le certificat de Mailpit doit porter `smtp.par1.medisphere.internal` (M19-E03).

**Explications**

Les notifications sont des **déclencheurs** (une condition sur l'état d'une Application) reliés à des **modèles** (le message) et à des **services** (le canal), activés par des **abonnements** (annotations). L'abonnement au niveau du projet suit l'équipe, celui de l'Application suit un environnement. Rien n'est envoyé sans abonnement : un déclencheur défini n'abonne personne.

**Alternatives**
- `subscriptions` globales dans `argocd-notifications-cm` (avec `selector` d'étiquettes) : un seul endroit, mais l'équipe ne voit plus ses abonnements dans son projet.
- Service `webhook` vers l'Alertmanager témoin (M21) : regroupement, silences, astreinte.
- Notifications d'**Argo Rollouts** (contrôleur propre, `argo-rollouts-notification-configmap`) : marches, interruptions — complémentaires.

**Pièges classiques**
- Croire que le chart installe le catalogue : aucun déclencheur, aucun courriel, aucune erreur.
- `insecure_skip_verify: true` pour « débloquer » : la vérification TLS saute pour toujours.
- S'abonner à `on-sync-succeeded` sur dev : un courriel par commit.
- Oublier `argocdUrl` : liens vides dans les messages.

**En production chez MédiSphère**

Les échecs et dégradations de prod vont aussi à l'astreinte par l'Alertmanager (M21, webhook) ; les adresses sont des listes (`plateforme@`, `astreinte@`), jamais des personnes seules (départs, congés).

---

### M20-E20 — Questions : stratégies de déploiement

1. **Recreate** arrête toutes les anciennes instances avant de démarrer les nouvelles (coupure). C'est le seul choix correct quand deux versions **ne peuvent pas** tourner ensemble : un processus qui prend un verrou exclusif sur une ressource partagée, un volume `ReadWriteOnce` monté par un seul pod (Valkey persistant de recette, M16 : un RollingUpdate resterait bloqué, le nouveau pod ne pouvant monter le volume), un changement de format de données incompatible. Legacy-RDV (PHP, sessions sur disque) en est un autre exemple. RollingUpdate suppose deux versions **compatibles** simultanément.
2. Non. Ce RollingUpdate est **progressif en capacité** (jamais moins de pods prêts) mais pas en **exposition** : chaque nouveau pod reçoit sa part de trafic dès qu'il est prêt, sans pause, sans mesure, sans arrêt automatique ; le PDB ne protège que contre les évictions volontaires. Il manque : des marches, des pauses, des analyses qui interrompent et un retour automatique.
3. Par réplicas (labo) : 10 % de 2 pods = 1 pod canary (arrondi) à côté des stables, soit un tiers à la moitié du trafic selon les pods stables gardés — impossible de faire 10 %. Par routage (MédiAgenda) : le poids de l'HTTPRoute fixe **10 %** du trafic, quel que soit le nombre de pods (1 pod canary suffit). Pour une petite application, seul le routage permet une exposition fine.
4. Canary : coût faible (quelques pods en plus), exposition progressive, retour rapide (poids à 0, ou fenêtre de retour arrière), mais deux versions servent en même temps pendant des minutes (compatibilité exigée). Blue/green : coût double (3 + 3 pods en prod : vérifier le quota de `mediagenda-prod`, 4 CPU de requêtes), validation complète avant toute exposition, bascule et retour instantanés tant que l'ancienne révision est gardée, mais 100 % des utilisateurs basculent d'un coup. Pour MédiAgenda, canary (exposition mesurée, coût), blue/green réservé aux changements non progressifs.
5. *Shadow* : on recopie le trafic réel vers la nouvelle version et on jette ses réponses. Pour une API qui écrit, la copie **écrit aussi** : rendez-vous créés deux fois, courriels envoyés deux fois. Il faudrait une base et des effets de bord isolés (base clonée, bouchons des services sortants) — lourd ; valable surtout pour des lectures.
6. Un *feature flag* active une fonction **dans le code** pour une population choisie, indépendamment du déploiement : on déploie la nouvelle version partout, fonction éteinte, puis on l'allume pour 1 % des praticiens. Exemple : un nouveau calcul de créneaux, activé pour un cabinet pilote ; un canary ne sait pas cibler « ce cabinet » durablement, et ne laisserait pas la fonction en place des semaines.
7. Pendant un canary, l'ancien et le nouveau code utilisent le même schéma : chaque migration doit être compatible avec **les deux** versions. *Expand / contract* pour renommer `motif` en `raison` : version N+1 ajoute `raison` (expand), écrit dans les deux colonnes, lit `raison` avec repli sur `motif` ; une migration recopie les données ; version N+2 ne lit et n'écrit plus que `raison` ; version N+3 supprime `motif` (contract), quand plus aucune version en service ne la lit.
8. Si la version qui cesse d'utiliser la colonne la supprime aussi, l'ancienne version (encore en service pendant le canary, et cible d'un retour arrière) plante sur une colonne absente : le retour arrière devient impossible sans restauration de la base. La suppression vient **une version plus tard**, quand le retour vers l'avant-dernière version n'est plus envisagé.
9. La migration doit être **additive** (expand) : l'ancienne version ignore ce qui est ajouté (colonne avec valeur par défaut ou nullable, nouvel index, nouvelle table). C'est la règle des migrations de MédiAgenda (V1, V2, V3 du M17-E18).
10. Non : `/pret` dit que PostgreSQL et Valkey répondent, pas que les créneaux sont justes. Il faudrait un test fonctionnel (le Job de fumée qui compare les créneaux d'un praticien de test à un résultat connu) ou une métrique métier. Au M21 : le taux de réponses 5xx et la latence **du canary** (`mediagenda_http_requests_total`, `mediagenda_http_request_duration_seconds` filtrés sur les pods canary), en analyse Prometheus.
11. Oui, s'il garde un état côté client ou un cache dont le format change (une page servie par la v2 qui appelle une route que la v1 ne connaît pas). MédiAgenda est sans état côté serveur (cache Valkey partagé, même format) : acceptable. Sinon : affinité de session (cookie) au niveau de la Gateway, routage par en-tête vers le canary pour une population fixe (`setHeaderRoute` du greffon), ou garder les deux formats compatibles.
12. Un *worker* n'a pas de trafic entrant : il **tire** des messages. 10 % de pods canary prendront à peu près 10 % des messages si la file est partagée équitablement (*prefetch* égal), sans contrôle fin, et chaque message traité l'est pour de vrai. Proposition : canary par réplicas avec analyse sur les erreurs de traitement (métriques du worker, M21) et petites marches, ou une file dédiée alimentée par un échantillon (copie) quand le traitement est idempotent.
13. Il améliore surtout le **taux d'échec des changements** visibles et le **temps de rétablissement** (un canary interrompu automatiquement n'est pas une panne de prod, et le retour est immédiat). Il peut allonger le **délai de mise en production** (lead time) : marches et pauses ajoutent des minutes à chaque livraison ; la fréquence de déploiement n'en souffre pas si le processus est automatique.

---

### M20-E21 — Revue : les Applications du stagiaire

**Solution**

Revue complète : [`revue.md`](fichiers/M20-E21/revue.md) (18 défauts, 6 bloquants). Version corrigée : [`corrige/applicationset-medinotif.yaml`](fichiers/M20-E21/corrige/applicationset-medinotif.yaml), [`corrige/rabbitmq-operateur.yaml`](fichiers/M20-E21/corrige/rabbitmq-operateur.yaml).

Les défauts majeurs, dans l'ordre où on les traite :
1. **Le Secret** (`secret-rabbitmq.yaml`) : base64 n'est pas un chiffrement, et le mot de passe est même en commentaire. Il est dans l'historique de la branche de la MR (et dans tous les clones) : on **change le mot de passe** côté RabbitMQ, on le range dans le Vault (`secrets/medinotif-<env>.yml`), un module `secrets-k8s.d/medinotif-<env>.sh` crée le Secret. Supprimer le fichier ne suffit pas.
2. **Le gabarit ne se rend pas** : `goTemplate: true` avec `{{path.basename}}` (syntaxe *fasttemplate*) ; Go cherche une fonction `path`. Aucune Application ne serait générée.
3. **`medinotif-prod` décrite deux fois** (générateur de répertoires sur `overlays/*` qui contient `prod`, et fichier à part) : l'ApplicationSet adopterait l'Application du fichier, l'Application `applications` la remettrait : bataille sans fin.
4. **Prod en synchronisation automatique avec `prune`, `selfHeal`, `allowEmpty`** : une fusion malheureuse part en prod seule, et un rendu vide supprime tout.
5. **Suppression en cascade** : finaliseur sur les Applications, ni `preserveResourcesOnDeletion` ni `create-update` ; retirer `overlays/prod` ou supprimer l'ApplicationSet supprime la prod.
6. **Projet `default`**, `targetRevision: HEAD`, `CreateNamespace=true`, `ignoreDifferences: /spec` sur tous les Deployments, `retry.limit: -1`, `Replace=true`, pas de `ServerSideApply` (CRD de l'opérateur trop grosses), chart Bitnami tiré d'Internet en `"*"`, `$valeurs` qui ne correspond à aucune `ref`, image `latest`, destination `namespace: "*"`.

Contrôle de la version corrigée :
```
admin@adm01:~/m20/e21/corrige$ argocd appset generate applicationset-medinotif.yaml -o wide
NAME            PROJECT    SYNCPOLICY  …  PATH
medinotif-dev   medinotif  Auto-Prune  …  overlays/dev
medinotif-prod  medinotif  Manual      …  overlays/prod
admin@adm01:~/m20/e21/corrige$ yamllint -d relaxed .
```
(`argocd appset generate` interroge le serveur : le projet `medinotif` n'existe pas encore, ce qui n'empêche pas la génération. ⚠️ À vérifier sur ton lab.)

Conseils à Lucas : `argocd appset generate` sur tout ApplicationSet ; `argocd app diff --local <dossier>` pour une Application ; `git grep -n "kind: Secret"` (et Gitleaks) avant de pousser.

**Explications**

Une Application GitOps est un **programme** qui agit sur la prod, pas un fichier de configuration inerte : chaque champ (`prune`, finaliseur, projet, révision) décide de ce qui peut être supprimé, par qui, et quand. La revue cherche ce qui arrive le jour où quelque chose se passe mal : fusion erronée, dossier supprimé, Application recréée, dépôt amont compromis.

**Pièges classiques**
- Relever les défauts sans leur risque : Lucas apprendra la règle, pas la raison.
- Corriger la syntaxe du gabarit sans voir le doublon de `medinotif-prod`.
- Proposer « SealedSecrets » sans dire que le mot de passe exposé doit être changé.

---

### M20-E22 — Runbook : une application est `OutOfSync` ou `Degraded`

Exemple de runbook : [`RB-200-application-outofsync-ou-degraded.md`](fichiers/M20-E22/medisphere/docs/livraison/gitops/runbooks/RB-200-application-outofsync-ou-degraded.md).

Points de contrôle pour l'auto-évaluation :
- **Qualification en une commande** (`argocd app get <app> --refresh`) et une table qui envoie vers la bonne section selon ce qu'on lit (condition `ComparisonError`, statut de synchronisation, phase de la dernière opération, santé). Un runbook qui commence par « regarde les journaux d'Argo CD » perd l'astreinte.
- **Qui a écrit ce champ ?** — les `managedFields` sont la clé de toute dérive : humain, contrôleur, opérateur. Sans cette étape, on « corrige » en boucle.
- **Ce qu'on ne fait pas** : corriger un objet géré à la main ; couper la synchronisation automatique pour « gagner du temps » (l'ApplicationSet la remet) ; `argocd app rollback` en premier recours ; supprimer une Application pour la « recréer » (finaliseur : suppression en cascade).
- **Canary interrompu** = garde-fou qui a fonctionné, pas une panne : la version stable sert ; on lit l'AnalysisRun avant de relancer.
- **Pause en prod** = attente de promotion, normale.
- **Clôture** : `argocd app wait <app> --sync --health`, cause corrigée dans Git, trace.

Le test « à froid » révèle d'ordinaire : la commande qui montre les ressources dégradées (`jq` sur `.status.resources`), le nom exact du Rollout et de l'espace, l'accès en lecture aux journaux d'un Job d'analyse. Le palier 4 (E35-E42) complète le RB-200 par des sections par panne.

---

### M20-E23 — Flux : le même déploiement avec un autre outil

**Solution**

Fichiers : état [`infra/envs/m20/`](fichiers/M20-E23/infra/envs/m20/) (`versions.tf`, `providers.tf`, `variables.tf`, `hotes.tf`, `dns.tf`, `terraform.tfvars.exemple`), Ansible [`netbox-m20.yml`](fichiers/M20-E23/ansible/inventories/lab/netbox-m20.yml), [`host_vars/flux01/k3s.yml`](fichiers/M20-E23/ansible/inventories/lab/host_vars/flux01/k3s.yml), [`playbooks/m20.yml`](fichiers/M20-E23/ansible/playbooks/m20.yml), bordure [`pare_feu.yml.extrait`](fichiers/M20-E23/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), dépôt [`flux-labo/`](fichiers/M20-E23/flux-labo/) (`clusters/flux01/apps.yaml`, `apps/labo/`, `apps/podinfo/`), [`charts.yaml`](fichiers/M20-E23/charts-miroir/charts.yaml) du miroir (version E23), [`comparatif-flux.md`](fichiers/M20-E23/medisphere/docs/livraison/gitops/comparatif-flux.md).

1. **Lecture.** Après le bootstrap, les manifestes de Flux sont **dans le dépôt** (`clusters/flux01/flux-system/gotk-components.yaml`, `gotk-sync.yaml`, `kustomization.yaml`) et Flux se gère **lui-même** : la Kustomization `flux-system` applique ce dossier, Flux compris (une montée de version = un `flux bootstrap` rejoué ou une MR sur `gotk-components.yaml`). Équivalents : application racine → Kustomization `flux-system` ; `selfHeal` → comportement **par défaut** (chaque `interval`, le kustomize-controller réapplique) ; `prune` → `spec.prune: true` ; vagues → `dependsOn` entre Kustomizations (ou HelmReleases) et `wait`. Flux 2.9 a retiré les API `v1beta2` d'images et de notifications : `flux migrate` avant une montée depuis une ancienne installation (sans objet ici).
2. **VM et réseau.**
   ```
   admin@adm01:~/src/infra/envs/m20$ tofu init && tofu plan -out=plan && tofu apply plan      # groupes = ["flux"]
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/routeurs.yml --limit gw01 --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/routeurs.yml --limit gw01 && uv run ansible-playbook playbooks/routeurs.yml --limit gw02
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph env_m20 && uv run ansible-playbook playbooks/m20.yml --diff
   admin@adm01:~$ ssh flux01 sudo cat /etc/rancher/k3s/k3s.yaml \
       | sed -e 's#https://127.0.0.1:6443#https://flux01.par1.medisphere.internal:6443#' -e 's/: default$/: flux01/' \
       | { install -d -m 700 ~/.config/workbook/m20 && install -m 600 /dev/stdin ~/.config/workbook/m20/flux01.kubeconfig; }
   admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m20/flux01.kubeconfig ; kubectl get nodes
   ```
   CLI `flux` sur `adm01` : une entrée de plus dans les archives vérifiées du rôle `outils_k8s` ([extrait](fichiers/M20-E23/ansible/roles/outils_k8s/defaults/main.extrait-E23.yml) ; `flux version --client` → `v2.9.6`).
   ⚠️ Pare-feu : si `--check --diff` montre autre chose que la règle ajoutée, arrête (une passerelle à la fois ; retour arrière : revert de la MR, même playbook). Le jeton du rôle `k3s` va dans le Vault `lab` (`vault_k3s_jeton_flux01`, comme `k3s01` au M18). Le flux MGMT → `vsandbox` 6443 pour `kubectl` depuis `adm01` existe depuis le M18 (accès d'administration). ⚠️ À vérifier sur ton lab.
3. **Accès.** Projet `formation/flux-labo` vide, puis *Settings → Access tokens* du projet : rôle **Maintainer** (pousser sur `main` protégée et créer un jeton de déploiement), portées `api` (création du jeton de déploiement et lecture du projet par l'API) et `write_repository` (poussée), expiration le lendemain. Pas ton jeton personnel (accès à tout ce que tu peux faire, dans le shell et l'historique) ; pas un jeton du groupe `formation` (tous ses projets). Le bootstrap crée lui-même le jeton de **déploiement** de lecture avec `--deploy-token-auth`.
4. **Bootstrap.**
   ```
   admin@adm01:~$ export GITLAB_TOKEN="$(<~/.config/workbook/m20/flux-bootstrap.token)"
   admin@adm01:~$ flux bootstrap gitlab --hostname=git01.par1.medisphere.internal --owner=formation --repository=flux-labo \
       --branch=main --path=clusters/flux01 --deploy-token-auth \
       --ca-file=/usr/local/share/ca-certificates/medisphere-root-ca.crt
   ► connecting to https://git01.par1.medisphere.internal
   ► cloning branch "main" from Git repository "https://git01.par1.medisphere.internal/formation/flux-labo.git"
   ✔ committed component manifests to "main" …
   ► generating GitLab deploy token …
   ✔ reconciled sync configuration
   ✔ all components are healthy
   admin@adm01:~$ unset GITLAB_TOKEN; flux check && flux get all -A
   ```
   (Sortie abrégée ; ⚠️ à vérifier sur ton lab : la lecture du groupe `formation` et la création du jeton de déploiement par un jeton **de projet** — l'utilisateur robot du jeton n'est membre que du projet ; si le bootstrap échoue sur le groupe, crée un jeton de groupe à portée identique, expiré le lendemain, et note l'écart —, et la reprise de `--ca-file` dans le Secret `flux-system` — clé `ca.crt` — pour les réconciliations suivantes.) Les images de Flux viennent de `ghcr.io/fluxcd` **par le miroir** k3s vers le cache Harbor `ghcr` (rien à changer dans le bootstrap ; `--registry` permettrait de viser un autre registre). Révocation du jeton d'amorçage (*Access tokens* → *Revoke*) : Flux continue, il utilise le jeton de déploiement (`kubectl -n flux-system get secret flux-system -o jsonpath='{.data.username}' | base64 -d` donne le nom d'utilisateur du jeton de déploiement, `gitlab+deploy-token-…`).
5. **labo.** `apps/labo/` reprend **les mêmes** manifestes que `formation/gitops-labo` (E04), dans un espace `labo` en `restricted` ; la Kustomization `labo` (`prune`, `wait`, `timeout`). Dérive :
   ```
   admin@adm01:~$ kubectl scale deploy labo -n labo --replicas=5 && kubectl get deploy labo -n labo -w
   ```
   Retour à 2 au plus tard à l'intervalle suivant (5 min ici) : pas d'option, c'est le comportement de Flux, et pas de réaction immédiate (Argo CD avec `selfHeal` réagit à l'événement de modification). `flux reconcile kustomization labo --with-source` force l'application tout de suite.
6. **podinfo.** Entrée `podinfo` dans `charts.yaml` (empreinte `5ca78968…a334d75`, champ `digest` de l'index de `https://stefanprodan.github.io/podinfo`), pipeline du miroir. Secrets (hors Git, sur `flux01`) :
   ```
   admin@adm01:~$ jeton="$(<~/.config/workbook/m20/charts-lecture.token)"
   admin@adm01:~$ kubectl -n flux-system create secret generic harbor-charts --type=kubernetes.io/dockerconfigjson \
       --from-file=.dockerconfigjson=<(jq -cn --arg a "$(printf '%s:%s' 'robot$charts+lecture' "$jeton" | base64 -w0)" \
         '{auths: {"registry.par1.medisphere.internal": {auth: $a}}}') ; unset jeton
   ```
   (Même forme que `secrets-k8s.sh` en E12 : le jeton ne passe jamais en argument. `kubectl create secret docker-registry --docker-password=…` le mettrait sur la ligne de commande, visible par `ps`.)
   ```
   admin@adm01:~$ kubectl -n flux-system create secret generic medisphere-ca --from-file=ca.crt=/usr/local/share/ca-certificates/medisphere-root-ca.crt
   admin@adm01:~$ flux get sources oci -A && flux get helmreleases -A
   admin@adm01:~$ helm list -n podinfo
   NAME     NAMESPACE  REVISION  STATUS    CHART           APP VERSION
   podinfo  podinfo    1         deployed  podinfo-6.15.0  6.15.0
   ```
   Flux installe une **vraie release Helm** (historique, hooks Helm exécutés par Helm, `helm rollback` possible) ; Argo CD rend le chart en manifestes et ne laisse aucune release (`helm list` vide, E13). L'espace `podinfo` est en `baseline` (le chart ne fixe pas d'utilisateur numérique) avec avertissement `restricted` : écart documenté dans le fichier.
7. **Comparatif** : voir l'exemple. L'essentiel pour MédiSphère : interface et RBAC pour les équipes, ApplicationSets, Argo Rollouts déjà intégré, vue centrale de plusieurs clusters → Argo CD ; Flux : léger, sans interface, un contrôleur par cluster qui tire — idéal pour un site isolé.
8. **Fin.** `flux01` reste jusqu'au check ; puis, si la mémoire manque avant E26 : `groupes = []`, `tofu apply`, MR qui retire la règle et la définition `FLUX01` de la bordure (une passerelle à la fois) et la ligne de la matrice. Sinon, le mini-projet (E46) le fait.

**Explications**

Argo CD et Flux appliquent le même principe (un contrôleur qui réconcilie le cluster avec Git) avec deux architectures : Argo CD est un **service central** (API, interface, RBAC, multi-cluster poussé depuis un point), Flux est un **ensemble de contrôleurs dans chaque cluster** (rien à exposer, chaque cluster tire). Le choix dépend moins des fonctions (proches) que de l'organisation : qui opère, qui regarde, combien de clusters, quel réseau.

**Alternatives**
- *Flux Operator* (`FluxInstance`, 0.61) : installe et met à jour Flux par une ressource, sans `flux bootstrap` ; adapté à un parc.
- *Clé de déploiement SSH* (mode par défaut du bootstrap) : il faudrait ouvrir `vsandbox` → `git01` 22 (et configurer `known_hosts`) ; HTTPS avec un jeton de déploiement suffit et réutilise le flux 443.
- *Jeton personnel avec `--token-auth`* : le jeton reste dans le cluster, avec tous tes droits ; à éviter.

**Pièges classiques**
- `flux bootstrap gitlab` sans `--hostname` : il vise `gitlab.com`.
- Sans `--ca-file` : `x509: certificate signed by unknown authority` au clonage.
- Ajouter `--personal` alors que `--owner` est un groupe : il cherche un utilisateur `formation` (sans `--personal`, `--owner` désigne un groupe, ce qu'on veut ici).
- Laisser le jeton d'amorçage actif « au cas où » : c'est un jeton `api` de Maintainer.
- `OCIRepository` sans `certSecretRef` : TLS refusé vers Harbor ; sans `secretRef` : 401 (projet `charts` privé).
- Lancer `flux01` avec un autre composant temporaire : mémoire (PLAN §4.11).

**En production chez MédiSphère**

Flux n'est pas retenu (ADR-0200, E31). S'il l'était pour un site isolé, son bootstrap passerait par Flux Operator géré par OpenTofu, et ses notifications (notification-controller) iraient à l'Alertmanager.
