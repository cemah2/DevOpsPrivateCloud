# Module 07 — Palier 4 : Expert

La bordure de PAR1 est redondante : deux passerelles en VRRP sur chaque VLAN routé, des tunnels qui suivent le maître, des connexions synchronisées par `conntrackd`. Les répartiteurs `lb01`/`lb02` publient GitLab et NetBox, FRR parle BGP à la fabric de la maquette et au site de Lyon, les réseaux de stockage passent en *jumbo frames*. Claire Morel résume la suite : « Un réseau redondant tombe moins souvent, mais il tombe de façon plus subtile. Une seule passerelle en panne, tout le monde la voit. Deux maîtres VRRP, un chemin de retour qui contourne la fabric ou un MTU mal réglé, personne ne voit rien… sauf les utilisateurs. » Karim Benali a préparé huit pannes, toutes vues en production : une session BGP qui ne sert plus à rien, une agence coupée du siège, deux maîtres pour la même adresse, des transferts qui se figent, un répartiteur qui répond 503, un agrégat amputé d'un lien, un trafic qui part sans revenir, une fabric à moitié aveugle. Une astreinte les combine, avec une panne de plus sur la bordure. Puis tu suis un paquet du poste d'administration jusqu'à GitLab, trame par trame, et tu réponds aux questions qu'on pose en entretien sur ces protocoles.

La méthode est celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres au réseau :
- **Descends les couches dans l'ordre.** Lien (état, MTU, agrégat), trame (VLAN, table de commutation, ARP), paquet (route, règle de routage, filtrage par chemin inverse), filtrage (nftables, suivi des connexions), plan de contrôle (VRRP, BGP), application (HAProxy, Nginx). Une couche saine se prouve par une mesure, pas par une impression.
- **Capture des deux côtés.** Un paquet vu à l'émission et absent à la réception désigne le segment fautif ; un paquet vu des deux côtés et une réponse absente désignent le **retour**. `tcpdump` au bon endroit vaut mieux que dix `ping`.
- **Lis l'état chargé, pas seulement le fichier.** `vtysh -c 'show running-config'`, `nft list ruleset`, `ip rule`, `ip -d link`, `wg show`, `cat /proc/net/bonding/…`, la socket d'administration de HAProxy : la panne est souvent dans l'écart entre ce qui est écrit et ce qui tourne.

> **Rappels** : tout se lance depuis `adm01`. Les VMs de la maquette (2070-2079) se joignent par leurs alias SSH (M07-E03) ou, quand le réseau est en cause, par l'agent QEMU depuis `pve01` : `qm guest exec <VMID> -- <commande>` (sortie JSON, champ `out-data`) et la console série `qm terminal <VMID>`. Projets : `~/src/ansible` (rôles `frr`, `keepalived`, `haproxy`, `nginx_web`, `wireguard`, inventaire de la maquette), `~/src/infra` (états `socle` et `m07-maquette`), `~/src/outils` (`ms-verif-reseau`, M07-E29), documentation `~/medisphere` (variable `WB_DEPOT`). Sur la maquette, une réparation à la main est permise ; sur le socle (`gw01`, `gw02`, `lb01`, `lb02`), tout correctif durable passe par le code (MR fusionnée, pipeline de référence).

## Règles du jeu des pannes (M07-E35 à M07-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 07 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (selon tes choix des paliers précédents : répartiteurs en multicast, configuration FRR sans route-map de sortie…), le script en essaie une autre. Certaines injections prennent une à deux minutes (le temps qu'un protocole constate la panne).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 07 35`) : il doit être vert. Une panne posée sur un lab déjà malade fausse tout le diagnostic.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 07 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte M07-E43 et le mini-projet) : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- Les pannes agissent sur les VMs de la maquette (2070-2079, toujours par l'agent QEMU, après contrôle du nom et de l'étiquette `env-m07`) et, pour M07-E37 (une variante) et M07-E43, sur `lb01`/`lb02` et sur la passerelle **de secours**. Jamais sur la passerelle active, jamais sur `pve01`, son réseau ou son pare-feu, jamais sur `pbs01`. Les modifications de fichiers sont sauvegardées sous `/var/lib/workbook/` de l'hôte touché ; les modifications à chaud (route, règle, MTU, table nftables, état d'un lien) sont notées pour être défaites.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/socle/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M07-E43 et les runbooks RB-073 à RB-079.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours** : plusieurs pannes de ce palier coupent un chemin réseau (routage, filtrage, tunnel). Vérifie **avant** le premier `break` que l'agent QEMU répond sur toute la maquette :
> ```
> root@pve01:~# for id in $(seq 2070 2079); do printf '%s ' $id; qm guest cmd $id ping && echo ok; done
> ```
> et que tu sais ouvrir la console série d'une VM (`qm terminal 2073`, sortie par `Ctrl+O`). Sur `gw01`/`gw02`, la console et l'agent sont tes seuls accès si tu coupes ta propre session : **ne modifie jamais à chaud le pare-feu, le VRRP ou les routes de la passerelle active** pendant ces exercices. Les pannes ne la touchent pas ; ta réparation ne doit pas le faire non plus.

> ⚠️ **Avant de « corriger en rejouant »** : un `ansible-playbook` lancé pendant une panne peut aussi bien la corriger que la masquer (il réécrit le fichier mais ne retire pas une route ou une table nftables posées à chaud) ou la propager (un rôle qui recharge FRR sur toute la fabric). Diagnostique d'abord, puis `--check --diff --limit <hôte>`, et lis ce qui serait changé.

---

### M07-E35 — Panne : la session BGP ne monte pas  `BF` `★★★`

> **Ticket INC-3401** — *De : Karim Benali*
> Depuis ce matin, `gw01` n'a plus aucune route vers les boucles de la maquette (10.10.255.0/24) : `ip route show proto bgp` est vide. Je teste le BGP qui servira à Kubernetes au bloc C, donc je veux comprendre, pas seulement que ça remarche. Côté bordure, personne n'a rien changé (j'ai vérifié l'historique de `plateforme/ansible`). InfoGér est intervenu sur la maquette hier.

**Objectifs pédagogiques**
- Lire une session BGP comme un automate : états (`Idle`, `Connect`, `Active`, `OpenSent`, `OpenConfirm`, `Established`), messages OPEN et NOTIFICATION, et ce que chaque état bloqué désigne (TCP, paramètres de l'OPEN, politique).
- Distinguer une session qui ne s'établit pas d'une session établie qui n'échange rien (RFC 8212, `bgp ebgp-requires-policy`).
- Utiliser les deux extrémités : `show bgp summary`, `show bgp neighbors <pair>`, journal de `bgpd`, capture du port 179, compteurs du noyau.

**Prérequis** : M07-E07, M07-E14, M07-E16 ; `lab/bin/check 07 35` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `leaf01` (AS 65101) parle eBGP avec la bordure (AS 65000) sur le VLAN 99, depuis son adresse fixe 10.10.99.251 ; la bordure n'accepte de la fabric que 10.10.255.0/24 et 10.10.41.0/24 (M07-E16). FRR lit `/etc/frr/frr.conf` (configuration intégrée, rôle `frr`) ; `systemctl reload frr` applique les différences par `frr-reload.py`. Le journal de `bgpd` est dans `journalctl -u frr`.

**Injection** : `lab/bin/break 07 35` (4 variantes).

**Travail demandé**
1. Constate l'état de la session **des deux côtés** (`gw01` et `leaf01`) : état, compteurs de messages, préfixes reçus et envoyés, dernière raison de remise à zéro. Note-les dans ton journal.
2. À partir de l'état seul, dis à quelle couche se situe le problème : TCP ne s'établit pas, OPEN refusé, ou session établie sans échange de routes. Confirme par une mesure indépendante (capture du port 179, journal de `bgpd`, compteurs).
3. Trouve la cause racine et corrige-la **à l'endroit où elle a été introduite**, sans rien modifier sur la bordure et sans désactiver `bgp ebgp-requires-policy`.
4. Prouve le retour : session établie, préfixes de la fabric de nouveau dans la table de `gw01`, et seulement ceux que la politique autorise.
5. Indique dans ton journal ce que `ms-verif-reseau` (M07-E29) a vu ou non, et quelle sonde aurait distingué « session tombée » de « session établie mais vide ».

**Critères de réussite**
- [ ] Sur `leaf01`, la session vers l'AS 65000 est `Established` et annonce des préfixes ; `bgp ebgp-requires-policy` est toujours en vigueur.
- [ ] `gw01` (et `gw02` si elle a sa session) a des routes BGP vers 10.10.255.0/24, et aucune route BGP hors des préfixes autorisés.
- [ ] Ton journal contient l'état initial des deux côtés, la couche identifiée et la mesure qui l'a confirmée.

**Vérification** : `lab/bin/check 07 35`

<details><summary>Indice 1</summary>

Un pair bloqué en `Active` ou `Connect` n'a jamais fini sa connexion TCP : regarde le port 179 (`ss -tn`, `tcpdump`). Un pair qui alterne `OpenSent` et `Idle` reçoit ou envoie une NOTIFICATION : `show bgp neighbors <pair>` affiche la dernière (« Last reset … due to … »). Un pair `Established` dont la colonne des préfixes affiche `(Policy)` est un pair qui n'a pas le droit d'échanger.
</details>

<details><summary>Indice 2</summary>

Certaines causes ne laissent **aucune** trace dans FRR, seulement dans le noyau : un segment TCP jeté par le filtrage ou par une vérification d'authentification de segment. `nft list ruleset`, `dmesg` et `nstat -az | grep -i -E 'md5|tcp'` complètent ce que `bgpd` ne voit pas.
</details>

<details><summary>Indice 3</summary>

Compare la configuration **chargée** de `leaf01` (`vtysh -c 'show running-config'`) à ce que produirait le rôle `frr` (`ansible-playbook … --limit leaf01 --check --diff`) : l'écart est la panne, ou la désigne.
</details>

**Pour aller plus loin** : active BFD sur cette session (`bfdd`, profil court) et mesure le temps de détection d'une coupure avec et sans BFD ; lis la [documentation BGP de FRR](https://docs.frrouting.org/en/latest/bgp.html) (sections *Peers*, *RFC 8212*) et la [RFC 4271](https://www.rfc-editor.org/rfc/rfc4271) §8 (automate).

---

### M07-E36 — Panne : Lyon ne joint plus Paris  `BF` `★★`

> **Ticket INC-3402** — *De : Nadia Roussel*
> L'agence de Lyon appelle : plus aucun accès aux services de Paris depuis les postes (`lyo-pc01`, 10.30.10.10, en est un). Leur accès Internet fonctionne. InfoGér, qui gère encore le routeur de l'agence (`lyo-gw01`), a « appliqué les correctifs du mois » hier soir. Côté Paris, personne n'a touché à la bordure.

**Objectifs pédagogiques**
- Découper un lien inter-sites en maillons testables : poste → routeur de l'agence (relais IP) → routage (BGP sur le tunnel) → routage cryptographique de WireGuard (`AllowedIPs`) → poignée de main → bordure.
- Lire `wg show` comme un instrument : clé du pair, extrémité, `allowed ips`, dernière poignée de main, compteurs d'octets.
- Reconnaître les messages caractéristiques (`Required key not available`, absence de poignée de main, compteurs qui ne bougent que dans un sens).

**Prérequis** : M07-E18, M07-E19, M07-E26 ; `lab/bin/check 07 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : `lyo-gw01` (VMID 2077) porte le tunnel `wg2` vers la bordure (10.255.2.2 ↔ 10.255.2.1, UDP 51822, extrémité 10.10.99.1), sa configuration est `/etc/wireguard/wg2.conf` (`wg-quick@wg2`) et la session BGP 65030 ↔ 65000 passe dans le tunnel. `lyo-pc01` (VMID 2078) n'a qu'une interface, sur `vfab8`. Pour tester comme un poste de l'agence, la cible de référence est 10.10.20.1 (passerelle du VLAN 20).

**Injection** : `lab/bin/break 07 36` (4 variantes).

**Travail demandé**
1. Reproduis depuis `lyo-pc01`, puis depuis `lyo-gw01` lui-même. La différence entre les deux résultats élimine déjà des hypothèses : lesquelles ?
2. Sur `lyo-gw01`, vérifie dans l'ordre : la route vers PAR1 (et d'où elle vient), l'état du tunnel (`wg show wg2`), la session BGP et ce qu'elle a reçu, le relais IP. Note la première mesure anormale.
3. Si nécessaire, regarde le côté bordure **en lecture seule** (`wg show wg2` sur la passerelle active) pour confirmer.
4. Corrige la cause racine sur `lyo-gw01`. Si un fichier de configuration est en cause, explique comment le rôle Ansible de l'agence aurait dû l'empêcher.
5. Prouve le retour depuis `lyo-pc01`, et vérifie que la politique de E19 tient toujours (le réseau MGMT de PAR1 reste inaccessible depuis Lyon).

**Critères de réussite**
- [ ] `lyo-pc01` joint 10.10.20.1 ; la dernière poignée de main de `wg2` a moins de trois minutes.
- [ ] Sur `lyo-gw01` : `AllowedIPs` couvre les réseaux de PAR1 annoncés, le relais IP est actif (et le restera au redémarrage), la session BGP reçoit des routes ; 10.10.10.0/24 ne passe pas par le tunnel.
- [ ] Ton journal contient la première mesure anormale et ce qu'elle désignait.

**Vérification** : `lab/bin/check 07 36`

<details><summary>Indice 1</summary>

Si `lyo-gw01` joint Paris et que `lyo-pc01` ne le joint pas, le tunnel et le routage de `lyo-gw01` vont bien pour son propre trafic : la question devient « qu'est-ce qui distingue un paquet **relayé** d'un paquet **émis** ? ». Si `lyo-gw01` lui-même échoue, lis l'erreur exacte de `ping` : elle ne dit pas la même chose selon que la route manque ou que WireGuard refuse le paquet.
</details>

<details><summary>Indice 2</summary>

`wg show wg2` : une poignée de main absente ou ancienne de plus de deux minutes, avec des octets envoyés mais aucun reçu, désigne les clés ou l'extrémité. Une poignée de main récente avec un ping qui échoue désigne ce que WireGuard accepte de transporter. `vtysh -c 'show bgp ipv4 unicast summary'` et `show bgp neighbors 10.255.2.1 received-routes` (si `soft-reconfiguration inbound` est actif) ou `show bgp ipv4 unicast` disent ce que BGP a appris… et gardé.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-reseau` une sonde « depuis l'agence » (une requête de `lyo-pc01` vers un service de PAR1, lancée par l'agent) en plus de la sonde « âge de la dernière poignée de main » ; lis la section *Cryptokey Routing* de la [présentation de WireGuard](https://www.wireguard.com/#cryptokey-routing).

---

### M07-E37 — Panne : deux maîtres VRRP  `BF` `★★★`

> **Ticket INC-3403** — *De : Nadia Roussel*
> Alerte de la supervision cette nuit : « deux maîtres VRRP ». *(L'injection précise quelle paire et ce que voient les utilisateurs.)* Rien n'a été déployé par le pipeline depuis hier. Rétablis un seul maître, et explique-moi pourquoi keepalived n'a rien dit.

**Objectifs pédagogiques**
- Comprendre ce qui fait d'un routeur VRRP un maître : il n'entend plus d'annonce d'un pair de priorité supérieure ou égale **pour le même routeur virtuel** pendant l'intervalle de maître défaillant (*Master_Down_Interval*, RFC 9568).
- Observer les annonces sur le fil (`tcpdump -ni <if> vrrp -vv` : VRID, priorité, intervalle, source, destination) et les confronter à la configuration chargée.
- Mesurer les effets d'un *split-brain* : ARP qui bascule d'une adresse matérielle à l'autre, connexions coupées, répartition aléatoire.

**Prérequis** : M07-E08, M07-E12, M07-E25 ; `lab/bin/check 07 37` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : deux paires sont concernées par cet exercice : `srv01`/`srv02` (maquette, VIP 10.10.99.240, VRID 199, M07-E08) et `lb01`/`lb02` (socle, VIP 10.10.70.200, VRID 170, M07-E12). Les configurations sont sous `/etc/keepalived/` (rôle `keepalived`) ; `journalctl -u keepalived` trace chaque transition (`Entering MASTER STATE`, `Entering BACKUP STATE`). Les passerelles ne sont **pas** concernées : ne touche pas à leur VRRP.

> ⚠️ **Attention** : si la paire est `lb01`/`lb02`, GitLab et NetBox sont publiés par cette VIP. Avant toute action, prends un instantané des deux répartiteurs (`ms-snapshot`, M02-E11) et vérifie l'agent QEMU de chacun. N'arrête pas keepalived sur les deux à la fois : la VIP disparaîtrait. Retour arrière : restauration des instantanés, puis passage du rôle `keepalived` (`--limit role_lb`).

**Injection** : `lab/bin/break 07 37` (3 variantes).

**Travail demandé**
1. Prouve le *split-brain* depuis un tiers : quelle adresse matérielle répond pour la VIP (`ip neigh`, `arping`), et est-ce qu'elle change ?
2. Sur **chaque** membre, capture les annonces VRRP reçues et émises pendant 10 secondes. Remplis un tableau : qui émet, vers où, quel VRID, quelle priorité ; qui reçoit quoi.
3. Confronte le tableau à la configuration chargée de chaque membre et au filtrage local. Identifie l'écart.
4. Corrige à la racine (fichier géré par le rôle → passage du rôle ; règle posée à chaud → retrait, et explique pourquoi la détection de dérive ne l'a pas vue), puis vérifie qu'un seul maître subsiste **et** que la bascule fonctionne encore (arrêt contrôlé du maître, retour).
5. Réponds à Nadia dans ton journal : pourquoi keepalived « n'a rien dit » ? Quelle sonde, quel script de suivi (`track_script`, `notify`) aurait levé l'alerte plus tôt ?

**Critères de réussite**
- [ ] Une seule machine porte la VIP de chaque paire ; la VIP de la maquette sert la page d'un serveur.
- [ ] Les deux membres de chaque paire ont le même VRID ; aucun filtrage local ne bloque VRRP ; en unicast, chaque répartiteur désigne l'autre.
- [ ] Ton journal contient le tableau des annonces et l'écart identifié.

**Vérification** : `lab/bin/check 07 37`

<details><summary>Indice 1</summary>

Deux maîtres, c'est deux machines qui n'entendent pas **l'autre**. Il suffit qu'un seul des deux sens soit coupé pour que le membre de plus basse priorité devienne maître : cherche le sens qui manque, puis la raison (le paquet n'est pas émis, pas vers la bonne adresse, pas reçu, ou reçu et ignoré).
</details>

<details><summary>Indice 2</summary>

Un paquet VRRP vu par `tcpdump` et pourtant ignoré par keepalived : regarde le VRID et la version dans la capture, et le journal de keepalived (avec `-D`/`--log-detail` si besoin). Un paquet qui n'apparaît même pas dans la capture d'un membre alors que l'autre l'émet : regarde l'adresse de destination. Un paquet vu par `tcpdump` sur l'interface mais jamais traité : `tcpdump` voit avant le filtrage d'entrée.
</details>

**Pour aller plus loin** : écris un `track_script` ou un `notify` qui publie l'état VRRP de chaque membre dans un fichier lu par `ms-verif-reseau`, et une sonde qui alerte si les deux membres d'une paire sont `MASTER` ; lis la [RFC 9568](https://www.rfc-editor.org/rfc/rfc9568) (VRRP v3) et la [documentation de keepalived](https://keepalived.org/manpage.html).

---

### M07-E38 — Panne : les gros transferts se figent  `BF` `★★★`

> **Ticket INC-3404** — *De : Julien Petit*
> Le transfert de l'export de nuit entre `srv01` et `srv02` ne finit plus : depuis `srv01`, `curl --interface 10.10.255.21 http://10.10.255.22/export-nuit.bin` reste à 0 octet puis expire. La page d'accueil de `srv02` répond pourtant instantanément, `ping` aussi, SSH aussi. InfoGér a « préparé la fabric pour l'encapsulation » hier et « durci » quelques machines.

**Objectifs pédagogiques**
- Reconnaître la signature d'un trou noir de la découverte du MTU du chemin (PMTUD, RFC 1191) : poignée de main TCP et petits échanges corrects, premiers segments pleins jamais acquittés, retransmissions.
- Trouver le lien le plus étroit d'un chemin (`ping -M do -s`, `tracepath`) et le routeur qui **devrait** émettre l'ICMP « fragmentation nécessaire » ; vérifier qu'il l'émet, et qu'il arrive.
- Choisir entre les remèdes : MTU cohérent, ICMP rétabli, *MSS clamping*, sondage du MTU par la couche de transport (RFC 4821/8899), et savoir pourquoi « tout remettre à 1500 » n'est pas toujours la bonne réponse.

**Prérequis** : M07-E14, M07-E15, M07-E20 ; `lab/bin/check 07 38` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : le chemin `srv01` → `leaf01` → `spine01`/`spine02` → `leaf02` → `srv02` passe par la fabric (M07-E14). Le fichier `export-nuit.bin` est servi par le Nginx de `srv02` pendant la panne. Les liens de la fabric sont des VNets `vfab1` à `vfab7` ; un MTU différent du MTU par défaut est légitime sur un lien de fabric s'il est **identique aux deux extrémités**. `tracepath` est dans le paquet `iputils-tracepath`.

**Injection** : `lab/bin/break 07 38` (3 variantes).

**Travail demandé**
1. Reproduis le blocage et capture-le **côté `srv02`** (l'émetteur des données) : que voit-on après la poignée de main ? Que contient la fenêtre de retransmission ?
2. Mesure le MTU du chemin de `srv02` vers `srv01` (et l'inverse) sans dépendre de TCP. Identifie le lien le plus étroit et le routeur qui doit signaler le dépassement.
3. Vérifie, par capture sur ce routeur puis sur l'émetteur, si l'ICMP « fragmentation nécessaire » est émis, puis s'il est reçu et traité. Note où il disparaît.
4. Corrige la cause racine. Discute dans ton journal : faut-il revenir au MTU d'avant sur la fabric, ou garder le changement et rétablir la PMTUD ? Quelle protection supplémentaire (au niveau TCP ou du pare-feu) rendrait ce type de changement sans risque ?
5. Rédige dans ton journal les commandes qui auraient détecté le problème **avant** la mise en production du changement de MTU.

**Critères de réussite**
- [ ] Le transfert de `export-nuit.bin` de `srv02` vers `srv01` aboutit ; `ping -M do -s 1472` de boucle à boucle répond ou annonce le MTU du chemin (jamais le silence).
- [ ] Les extrémités de chaque lien leaf-spine ont le même MTU ; aucune règle de filtrage ne jette d'ICMP utile sur la fabric ni sur les serveurs ; tout filtrage d'entrée en politique « drop » accepte les paquets `related`.
- [ ] Ton journal localise l'endroit où l'ICMP disparaît, preuve à l'appui.

**Vérification** : `lab/bin/check 07 38`

<details><summary>Indice 1</summary>

`ping -M do -s <taille>` envoie des paquets que personne n'a le droit de fragmenter : en faisant varier la taille, tu trouves la limite. La réponse peut être un écho, un message « Frag needed and DF set (mtu = …) » d'un routeur… ou le silence. Le silence au-delà d'une taille, c'est déjà presque le diagnostic.
</details>

<details><summary>Indice 2</summary>

Un ICMP « fragmentation nécessaire » est émis par le **routeur** dont l'interface de sortie est trop petite, vers l'**émetteur** du gros paquet. Il peut disparaître à trois endroits : il n'est pas émis (filtrage de sortie du routeur), il est jeté en route, il est jeté à l'arrivée (filtrage d'entrée de l'émetteur). Pour un pare-feu à états, cet ICMP n'est ni `new` ni `established`.
</details>

**Pour aller plus loin** : compare le comportement avec `sysctl net.ipv4.tcp_mtu_probing=1` sur `srv02` (sondage par la couche de transport) et avec une règle de *MSS clamping* (`tcp option maxseg size set rt mtu`) sur les leaves ; lis la [RFC 8899](https://www.rfc-editor.org/rfc/rfc8899) et la [RFC 2923](https://www.rfc-editor.org/rfc/rfc2923) (problèmes connus de la PMTUD).

---

### M07-E39 — Panne : 503 Service Unavailable  `BF` `★★`

> **Ticket INC-3405** — *De : Julien Petit*
> La démo de répartition (`hap01`) répond « 503 Service Unavailable » à toutes les requêtes. Pourtant `srv01` et `srv02` sont allumés et je peux m'y connecter en SSH. Lucas dit qu'il a « juste préparé un truc » sur la maquette, InfoGér a « durci » des serveurs : à toi de voir.

**Objectifs pédagogiques**
- Savoir ce que signifie un 503 de HAProxy (aucun serveur disponible dans le backend) et le distinguer d'un 502 (réponse invalide) et d'un 504 (délai dépassé).
- Lire l'état des serveurs par la socket d'administration (`show stat`, `show servers state`) : statut, `check_status` (`L4CON`, `L4TOUT`, `L6RSP`, `L7STS`…), `last_chk`.
- Rejouer le contrôle de santé à la main, exactement comme HAProxy le fait, pour savoir si le défaut est côté répartiteur ou côté serveur.

**Prérequis** : M07-E10, M07-E21, M07-E22 ; `lab/bin/check 07 39` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : `hap01` (VMID 2079) : HAProxy 3.2, configuration `/etc/haproxy/haproxy.cfg` (rôle `haproxy`), socket d'administration `/run/haproxy/admin.sock`, page de statistiques sur 127.0.0.1:8404 ; backend `be_web` vers `srv01` et `srv02` (rôle `nginx_web`, point de santé `/sante`). HAProxy journalise dans `journalctl -u haproxy` (dont les changements d'état des serveurs).

**Injection** : `lab/bin/break 07 39` (4 variantes).

**Travail demandé**
1. Vérifie que le 503 vient bien de HAProxy (et pas d'un serveur) : en-têtes, page d'erreur, journal.
2. Lis l'état des serveurs du backend par la socket d'administration. Note le `check_status` et sa description exacte : à quelle couche le contrôle échoue-t-il ?
3. Rejoue le contrôle de santé à la main depuis `hap01` (même adresse, même port, même protocole, même requête) pour confirmer.
4. Corrige à la racine, au bon endroit (rôle `haproxy` pour `hap01`, rôle `nginx_web` ou procédure de maintenance pour les serveurs). Recharge sans couper : le service doit revenir sans redémarrage complet de HAProxy.
5. Complète RB-070 (maintenance d'un répartiteur, M07-E22) ou le runbook de diagnostic qui convient pour que ce cas soit détecté en moins de 5 minutes.

**Critères de réussite**
- [ ] `hap01` répond 200 sur son frontend HTTP ; tous les serveurs du backend sont `UP` ; la configuration passe `haproxy -c`.
- [ ] Les deux serveurs écoutent sur une adresse joignable et répondent 200 sur `/sante`.
- [ ] Ton journal associe le `check_status` initial à la couche fautive et à la cause.

**Vérification** : `lab/bin/check 07 39`

<details><summary>Indice 1</summary>

`echo "show stat" | socat stdio /run/haproxy/admin.sock | cut -d, -f1,2,18,37,38` (ou les mêmes colonnes par la page de statistiques) : nom du proxy, du serveur, statut, `check_status`, `check_code`. `L4` : la connexion TCP elle-même ; `L6` : la couche TLS ; `L7` : la réponse HTTP. Le paquet `socat` est à installer s'il manque (ou `nc -U`).
</details>

<details><summary>Indice 2</summary>

Le contrôle de santé n'est pas forcément la même requête que le trafic réel : port, protocole (clair ou TLS), chemin, en-tête `Host` et code attendu peuvent différer. Lis les lignes `option httpchk`, `http-check …` et les options `check*` de chaque ligne `server`. Côté serveur, `ss -tlnp` et `curl -v` sur l'adresse que HAProxy utilise.
</details>

**Pour aller plus loin** : ajoute `option redispatch`, `retries` et un `errorfile 503` explicite ; compare `observe layer7` et les contrôles agents (`agent-check`) ; lis la [documentation des contrôles de santé de HAProxy 3.2](https://docs.haproxy.org/3.2/configuration.html#5.2-check).

---

### M07-E40 — Panne : l'agrégat a perdu un lien  `BF` `★★`

> **Ticket INC-3406** — *De : Karim Benali*
> La sonde de `net01` signale que l'agrégat LACP entre l'espace de noms « serveur » et le commutateur Open vSwitch ne compte plus qu'un port actif : débit divisé par deux et plus aucune redondance. Personne n'admet avoir touché à `net01`. Remets les deux liens dans l'agrégat, et dis-moi ce qu'aurait vu un vrai commutateur.

**Objectifs pédagogiques**
- Lire `/proc/net/bonding/<bond>` : mode, agrégateur actif, nombre de ports, état MII de chaque membre, partenaire LACP (adresse système, clé, état).
- Lire l'autre extrémité : `ovs-appctl bond/show`, `ovs-appctl lacp/show`, `ovs-vsctl list port`.
- Distinguer un lien physiquement coupé, un lien sorti de l'agrégat et une négociation LACP qui échoue, et savoir ce que chacun donne sur un commutateur réel.

**Prérequis** : M07-E04, M07-E05, M07-E17 ; `lab/bin/check 07 40` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : sur `net01` (VMID 2070), l'état de M07-E17 : un bond Linux 802.3ad dans l'espace de noms côté serveur, relié par des paires veth à un port agrégé d'Open vSwitch (`lacp=active`) sur le pont `br-lab`. Les commandes de l'espace de noms se lancent par `ip netns exec <nom> …` ; `ip -n <nom> …` pour `ip` seul.

**Injection** : `lab/bin/break 07 40` (3 variantes).

**Travail demandé**
1. Relève l'état complet de l'agrégat **des deux côtés** (Linux et Open vSwitch) et compare-le à celui que tu avais noté en M07-E17.
2. Pour chaque membre, réponds : le lien est-il administrativement actif ? A-t-il la porteuse ? Est-il membre du bond ? Échange-t-il des LACPDU, et le partenaire est-il le même que celui de l'autre membre ?
3. Trouve la cause racine et corrige-la là où elle a été introduite. Si ta configuration de `net01` est rejouée par un script ou un service (M07-E17), vérifie qu'un redémarrage ne réintroduit pas le défaut.
4. Prouve le retour : deux ports dans l'agrégateur actif, partenaire connu, trafic réparti (compteurs des deux membres qui avancent).
5. Réponds à Karim dans ton journal : pour chaque cause possible de « un seul port actif », qu'afficherait un commutateur réel (`show lacp neighbor`, `show etherchannel summary` ou équivalent) ?

**Critères de réussite**
- [ ] Le bond 802.3ad de `net01` a au moins deux ports dans l'agrégateur actif, tous ses membres en `MII Status: up`, et un partenaire LACP connu.
- [ ] Open vSwitch annonce une négociation LACP réussie sur le port agrégé.
- [ ] Ton journal contient l'état initial des deux côtés et la réponse à la question de Karim.

**Vérification** : `lab/bin/check 07 40`

<details><summary>Indice 1</summary>

Dans `/proc/net/bonding/<bond>`, chaque membre a son propre bloc : `MII Status`, `Aggregator ID`, et ses blocs `details actor lacp pdu` / `details partner lacp pdu`. Un membre dont l'`Aggregator ID` diffère de celui de l'agrégateur actif est en dehors du trafic ; un partenaire `00:00:00:00:00:00` n'a jamais répondu.
</details>

<details><summary>Indice 2</summary>

Une paire veth a deux extrémités, dans deux espaces de noms : l'état de l'une se lit sur l'autre (`NO-CARRIER`, `M-DOWN`). `ip -d link show` donne le maître d'une interface ; `ovs-vsctl list port <port>` donne la configuration LACP réellement enregistrée dans la base d'Open vSwitch (qui survit aux redémarrages).
</details>

**Pour aller plus loin** : compare `xmit_hash_policy layer2`, `layer2+3` et `layer3+4` en lançant plusieurs flux `iperf3` à travers l'agrégat ; lis la [documentation du bonding Linux](https://docs.kernel.org/networking/bonding.html) (section 802.3ad) et `ovs-vswitchd.conf.db(5)` (colonnes `lacp` et `other_config:lacp-time`).

---

### M07-E41 — Panne : ça part mais ça ne revient pas  `BF` `★★★`

> **Ticket INC-3407** — *De : Karim Benali*
> La sonde de boucle à boucle de la maquette est rouge : depuis `srv01`, `ping -I 10.10.255.21 10.10.255.22` n'obtient aucune réponse. J'ai lancé un `tcpdump` sur `srv02` : les requêtes arrivent bien et `srv02` répond. Ça part, mais ça ne revient pas. Lucas a fait des « essais de contournement » pendant la panne de E38, et InfoGér a appliqué un guide de durcissement réseau.

**Objectifs pédagogiques**
- Suivre une réponse saut par saut : choix de route **avec** la source et l'interface d'entrée (`ip route get … from … iif …`), règles de routage par politique (`ip rule`), tables secondaires.
- Comprendre le filtrage par chemin inverse (`rp_filter`, RFC 3704) : mode strict, mode lâche, valeur effective (maximum de `all` et de l'interface), compteur `IPReversePathFilter`.
- Savoir pourquoi un routage asymétrique fonctionne… jusqu'à ce qu'un contrôle à états ou un filtrage par chemin inverse le rencontre.

**Prérequis** : M07-E06, M07-E14, M07-E20 ; `lab/bin/check 07 41` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : chaque VM de la maquette a une interface d'administration sur `vsandbox` (`eth0`, route par défaut) et des interfaces de fabric ; `leaf01`, `srv01` et `srv02` y ont des adresses fixes (10.10.99.251, .252, .253). `srv01` et `srv02` ne parlent pas BGP : leur leaf joint leur boucle par une route statique (M07-E14). Le chemin normal entre les boucles de `srv01` et `srv02` passe par la fabric, **dans les deux sens**.

**Injection** : `lab/bin/break 07 41` (3 variantes).

**Travail demandé**
1. Reproduis et confirme l'observation de Karim avec deux captures simultanées : sur `srv02` (la réponse part-elle, et par quelle interface ?) et sur `srv01` (arrive-t-elle, et par quelle interface ?).
2. Reconstitue le chemin de la réponse saut par saut avec `ip route get` en précisant la source (et, sur un routeur, l'interface d'entrée). Compare-le au chemin de la requête.
3. Trouve **où** la réponse est jetée et **pourquoi** : quel mécanisme, avec quel compteur pour le prouver ?
4. Corrige la **cause** (le chemin asymétrique), pas seulement le symptôme. Discute dans ton journal : faut-il garder le filtrage strict par chemin inverse sur ces machines ? Quel mode convient à un serveur, à un routeur de fabric en ECMP, à une passerelle de bordure ?
5. Vérifie le retour dans les deux sens et que rien de ce que Lucas a laissé ne subsiste (y compris ce que `ip route` n'affiche pas).

**Critères de réussite**
- [ ] `srv01` et `srv02` se joignent de boucle à boucle dans les deux sens.
- [ ] Sur `srv01`, `srv02`, `leaf01` et `leaf02`, la route (règles comprises) vers les boucles des serveurs passe par la fabric, pas par le VLAN 99.
- [ ] Ton journal contient les deux captures, le chemin aller et retour reconstitués et la preuve du mécanisme qui jetait la réponse.

**Vérification** : `lab/bin/check 07 41`

<details><summary>Indice 1</summary>

`ip route get <destination> from <source>` sur l'émetteur de la réponse donne l'interface de sortie **réelle**, règles de routage par politique comprises ; `ip route show` seul ne regarde que la table `main`. Sur un routeur, ajoute `iif <interface d'entrée>` pour simuler un paquet relayé.
</details>

<details><summary>Indice 2</summary>

Un paquet qui arrive sur une interface et disparaît sans qu'aucune règle nftables ne compte quoi que ce soit : regarde `nstat -az IPReversePathFilter` (avant et après un essai) et `sysctl -a 2>/dev/null | grep '\.rp_filter'`. La valeur qui s'applique à une interface est le maximum entre `conf.all` et `conf.<interface>`. Et un réglage `sysctl -w` disparaît au redémarrage, pas un fichier de `/etc/sysctl.d/`.
</details>

**Pour aller plus loin** : remplace l'accès d'administration des VMs de la maquette par une **VRF** de gestion (`ip link add mgmt type vrf table 10`) pour que le réseau d'administration ne puisse plus jamais servir de chemin de données ; lis la [documentation VRF du noyau](https://docs.kernel.org/networking/vrf.html) et la [RFC 3704](https://www.rfc-editor.org/rfc/rfc3704).

---

### M07-E42 — Panne : la fabric perd la moitié de son trafic  `BF` `★★★`

> **Ticket INC-3408** — *De : Karim Benali*
> La fabric de la maquette a perdu la moitié d'elle-même. *(L'injection précise ce qu'on observe : des flux qui échouent, ou tout le trafic sur un seul spine.)* Toutes les sessions BGP sont établies. C'est exactement le genre de panne que je veux savoir diagnostiquer avant Kubernetes.

**Objectifs pédagogiques**
- Vérifier l'ECMP à chaque étage : RIB de BGP (chemins multiples, `multipath`), FIB de zebra, table du noyau (`nexthop … nexthop …`), et sur le fil (compteurs par spine).
- Comprendre comment le noyau choisit un chemin parmi plusieurs (hachage L3 ou L4 selon `fib_multipath_hash_policy`) et pourquoi une panne d'un chemin ne touche qu'une partie **stable** des couples source/destination.
- Distinguer « le plan de contrôle annonce un chemin » de « le plan de données le relaie ».

**Prérequis** : M07-E14 ; `lab/bin/check 07 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : fabric de M07-E14 : `spine01`, `spine02` (AS 65100), `leaf01` (65101), `leaf02` (65102), BGP *unnumbered*, deux chemins égaux entre leaves. Boucles : spines .1/.2, leaves .11/.12, serveurs .21/.22 dans 10.10.255.0/24.

**Injection** : `lab/bin/break 07 42` (3 variantes).

**Travail demandé**
1. Établis une matrice de joignabilité entre toutes les boucles (depuis chaque leaf et chaque serveur, avec l'adresse de boucle comme source) et une mesure de charge par spine (compteurs d'interfaces avant/après un échange). Qu'est-ce qui est stable, qu'est-ce qui varie ?
2. Sur `leaf01`, compare les trois étages : chemins BGP pour la boucle de `leaf02`, route installée par zebra, route du noyau. Où le nombre de chemins tombe-t-il à un (s'il tombe) ?
3. Si l'ECMP est intact, cherche quel spine ne relaie pas, et pourquoi le plan de contrôle ne l'a pas retiré.
4. Corrige la cause racine. Pour chaque variante possible que tu imagines (même si tu ne l'as pas eue), indique dans ton journal la commande qui la révèle en moins d'une minute.
5. Propose dans ton journal deux mécanismes qui auraient retiré automatiquement un spine qui ne relaie plus (indice : le plan de contrôle doit dépendre du plan de données).

**Critères de réussite**
- [ ] `leaf01` et `leaf02` ont deux chemins vers la boucle de l'autre leaf ; aucune limite d'ECMP à 1 dans leur configuration chargée.
- [ ] Les deux spines relaient (et relaieront après redémarrage), ont une session établie avec chaque leaf et en reçoivent des routes.
- [ ] Toutes les boucles se joignent ; ton journal contient la matrice de joignabilité initiale et la mesure de charge par spine.

**Vérification** : `lab/bin/check 07 42`

<details><summary>Indice 1</summary>

`vtysh -c 'show bgp ipv4 unicast 10.10.255.12/32'` affiche chaque chemin, s'il est `best` ou `multipath`, et d'où il vient ; `show ip route 10.10.255.12/32` montre ce que zebra a installé ; `ip route show 10.10.255.12` ce que le noyau utilise. Un chemin présent dans BGP mais absent de la FIB, ou un seul chemin dans BGP, ne racontent pas la même histoire.
</details>

<details><summary>Indice 2</summary>

Un routeur qui annonce des routes mais ne relaie pas : sa table est parfaite, ses sessions aussi ; ce sont ses **compteurs** qui parlent (`ip -s link`, `nstat -az | grep -i -E 'forw|noroute|InAddrErrors'`) et ses réglages de relais (`sysctl net.ipv4.ip_forward`, `vtysh -c 'show ip forwarding'`).
</details>

**Pour aller plus loin** : passe `net.ipv4.fib_multipath_hash_policy` à 1 (L4) sur les leaves et refais la matrice avec plusieurs ports source ; lis la [documentation ECMP de FRR](https://docs.frrouting.org/en/latest/zebra.html) et la section *BFD* de FRR comme réponse à la question 5.

---

### M07-E43 — Astreinte : la bordure en panne  `BF` `★★★★`

> **Ticket INC-3410** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte. Mardi, 6 h 40 : plusieurs remontées sur le réseau et la bordure (le détail s'affiche à l'injection). Une bascule de la bordure est planifiée à 9 h pour une maintenance de `pve01` : tout doit être redondant et sain d'ici là. Tiens-moi informée toutes les 30 minutes, puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples sur un réseau redondant : trier, prioriser par impact **et** par risque (une redondance perdue est invisible mais rend la prochaine bascule fatale).
- Éviter qu'une panne en masque une autre ; vérifier ses instruments avant de conclure.
- Communiquer pendant l'incident et rédiger un post-mortem sans recherche de coupable.

**Prérequis** : M07-E35 à M07-E42 (au moins une variante de chacun), M07-E29 (supervision), M07-E32 (tests de bascule), RB-071.
**Durée indicative** : 2 h 30 de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **trois** pannes distinctes parmi celles de M07-E35 à M07-E42 (variantes aléatoires ; les combinaisons qui se masquent complètement sont exclues), et en ajoute une quatrième, propre à l'astreinte, qui touche la bordure **sans** couper le trafic. `--variante N` force le triplet, pas les variantes. `--annuler` retire tout.

> ⚠️ **Attention** : la bascule planifiée à 9 h est fictive : **ne bascule pas la bordure** pour « tester » tant que les deux passerelles ne sont pas prouvées saines (keepalived, conntrackd, tunnels, FRR). Une bascule vers une passerelle dégradée coupe le lab, VPN d'administration compris : garde la console `qm terminal 1000` et `qm terminal 1009` ouvertes avant toute action sur la bordure, et suis RB-071 (retour arrière compris).

**Injection** : `lab/bin/break 07 43`

**Travail demandé**
1. **Triage (15 min max)** : liste les symptômes, leur impact métier (qui ne peut plus faire quoi ?) et le **risque** associé (qu'est-ce qui se passerait à 9 h ?). Vérifie d'abord tes instruments : SSH vers chaque hôte, agent QEMU de la maquette, `ms-verif-reseau`. Envoie la première communication.
2. **Diagnostic** : traite les pannes dans un ordre que tu justifies (impact, risque, dépendances entre couches). Tiens ton journal horodaté.
3. **Rétablissement** : corrige chaque cause racine ; après chaque correction, relance **tous** tes tests de départ.
4. **Avant 9 h** : prouve que la bordure peut basculer (sans basculer) : état des deux passerelles, services, synchronisation, tunnels prêts à suivre.
5. **Clôture** : communication de fin d'incident, `--annuler` pour clore, puis post-mortem rédigé à partir de `modules/00-lab/ressources/M00-E46/modele-post-mortem.md`, enregistré dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-3410.md` et publié par MR.

**Critères de réussite**
- [ ] Toutes les vérifications de M07-E35 à M07-E42 sont vertes (le contrôle les rejoue toutes) et aucune panne n'est encore marquée active.
- [ ] Sur `gw01` et `gw02`, keepalived (et conntrackd) sont actifs **et activés** ; une seule passerelle porte les VIP.
- [ ] Le post-mortem contient une chronologie horodatée, les quatre causes racines, l'analyse de la détection (qu'est-ce qui aurait dû alerter avant Nadia ?) et des actions correctives avec responsable et échéance ; le journal contient au moins quatre communications d'incident.

**Vérification** : `lab/bin/check 07 43`

<details><summary>Indice 1</summary>

Une panne qui ne fait rien voir aux utilisateurs n'est pas une panne mineure si elle supprime une redondance : demande-toi pour chaque élément de la bordure (VRRP, conntrackd, tunnels, FRR) « que se passe-t-il si la passerelle active s'arrête **maintenant** ? ». `ms-verif-reseau` et `lab/bin/check 07 25` à `07 27` répondent en partie.
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 07 35` à `07 42` sont des sondes ciblées : lance-les pendant le triage pour cartographier ce qui est rouge. Un contrôle rouge n'est pas forcément une panne injectée : ce peut être la conséquence d'une autre (un tunnel peut dépendre d'une route, une route d'une session).
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui) et mesure le temps jusqu'au **premier diagnostic juste** de chaque panne : c'est le chiffre que la supervision doit faire baisser.

---

### M07-E44 — Sous le capot : le voyage d'un paquet  `LAB` `★★★`

> **Ticket PLAT-885** — *De : Karim Benali*
> Pendant les pannes, j'ai entendu « ça passe par la passerelle » et « le VRRP gère ». Je veux que tu saches **montrer** ce qui se passe réellement quand `adm01` ouvre une page de GitLab par la VIP des répartiteurs : chaque trame, chaque décision de routage, chaque règle traversée, chaque état créé. Et ce qui maintient tout cela en vie en arrière-plan (VRRP, BGP). Compte rendu pour les prochains arrivants.

**Objectifs pédagogiques**
- Observer la couche 2 d'un hyperviseur : pont VLAN-aware, étiquettes 802.1Q, table de commutation (`bridge fdb`), interfaces `tap` des VMs.
- Observer la couche 3 et le filtrage d'une passerelle Linux : décision de routage (`ip route get … iif …`), trace nftables (`meta nftrace`, `nft monitor trace`), suivi des connexions (`conntrack -L`, `conntrack -E`), NAT éventuel.
- Observer le plan de contrôle qui rend tout cela redondant : annonces VRRP (fréquence, priorité, destination unicast), messages BGP (KEEPALIVE, UPDATE), et ce qui se passe sur le fil lors d'une bascule de répartiteur.

**Prérequis** : M07-E12, M07-E13, M07-E16, M07-E25, M07-E27, M07-E30.
**Durée indicative** : 3 h.

**Contexte technique**
- Flux étudié : `adm01` (10.10.10.10, VLAN 10) → `https://gitlab.par1.medisphere.internal` → VIP 10.10.70.200 (VLAN 70, `lb01`/`lb02`) → `git01` (10.10.20.12, VLAN 20). Il traverse la passerelle active **deux fois** (MGMT → DMZ, puis DMZ → INFRA).
- Sur `pve01`, les VMs sont reliées au pont `vmbr1` par des interfaces `tap<VMID>i<N>` ; la zone SDN `lab` crée une interface par VNet. Sur les passerelles, les sous-interfaces sont `ens19.<VLAN>`.
- Trace nftables : une règle `meta nftrace set 1` dans une chaîne de type `filter` accrochée tôt (priorité inférieure à celle de la table `inet filter`) marque les paquets à suivre ; `nft monitor trace` affiche chaque règle traversée.

> ⚠️ **Attention** : tu observes la **passerelle active** et `pve01` en production. Tout ce que tu poses est en lecture ou en marquage : une **table nftables dédiée** (jamais une règle insérée dans `inet filter`), retirée à la fin (`nft delete table inet trace_m07`) ; des captures `tcpdump` toujours bornées (`-c`, filtre précis) ; `conntrack -E` arrêté à la fin. Avant de commencer, ouvre une console `qm terminal` de la passerelle active : si une manipulation coupe ta session SSH, `nft delete table inet trace_m07` depuis la console rétablit tout. Ne lance pas de capture sans filtre sur `vmbr1` : tout le lab y passe.

**Travail demandé**
1. **Couche 2 sur `pve01`.** Trouve l'interface `tap` d'`adm01` et celle de la passerelle active. Montre les VLAN autorisés sur chacune (`bridge vlan show`), l'entrée de la table de commutation pour l'adresse matérielle d'`adm01` et pour celle qui répond à 10.10.10.1 (`bridge fdb show`). Capture (bornée) une requête d'`adm01` vers la VIP : où l'étiquette 802.1Q apparaît-elle, où disparaît-elle ?
2. **Résolution et passerelle.** Sur `adm01`, quelle adresse matérielle est associée à 10.10.10.1 ? À quelle machine appartient-elle ? Que se passerait-il pour cette entrée lors d'une bascule (et quel paquet la met à jour) ?
3. **Couche 3 sur la passerelle active.** Fais prendre à la passerelle la décision de routage du premier passage (`ip route get 10.10.70.200 from 10.10.10.10 iif ens19.10`) puis du second (depuis le répartiteur actif vers `git01`). Pose la table de trace, ouvre la page de GitLab depuis `adm01`, et relève les chaînes et règles traversées pour le premier paquet d'une connexion et pour les suivants.
4. **Suivi des connexions.** Liste les entrées `conntrack` des deux connexions (client → VIP, répartiteur → `git01`), avec leur état et leur délai. Que réplique `conntrackd` vers la passerelle de secours, et quand ?
5. **Le répartiteur.** Sur le répartiteur actif, montre les deux connexions TCP (côté client, côté serveur) et l'adresse source utilisée vers `git01`. Que voit `git01` comme adresse de client, et comment le retrouve-t-il ?
6. **Plan de contrôle.** Capture 20 secondes d'annonces VRRP sur `ens19.10` de la passerelle active (source, destination, VRID, priorité, intervalle) et sur le VLAN 70 entre `lb01` et `lb02`. Capture les échanges BGP entre la bordure et `leaf01` (KEEPALIVE, éventuellement UPDATE) et relie leur fréquence aux temporisateurs affichés par `show bgp neighbors`.
7. **Bascule observée.** Pendant une capture sur `adm01` (`ip neigh` en boucle) et une capture ARP sur le VLAN 70, arrête proprement keepalived sur le répartiteur actif (RB-070), observe les ARP gratuits émis par le nouveau maître et l'effet sur la connexion en cours, puis rétablis-le.
8. **Nettoyage et compte rendu.** Retire la table de trace, arrête toute capture et tout `conntrack -E`. Rédige `docs/socle/analyses/voyage-paquet.md` : `## Couche 2 : pont et VLAN`, `## Couche 3 : routage`, `## Filtrage et suivi des connexions`, `## Plan de contrôle : VRRP et BGP`, `## Réponses aux questions`, avec les extraits annotés.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Combien de fois le paquet est-il commuté, routé et filtré entre `adm01` et `git01` ? Combien d'entrées `conntrack` existent pour une seule page de GitLab, et sur quelles machines ?
2. Pourquoi la trace nftables montre-t-elle toutes les règles pour le premier paquet, et presque aucune pour les suivants ?
3. Avec VRRP sans adresse MAC virtuelle (`use_vmac` absent), quelle adresse matérielle `adm01` associe-t-il à 10.10.10.1 ? Quel est le coût d'une bascule pour les clients, et qu'apporterait `use_vmac` ?
4. Pourquoi les annonces VRRP de la bordure sont-elles en unicast, et que faut-il changer quand on ajoute une troisième passerelle ?
5. Avec les temporisateurs observés, combien de temps une panne silencieuse de `leaf01` (sans coupure de lien) met-elle à être détectée par la bordure ? Comment le réduire sans rendre la session instable ?
6. Dans la bascule de l'étape 7, la connexion en cours a-t-elle survécu ? Pourquoi (ou pourquoi pas), et que changerait une synchronisation des sessions entre répartiteurs (tables *stick* et *peers* de HAProxy) ?
7. Cite une panne de M07-E35 à M07-E42 que chacune des étapes 1, 3, 4 et 6 aurait permis de localiser en moins de 5 minutes, et la ligne décisive.

**Critères de réussite**
- [ ] Le compte rendu existe, est commité, et contient les cinq sections avec des extraits annotés (`bridge fdb`, capture avec étiquettes VLAN, `ip route get`, trace `nftrace`, `conntrack`, annonces VRRP, messages BGP).
- [ ] Les 7 questions sont traitées.
- [ ] Aucune capture, trace nftables, `nft monitor` ni `conntrack -E` ne reste actif sur `pve01` et les passerelles ; la table `inet trace_m07` n'existe plus.

**Vérification** : `lab/bin/check 07 44`

<details><summary>Indice 1</summary>

`qm config 1001 | grep ^net` donne l'adresse matérielle d'`adm01` ; l'interface sur `pve01` est `tap1001i0`. `tcpdump -eni vmbr1 -c 20 'vlan 10 and host 10.10.10.10'` affiche les en-têtes Ethernet avec l'étiquette ; sur `tap1001i0`, la même trame est sans étiquette. `bridge -d vlan show dev tap1001i0` montre le VLAN `PVID Egress Untagged`.
</details>

<details><summary>Indice 2</summary>

La table de trace : `table inet trace_m07 { chain pre { type filter hook prerouting priority -350; ip saddr 10.10.10.10 ip daddr 10.10.70.200 tcp dport 443 meta nftrace set 1; } }`, chargée par `nft -f`, puis `nft monitor trace` dans un second terminal. `conntrack -L -d 10.10.70.200` et `conntrack -L -d 10.10.20.12` ; `conntrack -E -p tcp --dport 443` montre la création et la destruction en direct.
</details>

**Pour aller plus loin** : refais le voyage pour un poste de Lyon (`lyo-pc01` → 10.10.20.1) : paquet en clair sur `wg2`, chiffré dans UDP 51822 sur le VLAN 99, décision de routage par la route BGP apprise de LYO1 ; et lis la [documentation de la trace nftables](https://wiki.nftables.org/wiki-nftables/index.php/Ruleset_debug/tracing).

---

### M07-E45 — Questions expert : réseau et haute disponibilité  `Q` `★★★`

> **Ticket PLAT-886** — *De : Karim Benali*
> Dernière étape avant la recette du socle v2 : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme senior. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la documentation et les RFC, et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes manipulés dans ce module (agrégation, VLAN, routage dynamique, ECMP, VRRP, suivi des connexions, répartition de charge, MTU, tunnels).
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M07-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Pourquoi un pont Linux ne relaie-t-il pas les trames LACP entre deux VMs, et pourquoi cette « limitation » est-elle en réalité le comportement attendu d'un équipement conforme à 802.1D/802.1AX ?
2. QCM — Un bond Linux 802.3ad a deux membres ; `/proc/net/bonding/bond0` montre deux `Aggregator ID` différents et `Partner Mac Address: 00:00:00:00:00:00` pour les deux. La cause la plus probable :
   a) un des câbles est défectueux ; b) le commutateur n'est pas configuré en LACP (ports indépendants ou agrégat statique) ; c) `miimon` vaut 0 ; d) `xmit_hash_policy` n'est pas la même des deux côtés.
3. Compare `active-backup`, `balance-xor` et `802.3ad` : besoin côté commutateur, détection de panne, répartition d'un flux unique, comportement face à un commutateur qui ne suit pas.
4. Qu'apporte Open vSwitch par rapport au pont Linux pour un hyperviseur (citer trois fonctions), et qu'est-ce qu'il coûte ?
5. Décris l'automate BGP de `Idle` à `Established`. Pour chacun des états bloquants `Active`, `OpenSent` et `Established` sans préfixe, donne deux causes et la commande qui les distingue.
6. RFC 8212 : que change `bgp ebgp-requires-policy`, pourquoi est-ce une bonne valeur par défaut, et pourquoi le profil `datacenter` de FRR la désactive-t-il ?
7. BGP *unnumbered* : comment deux routeurs établissent-ils une session sans adresse IPv4 configurée (découverte du voisin, RFC 5549/8950), et quel est le prochain saut d'une route IPv4 apprise ainsi ?
8. QCM — Dans une fabric leaf-spine en eBGP, les deux spines sont dans le même AS (65100). Que se passe-t-il pour une route annoncée par `leaf01` qui atteint `spine01`, puis `leaf02`, puis `spine02` ?
   a) elle est acceptée et crée une boucle ; b) `spine02` la rejette (son AS figure déjà dans l'AS_PATH) ; c) `leaf02` ne la réannonce pas aux spines (*split horizon*) ; d) elle est acceptée mais jamais choisie.
9. ECMP dans le noyau Linux : comment un chemin est-il choisi (politiques de hachage 0, 1 et 2) ? Pourquoi le hachage L3 rend-il une panne de chemin « stable » pour un couple donné, et pourquoi le L4 est-il préférable pour répartir la charge ?
10. `rp_filter` strict, lâche, désactivé : lequel sur un serveur à une seule interface de données, sur un routeur de fabric en ECMP, sur une passerelle de bordure avec routage asymétrique possible ? Justifie.
11. VRRP : décris l'élection, *Master_Down_Interval*, la préemption et `nopreempt`. Pourquoi les passerelles de MédiSphère choisissent-elles leur réglage de préemption (M07-E25), et quel est le risque de l'autre choix ?
12. QCM — Deux membres keepalived d'une même paire ont `virtual_router_id 51` et `virtual_router_id 52`, même VIP. Résultat :
    a) keepalived refuse de démarrer ; b) deux maîtres, ARP qui alterne entre deux adresses matérielles ; c) le membre de plus haute priorité gagne quand même ; d) la VIP n'est portée par personne.
13. *Split-brain* VRRP : trois causes, trois effets observables, trois protections (techniques ou organisationnelles).
14. `conntrackd` en mode FTFW : que synchronise-t-il, quand, et pourquoi une bascule sans lui coupe-t-elle les connexions TCP qui traversent un pare-feu à états ? Pourquoi un lien dédié (ou un VLAN choisi) pour la synchronisation ?
15. HAProxy : différence entre 502, 503 et 504 ; entre `L4CON`, `L4TOUT`, `L6RSP`, `L7STS` ; et entre un contrôle de santé et `observe layer7`.
16. Terminer TLS sur le répartiteur et ré-chiffrer vers le serveur, ou passer TLS de bout en bout (mode TCP, SNI) : avantages, inconvénients, conséquences pour les certificats, les journaux et l'adresse du client.
17. PMTUD : qui émet l'ICMP « fragmentation nécessaire », vers qui, et pourquoi un pare-feu à états qui oublie `related` crée-t-il un trou noir ? Comparer trois remèdes : MSS *clamping*, sondage par la couche transport (RFC 8899), MTU uniforme.
18. *Jumbo frames* : pourquoi seulement sur les VLAN 30, 31 et 51 du lab ? Que se passe-t-il si une seule VM d'un de ces VLAN reste à 1500 (TCP, UDP, trafic Ceph) ?
19. WireGuard : expliquer le routage cryptographique (`AllowedIPs` en sortie **et** en entrée), l'itinérance de l'extrémité, et pourquoi deux passerelles qui portent la même clé ne doivent jamais avoir le tunnel actif en même temps.
20. QCM — Depuis un routeur, `ping 10.10.20.1` à travers un tunnel WireGuard échoue avec `ping: sendmsg: Required key not available`. Cause :
    a) la poignée de main n'a jamais eu lieu ; b) aucun pair n'a 10.10.20.1 dans ses `AllowedIPs` ; c) la clé privée locale est absente ; d) le port UDP est filtré.

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 4 : la [documentation du bonding](https://docs.kernel.org/networking/bonding.html), IEEE 802.1AX (résumé dans la documentation du bonding), `ovs-vswitchd.conf.db(5)`. Pour 5 à 10 : RFC 4271, 8212, 5549/8950, 7938 (BGP dans les centres de données), 3704, et la documentation `ip-sysctl` du noyau.
</details>

<details><summary>Indice 2</summary>

Pour 11 à 14 : RFC 9568 (VRRP v3), `keepalived.conf(5)`, `conntrackd.conf(5)`. Pour 15 et 16 : la [configuration de HAProxy 3.2](https://docs.haproxy.org/3.2/configuration.html). Pour 17 à 20 : RFC 1191, 4821, 8899, et le [livre blanc de WireGuard](https://www.wireguard.com/papers/wireguard.pdf).
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur la maquette (5 minutes, reproductible), à présenter à Karim.
