# Final F3 — Phase 2 : lundi

Le téléphone sonne avant toute alerte. Un incident, puis la question que posera forcément ta responsable : pourquoi est-ce le support qui nous a prévenus ?

Pour chaque incident : main courante (`[ouverture]` dès le premier appel), gravité selon ta procédure (S02), messages d'état au rythme qu'elle fixe (courriel `[INC-59XX] …` + entrée `[état]`), décisions consignées, correction **par le code**, puis `lab/bin/check F3 <XX>` et `lab/bin/break F3 <XX> --annuler` pour clore. Rappel des règles : [`00-introduction.md`](00-introduction.md).

---

### F3-S03 — Lundi : « MédiAgenda rame »  `BF` `★★★`

> **Ticket INC-5903** — *De : support MédiSphère (file de Nadia Roussel)*
> *(Le détail s'affiche à l'injection : des cabinets se plaignent de la lenteur de MédiAgenda en production, lundi 9 h 10.)*

**Objectifs pédagogiques**
- Partir du symptôme utilisateur et le mesurer soi-même avant toute hypothèse.
- Descendre les couches d'une requête de MédiAgenda (Gateway, API, cache Valkey, pooler PgBouncer, PostgreSQL, ressources du pod) en cherchant où le temps se perd.
- Rétablir la production sans perte de données, puis empêcher la récidive par le code.

**Prérequis** : F3-S01, F3-S02 ; M21 (tableaux et règles de MédiAgenda), M22 (journaux), M27 (CloudNativePG, Pooler, Valkey), M28 (HPA, VPA).
**Durée indicative** : 45 min (temps cible) jusqu'au rétablissement, puis 1 h 30 pour la correction durable et la trace.

**Contexte technique**
- Environnement touché : **production** (`mediagenda-prod`, `https://mediagenda.apps.par1.medisphere.internal`). MédiAgenda passe par le pooler `mediagenda-db-pooler-rw` (PgBouncer, mode transaction), met les créneaux en cache dans Valkey 60 s, et `/pret` ne vérifie que la joignabilité de PostgreSQL et de Valkey.
- L'injection mesure d'abord la latence de référence, et lance une sauvegarde CloudNativePG de la production si la dernière a plus de 26 h (jusqu'à 20 min d'attente).
- Le check mesure lui-même, depuis `adm01`, des consultations de créneaux qui **manquent** le cache (praticien fictif `sonde-f3-…`) : médiane attendue sous 1 s.
- Toute action en production est précédée d'une entrée `[décision]` ; aucun redémarrage « pour voir ».

**Injection** : `lab/bin/break F3 3` (3 variantes).

**Travail demandé**
1. Ouvre INC-5903, qualifie la gravité, envoie le premier message d'état dans le délai de ta procédure.
2. Mesure : où le temps est-il perdu ? Situe l'étage avant d'agir.
3. Rétablis le service par le geste le moins risqué, décision consignée.
4. Trouve la cause racine et son origine (qui, quoi, quand, par quel chemin), corrige ou empêche la récidive **par le code** (MR), ouvre les tickets `PLAT-3303…` pour ce qui reste.
5. Écris **RB-330** « MédiAgenda lent en production » (`docs/exploitation/runbooks/`) : mesures, arbre de décision par étage, gestes sûrs en production.
6. Clôture : message de fin, entrée `[clôture]`, main courante publiée.

**Critères de réussite**
- [ ] Les consultations de créneaux qui manquent le cache répondent en moins de 1 s (médiane) en production.
- [ ] Aucune session n'attend un verrou ni ne garde une transaction ouverte depuis plus de 5 min ; aucun client n'attend dans le pooler ; Valkey a sa mémoire et n'évince pas en continu ; les pods de l'API ont les ressources de leur gabarit.
- [ ] Le contrôle de santé du lab est vert.
- [ ] INC-5903 est ouvert et clos dans la main courante, avec au moins un message d'état consigné et envoyé par courriel ; RB-330 est publié.

**Vérification** : `lab/bin/check F3 3`

<details><summary>Indice 1</summary>

Compare une consultation qui touche le cache et une qui le manque (même jour, deux praticiens), puis `/pret`. Si les deux sont lentes, le problème est avant la base ; si seule la seconde l'est, regarde ce qui se passe entre l'API et PostgreSQL ; si rien n'est lent pour une requête isolée mais tout l'est sous charge, regarde les ressources. Les tableaux du M21 (MédiAgenda) et du M27 (données) montrent chaque étage.
</details>

<details><summary>Indice 2</summary>

Dans PostgreSQL : `pg_stat_activity` (état, `wait_event_type`, `application_name`, `xact_start`) et `pg_blocking_pids()`. Dans le pooler : `SHOW POOLS;` (`cl_waiting`, `maxwait`). Dans Valkey : `INFO stats` et `INFO memory`, `CONFIG GET maxmemory*`. Côté Kubernetes : compare les ressources **réelles** des pods avec celles de leur gabarit, et lis les métriques de bridage CPU.
</details>

<details><summary>Indice 3</summary>

Le geste qui rétablit n'est pas toujours celui qui corrige. Un réglage fait « à chaud » disparaît au prochain redémarrage — ou pas ; un pod recréé reprend son gabarit ; une session se termine sans redémarrer la base. Demande-toi aussi **par quel chemin** la cause est arrivée en production : c'est ce chemin que la correction par le code doit fermer.
</details>

**Pour aller plus loin** (facultatif) : ajoute à MédiAgenda (par MR dans `mediagenda/deploiement`) un `statement_timeout` et un `lock_timeout` pour le rôle de l'API, et mesure ce que deviendrait cet incident avec eux.

---

### F3-S04 — Lundi : pourquoi personne n'a été prévenu ?  `BF` `★★★★`

> **Ticket INC-5904** — *De : Claire Morel*
> *(Le détail s'affiche à l'injection : pendant la lenteur du matin, ni l'astreinte ni l'équipe de MédiAgenda n'ont reçu d'alerte.)*

**Objectifs pédagogiques**
- Remonter la chaîne d'une alerte étage par étage (règle et son `for`, évaluation, envoi à l'Alertmanager, route, mise en sourdine, récepteur, courriel) et situer la rupture.
- Distinguer « l'alerte n'existe pas », « elle est en attente », « elle est éteinte » et « elle part ailleurs ».
- Prouver la réparation par un essai **qui suit le vrai chemin**, et la protéger par la CI.

**Prérequis** : F3-S03 **clos** ; M21 (règles de MédiAgenda, routes, silences, inhibitions, essais de routage en CI, témoin `mon01`).
**Durée indicative** : 1 h 30 (temps cible).

**Contexte technique**
- Cet incident est **en chaîne** avec S03 : il s'injecte après la clôture de S03, mais pose l'état dans lequel était la chaîne d'alerte lundi matin. Tu enquêtes donc « après coup » sur un état toujours présent.
- La configuration d'alerte vit dans `plateforme/observabilite` (règles `regles/`, Alertmanager dans `kps/values.yaml`, essais de routage `alertmanager/routes-tests.txt` joués par la CI) et est déployée par Argo CD ; les silences vivent dans l'Alertmanager du cluster (`http://alertmanager.apps.par1.medisphere.internal:9093`).
- Le *dead man's switch* de `mon01` n'est pas en cause et doit le rester.
- Ce que le check rejoue : l'arbre de routage de la configuration **chargée** (par `amtool`), les règles **chargées** dans Prometheus, les silences **actifs**.

**Injection** : `lab/bin/break F3 4` (3 variantes ; jusqu'à 15 min : certaines passent par un commit et la synchronisation d'Argo CD).

**Travail demandé**
1. Ouvre INC-5904 (gravité : à toi de la justifier — personne n'est impacté en ce moment, mais la plateforme est aveugle).
2. Reconstitue ce qui aurait dû se passer lundi matin (quelle règle, quel seuil, quel délai, quelle route, quel destinataire) et trouve l'étage qui a rompu, sa cause, son auteur, sa date.
3. Répare par le chemin normal (MR, ou geste documenté s'il n'y a pas de code en cause) ; prouve-le par une alerte d'essai qui suit **la vraie** route de MédiAgenda production.
4. Prévention : un essai de routage (ou de règle) en CI qui aurait attrapé cette panne ; une ligne dans ta procédure ou dans RB-331 sur ce qui aurait dû alerter (silences longs, routes vers `null`, `for` démesurés).
5. Écris **RB-331** « Une alerte n'est pas arrivée ». Pose la question qui fâche par un ticket `PLAT-3304` : la lenteur de lundi aurait-elle dû **réveiller** quelqu'un, avec les règles telles qu'elles étaient avant la panne ?

**Critères de réussite**
- [ ] Dans la configuration chargée, une alerte critique de MédiAgenda production va à `astreinte-mail` **et** à `mediagenda-mail` ; l'avertissement de latence de production va à `mediagenda-mail`.
- [ ] Les règles `MediagendaLatenceElevee` et `MediagendaTauxErreurEleve` (critique) de production sont chargées avec un délai `for` de 30 min au plus.
- [ ] Aucun silence actif de plus de 24 h ne couvre les alertes de MédiAgenda production.
- [ ] Les essais de routage de la CI exigent qu'une critique de MédiAgenda production aille à l'astreinte ; le *dead man's switch* est intact.
- [ ] INC-5904 est ouvert et clos, avec au moins un message d'état consigné et envoyé ; RB-331 et PLAT-3304 existent.

**Vérification** : `lab/bin/check F3 4`

<details><summary>Indice 1</summary>

Commence par une seule requête qui classe la panne : pose une alerte d'essai avec **exactement** les étiquettes qu'aurait eues l'alerte de lundi, puis demande à l'API v2 de l'Alertmanager ce qu'elle en fait (`receivers`, `status.state`, `silencedBy`, `inhibitedBy`). Si rien n'arrive jusque-là, remonte vers Prometheus : la règle existe-t-elle, dans quel état est-elle (`/api/v1/rules`, `ALERTS`) ?
</details>

<details><summary>Indice 2</summary>

`git log -p` sur `plateforme/observabilite` depuis vendredi, et la liste des silences (y compris leur auteur, leur commentaire et leur fin). Un test vert ne prouve rien s'il a été modifié dans le même commit que ce qu'il teste.
</details>

<details><summary>Indice 3</summary>

Pour la question de PLAT-3304 : regarde la gravité de l'alerte de latence et ses intervalles de temps de route. Une alerte « avertissement » ne réveille personne la nuit par construction ; est-ce le bon choix pour la latence de la production ? Les SLO du M21 (Pyrra) donnent une autre manière d'y répondre.
</details>

**Pour aller plus loin** (facultatif) : ajoute au témoin de `mon01` une sonde « bout en bout » : une alerte d'essai envoyée chaque heure par la vraie route d'astreinte, et une alerte du témoin si le courriel n'est pas arrivé dans Mailpit.
