# Journée de jeu — <SUJET> — <AAAA-MM-JJ>

> Gabarit de l'équipe Plateforme (M29-E16). À recopier dans `docs/qualite/journees-de-jeu/AAAA-MM-JJ-<sujet>.md` de `plateforme/medisphere`. Les sections 1 à 4 sont écrites **avant** le jeu et relues par un pair ; les sections 5 à 8 après. Aucun secret, aucune donnée personnelle.

| | |
|---|---|
| Ticket | PLAT-… |
| Maître du jeu | … |
| Astreinte (joueur) | … |
| Observateurs | … |
| Scribe | … |
| Date, heure de début et de fin prévues | … |
| Expériences versionnées | `plateforme/resilience/journees-de-jeu/<AAAA-MM-JJ>/` (commit …) |

## 1. Préparation : objectifs

Ce que la journée doit apprendre (système **et** équipe). Deux à quatre objectifs.

## 2. Préparation : hypothèses

| # | Expérience (fichier) | Hypothèse (« quand X arrive à Y, Z reste sous S, et l'astreinte le voit en moins de T ») | Mesure | Critère d'arrêt |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

## 3. Préparation : rayon d'action et garde-fous

- Dans le champ : …
- Hors champ (et pourquoi) : …
- Critères d'arrêt **globaux** (tout arrêter) : …
- Bouton d'arrêt : `outils/chaos-arret.sh` (RB-294), qui le tient : …
- Retour arrière préparé : …
- Ce qui est vérifié juste avant de commencer (SLO verts, aucune intervention en cours, charge prête) : …

## 4. Préparation : communication

| Quand | Qui | Quoi | Canal |
|---|---|---|---|
| J-2 | | annonce | |
| H-15 min | | confirmation | |
| H0 | | début | |
| Fin | | retour à la normale | |

## 5. Chronologie (le scribe, à la minute)

| Heure | Événement (injection, alerte, diagnostic, action, retour) | Qui | Preuve |
|---|---|---|---|

## 6. Hypothèses : résultats

| # | Confirmée / réfutée | Mesures (avant / pendant / après) | Commentaire |
|---|---|---|---|

## 7. Détection

| # | Alerte attendue | Alerte reçue (heure) | Temps de détection | Temps jusqu'au bon diagnostic | Commentaire |
|---|---|---|---|---|---|

## 8. Actions correctives

| Action | Type (système / détection / processus) | Responsable | Échéance | Ticket (issue `journee-de-jeu`) | État |
|---|---|---|---|---|---|

## 9. Ce qui a bien marché, ce qu'on refera autrement
