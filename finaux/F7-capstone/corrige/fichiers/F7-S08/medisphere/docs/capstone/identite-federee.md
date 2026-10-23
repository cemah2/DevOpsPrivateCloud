# Identité fédérée du client GHSV

> F7-S08 (PLAT-3708). Exigences : ESC-04 (agents authentifiés **exclusivement** par l'IdP OIDC du GHSV, MFA, aucun compte local, droits par les groupes du GHSV, désactivation effective en moins de 15 min) ; réponse R-16 (la MFA est de la responsabilité du GHSV ; nous ne proposons aucun autre moyen d'authentification aux agents). Code : `plateforme/identite` (`tofu/courtier-ghsv.tf`, `tofu/clients-dpi-ghsv.tf`, `tofu/flux.tf` ; simulation : `simulations/ghsv-idp/`). Procédure : RB-372.

## 1. Les échanges

```
 Agent (navigateur)                MédiSphère                                  GHSV (simulé : royaume ghsv-idp)
 ──────────────────                ─────────────────────────────────────────   ───────────────────────────────
 GET ghsv-agents.apps…  ─────────► oauth2-proxy-agents (ghsv-prod)
                                   │ pas de session → 302
                                   ▼
                         ◄──────── Keycloak medisphere, client ghsv-agents
                                   flux navigateur-ghsv : redirection d'office ──► /realms/ghsv-idp/…/auth
                                                                                   mot de passe + OTP (MFA du GHSV)
                         ◄──────────────────────────────────────────────────────── code d'autorisation
                                   courtier ghsv-idp (idp01, côté serveur) ──────► jeton, JWKS, userinfo
                                   │  mappeurs : ghsv.<identifiant>, rôle client-externe,
                                   │  ghsv-agents SI groups ∋ secretariat-medical (à chaque connexion)
                                   ▼
                         ◄──────── jeton medisphere (groups: [ghsv-agents]) → OAuth2 Proxy
 réponse de l'API       ◄───────── OAuth2 Proxy exige ghsv-agents, transmet le jeton d'identité → API
```

Le DPI ne passe pas par ce chemin : application cliente, jeton « client credentials » du client `ghsv-dpi` du royaume `medisphere`, vérifié par `oauth2-proxy-dpi` (F7-S09).

## 2. Ce que nous recevons du GHSV, et ce que nous en faisons

| Revendication | Usage chez nous | Conservé |
|---|---|---|
| `sub` | lien stable entre le compte fédéré et l'agent | oui (lien du fournisseur) |
| `preferred_username` | identifiant chez nous : `ghsv.<identifiant>` (aucune collision possible avec l'annuaire) | oui |
| `email` | traçabilité (journaux d'accès), OAuth2 Proxy ; `trust_email` : le GHSV fait foi pour ses agents | oui |
| `given_name`, `family_name` | affichage | oui |
| `groups` | **seule** source de droit : `secretariat-medical` → groupe `ghsv-agents` | non (seul le groupe dérivé est conservé) |
| tout le reste (`acr`, rôles, attributs) | ignoré | non |
| jetons du GHSV | jamais conservés (`store_token = false`) | non |

**Refusé** : dériver un droit d'un autre groupe ou attribut (un « admin » chez le GHSV n'est rien chez nous) ; lier un agent à un compte existant de MédiSphère (identifiant préfixé, pas de liaison automatique) ; importer des données de santé ou des données inutiles (minimisation, RGPD).

## 3. Cloisonnement : un agent n'entre jamais dans nos outils internes

| Barrière | Mécanisme | Constat (à refaire à chaque changement de flux) |
|---|---|---|
| Royaume | tout utilisateur venu du courtier porte le rôle `client-externe` (mappeur codé en dur) ; le flux `navigateur-medisphere` de **tous** les clients internes le refuse (sous-flux conditionnel « Deny access ») | `agent.demo1` connecté sur `ghsv-agents…`, puis `https://git01…` (connexion SSO), `https://argocd.apps…`, `https://grafana.apps…` : page « accès refusé » de Keycloak (événement `LOGIN_ERROR`, erreur `access_denied`) — résultat : `<À REMPLIR>` |
| Groupes | aucun agent dans un groupe de l'annuaire ni dans `ghsv` (lecture du locataire Kubernetes) | `kubectl auth can-i --as=ghsv.agent.demo1 --as-group=oidc:ghsv-agents get pods -n ghsv-prod` → `no` |
| Mandataire | OAuth2 Proxy des agents : `allowed_groups = ["ghsv-agents"]` ; `cadre.demo1` (encadrement) → 403 | `<À REMPLIR>` |
| Réseau | l'API n'accepte que les deux mandataires (CiliumNetworkPolicy) ; la route publique mène au mandataire du DPI : sans jeton, 401 | `curl -s -o /dev/null -w '%{http_code}' https://ghsv.apps.par1.medisphere.internal/api/v1/rendez-vous` → `401` |

## 4. Cycle de vie d'un agent

| Événement chez le GHSV | Effet chez nous | Délai |
|---|---|---|
| Arrivée dans `secretariat-medical` | compte fédéré créé à la première connexion, groupe `ghsv-agents` | immédiat |
| Retrait de `secretariat-medical` | `ghsv-agents` retiré à la connexion suivante (synchronisation `FORCE`) | ≤ 15 min (expiration du cookie d'OAuth2 Proxy et de la session du client `ghsv-agents` → nouvel aller-retour vers l'IdP) |
| Désactivation du compte | l'IdP refuse l'aller-retour suivant | ≤ 15 min (ESC-04) |
| Départ définitif | compte fédéré supprimé chez nous par la revue mensuelle des comptes fédérés inactifs depuis 90 jours (RB-372 §5) ; l'accès, lui, est tombé dès la désactivation | revue mensuelle |

Le mécanisme qui borne le délai : le flux `navigateur-ghsv` n'a **pas** d'exécution « Cookie » (une session `medisphere` ne suffit pas), la session du client `ghsv-agents` dure 15 min au plus, et le cookie d'OAuth2 Proxy aussi (sans rafraîchissement). Coût : un aller-retour silencieux vers l'IdP du GHSV toutes les 15 min par agent (≈ 1 500 agents au plus fort : moins de 2 req/s sur l'IdP du GHSV).

## 5. Ce qui est contractuel

- La MFA des agents est assurée par l'IdP du GHSV (R-16) ; nous ne proposons aucun autre moyen d'authentification aux agents (aucun mot de passe chez nous, fournisseur caché sur la page de connexion).
- Le GHSV nous fournit : l'émetteur OIDC, un client confidentiel (secret par canal séparé, rotation annuelle), la revendication `groups` avec le nom du groupe convenu, un compte de test (soutenance, §12 du CCTP).
- Nous fournissons : l'adresse de retour du courtier (`https://sso.par1.medisphere.internal/realms/medisphere/broker/ghsv-idp/endpoint` dans le lab), nos adresses de sortie (filtrage chez lui), le serveur d'autorisation de l'API pour le DPI.

## 6. Supervision

- Événements de connexion du royaume `medisphere` (M24-E26) : `IDENTITY_PROVIDER_LOGIN_ERROR`, `LOGIN_ERROR` des utilisateurs `ghsv.*` ; alerte si plus de 20 erreurs du courtier en 10 min (IdP du GHSV injoignable, secret expiré, horloge).
- Métriques d'OAuth2 Proxy (`oauth2_proxy_requests_total` par code) des deux mandataires ; part des 403 des agents.
- Sonde de `mon01` : `https://sso.par1.medisphere.internal/realms/ghsv-idp/.well-known/openid-configuration` (dans le lab) — en production, l'émetteur du GHSV.

## 7. Choix et limites

- **Courtier dans le royaume `medisphere`** (décision du plan) plutôt qu'un royaume « clients » séparé (que recommandait la réponse du M24-E32) : un seul royaume à exploiter, mais il faut le refus explicite du §3. Si un deuxième client arrive, la décision est à revoir (ADR de la phase 2).
- La preuve que l'IdP a vraiment demandé un second facteur n'est pas vérifiée chez nous (R-16 : responsabilité du GHSV). Possible plus tard : exiger une valeur de `acr` (niveaux d'authentification de Keycloak) dans un mappeur conditionnel.
