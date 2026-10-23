# Module 28 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Fichiers complets dans [`fichiers/`](fichiers/) : `portail/` reproduit `plateforme/portail`, `portail-modeles/` `plateforme/portail-modeles`, `gitops/`, `k8s/`, `identite/`, `secrets/`, `charts-miroir/`, `ansible/` les dépôts de plateforme, `mediagenda-api/`, `medidoc/`, `medinotif-worker/` les projets de code, `deploiement-*` les dépôts de déploiement, `medisphere/` la documentation.

**Ce qui a été vérifié à la rédaction** (23/10/2026) :
- `@backstage/create-app` **0.9.3** lu dans son paquet npm : gabarit `default-app` (nouveau système de frontend, `createApp` de `@backstage/frontend-defaults`), plugins du backend, `engines.node` « 22 || 24 », Yarn 4.13, `Dockerfile` d'hôte (`node:24-trixie-slim`, `USER node`), `app-config.production.yaml` (exemples, invité) ;
- documentation de Backstage **à l'étiquette v1.56.2** : *OIDC provider from scratch* (module backend, `metadataUrl`, `auth.session.secret`, `SignInPageBlueprint`, `OAuth2.create` avec `provider.id: 'oidc'`), *Service to Service Auth* (`externalAccess` statique, `accessRestrictions`, `permissionAttribute`), *Switching to PostgreSQL* (`pluginDivisionMode: schema`), *GitLab Discovery*, *LDAP Organizational Data*, Kubernetes (*configuration* : `serviceAccount` sans jeton = client dans le cluster, `objectTypes`, `customResources`, `frontend.podDelete`), TechDocs (*configuration* `awsS3`, CLI `publish`), *Deploying with Docker* (multi-étapes) ;
- code de la 1.56.2 : le module OIDC n'enregistre que `emailLocalPartMatchingUserEntityName` et `emailMatchingUserEntityProfileEmail` (`src/resolvers.ts`) alors que `config.d.ts` annonce aussi `preferredUsernameMatchingUserEntityName` → résolveur écrit dans un module local ; `AuthResolverCatalogUserQuery` (`entityRef.name`) ; identifiants des actions GitLab du *scaffolder* (`publish:gitlab`, `publish:gitlab:merge-request` et leurs entrées, `mergeRequestUrl`) ; `scaffolder.defaultAuthor` ; options de `backstage-cli config:check` (`--lax`) ;
- chart `backstage` **2.10.2** tiré par `helm pull oci://ghcr.io/backstage/charts/backstage`, empreinte de l'archive calculée, rendu avec nos valeurs (`fullnameOverride`, `command`/`args`, `httpRoute`, compte de service) ; sous-charts Bitnami `common` (bibliothèque) et `postgresql` (désactivé) constatés ;
- chart `loft/vcluster` **0.37.4** : empreinte, valeurs (image `vcluster-pro` par défaut, distribution `k8s` v1.36.5, plan de contrôle en `runAsUser: 0`, `defaultImageRegistry` qui remplace tous les registres), rendu avec nos valeurs (ClusterRole sur les PV et les `VolumeSnapshotContent`, contexte non-root) ;
- API GitLab des comptes de service (Free depuis 18.11, `external` vrai par défaut depuis 19.5) ; `@techdocs/cli` 1.13.0 et `mkdocs-techdocs-core` 1.7.1 (npm, PyPI) ;
- manifestes : `kubeconform -strict` (catalogue de schémas de CRD pour `cilium.io`, `external-secrets.io`, `argoproj.io`), `Cluster` CNPG validé contre la CRD 1.30.1 ; squelettes du modèle rendus avec `medidoc-vignettes` : `go vet`, `go build` (Go 1.26), `py_compile`, `kustomize build` + `kubeconform` ; `outils/exporter_openapi.py` exécuté contre `apps/mediagenda` (`ruff` propre) ; `RB-280` et le guide relus contre les fichiers produits.

**Points non testés en conditions réelles** : l'application Backstage n'a pas été construite (`yarn install` complet) : les fichiers TypeScript suivent la documentation et les types de la 1.56.2 lus dans le code, **à compiler** (`yarn tsc`) ; le démarrage dans `k8s-par1` (PSA `restricted` en lecture seule, connexion Keycloak, LDAPS d'`ipa01`, découverte de `git01`) ; le refus du jeton des checks hors du plugin `catalog` (code HTTP exact) ; le modèle `nouveau-service` de bout en bout (formulaire, dépendances du schéma, MR) ; le vCluster dans `medidoc-vc-essai` (non-root, refus à la synchronisation, messages) ; la publication TechDocs vers SeaweedFS (style chemin) ; les noms des objets créés par Capsule.

---

### M28-E06 — Backstage : construire et installer le portail

**Solution**

1. **L'application.**
   ```
   admin@adm01:~/src$ npx @backstage/create-app@0.9.3 --path ./portail      # nom : portail
   admin@adm01:~/src/portail$ cat package.json | jq .engines                 # { "node": "22 || 24" }
   admin@adm01:~/src/portail$ yarn start                                      # http://localhost:3000, catalogue d'exemple
   ```
   Le backend charge : `app-backend`, `proxy-backend`, `scaffolder` (+ module GitHub, + notifications), `techdocs`, `auth` (+ invité), `catalog` (+ modèle d'entités du scaffolder, + journaux), `permission` (+ « tout permis »), `search` (+ PostgreSQL, catalogue, TechDocs), `kubernetes`, `user-settings`, `notifications`, `signals`, `mcp-actions`. Retirés : invité (pas d'accès anonyme ; un invité serait propriétaire de rien et lirait tout) et module GitHub (pas de GitHub ; un module inutile = une surface et des mises à jour de plus). Fichier final : [`packages/backend/src/index.ts`](fichiers/M28-E06/portail/packages/backend/src/index.ts) (il contient déjà les modules d'E07 et E08).
2. **OIDC.** Client : [`clients-backstage.tf`](fichiers/M28-E06/identite/tofu/clients-backstage.tf) (même modèle que `grafana`, secret imposé). Backstage : [`modules/authOidcMedisphere.ts`](fichiers/M28-E06/portail/packages/backend/src/modules/authOidcMedisphere.ts) (fournisseur `oidc`, résolveur `preferred_username` → `User`), [`App.tsx`](fichiers/M28-E06/portail/packages/app/src/App.tsx) (API `auth.keycloak`, `SignInPage` à un seul fournisseur). Paquets : `yarn --cwd packages/backend add @backstage/backend-plugin-api @backstage/plugin-auth-backend-module-oidc-provider` ; `yarn --cwd packages/app add @backstage/core-app-api`.
3. **La production.** [`app-config.production.yaml`](fichiers/M28-E06/portail/app-config.production.yaml).
4. **L'image.** [`Dockerfile`](fichiers/M28-E06/portail/Dockerfile), [`.dockerignore`](fichiers/M28-E06/portail/.dockerignore), [`catalog-info.yaml`](fichiers/M28-E06/portail/catalog-info.yaml), [`.gitlab-ci.yml`](fichiers/M28-E06/portail/.gitlab-ci.yml). Utilisateur : `node` = UID 1000.
5. **Base et secrets.** [`espaces/portail/`](fichiers/M28-E06/k8s/espaces/portail/) : `50-portail-db.yaml` (CNPG, `initdb` `portail`/`portail`), `40-externalsecret.yaml`, `10-racine-medisphere.yaml`, `20-reseau.yaml` ; politique OpenBao : [`eso-plateforme.extrait`](fichiers/M28-E06/secrets/politiques/eso-plateforme.extrait-M28-E06.hcl).
   ```
   admin@adm01:~$ bao kv put kv/plateforme/portail oidc_client_secret="$(openssl rand -hex 32)" \
       session_secret="$(openssl rand -hex 32)" checks_token="$(openssl rand -hex 32)"
   admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/backstage-checks.token \
       && bao kv get -field=checks_token kv/plateforme/portail > ~/.config/workbook/backstage-checks.token
   ```
6. **Déploiement.** [`charts.extrait`](fichiers/M28-E06/charts-miroir/charts.extrait-M28-E06.yaml), [`valeurs/portail/values.yaml`](fichiers/M28-E06/gitops/valeurs/portail/values.yaml), [`plateforme/portail.yaml`](fichiers/M28-E06/gitops/plateforme/portail.yaml), destination `portail` de l'AppProject ([extrait M28](fichiers/M28-E03/gitops/projets/plateforme.extrait-M28.yaml)). Réponses : la `command` du chart (`node packages/backend`) remplace la `CMD` de l'image, donc ses `--config` ; sans `backstage.args`, seule la configuration de développement (SQLite en mémoire, invité) est lue. Le dossier `charts/` contient `common` (gabarits Bitnami, aucune image) et `postgresql` (désactivé) : aucune **image** ni aucun **chart déployé** Bitnami, ce que vise la règle ; la dépendance est notée pour la montée du chart.
7. **Contrôle.** Connexion avant E07 : Keycloak authentifie, puis le résolveur ne trouve pas d'entité `User` → « Failed to sign-in, unable to resolve user identity » : voulu (seules les personnes de l'annuaire, donc du catalogue, entrent). Jeton des checks et documentation : [`portail.md`](fichiers/M28-E06/medisphere/docs/plateforme-dev/portail.md).

**Explications**

Une application Backstage est un **monodépôt** : `packages/app` (le frontend, construit en fichiers statiques et servi par le plugin `app-backend`), `packages/backend` (le serveur Node.js) et d'éventuels `plugins/`. Le nouveau backend compose des *features* (`backend.add`) ; un module (`createBackendModule`) étend un plugin par ses points d'extension — ici le fournisseur `oidc` du plugin `auth`. Le nouveau frontend compose des extensions : l'API d'authentification et la page de connexion sont deux extensions d'un module du plugin `app`.

La configuration est empilée (`--config` successifs, la dernière l'emporte, une liste remplace la liste) et les `${VAR}` sont résolues au démarrage : l'image ne contient aucun secret et sert tous les environnements. `pluginDivisionMode: schema` met chaque plugin dans un schéma de la base `portail`, ce que le propriétaire CNPG peut faire.

L'accès externe statique crée une identité de service (`wb-checks`) dont les `accessRestrictions` limitent les plugins et les actions : le catalogue en lecture. Sans restriction, le jeton aurait tous les droits de tous les plugins.

**Alternatives**

- **Module communautaire Keycloak** (`@backstage-community/plugin-auth-backend-module-keycloak-provider`, documenté par la 1.56) : fournit `preferredUsernameMatchingUserEntityName` ; un paquet communautaire de plus à suivre.
- **`emailLocalPartMatchingUserEntityName`** : marche si l'adresse est `<uid>@medisphere.internal` pour tout le monde ; plus fragile qu'une revendication d'identifiant.
- **Construction « sur l'hôte »** (`yarn build:backend` puis `Dockerfile` du gabarit) : plus rapide, mais exige Node.js 24 sur le runner ; la multi-étapes ne demande que BuildKit.
- **Proxy d'authentification** (OAuth2 Proxy du M24 devant le portail, fournisseur `oauth2Proxy`) : une brique de plus, utile si l'on veut le même parcours que Hubble.

**Pièges classiques**

- Déclarer `preferredUsernameMatchingUserEntityName` dans `signIn.resolvers` du module générique : accepté par le schéma, refusé à la connexion.
- Oublier `backstage.args` : le pod démarre « sain » avec SQLite en mémoire et l'invité.
- `USER node` sans `runAsUser: 1000` : `CreateContainerConfigError` (« image has non-numeric user »).
- Laisser les emplacements d'exemple (`./examples/…`) : entités fictives au catalogue, et `examples/` copié dans l'image.
- Une URI de redirection plus large que nécessaire (joker) dans le client Keycloak.
- Un jeton statique court ou réutilisé ailleurs : il donne la lecture de tout le catalogue.

**En production chez MédiSphère**

Deux réplicas, PDB, sauvegarde et archivage de `portail-db`, supervision et montée de version au palier 3 (M28-E16) ; politique de permissions réelle (remplacer « tout permis ») ; rotation des secrets du coffre ; Renovate sur `backstage.json`.

---

### M28-E07 — Le catalogue : services, équipes et propriétaires

**Solution**

1. **Comptes.** FreeIPA : [`comptes-systeme.extrait`](fichiers/M28-E07/identite/annuaire/comptes-systeme.extrait-M28-E07.yml). GitLab : commandes et appartenances dans [`catalogue.md`](fichiers/M28-E07/medisphere/docs/plateforme-dev/catalogue.md) ; `external: true` par défaut (19.5) : l'utilisateur ne voit que les projets dont il est membre — c'est une protection, d'où les appartenances explicites. Secrets : `bao kv patch kv/plateforme/portail gitlab_token=… ldap_mot_de_passe=…`.
2. **Organisation** et 3. **découverte** : [`app-config.production.extrait-M28-E07`](fichiers/M28-E07/portail/app-config.production.extrait-M28-E07.yaml). Champ obligatoire absent : `spec.type` d'un `Group` (la correspondance par défaut lit `groupType`, inexistant dans FreeIPA) → `set: spec.type: equipe`.
4. **Entités** : [`mediagenda/api`](fichiers/M28-E07/mediagenda-api/catalog-info.yaml) (Component + API, avec [`outils/exporter_openapi.py`](fichiers/M28-E07/mediagenda-api/outils/exporter_openapi.py) et le [job de CI](fichiers/M28-E07/mediagenda-api/.gitlab-ci.extrait-M28-E07.yml) qui vérifie `openapi.json`), [`medidoc/medidoc`](fichiers/M28-E07/medidoc/catalog-info.yaml), [`medinotif/worker`](fichiers/M28-E07/medinotif-worker/catalog-info.yaml), [`plateforme/medisphere`](fichiers/M28-E07/medisphere/catalog-info.yaml) (Domain, Systems, Resources), `plateforme/portail` (E06). Choix pour l'API : un fichier versionné plutôt que l'URL `/openapi.json` d'un environnement (pas de dépendance à un environnement qui tourne, ni de flux du portail vers la Gateway, et le contrat se relit en MR).
5. **Contrôle.**
   ```
   admin@adm01:~$ T=$(<~/.config/workbook/backstage-checks.token)
   admin@adm01:~$ curl -s -H "Authorization: Bearer $T" https://portail.apps.par1.medisphere.internal/api/catalog/entities/by-name/user/default/julien.petit \
       | jq '[.relations[] | select(.type == "memberOf") | .targetRef]'
   [ "group:default/mediagenda" ]
   admin@adm01:~$ curl -s -H "Authorization: Bearer $T" https://portail.apps.par1.medisphere.internal/api/catalog/entities/by-name/component/default/mediagenda-api | jq -r .spec.owner
   group:default/mediagenda
   ```
   Essai d'usurpation : [`formation/catalogue-essai`](fichiers/M28-E07/formation-catalogue-essai/catalog-info.yaml) → erreur de traitement de l'emplacement (« … not allowed by the rules … »), aucun `Group` `mediagenda-bis`.

**Explications**

Deux mécanismes alimentent le catalogue. Les **fournisseurs** (LDAP) écrivent directement des entités : ils sont la source de vérité de ce qu'ils couvrent, et une personne retirée de l'annuaire disparaît du catalogue. La **découverte GitLab** n'écrit que des `Location` ; le catalogue lit ensuite les fichiers et les passe aux **règles** : c'est là que l'on interdit à un dépôt de déclarer une équipe. Les relations (`ownedBy`, `memberOf`, `partOf`) sont calculées : un propriétaire mal écrit ne bloque rien mais se voit dans le graphe et dans les requêtes de revue.

**Alternatives**

- **Organisation par Keycloak** (module communautaire `catalog-backend-module-keycloak`) : une source de plus entre l'annuaire et le portail ; l'annuaire reste la source des personnes (M24).
- **Organisation par GitLab** (`catalog-backend-module-gitlab-org`) : groupes GitLab ≠ équipes (les groupes GitLab sont des espaces de projets).
- **Emplacements statiques** (`catalog.locations` par dépôt) : chaque nouveau projet exigerait une MR sur le portail.

**Pièges classiques**

- Oublier `set: spec.type` : tous les groupes en erreur de validation, les `User` sans appartenance.
- Filtrer les personnes sur `objectClass=person` sans exclure `nsAccountLock` : un ancien employé reste propriétaire et peut se connecter au portail tant que Keycloak l'accepte.
- Importer `admins` ou `ipausers` : des groupes techniques deviennent « équipes ».
- Un compte de service GitLab administrateur « pour aller vite ».
- Mettre `owner: julien.petit` : propriété perdue au premier départ.

**En production chez MédiSphère**

Événements `push` de GitLab vers le portail (fraîcheur), revue mensuelle des entités sans propriétaire valide, supervision des erreurs de traitement (`catalog_processing_*`), rotation du jeton de `svc-portail`.

---

### M28-E08 — Un modèle « nouveau service »

**Solution** (une solution parmi d'autres ; le corrigé d'un `LIBRE` se juge sur les contraintes)

- Modèle : [`template.yaml`](fichiers/M28-E08/portail-modeles/modeles/nouveau-service/template.yaml) ; squelettes [`python`](fichiers/M28-E08/portail-modeles/modeles/nouveau-service/squelettes/python/), [`go`](fichiers/M28-E08/portail-modeles/modeles/nouveau-service/squelettes/go/), [`deploiement`](fichiers/M28-E08/portail-modeles/modeles/nouveau-service/squelettes/deploiement/) ; propositions [`k8s`](fichiers/M28-E08/portail-modeles/modeles/nouveau-service/propositions/k8s/) et [`gitops`](fichiers/M28-E08/portail-modeles/modeles/nouveau-service/propositions/gitops/) (noms de fichiers gabarits `${{ values.nom }}`).
- Portail : [`app-config.production.extrait-M28-E08`](fichiers/M28-E08/portail/app-config.production.extrait-M28-E08.yaml) (emplacement du modèle avec sa règle, auteur des commits), module `@backstage/plugin-scaffolder-backend-module-gitlab` (déjà dans `index.ts`).
- Droits, ordre de fusion, limites : [`modeles.md`](fichiers/M28-E08/medisphere/docs/plateforme-dev/modeles.md).

Déroulé de l'essai : formulaire (équipe `medidoc`, locataire `medidoc`, nom `medidoc-vignettes`, Go) → deux projets, deux MR (`portail/medidoc-vignettes`) → fusion de la MR `plateforme/k8s`, `task espaces`, rattachement → fusion de la MR `plateforme/gitops` → premier pipeline du code, MR de promotion, fusion → `kubectl -n medidoc-vignettes-dev get pods` prêts, fiche du composant dans le portail.

**Explications**

Trois familles d'actions : **rendre** (`fetch:template`, squelettes avec `${{ values.* }}`, même dans les noms de fichiers), **publier** (`publish:gitlab` : nouveau projet, premier commit sur `main`), **proposer** (`publish:gitlab:merge-request` : une branche et une MR dans un projet existant, `targetPath` pour placer les fichiers, `commitAction: create` pour ne rien écraser). La frontière est volontaire : l'équipe possède ce qui est à elle (son code, son déploiement) dès la création ; ce qui engage la plateforme (un espace, une Application) passe par une relecture humaine.

Le formulaire est un JSON Schema : les `dependencies` (`oneOf` sur l'équipe) imposent le préfixe du locataire, et le backend revalide les paramètres contre ce schéma. Toutes les actions utilisent le jeton de `svc-portail` : les droits du compte, et non le formulaire, sont la vraie limite.

**Alternatives**

- **Un seul projet** (code et `deploiement/`) : plus simple, mais la promotion par MR vers son propre projet relancerait le pipeline du code ; MédiSphère sépare depuis M17.
- **Modèle qui pousse directement dans `plateforme/gitops`** : plus rapide, mais sans relecture ; refusé par la contrainte.
- **Générer avec cookiecutter ou copier un projet modèle GitLab** (*project templates*) : pas d'intégration au catalogue ni aux MR de la plateforme.
- **Une seule MR dans un dépôt « demandes »** traitée par un pipeline de la plateforme : découple le portail des dépôts de la plateforme ; plus de mécanique.

**Pièges classiques**

- Jeton d'intégration en lecture seule (`read_api`) : la publication échoue au premier projet.
- Protection de branche par défaut sans premier envoi pour les développeurs : `publish:gitlab` crée le projet puis échoue au premier `push`.
- Squelette qui ne passe pas Pod Security `restricted` ou sans `requests` : le premier déploiement échoue chez l'équipe, qui en déduit que le chemin balisé ne marche pas.
- Oublier que l'AppProject de l'équipe doit autoriser le nouveau dépôt et le nouvel espace.
- Un nom accepté par le formulaire mais pas par Capsule (préfixe) : l'espace serait refusé à la fusion.

**En production chez MédiSphère**

Versions des composants CI tenues par Renovate dans les squelettes ; tests du modèle en CI (`@backstage/plugin-scaffolder-backend` en mode essai à blanc, *dry-run* depuis l'éditeur de modèles du portail) ; mesure : délai formulaire → service en `dev` ; permissions du portail limitant le modèle aux membres d'une équipe (M28-E16).

---

### M28-E09 — vCluster : un cluster virtuel pour une équipe, puis retrait

**Solution**

1. **Espace.**
   ```
   admin@adm01:~$ kubectl create namespace medidoc-vc-essai --as=oidc:essai.medidoc --as-group=oidc:medidoc
   admin@adm01:~$ kubectl get ns medidoc-vc-essai --show-labels      # tenant medidoc, PSA restricted, libre-service
   admin@adm01:~$ kubectl -n medidoc-vc-essai get rolebindings,resourcequotas
   ```
2. **Valeurs** : [`valeurs/vc-essai/values.yaml`](fichiers/M28-E09/gitops/valeurs/vc-essai/values.yaml), [`charts.extrait`](fichiers/M28-E09/charts-miroir/charts.extrait-M28-E09.yaml), [`plateforme/vc-essai.yaml`](fichiers/M28-E09/gitops/plateforme/vc-essai.yaml) (+ destination `medidoc-vc-essai` ajoutée **temporairement** à l'AppProject `plateforme`).
3. **Dedans** (CLI : binaire `vcluster-linux-amd64` de la version v0.37.4 des publications GitHub de `loft-sh/vcluster`, empreinte contrôlée avec le `checksums.txt` de la version, installé dans `~/.local/bin/vcluster`) :
   ```
   admin@adm01:~$ vcluster connect vc-essai -n medidoc-vc-essai      # CLI 0.37.4 ; ouvre un contexte « vcluster_vc-essai_… »
   admin@adm01:~$ kubectl apply -f ~/DevOpsPrivateCloud/modules/28-plateforme-dev/corrige/fichiers/M28-E09/essais/dans-le-vcluster.yaml
   admin@adm01:~$ kubectl get ns,deploy,pods,svc,pvc,crd -A | head -30         # vue virtuelle
   admin@adm01:~$ vcluster disconnect
   admin@adm01:~$ kubectl -n medidoc-vc-essai get pods,svc,pvc                  # vue de l'hôte : echo-…-x-essai-x-vc-essai
   ```
   (Fichier d'essai : [`essais/dans-le-vcluster.yaml`](fichiers/M28-E09/essais/dans-le-vcluster.yaml) ; l'appliquer avec le contexte du vCluster.)
4. **Ce que l'hôte impose** : `kubectl describe pod privilegie -n essai` (dans le vCluster) → événement de synchronisation refusée (Pod Security de l'hôte) ; PVC `partage` → refus du webhook de Capsule à la synchronisation ; journaux : `kubectl -n medidoc-vc-essai logs statefulset/vc-essai | grep -i error`.
5. **Limites** et 6. **comparatif** : [`comparatif-capsule-vcluster.md`](fichiers/M28-E09/medisphere/docs/plateforme-dev/comparatif-capsule-vcluster.md). Retrait :
   ```
   admin@adm01:~/src/gitops$ git rm plateforme/vc-essai.yaml valeurs/vc-essai/values.yaml   # + destination retirée de projets/plateforme.yaml ; MR
   admin@adm01:~$ kubectl get application -n argocd vc-essai                            # NotFound après l'élagage
   admin@adm01:~$ kubectl delete namespace medidoc-vc-essai --as=oidc:essai.medidoc --as-group=oidc:medidoc
   admin@adm01:~$ kubectl get pods,pvc -A -l app=vcluster ; kubectl get clusterrole | grep vc-vc-essai
   ```

**Explications**

Le plan de contrôle du vCluster (apiserver, contrôleurs, SQLite) tourne dans un pod de l'espace hôte ; le **syncer** recopie dans cet espace ce qui doit vraiment tourner, en traduisant les noms (`<nom>-x-<espace>-x-<vcluster>`) et les références. Tout ce qui est « logique » (Deployments, CRD, RBAC) reste dans l'API virtuelle. D'où les deux faces : l'équipe est administratrice de son API, mais ses pods restent soumis à l'hôte — Pod Security, quotas, Capsule — **au moment de la synchronisation**, ce qui rend les refus moins lisibles (le pod virtuel reste `Pending`, l'erreur est dans un événement ou les journaux du syncer).

**Alternatives**

- **CLI `vcluster create`** au lieu d'Argo CD : plus rapide pour un essai, mais hors GitOps et avec le compte de la personne.
- **Distribution k3s** (plus légère) : supportée par le chart ; `k8s` garde la même version que l'hôte.
- **Clusters dédiés par Cluster API** (M18) : isolation complète, coût de VMs.

**Pièges classiques**

- Garder l'image `vcluster-pro` par défaut : modules non libres embarqués (désactivés, mais ce n'est plus l'OSS demandé).
- `controlPlane.advanced.defaultImageRegistry` : remplace le registre de **toutes** les images, `ghcr.io` comme Docker Hub.
- Baisser Pod Security de l'espace au lieu de passer le plan de contrôle en non-root.
- Oublier la ClusterRole créée par le chart (dépasse les droits d'une équipe), ou la destination temporaire de l'AppProject après le retrait.
- Croire qu'un vCluster isole les charges : mêmes nœuds, même noyau.

**En production chez MédiSphère**

Pas de vCluster permanent (décision du comparatif). Si un besoin ponctuel revient : demande écrite, vCluster éphémère créé par la plateforme avec durée de vie, supervision et suppression planifiées.

---

### M28-E10 — Le portail montre l'état : plugins Kubernetes et TechDocs

**Solution**

1. **Kubernetes** : [`app-config.production.extrait-M28-E10`](fichiers/M28-E10/portail/app-config.production.extrait-M28-E10.yaml) (cluster, `objectTypes` sans `configmaps`, Rollouts, `podDelete` désactivé), [`rbac/portail-lecture-k8s.yaml`](fichiers/M28-E10/k8s/rbac/portail-lecture-k8s.yaml), sortie vers l'API déjà dans `20-reseau.yaml` (E06). Étiquettes : [MédiAgenda](fichiers/M28-E10/mediagenda-deploiement/base-kustomization.extrait-M28-E10.yaml), [MédiNotif](fichiers/M28-E10/medinotif-deploiement/base-kustomization.extrait-M28-E10.yaml), [MédiDoc](fichiers/M28-E10/medidoc-deploiement/base-kustomization.extrait-M28-E10.yaml) ; annotations : [`catalog-info.extrait`](fichiers/M28-E10/mediagenda-api/catalog-info.extrait-M28-E10.yaml). Retirés des types lus : `configmaps` (configuration des applications, visible de toute l'entreprise par le portail) ; `pods/log` jamais accordé.
2. **TechDocs** : compartiment et identités [`seaweedfs.yml.extrait`](fichiers/M28-E10/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait) ; image d'outils [`outils-techdocs`](fichiers/M28-E10/ci-templates/images/outils-techdocs/Dockerfile) ; dans `mediagenda/api` : [`mkdocs.yml`](fichiers/M28-E10/mediagenda-api/mkdocs.yml), [`docs/index.md`](fichiers/M28-E10/mediagenda-api/docs/index.md), [job de CI](fichiers/M28-E10/mediagenda-api/.gitlab-ci.extrait-M28-E10.yml). Identité de lecture du portail : `bao kv patch kv/plateforme/portail techdocs_cle=… techdocs_secret=…` ; copie pour les checks : `~/.config/workbook/s3-techdocs.env` (600, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).
3. **Contrôle** :
   ```
   admin@adm01:~$ ( set -a; . ~/.config/workbook/s3-techdocs.env; set +a
       aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls s3://portail-techdocs/default/component/mediagenda-api/ )
   ```
   Documentation : [`portail.extrait-M28-E10`](fichiers/M28-E10/medisphere/docs/plateforme-dev/portail.extrait-M28-E10.md).

**Explications**

Le plugin Kubernetes interroge l'API **du cluster entier** avec un sélecteur d'étiquettes par type d'objet (d'où la ClusterRole) et regroupe le résultat par entité ; l'annotation de l'entité doit correspondre à l'étiquette des objets. `authProvider: serviceAccount` sans jeton = client « dans le cluster » : le jeton projeté du pod, pas de secret longue durée. TechDocs en constructeur externe sépare la **construction** (la CI du projet, qui a le code et ses dépendances) de la **lecture** (le portail, qui ne fait que servir des fichiers statiques) : le portail n'exécute jamais de code d'un dépôt.

**Alternatives**

- **`backstage.io/kubernetes-label-selector`** : réutiliser les étiquettes existantes (`app.kubernetes.io/name`) sans en poser de nouvelles ; plus fragile quand deux services partagent un nom.
- **Constructeur `local`** : le portail génère la doc à la demande (Docker ou mkdocs dans le pod) — exécution de contenu de dépôt dans le portail, refusé.
- **Une identité par équipe sur le compartiment** (préfixe par entité) : empêche une équipe d'écraser la doc d'une autre ; à faire avec la politique de compartiment quand plus de deux équipes publient.

**Pièges classiques**

- Étiquette posée dans les sélecteurs (`includeSelectors: true`) : sélecteur de Deployment immuable, synchronisation en erreur.
- Publication en chemin sensible à la casse (`--legacyUseCaseSensitiveTripletPaths`) alors que le portail lit en minuscules : « documentation introuvable ».
- Installer mkdocs pendant le job avec un utilisateur non-root (`apt-get` refusé) : d'où l'image d'outils.
- Donner `configmaps`, `secrets` ou `pods/log` au plugin « pour être complet ».

**En production chez MédiSphère**

Une identité de publication par équipe, TechDocs de la plateforme (guide d'accueil, runbooks) publiés par la CI de `plateforme/medisphere`, permission du plugin Kubernetes par équipe (palier 3).

---

### M28-E11 — Revue : l'autoscaling et le locataire du stagiaire

**Solution** : le compte rendu attendu est [`revue-autoscaling-lucas.md`](fichiers/M28-E11/medisphere/docs/plateforme-dev/revue-autoscaling-lucas.md) (21 constats). Les défauts **bloquants** à ne pas manquer : API `autoscaling/v2beta2` retirée ; cible `Deployment` au lieu du Rollout ; VPA actif (`Auto` = `Recreate`) sur la même ressource que l'HPA CPU ; AMQP en clair sur 5672 avec le **compte du worker** (droit de consommer) ; mot de passe en clair dans un `Secret` versionné ; `cluster-admin` donné au propriétaire d'un locataire ; aucun budget ni quota d'espaces ; `LoadBalancer`/`NodePort`/`ExternalName` permis à un tiers.

**Explications**

La revue applique les quatre règles du module : un pilote par champ (HPA, VPA, Argo CD, Argo Rollouts), le moins de droits (compte dédié, `management` + `^$`), aucun secret dans Git, des contrats écrits pour la production et les tiers (bornes, budget, propriétaires de groupe, protections contre la suppression).

**Alternatives** : transformer les constats en garde-fous automatiques — `ValidatingPolicy` Kyverno qui refuse un VPA actif sur une cible qui a un HPA CPU, ou un `Tenant` dont un propriétaire est un `User` ; règle `conftest` (M29) sur les manifestes de `plateforme/k8s/locataires/`.

**Pièges classiques** : s'arrêter à la syntaxe (le fichier `ScaledObject` est **valide** pour l'API : le problème est ce qu'il fait) ; oublier la conséquence concrète (« le stagiaire garde les droits après son départ ») ; proposer une correction sans dire qui la fait et où (dépôt, MR).

**En production chez MédiSphère** : les « exemples trouvés en ligne » passent par un modèle du portail ou un exemple maintenu dans `docs/plateforme-dev/` ; toute première contribution d'un stagiaire est relue en binôme.

---

### M28-E12 — Guide d'accueil d'une équipe : le chemin balisé

**Solution** : [`guide-accueil-equipe.md`](fichiers/M28-E12/medisphere/docs/plateforme-dev/guide-accueil-equipe.md) et [`RB-280-creer-un-locataire.md`](fichiers/M28-E12/medisphere/docs/plateforme-dev/runbooks/RB-280-creer-un-locataire.md).

Grille d'auto-évaluation (2 points chacun, sur 16) : le guide dit **qui fait quoi et en combien de temps** à chaque étape ; chaque étape a une **vérification** observable ; les interdits ont **leur raison** en une phrase ; les **limites** du libre-service sont écrites ; RB-280 est **exécutable** (variables, commandes, résultats attendus) ; il a un **retour arrière** dans le bon ordre (espaces avant le `Tenant`) ; il couvre annuaire, Capsule, espaces, Argo CD, coffre, portail, supervision ; aucun savoir implicite (relecture « à voix haute »).

**Explications** : un chemin balisé ne vaut que s'il est **trouvable** (une page, liée depuis le portail) et **vrai** (il suit l'essai de `medidoc-vignettes`). Le runbook de la plateforme est l'envers du guide : chaque promesse du guide (« un jour ouvré ») suppose une étape du runbook qui la tient.

**Pièges classiques** : un guide qui décrit l'outil au lieu de la tâche ; des délais promis que personne n'a mesurés ; un runbook qui supprime le `Tenant` en premier (les espaces partent avec).

**En production chez MédiSphère** : le guide publié en TechDocs du System `plateforme`, revu à chaque modification du modèle ; le délai réel d'accueil mesuré (ticket → premier service en `dev`) et suivi comme un indicateur de la plateforme.
