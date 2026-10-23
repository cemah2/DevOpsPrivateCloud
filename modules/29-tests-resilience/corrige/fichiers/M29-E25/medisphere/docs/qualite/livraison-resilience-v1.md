# Livraison « Résilience MédiSphère v1 » (`resilience-v1`)

| | |
|---|---|
| Ticket | PLAT-3025 (M29-E25) |
| Étiquette | `resilience-v1` sur `plateforme/medisphere` (<DATE>) |
| Contrôle | `lab/bin/check 29 25` entièrement vert le <DATE> |
| Décision d'architecture | ADR-0290 |

## 1. Ce qui est livré

| Étage | Quoi | Où | Quand ça tourne |
|---|---|---|---|
| Statique | kubeconform (+ schémas `schemas-crd`), conftest (Rego v1), Kyverno CLI | composant `validation@vX.Y.Z` de `plateforme/ci-templates`, consommé par `plateforme/k8s`, `gitops`, `infra`, `ansible` | chaque MR, `main` |
| Politiques | `rego/tofu/`, `rego/kubernetes/`, tests `opa test`, plans de référence (`tests/plans/`) | `plateforme/politiques` | chaque MR |
| Infrastructure | Testinfra (`tests/infra/`) | `plateforme/ansible` | MR des rôles + chaque nuit sur tout le socle |
| Modules OpenTofu | Terratest (`vm-debian/test/`), nettoyeur (`outils/nettoyer-terratest.sh`) | `plateforme/tofu-modules` | Terratest à la demande ; nettoyeur chaque nuit (simulation) |
| Charge | k6 1.8, k6-operator 1.7 (espace `k6`), référence `charge/references/`, tableau `m29-charge-k6` | `plateforme/resilience` | non-régression chaque nuit sur la recette |
| Chaos | Chaos Mesh 2.8 (filtre d'espaces : `mediagenda-recette`, `medinotif-recette`, `wb-essais`), bibliothèque `chaos/`, journées de jeu `journees-de-jeu/` | `plateforme/resilience`, `plateforme/gitops` | à la main, annoncé (exception ADR-0290) |
| Documentation | `strategie-tests.md`, ADR-0290, RB-290 à RB-297, rapport des données, post-mortem INC-5623, `sous-le-capot-chaos-mesh.md`, journées de jeu | `docs/qualite/` | — |

## 2. Ce que les finaux trouvent

- **F1 (jour 0)** : la pyramide de validation s'applique à tout dépôt neuf : inclure `validation@vX.Y.Z` dès le premier commit ; un plan OpenTofu qui touche le socle passe par conftest.
- **F2 (jour 1)** : Testinfra est la preuve d'un rôle Ansible ; la suite nocturne doit rester verte (un rouge = une dérive, RB du M29-E22).
- **F3 (astreinte)** : RB-294 et RB-297 pour toute expérience qui déborde ; INC-5623 comme exemple de cascade dépendance → sonde.
- **F4 (changements)** : la non-régression nocturne bloque une version plus lente de 20 % ; une référence ne se change que par MR approuvée (RB-295) ; une perte de nœud RabbitMQ est un **changement annoncé**, jamais une expérience (CHG-3015).
- **F5 (PRA)** : bascule PostgreSQL mesurée (≈ 20 s d'erreurs subies, 4 s voulues) ; base de chiffres pour les objectifs de reprise.
- **F6 (sécurité)** : le `chaos-daemon` est le composant le plus privilégié après le plan de contrôle : exception PSA, politique réseau du gRPC, revue annuelle.
- **F7 (capstone)** : une journée de jeu complète (préparation, jeu, rapport, actions closes) fait partie de la recette finale.

**Jamais en production** : aucune expérience de chaos (le filtre d'espaces l'empêche) ; aucun test de charge sur `mediagenda-prod` ; aucune VM de Terratest hors 2290-2299.

## 3. Ce qui reste à traiter

| Sujet | Pourquoi pas maintenant | Où |
|---|---|---|
| Chaos en production | conditions non remplies (observabilité par utilisateur, budget d'erreur suivi, rayon d'action maîtrisé, accord de la direction et de la RSSI) | F7 ou après |
| Tests de **contrat** MédiAgenda ↔ MédiDoc (consommateur-producteur) | l'appel existe depuis M23 mais n'a ni schéma versionné ni test côté producteur | F7 (équipes MédiAgenda et MédiDoc) |
| Non-régression de MédiDoc et de MédiNotif | une seule référence (MédiAgenda) | après F4 |
| `/pret` sans dépendance au cache | correctif proposé (DEV-3013), déploiement par l'équipe MédiAgenda | suivi d'INC-5623 |
| Alertes de recette (latence, file, pods prêts) | ouvertes par la journée de jeu, fermées pour la latence et les pods ; file en cours | `plateforme/resilience` (issues `journee-de-jeu`) |

## 4. Démonstrations répétées pour la revue

| Démonstration | Durée répétée | Preuve |
|---|---|---|
| Sophie : plan dangereux refusé par la CI de `plateforme/infra` ; expérience vers `mediagenda-prod` sans effet | 4 min | MR de démonstration fermée, statut « no pod is selected » |
| Karim : MR cassée (CRD) arrêtée par kubeconform au premier étage | 3 min | pipeline de la MR |
| Julien : résultat de la non-régression de la nuit, écart à la référence | 2 min | artefact `resultat.json`, tableau `m29-charge-k6` |
| Nadia : une action de journée de jeu tirée au hasard, close avec preuve | 2 min | issue fermée + lien de la MR ou de l'alerte |
