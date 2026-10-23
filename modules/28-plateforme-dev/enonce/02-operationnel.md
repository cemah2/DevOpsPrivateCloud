# Module 28 — Palier 2 : Opérationnel

Le cluster suit la charge et chaque équipe a son locataire. Reste ce que Claire appelle « le guichet » : savoir qui possède quoi, où ça tourne, où est la doc, et créer un service sans ouvrir six tickets. Ce palier construit le portail **Backstage** de MédiSphère comme n'importe quelle application de l'entreprise (projet GitLab, CI, image signée, Argo CD), le remplit (catalogue, organisation), lui apprend à créer un service par MR, le compare à un cluster virtuel, puis te fait relire le travail du stagiaire et écrire le guide qu'une nouvelle équipe lira en arrivant.

Prérequis : palier 1 terminé (`lab/bin/check 28 02` à `05` verts) ; M19 (composants CI/CD, BuildKit, signature) ; M24 (Keycloak, FreeIPA, `plateforme/identite`) ; M25 (OpenBao, ESO) ; M16 (CloudNativePG). Refais le bilan de capacité de l'introduction avant E06.

---

### M28-E06 — Backstage : construire et installer le portail  `LAB` `★★★`

> **Ticket PLAT-2906** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent*
> Le portail est une application comme une autre : un projet GitLab `plateforme/portail`, une CI qui construit et signe l'image, une base CloudNativePG, Argo CD, une adresse en `apps.par1`. Connexion par Keycloak uniquement — pas de compte invité en production. Et un jeton en lecture seule, limité au catalogue, pour les vérifications. Tout ce que tu écris doit correspondre à la documentation de la 1.56 : le nouveau backend, le nouveau système de frontend.

**Objectifs pédagogiques**
- Créer une application Backstage 1.56 et comprendre sa structure (monodépôt Yarn, `packages/app`, `packages/backend`, configuration en couches).
- Configurer Backstage pour la production : base PostgreSQL, OIDC Keycloak et résolution des utilisateurs, accès externe statique restreint.
- Construire l'image par la CI (Dockerfile multi-étapes de la documentation), la signer, et la déployer avec le chart officiel par Argo CD.

**Prérequis** : M28-E05 ; M19-E10 et suivants (composants `construction-image`, `securite`, `release`) ; M24-E12 (clients OIDC par OpenTofu) ; M25-E12 (ClusterSecretStore `openbao`) ; M16 (CNPG, plugin Barman Cloud).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Création | `npx @backstage/create-app@0.9.3` (Node.js 24 et Yarn 4 de l'application) sur `adm01`, nom `portail`, poussé dans le projet GitLab **`plateforme/portail`** (clone `~/src/portail`) |
| Image | `registry.par1.medisphere.internal/plateforme/portail:vX.Y.Z`, construite par BuildKit (composant `construction-image`), signée (composant `securite`) ; base `node:24-trixie-slim` par le cache Harbor `dockerhub`, par empreinte |
| Chart | `backstage` **2.10.2**, OCI `oci://ghcr.io/backstage/charts/backstage`, recopié par `charts-miroir` |
| Application | **`portail`** (projet `plateforme`, chart + valeurs `plateforme/gitops/valeurs/portail/values.yaml`) ; espace **`portail`** (PSA `restricted`) et ses objets de plateforme dans `plateforme/k8s/espaces/portail/` (base, ExternalSecret, racine, politiques réseau ; `task espaces`) |
| Adresse | `https://portail.apps.par1.medisphere.internal` (HTTPRoute sur `gw-par1`) |
| Base | `Cluster` CNPG **`portail-db`** (une instance, PostgreSQL 18, `ceph-rbd`), base et propriétaire `portail`, dans `plateforme/k8s/espaces/portail/50-portail-db.yaml` (sauvegarde et archivage au palier 3, M28-E16) |
| OIDC | client Keycloak **`backstage`** (confidentiel) dans `plateforme/identite/tofu` ; redirection `https://portail.apps.par1.medisphere.internal/api/auth/oidc/handler/frame` ; utilisateurs résolus par leur `preferred_username` (= nom de l'entité `User` du catalogue, E07) |
| Secrets | `kv/plateforme/portail` : secret du client OIDC, secret de session, jeton des checks (puis jeton GitLab et mot de passe LDAP en E07, clés S3 en E10) ; ExternalSecret `portail` (ClusterSecretStore `openbao`) |
| Jeton des checks | accès externe statique, sujet `wb-checks`, limité au plugin `catalog` en lecture ; copie sur `adm01` : `~/.config/workbook/backstage-checks.token` (600) |
| Flux | sortie du pod vers `sso.par1.medisphere.internal` (VIP 10.10.70.200:443), la base, DNS ; déjà ouverts à la bordure pour les travailleurs (bloc F) |

**Travail demandé**

1. **L'application.** Crée l'application, lis sa structure : `app-config.yaml`, `app-config.production.yaml`, `packages/backend/src/index.ts` (quels plugins le backend charge-t-il ?), `packages/app/src/App.tsx`, `package.json` (quelles versions de Node.js acceptées ?). Lance-la en local (`yarn start`) pour voir le catalogue d'exemple. Retire du backend ce que MédiSphère n'utilise pas (module GitHub du *scaffolder*, fournisseur invité), et dis pourquoi.
2. **OIDC.** Déclare le client `backstage` dans `plateforme/identite/tofu` (même modèle que les autres clients confidentiels, secret imposé depuis le coffre). Côté Backstage, suis la page *OIDC provider from scratch* de la 1.56 : module du backend, configuration (`metadataUrl`, secret de session), page de connexion du frontend (API d'authentification, `SignInPage`). Les résolveurs intégrés du module OIDC conviennent-ils pour `preferred_username` ? Vérifie-le dans le code du module de la 1.56 avant de choisir, et écris le résolveur si besoin.
3. **La production.** Dans `app-config.production.yaml` : adresses publiques, base PostgreSQL (une seule base pour tous les plugins : cherche `pluginDivisionMode`), `auth.environment`, accès externe statique pour les checks (sujet, restriction au plugin `catalog`, lecture seulement), catalogue sans exemples. Racine MédiSphère reconnue par Node.js. Aucun secret dans un fichier : variables d'environnement.
4. **L'image.** Dockerfile multi-étapes de la documentation *Deploying with Docker* (adapté : base par Harbor et par empreinte, pas de dossier `plugins/` si tu n'en as pas), `.dockerignore` correspondant, `catalog-info.yaml` du projet, pipeline (composants de `plateforme/ci-templates` aux versions en vigueur). Le pod tournera en `restricted` : quel utilisateur numérique l'image utilise-t-elle ?
5. **La base et les secrets.** Le `Cluster` `portail-db` ; les secrets dans OpenBao ; l'ExternalSecret ; la politique OpenBao qui permet à ESO de les lire.
6. **Le déploiement.** Recopie le chart par `charts-miroir` et lis ses valeurs : que fait la `command` par défaut du conteneur aux arguments `--config` de ton image ? Que contient le dossier `charts/` de l'archive (et en quoi cela touche-t-il la règle « jamais de chart Bitnami ») ? Écris les valeurs (image par empreinte, arguments, variables depuis les Secrets, racine et autorité de la base montées, contexte de sécurité, ressources, sondes, HTTPRoute), les objets de `plateforme/k8s/espaces/portail/` (espace, politiques réseau), l'Application `portail`. Synchronise.
7. **Contrôle.** Connexion par Keycloak avec ton compte (tu n'existes pas encore dans le catalogue : que se passe-t-il, et pourquoi c'est le comportement voulu jusqu'à E07 ?). Le jeton des checks : `curl` sur `/api/catalog/entities` réussit ; sur `/api/scaffolder/v2/tasks`, refusé. Rédige `docs/plateforme-dev/portail.md` (architecture, configuration en couches, secrets, mise à jour, retour arrière).

**Critères de réussite**
- [ ] Projet `plateforme/portail` sur `main` : Dockerfile, `app-config.production.yaml` sans secret en clair, `catalog-info.yaml` ; pipeline de `main` vert ; image `plateforme/portail` signée dans Harbor.
- [ ] Application `portail` `Synced` et `Healthy` ; pod prêt, image de Harbor par empreinte ; `Cluster` `portail-db` sain.
- [ ] `https://portail.apps.par1.medisphere.internal` répond en HTTPS (certificat valide) et propose la connexion Keycloak ; aucun fournisseur invité.
- [ ] Le jeton des checks lit le catalogue et rien d'autre.
- [ ] Client `backstage` présent et confidentiel dans le royaume `medisphere`, une seule URI de redirection.
- [ ] `portail.md` est sur `main`.

**Vérification** : `lab/bin/check 28 06`

<details><summary>Indice 1</summary>

Le module OIDC de la 1.56 déclare dans son schéma de configuration plus de résolveurs qu'il n'en enregistre dans son code (`src/resolvers.ts`, `src/module.ts`) : un résolveur annoncé mais absent fait échouer la connexion. La page *Identity Resolver* montre comment écrire un module d'authentification qui résout à partir de `info.result.fullProfile.userinfo`.
</details>

<details><summary>Indice 2</summary>

Backstage crée par défaut une base par plugin : le compte propriétaire d'une seule base CNPG n'a pas le droit `CREATEDB`. Lis la page *Switching Backstage from SQLite to PostgreSQL*, section *Using a single database* (`backend.database.pluginDivisionMode`). Pour la racine de confiance, Node.js lit `NODE_EXTRA_CA_CERTS`.
</details>

<details><summary>Indice 3</summary>

Le chart remplace la commande de l'image par `node packages/backend` : sans `backstage.args`, le pod démarre avec la seule configuration de base (SQLite en mémoire, connexion invitée). Une image construite avec `USER node` (un nom) ne satisfait pas `runAsNonRoot` : il faut un UID numérique dans le contexte de sécurité.
</details>

**Pour aller plus loin** (facultatif) : lis *Configuring App with plugins* du nouveau frontend : comment désactiver une extension par la seule configuration (`app.extensions`) ?

---

### M28-E07 — Le catalogue : services, équipes et propriétaires  `LAB` `★★★`

> **Ticket PLAT-2907** — *De : Claire Morel* — *Copie : Julien Petit, Karim Benali*
> Un portail vide ne sert à rien. Je veux y voir les personnes et les équipes de l'annuaire (pas une liste tapée à la main), et chaque service avec son équipe propriétaire : MédiAgenda, MédiDoc, MédiNotif, et nos briques de plateforme. Les équipes décrivent leurs services dans **leurs** dépôts, le portail les découvre seul. Et personne ne doit pouvoir s'inventer une équipe en écrivant un fichier.

**Objectifs pédagogiques**
- Alimenter le catalogue par des fournisseurs d'entités : découverte GitLab et organisation LDAP (FreeIPA).
- Modéliser MédiSphère en entités Backstage (Systems, Components, Resources, APIs) avec des propriétaires valides.
- Restreindre ce que le catalogue accepte (règles) et donner au portail des comptes de service minimaux.

**Prérequis** : M28-E06 ; M24-E03 (comptes système FreeIPA, `plateforme/identite/annuaire`) ; M19 (comptes de service GitLab, Free depuis 18.11).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Modules du backend | `@backstage/plugin-catalog-backend-module-gitlab`, `@backstage/plugin-catalog-backend-module-ldap` (versions de la 1.56) |
| GitLab | intégration `git01.par1.medisphere.internal` (`apiBaseUrl` `https://git01.par1.medisphere.internal/api/v4`) ; compte de service d'instance **`svc-portail`** ; jeton dans `kv/plateforme/portail` |
| Annuaire | `ldaps://ipa01.par1.medisphere.internal` ; compte système **`uid=svc-portail,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal`** (déclaré dans `plateforme/identite/annuaire/comptes-systeme.yml`) ; personnes sous `cn=users,cn=accounts,…`, groupes sous `cn=groups,cn=accounts,…` |
| Entités à décrire | `catalog-info.yaml` à la racine de `mediagenda/api`, `medidoc/medidoc`, `medinotif/worker`, `plateforme/portail` ; les Systems **`mediagenda`**, **`medidoc`**, **`medinotif`**, **`plateforme`**, les Resources partagées et un Domain dans `plateforme/medisphere` (`catalog-info.yaml`) |
| Propriétaires | groupes de l'annuaire : `mediagenda` (MédiAgenda **et** MédiNotif), `medidoc`, `plateforme` |

**Travail demandé**

1. **Les comptes.** Compte système FreeIPA `svc-portail` (par `plateforme/identite/annuaire`). Compte de service GitLab d'instance `svc-portail` (API `service_accounts` ; que vaut `external` par défaut en 19.5, et quelle conséquence ?), jeton à expiration, portée minimale pour lire les dépôts **et** (en E08) créer un projet et ouvrir des MR ; appartenances minimales (quels groupes, quel rôle). Secrets dans `kv/plateforme/portail`. Écris les droits retenus et leur justification dans `docs/plateforme-dev/catalogue.md`.
2. **L'organisation.** Module LDAP : personnes (filtre qui exclut les comptes désactivés), groupes (seulement ceux des équipes et des fonctions), correspondances d'attributs ; quel champ obligatoire d'une entité `Group` FreeIPA ne fournit-il pas, et comment le poser ? TLS vérifié. Fréquence.
3. **La découverte.** Module GitLab : fournisseur pour les groupes `mediagenda`, `medidoc`, `medinotif`, `plateforme` (nom du fichier, branche, projets exclus), fréquence ; règles du catalogue (types acceptés depuis les dépôts : ni `User`, ni `Group`, ni `Template`).
4. **Les entités.** Écris les `catalog-info.yaml` : Components (type, cycle de vie, propriétaire, système, annotations GitLab), Resources (`mediagenda-db`, `rabbitmq`, `portail-db`…), un `API` OpenAPI pour MédiAgenda (lu depuis `/openapi.json`… ou depuis un fichier du dépôt ? choisis), relations `dependsOn`, `providesApis`. MR dans chaque projet (au nom des équipes : tu proposes, elles fusionnent).
5. **Contrôle.** Le catalogue montre-t-il `julien.petit` membre de `mediagenda`, et `mediagenda-api` possédé par `mediagenda` ? Connecte-toi : ton entité `User` existe désormais. Essaie de faire découvrir un `Group` déclaré dans un `catalog-info.yaml` d'essai (dans un projet de `formation/`) : que dit le catalogue ? Relève les erreurs de traitement (`/api/catalog/entities` et journaux du plugin) et corrige-les.

**Critères de réussite**
- [ ] Les groupes `mediagenda`, `medidoc`, `plateforme` et l'utilisateur `julien.petit` existent dans le catalogue (origine LDAP) ; `julien.petit` est membre de `mediagenda`.
- [ ] Components `mediagenda-api`, `medidoc`, `medinotif-worker`, `portail` découverts depuis GitLab, chacun dans son System et possédé par un **groupe** existant.
- [ ] Systems `mediagenda`, `medidoc`, `medinotif`, `plateforme` présents ; MédiNotif possédé par `mediagenda`.
- [ ] Aucune entité `Group` ou `User` du catalogue ne vient d'un dépôt GitLab.
- [ ] `catalogue.md` (comptes, droits, sources, règles) est sur `main`.

**Vérification** : `lab/bin/check 28 07`

<details><summary>Indice 1</summary>

Les comptes système FreeIPA lisent par défaut les personnes et les groupes (ACI de lecture des comptes authentifiés), comme `svc-keycloak` au M24. Pour les filtres, `objectClass` d'une personne FreeIPA : `inetOrgPerson` ; d'un groupe d'utilisateurs : `ipausergroup` ; compte désactivé : `nsAccountLock`.
</details>

<details><summary>Indice 2</summary>

Les règles du catalogue (`catalog.rules`) s'appliquent aux entités lues depuis des emplacements, ce que produit la découverte GitLab ; un `Template` n'est accepté que par une règle propre à l'emplacement qui le déclare (E08).
</details>

**Pour aller plus loin** (facultatif) : branche l'évènement `push` de GitLab sur le portail (*events* GitLab) pour ne plus attendre la prochaine découverte.

---

### M28-E08 — Un modèle « nouveau service »  `LIBRE` `★★★`

> **Ticket DEV-2908** — *De : Julien Petit* — *Copie : Claire Morel*
> Le test grandeur nature : l'équipe MédiDoc veut un petit service de vignettes d'images, `medidoc-vignettes`. Au lieu des six tickets, je voudrais un formulaire dans le portail qui crée le projet GitLab avec un squelette qui se construit, la base de déploiement, et qui **propose** à la Plateforme ce qui lui revient (l'Application Argo CD, les espaces dans le locataire) par des MR que Karim relira. Le jour où ça marche, on ne revient pas en arrière.

**Objectifs pédagogiques**
- Concevoir un chemin balisé de bout en bout : du formulaire au service livré par GitOps.
- Écrire un `Template` du *scaffolder* et ses squelettes, avec les actions GitLab.
- Donner au portail exactement les droits nécessaires, et garder la Plateforme maîtresse de ce qui touche au cluster.

**Prérequis** : M28-E05 (locataires), M28-E07 (catalogue, `svc-portail`) ; M20 (ApplicationSet, AppProjects) ; M19 (composants CI/CD).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet des modèles | **`plateforme/portail-modeles`** : modèle **`nouveau-service`** et ses squelettes ; déclaré au catalogue par un emplacement dédié |
| Module du backend | `@backstage/plugin-scaffolder-backend-module-gitlab` (version de la 1.56) |
| Essai | service **`medidoc-vignettes`** de l'équipe `medidoc` (locataire `medidoc`) |
| Ce qui revient à la Plateforme | `plateforme/gitops` (Application ou élément d'ApplicationSet) et `plateforme/k8s` (espaces du service dans le locataire, quotas, Pod Security, SecretStore) : **par MR seulement** |

**Travail demandé**

Conçois et livre le modèle `nouveau-service`, puis utilise-le pour créer `medidoc-vignettes`. Contraintes :

- le formulaire demande au plus : nom du service, équipe (choisie dans le catalogue), langage parmi ceux de MédiSphère, description ; il refuse un nom qui ne respecte pas le préfixe du locataire de l'équipe ;
- le projet GitLab créé contient un squelette qui passe sa CI (composants de `plateforme/ci-templates`), un `catalog-info.yaml` qui rattache le service à son équipe et à son système, un dépôt ou un dossier de déploiement Kustomize (base et overlay `dev`) conforme aux règles du cluster (Pod Security `restricted`, `requests`, sondes, politiques réseau) ;
- le portail ne pousse **jamais** directement sur la branche par défaut de `plateforme/gitops` ni de `plateforme/k8s` : il y ouvre des MR, attribuées à la Plateforme ;
- les droits de `svc-portail` sont les plus petits qui permettent tout cela, et écrits ;
- le service créé apparaît dans le catalogue sans intervention ;
- une fois les MR fusionnées par toi (dans le rôle de Karim), `medidoc-vignettes` tourne en `dev` dans un espace du locataire `medidoc`, livré par Argo CD ;
- le modèle et ses choix sont documentés dans `docs/plateforme-dev/modeles.md`, y compris ce que le modèle **ne** fait pas encore.

**Critères de réussite**
- [ ] L'entité `Template` `nouveau-service` est dans le catalogue, chargée depuis `plateforme/portail-modeles`.
- [ ] Le projet `medidoc/medidoc-vignettes` existe, avec un `catalog-info.yaml` ; son pipeline de `main` est vert ; le Component `medidoc-vignettes` est dans le catalogue, possédé par `medidoc`.
- [ ] Une MR « medidoc-vignettes » existe dans `plateforme/gitops` et une dans `plateforme/k8s`, ouvertes par `svc-portail` ; fusionnées, elles font tourner le service en `dev`.
- [ ] `svc-portail` n'est ni administrateur de l'instance, ni propriétaire d'un groupe, ni membre de `plateforme/gitops` ou `plateforme/k8s` au-dessus du rôle qui permet d'ouvrir une MR.
- [ ] `modeles.md` est sur `main`.

**Vérification** : `lab/bin/check 28 08`

<details><summary>Indice 1</summary>

Pars des exemples du dépôt d'actions GitLab de la 1.56 (`examples` de chaque action) et de la liste des actions installées, visible dans le portail (`/create/actions`). Distingue ce qui est rendu par le modèle (squelette), ce qui est publié (nouveau projet) et ce qui est proposé (MR dans un dépôt existant, avec un chemin cible).
</details>

<details><summary>Indice 2</summary>

Une MR proposée par un modèle peut ajouter un fichier dans un dossier existant (un fichier par service), ce qui évite les conflits sur un fichier partagé. Le jeton utilisé par une action est celui de l'intégration, sauf si l'action en reçoit un autre.
</details>

**Pour aller plus loin** (facultatif) : ajoute au modèle une étape qui crée l'entrée `kv/<équipe>/dev/<service>` dans OpenBao… et explique pourquoi tu y renonces (ou pas) : qui aurait alors le droit d'écrire dans le coffre ?

---

### M28-E09 — vCluster : un cluster virtuel pour une équipe, puis retrait  `LAB` `★★★`

> **Ticket PLAT-2909** — *De : Karim Benali*
> Avant qu'on me dise encore que « les locataires Capsule, c'est trop limité, il nous faut des vClusters » : on en monte un, dans le locataire `medidoc`, on regarde ce qu'il apporte et ce qu'il coûte, on écrit la comparaison, et on le **retire**. Version OSS uniquement, stockage par défaut. Et on n'installe pas Capsule dedans.

**Objectifs pédagogiques**
- Installer un vCluster OSS dans un espace de libre-service et s'y connecter.
- Comprendre ce que le *syncer* recopie vers l'hôte, ce qui reste virtuel, et ce que l'hôte continue d'imposer (quotas, Pod Security, politiques, Capsule).
- Comparer Capsule et vCluster sur des critères écrits, puis retirer proprement l'essai.

**Prérequis** : M28-E05 (locataire `medidoc`, libre-service).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Chart | `loft/vcluster` **0.37.4**, dépôt `https://charts.loft.sh` ; image du plan de contrôle **`loft-sh/vcluster-oss`** (le chart prend `vcluster-pro` par défaut), distribution `k8s` (image `loft-sh/kubernetes`), stockage par défaut (SQLite embarqué) ; tout par le cache Harbor `ghcr` |
| Espace | **`medidoc-vc-essai`**, créé en libre-service par l'équipe MédiDoc (locataire `medidoc`) |
| Installation | Application **`vc-essai`** (projet `plateforme`, temporaire), valeurs `plateforme/gitops/valeurs/vc-essai/values.yaml` |
| Accès | CLI `vcluster` **0.37.4** sur `adm01` (`vcluster connect`), avec ton identité d'administrateur |
| Mémoire | ≈ 1 Gi (plan de contrôle et CoreDNS virtuel) |
| Comparatif | `docs/plateforme-dev/comparatif-capsule-vcluster.md` |

> ⚠️ **Attention** : le plan de contrôle du vCluster tourne par défaut en `root` ; ne baisse pas le niveau Pod Security de l'espace sans exception écrite au registre du M26. La suppression de l'essai (étape 6) détruit tout ce qui vit dans le vCluster : rien de ce qui compte ne doit y être.

**Travail demandé**

1. **L'espace.** En te faisant passer pour un membre de l'équipe MédiDoc (`--as-group=oidc:medidoc`), crée `medidoc-vc-essai`. Que Capsule y pose-t-il (étiquettes, Pod Security, quotas, RoleBindings) ?
2. **Les valeurs.** Lis le `values.yaml` du chart 0.37.4 : image du plan de contrôle (OSS), distribution et sa version de Kubernetes, stockage, synchronisation vers l'hôte (`sync.toHost`) et depuis l'hôte (`sync.fromHost`), politiques (`policies.*`), télémétrie, contexte de sécurité. Écris des valeurs qui tournent sous Pod Security `restricted` (contexte de sécurité non-root du plan de contrôle et du conteneur d'initialisation), sans télémétrie, images par Harbor, classe `ceph-rbd`. Recopie le chart, Application `vc-essai`.
3. **Dedans.** Connecte-toi. Crée un espace, un Deployment (image de Harbor), un Service, un PVC, une CRD et une ClusterRole. Liste ce que tu vois dans le vCluster et ce que tu vois dans `medidoc-vc-essai` côté hôte (noms traduits, étiquettes). Que vois-tu des nœuds de l'hôte ?
4. **Ce que l'hôte impose.** Dans le vCluster, crée un pod `privileged` : qui le refuse, et à quel moment (création dans le vCluster, ou synchronisation vers l'hôte) ? Un PVC `cephfs` ? Un pod qui dépasse le budget du locataire `medidoc` ? Une image non signée (Kyverno vise-t-il cet espace) ? Note les messages et **où** ils apparaissent.
5. **Les limites.** Pourquoi n'installe-t-on pas Capsule dans le vCluster (version de Kubernetes exigée, et ce que cela dirait du modèle) ? Que coûte un vCluster de plus (mémoire, mises à jour, sauvegardes, supervision) ? Que gagne l'équipe (CRD, webhooks, versions) ?
6. **Comparatif, puis retrait.** Rédige `comparatif-capsule-vcluster.md` (critères : isolation de l'API, CRD et opérateurs, coût, exploitation, sécurité, supervision, cas d'usage où chacun gagne, décision pour MédiSphère). Puis retire l'essai : Application `vc-essai` (avec ses objets), espace `medidoc-vc-essai` (par l'équipe, en libre-service), plus rien dans le cluster qui en parle. Contrôle l'absence.

**Critères de réussite**
- [ ] `comparatif-capsule-vcluster.md` est sur `main`, avec les critères demandés et une décision.
- [ ] Il ne reste ni Application `vc-essai`, ni espace `medidoc-vc-essai`, ni pod ou PVC d'un vCluster dans le cluster.
- [ ] Le locataire `medidoc` est revenu à son nombre d'espaces d'avant l'essai.

**Vérification** : `lab/bin/check 28 09` (il ne passe qu'une fois le comparatif écrit **et** l'essai retiré)

<details><summary>Indice 1</summary>

La page *Run as non-root* de la documentation de vCluster et les champs `controlPlane.statefulSet.security` et `controlPlane.distro.k8s.securityContext` du `values.yaml` ; les pods synchronisés, eux, gardent le contexte de sécurité que tu leur donnes dans le vCluster.
</details>

<details><summary>Indice 2</summary>

Le refus de Pod Security de l'hôte arrive au moment de la synchronisation, pas de la création dans le vCluster : regarde les événements du pod **dans** le vCluster et les journaux du *syncer*.
</details>

**Pour aller plus loin** (facultatif) : lis ce qu'apportent les *private nodes* et l'etcd embarqué de l'édition « Free » enregistrée, et pourquoi MédiSphère s'en tient à l'OSS.

---

### M28-E10 — Le portail montre l'état : plugins Kubernetes et TechDocs  `LAB` `★★`

> **Ticket DEV-2910** — *De : Julien Petit*
> Dans la fiche de MédiAgenda, je veux voir mes pods en dev, recette et prod (en lecture, pas de bouton qui tue un pod en production) et la documentation de l'API à côté du code, écrite en Markdown dans le dépôt. Pas un wiki de plus.

**Objectifs pédagogiques**
- Brancher le plugin Kubernetes avec un compte de service en lecture seule et des objets étiquetés.
- Publier une documentation TechDocs construite par la CI (constructeur externe) dans un stockage objet, lue par le portail.

**Prérequis** : M28-E06, E07 ; M19 (composants CI/CD) ; M05 et M19-E07 (`s3-01`, identités par compartiment).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Plugin Kubernetes | backend `@backstage/plugin-kubernetes-backend` (déjà dans l'application) ; cluster `k8s-par1` déclaré en configuration, accès **dans le cluster** par le compte de service du pod `portail` ; ClusterRole **`portail-lecture-k8s`** (`plateforme/k8s/rbac/`) |
| Rattachement | annotation `backstage.io/kubernetes-id` dans les `catalog-info.yaml` ; étiquette `backstage.io/kubernetes-id` sur les objets (dépôts `…/deploiement`) |
| TechDocs | `techdocs.builder: external` ; publication `awsS3` vers **`s3-01`** (`https://s3-01.par1.medisphere.internal:8333`), compartiment **`portail-techdocs`**, style chemin ; identité d'écriture pour la CI (variables protégées et masquées du groupe, ou coffre), identité de lecture pour le portail ; outil `@techdocs/cli` 1.13 et `mkdocs-techdocs-core` dans un job de CI |
| Checks | identité de lecture copiée dans `~/.config/workbook/s3-techdocs.env` |

**Travail demandé**

1. **Kubernetes.** Configuration du plugin (cluster, méthode d'authentification, types d'objets lus : retire ce qui n'a rien à faire dans un portail — lesquels, pourquoi ?, ressources personnalisées : les Rollouts) ; ClusterRole en lecture seule **sans** Secrets ni journaux de pods, liée au compte de service du portail ; politique réseau vers l'API. Étiquette les objets de MédiAgenda, MédiNotif et MédiDoc (MR dans les dépôts de déploiement) et annote leurs entités. Pas de suppression de pod depuis le portail.
2. **TechDocs.** Compartiment et deux identités sur `s3-01`. Configuration du portail (constructeur externe, publication S3 compatible). Dans `mediagenda/api` : `mkdocs.yml`, `docs/index.md` (présentation, points d'accès, exploitation), annotation `backstage.io/techdocs-ref`, job de CI qui génère et publie le site à chaque fusion sur `main`.
3. **Contrôle.** Fiche `mediagenda-api` : onglet Kubernetes (trois espaces, le Rollout, l'HPA) et documentation. Avec l'identité des checks, liste le compartiment. Complète `portail.md` (plugins, droits, ce qui est exposé à qui).

**Critères de réussite**
- [ ] ClusterRole `portail-lecture-k8s` liée au compte de service du portail, sans droit sur les Secrets ni sur `pods/log`, sans verbe d'écriture.
- [ ] Les entités `mediagenda-api`, `medinotif-worker`, `medidoc` portent `backstage.io/kubernetes-id` ; le Rollout `mediagenda` porte l'étiquette correspondante en recette et en prod.
- [ ] `mediagenda-api` porte `backstage.io/techdocs-ref` ; le site est publié dans `portail-techdocs` (`default/component/mediagenda-api/index.html`).
- [ ] Le pipeline de `main` de `mediagenda/api` publie la documentation.

**Vérification** : `lab/bin/check 28 10`

<details><summary>Indice 1</summary>

`kubernetes.objectTypes` remplace la liste des types lus ; `customResources` ajoute les Rollouts. Avec `authProvider: serviceAccount` et sans jeton, le plugin utilise le compte de service du pod.
</details>

<details><summary>Indice 2</summary>

`techdocs-cli publish --publisher-type awsS3 --storage-name portail-techdocs --entity default/Component/mediagenda-api --awsEndpoint … --awsS3ForcePathStyle` ; les identifiants viennent des variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`. Les chemins publiés sont en minuscules par défaut.
</details>

**Pour aller plus loin** (facultatif) : affiche les Applications Argo CD dans la fiche (plugin communautaire) : quelles données verrait-il, avec quel compte ?

---

### M28-E11 — Revue : l'autoscaling et le locataire du stagiaire  `REV` `★★`

> **Ticket PLAT-2911** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas a préparé de quoi « finir l'autoscaling » et le locataire d'une équipe partenaire, en partant d'exemples trouvés en ligne. Relis-le avant qu'il ouvre la MR : tout ce qui casserait, coûterait ou fuirait. Ne l'applique pas.

**Objectifs pédagogiques**
- Relire des manifestes d'autoscaling et de multi-locataire avec les règles du module.
- Classer des défauts par gravité et proposer des corrections justifiées.

**Prérequis** : M28-E02 à E05.
**Durée indicative** : 1 h 30.

**Contexte technique** : les fichiers de Lucas sont dans [`ressources/E11-lucas/`](../ressources/E11-lucas/) : `hpa-vpa-mediagenda.yaml`, `scaledobject-medinotif-prod.yaml`, `triggerauthentication-medinotif-prod.yaml`, `tenant-partenaire.yaml`, et son mot `README.md`.

**Travail demandé**

1. Lis les quatre manifestes et le mot de Lucas.
2. Dans `docs/plateforme-dev/revue-autoscaling-lucas.md`, un tableau numéroté : fichier, ligne ou champ, défaut, gravité (bloquant, majeur, mineur), conséquence concrète chez MédiSphère, correction proposée.
3. Termine par une synthèse pour Lucas : les trois règles qu'il doit retenir.

**Critères de réussite**
- [ ] Au moins dix défauts distincts relevés, chacun avec une conséquence et une correction.
- [ ] Les défauts bloquants (sécurité, perte de service) sont identifiés comme tels.
- [ ] Rien de la proposition n'est appliqué dans le cluster.
- [ ] `revue-autoscaling-lucas.md` est sur `main`.

**Vérification** : `lab/bin/check 28 11`

<details><summary>Indice 1</summary>

Pour chaque fichier, demande-toi : qui d'autre écrit ce champ ? Que se passe-t-il à 3 h du matin, et le lundi à 9 h ? Que lit un membre d'une autre équipe ? Que se passe-t-il si l'objet est supprimé ?
</details>

<details><summary>Indice 2</summary>

Compare chaque champ au contrat du module : bornes de la production, `behavior`, protocole et droits du scaler, secrets, propriétaires, budget, protection contre la suppression, classes de stockage.
</details>

**Pour aller plus loin** (facultatif) : écris une `ValidatingPolicy` Kyverno (M26) qui aurait refusé deux des défauts relevés.

---

### M28-E12 — Guide d'accueil d'une équipe : le chemin balisé  `RED` `★★`

> **Ticket PLAT-2912** — *De : Claire Morel* — *Copie : Nadia Roussel*
> Une équipe « Téléconsultation » arrive le mois prochain. Je veux qu'elle trouve **une** page qui lui dise comment démarrer sur la plateforme sans nous appeler : obtenir son locataire, créer son premier service par le portail, le voir déployé, le faire monter en charge, trouver sa doc et ses métriques. Et un runbook pour nous : créer un locataire, sans rien oublier.

**Objectifs pédagogiques**
- Écrire une documentation d'accueil orientée tâches (chemin balisé), à jour avec la plateforme réelle.
- Écrire un runbook reproductible et vérifiable.

**Prérequis** : M28-E02 à E10.
**Durée indicative** : 1 h 30.

**Travail demandé**

1. `docs/plateforme-dev/guide-accueil-equipe.md` : à qui il s'adresse ; prérequis (comptes, groupe dans l'annuaire) ; les étapes du chemin balisé, chacune avec ce que l'équipe fait, ce que la Plateforme fait, le délai attendu, comment vérifier ; ce qui est interdit et pourquoi (en une phrase chacun) ; où trouver de l'aide ; les limites actuelles du libre-service.
2. `docs/plateforme-dev/runbooks/RB-280-creer-un-locataire.md` : déclencheur, prérequis, étapes (annuaire, Keycloak, Capsule, espaces, Argo CD, coffre, portail, supervision), vérifications après chaque étape, retour arrière, durée estimée.
3. Fais relire le guide par quelqu'un qui ne connaît pas la plateforme (ou relis-le comme tel, à voix haute) et corrige ce qui suppose un savoir implicite.

**Critères de réussite**
- [ ] Le guide décrit les étapes locataire → portail → déploiement → autoscaling → documentation → supervision, avec pour chacune une vérification.
- [ ] RB-280 a des étapes numérotées, des vérifications et un retour arrière.
- [ ] Les deux fichiers sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 28 12` (présence et contenu ; la qualité s'évalue avec le corrigé)

<details><summary>Indice 1</summary>

Écris le guide en suivant pas à pas le parcours de `medidoc-vignettes` (E08) : chaque fois que tu as dû savoir quelque chose qui n'était écrit nulle part, c'est une ligne du guide.
</details>

<details><summary>Indice 2</summary>

Un bon runbook se lit à 3 h du matin : commandes copiables, résultat attendu après chaque commande, et ce qu'on fait si ce n'est pas le résultat attendu.
</details>

**Pour aller plus loin** (facultatif) : transforme le guide en documentation TechDocs du System `plateforme`, publiée dans le portail.
