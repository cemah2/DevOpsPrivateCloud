<!-- docs/kubernetes/reseau/matrice-flux-cluster.md — EXTRAIT : section ajoutée en M26-E27 (SEC-2727). -->

## Entrées des nœuds (pare-feu d'hôte de Cilium, M26-E27)

Relevé par `ss -lntup` sur `k8s-cp01` et `k8s-w01`, puis confirmé par 24 h d'audit par nœud. Politiques : `composants/cilium/hote/`. « C » = nœuds de contrôle, « T » = travailleurs, « tous » = les deux.

| Port / protocole | Nœuds | Source autorisée | Processus | Raison (exercice d'origine) | Politique |
|---|---|---|---|---|---|
| 22/TCP | tous | 10.10.10.0/24 (MGMT), 10.10.20.15 (`runner01`) | sshd | administration, pipeline Ansible (M04, M14) | `hote-commun` |
| ICMP 8 | tous | `remote-node`, `health`, MGMT, `mon01` | noyau | sondes cilium-health, témoin (M21) | `hote-commun` |
| ICMP 3 | tous | 10.10.0.0/16 | noyau | découverte du MTU du chemin (M26-E26) | `hote-commun` |
| 4240/TCP | tous | `remote-node`, `health` | cilium-agent | santé (M14) | `hote-commun` |
| 8472/UDP | tous | `remote-node` | noyau (VXLAN) | routage tunnel (ADR-0150) | `hote-commun` |
| 51871/UDP | tous | `remote-node` | noyau (WireGuard) | chiffrement (M15-E24, M26-E26) | `hote-commun` |
| 10250/TCP | tous | `kube-apiserver`, pods `supervision`, metrics-server | kubelet | logs, exec, métriques (M14, M21) | `hote-commun` |
| 9100/TCP | tous | pods `supervision` | node-exporter (`hostNetwork`) | métriques (M21) | `hote-commun` |
| 9962, 9964, 9965/TCP | tous | pods `supervision` | cilium-agent, cilium-envoy | métriques (M15-E26) | `hote-commun` |
| 2112/TCP | tous | pods `supervision` | Tetragon (`hostNetwork`) | métriques (M26-E20) | `hote-commun` |
| 4244/TCP | tous | Hubble Relay (`kube-system`) | cilium-agent | Hubble (M14, M15) | `hote-commun` |
| 2379-2380/TCP | C | `kube-apiserver` (autres C) | etcd | client et pairs (M14) | `hote-plan-controle` |
| VRRP (112) | C | `kube-apiserver` (autres C) | keepalived | VIP 10.10.40.200 (M14-E03) | `hote-plan-controle` |
| 6443/TCP | C | `cluster` (nœuds et pods) | kube-apiserver | API (HAProxy, Service `kubernetes`) | `hote-plan-controle` |
| 8443/TCP | C | `cluster`, MGMT, `vault01-03`, `mon01` | HAProxy | point d'accès de l'API (M14, M25) | `hote-plan-controle` |
| 2381, 10257, 10259, 8405/TCP | C | pods `supervision` | etcd, contrôleur, ordonnanceur, HAProxy | métriques (M21-E10, E20) | `hote-plan-controle` |
| 179/TCP | T | 10.10.40.2, 10.10.40.3 | cilium-agent (BGP) | annonces de 10.10.41.0/24 (M15-E11) | `hote-travailleurs` |

Non filtrés par ces politiques : la sortie des nœuds (aucune règle de sortie) ; les Services `LoadBalancer` et `NodePort` (traduits avant, filtrés chez les pods) ; les flux d'hôte entre travailleurs reçus par `cilium_wg0` (limite connue de Cilium 1.20).
