# Calendrier des tests du PRA

| | |
|---|---|
| Ticket | PLAT-3514 |
| Propriétaire | Claire Morel (responsable du PRA) ; tenue : Nadia Roussel |
| Révision | après chaque exercice complet, au plus tard en décembre |
| Principe | la capacité de reprise est **mesurée en continu** (alertes), **essayée automatiquement** chaque trimestre, **répétée** à la main chaque semestre et **exercée** en vrai chaque année |

## 1. Ce qui tourne tout seul

| Quoi | Fréquence | Qui est prévenu | Critère de réussite | Où va le résultat |
|---|---|---|---|---|
| Contrôle de préparation (`outils/pra/controle-preparation.sh`, minuterie de `adm02`) | chaque nuit 02:17 | astreinte (alerte `PraPar2NonPret` après 30 min) | `pra_par2_pret = 1` | Prometheus de PAR2 |
| Âge du témoin à PAR2, retard de réplication | en continu | astreinte (`PraTemoinEnRetard`, `PraReplicationEnRetard`, `PraTemoinAbsent`) | âge < 15 min, retard < 10 min | Prometheus de PAR2 |
| Retard des flux (WAL copiés, MédiDoc, miroirs, images) | en continu | astreinte (alertes de S04) | sous les objectifs de `dependances.md` | Prometheus |
| **Essai de reprise trimestriel** (`pra:essai-reprise`, pipeline planifié de `plateforme/k8s`) | le 2 de janvier, avril, juillet, octobre à 06:17 | équipe Plateforme (échec du pipeline, courriel GitLab) ; résultat relu au comité du lundi | base restaurée à PAR2 en moins de 30 min, dernier témoin de moins de 15 min, rendez-vous présents, DNS de PAR2 à jour, image de prod sur `reg02` | artefact `resultat-essai.json` (400 jours) ; une ligne dans §4 |

## 2. Ce qui se fait à la main

| Quoi | Quand (2027) | Qui | Critère de réussite | Trace |
|---|---|---|---|---|
| Test mensuel des alertes de préparation (une alerte provoquée puis résolue, à tour de rôle) | 1er mardi du mois | astreinte de la semaine | courriel reçu, alerte résolue | main courante d'exploitation |
| Répétition à blanc de RB-350 (sans toucher PAR1) | 2027-03-16, 2027-09-14 | équipe Plateforme + Nadia | `check F5 8` vert ; durées comparées à la répétition précédente | `exercices/<année>-repetition-N.md` |
| Répétition du retour (RB-351 phases B-C sur la recette) | 2027-03-16 (même jour) | équipe Plateforme | coupure < 15 min, aucun écart de données | idem |
| Vérification de l'enveloppe (sans l'ouvrir, puis ouverture en double contrôle une fois par an) | 2027-02-09, 2027-08-10 ; ouverture : 2027-11-09 | Claire + un gardien | chaque élément présent, daté, scellé ; empreintes concordantes | `enveloppe.md` (date de dernière vérification) |
| **Exercice complet annuel** (isolement de PAR1, RB-350, RB-351, rapport) | **2027-05-18** (jour choisi par Nadia, activité forte), heure tirée au sort | cellule de crise complète, observateur : Sophie | objectifs de `objectifs.md` ; rapport sous 15 jours | `exercices/2027-exercice-1/` |
| Revue de la BIA et des objectifs | 2027-06 (après l'exercice), 2027-12 | Claire, métiers | objectifs revalidés ou révisés, ADR-0350 à jour | `bia.md`, `objectifs.md` |

## 3. Après chaque test

- Un échec ouvre un ticket PLAT-35xx le jour même ; un échec de l'essai trimestriel non corrigé sous 15 jours est remonté à Claire.
- Toute modification de PAR2 (VM, cluster, configuration de site) est suivie du contrôle de préparation à la main ; une modification de RB-350 ou RB-351 est suivie d'une répétition à blanc dans le trimestre.

## 4. Historique

| Date | Test | Résultat | Remarques |
|---|---|---|---|
| 2026-12-08 | répétition à blanc | réussie après INC-6108 | réplication `filer.sync` arrêtée, prévention PLAT-3508 |
| 2026-12-15/16 | exercice complet 2026-1 | objectifs tenus | rapport `exercices/2026-exercice-1/rapport.md` |
| 2026-12-21 | premier essai de reprise automatisé (lancé à la main) | réussi : restauration 11 min 40 s, dernier témoin 4 min 10 s | `resultat-essai.json` du pipeline |
