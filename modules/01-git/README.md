# Module 01 — Git et workflow professionnel

| | |
|---|---|
| **Bloc** | A — Fondations automatisées |
| **Niveau** | Cœur |
| **Profil de lab** | Socle (+ `git01` et `runner01`, permanents, créés dans ce module) |
| **Prérequis** | Module 00 (socle v0 livré, étiquette `socle-v0`) |
| **Durée indicative** | 35 à 45 heures |

## Contexte MédiSphère

Le socle v0 est livré, mais tout ce qui le décrit vit dans un dépôt Git local sur `adm01`, connu d'une seule personne. Avant d'écrire la moindre ligne de script, de rôle Ansible ou de code OpenTofu, Claire Morel veut une **forge** : un GitLab auto-hébergé sur le socle (les données de santé et le code qui les protège ne partent pas chez un SaaS), un workflow de revue commun à toute l'équipe, des garde-fous automatiques (format des commits, secrets, qualité) et des versions publiées sans intervention manuelle. Karim Benali en profite pour vérifier que tu maîtrises Git au-delà de `add`/`commit`/`push` : historique, rebase, récupération, bisect. Sophie Laurent, elle, a une exigence : **aucun secret dans un dépôt, jamais**.

## Objectifs

À la fin de ce module, tu sais :
- expliquer et manipuler le modèle objet de Git (objets, références, reflog, packfiles) ;
- réécrire, nettoyer et réparer un historique sans perdre de travail (rebase interactif, reset, revert, reflog, cherry-pick, worktrees, bisect) ;
- installer, administrer, sauvegarder, mettre à jour et durcir GitLab CE ;
- organiser le travail d'une équipe : merge requests, revue, branches protégées, conventions de commit, modèle de MR, CONTRIBUTING ;
- automatiser la qualité avant et après le push : pre-commit, commitlint, Gitleaks, hooks côté serveur, pipeline obligatoire ;
- publier des versions automatiquement avec semantic-release ;
- diagnostiquer les pannes courantes d'une forge (push refusé, 502, runner muet, release en échec, dépôt corrompu).

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M01-E01 | Test de positionnement Git | Q | ★★ | 1 |
| M01-E02 | Le modèle objet de Git : blobs, arbres, commits, références | LAB | ★ | 1 |
| M01-E03 | Configurer Git sur `adm01` (identité, `main`, alias, signature SSH) | LAB | ★ | 1 |
| M01-E04 | Installer GitLab CE sur `git01` avec une PKI provisoire | LAB | ★★ | 1 |
| M01-E05 | Premiers pas d'administration GitLab : comptes, groupes, inscriptions | LAB | ★ | 1 |
| M01-E06 | Migrer `~/medisphere` vers GitLab sans rien perdre | LAB | ★ | 1 |
| M01-E07 | Lire et construire un historique : branches, fusions, graphe | LAB | ★ | 1 |
| M01-E08 | Annuler proprement : `restore`, `reset`, `revert`, `reflog` | LAB | ★★ | 1 |
| M01-E09 | Questions : modèles de branches et choix pour l'équipe Plateforme | Q | ★★ | 1 |
| M01-E10 | Le cycle d'une merge request : branche, revue, suggestions, fusion | LAB | ★ | 2 |
| M01-E11 | Protéger `main` : branches protégées et règles de fusion (limites de CE) | LAB | ★★ | 2 |
| M01-E12 | Rebase interactif : préparer une branche pour la revue | LAB | ★★ | 2 |
| M01-E13 | Résoudre des conflits de fusion et de rebase (`rerere`, outils) | LAB | ★★ | 2 |
| M01-E14 | Conventional Commits et commitlint en local | LAB | ★★ | 2 |
| M01-E15 | pre-commit : des contrôles versionnés avec le dépôt | LAB | ★★ | 2 |
| M01-E16 | Gitleaks : arrêter un secret avant qu'il parte | LAB | ★★ | 2 |
| M01-E17 | Un secret a été poussé : purge, rotation, communication | LAB | ★★★ | 2 |
| M01-E18 | Worktrees : un correctif urgent sans abandonner son travail | LAB | ★★ | 2 |
| M01-E19 | Cherry-pick et rétroportage vers une branche de maintenance | LAB | ★★ | 2 |
| M01-E20 | Jetons et clés : personnels, de projet, de déploiement | LAB | ★★ | 2 |
| M01-E21 | Revue de la merge request d'un stagiaire | REV | ★★ | 2 |
| M01-E22 | Rédiger le CONTRIBUTING et le modèle de MR de l'équipe | RED | ★★ | 2 |
| M01-E23 | Installer GitLab Runner sur `runner01` | LAB | ★★ | 3 |
| M01-E24 | Pipeline de qualité obligatoire avant fusion | LAB | ★★ | 3 |
| M01-E25 | semantic-release : versions, changelog et releases automatiques | LAB | ★★★ | 3 |
| M01-E26 | Hooks côté serveur : imposer les règles même sans pre-commit | LAB | ★★★ | 3 |
| M01-E27 | Signer commits et étiquettes, vérifier dans GitLab | LAB | ★★ | 3 |
| M01-E28 | Sauvegarder et restaurer GitLab | LAB | ★★★ | 3 |
| M01-E29 | Mettre à jour GitLab en suivant le chemin de montée de version | LAB | ★★ | 3 |
| M01-E30 | Superviser GitLab : sondes de santé, services, journaux, métriques | LAB | ★★ | 3 |
| M01-E31 | Durcir GitLab | LIBRE | ★★★ | 3 |
| M01-E32 | Revue de la configuration CI et pre-commit d'un projet | REV | ★★ | 3 |
| M01-E33 | ADR : monodépôt ou multidépôts pour la plateforme | RED | ★★ | 3 |
| M01-E34 | Questions de production : Git et GitLab à l'échelle | Q | ★★★ | 3 |
| M01-E35 | Workflow complet en temps limité | CHRONO | ★★★ | 3 |
| M01-E36 | Panne : `git push` est refusé | BF | ★★ | 4 |
| M01-E37 | Panne : GitLab répond « 502 » | BF | ★★★ | 4 |
| M01-E38 | Panne : le runner ne prend plus les jobs | BF | ★★ | 4 |
| M01-E39 | Panne : la release automatique échoue | BF | ★★★ | 4 |
| M01-E40 | Panne : clone et push en SSH impossibles | BF | ★★ | 4 |
| M01-E41 | Panne : le dépôt local est corrompu | BF | ★★★ | 4 |
| M01-E42 | Panne : « tout mon travail a disparu » | BF | ★★ | 4 |
| M01-E43 | Astreinte : la forge en difficulté | BF | ★★★★ | 4 |
| M01-E44 | Trouver le commit fautif avec `git bisect run` | LAB | ★★★ | 4 |
| M01-E45 | Sous le capot : packfiles, maintenance et gros dépôts | LAB | ★★★ | 4 |
| M01-E46 | Questions expert : les entrailles de Git | Q | ★★★ | 4 |
| M01-E47 | Mini-projet : la forge MédiSphère | LIBRE | ★★★ | 5 |

**Répartition** : 46 exercices + mini-projet · 8 break & fix · 4 questionnaires · 2 revues · 2 rédactions · 1 chronométré.

## Hôtes créés dans ce module

| Hôte | VMID | Adresse | Rôle | Exercice |
|---|---|---|---|---|
| `git01` | 1004 | 10.10.20.12 (VLAN 20 INFRA) | GitLab CE (4 vCPU, 8 Go) | E04 |
| `runner01` | 1007 | 10.10.20.15 (VLAN 20 INFRA) | GitLab Runner, exécuteur `shell` | E23 |

VMs jetables du module : 2010-2019 (pool `lab`, VNet `vsandbox`).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 01 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 01 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
