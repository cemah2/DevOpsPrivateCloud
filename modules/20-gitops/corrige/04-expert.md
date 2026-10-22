# Module 20 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Avec Argo CD, « j'ai resynchronisé et c'est reparti » est presque toujours faux : soit rien n'a changé (la même révision échoue de la même façon), soit la synchronisation forcée a masqué la cause (un objet supprimé et recréé, une différence écrasée qui reviendra).

Les scripts d'injection sont dans `corrige/pannes/` : `_m20-commun.sh` contient les fonctions partagées — commits « de Lucas » par l'API de GitLab (branche, commit dont l'auteur est Lucas Martin, MR, attente du pipeline, fusion avec ton jeton d'administration), annulation par **commit inverse** (API `revert`, MR, fusion ; jamais de réécriture d'historique), copie de travail d'un dépôt et rendu local des overlays (`kubectl kustomize`) pour vérifier avant injection ce qui disparaîtrait, sauvegarde et restauration des objets modifiés hors de Git (JSON nettoyé, `~/.local/state/workbook/M20-EXX/`, 600), lecture et rafraîchissement des Applications. Chaque commit de panne porte la ligne `Réf-workbook: M20-EXX` dans son message.

Pour chaque panne, la section de RB-200 attendue est donnée en exemple dans `corrige/fichiers/M20-EXX/docs/RB-200-section-*.md`, et les outils écrits au fil du palier (`argocd-diagnostic.sh`, `verifier-overlay.sh`, `tester-sante.sh`, `qui-ecrit.sh`, `canary-etat.sh`, `chronometrer-livraison.sh`) dans `corrige/fichiers/M20-EXX/outils/` ; tous passent `shellcheck`.

> **Remarque sur les traces** : les MR de panne sont ouvertes et fusionnées avec **ton** jeton d'administration ; seul l'auteur du commit est Lucas. Dans le journal d'audit de GitLab comme dans celui de Kubernetes (objets modifiés avec ton kubeconfig), c'est donc ton nom qui apparaît à l'heure de l'injection. En production, ce serait celui de Lucas : c'est l'argument pour des identités nominatives partout, y compris pour les outils.

Les sorties reproduites sont **représentatives** : noms de pods, empreintes, horodatages et formulations exactes varient selon ton lab et les versions (Argo CD 3.5.5, Argo Rollouts 1.10.1, greffon Gateway API 0.17.0, Kubernetes 1.36, CNPG 1.30, k3s v1.36.5+k3s1).

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- Ensemble des pannes : écrites contre les fichiers des paliers 1 à 3 (ApplicationSet `mediagenda`, components `dependances`, `migrations`, `canary`, valeurs d'Argo Rollouts, Secret de cluster de `lyo-k3s01`) et validées hors cluster (rendus Kustomize des variantes, filtres `jq`/`yq`, `shellcheck`, contrôle de santé Lua évalué par `argocd admin settings resource-overrides health` 3.5.5) ; le cheminement complet MR → pipeline → fusion → synchronisation n'a pas été joué sur un lab réel. Le délai d'attente d'un pipeline de MR se règle par `WB_M20_DELAI_FUSION`.
- E35 v4 (quantité réécrite par le webhook de CNPG) : avec `ServerSideDiff=true,IncludeMutationWebhook=true` (ApplicationSet de M20-E12), la différence est absorbée et la variante est sautée — c'est attendu. Sans ces options, la normalisation de la quantité par le webhook de CNPG (décodage puis ré-encodage de l'objet) est **supposée**.
- E35 v1 : message exact de l'opération bloquée (`waiting for healthy state of /PersistentVolumeClaim/mediagenda-archives`, relevé dans le code de la 3.5.5) ; un PVC `Pending` est jugé `Progressing` par Argo CD.
- E36 v2 : selon la version, la ressource non permise apparaît comme condition de l'Application avant l'opération, ou dans le résultat de l'opération (« one or more synchronization tasks are not valid ») : le script accepte les deux.
- E39 v2 : la « bataille » de deux Applications sur les mêmes objets (annotation de suivi réécrite, condition `SharedResourceWarning`) dépend de la version ; le script exige l'un des deux signes.
- E40 v2 : refus de démarrer du contrôleur d'Argo Rollouts quand le greffon déclaré en `file://` est introuvable (documenté pour les emplacements `http(s)`, déduit du code pour `file://`).
- E42 v4 : k3s réapplique les manifestes de `/var/lib/rancher/k3s/server/manifests/` quand ils changent ; s'il recrée la liaison supprimée de lui-même, la variante est sautée.
- E44 : noms exacts des lignes de journal du repo-server en `debug` (les commandes filtrent large) ; familles de clés de Redis relevées dans le code de la 3.5.5.

---

## Méthode commune aux pannes GitOps

1. **Lire ce qu'Argo CD dit, en entier.** `argocd app get <app>` donne le résumé ; le JSON (`kubectl -n argocd get applications.argoproj.io <app> -o json`) donne `status.sync` (statut, révision comparée), `status.health`, `status.conditions` (erreurs de comparaison, de spécification, avertissements), `status.operationState` (phase, message, révision, ressources et leur message), `status.resources[]` (statut, santé, `requiresPruning`) et `status.history`. L'outil `outils/argocd-diagnostic.sh` (E35) les photographie pour le journal.
2. **Situer l'étage.** Git (commit, rendu) → repo-server (génération : outils, options, accès au dépôt) → contrôleur (comparaison : stratégie, différences ignorées ; opération : vagues, hooks, dry-run client puis application) → API Kubernetes (validation, admission, quotas, AppProject avant elle) → contrôleurs du cluster (Deployment, Rollout, CNPG) → pod.
3. **Chercher ce qui a bougé.** `argocd app history <app>` (révisions et initiateur), `git log -p` sur le chemin suivi, les MR fusionnées ; hors de Git : `metadata.managedFields` (qui a écrit quoi et quand), annotations, journal d'audit de l'API (M14-E27), configuration d'Argo CD (`helmfile -e par1 -l composant=argocd diff`).
4. **Protéger avant d'agir.** Pas de synchronisation de production pendant un incident ; jamais de suppression d'Application sans regarder ses finaliseurs ; pas de `--force`/`--replace`.
5. **Corriger à la racine, dans le code.** Git (MR), release Helmfile `argocd`, `secrets-k8s.sh`, rôles et playbooks Ansible.
6. **Prévenir** : quelle porte de MR, quel réglage d'Argo CD, quelle alerte (M21) aurait arrêté la panne avant l'utilisateur ?

---

### M20-E35 — Panne : l'application reste `OutOfSync`

**Démarche de diagnostic**

*Symptômes* : `mediagenda-dev` `OutOfSync` en permanence ; selon la variante, opérations `Succeeded` qui n'y changent rien (v2, v4), opération `Running` sans fin (v1), statut `Unknown` et condition `ComparisonError` sur les trois environnements (v3).

*Hypothèses* : ressource retirée de Git mais protégée de l'élagage ; opération qui attend une vague qui ne sera jamais saine ; manifestes impossibles à générer ; champ réécrit par l'API ou un webhook.

**Étape 1 — Constater sans toucher.**

```
admin@adm01:~$ argocd app get mediagenda-dev
Name:               argocd/mediagenda-dev
Project:            mediagenda
Sync Policy:        Automated (Prune)
Sync Status:        OutOfSync from main (5c1d2e7)
Health Status:      Healthy
…
GROUP               KIND                   NAMESPACE       NAME            STATUS     HEALTH   HOOK  MESSAGE
postgresql.cnpg.io  Cluster                mediagenda-dev  mediagenda-db   OutOfSync  Healthy        ignored (no prune)
admin@adm01:~$ outils/argocd-diagnostic.sh mediagenda-dev > /tmp/e35.txt
```

L'outil (`corrige/fichiers/M20-E35/outils/argocd-diagnostic.sh`) lit l'Application par `kubectl` (lecture seule), affiche l'état, les conditions, l'opération (phase, message, révision, initiateur), les ressources non conformes (statut, santé, `requiresPruning`, message de santé), les cinq dernières opérations, les ressources en échec de l'opération et, avec `--diff`, `argocd app diff --exit-code=false`. Il évite la question « tu peux me copier ce que tu vois ? » pendant une astreinte.

**Variante 1 — une vague qui ne sera jamais saine.**

```
admin@adm01:~$ kubectl -n argocd get applications.argoproj.io mediagenda-dev -o json | jq '.status.operationState | {phase, message, startedAt}'
{
  "phase": "Running",
  "message": "waiting for healthy state of /PersistentVolumeClaim/mediagenda-archives",
  "startedAt": "2026-11-04T09:12:44Z"
}
admin@adm01:~$ kubectl -n argocd logs statefulset/argocd-application-controller --since=10m | grep '"application":"mediagenda-dev"' | jq -r .msg | sort | uniq -c
     14 Skipping auto-sync: another operation is in progress
admin@adm01:~$ kubectl -n mediagenda-dev describe pvc mediagenda-archives | tail -n 3
  Warning  ProvisioningFailed  …  storageclass.storage.k8s.io "ceph-rbd-ssd" not found
admin@adm01:~/src/mediagenda-deploiement$ git log -1 -p -- overlays/dev
commit 7a3c9e21…  Author: Lucas Martin <lucas.martin@medisphere.internal>
    feat(dev): volume d'archives et fuseau explicite
    …
+  argocd.argoproj.io/sync-wave: "-2"
+  storageClassName: ceph-rbd-ssd
```

Argo CD applique les vagues dans l'ordre et **attend qu'une vague soit saine** avant la suivante (M20-E11). Le PVC est en vague -2 avec la base et Valkey ; sa classe n'existe pas (`ceph-rbd`, `ceph-rbd-retain`, `ceph-rbd-chiffre`, `cephfs` existent, pas `ceph-rbd-ssd`), il reste `Pending`, donc `Progressing` pour Argo CD ; la ConfigMap (vague -3) est déjà appliquée, le Deployment (vague 0) ne le sera jamais. Aucune limite de durée par défaut (`controller.sync.timeout.seconds: "0"`) : l'opération attend indéfiniment, et toute synchronisation suivante est refusée (« another operation is in progress »). Lucas « clique sur Sync » : Argo CD lui répond qu'une opération est en cours.

Correctif : (1) revert par MR (ou correction : `storageClassName: ceph-rbd`, si le besoin d'archives est confirmé par Julien — un volume en dev porte des données : protège-le, E41) ; (2) **puis** terminer l'opération bloquée, sinon le commit correctif attend derrière elle : `argocd app terminate-op mediagenda-dev` ; la synchronisation automatique repart sur la nouvelle révision. Le PVC `Pending` est élagué (aucune donnée : jamais lié) ; s'il porte `Prune=false` (component de protection d'E41), supprime-le toi-même après avoir vérifié sa phase.

**Variante 2 — ressource retirée de Git mais protégée de l'élagage.**

La sortie de l'étape 1 : `Cluster mediagenda-db … OutOfSync … ignored (no prune)` et, dans le JSON, `requiresPruning: true`. Le commit : un correctif `$patch: delete` sur le Cluster dans `overlays/dev/kustomization.yaml` (« la base sera fournie par la plateforme »). Argo CD voudrait supprimer la base (elle n'est plus dans le rendu, `prune` est actif), mais l'annotation `argocd.argoproj.io/sync-options: Prune=false,Delete=false` posée en M20-E08 l'en empêche : l'opération réussit (« ignored (no prune) »), l'application reste `OutOfSync` — et c'est exactement le comportement voulu pour une base. Le message `ignored (requires pruning)` serait celui d'une Application **sans** `prune` automatique.

Correctif : ce n'est pas à Argo CD de trancher. Julien confirme qu'aucune base partagée n'existe : revert par MR. Si la base devait vraiment partir : ticket CHG, sauvegarde CNPG vérifiée (M16), suppression manuelle, et retrait de Git dans la même fenêtre.

**Variante 3 — génération impossible : version de Kustomize non déclarée.**

```
admin@adm01:~$ argocd app get mediagenda-dev -o json | jq -r '.status.conditions[].message'
Failed to load target state: failed to generate manifest for source 1 of 1: rpc error: code = Unknown desc = kustomize version v5.8.1 is not registered
admin@adm01:~/src/gitops$ git log -1 -p -- applications/mediagenda.yaml
    chore(mediagenda): épingler Kustomize v5.8.1 comme dans la CI
+        kustomize:
+          version: v5.8.1
```

`spec.source.kustomize.version` demande une version **supplémentaire**, à déclarer dans `argocd-cm` (`kustomize.path.v5.8.1: /chemin/vers/le/binaire`) et à embarquer dans l'image du repo-server. Argo CD 3.5 embarque déjà Kustomize 5.8.1 comme version par défaut : l'épinglage est inutile, et sans déclaration il casse la génération des trois Applications de l'ApplicationSet (statut `Unknown`, rien ne se déploie, ni dev ni la synchronisation manuelle de prod). Correctif : revert dans `plateforme/gitops`. Le besoin de Lucas (même version en CI et dans Argo CD) est légitime : il se satisfait en **vérifiant** la version dans la CI (`verifier-overlay.sh` d'E36 compare `kustomize version` à v5.8.1), pas en épinglant côté Argo CD.

**Variante 4 — champ réécrit par un webhook (labs sans comparaison côté serveur).**

```
admin@adm01:~$ argocd app diff mediagenda-dev --exit-code=false
===== postgresql.cnpg.io/Cluster mediagenda-dev/mediagenda-db ======
33c33
<       memory: 256Mi
---
>       memory: 0.25Gi
```

Même valeur, deux écritures : Git dit `0.25Gi`, le webhook de défaut de CNPG décode l'objet et le ré-encode sous sa forme canonique `256Mi`. La comparaison 3-way historique compare les chaînes : différence permanente, que chaque synchronisation « corrige » sans effet. Avec la comparaison **côté serveur** et les webhooks de mutation (`ServerSideDiff=true,IncludeMutationWebhook=true`, ApplicationSet de M20-E12), Argo CD calcule l'état attendu en passant par l'API **et** le webhook : la différence disparaît, et le script d'injection déclare la variante sans effet. Correctif durable : écrire dans Git la forme canonique (`256Mi`), ou garder la comparaison côté serveur ; un `ignoreDifferences` sur ce champ précis serait acceptable, jamais sur `/spec`.

**Vérification** : `argocd app get mediagenda-dev --hard-refresh` → `Synced`, `Healthy` ; attendre une réconciliation (3 min) : la différence ne revient pas ; `lab/bin/check 20 35`.

**Explications** — un `OutOfSync` persistant vient toujours d'un écart entre ce qu'Argo CD **compare** et ce que le cluster **garde** : une ressource qu'il n'a pas le droit d'élaguer, une ressource qu'il n'a pas pu appliquer (opération bloquée), des manifestes qu'il n'a pas pu générer, ou une valeur qu'un tiers réécrit. Les trois premiers se lisent dans `status.operationState`, `status.resources[].requiresPruning` et `status.conditions` ; le quatrième dans le diff et les `managedFields`.

**Pièges classiques**
- `argocd app sync --force` : supprime et recrée les objets qui diffèrent. Sur un Cluster CNPG, c'est une destruction de base (le finaliseur de CNPG supprime les PVC). Le `Prune=false` ne protège pas d'un `--force`.
- Lancer une nouvelle synchronisation sans terminer l'opération bloquée (v1) : elle est refusée ; terminer l'opération sans corriger : la suivante bloquera au même endroit.
- `ignoreDifferences` large pour faire passer au vert : masque aussi la prochaine vraie dérive.
- Oublier que l'ApplicationSet régénère l'Application : un `argocd app set mediagenda-dev --kustomize-version …` (ou une modification de l'Application) est défait par le contrôleur des ApplicationSets.

**En production chez MédiSphère** : `controller.sync.timeout.seconds` fixé (30 min) dans la release `argocd` pour qu'une opération bloquée finisse en échec et notifie (`on-sync-failed`) au lieu d'attendre en silence ; un déclencheur de notification sur `sync.status == 'Unknown'` (ajouté après INC-4743) ; métrique `argocd_app_info{sync_status="OutOfSync"}` durable plus de 30 min → alerte (M21).

---

### M20-E36 — Panne : la synchronisation échoue

**Démarche de diagnostic**

*Symptômes* : `Sync failed` sur `mediagenda-dev`, application `OutOfSync`, rien de nouveau en dev ; le pipeline de la MR était vert.

*Hypothèses* : l'API refuse un objet (validation, immutabilité) ; l'AppProject refuse une ressource ou une destination ; un hook échoue ; l'admission refuse (quota, politique).

**Étape 1 — Le message de l'opération.**

```
admin@adm01:~$ argocd app get mediagenda-dev --show-operation
Operation:          Sync
Sync Revision:      e81f0c4…
Phase:              Failed
Message:            one or more objects failed to apply, reason: Deployment.apps "mediagenda" is invalid: spec.selector: Invalid value: v1.LabelSelector{…"medisphere.internal/equipe":"mediagenda"…}: field is immutable
```

Argo CD fait d'abord un **essai à blanc côté client** (validation du YAML), puis applique vague par vague. Les refus de l'API (immutabilité, quota, webhook) n'apparaissent donc qu'à l'application réelle. Une synchronisation en échec n'est **pas relancée** pour la même révision, au-delà des `retry` de l'ApplicationSet (3 essais, 30 s puis 1 et 2 min) : le journal du contrôleur écrit ensuite `Skipping auto-sync: failed previous sync attempt to [e81f0c4…] and will not retry for [e81f0c4…]`, et l'Application porte une condition `SyncError` (« Failed last sync attempt to … »). (Le message `already attempted sync to … with timeout …` est celui de l'auto-réparation en attente, E39.) Ce qui tourne en dev n'a pas changé (l'objet refusé n'a pas été modifié ; les autres objets de la vague, inchangés, ont été réappliqués à l'identique).

**Variante 1 — sélecteur modifié (champ immuable).** Le correctif de Lucas ajoute `medisphere.internal/equipe` au sélecteur **et** au modèle de pod. Le sélecteur d'un Deployment est immuable depuis `apps/v1` : changer de sélecteur, c'est créer un autre objet. Le besoin (filtrer par équipe dans les tableaux de bord) se satisfait par l'**étiquette du modèle de pod seule** (`labels` de Kustomize avec `includeTemplates: true`, `includeSelectors: false` — exactement ce que fait déjà l'overlay pour l'environnement), ou par les étiquettes déjà posées par le chart. Correctif : revert, puis MR qui pose l'étiquette au bon endroit. (Changer réellement un sélecteur : nouveau nom d'objet, bascule, retrait de l'ancien, planifiés.)

*Avec la comparaison côté serveur* (`ServerSideDiff=true`, ApplicationSet de M20-E12, cas du lab de référence), cette variante ne va même pas jusqu'à la synchronisation : l'essai à blanc *server-side apply* du diff se heurte au champ immuable sur le Deployment **existant**, la comparaison entière échoue (`ComparisonError` : `Failed to compare desired state to live state: … serverSideDiff error: error running server side apply in dryrun mode for resource Deployment/mediagenda: … field is immutable`), le statut de synchronisation passe à `Unknown` et la synchronisation automatique ne se déclenche pas (`Skipping auto-sync: application status is Unknown`). Même diagnostic, même correctif ; après le revert, l'Application redevient `Synced` sans opération nouvelle : lance une synchronisation pour que la dernière opération porte sur la révision courante (critère de réussite).

**Variante 2 — ressource de portée cluster refusée par l'AppProject.**

```
Message:            one or more synchronization tasks are not valid
…  rbac.authorization.k8s.io  ClusterRole  mediagenda-lecture-noeuds  SyncFailed  PruneSkipped  resource rbac.authorization.k8s.io:ClusterRole is not permitted in project mediagenda
```

`clusterResourceWhitelist: []` (M20-E07) : l'équipe ne crée aucun objet de cluster. Le refus arrive **avant** toute application (tâches invalides). Correctif : revert ; le besoin (lire les nœuds pour connaître sa baie) se satisfait sans droit de cluster : l'API descendante (*downward API*) donne le nom du nœud au pod (`spec.nodeName` en variable d'environnement) et la topologie se lit dans les étiquettes que la plateforme expose ; si un droit de cluster était vraiment nécessaire, il serait porté par `plateforme/k8s`, relu par la plateforme.

**Variante 3 — hook `PreSync` qui échoue.**

```
Message:            one or more synchronization tasks completed unsuccessfully, reason: Job has reached the specified backoff limit
admin@adm01:~$ kubectl -n mediagenda-dev logs job/verifier-base
nc: bad address 'mediagenda-bd-rw'
```

Le hook passe **avant toutes les vagues** ; il échoue (faute de frappe : `mediagenda-bd-rw` pour `mediagenda-db-rw`, et de toute façon un `PreSync` qui exige la base interbloquerait un environnement neuf, comme l'explique le corrigé de M20-E11). La synchronisation s'arrête : le paramètre `MEDIAGENDA_DELAI_ARRET` n'est jamais appliqué. Correctif : revert ; si le contrôle est voulu, il devient un hook `Sync` en vague -1 avec un `activeDeadlineSeconds`, et le nom du Service se prend de la convention CNPG (`<cluster>-rw`).

**Variante 4 — quota.**

```
Message:            one or more objects failed to apply, reason: services "mediagenda-direct" is forbidden: exceeded quota: quota-mediagenda, requested: services.loadbalancers=1, used: services.loadbalancers=0, limited: services.loadbalancers=0
```

Le quota de l'espace (M14-E10) interdit les Services `LoadBalancer` : l'exposition passe par `gw-par1`, filtrée et chiffrée. Correctif : revert ; le besoin de Julien (tester depuis son poste) : `kubectl port-forward` avec ses droits de lecture, ou la route publiée de dev.

**Prévention — la porte `verifier-overlays`.** kubeconform valide un **schéma** ; il ne connaît ni l'immutabilité, ni les AppProjects, ni les quotas, ni les webhooks. Le script `corrige/fichiers/M20-E36/outils/verifier-overlay.sh` ajoute, sans aucun accès au cluster (la CI n'en a plus, M20-E30) : refus des ressources de portée cluster, des Services `LoadBalancer`/`NodePort`, des hooks sans `hook-delete-policy` ou sans `activeDeadlineSeconds`, et comparaison des sélecteurs de Deployment/StatefulSet avec `main` (rendu des deux révisions par `git worktree`) ; il liste aussi les objets qui disparaîtraient du rendu (E41). Job : `corrige/fichiers/M20-E36/ci/verification-overlays.yml` (image `alpine/k8s:1.36.5` par le cache Harbor, `GIT_DEPTH: "0"` pour comparer avec la branche cible). Démonstration sur une branche qui rejoue le commit de Lucas :

```
$ outils/verifier-overlay.sh overlays/dev origin/main
REFUS : overlays/dev : sélecteur modifié pour Deployment/mediagenda (champ immuable : l'API refusera la synchronisation)
```

Testé hors cluster avec Kustomize 5.8.1 sur les overlays du M17 complétés aux paliers 1 à 3 : aucun refus sur `main`. Sur l'`overlays/prod` du M17 **d'avant** M20-E07, il aurait refusé le `Namespace` (`ResourceQuota` et `LimitRange`, eux, sont refusés par l'AppProject) : ces trois objets relèvent de `plateforme/k8s` (`espaces/mediagenda-prod/`) depuis M20-E07, et `overlays/prod/espace.yaml` ne garde que la NetworkPolicy `refus-par-defaut`.

**Explications** — la chaîne de validation a trois étages : la CI (forme et règles écrites), Argo CD (AppProject, essai à blanc client), l'API (validation, admission). Chaque étage voit ce que le précédent ne voit pas. La comparaison côté serveur (ApplicationSet de M20-E12) fait passer les manifestes par l'admission **pendant le diff** pour les objets existants : un webhook de validation ou un champ immuable y apparaissent dès le diff, avant toute synchronisation (pas pour un objet nouveau, comme le Service de la variante 4).

**Pièges classiques**
- Désactiver l'auto-synchronisation « pour débloquer » : la panne reste, et la dérive suivante passera inaperçue.
- `Replace=true` pour contourner l'immutabilité : supprime et recrée le Deployment (coupure), et le nouveau sélecteur ne correspond plus aux ReplicaSets existants.
- Élargir l'AppProject pour « faire passer » la ClusterRole : l'équipe obtient le droit de créer n'importe quel objet de ce type dans le cluster.
- Relancer la synchronisation sans correctif : même révision, même refus.

**En production chez MédiSphère** : notification `on-sync-failed` vers l'équipe et `plateforme@` (M20-E19) ; règle « un objet de portée cluster demandé par une équipe = MR dans `plateforme/k8s` » écrite dans `normes-pipeline.md` ; `verifier-overlays` obligatoire (pipeline qui doit réussir pour fusionner).

---

### M20-E37 — Panne : Argo CD ne lit plus le dépôt

**Démarche de diagnostic**

*Symptômes* : condition `ComparisonError`, statut de synchronisation `Unknown` ; les pods tournent ; le dépôt se clone depuis `adm01`.

*Hypothèses* : identifiants (Secret, jeton de déploiement) ; confiance TLS ; adresse du dépôt ; réseau entre le repo-server et `git01`.

**Étape 1 — Périmètre et message.**

```
admin@adm01:~$ argocd app list -o json | jq -r '.[] | select(.status.sync.status == "Unknown") | .metadata.name'
mediagenda-dev
mediagenda-recette
mediagenda-prod
admin@adm01:~$ argocd app get mediagenda-dev -o json | jq -r '.status.conditions[].message'
Failed to load target state: failed to generate manifest for source 1 of 1: rpc error: code = Unknown desc = failed to list refs: authentication required: HTTP Basic: Access denied. …
```

Le périmètre est déjà un indice : un seul groupe GitLab touché (les trois Applications de `mediagenda`, pas `racine` ni `labo`) → les identifiants de ce groupe ; tout touché → CA, réseau, ou identifiants communs ; une seule Application → son adresse.

**Étape 2 — Reproduire depuis le repo-server.**

```
admin@adm01:~$ kubectl -n argocd exec deploy/argocd-repo-server -- git ls-remote https://git01.par1.medisphere.internal/mediagenda/deploiement.git
fatal: could not read Username for 'https://git01.par1.medisphere.internal': No such device or address
```

Sans identifiants : la résolution, la connexion et TLS passent (sinon le message serait `Could not resolve host`, `Connection timed out` ou `server certificate verification failed`), seule l'authentification manque. Le conteneur du repo-server fait confiance aux CA de son image **plus** celles d'`argocd-tls-certs-cm` pour les opérations d'Argo CD : un `git` lancé à la main dans le conteneur peut ne pas voir ces dernières ; pour le test TLS, `curl --cacert /app/config/tls/git01.par1.medisphere.internal https://git01.par1.medisphere.internal/` est plus fidèle (chemin de montage de la ConfigMap à vérifier sur ta version : `kubectl -n argocd get deploy argocd-repo-server -o yaml | grep -A3 tls-certs`).

**Variante 1 — identifiants restaurés d'une ancienne copie.**

```
admin@adm01:~$ kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type=repo-creds \
    -o custom-columns=NOM:.metadata.name,ANNOT:.metadata.annotations
NOM                ANNOT
repo-creds-mediagenda   map[medisphere.internal/restaure-depuis:sauvegarde-2026-09]
repo-creds-plateforme   <none>
…
admin@adm01:~$ kubectl -n argocd get secret repo-creds-mediagenda -o json --show-managed-fields | jq -r '.metadata.managedFields[] | [.manager, .operation, .time] | @tsv'
secrets-k8s   Apply    2026-10-30T08:14:51Z
kubectl-replace   Update   2026-11-04T13:02:17Z
```

Le Secret a été remplacé à la main (`kubectl-replace`, hors de `secrets-k8s.sh`) avec un ancien jeton de déploiement révoqué. Correctif : `plateforme/k8s/outils/secrets-k8s.sh appliquer argocd` (il réécrit les Secrets depuis le Vault `critique`), puis `argocd app get mediagenda-dev --hard-refresh`. Si le jeton du Vault était lui-même révoqué : nouveau jeton de déploiement (`read_repository`, expiration) dans GitLab, Vault mis à jour, `secrets-k8s.sh` ; jamais un jeton personnel.

**Variante 2 — racine MédiSphère retirée d'`argocd-tls-certs-cm`.**

Message : `x509: certificate signed by unknown authority`. `kubectl -n argocd get cm argocd-tls-certs-cm -o yaml` : l'entrée `git01.par1.medisphere.internal` a disparu (l'entrée `registry.par1.medisphere.internal` est encore là). `helmfile -e par1 -l composant=argocd diff --diff-args '--three-way-merge'` montre l'écart (sans `--three-way-merge`, helm-diff compare seulement les manifestes de la release et ne voit pas une modification faite à la main, M17-E14) : la release remettrait l'entrée. Correctif : `helmfile -e par1 -l composant=argocd sync` (une `apply` sans `--three-way-merge` conclurait « aucun changement » et ne ferait rien ; `sync` relance `helm upgrade`, dont l'application côté serveur remet l'entrée que la release possède), après le `diff`, qui ne doit montrer que cette entrée ; attendre la propagation du volume (une minute), `--hard-refresh`. Une entrée par **nom d'hôte** : une forge publiée sous un autre nom aurait besoin de la sienne.

**Variante 3 — adresse du dépôt modifiée.**

```
admin@adm01:~$ argocd app get labo -o json | jq -r '.status.conditions[].message'
application repo https://gitlab.par1.medisphere.internal/formation/gitops-labo.git is not permitted in project 'labo'
admin@adm01:~/src/gitops$ git log -1 -p -- applications/labo.yaml
    chore(labo): nouvelle adresse de la forge
-    repoURL: https://git01.par1.medisphere.internal/formation/gitops-labo.git
+    repoURL: https://gitlab.par1.medisphere.internal/formation/gitops-labo.git
```

L'AppProject `labo` refuse l'adresse avant même toute connexion (`sourceRepos`) ; s'il l'avait permise, le message aurait été `no such host` (le nom n'existe pas) puis, une fois le nom créé, une erreur d'authentification (les identifiants `repo-creds` sont choisis par **préfixe d'URL**). Correctif : revert dans `plateforme/gitops`. Un vrai changement d'adresse de la forge se prépare : nom publié, certificat, entrée de CA, `repo-creds` et `sourceRepos` aux deux adresses, bascule, retrait de l'ancienne.

**Variante 4 — politique réseau de refus.**

```
Message : … dial tcp 10.10.20.12:443: i/o timeout
admin@adm01:~$ hubble observe --namespace argocd --verdict DROPPED --last 5
… argocd/argocd-repo-server-… (ID:…) <> 10.10.20.12:443 (world) policy-verdict:none EGRESS DENIED (TCP Flags: SYN)
admin@adm01:~$ kubectl -n argocd get ciliumnetworkpolicies.cilium.io
NAME                        AGE
argocd-repo-server          21d
argocd-sortie-restreinte    18m
```

Une politique `egressDeny` (prioritaire sur toutes les autorisations) refuse `10.10.20.12:443` au repo-server. Elle n'est dans aucun dépôt (`git grep argocd-sortie-restreinte` dans `plateforme/k8s` ne trouve rien) : objet orphelin posé à la main. Correctif : la retirer (`kubectl -n argocd delete cnp argocd-sortie-restreinte`), après avoir noté son contenu et son auteur dans le journal ; l'intention (restreindre les sorties du repo-server) est déjà couverte par la politique d'E25, qui est dans le code.

**Vérification** : `argocd app list` sans `Unknown` ; `lab/bin/check 20 37`.

**Explications** — le repo-server est le seul composant qui parle aux dépôts. Il résout la révision d'une branche (`git ls-remote`, mise en cache quelques minutes), récupère le dépôt dans `/tmp/_argocd-repo/<uuid>`, génère les manifestes et les met en cache dans Redis par révision. Les identifiants viennent des Secrets `repository` (un dépôt) ou `repo-creds` (modèle par préfixe d'URL), la confiance TLS d'`argocd-tls-certs-cm` (par nom d'hôte), le réseau des politiques de l'espace `argocd` et de la bordure. Le cache explique les comportements trompeurs : une panne qui « met du temps à apparaître », une réparation qui « ne marche pas tout de suite ».

**Pièges classiques**
- Tester depuis `adm01` : autres identifiants, autre magasin de CA, autre chemin réseau. Le test qui compte part du repo-server.
- Passer le dépôt en `insecure: true` « pour voir » : désactive la vérification TLS, et reste.
- Coller un nouveau jeton à la main dans le Secret : le prochain `secrets-k8s.sh` remettra l'ancien (celui du Vault).
- Oublier le `--hard-refresh` et conclure que le correctif est inefficace.

**En production chez MédiSphère** : alerte sur `argocd_app_info{sync_status="Unknown"}` et sur les erreurs Git du repo-server (`argocd_git_lsremote_fail_total`, `argocd_git_fetch_fail_total`, M21) ; inventaire des jetons de déploiement avec leur date d'expiration (M19-E25) ; contrôle périodique « Secrets d'Argo CD égaux au Vault » par empreinte.

---

### M20-E38 — Panne : l'application est `Degraded` après synchronisation

**Démarche de diagnostic**

*Symptômes* : variantes 1 à 3, `Synced` mais `Progressing` puis `Degraded`, l'ancienne version répond ; variante 4, `Degraded` en dev **et** en prod, notifications en rafale, applications en parfait état.

**Étape 1 — Quelle ressource, quel message.**

```
admin@adm01:~$ argocd app get mediagenda-dev | awk 'NR==1 || /Progressing|Degraded/'
apps   Deployment   mediagenda-dev   mediagenda   Synced   Progressing   Waiting for rollout to finish: 1 old replicas are pending termination...
admin@adm01:~$ kubectl -n mediagenda-dev get pods -l app.kubernetes.io/name=mediagenda --sort-by=.metadata.creationTimestamp
NAME                          READY   STATUS             RESTARTS   AGE
mediagenda-6d9f7c5b8-x2v4q    1/1     Running            0          3d
mediagenda-7b64d9c4f-k8mzt    0/1     ImagePullBackOff   0          6m
```

Avec `maxUnavailable: 0`, l'ancien pod reste prêt et en service : livraison bloquée, pas coupure. Le Deployment passera `Degraded` à `progressDeadlineSeconds` (600 s).

**Variante 1 — digest introuvable.** `kubectl describe pod …` : `failed to resolve reference "registry.par1.medisphere.internal/medisphere/mediagenda-api@sha256:9c1d…": … not found`. Le commit de Lucas a changé le digest de `images:` de l'overlay de dev (« image reconstruite sur mon poste ») : un digest qui n'existe pas dans Harbor. Correctif : revert. Cette variante n'arrive que si la vérification de signatures du pipeline de MR (M19-E29) n'est pas bloquante : sur un lab conforme, le script d'injection la saute — c'est la preuve que la porte marche. Une image ne vient que de la CI (promotion par MR, M19-E17), jamais d'un poste.

**Variante 2 — sonde mal réglée.** `kubectl describe pod` : `Readiness probe failed: HTTP probe failed with statuscode: 404`. Le correctif de Lucas vise `/ready` ; MédiAgenda expose `/pret` (apps/README). Le pod tourne, n'est jamais prêt, ne reçoit pas de trafic, et le rollout ne progresse pas. Correctif : revert. « Aligner les sondes » est une décision de l'application (code et chart), pas un correctif d'overlay.

**Variante 3 — volume impossible à provisionner.** Pod neuf `Pending` : `0/6 nodes are available: pod has unbound immediate PersistentVolumeClaims` ; `kubectl describe pvc mediagenda-exports` : `storageclass.storage.k8s.io "ceph-rbd-ssd" not found`. Correctif : revert (ou `ceph-rbd`, si le besoin est confirmé, avec la protection d'E41). Le PVC `Pending` est élagué au revert (jamais lié, aucune donnée) — sauf si le component `protection-donnees` d'E41 est déjà en place : il porte alors `Prune=false`, l'Application reste `OutOfSync` (« ignored (no prune) ») et c'est à toi de le supprimer, après avoir vérifié qu'il est bien `Pending` et jamais lié (`kubectl -n mediagenda-dev get pvc mediagenda-exports -o jsonpath='{.status.phase} {.spec.volumeName}'`).

**Variante 4 — un contrôle de santé qui ment.**

```
admin@adm01:~$ argocd app get mediagenda-dev | grep Cluster
postgresql.cnpg.io  Cluster  mediagenda-dev  mediagenda-db  Synced  Degraded  La base n'est pas encore prête
admin@adm01:~$ kubectl -n mediagenda-dev get clusters.postgresql.cnpg.io mediagenda-db -o jsonpath='{.status.phase}{"\n"}'
Cluster in healthy state
admin@adm01:~$ kubectl -n argocd get cm argocd-cm -o json | jq -r '.data | keys[] | select(startswith("resource.customizations.health"))'
resource.customizations.health.postgresql.cnpg.io_Cluster
admin@adm01:~$ kubectl -n argocd get cm argocd-cm --show-managed-fields -o json \
>   | jq -r '.metadata.managedFields[] | select(.fieldsV1."f:data"."f:resource.customizations.health.postgresql.cnpg.io_Cluster") | "\(.manager) \(.operation) \(.time)"'
kubectl-patch Update 2026-…
admin@adm01:~/src/k8s$ grep -rn 'customizations.health' composants/argocd/      # rien : la release ne déclare pas cette clé
```

La base va bien pour son opérateur ; Argo CD la dit `Degraded` parce qu'un script Lua ajouté à la main dans `argocd-cm` (hors de la release) attend une phase `Healthy` que CNPG ne publie pas. Les scripts de `argocd-cm` remplacent le contrôle **intégré** d'Argo CD pour ce type (dossier `resource_customizations/postgresql.cnpg.io/Cluster/` du projet, qui connaît les phases de CNPG). Toutes les Applications qui portent une base passent `Degraded` — la prod comprise, d'où les notifications `on-health-degraded`. Correctif : **défaire le geste manuel**, exactement, et le tracer dans le journal (qui, quand : l'entrée `kubectl-patch` des `managedFields`). Une `helmfile apply` ne suffit **pas** : la clé n'a jamais appartenu à la release, et ni la fusion à trois voies de Helm ni le *server-side apply* de Helm 4 ne retirent un champ posé par un autre gestionnaire (`helmfile diff`, même avec `--three-way-merge`, ne la montre d'ailleurs pas). On retire donc cette seule clé :

```
admin@adm01:~$ kubectl -n argocd patch configmap argocd-cm --type json \
>   -p '[{"op":"remove","path":"/data/resource.customizations.health.postgresql.cnpg.io_Cluster"}]'
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff --diff-args '--three-way-merge'   # vide : argocd-cm = la release
admin@adm01:~$ argocd app get mediagenda-dev --refresh
```

Si un contrôle de santé personnalisé était réellement voulu, il arriverait par la release (`configs.cm` dans `composants/argocd/`, MR avec la sortie de `tester-sante.sh`), jamais par `argocd-cm` directement.

Éprouver un contrôle avant de le livrer (`corrige/fichiers/M20-E38/outils/tester-sante.sh`) :

```
admin@adm01:~/src/k8s$ outils/tester-sante.sh composants/argocd/values-sante.yaml postgresql.cnpg.io Cluster mediagenda-db mediagenda-dev
Objet : Cluster/mediagenda-db (mediagenda-dev) — phase rapportée par l opérateur : Cluster in healthy state
--- avec le contrôle proposé
STATUS: Degraded
MESSAGE: La base n'est pas encore prête
--- avec le contrôle intégré d'Argo CD (sans personnalisation)
STATUS: Healthy
MESSAGE:
```

(Sortie obtenue telle quelle avec `argocd admin settings resource-overrides health` 3.5.5 sur un objet CNPG d'exemple.)

**Vérification** : `argocd app wait mediagenda-dev --health --timeout 600` ; plus de notification erronée ; `lab/bin/check 20 38`.

**Explications** — synchronisation et santé sont deux axes indépendants : `Synced` compare le cluster à Git, `Healthy` évalue chaque ressource (règles intégrées pour les types de Kubernetes, scripts Lua intégrés ou personnalisés pour les CRD) puis agrège le pire état. Un Deployment est `Progressing` tant que le rollout n'est pas terminé et que `progressDeadlineSeconds` n'est pas dépassé. Un contrôle de santé personnalisé est du code qui décide de tes alertes de production : il se relit et se teste comme du code.

**Pièges classiques**
- Supprimer le pod en `ImagePullBackOff` : le ReplicaSet le recrée à l'identique.
- Allonger `progressDeadlineSeconds` ou supprimer la sonde « pour que ça passe ».
- `kubectl edit configmap argocd-cm` pour « arranger » le Lua, ou retirer la clé sans rien noter : la prochaine personne ne saura jamais ce qui s'est passé. Le retrait est un geste ciblé (une clé, tracée), pas une édition libre.
- Croire qu'une `helmfile apply` nettoie tout ajout manuel : elle remet les champs **de la release**, pas ceux posés à côté par un autre gestionnaire.
- Conclure que « la santé d'Argo CD ment souvent » et ignorer les alertes : un contrôle faux se corrige.

**En production chez MédiSphère** : toute personnalisation de santé dans `composants/argocd/` avec la sortie de `tester-sante.sh` dans la MR ; alerte `argocd_app_info{health_status="Degraded"}` plus de 15 min (M21) ; déclencheur `on-health-degraded` limité à la prod pour l'astreinte, et à l'équipe pour dev et recette.

---

### M20-E39 — Panne : la dérive revient sans cesse

**Démarche de diagnostic**

*Symptômes* : synchronisations automatiques sans commit, à intervalles croissants ; selon la variante, pods de dev recréés (v1, v3) ou application `labo` qui oscille (v2).

**Étape 1 — Mesurer la bataille.**

```
admin@adm01:~$ argocd app history mediagenda-dev | tail -n 6
ID  DATE                           REVISION
41  2026-11-04 14:02:11 +0000 UTC  main (5c1d2e7)
42  2026-11-04 14:02:15 +0000 UTC  main (5c1d2e7)
43  2026-11-04 14:02:24 +0000 UTC  main (5c1d2e7)
44  2026-11-04 14:02:45 +0000 UTC  main (5c1d2e7)
45  2026-11-04 14:03:44 +0000 UTC  main (5c1d2e7)
46  2026-11-04 14:06:31 +0000 UTC  main (5c1d2e7)
```

Même révision, synchronisations de plus en plus espacées : c'est l'**attente exponentielle** de l'auto-réparation (`controller.self.heal.backoff.timeout.seconds: 2`, facteur 3, plafond 300 s : 2, 6, 18, 54, 162, puis 300 s). Argo CD répare ; quelqu'un défait. `outils/qui-ecrit.sh` (fichier `corrige/fichiers/M20-E39/outils/qui-ecrit.sh`) dit qui.

**Variante 1 — HPA contre `replicas` de Git.**

```
admin@adm01:~$ outils/qui-ecrit.sh mediagenda-dev deployment mediagenda
== Gestionnaires de champs de deployment/mediagenda (mediagenda-dev)
argocd-controller        Apply    -       2026-11-04T14:06:31Z  spec metadata
kube-controller-manager  Update   scale   2026-11-04T14:06:46Z  spec
kube-controller-manager  Update   status  2026-11-04T14:06:50Z  status
…
== HPA de l'espace
mediagenda   mediagenda   2   3
```

Le commit de Lucas ajoute un HPA (min 2) ; l'overlay de dev fixe `replicas: 1` et l'Application de dev n'ignore pas ce champ (seules recette et prod l'ignorent, pour le Rollout). Le HPA écrit `spec.replicas` par la sous-ressource `scale`, Argo CD le remet à 1 en appliquant, le HPA le remonte… Chaque cycle crée et détruit un pod. Correctif — **un seul propriétaire** : soit pas de HPA en dev (décision de Julien ici : revert), soit le HPA est le propriétaire et Git cesse de décrire les réplicas (retirer `replicas:` du rendu de dev **ou** `ignoreDifferences` sur `/spec/replicas` du Deployment **et** `RespectIgnoreDifferences=true`, sans quoi la synchronisation remettrait quand même la valeur de Git).

**Variante 2 — deux Applications sur les mêmes objets.**

```
admin@adm01:~$ argocd app get labo -o json | jq -r '.status.conditions[] | [.type, .message] | @tsv'
SharedResourceWarning   Deployment/labo is part of applications argocd/labo and labo-essai
admin@adm01:~$ kubectl -n wb-essais get deploy labo -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}{"\n"}'
labo-essai:apps/Deployment:wb-essais/labo
admin@adm01:~/src/gitops$ git log -1 --stat
    feat(labo): copie de labo pour mes essais
 applications/labo.yaml | 23 +++++++++++++++++++++++
```

Lucas a ajouté, à la fin de `applications/labo.yaml`, une seconde Application `labo-essai` qui déploie la même source dans le même espace. Chaque synchronisation réécrit l'annotation de suivi au nom de son Application ; l'autre voit l'objet comme « pas à elle », repasse `OutOfSync`, resynchronise. Correctif : revert (l'Application `applications` élague `labo-essai`). **Avant** de supprimer une Application à la main, regarder ses finaliseurs : `labo` porte `resources-finalizer.argocd.argoproj.io` (sa suppression supprimerait le déploiement) ; `labo-essai` n'en a pas (`kubectl -n argocd get application labo-essai -o jsonpath='{.metadata.finalizers}'`). Prévention : `FailOnSharedResource=true` dans les options de synchronisation (ApplicationSet `mediagenda` : `corrige/fichiers/M20-E41/gitops/applications/mediagenda.yaml`) : la synchronisation échoue au lieu de se battre.

**Variante 3 — tâche planifiée qui « corrige ».**

```
== Gestionnaires de champs de deployment/mediagenda (mediagenda-dev)
argocd-controller   Apply    -   2026-11-04T15:21:05Z  spec metadata
correcteur-lucas    Update   -   2026-11-04T15:22:01Z  spec
== Comptes de service d'autres espaces avec des droits dans mediagenda-dev
correcteur-memoire  → wb-pannes/correcteur-memoire  (Role/correcteur-memoire)
admin@adm01:~$ kubectl -n wb-pannes get cronjob correcteur-memoire -o jsonpath='{.spec.schedule}{"\n"}'
*/1 * * * *
```

Une CronJob de l'espace `wb-pannes`, avec un Role dans `mediagenda-dev`, remonte chaque minute la limite mémoire de l'API par un `PATCH` (manager `correcteur-lucas`, choisi par `?fieldManager=`). Argo CD remet la valeur de Git, la tâche la remet : un déploiement progressif par minute. L'AppProject `mediagenda` signalait déjà le Role et le RoleBinding comme **orphelins** (M20-E07). Correctif : supprimer la CronJob, son compte de service, le Role et le RoleBinding (en notant leur contenu dans le journal) ; si le besoin est réel (OOMKilled en dev ?), le vérifier (`kubectl get events`, `lastState.terminated.reason`) et porter la nouvelle limite **dans Git**, par MR.

**Vérification** : quelques minutes sans synchronisation automatique ni nouvelle génération (`kubectl get deploy mediagenda -o jsonpath='{.metadata.generation}'` stable) ; `lab/bin/check 20 39` observe 60 s.

**Explications** — l'auto-réparation part du principe qu'une dérive est **accidentelle** : on remet Git, elle ne revient pas. Une dérive qui revient est **systématique** : un autre acteur veut une autre valeur. Le seul correctif est de supprimer l'ambiguïté de propriété : pour chaque champ, un seul écrivain. Les `managedFields` sont la mémoire de l'API sur la question « qui a écrit ce champ, par quel chemin, quand ».

**Pièges classiques**
- Désactiver `selfHeal` : la bataille cesse, la dérive reste et devient invisible.
- `ignoreDifferences` sans `RespectIgnoreDifferences=true` : le diff se tait, mais chaque synchronisation (déclenchée par un autre changement) remet quand même la valeur de Git.
- Supprimer l'Application « fautive » sans regarder ses finaliseurs.
- Supprimer la CronJob mais laisser ses droits : le prochain script les réutilisera.

**En production chez MédiSphère** : alerte sur le taux de synchronisations automatiques par Application (`increase(argocd_app_sync_total[1h]) > 6` sans commit) ; plus aucun gestionnaire de champs étranger sur les objets applicatifs (M20-E30) ; orphelins signalés et revus chaque semaine.

---

### M20-E40 — Panne : le canary ne progresse plus

**Démarche de diagnostic**

*Symptômes* : selon la variante, canary interrompu et retour au stable, contrôleur en redémarrage, synchronisations en boucle pendant le canary, version livrée qui ne part jamais. Le commit déclencheur de Lucas (cache des créneaux, `parametres.env` de recette) est anodin : il crée une nouvelle révision, c'est tout.

**Étape 1 — Photographier** (`corrige/fichiers/M20-E40/outils/canary-etat.sh`) :

```
admin@adm01:~$ kubectl argo rollouts get rollout mediagenda -n mediagenda-recette
Name:            mediagenda
Namespace:       mediagenda-recette
Status:          ✖ Degraded
Message:         RolloutAborted: Rollout aborted update to revision 7: Metric "pret" assessed Error due to consecutiveErrors (3) > consecutiveErrorLimit (2): "Error Message: received non 2xx response code: 404"
Strategy:        Canary
  Step:          1/7
  SetWeight:     0
  ActualWeight:  0
…
```

**Variante 1 — analyse qui vise un chemin inexistant.** `kubectl get analysisrun -n mediagenda-recette … -o yaml` : mesures en `Error`, `received non 2xx response code: 404`, URL `…/prets`. Le commit de Lucas ajoute dans `overlays/recette` un correctif de l'AnalysisTemplate `pret-mediagenda` (« chemin de la future version »). Une **erreur** de mesure (code HTTP, délai) n'est pas un **échec** (mesure mauvaise) ; au-delà de `consecutiveErrorLimit` (2) erreurs consécutives, l'analyse passe en `Error` et le Rollout est interrompu : poids à 0, pods canary réduits, retour au stable. Le système a **bien** fonctionné : une version qu'on ne sait pas valider ne passe pas. Correctif : revert du correctif de l'analyse (en gardant, si Julien le veut, le changement de cache dans une MR séparée) ; le Rollout repart sur la nouvelle révision, canary complet, analyses `Successful`. Ne jamais `kubectl argo rollouts promote --full` un canary dont l'analyse échoue.

**Variante 2 — greffon introuvable, contrôleur arrêté.**

```
admin@adm01:~$ kubectl -n argo-rollouts get pods -l app.kubernetes.io/name=argo-rollouts
NAME                             READY   STATUS             RESTARTS      AGE
argo-rollouts-7c9d5b6f4b-2kz8q   0/1     CrashLoopBackOff   5 (40s ago)   6m
argo-rollouts-7c9d5b6f4b-9wq4n   0/1     CrashLoopBackOff   5 (35s ago)   6m
admin@adm01:~$ kubectl -n argo-rollouts logs argo-rollouts-7c9d5b6f4b-2kz8q --previous | tail -n 2
… level=fatal msg="Failed to download plugins: failed to copy plugin from file:///greffons/rollouts-plugin-trafficrouter-gatewayapi-0.17.0 …: no such file or directory"
admin@adm01:~$ kubectl -n argo-rollouts get cm argo-rollouts-config -o jsonpath='{.data.trafficRouterPlugins}'
- name: argoproj-labs/gatewayAPI
  location: file:///greffons/rollouts-plugin-trafficrouter-gatewayapi-0.17.0
```

(Libellé exact du message à relever sur ton lab.) Le contrôleur charge ses greffons **au démarrage** ; le commit de Lucas a renommé l'emplacement dans les valeurs (`valeurs/argo-rollouts/values.yaml` de `plateforme/gitops`) sans changer la copie faite par le conteneur d'initialisation (M20-E15). Tant que les pods tournaient, rien ne se voyait ; au premier redémarrage (maintenance de nœud), plus aucun contrôleur, plus aucun Rollout n'avance — y compris en prod, qui reste figée sur sa version stable (rien n'est cassé côté trafic, rien ne se livre). Correctif : revert ; la nouvelle configuration est appliquée par Argo CD, les pods redémarrent (le `CrashLoopBackOff` les relance avec une attente croissante : `kubectl -n argo-rollouts rollout restart deploy/argo-rollouts` accélère). Prévention : un changement de la configuration des greffons se teste en recette en **redémarrant** le contrôleur dans la même MR (annotation de redémarrage dans les valeurs), pas au hasard d'une maintenance.

**Variante 3 — Argo CD et le greffon se disputent les poids.**

```
admin@adm01:~$ argocd app history mediagenda-recette | tail -n 4     # synchronisations automatiques toutes les quelques secondes pendant le canary
admin@adm01:~$ argocd app diff mediagenda-recette --exit-code=false
===== gateway.networking.k8s.io/HTTPRoute mediagenda-recette/mediagenda ======
<         weight: 90
>         weight: 100
<         weight: 10
>         weight: 0
admin@adm01:~$ argocd app get mediagenda-recette -o json | jq '.spec.ignoreDifferences'
[ { "group": "apps", "kind": "Deployment", "name": "mediagenda", "jsonPointers": ["/spec/replicas"] } ]
```

Le commit de Lucas a retiré du `templatePatch` de l'ApplicationSet l'entrée qui ignorait les poids de la HTTPRoute (« Argo CD doit tout voir »). Pendant le canary, le greffon écrit 90/10 ; Argo CD voit une dérive et remet les poids de Git ; le greffon les réécrit à sa prochaine réconciliation. Le canary « avance » sur le papier (étapes et pauses), le trafic réel oscille entre 0 et 10 %, et l'analyse de fond mesure à peine la nouvelle version. Correctif : revert dans `plateforme/gitops`. C'est l'un des rares cas où ignorer une différence est **juste** : le champ appartient à un autre contrôleur, par conception, et `RespectIgnoreDifferences=true` (déjà là) empêche la synchronisation de le remettre.

**Variante 4 — pause manuelle.** `kubectl argo rollouts get rollout …` : `Status: ॥ Paused`, `Message: manually paused` ; aucune condition de pause d'étape : la pause vient de `spec.paused: true`. `managedFields` : manager `kubectl-argo-rollouts`, quelques secondes avant le commit de livraison. Argo CD ne voit rien (`spec.paused` n'est pas dans Git, la différence est un champ en plus). Correctif : `kubectl argo rollouts resume mediagenda -n mediagenda-recette`, puis comprendre pourquoi quelqu'un a mis en pause (une raison valable ? alors elle se documente dans le ticket, et la reprise attend).

**Vérification** : un canary complet en recette (toutes les étapes, `fumee` et `pret` `Successful`, poids revenus à 100 % sur le stable, Rollout `Healthy`) ; `lab/bin/check 20 40`. Section de RB-200 : `corrige/fichiers/M20-E40/docs/RB-200-section-canary.md`.

**Explications** — un canary par la Gateway API met trois acteurs sur les mêmes objets : Argo CD (le Rollout, les Services, la HTTPRoute tels que Git les décrit), le contrôleur d'Argo Rollouts (ReplicaSets, sélecteurs des Services, analyses), le greffon (poids de la HTTPRoute). Chacun doit savoir ce qui ne lui appartient pas : `ignoreDifferences` + `RespectIgnoreDifferences` pour Argo CD, `workloadRef` et réduction progressive pour le Deployment, configuration du greffon chargée au démarrage.

**Pièges classiques**
- `promote --full` sur un canary interrompu : livre sans validation.
- Relancer le contrôleur sans lire `--previous` : la cause est dans les journaux du conteneur précédent.
- Croire le statut des étapes plutôt que les poids réels de la HTTPRoute.
- Reprendre un Rollout mis en pause par quelqu'un d'autre sans lui demander pourquoi.

**En production chez MédiSphère** : alerte sur les Rollouts interrompus et sur un contrôleur d'Argo Rollouts sans réplica prêt (M21) ; analyses par Prometheus en plus de `web` (M21) ; toute modification des AnalysisTemplates dans une MR séparée, relue par l'équipe et la plateforme.

---

### M20-E41 — Panne : une synchronisation a supprimé des ressources

**Démarche de diagnostic**

*Symptômes* : 5xx sur `https://mediagenda-dev.apps.par1.medisphere.internal/pret` ; des objets manquent ; une synchronisation automatique récente.

**Étape 1 — Ce qui a été supprimé, par quelle opération.**

```
admin@adm01:~$ argocd app get mediagenda-dev --show-operation | grep -i pruned
apps                StatefulSet          mediagenda-dev  valkey                          Pruned   pruned
                    Service              mediagenda-dev  valkey                          Pruned   pruned
networking.k8s.io   NetworkPolicy        mediagenda-dev  valkey                          Pruned   pruned
networking.k8s.io   NetworkPolicy        mediagenda-dev  mediagenda-db                   Pruned   pruned
cilium.io           CiliumNetworkPolicy  mediagenda-dev  mediagenda-db-api-kubernetes    Pruned   pruned
postgresql.cnpg.io  Cluster              mediagenda-dev  mediagenda-db                   OutOfSync  ignored (no prune)
```

**Étape 2 — Le commit et le rendu.**

```
admin@adm01:~/src/mediagenda-deploiement$ git show --stat HEAD~1
    refactor(dev): regrouper les composants de dev dans overlays/dev/composants
 overlays/dev/composants/kustomization.yaml | 4 ++++
 overlays/dev/kustomization.yaml            | 1 -
admin@adm01:~/src/mediagenda-deploiement$ git worktree add -q --detach /tmp/avant HEAD~2
admin@adm01:~/src/mediagenda-deploiement$ diff <(kubectl kustomize /tmp/avant/overlays/dev | yq -N '.kind+"/"+.metadata.name' | sort) \
                                               <(kubectl kustomize overlays/dev | yq -N '.kind+"/"+.metadata.name' | sort)
3d2
< CiliumNetworkPolicy/mediagenda-db-api-kubernetes
…
admin@adm01:~/src/mediagenda-deploiement$ git worktree remove /tmp/avant
```

(Plus simple : `outils/verifier-overlay.sh overlays/dev <révision-d'avant>` affiche « Objets qui DISPARAISSENT du rendu ».) Les **fichiers** ont à peine bougé (une ligne retirée, un fichier ajouté) ; les **objets** ont bougé beaucoup : un component non référencé n'apporte plus rien.

**Variante 1 — composants regroupés mais non référencés.** Le nouveau `overlays/dev/composants/kustomization.yaml` (un Component qui inclut `dependances`) n'est référencé par personne ; `dependances` a disparu de `components:`. Tout ce qu'il apportait disparaît du rendu : Valkey (StatefulSet en `emptyDir`, Service), politiques réseau. Argo CD élague ; la base, `Prune=false`, reste (« ignored (no prune) ») — sans elle, ce serait une perte de données. L'API ne joint plus Valkey : `/pret` en 503.

**Variante 2 — Service renommé.** Un correctif `allowNameChange` renomme le Service `mediagenda` en `mediagenda-api`. Kustomize ne met pas à jour la référence de la HTTPRoute (il ne connaît pas `backendRefs` de la Gateway API) ; Argo CD élague l'ancien Service ; la HTTPRoute vise un Service absent (`ResolvedRefs: False`, `BackendNotFound`) : 500 par la Gateway.

**Variante 3 — politiques réseau « déplacées ».** Des correctifs `$patch: delete` retirent les NetworkPolicy et CiliumNetworkPolicy de dev (« déplacées vers plateforme/k8s ») avant que la plateforme ne les ait appliquées de son côté. Élaguées : avec le refus par défaut de l'espace, l'API ne joint plus la base ni Valkey. Deux outils, deux rythmes : retirer d'un côté avant d'avoir ajouté de l'autre.

**Correctif (toutes variantes)** : revert par MR. Argo CD recrée les objets à l'identique (même nom, même contenu : Valkey de dev est un cache sans persistance, il repart vide sans perte). Vérifier `/pret` (200) et la liste des objets.

**Prévention**
- `components/protection-donnees` (`corrige/fichiers/M20-E41/deploiement/components/protection-donnees/kustomization.yaml`) : pose `Prune=false,Delete=false` sur **toute** base CNPG et **tout** PVC rendus, après `dependances` dans dev et prod, en tête en recette. La protection ne dépend plus d'une annotation oubliée dans un nouveau fichier (le PVC d'E35 et d'E38 en aurait bénéficié). Rendu vérifié avec Kustomize 5.8.1.
- `PruneLast=true` dans l'ApplicationSet (`corrige/fichiers/M20-E41/gitops/applications/mediagenda.yaml`, avec `FailOnSharedResource=true` d'E39) : l'élagage passe après l'application et la santé du reste. Il ne sauve pas la variante 1 (rien ne remplace Valkey), il sauve la variante 2 dans sa forme correcte (un Service renommé **et** la route mise à jour : l'ancien Service n'est supprimé qu'une fois la route sur le nouveau).
- `Prune=confirm` pour ce dont la suppression doit rester une décision humaine sans être interdite : la synchronisation s'arrête (« waiting for pruning confirmation of … ») jusqu'à confirmation dans l'interface ou par l'annotation `argocd.argoproj.io/deletion-approved` sur l'Application.
- `verifier-overlay.sh` (E36) : la MR affiche les objets qui disparaissent et refuse ceux qui portent des données.
- Production sans synchronisation automatique : avant de synchroniser la prod, `argocd app diff mediagenda-prod` et `argocd app sync mediagenda-prod --dry-run --prune` montrent l'élagage prévu.

**Explications** — avec `prune: true`, Git est la **liste exhaustive** de ce qui doit exister pour l'Application. Argo CD ne sait pas distinguer « Lucas a voulu supprimer » de « Lucas a oublié une ligne » : c'est le rôle de la revue (le diff du **rendu**, pas seulement celui des fichiers) et des protections déclaratives.

**Pièges classiques**
- `kubectl apply` des objets supprimés : la synchronisation suivante les ré-élague.
- Relire le diff des fichiers d'une MR de Kustomize sans regarder le rendu.
- Désactiver `prune` en dev : les objets retirés de Git s'accumulent (orphelins, coûts, surprises au retour du `prune`).
- Supprimer l'Application pour « repartir propre » : finaliseur, suppression en cascade.

**En production chez MédiSphère** : production en synchronisation manuelle avec revue du diff (ADR-0200) ; `Delete=false` sur tout ce qui porte des données ; sauvegardes CNPG et Velero vérifiées (M16) ; alerte sur toute opération qui élague plus de N objets (`argocd_app_sync_total` ne le dit pas : notification `on-sync-succeeded` filtrée sur `operationState.syncResult.resources[].message == "pruned"`, à écrire au M21).

---

### M20-E42 — Panne : le cluster de l'agence est `Unknown`

**Démarche de diagnostic**

*Symptômes* : `argocd cluster list` : `lyo-k3s01` en échec ; `labo-lyo-k3s01` `Unknown`.

**Étape 1 — Le message côté Argo CD.**

```
admin@adm01:~$ argocd cluster list
SERVER                                           NAME        VERSION  STATUS      MESSAGE
https://kubernetes.default.svc                   in-cluster  1.36     Successful
https://lyo-k3s01.par1.medisphere.internal:6443  lyo-k3s01   1.36     Failed      … the server has asked for the client to provide credentials
```

**Étape 2 — Tester l'étage.**

```
admin@k8s-w01:~$ curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 \
    --cacert /tmp/k3s-server-ca.crt https://lyo-k3s01.par1.medisphere.internal:6443/version
401
admin@lyo-k3s01:~$ sudo k3s kubectl auth can-i list deployments.apps -n agence --as=system:serviceaccount:agence:argocd-gestion
yes
admin@lyo-k3s01:~$ sudo nft list ruleset | grep -n 6443
```

Depuis un travailleur (le trafic des pods d'Argo CD sort avec l'adresse du nœud) : un code HTTP, même `401` (pas d'accès anonyme à l'API de k3s), prouve que le réseau et TLS passent ; un délai dépassé désigne le réseau ; une erreur de certificat, l'autorité. Copie d'abord la CA de k3s (`/var/lib/rancher/k3s/server/tls/server-ca.crt`, publique) dans `/tmp/k3s-server-ca.crt` du nœud, et compare-la à la `caData` du Secret de cluster.

**Variante 1 — jeton périmé.** Message `Unauthorized` / « provide credentials ». Le Secret `cluster-lyo-k3s01` porte l'annotation `medisphere.internal/restaure-depuis` et un manager `kubectl-replace` récent ; son jeton (longueur, début) ne correspond pas à celui du Secret `argocd-gestion-jeton` de `lyo-k3s01`. Correctif : `secrets-k8s.sh appliquer argocd` (fonction `secret_cluster_lyo_k3s01`, M20-E26), depuis le Vault.

**Variante 2 — pare-feu local de l'agence.** Message `dial tcp 10.10.99.61:6443: i/o timeout`. Le test depuis un pod échoue aussi, depuis `adm01` (MGMT) il passe : le filtrage vise la source. `nft list ruleset` sur `lyo-k3s01` : une table `inet filtrage_agence` refuse 6443 depuis 10.10.40.0/24 et 10.240.0.0/16 (« API réservée à l'agence »). Correctif : `nft delete table inet filtrage_agence`, puis porter l'intention légitime (restreindre l'API de l'agence) dans le rôle Ansible de la machine, **avec** l'exception pour `K8S_TRAV`, et la matrice des flux. Une règle posée à la main sur une VM disparaît au redémarrage… ou survit si quelqu'un l'a rendue persistante : dans les deux cas, elle n'est dans aucun code.

**Variante 3 — autorité remplacée.** Message `x509: certificate signed by unknown authority`. La `caData` du Secret est la racine MédiSphère ; l'API de k3s présente un certificat signé par **sa** CA (`/var/lib/rancher/k3s/server/tls/server-ca.crt`). Correctif : `secrets-k8s.sh appliquer argocd` (le Vault contient `lyo_k3s01_ca`). Jamais `insecure: true`.

**Variante 4 — droits retirés.** Message `failed to sync cluster …: forbidden: User "system:serviceaccount:agence:argocd-gestion" cannot list resource "deployments" …`. `k3s kubectl get rolebinding -n agence` : la liaison `argocd-gestion` a disparu (« ménage » de l'agence). Correctif : par le code, mais en sachant comment k3s applique ses manifestes. Rejouer le playbook `m20-lyo.yml` **ne suffit pas** : le fichier `medisphere-argocd-gestion.yaml` n'a pas changé, et le contrôleur *deploy* de k3s ne réapplique un manifeste de `/var/lib/rancher/k3s/server/manifests/` qu'**au démarrage** de k3s ou quand son contenu change (empreinte gardée dans l'objet `Addon` `kube-system/medisphere-argocd-gestion` ; code de `pkg/deploy` de k3s). Deux gestes, tous deux à partir du fichier déposé par le code : `sudo k3s kubectl apply -f /var/lib/rancher/k3s/server/manifests/medisphere-argocd-gestion.yaml` sur `lyo-k3s01`, ou `sudo systemctl restart k3s` (réapplication forcée de tout le dossier ; l'API de l'agence est indisponible quelques secondes, les pods continuent de tourner). Puis vérifier que `argocd-gestion` n'a **que** le Role de l'espace `agence` : `k3s kubectl auth can-i '*' '*' --all-namespaces --as=…` → `no`.

**Vérification** : `argocd cluster list` → `Successful` ; `labo-lyo-k3s01` `Synced`/`Healthy` ; `lab/bin/check 20 42`.

**Explications** — Argo CD gère un cluster distant avec quatre ingrédients : une adresse joignable, une autorité qui valide le certificat de l'API, un jeton accepté, des droits suffisants pour **surveiller** (cache d'état) et **appliquer**. Avec `namespaces: agence` et `clusterResources: false`, il ne surveille que l'espace `agence` : moins de droits, moins de mémoire, mais un nouveau type d'objet dans l'application de l'agence demande d'étendre le Role.

**Pièges classiques**
- `cluster-admin` « pour voir si ça passe » : ça passe, et ça reste.
- Retirer la règle nftables sans comprendre ce que l'agence voulait protéger.
- Régénérer un jeton côté k3s sans mettre à jour le Vault : la panne revient au prochain `secrets-k8s.sh`.

**En production chez MédiSphère** : alerte sur `argocd_cluster_connection_status == 0` (M21) ; jetons des clusters distants dans l'inventaire des secrets avec rotation (M25 : OpenBao) ; règles de filtrage de l'agence dans le rôle Ansible, avec la plateforme en exception écrite.

---

### M20-E43 — Astreinte : la mise en production tourne mal

**Démarche**

Le script tire trois pannes (au plus une sur `mediagenda-dev`) et les injecte dans l'ordre E42, E40, la panne de dev, E37 en dernier. Il n'y a pas de « bonne réponse » unique : le corrigé est la méthode, et le post-mortem d'exemple `corrige/fichiers/M20-E43/2026-11-05-INC-4743-mise-en-production-bloquee.md` (trio E37 v1 + E40 v1 + E39 v1).

1. **Premier message (≤ 10 min)** : « Je prends INC-4743. Trois symptômes : … La mise en production reste suspendue ; prochain point à 18 h 15. »
2. **Trier** : ce qui empêche de **voir** ou de **corriger** passe d'abord. Un dépôt illisible pour Argo CD (E37) d'abord : sans lui, aucun correctif par Git n'arrive, et un bon revert « ne marche pas ». Puis ce qui bloque la mise en production (canary de recette, E40), puis dev.
3. **Une panne à la fois**, chacune avec son journal, son correctif par MR, son check (`lab/bin/check 20 3X`). Ne pas mélanger deux correctifs dans une MR : le post-mortem doit pouvoir dire lequel a réparé quoi.
4. **Retrouver les commits** : `git log --author='Lucas Martin' --since='3 hours ago' --oneline` dans `mediagenda/deploiement` et `plateforme/gitops` ; les objets modifiés hors Git par leurs `managedFields` et annotations.
5. **Ne pas synchroniser la prod** : la synchronisation de prod est manuelle, elle attend le feu vert de Nadia après le dernier check ; si le gel (vendredi 16 h, M20-E29) arrive avant, la mise en production est reportée, pas forcée par `manualSync`.
6. **Clore** : `lab/bin/break 20 43 --annuler` (rien à défaire si tout est réparé, mais les marqueurs sont retirés), `lab/bin/check 20 43`.

**Post-mortem** — attendu : chronologie horodatée (détection, chaque hypothèse, chaque MR), causes racines (une par panne, côté système : « un Secret géré hors Git a été réécrit à la main », pas « Lucas s'est trompé »), détection (ce qui aurait dû alerter : `Unknown` n'a aucune notification, un Rollout interrompu non plus), ce qui a bien marché, actions (responsable, échéance), commandes citées, empreintes des commits fautifs et correctifs, aucun jeton.

**Pièges classiques** : corriger E40 avant E37 (le revert n'arrive pas, on doute du bon diagnostic) ; un « petit » `argocd app sync mediagenda-prod` pour « vérifier que la prod va bien » ; désactiver l'auto-synchronisation de dev pour « avoir la paix » pendant l'incident et l'oublier.

**En production chez MédiSphère** : astreinte avec rôles (incident manager, communication, technique) dès deux personnes ; modèle de message ; post-mortem relu en revue d'équipe sous 5 jours ouvrés.

---

### M20-E44 — Sous le capot : du commit à l'objet

**Solution**

Livrable d'exemple : `corrige/fichiers/M20-E44/docs/sous-le-capot.md` ; outil : `corrige/fichiers/M20-E44/outils/chronometrer-livraison.sh`.

1. **Mesure préparée.** Le passage en `debug` se fait **par la release**, avec deux `--set` passés à `helmfile apply` (`configs.params."controller.log.level"` et `configs.params."reposerver.log.level"`, qui valent sinon `info`, hérité de `global.logging.level`) : le chart réécrit `argocd-cmd-params-cm` et, par ses annotations `checksum/cmd-params`, redémarre lui-même le contrôleur et le repo-server. Ce n'est pas un `kubectl patch` : la release est en *server-side apply* (Helm 4, M20-E02) ; un `kubectl patch` sur des champs qu'elle possède les ferait passer au gestionnaire `kubectl-patch` : sans `--three-way-merge`, `helmfile diff` ne verrait pas l'écart (M17-E14) et `helmfile apply` ne ferait rien ; une `helm upgrade` forcée pourrait buter sur un conflit de *server-side apply* (comportement exact à vérifier sur ton lab : `kubectl -n argocd get cm argocd-cmd-params-cm --show-managed-fields`). La surcharge par `--set` laisse un état temporaire **hors de Git** (le dépôt dit `info`) : l'alternative tracée est une MR qui change `global.logging.level`, puis une seconde qui le remet ; les deux se défendent pour une mesure d'une heure.

2. **Chronologie.** Lignes réelles d'Argo CD 3.5 (code source de la 3.5.5) :
   - serveur : `Received push event repo: https://git01.par1.medisphere.internal/mediagenda/deploiement, revision: main, touchedHead: true` ;
   - contrôleur (champ `application` = nom de l'Application) : `Refreshing app status (…), level (N)`, `Initialized new operation: …`, `updated 'argocd/mediagenda-dev' operation (phase: Succeeded)`, `Reconciliation completed` avec `time_ms`, `patch_ms`, `setop_ms`, `comparison-level` et les durées détaillées par étape ;
   - si une opération est déjà en cours : `Skipping auto-sync: another operation is in progress` (E35 v1) ; après un échec : `Skipping auto-sync: failed previous sync attempt to … and will not retry for …` (E36) ; pendant l'attente de l'auto-réparation : `Skipping auto-sync: already attempted sync to … with timeout …` (E39).
   L'outil `chronometrer-livraison.sh` relève `committed_date`, `merged_at` (API GitLab, jeton des checks), la ligne du webhook, les lignes du contrôleur, `startedAt`/`finishedAt` de l'opération (ou de l'historique), la création et la disponibilité du pod le plus récent. Ordres de grandeur attendus : webhook + rafraîchissement en une seconde ; génération en quelques secondes (premier rendu d'une révision) ; opération de quelques dizaines de secondes (vagues, Job de migration en vague -1, attente de santé de chaque vague) ; sonde `/pret` en une vingtaine de secondes. Sans webhook : jusqu'à `timeout.reconciliation` (180 s) plus la gigue en attente avant la moindre action — l'argument du webhook d'E27.

3. **Repo-server.** `ls /tmp/_argocd-repo/` : un répertoire par dépôt, nommé par un UUID, pour ne pas faire apparaître l'URL (et d'éventuels identifiants) dans les journaux et les messages d'erreur (commentaire explicite dans le code du repo-server). `--refresh` recompare avec ce qui est en cache ; `--hard-refresh` invalide aussi le cache des manifestes et force la résolution de la révision et la régénération.

4. **Redis.** Familles relevées (code de la 3.5.5) : `mfst|` (manifestes générés, par suivi, application, révision, espace, empreinte de la source), `git-refs|` (références d'un dépôt, d'où le délai d'E37), `appdetails|`, `revisionmetadata|`, `gitfiles|`/`gitdirs|` (générateurs Git des ApplicationSets) ; côté contrôleur, l'état des ressources gérées et des clusters pour l'interface. Redis n'est pas une source de vérité : un redémarrage coûte des recalculs (pointe de génération sur le repo-server), pas des déploiements. Ne jamais afficher les valeurs (manifestes, éventuellement données de configuration).

5. **Comparaison.** `kubectl -n argocd get application mediagenda-dev -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/compare-options}'` → `ServerSideDiff=true,IncludeMutationWebhook=true` (posé par l'ApplicationSet, M20-E12) ; `controller.diff.server.side` absent d'`argocd-cmd-params-cm` (défaut `false`) : la comparaison côté serveur est donc **par Application**. `argocd app manifests --source git` et `kubectl kustomize` produisent les mêmes objets ; Argo CD ajoute l'annotation de suivi `argocd.argoproj.io/tracking-id: mediagenda-dev:apps/Deployment:mediagenda-dev/mediagenda` (application, groupe/type, espace/nom) au moment d'appliquer — elle est visible en `--source live`. Retirée à la main, elle est remise à la synchronisation suivante ; copiée sur un objet étranger, elle fait croire à Argo CD que l'objet est à lui (et il l'élaguerait s'il n'est pas dans Git).

6. **Métriques** (ports : contrôleur 8082, serveur 8083, repo-server 8084) : `argocd_app_reconcile` (histogramme de durée de réconciliation), `argocd_git_request_total` (requêtes Git par type) et `argocd_git_lsremote_fail_total` / `argocd_git_fetch_fail_total` (repo-server : E37 en une courbe), `argocd_app_sync_total` par phase (E36, E39 : rythme anormal de synchronisations automatiques), `argocd_app_info` (statuts de synchronisation et de santé : E35, E38), `argocd_app_condition` (conditions par type : `ComparisonError`, `SharedResourceWarning`), `argocd_cluster_api_resource_objects` et `argocd_cluster_connection_status` (E42). Noms et étiquettes à vérifier sur ta version (`curl -s localhost:8082/metrics | grep ^argocd_ | cut -d'{' -f1 | sort -u`).

7. **Retour.** `helmfile -e par1 -l composant=argocd diff` (sans les `--set`) ne montre que le retour des deux clés à `info`, `apply`, vérifier `argocd-cmd-params-cm`, commit du livrable.

**Explications** — Argo CD est un ensemble de boucles : le serveur reçoit et authentifie (interface, CLI, webhooks), le contrôleur réconcilie (cache d'état des clusters par *watch*, comparaison, opérations), le repo-server génère (Git, Kustomize, Helm, greffons), Redis met en cache ; l'ApplicationSet controller et le contrôleur de notifications sont des boucles à côté. Chaque panne du palier se situe dans une de ces boucles : la lecture des journaux et des métriques se fait boucle par boucle.

**Alternatives** — mesurer par les métriques seules (histogrammes, pas d'événement par livraison) ; tracer par OpenTelemetry (Argo CD sait exporter des traces : `otlp.address` dans `argocd-cmd-params-cm`, à brancher au M23).

**Pièges classiques** — oublier de revenir en `info` ; `kubectl debug` sur un pod d'Argo CD (le conteneur éphémère reste jusqu'à la recréation du pod) ; afficher des valeurs de Redis ou des journaux `debug` contenant des données de configuration dans un document partagé ; lire les journaux d'un seul réplica du contrôleur partitionné.

**En production chez MédiSphère** : tableau de bord Argo CD (M21) avec ces métriques ; `debug` seulement sur décision d'astreinte, avec durée notée ; traces des réconciliations au M23.

---

### M20-E45 — Questions expert : GitOps

**1. `Synced` et `Healthy`, mais le cluster ne fait pas ce que Git décrit.** (a) Champ ignoré : `ignoreDifferences` (avec `RespectIgnoreDifferences`) masque une valeur différente posée par un autre acteur (E39 v1 mal corrigé) ; seul le diff « sans ignorer » ou les `managedFields` le montrent. (b) Champ en plus : un objet porte une valeur que Git ne décrit pas du tout (`spec.paused: true`, E40 v4 ; une variable d'environnement ajoutée par `kubectl set env`) : la comparaison 3-way ne compare que les champs décrits ; `kubectl get -o yaml` et `managedFields`. (c) Santé optimiste : un contrôle de santé personnalisé qui dit `Healthy` par défaut, ou une ressource sans contrôle (santé inconnue agrégée comme saine) ; seul un test applicatif (sonde blackbox, M21) le voit. On peut ajouter : le contenu d'un Secret géré hors Git (E37), et un `targetRevision` qui suit une branche ou une étiquette déplacée.

**2. Stratégies de comparaison.** *3-way historique* : compare le rendu Git au vivant, en s'aidant de `last-applied-configuration` pour savoir quels champs ont été appliqués ; laisse passer les champs en plus, et invente des différences sur les valeurs normalisées ou défautées par l'API dans les listes atomiques des CRD (E35 v4). *Structured merge* (activée avec `ServerSideApply=true`, abandonnée au profit de la suivante) : compare par propriété des champs ; mal à l'aise avec les valeurs par défaut des CRD. *Côté serveur* : un `apply --server-side --dry-run` par ressource donne l'état prédit, comparé au vivant ; les défauts et normalisations de l'API sont inclus, les webhooks de validation s'expriment dès le diff ; **pas** les webhooks de mutation par défaut — d'où `IncludeMutationWebhook=true`, pour que la base CNPG complétée par son webhook ne soit pas éternellement `OutOfSync`. Elle laisse passer ce qui n'est pas dans la requête (un objet nouveau n'est pas comparé côté serveur) et coûte des appels à l'API (mis en cache par version de ressource).

**3. `selfHeal` et la bataille.** `selfHeal` remet Git quand le vivant diverge ; si un second écrivain veut une autre valeur, il la remet après chaque réparation : la boucle est sans fin. L'attente exponentielle (2 s × 3ⁿ, plafond 300 s) limite la charge et les redémarrages, mais transforme la bataille en oscillation lente, plus difficile à remarquer. Désactiver `selfHeal` arrête la bataille en donnant raison à l'autre écrivain, en silence : la dérive devient permanente et invisible, et la prochaine synchronisation (pour une autre raison) relancera la bataille. Le correctif est de supprimer l'ambiguïté de propriété.

**4. `ignoreDifferences` sur `/spec`.** Non : on ignorerait toute dérive réelle (image, sondes, ressources), et l'Application dirait `Synced` quoi que contienne le cluster. On ignore un champ quand il **appartient par conception** à un autre contrôleur (poids du greffon, réplicas d'un HPA ou du Rollout, champs posés par un opérateur), on le décrit dans Git quand il exprime une **intention** humaine. Si on peut le décrire sous forme canonique, on le décrit. `RespectIgnoreDifferences=true` fait que la synchronisation n'écrase pas le champ ignoré (sinon il est ignoré dans le diff mais remis à chaque synchronisation).

**5. `prune` et `selfHeal` en production.** Pour : la production est exactement ce que dit Git, une dérive est réparée sans délai, pas d'étape manuelle à oublier. Contre : un commit erroné (E41) supprime ou casse sans regard humain ; une bataille (E39) redémarre des pods en prod ; la synchronisation devient le moment du risque, sans le choisir. MédiSphère (ADR-0200) : prod synchronisée à la main après MR approuvée, revue du diff (`argocd app diff`, `sync --dry-run`), fenêtres et gel (E29). Un élagage automatique en prod deviendrait acceptable avec : `Prune=false,Delete=false` sur toutes les données posés par un component, `PruneLast=true`, `Prune=confirm` sur les objets critiques, porte de MR qui liste les suppressions, canary pour tout ce qui sert du trafic, et des sauvegardes vérifiées.

**6. Finaliseur `resources-finalizer.argocd.argoproj.io`.** À la suppression de l'Application, l'API pose `deletionTimestamp` ; le contrôleur voit le finaliseur, supprime **toutes** les ressources gérées (en cascade, sauf `Delete=false`), puis retire le finaliseur, et l'Application disparaît. Contrôleur arrêté : l'Application reste « en suppression » indéfiniment, rien n'est supprimé… jusqu'au redémarrage du contrôleur, qui fait alors le travail (le piège de la reconstruction, E28). Supprimer **sans** toucher aux charges : retirer d'abord le finaliseur (`kubectl patch application … --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'`) ou utiliser `argocd app delete --cascade=false`, puis supprimer ; vérifier ensuite que les objets portent toujours leur annotation de suivi (ils seront adoptés par la future Application).

**7. Hook `Sync` en vague -1 contre `PreSync`.** La phase `PreSync` passe avant **toutes** les vagues : sur un environnement neuf, la base (vague -2) n'existe pas encore, la migration échoue, et la base ne sera jamais créée — interblocage. En `Sync` vague -1, la base et Valkey (vague -2) sont créées et **saines** avant le Job, l'application (vague 0) après. Une ressource d'une vague qui ne devient jamais saine bloque l'opération en `Running` (« waiting for healthy state of … ») sans limite par défaut (`controller.sync.timeout.seconds: 0`) : E35 v1. D'où un délai de synchronisation en production, et des `activeDeadlineSeconds` sur les Jobs.

**8. `argocd app rollback` contre `git revert`.** `rollback` resynchronise l'Application sur une révision **antérieure** de son historique, hors de Git. Il est refusé tant que la synchronisation automatique est active (« rollback cannot be initiated when auto-sync is enabled » : sinon le contrôleur ramènerait aussitôt `main`) ; l'interface propose de la désactiver d'abord. Résultat : Git et le cluster divergent, la synchronisation automatique est coupée, et il faut penser à la réactiver après avoir corrigé Git. `git revert` crée un commit inverse dans Git, passe par MR et CI, et la synchronisation (automatique ou manuelle) applique ; Git reste vrai, l'historique raconte l'incident. `rollback` est un outil d'urgence (minutes comptées, CI indisponible), à suivre d'un revert.

**9. Le repo-server.** Entrées : URL et identifiants du dépôt, révision (résolue par `ls-remote`), chemin, type de source et options (Kustomize : version, options de construction ; Helm : valeurs, paramètres), outils embarqués (Kustomize 5.8.1, Helm 4.2 dans la 3.5), greffons de gestion de configuration. Sortie : manifestes, mis en cache dans Redis (`mfst|…`) par révision et options. Risques : il exécute des outils sur du contenu fourni par les équipes (une option `--enable-helm` ou un greffon peuvent télécharger et exécuter du code), il détient tous les identifiants de dépôts, et un rendu peut viser n'importe quel espace (d'où les AppProjects). Interdire Internet (E25) empêche l'exfiltration, le téléchargement de charts non recopiés et l'appel de ressources distantes de Kustomize ; les charts tiers passent par `plateforme/charts-miroir`.

**10. Le cache d'état du contrôleur.** Il surveille (*watch*) tous les types d'objets des clusters gérés (filtrés par les exclusions), d'où une mémoire proportionnelle au nombre d'objets et une pointe au démarrage (listes initiales). Il faut des droits de **liste/surveillance** sur ce qu'il surveille ; avec `resource.respectRBAC: normal`, il cesse de surveiller ce qu'il n'a pas le droit de lister au lieu de tomber en erreur (cluster de l'agence, E26/E42). Si une API d'extension est indisponible (webhook de conversion d'une CRD en panne), la synchronisation du cache de ce type échoue et le cluster peut passer en erreur : exclure ou corriger l'API ; c'est un classique après une désinstallation incomplète d'opérateur.

**11. Secrets hors Git.** Angles morts : Argo CD ne voit pas les Secrets créés par `secrets-k8s.sh` (pas de diff, pas d'historique) ; un Secret réécrit à la main (E37 v1, E42 v1) ne laisse de trace que dans `managedFields` et l'audit ; la reconstruction (E28) dépend d'un script et d'un Vault en plus de Git. External Secrets (M25) remet dans Git la **référence** (ExternalSecret : quel secret, quelle clé, quelle rotation), qu'Argo CD compare et répare, la valeur restant dans OpenBao ; SOPS remet dans Git la valeur chiffrée (greffon de déchiffrement dans le repo-server, clé à protéger). Dans les deux cas, un Secret modifié à la main redevient une dérive visible.

**12. Canary par la Gateway API.** Le greffon écrit les **poids** des `backendRefs` de la HTTPRoute ; Argo CD écrit le reste de la route (règles, filtres, noms d'hôte) ; le contrôleur d'Argo Rollouts écrit les ReplicaSets et les sélecteurs des Services stable et canary. Si Argo CD ne laisse pas les poids au greffon, il les remet à chaque synchronisation : trafic réel faux, canary qui « avance » sur le papier (E40 v3). `Error` : la mesure n'a pas pu être prise (code non 2xx, délai, analyse impossible) ; `Failed` : la mesure contredit la condition de succès. `consecutiveErrorLimit` (4 par défaut, 2 dans `pret-mediagenda`) arrête l'analyse après N erreurs **consécutives** : une indisponibilité de l'outil de mesure ne doit ni valider ni bloquer éternellement.

**13. Webhook contre interrogation.** Gains : délai de quelques secondes au lieu de `timeout.reconciliation` (3 min), moins d'appels `ls-remote` sur la forge. Risques : un point d'entrée public de l'API d'Argo CD (déni de service par rafraîchissements, d'où le secret partagé vérifié et la limitation de débit), une exception dans la liste d'autorisation des requêtes locales de GitLab (`git01` → 10.10.41.10) qui doit rester étroite. Webhook perdu : rien ne casse, l'interrogation périodique prend le relais — d'où l'importance de **ne pas** allonger `timeout.reconciliation` à l'excès en comptant sur le webhook.

**14. Cluster distant limité à un espace.** Gains : un Argo CD compromis ou une erreur de projet ne touchent que l'espace `agence` ; moins d'objets surveillés (mémoire) ; l'agence garde la main sur son cluster. Pertes : pas d'objets de cluster (CRD, ClusterRole, Namespace) depuis Argo CD — la plateforme de l'agence se gère autrement (manifestes de k3s, Ansible) ; chaque nouveau type d'objet dans l'application de l'agence (un Ingress, une NetworkPolicy) exige d'étendre le Role, sinon `forbidden` à la synchronisation et types non surveillés.

**15. Flux contre Argo CD après le palier.** Pour Flux (concrétisé par les pannes) : contrôleurs indépendants par type de source, sans API ni interface à exposer ni Redis à garder, et réconciliation par `Kustomization` dans le cluster cible lui-même — la panne E42 (gestion à distance d'un cluster d'agence) n'existerait pas sous cette forme, chaque agence tirant elle-même son dépôt. Pour Argo CD : la visibilité (diff, santé, historique, conditions) qui a rendu les huit pannes diagnosticables par une équipe, l'RBAC et les AppProjects multi-équipes, Argo Rollouts intégré. L'ADR-0200 n'a pas à changer pour le siège ; elle peut s'enrichir d'une **révision** : pour des sites distants nombreux et autonomes, un Flux local par site (ou un modèle « hub » avec des agents) serait réévalué — c'est un critère de révision, pas une décision.
