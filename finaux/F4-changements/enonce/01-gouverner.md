# Final F4 — Phase 1 : Gouverner

Avant de toucher à quoi que ce soit, deux choses : des règles que tout le monde a lues, et un instrument qui dit, après chaque opération, ce que les utilisateurs ont vécu. Sans elles, « ça s'est bien passé » reste une opinion.

Prérequis de la phase : [`00-introduction.md`](00-introduction.md) lu, état d'entrée vérifié.

---

### F4-S01 — Le processus de changement de MédiSphère  `RED` `★★`

> **Ticket PLAT-3401** — *De : Claire Morel* — *Copie : Karim Benali, Nadia Roussel, Julien Petit, Sophie Laurent*
> Jusqu'ici, nos changements tenaient dans les fiches de chaque module, chacune avec sa forme : CHG-952 pour Ceph, CHG-1154 pour OpenStack, CHG-1525 pour Kubernetes… Pour l'audit HDS et pour ce trimestre, je veux **un** processus : ce qui est un changement, qui l'approuve, comment on décide d'y aller ou non, quand on a le droit, comment on mesure, comment on revient en arrière, et comment on apprend après. Et un modèle de fiche que tout le monde remplira de la même façon, outils compris. Je relis jeudi.

**Objectifs pédagogiques**
- Distinguer les catégories de changement (standard pré-approuvé, normal, urgent) et les règles qui en découlent.
- Écrire un modèle de fiche complet et exploitable par des outils (en-tête structuré).
- Planifier un trimestre de changements sous contraintes (dépendances, fenêtres, gel, mémoire du lab).

**Prérequis** : fiches de changement des modules (CHG-952 du M08, CHG-1154 du M10, CHG-1525 du M14, CHG-3015 du M29) ; gestion d'incident de F3 si tu l'as fait.
**Durée indicative** : 2 h.

**Contexte technique**
- Les décisions de Claire et les contraintes du calendrier sont dans [`00-introduction.md`](00-introduction.md) (fenêtres, gel, ordre des changements, mémoire).
- Les checks de tout le final lisent l'en-tête YAML des fiches : clés `decision`, `mesure-source`, `mesure-groupes`, `mesure-debut`, `mesure-fin`, `mesure-objectif-s`, `mesure-interruption-s` (format dans l'introduction, « Conventions du final »). Ton modèle les contient, avec d'autres si tu veux.
- Numérotation : CHG-34xx où `xx` est le numéro du scénario (CHG-3404 pour la montée de S04…).

**Travail demandé**
1. Rédige `docs/changements/processus.md` : définition d'un changement (et de ce qui n'en est pas un : une livraison applicative par le chemin GitOps ?), les trois catégories avec exemples tirés de **notre** plateforme et leurs approbateurs, le cycle de vie d'une fiche, le go/no-go (qui, quand, critères, et ce qu'on fait d'un no-go), les fenêtres et le **gel**, la mesure de l'interruption (avant, pendant, après), le retour arrière, la revue après mise en œuvre, les rôles.
2. Mets dans ce document le **calendrier du trimestre** : chaque changement de F4 (CHG-3402 à CHG-3414), sa catégorie, sa fenêtre, son domaine, ses dépendances.
3. Rédige le modèle `docs/changements/fiches/modele.md` : en-tête YAML (au moins les clés lues par les checks, plus catégorie, statut, fenêtre), puis les sections risque, impact, fenêtre, préparation, étapes, critères de go/no-go et d'abandon, retour arrière, communication, mesure, journal, clôture.
4. MR relue par Karim (et par Claire pour le calendrier), fusionnée sur `main`.

**Critères de réussite**
- [ ] `docs/changements/processus.md` est sur `main` avec les trois catégories, le go/no-go, le gel, le retour arrière, la revue après mise en œuvre, la mesure, et le calendrier citant les changements du trimestre.
- [ ] `docs/changements/fiches/modele.md` est sur `main` ; son en-tête YAML contient les clés de catégorie, statut, décision, fenêtre et mesure ; ses sections couvrent risque, impact, fenêtre, préparation, étapes, go/no-go, retour arrière, communication, mesure.

**Vérification** : `lab/bin/check F4 1` (présence et contenu minimal ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Un changement standard n'est pas « un petit changement » : c'est un changement **répété**, dont le runbook a déjà été éprouvé et dont la mesure passée est connue. Relis RB-142, RB-101, RB-082 : lesquels peuvent devenir standard, et à quelle condition perdent-ils ce statut ?
</details>

<details><summary>Indice 2</summary>

Le calendrier se construit à rebours depuis la fin du contrat d'InfoGér, en respectant trois contraintes : les dépendances (la plateforme montée avant d'y accueillir Legacy-RDV), la mémoire (OpenStack exige le cluster arrêté : pas en même temps qu'autre chose sur le cluster), et le gel qui suit la bascule.
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord des changements (fiches du trimestre, statut, mesure contre objectif) généré depuis les en-têtes par un job de CI ; la notion de *change advisory board* d'ITIL 4 (« change enablement ») et ce qu'elle devient dans une équipe de cinq.

---

### F4-S02 — La sonde de continuité  `LIBRE` `★★★`

> **Ticket CHG-3402** — *De : Karim Benali* — *Copie : Julien Petit, Nadia Roussel*
> Chaque fiche de ce trimestre devra dire combien de secondes nos utilisateurs ont perdues. Il me faut donc un instrument qui tourne pendant toute fenêtre et qui joue l'utilisateur : une charge constante et faible, des sondes vues de l'extérieur du cluster, un tableau qu'on garde ouvert pendant l'opération, et surtout **un nombre** à la fin, toujours calculé de la même façon. Julien accepte une lecture très légère sur la prod, à condition que rien ne s'y écrive. Et l'instrument doit encore marcher le jour où le cluster sera éteint pour OpenStack.

**Objectifs pédagogiques**
- Concevoir une mesure d'interruption objective, reproductible et indépendante de l'opérateur.
- Combiner une charge synthétique (k6-operator), des sondes externes (blackbox de `mon01`) et des métriques d'application en une série unique.
- Écrire des règles d'enregistrement testées et un tableau de pilotage d'opération.

**Prérequis** : F4-S01 ; M29-E14 (k6-operator, `TestRun`, écriture distante vers Prometheus, CNP `prometheus-ecriture-k6`) ; M21-E11, E12 (témoin de `mon01`, sondes, fédération), M21-E14 (règles d'enregistrement, `promtool`), M21-E26/E27 (Pyrra) ; M29-E07 (règles du témoin dans le rôle).
**Durée indicative** : 5 à 6 h.

**Contexte technique**
- MédiAgenda prod : `https://mediagenda.apps.par1.medisphere.internal` (`/pret`, `GET /api/v1/creneaux?date=…&praticien=…`) ; recette : `https://mediagenda-recette.apps.par1.medisphere.internal` (parcours d'écriture du M29). MédiDoc n'est publié qu'en recette (`/readyz`). Portail : `/.backstage/health/v1/readiness`. RabbitMQ : interface publiée `https://rabbitmq.apps.par1.medisphere.internal`.
- Sur `mon01`, les sondes se déclarent par groupes (`supervision_temoin_sondes`, étiquette `groupe` = nom du groupe, job `blackbox`) ; le cluster fédère toutes les séries du job `blackbox` (`federation-mon01`). Le témoin dépose les fichiers de règles du rôle comme au M29-E07.
- Les checks du final attendent : des groupes de sondes nommés **`continuite-*`** avec une étiquette **`service`** (au moins `mediagenda`, `medidoc`, `rabbitmq`, `portail` ; `openstack` en S08, `legacy-rdv` en S10) ; sur le **témoin**, les séries enregistrées **`continuite:sonde_en_erreur`** (1 par sonde en échec) et **`continuite:sondes_en_erreur:max`** (1 si au moins une sonde échoue) ; dans le **cluster**, une `PrometheusRule` **`continuite`** (espace `supervision`, groupe évalué toutes les **15 s**) qui enregistre **`continuite:en_erreur`** : 1 dès qu'une sonde échoue, que la charge voit des erreurs ou que MédiAgenda prod renvoie des 5xx, 0 sinon. « Secondes d'erreur cumulées » d'une fenêtre = moyenne de cette série sur la fenêtre × sa durée.
- Charge : un `TestRun` dans l'espace `k6`, manifeste et script dans `plateforme/resilience/continuite/`, étiquette **`testid=sonde-continuite-<CHG>`**, images par Harbor. C'est un instrument lancé pour une fenêtre, pas un état désiré : décide (et écris) s'il passe par Argo CD ou s'il est créé depuis `adm01` comme les expériences de chaos (ADR-0290).
- Tableau Grafana : UID **`f4-changement-en-cours`**.

**Travail demandé**

Objectifs :
1. Une **charge constante** qui joue l'utilisateur pendant des heures sans rien abîmer : lecture seule en production, écriture en recette ; elle ne s'arrête pas d'elle-même au premier incident.
2. Des **sondes externes** de continuité sur `mon01` pour les services listés, versionnées dans `plateforme/ansible`.
3. Une **mesure** unique (`continuite:en_erreur`), sa variante sans le cluster (témoin), leurs **tests** `promtool`, et un outil qui la relève pour une fenêtre donnée (secondes d'erreur, requêtes en erreur, p95, détail par sonde).
4. Un **tableau** « Changement en cours » : secondes d'erreur de la période affichée, état par sonde, taux d'erreurs, latence p95/p99 de MédiAgenda prod, budget d'erreur Pyrra, et l'indication que la charge tourne.
5. Une **documentation** : `docs/changements/sonde-continuite.md` (ce que mesure chaque instrument, ce qu'il ne voit pas, la requête de la mesure, les objectifs par défaut, l'exception « lecture en production » et qui l'a approuvée) et le runbook **RB-340** (lancer, suivre, arrêter, relever ; sans le cluster).
6. Une **répétition** : lance la sonde, provoque une erreur maîtrisée en **recette** (par exemple une réplique de l'API supprimée, ou une expérience de chaos du M29) et vérifie que la mesure la compte.

Contraintes :
- Aucune écriture en production ; lecture plafonnée et limitée à une route ; données factices en recette (créées puis supprimées).
- Rien à la main sur `mon01` ni dans Prometheus : rôle `supervision_temoin`, `plateforme/observabilite` (MR, `promtool` en CI).
- La mesure doit rester calculable quand `k8s-par1` est arrêté (S08).

Livrables : MR dans `plateforme/resilience`, `plateforme/ansible`, `plateforme/observabilite`, `plateforme/medisphere` ; fiche CHG-3402 (changement standard).

**Critères de réussite**
- [ ] Le témoin de `mon01` voit des sondes `continuite-*` étiquetées `service=mediagenda`, `medidoc`, `rabbitmq`, `portail`, vertes en temps normal, et enregistre `continuite:sondes_en_erreur:max` ; le cluster reçoit cette série par la fédération.
- [ ] La `PrometheusRule` `continuite` enregistre `continuite:en_erreur` toutes les 15 s ; ses tests `promtool` sont sur `main` de `plateforme/observabilite` (dossier `tests/`, convention du M21).
- [ ] Le tableau `f4-changement-en-cours` existe et montre la mesure, les sondes, la latence p95/p99 et le budget d'erreur.
- [ ] Un `TestRun` de la sonde (testid `sonde-continuite-…`, image Harbor) et son script (lecture en prod, écriture en recette, débit constant) sont sur `main` de `plateforme/resilience`, et la charge a déjà alimenté Prometheus.
- [ ] `sonde-continuite.md` et RB-340 sont publiés.

**Vérification** : `lab/bin/check F4 2`

<details><summary>Indice 1</summary>

Trois signaux, trois résolutions : k6 envoie ses points toutes les quelques secondes, les sondes de `mon01` tournent à l'intervalle du job `blackbox`, les compteurs de MédiAgenda sont collectés toutes les 30 s. Une série 0/1 évaluée à pas fixe les ramène à une même grille ; `avg_over_time` sur la fenêtre en donne la part en erreur, que tu convertis en secondes. Pense au cas « aucune erreur n'a jamais eu lieu » : une série qui n'existe pas n'est pas un zéro (`or vector(0)`).
</details>

<details><summary>Indice 2</summary>

Une série enregistrée sur le témoin garde les étiquettes de l'expression : si elle garde `job="blackbox"`, la fédération du M21 l'emporte sans rien y changer. Côté k6, l'étiquette `expected_response` distingue les réponses attendues (selon `responseCallback`) des autres ; vérifie qu'elle arrive bien dans Prometheus avec ta version de k6. Un exécuteur `constant-arrival-rate` garde un débit fixe même quand les réponses ralentissent : c'est ce qu'on veut d'une sonde.
</details>

<details><summary>Indice 3</summary>

Pour vérifier que ta mesure compte juste, provoque une erreur dont tu connais la durée (une sonde dont tu changes la cible pendant deux minutes dans un groupe d'essai, ou une expérience de chaos de la recette avec une `duration` connue) et compare. Une mesure qui donne zéro pendant une coupure réelle est pire que pas de mesure.
</details>

**Pour aller plus loin** (facultatif) : annotations Grafana automatiques au début et à la fin de chaque fenêtre (API d'annotations, depuis l'outil de lancement de la sonde) ; une sonde de continuité **depuis PAR2** (`pbs01` ou une VM de `hp01`) pour voir ce qu'un utilisateur extérieur verrait ; histogrammes natifs de k6 pour une latence exacte côté client.
