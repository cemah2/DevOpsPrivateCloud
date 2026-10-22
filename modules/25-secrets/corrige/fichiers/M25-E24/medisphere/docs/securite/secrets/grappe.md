# Grappe OpenBao de PAR1

> Projet `plateforme/medisphere`, `docs/securite/secrets/grappe.md` — M25-E24 (PLAT-2624). Mis à jour au M25-E25 (seal), E29 (version).

## Schéma

```
                    clients : adm01 (MGMT), runner01/02 (CI), travailleurs k8s-par1 (ESO, cert-manager)
                                              │ HTTPS 8200
                                              ▼
                       openbao.par1.medisphere.internal = VIP 10.10.20.200
                       (keepalived VRID 120, portée par le nœud ACTIF seulement)
              ┌───────────────────────────────┼───────────────────────────────┐
              ▼                               ▼                               ▼
   vault01 10.10.20.21             vault02 10.10.20.22             vault03 10.10.20.23
   API 8200 / grappe 8201          API 8200 / grappe 8201          API 8200 / grappe 8201
   Raft /var/lib/openbao           Raft /var/lib/openbao           Raft /var/lib/openbao
   HAProxy :80 (défi ACME)         HAProxy :80 (défi ACME)         HAProxy :80 (défi ACME)
              └──────────── Raft + transfert de requêtes (8201, TLS interne) ──┘
                                              │ HTTPS 8200 (seal transit, M25-E25)
                                              ▼
                                  kms01 10.10.20.24 (Shamir, transit)
```

## Règles

- **Un** nœud actif (`/v1/sys/health` = 200) sert les requêtes ; les deux autres sont **en attente** (429) et transmettent par le port 8201 ce qu'on leur envoie. Le leader Raft et le nœud actif sont en pratique le même nœud, mais ce sont deux notions : le verrou d'actif est pris **après** l'élection Raft.
- Trois électeurs : la grappe tolère **une** panne. Deux nœuds arrêtés = plus de quorum = plus d'écriture **ni de lecture** (le nœud restant ne peut pas devenir actif).
- La VIP ne suit que le nœud actif (script `chk_openbao_actif`, `curl -f` sur `sys/health` local) ; sans préemption.
- Autopilot : `cleanup_dead_servers = true`, `min_quorum = 3`, seuil 24 h : il ne retire jamais un pair dans une grappe de trois (retrait manuel : RB-251).
- Configuration identique sur les trois nœuds (rôle `openbao`) : en particulier le bloc d'audit, que le nœud qui devient actif compare à celui enregistré (un écart l'empêche de prendre la main).

## Mesures (M25-E24)

| Épreuve | Indisponibilité en écriture | Échecs (boucle 250 ms) | Nouveau nœud actif | VIP déplacée en |
|---|---|---|---|---|
| `bao operator step-down` | `<MESURE>` | `<N>` | `<NŒUD>` | `<MESURE>` |
| `systemctl stop openbao` sur l'actif | `<MESURE>` | `<N>` | `<NŒUD>` | `<MESURE>` |
| `qm stop` de l'actif | `<MESURE>` | `<N>` | `<NŒUD>` | `<MESURE>` |

Ordres de grandeur attendus (voir le corrigé) : passage de témoin, moins d'une seconde (souvent aucun échec) ; arrêt propre, une à trois secondes ; arrêt brutal, de l'ordre de dix secondes (délai d'élection Raft, prise du verrou, puis deux échecs du script keepalived).

## Flux

Entre nœuds (pare-feu local, même VLAN) : 8200-8201 TCP, VRRP (112), 8402 TCP (défi ACME relayé). `ca01` → nœuds et VIP TCP 80. Consommateurs → VIP 8200 (matrice des flux, PLAN §4.12).
