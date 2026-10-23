# Final F5 — Phase 1 : Analyser

Un PRA commence par deux questions qu'aucun outil ne tranche : *qu'est-ce qui coûte, et combien, quand ça s'arrête ?* et *de quoi a besoin ce qui doit repartir ?* Les réponses fixent tout le reste : la taille de PAR2, ce qu'on y réplique, l'ordre de la reprise, ce qu'on accepte de perdre.

Prérequis de la phase : [`00-introduction.md`](00-introduction.md) lu, état d'entrée vérifié.

---

### F5-S01 — Analyse d'impact et objectifs de reprise  `RED` `★★`

> **Ticket PLAT-3501** — *De : Claire Morel* — *Copie : Julien Petit, Nadia Roussel, Sophie Laurent*
> La direction me demande « le RTO du PRA ». Il n'y en a pas un : il y en a un par service, et chacun doit se défendre devant quelqu'un qui paie. Je veux une analyse d'impact (BIA) service par service : ce que coûte une heure d'arrêt, une heure de données perdues, à partir de quand c'est intenable, et ce qu'on fait en attendant. Puis des objectifs de reprise que l'on sait atteindre avec `hp01` — ou, sinon, ce qu'il faudrait acheter. Julien et Nadia ont des chiffres. Les équipes Data et MédiVisio me demandent si elles sont « dans le PRA » : tranche, et écris pourquoi.

**Objectifs pédagogiques**
- Conduire une analyse d'impact sur l'activité : impacts dans le temps, durée maximale d'interruption admissible, perte de données maximale admissible.
- Distinguer RTO, RPO, durée maximale d'interruption et mode dégradé ; les relier aux capacités techniques réelles.
- Délimiter le périmètre d'un PRA et assumer par écrit ce qui en est exclu.

**Prérequis** : SLO du M21 (MédiAgenda), mesures de bascule du M29 et du F4 si faites, réplica de secours du M27.
**Durée indicative** : 3 h.

**Contexte technique** (chiffres de Julien et Nadia, à reprendre dans la BIA)
- **MédiAgenda** : 1 200 cabinets, ≈ 9 000 rendez-vous par jour ouvré, pointe de 8 h à 10 h (≈ 30 % des prises de la journée) ; un rendez-vous perdu = un patient qui se présente pour rien ou ne vient pas ; au-delà d'une demi-journée sans prise en ligne, le standard des cabinets sature (appels reportés). Valkey n'est qu'un cache.
- **MédiDoc** : pièces jointes des rendez-vous (ordonnances, comptes rendus) ; consultation surtout en consultation ; un document perdu est une perte de donnée de santé (déclaration possible) ; ≈ 1 500 dépôts par jour.
- **Legacy-RDV** : quarante cabinets historiques, prise de rendez-vous par le secrétariat (téléphone), habitués aux pannes ; sauvegarde **quotidienne** de sa base (M27/F4 : `Backup` de mariadb-operator vers `mariadb-legacy-rdv`) ; pièces jointes sur CephFS.
- **MédiNotif** : rappels SMS et courriels la veille des rendez-vous ; un message perdu se rejoue depuis MédiAgenda (les rendez-vous sont la source) ; un rappel en retard de quelques heures reste utile, un rappel du lendemain non.
- **MédiVisio** (F2) : téléconsultation en lancement, 30 praticiens pilotes, aucun engagement contractuel de disponibilité ; **Data** (F2) : statistiques d'activité, extraction nocturne pseudonymisée, aucun usage clinique.
- **Hors des applications** : la CI/CD, OpenStack, l'observabilité complète, le portail Backstage. Le contrat des cabinets (annexe HDS) promet une « reprise dans la journée ouvrée en cas de sinistre majeur ».
- Capacités connues : réplica de secours de la base par archive des WAL (`archive_timeout` 5 min au M27), sauvegardes PBS quotidiennes, instantanés OpenBao horaires (M25), `hp01` : 16 Go, 2 cœurs (≈ 8-10 Go pour les VMs de PAR2).
- Objectifs de référence que ta BIA doit **justifier ou contester** : MédiAgenda RTO 4 h / RPO 15 min ; MédiDoc RTO 8 h / RPO 1 h ; Legacy-RDV RTO 8 h / RPO 24 h ; MédiNotif RTO 8 h (messages en vol perdus, rejoués depuis MédiAgenda).

**Travail demandé**
1. Rédige `docs/pra/bia.md` : pour chaque service métier, les impacts dans le temps (1 h, 4 h, 1 jour, 3 jours) sur les patients, les cabinets, la conformité et la réputation ; la **durée maximale d'interruption admissible** et la **perte de données maximale admissible** ; les dépendances métier (qui ne peut rien faire sans qui) ; les procédures manuelles possibles en attendant.
2. Rédige `docs/pra/objectifs.md` : par service, RTO, RPO, mode dégradé accepté pendant le PRA (capacité, fonctions coupées, performance), et la **capacité technique** qui rend chaque objectif tenable (ou l'écart, et ce qu'il coûterait de le combler) ; le **périmètre** du PRA v1, avec ce qui en est exclu et pourquoi (MédiVisio, Data, CI, OpenStack, observabilité complète), et la **supervision minimale** de PAR2 que tu prévois pendant un PRA (ce qu'elle surveille, qui reçoit les alertes, ce qu'elle coûte en mémoire) ; les hypothèses (quel sinistre ? PAR1 perdu entièrement, PAR2 intact, équipe joignable) ; la **définition de la reprise** (à quel instant l'horloge du RTO s'arrête).
3. MR relue par Julien (MédiAgenda), Nadia (exploitation), Sophie (conformité), approuvée par Claire.

**Critères de réussite**
- [ ] `docs/pra/bia.md` est sur `main` et traite au moins MédiAgenda, MédiDoc, Legacy-RDV et MédiNotif, avec des impacts dans le temps et une durée maximale d'interruption pour chacun.
- [ ] `docs/pra/objectifs.md` est sur `main` avec un RTO et un RPO par service, le mode dégradé, le périmètre (exclusions motivées, dont MédiVisio et Data), la supervision minimale de PAR2 et la définition de la fin de reprise.

**Vérification** : `lab/bin/check F5 1` (présence et contenu minimal ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Le RTO n'est pas la durée maximale d'interruption admissible : c'est ce que l'on **s'engage** à tenir, et il doit être inférieur à elle avec une marge. Même chose pour le RPO et la perte maximale admissible. Si un objectif de référence te paraît trop ambitieux (ou trop timide) pour `hp01`, dis-le avec un chiffre.
</details>

<details><summary>Indice 2</summary>

« Reprise » doit se mesurer : choisis un critère observable de l'extérieur (une prise de rendez-vous réussie par le nom global, depuis un poste qui n'est pas dans le lab ?) plutôt que « le pod est `Running` ». Et décide d'où part l'horloge : la panne, sa détection, ou la décision de déclencher ? Les trois existent ; écris lesquels tu mesures.
</details>

<details><summary>Indice 3</summary>

Pour le RPO de MédiAgenda, regarde le chemin d'une écriture jusqu'à PAR2 : transaction validée → WAL archivé (quand ?) → objet dans `s3-01` → copié à PAR2 (combien de temps ?) → rejoué. Chaque étape a un délai ; le RPO est leur somme dans le pire cas, pas dans le cas moyen.
</details>

**Pour aller plus loin** (facultatif) : la norme ISO 22301 (management de la continuité d'activité) et la mesure 5.30 d'ISO 27001:2022 (« préparation des TIC pour la continuité d'activité ») : relève ce qu'un auditeur attendrait de plus que ta BIA ; le guide de l'ANSSI sur la continuité d'activité (« Guide pour réaliser un plan de continuité d'activité », SGDSN).

---

### F5-S02 — Les dépendances de la reprise et l'architecture de PAR2  `RED` `★★★`

> **Ticket PLAT-3502** — *De : Karim Benali* — *Copie : Claire Morel, Sophie Laurent*
> Avant de poser une seule VM sur `hp01`, je veux voir la carte complète de ce dont MédiAgenda a besoin pour démarrer **sans PAR1** : pas seulement « une base et un cluster ». Les noms, les certificats, la confiance, les images, les secrets, les comptes, le code, l'état OpenTofu, les identités — et pour chacun : où il vit aujourd'hui, où il vivra à PAR2, comment il y arrive, et comment on le vérifie. Puis un ordre de redémarrage. Puis l'architecture de PAR2 dans un ADR que je puisse relire, avec ce qu'on refuse de faire et pourquoi. Je cherche les boucles : la chose qui a besoin d'elle-même pour démarrer.

**Objectifs pédagogiques**
- Cartographier les dépendances techniques d'une reprise, y compris les dépendances « invisibles » (DNS, temps, confiance, identités, état d'outillage).
- Détecter les dépendances circulaires et les résoudre par un amorçage explicite.
- Concevoir un site de repli contraint (mémoire, disque, réseau) et en défendre les choix dans un ADR.

**Prérequis** : F5-S01 ; F1 (reconstruction depuis le code : amorçage des secrets, ordre de la couche de base) ; M25 (OpenBao, `kms01`, instantanés) ; M06 (racine hors ligne).
**Durée indicative** : 4 h.

**Contexte technique**
- Faits figés de PAR2 : [`00-introduction.md`](00-introduction.md) (hôtes, adresses, mémoire, noms globaux) et `PLAN.md` §4.15.
- Mécanismes de réplication retenus par l'équipe (à justifier, détailler ou contester dans l'ADR) : `weed filer.sync -isActivePassive` de `s3-01` vers `s3-02` (lancé sur `s3-02`) ; copie des compartiments MédiDoc du RGW vers `s3-02` par `rclone` (minuterie) ; *push mirrors* GitLab vers `adm02` (SSH, compte `miroir`) ; images et signatures copiées vers `reg02` par `cosign copy` (job planifié du runner protégé) ; base de MédiAgenda en **topologie distribuée** CloudNativePG (`mediagenda-db` ↔ `mediagenda-db-par2`, réplica alimenté par l'archive copiée sur `s3-02`).
- Confiance : la racine « MédiSphère Root CA » est **hors ligne** (`~/pki-racine` sur `adm01`, archives chiffrées) ; l'autorité en ligne (`ca01`, step-ca) est à PAR1 ; les certificats ACME durent 30 jours et se renouvellent à 15 jours.
- Secrets : OpenBao (`vault01-03`) est auto-descellé par `kms01` (transit) ; `kms01` est scellé par Shamir (5 parts, seuil 3) et sauvegardé uniquement par PBS ; les instantanés Raft horaires sont chiffrés `age` dans `s3://openbao-instantanes/` de `s3-01`.
- Identité : Keycloak (`idp01`) et FreeIPA (`ipa01`) sont à PAR1 et ne sont **pas** dans le périmètre du PRA v1 (mémoire) : décide comment on s'authentifie à PAR2 pendant un PRA.

**Travail demandé**
1. Rédige `docs/pra/dependances.md` :
   - un **inventaire des dépendances** de la reprise : pour chacune, sa source à PAR1, sa forme à PAR2, le mécanisme qui l'y amène et sa fréquence, son retard maximal, le contrôle qui prouve qu'elle est à jour, et le **secret ou la personne** nécessaire pour s'en servir ;
   - les **boucles** que tu as trouvées (au moins trois) et leur amorçage ;
   - un **ordre de redémarrage** de PAR2 en PRA, par vagues, avec pour chaque vague sa condition de passage (observable) ;
   - ce qui reste **impossible ou dégradé** sans PAR1 (et combien de temps on peut vivre ainsi) ;
   - les flux réseau nouveaux (PAR1 → PAR2, PAR2 → Internet), pour la matrice des flux.
2. Rédige `docs/pra/adr/ADR-0350-site-de-repli-par2.md` : contexte (BIA, contraintes de `hp01`), options comparées (au moins : sauvegardes seules et reconstruction à la demande ; site tiède sur `hp01` ; site chaud ; prestataire externe), décision, conséquences (y compris ce que l'on **accepte** : nœud unique, pas d'observabilité complète, `hp01` porteur des sauvegardes **et** du site de repli), risques et conditions de révision.
3. MR relue par Karim et Sophie, décision de Claire écrite dans l'ADR.

**Critères de réussite**
- [ ] `docs/pra/dependances.md` est sur `main` : il couvre au moins DNS, PKI ou certificats, secrets (OpenBao et `kms01`), images, code Git, état OpenTofu, données (base, objets), identité ou accès, temps (NTP) ; il donne un ordre de redémarrage par vagues et au moins trois boucles avec leur amorçage.
- [ ] `docs/pra/adr/ADR-0350-site-de-repli-par2.md` est sur `main` avec statut, contexte, options (au moins trois), décision, conséquences et risques.

**Vérification** : `lab/bin/check F5 2` (présence et contenu minimal).

<details><summary>Indice 1</summary>

Prends une requête d'un patient à PAR2 et remonte-la : le nom qu'il tape, qui le résout, quel certificat la Gateway présente et qui l'a signé, quelle image tourne et d'où le nœud la tire, quel Secret la configure et qui l'a écrit, quelle base répond et comment elle a reçu ses données. Puis fais la même chose pour **toi**, l'opérateur : comment tu te connectes à `adm02`, avec quel compte, quel certificat SSH, quel mot de passe Ansible Vault, quel jeton Proxmox.
</details>

<details><summary>Indice 2</summary>

Trois boucles classiques : (a) OpenBao se descelle par `kms01`, `kms01` se descelle par des parts que l'on garde… où ? (b) l'état OpenTofu de PAR2 doit vivre sur `s3-02`, que l'état OpenTofu de PAR2 décrit ; (c) le mot de passe d'Ansible Vault « critique » est, depuis le M25, lu **dans OpenBao**. Cherche aussi du côté des noms : la délégation `par1` de la zone parente, les certificats ACME de 30 jours, et l'API d'OpenBao que l'opérateur ESO de `k8s-par2` doit joindre.
</details>

<details><summary>Indice 3</summary>

Pour l'ADR, chiffre chaque option sur les mêmes axes : RTO atteignable, RPO, coût (matériel, temps humain d'entretien), risque pour les sauvegardes, complexité du retour. Une option « site chaud » que `hp01` ne peut pas porter n'est pas fausse : elle dit ce qu'il faudrait acheter, et c'est une information pour Claire.
</details>

**Pour aller plus loin** (facultatif) : représente les dépendances en graphe (Graphviz ou Mermaid dans le document) et calcule le chemin critique de la reprise ; compare ta carte avec les « dépendances implicites » recensées dans les retours d'expérience publics de grands incidents (par exemple la panne de Facebook d'octobre 2021 : les outils de reprise dépendaient du réseau qu'ils devaient réparer).
