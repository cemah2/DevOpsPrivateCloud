# Final F7 — Phase 2 : Concevoir

Le lab est une maquette fidèle : mêmes logiciels, mêmes principes, même code. Mais il tient sur un hyperviseur, son site de repli sur un vieux serveur de 16 Go, et il n'a jamais vu Internet. Le GHSV, lui, achète un service en production, sur deux vrais sites, pour cinq ans. Cette phase dessine cette production, décide ce qui doit l'être, la chiffre, et la planifie. Les quatre scénarios sont des rédactions, relues comme le reste par MR ; ce sont elles que le jury lira.

Prérequis de la phase : F7-S01 et F7-S02 fusionnés ; réponses du GHSV lues ([`ressources/S02/reponses-aux-candidats.md`](../ressources/S02/reponses-aux-candidats.md)).

---

### F7-S03 — L'architecture cible de production  `RED` `★★★★`

> **Ticket PLAT-3703** — *De : Karim Benali* — *Copie : Sophie Laurent, Julien Petit, Claire Morel*
> J'ai lu `exigences.md` : ta capacité cible avec un nœud en moins, la même chose à PAR2 en PRA, des pièces jointes, des journaux pendant un an, Internet en façade, et un IdP qui n'est pas le nôtre. Dessine-moi la **vraie** production : les deux sites, le matériel, ce qui tourne où, comment le trafic entre, comment on bascule. Et le dimensionnement, à partir de **nos** mesures, pas d'un abaque de constructeur : je veux voir le coût d'une requête mesuré sur la recette et le calcul qui en sort un nombre de serveurs. Termine par la liste honnête de ce qui change par rapport au lab, et des points uniques de défaillance qui restent.

**Objectifs pédagogiques**
- Concevoir une architecture de production sur deux sites à partir d'exigences chiffrées et d'une plateforme existante.
- Dimensionner à partir de mesures (coût par requête, volumes), avec des facteurs explicites entre le lab et la production.
- Identifier ce qu'un environnement de laboratoire ne montre pas : exposition publique, redondance matérielle, points uniques de défaillance, contraintes d'hébergement certifié.

**Prérequis** : F7-S02 ; M29-E14 (k6-operator, référence, RB-295) ; F4-S02 (sonde de continuité) ; F5 (architecture de PAR2, bascule, noms globaux) ; M07 (répartiteurs), M08 (Ceph), M09 (cluster Proxmox), M15 (Gateway, LB IPAM), M24 (Keycloak), M25 (OpenBao, `kms01`).
**Durée indicative** : 6 à 8 h (dont 1 à 2 h de mesure sur la recette).

**Contexte technique**
- Référence de charge de MédiAgenda (M29-E14) : `plateforme/resilience`, `charge/references/mediagenda-recette.json` ; script `charge/distribue/mediagenda-recette.js` (paramètres `TAUX_CIBLE`, `PALIER`) ; verdict lu dans Prometheus (RB-295). La recette de MédiAgenda est pilotée par un HPA (2 à 4 pods, M28) : pour mesurer un **coût par requête**, il faut savoir combien de pods tournaient et ce qu'ils consommaient pendant chaque palier.
- Mélange de requêtes attendu chez le GHSV : ton hypothèse de S01 (R-01 ne donne pas la répartition ; le parcours du M29 écrit à chaque itération : il est plus lourd que la pointe du GHSV).
- Hébergement : les salles de MédiSphère sont dans des centres de données certifiés HDS pour l'activité 1 (hypothèse du final) ; MédiSphère y loue des baies (espace, énergie, refroidissement, accès Internet de l'hébergeur en option).
- Dans le lab, aucun service n'est exposé à Internet, `idp01` et `kms01` sont uniques, PAR2 est un nœud Proxmox unique de 16 Go, l'interconnexion est un tunnel WireGuard sur un réseau domestique.
- Le nom public est celui du GHSV (`rendez-vous.ghsv.example`, annexe A1) ; en cas de PRA, les noms de service de MédiSphère basculent par CNAME (F5).

**Travail demandé**
1. **Mesure** : relève sur la recette de MédiAgenda le coût d'une charge connue (au moins deux paliers de débit) : CPU et mémoire de l'API, du pooler, de PostgreSQL et de Valkey, latences p95/p99 serveur, nombre de pods. Écris la méthode et le résultat (`testid`, fenêtres, requêtes) dans le document : c'est la base du dimensionnement.
2. Rédige `docs/capstone/architecture.md` :
   - une **vue d'ensemble** (schéma : sites, flux des patients, du DPI et des agents, interconnexion, sauvegardes) ;
   - **par site** : matériel (serveurs, stockage, réseau, sécurité périmétrique), virtualisation, Kubernetes, données, identité, secrets, observabilité, sauvegarde ;
   - l'**exposition Internet** : noms, certificats, protection contre le déni de service, filtrage, limites de débit ;
   - la **bascule** du GHSV vers PAR2 et le retour ;
   - le **dimensionnement** : du coût par requête mesuré aux capacités cibles de `exigences.md` (PAR1 et repli), des volumes à cinq ans au stockage brut, avec chaque facteur justifié ; la part de la plateforme que consomme le GHSV ;
   - **ce qui change par rapport au lab**, élément par élément ;
   - les **points uniques de défaillance** qui restent, et pourquoi on les accepte (ou pas) ;
   - les hypothèses.
3. MR relue par Karim (et Sophie pour l'exposition et l'isolation), fusionnée sur `main`.

**Contraintes**
- Mêmes logiciels que la plateforme (pas de nouveau produit sans le justifier) : le jury doit pouvoir rattacher chaque brique à ce que la démonstration montrera.
- Chaque nombre de serveurs, de vCPU ou de To vient d'un calcul écrit à partir d'une mesure ou d'une hypothèse identifiée.
- Aucun point unique de défaillance non écrit sur le chemin de la prise de rendez-vous à PAR1.
- La mesure de charge se fait sur la **recette**, jamais sur la production, avec les données factices du M29.

**Critères de réussite**
- [ ] `docs/capstone/architecture.md` est sur `main` avec les sections vue d'ensemble, PAR1, PAR2, exposition, PRA ou bascule, dimensionnement, écarts avec le lab, points uniques de défaillance.
- [ ] Le document contient un schéma (bloc Mermaid, image versionnée ou schéma texte).
- [ ] Le dimensionnement cite la mesure (référence du M29 ou ta mesure, avec son `testid`) et chiffre la capacité en req/s, le calcul en vCPU (ou cœurs), la mémoire et le stockage en Go ou To.
- [ ] Le nombre de serveurs de chaque site est écrit.
- [ ] Les écarts avec le lab sont listés (au moins exposition Internet, PAR2, fournisseur d'identité, interconnexion).

**Vérification** : `lab/bin/check F7 3` (présence et contenu minimal ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Le coût par requête se lit dans Prometheus pendant un palier stable : CPU consommé (`container_cpu_usage_seconds_total`, en taux) des conteneurs de chaque composant, divisé par le débit servi (`mediagenda_http_requests_total`, en taux). Deux paliers permettent de séparer la part fixe (ce qui tourne même sans charge) de la part proportionnelle. Ne lis pas les `requests` des pods : c'est une réservation, pas une consommation.
</details>

<details><summary>Indice 2</summary>

Fais le calcul dans l'ordre : capacité à tenir (ta capacité cible de S02) × coût par requête → vCPU utiles ; ÷ utilisation cible → vCPU à réserver ; + ce qui ne dépend pas de la charge (plan de contrôle, opérateurs, observabilité, Keycloak, OpenBao) ; puis N+1 sur les hyperviseurs. Tu constateras que la charge du GHSV pèse peu : ce qui dimensionne la production, c'est la redondance, le site de repli à pleine capacité et le stockage. Compare avec ce que le F5 a mis à PAR2.
</details>

<details><summary>Indice 3</summary>

Pour les points uniques de défaillance, suis une prise de rendez-vous d'un agent, de son navigateur jusqu'au disque : DNS public, accès Internet, répartiteur, Gateway, API, pooler, PostgreSQL, Ceph… et le fournisseur d'identité, sans lequel aucun agent ne se connecte. Dans le lab, `idp01` est seul. Est-ce acceptable pour un engagement à 99,9 % ? Et `kms01` : que se passe-t-il s'il est arrêté au moment où un nœud OpenBao redémarre ?
</details>

**Pour aller plus loin** (facultatif) : un modèle de capacité sous forme de tableur (débit → pods → nœuds → serveurs) réutilisé pour les autres clients ; une revue de l'architecture selon le pilier « fiabilité » d'un cadre public (par exemple les questions du *Well-Architected Framework*, transposées au cloud privé).

---

### F7-S04 — Les décisions d'architecture  `RED` `★★★`

> **Ticket PLAT-3704** — *De : Karim Benali* — *Copie : Sophie Laurent, Thomas Renaud, Julien Petit*
> Ton architecture repose sur des choix que le jury va attaquer un par un : pourquoi le GHSV partage-t-il notre cluster ? Que veulent dire « clés dédiées » chez nous ? Comment ses agents se connectent-ils sans compte chez nous, et ses patients ? Que devient son service si PAR1 brûle, et ses rendez-vous de la dernière minute ? Comment récupère-t-il tout, et comment prouve-t-on qu'on a tout détruit ? Je veux une ADR par décision, au format des nôtres, avec les options écartées et ce qu'elles nous auraient coûté. Thomas relit tout ce qui touche aux données personnelles.

**Objectifs pédagogiques**
- Formaliser des décisions d'architecture structurantes pour un client hébergé : options, critères, conséquences, conditions de révision.
- Relier chaque décision aux exigences du client et aux capacités réelles de la plateforme.
- Anticiper les questions d'un jury technique et d'un DPO.

**Prérequis** : F7-S03 ; ADR existantes de la plateforme (format : `docs/*/adr/`, par exemple ADR-0290 du M29, ADR-0320 du F2, ADR-0350 du F5) ; F2 (équipe en code, locataires Capsule) ; M24 (Keycloak, courtier d'identité) ; M25 (OpenBao, `transit`) ; F5 (PRA) ; F6 (preuves, verrouillage d'objets, transferts hors EEE).
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- Numérotation : `ADR-0370` à `ADR-0379`, dans `docs/capstone/adr/`, un fichier par décision : `ADR-037x-<sujet>.md`.
- Objets que la phase 3 créera (noms figés) : locataire `ghsv` dans `plateforme/equipes` (`equipes/ghsv.yaml`), espaces `ghsv-recette`, `ghsv-prod`, clés `transit/ghsv-*` d'OpenBao, royaume Keycloak `ghsv-idp` sur `idp01` (qui **simule** le fournisseur d'identité du GHSV) déclaré comme fournisseur d'identité OIDC dans le royaume `medisphere`. Tes ADR décident de la cible de production ; si elles s'écartent de ce que le lab montrera, elles le disent.
- Le GHSV ne veut pas détenir ses clés mais veut pouvoir rendre ses données illisibles (R-14) ; il maintient ENF-07 (R-11) ; il accepte une proposition sur les journaux en fin de marché (R-17).

**Travail demandé**
1. Rédige au moins **quatre** ADR parmi ces cinq sujets (les cinq si tu peux) :
   - l'**isolation** du client dans la plateforme ;
   - les **clés dédiées** : quelles données sont chiffrées avec quelles clés, où vivent les clés, rotation, destruction, et ce que la destruction rend illisible ;
   - la **fédération d'identité** : agents (IdP du GHSV), patients (comptes locaux), DPI (compte de service), et ce qu'on fait de l'exigence « aucun compte local d'agent » ;
   - le **PRA du client** : ce qui bascule, comment, avec quelle capacité, et comment ENF-07 est tenue ;
   - la **réversibilité** : format de l'export, outil, vérification par un tiers, destruction et ce qu'on conserve.
2. Chaque ADR : statut, décideurs, ticket, contexte (avec les exigences du cahier des charges concernées), décision, **options étudiées** (au moins deux écartées, avec la raison), **conséquences** (ce qu'on gagne, ce qu'on perd, coût, travail pour la phase 3), conditions de **révision**.
3. MR relue par Karim, Sophie et Thomas, fusionnée sur `main`.

**Contraintes**
- Une ADR décide : « on pourrait » n'est pas une décision.
- Chaque option écartée l'est pour une raison vérifiable (une mesure, un coût, une limite documentée, une exigence), pas par goût.
- Aucune décision ne contredit une exigence éliminatoire du cahier des charges (ESC-01, ESC-03, ESC-04).

**Critères de réussite**
- [ ] Au moins quatre fichiers `docs/capstone/adr/ADR-037x-*.md` sont sur `main`.
- [ ] Chacun a un statut, et des sections contexte, décision, options (ou alternatives) et conséquences.
- [ ] Chacun cite au moins une exigence du cahier des charges.
- [ ] Ensemble, ils couvrent au moins quatre des cinq sujets.

**Vérification** : `lab/bin/check F7 4` (présence et structure ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Pour l'isolation, place les options sur une échelle : un espace de noms de plus ; un locataire Capsule (quotas, politiques, propriétaires) ; des nœuds dédiés ; un cluster virtuel ; un cluster dédié ; une infrastructure dédiée. Pour chacune : ce qu'elle isole vraiment (calcul, réseau, données, clés, administration, pannes), ce qu'elle coûte, et ce que le cahier des charges exige réellement. « Dédié » dans un cahier des charges vise souvent les **clés** et les **données**, pas les machines.
</details>

<details><summary>Indice 2</summary>

Pour les clés, pars de la question de R-14 : « si on détruit la clé, qu'est-ce qui devient illisible ? ». Une clé qui ne chiffre que la base vivante laisse lisibles les sauvegardes, les copies de PAR2, les journaux et les exports. Regarde ce que chaque couche sait faire avec un service de gestion de clés externe (chiffrement côté serveur du stockage objet, volumes chiffrés, chiffrement applicatif par `transit`), et ce qui en est **vérifié** par la documentation officielle de nos versions.
</details>

<details><summary>Indice 3</summary>

Pour l'identité, distingue trois populations qui n'ont ni les mêmes risques ni les mêmes volumes : 9 200 agents (fédérés, MFA chez le GHSV), 400 000 patients (comptes locaux, inscription libre, attaques par bourrage d'identifiants) et un DPI (machine, flux *client credentials*). Mettre les patients dans le même royaume que les personnels de MédiSphère serait-il raisonnable ? Et les agents du GHSV ?
</details>

**Pour aller plus loin** (facultatif) : une ADR « exposition Internet » (protection contre le déni de service, pare-feu applicatif, limites de débit par client) ; une ADR sur l'hébergement de plusieurs clients (ce qui change au deuxième client).

---

### F7-S05 — Chiffrage et coût complet sur cinq ans  `RED` `★★★`

> **Ticket PLAT-3705** — *De : Claire Morel* — *Copie : Karim Benali, Nadia Roussel*
> La direction financière me demande trois choses : combien ça nous coûte vraiment de servir le GHSV pendant cinq ans (pas seulement le matériel : les gens, les licences, les audits, les SMS, la quote-part de ce qu'on a déjà), à combien on le vend, et si on ne ferait pas mieux de l'héberger chez un cloud public certifié HDS ou de le faire infogérer. Je ne veux pas de prix inventés présentés comme des devis : des ordres de grandeur, datés, sourcés, marqués « à vérifier », et des hypothèses que je peux changer dans un tableur. Et dis-moi quels chiffres font basculer la décision.

**Objectifs pédagogiques**
- Établir un coût complet (TCO) sur plusieurs années : investissement, amortissement, exploitation, personnel, quote-part mutualisée, coûts ponctuels.
- Comparer des scénarios d'hébergement sur une base commune et identifier les variables qui changent la décision (sensibilité).
- Présenter des chiffres non contractuels honnêtement : sources, dates, hypothèses, incertitudes.

**Prérequis** : F7-S03, F7-S04 ; outil `ms-showback` du F2 (coût par équipe) si tu l'as fait.
**Durée indicative** : 5 à 6 h.

**Contexte technique**
- Durée : cinq années de marché (mars 2027 à février 2032). Prix **hors taxes**, en euros, en ordres de grandeur d'**octobre 2026**.
- Le bordereau de prix du GHSV est au §11.3 du CCTP (P1 à P7) ; R-04 définit le comptage des rendez-vous ; R-05 le volume de SMS.
- Marché du matériel au relevé : les prix de la mémoire des serveurs ont fortement augmenté en 2026 (hausses trimestrielles de l'ordre de 80 à 90 % début 2026 selon les cabinets d'analyse du marché des semi-conducteurs) ; les délais de livraison s'en ressentent. Un prix de serveur relevé aujourd'hui peut être faux dans trois mois.
- Le tableur `chiffrage.csv` est lu par le check : séparateur virgule (ou point-virgule), une ligne par poste et par scénario, colonnes **au moins** `scenario`, `poste`, `categorie` (`CAPEX` ou `OPEX`), `annee_1` à `annee_5`, `total_5_ans`, `hypothese` (identifiant d'hypothèse ou source) ; montants entiers en euros, sans séparateur de milliers. Tu peux ajouter des colonnes.

**Travail demandé**
1. Rédige `docs/capstone/chiffrage.md` :
   - les **hypothèses** (`H-nn`, ou une série dédiée) : volumes, effectifs, durées d'amortissement, clés de répartition des coûts mutualisés, prix unitaires avec leur source et leur date ;
   - le **coût complet sur cinq ans** du scénario « plateforme MédiSphère » : matériel (amorti), hébergement des baies, liaisons, souscriptions, SMS, certifications et audits, test d'intrusion, personnel (projet et run, astreinte), développements, quote-part de la plateforme existante ;
   - deux **comparaisons** sur le même périmètre : hébergement dans un **nuage public certifié HDS** (fournisseur européen, la plateforme Kubernetes reconstruite dessus) et **solution infogérée** (un infogérant HDS opère l'infrastructure, MédiSphère l'application) ; ce qui reste à notre charge dans chaque cas ;
   - le **prix proposé** au GHSV (lignes P1, P2, P3, P7 du bordereau), avec la marge et le point mort ;
   - une **analyse de sensibilité** : les trois ou quatre variables qui font changer le classement des scénarios ou la rentabilité ;
   - ta **recommandation**.
2. Produis `docs/capstone/chiffrage.csv` conforme au format ci-dessus, cohérent avec le document (mêmes totaux).
3. MR relue par Claire, fusionnée sur `main`.

**Contraintes**
- Aucun prix présenté comme un devis : chaque prix unitaire porte sa source (page publique, ordre de grandeur, estimation interne) et la mention « à vérifier ».
- Les trois scénarios couvrent le **même** périmètre (deux sites, mêmes engagements) ; ce qui n'est pas comparable est dit.
- Les totaux de chaque ligne du tableur sont la somme de ses cinq années.

**Critères de réussite**
- [ ] `docs/capstone/chiffrage.md` est sur `main` avec les hypothèses, le coût complet du scénario retenu, les deux comparaisons, le prix proposé, la sensibilité et la recommandation ; les prix sont datés et marqués « à vérifier ».
- [ ] `docs/capstone/chiffrage.csv` est sur `main`, lisible (même nombre de colonnes sur chaque ligne), avec les colonnes demandées.
- [ ] Le tableur couvre au moins trois scénarios, contient des lignes `CAPEX` et `OPEX`, et chaque `total_5_ans` est la somme de `annee_1` à `annee_5`.

**Vérification** : `lab/bin/check F7 5` (présence, format et cohérence arithmétique ; la justesse des hypothèses se juge avec le corrigé).

<details><summary>Indice 1</summary>

Le coût le plus sous-estimé d'un service hébergé est le **personnel** : astreinte 24 h/24, support du samedi (EXP-01), tests de PRA, rapports mensuels, revues d'accès, audits, test d'intrusion à piloter. Compte en équivalents temps plein, au coût complet employeur (salaire chargé), pas au salaire brut. Le deuxième est la **quote-part** de ce qui existe déjà : le GHSV utilise notre supervision, notre PBS, nos salles, notre équipe ; s'il ne paie pas sa part, c'est MédiSphère qui la paie.
</details>

<details><summary>Indice 2</summary>

Pour le nuage public, ne compare pas « des VMs » : reconstruis le même service (deux régions ou zones, Kubernetes, stockage objet, sauvegardes hors du fournisseur, sortie de données, protection contre le déni de service), et garde ce qui reste à ta charge (exploitation de Kubernetes et des applications, astreinte, sécurité, certification des activités que le fournisseur ne couvre pas). Pour l'infogérance, demande-toi qui tient l'astreinte de quoi, et ce que coûte la coordination.
</details>

<details><summary>Indice 3</summary>

La sensibilité se fait en faisant varier une hypothèse à la fois (± 30 % ou ± 50 %) et en regardant ce qui change : le classement des scénarios ? la marge ? le point mort ? Sur un petit client comme le GHSV, le prix des SMS ou le nombre d'ETP pèsent souvent plus que le prix d'un serveur.
</details>

**Pour aller plus loin** (facultatif) : un modèle de coût en code (script qui produit `chiffrage.csv` à partir d'un fichier d'hypothèses YAML, pour que chaque hypothèse change par MR et que le tableur ne diverge jamais du document) ; la valeur actuelle nette des flux sur cinq ans avec un taux d'actualisation.

---

### F7-S06 — Planning, risques et organisation du run  `RED` `★★`

> **Ticket PLAT-3706** — *De : Nadia Roussel* — *Copie : Claire Morel, Julien Petit, Sophie Laurent*
> Le 1er mars, cinq établissements basculent chez nous, avec leurs données, et le 30 juin les douze. Entre la notification fin janvier et le 1er mars, il y a quatre semaines. Je veux un planning qui tient debout (avec ce qu'on lance avant la notification, à nos risques, et ce qui ne peut pas être prêt), un registre des risques avec un propriétaire pour chacun, qui fait quoi (RACI) chez nous et chez le GHSV, et l'organisation du run : support du lundi au samedi, astreinte 24 h/24, rapport mensuel, et comment on forme l'équipe. Aujourd'hui, l'astreinte, c'est cinq personnes dont un stagiaire.

**Objectifs pédagogiques**
- Construire un planning réaliste sous contraintes fortes (date imposée, dépendances client, délais d'approvisionnement), avec son chemin critique.
- Tenir un registre des risques exploitable (probabilité, impact, propriétaire, réponse, indicateur de déclenchement).
- Organiser l'exploitation d'un service engagé contractuellement : niveaux de support, astreinte, rituels, montée en compétences.

**Prérequis** : F7-S03 à F7-S05 ; F3 (astreinte, gestion d'incident) ; F4 (processus de changement) ; F5 (cellule de crise, exercice de PRA).
**Durée indicative** : 3 à 4 h.

**Contexte technique**
- Calendrier : introduction du final et R-18 (vagues jusqu'au 30 juin 2027) ; EXP-06 (recette au GHSV 10 jours ouvrés avant la production) ; EF-08 (reprise des données, export de l'outil actuel) ; ENF-08 (test du PRA annuel en présence du GHSV).
- Équipe Plateforme aujourd'hui : Claire Morel, Karim Benali, toi, Lucas Martin (stagiaire), avec Nadia Roussel pour le support et l'astreinte ; équipe MédiAgenda de Julien Petit (développement).
- Fournitures du GHSV : nom de domaine, IdP (enregistrement du client OIDC), export de l'outil actuel, export quotidien des praticiens (R-07), environnement de recette du DPI.

**Travail demandé**
1. Rédige `docs/capstone/planning.md` : jalons datés de la soutenance au 30 juin 2027 (et le premier test de PRA), lots de travail, dépendances (internes, GHSV, fournisseurs), **chemin critique**, travaux lancés avant la notification et leur risque, ce qui ne sera pas prêt au 1er mars et la réponse proposée, **RACI** des activités principales (MédiSphère et GHSV).
2. Rédige `docs/capstone/risques.md` : au moins dix risques `RSQ-nn` (pas `R-nn` : ces identifiants sont ceux des réponses du GHSV) (projet, technique, sécurité, conformité, fournisseurs, humains, financiers), chacun avec probabilité, impact, criticité, propriétaire, réponse (éviter, réduire, transférer, accepter), actions, indicateur de déclenchement.
3. Rédige `docs/capstone/run.md` : niveaux de support et horaires, astreinte (rotation, effectif, rémunération ou récupération, escalade), traitement des P1 à P3 (EXP-02), rituels (comités, revue de capacité, revue des accès), rapport mensuel, changements chez le GHSV, montée en compétences de l'équipe (formation, binômes, exercices) et recrutements.
4. MR relue par Nadia et Claire, fusionnée sur `main`.

**Contraintes**
- Le planning distingue ce qui est **engagé** (contractuel) de ce qui est **interne**.
- Une astreinte 24 h/24 tenue par moins de quatre personnes formées n'est pas une astreinte : dis comment tu y arrives, ou ce que tu proposes à la place.
- Chaque risque a un propriétaire nommé (un personnage ou un rôle), pas « l'équipe ».

**Critères de réussite**
- [ ] `docs/capstone/planning.md` est sur `main`, avec des jalons datés couvrant au moins le 1er mars et le 30 juin 2027, un chemin critique et une matrice RACI.
- [ ] `docs/capstone/risques.md` est sur `main`, avec au moins dix risques `RSQ-nn`, chacun avec probabilité, impact et propriétaire.
- [ ] `docs/capstone/run.md` est sur `main` et traite le support (dont le samedi), l'astreinte, les priorités P1 à P3, le rapport mensuel et la montée en compétences.

**Vérification** : `lab/bin/check F7 6` (présence et contenu minimal ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Le chemin critique ne passe probablement pas par l'infrastructure (elle existe, et le GHSV est petit) mais par le **développement** (ton estimation de S01) et par les **dépendances du GHSV** (export de l'outil actuel, enregistrement du client OIDC, DPI en recette). Commence par le 1er mars et remonte. Qu'est-ce qui doit être vrai le 26 février, jour du go/no-go de la vague 1 ?
</details>

<details><summary>Indice 2</summary>

Le matériel de PAR2 commandé à la notification arrivera-t-il avant le 1er mars ? Si non, quelle couverture PRA offres-tu entre le 1er mars et sa mise en service, et comment le dis-tu au GHSV (réserve écrite, plan de transition, test de PRA décalé) ? Un risque connu et écrit dans l'offre n'est pas un risque de pénalité : c'est une condition.
</details>

<details><summary>Indice 3</summary>

Pour l'astreinte, compte : 52 semaines, une semaine sur N par personne, congés, départs, et un stagiaire qui ne peut pas être seul d'astreinte. Puis regarde ce que les runbooks (F3, F5) et les alertes permettent à quelqu'un qui ne connaît pas le GHSV de faire seul à 3 h du matin.
</details>

**Pour aller plus loin** (facultatif) : un diagramme de Gantt en Mermaid généré depuis un fichier de jalons ; une simulation de Monte-Carlo de la date de fin du développement à partir d'estimations en trois points.
