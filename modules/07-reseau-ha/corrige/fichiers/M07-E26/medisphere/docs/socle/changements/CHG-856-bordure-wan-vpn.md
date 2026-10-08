# CHG-856 — Bordure redondante côté WAN et VPN

| | |
|---|---|
| Ticket | PLAT-852 |
| Demandeur | Nadia Roussel ; relecture : Karim Benali, Sophie Laurent (clés, NAT) |
| Créneau | `<DATE>`, 9 h 00 – 12 h 00, hors fenêtre de sauvegarde PBS (22 h – 2 h) |
| Hôtes | `gw01`, `gw02` (pool `lab`) ; **`pve01`** (routes) et **`pbs01`** (pare-feu, `wg0`) hors pool `lab` ; poste de `<MOI>` |
| Risque | Élevé : accès au lab depuis le LAN maison, VPN d'administration, sauvegardes PAR2, Lyon |

## Objectif

Tout ce qui suit la passerelle active la suit vraiment : VIP WAN `<IP-GW-WAN-VIP>` (VRID 250, groupe `BORDURE`), traduction sortante vers cette VIP, redirection HTTPS sur cette VIP, tunnels `wg0`/`wg1`/`wg2` (mêmes clés, montés sur le maître seulement), extrémités externes (`pve01`, `pbs01`, poste) sur la VIP.

## Étapes

| # | Action | Vérification | Retour arrière |
|---|---|---|---|
| 1 | Clés privées de `gw01` reprises en Vault `critique` (`ansible-vault edit`), rôle `wireguard` appliqué à **`gw02`** seulement (`pilotage: transition` : rien ne démarre) | `/etc/wireguard/wg*.conf` en 600 sur `gw02` ; `wg pubkey < …` identique sur les deux | supprimer les fichiers de `gw02` |
| 2 | Rôle `wireguard` sur `gw01` : fichiers identiques, `wg syncconf` (aucune coupure) ; unités `wg-quick@` **désactivées** | `wg show` inchangé ; `systemctl is-enabled wg-quick@wg0` → `disabled` | réactiver les unités |
| 3 | Groupe `BORDURE` désactivé (`bordure_groupe_actif: false`, aucune transition), instance WAN sur `gw01` puis `gw02`, puis groupe reconstitué (`playbooks/groupe-bordure.yml`) : jamais d'instance nouvelle dans un groupe déjà maître | VIP WAN sur `gw01` ; la box la voit (`arping` depuis `pve01`) ; aucune VIP de VLAN n'a bougé ; groupe de dix instances | retirer l'instance (MR inverse, groupe désactivé pendant le retrait) |
| 4 | Matrice : traduction vers la VIP (masquerade retiré), traductions des tunnels, redirection 443 sur la VIP, VRRP WAN | `nft list ruleset` identique sur les deux ; `curl ifconfig.me` depuis une VM du VLAN 99 (source = VIP) | filet du rôle `pare_feu` ; MR inverse |
| 5 | Purge des entrées conntrack des tunnels sur `gw01` (`conntrack -D -p udp --orig-port-src 51820`, puis 51821, 51822) : les prochains paquets émis prennent la nouvelle traduction | `conntrack -L -p udp --orig-port-src 51820` : `src=` réponse vers la VIP | aucun (la purge recrée l'entrée) |
| 6 | `pbs01` : nft accepte propre de `gw01` **et** VIP, puis `wg set … endpoint` VIP | poignée de main `wg0` < 2 min ; sauvegarde de test | remettre l'extrémité `<IP-GW01-WAN>` |
| 7 | `pve01` : `ip route replace` des trois réseaux via la VIP, puis fichier | `ssh root@pve01` et API depuis `adm01` | `ip route replace … via <IP-GW01-WAN>` |
| 8 | Poste : extrémité `wg1` sur la VIP | `ping 10.10.10.10` depuis le poste | ancienne extrémité |
| 9 | Script de transition : `bordure_tunnels: [wg0, wg1, wg2]` | `cat /etc/bordure/transition.conf` | liste vide |
| 10 | Test : RB-071 aller et retour, avec les flux de la fiche (PAR2, VPN, Lyon, LAN maison → GitLab) | voir compte rendu | RB-071 retour |
| 11 | `pbs01` : nft restreint à la VIP seule | sauvegarde de test | — |

## Compte rendu

| Flux pendant la bascule `gw01` → `gw02` | Résultat | Retour (`gw02` → `gw01`) |
|---|---|---|
| `adm01` → `pve01` (SSH) | `<…>` | `<…>` |
| `adm01` → `pbs01` (8007) | `<…>` | `<…>` |
| Poste (VPN `wg1`) → `adm01` | `<…>` | `<…>` |
| `lyo-pc01` → `nbx01` ; session BGP 65030 | `<…>` | `<…>` |
| LAN maison → `https://gitlab.par1.medisphere.internal` (redirection) | `<…>` | `<…>` |
