# RB-003 — Perte d'accès Internet depuis le lab

| | |
|---|---|
| Déclencheur | alerte « sortie Internet KO » d'une sonde, ou ticket utilisateur (`apt update` en échec) |
| Prérequis | accès SSH à `adm01` et `gw01` ; console de `gw01` (noVNC/`qm terminal 1000`) en secours |
| Durée cible | 30 min |
| Issu de | M00-E38 (et M00-E40, M00-E41 pour les diagnostics voisins) |

## 1. Délimiter (5 min)

| Test | Commande | Résultat attendu |
|---|---|---|
| Passerelle depuis la VM touchée | `ping -c2 10.10.<VLAN>.1` | répond |
| Internet par adresse | `ping -c2 9.9.9.9` ; `timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443'` | répond |
| Autre VLAN | même test depuis `adm01` (VLAN 10) | répond |
| `gw01` lui-même | `ping -c2 9.9.9.9` depuis `gw01` | répond |

- `gw01` ne joint pas Internet → problème WAN/box : vérifier `ip route`, `ip -br addr show ens18`, la box. Fin de ce runbook, escalade.
- Un seul VLAN touché → étape 3 (filtrage spécifique).
- Tous les VLANs touchés, et aussi le trafic entre VLANs → étape 2 (routage).
- Tous les VLANs touchés pour Internet seulement → étape 4 (NAT).

## 2. Routage

```
admin@gw01:~$ sysctl net.ipv4.ip_forward
```
Attendu : `1`. Sinon : `sudo sysctl --system`, puis chercher qui l'a modifié (historique, changements récents).

## 3. Filtrage

```
admin@gw01:~$ sudo nft -a list chain inet filter forward | head -n 15
```
Relancer pendant un ping : une règle `drop`/`reject` dont le compteur monte, placée avant
`ct state established,related accept`, est suspecte. Comparer avec `/etc/nftables.conf`
(méthode de comparaison du corrigé M00-E38). Supprimer par handle ou recharger le fichier :
`sudo nft -c -f /etc/nftables.conf && sudo systemctl reload nftables`.

## 4. NAT

```
admin@gw01:~$ sudo tcpdump -c 4 -ni ens18 'icmp and host 9.9.9.9'     # pendant un ping depuis la VM
admin@gw01:~$ sudo nft list chain ip nat postrouting
```
Source privée visible sur `ens18` → la règle `masquerade` ne s'applique pas (interface, adresses).
Après correction : `sudo conntrack -D -s <IP-VM>` pour les flux créés pendant la panne.

## 5. Vérification

`lab/bin/check 00 38` vert ; `apt update` sur la VM touchée ; résolution externe via `dns01`.

## 6. Retour arrière

Les corrections se limitent à rétablir l'état du fichier de référence : en cas de doute,
`sudo systemctl reload nftables` recharge `/etc/nftables.conf` versionné.

## 7. Escalade

Box/FAI ou matériel de `pve01` : Claire Morel. Incident de plus de 30 min : ouvrir un INC (Nadia Roussel).
