# Final F7 — Phase 1 : Comprendre le besoin

Un cahier des charges n'est pas une spécification : c'est la façon dont un client a réussi à écrire son besoin, avec ses habitudes, ses copier-coller et ses contradictions. Avant de concevoir quoi que ce soit, tu dois savoir ce qu'il demande vraiment, ce que notre solution sait déjà faire, ce qui manque, et ce qui doit être clarifié par écrit avant le 13 novembre. Puis traduire ses exigences en engagements que tu sais mesurer.

Prérequis de la phase : [`00-introduction.md`](00-introduction.md) lu, état d'entrée vérifié, cahier des charges lu une première fois en entier.

---

### F7-S01 — Lire le cahier des charges  `RED` `★★`

> **Ticket PLAT-3701** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Julien Petit*
> Avant qu'on parle architecture, je veux une lecture critique du cahier des charges du GHSV : ce qu'ils demandent, ce qu'on sait déjà faire, ce qui nous manque, ce qui est flou et ce qui ne tient pas debout. Et la liste des questions à leur poser **avant le 13 novembre midi** : après, on répond avec nos hypothèses et on vit avec. Julien a un doute sur leur annexe d'API, regarde-la de près. Termine par ta recommandation : on y va, on y va avec des réserves, ou on n'y va pas.

**Objectifs pédagogiques**
- Lire un cahier des charges comme un ingénieur qui devra tenir les engagements : repérer périmètre, ambiguïtés, contradictions, exigences irréalistes et conditions de recevabilité.
- Comparer un besoin écrit à ce que fait réellement un produit, jusqu'au niveau du contrat d'interface.
- Formuler des questions utiles à un client (précises, fermées quand c'est possible, chacune liée à une décision) et les hypothèses qu'on retient sans réponse.

**Prérequis** : F2 (équipe en code, accueil d'un locataire), F5 (PRA, RTO/RPO mesurés), F6 (périmètre HDS, transferts hors EEE) ; code de `apps/mediagenda` et ses évolutions des modules (M27-E06 : `rappel`).
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- Ressources : [`cahier-des-charges.md`](../ressources/S01/cahier-des-charges.md) (CCTP et règlement de la consultation), [`api-rendez-vous-v1.yaml`](../ressources/S01/api-rendez-vous-v1.yaml) (annexe A1, OpenAPI 3.1), [`volumetrie.csv`](../ressources/S01/volumetrie.csv) (annexe A2).
- Ce que fait MédiAgenda : son `README.md`, son code (`app.py`, `modeles.py`) et sa documentation OpenAPI générée (`/docs`, `/openapi.json` sur la recette). Ce que fait MédiDoc : `apps/medidoc`. Ce qui est publié en production et ce qui ne l'est qu'en recette : ton propre dépôt `plateforme/gitops`.
- Les exigences du GHSV ont des identifiants (`EF-nn`, `ENF-nn`, `ESC-nn`, `ERV-nn`, `EXP-nn`, `MES-nn`) : cite-les partout. Questions `Q-nn`, hypothèses `H-nn` (conventions de l'introduction).
- Comme tout vrai cahier des charges, celui-ci contient des imprécisions, des exigences qui se contredisent et au moins une exigence qu'aucun hébergeur ne peut honnêtement promettre telle qu'elle est écrite.

**Travail demandé**
1. Rédige `docs/capstone/analyse-cdc.md` :
   - le besoin en cinq lignes, dans tes mots ;
   - le **périmètre** tel que tu le comprends (dans, hors, options), et ce que **nous** proposons de laisser hors périmètre ;
   - un tableau **besoin ↔ solution** : chaque exigence fonctionnelle, et chaque opération de l'annexe A1 (par son `operationId`), avec son état chez nous (*disponible et publié en production*, *disponible en recette seulement*, *à développer*, *à négocier*, *hors produit*) et la preuve (fichier, route, version) ;
   - les **incohérences** : exigences contradictoires (par paires d'identifiants), exigences irréalistes, ambiguïtés, données douteuses de l'annexe A2 ; pour chacune, son impact sur l'offre et ce que tu proposes ;
   - les **conditions de recevabilité** de l'offre et notre situation au regard de chacune ;
   - les **hypothèses** `H-nn` retenues ;
   - ta **recommandation** (répondre, répondre avec réserves, ne pas répondre), argumentée.
2. Rédige `docs/capstone/questions-client.md` : au moins dix questions `Q-nn`, chacune avec l'exigence concernée, la question elle-même (précise, avec les options possibles quand il y en a), pourquoi elle compte pour l'offre (ce qu'elle change : architecture, prix, planning, engagement), et l'hypothèse `H-nn` retenue si le GHSV ne répond pas.
3. MR relue par Claire et Julien, fusionnée sur `main`.

**Contraintes**
- Aucune question dont la réponse est déjà dans le cahier des charges, ni de question « ouverte » sans enjeu (« pouvez-vous préciser vos attentes ? »).
- Les questions sont publiées à **tous** les candidats : n'y révèle ni notre architecture, ni nos faiblesses.
- Tout ce que tu affirmes sur MédiAgenda est vérifiable dans le code ou sur la recette.

**Critères de réussite**
- [ ] `docs/capstone/analyse-cdc.md` est sur `main` avec les sections périmètre, hors périmètre, besoin ↔ solution, incohérences, hypothèses et recommandation.
- [ ] L'analyse cite au moins 15 exigences distinctes du cahier des charges, et les six `operationId` de l'annexe A1.
- [ ] Les incohérences relevées citent les identifiants concernés, y compris les contradictions et les exigences irréalistes volontaires du cahier des charges.
- [ ] Au moins 5 hypothèses `H-nn`.
- [ ] `docs/capstone/questions-client.md` est sur `main` avec au moins 10 questions `Q-nn`, chacune liée à au moins une exigence du cahier des charges.

**Vérification** : `lab/bin/check F7 1` (présence et contenu minimal ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Lis chaque exigence en te demandant : « comment le GHSV saura-t-il, le 10 avril 2027, si je l'ai tenue ? ». Une exigence à laquelle tu ne sais pas répondre est soit ambiguë (question), soit non mesurable (reformulation en S02), soit intenable (réserve). Et lis les exigences **deux à deux** dans les sections différentes : les contradictions d'un cahier des charges sont rarement dans la même page (PRA et intégrité, journaux et réversibilité, calendrier et déploiement…).
</details>

<details><summary>Indice 2</summary>

Pour l'annexe A1, ne te contente pas des chemins : compare **paramètre par paramètre** avec ce que l'API de MédiAgenda accepte réellement. Un framework qui ignore les paramètres de requête inconnus renvoie `200` à une requête qu'il n'a pas comprise. Regarde aussi la sécurité déclarée par le contrat, et ce qui, dans notre plateforme, la fournirait aujourd'hui.
</details>

<details><summary>Indice 3</summary>

L'annexe A2 mérite un tableur : refais les totaux, calcule les ratios (consultations par praticien, pièces jointes par rendez-vous pris en ligne), compare le total des patients au total déclaré. Une donnée aberrante dans un fichier de volumétrie est une question au client, pas une valeur à reprendre telle quelle dans un dimensionnement.
</details>

**Pour aller plus loin** (facultatif) : une matrice de conformité complète (une ligne par exigence, *conforme* / *conforme avec réserve* / *non conforme*, comme le demande le §11.2 du CCTP), générée depuis un fichier YAML par un petit script de la CI pour rester à jour pendant toute la rédaction de l'offre.

---

### F7-S02 — Les exigences non fonctionnelles, chiffrées  `RED` `★★★`

> **Ticket PLAT-3702** — *De : Karim Benali* — *Copie : Julien Petit, Nadia Roussel, Sophie Laurent*
> Le cahier des charges dit « 99,9 % », « 150 requêtes par seconde », « RTO 4 h, RPO 15 min », « journaux un an ». Ce ne sont pas encore des exigences, ce sont des intentions. Il me faut la version qu'on saura mesurer et défendre : définitions exactes, point de mesure, calcul, fenêtre, budget d'erreur, capacité cible avec le calcul qui y mène, et l'écart avec ce que notre plateforme mesure **aujourd'hui**. Chaque exigence du GHSV doit retomber quelque part chez nous, ou être explicitement laissée de côté avec la raison. C'est ce document que la phase 3 implémentera et que le jury attaquera.

**Objectifs pédagogiques**
- Transformer une exigence de cahier des charges en SLO mesurable (bon événement, événement valide, point de mesure, fenêtre) et en budget d'erreur.
- Dériver une capacité cible d'une volumétrie et d'une pointe, avec croissance, saisonnalité et marges de défaillance.
- Établir la traçabilité entre les exigences du client et les engagements du fournisseur.

**Prérequis** : F7-S01 ; M21 (SLO Pyrra `mediagenda-disponibilite` et `mediagenda-latence`, règles d'enregistrement) ; M29-E14 (référence de charge `charge/references/mediagenda-recette.json`, RB-295) ; F4-S02 (sonde de continuité) ; F5 (RTO et RPO mesurés, rapport d'exercice) ; F6 (journaux, preuves, `ECA-3601`).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- Le 20 novembre, le GHSV a publié ses réponses aux questions de tous les candidats : [`ressources/S02/reponses-aux-candidats.md`](../ressources/S02/reponses-aux-candidats.md). Lis-les maintenant (S01 terminé) : elles tranchent certaines de tes questions, en laissent d'autres ouvertes, et en tranchent parfois autrement que ton hypothèse. Mets à jour tes hypothèses `H-nn` dans `analyse-cdc.md` (une ligne « réponse R-nn » suffit) et appuie-toi sur les réponses ici.
- SLO actuels de MédiAgenda (M21) : `mediagenda-disponibilite` 99,5 % sur 28 jours ; `mediagenda-latence` 95 % des requêtes sous 250 ms (seau d'histogramme le plus proche de 300 ms).
- Référence de performance de MédiAgenda en recette (M29-E14) : 40 itérations/s, ≈ 158 requêtes/s, p95 serveur 112 ms, p99 205 ms, 0 erreur ; le parcours mesuré **écrit** (création et annulation à chaque itération). Le dimensionnement de la recette (réplicas, `requests`) est dans ton dépôt `mediagenda/deploiement`.
- Tes propres mesures (F4, F5) sont dans `docs/changements/` et `docs/pra/` : cite les tiennes, pas celles du corrigé.
- Le lab est un seul hyperviseur : ses mesures valent pour une architecture, pas pour une capacité de production (règle 3 de l'introduction).

**Travail demandé**
1. Rédige `docs/capstone/exigences.md` avec une exigence `NF-nn` par engagement, chacune décrite par : énoncé mesurable, exigence(s) source(s) du cahier des charges, valeur cible, définition précise (bon événement, événement valide, exclusions), point de mesure, méthode (requête, outil, procédure), fenêtre et fréquence, état mesuré aujourd'hui sur notre plateforme (avec sa source), statut (*tenue*, *à construire*, *réserve*).
2. Couvre au moins :
   - la **disponibilité** : budget d'erreur mensuel en minutes et en requêtes, traitement des maintenances programmées, politique de budget d'erreur (que fait-on quand il est consommé ?) ;
   - les **temps de réponse**, y compris une reformulation défendable de ce que le GHSV a écrit et qu'aucun hébergeur ne peut promettre tel quel ;
   - la **capacité** : capacité cible en requêtes/s et sa justification (pointe, croissance sur cinq ans, campagne de vaccination, perte d'un nœud ou d'un site), volumes de données à cinq ans (base, pièces jointes, journaux, sauvegardes) ;
   - la **reprise** : RTO et RPO, leur définition et leur mesure, et la position que tu proposes face à l'exigence d'intégrité absolue des rendez-vous ;
   - la **sécurité** chiffrée : délai de désactivation d'un agent, conservation et restitution des journaux, délais de correction des vulnérabilités, délai d'information des incidents, rotation des clés.
3. Termine par une **matrice de traçabilité** : chaque exigence `ENF-nn` et `ESC-nn` du cahier des charges → les `NF-nn` qui la couvrent, ou « non reprise » avec la raison.
4. MR relue par Karim (et Sophie pour la sécurité), fusionnée sur `main`.

**Contraintes**
- Chaque valeur cible est **soit** issue du cahier des charges, **soit** une décision de MédiSphère justifiée ; chaque capacité est issue d'un calcul écrit.
- Aucune exigence sans méthode de mesure. Si on ne sait pas encore la mesurer, le statut est *à construire*, et la phase 3 la construit (F7-S10).
- Les objectifs internes (SLO) peuvent être plus stricts que les engagements contractuels ; jamais l'inverse. Explique l'écart.

**Critères de réussite**
- [ ] `docs/capstone/exigences.md` est sur `main` avec au moins 15 exigences `NF-nn`, chacune liée à au moins une exigence du cahier des charges.
- [ ] La disponibilité porte un budget d'erreur mensuel chiffré en minutes, et sa méthode de mesure est écrite.
- [ ] La capacité cible est chiffrée en requêtes par seconde, avec le calcul (croissance, saisonnalité, marge) qui la produit ; les volumes de données à cinq ans sont chiffrés.
- [ ] RTO et RPO sont définis, chiffrés, et rapprochés de la mesure du F5.
- [ ] La matrice de traçabilité reprend au moins 80 % des exigences `ENF-nn` et `ESC-nn` du cahier des charges.

**Vérification** : `lab/bin/check F7 2` (présence, identifiants et quelques chiffres ; la justesse se juge avec le corrigé).

<details><summary>Indice 1</summary>

Un SLO de disponibilité se définit comme un rapport : événements bons / événements valides. « Valide » exclut ce que tu choisis d'exclure (et que tu écris) : maintenances annoncées, requêtes invalides du client (4xx), sondes. Le choix du **point de mesure** décide de ce que tu vois : une métrique de l'application ne voit pas une Gateway en panne ; une sonde externe voit tout mais avec une résolution grossière. Et 99,9 % sur un mois de 31 jours, ce n'est pas le même nombre de minutes que sur 28 jours glissants.
</details>

<details><summary>Indice 2</summary>

Pour la capacité, écris la chaîne : pointe d'aujourd'hui × croissance composée sur cinq ans × facteur saisonnier (est-il plausible de l'appliquer à la pointe du lundi ?) ÷ taux d'utilisation cible (quelle marge laisses-tu pour perdre un nœud, ou pour tout faire tourner sur le site de repli ?). Puis compare au débit mesuré au M29, en notant que ce débit vient d'un parcours qui n'a pas le même mélange lecture/écriture que la pointe du GHSV, sur un lab qui n'a pas le même matériel.
</details>

<details><summary>Indice 3</summary>

« Aucune requête ne doit dépasser 1 seconde » est un 100e centile : il suffit d'un ramasse-miettes, d'une bascule de base ou d'une requête de liste à 1 000 éléments pour le violer. Un engagement défendable porte sur un centile élevé (p99, p99,9) sur une fenêtre, avec ses exclusions. Pour le RPO, distingue ce que la réplication asynchrone peut perdre au pire et ce qu'on mesure en moyenne ; et cherche ce qui, côté processus, peut rendre un rendez-vous perdu **retrouvable** (qui d'autre en garde une trace ?).
</details>

**Pour aller plus loin** (facultatif) : écrire directement les `ServiceLevelObjective` Pyrra du GHSV et leurs tests `promtool` à partir de `exigences.md` (c'est le travail de F7-S10, mais commencer maintenant révèle les définitions encore floues) ; lire le chapitre « Implementing SLOs » du *Site Reliability Workbook* de Google (sre.google/workbook).
