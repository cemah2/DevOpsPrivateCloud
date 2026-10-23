---
exercice: 2026-exercice-1
incident: INC-6109
t0: "2026-12-15T10:07:00+01:00"
decision: "2026-12-15T10:24:00+01:00"
rto-mediagenda-min: 73
rto-medidoc-min: 91
rto-rdv-min: 139
rto-medinotif-min: 245
rpo-mediagenda-min: 8
rpo-mediagenda-s: 481
rpo-medidoc-min: 7
rpo-rdv-min: 457
coupure-retour-min: 10
statut: approuve
approbateurs: Claire Morel, Sophie Laurent
---

# Rapport de l'exercice PRA 2026-1 — perte simulée de PAR1

| | |
|---|---|
| Exercice | 2026-12-15 (sinistre, T0 10:07) → 2026-12-16 (retour, fin de coupure 10:40) |
| Rédaction | équipe Plateforme ; relevés : Sophie Laurent (observatrice) ; relecture : Nadia Roussel, Julien Petit, Karim Benali |
| Tickets | INC-6108 (répétition), INC-6109 (sinistre), INC-6110 (incident pendant le PRA), CHG-3512 (retour) |
| Preuves | `docs/pra/journal/2026-12-15.md`, `2026-12-16.md` ; `docs/pra/mesures/2026-exercice-1/` (sonde, témoins, documents, divergence) |

> Exemple de référence : chiffres d'un lab imaginé. Les RTO de l'en-tête sont ceux de la sonde (première réponse 2xx servie par PAR2) ; la création de rendez-vous confirmée par Julien (critère d'`objectifs.md`) a eu lieu 2 min après pour MédiAgenda.

## 1. Synthèse pour la direction

**Les objectifs de reprise sont tenus pour les quatre services.** Les patients ont pu reprendre rendez-vous **1 h 13** après la perte de PAR1 (objectif 4 h). Le site de repli a perdu **8 minutes** de rendez-vous (objectif 15 min) : 3 rendez-vous réels pendant l'exercice, que le support a recontactés. Le retour a coûté **une coupure de 9 min 10 s**, annoncée (objectif 15 min), sans aucune perte de ce qui a été écrit pendant le PRA (1 387 témoins, 41 documents, vérifiés un par un).

Trois choses ont failli compromettre la reprise et sont corrigées : une réplication arrêtée sans alerte (trouvée par la répétition, une semaine avant), une dépendance de temps à PAR1 à PAR2 (incident pendant le PRA, 27 min), une étape mal placée dans le runbook (identifiants de la base). La faiblesse principale qui reste : **tout PAR2 tient dans une seule machine**, sans copie hors du bâtiment pendant un PRA (action PLAT-3533, décision budgétaire).

## 2. Objectifs contre mesures

| Service | RTO objectif | RTO mesuré | RPO objectif | RPO mesuré | Verdict |
|---|---|---|---|---|---|
| MédiAgenda | 4 h | **1 h 13** (création confirmée : 1 h 14) | 15 min | **8 min 01 s** (exact, lu à PAR1 au retour ; borne mesurée pendant le PRA : 8 min 58 s) | tenu |
| MédiDoc | 8 h | **1 h 31** | 1 h | **7 min** (dernière copie `rclone` 10:00) | tenu |
| Legacy-RDV | 8 h | **2 h 19** | 24 h | **7 h 37** (sauvegarde de 02:30) | tenu |
| MédiNotif | 8 h | **4 h 05** | messages en vol perdus | 37 confirmations rejouées, doublons acceptés | tenu |
| Retour (coupure) | 15 min | **9 min 10 s** | aucune perte | aucune perte (vérifiée) | tenu |

Décomposition du RTO de MédiAgenda :

| Durée | Mesure | Commentaire |
|---|---|---|
| T0 → décision | **17 min** | critère de RB-350 (15 min d'injoignabilité) + 2 min de décision |
| décision → reprise | **56 min** | vagues 0-1 (isoler, socle) 7 min, vague 2 (secrets) 23 min, vague 3 (base) 14 min, vague 4 (application) 7 min, vague 5 (noms) 5 min ; écart de 5 min (identifiants) |
| reprise → service complet | **3 h 48** | MédiNotif en dernier (supervision montée avant, décision de la cellule) |

## 3. Chronologie (heure de Paris)

| Heure | Événement |
|---|---|
| 12-08 09:44 | répétition à blanc : INC-6108 (réplication `filer.sync` arrêtée depuis 07:58, aucune alerte) ; corrigé, répétition rejouée verte |
| 12-15 10:07 | **T0** — isolement de PAR1 |
| 10:09 | sonde : trois noms en échec ; INC-6109 ouvert |
| 10:14 | cellule de crise réunie |
| 10:24 | **décision de Claire Morel** : PRA déclenché |
| 10:27-10:31 | vagues 0 et 1 : réplications de `s3-02` arrêtées, âges relevés ; zones internes de dns03 en natif ; forge sur `adm02` |
| 10:33-10:54 | vague 2 : `kms01` restauré (3501), descellé, `bao-par2` restauré et descellé |
| 10:58-11:03 | vague 3 : `mediagenda-db-par2` promu (sans jeton) |
| 11:04 | RPO relevé (borne 8 min 58 s) |
| 11:06 | écart : moteur `db-mediagenda` reconfiguré après 5 min de recherche (étape de la vague 2 renvoyée à la vague 3 par RB-350) |
| 11:12-11:15 | vague 4 : MédiAgenda démarré à PAR2, création directe réussie |
| 11:17 | vague 5 : noms globaux vers PAR2 (CNAME, TTL 60 s) |
| **11:19:45** | **MédiAgenda servi par PAR2** (sonde) ; 11:21 création confirmée par Julien |
| 11:37:30 | MédiDoc servi par PAR2 |
| 12:25:45 | Legacy-RDV servi par PAR2 |
| 12:58-13:25 | INC-6110 : horloge de `s3-02` (+25 min), dépôts MédiDoc et archivage de la base refusés pendant 27 min |
| 13:40 | supervision minimale de PAR2 mise en service sur `adm02` (vague 6 ; décision : +512 Mio pour `adm02`) |
| 14:12 | MédiNotif repris ; 14:24 37 confirmations rejouées |
| 14:40 | sauvegardes de PAR2 (base, VMs) ; 15:10 copie hors site décidée (disque de l'enveloppe) |
| 12-16 08:02-08:31 | retour, phase A : PAR1 neutralisé depuis `pve01`, isolement levé |
| 08:40-10:10 | phase B : miroirs versés dans GitLab, PAR1 reconstruit en réplique de PAR2, documents recopiés |
| **10:30:45-10:39:55** | **coupure du retour** ; PAR2 rétrogradé (10:34), PAR1 promu par jeton (10:37), DNS revenu (10:39) |
| 11:30 | PAR2 en veille ; INC-6109 clos |

## 4. Écarts et incidents

| # | Écart | Effet | Cause (mécanisme) | Action |
|---|---|---|---|---|
| E1 | Réplication de l'archive de la base arrêtée 1 h 46 (répétition) | RPO réel de 1 h 46 s'il y avait eu sinistre | arrêt manuel non relancé ; supervision sur « en échec » seulement ; retard non mesuré côté destination pour l'archive de la base | PLAT-3508 contrôle de préparation ; PLAT-3530 alertes de préparation |
| E2 | Moteur `db-mediagenda` d'OpenBao restauré pointant vers la base de PAR1 | 5 min de reprise ; risque d'échec des renouvellements | RB-350 range l'étape en vague 2 avec un renvoi « après la vague 3 » : cherchée au mauvais endroit | PLAT-3536 : étape déplacée dans RB-350, vague 3 |
| E3 | INC-6110 : `s3-02` sans source de temps à PAR2 | 27 min sans dépôt MédiDoc ; archivage de PAR2 suspendu (RPO de PAR2 dégradé d'autant) | `ms_serveurs_ntp` de PAR1 appliquée à PAR2 ; dépendance invisible tant que `wg0` existe | PLAT-3532 : variables de site, contrôle « aucune adresse de PAR1 dans la configuration de PAR2 », alerte d'horloge |
| E4 | Supervision minimale de PAR2 (prévue par `objectifs.md`) mise en service seulement en vague 6, 2 h 20 après la reprise | INC-6110 détecté par un utilisateur, pas par une alerte | arbitrage de mémoire de S01 : rien de prêt en veille, tout à installer le jour J | PLAT-3537 : supervision de PAR2 permanente, en veille aussi (`adm02` à 1,5 Go) ; `objectifs.md` révisé |
| E5 | Aucune copie hors de `hp01` des données écrites pendant le PRA (avant 15:10) | perte totale de la journée si `hp01` tombait | PRA v1 conçu pour reprendre, pas pour durer | PLAT-3533 : cible de sauvegarde chez un tiers HDS (ADR-0350 révisée) |
| E6 | Droit `List` manquant sur l'identité de lecture de `cnpg-k8s-par2` (retour) | 12 min de retour | flux de retour jamais essayé | PLAT-3538 : le test trimestriel lit l'archive de PAR2 depuis PAR1 |
| E7 | Legacy-RDV : 7 h 37 de rendez-vous à ressaisir | charge pour les cabinets | RPO de 24 h accepté en S01 (application en fin de vie) | aucune (accepté) ; à rappeler dans l'ADR-0340 |
| E8 | Rejeu des notifications fait à la main | 12 min, risque d'erreur | pas de fonction de rejeu dans MédiAgenda | PLAT-3539 (avec l'équipe MédiAgenda) |

## 5. Ce qui a bien marché

- La répétition à blanc a trouvé le défaut le plus grave **avant** l'exercice.
- Le critère de déclenchement temporel n'a fait l'objet d'aucune discussion : décision en 2 min.
- La promotion sans jeton, puis le retour par jetons : aucune intervention manuelle sur PostgreSQL.
- Le témoin a donné un RPO incontestable, à la seconde, confirmé au retour.
- Aucune donnée de patient dans la main courante ni dans les messages (relu par Sophie).

## 6. Leçons

1. Un site tiède se dégrade **en silence** : ce qui ne s'exerce pas (démarrer, planifier, recevoir) doit être mesuré par son effet, chaque jour.
2. Une dépendance au site principal ne se voit qu'en le coupant : chaque configuration de PAR2 doit être relue avec la question « et sans PAR1 ? ».
3. Le retour est plus délicat que la bascule : il a ses propres flux (qui n'avaient jamais tourné) et son propre runbook, qui doit être répété.
4. `hp01` suffit à reprendre ; il ne suffit pas à durer plusieurs jours.

## 7. Actions

| Ticket | Action | Responsable | Échéance |
|---|---|---|---|
| PLAT-3508 | contrôle de préparation quotidien (fait) | Plateforme | fait |
| PLAT-3530 | alertes de préparation à PAR2 (âge du témoin, retard de réplication, indicateur de préparation) | Plateforme | 2027-01-15 |
| PLAT-3531 | RB-350 : préalables = résultat du contrôle de préparation | Nadia Roussel | 2027-01-15 |
| PLAT-3532 | sources de temps et DNS par site ; contrôle d'absence d'adresses de PAR1 dans la configuration de PAR2 ; alerte d'horloge | Karim Benali | 2027-01-31 |
| PLAT-3533 | cible de sauvegarde hors des deux sites (tiers HDS, chiffrée) ; chiffrage dans l'ADR-0350 révisée | Claire Morel | 2027-03-31 |
| PLAT-3535 | suppression des instantanés et exports de divergence après approbation du rapport | Plateforme | 2027-01-15 |
| PLAT-3536 | RB-350 : reconfiguration du moteur `db-mediagenda` déplacée en vague 3 | Plateforme | 2027-01-15 |
| PLAT-3537 | supervision minimale de PAR2 permanente (en veille aussi) ; `objectifs.md` révisé | Plateforme | 2027-01-31 |
| PLAT-3538 | test de reprise trimestriel automatisé, avec lecture de l'archive de PAR2 depuis PAR1 | Plateforme | 2027-01-15 |
| PLAT-3539 | fonction de rejeu des notifications dans MédiAgenda | Julien Petit | 2027-T1 |

## 8. Révisions décidées

- `objectifs.md` : supervision minimale de PAR2 **permanente** (et non plus démarrée en PRA seulement) ; RTO et RPO **maintenus** (tenus avec marge, mais sur un seul exercice).
- RB-350 : étape du moteur `db-mediagenda` en vague 3 ; préalables par le contrôle de préparation ; le RPO se relève **avant** la réactivation du témoin de PAR2.
- RB-351 : contrôle 0.6 (droits de l'identité de lecture) ; ordre des miroirs.
- ADR-0350 : révision au 2027-03-31 (cible hors site, durée de tenue de PAR2).
- Prochain exercice complet : mai 2027 (calendrier-tests.md), sur un jour de forte activité choisi par Nadia.
