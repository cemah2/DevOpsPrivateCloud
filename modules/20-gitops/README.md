# Module 20 — GitOps et déploiement continu

| | |
|---|---|
| **Bloc** | D — Livraison |
| **Niveau** | Cœur |
| **Profil de lab** | Socle v4 + `ceph-par1` + `k8s-par1` ; `lyo-k3s01` (2201) et `flux01` (2202), 2 Go chacune, le temps de leurs exercices |
| **Prérequis** | Module 19 (`ci-v1` : images promues par MR, agent GitLab) ; module 17 (chart, overlays de `mediagenda/deploiement`, Helmfile de `plateforme/k8s`) ; module 15 (Gateway `gw-par1`, cert-manager, ExternalDNS) |
| **Durée indicative** | 80 à 100 heures (palier 1 : 15-19 h ; palier 2 : 27-33 h ; palier 3 : 22-27 h ; palier 4 : 12-15 h ; mini-projet : 8-12 h) |

## Contexte MédiSphère

La CI sait construire et signer ; mais qui applique quoi en production, et comment savoir que le cluster est bien dans l'état décrit par Git ? Aujourd'hui, c'est Karim avec `helmfile apply` et `kubectl apply -k` depuis `adm01`, et personne ne remarque quand Lucas « corrige vite fait » un Deployment à la main. Claire Morel veut passer au **GitOps** : Git comme seule source de vérité, un contrôleur qui converge en continu, des promotions par MR, des déploiements progressifs qui s'arrêtent seuls quand ça tourne mal. Sophie Laurent veut que la CI n'ait plus aucun droit d'écriture sur les espaces applicatifs. L'agence de Lyon, qui a son propre petit cluster, doit être gérée du même endroit.

## Objectifs

À la fin de ce module, tu sais :
- installer, sécuriser et exploiter **Argo CD** : Applications, AppProjects, RBAC, App of Apps, ApplicationSets, vagues et hooks, multi-sources, multi-cluster ;
- reprendre sous Argo CD des charges déjà déployées, sans coupure ;
- promouvoir des versions d'environnement en environnement par MR, et revenir en arrière ;
- faire des déploiements progressifs avec **Argo Rollouts** (canary par la Gateway API, blue/green, analyses) ;
- comparer Argo CD avec **Flux** et les outils de promotion, et trancher dans un ADR ;
- diagnostiquer une application `OutOfSync`, `Degraded`, une synchronisation en échec, une dérive qui revient, un canary bloqué.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M20-E01 | Test de positionnement : déploiement et GitOps | Q | ★★ | 1 |
| M20-E02 | Installer Argo CD par Helmfile | LAB | ★★ | 1 |
| M20-E03 | Accéder à Argo CD : interface, CLI et comptes locaux | LAB | ★★ | 1 |
| M20-E04 | Première Application | LAB | ★ | 1 |
| M20-E05 | Synchronisation, santé, dérive et auto-réparation | LAB | ★★ | 1 |
| M20-E06 | Le dépôt `plateforme/gitops` et l'application racine | LAB | ★★ | 1 |
| M20-E07 | AppProjects : cloisonner les équipes | LAB | ★★★ | 1 |
| M20-E08 | Reprendre MédiAgenda dev sous Argo CD sans coupure | LAB | ★★★ | 1 |
| M20-E09 | Questions : les principes du GitOps | Q | ★★ | 1 |
| M20-E10 | ApplicationSets : un générateur pour trois environnements | LAB | ★★★ | 2 |
| M20-E11 | Vagues et hooks de synchronisation | LAB | ★★★ | 2 |
| M20-E12 | Ce qu'Argo CD ne doit pas gérer : différences ignorées et Secrets hors Git | LAB | ★★★ | 2 |
| M20-E13 | Helm et Kustomize dans Argo CD, sources multiples | LAB | ★★ | 2 |
| M20-E14 | Promouvoir une version de dev à la production, et revenir en arrière | LAB | ★★ | 2 |
| M20-E15 | Argo Rollouts : installer et premier canary | LAB | ★★ | 2 |
| M20-E16 | Canary piloté par la Gateway API | LAB | ★★★ | 2 |
| M20-E17 | Blue/green avec aperçu et promotion manuelle | LAB | ★★ | 2 |
| M20-E18 | Analyses : tests de fumée et requêtes web | LAB | ★★★ | 2 |
| M20-E19 | Notifications d'Argo CD | LAB | ★★ | 2 |
| M20-E20 | Questions : stratégies de déploiement | Q | ★★ | 2 |
| M20-E21 | Revue : les Applications du stagiaire | REV | ★★ | 2 |
| M20-E22 | Runbook : une application est `OutOfSync` ou `Degraded` | RED | ★★ | 2 |
| M20-E23 | Flux : le même déploiement avec un autre outil | LAB | ★★★ | 2 |
| M20-E24 | RBAC d'Argo CD et projets par équipe | LAB | ★★★ | 3 |
| M20-E25 | Durcir Argo CD | LAB | ★★★ | 3 |
| M20-E26 | Multi-cluster : le cluster de l'agence LYO1 | LAB | ★★★ | 3 |
| M20-E27 | Haute disponibilité et performance d'Argo CD | LAB | ★★★ | 3 |
| M20-E28 | Sauvegarder et reconstruire Argo CD | LAB | ★★★ | 3 |
| M20-E29 | Fenêtres de synchronisation et gel des changements | LAB | ★★ | 3 |
| M20-E30 | Retirer à la CI tout accès en écriture aux applications | LIBRE | ★★★ | 3 |
| M20-E31 | ADR : Argo CD, Flux et le modèle de promotion | RED | ★★ | 3 |
| M20-E32 | Questions de production : GitOps | Q | ★★★ | 3 |
| M20-E33 | Accueillir MédiDoc en GitOps | LIBRE | ★★★ | 3 |
| M20-E34 | Une mise en production en temps limité | CHRONO | ★★★ | 3 |
| M20-E35 | Panne : l'application reste `OutOfSync` | BF | ★★ | 4 |
| M20-E36 | Panne : la synchronisation échoue | BF | ★★ | 4 |
| M20-E37 | Panne : Argo CD ne lit plus le dépôt | BF | ★★ | 4 |
| M20-E38 | Panne : l'application est `Degraded` après synchronisation | BF | ★★ | 4 |
| M20-E39 | Panne : la dérive revient sans cesse | BF | ★★★ | 4 |
| M20-E40 | Panne : le canary ne progresse plus | BF | ★★★ | 4 |
| M20-E41 | Panne : une synchronisation a supprimé des ressources | BF | ★★★ | 4 |
| M20-E42 | Panne : le cluster de l'agence est `Unknown` | BF | ★★★ | 4 |
| M20-E43 | Astreinte : la mise en production tourne mal | BF | ★★★★ | 4 |
| M20-E44 | Sous le capot : du commit à l'objet | LAB | ★★★★ | 4 |
| M20-E45 | Questions expert : GitOps | Q | ★★★ | 4 |
| M20-E46 | Mini-projet : MédiSphère en GitOps v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 5 questionnaires · 1 revue · 2 rédactions · 1 chronométré.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| Argo CD 3.5 | espace `argocd`, release Helmfile `argocd`, `argocd.apps.par1.medisphere.internal` | Contrôleur GitOps | E02 |
| `plateforme/gitops` | projet GitLab | Application racine, AppProjects, services de plateforme, ApplicationSets | E06 |
| Argo Rollouts 1.10 | espace `argo-rollouts`, géré par Argo CD | Canary (plugin Gateway API 0.17) et blue/green | E15 |
| `lyo-k3s01` | VMID 2201, 10.10.99.61 | Cluster k3s de l'agence LYO1 (multi-cluster), **détruit** en fin de module | E26 |
| `flux01` | VMID 2202, 10.10.99.62 | k3s pour la comparaison avec Flux 2.9, **détruit** en fin de module | E23 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.11. Versions : [`annexes/versions-bloc-DE.md`](../../annexes/versions-bloc-DE.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 20 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 20 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
