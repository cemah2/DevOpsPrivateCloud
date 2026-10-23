# Final F6 — Phase 2 : Auditer

Lundi 16 novembre, 9 h. Hélène Mercier ouvre son ordinateur dans la petite salle que Sophie lui a réservée. Elle a lu la SoA, le périmètre, le catalogue des preuves et la revue des accès pendant le week-end. Elle a son compte de lecture. « Je vais vérifier que ce que vous avez écrit est vrai. Et vous, vous allez faire la même chose, avec vos outils. On compare vendredi. »

Prérequis de la phase : phase 1 terminée (SoA, `ms-preuves` en service, revue des accès publiée).

> **Règle de la phase** : Hélène ne modifie rien. Toi, tu corriges ce que tu trouves **en S04** (ce sont des dérives récentes, à fermer tout de suite) ; ce qu'elle formalise en **S07** se corrige dans les phases suivantes, selon le plan de remédiation.

---

### F6-S04 — Panne : les écarts cachés de l'audit à blanc  `BF` `★★★★`

> **Ticket SEC-3604** — *De : Hélène Mercier (Auditia Santé), relayé par Sophie Laurent*
> Bonjour. Hier soir, avec le compte de lecture que vous m'avez ouvert, j'ai refait un tour de ce que vous m'aviez montré la semaine dernière : revue des accès, catalogue des preuves, dérogations, sauvegardes, bordure, supervision. J'ai noté plusieurs choses qui ne collent plus avec ce que vous m'avez présenté. Je ne vous dis pas lesquelles : un auditeur interne doit les trouver avant moi. Je veux, pour chacune, l'écart formalisé, sa cause, qui l'a introduit et quand, la correction et ce qui l'empêchera de revenir.

**Objectifs pédagogiques**
- Auditer une plateforme par comparaison méthodique entre ce qui est déclaré (code, SoA, catalogue, revue) et ce qui est observé.
- Retrouver l'auteur et la date d'un changement fait hors du chemin normal (journaux d'audit, historiques, métadonnées).
- Corriger par le bon chemin et formaliser chaque écart.

**Prérequis** : F6-S02 (preuves quotidiennes : elles servent de **référence** d'avant), F6-S03 (revue des accès) ; M22/M26 (audit Kubernetes dans Loki, locataire `audit`) ; M07 (bordure en code), M16 (Velero), M21 (Alertmanager), M26 (dérogations Kyverno, registre `EXC-…`).
**Durée indicative** : 3 h de recherche, plus la formalisation (1 h).

**Contexte technique**
- Le lab doit être sain avant l'injection : API de `k8s-par1` joignable, espaces `mediagenda-recette` et `kyverno-exceptions` présents, aucune injection précédente de ce scénario. L'injection ne touche ni la production, ni les données.
- Injection : `lab/bin/break F6 4` (depuis `adm01`). Elle pose **un lot d'écarts** tirés au hasard (le message d'Hélène en donne le **nombre**) ; `WB_F6_S04_NB` (3 à 7, défaut 4) règle leur nombre. Abandon : `lab/bin/break F6 4 --annuler` (ne défait que ce qui est encore dans l'état injecté).
- Les écarts sont des **dérives récentes**, postérieures à ta revue des accès (S03) et aux premiers lots de preuves (S02).
- Formalisation : une fiche `docs/conformite/ecarts/ECA-3611[-<sujet>].md`, `ECA-3612…`… par écart trouvé (en-tête YAML et sections : [`00-introduction.md`](00-introduction.md)).

**Travail demandé**
1. Lance `lab/bin/break F6 4` et lis le message d'Hélène.
2. Audite : trouve chaque écart, date-le, identifie qui (ou quoi) l'a introduit.
3. Corrige chaque écart par le bon chemin, et vérifie que la correction tient.
4. Formalise : une fiche ECA par écart, close avec sa preuve de clôture (le lot `ms-preuves` qui montre l'état corrigé) ; et pour chacun, ce qui l'aurait détecté plus tôt (et, si rien ne l'aurait fait, la détection à ajouter).

**Critères de réussite**
- [ ] Aucun compte de prestataire parti n'est actif ; la bordure n'a aucune règle active absente de sa configuration persistée ; toute dérogation Kyverno a une échéance et figure au registre ; aucune ConfigMap d'un espace applicatif ne contient de mot de passe ou de jeton ; aucune planification Velero n'est suspendue ; aucun compte de service applicatif n'est `cluster-admin` ; aucun silence d'Alertmanager ne couvre les alertes de sécurité ni ne dure plus de sept jours.
- [ ] Autant de fiches `ECA-3611`… que d'écarts injectés, chacune avec cause, mesure ISO, correction et prévention.

**Vérification** : `lab/bin/check F6 4`
**Temps cible** : 3 h.

<details><summary>Indice 1</summary>

Tu as une **photo d'avant** : les lots de preuves quotidiens (S02) et ta revue des accès (S03). Une dérive est une différence entre la photo d'hier et l'état d'aujourd'hui. Compare preuve par preuve, puis va voir ce que les preuves ne couvrent pas encore.
</details>

<details><summary>Indice 2</summary>

Pour chaque domaine de ton catalogue, la question est toujours la même : **ce qui tourne est-il ce que le code décrit ?** Le code est dans Git (bordure, politiques, planifications, liaisons), l'état est dans les API. Ce qui existe sans être dans un dépôt, ou diffère de son dépôt, est suspect. Pour l'auteur et la date : journal d'audit de l'API Kubernetes (Loki, locataire `audit`), métadonnées des objets (`managedFields`, annotations), événements d'audit de GitLab, champ `createdBy` des silences, journal système des passerelles.
</details>

<details><summary>Indice 3</summary>

Une correction qui tient se fait au bon endroit : un objet posé à la main se retire (et on note pourquoi), un réglage qui doit exister se déclare dans son dépôt, une dérogation légitime passe par le registre et prend une échéance. Ensuite, demande-toi pour chaque écart **quel contrôle l'aurait vu en moins de 24 h** : une preuve quotidienne qui le montre, une alerte, une politique d'admission.
</details>

---

### F6-S05 — L'audit technique outillé  `LIBRE` `★★★`

> **Ticket SEC-3605** — *De : Sophie Laurent* — *Copie : Hélène Mercier, Karim Benali*
> Hélène va passer ses propres outils. Je veux que nous passions les **nôtres** avant, sur tout le périmètre : conformité des hôtes, du cluster, des images, des accès SSH. Pas un tas de rapports bruts : un document qui dit ce qu'on a mesuré, avec quoi, ce qui est grave, ce qui est un faux positif et pourquoi, et ce qui devient un écart. Les résultats bruts sont gardés à côté, avec leurs empreintes : Hélène voudra pouvoir recompter.

**Objectifs pédagogiques**
- Conduire un audit technique outillé sans perturber la production (mesure 8.34).
- Trier des résultats hétérogènes par gravité réelle dans **notre** contexte, et justifier chaque faux positif.
- Relier les constats techniques aux mesures de la SoA et aux écarts.

**Prérequis** : F6-S01 (SoA) ; M26-E03 (Lynis, ssh-audit), E04 (OpenSCAP, profils adaptés, exceptions), E05 (kube-bench, kubescape), E24 (analyses hebdomadaires, compartiment `conformite`), E30 (vulnérabilités des images en service) ; M13 (Trivy, Harbor).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Outils et versions installés au M26 : OpenSCAP 1.4 et contenu ComplianceAsCode 0.1.82 (profils adaptés `…_medisphere`, registre `docs/securite/durcissement/exceptions.md`) ; kube-bench 0.16 (référentiel `cis-1.12` forcé : aucun pour 1.36) ; kubescape 4 ; Trivy (rôle `outils_supply_chain`) et l'analyse de Harbor ; ssh-audit 3.9 ; Lynis 3.1.7.
- Les analyses OpenSCAP hebdomadaires du M26-E24 sont déjà dans `s3-01`, compartiment `conformite` : décide si tu t'en sers, si tu relances, ou les deux.
- Livrables figés (lus par le check) : `docs/conformite/audit-2026/audit-technique.md` et les résultats bruts (ou leurs résumés quand ils sont volumineux) dans `docs/conformite/audit-2026/technique/`.
- ⚠️ Un Job kube-bench sur un nœud de contrôle, un balayage ssh-audit de toutes les passerelles, Trivy en mode cluster : chacun a une charge et des droits. Annonce l'audit, choisis l'heure, retire après coup ce que tu as créé.

**Travail demandé**

Objectifs :
1. Un **plan d'audit** : périmètre analysé (quels hôtes, quel cluster, quelles images, quels services SSH), outils et versions, référentiels, créneau, ce qui est exclu et pourquoi.
2. Les **analyses** : conformité des hôtes du socle (CIS et ANSSI), du cluster (kube-bench, kubescape), vulnérabilités des **images en service** (par empreinte), configuration des services SSH.
3. Le **tri** : constats classés (critique, élevé, moyen, faible), faux positifs justifiés **dans notre contexte** (choix de kubeadm, exceptions déjà enregistrées, contrôle non applicable), doublons fusionnés entre outils.
4. Le **rapport** `audit-technique.md` : synthèse, méthode, résultats par domaine, faux positifs, renvois aux mesures de la SoA et aux écarts (`ECA-36xx` existants ou à créer en S07), empreintes SHA-256 des fichiers bruts.

Contraintes :
- Lecture seule sur la production ; tout objet créé pour l'audit (Job, compte de service) est retiré à la fin.
- Aucun secret ni donnée de santé dans les résultats publiés (un rapport kubescape cite des noms d'objets, pas des valeurs : vérifie).
- Un faux positif sans justification est un vrai positif.

**Critères de réussite**
- [ ] `audit-technique.md` est sur `main` : OpenSCAP, kube-bench, kubescape, Trivy (ou Harbor) et ssh-audit, avec versions, référentiels et périmètre.
- [ ] Les résultats sont triés par gravité, les faux positifs justifiés, les constats reliés aux écarts.
- [ ] Au moins cinq fichiers de résultats bruts sont dans `audit-2026/technique/`, et leurs empreintes SHA-256 dans le rapport.

**Vérification** : `lab/bin/check F6 5`

<details><summary>Indice 1</summary>

Commence par la question de l'auditeur : « qu'avez-vous **regardé** ? ». Un rapport qui ne dit pas ce qui n'a pas été analysé laisse croire que tout l'a été. Un échantillon est acceptable s'il est **représentatif** (une VM de chaque famille, chaque rôle) et dit comme tel.
</details>

<details><summary>Indice 2</summary>

Les trois outils de conformité se recouvrent (kube-bench et kubescape sur le cluster, OpenSCAP et Lynis sur les hôtes). Range par **constat**, pas par outil : un même défaut vu par deux outils est un seul constat. Et pour chaque « échec » d'un référentiel, demande-toi : est-ce un défaut chez nous, un choix assumé et enregistré (registre des exceptions du M26), ou un contrôle qui ne s'applique pas à notre architecture ?
</details>

<details><summary>Indice 3</summary>

Pour les images, ce qui compte est ce qui **tourne** (empreinte réelle des conteneurs), pas ce qui est dans le registre. Une critique sans correctif publié n'est pas traitée comme une critique corrigeable : note-la, avec la date de sa première détection — c'est exactement ce qu'Hélène cherchera en parlant de délais de traitement.
</details>

**Pour aller plus loin** (facultatif) : TLS des points d'entrée publiés (`testssl.sh` ou `sslscan`, non installés au lab : à évaluer) ; balayage de ports de la bordure depuis l'extérieur du lab (depuis `<LAN-MAISON>`) comparé à la matrice des flux.

---

### F6-S06 — L'entretien d'audit  `Q` `★★★`

> **Ticket SEC-3606** — *De : Hélène Mercier* — *Copie : Sophie Laurent*
> Jeudi, 14 h, une heure. Je vous poserai mes questions ; vous me répondrez avec ce que vous avez, et quand vous ne savez pas, vous me le direz. Une réponse fausse donnée avec assurance me coûte plus de temps qu'un « je vérifie et je reviens vers vous ».

**Objectifs pédagogiques**
- Répondre à un auditeur : précisément, preuve à l'appui, sans sur-promettre.
- Reconnaître dans une question l'exigence qu'elle vérifie.

**Prérequis** : F6-S01 à F6-S05.
**Durée indicative** : 1 h 30 (réponses écrites, chacune en quelques lignes, avec la preuve que tu montrerais).

**Questions**

1. « Vous ne faites pas certifier l'activité 1. Pourquoi, et que me montrez-vous pour que je n'aie pas à aller voir les salles ? »
2. « Défendez une exclusion de votre déclaration d'applicabilité. Puis dites-moi quelle mesure vous avez été tenté d'exclure, et pourquoi vous ne l'avez pas fait. »
3. « Votre preuve P-IAM-01 du 3 novembre : comment est-ce que je sais qu'elle n'a pas été produite le 15 ? »
4. « Votre compartiment de preuves est en mode `COMPLIANCE`. Qu'est-ce qui empêche votre administrateur Ceph d'effacer tout cela quand même ? »
5. « Votre lot d'hier est marqué partiel. Est-ce un écart ? »
6. « Montrez-moi qui a lu un Secret de `mediagenda-prod` la semaine dernière. Combien de temps gardez-vous cette information, et pourquoi cette durée ? »
7. « Votre accès de bris de glace au cluster : où est-il, qui l'a utilisé pour la dernière fois, et comment le savez-vous ? »
8. « Un développeur d'AxiomDev est parti. Prouvez-moi qu'il n'a plus aucun accès. Et ce qu'il a **créé** pendant sa mission ? »
9. « Vos dérogations aux politiques d'admission : qui les valide, pour combien de temps, et que se passe-t-il le jour de l'échéance ? »
10. « Une vulnérabilité critique est publiée ce matin sur une bibliothèque d'une image qui tourne en production. Racontez-moi les sept jours qui suivent. »
11. « Si j'obtenais les clés d'accès du compartiment de vos sauvegardes Velero, qu'est-ce que je lirais ? »
12. « Vos données de recette sont-elles des données réelles ? Comment le savez-vous, et comment le saurez-vous dans six mois ? »
13. « Un de vos clients vous appelle : il pense que des données de ses patients ont fuité par votre plateforme. Que faites-vous dans la première heure ? Et qui notifie la CNIL ? »
14. « Avez-vous des accès ou des transferts hors de l'EEE ? Comment le savez-vous ? »
15. « Pourquoi est-ce que je vous pose une question sur vos horloges ? D'où vient l'heure de vos journaux ? »
16. « Qui a approuvé votre déclaration d'applicabilité, et où est la trace de la dernière revue de direction ? »

Pas de vérification automatique : les réponses argumentées sont dans le corrigé.

---

### F6-S07 — Rapport d'écarts et plan de remédiation  `RED` `★★★`

> **Ticket SEC-3607** — *De : Sophie Laurent* — *Copie : Claire Morel, Thomas Renaud, Hélène Mercier*
> Vendredi, Hélène m'a remis ses notes (ci-dessous). C'est à nous de les mettre au propre : un **rapport d'écarts** que je puisse présenter à la direction, une fiche par écart, et un **plan de remédiation** que Claire puisse arbitrer — priorisé par le **risque**, pas par la facilité. Thomas ajoute une pièce que le nouveau référentiel HDS exige et que nous n'avons pas : la **cartographie des transferts hors EEE**. Je veux tout sur `main` lundi soir.

**Objectifs pédagogiques**
- Formaliser des constats d'audit (constat, référence, preuve, gravité) sans les édulcorer ni les grossir.
- Prioriser une remédiation par le risque (vraisemblance, impact sur les données de santé, exposition), avec des échéances tenables.
- Établir une cartographie des transferts hors EEE au sens de HDS v2.

**Prérequis** : F6-S01 à F6-S06.
**Durée indicative** : 4 h.

**Contexte technique**

*Notes d'Hélène Mercier (à formaliser)* :

| Numéro | Constat d'Hélène |
|---|---|
| ECA-3601 | « Les journaux d'audit existent (API Kubernetes, OpenBao, Keycloak…) mais rien ne prouve qu'ils n'ont pas été modifiés : Loki est administré par les mêmes personnes que ce qu'il trace, chaque brique garde ses journaux avec sa propre durée, et certaines sources ne sont pas centralisées. » |
| ECA-3602 | « Les vulnérabilités sont détectées (Harbor, Trivy) mais aucun délai de traitement n'est écrit ; j'ai trouvé des critiques connues depuis plus de trente jours en recette, et des « exceptions » sans date de fin. » |
| ECA-3603 | « Les sauvegardes Velero et les exports déposés sur `s3-01` ne sont pas chiffrés côté serveur : un administrateur du stockage objet lit des données de santé en clair. » |
| ECA-3604 | « La revue des accès est récente et bien faite, mais c'est la **première** : aucune trace de revue antérieure, et elle a trouvé des comptes orphelins. Le processus n'existait pas. » |
| ECA-3605 | « Aucune réponse à incident de sécurité n'a jamais été testée : pas de procédure de confinement d'une charge compromise, pas de kit forensique, pas de modèle de notification aux clients. » |
| ECA-3606 | « Aucune cartographie des transferts hors EEE ; les fournisseurs n'ont pas été passés en revue sous cet angle. » |

*Fournisseurs et accès à examiner pour la cartographie* (informations recueillies par Thomas) :

| Fournisseur ou accès | Usage | Données concernées | Localisation déclarée |
|---|---|---|---|
| DataCampus | colocation de PAR1 et PAR2 (activité 1) | aucune donnée lue (accès physique aux salles) | France |
| HelpNow (SaaS) | outil de tickets du support | demandes des clients ; il arrive qu'un cabinet joigne une **capture d'écran** d'un dossier patient | Allemagne (Francfort) ; société mère aux États-Unis |
| SMS-Express | envoi des SMS de rappel de MédiNotif | numéro de téléphone, date et heure du rendez-vous, nom du praticien | Irlande ; rapports de remise traités par un sous-traitant aux États-Unis (selon ses conditions générales) |
| Registres publics (Docker Hub, ghcr.io, quay.io) | téléchargement d'images et de charts par les caches de Harbor | aucune donnée envoyée (requêtes de téléchargement) | États-Unis |
| Messagerie d'entreprise | SI interne, hors périmètre | règle : aucune donnée de santé par courriel | éditeur américain, données en UE |
| Astreinte du support | un ingénieur du support passe deux semaines par an chez sa famille au Maroc et y assure l'astreinte par le VPN | accès d'administration à la plateforme | Maroc (pays tiers) |

**Travail demandé**
1. Rédige `docs/conformite/audit-2026/rapport-ecarts.md` : synthèse pour la direction, méthode et périmètre de l'audit à blanc, **points forts** (il y en a), liste des écarts ECA-3601 à 3606 **et** de ceux trouvés en S04 (déjà clos), avec leur gravité argumentée (non-conformité majeure, mineure, observation).
2. Rédige une fiche par écart, `docs/conformite/ecarts/ECA-3601[-<sujet>].md` à `ECA-3606[-<sujet>].md` (en-tête YAML et sections de l'introduction) : constat, référence (mesure ISO, exigence HDS), preuves, gravité, cause, correction et action corrective envisagées, responsable, échéance, statut. Ce fichier vivra jusqu'à la clôture.
3. Rédige `docs/conformite/plan-remediation.md` : pour chaque écart, le risque (vraisemblance × impact, et pourquoi), la priorité qui en découle, les actions, le responsable, l'échéance, la preuve de clôture attendue ; l'ordre de traitement et sa justification ; ce qui est accepté temporairement et par qui.
4. Rédige `docs/conformite/transferts-hors-eee.md` : pour chaque fournisseur ou accès, s'il y a transfert ou accès depuis un pays tiers, ou soumission à une loi extra-européenne ; la base et les garanties ; les mesures (techniques, contractuelles) ; la décision ; ce qui doit être **publié** et ce qui doit être **dit aux clients** ; validation par Thomas.
5. MR relue par Sophie, Thomas et Claire, fusionnée sur `main`.

**Contraintes**
- Un écart se décrit par des faits observables, pas par des jugements (« les journaux ne sont pas fiables » n'est pas un constat).
- La gravité suit la définition d'ISO (majeure : exigence non satisfaite ou doute sérieux sur l'efficacité du système), pas l'inquiétude.
- Les échéances tiennent compte de la capacité réelle de l'équipe ; le plan dit ce qui sera fait en S08 à S10.

**Critères de réussite**
- [ ] `rapport-ecarts.md` est sur `main` avec synthèse, méthode, points forts, ECA-3601 à 3606 et les écarts de S04, gravités majeur/mineur argumentées.
- [ ] Les fiches `ECA-3601` à `ECA-3606` existent avec l'en-tête YAML, constat, preuve, mesure ISO, exigence, gravité.
- [ ] `plan-remediation.md` couvre les six écarts avec risque, priorité, action, responsable et échéance.
- [ ] `transferts-hors-eee.md` couvre chaque fournisseur et accès de la liste, avec pays, garanties, mesures, et la validation du DPO.

**Vérification** : `lab/bin/check F6 7` (présence et contenu minimal ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Pour la gravité, pose la question d'ISO : **le système de management atteint-il ses résultats** sur ce point ? Un processus qui n'existe pas du tout (aucune revue d'accès avant celle-ci, aucune réponse à incident testée) n'est pas un oubli ponctuel. Un défaut technique isolé avec un processus qui fonctionne par ailleurs l'est davantage.
</details>

<details><summary>Indice 2</summary>

Pour prioriser, sépare la **gravité d'audit** (ce qui bloque la certification) et le **risque** (ce qui peut faire du mal aux patients et aux clients). Ils ne donnent pas toujours le même ordre. Le plan suit le risque ; le calendrier de certification dit seulement ce qui doit être **fermé** avant l'audit officiel. Et regarde les dépendances : une enquête sur incident sans journaux inaltérables ne prouve rien.
</details>

<details><summary>Indice 3</summary>

Pour les transferts, trois questions par ligne : des données (de santé ou personnelles) **quittent-elles** l'EEE ? Quelqu'un y **accède-t-il** depuis un pays tiers ? Le fournisseur est-il **soumis** à une loi extra-européenne qui pourrait l'obliger à communiquer des données ? Une seule réponse « oui » suffit pour que la ligne figure dans la cartographie, avec ses mesures.
</details>

**Pour aller plus loin** (facultatif) : une matrice des risques (5 × 5) commune à la SoA, au plan et au registre des écarts ; un tableau de bord des écarts (statut, échéance, retard) généré depuis les fiches par un job de CI, sur le modèle des fiches de changement du F4.
