# ADR-0340 — Avenir de Legacy-RDV

- Statut : accepté le <DATE> (Claire Morel, Sophie Laurent, Julien Petit, Karim Benali)
- Contexte : F4 (CHG-3410 à CHG-3414)

## Contexte
Legacy-RDV (PHP, 2014, écrit par InfoGér) tourne depuis CHG-3413 dans `k8s-par1` (`legacy-rdv-prod`) : deux réplicas, MariaDB 11.8 par mariadb-operator, pièces jointes sur CephFS, sauvegardes, image signée. Quarante cabinets l'utilisent ; MédiAgenda couvre déjà la prise de rendez-vous en ligne pour les autres clients. Dette restante : pas de tests, pas de migrations versionnées, code sans auteur, modèle de données sans fuseau, sessions maison, aucune authentification des cabinets (héritage).

## Options
| Critère | A. Maintien en l'état sur Kubernetes | B. Migration des cabinets vers MédiAgenda puis arrêt | C. Réécriture de Legacy-RDV |
|---|---|---|---|
| Sécurité / HDS | moyen : correctifs de l'image (Renovate) mais code non maintenu ; pas d'authentification | bon : application maintenue, SSO, traces | bon à terme, risque pendant la réécriture |
| Coût | faible (exploitation) | moyen : import des données, accompagnement de 40 cabinets | élevé : une équipe pendant 2 à 3 trimestres |
| Risque | dette qui grandit ; compétence PHP rare dans l'équipe | conduite du changement chez les cabinets | double run long, fonctionnalités divergentes |
| Données | inchangées | import des rendez-vous à venir et des pièces jointes (dates sans fuseau à convertir) | migration de schéma |
| Attente des cabinets | aucune | formation, nouvelle interface | aucune visible |

## Décision
**B**, avec **A** comme état transitoire borné : Legacy-RDV reste en production sur Kubernetes au plus 12 mois, en maintenance de sécurité seulement (aucune évolution fonctionnelle) ; l'équipe MédiAgenda (Julien Petit) prépare l'import des rendez-vous à venir et des pièces jointes et l'accueil des cabinets par vagues ; arrêt de Legacy-RDV quand le dernier cabinet est migré, par CHG-34xx et RB-347 (pièces jointes et base effacées après sauvegarde finale protégée).

## Conséquences
- Gel fonctionnel de `legacy/legacy-rdv` (seulement correctifs de sécurité et montées de l'image de base, par Renovate).
- Indicateur suivi : nombre de cabinets encore sur Legacy-RDV (sonde : rendez-vous créés par semaine, `pret.php`).
- Revue de cette décision : dans 6 mois (<DATE>), ou plus tôt si une faille non corrigeable est trouvée dans le code.
