# Module 20 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

### M20-E46 — Mini-projet : MédiSphère en GitOps v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, l'ordre du retrait du provisoire (c'est là que se cachent les orphelins), la préparation des démonstrations et la **grille de revue** avec laquelle Claire, Karim, Sophie, Julien et Nadia évaluent la livraison. Les fichiers de référence sont ceux des exercices du module ; les nouveaux sont l'exemple de dossier de recette [`docs/recette-gitops-v1.md`](fichiers/M20-E46/docs/recette-gitops-v1.md) et, du palier 4, l'ApplicationSet `mediagenda` final ([`M20-E41/gitops/applications/mediagenda.yaml`](fichiers/M20-E41/gitops/applications/mediagenda.yaml) : `PruneLast`, `FailOnSharedResource`) et le component [`protection-donnees`](fichiers/M20-E41/deploiement/components/protection-donnees/kustomization.yaml).

**Solution**

*Plan de travail recommandé* (on prouve d'abord, on retire ensuite, on documente à la fin)

1. **État des lieux** (1 h) : `lab/bin/check 20 46`, puis `lab/bin/check 20 43` (tout le palier 4) et les contrôles détaillés rouges. Inventaire des restes :
   ```
   admin@adm01:~$ argocd app list
   admin@adm01:~$ argocd cluster list
   admin@adm01:~$ ls ~/.local/state/workbook/pannes-actives/
   admin@adm01:~$ for p in mediagenda%2Fdeploiement plateforme%2Fgitops; do glab api "projects/$p/merge_requests?state=opened" | jq -r '.[].source_branch'; done
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff
   ```
2. **Filet** (30 min) : instantané etcd vérifié (M14-E24), sauvegarde d'Argo CD (E28 : `argocd admin export` chiffré vers `s3-01`), sauvegardes CNPG de `mediagenda-prod` récentes (M16).
3. **Livraison de Julien, répétition** (1 à 2 h) — voir le tableau plus bas. Faite **avant** le retrait du provisoire : si quelque chose ne va pas, tu as encore le temps.
4. **Retirer `lyo-k3s01`** (1 à 2 h), dans cet ordre :
   1. *Ce qui le cible dans Argo CD.* L'ApplicationSet `labo-agences` (générateur `clusters`, politique `create-update`) ne supprime **pas** l'Application `labo-lyo-k3s01` quand le cluster disparaît, et l'Application n'a pas de finaliseur de cascade (`preserveResourcesOnDeletion`). Décision à écrire : retirer `applications/labo-agences.yaml` de `plateforme/gitops` (MR) — l'Application `applications` élague l'ApplicationSet, puis supprimer `labo-lyo-k3s01` (`argocd app delete labo-lyo-k3s01 --cascade=false` après avoir vérifié `metadata.finalizers`) ; ou garder l'ApplicationSet « prêt pour une prochaine agence » (sans cluster, il ne génère rien) et le dire dans `multi-cluster.md`.
   2. *Le Secret de cluster.* Retirer `secret_cluster_lyo_k3s01`, `verifier_cluster_lyo_k3s01` et leurs appels du module `outils/secrets-k8s.d/argocd.sh` de `plateforme/k8s` **et** les clés `lyo_k3s01_jeton`, `lyo_k3s01_ca` de `secrets/argocd.yml` (Vault `critique`), MR ; puis `kubectl -n argocd delete secret cluster-lyo-k3s01`. Dans l'autre ordre, le prochain `secrets-k8s.sh appliquer argocd` recréerait le cluster. `argocd cluster list` ne montre plus que `in-cluster`.
   3. *La VM.* `plateforme/infra/envs/m20` : groupe `lyo` retiré de `groupes` (`terraform.tfvars`, catalogue `hotes.tf` d'E23), `tofu plan` (uniquement des destructions : VM 2201, enregistrement DNS), `tofu apply`. Le module `vm-noeud` retire aussi l'objet NetBox ; vérifie-le.
   4. *Les flux.* `group_vars/role_routeur/pare_feu.yml` : règle VLAN 40 (`K8S_TRAV`) → `LYO_K3S01` 6443 et définition `LYO_K3S01` retirées ; `playbooks/routeurs.yml --limit gw01 --check --diff` (seule cette règle disparaît), puis `gw01`, puis `gw02`. `docs/socle/matrice-flux.md` : lignes marquées « retiré (M20-E46) » ou supprimées.
5. **Retirer `flux01`** (30 min à 1 h), s'il existe encore (le palier 3 conseillait de le détruire avant E26) : `groupes` de `envs/m20` sans `flux`, `tofu plan`/`apply` ; règle VLAN 99 (`FLUX01`) → `git01` 443 **et** définition `FLUX01` retirées de la bordure (même méthode) ; projet `formation/flux-labo` archivé (pas supprimé : il illustre le comparatif) et son jeton de déploiement révoqué.
6. **État `envs/m20` vide** : `tofu state list` ne rend rien ; garder le dossier `envs/m20` (le code des VMs reste un exemple réutilisable) ou le retirer, et le dire dans la MR.
7. **Converger** (1 à 2 h) : `helmfile diff` vide pour `argocd` ; `argocd app list` tout `Synced`/`Healthy` ; `lab/bin/check 20 30` (aucun droit de la CI) ; component `protection-donnees` dans les trois overlays ; ApplicationSet `mediagenda` avec `PruneLast` et `FailOnSharedResource` ; plus aucune MR `lucas/…` ni `wb/annulation-…`.
8. **Documentation et livraison** (2 à 3 h) : `recette-gitops-v1.md`, RB-200 complet, `multi-cluster.md` marqué historique, liste pour le M21 (ci-dessous), étiquette `gitops-v1`.

*Démonstration de Julien — une version jusqu'en production* (à répéter et chronométrer **avant** la revue)

| Étape | Action | Attendu |
|---|---|---|
| 1 | Étiquette `vX.Y.Z` sur `mediagenda/api` | pipeline : construction, analyse, signature, MR de promotion vers `overlays/dev` ouverte par `ci-promotion` |
| 2 | Julien fusionne la MR de dev | `mediagenda-dev` synchronisée automatiquement (webhook : quelques secondes), `Healthy` |
| 3 | `outils/promouvoir.sh dev recette` (E14), MR, fusion | canary de recette : `setWeight` 10, tests de fumée, pauses, analyses `Successful`, Rollout `Healthy` |
| 4 | `outils/promouvoir.sh recette prod`, MR approuvée, fusion | `mediagenda-prod` `OutOfSync` (synchronisation manuelle) ; `argocd app diff mediagenda-prod` montre **seulement** le changement d'image |
| 5 | `argocd proj windows list mediagenda` puis `argocd app sync mediagenda-prod` dans une fenêtre autorisée | canary de prod, analyses `Successful`, Rollout `Healthy` |
| 6 | Mailpit | courriel `on-deployed` pour `mediagenda-prod` (abonnement de l'ApplicationSet, E19) |

Durée typique : 25 à 40 minutes, dont l'essentiel en pauses de canary (2 × 3 pauses de 2 min) ; à consigner dans `recette-gitops-v1.md`.

*Vérification de Sophie* : `kubectl auth can-i create deployments -n mediagenda-prod --as=system:serviceaccount:gitlab-agent:gitlab-agent` → `no` (et pour `medidoc-*`) ; configuration de l'agent `k8s-par1` (`ci_access` limité à `wb-essais`) ; `lab/bin/check 20 24`, `20 25`, `20 30`.

*La panne de Karim* : n'importe quelle panne du palier 4 (il choisira probablement E37 ou E40). Ce qui est évalué : la photographie (`outils/argocd-diagnostic.sh`), la lecture du message entier, l'arbre de RB-200, le correctif par Git, la vérification. Pas la vitesse.

*Ce que le M21 devra alerter* (à écrire dans la documentation, repris du palier 4) :

| Signal | Métrique (Argo CD 3.5, Argo Rollouts 1.10) | Panne du palier |
|---|---|---|
| Application `Unknown` ou en erreur de comparaison | `argocd_app_info{sync_status="Unknown"}`, `argocd_app_condition{type="ComparisonError"}` | E35 v3, E37 |
| Échecs Git du repo-server | `argocd_git_lsremote_fail_total`, `argocd_git_fetch_fail_total` | E37 |
| Synchronisations en échec | `argocd_app_sync_total{phase=~"Failed|Error"}` | E36 |
| Opération qui dure | durée de `operationState` (pas de métrique directe : notification, ou `controller.sync.timeout.seconds`) | E35 v1 |
| `Degraded` durable | `argocd_app_info{health_status="Degraded"}` | E38 |
| Bataille | taux de synchronisations automatiques sans nouvelle révision (`argocd_app_sync_total`) | E39 |
| Rollout interrompu, contrôleur absent | métriques du contrôleur d'Argo Rollouts (`rollout_info`, à vérifier), absence de cible `up` | E40 |
| Cluster injoignable | `argocd_cluster_connection_status` | E42 |

*Comment un module ajoute un service de plateforme* (M21 à M23, blocs F et G) : chart tiers ajouté à `charts.yaml` de `plateforme/charts-miroir` (empreinte vérifiée, recopie OCI, signature Cosign) ; valeurs dans `plateforme/gitops/valeurs/<service>/values.yaml` ; Application multi-sources dans `plateforme/gitops/plateforme/<service>.yaml` (projet `plateforme`, chart OCI de `registry.par1.medisphere.internal/charts`, `$values`) ; espace déclaré dans `plateforme/k8s/espaces/` ; politiques réseau dans `plateforme/k8s` ; Secrets par `secrets-k8s.sh` jusqu'au M25. Rien de tout cela ne passe par `helmfile apply` : la couche de base reste celle du M17 + M19 + Argo CD.

**Explications** — un mini-projet de GitOps se juge sur ce que **Git ne dit plus** autant que sur ce qu'il dit : un cluster enregistré à la main, un Secret de cluster recréé par un script oublié, une règle de bordure qui vise une adresse libérée, une MR de panne restée ouverte sont autant d'écarts entre la description et la réalité. L'ordre du retrait suit la chaîne des dépendances inverses : ce qui cible (Applications, ApplicationSets), ce qui authentifie (Secrets et leur source), ce qui existe (VM), ce qui relie (flux), ce qui recense (DNS, NetBox, matrice).

**Alternatives** — garder `lyo-k3s01` éteinte « pour plus tard » : refusé par le ticket (provisoire) et par le budget mémoire (blocs E et suivants) ; la recréer coûte un `tofu apply` et un playbook. Garder Flux sur `flux01` pour une démonstration : le comparatif écrit (E23) suffit, la VM coûte 2 Go.

**Pièges classiques**
- Détruire la VM avant de retirer le Secret de cluster : Argo CD garde un cluster `Failed`, l'ApplicationSet garde son Application en erreur, et le prochain `secrets-k8s.sh` recrée le tout.
- Supprimer `labo-lyo-k3s01` avec cascade alors que le cluster est déjà détruit : l'Application reste bloquée « en suppression » (le contrôleur ne peut pas joindre le cluster pour supprimer les objets) ; retirer son finaliseur à la main devient nécessaire — d'où la préférence pour `--cascade=false` sur une cible déjà perdue.
- Retirer la règle de bordure sur `gw01` seulement (matrice commune : les deux passerelles).
- Oublier `docs/socle/matrice-flux.md` et `docs/kubernetes/reseau/matrice-flux-cluster.md`.
- Une mise en production de démonstration lancée un vendredi après 16 h : la fenêtre la refuse — c'est le système qui marche, mais la démonstration tombe.

**En production chez MédiSphère** : la recette `gitops-v1` devient la checklist de chaque montée de version d'Argo CD (E28 rejoué sur une copie) ; les retraits d'environnements suivent le même ordre (ticket CHG, dépendances inverses, preuve par contrôle) ; les alertes listées ci-dessus sont la première tâche du M21.

**Grille de revue**

| Critère | Attendu | Évalué par |
|---|---|---|
| Contrôle global | `lab/bin/check 20 46` vert, sans `[--]` inexpliqué | Claire |
| GitOps intégral | toutes les Applications d'équipe sous ApplicationSets ; `helmfile diff` vide ; aucun gestionnaire de champs étranger | Karim |
| Livraison | de l'étiquette à la prod sans geste hors de Git, canary et analyses, notification, durée mesurée | Julien |
| Sécurité | CI sans droits ; RBAC testé ; durcissement ; aucun secret dans les dépôts ni la documentation | Sophie |
| Exploitation | RB-200 complet, post-mortem INC-4743, diagnostic en direct de la panne de Karim, liste d'alertes pour le M21 | Nadia |
| Provisoire | VMs, état, flux, DNS, NetBox, cluster enregistré, MR de panne : tout retiré, par le code | Karim |
| Présentation | frontière Helmfile / Argo CD, modèle de promotion, limites (Secrets hors Git jusqu'au M25, un seul Argo CD, pas d'analyse Prometheus avant le M21) | Claire |
