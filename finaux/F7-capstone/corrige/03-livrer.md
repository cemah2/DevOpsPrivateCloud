# Final F7 — Phase 3 : Livrer — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les solutions des `LIBRE` sont **des** solutions de référence, cohérentes avec les ADR-0370 à ADR-0374 du corrigé de la phase 2 ; une autre, qui tient les mêmes critères et les mêmes standards, vaut autant.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- correctifs de `mediagenda/api` (filtres de la liste, déplacement, bornes de l'identifiant, titre, portées) appliqués à une copie de `apps/mediagenda` + rappel du M27 : **59 tests verts** (39 existants + 20 tests de contrat), `ruff check` propre ; les tests de contrat **échouent** quand l'opération `PATCH` est retirée (vérifié) ;
- relecture (23/10/2026) : mêmes correctifs rejoués sur `apps/mediagenda` + **tous** les correctifs des modules (M22-E06, M23-E04/E06/E08/E14, M27-E06/E08 : état « fin du F4 ») : **87 tests verts** (67 + 20), `ruff check` et `ruff format` propres ; MR fautive (`PATCH` → `PUT`) : 2 tests de contrat en échec ; `oasdiff breaking` **1.34.1** contre la description générée : vert avec `oasdiff-ecarts-acceptes.txt`, rouge sur la MR fautive (`api-removed-without-deprecation`) ;
- relecture : `tofu validate` (OpenTofu 1.13.0, fournisseurs `keycloak/keycloak` 5.10.0 et `hashicorp/vault` 5.x) des racines `tofu/` (fichiers du M24 + F7) et `simulations/ghsv-idp/` et de `clients.tf` ; clés de configuration de Keycloak (`pkceEnabled`, `pkceMethod`, `clientAuthMethod`, `claims`, `are.claim.values.regex`, `group`, `client_scope`, `negate`) et comportement de la synchronisation `FORCE` lus dans les sources de Keycloak 26.8.1 ; options d'OAuth2 Proxy lues dans les sources de la 7.15.5 ; module blackbox validé par `blackbox_exporter --config.check` (0.29.1) ; champs du CRD de Pyrra lus dans les sources de la 0.10.2 ;
- `ms-rapport-client` exécuté contre un Prometheus simulé (valeurs fixes) : calcul des intervalles hors maintenances, contrôle de conformité d'une maintenance (annonce, fenêtre de nuit, cumul), rendu Markdown ;
- scripts : `bash -n` et `shellcheck -x` propres (`ms-reversibilite`, `ms-rapport-client`, checks, `break-S11.sh`) ; checks et panne exécutés sans lab (outils simulés en échec) : aucun arrêt intempestif, messages en KO, `--annuler` sans état ;
- expressions `jq` de la panne (mappeur, audience du mandataire) rejouées sur des représentations d'exemple ;
- manifestes et fichiers YAML : syntaxe valide.

**Fichiers** : [`fichiers/F7-S07/`](fichiers/F7-S07/) à [`fichiers/F7-S11/`](fichiers/F7-S11/), en extraits des projets : `equipes/…` = `plateforme/equipes`, `secrets/…`, `identite/…`, `ceph/…`, `ansible/…`, `observabilite/…`, `outils/…`, `resilience/…`, `mediagenda-api/…` = `mediagenda/api`, `mediagenda-deploiement/…` = `mediagenda/deploiement`, `medisphere/…` = `plateforme/medisphere`. Les `*.extrait*` sont à fusionner dans le fichier existant (l'emplacement est en tête). Les valeurs `<EN-MAJUSCULES>` sont à relever sur ton lab (empreintes d'images, versions promues).

**Correspondance avec la phase 2** : ADR-0370 (isolation : ce que crée `equipes/ghsv.yaml` ; le groupe `ghsv` du fichier joue le rôle du groupe « exploitation du GHSV »), ADR-0371 (clés `transit/ghsv-*`, aucune personne avec `decrypt`), ADR-0372 (courtier d'alias `ghsv-idp` dans `medisphere`, comme le royaume simulé ; DPI en compte de service ; groupe unique `ghsv-agents` et rôle `client-externe` : simplifications de la preuve de concept écrites dans l'ADR), ADR-0373 (témoin de RPO, `archive_timeout` à 1 min), ADR-0374 (format d'export, `ms-reversibilite`, RB-371 ; export lancé depuis `adm01`, le pipeline protégé restant la cible). Chaque ADR concernée porte une ligne « Preuve de concept du lab » qui dit ces écarts.

---

### F7-S07 — Le client en code

**Solution**

*1. Le type « client »* — ajout au format v1, comme F2-S07 et F2-S10 : [`schema/equipe.schema.extrait-F7-S07.json`](fichiers/F7-S07/equipes/schema/equipe.schema.extrait-F7-S07.json) (`client` dans l'énumération des types, bloc `spec.client`, règle « un client a un bloc `kubernetes` et pas de libre-service »), [`outils/rendre.extrait-F7-S07.py`](fichiers/F7-S07/equipes/outils/rendre.extrait-F7-S07.py) (contrôles : recette et prod seulement, prod manuelle, dates du contrat, groupe des agents distinct du groupe du compte, compartiment préfixé ; rendu : AppProject à **une** source, ApplicationSet `client-ghsv` par [`gabarits/gitops/client.yaml.j2`](fichiers/F7-S07/equipes/gabarits/gitops/client.yaml.j2), pas d'utilisateur Capsule, étiquette `medisphere.internal/client`, clé `clients_en_code` pour `plateforme/secrets`), tests [`test_rendre.extrait-F7-S07.py`](fichiers/F7-S07/equipes/tests/test_rendre.extrait-F7-S07.py) — dont celui qui rend le dépôt **avec et sans** `ghsv.yaml` et compare octet pour octet les fichiers des autres équipes.

*2. Le fichier* — [`equipes/ghsv.yaml`](fichiers/F7-S07/equipes/equipes/ghsv.yaml) : Julien Petit (responsable) et Nadia Roussel (lecteur) répondent du compte ; recette (600m / 1 Gio) et production (1 CPU / 1,75 Gio) dans un budget de 1,6 CPU / 2,75 Gio ; `ceph-rbd-chiffre` par défaut ; bloc `client` (contrat du 1er mars 2027 au 29 février 2032, dépôt `mediagenda/deploiement`, `overlays/clients`, titre public, adresses, fournisseur `ghsv-idp`, groupe `ghsv-agents`, clés `exports`, `signature`, `sauvegardes`, compartiment `ghsv-reversibilite`, site de secours `par2`).

```
admin@adm01:~/src/equipes$ uv run outils/rendre.py --valider && uv run pytest -q && uv run outils/capacite.py
admin@adm01:~/src/equipes$ uv run outils/rendre.py && tree rendu/gitops/equipes/ghsv rendu/k8s/equipes/ghsv
```

MR relue (Plateforme, Sophie Laurent), fusion, propagation : MR automatiques dans `plateforme/k8s`, `plateforme/gitops`, `plateforme/secrets`, `plateforme/identite`, `plateforme/infra`.

*3. Les clés* — [`secrets/tofu/clients.tf`](fichiers/F7-S07/secrets/tofu/clients.tf) : `transit/ghsv-exports` et `ghsv-sauvegardes` (`aes256-gcm96`), `ghsv-signature` (`ed25519`), toutes `exportable = false`, `allow_plaintext_backup = false`, `deletion_allowed = false`, rotation annuelle ; politiques `ghsv-reversibilite` (produire un export : clé de données, signature, clés S3 ; jamais `decrypt`), `ghsv-dechiffrement` et `ghsv-destruction` attachées à **aucun** groupe, obtenues pour une opération par des **rôles de jeton** (15 min, 10 usages) — ADR-0371 : aucune personne ne détient `decrypt`. `wb-checks` a déjà `list` sur `transit/keys` et `read` sur `transit/keys/+` depuis M25-E17 (métadonnées seulement) : rien à ajouter, mais vérifie-le dans `politiques/wb-checks.hcl`. Politique `ghsv-destruction` : chemins **énumérés** clé par clé (`transit/keys/ghsv-exports/config`…) — dans une politique, `+` ne remplace qu'un segment entier (`ghsv-+` serait lu tel quel) et `*` n'est permis qu'en fin de chemin.

*4. L'instance* — `mediagenda/deploiement` : [`overlays/clients/ghsv-recette`](fichiers/F7-S07/mediagenda-deploiement/overlays/clients/ghsv-recette/kustomization.yaml) et [`ghsv-prod`](fichiers/F7-S07/mediagenda-deploiement/overlays/clients/ghsv-prod/kustomization.yaml) : même base, mêmes components que la prod de MédiAgenda (migrations, Valkey, canary, autoscaling, supervision), plus [`client-donnees`](fichiers/F7-S07/mediagenda-deploiement/components/client-donnees/) (grappe CNPG **propre** au client, même nom `mediagenda-db` dans son espace — donc mêmes Secrets attendus par la base et les migrations —, volume chiffré, archivage dans `cnpg-ghsv`, `archive_timeout` à 1 min) et `client` (fichiers de F7-S08 et S09). Version et nom publié par `livraison.yaml`, promotion par MR (recette au moins 10 jours ouvrés avant la prod, EXP-06). Marque blanche : `MEDIAGENDA_TITRE` (correctif additif de `mediagenda/api`, [`LISEZMOI-F7.md`](fichiers/F7-S09/mediagenda-api/LISEZMOI-F7.md) § config et app) ; rien ne change pour les cabinets qui ne posent pas la variable.

```
admin@adm01:~$ curl -s https://ghsv-recette.apps.par1.medisphere.internal/openapi.json | jq -r .info.title
API de rendez-vous du GHSV (recette)
```

*5. La réversibilité* — compartiments : [`rgw-compartiments.extrait-F7-S07.yaml`](fichiers/F7-S07/ceph/outils/rgw-compartiments.extrait-F7-S07.yaml) (`ghsv-reversibilite` sur le RGW, versionné) et identité `cnpg-ghsv` sur `s3-01` (ajoutée à `filer.sync`). Outil [`ms-reversibilite`](fichiers/F7-S07/outils/bin/ms-reversibilite) (format de l'ADR-0374 : `rendez-vous.jsonl` et `rendez-vous.csv` aux champs de l'API v1, annexe technique `schema.sql` + une table = un CSV, `dictionnaire.csv`, `MANIFESTE.sha256`, `manifeste.json` signé par `transit/ghsv-signature` ; archive chiffrée par une clé de données à usage unique enveloppée par `transit/ghsv-exports` ; travail en mémoire dans `/dev/shm`, lecture en transaction en lecture seule) :

```
admin@adm01:~$ bao login -method=oidc                     # membre du groupe ghsv
admin@adm01:~$ ms-reversibilite exporter ghsv prod
admin@adm01:~$ export BAO_TOKEN="$(bao token create -role=ghsv-dechiffrement -policy=ghsv-dechiffrement -field=token)"   # plateforme-admins
admin@adm01:~$ ms-reversibilite relire ghsv <DOSSIER> --pg 'postgresql://essai@<HÔTE-VIERGE>/essai'
admin@adm01:~$ bao token revoke -self; unset BAO_TOKEN
```

Base vierge : VM jetable **3701** (`vsandbox`, Debian 13 et son PostgreSQL 17 : une version différente de la production, preuve que le format ne dépend pas de nous), détruite après. Compte rendu : [`reversibilite/essai-reference.md`](fichiers/F7-S07/medisphere/docs/capstone/reversibilite/essai-reference.md) ; procédure [RB-371](fichiers/F7-S07/medisphere/docs/capstone/runbooks/RB-371-reversibilite-client.md) (export, relecture, remise par rechiffrement vers la clé publique du client, ce qui est conservé, destruction physique puis cryptographique avec jeton d'opération, instantanés Raft, procès-verbal, rotation et `rewrap`) ; documentation [`locataire-ghsv.md`](fichiers/F7-S07/medisphere/docs/capstone/locataire-ghsv.md).

**Explications**
- **Pourquoi l'AppProject lit `mediagenda/deploiement`** : le client ne possède pas le code ; ses environnements sont des dossiers de l'application hébergée. Une seule source, sans joker, et deux destinations nommées : le projet ne peut rien déployer d'autre ni ailleurs. La production du client avance par la **même** promotion que MédiAgenda : une faille corrigée l'est partout en même temps.
- **Pourquoi le même nom de grappe** (`mediagenda-db`) : la base est séparée par l'espace, pas par le nom ; garder le nom évite de réécrire dix références (Secrets, politiques réseau, Job de migrations) et donc dix occasions d'erreur.
- **Pourquoi des clés d'enveloppe** : `transit` ne chiffre pas 2 To ; il chiffre une clé de données. Supprimer la clé d'enveloppe rend illisibles toutes les clés de données, donc toutes les archives, où qu'elles soient (PAR2, sauvegardes en rétention) : c'est l'effacement cryptographique de R-14. La signature, elle, permet au GHSV de vérifier l'origine de l'export sans nous faire confiance.
- **« Format ouvert »** : un vidage `pg_dump -Fc` exige PostgreSQL, sa version, et notre schéma. Le JSON Lines aux champs de l'API v1 et le CSV se relisent avec n'importe quel outil ; l'annexe technique sert au rechargement exact.

**Alternatives**
- Une équipe interne `ghsv-exploitation` au lieu de personnes dans le fichier client : possible, mais deux fichiers à garder cohérents ; le groupe `ghsv` rendu par le fichier joue ce rôle.
- Identifiants dynamiques de la base (moteur `db-ghsv` d'OpenBao, comme `db-data` du F2) : la cible ; ils exigent une adresse `LoadBalancer` 10.10.41.x par base et par environnement (F2-S07). Écart écrit.
- Export lancé par un **pipeline protégé** (ADR-0374) plutôt que depuis `adm01` : meilleure traçabilité, pas de données sur un poste ; demande un rôle JWT `ci-ghsv-reversibilite` et un runner qui joint la base. Cible de production.
- `age` à la place d'OpenSSL pour l'archive : chiffrement authentifié, mais pas de lien direct avec `transit` (il faudrait envelopper l'identité `age`) ; le rechiffrement vers la clé publique du client, lui, se fait en `age` (RB-371 §3).

**Pièges classiques**
- Un AppProject avec `sourceRepos: ["https://git01…/mediagenda/*"]` : le client déploierait n'importe quel dépôt de l'équipe MédiAgenda dans ses espaces.
- Le groupe des agents égal au groupe du compte : un agent fédéré obtiendrait la lecture du locataire Kubernetes (propriétaire Capsule `oidc:ghsv`).
- `deletion_allowed = true` « pour plus tard » : la clé se supprime d'un appel ; et une clé `exportable` ne redevient jamais non exportable.
- Un test de non-régression du générateur qui ne compare que le client : la contrainte du ticket est sur les **autres** équipes.
- Un export chiffré sur disque mais écrit d'abord en clair dans `/tmp` : la donnée de santé est sur le disque d'`adm01`.
- Une clé de données conservée « au cas où » à côté de l'archive : l'enveloppe ne protège plus rien.

**En production chez MédiSphère**
Le modèle Backstage `nouveau-client` ouvre la MR ; le contrat (dates) déclenche des rappels (essai de réversibilité annuel, fin de contrat à J−6 mois) ; l'export tourne en pipeline protégé hors heures de pointe ; la relecture est faite par l'équipe Data, sans l'outil, chaque année (ADR-0374).

---

### F7-S08 — Fédérer l'identité du client

**Solution**

*1. L'IdP simulé* — racine OpenTofu séparée [`simulations/ghsv-idp/`](fichiers/F7-S08/identite/simulations/ghsv-idp/) dans `plateforme/identite` : état `identite-ghsv-idp/terraform.tfstate` (chiffré), identité `svc-tofu-ghsv-idp` du royaume `master` avec le **seul** rôle `create-realm` (Keycloak donne au créateur l'administration du royaume qu'il crée, rien d'autre). Royaume `ghsv-idp` : flux du navigateur avec OTP **obligatoire** (pas conditionnel) et action requise `CONFIGURE_TOTP` par défaut, protection contre la force brute, client confidentiel `medisphere-courtier` (PKCE, une seule adresse de retour : `…/realms/medisphere/broker/ghsv-idp/endpoint`), revendication `groups` ; groupes `secretariat-medical` et `encadrement`, comptes `agent.demo1`, `agent.demo2` (secrétariat) et `cadre.demo1` (encadrement), mot de passe initial temporaire.

```
admin@adm01:~/src/identite/simulations/ghsv-idp$ tofu init && tofu plan -out plan && tofu apply plan
admin@adm01:~$ curl -s https://sso.par1.medisphere.internal/realms/ghsv-idp/.well-known/openid-configuration | jq -r .issuer
```

*2. Le courtier* — [`tofu/courtier-ghsv.tf`](fichiers/F7-S08/identite/tofu/courtier-ghsv.tf) dans la racine du royaume `medisphere` : fournisseur `ghsv-idp` (signatures vérifiées sur le JWKS, émetteur contrôlé, PKCE, `store_token = false`, `sync_mode = "FORCE"`, `hide_on_login_page = true`, secret en écriture seule depuis une variable éphémère) ; mappeurs : identifiant `ghsv.${CLAIM.preferred_username}`, rôle de royaume `client-externe` codé en dur, groupe `ghsv-agents` par « Advanced Claim to Group » sur `groups` ∋ `secretariat-medical` ; flux `navigateur-ghsv` réduit à l'exécution « Identity Provider Redirector » (`defaultProvider = ghsv-idp`, **sans** « Cookie ») ; client `ghsv-agents` (OAuth2 Proxy) lié à ce flux, session de client de 15 min (en **secondes** : `"900"`, les attributs `client_session_*` d'un client sont passés tels quels à Keycloak) ; flux **après courtier** `apres-courtier-ghsv` (`post_broker_login_flow_alias`) qui refuse tout client sans la portée marqueur `client-ghsv` (« Condition - client scope » inversée + « Deny access », puis « Allow access ») ; rôle `view-identity-providers` de `wb-checks` (ressource `wb_checks_fournisseurs`). Flux réseau `idp01` → VIP 10.10.70.200:443 ([`pare_feu.extrait-F7-S08.yml`](fichiers/F7-S08/ansible/inventories/lab/group_vars/role_routeur/pare_feu.extrait-F7-S08.yml)) : sans lui, l'échange du code échoue côté serveur alors que le navigateur, lui, atteint l'IdP — l'erreur la plus déroutante du scénario.

*3. Le cloisonnement* — [`tofu/flux.extrait-F7-S08.tf`](fichiers/F7-S08/identite/tofu/flux.extrait-F7-S08.tf) : `navigateur-medisphere` devient « authentification » (REQUIRED : cookie ou formulaires) **puis** « refus des externes » (CONDITIONAL : `Condition - user role` `client-externe` + `Deny access`). Constat (à écrire dans `identite-federee.md` §3) : `agent.demo1` connecté sur `ghsv-agents-recette…`, puis GitLab, Argo CD, Grafana → page « accès refusé » de Keycloak.

*4. L'accès des agents* — [`components/client/`](fichiers/F7-S08/mediagenda-deploiement/components/client/) de `mediagenda/deploiement` : [`oauth2-proxy-agents.yaml`](fichiers/F7-S08/mediagenda-deploiement/components/client/oauth2-proxy-agents.yaml) (OAuth2 Proxy 7.15.5 **dans l'espace du client**, `allowed_groups = ["ghsv-agents"]`, cookie de 15 min sans rafraîchissement, `pass_authorization_header`, `api_routes` pour répondre 401 au lieu d'une redirection, route `mediagenda-agents` sur `ghsv-agents[-recette].apps…`), [`reseau.yaml`](fichiers/F7-S08/mediagenda-deploiement/components/client/reseau.yaml) (Gateway → mandataires → API, plus d'accès direct de la Gateway à l'API : la politique du chart est retirée par le component). En attendant S09, la route publique ne sert que `/pret` et `/openapi.json` ; en S09, elle passe derrière le mandataire du DPI.

*5. Cycle de vie et documentation* — [`identite-federee.md`](fichiers/F7-S08/medisphere/docs/capstone/identite-federee.md) (schéma, ce que nous recevons et refusons, cloisonnement, délais, contractuel, supervision, limites) ; [RB-372](fichiers/F7-S08/medisphere/docs/capstone/runbooks/RB-372-identite-federee-client.md). Mesure de la révocation : désactiver `agent.demo2` dans `ghsv-idp` à T, recharger toutes les minutes : refus au plus tard à T + 15 min.

**Explications**
- **Une session SSO vaut pour tout le royaume** : c'est pourquoi le refus est dans le flux du royaume (il s'exécute même quand le cookie authentifie) et pourquoi le flux des agents n'a pas de cookie (sinon une session `medisphere` survivrait à la désactivation chez le GHSV).
- **Deux refus, pas un** : « caché sur la page de connexion » n'interdit pas d'appeler `/realms/medisphere/broker/ghsv-idp/login` avec la session d'authentification ouverte pour GitLab ; au retour du courtier, Keycloak termine l'authentification **sans** rejouer le flux du navigateur (sources de la 26.8 : `IdentityBrokerService.finishBrokerAuthentication`). Le flux après courtier ferme ce chemin ; le refus de `navigateur-medisphere` ferme celui du cookie.
- **Synchronisation `FORCE`** : le mappeur de groupe est réévalué à chaque connexion ; en `IMPORT`, il ne joue qu'au premier passage, et un agent retiré du secrétariat garderait `ghsv-agents` indéfiniment.
- **Minimisation** : seul `groups` donne un droit, et seulement pour une valeur convenue ; « admin » chez le GHSV n'est rien chez nous (même réponse que M24-E32, question 3).
- **Le jeton transmis à l'API** permet au contrôle des portées de S09 de reconnaître un agent (groupe) ou le DPI (portées) avec un seul mécanisme.

**Alternatives**
- Royaume dédié aux clients (`clients` ou `ghsv`) : isolation naturelle, pas de refus à ajouter au flux de `medisphere` ; mais un émetteur de plus pour l'API et les outils. Écarté pour la v1 (structure figée, ADR-0372), à revoir au deuxième client.
- Vérifier la MFA côté courtier (revendication `acr` et niveaux d'authentification de Keycloak) : défense en profondeur ; R-16 la met à la charge du GHSV.
- Déconnexion par canal arrière (*back-channel logout*) depuis l'IdP du GHSV : révocation immédiate au lieu de 15 min ; dépend de leur IdP.
- Groupes par service (`ghsv-<service>`, EF-04, ADR-0372) : la cible ; la preuve de concept n'a qu'un groupe parce que l'API n'a pas de notion de service.

**Pièges classiques**
- Flux `navigateur-medisphere` modifié en ajoutant le refus à côté de « Cookie » : les exécutions ALTERNATIVE deviennent ignorées, plus personne ne se connecte. Essai sur une copie du royaume, retour arrière écrit (M24-E21).
- Fournisseur visible sur la page de connexion de MédiSphère : les personnels voient un bouton « GHSV », et un agent peut tenter d'autres clients.
- Compter sur l'identifiant préfixé seul pour éviter toute liaison : il écarte la collision de **nom**, pas celle d'**adresse** ; un agent dont le GHSV déclare l'adresse d'une personne de MédiSphère tomberait dans « Handle Existing Account » du premier passage (liaison après réauthentification du compte existant : pas de prise de compte, mais un compte mêlé). Durcissement : un flux de premier passage réduit à « Create User If Unique » (une collision = refus).
- Se fier à « caché sur la page de connexion » pour le cloisonnement : voir le flux après courtier.
- `store_token = true` (défaut du fournisseur OpenTofu) : les jetons du GHSV dorment dans notre base Keycloak.
- `client_session_idle_timeout = "15m"` : accepté par `tofu validate`, mais Keycloak attend des secondes.
- Ouvrir `https://ghsv-agents…/api/v1/rendez-vous` sans session : 401 (`api_routes`), pas de redirection ; l'agent passe par `/` (ou `/oauth2/start?rd=/api/v1/rendez-vous`).
- Oublier `view-identity-providers` pour `wb-checks` : le check dit KO alors que tout marche.
- Tester le refus avec une session déjà ouverte dans le même navigateur que la console d'administration : utilise une fenêtre privée par identité.

**En production chez MédiSphère**
Le client OIDC est fourni par l'IdP réel du GHSV (secret par canal séparé, rotation annuelle) ; le courtier pointe son émetteur public par le mandataire sortant ; un Keycloak de repli existe à PAR2 (`architecture.md`, ADR-0372 ; dans le lab, risque RSQ-17) ; une sonde synthétique de connexion d'agent alerte avant les secrétariats.

---

### F7-S09 — Contrats d'interface et tests de contrat

**Solution**

*1. Les écarts* — [`api/ecarts-contrat-v1.md`](fichiers/F7-S09/medisphere/docs/capstone/api/ecarts-contrat-v1.md) : dix écarts, dont **quatre bloquants** — la liste ignore en silence `praticien`, `du`, `au` (le rapprochement de R-01 serait faux), le déplacement (`PATCH`) n'existe pas, aucune authentification, nom publié dans le domaine du GHSV — ; gênants : identifiant 0 → 404 au lieu de 422, rappel d'un rendez-vous déplacé, 403 absent du contrat (question au GHSV) ; sans effet : corps d'erreur 422 de FastAPI (champs en plus permis), fuseau, identifiants `P` + six chiffres. Le rappel (`rappel.canal`, `rappel.contact`) est **déjà** conforme depuis le M27.

*2. L'API adaptée* — [`LISEZMOI-F7.md`](fichiers/F7-S09/mediagenda-api/LISEZMOI-F7.md) : correctifs **additifs** de `mediagenda/api` (filtres facultatifs de la liste, `PATCH` atomique — une instruction `UPDATE`, l'index unique de V2 rend le 409 sans fenêtre de concurrence —, `Path(ge=1)`, titre), nouveau module [`portees.py`](fichiers/F7-S09/mediagenda-api/src/mediagenda/portees.py) activé par `MEDIAGENDA_PORTEES=oui` (instances des clients seulement : 401 sans jeton, 403 sans la portée, le groupe des agents vaut les deux portées). Aucune migration. Livraison par le chemin normal jusqu'à `ghsv-recette`.

*3. Les tests de contrat* — [`tests/test_contrat_ghsv.py`](fichiers/F7-S09/mediagenda-api/tests/test_contrat_ghsv.py) : le contrat est chargé tel quel (empreinte vérifiée contre [`contrats/ghsv/ORIGINE.md`](fichiers/F7-S09/mediagenda-api/contrats/ghsv/ORIGINE.md)) ; chaque opération du contrat doit exister ; chaque réponse est validée contre les schémas du contrat (JSON Schema 2020-12, références résolues par `referencing`) ; authentification et portées testées ; et l'instance des cabinets reste inchangée. Jobs [`ci/contrat.yml`](fichiers/F7-S09/mediagenda-api/ci/contrat.yml) : `contrat:ghsv` (pytest `-m contrat`, rapport JUnit) et `contrat:compatibilite` (+ `:oasdiff`) qui compare la description générée au contrat. Sans liste d'écarts acceptés, `oasdiff breaking` (1.34) signale **9 erreurs** sur l'implémentation de référence (nom du paramètre de chemin `rdv_id` contre `id`, `detail` facultatif dans le schéma 422 de FastAPI) : elles sont listées au texte exact dans [`contrats/ghsv/oasdiff-ecarts-acceptes.txt`](fichiers/F7-S09/mediagenda-api/contrats/ghsv/oasdiff-ecarts-acceptes.txt) (`--err-ignore`) et justifiées dans `ecarts-contrat-v1.md`. Marqueur à déclarer dans `pyproject.toml` (`"contrat: tests de contrat (F7-S09)"`), dépendances de développement `jsonschema` et `pyyaml`.

```
admin@adm01:~/src/mediagenda-api$ uv run pytest -q -m contrat
....................                                                     [100%]
20 passed
```

MR de démonstration : renommer `@app.patch` en `@app.put` → `test_operation_presente[/rendez-vous/{id}-patch]` et `test_deplacement_atomique` échouent, `oasdiff` signale l'opération retirée ; MR fermée sans fusion.

*4. La publication* — [`oauth2-proxy-dpi.yaml`](fichiers/F7-S09/mediagenda-deploiement/components/client/oauth2-proxy-dpi.yaml) (jetons porteurs vérifiés par `skip_jwt_bearer_tokens` avec le vérificateur du fournisseur : émetteur `medisphere`, audience = `client_id` du mandataire `ghsv-api` — `extra_jwt_issuers` ne sert que pour un autre émetteur ; `/pret` et `/openapi.json` anonymes ; 401 sur `/api/` ; l'en-tête `Authorization` d'origine passe à l'API, `pass_authorization_header = false` ne la retire pas) et [`tofu/clients-dpi-ghsv.tf`](fichiers/F7-S09/identite/tofu/clients-dpi-ghsv.tf) (portées `rdv:lecture`, `rdv:ecriture`, client `ghsv-dpi` en *client credentials*, mappeur d'audience `ghsv-api`, jeton de 5 min). La route publique `mediagenda` mène au mandataire (component `client`).

```
admin@adm01:~$ JETON="$(curl -s -d grant_type=client_credentials -d client_id=ghsv-dpi-demo -d client_secret="$SECRET" \
    https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/token | jq -r .access_token)"
admin@adm01:~$ curl -s -H "Authorization: Bearer $JETON" "https://ghsv-recette.apps.par1.medisphere.internal/api/v1/creneaux?date=2030-01-07&praticien=P004217" | jq .fuseau
"Europe/Paris"
```

*5 et 6. Versionnage, MédiDoc* — [`api/versionnage.md`](fichiers/F7-S09/medisphere/docs/capstone/api/versionnage.md) (majeure dans le chemin, coexistence ≥ 12 mois — EF-05 —, en-têtes `Deprecation` et `Sunset`, trafic par version dans le rapport), [RB-373](fichiers/F7-S09/medisphere/docs/capstone/runbooks/RB-373-contrat-api-client.md), et la section « MédiAgenda → MédiDoc » des écarts (contrat écrit par le consommateur, vérifié dans la CI du producteur).

**Explications**
- Un test de contrat **côté producteur** répond à « est-ce que je tiens ce que j'ai promis ? » sans déployer personne ; il attrape la rupture **avant** la recette, et dit qui l'a provoquée. Il ne voit ni le réseau ni la publication : d'où la recette et la charge du DPI.
- Tenir le contrat par **ajout** (paramètres facultatifs, nouvelle opération, contrôle activé par variable) évite de forker l'API : une seule version, deux publics.
- L'API ne revérifie pas la signature du jeton : elle n'est joignable que par les mandataires (politique réseau). C'est une **confiance de zone** assumée et écrite ; la vérifier aussi dans l'API (JWKS) est une défense en profondeur possible.

**Alternatives**
- Pact (consommateur → producteur, *broker*) : le bon outil quand le consommateur écrit ses attentes ; ici le consommateur (le DPI) n'a fourni qu'un OpenAPI.
- Schemathesis (tests de propriétés générés depuis le contrat) en recette : trouve des cas limites qu'aucun test écrit n'imagine ; complément, pas remplacement.
- Validation des jetons à la Gateway (Envoy `jwt_authn`) : pas exposée par la Gateway API de Cilium dans nos versions ; le mandataire reste le point de contrôle.

**Pièges classiques**
- « Corriger » le contrat du GHSV pour faire passer un test : le test ne prouve plus rien. D'où l'empreinte.
- Un test de contrat qui ne valide que le code HTTP : un champ renommé passe.
- Ajouter `du`/`au` en paramètres **obligatoires** : rupture pour les cabinets.
- Un `PATCH` en deux temps (lecture, puis suppression et création) : non atomique, nouvel identifiant, et un 409 qui laisse le rendez-vous supprimé.
- Le job de contrat en `allow_failure: true` « le temps de stabiliser » : il ne refuse plus rien.

**En production chez MédiSphère**
Le contrat du client est versionné dans `ghsv/contrat-api` (référence) et recopié dans chaque producteur ; un tableau suit le trafic par version d'API ; la recette du client rejoue chaque nuit le parcours du DPI (k6, `testid=contrat-ghsv`).

---

### F7-S10 — Des engagements de service mesurés

**Solution**

*1. SLO* — [`slo/ghsv-disponibilite-sonde.yaml`](fichiers/F7-S10/observabilite/slo/ghsv-disponibilite-sonde.yaml) (indicateur contractuel : `bool_gauge` sur `probe_success{groupe=~"client-ghsv.*"}`), [`ghsv-disponibilite.yaml`](fichiers/F7-S10/observabilite/slo/ghsv-disponibilite.yaml) (5xx de l'API), [`ghsv-latence.yaml`](fichiers/F7-S10/observabilite/slo/ghsv-latence.yaml) (seau `le="0.3"`, rendu possible par le correctif [`seaux-latence.extrait-F7-S10.py`](fichiers/F7-S10/mediagenda-api/seaux-latence.extrait-F7-S10.py) : l'histogramme n'avait pas de seau 0,3 s, le M21 mesurait à 250 ms). Sondes de `mon01` : [`supervision_temoin.yml.extrait-F7-S10`](fichiers/F7-S10/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml.extrait-F7-S10) — `/pret` par la chaîne complète **et** une opération authentifiée du contrat (module `http` de blackbox avec un bloc `oauth2` *client credentials*, client `ghsv-sonde`, portée `rdv:lecture`).

*2. Engagements* — [`engagements.md`](fichiers/F7-S10/medisphere/docs/capstone/engagements.md) : chaque engagement, sa requête, sa source, ce qu'il ne voit pas ; glissant (Pyrra, pilotage) contre calendaire (contrat, rapport) ; maintenances : liste versionnée, conformité vérifiée par l'outil.

*3. Rapport* — [`ms-rapport-client`](fichiers/F7-S10/outils/bin/ms-rapport-client) et [`clients/ghsv.yaml`](fichiers/F7-S10/outils/clients/ghsv.yaml) : mois de Paris, intervalles **privés des maintenances conformes** (annonce ≥ 5 jours ouvrés, 22 h-6 h, cumul ≤ 4 h ; sinon l'indisponibilité compte), disponibilité = échantillons de sonde réussis / échantillons, plus 5xx, latence, alertes critiques, capacité (rendez-vous créés, pointe de req/s, volume de la base, CPU et mémoire contre quota), et les requêtes en annexe. Pipeline [`ci/rapport-clients.yml`](fichiers/F7-S10/outils/ci/rapport-clients.yml) planifié le 1er à 06:15 (Paris), MR automatique sur `plateforme/medisphere`. [RB-374](fichiers/F7-S10/medisphere/docs/capstone/runbooks/RB-374-rapport-mensuel-client.md).

```
admin@adm01:~/src/outils$ bin/ms-rapport-client --partiel ghsv > ~/medisphere/docs/capstone/rapports/ghsv-$(date +%Y-%m).md
```

*4. PRA* — [`pra-ghsv.md`](fichiers/F7-S10/medisphere/docs/capstone/pra-ghsv.md) : ce qui est répliqué et comment ; overlay de PAR2 [`ghsv-prod-par2`](fichiers/F7-S10/mediagenda-deploiement/overlays/clients/ghsv-prod-par2/kustomization.yaml) (réplique [`mediagenda-db-par2`](fichiers/F7-S10/mediagenda-deploiement/overlays/clients/ghsv-prod-par2/mediagenda-db-par2.yaml) en topologie distribuée depuis `cnpg-ghsv` de `s3-02`, tout le reste à 0, témoin suspendu) ; côté PAR1, la grappe de `ghsv-prod` reçoit le bloc symétrique :

```yaml
# overlays/clients/ghsv-prod : correctif de la grappe (topologie distribuée, F5-S06)
spec:
  replica:
    self: mediagenda-db-prod
    primary: mediagenda-db-prod
    source: mediagenda-db-par2
  externalClusters:
    - {name: mediagenda-db-prod, plugin: {name: barman-cloud.cloudnative-pg.io, parameters: {barmanObjectName: cnpg-ghsv, serverName: mediagenda-db-prod}}}
    - {name: mediagenda-db-par2, plugin: {name: barman-cloud.cloudnative-pg.io, parameters: {barmanObjectName: cnpg-ghsv-par2, serverName: mediagenda-db-par2}}}
```

avec, dans `overlays/clients/ghsv-prod`, un ObjectStore `cnpg-ghsv-par2` **en lecture** (compartiment `cnpg-ghsv-par2` de `s3-02`, sans `retentionPolicy`), comme `objectstore-par2.yaml` de MédiAgenda (F5-S06). À PAR2, la réplique lit la copie de l'archive de PAR1 par l'ObjectStore `cnpg-ghsv-par1` et archive dans **son** compartiment `cnpg-ghsv-par2` ([`sauvegarde-par2.yaml`](fichiers/F7-S10/mediagenda-deploiement/overlays/clients/ghsv-prod-par2/sauvegarde-par2.yaml)), classe de stockage `local-path` : mêmes règles que `mediagenda-db-par2` du F5. Compartiment `cnpg-ghsv-par2` et identité `cnpg-ghsv-par2` à ajouter à `s3-02` (rôle `seaweedfs`, F5-S04), `cnpg-ghsv` à la liste de `filer.sync`.

Témoin de RPO [`temoin-rpo-client`](fichiers/F7-S10/mediagenda-deploiement/components/temoin-rpo-client/cronjob.yaml) (écriture SQL directe : l'API exige un jeton) ; nom `ghsv.medisphere.internal` (CNAME, TTL 60 s, même mécanisme que les noms globaux du F5) ; essai de reprise **isolé** (grappe restaurée à part dans `ghsv-essai-reprise` de `k8s-par2`, API à 1 réplica, mesure, suppression) : RPO = dernier témoin PAR1 − dernier témoin restauré.

**Explications**
- **La sonde fait foi** parce qu'elle voit ce que voit le client, y compris ce qui n'atteint jamais l'API ; le compteur de l'application complète (toutes les requêtes réelles) et explique.
- **Calendaire et maintenances** : un calcul exact se fait sur des échantillons, pas en retranchant des minutes : on n'additionne que les échantillons hors fenêtres conformes. Requête instantanée évaluée à la fin de chaque intervalle, fenêtre = durée de l'intervalle, données brutes de Thanos (30 jours comptés depuis le calcul : un mois de 31 jours n'y tient plus entièrement le 1er à 06:15 ; d'où la rétention brute portée à 35 jours, écrite dans `engagements.md`).
- **Essai isolé** : il mesure ce que mesurerait une reprise (archives disponibles à PAR2, durée de restauration, retard) sans toucher à la réplique continue ni à PAR1.

**Alternatives**
- Sloth plutôt que Pyrra : mêmes fenêtres glissantes, même limite calendaire.
- Règles de Pyrra évaluées par **Thanos Ruler** (ou Pyrra branché sur Thanos Query pour son interface) : sans cela, les règles générées sont évaluées par Prometheus sur ses **15 jours** locaux, et la fenêtre de 30 j des alertes de long terme en voit la moitié.
- Mesure au point d'entrée (métriques de l'Envoy de la Gateway) pour ENF-05 : plus fidèle au contrat ; à retenir si l'écart client/serveur dépasse 20 ms.
- Bascule réelle du seul locataire GHSV à PAR2 : la vraie preuve d'ENF-06 ; coûteuse (jetons, retour), à faire lors du test annuel (ENF-08), pas dans ce scénario.

**Pièges classiques**
- `avg_over_time` sur la série **fédérée** sans regarder son pas : la fédération ramène un échantillon par intervalle de collecte, pas par sonde ; compter des échantillons, c'est ce que fait l'outil, et c'est cohérent tant que le pas est constant.
- Un SLO à 30 jours glissants présenté comme « la disponibilité du mois ».
- Les seuils de latence en nombre dans la configuration : `1.0` devient `1` et ne correspond plus à `le="1.0"`.
- Promouvoir la réplique continue pour « tester » : la topologie distribuée exige alors le retour par jeton, et PAR1 n'est plus primaire.
- Le témoin qui passe par l'API : il mesure l'API et ses jetons, plus la réplication.

**En production chez MédiSphère**
La sonde du GHSV (R-09) est ajoutée au rapport à côté de la nôtre ; le rapport est signé et collecté par `ms-preuves` ; le test annuel du PRA se fait en présence du GHSV avec bascule réelle de son locataire.

---

### F7-S11 — Panne : la démonstration sous incidents

**Démarche de diagnostic**

*Symptômes → hypothèses.* Pendant une démonstration sous charge, trois questions avant tout geste : **qui** voit l'incident (patient/DPI sur le nom public, agents sur le nom des agents, ou personne encore), **depuis quand** (sonde à 30 s, charge k6 à 5 s, `continuite:en_erreur` du F4), **à quelle couche** (Gateway et route, mandataire, API, base, cache, identité). Le meneur injecte deux ou trois incidents, l'un après la réparation du précédent ; les suivants arrivent sans prévenir : seuls tes instruments et la boîte `support@` te les signalent. La démonstration continue : on répare par le chemin normal (Git et Argo CD, OpenTofu), pas par un contournement.

Séquences : variante 1 *route → cache → identité* ; 2 *réseau → mandataire → identité* ; 3 *cache → route → mandataire* ; 4 *identité → réseau → cache*.

#### Incident « réseau » — l'API ne joint plus sa base

1. Symptôme : tout le nom public en 503, la sonde `/pret` rouge, la charge en erreur ; les pods de l'API `0/1` prêts.
   ```
   admin@adm01:~$ kubectl -n ghsv-prod get pods -l app.kubernetes.io/component=api
   admin@adm01:~$ kubectl -n ghsv-prod logs deploy/mediagenda --tail=20 | grep -i postgres
   ```
   `/pret` : `{"statut":"pas-pret","postgresql":"indisponible","valkey":"ok"}`. La base, elle, est saine (`kubectl cnpg status mediagenda-db -n ghsv-prod`).
2. Entre les deux, le réseau : les politiques de l'espace et les verdicts de Cilium.
   ```
   admin@adm01:~$ kubectl -n ghsv-prod get cnp,netpol
   admin@adm01:~$ hubble observe -n ghsv-prod --verdict DROPPED --last 20
   ```
   `protection-donnees-ghsv` (étiquette `auteur: lucas.martin`, annotation « durcissement… à valider ») avec un `egressDeny` vers `cnpg.io/cluster=mediagenda-db` sur 5432 ; Hubble : `DROPPED (Policy denied by denylist)`. Les pods de l'API sont récents : une nouvelle politique ne coupe pas toujours les connexions déjà établies de la réserve, « Lucas » a supprimé les pods pour la « prendre en compte » (le script le fait si `/pret` reste vert).
3. **Cause** : une politique de refus ajoutée en direct, absente de Git (Argo CD ne la montre pas : un objet ajouté hors de son suivi n'apparaît pas dans le diff).
4. **Correctif** : supprimer la politique (`kubectl -n ghsv-prod delete cnp protection-donnees-ghsv`), vérifier `/pret`. Si un durcissement est voulu, il passe par une MR dans le component `client`.
5. **Prévention** : politique d'admission qui refuse les `CiliumNetworkPolicy` des espaces applicatifs non créées par Argo CD (gestionnaire `argocd-controller`), alerte « pods de l'API non prêts > 2 min ».

#### Incident « route » — le DPI reçoit des 500, les agents travaillent

1. Le nom public seul est touché (le nom des agents répond) : la couche commune (API, base) va bien.
2. La route et son état :
   ```
   admin@adm01:~$ kubectl -n ghsv-prod get httproute mediagenda -o yaml | yq '.spec.rules[0].backendRefs, .status.parents[].conditions'
   admin@adm01:~$ argocd app diff ghsv-prod
   ```
   Backend `oauth2-proxy-dpi:8080`, condition `ResolvedRefs=False` (`BackendNotFound` ou port inexistant) ; Argo CD : `OutOfSync`, diff sur le port.
3. **Cause** : modification en direct d'un objet géré ; en production, pas de `selfHeal`, la dérive reste.
4. **Correctif** : synchroniser l'Application `ghsv-prod` (dans la fenêtre, ou dérogation d'incident) ; le diff montre exactement ce qui revient.
5. **Prévention** : alerte « Application de production `OutOfSync` depuis 15 min » ; droits d'écriture directe sur les espaces des clients retirés aux personnes (lecture seule, sauf bris de glace).

#### Incident « cache » — tout tombe alors que la base va bien

1. Nom public et agents en 503 ; `/pret` : `"valkey":"indisponible"` ; base saine.
2. ```
   admin@adm01:~$ kubectl -n ghsv-prod get sts,pvc -l app.kubernetes.io/name=valkey
   ```
   `valkey` à `0/0` réplica, PVC présent (rien de perdu).
3. **Cause** : le StatefulSet a été réduit à 0 en direct ; et surtout, **`/pret` exige Valkey** : un cache dont la perte devrait dégrader (M27 : MédiAgenda sait servir depuis la base) sort l'API du Service. Le défaut de conception compte plus que le geste.
4. **Correctif** : synchroniser l'Application (réplicas de Git), attendre Valkey prêt ; vérifier la sonde.
5. **Prévention** : correctif de `mediagenda/api` (`/pret` ne dépend que de PostgreSQL ; Valkey en état dégradé dans `/sante` détaillé ou une métrique), alerte sur `mediagenda_cache_total{resultat="erreur"}`.

#### Incident « identité » — 403 pour les secrétaires qui se reconnectent

1. Seuls les agents qui **se reconnectent** sont refusés (les sessions en cours tiennent jusqu'à 15 min) ; page « 403 Forbidden » d'OAuth2 Proxy **après** la MFA : l'authentification réussit, l'autorisation échoue.
2. Journaux du mandataire (`kubectl -n ghsv-prod logs deploy/oauth2-proxy-agents`) : utilisateur `ghsv.agent.demo1`, groupes vides ou sans `ghsv-agents`. Événements Keycloak (royaume `medisphere`) : connexion réussie par le courtier. Le compte fédéré n'a plus le groupe. Le mappeur :
   ```
   admin@adm01:~/src/identite/tofu$ tofu plan    # écart sur keycloak_custom_identity_provider_mapper.agents
   ```
   La revendication attendue est `secretariat-medicale` au lieu de `secretariat-medical`.
3. **Cause** : modification hors code du mappeur ; avec la synchronisation `FORCE`, chaque reconnexion retire le groupe.
4. **Correctif** : `tofu apply` (le code fait foi) ; se reconnecter : groupe rendu.
5. **Prévention** : `tofu plan` planifié sur `plateforme/identite` qui alerte sur toute dérive ; administration du royaume `medisphere` réservée au compte d'OpenTofu (les personnes en lecture).

#### Incident « mandataire » — le DPI reçoit des 401 avec un jeton tout neuf

1. La sonde `/pret` reste **verte** (route anonyme) mais la sonde de l'opération authentifiée est rouge, la charge `demo-ghsv` en 401 ; les agents ne sont pas touchés.
2. Le jeton est-il valide ? Décoder sa charge (`jq -R 'split(".")[1] | @base64d | fromjson'`) : `aud` contient `ghsv-api`, `exp` dans le futur. Le mandataire ne regarde même pas le jeton : ses journaux montrent des 401 sans session (aucune ligne de jeton porteur refusé), et au démarrage il n'annonce plus « Skipping JWT tokens from configured OIDC issuer ». Configuration :
   ```
   admin@adm01:~$ kubectl -n ghsv-prod get cm oauth2-proxy-dpi -o jsonpath='{.data.oauth2_proxy\.cfg}' | grep -n jwt
   admin@adm01:~$ argocd app diff ghsv-prod
   ```
   `skip_jwt_bearer_tokens = false` : les jetons porteurs sont ignorés, `/api/` répond 401 (`api_routes`) faute de session.
3. **Cause** : ConfigMap modifiée en direct et pods redémarrés (`rollout restart` : l'annotation `kubectl.kubernetes.io/restartedAt` du modèle de pod n'est pas dans Git ; selon le mode de comparaison de ton Argo CD, elle apparaît ou non dans le diff).
4. **Correctif** : synchroniser l'Application, redémarrer le mandataire (ConfigMap montée : relue au redémarrage).
5. **Prévention** : ConfigMap générée avec suffixe d'empreinte (un changement crée un nouvel objet et un nouveau déploiement, visibles dans Git) ; la sonde authentifiée existe justement pour voir ce que `/pret` ne voit pas.

**Le compte rendu** — [`journees-de-jeu/AAAA-MM-JJ-demonstration-ghsv.md`](fichiers/F7-S11/medisphere/docs/qualite/journees-de-jeu/AAAA-MM-JJ-demonstration-ghsv.md) : chronologie, vue par utilisateur, délais de détection, secondes d'indisponibilité (requête de la sonde), budget consommé, effet sur le rapport, actions. Charge : [`demo-ghsv.js`](fichiers/F7-S11/resilience/demonstration/demo-ghsv.js) et [`testrun.yaml`](fichiers/F7-S11/resilience/demonstration/testrun.yaml) (client `ghsv-dpi-demo`, jamais le secret remis au GHSV).

**Explications**
Un incident « vu par un client » se diagnostique par la **différence** entre ce que voient les différents utilisateurs et instruments : nom public contre nom des agents, `/pret` contre opération authentifiée, sessions en cours contre reconnexions. Trois des cinq incidents sont des modifications **en direct** d'objets gérés : la production d'un client sans `selfHeal` garde toute dérive, et seul le diff (Argo CD, `tofu plan`) la montre. Les deux autres révèlent un défaut de conception (cache rendu critique) et un angle mort de la sonde (`/pret` anonyme).

**Pièges classiques**
- Redémarrer l'API « pour voir » : l'incident réseau ou cache revient à l'identique, et on perd du temps sous les yeux du client.
- Chercher l'incident d'identité dans Keycloak seul : l'authentification réussit, c'est l'autorisation (groupe) qui échoue.
- Conclure « tout va bien » sur la foi de `/pret` pendant l'incident du mandataire.
- Oublier que la synchronisation de la production se fait dans la fenêtre : en incident, la dérogation est tracée.
- Lancer `--annuler` en pleine démonstration pour « faire propre » : il arrête aussi les incidents à venir.

**En production chez MédiSphère**
Les journées de jeu sur les locataires des clients se font sur la recette du client, jamais sur sa production (ici, production de démonstration aux données fictives) ; les actions alimentent le registre des risques et le comité de suivi.

---

## Points non testés en conditions réelles

Signale tes retours : ils corrigent le workbook.

- **Fournisseur OpenTofu `keycloak/keycloak` 5.10** : configurations validées par `tofu validate` à la relecture (le type de ressource du mappeur générique est `keycloak_custom_identity_provider_mapper`) ; clés de Keycloak lues dans ses sources 26.8.1 (`pkceEnabled`, `pkceMethod`, `clientAuthMethod`, `claims` au format `[{"key":…,"value":…}]`, `are.claim.values.regex`, `group` en chemin `/ghsv-agents`, `client_scope`/`negate` de « Condition - client scope ») ; **non joué** contre un Keycloak : `apply` complet, plan vide au second passage (le fournisseur peut relire `extra_config` autrement qu'écrit).
- **Keycloak 26.8** (sources lues) : « Advanced Claim to Group » accepte une revendication **tableau** (une valeur suffit) et, en `FORCE`, retire le groupe quand elle ne correspond plus ; le retour du courtier ne rejoue pas le flux du navigateur (d'où le flux après courtier). **À essayer sur une copie du royaume** : le flux restructuré de `navigateur-medisphere` (REQUIRED puis CONDITIONAL au premier niveau) et le flux `apres-courtier-ghsv` (refus de GitLab par l'URL directe du courtier, accès de `ghsv-agents`).
- **OAuth2 Proxy 7.15.5** (sources lues) : `skip_auth_routes` au format `METHODE=regex`, `api_routes`, `skip_jwt_bearer_tokens` qui essaie d'abord le vérificateur du fournisseur (audience = `client_id`), `user_id_claim` (ancien nom de `oidc_email_claim`, encore accepté), en-tête `Authorization` d'origine transmis quand `pass_authorization_header = false`. **Non joué** : jeton de compte de service sans adresse réelle accepté de bout en bout.
- **OpenBao 2.7** : rôles de jeton avec `allowed_policies` permettant une politique que l'appelant n'a pas (comportement documenté de Vault, repris par OpenBao), `-policy` à préciser à la création ; `token_num_uses = 10` suffisant pour une relecture (chaque appel `bao` compte).
- **CloudNativePG 1.30** : topologie distribuée de la grappe du client (blocs `replica.self/primary/source` et `externalClusters` des deux côtés) recopiée du principe du F5-S06 ; `archive_timeout` dans `postgresql.parameters` ; libellé de `status.phase` lu par le check.
- **Pyrra 0.10** : champs `bool_gauge`, `latency`, `alerting.severities` présents dans le CRD (sources 0.10.2) ; **non joué** : `bool_gauge` sur une série fédérée ; les règles générées sont évaluées par Prometheus sur 15 jours locaux (voir Alternatives).
- **blackbox_exporter 0.29.1** : module avec bloc `oauth2` validé par `--config.check` ; **non joué** : obtention réelle du jeton, boucle ajoutée au gabarit `blackbox.yml.j2` du rôle (la variable `supervision_temoin_modules_supplementaires` est nouvelle).
- **Ceph RGW** : SSE-KMS adossé au moteur `transit` d'OpenBao (cible de `ghsv-sauvegardes`) : non essayé.
- **oasdiff 1.34.1** : options et liste d'écarts acceptés vérifiées hors du lab ; une autre version peut formuler ses messages autrement (le fichier `--err-ignore` compare le texte) : relance le job et ajuste le fichier, jamais le contrat.
- **Panne F7-S11** : injection et effets jamais joués sur un lab réel ; vérifié hors du lab : refus si l'espace ou le fournisseur n'est pas `ghsv-…`, `--annuler` sans état, arrêt du meneur (drapeau, groupe de processus entier, attente de sa fin : aucun processus restant), expressions `jq` sur des exemples. Le meneur survit à la fermeture du terminal (`trap '' HUP`, groupe de processus à part) mais pas à un redémarrage d'`adm01` (`--annuler` défait quand même ce qui a été injecté). À confirmer : coupure effective des connexions établies par la politique de refus de Cilium, délai d'effet du mandataire, envoi des courriels par `curl` en SMTP avec STARTTLS vers Mailpit.
- **Overlays** : listes de components et chemins de correctifs (`env/0`, `containers/0`) à confronter à l'état réel de **ton** `mediagenda/deploiement` (M17 à M28, F4) ; nom du component `racine-medisphere` ; cibles des correctifs de route de `ghsv-prod-par2` (reprises de `overlays/prod-par2` du F5).
- Mesures (RPO, durées de reprise, durée d'export) : à relever sur ton lab ; les valeurs du corrigé sont des emplacements `<…>`.
