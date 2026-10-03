# Module 00 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent tous la même trame : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif : un correctif trouvé par chance (« j'ai redémarré `gw01` et ça remarche ») est un échec pédagogique, parce que la panne reviendra et que tu ne sauras pas pourquoi.

Les scripts d'injection sont dans `corrige/pannes/` (`_commun.sh` contient les fonctions partagées). Chaque modification est journalisée sur l'hôte touché dans `/var/lib/workbook/pannes.log`, avec une copie de l'état d'origine dans `/var/lib/workbook/EXX.*`.

Les sorties de commandes reproduites ci-dessous sont **représentatives** : les numéros de handle, compteurs, adresses MAC et messages exacts varient selon ta version et ton installation.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) : message exact de dnsmasq sur une valeur invalide (E40 v1), comportement de `vzdump` vers un namespace PBS inexistant (E42 v4), application à chaud de `firewall=1` sur une carte en cours d'utilisation (E39 v2), refus de démarrage de QEMU par la surallocation heuristique du noyau (E44 v3), implémentation exacte de la zone SDN VLAN sur un bridge VLAN-aware (E47).

---

## Méthode commune aux pannes réseau

Avant le détail par exercice, la grille qui sert partout :

1. **Reproduire et délimiter** : qui est touché, depuis où, quels flux. Un symptôme sans périmètre ne permet aucune hypothèse.
2. **Couper le chemin en deux** : tester un point intermédiaire (la passerelle, l'autre extrémité du tunnel). Chaque test élimine une moitié des hypothèses.
3. **Mesurer avant de lire** : un compteur nftables qui monte, une capture, un état du noyau (`sysctl`, `ip -d link`, `wg show`) sont des preuves. Relire `/etc/nftables.conf` ne prouve rien : ce qui compte est ce qui est **chargé**.
4. **Comparer l'exécution et la persistance** : beaucoup de pannes réelles sont des modifications « à chaud » jamais reportées (ou l'inverse). La comparaison est le réflexe qui les révèle.
5. **Corriger à la racine, puis vérifier le symptôme initial** et les flux voisins.
6. **Prévenir** : quelle sonde, quel processus, quel garde-fou aurait empêché ou détecté la panne ?

Astuce réutilisable pour comparer le jeu de règles chargé et celui du fichier, sans rien toucher sur `gw01` (un espace de noms réseau vide accepte de charger le fichier ; les noms d'interface dans `iifname`/`oifname` n'ont pas besoin d'exister) :

```
root@gw01:~# ip netns add verif
root@gw01:~# ip netns exec verif nft -f /etc/nftables.conf
root@gw01:~# diff <(ip netns exec verif nft list ruleset) <(nft list ruleset | sed -E 's/counter packets [0-9]+ bytes [0-9]+/counter packets 0 bytes 0/')
root@gw01:~# ip netns del verif
```

Une différence = une modification à chaud (ou un fichier modifié mais pas rechargé). À vérifier selon ta version : l'ordre d'affichage est stable entre deux `list ruleset` d'un même nft.

---

### M00-E38 — Panne : plus d'accès Internet depuis INFRA

**Démarche de diagnostic**

*Symptômes rapportés* : depuis `dns01`, `apt update` et `curl https://deb.debian.org` échouent.

*Hypothèses initiales* (du plus proche au plus lointain) : configuration réseau de `dns01` ; résolution DNS ; joignabilité de la passerelle ; routage sur `gw01` ; filtrage `forward` ; NAT sortant ; accès Internet de `gw01` lui-même ; box/FAI.

**Étape 1 — Délimiter depuis `dns01`.**

```
admin@dns01:~$ ping -c 2 10.10.20.1            # passerelle
admin@dns01:~$ ping -c 2 9.9.9.9               # Internet par adresse
admin@dns01:~$ timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' && echo TCP-OK
admin@dns01:~$ dig @127.0.0.1 deb.debian.org +short
```

Dans les trois variantes, la passerelle répond et Internet ne répond pas, ni en ICMP ni en TCP. La résolution des noms externes échoue **aussi** : `dns01` est le résolveur récursif du lab et ses requêtes amont sortent par le même chemin. Ce n'est donc pas « un problème de DNS » : le DNS est une victime. Erreur classique : partir sur dnsmasq parce que `apt` affiche « Temporary failure resolving ».

**Étape 2 — Délimiter le périmètre (avant d'ouvrir `gw01`).**

| Test | Variante 1 | Variante 2 | Variante 3 |
|---|---|---|---|
| `adm01` → 9.9.9.9 | KO | KO | **OK** |
| `adm01` → `dns01` (SSH) | **KO** | OK | OK |
| `gw01` → 9.9.9.9 | OK | OK | OK |

- `gw01` joint Internet dans tous les cas : son WAN, sa route par défaut et la box sont hors de cause. Le problème concerne ce que `gw01` fait des paquets **qu'il fait suivre**.
- Si même le trafic entre VLANs est coupé (variante 1), c'est le routage lui-même. Si seul Internet est coupé pour tous les VLANs (variante 2), c'est un élément commun à la sortie : NAT ou filtrage de sortie. Si seul le VLAN 20 est touché (variante 3), c'est un élément spécifique à ce VLAN.

**Étape 3 — Sur `gw01`, trois preuves en trois commandes.**

```
admin@gw01:~$ sysctl net.ipv4.ip_forward
admin@gw01:~$ sudo nft list chain ip nat postrouting
admin@gw01:~$ sudo nft list chain inet filter forward | head -n 8
```

Et la capture qui tranche entre « jeté » et « sorti mais sans retour », pendant un `ping 9.9.9.9` depuis `dns01` :

```
admin@gw01:~$ sudo tcpdump -c 10 -ni any 'icmp and host 9.9.9.9'
```

**Variante 1 — routage désactivé à chaud.**

```
admin@gw01:~$ sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 0
admin@gw01:~$ grep -r ip_forward /etc/sysctl.conf /etc/sysctl.d/
/etc/sysctl.d/99-routeur.conf:net.ipv4.ip_forward=1
```

La capture montre la requête entrer sur `ens19.20` et ne jamais ressortir sur `ens18`. Le noyau jette les paquets dont il n'est pas le destinataire quand le routage est désactivé, **avant** le hook `forward` : aucune règle nftables, aucun compteur, aucun journal `nft-fwd-drop` ne le montre. Les statistiques IP du noyau, elles, augmentent (`nstat -az | grep -i InAddrErrors`, à vérifier selon ta version).

Cause racine : `net.ipv4.ip_forward` passé à 0 à chaud (`sysctl -w`), configuration persistante intacte. Un redémarrage aurait « réparé » la panne et effacé la preuve.

Correctif, en rejouant la configuration persistante (ce qui prouve au passage qu'elle est bonne) :

```
admin@gw01:~$ sudo sysctl --system | grep ip_forward
net.ipv4.ip_forward = 1
```

**Variante 2 — NAT vers la mauvaise interface.**

La capture montre la requête sortir sur `ens18` avec l'adresse source **privée** :

```
ens18 Out IP 10.10.20.10 > 9.9.9.9: ICMP echo request, id 7, seq 1, length 64
```

La box ne sait pas renvoyer vers 10.10.20.10 (et le FAI filtrerait de toute façon les sources RFC 1918). Le NAT n'est pas appliqué :

```
admin@gw01:~$ sudo nft list chain ip nat postrouting
table ip nat {
	chain postrouting {
		type nat hook postrouting priority srcnat; policy accept;
		oifname "ens19" ip saddr 10.10.0.0/16 ip daddr != 192.168.1.20 masquerade comment "lab vers Internet et LAN maison"
		oifname "wg0" ip saddr 192.168.1.0/24 masquerade comment "LAN maison vers PAR2 : retour symétrique par le tunnel (M00-E21)"
	}
}
```

`ens19` est le trunk : aucun paquet routé ne « sort » par `ens19` (ils sortent par `ens19.<VLAN>`), la règle ne s'applique jamais. Le fichier, lui, est sain (`oifname $WAN`) : c'est une modification à chaud. La comparaison exécution/fichier (méthode commune) le confirme.

Correctif :

```
admin@gw01:~$ sudo nft -c -f /etc/nftables.conf && sudo systemctl reload nftables
admin@gw01:~$ sudo conntrack -L -s 10.10.20.10        # entrées sans traduction (tuple de réponse vers 10.10.20.10)
admin@gw01:~$ sudo conntrack -D -s 10.10.20.10        # paquet conntrack ; à répéter pour chaque hôte touché
```

La seconde commande est le **piège caché** de cette variante : les connexions créées pendant la panne ont une entrée conntrack *sans* NAT. Le NAT n'étant décidé qu'au premier paquet d'un flux, un `ping` continu (même identifiant ICMP) ou un client qui réessaie avec le même port source continue d'échouer après la correction, jusqu'à expiration de l'entrée (30 s pour ICMP, bien plus pour TCP). Supprime les entrées concernées de façon ciblée ; `conntrack -F` vide toute la table et coupe aussi les sessions SSH d'administration établies à travers `gw01`.

**Variante 3 — règle « temporaire » oubliée.**

```
admin@gw01:~$ sudo nft list chain inet filter forward | head -n 4
table inet filter {
	chain forward {
		type filter hook forward priority filter; policy drop;
		iifname "ens19.20" oifname "ens18" counter packets 212 bytes 15840 drop comment "CHG-0907 isolement temporaire INFRA"
```

Relance la commande pendant un ping depuis `dns01` : le compteur monte. Cette règle est **avant** `ct state established,related accept`, donc elle coupe aussi les connexions établies. Elle ne journalise rien : la règle `log prefix "nft-fwd-drop: "` en fin de chaîne n'est jamais atteinte. C'est pour cela qu'il ne fallait pas chercher dans `journalctl`.

Correctif : supprimer la règle par son handle (ou recharger le fichier, qui ne la contient pas), puis traiter le **processus** : retrouver le changement CHG-0907, vérifier avec son auteur que l'isolement n'est plus nécessaire, le clore.

```
admin@gw01:~$ sudo nft -a list chain inet filter forward | grep CHG-0907
		iifname "ens19.20" oifname "ens18" counter packets 230 bytes 17192 drop comment "CHG-0907 isolement temporaire INFRA" # handle 57
admin@gw01:~$ sudo nft delete rule inet filter forward handle 57
admin@gw01:~$ grep -c CHG-0907 /etc/nftables.conf
0
```

**Vérification** : `lab/bin/check 00 38`, puis `apt update` sur `dns01`.

**Prévention**
- Sonde de supervision depuis **chaque** VLAN significatif (pas seulement depuis `gw01`) : TCP/443 vers deux destinations Internet et résolution d'un nom externe, toutes les minutes, alerte après 3 échecs (Prometheus *blackbox exporter*, module 21).
- Détection de dérive : comparaison quotidienne exécution/fichier pour nftables et pour les `sysctl` critiques ; à terme, configuration de `gw01` gérée par Ansible avec mode `--check --diff` planifié (module 04).
- Règle d'équipe : toute règle temporaire porte un `comment` avec ticket **et date d'expiration**, et un compteur. Une règle de blocage sans compteur ni journal est invisible au diagnostic.

**Explications**

Ordre de traitement d'un paquet routé par `gw01` : *prerouting* (conntrack, DNAT) → **décision de routage** (c'est ici que `ip_forward=0` jette le paquet) → *forward* (filtrage) → *postrouting* (SNAT/masquerade, uniquement pour le premier paquet du flux) → sortie. Chacune des trois variantes casse un étage différent, et chaque étage a son instrument de mesure : `sysctl` et statistiques IP pour le routage, compteurs de règles pour le filtrage, capture sur l'interface de sortie (adresse source) pour le NAT.

Le masquerade et la variante 2 illustrent la différence entre **décision** et **application** du NAT : la décision est prise une fois, au premier paquet, puis mémorisée dans conntrack ; les paquets suivants sont traduits par conntrack sans repasser par la chaîne `nat`.

**Alternatives**
- `nft monitor trace` (voir M00-E47) aurait désigné la règle de la variante 3 directement, au prix d'une table de traçage temporaire.
- `conntrack -E -s 10.10.20.10` (événements en direct) montre si les flux sont créés et s'ils reçoivent une traduction (`[UNREPLIED]` sans tuple de réponse traduit en variante 2).
- `ip route get 9.9.9.9 from 10.10.20.10 iif ens19.20` simule la décision de routage d'un paquet entrant ; selon les versions, un routage désactivé produit une erreur explicite (à vérifier).

**Pièges classiques**
- Tester depuis `gw01` lui-même : son trafic n'est ni routé ni traduit, il passe par *output*, pas par *forward*.
- Redémarrer `gw01` ou recharger nftables « pour voir » : la panne disparaît (variantes 1 et 2), la preuve aussi, et la cause reviendra.
- Oublier les entrées conntrack créées pendant la panne (variante 2).
- Corriger à chaud sans vérifier le fichier, ou corriger le fichier sans le recharger.
- Conclure « problème DNS » parce que le message d'`apt` parle de résolution.

**En production chez MédiSphère**

Le routeur de bordure n'est jamais modifié à la main : la configuration vient du dépôt (revue de MR, module 01 ; Ansible, module 04), chaque changement a un ticket CHG, et un contrôle de dérive alerte sur toute différence. La sortie Internet de chaque zone est sondée en continu, et les compteurs des règles de blocage sont exportés en métriques. Le module 07 doublera `gw01` (VRRP) : il faudra alors vérifier ces trois étages sur les deux routeurs.

---

### M00-E39 — Panne : `adm01` ne joint plus `dns01`

**Démarche de diagnostic**

*Symptômes* : `ssh dns01` et `ping 10.10.20.10` échouent depuis `adm01`. La VM est démarrée.

*Hypothèses* : `dns01` éteinte ou figée ; problème de routage sur `gw01` ; problème de couche 2 (VLAN, bridge) entre `gw01` et `dns01` ; filtrage entre le bridge et la VM ; configuration IP de `dns01`.

**Étape 1 — Ce qui marche encore depuis `adm01`.**

```
admin@adm01:~$ ping -c 2 10.10.20.1                       # passerelle INFRA (gw01)
admin@adm01:~$ dig +time=2 +tries=1 @10.10.20.10 dns01.par1.medisphere.internal
admin@adm01:~$ ssh pbs01 true && echo PAR2-OK             # autre destination routée
```

`10.10.20.1` répond et les autres destinations routées aussi : `gw01` route. Le DNS de `dns01` **répond en variante 2** et seulement en variante 2 : la VM est vivante, joignable en couche 3, et quelque chose filtre par port. En variantes 1 et 3, plus rien ne répond.

**Étape 2 — Depuis `gw01`, sur le même segment que `dns01`.**

```
admin@gw01:~$ ping -c 2 10.10.20.10
admin@gw01:~$ ip neigh show dev ens19.20 10.10.20.10
```

| Observation | Variante 1 | Variante 2 | Variante 3 |
|---|---|---|---|
| Ping depuis `gw01` | KO | KO | KO |
| Voisin 10.10.20.10 | `INCOMPLETE` / `FAILED` | `REACHABLE` (MAC connue) | `REACHABLE` (MAC connue) |

- Variante 1 : la résolution ARP échoue, la VM n'est **pas** sur le même domaine de diffusion que `ens19.20`. Problème de couche 2.
- Variantes 2 et 3 : ARP fonctionne (la couche 2 est bonne, la VM a toujours l'adresse 10.10.20.10), mais les paquets IP ne reçoivent pas de réponse. Le pare-feu Proxmox ne filtre pas ARP (il filtre IP) ; une pile IP mal configurée répond quand même à ARP (`arp_ignore=0` par défaut).

**Étape 3 — Côté hyperviseur.**

```
root@pve01:~# qm config 1002 | grep ^net0
root@pve01:~# ip -d link show tap1002i0 | grep -o 'master [^ ]*'
root@pve01:~# bridge vlan show dev tap1002i0
root@pve01:~# ls -l /etc/pve/firewall/1002.fw; pve-firewall status
```

*Variante 1* : `net0: virtio=BC:24:11:xx:xx:xx,bridge=vsandbox` (ou `tag=99` avant SDN). La carte est sur le VLAN 99 : elle émet ses ARP dans le mauvais domaine de diffusion. `gw01` (sur `ens19.99`) pourrait même la voir, avec une adresse qui n'appartient pas à ce sous-réseau.

*Variante 2* : `net0: …,bridge=vinfra,firewall=1` ; `tap1002i0` a pour maître `fwbr1002i0` (pare-feu historique) ; `/etc/pve/firewall/1002.fw` existe :

```
[OPTIONS]
enable: 1
policy_in: DROP

[RULES]
IN ACCEPT -p udp -dport 53
IN ACCEPT -p tcp -dport 53
```

Les trois conditions sont réunies : pare-feu du datacenter actif (M00-E27), pare-feu de la VM activé (`enable: 1`), carte avec `firewall=1`. Politique entrante `DROP` et seul le DNS autorisé : SSH, ICMP, mais aussi le **relais DHCP** de `gw01` (UDP/67 vers `dns01`) sont coupés. Une capture prouve l'endroit exact du filtrage :

```
root@pve01:~# tcpdump -c 4 -ni fwbr1002i0 icmp     # les requêtes arrivent jusqu'au bridge de pare-feu
root@pve01:~# tcpdump -c 4 -ni tap1002i0 icmp      # … mais jamais jusqu'à la VM
```

*Variante 3* : la configuration Proxmox est normale. Le réseau ne permettant plus d'entrer dans la VM, on passe par l'agent QEMU :

```
root@pve01:~# qm guest exec 1002 -- ip -4 -o addr show
root@pve01:~# qm guest exec 1002 -- ip route
```

La sortie (JSON, champ `out-data`) montre `10.10.20.10/29` et **aucune route par défaut**. Avec un /29 (10.10.20.8 à .15), la passerelle 10.10.20.1 n'est plus sur le lien : la route par défaut a disparu avec l'ancienne adresse et la VM ne sait plus répondre à rien qui soit hors de 10.10.20.8/29. Elle reçoit les pings de `gw01`… et ne peut pas lui répondre. La configuration persistante (cloud-init, `qm config 1002 | grep ipconfig0`, et le fichier réseau généré dans la VM) indique bien `/24` : modification à chaud.

**Correctifs**

*Variante 1* — remettre le bon VNet **en conservant l'adresse MAC** :

```
root@pve01:~# qm config 1002 | grep ^net0
net0: virtio=BC:24:11:AA:BB:CC,bridge=vsandbox
root@pve01:~# qm set 1002 --net0 virtio=BC:24:11:AA:BB:CC,bridge=vinfra
```

Le changement de bridge est appliqué à chaud (la carte est débranchée puis rebranchée côté hôte). Si tu écris `--net0 virtio,bridge=vinfra`, Proxmox génère une **nouvelle** MAC : la configuration réseau rendue par cloud-init, qui identifie souvent l'interface par son adresse MAC, ne s'applique plus, et tu crées une seconde panne.

*Variante 2* — revenir à l'état antérieur (pare-feu de VM désactivé), puis ouvrir un ticket pour concevoir une vraie micro-segmentation :

```
root@pve01:~# cp /etc/pve/firewall/1002.fw /root/1002.fw.$(date +%F-%H%M)
root@pve01:~# qm set 1002 --net0 virtio=BC:24:11:AA:BB:CC,bridge=vinfra,firewall=0
root@pve01:~# pvesh set /nodes/$(hostname)/qemu/1002/firewall/options --enable 0
```

Si tu choisis au contraire de **garder** le pare-feu de VM (défendable : il filtre aussi le trafic entre VMs d'un même VLAN, que `gw01` ne voit pas), la politique doit autoriser au minimum : SSH depuis `+management` (ou 10.10.10.0/24), ICMP, DNS UDP/TCP 53 depuis 10.10.0.0/16, 10.20.0.0/16 et 10.255.1.0/24, DHCP UDP/67 depuis 10.10.99.1. Sans cette liste exhaustive (matrice des flux de M00-E50), activer `policy_in: DROP` est un incident programmé.

*Variante 3* — réappliquer la configuration persistante plutôt que retaper des adresses à la main. Depuis la console de la VM (ou l'agent) :

```
root@dns01:~# networkctl reconfigure <INTERFACE>   # si systemd-networkd gère l'interface
root@dns01:~# ifdown <INTERFACE>; ifup <INTERFACE> # si c'est ifupdown (depuis la console, pas en SSH !)
```

À défaut : `ip addr del 10.10.20.10/29 dev <INTERFACE>`, `ip addr add 10.10.20.10/24 dev <INTERFACE>`, `ip route add default via 10.10.20.1`. Identifie le gestionnaire réseau de la VM (`networkctl list`, `ls /etc/netplan /etc/network/interfaces.d`) : selon l'image Debian et la version de cloud-init, ce n'est pas le même.

**Vérification** : `lab/bin/check 00 39` ; puis vérifie aussi le relais DHCP (un client du VLAN 99) et le NTP de `dns01` (`chronyc sources`).

**Prévention**
- Sondes multi-protocoles : un ping seul n'aurait pas distingué la variante 2 (DNS OK) ; une sonde DNS seule l'aurait ratée. Sonder ICMP **et** SSH **et** DNS depuis `adm01`.
- Traçabilité : les modifications de configuration de VM passent par l'API avec un compte nominatif (`wb-admin@pve`), jamais `root@pam` partagé ; le journal des tâches et `journalctl -u pvedaemon` gardent la trace (les modifications faites par `qm` en local sont moins visibles).
- Pour la variante 3 : interdire les modifications réseau à chaud sur les VMs du socle (procédure), et contrôle de cohérence « adresse configurée = adresse attendue » dans la supervision.

**Explications**

Trois couches, trois signatures :
- **Couche 2** (variante 1) : pas de réponse ARP. On regarde le bridge, le VLAN, le VNet.
- **Filtrage entre bridge et VM** (variante 2) : ARP répond, certains ports répondent, d'autres non. Le pare-feu Proxmox historique repose sur iptables appliqué au trafic ponté (`br_netfilter`). Pour isoler les règles d'une carte, Proxmox insère un petit bridge par carte (`fwbr<VMID>i<N>`), relié au bridge principal par une paire veth (`fwpr…p<N>` côté `vmbr1`, `fwln…i<N>` côté `fwbr`). Le moteur basé sur nftables (`proxmox-firewall`, en option depuis PVE 8.2) n'a plus besoin de ces bridges intermédiaires (à vérifier selon ta version).
- **Pile IP de la VM** (variante 3) : ARP répond, rien d'autre. Le masque décide de ce qui est « sur le lien » : une passerelle hors du sous-réseau rend la route par défaut inutilisable.

**Alternatives**
- `arping -I ens19.20 10.10.20.10` depuis `gw01` teste la couche 2 sans dépendre d'IP.
- `tcpdump -eni tap1002i0` sur `pve01` montre ce que la VM reçoit et émet (ARP compris), quelle que soit la panne : c'est le point d'observation le plus proche de la VM sans y entrer.
- Console série (`qm terminal 1002`) plutôt que l'agent si l'agent n'est pas actif.

**Pièges classiques**
- Recréer la carte réseau au lieu de la modifier (nouvelle MAC).
- Activer le pare-feu de VM « pour voir » sur une VM du socle sans matrice des flux.
- Corriger la variante 3 en SSH… impossible, puis en modifiant le fichier persistant alors qu'il est sain.
- Conclure « la VM est figée » parce que le ping ne répond pas, alors qu'ARP prouve le contraire.

**En production chez MédiSphère**

L'adressage et l'appartenance VLAN des VMs sont décrits dans NetBox (module 06) et appliqués par l'IaC (module 05) : un écart entre NetBox et `qm config` est une alerte. Le pare-feu de VM est géré comme du code, à partir de la matrice des flux, avec une phase « journalisation seule » avant tout `DROP`.

---

### M00-E40 — Panne : la résolution DNS ne fonctionne plus

**Démarche de diagnostic**

*Symptômes* : sur `adm01`, `apt update` et `git clone` échouent sur la résolution de noms. Les accès par IP fonctionnent.

*Hypothèses*, maillon par maillon : configuration du client (`/etc/resolv.conf`, `systemd-resolved`, `/etc/nsswitch.conf`) ; transport UDP/TCP 53 entre VLAN 10 et VLAN 20 ; service dnsmasq ; zone locale ; récursion amont (configuration ou chemin vers Internet).

**Étape 1 — La matrice de tests.** C'est l'outil central de l'exercice. Chaque case isole un maillon :

```
admin@adm01:~$ getent hosts dns01; getent hosts deb.debian.org          # client complet
admin@adm01:~$ dig +notcp @10.10.20.10 adm01.par1.medisphere.internal   # transport UDP + serveur + zone
admin@adm01:~$ dig +tcp   @10.10.20.10 adm01.par1.medisphere.internal   # transport TCP + serveur + zone
admin@adm01:~$ dig @10.10.20.10 deb.debian.org                          # + récursion
admin@dns01:~$ dig @127.0.0.1 adm01.par1.medisphere.internal; dig @127.0.0.1 deb.debian.org
admin@gw01:~$  dig @10.10.20.10 deb.debian.org                          # même serveur, autre chemin
```

Résultats attendus par variante (`refus` = réponse immédiate `connection refused`, `délai` = `connection timed out`) :

| Test | V1 dnsmasq arrêté | V2 amont invalide | V3 client `adm01` | V4 UDP/53 filtré |
|---|---|---|---|---|
| `getent` sur `adm01` (interne / externe) | KO / KO | OK / KO | KO / KO | KO / KO |
| `dig` UDP depuis `adm01`, nom interne | refus | OK | OK | délai |
| `dig` TCP depuis `adm01`, nom interne | refus | OK | OK | **OK** |
| `dig` depuis `adm01`, nom externe | refus | SERVFAIL ou délai | OK | délai |
| `dig @127.0.0.1` sur `dns01` | refus | interne OK, externe KO | OK | OK |
| `dig` depuis `gw01` | refus | externe KO | OK | OK |

Lecture :
- **Refus immédiat** partout : plus rien n'écoute sur le port 53 de `dns01` (le noyau répond par un ICMP *port unreachable*, que conntrack laisse revenir). Service arrêté.
- **Interne OK, externe KO** partout : le serveur fonctionne, sa récursion non.
- **`dig @10.10.20.10` OK mais `getent` KO**, uniquement sur `adm01` : le serveur et le transport sont bons, le client interroge autre chose.
- **UDP en délai, TCP OK**, depuis le seul VLAN 10 : filtrage du transport UDP sur le chemin. Ni le serveur ni le client ne font de différence entre UDP et TCP de cette façon.

**Variante 1 — dnsmasq arrêté et impossible à redémarrer.**

```
admin@dns01:~$ systemctl status dnsmasq --no-pager
admin@dns01:~$ sudo systemctl start dnsmasq
Job for dnsmasq.service failed because the control process exited with error code.
admin@dns01:~$ journalctl -u dnsmasq -n 20 --no-pager
admin@dns01:~$ sudo dnsmasq --test
```

`dnsmasq --test` (et le journal : le service Debian vérifie la configuration avant de démarrer) désigne `/etc/dnsmasq.d/90-perf.conf`, ligne 2 : `cache-size=dix-mille` n'est pas un nombre. Le fichier porte un commentaire « PLAT-0731 » : un changement poussé sans validation. Correctif : corriger la valeur (ou retirer le fichier si le changement n'est pas validé), **valider**, démarrer.

```
admin@dns01:~$ sudo sed -i 's/^cache-size=.*/cache-size=10000/' /etc/dnsmasq.d/90-perf.conf
admin@dns01:~$ sudo dnsmasq --test && sudo systemctl start dnsmasq
```

Impact à signaler : le DHCP du VLAN 99 était coupé aussi (même démon).

**Variante 2 — amont invalide.**

```
admin@dns01:~$ grep -Hn '^server=\|^no-resolv' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf
/etc/dnsmasq.d/medisphere.conf:12:server=192.0.2.53
admin@dns01:~$ dig @9.9.9.9 deb.debian.org +short        # le chemin vers Internet fonctionne
admin@dns01:~$ sudo tcpdump -c 6 -ni any 'udp port 53 and host 192.0.2.53'
```

`192.0.2.0/24` est le bloc de documentation TEST-NET-1 (RFC 5737) : il n'est routé nulle part. La capture montre dnsmasq relayer chaque requête vers cette adresse sans jamais obtenir de réponse. Correctif : rétablir `<DNS-AMONT>` (la valeur documentée en M00-E13), valider, redémarrer (ce qui vide aussi le cache, y compris les réponses négatives).

**Variante 3 — client `adm01` détourné.**

```
admin@adm01:~$ ls -l /etc/resolv.conf; cat /etc/resolv.conf
admin@adm01:~$ resolvectl status 2>/dev/null | sed -n '1,25p'
```

Selon la gestion du résolveur sur ta VM, tu trouves soit un `/etc/resolv.conf` réécrit en fichier ordinaire avec `nameserver 10.10.20.250`, soit (si `systemd-resolved` est actif) un serveur DNS de lien positionné à 10.10.20.250 par `resolvectl dns`. 10.10.20.250 est dans la plage réservée « équipements / tests » : rien n'y répond. Correctif selon le cas :

```
admin@adm01:~$ sudo resolvectl revert <INTERFACE> && sudo networkctl reconfigure <INTERFACE>   # cas systemd-resolved + networkd
admin@adm01:~$ sudoedit /etc/resolv.conf                                                       # cas fichier : nameserver 10.10.20.10, search par1.medisphere.internal
```

Vérifie ensuite **qui** est censé écrire ce fichier (cloud-init au premier démarrage, networkd/resolved, `resolvconf`…) pour que ta correction ne soit pas écrasée au prochain renouvellement ou redémarrage, et inversement pour ne pas figer à la main un fichier géré.

**Variante 4 — UDP/53 filtré entre VLAN 10 et VLAN 20.**

Seul le VLAN 10 est touché, et seulement en UDP. Le chemin passe par `gw01` :

```
admin@gw01:~$ sudo nft -a list chain inet filter forward | head -n 5
		iifname "ens19.10" oifname "ens19.20" udp dport 53 counter packets 96 bytes 6912 drop # handle 61
```

Le compteur monte à chaque `dig`. Correctif : `sudo nft delete rule inet filter forward handle 61` (ou rechargement du fichier sain), puis comparaison exécution/fichier. `dig +tcp` qui fonctionne était l'indice décisif : la bibliothèque C n'utilise TCP que sur réponse tronquée, donc le système entier était « sans DNS » alors que le serveur répondait parfaitement en TCP.

**Vérification** : `lab/bin/check 00 40`.

**Prévention**
- Validation obligatoire avant rechargement (`dnsmasq --test`) : en gestion de configuration, c'est l'option `validate` du module `template` d'Ansible (module 04).
- Sonde DNS depuis chaque VLAN, en UDP **et** en TCP, sur un nom interne **et** un nom externe : les quatre combinaisons distinguent la plupart des pannes.
- Deux résolveurs dans le lab (module 06 : PowerDNS Recursor redondé) ; aujourd'hui `dns01` est un point unique de défaillance, à écrire dans le dossier de M00-E50.

**Explications**

La résolution système passe par `nsswitch.conf` (`hosts: files dns …`), puis par le résolveur de la bibliothèque C, qui lit `/etc/resolv.conf` (ou le *stub* `127.0.0.53` de `systemd-resolved`). Le résolveur interroge en UDP, attend `timeout` (5 s par défaut) par serveur et par tentative, et ne passe en TCP que si la réponse est tronquée. D'où les longues attentes avant l'échec, et d'où l'invisibilité d'une panne « UDP seulement » pour qui ne teste qu'en TCP (ou l'inverse).

`dig` court-circuite toute la configuration du client quand on précise `@serveur` : c'est ce qui en fait un instrument de mesure. `ping nom` ou `getent` mesurent la chaîne complète, utile pour constater, inutile pour localiser.

**Alternatives**
- `dig +norecurse @10.10.20.10 deb.debian.org` : distingue une réponse servie du cache d'une récursion.
- Activer temporairement `log-queries` dans dnsmasq (puis le retirer : volumineux et contient des données de navigation).
- `strace -f -e trace=network getent hosts deb.debian.org` pour voir quel serveur le client interroge réellement.

**Pièges classiques**
- Redémarrer dnsmasq sans lire pourquoi il s'est arrêté (variante 1 : il ne redémarre pas).
- Tester avec `nslookup` ou `dig` sans `@` : on teste le client cassé avec lui-même.
- Oublier que `ssh dns01` fonctionnait grâce aux adresses IP de `~/.ssh/config` (choix de M00-E15) : avec des FQDN, tu aurais perdu ton accès au moment où tu en avais besoin.
- Écraser à la main un `/etc/resolv.conf` géré par un démon.

**En production chez MédiSphère**

Le DNS est un service critique et redondé (module 06), sondé en continu, avec des alertes sur le taux de SERVFAIL et sur la latence. Les postes d'administration et les scripts critiques gardent un chemin de secours indépendant du DNS (adresses dans la configuration SSH, entrées `/etc/hosts` pour les hôtes vitaux).

---

### M00-E41 — Panne : les petits échanges passent, les gros bloquent

**Démarche de diagnostic**

*Symptômes* : établissement de connexion, commandes courtes, ping, DNS : OK. Transferts volumineux : figés, sans erreur, jusqu'à expiration. Le ticket précise le flux : téléchargements vers `dns01` et `scp` de `adm01` vers `dns01` (variante 1), sauvegarde `pve01` → `pbs01` (variante 2), téléchargements vers `adm01` (variante 3).

*Hypothèse dominante* : ce profil (« petits paquets OK, gros paquets KO, aucun message d'erreur ») est la signature d'un **trou noir PMTU** : un lien du chemin a une MTU plus petite que les extrémités, et le message ICMP qui devrait le signaler (« fragmentation needed », type 3 code 4) n'arrive pas à l'émetteur. Hypothèses concurrentes à éliminer : perte de paquets aléatoire, limitation de débit, problème applicatif.

**Étape 1 — Prouver la dépendance à la taille.**

```
admin@adm01:~$ ping -c 3 -M do -s 1472 10.10.20.10       # 1500 octets, fragmentation interdite
admin@adm01:~$ ping -c 3 -M do -s 1372 10.10.20.10       # 1400 octets
```

En variante 1, 1472 échoue **sans aucun message** (simple délai), 1372 passe ; par dichotomie, la limite est exactement 1400 octets. Si ICMP fonctionnait, le premier ping aurait affiché `From 10.10.20.1 icmp_seq=1 Frag needed and DF set (mtu = 1400)` : l'absence de ce message est elle-même un indice. Même méthode pour les autres variantes :

```
root@pve01:~# ping -c 3 -M do -s 1392 10.20.10.10         # variante 2 : échoue (1420 attendus à travers wg0)
root@pve01:~# ping -c 3 -M do -s 1172 10.20.10.10         # passe : limite à 1200
admin@dns01:~$ ping -c 3 -M do -s 1472 10.10.10.10        # variante 3 : échoue de dns01 vers adm01
```

**Étape 2 — Le sens compte.** En variante 1, `dns01 → adm01` en 1500 octets passe, `adm01 → dns01` échoue : le lien étroit est sur le chemin **vers** `dns01`, c'est-à-dire sur l'interface de sortie de `gw01` vers le VLAN 20. En variante 3, c'est l'inverse (sortie vers le VLAN 10). Un téléchargement est un flux de gros paquets **vers** le client : c'est le sens qui casse.

**Étape 3 — Localiser sur `gw01`.**

```
admin@gw01:~$ ip -o link show | awk '{print $2, $4, $5}'
admin@gw01:~$ nstat -az IpFragFails
```

Une interface sort du lot : `ens19.20` à 1400 (variante 1), `wg0` à 1200 au lieu de 1420 (variante 2), `ens19.10` à 1400 (variante 3). `IpFragFails` augmente à chaque paquet trop gros avec DF : le noyau de `gw01` **sait** qu'il doit envoyer un ICMP. La configuration persistante (`/etc/network/interfaces`, `wg0.conf`) ne contient aucune MTU réduite : modification à chaud.

**Étape 4 — Pourquoi la PMTUD ne s'est pas réparée toute seule.** Capture pendant un `scp` qui stagne (variante 1) :

```
admin@gw01:~$ sudo tcpdump -ni any 'icmp or (tcp and greater 1400)' -c 20
ens19.10 In  IP 10.10.10.10.53114 > 10.10.20.10.22: Flags [.], seq 1:1449, ack 1, length 1448
ens19.10 In  IP 10.10.10.10.53114 > 10.10.20.10.22: Flags [.], seq 1:1449, ack 1, length 1448
…
```

Le même segment de 1448 octets de données est retransmis en boucle, et **aucun** ICMP ne sort. Le noyau génère pourtant le message ; il est jeté avant d'atteindre l'interface (tcpdump capture après le hook `output`) :

```
admin@gw01:~$ sudo nft list chain inet filter output
table inet filter {
	chain output {
		type filter hook output priority filter; policy accept;
		icmp type destination-unreachable icmp code frag-needed counter packets 41 bytes 23780 drop
	}
}
```

Une règle identique se trouve en tête de la chaîne `forward` (elle jetterait les ICMP émis par d'autres routeurs). Le compteur augmente au rythme des retransmissions.

**Cause racine** : deux modifications à chaud combinées lors de « l'intervention d'hier soir » : MTU réduite sur une interface de `gw01`, et filtrage des ICMP « fragmentation needed ». Chacune seule était sans effet visible : une MTU réduite avec ICMP fonctionnel coûte un aller-retour de découverte ; un filtrage ICMP sur un chemin homogène ne se voit pas. Ensemble, elles créent le trou noir.

**Correctif**

```
admin@gw01:~$ sudo ip link set dev ens19.20 mtu 1500          # variante 1 (ens19.10 en variante 3)
admin@gw01:~$ sudo ip link set dev wg0 mtu 1420               # variante 2 (valeur calculée par wg-quick)
admin@gw01:~$ sudo nft -c -f /etc/nftables.conf && sudo systemctl reload nftables
```

Le rechargement complet retire les deux règles ICMP qui n'existent pas dans le fichier (contrôle préalable : méthode commune). Les connexions TCP figées repartent d'elles-mêmes dès que leurs retransmissions passent. Pour `wg0`, préfère `ip link set` à un redémarrage de `wg-quick@wg0`, qui couperait le tunnel.

**Décision sur le MSS clamping** (attendue dans le journal)

Le *MSS clamping* réécrit l'option MSS des segments SYN qui traversent le routeur. Avec `set rt mtu`, la valeur imposée est calculée à partir de la MTU de la route de **sortie de ce SYN**. Conséquences :
- Il protège le sens **inverse** du SYN : en réduisant le MSS annoncé par le client, il limite la taille des segments que le serveur enverra.
- Il **n'aurait pas corrigé** la variante 1 : le flux cassé (`adm01` → `dns01`, ou Internet → `dns01`) dépend du MSS annoncé par `dns01` dans son SYN-ACK, qui sort de `gw01` par `ens19.10` ou `ens18` (MTU 1500) : rien n'est réduit.
- Il ne protège ni UDP (réponses DNS volumineuses, QUIC), ni ICMP, ni les tunnels imbriqués : il ne remplace pas une PMTUD fonctionnelle.

Dans ce lab, le seul lien à MTU réduite **légitime** est `wg0` (1420). Les extrémités actuelles du tunnel (`pbs01`, `gw01`) annoncent elles-mêmes un MSS adapté, mais dès que des services de PAR2 (10.20.20.0/24, MTU 1500) échangeront avec PAR1, le clamping des SYN **entrant** dans le tunnel, sur chacune des deux extrémités, évitera de dépendre de la PMTUD. La règle est fournie dans [`fichiers/M00-E41/gw01-mss-clamp.nft`](fichiers/M00-E41/gw01-mss-clamp.nft). Décision défendable : l'ajouter (défense en profondeur, sur `gw01` et `pbs01`) **et** garder les ICMP d'erreur autorisés partout ; ne jamais compter sur le clamping seul.

**Vérification** : `lab/bin/check 00 41` (pings non fragmentables dans les deux sens, transferts de 2 Mo dans les deux sens, téléchargement HTTP sur `dns01`).

**Prévention**
- Politique ICMP écrite dans la matrice des flux : les types *destination-unreachable* (dont *frag-needed*), *time-exceeded* et *parameter-problem* (et ICMPv6 *packet-too-big*) ne sont jamais jetés. Le `ct state related accept` du fichier de référence les autorise quand ils concernent un flux connu ; une règle de « durcissement » placée avant le casse.
- Test post-changement standard sur `gw01` : `ping -M do -s 1472` entre deux VLANs et `ping -M do -s 1392` à travers `wg0`.
- Supervision de la cohérence des MTU (exporter le MTU des interfaces, alerte sur changement).

**Explications**

Un émetteur IPv4 positionne le bit DF (*Don't Fragment*) sur ses segments TCP pour découvrir la MTU du chemin (PMTUD, RFC 1191). Un routeur qui ne peut pas faire passer le paquet le jette et renvoie un ICMP type 3 code 4 contenant la MTU du saut suivant ; l'émetteur met cette valeur en cache (`ip route get <dest>` affiche alors `mtu 1400` sur l'émetteur) et réduit ses segments. Si l'ICMP est perdu, l'émetteur retransmet indéfiniment le même gros segment : la connexion s'ouvre (petits SYN), les petites requêtes passent, le premier segment plein bloque tout.

Linux propose `net.ipv4.tcp_mtu_probing` (PLPMTUD, RFC 4821) qui finit par réduire la taille des segments après des pertes répétées, mais il est désactivé par défaut, lent à converger, et ne concerne que TCP de l'hôte qui l'active : c'est une rustine côté client, pas une réparation du réseau.

Pourquoi `IpFragFails` et pas `IpOutNoRoutes` : le paquet est routable, c'est sa taille qui empêche l'émission sur l'interface choisie.

**Alternatives**
- `tracepath -n 10.10.20.10` découvre la MTU de chemin saut par saut… à condition de recevoir les ICMP : pendant la panne, il ne voit pas la réduction, ce qui confirme indirectement le filtrage.
- Capturer sur l'émetteur (`adm01`) plutôt que sur `gw01` : retransmissions visibles, aucun ICMP reçu.
- `ss -ti dst 10.10.20.10` sur l'émetteur : `pmtu`, `rcv_mss`, `retrans` et `mss` de la connexion figée.

**Pièges classiques**
- Tester avec un `ping` de taille par défaut (84 octets) et conclure que « le réseau marche ».
- Corriger en baissant la MTU des VMs : ça masque la cause, ça dégrade tout le reste, et la prochaine VM créée retombera dans le trou.
- Ne tester qu'un sens.
- Confondre avec les « gros paquets » qu'on voit dans une capture sur une interface de VM : avec GRO/TSO, tcpdump affiche des segments de plusieurs dizaines de Ko qui ne transitent jamais tels quels sur un lien (voir M00-E47, question 6).
- Considérer le MSS clamping comme la correction.

**En production chez MédiSphère**

Les MTU font partie de la conception réseau (module 07 : jumbo frames sur le réseau de stockage, tunnels, overlays Geneve/VXLAN d'OpenStack et de Kubernetes). Chaque overlay a sa MTU documentée, testée par un `ping -M do` automatisé après tout changement, et la politique ICMP est commune à tous les pare-feu.

---

### M00-E42 — Panne : la sauvegarde nocturne a échoué

**Démarche de diagnostic**

*Symptômes* : tâches `vzdump` vers `pbs-par2` en erreur, relance manuelle en erreur.

*Hypothèses*, par étage : **transport** (réseau, tunnel, TLS/empreinte), **authentification** (jeton, secret), **autorisation** (ACL du jeton et de l'utilisateur), **état du datastore** (maintenance, espace, namespace), **source** (VM verrouillée, snapshot impossible).

**Étape 1 — Lire l'erreur.**

```
root@pve01:~# pvesh get /nodes/$(hostname)/tasks --typefilter vzdump --errors 1 --limit 3
root@pve01:~# pvesh get /nodes/$(hostname)/tasks/<UPID>/log | grep -E 'ERROR|error|fail'
root@pve01:~# pvesm status --storage pbs-par2; pvesm list pbs-par2 | head -n 3
```

| Observation | V1 empreinte | V2 ACL | V3 maintenance | V4 namespace |
|---|---|---|---|---|
| `pvesm status` | inactif | inactif ou erreur de droits | actif | actif (à vérifier) |
| `pvesm list pbs-par2` | erreur TLS (empreinte non vérifiée) | refus de permission | OK | vide ou « namespace » introuvable |
| Journal `vzdump` | erreur de certificat / empreinte | `permission check failed` (ou 403) | datastore en maintenance (lecture seule) | namespace inexistant |

Les messages exacts dépendent des versions ; ce qui compte est l'**étage** qu'ils désignent. La lecture seule (`pvesm list`) qui fonctionne alors que l'écriture échoue (V3) élimine d'emblée transport, authentification et droits de lecture.

**Étape 2 — Confirmer côté PBS.** Le journal des tâches de PBS (interface web, *Tâches*) montre ou non les connexions de `pve01`. Puis :

```
root@pbs01:~# proxmox-backup-manager cert info | grep -i fingerprint
root@pbs01:~# proxmox-backup-manager datastore show ds-lab
root@pbs01:~# proxmox-backup-manager acl list
root@pbs01:~# proxmox-backup-manager user permissions 'wb-backup@pbs!pve01' --path /datastore/ds-lab/par1
root@pve01:~# awk '/^pbs: pbs-par2$/{f=1;next} /^[a-z]+: /{f=0} f' /etc/pve/storage.cfg
```

**Variante 1 — empreinte altérée.** L'empreinte de `storage.cfg` diffère de celle que donne `cert info` sur `pbs01`, sur le dernier octet seulement (copier-coller raté). Côté PBS, aucune tâche : la connexion TLS est refusée par le client avant toute requête.

> ⚠️ **Sécurité** : une empreinte qui ne correspond plus n'est **pas** un détail à « accepter » en cliquant. C'est exactement le symptôme d'une interception (homme du milieu). Compare toujours avec une valeur obtenue par un canal indépendant (console iLO de `hp01`, inventaire de M00-E50). Ici le certificat de PBS n'a pas changé : c'est la configuration du client qui a été modifiée.

```
root@pve01:~# pvesm set pbs-par2 --fingerprint <EMPREINTE-LUE-SUR-PBS01>
```

Bonus : la sauvegarde de configuration de l'hyperviseur (M00-E30) permet de prouver quand `storage.cfg` a changé (diff entre deux instantanés).

**Variante 2 — ACL retirées.** `acl list` ne contient plus aucune entrée pour `wb-backup@pbs` ni pour son jeton ; `user permissions` est vide sur le chemin du namespace. Côté PBS, les tentatives de `pve01` apparaissent comme refusées. Rétablir **exactement** les droits de M00-E22 (rôle `DatastoreBackup`, sur le chemin choisi alors), pour l'utilisateur et pour le jeton : avec la séparation des privilèges, les droits effectifs d'un jeton sont l'intersection des siens et de ceux de l'utilisateur.

```
root@pbs01:~# proxmox-backup-manager acl update /datastore/ds-lab/par1 DatastoreBackup --auth-id 'wb-backup@pbs'
root@pbs01:~# proxmox-backup-manager acl update /datastore/ds-lab/par1 DatastoreBackup --auth-id 'wb-backup@pbs!pve01'
root@pbs01:~# proxmox-backup-manager user permissions 'wb-backup@pbs!pve01' --path /datastore/ds-lab/par1
```

Tentation à refuser : donner `DatastoreAdmin` ou `Admin` « pour que ça marche ». Le jeton de sauvegarde ne doit ni purger ni supprimer (protection contre un `pve01` compromis qui effacerait ses propres sauvegardes : c'est tout l'intérêt d'un site PAR2).

**Variante 3 — maintenance en lecture seule.**

```
root@pbs01:~# proxmox-backup-manager datastore show ds-lab | grep -i maintenance
│ maintenance-mode │ type=read-only │
```

Avant de lever le mode, **demande pourquoi il a été posé** : une maintenance réelle (remplacement de disque, vérification de système de fichiers) peut être en cours. Ici, personne ne la revendique :

```
root@pbs01:~# proxmox-backup-manager datastore update ds-lab --delete maintenance-mode
```

**Variante 4 — namespace inexistant.** `storage.cfg` indique `namespace par1-prod`. Sur PBS, seul `par1` existe (`proxmox-backup-client namespace list` avec les identifiants du stockage, ou l'interface). Un changement de namespace se prépare (créer le namespace côté PBS, adapter les jobs de purge et de vérification, décider du sort des anciennes sauvegardes) : ici, rien n'a été préparé. Retour à `par1` :

```
root@pve01:~# pvesm set pbs-par2 --namespace par1
```

**Pour toutes les variantes** — relance et preuve :

```
root@pve01:~# vzdump 1002 --storage pbs-par2 --mode snapshot
root@pve01:~# pvesm list pbs-par2 --vmid 1002 | tail -n 2
```

Puis vérifie dans ta messagerie (ou ta cible de notification, M00-E29) que le succès a été notifié.

**Vérification** : `lab/bin/check 00 42`.

**Prévention**
- Superviser l'**âge de la dernière sauvegarde réussie** par VM (et non seulement les échecs) : un job désactivé ou supprimé n'envoie aucun échec.
- Alerte côté PBS sur un datastore en maintenance depuis plus de N heures.
- Diff quotidien de `/etc/pve/storage.cfg` et des ACL PBS (sauvegardes de configuration de M00-E30 + comparaison).
- Runbook « sauvegarde en échec » : tableau message → étage → commande de confirmation → correctif (c'est le « pour aller plus loin » de l'énoncé, à verser au dossier de M00-E50).

**Explications**

`pve01` parle à PBS via HTTPS (port 8007). Avant toute requête, le client vérifie le certificat : soit par une chaîne de confiance (certificat signé par une autorité connue), soit par **épinglage** de l'empreinte SHA-256 (cas du certificat auto-signé de PBS). Puis il s'authentifie par jeton (`wb-backup@pbs!pve01` + secret dans `/etc/pve/priv/storage/pbs-par2.pw`). PBS vérifie ensuite les privilèges sur le chemin ACL du datastore et du namespace (`/datastore/ds-lab/par1`), puis l'état du datastore (le mode maintenance bloque les nouvelles écritures, ou tout accès en mode `offline`). Chaque variante casse un de ces étages, et le message d'erreur dit lequel.

**Alternatives**
- `proxmox-backup-client` en ligne de commande avec les paramètres du stockage (`PBS_REPOSITORY`, `PBS_FINGERPRINT`, `PBS_PASSWORD` lus depuis `storage.cfg` et le fichier `.pw`), pour reproduire hors de `vzdump`. Attention à ne pas laisser le secret dans l'historique du shell.
- Interface PBS : *Configuration → Accès → Permissions* pour visualiser les droits effectifs.

**Pièges classiques**
- Relancer la sauvegarde complète à chaque essai (10 minutes perdues par hypothèse) au lieu de tester l'étage avec `pvesm list`.
- Accepter une nouvelle empreinte sans la vérifier.
- Élargir les droits du jeton.
- Lever un mode maintenance sans demander pourquoi il existe.
- Oublier de relancer une sauvegarde après correction : la nuit sans sauvegarde reste un trou dans le RPO.

**En production chez MédiSphère**

La sauvegarde est un contrôle de conformité HDS : chaque échec ouvre un ticket, chaque nuit sans sauvegarde valide est consignée, et un test de restauration périodique (M00-E37, M00-E50) prouve que les sauvegardes sont exploitables. Les identifiants de sauvegarde sont propres à chaque client (un jeton par hyperviseur), sans droit de suppression.

---

### M00-E43 — Panne : le site PAR2 est injoignable

**Démarche de diagnostic**

*Symptômes* : `pbs-par2` grisé, `ssh pbs01` sans réponse ; `hp01` allumé et sain d'après l'iLO.

*Hypothèses* : `hp01` hors réseau (LAN) ; transport UDP entre `<IP-GW01-WAN>` et `<IP-HP01-LAN>` (filtrage sur l'une des extrémités) ; clés ; routage par clé (`AllowedIPs`) ; routes système ; service PBS.

**Étape 1 — État du tunnel sur `gw01`.**

```
admin@gw01:~$ sudo wg show wg0
admin@gw01:~$ ping -c 2 <IP-HP01-LAN>          # le LAN maison, hors tunnel
admin@gw01:~$ ping -c 2 10.255.0.2             # l'autre extrémité du tunnel
admin@gw01:~$ ping -c 2 10.20.10.10            # le réseau PAR2 derrière
```

| Observation | V1 clé publique | V2 AllowedIPs | V3 UDP/51820 filtré |
|---|---|---|---|
| `<IP-HP01-LAN>` | OK | OK | OK |
| `latest handshake` | absent | récent (< 2 min) | de plus en plus ancien |
| `transfer` | reçu stagne | reçu augmente | reçu stagne |
| `10.255.0.2` | KO | **OK** | KO |
| `10.20.10.10` | KO | **`Required key not available`** | KO |
| clé du pair affichée | ≠ clé de `pbs01` | = | = |

`hp01` répond sur le LAN : la machine et le réseau physique vont bien.

**Étape 2 — Observer le transport.**

```
admin@gw01:~$ sudo tcpdump -c 12 -ni ens18 udp port 51820
```

Tailles utiles UDP à connaître : **148** octets = initiation de poignée de main, **92** = réponse, **32** = *keepalive* (données vides chiffrées).
- *Variante 1* : des initiations de 148 octets dans les deux sens, toutes les 5 secondes environ, **jamais** de réponse de 92 octets. Chaque extrémité tente d'établir la session et l'autre refuse : l'une des deux ne reconnaît pas la clé de l'autre.
- *Variante 3* : les paquets de `hp01` **arrivent** sur `ens18` (tcpdump capture avant le pare-feu) mais `wg show` n'en voit aucun effet : quelque chose les jette localement entre la carte et WireGuard. Le compteur le confirme :

```
admin@gw01:~$ sudo nft list chain inet filter input | head -n 4
		udp dport 51820 counter packets 37 bytes 4736 drop
```

**Étape 3 — Comparer les clés (variante 1)** depuis la console iLO de `hp01` :

```
root@pbs01:~# wg show wg0 public-key          # clé publique de pbs01
root@pbs01:~# wg show wg0 peers               # clé de gw01 telle que pbs01 la connaît
admin@gw01:~$ sudo wg show wg0 public-key; sudo wg show wg0 peers
```

La clé déclarée pour le pair dans le `wg0.conf` de `gw01` n'est pas la clé publique de `pbs01`. On ne compare **que des clés publiques** : jamais `wg showconf` (qui affiche la clé privée) dans un ticket, un chat ou un journal.

**Étape 4 — Variante 2 : le tunnel est établi, mais quoi passe dedans ?**

```
admin@gw01:~$ sudo wg show wg0 allowed-ips
<clé-pbs01>	10.255.0.2/32
admin@gw01:~$ ip route get 10.20.10.10
10.20.10.10 dev wg0 src 10.255.0.1 uid 1000
```

La route système envoie 10.20.10.10 dans `wg0`, mais aucun pair n'a 10.20.10.10 dans ses `AllowedIPs` : WireGuard ne sait pas à qui chiffrer le paquet et le refuse (`ENOKEY`, « Required key not available »). En réception, il jetterait aussi tout paquet venant de 10.20.10.10 (source non autorisée pour ce pair). Le fichier `wg0.conf` a été modifié (10.20.0.0/16 retiré) et appliqué par `wg syncconf`, qui ne touche pas aux routes : d'où l'incohérence route/AllowedIPs.

**Correctifs**

```
admin@gw01:~$ sudoedit /etc/wireguard/wg0.conf     # V1 : PublicKey = clé publique de pbs01 ; V2 : AllowedIPs = 10.255.0.2/32, 10.20.0.0/16
admin@gw01:~$ sudo bash -c 'wg syncconf wg0 <(wg-quick strip wg0)'
admin@gw01:~$ sudo nft -c -f /etc/nftables.conf && sudo systemctl reload nftables    # V3
```

`wg syncconf` applique les différences sans couper les sessions existantes (contrairement à `systemctl restart wg-quick@wg0`). La syntaxe `<(…)` exige bash, d'où le `bash -c`.

Puis toute la chaîne : `ping 10.20.10.10`, `pvesm status --storage pbs-par2`, `chronyc sources` sur `pbs01` (son NTP passe par le tunnel), une sauvegarde manuelle de `dns01`.

**Pourquoi un `Endpoint` faux sur une seule extrémité est souvent sans effet** : WireGuard met à jour l'adresse de son pair à partir de la source du **dernier paquet authentifié** reçu (*roaming*). Ici, les deux extrémités ont un `Endpoint` et `PersistentKeepalive = 25` : si `gw01` a un mauvais endpoint pour `pbs01`, `pbs01` continue de joindre `gw01` à la bonne adresse, `gw01` authentifie ses paquets et corrige de lui-même l'endpoint en mémoire. La panne devient bloquante si les deux extrémités sont fausses, si l'extrémité correcte n'émet rien (pas de keepalive, pas de trafic), si un filtrage ou un NAT n'autorise qu'un sens, ou après un redémarrage de l'extrémité fausse pendant que l'autre est silencieuse. C'est pour cela que le script ne propose pas cette variante : elle se « répare » en moins de 30 secondes. Elle laisse pourtant une dette : le fichier reste faux et la panne réapparaîtra au pire moment.

**Vérification** : `lab/bin/check 00 43`.

**Prévention**
- Supervision du tunnel : âge de la dernière poignée de main (< 180 s avec un keepalive de 25 s) et progression des octets reçus. Une poignée de main récente ne suffit pas (variante 2) : ajoute une sonde **à travers** le tunnel (ping 10.20.10.10, TCP/8007).
- Inventaire des clés **publiques** de chaque extrémité (M00-E50), pour comparer sans accès à l'autre site.
- Configuration WireGuard générée à partir d'une source unique (module 04), cohérence routes/AllowedIPs testée.

**Explications**

Le *cryptokey routing* associe à chaque pair une liste de préfixes. **En émission**, après la décision de routage du noyau (qui envoie le paquet dans `wg0`), WireGuard choisit le pair dont un préfixe de `AllowedIPs` contient la destination (préfixe le plus long). **En réception**, après déchiffrement, il n'accepte le paquet que si sa source est dans les `AllowedIPs` du pair qui l'a chiffré. La table de routage et `AllowedIPs` sont deux mécanismes distincts : `wg-quick` crée des routes à partir de `AllowedIPs` au démarrage, mais `wg syncconf` ne les met pas à jour.

La poignée de main (Noise IK) repose sur la clé publique du répondeur, connue à l'avance de l'initiateur : un initiateur qui chiffre vers une mauvaise clé publique produit un message que le répondeur ne peut pas authentifier, il l'ignore silencieusement. WireGuard ne répond jamais à un paquet non authentifié : d'où l'absence totale de message d'erreur.

**Alternatives**
- `dmesg` avec la journalisation dynamique de WireGuard (`echo module wireguard +p > /sys/kernel/debug/dynamic_debug/control`, si debugfs est disponible) : messages explicites sur les poignées de main refusées. Volumineux, à désactiver ensuite.
- Sur `pbs01`, le même diagnostic en miroir : quand une seule extrémité est fausse, l'autre raconte souvent la moitié manquante de l'histoire.

**Pièges classiques**
- Redémarrer `wg-quick@wg0` : remet la route et la configuration du fichier… donc la panne si le fichier est faux, et coupe tout pendant ce temps.
- Coller une clé privée dans un ticket en voulant comparer les configurations.
- Croire le tunnel sain parce que `latest handshake` est récent (variante 2).
- Chercher sur `hp01` alors que la panne est sur `gw01` : commence toujours par l'extrémité que tu administres le plus facilement, mais vérifie les deux.

**En production chez MédiSphère**

Le lien PAR1-PAR2 portera la réplication, les sauvegardes et le quorum (QDevice, module 09) : il sera doublé (deux tunnels, deux chemins), supervisé de bout en bout, et toute modification passera par un changement planifié avec procédure de retour arrière testée.

---

### M00-E44 — Panne : une VM refuse de démarrer

**Démarche de diagnostic**

*Symptôme* : `qm start 5044` échoue.

*Hypothèses*, de la plus administrative à la plus matérielle : verrou sur la VM ; configuration invalide ; stockage indisponible ou désactivé ; volume absent ; ressources de l'hôte insuffisantes (mémoire, hugepages) ; périphérique absent (PCI, ISO) ; erreur de QEMU.

**Étape 1 — Lire l'erreur exacte et sauvegarder la configuration.**

```
root@pve01:~# qm start 5044
root@pve01:~# cp /etc/pve/qemu-server/5044.conf /root/5044.conf.$(date +%F-%H%M%S)
root@pve01:~# qm config 5044
```

Les quatre variantes donnent quatre messages très différents (formulations indicatives) :

| Variante | Message de `qm start` | Couche |
|---|---|---|
| 1 | `VM is locked (backup)` | Proxmox (verrou) |
| 2 | `storage 'sbx-store' is disabled` | Proxmox (stockage) |
| 3 | `kvm: cannot set up guest memory 'pc.ram': Cannot allocate memory` puis `start failed: QEMU exited with code 1` | Hôte / QEMU |
| 4 | `volume 'sbx-store:5044/vm-5044-disk-10.qcow2' does not exist` | Proxmox (stockage / configuration) |

La première chose à faire est donc… de lire le message en entier, y compris dans le journal de la tâche (interface web) quand l'erreur est longue.

**Variante 1 — verrou résiduel.**

```
root@pve01:~# qm config 5044 | grep ^lock
lock: backup
root@pve01:~# pgrep -af vzdump; pvesh get /cluster/tasks --output-format json | grep -c '"status"'
```

Un verrou `backup` protège la VM pendant une sauvegarde. **Avant** de le retirer, vérifie qu'aucune sauvegarde n'est en cours pour 5044 (processus `vzdump`, tâche active dans l'interface, tâche en cours côté PBS). Un verrou résiduel apparaît quand le processus qui l'a posé est mort sans le retirer (arrêt brutal de l'hôte, `kill`, perte de la connexion vers le stockage de sauvegarde). Ici, aucune tâche :

```
root@pve01:~# qm unlock 5044
```

**Variante 2 — stockage désactivé.**

```
root@pve01:~# pvesm status | grep sbx-store
root@pve01:~# grep -A4 '^dir: sbx-store' /etc/pve/storage.cfg
dir: sbx-store
	path /…/sbx-store
	content images
	disable
```

Un stockage désactivé n'est plus activé par Proxmox : impossible d'y démarrer, migrer ou sauvegarder une VM (les VMs déjà démarrées continuent de tourner, ce qui rend la panne invisible jusqu'au prochain démarrage). Avant de le réactiver, vérifie pourquoi il a été désactivé et que son support est bien présent (montage, pool ZFS) :

```
root@pve01:~# findmnt -T "$(awk '/^dir: sbx-store/{f=1} f && $1=="path"{print $2; exit}' /etc/pve/storage.cfg)"
root@pve01:~# pvesm set sbx-store --disable 0
```

**Variante 3 — mémoire impossible à allouer.**

```
root@pve01:~# qm config 5044 | grep -E '^(memory|balloon)'
memory: 393216
balloon: 0
root@pve01:~# free -g; sysctl vm.overcommit_memory
```

La VM demande trois fois la RAM physique de l'hôte. Avec `vm.overcommit_memory=0` (heuristique, valeur par défaut), le noyau refuse une allocation manifestement impossible, et QEMU échoue en réservant la mémoire du *guest*. Correctif : une valeur cohérente avec l'usage (la VM sandbox du template : 2 Gio) et le ballooning d'origine :

```
root@pve01:~# qm set 5044 --memory 2048 --delete balloon
```

Variante voisine que tu rencontreras : `hugepages: 1024` sur une VM sans pages énormes réservées sur l'hôte, ou NUMA mal déclaré ; le message pointe alors la réservation de pages.

**Variante 4 — volume inexistant.**

```
root@pve01:~# qm config 5044 | grep -E '^(scsi|virtio|sata|ide)[0-9]'
scsi0: sbx-store:5044/vm-5044-disk-10.qcow2,discard=on,…
root@pve01:~# pvesm list sbx-store --vmid 5044
Volid                                  Format  Type     Size VMID
sbx-store:5044/vm-5044-cloudinit.qcow2 qcow2   images    …   5044
sbx-store:5044/vm-5044-disk-0.qcow2    qcow2   images    …   5044
```

La configuration pointe vers `disk-10`, le stockage contient `disk-0`. Deux corrections propres :
- éditer la ligne `scsi0` (après la copie de sauvegarde de l'étape 1) pour remettre le bon nom de volume, en conservant toutes les options ;
- ou `qm rescan --vmid 5044`, qui ajoute le volume réel en `unused0`, puis rattacher ce volume en `scsi0` avec les mêmes options.

> ⚠️ **Attention** : supprimer une ligne `unusedN` avec `qm set 5044 --delete unused0` (ou le bouton *Remove* sur un disque inutilisé) **détruit le volume**. Ne supprime jamais un disque « inutilisé » sans avoir vérifié qu'il n'est référencé nulle part et que tu n'en as pas besoin.

Vérifie ensuite l'ordre de démarrage (`boot: order=scsi0`) et démarre.

**Pour toutes les variantes** :

```
root@pve01:~# qm start 5044 && qm status 5044
admin@adm01:~$ ssh sbx44 hostname        # une fois l'adresse DHCP du VLAN 99 connue (dnsmasq de dns01)
```

**Nettoyage** (étape 5 de l'énoncé, après la vérification) :

```
root@pve01:~# qm stop 5044; qm destroy 5044 --purge 1 --destroy-unreferenced-disks 1
root@pve01:~# pvesm list sbx-store            # doit être vide
root@pve01:~# pvesm remove sbx-store          # retire la définition, pas les données
```

Puis supprime le répertoire (ou le dataset ZFS `…/sbx-store`) créé pour l'exercice, après avoir vérifié son chemin exact et qu'il est vide.

> ⚠️ **Attention** : `pvesm remove` ne supprime aucune donnée ; un `rm -r` ou un `zfs destroy` sur un mauvais chemin, si. Relis le chemin deux fois.

**Vérification** : `lab/bin/check 00 44` (avant le nettoyage ; après, le contrôle est ignoré).

**Prévention**
- Alerte sur les verrous anciens (une VM verrouillée depuis plus de quelques heures) et sur les stockages désactivés.
- Validation des modifications de configuration par l'API (qui contrôle les valeurs) plutôt que par édition directe de `/etc/pve` ; IaC (module 05) avec plan relu.
- Garde-fou de capacité : la somme des mémoires configurées des VMs démarrées est suivie (plan de capacité de M00-E50).

**Explications**

Le démarrage d'une VM Proxmox enchaîne : lecture et validation de la configuration (pmxcfs) → vérification des verrous → activation des stockages et des volumes → construction de la ligne de commande QEMU (`qm showcmd 5044 --pretty` l'affiche) → lancement de QEMU → allocation de la mémoire et ouverture des disques par QEMU. Les variantes 1, 2 et 4 échouent dans Proxmox, avant QEMU ; la variante 3 échoue dans QEMU, ce qui se reconnaît au préfixe `kvm:` du message.

Les verrous Proxmox (`backup`, `migrate`, `snapshot`, `snapshot-delete`, `clone`, `create`, `rollback`, `suspended`…) sont des marqueurs dans la configuration, pas des verrous du système : ils survivent à la mort du processus qui les a posés.

**Alternatives**
- `qm start 5044 --skiplock` : démarre malgré un verrou, réservé à `root@pam`. À éviter : le verrou existe pour une raison, et `qm unlock` documente mieux l'intention.
- Lire les tâches de l'hôte : `journalctl -u pvedaemon --since -15min`.

**Pièges classiques**
- `qm unlock` réflexe pendant une vraie sauvegarde en cours.
- Supprimer un disque `unused` (perte de données).
- Recréer un disque vide « pour que ça démarre ».
- Augmenter la mémoire de l'hôte en swap pour faire passer la variante 3.

**En production chez MédiSphère**

Les VMs sont décrites en IaC : une configuration incohérente est corrigée en réappliquant le code, pas à la main. Les verrous résiduels et les stockages désactivés sont des alertes. Le démarrage automatique des VMs critiques est testé lors de chaque maintenance de l'hyperviseur (module 09).

---

### M00-E45 — Panne : horloges désynchronisées

**Démarche de diagnostic**

*Symptôme* : journaux de `dns01` en avance d'environ 10 minutes.

*Hypothèses* : client NTP de `dns01` arrêté ; source injoignable (réseau, filtrage) ; source qui refuse de répondre ; source elle-même fausse ; horloge forcée manuellement.

**Étape 1 — Mesurer.**

```
admin@adm01:~$ for h in gw01 dns01; do printf '%s ' "$h"; ssh "$h" date +%s.%N; done; date +%s.%N
admin@gw01:~$  chronyc -n tracking | grep -E 'Reference|System time|Leap'
admin@dns01:~$ chronyc -n tracking; chronyc -n sources -v
```

`gw01` et `adm01` sont à l'heure (écart de quelques millisecondes avec les serveurs du pool) ; `dns01` a environ 600 secondes d'avance. Puis :

| Observation sur `dns01` / `gw01` | V1 | V2 | V3 |
|---|---|---|---|
| `chronyc tracking` sur `dns01` | `506 Cannot talk to daemon` | répond | répond |
| `systemctl is-active chrony` (`dns01`) | `inactive` (et `disabled`) | `active` | `active` |
| `chronyc sources` (`dns01`) | — | `^? 10.10.20.1`, `Reach` qui décroît vers 0 | `^? 10.10.20.1`, `Reach` qui décroît vers 0 |
| `nft list chain inet filter input` (`gw01`) | normal | `udp dport 123 counter … drop` en tête | normal |
| `chronyc accheck 10.10.20.10` (`gw01`) | `allowed` | `allowed` | `Access denied` |
| `chronyc serverstats` (`gw01`) | — | paquets NTP reçus stables | paquets NTP **jetés** (*dropped*) en hausse |

La colonne `Reach` est un registre à décalage en octal des 8 dernières interrogations : `377` = 8 réponses sur 8, `0` = aucune. Une source qui ne répond plus voit son `Reach` décroître à chaque interrogation (tous les 64 à 1024 s selon le *poll*) : la panne n'est pas visible tout de suite, et touche en réalité **tous** les clients de `gw01` en variantes 2 et 3 (seul `dns01` avait été décalé, mais `adm01` dérive aussi, lentement).

**Causes et correctifs**

*Variante 1* — client arrêté et désactivé :

```
admin@dns01:~$ sudo systemctl enable --now chrony
```

*Variante 2* — NTP filtré sur `gw01` (règle en tête de `input`, avant l'autorisation NTP du lab) : suppression par handle ou rechargement du fichier.

*Variante 3* — `gw01` ne sert plus le temps : les directives `allow` ont disparu de `/etc/chrony/conf.d/10-serveur-lab.conf` (M00-E31). Rétablir le fichier, puis redémarrer (une directive `allow` du fichier est lue au démarrage ; `chronyc allow` agirait à chaud mais serait perdu au redémarrage suivant) :

```
admin@gw01:~$ sudoedit /etc/chrony/conf.d/10-serveur-lab.conf
admin@gw01:~$ sudo systemctl restart chrony && sudo chronyc accheck 10.10.20.10
```

**Ramener `dns01` à l'heure.** Une fois la source joignable, chrony ne corrige pas forcément d'un coup : la directive Debian `makestep 1 3` n'autorise un saut que pendant les trois premières mises à jour après le démarrage du service. Au-delà, il ralentit ou accélère l'horloge (*slew*) au plus de 83 ms par seconde (`maxslewrate` par défaut, à vérifier) : rattraper 600 s prendrait environ 2 heures, pendant lesquelles les journaux restent faux. Deux méthodes :

```
admin@dns01:~$ sudo chronyc makestep          # saut immédiat, service en marche
admin@dns01:~$ sudo systemctl restart chrony  # ou : redémarrage, makestep s'applique aux premières mesures
admin@dns01:~$ chronyc tracking | grep 'System time'
```

Un saut **en arrière** de 10 minutes n'est pas anodin : horodatages de journaux qui « remontent le temps », baux DHCP et caches calculés sur l'horloge murale, tâches planifiées rejouées. Sur `dns01` (service sans état durable, fenêtre courte), le saut est le bon choix ; annonce-le dans le ticket pour que Nadia sache que les journaux de la plage concernée sont décalés. Sur une base de données, on préfère souvent le *slew* ou un arrêt applicatif pendant le saut.

**Conséquences d'un décalage de 10 minutes dans le socle** (étape 4) : corrélation de journaux impossible (traçabilité HDS) ; certificats TLS jugés « pas encore valides » ou expirés selon le sens (futur PKI step-ca, module 06) ; codes TOTP refusés (fenêtre de 30 s) ; tickets d'authentification et jetons à durée de vie (PVE, PBS, JWT, OIDC au module 24) rejetés ; horodatage et ordre des sauvegardes faussés si c'est l'hôte qui sauvegarde qui est décalé ; tâches planifiées exécutées au mauvais moment ; Kerberos (5 min de tolérance) cassé ; avertissements de décalage d'horloge des systèmes distribués (Ceph alerte au-delà de 0,05 s, module 08 ; etcd, module 14).

**Vérification** : `lab/bin/check 00 45`.

**Prévention**
- Supervision de l'écart et de l'état de synchronisation de chaque machine (métriques `timex` de node_exporter, module 21), alerte au-delà de 100 ms ou si non synchronisé depuis 30 min.
- `chrony` activé et contrôlé par la gestion de configuration ; flux NTP dans la matrice (M00-E50).
- Deux sources pour les clients critiques (passerelle + une seconde source interne) quand le socle aura plusieurs serveurs de temps.

**Explications**

chrony mesure l'écart avec ses sources, filtre, choisit la meilleure (`^*`) et discipline l'horloge système par petites corrections de fréquence ; il ne « met pas à l'heure » brutalement, sauf dans les conditions de `makestep`. Sur une VM, l'horloge `kvm-clock` est stable mais dérive légèrement : sans NTP, l'écart grandit de quelques secondes par jour. Un `date -s` manuel produit un saut que rien ne corrige si le client NTP ne peut pas joindre sa source : c'est ce qu'a vécu `dns01`. Côté serveur, chrony ne répond qu'aux clients autorisés par `allow` : un client non autorisé n'obtient **aucune** réponse (et non un refus explicite), d'où le même symptôme qu'un filtrage réseau. `chronyc accheck` et `serverstats` font la différence.

**Alternatives**
- `chronyc ntpdata 10.10.20.1` sur le client : détail des derniers échanges (paquets envoyés, reçus).
- `tcpdump -ni ens19.20 udp port 123` sur `gw01` : requêtes reçues sans réponse (variante 3) contre requêtes jetées avant d'être vues par chrony (variante 2, visibles dans tcpdump mais compteur nftables en hausse).

**Pièges classiques**
- Corriger l'heure avec `date -s` sans réparer la synchronisation : le problème revient.
- Ignorer que la panne de serveur (V2, V3) touche tous les clients, pas seulement celui qui est visible.
- Toucher à l'horloge de `pve01` « pour tester » : toutes les VMs, PBS et le cluster en dépendent.
- Oublier `systemctl enable` en variante 1 : la panne revient au redémarrage.

**En production chez MédiSphère**

Le temps est une dépendance de sécurité. Deux serveurs NTP internes au moins, synchronisés sur des sources diversifiées (et, pour une exigence forte de traçabilité, une source GPS ou NTS), supervisés ; les écarts sont des alertes de priorité haute ; les horodatages des journaux sont centralisés (module 22) avec l'heure de réception en plus de l'heure d'émission.

---

### M00-E46 — Astreinte : pannes multiples

**Démarche de diagnostic**

La difficulté n'est pas technique (chaque panne a été traitée dans son exercice) : elle est **méthodologique**. Deux pannes simultanées produisent des symptômes qui se recouvrent, et une panne peut en masquer une autre.

**1. Triage (10 minutes maximum).** Liste brute des symptômes, puis pour chacun : impact métier, couche probable, dépendances. Exemple de tableau (paire E43 variante 2 + E42 variante 3) :

| Symptôme | Impact | Couche | Dépend de |
|---|---|---|---|
| `pbs-par2` grisé | plus de sauvegarde ni de restauration hors site | tunnel ou PBS | réseau PAR1-PAR2 |
| Sauvegarde de la nuit en erreur | RPO dégradé (> 24 h) | PBS ou chemin | `pbs-par2` joignable |

Hypothèse de regroupement : une cause unique (tunnel) expliquerait les deux symptômes. C'est l'hypothèse la plus économique… et la plus dangereuse si elle est fausse.

**2. Ordre de traitement.** Restaure d'abord tes **instruments** : accès SSH à chaque hôte, routage, DNS, tunnel. Tant qu'ils sont cassés, tous tes autres tests mentent. Ordre typique : accès de secours → routage/NAT (E38) → joignabilité des VMs (E39) → DNS (E40) → tunnel (E43) → MTU (E41) → services (E42, E44) → temps (E45). Le temps est traité en dernier sauf s'il casse l'authentification (ce n'est pas le cas ici : `pve01` n'est jamais décalé).

**3. Le piège central : la panne masquée.** Après chaque correction, **rejoue l'intégralité des tests du triage**, pas seulement celui que tu viens de réparer. Cas typiques de masquage :

| Paire | Ce qu'on voit d'abord | Ce qui reste caché |
|---|---|---|
| E43 + E42 | PAR2 injoignable : la sauvegarde échoue, « logique » | une fois le tunnel réparé, la sauvegarde échoue **encore** (ACL, maintenance, empreinte ou namespace) |
| E38 (V1) + E39 | `ip_forward=0` : `dns01` injoignable depuis `adm01`, « c'est le routage » | une fois le routage rétabli, `dns01` reste injoignable (VNet, pare-feu de VM ou masque) |
| E38 + E40 | plus de récursion DNS (amont injoignable) | une fois Internet rétabli, la résolution échoue encore (dnsmasq arrêté, client détourné, UDP filtré) ; le test « nom interne » les distingue dès le départ |
| E41 (V2) + E42 | sauvegarde bloquée (trou PMTU dans `wg0`) | après la MTU, la sauvegarde échoue franchement (autre étage) |
| E39 + E45 | `dns01` injoignable : impossible de voir son heure | une fois joignable, son horloge est fausse |

Inversement, une correction peut faire **apparaître** un symptôme : il était masqué par la première panne. Ce n'est pas ta correction qui l'a créé ; vérifie-le avant de revenir en arrière.

Les contrôles `lab/bin/check 00 38` à `00 45` sont d'excellentes sondes de triage : lance-les tous au début (carte de ce qui est rouge), puis après chaque correction.

**4. Une modification à la fois**, horodatée dans le journal : la chronologie du post-mortem s'écrit pendant l'incident, pas après.

**5. Communication.** Trois messages au minimum. Exemples :

> **[INC-2620] 07:40 — En cours.** Impact : plus de sauvegarde hors site depuis 02:10 (PAR2 injoignable), aucune perte de données, services du socle PAR1 opérationnels. Cause en cours d'analyse côté tunnel PAR1-PAR2. Prochain point : 08:10.

> **[INC-2620] 08:10 — Partiellement rétabli.** Tunnel PAR1-PAR2 rétabli à 07:58 (erreur de configuration du pair). La sauvegarde échoue encore pour une seconde cause, côté PBS, en cours de correction. Prochain point : 08:40.

> **[INC-2620] 08:35 — Résolu.** Sauvegarde manuelle de dns01, gw01 et adm01 réussie à 08:31. Surveillance renforcée jusqu'au job de cette nuit. Post-mortem diffusé demain.

**6. Post-mortem.** Un exemple complet est fourni : [`fichiers/M00-E46/post-mortem-exemple.md`](fichiers/M00-E46/post-mortem-exemple.md) (paire E43 V2 + E42 V3). Points d'évaluation :

| Critère | Attendu |
|---|---|
| Sans recherche de coupable | faits et mécanismes, pas de « X a fait une erreur » |
| Chronologie | horodatée, sources citées, de la première alerte au retour à la normale, hypothèses écartées comprises |
| Causes | **deux** causes racines distinctes, chacune prouvée par une commande et sa sortie ; facteurs contributifs (modifications à chaud non tracées, supervision incomplète) |
| Détection | délai de détection, ce qui aurait permis de détecter avant l'utilisateur |
| Actions | concrètes, chacune typée (prévenir / détecter / atténuer), avec responsable et échéance ; pas de « faire attention » |
| Masquage | le document explique comment la seconde panne était masquée et comment elle a été découverte |

**Annulation** si nécessaire : `lab/bin/break 00 46 --annuler`.

**Vérification** : `lab/bin/check 00 46` (rejoue les contrôles de E38 à E45 et vérifie la présence du post-mortem).

**Explications**

En incident, le cerveau cherche **une** histoire qui explique tout. La méthode (triage écrit, rejouer tous les tests après chaque correction, une modification à la fois) est un garde-fou contre ce biais. Le post-mortem *blameless* part du principe que les personnes ont agi raisonnablement avec l'information dont elles disposaient : on corrige le système (outils, processus, supervision) qui a permis l'erreur, sinon l'erreur se reproduira avec quelqu'un d'autre.

**Alternatives**
- Rôles séparés en incident réel : un *incident commander* qui coordonne et communique, un ou plusieurs intervenants techniques. Seul en astreinte, tu tiens les deux rôles : d'où l'importance du rythme de communication fixé à l'avance.

**Pièges classiques**
- Corriger la première cause trouvée, constater une amélioration, déclarer l'incident résolu.
- Annuler une bonne correction parce qu'un nouveau symptôme est apparu.
- Changer trois choses à la fois : impossible de savoir laquelle a agi.
- Rédiger le post-mortem de mémoire, le lendemain, sans journal.

**En production chez MédiSphère**

Nadia tient le processus : niveaux de priorité, rythme de communication par priorité, canal d'incident dédié, post-mortem obligatoire pour toute P1/P2 dans les 5 jours ouvrés, revue des actions en réunion hebdomadaire. Le workbook final F3 (« semaine d'astreinte ») reprend ce format à plus grande échelle.

---

### M00-E47 — Suivre un paquet de bout en bout

**Solution**

Un compte rendu de référence est fourni : [`fichiers/M00-E47/trace-paquet-exemple.md`](fichiers/M00-E47/trace-paquet-exemple.md), avec le script de table de traçage temporaire [`fichiers/M00-E47/nft-trace.sh`](fichiers/M00-E47/nft-trace.sh). Les points clés :

**1. Chaîne côté hyperviseur.** Après M00-E28, `qm config 1001` affiche `net0: virtio=…,bridge=vmgmt`. Ce que Proxmox construit réellement dépend de la version de `pve-network` ; deux topologies sont possibles et **seules tes sorties tranchent** :

- *Topologie A* : `ip -d link show tap1001i0` indique `master vmbr1` et `bridge vlan show dev tap1001i0` montre `10 PVID Egress Untagged`. Le VNet est un nom logique : le tap est branché directement sur le bridge VLAN-aware avec l'étiquette du VNet.
- *Topologie B* : `tap1001i0` a pour maître le bridge `vmgmt`, lui-même relié à `vmbr1` par une interface créée par la zone SDN : avec un `vmbr1` VLAN-aware, le code actuel de `pve-network` utilise la sous-interface VLAN du bridge parent, `vmbr1.10` (port unique de `vmgmt`, qui étiquette 10 et remet la trame à `vmbr1` par son interface propre, entrée `self` de `bridge vlan show`) ; une paire veth `ln_`/`pr_` n'apparaît qu'avec un bridge parent non VLAN-aware. Lis `/etc/network/interfaces.d/sdn` pour trancher.

Dans les deux cas, le trunk de `gw01` (`tap1000i1`, carte `net1` sans étiquette) est membre de toutes les VLANs de `bridge-vids` (2-4094 par défaut) en mode étiqueté, plus la VLAN 1 en PVID non étiquetée.

Si le pare-feu Proxmox est actif sur la carte (`firewall=1`, moteur historique), on trouve en plus : `tap1001i0` → `fwbr1001i0` ← `fwln1001i0` ⇄ `fwpr1001p0` → bridge du VNet ou `vmbr1`.

**2. Captures couche 2.** Sur `tap1001i0`, trames **sans** étiquette, MAC source = carte de `adm01`, MAC destination = `ens19` de `gw01` (passerelle 10.10.10.1). Sur `tap1000i1`, les mêmes trames portent `ethertype 802.1Q (0x8100), vlan 10`. L'étiquette est ajoutée par le bridge à la sortie vers le port trunk.

**3. Côté routeur.** Sur `ens19` (parent) : trames étiquetées `vlan 10` ; sur `ens19.10` : le même paquet sans étiquette (retirée par le pilote 8021q) ; sur `ens18` : source = `<IP-GW01-WAN>`, MAC source = `ens18` de `gw01`, MAC destination = la box.

**4. Conntrack** (sortie représentative) :

```
tcp 6 431995 ESTABLISHED src=10.10.10.10 dst=151.101.2.132 sport=48712 dport=443 src=151.101.2.132 dst=192.168.1.50 sport=443 dport=48712 [ASSURED] mark=0 use=1
```

Protocole et numéro, durée de vie restante en secondes (5 jours par défaut pour une connexion TCP établie), état TCP, **tuple d'origine** (tel que vu à l'entrée), **tuple de réponse attendu** (ce que la réponse doit contenir : destination = adresse WAN de `gw01`, c'est la trace du NAT), `[ASSURED]` (trafic vu dans les deux sens, l'entrée ne sera pas évincée en priorité).

**5. Trace nftables.**

```
root@gw01:~# nft add table inet wbtrace
root@gw01:~# nft add chain inet wbtrace pre '{ type filter hook prerouting priority -350; }'
root@gw01:~# nft add rule inet wbtrace pre ip saddr 10.10.10.10 ip daddr 9.9.9.9 meta nftrace set 1
root@gw01:~# nft monitor trace
…
root@gw01:~# nft delete table inet wbtrace
```

La priorité -350 place la chaîne avant conntrack (-200) : le marquage est posé avant toute autre décision. Premier paquet (extrait représentatif, avec le fichier de référence de M00-E26) :

```
trace id 4f1c… inet filter forward rule ip saddr { 10.10.10.0/24, 10.255.1.0/24, 192.168.1.20 } icmp type echo-request accept (verdict accept)
trace id 4f1c… ip nat postrouting rule oifname "ens18" ip saddr 10.10.0.0/16 ip daddr != 192.168.1.20 masquerade comment "lab vers Internet et LAN maison" (verdict accept)
```

Paquets suivants : `inet filter forward rule ct state { established, related } accept (verdict accept)`, et **plus de passage** dans `ip nat postrouting`.

**Réponses aux questions d'analyse**

1. L'étiquette 10 est attribuée à l'**entrée** dans le bridge VLAN-aware, par le PVID du port de la VM (ou du port d'accès du VNet en topologie B) ; elle est **matérialisée** dans la trame à la sortie vers le port trunk de `gw01`, membre étiqueté de la VLAN 10. Elle disparaît dans `gw01` quand le pilote 8021q démultiplexe `ens19` vers `ens19.10`. Réglages en jeu : `PVID`/`Egress Untagged` du port VM, appartenance étiquetée du port trunk (`bridge vlan show`).
2. `gw01` **route** : il réécrit l'en-tête Ethernet pour le saut suivant. MAC source = `ens18`, MAC destination = celle de la passerelle par défaut de `gw01` (la box). `gw01` fait la résolution ARP de **l'adresse de sa passerelle**, jamais de 9.9.9.9, qui n'est pas sur un lien local.
3. Le tuple d'origine décrit le flux tel qu'il est entré ; le tuple de réponse décrit ce que la réponse **doit** porter après traduction (destination = adresse WAN de `gw01`). À l'arrivée d'un paquet de 151.101.2.132:443 vers `<IP-GW01-WAN>`:48712, conntrack trouve l'entrée par son tuple de réponse et applique la traduction inverse : la destination redevient 10.10.10.10:48712.
4. La chaîne `nat` n'est consultée que pour les paquets dont l'état conntrack est `NEW`. La décision (adresse et port de traduction) est enregistrée dans l'entrée conntrack et appliquée aux paquets suivants sans réévaluation. Conséquence : modifier une règle de NAT n'affecte pas les flux existants (voir le piège de M00-E38 V2).
5. Avec le moteur historique (iptables), `fwbr1001i0`, `fwln1001i0`, `fwpr1001p0` : un bridge dédié par carte, pour appliquer les règles iptables de la VM au trafic ponté (`br_netfilter`) indépendamment du bridge principal (qui peut être VLAN-aware ou OVS). Le moteur basé sur nftables (`proxmox-firewall`) filtre directement dans la famille `bridge` de nftables et n'a plus besoin de ces équipements (à vérifier selon ta version et le moteur choisi en M00-E27).
6. Délestages (*offloads*) : avec TSO/GSO, la pile TCP de la VM remet à virtio-net des segments jusqu'à 64 Kio, découpés plus tard (dans l'hôte, ou par la carte physique) ; en réception, GRO agrège des segments. tcpdump voit les tampons avant découpage ou après agrégation. Ce n'est pas un dépassement de MTU sur le fil.
7. Sur l'interface physique de `vmbr0` : le paquet **déjà traduit**, source `<IP-GW01-WAN>`, MAC source de `ens18` de `gw01` (adresse générée par Proxmox, préfixe `BC:24:11` par défaut), destination MAC de la box. Aucune étiquette (sauf si ton LAN maison est lui-même étiqueté).
8. Exemples : M00-E38 V2 (`tcpdump -ni ens18` : source privée qui sort sans NAT) ; M00-E39 V1 (`bridge vlan show` / `qm config` : mauvaise VLAN) ; M00-E41 (capture : retransmissions du même gros segment, aucun ICMP) ; M00-E43 V3 (`tcpdump -ni ens18 udp port 51820` : paquets reçus, compteur de drop qui monte).

**Explications**

Le chemin d'un paquet traverse trois mondes : le **pont** (bridge Linux de l'hôte : apprentissage MAC, filtrage VLAN), le **routeur** (`gw01` : décision de routage, netfilter, conntrack, NAT) et le **lien physique** (offloads, MTU). Chacun a ses outils d'observation, et la capacité à les enchaîner est ce qui permet de localiser une panne en minutes au lieu d'heures.

**Alternatives**
- `pwru` (eBPF) ou `perf trace` pour suivre un paquet dans le noyau fonction par fonction : plus puissant, mais un outil de plus à installer.
- `conntrack -E` (événements en direct) plutôt que `-L`.
- Mise en miroir de port (`tc mirred`) pour capturer depuis une autre machine.

**Pièges classiques**
- Capturer sans filtre sur `vmbr0` ou sur l'interface physique de `pve01` (bruit, charge, données d'autres VMs).
- Oublier de supprimer la table de traçage (coût CPU, et un futur diagnostic « pollué »).
- Supposer la topologie SDN au lieu de la lire.
- Confondre les tailles affichées par tcpdump avec la MTU du fil.

**En production chez MédiSphère**

Le compte rendu sert de support d'intégration des nouveaux arrivants. Les captures sur des équipements de production obéissent à une procédure (durée, filtre, destination des fichiers, suppression) : elles contiennent des données de santé potentielles et relèvent du RGPD.

---

### M00-E48 — Mesurer et comprendre les performances disque

**Solution**

Fichiers fournis : [`fichiers/M00-E48/perf-disques.fio`](fichiers/M00-E48/perf-disques.fio) (profils P1 à P5), [`fichiers/M00-E48/mesurer.sh`](fichiers/M00-E48/mesurer.sh) (lance tous les profils sur un disque et produit une ligne de tableau par profil), [`fichiers/M00-E48/perf-disques-exemple.md`](fichiers/M00-E48/perf-disques-exemple.md) (structure de rapport attendue).

**1. Préparation de la VM.**

> ⚠️ **Attention** : vérifie que chaque stockage accepte le contenu `images` (`pvesm status --content images`). Si `hdd-bulk` n'est déclaré que pour `iso,vztmpl,backup`, ajoute `images` sans retirer l'existant (`pvesm set hdd-bulk --content iso,vztmpl,backup,images` en reprenant **exactement** la liste actuelle).

```
root@pve01:~# qm clone 9000 5048 --name sbx48 --full 1 --storage local-nvme --pool lab
root@pve01:~# qm set 5048 --scsihw virtio-scsi-single --cores 4 --memory 4096 --net0 virtio,bridge=vsandbox --ipconfig0 ip=dhcp
root@pve01:~# qm set 5048 --scsi1 local-nvme:10,iothread=1,cache=none,discard=on,serial=nvme48 \
                         --scsi2 ssd-lab:10,iothread=1,cache=none,discard=on,serial=ssd48 \
                         --scsi3 hdd-bulk:10,iothread=1,cache=none,discard=on,serial=hdd48
root@pve01:~# qm start 5048
admin@sbx48:~$ sudo apt-get install -y fio jq
admin@sbx48:~$ lsblk -o NAME,SIZE,SERIAL; ls -l /dev/disk/by-id/ | grep 48
```

Le numéro de série rend l'identification certaine : l'ordre `sdb`/`sdc`/`sdd` n'est pas garanti d'un démarrage à l'autre, et écrire sur le mauvais disque détruirait le système de la VM (ou fausserait toutes les mesures).

**2. Préconditionnement** (une écriture séquentielle complète par disque) :

```
admin@sbx48:~$ sudo fio --name=precond --filename=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_nvme48 \
      --rw=write --bs=1M --iodepth=16 --direct=1 --ioengine=libaio
```

Indispensable sur les stockages à **allocation dynamique** (LVM-thin, ZFS, fichiers qcow2/raw creux) : un bloc jamais écrit est lu sans aucune E/S (le stockage renvoie des zéros), et sa première écriture coûte une allocation. Sans préconditionnement, on mesure l'allocateur et des lectures fictives, pas le disque. Sur SSD et NVMe, l'état du contrôleur (blocs libres, ramasse-miettes interne) change aussi les résultats en écriture soutenue. Note : `discard=on` + un TRIM dans la VM (`blkdiscard`, `fstrim`) remettrait les blocs à l'état « non alloué ».

**3. Mesures.** Le script lance chaque profil 60 s après 10 s de chauffe, en JSON, et extrait les champs utiles avec `jq`. Le profil P6 (etcd) suit la méthode de référence de la communauté etcd :

```
admin@sbx48:~$ sudo fio --name=etcd --filename=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_nvme48 \
      --rw=write --ioengine=sync --fdatasync=1 --bs=2300 --size=22m --direct=0
```

Lis dans la sortie la section des latences de synchronisation (`fsync/fdatasync/sync_file_range` → `sync percentiles`) : c'est le p99 de **`fdatasync`** qui compte (cible etcd : sous 10 ms ; confortable : sous 2 ms).

**4. Variantes.** `cache` et `iothread` sont des paramètres du périphérique : modifiés par `qm set` sur une VM démarrée, ils restent en attente (*pending*) jusqu'à un arrêt/démarrage complet de la VM (un redémarrage depuis l'intérieur ne suffit pas). Procédure : `qm set 5048 --scsi2 ssd-lab:vm-5048-disk-2,iothread=1,cache=writeback,discard=on,serial=ssd48` (reprends le nom exact du volume dans `qm config`), `qm shutdown 5048 && qm start 5048`, mesure, puis retour à `cache=none`.

**5. Résultats et interprétation.** Le tableau ci-dessous illustre la **forme** attendue et des ordres de grandeur **typiques**, pas des résultats : tes chiffres dépendent de tes disques (grand public ou datacenter, avec ou sans protection contre la coupure d'alimentation), du type de stockage Proxmox et de la charge des autres VMs.

| Stockage | Profil | IOPS | Débit | Lat. moy. | p99 | p99.9 |
|---|---|---|---|---|---|---|
| local-nvme | P1 4k randread QD32×4 | 100 000 à 400 000 | — | 0,3 à 1 ms | 1 à 3 ms | |
| local-nvme | P3 4k randwrite QD1 | 10 000 à 40 000 | — | 25 à 100 µs | 50 à 300 µs | |
| local-nvme | P6 etcd (fdatasync) | 500 à 20 000 | — | — | 0,1 à 5 ms | |
| ssd-lab (SATA) | P1 | 40 000 à 90 000 | ~350 à 550 Mo/s | 1 à 3 ms | 2 à 6 ms | |
| ssd-lab (SATA) | P6 etcd | 300 à 10 000 | — | — | 0,2 à 10 ms | |
| hdd-bulk (7200 tr/min) | P1 | 100 à 400 | — | 100 ms et plus | plusieurs centaines de ms | |
| hdd-bulk | P5 1M seq write | — | 120 à 250 Mo/s | | | |
| hdd-bulk | P6 etcd | 20 à 100 | — | — | 10 à 50 ms | |

Lecture :
- **IOPS et latence sont liées** par la profondeur de file (loi de Little : IOPS ≈ requêtes en vol / latence). Un chiffre d'IOPS sans la profondeur de file qui l'a produit ne veut rien dire ; P1 (QD 128 au total) et P3 (QD 1) mesurent deux choses différentes.
- **Le p99 compte plus que la moyenne** pour les systèmes à consensus et les bases de données : une requête sur cent qui attend 50 ms suffit à faire expirer un *heartbeat* etcd ou à ralentir un commit.
- **Le test `fdatasync` sépare les disques** : un SSD ou NVMe grand public sans protection contre la coupure d'alimentation doit réellement écrire en mémoire flash à chaque synchronisation (plusieurs centaines de µs à quelques ms) ; un disque datacenter avec condensateurs acquitte depuis son cache protégé (dizaines de µs). Le disque dur, lui, paie une rotation à chaque synchronisation.
- **`iothread=1`** sort le traitement des E/S du thread principal de QEMU : effet surtout visible à forte profondeur de file (P1) et sur plusieurs disques en parallèle. Il n'a d'intérêt par disque qu'avec `virtio-scsi-single` (un contrôleur, donc un thread, par disque).
- **`cache=writeback`** fait passer les écritures par le cache de page de l'hôte : P2 et P3 explosent (la RAM de l'hôte absorbe), alors que P6 change peu, car les `fdatasync` de la VM sont toujours transmis jusqu'au disque. Les données écrites sans synchronisation restent en RAM de `pve01` : une coupure de courant les perd, comme elles le seraient dans le cache d'un disque. Le mode est donc sûr pour une application qui synchronise correctement, mais il consomme la RAM de l'hôte, double la mise en cache (VM + hôte) et rend les mesures sans synchronisation trompeuses. `cache=unsafe`, lui, ignore les synchronisations : jamais pour des données qu'on veut garder.

**6. Recommandation de placement** (à adapter à **tes** chiffres) :

| Charge | Stockage | Justification |
|---|---|---|
| etcd (module 14), bases PostgreSQL (modules 12, 27) | `local-nvme` | p99 de `fdatasync` le plus bas ; latence en QD 1 |
| OSD Ceph virtuels (module 08) | `ssd-lab` | IOPS correctes, disque physique **séparé** de celui d'etcd : un rééquilibrage Ceph ne doit pas dégrader le quorum etcd |
| Disques système des VMs | `local-nvme` | démarrages et mises à jour rapides |
| MinIO, artefacts, sauvegardes locales, ISO, images source et snippets (les templates eux-mêmes restent sur `local-nvme`, pour les clones liés) | `hdd-bulk` | volumétrie, accès séquentiels, latence peu critique |
| À proscrire | `hdd-bulk` pour etcd, bases ou journaux de Ceph | p99 de synchronisation de plusieurs dizaines de ms |

**7. Nettoyage.**

```
root@pve01:~# qm stop 5048 && qm destroy 5048 --purge 1 --destroy-unreferenced-disks 1
root@pve01:~# for s in local-nvme ssd-lab hdd-bulk; do pvesm list $s | grep vm-5048- ; done   # doit être vide
```

**Vérification** : `lab/bin/check 00 48`.

**Explications**

Ce qu'une VM mesure est une **pile** : application → système de fichiers (absent ici, on mesure le périphérique brut) → pilote virtio-scsi → QEMU (contrôleur émulé, iothread, mode de cache, `aio`) → couche de stockage Proxmox (LVM-thin, ZFS, fichier qcow2) → cache de page de l'hôte (selon `cache`) → disque physique (cache interne, FTL, rotation). Chaque étage peut dominer selon le profil. `--direct=1` contourne le cache de page **de la VM** ; le mode `cache` de Proxmox décide du cache **de l'hôte**. ZFS ajoute son propre cache (ARC) qui peut rendre les lectures irréalistes : si un stockage est sur ZFS, choisis une taille de test supérieure à l'ARC disponible ou note la limite dans le rapport.

**Alternatives**
- Mesurer sur l'hôte (`fio` sur un volume dédié) pour isoler le coût de la virtualisation : intéressant, mais plus risqué (jamais sur un périphérique utilisé).
- `ioping` pour une mesure rapide de latence ; `iostat -x 1` sur l'hôte pendant les tests pour voir la file et l'utilisation de chaque disque physique.
- Profil réaliste PostgreSQL : `pgbench` dans la VM, plus parlant pour un DBA qu'un profil `fio` synthétique.

**Pièges classiques**
- Mesurer sans préconditionnement sur LVM-thin ou ZFS (lectures « infinies »).
- Mesurer avec `cache=writeback` sans le dire, ou sans `--direct=1`.
- Comparer des IOPS obtenues à des profondeurs de file différentes.
- Tests de 10 secondes : on mesure le cache SLC/DRAM d'un SSD, pas son régime établi.
- Écrire avec `fio` sur `/dev/sda` de la VM (son système) ou, pire, sur un périphérique de l'hôte.
- Oublier les autres VMs : une VM personnelle active sur le même disque fausse les mesures et subit le test.

**En production chez MédiSphère**

Chaque classe de stockage a une fiche de performance mesurée à la réception du matériel et après chaque changement majeur (firmware, version de Ceph), et des StorageClasses Kubernetes (module 16) ou des types de volume OpenStack (module 10) qui exposent ces classes aux équipes, avec des quotas. Les disques destinés à etcd et aux bases sont choisis avec protection contre la coupure d'alimentation.

---

### M00-E49 — Questions expert : sous le capot

**Réponses argumentées**

**1. Port d'une VM `tag=20` et trame étiquetée 30 émise par la VM.**
Pour le `tap` de la VM : `20 PVID Egress Untagged` (la VLAN 20 est attribuée aux trames reçues sans étiquette, et l'étiquette est retirée en sortie vers la VM). Pour le trunk de `gw01` (carte sans `tag`) : `1 PVID Egress Untagged` plus `2-4094` étiquetées (valeur de `bridge-vids`). Une trame **déjà étiquetée 30** émise par la VM arrive sur un port dont la seule VLAN autorisée est 20 : le filtrage VLAN du bridge (`vlan_filtering=1`) la **jette** à l'entrée. C'est ce qui empêche une VM de « sauter » de VLAN en étiquetant elle-même ses trames (*VLAN hopping*). Sans `vlan_filtering`, le comportement serait tout autre : la raison d'être d'un bridge VLAN-aware est précisément ce filtrage.

**2. QCM — réponse b.** Proxmox ajoute au port les VLANs de `bridge-vids` du bridge (2-4094 par défaut) quand aucun `trunks=` n'est précisé, plus la VLAN 1 non étiquetée. a) est faux : la VLAN 1 n'est que le PVID. c) est faux : 0 et 4095 sont réservées, et la plage dépend de `bridge-vids`. d) est faux : les VNets SDN sont une couche de gestion, le bridge VLAN-aware fonctionne sans eux.

**3. `fwbr`/`fwpr`/`fwln`.** Le pare-feu historique applique des règles iptables au trafic **ponté** grâce à `br_netfilter`. Pour attacher des règles propres à une carte, sans dépendre de la nature du bridge principal (Linux VLAN-aware, OVS) et en gardant la possibilité de filtrer par port physique (`physdev`), Proxmox insère un bridge minuscule par carte (`fwbr<VMID>i<N>`) contenant le `tap`, relié au bridge principal par une paire veth (`fwln…` côté `fwbr`, `fwpr…` côté bridge principal). Coûts : deux sauts de pont supplémentaires, des interfaces en plus, une complexité de diagnostic. Le moteur nftables (`proxmox-firewall`) filtre dans la famille `bridge` de nftables, directement sur les ports, sans ces intermédiaires (option à activer, à vérifier selon ta version).

**4. Table conntrack pleine.** Symptômes : nouvelles connexions qui échouent de manière **aléatoire** (les connexions existantes continuent), pertes de paquets UDP (DNS !), message `nf_conntrack: table full, dropping packet` dans `dmesg`. Paramètres : `net.netfilter.nf_conntrack_max` (nombre d'entrées), `nf_conntrack_buckets` (table de hachage ; ratio courant max = 4 × buckets), délais par protocole (`nf_conntrack_tcp_timeout_established` = 5 jours par défaut, `udp_timeout`…), compteur `nf_conntrack_count`. Causes typiques en lab : un scan ou une boucle de requêtes UDP (DNS récursif sous charge : chaque requête amont crée une entrée), des connexions TCP abandonnées sans FIN qui restent « established » des jours, un `nf_conntrack_max` dimensionné pour 1 Go de RAM. Remèdes par pertinence : 1) trouver et traiter la source (`conntrack -L | awk '{print $1}' | sort | uniq -c`, top des sources) ; 2) réduire les délais excessifs (TCP established, UDP) ; 3) augmenter `nf_conntrack_max` et `buckets` en connaissant le coût mémoire (~300 octets par entrée) ; en complément, `notrack` pour des flux qui n'en ont pas besoin (trafic local à très haut débit), en sachant qu'ils ne bénéficient plus du filtrage à états.

**5. QCM — réponse b.** Chaque chaîne de base attachée à un hook est évaluée, par ordre de priorité ; à priorité égale, l'ordre n'est pas garanti. Un `accept` termine **la chaîne courante** (et la table) mais le paquet continue vers les autres chaînes de base du même hook ; un `drop` est définitif. Le paquet accepté par `inet filter` est donc jeté par `ip filter FORWARD` de politique DROP. a) est faux pour cette raison. c) est faux : l'ordre de création ne joue pas, seule la priorité. d) est faux : plusieurs chaînes de même priorité sur un hook sont autorisées. C'est le scénario classique « Docker installé sur le routeur, plus rien ne passe ».

**6. `iptables-legacy`, `iptables-nft`, `nft`.** `iptables-legacy` utilise l'ancienne API du noyau (x_tables) ; `iptables-nft` garde la syntaxe iptables mais crée des tables et chaînes **nftables** (tables `ip filter`, `ip nat`… visibles par `nft list ruleset`) ; `nft` est l'outil natif. Coexistence : `iptables -V` indique `(nf_tables)` ou `(legacy)` ; `nft list ruleset` montre des tables `ip filter` avec des chaînes en majuscules ; `iptables-legacy-save` non vide en parallèle signale des règles legacy invisibles de `nft`. Risque : deux sources de vérité, interactions non évidentes (question 5), règles legacy invisibles pour qui ne regarde que `nft`, et outils (Docker, Kubernetes, fail2ban, `pve-firewall` historique) qui écrivent chacun dans leur monde.

**7. NAT au premier paquet.** Voir M00-E47, question 4 : la chaîne de type `nat` n'est traversée que par les paquets `NEW` ; la traduction est stockée dans l'entrée conntrack. Une règle de NAT modifiée n'affecte que les nouveaux flux ; les flux établis gardent l'ancienne traduction jusqu'à expiration ou suppression de l'entrée (`conntrack -D`). C'est aussi pourquoi un changement d'adresse WAN laisse des connexions « fantômes » avec l'ancienne adresse.

**8. Cryptokey routing.** En **émission**, une fois le paquet routé dans l'interface WireGuard, le pair est choisi par correspondance la plus spécifique de la destination dans les `AllowedIPs` de tous les pairs ; aucun pair → `ENOKEY`. En **réception**, après déchiffrement, le paquet n'est accepté que si sa source appartient aux `AllowedIPs` **du pair qui l'a chiffré** : c'est une liste de contrôle d'accès autant qu'une table de routage. Recouvrement 10.20.0.0/16 (pair A) et 10.20.10.0/24 (pair B) : autorisé ; en émission, 10.20.10.5 part vers B (préfixe le plus long), 10.20.20.5 vers A ; en réception, A ne peut plus émettre depuis 10.20.10.0/24 (cette plage « appartient » à B). En revanche, un **même** préfixe déclaré sur deux pairs est retiré du premier quand on l'ajoute au second : il ne peut appartenir qu'à un seul pair.

**9. QCM — réponse b.** `ENOKEY` est renvoyé par WireGuard quand aucun pair ne couvre la destination (ou qu'aucune session n'est possible faute de clé). a) une clé privée absente empêcherait l'interface de fonctionner, avec d'autres symptômes (et `wg show` le montre). c) un port filtré produit un tunnel silencieux (pas de poignée de main), pas une erreur à l'émission. d) WireGuard tolère des écarts d'horloge (les horodatages TAI64N servent à l'anti-rejeu, comparés uniquement aux précédents du même pair).

**10. Endpoint faux sur une seule extrémité.** WireGuard met à jour l'endpoint d'un pair à partir de l'adresse source de tout paquet authentifié reçu de lui (*roaming*). Si l'autre extrémité connaît la bonne adresse et émet (keepalive, trafic), l'extrémité fausse se corrige en mémoire au premier paquet reçu. Bloquant quand : les deux extrémités sont fausses ; l'extrémité correcte n'émet jamais (pas de `PersistentKeepalive`, pas de trafic) ; un NAT ou un pare-feu ne laisse passer qu'un sens ; après redémarrage de l'extrémité fausse si l'autre reste silencieuse. Dette : le fichier reste faux.

**11. `.fidx` et `.didx`.** Une image de disque (VM) est découpée en morceaux de **taille fixe** (4 Mio) : l'index `.fidx` est un tableau de condensats (SHA-256) dans l'ordre des blocs. Adapté aux disques : accès aléatoire direct au bloc N (restauration en direct, montage de fichiers), et le *dirty bitmap* de QEMU dit exactement quels blocs ont changé depuis la dernière sauvegarde : on ne lit et n'envoie que ceux-là (sauvegarde incrémentale en secondes au lieu de relire tout le disque). Le bitmap vit dans QEMU : il est perdu à l'arrêt complet de la VM (ou si la cible change), et la sauvegarde suivante relit tout le disque (en ne transférant toujours que les morceaux absents du serveur). Une archive de fichiers (`pxar`) est découpée **selon le contenu** (*content-defined chunking*, somme glissante), en morceaux de taille variable : l'index `.didx` contient décalages et condensats. Avantage : une insertion au milieu d'un fichier ne décale pas tous les morceaux suivants, la déduplication reste efficace ; un découpage fixe serait inadapté (tout décalage changerait tous les blocs).

**12. Ramasse-miettes (GC).** Supprimer un instantané supprime seulement son **index** ; les morceaux sont partagés entre instantanés et ne peuvent être supprimés que s'ils ne sont plus référencés par aucun index. Le GC procède en deux phases : 1) **marquage** : il parcourt tous les index et met à jour l'horodatage d'accès (`atime`) de chaque morceau référencé ; 2) **balayage** : il supprime les morceaux dont l'`atime` est plus ancien que le début du GC moins une marge (24 h et 5 min par défaut, pour tenir compte des sauvegardes en cours et de la sémantique `relatime`). L'espace n'est donc libéré qu'au GC suivant, et seulement pour les morceaux devenus orphelins depuis plus de la marge. C'est aussi pourquoi le système de fichiers du datastore doit gérer `atime` correctement.

**13. Vérification et chiffrement.** Avec le chiffrement côté client, PBS ne possède pas la clé : il peut vérifier l'**intégrité** de chaque morceau stocké (le condensat et la somme de contrôle du conteneur chiffré correspondent) et la cohérence des index (tous les morceaux référencés existent), mais il ne peut pas vérifier que le contenu **déchiffré** est valide ni qu'il est restaurable. Perte de la clé = perte définitive des sauvegardes chiffrées avec elle. Procédure attendue : clé maître (*master key*) RSA pour chiffrer une copie de la clé de chiffrement dans chaque sauvegarde, version papier ou coffre (`proxmox-backup-client key paperkey`), copie hors ligne dans un coffre-fort (deux emplacements, deux personnes), test de restauration régulier **à partir de la clé de secours** (M00-E36, M00-E37) et inventaire des clés (empreintes, pas les clés) dans le dossier d'exploitation.

**14. Virtualisation imbriquée.** Côté `pve01` : module `kvm_intel` chargé avec `nested=1` (vérifiable dans `/sys/module/kvm_intel/parameters/nested`) ; côté VM : type de CPU exposant VMX (`cpu: host`, ou un modèle avec le drapeau `+vmx`). EPT (*Extended Page Tables*) traduit en matériel les adresses physiques invitées en adresses physiques hôtes ; en imbriqué, l'hyperviseur L0 combine les tables de L1 et L2 (EPT « shadow ») pour que L2 tourne aussi avec la traduction matérielle. Le calcul pur s'exécute donc presque à vitesse native. Les **sorties de VM** (E/S, interruptions, instructions privilégiées) de L2 doivent être interceptées par L0, transmises à L1, traitées, puis réinjectées : plusieurs transitions coûteuses par événement. D'où des performances correctes en CPU, nettement dégradées en E/S et en réseau (et l'intérêt de virtio et de vhost à chaque niveau). Rappel : `cpu: host` empêche la migration à chaud vers un hôte de CPU différent.

**15. QCM — réponse b.** `iothread` associe un thread d'E/S à un **contrôleur**. Avec `virtio-scsi-pci`, tous les disques SCSI partagent un contrôleur, donc un thread ; avec `virtio-scsi-single`, chaque disque a son contrôleur, donc son thread. a) est faux : les deux gèrent le TRIM (`discard`). c) est faux : sans `iothread`, la différence est faible ; « toujours plus rapide » ne veut rien dire. d) est faux : `iothread` n'est pas ignoré, il est seulement partagé (Proxmox l'indique dans l'interface).

**16. Modes de cache.** `cache=none` : QEMU ouvre l'image en `O_DIRECT`, le cache de page de l'hôte est contourné ; le cache d'écriture du disque reste actif et exposé à la VM, qui doit émettre des *flush* (ce que font les systèmes de fichiers modernes et les `fsync`) : intégrité garantie pour les données synchronisées, perte possible des écritures non synchronisées en cas de coupure (comme sur une machine physique). `writeback` : cache de page de l'hôte en lecture et en écriture, *flush* de la VM transmis : même garantie pour les données synchronisées, mais consommation de RAM de l'hôte, double mise en cache, et volume de données non synchronisées potentiellement perdu plus grand. `writethrough` : chaque écriture est synchronisée avant acquittement : sûr même pour une VM qui ne synchronise pas, mais lent en écriture. (`unsafe` ignore les *flush* : jamais pour des données à garder.) Recommandation par défaut : `none` (ou le défaut de Proxmox, à vérifier selon ta version et le type de stockage).

**17. pmxcfs.** `/etc/pve` est un système de fichiers FUSE fourni par `pmxcfs` ; les données sont stockées dans une base SQLite locale (`/var/lib/pve-cluster/config.db`) et entièrement chargées en mémoire. En cluster, chaque modification est diffusée par corosync à tous les nœuds (ordre total des messages) : chaque nœud a une copie complète. Sans quorum, `/etc/pve` passe en **lecture seule** sur le nœud isolé (pas de démarrage de VM, pas de modification de configuration), pour éviter des écritures divergentes. Pas de gros fichiers : tout est en RAM et répliqué à chaque écriture, la taille par fichier et la taille totale sont limitées (de l'ordre du Mio par fichier et de quelques dizaines de Mio au total, à vérifier dans la documentation pmxcfs). Sur un nœud seul comme `pve01`, le quorum est trivialement atteint.

**18. Même adresse DHCP pour des clones.** Cause la plus probable : le template contient un `/etc/machine-id` déjà généré. `systemd-networkd` (et d'autres clients) dérive l'identifiant client DHCP (DUID/IAID) du `machine-id` ; dnsmasq attribue les baux par identifiant client quand il est présent, pas par adresse MAC : tous les clones présentent le même identifiant et obtiennent le même bail, à tour de rôle. Préparation correcte du template : vider `/etc/machine-id` (fichier vide, pas supprimé) et supprimer `/var/lib/dbus/machine-id` s'il n'est pas un lien, `cloud-init clean` (instance, journaux, et selon le cas `--machine-id`, option à vérifier selon ta version), clés d'hôte SSH supprimées (régénérées au premier démarrage). Les images *genericcloud* vierges ne posent pas le problème ; c'est le fait de démarrer l'image avant de la convertir en template qui le crée.

**19. Ballooning, KSM, ARC.** Le **ballooning** permet à Proxmox de reprendre de la mémoire à une VM (pilote dans l'invité) jusqu'à son minimum `balloon`, quand l'hôte dépasse environ 80 % d'utilisation : utile pour absorber un pic, inefficace si toutes les VMs utilisent réellement leur mémoire. **KSM** fusionne les pages identiques entre VMs (beaucoup de VMs Debian identiques : gain réel), au prix de CPU et d'un risque théorique de canal auxiliaire ; il ne s'active qu'au-delà d'un seuil d'utilisation. L'**ARC ZFS** utilise par défaut une part importante de la RAM (depuis OpenZFS 2.3, livré avec PVE 9 : jusqu'à la RAM moins 1 Gio ; l'installateur Proxmox ne le plafonne à 10 % de la RAM, 16 Gio au plus, que si la racine a été installée en ZFS — voir M00-E35, question 2) : il se réduit sous pression, mais pas instantanément. Pour le budget de PLAN §3.3 : 128 Go moins l'hôte, l'ARC éventuel et une marge = mémoire réellement disponible ; le socle (~24 Go) plus le profil le plus lourd (plateforme, ~80 Go) approche la limite, d'où la règle « un seul profil lourd à la fois ». Quand l'hôte manque réellement de mémoire : ballooning, puis swap (lent), puis **OOM killer**, qui tue le plus gros processus… c'est-à-dire un processus QEMU, donc une VM entière, arrêtée brutalement.

**20. MSS et clamping.** MTU 1420 sur `wg0` : IPv4 → 1420 − 20 (IP) − 20 (TCP) = **1380** ; IPv6 → 1420 − 40 − 20 = **1360** (sans options TCP comme les horodatages, qui réduisent encore la charge utile réelle de 12 octets). Le MSS n'est **annoncé** que dans les segments SYN et SYN-ACK, à l'ouverture de connexion : c'est le seul moment où un routeur peut le réécrire. Le clamping ne remplace pas la PMTUD parce qu'il ne concerne que TCP (rien pour UDP, QUIC, ICMP, tunnels imbriqués), qu'il ne voit que les connexions qui le traversent, qu'il se calcule sur la route de sortie du SYN (donc protège un seul sens, voir M00-E41) et qu'il ne s'adapte pas à un changement de chemin en cours de connexion.

**Explications**

Ces questions recoupent les quatre fondamentaux du module : le **pont** (questions 1 à 3), le **filtrage et la traduction** (4 à 7), les **tunnels** (8 à 10, 20) et le **stockage/la virtualisation** (11 à 19). En entretien, une bonne réponse annonce le mécanisme, donne un exemple concret ou une commande d'observation, et cite une limite ou un piège.

**Pièges classiques**
- Répondre aux QCM sans justifier pourquoi les autres options sont fausses : en revue d'architecture, c'est la justification qui convainc.
- Réciter la documentation sans lien avec le lab : les meilleures réponses citent une observation faite en M00-E47 ou dans une panne.

**En production chez MédiSphère**

Karim utilise une partie de ces questions en entretien et en revue de MR : la question 5 (Docker sur un routeur), la 13 (clé de chiffrement) et la 19 (OOM d'un hyperviseur) correspondent à des incidents réels de l'ancien prestataire.
