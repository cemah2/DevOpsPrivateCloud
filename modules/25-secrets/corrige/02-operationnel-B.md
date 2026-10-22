# Module 25 — Palier 2 : Opérationnel — Corrigé (E10 à E16)

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les solutions complètes sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `…/secrets/…` = `plateforme/secrets`, `…/ci-templates/…` = `plateforme/ci-templates`, `…/ansible/…` = `plateforme/ansible`, `…/k8s/…` = `plateforme/k8s`, `…/gitops/…` = `plateforme/gitops`, `…/charts-miroir/…` = `plateforme/charts-miroir`, `…/deploiement/…` = `mediagenda/deploiement`, `…/medidoc-deploiement/…` = `medidoc/deploiement`, `…/mediagenda-api/…` = `mediagenda/api`, `…/medisphere/…` = la documentation, `…/essais/` = `~/m25/eXX/`. On **superpose** les dossiers dans l'ordre des exercices, par-dessus ceux du palier 1 ; un fichier d'un exercice plus récent remplace le précédent. Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête). Les valeurs `<EN-MAJUSCULES>` sont à remplacer par les tiennes (`<RACINE-MEDISPHERE-EN-BASE64>` : `base64 -w0 /usr/local/share/ca-certificates/medisphere-root-ca.crt`).

**Structure de `plateforme/secrets`.** Celle du palier 1 (E08) : `tofu/` (fournisseur `hashicorp/vault ~> 5.13`, état S3 `secrets` chiffré, jeton enfant de 20 min créé à partir de ta session OIDC), `politiques/<nom>.hcl` appliquées par **une seule** ressource `vault_policy.acl` (`for_each` sur `fileset`) : ajouter une politique = ajouter un fichier `.hcl`, aucune ressource `vault_policy` à écrire dans ce palier (sauf les politiques **générées** par gabarit, `eso-<espace>`, E13). Les certificats publics lus par `file()` sont rangés dans `racine/`.

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *OpenBao* : un serveur OpenBao **2.6.4** de développement a servi de banc. Politiques chargées (`bao policy fmt`, `bao policy write`) ; méthode `jwt` : rôles avec revendications liées en `glob` et en listes, jetons forgés au format de GitLab (bonne branche acceptée, branche non protégée, autre audience, autre `project_id` refusés, messages relevés) ; méthode `kubernetes` : configuration et rôles écrits et relus (la vérification TokenReview elle-même exige un cluster) ; moteur `database` contre un **PostgreSQL 16** local : connexion, `rotate-root`, politique de mot de passe, rôles `api` et `migrateur` (droits, propriétaire des objets créés, refus du `DROP`), révocation **pendant** une session ouverte (la session casse), renouvellement (le `VALID UNTIL` suit), connexion TLS `sslmode=verify-ca` + `sslrootcert` (et refus de `verify-full` sur une adresse, refus d'une mauvaise CA) ; PKI : CSR d'intermédiaire, signature par une racine d'essai, `set-signed` de la chaîne, émetteur par défaut, rôle (nom hors `svc`, IP et durée excessive essayés), CRL et révocation. Le SQL de préparation joué deux fois (idempotent) ; la mise à jour des options d'une appartenance existante par un nouveau `GRANT` vérifiée.
- *OpenTofu* 1.13.2 et `hashicorp/vault` **5.13.0** : `tofu fmt`, `tofu validate` de l'ensemble des fichiers du palier, `plan` contre le banc, `apply` de ressources témoins (rôle JWT : la liste `"main,v*"` arrive bien en liste ; rôle PKI ; politique de mot de passe ; rôle de base de données).
- *Kubernetes* : `kubeconform -strict` avec les schémas tirés des CRD d'**ESO 2.13.0** (rendu du chart), **cert-manager 1.21.2**, **CloudNativePG 1.30.1**, **Argo CD 3.5.6**, **Argo Rollouts 1.10.1**, **Cilium 1.20.3** ; `helm template` (Helm 4.0.1) des charts **external-secrets 2.13.0** et **reloader 2.2.18** avec les valeurs du palier (images, arguments, droits relus) ; `kustomize build` (5.8.1) du component `identifiants-dynamiques` (correctifs appliqués ; correctif **ignoré sans erreur** quand le component passe avant celui qui rend sa cible : vérifié) et des correctifs de relais TLS.
- *Scripts et Ansible* : `shellcheck -x` et `bash -n` (checks, `openbao-ci.sh`, `etat-depuis-openbao.sh`, `vault-pass-client.sh` — essayé contre le banc : identité permise, refusée, jeton invalide, mode secours —, `secret-vers-openbao.sh` — essayé avec un faux `kubectl` : recopie, refus d'écraser, comparaison) ; `ansible-lint` (profil `production`) sur `openbao_client`.
- **Points non testés en conditions réelles** (à vérifier sur ton lab ; signale tout écart) : connexion d'un vrai job GitLab 19.5 (nom et présence de la revendication `environment`, valeur de `ref_protected` dans un **pipeline de MR** issu d'une branche protégée) et découverte OIDC de `git01` depuis `vault01` ; comportement d'ESO 2.13 contre OpenBao (adoption d'un Secret existant, générateur `VaultDynamicSecret` avec la méthode `kubernetes`, modèles `engineVersion: v2`, cache de jetons) — le fournisseur OpenBao d'ESO est classé *alpha* ; Reloader 1.4.22 sur un `Rollout` en `workloadRef` (stratégie `restart`) et absence de dérive dans Argo CD après `spec.restartAt` ; options d'appartenance de `openbao` conservées après une réconciliation de CloudNativePG ; Service géré par CNPG avec l'annotation de Cilium LB IPAM ; ClusterIssuer `vault` de cert-manager contre OpenBao (contenu de `ca.crt`) ; image distroless de ghostunnel (utilisateur) en conteneur annexe natif ; deux clés d'accès IAM simultanées sur le RGW ; lookups de `community.hashi_vault` 7.1 contre OpenBao.

**Où lancer les commandes.** `admin@adm01:~$` avec ta session OIDC (`bao login -method=oidc`) et ton kubeconfig personnel ; `admin@adm01:~/src/<projet>$` dans les copies des projets ; `admin@vault01:~$` sur le coffre. Toute configuration du coffre passe par une MR de `plateforme/secrets` (à partir d'E10, appliquée par son pipeline), tout objet du cluster par Argo CD ou `task appliquer`.

---

### M25-E10 — La CI sans secret durable : jetons d'identité de GitLab

**Solution**

Fichiers : `plateforme/secrets` : [`tofu/auth-gitlab.tf`](fichiers/M25-E10/secrets/tofu/auth-gitlab.tf), [`tofu/projets-gitlab.auto.tfvars`](fichiers/M25-E10/secrets/tofu/projets-gitlab.auto.tfvars), politiques [`ci-mediagenda-api`](fichiers/M25-E10/secrets/politiques/ci-mediagenda-api.hcl), [`ci-mediagenda-api-promotion`](fichiers/M25-E10/secrets/politiques/ci-mediagenda-api-promotion.hcl), [`ci-medidoc-medidoc`](fichiers/M25-E10/secrets/politiques/ci-medidoc-medidoc.hcl) (et `-promotion`), [`tofu-secrets`](fichiers/M25-E10/secrets/politiques/tofu-secrets.hcl), [`wb-checks` (extrait)](fichiers/M25-E10/secrets/politiques/wb-checks.hcl.extrait), [`.gitlab-ci.yml`](fichiers/M25-E10/secrets/.gitlab-ci.yml), [`outils/openbao-ci.sh`](fichiers/M25-E10/secrets/outils/openbao-ci.sh), [`outils/etat-depuis-openbao.sh`](fichiers/M25-E10/secrets/outils/etat-depuis-openbao.sh) ; `plateforme/ci-templates` : [image](fichiers/M25-E10/ci-templates/images/outils-supply-chain/Dockerfile.extrait), [`securite` v2.9.0](fichiers/M25-E10/ci-templates/templates/securite/template.yml.extrait), [`promotion` v2.8.0](fichiers/M25-E10/ci-templates/templates/promotion/template.yml.extrait), [`release` v2.1.0](fichiers/M25-E10/ci-templates/templates/release/template.yml.extrait) ; [`mediagenda/api`](fichiers/M25-E10/mediagenda-api/.gitlab-ci.yml.extrait), [`formation/ci-labo`](fichiers/M25-E10/ci-labo/.gitlab-ci.yml.extrait) ; `plateforme/ansible` : rôle [`openbao_client`](fichiers/M25-E10/ansible/roles/openbao_client/), [playbook](fichiers/M25-E10/ansible/playbooks/outils-openbao.yml), [flux](fichiers/M25-E10/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; documentation [`ci-et-openbao.md`](fichiers/M25-E10/medisphere/docs/securite/secrets/ci-et-openbao.md), [`secrets-ci.md` (extrait)](fichiers/M25-E10/medisphere/docs/livraison/ci/secrets-ci.md.extrait) ; modèles [`conception.md`](fichiers/M25-E10/essais/conception.md), [`essais.md`](fichiers/M25-E10/essais/essais.md).

1. **Conception** ([modèle](fichiers/M25-E10/essais/conception.md)). Les trois réponses : `project_id` ne change pas avec le chemin et n'est jamais réattribué ; `ref_protected` seul accepterait toute branche protégée et `ref` seul ne dit rien de la protection ; `sub` (`project_path:…:ref_type:…:ref:…`) ne contient ni la protection, ni l'environnement, ni le runner. Types : dans le jeton de GitLab, `project_id` et `ref_protected` sont des **chaînes** (`"42"`, `"true"`, relevé du M19-E25).
2. **Méthode `gitlab/`.** Avant d'écrire, vérifie que le coffre joint la découverte :
   ```
   admin@vault01:~$ curl -s https://git01.par1.medisphere.internal/.well-known/openid-configuration | jq -r .jwks_uri
   https://git01.par1.medisphere.internal/oauth/discovery/keys
   ```
   Puis [`auth-gitlab.tf`](fichiers/M25-E10/secrets/tofu/auth-gitlab.tf) : `oidc_discovery_url` = l'émetteur (OpenBao lit lui-même `jwks_uri`), `oidc_discovery_ca_pem` = racine MédiSphère, `bound_issuer`. La politique `wb-checks` (qui lit déjà la configuration des méthodes et des rôles depuis le palier 1) reçoit les blocs de [l'extrait](fichiers/M25-E10/secrets/politiques/wb-checks.hcl.extrait) ; noter que **lister des baux exige `sudo`** sur `sys/leases/lookup/…` (essayé : `list` seul est refusé), d'où un `sudo` limité au préfixe `db-mediagenda/`.
3. **Rôles et politiques.** Une table `roles_ci` et une ressource `vault_jwt_auth_backend_role` par entrée. Points qui comptent : `bound_audiences = ["openbao.medisphere.internal"]` ; `bound_claims_type = "glob"` et des listes (`ref = "main,v*"` : le fournisseur découpe sur la virgule et envoie une liste ; une liste vaut « l'une des valeurs ») ; `ref_protected = "true"` ; pour `…-promotion`, `environment = "promotion/*"` ; `user_claim = "project_path"` (une entité par projet) et `claim_mappings` (référence, pipeline, job, utilisateur recopiés en métadonnées du jeton, donc dans l'audit d'E21) ; jeton **de service** de 600 s (`token_explicit_max_ttl`) : révocable, avec accesseur (RB-250). Essai sur le banc avec des jetons forgés :
   ```
   {} (main, protégée)                        → accepté, politiques ci-mediagenda-api,default, ttl 599
   {"ref":"v1.2.0","ref_type":"tag"}          → accepté
   {"ref_protected":"false","ref":"essai"}    → error validating claims: claim "ref_protected" does not match any associated bound claim values
   {"aud":"autre"}                            → invalid audience (aud) claim: audience claim does not match any expected audience
   {"project_id":"43"}                        → claim "project_id" does not match any associated bound claim values
   ```
   Contrôle des politiques : un administrateur ne peut pas se fabriquer un jeton porteur d'une politique qu'il n'a pas (il faudrait `sudo` sur `auth/token/create`) ; on contrôle donc **depuis un job**, avec le vrai jeton du rôle (job d'essai de l'étape 6, ou une ligne temporaire dans un job de `main`) :
   ```
   $ bao token capabilities kv/data/mediagenda/ci/promotion      # dans le job, rôle ci-mediagenda-api
   deny
   ```
4. **Recopier sans afficher.** La plateforme **dépose** les secrets des applications sans pouvoir les relire : [extrait de `plateforme-admin`](fichiers/M25-E10/secrets/politiques/plateforme-admin.hcl.extrait), écriture seule (`create`, `update`) sur `kv/data/mediagenda/*` et `kv/data/medidoc/*` (essayé : `kv put` réussit, `kv get` est refusé ; et une règle `kv/data/+/ci/*` aurait perdu face au `kv/metadata/*` du palier 1, les `+` abaissant la priorité d'une règle). Depuis l'interface de GitLab, la valeur d'une variable *cachée* n'est plus lisible : c'est l'occasion de **régénérer** (jeton `ci-promotion` de `mediagenda/deploiement`, robot Harbor par OpenTofu `registre/`, jeton `bot-release`). La nouvelle valeur va directement au coffre, par l'entrée standard :
   ```
   admin@adm01:~$ read -rs -p "jeton ci-promotion : " v; printf '{"jeton":"%s"}' "$v" | bao kv put -mount=kv mediagenda/ci/promotion -; unset v
   admin@adm01:~$ bao kv metadata put -mount=kv -max-versions=10 -custom-metadata=ticket=SEC-2610 mediagenda/ci/promotion
   ```
   (`read -s` : rien à l'écran, rien dans l'historique ; `printf` est une commande interne du shell : pas de processus dont les arguments seraient visibles.) Même chose pour `plateforme/harbor/robot-ci` (`utilisateur`, `jeton`), `mediagenda/ci/release`, ceux de MédiDoc, et `plateforme/tofu/etat-secrets` (identité S3 `tofu-etat` et phrase de chiffrement, depuis `~/.config/workbook/` d'E08).
5. **Composant.** Image 1.1.0 ([extrait](fichiers/M25-E10/ci-templates/images/outils-supply-chain/Dockerfile.extrait)) : archive `openbao_2.6.4_linux_amd64.tar.gz`, empreinte `659a4875…f6d84220` relevée dans `checksums.txt` de la version (binaire seul : le `.deb` installerait aussi l'unité du serveur). Composant `securite` v2.9.0 ([extrait](fichiers/M25-E10/ci-templates/templates/securite/template.yml.extrait)) : `.openbao-connexion` déclare `id_tokens` (`OPENBAO_ID_TOKEN`, audience fixée), se connecte au rôle `ci-<groupe>-<projet>` déduit de `CI_PROJECT_PATH`, écrit le jeton dans `~/.vault-token` du pod (la CLI le lit seule ; `after_script`, qui tourne dans un autre shell, le retrouve pour `bao token revoke -self`). Les jobs lisent le robot Harbor par `bao kv get -field=…` dans des variables **du shell** (jamais déclarées comme variables GitLab, donc jamais exportées vers un artefact) et passent le jeton à `cosign login --password-stdin`. Composant `promotion` v2.8.0 : rôle `…-promotion` (seul ce job a l'environnement `promotion/*`). Composant `release` v2.1.0 : l'image Node n'a ni `bao` ni `jq`, la connexion passe par `curl` et `node` (corps par l'entrée standard, en-tête `X-Vault-Token` par `curl -K -`).
6. **Essai du refus** ([modèle](fichiers/M25-E10/essais/essais.md)). Sur `essai-oidc` (non protégée) : `error validating claims: claim "ref_protected" does not match any associated bound claim values` ; sur `main` : accès. Le rôle et le secret d'essai sont retirés par MR.
7. **Migration.** `mediagenda/api` passe aux nouvelles versions ([extrait](fichiers/M25-E10/mediagenda-api/.gitlab-ci.yml.extrait)) ; pipeline de `main` vert **de bout en bout** (signature, attestations, promotion vers `dev`) avant de supprimer `DEPLOIEMENT_TOKEN`, `GITLAB_TOKEN` du projet et `HARBOR_ROBOT_*` des groupes `mediagenda` et `medidoc` ; l'ancien jeton `ci-promotion` est révoqué dans GitLab (*Settings → Access tokens*), l'ancien robot désactivé après la dernière publication.
8. **`plateforme/secrets` se gère lui-même.** `outils-openbao.yml` sur `runner01` (rôle [`openbao_client`](fichiers/M25-E10/ansible/roles/openbao_client/) : archive vérifiée, binaire seul, `bao version` contrôlée) ; [pipeline](fichiers/M25-E10/secrets/.gitlab-ci.yml) : `before_script` = [`openbao-ci.sh`](fichiers/M25-E10/secrets/outils/openbao-ci.sh) (jeton d'identité par l'entrée standard, jeton OpenBao dans `$CI_PROJECT_DIR/.bao-jeton` en 600 — **pas** dans `$HOME`, partagé par tous les jobs d'un exécuteur `shell` —, exporté en `BAO_TOKEN` et `VAULT_TOKEN`) puis [`etat-depuis-openbao.sh`](fichiers/M25-E10/secrets/outils/etat-depuis-openbao.sh) (accès à l'état lus dans le coffre). Le fournisseur `vault` crée par défaut un jeton enfant (`auth/token/create`), ce que la politique `tofu-secrets` ne permet pas et qui n'a pas de sens pour un jeton de 10 min : le pipeline pose `TERRAFORM_VAULT_SKIP_CHILD_TOKEN: "true"` (variable lue par le fournisseur, équivalente à `skip_child_token`) ; `fournisseurs.tf` ne change pas et `adm01` garde son jeton enfant. Premier `apply` du pipeline : un plan qui ne touche **rien** (le code déjà appliqué depuis `adm01`), pour éprouver la chaîne avant qu'elle n'applique un vrai changement.
9. **Documenter** : [`ci-et-openbao.md`](fichiers/M25-E10/medisphere/docs/securite/secrets/ci-et-openbao.md), [`secrets-ci.md`](fichiers/M25-E10/medisphere/docs/livraison/ci/secrets-ci.md.extrait), inventaire E02 (lignes « robot Harbor », « jetons de promotion » : état « migré »).

**Explications**

Le jeton d'identité inverse le modèle : le job ne **détient** rien, il **prouve** qui il est par une signature de GitLab, et le coffre décide. OpenBao vérifie la signature (clés lues par la découverte), l'émetteur, l'audience, les dates, puis chaque revendication liée ; il délivre un jeton OpenBao de dix minutes porteur des seules politiques du rôle. Un jeton d'identité volé dans un journal ne sert à rien ailleurs (audience) ni longtemps (5 min) ; un jeton OpenBao volé dure dix minutes et se révoque par son accesseur. Ce qui reste critique : GitLab lui-même (qui peut pousser sur `main` peut lire ces secrets) — d'où la protection des branches, les approbations, et l'audit des lectures (E21).

**Alternatives**
- `secrets:vault` de GitLab : la même chose en déclaratif, **Premium** ; écarté (CE).
- `jwks_url` au lieu de la découverte : équivalent pour la signature ; la découverte suit d'elle-même l'URL des clés. `jwt_validation_pubkeys` (clé recopiée) : à proscrire (rotation des clés de GitLab = panne).
- Jeton *batch* (plus léger, non stocké dans Raft) : sans accesseur, il ne se révoque pas un par un ; écarté pour pouvoir appliquer RB-250.
- AppRole pour la CI : un `secret_id` à stocker dans GitLab… c'est-à-dire le secret durable qu'on veut supprimer (secret zéro).

**Pièges classiques**
- `bound_claims = { ref_protected = true }` en booléen : refus de tous les jobs, la revendication est une chaîne.
- `bound_claims` en type `string` avec `ref = "v*"` : l'astérisque est littéral ; il faut `glob`.
- `jwt=$OPENBAO_ID_TOKEN` en argument : visible dans `ps` de tout le pod (et d'un `CI_DEBUG_TRACE`) ; `jwt=-` et l'entrée standard.
- Jeton OpenBao écrit dans `~/.vault-token` sur `runner01` : partagé entre jobs concurrents, et il survit au job.
- `set -x` dans un script de job qui lit un secret : la variable du shell n'est pas une variable GitLab, **le masquage ne la couvre pas**.
- Oublier `TERRAFORM_VAULT_SKIP_CHILD_TOKEN` dans le pipeline de `plateforme/secrets` : `permission denied` sur `auth/token/create` au premier `plan`.
- Supprimer les variables de groupe avant que **tous** les projets du groupe soient migrés : le pipeline d'un projet oublié casse à la publication suivante.

**En production chez MédiSphère**
Un rôle par projet créé à la demande par MR ; revue trimestrielle des rôles et des politiques `ci-*` (projets archivés, chemins morts) ; alerte sur un pic de refus de connexion `gitlab/` (E27) ; liaison du jeton de signature au runner protégé (`runner_id`, E20) ; identités de lecture `*_RO_*` dans le coffre avec un rôle sans contrainte de protection (mini-projet).

---

### M25-E11 — Ansible lit ses secrets dans OpenBao

**Solution**

Fichiers : `plateforme/secrets` : [`ansible-lab.hcl`](fichiers/M25-E11/secrets/politiques/ansible-lab.hcl), [`ansible-critique.hcl`](fichiers/M25-E11/secrets/politiques/ansible-critique.hcl), [`tofu/ci-ansible.tf`](fichiers/M25-E11/secrets/tofu/ci-ansible.tf), [groupes Keycloak (extrait)](fichiers/M25-E11/secrets/tofu/variables.tf.extrait) ; `plateforme/ansible` : [`outils/vault-pass-client.sh`](fichiers/M25-E11/ansible/outils/vault-pass-client.sh), [`outils/openbao-ci.sh`](fichiers/M25-E11/ansible/outils/openbao-ci.sh), [`ansible.cfg` (extrait)](fichiers/M25-E11/ansible/ansible.cfg.extrait), [`requirements.yml` (extrait)](fichiers/M25-E11/ansible/collections/requirements.yml.extrait), [`host_vars/mon01/mailpit.yml`](fichiers/M25-E11/ansible/inventories/lab/host_vars/mon01/mailpit.yml), [`.gitlab-ci.yml` (extrait)](fichiers/M25-E11/ansible/.gitlab-ci.yml.extrait) ; [`ansible-et-openbao.md`](fichiers/M25-E11/medisphere/docs/securite/secrets/ansible-et-openbao.md) ; [modèle de conception](fichiers/M25-E11/essais/conception.md).

1. **Le découpage.** Une politique accorde un chemin et toutes ses clés : deux secrets. Recopie depuis les fichiers actuels, sans affichage :
   ```
   admin@adm01:~$ for id in lab critique; do f=~/.config/workbook/ansible-vault-$id.pass; [ "$id" = lab ] && [ ! -e "$f" ] && f=~/.config/workbook/ansible-vault.pass
       jq -Rn --rawfile v "$f" '{"mot-de-passe": ($v | rtrimstr("\n"))}' | bao kv put -mount=kv "plateforme/ansible-vault/$id" -; done
   ```
   (`jq --rawfile` lit le fichier lui-même : la valeur ne passe dans aucun argument.)
2. **Politiques et rôles** (`ci-plateforme-ansible` : `main`, `conf/*` ; `ci-plateforme-ansible-critique` : `main` **et** `environment = "lab/socle"`, avec `ansible-lab` + `ansible-critique`, puisque `appliquer` déchiffre les deux identités ; le groupe Keycloak `plateforme` reçoit `ansible-lab` par la variable `groupes_keycloak` du palier 1). Contrôle dans un job d'essai de `conf/essai-openbao` (rôle `ci-plateforme-ansible`) : `bao token capabilities kv/data/plateforme/ansible-vault/critique` → `deny`, `…/lab` → `read`.
3. **Le script** ([`vault-pass-client.sh`](fichiers/M25-E11/ansible/outils/vault-pass-client.sh)). Même contrat (`--vault-id`, sortie standard, codes 0/1/2). Ordre : `VAULT_PASS_SECOURS=1` → anciennes sources seulement ; sinon `bao token lookup` (jeton valide ?) puis `bao kv get -mount=kv -field=mot-de-passe plateforme/ansible-vault/<id>`. Le script ne se connecte jamais lui-même (il n'aurait aucun secret pour le faire). Essai sur le banc :
   ```
   jeton ansible-lab, --vault-id lab        → mot de passe sur la sortie, code 0
   jeton ansible-lab, --vault-id critique   → « OpenBao refuse kv/plateforme/ansible-vault/critique (politique … absente de ton jeton ?) », code 1
   jeton invalide                           → « pas de jeton OpenBao valide… Connecte-toi : bao login -method=oidc », code 1
   ```
4. **Le pipeline** ([extrait](fichiers/M25-E11/ansible/.gitlab-ci.yml.extrait)). `.socle` et `.molecule` déclarent `id_tokens` et sourcent `openbao-ci.sh <rôle>` (copie de celui de `plateforme/secrets`) **avant** `ansible-playbook` : Ansible lance le script client dans le même environnement, qui trouve `BAO_TOKEN`. `appliquer` et `derive` prennent le rôle `critique`. Ordre de bascule : MR, pipeline de `main` vert **y compris `appliquer`** (lancé à la main, sur un changement anodin) ; ensuite seulement, suppression de `VAULT_PASS_LAB` et `VAULT_PASS_CRITIQUE`.
5. **Bris de glace** ([procédure](fichiers/M25-E11/medisphere/docs/securite/secrets/ansible-et-openbao.md), §3). Copie des deux mots de passe chiffrée par `age` pour les dépositaires (même support que les parts d'E03), déchiffrée dans `/dev/shm` (mémoire), passée par `VAULT_PASS_SECOURS=1 VAULT_PASS_CRITIQUE=<fichier>`, puis `shred`. Essai : `BAO_ADDR=https://127.0.0.1:1` (coffre injoignable) → refus clair ; secours → `--check` réussi. Ensuite seulement : `shred -u ~/.config/workbook/ansible-vault*.pass`.
6. **Un lookup.** `community.hashi_vault` 7.1.0 et `uv add hvac` ; `ansible.cfg` : section `[hashi_vault_collection]`, `url` et `ca_cert` ([extrait](fichiers/M25-E11/ansible/ansible.cfg.extrait)). Comptes de Mailpit recopiés (`kv/plateforme/mailpit/comptes`, clés `moi` et `wb-checks`, depuis `ansible-vault view` par un tube vers `yq` puis `bao kv put … -`), lus par `vault_kv2_get` ([`mailpit.yml`](fichiers/M25-E11/ansible/inventories/lab/host_vars/mon01/mailpit.yml)) ; `--check --diff --limit mon01` : aucun changement ; les deux variables quittent `host_vars/mon01/vault.yml`.

**Explications**

Le mot de passe d'Ansible Vault est un **secret qui protège des secrets** : le servir par le coffre déplace le contrôle d'accès (qui, quand, depuis où) là où il est journalisé, et le rend révocable par personne. Les fichiers chiffrés restent utiles pour l'**amorçage** : ce qu'il faut pour réparer le coffre lui-même ne peut pas dépendre du coffre. Le lookup, lui, supprime le fichier chiffré pour un secret donné : la valeur n'est plus dans Git du tout, même chiffrée. Côté technique, le lookup n'utilise pas la CLI mais `hvac` (Python, `requests`), qui ignore le magasin d'autorités du système : sans `ca_cert`, la racine MédiSphère n'est pas reconnue.

**Alternatives**
- AppRole pour le pipeline (rôles `ansible-lab`/`ansible-critique` avec `secret_id` en variable protégée) : fonctionne, mais remet un secret durable dans GitLab ; écarté au profit de la méthode `gitlab/` d'E10 (même règle pour toute la CI). AppRole reste la bonne réponse pour un ordonnanceur hors GitLab (Semaphore, cron sur un hôte) : `secret_id` livré par enveloppement de réponse (E28).
- Agent OpenBao (`bao agent`) sur `adm01` : cache de jeton, rendu de fichiers ; utile pour un service, pas pour des sessions humaines courtes.

**Pièges classiques**
- Un seul secret avec deux clés `lab`/`critique` : la politique de Lucas lit `critique`.
- `VAULT_PASS_CRITIQUE` supprimée avant un `appliquer` réussi : le premier changement urgent bloque.
- `vault_kv2_get` sans `engine_mount_point='kv'` : la collection cherche `secret/` (défaut) et répond « permission denied » ou « not found ».
- `--check` qui « change » tout après le passage au lookup : une valeur relue différente (espace final, clé mal nommée) ; comparer les empreintes avant de retirer l'ancienne variable.
- Garder une copie « provisoire » du mot de passe en clair « au cas où » : c'est elle qui fuit.

**En production chez MédiSphère**
Rotation annuelle des deux mots de passe Ansible Vault (script de `rekey` + nouvelle version KV, E33) ; migration progressive des variables `vault_*` vers des lookups, inventaire tenu dans `ansible-et-openbao.md` §5 ; alerte sur la lecture de `ansible-vault/critique` hors des jobs `appliquer`/`derive` et des administrateurs (E21).

---

### M25-E12 — Méthode Kubernetes et External Secrets Operator

**Solution**

Fichiers : `plateforme/secrets` : [`tofu/auth-k8s-par1.tf`](fichiers/M25-E12/secrets/tofu/auth-k8s-par1.tf), [`eso-wb-essais.hcl`](fichiers/M25-E12/secrets/politiques/eso-wb-essais.hcl), [`eso-plateforme.hcl` (E12)](fichiers/M25-E12/secrets/politiques/eso-plateforme.hcl) ; `plateforme/k8s` : [`espaces/external-secrets.yaml`](fichiers/M25-E12/k8s/espaces/external-secrets.yaml), [`espaces/wb-essais/80-openbao.yaml`](fichiers/M25-E12/k8s/espaces/wb-essais/80-openbao.yaml), [`rbac/openbao-auth-delegator.yaml`](fichiers/M25-E12/k8s/rbac/openbao-auth-delegator.yaml), [`rbac/wb-checks-securite` (extrait)](fichiers/M25-E12/k8s/rbac/wb-checks-securite.yaml.extrait) ; [`charts.yaml` (extrait)](fichiers/M25-E12/charts-miroir/charts.yaml.extrait) ; `plateforme/gitops` : [Application](fichiers/M25-E12/gitops/plateforme/external-secrets.yaml), [valeurs](fichiers/M25-E12/gitops/valeurs/external-secrets/values.yaml), [ClusterSecretStore](fichiers/M25-E12/gitops/manifestes/external-secrets/clustersecretstore.yaml), [politique réseau](fichiers/M25-E12/gitops/manifestes/external-secrets/reseau.yaml) ; [flux](fichiers/M25-E12/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [matrice](fichiers/M25-E12/medisphere/docs/socle/matrice-flux.md.extrait) ; modèles [`conception.md`](fichiers/M25-E12/essais/conception.md), [`rbac-eso.md`](fichiers/M25-E12/essais/rbac-eso.md), [`premier-secret.yaml`](fichiers/M25-E12/essais/premier-secret.yaml).

1. **La méthode** ([conception](fichiers/M25-E12/essais/conception.md)). CA du cluster depuis ton kubeconfig :
   ```
   admin@adm01:~$ kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ~/src/secrets/racine/k8s-par1-ca.crt
   ```
   Choix retenu : **jeton du client** pour TokenReview (`token_reviewer_jwt` vide ; le texte d'aide d'OpenBao 2.6 le dit : « If not set the JWT used for login will be used to access the API ») ; donc `system:auth-delegator` pour chaque compte client. Flux `vault01-03` → 10.10.40.200:8443 (une passerelle à la fois).
2. **Premier essai, sans ESO.** Compte `eso` de `wb-essais` (par `task appliquer`), rôle `eso-wb-essais`, lecture et écriture de `kv/wb-essais/*` pour les administrateurs ([extrait de `plateforme-admin`](fichiers/M25-E12/secrets/politiques/plateforme-admin.hcl.extrait)), puis :
   ```
   admin@adm01:~$ kubectl -n wb-essais create token eso --audience openbao.medisphere.internal --duration 10m \
       | bao write auth/k8s-par1/login role=eso-wb-essais jwt=-
   ```
   Refus attendus (messages du code de la méthode) : compte `default` → `service account name not authorized` ; sans `--audience` → `invalid audience (aud) claim…` ; compte `eso` d'un autre espace → `namespace not authorized`.
3. **ESO.** Chart 2.13.0 recopié par `charts-miroir` (empreinte `f693a96f…bcac3a`) ; [valeurs](fichiers/M25-E12/gitops/valeurs/external-secrets/values.yaml) : images par le cache `ghcr` (`global.repository`), `crds.unsafeServeV1Beta1: false`, `systemAuthDelegator: true` (le compte du contrôleur est celui du ClusterSecretStore), cache des jetons OpenBao (`vault.enableTokenCache`), contrôleurs « Cluster » et `PushSecret` désactivés, ServiceMonitor étiqueté pour le M21. Lecture du rendu :
   ```
   admin@adm01:~$ helm template external-secrets oci://registry.par1.medisphere.internal/charts/external-secrets --version 2.13.0 \
       -n external-secrets -f ~/src/gitops/valeurs/external-secrets/values.yaml > /tmp/eso.yaml
   admin@adm01:~$ yq 'select(.kind == "CustomResourceDefinition") | .metadata.name + " " + ([.spec.versions[] | .name + ":" + (.served | tostring)] | join(","))' /tmp/eso.yaml
   ```
   `externalsecrets`, `secretstores`, `clustersecretstores` : `v1:true,v1beta1:false` ; `pushsecrets` : `v1alpha1` ; générateurs : `v1alpha1`. ClusterRole du contrôleur : **tous les Secrets du cluster** en lecture et écriture ([`rbac-eso.md`](fichiers/M25-E12/essais/rbac-eso.md)).
4. **Les magasins.** [ClusterSecretStore](fichiers/M25-E12/gitops/manifestes/external-secrets/clustersecretstore.yaml) (vague 1, `SkipDryRunOnMissingResource`, `conditions.namespaces` = espaces de plateforme d'E13) et [SecretStore de `wb-essais`](fichiers/M25-E12/k8s/espaces/wb-essais/80-openbao.yaml). Particularités du fournisseur `vault` d'ESO : `path: kv` (le **moteur**, sans `data/`) et `version: v2` ; `mountPath: k8s-par1` (sans `/v1/auth/`) ; `serviceAccountRef.audiences` ; `caBundle` en base64 (ESO n'utilise pas le magasin du nœud).
   ```
   admin@adm01:~$ kubectl get clustersecretstore openbao -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
   True
   ```
5. **Le premier Secret.** Valeur aléatoire par l'entrée standard, puis l'[ExternalSecret](fichiers/M25-E12/essais/premier-secret.yaml) (dans `wb-essais`, `kubectl apply` permis). Changement de valeur : visible au plus tard après `refreshInterval` (1 min ici) ; relecture immédiate : `kubectl -n wb-essais annotate externalsecret premier-secret force-sync=$(date +%s) --overwrite`. Suppression de l'ExternalSecret : le Secret **reste** (`deletionPolicy: Retain`)… sauf qu'avec `creationPolicy: Owner`, il porte une `ownerReference` vers l'ExternalSecret : le ramasse-miettes de Kubernetes le supprime. C'est la différence entre la politique d'ESO (ce que l'opérateur fait) et le propriétaire (ce que fait Kubernetes) : pour garder le Secret, supprimer avec `--cascade=orphan`.
6. **Droits des checks** ([extrait](fichiers/M25-E12/k8s/rbac/wb-checks-securite.yaml.extrait)) : la ClusterRole du M24-E16 couvre déjà les objets principaux d'ESO ; ajout des générateurs (sans `generatorstates`, qui peut garder des valeurs produites), `clusterpushsecrets` et des objets de cert-manager (E16).
   ```
   admin@adm01:~$ kubectl auth can-i list externalsecrets.external-secrets.io -n wb-essais --as=system:serviceaccount:wb-system:wb-checks
   yes
   admin@adm01:~$ kubectl auth can-i get secrets -n wb-essais --as=system:serviceaccount:wb-system:wb-checks
   no
   ```

**Explications**

La méthode `kubernetes` ne garde aucun secret : le pod présente un jeton **projeté** (court, d'audience choisie, lié au pod) ; OpenBao vérifie l'audience et demande à l'API si le jeton est valide et à qui il appartient (TokenReview), puis compare le compte et l'espace au rôle. ESO fait cela pour le compte du pod : il demande lui-même (TokenRequest) un jeton pour le compte référencé par le magasin, se connecte, lit, écrit un Secret. La sécurité tient donc à trois choses : qui peut créer ou modifier un magasin (la plateforme), quel compte il référence (un compte par espace), et ce que la politique du rôle permet (un chemin par espace).

**Alternatives**
- Jeton de vérification dédié (`openbao-tokenreview`) : un droit RBAC unique, mais un jeton longue durée dans la configuration du coffre (et ses sauvegardes) ; écarté.
- Méthode `jwt` sur la découverte OIDC du serveur d'API : aucun flux vers l'API ni droit RBAC, mais un jeton reste valide jusqu'à son expiration même si le pod ou le compte disparaît.
- Injecteur `openbao-k8s` (agent en conteneur annexe qui écrit des fichiers) ou pilote CSI (E19) : pas de Secret Kubernetes du tout, mais un composant par pod, et l'application doit lire des fichiers.
- vault-secrets-operator de HashiCorp : prévu pour Vault, usage avec OpenBao non documenté.

**Pièges classiques**
- `path: kv/data` dans le magasin : ESO ajoute `data/`, le chemin devient `kv/data/data/…` (« permission denied » ou secret introuvable : panne E37).
- `mountPath: /v1/auth/k8s-par1` dans ESO (c'est la syntaxe de **cert-manager**, E16) : échec de connexion.
- Oublier `audiences` : le jeton porte l'audience de l'API du cluster, le rôle le refuse.
- Une politique réseau en sortie sur les pods d'ESO sans le DNS ou sans l'API : l'opérateur ne démarre plus ses contrôleurs (journaux : délai de connexion).
- Supprimer l'Application `external-secrets` avec cascade : les CRD partent, tous les ExternalSecret avec, et par leurs `ownerReferences` tous les Secrets qu'ils possèdent.

**En production chez MédiSphère**
ESO suit les mineures du projet (seule la dernière est maintenue) ; supervision de `externalsecret_status_condition` et des erreurs de magasin (E27) ; espace et images d'ESO surveillés comme ceux d'Argo CD (Falco, M26) ; Kyverno (M26) interdit aux équipes `SecretStore`, `ClusterSecretStore` et générateurs, en plus des AppProjects.

---

### M25-E13 — Migrer les Secrets hors Git vers des ExternalSecret

**Solution**

Fichiers : [`outils/secret-vers-openbao.sh`](fichiers/M25-E13/k8s/outils/secret-vers-openbao.sh) et [`secrets-k8s.conf`](fichiers/M25-E13/k8s/outils/secrets-k8s.conf) de `plateforme/k8s`, [`espaces/<espace>/80-openbao.yaml`](fichiers/M25-E13/k8s/espaces/), [`rbac/openbao-auth-delegator.yaml`](fichiers/M25-E13/k8s/rbac/openbao-auth-delegator.yaml) ; `plateforme/gitops` : [Application `secrets-plateforme`](fichiers/M25-E13/gitops/plateforme/secrets-plateforme.yaml), [ExternalSecret `secrets/<espace>/`](fichiers/M25-E13/gitops/secrets/), [AppProjects (extrait)](fichiers/M25-E13/gitops/projets/applications.extrait.yaml) ; `plateforme/secrets` : [`eso-plateforme.hcl`](fichiers/M25-E13/secrets/politiques/eso-plateforme.hcl), [gabarit `eso-espace`](fichiers/M25-E13/secrets/politiques/eso-espace.hcl.tftpl), [`tofu/eso-espaces.tf`](fichiers/M25-E13/secrets/tofu/eso-espaces.tf) ; [`mediagenda/deploiement`](fichiers/M25-E13/deploiement/overlays/) et [`medidoc/deploiement`](fichiers/M25-E13/medidoc-deploiement/overlays/) ; [inventaire](fichiers/M25-E13/medisphere/docs/securite/secrets/inventaire-secrets.md.extrait) ; modèles [`inventaire.md`](fichiers/M25-E13/essais/inventaire.md), [`comparaison.md`](fichiers/M25-E13/essais/comparaison.md).

1. **Inventaire** ([modèle](fichiers/M25-E13/essais/inventaire.md)) :
   ```
   admin@adm01:~$ kubectl get secrets -A -l medisphere.internal/source=ansible-vault -o json \
       | jq -r '.items[] | [.metadata.namespace, .metadata.name, (.data | keys | join(","))] | @tsv'
   ```
   Noms et clés, jamais les valeurs. On ajoute ce que d'autres scripts ont créé (registre) et on classe : à migrer maintenant (plateforme d'observabilité, Argo CD, runners, agent, OAuth2 Proxy ; applications), plus tard (couche de base : Velero, CNPG, cert-manager, ExternalDNS, ceph-csi : mini-projet), ailleurs (clé Cosign : E20), jamais (racine publique).
2. **L'outil** ([`secret-vers-openbao.sh`](fichiers/M25-E13/k8s/outils/secret-vers-openbao.sh)) : `kubectl get secret -o json | jq '.data | map_values(@base64d)' | bao kv put … -` ; refus d'écraser un chemin qui a des versions (`bao kv metadata get`) ; refus d'une valeur non UTF-8 (`@base64d` l'altérerait) ; métadonnées personnalisées (origine, ticket) ; `comparer` : empreinte SHA-256 de chaque clé des deux côtés.
3. **La plateforme**, un Secret à la fois, en commençant par `supervision/grafana-admin` (lu une seule fois, à la création de la base : sans risque) :
   ```
   admin@adm01:~/src/k8s$ outils/secret-vers-openbao.sh copier supervision grafana-admin plateforme/grafana/admin
   [OK] supervision/grafana-admin → kv/plateforme/grafana/admin (admin-password, admin-user)
   [OK] admin-password : empreinte 7e2b684e62d926b0
   [OK] admin-user : empreinte 8c6976e5b5410415
   ```
   Puis le chemin dans [`eso-plateforme.hcl`](fichiers/M25-E13/secrets/politiques/eso-plateforme.hcl) (MR `plateforme/secrets`), l'ExternalSecret [`secrets/supervision/grafana-admin.yaml`](fichiers/M25-E13/gitops/secrets/supervision/grafana-admin.yaml) (MR `plateforme/gitops`), synchronisation de `secrets-plateforme`, et la vérification de l'adoption ([comparaison](fichiers/M25-E13/essais/comparaison.md)) : propriétaire `ExternalSecret`, étiquette `medisphere.internal/source: openbao`, données identiques, UID des pods inchangés. Pour Argo CD (`repo-creds-*`, `argocd-oidc`, `argocd-webhook-gitlab`), le modèle de l'ExternalSecret **repose les étiquettes fonctionnelles** (`argocd.argoproj.io/secret-type`, `app.kubernetes.io/part-of`) avec `mergePolicy: Merge` (sans `Merge`, un modèle qui ne pose que des étiquettes produit un Secret… vide). Argo CD en dernier, session `admin.conf` ouverte.
4. **Les équipes.** Par `plateforme/k8s` : compte `eso` et SecretStore `openbao` de chaque espace ([fichiers](fichiers/M25-E13/k8s/espaces/)), liaison `auth-delegator` ; par `plateforme/secrets` : rôles et politiques `eso-<espace>` générés par un gabarit ([`eso-espaces.tf`](fichiers/M25-E13/secrets/tofu/eso-espaces.tf)). Puis les ExternalSecret `harbor-pull` (modèle : `type: kubernetes.io/dockerconfigjson`, `Merge`) et `medidoc-s3` dans les overlays (MR relues par les équipes). Essai du cloisonnement : un ExternalSecret de `mediagenda-recette` qui vise `medidoc/recette/s3` reste en erreur (`SecretSyncedError`, « permission denied » dans le statut).
5. **Comparer** : pour chaque Secret de plateforme, `secret-vers-openbao.sh comparer` juste après la recopie ; pour **tous**, `secrets-k8s.sh verifier <composant>` après la synchronisation (il compare toujours le Vault Ansible au cluster : `[OK]` prouve que la valeur n'a pas bougé). Les secrets d'application sont déposés en écriture seule (E10) : le script le signale (`[--] comparaison impossible…`, code 3 converti en succès) et seule la seconde comparaison s'applique.
6. **Ranger** : [`secrets-k8s.conf`](fichiers/M25-E13/k8s/outils/secrets-k8s.conf) ne garde que l'amorçage ; les modules `secrets-k8s.d/*.sh` migrés sont renommés `.sh.migre` (le script ne charge que `*.sh`) ; [AppProjects](fichiers/M25-E13/gitops/projets/applications.extrait.yaml) : `harbor-pull` et `medidoc-s3` sortent de `orphanedResources.ignore` (ils sont suivis) ; `SecretStore`, `PushSecret` et générateurs entrent dans la liste noire des équipes.

**Explications**

ESO, en politique de création `Owner`, **adopte** un Secret existant qui n'a pas de propriétaire : il pose son `ownerReference` et réécrit les données. Si les clés et les valeurs sont identiques, aucun consommateur ne voit de différence et aucun pod ne redémarre : la migration est invisible. C'est pourquoi la recopie se fait **depuis le Secret du cluster** (la valeur réellement en service) et non depuis le Vault Ansible (qui pourrait avoir divergé). Le résultat : Git porte la référence (quoi, d'où, à quelle fréquence), Argo CD la compare et la répare, OpenBao porte la valeur et l'audit.

**Alternatives**
- Recopier depuis Ansible Vault (`ansible-vault view | yq | bao kv put -`) : correct si les deux sources sont identiques ; la comparaison `verifier` le dit.
- Un SecretStore par espace **aussi** pour la plateforme : meilleur cloisonnement (l'espace `traces` ne lirait pas les secrets d'`argocd`), plus d'objets ; à envisager au mini-projet.
- `ClusterExternalSecret` pour `harbor-pull` dans tous les espaces d'une équipe : un seul objet, mais un même secret partout (et les valeurs diffèrent par environnement ici).

**Pièges classiques**
- Clé renommée à la migration (`password` → `jeton`) : le pod en cours tourne, le **suivant** ne démarre plus (`CreateContainerConfigError`).
- Modèle sans `mergePolicy: Merge` : Secret vide, Argo CD perd ses dépôts.
- Oublier `type: kubernetes.io/dockerconfigjson` : Secret `Opaque`, tirage refusé au prochain nœud qui n'a pas l'image en cache.
- Supprimer un ExternalSecret « pour recommencer » : le ramasse-miettes supprime le Secret qu'il possède (`--cascade=orphan`).
- Ajouter `kv/data/plateforme/*` à `eso-plateforme` « pour aller vite » : tout espace de plateforme lit les mots de passe Ansible Vault et le robot Harbor de la CI.

**En production chez MédiSphère**
Alerte sur tout ExternalSecret non prêt depuis plus de 15 min et sur tout Secret sans propriétaire dans les espaces gérés (dérive : quelqu'un a recréé un Secret à la main) ; registre des secrets tenu par un outil qui lit les métadonnées KV et les ExternalSecret (E46) ; couche de base (Velero, CNPG, TSIG, ceph-csi) migrée au mini-projet par la même méthode.

---

### M25-E14 — Identifiants dynamiques PostgreSQL pour MédiAgenda

**Solution**

Fichiers : `plateforme/secrets` : [`tofu/db-mediagenda.tf`](fichiers/M25-E14/secrets/tofu/db-mediagenda.tf), [`tofu/imports-db.tf`](fichiers/M25-E14/secrets/tofu/imports-db.tf), [`politiques-mdp/postgresql-url.hcl`](fichiers/M25-E14/secrets/politiques-mdp/postgresql-url.hcl), [`eso-espaces.tf` (extrait)](fichiers/M25-E14/secrets/tofu/eso-espaces.tf.extrait) ; `plateforme/k8s` (recette) : [`50-mediagenda-db.yaml`](fichiers/M25-E14/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml), [`41-reseau-openbao.yaml`](fichiers/M25-E14/k8s/espaces/mediagenda-recette/41-reseau-openbao.yaml), [`45-openbao-pg-initial.yaml`](fichiers/M25-E14/k8s/espaces/mediagenda-recette/45-openbao-pg-initial.yaml), [`90-openbao-dynamique.yaml`](fichiers/M25-E14/k8s/espaces/mediagenda-recette/90-openbao-dynamique.yaml), [`sql/preparer-openbao.sql`](fichiers/M25-E14/k8s/espaces/mediagenda-recette/sql/preparer-openbao.sql) ; prod : [`espaces/mediagenda-prod/`](fichiers/M25-E14/k8s/espaces/mediagenda-prod/), [`overlays/prod/`](fichiers/M25-E14/deploiement/overlays/prod/) ; `mediagenda/deploiement` : [`components/identifiants-dynamiques`](fichiers/M25-E14/deploiement/components/identifiants-dynamiques/), [overlay de recette (extrait)](fichiers/M25-E14/deploiement/overlays/recette/kustomization.yaml.extrait) ; `plateforme/ansible` : [`ca-postgresql.yml`](fichiers/M25-E14/ansible/roles/openbao/tasks/ca-postgresql.yml), [variables](fichiers/M25-E14/ansible/inventories/lab/group_vars/role_coffre/openbao-postgresql.yml) ; [`identifiants-dynamiques.md`](fichiers/M25-E14/medisphere/docs/securite/secrets/identifiants-dynamiques.md) ; modèles [`banc.md`](fichiers/M25-E14/essais/banc.md), [`observations.md`](fichiers/M25-E14/essais/observations.md).

1. **Banc** ([modèle](fichiers/M25-E14/essais/banc.md)). Le résultat qui compte : la révocation d'un bail exécute `DROP ROLE`, et la session ouverte **casse** (`permission denied`, puis `invalid role OID`) ; une nouvelle connexion est refusée. Un pod doit donc changer d'identifiant avant la fin du bail.
2. **La base** ([`50-mediagenda-db.yaml`](fichiers/M25-E14/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml)) : `managed.roles` (`mediagenda_api` sans connexion ; `openbao` avec `createrole`, `inherit: false`, `inRoles: [mediagenda, mediagenda_api]`, `passwordSecret`), `managed.services.additional` (`selectorType: rw`, Service `mediagenda-db-openbao`, `lbipam.cilium.io/ips: 10.10.41.64`, `externalTrafficPolicy: Local`), [politique réseau](fichiers/M25-E14/k8s/espaces/mediagenda-recette/41-reseau-openbao.yaml). `inRoles` est **obligatoire** : CloudNativePG révoque les appartenances qui n'y figurent pas (« memberships not listed in inRoles are revoked »). Après `task appliquer` et la réconciliation (`kubectl -n mediagenda-recette get cluster mediagenda-db -o jsonpath='{.status.managedRolesStatus}'`), le SQL :
   ```
   admin@adm01:~/src/k8s$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -v ON_ERROR_STOP=1 \
       < espaces/mediagenda-recette/sql/preparer-openbao.sql
    role           | membre  | admin_option | inherit_option | set_option
    mediagenda     | openbao | t            | f              | f
    mediagenda_api | openbao | t            | f              | f
   ```
   Option ADMIN : depuis PostgreSQL 16, un rôle `CREATEROLE` ne donne l'appartenance à un rôle que s'il en a l'option ADMIN ; `INHERIT FALSE` et `SET FALSE` : `openbao` peut **donner** les droits du propriétaire sans **les avoir**. Un nouveau `GRANT` sur l'appartenance créée par CNPG en met les options à jour (vérifié).
3. **La connexion.** Droits des administrateurs sur le moteur ([extrait de `plateforme-admin`](fichiers/M25-E14/secrets/politiques/plateforme-admin.hcl.extrait) : configuration, `rotate-root`, identifiants de **recette** seulement, liste des baux). Mot de passe initial produit dans le cluster ([générateur `Password`](fichiers/M25-E14/k8s/espaces/mediagenda-recette/45-openbao-pg-initial.yaml), `refreshPolicy: CreatedOnce`), passé à OpenBao **par un tube**, puis tourné :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette get secret openbao-pg-initial -o jsonpath='{.data.password}' | base64 -d \
       | bao write db-mediagenda/config/mediagenda-recette plugin_name=postgresql-database-plugin \
           connection_url='postgresql://{{username}}:{{password}}@10.10.41.64:5432/mediagenda?sslmode=verify-ca&sslrootcert=/etc/openbao/postgresql/mediagenda-recette-ca.crt&connect_timeout=5' \
           username=openbao password=- password_authentication=scram-sha-256 verify_connection=true \
           allowed_roles=mediagenda-api-recette,mediagenda-migrateur-recette
   admin@adm01:~$ bao write -f db-mediagenda/rotate-root/mediagenda-recette
   ```
   Avant cela, la CA du Cluster sur `vault01-03` ([variables](fichiers/M25-E14/ansible/inventories/lab/group_vars/role_coffre/openbao-postgresql.yml), [tâche](fichiers/M25-E14/ansible/roles/openbao/tasks/ca-postgresql.yml)) : `verify-ca`, parce que le certificat de CNPG ne porte pas 10.10.41.64 (`verify-full` échoue : essayé) ; dans l'URL, parce que le greffon PostgreSQL d'OpenBao 2.6 **enregistre** `tls_ca` sans s'en servir (essayé : une CA fausse dans `tls_ca` est acceptée et ignorée ; absente du code du greffon). Puis MR : `passwordSecret` retiré du rôle géré et le générateur supprimé — CloudNativePG réapplique le mot de passe d'un `passwordSecret` dès que ce Secret change (suivi de son `resourceVersion`), ce qui remettrait l'ancien. Enfin import en code ([`imports-db.tf`](fichiers/M25-E14/secrets/tofu/imports-db.tf)) : une mise à jour sans mot de passe **garde** celui d'OpenBao (vérifié : `verify_connection` réussit après une réécriture sans `password`).
4. **Les rôles** ([`db-mediagenda.tf`](fichiers/M25-E14/secrets/tofu/db-mediagenda.tf)) : politique de mot de passe alphanumérique de 32 caractères (le mot de passe finit dans une URL) ; `api` : `CREATE ROLE … VALID UNTIL '{{expiration}}' IN ROLE mediagenda_api;` ; `migrateur` : `… IN ROLE mediagenda; ALTER ROLE "{{name}}" SET role = 'mediagenda';` ; révocation `DROP ROLE IF EXISTS`.
5. **Observer** ([modèle](fichiers/M25-E14/essais/observations.md)) :
   ```
   admin@adm01:~$ bao read -format=json db-mediagenda/creds/mediagenda-migrateur-recette | jq '{lease_id, lease_duration}'
   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda \
       -c "SELECT rolname, rolvaliduntil FROM pg_roles WHERE rolname LIKE 'v-%'"
   admin@adm01:~$ bao list sys/leases/lookup/db-mediagenda/creds/mediagenda-api-recette
   admin@adm01:~$ bao lease renew -increment=24h <BAIL>       # plafonné à 24 h après la création ; VALID UNTIL suit
   ```
   Table créée par un `migrateur` : propriétaire `mediagenda` ; `DROP` par un `api` : `must be owner of table`.
6. **Prod (préparation)** : [`base-openbao.yaml`](fichiers/M25-E14/deploiement/overlays/prod/base-openbao.yaml) (correctif du Cluster rendu par `components/dependances`, dans l'overlay de **prod** seulement : `dev` utilise le même component), [`reseau-openbao.yaml`](fichiers/M25-E14/deploiement/overlays/prod/reseau-openbao.yaml), [générateurs de prod](fichiers/M25-E14/k8s/espaces/mediagenda-prod/), même SQL et même bascule de mot de passe ; l'API n'est pas encore touchée.
7. **Recette (bascule).** Politique `eso-mediagenda-recette` étendue aux deux chemins `creds` ([extrait](fichiers/M25-E14/secrets/tofu/eso-espaces.tf.extrait)), [générateurs](fichiers/M25-E14/k8s/espaces/mediagenda-recette/90-openbao-dynamique.yaml), [component](fichiers/M25-E14/deploiement/components/identifiants-dynamiques/kustomization.yaml) : deux ExternalSecret (vague -2 : prêts avant le Job de migration), modèle `uri` au format de CNPG, correctifs du Deployment (conteneur `api`) et du Job (`migrate`). Ordre des components dans l'overlay : `migrations`, `canary`, puis `identifiants-dynamiques`, puis `livraison` ([extrait](fichiers/M25-E14/deploiement/overlays/recette/kustomization.yaml.extrait)). Après synchronisation :
   ```
   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda \
       -c "SELECT usename, count(*) FROM pg_stat_activity WHERE usename LIKE 'v-%' GROUP BY 1"
   admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://mediagenda-recette.apps.par1.medisphere.internal/pret
   200
   ```
8. **Documenter** : [`identifiants-dynamiques.md`](fichiers/M25-E14/medisphere/docs/securite/secrets/identifiants-dynamiques.md).

**Explications**

Un identifiant dynamique n'existe que le temps de son bail : il n'y a plus de mot de passe à faire tourner, à oublier dans un fichier ou à révoquer après une fuite (révoquer le bail suffit, ou attendre une heure). Le prix : le consommateur doit **suivre** le changement, et le coffre devient une dépendance du démarrage. La partie délicate est PostgreSQL : un compte temporaire qui crée des objets en devient propriétaire, et `DROP ROLE` échoue alors à la révocation ; le paramètre de session `role` fixé par `ALTER ROLE … SET role = 'mediagenda'` fait que tout ce que le migrateur crée appartient au propriétaire stable. Côté exposition, la base ne quitte le cluster que vers trois adresses, par un Service dédié, avec un certificat vérifié.

**Alternatives**
- Rôles **statiques** (`static-roles`) : OpenBao fait tourner le mot de passe d'un compte existant à intervalle fixe ; un seul compte, pas de création ; bon choix pour un outil qui ne sait pas changer d'utilisateur.
- Plugin CNPG d'identification par certificat client (`spec.certificates.clientCASecret`) et une PKI courte : pas de mot de passe du tout ; plus de pièces.
- OpenBao **dans** le cluster : pas de Service exposé, mais un coffre qui dépend du cluster qu'il sert (écarté au PLAN).

**Pièges classiques**
- Oublier `inRoles` sur `openbao` : CNPG retire l'appartenance (et l'option ADMIN) à la réconciliation suivante ; les créations échouent (`permission denied to grant role`).
- Laisser `passwordSecret` après `rotate-root` : au prochain changement du Secret, CNPG remet l'ancien mot de passe, OpenBao ne se connecte plus (panne E38).
- `sslmode=require` « pour que ça marche » : chiffré mais n'importe quel serveur est accepté.
- `tls_ca` du fournisseur OpenTofu : accepté, ignoré par le greffon d'OpenBao 2.6.
- Un mot de passe avec `@` ou `/` dans une URL : connexion refusée de façon aléatoire ; politique de mot de passe alphanumérique.
- Component inclus avant `canary` : ses correctifs du Rollout (E15) sont ignorés **sans erreur**.

**En production chez MédiSphère**
Certificat serveur de la base signé par la PKI de services (nom stable, `verify-full`, plus de recopie de la CA de CNPG tous les 90 jours) ; supervision des baux actifs par rôle et des échecs de création (`vault.database.*` dans les métriques, E27) ; `PgBouncer` (Pooler CNPG) si le nombre de connexions par compte devient un sujet ; application qui relit son URL dans un fichier et se reconnecte (ticket DEV pour Julien).

---

### M25-E15 — Tourner un secret sans redémarrage manuel

**Solution**

Fichiers : [`charts.yaml` (extrait)](fichiers/M25-E15/charts-miroir/charts.yaml.extrait) ; [`espaces/reloader.yaml`](fichiers/M25-E15/k8s/espaces/reloader.yaml) ; `plateforme/gitops` : [Application](fichiers/M25-E15/gitops/plateforme/reloader.yaml), [valeurs](fichiers/M25-E15/gitops/valeurs/reloader/values.yaml), [droits sur les Rollouts](fichiers/M25-E15/gitops/manifestes/reloader/roles-rollouts.yaml) ; `mediagenda/deploiement` : [component (version E15)](fichiers/M25-E15/deploiement/components/identifiants-dynamiques/kustomization.yaml), [overlay de prod (extrait)](fichiers/M25-E15/deploiement/overlays/prod/kustomization.yaml.extrait) ; `medidoc/deploiement` : [`medidoc-s3.yaml`](fichiers/M25-E15/medidoc-deploiement/overlays/recette/medidoc-s3.yaml), [annotation (extrait)](fichiers/M25-E15/medidoc-deploiement/overlays/recette/kustomization.yaml.extrait) ; [documentation (extrait)](fichiers/M25-E15/medisphere/docs/securite/secrets/identifiants-dynamiques.md.extrait) ; modèles [`choix.md`](fichiers/M25-E15/essais/choix.md), [`journal.md`](fichiers/M25-E15/essais/journal.md).

1. **Choisir** ([modèle](fichiers/M25-E15/essais/choix.md)). L'empreinte dans le gabarit suppose que l'outil de rendu connaisse la valeur : impossible pour un Secret fabriqué dans le cluster. Et sur un `Rollout` en `workloadRef`, toucher le gabarit du Deployment crée une **révision** (canary complet ; en prod, bloqué à la marche sans durée). Retenu : Reloader **1.4.22** (chart 2.2.18, 30/09/2026 ; la série 3.0.0 est en bêta).
2. **Installer.** Rendu relu ([valeurs](fichiers/M25-E15/gitops/valeurs/reloader/values.yaml)) : en mode « espaces listés » (`watchGlobally: false`, `namespaces`), le chart crée un **Role par espace** (Secrets en lecture, Deployments en mise à jour…) et aucune ClusterRole… ni aucun droit sur les `rollouts` : d'où [`roles-rollouts.yaml`](fichiers/M25-E15/gitops/manifestes/reloader/roles-rollouts.yaml) (mêmes verbes que la ClusterRole du chart). Arguments rendus : `--namespaces=…`, `--is-Argo-Rollouts=true`, `--reload-strategy=annotations`, `--resources-to-ignore=configmaps`.
3. **MédiAgenda.** Le component ([version E15](fichiers/M25-E15/deploiement/components/identifiants-dynamiques/kustomization.yaml)) annote le Rollout : `secret.reloader.stakater.com/reload: "mediagenda-db-api"` (le Rollout n'a pas de gabarit : on **nomme** le Secret) et `reloader.stakater.com/rollout-strategy: "restart"` (Reloader pose `spec.restartAt` ; Argo Rollouts évince les pods un à un, respecte le PodDisruptionBudget, ne crée pas de révision). Observation :
   ```
   admin@adm01:~$ while sleep 1; do curl -s -o /dev/null -w '%{http_code}\n' https://mediagenda-recette.apps.par1.medisphere.internal/pret; done | sort | uniq -c
   admin@adm01:~$ kubectl -n reloader logs deploy/reloader -f
   admin@adm01:~$ kubectl argo rollouts get rollout mediagenda -n mediagenda-recette --watch
   ```
   Révision inchangée, pods remplacés un à un, aucun 503 ; les anciens comptes disparaissent à la fin de leur bail (`pg_roles`). Délai mesuré : ~2 min après le rafraîchissement d'ESO ([journal](fichiers/M25-E15/essais/journal.md)).
4. **MédiDoc.** `refreshInterval: 5m` ([fichier](fichiers/M25-E15/medidoc-deploiement/overlays/recette/medidoc-s3.yaml)), annotation du Deployment. Rotation (identifiants de l'administrateur du RGW comme au M20-E33) :
   ```
   admin@adm01:~$ aws --profile <PROFIL-ADMIN-RGW> --endpoint-url <URL-RGW> iam create-access-key --user-name medidoc-recette \
       | jq '{AWS_ACCESS_KEY_ID: .AccessKey.AccessKeyId, AWS_SECRET_ACCESS_KEY: .AccessKey.SecretAccessKey}' \
       | bao kv put -mount=kv medidoc/recette/s3 -
   ```
   Attendre le redémarrage, envoyer un document de test (201), vérifier dans le journal d'accès du RGW que la **nouvelle** clé est utilisée, **puis** `aws iam delete-access-key --user-name medidoc-recette --access-key-id <ANCIENNE>` (identifiant relevé par `list-access-keys`, jamais la clé secrète).
5. **La racine.** `bao write -f db-mediagenda/rotate-root/mediagenda-recette` : les comptes déjà délivrés restent valides (ce sont d'autres comptes) ; plus personne ne connaît le mot de passe d'`openbao` ; si OpenBao perd la connexion, la plateforme reprend la main par le superutilisateur de CNPG (`kubectl cnpg psql`, nouveau mot de passe initial par l'entrée standard, `rotate-root` : `identifiants-dynamiques.md` §4).
6. **La prod** ([extrait](fichiers/M25-E15/deploiement/overlays/prod/kustomization.yaml.extrait)) : `canary` avant `identifiants-dynamiques` ; MR approuvée ; synchronisation manuelle ; `/pret` de la prod en 200 ; vérification que le Rollout de prod porte bien l'annotation (sinon, à la première expiration, la prod perd sa base).
7. **Journal** ([modèle](fichiers/M25-E15/essais/journal.md)) et [documentation](fichiers/M25-E15/medisphere/docs/securite/secrets/identifiants-dynamiques.md.extrait).

**Explications**

Deux mécanismes se complètent : ESO fait suivre le **Secret** (rafraîchissement), Reloader fait suivre les **pods** (redémarrage). Pour une rotation sans coupure, il faut en plus que l'ancienne valeur reste valable pendant la bascule : c'est le recouvrement des baux (un nouveau compte toutes les 30 min, chacun valable 1 h) pour PostgreSQL, et les deux clés IAM simultanées pour le RGW. L'ordre « créer, distribuer, **constater**, supprimer » vaut pour toute rotation ; supprimer avant d'avoir constaté, c'est la coupure.

**Alternatives**
- Annotation d'empreinte calculée par Helm (`checksum/secret`) : seulement si la valeur est dans Git (SOPS, Sealed Secrets, E18-E19).
- Stratégie `rollout` de Reloader sur un Rollout : nouvelle révision, canary et analyses à chaque rotation ; en prod, révision bloquée à la marche manuelle pendant que les identifiants des anciens pods expirent.
- Relecture par l'application (fichier monté, reconnexion) : la meilleure solution, au prix d'un changement de code.

**Pièges classiques**
- Annotation `reloader.stakater.com/auto: "true"` sur un Rollout en `workloadRef` : aucun Secret découvert, rien ne redémarre, la panne arrive une heure plus tard.
- Reloader en mode « espaces listés » sans droit sur `rollouts` : `forbidden` dans ses journaux, rien ne redémarre.
- Component placé avant `canary` dans l'overlay : annotation absente, sans erreur de Kustomize.
- Une seule réplique : `restart` évince le seul pod (coupure, documentée par Argo Rollouts).
- Supprimer l'ancienne clé S3 juste après avoir écrit la nouvelle dans le coffre : les pods n'ont pas encore redémarré.

**En production chez MédiSphère**
Alertes : ExternalSecret non prêt depuis 20 min, Rollout non redémarré depuis 45 min alors que son Secret a changé, baux d'identifiants dynamiques proches de leur maximum ; rotation trimestrielle des clés S3 par le pipeline planifié de `plateforme/secrets` (E33) ; Reloader étendu aux espaces de plateforme qui lisent des identités RGW (Thanos, Loki, Tempo : promesse du M21).

---

### M25-E16 — PKI de services : « MédiSphère Services CA » et cert-manager

**Solution**

Fichiers : `plateforme/secrets` : [`tofu/pki-services.tf`](fichiers/M25-E16/secrets/tofu/pki-services.tf), [`cert-manager-services.hcl`](fichiers/M25-E16/secrets/politiques/cert-manager-services.hcl) ; `plateforme/k8s` : [`composants/cert-manager/openbao-services.yaml`](fichiers/M25-E16/k8s/composants/cert-manager/openbao-services.yaml), [auth-delegator (extrait)](fichiers/M25-E16/k8s/rbac/openbao-auth-delegator.yaml.extrait) ; `medidoc/deploiement` : [`mtls.yaml`](fichiers/M25-E16/medidoc-deploiement/overlays/recette/mtls.yaml), [`relais-tls.yaml`](fichiers/M25-E16/medidoc-deploiement/overlays/recette/relais-tls.yaml), [`service-https.yaml`](fichiers/M25-E16/medidoc-deploiement/overlays/recette/service-https.yaml), [`entree-mediagenda.yaml`](fichiers/M25-E16/medidoc-deploiement/overlays/recette/entree-mediagenda.yaml), [extrait](fichiers/M25-E16/medidoc-deploiement/overlays/recette/kustomization.yaml.extrait) ; `mediagenda/deploiement` : [`mtls.yaml`](fichiers/M25-E16/deploiement/overlays/recette/mtls.yaml), [`relais-tls.yaml`](fichiers/M25-E16/deploiement/overlays/recette/relais-tls.yaml), [`sortie-medidoc.yaml`](fichiers/M25-E16/deploiement/overlays/recette/sortie-medidoc.yaml), [extrait](fichiers/M25-E16/deploiement/overlays/recette/kustomization.yaml.extrait) ; documentation : [procès-verbal](fichiers/M25-E16/medisphere/docs/securite/identite/ceremonie-ca.md.extrait), [`pki-services.md`](fichiers/M25-E16/medisphere/docs/securite/secrets/pki-services.md) ; [certificat d'essai](fichiers/M25-E16/essais/certificat-essai.yaml), [modèle d'essais](fichiers/M25-E16/essais/essais-mtls.md).

1. **La CSR.** Montage en code (durée maximale 3 ans, URL, CRL, ménage), droits des administrateurs sur `pki-services/*` ([extrait de `plateforme-admin`](fichiers/M25-E16/secrets/politiques/plateforme-admin.hcl.extrait)), puis, une fois :
   ```
   admin@adm01:~$ bao write -format=json pki-services/intermediate/generate/internal \
       common_name="MédiSphère Services CA" key_type=ec key_bits=256 key_name=services-2026 \
       | jq -r .data.csr > ~/src/ansible/pki/openbao-services.csr
   ```
   `internal` : la clé reste dans OpenBao (`exported` la renverrait, et elle aurait existé ailleurs). La CSR contient le sujet et la clé **publique** ; ni durée, ni contrainte `pathlen` : c'est la racine qui les fixe en signant.
2. **La cérémonie** (procédure `ceremonie-ca.md`, [procès-verbal](fichiers/M25-E16/medisphere/docs/securite/identite/ceremonie-ca.md.extrait)) :
   ```
   admin@adm01:~/src/ansible/pki$ step certificate inspect openbao-services.csr --short
   admin@adm01:~/src/ansible/pki$ DUREE_INTERMEDIAIRE=26280h ceremonie-pki.sh signer openbao-services.csr
   admin@adm01:~/src/ansible/pki$ openssl verify -CAfile medisphere-root-ca.crt openbao-services.crt
   admin@adm01:~/src/ansible/pki$ cat openbao-services.crt medisphere-root-ca.crt > /tmp/chaine.pem
   admin@adm01:~/src/ansible/pki$ bao write pki-services/intermediate/set-signed certificate=@/tmp/chaine.pem
   admin@adm01:~$ bao list pki-services/issuers
   admin@adm01:~$ bao patch pki-services/issuer/<ID-DE-L-EMETTEUR-AVEC-CLÉ> issuer_name=services-2026
   admin@adm01:~$ bao write pki-services/config/issuers default=services-2026
   admin@adm01:~$ curl -s https://openbao.par1.medisphere.internal:8200/v1/pki-services/ca/pem \
       | openssl verify -CAfile /usr/local/share/ca-certificates/medisphere-root-ca.crt
   ```
   `set-signed` de la **chaîne** : OpenBao importe deux émetteurs (la Services CA, liée à sa clé, et la racine, sans clé) et peut publier la chaîne complète (`ca_chain`) ; seul l'émetteur qui a une clé peut être émetteur par défaut. `DUREE_INTERMEDIAIRE` : la variable du script du M06 (5 ans par défaut).
3. **Le rôle et la CRL** ([`pki-services.tf`](fichiers/M25-E16/secrets/tofu/pki-services.tf)). Demandes d'essai ([modèle](fichiers/M25-E16/essais/essais-mtls.md)) : nom hors `svc` → `common name … not allowed by this role` ; IP → `IP Subject Alternative Names are not allowed in this role, but was provided via CSR` ; 100 h → **acceptée et réduite à 72 h**, avec un simple avertissement (« TTL … is longer than permitted maxTTL … so maxTTL is being used ») : la durée maximale borne, elle ne refuse pas. CRL de 72 h reconstruite automatiquement, ménage toutes les 12 h.
4. **cert-manager** ([fichier](fichiers/M25-E16/k8s/composants/cert-manager/openbao-services.yaml)) : compte `openbao-emetteur` dans l'espace `cert-manager` (espace des ressources de cluster), Role qui permet **au contrôleur** de demander un jeton pour ce compte (`serviceaccounts/token`, `create`, `resourceNames`), liaison `auth-delegator`, ClusterIssuer (chemin `sign`, `mountPath: /v1/auth/k8s-par1` **complet**, audience ajoutée à celle que cert-manager met toujours, `vault://openbao-services`). Essai dans `wb-essais` :
   ```
   admin@adm01:~$ kubectl apply -f ~/m25/e16/certificat-essai.yaml
   admin@adm01:~$ kubectl -n wb-essais get certificaterequest -o wide
   admin@adm01:~$ kubectl -n wb-essais get secret essai-services-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
       | openssl x509 -noout -subject -issuer -enddate -ext subjectAltName,extendedKeyUsage
   ```
5. **Le TLS mutuel**, dans l'ordre qui ne coupe rien : (a) MédiDoc : [Certificate](fichiers/M25-E16/medidoc-deploiement/overlays/recette/mtls.yaml), [relais `server`](fichiers/M25-E16/medidoc-deploiement/overlays/recette/relais-tls.yaml) en conteneur annexe natif (`--allow-dns=mediagenda.mediagenda-recette.svc`, `--timed-reload=300s`), port 8443 au [Service](fichiers/M25-E16/medidoc-deploiement/overlays/recette/service-https.yaml), politique d'entrée **avec 8080 et 8443** ; (b) MédiAgenda : [Certificate](fichiers/M25-E16/deploiement/overlays/recette/mtls.yaml), [relais `client`](fichiers/M25-E16/deploiement/overlays/recette/relais-tls.yaml) (`--verify-dns=medidoc.medidoc-recette.svc`), `MEDIAGENDA_MEDIDOC_URL=http://127.0.0.1:8081`, [politique de sortie](fichiers/M25-E16/deploiement/overlays/recette/sortie-medidoc.yaml) sur 8443 ; (c) MédiDoc : [politique d'entrée](fichiers/M25-E16/medidoc-deploiement/overlays/recette/entree-mediagenda.yaml) réduite à 8443. Preuves : rendez-vous avec pièce jointe en recette (201) ; depuis un pod d'essai de `mediagenda-recette`, `curl -sk https://medidoc.medidoc-recette.svc.cluster.local:8443/readyz` échoue à la poignée de main (pas de certificat client).
6. **Révoquer** :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette get secret mediagenda-mtls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -serial
   admin@adm01:~$ bao write pki-services/revoke serial_number=<SÉRIE-AVEC-DEUX-POINTS>
   admin@adm01:~$ bao read pki-services/crl/rotate
   admin@adm01:~$ curl -s https://openbao.par1.medisphere.internal:8200/v1/pki-services/crl/pem | openssl crl -noout -text | grep -A1 'Serial Number'
   ```
   La série apparaît dans la CRL (après reconstruction : sans `crl/rotate`, au plus tard après le délai de grâce), et les appels **continuent** : ghostunnel ne lit ni CRL ni OCSP. Conclusion dans [`pki-services.md`](fichiers/M25-E16/medisphere/docs/securite/secrets/pki-services.md) : ici, la protection est la durée (48 h) et la nouvelle clé à chaque renouvellement ; la CRL sert aux clients qui la lisent et à la preuve.

**Explications**

Une CA intermédiaire dans le coffre permet des certificats **courts et nombreux**, émis à la demande à des identités vérifiées (le compte de service de cert-manager), sans que la clé de la CA ne quitte jamais le coffre ni que la racine ne sorte plus d'une fois tous les trois ans. Le TLS mutuel répond aux deux questions que la politique réseau laissait ouvertes : *qui* parle (le certificat client au nom du Service de MédiAgenda) et *qui l'entend* (le certificat serveur de MédiDoc), avec chiffrement. Le relais en conteneur annexe évite de toucher au code des deux applications, au prix d'un saut local en clair (dans le pod).

**Alternatives**
- `issue` au lieu de `sign` : OpenBao génère la clé et la renvoie ; plus simple, mais la clé transite.
- Maillage de services (Istio ambiant, Linkerd) : mTLS automatique pour tout le cluster, avec sa propre CA (qui peut être une intermédiaire d'OpenBao) ; beaucoup plus de pièces. L'authentification mutuelle de Cilium est dépréciée en 1.20.
- TLS dans les applications (Go `tls.Config{ClientAuth: RequireAndVerifyClientCert}`, `httpx` avec `cert=`) : pas de relais, mais du code et des clés dans les applications.
- SPIFFE/SPIRE : identités de charge de travail standard, rotation automatique ; une infrastructure de plus.

**Pièges classiques**
- `set-signed` avec le seul certificat de l'intermédiaire : chaîne incomplète publiée, clients qui ne remontent pas à la racine.
- Oublier `pathlen:0` (profil de la cérémonie) : la Services CA pourrait créer d'autres autorités.
- `mountPath: k8s-par1` dans la ClusterIssuer : cert-manager attend le chemin complet `/v1/auth/k8s-par1`.
- Pas de droit `serviceaccounts/token` pour le contrôleur de cert-manager : la ClusterIssuer reste « not ready » (« cannot create resource serviceaccounts/token »).
- Ouvrir 8443 et fermer 8080 dans la même MR : l'appel est coupé tant que MédiAgenda n'a pas son relais.
- Croire que révoquer suffit : sans client qui lit la CRL, un certificat révoqué vit jusqu'à son expiration.

**En production chez MédiSphère**
`approver-policy` de cert-manager (un espace ne demande que les noms de ses Services) ; relais ou proxy qui vérifie la CRL (ou OCSP) pour les flux de données de santé ; certificat serveur des bases CNPG signé par cette PKI (fin de la recopie de la CA de CNPG, E14) ; supervision de l'échéance de la Services CA (un an avant), de l'âge de la CRL et des échecs d'émission ; TLS mutuel étendu à MédiDoc → stockage et à la prod au palier 3 ou au mini-projet.

---

## Ce qui reste promis (E10 à E16)

Promesses des modules précédents que cette moitié du palier ne tient **pas** entièrement, et où elles le seront :

| Promesse | Origine | Où |
|---|---|---|
| Secrets S3 et cephx (Velero, CNPG, ceph-csi), TSIG et compte ACME (cert-manager, ExternalDNS) par ESO | M15-E46, M16-E23, M16 mini-projet | couche de base sous Helmfile : mini-projet M25-E46, même méthode qu'E13 |
| Clé KEK de la classe chiffrée de ceph-csi dans le coffre (`vaulttenantsa`) | M16-E26 | non tenue : fonctionnement de ceph-csi avec OpenBao non documenté (annexe des versions) ; reste au registre des risques (ADR-0251, E31) |
| Rotation des identités RGW de Thanos, Loki, Tempo avec redémarrage contrôlé | M21-E24, M22 | Reloader limité aux espaces applicatifs ici ; E33 (politique de rotation) |
| MédiAgenda lit son URL de base dans un fichier (`MEDIAGENDA_DB_URL_FILE`) | M12-E01 | ticket DEV ouvert (E15) ; hors du module |
| Autorité des partenaires dans la PKI d'OpenBao (mTLS d'entrée) | M15-E33 | E16 couvre les services internes ; partenaires : F6 |
| Clé de l'intermédiaire de step-ca dans un KMS | M06-E33 | hors périmètre du M25 (ADR-0250, E31) |
| Robot de tirage à durée limitée renouvelé par le coffre | M14-E19 | `harbor-pull` vient du coffre (E13) ; rotation automatique : E33 |
