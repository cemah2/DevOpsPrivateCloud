# RB-074 — Un site distant ne joint plus PAR1

| | |
|---|---|
| **Portée** | Sites raccordés par WireGuard et BGP : LYO1 (`wg2`, 10.255.2.0/24, AS 65030) ; même méthode pour PAR2 (`wg0`) |
| **Déclencheur** | Appel de l'agence ; sonde « dernière poignée de main > 3 min » ; sonde « depuis l'agence » rouge |
| **Durée cible** | 15 min jusqu'au diagnostic |
| **Issu de** | INC-3402 (M07-E36) |

## Règles

- Côté bordure, **lecture seule** sur la passerelle active (`wg show`, `vtysh show …`) : ne jamais redémarrer `wg-quick@wg2` sur la bordure pour « relancer » (les scripts de transition de keepalived pilotent les tunnels, RB-071).
- Les clés **publiques** ne sont pas secrètes (registre des secrets, section « clés publiques ») ; les clés privées ne s'affichent jamais.

## 1. Où est la coupure ? (5 min)

Depuis un poste de l'agence, puis depuis le routeur de l'agence (agent QEMU si le réseau est en cause) :

```
root@lyo-pc01:~# ping -c 2 10.10.20.1
root@lyo-gw01:~# ping -c 2 10.10.20.1
```

| Poste | Routeur | Hypothèse | Aller à |
|---|---|---|---|
| KO | OK | Relais du routeur de l'agence (sysctl, `forward`, NAT) | §4 |
| KO | KO, `Required key not available` | `AllowedIPs` ne couvre pas la destination | §3 |
| KO | KO, silence | Pas de route vers PAR1, ou tunnel mort | §2 |

## 2. Route et tunnel

```
root@lyo-gw01:~# ip route get 10.10.20.1
root@lyo-gw01:~# wg show wg2
root@lyo-gw01:~# vtysh -c 'show bgp ipv4 unicast summary'
admin@<passerelle active>:~$ sudo wg show wg2
```

- Pas de poignée de main depuis plus de 2 min, octets envoyés et aucun reçu : clé du pair (comparer à la clé publique de la bordure), extrémité (VIP du VLAN 99, port 51822), filtrage UDP.
- Poignée de main récente, session BGP établie, 0 préfixe accepté : politique d'entrée de l'agence (`show route-map`, noms des route-maps par sens).
- Route vers 10.10.20.1 par la route par défaut « Internet » : **fuite** ; vérifier la route de refus `10.10.0.0/16 blackhole`.

## 3. Routage cryptographique

```
root@lyo-gw01:~# wg show wg2 allowed-ips
```

Les `AllowedIPs` du pair « bordure » doivent couvrir exactement les réseaux de PAR1 autorisés pour LYO1 (même variable que la prefix-list d'annonce). Correction par le rôle `wireguard`, application sans coupure : `wg syncconf wg2 <(wg-quick strip wg2)`.

## 4. Relais du routeur de l'agence

```
root@lyo-gw01:~# sysctl net.ipv4.ip_forward
root@lyo-gw01:~# grep -rn ip_forward /etc/sysctl.conf /etc/sysctl.d/
root@lyo-gw01:~# nft list chain inet filter forward 2>/dev/null
```

Un fichier de « durcissement » qui force `ip_forward = 0` reviendra à chaque redémarrage : le supprimer, `sysctl --system`, et ajouter au rôle un contrôle qui échoue si le relais est désactivé.

## 5. Après correction

`lab/bin/check 07 36` ; depuis le poste : un service réel de PAR1 ; vérifier que MGMT (10.10.10.0/24) reste **inaccessible** depuis l'agence ; journal d'incident.
