# Chiffrement du trafic entre nœuds de `k8s-par1`

| | |
|---|---|
| Tickets | SEC-1624 (M15-E24), SEC-2726 (M26-E26) |
| Propriétaire | Équipe Plateforme ; revue : RSSI |
| Dernière revue | <DATE> |

## Décision (révisée en M26-E26)

Cilium 1.20 chiffre par **WireGuard** (UDP 51871, interface `cilium_wg0`, une paire de clés par agent,
clé publique dans l'annotation `network.cilium.io/wg-pub-key` du `CiliumNode`) :

- depuis M15-E24 : tout le trafic **entre pods de nœuds différents** ;
- depuis M26-E26 (`encryption.nodeEncryption: true`, *beta*) : aussi **nœud ↔ nœud, pod → nœud, nœud → pod**
  (un pod en `hostNetwork` compte comme « nœud »), **sauf** depuis et vers les nœuds de contrôle, exclus
  par défaut (`node-encryption-opt-out-labels` = `node-role.kubernetes.io/control-plane`).

Non retenu : mode strict (`encryption.strictMode.egress.*`, `encryption.strictMode.ingress.enabled` en 1.20)
— une clé périmée isolerait un nœud ; IPsec — clés à gérer, accélération absente du lab ; retrait de
l'exclusion des nœuds de contrôle — un travailleur qui change de clé ne pourrait plus la publier.

## Ce qui circule entre nœuds, avant et après

Relevé le <DATE> (`kubectl get pods -A -o json | jq` pour les pods en `hostNetwork`, `ss -lntup` sur un
nœud de contrôle et un travailleur, captures sur `eth0`). « T » = travailleur, « C » = nœud de contrôle.

| Flux | Source → destination | Port | Protégé avant (M15) | Protégé après (M26-E26) |
|---|---|---|---|---|
| Pod → pod (Service ClusterIP compris), T ↔ T, T ↔ C | pods | divers | WireGuard | WireGuard |
| Envoy de la Gateway → pod d'un autre nœud | T → T | divers | WireGuard | WireGuard |
| Prometheus → agents Cilium (`cilium-agent`, `cilium-envoy`, Hubble) | pod → T | 9962, 9964, 9965 (HTTP) | **rien** | WireGuard |
| Prometheus → agents Cilium des nœuds de contrôle | pod → C | 9962, 9964, 9965 (HTTP) | **rien** | **rien** (C exclus) |
| Prometheus → node-exporter (pod `hostNetwork`) | pod → T / C | 9100 (HTTP) | **rien** | WireGuard vers T ; **rien** vers C |
| Prometheus → kubelets (`/metrics`, cAdvisor) | pod → T / C | 10250 (TLS vérifié, E25) | TLS | TLS + WireGuard vers T |
| Prometheus → etcd (métriques) | pod → C | 2381 (HTTP) | **rien** | **rien** (C exclus) |
| Prometheus → contrôleur, ordonnanceur | pod → C | 10257, 10259 (TLS non vérifié) | TLS | TLS |
| Prometheus → Tetragon (pod `hostNetwork`) | pod → T / C | 2112 (HTTP) | **rien** | WireGuard vers T ; **rien** vers C |
| Hubble Relay → serveur Hubble des agents | pod → T / C | 4244 (TLS) | TLS | TLS + WireGuard vers T |
| metrics-server → kubelets | pod → T / C | 10250 (TLS vérifié) | TLS | TLS + WireGuard vers T |
| kube-apiserver → kubelets (`logs`, `exec`) | C → T | 10250 (TLS) | TLS | TLS (C exclus) |
| kubelets, agents Cilium → API (VIP 10.10.40.200:8443 → 6443) | T → C | 8443, 6443 (TLS) | TLS | TLS (C exclus) |
| etcd entre membres | C ↔ C | 2379-2380 (TLS mutuel) | TLS | TLS |
| VRRP de keepalived | C ↔ C | protocole 112 | rien (authentification seulement) | rien |
| Sondes de santé Cilium | T ↔ T, T ↔ C | 4240, ICMP | rien | WireGuard entre T |
| Encapsulation VXLAN | tous | UDP 8472 | dans WireGuard pour pod → pod | inchangé |
| BGP vers la bordure | T → `gw01`/`gw02` | 179 | rien (hors cluster) | rien (hors cluster) |
| Ceph (RBD, CephFS) | T → `ceph01-03` | `eth1`, VLAN 30 | messager v2 de Ceph (mode `secure` si configuré, M16) | inchangé (hors cluster) |

Constat de la capture « avant » (`tcpdump -ni eth0 -A 'tcp port 9962 and host 10.10.40.62'` sur
`k8s-w01`) : le texte des métriques (`cilium_…`) est lisible. « Après » : plus aucun TCP 9962 entre deux
travailleurs, seulement de l'UDP 51871 ; vers `k8s-cp01`, toujours lisible (exclusion).

## Ce qui reste en clair, et pourquoi c'est accepté

- **Métriques vers les nœuds de contrôle** (9962, 9100, 2381, 2112) : pas de secret, mais des noms
  d'objets et d'espaces. Accepté (VLAN 40 réservé au cluster, filtré par le pare-feu d'hôte en E27).
  Action : passer etcd en métriques HTTPS (`--listen-metrics-urls=https://…`) au prochain changement du
  plan de contrôle.
- **VRRP** : authentification seulement ; accepté (même segment, pare-feu d'hôte).
- **BGP** : hors du cluster ; TCP-MD5 si posé au M15-E11.

## Mesures

Pods `mesure-a` (`k8s-w01`) et `mesure-b` (`k8s-w02`) de la ressource du M15 ; pod de débogage de nœud
(`kubectl debug node/k8s-w02 --profile=sysadmin`, `iperf3 -s`) pour le réseau de l'hôte ; iperf3 30 s,
trois répétitions. Chiffres **indicatifs** (VMs d'un même hyperviseur, non mesurés par le workbook) :
remplace-les par tes mesures.

| Grandeur | Avant (WireGuard pod → pod) | Après (+ nœud à nœud) |
|---|---|---|
| Débit pod → pod, 1 flux | 3,1 Gbit/s | 3,1 Gbit/s (inchangé) |
| Débit pod → hôte d'un autre travailleur | 9,5 Gbit/s | 3,0 Gbit/s |
| Débit hôte → hôte (deux travailleurs) | 11 Gbit/s | 3,2 Gbit/s |
| Latence hôte → hôte (ping, moyenne) | 0,18 ms | 0,26 ms |
| Processeur des deux nœuds pendant le débit hôte → hôte | ~1,1 cœur | ~2,8 cœurs |
| MTU : `eth0` / routes des pods / `cilium_wg0` | 1500 / 1355 / 1405 | 1500 / 1355 / 1405 |
| Plus grand `ping -M do` hôte → hôte | 1472 octets de données | voir ci-dessous |

Chemin MTU des flux de l'hôte : le trafic nœud → nœud est désormais redirigé vers `cilium_wg0`
(MTU 1405). Relève ce que tu observes (`ping -M do -s <taille>` croissant, `tracepath`) : soit le noyau
renvoie « message too long » au-delà de 1377 octets de données et TCP s'adapte (découverte du MTU du
chemin), soit des paquets disparaissent sans message (trou noir de MTU) — dans ce cas, inscris-le comme
incident et reviens à `nodeEncryption: false`.

## Coût et conditions de révision

Coût : ×2,5 de processeur sur le trafic de l'hôte entre travailleurs (collecte de métriques, journaux
des agents, quelques Mo/s en régime normal : négligeable en dehors des mesures). Révision : passage en
stable du chiffrement nœud à nœud ; ajout d'un nœud hors du VLAN 40 ; exigence d'un auditeur sur les
flux des nœuds de contrôle ; un trou noir de MTU constaté.

## Preuve (à rejouer à chaque revue)

```
admin@adm01:~$ kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-wireguard} {.data.encrypt-node}{"\n"}'
admin@adm01:~$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep Encryption
admin@adm01:~$ kubectl get ciliumnodes -o custom-columns='NOEUD:.metadata.name,CLE:.metadata.annotations.network\.cilium\.io/wg-pub-key'
```
