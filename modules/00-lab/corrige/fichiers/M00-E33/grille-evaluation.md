# Grille d'évaluation des ADR (M00-E33)

Note chaque critère de 0 à 2 (0 = absent, 1 = partiel, 2 = satisfaisant). Seuil : 14/20 par ADR, et aucun 0 sur les critères marqués ★.

| # | Critère | 0 | 1 | 2 |
|---|---|---|---|---|
| 1 ★ | **Contexte** compréhensible sans connaître le lab | Absent ou jargon interne | Présent mais suppose du contexte | Lisible par un nouvel arrivant dans un an |
| 2 ★ | **Question tranchée** explicite | Pas de question | Implicite | Une question claire, un périmètre |
| 3 | **Facteurs de décision** métier ET techniques | Aucun | Seulement techniques | Mélange métier (HDS, RPO/RTO, compétences, coût) et technique (RAM, débit, évolutivité) |
| 4 ★ | **Options réelles** (≥ 3) | Une seule option | Options « de paille » | Trois options crédibles, chacune défendable |
| 5 | **Pour/contre** par option | Absents | Déséquilibrés (l'option retenue n'a pas de « contre ») | Honnêtes et symétriques |
| 6 ★ | **Décision justifiée** par les facteurs | « Parce que » | Justification sans lien avec les facteurs | Chaque argument renvoie à un facteur |
| 7 ★ | **Conséquences négatives** assumées | Aucune | Minimisées | Listées franchement |
| 8 | **Actions induites** (et où elles seront traitées) | Aucune | Vagues | Concrètes, rattachées à un module/ticket |
| 9 | **Chiffres** (ADR-0002 : RPO, RTO, rétention, volumes ; ADR-0001 : ressources) | Aucun | Approximatifs sans méthode | Chiffrés et mesurables (comment on les mesure) |
| 10 | **Forme** : gabarit respecté, ≤ 2 pages, statut et date, liens | Hors gabarit | Partiel | Conforme |

Défauts fréquents qui coûtent des points :
- ADR écrit après coup comme une justification (aucune option écartée n'a d'avantage réel).
- Confusion entre décision et mode opératoire (des commandes dans l'ADR).
- Aucune date de révision ni condition de remise en cause.
- ADR-0002 : réplication présentée comme sauvegarde ; chiffrement sans gestion de clé ; « 3-2-1 respectée » alors qu'il n'existe qu'une copie hors site sur un seul disque.
