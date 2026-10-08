# Module 17 — Packaging (Helm, Kustomize, Helmfile)

| | |
|---|---|
| **Bloc** | C — Conteneurs et Kubernetes |
| **Niveau** | Secondaire |
| **Profil de lab** | k8s : socle + `k8s-par1` (+ `ceph-par1` pour les volumes de MédiAgenda) |
| **Prérequis** | Module 14 (`k8s-v1`) ; modules 15 et 16 (composants de plateforme installés, CloudNativePG) ; module 13 (Harbor, Cosign) |
| **Durée indicative** | 20 à 28 heures |

## Contexte MédiSphère

Les manifestes de MédiAgenda sont copiés d'un environnement à l'autre et modifiés à la main ; personne ne sait plus quelle version de cert-manager tourne ni avec quelles valeurs. Julien Petit veut **un paquet** de son application, versionné et testé, qu'il installe en dev, en recette et en production avec trois commandes. Karim Benali veut que toute la plateforme installée depuis le module 14 soit décrite dans un seul fichier, relu en MR. Ce module prépare directement l'intégration continue (M19) et GitOps (M20).

## Objectifs

À la fin de ce module, tu sais :
- utiliser Helm 4 et écrire un chart de qualité (valeurs, schéma, helpers, dépendances, hooks) ;
- tester un chart (helm-unittest, `helm test`, chart-testing) et le publier en OCI, signé ;
- organiser des déploiements par environnement avec Kustomize (bases, overlays, components) ;
- décrire et faire évoluer la plateforme avec Helmfile ;
- comprendre où Helm stocke ses releases, comment fonctionne le *server-side apply*, et réparer une release bloquée.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M17-E01 | Questions : manifestes, gabarits et overlays | Q | ★★ | 1 |
| M17-E02 | Helm 4 : installer, inspecter, monter, revenir | LAB | ★★ | 1 |
| M17-E03 | Écrire le chart `mediagenda` | LAB | ★★ | 1 |
| M17-E04 | Kustomize : une base et des overlays | LAB | ★★ | 1 |
| M17-E05 | Valeurs, schéma de valeurs et helpers | LAB | ★★ | 1 |
| M17-E06 | Dépendances et sous-charts | LAB | ★★★ | 2 |
| M17-E07 | Tester un chart | LAB | ★★★ | 2 |
| M17-E08 | Publier le chart en OCI dans Harbor et le signer | LAB | ★★ | 2 |
| M17-E09 | Kustomize avancé : components, remplacements, générateurs | LAB | ★★★ | 2 |
| M17-E10 | Helmfile : décrire la plateforme | LAB | ★★★ | 2 |
| M17-E11 | Revue : le chart du stagiaire | REV | ★★ | 2 |
| M17-E12 | Hooks, ordre de déploiement et migrations de schéma | LAB | ★★★ | 2 |
| M17-E13 | Le pipeline du chart | LIBRE | ★★★ | 3 |
| M17-E14 | Différences et dérive : `helm diff`, `kubectl diff`, *server-side apply* | LAB | ★★ | 3 |
| M17-E15 | Des paquets sans secrets | LAB | ★★ | 3 |
| M17-E16 | Monter un composant de plateforme par Helmfile | LAB | ★★★ | 3 |
| M17-E17 | ADR : Helm, Kustomize ou les deux | RED | ★★ | 3 |
| M17-E18 | Livrer une nouvelle version de MédiAgenda en temps limité | CHRONO | ★★★ | 3 |
| M17-E19 | Panne : la release est bloquée | BF | ★★ | 4 |
| M17-E20 | Panne : le rendu du chart échoue | BF | ★★ | 4 |
| M17-E21 | Panne : la production déploie la mauvaise image | BF | ★★ | 4 |
| M17-E22 | Panne : conflit de propriété des champs | BF | ★★★ | 4 |
| M17-E23 | Sous le capot : où Helm range-t-il ses releases ? | LAB | ★★★ | 4 |
| M17-E24 | Questions expert : packaging | Q | ★★★ | 4 |
| M17-E25 | Mini-projet : packaging MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 4 break & fix · 2 questionnaires · 1 revue · 1 rédaction · 1 chronométré.

## Objets créés dans ce module

| Élément | Valeur | Exercice |
|---|---|---|
| Chart | `mediagenda` (projet GitLab `mediagenda/chart`), publié dans Harbor `oci://registry.par1.medisphere.internal/charts` | E03, E08 |
| Déploiements par environnement | projet `mediagenda/deploiement` (base + overlays `dev`, `recette`, `prod`) | E04, E09 |
| Plateforme | `helmfile.yaml` du projet `plateforme/k8s` (composants des modules 14 à 16) | E10 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.10.

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 17 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 17 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
