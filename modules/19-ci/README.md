# Module 19 — Intégration continue

| | |
|---|---|
| **Bloc** | D — Livraison |
| **Niveau** | Cœur |
| **Profil de lab** | Socle v4 (dont `mon01`, créée ici) + `ceph-par1` + `k8s-par1` (travailleurs portés à 10 Go en E02) ; Jenkins puis SonarQube temporairement dans le cluster, jamais ensemble |
| **Prérequis** | Module 01 (GitLab, MR, gabarits CI), module 13 (Harbor, Cosign, Trivy, SBOM), module 17 (chart et `mediagenda/deploiement`) ; module 14 (administration Kubernetes) |
| **Durée indicative** | 85 à 105 heures (palier 1 : 16-20 h ; palier 2 : 28-34 h ; palier 3 : 22-27 h ; palier 4 : 12-15 h ; mini-projet : 8-12 h) |

## Contexte MédiSphère

Les pipelines de MédiSphère tournent tous sur un seul runner Docker (`runner02`) : file d'attente le matin, gabarits copiés-collés d'un projet à l'autre, constructions d'images qui se marchent dessus, et une mise en recette qui consiste encore à lancer `kubectl apply` depuis `adm01`. Claire Morel veut une **chaîne de livraison** digne de ce nom : des runners élastiques dans `k8s-par1`, un pipeline standard que chaque équipe adopte en une ligne, des analyses de sécurité qui bloquent vraiment, des images signées et promues par merge request. Julien Petit veut des pipelines rapides ; Sophie Laurent veut qu'aucun secret ne fuie et qu'aucun job ne tourne en privilégié ; Karim Benali a entendu parler de Jenkins et de SonarQube et veut une décision argumentée.

## Objectifs

À la fin de ce module, tu sais :
- exploiter GitLab CI en profondeur : `rules`, `needs`, `workflow`, pipelines enfants et multi-projets, artefacts, caches, environnements, rapports ;
- faire tourner les jobs dans Kubernetes (exécuteur `kubernetes`), les cloisonner, les dimensionner et les superviser ;
- construire des images dans le cluster sans privilège (BuildKit *rootless*) et sécuriser la chaîne (Semgrep, Gitleaks, Trivy, SBOM, signature, provenance) ;
- factoriser les pipelines en **composants CI/CD** versionnés et imposer un socle commun ;
- promouvoir une image par MR et déployer en dev avec l'agent GitLab pour Kubernetes ;
- comparer GitLab CI avec Jenkins, évaluer SonarQube, et trancher dans un ADR ;
- monter GitLab de version et diagnostiquer méthodiquement un pipeline bloqué, lent ou cassé.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M19-E01 | Test de positionnement : intégration continue | Q | ★★ | 1 |
| M19-E02 | Préparer `k8s-par1` pour la CI | LAB | ★★ | 1 |
| M19-E03 | `mon01` et Mailpit : la messagerie du lab | LAB | ★★ | 1 |
| M19-E04 | Un runner GitLab dans Kubernetes | LAB | ★★ | 1 |
| M19-E05 | Anatomie d'un job dans Kubernetes | LAB | ★★ | 1 |
| M19-E06 | Pipelines : stages, `needs`, `rules` et `workflow` | LAB | ★★ | 1 |
| M19-E07 | Variables, artefacts, caches et environnements | LAB | ★★ | 1 |
| M19-E08 | Construire des images dans le cluster : BuildKit *rootless* partagé | LAB | ★★★ | 1 |
| M19-E09 | Questions : le modèle d'exécution de GitLab CI | Q | ★★ | 1 |
| M19-E10 | Des gabarits aux composants CI/CD | LAB | ★★★ | 2 |
| M19-E11 | Le pipeline standard de MédiAgenda | LIBRE | ★★★ | 2 |
| M19-E12 | Pipelines enfants, multi-projets et déclencheurs | LAB | ★★ | 2 |
| M19-E13 | Pipelines de MR : rapports de tests et couverture | LAB | ★★ | 2 |
| M19-E14 | Services de job : une base PostgreSQL pour les tests d'intégration | LAB | ★★ | 2 |
| M19-E15 | Semgrep CE et Gitleaks dans le composant `securite` | LAB | ★★ | 2 |
| M19-E16 | SonarQube Community Build : installer et analyser | LAB | ★★★ | 2 |
| M19-E17 | Promouvoir une image par merge request | LAB | ★★★ | 2 |
| M19-E18 | Déployer en dev avec l'agent GitLab pour Kubernetes | LAB | ★★★ | 2 |
| M19-E19 | Jenkins dans Kubernetes : JCasC et agents en pods | LAB | ★★ | 2 |
| M19-E20 | Le même pipeline en Jenkinsfile | LAB | ★★★ | 2 |
| M19-E21 | Revue : le `.gitlab-ci.yml` du stagiaire | REV | ★★ | 2 |
| M19-E22 | Runbook : un pipeline reste en attente | RED | ★★ | 2 |
| M19-E23 | Accélérer un pipeline lent | LAB | ★★★ | 2 |
| M19-E24 | Cloisonner les runners : comptes, Pod Security, réseau, quotas | LAB | ★★★ | 3 |
| M19-E25 | Secrets en CI : variables protégées, `CI_JOB_TOKEN`, jetons d'identité | LAB | ★★★ | 3 |
| M19-E26 | Monter GitLab, les runners et l'agent en 19.5 | LAB | ★★★ | 3 |
| M19-E27 | Capacité et disponibilité des runners | LAB | ★★★ | 3 |
| M19-E28 | Indicateurs de livraison (DORA) | RED | ★★ | 3 |
| M19-E29 | Chaîne d'approvisionnement : SBOM, provenance, signature, vérification | LAB | ★★★ | 3 |
| M19-E30 | ADR : la chaîne de CI de MédiSphère | RED | ★★ | 3 |
| M19-E31 | Questions de production : intégration continue | Q | ★★★ | 3 |
| M19-E32 | Imposer le socle de sécurité à tous les projets | LIBRE | ★★★ | 3 |
| M19-E33 | Accueillir l'équipe MédiDoc dans la CI | LIBRE | ★★★ | 3 |
| M19-E34 | Un pipeline en temps limité | CHRONO | ★★★ | 3 |
| M19-E35 | Panne : les jobs restent en attente | BF | ★★ | 4 |
| M19-E36 | Panne : le job échoue avant le script | BF | ★★ | 4 |
| M19-E37 | Panne : la construction d'image échoue | BF | ★★★ | 4 |
| M19-E38 | Panne : le cache ne sert plus | BF | ★★ | 4 |
| M19-E39 | Panne : le déploiement en dev est refusé | BF | ★★★ | 4 |
| M19-E40 | Panne : un secret apparaît dans un journal de job | BF | ★★★ | 4 |
| M19-E41 | Panne : les pipelines ne se déclenchent plus | BF | ★★ | 4 |
| M19-E42 | Panne : le job est tué en cours de route | BF | ★★★ | 4 |
| M19-E43 | Astreinte : la chaîne de livraison en détresse | BF | ★★★★ | 4 |
| M19-E44 | Sous le capot : du `git push` au pod de job | LAB | ★★★★ | 4 |
| M19-E45 | Questions expert : intégration continue | Q | ★★★ | 4 |
| M19-E46 | Mini-projet : la chaîne de CI de MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 45 exercices + mini-projet · 9 break & fix · 4 questionnaires · 1 revue · 3 rédactions · 1 chronométré.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| `mon01` | VMID 1014, 10.10.20.19 (VLAN 20), état `socle` | Mailpit (SMTP 25, interface 8025), CNAME `smtp.par1.medisphere.internal` ; supervision hors cluster au M21 | E03 |
| Runner `k8s-par1` | espaces `gitlab-runner` (gestionnaire) et `ci-jobs` (jobs) | Exécuteur `kubernetes`, étiquettes `k8s` et `kubernetes` | E04 |
| `buildkitd` | espace `buildkit` | Démon BuildKit *rootless* partagé, TLS mutuel | E08 |
| Agent `k8s-par1` | espace `gitlab-agent` | Agent GitLab pour Kubernetes (*CI/CD workflow* vers `mediagenda-dev` et `wb-essais`) | E18 |
| Jenkins, SonarQube | espaces `jenkins`, `sonarqube` | Pratiqués puis **retirés** (ADR-0190) | E16, E19, E46 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.11. Versions : [`annexes/versions-bloc-DE.md`](../../annexes/versions-bloc-DE.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 19 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 19 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
