# Module 29 — Tests et résilience

| | |
|---|---|
| **Bloc** | G — Services de plateforme |
| **Niveau** | Secondaire |
| **Profil de lab** | Socle v5 + `ceph-par1` + `k8s-par1` (≈ 111 Go) ; VMs de Terratest (2290-2299, 1 Go chacune, détruites par le test) le temps de E08 |
| **Prérequis** | Module 28 (`plateforme-dev-v1` : KEDA, HPA, locataires) ; module 27 (RabbitMQ, CNPG approfondi) ; module 21 (SLO, Prometheus) ; module 20 (Argo CD) ; module 19 (composants CI/CD) ; module 26 (politiques, PSA, Falco) ; modules 04 et 05 (rôles Ansible, modules OpenTofu) |
| **Durée indicative** | 40 à 50 heures (palier 1 : 8-10 h ; palier 2 : 12-15 h ; palier 3 : 10-13 h ; palier 4 : 6-8 h ; mini-projet : 4-6 h) |

## Contexte MédiSphère

La plateforme tient, mais personne ne sait jusqu'où. Les rôles Ansible sont « testés » par le fait qu'ils passent, les modules OpenTofu par le fait que personne ne s'est plaint, et la seule épreuve de charge a été la campagne de vaccination de l'an dernier, qui a mis MédiAgenda à genoux un lundi matin. Avant l'audit et la mise en production générale, Claire Morel veut trois choses : des tests automatiques à chaque MR (de la syntaxe à l'infrastructure réelle), la preuve chiffrée que MédiAgenda tient la charge attendue avec ses SLO, et des pannes **provoquées exprès**, en heures ouvrées, plutôt que subies à 3 h du matin.

## Objectifs

À la fin de ce module, tu sais :
- valider statiquement des manifestes et des plans : **kubeconform** avec les schémas des CRD, **conftest/OPA** en Rego v1 ;
- tester une infrastructure réelle : **Testinfra** (et **Goss**) pour les VMs, **Terratest** pour un module OpenTofu ;
- mesurer la tenue en charge avec **k6** et **k6-operator**, avec des seuils alignés sur les SLO ;
- conduire des expériences de **chaos** avec Chaos Mesh, avec des garde-fous, et une journée de jeu documentée ; situer LitmusChaos ;
- organiser une stratégie de tests en CI (pyramide, coûts, ce qu'on ne teste pas) ;
- diagnostiquer une CI trop permissive, une expérience qui ne s'arrête pas, des ressources de test orphelines.

## Carte des exercices

| ID | Titre | Type | Diff. | Palier |
|---|---|---|---|---|
| M29-E01 | Test de positionnement : tests et résilience | Q | ★★ | 1 |
| M29-E02 | kubeconform : valider les manifestes avec leurs CRD | LAB | ★★ | 1 |
| M29-E03 | conftest et Rego v1 : des règles sur les plans OpenTofu | LAB | ★★ | 1 |
| M29-E04 | Testinfra : tester les rôles Ansible sur les VMs | LAB | ★★ | 1 |
| M29-E05 | k6 : premier test de charge de MédiAgenda | LAB | ★★ | 1 |
| M29-E06 | k6 en profondeur : scénarios, seuils des SLO, métriques | LAB | ★★★ | 2 |
| M29-E07 | Goss : la comparaison et les sondes de santé | LAB | ★★ | 2 |
| M29-E08 | Terratest : tester le module `vm-debian` | LAB | ★★★ | 2 |
| M29-E09 | Chaos Mesh : installer avec des garde-fous | LAB | ★★★ | 2 |
| M29-E10 | Le composant `validation` : une pyramide de tests en CI | LIBRE | ★★★ | 2 |
| M29-E11 | Revue : les politiques Rego et le test k6 du stagiaire | REV | ★★ | 2 |
| M29-E12 | Stratégie de tests de la plateforme | RED | ★★ | 2 |
| M29-E13 | Expériences de chaos : réseau, ressources, horaires, enchaînements | LAB | ★★★ | 3 |
| M29-E14 | k6-operator : tests distribués et non-régression de performance | LAB | ★★★ | 3 |
| M29-E15 | Résilience des données sous charge : primaire et nœud RabbitMQ perdus | LAB | ★★★ | 3 |
| M29-E16 | Journée de jeu : hypothèse, mesure, rapport | LIBRE | ★★★ | 3 |
| M29-E17 | ADR : outillage de tests et de chaos | RED | ★★ | 3 |
| M29-E18 | Questions de production : tests et résilience | Q | ★★★ | 3 |
| M29-E19 | Panne : un plan dangereux passe la CI | BF | ★★ | 4 |
| M29-E20 | Panne : une expérience de chaos ne s'arrête plus | BF | ★★★ | 4 |
| M29-E21 | Panne : Terratest laisse des VMs derrière lui | BF | ★★ | 4 |
| M29-E22 | Panne : les tests d'infrastructure sont rouges | BF | ★★ | 4 |
| M29-E23 | Astreinte : la journée de jeu réveille une vraie faiblesse | BF | ★★★★ | 4 |
| M29-E24 | Sous le capot : comment Chaos Mesh injecte une panne | LAB | ★★★★ | 4 |
| M29-E25 | Mini-projet : tests et résilience de MédiSphère v1 | LIBRE | ★★★ | 5 |

**Répartition** : 24 exercices + mini-projet · 5 break & fix · 2 questionnaires · 1 revue · 2 rédactions.

## Hôtes et composants créés dans ce module

| Élément | Où | Rôle | Exercice |
|---|---|---|---|
| Composant CI/CD `validation` | `plateforme/ci-templates` | kubeconform, conftest, Testinfra dans les pipelines | E10 |
| Politiques Rego | `plateforme/politiques/rego/` | Règles sur les plans et les manifestes | E03 |
| k6-operator 1.7 | espace `k6` | Tests de charge dans le cluster | E14 |
| Chaos Mesh 2.8 | espace `chaos-mesh`, expériences dans `chaos-experiences` (projet `plateforme/resilience`) | Ingénierie du chaos, espaces de recette seulement | E09 |
| VMs de Terratest | 2290-2299, sous-pool Proxmox `lab/terratest`, `vsandbox` (adresse allouée par NetBox) | Créées et détruites par les tests | E08 |

Détails figés : [`PLAN.md`](../../PLAN.md) §4.13. Versions : [`annexes/versions-bloc-G.md`](../../annexes/versions-bloc-G.md). Fiche : [`annexes/decouverte/litmuschaos.md`](../../annexes/decouverte/litmuschaos.md).

## Fichiers

- Énoncé : [`enonce/`](enonce/) — commence par [`00-introduction.md`](enonce/00-introduction.md).
- Vérifications : `lab/bin/check 29 <XX>`, depuis `adm01`.
- Pannes : `lab/bin/break 29 <XX>`, depuis `adm01`.
- ⚠️ Corrigé : [`corrige/`](corrige/) — à n'ouvrir qu'après avoir cherché.
