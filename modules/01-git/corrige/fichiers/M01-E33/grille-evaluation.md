# Grille d'auto-évaluation — ADR-0010 (M01-E33)

Note ton ADR **avant** de lire l'exemple. Chaque critère : 0 (absent), 1 (partiel), 2 (solide).

| # | Critère | 0 | 1 | 2 |
|---|---|---|---|---|
| 1 | Le contexte se comprend sans connaître le lab (qui, quoi, pourquoi maintenant) | | | |
| 2 | Les facteurs de décision sont écrits **avant** les options et servent ensuite à trancher | | | |
| 3 | Au moins trois options réelles, chacune avec des « pour » honnêtes (pas d'homme de paille) | | | |
| 4 | Les limites de GitLab CE sont prises en compte (code owners, approbations, merge trains) | | | |
| 5 | La question des versions est traitée (semantic-release par composant, dépendances par version publiée) | | | |
| 6 | La question des droits d'accès (HDS, cloisonnement d'`infra`) est traitée | | | |
| 7 | Le coût CI (runner unique, pipelines ciblés) est chiffré ou au moins estimé | | | |
| 8 | Les conséquences négatives de l'option retenue sont écrites, avec les actions qui les compensent | | | |
| 9 | Une condition de révision de la décision est donnée (taille d'équipe, part de changements transverses…) | | | |
| 10 | L'ADR est cohérent avec PLAN.md §4.8 (ou propose explicitement de le changer) | | | |
| 11 | L'ADR est passé par une MR, avec au moins une discussion résolue, et le pipeline de qualité est vert | | | |
| 12 | Pas de commandes ni de procédure dans l'ADR (elles vont dans les runbooks et le CONTRIBUTING) | | | |

**Lecture** : 20 à 24 : prêt pour une revue d'architecture. 14 à 19 : reprends les critères à 0 ou 1. Moins de 14 : relis l'exemple de M00-E33 et le gabarit MADR, puis réécris.

Un ADR qui choisit le monodépôt peut obtenir 24/24 : ce qui est évalué, c'est la qualité du raisonnement et la cohérence avec les contraintes, pas la conclusion. Dans ce cas, il doit proposer la modification de PLAN.md §4.8 et dire comment il compense l'absence de *code owners* obligatoires en CE.
