# Journal de diagnostic — INC-5236 « la CI ne lit plus ses secrets » (Julien Petit)

> Modèle de journal (M25-E36, variante 2 jouée). Une ligne par geste : heure, hypothèse, commande
> (sans secret), résultat, conclusion. Aucun jeton d'identité, aucun jeton OpenBao, aucun accesseur
> complet (6 premiers caractères au plus).

| Heure | Hypothèse | Commande | Résultat | Conclusion |
|---|---|---|---|---|
| 10:02 | — | journal du job `securite:verification` (pipeline de `main`) | `OpenBao refuse le rôle ci-mediagenda-api…` ; au-dessus : `error validating claims: claim "ref_protected" does not match any associated bound claim values` | refus **à la connexion**, sur une revendication liée |
| 10:04 | le coffre est fermé ou injoignable | `curl -s https://openbao.par1.medisphere.internal:8200/v1/sys/health \| jq .sealed` | `false` | le coffre répond |
| 10:05 | toutes les CI touchées ? | dernier pipeline de `main` de `medidoc/medidoc` et de `plateforme/secrets` | verts ce matin | seul le rôle de MédiAgenda : pas la méthode |
| 10:07 | la référence n'est plus protégée | Paramètres > Dépôt > Branches protégées de `mediagenda/api` | `main` protégée, inchangée | côté GitLab rien n'a bougé |
| 10:09 | — | `bao read auth/gitlab/role/ci-mediagenda-api` | `bound_claims map[… ref_protected:true …]` | rien de visible en tableau |
| 10:10 | type de la valeur | `bao read -format=json … \| jq '.data \| {bound_claims_type, rp: .bound_claims.ref_protected}'` | `"string"`, `true` (sans guillemets) | booléen contre la chaîne `"true"` du jeton ; type `string` : `v*` littéral |
| 10:12 | dérive | audit Loki : écritures sur `auth/gitlab/role/ci-mediagenda-api` | hier 18:41, jeton `oidc-…` | modification à la main, hors pipeline |
| 10:13 | — | `tofu plan` (plateforme/secrets) | `vault_jwt_auth_backend_role.ci["ci-mediagenda-api"]` à mettre à jour | le dépôt a raison |
| 10:20 | — | pipeline de `main` de `plateforme/secrets` (apply manuel) | apply OK, `roles-ci:verifier` ajouté : 0 écart | — |
| 10:24 | — | relance du pipeline de `main` de `mediagenda/api` | `OpenBao : connecté au rôle ci-mediagenda-api (ci-mediagenda-api,default)`, vérification OK | réparé |

**Cause** : rôle `ci-mediagenda-api` réécrit à la main d'après l'exemple de la documentation :
`bound_claims_type` passé à `string` et `ref_protected` lié au booléen `true`, alors que GitLab émet la
chaîne `"true"` ; la comparaison est typée. **Correctif** : `tofu apply` de `main`.
**Prévention** : `outils/verifier-roles-ci.sh` après chaque apply et chaque nuit ; écritures sur
`auth/*/role/*` et `auth/*/config` hors du jeton du pipeline signalées par l'audit.
