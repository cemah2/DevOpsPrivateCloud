# Final F5 — Phase 3 : L'exercice

Le site de repli existe, le runbook est écrit, la cellule de crise est nommée. Reste à le prouver. Une répétition à blanc d'abord, sans toucher à PAR1, pour débusquer ce qui ne marche que sur le papier. Puis le jour J : PAR1 disparaît, et l'horloge tourne. Ensuite, il faudra tenir — un site de repli n'est pas fait pour durer, et pourtant les cabinets, eux, continuent de travailler.

Prérequis de la phase : phases 1 et 2 terminées (`lab/bin/check F5 3` à `lab/bin/check F5 7` verts), date de l'exercice annoncée aux métiers par Claire, enveloppe de reprise (S05) **en main**.

> ⚠️ **Attention** : pendant l'exercice, `hp01` porte à la fois **toutes les sauvegardes du lab** et **toute la production**. Avant S09 : vérifie qu'aucun travail de vérification ni d'élagage de PBS n'est prévu dans la journée, que la mémoire libre de `hp01` couvre le passage de ≈ 8 à ≈ 10 Go de VMs (PLAN §4.15), et que les sauvegardes de la nuit précédente sont vertes. Si ton stockage `pbs-par2` de `pve01` passe par le tunnel `wg0`, **aucune sauvegarde de PAR1 n'aboutira pendant l'isolement** : choisis une journée où ce n'est pas grave, et lance une sauvegarde complète de PAR1 juste après le retour (S12).

---

### F5-S08 — Panne : la reprise qui ne reprend pas  `BF` `★★★`

> **Ticket INC-6108** — *De : Karim Benali* — *Copie : Nadia Roussel, Claire Morel*
> Avant de couper quoi que ce soit, on fait une répétition à blanc : tout RB-350 qui ne touche pas à PAR1. Contrôles de préparation, démarrage du coffre de secours, démarrage d'essai des applications à PAR2, relevé du témoin. Si quelque chose casse aujourd'hui, tant mieux : c'est aujourd'hui qu'il faut que ça casse. Lance `lab/bin/break F5 8`, je te dis ce que je vois.

**Objectifs pédagogiques**
- Répéter une bascule sans risque pour la production, et lire ce qu'une répétition révèle.
- Diagnostiquer une panne du site de repli à partir de son seul symptôme, sans PAR1 comme référence.
- Transformer chaque panne trouvée en contrôle de préparation automatique (prévention).

**Prérequis** : F5-S03 à F5-S07 (RB-350, RB-355, RB-356).
**Durée indicative** : 3 h (répétition, diagnostic, compte rendu).

**Contexte technique**
- Injection depuis `adm01` : `lab/bin/break F5 8` ; abandon : `lab/bin/break F5 8 --annuler`. Le contrôle préalable exige PAR2 prêt (dns03, reg02, réplication de `s3-02`, nœud de `k8s-par2`, `bao-par2` arrêté et démarrable, `mediagenda-db-par2` réplique saine) ; sinon l'injection est refusée.
- La panne ne touche **que** des objets de PAR2 (VMs du pool `par2`, `k8s-par2`) ; jamais PAR1, ni le datastore `ds-lab`, ni la configuration de PBS, ni le réseau de `hp01`.
- Le kubeconfig d'administration de `k8s-par2` est attendu sur `adm01` en `~/.kube/k8s-par2.config` (variable `WB_F5_PAR2_ADMIN_KUBECONFIG`).
- Une répétition qui démarre `bao-par2` et restaure `kms01` en 3501 suit RB-355 : remets tout en veille à la fin (3501 détruite, `bao-par2` arrêté).
- Compte rendu attendu : `docs/pra/exercices/2026-exercice-1/repetition.md`.

**Travail demandé**
1. Déroule la répétition à blanc (la partie de RB-350 qui ne touche pas PAR1) et note chaque étape avec son heure.
2. Lance `lab/bin/break F5 8`, lis le symptôme, diagnostique, répare.
3. Rejoue l'étape qui avait échoué, puis remets PAR2 en veille.
4. Écris le compte rendu : constat, chronologie, cause, réparation, et surtout **prévention** : quel contrôle de préparation (automatique, alerté) l'aurait vu avant la répétition. Corrige RB-350 si une étape manquait.

**Critères de réussite**
- [ ] `s3-02` réplique de nouveau depuis `s3-01` (unité `filer.sync` active).
- [ ] Le nœud `k8s-par2-n01` est `Ready` et planifiable.
- [ ] La VM 1055 (`bao-par2`) ne porte aucun verrou et est arrêtée (veille).
- [ ] `mediagenda-db-par2` est une réplique saine ; dns03 et reg02 répondent.
- [ ] `repetition.md` est sur `main` avec INC-6108, la cause, la réparation et la prévention.

**Vérification** : `lab/bin/check F5 8`
**Temps cible** : 45 min à 1 h pour le diagnostic et la réparation.

<details><summary>Indice 1</summary>

Une répétition « verte » ne prouve rien si l'on ne regarde que les processus. Regarde l'effet : l'âge de la dernière donnée arrivée à PAR2, la capacité réelle à planifier un pod, la capacité réelle à démarrer une VM. Le symptôme te dit laquelle des trois regarder.
</details>

<details><summary>Indice 2</summary>

Trois commandes de diagnostic suffisent à départager : `systemctl` sur la machine qui reçoit les données, `kubectl describe` sur un pod en attente (les événements disent pourquoi il ne se place pas), `qm config` sur la VM qui ne démarre pas (une ligne de plus que d'habitude ?).
</details>

<details><summary>Indice 3</summary>

Après la réparation, demande-toi pourquoi aucune alerte n'a sonné : le retard de réplication est-il mesuré **côté destination** (S04) ? Un nœud non planifiable déclenche-t-il quelque chose ? Un verrou sur une VM arrêtée se voit-il quelque part ? Chacune de ces questions est une ligne du contrôle de préparation.
</details>

**Pour aller plus loin** (facultatif) : un script `controle-preparation` lancé chaque nuit (et au début de RB-350) qui vérifie tous les voyants de PAR2 et publie un indicateur unique « PAR2 prêt » ; le rejouer après chaque changement de PAR2.

---

### F5-S09 — Le sinistre : perte de PAR1  `CHRONO` `★★★★`

> **Ticket INC-6109** — *De : Claire Morel* — *À : la cellule de crise*
> C'est le jour. Je ne vous dirai pas l'heure. Quand PAR1 tombera, Nadia ouvre la cellule, je décide du déclenchement selon nos critères, et vous appliquez RB-350, rien que RB-350 — si le runbook se trompe, on le note et on décide, on n'improvise pas en silence. Sophie relève tout. À la fin, je veux deux nombres que personne ne pourra contester : à quelle heure les patients ont repris rendez-vous, et combien de rendez-vous on a perdus.

**Objectifs pédagogiques**
- Déclarer un sinistre et conduire une bascule sous contrainte de temps, en suivant un runbook et une organisation de crise.
- Mesurer, et non estimer, le RTO de chaque application et le RPO de MédiAgenda.
- Tenir une main courante qui servira de preuve au rapport d'exercice.

**Prérequis** : F5-S08 (`lab/bin/check F5 8` vert, répétition faite) ; RB-350, RB-355, RB-356, `cellule-de-crise.md` ; sur ton poste, le VPN de secours `wg1` de `hp01` (10.255.3.0/24, UDP 51823) **essayé** ; sur `adm02`, le dépôt du workbook cloné depuis GitHub avec son `lab/lab.env` et un clone de travail de `plateforme/medisphere` (`~/medisphere`).
**Durée indicative** : 1 h de préparation, puis **4 h chronométrées** (la durée limite s'affiche à l'injection) ; MédiDoc et Legacy-RDV peuvent finir pendant S11, dans leur propre objectif.

**Contexte technique**
- Le sinistre est **simulé par isolement** : `lab/bin/break F5 9`, lancé depuis `adm01` par la personne qui joue « le destin » (toi, si tu es seul : lance-le à une heure tirée au hasard). La bordure de PAR1 coupe la liaison `wg0` vers PAR2, le VPN `wg1` de PAR1 et les accès au lab depuis le LAN (sauf `pve01`). **Aucune VM de PAR1 n'est arrêtée** : PAR1 continue de tourner, seul, sans que personne le voie.
- Le contrôle préalable refuse l'injection si PAR2 n'est pas prêt, si le témoin ne tourne pas, si la sonde `ms-sonde-pra` est arrêtée, si `wg1` de `hp01` manque, ou si `pve01` ne joint pas `gw01` **et** `gw02` (l'annulation, en S12, se fait depuis `pve01`).
- **Règle du jeu** : à partir de T0, PAR1 n'existe plus. Ni VPN de PAR1, ni `adm01`, ni `pve01` (« il est dans la salle »). Seule exception : une urgence réelle du lab, décidée par écrit dans la main courante avec l'accord de Sophie — et l'exercice est alors noté comme interrompu.
- T0 est écrit par l'injection dans `/var/lib/workbook/f5-t0` de `adm02` (et dans la main courante de ton clone de travail, s'il existe). C'est l'heure de référence du RTO et du RPO.
- **Mesures** : la sonde `ms-sonde-pra` de `adm02` écrit toutes les 15 s `horodatage_utc,cible,code_http,latence_ms,site` dans `/var/lib/ms-sonde-pra/mesures.csv`. RTO d'une application = première réponse 2xx servie par `par2` sur son nom global − T0. RPO de MédiAgenda = horodatage du dernier témoin `PRA-TEMOIN` écrit à PAR1 avant T0 − horodatage du dernier témoin retrouvé à PAR2.
- Objectifs de référence (S01, à remplacer par les tiens) : MédiAgenda RTO 4 h / RPO 15 min ; MédiDoc RTO 8 h / RPO 1 h ; Legacy-RDV RTO 8 h / RPO 24 h ; MédiNotif RTO 8 h (S11). Le check lit les objectifs dans `WB_F5_RTO_MEDIAGENDA_MIN`, `WB_F5_RTO_MEDIDOC_MIN`, `WB_F5_RTO_RDV_MIN` (minutes).
- Pendant le PRA, la documentation se tient dans le **miroir** de `plateforme/medisphere` sur `adm02` (branche `main`, poussée depuis ton clone de travail, comme le prévoit RB-350). La main courante : `docs/pra/journal/<AAAA-MM-JJ>.md`, une ligne `- HH:MM INC-6109 [type] texte`, types `ouverture`, `état`, `action`, `décision`, `mesure`, `clôture`.
- Les checks de S09 à S11 se lancent **depuis `adm02`** : `admin@adm02:~/DevOpsPrivateCloud$ lab/bin/check F5 9`.

**Travail demandé**

Objectifs :
1. **Détecter et déclarer** : constater la perte, ouvrir INC-6109, réunir la cellule, faire décider Claire selon le critère de RB-350, consigner l'heure et l'auteur de la décision.
2. **Basculer** selon RB-350 : coffre, base, applications, noms globaux, dans l'ordre et avec les conditions de passage du runbook. Chaque écart au runbook est une entrée `[décision]` de la main courante.
3. **Mesurer** : RTO de MédiAgenda, MédiDoc et Legacy-RDV (sonde), RPO de MédiAgenda (témoin), consignés en entrées `[mesure]` ; le témoin de PAR2 reprend son écriture.
4. **Informer** : les messages d'état prévus par `cellule-de-crise.md`, par des canaux qui ne dépendent pas de PAR1, au rythme prévu.

Contraintes :
- Pas d'accès à PAR1 (voir la règle du jeu). Pas de corrigé ouvert pendant le chronomètre.
- La base de PAR2 n'est promue qu'après la décision de Claire, et la main courante dit ce que cette promotion rend irréversible.
- Aucun secret dans la main courante ni dans les messages.

**Critères de réussite**
- [ ] PAR1 reste injoignable depuis PAR2 pendant toute la phase (l'isolement n'est pas levé).
- [ ] dns03 publie `mediagenda.medisphere.internal`, `medidoc.medisphere.internal` et `rdv.medisphere.internal` vers `*.apps.par2.medisphere.internal`, avec un TTL court.
- [ ] Les trois noms répondent en 2xx avec `X-MediSphere-Site: par2`.
- [ ] RTO mesurés par la sonde sous les objectifs (MédiAgenda dans le chronomètre).
- [ ] `mediagenda-db-par2` est primaire et sain ; `temoin-rpo` tourne à PAR2 depuis la reprise.
- [ ] La main courante INC-6109 (au moins 8 entrées) contient l'ouverture, la décision de déclenchement, le RTO de MédiAgenda et le RPO mesuré (valeur chiffrée).

**Vérification** : `lab/bin/check F5 9` (depuis `adm02`)
**Temps limite** : 4 h à partir de T0 pour MédiAgenda (le chronomètre s'affiche à l'injection).

<details><summary>Indice 1</summary>

Les premières minutes ne sont pas techniques : ouvre la main courante, note T0, appelle la cellule, vérifie ton accès à PAR2. Une bascule commencée sans décision est une faute de procédure, même si elle réussit. Et pendant que tu attends la décision, rien ne t'empêche de **préparer** ce qui ne crée pas de point de non-retour.
</details>

<details><summary>Indice 2</summary>

Une promotion sans jeton de rétrogradation est la seule possible ici : PAR1 n'a pas été rétrogradé, et ne peut pas l'être. Relis ce que la documentation de CloudNativePG en dit, et ce que cela implique pour le retour (S12). Côté DNS, une zone secondaire de PowerDNS ne se modifie pas tant qu'elle reste secondaire.
</details>

<details><summary>Indice 3</summary>

Pour le RPO, deux requêtes suffisent : le dernier témoin retrouvé à PAR2 (une fois la base promue), et le dernier témoin écrit à PAR1 **avant T0** — que tu ne peux pas lire à PAR1 aujourd'hui. Avec un témoin par minute, que vaut la seconde valeur ? Note l'hypothèse ; S12 te donnera la vraie valeur.
</details>

**Pour aller plus loin** (facultatif) : faire jouer la cellule à plusieurs (un ami tient le rôle de Claire et décide à partir de tes messages d'état seulement) ; enregistrer le terminal (`script`) pour la preuve.

---

### F5-S10 — Panne : les surprises de la crise  `BF` `★★★★`

> **Ticket INC-6110** — *De : Nadia Roussel* — *Copie : la cellule de crise*
> Ça tenait depuis le déclenchement, et voilà que quelque chose lâche à PAR2. On est seuls : pas de PAR1 pour comparer, pas de supervision complète, pas de collègue d'astreinte de l'autre côté. Tu traites comme un incident dans l'incident : ouverture, diagnostic, réparation, clôture, dans la même main courante. Lance `lab/bin/break F5 10` depuis `adm02`.

**Objectifs pédagogiques**
- Diagnostiquer, pendant un PRA, les pannes typiques d'un site de repli : dépendance oubliée, accès ou secret absent, horloge.
- Raisonner sans la référence du site principal et sans l'observabilité habituelle.
- Mener un incident imbriqué dans une crise sans perdre la trace de la crise.

**Prérequis** : F5-S09 en cours (`lab/bin/check F5 9` vert depuis `adm02`).
**Durée indicative** : 1 à 2 h.

**Contexte technique**
- Injection depuis `adm02` : `lab/bin/break F5 10` ; abandon : `lab/bin/break F5 10 --annuler`. Le contrôle préalable exige le sinistre en cours, les trois noms servis par PAR2, l'horloge de `s3-02` synchronisée et dns03 qui résout.
- `adm02` doit avoir les alias SSH de `s3-02` et `dns03` (compte `admin`, `sudo -n`).
- La panne ne touche que des VMs de PAR2 (configurations et services) ; aucune donnée n'est modifiée.
- INC-6110 se trace dans la **même** main courante que INC-6109 (entrées `INC-6110 [ouverture]` … `[clôture]`, avec la cause).

**Travail demandé**
1. Lance `lab/bin/break F5 10` depuis `adm02`, lis le symptôme.
2. Ouvre INC-6110 dans la main courante, qualifie son effet sur la crise (quelles applications, quel risque pour le RPO à venir).
3. Diagnostique, répare, vérifie les conséquences (ce qui a échoué pendant la panne s'est-il rattrapé tout seul ?).
4. Clos INC-6110 avec la cause et l'action de prévention (PLAT-35xx à ouvrir au retour).

**Critères de réussite**
- [ ] L'horloge de `s3-02` est synchronisée sur une source de PAR2 (écart < 5 s).
- [ ] dns03 résout les noms internes et les noms globaux par ses propres autoritaires, sans renvoi vers PAR1.
- [ ] `adm02` accepte le compte `miroir` en SSH ; Argo CD de `k8s-par2` n'a aucune Application en erreur.
- [ ] MédiDoc (servi par PAR2) est prêt ; `mediagenda-db-par2` archive ses WAL.
- [ ] INC-6110 est ouvert, sa cause écrite et clos dans la main courante.

**Vérification** : `lab/bin/check F5 10` (depuis `adm02`)
**Temps cible** : 45 min.

<details><summary>Indice 1</summary>

Le symptôme décrit un effet ; cherche la **première** chose qui a changé. Les journaux de la machine qui refuse (`journalctl` de son service, codes d'erreur S3, événements Argo CD) nomment souvent le mécanisme en clair.
</details>

<details><summary>Indice 2</summary>

Trois familles à vérifier, dans l'ordre du moins cher au plus cher : le temps (`chronyc tracking`, `date` comparé entre deux machines), les noms (`dig @10.20.20.11 …` et ce vers quoi le récurseur renvoie), les accès (`ssh -v` avec le compte concerné, `sshd -T`). Une configuration « de temps normal » rejouée sur PAR2 pendant un PRA réintroduit souvent une dépendance à PAR1.
</details>

**Pour aller plus loin** (facultatif) : rejoue `lab/bin/break F5 10` après réparation pour tirer une autre variante ; écris pour chacune la ligne du contrôle de préparation qui l'aurait vue avant le sinistre.

---

### F5-S11 — Tenir en mode dégradé  `LIBRE` `★★★`

> **Ticket PLAT-3511** — *De : Nadia Roussel* — *Copie : Claire Morel, Sophie Laurent, Julien Petit*
> La bascule est faite, bravo. Maintenant le plus long : PAR1 ne reviendra pas avant demain, peut-être plus. On ne fait pas tourner la production sans sauvegarde ni supervision, même à PAR2, même « juste un jour ». MédiNotif doit repartir dans son objectif, et les messages perdus doivent être rejoués sans spammer les patients. Et les demandes arrivent déjà : je te les transfère, il me faut une réponse écrite pour chacune.

**Objectifs pédagogiques**
- Organiser un mode dégradé : ce qui est rendu, ce qui ne l'est pas, ce qui est protégé, ce qui est surveillé, avec les moyens du site de repli.
- Protéger les données écrites pendant le PRA (elles n'existent qu'à PAR2).
- Arbitrer les demandes des métiers pendant une crise, par écrit.

**Prérequis** : F5-S09 (et S10 si joué) ; M27 (RabbitMQ, MédiNotif, rebut) ; M21 (règles d'alerte) ; M19 (Mailpit).
**Durée indicative** : 4 à 6 h, réparties sur au moins trois heures d'horloge pendant le PRA.

**Contexte technique**
- Tout PAR2 tient dans `hp01` : la base de PAR2, ses archives (`cnpg-k8s-par2` sur `s3-02`), les VMs et PBS partagent les mêmes disques. Le datastore `ds-lab` et sa configuration ne se modifient pas (PLAN §4.15).
- MédiNotif simule l'envoi (journal), consomme la file quorum `notifications` du vhost `medinotif-prod` ; MédiAgenda publie sur l'échange `notifications` (clé `notifications`) après validation de la transaction, et seulement si `MEDIAGENDA_AMQP_URL` est défini. Une demande : `{"type": "sms"|"mail", "destinataire": …, "modele": "confirmation", "rendez_vous_id": …}` ; les colonnes `canal_rappel` et `contact_rappel` de `rendez_vous` portent le choix du patient.
- Les messages restés dans le RabbitMQ de PAR1 au moment de T0 sont perdus pour PAR2 (objectif de S01 : rejouables depuis MédiAgenda).
- Le check attend une supervision minimale **joignable depuis `adm02`** : Prometheus (`WB_F5_PROM_PAR2_URL`, défaut `http://adm02.par2.medisphere.internal:9090`), Alertmanager (`WB_F5_AM_PAR2_URL`, défaut `:9093`), et une boîte de réception de secours Mailpit (`WB_F5_MAILPIT_PAR2_URL`, défaut `:8025`). Où les faire tourner (sur `adm02`, dans `k8s-par2`) est ton choix, dans la mémoire de PAR2.
- Demandes reçues par Nadia (à traiter toutes) :
  1. Julien : « Peut-on livrer ce soir le correctif d'affichage des créneaux prévu demain ? »
  2. Hugo Bernard (Data) : « L'extraction pseudonymisée de cette nuit pourra-t-elle tourner ? »
  3. Un cabinet, par le support : « J'ai pris un rendez-vous à 10 h 05 ce matin, je ne le retrouve plus. »
  4. Sophie : « Qui s'est connecté à quoi à PAR2 depuis ce matin ? Je veux pouvoir le montrer à l'auditeur. »
  5. La direction : « Quand revient-on à la normale ? »

**Travail demandé**

Objectifs :
1. **Sauvegarder PAR2** : la base de PAR2 archive en continu et a une sauvegarde de base postérieure à T0 ; les VMs de PAR2 ont une sauvegarde postérieure à T0 ; décide et écris ce qui protège ces copies d'une perte de `hp01` lui-même.
2. **Superviser a minima** : disponibilité des trois noms globaux, santé et archivage de la base de PAR2, mémoire et disque de `hp01` ; des alertes qui arrivent à quelqu'un pendant la crise.
3. **MédiNotif** : reprise dans son objectif, puis rejeu des notifications perdues, avec une règle écrite (fenêtre, doublons acceptés ou non, données personnelles jamais journalisées) validée par Julien.
4. **Les demandes des métiers** : une réponse écrite et datée pour chacune, avec sa justification (périmètre du PRA de S01, risque, capacité de PAR2).
5. **Le journal** : main courante tenue (messages d'état au rythme de `cellule-de-crise.md`), et `docs/pra/exercices/2026-exercice-1/mode-degrade.md` : ce qui est ouvert et fermé, les décisions, les sauvegardes, la supervision, les réponses aux demandes.

Contraintes :
- Aucun service hors du périmètre du PRA démarré à PAR2 sans décision écrite de Claire (mémoire de `hp01`).
- Aucune modification de `ds-lab` ni de la configuration de PBS ; aucune purge de données à PAR2.
- Aucune donnée personnelle (contact, nom de patient) dans la main courante, les journaux du rejeu ou les messages.

**Critères de réussite**
- [ ] `mediagenda-db-par2` archive ses WAL, a une sauvegarde de base terminée après T0 et une sauvegarde planifiée active.
- [ ] Une sauvegarde vzdump réussie depuis T0 existe sur `hp01`.
- [ ] Le Prometheus de PAR2 a au moins quatre cibles actives et des alertes sur la base et sur la disponibilité ; Alertmanager répond ; Mailpit de secours a reçu au moins un message depuis T0.
- [ ] Le worker MédiNotif tourne à PAR2.
- [ ] `mode-degrade.md` est poussé dans le miroir et traite les sauvegardes, la supervision, les décisions et les demandes ; la main courante couvre au moins trois heures différentes.

**Vérification** : `lab/bin/check F5 11` (depuis `adm02`)

<details><summary>Indice 1</summary>

Une sauvegarde sur le même disque que l'original protège d'une erreur humaine, pas d'une panne de matériel. Avec `hp01` seul, qu'est-ce qui peut sortir du bâtiment, chiffré, sans dépendre de PAR1 ? PBS sait aussi travailler avec des datastores amovibles ; un compartiment chiffré ailleurs est une autre réponse. Écris le risque que tu acceptes.
</details>

<details><summary>Indice 2</summary>

Pour le rejeu, la fenêtre se calcule à partir des deux bornes que tu connais : le dernier témoin retrouvé à PAR2 (avant lui, PAR1 a vraisemblablement publié et MédiNotif consommé) et l'heure où MédiAgenda a recommencé à publier à PAR2. Entre les deux, chaque rendez-vous dont `canal_rappel` n'est pas `aucun` mérite une confirmation — mais pas les témoins.
</details>

<details><summary>Indice 3</summary>

La demande 3 est un test de ton RPO : où ce rendez-vous peut-il se trouver ? Ne promets rien que la base de PAR2 ne contienne. La demande 2 relève du périmètre de S01 ; la demande 1, de la politique de changement en crise.
</details>

**Pour aller plus loin** (facultatif) : un tableau de bord d'une page (Grafana sur `adm02` ou page statique générée par la sonde) partagé avec la direction ; une rotation de la cellule (passation écrite entre deux « équipes »).
