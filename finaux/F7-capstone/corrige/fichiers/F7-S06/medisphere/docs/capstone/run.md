# Organisation du run du service GHSV

> PLAT-3706 (F7-S06). Auteur : équipe Plateforme. Relu par Nadia Roussel (responsable du support et de l'astreinte) et Claire Morel.
> Références : EXP-01 à EXP-08 du CCTP, `exigences.md` (NF-20, NF-21), processus d'incident du F3, processus de changement du F4, cellule de crise du F5, réponse à incident du F6 (RB-360).

## 1. Niveaux de support

| Niveau | Qui | Horaires | Rôle |
|---|---|---|---|
| N1 | centre de services du GHSV | ses horaires | accueil des agents et des patients, qualification, ticket dans l'outil commun |
| N2 | support de MédiSphère (équipe de Nadia Roussel) | **lundi au samedi, 8 h-19 h** (EXP-01) | diagnostic, contournements, runbooks ; escalade N3 |
| N3 | équipe Plateforme (infrastructure, données, sécurité) et équipe MédiAgenda (application) | heures ouvrées ; astreinte pour les P1 | correctifs, changements, analyse de cause |
| Astreinte | rotation de l'équipe Plateforme, escalade applicative | **24 h/24, 7 j/7**, P1 seulement | rétablissement, communication, cellule de crise |

**Le samedi** : un agent du support N2 en poste de 8 h à 19 h, en rotation (un samedi sur quatre par personne, récupéré dans la semaine) ; l'astreinte couvre les P1. Le support compte aujourd'hui trop peu de personnes pour tenir le samedi sans renfort : **+0,5 ETP** de support (recrutement ou temps partagé avec le support de MédiAgenda).

## 2. Priorités et délais (EXP-02, NF-20)

| Priorité | Exemple | Prise en compte | Rétablissement | Qui est réveillé |
|---|---|---|---|---|
| P1 | prise de rendez-vous indisponible (sondes en échec, budget qui fond), incident de sécurité | **15 min**, 24 h/24 | **4 h** (au-delà : PRA, décision de la cellule de crise) | astreinte (alerte directe), puis le responsable d'escalade |
| P2 | rappels non envoyés, pièces jointes indisponibles, API lente (p95 > 300 ms), interface des agents dégradée | 1 h ouvrée | 1 jour ouvré | personne la nuit ; N2 en journée |
| P3 | anomalie sans impact sur la prise de rendez-vous | 1 jour ouvré | 10 jours ouvrés | — |

- Les alertes de NF-01/NF-02 (consommation rapide du budget, Pyrra) et de sécurité (Falco, Tetragon, F6) ouvrent un P1 **sans attendre** un ticket du N1 ; l'horodatage de l'alerte fait foi pour la prise en compte.
- Message d'état au GHSV : à la prise en compte d'un P1, puis toutes les 30 min jusqu'au rétablissement (modèle du F3) ; incident de sécurité : information sous 24 h au plus (ESC-10, RB-360 avec le contact du GHSV).
- Post-mortem sans recherche de coupable pour chaque P1 (F3), remis au GHSV sous 10 jours ouvrés.

## 3. Astreinte

- **Rotation** hebdomadaire (du lundi 9 h au lundi 9 h), une personne d'astreinte primaire + un **responsable d'escalade** (Karim Benali ou Claire Morel) ; escalade applicative vers un développeur de l'équipe MédiAgenda (rotation séparée, joignable, sans engagement de 15 min).
- **Effectif** : aujourd'hui, quatre personnes peuvent tenir l'astreinte primaire (Claire Morel, Karim Benali, toi, Nadia Roussel) ; Lucas Martin, stagiaire, n'est **jamais seul** d'astreinte (binôme d'observation). Quatre personnes, c'est une semaine sur quatre, sans marge pour les congés : **recrutement d'un ingénieur plateforme** lancé à la notification (arrivée visée en mai) pour passer à cinq, soit une semaine sur cinq.
- **Conditions** : prime d'astreinte et récupération des interventions de nuit selon l'accord d'entreprise (≈ 4 000 €/an par personne au chiffrage), temps de repos respecté après une intervention ; outillage : alertes vers le téléphone (Alertmanager), accès d'urgence par le VPN d'administration de PAR1 et de PAR2, enveloppe de reprise (F5) pour le PRA.
- **Hypercare** après chaque vague : deux semaines d'astreinte doublée et un point quotidien de 15 min avec le centre de services du GHSV.

## 4. Rituels

| Rituel | Fréquence | Participants | Sortie |
|---|---|---|---|
| Point d'exploitation | hebdomadaire | Nadia Roussel, toi, Julien Petit | incidents, changements de la semaine, actions |
| Comité de suivi (EXP-04) | mensuel | DSI du GHSV, Claire Morel, toi, Nadia Roussel | rapport mensuel commenté, actions, validation des méthodes de mesure (R-09) |
| Revue de capacité | mensuelle (trimestrielle à partir de l'année 2) | toi, Karim Benali | pointe, utilisation, marge, prévision ; essai de capacité trimestriel (NF-07) |
| Revue des accès (ESC-11) | trimestrielle | Sophie Laurent, Nadia Roussel | accès de notre personnel à `ghsv-prod`, comptes orphelins (processus du F6) |
| Comité de pilotage (EXP-04) | trimestriel | direction du GHSV, Claire Morel | bilan, évolutions, options |
| Revue de sécurité | annuelle | Sophie Laurent, RSSI du GHSV | test d'intrusion, vulnérabilités, incidents |
| Exercice de PRA | annuel avec le GHSV + un interne | cellule de crise | rapport (ENF-08, NF-13) |

## 5. Rapport mensuel (EXP-03, NF-21)

Généré automatiquement le 1er du mois à 06:15 (F7-S10, RB-374) à partir de Prometheus, Loki, des fiches de changement et des tickets ; relu par Nadia Roussel et toi ; envoyé au GHSV avant le 10. Contenu : disponibilité (NF-01, méthode rappelée, minutes indisponibles et causes), latence p95/p99, incidents et post-mortems, maintenances (durée annoncée et mesurée), capacité (pointe, marge, prévision), sécurité (vulnérabilités, accès de notre personnel, incidents), changements réalisés et prévus, état des actions, rotation des clés (NF-18).

## 6. Changements chez le GHSV

Processus du F4 (fiches CHG, go/no-go, mesure) ; en plus : préavis de **5 jours ouvrés** au GHSV pour toute maintenance qui peut l'interrompre (ENF-04), versions de MédiAgenda livrées en recette du GHSV **10 jours ouvrés** avant la production (EXP-06), évolutions de l'API rétrocompatibles et testées par les tests de contrat (EF-05). Gel des changements du locataire si le budget d'erreur est consommé (NF-02).

## 7. Montée en compétences

| Action | Pour qui | Quand |
|---|---|---|
| Runbooks RB-370 (exploitation du service GHSV, avec la réconciliation des rendez-vous après un PRA ; à écrire à la notification), RB-371 (réversibilité et fin de contrat d'un client), RB-372 (identité fédérée du client), RB-373 (contrat d'API du client), RB-374 (rapport mensuel d'un client) ; PRA du client : `pra-ghsv.md` et RB-350/RB-351 du F5 | toute l'astreinte | avant la vague 1 (RB-370, RB-372, RB-373), avant le premier test de PRA (RB-371, RB-374) |
| Binôme d'astreinte : chaque nouvel arrivant fait deux semaines en second avant d'être primaire | nouvel ingénieur, Lucas Martin | dès l'arrivée |
| Exercice sur table d'un P1 du GHSV (panne de la base, IdP du GHSV en panne, fuite suspectée) | astreinte, support | février, puis trimestriel |
| Journée de jeu (M29) sur la recette du GHSV | Plateforme et MédiAgenda | trimestrielle |
| Formation à l'outil de tickets commun et aux procédures du centre de services du GHSV | support N2 | février |
| Revue des post-mortems du trimestre | tous | trimestrielle |

Indicateurs de l'organisation (revus en comité interne) : nombre de personnes dans la rotation, interventions de nuit par mois, délai de prise en compte des P1, part des P1 résolus sans escalade, runbooks utilisés et corrigés après usage.
