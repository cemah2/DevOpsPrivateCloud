# Phase 5 — Recette Day 1

Trois équipes sont passées par la plateforme : MédiVisio est en production, Data reçoit ses données chaque matin, AxiomDev est parti sans laisser de traces. Claire Morel veut deux choses avant de poser l'étiquette : un **outil** qui dit, à tout moment, si une équipe accueillie a bien tout ce que l'offre de service promet (et rien de plus) ; et un **retour d'expérience** honnête, chiffré, qui dise quoi améliorer avant la prochaine arrivée.

> **Rappels** : `lab/bin/check F2 13` relance les vérifications des scénarios qui laissent un état (S02, S04, S05, S07, S08, S11, S12) : traite d'abord leurs points rouges. Aucune panne F2 ne doit rester ouverte.

---

### F2-S13 — Recette Day 1  `LIBRE` `★★★`

> **Ticket PLAT-3213** — *De : Claire Morel*
> Avant de dire « Day 1 terminé », je veux qu'on puisse vérifier une équipe en une commande, la nuit comme le jour de son arrivée : ses groupes, son locataire et ses quotas, son projet Argo CD, ses alertes, sa fiche au catalogue, et son SLO si elle a un service en production. Vert pour MédiVisio et Data. Ensuite on pose l'étiquette, avec Sophie en témoin.

**Objectifs pédagogiques**
- Traduire une offre de service en contrôles exécutables, en lecture seule, avec des identités de lecture.
- Écrire un outil de plateforme testable sans les services réels (codes retour, sortie lisible et JSON, sources non vérifiées signalées).
- Conduire une recette : preuves, délais mesurés, réserves, étiquette.

**Prérequis** : S01 à S12 (S12 avant S13 : la recette constate qu'AxiomDev est parti) ; M02 (outils de `plateforme/outils`, bibliothèque commune), M19 (composants CI).
**Durée indicative** : 4 à 6 h.

**Contexte technique**
- Nom et emplacement : **`bin/ms-verif-equipe <equipe>`** dans **`plateforme/outils`**.
- Ce que l'outil doit couvrir, pour une équipe interne : groupe de l'annuaire (et ses membres), groupe Keycloak, groupe GitLab, locataire Capsule (propriétaire, classes de priorité) et, pour chaque espace, quota, limites et niveau Pod Security, AppProject (destinations, ressources de cluster, dépôts), politiques OpenBao du groupe, dossier Grafana, route d'Alertmanager (`equipe="<equipe>"`), entité `Group` du catalogue, SLO Pyrra (`pyrra.dev/equipe=<equipe>`) dès qu'un service tourne en production. Pour une équipe externe (`ext-*`) : l'**absence** de ce qu'elle ne doit pas avoir.
- Identités de lecture : celles des vérifications du workbook (`wb-checks`) conviennent dans le lab ; en production, des identités dédiées (variables protégées de la CI).
- Rapport de recette : **`docs/accueil/recette-day1.md`** ; étiquette **`day1-v1`** sur `plateforme/medisphere`.

**Travail demandé**
1. Écris `ms-verif-equipe` : une ligne par contrôle (OK, KO, non vérifié), une sortie JSON, un code retour exploitable par la CI ; une source sans identité n'est jamais « OK ».
2. Teste-le **sans** les services (faux outils, cas d'échec : membre désactivé resté dans le groupe, locataire absent, équipe externe) et branche ces tests dans la CI de `plateforme/outils` ; planifie une vérification quotidienne des équipes accueillies.
3. Passe la recette : `ms-verif-equipe medivisio`, `data` (vert) et `ext-axiomdev` (ce qui est attendu après un départ) ; délais mesurés (création d'équipe, premier déploiement, mise en production, première extraction, arrivée et départ du prestataire) ; interventions manuelles de la plateforme ; réserves.
4. Publie `recette-day1.md` et pose **`day1-v1`** (étiquette annotée, message qui résume la recette).

**Critères de réussite**
- [ ] `bin/ms-verif-equipe` est sur `main` de `plateforme/outils` et couvre locataire, quotas, AppProject, alertes, catalogue et SLO ; la CI le teste ; le dernier pipeline de `main` est vert.
- [ ] `lab/bin/check F2` est vert pour 02, 04, 05, 07, 08, 11 et 12.
- [ ] `docs/accueil/recette-day1.md` publié (sorties de l'outil pour chaque équipe, délais mesurés).
- [ ] Aucune panne F2 ouverte ; étiquette `day1-v1` posée sur `plateforme/medisphere`.

**Vérification** : `lab/bin/check F2 13`

<details><summary>Indice 1</summary>

Pense l'outil comme un check du workbook, mais pour la production : chaque contrôle doit pouvoir être rouge sur un cas réaliste, et « je n'ai pas pu regarder » n'est pas « tout va bien ». Sépare collecte (appels en lecture), décision (OK/KO) et présentation (texte, JSON).
</details>

<details><summary>Indice 2</summary>

Pour tester sans services : place en tête du `PATH` de faux `kubectl` et `ldapsearch` qui répondent selon leurs arguments ; laisse les autres sources sans identité et ignore-les explicitement. Trois ou quatre cas bien choisis valent mieux que vingt.
</details>

**Pour aller plus loin** (facultatif) : lancer `ms-verif-equipe` à la fin de chaque pipeline de `plateforme/equipes` (après propagation et synchronisation d'Argo CD) pour que « une équipe en un changement » soit aussi « une équipe vérifiée en un changement ».

---

### F2-S14 — Retour d'expérience et feuille de route  `RED` `★★`

> **Ticket PLAT-3214** — *De : Claire Morel*
> Fais-moi le bilan de ce mois d'accueil, pour le comité de direction : ce qu'on a promis, ce qu'on a tenu, combien de temps ça a pris, ce qui a coincé, ce qu'en pensent Inès, Hugo et Marc. Et ta proposition pour le trimestre prochain, priorisée. Une page qu'on lit en dix minutes, avec les chiffres en annexe.

**Objectifs pédagogiques**
- Évaluer une plateforme interne comme un produit : délais, frictions, satisfaction des équipes.
- Transformer des constats en feuille de route priorisée et argumentée.

**Prérequis** : S01 à S13 ; tes journaux et mesures (`docs/accueil/journal/`, `mesures/`).
**Durée indicative** : 2 h.

**Travail demandé**

Rédige **`docs/accueil/retour-experience.md`** :
1. ce qu'on voulait prouver (rappel de l'offre de service) ;
2. les délais mesurés contre les cibles, avec la cause principale de chaque écart ;
3. les frictions et les tickets (`DEV-32xx`, `SEC-32xx`, `PLAT-32xx`), cause racine, état ; le nombre d'interventions manuelles de la plateforme ;
4. la satisfaction recueillie auprès d'Inès, Hugo et Marc (questionnaire court, notes et citations ; dans le lab, joue les réponses de façon vraisemblable à partir de ce que les scénarios leur ont fait vivre) ;
5. ce qui a marché, ce qui n'a pas marché ;
6. la feuille de route du trimestre : actions priorisées (méthode de priorisation dite), effort, responsable, indicateur de réussite ;
7. les décisions demandées à la direction.

**Critères de réussite**
- [ ] Le document est publié sur `main` et compte au moins cinq sections.
- [ ] Il chiffre des délais (dont le premier déploiement) et cite des tickets du final.
- [ ] Il rapporte la satisfaction d'Inès, Hugo et Marc.
- [ ] Il propose une feuille de route trimestrielle priorisée.

**Vérification** : `lab/bin/check F2 14` (présence et contenu minimal ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Un comité de direction lit la première page : mets la conclusion et les trois décisions demandées en tête, les tableaux ensuite. Un délai sans cible ne dit rien ; une cible sans mesure non plus.
</details>

**Pour aller plus loin** (facultatif) : définir trois indicateurs suivis chaque mois (délai jusqu'au premier déploiement, tickets d'accueil par équipe, efficacité réservé/utilisé) et les mettre dans un tableau Grafana « plateforme comme produit ».
