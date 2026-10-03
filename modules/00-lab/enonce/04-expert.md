# Module 00 — Palier 4 : Expert

Le socle tourne. Il route, résout, synchronise, sauvegarde et relie les deux sites. Claire Morel annonce la suite : « Un socle qu'on ne sait pas dépanner n'est pas livrable. Avant la recette, Nadia va te mettre en astreinte d'entraînement. Karim a préparé des pannes. » Ce palier est celui des incidents : huit pannes réalistes, une astreinte où elles se combinent, puis trois exercices qui descendent sous le capot (chemin d'un paquet, performances disque, questions d'entretien). On n'y apprend presque aucune commande nouvelle. On y apprend la **méthode** : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive.

## Règles du jeu des pannes (M00-E38 à M00-E46)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 00 38
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 00 38`) : il doit être vert. Une panne posée sur un lab déjà malade fausse tout le diagnostic.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 00 38 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi).
- Les pannes ne touchent qu'aux ressources du lab (VMs du pool `lab`, `gw01`, `adm01`, `dns01`, `pbs01`) et ne détruisent aucune donnée. `pve01` n'est jamais décalé dans le temps ni redémarré.
- **Tiens un journal de diagnostic** pour chaque panne, dans ton dépôt de documentation `~/medisphere` sur `adm01` (créé en M00-E25, chemin `WB_DEPOT` de `lab/lab.env`). Rédige-le dans `docs/socle/journal/`. Format libre, mais chaque entrée contient : heure, hypothèse, commande, résultat observé, conclusion. C'est ce journal qui alimentera le post-mortem de M00-E46.
- Le **temps cible** est indicatif : c'est l'ordre de grandeur attendu d'un administrateur confirmé qui connaît son socle. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours** : certaines pannes coupent l'accès SSH à une VM. Tu as toujours la console de la VM (`qm terminal <VMID>` si la console série du template est active, ou noVNC dans l'interface web de `pve01`) et l'agent QEMU (`qm guest exec`). Repère-les **avant** d'en avoir besoin.

---

### M00-E38 — Panne : plus d'accès Internet depuis INFRA  `BF` `★★`

> **Ticket INC-2604** — *De : Julien Petit*
> Salut, depuis ce matin `dns01` ne sort plus du tout vers Internet : `apt update` reste bloqué puis échoue sur deb.debian.org, et un `curl` vers https://deb.debian.org n'aboutit pas. Je n'ai rien changé sur la VM. Tu peux regarder ? Je dois passer les mises à jour de sécurité aujourd'hui.

**Objectifs pédagogiques**
- Dérouler un diagnostic de connectivité sortante dans l'ordre du chemin : VM → passerelle → routage → filtrage → traduction d'adresses → Internet.
- Lire l'état d'exécution d'un routeur Linux (sysctl, jeu de règles chargé, compteurs) et le comparer à sa configuration persistante.
- Distinguer « le paquet n'est pas routé », « le paquet est jeté » et « le paquet sort mais la réponse ne revient pas ».

**Prérequis** : M00-E10, M00-E13, M00-E26 ; `lab/bin/check 00 38` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 00 38` (3 variantes).

**Travail demandé**
1. Injecte la panne et reproduis le symptôme depuis `dns01`. Note précisément ce qui échoue et ce qui fonctionne encore (résolution DNS ? ping de la passerelle ? ping d'une IP publique ? TCP/443 ?).
2. Délimite le périmètre : `adm01` (VLAN 10) est-il touché ? `pve01` joint-il encore `dns01` ? Conclus sur l'endroit où le chemin se rompt avant d'ouvrir une session sur `gw01`.
3. Sur `gw01`, trouve la cause racine en t'appuyant sur des **mesures** (compteurs, captures, état du noyau), pas sur la relecture de la configuration seule.
4. Corrige. Si la configuration persistante était saine, explique pourquoi la panne aurait (ou n'aurait pas) survécu à un redémarrage de `gw01`.
5. Propose une mesure de supervision qui aurait détecté la panne avant Julien (quoi mesurer, d'où, à quelle fréquence).

**Critères de réussite**
- [ ] `dns01` joint Internet en ICMP et en TCP/443, par adresse et par nom.
- [ ] La configuration en mémoire de `gw01` est cohérente avec sa configuration persistante.
- [ ] Ton journal de diagnostic montre la cause racine, la mesure qui l'a prouvée et la prévention proposée.

**Vérification** : `lab/bin/check 00 38`

<details><summary>Indice 1</summary>

Coupe le chemin en deux : si `dns01` joint `10.10.20.1` mais pas `9.9.9.9`, le problème est sur `gw01` ou au-delà. Depuis `gw01` lui-même, Internet répond-il ? Si oui, le problème concerne ce que `gw01` fait des paquets **des autres**.
</details>

<details><summary>Indice 2</summary>

Un routeur Linux a trois raisons de ne pas faire suivre un paquet : il ne route pas du tout, son pare-feu le jette, ou il le fait sortir avec une adresse source que personne ne sait renvoyer. Pour chacune, il existe une commande qui la prouve en quelques secondes : `sysctl`, les compteurs de `nft list ruleset`, et `tcpdump -ni ens18` pendant un ping depuis `dns01`.
</details>

**Pour aller plus loin** : refais l'exercice jusqu'à avoir rencontré les trois variantes. Pour chacune, note la première commande qui l'aurait révélée : c'est l'ébauche de ton runbook « perte d'Internet du lab ».

---

### M00-E39 — Panne : `adm01` ne joint plus `dns01`  `BF` `★★`

> **Ticket INC-2605** — *De : Karim Benali*
> Depuis `adm01`, je n'arrive plus à me connecter à `dns01` : `ssh dns01` part en délai dépassé et le ping ne répond pas non plus. La VM est pourtant démarrée dans l'interface Proxmox. Personne n'admet y avoir touché.

**Objectifs pédagogiques**
- Diagnostiquer une perte de connectivité **couche 2 / couche 3** entre deux VMs de VLANs différents, de l'hyperviseur jusqu'à la pile réseau de la VM.
- Utiliser les accès hors bande d'une VM (console, agent QEMU) quand le réseau est coupé.
- Lire la configuration réseau d'une VM côté Proxmox (VNet, tag, pare-feu de VM) et ses effets côté hôte (`bridge`, `ip -d link`).

**Prérequis** : M00-E12, M00-E27, M00-E28.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 00 39` (3 variantes).

**Travail demandé**
1. Reproduis le symptôme. Le DNS fonctionne-t-il encore (`dig @10.10.20.10 …`) ? Cette information seule élimine une partie des hypothèses : lesquelles ?
2. Vérifie depuis `gw01` si `dns01` est joignable sur son propre VLAN et si `gw01` voit son adresse MAC (table ARP/voisins).
3. Remonte jusqu'à `pve01` : sur quel bridge, avec quelle étiquette et à travers quels équipements virtuels la carte de `dns01` est-elle branchée ?
4. Si le réseau ne te permet pas d'entrer dans `dns01`, entres-y autrement et inspecte sa configuration IP.
5. Corrige à la racine, puis vérifie que **tous** les flux de `dns01` sont revenus (SSH, DNS depuis les autres VLANs, relais DHCP, NTP).

**Critères de réussite**
- [ ] `adm01` joint `dns01` en ICMP, en SSH et en DNS (UDP et TCP).
- [ ] La carte réseau de `dns01` est sur le réseau INFRA, avec l'adresse 10.10.20.10/24 et la passerelle 10.10.20.1.
- [ ] Ton journal explique comment tu as accédé à `dns01` quand le réseau était coupé (si la variante l'a imposé).

**Vérification** : `lab/bin/check 00 39`

<details><summary>Indice 1</summary>

`ip neigh show dev ens19.20` sur `gw01` après un ping vers 10.10.20.10 : `REACHABLE`, `STALE`, `FAILED` ou `INCOMPLETE` ne racontent pas la même histoire. Une adresse MAC apprise prouve que la couche 2 fonctionne jusqu'à la VM.
</details>

<details><summary>Indice 2</summary>

Côté hyperviseur : `qm config 1002`, `bridge vlan show`, `ip -d link show tap1002i0` et la présence éventuelle d'interfaces `fwbr1002i0` / `fwpr1002p0` / `fwln1002i0`. Côté VM, sans réseau : `qm guest exec 1002 -- ip -4 addr` ou la console.
</details>

<details><summary>Indice 3</summary>

Si la couche 2 fonctionne et que la VM ne répond qu'à certains ports, cherche un filtrage **entre** le bridge et la VM, pas dans la VM ni sur `gw01`. Le pare-feu Proxmox se lit avec `pve-firewall status`, `/etc/pve/firewall/<VMID>.fw` et l'onglet *Firewall* de la VM.
</details>

**Pour aller plus loin** : pour chaque variante, indique laquelle aurait été détectée par une supervision de type « ping depuis `adm01` », laquelle par « résolution DNS depuis `adm01` », et laquelle par aucune des deux.

---

### M00-E40 — Panne : la résolution DNS ne fonctionne plus  `BF` `★★★`

> **Ticket INC-2607** — *De : Nadia Roussel*
> Plusieurs remontées ce matin : depuis `adm01`, `apt update` échoue avec « Temporary failure resolving 'deb.debian.org' ». Un `git clone` depuis GitHub échoue aussi (« Could not resolve host »). Les accès par adresse IP fonctionnent.

**Objectifs pédagogiques**
- Décomposer une résolution de noms en maillons testables séparément : configuration du client (`resolv.conf`, `systemd-resolved`, `nsswitch`), transport (UDP/TCP 53, filtrage), serveur (service, configuration, zone locale), récursion amont.
- Utiliser `dig` comme un instrument de mesure (`@serveur`, `+tcp`, `+norecurse`, `+trace`, statut et temps de réponse) plutôt que `ping nom`.
- Lire les journaux de dnsmasq et valider sa configuration avant redémarrage.

**Prérequis** : M00-E13, M00-E15, M00-E26.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 00 40` (4 variantes).

**Travail demandé**
1. Reproduis le symptôme et établis une **matrice de tests** : nom interne / nom externe × résolveur système de `adm01` / `dig @10.10.20.10` en UDP / en TCP × depuis `adm01` / depuis `dns01` / depuis `gw01`. Remplis-la avant toute correction.
2. Déduis de la matrice le maillon cassé. Une seule case de la matrice doit te permettre d'éliminer chaque hypothèse : montre-le dans ton journal.
3. Corrige. Si un service refuse de redémarrer, trouve pourquoi dans ses journaux avant de toucher à sa configuration.
4. Explique pourquoi `ssh dns01` fonctionnait encore pendant la panne (indice : regarde ton `~/.ssh/config`), et ce que ce choix t'a apporté.

**Critères de réussite**
- [ ] Depuis `adm01`, les noms internes (dont le nom court `dns01`, via le domaine de recherche) et externes se résolvent par le résolveur système.
- [ ] `dig @10.10.20.10` répond en UDP et en TCP ; la zone locale, les enregistrements inverses et la récursion fonctionnent.
- [ ] La configuration de dnsmasq passe `dnsmasq --test`.
- [ ] Ton journal contient la matrice de tests remplie.

**Vérification** : `lab/bin/check 00 40`

<details><summary>Indice 1</summary>

`dig @10.10.20.10 adm01.par1.medisphere.internal` et `dig @10.10.20.10 deb.debian.org` n'interrogent pas les mêmes maillons. `getent hosts deb.debian.org` interroge encore d'autres maillons (ceux du client). Compare les trois.
</details>

<details><summary>Indice 2</summary>

`;; connection timed out; no servers could be reached`, `status: SERVFAIL` et `status: REFUSED` sont trois pannes différentes. Si UDP échoue et TCP réussit vers le même serveur, ce n'est pas le serveur. Sur `dns01` : `systemctl status dnsmasq`, `journalctl -u dnsmasq`, `dnsmasq --test`.
</details>

<details><summary>Indice 3</summary>

Côté client, `resolvectl status` (si `systemd-resolved` est actif) et `ls -l /etc/resolv.conf` (lien symbolique ou fichier ?) indiquent qui décide vraiment du serveur interrogé.
</details>

**Pour aller plus loin** : écris une sonde (script de 15 lignes) qui remplit automatiquement ta matrice de tests et affiche le maillon défaillant. Elle te servira en M00-E46.

---

### M00-E41 — Panne : les petits échanges passent, les gros bloquent  `BF` `★★★`

> **Ticket INC-2611** — *De : Karim Benali*
> Comportement bizarre depuis l'intervention réseau d'hier soir sur `gw01`. Les sessions SSH s'ouvrent, le ping passe, le DNS répond… mais tout ce qui transfère du volume se fige : un `apt update` reste à 0 %, un `scp` démarre puis stagne à quelques Ko, ou une sauvegarde reste bloquée à quelques pour cent. Les petits échanges passent, les gros bloquent.

**Objectifs pédagogiques**
- Reconnaître la signature d'un **trou noir PMTU** (Path MTU black hole) et la prouver par la mesure.
- Maîtriser `ping -M do -s`, `tracepath`, `tcpdump` (taille des segments, retransmissions, ICMP type 3 code 4) et `ip link`/`ip route get` pour localiser le maillon.
- Comprendre le rôle des messages ICMP « fragmentation needed », du MSS et du *MSS clamping*.

**Prérequis** : M00-E10, M00-E21, M00-E26.
**Durée indicative** : 60 min (temps cible).

**Injection** : `lab/bin/break 00 41` (3 variantes ; le ticket affiché précise quel flux est touché).

**Travail demandé**
1. Reproduis le symptôme sur le flux indiqué et prouve qu'il dépend de la **taille** des paquets, pas du protocole ni de l'application.
2. Mesure la MTU de chemin dans les deux sens du flux touché. Localise le saut où la taille maximale diminue.
3. Explique pourquoi la découverte de MTU de chemin (PMTUD) n'a pas résolu d'elle-même le problème. Prouve-le par une capture.
4. Corrige la cause racine. Puis décide, en le justifiant dans ton journal, si un *MSS clamping* sur `gw01` est utile **en plus** pour ce lab (pour quels flux, dans quel sens), et ce qu'il ne corrigerait pas.
5. Vérifie que tous les flux volumineux du lab sont revenus (téléchargements, transferts entre VMs, sauvegarde vers `pbs01`).

**Critères de réussite**
- [ ] Un ping non fragmentable de 1500 octets passe de `adm01` à `dns01` et de `dns01` à `adm01` ; un ping non fragmentable de 1300 octets passe de `pve01` à `pbs01` à travers le tunnel.
- [ ] Un transfert de plusieurs Mo aboutit dans les deux sens entre `adm01` et `dns01`, et `dns01` télécharge depuis deb.debian.org.
- [ ] Ton journal contient la capture (ou son extrait commenté) qui prouve la cause, et ta décision argumentée sur le MSS clamping.

**Vérification** : `lab/bin/check 00 41`

<details><summary>Indice 1</summary>

`ping -M do -s 1472 <cible>` envoie un paquet IP de 1500 octets interdit de fragmentation. Diminue la taille par dichotomie jusqu'à ce que ça passe. Fais-le depuis les deux extrémités : la MTU d'un chemin n'est pas forcément symétrique.
</details>

<details><summary>Indice 2</summary>

Pendant un `scp` qui stagne, capture sur `gw01` : `tcpdump -ni any 'icmp or (tcp and greater 1000)'`. Que devient le gros segment ? Un message ICMP part-il vers l'émetteur ? Arrive-t-il ? Les compteurs de `nft list ruleset` aident aussi.
</details>

<details><summary>Indice 3</summary>

Sur `gw01`, `ip -d link` donne la MTU de chaque interface et `ip route get <destination>` indique l'interface (et la MTU éventuelle de la route) utilisée pour une destination. Toutes les interfaces d'un même chemin devraient avoir des MTU cohérentes.
</details>

**Pour aller plus loin** : active temporairement `net.ipv4.tcp_mtu_probing=1` sur l'émetteur pendant la panne et observe la différence. Explique pourquoi ce n'est pas un correctif acceptable pour MédiSphère.

---

### M00-E42 — Panne : la sauvegarde nocturne a échoué  `BF` `★★`

> **Ticket INC-2612** — *De : Nadia Roussel*
> La notification de cette nuit indique que le job de sauvegarde vers `pbs-par2` s'est terminé en erreur pour les VMs du socle. Une relance manuelle de la sauvegarde de `dns01` échoue aussi. Pas de sauvegarde valide de la nuit : à corriger avant ce soir, et relance une sauvegarde pour qu'on reparte d'un point sain.

**Objectifs pédagogiques**
- Lire un journal de tâche `vzdump` et en extraire le message d'erreur utile.
- Distinguer les quatre étages d'une sauvegarde Proxmox → PBS : transport (réseau, TLS), authentification (jeton), autorisation (ACL), état du datastore (maintenance, espace, namespace).
- Corriger sans dégrader la sécurité (pas de « je donne `Admin` au jeton pour que ça marche »).

**Prérequis** : M00-E22, M00-E29, M00-E36.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 00 42` (4 variantes ; le script lance aussi une sauvegarde de `dns01`, qui échoue).

**Travail demandé**
1. Retrouve la tâche en échec (interface web ou `pvesh get /nodes/<nœud>/tasks`) et lis son journal complet. Note le message exact.
2. Reproduis l'erreur avec la commande la plus courte possible (sans relancer toute une sauvegarde à chaque essai).
3. Identifie l'étage en cause et confirme-le **côté PBS** (journal de tâches, `proxmox-backup-manager`), pas seulement côté `pve01`.
4. Corrige avec le moindre privilège, puis relance une sauvegarde de `dns01` et vérifie qu'elle est complète et listée dans le bon namespace.
5. Vérifie que la notification de succès est bien partie (M00-E29) : une chaîne d'alerte qui ne signale que les échecs ne prouve pas qu'elle fonctionne.

**Critères de réussite**
- [ ] Le stockage `pbs-par2` est actif et son contenu lisible depuis `pve01`, dans le namespace `par1`.
- [ ] Le datastore `ds-lab` accepte les écritures ; `wb-backup@pbs` et son jeton ont exactement les droits définis en M00-E22, pas plus.
- [ ] La dernière tâche de sauvegarde de `pve01` s'est terminée sans erreur.

**Vérification** : `lab/bin/check 00 42`

<details><summary>Indice 1</summary>

`pvesm status` puis `pvesm list pbs-par2` : si le stockage lui-même est inactif ou illisible, le problème est en amont de la sauvegarde. Si la liste fonctionne mais que l'écriture échoue, regarde du côté des droits et de l'état du datastore.
</details>

<details><summary>Indice 2</summary>

Côté PBS : `proxmox-backup-manager datastore show ds-lab`, `proxmox-backup-manager acl list`, `proxmox-backup-manager user permissions '<jeton>' --path /datastore/ds-lab/par1`, et le journal des tâches de l'interface PBS. Côté `pve01`, la section `pbs: pbs-par2` de `/etc/pve/storage.cfg` contient tout ce que `pve01` croit savoir du serveur.
</details>

**Pour aller plus loin** : pour chaque variante, rédige la ligne du runbook « sauvegarde en échec » : message d'erreur → étage → commande de confirmation → correctif.

---

### M00-E43 — Panne : le site PAR2 est injoignable  `BF` `★★★`

> **Ticket INC-2614** — *De : Nadia Roussel*
> Alerte de supervision : le stockage `pbs-par2` apparaît avec un point d'interrogation gris dans l'interface de `pve01`, et `ssh pbs01` depuis `adm01` ne répond plus. J'ai vérifié via l'iLO : `hp01` est allumé, la console PBS est accessible, aucune erreur. Le site PAR2 semble coupé du reste du monde.

**Objectifs pédagogiques**
- Diagnostiquer un tunnel WireGuard : établissement (poignées de main), transport UDP, routage par clé (*cryptokey routing*), routes système.
- Interpréter `wg show` (endpoint, latest handshake, transfer, allowed ips) et les erreurs du noyau (`Required key not available`).
- Comparer la configuration de deux extrémités sans jamais exposer de clé privée.

**Prérequis** : M00-E21, M00-E26.
**Durée indicative** : 45 min (temps cible).

**Injection** : `lab/bin/break 00 43` (3 variantes).

**Travail demandé**
1. Établis le périmètre : `gw01` joint-il `10.255.0.2` ? `10.20.10.10` ? `hp01` répond-il sur son adresse LAN ? Le tunnel est-il établi (dernière poignée de main) ?
2. Accède à `hp01`/`pbs01` par un autre chemin (console iLO, ou SSH sur son adresse LAN si M00-E21 l'autorise encore) et compare l'état WireGuard des deux extrémités.
3. Trouve la cause racine en t'appuyant sur `wg show`, `ip route get`, les compteurs nftables et une capture du trafic UDP entre les deux extrémités.
4. Corrige, puis vérifie toute la chaîne : tunnel, routage, stockage `pbs-par2`, NTP de `pbs01` via le tunnel.
5. Explique dans ton journal pourquoi une erreur sur l'`Endpoint` d'une seule des deux extrémités n'aurait probablement **pas** coupé ce tunnel.

**Critères de réussite**
- [ ] La dernière poignée de main sur `wg0` date de moins de 3 minutes, `10.255.0.2` et `10.20.10.10` répondent depuis `gw01` et `adm01`.
- [ ] `pve01` joint l'API de `pbs01` (TCP/8007) et le stockage `pbs-par2` est actif.
- [ ] `wg0.conf` de `gw01` est cohérent avec la configuration en cours d'exécution (`wg showconf wg0`).

**Vérification** : `lab/bin/check 00 43`

<details><summary>Indice 1</summary>

`wg show wg0` sur les deux extrémités. Pas de « latest handshake » (ou une valeur qui vieillit) : le tunnel ne s'établit pas — transport UDP ou clés. Poignée de main récente mais pas de trafic utile : le tunnel est établi, le problème est dans ce qui est routé **dedans**.
</details>

<details><summary>Indice 2</summary>

`ping 10.20.10.10` depuis `gw01` qui répond `ping: sendmsg: Required key not available` est un message de WireGuard, pas du réseau. Sur `gw01`, `tcpdump -ni ens18 udp port 51820` montre si les deux extrémités s'envoient quelque chose, et dans quel sens.
</details>

<details><summary>Indice 3</summary>

Pour comparer les clés sans rien exposer : la clé **publique** de chaque extrémité s'obtient avec `wg show wg0 public-key` ; compare-la avec ce que l'autre extrémité déclare pour son pair (`wg show wg0 peers`).
</details>

**Pour aller plus loin** : écris un contrôle de supervision du tunnel (âge de la dernière poignée de main, octets reçus qui augmentent) et le seuil d'alerte associé, en tenant compte de `PersistentKeepalive`.

---

### M00-E44 — Panne : une VM refuse de démarrer  `BF` `★★★`

> **Ticket DEV-0318** — *De : Julien Petit*
> La VM `sbx44` (5044) que tu m'as préparée pour mes tests refuse de démarrer : le bouton *Start* dans l'interface (et `qm start 5044`) renvoie une erreur. J'en ai besoin cet après-midi pour valider un correctif de MédiAgenda.

**Objectifs pédagogiques**
- Lire une erreur de démarrage de VM et remonter à la couche responsable : configuration Proxmox (`/etc/pve/qemu-server`), verrous, stockage, ressources de l'hôte, QEMU.
- Connaître les commandes de réparation propres (`qm unlock`, `qm rescan`, `pvesm set`, `qm showcmd`) et leurs risques.
- Ne jamais « réparer » en détruisant : sauvegarder la configuration avant toute modification manuelle.

**Prérequis** : M00-E07, M00-E11, M00-E19.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la panne ne touche jamais au socle. Le script prépare lui-même une VM jetable `sbx44` (VMID 5044, pool `lab`) par clone complet du template 9000, sur un stockage de type répertoire dédié `sbx-store` (créé sur `hdd-bulk` quand c'est possible). La première injection prend 1 à 3 minutes.

**Injection** : `lab/bin/break 00 44` (4 variantes).

**Travail demandé**
1. Reproduis l'erreur en ligne de commande et note le message exact.
2. Avant de modifier quoi que ce soit, copie la configuration actuelle de la VM hors de `/etc/pve` (horodatée).
3. Identifie la cause racine. Pour chaque commande de réparation envisagée, écris dans ton journal ce qu'elle fait réellement et ce qui pourrait mal tourner si ton diagnostic était faux.
4. Corrige, démarre la VM et vérifie qu'elle obtient une adresse DHCP du VLAN 99 (relais de M00-E14).
5. En fin d'exercice (après avoir rencontré les variantes qui t'intéressent), supprime la VM 5044 et le stockage `sbx-store`, puis vérifie qu'aucun volume orphelin ne subsiste.

**Critères de réussite**
- [ ] La VM 5044 est démarrée, sans verrou, avec une mémoire cohérente avec l'hôte et tous ses volumes présents.
- [ ] Le stockage qui porte ses disques est actif.
- [ ] Ton journal contient le message d'erreur initial et la justification de la commande de réparation choisie.

**Vérification** : `lab/bin/check 00 44` (avant le nettoyage de l'étape 5).

<details><summary>Indice 1</summary>

L'erreur affichée par `qm start` est souvent la dernière d'une chaîne. Regarde aussi le journal de la tâche dans l'interface, `journalctl -u pvedaemon -u pveproxy --since -10min` et, pour les erreurs de QEMU lui-même, `qm showcmd 5044 --pretty`.
</details>

<details><summary>Indice 2</summary>

`qm config 5044` (cherche une ligne `lock:`), `pvesm status`, `pvesm list sbx-store --vmid 5044`, `free -g` sur l'hôte. Compare ce que la configuration référence avec ce qui existe vraiment sur le stockage.
</details>

**Pour aller plus loin** : provoque toi-même, sur la VM 5044, une cinquième cause de non-démarrage que le script ne simule pas (par exemple un périphérique PCI ou un fichier ISO absent), documente le message obtenu et la correction.

---

### M00-E45 — Panne : horloges désynchronisées  `BF` `★★`

> **Ticket INC-2615** — *De : Nadia Roussel*
> En préparant le post-mortem d'hier, impossible de corréler les journaux : les entrées de `dns01` (journalctl, requêtes dnsmasq) sont en avance d'une dizaine de minutes sur celles de `gw01` et `adm01`. Pour un hébergeur HDS, la traçabilité horodatée n'est pas négociable : remets les horloges d'équerre et explique-moi pourquoi elles ont dérivé.

**Objectifs pédagogiques**
- Diagnostiquer une chaîne de temps (serveur `gw01` → clients) : service client, transport UDP/123, autorisation côté serveur, sélection de source.
- Lire `chronyc tracking`, `chronyc sources -v`, `chronyc sourcestats`, `chronyc clients`, `chronyc accheck`.
- Comprendre pourquoi un décalage important n'est pas rattrapé tout seul (pas, *slew*, `makestep`) et les risques d'un saut d'horloge.

**Prérequis** : M00-E31.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 00 45` (3 variantes).

**Travail demandé**
1. Mesure le décalage de chaque machine du lab par rapport à `gw01` et par rapport à une référence externe.
2. Détermine pourquoi `dns01` ne revient pas à l'heure : son client NTP fonctionne-t-il ? Atteint-il sa source ? La source accepte-t-elle de lui répondre ?
3. Corrige la cause racine, puis ramène l'horloge de `dns01` à l'heure **en justifiant la méthode** (laisser *slew*, forcer un pas, redémarrer le service) au regard des services qui tournent dessus.
4. Liste dans ton journal les autres conséquences concrètes qu'un décalage de 10 minutes aurait eues dans le socle (pense TLS, PBS, journaux, jetons).

**Critères de réussite**
- [ ] `chrony` est actif et démarre au boot sur `gw01`, `adm01` et `dns01`.
- [ ] `dns01` et `adm01` sont synchronisés sur la passerelle de leur VLAN (`^*` dans `chronyc sources`).
- [ ] L'écart d'horloge entre `dns01`, `gw01` et `adm01` est inférieur à 2 secondes.

**Vérification** : `lab/bin/check 00 45`

<details><summary>Indice 1</summary>

Sur `dns01` : `systemctl status chrony`, puis `chronyc sources -v`. La colonne `Reach` (registre octal des 8 dernières interrogations) dit si la source répond. Sur `gw01` : `chronyc clients` et `chronyc accheck 10.10.20.10`.
</details>

<details><summary>Indice 2</summary>

Si la source répond à nouveau mais que l'écart reste de plusieurs minutes, relis la directive `makestep` de `/etc/chrony/chrony.conf` : elle ne s'applique pas en permanence.
</details>

**Pour aller plus loin** : configure sur `dns01` une alerte locale (journal ou notification) si `chronyc tracking` indique un écart supérieur à 1 seconde ou une source non joignable depuis plus de 30 minutes.

---

### M00-E46 — Astreinte : pannes multiples  `BF` `★★★★`

> **Ticket INC-2620** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte cette semaine. Réveil difficile : plusieurs alertes et remontées depuis 6 h (le détail s'affiche à l'injection). Je ne sais pas si c'est lié. Rétablis le service, tiens-moi informée toutes les 30 minutes (un message court dans le canal #astreinte suffit), puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples : trier, prioriser, éviter qu'une panne en masque une autre.
- Communiquer pendant l'incident (statut, impact, prochaine étape, prochaine communication).
- Rédiger un post-mortem sans recherche de coupable, centré sur les causes, la détection et les actions.

**Prérequis** : M00-E38 à M00-E45 (au moins une variante de chacun).
**Durée indicative** : 90 min de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **deux** pannes distinctes parmi celles de M00-E38 à M00-E45 (variantes aléatoires) et les injecte ensemble. Les symptômes peuvent se recouvrir. `--variante N` (1 à 28) force la paire, pas les variantes. `--annuler` retire les deux.

**Injection** : `lab/bin/break 00 46`

**Travail demandé**
1. **Triage (10 min max)** : avant toute correction, liste les symptômes, leur impact métier (qu'est-ce qui ne marche plus pour qui ?) et une première hypothèse de regroupement. Envoie la première communication (modèle libre : statut, impact, actions en cours, prochaine communication).
2. **Diagnostic** : traite les pannes dans l'ordre que tu justifies (impact, dépendances : un DNS ou un routage cassé fausse tous les autres tests). Tiens ton journal horodaté.
3. **Rétablissement** : corrige chaque cause racine. Vérifie après chaque correction que les symptômes attendus ont disparu… et seulement ceux-là.
4. **Clôture** : communication de fin d'incident, puis post-mortem rédigé à partir de `ressources/M00-E46/modele-post-mortem.md`, enregistré dans `docs/socle/post-mortems/AAAA-MM-JJ-INC-2620.md` de ton dépôt et commité.

**Critères de réussite**
- [ ] Toutes les vérifications de M00-E38 à M00-E45 sont vertes (le contrôle les rejoue toutes).
- [ ] Le post-mortem existe, contient une chronologie horodatée, les deux causes racines, l'analyse de la détection (comment aurait-on pu le savoir avant l'utilisateur ?) et des actions correctives avec responsable et échéance.
- [ ] Le journal contient au moins trois communications d'incident espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 00 46`

<details><summary>Indice 1</summary>

Commence par ce qui conditionne tes instruments : si le routage, le DNS ou le tunnel sont touchés, une bonne partie de tes tests mentiront. Vérifie d'abord tes chemins d'accès (SSH vers chaque hôte, console de secours).
</details>

<details><summary>Indice 2</summary>

Après avoir corrigé une première cause, relance **tous** tes tests de départ. Un symptôme qui persiste peut avoir une seconde cause ; un symptôme qui apparaît était peut-être masqué par la première.
</details>

<details><summary>Indice 3</summary>

Les contrôles `lab/bin/check 00 38` à `00 45` sont des sondes de santé ciblées : rien ne t'interdit de les lancer pendant le triage pour cartographier ce qui est rouge.
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), sans regarder l'écran pendant l'injection, et chronomètre ton temps de rétablissement.

---

### M00-E47 — Suivre un paquet de bout en bout  `LAB` `★★★`

> **Ticket PLAT-147** — *De : Karim Benali*
> Pendant les pannes, j'ai vu trop de « je pense que le paquet passe par… ». Je veux que tu saches **montrer** où passe un paquet, de la carte virtuelle de `adm01` jusqu'à Internet, à chaque étage : hyperviseur, bridge, VLAN, routeur, conntrack, NAT. Fais-moi un compte rendu qu'on pourra donner aux prochains arrivants.

**Objectifs pédagogiques**
- Identifier les équipements virtuels traversés par une trame entre une VM et `gw01` (tap, bridges, VNet SDN, éventuels bridges de pare-feu) et les observer.
- Lire le filtrage VLAN d'un bridge Linux (`bridge vlan show`, `bridge -d link`, `ip -d link`).
- Suivre un flux dans `gw01` : capture par interface, table conntrack, trace nftables (`meta nftrace set 1` + `nft monitor trace`).

**Prérequis** : M00-E10, M00-E26, M00-E28.
**Durée indicative** : 2 h.

**Contexte technique** : flux étudié = ping de `adm01` (10.10.10.10, VMID 1001, carte `net0`) vers `9.9.9.9`, puis une connexion HTTPS vers `deb.debian.org`. `gw01` est la VM 1000 : `net0` = `ens18` (WAN, sur `vmbr0`), `net1` = `ens19` (trunk, sur `vmbr1`). Sur `pve01`, l'interface de la carte N de la VM V s'appelle `tap<V>i<N>`.

> ⚠️ **Attention** : sur `pve01`, ne capture jamais sur l'interface physique de `vmbr0` sans filtre : elle porte aussi le trafic de tes VMs personnelles et de l'interface d'administration. Filtre toujours (`host 10.10.10.10`, `icmp`…) et limite le nombre de paquets (`-c 20`).

**Travail demandé**
1. **Côté hyperviseur.** Sur `pve01`, identifie l'interface de `adm01` et celle du trunk de `gw01` :
   ```
   root@pve01:~# qm config 1001 | grep ^net
   root@pve01:~# ip -d link show tap1001i0
   root@pve01:~# bridge -d link show | grep -E 'tap100[01]|fwpr|fwln|vmbr1|ln_|pr_'
   root@pve01:~# bridge vlan show
   ```
   Dessine la chaîne exacte des équipements entre `tap1001i0` et `tap1000i1` (quel bridge est maître de quoi, quelles VLANs sont autorisées sur quel port, lesquelles sont « PVID » / « Egress Untagged »). Ne suppose rien : déduis-le des sorties. Lis aussi `/etc/network/interfaces.d/sdn` pour comprendre ce que la zone SDN `lab` a généré.
2. **Capture couche 2.** Lance un ping de `adm01` vers 9.9.9.9 et capture simultanément, avec affichage des en-têtes Ethernet (`-e`) :
   ```
   root@pve01:~# tcpdump -c 6 -eni tap1001i0 icmp
   root@pve01:~# tcpdump -c 6 -eni tap1000i1 icmp
   ```
   Compare les deux captures (étiquette 802.1Q, adresses MAC).
3. **Côté routeur.** Sur `gw01`, capture le même flux sur `ens19` (parent), `ens19.10` et `ens18`. Observe où l'étiquette disparaît et où l'adresse source change.
4. **Conntrack.** Pendant une connexion HTTPS de `adm01` vers `deb.debian.org` (`curl -so /dev/null https://deb.debian.org/debian/dists/trixie/Release`), relève l'entrée correspondante :
   ```
   root@gw01:~# conntrack -L -p tcp --dport 443 -s 10.10.10.10
   ```
   (paquet `conntrack` à installer si besoin). Annote chaque champ.
5. **Trace nftables.** Crée une table de traçage **dédiée et temporaire** (ne modifie pas `/etc/nftables.conf`) qui marque `meta nftrace set 1` les paquets de `adm01` vers 9.9.9.9 le plus tôt possible (hook *prerouting*, priorité inférieure à celle de conntrack), puis observe avec `nft monitor trace` pendant un ping. Relève la liste des chaînes et règles traversées par le premier paquet, puis par le deuxième. Supprime la table de traçage à la fin.
6. **Compte rendu.** Rédige `docs/socle/analyses/trace-paquet.md` dans ton dépôt : schéma de la chaîne complète (de `tap1001i0` à `ens18`), extraits de sorties annotés, puis une section `## Réponses aux questions` traitant les questions ci-dessous.

**Questions d'analyse** (à traiter dans le compte rendu)
1. À quel endroit exact la trame reçoit-elle l'étiquette VLAN 10, et où la perd-elle ? Quel réglage de quel port le détermine ?
2. Pourquoi l'adresse MAC source change-t-elle entre la capture sur `ens19.10` et celle sur `ens18` ? Qui fait la résolution ARP de 9.9.9.9 ?
3. Dans l'entrée conntrack, explique le tuple d'origine et le tuple de réponse. Comment conntrack sait-il « dé-NATer » la réponse ?
4. Dans la trace, pourquoi la chaîne `postrouting` de la table `ip nat` n'apparaît-elle que pour le premier paquet du flux ?
5. Si tu activais le pare-feu Proxmox (`firewall=1`) sur la carte de `adm01`, quels équipements apparaîtraient entre la VM et le bridge, et pourquoi Proxmox en a-t-il besoin (ou pas, selon le moteur de pare-feu utilisé) ?
6. Dans la capture sur `tap1001i0` d'un transfert HTTPS, il est fréquent de voir des segments TCP de plus de 1500 octets. Explique pourquoi ce n'est pas une anomalie.
7. Que verrait-on sur l'interface physique de `vmbr0` (sur `pve01`) pour ce même flux ? Avec quelle adresse source ?
8. Cite deux pannes de M00-E38 à M00-E45 que cette démarche aurait permis de localiser en moins de 5 minutes, et la commande décisive pour chacune.

**Critères de réussite**
- [ ] Le compte rendu existe, contient le schéma de la chaîne et des extraits annotés de captures, de conntrack et de trace nftables.
- [ ] La section `## Réponses aux questions` traite les 8 questions.
- [ ] Aucune règle de traçage ni capture ne reste active sur `gw01` et `pve01`.

**Vérification** : `lab/bin/check 00 47`

<details><summary>Indice 1</summary>

Une table nftables supplémentaire peut avoir sa propre chaîne de base sur le hook `prerouting` : elle s'ajoute aux autres sans les modifier. Le traçage n'apparaît dans `nft monitor trace` que pour les paquets marqués. `nft delete table …` la retire entièrement.
</details>

<details><summary>Indice 2</summary>

Dans `bridge vlan show`, chaque port liste ses VLANs autorisées ; `PVID` désigne la VLAN attribuée aux trames reçues sans étiquette, `Egress Untagged` les VLANs dont l'étiquette est retirée en sortie. Le trunk de `gw01` et le port d'une VM n'ont pas du tout le même profil.
</details>

**Pour aller plus loin** : refais le parcours pour un flux `pve01` → `pbs01` (sauvegarde) : il traverse `ens18`, `wg0`, le NAT vers le tunnel et `hp01`. Capture aussi sur `ens18` le trafic UDP/51820 chiffré correspondant et compare tailles et débits.

---

### M00-E48 — Mesurer et comprendre les performances disque  `LAB` `★★★★`

> **Ticket PLAT-148** — *De : Claire Morel*
> Avant de placer etcd, Ceph et les bases de données des prochains modules, je veux des chiffres, pas des fiches techniques. Mesure ce que nos trois stockages délivrent **vus depuis une VM**, avec les réglages qu'on utilisera vraiment, et donne-moi une recommandation de placement argumentée.

**Objectifs pédagogiques**
- Concevoir des mesures `fio` représentatives (profil d'accès, taille de bloc, profondeur de file, nombre de tâches, durée, préconditionnement) et éviter les mesures trompeuses (cache, disque vide, thin provisioning).
- Interpréter IOPS, débit et latences (moyenne vs centiles p99/p99.9) et les relier à des besoins réels (etcd, PostgreSQL, Ceph, sauvegardes).
- Mesurer l'effet des options de disque Proxmox : `cache`, `iothread`, contrôleur `virtio-scsi-single`, `discard`, `aio`.

**Prérequis** : M00-E07, M00-E11, M00-E32.
**Durée indicative** : 3 à 4 h (dont beaucoup d'attente).

**Contexte technique** : VM de mesure `sbx48`, VMID **5048**, pool `lab`, clonée depuis le template 9000, sur le VNet `vsandbox`. Elle porte, en plus de son disque système, **trois disques de données de 10 Gio** : un sur `local-nvme`, un sur `ssd-lab`, un sur `hdd-bulk`, tous derrière un contrôleur `virtio-scsi-single`, avec `iothread=1`, `cache=none` et `discard=on` pour la série de référence.

> ⚠️ **Attention** : `fio` sature réellement les disques. Si `pve01` héberge des VMs personnelles sur les mêmes disques physiques, elles seront ralenties pendant les mesures : choisis un créneau adapté et limite chaque test à 60 s. N'écris **jamais** avec `fio` sur un périphérique de l'hôte : uniquement sur les disques de données de la VM 5048, dans la VM.

> ⚠️ **Attention** : vérifie l'espace libre de chaque stockage avant d'ajouter les disques (`pvesm status`). Sur un stockage LVM-thin ou ZFS presque plein, le préconditionnement peut le remplir.

**Travail demandé**
1. Crée la VM 5048 et ses trois disques de données conformément au contexte. Dans la VM, installe `fio` et identifie chaque disque de manière **certaine** (numéro de série ou chemin `/dev/disk/by-id/`, pas l'ordre `sdb`/`sdc`).
2. **Préconditionne** chaque disque (écriture séquentielle complète) et explique dans ton rapport pourquoi c'est indispensable sur au moins un de tes trois stockages.
3. Mesure, pour chacun des trois disques, en accès direct (`--direct=1`), avec `--time_based --runtime=60 --ramp_time=10` :

   | Profil | Accès | Bloc | Profondeur de file × tâches | Ce qu'il représente |
   |---|---|---|---|---|
   | P1 | lecture aléatoire | 4 Kio | 32 × 4 | Pic d'IOPS, index de base de données |
   | P2 | écriture aléatoire | 4 Kio | 32 × 4 | Écritures dispersées, OSD Ceph |
   | P3 | écriture aléatoire | 4 Kio | 1 × 1 | Latence unitaire, transactions |
   | P4 | lecture séquentielle | 1 Mio | 8 × 1 | Restauration, lecture de sauvegarde |
   | P5 | écriture séquentielle | 1 Mio | 8 × 1 | Sauvegarde, écriture d'images |
   | P6 | écriture séquentielle synchronisée (`fdatasync` à chaque écriture), blocs de 2300 octets, moteur `sync` | — | 1 × 1 | Journal d'etcd (WAL) |

   Pour chaque mesure, relève : IOPS, débit, latence moyenne et **p99** (et p99.9 pour P3 et P6).
4. Sur le disque `ssd-lab` uniquement, refais P2, P3 et P6 avec `cache=writeback`, puis P1 avec `iothread=0`. Note ce que chaque changement exige côté VM (redémarrage, détachement…).
5. Consigne tout dans `docs/socle/mesures/perf-disques.md` : un tableau de résultats (une ligne par stockage × profil, colonnes `Stockage | Profil | IOPS | Débit | Lat. moy. | p99 | p99.9`), le tableau des variantes de cache/iothread, la configuration exacte (type de stockage sous-jacent, modèle de disque si connu, options de la VM, commandes `fio`), puis une section **Recommandation de placement** : etcd, PostgreSQL, OSD Ceph virtuels, MinIO, sauvegardes, ISO/templates.
6. Supprime la VM 5048 et ses disques, et vérifie qu'aucun volume `vm-5048-*` ne subsiste.

**Critères de réussite**
- [ ] Le rapport contient les 18 mesures de référence (3 stockages × 6 profils) avec IOPS et p99, et les mesures de variantes `writeback` / `iothread=0`.
- [ ] La recommandation de placement est argumentée par les chiffres mesurés (pas par des généralités).
- [ ] La VM 5048 et tous ses volumes ont été supprimés.

**Vérification** : `lab/bin/check 00 48`

<details><summary>Indice 1</summary>

`qm set 5048 --scsihw virtio-scsi-single --scsi1 local-nvme:10,iothread=1,cache=none,discard=on,serial=nvme48` : l'option `serial` fixe un numéro de série visible dans la VM (`lsblk -o NAME,SERIAL`). Vérifie la syntaxe exacte avec `man qm` / la doc de ta version.
</details>

<details><summary>Indice 2</summary>

Le test etcd de référence de la communauté ressemble à `fio --rw=write --ioengine=sync --fdatasync=1 --bs=2300 --size=22m --name=etcd …`. Le critère habituel : p99 de `fdatasync` sous 10 ms. `fio` affiche une section dédiée aux latences de synchronisation.
</details>

<details><summary>Indice 3</summary>

Avec `cache=writeback`, une partie des écritures est absorbée par le cache de page de **l'hôte** : les chiffres montent, mais que garantit encore un `fdatasync` de la VM ? Pense à ce qui arrive en cas de coupure de courant de `pve01`.
</details>

**Pour aller plus loin** : mesure l'effet de `aio=io_uring` contre `aio=native` et `aio=threads` sur P1, et l'effet de `numjobs` au-delà du nombre de vCPU de la VM.

---

### M00-E49 — Questions expert : sous le capot  `Q` `★★★`

> **Ticket PLAT-149** — *De : Karim Benali*
> Dernière étape avant la recette : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme senior. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la doc et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes manipulés dans ce module (réseau virtuel, filtrage, tunnels, sauvegarde, virtualisation, cluster Proxmox).
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M00-E47.
**Durée indicative** : 2 h 30.

**Questions**

1. Sur `vmbr1` (VLAN-aware), la carte d'une VM est déclarée avec `tag=20` (ou sur le VNet `vinfra`). Décris ce que `bridge vlan show` affiche pour son port `tap` et pour le port trunk de `gw01`, et explique ce qui se passe pour une trame **étiquetée 30** que la VM émettrait elle-même.
2. QCM — Sur un port trunk de bridge VLAN-aware, aucune option `trunks=` n'est précisée côté Proxmox. Quelles VLANs passent ?
   a) uniquement la VLAN native 1 ; b) les VLANs listées par `bridge-vids` de `vmbr1` (2-4094 par défaut) ; c) toutes les VLANs de 0 à 4095 ; d) aucune tant qu'un VNet n'est pas créé.
3. Pourquoi le pare-feu Proxmox « historique » (basé sur iptables) insère-t-il `fwbr<VMID>i<N>`, `fwpr<VMID>p<N>` et `fwln<VMID>i<N>` entre la VM et le bridge quand `firewall=1` ? Qu'est-ce qui change avec le pare-feu basé sur nftables (`proxmox-firewall`) ?
4. `gw01` journalise « nf_conntrack: table full, dropping packet ». Décris les symptômes vus par les utilisateurs, les paramètres en jeu (`nf_conntrack_max`, taille de la table de hachage, délais d'expiration), deux causes typiques sur un routeur de lab, et trois remèdes classés par pertinence.
5. QCM — Sur `gw01`, un paquet est accepté (`accept`) par la chaîne `forward` de la table `inet filter` (priorité 0). Un paquet logiciel installé ensuite a créé, via `iptables-nft`, une table `ip filter` avec une chaîne `FORWARD` de politique `DROP` (priorité 0 également). Que devient le paquet ?
   a) accepté : la première décision `accept` est définitive ; b) jeté : chaque chaîne de base du hook est évaluée, et un `drop` est définitif ; c) cela dépend de l'ordre de création des tables ; d) erreur : deux chaînes de même priorité sur un hook sont interdites.
6. Explique la différence entre `iptables-legacy`, `iptables-nft` et `nft`. Comment repérer sur un hôte que plusieurs de ces mondes coexistent, et pourquoi c'est un risque opérationnel ?
7. Pourquoi la règle de NAT `masquerade` de `gw01` n'est-elle évaluée que pour le premier paquet d'une connexion ? Quelle conséquence pour une règle de NAT modifiée pendant qu'une connexion est établie ?
8. WireGuard pratique le *cryptokey routing*. Explique le rôle de `AllowedIPs` en émission **et** en réception. Que se passe-t-il si deux pairs d'une même interface déclarent des `AllowedIPs` qui se recouvrent (10.20.0.0/16 et 10.20.10.0/24) ?
9. QCM — `ping 10.20.10.10` sur `gw01` répond `sendmsg: Required key not available`. La cause la plus probable :
   a) la clé privée de `wg0` est absente ; b) aucun pair de `wg0` n'a 10.20.10.10 dans ses `AllowedIPs` alors que la route y envoie le paquet ; c) le port UDP 51820 est filtré ; d) l'horloge de `gw01` est décalée.
10. Pourquoi une erreur d'`Endpoint` sur une seule extrémité d'un tunnel WireGuard est-elle souvent sans effet ? Dans quel cas de figure devient-elle bloquante ?
11. PBS stocke les sauvegardes de VM avec des index `.fidx` et les archives de fichiers avec des index `.didx`. Explique la différence (découpage fixe vs défini par le contenu), pourquoi chaque type est adapté à son usage, et le rôle du *dirty bitmap* de QEMU dans la vitesse des sauvegardes incrémentales.
12. Un administrateur supprime 30 instantanés sur `ds-lab`, mais l'espace disque ne diminue pas. Explique le fonctionnement du ramasse-miettes (GC) de PBS (phases, critère d'âge) et pourquoi l'espace n'est pas libéré immédiatement.
13. Avec le chiffrement côté client (M00-E36), que peut encore vérifier PBS lors d'une tâche *verify* ? Que ne peut-il pas vérifier ? Quelles sont les conséquences de la perte de la clé, et quelle procédure MédiSphère doit-elle avoir en place ?
14. Virtualisation imbriquée : que faut-il côté `pve01` et côté VM pour qu'un Proxmox imbriqué exécute des VMs KVM ? Quel est le rôle d'EPT et pourquoi les performances restent-elles acceptables pour du calcul mais se dégradent sur les sorties de VM (I/O, interruptions) ?
15. QCM — Pourquoi recommander `virtio-scsi-single` plutôt que `virtio-scsi-pci` quand on active `iothread=1` sur plusieurs disques ?
   a) `virtio-scsi-pci` ne gère pas le TRIM ; b) avec `virtio-scsi-single`, chaque disque a son propre contrôleur, donc son propre thread d'E/S ; avec `virtio-scsi-pci`, tous les disques partagent le contrôleur et donc un seul thread ; c) `virtio-scsi-single` est plus récent et toujours plus rapide ; d) `iothread` est ignoré avec `virtio-scsi-pci`.
16. Que garantit `cache=none` (et que ne garantit-il pas) ? Comparez avec `writeback` et `writethrough` du point de vue de l'intégrité des données en cas de coupure de l'hôte, sachant que la VM émet des `fsync`.
17. `/etc/pve` : qu'est-ce que pmxcfs, où les données sont-elles réellement stockées, comment sont-elles répliquées dans un cluster, et que se passe-t-il pour `/etc/pve` quand un nœud perd le quorum ? Pourquoi ne faut-il pas y stocker de gros fichiers ?
18. Les VMs clonées depuis `tpl-debian13` obtiennent toutes la même adresse sur le VLAN 99 alors que leurs adresses MAC diffèrent. Quelle est la cause la plus probable, et comment le template aurait-il dû être préparé ?
19. Ballooning, KSM et ARC ZFS sur `pve01` : explique comment ces trois mécanismes interagissent avec le budget mémoire du lab (PLAN §3.3), et ce qui se passe quand l'hôte manque réellement de mémoire.
20. Calcule le MSS TCP attendu pour un flux traversant `wg0` (MTU 1420) sur IPv4, puis sur IPv6. Pourquoi le *MSS clamping* ne s'applique-t-il qu'aux segments SYN, et pourquoi ne remplace-t-il pas le bon fonctionnement de la PMTUD ?

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour les questions 1 à 3 et 7, tes captures et traces de M00-E47 contiennent l'essentiel des réponses.
</details>

<details><summary>Indice 2</summary>

Pour les questions 11 à 13, le chapitre « Technical Overview » de la documentation PBS et le guide d'administration (sections *Garbage Collection*, *Encryption*) sont la référence.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible), à présenter à Karim.
