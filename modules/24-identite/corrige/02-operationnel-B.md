# Module 24 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les solutions complètes sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un extrait des projets : `identite/` = `plateforme/identite`, `ansible/` = `plateforme/ansible`, `infra/` = `plateforme/infra`, `k8s/` = `plateforme/k8s`, `observabilite/` = `plateforme/observabilite`, `gitops/` = `plateforme/gitops`, `medisphere/` = la documentation, `git01/` et `nbx01/` = fichiers posés ou lancés sur ces hôtes. On **superpose** les dossiers dans l'ordre des exercices, par-dessus ceux du palier 1 (`M24-E08` pour `plateforme/identite`). Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête).

**Ce qui a été vérifié à la rédaction.**
- *Keycloak* : les neuf clients du palier (`tofu/clients-*.tf` d'E11 à E16, avec `clients-communs.tf`) appliqués par OpenTofu 1.13.2 et le fournisseur `keycloak/keycloak` 5.10.0 contre un **Keycloak 26.7.5 réel** (royaume `medisphere` d'E08, portée `groupes`, client `wb-checks`) : création, puis **plan vide** ; représentations relues par l'API d'administration avec le compte `wb-checks` (`publicClient`, flux, `redirectUris`, `attributes["pkce.code.challenge.method"]`, `fullScopeAllowed`, portées par défaut). Ce test a montré qu'un client créé dans le **même** apply que l'ajout de `groupes` aux portées par défaut du royaume n'hérite pas de `groupes` : d'où `keycloak_openid_client_default_scopes` sur chaque client. Le jeton `client_credentials` de `wb-checks` porte `aud = [realm-management, account]` et `azp = wb-checks` : c'est lui que le check d'E16 présente au serveur d'API.
- *Contrôles* (`checks/_m24-operationnel.sh`, `check-E11.sh` à `check-E16.sh`) : exécutés contre ce Keycloak (contrôles des clients au vert, puis au rouge après retrait de PKCE, d'une redirection ou de la portée `groupes`) ; filtres `jq` des contrôles d'Argo CD, des pods de kube-apiserver, de la ClusterRole et des politiques Cilium rejoués sur des objets construits à partir des fichiers du corrigé ; filtres `pveum`/`pvesh` rejoués sur des sorties JSON au format de la documentation ; expressions régulières rejouées sur les fichiers de solution.
- *Authentification structurée* : le fichier rendu par le rôle `k8s_authentification` chargé par un **kube-apiserver 1.36.5 réel** (`--authentication-config`) : accepté ; une expression CEL fausse et un champ inconnu sont refusés au démarrage ; `--authentication-config` avec `--oidc-issuer-url` : « authentication-config file and oidc-* flags are mutually exclusive ». `outils/kubeconfig-oidc.sh` exécuté avec `kubectl` 1.36.5 (contexte et `exec` attendus, `interactiveMode: Never`).
- *OpenTofu* : `tofu validate` et `tofu fmt -check` sur `acces-proxmox/` (`bpg/proxmox` 0.116.1 : `proxmox_realm_openid` et `client_key_wo`, `proxmox_acl`), `registre/` (`goharbor/harbor` 3.12.5 : `harbor_config_auth` et `oidc_client_secret_wo`, `harbor_project_member_group`) et `observabilite-grafana/` (`grafana/grafana` 4.50.0 : `data "grafana_users"`, `ignore_changes` sur l'organisation).
- *Outils* : `ranger-secret-client.sh` exécuté contre un Keycloak simulé et un vrai `ansible-vault` (ansible-core 2.21.5) : fichier recréé chiffré sous l'identité `critique`, `--verifier` au vert puis au rouge ; `synchro-gitlab.py` exécuté contre une API GitLab simulée (aperçu, `--verifier`, `--appliquer` : ajouts, changement de niveau, retrait, Owner laissé, compte absent signalé, jeton refusé → code 1).
- *Sources amont relues* : Harbor 2.15.0 (`authModeCanBeModified` ne compte que les utilisateurs non supprimés hors administrateur ; suppression = marquage et renommage ; PKCE dans `controllers/oidc.go` ; `storage_service.ca_bundle` copié dans `/harbor_cust_cert`), Argo CD 3.5.5 (`OAuth2UsePKCE` ⇔ `enablePKCEAuthentication`, PKCE de la CLI, champs d'`oidc.config`), crate `proxmox-openid` (PKCE S256), `social-auth-core` 4.8.7 de NetBox 4.6.9 (`OpenIdConnectAuth`, `USE_PKCE`, `associate_by_email`), modèles NetBox 4.6.9 du script de groupes, pages `pveum` et `proxmox-backup-manager`, documentation de GitLab (OIDC), de Grafana (`generic_oauth`) et de kubelogin 1.36.4.
- *Scripts* : `shellcheck -x` et `bash -n` sur tous les scripts (checks, outils, module `secrets-k8s.d/identite.sh`) ; `python3 -m py_compile` ; YAML analysés.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- **GitLab 19.5** : connexion OmniAuth réelle (rattachement par `omniauth_auto_link_user`, `uid_field: sub`, `pkce: true`) ; rôle Owner du compte `svc-synchro-identite` (la page *Roles and permissions* réserve la gestion des membres d'un groupe aux Owners) et refus d'un `PUT` qui vise un autre Owner.
- **Grafana 13.2** : `org_mapping` avec un nom d'organisation accentué (« Sécurité ») et le joker `*:1:Viewer` ; comportement de l'organisation principale quand `org_mapping` est défini (la documentation ne le précise pas) : si une personne perd l'organisation principale, remplace le nom par l'identifiant de l'organisation (`organisation_securite_id`, sortie de l'état) et vérifie ; rendu de `envFromSecret` et `extraConfigmapMounts` par le sous-chart 14.x.
- **Argo CD** : `rootCA` dans `oidc.config` rendu par le gabarit Helmfile (indentation), résolution de `$argocd-oidc:clientSecret`, `logoutURL`.
- **Harbor** : la confiance par `storage_service.ca_bundle` (mécanisme lu dans `prepare`, pas essayé) ; l'appel `PUT /configurations` par le fournisseur avec `oidc_client_secret_wo` ; le secret CLI d'un utilisateur OIDC pour `docker login`.
- **Proxmox VE et PBS** : options exactes du royaume sur **ta** version (`pveum realm add --help`), nom des groupes suffixés, affichage de la clé `groups-overwrite` dans `pvesh get /access/domains/medisphere` ; chemin de l'API de PBS (`/api2/json/config/access/openid`) et chemin d'ACL `/access/domains` pour le jeton temporaire ; résolution de `sso.par1.medisphere.internal` depuis `pve01` et `pbs01` (hors du DNS du lab selon ta configuration du M00).
- **NetBox 4.6** : connexion réelle par `python-social-auth` (pipeline avec `associate_by_email`, PKCE, `REQUESTS_CA_BUNDLE` hérité par gunicorn).
- **Kubernetes** : reconfiguration réelle des trois serveurs d'API par `reconfigurer-apiserver.sh` (le fichier, lui, a été chargé par un vrai kube-apiserver 1.36.5) ; flux `K8S_CP` → VIP 443 ; kubelogin réel avec le tunnel SSH ; message exact du journal pour un jeton refusé.

**Où lancer les commandes.** `admin@adm01:~/src/identite$`, `~/src/ansible$`, `~/src/infra$`, `~/src/k8s$`, `~/src/observabilite$`, `~/src/gitops$` dans les copies des projets ; `admin@git01:~$`, `root@pve01:~#`, `root@pbs01:~#`, `admin@nbx01:~$`, `admin@k8s-cp01:~$` sur les hôtes ; ton navigateur sur ton poste (VPN). Toute modification de `plateforme/identite` passe par une MR, le plan du pipeline et le job manuel `tofu:apply`.

---

### M24-E10 — Le modèle d'autorisation : groupes, rôles et services

**Solution**

Document modèle : [`modele-autorisation.md`](fichiers/M24-E10/medisphere/docs/securite/identite/modele-autorisation.md). Grille d'auto-évaluation (2 points par ligne, 16 au total) :

| Critère | Attendu |
|---|---|
| Principes | cinq au plus, chacun avec une conséquence vérifiable (« aucun nom de personne dans une politique ») |
| Matrice | sept groupes × douze services, rôle **natif** et portée dans chaque case ; aucune personne citée |
| Écriture en production | justifiée ligne par ligne : seuls `plateforme-admins` écrivent partout ; `mediagenda` livre dev et recette, lit la production |
| Mécanisme par service | revendication `groups` lue par le service, script, ou affectation manuelle, et le fichier où c'est écrit |
| Limites des éditions | GitLab CE (groupes OIDC Premium), Grafana OSS (*team sync* Enterprise), PBS et NetBox (pas de groupes par OIDC), chacune avec son contournement |
| Séparation des tâches | au moins trois paires, chacune avec son **mécanisme** (règle d'approbation, comptes distincts, journal hors d'atteinte) |
| Comptes locaux | tous les bris de glace et tous les comptes d'automatisation : raison, propriétaire, protection |
| Lucas | une ligne lisible : ce qu'il lit, ce qu'il propose, ce qu'il ne fait jamais seul |

Les choix structurants du modèle, repris par les exercices suivants :
- **Trois niveaux** répétés partout : administrer (`plateforme-admins`), exploiter et proposer (`plateforme`), lire (`support`, `securite`). Les équipes applicatives ont l'écriture **dans leur périmètre hors production**. `direction` n'écrit nulle part.
- **Lucas** (`plateforme`) n'a d'écriture que là où elle passe par une relecture (MR sur `main`, `wb-essais`) : en GitLab, Developer de `plateforme` (il pousse des branches, ouvre des MR, ne fusionne pas sur une branche protégée réservée aux Maintainers) ; dans Argo CD, lecture ; dans Proxmox, auditeur ; sur les VMs, sudo de consultation.
- **Ce qui reste local est listé**, avec sa protection : c'est ce que la revue d'accès (E30) comparera, et ce que le bris de glace (E28) éprouvera.

**Explications**

Un modèle d'autorisation vaut par ce qu'il **interdit** d'écrire : si la règle est « aucune personne dans une politique », un relecteur de MR la vérifie en une seconde, et la revue d'accès peut la contrôler par script. Partir des **rôles natifs** évite de fabriquer des rôles qu'il faudrait maintenir dans dix outils ; on n'en fabrique que lorsque le rôle natif est trop large (lecture **sans** journaux dans Argo CD, lecture **sans** Secrets dans Kubernetes). La matrice rend visibles les écarts : PBS par personne, NetBox à la main, GitLab par script. Un écart écrit et compensé (revue d'accès) est acceptable ; un écart découvert par l'auditeur ne l'est pas.

**Alternatives**

- *Rôles fonctionnels dans Keycloak* (rôles de royaume ou de client) au lieu des groupes de l'annuaire : plus fins (un rôle `argocd-sync` distinct de l'appartenance d'équipe), mais deux sources (l'annuaire pour les équipes, Keycloak pour les rôles) et un royaume qui grossit. Les groupes suffisent à 400 personnes et sept équipes.
- *ABAC* (attributs : équipe **et** environnement **et** astreinte en cours) : réservé aux décisions sensibles (accès temporaire à la production pendant une astreinte), avec un outil d'accès juste-à-temps ; hors périmètre du module.
- *Un groupe par service et par rôle* (`argocd-admins`, `grafana-editors`…) : très explicite, mais la combinatoire explose et l'arrivée d'une personne demande dix appartenances.

**Pièges classiques**

- Une matrice qui cite des personnes (« Karim : admin ») : elle sera fausse au premier départ.
- Oublier les comptes non humains : ce sont eux que l'auditeur trouve en premier (robots, jetons sans expiration).
- `support` en Editor partout « pour dépanner » : l'astreinte niveau 1 lit et escalade ; l'écriture passe par `plateforme`.
- Confondre authentification et autorisation : « Keycloak donne les droits ». Keycloak transmet les groupes ; chaque service décide.
- Laisser `direction` sans aucun accès : Claire doit pouvoir lire la revue d'accès et les tableaux de synthèse (Viewer).

**En production chez MédiSphère**

Le document est relu à chaque nouveau service et chaque trimestre avec la revue d'accès ; chaque ligne de la matrice a un test automatique (E30 compare ce document à la réalité de chaque service) ; les écarts acceptés ont une date de revue ; les MR qui touchent un droit exigent l'approbation de la RSSI (règle d'approbation en Premium, revue tenue à la main en CE).

---

### M24-E11 — SSO de GitLab

**Solution**

Fichiers : [`clients-communs.tf`](fichiers/M24-E11/identite/tofu/clients-communs.tf) et [`clients-gitlab.tf`](fichiers/M24-E11/identite/tofu/clients-gitlab.tf), [`ranger-secret-client.sh`](fichiers/M24-E11/identite/outils/ranger-secret-client.sh), [`synchro-gitlab.py`](fichiers/M24-E11/identite/outils/synchro-gitlab.py), [`synchro-gitlab.yml`](fichiers/M24-E11/identite/outils/synchro-gitlab.yml), [`pyproject.toml`](fichiers/M24-E11/identite/pyproject.toml), [`.gitlab-ci.yml.extrait`](fichiers/M24-E11/identite/.gitlab-ci.yml.extrait), [`gitlab.rb.extrait`](fichiers/M24-E11/git01/gitlab.rb.extrait), [structure du Vault](fichiers/M24-E11/ansible/secrets/identite.yml.exemple).

*A. Préparer.* Notes attendues : `discovery: true` lit la configuration publiée par l'émetteur (points de terminaison, JWKS) ; `uid_field` désigne la revendication qui identifie **durablement** la personne côté GitLab (table des identités) : `sub` (identifiant interne de Keycloak, stable grâce à `ipaUniqueID`), jamais `preferred_username` ni `email`, qu'un renommage changerait (GitLab créerait alors une **nouvelle** identité) ; `pkce: true` ajoute le défi S256 ; `omniauth_allow_single_sign_on` autorise la création d'un compte à la première connexion ; `omniauth_block_auto_created_users: false` ne le met pas en attente d'approbation ; `omniauth_auto_link_user` rattache l'identité OIDC à un compte **existant de même adresse**. Contrôle de confiance :

```
admin@git01:~$ sudo ls /etc/gitlab/trusted-certs/
medisphere-root-ca.crt
admin@git01:~$ sudo /opt/gitlab/embedded/bin/curl -s -o /dev/null -w '%{http_code}\n' \
>   https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration
200
```

*B. Le client et son secret.* Toutes les règles communes sont en tête de `clients-gitlab.tf` ; `clients-communs.tf` déclare la liste des portées par défaut des clients (dont `groupes`), appliquée à chaque client par `keycloak_openid_client_default_scopes`. MR, plan (`2 to add`), apply. Puis :

```
admin@adm01:~/src/identite$ outils/ranger-secret-client.sh gitlab
[OK] secret de gitlab rangé dans /home/admin/src/ansible/secrets/identite.yml (clé keycloak_secrets_clients.gitlab). MR dans plateforme/ansible.
admin@adm01:~/src/identite$ outils/ranger-secret-client.sh --verifier gitlab
[OK] gitlab : le secret du Vault est celui de Keycloak (3f1a…)
admin@adm01:~/src/ansible$ head -n 1 secrets/identite.yml
$ANSIBLE_VAULT;1.2;AES256;critique
```

Le script : jeton de `svc-tofu-keycloak` (identifiants par `-K <(…)`), identifiant interne du client, `GET …/clients/<id>/client-secret` (exige `manage-clients` depuis la 26.8, que le compte d'OpenTofu a), contenu du Vault déchiffré **en mémoire**, clé posée par `yq` à partir d'une variable d'environnement (`strenv`), rechiffrement par `ansible-vault encrypt … --output <temporaire> -` (entrée standard), contrôle de l'en-tête, renommage. Rien n'est écrit en clair, rien ne passe en argument.

*C. GitLab.* `sudo cp -a /etc/gitlab/gitlab.rb /etc/gitlab/gitlab.rb.$(date +%F-%H%M)`, `sudoedit /etc/gitlab/gitlab.rb` (ajout de l'extrait, secret collé depuis `ansible-vault view`), `sudo gitlab-ctl reconfigure`. Connexion par « SSO MédiSphère » en `<MOI>` : tu arrives sur **ton** compte (projets, statut d'administrateur), parce que l'adresse `<MOI>@medisphere.internal` existe déjà ; *Account* → *Service sign-in* montre « SSO MédiSphère » comme **connecté**. Pour Lucas, un seul compte `lucas.martin`, auquel l'identité `openid_connect` (`extern_uid` = son `sub`) est liée (*Admin* → *Users* → `lucas.martin` → *Identities*).

*D. Les groupes.* `svc-synchro-identite` : créé en `root` (*Admin* → *Users* → *New user*, adresse `svc-synchro-identite@medisphere.internal`, sans mot de passe défini : il ne se connecte jamais, il n'a qu'un jeton), ajouté **Owner** des groupes `plateforme`, `mediagenda`, `medidoc` (la page *Roles and permissions* réserve *Manage group members* aux Owners : un Maintainer reçoit 403 sur `POST /groups/:id/members`), jeton personnel `api` avec expiration d'un an ; variable `GITLAB_SYNCHRO_JETON` protégée, masquée et cachée ; pour les essais sur `adm01`, `~/.config/workbook/gitlab-synchro.env` (600). Owner, c'est aussi pouvoir supprimer le groupe ou changer ses réglages : l'outil s'impose donc des bornes que le rôle ne lui impose pas (membres directs seulement, personnes de l'annuaire seulement, jamais le niveau Owner, ni pour donner ni pour retirer : il le signale et laisse faire un humain), le code est relu en MR, son jeton n'existe que dans la CI des branches protégées, et la revue d'accès (E30) contrôle ses effets.

```
admin@adm01:~/src/identite$ ( . ~/.config/workbook/gitlab-synchro.env; export GITLAB_SYNCHRO_JETON; \
>   REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt uv run outils/synchro-gitlab.py )
ÉCART    mediagenda   julien.petit            developer → maintainer
ÉCART    mediagenda   sophie.laurent                  — → reporter
ÉCART    medidoc      sophie.laurent                  — → reporter
ÉCART    plateforme   <MOI>                       owner → owner      (Owner : laissé tel quel, à revoir à la main)
ÉCART    plateforme   lucas.martin                    — → developer
ÉCART    plateforme   nadia.roussel                   — → reporter
…
synchro-gitlab : 3 groupe(s) GitLab, 9 écart(s), rien n'a été changé.
```

Les écarts dépendent de ce que tu avais fait aux M01-M20 (Julien membre de `plateforme` pour une revue, par exemple : il en sera retiré). Planification : *Build* → *Pipeline schedules* → « Synchronisation GitLab », `7 * * * *`, `main`, variable `SYNCHRO=gitlab`. Le job `synchro:gitlab` applique puis rejoue en aperçu et échoue s'il reste un écart non signalé. Étape 10 : la MR qui retire Lucas de `plateforme` affiche dans `synchro:gitlab:apercu` la ligne `plateforme lucas.martin developer → —` : le relecteur voit l'effet dans GitLab **avant** la fusion.

**Explications**

- **Fédération, pas synchronisation des comptes.** GitLab ne reçoit pas de liste de comptes : une personne se connecte, Keycloak l'authentifie (liaison LDAP à l'annuaire), GitLab crée ou retrouve le compte par l'identité OIDC. Une personne désactivée dans l'annuaire ne peut plus **se connecter**, même si son compte GitLab existe encore.
- **Pourquoi `sub`.** GitLab enregistre le couple (fournisseur, `extern_uid`). Avec `preferred_username`, le renommage d'une personne dans l'annuaire créerait une seconde identité, puis un second compte ; avec `sub`, rien ne change. Le rattachement **initial** par adresse (`auto_link_user`) est sûr chez nous parce que l'adresse vient de l'annuaire, en lecture seule pour tout le monde sauf le pipeline : personne ne peut se donner l'adresse d'un autre.
- **Synchronisation bornée.** L'outil ne touche qu'aux **membres directs** et qu'aux **personnes de l'annuaire** : un robot, un compte de service ou un membre hérité d'un groupe parent n'est jamais retiré par erreur. La fonction `calculer_cible` est pure (pas d'appel réseau) : c'est elle qu'on teste.
- **Aperçu en MR.** La même commande, sans `--appliquer`, montre la conséquence d'une MR sur l'annuaire : la relecture ne porte plus sur un YAML mais sur des droits.

**Alternatives**

- *GitLab Premium* : `groups_attribute`, `required_groups`, `admin_groups` dans la configuration OIDC, et la synchronisation de groupes SAML ou LDAP native ; l'outil disparaît.
- *Synchronisation LDAP de GitLab* (`gitlab_rails['ldap_servers']`, groupe ↔ groupe LDAP) : réservée à Premium pour les groupes ; en CE, LDAP sert à l'authentification seulement.
- *Fournisseur OpenTofu `gitlabhq/gitlab`* (`gitlab_group_membership`) : déclaratif, mais il faut générer la liste depuis l'annuaire et il gère **toute** l'appartenance du groupe (les robots aussi), ce qui demande de les déclarer.
- *SCIM* : GitLab l'accepte pour l'offre SaaS et Premium ; pas pour une instance CE autogérée.

**Pièges classiques**

- `uid_field` absent : par défaut `sub` avec omniauth_openid_connect, mais certains tutoriels mettent `preferred_username` « pour lisibilité ».
- Oublier `/etc/gitlab/trusted-certs/` : « SSL_connect returned=1 … certificate verify failed » dans `production_json.log` au premier clic.
- Donner au compte de synchronisation le rôle Maintainer « par moindre privilège » : 403 à la première modification ; Owner est nécessaire, d'où les bornes que l'outil s'impose et la protection de son jeton.
- Laisser l'outil gérer **tous** les membres d'un groupe : au premier passage, il retire `root`, les robots de projet, le compte de synchronisation lui-même.
- Un jeton personnel sans expiration pour `svc-synchro-identite` : il survivrait à tout.
- `echo "secret" >> gitlab.rb` : le secret dans l'historique du shell.

**En production chez MédiSphère**

La connexion par mot de passe local est coupée (sauf `root`) au mini-projet (E46) ; la synchronisation alerte quand un Owner ou un compte absent persiste plus d'une semaine ; son journal est conservé un an (preuve HDS de l'application des départs) ; en Premium, elle serait remplacée par la synchronisation native et l'approbation obligatoire des MR sur `annuaire/`.

---

### M24-E12 — SSO de Grafana : rôles, organisations et équipes

**Solution**

Fichiers : [`clients-grafana.tf`](fichiers/M24-E12/identite/tofu/clients-grafana.tf) ; dans `plateforme/k8s` : [`secrets-k8s.sh.extrait-E12`](fichiers/M24-E12/k8s/outils/secrets-k8s.sh.extrait-E12), [`secrets-k8s.conf.extrait`](fichiers/M24-E12/k8s/outils/secrets-k8s.conf.extrait) ; dans `plateforme/observabilite` : [`kps/values.yaml.extrait`](fichiers/M24-E12/observabilite/kps/values.yaml.extrait), [`reseau/espace-supervision.yaml.extrait`](fichiers/M24-E12/observabilite/reseau/espace-supervision.yaml.extrait) ; dans `plateforme/infra` : [`utilisateurs.tf`](fichiers/M24-E12/infra/observabilite-grafana/utilisateurs.tf), [`main.tf.extrait`](fichiers/M24-E12/infra/observabilite-grafana/main.tf.extrait), [`variables.tf.extrait`](fichiers/M24-E12/infra/observabilite-grafana/variables.tf.extrait), [`organisation-securite.tf.extrait`](fichiers/M24-E12/infra/observabilite-grafana/organisation-securite.tf.extrait).

1. Notes : à la première connexion par OAuth, Grafana cherche un utilisateur lié à ce fournisseur et à cet identifiant externe ; il ne rattache **pas** un compte local par l'adresse, sauf `oauth_allow_insecure_email_lookup = true` (désactivé par défaut depuis Grafana 10, d'où le nom). Sans lui, un compte local de même adresse fait échouer la création (« user already exists ») ou crée un doublon selon le login : on **supprime** les comptes locaux des personnes. Bris de glace essayé avant :
   ```
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
   >   -K <(printf 'user = "admin:%s"\n' "$(cd ~/src/ansible && uv run ansible-vault view ~/src/k8s/secrets/grafana.yml | yq -r .grafana_admin_password)") \
   >   https://grafana.apps.par1.medisphere.internal/api/admin/stats
   200
   ```
2. Client et secret comme en E11 (`ranger-secret-client.sh grafana`).
3. La modification de `secrets-k8s.sh` (trois lignes) lit le Vault d'un composant dans `$MS_ANSIBLE_DIR/secrets/` quand `plateforme/k8s/secrets/` n'en a pas : une seule copie des secrets des clients, qui servent aussi aux VMs. Puis :
   ```
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer identite && outils/secrets-k8s.sh verifier identite
   Vault du composant identite lu dans plateforme/ansible : /home/admin/src/ansible/secrets/identite.yml
   [OK] supervision/grafana-oidc à jour (GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET)
   [OK] supervision/grafana-oidc : GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET identique à sa source
   ```
4. `grafana-sortie` d'abord (sans elle, le retour du SSO affiche « Login failed » et le journal « context deadline exceeded » vers 10.10.70.200), puis les valeurs. Points clés de `generic_oauth` : points de terminaison explicites du royaume, `use_pkce`, `tls_client_ca` (la ConfigMap `racine-medisphere` montée en `/etc/grafana/racine`), `login_attribute_path: preferred_username`, `role_attribute_path` sur `groups` avec **`GrafanaAdmin`** pour `plateforme-admins` et `allow_assign_grafana_admin: true`, `role_attribute_strict: true`, `org_attribute_path: groups` et `org_mapping`. `disable_login_form` reste faux jusqu'à l'étape 8.
5. `<MOI>` : *Profile* → rôle Admin de l'organisation principale et badge *Grafana Admin* ; Lucas : Editor (crée un tableau dans un dossier où il a le droit), n'a pas l'organisation « Sécurité » dans le sélecteur. Journal :
   ```
   admin@adm01:~$ kubectl -n supervision logs deploy/kps-grafana -c grafana | grep -i oauth | tail -n 3
   logger=oauth.generic_oauth … msg="Received id_token" …
   logger=authn.service … msg="Login succeeded" … login=lucas.martin
   ```
6. Comptes locaux (en `admin`, `GET /api/users?perpage=100`) : les personnages et toi, plus éventuellement des comptes de test. Suppression (`DELETE /api/admin/users/<id>`, ou l'interface d'administration) **sauf** le tien, puis le tien après une connexion SSO réussie dans une autre fenêtre (le SSO a créé `<MOI>` comme nouvel utilisateur : supprime l'**ancien**, repéré par son identifiant numérique plus petit et son *auth module* vide). Les tableaux **restent** (ils appartiennent aux dossiers, pas aux personnes) ; les jetons et les préférences personnelles des comptes supprimés disparaissent.
7. `observabilite-grafana` : `ignore_changes` sur les membres de l'organisation « Sécurité » (désormais posés par `org_mapping` à chaque connexion) ; équipes filtrées par les comptes existants (`data "grafana_users"`, fournisseur `admin_serveur` de M22-E16) ; l'adresse de Lucas ajoutée à l'équipe `plateforme`. Plan :
   ```
   admin@adm01:~/src/infra$ tofu -chdir=observabilite-grafana plan
   …
     ~ resource "grafana_team" "equipe" {
         ~ members = [
             + "lucas.martin@medisphere.internal",
             - "karim.benali@medisphere.internal",
             - "nadia.roussel@medisphere.internal",
   …
   Changes to Outputs:
     + membres_pas_encore_connectes = { plateforme = ["karim.benali@…", "nadia.roussel@…", "claire.morel@…"], … }
   ```
   Karim, Nadia et Claire sortent **provisoirement** des équipes : leurs comptes ont été supprimés à l'étape 6 et ne reviendront qu'à leur première connexion par le SSO (c'est écrit dans la sortie). Après tes connexions et celle de Lucas, le plan suivant est vide.
8. `disable_login_form: true`, MR, synchronisation. La page `/login` ne montre plus que « SSO MédiSphère » ; l'appel de l'étape 1 répond toujours 200.

**Explications**

- **Rôle par expression.** `role_attribute_path` est évalué sur l'ID token (puis userinfo, puis le jeton d'accès). `contains(groups[*], …)` échoue si la revendication est absente : avec `role_attribute_strict`, l'échec **refuse** la connexion au lieu de donner Viewer. C'est un garde-fou contre une portée `groupes` retirée (panne M24-E35).
- **Organisations par `org_mapping`.** Le rôle final dans une organisation est le plus élevé de celui de `role_attribute_path` et de celui d'`org_mapping` ; la synchronisation a lieu à **chaque** connexion (`skip_org_role_sync: false`) : un retrait dans l'annuaire se voit à la connexion suivante, pas avant.
- **Équipes en code.** La *team sync* (`groups_attribute_path` → équipes) est réservée à Enterprise ; les équipes restent en OpenTofu, et le filtre par comptes existants rend l'apply robuste au fait que, depuis le SSO, un compte n'existe qu'après sa première connexion.
- **Secret par variable d'environnement.** `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` remplace `client_secret` de `grafana.ini` sans jamais passer par les valeurs du chart (lisibles dans le Secret de la release Helm, dans Git, dans Argo CD).

**Alternatives**

- *OAuth2 Proxy devant Grafana* avec l'authentification par en-tête (`auth.proxy`) : un composant de plus, et Grafana ne reçoit plus les groupes que par en-tête ; utile quand une application ne parle pas OIDC (E18), pas ici.
- *`oauth_allow_insecure_email_lookup = true`* pour rattacher les comptes locaux : acceptable avec notre annuaire, mais les mots de passe locaux restent utilisables par l'API basique ; supprimer les comptes est plus net.
- *Grafana Enterprise* : *team sync*, permissions par source de données (l'organisation « Sécurité » deviendrait inutile).

**Pièges classiques**

- `scopes: openid profile email groups` : la portée `groups` n'existe pas chez nous (la nôtre s'appelle `groupes`, et elle est par défaut).
- `role_attribute_path` qui renvoie `Admin` pour `plateforme-admins` **sans** `GrafanaAdmin` : pas d'administration du serveur (organisations, utilisateurs).
- `cookie_samesite: strict` (M21-E29 l'a évité) : le retour depuis Keycloak perd le cookie d'état, « login.OAuthLogin(missing saved state) ».
- Désactiver le formulaire **avant** d'avoir testé deux personnes : seul l'API basique d'`admin` reste.
- Laisser OpenTofu gérer les membres de l'organisation « Sécurité » : dérive à chaque plan, et des droits qui oscillent.
- Oublier la politique de sortie : le symptôme ressemble à un mauvais secret.

**En production chez MédiSphère**

Alerte sur toute connexion d'`admin` (journal de Grafana dans Loki, M22) ; contrôle de dérive nocturne de `observabilite-grafana` (un plan non vide signale une personne pas encore dans son équipe) ; revue trimestrielle des *Grafana Admins* ; à terme, Grafana Enterprise ou une instance par équipe si les données de santé l'exigent.

---

### M24-E13 — SSO d'Argo CD et fin des comptes locaux

**Solution**

Fichiers : [`clients-argocd.tf`](fichiers/M24-E13/identite/tofu/clients-argocd.tf) ; dans `plateforme/k8s` : [`secrets-k8s.d/identite.sh`](fichiers/M24-E13/k8s/outils/secrets-k8s.d/identite.sh), [`releases/argocd.yaml.gotmpl.extrait`](fichiers/M24-E13/k8s/releases/argocd.yaml.gotmpl.extrait), [`values.yaml.extrait`](fichiers/M24-E13/k8s/composants/argocd/values.yaml.extrait), [`values-durcissement.yaml.extrait`](fichiers/M24-E13/k8s/composants/argocd/values-durcissement.yaml.extrait), [`politiques/argocd.yaml.extrait`](fichiers/M24-E13/k8s/composants/reseau/politiques/argocd.yaml.extrait), [`policy.csv`](fichiers/M24-E13/k8s/releases/argocd/policy.csv), [`rbac-tests.txt`](fichiers/M24-E13/k8s/releases/argocd/rbac-tests.txt) ; dans `plateforme/gitops` : [`medidoc.extrait-E13.yaml`](fichiers/M24-E13/gitops/projets/medidoc.extrait-E13.yaml), [`mediagenda.extrait-E13.yaml`](fichiers/M24-E13/gitops/projets/mediagenda.extrait-E13.yaml).

1. `requestedScopes` vaut par défaut `["openid", "profile", "email", "groups"]` : il faut l'écrire sans `groups`. `enablePKCEAuthentication: true` fait faire l'échange du code **par le navigateur** (page `/pkce/verify` de l'interface), sans secret : c'est le mode « client public ». Avec un client `argocd` confidentiel, l'échange se fait côté `argocd-server` avec le secret, on ne l'active pas. La CLI tourne sur un poste et ne peut garder aucun secret : elle a son propre client **public**, et elle envoie toujours un défi PKCE S256 (code de `argocd login`). Argo CD accepte les jetons dont `aud` vaut `clientID` **ou** `cliClientID`.
2. Deux clients, un secret (`ranger-secret-client.sh argocd`).
3. Le module `identite.sh` est appelé par `secrets-k8s.sh` après les lignes de la table : il crée `argocd/argocd-oidc` avec l'étiquette `app.kubernetes.io/part-of=argocd`.
   ```
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer identite && outils/secrets-k8s.sh verifier identite
   [OK] supervision/grafana-oidc à jour (GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET)
   [OK] argocd/argocd-oidc à jour (clientSecret, étiquette part-of=argocd)
   …
   [OK] argocd/argocd-oidc identique au Vault
   ```
4. Sortie `toFQDNs` vers `sso` sur 443 dans `argocd-server`, puis `oidc.config` dans le gabarit (la racine lue par `readFile`, les accolades de `logoutURL` protégées pour Helmfile : `{{ "{{" }}token{{ "}}" }}` devient `{{token}}` dans `argocd-cm`).
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply
   admin@adm01:~$ kubectl -n argocd get cm argocd-cm -o jsonpath='{.data.oidc\.config}' | head -n 4
   name: SSO MédiSphère
   issuer: https://sso.par1.medisphere.internal/realms/medisphere
   clientID: argocd
   clientSecret: $argocd-oidc:clientSecret
   ```
5. Interface : `<MOI>` voit tout ; Lucas (groupe `plateforme`) voit les Applications sans pouvoir les synchroniser ni lire les journaux des pods. CLI :
   ```
   admin@adm01:~$ argocd login argocd.apps.par1.medisphere.internal --grpc-web --sso --sso-launch-browser=false
   Opening browser for authentication
   Performing authorization_code flow login: https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/auth?…client_id=argocd-cli&code_challenge=…
   Authentication successful
   …
   admin@adm01:~$ argocd account get-user-info
   Logged In: true
   …
   Issuer: https://sso.par1.medisphere.internal/realms/medisphere
   Groups: plateforme-admins,plateforme
   ```
   (Le nom d'utilisateur affiché dépend des revendications que la version d'Argo CD retient : adresse ou `sub`. Ce qui compte pour les droits, ce sont les groupes.)
6. `policy.csv` : `g, plateforme-admins, role:plateforme-admin` ; `g, plateforme|support|securite|ci-lecture, role:lecture` ; `g, mediagenda, role:mediagenda-equipe` ; plus aucune personne. `rbac-tests.txt` : mêmes cas qu'au M20, sujets = groupes, plus des « non » pour `direction`, `medidoc` (rôle de projet non testable ici) et les anciens comptes. AppProject `medidoc` : `groups: [medidoc]`. AppProject `mediagenda` : **sans** groupe, parce que le rôle global `role:mediagenda-equipe` porte déjà les mêmes droits et qu'il est **testé** en CI ; deux chemins vers les mêmes droits, c'est deux endroits à relire et un seul de testé. Suppression des quatre comptes dans `values.yaml` **et** `values-durcissement.yaml` (Helm fusionne les dictionnaires des deux fichiers : un compte retiré d'un seul reste). MR (le job `argocd-rbac` passe), `helmfile apply`.
7. Contrôles :
   ```
   admin@adm01:~$ argocd account list
   NAME        ENABLED  CAPABILITIES
   ci-lecture  true     apiKey
   admin@adm01:~$ argocd account can-i sync applications mediagenda/mediagenda-prod
   yes
   admin@adm01:~/src/k8s$ outils/argocd-rbac-tests.sh
   …
   ```
   Tous les cas « oui » et « non » de `rbac-tests.txt` passent (code 0 ; le script affiche tous les écarts et sort en 1 s’il y en a un).

**Explications**

- **Où vit la décision.** Argo CD vérifie l'ID token (émetteur, signature par le JWKS, audience `argocd` ou `argocd-cli`), lit `groups` (`scopes: [groups]`), et Casbin évalue `policy.csv` : un sujet de ligne `g` peut être un compte local ou un groupe OIDC, sans distinction. C'est pourquoi aucun compte local ne doit porter le nom d'un groupe, et pourquoi les tests de la politique fonctionnent avec des noms de groupes.
- **Durée de session.** `users.session.duration: 8h` (M20-E25) : une personne désactivée dans l'annuaire garde l'interface déjà ouverte au plus 8 h ; le jeton OIDC (5 min) n'est pas rejoué par Argo CD à chaque requête. RB-242 (E23) traite ce cas.
- **Bris de glace.** `admin` reste désactivé ; si Keycloak est en panne **et** qu'une intervention dans Argo CD est indispensable, on le réactive par Helmfile (procédure du M20-E03, depuis un accès `kubectl` de bris de glace), on l'utilise, on le désactive, on le consigne (RB-240).

**Alternatives**

- *Dex* comme intermédiaire (connecteur OIDC vers Keycloak) : utile pour fédérer plusieurs sources ou GitHub ; ici, un pod et une configuration de plus pour rien.
- *Client unique public avec `enablePKCEAuthentication`* pour l'interface et la CLI : pas de secret à gérer ni à faire tourner ; l'échange se fait dans le navigateur, Keycloak doit alors autoriser l'origine de l'interface (*Web origins*) ; défendable, mais le modèle confidentiel garde le jeton de Keycloak hors du navigateur.
- *Rôles de projet pour toutes les équipes* (y compris MédiAgenda) : droits écrits avec le projet, mais non couverts par le test de `policy.csv`.

**Pièges classiques**

- Secret `argocd-oidc` sans l'étiquette `part-of` : Argo CD journalise « config referenced '$argocd-oidc:clientSecret', which is not labeled » et le SSO échoue avec un secret vide.
- `requestedScopes` absent : Keycloak refuse ou ignore la portée inconnue `groups` selon sa version ; on l'écrit.
- Groupes en chemin complet (`/plateforme-admins`) si le mappeur change : plus aucune ligne `g` ne correspond (panne M24-E39).
- Retirer les comptes de `values.yaml` seulement.
- `policy.default: role:readonly` « pour que les nouveaux voient quelque chose » : toute personne authentifiée de l'annuaire lirait tout, journaux compris.
- Oublier la politique réseau : « Failed to query provider … i/o timeout » dans le journal d'`argocd-server`.

**En production chez MédiSphère**

Le rôle de projet par équipe pour les jetons d'automatisation, révoqués un par un ; les tests de la politique joués aussi contre la configuration rendue (`helmfile template`) ; alerte sur la réactivation d'`admin` (événement d'audit sur le ConfigMap `argocd-cm`) ; `users.session.duration` ramené à 4 h quand l'OTP (E21) rend les reconnexions moins coûteuses à justifier.

---

### M24-E14 — Harbor en OIDC

**Solution**

Fichiers : [`clients-harbor.tf`](fichiers/M24-E14/identite/tofu/clients-harbor.tf) ; dans `plateforme/infra` : [`registre/authentification.tf`](fichiers/M24-E14/infra/registre/authentification.tf), [`registre/projets.tf.extrait`](fichiers/M24-E14/infra/registre/projets.tf.extrait), [`registre/variables.tf.extrait`](fichiers/M24-E14/infra/registre/variables.tf.extrait), [`outils/charger-acces.sh.extrait`](fichiers/M24-E14/infra/outils/charger-acces.sh.extrait) ; dans `plateforme/ansible` : rôle `harbor` [`defaults/main.yml.extrait`](fichiers/M24-E14/ansible/roles/harbor/defaults/main.yml.extrait), [`templates/harbor.yml.j2.extrait`](fichiers/M24-E14/ansible/roles/harbor/templates/harbor.yml.j2.extrait).

*A. Comprendre.*
```
admin@adm01:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt \
>   -K <(printf 'user = "admin:%s"\n' "<mot de passe lu dans le Vault>") \
>   https://registry.par1.medisphere.internal/api/v2.0/configurations | jq .auth_mode
{
  "editable": false,
  "value": "db_auth"
}
```
(Le mot de passe se lit dans le Vault et passe par une substitution, jamais en clair dans la commande : `-K <(printf … "$(… ansible-vault view … | yq -r .vault_harbor_admin_mdp)")`.) La documentation : « You can change the authentication mode … only if no local users have been added » ; le code (`src/controller/config/controller.go`, `authModeCanBeModified`) compte les utilisateurs **non supprimés**, administrateur par défaut exclu (`src/pkg/user/manager.go`, `excludeDefaultAdmin`), et refuse s'il en reste un : `editable: false`. Les quatre comptes créés par OpenTofu au M13-E03 bloquent la bascule.

Plan (`~/m24/e14/plan.md`) : (1) membres de **groupes** OIDC en plus des membres utilisateurs ; (2) suppression des utilisateurs et de leurs appartenances ; (3) bascule. Entre (2) et (3), Lucas ne peut plus se connecter à Harbor (ni compte local, ni OIDC) : fenêtre courte, annoncée ; les robots (CI, Argo CD, `k8s-pull`, checks) ne sont pas des utilisateurs, ils ne dépendent pas du mode et continuent.

*B. La confiance.* `harbor_ca_confiance` (la racine posée par `ca_lab`) et `storage_service.ca_bundle` dans `harbor.yml` : `prepare` copie le paquet dans `common/config/shared/trust-certificates/`, monté en `/harbor_cust_cert` dans `harbor-core`, `harbor-jobservice`, `registry`… ; au démarrage, `install_cert.sh` l'ajoute au magasin du conteneur.
```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/registre.yml --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/registre.yml
admin@reg01:~$ sudo docker exec harbor-core curl -s -o /dev/null -w '%{http_code}\n' \
>   https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration
200
```

*C. Le client et les trois MR.* Client, `ranger-secret-client.sh harbor`, variable de CI `TF_VAR_harbor_oidc_secret` (protégée, masquée, cachée) et chargement par `charger-acces.sh` sur `adm01`.
- MR 1 : `harbor_project_member_group` (8 membres de groupes) ; le plan annonce `8 to add`. *Administration* → *Groups* montre les groupes OIDC créés.
- MR 2 : `utilisateurs.tf` supprimé, `harbor_project_member_user` supprimés, variables `moi` et `moi_nom` retirées ; plan `14 to destroy` (4 `harbor_user`, 4 `random_password`, 6 appartenances, selon ton état du M13). Après l'apply, `auth_mode.editable` vaut `true`. Un utilisateur « supprimé » reste en base, marqué `deleted` et renommé `lucas.martin#5` : il ne compte plus, et son nom est libre pour le compte OIDC.
- MR 3 : `authentification.tf`. Plan `1 to add` ; le secret n'apparaît ni dans le plan ni dans l'état (`oidc_client_secret_wo`).

Connexion : la page de Harbor propose « LOGIN VIA OIDC PROVIDER » ; `<MOI>` arrive administrateur système (`oidc_admin_group`), Lucas est créé sans écran d'inscription (`oidc_auto_onboard`), membre des groupes `plateforme` (*Administration* → *Groups*), donc `maintainer` de `medisphere`. Pour `docker login` ou `helm registry login`, chaque personne utilise le **secret CLI** de son profil (*User Profile* → *CLI secret*), pas son mot de passe de l'annuaire. Contrôles : `lab/bin/check 13 03` (robot des checks) au vert ; une Application d'Argo CD qui tire un chart de `charts` se synchronise.

**Explications**

- **Pourquoi Harbor fige le mode.** Un compte local et un compte OIDC du même nom seraient deux identités différentes pour les mêmes droits ; Harbor préfère interdire. Supprimer d'abord les comptes, puis basculer, est la seule voie propre ; « recréer Harbor », « modifier la base » ou « passer par LDAP » sont des contournements qui perdent l'historique ou l'intégrité.
- **Groupes OIDC.** Harbor crée un groupe à partir de la revendication `groups` à chaque connexion (filtré par `oidc_group_filter`) ; la ressource OpenTofu le crée **avant**, ce qui permet de déclarer les appartenances en code sans attendre une connexion.
- **Vérifier le certificat.** `oidc_verify_cert = false` ferait accepter n'importe quel serveur qui répond au nom de `sso` : un attaquant sur le chemin obtiendrait les codes et les jetons. La racine dans le magasin des conteneurs règle le problème durablement (elle survit aux montées de version par `prepare`).

**Alternatives**

- *Bascule par l'API* (`PUT /api/v2.0/configurations`) au lieu d'OpenTofu : immédiate, mais hors du code ; le fournisseur la décrit et détecte la dérive.
- *LDAP direct vers FreeIPA* (`ldap_auth`) : groupes LDAP natifs, mais pas de SSO ni d'OTP, et un mot de passe saisi dans Harbor.
- *Garder des comptes locaux et une synchronisation par l'API* : pas de SSO, deux sources ; rejeté par le modèle d'autorisation.

**Pièges classiques**

- Supprimer les comptes **avant** d'avoir ajouté les groupes : pendant la fenêtre, plus personne d'autre qu'`admin` n'a de droits.
- `oidc_scope` sans `openid`, ou avec `offline_access` sans raison.
- `oidc_user_claim` à `name` (défaut) : « Lucas Martin » devient l'identifiant Harbor, avec une espace.
- `oidc_verify_cert = false`.
- Un changement de `harbor.yml` sans `prepare` : la racine n'arrive jamais dans les conteneurs.
- Oublier les variables `TF_VAR_moi` de la CI : le plan échoue sur des variables non déclarées après la MR 2.

**En production chez MédiSphère**

`oidc_logout` activé (déconnexion de Keycloak avec Harbor) ; rotation du secret par `harbor_oidc_secret_version` (RB-244) ; alerte sur toute connexion `admin` (journal d'audit de Harbor vers Loki) ; les secrets CLI des personnes expirent avec leur session OIDC ; les robots restent la seule voie des automatisations.

---

### M24-E15 — Proxmox VE, PBS et NetBox en SSO

**Solution**

Fichiers : [`clients-proxmox.tf`](fichiers/M24-E15/identite/tofu/clients-proxmox.tf), [`clients-pbs.tf`](fichiers/M24-E15/identite/tofu/clients-pbs.tf), [`clients-netbox.tf`](fichiers/M24-E15/identite/tofu/clients-netbox.tf) ; dans `plateforme/infra` : [`acces-proxmox/`](fichiers/M24-E15/infra/acces-proxmox/) ([`versions.tf`](fichiers/M24-E15/infra/acces-proxmox/versions.tf), [`chiffrement.tf`](fichiers/M24-E15/infra/acces-proxmox/chiffrement.tf), [`variables.tf`](fichiers/M24-E15/infra/acces-proxmox/variables.tf), [`royaume.tf`](fichiers/M24-E15/infra/acces-proxmox/royaume.tf), [`acl.tf`](fichiers/M24-E15/infra/acces-proxmox/acl.tf)) ; dans `plateforme/ansible` : rôle `netbox` ([`defaults`](fichiers/M24-E15/ansible/roles/netbox/defaults/main.yml.extrait), [`configuration.py.j2`](fichiers/M24-E15/ansible/roles/netbox/templates/configuration.py.j2.extrait), [`netbox.service.j2`](fichiers/M24-E15/ansible/roles/netbox/templates/netbox.service.j2.extrait)), [`group_vars/role_netbox/sso.yml`](fichiers/M24-E15/ansible/inventories/lab/group_vars/role_netbox/sso.yml), [`playbooks/netbox.yml.extrait`](fichiers/M24-E15/ansible/playbooks/netbox.yml.extrait) ; [`nbx01/groupes-sso.py`](fichiers/M24-E15/nbx01/groupes-sso.py).

*A.* Trois clients, trois secrets. Proxmox VE et PBS envoient un défi PKCE S256 (crate `proxmox-openid`) : exigé. La redirection de Proxmox est **l'origine** de l'interface (`https://pve01.par1.medisphere.internal:8006`, sans barre finale). Accès à `sso` : sur `pve01` et `pbs01`, vérifie la résolution (`getent hosts sso.par1.medisphere.internal`) et la racine (`/usr/local/share/ca-certificates/`, `update-ca-certificates`) ; `pve01` et `pbs01` ne sont pas gérés par le rôle `ca_lab` des VMs : une ligne de plus dans ton journal du M00, ou un fichier `/etc/hosts` documenté si le résolveur de ta maison ne connaît pas le lab.

*B. Proxmox VE.* `--username-claim` ne peut plus changer après la création : les utilisateurs du royaume sont nommés d'après lui (`lucas.martin@medisphere`), le changer rendrait orphelins tous les comptes et leurs droits. Le jeton temporaire :
```
root@pve01:~# pveum user token add root@pam realm-oidc --privsep 0 --expire $(( $(date +%s) + 1800 )) \
>   --comment "M24-E15 apply acces-proxmox, supprimé après usage"
┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
│ full-tokenid │ root@pam!realm-oidc                  │
│ value        │ 3c2b…                                │
admin@adm01:~/src/infra$ . outils/charger-acces.sh
admin@adm01:~/src/infra$ read -rsp 'Jeton temporaire : ' v; echo; export PROXMOX_VE_API_TOKEN="root@pam!realm-oidc=$v"; unset v
admin@adm01:~/src/infra$ tofu -chdir=acces-proxmox init && tofu -chdir=acces-proxmox plan -out=plan.tfplan
Plan: 9 to add, 0 to change, 0 to destroy.
admin@adm01:~/src/infra$ tofu -chdir=acces-proxmox apply plan.tfplan
root@pve01:~# pveum user token delete root@pam realm-oidc
admin@adm01:~/src/infra$ unset PROXMOX_VE_API_TOKEN; rm -f acces-proxmox/plan.tfplan
```
(La MR est relue **avant** l'apply, sur le plan joint en commentaire ; l'état `acces-proxmox` n'est pas appliqué par la CI : la CI n'a pas, et ne doit pas avoir, de jeton capable de changer les droits de l'hyperviseur.) Le compromis : un jeton `root@pam` de 30 minutes, créé et supprimé sous tes yeux, vaut mieux qu'un jeton d'automatisation permanent avec `Permissions.Modify` sur `/` (qui équivaut à l'administration complète de l'hyperviseur).

Connexions : `<MOI>@medisphere` (membre de `plateforme-admins-medisphere` et `plateforme-medisphere`, rôle `PVEAdmin` sur `/`), `lucas.martin@medisphere` (`plateforme-medisphere`, `PVEAuditor` : il voit tout, n'arrête rien ; le bouton *Shutdown* répond « Permission check failed »). `wb-admin@pve` désactivé (`pveum user modify wb-admin@pve --enable 0`) : pas supprimé, pour garder le lien entre son nom et l'historique des tâches et des journaux.

*C. PBS.*
```
root@pbs01:~# proxmox-backup-manager user generate-token root@pam realm-oidc --expire $(( $(date +%s) + 1800 ))
Result: {"tokenid": "root@pam!realm-oidc", "value": "…"}
root@pbs01:~# proxmox-backup-manager acl update /access/domains Admin --auth-id 'root@pam!realm-oidc'
root@pbs01:~# ( umask 077; read -rsp 'Jeton : ' j; echo; read -rsp 'Secret du client pbs : ' s; echo
>   printf '%s' "$s" > /root/.pbs-oidc
>   curl -sS --cacert /etc/proxmox-backup/proxy.pem --resolve "$(hostname -f):8007:127.0.0.1" \
>     -K <(printf 'header = "Authorization: PBSAPIToken=root@pam!realm-oidc:%s"\n' "$j") \
>     --data-urlencode realm=medisphere \
>     --data-urlencode issuer-url=https://sso.par1.medisphere.internal/realms/medisphere \
>     --data-urlencode client-id=pbs --data-urlencode client-key@/root/.pbs-oidc \
>     --data-urlencode username-claim=preferred_username --data-urlencode autocreate=1 \
>     "https://$(hostname -f):8007/api2/json/config/access/openid"
>   shred -u /root/.pbs-oidc )
{"data":null}
root@pbs01:~# proxmox-backup-manager user delete-token root@pam realm-oidc
root@pbs01:~# proxmox-backup-manager openid show medisphere
```
Après la première connexion de chacun (utilisateur `<MOI>@medisphere` créé sans droit) : `proxmox-backup-manager acl update / Admin --auth-id '<MOI>@medisphere'`, `… /datastore/ds-lab DatastoreAudit --auth-id 'nadia.roussel@medisphere'`, `… / Audit --auth-id 'sophie.laurent@medisphere'`. PBS reste **par personne** : son royaume OpenID ne lit pas de groupes ; les ACL sont peu nombreuses, posées par RB-241 et contrôlées par la revue d'accès.

*D. NetBox.* Rôle : `REMOTE_AUTH_BACKEND` (backend `OpenIdConnectAuth`), `SOCIAL_AUTH_OIDC_OIDC_ENDPOINT` (émetteur, sans `/.well-known`), `SOCIAL_AUTH_OIDC_KEY`, `_SECRET`, `_USE_PKCE`, `REMOTE_AUTH_DEFAULT_GROUPS = ["sso-lecture"]`, pipeline avec `associate_by_email` **avant** `create_user`, et `Environment=REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt` dans les unités (requests utilise `certifi` sinon : « SSLError … certificate verify failed »). Groupes et permissions :
```
admin@nbx01:~$ sudo -u netbox /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py nbshell < groupes-sso.py
sso-lecture : 1 action(s) sur 112 types d'objets
sso-ecriture : 4 action(s) sur 112 types d'objets
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/netbox.yml --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/netbox.yml
```
La page de connexion propose « SSO MédiSphère ». `<MOI>` arrive sur son compte local (rattaché par l'adresse) : ses jetons (`netbox-moi.token`) fonctionnent toujours. Lucas est créé, membre de `sso-lecture`. `sso-ecriture` se donne à la main (*Admin* → *Users* → `<MOI>` → *Groups*). `lab/bin/check 06 04` au vert : les jetons des comptes de service ne dépendent pas du SSO.

**Explications**

- **Proxmox VE** lit la revendication `groups` et la projette sur des groupes `<nom>-<royaume>` ; avec `groups-overwrite`, les appartenances sont **remplacées** à chaque connexion (un retrait dans l'annuaire se voit à la connexion suivante) ; sans `groups-autocreate`, seuls les groupes déclarés servent. Les ACL vont aux groupes, jamais aux personnes.
- **PBS** fait de l'OIDC sans groupes : l'authentification est centralisée (départ = plus de connexion), l'autorisation reste locale. C'est un écart écrit dans le modèle.
- **NetBox** délègue à `python-social-auth` ; le pipeline décide du compte : `social_user` cherche une association existante, `associate_by_email` rattache un compte local de même adresse, `create_user` crée sinon. Sans `associate_by_email`, `get_username` aurait produit `lucas.martin` + un suffixe aléatoire, à côté de l'ancien compte.

**Alternatives**

- *Proxmox VE par LDAP* (royaume `ldap` vers FreeIPA, synchronisation des groupes `pveum realm sync`) : groupes synchronisés sans connexion préalable, mais pas de SSO ni d'OTP.
- *PBS par LDAP* : de même, avec synchronisation de groupes ; ou OAuth2 Proxy devant l'interface, sans droits par groupe.
- *NetBox derrière OAuth2 Proxy* avec `REMOTE_AUTH_BACKEND = RemoteUserBackend` et `REMOTE_AUTH_GROUP_SYNC_ENABLED` : les groupes de l'annuaire arrivent par en-tête (séparateur `|`) et deviennent les groupes NetBox ; plus de travail manuel, un mandataire de plus, et la confiance dans un en-tête (NetBox ne doit être joignable que par le mandataire).

**Pièges classiques**

- `username-claim` laissé à `subject` : des utilisateurs `3f6a…@medisphere` illisibles, et impossible à changer ensuite.
- Donner `Administrator` au lieu de `PVEAdmin` : les membres changeraient eux-mêmes les ACL et les royaumes.
- Augmenter les droits de `wb-tofu@pve` pour appliquer `acces-proxmox/` « une fois » : ils restent.
- Oublier `pveum user token delete` : un jeton `root@pam` sans séparation des privilèges qui traîne (le check le cherche).
- NetBox sans `REQUESTS_CA_BUNDLE` : l'erreur apparaît au retour de Keycloak, pas au démarrage.
- `associate_by_email` avec un IdP où chacun saisit son adresse : prise de compte offerte.

**En production chez MédiSphère**

Proxmox VE et PBS derrière l'OTP de Keycloak (E21) ; TFA locale exigée sur `root@pam` (clé matérielle au coffre) ; ACL de PBS revues chaque mois par la revue d'accès ; NetBox derrière OAuth2 Proxy si le nombre de personnes ayant l'écriture grandit ; état `acces-proxmox` appliqué seulement par deux personnes, avec un jeton temporaire journalisé.

---

### M24-E16 — `kubectl` par OIDC : authentification structurée et kubelogin

**Solution**

Fichiers : [`clients-kubernetes.tf`](fichiers/M24-E16/identite/tofu/clients-kubernetes.tf) ; dans `plateforme/ansible` : rôle [`k8s_authentification`](fichiers/M24-E16/ansible/roles/k8s_authentification/) ([`defaults`](fichiers/M24-E16/ansible/roles/k8s_authentification/defaults/main.yml), [`tasks`](fichiers/M24-E16/ansible/roles/k8s_authentification/tasks/main.yml), [`config.yaml.j2`](fichiers/M24-E16/ansible/roles/k8s_authentification/templates/config.yaml.j2)), [`group_vars/k8s_plan_controle/authentification.yml`](fichiers/M24-E16/ansible/inventories/lab/group_vars/k8s_plan_controle/authentification.yml), [`playbooks/k8s-api-fichiers.yml`](fichiers/M24-E16/ansible/playbooks/k8s-api-fichiers.yml) ; dans `plateforme/k8s` : [`cluster/kubeadm-config.yaml.extrait`](fichiers/M24-E16/k8s/cluster/kubeadm-config.yaml.extrait), [`outils/kubeconfig-oidc.sh`](fichiers/M24-E16/k8s/outils/kubeconfig-oidc.sh), [`rbac/wb-checks-securite.yaml`](fichiers/M24-E16/k8s/rbac/wb-checks-securite.yaml) ; documentation : [`acces.md.extrait`](fichiers/M24-E16/medisphere/docs/kubernetes/acces.md.extrait).

*A.* Notes attendues :
- **Préfixe `oidc:`** : sans lui, un groupe `system:masters` créé dans l'annuaire donnerait les pleins pouvoirs sans passer par le RBAC, et un utilisateur `kubernetes-admin` se ferait passer pour celui d'`admin.conf`. Avec lui, tout ce qui vient de Keycloak est dans un espace de noms à part ; les `userValidationRules` refusent en plus tout nom en `system:`.
- **Ce que vérifie le serveur d'API** : signature de l'ID token avec les clés du JWKS (récupérées par la découverte et gardées en cache), `iss` = l'URL de l'émetteur, `aud` contient `kubernetes`, `exp` et `nbf`, puis les `claimValidationRules` (CEL sur `claims`), la correspondance (`username`, `groups`, `uid`), enfin les `userValidationRules` (CEL sur `user`).
- **La racine dans le fichier** : kube-apiserver tourne dans un conteneur dont l'image a son propre magasin, sans la racine MédiSphère ; `certificateAuthority` est la seule ancre qu'il utilisera pour joindre `sso`.
- **Option mélangée** : `--authentication-config` et une option `--oidc-*` ensemble, et le serveur d'API refuse de démarrer (« authentication-config file and oidc-* flags are mutually exclusive ») : un tiers du plan de contrôle perdu par nœud reconfiguré.
- **Qui porte le jeton** : kubelogin obtient l'ID token (code + PKCE), le garde en cache et le donne à `kubectl` (plugin `exec`), qui l'envoie en `Authorization: Bearer`. Le serveur d'API vérifie la signature **localement** : il n'appelle Keycloak que pour la découverte et les clés.

```
admin@k8s-cp01:~$ curl -sS --max-time 5 https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration | jq -r .issuer
https://sso.par1.medisphere.internal/realms/medisphere
```
(Si le flux `K8S_CP` → 10.10.70.200:443 manque à la bordure, ajoute-le au rôle `pare_feu` et à la matrice : c'est ce flux que le serveur d'API utilisera.)

*B.* Client public : kubelogin est un binaire sur des postes, un secret y serait un secret de tout le monde ; PKCE protège l'échange, et le serveur d'API n'a pas besoin de secret puisqu'il ne fait que **vérifier** des jetons signés. Grafana, lui, échange le code depuis un serveur qui sait garder un secret.
```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-api-fichiers.yml --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-api-fichiers.yml
TASK [k8s_authentification : AuthenticationConfiguration] ***
changed: [k8s-cp01]
RUNNING HANDLER [k8s_authentification : Rappel du serveur d'API] ***
ok: [k8s-cp01] => msg: k8s-cp01 : /etc/kubernetes/authentification/config.yaml a changé. …
```
Rien ne change pour le serveur d'API : aucune option ne désigne encore ce fichier (le rôle pose les fichiers **avant** la reconfiguration, comme l'audit et le chiffrement du M14).

*C.*
```
admin@adm01:~/src/k8s$ outils/reconfigurer-apiserver.sh k8s-cp01
== k8s-cp01 : dépôt du fichier de configuration du nœud
…
+    - --authentication-config=/etc/kubernetes/authentification/config.yaml
+    - mountPath: /etc/kubernetes/authentification
+      name: authentification
…
== k8s-cp01 : /readyz OK
admin@adm01:~$ kubectl --context k8s-par1 -n kube-system get pod kube-apiserver-k8s-cp01 -o yaml | grep authentication-config
    - --authentication-config=/etc/kubernetes/authentification/config.yaml
admin@adm01:~$ kubectl --context k8s-par1 -n kube-system logs kube-apiserver-k8s-cp01 | grep -i -E 'jwt|authenticat' | tail -n 3
admin@adm01:~/src/k8s$ outils/reconfigurer-apiserver.sh k8s-cp02    # puis k8s-cp03
admin@adm01:~/src/k8s$ outils/reconfigurer-apiserver.sh --televerser k8s-cp01
```

*D.*
```
admin@adm01:~$ kubectl krew install oidc-login && kubectl oidc-login --help | head -n 3
admin@adm01:~/src/k8s$ outils/kubeconfig-oidc.sh
kubeconfig-oidc : contexte k8s-par1-oidc (cluster k8s-par1, utilisateur oidc, client kubernetes) prêt.
toi@poste:~$ ssh -L 8000:127.0.0.1:8000 -L 18000:127.0.0.1:18000 admin@adm01.par1.medisphere.internal
admin@adm01:~$ kubectl --context k8s-par1-oidc auth whoami
Please visit the following URL in your browser: http://localhost:8000
ATTRIBUTE                                           VALUE
Username                                            oidc:<MOI>
UID                                                 7c0e…
Groups                                              [oidc:plateforme-admins oidc:plateforme system:authenticated]
admin@adm01:~$ kubectl --context k8s-par1-oidc get pods -A
Error from server (Forbidden): pods is forbidden: User "oidc:<MOI>" cannot list resource "pods" in API group "" at the cluster scope
```
`Forbidden` et non `Unauthorized` : l'**authentification** a réussi (le serveur sait qui tu es), l'**autorisation** refuse (aucune liaison RBAC ne vise `oidc:plateforme-admins`) ; c'est M24-E17. `auth whoami` (SelfSubjectReview) est permis à tout utilisateur authentifié.

Refus :
- Jeton d'accès : un utilisateur `oidc-acces` identique avec `--oidc-use-access-token` → `error: You must be logged in to the server (Unauthorized)`. Décodé : `aud` = `account` (ou absent), `azp` = `kubernetes` ; le serveur d'API refuse sur l'audience (journal : « invalid bearer token … audience »).
- Jeton de `wb-checks` : 
  ```
  admin@adm01:~$ ( . ~/.config/workbook/keycloak-checks.env
  >   j=$(curl -s -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") -d grant_type=client_credentials \
  >     https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/token | jq -r .access_token)
  >   curl -s -o /dev/null -w '%{http_code}\n' --cacert <(kubectl config view --raw --minify --context k8s-par1 \
  >     -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d) \
  >     -K <(printf 'header = "Authorization: Bearer %s"\n' "$j") -H 'Content-Type: application/json' \
  >     -d '{"apiVersion":"authentication.k8s.io/v1","kind":"SelfSubjectReview"}' \
  >     https://k8s-api.par1.medisphere.internal:8443/apis/authentication.k8s.io/v1/selfsubjectreviews )
  401
  ```
  `aud` = `realm-management, account`, `azp` = `wb-checks` : refusé par l'audience, et la règle `azp` l'aurait refusé aussi.

`rbac/wb-checks-securite.yaml` appliquée par `task appliquer` : lecture d'ESO et de Kyverno pour les modules suivants ; les liaisons RBAC (y compris celles des groupes `oidc:…` d'E17) sont déjà lisibles par `wb-checks-base`.

**Explications**

- **Authentification structurée.** GA depuis la 1.34 : plusieurs émetteurs, règles CEL, correspondances par expression, **rechargement à chaud** du fichier (métrique `apiserver_authentication_config_controller_automatic_reload_last_timestamp_seconds`). Une configuration invalide est refusée au démarrage ; au rechargement, l'ancienne reste active et l'erreur est journalisée. Les options `--oidc-*` existent encore en 1.36 mais n'offrent qu'un émetteur, sans CEL ni rechargement.
- **`azp`.** L'audience prouve que le jeton est **destiné** à Kubernetes ; `azp` prouve qu'il a été **demandé** par le client `kubernetes`. La règle ferme un trou : un mappeur d'audience mal placé sur un autre client (« ajoute `kubernetes` à l'`aud` de Grafana ») ne rend pas les jetons de Grafana valables pour le cluster.
- **Un nœud à la fois.** Le manifeste statique change, le kubelet redémarre le pod ; pendant ce temps, la VIP de l'API (HAProxy sur les nœuds, M14-E03) envoie vers les deux autres. Le script revient en arrière tout seul si `/readyz` ne répond pas.
- **Disponibilité.** Si Keycloak tombe, les jetons déjà émis restent valables jusqu'à leur expiration (5 min) et les clés restent en cache : les nouvelles connexions échouent. `admin.conf` ne dépend de rien de tout cela : c'est le bris de glace.

**Alternatives**

- *Options `--oidc-*`* : plus simples, un seul émetteur, pas de CEL ni de rechargement ; toujours prises en charge en 1.36.
- *Pinniped* : un *Concierge* dans le cluster et un *Supervisor* qui fédèrent l'identité **sans toucher au serveur d'API** (utile sur les distributions gérées) ; un composant de plus.
- *Device code* (`--grant-type device-code` de kubelogin) : pas de tunnel, mais il faut activer le flux d'appareil sur le client, que l'hameçonnage par code d'appareil vise précisément.
- *Jeton d'accès* (`--oidc-use-access-token`) avec un mappeur d'audience `kubernetes` sur le client : possible, mais l'ID token est fait pour cela.

**Pièges classiques**

- Barre finale à l'émetteur (`…/realms/medisphere/`) : `iss` ne correspond plus, tous les jetons sont refusés.
- `prefix` absent : la configuration est refusée (il est obligatoire avec `claim`) ; `prefix: ""` est accepté, et dangereux.
- Monter le **fichier** au lieu du dossier : une mise à jour par renommage n'est jamais vue par le pod.
- Oublier `--televerser` : la prochaine montée de version (RB-142) régénère le manifeste sans l'option.
- Lancer kubelogin sans tunnel : le navigateur du poste reçoit « connexion refusée » sur `localhost:8000` après la connexion, et kubelogin attend jusqu'au délai.
- Copier le cache de kubelogin (`~/.kube/cache/oidc-login`) : il contient un jeton de rafraîchissement, c'est un secret.

**En production chez MédiSphère**

Le certificat personnel du M14 n'est plus renouvelé (E17) ; l'OTP s'applique aussi à `kubectl` puisque kubelogin passe par le navigateur (E21) ; supervision de la métrique de rechargement et d'une alerte « aucune authentification OIDC réussie depuis 1 h en heures ouvrées » ; un second émetteur (royaume de secours) dans le même fichier si un jour Keycloak est en grappe multi-site ; `admin.conf` utilisé seulement en bris de glace, son usage visible dans l'audit de l'API (`user.username = "kubernetes-admin"`).
