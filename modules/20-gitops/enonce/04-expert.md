# Module 20 — Palier 4 : Expert

MédiSphère est en GitOps : Argo CD réconcilie les trois environnements de MédiAgenda, MédiDoc, le cluster de l'agence de Lyon et les services de plateforme ; la CI n'a plus aucun droit d'écriture sur les espaces applicatifs ; les mises en production passent par MR, canary et analyses. Nadia Roussel pose la question que tout le monde évite : « Quand Argo CD affiche du jaune ou du rouge, qui sait lire ce qu'il dit ? Et quand il affiche du vert alors que rien n'est déployé ? » Karim Benali a préparé huit pannes, toutes de celles qu'on trouve dans les post-mortems publics des équipes GitOps : une application qui ne revient jamais à `Synced`, une synchronisation refusée, un dépôt devenu illisible, une application `Degraded` après une synchronisation « réussie », une dérive qui revient sans cesse, un canary qui ne va pas au bout, une synchronisation qui a supprimé des ressources, un cluster distant perdu. Une astreinte en combine trois pendant une mise en production. Puis tu descends sous le capot, du commit à l'objet, et tu passes les questions qu'on pose en entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres au GitOps :
- **Git est la vérité, Argo CD est le témoin.** Le statut de synchronisation dit si le cluster ressemble à Git, la santé dit si ce qui a été appliqué fonctionne, les conditions (`status.conditions`) disent ce qu'Argo CD n'a pas pu faire. Lis les trois, et le message entier, avant de toucher à quoi que ce soit (`argocd app get <app>`, `argocd app get <app> -o json | jq .status.conditions`, `--show-operation`).
- **Cherche ce qui a bougé dans Git d'abord.** Une panne GitOps commence presque toujours par un commit : `argocd app history <app>`, `git log -p` sur le chemin suivi, la MR qui l'a apporté. Ensuite seulement : ce qui a bougé hors de Git (objets modifiés à la main, Secrets, configuration d'Argo CD, réseau).
- **Le correctif passe par Git.** Un `kubectl edit` sur un objet suivi est défait par l'auto-réparation, un `argocd app sync --force` peut supprimer et recréer des objets, un `argocd app set` modifie l'Application hors de `plateforme/gitops`. Le retour arrière normal est un `git revert` par MR ; la configuration d'Argo CD lui-même se corrige dans la release Helmfile `argocd` ; les Secrets se recréent par `secrets-k8s.sh`.

> **Rappels** : tout se lance depuis `adm01`. La CLI `argocd` est connectée avec ton compte local (M20-E03) ; ton kubeconfig personnel sert pour lire les objets (`kubectl get applications -n argocd`) ; aucun `kubectl apply` sur les espaces applicatifs (M20-E30). Les comptes locaux d'Argo CD s'écrivent avec des tirets (`karim-benali`, `julien-petit`, `nadia-roussel`).

## Règles du jeu des pannes (M20-E35 à M20-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 20 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé, ou une porte de ta CI a refusé le changement — bonne nouvelle), le script la défait et en essaie une autre.
- **Comment les pannes arrivent.** Comme dans la vraie vie, la plupart sont des **commits de Lucas Martin** dans `mediagenda/deploiement` ou `plateforme/gitops` : le script crée une branche `lucas/…`, un commit dont l'auteur est Lucas, ouvre une MR et la fusionne avec ton **jeton d'administration GitLab** (M01-E05, `WB_GITLAB_ADMIN_TOKEN_FILE`), après le pipeline de la MR. Dans GitLab, la MR apparaît donc ouverte et fusionnée par toi : c'est un artefact du lab, pas une piste. Les autres pannes modifient un objet hors de Git (Secret, ConfigMap d'Argo CD, politique réseau, Rollout, pare-feu de `lyo-k3s01`). **Une injection prend de 2 à 15 minutes** : pipeline de la MR, fusion, synchronisation, puis le script attend qu'Argo CD constate la panne.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 20 35`) : il doit être vert. Le script refuse de casser des applications qui ne sont pas `Synced` et `Healthy`, ou un canary qui n'est pas au repos.
- **Prérequis sur `adm01`** : `yq` de mikefarah (PLAN §6), `jq`, `curl`, `kubectl` et `openssl` ; ton jeton d'administration GitLab lisible ; ton kubeconfig personnel (`WB_K8S_ADMIN_KUBECONFIG`). Les variables facultatives de `lab/lab.env` : `WB_M20_DELAI_FUSION` (attente maximale du pipeline d'une MR, 900 s par défaut), `WB_M20_APP_DEV` / `WB_M20_APP_RECETTE` (si tes Applications portent d'autres noms), `WB_M20_LYO_HOTE` (adresse de `lyo-k3s01`, 10.10.99.61), `WB_M20_OBSERVATION` (durée de l'observation du check E39, 60 s), `WB_ARGOCD_URL` et `WB_ARGOCD_TOKEN_FILE` (API d'Argo CD pour les checks).
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `~/.local/state/workbook/` sur `adm01`, ni `/var/lib/workbook/` sur `lyo-k3s01` : ils contiennent la cause. Les commits, les MR, les objets et les journaux, eux, sont faits pour être lus.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 20 35 --annuler` remet l'état sain par un **commit inverse** (jamais par réécriture d'historique) et restaure les objets modifiés (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : l'annulation ne défait que ce qui est encore cassé (un commit déjà annulé ou des lignes que tu as reprises ne sont jamais forcés) et ne revient jamais sur ta réparation.
- Périmètre : les pannes touchent `mediagenda-dev`, `mediagenda-recette`, `labo`, la configuration d'Argo CD et d'Argo Rollouts, et `lyo-k3s01`. **Jamais la production** : aucune panne ne commite dans `overlays/prod`, ne désactive la synchronisation de prod ni ne modifie le Rollout de prod. **Aucune donnée n'est détruite** : une panne qui fait élaguer des objets vérifie d'abord, sur un rendu des deux versions, que rien de ce qui disparaîtrait ne porte de données (bases CNPG en `Prune=false`, aucun PVC).
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/kubernetes/journal/` de `~/medisphere` (publié par MR), avec le numéro du ticket (`INC-4735`…) : heure, hypothèse, commande, résultat observé, conclusion. Un outil t'aide à photographier une Application pour le journal : écris-le en E35 (ou reprends celui du corrigé une fois l'exercice fait). Chaque panne se termine par une **section de RB-200** (M20-E22) : l'arbre de décision de la famille de pannes.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Les gestes interdits du palier**, sauf mention explicite dans ta démarche avec sa justification : désactiver l'auto-synchronisation ou l'auto-réparation « pour que ça se calme » (si tu dois le faire le temps d'un diagnostic, note l'heure et rétablis-la) ; `argocd app sync --force` ou `--replace` ; `argocd app delete` ou suppression d'une Application **sans avoir vérifié ses finaliseurs** (`resources-finalizer.argocd.argoproj.io` supprime en cascade tout ce qu'elle gère) ; `kubectl apply`/`edit` sur un objet applicatif suivi par Argo CD ; élargir un AppProject, un RBAC ou une politique réseau pour « faire passer » ; réécrire l'historique de `main` ; synchroniser la production pendant une panne.

> ⚠️ **Annulation et production** : les annulations passent par des MR fusionnées automatiquement. Si une MR d'annulation reste ouverte (pipeline en échec, conflit avec ta propre correction), le script te le dit et te laisse la fusionner ou la fermer : vérifie qu'aucune branche `lucas/…` ou `wb/annulation-…` ne traîne avant le mini-projet (le check E46 le contrôle).

---

### M20-E35 — Panne : l'application reste `OutOfSync`  `BF` `★★`

> **Ticket INC-4735** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, `mediagenda-dev` reste `OutOfSync` malgré des synchronisations réussies, reste « en cours de synchronisation » sans fin, ou les environnements de MédiAgenda passent en `Unknown`.)* Lucas propose de « cocher Replace et Force et de resynchroniser » : n'en fais rien avant d'avoir trouvé la cause.

**Objectifs pédagogiques**
- Distinguer les causes d'un `OutOfSync` qui ne se résorbe pas : ressource que Git ne décrit plus mais qu'Argo CD n'a pas le droit d'élaguer, opération bloquée sur une vague, manifestes que le repo-server ne sait pas générer, champ que l'API ou un webhook réécrit.
- Lire le diff d'Argo CD, les conditions et l'opération en cours ; relier chaque cas à la stratégie de comparaison (3-way, comparaison côté serveur avec ou sans webhooks de mutation).
- Corriger dans Git sans masquer une vraie différence, et compléter RB-200.

**Prérequis** : M20-E05, M20-E10, M20-E11 (vagues), M20-E12 (différences ignorées, comparaison côté serveur), M20-E22 (RB-200) ; `lab/bin/check 20 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : `mediagenda-dev` est générée par l'ApplicationSet `mediagenda` (synchronisation automatique, `prune`, `selfHeal`, `ServerSideApply`, comparaison côté serveur avec les webhooks de mutation). L'overlay `overlays/dev` de `mediagenda/deploiement` inclut les components `dependances` (base CNPG `mediagenda-db` en `Prune=false,Delete=false`, Valkey), `debogage`, `migrations` (vagues : -3 configuration, -2 base et Valkey, -1 Job de migration, 0 application) et `livraison`. Argo CD 3.5 embarque Kustomize 5.8.1.

**Injection** : `lab/bin/break 20 35` (4 variantes).

**Travail demandé**
1. Constate sans rien toucher : statut de synchronisation et de santé, conditions, opération en cours ou dernière opération (phase, message, révision, début et fin), ressources `OutOfSync` et leur message. Écris dans ton journal ce que dit chaque champ.
2. Écris l'outil `outils/argocd-diagnostic.sh` de `plateforme/outils` : pour une Application donnée, il affiche (lecture seule) l'état, les conditions, l'opération, les ressources non conformes (statut, santé, élagage requis), les cinq dernières opérations et, sur option, le diff. Il te servira pour toutes les pannes du palier.
3. Retrouve le commit qui a provoqué la situation (`argocd app history`, `git log -p`), et explique **pourquoi** Argo CD ne peut pas converger : quel mécanisme (élagage refusé, vague qui attend, génération impossible, valeur réécrite) et quelle preuve (message, champ, ligne de journal).
4. Corrige par une MR. Si une opération est bloquée, termine-la proprement (`argocd app terminate-op`) **après** avoir compris pourquoi elle l'était. Si une ressource porteuse de données n'est plus dans Git, ne la supprime pas : remets-la dans Git ou ouvre un ticket de changement.
5. Vérifie : `Synced`, `Healthy`, dernière opération `Succeeded` sur la révision courante, et une nouvelle synchronisation automatique ne rouvre pas la différence.
6. Complète RB-200 d'une section « L'application reste OutOfSync juste après une synchronisation réussie » : un arbre de décision (élagage refusé, génération impossible, opération bloquée, valeur réécrite), avec la commande qui prouve chaque cas et le correctif.

**Critères de réussite**
- [ ] `mediagenda-dev` est `Synced` et `Healthy`, sans ressource `OutOfSync`, sans élagage en attente, sans opération en cours depuis plus de 10 minutes, sans PVC `Pending` dans son espace.
- [ ] Aucune Application de l'ApplicationSet `mediagenda` en erreur de comparaison ; toute version de Kustomize épinglée par une Application est déclarée dans `argocd-cm`.
- [ ] Les bases CNPG de `mediagenda-*` existent et portent toujours `Prune=false`.
- [ ] RB-200 contient la section ; ton journal (`docs/kubernetes/journal/`, ticket `INC-4735`) est commité ; aucune MR `lucas/…` ne reste ouverte ; la panne est close.

**Vérification** : `lab/bin/check 20 35`

<details><summary>Indice 1</summary>

`argocd app get mediagenda-dev` ne montre qu'un résumé. Le JSON complet (`kubectl -n argocd get applications.argoproj.io mediagenda-dev -o json`) contient `status.conditions`, `status.operationState` (avec `syncResult.resources[]` et le message de chaque ressource) et `status.resources[]` (dont `requiresPruning`). Une opération dont la phase reste `Running` n'est pas « en cours » par hasard : son message dit ce qu'elle attend.
</details>

<details><summary>Indice 2</summary>

Quatre familles : (1) une ressource n'est plus dans Git mais porte une option qui interdit de l'élaguer ; (2) Argo CD attend qu'une vague soit **saine** avant la suivante — que se passe-t-il si une ressource de la vague ne le devient jamais ? (3) le repo-server n'arrive pas à rendre les manifestes avec les options demandées par l'Application ; (4) la valeur écrite dans Git n'est pas celle que l'API conserve (forme canonique, valeur par défaut, webhook). Pour (4), regarde quelle stratégie de comparaison l'Application utilise (annotation `argocd.argoproj.io/compare-options`) : elle peut rendre ce cas impossible.
</details>

<details><summary>Indice 3</summary>

Le journal du contrôleur (`kubectl -n argocd logs statefulset/argocd-application-controller | grep '"application":"mediagenda-dev"'`) écrit `Skipping auto-sync: another operation is in progress` quand une opération bloque les suivantes. `argocd app terminate-op` arrête l'opération ; elle ne corrige rien. La documentation « Sync Options » (`Prune=false`), « Sync Phases and Waves » et « Kustomize » (versions personnalisées) d'Argo CD décrivent les trois premiers cas.
</details>

**Pour aller plus loin** (facultatif) : reproduis le cas (4) sur une Application de `wb-essais` **sans** comparaison côté serveur (quantité écrite `0.5` pour `500m` dans une ressource personnalisée) et compare le diff avec et sans `ServerSideDiff=true,IncludeMutationWebhook=true` ; documentation « Diff Strategies ».

---

### M20-E36 — Panne : la synchronisation échoue  `BF` `★★`

> **Ticket INC-4736** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection.)* Une MR de Lucas, pipeline vert, est fusionnée dans `mediagenda/deploiement` ; Argo CD affiche « Sync failed » (ou, selon le cas, une erreur de comparaison) sur `mediagenda-dev` et rien n'arrive en dev. Lucas veut « forcer » ou désactiver l'auto-synchronisation de dev.

**Objectifs pédagogiques**
- Lire le résultat d'une opération en échec (message de l'opération, message par ressource, phase des hooks) et situer l'étage qui refuse : validation de l'API, AppProject, hook, admission (quotas).
- Comprendre pourquoi une synchronisation en échec n'applique rien de la vague en cause, et pourquoi elle n'est pas relancée d'elle-même pour la même révision.
- Expliquer ce que la validation de la CI (rendu, schéma) ne peut pas voir, et ajouter une porte qui le voit, sans accès au cluster.

**Prérequis** : M20-E07 (AppProjects), M20-E11 (hooks), M19-E29 et M20-E30 (pipeline de validation de `mediagenda/deploiement`), M14-E10 (quotas) ; `lab/bin/check 20 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 20 36` (4 variantes).

**Travail demandé**
1. Constate : phase et message de l'opération, ressources en échec (`argocd app get mediagenda-dev --show-operation`), éventuel Job de hook et son journal. Ce qui tourne en dev a-t-il changé ? Pourquoi ?
2. Situe l'étage qui refuse et prouve-le par la règle qui s'applique (champ, AppProject, annotation de hook, ResourceQuota).
3. Corrige par une MR : revert, ou correction qui atteint le but de Lucas **par le bon chemin** (ce qui relève de la plateforme part dans le dépôt de la plateforme, pas dans l'overlay de l'équipe). Une ressource de cluster ou un quota ne s'obtiennent pas en élargissant l'AppProject.
4. Vérifie que la synchronisation suivante réussit et porte sur la révision courante. Si elle ne repart pas seule, explique pourquoi avant de la lancer.
5. Ajoute au pipeline de MR de `mediagenda/deploiement` un job `verifier-overlays` (script `outils/verifier-overlay.sh`) qui, sans accès au cluster, refuse : les ressources de portée cluster, les Services `LoadBalancer`/`NodePort`, les hooks sans politique de suppression ni délai, et un sélecteur de Deployment ou de StatefulSet modifié par rapport à `main`. Rejoue le commit de Lucas sur une branche : le job doit échouer.
6. Complète RB-200 d'une section « La synchronisation échoue ».

**Critères de réussite**
- [ ] `mediagenda-dev` `Synced`, `Healthy`, dernière opération `Succeeded` sur la révision courante.
- [ ] Aucune Application ne signale de ressource refusée par son AppProject ; aucun Job de hook en échec dans `mediagenda-dev` ; le sélecteur du Deployment `mediagenda` est celui du chart ; aucun Service `LoadBalancer` dans l'espace.
- [ ] `overlays/dev` (sur `main`) ne contient aucune ressource de portée cluster.
- [ ] Le job `verifier-overlays` existe et a échoué sur ta branche de démonstration (lien dans ton journal) ; RB-200 contient la section ; journal (`INC-4736`) commité ; panne close.

**Vérification** : `lab/bin/check 20 36`

<details><summary>Indice 1</summary>

Le message d'une opération en échec contient le message de l'API ou d'Argo CD mot pour mot : `field is immutable`, `is not permitted in project`, `exceeded quota`, `PreSync`/`Sync hook … failed`. Pour un hook, le Job reste là (politique `BeforeHookCreation`) : `kubectl -n mediagenda-dev logs job/<nom>`.
</details>

<details><summary>Indice 2</summary>

Argo CD ne relance pas automatiquement une synchronisation qui a échoué pour la **même** révision (journal du contrôleur : `Skipping auto-sync: failed previous sync attempt to … and will not retry for …`, condition `SyncError` « Failed last sync attempt to … »), sauf `retry` configuré : c'est voulu, pour ne pas marteler l'API. Le prochain commit, ou un `argocd app sync` après correction, relance. kubeconform valide la forme des objets, pas l'immutabilité d'un champ, les AppProjects, les quotas ni les webhooks.
</details>

**Pour aller plus loin** (facultatif) : la comparaison côté serveur fait passer les manifestes par l'admission pendant le diff : quelles variantes de cette panne seraient alors visibles **avant** la synchronisation ? Documentation « Diff Strategies », section « Server-Side Diff ».

---

### M20-E37 — Panne : Argo CD ne lit plus le dépôt  `BF` `★★`

> **Ticket INC-4737** — *De : Karim Benali*
> *(Le détail s'affiche à l'injection.)* Une ou plusieurs Applications affichent une erreur de comparaison et un statut `Unknown` ; les pods tournent, mais plus rien de ce qu'on fusionne n'arrive dans le cluster. Karim clone pourtant les dépôts sans problème depuis `adm01`.

**Objectifs pédagogiques**
- Situer un accès au dépôt qui échoue : identifiants (Secrets `repo-creds`/`repository`, jetons de déploiement), confiance TLS (`argocd-tls-certs-cm`), adresse du dépôt (Application, AppProject), réseau (politiques de l'espace `argocd`, bordure).
- Reproduire le problème **depuis le repo-server**, pas depuis `adm01`.
- Corriger à la source (Vault et `secrets-k8s.sh`, release Helmfile, Git, code des politiques), sans affaiblir la sécurité.

**Prérequis** : M20-E06 (identifiants des dépôts, racine MédiSphère), M20-E25 (politiques réseau de l'espace `argocd`), M20-E27 (webhooks) ; `lab/bin/check 20 37` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 20 37` (4 variantes).

**Travail demandé**
1. Constate : quelles Applications sont touchées (toutes, un groupe de dépôts, une seule) ? Message exact de la condition. Ce que cela dit déjà de l'étage en cause.
2. Reproduis depuis le repo-server (`kubectl -n argocd exec deploy/argocd-repo-server -- …`) : résolution du nom, connexion TCP, poignée de main TLS, `git ls-remote`. Note ce qui passe et ce qui casse.
3. Trouve ce qui a changé (Git, Secret, ConfigMap, politique) et **qui** l'a changé (`managedFields`, annotations, historique des MR).
4. Corrige à la source : un identifiant se recrée depuis le Vault par `secrets-k8s.sh` (jamais une valeur collée à la main), une CA par la release Helmfile `argocd` (`helmfile diff` d'abord ; rappel du M17-E14 : sans `--three-way-merge`, il ne voit pas ce qui a été modifié à la main), une adresse par un revert dans `plateforme/gitops`, un refus réseau par le code qui le porte.
5. Accélère la reprise (`--hard-refresh`) et vérifie qu'aucune Application ne reste en erreur.
6. Complète RB-200 d'une section « Argo CD ne lit plus le dépôt ».

**Critères de réussite**
- [ ] Aucune Application en erreur de comparaison ou de spécification ; `racine`, `mediagenda-dev` et `labo` `Synced` et `Healthy`, `labo` pointant sur `git01`.
- [ ] L'entrée `git01.par1.medisphere.internal` de `argocd-tls-certs-cm` valide le certificat de la forge ; aucune CiliumNetworkPolicy de l'espace `argocd` ne refuse `git01`.
- [ ] Les dépôts déclarés sont en état de connexion `Successful` (API d'Argo CD) ; RB-200 et journal (`INC-4737`) commités ; panne close.

**Vérification** : `lab/bin/check 20 37`

<details><summary>Indice 1</summary>

Argo CD garde quelques minutes la révision résolue d'une branche (`git ls-remote`) : un dépôt devenu illisible peut sembler fonctionner encore un moment, et une réparation peut sembler sans effet. `argocd app get <app> --hard-refresh` force la régénération. `git ls-remote` sans identifiants depuis le repo-server distingue déjà le réseau et TLS (qui passent) de l'authentification (refusée).
</details>

<details><summary>Indice 2</summary>

`kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=repo-creds` (sans afficher les valeurs) : qui a écrit en dernier (`--show-managed-fields`), quelles annotations ? `kubectl -n argocd get cm argocd-tls-certs-cm -o yaml` : une entrée par **nom d'hôte**. `hubble observe --namespace argocd --verdict DROPPED` montre un refus réseau en direct. Pour l'adresse d'un dépôt, l'AppProject peut refuser avant même toute connexion.
</details>

**Pour aller plus loin** (facultatif) : mesure le temps que met Argo CD à remarquer qu'un dépôt est illisible sans `--hard-refresh` ; relie-le à `timeout.reconciliation` et au cache des révisions résolues du repo-server (option `--revision-cache-expiration` de `argocd-repo-server`, qui n'a pas de clé dans `argocd-cmd-params-cm` en 3.5 et vaut par défaut `timeout.reconciliation`).

---

### M20-E38 — Panne : l'application est `Degraded` après synchronisation  `BF` `★★`

> **Ticket INC-4738** — *De : Julien Petit ou Nadia Roussel*
> *(Le détail s'affiche à l'injection : une nouvelle version de dev qui ne démarre jamais, ou des notifications « health degraded » pour une application que les équipes disent en parfait état.)*

**Objectifs pédagogiques**
- Séparer synchronisation et santé : une synchronisation peut réussir sans que ce qu'elle applique fonctionne, et une santé peut être fausse.
- Descendre de l'Application au pod (rollout, ReplicaSet neuf, événements) et reconnaître les causes classiques : image introuvable, sonde mal réglée, volume impossible à provisionner.
- Lire, éprouver et corriger un contrôle de santé Lua (`resource.customizations.health.*`), et connaître les contrôles intégrés d'Argo CD.

**Prérequis** : M14-E37 et M14-E38 (pods en échec), M16 (StorageClasses), M20-E12, M20-E19 (notifications) ; `lab/bin/check 20 38` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 20 38` (4 variantes).

**Travail demandé**
1. Constate : quelle ressource porte la santé dégradée, avec quel message ? L'ancienne version de l'application répond-elle encore ? Pourquoi ?
2. Descends jusqu'à la cause (`kubectl rollout status`, pods neufs, événements, PVC, StorageClass, contrôle de santé). Si la ressource déclarée malade est saine pour son opérateur, prouve-le, puis trouve d'où vient le jugement d'Argo CD.
3. Corrige à la source (MR dans `mediagenda/deploiement` ; pour un contrôle de santé, c'est la release Helmfile `argocd` qui porte ce qui est voulu). N'ajoute ni ne modifie rien à la main dans `argocd-cm` (pas de `kubectl edit`) ; si quelqu'un l'a fait, défais exactement son geste, trace-le dans ton journal, et vérifie que `argocd-cm` ne s'écarte plus de la release.
4. Écris `outils/tester-sante.sh` (dans `plateforme/k8s`) : il évalue un contrôle de santé proposé dans les valeurs de la release contre un objet réel, avec `argocd admin settings resource-overrides health`, et le compare au contrôle intégré. Toute MR qui touche `resource.customizations.health` en joindra la sortie.
5. Vérifie : `argocd app wait mediagenda-dev --health --timeout 600` ; plus aucune notification `health-degraded` erronée.
6. Complète RB-200 d'une section « L'application est Degraded après une synchronisation réussie ».

**Critères de réussite**
- [ ] `mediagenda-dev` `Synced` et `Healthy` ; Deployment `mediagenda` à jour et disponible ; aucun pod en échec de tirage ni en attente ; aucun PVC `Pending` dans `mediagenda-*`.
- [ ] La sonde de disponibilité de l'API vise `/pret`.
- [ ] Aucune base CNPG saine (« Cluster in healthy state ») n'est déclarée `Degraded` par une Application.
- [ ] RB-200 et journal (`INC-4738`) commités ; `outils/tester-sante.sh` dans `plateforme/k8s` ; panne close.

**Vérification** : `lab/bin/check 20 38`

<details><summary>Indice 1</summary>

Avec `maxUnavailable: 0`, l'ancien pod reste en service tant que le nouveau n'est pas prêt : c'est une livraison bloquée, pas une coupure. Un Deployment ne passe `Degraded` qu'après `progressDeadlineSeconds` (600 s par défaut) ; avant, il est `Progressing`. Les pods **neufs** disent la cause : `kubectl get pods --sort-by=.metadata.creationTimestamp`, puis `describe`.
</details>

<details><summary>Indice 2</summary>

Argo CD calcule la santé des ressources personnalisées avec des scripts Lua : les siens (dossier `resource_customizations/` du projet, CNPG compris) ou ceux de `argocd-cm` (`resource.customizations.health.<groupe>_<Kind>`), qui ont la priorité. `argocd admin settings resource-overrides health objet.yaml --argocd-cm-path argocd-cm.yaml` exécute un script en local.
</details>

**Pour aller plus loin** (facultatif) : la documentation « Resource Health » liste les règles pour écrire un bon contrôle (ne jamais dire `Healthy` par défaut, renvoyer `Progressing` tant que le statut n'est pas observé). Compare avec le contrôle intégré de `postgresql.cnpg.io/Cluster`.

---

### M20-E39 — Panne : la dérive revient sans cesse  `BF` `★★★`

> **Ticket INC-4739** — *De : Julien Petit ou Karim Benali*
> *(Le détail s'affiche à l'injection : des pods de dev recréés en boucle et des synchronisations automatiques sans commit, ou une application de labo qui se resynchronise toute seule.)* Lucas assure qu'il « n'a rien cassé, juste aidé ».

**Objectifs pédagogiques**
- Reconnaître une bataille entre Argo CD (`selfHeal`) et un second écrivain, et le rythme de ses réparations (attente exponentielle de l'auto-réparation).
- Identifier l'autre écrivain : contrôleur (HPA), seconde Application, script ou tâche planifiée ; par les gestionnaires de champs, l'annotation de suivi, les conditions, les droits accordés.
- Supprimer la cause sans désactiver `selfHeal`, et choisir entre « Git décrit le champ » et « Git l'ignore ».

**Prérequis** : M20-E05 (selfHeal), M20-E12 (différences ignorées), M20-E30 (gestionnaires de champs), M14-E27 (journal d'audit) ; `lab/bin/check 20 39` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 20 39` (3 variantes).

**Travail demandé**
1. Constate et mesure la bataille : fréquence des synchronisations automatiques (`argocd app history`), générations successives de l'objet, événements, pods recréés. Pourquoi les intervalles s'allongent-ils ?
2. Écris `outils/qui-ecrit.sh` (dans `plateforme/outils`) : pour un objet, il liste ses gestionnaires de champs (manager, opération, sous-ressource, date, champs possédés), son annotation de suivi et les Applications qui le déclarent, les HPA de l'espace, et les comptes de service d'autres espaces qui ont des droits dans l'espace.
3. Nomme l'autre écrivain et prouve-le (au besoin par le journal d'audit de l'API).
4. Fais cesser la bataille durablement : un seul propriétaire par champ et par objet. Si tu supprimes une Application, vérifie d'abord ses finaliseurs. Si tu supprimes une tâche planifiée, retire aussi les droits qu'on lui a donnés.
5. Vérifie : quelques minutes sans synchronisation automatique ni nouvelle génération.
6. Ajoute une prévention dans l'ApplicationSet `mediagenda` (une ressource déjà gérée par une autre Application doit faire **échouer** la synchronisation) et complète RB-200 d'une section « La dérive revient sans cesse ».

**Critères de réussite**
- [ ] `mediagenda-dev` et `labo` `Synced` et `Healthy` ; aucune condition `SharedResourceWarning`.
- [ ] Le Deployment `mediagenda` de dev n'a pas d'autre gestionnaire de champs qu'Argo CD et les contrôleurs du cluster ; pas de HPA en dev, ou bien réplicas ignorés **et** respectés par l'Application.
- [ ] Aucun compte de service d'un espace hors plateforme n'a de droits dans `mediagenda-dev`.
- [ ] Observation de 60 s sans synchronisation automatique ni nouvelle génération (le check l'effectue) ; RB-200 et journal (`INC-4739`) commités ; panne close.

**Vérification** : `lab/bin/check 20 39`

<details><summary>Indice 1</summary>

`kubectl get deploy mediagenda -n mediagenda-dev -o yaml --show-managed-fields` : chaque entrée de `managedFields` dit **qui** (manager), **comment** (Apply, Update), **par où** (sous-ressource `scale`, `status`) et **quand**. Un manager qui n'est ni Argo CD ni un contrôleur du cluster est une piste ; la date de sa dernière écriture aussi.
</details>

<details><summary>Indice 2</summary>

Deux Applications qui déclarent le même objet se le disputent par l'annotation `argocd.argoproj.io/tracking-id` ; Argo CD le signale par une condition `SharedResourceWarning`. Un HPA écrit `spec.replicas` par la sous-ressource `scale`. Une écriture qui vient de l'extérieur de l'espace passe par un compte de service d'un autre espace : cherche les RoleBindings qui le désignent.
</details>

**Pour aller plus loin** (facultatif) : lis les paramètres `controller.self.heal.backoff.*` de `argocd-cmd-params-cm` et calcule le délai de la sixième réparation ; quelle alerte (M21) détecterait une bataille avant l'utilisateur ?

---

### M20-E40 — Panne : le canary ne progresse plus  `BF` `★★★`

> **Ticket INC-4740** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : un canary de recette interrompu, un contrôleur qui ne démarre plus, des synchronisations en boucle pendant le canary, ou une version livrée qui ne part jamais.)* Lucas a livré un petit réglage en recette ; la promotion en production prévue l'après-midi est bloquée.

**Objectifs pédagogiques**
- Lire l'état d'un Rollout (phase, étape, pause, interruption, message), de ses AnalysisRuns (mesures, échecs, erreurs) et des poids réels de la HTTPRoute.
- Situer le blocage : analyse, contrôleur ou greffon, cohabitation Argo CD / Argo Rollouts sur la HTTPRoute, pause manuelle.
- Rétablir et prouver par un canary complet, sans promouvoir de force.

**Prérequis** : M20-E15 à M20-E18 (Argo Rollouts, canary par la Gateway API, analyses), M20-E12 (différences ignorées) ; `lab/bin/check 20 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : le Rollout `mediagenda` de `mediagenda-recette` référence le Deployment du chart (`workloadRef`, réduction progressive), route le trafic par le greffon `argoproj-labs/gatewayAPI` (Services `mediagenda` et `mediagenda-canary`, HTTPRoute `mediagenda`), lance l'analyse de fond `pret-mediagenda` (web) et les tests de fumée `fumee-mediagenda` (Job), puis avance par étapes 10/25/50 % avec des pauses de 2 minutes. Le contrôleur d'Argo Rollouts (2 réplicas) charge le greffon **au démarrage**, depuis l'emplacement déclaré dans `argo-rollouts-config` (valeurs de l'Application `argo-rollouts` dans `plateforme/gitops`).

**Injection** : `lab/bin/break 20 40` (4 variantes).

**Travail demandé**
1. Constate avec `kubectl argo rollouts get rollout mediagenda -n mediagenda-recette` : phase, étape, raison de l'arrêt. Puis les AnalysisRuns et leurs mesures, les poids de la HTTPRoute, l'état du contrôleur et ses journaux, l'historique de synchronisation de `mediagenda-recette`.
2. Écris `outils/canary-etat.sh` (dans `plateforme/outils`) qui photographie tout cela en une commande, pour le journal et pour l'astreinte.
3. Trouve la cause et le commit (ou le geste) qui l'a introduite.
4. Corrige à la source par MR (ou en défaisant le geste manuel, et en notant qui l'avait fait et pourquoi). Ne promeus pas de force un canary dont l'analyse échoue.
5. Vérifie par un **canary complet** en recette : toutes les étapes, analyses `Successful`, poids revenus à 100 % sur le stable, Rollout `Healthy`.
6. Complète RB-200 d'une section « Le canary ne progresse plus ».

**Critères de réussite**
- [ ] Contrôleur Argo Rollouts prêt, sans redémarrage en boucle ; greffon `argoproj-labs/gatewayAPI` déclaré.
- [ ] `mediagenda-recette` `Synced` et `Healthy` ; Rollout `Healthy`, ni en pause ni interrompu, piloté par le greffon ; dernier AnalysisRun `Successful`.
- [ ] Différences de la HTTPRoute ignorées par `mediagenda-recette` ; HTTPRoute revenue à 100 % sur le stable.
- [ ] RB-200, journal (`INC-4740`), `outils/canary-etat.sh` commités ; panne close.

**Vérification** : `lab/bin/check 20 40`

<details><summary>Indice 1</summary>

Une analyse en `Error` n'est pas une analyse en `Failed` : la première dit que la **mesure** n'a pas pu être prise (code HTTP, délai), la seconde que la mesure est mauvaise. `kubectl get analysisrun <nom> -n mediagenda-recette -o yaml` montre les dernières mesures et leur message. Un Rollout interrompu revient seul au stable ; il ne repartira qu'avec une nouvelle révision ou une reprise explicite.
</details>

<details><summary>Indice 2</summary>

Si le contrôleur ne démarre pas, ses journaux disent pourquoi dès les premières lignes (`kubectl -n argo-rollouts logs <pod> --previous`). Si Argo CD resynchronise la recette pendant chaque canary, regarde ce qui change entre deux synchronisations (`argocd app diff`) et ce que l'Application ignore (`spec.ignoreDifferences`). Une pause sans condition de pause dans le statut vient de `spec.paused`.
</details>

**Pour aller plus loin** (facultatif) : ajoute une alerte sur les Rollouts interrompus à partir des métriques du contrôleur (`rollout_info`, à vérifier sur ta version) ; elle sera branchée au M21.

---

### M20-E41 — Panne : une synchronisation a supprimé des ressources  `BF` `★★★`

> **Ticket INC-4741** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection.)* Depuis la dernière synchronisation automatique, MédiAgenda dev renvoie des erreurs 5xx ; des objets ont disparu de l'espace. Lucas jure qu'il n'a « rien supprimé, juste rangé des fichiers ». Julien veut savoir exactement ce qui a été supprimé, et l'assurance que cela ne peut pas arriver en production.

**Objectifs pédagogiques**
- Comprendre l'élagage (`prune`) : avec la synchronisation automatique, Git est la liste exhaustive de ce qui doit exister ; un fichier déplacé, renommé ou oublié dans une liste est une suppression.
- Reconstituer ce qui a été supprimé (opération, historique, rendu des deux révisions) et rétablir par Git.
- Mettre en place les protections : `Prune=false`/`Delete=false` posés systématiquement sur ce qui porte des données, `PruneLast=true`, `Prune=confirm`, production sans synchronisation automatique, porte de MR qui montre ce qu'une fusion supprimera.

**Prérequis** : M20-E08 (`Prune=false,Delete=false` de la base), M20-E10 (ApplicationSet, production manuelle), M20-E36 (`verifier-overlay.sh`) ; `lab/bin/check 20 41` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 20 41` (3 variantes).

**Travail demandé**
1. Constate : ce qui répond et ce qui ne répond plus (`/pret` par la Gateway), les objets manquants, la dernière opération et ses ressources `pruned`.
2. Reconstitue le commit et le **rendu** avant/après (`kubectl kustomize` sur les deux révisions) : liste exacte des objets supprimés, et pourquoi la base CNPG, elle, n'a pas disparu.
3. Rétablis dev par Git (revert par MR). Vérifie que les objets recréés sont identiques.
4. Prévention, chacune par une MR :
   - un component `components/protection-donnees` dans `mediagenda/deploiement` qui pose `Prune=false,Delete=false` sur **toute** base CNPG et **tout** PVC rendus, inclus dans les trois overlays ;
   - `PruneLast=true` dans l'ApplicationSet `mediagenda` ;
   - `outils/verifier-overlay.sh` (E36) affiche ce qui disparaît du rendu et refuse ce qui porte des données ;
   - la production reste sans synchronisation automatique ; écris dans RB-200 comment vérifier, avant de synchroniser la prod, qu'un élagage est prévu (`argocd app diff`, `argocd app sync --dry-run`).
5. Complète RB-200 d'une section « Une synchronisation a supprimé des ressources ».

**Critères de réussite**
- [ ] `mediagenda-dev` `Synced` et `Healthy`, sans ressource manquante ; HTTPRoute de dev résolue ; `https://mediagenda-dev.apps.par1.medisphere.internal/pret` répond 200.
- [ ] Bases CNPG de `mediagenda-*` en `Prune=false` ; `mediagenda-dev` et `mediagenda-recette` en `PruneLast=true` ; `mediagenda-prod` sans synchronisation automatique.
- [ ] RB-200 et journal (`INC-4741`, avec la liste des objets supprimés) commités ; panne close.

**Vérification** : `lab/bin/check 20 41`

<details><summary>Indice 1</summary>

`argocd app get mediagenda-dev --show-operation` liste les ressources de la dernière opération avec leur message (`pruned`). `git show <révision> --stat` dit quels fichiers ont bougé ; le rendu dit quels **objets** ont bougé, et ce n'est pas la même chose (un component non référencé ne produit aucune ligne de diff dans les manifestes rendus… mais retire tout ce qu'il apportait).
</details>

<details><summary>Indice 2</summary>

Dans un `kustomize` de components, l'ordre compte : un correctif avec `target` ne voit que les objets déjà rendus par les components précédents. Documentation « Sync Options » d'Argo CD : `Prune=false`, `Prune=confirm`, `Delete=false`, `PruneLast=true`.
</details>

**Pour aller plus loin** (facultatif) : un générateur de répertoires (`git: directories: overlays/*`) aurait rendu un **déplacement de dossier** bien plus dangereux qu'ici. Explique pourquoi, et ce que `applicationsSync: create-update` et `preserveResourcesOnDeletion` de l'ApplicationSet `mediagenda` changent à ce scénario.

---

### M20-E42 — Panne : le cluster de l'agence est `Unknown`  `BF` `★★★`

> **Ticket INC-4742** — *De : Karim Benali*
> *(Le détail s'affiche à l'injection.)* Dans Argo CD, le cluster de l'agence LYO1 (`lyo-k3s01`) n'est plus joignable et l'application qui y est déployée affiche `Unknown`. L'agence utilise toujours son application locale et dit avoir « juste fait un peu de ménage ».

**Objectifs pédagogiques**
- Situer une perte de connexion à un cluster distant : jeton, autorité (TLS), réseau, droits du compte de service.
- Diagnostiquer des deux côtés : Argo CD (`argocd cluster list/get`, conditions) et le cluster k3s (compte, rôles, pare-feu local).
- Rétablir **sans élargir** les droits ni la confiance (jamais `cluster-admin`, jamais `insecure`).

**Prérequis** : M20-E26 (cluster `lyo-k3s01` enregistré : Secret `cluster-lyo-k3s01`, compte `argocd-gestion` de l'espace `agence`, ApplicationSet `labo-agences`) ; M18 (k3s) ; `lab/bin/check 20 42` vert avant l'injection. **À faire avant le mini-projet** : `lyo-k3s01` y est détruite ; si elle n'existe plus, l'injection refuse et l'exercice se fait sur le corrigé.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 20 42` (4 variantes).

**Travail demandé**
1. Constate côté Argo CD : `argocd cluster list`, `argocd cluster get https://lyo-k3s01.par1.medisphere.internal:6443`, conditions de `labo-lyo-k3s01`. Message exact.
2. Teste la connexion depuis un pod de `k8s-par1` et depuis un nœud (TCP 6443, TLS avec la bonne autorité), puis côté `lyo-k3s01` : compte `argocd-gestion`, son jeton, ses droits (`k3s kubectl auth can-i … --as=system:serviceaccount:agence:argocd-gestion`), le pare-feu local (`nft list ruleset`).
3. Trouve l'étage en cause et ce qui l'a modifié (Secret de cluster, règles, liaisons RBAC).
4. Corrige à la source : Secret de cluster par `secrets-k8s.sh appliquer argocd` depuis le Vault ; règles et droits de `lyo-k3s01` à partir du code (playbook `m20-lyo.yml` et manifestes qu'il dépose ; vérifie que k3s les réapplique vraiment), pas à la main, et note dans ton journal ce que l'agence voulait obtenir avec son « ménage ».
5. Vérifie : cluster `Successful`, `labo-lyo-k3s01` `Synced` et `Healthy`, et `argocd-gestion` toujours limité à l'espace `agence`.
6. Complète RB-200 d'une section « Un cluster distant est Unknown ».

**Critères de réussite**
- [ ] Cluster de l'agence en état de connexion `Successful` (API d'Argo CD) ; Applications qui y déploient `Synced` et `Healthy`.
- [ ] Aucune règle nftables de `lyo-k3s01` ne refuse l'API (6443) ; `argocd-gestion` n'est pas administrateur du cluster et gère encore l'espace `agence`.
- [ ] RB-200 et journal (`INC-4742`) commités ; panne close.

**Vérification** : `lab/bin/check 20 42`

<details><summary>Indice 1</summary>

Quatre messages, quatre étages : `Unauthorized` / « provide credentials » (jeton), `x509` (autorité), `timeout` / `connection refused` (réseau), `forbidden` (droits). Le Secret de cluster se lit sans afficher le jeton : `kubectl -n argocd get secret cluster-lyo-k3s01 -o json | jq '.data.config | @base64d | fromjson | {tlsClientConfig: (.tlsClientConfig | {insecure, caData: (.caData | length)}), jeton: (.bearerToken | length)}'`.
</details>

<details><summary>Indice 2</summary>

Sur `lyo-k3s01` : le jeton attendu est celui du Secret `argocd-gestion-jeton` de l'espace `agence` ; l'autorité est `/var/lib/rancher/k3s/server/tls/server-ca.crt`. Les manifestes déposés dans `/var/lib/rancher/k3s/server/manifests/` sont appliqués par k3s quand ils changent : un objet supprimé à la main n'est pas forcément recréé tout de suite.
</details>

**Pour aller plus loin** (facultatif) : Argo CD sait renouveler l'accès par d'autres moyens qu'un jeton longue durée (`execProviderConfig`, fournisseurs d'identité). Lequel conviendrait à une agence reliée par un tunnel, et pourquoi le lab garde un jeton (M20-E26) ?

---

### M20-E43 — Astreinte : la mise en production tourne mal  `BF` `★★★★`

> **Ticket INC-4743** — *De : Nadia Roussel (responsable astreinte)* — priorité P1
> *(Le détail s'affiche à l'injection : trois remontées pendant la mise en production de MédiAgenda.)* La mise en production est suspendue tant que l'incident n'est pas clos ; le gel des changements commence le lendemain à 16 h (M20-E29).

**Objectifs pédagogiques**
- Mener un incident à plusieurs causes indépendantes : trier, prioriser (ce qui empêche de voir et de corriger d'abord), communiquer, ne pas mélanger les correctifs.
- Garder la discipline GitOps sous pression : tout correctif par Git ou par le code de la plateforme, aucune désactivation durable de l'auto-synchronisation, aucune synchronisation de production pendant l'incident.
- Rédiger un post-mortem sans reproche, avec chronologie, empreintes des commits fautifs et correctifs, analyse de la détection et actions.

**Prérequis** : M20-E35 à M20-E42 (toutes leurs variantes rencontrées au moins une fois), RB-200 complété, modèle de post-mortem du module 00 ; `lab/bin/check 20 35` à `lab/bin/check 20 42` verts.
**Durée indicative** : 2 h (rétablissement) + 45 min (post-mortem).

**Contexte technique** : le script tire trois pannes distinctes parmi E35 à E42 (au plus une qui touche `mediagenda-dev`), avec leurs variantes au hasard ; `lab/bin/break 20 43 --variante N` force un trio. L'injection prend de 10 à 30 minutes. Elle peut rendre un dépôt illisible pour Argo CD : tant que c'est le cas, tes correctifs dans Git ne lui parviennent pas.

**Injection** : `lab/bin/break 20 43`

**Travail demandé**
1. Prends le ticket : un premier message à Nadia (ce que tu vois, ce que tu fais, quand tu reviens) dans les 10 minutes.
2. Trie les trois symptômes : lequel t'empêche de voir ou de corriger les autres ? Commence par lui.
3. Pour chaque panne : diagnostic (journal), correctif par MR ou par le code de la plateforme, vérification par son check (`lab/bin/check 20 3X`).
4. Toutes les 30 minutes, un point à Nadia ; à la fin, l'autorisation de reprendre la mise en production (et pas avant).
5. Rédige le post-mortem `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-4743-<titre>.md` (modèle du module 00) : chronologie, causes racines, détection (qu'est-ce qui aurait dû alerter avant Julien et Nadia ?), ce qui a bien marché, actions avec responsables et échéances. Cite les commandes de diagnostic et les empreintes des commits fautifs et correctifs ; aucun jeton.
6. Clos l'astreinte : `lab/bin/break 20 43 --annuler` (aucune panne ne doit rester marquée).

**Critères de réussite**
- [ ] Les checks E35 à E42 sont verts (le check E43 les rejoue).
- [ ] Le post-mortem est commité, avec chronologie, causes, détection, actions, commandes de diagnostic et empreintes de commits ; aucun secret recopié.
- [ ] Aucune panne M20 encore marquée active.

**Vérification** : `lab/bin/check 20 43`

<details><summary>Indice 1</summary>

Un dépôt illisible pour Argo CD se corrige en premier : sans lui, aucun autre correctif par Git n'arrive dans le cluster, et tu risques de conclure qu'un bon correctif « ne marche pas ».
</details>

<details><summary>Indice 2</summary>

`argocd app list` en une commande donne l'état de tout ; `outils/argocd-diagnostic.sh`, `outils/canary-etat.sh` et `outils/qui-ecrit.sh` photographient le reste. Les commits de la panne se retrouvent par `git log --author='Lucas Martin' --since=…` dans les deux dépôts.
</details>

---

### M20-E44 — Sous le capot : du commit à l'objet  `LAB` `★★★★`

> **Ticket PLAT-2144** — *De : Karim Benali*
> Les pannes ont montré qu'on lit Argo CD comme une boîte noire : « il est vert », « il est rouge ». Je veux qu'on sache ce qui se passe entre la fusion d'une MR et le pod qui démarre : qui reçoit quoi, qui génère quoi, ce qui est mis en cache et où, comment la comparaison est faite. Mesure-le sur une vraie livraison en dev, et écris-le pour l'équipe et pour l'astreinte.

**Objectifs pédagogiques**
- Suivre une livraison à travers les composants d'Argo CD : API et webhook, contrôleur d'applications (réconciliation, cache d'état du cluster, comparaison, opération), repo-server (copies des dépôts, génération des manifestes, cache), Redis.
- Mesurer chaque étape et identifier où passe le temps (attente d'interrogation, file du repo-server, vagues, sondes).
- Relier ce que l'on voit dans les journaux, les métriques et Redis aux symptômes des pannes du palier.

**Prérequis** : M20-E02, M20-E12, M20-E27 (webhooks, performance) ; toutes les pannes du palier closes.
**Durée indicative** : 3 à 4 h.

> ⚠️ **Attention** : le niveau de journalisation `debug` du contrôleur et du repo-server multiplie le volume de leurs journaux (Loki les gardera au M22) et ralentit un peu la réconciliation. Active-le le temps des mesures seulement, note l'heure, et reviens au niveau `info` par la release Helmfile avant de clore l'exercice. Ne lance pas `kubectl debug` sur les pods d'Argo CD (un conteneur éphémère ne se retire qu'en recréant le pod) : `kubectl exec` suffit.

**Travail demandé**
1. **Préparer la mesure.** Copie le squelette `modules/20-gitops/ressources/E44-sous-le-capot/sous-le-capot.md` dans `~/medisphere/docs/livraison/gitops/`. Passe temporairement le contrôleur et le repo-server en `debug` **par la release** (valeurs surchargées le temps de la mesure, sans rien modifier à la main dans `argocd-cmd-params-cm` : la release est en *server-side apply* depuis M20-E02 : un `kubectl patch` sur un champ qu'elle possède le ferait passer à un autre gestionnaire de champs, et le retour en arrière par la release deviendrait incertain — écart invisible pour `helmfile diff` sans `--three-way-merge` (M17-E14), conflit possible à l'`apply`) :
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff \
       --set 'configs.params.controller\.log\.level=debug' --set 'configs.params.reposerver\.log\.level=debug'
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply \
       --set 'configs.params.controller\.log\.level=debug' --set 'configs.params.reposerver\.log\.level=debug'
   ```
   Le `diff` ne doit montrer que ces deux clés (et les sommes de contrôle des pods qui en dépendent : le chart redémarre lui-même le contrôleur et le repo-server).
2. **Une livraison chronométrée.** Fais fusionner une MR anodine sur `overlays/dev` de `mediagenda/deploiement` (un paramètre de `debogage`, par exemple), et relève pour cette révision : `committed_date` et `merged_at` (API GitLab), la ligne `Received push event` du serveur, les lignes `Refreshing app status`, `Initialized new operation`, `updated '…' operation (phase: …)` et `Reconciliation completed` (avec ses durées) du contrôleur, les lignes de génération du repo-server, `startedAt`/`finishedAt` de l'opération, la création et la disponibilité du pod neuf. Écris l'outil `outils/chronometrer-livraison.sh` (dans `plateforme/outils`) qui rassemble ces horodatages en une commande.
   ```
   admin@adm01:~$ kubectl -n argocd logs deploy/argocd-server --since=10m | grep 'push event'
   admin@adm01:~$ kubectl -n argocd logs statefulset/argocd-application-controller --since=10m | grep '"application":"mediagenda-dev"' | jq -r '[.time, .msg, (.time_ms // "")] | @tsv'
   admin@adm01:~$ kubectl -n argocd logs deploy/argocd-repo-server --since=10m | jq -r 'select(.msg | test("manifest|git|kustomize"; "i")) | [.time, .msg] | @tsv' | head -n 30
   ```
   Refais la mesure une fois **sans webhook** (désactive le webhook du projet dans GitLab le temps d'une MR, puis réactive-le) et compare.
3. **Le repo-server.** Regarde ses copies de dépôts et le cache :
   ```
   admin@adm01:~$ kubectl -n argocd exec deploy/argocd-repo-server -- ls -la /tmp/_argocd-repo/
   admin@adm01:~$ kubectl -n argocd exec deploy/argocd-repo-server -- sh -c 'env | grep -E "^ARGOCD_(REPO|EXEC)"'
   ```
   Pourquoi des UUID et pas des noms de dépôts ? Que fait `argocd app get mediagenda-dev --hard-refresh` que ne fait pas `--refresh` ?
4. **Redis.** Liste les **familles** de clés (jamais les valeurs, qui peuvent contenir des manifestes) :
   ```
   admin@adm01:~$ kubectl -n argocd exec deploy/argocd-redis -- sh -c \
       'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning --scan --count 500 | cut -d"|" -f1 | sort | uniq -c'
   ```
   Relie chaque famille à un composant ; qu'est-ce qui se passe si Redis redémarre ?
5. **Le contrôleur et la comparaison.** Établis la stratégie de comparaison réellement utilisée par `mediagenda-dev` (annotation de l'Application, paramètres du contrôleur) ; compare le rendu servi par Argo CD et le rendu local :
   ```
   admin@adm01:~$ argocd app manifests mediagenda-dev --source git > /tmp/argo.yaml
   admin@adm01:~/src/mediagenda-deploiement$ kubectl kustomize overlays/dev > /tmp/local.yaml
   admin@adm01:~$ diff <(yq -N '.kind + "/" + .metadata.name' /tmp/argo.yaml | sort) <(yq -N '.kind + "/" + .metadata.name' /tmp/local.yaml | sort)
   admin@adm01:~$ argocd app manifests mediagenda-dev --source live | yq 'select(.kind == "Deployment") | .metadata.annotations'
   ```
   Relève l'annotation de suivi réelle du Deployment de dev et explique ce qu'Argo CD en fait.
6. **Métriques.** Interroge les métriques du contrôleur (port 8082) et du repo-server (port 8084) par `kubectl port-forward` : `argocd_app_reconcile`, `argocd_git_request_total`, `argocd_app_sync_total`, `argocd_cluster_api_resource_objects`. Lesquelles auraient vu les pannes E35, E37 et E39 avant l'utilisateur ?
7. **Rétablir.** Reviens au niveau `info` par la release (`helmfile -e par1 -l composant=argocd apply` **sans** les `--set`, après un `diff` qui ne montre que le retour des deux clés), vérifie `argocd-cmd-params-cm`, commite le livrable.

**Critères de réussite**
- [ ] `docs/livraison/gitops/sous-le-capot.md` commité : chronologie mesurée (horodatages), copies du repo-server (`/tmp/_argocd-repo/…`), familles de clés Redis, journal `Reconciliation completed`, annotation de suivi réelle du Deployment de dev, comparaison des rendus par `argocd app manifests`, stratégie de comparaison établie par sa source.
- [ ] `argocd-cmd-params-cm` : journaux du contrôleur et du repo-server hors `debug` ; aucun conteneur éphémère dans l'espace `argocd`.
- [ ] `outils/chronometrer-livraison.sh` dans `plateforme/outils`.

**Vérification** : `lab/bin/check 20 44`

<details><summary>Indice 1</summary>

Les journaux d'Argo CD sont en JSON (`global.logging.format: json`) : `jq` les filtre par champ (`application`, `msg`, `time`, `time_ms`). Le contrôleur est un StatefulSet partitionné (M20-E27) : l'Application de dev est traitée par **un** des réplicas ; `kubectl logs statefulset/…` n'en lit qu'un, cherche le bon.
</details>

<details><summary>Indice 2</summary>

Les clés du repo-server commencent par `mfst|` (manifestes générés), `git-refs|` (références d'un dépôt), `appdetails|`, `revisionmetadata|` ; celles du contrôleur décrivent l'état des applications et des clusters. Le mot de passe de Redis est dans la variable `REDIS_PASSWORD` du conteneur (Secret `argocd-redis`) : ne le recopie nulle part.
</details>

**Pour aller plus loin** (facultatif) : la *Source Hydrator* (bêta en 3.5) déplace la génération des manifestes **avant** Git (un commit de manifestes rendus par environnement). Qu'est-ce que cela changerait aux pannes E35 (génération impossible) et E41 (élagage), et au rendu commité de MédiAgenda (ADR-0170) ?

---

### M20-E45 — Questions expert : GitOps  `Q` `★★★`

Réponds par écrit, en argumentant (5 à 15 lignes par question). Aucune manipulation n'est demandée ; tu peux t'appuyer sur ce que tu as observé au palier.

1. Une Application est `Synced` et `Healthy`, et pourtant le cluster ne fait pas ce que Git décrit. Donne trois situations réelles où c'est possible, et pour chacune ce qui l'aurait montrée.
2. Argo CD propose trois façons de calculer un diff (3-way « historique », *structured merge*, comparaison côté serveur). Explique ce que chacune compare, une panne que chacune laisse passer, et pourquoi l'ApplicationSet `mediagenda` ajoute `IncludeMutationWebhook=true`.
3. `selfHeal` répare une dérive. Expliquez pourquoi il ne répare pas une bataille entre deux écrivains, ce que fait l'attente exponentielle, et pourquoi désactiver `selfHeal` « pour calmer » est une erreur.
4. Un collègue propose `ignoreDifferences` sur `/spec` pour toutes les ressources d'une Application « qui sont souvent OutOfSync ». Que réponds-tu ? Où place-t-on la limite entre ignorer un champ et le décrire dans Git ? Que change `RespectIgnoreDifferences=true` ?
5. `prune: true` et `selfHeal: true` sur la production : arguments pour et contre, et ce que MédiSphère a retenu (ADR-0200). Quelles protections rendent un élagage en production acceptable ?
6. Une Application porte le finaliseur `resources-finalizer.argocd.argoproj.io`. Décris ce qui se passe à sa suppression, avec et sans le contrôleur en marche, et la procédure pour supprimer une Application **sans** toucher à ses charges (M20-E28).
7. Vagues et hooks : pourquoi le hook de migration de MédiAgenda est-il un hook `Sync` en vague -1 et pas un hook `PreSync` ? Qu'arrive-t-il à une synchronisation dont une ressource d'une vague ne devient jamais saine ?
8. `argocd app rollback` contre `git revert` : que fait chacun, que devient la synchronisation automatique, et lequel garde Git vrai ?
9. Le repo-server génère les manifestes. Quelles sont ses entrées (dépôt, révision, options, outils, plugins), où met-il le résultat en cache, et quels risques de sécurité porte-t-il (pourquoi M20-E25 lui interdit Internet) ?
10. Le cache d'état du contrôleur surveille tous les types de ressources des clusters gérés. Quelles conséquences sur la mémoire, sur les droits nécessaires dans un cluster distant (`resource.respectRBAC`), et sur le comportement quand une API d'extension (CRD) est indisponible ?
11. Les Secrets ne sont pas dans Git chez MédiSphère jusqu'au M25. Quels angles morts cela crée-t-il pour Argo CD (pannes E37 et E42), et comment External Secrets ou SOPS les réduiront-ils ?
12. Canary par la Gateway API : qui écrit les poids de la HTTPRoute, qui écrit le reste, et que se passe-t-il si Argo CD et le greffon se disputent les poids ? Quelle est la différence entre une analyse en `Error` et en `Failed`, et l'effet de `consecutiveErrorLimit` ?
13. Webhook GitLab contre interrogation périodique : quels gains, quels risques (déni de service, secret partagé, liste d'autorisation des requêtes locales) ? Que se passe-t-il si le webhook est perdu ?
14. Multi-cluster : enregistrer un cluster avec un compte limité à un espace (`namespaces`, `clusterResources: false`) plutôt qu'en `cluster-admin`. Ce que l'on gagne, ce que l'on perd, et ce qui casse quand on ajoute une nouvelle sorte d'objet à l'application de l'agence.
15. Flux contre Argo CD pour MédiSphère, après le palier 4 : un argument technique en faveur de Flux que les pannes ont rendu concret, et un argument en faveur d'Argo CD. Est-ce que l'ADR-0200 doit changer ?
