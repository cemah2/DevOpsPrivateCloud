---
# En-tête lu par les checks du final F4 (finaux/F4-changements/checks/_f4-montees.sh) et par la revue du
# trimestre (S14). Garde les noms de clés ; laisse une valeur vide plutôt que de supprimer une clé.
chg: CHG-34XX
titre: ""
categorie: normal            # standard | normal | urgent
statut: brouillon            # brouillon | approuve | en-cours | termine | annule | retour-arriere
decision: ""                 # go | no-go (rempli au go/no-go, avec l'heure dans « Décision »)
demandeur: ""
executant: ""
approbateurs: ""             # au moins Claire Morel pour un « normal » ; + Sophie Laurent si sécurité
fenetre-debut: ""            # ISO 8601 avec fuseau, ex. 2026-11-10T20:00:00+01:00
fenetre-fin: ""
mesure-source: cluster       # cluster (Thanos, continuite:en_erreur) | temoin (mon01, sondes seules)
mesure-groupes: ""           # facultatif, source temoin : regex des groupes de sondes retenus
mesure-debut: ""             # début de la mesure = début de la fenêtre (ou de l'étape mesurée)
mesure-fin: ""
mesure-objectif-s: 30        # secondes d'erreur cumulées admises (fixées AVANT, jamais après)
mesure-interruption-s: ""    # valeur relevée APRÈS (outils/mesurer-interruption.sh)
---

# CHG-34XX — <titre>

## 1. Résumé

Quoi, pourquoi maintenant, pour qui. Une phrase par point.

## 2. Risque

| Risque | Probabilité | Gravité | Réduction | Signal qui le révèle |
|---|---|---|---|---|
| | faible / moyenne / forte | faible / moyenne / forte | | requête, alerte, sonde |

Niveau global (faible / moyen / élevé) et justification.

## 3. Impact attendu

- Utilisateurs (cabinets, patients, équipes) : ce qu'ils peuvent voir, pendant combien de temps.
- Services touchés et dépendances (amont, aval).
- Ce qui n'est **pas** touché (et pourquoi on en est sûr).

## 4. Fenêtre

- Fenêtre : <date, heure de début, heure de fin>, fuseau Europe/Paris.
- Hors gel (voir `processus.md` §5) ; aucun autre changement normal dans la même fenêtre.
- Durée estimée de chaque grande étape ; marge pour le retour arrière **comprise** dans la fenêtre.

## 5. Préparation (avant le jour J)

- [ ] Lectures faites (notes de version, guides de montée) : liens.
- [ ] Répétition (où, quand, résultat) ou raison écrite de ne pas répéter.
- [ ] Sauvegardes **vérifiées** (quoi, où, date, comment on l'a vérifiée).
- [ ] MR prêtes (liens), pipelines verts, non fusionnées si elles décrivent l'état d'après.
- [ ] Sonde de continuité prête (RB-340) ; objectif `mesure-objectif-s` fixé.
- [ ] Communication « avant » envoyée (voir §9).

## 6. Étapes

| # | Étape | Commande, MR ou playbook | Durée prévue | Contrôle de passage | Heure réelle |
|---|---|---|---|---|---|
| 1 | | | | | |

## 7. Critères de go/no-go et d'abandon

- **Go** (juste avant de commencer) : santé, sauvegardes, sonde verte depuis 10 min, personnes présentes.
- **Abandon** (pendant) : seuils chiffrés qui font arrêter et revenir en arrière (ex. > 60 s d'erreur cumulées, une sonde rouge plus de 2 min, `HEALTH_ERR`).

## 8. Retour arrière

- Procédure par étape (jusqu'où on peut revenir, et comment).
- **Testé** : quand, comment (répétition, essai sur un environnement jetable) — ou limite écrite (« une montée de plan de contrôle ne se défait que par restauration d'etcd »).
- Point de non-retour : à quelle étape, et ce qu'on fait après lui (réparer en avant).

## 9. Communication

| Quand | Qui | Message | Canal |
|---|---|---|---|
| J-2 | Julien Petit, Nadia Roussel, support | annonce, fenêtre, impact attendu | courriel `plateforme@` |
| début | astreinte | « CHG-34XX commence » | journal + courriel |
| fin | mêmes | résultat, mesure, suites | courriel |

## 10. Mesure de l'interruption

| Moment | Fenêtre | Secondes d'erreur cumulées | Requêtes en erreur (k6) | p95 MédiAgenda prod | Remarques |
|---|---|---|---|---|---|
| avant (ligne de base, 30 min) | | | | | |
| pendant | | | | | |
| après (30 min) | | | | | |

Commande : `outils/mesurer-interruption.sh <DÉBUT> <FIN> [cluster|temoin]` (projet `plateforme/observabilite`). Report la valeur « pendant » dans `mesure-interruption-s`.

## 11. Journal d'exécution

Horodatage de chaque étape, écart au plan, décision prise.

## 12. Clôture et revue après mise en œuvre

Résultat (réussi, réussi avec écarts, abandonné), mesure contre objectif, écarts, actions (ticket, responsable, échéance). La revue du trimestre (`revue-trimestre.md`) reprend cette section.
