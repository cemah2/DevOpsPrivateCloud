# Final F3 — Phase 7 : bilan

Vendredi après-midi. Plus d'incident injecté : il reste à transformer la semaine en **apprentissage** pour l'équipe. Un post-mortem qui ne cherche pas de coupable mais des conditions, une alerte qui ne réveille plus personne pour rien sans qu'aucune vraie panne ne passe inaperçue, une passation qui permet à Karim de prendre le téléphone lundi sans t'appeler. C'est aussi la recette du final : l'étiquette `astreinte-v1` sur `plateforme/medisphere`.

Avant de commencer : toutes les injections de la semaine sont closes (`lab/bin/break F3 <XX> --annuler` après chaque réparation), et `lab/bin/check F3 1` est vert.

---

### F3-S14 — Le post-mortem de la semaine  `RED` `★★★`

> **Ticket PLAT-3314** — *De : Nadia Roussel*
> « Un post-mortem pour l'incident le plus grave de ta semaine, avant la réunion d'exploitation de lundi. Pas un roman, pas de coupable : ce qui s'est passé, minute par minute, ce que ça a coûté, pourquoi le système l'a permis, ce qu'on change et quand. Choisis toi-même l'incident, et dis pourquoi celui-là. »

**Objectifs pédagogiques**
- Reconstituer une chronologie fiable à partir de **sources horodatées** (main courante, Alertmanager et Mailpit, Loki dont le locataire `audit`, événements Kubernetes, Argo CD, historique Git), et non de mémoire.
- Mesurer MTTA et MTTR selon des définitions écrites ; chiffrer un impact.
- Chercher des causes contributives (« 5 pourquoi ») au niveau du **système** ; écrire des actions suivies, datées, portées.

**Prérequis** : S03 à S13 ; S02 (définitions, gravités, modèle de post-mortem s'il y en a un) ; module 22 (requêtes LogQL), module 21 (API d'Alertmanager).
**Durée indicative** : 2 à 3 h.

**Livrable** : `docs/exploitation/post-mortems/INC-59XX.md` dans `plateforme/medisphere` (XX : le numéro de l'incident choisi, entre 03 et 13), par MR relue.

**Contenu attendu**
1. Résumé (5 lignes au plus), gravité et **justification du choix** de cet incident parmi ceux de la semaine.
2. Chronologie horodatée (au moins une dizaine d'instants) avec la **source** de chaque ligne ; début de l'impact, détection, prise en compte, diagnostic, rétablissement, clôture.
3. Impact chiffré : services, environnements, utilisateurs, durée, requêtes ou messages concernés, données.
4. Mesures : MTTD, MTTA, MTTR (définitions rappelées), délai de diagnostic.
5. Causes : « 5 pourquoi » jusqu'à une condition du système ; facteurs contributifs.
6. Ce qui a bien marché, ce qui a moins bien marché, la part de chance.
7. Actions : au moins trois, chacune avec un ticket `PLAT-33xx`, un porteur, une échéance datée, un état ; distinguer détection, prévention, atténuation.
8. La règle « sans recherche de coupable » écrite en tête, et respectée (des rôles, pas des personnes, dans les causes).

**Critères de réussite**
- [ ] Le fichier existe sur `main` et contient chacune des huit parties.
- [ ] La chronologie cite ses sources ; les durées MTTA et MTTR se recalculent à partir d'elle.
- [ ] Les actions sont datées et ont un ticket chacune.

**Vérification** : `lab/bin/check F3 14` (présence et contenu minimal ; la qualité s'évalue avec le corrigé).

<details><summary>Indice 1</summary>

L'API d'Alertmanager ne garde pas l'historique des alertes résolues ; Mailpit, si (chaque notification, avec son heure). Prometheus aussi : `ALERTS{alertname="…"}` sur la période, dans Grafana, donne l'heure de passage en *pending* puis en *firing*.
</details>

<details><summary>Indice 2</summary>

Un « pourquoi » qui s'arrête à une personne (« parce que X a lancé la commande ») n'est pas fini : demande pourquoi le système a laissé cette commande produire cet effet, et pourquoi personne ne l'a vu.
</details>

**Pour aller plus loin** (facultatif) : présente le post-mortem en 10 minutes à Claire et Karim (relecture par MR, commentaires intégrés) et fais-en un exercice de jeu M29 pour vérifier dans trois mois que les actions ont tenu.

---

### F3-S15 — Faire taire les alertes inutiles  `LIBRE` `★★★`

> **Ticket PLAT-3315** — *De : Nadia Roussel*
> « J'ai lu ta main courante : tu as passé une partie de ta semaine à trier des courriels qui ne demandaient rien. La personne d'astreinte doit pouvoir faire confiance à chaque notification. Fais le ménage, mais je veux la preuve qu'on ne perd aucune couverture : une alerte qui doit sonner sonne toujours. »

**Objectifs pédagogiques**
- Classer des alertes réellement reçues : actionnables ou non (bruit, doublon, trop tôt, mauvaise cible, mauvais moment).
- Choisir le bon outil pour chaque cas : seuil, durée (`for`), expression de symptôme, inhibition, regroupement, route, intervalle horaire — et savoir quand **ne rien changer** (alertes de sécurité).
- Prouver la couverture par des tests unitaires de règles exécutés en CI.

**Prérequis** : S03 à S13 ; module 21 (règles, `promtool`, Alertmanager, routes et inhibitions, politique d'alerte du M21-E32, CI de `plateforme/observabilite`), module 26 (routes des alertes Falco).
**Durée indicative** : 3 à 4 h.

**Contexte technique** : toutes les notifications de la semaine sont dans Mailpit (`astreinte@`, `plateforme@`, `securite@`) ; les règles et la configuration d'Alertmanager sont dans `plateforme/observabilite` (Argo CD les applique) ; le pipeline de ce dépôt extrait les règles, les vérifie et exécute `promtool test rules` (job `tests-regles`), et rejoue les essais de routage.

**Objectifs à atteindre**
- Une revue écrite de **toutes** les alertes reçues dans la semaine : nombre de notifications, incident lié, classement, décision et sa raison.
- Des corrections dans `plateforme/observabilite`, par **une** MR qui cite `PLAT-3315`, relue, au pipeline vert.
- Au moins une inhibition ou un regroupement ajouté là où une cause et ses conséquences notifiaient séparément.

**Contraintes**
- Aucune alerte supprimée ou désactivée sans **remplaçant** testé qui couvre la même situation ; chaque règle modifiée ou ajoutée a un test qui la fait sonner et un test qui ne la fait pas sonner.
- Aucune alerte de sécurité (Falco, Tetragon, audit) masquée par une inhibition ; aucun avertissement ne devient une notification de nuit.
- Les règles du chart se désactivent par ses valeurs, pas en éditant ses fichiers ; les listes de la configuration d'Alertmanager sont données en entier (Helm remplace les listes).
- La configuration chargée par l'Alertmanager du cluster doit correspondre au dépôt à la fin.

**Livrables**
- MR fusionnée dans `plateforme/observabilite` (règles, tests, valeurs, essais de routage).
- Revue des alertes dans `docs/exploitation/` de `plateforme/medisphere` (nom de fichier contenant `revue-alertes` ou `bruit`), avec le classement et le renvoi à la MR.

**Critères de réussite**
- [ ] Une MR fusionnée de `plateforme/observabilite` cite `PLAT-3315`, modifie des règles **et** des tests, ajoute au moins une inhibition ou un regroupement ; son pipeline et celui de `main` sont verts, `tests-regles` compris.
- [ ] L'Alertmanager du cluster a chargé la configuration du dépôt (même nombre d'inhibitions).
- [ ] La revue est publiée, classe les alertes (actionnable / non actionnable) et renvoie à `PLAT-3315`.

**Vérification** : `lab/bin/check F3 15`

<details><summary>Indice 1</summary>

Compte avant de juger : les objets des courriels de Mailpit, regroupés et comptés, donnent la liste ; `ALERTS` dans Prometheus sur la semaine donne celles qui ont sonné sans être notifiées (routes vers `null`, inhibitions, intervalles horaires).
</details>

<details><summary>Indice 2</summary>

Une alerte du chart qu'on remplace : `defaultRules.disabled` dans les valeurs de kube-prometheus-stack. Une inhibition n'est sûre que si la source et la cible partagent les étiquettes de `equal` : lis les étiquettes réelles des deux alertes avant de l'écrire.
</details>

**Pour aller plus loin** (facultatif) : mesure le bruit dans la durée (une requête ou un tableau de bord « notifications par semaine et par alerte ») et propose un indicateur à suivre dans le rapport de semaine.

---

### F3-S16 — Rapport de semaine et passation  `RED` `★★`

> **Ticket PLAT-3316** — *De : Claire Morel*
> « Lundi 8 h, c'est Karim qui prend le téléphone. Je veux un rapport que je puisse lire en cinq minutes et dont Karim puisse se servir pendant une semaine : ce qui s'est passé, ce que ça a coûté, ce qui reste ouvert. Et pose l'étiquette, qu'on sache où on en était. »

**Objectifs pédagogiques**
- Synthétiser une semaine d'exploitation en indicateurs (incidents, gravités, MTTA, MTTR, interruptions par service) mesurés à partir des traces.
- Rédiger une **passation** utilisable : ce qui est en cours, ce qui est fragile, ce qui doit être fait et par qui.
- Clore proprement : plus rien d'ouvert sur le banc, livrables sous étiquette.

**Prérequis** : S01 à S15.
**Durée indicative** : 1 h 30 à 2 h.

**Livrable** : `docs/exploitation/rapport-semaine-<AAAA-Sww>.md` (semaine ISO, ex. `2026-S45`) dans `plateforme/medisphere`, par MR ; puis l'étiquette **`astreinte-v1`** sur `main`, quand le rapport, la procédure (S02) et le post-mortem (S14) y sont.

**Contenu attendu**
1. La semaine en une phrase.
2. Tableau des incidents : numéro, jour, gravité, service, cause en une ligne, MTTA, MTTR, lien vers la trace.
3. Interruptions et dégradations par service (production d'abord).
4. Travail de fond fait pendant la semaine (MR, runbooks, alertes) et dette constatée, classée par risque.
5. Points ouverts pour la personne suivante : état, prochaine étape, ticket ; ce qui est en cours d'exécution (silences, injections, interventions suspendues) — idéalement rien.
6. Ce que tu referais et ne referais pas.

**Critères de réussite**
- [ ] Le rapport existe sur `main`, recense au moins huit incidents `INC-59xx` avec MTTA et MTTR, les interruptions, la dette, les points ouverts, et renvoie au post-mortem.
- [ ] L'étiquette `astreinte-v1` existe et contient la procédure de gestion d'incident, le post-mortem et le rapport.
- [ ] Aucune injection du final n'est encore ouverte sur le banc.

**Vérification** : `lab/bin/check F3 16`

<details><summary>Indice 1</summary>

`date +%G-S%V` donne la semaine ISO du jour. Les durées viennent de ta main courante (`[ouverture]` → `[clôture]`), pas de ton souvenir ; écris quelle définition de MTTA et de MTTR tu utilises.
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord Grafana « semaine d'astreinte » (alertes notifiées, incidents, SLO consommés) provisionné depuis `plateforme/observabilite`, lien en tête du rapport.
