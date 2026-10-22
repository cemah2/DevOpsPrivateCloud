# <AAAA-MM-JJ> — M24-E34 — Pyrra derrière le SSO (PLAT-2534)

| | |
|---|---|
| Début (lecture du ticket) | <HH:MM> |
| Preuve écrite | <HH:MM> (durée : <NN> min, objectif 60) |
| MR | `plateforme/identite` !<N> (redirection), `plateforme/identite` !<N> (valeurs de l'instance), `plateforme/gitops` !<N> (release), `plateforme/observabilite` !<N> (HTTPRoute et CNP de Pyrra) |

## Chronologie

| Heure | Étape | Résultat |
|---|---|---|
| <HH:MM> | État initial : `curl -s -o /dev/null -w '%{http_code}' https://slo.apps…/` | 200 sans authentification (le problème) |
| <HH:MM> | MR `clients-oauth2-proxy.tf` : redirection `https://slo.apps…/oauth2/callback` ; plan : 1 changement ; apply | OK |
| <HH:MM> | Secret : rien à faire (`oauth2-proxy-oidc` d'E18, commun aux instances) | OK |
| <HH:MM> | MR `plateforme/identite` (`valeurs-pyrra.yaml`) puis `plateforme/gitops` (release `oauth2-proxy-pyrra` dans l'Application `oauth2-proxy`) ; synchronisée | pods prêts |
| <HH:MM> | MR `plateforme/observabilite` : HTTPRoute `pyrra` retirée, CNP `pyrra-api-entree` limitée à `oauth2-proxy-pyrra` ; synchronisée | OK |
| <HH:MM> | Preuves (ci-dessous) | OK |

## Preuves

```
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' https://slo.apps.par1.medisphere.internal/
302 https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/auth?…client_id=oauth2-proxy…
admin@adm01:~$ kubectl get httproute -A -o json | jq -r '.items[] | select(.spec.hostnames[]? == "slo.apps.par1.medisphere.internal") | "\(.metadata.namespace)/\(.metadata.name) → \(.spec.rules[].backendRefs[].name)"'
oauth2-proxy/oauth2-proxy-pyrra → oauth2-proxy-pyrra
```

- <HH:MM> `claire.morel` (groupe `direction`) : page des SLO de MédiAgenda affichée.
- <HH:MM> `julien.petit` (groupe `mediagenda`) : authentifié, puis **403 Forbidden** d'OAuth2 Proxy.
- <HH:MM> Contournement essayé : `kubectl -n supervision port-forward` n'est pas un contournement public (RBAC) ; une HTTPRoute ajoutée vers `pyrra-api` serait refusée par la CNP (essai sur `wb-essais` non fait : chemin GitOps).

## Ce qui m'a ralenti

<…par exemple : le nom du Secret attendu par le chart, l'étiquette des pods d'OAuth2 Proxy pour la CNP, le délai d'ExternalDNS…>

## Ce qui reste

Thanos Query et Alertmanager (limite de M21-E29) : même schéma, à faire (ticket PLAT-…).
