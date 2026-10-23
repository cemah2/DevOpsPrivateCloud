### M25-E36 — Panne : la CI ne lit plus ses secrets

**Points non vérifiés en conditions réelles** — signale tes retours, ils corrigent le workbook :
- `break-E36.sh` n'a pas été joué contre un OpenBao. Il suppose que l'écriture d'un rôle `jwt` **met à jour les seuls champs fournis** (comportement du greffon JWT hérité de Vault) et que la configuration de la méthode est **réécrite en entier** (d'où l'envoi de la configuration complète sauvegardée).
- Les messages cités ci-dessous suivent le code du greffon JWT ; leur libellé exact peut varier d'une version à l'autre. Le message de la variante 3 (clés introuvables) est le moins sûr : retiens « échec de récupération ou de vérification des clés », pas le texte mot pour mot.
- Variante 2 : le greffon refuse une valeur non textuelle dans `bound_claims` quand le type est `glob`. La panne passe donc d'abord le rôle en type `string`, comme le ferait quelqu'un qui recopie l'exemple de la documentation et se heurte à ce refus.

**Démarche de diagnostic**

*Symptômes* : `securite:signature` échoue sur `main` de `mediagenda/api`, à l'étape OpenBao. Le dépôt et le composant n'ont pas changé.

*Hypothèses*, dans l'ordre de la chaîne : (a) coffre scellé ou injoignable ; (b) la méthode ne peut plus vérifier la **signature** (source des clés, autorité TLS, `git01`) ; (c) l'**émetteur** ou l'**audience** ne correspondent plus ; (d) une **revendication liée** ne correspond plus (projet, protection, référence, ou type de la valeur) ; (e) la connexion réussit mais le jeton n'a plus la bonne **politique** ; (f) côté GitLab, `main` n'est plus protégée ou l'`id_tokens` a changé.

**Étape 1 — Le journal du job.** Le message vient de la CLI `bao` lancée par `.openbao-connexion` :

```
Error writing data to auth/gitlab/login: Error making API request.
URL: PUT https://openbao.par1.medisphere.internal:8200/v1/auth/gitlab/login
Code: 400. Errors:
* error validating claims: claim "ref_protected" does not match any associated bound claim values
OpenBao refuse le rôle ci-mediagenda-api pour mediagenda/api@main (référence protégée ? projet lié au rôle ?)
```

Trois familles de messages possibles. Une erreur sur la **signature** ou les **clés** désigne la méthode (variante 3). Un code **400** `error validating claims` / `audience` désigne le rôle (variantes 1 et 2). Une ligne `OpenBao : connecté au rôle ci-mediagenda-api (default)` suivie d'un `Code: 403 … permission denied` sur `kv/data/plateforme/harbor/robot-ci` désigne les politiques (variante 4) : la connexion a **réussi**.

**Étape 2 — Délimiter.**

```
admin@adm01:~$ curl -s https://openbao.par1.medisphere.internal:8200/v1/sys/health | jq '{sealed, standby}'
```

Regarde ensuite le dernier pipeline de `medidoc/medidoc` et relance `tofu:plan` sur `main` de `plateforme/secrets`. S'ils se connectent, la méthode fonctionne et la panne est dans **le rôle** de MédiAgenda. Si **tous** échouent avec un message de clés, c'est **la méthode**, et le pipeline de `plateforme/secrets` est hors jeu lui aussi. Dans `mediagenda/api`, Paramètres > Dépôt > Branches protégées : `main` toujours protégée (hypothèse f écartée).

**Étape 3 — Configuration, au format JSON.**

```
admin@adm01:~$ bao read -format=json auth/gitlab/config | jq '.data | {oidc_discovery_url, jwks_url, bound_issuer, ca: (.oidc_discovery_ca_pem // .jwks_ca_pem | length > 0)}'
admin@adm01:~$ bao read -format=json auth/gitlab/role/ci-mediagenda-api \
    | jq '.data | {bound_audiences, bound_claims_type, bound_claims, token_policies, user_claim}'
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan        # en lecture : la ressource qui dérive
```

**Étape 4 — L'audit** (Grafana, Loki, locataire `audit`) : d'abord les refus, puis l'écriture fautive.

```logql
{service="openbao"} | json chemin="request.path", op="request.operation", erreur="error"
  | chemin=~"auth/gitlab/(login|config|role/.*)" | line_format "{{.op}} {{.chemin}} {{.erreur}}"
```

Les `update auth/gitlab/login` portent l'erreur vue dans le job. Plus tôt, une écriture `update auth/gitlab/role/ci-mediagenda-api` ou `update auth/gitlab/config` donne l'heure et l'auteur (`auth.display_name` : ici ton jeton OIDC). `OpenBaoPolitiqueModifiee` (M25-E21) n'a **pas** sonné : elle ne regarde que `sys/policies/acl/*`. Un rôle ou une méthode modifiés passent sous son radar.

**Variante 1 — audience changée.**

```json
"bound_audiences": ["openbao.par1.medisphere.internal"]
```

Le job demande toujours un jeton d'identité d'audience `openbao.medisphere.internal` (`id_tokens:` du composant). OpenBao exige qu'**une** des audiences du jeton figure dans `bound_audiences` : aucune ne correspond, d'où un 400 qui cite l'audience (`aud claim does not match any bound audience` ou `invalid audience`, selon la version). L'« harmonisation » sur le nom DNS du service confond deux choses. L'audience n'est pas une adresse : c'est le nom **convenu** du destinataire, fixé au M19-E25 et inscrit dans chaque `id_tokens`. La changer d'un côté sans l'autre casse tous les jobs du rôle. Plan : `vault_jwt_auth_backend_role.ci["ci-mediagenda-api"]`. Correctif : apply de `main` par le pipeline de `plateforme/secrets`, qui n'est pas touché.

**Variante 2 — booléen contre chaîne.**

```
admin@adm01:~$ bao read auth/gitlab/role/ci-mediagenda-api | grep bound_claims
bound_claims         map[project_id:[4] ref:[main v*] ref_protected:true ref_type:[branch tag]]
bound_claims_type    string
admin@adm01:~$ bao read -format=json auth/gitlab/role/ci-mediagenda-api | jq -c '.data.bound_claims.ref_protected'
true
```

En tableau, rien ne distingue `true` de `"true"`. En JSON, la valeur liée est le **booléen** `true`. Or GitLab émet `"ref_protected": "true"`, une chaîne (relevé au M19-E25, rappelé par l'indice 1 d'E10). La comparaison est **typée** : un booléen n'égale jamais une chaîne, d'où `claim "ref_protected" does not match any associated bound claim values`. Le type est aussi passé à `string`, sans quoi OpenBao aurait refusé d'enregistrer un booléen. Ce second écart casse **en plus** les étiquettes, car `v*` devient un littéral. Le pipeline de `main` ne le montre pas, la prochaine release le montrerait. Correctif : apply de `main`. Le plan remet les deux champs.

**Variante 3 — clés introuvables.**

```
admin@adm01:~$ bao read -format=json auth/gitlab/config | jq -c '.data | {oidc_discovery_url, jwks_url}'
{"oidc_discovery_url":"","jwks_url":"https://git01.par1.medisphere.internal/oauth/discovery/jwks.json"}
admin@vault01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://git01.par1.medisphere.internal/oauth/discovery/jwks.json
404
admin@vault01:~$ curl -s https://git01.par1.medisphere.internal/.well-known/openid-configuration | jq -r .jwks_uri
https://git01.par1.medisphere.internal/oauth/discovery/keys
```

La méthode ne suit plus la découverte : elle va chercher les clés à une URL fixe, qui n'existe pas. Chaque connexion échoue **avant** toute comparaison de revendication, pour **tous** les rôles, y compris `ci-plateforme-secrets`. L'écriture n'a pu passer que parce que la validation a été sautée (`skip_jwks_validation=true`). Sans cette option, OpenBao aurait refusé d'enregistrer une URL de clés qui ne répond pas. Une option qui fait taire un refus est un signal d'alerte à la relecture.

Le pipeline de `plateforme/secrets` ne peut pas réparer la méthode qui l'authentifie. On passe donc au **bris de glace d'E10** : `tofu apply` depuis `adm01` avec ta session `plateforme-admin` et les copies locales des accès à l'état (`~/.config/workbook/`, palier 1) :

```
admin@adm01:~$ bao token lookup -format=json | jq -r '.data.ttl'       # au moins 20 min
admin@adm01:~/src/secrets$ git switch main && git pull
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan -out=plan.tfplan     # seule vault_jwt_auth_backend.gitlab change
admin@adm01:~/src/secrets$ tofu -chdir=tofu apply plan.tfplan
```

Relance ensuite un `tofu:plan` dans le pipeline : il doit se connecter et ne rien proposer. Note le bris de glace dans le journal : un apply hors pipeline se justifie par écrit.

**Variante 4 — la politique retirée du rôle.**

```
OpenBao : connecté au rôle ci-mediagenda-api (default)
Error reading kv/data/plateforme/harbor/robot-ci: Error making API request.
Code: 403. Errors:
* permission denied
```

La connexion a réussi : signature, audience et revendications sont bonnes. Le jeton émis ne porte que `default`, car `token_policies` vaut `["default"]` au lieu de `["ci-mediagenda-api"]`. Chercher du côté du contenu de la politique `ci-mediagenda-api` serait une fausse piste : elle est intacte, elle n'est simplement plus **attribuée**. À la différence d'une politique de groupe (M25-E40), les politiques d'un rôle sont copiées dans le jeton **à son émission**. Une réparation ne profite qu'aux jetons suivants, ce qui ne pose aucun problème ici : chaque job se reconnecte. Correctif : apply de `main` par le pipeline.

**Clôture commune** : relance du pipeline de `main` de `mediagenda/api` jusqu'au vert, `lab/bin/check 25 36`, puis `lab/bin/break 25 36 --annuler` et journal ([modèle](fichiers/M25-E36/medisphere/docs/securite/secrets/journal/AAAA-MM-JJ-INC-5236.md)).

**Prévention**
- **Contrôle de dérive** : [`outils/verifier-roles-ci.sh`](fichiers/M25-E36/secrets/outils/verifier-roles-ci.sh) lit la méthode et **chaque** rôle `ci-*` sur le coffre réel, avec l'identité du pipeline. Il vérifie la découverte (et que `git01` sert ses clés), l'audience exacte, le type `glob`, des valeurs liées **toutes textuelles**, `ref_protected = "true"`, au moins une politique utile et existante. Il explique chaque écart en clair. Job [`roles-ci:verifier`](fichiers/M25-E36/secrets/.gitlab-ci.yml.extrait) après chaque apply et chaque nuit (pipeline planifié). Si c'est la méthode elle-même qui casse, ce job échoue à la connexion : c'est déjà l'alerte.
- **Audit** : une règle du ruler de Loki, sur le modèle d'`OpenBaoPolitiqueModifiee`, pour toute écriture sur `auth/+/config` ou `auth/+/role/*` faite par un autre jeton que celui du pipeline (`auth.metadata.project_path != "plateforme/secrets"`).
- Dans la relecture des MR de `plateforme/secrets`, tout `skip_jwks_validation`, tout changement d'audience et tout `bound_claims_type` autre que `glob` demandent deux relecteurs, comme les méthodes d'authentification (garde-fou du `tofu:plan`).

**Explications**

À chaque connexion, la méthode `jwt` déroule toujours la même chaîne. Elle vérifie d'abord la **signature** avec les clés publiées par l'émetteur (découverte OIDC, `jwks_url` ou clés recopiées : une seule source). Viennent ensuite les champs standard (`iss` contre `bound_issuer`, `aud` contre `bound_audiences`, `exp`, `nbf`), puis chaque `bound_claims`, comparé **avec son type** (`string` : égalité exacte ; `glob` : motif, valeurs textuelles seulement). Le jeton émis reçoit enfin les `token_policies` **du rôle**, figées à l'émission.

Chaque maillon a son message, et sa portée : les clés touchent la **méthode**, donc tous les rôles ; l'audience et les revendications touchent **un rôle** ; les politiques laissent passer la connexion et refusent la lecture. Lire le message du job, puis vérifier si les autres projets passent, suffit à situer la panne avant d'ouvrir la configuration.

**Alternatives**
- Diagnostiquer en rejouant la connexion à la main avec un jeton d'identité copié depuis un job : possible en théorie (le jeton vit 5 min), à proscrire en pratique (un jeton d'identité est une preuve d'identité, et il finit dans un historique ou un ticket). Le journal du job, la configuration en JSON et l'audit suffisent.
- `jwks_url` au lieu de la découverte : équivalent pour la signature quand l'URL est la bonne (`/oauth/discovery/keys`), mais un réglage de plus à maintenir. La découverte suit d'elle-même l'URL annoncée par GitLab.
- `bound_claims_type = "string"` avec la liste exacte des références : possible, mais il faut énumérer les étiquettes. `glob` est le choix d'E10. Dans les deux cas, les valeurs sont des **chaînes**.

**Pièges classiques**
- Lire le rôle en tableau et conclure « `ref_protected` vaut `true`, c'est bon ».
- Retirer `ref_protected` du rôle « pour débloquer la recette » : n'importe quelle branche non protégée lirait le robot Harbor.
- Ajouter la bonne audience **à côté** de la mauvaise : ça remarche, mais la dérive reste et le plan ne sera jamais vide.
- Activer `CI_DEBUG_TRACE` pour voir le jeton : il est alors dans le journal du job, pour tout le projet.
- Variante 3 : attendre le pipeline de `plateforme/secrets` pour réparer, alors qu'il ne peut pas se connecter non plus.
- Variante 4 : modifier la **politique** `ci-mediagenda-api` alors que c'est son **attribution** qui manque.

**En production chez MédiSphère**

La configuration des méthodes d'authentification est traitée comme du code critique : modifications par MR seulement, relecture à deux, contrôle de dérive nocturne qui ouvre un incident, alerte d'audit sur toute écriture hors pipeline. Le bris de glace (apply depuis un poste d'administration) est prévu, testé une fois par trimestre, et chaque usage est justifié dans le journal. Un canari par projet critique (un job planifié qui se connecte et lit un secret témoin sans valeur) montre la panne avant le premier développeur du matin.

---
