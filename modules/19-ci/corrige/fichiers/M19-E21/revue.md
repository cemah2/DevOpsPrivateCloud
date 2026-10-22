# Revue de MR — pipeline du service « rappels » (Lucas Martin)

> Exemple de corrigé (M19-E21, DEV-2021). Gravités : **B** bloquant (fusion impossible), **M** majeur, **m** mineur.
> Lignes : celles de `ressources/E21-ci-lucas/.gitlab-ci.yml`.

Merci Lucas, le pipeline couvre les bonnes étapes. En l'état je ne peux pas l'approuver : un secret est
publié dans le dépôt, un job demande un runner privilégié et la sécurité est décorative. Détail :

| # | Ligne | Catégorie | Grav. | Défaut | Risque concret | Correction |
|---|---|---|---|---|---|---|
| 1 | 11 | Sécurité | **B** | Mot de passe du robot Harbor en clair dans les `variables:` du fichier | Toute personne qui lit le dépôt (et son historique, pour toujours) pousse dans `medisphere` | **Rotation immédiate** du robot (Sophie prévenue, INC), puis variable protégée et masquée ; jamais de secret dans un dépôt, interne ou non |
| 2 | 56-59 | Sécurité | **B** | Docker-in-Docker (`docker:dind`) : exige `privileged = true` sur le runner | Un job privilégié contrôle le nœud : n'importe quelle branche devient administrateur de l'hôte (ADR-0120, ADR-0190) | Composant `construction-image` (buildkitd rootless partagé, E08) |
| 3 | 8-9 | Sécurité | M | `DOCKER_HOST=tcp://docker:2375` sans TLS (`DOCKER_TLS_CERTDIR: ""`) | API Docker en clair, sans authentification, joignable depuis le pod | sans objet après #2 |
| 4 | 61-62 | Sécurité | **B** | `set -x` puis `docker login -p $HARBOR_PASSWORD` | Le mot de passe s'affiche dans le journal (la valeur ne vient pas d'une variable masquée) et dans `ps` | Pas de `set -x` dans un job à secrets ; mot de passe par l'entrée standard (`--password-stdin`) |
| 5 | (tout) | Fiabilité | M | Aucun `workflow:rules` ; `lint` en `only: branches, merge_requests`, `tests` en `rules` MR + branche | Deux pipelines par poussée dès qu'une MR est ouverte : double coût, statuts contradictoires | `workflow:rules` du standard (MR, branches sans MR ouverte) |
| 6 | 36-38, 91-92 | Maintenabilité | m | `only`/`except` mélangés avec `rules` dans le même fichier | `only`/`except` ne sont plus développés ; combinaisons difficiles à lire et à prévoir | `rules` partout |
| 7 | 4, 56, 72, 79, 87 | Sécurité | M | Images `latest` ou sans version, tirées de Docker Hub en direct (`python:3.13`, `docker:latest`, `aquasec/trivy:latest`, `zricethezav/gitleaks:latest`, `bitnami/kubectl:latest`) | Contenu qui change sans prévenir (cf. Trivy 0.69.4 compromise, CVE-2026-33634) ; quotas Docker Hub ; refus par Harbor/VAP ; catalogue gratuit Bitnami retiré | Images de Harbor, étiquette **et** empreinte (composants) |
| 8 | 63-64, 75, 90 | Fiabilité | M | Étiquette `latest` poussée et réutilisée par Trivy et le déploiement | On analyse, on déploie « ce qui est `latest` à ce moment-là » : peut-être pas l'image construite par ce pipeline | Publication par empreinte (`IMAGE_REF`), jamais de `latest` |
| 9 | 73, 80 | Sécurité | **B** | `allow_failure: true` sur Trivy et Gitleaks | Pipeline vert avec un secret commité ou une CVE critique corrigeable : analyse décorative | Analyses bloquantes ; exceptions tracées (`.trivyignore`, `.gitleaksignore`, normes §4) |
| 10 | 75 | Sécurité | M | Trivy analyse **après** la poussée | L'image vulnérable est déjà dans Harbor (et déployable) quand l'analyse échoue | Analyse de l'archive **avant** publication (`securite:trivy`) |
| 11 | 20-24 | Fiabilité | M | Cache global à clé fixe `cache` (`.venv`, `.cache`) pour tous les jobs et toutes les branches, en lecture-écriture | Une branche empoisonne le cache de `main` ; `.venv` d'une image Python réutilisé par une autre ; écritures concurrentes | Clé calculée sur `uv.lock`, cache `uv` seulement (pas `.venv`), écriture sur `main` (E23) |
| 12 | 46-49, 66-68 | Performance | m | Artefacts sans `expire_in` (`.pytest_cache/`, `htmlcov/`, `dist/` qui n'existe même pas) | Stockage qui grossit indéfiniment ; artefacts inutiles téléchargés par les jobs suivants | `expire_in`, seulement les rapports utiles (`reports:junit`) |
| 13 | 26-29 | Sécurité | M | `curl … \| sh` pour installer uv à **chaque** job (y compris dans `docker:latest`, où `apt-get` n'existe pas) | Code distant exécuté sans vérification ; job d'image cassé ; lenteur | Image uv épinglée par empreinte ; aucun téléchargement de code exécuté |
| 14 | 35 | Fiabilité | M | `ruff check . \|\| true` | Le lint ne peut jamais échouer : faux vert | Composant `qualite` (lint bloquant + rapport Code Quality) |
| 15 | 42 | Fiabilité | m | `tests` a `needs: [construire-image]` | Les tests attendent une construction d'image dont ils n'ont pas besoin, et ne tournent pas si elle échoue | Tests indépendants (`needs: []` ou rien) |
| 16 | 86, 93 | Sécurité | **B** | `deploy` : `needs: []` et `when: always` | Déploiement avant (et malgré) les tests et les analyses | Promotion par MR après signature (E17) ; jamais `when: always` sur un déploiement |
| 17 | 89, 91-92 | Sécurité | **B** | `KUBECONFIG_DEV` non protégée, utilisée sur toutes les branches (`except: tags`) | N'importe quelle branche (stagiaire, MR externe) modifie `mediagenda-dev` avec un kubeconfig longue durée | Agent GitLab (E18), branches protégées seulement, environnement `dev` |
| 18 | 90 | Exploitation | M | `kubectl set image` impératif sur le cluster | Le dépôt de déploiement ne dit plus ce qui tourne (dérive), contournement des MR | Promotion par MR dans `deploiement` (E17) |
| 19 | (tout) | Fiabilité | M | Aucun `tags:` sauf `construire-image` | Le runner `k8s-par1` ne prend pas de jobs sans étiquette (`run_untagged: false`) : jobs en attente (RB-190) | Composants (étiquette `k8s`) |
| 20 | 7 | Performance | m | `GIT_DEPTH: "0"` global | Clone complet pour chaque job | Profondeur par défaut ; historique seulement pour Gitleaks |
| 21 | 27 | Performance | m | `apt-get update && apt-get install` dans le `before_script` global | 30-60 s par job, dépend d'Internet | Image qui contient les outils |
| 22 | (tout) | Fiabilité | m | Aucun `interruptible` | Les pipelines dépassés continuent de consommer des runners | `interruptible: true` + `workflow:auto_cancel` |
| 23 | 34, 44 | Fiabilité | m | `uv sync` sans `--locked` | Dépendances résolues à la volée, différentes d'un job à l'autre | `uv sync --locked` |

**Demandes avant fusion** : #1 (rotation d'abord), #2, #4, #9, #16, #17. Version corrigée poussée sur
la branche `revue-lucas` de `formation/ci-labo` : composants `qualite`, `construction-image`, `securite`.
On en parle demain si tu veux : la plupart de ces points sont dans `docs/livraison/ci/normes-pipeline.md`.
