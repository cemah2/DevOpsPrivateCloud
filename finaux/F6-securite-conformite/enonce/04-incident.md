# Final F6 — Phase 4 : L'incident

Thomas Renaud, le DPO, l'avait demandé pendant l'audit : « Que se passe-t-il si des données de patients fuitent demain ? » La réponse arrive maintenant. D'abord, on vérifie qu'on est **prêt** (runbooks, kit, comptes de bris de glace, capacité de capture, exercice de table) — parce qu'un incident ne se prépare pas pendant qu'il a lieu. Ensuite, une alerte tombe sur un conteneur de recette : il faut **détecter, qualifier, confiner sans détruire les preuves, investiguer, éradiquer**, puis **décider** des notifications réglementaires et écrire un post-mortem qui cherche des mécanismes, pas des coupables.

Prérequis de la phase : F6-S08 et F6-S09 terminés (traçabilité inaltérable et gestion des vulnérabilités en place : c'est ce qui rendra l'enquête possible).

> **Simulation — à lire avant F6-S11** : l'incident est **entièrement inoffensif**. Le script d'injection ne contient **aucun code malveillant** : il rejoue des commandes ordinaires (un shell, une tentative de lecture du jeton de compte de service, une connexion sortante qui n'envoie aucun octet et, selon la variante, deux requêtes de lecture sur l'API ou des règles réseau trop larges) et crée un faux « centre de commande » `c2-simule01` qui ne fait que **journaliser** ce qu'il reçoit. Aucune donnée n'est lue ni envoyée, aucun binaire d'attaque n'existe. Traite-le comme si c'était réel.

> **Rappel — journal et notifications** : chaque geste va dans le dossier d'incident `docs/securite/incidents/INC-6211/` (chronologie horodatée UTC : une entrée par événement avec son heure, son type et sa source — en lignes `- HH:MM INC-6211 [type] texte` comme la main courante du F3, ou en tableau) ; les preuves vont dans `preuves-conformite/INC-6211/` (collecte par la procédure, empreintes recopiées dans la chronologie). Types d'entrée : `[ouverture]`, `[état]`, `[décision]`, `[action]`, `[clôture]`.

---

### F6-S10 — Prêts pour l'incident  `LIBRE` `★★★`

> **Ticket SEC-3610** — *De : Sophie Laurent (RSSI)* — *Copie : Thomas Renaud (DPO), Nadia Roussel, Claire Morel*
> Hélène Mercier a relevé **ECA-3605** : nous n'avons jamais testé notre réponse à un incident de sécurité, et nous n'avons pas de kit forensique prêt. RB-262 existe depuis le durcissement, mais il n'a servi qu'une fois, sur un pod d'essai. Je veux qu'on soit prêts **avant** que ça arrive : deux runbooks à jour (réponse à incident, forensique d'un conteneur), un kit rangé et vérifié, des comptes de bris de glace éprouvés, la certitude qu'on sait capturer un conteneur vivant, et un **exercice de table** avec l'équipe pour que personne ne découvre la procédure le jour J. Ferme l'écart avec les preuves.

**Objectifs pédagogiques**
- Transformer une procédure écrite en **capacité** opérationnelle : outils rangés, accès vérifiés, gestes répétés.
- Préparer la collecte forensique d'un conteneur (capture de l'état vivant) sans l'avoir improvisée.
- Conduire un exercice de table (*tabletop*) et en tirer des actions.

**Prérequis** : F6-S01 à F6-S09 ; M26 (RB-262 réponse à incident conteneur, quarantaine réseau, point de contrôle de conteneur), M24 (comptes de bris de glace, RB-240), F3 (main courante, format d'incident). F6-S02 et F6-S08 (preuves inaltérables).
**Durée indicative** : 4 à 6 h.

**Contexte technique**
- RB-262 (M26) couvre déjà l'isolement, la collecte et l'escalade. Le F6 en tire **deux** runbooks de niveau plateforme : **RB-360** (réponse à incident de sécurité, générique, au-dessus de RB-262) et **RB-361** (forensique d'un conteneur, le détail de la capture). Ne duplique pas RB-262 : référence-le, généralise-le.
- Kit forensique : ce qu'il faut sous la main (conteneur éphémère d'outils signé et à jour, identité de dépôt des preuves `preuves-conformite` en écriture sans suppression, modèles de chronologie et de manifeste, contacts d'escalade, commandes prêtes). Il doit être **rangé** (un endroit connu) et **vérifié** (les accès marchent, les images existent).
- Comptes de bris de glace : `admin.conf` de `k8s-par1`, `root@pam` de Proxmox, OpenBao (parts Shamir), Keycloak `kc-secours`, GitLab `root` — éprouvés **en lecture** (RB-240, M24), usage tracé et alerté (l'usage d'`admin.conf` fait sonner `AuditBrisDeGlace`) : un contrôle automatique quotidien ne s'en sert donc pas.
- Capture d'un conteneur vivant : point de contrôle du kubelet (`ContainerCheckpoint`, KEP-2008, M26) si le runtime le permet (containerd + CRIU), sinon copie du système de fichiers et des journaux. À **confirmer sur le lab** (déjà noté « à confirmer » au M26) : éprouve-le sur un pod d'essai et écris le résultat.
- Exercice de table : un scénario joué sur table (pas sur le lab) avec l'équipe, chronométré, qui révèle les trous (un accès qui manque, un contact introuvable, une étape ambiguë).
- Valeurs figées (lues par le check) : runbooks dans `docs/securite/incidents/runbooks/` (`RB-360-…`, `RB-361-…`) ; comptes rendus dans `docs/securite/incidents/exercices/` ; contrôle du kit `bin/ms-verifier-kit-forensique` de `plateforme/outils` ; identité de dépôt : fichier `s3-preuves-conformite-depot.env` (introduction).

**Travail demandé**

Objectifs :
1. **RB-360** « Réponse à incident de sécurité » (`docs/securite/incidents/runbooks/RB-360-reponse-incident.md`) : déclenchement, gravités, rôles (responsable, collecte, RSSI, DPO, communication, support), rythme des points, lien vers RB-361 et RB-262, et le volet **réglementaire** (quand on se pose la question CNIL/clients/CERT Santé, et qui décide).
2. **RB-361** « Forensique d'un conteneur » (`…/runbooks/RB-361-forensique-conteneur.md`) : l'ordre de collecte du plus volatil au plus durable, la capture de l'état vivant (point de contrôle **ou** copie), les empreintes, le dépôt dans `preuves-conformite`, et ce qu'on ne touche pas.
3. **Kit** rangé et **vérifié** : le contrôle `ms-verifier-kit-forensique`, planifié, qui prouve que l'image d'outils existe et est signée, que l'identité de dépôt des preuves écrit (et ne peut pas supprimer ce qu'elle a écrit), que les modèles sont présents ; les comptes de bris de glace s'éprouvent à la main, en lecture, selon RB-240.
4. **Capture éprouvée** sur un pod d'essai (point de contrôle si disponible, sinon copie), résultat écrit dans RB-361 (« à confirmer » résolu dans un sens ou l'autre).
5. **Exercice de table** : scénario, déroulé, trous trouvés, actions (responsable, échéance), compte rendu dans `docs/securite/incidents/exercices/<AAAA-MM>-exercice-table.md`.
6. **Fermer ECA-3605** : preuve de clôture au catalogue de `ms-preuves`, fiche close (en-tête : `clos-le`, `preuve:` = un lot déjà déposé).

Contraintes :
- Les comptes de bris de glace s'éprouvent **en lecture** seulement (RB-240) : un essai en écriture est une modification non tracée.
- La capture sur le pod d'essai ne doit pas le redémarrer (une sonde de vivacité qui tue le conteneur détruit la preuve).
- Rien n'est « prêt » tant qu'un contrôle automatisé ne le confirme : le kit se vérifie, il ne se déclare pas.

Livrables : MR dans `plateforme/medisphere` (runbooks, exercice), `plateforme/outils` ou `plateforme/k8s` (vérification du kit) ; `ECA-3605` clos.

**Critères de réussite**
- [ ] RB-360 et RB-361 sont sur `main`, cohérents avec RB-262, avec rôles, gravités, ordre de collecte et volet réglementaire.
- [ ] `ms-verifier-kit-forensique` est sur `main` de `plateforme/outils`, planifié, et passe : image d'outils signée présente, dépôt des preuves en écriture sans suppression possible, modèles présents.
- [ ] La capacité de capture d'un conteneur vivant est éprouvée et son résultat écrit dans RB-361 (point de contrôle ou copie).
- [ ] Le compte rendu de l'exercice de table est sur `main`, avec des actions datées.
- [ ] La fiche `ECA-3605` est close sur `main`, avec un lot de preuve antérieur à sa clôture.

**Vérification** : `lab/bin/check F6 10`

<details><summary>Indice 1</summary>

Ne réécris pas RB-262 : il contient déjà l'isolement (quarantaine), l'ordre de collecte et l'escalade. RB-360 est le niveau **au-dessus** (déclenchement, rôles, gravités, réglementaire, qui décide quoi) ; RB-361 est le niveau **en dessous** (le détail de la capture d'un conteneur). Les trois se citent.
</details>

<details><summary>Indice 2</summary>

« Prêt » est une propriété **vérifiable**, pas une déclaration. Écris le contrôle qui le prouve : l'image d'outils répond et sa signature est valide, l'identité de dépôt écrit un objet d'essai et échoue à le supprimer (attention : dans un compartiment versionné, que fait une suppression qui ne précise pas de version ?), les fichiers de modèle existent. Lance-le à froid : s'il passe au vert sans que rien ne soit prêt, il ne vérifie rien.
</details>

**Pour aller plus loin** (facultatif) : une « trousse d'astreinte sécurité » dérivée de celle du F3 ; un deuxième exercice de table joué par une personne qui n'a pas écrit la procédure (le meilleur test de clarté) ; l'intégration du point de contrôle de conteneur dans un pipeline de capture déclenché par une étiquette.

---

### F6-S11 — Panne : un conteneur compromis  `BF` `★★★★`

> **Alerte reçue sur `securite@`, puis `astreinte@`** — *transférée par Nadia Roussel, objet « Falco : activité anormale en recette ?! »*
> Courriels d'Alertmanager (source `falco`) pour l'espace `mediagenda-recette` : un **shell interactif** ouvert dans un conteneur de l'API, puis des **connexions sortantes** vers une adresse que personne ne reconnaît. Les alertes restent actives : la connexion se répète chaque minute. Aucune intervention n'a été annoncée. *(L'adresse de destination et le pod concerné s'affichent à l'injection ; vérifier qu'il s'agit bien de la recette et non d'une intervention légitime fait partie de la qualification.)*

**Objectifs pédagogiques**
- **Détecter** une activité anormale par la chaîne Falco/Tetragon → Alertmanager → Mailpit et la croiser avec le journal d'audit.
- **Qualifier** : vrai ou faux positif, quel vecteur, quelle portée.
- **Confiner sans détruire les preuves** : quarantaine réseau, pod sorti de son contrôleur, service rétabli par un pod sain, aucun redémarrage du conteneur suspect.

**Prérequis** : F6-S10 (RB-360, RB-361, kit), M26 (Falco 0.45, falcosidekick, Tetragon 1.7, quarantaine `quarantaine.yaml`, RB-262), M22 (Loki locataire `audit`), M21 (Alertmanager, Mailpit sur `mon01`), M15 (Hubble).
**Durée indicative** : 2 h à 2 h 30 (collecte comprise).

**Contexte technique**
- Espace **`mediagenda-recette`** uniquement (jamais la production). Les données de recette sont fictives ou pseudonymisées (vérifie-le : c'est une pièce de la décision de F6-S13).
- La politique de cluster `quarantaine` (M26-E33, `plateforme/k8s/composants/reseau/politiques/quarantaine.yaml`) s'applique à tout pod étiqueté `medisphere.internal/quarantaine=oui`. RB-262 et RB-361 décrivent l'ordre des gestes.
- Le « C2 » est une VM `c2-simule01` (VMID **3601**, VNet `vsandbox`, VLAN 99, **10.10.99.66**) **créée par le script d'injection** dans le pool `lab` : elle ne fait que **journaliser** les connexions qu'elle reçoit (horodatage, adresse source). Le script la détruit à l'annulation.
- ⚠️ **Ne supprime pas le pod suspect, ne redémarre pas son conteneur, ne lance rien dedans** avant la fin de la collecte. Ne désactive ni ne modifie Falco/Tetragon pour faire taire l'alerte. Un silence Alertmanager **ciblé et daté** sur le pod une fois isolé est permis (consigne-le).
- Compartiment de preuves : `preuves-conformite` (verrouillage d'objets, F6-S02/S08), identité de dépôt du kit (écrire et lister, jamais supprimer).

**Injection** : `lab/bin/break F6 11` (2 variantes de vecteur, tirées au hasard ; `--variante N` pour forcer). Temps cible : **60 min** jusqu'au confinement et à l'escalade ; la collecte peut déborder. Le lab doit être sain (Falco et Tetragon prêts, politique de quarantaine présente, un pod d'API prêt en recette, VMID 3601 libre), sinon l'injection refuse. `lab/bin/break F6 11 --annuler` retire tout ce que le script a créé ou modifié (y compris `c2-simule01`), sans supprimer le pod suspect (l'éradication est ton geste, F6-S12).

**Travail demandé**
1. Ouvre l'incident **INC-6211** dans `docs/securite/incidents/INC-6211/` ; dans les 15 premières minutes, **qualifie** (RB-360/RB-262) : quel pod, quel espace, quel nœud, quelle image, depuis quand, qui a ouvert le shell (audit de l'API), vers où partent les connexions, un changement annoncé l'explique-t-il ? Écris ta décision (vrai/faux positif) et sa justification.
2. **Confine** selon RB-262 : quarantaine réseau, pod sorti de son contrôleur, service de la recette rétabli par un pod sain ; vérifie que l'isolement n'a pas redémarré le conteneur.
3. **Préviens** Sophie Laurent (RSSI) et Thomas Renaud (DPO) dans le délai de RB-360, avec ce qu'il leur faut pour décider ; préviens Julien Petit (MédiAgenda).
4. Prépare la collecte pour F6-S12 (ne supprime rien) : la suite (chronologie complète, portée, éradication, retour) est le scénario suivant.

**Critères de réussite**
- [ ] Falco et Tetragon tournent sur tous les nœuds ; la politique de quarantaine est intacte.
- [ ] Le pod suspect de `mediagenda-recette` est étiqueté `medisphere.internal/quarantaine=oui`, sorti de son contrôleur, et derrière aucun Service ; son conteneur n'a pas redémarré.
- [ ] Le service de `mediagenda-recette` est rétabli (un pod sain a remplacé le suspect).
- [ ] Le dossier `INC-6211/` contient l'ouverture, la qualification (`[décision]`) et l'escalade à la RSSI et au DPO ; au moins un courriel d'état est parti (visible dans Mailpit).

**Vérification** : `lab/bin/check F6 11`

<details><summary>Indice 1</summary>

Trois sources, trois questions. Falco dit **ce qui** a déclenché une règle (shell, connexion) et Tetragon **tout** ce qui a été exécuté, arguments compris (y compris ce qu'aucune règle Falco n'a signalé) ; le journal d'audit de l'API (locataire `audit`, `{job="kubernetes-audit"}`) dit **qui** a appelé l'API, avec quelle identité, quel outil (`userAgent`) et depuis où ; Tetragon et Hubble disent **où** les paquets sont allés et s'ils ont été jetés ou non. Une identité de compte de service qui appelle l'API depuis l'extérieur du cluster est un indice.
</details>

<details><summary>Indice 2</summary>

Deux vecteurs possibles, qui changent la **portée**, pas les gestes de confinement : soit un jeton du compte de service de l'application a fuité et sert contre l'API (le pod en monte-t-il seulement un ? regarde aussi qui a **émis** des jetons pour ce compte), soit des **règles de sortie trop larges** (une vieille MR oubliée) ont laissé la connexion atteindre sa cible. Hubble te dit vite laquelle : la connexion vers le C2 est-elle `DROPPED` (refus par défaut tenu) ou `FORWARDED` (une politique l'autorise) ? Et si elle est autorisée dans le cluster, qu'est-ce qui la laisse passer ensuite ? La réponse oriente l'enquête de F6-S12.
</details>

<details><summary>Indice 3</summary>

Confiner sans détruire : étiquette de quarantaine d'abord (la politique posée à l'avance refuse entrée et sortie, sauf les sondes de l'hôte), puis retirer une étiquette du **sélecteur** du ReplicaSet pour sortir le pod de son contrôleur (le contrôleur recrée un pod sain, le suspect reste orphelin et isolé). Vérifie `restartCount` : il ne doit pas bouger. Ne supprime rien : la collecte, c'est F6-S12.
</details>

**Pour aller plus loin** (facultatif) : un silence Alertmanager ciblé et daté sur le pod isolé (pour ne plus recevoir l'alerte toutes les minutes sans masquer une nouvelle alerte ailleurs) ; une note d'une page pour la RSSI : ce qui est établi, ce qui ne l'est pas, ce qui reste à vérifier.

---

### F6-S12 — Investigation et éradication  `LIBRE` `★★★★`

> **Ticket INC-6211 (suite)** — *De : Sophie Laurent (RSSI)* — *Copie : Thomas Renaud (DPO), Karim Benali*
> Le conteneur est isolé, merci. Maintenant je veux **comprendre** : la chronologie depuis la première trace, comment on est entré, jusqu'où ça allait, ce qui a été touché, et la **preuve** que c'est fini. Pas une impression — une chronologie datée, des preuves rangées, une cause éradiquée, les secrets exposés tournés, et le service rendu propre. Thomas a besoin de savoir, pour sa décision, si des données de patients ont pu être lues ou sortir.

**Objectifs pédagogiques**
- Reconstruire une **chronologie** à partir de sources croisées inaltérables (audit de l'API, Falco, Tetragon, Hubble, journaux du C2).
- Déterminer la **portée** (accès possible, données touchées, latéralité) et distinguer ce qui est établi de ce qui ne l'est pas.
- **Éradiquer** la cause (pas seulement le symptôme) et **rétablir** proprement (rotation des secrets exposés, retour en service).

**Prérequis** : F6-S11 (incident ouvert, pod isolé, preuves collectées selon RB-361) ; M22 (locataire `audit`), M15 (Hubble), M25 (rotation des secrets OpenBao), M14 (comptes de service), F6-S08 (archive d'audit inaltérable).
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- Sources pour la chronologie : journal d'audit de l'API (locataire `audit`, `{job="kubernetes-audit"}`), événements Falco (locataire `audit`, envoyés par falcosidekick, M26) et Tetragon, flux Hubble, journaux de la bordure, et les **journaux du C2** `c2-simule01` (`/var/log/c2-simule.log` : ce qu'il a reçu, adresses source, horodatages) — lisibles sur la VM tant que l'injection n'est pas annulée.
- Portée : le pod suspect avait-il un jeton de compte de service monté ? un jeton de son compte a-t-il été émis et utilisé ailleurs ? quels droits ? quels Secrets montés ou variables d'environnement sensibles (quelles valeurs OpenBao) ? la connexion sortante a-t-elle **abouti** (Hubble : `FORWARDED`/`DROPPED`, journaux du C2) ? d'autres pods de la même image, du même compte ?
- Éradication : supprimer le pod suspect **après** la collecte et l'accord de la RSSI ; corriger la **cause** (selon le vecteur observé) et pas seulement le symptôme ; tourner dans OpenBao ce que le pod a pu voir.
- Retour : vérifier que le pod sain tourne, qu'aucune nouvelle alerte ne revient, que la connexion vers le C2 ne part plus.

**Travail demandé**
1. **Chronologie** (`INC-6211/chronologie.md`, la suite du journal ouvert en F6-S11) : de la première trace à l'isolement, chaque événement daté (UTC), sourcé (quelle source le prouve), avec les empreintes des preuves dans `preuves-conformite/INC-6211/`.
2. **Portée** : écris ce qui est **établi** (jeton lu, connexion tentée/aboutie, données accessibles) et ce qui **ne l'est pas** (données effectivement lues ou sorties). Appuie-toi sur Hubble et les journaux du C2 pour trancher l'aboutissement.
3. **Éradication de la cause** (pas du symptôme) : traite le vecteur réellement observé, partout où il existe (cluster, bordure, code). Supprime le pod suspect après la collecte.
4. **Rotation des secrets exposés** : tout ce que le pod a pu lire (jeton de compte de service, Secrets montés, identifiants OpenBao) est renouvelé ; écris ce qui a été tourné et pourquoi.
5. **Retour en service** : la recette tourne proprement, plus de connexion vers le C2, plus d'alerte ; consigne-le.
6. Quand tout est propre, **annule** l'injection (`lab/bin/break F6 11 --annuler`) : elle détruit `c2-simule01` et retire ce qu'elle a posé et que tu n'aurais pas déjà retiré. Relève d'abord les journaux du C2 comme preuve.

**Critères de réussite**
- [ ] `INC-6211/chronologie.md` est sur `main` : événements datés, sourcés, avec les empreintes des preuves.
- [ ] La portée distingue l'établi du non établi, et tranche l'aboutissement de la connexion sortante (Hubble / journaux du C2).
- [ ] La cause du vecteur observé est éradiquée (compte de service renouvelé, ce qui invalide ses jetons, ou règles de sortie trop larges retirées du cluster **et** de la bordure) ; le pod suspect est supprimé après collecte.
- [ ] Les secrets exposés sont tournés (trace OpenBao / nouveaux identifiants).
- [ ] La recette tourne (Rollout complet), aucune alerte Falco active sur l'espace, l'injection est annulée (`c2-simule01` détruite après relevé de ses journaux) ; consigné dans la chronologie.

**Vérification** : `lab/bin/check F6 12` (après l'annulation : le check lit l'état local laissé par l'injection, lance-le depuis le poste qui l'a injectée).

<details><summary>Indice 1</summary>

L'archive d'audit inaltérable de F6-S08 est faite pour ce moment : la chronologie se reconstruit avec des sources qu'on ne peut pas avoir retouchées. Commence par la première trace Falco, remonte le `kubectl exec` dans l'audit de l'API (quelle identité ?), puis les connexions dans Tetragon et Hubble, et confronte aux journaux du C2.
</details>

<details><summary>Indice 2</summary>

« Éradiquer la cause » dépend du vecteur de F6-S11. Un jeton lié ne se révoque pas un par un : qu'est-ce qui invalide **tous** les jetons d'un compte de service ? Et que pouvait-il ouvrir ailleurs (OpenBao, baux du moteur `database`) ? Si c'est une sortie trop large, cherche **chaque** couche qui l'a laissée passer, retire-les par le bon chemin, et vérifie que le refus par défaut est de nouveau tenu.
</details>

**Pour aller plus loin** (facultatif) : une règle de détection nouvelle issue de l'incident (Falco/Tetragon) ; un contrôle de dérive qui aurait vu la règle réseau trop large avant l'incident ; le retrait de la capacité d'`exec` humain hors bris de glace sur la recette aussi (comme la production, `prod-gestes-interactifs` du F3).

---

### F6-S13 — Notifications, communication et post-mortem  `RED` `★★★`

> **Ticket INC-6211 (suite)** — *De : Thomas Renaud (DPO)* — *Copie : Sophie Laurent (RSSI), Claire Morel*
> J'ai besoin d'une décision écrite, pas d'un avis en réunion. Au vu des preuves : est-ce une **violation de données personnelles** au sens du RGPD ? Faut-il notifier la **CNIL** sous 72 heures ? Faut-il informer nos **clients** (responsables de traitement) au titre du contrat HDS ? Y a-t-il un **signalement** d'incident grave à faire (CERT Santé) ? Et dans tous les cas, l'entrée au **registre des violations** (article 33.5), un message d'état pour l'interne, et un post-mortem **sans recherche de coupable**. Si la réponse est « non, pas de notification », je veux la démonstration, pas l'affirmation.

**Objectifs pédagogiques**
- Appliquer le RGPD (art. 33, 34, 33.5) et le cadre HDS/santé à un incident réel : décider de notifier **sur preuves**.
- Rédiger des notifications réglementaires exactes (CNIL, clients, signalement) ou justifier leur absence.
- Écrire un post-mortem qui cherche des mécanismes, avec des actions datées.

**Prérequis** : F6-S11 et F6-S12 terminés (chronologie, portée établie) ; [`annexes/versions-finaux-F5-F7.md`](../../../annexes/versions-finaux-F5-F7.md) (cadre réglementaire), RB-360.
**Durée indicative** : 2 h 30 à 3 h 30.

**Contexte technique**
- La décision se prend **sur les preuves de F6-S12** : données de recette fictives ou pseudonymisées ? accès à la production ? jeton/Secrets exposés donnant accès à des données réelles ? connexion sortante aboutie et données sorties, ou refusée ?
- Repères réglementaires (dans l'annexe ; **vérifie sur Légifrance** ce qui n'y est pas établi) : RGPD art. 33 (notification CNIL **72 h** sauf risque improbable, par le responsable de traitement ; obligations du sous-traitant envers lui), art. 34 (information des personnes si risque élevé), art. 33.5 (registre des violations **dans tous les cas**) ; HDS v2 (information contractuelle des clients) ; code de la santé publique art. L.1111-8-2 (signalement d'incident grave, portail, CERT Santé — **texte et périmètre à vérifier sur Légifrance**).
- Une violation « évitée » ou « sans conséquence » se consigne quand même au registre (art. 33.5) : c'est la trace qui prouve qu'on a analysé et décidé.

**Travail demandé**

Livre dans `docs/securite/incidents/INC-6211/` (MR relue par Sophie et Thomas) :
1. **`decision-notification.md`** : la décision motivée, point par point — violation de données personnelles (oui/non, pourquoi, sur quelles preuves de F6-S12) ; CNIL (notifier ou non, dans quel délai) ; personnes concernées (art. 34) ; clients HDS ; signalement CERT Santé. Chaque « non » est **démontré** par une preuve, pas affirmé.
2. **`registre-violations.md`** (ou l'entrée dans le registre existant) : l'entrée au titre de l'art. 33.5 (nature, catégories et nombre approximatif de personnes et d'enregistrements concernés, conséquences probables, mesures prises), même si aucune notification n'est due.
3. **Les notifications elles-mêmes** : soit les projets de notification (CNIL, client, signalement) prêts à envoyer **si** les faits l'exigeaient, soit, si elles ne sont pas dues, la version « pour mémoire » qui montre ce qu'on aurait envoyé — l'exercice est de savoir les rédiger.
4. **`message-etat.md`** : le message d'état interne (Claire, équipes), factuel, sans jargon, au rythme de RB-360.
5. **`post-mortem.md`** : chronologie (reprise de F6-S12), impact, cause racine (mécanisme, pas personne), ce qui a marché et ce qui a coûté, actions (responsable, échéance). Aucun nom de coupable.

**Contraintes**
- Décider sur preuves : une notification CNIL envoyée « par prudence » sur une recette fictive est une fausse alerte réglementaire ; une non-notification d'une vraie violation est une faute. L'enjeu est de **justifier**.
- Marque « à vérifier sur Légifrance » tout point réglementaire non établi dans l'annexe (notamment le signalement CERT Santé).
- Post-mortem sans recherche de coupable : les écarts sont des faits, les causes sont des mécanismes.

**Critères de réussite** (ce `RED` est publié : le check vérifie présence et contenu minimal)
- [ ] `decision-notification.md`, `registre-violations.md`, `message-etat.md` et `post-mortem.md` sont sur `main` dans `INC-6211/`.
- [ ] La décision CNIL est tranchée et **justifiée sur preuves** (référence à la portée établie en F6-S12).
- [ ] Le registre des violations (art. 33.5) est renseigné même en l'absence de notification.
- [ ] Le post-mortem a une cause racine formulée comme un mécanisme et des actions datées.

**Vérification** : `lab/bin/check F6 13` (présence et contenu minimal ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

La question n'est pas « y a-t-il eu une alerte ? » mais « des **données à caractère personnel** ont-elles été violées (confidentialité, intégrité, disponibilité) ? ». Reprends la portée de F6-S12 : si les données de recette sont fictives ou pseudonymisées, s'il n'y a pas eu d'accès à la production, et si la connexion sortante n'a rien emporté, il n'y a pas de violation de données personnelles — mais tu le **démontres** avec les preuves, et tu l'inscris quand même au registre.
</details>

<details><summary>Indice 2</summary>

Commence par le **rôle** de MédiSphère pour les données en cause : responsable de traitement (ses propres données) ou sous-traitant (les données de patients de ses clients, art. 28) ? Le RGPD ne donne pas les mêmes obligations aux deux (relis l'article 33 en entier, pas seulement son premier paragraphe). Ensuite, des régimes distincts : la **CNIL** (RGPD, si violation de données personnelles avec risque non improbable, 72 h), les **personnes** (art. 34, si risque élevé), les **clients** responsables de traitement (contrat HDS : ils doivent pouvoir faire leurs propres déclarations), et le **signalement** d'incident grave de sécurité d'un système d'information de santé (CERT Santé, art. L.1111-8-2 — périmètre exact **à vérifier sur Légifrance**). Un incident peut déclencher l'un sans les autres.
</details>

**Pour aller plus loin** (facultatif) : un modèle de notification CNIL réutilisable (champs du téléservice) ; un arbre de décision « faut-il notifier ? » versionné dans `docs/conformite/` ; la place de ce post-mortem dans la revue de suivi (F6-S14).

