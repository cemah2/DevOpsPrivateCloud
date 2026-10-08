# RB-073 — Diagnostic d'une session BGP

| | |
|---|---|
| **Portée** | Sessions BGP de la bordure (`gw01`/`gw02`, AS 65000) avec la fabric, LYO1 (65030) et, à partir du module 15, Kubernetes (65040) |
| **Déclencheur** | Sonde `ms-verif-reseau` « session non établie » ou « préfixes reçus hors fourchette » ; ticket « routes absentes » |
| **Durée cible** | 15 min jusqu'au diagnostic |
| **Issu de** | INC-3401 (M07-E35) |
| **Propriétaire** | Équipe Plateforme |

## Règles

- Lecture seule tant que le diagnostic n'est pas posé. **Jamais** `clear bgp *` sur la bordure (toutes les sessions tombent, Kubernetes et LYO1 compris) : `clear bgp <pair>`, et `soft` quand c'est une question de politique.
- Ne jamais désactiver `bgp ebgp-requires-policy` pour « faire passer » des routes.
- Toute correction durable passe par le rôle `frr` (MR, pipeline) ; une correction à chaud est reportée dans le code dans la journée.

## 1. Classer la panne par l'état (2 min)

```
admin@gw01:~$ sudo vtysh -c 'show bgp ipv4 unicast summary'
```

| État observé | Couche | Aller à |
|---|---|---|
| `Active` / `Connect`, compteurs figés | TCP | §2 |
| `Idle` ou `OpenSent` qui revient, « Last reset … Notification » | OPEN | §3 |
| `Established`, `(Policy)` ou 0 préfixe | Politique | §4 |
| `Established`, préfixes reçus mais absents de la table | Politique d'entrée de la bordure, ou prochain saut | §4 |

## 2. TCP ne s'établit pas

```
admin@gw01:~$ ip route get <pair>                         # le pair est-il joignable, par quelle interface ?
admin@gw01:~$ sudo tcpdump -ni any -c 10 'tcp port 179 and host <pair>'
admin@gw01:~$ nstat -az | grep -iE 'md5|ao'
admin@gw01:~$ sudo nft list ruleset | grep -n 179
```

- SYN émis sans réponse : routage ou filtrage côté pair (demander la même capture de l'autre côté).
- Option `md5` dans les SYN d'un seul côté, compteurs `TCPMD5NotFound`/`TCPMD5Unexpected` : mot de passe d'un seul côté ou différent. Le secret est dans Vault `critique` ; ne jamais l'afficher, comparer par le rôle.
- SYN reçus, jamais acquittés : filtrage d'entrée du pair (compteurs nftables qui montent pendant l'essai).

## 3. OPEN refusé

```
admin@gw01:~$ sudo vtysh -c 'show bgp neighbors <pair>' | grep -E 'remote AS|Last reset|Notification|Hostname'
admin@gw01:~$ sudo journalctl -u frr --since -30min --no-pager | grep -i notification
```

- `Bad Peer AS` : AS configuré d'un côté différent de l'AS réel de l'autre. Les AS sont déclarés une seule fois dans l'inventaire (variables de groupe consommées par le rôle `frr`) : corriger là.
- `Unsupported Capability`, identifiant de routeur en double, temps de maintien inacceptable : comparer les deux configurations chargées.

## 4. Session établie, routes absentes

```
admin@gw01:~$ sudo vtysh -c 'show bgp neighbors <pair>' | grep -iE 'policy|accepted|prefixes'
admin@gw01:~$ sudo vtysh -c 'show bgp ipv4 unicast neighbors <pair> received-routes'   # si soft-reconfiguration inbound
admin@gw01:~$ sudo vtysh -c 'show route-map' ; sudo vtysh -c 'show ip prefix-list'
```

- `(Policy)` en envoi chez le pair : sa route-map de sortie manque (RFC 8212).
- Préfixes reçus puis refusés : la prefix-list d'entrée de la bordure ne les autorise pas (c'est **normal** pour tout ce qui sort de 10.10.255.0/24, 10.10.41.0/24 et 10.30.0.0/16).
- Compteur `Invoked` d'une entrée `deny` qui monte : une entrée de route-map bloque tout.

## 5. Après correction

1. `clear bgp <pair> soft in` (ou `out`) si la politique a changé ; la session ne doit pas tomber.
2. `ip -4 route show proto bgp` sur les **deux** passerelles : préfixes attendus, rien d'autre.
3. `lab/bin/check 07 35` (maquette) ; `ms-verif-reseau` au vert.
4. Journal d'incident : état initial des deux côtés, couche identifiée, preuve, correction et MR.

## Prévention

- Sondes séparées « session établie » et « préfixes reçus dans la fourchette ».
- BFD sur les sessions de la fabric et de Kubernetes.
- Contrôle « jeu de règles nftables chargé = fichier » sur tout routeur.
