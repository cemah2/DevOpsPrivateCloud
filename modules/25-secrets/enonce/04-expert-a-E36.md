### M25-E36 — Panne : la CI ne lit plus ses secrets  `BF` `★★★`

> **Ticket INC-5236** — *De : Julien Petit*
> Le pipeline de `main` de `mediagenda/api` est rouge depuis ce matin : `securite:signature` s'arrête à l'étape OpenBao, avant même de signer. On n'a rien poussé depuis hier midi, le composant `securite` est toujours en v2.9.0, et relancer le job ne change rien. On a une mise en recette prévue à 14 h. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Lire un échec de connexion par jeton d'identité : distinguer un refus **à la connexion** (méthode, rôle, revendications) d'un refus **à la lecture** (politique), à partir du seul journal du job.
- Suivre la chaîne de validation de la méthode `jwt` : clés de signature (découverte OIDC ou `jwks_url`), émetteur, audience, revendications liées et leur **type**, puis politiques du jeton émis.
- Délimiter la panne (un rôle, une méthode, tous les projets ?) avant de toucher à quoi que ce soit, et retrouver l'écriture fautive dans l'audit.
- Corriger par le code, y compris quand le pipeline qui applique la configuration est lui-même touché, et mettre en place un contrôle de dérive.

**Prérequis** : M25-E10 (méthode `gitlab/`, composant `securite` v2.9.0), M25-E21 (audit dans Loki) ; `lab/bin/check 25 10` vert et dernier pipeline de `main` de `mediagenda/api` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique**
- Chaîne en place depuis M25-E10 : le job déclare un jeton d'identité (`id_tokens`, audience `openbao.medisphere.internal`) ; le job caché `.openbao-connexion` du composant `securite` le présente à `auth/gitlab/login` avec le rôle `ci-mediagenda-api` et affiche, s'il réussit, `OpenBao : connecté au rôle … (<politiques>)` ; le job lit ensuite le robot Harbor (`kv/plateforme/harbor/robot-ci`).
- La méthode `gitlab/` est de type `jwt`, configurée par la **découverte OIDC** de `git01` (racine MédiSphère comme autorité), émetteur lié. Les rôles `ci-<groupe>-<projet>` lient l'audience, `project_id`, `ref_protected`, `ref` et `ref_type` avec `bound_claims_type = "glob"`. Référence : `tofu/auth-gitlab.tf` de `plateforme/secrets` et `docs/securite/secrets/ci-et-openbao.md`.
- Ton jeton `plateforme-admin` lit la configuration de la méthode (`auth/gitlab/config`) et de ses rôles (`auth/gitlab/role/<rôle>`). Le journal d'audit est dans Loki (locataire `audit`, `{service="openbao"}`) : les connexions refusées y figurent comme les autres requêtes.
- La panne modifie la configuration **directement dans OpenBao**, avec **ton** jeton d'administration : `plateforme/secrets` n'a pas changé, le coffre si.

> ⚠️ **Attention** : n'active **jamais** `CI_DEBUG_TRACE` ni `set -x` pour « voir ce qui se passe » : le journal du job contiendrait le jeton d'identité, le jeton OpenBao et le jeton du robot Harbor, lisibles par tous les développeurs du projet. Ne recopie pas non plus le jeton d'identité d'un job dans un décodeur en ligne. Tout ce qu'il te faut est dans le journal normal du job, dans la configuration du coffre et dans l'audit.

**Injection** : `lab/bin/break 25 36` (4 variantes).

**Travail demandé**
1. **Lis l'échec.** Dans le journal du job `securite:signature`, relève le message exact renvoyé par OpenBao (code HTTP compris). La connexion a-t-elle réussi ? Si oui, avec quelles politiques ? Formule une hypothèse par **étape** de la chaîne (clés, émetteur, audience, revendications, politiques) et dis laquelle le message désigne.
2. **Délimite.** Les autres projets migrés en M25-E10 (`medidoc/medidoc`, le pipeline de `plateforme/secrets`) se connectent-ils encore ? Relance au besoin un job qui lit le coffre. Conclus : panne de la **méthode** ou d'un **rôle** ? Vérifie aussi que le coffre est descellé et que `main` est toujours protégée dans `mediagenda/api`.
3. **Compare la configuration à la référence.** Lis la méthode et le rôle **au format JSON** (pas en tableau), confronte chaque champ à `tofu/auth-gitlab.tf` et lance `tofu plan` en lecture. Pour l'écart trouvé, explique **pourquoi** il produit exactement ce message (ou ce refus de lecture).
4. **Trouve l'écriture.** Dans l'audit, retrouve la requête qui a modifié la méthode ou le rôle : heure, chemin, auteur (ici ton propre jeton : l'injection l'utilise). L'alerte `OpenBaoPolitiqueModifiee` d'E21 a-t-elle sonné ? Pourquoi ?
5. **Corrige par le code** : ramène le coffre à l'état de `plateforme/secrets` par le pipeline, ou par le bris de glace d'E10 si le pipeline ne peut pas s'en charger (dis pourquoi). Relance le pipeline de `main` de `mediagenda/api` jusqu'au vert.
6. **Préviens** : un script `outils/verifier-roles-ci.sh` dans `plateforme/secrets` qui contrôle, sur le coffre réel et en lecture seule, la méthode `gitlab/` et chaque rôle `ci-*` (audience, type des revendications liées, `ref_protected`, politiques existantes et utiles), lancé par un job après chaque apply et chaque nuit. Tiens ton journal de diagnostic.

**Critères de réussite**
- [ ] La méthode `gitlab/` est configurée par la découverte OIDC de `git01`, sans `jwks_url` ni clé recopiée, émetteur lié.
- [ ] Le rôle `ci-mediagenda-api` lie l'audience `openbao.medisphere.internal`, `ref_protected` à la **chaîne** `"true"` avec le type `glob`, accepte `main` et `v*`, et porte la politique `ci-mediagenda-api` ; les autres rôles `ci-*` de M25-E10 lient la même audience et la même chaîne.
- [ ] Le dernier pipeline de `main` de `mediagenda/api` est vert, signature comprise.
- [ ] Le contrôle de dérive des rôles tourne dans la CI de `plateforme/secrets` ; ton journal de diagnostic (un fichier dont le nom contient `INC-5236`, dans le dossier des journaux du palier) cite le message exact du job et la cause.

**Vérification** : `lab/bin/check 25 36`

<details><summary>Indice 1</summary>

Un job qui affiche `OpenBao : connecté au rôle …` puis `permission denied` (403) **a** obtenu un jeton : le problème est dans ce que ce jeton peut faire, pas dans la connexion. Un code 400 avec `error validating claims` ou une erreur de vérification de signature arrive **avant** l'émission du jeton : regarde la méthode et le rôle, pas les politiques.
</details>

<details><summary>Indice 2</summary>

`bao read auth/gitlab/role/ci-mediagenda-api` affiche les valeurs **sans leur type** : `true` et `"true"` s'y ressemblent. `bao read -format=json … | jq '.data | {bound_audiences, bound_claims_type, bound_claims}'` les distingue. Compare ensuite avec ce que GitLab met dans le jeton (relevé dans `docs/livraison/ci/secrets-ci.md` §4, M19-E25).
</details>

<details><summary>Indice 3</summary>

Si **tous** les rôles de `gitlab/` sont refusés, le pipeline de `plateforme/secrets` l'est aussi : il ne peut pas réparer la méthode qui l'authentifie. C'est le cas prévu par l'avertissement et le bris de glace de M25-E10 (`tofu apply` depuis `adm01` avec ta session `plateforme-admin`). Pense aussi à `bao read auth/gitlab/config` : quelle source de clés la méthode utilise-t-elle, et cette URL répond-elle depuis `vault01` ?
</details>

**Pour aller plus loin** (facultatif) : sur un `bao server -dev` jetable de ton poste, monte une méthode `jwt` avec une clé que tu génères, signe toi-même des jetons (`ref_protected` en chaîne puis en booléen, audience juste puis fausse) et note le message de chaque refus, avec `bound_claims_type` à `string` puis à `glob`. Documentation : [méthode JWT/OIDC d'OpenBao](https://openbao.org/docs/auth/jwt/), [API de la méthode](https://openbao.org/api-docs/auth/jwt/) (`skip_jwks_validation`, `bound_claims_type`), [jetons d'identité de GitLab](https://docs.gitlab.com/ci/secrets/id_token_authentication/).

---
