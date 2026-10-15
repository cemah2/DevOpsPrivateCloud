# Supervision du réseau de `k8s-par1`

| | |
|---|---|
| Ticket | PLAT-1626 |
| Exercice | M15-E26 |
| Dernière revue | <DATE> |

## Ce qui est surveillé, et par quoi

| Quoi | Source | Outil | Fréquence |
|---|---|---|---|
| Agents Cilium, Envoy, opérateur, relay, UI, CoreDNS, cert-manager, ExternalDNS | statut des DaemonSets/Deployments (API) | `ms-verif-k8s-reseau` | 5 min |
| Joignabilité entre nœuds | `cilium_unreachable_nodes` (agent, 9962) | `ms-verif-k8s-reseau` | 5 min |
| Clés WireGuard | annotation `network.cilium.io/wg-pub-key` des `CiliumNode` | `ms-verif-k8s-reseau` | 5 min |
| Sessions BGP (vue des nœuds) | statut des `CiliumBGPNodeConfig` (`peeringState`) ; métrique `cilium_bgp_control_plane_session_state` | `ms-verif-k8s-reseau` | 5 min |
| Sessions et routes vues du **maître** de la bordure | `etat-reseau` (compte `supervision`, M07-E29, champ `routes_service` ajouté en M15-E26) | `ms-verif-k8s-reseau` | 5 min |
| Certificats | `status.conditions` et `status.notAfter` des `Certificate` | `ms-verif-k8s-reseau` (seuil 10 jours) | 5 min |
| Noms publiés | DNS de `dns01` + HTTPS vérifié contre la racine | `ms-verif-k8s-reseau` | 5 min |
| Refus de politique, DNS, flux | familles Hubble `dns`, `drop`, `tcp`, `flow`, `icmp` (9965) ; `hubble observe` | lecture à la demande (Prometheus au M21) | — |

Identité de la sonde : compte de service `ms-supervision` (espace `supervision`), ClusterRole
`ms-supervision-lecture` (lecture des statuts, **pas** des Secrets), jeton long par Secret (exception documentée
comme `wb-checks`), kubeconfig `~/.config/workbook/k8s-supervision.kubeconfig` (600) sur `adm01`.

## Hubble UI : qui peut voir quoi

- Publiée en `https://hubble.apps.par1.medisphere.internal` par `gw-par1` (route `hubble-ui` dans `passerelles`, `ReferenceGrant` dans `kube-system`).
- **Aucune authentification** dans Hubble UI. Protection par le réseau seulement :
  - 10.10.41.0/24 n'est joignable que depuis MGMT (`adm01`), le VPN d'administration et la DMZ (répartiteurs) ;
  - `lb01`/`lb02` ne relaient pas `hubble.apps…` (liste explicite de noms, M15-E20) : vérifié par
    `curl --resolve hubble.apps.par1.medisphere.internal:443:10.10.70.200` (échec attendu) ;
  - la politique `hubble-ui-entree` (kube-system) n'accepte que l'identité `ingress` : un pod ne contourne pas la Gateway.
- Ce qui reste ouvert : **un pod du cluster** peut joindre la Gateway (10.10.41.10) et donc l'interface ; toute personne du VPN d'administration voit **tous** les flux (noms de pods, d'espaces, requêtes DNS). Pas d'URL ni d'en-têtes HTTP tant qu'aucune visibilité L7 n'est activée sur les applications.
- À faire : authentification OIDC devant l'interface (OAuth2 Proxy, module 24) ; ensuite seulement, élargir l'accès.

## Métriques exposées sur les nœuds

Les ports 9962-9965 écoutent sur l'adresse des nœuds, sans authentification. Ils sont joignables depuis le
VLAN 40 et MGMT. Ils ne contiennent aucune donnée de patient, mais révèlent la topologie (noms de pods,
d'espaces). Acceptable dans le lab ; en production : filtrage sur l'hôte (politique d'hôte Cilium) ou
collecte par Prometheus dans le cluster (M21) et fermeture des ports vers MGMT.
