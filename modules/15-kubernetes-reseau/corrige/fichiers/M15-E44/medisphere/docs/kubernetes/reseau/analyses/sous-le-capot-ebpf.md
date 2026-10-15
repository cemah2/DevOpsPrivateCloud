# Analyse — Le chemin d'un paquet dans Cilium (k8s-par1)

| | |
|---|---|
| **Ticket** | PLAT-1680 |
| **Cluster** | `k8s-par1`, Kubernetes 1.36, Cilium 1.20 (KPR, tunnel VXLAN, WireGuard), noyau 6.12 |
| **Objet d'étude** | Service `mediagenda-recette/mediagenda-api`, ClusterIP **10.96.41.187**:80 → pods :8000 ; client : témoin `wb-pannes/sonde-4xk2p` (10.240.3.41, `k8s-w01`) |
| **Auteur, date** | <MOI>, 2026-10-14 |

> Modèle de corrigé : les sorties sont représentatives et réduites à l'utile ; remplace-les par les tiennes (adresses, identifiants, noms de pods). Aucune donnée secrète n'y figure.

## Programmes eBPF

Sur `k8s-w01`, `bpftool net show` et `bpftool cgroup tree /sys/fs/cgroup` (depuis `kubectl debug node/k8s-w01 --profile=sysadmin`, pod supprimé ensuite) :

| Point d'attache | Programme | Rôle |
|---|---|---|
| `ens18` tcx/ingress, egress | `cil_from_netdev`, `cil_to_netdev` | trafic qui entre et sort par l'interface du nœud (NodePort, LoadBalancer, hôte) |
| `cilium_host` tcx | `cil_to_host`, `cil_from_host` | trafic de et vers la pile de l'hôte |
| `cilium_vxlan` tcx | `cil_from_overlay`, `cil_to_overlay` | entrée et sortie du tunnel |
| `cilium_wg0` tcx/egress | `cil_to_wireguard` | marquage avant chiffrement |
| `lxc…` (pod témoin) tcx/ingress | `cil_from_container` | **sortie** du pod : politique de sortie, traduction, choix du chemin |
| `lxc…` tcx/egress | `cil_to_container` | **entrée** du pod : politique d'entrée |
| cgroup racine `connect4`, `sendmsg4`, `recvmsg4`, `getpeername4` | `cil_sock4_*` | *socket LB* : traduction des Services au niveau de la socket |

## Un Service vu par Cilium

`cilium-dbg service list` puis `cilium-dbg bpf lb list` (agent de `k8s-w01`) : frontal 10.96.41.187:80 (identifiant 42), deux backends 10.240.3.17:8000 et 10.240.5.22:8000 ; à 3 réplicas, un *slot* 3 apparaît en moins d'une seconde, et disparaît au retour à 2. Le Service de la Gateway figure en ClusterIP, en NodePort et en `LoadBalancer` 10.10.41.10:443, avec Envoy comme destination (proxy L7 local).

## Suivi de connexion et NAT

`cilium-dbg bpf ct list global | grep 10.240.3.41` : `TCP OUT 10.240.3.41:50122 -> 10.240.5.22:8000 … SourceSecurityID=40213`. L'adresse de **pod** et non la ClusterIP : la traduction a eu lieu au `connect()`. `cilium-dbg bpf nat list` : vide pour ce flux, entrées de masquerade pour les requêtes de CoreDNS vers 10.10.20.10/16.

## Identités et politiques

- Témoin : point de terminaison 1877, identité **40213** (`app.kubernetes.io/name=sonde`, espace `wb-pannes`). API : identité 31842.
- *ipcache* (`cilium-dbg bpf ipcache list`) : `10.240.3.41/32 identity=40213 tunnelendpoint=0.0.0.0` (local) ; `10.240.5.22/32 identity=31842 tunnelendpoint=10.10.40.63` (sur `k8s-w03`, joint par le tunnel).
- `cilium-dbg bpf policy get 2204` (API, sur `k8s-w03`) : `Allow Ingress k8s:app.kubernetes.io/name=sonde … 8000/TCP`, compteurs qui montent avec la boucle de requêtes ; `Allow Ingress reserved:ingress 8000/TCP` (la Gateway).

## Suivre un paquet

`cilium-dbg monitor --related-to 2204 --type trace --type drop --type policy-verdict` et `hubble observe --from-pod wb-pannes/sonde-4xk2p` : `to-overlay FORWARDED` (départ de `k8s-w01`), `to-endpoint FORWARDED` (livraison sur `k8s-w03`), verdict `ingress, action allow, match L3-L4`. Autorisation d'entrée retirée : `action deny`, `drop (Policy denied)`, Hubble `INGRESS DENIED`, compteur de pertes de l'agent incrémenté. Politiques temporaires supprimées à 16 h 20.

## Réponses aux questions

1. *Socket LB* : … (adresse du pod dans la table de suivi, `getpeername` pour l'application, capture à faire vers les backends).
2. kube-proxy iptables : recherche linéaire, réécriture complète à chaque mise à jour ; eBPF : tables de hachage, mise à jour par entrée.
3. Identités : stables, partagées par étiquettes, indépendantes des adresses réutilisées.
4. Tables de taille fixe (préallocation, vérifieur) ; table de suivi pleine : nouvelles connexions jetées, `cilium_drop_count_total{reason="CT map insertion failed"}`.
5. Redémarrage de l'agent : la connexion survit ; politique supprimée : coupée au paquet suivant.
6. Encapsulation VXLAN puis chiffrement WireGuard : clair sur `cilium_vxlan`, chiffré sur `ens18`.
7. XDP : gain inutile sur `k8s-par1` (virtio, trafic modeste, Envoy sur le chemin) ; non activé (ADR-0150).
