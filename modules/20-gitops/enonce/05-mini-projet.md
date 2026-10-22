# Module 20 — GitOps et déploiement continu : palier 5 — Mini-projet

Le module a fait passer MédiSphère d'un `helmfile apply` et d'un `kubectl apply -k` lancés depuis `adm01` à une plateforme où Git décrit tout, où Argo CD converge en continu, où les versions passent de dev à la production par MR, canary et analyses, où la CI n'a plus aucun droit sur les applications, et où chaque panne du palier 4 a laissé un runbook. Il reste à le **livrer** : une brique propre, sans provisoire — le cluster de l'agence et la VM de comparaison avec Flux ont fait leur temps —, documentée, et prête pour les modules suivants, qui ajouteront leurs services de plateforme comme des Applications de `plateforme/gitops`. C'est ce que Claire Morel présentera au comité de direction et à l'auditeur HDS comme « MédiSphère en GitOps v1 ».

---

### M20-E46 — Mini-projet : MédiSphère en GitOps v1  `LIBRE` `★★★`

> **Ticket PLAT-2146** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel*
> Recette de « GitOps v1 » dans deux semaines. Je veux un contrôle global sans un rouge, **sans rien de provisoire** (plus de `lyo-k3s01` ni de `flux01`, plus leurs flux, plus de panne ouverte, plus de branche de Lucas qui traîne), et une plateforme prête pour la supervision (M21) : les modules suivants livreront leurs composants par Argo CD, comme MédiAgenda.
> Pendant la revue : Julien livrera une nouvelle version de MédiAgenda **jusqu'en production** devant nous (MR de promotion, canary, analyses, notification) ; Sophie vérifiera que la CI ne peut plus rien écrire dans les espaces applicatifs et relira le RBAC et le durcissement d'Argo CD ; Karim fera la revue de `plateforme/gitops` et de la release `argocd`, puis cassera « quelque chose » dans Argo CD pendant ta présentation ; Nadia te demandera où sont les runbooks et ce qui alerte aujourd'hui. Format habituel : 10 minutes de présentation, les démonstrations, nos questions.

**Objectifs pédagogiques**
- Consolider le module en une brique cohérente : toutes les applications sous ApplicationSets, la couche de base sous Helmfile, aucune écriture hors de Git sur les espaces applicatifs.
- Prouver ce qui a été construit : une mise en production complète par MR, canary et analyses, notification ; un diagnostic en direct ; une CI sans droits.
- Retirer proprement ce qui était provisoire (VMs, flux, enregistrements, cluster enregistré) **par le code**, et livrer l'état `gitops-v1`.

**Prérequis** : M20-E01 à M20-E45 (au minimum tous les `LAB`, `LIBRE`, `BF` et le `CHRONO`) ; `ci-v1` (M19-E46).
**Durée indicative** : 8 à 12 h, plus 30 min de revue.

**Contexte technique**
- Argo CD 3.5.5 (release Helmfile `argocd` de `plateforme/k8s`, espace `argocd`) ; `plateforme/gitops` : `racine/` (Applications `racine`, `projets`, `applications`, et celle des services de plateforme), `projets/` (AppProjects `plateforme`, `mediagenda`, `medidoc`, `labo`), `plateforme/` (Application `argo-rollouts`), `applications/` (ApplicationSets `mediagenda`, `medidoc`, `labo-agences`, Application `labo`).
- Argo Rollouts 1.10.1 (chart recopié dans Harbor `charts/` par `plateforme/charts-miroir`), greffon Gateway API 0.17.0 ; Rollout `mediagenda` en recette **et** en production.
- VMs provisoires de l'état OpenTofu `envs/m20` : 2201 `lyo-k3s01` (10.10.99.61) et 2202 `flux01` (10.10.99.62), avec leurs enregistrements DNS, leurs objets NetBox, leurs flux de bordure (VLAN 40 → 10.10.99.61:6443, VLAN 99 → `git01` 443) et, pour `lyo-k3s01`, le Secret de cluster `cluster-lyo-k3s01` d'Argo CD (`secrets-k8s.sh`, composant `argocd`) et l'Application `labo-lyo-k3s01`.
- Le contrôle global `lab/bin/check 20 46` rejoue les contrôles clés des paliers (E06, E08, E10, E16, E18, E24, E25, E30), puis vérifie l'intégration, le retrait du provisoire et la documentation. Il prend quelques minutes.

**État livré `gitops-v1`** — ce que les modules 21 à 29 et les finaux trouveront en entrant. Rien de ce tableau ne doit manquer, rien ne doit porter un autre nom.

| Élément | État attendu à la livraison |
|---|---|
| Argo CD | 3.5.5, release Helmfile `argocd` sans dérive (`helmfile diff` vide) ; HA (E27) ; `admin` désactivé, comptes locaux `<MOI>`, `karim-benali`, `julien-petit`, `nadia-roussel`, `ci-lecture` ; RBAC par équipe testé en CI (E24) ; durcissement (E25) ; webhooks GitLab → Argo CD (E27) ; sauvegarde et procédure de reconstruction (E28, RB-201) ; notifications vers Mailpit (E19) |
| `plateforme/gitops` | racine Synced et propriétaire de tout ; AppProjects par équipe ; **toutes** les Applications de `mediagenda-*` et `medidoc-*` générées par un ApplicationSet ; `prod` sans synchronisation automatique, fenêtres de synchronisation et gel (E29) ; `PruneLast=true`, `FailOnSharedResource=true` ; services de plateforme : `argo-rollouts` (les modules 21 à 23 ajouteront les leurs dans `plateforme/`) |
| Livraison | promotion par MR (`outils/promouvoir.sh`, E14) ; canary + analyses (`fumee-mediagenda`, `pret-mediagenda`) en recette et en prod ; component `protection-donnees` dans les trois overlays ; porte de MR `verifier-overlays` (E36) |
| CI | aucun droit d'écriture sur les espaces applicatifs (agent `k8s-par1` limité à `wb-essais`, E30) ; pipeline de `mediagenda/deploiement` = validation seulement |
| Provisoire retiré | VMs 2201 et 2202 détruites par OpenTofu, état `envs/m20` vide ; flux de bordure et définitions retirés (`pare_feu.yml`, `gw01`/`gw02`), matrice des flux à jour ; DNS et NetBox nettoyés ; plus aucun cluster distant enregistré dans Argo CD ; plus aucune panne ouverte ni MR `lucas/…` ou `wb/annulation-…` |
| Documentation | `docs/livraison/gitops/` : ADR-0200, RB-200 (avec les sections du palier 4), RB-201, `promotion.md`, `politique-changements.md`, `comparatif-flux.md`, `rbac.md`, `durcissement-argocd.md`, `multi-cluster.md` (marqué « historique » : l'agence est retirée), `performance.md`, `sous-le-capot.md`, `recette-gitops-v1.md` ; post-mortem INC-4743 ; étiquette `gitops-v1` sur `plateforme/medisphere` |

**Travail demandé**
1. **Rien de provisoire.** Retire `lyo-k3s01` et `flux01` dans l'ordre qui ne laisse rien d'orphelin : d'abord ce qui dépend d'eux (Application et Secret de cluster côté Argo CD, ApplicationSet par cluster), puis les VMs par le code, puis leurs flux, leurs enregistrements et leurs objets d'inventaire. Aucune panne `M20` ouverte, aucune branche de panne qui traîne.
2. **Tout par Git et par le code.** Toutes les applications sous ApplicationSets ; release `argocd` sans dérive ; aucun objet des espaces applicatifs écrit par autre chose qu'Argo CD et les contrôleurs du cluster ; aucun `kubectl apply` ni `argocd app set` résiduel.
3. **Une mise en production complète, préparée.** Une nouvelle version de MédiAgenda, de l'étiquette de l'API à la production : MR de promotion dev → recette → prod, canary de recette puis de prod avec analyses réussies, synchronisation manuelle de la prod dans une fenêtre autorisée, notification `on-deployed` reçue. Répète-la avant la revue et chronomètre-la.
4. **Prêt pour la supervision.** Liste, dans la documentation, ce que le M21 devra alerter à partir des pannes du palier 4 (métriques d'Argo CD et d'Argo Rollouts) et la façon dont un module ajoute un service de plateforme (chart recopié par `plateforme/charts-miroir`, Application dans `plateforme/gitops/plateforme/`, projet `plateforme`).
5. **Dossier de recette.** `docs/livraison/gitops/recette-gitops-v1.md` (squelette : `modules/20-gitops/ressources/E46-gitops-v1/recette-gitops-v1.md`) : chaque exigence du ticket avec sa **preuve** (commande, MR, pipeline), et les écarts justifiés.
6. **Livraison.** Tout est fusionné, les pipelines de `main` sont verts, l'étiquette **`gitops-v1`** est posée sur `plateforme/medisphere`.
7. **La revue.** 10 minutes de présentation (architecture, frontière Helmfile / Argo CD, modèle de promotion, limites), la livraison de Julien jusqu'en production, la vérification de Sophie, la panne de Karim (diagnostic en direct avec RB-200), les questions de Nadia.

**Contraintes**
- La production n'est synchronisée qu'à la main, dans une fenêtre autorisée, après une MR approuvée ; jamais pendant un incident.
- Aucune suppression d'Application sans vérification de ses finaliseurs ; aucune donnée détruite (bases, volumes, compartiments).
- Tout ce qui est retiré l'est par le code (OpenTofu, Ansible, `plateforme/gitops`, `secrets-k8s.sh`) ; une intervention manuelle exceptionnelle est consignée et reportée dans le code.
- Aucun secret dans un dépôt, un journal de CI ou la documentation.
- Les choix qui s'écartent d'un exercice du module sont justifiés (ADR-0200 ou description de MR).

**Critères de réussite**
- [ ] `lab/bin/check 20 46` est entièrement vert.
- [ ] La livraison de Julien va de l'étiquette à la production sans geste hors de Git, canary et analyses compris, avec la notification reçue ; sa durée est mesurée et consignée.
- [ ] Sophie constate que le compte de la CI ne peut rien écrire dans `mediagenda-*` ni `medidoc-*` (preuve par `kubectl auth can-i --as=…`).
- [ ] La panne de Karim est diagnostiquée en direct avec RB-200.
- [ ] La documentation dit ce que le M21 devra alerter et comment un module ajoute un service de plateforme ; la revue est passée (auto-évaluation avec la grille du corrigé si tu travailles seul).

**Vérification** : `lab/bin/check 20 46`

<details><summary>Indice 1</summary>

Lance `lab/bin/check 20 46` dès le début : la liste des points rouges est ton plan de travail. `lab/bin/check 20 43` rejoue d'un coup tout le palier 4.
</details>

<details><summary>Indice 2</summary>

L'ordre du retrait compte : un ApplicationSet par cluster qui perd son cluster ne supprime pas son Application (politique `create-update`) ; une Application dont le cluster n'existe plus reste en erreur ; un Secret de cluster recréé par `secrets-k8s.sh` au prochain passage fait revenir le cluster. Retire d'abord la source de chaque objet, puis l'objet.
</details>

<details><summary>Indice 3</summary>

Pour la livraison de Julien, prépare la fenêtre (E29) et le contrôle de Mailpit (`lab/bin/check 20 19`) avant la revue ; une mise en production qui tombe dans le gel du vendredi ne se force pas devant le comité.
</details>

**Pour aller plus loin** (facultatif) : une Application « garde-fou » dans `plateforme/gitops` qui déploie une règle d'alerte d'Argo CD dès que le M21 sera là (préparée, non synchronisée) ; une reconstruction complète d'Argo CD (E28) chronométrée, sur la configuration finale.
