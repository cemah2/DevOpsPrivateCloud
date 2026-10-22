# OIDC à la main : ce que font nos services à notre place

> Compte rendu de M24-E07 (ticket PLAT-2507). Royaume `medisphere`, client d'essai `essai-oidc`
> (confidentiel, PKCE S256 exigé, redirection exacte `http://localhost:8765/rappel`), utilisateur
> `lucas.martin` (fédéré depuis l'annuaire). Aucun jeton complet n'est recopié ici : seulement
> les en-têtes et revendications décodés, et des extraits tronqués.

## 1. Découverte

`GET https://sso.par1.medisphere.internal/realms/medisphere/.well-known/openid-configuration`

| Clé | Valeur relevée | Rôle |
|---|---|---|
| `issuer` | `https://sso.par1.medisphere.internal/realms/medisphere` | identité de l'émetteur : comparée à `iss` de chaque jeton |
| `authorization_endpoint` | `…/protocol/openid-connect/auth` | le navigateur y est envoyé |
| `token_endpoint` | `…/protocol/openid-connect/token` | échange du code, rafraîchissement (de serveur à serveur) |
| `userinfo_endpoint` | `…/protocol/openid-connect/userinfo` | profil, avec le jeton d'accès |
| `introspection_endpoint` | `…/protocol/openid-connect/token/introspect` | « ce jeton est-il encore valable ? » (client authentifié) |
| `end_session_endpoint` | `…/protocol/openid-connect/logout` | déconnexion |
| `jwks_uri` | `…/protocol/openid-connect/certs` | clés publiques de signature |
| `code_challenge_methods_supported` | `plain`, `S256` | on n'accepte que S256 (réglage du client) |
| `grant_types_supported` | `authorization_code`, `refresh_token`, `client_credentials`, `password`, `implicit`… | annoncés par le royaume ; chaque client n'en active que ce qu'il faut |

JWKS : une clé `RSA` `use=sig` `alg=RS256` (`kid` = `<KID>`), et une clé `use=enc` (`RSA-OAEP`, chiffrement, non utilisée ici). Aucun `d`, `p`, `q` : seules les parties publiques (`n`, `e`) sont publiées.

## 2. Code d'autorisation avec PKCE

- `code_verifier` : 64 caractères aléatoires base64url (43 à 128 permis par la RFC 7636), gardé côté client.
- `code_challenge` = base64url(SHA-256(`code_verifier`)), sans `=` ; `code_challenge_method=S256`.
- `state` (anti-CSRF, vérifié au retour) et `nonce` (anti-rejeu, retrouvé dans l'ID token) : 128 bits aléatoires chacun.
- Retour : `http://localhost:8765/rappel?state=…&session_state=…&iss=…&code=<36 caractères>` ; `state` identique à celui envoyé ; `iss` présent (RFC 9207, contre la confusion d'émetteur).
- Le code ne vit qu'**une minute** et ne sert **qu'une fois** : un échange raté (mauvais verifier) le consomme aussi (`Code not valid` au second essai).

## 3. Les jetons

| | ID token | Access token | Refresh token |
|---|---|---|---|
| `typ` | `ID` | `Bearer` | `Refresh` |
| Signature | RS256, `kid` du JWKS | RS256 | HS512 (clé secrète du royaume : seul Keycloak le lit) |
| `iss` | l'émetteur | l'émetteur | l'émetteur |
| `aud` | `essai-oidc` | `account` (puis `essai-oidc`, `account` avec le mappeur d'audience) | l'émetteur |
| `azp` | `essai-oidc` | `essai-oidc` | — |
| `exp - iat` | 300 s | 300 s | 1 800 s (session inactive) |
| Autres | `nonce` = celui envoyé, `at_hash`, `sid`, `preferred_username`, `email`, `groups` (`plateforme`) | `scope`, `realm_access`, `resource_access`, `groups` | — |

Ce qui distingue les deux premiers : l'**ID token** dit au client *qui* s'est connecté (il lui est destiné : `aud` = le client) ; l'**access token** est présenté à une API (`aud` = l'API), le client n'a pas à le lire.

## 4. Userinfo, introspection, rafraîchissement, déconnexion

- `userinfo` avec le jeton d'accès : `sub`, `preferred_username`, `email`, `groups`.
- Introspection **avant** le mappeur d'audience : `{"active": false}`, et dans le journal de Keycloak `INTROSPECT_TOKEN_ERROR … reason="Client 'essai-oidc' is not in the token audience"`. Keycloak 26 n'introspecte pour un client que les jetons qui lui sont destinés. Après ajout d'un mappeur *Audience* (`included.client.audience = essai-oidc`, dans le jeton d'accès) : `{"active": true, "client_id": "essai-oidc", "username": "lucas.martin", …}`.
- Rafraîchissement (`grant_type=refresh_token`) : nouveaux jetons d'accès et d'identité, même `sid`.
- Déconnexion (`POST …/logout` avec le refresh token, client authentifié) : HTTP 204 ; ensuite l'introspection du **même** jeton d'accès répond `active: false` et `userinfo` répond 401 : la session est fermée côté Keycloak. Un service qui vérifie la signature **hors ligne** (JWKS) continuerait, lui, d'accepter ce jeton jusqu'à son `exp` (5 minutes) : c'est la raison des jetons courts.

## 5. Sans PKCE, ou avec un mauvais verifier

- Requête d'autorisation sans `code_challenge` : redirection immédiate vers `…/rappel?error=invalid_request&error_description=Missing+parameter%3A+code_challenge_method` (le client exige S256).
- Échange avec un mauvais `code_verifier` : `{"error":"invalid_grant","error_description":"PKCE verification failed: Code mismatch"}`.
- Ce que PKCE empêche : un code intercepté (journal d'un mandataire, historique, application malveillante qui écoute la même redirection) est inutilisable sans le verifier, resté chez le client légitime. Pour un client confidentiel, le secret protège déjà l'échange ; PKCE ajoute la liaison entre la requête et l'échange (OAuth 2.1 et la RFC 9700 le recommandent pour tous les clients).
- Redirection non enregistrée (`…/autre`) : Keycloak refuse (page d'erreur « Invalid parameter: redirect_uri »), **sans** rediriger : on ne renvoie jamais un code vers une adresse inconnue.
