# Essais de cycle de vie Cluster API — capi-essai (M18-E13)

> Compte rendu à remplir avec **tes** mesures. Les valeurs entre crochets sont des ordres de grandeur attendus.

| | |
|---|---|
| Date | <AAAA-MM-JJ> |
| Cluster | `capi-essai` : 1 nœud de contrôle + 2 travailleurs, 2 vCPU / 4 Go / 32 Go, VLAN 40 |
| Versions | Cluster API 1.12.<N>, CAPMOX 0.9.<N>, IPAM in-cluster <N>, Kubernetes v1.36.4 → v1.36.5 |
| Charge témoin | `wb-essais/temoin` : 3 réplicas `pause`, PDB `minAvailable: 2` |

## 1. Réparation automatique (MachineHealthCheck `capi-essai-travailleurs`)

| Instant | Événement | Mesure |
|---|---|---|
| T0 | `qm stop <VMID>` sur `pve01` | |
| | `Node` en `Ready=Unknown` | [≈ 40 s] |
| | pods du nœud évincés et recréés ailleurs | [≈ 5 min] |
| | `Machine` marquée malade (`HealthCheckSucceeded=False`) | [≈ 5 à 6 min] |
| | VM supprimée par CAPMOX | |
| | nouvelle VM clonée (VMID : ) | |
| | nouveau `Node` `Ready` | [≈ 10 à 15 min] |

Minimum de pods témoins prêts : [2]. Remarques :

## 2. Mise à l'échelle

| Opération | Durée | Remarques (drain, PDB) |
|---|---|---|
| 2 → 3 travailleurs (MR + `apply`) | [≈ 6 à 10 min] | |
| 3 → 2 (machine choisie par `cluster.x-k8s.io/delete-machine`) | [≈ 1 à 3 min] | |

## 3. Montée de version v1.36.4 → v1.36.5 (template 9060 → 9061)

| Étape | Début | Fin | Durée |
|---|---|---|---|
| Construction du template 9061 (`make build-proxmox-ubuntu-2404`) | | | [≈ 30 à 50 min] |
| Plan de contrôle (KCP) | | | [≈ 10 à 15 min] |
| Travailleurs (MD, `maxSurge: 1`, `maxUnavailable: 0`) | | | [≈ 15 à 25 min] |

- Pic de VMs simultanées : [4 pendant le plan de contrôle, 4 pendant les travailleurs].
- Membres etcd pendant le remplacement du plan de contrôle : [1 → 2 → 1].
- Interruptions de l'API vues par la boucle (secondes) :
- Minimum de pods témoins prêts : [2].

## 4. Ce que j'en retiens pour l'ADR-0180

- 
