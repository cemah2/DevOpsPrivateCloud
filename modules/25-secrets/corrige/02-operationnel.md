# Module 25 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les solutions complètes sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `…/secrets/…` = `plateforme/secrets`, `…/ci-templates/…` = `plateforme/ci-templates`, `…/ansible/…` = `plateforme/ansible`, `…/k8s/…` = `plateforme/k8s`, `…/gitops/…` = `plateforme/gitops`, `…/charts-miroir/…` = `plateforme/charts-miroir`, `…/deploiement/…` = `mediagenda/deploiement`, `…/medidoc-deploiement/…` = `medidoc/deploiement`, `…/mediagenda-api/…` = `mediagenda/api`, `…/medisphere/…` = la documentation, `…/essais/` = `~/m25/eXX/`. On **superpose** les dossiers dans l'ordre des exercices, par-dessus ceux du palier 1 ; un fichier d'un exercice plus récent remplace le précédent. Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête). Les valeurs `<EN-MAJUSCULES>` sont à remplacer par les tiennes (`<RACINE-MEDISPHERE-EN-BASE64>` : `base64 -w0 /usr/local/share/ca-certificates/medisphere-root-ca.crt`).

**Structure de `plateforme/secrets`.** Celle du palier 1 (E08) : `tofu/` (fournisseur `hashicorp/vault ~> 5.13`, état S3 `secrets` chiffré, jeton enfant de 20 min créé à partir de ta session OIDC), `politiques/<nom>.hcl` appliquées par **une seule** ressource `vault_policy.acl` (`for_each` sur `fileset`) : ajouter une politique = ajouter un fichier `.hcl`, aucune ressource `vault_policy` à écrire dans ce palier (sauf les politiques **générées** par gabarit, `eso-<espace>`, E13). Les certificats publics lus par `file()` sont rangés dans `racine/`.

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *OpenBao* : un serveur OpenBao **2.6.4** de développement a servi de banc. Politiques chargées (`bao policy fmt`, `bao policy write`) ; méthode `jwt` : rôles avec revendications liées en `glob` et en listes, jetons forgés au format de GitLab (bonne branche acceptée, branche non protégée, autre audience, autre `project_id` refusés, messages relevés) ; méthode `kubernetes` : configuration et rôles écrits et relus (la vérification TokenReview elle-même exige un cluster) ; moteur `database` contre un **PostgreSQL 16** local : connexion, `rotate-root`, politique de mot de passe, rôles `api` et `migrateur` (droits, propriétaire des objets créés, refus du `DROP`), révocation **pendant** une session ouverte (la session casse), renouvellement (le `VALID UNTIL` suit), connexion TLS `sslmode=verify-ca` + `sslrootcert` (et refus de `verify-full` sur une adresse, refus d'une mauvaise CA) ; PKI : CSR d'intermédiaire, signature par une racine d'essai, `set-signed` de la chaîne, émetteur par défaut, rôle (nom hors `svc`, IP et durée excessive essayés), CRL et révocation. Le SQL de préparation joué deux fois (idempotent) ; la mise à jour des options d'une appartenance existante par un nouveau `GRANT` vérifiée.
- *OpenTofu* 1.13.2 et `hashicorp/vault` **5.13.0** : `tofu fmt`, `tofu validate` de l'ensemble des fichiers du palier, `plan` contre le banc, `apply` de ressources témoins (rôle JWT : la liste `"main,v*"` arrive bien en liste ; rôle PKI ; politique de mot de passe ; rôle de base de données).
- *Kubernetes* : `kubeconform -strict` avec les schémas tirés des CRD d'**ESO 2.13.0** (rendu du chart), **cert-manager 1.21.2**, **CloudNativePG 1.30.1**, **Argo CD 3.5.6**, **Argo Rollouts 1.10.1**, **Cilium 1.20.3** ; `helm template` (Helm 4.0.1) des charts **external-secrets 2.13.0** et **reloader 2.2.18** avec les valeurs du palier (images, arguments, droits relus) ; `kustomize build` (5.8.1) du component `identifiants-dynamiques` (correctifs appliqués ; correctif **ignoré sans erreur** quand le component passe avant celui qui rend sa cible : vérifié) et des correctifs de relais TLS.
- *Scripts et Ansible* : `shellcheck -x` et `bash -n` (checks, `openbao-ci.sh`, `etat-depuis-openbao.sh`, `vault-pass-client.sh` — essayé contre le banc : identité permise, refusée, jeton invalide, mode secours —, `secret-vers-openbao.sh` — essayé avec un faux `kubectl` : recopie, refus d'écraser, comparaison) ; `ansible-lint` (profil `production`) sur `openbao_client`.
- *E17 à E22* (vérifications propres à chaque exercice) :
  - *E17* (OpenBao 2.6.4 et 2.7.1 en développement, OpenTofu 1.13.2, fournisseur `hashicorp/vault` 5.13.0, Python 3.13) : `tofu/transit.tf` appliqué contre OpenBao (plan vide ensuite) ; chiffrement, rotation, `rewrap`, `min_decryption_version` (refus puis retour), `trim` (refusé tant que `min_encryption_version` n'est pas posé), `batch_input`, `datakey` ; politique `medictl` (encrypt, decrypt, rewrap autorisés ; `rotate` refusé en 403) ; module `transit.py` et commandes `medictl transit …` assemblées dans le `cli.py` du M02, `ruff` et `pytest` au vert, essai réel contre un OpenBao en TLS ; fournisseur de clé `openbao` d'OpenTofu (migration d'un état local, chemins appelés relevés dans l'audit, état illisible après suppression de la clé) ; `check-E17.sh` exécuté contre ce coffre (contrôles OpenBao et fichier au vert, puis au rouge après une rotation non suivie de `rewrap`).
  - *E18* (SOPS 3.13.3, age 1.3.2, OpenBao 2.6.4 en développement, yq 4.48.1, ansible-core 2.21) : le gabarit `binaire.yml` étendu et les deux entrées du rôle, exécutés (empreintes vérifiées par `get_url`, liens créés, `sops --version` et `age --version`) ; signature du fichier de sommes de SOPS vérifiée par `cosign verify-blob` (identité du flux de publication) ; `.sops.yaml` avec `hc_vault_transit_uri` + `age` (un groupe, l'un **ou** l'autre déchiffre) ; `sops encrypt`, `decrypt`, `updatekeys`, `rotate` ; MAC refusé après modification d'un champ **en clair** (`MAC mismatch`) ; déchiffrement refusé sans jeton (`permission denied` du coffre, puis échec des identités age) ; SOPS **ne lit pas** `BAO_TOKEN` (seulement `VAULT_TOKEN` et `~/.vault-token`) ; `SOPS_HC_VAULT_ALLOWLIST` (code source de 3.13.3 : liste d'URL séparées par des virgules, comparées en préfixe, défaut `all`) ; `outils/verifier-chiffres.sh` (au vert sur un fichier chiffré, au rouge sur un Secret en clair et sur des valeurs en clair) ; filtres de `check-E18.sh` sur ces fichiers réels.
  - *E19* : index Helm des trois charts (versions et empreintes relevées, archives téléchargées et contrôlées) ; les trois charts **rendus** par `helm template` avec les valeurs de ce corrigé (images du cache Harbor, `--key-renew-period`, `--enable-secret-rotation=true`, `--rotation-poll-interval=2m`, agent 2.6.4, montage de la racine dans les deux conteneurs du fournisseur, contextes de sécurité du contrôleur Sealed Secrets compatibles `restricted`) ; `kubeseal` 0.40.0 hors ligne (scellement en portée stricte et `cluster-wide`, `--recovery-unseal` avec la clé privée) ; paramètres de la `SecretProviderClass` relus dans la documentation du fournisseur OpenBao 2.x (`provider: openbao`, `baoAuthMountPath`, `audience`, `roleName`) ; rôle Kubernetes d'essai appliqué par OpenTofu contre OpenBao 2.7.1 ; filtres de `check-E19.sh` sur un `SealedSecret` réel.
  - *E20* (Cosign 3.1.4, OpenBao 2.6.4 **et** 2.7.1 en développement, fournisseur `hashicorp/vault` 5.13.0, OpenTofu 1.13.2) : `cosign public-key`, `sign-blob`, `verify-blob`, `sign`, `attest`, `verify`, `verify-attestation` avec `hashivault://cosign-medisphere` contre OpenBao (registre OCI local) — **le point non vérifié de l'annexe des versions est levé** ; Cosign lit `BAO_ADDR`/`BAO_TOKEN` (code de `sigstore/sigstore` 1.11.1 utilisé par Cosign 3.1.4 : `VAULT_*` d'abord, puis `BAO_*`, puis `~/.vault-token`), essayé sans `VAULT_*` ; chemins appelés relevés dans l'audit (`read transit/keys/cosign-medisphere`, `update transit/sign/cosign-medisphere/sha2-256`) et signature réussie avec la seule politique `cosign-signature` ; clé publique de transit identique à la sortie de `cosign public-key` ; rôle `ci-signature` : le rôle écrit par `vault_jwt_auth_backend_role` **refuse** un jeton dont `runner_id` est numérique (le fournisseur l'enregistre `["12"]`), le rôle écrit par `vault_generic_endpoint` l'accepte (plan vide ensuite) ; jetons forgés (RS256, JWKS de test) : accepté pour `mediagenda` + `ref_protected="true"` + runner 12, refusé pour le runner 13, une référence non protégée, le groupe `formation` (messages relevés) ; `bao token revoke -self` refusé tant que `auth/token/revoke-self` manquait à la politique (le rôle retire `default`) ; connexion par JSON sur l'entrée standard ; `check-E20.sh` contre ce coffre (contrôles OpenBao au vert, puis au rouge avec une politique qui ouvre `transit/export`).
  - *E21* (OpenBao 2.6.4 réel, stockage Raft, Loki 3.7.9 et Alloy 1.21.1 locaux) : refus de `bao audit enable` (« cannot enable audit device via API; use declarative, config-based audit device management instead ») ; dispositif déclaré créé au descellement, **modification refusée** au rechargement (« modifications to audit devices are not allowed … missing option hmac_accessor »), nouveau chemin accepté au SIGHUP, `bao audit disable` refusé (« cannot disable configuration-managed audit device ») ; `hmac_accessor = "false"` (accessors en clair) ; `sys/audit-hash/fichier` retrouvant une valeur lue ; panne simulée (fichier remplacé par un dossier) : HTTP 500 « internal error » et « core: failed to audit request … no audit backend succeeded in logging the response » dans le journal, retour à la normale au rechargement ; gabarits `openbao.hcl` (validé par `bao operator validate-config`), `logrotate` et `config.alloy` rendus par Ansible (`alloy fmt` au vert, Alloy a lu le fichier et l'a poussé dans Loki) ; les quatre règles chargées par un ruler Loki 3.7.9 (santé `ok`) et **toutes passées en `firing`** sur un vrai journal d'audit (jeton racine, écriture de politique, réglage d'une clé de transit, ligne « failed to audit » poussée avec la métadonnée structurée `unite`) ; requête « qui a lu `kv/data/mediagenda/prod/*` » exécutée ; `check-E21.sh` contre ce Loki (contrôles Loki et ruler).
  - *E22* : les fichiers de Lucas passent `bao policy fmt` et `tofu validate` (comme il le dit) ; politiques chargées dans OpenBao 2.6.4 de développement et interrogées par `bao token capabilities` (sorties dans le corrigé d'E22), lecture réelle de `kv/data/mediagenda/prod/valkey` avec la politique `medidoc-ci` ; un rôle AppRole `bind_secret_id=false` **sans** contrainte est refusé par OpenBao (« at least one constraint should be enabled on the role ») et accepté avec `token_bound_cidrs = ["0.0.0.0/0"]`, puis connexion avec le seul `role_id` ; fichiers corrigés : `bao policy fmt`, `tofu fmt -check` et `tofu validate`, et rôles corrigés appliqués par OpenTofu contre OpenBao 2.7.1.
- **Points non testés en conditions réelles** (à vérifier sur ton lab ; signale tout écart) : connexion d'un vrai job GitLab 19.5 (nom et présence de la revendication `environment`, valeur de `ref_protected` dans un **pipeline de MR** issu d'une branche protégée) et découverte OIDC de `git01` depuis `vault01` ; comportement d'ESO 2.13 contre OpenBao (adoption d'un Secret existant, générateur `VaultDynamicSecret` avec la méthode `kubernetes`, modèles `engineVersion: v2`, cache de jetons) — le fournisseur OpenBao d'ESO est classé *alpha* ; Reloader 1.4.22 sur un `Rollout` en `workloadRef` (stratégie `restart`) et absence de dérive dans Argo CD après `spec.restartAt` ; options d'appartenance de `openbao` conservées après une réconciliation de CloudNativePG ; Service géré par CNPG avec l'annotation de Cilium LB IPAM ; ClusterIssuer `vault` de cert-manager contre OpenBao (contenu de `ca.crt`) ; image distroless de ghostunnel (utilisateur) en conteneur annexe natif ; deux clés d'accès IAM simultanées sur le RGW ; lookups de `community.hashi_vault` 7.1 contre OpenBao ; E17 : la publication de `medictl` par le pipeline de `plateforme/outils` (M02), l'AppRole `medictl` d'E07 (liaison à `adm01`) ; E18 : le pipeline de `formation/sops-labo` sur le runner (image `alpine/k8s`, yq de mikefarah attendu), le flux OIDC réel ; E19 : aucun des trois composants n'a tourné dans un cluster à la rédaction ; le montage de la racine sur `/etc/ssl/certs/ca-certificates.crt` pour l'agent (image Alpine), la rotation alpha du pilote et les messages exacts des événements sont à confirmer sur ton lab ; E20 : le composant v2.10.0 dans un vrai pipeline GitLab 19.5, Harbor et sa politique « signature exigée » avec la nouvelle clé, la nouvelle image outillée, la re-signature d'images réellement déployées ; E21 : le rôle `openbao` complet sur `vault01` (gabarit validé seul), `logrotate` sur la VM (validé sauf l'utilisateur `openbao`, absent du bac à sable), la livraison des règles par le *sidecar* du chart Loki, le format exact de `auth.display_name` pour les méthodes `jwt` et `kubernetes`.

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
4. **Recopier sans afficher.** La plateforme **dépose** les secrets des applications sans pouvoir les relire : [extrait de `plateforme-admin`](fichiers/M25-E10/secrets/politiques/plateforme-admin.hcl.extrait), écriture seule (`create`, `update`) sur `kv/data/mediagenda/*` et `kv/data/medidoc/*` (essayé : `kv put` réussit, `kv get` est refusé ; et, pour les métadonnées, une règle `kv/metadata/+/ci/*` aurait perdu face au `kv/metadata/*` du palier 1 : à position de premier joker égale, chaque `+` abaisse la priorité d'une règle ; d'où des chemins écrits en clair par application). Depuis l'interface de GitLab, la valeur d'une variable *cachée* n'est plus lisible : c'est l'occasion de **régénérer** (jeton `ci-promotion` de `mediagenda/deploiement`, robot Harbor par OpenTofu `registre/`, jeton `bot-release`). La nouvelle valeur va directement au coffre, par l'entrée standard :
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

Le jeton d'identité inverse le modèle : le job ne **détient** rien, il **prouve** qui il est par une signature de GitLab, et le coffre décide. OpenBao vérifie la signature (clés lues par la découverte), l'émetteur, l'audience, les dates, puis chaque revendication liée ; il délivre un jeton OpenBao de dix minutes porteur des seules politiques du rôle. Un jeton d'identité volé dans un journal ne sert à rien ailleurs (audience), mais il reste valable jusqu'à son `exp`, c'est-à-dire la **durée maximale du job** (une heure par défaut : GitLab calcule `exp` à partir du *timeout* du job) ; d'où des *timeouts* de jobs courts et un jeton jamais affiché ; un jeton OpenBao volé dure dix minutes et se révoque par son accesseur. Ce qui reste critique : GitLab lui-même (qui peut pousser sur `main` peut lire ces secrets) — d'où la protection des branches, les approbations, et l'audit des lectures (E21).

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
2. **Le quota d'abord.** Le quota de l'espace (M14-E10, M20-E07) interdit les Services `LoadBalancer` (`services.loadbalancers: "0"`) : sans MR préalable, le Service ajouté par `managed.services` est refusé et CNPG le signale dans l'état du `Cluster`. Passe la valeur à `"1"` en recette puis en prod, avec la justification en commentaire ([recette](fichiers/M25-E14/k8s/espaces/mediagenda-recette/10-quota.yaml), [prod](fichiers/M25-E14/k8s/espaces/mediagenda-prod/10-quota.yaml)).
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

1. **La CSR.** Montage en code (durée maximale 3 ans, URL, CRL, ménage), droits des administrateurs sur `pki-services/*`, `patch` compris ([extrait de `plateforme-admin`](fichiers/M25-E16/secrets/politiques/plateforme-admin.hcl.extrait)), puis, une fois :
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
   admin@adm01:~$ bao patch pki-services/issuer/<ID-DE-L-EMETTEUR-AVEC-CLÉ> issuer_name=services-2026   # capacité « patch » (extrait ci-dessus)
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

### M25-E17 — Transit : le chiffrement comme service

**Solution**

Fichiers : [`secrets/tofu/transit.tf`](fichiers/M25-E17/secrets/tofu/transit.tf), [`politiques/medictl.hcl`](fichiers/M25-E17/secrets/politiques/medictl.hcl) (version complète), extraits [`plateforme-admin.hcl.extrait`](fichiers/M25-E17/secrets/politiques/plateforme-admin.hcl.extrait) et [`wb-checks.hcl.extrait`](fichiers/M25-E17/secrets/politiques/wb-checks.hcl.extrait), [`tofu-secrets.hcl.extrait`](fichiers/M25-E17/secrets/politiques/tofu-secrets.hcl.extrait) (le pipeline relit les clés à chaque `plan`) ; `medictl` : [`src/medictl/transit.py`](fichiers/M25-E17/outils/src/medictl/transit.py), [`cli.py.extrait`](fichiers/M25-E17/outils/src/medictl/cli.py.extrait), [`tests/python/test_transit.py`](fichiers/M25-E17/outils/tests/python/test_transit.py) ; essai [`tofu-essai/main.tf`](fichiers/M25-E17/essais/tofu-essai/main.tf) ; note [`transit.md`](fichiers/M25-E17/medisphere/docs/securite/secrets/transit.md).

1. **Lecture.** Clés symétriques `aes128-gcm96`, `aes256-gcm96`, `chacha20-poly1305` (chiffrement), asymétriques `ed25519`, `ecdsa-p256/384/521`, `rsa-2048/3072/4096` (signature, et chiffrement pour RSA), `hmac`, et en 2.7 ML-DSA. Le clair est en **base64** parce que l'API est du JSON et que la donnée peut être binaire. Le chiffré `vault:v3:…` dit quelle **version** de la clé l'a produit (préfixe historique conservé par OpenBao). `rotate` crée une nouvelle version (qui chiffre désormais) ; `rewrap` rechiffre un chiffré avec la dernière version **sans renvoyer le clair** ; `min_decryption_version` refuse de déchiffrer les versions plus anciennes ; `min_encryption_version` interdit de chiffrer avec elles ; `trim` **supprime** les versions sous `min_available_version`. Une clé de données (`datakey/plaintext` ou `datakey/wrapped`) est une clé AES aléatoire rendue en clair et/ou chiffrée par la clé de transit : le client chiffre localement de gros volumes et range la clé de données chiffrée à côté (*envelope encryption*).
2. **En code.** `tofu/transit.tf` (montage + `medictl-donnees` + `essai-e17`), politiques, puis :
   ```
   admin@adm01:~/src/secrets$ git switch -c transit
   admin@adm01:~/src/secrets$ bao login -method=oidc && . outils/charger-acces.sh
   admin@adm01:~/src/secrets$ cd tofu && tofu plan -out transit.tfplan
     # vault_mount.transit, deux vault_transit_secret_backend_key, trois vault_policy.acl modifiées
   ```
   MR, fusion, `tofu apply transit.tfplan` (comme en E08), puis un `tofu plan` vide. Le fournisseur **ne sait pas tourner** une clé : `latest_version` n'est qu'un attribut lu. C'est voulu : une rotation est un événement daté, pas un état à reconverger. Gérer `min_decryption_version` en code serait dangereux : un `apply` d'une branche ancienne pourrait **rouvrir** des versions gelées pendant un incident, ou en geler par erreur ; cette valeur se change par un geste tracé (ticket, audit).
3. **Premiers chiffrés.**
   ```
   admin@adm01:~$ for i in 1 2; do bao write -field=ciphertext transit/encrypt/essai-e17 plaintext="$(printf 'code 4821' | base64)"; echo; done
   vault:v1:SgyyCGt7BaeHYePpjksbTZ9f1W7t5yBP8AY9yhjgrIDujMX/qOFoP273…
   vault:v1:8SctdVi4muK3V1Jd5R8WBYqcO14d1K46RTWCC50e+t6a/g==…
   admin@adm01:~$ bao write -field=plaintext transit/decrypt/essai-e17 ciphertext='vault:v1:SgyyCG…' | base64 -d
   code 4821
   ```
   Deux chiffrés différents : AES-GCM tire un **nonce** aléatoire à chaque chiffrement (le même clair ne donne jamais le même chiffré, sauf chiffrement convergent). Par l'API, le jeton passe par un fichier de configuration de `curl` lu sur un descripteur (jamais en argument, visible par `ps`) :
   ```
   admin@adm01:~$ curl -s -K <(printf 'header = "X-Vault-Token: %s"\n' "$(cat ~/.vault-token)") \
       -d "{\"plaintext\":\"$(printf 'code 4821' | base64)\"}" $BAO_ADDR/v1/transit/encrypt/essai-e17 | jq -r .data.ciphertext
   admin@adm01:~$ jq -nc '{batch_input: [{plaintext: ("a"|@base64)}, {plaintext: ("b"|@base64)}, {plaintext: ("c"|@base64)}]}' \
       | bao write -format=json transit/encrypt/essai-e17 - | jq -r '.data.batch_results[].ciphertext'
   ```
4. **Rotation et rechiffrement.**
   ```
   admin@adm01:~/m25/e17$ bao write -field=ciphertext transit/encrypt/essai-e17 plaintext="$(printf secret | base64)" > v1.txt
   admin@adm01:~/m25/e17$ bao write -f transit/keys/essai-e17/rotate
   admin@adm01:~/m25/e17$ bao write -field=ciphertext transit/encrypt/essai-e17 plaintext="$(printf secret | base64)"   # vault:v2:…
   admin@adm01:~/m25/e17$ bao write -field=plaintext transit/decrypt/essai-e17 ciphertext="$(cat v1.txt)" | base64 -d   # secret : v1 se lit toujours
   admin@adm01:~/m25/e17$ bao write -field=ciphertext transit/rewrap/essai-e17 ciphertext="$(cat v1.txt)" > v2.txt        # vault:v2:…
   ```
   Le clair n'apparaît jamais pendant le `rewrap` : OpenBao déchiffre et rechiffre en interne. C'est ce qui permet à un job de rechiffrement de n'avoir que le droit `rewrap`.
5. **Geler, puis détruire.**
   ```
   admin@adm01:~/m25/e17$ bao write transit/keys/essai-e17/config min_decryption_version=2
   admin@adm01:~/m25/e17$ bao write transit/decrypt/essai-e17 ciphertext="$(cat v1.txt)"
   Code: 400. Errors:
   * ciphertext or signature version is disallowed by policy (too old)
   admin@adm01:~/m25/e17$ bao write transit/keys/essai-e17/config min_decryption_version=1   # v1 redevient lisible
   admin@adm01:~/m25/e17$ bao write transit/keys/essai-e17/trim min_available_version=2
   * minimum available version cannot be set when minimum encryption version is not set
   admin@adm01:~/m25/e17$ bao write transit/keys/essai-e17/config min_decryption_version=2 min_encryption_version=2
   admin@adm01:~/m25/e17$ bao write transit/keys/essai-e17/trim min_available_version=2
   admin@adm01:~/m25/e17$ bao read -field=keys transit/keys/essai-e17          # map[2:…] : la version 1 n'existe plus
   ```
   `min_decryption_version` est un **gel** réversible (la version est toujours là) : il répond à « rendre illisible d'un coup » tant qu'on n'a pas confirmé, et permet de revenir en arrière si une donnée encore utile était concernée. La destruction, irréversible, est `trim` : c'est le vrai **crypto-effacement** (plus aucune copie des fiches anciennes ne se déchiffre jamais, sauvegardes comprises). Pour un prestataire qui part : rewrap de ce qu'on garde, gel, vérification, puis trim.
6. **`medictl`.** Le module ([`transit.py`](fichiers/M25-E17/outils/src/medictl/transit.py)) n'a qu'une classe qui parle au réseau (`ClientTransit`), des opérations par lots de 100 (`batch_input`), des erreurs traduites en `ErreurApi` sans jamais citer le jeton (ni dans `repr`), `https://` exigé, et **`verify=` passé à chaque requête** : posé sur la session, il serait remplacé sans bruit par `REQUESTS_CA_BUNDLE` (essayé : la vérification a échoué contre l'autorité de développement tant que `verify` était sur la session, avec `REQUESTS_CA_BUNDLE` défini dans le shell). Les fonctions de champs (`chiffrer_champs`…) travaillent sur des structures JSON et se testent sans réseau ; `chiffrer` ne rechiffre pas un champ déjà chiffré (idempotent). Le CLI réécrit le fichier **atomiquement** (fichier `.tmp` puis `replace`). Tests : [`test_transit.py`](fichiers/M25-E17/outils/tests/python/test_transit.py) (lot en base64 et jeton en en-tête, erreur d'un élément du lot, 403 sans fuite du jeton, `http://` refusé, cycle chiffrer → rotation simulée → rechiffrer → déchiffrer).
7. **Les fiches.**
   ```
   admin@adm01:~/m25/e17$ cat fiche-intervention.json
   [{"vm": "gw01", "baie": "PAR1-A3", "code_baie": "4821", "astreinte_tel": "06 00 00 00 01", "prestataire": "InfoGér"}, …]
   admin@adm01:~/m25/e17$ BAO_TOKEN="$(<CONNEXION-APPROLE-MEDICTL-D-E07>)" medictl transit chiffrer fiche-intervention.json -c code_baie -c astreinte_tel
   5 champ(s) chiffré(s) dans fiche-intervention.json
   admin@adm01:~/m25/e17$ bao write -f transit/keys/medictl-donnees/rotate            # identité plateforme-admins
   admin@adm01:~/m25/e17$ BAO_TOKEN=… medictl transit rechiffrer fiche-intervention.json -c code_baie -c astreinte_tel
   admin@adm01:~/m25/e17$ jq -r '.[].code_baie' fiche-intervention.json               # vault:v2:… partout
   admin@adm01:~/m25/e17$ BAO_TOKEN=… bao write -f transit/keys/medictl-donnees/rotate
   Code: 403. Errors:
   * permission denied
   ```
   (Le jeton se met dans `BAO_TOKEN` par une substitution de commande, jamais tapé ni affiché.) Le refus est voulu : l'outil qui **utilise** la clé n'a pas à la gérer ; sinon une compromission de `medictl` permettrait de tourner la clé en boucle, ou pire si `transit/keys/*/config` était ouvert (rendre la clé exportable est **irréversible**).
8. **Clé de données et état OpenTofu.** Avec [`main.tf`](fichiers/M25-E17/essais/tofu-essai/main.tf) : un premier `apply` sans bloc `encryption` (état en clair), puis avec le bloc (repli `unencrypted`) :
   ```
   admin@adm01:~/m25/e17/tofu-essai$ tofu apply -auto-approve && jq -c keys terraform.tfstate
   ["encrypted_data","encryption_version","lineage","meta","serial"]
   admin@adm01:~/m25/e17/tofu-essai$ jq -r '.meta | keys[]' terraform.tfstate
   key_provider.openbao.essai
   ```
   Dans l'audit (ou la documentation) : `transit/datakey/plaintext/essai-e17` à chaque écriture (une clé de données neuve), `transit/decrypt/essai-e17` à chaque lecture (déchiffrer la clé de données rangée dans `meta`). Une politique pour un pipeline OpenTofu n'a besoin que de ces deux chemins. Après le retrait du repli, `tofu plan` est vide. Puis on retire `essai-e17` du code (MR ; `deletion_allowed = true` le permet) et :
   ```
   admin@adm01:~/m25/e17/tofu-essai$ tofu plan
   Error: Unable to fetch encryption key data
   key_provider.openbao.essai failed with error: failed to generate OpenBao … Code: 400
   ```
   L'état est **définitivement** illisible. Décision (note, § 4) : les états `secrets` et `identite` peuvent dépendre du coffre (on ne les applique pas sans lui) ; **`socle` ne doit pas** : c'est lui qui recrée `vault01-03` et `kms01` au PRA — un état chiffré par le coffre qu'il sert à reconstruire serait une dépendance circulaire.
9. **La note** : [`transit.md`](fichiers/M25-E17/medisphere/docs/securite/secrets/transit.md).

**Explications**

Transit sépare **la clé** (dans le coffre, jamais exportée) et **la donnée** (n'importe où). La sécurité ne repose plus sur la protection de chaque stockage, mais sur la politique d'OpenBao et sur son audit : voler la base ne suffit plus, il faut aussi une identité autorisée. Le prix : le coffre devient une dépendance de **lecture** des données (disponibilité, latence), d'où la grappe (E24) et la supervision (E27). Le versionnage des clés rend la rotation indolore (les anciennes versions déchiffrent toujours) et sépare trois gestes : tourner (protéger l'avenir), rechiffrer (rattraper le passé), effacer (rendre le passé illisible).

**Alternatives**

- **Chiffrement côté application avec une clé locale** (fichier, variable) : simple, mais la clé est partout où l'application tourne, et sa rotation demande de tout rechiffrer d'un coup.
- **Clé de données (`datakey/wrapped`)** pour de gros volumes : le coffre ne voit passer que des clés de 32 octets ; même principe que le fournisseur de clé d'OpenTofu.
- **Chiffrement convergent** (`derived` + `convergent_encryption` + `context`) : recherche par égalité possible, mais deux valeurs égales se voient égales.
- **Chiffrement transparent de la base** (TDE, pgcrypto avec une clé de session) : protège le disque, pas un administrateur de la base.

**Pièges classiques**

- Envoyer le clair sans base64 : `illegal base64 data at input byte …`.
- Gérer `min_decryption_version` ou la rotation dans OpenTofu : un `apply` peut défaire un gel d'incident.
- Donner `update` sur `transit/keys/*` à une identité applicative : elle peut rendre la clé **exportable** (sans retour) ou la tourner en boucle.
- Supprimer une clé « qui ne sert plus » : tout ce qu'elle a chiffré, y compris les sauvegardes et un état OpenTofu, est perdu. D'où `deletion_allowed = false` partout sauf sur la clé d'essai.
- Croire que `min_decryption_version` détruit : il gèle. Seul `trim` détruit, et il exige `min_encryption_version` d'abord.
- `session.verify` dans `requests` : remplacé par `REQUESTS_CA_BUNDLE` sans prévenir.

**En production chez MédiSphère**

Une clé par usage et par équipe, rotation annuelle automatique, rechiffrement planifié par le propriétaire de la donnée après chaque rotation (et alerte si des chiffrés restent sur une version ancienne), crypto-effacement documenté dans la politique de rotation (E33) et dans RB-250. Pour MédiAgenda : chiffrement de colonne avec contexte dérivé par patient, après un essai de charge et la grappe en place ; états OpenTofu `secrets` et `identite` migrés vers le fournisseur `openbao` (une clé par état) avec la politique de rotation (E33). Supervision : nombre de requêtes de transit et erreurs par clé (E27), alerte sur tout réglage de clé (E21).

---

### M25-E18 — Des secrets chiffrés dans Git : SOPS, age et transit

**Solution**

Fichiers : rôle [`binaire.yml`](fichiers/M25-E18/ansible/roles/outils_k8s/tasks/binaire.yml) et [`defaults/main.yml.extrait`](fichiers/M25-E18/ansible/roles/outils_k8s/defaults/main.yml.extrait) ; coffre [`transit.tf.extrait`](fichiers/M25-E18/secrets/tofu/transit.tf.extrait), [`politiques/sops-plateforme.hcl`](fichiers/M25-E18/secrets/politiques/sops-plateforme.hcl), [`variables.tf.extrait`](fichiers/M25-E18/secrets/tofu/variables.tf.extrait) ; dépôt [`sops-labo/`](fichiers/M25-E18/sops-labo/) (`.sops.yaml`, `.gitattributes`, `outils/verifier-chiffres.sh`, `.gitlab-ci.yml`, `README.md`) ; comparaison (version E18) [`comparatif-livraison-k8s.md`](fichiers/M25-E18/medisphere/docs/securite/secrets/comparatif-livraison-k8s.md).

1. **Outils.** `get_url` accepte `checksum: sha256:<URL>` (il cherche dans le fichier de sommes la ligne du **nom du fichier** téléchargé : `sops-v3.13.3.linux.amd64` y est) ou `sha256:<empreinte>` (age ne publie pas de fichier de sommes). Clé `brut: true` : mode `0755`, pas d'`unarchive`. Avant d'inscrire l'empreinte :
   ```
   admin@adm01:~/m25/e18$ cosign verify-blob --bundle sops-v3.13.3.checksums.sigstore.json \
       --certificate-identity https://github.com/getsops/sops/.github/workflows/release.yml@refs/tags/v3.13.3 \
       --certificate-oidc-issuer https://token.actions.githubusercontent.com sops-v3.13.3.checksums.txt
   Verified OK
   admin@adm01:~/m25/e18$ grep 'linux.amd64$' sops-v3.13.3.checksums.txt
   e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b  sops-v3.13.3.linux.amd64
   ```
   Le fichier de sommes ne couvre **pas** le `.deb` de SOPS : on installe le binaire, dont la somme est signée.
2. **SOPS + age.**
   ```
   admin@adm01:~$ mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt
   admin@adm01:~$ age-keygen -o ~/m25/e18/karim.txt          # clé « Karim » simulée
   admin@adm01:~/src/sops-labo$ sops edit k8s/wb-essais/essai.sops.yaml
   ```
   Pendant `sops edit`, le clair n'existe que dans un fichier temporaire (créé en 0600 dans le dossier temporaire, supprimé à la sortie de l'éditeur) ; jamais dans le dépôt. Le fichier chiffré garde `apiVersion`, `kind`, `metadata`, `type` lisibles ; `stringData` contient des `ENC[AES256_GCM,data:…,iv:…,tag:…,type:str]` ; la section `sops` liste chaque destinataire avec **sa** copie chiffrée de la clé de données (`age[].enc`, plus tard `hc_vault[].enc` en `vault:v1:…`), la date, la version de SOPS, `encrypted_regex` et le **MAC** (chiffré lui aussi). Modifier à la main `namespace: wb-essais` en `mediagenda-prod` (un champ **en clair**) :
   ```
   admin@adm01:~/src/sops-labo$ sops decrypt k8s/wb-essais/essai.sops.yaml
   MAC mismatch. File has E4C559F9…, computed 40DE91E4…
   ```
   Le MAC couvre tout le fichier : personne ne peut « recibler » un secret chiffré vers un autre espace sans pouvoir le déchiffrer.
3. **Historique.** Avec `git config --global diff.sopsdiffer.textconv "sops decrypt"`, `git log -p` montre les valeurs en clair à qui peut déchiffrer ; sans, les `ENC[…]` (rien ne fuit, mais la revue ne voit pas ce qui change).
4. **Contrôle en CI.** [`verifier-chiffres.sh`](fichiers/M25-E18/sops-labo/outils/verifier-chiffres.sh) (yq v4 de mikefarah ; le `yq` Python a une autre syntaxe) :
   ```
   admin@adm01:~/src/sops-labo$ outils/verifier-chiffres.sh k8s
   verifier-chiffres : k8s/wb-essais/oubli.yaml : objet Secret hors d'un fichier *.sops.yaml (en clair ?)
   verifier-chiffres : 1 problème(s)
   ```
   La MR de démonstration échoue en CI ; on la **ferme** et on supprime la branche. ⚠️ Le Secret fictif est quand même dans l'historique de cette branche (et dans le dépôt tant qu'elle existe) : c'est pour cela que la valeur est fictive. Avec une vraie valeur : rotation immédiate (RB-250).
5. **Retirer Karim.** `.sops.yaml` sans sa clé, puis `sops updatekeys -y k8s/wb-essais/essai.sops.yaml` (la clé de données est rechiffrée pour les seuls destinataires restants). Karim ne déchiffre plus le fichier de `main`… mais **il déchiffre toujours celui du commit précédent** (`git show HEAD~1:… | sops decrypt /dev/stdin` avec sa clé), et il a pu garder la clé de données. `sops rotate -i` change la clé de données (nouvelles valeurs chiffrées) : utile pour l'avenir, sans effet sur l'historique. La seule vraie réponse est de **tourner la valeur du secret** dans le système qui l'utilise.
6. **SOPS + transit.** MR dans `plateforme/secrets` (clé, politique, attachement aux groupes ; plan : 1 clé, 1 politique, 2 groupes modifiés). Puis `.sops.yaml` final ([fichier](fichiers/M25-E18/sops-labo/.sops.yaml) : transit + age « secours »), `sops updatekeys`, `sops rotate -i`.
   ```
   admin@adm01:~/src/sops-labo$ bao login -method=oidc        # écrit ~/.vault-token, que SOPS lit
   admin@adm01:~/src/sops-labo$ sops decrypt k8s/wb-essais/essai.sops.yaml | yq '.stringData | keys'
   admin@adm01:~/src/sops-labo$ mv ~/.vault-token ~/.vault-token.bak; sops decrypt k8s/wb-essais/essai.sops.yaml
   Failed to get the data key required to decrypt the SOPS file.
   Group 0: FAILED
     https://openbao.par1.medisphere.internal:8200/v1/transit/keys/sops-plateforme: FAILED
       - | … Code: 403. Errors: * permission denied
     age1…: FAILED
       - | failed to load age identities. Did not find keys in locations 'SOPS_AGE_SSH_PRIVATE_KEY_FILE', … '/home/admin/.ssh/id_ed25519', …
   admin@adm01:~/src/sops-labo$ mv ~/.vault-token.bak ~/.vault-token
   ```
   (Remarque : SOPS essaie aussi les clés SSH comme identités age.) `SOPS_HC_VAULT_ALLOWLIST` : sans elle (défaut `all`), SOPS contacte **l'adresse écrite dans le fichier chiffré** (`sops.hc_vault[].vault_address`) ou dans un `.sops.yaml` reçu, **avec ton jeton** : un fichier piégé ferait envoyer ton jeton OpenBao à un serveur de l'attaquant. Avec la liste, toute autre adresse est refusée (`Allowlist does not allow …`). Dans l'audit (E21) : une requête `update transit/decrypt/sops-plateforme` de ton identité OIDC par déchiffrement ; la clé de données apparaît en HMAC.
7. **Dans le cluster.** `sops decrypt … | kubectl apply -n wb-essais -f -` puis `kubectl delete secret essai-sops -n wb-essais`. Argo CD ne déchiffre pas SOPS : il faudrait un greffon de gestion de configuration (KSOPS pour Kustomize, helm-secrets pour Helm) dans le *repo-server*, avec **le droit de déchiffrer tous les fichiers de tous les dépôts** qu'il rend (une identité OpenBao ou une clé age dans le cluster) : le *repo-server* deviendrait la cible la plus intéressante du cluster.
8. **Comparaison** : [version E18](fichiers/M25-E18/medisphere/docs/securite/secrets/comparatif-livraison-k8s.md), complétée en E19.

**Explications**

SOPS chiffre **les valeurs** d'un fichier structuré avec une clé de données AES-256-GCM propre au fichier, puis chiffre cette clé pour chaque destinataire (*envelope encryption*) : age (X25519), une clé de transit, un KMS de cloud, PGP. Le MAC (HMAC sur toutes les valeurs, chiffré par la clé de données) empêche de modifier, ajouter ou retirer quoi que ce soit sans la clé. Avec transit, la clé de données ne se déchiffre que par un appel au coffre : l'accès se gère par politique et s'audite, mais **le chiffré, lui, reste dans Git pour toujours** — c'est la différence de fond avec ESO, où Git ne contient qu'une référence.

**Alternatives**

- **Groupes de clés à seuil** (`key_groups` + `shamir_threshold: 2`) : il faut deux destinataires pour déchiffrer (par exemple transit **et** une clé age personnelle).
- **Ansible Vault** : même idée (fichier chiffré dans Git), un seul mot de passe pour tout le fichier, pas de destinataires multiples ni de diff lisible ; reste l'outil de l'amorçage.
- **git-crypt** : chiffre des fichiers entiers (pas de diff de structure), clés GPG, pas de gestionnaire de clés.

**Pièges classiques**

- Chiffrer avec SOPS 3.13.2 (MAC erroné sur les listes YAML commentées : fichiers que 3.13.3 refuse ensuite).
- Oublier `encrypted_regex` : `metadata.name` chiffré, kustomize et la revue ne s'y retrouvent plus ; ou l'inverse, un champ sensible hors de `data`/`stringData` (annotation) laissé en clair.
- Croire que retirer un destinataire lui retire l'accès : l'historique Git se souvient.
- `BAO_TOKEN` défini mais pas `~/.vault-token` : SOPS ne trouve pas de jeton.
- Laisser `SOPS_HC_VAULT_ALLOWLIST` à `all`.
- Commiter le clair « une seconde » pour tester : il est dans l'historique.

**En production chez MédiSphère**

SOPS n'est pas retenu pour le cluster (ESO). S'il l'était pour d'autres fichiers : clé de transit par équipe, groupe à seuil pour la production, `SOPS_HC_VAULT_ALLOWLIST` posée par Ansible sur tous les postes et runners, contrôle `verifier-chiffres.sh` dans le composant `securite` (avec Gitleaks), clé age de secours hors ligne testée chaque trimestre.

---

### M25-E19 — Comparer : Sealed Secrets et Secrets Store CSI

**Solution**

Fichiers : [`charts.yaml.extrait`](fichiers/M25-E19/charts-miroir/charts.yaml.extrait) ; espaces [`essai-csi.yaml`](fichiers/M25-E19/k8s/espaces/essai-csi.yaml) et [`sealed-secrets.yaml`](fichiers/M25-E19/k8s/espaces/sealed-secrets.yaml) ; Applications [`essai-sealed-secrets.yaml`](fichiers/M25-E19/gitops/plateforme/essai-sealed-secrets.yaml), [`essai-csi-driver.yaml`](fichiers/M25-E19/gitops/plateforme/essai-csi-driver.yaml), [`essai-openbao-csi.yaml`](fichiers/M25-E19/gitops/plateforme/essai-openbao-csi.yaml) et leurs [`valeurs/`](fichiers/M25-E19/gitops/valeurs/) ; coffre [`essais-m25.tf`](fichiers/M25-E19/secrets/tofu/essais-m25.tf), [`essai-csi.hcl`](fichiers/M25-E19/secrets/politiques/essai-csi.hcl) ; objets d'essai [`secret-a-sceller.yaml`](fichiers/M25-E19/essais/secret-a-sceller.yaml), [`essai-csi.yaml`](fichiers/M25-E19/essais/essai-csi.yaml) ; `kubeseal` : [`defaults/main.yml.extrait`](fichiers/M25-E19/ansible/roles/outils_k8s/defaults/main.yml.extrait) ; comparaison complète [`comparatif-livraison-k8s.md`](fichiers/M25-E19/medisphere/docs/securite/secrets/comparatif-livraison-k8s.md).

1. **Charts.** Empreintes (champ `digest` des index, identiques au `sha256sum` des archives) : `sealed-secrets-2.20.0.tgz` `6092d219…b990ef`, `secrets-store-csi-driver-1.6.1.tgz` `d312041d…97e1b6`, `openbao-0.30.4.tgz` `f9d464f0…bb96b`. Le chart `sealed-secrets` vient de `https://bitnami.github.io/sealed-secrets` (le **projet**), pas de `bitnamicharts`.
2. **Espaces et Applications.** `essai-csi` en `privileged` avec l'annotation d'exception (le pilote monte des volumes dans les pods : conteneur privilégié, `hostPath` vers `/var/lib/kubelet` ; le fournisseur dépose sa socket dans un `hostPath`) ; `sealed-secrets` en `restricted`. Le finaliseur `resources-finalizer.argocd.argoproj.io` fait **supprimer en cascade** tout ce que l'Application a créé quand on la supprime : pour un essai, c'est la désinstallation complète en une MR (CRD comprises) ; pour kube-prometheus-stack (M21), on l'avait refusé parce qu'une suppression accidentelle aurait emporté les CRD et donc tous les objets des équipes. Ordre de synchronisation : `essai-csi-driver` avant `essai-openbao-csi` (le fournisseur se branche sur le pilote).
3. **Sealed Secrets.**
   ```
   admin@adm01:~/m25/e19$ kubeseal --fetch-cert --controller-namespace sealed-secrets > scelle.pem
   admin@adm01:~/m25/e19$ kubeseal --cert scelle.pem --format yaml < secret-a-sceller.yaml > sealedsecret.yaml && shred -u secret-a-sceller.yaml
   admin@adm01:~/m25/e19$ kubectl apply -n wb-essais -f sealedsecret.yaml
   admin@adm01:~/m25/e19$ kubectl -n wb-essais get secret essai-scelle -o jsonpath='{.metadata.ownerReferences[0].kind}'
   SealedSecret
   ```
   La copie renommée (`metadata.name: essai-scelle-2`) : le contrôleur refuse (événement `ErrUnsealFailed`, « no key could decrypt secret ») — en portée `strict`, l'espace **et** le nom sont des données associées du chiffrement : un `SealedSecret` ne se déplace ni ne se renomme. `namespace-wide` : le nom peut changer, pas l'espace ; `cluster-wide` : n'importe où (annotation `sealedsecrets.bitnami.com/cluster-wide: "true"` posée par `kubeseal --scope cluster-wide`) — à éviter, tout espace où l'on peut créer un objet le descelle.
4. **La clé du contrôleur.**
   ```
   admin@adm01:~$ kubectl -n sealed-secrets get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o name
   secret/sealed-secrets-keyxxxxx
   admin@adm01:~$ ( umask 077; kubectl -n sealed-secrets get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > ~/m25/e19/cle.yaml )
   admin@adm01:~$ kubeseal --recovery-unseal --recovery-private-key ~/m25/e19/cle.yaml < ~/m25/e19/sealedsecret.yaml | jq -r '.data | keys[]'
   mot_de_passe
   admin@adm01:~$ shred -u ~/m25/e19/cle.yaml
   ```
   Une nouvelle clé tous les `keyrenewperiod` (30 jours) ; les anciennes sont **gardées** pour desceller l'existant. Conséquences : (a) sans sauvegarde de ces Secrets, un cluster reconstruit ne descelle plus rien de ce qui est dans Git ; (b) avec une sauvegarde, celle-ci descelle **tout l'historique Git**, hors du cluster : c'est un secret de premier rang, plus sensible que chacun des secrets qu'il protège ; (c) aucun audit ne dit qui l'a utilisée.
5. **Pilote CSI.**
   ```
   admin@adm01:~$ bao kv put -mount=kv plateforme/essais/csi-demo message="bonjour depuis OpenBao (v1)"
   admin@adm01:~$ kubectl apply -n wb-essais -f ~/m25/e19/essai-csi.yaml
   admin@adm01:~$ kubectl -n wb-essais logs essai-csi --tail=1
   10:42:07 fichier=bonjour depuis OpenBao (v1) env=bonjour depuis OpenBao (v1)
   admin@adm01:~$ bao kv put -mount=kv plateforme/essais/csi-demo message="bonjour depuis OpenBao (v2)"
   admin@adm01:~$ kubectl -n wb-essais logs essai-csi --tail=1      # après ≤ 2 min
   10:44:37 fichier=bonjour depuis OpenBao (v2) env=bonjour depuis OpenBao (v1)
   ```
   Le fichier suit (rotation du pilote, plus le cache de l'agent), la variable non : elle est lue au démarrage du conteneur (et le Secret recopié n'est mis à jour qu'avec la rotation). Politique retirée puis pod recréé : il reste en **`ContainerCreating`**, événement `FailedMount` (`… failed to mount secrets store objects … permission denied`) : le pod **ne démarre pas** tant que le coffre ne délivre pas. Avec ESO, le Secret existe déjà : le pod démarre, seule la mise à jour s'arrête (`SecretSyncedError` sur l'`ExternalSecret`). Dans l'audit : `auth/k8s-par1/login` du rôle `essai-csi` avec `auth.metadata.service_account_name = essai-csi`, `service_account_namespace = wb-essais` — l'identité **du pod**, pas celle d'un contrôleur.
6. **Mesures** : à reporter dans le tableau de la comparaison (`container_memory_working_set_bytes{namespace=~"sealed-secrets|essai-csi"}` dans Prometheus, délais relevés à l'étape 5). etcd : Sealed Secrets et ESO y mettent un Secret ; CSI seul n'y met rien (sauf `secretObjects`, utilisé ici pour la comparaison).
7. **Décision** : voir la [comparaison](fichiers/M25-E19/medisphere/docs/securite/secrets/comparatif-livraison-k8s.md) — ESO seul retenu ; CSI non retenu (pilote privilégié sur chaque nœud, rotation alpha, démarrage dépendant du coffre, pas de besoin réel « aucun secret dans etcd » aujourd'hui) ; Sealed Secrets non retenu (clé privée du contrôleur, pas de retrait d'accès sur l'historique, pas d'audit) ; SOPS réservé aux dépôts d'essai.
8. **Désinstallation** : `kubectl delete -n wb-essais -f ~/m25/e19/essai-csi.yaml` et le `SealedSecret` ; MR qui supprime les trois Applications (cascade) ; MR qui retire les deux espaces de `plateforme/k8s/espaces/` (puis `kubectl delete namespace` si l'outil d'application des espaces ne supprime pas, comme au M21) ; MR qui retire `essais-m25.tf` et `essai-csi.hcl` (`2 to destroy`) et `bao kv metadata delete -mount=kv plateforme/essais/csi-demo` ; MR qui retire les entrées de `charts-miroir` et `kubeseal`. Puis `lab/bin/check 25 19`.

**Explications**

Les trois approches répondent à la même question — comment un secret arrive dans un pod sans être en clair dans Git — par trois architectures : **chiffrer pour le cluster** (Sealed Secrets : asymétrique, la clé privée vit dans le cluster), **chiffrer pour des personnes et un KMS** (SOPS), **référencer** une valeur qui reste dans un coffre (ESO, CSI). La différence entre ESO et CSI tient à **qui** lit le coffre (un contrôleur par espace, ou chaque pod) et à **quand** (en continu, ou au montage du volume) : CSI donne une traçabilité par pod et évite etcd, au prix d'une dépendance forte au démarrage et d'un composant privilégié sur chaque nœud.

**Alternatives**

- **Injecteur d'agent OpenBao** (`openbao-k8s`) : un conteneur agent dans chaque pod, rendu de modèles, renouvellement des baux ; pas de Secret Kubernetes, mais un conteneur de plus par pod.
- **vault-secrets-operator** (HashiCorp) : non documenté avec OpenBao.
- **Chiffrement d'etcd** (`secretbox`, M14) : complément, pas alternative (il protège le disque d'etcd, pas l'API).

**Pièges classiques**

- Installer le chart `bitnamicharts/sealed-secrets` (catalogue retiré) au lieu de celui du projet.
- Oublier que `kubeseal --fetch-cert` passe par le proxy de l'API (droit lié à `system:authenticated` par le chart) : un poste sans accès à l'API scelle avec un certificat copié, à garder à jour après chaque renouvellement de clé.
- Audience absente de la `SecretProviderClass` alors que le rôle l'exige : `FailedMount` avec une erreur d'authentification qui fait chercher du côté de la politique.
- Supprimer l'espace `sealed-secrets` en croyant que les `SealedSecret` de Git « resteront valables » : sans la clé, ils sont perdus (c'est voulu ici).
- Laisser les DaemonSets d'essai en place : mémoire sur chaque nœud, et un conteneur privilégié de plus dans le cluster.

**En production chez MédiSphère**

Une seule voie (ESO), documentée et vérifiée par une règle d'admission au M26 (refus d'un `SealedSecret` ou d'une `SecretProviderClass` hors d'une exception écrite). Réexamen de CSI si une exigence HDS impose « aucun secret dans etcd ». La comparaison est une pièce du dossier d'audit HDS, avec ses mesures.

---

### M25-E20 — Signer avec une clé qui ne sort jamais du coffre

**Solution**

Fichiers : [`transit.tf.extrait`](fichiers/M25-E20/secrets/tofu/transit.tf.extrait), [`politiques/cosign-signature.hcl`](fichiers/M25-E20/secrets/politiques/cosign-signature.hcl), [`gitlab-signature.tf`](fichiers/M25-E20/secrets/tofu/gitlab-signature.tf), [`terraform.tfvars.extrait`](fichiers/M25-E20/secrets/tofu/terraform.tfvars.extrait) ; composant [`template.yml.extrait`](fichiers/M25-E20/ci-templates/templates/securite/template.yml.extrait) (v2.10.0) ; [`charts-miroir/outils/signer.sh`](fichiers/M25-E20/charts-miroir/outils/signer.sh) et [`.gitlab-ci.yml.extrait`](fichiers/M25-E20/charts-miroir/.gitlab-ci.yml.extrait) ; retraits dans `plateforme/k8s` : [`values.yaml.extrait`](fichiers/M25-E20/k8s/composants/gitlab-runner-protege/values.yaml.extrait), [`secrets-k8s.conf.extrait`](fichiers/M25-E20/k8s/outils/secrets-k8s.conf.extrait), sortie réseau [`40-politiques-reseau.yaml.extrait`](fichiers/M25-E20/k8s/espaces/ci-jobs-protege/40-politiques-reseau.yaml.extrait) ; décision [`cle-signature.md`](fichiers/M25-E20/medisphere/docs/securite/secrets/cle-signature.md).

1. **Essai à blanc.** Depuis OpenBao 2.4, l'API ne crée plus de dispositif d'audit, même en `-dev` : on le déclare dans un fichier ajouté par `-config`.
   ```
   admin@adm01:~/m25/e20$ printf 'audit "file" "essai" {\n  options {\n    file_path = "%s/audit.log"\n  }\n}\n' "$PWD" > audit.hcl
   admin@adm01:~/m25/e20$ bao server -dev -dev-listen-address=127.0.0.1:8300 -config=audit.hcl > serveur.log 2>&1 &
   admin@adm01:~/m25/e20$ export BAO_ADDR=http://127.0.0.1:8300 BAO_TOKEN=<JETON-RACINE-DU-DEV, affiché dans serveur.log>
   admin@adm01:~/m25/e20$ bao secrets enable transit && bao write transit/keys/cosign-medisphere type=ecdsa-p256
   admin@adm01:~/m25/e20$ cosign public-key --key hashivault://cosign-medisphere > essai.pub
   admin@adm01:~/m25/e20$ cosign sign-blob --yes --key hashivault://cosign-medisphere \
       --signing-config /etc/medisphere/signing-config.json --bundle a.bundle a.txt
   admin@adm01:~/m25/e20$ cosign verify-blob --key essai.pub --insecure-ignore-tlog=true --bundle a.bundle a.txt
   Verified OK
   admin@adm01:~/m25/e20$ jq -r 'select(.type=="request") | .request.operation + " " + .request.path' audit.log | sort -u
   read transit/keys/cosign-medisphere
   update transit/sign/cosign-medisphere/sha2-256
   ```
   (Sans `--signing-config` ni `--bundle`, Cosign 3 refuse : « must specify --bundle with --new-bundle-format ».) Le jeton racine du serveur de développement n'existe que le temps de l'essai, sur la boucle locale ; on arrête le serveur ensuite (`kill %1`).
2. **En code.** Clé et politique sans surprise. Le rôle, d'abord en `vault_jwt_auth_backend_role` avec `bound_claims = { ref_protected = "true", runner_id = "12" }` : la connexion échoue (« claim "runner_id" does not match any associated bound claim values »), et `bao read auth/gitlab/role/ci-signature` montre `runner_id: ["12"]` — une **chaîne**, alors que GitLab émet `"runner_id": 12`, un **nombre** (exemple de jeton de la documentation et jeton réel du M19-E25). Le type `glob` refuse un nombre à l'écriture (« claim is not a string ») ; le type `string` accepte un nombre **si la valeur liée est un nombre**. Le fournisseur ne sait pas l'écrire : [`gitlab-signature.tf`](fichiers/M25-E20/secrets/tofu/gitlab-signature.tf) passe par `vault_generic_endpoint` (JSON tel quel), avec l'identifiant du runner en variable numérique ([`terraform.tfvars.extrait`](fichiers/M25-E20/secrets/tofu/terraform.tfvars.extrait)). Plan vide après l'apply (`ignore_absent_fields`).
3. **Le composant** ([extrait v2.10.0](fichiers/M25-E20/ci-templates/templates/securite/template.yml.extrait)) : **deux** connexions dans `securite:signature`. La première est celle de `.openbao-connexion` (v2.9.0, inchangée) : rôle du projet (`role_openbao`, défaut vide → `ci-<groupe>-<projet>`), jeton dans `~/.vault-token`, lecture du robot Harbor dans des variables du shell. La seconde prend le rôle de signature, par une **nouvelle** entrée `role_signature` (défaut `ci-signature`) : redéfinir `role_openbao` à `ci-signature` aurait aussi basculé `securite:verification` (et tout job qui étend `.openbao-connexion`) sur un rôle qui ne lit pas le robot Harbor, et le job de signature lui-même n'aurait plus eu de quoi remplir `HARBOR_ROBOT_*`. Même jeton d'identité (`id_tokens`, audience `openbao.medisphere.internal`) pour les deux, connexion par un JSON sur l'entrée standard (`printf` est interne au shell : le JWT n'apparaît pas dans `ps`), `BAO_ADDR`/`BAO_TOKEN` exportés pour Cosign, mêmes `cosign sign`/`attest` qu'en v2.8.0 avec `--key hashivault://cosign-medisphere`, `bao token revoke -self` à la fin pour le jeton de signature (d'où `auth/token/revoke-self` dans la politique : le rôle retire `default`), l'`after_script` de `.openbao-connexion` révoquant celui du projet. La racine MédiSphère vient de `SSL_CERT_DIR` (configuration du runner, M19-E07) ; la sortie vers `openbao…:8200` doit exister dans `ci-jobs-protege` (ajoutée en E10, sinon [extrait](fichiers/M25-E20/k8s/espaces/ci-jobs-protege/40-politiques-reseau.yaml.extrait)). Nouvelle image `outils-supply-chain` avec la nouvelle clé publique dans `/etc/medisphere/cosign.pub` ; entrée `cosign_pub_sha256` du composant `deploiement` mise à jour. `charts-miroir` : même connexion dans le job `signer`, et [`signer.sh`](fichiers/M25-E20/charts-miroir/outils/signer.sh) signe par la clé du coffre.
4. **Bascule.**
   ```
   admin@adm01:~/medisphere$ git mv docs/registre/cosign.pub docs/registre/cosign-m13.pub
   admin@adm01:~/medisphere$ cosign public-key --key hashivault://cosign-medisphere > docs/registre/cosign.pub   # BAO_ADDR, jeton OIDC
   admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true \
       registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.9.0 > /dev/null && echo nouvelle-cle-ok
   admin@adm01:~$ cosign verify --key ~/medisphere/docs/registre/cosign-m13.pub --insecure-ignore-tlog=true \
       registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.9.0
   Error: no matching signatures
   ```
   Le job `securite:signature` tourne sur `k8s-par1-protege` (sur un autre runner, la connexion serait refusée par la condition `runner_id`). Au pipeline planifié de `charts-miroir`, `signer.sh` vérifie chaque chart avec la **nouvelle** clé publique : ceux qui n'étaient signés que par l'ancienne sont re-signés — la re-signature des charts se fait toute seule.
5. **Re-signer ce qui est déployé.** Liste (`kustomize build overlays/recette` et `overlays/prod` de `mediagenda/deploiement`, `yq` des champs `image`), puis pour chaque image qui ne vérifie pas avec la nouvelle clé :
   ```
   admin@adm01:~$ cosign sign --key hashivault://cosign-medisphere --signing-config /etc/medisphere/signing-config.json \
       --annotations ticket=CHG-2620 registry.par1.medisphere.internal/medisphere/mediagenda-api@sha256:<EMPREINTE>
   ```
   (Par empreinte, jamais par étiquette ; ton identité `plateforme-admins` a `transit/sign/*` depuis E17 ; connexion à Harbor par ton secret CLI OIDC, sur l'entrée standard.) Les attestations SBOM et provenance de ces versions restent signées par l'ancienne clé : on les ré-atteste de la même façon si la porte de déploiement les vérifie (elle le fait depuis M19-E29), à partir des artefacts du pipeline d'origine.
6. **Retrait.** Montage du runner protégé et ligne `cosign-ci` retirés (MR), Secret supprimé (`kubectl -n ci-jobs-protege delete secret cosign-medisphere`), `secrets/cosign-ci.yml` supprimé, variables Cosign restantes supprimées (API des variables de groupe et de projet) ; procès-verbal de destruction (copies hors ligne de l'ancienne clé privée détruites, deux signataires). Preuves de refus (jetons d'un job d'essai de `formation/ci-labo`) : branche non protégée → `claim "ref_protected" does not match any associated bound claim values` ; projet d'un autre groupe → `claim "namespace_path" does not match …` ; runner `k8s-par1` → `claim "runner_id" does not match …`.
7. **Écrire** : [`cle-signature.md`](fichiers/M25-E20/medisphere/docs/securite/secrets/cle-signature.md).

**Explications**

Cosign ne connaît pas OpenBao : il parle l'API transit de Vault (`hashivault://`), qu'OpenBao sert à l'identique. La clé privée ne quitte jamais le coffre : Cosign calcule l'empreinte SHA-256 du contenu à signer et demande `transit/sign/<clé>/sha2-256` ; OpenBao renvoie la signature `vault:v1:<base64>` que Cosign décode. Le contrôle d'accès passe de « qui peut lire un fichier sur ce runner » à « quel job, de quel projet, sur quelle référence, sur quel runner », écrit dans un rôle et tracé dans l'audit avec le projet, la référence et le pipeline (`claim_mappings`). Une nouvelle clé plutôt qu'un import : la promesse « la clé n'est jamais sortie » n'est vraie que pour une clé **née** dans le coffre.

**Alternatives**

- **Importer l'ancienne clé** (`bao transit import`, enveloppement RSA-OAEP + AES-KWP) : aucune re-signature, mais une clé qui a vécu hors du coffre.
- **Repli** si `hashivault://` cessait de fonctionner : clé Cosign classique dans `kv/plateforme/cosign/medisphere`, lue par le seul rôle `ci-signature` et écrite sur un `tmpfs` du job (la clé sort du coffre à chaque signature, mais c'est tracé et révocable).
- **Signature sans clé** (*keyless*, Fulcio) : identité OIDC du job dans un certificat éphémère ; demande d'héberger Fulcio (et Rekor) en interne.
- **Deux rôles** (`ci-signature-applications` par `namespace_path`, `ci-signature-charts` par `project_path` exact) : plus étroit que la liste de groupes, qui inclut tout le groupe `plateforme`.

**Pièges classiques**

- `vault_jwt_auth_backend_role` pour lier `runner_id` : la condition n'est **jamais** vraie (chaîne contre nombre), et le premier réflexe est de retirer la condition « pour que ça marche ».
- `transit/sign/cosign-medisphere` sans `/sha2-256` dans la politique : `permission denied` sur le chemin réellement appelé.
- `token_no_default_policy` sans `auth/token/revoke-self` : le job ne peut plus révoquer son jeton.
- JWT en argument (`bao write … jwt=$OPENBAO_ID_TOKEN`) : visible par `ps` dans le conteneur du job.
- Changer `docs/registre/cosign.pub` **avant** d'avoir publié l'image outillée et mis à jour la porte de déploiement : toutes les promotions échouent.
- `bao write transit/keys/cosign-medisphere/config exportable=true` par erreur : irréversible ; d'où le `deny` dans la politique de signature et l'alerte d'E21.
- Oublier `charts-miroir`, qui signait encore avec une variable de CI.

**En production chez MédiSphère**

Clé de signature changée tous les deux ans ou sur incident (procédure de `cle-signature.md`, vérificateurs d'abord), alerte sur toute requête de signature hors du runner protégé (impossible par le rôle, mais l'audit le prouve) et sur tout réglage de la clé ; revue trimestrielle des signatures par projet (requête d'audit d'E21) ; Kyverno (M26) ne fait confiance qu'à `docs/registre/cosign.pub`. Ce que le M26 consomme : la clé publique, son empreinte, et la liste des registres signés.

---

### M25-E21 — Audit : qui a lu quel secret

**Solution**

Fichiers : rôle `openbao` [`defaults/main.yml.extrait`](fichiers/M25-E21/ansible/roles/openbao/defaults/main.yml.extrait), [`openbao.hcl.j2.extrait`](fichiers/M25-E21/ansible/roles/openbao/templates/openbao.hcl.j2.extrait), [`tasks/audit.yml`](fichiers/M25-E21/ansible/roles/openbao/tasks/audit.yml), [`logrotate-openbao-audit.j2`](fichiers/M25-E21/ansible/roles/openbao/templates/logrotate-openbao-audit.j2) ; rôle `alloy` [`defaults`](fichiers/M25-E21/ansible/roles/alloy/defaults/main.yml.extrait) et [`config.alloy.j2.extrait`](fichiers/M25-E21/ansible/roles/alloy/templates/config.alloy.j2.extrait), [`group_vars/role_coffre/alloy.yml`](fichiers/M25-E21/ansible/inventories/lab/group_vars/role_coffre/alloy.yml) ; règles [`regles/audit/openbao.yaml`](fichiers/M25-E21/observabilite/loki/regles/audit/openbao.yaml) et [`regles/plateforme/openbao.yaml`](fichiers/M25-E21/observabilite/loki/regles/plateforme/openbao.yaml) (à ajouter aux `configMapGenerator` des locataires `audit` et `plateforme` de `loki/kustomization.yaml`, M22-E08) ; politique [`plateforme-admin.hcl.extrait`](fichiers/M25-E21/secrets/politiques/plateforme-admin.hcl.extrait) ; documentation [`audit-openbao.md`](fichiers/M25-E21/medisphere/docs/securite/secrets/audit-openbao.md).

1. **L'API refuse.**
   ```
   admin@adm01:~$ bao audit enable file file_path=/var/log/openbao/audit.log
   Code: 400. Errors:
   * cannot enable audit device via API; use declarative, config-based audit device management instead
   ```
   CVE-2025-6000 : un dispositif `file` créé par l'API pouvait écrire **n'importe où** sur le nœud avec les droits du service (et, avec `prefix`, un contenu choisi) — de quoi déposer un greffon et exécuter du code. Depuis 2.4, `unsafe_allow_api_audit_creation` vaut faux ; les dispositifs se déclarent dans la configuration : créés ou retirés **sur le nœud actif** au démarrage et à chaque SIGHUP, **immuables** (changer une option = nouveau chemin), identiques sur tous les nœuds.
2. **Déclarer.** Après le playbook (`--limit vault01 --tags openbao_configuration,openbao_audit`), le rôle prévient qu'un redémarrage serait nécessaire (il ne sait pas quelle partie a changé) : pour l'audit, **SIGHUP suffit**, et un redémarrage scellerait le nœud.
   ```
   root@vault01:~# systemctl reload openbao && journalctl -u openbao -n 5 --no-pager | grep -i audit
   … core: adding new audit device: path=fichier/
   … core: enabled audit backend: path=fichier/ type=file
   admin@adm01:~$ bao audit list -detailed
   Path        Type    Description                                                          Replication    Options
   fichier/    file    Journal d'audit local, envoyé à Loki (locataire audit) par Alloy    replicated     file_path=/var/log/openbao/audit.log mode=0640
   admin@adm01:~$ bao audit disable fichier
   * cannot disable configuration-managed audit device
   ```
3. **Lire une ligne** (`sudo jq -c 'select(.request.path=="kv/data/mediagenda/prod/valkey")' /var/log/openbao/audit.log`) : `type`, `time`, `auth` (`display_name` comme `oidc-<identifiant>` ou `approle`, `policies`, `metadata`, `accessor` en clair), `request` (`id`, `operation`, `path`, `remote_address`, `mount_type`), `response.data` (valeurs des secrets en `hmac-sha256:…` ; nombres et booléens jamais hachés — `version`, `destroyed` — et quelques chaînes laissées en clair par le moteur, comme `created_time`). Un refus a `error: "permission denied"`. HMAC d'une valeur :
   ```
   admin@adm01:~$ read -rs v; printf '%s' "$v" | jq -Rs '{input: .}' | bao write -field=hash sys/audit-hash/fichier - ; unset v
   hmac-sha256:242806242596c6817c300f509415d80712f33cf78884431ddc492ed1cf1cb7ec
   root@vault01:~# grep -c 'hmac-sha256:242806242596c6817c' /var/log/openbao/audit.log
   ```
   Jamais audités (liste de la documentation) : `sys/init`, `sys/seal-status`, `sys/unseal`, `sys/leader`, `sys/health`, `sys/storage/raft/bootstrap`, `sys/storage/raft/join` (et `sys/metrics` non authentifié). La documentation cite aussi `sys/seal`, mais OpenBao 2.6.4 journalise bel et bien la **requête** de scellement (ligne `request`, sans `response` : vérifié sur un serveur de développement) — heureusement, puisque c'est un geste d'incident.
4. **Acheminer.** Alloy (groupe `openbao`) lit le fichier et l'envoie au locataire `audit` (`loki.source.file` → `loki.write` dédié) ; `tail_from_end` évite de renvoyer l'historique au premier démarrage. Après `logrotate -f`, aucune ligne ne manque : logrotate **renomme** le fichier (Alloy finit de lire l'ancien) puis en crée un neuf, et SIGHUP fait rouvrir le fichier à OpenBao ; avec `copytruncate`, des lignes écrites entre la copie et la troncature seraient perdues.
5. **Interroger** : requêtes de [`audit-openbao.md`](fichiers/M25-E21/medisphere/docs/securite/secrets/audit-openbao.md), par exemple :
   ```logql
   {service="openbao"} | json type="type", chemin="request.path", operation="request.operation", qui="auth.display_name", ip="request.remote_address"
     | type="response" | operation="read" | chemin=~"kv/data/mediagenda/prod/.*" | line_format "{{.qui}} {{.ip}} {{.chemin}}"
   ```
6. **La panne de l'audit** (OpenBao de développement, dispositif déclaré par `-config`, fichier remplacé par un dossier puis `kill -HUP`) :
   ```
   admin@adm01:~$ bao kv get -mount=kv essai
   Code: 500. Errors:
   * internal error
   … [ERROR] core: failed to audit request: path=…
   … no audit backend succeeded in logging the response
   ```
   OpenBao **refuse de répondre sans trace**. Conséquences : surveiller l'espace de `/var/log` et le journal du service (alerte `OpenBaoAuditImpossible`), et, à terme, un second dispositif (la requête passe si **un** dispositif écrit).
7. **Alerter.** Règles chargées (`/prometheus/api/v1/rules`, en-têtes `X-Scope-OrgID: audit` puis `plateforme`) ; la MR de la politique `plateforme-admin` (droits `sys/audit`, `sys/audit-hash/*`) déclenche `OpenBaoPolitiqueModifiee` (`firing` au plus une à deux minutes après l'apply), courriel `plateforme@` dans Mailpit.

**Explications**

L'audit d'OpenBao est **synchrone** et **bloquant** : une réponse ne part que si au moins un dispositif l'a écrite. C'est une garantie forte (rien sans trace) et une dépendance de disponibilité. Les valeurs sont hachées avec un sel propre au dispositif (HMAC) : le journal peut circuler (Loki, 1 an) sans exposer les secrets, et `sys/audit-hash` permet de retrouver une valeur connue. Les accessors en clair facilitent la réponse à incident (révocation directe) ; un accessor ne permet que de consulter ou révoquer un jeton, avec un droit dédié.

**Alternatives**

- **Second dispositif** `syslog` (journald) ou `socket` (vers Alloy) : redondance, mais il faut le garder hors du locataire `plateforme`.
- **`http`** (2.4+) : envoi direct à un collecteur, conseillé pour de faibles volumes.
- **Fichier sur une partition dédiée** : une saturation de `/var/log` par un autre service n'arrêterait plus le coffre.
- `unsafe_allow_api_audit_creation = true` : retour à l'ancien comportement ; refusé (CVE-2025-6000).

**Pièges classiques**

- Modifier une option d'un dispositif déclaré et croire qu'elle s'applique : refusée au rechargement, l'ancien reste — lire le journal du service après chaque SIGHUP.
- `copytruncate` dans logrotate (lignes perdues) ou oubli du SIGHUP (OpenBao écrit dans le fichier renommé, puis compressé : lignes perdues pour Alloy).
- Envoyer l'audit au locataire `plateforme` : 14 jours de rétention au lieu d'un an, lecteurs plus nombreux.
- Étiqueter les flux Loki avec le chemin ou l'identité : explosion de la cardinalité.
- Redémarrer `vault01` « pour appliquer » : il se scelle.
- Ajouter Alloy au groupe `openbao` sans redémarrer Alloy : l'appartenance ne vaut que pour les processus lancés après (« permission denied » dans le journal d'Alloy).
- Un SIGHUP de logrotate applique aussi une configuration écrite mais pas encore voulue (certificat, dispositifs).

**En production chez MédiSphère**

Dispositifs déclarés identiques sur les trois nœuds et sur `kms01` (E24, E25), partition `/var/log` surveillée, métrique d'échec d'audit (E27), revue mensuelle des lectures de secrets de production par la RSSI (requête enregistrée dans Grafana), conservation d'un an (HDS) et export trimestriel signé pour l'auditeur. Les règles d'alerte d'audit sont relues avec chaque nouveau moteur (base de données, PKI).

---

### M25-E22 — Revue : les politiques du stagiaire

**Solution**

Revue, du plus grave au moins grave (fichiers de [`ressources/M25-E22/`](../ressources/M25-E22/)) :

| # | Fichier, bloc | Gravité | Défaut | Scénario | Correction |
|---|---|---|---|---|---|
| 1 | `medidoc-ci.hcl`, `path "*"` | bloquant | lecture et liste de **tout** le coffre | la CI de MédiDoc lit `kv/data/mediagenda/prod/*`, `kv/data/plateforme/*`, les politiques, les `role_id`… ; un job de branche (défaut 4) aussi | chemins exacts lus par le job (relevés dans l'audit) ; jamais de `*` « temporaire » |
| 2 | `medidoc-dev.hcl`, `kv/data/*` | bloquant | écriture et lecture des secrets de **toutes** les équipes | un membre de `medidoc` lit et **remplace** `kv/data/mediagenda/prod/valkey` | `kv/data/medidoc/dev/*` |
| 3 | `medidoc-dev.hcl`, `kv/metadata/*` avec `delete` | bloquant | `delete` sur les métadonnées **détruit toutes les versions** d'un secret, définitivement | `bao kv metadata delete kv/plateforme/argocd/oidc` par un membre de `medidoc` : secret perdu | `read`, `list` sur `kv/metadata/medidoc/dev/*` ; suppression réversible par `kv/delete/…` ; destruction réservée à la plateforme |
| 4 | `medidoc.tf`, rôle JWT, `bound_claims` | bloquant | aucune condition sur la **référence** ; `project_path = "medidoc/*"` en glob : tous les projets du groupe | une branche non protégée, ou un projet bac à sable créé dans `medidoc`, obtient le jeton de la CI de production | un rôle par projet, `project_id` (stable) **et** `ref_protected = "true"` (comparaison `string`) |
| 5 | `medidoc.tf`, rôle Kubernetes, `["*"]`/`["*"]` | bloquant | **tout** compte de service de **tout** espace | un pod de `wb-essais` (ou d'une application compromise) lit les secrets de production de MédiDoc | un rôle par espace (`eso-medidoc-dev`), compte `eso`, espace exact |
| 6 | `medidoc.tf`, AppRole, `bind_secret_id = false` + `0.0.0.0/0` | bloquant | le `role_id` suffit pour se connecter, de partout ; or le `role_id` n'est pas un secret (dans l'état, en sortie `output`, dans les journaux de la CI) | quiconque lit la sortie du plan obtient un jeton `medidoc-ci` (donc tout le coffre, défaut 1) | `bind_secret_id = true`, `secret_id` et jeton liés à `runner02` (10.10.20.17/32), `secret_id` de 90 jours remis par enveloppement (E28) ; pas d'`output` |
| 7 | `medidoc-dev.hcl`, `sys/leases/revoke-prefix/db-medidoc/*` + `sudo` | bloquant | le préfixe couvre **aussi** les identifiants de production (`db-medidoc/creds/medidoc-prod…`) | un développeur coupe d'un coup toutes les connexions de MédiDoc en production | `sys/leases/revoke` (un bail précis, sans `sudo`) ; la révocation par préfixe reste un geste d'incident (RB-250) |
| 8 | `medidoc.tf`, rôle JWT, `token_ttl = 2592000` | à corriger | un jeton de CI vit **30 jours** après le job | le jeton affiché par erreur dans un journal (RB-198) reste valable un mois | 10 min (`token_ttl` et `token_max_ttl = 600`) ; un pipeline long demande un nouveau jeton par job |
| 9 | `medidoc.tf`, rôle JWT, deuxième audience `https://git01…` | à corriger | accepte des jetons émis **pour un autre destinataire** (confusion d'audience) | un jeton d'identité destiné à un autre service (même émetteur, autre `aud`) est rejoué contre le coffre | `bound_audiences = ["openbao.medisphere.internal"]` seulement |
| 10 | `medidoc.tf`, rôle Kubernetes, pas d'`audience` | à corriger | le rôle accepte les jetons de compte de service de **n'importe quelle** audience, y compris ceux faits pour l'API Kubernetes | un jeton volé ailleurs (ou monté par défaut dans un pod) sert au coffre | `audience = "openbao.medisphere.internal"` (jeton projeté dédié, M14) |
| 11 | `medidoc-dev.hcl`, `kv/data/medidoc/dev/+` | à corriger (fonctionnel) | `+` remplace **un** segment : `kv/data/medidoc/dev/api/db` n'y correspond pas (le commentaire dit « tout l'arbre ») | masqué aujourd'hui par le défaut 2 ; une fois 2 corrigé, l'équipe ne lit plus rien | `kv/data/medidoc/dev/*` |
| 12 | `medidoc-ci.hcl`, `sudo` sur `kv/data/medidoc/prod/*` | remarque | `sudo` ne sert que sur les chemins protégés (`sys/…`) ; ici il ne fait rien, mais dit qu'on ne sait pas ce qu'on donne | — | retirer ; même rôle et même politique pour la CI, ESO et la purge (défauts 5 et 6) : une politique par identité (`medidoc-ci`, `eso-medidoc-dev`, `medidoc-purge`) |

**Ce qui est correct** (à ne pas signaler) : le `deny` explicite sur `kv/data/medidoc/prod/*` dans `medidoc-dev.hcl` (redondant, et efficace contre toute règle de même chaîne ou moins précise d'une autre politique du jeton, comme `*` ou `kv/data/*` ; pas contre une règle plus précise, par exemple un chemin exact `kv/data/medidoc/prod/db` : une ceinture utile, pas une garantie absolue) ; `sys/capabilities-self` (diagnostic de ses propres droits) ; `token_type = "batch"` pour ESO (jetons légers, non renouvelables, adaptés à des connexions fréquentes).

Preuves (OpenBao de développement, une politique par jeton) :
```
admin@adm01:~/m25/e22$ bao policy write lucas-dev politiques/medidoc-dev.hcl && bao policy write lucas-ci politiques/medidoc-ci.hcl
admin@adm01:~/m25/e22$ TD=$(bao token create -policy=lucas-dev -field=token); TC=$(bao token create -policy=lucas-ci -field=token)
admin@adm01:~/m25/e22$ bao token capabilities $TD kv/data/mediagenda/prod/valkey
create, delete, read, update
admin@adm01:~/m25/e22$ bao token capabilities $TD kv/metadata/mediagenda/prod/valkey
delete, list, read
admin@adm01:~/m25/e22$ bao token capabilities $TD kv/data/medidoc/prod/db
deny
admin@adm01:~/m25/e22$ bao token capabilities $TD sys/leases/revoke-prefix/db-medidoc/creds/medidoc-prod
sudo, update
admin@adm01:~/m25/e22$ bao token capabilities $TC kv/data/plateforme/argocd/oidc
list, read
admin@adm01:~/m25/e22$ BAO_TOKEN=$TC bao kv get -mount=kv mediagenda/prod/valkey     # se lit réellement
```
(`bao token capabilities` ne tient pas compte de l'exigence `sudo` des chemins protégés : il affiche `read` sur `sys/audit` pour `lucas-ci`, mais la lecture réelle est refusée. Toujours confirmer par un essai.) Le jeton d'un serveur de développement se donne en argument ici parce que c'est un jeton jetable de la boucle locale ; jamais avec un jeton réel.

Fichiers corrigés : [`politiques/`](fichiers/M25-E22/secrets/politiques/) (`medidoc-dev.hcl`, `medidoc-ci.hcl`, `eso-medidoc-dev.hcl`, `medidoc-purge.hcl`) et [`tofu/medidoc.tf`](fichiers/M25-E22/secrets/tofu/medidoc.tf).

Pour Lucas, trois règles : (1) **un droit = un chemin exact pour une identité exacte** — jamais `*` à la racine, jamais un rôle partagé entre usages ; (2) **pour chaque rôle, qui peut obtenir ce jeton, et combien de temps vit-il** — référence protégée, audience, compte et espace, CIDR, durée ; (3) **`tofu validate` dit que c'est du HCL, pas que c'est sûr** — vérifie avec `bao token capabilities` et un essai de lecture sur un chemin d'une autre équipe.

**Explications**

Une politique OpenBao est une liste blanche de chemins ; la plus spécifique l'emporte entre politiques d'un même jeton, et `deny` l'emporte sur les autres capacités d'une règle de **même chaîne** (pas sur une règle plus précise). Les rôles des méthodes d'authentification font le lien entre une identité externe (un job, un pod, une machine) et des politiques : la plupart des fuites viennent de rôles trop larges (qui peut se connecter) plus que de politiques trop larges (ce qu'on peut faire une fois connecté). Les deux défauts ensemble (1 et 4, ou 1 et 6) sont ce qui transforme une erreur en incident.

**Alternatives**

- Un rôle JWT par **environnement** (`ref` exacte `main` pour la recette, étiquettes protégées pour la production) plutôt que `ref_protected` seul.
- `bound_service_account_namespace_selector` (sélecteur d'étiquettes d'espaces) au lieu d'une liste d'espaces, si l'on crée beaucoup d'espaces par équipe.
- Politiques modèles (*templated policies*, `{{identity.entity.aliases.<accessor>.metadata.…}}`) pour éviter une politique par espace.

**Pièges classiques**

- Croire `+` équivalent à `*`, ou `*` en milieu de chemin (il n'est permis qu'à la fin).
- Oublier `kv/metadata/…` et conclure que « la politique ne marche pas » parce que `bao kv list` échoue.
- Sortir le `role_id` en `output` OpenTofu « pour le récupérer facilement ».
- Contourner « at least one constraint should be enabled on the role » par `0.0.0.0/0`.
- Signaler le `deny` explicite comme un défaut.

**En production chez MédiSphère**

Toute MR de `plateforme/secrets` passe un job qui charge les politiques modifiées dans un OpenBao de développement éphémère et exécute une batterie de `bao token capabilities` attendues (« `medidoc-dev` ne lit pas `kv/data/mediagenda/*` ») ; règle de revue : aucun `path "*"`, aucun `["*"]` dans un rôle, aucun TTL de jeton machine au-delà d'une heure sans justification écrite.

---

### M25-E23 — Runbook : un secret a fuité

**Solution**

Runbook modèle : [`RB-250-fuite-de-secret.md`](fichiers/M25-E23/medisphere/docs/securite/secrets/runbooks/RB-250-fuite-de-secret.md) ; droits manquants : [`plateforme-admin.hcl.extrait`](fichiers/M25-E23/secrets/politiques/plateforme-admin.hcl.extrait) (révocation par préfixe et liste des baux, `sudo`).

**Grille d'auto-évaluation** (un point par ligne ; 12 attendus sur 14) :

| Élément | Attendu |
|---|---|
| Déclencheurs | message, journal de CI, Git, poste perdu, alerte d'audit, doute ; « a pu être lu = fuité » |
| Rôles | responsable, RSSI, propriétaire, scribe ; pas de canal public |
| Dix premières minutes | retirer de la vue **après** copie de preuve ; identifier le chemin ; contenir ; sceller en dernier recours avec avertissement et décideur |
| Gravité | trois niveaux avec délais ; données de santé → RSSI, CNIL 72 h décidée par elle |
| Jeton OpenBao | révocation **par accessor** (enfants et baux compris) |
| `secret_id` | destruction par accessor de `secret_id`, nouveau par enveloppement |
| KV statique | cible d'abord, coffre ensuite, ESO propage, vérifier le **refus** de l'ancienne valeur |
| Dynamique | `lease revoke` / `-prefix` (avec qui détient `sudo`), `rotate-root` si c'est le compte de connexion |
| PKI, transit, signature | révocation + CRL ; rotate + rewrap + gel + trim ; procédure de changement de clé de signature |
| Retour à la normale | ESO synchronisés, applications saines, pipelines témoins, coffre |
| Enquête | fenêtre, qui a lu (audit), qui a **utilisé** (système cible), HMAC, accessor, cause racine |
| Preuves | hors de Git et du ticket, secret caviardé, empreintes, chronologie UTC |
| Communication | qui, à qui, quand ; jamais la valeur |
| Clôture | liste vérifiable, post-mortem sans reproche, gestes exceptionnels reliés à l'incident |

**Rejeu de l'incident de Nadia** (chronologie type, UTC) :

| T | Geste |
|---|---|
| T0 | Signalement dans le canal ; ouverture INC-5223, responsable = astreinte, fil privé |
| T0+3 | Copie de la sortie du job (secrets caviardés) dans le dossier de preuves, puis effacement du journal du job (*Erase job log*) et masquage du message |
| T0+5 | Identification : jeton OpenBao d'un job de CI de `medidoc/medidoc` (rôle `ci-medidoc`) ; mot de passe de `kv/medidoc/prod/compte-service` (inventaire : propriétaire MédiDoc) → G2 |
| T0+7 | Requête par accessor : le jeton est-il encore valable ? (TTL 10 min depuis E10 : souvent déjà expiré — sinon `bao token revoke -accessor …`) |
| T0+10 | Appel du propriétaire MédiDoc ; nouveau mot de passe dans le système cible ; nouvelle version dans `kv/medidoc/prod/compte-service` ; rafraîchissement forcé de l'`ExternalSecret` (annotation `force-sync`, E15) ; redémarrage contrôlé |
| T0+25 | Vérification : l'ancien mot de passe est refusé ; pods sains ; `ExternalSecret` synchronisé |
| T0+30 | Enquête : qui a lu le chemin depuis le début de la fenêtre ; utilisation de l'ancien mot de passe dans les journaux du système cible ; accessor du jeton (ce qu'il a fait pendant sa vie) |
| T0+45 | Cause racine provisoire : `set -x` dans un script du job (la règle Semgrep du M19 ne couvrait pas ce dépôt) |
| T0+50 | Communication à Sophie (faits) ; post-mortem planifié ; actions : règle Semgrep étendue, `verifier-chiffres` / Gitleaks sur ce dépôt |

Manques typiquement trouvés au rejeu, et corrigés dans le modèle : qui détient le `sudo` de la révocation par préfixe (aucun rôle humain ne l'avait : extrait de politique) ; où ranger les preuves (compartiment dédié, pas le ticket) ; « retirer de la vue » détruisait la preuve (copie d'abord) ; la vérification que l'ancienne valeur est **refusée** n'était pas écrite.

**Explications**

Un runbook de fuite doit être suivi par une personne seule, la nuit : l'ordre des gestes compte plus que leur exhaustivité. Contenir avant d'enquêter (on ne prouve pas l'absence d'exploitation), tourner en commençant par le **système cible** (sinon le coffre délivre une valeur que la cible refuse : coupure), vérifier le refus de l'ancienne valeur (sinon la rotation n'a servi à rien). L'audit d'E21 transforme l'enquête : qui a lu, quand, depuis où, avec quel jeton — sans jamais recopier le secret (HMAC).

**Alternatives**

- Un runbook par type de secret : plus précis, mais l'astreinte doit d'abord savoir lequel ouvrir ; le tableau unique avec renvois est plus rapide la nuit.
- Automatiser les gestes (pipeline « rotation d'urgence » par type) : c'est l'objet de M25-E33 et le chronométré d'E34.

**Pièges classiques**

- Supprimer le message avant d'en garder la preuve.
- Mettre la nouvelle valeur dans le coffre avant de la mettre dans la cible.
- Révoquer un jeton par sa valeur en la collant dans une commande (`bao token revoke <jeton>`) : on répand le secret dans l'historique du shell ; par accessor.
- Révoquer par préfixe sans savoir ce que couvre le préfixe (production comprise).
- Oublier les copies : l'historique Git, les sauvegardes, les journaux du runner, les caches.
- Chercher un coupable dans le post-mortem.

**En production chez MédiSphère**

RB-250 exercé deux fois par an (exercice de table et E34), relié aux alertes d'audit (`runbook_url`), et révisé après chaque usage réel ; l'inventaire des secrets indique pour chaque secret son geste de rotation et son propriétaire joignable ; les pipelines de rotation d'E33 réduisent la rotation d'un secret de plateforme à un déclenchement.

---

## Ce qui reste promis (palier 2)

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
