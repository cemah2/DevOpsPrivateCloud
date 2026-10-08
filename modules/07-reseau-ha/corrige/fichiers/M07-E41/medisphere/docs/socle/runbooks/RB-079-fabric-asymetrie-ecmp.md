# RB-079 — Fabric : trafic qui ne revient pas, ECMP perdu

| | |
|---|---|
| **Portée** | Fabric leaf-spine en BGP (maquette du module 07 ; demain la fabric des nœuds Kubernetes) |
| **Déclencheur** | « Ça part mais ça ne revient pas » ; couples de machines qui ne se joignent pas ; un spine sans trafic |
| **Durée cible** | 20 min jusqu'au diagnostic |
| **Issu de** | INC-3407 (M07-E41) et INC-3408 (M07-E42) |

## 1. Matrice de joignabilité (5 min)

Depuis chaque leaf et chaque serveur, **avec l'adresse de boucle comme source** :

```
$ for d in <boucles>; do printf '%s ' $d; ping -c 2 -W 1 -I <ma boucle> $d >/dev/null && echo ok || echo KO; done
```

- Couples en échec **stables** : chemin ECMP mort (hachage L3) → §3.
- Échec dans un seul sens : chemin de retour → §2.
- Tout passe, mais un spine sans trafic (`ip -s link` à 30 s d'intervalle) → §3.

## 2. Trafic qui ne revient pas

```
# captures simultanées aux deux extrémités : la réponse part-elle, par où arrive-t-elle ?
$ sudo tcpdump -ni any -c 6 'icmp and host <autre boucle>'
# chemin de la réponse, règles comprises
$ ip route get <destination> from <source> [iif <entrée>]
$ ip rule show ; ip route show table all | grep <destination>
$ vtysh -c 'show ip route <destination>'           # routes statiques FRR (distance 1)
# preuve du rejet
$ nstat -az IPReversePathFilter ; sysctl -a 2>/dev/null | grep '\.rp_filter'
```

Corriger le **chemin** (route ou règle parasite, route statique oubliée dans FRR) ; ne pas désactiver `rp_filter` pour masquer l'asymétrie. Mode recommandé : strict sur les serveurs (avec VRF de gestion), lâche sur les routeurs de fabric et la bordure.

## 3. ECMP

```
$ vtysh -c 'show bgp ipv4 unicast <boucle distante>/32'     # chemins « multipath » ?
$ vtysh -c 'show ip route <boucle distante>/32'             # installés par zebra ?
$ ip route show <boucle distante>                            # dans le noyau ?
$ vtysh -c 'show running-config' | grep maximum-paths
$ sysctl net.ipv4.ip_forward ; vtysh -c 'show ip forwarding'    # sur chaque spine
$ vtysh -c 'show route-map'                                       # entrées « deny » invoquées
```

| Observation | Cause |
|---|---|
| Un seul chemin dans BGP, l'autre spine n'a rien appris | Politique d'entrée du spine |
| Deux chemins dans BGP, un seul installé | `maximum-paths 1` |
| Deux chemins partout, des couples en échec | Un spine ne relaie pas (`ip_forward`, filtrage `forward`) |

## 4. Prouver et prévenir

Matrice complète au vert, deux chemins vers chaque boucle distante, compteurs équilibrés entre spines ; `lab/bin/check 07 41` et `07 42`. Prévention : BFD sur toutes les sessions, sondes « nombre de chemins » et « relais actif », routes statiques uniquement par le rôle `frr`.
