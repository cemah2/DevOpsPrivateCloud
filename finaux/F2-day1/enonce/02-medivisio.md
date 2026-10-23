# Phase 2 — MédiVisio, du modèle à la production

MédiVisio existe (S02) : un groupe, un locataire, trois environnements, un projet Argo CD, un coffre, une adresse d'alertes. Il lui manque un service. Inès veut le premier en ligne cette semaine, et Claire veut savoir **combien de temps** cela a vraiment pris et **qui** a dû intervenir.

---

### F2-S04 — MédiVisio : du modèle au premier déploiement  `LIBRE` `★★★`

> **Ticket DEV-3204** — *De : Inès Garnier*
> Bonjour la Plateforme ! On a notre groupe et nos espaces, merci. On voudrait créer notre premier service, la **consultation** (créneaux et salles de téléconsultation ; données factices pour l'instant), en Python, par le portail comme le dit votre guide. On aimerait le voir tourner en dev aujourd'hui. Léo et moi faisons tout nous-mêmes ; dites-nous juste si on doit vous attendre quelque part.

**Objectifs pédagogiques**
- Mener un service du modèle Backstage à son premier déploiement par le chemin balisé (CI par composants, image signée, Argo CD).
- Adapter un chemin balisé à une nouvelle organisation des environnements (équipe en code) sans casser les équipes existantes.
- Mesurer le délai jusqu'au premier déploiement et chaque intervention de la plateforme.

**Prérequis** : S02 ; M28-E08 et E10 (modèle « nouveau service », TechDocs) ; M19 (composants CI, promotion) ; M25-E20 (signature par `transit/cosign-medisphere`, rôle `ci-signature`).
**Durée indicative** : 4 à 6 h.

**Contexte technique**
- Noms de référence : projets **`medivisio/consultation`** (code) et **`medivisio/consultation-deploiement`** (Kustomize) ; entité **`Component` `medivisio-consultation`** au catalogue ; image **`registry.par1.medisphere.internal/medisphere/medivisio-consultation`** ; déploiement dans **`medivisio-dev`** (puis `-recette`, `-prod` en S05) ; adresse **`https://consultation-dev.apps.par1.medisphere.internal`** ; le service répond `GET /sante` (200).
- Le modèle `nouveau-service` du M28 (`plateforme/portail-modeles`) impose un nom préfixé par le locataire et crée un espace **par service** (`<nom>-dev`), proposé par MR à la Plateforme avec son Application. MédiVisio, elle, a déjà ses environnements partagés par tous ses services.
- Les rôles JWT d'OpenBao des pipelines sont nommés `ci-<groupe>-<projet>` (et `-promotion`) ; le rôle `ci-signature` n'accepte que certains groupes (M25-E20). Le composant `promotion` lit son jeton dans `kv/<groupe>/ci/promotion` (M25-E10).
- La politique de signature de Kyverno s'applique en recette et en production de MédiVisio (S02), pas en dev.

**Travail demandé** (objectifs, contraintes, livrables)
1. Faire évoluer le modèle `nouveau-service` pour les équipes en code : ce que le modèle crée, ce qu'il propose (et à qui), comment les Applications naissent, sans MR à la Plateforme pour chaque service si c'est possible. Les équipes historiques gardent le comportement actuel. Décision : `docs/accueil/adr/ADR-0321-…`.
2. Jouer Inès : créer le service par le portail, faire passer la CI (construction, analyse, signature), promouvoir en `dev`, voir le service répondre ; sa documentation (TechDocs) visible dans le portail.
3. Tout ce qui ne marche pas du premier coup se corrige **par le code** (modèle, fichier d'équipe, composants), jamais par un geste manuel non tracé.
4. **Mesurer** : de « Inès clique sur Créer » à « l'URL de dev répond ». Noter chaque étape horodatée, chaque attente, chaque intervention de la Plateforme (quoi, pourquoi, combien de temps) dans `docs/accueil/mesures/medivisio-premier-deploiement.md`.

Contraintes : la clé de signature ne quitte jamais le coffre ; aucune image désignée par une étiquette dans un overlay ; aucune donnée de santé, même factice d'apparence réelle.

**Critères de réussite**
- [ ] `Component` `medivisio-consultation` au catalogue, propriétaire `group:default/medivisio`, avec sa documentation (annotation TechDocs).
- [ ] Projet `medivisio/consultation` créé par le modèle ; image `medisphere/medivisio-consultation` dans Harbor, **signée**.
- [ ] Un Deployment de `medivisio-dev` exécute cette image, désignée par son empreinte, tous ses réplicas prêts ; l'Application Argo CD correspondante est `Synced` et `Healthy`.
- [ ] `https://consultation-dev.apps.par1.medisphere.internal/sante` répond 200 depuis `adm01`.
- [ ] Mesure publiée : délai total, temps d'attente de la Plateforme, liste des interventions ; ADR-0321 publié.

**Vérification** : `lab/bin/check F2 04`

<details><summary>Indice 1</summary>

Avec des environnements par équipe, ce qui manque pour déployer un service n'est plus un espace, c'est une **Application**. Qui doit pouvoir la créer ? Un générateur d'Argo CD peut fabriquer des Applications à partir de fichiers d'un dépôt… que l'équipe tient elle-même. Ce qui doit rester hors de sa portée : le projet Argo CD et les destinations.
</details>

<details><summary>Indice 2</summary>

Lis le premier pipeline en échec avant de chercher plus loin : quel rôle du coffre le job demande-t-il, existe-t-il, quels groupes accepte `ci-signature` ? La réponse « durable » passe par le fichier d'équipe de S02.
</details>

**Pour aller plus loin** (facultatif) : faire ouvrir par le modèle la MR du fichier d'équipe (déclaration du service) pour supprimer la dernière attente.

---

### F2-S05 — MédiVisio en production, avec ses alertes et son SLO  `LIBRE` `★★★`

> **Ticket DEV-3205** — *De : Inès Garnier*
> La consultation tourne en dev, la recette est validée par notre PO. On aimerait passer en production avant la démonstration de jeudi. Karim nous a dit : « pas de production sans SLO, sans alertes qui vous arrivent, sans tableau de bord et sans runbook ». On s'en occupe, mais dites-nous ce qu'on fait nous-mêmes et ce qui passe par vous. Et la clé qui signe les liens des salles, on la met où ?

**Objectifs pédagogiques**
- Promouvoir un service en recette puis en production par MR, à empreinte identique, dans une fenêtre autorisée.
- Rendre une équipe autonome sur ses secrets, son SLO et ses alertes, dans le cadre posé par la plateforme.
- Vérifier le routage d'une alerte de bout en bout.

**Prérequis** : S04 ; M21 (Pyrra, Alertmanager, tableaux provisionnés), M25 (ESO), M20-E29 (fenêtres de synchronisation).
**Durée indicative** : 4 à 6 h.

**Contexte technique**
- Secret du service : `kv/medivisio/<env>/consultation`, champ `cle_salles` (clé HMAC des liens de salle) ; le service n'est **prêt** (`/pret`) que s'il la reçoit (variable `CONSULTATION_CLE_SALLES`).
- Métriques : le service expose `/metrics` (`consultation_http_requests_total{methode, route, code}`, histogramme `consultation_http_request_duration_seconds`) — à ajouter au squelette si ton S04 ne l'a pas fait.
- Production : synchronisation **manuelle**, jamais du vendredi 16 h au lundi 8 h (règle CHG-2129 du M20) ; adresse `https://consultation.apps.par1.medisphere.internal`.
- Alertes : Mailpit reçoit `medivisio@medisphere.internal` ; les critiques vont aussi à `astreinte@` (M21).
- Tableaux de bord : provisionnés depuis `plateforme/observabilite` (M21-E19), dossier de l'équipe créé en S02.

**Travail demandé** (objectifs, contraintes, livrables)
1. Secrets en libre-service : l'équipe écrit elle-même ses secrets de recette et de production dans le coffre (connexion OIDC) ; ils arrivent dans les espaces par External Secrets. Montrer qu'Inès ne peut lire **aucun** autre chemin.
2. Promotion : recette puis production par MR dans `medivisio/consultation-deploiement`, avec l'empreinte validée à l'étape précédente ; production synchronisée à la main, dans la fenêtre.
3. SLO de disponibilité de la consultation en production (Pyrra), alertes de budget d'erreurs routées vers l'équipe ; preuve que le routage fonctionne (test de routage et alerte reçue dans Mailpit).
4. Tableau de bord dans le dossier Grafana de MédiVisio.
5. Runbook de service minimal, publié avec la documentation du service (TechDocs) : que faire quand l'alerte sonne, retour arrière, contacts.
6. Noter dans `docs/accueil/mesures/` ce qui a demandé la Plateforme pour cette mise en production.

Contraintes : pas de `kubectl` en écriture dans `medivisio-*` ; pas de secret dans Git ni dans une variable de CI ; production à deux réplicas au moins, en classe `medisphere-critique`, avec un budget de perturbation.

**Critères de réussite**
- [ ] L'Application de production de la consultation est `Synced` et `Healthy`, sans synchronisation automatique ; `https://consultation.apps.par1.medisphere.internal/sante` répond 200.
- [ ] Production : au moins deux réplicas prêts, classe `medisphere-critique`, `PodDisruptionBudget`, image désignée par la même empreinte qu'en recette.
- [ ] `ExternalSecret` de production synchronisé, qui ne lit que `kv/medivisio/prod/…`.
- [ ] Un `ServiceLevelObjective` dans `medivisio-prod` et ses règles générées ; la configuration d'Alertmanager route `equipe="medivisio"` vers `medivisio@medisphere.internal` ; une alerte de test reçue dans Mailpit.
- [ ] Un tableau de bord dans le dossier Grafana de MédiVisio ; un runbook dans la documentation du service.

**Vérification** : `lab/bin/check F2 05`

<details><summary>Indice 1</summary>

Pour que le SLO déclenche des alertes que l'équipe reçoit, trois choses doivent s'aligner : Prometheus lit les règles de l'espace, les alertes portent l'étiquette qui désigne l'équipe, et Alertmanager a une route pour cette étiquette **dans cet espace**. Relis comment Pyrra transmet ses étiquettes (M21-E27).
</details>

<details><summary>Indice 2</summary>

Tester le routage sans attendre une vraie panne : `amtool config routes test` sur la configuration **générée** (récupérée par l'API d'Alertmanager), puis une alerte injectée (`amtool alert add …`) avec les bonnes étiquettes.
</details>

**Pour aller plus loin** (facultatif) : un SLO de latence ; un canary Argo Rollouts en production comme MédiAgenda (M20) ; un *game day* sur la recette de MédiVisio (M29).

---

### F2-S06 — Panne : les premiers pas qui coincent  `BF` `★★★`

> **Ticket DEV-3206** — *De : Inès Garnier*
> Bonjour, notre déploiement en **recette** ne démarre pas, alors que ça marchait en dev ce matin. Léo a poussé une petite modification de configuration hier soir (« rien de méchant », dit-il), et Lucas nous a aidés à « simplifier » un fichier. Argo CD a bien vu le commit, mais la nouvelle version n'arrive jamais. On a la démonstration jeudi. Vous pouvez regarder ?

**Injection** : `lab/bin/break F2 06` (depuis `adm01` ; tire une cause au hasard parmi plusieurs).
**Temps cible** : 45 min.

**Objectifs pédagogiques**
- Diagnostiquer un déploiement qui ne progresse pas dans un environnement multi-locataire (quota, admission, secrets).
- Lire les bons objets dans le bon ordre : Application, Deployment, ReplicaSet, événements, ExternalSecret, rapports de politique.
- Corriger par Git, et expliquer la cause à l'équipe sans la mettre en faute.

**Prérequis** : S05 (recette et production de MédiVisio en marche, `lab/bin/check F2 05` vert).

**Contexte technique** : l'équipe n'a que la lecture dans ses environnements ; toi aussi, tu répares par une MR dans `medivisio/consultation-deploiement` (ou dans le fichier d'équipe si la cause s'y trouve), jamais par `kubectl` en écriture dans `medivisio-recette`.

**Travail demandé**
1. Diagnostiquer, en notant chaque commande et ce qu'elle t'apprend, dans `docs/accueil/journal/AAAA-MM-JJ-F2-S06-<sujet>.md`.
2. Corriger par le code ; vérifier que la recette est revenue.
3. Répondre à Inès (dans le journal) : la cause, la correction, et ce qui empêchera que cela se reproduise (contrôle en CI, garde-fou dans le modèle, documentation).
4. Si la cause révèle un manque de la plateforme, l'ajouter au runbook RB-321 (`docs/accueil/runbooks/RB-321-premier-deploiement-bloque.md`) : symptômes, vérifications dans l'ordre, corrections.

**Critères de réussite**
- [ ] L'Application de recette est `Synced` et `Healthy` ; tous les réplicas du Deployment sont prêts, sur la dernière version.
- [ ] Aucun ReplicaSet de la recette en échec de création ; tous les `ExternalSecret` de l'espace synchronisés.
- [ ] La correction est un commit dans Git (pas une modification à la main).
- [ ] Journal de diagnostic publié ; RB-321 publié ou complété.

**Vérification** : `lab/bin/check F2 06` · Abandon : `lab/bin/break F2 06 --annuler`.

<details><summary>Indice 1</summary>

Commence par le résultat de la **dernière opération** d'Argo CD : a-t-il pu écrire ce que dit Git ? S'il l'a écrit (« Synchronisé »), cela ne dit pas encore que les pods ont pu être créés : descends d'un niveau — qui crée les pods, et où écrit-il quand il n'y arrive pas ?
</details>

<details><summary>Indice 2</summary>

Trois contrôles peuvent refuser un pod ou l'empêcher de démarrer dans un environnement d'équipe : l'enveloppe de ressources de l'espace et du locataire, l'admission (Pod Security, Kyverno), et ce que le pod attend pour démarrer (Secrets, ConfigMaps). Chacun laisse une trace différente.
</details>

<details><summary>Indice 3</summary>

Compare le dernier commit de `medivisio/consultation-deploiement` avec l'état qui marchait : `git log -p` sur l'overlay de recette.
</details>

**Pour aller plus loin** (facultatif) : un contrôle en CI du dépôt de déploiement qui rend chaque overlay et vérifie quotas, empreintes et chemins de secrets avant la fusion (composant `validation` du M29, politiques Rego).
