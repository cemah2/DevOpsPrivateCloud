# Phase 3 — L'équipe Data : des données utiles, jamais la production

L'équipe Data existe (S02) : un groupe, le locataire `data`, l'espace `data-traitements`, un coffre, une adresse d'alertes. Hugo Bernard doit livrer à la direction des statistiques d'activité de MédiAgenda, chaque mois. Il a trois besoins : une base à lui, des données à jour chaque matin, des traitements de nuit qui ne gênent personne. Et il a déjà ouvert un ticket pour « juste un accès en lecture à la base de prod ». Sophie Laurent suit la phase de près : la table `rendez_vous` contient des données de santé.

> **Rappels** : tout se lance depuis `adm01` ; ton kubeconfig personnel (OIDC) pour lire, `admin.conf` en bris de glace ; `kubectl cnpg`, `bao`, `aws` (S3), `psql` ; les clones `~/src/equipes`, `~/src/k8s`, `~/src/secrets`, `~/src/observabilite`, `~/src/ceph`, `~/src/outils`, `~/medisphere`. Le dépôt de l'équipe Data (`data/deploiement`, créé par l'équipe et synchronisé par son projet Argo CD) est **le sien** : tu peux l'amorcer avec Hugo, mais ce qui relève de la plateforme (quota, coffre, exposition, politiques) reste dans les dépôts de la plateforme.

---

### F2-S07 — Des bases en libre-service pour l'équipe Data  `LIBRE` `★★★★`

> **Ticket DEV-3207** — *De : Hugo Bernard*
> Bonjour ! Pour les statistiques mensuelles, il me faut une base PostgreSQL à nous (Sarah et moi y créerons nos tables et nos requêtes), et chaque matin les rendez-vous de MédiAgenda de la veille, sur au moins un an. Je n'ai besoin ni des noms ni des motifs, mais il faut que je puisse compter les patients distincts, regarder l'activité par praticien et les délais de réservation. On peut se voir pour voir ce qui est possible ?
>
> *Commentaire de Sophie Laurent* : d'accord sur le principe, à condition que l'équipe Data n'ait **aucun** chemin vers les données identifiantes : ni compte, ni flux, ni secret. Je veux lire la décision avant la mise en service.

**Objectifs pédagogiques**
- Offrir une base de données **en libre-service** sans perdre les garanties de la plateforme (sauvegarde, limites, identifiants courts), en les imposant par le code plutôt que par la confiance.
- Concevoir un flux de données d'une zone de santé vers une zone d'analyse : minimisation, pseudonymisation, sens du flux, propriétaire de la décision.
- Faire porter un changement de schéma par l'équipe propriétaire de la donnée (migration *expand*), et un rôle par CloudNativePG, sans geste manuel sur la production.
- Observer un traitement sur des données sensibles **sans lire les données** (métriques de contrôle).

**Prérequis** : S02 (équipe `data` et espace `data-traitements`), S03 ; M16 (CloudNativePG, plugin Barman Cloud), M25 (moteur `database`, ESO), M26 (Kyverno, politiques CEL), M27 (rôles déclaratifs, Flyway, réplica de secours `mediagenda-db-secours`, RB-275).
**Durée indicative** : 8 à 12 h.

**Contexte technique**
- Table source : `public.rendez_vous` de la base `mediagenda` (Cluster `mediagenda-db`, espace `mediagenda-prod`) : `id`, `patient` (nom saisi), `praticien`, `debut`, `duree_minutes`, `motif` (texte libre), `cree_le`, `canal_rappel` (`sms`, `mail`, `aucun`), `contact_rappel` (téléphone ou courriel) — migrations V1 à V4 de `mediagenda/api` (Flyway, M27). Le réplica autonome **`mediagenda-db-secours`** (espace `mediagenda-secours`) rejoue l'archive de la prod avec quelques minutes de retard ; il est **en lecture seule** : on n'y crée ni rôle, ni vue, ni table.
- Noms de référence : Cluster **`statistiques-db`** dans **`data-traitements`**, base **`statistiques`**, table d'extraction **`stats.rendez_vous`** ; dépôt de l'équipe **`data/deploiement`**.
- Contrat de supervision (lu par la plateforme et par le check, qui ne lit jamais les données) : la base Data publie, par les requêtes personnalisées de CloudNativePG, trois métriques — **`cnpg_stats_extraction_lignes`** (lignes du dernier chargement), **`cnpg_stats_extraction_age_secondes`** (âge du dernier chargement) et **`cnpg_stats_extraction_colonnes_presente`** (une série par colonne de `stats.rendez_vous`, étiquette `colonne`). Une colonne pseudonymisée porte `pseudo` dans son nom.
- Stockage objet : `s3-01` (SeaweedFS, identités et compartiments déclarés dans `plateforme/ansible`, `host_vars/s3-01/seaweedfs.yml`) ; le compartiment `cnpg-k8s-par1` contient l'archive de la **production** : aucune identité d'équipe n'y écrit.
- OpenBao (vault01-03, hors du cluster) joint une base par un Service `LoadBalancer` réservé, filtré sur `vault01-03` (modèle M25-E14). Adresse réservée pour la base Data : **10.10.41.66**. Le quota rendu par l'équipe en code interdit aujourd'hui tout `LoadBalancer` dans les espaces d'équipe.
- Tu choisis où s'exécute l'extraction (un traitement de l'équipe Data qui lit, ou un traitement côté MédiAgenda qui dépose) : **la décision et sa justification font partie du livrable**.

**Travail demandé**
1. **Décider** (avec Sophie et Julien) comment les données passent de MédiAgenda à l'équipe Data : sens du flux, qui exécute, qui détient quels secrets, ce qui sort et ce qui ne sort jamais, comment on pseudonymise (et pourquoi un pseudonyme reste une donnée personnelle), fraîcheur, conservation. ADR **ADR-0327** dans `docs/accueil/adr/`.
2. **La base en libre-service** : l'équipe Data déclare son Cluster dans son dépôt ; la plateforme **impose** par une politique d'admission, dans les espaces des locataires, l'archivage des WAL par le plugin Barman Cloud, une classe de stockage, des requests et une limite mémoire, et l'absence de superutilisateur (exceptions justifiées). Sauvegardes vers un compartiment propre à l'équipe, sauvegarde de base planifiée.
3. **Les identifiants** : personne ne connaît de mot de passe permanent de la base Data. Les traitements et les analystes obtiennent des identifiants de courte durée par OpenBao ; les droits viennent de rôles de groupe déclarés avec la base. Ce que le mécanisme d'équipe en code ne sait pas encore exprimer (exposition de la base à OpenBao), tu l'ajoutes **au mécanisme** ou en complément écrit de la plateforme, jamais dans un fichier rendu.
4. **L'extraction** : une vue (ou un équivalent) pseudonymisée côté MédiAgenda, livrée par la **chaîne de MédiAgenda** (migration, rôle géré par CloudNativePG), un traitement nocturne qui l'amène dans `stats.rendez_vous` sans aucun lien entre l'équipe Data et les bases de MédiAgenda, des contrôles d'intégrité (le fichier ou le lot reçu est complet), les métriques du contrat ci-dessus et des alertes (retard, lot vide, colonne identifiante apparue).
5. **Le runbook** **RB-327** (`docs/accueil/runbooks/`) : chaîne horaire, diagnostic d'un retard, rotation des secrets (y compris la clé de pseudonymisation, si tu en as une), suspension d'urgence.

**Contraintes**
- Aucune charge, aucun verrou, aucun geste manuel sur `mediagenda-db` en production. Le réplica de secours reste d'abord un réplica de **secours** : l'extraction ne retarde jamais une reprise (RB-275).
- L'équipe Data n'a **aucun** flux réseau vers un espace `mediagenda-*`, **aucun** rôle dans une base de MédiAgenda, **aucun** secret de MédiAgenda ; les espaces `mediagenda-*` n'acceptent aucune entrée depuis `data-traitements`.
- Ni nom, ni motif, ni coordonnées, ni horodatage exact ne quittent MédiAgenda ; les identifiants qui sortent ne permettent pas de remonter à l'identifiant d'origine sans un secret qui reste chez MédiAgenda.
- Les objets de l'équipe passent par son projet Argo CD ; les tiens par les dépôts de la plateforme. Une exception (`kubectl apply` des espaces de la plateforme, M27) est écrite.

**Critères de réussite**
- [ ] `statistiques-db` est sain, archive ses WAL par le plugin Barman Cloud, a une sauvegarde de base réussie depuis moins de 36 h, une `ScheduledBackup` active, des requests et une limite mémoire, pas de superutilisateur.
- [ ] Une politique d'admission refuse un Cluster CloudNativePG non conforme dans un espace de locataire (essai écrit dans l'ADR ou le journal).
- [ ] Les métriques `cnpg_stats_extraction_*` sont servies par Prometheus : table non vide, chargée depuis moins de 36 h, au moins une colonne `*pseudo*`, aucune colonne identifiante (nom, motif, contact, horodatage exact, identifiant d'origine).
- [ ] Aucune règle réseau de `data-traitements` ne vise un espace `mediagenda-*` ; aucune règle des espaces `mediagenda-*` n'accepte `data-traitements` ; aucune liaison RBAC du groupe `data` dans un espace `mediagenda-*` ; aucun `ExternalSecret` de `data-traitements` ne vise un secret de MédiAgenda.
- [ ] Le groupe `data` obtient des identifiants dynamiques de sa base par OpenBao et aucun chemin sous `mediagenda`.
- [ ] ADR-0327 et RB-327 publiés sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check F2 07`

<details><summary>Indice 1</summary>

Commence par la question « qui a le droit de décider de ce qui sort ? ». Si c'est le responsable de la donnée, le traitement qui lit la table devrait-il appartenir à l'équipe qui la reçoit ? Que faudrait-il ouvrir (réseau, rôle, secret, cloison de locataire) dans chacun des deux sens ?
</details>

<details><summary>Indice 2</summary>

Un réplica physique a le même catalogue que la production : un rôle ou une vue créés sur le primaire de la prod (par une migration et par `managed.roles`) y arrivent par les WAL. Une vue PostgreSQL classique s'exécute avec les droits de son **propriétaire** : un lecteur de la vue n'a pas besoin de lire la table, ni ce que la vue utilise pour pseudonymiser. Pour un pseudonyme qu'on ne peut pas recalculer de l'extérieur : HMAC avec une clé générée **dans** la base (`pgcrypto`).
</details>

<details><summary>Indice 3</summary>

Les requêtes personnalisées de CloudNativePG (`spec.monitoring.customQueriesConfigMap`) nomment leurs métriques `cnpg_<requête>_<colonne>`. Le catalogue (`pg_attribute`) donne les noms des colonnes sans lire une ligne ; un petit journal des chargements donne nombre et date. Côté stockage objet, deux identités valent mieux qu'une : l'une ne sait qu'écrire, l'autre ne sait que lire.
</details>

**Pour aller plus loin** (facultatif) : généraliser « une base d'équipe jointe par OpenBao » dans l'équipe en code (moteur `db-<equipe>`, rôles, chemins ESO rendus) ; mesurer le risque de ré-identification de l'extraction (*k*-anonymat par praticien et par créneau) et décider d'une règle de diffusion.

---

### F2-S08 — Traitements par lots et refacturation interne  `LIBRE` `★★★`

> **Ticket PLAT-3208** — *De : Claire Morel*
> Deux sujets liés. D'abord Hugo veut ses calculs de nuit (agrégats quotidiens, export mensuel pour la direction) : fais en sorte qu'ils passent sans jamais déloger MédiVisio ni MédiAgenda, et qu'un lot qui s'emballe ne prenne pas tout le locataire. Ensuite, avec trois équipes de plus sur les mêmes trois travailleurs, je veux savoir **qui consomme quoi** : un tableau par équipe, et un petit rapport chaque mois que j'envoie aux responsables. Pas une facture : que chacun voie ce qu'il mobilise.

**Objectifs pédagogiques**
- Placer des traitements par lots dans une classe de priorité basse et un quota qui leur est propre.
- Donner à une équipe un compartiment objet dédié, créé et borné par le code.
- Mesurer la consommation par locataire (réservé, utilisé, stockage) avec des règles d'enregistrement, et en tirer un rapport de *showback* reproductible.

**Prérequis** : S07 ; M28-E14 (classes de priorité, budgets des locataires, tableau de capacité), M21 (règles d'enregistrement, tableaux provisionnés), M21-E24 (utilisateur et compartiment RGW).
**Durée indicative** : 5 à 7 h.

**Contexte technique**
- Classes de priorité : `medisphere-lot` (100, `preemptionPolicy: Never`), `medisphere-standard`, `medisphere-critique` (M28) ; le locataire `data` autorise `medisphere-standard` et `medisphere-lot`.
- kube-state-metrics expose l'étiquette `capsule.clastix.io/tenant` des espaces (`kube_namespace_labels`, `label_capsule_clastix_io_tenant`, M28-E14).
- Contrat de nommage (lu par le tableau, le rapport et le check) : règles d'enregistrement **`locataire:cpu_demande:somme`**, **`locataire:cpu_utilise:taux5m`**, **`locataire:memoire_demandee:somme`**, **`locataire:memoire_utilisee:somme`**, **`locataire:stockage_demande:somme`**, chacune avec l'étiquette `locataire` ; tableau Grafana d'UID **`plateforme-consommation-locataires`** ; rapport mensuel **`docs/accueil/mesures/refacturation-AAAA-MM.md`** ; procédure **RB-328**.
- Résultats de l'équipe Data : compartiment **`data-resultats`** sur le RGW de `ceph-par1` (`https://rgw.par1.medisphere.internal`), avec un utilisateur RGW à lui.

**Travail demandé**
1. **Les lots de l'équipe Data** (avec Hugo, dans son dépôt) : au moins un traitement nocturne (agrégats) et l'export mensuel des résultats vers `data-resultats`, en `medisphere-lot`, avec requests et limites ; aucune cellule publiée sous un seuil de petits effectifs (règle d'ADR-0327).
2. **Le cadre de la plateforme** : un quota qui ne compte que les pods de classe `medisphere-lot` de `data-traitements` ; l'utilisateur RGW, son quota et le compartiment créés par un outil versionné et rejouable, dont les clés vont dans OpenBao sans passer par un écran.
3. **La mesure** : règles d'enregistrement par locataire (contrat ci-dessus, et ce que tu juges utile en plus : facturé = max(réservé, utilisé), part du quota) et le tableau « Consommation par locataire ».
4. **Le rapport** : un outil de `plateforme/outils` qui produit le rapport d'un mois à partir de Prometheus et de tarifs versionnés ; le premier rapport publié ; RB-328 (ce qui est compté, ce qui ne l'est pas, comment lire et quoi proposer aux équipes).

**Critères de réussite**
- [ ] Dans `data-traitements`, au moins un CronJob en `medisphere-lot`, conteneurs avec requests (CPU, mémoire) et limite mémoire, un passage réussi depuis moins de 36 h ; un `ResourceQuota` à portée `PriorityClass` `medisphere-lot`.
- [ ] Au moins quatre règles `locataire:…` ; Prometheus sert `locataire:cpu_demande:somme` pour `medivisio` et `data`, `locataire:cpu_utilise:taux5m`, la mémoire réservée et utilisée, `locataire:stockage_demande:somme`.
- [ ] Le tableau `plateforme-consommation-locataires` existe et interroge au moins trois de ces règles.
- [ ] `docs/accueil/mesures/refacturation-AAAA-MM.md` cite chaque équipe accueillie (CPU, mémoire, stockage) ; RB-328 publié.

**Vérification** : `lab/bin/check F2 08`

<details><summary>Indice 1</summary>

Un `ResourceQuota` peut avoir une **portée** (`scopeSelector`, `scopeName: PriorityClass`) : il ne compte alors que les pods de cette classe. Pourquoi est-ce mieux ici qu'un simple abaissement du quota de l'espace ?
</details>

<details><summary>Indice 2</summary>

Les requests d'un pod terminé ne réservent plus rien : filtre sur la phase (`kube_pod_status_phase`). Le locataire d'un espace se joint par `* on (namespace) group_left (…) kube_namespace_labels{…}` ; renomme l'étiquette avec `label_replace` une fois pour toutes dans une règle intermédiaire.
</details>

<details><summary>Indice 3</summary>

Un rapport mensuel = une requête instantanée **à la fin du mois** (`time=`) sur `avg_over_time(<règle>[<jours du mois>d])`. Un mois commencé en cours de route donne une moyenne sur les seuls échantillons existants : dis-le dans le rapport.
</details>

**Pour aller plus loin** (facultatif) : ajouter le stockage objet par compartiment (métriques du RGW par l'exportateur du mgr de Ceph, ou `radosgw-admin bucket stats` collecté en *textfile*) ; comparer avec OpenCost (projet de la CNCF, https://opencost.io) : ce qu'il apporte (coût par charge, par étiquette) et ce qu'il suppose (un prix par nœud).

---

### F2-S09 — Réponse à la demande d'accès à la production  `RED` `★★`

> **Ticket DEV-3209** — *De : Hugo Bernard*
> Merci pour la base ! En attendant que tout soit en place, est-ce que je peux avoir juste un accès en lecture à la base de prod de MédiAgenda ? Ce serait le plus simple pour vérifier mes chiffres, et je ne toucherai à rien, promis.
>
> *Commentaire de Sophie Laurent* : on répond par écrit, ensemble. Je veux un refus que Hugo comprenne et une porte ouverte pour les vrais cas.

**Objectifs pédagogiques**
- Refuser une demande d'accès avec des motifs réglementaires et techniques compréhensibles par un non-spécialiste.
- Partir du besoin réel plutôt que de la solution demandée, et proposer l'alternative qui y répond.
- Écrire les conditions d'une exception (qui valide, combien de temps, quelle trace).

**Prérequis** : S07 (l'alternative existe ou est décidée) ; M24-E23 (arrivées et départs), M27-E02 (accès temporaire en lecture de Lucas).
**Durée indicative** : 1 h 30 à 2 h.

**Travail demandé**

Rédige la réponse à DEV-3209, publiée dans `docs/accueil/reponses/` (nom commençant par `DEV-3209`), signée avec Sophie :
1. le besoin réel reformulé ;
2. le refus motivé : HDS, RGPD (minimisation, finalité), sécurité et disponibilité de la production, principe de la plateforme ;
3. l'alternative fournie (S07) : ce qu'elle contient et ce qui en est exclu, comment y accéder, les règles d'usage ;
4. les conditions d'un accès **exceptionnel** : motif, validations, périmètre, durée et expiration automatique, authentification, traces, clôture ;
5. les prochaines étapes.

**Critères de réussite**
- [ ] La réponse est publiée sur `main` et cite DEV-3209.
- [ ] Le refus s'appuie sur HDS, le RGPD et la minimisation ; l'alternative (extraction pseudonymisée, base Data) est décrite.
- [ ] Les conditions d'un accès exceptionnel fixent une durée ou une expiration, une validation par la RSSI et une traçabilité.

**Vérification** : `lab/bin/check F2 09` (présence et contenu minimal ; la qualité se juge avec le corrigé).

<details><summary>Indice 1</summary>

Hugo n'est pas un attaquant : il a un délai et une direction qui attend. Une réponse qui ne dit que « non » produira un contournement (une copie, un compte partagé). Que doit-il pouvoir faire **demain matin** ?
</details>

<details><summary>Indice 2</summary>

Le RGPD autorise la réutilisation statistique (article 89) **avec** des garanties ; HDS et ISO 27001 exigent des accès nominatifs, justifiés, tracés. L'accès temporaire de Lucas au M27 (rôle géré à expiration automatique, `VALID UNTIL`) est un bon modèle d'exception.
</details>

**Pour aller plus loin** (facultatif) : un modèle de réponse réutilisable (`docs/accueil/reponses/modele-refus-acces.md`) et l'entrée correspondante dans l'offre de service (S01).
