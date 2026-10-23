# Processus de changement de MédiSphère

| | |
|---|---|
| Propriétaire | Claire Morel (responsable infrastructure) |
| Rédaction | équipe Plateforme (F4-S01) |
| Relecture | Karim Benali, Nadia Roussel, Julien Petit, Sophie Laurent |
| Révision | à chaque revue de trimestre (`revue-trimestre.md`) |

> « Aucun changement sans fiche, sans mesure et sans retour arrière. Et les cabinets ne doivent rien voir. » — Claire Morel

## 1. Ce qu'est un changement

Toute action qui modifie la production ou ce dont elle dépend : version d'un composant, configuration d'un service partagé (Ceph, réseau, cluster, identité, coffre), données de production, matériel. Ne sont **pas** des changements : une livraison applicative par le chemin normal (MR → CI → promotion → Argo CD, M19-M20), qui a ses propres garde-fous ; une opération d'exploitation décrite par un runbook sans effet sur le service (lecture, sauvegarde, rotation automatique).

## 2. Catégories

| Catégorie | Définition | Approbation | Fiche | Exemples chez MédiSphère |
|---|---|---|---|---|
| **Standard** (pré-approuvé) | Changement répété, à risque faible, décrit par un runbook éprouvé et dont la mesure passée est connue | Pré-approuvé une fois par Claire Morel ; l'exécutant l'inscrit au calendrier | Fiche courte (en-tête + journal + mesure) | correctif Kubernetes dans la même mineure (RB-142), mise à jour d'images Kolla dans une série (RB-101), corrective Ceph sans avis critique (RB-082), rotation de certificats |
| **Normal** | Tout le reste : nouvelle mineure, changement d'architecture, migration, première exécution d'un runbook | Claire Morel ; + Sophie Laurent si la sécurité ou les données de santé sont en jeu ; + Julien Petit ou Nadia Roussel si un service applicatif est touché | Fiche complète (modèle), relue par MR | montée de Kubernetes (CHG-3404), Ceph (CHG-3407), OpenStack (CHG-3408), migration VMware (CHG-3410), bascule de Legacy-RDV (CHG-3413) |
| **Urgent** | Correctif qui ne peut pas attendre la fenêtre suivante (faille exploitée, incident en cours) | Claire Morel (ou son suppléant) par écrit, même bref ; Sophie Laurent si sécurité | Fiche rédigée **après** dans les 48 h, revue obligatoire | correctif de sécurité critique, réparation d'un incident (INC-60xx) |

Un changement standard qui dépasse son objectif de mesure ou échoue repasse en **normal** jusqu'à la revue suivante.

## 3. La fiche CHG

Modèle : [`fiches/modele.md`](fiches/modele.md). Une fiche par changement, nommée `fiches/CHG-34xx-<sujet>.md`, ouverte par MR dans `plateforme/medisphere` **avant** la fenêtre et complétée après. L'en-tête YAML (catégorie, statut, décision, fenêtre, mesure) est lu par les outils : ne pas renommer ses clés.

Contenu obligatoire : risque, impact, fenêtre, préparation, étapes, critères de go/no-go et d'abandon, **retour arrière testé** (ou limite écrite), communication, **mesure de l'interruption** avant / pendant / après, journal, clôture.

## 4. Cycle de vie

1. **Demande** : ticket (`CHG-34xx`), fiche en brouillon par MR.
2. **Évaluation** : risque, impact, dépendances, matrice de compatibilité si c'est une montée (`matrices/`).
3. **Approbation** : MR approuvée par les personnes du §2 ; statut `approuve`.
4. **Préparation** : répétition, sauvegardes vérifiées, MR techniques prêtes, sonde prête, communication J-2.
5. **Go/no-go** : juste avant la fenêtre, 10 minutes, en présence de l'exécutant et d'un relecteur. Critères de la fiche §7. La décision et l'heure sont écrites (`decision: go|no-go`). Un **no-go est un résultat normal**, pas un échec : la fiche dit ce qui manque et quand on réévalue.
6. **Exécution** : étapes dans l'ordre, journal horodaté, un seul changement normal à la fois sur un même domaine (cluster, Ceph, OpenStack, réseau).
7. **Retour arrière** si un critère d'abandon est atteint : on n'improvise pas, on suit la fiche.
8. **Clôture** : mesure relevée et reportée dans l'en-tête, statut final, communication de fin.
9. **Revue après mise en œuvre** : dans les 5 jours ouvrés pour un normal ou un urgent ; tous les changements du trimestre dans `revue-trimestre.md`.

## 5. Fenêtres et gel

- **Fenêtres normales** : mardi et jeudi, 20 h-23 h (faible activité des cabinets) ; samedi 8 h-14 h pour les changements longs (OpenStack, migration).
- **Gel** (aucun changement normal ; urgents seulement) :
  - 48 h après la bascule de Legacy-RDV (CHG-3413) : la fenêtre de retour arrière doit rester propre ;
  - du 18 décembre au 4 janvier (congés, astreinte réduite) ;
  - pendant une campagne annoncée par les équipes produit (vaccination, M29) ;
  - pendant un incident de gravité 1 ou 2 en cours (F3).
- Deux changements normaux ne partagent jamais une fenêtre s'ils touchent un même domaine ; la sonde doit pouvoir attribuer une interruption à **un** changement.

## 6. Mesure de l'interruption

La **sonde de continuité** (F4-S02, [`sonde-continuite.md`](sonde-continuite.md), RB-340) tourne pendant toute fenêtre : charge k6 constante, sondes blackbox de `mon01`, tableau Grafana « Changement en cours ». Chaque fiche note la mesure **avant** (ligne de base de 30 min), **pendant** (la fenêtre) et **après** (30 min). L'objectif (`mesure-objectif-s`) est fixé **avant** le go ; il ne se corrige jamais après coup. Par défaut : 0 erreur 5xx vue par les utilisateurs de production, ≤ 30 s d'erreur cumulées sur la fenêtre.

## 7. Calendrier du trimestre (final F4)

Contrat d'InfoGér : fin dans six semaines. Ordre imposé par les dépendances : le processus et la sonde d'abord, les montées ensuite (la plateforme doit être à jour avant d'y accueillir Legacy-RDV), la migration enfin.

| Semaine | Changement | Catégorie | Fenêtre | Domaine | Dépend de |
|---|---|---|---|---|---|
| S1 | Processus (ce document), sonde de continuité (CHG-3402) | standard | heures ouvrées | observabilité | — |
| S1 | CHG-3403 — go/no-go de la mineure suivante de Kubernetes | normal (décision) | revue jeudi | cluster | CHG-3402 |
| S2 | CHG-3404 — montée de Kubernetes (ou Cilium + remplacement d'un travailleur si no-go) | normal | mardi 20 h-23 h | cluster | CHG-3403 |
| S2 | CHG-3405 — composants de plateforme par GitOps | normal | jeudi 20 h-23 h | cluster | CHG-3404 |
| S3 | CHG-3407 — Ceph sous charge | normal | mardi 20 h-23 h | stockage | CHG-3404 terminé |
| S3 | CHG-3408 — OpenStack 2026.1 → 2026.2 (k8s-par1 arrêté) | normal | samedi 8 h-14 h | cloud | CHG-3407 |
| S4 | CHG-3409 / CHG-3410 — plan et migration des VMs d'InfoGér | normal | samedi 8 h-14 h | virtualisation | CHG-3408 (mémoire rendue) |
| S5 | CHG-3412 — Legacy-RDV en recette sur Kubernetes | standard (recette) | heures ouvrées | cluster | CHG-3410 |
| S6 | CHG-3413 — bascule de production de Legacy-RDV ; **gel 48 h** | normal | samedi 8 h-10 h | applications | CHG-3412 |
| S6 + 48 h | CHG-3414 — décommissionnement de `legacy-rdv01`, revue du trimestre | normal | mardi | virtualisation | fin du gel |

## 8. Rôles

| Rôle | Qui | Responsabilité |
|---|---|---|
| Propriétaire du processus | Claire Morel | approuve, arbitre les fenêtres, préside la revue |
| Exécutant | équipe Plateforme | fiche, préparation, exécution, mesure, clôture |
| Relecteur technique | Karim Benali | relit la fiche et les MR, présent au go/no-go des normaux |
| Sécurité | Sophie Laurent | approuve tout changement qui touche identité, coffre, données de santé |
| Équipes produit | Julien Petit (MédiAgenda), Inès Garnier (MédiVisio) | informées J-2, valident l'impact sur leurs services |
| Support et astreinte | Nadia Roussel | informée, prévient les cabinets, reçoit les signalements pendant la fenêtre |

## 9. Revue après mise en œuvre

Pour chaque changement : objectif de mesure atteint ou non, écarts au plan, retours arrière, incidents liés (INC-60xx), leçons, actions (responsable, échéance). Un changement standard dont la revue est mauvaise perd sa pré-approbation. La revue du trimestre agrège les mesures (`revue-trimestre.md`, F4-S14).
