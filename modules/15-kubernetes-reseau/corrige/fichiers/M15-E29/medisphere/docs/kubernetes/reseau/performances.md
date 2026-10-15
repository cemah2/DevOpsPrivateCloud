# Performances réseau de `k8s-par1`

| | |
|---|---|
| Ticket | PLAT-1629 |
| Exercice | M15-E29 |
| Dernière revue | <DATE> |

> Les chiffres de ce document sont **indicatifs** (ordre de grandeur attendu sur des VMs d'un seul hyperviseur, non mesuré par le workbook) : remplace-les par tes séries.

## Protocole

- Pods `mesure-a` (client) et `mesure-b` (serveur `iperf3 -s`, `agnhost netexec`) de `ressources/E24-mesure-iperf3.yaml`, espace `wb-perf`, sans politique réseau ; inter-nœuds : `k8s-w01` → `k8s-w02` ; même nœud : les deux sur `k8s-w02`.
- Grandeurs : TCP 1 flux et 4 flux (`iperf3 -t 30 [-P 4]`), UDP à 1 Gbit/s imposé (`-u -b 1G`, pertes), latence au repos (`ping -c 100 -i 0.2`), latence sous charge (même ping pendant un TCP 4 flux), requêtes HTTP courtes (`curl -w '%{time_total}'` × 1000 vers `/hostname`, médiane et 99e centile).
- 5 répétitions par grandeur ; on retient la médiane et l'écart (min-max). Rien d'autre sur `pve01` (`ceph-par1` arrêté), mêmes nœuds, mêmes pods recréés entre les séries.
- Référence sans Kubernetes : `iperf3` entre `k8s-w01` et `k8s-w02` sur 10.10.40.61/62 (paquet `iperf3` installé puis retiré).

## Résultats

| Grandeur (médiane, [min-max]) | Référence nœud → nœud | A1 : VXLAN + WG, inter-nœuds | A2 : même nœud | B : natif + WG, inter-nœuds |
|---|---|---|---|---|
| TCP 1 flux (Gbit/s) | 14,0 [13,1-14,6] | 3,1 [2,8-3,3] | 28 [26-30] | 3,6 [3,3-3,9] |
| TCP 4 flux (Gbit/s) | 18,5 [17-19] | 5,6 [5,2-5,9] | 41 [38-44] | 6,4 [6,0-6,8] |
| UDP 1 Gbit/s : pertes | 0 % | 0,4 % | 0 % | 0,3 % |
| Latence au repos (ms) | 0,15 | 0,29 | 0,05 | 0,26 |
| Latence sous charge (ms) | 0,4 | 1,9 | 0,3 | 1,6 |
| HTTP court, médiane / p99 (ms) | — | 1,1 / 2,8 | 0,7 / 1,9 | 1,0 / 2,5 |
| Processeur (cœurs, deux nœuds, TCP 4 flux) | 1,5 | 3,0 | 1,8 | 2,8 |
| MTU des pods | — | 1370 | 1370 | 1420 |

## MTU de bout en bout

- VLAN 40 : 1500. VXLAN : 50 octets (IP 20 + UDP 8 + VXLAN 8 + Ethernet interne 14) ; WireGuard : 80 octets réservés par Cilium (IP 20 + UDP 8 + en-tête et étiquette WireGuard 32, marge pour IPv6). Pods en tunnel + WireGuard : 1500 − 50 − 80 = **1370** ; en natif + WireGuard : 1500 − 80 = **1420**.
- Mesure : `ping -M do -s 1342` passe (1342 + 28 = 1370), `-s 1343` échoue (`message too long`) entre `mesure-a` et `mesure-b`.
- Un nœud avec une MTU différente : Cilium calcule la MTU des pods à partir de **sa** interface ; un pod d'un nœud à 9000 enverrait de gros paquets que l'autre nœud (1500) ne recevrait pas : trous noirs sur les gros transferts (le TCP s'établit, les données ne passent pas). Une seule MTU par VLAN (M07-E15).

## Lecture

- **Chiffrement** : c'est lui qui coûte le plus (E24 : environ −60 % en débit, ×2 en processeur). Le débit est limité par le processeur des VMs, pas par un lien.
- **VXLAN contre natif** : +15 % de débit environ et 50 octets de MTU en natif ; latence presque identique. L'écart est faible devant celui du chiffrement.
- **Même nœud** : aucune encapsulation ni chiffrement ; c'est ce que gagnerait une affinité API ↔ base (au prix de la résilience).
- Réserves : un seul hyperviseur, pont Linux en mémoire, VMs à 4 vCPU ; aucune vraie carte réseau ; les résultats ne prédisent pas la production, ils comparent des modes **entre eux**.

## Recommandation pour l'ADR-0150

Rester en **tunnel VXLAN** : le gain du natif (≈ 15 %) ne compense pas sa dépendance au domaine L2 commun des nœuds (ou à l'annonce des plages de pods à la bordure, que sa politique refuse) ; revoir si le cluster s'étend sur plusieurs VLAN avec une vraie fabric (BGP des PodCIDR) ou si le débit entre pods devient un goulot mesuré. BBR (`bandwidthManager.bbr`) : sans intérêt dans le lab (liens courts, sans perte) ; à revoir pour des flux vers PAR2.
