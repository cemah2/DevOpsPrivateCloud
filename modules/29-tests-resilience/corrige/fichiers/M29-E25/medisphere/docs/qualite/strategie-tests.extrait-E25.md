# Stratégie de tests — mise à jour de livraison (EXTRAIT M29-E25, PLAT-3025)

> `plateforme/medisphere` — `docs/qualite/strategie-tests.md` : modifications apportées à la version de M29-E12 ([fichier complet d'E12](../../../../M29-E12/medisphere/docs/qualite/strategie-tests.md)) pour qu'elle décrive ce qui **tourne réellement** à la livraison `resilience-v1`. Le reste est inchangé.

## En-tête

> Procédures : RB-290 (charge), RB-291 (Goss : essai retiré, fiche conservée pour l'historique), RB-292 (chaos, arrêt d'urgence), RB-293 (VMs de test orphelines, complété en E21), RB-294 (arrêter une expérience), RB-295 (non-régression de performance rouge), RB-296 (perte du primaire ou d'un nœud RabbitMQ), RB-297 (expérience qui ne s'arrête pas).

## §3 « Ce qui tourne quand » — lignes ajoutées ou corrigées

| Moment | Où | Tests | Durée cible | Bloquant |
|---|---|---|---|---|
| **Chaque MR** de `plateforme/politiques` | job `non-regression-plans` (M29-E19) | plan de référence dangereux **refusé** et plan sain accepté, avec les arguments du job de plan (`--namespace tofu`, `--data rego/donnees`, contexte `socle`) ; tout paquet de `rego/tofu` évalué | < 1 min | **oui** |
| Chaque nuit | `plateforme/resilience` (pipeline planifié) | **non-régression de performance** : `TestRun` k6-operator à 4 exécuteurs, comparaison à `charge/references/mediagenda-recette.json` lue dans Thanos (p95 +20 %, erreurs +0,5 point) | 15 min | ticket si rouge (RB-295) |
| Chaque nuit | `plateforme/tofu-modules` (pipeline planifié `nettoyage-terratest`) | **nettoyeur Terratest** en simulation : aucune VM `tt-*` de plus de 2 h dans 2290-2299 | 1 min | échec = courriel à la plateforme (RB-293) |
| En continu | `mon01` | ~~sondes Goss (essai)~~ : essai retiré (ADR-0290) | — | — |
| Chaque trimestre | recette | **journée de jeu** (`journees-de-jeu/<date>/`, rapport `docs/qualite/journees-de-jeu/`) ; actions suivies en issues `journee-de-jeu` de `plateforme/resilience` | ½ journée | actions closes avant la suivante |

## §5 « Ce qu'on ne teste pas » — ajouts

- **Les tests de contrat** entre MédiAgenda et MédiDoc (Pact ou équivalent) : pas encore ; repris par les finaux (`livraison-resilience-v1.md`).
- **La non-régression de MédiDoc** : seule MédiAgenda a une référence de performance.
- **La perte d'un nœud RabbitMQ par Chaos Mesh** : `messagerie` porte la production ; c'est un changement annoncé (CHG-3015, RB-296), jamais une expérience.

Prochaine revue de cette liste : <DATE + 3 mois>.
