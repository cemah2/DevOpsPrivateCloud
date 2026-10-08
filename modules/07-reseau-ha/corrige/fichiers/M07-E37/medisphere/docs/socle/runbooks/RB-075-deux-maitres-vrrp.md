# RB-075 — Deux maîtres VRRP (split-brain)

| | |
|---|---|
| **Portée** | Paires keepalived : passerelles (`gw01`/`gw02`, VRID = VLAN, 250 WAN), répartiteurs (`lb01`/`lb02`, VRID 170), maquette (`srv01`/`srv02`, VRID 199) ; plus tard VIP du cluster `hv-par1` (VRID 110) |
| **Déclencheur** | Sonde « exactement un maître par VIP » ; erreurs de connexion intermittentes ; ARP qui alterne |
| **Durée cible** | 20 min jusqu'au diagnostic |
| **Issu de** | INC-3403 (M07-E37) |

## Règles

- ⚠️ Instantané (`ms-snapshot`) des deux membres avant toute action sur une paire du socle ; agent QEMU vérifié.
- **Ne jamais arrêter keepalived sur les deux membres** ; pour les passerelles, suivre RB-071 (console `qm terminal` ouverte).
- Arrêter keepalived sur un membre fait disparaître le symptôme, pas la cause : seulement en mesure d'urgence, consignée.

## 1. Prouver le split-brain (3 min)

```
admin@<tiers sur le même VLAN>:~$ for i in $(seq 5); do sudo arping -c 1 -I <if> <VIP> | grep reply; sleep 2; done
admin@adm01:~$ for h in <membre A> <membre B>; do ssh $h "ip -br -4 addr | grep -w '<VIP>'"; done
```

## 2. Le tableau des annonces (5 min)

Sur **chaque** membre, simultanément :

```
$ sudo timeout 10 tcpdump -ni <if> -vv vrrp
$ sudo journalctl -u keepalived --since -1h --no-pager | grep -E 'STATE|VRID'
```

Remplir : émetteur, destination, VRID, priorité, version ; ce que chaque membre reçoit de l'autre.

| Observation | Cause probable | Vérification |
|---|---|---|
| Annonces de A vues dans la capture de B, B maître quand même | Filtrage d'entrée sur B (`tcpdump` capture avant nftables) | `nft list ruleset`, compteurs |
| VRID ou version différents dans la capture | Configuration divergente | `grep -rn virtual_router_id /etc/keepalived` |
| Annonces de A vers une adresse qui n'est pas B | `unicast_peer` faux | `grep -A3 unicast_peer …` |
| Aucune annonce de A dans la capture de B, ni sur le fil | Segments différents (VLAN, VNet) | `bridge vlan show`, `qm config` |

## 3. Correction

- Configuration : par le rôle `keepalived` (VRID, VIP et pairs générés depuis l'inventaire), `systemctl reload keepalived`.
- Filtrage : VRRP (protocole 112, source = l'autre membre) dans la matrice des flux ; retrait de toute règle posée à chaud.
- Vérifier : un seul membre porte la VIP ; `Entering BACKUP STATE` dans le journal de l'autre.

## 4. Prouver la redondance

Bascule contrôlée (RB-070 pour les répartiteurs, RB-071 pour les passerelles) : arrêt de keepalived sur le maître, prise de la VIP par l'autre en moins de 4 s, retour. Puis `lab/bin/check 07 37` (maquette) et `ms-verif-reseau`.
