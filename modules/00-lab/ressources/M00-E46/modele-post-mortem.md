# Post-mortem — <INC-XXXX> — <titre court et factuel>

> Modèle de l'équipe Plateforme MédiSphère. Principe : **sans recherche de coupable**
> (*blameless*). On décrit des faits, des systèmes et des décisions, jamais des fautes de
> personnes. Copie ce fichier dans `docs/socle/post-mortems/AAAA-MM-JJ-<INC-XXXX>.md`.

| | |
|---|---|
| **Statut** | Brouillon / Relu / Clos |
| **Date de l'incident** | AAAA-MM-JJ |
| **Rédacteur** | <nom> |
| **Relecteurs** | <noms> |
| **Sévérité** | P1 / P2 / P3 (justifier en une phrase) |
| **Durée d'impact** | début → fin (durée totale) |
| **Services touchés** | <liste> |

## 1. Résumé

Trois à cinq phrases lisibles par la direction : ce qui s'est passé, l'impact, la cause en
une phrase, l'état actuel.

## 2. Impact

- Qui a été touché, comment (fonctionnalités indisponibles, dégradées).
- Données : perte, corruption, exposition ? (« aucune » doit être justifié).
- Conformité (HDS, ISO 27001) : traçabilité, sauvegardes, journaux affectés ?

## 3. Chronologie

Heures en heure locale, sources citées (journal, alerte, message). Inclure détection,
communications, hypothèses écartées, actions et retour à la normale.

| Heure | Événement | Source |
|---|---|---|
| hh:mm | | |

## 4. Causes

### 4.1 Cause(s) racine(s)

Pour chaque cause : mécanisme technique précis, preuve (commande et sortie), pourquoi elle
a produit ce symptôme.

### 4.2 Facteurs contributifs

Ce qui a rendu l'incident possible, plus long ou plus grave (absence de supervision,
documentation, configuration non persistée, panne masquée par une autre…).

## 5. Détection et diagnostic

- Comment l'incident a-t-il été détecté ? Par qui ? Combien de temps après le début ?
- Qu'est-ce qui a ralenti le diagnostic ? Qu'est-ce qui l'a accéléré ?
- Aurait-on pu le détecter avant l'utilisateur ? Avec quelle sonde ?

## 6. Ce qui a bien fonctionné

## 7. Actions

| # | Action | Type (prévenir / détecter / atténuer / documenter) | Responsable | Échéance | Ticket |
|---|---|---|---|---|---|
| 1 | | | | | |

## 8. Enseignements

Deux ou trois enseignements généralisables au-delà de cet incident.

## Annexes

Extraits de journaux, captures, commandes utiles (sans secret : ni clé privée, ni jeton,
ni mot de passe).
