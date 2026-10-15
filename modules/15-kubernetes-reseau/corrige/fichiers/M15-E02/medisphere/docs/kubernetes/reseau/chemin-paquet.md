# Le chemin d'un paquet dans `k8s-par1`

> Fiche de l'équipe Plateforme — PLAT-1602 (M15-E02). État décrit : Cilium 1.20, mode tunnel VXLAN, IPAM `cluster-pool`.
> À relire après tout changement du mode réseau de Cilium (routage natif, chiffrement, remplacement de kube-proxy).

## Adresses

| Réseau | Plage | Qui l'attribue | Où la voir |
|---|---|---|---|
| Nœuds | 10.10.40.0/24 (VLAN 40) | OpenTofu + NetBox | `kubectl get nodes -o wide` |
| Pods | 10.240.0.0/16, un /24 par nœud | opérateur Cilium (IPAM `cluster-pool`) | `kubectl get ciliumnodes -o custom-columns=NOEUD:.metadata.name,PODS:.spec.ipam.podCIDRs` |
| Services | 10.96.0.0/16 | kube-apiserver (`--service-cluster-ip-range`) | `kubectl get svc -A` |
| Routeur de chaque nœud | une adresse de son /24, portée par `cilium_host` | agent Cilium | `ip -4 addr show cilium_host` sur le nœud |

## Interfaces d'un nœud

| Interface | Rôle |
|---|---|
| `ens18` | carte du nœud sur le VLAN 40 ; porte le tunnel VXLAN (UDP 8472) |
| `cilium_host` / `cilium_net` | paire veth de l'agent : `cilium_host` porte l'adresse « routeur » du /24 du nœud, passerelle de tous ses pods |
| `cilium_vxlan` | interface VXLAN en mode « collecte » (`external`) : pas de VNI ni de pair fixes, les programmes eBPF choisissent la destination paquet par paquet |
| `lxcXXXXXXXXXXXX` | côté nœud de la paire veth de chaque pod (l'autre côté est `eth0` dans le pod) |
| `lxc_health` | point de terminaison de santé de Cilium (sondes entre nœuds, TCP 4240) |

Pour retrouver l'interface `lxc` d'un pod : dans le pod, `ip -o link show eth0` donne `eth0@ifNN` ; sur le nœud, l'interface d'index `NN` est son pair (`ip -o link | grep "^NN:"`).

## 1. Pod → pod, même nœud

```
sonde-w01a (eth0) ──veth──> lxcA (nœud) ──[eBPF : identité, politique]──> lxcB (nœud) ──veth──> sonde-w01b (eth0)
```

- Dans le pod, la route par défaut passe par l'adresse de `cilium_host` ; le pod résout son adresse MAC par ARP, et c'est le programme eBPF de `lxcA` qui répond.
- Le programme attaché à `lxcA` (sortie du pod) cherche la destination dans la table des points de terminaison locaux, applique la politique de sortie de la source et la politique d'entrée de la destination, puis **redirige** le paquet vers `lxcB` sans passer par la table de routage du nœud.
- `tcpdump -i lxcB` sur le nœud voit le paquet tant que le routage d'hôte est « Legacy » (état du module 14) ; avec le routage d'hôte eBPF, le paquet est remis directement dans l'espace de noms du pod et `tcpdump` sur `lxcB` ne voit plus l'entrée : capturer **dans** le pod.

## 2. Pod → pod, autre nœud (tunnel VXLAN)

```
sonde-w01a ─> lxcA ─[eBPF : ipcache 10.240.Y.Z → identité + nœud 10.10.40.62]─> cilium_vxlan
     ─> ens18 de k8s-w01 : IP 10.10.40.61 → 10.10.40.62, UDP → 8472, VXLAN (VNI = identité de la source)
     ─> ens18 de k8s-w02 ─> cilium_vxlan ─[eBPF : politique d'entrée de la destination, identité lue dans le VNI]─> lxcC ─> sonde-w02
```

- L'**ipcache** (`cilium-dbg bpf ipcache list`) associe chaque adresse de pod du cluster à son identité et à l'adresse du nœud qui l'héberge (`tunnelendpoint`).
- Le **VNI** de l'en-tête VXLAN porte l'**identité de sécurité** de la source : le nœud d'arrivée applique la politique sans avoir à deviner qui a émis. `cilium-dbg identity get <VNI>` donne ses labels.
- Le paquet interne garde les adresses de pods : aucune traduction d'adresse entre pods (règle du modèle Kubernetes).
- MTU : 50 octets d'en-têtes VXLAN (Ethernet 14 + IP 20 + UDP 8 + VXLAN 8) ; avec un VLAN à 1500, les routes des pods sont à **1450**.
- Le VLAN 40 doit laisser passer UDP 8472 entre nœuds (même VLAN : la bordure ne le voit pas ; un pare-feu local des nœuds, lui, pourrait le bloquer : panne M15-E42).

## 3. Pod → hors du cluster (ex. `dns01`)

```
sonde-w01a ─> lxcA ─> routage du nœud ─> masquage (SNAT) : source 10.240.X.Y → 10.10.40.61 ─> ens18 ─> 10.10.40.1 (VIP bordure) ─> 10.10.20.10
```

- Tout ce qui sort de 10.240.0.0/16 (sauf vers un autre pod) est **masqué** derrière l'adresse du nœud : la bordure et `dns01` ne voient jamais une adresse de pod. En conséquence, la matrice des flux de la bordure raisonne en **nœuds** (10.10.40.0/24), pas en pods.
- État actuel : masquage par iptables (`bpf.masquerade` non activé).

## 4. Pod → Service (rappel)

Le pod vise l'adresse d'un Service (10.96.x.y) ; la traduction vers l'adresse d'un pod se fait **avant** le routage (dès `connect()` avec le *socket LB* de Cilium, ou par paquet). Ensuite, c'est l'un des chemins 1 ou 2.

## Commandes utiles

| Question | Commande |
|---|---|
| Points de terminaison d'un nœud, identités, état des politiques | `kubectl -n kube-system exec <POD-CILIUM-DU-NOEUD> -c cilium-agent -- cilium-dbg endpoint list` |
| Où vit telle adresse de pod, avec quelle identité | `… cilium-dbg bpf ipcache list` (ou `bpf ipcache get <IP>`) |
| Labels d'une identité | `… cilium-dbg identity get <ID>` |
| Nœuds connus et leurs adresses | `… cilium-dbg node list` |
| Mode de routage, tunnel, masquage | `… cilium-dbg status --verbose` (lignes *Routing*, *Host Routing*, *Masquerading*) |
| Le tunnel sur le fil | `sudo tcpdump -ni ens18 udp port 8472` sur un nœud |
| Trouver le pod Cilium d'un nœud | `kubectl -n kube-system get pods -l k8s-app=cilium --field-selector spec.nodeName=<NOEUD>` |

Outils des nœuds : `playbooks/k8s-outils-diagnostic.yml` de `plateforme/ansible` (tcpdump, conntrack, iptables, bpftool, dig, iperf3).
