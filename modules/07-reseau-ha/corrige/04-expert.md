# Module 07 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Dans ce palier, « j'ai redémarré FRR (ou keepalived, ou la VM) et ça remarche » est presque toujours faux : un redémarrage efface la preuve (session, route posée à chaud, table nftables, état LACP) et laisse souvent la cause en place (fichier sysctl, configuration écrite), qui revient au prochain démarrage ou au prochain passage du code.

Les scripts d'injection sont dans `corrige/pannes/` (`_m07-commun.sh` contient les fonctions partagées : accès aux VMs de la maquette **par l'agent QEMU** après contrôle du nom et de l'étiquette `env-m07`, modifications de fichiers mémorisées et réversibles sans écraser une réparation, valeurs sysctl et MTU d'origine notées, tables nftables dédiées, actions à chaud notées avec leur test). Chaque modification est journalisée sur l'hôte touché dans `/var/lib/workbook/pannes.log` (copies et notes dans `/var/lib/workbook/M07-EXX.*`), et sur `adm01` dans `~/.local/state/workbook/M07-EXX/`.

Les runbooks issus des pannes sont dans `corrige/fichiers/M07-E35/` à `M07-E42/` (`medisphere/docs/socle/runbooks/RB-073` à `RB-079`), le post-mortem d'exemple de l'astreinte dans `corrige/fichiers/M07-E43/`, le compte rendu d'exemple du voyage d'un paquet dans `corrige/fichiers/M07-E44/`.

Les sorties reproduites sont **représentatives** : numéros, horodatages et formulations exactes varient selon les versions. Les noms d'interfaces de la maquette sont ceux de l'introduction (`eth0` administration sur `vsandbox`, `eth1`… vers la fabric) ; adapte-les si ta maquette les nomme autrement (`ens18`…). Sur le socle : `ens18`/`ens19`. Elles suivent la documentation de FRR 10.7, keepalived 2.3, HAProxy 3.2, Open vSwitch 3.5, WireGuard (noyau 6.12 de Debian 13) et iproute2 de Debian 13.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- champs `pfxRcd`, `pfxSnt`, `remoteAs`, `hostname` de `show bgp ipv4 unicast summary json` (FRR 10.7), sur lesquels s'appuient les scripts et les contrôles de E35, E36, E38 et E42 ;
- traitement par `frr-reload.py` d'un changement de `remote-as` sur un groupe de pairs (E35 v1) : selon la version, la session est remise à zéro ou le groupe recréé ; dans les deux cas la session ne s'établit plus ;
- message exact du noyau pour un segment TCP-MD5 inattendu ou manquant (E35 v3) : `TCP: MD5 Hash NOT expected` / `MD5 Hash expected but not found` dans les noyaux récents, compteurs `TCPMD5Unexpected` / `TCPMD5NotFound` de `nstat` ;
- délai d'expiration du partenaire LACP quand Open vSwitch cesse d'émettre (E40 v2) : 3 s (`lacp_rate fast`) ou 90 s (`slow`) ;
- comportement de l'injection de E38 si les VNets `vfab*` ont été créées avec un MTU inférieur à 1500 : la panne se constate quand même, mais le diagnostic doit alors commencer par le MTU des VNets ;
- présence de `curl`, `nft` et `python3` dans l'image dorée `current` (utilisés par les scripts et les contrôles).

---

## Méthode commune aux pannes réseau

1. **Reproduire avec la bonne source.** Sur la maquette, une machine a au moins deux adresses (administration, boucle) : `ping -I <boucle>`, `curl --interface <boucle>`. Un test lancé avec la mauvaise source teste un autre chemin.
2. **Descendre les couches dans l'ordre.** Lien (`ip -d link`, `/proc/net/bonding`, `ovs-appctl bond/show`), trame (`bridge fdb`, `ip neigh`), paquet (`ip route get … from … iif …`, `ip rule`, `rp_filter`), filtrage (`nft list ruleset`, compteurs), plan de contrôle (`vtysh`, journal de keepalived), application (socket d'administration de HAProxy, `curl -v`).
3. **Capturer aux deux extrémités du segment suspect**, simultanément, avec un filtre précis et une limite (`-c`). Un paquet vu d'un côté et pas de l'autre désigne le segment ; une requête vue des deux côtés sans réponse désigne le retour.
4. **Lire l'état chargé, pas seulement le fichier.** `vtysh -c 'show running-config'`, `nft list ruleset`, `ip rule`, `sysctl -n`, `wg show`, `show stat` : la panne est souvent dans l'écart avec le fichier ou avec ce que produirait le rôle (`--check --diff --limit`).
5. **Chercher ce qui a bougé** : `find /etc -newer <fichier témoin>`, `ls -lt /etc/sysctl.d /etc/frr /etc/keepalived`, `journalctl --since`, historique Git des projets.
6. **Corriger à la source, puis faire converger le code.** Une réparation à chaud est permise sur la maquette ; elle n'est pas finie tant que le rôle ne produit pas le même état (second passage `changed=0`) et qu'un redémarrage ne réintroduit rien (fichiers de `/etc/sysctl.d/`, base d'Open vSwitch).
7. **Prévenir** : quelle sonde de `ms-verif-reseau`, quel test Molecule, quel contrôle de pipeline aurait vu la panne avant l'utilisateur ?

---

### M07-E35 — Panne : la session BGP ne monte pas

**Démarche de diagnostic**

*Symptôme* : `gw01` n'a plus de route BGP vers 10.10.255.0/24 ; la bordure n'a pas changé.

*Hypothèses*, de bas en haut : pas de connectivité IP entre 10.10.99.251 et la passerelle ; TCP/179 filtré ; segments TCP rejetés (authentification) ; OPEN refusé (AS, identifiant, capacités) ; session établie mais aucune route échangée (politique, RFC 8212) ; routes reçues mais refusées par la politique de la bordure.

**Étape 1 — L'état des deux côtés.**

```
admin@gw01:~$ sudo vtysh -c 'show bgp ipv4 unicast summary'
Neighbor        V    AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
10.10.99.251    4 65101      1203      1198        0    0    0 00:02:11        Active        0 N/A
root@leaf01:~# vtysh -c 'show bgp ipv4 unicast summary'
root@leaf01:~# vtysh -c 'show bgp neighbors 10.10.99.2' | grep -E 'BGP state|Last reset|Notification|Local host|Foreign host'
root@leaf01:~# journalctl -u frr --since -30min --no-pager | grep -iE 'bgp|notif|open' | tail -n 20
```

L'état seul classe la panne : `Active`/`Connect` (TCP ne s'établit pas), `Idle` qui revient sans cesse avec une NOTIFICATION (OPEN refusé), `Established` avec `(Policy)` ou `0` en préfixes envoyés (politique).

**Variante 1 — AS distant faux.** Sur `leaf01`, le pair apparaît avec l'AS 65010 ; sur `gw01`, le pair 10.10.99.251 alterne `Idle`/`Active`.

```
root@leaf01:~# vtysh -c 'show bgp neighbors 10.10.99.2' | grep -E 'remote AS|Last reset'
BGP neighbor is 10.10.99.2, remote AS 65010, local AS 65101, external link
  Last reset 00:00:07,  Notification sent (OPEN Message Error/Bad Peer AS)
root@leaf01:~# grep -n 'remote-as' /etc/frr/frr.conf
8: neighbor BORDURE remote-as 65010
```

`leaf01` reçoit un OPEN de l'AS 65000 alors qu'il attend 65010 : il répond par une NOTIFICATION « Bad Peer AS » (RFC 4271 §6.2) et ferme. Correctif : remettre 65000 par le rôle `frr` (`host_vars/leaf01/frr.yml` ou le gabarit), `--check --diff --limit leaf01` montre la ligne, application, `systemctl reload frr` par le *handler*. Prévention : déclarer les AS **une seule fois** (variables de groupe `bgp_as_bordure: 65000`) et les consommer partout ; un test Molecule qui vérifie `Established` avec un pair simulé.

**Variante 2 — route-map de sortie supprimée.** La session est `Established` des deux côtés, mais :

```
root@leaf01:~# vtysh -c 'show bgp ipv4 unicast summary' | grep 10.10.99
10.10.99.2      4 65000   …  00:12:40            0   (Policy) N/A
root@leaf01:~# vtysh -c 'show bgp neighbors 10.10.99.2' | grep -i policy
  Outbound updates discarded due to missing policy
```

`bgp ebgp-requires-policy` (RFC 8212) interdit toute annonce eBGP sans politique de sortie explicite : `leaf01` n'annonce plus rien, la bordure n'a plus rien à apprendre. Le fichier ne contient plus la ligne `neighbor BORDURE route-map BORDURE-OUT out` (InfoGér l'a retirée en « nettoyant les politiques inutiles »). Correctif : rétablir la ligne par le rôle. **Le mauvais correctif** : `no bgp ebgp-requires-policy` ; il « répare » en annonçant tout (et en acceptant tout de la bordure), exactement ce que la RFC veut empêcher — le contrôle de l'exercice le refuse.

**Variante 3 — mot de passe TCP-MD5 d'un seul côté.** Pair en `Active`/`Connect` des deux côtés, compteurs de messages figés.

```
root@leaf01:~# tcpdump -ni any -c 6 'tcp port 179 and host 10.10.99.2'
… 10.10.99.2.43122 > 10.10.99.251.179: Flags [S], … options [mss 1460,…]
… 10.10.99.251.38811 > 10.10.99.2.179: Flags [S], … options […,md5 …]
root@leaf01:~# nstat -az | grep -i md5
TcpExtTCPMD5NotFound            14                 0.0
admin@gw01:~$ sudo dmesg | grep -i md5 | tail -n 2
admin@gw01:~$ nstat -az | grep -i md5
TcpExtTCPMD5Unexpected          12                 0.0
root@leaf01:~# grep -n password /etc/frr/frr.conf
9: neighbor BORDURE password Bordure-PAR1-2025
```

Les SYN de `leaf01` portent l'option TCP-MD5 (RFC 2385), ceux de la bordure non : chaque noyau jette ce que l'autre envoie, **sans que `bgpd` voie quoi que ce soit** (le segment ne remonte jamais au processus). C'est pour cela que la mesure décisive est la capture (`md5` dans les options) ou les compteurs `TCPMD5NotFound`/`TCPMD5Unexpected`. Correctif : retirer le mot de passe de `leaf01` (ou, si l'équipe décide d'authentifier la session, le poser **des deux côtés** : secret dans Ansible Vault `critique`, rôle `frr` des passerelles et de la fabric, TCP-AO de préférence quand les deux côtés le supportent). Un secret n'a rien à faire en clair dans un fichier hors Vault : signale-le à Sophie Laurent.

**Variante 4 — port 179 filtré sur `leaf01`.** `Active` des deux côtés ; la capture sur `leaf01` (avant le filtrage d'entrée) montre les SYN de la bordure **et** les SYN-ACK de la bordure aux SYN de `leaf01`, mais la poignée de main n'aboutit jamais :

```
root@leaf01:~# nft list ruleset | grep -B3 -A3 179
table inet durcissement {
	chain entree {
		type filter hook input priority -10; policy accept;
		ip saddr 10.10.99.0/24 tcp dport 179 counter packets 37 bytes 2220 drop comment "audit SEC : BGP hors fabric"
		ip saddr 10.10.99.0/24 tcp sport 179 counter packets 12 bytes 720 drop comment "audit SEC : BGP hors fabric"
```

Les compteurs qui montent pendant un essai prouvent la cause. La table a été posée à chaud (absente de tout fichier et de tout rôle) : la détection de dérive par Ansible ne la voit pas, puisqu'aucun rôle ne gère nftables sur la maquette. Correctif : `nft delete table inet durcissement`, puis demander l'origine (un « audit » qui filtre BGP sur un équipement de fabric doit passer par la matrice des flux). Prévention : sur tout hôte, un contrôle « jeu de règles chargé = fichier » (`nft -c -f` du fichier, comparaison avec `nft list ruleset`), comme sur la bordure.

**Vérification** : `lab/bin/check 07 35`, puis `lab/bin/break 07 35 --annuler` pour clore.

**Explications**

Une session BGP est une connexion TCP (port 179) entre deux pairs configurés de chaque côté ; elle passe par OPEN (version, AS, temps de maintien, identifiant, capacités), puis KEEPALIVE, puis échange d'UPDATE. Chaque étape a son mode de défaillance : TCP (filtrage, routage, authentification de segment), OPEN (AS, capacités, identifiant en double), politique (RFC 8212, filtres d'entrée et de sortie). La bordure de MédiSphère n'accepte de la fabric que 10.10.255.0/24 et 10.10.41.0/24 : même une session réparée « trop largement » côté `leaf01` ne ferait pas entrer autre chose dans la table de `gw01` — c'est la défense en profondeur de M07-E16.

**Alternatives**
- BFD (RFC 5880) pour détecter en moins d'une seconde la perte d'un pair, au lieu des 9 s (profil `datacenter`) à 180 s (défaut) du temps de maintien.
- TCP-AO (RFC 5925) plutôt que TCP-MD5 pour authentifier une session, quand les deux côtés le supportent.
- Groupe de pairs dynamique (`bgp listen range`) côté bordure, déjà prévu pour Kubernetes : la configuration côté passerelle n'énumère pas les pairs, mais la politique d'entrée devient d'autant plus importante.

**Pièges classiques**
- Regarder un seul côté : `Active` sur `gw01` ne dit pas pourquoi ; la NOTIFICATION est dans le journal de celui qui l'a émise.
- Chercher dans `bgpd` une cause qui est dans le noyau (MD5, filtrage) : rien dans le journal, tout dans `tcpdump` et `nstat`.
- « Réparer » la variante 2 en désactivant `ebgp-requires-policy`.
- Oublier `clear bgp <pair> soft out` après un changement de politique sur une version qui ne le fait pas d'elle-même.

**En production chez MédiSphère**
Sondes séparées dans `ms-verif-reseau` : « session `Established` » **et** « nombre de préfixes reçus dans une fourchette attendue » (une session établie et vide est une panne) ; alerte sur les remises à zéro répétées ; AS et pairs déclarés une seule fois dans l'inventaire ; secrets de session dans Vault. Runbook : `corrige/fichiers/M07-E35/medisphere/docs/socle/runbooks/RB-073-session-bgp.md`.

---

### M07-E36 — Panne : Lyon ne joint plus Paris

**Démarche de diagnostic**

*Symptôme* : `lyo-pc01` ne joint plus PAR1 ; Internet fonctionne (la sortie Internet de l'agence passe par la patte « WAN » de `lyo-gw01`, pas par le tunnel).

*Hypothèses*, dans l'ordre du chemin : `lyo-gw01` ne relaie plus ; pas de route vers PAR1 (BGP) ; WireGuard refuse le paquet (`AllowedIPs`) ; pas de poignée de main (clés, extrémité, filtrage UDP) ; problème côté bordure.

**Étape 1 — Depuis le poste, puis depuis le routeur.**

```
root@lyo-pc01:~# ping -c 2 10.10.20.1
root@lyo-gw01:~# ping -c 2 10.10.20.1
root@lyo-gw01:~# ip route get 10.10.20.1
root@lyo-gw01:~# wg show wg2
root@lyo-gw01:~# vtysh -c 'show bgp ipv4 unicast summary'
```

Si `lyo-gw01` joint Paris et pas `lyo-pc01`, tout ce qui est propre au tunnel fonctionne pour le trafic **émis** par le routeur : il reste ce qui distingue un paquet **relayé** (relais IP, filtrage `forward`, NAT de l'agence).

**Variante 1 — clé publique du pair fausse.**

```
root@lyo-gw01:~# wg show wg2
interface: wg2
  public key: …
  listening port: …
peer: Q2Zk…=            ← n'est pas la clé publique de la bordure
  endpoint: 10.10.99.1:51822
  allowed ips: 10.10.0.0/16, 10.255.2.0/24, …
  transfer: 0 B received, 14.80 KiB sent
admin@gw01:~$ sudo wg show wg2 | grep -A4 peer     # lecture seule, passerelle active
  latest handshake: 6 minutes, 12 seconds ago
```

Aucune poignée de main, des octets envoyés et rien reçu : la bordure ne reconnaît pas l'initiateur (le message d'initiation est chiffré pour une clé qu'elle n'a pas). La session BGP est tombée avec le tunnel, `lyo-gw01` n'a plus de route vers PAR1. Comparer la clé du pair à la clé publique de la bordure (`wg show wg2 public-key` sur la passerelle active, ou le registre des secrets : **la clé publique** n'est pas un secret). Correctif : rétablir la clé dans `wg2.conf` par le rôle `wireguard` de l'agence, puis `wg syncconf wg2 <(wg-quick strip wg2)` (sans couper le tunnel) ou le *handler* du rôle.

**Variante 2 — `AllowedIPs` réduit au réseau du tunnel.**

```
root@lyo-gw01:~# ping -c 1 10.10.20.1
PING 10.10.20.1 (10.10.20.1) 56(84) bytes of data.
ping: sendmsg: Required key not available
root@lyo-gw01:~# wg show wg2 allowed-ips
<clé de la bordure>	10.255.2.0/24
root@lyo-gw01:~# ip route get 10.10.20.1
10.10.20.1 via 10.255.2.1 dev wg2 src 10.255.2.2 …
```

Poignée de main récente, session BGP établie (elle passe entre 10.255.2.2 et 10.255.2.1, couverts), routes apprises… et pourtant `ENOKEY` : en **sortie**, WireGuard cherche le pair dont les `AllowedIPs` contiennent la **destination** ; aucun ne contient 10.10.20.1, le paquet est refusé (routage cryptographique). En **entrée**, le même tableau sert de filtre sur l'adresse **source** : la bordure jetterait de même un paquet de 10.30.10.10 si elle ne l'avait pas dans les `AllowedIPs` de LYO1. Correctif : `AllowedIPs` couvre tous les réseaux de PAR1 que la politique de E19 autorise (pas tout 10.10.0.0/16 si l'on veut que le tunnel refuse aussi MGMT : la cohérence entre `AllowedIPs` et la politique BGP est une décision à écrire dans l'ADR de E19). Prévention : générer `AllowedIPs` et la prefix-list d'annonce à partir de la **même** variable de l'inventaire.

**Variante 3 — route-map d'entrée remplacée par celle de sortie.**

```
root@lyo-gw01:~# vtysh -c 'show bgp ipv4 unicast summary' | grep 10.255.2.1
10.255.2.1      4 65000   …  01:02:03            0        2 N/A
root@lyo-gw01:~# vtysh -c 'show running-config' | grep 'route-map'
  neighbor 10.255.2.1 route-map LYO1-OUT in
  neighbor 10.255.2.1 route-map LYO1-OUT out
root@lyo-gw01:~# ip route get 10.10.20.1
10.10.20.1 via 10.10.99.1 dev eth0 …         ← la route par défaut « Internet » de l'agence
```

Session établie, 0 préfixe accepté : la politique d'entrée est celle qui autorise les réseaux de **Lyon** (10.30.0.0/16) et refuse le reste, donc tout ce que Paris annonce. Le paquet vers 10.10.20.1 part par la route par défaut (« Internet »), en clair, et n'arrive nulle part — une **fuite** que la sonde n'a pas vue : à noter au post-mortem. Correctif : rétablir `route-map PAR1-IN in` (le nom exact de ton rôle) puis `clear bgp 10.255.2.1 soft in`. Prévention : nommer les route-maps par sens et par pair (`RM-LYO1-DEPUIS-PAR1`, `RM-LYO1-VERS-PAR1`) et faire vérifier par Molecule qu'une route de PAR1 au moins est acceptée ; une route de **refus** explicite (`ip route 10.10.0.0/16 blackhole 250`) empêcherait la fuite par la route par défaut.

**Variante 4 — relais IP désactivé par un « durcissement CIS ».**

```
root@lyo-gw01:~# ping -c 1 10.10.20.1          ← fonctionne
root@lyo-gw01:~# sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 0
root@lyo-gw01:~# grep -rn ip_forward /etc/sysctl.conf /etc/sysctl.d/
/etc/sysctl.d/99-cis-durcissement.conf:1:net.ipv4.ip_forward = 0
root@lyo-gw01:~# nstat -az | grep -i forw
IpForwarding                    2                  0.0
```

Le routeur joint Paris, les postes non : le relais est coupé. Les guides CIS recommandent `ip_forward = 0`… **pour un hôte qui n'est pas un routeur**. Le fichier `99-…` est lu après celui du rôle (`/etc/sysctl.d/` est lu dans l'ordre lexicographique, le dernier réglage l'emporte) : même corrigé par `sysctl -w`, le défaut reviendrait au redémarrage. Correctif : supprimer le fichier, `sysctl --system` (ou `sysctl -w net.ipv4.ip_forward=1`), et faire porter par le rôle de l'agence un fichier qui gagne l'ordre (`zz-routeur.conf`) ou, mieux, un contrôle qui échoue si une autre source désactive le relais. Prévention : un profil de durcissement **par rôle** (routeur, serveur), jamais un guide appliqué à l'aveugle.

**Vérification** : `lab/bin/check 07 36` ; `lab/bin/break 07 36 --annuler`.

**Explications**

Un tunnel WireGuard est une interface : le noyau y envoie un paquet parce qu'une **route** le dit ; WireGuard l'accepte s'il trouve un pair dont les `AllowedIPs` couvrent la destination, le chiffre pour ce pair et l'envoie à son extrémité ; à l'arrivée, il n'accepte le paquet déchiffré que si sa source est dans les `AllowedIPs` du pair qui l'a chiffré. La poignée de main est renouvelée toutes les deux minutes environ quand il y a du trafic. Quatre maillons, quatre pannes distinctes, et une seule mesure (`ping` depuis le poste) qui ne les sépare pas : il faut les mesures de l'étape 1.

**Alternatives**
- `Table = off` et routes uniquement par BGP (ce que fait E19) contre routes posées par `wg-quick` (E18) : avec BGP, `AllowedIPs` peut être large (0.0.0.0/0) puisque le routage décide… à condition d'accepter qu'un pair puisse alors usurper n'importe quelle source.
- `PersistentKeepalive` côté agence pour maintenir l'état NAT d'une box Internet (inutile dans la maquette, utile en vrai).

**Pièges classiques**
- Tester seulement depuis `lyo-gw01` : la variante 4 est invisible.
- Confondre « la poignée de main est récente » et « le trafic passe » (variante 2).
- Redémarrer `wg-quick@wg2` : coupe la session BGP et efface les compteurs qui servaient de preuve.
- Corriger un `sysctl -w` sans supprimer le fichier qui le force.

**En production chez MédiSphère**
Sonde « depuis l'agence » (requête applicative depuis un poste de LYO1, par l'agent) en plus des sondes d'infrastructure (poignée de main de moins de 3 min, session BGP, nombre de préfixes reçus) ; génération de `AllowedIPs` et des prefix-lists depuis une même source ; la route de refus pour ne jamais fuir vers Internet. Runbook : `corrige/fichiers/M07-E36/medisphere/docs/socle/runbooks/RB-074-site-distant.md`.

---

### M07-E37 — Panne : deux maîtres VRRP

**Démarche de diagnostic**

*Symptôme* : la VIP est portée par les deux membres d'une paire (`srv01`/`srv02` pour les variantes 1 et 2, `lb01`/`lb02` pour la variante 3).

*Hypothèses* : un membre n'émet pas ; il émet vers la mauvaise destination ; il émet mais l'autre ne reçoit pas (filtrage) ; l'autre reçoit mais ignore (VRID, version, authentification, adresse attendue) ; les deux membres ne sont pas sur le même segment.

**Étape 1 — Le *split-brain* vu d'un tiers.**

```
root@hap01:~# for i in 1 2 3 4 5; do arping -c 1 -I eth0 10.10.99.240 | grep reply; sleep 2; done
Unicast reply from 10.10.99.240 [BC:24:11:AA:00:75]  0.6ms
Unicast reply from 10.10.99.240 [BC:24:11:AA:00:76]  0.7ms    ← deux machines répondent
root@hap01:~# for i in $(seq 5); do curl -s http://10.10.99.240/ | grep -o 'srv0[12]'; sleep 3; done
```

(Pour la paire `lb`, depuis `adm01` : `ip neigh show 10.10.70.200` en boucle sur la passerelle active, en lecture.)

**Étape 2 — Le tableau des annonces.** Sur chaque membre, simultanément :

```
root@srv01:~# timeout 10 tcpdump -ni eth0 -vv vrrp
root@srv02:~# timeout 10 tcpdump -ni eth0 -vv vrrp
root@srv02:~# journalctl -u keepalived --since -1h --no-pager | grep -E 'STATE|VRID|vrid|ignor'
```

| | émet (src → dst) | VRID / prio | reçoit de l'autre |
|---|---|---|---|
| exemple sain | `srv01` → 224.0.0.18 (ou l'adresse de `srv02`) | 199 / 150 | `srv02` reçoit, reste BACKUP |

**Variante 1 — VRRP jeté par un filtrage local sur le membre BACKUP.** `tcpdump` sur `srv02` **voit** arriver les annonces de `srv01` (`tcpdump` capture avant le filtrage d'entrée), et pourtant `srv02` est passé maître (`Entering MASTER STATE` au moment de la panne).

```
root@srv02:~# nft list ruleset
table inet durcissement {
	chain entree {
		type filter hook input priority -10; policy accept;
		ip protocol vrrp counter packets 412 bytes 16480 drop comment "audit SEC : protocoles non documentes"
```

Les compteurs avancent d'une annonce par seconde. Le maître (`srv01`) reçoit bien les annonces de `srv02` (priorité 100 < 150) et reste maître : deux maîtres. Correctif : retirer la table, constater le retour de `srv02` en BACKUP (`Entering BACKUP STATE`). Sur un hôte dont le pare-feu est géré (rôle `pare_feu_local`), VRRP doit être un flux de la matrice (protocole 112, source = l'autre membre).

**Variante 2 — VRID différent.** Les deux membres émettent ; chacun voit les annonces de l'autre dans `tcpdump`, avec un VRID différent du sien :

```
root@srv02:~# tcpdump -ni eth0 -c 4 -vv vrrp
… 10.10.99.252 > 224.0.0.18: VRRPv3, Advertisement, vrid 199, prio 150, intvl 100cs, length 12
… 10.10.99.253 > 224.0.0.18: VRRPv3, Advertisement, vrid 198, prio 100, intvl 100cs, length 12
root@srv02:~# grep -rn virtual_router_id /etc/keepalived/
/etc/keepalived/keepalived.conf:6:    virtual_router_id 198
```

Pour keepalived, une annonce d'un autre VRID concerne un **autre** routeur virtuel : il l'ignore (selon le niveau de journal, une ligne sur un VRID inconnu ou rien du tout). Deux routeurs virtuels différents revendiquent la même adresse : deux maîtres, ARP qui alterne. Correctif : VRID 199 par le rôle `keepalived` (le VRID doit venir d'une **seule** variable de groupe, pas de chaque `host_vars`). Pourquoi keepalived « n'a rien dit » : de son point de vue, tout est normal — chaque instance est seule dans son routeur virtuel et maître légitime.

**Variante 3 — `unicast_peer` faux sur le répartiteur maître.** `tcpdump` sur `lb01` montre ses annonces partir vers **10.10.70.12** ; sur `lb02`, aucune annonce de `lb01` n'arrive, et `lb02` est passé maître ; `lb01` reçoit celles de `lb02` (priorité inférieure) et reste maître.

```
admin@lb01:~$ sudo timeout 10 tcpdump -ni ens18 -vv vrrp
… 10.10.70.10 > 10.10.70.12: VRRPv3, Advertisement, vrid 170, prio 150, …
… 10.10.70.11 > 10.10.70.10: VRRPv3, Advertisement, vrid 170, prio 100, …
admin@lb01:~$ sudo grep -A3 unicast_peer /etc/keepalived/keepalived.conf
```

Correctif : la bonne adresse par le rôle (`unicast_peer` construit à partir de l'inventaire du groupe `role_lb` : `{{ groups['role_lb'] | difference([inventory_hostname]) | map('extract', hostvars, 'ansible_host') }}`), puis `systemctl reload keepalived`. ⚠️ Avant : instantanés des deux répartiteurs. Après : bascule contrôlée (RB-070) pour prouver que la redondance fonctionne de nouveau.

**Vérification** : `lab/bin/check 07 37` ; `lab/bin/break 07 37 --annuler`.

**Explications**

Un membre VRRP devient maître quand il n'a reçu, pendant *Master_Down_Interval* (3 × l'intervalle d'annonce + un délai d'asymétrie fonction de la priorité, RFC 9568 §6.1), **aucune** annonce valide pour son VRID d'un membre de priorité supérieure ou égale. Il suffit donc qu'un **seul** sens soit coupé (le maître vers le backup) pour obtenir deux maîtres ; le maître, lui, entend le backup et n'a aucune raison de céder. Sans `use_vmac`, chaque maître répond à l'ARP pour la VIP avec **sa** propre adresse matérielle et émet des ARP gratuits à sa prise de fonction : les clients basculent d'un maître à l'autre au gré des ARP, d'où les connexions coupées (les tables `conntrack` et les sessions TLS sont sur l'un, les paquets suivants arrivent sur l'autre).

**Alternatives**
- `use_vmac` (adresse matérielle virtuelle 00:00:5e:00:01:<VRID>) : l'adresse ne change plus à la bascule… et, en *split-brain*, le pont voit la même adresse matérielle sur deux ports (table de commutation instable) : la panne est plus visible, pas évitée.
- `track_script` qui vérifie que l'autre membre est joignable par un second chemin et se met en `FAULT` en cas de doute (au prix d'un risque de « zéro maître »).
- Pacemaker/Corosync avec quorum et *fencing* (STONITH) pour les services où deux maîtres sont pires qu'aucun (stockage partagé).

**Pièges classiques**
- Croire `tcpdump` sur la réception : il capture **avant** nftables.
- Corriger en arrêtant keepalived sur un membre : un seul maître, mais plus de redondance (et la panne revient à son redémarrage).
- VRID choisi par machine dans `host_vars` : le défaut le plus fréquent en production.
- Oublier qu'un VRID est unique **par segment** : deux paires différentes du même VLAN avec le même VRID se battent (voir le VRID 199 de la maquette, choisi pour ne pas heurter le VRID 99 des passerelles).

**En production chez MédiSphère**
Sonde « exactement un maître par VIP » dans `ms-verif-reseau` (à partir de l'état publié par un script `notify` de chaque membre, et d'un `arping` depuis un tiers), alerte immédiate ; VRID et VIP déclarés une fois par paire dans l'inventaire ; VRRP dans la matrice des flux ; bascule contrôlée après toute modification. Runbook : `corrige/fichiers/M07-E37/medisphere/docs/socle/runbooks/RB-075-deux-maitres-vrrp.md`.

---

### M07-E38 — Panne : les gros transferts se figent

**Démarche de diagnostic**

*Symptôme* : petite page instantanée, téléchargement de 8 Mio bloqué à 0 octet ; ping et SSH fonctionnent.

*Hypothèses* : trou noir de la PMTUD (MTU réduit quelque part, ICMP « fragmentation nécessaire » perdu) ; MTU incohérent sur un lien ; problème de fenêtre ou de déchargement (TSO/GRO) ; problème applicatif (fichier, droits).

**Étape 1 — Côté émetteur des données (`srv02`).**

```
root@srv01:~# curl -o /dev/null --max-time 20 --interface 10.10.255.21 http://10.10.255.22/export-nuit.bin &
root@srv02:~# tcpdump -ni any -c 30 'host 10.10.255.21 and tcp port 80'
… 10.10.255.21.51522 > 10.10.255.22.80: Flags [S], … options [mss 1460,…]
… 10.10.255.22.80 > 10.10.255.21.51522: Flags [S.], … options [mss 1460,…]
… 10.10.255.21.51522 > 10.10.255.22.80: Flags [.], ack 1
… 10.10.255.21.51522 > 10.10.255.22.80: Flags [P.], … length 98          ← la requête GET
… 10.10.255.22.80 > 10.10.255.21.51522: Flags [.], … length 1448       ← segments pleins…
… 10.10.255.22.80 > 10.10.255.21.51522: Flags [.], … length 1448       ← … retransmis, jamais acquittés
```

Poignée de main et requête correctes, premiers segments pleins (1500 octets en IP) jamais acquittés : signature d'un trou noir de MTU. Une petite réponse tient dans un segment court, d'où la page d'accueil qui passe.

**Étape 2 — Le MTU du chemin, sans TCP.**

```
root@srv02:~# ping -M do -s 1472 -c 2 -I 10.10.255.22 10.10.255.21      ← silence
root@srv02:~# ping -M do -s 1372 -c 2 -I 10.10.255.22 10.10.255.21      ← réponses
root@leaf02:~# ip -br link | awk '{ print $1 }' | xargs -I{} sh -c 'printf "%s " {}; cat /sys/class/net/{}/mtu'
root@spine01:~# … même chose
```

Le chemin passe 1400 octets, pas 1500 : les liens leaf-spine ont été passés à 1400 aux deux extrémités (la préparation de l'encapsulation), **sans incohérence** entre extrémités. C'est un changement légitime : le routeur dont l'interface de sortie est trop petite (`leaf02` pour les données de `srv02`) doit émettre un ICMP type 3 code 4 (« fragmentation nécessaire », MTU suivant = 1400) vers `srv02`, qui réduit alors son MTU de chemin et retransmet en segments de 1360 octets. Le silence de `ping -M do` dit que cet ICMP n'arrive pas.

**Étape 3 — Où disparaît l'ICMP ?** Capture simultanée sur `leaf02` (interface vers `srv02`) et sur `srv02` :

```
root@leaf02:~# tcpdump -ni <interface vers srv02> -c 5 'icmp[icmptype] == 3'
root@srv02:~# tcpdump -ni <interface de fabric> -c 5 'icmp[icmptype] == 3'
```

**Variante 1 — `leaf02` (et `leaf01`) jettent les ICMP qu'ils émettent.** Rien dans aucune des deux captures ; sur `leaf02` :

```
root@leaf02:~# nft list ruleset
table inet durcissement {
	chain sortie {
		type filter hook output priority -10; policy accept;
		icmp type destination-unreachable icmp code frag-needed counter packets 58 bytes 33640 drop comment "limiter les ICMP emis"
```

L'ICMP est généré localement par `leaf02` (chaîne `output`, pas `forward`) et jeté avant de partir. Correctif : retirer la table. « Limiter les ICMP émis » est le travail de `net.ipv4.icmp_ratelimit` et `icmp_ratemask`, qui épargnent justement la PMTUD ; jeter les « fragmentation nécessaire » n'est jamais une mesure de sécurité acceptable.

**Variante 2 — `srv01`/`srv02` n'acceptent que l'écho.** L'ICMP est vu sur `leaf02` **et** dans la capture de `srv02` (qui capture avant le filtrage), mais `srv02` ne réduit pas son MTU de chemin (`ip route get 10.10.255.21` ne montre pas de `mtu 1400` en cache) :

```
root@srv02:~# nft list ruleset | grep -A4 'chain entree'
		icmp type { echo-request, echo-reply } accept
		ip protocol icmp counter packets 61 bytes 35380 drop comment "ICMP : echo seulement"
root@srv02:~# ip route get 10.10.255.21
10.10.255.21 via … dev eth1 src 10.10.255.22 uid 0
    cache                 ← pas d'« expires … mtu 1400 »
```

Correctif : retirer la règle ; si un filtrage d'ICMP est exigé, il garde au minimum `destination-unreachable`, `time-exceeded`, `parameter-problem` (et en IPv6 `packet-too-big`, indispensable : IPv6 ne fragmente jamais en route).

**Variante 3 — pare-feu d'hôte à états sans `related`.** Même observation qu'en variante 2, mais la table est un vrai pare-feu d'entrée en politique `drop` :

```
root@srv02:~# nft list table inet filtre_hote
	chain entree {
		type filter hook input priority -10; policy drop;
		ct state established accept
		…
		counter packets 64 bytes 37120 comment "rejete par la politique"
root@srv02:~# conntrack -L -p icmp 2>/dev/null | head      # (paquet conntrack) : rien de pertinent
```

L'ICMP « fragmentation nécessaire » se rapporte à une connexion existante : `conntrack` le classe `related`, pas `established`. La règle `ct state established accept` le laisse tomber dans la politique `drop`. Correctif : `ct state { established, related } accept` (ce que font les rôles `pare_feu` et `pare_feu_local` du workbook). Ce pare-feu ne vient d'aucun rôle : il est à retirer, ou à reprendre dans `pare_feu_local` avec les flux de la maquette.

**Le débat de l'étape 4.** Revenir à 1500 sur la fabric « répare » aussi (plus besoin de PMTUD), mais masque les trois défauts, qui ressortiront à la première encapsulation, au premier tunnel ou au premier lien de MTU différent. La bonne réponse : garder le MTU choisi (s'il est voulu et **cohérent aux deux extrémités**), rétablir la PMTUD, et ajouter un filet : `tcp option maxseg size set rt mtu` (*MSS clamping*) sur les leaves pour le trafic TCP qui les traverse, et/ou `net.ipv4.tcp_mtu_probing = 1` sur les serveurs (sondage du MTU par la couche transport, RFC 4821, qui ne dépend plus des ICMP).

**Étape 5 — Ce qui aurait détecté le problème avant la mise en production** : `ping -M do -s 1472` de boucle à boucle dans les deux sens après le changement de MTU (succès **ou** message « mtu = 1400 », jamais le silence) ; `tracepath -n 10.10.255.22` (qui affiche le MTU découvert à chaque saut) ; un transfert de taille réelle dans la recette du changement.

**Vérification** : `lab/bin/check 07 38` ; `lab/bin/break 07 38 --annuler` (remet aussi les liens de fabric à leur MTU d'origine s'ils sont encore à 1400 et retire le fichier de test).

**Explications**

TCP négocie la taille de segment (MSS) d'après le MTU des **interfaces des deux extrémités** ; il ignore tout des liens intermédiaires. Quand un lien intermédiaire est plus étroit, IPv4 avec le bit DF (posé par défaut par Linux pour TCP) compte sur le routeur pour signaler le dépassement (RFC 1191). Si l'ICMP est perdu, l'émetteur retransmet indéfiniment des segments trop gros : la connexion « fige ». Les petits échanges (poignée de main, requête, page courte, SSH interactif, ping par défaut) passent, ce qui rend la panne déroutante. La RFC 2923 décrit ce trou noir depuis 2000.

**Alternatives**
- MTU uniforme et maximal partout (*jumbo* de bout en bout), ce que fait MédiSphère sur les VLAN 30/31/51 : réduit le besoin de PMTUD, ne le supprime pas (les tunnels).
- *MSS clamping* aux frontières (sur la bordure pour les tunnels WireGuard, par exemple) : ne protège que TCP.
- Sondage par la couche transport (RFC 4821/8899) : robuste, mais plus lent à converger.

**Pièges classiques**
- Tester avec `ping` sans `-M do` et sans taille : il passe toujours.
- Chercher l'ICMP dans la chaîne `forward` du routeur : il est **émis** par le routeur (`output`).
- Croire la capture de l'émetteur : l'ICMP y apparaît même s'il est jeté ensuite par son pare-feu.
- Corriger en baissant le MTU des serveurs : MSS plus petit, ça « marche », et le prochain chemin plus étroit refait la panne.

**En production chez MédiSphère**
Recette de tout changement de MTU : `ping -M do` aux tailles limites dans les deux sens, `tracepath`, transfert réel ; règle de matrice des flux « ICMP d'erreur toujours autorisé » (types 3, 11, 12 en IPv4 ; 1, 2, 3, 4 en IPv6) ; `related` dans tout pare-feu à états ; sonde PMTUD dans `ms-verif-reseau` sur les chemins de stockage (VLAN 30/31). Runbook : `corrige/fichiers/M07-E38/medisphere/docs/socle/runbooks/RB-076-mtu-pmtud.md`.

---

### M07-E39 — Panne : 503 Service Unavailable

**Démarche de diagnostic**

*Symptôme* : `hap01` répond 503 à tout ; les serveurs sont allumés.

*Hypothèses* : tous les serveurs du backend sont considérés hors service (contrôle de santé), en maintenance, ou saturés (`maxconn` et file d'attente pleine) ; le 503 vient d'un serveur et non de HAProxy.

**Étape 1 — Qui répond 503 ?**

```
admin@adm01:~$ curl -si http://hap01.par1.medisphere.internal/ | head -n 5
HTTP/1.1 503 Service Unavailable
content-length: 107
cache-control: no-cache
content-type: text/html
root@hap01:~# journalctl -u haproxy --since -1h --no-pager | grep -E 'is DOWN|no server available'
… Server be_web/srv01 is DOWN, reason: Layer7 wrong status, code: 404, info: "Not Found", check duration: 1ms. …
… backend be_web has no server available!
```

La page d'erreur intégrée de HAProxy (« No server is available to handle this request ») et le journal le prouvent : c'est HAProxy, et aucun serveur n'est disponible.

**Étape 2 — L'état par la socket d'administration.**

```
root@hap01:~# apt-get install -y socat     # si absent
root@hap01:~# echo "show stat" | socat stdio /run/haproxy/admin.sock | cut -d, -f1,2,18,37,38 | column -ts,
# pxname  svname  status  check_status  check_code
be_web    srv01   DOWN    L7STS         404
be_web    srv02   DOWN    L7STS         404
```

Le `check_status` désigne la couche ; l'étape 3 rejoue le contrôle **exactement** pour le confirmer.

**Variante 1 — `check-ssl` ajouté (couche 6).** `check_status` = `L6RSP` (ou `L6TOUT`) : HAProxy ouvre une session TLS vers des serveurs qui parlent HTTP en clair.

```
root@hap01:~# grep -n '^ *server' /etc/haproxy/haproxy.cfg
    server srv01 srv01.par1.medisphere.internal:80 check check-ssl verify required ca-file /etc/ssl/certs/ca-certificates.crt
root@hap01:~# openssl s_client -connect srv01.par1.medisphere.internal:80 </dev/null 2>&1 | head -n 3
… wrong version number …
```

Lucas a préparé le ré-chiffrement (bonne intention, M07-E13) en commençant par les contrôles, sans TLS côté serveur. Correctif : retirer `check-ssl …` par le rôle `haproxy` (`host_vars/hap01/haproxy.yml`). Le ré-chiffrement se fait en **une** modification cohérente : TLS sur le serveur (certificat ACME), puis `ssl verify required ca-file <racine MédiSphère> sni str(<nom>)` sur la ligne `server` (le contrôle suit alors le trafic). Note : la racine à utiliser est celle de MédiSphère (`haproxy_racine_ca`), pas le magasin public.

**Variante 2 — URI de contrôle fausse (couche 7, 404).** `check_status` = `L7STS`, `check_code` = 404 :

```
root@hap01:~# grep -n 'http-check' /etc/haproxy/haproxy.cfg
    http-check send meth GET uri /etat ver HTTP/1.1 hdr Host hap01.par1.medisphere.internal
root@hap01:~# curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: hap01.par1.medisphere.internal' http://srv01.par1.medisphere.internal/etat
404
```

Correctif : `/sante` par le rôle. Prévention : le chemin du point de santé est une variable **partagée** entre le rôle `nginx_web` (qui le sert) et le rôle `haproxy` (qui l'interroge).

**Variante 3 — Nginx n'écoute plus que sur la boucle locale (couche 4).** `check_status` = `L4CON` (« Connection refused ») :

```
root@srv01:~# ss -tlnp 'sport = :80'
LISTEN 0 511 127.0.0.1:80 0.0.0.0:* users:(("nginx",…))
root@srv01:~# grep -rn listen /etc/nginx/sites-enabled/
… listen 127.0.0.1:80 default_server;
```

Le « durcissement » d'InfoGér a restreint l'écoute. Correctif : le rôle `nginx_web` (`nginx_web_port`), `nginx -t`, `systemctl reload nginx`. Remarque : la page de la VIP de E08 était cassée aussi ; une sonde HTTP sur chaque serveur **par son adresse** l'aurait vu avant la répartition.

**Variante 4 — fichier de maintenance oublié (couche 7, 503 du serveur).** `check_status` = `L7STS`, `check_code` = 503 :

```
root@srv01:~# curl -si http://127.0.0.1/sante
HTTP/1.1 503 Service Temporarily Unavailable
maintenance
root@srv01:~# ls -l /var/www/maintenance
-rw-r--r-- 1 root root 32 … /var/www/maintenance
```

La procédure de RB-070 retire un serveur de la répartition en posant ce fichier ; personne ne l'a retiré, sur les deux serveurs. Correctif : supprimer le fichier (après avoir vérifié qu'aucune maintenance n'est en cours !). Prévention : RB-070 se termine par « retirer le fichier et vérifier `UP` dans `show stat` » ; le fichier contient la date et le nom de l'intervenant ; une sonde alerte sur un fichier de maintenance de plus de 4 heures.

**Étape 4 — Recharger sans couper.** `haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy` : le processus maître lance de nouveaux processus avec la nouvelle configuration, les anciens finissent leurs connexions (le rôle le fait par son *handler*). Pour une action ponctuelle sur un serveur, la socket suffit (`set server be_web/srv01 state ready`), sans rechargement.

**Vérification** : `lab/bin/check 07 39` ; `lab/bin/break 07 39 --annuler`.

**Explications**

HAProxy répond 503 quand il ne trouve aucun serveur utilisable pour la requête : tous `DOWN` (contrôles de santé), en `MAINT`, ou saturés au-delà de la file d'attente. 502 : un serveur a répondu quelque chose d'invalide (ou a fermé) ; 504 : un serveur n'a pas répondu dans `timeout server`. Les codes `check_status` disent à quelle étape le contrôle échoue : `L4CON`/`L4TOUT` (TCP), `L6RSP`/`L6TOUT` (TLS), `L7RSP`/`L7STS`/`L7TOUT` (réponse HTTP), `L7OKC` (réponse correcte mais conditionnelle).

**Alternatives**
- `option redispatch` + `retries` : utile quand **un** serveur tombe, inutile quand tous sont `DOWN`.
- Un serveur de secours (`backup`) qui sert une page de maintenance : un 503 « propre » et documenté plutôt qu'une erreur brute.
- `agent-check` : le serveur annonce lui-même son poids ou son état (drain), sans fichier.

**Pièges classiques**
- Tester les serveurs avec `curl http://srv01/` : ce n'est pas la requête du contrôle (chemin, `Host`, TLS, port).
- Redémarrer HAProxy (coupure) au lieu de recharger.
- Désactiver le contrôle de santé « pour que ça marche » : on envoie alors du trafic à des serveurs morts.

**En production chez MédiSphère**
Sonde par backend « au moins N serveurs `UP` » (export de la page de statistiques pour le module 21), alerte sur tout passage `DOWN` ; variables partagées entre rôles (port, chemin de santé) ; procédures de maintenance qui se ferment d'elles-mêmes (fichier daté, sonde d'âge). Runbook : `corrige/fichiers/M07-E39/medisphere/docs/socle/runbooks/RB-077-repartiteur-503.md`.

---

### M07-E40 — Panne : l'agrégat a perdu un lien

**Démarche de diagnostic**

*Symptôme* : l'agrégateur actif du bond 802.3ad de `net01` n'a plus qu'un port.

*Hypothèses* : un membre a perdu la porteuse (lien coupé, extrémité désactivée) ; un membre est sorti du bond ; la négociation LACP échoue (partenaire muet, clé ou système différents) ; `miimon` absent (une panne non détectée laisserait au contraire **deux** ports « actifs » dont un mort).

**Étape 1 — Les deux côtés.**

```
root@net01:~# ip netns list
root@net01:~# ip netns exec ns-srv cat /proc/net/bonding/bond0
root@net01:~# ovs-appctl bond/show
root@net01:~# ovs-appctl lacp/show
```

Dans `/proc/net/bonding/bond0`, à comparer membre par membre : `MII Status`, `Aggregator ID`, `Partner Mac Address`, `details partner lacp pdu` (`system mac address`, `oper key`, `port state`).

**Variante 1 — extrémité « commutateur » d'une paire veth désactivée.**

```
root@net01:~# ip netns exec ns-srv cat /proc/net/bonding/bond0 | grep -A2 'Slave Interface'
Slave Interface: vsrv2
MII Status: down
Link Failure Count: 1
root@net01:~# ip -n ns-srv -o link show vsrv2
… vsrv2@if12: <NO-CARRIER,BROADCAST,MULTICAST,SLAVE,UP> … state LOWERLAYERDOWN …
root@net01:~# ip -n ns-sw -o link | grep '^12:'          # ou l'espace de noms initial, selon ta construction de E17
12: vsw2@if11: <BROADCAST,MULTICAST> mtu 1500 … state DOWN …
```

Le membre côté serveur est administrativement `UP` mais sans porteuse : c'est l'autre extrémité qui est `DOWN` (pas de `UP` dans ses drapeaux). Équivalent physique : câble débranché ou port du commutateur en `shutdown`. Correctif : `ip -n ns-sw link set vsw2 up` (ou sans `-n` si l'extrémité est dans l'espace de noms initial) ; vérifier que le script ou l'unité qui monte `net01` (M07-E17) l'aurait fait au démarrage. Un vrai commutateur afficherait le port `down` (ou `disabled`) et l'agrégat avec un seul membre `bundled`.

**Variante 2 — LACP désactivé côté Open vSwitch.**

```
root@net01:~# ovs-vsctl list port <bond-ovs> | grep -E '^(name|lacp|bond_mode)'
lacp                : off
bond_mode           : []
root@net01:~# ovs-appctl lacp/show
(rien pour ce port)
root@net01:~# ip netns exec ns-srv grep -E 'Aggregator ID|Partner Mac' /proc/net/bonding/bond0
        Aggregator ID: 1
        Partner Mac Address: 00:00:00:00:00:00
Aggregator ID: 1
Aggregator ID: 2
```

Plus de LACPDU du côté commutateur : le bond Linux, après expiration du partenaire, met chaque membre dans son propre agrégateur (partenaire inconnu) et n'en utilise qu'un. Côté Open vSwitch, le port est revenu en `active-backup` par défaut. Correctif : `ovs-vsctl set port <bond-ovs> lacp=active` (enregistré dans la base : survit au redémarrage, c'est aussi pour cela que la panne y survivait). Un vrai commutateur montrerait ses ports en `suspended`/`individual` (« not receiving LACPDUs » côté serveur, ou l'inverse).

**Variante 3 — membre retiré du bond.**

```
root@net01:~# ip netns exec ns-srv cat /sys/class/net/bond0/bonding/slaves
vsrv1
root@net01:~# ip -n ns-srv -d link show vsrv2 | head -n 2
… vsrv2@if12: <BROADCAST,MULTICAST,UP,LOWER_UP> … state UP …        ← pas de « master bond0 »
```

Le lien est en parfait état, simplement hors de l'agrégat. Correctif : `ip -n ns-srv link set vsrv2 down; ip -n ns-srv link set vsrv2 master bond0; ip -n ns-srv link set vsrv2 up` (un membre doit être `down` pour être asservi). Côté commutateur réel : le port de l'agrégat ne reçoit plus de LACPDU et passe `suspended` ; selon la configuration, il peut aussi repasser en port indépendant et créer une boucle si l'autre côté n'est pas un bond… c'est le rôle de LACP de l'empêcher.

**Vérification** : `lab/bin/check 07 40` ; `lab/bin/break 07 40 --annuler`. Pour prouver la répartition, plusieurs flux à travers l'agrégat et les compteurs `ip -s link` des deux membres qui avancent (avec un hachage `layer3+4`, un flux unique ne passe que par un membre).

**Explications**

802.3ad (802.1AX) regroupe des ports **qui ont le même partenaire** (même identifiant de système et même clé) dans un agrégateur ; les LACPDU (toutes les secondes en `fast`, toutes les 30 s en `slow`) servent à la fois à découvrir ce partenaire et à vérifier que le lien est vivant dans les deux sens. `miimon` surveille la porteuse localement. Les trois variantes donnent le même symptôme (« un seul port ») pour trois raisons différentes ; seule la lecture des deux côtés les sépare.

**Alternatives**
- `lacp_rate fast` (détection en 3 s) contre `slow` (90 s) : `fast` est préférable dans un centre de données.
- Agrégat statique (`balance-xor`, OVS `balance-slb` sans LACP) : aucune négociation, donc aucune protection contre un câblage croisé ou un port unidirectionnel ; c'est ce que le module pratique entre VMs, faute de LACP à travers le pont de `pve01`.

**Pièges classiques**
- Ne lire que le côté Linux : la cause des variantes 1 et 2 est de l'autre côté.
- Corriger la variante 2 en passant le bond Linux en `balance-xor` : « ça marche », sans détection d'erreur de câblage.
- Oublier que la base d'Open vSwitch est persistante : une erreur `ovs-vsctl` survit au redémarrage, une erreur `ip link` non.

**En production chez MédiSphère**
Sonde « nombre de ports dans l'agrégateur actif = attendu » et « partenaire identique pour tous les membres » sur chaque hyperviseur (module 09) ; même vérification côté commutateurs par leur API ; `lacp_rate fast` par défaut. Runbook : `corrige/fichiers/M07-E40/medisphere/docs/socle/runbooks/RB-078-agregats-lacp.md`.

---

### M07-E41 — Panne : ça part mais ça ne revient pas

**Démarche de diagnostic**

*Symptôme* : `srv01` → `srv02` de boucle à boucle : la requête arrive, `srv02` répond, `srv01` ne reçoit rien.

*Hypothèses* : la réponse ne prend pas le même chemin que la requête (route plus spécifique, règle de routage par politique, route statique sur un routeur) ; elle est jetée en route ou à l'arrivée (filtrage, `rp_filter`, état `conntrack` absent sur un pare-feu à états).

**Étape 1 — Deux captures simultanées.**

```
root@srv02:~# tcpdump -ni any -c 6 'icmp and host 10.10.255.21'
… eth1 In  IP 10.10.255.21 > 10.10.255.22: ICMP echo request …
… eth0 Out IP 10.10.255.22 > 10.10.255.21: ICMP echo reply …        ← la réponse sort par l'administration
root@srv01:~# tcpdump -ni any -c 6 'icmp and host 10.10.255.22'
… eth1 Out IP 10.10.255.21 > 10.10.255.22: ICMP echo request …
… eth0 In  IP 10.10.255.22 > 10.10.255.21: ICMP echo reply …        ← elle arrive… par eth0 (variantes 1 et 2)
```

(`-i any` affiche le sens et l'interface de chaque paquet.) Variantes 1 et 2 : la réponse quitte `srv02` par son interface d'administration et arrive sur celle de `srv01`. Variante 3 : elle quitte `srv02` par la fabric, mais n'atteint jamais `srv01` ; la capture sur `leaf01` la montre arriver… sur son interface du VLAN 99.

**Étape 2 — Le chemin de la réponse, avec la source.**

```
root@srv02:~# ip route get 10.10.255.21 from 10.10.255.22
root@srv02:~# ip rule show
root@leaf02:~# ip route get 10.10.255.21 from 10.10.255.22 iif <interface vers srv02>
root@leaf02:~# vtysh -c 'show ip route 10.10.255.21'
```

**Étape 3 — Qui jette, et la preuve.**

```
root@srv01:~# nstat -az IPReversePathFilter
TcpExtIPReversePathFilter       0                  0.0
root@srv01:~# ping -c 3 -W 1 -I 10.10.255.21 10.10.255.22 >/dev/null; nstat -z IPReversePathFilter
TcpExtIPReversePathFilter       3                  0.0
root@srv01:~# sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.eth0.rp_filter
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.eth0.rp_filter = 2
root@srv01:~# grep -rn rp_filter /etc/sysctl.d/
/etc/sysctl.d/99-durcissement-reseau.conf:1:net.ipv4.conf.all.rp_filter = 1
```

Le filtrage strict par chemin inverse (RFC 3704) jette un paquet si la route **vers sa source** ne sort pas par l'interface où il est arrivé. La valeur effective pour `eth0` est `max(all, eth0) = 1` (strict). La réponse de 10.10.255.22 arrive sur `eth0` alors que la route vers 10.10.255.22 sort par la fabric : jetée, et le seul témoin est ce compteur (aucune règle nftables, aucun journal, sauf `log_martians`).

**Variante 1 — route statique de contournement sur `srv02`.**

```
root@srv02:~# ip route show 10.10.255.21
10.10.255.21 via 10.10.99.252 dev eth0
```

Une route /32 vers la boucle de `srv01` par son adresse d'administration (10.10.99.252), posée à chaud pendant la panne de E38 (« pour contourner la fabric »), oubliée. Plus spécifique que la route de la fabric : elle gagne. Correctif : `ip route del 10.10.255.21/32 via 10.10.99.252` ; elle n'était dans aucun fichier (elle disparaîtrait au redémarrage, ce qui n'est pas une raison pour la laisser).

**Variante 2 — règle de routage par politique sur `srv02`.**

```
root@srv02:~# ip route show 10.10.255.21          ← rien d'anormal dans la table main
root@srv02:~# ip rule show
0:	from all lookup local
1999:	from 10.10.255.22 to 10.10.255.21 lookup 199
32766:	from all lookup main
32767:	from all lookup default
root@srv02:~# ip route show table 199
10.10.255.21 via 10.10.99.252 dev eth0
root@srv02:~# ip route get 10.10.255.21 from 10.10.255.22
10.10.255.21 from 10.10.255.22 via 10.10.99.252 dev eth0 table 199 …
```

Invisible dans `ip route` ; `ip route get … from …` le révèle (il applique les règles). Correctif : `ip rule del priority 1999 ; ip route flush table 199`.

**Variante 3 — route statique FRR sur `leaf02` et `rp_filter` strict sur `leaf01`.**

```
root@leaf02:~# vtysh -c 'show ip route 10.10.255.21'
Routing entry for 10.10.255.21/32
  Known via "static", distance 1, metric 0, best
  * 10.10.99.251, via eth0, weight 1
root@leaf02:~# grep -n 'ip route' /etc/frr/frr.conf
3:ip route 10.10.255.21/32 10.10.99.251
root@leaf01:~# nstat -az IPReversePathFilter ; sysctl net.ipv4.conf.all.rp_filter
```

`leaf02` envoie les réponses destinées à `srv01` vers `leaf01` **par le VLAN 99** (une route statique de distance 1 bat la route BGP de distance 20) ; `leaf01` les reçoit sur son interface du VLAN 99, alors que sa route vers 10.10.255.22 passe par les spines : rejet strict. Correctif : retirer la ligne de `frr.conf` (par le rôle `frr`) et recharger ; puis décider du mode `rp_filter` de `leaf01` (étape 4).

**Étape 4 — Garder le filtrage strict ?** Sur un **serveur** à une interface de données, le mode strict est sain : il empêche l'usurpation d'adresse… à condition que l'administration et les données soient séparées proprement (VRF de gestion, voir « Pour aller plus loin »). Sur un **routeur de fabric** en ECMP, le mode strict est compatible avec l'ECMP (le noyau vérifie toutes les interfaces des chemins égaux) mais pas avec un routage asymétrique voulu ; le mode lâche (2) garde la protection contre les sources impossibles. Sur la **bordure**, avec deux passerelles et VRRP, l'asymétrie est possible pendant une bascule : lâche, et le filtrage d'usurpation se fait explicitement dans nftables (`fib saddr . iif oif missing drop` par interface, ou règles par VLAN).

**Vérification** : `lab/bin/check 07 41` ; `lab/bin/break 07 41 --annuler` (retire aussi le fichier `99-durcissement-reseau.conf` et remet `rp_filter` à sa valeur d'origine s'il porte encore la valeur posée).

**Explications**

Le noyau choisit la route d'un paquet émis d'après la destination **et** la source, en parcourant les règles (`ip rule`) puis les tables ; un paquet relayé, d'après l'interface d'entrée en plus. Rien ne garantit que la réponse suive le chemin de la requête : la symétrie est une propriété de la **configuration**, pas du protocole. Un routage asymétrique fonctionne tant qu'aucun élément ne vérifie la cohérence : `rp_filter` strict, pare-feu à états (qui n'a vu que la moitié de la connexion), NAT.

**Alternatives**
- VRF de gestion sur toutes les VMs : le réseau d'administration n'a plus de route vers les boucles, l'erreur de Lucas devient impossible.
- `rp_filter = 2` partout et filtrage d'usurpation explicite dans nftables (plus lisible, journalisable).

**Pièges classiques**
- `ip route show` au lieu de `ip route get … from …` : la variante 2 reste invisible.
- Passer `rp_filter` à 0 sur `srv01` : le ping revient, le chemin reste asymétrique (et un pare-feu à états sur le chemin le cassera plus tard).
- Oublier le fichier de `/etc/sysctl.d/` : `sysctl -w` ne survit pas au redémarrage, le fichier si.

**En production chez MédiSphère**
Sonde de boucle à boucle **dans les deux sens** ; compteur `IPReversePathFilter` exporté (module 21) ; `log_martians` activé sur les routeurs ; VRF de gestion dans l'image de base des équipements de fabric ; toute route statique dans le code (rôle `frr`), jamais à chaud. Runbook (avec E42) : `corrige/fichiers/M07-E41/medisphere/docs/socle/runbooks/RB-079-fabric-asymetrie-ecmp.md`.

---

### M07-E42 — Panne : la fabric perd la moitié de son trafic

**Démarche de diagnostic**

*Symptôme* : des couples de machines ne se joignent plus (variante 1), ou tout passe par un seul spine (variantes 2 et 3) ; toutes les sessions sont établies.

*Hypothèses* : ECMP perdu à un étage (BGP, zebra, noyau) ; un spine n'apprend plus ou n'annonce plus ; un spine annonce mais ne relaie pas.

**Étape 1 — Matrice de joignabilité et charge par spine.**

```
root@srv01:~# for d in 10.10.255.1 10.10.255.2 10.10.255.11 10.10.255.12 10.10.255.22; do printf '%s ' $d; ping -c 2 -W 1 -I 10.10.255.21 $d >/dev/null && echo ok || echo KO; done
root@leaf01:~# for d in 10.10.255.12 10.10.255.21 10.10.255.22; do printf '%s ' $d; ping -c 2 -W 1 -I 10.10.255.11 $d >/dev/null && echo ok || echo KO; done
root@spine01:~# ip -s -br link ; sleep 30 ; ip -s -br link     # idem sur spine02
```

Un `ping` n'a pas de ports : même avec la politique de hachage 1 (L4) posée en M07-E14, un couple source/destination ICMP prend toujours le même chemin. La matrice est donc **stable** (variante 1 : toujours les mêmes couples en échec), ce qui distingue cette panne d'une perte aléatoire ; les connexions TCP d'un même couple, elles, se répartissent selon leurs ports (certaines passent, d'autres non).

**Étape 2 — Les trois étages sur `leaf01`.**

```
root@leaf01:~# vtysh -c 'show bgp ipv4 unicast 10.10.255.12/32'
root@leaf01:~# vtysh -c 'show ip route 10.10.255.12/32'
root@leaf01:~# ip route show 10.10.255.12
10.10.255.12 nhid 42 proto bgp metric 20
	nexthop via inet6 fe80::…:a1 dev eth1 weight 1
	nexthop via inet6 fe80::…:b2 dev eth2 weight 1
```

**Variante 1 — `spine02` ne relaie plus.** ECMP intact aux trois étages, sessions établies, mais :

```
root@spine02:~# sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 0
root@spine02:~# vtysh -c 'show ip forwarding'
IP forwarding is off
root@spine02:~# grep -rn ip_forward /etc/sysctl.d/
/etc/sysctl.d/99-durcissement.conf:1:net.ipv4.ip_forward = 0
root@spine02:~# nstat -az | grep -E 'IpInAddrErrors|IpForwDatagrams'
```

Le plan de contrôle (BGP) fonctionne et continue d'annoncer `spine02` comme chemin ; le plan de données le jette (le noyau d'un hôte non routeur jette un paquet qui ne lui est pas destiné, compteur `InAddrErrors`). Correctif : supprimer le fichier, `sysctl -w net.ipv4.ip_forward=1`. Pourquoi BGP ne l'a pas retiré : rien ne lie les annonces à la capacité de relayer. Les deux mécanismes de l'étape 5 : **BFD** sur les sessions (il vérifie que le chemin de données répond, pas seulement le processus), et une sonde locale qui retire le routeur de la fabric (`bgp graceful-shutdown`, ou arrêt des annonces) si le relais est désactivé ; plus généralement, un contrôle de configuration (`ip_forward = 1` obligatoire sur le rôle « routeur »).

**Variante 2 — `maximum-paths 1` sur les leaves.**

```
root@leaf01:~# vtysh -c 'show bgp ipv4 unicast 10.10.255.12/32' | grep -E 'best|multipath'
      … valid, external, best (Older Path)                ← un seul chemin, pas de « multipath »
root@leaf01:~# vtysh -c 'show running-config' | grep maximum-paths
  maximum-paths 1
```

BGP connaît les deux chemins mais n'en installe qu'un. Correctif : retirer la ligne (la valeur par défaut de FRR permet l'ECMP) par le rôle `frr`. C'est la panne de « capacité » : rien n'est cassé, la moitié de la fabric ne sert plus, et la première panne de `spine01` coupera tout le trafic le temps de la reconvergence.

**Variante 3 — route-map d'entrée de `spine02` qui refuse tout.**

```
root@spine02:~# vtysh -c 'show bgp ipv4 unicast summary'
Neighbor        V    AS   … State/PfxRcd   PfxSnt
eth1            4 65101   …            0        2
eth2            4 65102   …            0        2
root@spine02:~# vtysh -c 'show route-map' | head
route-map: RM-LEAVES-IN Invoked: 0 Optimization: enabled Processed Change: false
 deny, sequence 1 Invoked 18
```

`spine02` n'accepte plus rien des leaves (une entrée `deny 1` en tête de la route-map d'entrée, « test » oublié) ; il ne peut donc rien leur réannoncer, et chaque leaf n'a plus qu'un chemin. Correctif : retirer l'entrée par le rôle, `clear bgp * soft in`. Le compteur `Invoked` de la séquence fautive est la preuve.

**Vérification** : `lab/bin/check 07 42` ; `lab/bin/break 07 42 --annuler`.

**Explications**

En eBGP, FRR installe plusieurs chemins égaux (même longueur d'AS_PATH, même AS voisin ou `as-path multipath-relax`) jusqu'à `maximum-paths` ; zebra les pousse dans le noyau comme une route à plusieurs sauts ; le noyau choisit un saut par hachage (`fib_multipath_hash_policy` : 0 = adresses, 1 = adresses + ports, 2 = en-têtes internes pour les tunnels). Une panne d'un chemin ne touche donc qu'une fraction **stable** des couples. Le plan de contrôle ne garantit rien sur le plan de données : un équipement peut annoncer une route qu'il ne sait pas relayer.

**Alternatives**
- `fib_multipath_hash_policy = 1` sur les leaves : meilleure répartition des flux d'un même couple de machines (Ceph, réplications).
- BFD sur toutes les sessions de la fabric (FRR `bfdd`, profil court) : une session BGP ne survit pas à un chemin de données mort.
- OSPF/IS-IS dans la fabric à la place de BGP : même problème, même remède (BFD).

**Pièges classiques**
- Conclure « tout va bien » parce que toutes les sessions sont `Established`.
- Tester toujours le même couple : avec un hachage L3, il passe ou il échoue toujours.
- Chercher l'ECMP seulement dans BGP : la variante 2 se voit dans BGP, la 1 nulle part dans le plan de contrôle.

**En production chez MédiSphère**
Sondes « nombre de chemins égaux vers chaque boucle » et « relais actif » sur chaque routeur de fabric ; BFD obligatoire ; compteurs par interface des spines exportés (déséquilibre = alerte) ; matrice de joignabilité de boucle à boucle comme test de recette de tout changement de la fabric. Runbook : `RB-079-fabric-asymetrie-ecmp.md` (commun avec E41).

---

### M07-E43 — Astreinte : la bordure en panne

**Démarche**

1. **Triage** : lister les symptômes affichés, puis vérifier les instruments : SSH vers `gw01`, `gw02`, `lb01`, `lb02` ; agent QEMU de la maquette (`qm guest cmd 2070 ping` … `2079`) ; `ms-verif-reseau` ; puis `lab/bin/check 07 35` à `07 42` pour la carte. **Et** l'état de la bordure, que le ticket ne mentionne qu'indirectement (« redondance dégradée ») :
   ```
   admin@adm01:~$ for h in gw01 gw02; do echo "== $h"; ssh $h 'systemctl is-active keepalived conntrackd frr wg-quick@wg0; ip -br -4 addr | grep -c " 10\.10\.10\.1/"'; done
   ```
   La panne propre à l'astreinte est sur la passerelle de **secours** : keepalived (ou conntrackd) arrêté **et désactivé**. Aucun utilisateur ne la voit ; à 9 h, la bascule planifiée aurait soit échoué (pas de secours : les VIP disparaissent avec la passerelle active), soit coupé toutes les connexions (pas de synchronisation).
2. **Priorisation** : impact **et** risque. Ordre conseillé : (a) la redondance de la bordure (risque maximal à 9 h, correction rapide : `systemctl enable --now keepalived` sur la passerelle de secours… **après** avoir vérifié sa configuration et que sa priorité ne lui fait pas prendre les VIP par préemption au mauvais moment — sinon, le faire dans une fenêtre, en suivant RB-071) ; (b) ce qui touche des utilisateurs réels (LYO1, répartiteurs `lb` si E37 v3) ; (c) la maquette (fabric, MTU, `hap01`, `net01`). Une panne de couche basse (E40, E42, E41) fausse les tests des couches hautes : si la fabric est touchée, réparer la fabric avant de conclure sur BGP ou HAProxy.
3. **Communication** (modèle) : « 07 h 05 — INC-3410 — Statut : en cours. Impact : l'agence de Lyon n'accède plus aux services de Paris ; la bordure n'est plus redondante (bascule de 9 h compromise). Cause : quatre anomalies distinctes, la redondance de la bordure est rétablie en priorité. Prochaine communication : 07 h 35. »
4. **Avant 9 h** : prouver que la bordure **peut** basculer, sans basculer : sur les deux passerelles, keepalived actif et activé, état `BACKUP` sur la secours (`journalctl -u keepalived`), annonces VRRP reçues sur chaque VLAN (`tcpdump -ni ens19.10 -c 3 vrrp` sur la secours), conntrackd actif et synchronisé (`conntrackd -s` : compteurs de la file externe qui avancent), configurations identiques (`--check --diff` des rôles sur les deux), scripts de transition présents et exécutables (tunnels), FRR actif.
5. **Post-mortem** : chronologie horodatée, quatre causes racines et leurs causes contributives (modifications hors du code, « durcissements » appliqués à l'aveugle, maintenance non refermée), détection (qu'est-ce qui aurait dû alerter avant Nadia : sonde « services de la passerelle de secours », sonde « exactement un maître », sonde « depuis l'agence »), actions (responsable, échéance). Exemple : `corrige/fichiers/M07-E43/medisphere/docs/socle/post-mortems/2026-10-13-INC-3410.md`.

**Grille d'auto-évaluation**
- [ ] Les instruments ont été vérifiés avant le diagnostic.
- [ ] La redondance de la bordure a été traitée comme un risque prioritaire, même sans impact visible.
- [ ] L'ordre de traitement est justifié (impact, risque, couches).
- [ ] Chaque correction a été suivie d'une reprise de **tous** les tests de départ.
- [ ] Quatre communications au moins, avec statut, impact, prochaine étape, prochaine heure.
- [ ] Post-mortem sans coupable, causes racines distinctes des déclencheurs, actions vérifiables.

---

### M07-E44 — Sous le capot : le voyage d'un paquet

**Solution**

Le compte rendu d'exemple est dans `corrige/fichiers/M07-E44/medisphere/docs/socle/analyses/voyage-paquet.md`. Les étapes et ce qu'il faut y voir :

**1. Couche 2 sur `pve01`.**

```
root@pve01:~# qm config 1001 | grep ^net0
net0: virtio=BC:24:11:10:01:01,bridge=vmgmt,firewall=0
root@pve01:~# bridge -d vlan show dev tap1001i0
root@pve01:~# bridge fdb show | grep -i bc:24:11:10:01:01
root@pve01:~# tcpdump -eni vmbr1 -c 10 'vlan 10 and host 10.10.10.10 and tcp port 443'
… bc:24:11:10:01:01 > <MAC de la passerelle active>, ethertype 802.1Q (0x8100), length 78: vlan 10, p 0, ethertype IPv4 (0x0800), 10.10.10.10.52344 > 10.10.70.200.443: Flags [S] …
root@pve01:~# tcpdump -eni tap1001i0 -c 3 'tcp port 443'
… bc:24:11:10:01:01 > …, ethertype IPv4 (0x0800) …            ← sans étiquette
```

La carte d'`adm01` est sur la VNet `vmgmt` : la trame entre **sans** étiquette par `tap1001i0` (VLAN natif du port, `PVID Egress Untagged`), reçoit l'étiquette 10 en entrant dans `vmbr1`, voyage étiquetée jusqu'au port de la passerelle (trunk, `ens19` sans étiquette côté Proxmox : la VM reçoit les étiquettes et les traite par ses sous-interfaces `ens19.10`). La table de commutation associe chaque adresse matérielle à un port **et** à un VLAN. Selon la configuration SDN, les VNets apparaissent comme des ponts intermédiaires ; l'essentiel est de suivre l'étiquette.

**2. Résolution.** `ip neigh show 10.10.10.1` sur `adm01` donne l'adresse matérielle **réelle** de la passerelle active (sans `use_vmac`). À la bascule, le nouveau maître émet des ARP gratuits (`garp_master_delay`, `garp_master_repeat`) qui mettent à jour le cache d'`adm01` et la table de commutation du pont.

**3. Routage et trace.**

```
admin@gw01:~$ ip route get 10.10.70.200 from 10.10.10.10 iif ens19.10
10.10.70.200 from 10.10.10.10 dev ens19.70 table main …
admin@gw01:~$ sudo nft -f - <<'EOF'
table inet trace_m07 {
	chain pre {
		type filter hook prerouting priority -350; policy accept;
		ip saddr 10.10.10.10 ip daddr 10.10.70.200 tcp dport 443 meta nftrace set 1
	}
}
EOF
admin@gw01:~$ sudo nft monitor trace
trace id 6a3f… inet trace_m07 pre packet: iif "ens19.10" ip saddr 10.10.10.10 ip daddr 10.10.70.200 … tcp dport 443 tcp flags == syn …
trace id 6a3f… inet trace_m07 pre rule … meta nftrace set 1 (verdict continue)
trace id 6a3f… inet filter forward rule ct state { established, related } accept …       ← paquets suivants
trace id 6a3f… inet filter forward rule ip saddr 10.10.10.0/24 ip daddr 10.10.70.200 tcp dport 443 accept comment "…" (verdict accept)   ← premier paquet
admin@gw01:~$ sudo nft delete table inet trace_m07
```

Le premier paquet (SYN, état `new`) traverse les règles jusqu'à la règle de la matrice qui l'accepte ; les suivants sont acceptés dès la règle `established` : c'est la réponse à la question 2 (et la raison d'être des pare-feu à états : le coût du filtrage est payé une fois par connexion).

**4. `conntrack`.**

```
admin@gw01:~$ sudo conntrack -L -d 10.10.70.200
tcp      6 431999 ESTABLISHED src=10.10.10.10 dst=10.10.70.200 sport=52344 dport=443 src=10.10.70.200 dst=10.10.10.10 sport=443 dport=52344 [ASSURED] mark=0 use=1
admin@gw01:~$ sudo conntrack -L -d 10.10.20.12
tcp      6 431980 ESTABLISHED src=10.10.70.10 dst=10.10.20.12 sport=40112 dport=443 … [ASSURED] …
```

Deux entrées sur la passerelle active pour une page (client → VIP, répartiteur → `git01`), plus celles des répartiteurs eux-mêmes (côté client et côté serveur) et celles de `git01` (s'il filtre localement). `conntrackd` (FTFW) les réplique vers la passerelle de secours à la création, aux changements d'état et à la destruction, avec acquittement et retransmission sur le lien de synchronisation choisi en E27.

**5. Le répartiteur.** `ss -tnp` sur le répartiteur actif montre la connexion entrante (10.10.10.10 → 10.10.70.200:443) et la sortante (10.10.70.10 → 10.10.20.12:443). `git01` voit le répartiteur comme client ; il retrouve l'adresse d'origine dans `X-Forwarded-For` (configuration `trusted_proxies` de GitLab, M07-E13).

**6. Plan de contrôle.**

```
admin@gw01:~$ sudo timeout 20 tcpdump -ni ens19.10 -vv vrrp
… 10.10.10.2 > 10.10.10.3: VRRPv3, Advertisement, vrid 10, prio 150, intvl 100cs, length 12, addrs: 10.10.10.1
admin@gw01:~$ sudo timeout 30 tcpdump -ni ens19.99 'tcp port 179'
admin@gw01:~$ sudo vtysh -c 'show bgp neighbors 10.10.99.251' | grep -E 'Hold time|keepalive'
```

Une annonce VRRP par seconde, en unicast de `.2` vers `.3` ; un KEEPALIVE BGP toutes les `keepalive` secondes (tiers du temps de maintien négocié, le plus petit des deux proposés).

**7. Bascule observée.** Arrêt propre de keepalived sur le répartiteur actif (RB-070) : le second émet 5 ARP gratuits (par défaut), le cache d'`adm01` et la passerelle changent d'adresse matérielle pour 10.10.70.200 ; la connexion HTTPS en cours est coupée (l'état TLS et la connexion TCP étaient sur l'ancien maître), la suivante passe par le nouveau.

**Réponses aux questions d'analyse**
1. Commuté : à chaque traversée de `vmbr1` (`adm01` → passerelle, passerelle → répartiteur, répartiteur → passerelle, passerelle → `git01`, et autant au retour) ; routé deux fois par la passerelle (MGMT → DMZ, DMZ → INFRA) ; filtré à chaque routage (chaîne `forward`) et à l'entrée de chaque hôte qui filtre localement ; deux connexions TCP distinctes, donc deux entrées `conntrack` sur la passerelle (et sur la secours par `conntrackd`), plus celles des répartiteurs.
2. Parce que la décision complète n'est prise que pour le premier paquet (état `new`) ; les suivants sont reconnus par `conntrack` et acceptés par la règle d'état placée en tête.
3. L'adresse matérielle réelle du maître ; une bascule impose des ARP gratuits et laisse quelques secondes d'incertitude pour les clients qui les manquent ; `use_vmac` donne une adresse stable (00:00:5e:00:01:VRID) au prix d'une interface `macvlan` et d'une table de commutation à surveiller.
4. Pour ne pas inonder le LAN maison et les VLAN de multicast, et parce que certains environnements le filtrent ; avec une troisième passerelle, chaque membre doit lister les **deux** autres dans `unicast_peer` (généré depuis l'inventaire).
5. Jusqu'au temps de maintien négocié (9 s avec le profil `datacenter`, 180 s par défaut) ; BFD réduit la détection à moins d'une seconde sans raccourcir dangereusement les temporisateurs BGP.
6. Non, sauf requête déjà terminée : l'état TCP et TLS est sur l'ancien maître ; les tables *stick* synchronisées par `peers` conservent l'affinité et les compteurs, **pas** les connexions TCP elles-mêmes.
7. Étape 1 (`bridge fdb`, VLAN) : E40 et, au-delà du module, une VM sur la mauvaise VNet ; étape 3 (`ip route get … iif`, trace) : E41 (le chemin de retour) et E38 (une règle qui jette un ICMP apparaît dans la trace) ; étape 4 (`conntrack`) : E38 v3 (`related`) ; étape 6 (annonces, KEEPALIVE) : E37 (VRID, destination des annonces) et E35 (absence de KEEPALIVE, segments MD5).

**Pièges classiques**
- Laisser la table de trace en place : le marquage coûte peu, mais `nft monitor trace` oublié dans un `tmux` remplit des journaux.
- Capturer sur `vmbr1` sans filtre : tout le lab, des Go en quelques minutes.
- Insérer une règle de trace dans `inet filter` : une faute de frappe et c'est une règle de filtrage en production.

---

### M07-E45 — Questions expert : réseau et haute disponibilité

**Réponses**

1. Les trames LACP (et STP, 802.1X…) sont envoyées à des adresses du groupe réservé 01:80:c2:00:00:0X, que 802.1D impose à un pont conforme de **ne pas relayer** : elles concernent le lien entre deux équipements adjacents, pas le réseau. Le pont Linux suit la norme (seules certaines adresses sont débloquables par `group_fwd_mask`, pas celle de LACP). Relayer LACP à travers un pont reviendrait à négocier un agrégat avec un équipement qui n'est pas au bout du câble.
2. **b**. Deux agrégateurs et un partenaire nul : aucune LACPDU reçue, le commutateur n'est pas en LACP. a) un câble défectueux donnerait `MII Status: down` sur un membre, pas un partenaire nul sur les deux ; c) `miimon = 0` empêche la détection de porteuse, il ne change pas la négociation ; d) la politique de hachage est locale à chaque côté et n'empêche pas l'agrégation.
3. `active-backup` : aucun besoin côté commutateur, détection par `miimon` (ou ARP), un seul lien utilisé. `balance-xor` : agrégat statique côté commutateur, répartition par hachage, aucune vérification de câblage. `802.3ad` : LACP des deux côtés, répartition par hachage, détection et vérification de cohérence par les LACPDU. Un flux unique ne dépasse jamais le débit d'un lien. Face à un commutateur qui ne suit pas, `active-backup` fonctionne, `balance-xor` crée des pertes ou des boucles, `802.3ad` se replie sur un seul lien (ce qui est voulu).
4. OVS : contrôleur et règles OpenFlow, VLAN et agrégats LACP gérés par le commutateur virtuel (avec `bond/show`, `lacp/show`), tunnels (VXLAN, Geneve), miroirs, intégration OVN (module 10). Coût : un démon et une base de plus, un plan de données à apprendre, des pannes plus difficiles à lire que `bridge`.
5. `Idle` → `Connect` (tentative TCP) → `Active` (attente, nouvelle tentative) → `OpenSent` → `OpenConfirm` → `Established`. Bloqué en `Active` : TCP/179 filtré (capture, compteurs nftables) ou authentification de segment (option MD5 dans la capture, `nstat`) ; bloqué en `OpenSent`/retour à `Idle` : AS faux ou capacité refusée (NOTIFICATION dans `show bgp neighbors`, « Last reset ») ; `Established` sans préfixe : politique absente (`(Policy)`, RFC 8212) ou filtre qui refuse tout (`show route-map`, compteurs `Invoked`).
6. Sans politique explicite en entrée et en sortie, une session eBGP n'accepte ni n'annonce rien. Bonne valeur par défaut : un oubli de filtre ne transforme plus un routeur en relais de tout Internet (fuites de routes). Le profil `datacenter` la désactive parce que dans une fabric où tous les équipements sont sous le même contrôle, les configurations minimales (BGP *unnumbered*, `redistribute connected`) étaient la norme ; MédiSphère la garde active partout (M07-E16).
7. Les routeurs se découvrent par les annonces de routeur IPv6 (adresses *link-local*), ouvrent la session sur l'adresse *link-local* du voisin, et négocient la capacité « extended next-hop » (RFC 5549/8950) : les routes IPv4 sont annoncées avec un prochain saut IPv6 *link-local* ; le noyau installe `nexthop via inet6 fe80::… dev <if>` (et résout l'adresse matérielle par la découverte de voisins).
8. **b**. `spine02` voit 65100 (son propre AS, déjà ajouté par `spine01`) dans l'AS_PATH et rejette la route (détection de boucle eBGP). C'est voulu : un leaf ne doit pas servir de transit entre spines. a) la détection l'empêche ; c) eBGP n'a pas de *split horizon* entre pairs, c'est l'AS_PATH qui joue ce rôle ; d) elle n'est même pas acceptée.
9. Le noyau calcule un hachage : politique 0 sur les adresses source et destination, 1 sur les adresses, le protocole et les ports, 2 sur les en-têtes internes (tunnels). En L3, un couple de machines a toujours le même chemin : une panne de chemin touche toujours les mêmes couples (stable, déroutant) et un couple très bavard charge un seul lien ; en L4, les flux d'un même couple se répartissent.
10. Serveur à une interface de données : strict (aucune route légitime asymétrique) ou lâche si une interface d'administration peut porter des réponses ; routeur de fabric en ECMP : strict est compatible avec l'ECMP, lâche si l'asymétrie est possible (maintenance, ingénierie de trafic) ; bordure à deux passerelles : lâche, et filtrage d'usurpation explicite dans nftables par interface.
11. Le membre de plus haute priorité devient maître et annonce ; les autres attendent *Master_Down_Interval* (≈ 3 intervalles) sans annonce pour prendre la place. Préemption : un membre de priorité supérieure qui revient reprend la place (seconde coupure). `nopreempt` : il reste en secours (une seule coupure, mais le maître n'est plus celui qu'on croit). Pour les passerelles, M07-E25 justifie son choix (la réponse attendue est cohérente avec ce choix : par exemple préemption pour garder `gw01` maître par défaut, avec un `preempt_delay` qui laisse aux tunnels et à conntrackd le temps d'être prêts) ; le risque de l'autre choix : avec préemption sans délai, un `gw01` qui redémarre reprend les VIP avant d'être prêt ; avec `nopreempt`, la passerelle active dérive au fil des incidents et la supervision doit suivre « qui est maître ».
12. **b**. Deux routeurs virtuels distincts revendiquent la même adresse ; chacun est seul dans le sien, donc maître. a) la configuration est valide pour chacun ; c) les priorités ne se comparent qu'au sein d'un même VRID ; d) au contraire, deux membres la portent.
13. Causes : filtrage de VRRP, VRID ou version différents, destination unicast erronée, membres sur deux segments (VLAN mal affecté). Effets : ARP qui alterne, connexions coupées aléatoirement, deux répartiteurs qui reçoivent chacun une partie du trafic (sessions perdues). Protections : sonde « un seul maître » depuis un tiers, VRID/VIP générés depuis une seule variable, VRRP dans la matrice des flux, bascule de test après tout changement, `track_script` qui se met en défaut si l'autre membre est joignable mais muet.
14. Les entrées de la table `conntrack` (création, mises à jour d'état, destruction), en continu, avec acquittements et retransmissions (FTFW = *fault tolerant*) ; à la bascule, le script de transition engage le cache externe dans le noyau du nouveau maître. Sans lui, le nouveau maître voit arriver le milieu de connexions qu'il ne connaît pas : état `invalid` (ou `new` sans SYN), jeté par la politique, et les clients doivent se reconnecter. Lien dédié : la synchronisation ne doit ni concurrencer le trafic ni dépendre d'un VLAN qui tombe avec la passerelle ; elle transporte de l'état de sécurité (à protéger).
15. 502 : réponse invalide ou connexion fermée par le serveur ; 503 : aucun serveur disponible ; 504 : délai de réponse du serveur dépassé. `L4CON` : connexion refusée ; `L4TOUT` : pas de réponse TCP ; `L6RSP` : échec de la négociation TLS ; `L7STS` : code HTTP inattendu. Un contrôle de santé est actif (requête dédiée, périodique) ; `observe layer7` est passif (il compte les erreurs du trafic réel et peut retirer un serveur entre deux contrôles).
16. Terminaison et ré-chiffrement : le répartiteur voit le HTTP (routage par chemin, en-têtes, `X-Forwarded-For`, journaux complets, WAF), deux certificats à gérer, la clé privée sur le répartiteur. Passage de bout en bout (mode TCP, routage par SNI) : le serveur garde sa clé et voit le TLS du client, mais le répartiteur ne voit plus rien du HTTP ; l'adresse du client se transmet par le protocole PROXY. MédiSphère termine et ré-chiffre (M07-E13) pour GitLab et NetBox.
17. Le routeur dont l'interface de sortie est trop petite émet l'ICMP vers la **source** du paquet. Pour un pare-feu à états, cet ICMP est `related` à la connexion : un pare-feu qui n'accepte que `established` le jette, l'émetteur ne réduit jamais sa taille, la connexion fige. Remèdes : *MSS clamping* (simple, TCP seulement, à chaque frontière), sondage par la couche transport (indépendant des ICMP, plus lent), MTU uniforme (supprime le besoin… jusqu'au premier tunnel).
18. Le gain (moins d'en-têtes, moins d'interruptions) compte pour le stockage et l'overlay ; les autres VLAN parlent à l'extérieur (1500) et n'y gagneraient que des risques. Une VM à 1500 dans un VLAN à 9000 : TCP s'en sort (MSS négocié sur le plus petit MTU des extrémités), UDP et les protocoles à grands datagrammes échouent (fragmentation ou pertes silencieuses selon le pilote), Ceph voit des OSD qui battent (*heartbeats* de grande taille perdus) : le pire est un MTU incohérent **dans** un segment.
19. En sortie, WireGuard choisit le pair dont les `AllowedIPs` contiennent la destination (et refuse sinon : `ENOKEY`) ; en entrée, il n'accepte un paquet déchiffré que si sa source est dans les `AllowedIPs` du pair. L'extrémité d'un pair est mise à jour à chaque paquet authentifié reçu (itinérance). Deux passerelles avec la même clé actives en même temps : le pair distant envoie à la dernière qui lui a parlé, les compteurs anti-rejeu et les sessions divergent, le tunnel bat ; d'où les interfaces montées seulement par le maître (M07-E26).
20. **b**. `ENOKEY` est renvoyé quand aucun pair ne couvre la destination. a) sans poignée de main, le paquet est mis en file et une poignée de main est tentée (pas d'erreur immédiate) ; c) sans clé privée l'interface ne peut pas fonctionner du tout ; d) un port filtré donne un silence, pas une erreur locale.

**Grille d'auto-évaluation** : 16/20 au moins avec des réponses argumentées ; reprends les exercices liés à chaque erreur (E04/E17/E40 pour l'agrégation, E07/E14/E35/E42 pour BGP, E08/E25/E37 pour VRRP, E27 pour `conntrackd`, E10/E28/E39 pour HAProxy, E15/E38 pour le MTU, E18/E19/E36 pour WireGuard).
