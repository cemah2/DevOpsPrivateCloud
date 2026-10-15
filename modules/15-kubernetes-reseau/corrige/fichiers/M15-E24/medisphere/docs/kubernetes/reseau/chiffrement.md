# Chiffrement du trafic entre nœuds de `k8s-par1`

| | |
|---|---|
| Ticket | SEC-1624 |
| Exercice | M15-E24 |
| Propriétaire | Équipe Plateforme |
| Dernière revue | <DATE> |

## Décision

Cilium 1.20 chiffre par **WireGuard** (`encryption.type: wireguard`) tout le trafic **entre pods de nœuds
différents**. Chaque agent crée sa paire de clés au démarrage, publie sa clé publique dans l'annotation
`network.cilium.io/wg-pub-key` de son `CiliumNode` et monte l'interface `cilium_wg0` (UDP 51871). Aucun
secret à gérer, aucune rotation à organiser : une clé change quand l'agent la régénère (nœud reconstruit).

Non retenu pour l'instant :

| Option | Raison |
|---|---|
| `nodeEncryption` (beta) | Les flux entre nœuds (API, etcd, kubelet) sont déjà en TLS mutuel ; les nœuds de contrôle en sont exclus par défaut ; *beta* en 1.20. À réévaluer (ADR-0150). |
| `strictMode.ingress` | Refuse tout trafic entre pods non chiffré : une clé publique périmée (nœud reconstruit) coupe le nœud. Bénéfice faible tant que le VLAN 40 est à nous. |
| IPsec | Clés à générer, distribuer et faire tourner nous-mêmes (Secret `cilium-ipsec-keys`) ; plus d'en-têtes ; seul intérêt : l'accélération matérielle, absente du lab. |

## Ce qui est chiffré, et ce qui ne l'est pas

| Flux | Chiffré par | Remarque |
|---|---|---|
| Pod → pod d'un autre nœud (dont par un Service ClusterIP) | WireGuard (Cilium) | double encapsulation : VXLAN dans WireGuard |
| Pod → pod du même nœud | rien | ne quitte pas le nœud (comportement voulu par Cilium) |
| Envoy (Gateway) → pod d'un autre nœud | WireGuard | tableau *Which traffic is encrypted*, ligne « L7 Proxy / Ingress » |
| Client (`adm01`, `lb01`) → Gateway | TLS de la Gateway | WireGuard ne couvre jamais l'extérieur du cluster |
| Nœud → nœud (kubelet, API, etcd, BGP vers la bordure) | TLS de Kubernetes / rien pour BGP | BGP vers `gw01`/`gw02` en clair (même VLAN, TCP-MD5 si posé en E11) |
| Pod → `s3-01`, `ca01`, `reg01` | TLS applicatif | sortent du cluster masqués derrière l'adresse du nœud |
| Sonde du kubelet → pod d'un autre nœud | rien (sans `nodeEncryption`) | pas de donnée de santé |

## Mesures (pods `mesure-a` sur `k8s-w01`, `mesure-b` sur `k8s-w02`, iperf3 30 s, 3 répétitions)

Les chiffres ci-dessous sont **indicatifs** (ordre de grandeur attendu sur des VMs d'un même hyperviseur, non mesuré par le workbook) : **remplace-les par tes mesures**.

| Grandeur | Avant (VXLAN) | Après (VXLAN + WireGuard) | Écart |
|---|---|---|---|
| Débit TCP, 1 flux | 9,8 Gbit/s | 3,1 Gbit/s | −68 % |
| Débit TCP, 4 flux | 12,4 Gbit/s | 5,6 Gbit/s | −55 % |
| Latence (ping 100 paquets, moyenne) | 0,21 ms | 0,29 ms | +0,08 ms |
| MTU de `eth0` des pods | 1450 | 1370 | −80 octets |
| Processeur des deux nœuds pendant le débit | ~1,2 cœur | ~2,9 cœurs | ×2,4 |

Réserve : les six nœuds sont des VMs d'un seul hyperviseur, le « réseau » est un pont Linux en mémoire de
`pve01`. Le débit est limité par le processeur, pas par un lien : l'écart réel sur des serveurs physiques
reliés en 10 Gbit/s serait différent. L'ordre de grandeur du coût processeur, lui, est représentatif.

## Preuve

- `cilium-dbg status | grep Encryption` sur chaque agent : `Encryption: Wireguard [cilium_wg0 (Pubkey: …, Port: 51871, Peers: 5)]` (format de la documentation 1.20 ; le détail peut varier).
- Capture sur l'interface VLAN 40 de `k8s-w02` pendant une requête HTTP de `mesure-a` : plus aucun paquet UDP 8472, seulement de l'UDP 51871 illisible. Sur `cilium_wg0`, la même requête apparaît en clair : c'est l'interface **avant** chiffrement.

## Flux réseau

Aucune règle de bordure : les six nœuds sont dans le VLAN 40, UDP 51871 ne traverse pas `gw01`/`gw02`. Si un
nœud était un jour dans un autre VLAN (ou un autre site), il faudrait ouvrir UDP 51871 entre les réseaux des
nœuds dans `pare_feu.yml`, et la MTU du chemin deviendrait un sujet (WireGuard ne fragmente pas pour nous).
La ligne est inscrite dans la matrice des flux du cluster (M15-E32).

## Exploitation

- Supervision : `ms-verif-k8s-reseau` (M15-E26) contrôle la présence de la clé dans chaque `CiliumNode`.
- Nœud reconstruit : nouvelle clé, publiée par l'agent ; les autres la reprennent. Pertes de paquets possibles quelques secondes (problème connu `cilium/cilium#33159`).
- Retour arrière : `encryption.enabled: false` dans `composants/cilium/values.yaml`, MR, application, redémarrage des agents.
