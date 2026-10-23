# OIDC sous le capot : signatures, JWKS, sessions et rotation des clés

*M24-E44 (PLAT-2544). Auteur : <MOI>. Relu par : Karim Benali, Sophie Laurent. Exemple de corrigé : valeurs représentatives, extraits tronqués, aucun jeton complet.*

Pour les prochains arrivants : ce qu'on vérifie quand on dit « le jeton est signé », qui garde les clés, ce que Keycloak met dans le navigateur, et ce qu'il envoie à un service quand quelqu'un se déconnecte. Outil : `plateforme/identite/outils/verifier-jeton.sh` (vérifie un jeton sans bibliothèque, lu sur l'entrée standard).

## Signature

Un JWT est `base64url(en-tête).base64url(charge).base64url(signature)`. Rien n'est chiffré : tout se lit ; seule la signature fait foi.

- En-tête d'un jeton d'accès du royaume : `{"alg": "RS256", "typ": "JWT", "kid": "q3Xr…"}`.
- **Entrée signée** : la chaîne ASCII `en-tête.charge`, **telle quelle** (base64url, sans décodage).
- RS256 = RSASSA-PKCS1-v1_5 sur le SHA-256 de l'entrée ; signature de 512 octets (clé `rsa-2026-10`, 4096 bits).
- Clé publique : JWKS du royaume, entrée de même `kid`, champ `x5c` (certificat autosigné qui transporte la clé ; module identique à `n`).
- Vérification : `openssl dgst -sha256 -verify cle.pub -signature signature.bin entree-signee.txt` → `Verified OK` ; un caractère changé dans la charge → `Verification failure`.
- Ordre des contrôles d'un vérificateur correct : algorithme **imposé** (jamais choisi d'après `alg`), clé par `kid` dans le JWKS de l'émetteur **attendu**, signature, puis `iss`, `exp`/`nbf`, `aud`.

## JWKS et caches

| Qui vérifie | Où il prend les clés | Quand il recharge | Ce qu'on peut observer |
|---|---|---|---|
| kube-apiserver (×3) | JWKS de l'émetteur du fichier d'authentification structurée | au démarrage, puis quand un jeton porte un `kid` inconnu (limité en fréquence) | `apiserver_authentication_jwt_authenticator_jwks_fetch_last_timestamp_seconds{result}` et `…_jwks_fetch_last_key_set_info{hash}` : même empreinte sur les trois nœuds le <AAAA-MM-JJ> |
| OAuth2 Proxy | JWKS de la découverte (`oidc_issuer_url`) | idem (bibliothèque go-oidc) | journal de l'instance au redémarrage |
| Argo CD | JWKS de la découverte | idem | journal d'`argocd-server` |
| Grafana, GitLab, Harbor… | selon le service (vérification locale ou appel à userinfo) | à vérifier par service | — |
| `verifier-jeton.sh` | JWKS de l'émetteur passé en paramètre, à chaque appel | toujours | — |

## Sessions et cookies

| Cookie | Moment | Attributs | Rôle |
|---|---|---|---|
| `AUTH_SESSION_ID` | formulaire | `HttpOnly`, `Secure`, `SameSite=None`, session | session d'authentification en cours (étapes du flux) |
| `KC_RESTART` | formulaire | `HttpOnly`, `Secure`, `SameSite=None` | reprise d'une connexion dont la session d'authentification a expiré |
| `KC_AUTH_SESSION_HASH` | formulaire | lisible par JavaScript, 60 s | détection d'une connexion faite dans un autre onglet |
| `KEYCLOAK_IDENTITY` | après connexion | `HttpOnly`, `Secure`, `SameSite=None` | jeton signé par une clé HMAC interne du royaume (jamais publiée) : **c'est lui qui fait le SSO** |
| `KEYCLOAK_SESSION` | après connexion | lisible par JavaScript, `Secure`, `SameSite=None`, durée = session SSO maximale | empreinte SHA-384 de l'identifiant de session (iframe de vérification de session) |

- L'identifiant de session de `users/<ID>/sessions` (API) = revendication `sid` des jetons ; son SHA-384 en base64url = `KEYCLOAK_SESSION`.
- Trois niveaux : session SSO (navigateur ↔ Keycloak), sessions de client (une par service, dans la session SSO), session **du service** (son propre cookie, que Keycloak ne voit pas).
- Une déconnexion de Keycloak supprime la session SSO et les sessions de client (plus de rafraîchissement) ; elle ne ferme une session de service que si ce service reçoit une déconnexion (canal avant ou arrière) ou rafraîchit souvent (OAuth2 Proxy : 5 min).

## Déconnexion par canal arrière

Essai avec le client temporaire `essai-capot` (supprimé) et un récepteur sur `idp01:127.0.0.1:18081` (arrêté). Déconnexion par `end_session` → Keycloak POSTe `logout_token=eyJhbGciOiJSUzI1NiIs…` (tronqué).

| Revendication | Valeur relevée | Remarque |
|---|---|---|
| `iss` | `https://sso.par1.medisphere.internal/realms/medisphere` | |
| `aud` | `essai-capot` | le service destinataire |
| `iat`, `jti` | <horodatage>, <identifiant> | `jti` permet de refuser un rejeu |
| `sub`, `sid` | identifiant de Lucas, session SSO | au moins l'un des deux est obligatoire |
| `typ` | `Logout` | |
| `events` | `{"http://schemas.openid.net/event/backchannel-logout": {}}` | obligatoire |
| `nonce` | **absent** | interdit par la spécification |

Signature vérifiée par `verifier-jeton.sh` (même clé que les autres jetons). Un service doit vérifier signature, `iss`, `aud`, l'événement, `sid` ou `sub`, l'absence de `nonce`, et refuser un `jti` déjà vu. Aucun de nos services ne reçoit aujourd'hui de déconnexion par canal arrière (GitLab, Grafana, Argo CD, Harbor, Proxmox, NetBox, OAuth2 Proxy : vérifié dans leur documentation le <AAAA-MM-JJ>) : RB-242 ferme leurs sessions une par une.

## Rotation des clés

- Clé active (priorité la plus haute) : signe ; passive : ne signe plus, reste publiée, vérifie ce qu'elle a signé ; désactivée : retirée du JWKS, ses jetons sont refusés partout.
- Un vérificateur adopte une nouvelle clé au premier jeton qui porte son `kid` (rechargement du JWKS) ; c'est la **désactivation** trop tôt qui casse (jetons encore valables refusés) : d'où 24 h d'attente dans RB-244.
- Pendant la rotation d'E29 : rechargement de kube-apiserver visible par `jwks_fetch_last_timestamp_seconds` (heure relevée par nœud dans le journal d'E29).

## Réponses aux questions

1. Choisir l'algorithme d'après `alg` laisse l'attaquant choisir `none` ou HS256 avec la clé publique RSA comme secret. Notre outil n'accepte que RS256 ; kube-apiserver et OAuth2 Proxy n'acceptent que des algorithmes asymétriques fixés ou annoncés par la découverte.
2. Plusieurs clés : rotation sans coupure (active, passive), et usages différents (signature, chiffrement, HMAC interne non publiée).
3. Jeton d'accès volé : jusqu'à son `exp`, 5 min ; jeton de rafraîchissement : jusqu'à son premier usage (rotation), au plus la session SSO (30 min d'inactivité, 10 h).
4. Jamais rechargé : nouvelle clé inconnue, clé compromise jamais retirée ; rechargé à chaque requête : charge et dépendance inutiles, levier pour un attaquant.
5. `KEYCLOAK_SESSION` est lu par du JavaScript et n'est qu'une empreinte : il n'authentifie rien (`KEYCLOAK_IDENTITY` le fait, en `HttpOnly`).
6. Les cookies de Keycloak doivent suivre une redirection depuis un autre site et vivre dans des iframes : `SameSite=None` ; nos services ne sont jamais intégrés ailleurs : `Lax`.
7. `iat` obligatoire, `exp` facultatif selon la spécification (relevé ci-dessus) ; rejeu refusé par la mémoire des `jti` vus.
8. <service le plus lent à adopter la nouvelle clé en E29, et pourquoi> (d'après le journal d'E29 et les métriques `jwks_fetch`).
