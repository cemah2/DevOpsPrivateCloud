# Matrice des flux du cluster `k8s-par1`

| | |
|---|---|
| Ticket | SEC-1632 |
| Exercice | M15-E32 (mise à jour par M15-E33 et M15-E34) |
| Propriétaire | Équipe Plateforme ; relue par la RSSI à chaque modification |
| Complète | `docs/socle/matrice-flux.md` (bordure, `group_vars/role_routeur/pare_feu.yml`) |

Légende « Autorisé par » : **même VLAN** = trafic dans le VLAN 40, non filtré par la bordure ni par un pare-feu
d'hôte ; **bordure** = ligne de `pare_feu.yml` ; un nom de politique = la politique Cilium ou Kubernetes qui
**autorise** le flux (jamais une politique de refus par défaut). Les noms des politiques de MédiAgenda (E17)
sont ceux de ce corrigé : remplace-les par ceux de **ton** dépôt.

## 1. Plan de contrôle et nœuds

| Source | Destination | Proto/port | Chiffré | Besoin | Autorisé par | Origine |
|---|---|---|---|---|---|---|
| `adm01`, VPN admin | VIP 10.10.40.200 | TCP 8443 | TLS | kubectl, checks | bordure (MGMT → tout) | M14-E03 |
| HAProxy (cp01-03) | kube-apiserver cp01-03 | TCP 6443 | TLS | VIP d'API | même VLAN | M14-E03 |
| keepalived cp01-03 | cp01-03 | VRRP (112), unicast | non | VIP d'API | même VLAN | M14-E03 |
| kube-apiserver | etcd cp01-03 | TCP 2379 | TLS mutuel | stockage | même VLAN | M14-E04 |
| etcd | etcd | TCP 2380 | TLS mutuel | réplication | même VLAN | M14-E05 |
| kube-apiserver | kubelet (6 nœuds) | TCP 10250 | TLS | logs, exec, métriques | même VLAN | M14 |
| kubelet, pods | VIP 10.10.40.200 | TCP 8443 | TLS | API | même VLAN | M14 |
| `adm01` | 6 nœuds | TCP 22 | SSH | administration, checks | bordure (MGMT → tout) | M14 |
| nœuds de contrôle | `s3-01` | TCP 8333 | TLS | instantanés etcd | bordure (VLAN 40 → `s3-01` 8333) | M14-E24 |
| nœuds | `reg01` | TCP 443 | TLS | images (cache Harbor) | bordure (VLAN 40 → `reg01` 443) | M14-E19 |

## 2. Réseau du cluster

| Source | Destination | Proto/port | Chiffré | Besoin | Autorisé par | Origine |
|---|---|---|---|---|---|---|
| nœud | nœud | UDP 8472 (VXLAN) | dans WireGuard | tunnel entre pods | même VLAN | M15-E02 |
| nœud | nœud | UDP 51871 (WireGuard) | oui | chiffrement entre pods | même VLAN | M15-E24 |
| agent | agent, `cilium-health` | TCP 4240, ICMP | non | santé des nœuds | même VLAN | M15-E02 |
| hubble-relay | agents | TCP 4244 | TLS (mTLS Hubble) | flux | même VLAN | M15-E05 |
| hubble-ui | hubble-relay | TCP 80→4245 | non (dans le cluster, chiffré entre nœuds) | interface | pas de politique en sortie sur hubble-ui | M15-E26 |
| `adm01` | 6 nœuds | TCP 9962-9965 | non | métriques | bordure (MGMT → tout) | M15-E26 |
| agents | VIP API | TCP 8443 | TLS | état du cluster | même VLAN | M14 |

## 3. Entrée et sortie

| Source | Destination | Proto/port | Chiffré | Besoin | Autorisé par | Origine |
|---|---|---|---|---|---|---|
| travailleurs (AS 65040) | `gw01`, `gw02` | TCP 179 | non (TCP-MD5 si posé) | annonces BGP | bordure (VLAN 40 ↔ passerelles 179) | M15-E11 |
| MGMT, VPN admin | 10.10.41.10 (`gw-par1`) | TCP 80, 443 | TLS (443) | applications, Hubble UI | bordure (MGMT → tout) | M15-E12 |
| `lb01`/`lb02` (DMZ) | 10.10.41.10 | TCP 443 (*passthrough*, noms listés) | TLS | publication externe | bordure (DMZ → 10.10.41.0/24 443) | M15-E20 |
| MGMT, VPN admin | 10.10.41.11 (`gw-partenaires`) | TCP 443 | TLS mutuel | API des partenaires | bordure | M15-E33 |
| Envoy (`ingress`) | API MédiAgenda (8000), `medidoc` (8080), `hubble-ui` (8081), `relais-mtls` (8443) | TCP | WireGuard entre nœuds | routes | `allow-gateway-api` (E17), `medidoc-entree-gateway` (E34), `hubble-ui-entree` (E26), `relais-mtls` (E33) | M15 |
| `relais-mtls` | API MédiAgenda | TCP 8000 | WireGuard entre nœuds | partenaires | `relais-mtls-vers-api` (E33) | M15-E33 |
| cert-manager | `ca01` | TCP 443 | TLS | ACME | bordure (VLAN 40 → `ca01` 443) | M15-E13 |
| cert-manager, ExternalDNS (masqués : nœud) | `dns01` | TCP/UDP 53 (RFC 2136, TSIG) | signé, non chiffré | défis DNS-01, noms | bordure (VLAN 40 → `dns01` 53) | M15-E14, E15 |
| `ca01` | 10.10.41.10 | TCP 80 | non | défis HTTP-01 | bordure | M15-E13 |
| tous les pods | CoreDNS (10.96.0.10) | UDP/TCP 53 | WireGuard entre nœuds | DNS | `base-dns` (CCNP) + politiques DNS des espaces | M15-E04, E28 |
| CoreDNS (masqué : nœud) | `dns01`, `dns02` | UDP/TCP 53 | non | récursion | bordure (DNS depuis tous les VLAN) | M15-E04 |
| API MédiAgenda | `calendrier.api.gouv.fr` | TCP 443 | TLS | jours fériés | `sortie-mediagenda` (CCNP, `toFQDNs`) | M15-E28 |
| `medidoc` | `s3-01` | TCP 8333 | TLS | documents | `medidoc-sortie` (E34) + bordure (VLAN 40 → `s3-01` 8333) | M15-E34 |

## 4. Applications

| Source | Destination | Proto/port | Chiffré | Besoin | Autorisé par | Origine |
|---|---|---|---|---|---|---|
| API MédiAgenda | PostgreSQL (même espace) | TCP 5432 | WireGuard entre nœuds | données | `api-vers-postgresql` (E17) | M15-E17 |
| API MédiAgenda | Valkey (même espace) | TCP 6379 | WireGuard entre nœuds | cache | `api-vers-valkey` (E17) | M15-E17 |
| kubelet (hôte) | pods (sondes) | TCP | non | `/sante`, `/pret`, `/healthz`, `/readyz` | hôte local toujours permis par Cilium | M14-E08 |

## 5. Flux refusés exprès

| Flux | Refusé par | Preuve |
|---|---|---|
| tout espace d'équipe → tout **autre** espace d'équipe (dont `mediagenda-dev` → `mediagenda-recette`) | `isolement-<espace>` (CCNP, `ingressDeny`/`egressDeny`) | matrice de tests de `segmentation.md` (tests 1, 2, 6) |
| MédiAgenda → Internet hors `calendrier.api.gouv.fr` | refus par défaut des espaces MédiAgenda (E17) | test 9 de `segmentation.md` |
| MédiDoc → Internet, → MédiAgenda | refus par défaut de `medidoc-dev` (E34) + `isolement-medidoc-dev` | check E34 |
| pod → `hubble-ui` sans passer par la Gateway | `hubble-ui-entree` | test depuis `wb-essais` (E26) |
| `hubble.apps…` par les répartiteurs | liste de noms de `lb01`/`lb02` (E20) | `curl --resolve … 10.10.70.200` en échec |
| partenaire sans certificat client | `relais-mtls` (nginx `ssl_verify_client on`) | E33 |
| annonces BGP hors 10.10.41.0/24 | `PL-DEPUIS-K8S` (bordure) | M15-E11 |

## 6. Vérification (période du <DATE> 09:00 au <DATE> 11:00)

Requêtes utilisées :

```
admin@adm01:~$ hubble observe --since 2h --namespace mediagenda-recette -o json \
    | jq -r 'select(.flow.verdict=="FORWARDED") | .flow | "\(.source.namespace // .source.identity)/\(.source.labels // [] | map(select(startswith("k8s:app"))) | join(",")) -> \(.destination.namespace // "world")/\(.destination_names // [] | join(",")):\(.l4.TCP.destination_port // .l4.UDP.destination_port)"' \
    | sort | uniq -c | sort -rn
admin@adm01:~$ hubble observe --since 2h --verdict DROPPED -o compact | sort | uniq -c | sort -rn | head -30
admin@adm01:~$ hubble observe --since 2h --to-identity world -o compact | head -50
```

Écarts trouvés et traitement :

| Écart | Traitement |
|---|---|
| Flux `mediagenda-recette` → `world:443` vers une adresse inconnue, refusé (bibliothèque de télémétrie de FastAPI ?) | ticket DEV-1640 à Julien : désactiver la télémétrie ; pas d'autorisation ajoutée |
| `hubble-ui` → `kube-apiserver:443` absent de la matrice | ajouté (ligne « hubble-ui → API », autorisé : pas de politique en sortie sur hubble-ui) |

## 7. Tenue à jour

- Toute MR de `plateforme/k8s` qui ajoute ou modifie une politique, une route ou une Gateway modifie cette matrice dans la même semaine (case à cocher du modèle de MR).
- Revue trimestrielle par la RSSI avec les requêtes de la section 6.
