# ADR-0010 — Organiser le code de la plateforme en dépôts par composant, avec gabarits CI partagés

- Statut : accepté
- Date : AAAA-MM-JJ
- Décideurs : Claire Morel (responsable infrastructure), <apprenant>
- Consultés : Karim Benali (relecture MR), Sophie Laurent (droits d'accès, HDS), Julien Petit (consommateur des gabarits)

## Contexte et problème

Les modules 02 à 06 vont créer le code de la plateforme : scripts et CLI (`outils`), images Packer (`images`), rôles et playbooks Ansible (`ansible`), modules OpenTofu (`tofu-modules`) et leur assemblage (`infra`), à côté de la documentation (`medisphere`) et des gabarits CI (`ci-templates`). Ils ont des cycles de vie différents (un module OpenTofu se versionne et se consomme ; l'infrastructure s'applique), des publics différents et des niveaux de risque différents (une MR sur `infra` peut détruire des VMs). Il faut décider maintenant si ce code vit dans un seul dépôt ou dans plusieurs, avant que les habitudes ne décident à notre place. La forge est GitLab CE sur une VM de 8 Go, avec un runner shell unique.

## Facteurs de décision

- **Sécurité et HDS** : pouvoir donner l'accès en écriture à `ansible` sans le donner à `infra` ; tracer qui peut modifier ce qui touche la production.
- **Versions** : chaque composant consommé par un autre (modules OpenTofu, rôles, gabarits CI) doit avoir des versions publiées et figées (semantic-release, M01-E25).
- **Limites de CE** : pas de *code owners* obligatoires, pas d'approbations obligatoires, pas de *merge trains* : on ne peut pas imposer « Sophie relit tout ce qui touche `infra/` » dans un monodépôt.
- **Coût de la CI** : un runner shell, 2 vCPU ; un pipeline ne doit faire que le travail utile.
- **Changements transverses** : un changement qui touche un module OpenTofu et son utilisation doit rester faisable sans acrobaties.
- **Compétences et charge** : une équipe de cinq personnes, pas d'outillage de monodépôt (Bazel, Nx…).

## Options envisagées

1. Monodépôt `plateforme/plateforme` (un dossier par composant).
2. Multidépôts : un projet GitLab par composant, gabarits CI partagés par `include: project`.
3. Hybride : un dépôt « code » (outils, images, ansible, tofu-modules) et un dépôt « déploiement » (`infra`), plus la documentation.

## Décision

Option retenue : **2, multidépôts par composant**, parce qu'elle est la seule qui permette, avec GitLab CE, des droits d'écriture et des règles de fusion différents par composant (facteur sécurité/HDS), et un versionnage indépendant de chaque composant consommé (facteur versions). Les inconvénients sont compensés par les gabarits partagés (`plateforme/ci-templates`, M01-E24/E25) et les conventions communes (CONTRIBUTING, Conventional Commits, pre-commit de référence).

### Conséquences

- Positives : droits par projet (Maintainers d'`infra` restreints) ; versions et notes de version par composant ; pipelines courts et ciblés ; un composant peut être archivé ou réécrit sans toucher aux autres ; clones légers.
- Négatives : un changement transverse demande plusieurs MR coordonnées et une publication dans l'ordre (module OpenTofu publié, puis montée de version dans `infra`) ; les conventions peuvent diverger d'un projet à l'autre ; la recherche de code est dispersée ; les mises à jour de dépendances se font projet par projet.
- Actions induites :
  - gabarits CI uniques, consommés par `ref: v1` (fait, M01-E24/E25) ; un projet `plateforme/*` sans `include` de `ci-templates` est une anomalie (contrôle du mini-projet M01-E47) ;
  - modèle de projet (CONTRIBUTING, modèle de MR, pre-commit, commitlint, `.releaserc.json`) à copier à la création de chaque projet, puis gabarit de projet GitLab (*custom project template*, à vérifier en CE) ;
  - dépendances entre composants toujours **par version publiée** (module OpenTofu `?ref=vX.Y.Z` au M05, collection/rôle versionné au M04), jamais par branche ;
  - Renovate (M13) pour proposer les montées de version entre projets ;
  - revue de cette décision si l'équipe dépasse ~15 personnes ou si les changements transverses deviennent la majorité des MR.

## Analyse des options

### 1. Monodépôt
- Pour : changements atomiques transverses (une MR, un commit) ; une seule configuration de qualité ; recherche et refactorisation globales faciles ; visibilité totale pour toute l'équipe.
- Contre : droits d'écriture tout ou rien en CE (pas de *code owners* obligatoires) — contraire au besoin de cloisonnement d'`infra` ; versionnage par composant difficile avec semantic-release (une seule suite d'étiquettes ; il faudrait des outils de type *multi-semantic-release* et des étiquettes préfixées) ; chaque pipeline doit calculer ce qui a changé (`rules: changes`), fragile, sinon tout est retesté sur un runner unique ; historique bruyant ; clone de plus en plus gros (images, artefacts tentants).

### 2. Multidépôts par composant
- Pour : droits, protections, règles de fusion et visibilité par projet ; versions et notes indépendantes ; pipelines spécifiques et courts ; responsabilité claire par composant.
- Contre : coordination des changements transverses ; risque de divergence des conventions (compensé par `ci-templates` et le modèle de projet) ; plus de projets à administrer (jetons de bot, variables, protections) — à automatiser (API, M02 ; OpenTofu provider GitLab possible plus tard).

### 3. Hybride (code / déploiement)
- Pour : sépare bien le « quoi » (code réutilisable) du « où » (infrastructure appliquée), point le plus sensible ; moins de projets.
- Contre : à l'intérieur du dépôt « code », mêmes défauts que le monodépôt pour les versions (rôles Ansible, modules OpenTofu et images n'ont pas le même rythme) ; découpage arbitraire qu'il faudra probablement refaire.

## Liens

- PLAT-260 ; PLAN.md §4.8 (projets GitLab du bloc A) ; M01-E24 et M01-E25 (gabarits, versions) ; M01-E26 (hooks serveur, périmètre `plateforme/`).
- ADR-0011 (à venir) : stratégie de versionnage des modules OpenTofu (M05).
