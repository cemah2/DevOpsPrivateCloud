# Final F7 — Phase 4 : Soutenir

La preuve de concept tourne, les mesures existent. Il reste à convaincre : un jury de quatre personnes — Claire Morel, Sophie Laurent, Karim Benali et Élodie Marchand —, 45 minutes de présentation et de démonstration, puis 30 minutes de questions. Claire a prévenu : « On ne vend pas une plateforme, on vend notre capacité à tenir ce qu'on écrit. Chaque phrase du dossier doit avoir une preuve derrière, ou ne pas y être. »

Prérequis de la phase : phase 3 terminée (`lab/bin/check F7 7` à `F7 11` verts).

---

### F7-S12 — Le dossier de soutenance  `RED` `★★★`

> **Ticket PLAT-3712** — *De : Claire Morel* — *Copie : Sophie Laurent, Karim Benali, Julien Petit*
> Le dossier part au GHSV dix jours avant la soutenance. Quatre pièces : le document d'architecture (celui que leur RSSI et leur architecte liront ligne à ligne), une synthèse pour leur direction (deux pages, pas un mot d'anglais technique sans explication, les chiffres qui comptent et ce qu'ils coûtent), le script de la démonstration (minute par minute, avec ce qu'on fait si ça casse), et les annexes de preuves. Rien dans le dossier qui ne soit mesuré, décidé ou chiffré quelque part dans nos dépôts.

**Objectifs pédagogiques**
- Écrire pour trois publics (technique, direction, jury) à partir des mêmes faits.
- Relier chaque affirmation à une preuve (mesure, code, décision, rapport) et retirer ce qui n'en a pas.
- Préparer une démonstration résistante aux incidents (plan B, ordre, durée).

**Prérequis** : F7-S01 à F7-S11.
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Dossier dans `docs/capstone/soutenance/` de `plateforme/medisphere` : `document-architecture.md`, `synthese-direction.md`, `script-demonstration.md`, `annexes-preuves.md` (tu peux ajouter des fichiers, pas en retirer).
- Le document d'architecture s'appuie sur `architecture.md` (S03) et les ADR-0370 et suivantes (S04) : il ne les recopie pas, il montre ce que la preuve de concept a **confirmé**, **infirmé** ou laissé **ouvert**.
- Les prix sont ceux de `chiffrage.md` (S05) : ordres de grandeur d'octobre 2026, marqués « à vérifier », jamais présentés comme un devis.
- Durées : 45 min de présentation **et** de démonstration, 30 min de questions.

**Travail demandé**
1. **`document-architecture.md`** : périmètre, exigences du GHSV et réponse à chacune (tableau de traçabilité exigence → décision → preuve), architecture cible de production (sites, réseaux, flux, identité, données, chiffrement, sauvegarde et PRA, exploitation), écarts entre la preuve de concept et la cible (ce que le lab ne montre pas, et pourquoi on peut quand même s'engager… ou pas), réversibilité, risques résiduels.
2. **`synthese-direction.md`** (deux pages au plus) : ce que le GHSV obtient, les engagements chiffrés et ce qui les garantit, le coût sur cinq ans (ordre de grandeur, hypothèses), les trois risques principaux et leur traitement, le calendrier jusqu'au 1er mars 2027, ce que le GHSV doit fournir.
3. **`script-demonstration.md`** : déroulé minute par minute (qui parle, ce qu'on montre, la commande ou l'écran, ce que le jury doit en retenir), état de départ vérifié (liste de contrôle à T−30 min), **plan B** pour chaque étape (incident pendant la démo, réseau, identité), et la phrase de transition vers les questions.
4. **`annexes-preuves.md`** : une ligne par preuve citée (identifiant, nature, emplacement — objet de `preuves-conformite`, rapport, MR, tableau —, date, ce qu'elle prouve), regroupées par exigence.

**Contraintes**
- Aucune affirmation chiffrée sans preuve dans les annexes ; aucun prix sans hypothèse ; aucun engagement que la preuve de concept n'a pas mesuré, sauf s'il est **écrit** comme un engagement de la phase de construction, avec sa condition.
- La synthèse se lit sans le document d'architecture.
- Aucune donnée personnelle (même fictive) ni secret dans le dossier.

**Critères de réussite**
- [ ] Les quatre documents sont sur `main` de `plateforme/medisphere`.
- [ ] Le document d'architecture contient une traçabilité exigence → décision → preuve, les écarts entre preuve de concept et cible, la réversibilité et les risques.
- [ ] La synthèse tient en deux pages, chiffre disponibilité, RTO, RPO et coût, et liste ce que le GHSV doit fournir.
- [ ] Le script prévoit un plan B par étape et tient en 45 minutes.
- [ ] Les annexes citent des preuves réelles (rapports, objets de preuve, MR) avec leur emplacement.

**Vérification** : `lab/bin/check F7 12` (présence et contenu minimal ; la qualité se juge avec le corrigé)

<details><summary>Indice 1</summary>

Pars des exigences de `exigences.md`, pas de ton architecture : pour chacune, une ligne « ce que dit le GHSV / ce que nous faisons / comment on le prouve / où ». Une ligne dont la dernière colonne est vide est soit un risque, soit une promesse à retirer.
</details>

<details><summary>Indice 2</summary>

Une démonstration de 20 minutes en direct dans un lab partagé avec d'autres travaux a une probabilité réelle d'incident. Le plan B n'est pas « on improvise » : c'est une capture (vidéo, journal, tableau figé) préparée à l'avance, et une phrase qui transforme l'incident en démonstration de la réaction (S11).
</details>

**Pour aller plus loin** (facultatif) : faire relire la synthèse par quelqu'un qui n'est pas du métier et noter chaque mot qu'il ne comprend pas ; produire le dossier en PDF par la CI (Pandoc) avec numéro de version et empreinte.

---

### F7-S13 — La soutenance : questions du jury  `Q` `★★★★`

> **Note de Claire Morel**
> Trente minutes de questions, quatre personnes qui n'ont pas les mêmes soucis. Je te donne celles que je poserais à leur place — et quelques-unes que je poserais pour te piéger. Réponds par écrit, comme si tu étais devant eux : court, chiffré quand c'est possible, honnête quand tu ne sais pas.

**Objectifs pédagogiques**
- Défendre des choix techniques devant des publics différents, avec des arguments et des preuves.
- Reconnaître les limites de sa solution et les dire sans les maquiller.
- Repérer les questions-pièges (fausse alternative, présupposé faux, engagement impossible).

**Prérequis** : F7-S01 à F7-S12.
**Durée indicative** : 2 à 3 h (puis une répétition orale chronométrée, si tu peux).

**Questions**

*Élodie Marchand (DSI du GHSV)*
1. Vous êtes un éditeur de logiciels qui s'est mis à héberger il y a deux ans. Pourquoi vous confierais-je les rendez-vous de 400 000 patients plutôt qu'à un grand hébergeur certifié ?
2. Votre preuve de concept tourne sur **un** serveur et un HP de récupération. Qu'est-ce qui me garantit que la production réelle tiendra 150 requêtes par seconde le lundi à 8 h ?
3. En fin de contrat, combien de temps et combien d'argent pour récupérer nos données, et dans quel état les reçoit-on ?
4. *(Piège)* « Votre plateforme est 100 % souveraine, je suppose ? Aucune dépendance à un acteur non européen ? »
5. Le rapport mensuel dit 99,93 %, mais mes agents disent qu'ils n'ont pas pu se connecter mardi matin pendant une heure. Qui a raison ?

*Sophie Laurent (RSSI, dans le rôle du RSSI du GHSV)*
6. Un agent du GHSV est licencié vendredi soir. À quel moment exact perd-il l'accès à MédiAgenda, et qu'est-ce qui pourrait le prolonger ?
7. Si votre Keycloak est compromis, que peut faire l'attaquant avec les identités de nos agents et avec nos données ?
8. Vous dites « clés dédiées au GHSV ». Qui chez vous peut déchiffrer nos données, et comment le saurions-nous ?
9. *(Piège)* « Le chiffrement au repos de vos disques suffit à protéger nos données contre vos administrateurs, n'est-ce pas ? »
10. Un incident de sécurité touche votre plateforme mais pas, à votre connaissance, les données du GHSV. Nous prévenez-vous, quand, et sur quelle base ?

*Karim Benali (architecture, exploitation)*
11. Pourquoi une instance de MédiAgenda par client plutôt qu'une instance multi-locataire ? À partir de combien de clients changeriez-vous d'avis ?
12. Votre SLO est sur 30 jours glissants, le contrat sur le mois calendaire, et Prometheus garde 15 jours en local. Montrez-moi que votre chiffre du mois est juste.
13. Le DPI du GHSV appelle votre API v1. Vous devez corriger un champ mal typé. Racontez-moi les six prochains mois.
14. *(Piège)* « Puisque PAR2 a la base répliquée en continu, votre RPO est de zéro, non ? »
15. Votre locataire de démonstration a tenu sous la charge. Qu'est-ce qui, dans la plateforme, casserait en premier avec cinq clients comme le GHSV ?

*Claire Morel (direction de l'infrastructure)*
16. Combien de personnes faut-il pour tenir ces engagements 24 h/24, et les avons-nous ?
17. Quelle est l'hypothèse de votre chiffrage qui, si elle est fausse, coûte le plus cher ?
18. *(Piège)* « Si le GHSV demande 99,99 % au lieu de 99,9 %, on peut dire oui pour 10 % de plus ? »

*Question ajoutée par Sophie Laurent (dans le rôle du DPO du GHSV)*
19. Le prestataire de notre DPI est à Tunis (ESC-12) et doit lire les journaux techniques de l'API. Comment lui donnez-vous accès sans que des données de santé quittent l'Espace économique européen, et qu'écrivez-vous dans la cartographie des transferts ?

**Livrable** : tes réponses dans `docs/capstone/soutenance/questions-jury.md` (facultatif dans le dépôt : ce scénario est auto-évalué avec le corrigé).

<details><summary>Indice 1</summary>

Chaque question cache une demande de preuve. Avant de répondre, demande-toi : « quel fichier, quelle mesure, quelle MR de mes dépôts répond à cette question ? ». S'il n'y en a pas, la bonne réponse commence par le dire.
</details>

<details><summary>Indice 2</summary>

Les pièges ont un présupposé faux (souveraineté « totale », chiffrement au repos contre l'administrateur, RPO nul d'une réplication asynchrone, un neuf de plus « pour 10 % »). Corrige le présupposé poliment, puis réponds à la vraie question.
</details>

---

### F7-S14 — Recette `capstone-v1`  `LIBRE` `★★`

> **Ticket PLAT-3714** — *De : Claire Morel* — *Copie : Sophie Laurent, Karim Benali*
> Avant d'envoyer le dossier, une dernière vérification, la même que pour chaque final : tout ce qu'on montre au GHSV se reconstruit depuis le code, les pipelines sont verts, les preuves sont dans le compartiment verrouillé, et la recette du GHSV se reconstruit à vide sous nos yeux. Quand c'est fait, tu poses `capstone-v1`.

**Objectifs pédagogiques**
- Prouver qu'une livraison est reproductible depuis le code (idempotence, reconstruction).
- Faire collecter les preuves par l'outillage de conformité plutôt que les rassembler à la main.
- Clore un projet avec une recette écrite et une étiquette.

**Prérequis** : F7-S01 à F7-S13 ; F6 (`ms-preuves`, compartiment `preuves-conformite`).
**Durée indicative** : 2 à 3 h.

**Contexte technique**
- Projets concernés : `plateforme/equipes`, `plateforme/identite` (royaume `medisphere` et état séparé de `ghsv-idp`), `plateforme/secrets`, `plateforme/k8s`, `plateforme/gitops`, `plateforme/observabilite`, `plateforme/outils`, `mediagenda/api`, `mediagenda/deploiement`, `plateforme/medisphere`.
- `ms-preuves` (F6) collecte, horodate, signe et dépose ses preuves dans `preuves-conformite` ; ajoute-lui ce que la capstone doit prouver, selon le mode d'emploi que tu lui as donné au F6.
- La recette `ghsv-recette` ne contient que des données fictives ; sa reconstruction à vide est permise, celle de `ghsv-prod` ne l'est **pas** dans ce scénario.
- Étiquette finale **`capstone-v1`** sur `plateforme/medisphere`.

**Travail demandé**
1. **Idempotence** : le rendu de `plateforme/equipes` ne propose aucun changement ; les plans OpenTofu de `medisphere`, `ghsv-idp` et `plateforme/secrets` sont vides ; les Applications du GHSV sont `Synced`/`Healthy`.
2. **Reconstruction** : `ghsv-recette` détruite puis reconstruite depuis le code seul (espace, secrets, base vide, données de démonstration, accès des agents), chronométrée, avec un contrôle de bout en bout après.
3. **Preuves** : les preuves de la capstone (rapport mensuel, essai de réversibilité, compte rendu de la journée de jeu, essai de reprise de PAR2, constat du cloisonnement des identités, pipelines du contrat) collectées par `ms-preuves` dans `preuves-conformite` ; leurs identifiants reportés dans `annexes-preuves.md`.
4. **Recette** : `docs/capstone/recette.md` (contrôles, résultats, durées, écarts restants et leur suite), puis l'étiquette `capstone-v1`.

**Contraintes**
- ⚠️ La reconstruction ne touche que `ghsv-recette` ; la production du GHSV, MédiAgenda et les autres locataires restent intacts (vérifie-le avant et après).
- Aucune preuve déposée à la main dans le compartiment.

**Critères de réussite**
- [ ] Les derniers pipelines de `main` des projets listés sont verts.
- [ ] Les Applications Argo CD du GHSV sont `Synced`/`Healthy` ; `ghsv-recette` a été recréé (date de création postérieure au début de la recette) et répond.
- [ ] Des preuves de la capstone sont présentes dans `preuves-conformite`.
- [ ] `docs/capstone/recette.md` est sur `main` (contrôles, durées, écarts) et l'étiquette `capstone-v1` est posée.
- [ ] `lab/bin/check F7 7` à `F7 12` sont verts.

**Vérification** : `lab/bin/check F7 14`

<details><summary>Indice 1</summary>

Un espace protégé contre l'élagage par Argo CD ne disparaît pas tout seul et ne revient pas tout seul non plus : relis RB-320 (§ Départ) et ce que fait l'Application qui livre les espaces des équipes quand un espace manque. La base de recette n'a pas de sauvegarde à restaurer : elle renaît vide, et tes données de démonstration doivent être du code.
</details>

<details><summary>Indice 2</summary>

« Rejouable » se prouve par un plan vide **et** par une reconstruction réelle : l'un sans l'autre laisse un doute (un plan vide sur un état qui a dérivé avec le code, une reconstruction qui marche grâce à un geste manuel oublié). Note chaque geste manuel de la reconstruction : chacun est un écart.
</details>

**Pour aller plus loin** (facultatif) : un pipeline planifié qui reconstruit `ghsv-recette` chaque semaine et publie la durée ; la même recette lancée depuis `adm02` (PAR2) pour vérifier que le code suffit aussi sans PAR1.
