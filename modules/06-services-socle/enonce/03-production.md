# Module 06 — Palier 3 : Production

Les services socle tournent : `ca01` délivre des certificats par ACME et signe les clés SSH, NetBox fait foi pour les adresses, PowerDNS sert les zones et les résout, Kea distribue les baux du VLAN 99 et met le DNS à jour. Mais tout repose sur **un seul** `dns01` : s'il tombe, plus de résolution, plus de DHCP, et rien ne démarre dans le lab. Personne ne sait restaurer NetBox ou la CA, les certificats expireront en silence le jour où un renouvellement cassera, et la matrice des flux ne dit plus la vérité. Claire Morel veut un socle qui tienne la panne d'une machine, qu'on sache reconstruire, et qu'on surveille. Sophie Laurent veut des zones signées, une PKI gouvernée par une politique écrite, et des services cloisonnés jusque dans le VLAN INFRA. Ce palier fait passer les services socle en production.

> ⚠️ **Rappel** : ces exercices touchent au DNS et au DHCP **de tout le lab**. Avant chaque intervention sur `dns01` ou `dns02`, garde une session SSH ouverte sur l'hôte, vérifie que l'autre résolveur répond, et note la commande de retour arrière. Une coupure du DNS se voit partout (forge, runner, sauvegardes, `apt`) en quelques minutes.

**Chemin imposé** (introduction du module) : toute nouvelle VM est créée par **OpenTofu** (état `socle`, module `vm-debian`) avec son adresse réservée dans **NetBox** ; toute configuration passe par un **rôle Ansible** testé par Molecule et appliqué par le **pipeline** de `plateforme/ansible` ; tout flux traversant `gw01` est déclaré dans `host_vars/gw01/pare_feu.yml`. Tout nouveau secret est en Vault (identité `critique` pour les clés TSIG, les clés d'API et les mots de passe de service) et inscrit au registre des secrets.

**VMs d'essai de ce palier** (pool `lab`, étiquette `env-m06`, VNet `vsandbox` sauf mention) : 2065 `m06-client` (client DHCP de test), 2066-2067 (instances Molecule des scénarios à deux nœuds), 2068 `m06-restau` (restauration), 2069 `stat01` (E34, VNet `vinfra`). Vérifie toujours qu'un VMID est libre avant de l'utiliser.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 06 XX`).

---

### M06-E24 — DNS secondaire `dns02` : transferts de zone et TSIG  `LAB` `★★★`

> **Ticket PLAT-750** — *De : Karim Benali*
> Hier soir, `dns01` a redémarré pour une mise à jour du noyau : quatre minutes sans DNS. Le runner a fait échouer trois pipelines, `git01` n'a pas pu envoyer sa sauvegarde, et Nadia a reçu des alertes partout. Un service dont **tout** dépend n'a pas le droit d'être unique.
> Je veux `dns02` : serveur faisant autorité **secondaire**, alimenté par transfert de zone depuis `dns01`, transferts et notifications signés, et un récurseur identique. Et je veux que chaque client du lab connaisse les deux résolveurs.

**Objectifs pédagogiques**
- Créer un hôte du socle par le chemin standard (NetBox → OpenTofu → Ansible → DNS), sans geste manuel.
- Comprendre la réplication primaire/secondaire du DNS : SOA et numéro de série, NOTIFY, AXFR/IXFR, rafraîchissement.
- Signer les transferts avec TSIG et comprendre ce que TSIG change aux contrôles d'accès par adresse.
- Rendre un service redondant **côté client** (deux résolveurs) et mesurer ce qui se passe quand l'un tombe.

**Prérequis** : M06-E06, M06-E07, M06-E08 (PowerDNS sur `dns01`), M06-E13 (adresses depuis NetBox), M06-E14 (enregistrements par OpenTofu), M06-E16 (Kea), M06-E19 (certificats SSH d'hôte), M06-E23 (RB-060 « ajouter un hôte au socle »).
**Durée indicative** : 3 h.

**Contexte technique**
- `dns02` : VMID **1008**, **10.10.20.16/24**, VNet `vinfra`, 1 vCPU, 2 Go, disque 10 Go sur `local-nvme`, clone **complet** de l'image dorée `current`, étiquettes `socle;role-dns`, démarrage automatique avec le même ordre que `dns01`. Déclaration dans l'état `socle` de `plateforme/infra` (un fichier `socle/dns02.tf`) ; adresse **réservée** dans NetBox (10.10.20.16 est fixée par le PLAN : on ne la tire pas au hasard dans le préfixe).
- Sur `dns02`, mêmes paquets et mêmes ports que sur `dns01` : PowerDNS **Recursor** sur 10.10.20.16:53 et 127.0.0.1:53, PowerDNS **Authoritative** sur 10.10.20.16:5300 et 127.0.0.1:5300. Le serveur faisant autorité de `dns02` n'expose **pas** d'API HTTP : il ne reçoit ses données que par transfert.
- Zones à répliquer : `par1.medisphere.internal`, `par2.medisphere.internal`, `10.10.in-addr.arpa`, `20.10.in-addr.arpa`. Chacune doit annoncer `dns01` **et** `dns02` dans ses enregistrements NS.
- Clé TSIG : nom **`axfr-par1`**, algorithme `hmac-sha256`, secret en Vault `critique` (variable `vault_powerdns_tsig_axfr_par1`), jamais en clair dans le dépôt ni dans une ligne de commande.
- Les rôles `powerdns_auth` et `powerdns_recursor` (M06-E06, E07) servent pour les deux hôtes : la différence primaire/secondaire est une **variable d'inventaire**, pas un second rôle. Nouveau scénario Molecule à deux instances : VMID 2066 et 2067.
- `dns01` et `dns02` sont dans le même VLAN : leurs échanges ne traversent pas `gw01`. Les clients des **autres** VLANs (SANDBOX, VPN d'administration, PAR2) passent par `gw01`.

> ⚠️ **Attention** : (1) tant que `dns02` n'est pas validé, ne l'annonce à aucun client ; (2) la modification des enregistrements NS et du type des zones sur `dns01` se fait par MR et pipeline, après un instantané de la VM 1002 (`ms-snapshot 1002`) ; (3) un primaire qui ne notifie pas n'empêche rien de fonctionner pendant des jours… jusqu'à l'expiration de la zone sur le secondaire (champ *expire* du SOA) : c'est pour cela qu'on prouve la réplication, on ne la suppose pas.

**Travail demandé**
1. **Lecture.** Dans la documentation PowerDNS (*Primary operation*, *Secondary operation*, *TSIG*), relève : quand le primaire envoie-t-il un NOTIFY, à **qui** (et sur quel port) par défaut ? Que fait le secondaire quand il en reçoit un ? Que se passe-t-il si aucun NOTIFY n'arrive ? Que dit la documentation de `allow-axfr-ips` quand une clé TSIG est configurée ? Note les réponses dans ton journal : elles conditionnent ta configuration.
2. **L'hôte.** Suis RB-060 : réservation de 10.10.20.16 dans NetBox (VM `dns02`, interface, adresse primaire, champ `vmid`), déclaration de la VM dans `socle/dns02.tf`, enregistrements A et PTR de `dns02` créés **par le même code**. `tofu plan` doit annoncer exactement ce que tu attends, et rien sur les autres VMs. Applique par le pipeline de `plateforme/infra`. Vérifie que `dns02` apparaît dans l'inventaire Ansible (groupe `role_dns`) et que sa clé d'hôte SSH est signée (M06-E19) avant d'aller plus loin.
3. **Le primaire.** Fais évoluer le rôle `powerdns_auth` pour qu'une variable choisisse le mode (primaire ou secondaire). Sur `dns01` : fonctionnement en primaire, NOTIFY envoyés **seulement** au serveur faisant autorité de `dns02` (pas aux adresses des NS : réfléchis à ce qui écoute sur le port 53 de 10.10.20.16), transferts sans TSIG réservés à la boucle locale, clé `axfr-par1` importée et associée aux quatre zones. Vérifie le **type** des quatre zones (`pdnsutil zone list-all`) : une zone créée par l'API sans précision n'est pas forcément une zone primaire. Ajoute `dns02` aux NS des zones.
4. **Le secondaire.** Sur `dns02` : fonctionnement en secondaire, les quatre zones déclarées secondaires avec `dns01` (10.10.20.10, port 5300) comme primaire et la clé `axfr-par1` pour les transferts. Le récurseur de `dns02` relaie les zones internes vers son propre serveur faisant autorité **puis** vers celui de `dns01`. Mets à jour les playbooks pour que `dns01` et `dns02` ne soient **jamais** configurés en même temps.
5. **Molecule.** Écris un scénario `powerdns_replication` à deux instances (un primaire, un secondaire) qui prouve qu'une modification sur le primaire arrive sur le secondaire, et qu'un AXFR sans TSIG est refusé.
6. **Preuves.** Depuis `adm01` :
   ```
   admin@adm01:~$ for z in par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa; do
                    echo "$z $(dig +short @10.10.20.10 -p 5300 $z SOA | awk '{print $3}') $(dig +short @10.10.20.16 -p 5300 $z SOA | awk '{print $3}')"; done
   admin@adm01:~$ dig @10.10.20.10 -p 5300 par1.medisphere.internal AXFR
   ```
   Modifie un enregistrement de test par OpenTofu (ou par l'API), et mesure le délai avant que `dns02` serve la nouvelle valeur ; retrouve le NOTIFY et l'AXFR dans les journaux des deux serveurs. Prouve qu'un transfert **avec** la clé fonctionne depuis `adm01` sans écrire le secret sur la ligne de commande, puis supprime le fichier de clé temporaire.
7. **Les clients.** Annonce les deux résolveurs, dans cet ordre, partout où ton socle les fixe : configuration cloud-init des VMs créées par OpenTofu, rôle `base`, options DHCP de Kea pour le VLAN 99. Ouvre dans `host_vars/gw01/pare_feu.yml` ce qu'il faut pour que les VLANs qui interrogeaient `dns01` à travers `gw01` puissent aussi interroger `dns02`, et rien de plus.
8. **La panne.** Arrête le service faisant autorité de `dns01` : que voient les clients ? Puis arrête **tout** `dns01` (VM) : combien de temps met `adm01` à résoudre un nom ? Lis `man resolv.conf` (`timeout`, `attempts`, `rotate`) ou la documentation de systemd-resolved selon ce qui gère le résolveur de tes VMs, et décide s'il faut régler quelque chose. Remets `dns01` en service et vérifie que les deux serveurs ont le même numéro de série.

**Critères de réussite**
- [ ] La VM 1008 `dns02` tourne, dans le pool `lab`, étiquetée `socle` et `role-dns`, démarrage automatique ; elle est déclarée dans NetBox avec 10.10.20.16 comme adresse primaire et `vmid` = 1008 ; `dns02.par1.medisphere.internal` et son PTR se résolvent.
- [ ] Les quatre zones sont de type primaire sur `dns01`, secondaire sur `dns02`, avec le **même numéro de série** ; leurs NS citent `dns01` et `dns02`.
- [ ] Un AXFR sans clé depuis `adm01` est refusé par `dns01` ; la clé `axfr-par1` est associée aux quatre zones des deux côtés.
- [ ] Le récurseur de `dns02` résout les noms internes et Internet.
- [ ] `adm01` et `runner01` connaissent les deux résolveurs ; les VLANs routés peuvent interroger `dns02` sur le port 53 (UDP et TCP).
- [ ] Le scénario Molecule `powerdns_replication` passe dans le pipeline.

**Vérification** : `lab/bin/check 06 24`

<details><summary>Indice 1</summary>

Par défaut, un primaire PowerDNS notifie les adresses des serveurs cités dans les **NS** de la zone, sur le port 53. Sur `dns02`, le port 53 est celui du récurseur, pas celui du serveur faisant autorité. Cherche dans la liste des réglages ceux qui restreignent les destinataires automatiques des NOTIFY et ceux qui en ajoutent.
</details>

<details><summary>Indice 2</summary>

Depuis la version 5.0, `pdnsutil` a une syntaxe « objet action » : `pdnsutil zone …`, `pdnsutil tsigkey …`, `pdnsutil metadata …` (l'ancienne syntaxe reste acceptée). La sous-commande qui associe une clé TSIG à une zone prend un dernier argument qui dit de quel côté du transfert on se trouve. Pour forcer un transfert immédiat sur le secondaire, regarde les commandes de `pdns_control`.
</details>

<details><summary>Indice 3</summary>

`dig` sait signer une requête avec une clé TSIG lue dans un **fichier** (option `-k`, format `key "nom" { algorithm …; secret "…"; };`) : le secret n'apparaît ni dans `ps` ni dans l'historique. Pour l'ordre de configuration : le secondaire peut être prêt avant que le primaire ne le notifie ; l'inverse produit des erreurs dans les journaux du primaire, sans gravité.
</details>

**Pour aller plus loin** (facultatif) : les zones catalogues (RFC 9432, *producer*/*consumer* dans PowerDNS) pour qu'une nouvelle zone créée sur `dns01` apparaisse seule sur `dns02` ; IXFR ; `incoming.allow_notify_for` du récurseur pour vider son cache à la réception d'un NOTIFY ; [Primary operation](https://doc.powerdns.com/authoritative/primary.html), [Secondary operation](https://doc.powerdns.com/authoritative/secondary.html), [TSIG](https://doc.powerdns.com/authoritative/tsig.html), [`pdnsutil`](https://doc.powerdns.com/authoritative/manpages/pdnsutil.1.html).

---

### M06-E25 — Kea en haute disponibilité  `LAB` `★★★`

> **Ticket PLAT-751** — *De : Nadia Roussel*
> Le DNS a maintenant un secondaire. Le DHCP, non : si `dns01` tombe, plus aucune VM sandbox n'obtient d'adresse, les tests Molecule et les pannes du palier 4 échouent en cascade.
> Je veux un second serveur Kea sur `dns02`, qui prend le relais **tout seul** si `dns01` disparaît, sans jamais distribuer deux fois la même adresse. Et je veux savoir comment arrêter proprement l'un des deux pour une mise à jour.

**Objectifs pédagogiques**
- Comprendre les modes de haute disponibilité de Kea (`load-balancing`, `hot-standby`, `passive-backup`) et la machine à états du hook HA.
- Configurer une paire `hot-standby` avec communication directe entre pairs (HA+MT) **authentifiée par TLS mutuel** avec des certificats de la PKI interne.
- Adapter le relais DHCP de `gw01` pour qu'il relaie vers deux serveurs, par le code.
- Tester la bascule automatique, le retour, et la maintenance contrôlée.

**Prérequis** : M06-E16, M06-E17 (Kea, socket de contrôle, DDNS), M06-E18 (ACME), M06-E24 (`dns02`), M00-E14 (relais DHCP de `gw01`).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Paquets ISC du dépôt `kea-3-0` : `isc-kea-dhcp4`, `isc-kea-hooks` (contient `libdhcp_ha.so` et `libdhcp_lease_cmds.so`, libres depuis Kea 3.0). Service réel `isc-kea-dhcp4-server` (alias `kea-dhcp4`). Depuis Kea 2.7.9, les bibliothèques de *hooks* ne se chargent que depuis le répertoire de *hooks* du paquet : écris seulement le nom du fichier.
- Mode **`hot-standby`** : `dns01` est `primary`, `dns02` est `standby`. Noms des pairs dans la configuration : `dns01` et `dns02`.
- Communication entre pairs : écouteur HA dédié (*HA+MT*) sur le **port 8001** de chaque serveur (10.10.20.10 et 10.10.20.16), en **HTTPS avec certificats client obligatoires**. Les URL des pairs sont des **adresses IP** (la documentation refuse les noms).
- Socket de contrôle (M06-E17) : il passe en **HTTPS** sur l'adresse de service, port **8004**, avec authentification basique : le compte `kea-api` de M06-E17 (administration, secret en Vault) et un second compte `supervision` (pour M06-E29). Il doit rester joignable depuis `adm01`, et seulement depuis lui. Le fichier `~/.config/workbook/kea-supervision.env` (600) de `adm01` contient `KEA_API_USER` et `KEA_API_PASSWORD` du compte `supervision` ; les checks l'utilisent.
- Certificats TLS de Kea : émis par `ca01` (ACME, M06-E18), avec le nom DNS **et** l'adresse IP de l'hôte dans les SAN, déposés dans `/etc/kea/tls/` (`kea.crt`, `kea.key`), lisibles par l'utilisateur du service (`_kea`), renouvelés automatiquement par le rôle `certificats_acme` de M06-E18 (identifiant `kea`, donc unité `cert-renewer@kea.timer`). Racine de confiance : `/usr/local/share/ca-certificates/medisphere-root-ca.crt`.
- Le relais de `gw01` est aujourd'hui un fichier posé à la main en M00-E14 (`/etc/dnsmasq.d/relais-dhcp.conf`). Il devient un rôle Ansible **`relais_dhcp`**, appliqué à `gw01` avant le rôle `pare_feu`.
- DDNS en cas de bascule : si `dns02` sert les clients, c'est son `kea-dhcp-ddns` qui envoie les mises à jour, **vers le serveur faisant autorité primaire** (`dns01:5300`) : un secondaire n'accepte pas de mise à jour dynamique.
- Client de test : VM **2065** `m06-client` (clone lié de l'image dorée, VNet `vsandbox`, DHCP).

> ⚠️ **Attention** : (1) deux serveurs DHCP actifs sans HA sur le même réseau, c'est la garantie d'adresses distribuées deux fois : **ne démarre pas** Kea sur `dns02` avant que sa configuration HA soit en place ; (2) l'écart d'horloge entre pairs est surveillé par le hook (au-delà de 60 secondes, la paire cesse de coopérer) : vérifie `chronyc tracking` sur les deux hôtes avant de commencer ; (3) la modification de `gw01` passe par le filet anti-coupure du rôle `pare_feu`, et le relais ne doit être pointé vers `dns02` qu'une fois la paire en état `hot-standby`.

**Travail demandé**
1. **Lecture.** Dans le manuel de Kea 3.0 (*High Availability Hook*), lis la description des trois modes et le tableau des états. Explique dans ton journal pourquoi `hot-standby` convient mieux ici que `load-balancing` (taille du lab, plage unique, simplicité de diagnostic), ce que signifient `heartbeat-delay`, `max-response-delay`, `max-ack-delay`, `max-unacked-clients`, et la valeur que tu retiens pour chacun. Lis aussi ce que la documentation dit de `restrict-commands`, de `require-client-certs`, et de l'authentification basique des pairs : qui **vérifie** quoi ?
2. **Certificats.** Obtiens pour `dns01` et `dns02` un certificat TLS portant le nom DNS et l'adresse IP de l'hôte, en automatisant l'obtention et le renouvellement par le rôle `certificats_acme` de M06-E18 (une entrée de plus dans les variables de l'hôte, pas de code nouveau). Vérifie avec `step certificate inspect` : SAN, durée, usages étendus (le même certificat sert de serveur **et** de client TLS).
3. **Le rôle.** Fais évoluer `kea_dhcp4` : bibliothèques `lease_cmds` puis `ha`, paramètres HA, pairs, TLS, socket de contrôle HTTPS ; la configuration de `dns01` et celle de `dns02` sortent du **même** gabarit et ne diffèrent que par `this-server-name` et les adresses d'écoute. Configure aussi `kea-dhcp-ddns` sur `dns02`, et l'autorisation des mises à jour dynamiques depuis 10.10.20.16 sur les zones concernées de `dns01`. Valide chaque fichier avec `kea-dhcp4 -t` avant tout redémarrage. Ajoute un scénario Molecule `kea_ha` à deux instances (2066, 2067) qui vérifie que la paire atteint l'état `hot-standby`.
4. **Mise en service.** Applique sur `dns01` (le service continue, sans pair : observe son état), puis sur `dns02`. Interroge l'état de chaque serveur :
   ```
   admin@adm01:~$ set -a; . ~/.config/workbook/kea-supervision.env; set +a
   admin@adm01:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt -u "$KEA_API_USER:$KEA_API_PASSWORD" \
                    -H 'Content-Type: application/json' -d '{"command": "status-get"}' https://10.10.20.10:8004/ | jq '.[0].arguments["high-availability"]'
   ```
   Explique pourquoi la commande `status-get` est refusée sur le port 8001.
5. **Le relais.** Écris le rôle `relais_dhcp` (gabarit du fichier de relais, validation, redémarrage) et ses variables pour `gw01` : le relais transmet chaque requête du VLAN 99 aux **deux** serveurs. Dans `pare_feu.yml`, ajoute ce que le second serveur impose (réponses vers le `giaddr`, renouvellements en *unicast*). Applique par le pipeline. Vérifie avec `tcpdump` sur `gw01` qu'un DISCOVER part vers les deux serveurs, et qu'un seul répond.
6. **Bascule.** Crée la VM 2065 et vérifie qu'elle obtient un bail de `dns01`. Puis :
   1. arrête Kea sur `dns01` ; mesure le temps avant que `dns02` passe en `partner-down` ; renouvelle le bail de 2065 et lance un nouveau client (redémarre 2065 avec une nouvelle adresse MAC, par exemple) : qui répond ? le nom `sbxNN` est-il mis à jour dans le DNS ?
   2. redémarre Kea sur `dns01` : décris les états traversés jusqu'au retour en `hot-standby` (synchronisation des baux) ;
   3. fais une **maintenance contrôlée** de `dns01` (`ha-maintenance-start` envoyé à `dns02`, arrêt, redémarrage, `ha-maintenance-cancel` si nécessaire) et compare avec la panne brutale.
7. **Runbook.** Rédige `docs/socle/runbooks/RB-062-dhcp-kea-ha.md` : état normal, lecture de `status-get`, maintenance planifiée d'un nœud, panne d'un nœud, retour, cas où les deux nœuds se croient seuls (horloges, réseau coupé), renouvellement des certificats. Détruis la VM 2065.

**Critères de réussite**
- [ ] Kea tourne sur `dns01` et `dns02` ; `status-get` montre le mode `hot-standby`, `dns01` en rôle `primary` et `dns02` en `standby`, tous deux dans l'état `hot-standby`, chacun « en contact » avec l'autre.
- [ ] La communication HA utilise HTTPS sur le port 8001 avec certificats clients exigés ; le socket de contrôle répond en HTTPS sur 8004 avec authentification, et refuse une requête sans identifiants.
- [ ] Les certificats de Kea sont émis par la PKI interne, portent l'adresse IP de l'hôte, et un renouvellement automatique est en place.
- [ ] Le relais de `gw01` est géré par le rôle `relais_dhcp` et relaie vers 10.10.20.10 **et** 10.10.20.16 ; le pare-feu de `gw01` accepte les réponses de `dns02`.
- [ ] Le test de bascule et la maintenance contrôlée sont consignés (heures, états, client servi) ; RB-062 est sur `main` de `plateforme/medisphere`.
- [ ] La VM 2065 n'existe plus.

**Vérification** : `lab/bin/check 06 25`

<details><summary>Indice 1</summary>

En `hot-standby`, seul le primaire répond tant que tout va bien, et chaque bail qu'il accorde est d'abord transmis au pair (commandes `lease4-update`, fournies par `libdhcp_lease_cmds.so`). Les deux serveurs doivent donc avoir **la même** définition de sous-réseau, avec le même identifiant (`id: 99`). Le relais envoie chaque requête aux deux : le pair en veille ne répond pas, mais il **voit** le trafic, ce qui lui permet de détecter qu'un primaire muet laisse des clients sans réponse (`max-unacked-clients`).
</details>

<details><summary>Indice 2</summary>

L'écouteur HA dédié ne sert que les commandes du protocole HA (comportement par défaut de `restrict-commands` depuis Kea 3.0). Avec TLS, `trust-anchor`, `cert-file` et `key-file` vont ensemble ; côté serveur, c'est `require-client-certs` (paramètre de la relation HA, pas d'un pair) qui impose le certificat client. Pour l'authentification basique des pairs, relis bien : le paramètre ajoute un en-tête aux requêtes **envoyées**… et l'écouteur dédié, lui, que vérifie-t-il ?
</details>

<details><summary>Indice 3</summary>

Pour dnsmasq, `man dnsmasq` (`--dhcp-relay`) explique comment relayer une même adresse locale vers plusieurs serveurs. Pour une adresse IP dans un certificat ACME, le défi HTTP-01 est validé par `ca01` en se connectant à cette adresse sur le port 80 : la machine doit être joignable depuis `ca01` sur ce port pendant l'émission.
</details>

**Pour aller plus loin** (facultatif) : le mode `load-balancing` avec deux plages et les classes `HA_dns01`/`HA_dns02` ; un troisième serveur en `backup` sur PAR2 ; le hook `ping_check` (libre depuis Kea 3.0) avant d'offrir une adresse ; [HA hook (manuel Kea 3.0)](https://kea.readthedocs.io/en/kea-3.0.0/arm/hooks.html#libdhcp-ha-so-high-availability-outage-resilience-for-kea-servers), [sockets de contrôle HTTP](https://kea.readthedocs.io/en/kea-3.0.0/arm/dhcp4-srv.html#dhcp4-http-ctrl-channel), [sécurité de Kea](https://kea.readthedocs.io/en/kea-3.0.0/arm/security.html).

---

### M06-E26 — DNSSEC sur la zone interne  `LAB` `★★★`

> **Ticket SEC-752** — *De : Sophie Laurent*
> Audit HDS, constat n° 14 : « les réponses DNS internes ne sont pas authentifiées ; une VM compromise du VLAN INFRA pourrait usurper `git01` ou `ca01` ». Le TLS nous protège en partie, mais l'ACME de `ca01` lui-même fait confiance au DNS pour valider les défis.
> Je veux la zone `par1.medisphere.internal` signée, et des résolveurs qui **refusent** une réponse non authentique pour cette zone. Et je veux savoir ce qu'on fait le jour où il faut changer la clé.

**Objectifs pédagogiques**
- Signer une zone avec PowerDNS (signature en ligne, clé combinée CSK, NSEC ou NSEC3) et comprendre ce qui est produit (DNSKEY, RRSIG, NSEC, DS).
- Établir la chaîne de confiance d'une zone **privée** sans parent signé : ancre de confiance sur le récurseur.
- Faire cohabiter signature en ligne sur le primaire et zone pré-signée sur le secondaire.
- Préparer le roulement de clé et mesurer ce qui casse quand on se trompe.

**Prérequis** : M06-E24 (`dns02` secondaire), M06-E07 (récurseur en mode `validate`, ancres négatives éventuelles), M06-E14 et E17 (enregistrements créés par OpenTofu et par Kea).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Zone à signer : **`par1.medisphere.internal`** sur `dns01` (backend `gsqlite3`). Les autres zones restent non signées dans cet exercice.
- Le TLD `.internal` n'existe pas dans la racine publique : il n'y aura **jamais** de DS chez un parent. La confiance se configure dans `dnssec.trustanchors` des récurseurs de `dns01` et `dns02` (YAML, Recursor 5.4).
- M06-E07 a posé des ancres **négatives** (`dnssec.negative_trustanchors`) pour les zones internes non signées. Aucune ne doit plus porter sur `par1.medisphere.internal` elle-même. La zone parente `medisphere.internal` (M06-E06) reste non signée : si une ancre négative la couvre, c'est la **preuve par le drapeau `ad`** qui dira si la zone signée, en dessous, est bien validée.
- Les enregistrements continuent d'arriver par l'API (OpenTofu, synchronisation NetBox) et par mise à jour dynamique (Kea) : rien ne doit exiger de geste manuel après signature.
- Les données de la chaîne de confiance (DS) sont publiques : elles vont dans l'inventaire Ansible en clair ; les clés privées restent dans la base de PowerDNS (et donc dans ses sauvegardes, M06-E28).

> ⚠️ **Attention** : une ancre de confiance qui ne correspond plus à la clé de la zone rend **toute** la zone injoignable (SERVFAIL) pour tous les clients, y compris pour l'ACME de `ca01`. Travaille dans cet ordre : signer, vérifier la signature sur les deux serveurs faisant autorité, **puis** poser l'ancre sur un seul récurseur, vérifier, et seulement ensuite sur le second. Garde sous la main la commande qui retire l'ancre à chaud.

**Travail demandé**
1. **Préparation.** Vérifie que le backend de `dns01` est configuré pour DNSSEC (réglage `gsqlite3-dnssec`) et lis la section *DNSSEC → Modes of operation* de la documentation. Choisis entre NSEC et NSEC3 et écris ta justification (énumération de la zone, coût, simplicité de diagnostic, contexte « zone interne »).
2. **Signature.** Signe la zone, puis inspecte le résultat :
   ```
   admin@dns01:~$ sudo -u pdns pdnsutil zone show par1.medisphere.internal
   admin@dns01:~$ sudo -u pdns pdnsutil zone export-ds par1.medisphere.internal
   admin@adm01:~$ dig +dnssec +multi @10.10.20.10 -p 5300 par1.medisphere.internal DNSKEY
   admin@adm01:~$ dig +dnssec @10.10.20.10 -p 5300 inexistant.par1.medisphere.internal A
   ```
   Explique l'algorithme et le type de clé générés, la durée de validité des signatures (champs *inception*/*expiration* d'un RRSIG) et ce qui prouve la non-existence d'un nom.
3. **Le secondaire.** Après transfert, la zone de `dns02` contient-elle des signatures ? Quelle métadonnée PowerDNS a été posée sur `dns02`, par qui ? Les signatures du primaire sont renouvelées chaque semaine ; un secondaire ne retransfère que si le numéro de série change : choisis et applique le réglage `SOA-EDIT` qui garantit que `dns02` ne servira jamais des signatures expirées, et justifie-le.
4. **Code.** Reporte ces décisions dans le rôle `powerdns_auth` (signature idempotente des zones listées, métadonnées) : un second passage du pipeline ne doit rien changer et surtout **jamais** régénérer une clé.
5. **Ancres.** Ajoute l'enregistrement DS de la zone aux ancres de confiance des récurseurs, par le rôle `powerdns_recursor`, d'abord sur `dns02` seul (limite le jeu avec `--limit`), vérifie, puis sur `dns01`. Constate :
   ```
   admin@adm01:~$ dig +dnssec @10.10.20.16 git01.par1.medisphere.internal A     # drapeau ad ?
   admin@adm01:~$ dig +cd +dnssec @10.10.20.16 git01.par1.medisphere.internal A # différence ?
   admin@dns02:~$ sudo rec_control get-tas
   admin@dns02:~$ sudo rec_control get-ntas
   ```
   Vérifie aussi qu'un nom Internet signé est toujours validé, et que les zones non signées (inverses, `par2`) se résolvent toujours.
6. **Ce qui arrive après.** Crée un enregistrement par OpenTofu et laisse Kea en créer un (renouvellement de bail d'une VM sandbox) : sont-ils signés sans intervention ? Pourquoi ?
7. **Roulement.** Lis la page *DNSSEC → Key rollover* et écris dans `docs/socle/runbooks/` (dans le RB du DNS existant, ou un nouveau) la procédure de roulement de la CSK avec **ancres de confiance**, étape par étape, durées d'attente comprises (TTL du DNSKEY, durée de cache des récurseurs). N'effectue pas le roulement.

**Critères de réussite**
- [ ] La zone `par1.medisphere.internal` sert des DNSKEY et des RRSIG depuis `dns01` **et** `dns02` (ports 5300).
- [ ] Les deux récurseurs ont une ancre de confiance pour `par1.medisphere.internal` qui correspond à la clé publiée ; aucune ancre négative ne porte sur cette zone.
- [ ] Une requête avec `+dnssec` sur un nom de la zone, posée à 10.10.20.10 et à 10.10.20.16, revient avec le drapeau `ad` ; la résolution Internet validée et celle des zones non signées fonctionnent toujours.
- [ ] Le secondaire retransfère la zone quand les signatures changent (réglage justifié).
- [ ] Un second passage du rôle ne change rien ; la procédure de roulement est rédigée.

**Vérification** : `lab/bin/check 06 26`

<details><summary>Indice 1</summary>

Un récurseur valide en partant de l'ancre de confiance **la plus proche** du nom demandé. Pour `par1.medisphere.internal`, sans ancre propre, il partirait de la racine… qui prouve que `.internal` n'existe pas. C'est pour cela que la zone interne a d'abord eu besoin d'une ancre négative, et qu'elle a maintenant besoin d'une ancre positive.
</details>

<details><summary>Indice 2</summary>

`pdnsutil zone export-ds` affiche plusieurs lignes (empreintes SHA-256, SHA-384…) : une seule suffit dans l'ancre, celle en SHA-256 (type 2) est le choix courant. Côté récurseur, les modifications d'ancres se rechargent sans redémarrage : regarde les commandes `rec_control` qui rechargent la configuration « Lua/YAML ».
</details>

<details><summary>Indice 3</summary>

Les valeurs possibles de `SOA-EDIT` sont décrites dans *Domain metadata* : certaines font évoluer le numéro de série servi en même temps que la date de création (*inception*) des signatures. Le secondaire compare le numéro de série servi par le primaire au sien à chaque intervalle de rafraîchissement.
</details>

**Pour aller plus loin** (facultatif) : signer les zones inverses ; publier un enregistrement `SSHFP` signé pour les hôtes qui ne portent pas encore de certificat d'hôte ; la validation DNSSEC « locale » (`systemd-resolved` en `DNSSEC=yes`) et ses pièges ; [DNSSEC dans PowerDNS](https://doc.powerdns.com/authoritative/dnssec/index.html), [ancres dans le Recursor](https://doc.powerdns.com/recursor/dnssec.html), [réglages YAML `dnssec.*`](https://doc.powerdns.com/recursor/yamlsettings.html).

---

### M06-E27 — La PKI en production : durées de vie, renouvellement, révocation  `LAB` `★★`

> **Ticket SEC-753** — *De : Sophie Laurent*
> La PKI délivre des certificats, très bien. Mais je n'ai aucune réponse à ces questions d'auditeur : combien de temps vit chaque type de certificat, et pourquoi ? qui renouvelle quoi, et qui le voit si ça casse ? comment retire-t-on un certificat dont la clé a fuité ? quand expire l'intermédiaire, et que fait-on ce jour-là ?
> Je veux une politique de durées **appliquée par la configuration** de `ca01`, des renouvellements automatiques avec de la marge, et un exercice de révocation réalisé et documenté.

**Objectifs pédagogiques**
- Régler les durées par provisioner (`claims`) et comprendre leur hiérarchie (globale, provisioner).
- Comprendre la révocation passive (défaut de step-ca) et active (CRL), leurs limites, et le rôle des durées courtes.
- Vérifier le renouvellement automatique sur tout le socle et lui donner une marge cohérente avec la supervision (M06-E29).
- Planifier la fin de vie des certificats de la CA elle-même.

**Prérequis** : M06-E02, M06-E03 (PKI racine + intermédiaire), M06-E18 (ACME, `cert-renewer@`), M06-E19, M06-E20 (certificats SSH).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Configuration : `ca.json` dans le répertoire de step-ca sur `ca01` (`STEPPATH`, voir M06-E02) ; service `step-ca`, rechargement par `systemctl reload step-ca` (signal HUP) ; le rôle `step_ca` gère ce fichier.
- Politique de durées imposée (reprise par la politique de certification de M06-E33) :

  | Certificat | Provisioner | Défaut | Maximum |
  |---|---|---|---|
  | Serveur TLS (ACME) | `acme` | 30 jours | 30 jours |
  | TLS émis à la main (essais, outils) | `admin` (JWK) | 24 h | 7 jours |
  | SSH d'hôte | provisioner SSH de M06-E19 | 30 jours | 30 jours |
  | SSH d'utilisateur | provisioner SSH de M06-E20 | 16 h | 16 h |

- Renouvellement : le `cert-renewer@<service>` de Smallstep renouvelle par défaut quand **66 %** de la durée de vie est écoulée. La supervision (M06-E29) alertera à **10 jours** de l'expiration ; le renouvellement des certificats de 30 jours doit donc partir **avant** : à **15 jours** de l'expiration.
- Révocation active : step-ca embarque un petit serveur de CRL (fonction marquée expérimentale dans la documentation), servi par l'API (`/1.0/crl`) et, pour les clients qui ne peuvent pas faire de TLS, par un écouteur HTTP (`insecureAddress`). Retenu ici : écouteur HTTP sur le **port 80** de `ca01`, CRL à `http://ca01.par1.medisphere.internal/1.0/crl`, régénérée à chaque révocation.
- Exercice de révocation sur un certificat **d'essai** seulement : `essai-revocation.par1.medisphere.internal`, émis depuis `adm01` avec le provisioner `admin`.

> ⚠️ **Attention** : (1) avant toute modification de `ca.json`, sauvegarde le fichier et garde sous la main la commande qui le remet en place ; un `ca.json` invalide arrête l'émission **et** le renouvellement de tout le socle ; (2) ne révoque **jamais** un certificat en service pour « voir » : le renouvellement d'un certificat révoqué est refusé, le service tombera à l'expiration ; (3) réduire une durée maximale ne raccourcit pas les certificats déjà émis.

**Travail demandé**
1. **État des lieux.** Relève la date d'expiration de la racine et de l'intermédiaire (`step certificate inspect`), les `claims` actuels (globaux et par provisioner) dans `ca.json`, et, sur chaque hôte du socle, les certificats TLS en service (fichier, service qui l'utilise, émetteur, expiration, unité de renouvellement). Présente-le comme un tableau dans ton journal : il servira à M06-E29 et M06-E33.
2. **Durées.** Applique la politique ci-dessus par le rôle `step_ca`. Vérifie chaque provisioner :
   ```
   admin@adm01:~$ step ca provisioner list | jq '.[] | {name, type, claims}'
   ```
   puis demande un certificat `admin` de 10 jours : que répond `ca01` ? Demande un certificat SSH d'utilisateur de 24 h : idem.
3. **Renouvellement.** Sur chaque hôte qui porte un certificat de 30 jours, règle le déclenchement à 15 jours de l'expiration, dans le rôle `certificats_acme` de M06-E18 (une variable de seuil utilisée par son unité `cert-renewer@.service`), jamais à la main sur un hôte. Prouve-le sur un hôte : force un renouvellement, vérifie que le service a rechargé le nouveau certificat (empreinte servie avant/après avec `openssl s_client`).
4. **Révocation passive.** Sur `adm01`, émets le certificat d'essai, renouvelle-le une fois (succès), révoque-le par son numéro de série, puis tente de le renouveler. Explique ce que « révocation passive » protège et ce qu'elle ne protège pas (un client qui ne fait que **vérifier** ce certificat d'essai le refuse-t-il ?).
5. **Révocation active.** Active la CRL et l'écouteur HTTP, ouvre ce qu'il faut (le flux se discute : qui doit pouvoir lire la CRL ?), puis :
   ```
   admin@adm01:~$ step crl inspect --ca /usr/local/share/ca-certificates/medisphere-root-ca.crt http://ca01.par1.medisphere.internal/1.0/crl
   ```
   Le numéro de série révoqué y figure-t-il ? Vérifie le certificat d'essai **avec** la CRL (`openssl verify -crl_check`). Quels clients du socle consultent réellement une CRL aujourd'hui ? Qu'en conclus-tu sur la vraie protection en cas de clé compromise ?
6. **Fin de vie de la CA.** Calcule la date à laquelle l'intermédiaire ne pourra plus émettre de certificat de 30 jours valide jusqu'au bout. Écris la procédure de renouvellement de l'intermédiaire (cérémonie avec la racine hors ligne de `~/pki-racine/`) et pose deux rappels datés dans le calendrier de l'équipe (dans le runbook).
7. **Runbook.** Rédige `docs/socle/runbooks/RB-063-revoquer-un-certificat.md` : décision (qui décide, sur quels critères), révocation TLS et SSH, remplacement, vérification, communication, et ce que la révocation **ne** fait **pas**.

**Critères de réussite**
- [ ] Les `claims` de `ca.json` appliquent la politique (ACME : 30 j par défaut et au maximum ; `admin` : 24 h / 7 j ; SSH utilisateur : 16 h au maximum ; SSH hôte : 30 j au maximum) ; le fichier est géré par Ansible.
- [ ] La CRL est servie en HTTP par `ca01`, signée par la PKI interne, et contient au moins un certificat révoqué.
- [ ] Les certificats de 30 jours du socle sont renouvelés à 15 jours de l'expiration (seuil présent dans l'unité `cert-renewer@.service`, minuterie active) ; aucun certificat en service n'expire dans moins de 10 jours.
- [ ] La clé privée de la racine est absente de `ca01`.
- [ ] RB-063 est sur `main` de `plateforme/medisphere` ; les dates de fin de vie de l'intermédiaire et de la racine y figurent.

**Vérification** : `lab/bin/check 06 27`

<details><summary>Indice 1</summary>

Les `claims` existent à deux niveaux : sous `authority` (valeurs globales) et dans chaque provisioner (qui les remplace pour lui). Un défaut supérieur au maximum, ou un maximum supérieur au maximum global, est refusé au démarrage. La commande `step ca provisioner update` sait modifier les durées d'un provisioner ; mais si Ansible gère `ca.json`, qui gagne au prochain passage ?
</details>

<details><summary>Indice 2</summary>

`step certificate needs-renewal` accepte un seuil en durée (`--expires-in`) ; attention, les durées s'écrivent en heures (`h`), pas en jours. Dans l'unité gabarit `cert-renewer@.service`, c'est la ligne `ExecCondition=` qui décide s'il faut renouveler : c'est là que le seuil doit apparaître.
</details>

<details><summary>Indice 3</summary>

`step ca revoke` révoque par numéro de série (il faut alors un jeton d'un provisioner, donc le mot de passe d'`admin`) ou en présentant le certificat **et** sa clé. Le numéro de série affiché par `step certificate inspect` est décimal ; `openssl` l'affiche en hexadécimal.
</details>

**Pour aller plus loin** (facultatif) : modèles X.509 (*templates*) de step-ca pour ajouter un point de distribution de CRL aux certificats ; politiques de noms (`policy`) pour interdire à l'ACME d'émettre hors de `par1.medisphere.internal` ; [configuration de step-ca](https://smallstep.com/docs/step-ca/configuration/), [renouvellement](https://smallstep.com/docs/step-ca/renewal/), [révocation](https://smallstep.com/docs/step-ca/revocation/), [step-ca en production](https://smallstep.com/docs/step-ca/certificate-authority-server-production/).

---

### M06-E28 — Sauvegarder et restaurer les services socle  `LIBRE` `★★★`

> **Ticket PLAT-754** — *De : Nadia Roussel*
> La sauvegarde de nuit des VMs couvre `dns01`, `ca01` et `nbx01`. Mais je ne sais toujours pas rendre l'inventaire NetBox d'avant-hier sans écraser toute la VM, ni reconstruire la CA sur une autre machine, ni récupérer les zones et les baux. Et personne n'a jamais essayé.
> Je veux, comme pour GitLab, des sauvegardes **applicatives** quotidiennes, chiffrées, envoyées à PAR2, et une restauration **testée** de chaque service, chronométrée, avec un runbook.
> *Sophie Laurent, en commentaire* : la sauvegarde de la CA contient la clé de l'intermédiaire. Je veux savoir qui peut la lire, et je ne veux **pas** voir la clé racine dans PBS.

**Objectifs pédagogiques**
- Identifier, pour chaque service, les données qui font son état (base, fichiers, secrets) et la façon d'en prendre une copie **cohérente**.
- Généraliser la sauvegarde applicative vers PBS de M01-E28 en un rôle Ansible réutilisable.
- Raisonner sur les secrets contenus dans une sauvegarde et sur ce qu'une restauration réveille.
- Prouver la restauration, et mesurer RTO et RPO.

**Prérequis** : M01-E28 (sauvegarde applicative de GitLab vers PBS), M00-E36 (chiffrement côté client, *paperkey*), M06-E04 (NetBox), M06-E06/E16 (PowerDNS, Kea), M06-E02 (step-ca), M06-E24/E25 (`dns02`).
**Durée indicative** : 4 h.

**Contraintes**
- Services à couvrir : PowerDNS et Kea sur `dns01` (base, configuration, baux) ; NetBox sur `nbx01` (base PostgreSQL, fichiers téléversés, configuration et ses secrets) ; step-ca sur `ca01` (configuration, base, certificats, clé de l'intermédiaire **chiffrée**, **sans** la clé racine). Pour `dns02`, décide s'il faut une sauvegarde applicative et justifie.
- Une seule mise en œuvre pour les trois hôtes : un rôle Ansible testé, des variables par hôte ; exécution quotidienne par un timer systemd, après la sauvegarde de `git01` et avant la tâche `lab-nuit` ; échec visible (code retour, journal, alerte `ms-alerte@`).
- PBS : espace de noms `par1/<hôte>` dans `ds-lab`, groupe de sauvegarde `host/<hôte>`, un jeton par hôte (`wb-backup@pbs!<hôte>`) dont les droits se limitent à son espace de noms ; chiffrement côté client avec une clé par hôte, *paperkey* et copie hors ligne **avant** la première sauvegarde ; aucun secret en clair dans le dépôt, dans le script ou dans les journaux.
- Copie cohérente : aucune copie à chaud d'un fichier de base en cours d'écriture ; si un service doit être suspendu, la coupure est bornée, mesurée et sans effet visible pour les clients (le DNS et le DHCP sont redondants, l'ACME réessaie).
- Flux : chaque hôte joint `pbs01:8007` à travers le tunnel, et rien d'autre de nouveau ; règles dans `pare_feu.yml` et sur `pbs01`, matrice des flux à jour.
- Restauration de test sur la VM **2068** `m06-restau` (VNet `vsandbox`, pool `lab`, étiquette `env-m06`), qui ne joint pas PAR2 : les données passent par `adm01`. Elle doit prouver, pour chacun des trois services, que les données restaurées sont **utilisables** (zones servies avec le même numéro de série ; NetBox qui répond avec l'inventaire du jour de la sauvegarde ; une CA restaurée qui démarre et dont un certificat émis est vérifiable par la racine MédiSphère). La VM restaurée porte des secrets de production : elle ne doit **jamais** être joignable depuis le reste du lab sous un nom ou une adresse de production, et elle est détruite à la fin, avec les copies de travail.
- Noms imposés (vérification) : sur chaque hôte sauvegardé, script `/usr/local/sbin/wb-backup-socle.sh`, unités `wb-backup-socle.service` et `wb-backup-socle.timer`, secrets `/etc/wb-backup/pbs-<hôte>.env` (`PBS_REPOSITORY`, `PBS_PASSWORD`, `PBS_FINGERPRINT`) et clé `/etc/wb-backup/pbs-<hôte>.key`.
- Livrables dans `plateforme/medisphere` : `docs/socle/runbooks/RB-061-restaurer-un-service-socle.md` (un chapitre par service), une section datée dans `docs/socle/tests/restauration.md` (feuille de temps, RTO, RPO par service), registre des secrets et matrice des flux à jour.

**Critères de réussite**
- [ ] Sur `dns01`, `nbx01` et `ca01`, le timer de sauvegarde applicative est actif et le dernier passage a réussi ; fichiers de secrets et clés en `root:root 600`.
- [ ] PBS contient pour chacun un instantané `host/<hôte>` de moins de 48 h dans `par1/<hôte>`, chiffré ; chaque jeton est limité à son espace de noms ; aucune clé de chiffrement sur `pbs01`.
- [ ] La sauvegarde de `ca01` ne contient pas de clé racine (prouvé par le catalogue).
- [ ] Les flux `dns01`, `nbx01`, `ca01` → `pbs01:8007` sont ouverts et documentés ; `runner01` ne joint toujours pas `pbs01:8007`.
- [ ] La VM 2068 a servi au test et n'existe plus ; RB-061 et le compte rendu daté (RTO, RPO par service) sont sur `main`.

**Vérification** : `lab/bin/check 06 28`

<details><summary>Indice 1</summary>

Pour chaque service, pose-toi trois questions : où sont les données qui changent (base, fichiers) ? existe-t-il un outil d'export cohérent fourni par le logiciel ou par sa base ? quels secrets faut-il pour **relire** ces données sur une autre machine (clé de chiffrement de la base, sel des jetons, mot de passe d'une clé privée) ? Une sauvegarde qui restaure les données sans le secret qui les déchiffre ne vaut rien.
</details>

<details><summary>Indice 2</summary>

La base des certificats de step-ca est une base clé-valeur embarquée (Badger) : elle ne s'ouvre pas par deux processus à la fois et n'a pas d'outil d'export en ligne. La base de PowerDNS (SQLite) en a un ; PostgreSQL aussi. Les baux de Kea sont dans un fichier CSV réécrit périodiquement : regarde ce que fait le processus *Lease File Cleanup*.
</details>

<details><summary>Indice 3</summary>

La CA restaurée sur la VM 2068 a la **même** clé d'intermédiaire que `ca01` : elle peut émettre des certificats que tout le socle croira. Pense à ce que ta VM de test doit et ne doit pas pouvoir joindre, et à ce que tu effaces à la fin.
</details>

**Pour aller plus loin** (facultatif) : synchroniser `par1/*` vers un second datastore ; vérifier automatiquement chaque nuit qu'un instantané se restaure (extraction d'un fichier témoin) ; [client PBS](https://pbs.proxmox.com/docs/backup-client.html), [sauvegarde de NetBox](https://netboxlabs.com/docs/netbox/administration/replicating-netbox/), [*Lease File Cleanup* de Kea](https://kea.readthedocs.io/en/kea-3.0.0/arm/lfc.html).

---

### M06-E29 — Superviser les services socle et l'expiration des certificats  `LAB` `★★`

> **Ticket PLAT-755** — *De : Nadia Roussel*
> Prometheus arrivera au module 21. D'ici là, je ne veux plus découvrir une panne du socle par un utilisateur. Je veux une sonde qui passe toutes les quinze minutes sur tout ce que vous avez monté : DNS (les deux), zones à jour sur le secondaire, signature, DHCP et sa haute disponibilité, NetBox, la CA… et surtout les certificats qui vont expirer. Si quelque chose ne va pas, une alerte, comme pour les sauvegardes.

**Objectifs pédagogiques**
- Concevoir des sondes **de service** (le service rend-il ce qu'on attend ?) plutôt que des sondes de processus.
- Réutiliser la chaîne d'alerte de M02-E26 (`OnFailure=ms-alerte@%n.service`) et ses principes : « rien vu » n'est jamais « tout va bien ».
- Donner à une sonde des identités en lecture seule, et constater quand c'est impossible.
- Tester une sonde : chaque contrôle doit pouvoir passer au rouge.

**Prérequis** : M02-E26 (`ms-verif-sauvegardes`, `ms-alerte@`), M02-E20 (Taskfile, `install:systeme`), M06-E24 à E27.
**Durée indicative** : 3 h.

**Contexte technique**
- Script : `bin/ms-verif-services` dans `plateforme/outils`, avec ses tests bats, installé sous `/usr/local/bin` par `task install:systeme`. Options : `-s|--seuil-certificats JOURS` (défaut 10), `-q|--quiet` (n'affiche que les anomalies). Codes 0 (tout va bien), 1 (au moins une anomalie **ou** un contrôle impossible), 2 (usage).
- Ce qui est surveillé (résolveurs, zones, serveurs Kea, points TLS…) est décrit dans un fichier de configuration **versionné** du projet, `etc/ms-verif-services.conf`, installé en `/usr/local/etc/ms-verif-services.conf` par la même tâche : ajouter un service à surveiller ne doit jamais demander de modifier le script.
- Unités sur `adm01` : `ms-verif-services.service` (oneshot, `User=admin`, `OnFailure=ms-alerte@%n.service`) et `ms-verif-services.timer` (toutes les 15 minutes, rattrapage).
- Identités en lecture : jeton NetBox **dédié** en lecture seule dans `~/.config/workbook/netbox-supervision.token` ; compte Kea `supervision` dans `~/.config/workbook/kea-supervision.env` (M06-E25). Fichiers en 600.
- Contrôles attendus (au minimum) :

  | Domaine | Contrôle |
  |---|---|
  | DNS | chaque récurseur (10.10.20.10, 10.10.20.16) résout un nom interne et un nom Internet ; un nom interne inexistant donne `NXDOMAIN` **localement** (sans délai) |
  | Réplication | pour chaque zone, même numéro de série sur les deux serveurs faisant autorité |
  | DNSSEC | un nom de `par1.medisphere.internal` revient validé (`ad`) par chaque récurseur |
  | DHCP | les deux serveurs Kea répondent, la paire est en `hot-standby` et en contact ; adresses libres dans la plage du VLAN 99 |
  | NetBox | `/api/status/` répond, avec les versions attendues |
  | PKI | `https://ca01.par1.medisphere.internal/health` répond `ok` |
  | Certificats | chaque point TLS du socle présente un certificat valide pour son nom, émis par la PKI interne, qui expire dans **plus de 10 jours** |

**Travail demandé**
1. **Inventaire des points TLS.** À partir du tableau de M06-E27, liste les points TLS à surveiller (hôte, port, nom attendu) et écris-les dans le fichier de configuration. Faudrait-il plutôt générer cette liste depuis NetBox ? Écris les avantages et la dépendance que cela crée, et justifie ton choix.
2. **Identités.** Crée le jeton NetBox en lecture seule (vérifie qu'il ne peut **pas** écrire) et inscris-le au registre des secrets. Pour Kea, lis ce que permet le compte `supervision` : l'authentification basique de Kea a-t-elle des rôles ? Écris dans le registre ce que tu acceptes et comment tu limites le risque.
3. **Le script.** Écris `ms-verif-services` et ses tests bats (réseau simulé : `dig`, `curl`, `openssl` remplacés par des fonctions). Chaque contrôle affiche une ligne `OK`/`KO` lisible par un humain et la sortie se termine par un bilan. Un contrôle qui ne peut pas s'exécuter (outil absent, identité illisible, réponse vide) est un `KO`.
4. **Les unités.** Service, timer, alerte. Durcis le service comme en M02-E26. Valide (`systemd-analyze verify`), active, vérifie la prochaine échéance.
5. **Le rouge.** Pour **chaque** domaine du tableau, provoque un échec réaliste et réversible sans toucher à la production (ex. : seuil de certificats à 400 jours par un *drop-in*, arrêt du récurseur de `dns02` une minute, zone de test modifiée sur `dns01` avec la réplication suspendue…), constate l'alerte dans le journal, puis remets en état. Note dans ton journal la liste des tests et leur résultat.
6. **Le guide.** Complète `docs/astreinte.md` de `plateforme/outils` : pour chaque ligne `KO` possible, que vérifier en premier et quel runbook ouvrir.

**Critères de réussite**
- [ ] `ms-verif-services` est installé sous `/usr/local/bin`, ses tests bats passent dans le pipeline de `plateforme/outils`.
- [ ] Le timer est actif, toutes les 15 minutes, avec rattrapage ; le service est oneshot, tourne en `admin`, et déclenche `ms-alerte@` en cas d'échec ; il a déjà tourné sous systemd.
- [ ] Lancé maintenant, le contrôle répond 0 ; avec un seuil de certificats absurde (400 jours), il répond 1 ; avec une option inconnue, 2.
- [ ] Le journal contient une alerte `ms-alerte` issue de ce service (moins de 30 jours).
- [ ] Les identités de supervision sont en 600 ; le jeton NetBox ne peut pas écrire.

**Vérification** : `lab/bin/check 06 29`

<details><summary>Indice 1</summary>

`openssl s_client -connect HÔTE:PORT -servername NOM` suivi de `openssl x509 -noout -checkend SECONDES` donne l'expiration ; `-verify_return_error` et `-CAfile` donnent la validité de la chaîne ; `-verify_hostname` (ou l'option équivalente) le nom. `dig` renvoie le statut de la réponse (`status: NXDOMAIN`) et les drapeaux (`flags: qr rd ra ad`) dans sa sortie complète.
</details>

<details><summary>Indice 2</summary>

Kea renvoie les réponses de ses sockets de contrôle HTTP dans une **liste** (compatibilité avec l'ancien agent de contrôle). La statistique `subnet[99].assigned-addresses` et la taille de la plage donnent les adresses libres : `statistic-get` est une commande intégrée, sans *hook*.
</details>

**Pour aller plus loin** (facultatif) : produire aussi un fichier au format texte de node_exporter (préparation du module 21) ; éviter les alertes répétées toutes les 15 minutes (état mémorisé, n'alerter qu'au changement) ; [systemd.timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html), [API de statut NetBox](https://netboxlabs.com/docs/netbox/integrations/rest-api/), [commandes Kea `statistic-get`, `status-get`](https://kea.readthedocs.io/en/kea-3.0.0/api.html).

---

### M06-E30 — Durcir les services et mettre à jour la matrice des flux  `LAB` `★★`

> **Ticket SEC-756** — *De : Sophie Laurent*
> J'ai lancé un scan depuis `runner01`, qui est dans le même VLAN que les services socle : l'API de PowerDNS, le serveur faisant autorité sur 5300, le socket de contrôle de Kea, la base PostgreSQL de NetBox… Tout ce qui écoute est joignable, parce que `gw01` ne voit **pas** le trafic interne au VLAN INFRA. Et la matrice des flux ne parle ni de `dns02`, ni des sauvegardes, ni de la CRL.
> Je veux : chaque service n'écoute que là où il doit, chaque hôte INFRA filtre ce qu'il reçoit, et une matrice des flux qui dit la vérité. Preuve par un nouveau scan.

**Objectifs pédagogiques**
- Comprendre la limite d'un pare-feu central dans un VLAN plat et ajouter un filtrage par hôte (défense en profondeur).
- Réduire la surface d'attaque de chaque service : adresses d'écoute, contrôles d'accès applicatifs, authentification des API.
- Tenir la matrice des flux en code et la confronter à la réalité (scan).

**Prérequis** : M04-E17 (rôle `pare_feu`, filet anti-coupure), M06-E24 à E29.
**Durée indicative** : 3 h.

**Contexte technique**
- Hôtes concernés par le filtrage local : `dns01`, `dns02`, `ca01`, `nbx01`. Nouveau rôle **`pare_feu_local`** (nftables, table `inet filtre_local`, chaîne d'entrée en politique `drop`), données par hôte dans l'inventaire, scénario Molecule (VMID 2066). Il ne touche pas à `gw01` (rôle `pare_feu`) ni à `git01`/`runner01`/`s3-01` (hors périmètre de ce ticket : noté dans le registre des écarts).
- Flux légitimes vers ces hôtes (à compléter par ton analyse) : SSH depuis `adm01` et `runner01` (clé `ansible-ci`) ; DNS 53 depuis tout le lab, PAR2 et le VPN ; 5300 entre `dns01` et `dns02` et depuis `adm01` (diagnostic) ; API PowerDNS 8081 depuis `adm01` et `runner01` ; Kea : 67 depuis le relais de `gw01` (vérifie l'adresse source réelle des requêtes relayées), 8001 entre pairs, 8004 depuis `adm01` ; ACME/HTTPS 443 de `ca01` depuis tout le lab ; CRL 80 de `ca01` ; HTTP-01 (80) vers les hôtes qui obtiennent un certificat ACME, depuis `ca01` ; NetBox 443 depuis MGMT, VPN et `runner01` ; mises à jour DNS dynamiques (5300) de `dns02` vers `dns01` ; NTP et sauvegardes **sortants**.
- `host_vars/gw01/pare_feu.yml` reste la matrice des flux qui traversent `gw01` ; la matrice **documentaire** (`docs/socle/matrice-flux.md`) doit désormais couvrir aussi les flux internes au VLAN INFRA.

> ⚠️ **Attention** : un filtrage local d'entrée mal écrit coupe SSH, donc Ansible, donc le moyen de réparer. Le rôle `pare_feu_local` applique la même prudence que `pare_feu` : validation (`nft -c`), retour automatique si la confirmation n'arrive pas, et **un hôte à la fois** (`dns02` d'abord, puis `ca01`, `nbx01`, et `dns01` en dernier). Garde l'accès console Proxmox (`qm terminal`) et le compte `secours` sous la main.

**Travail demandé**
1. **Constat.** Depuis `runner01` et depuis une VM sandbox, scanne les quatre hôtes (`nmap -sT -p- --open`, et `-sU` sur 53, 67, 123) ; sur chaque hôte, liste ce qui écoute (`ss -tulpn`). Fais le tableau « écoute / devrait écouter / devrait être joignable par ».
2. **Les services d'abord.** Corrige à la source ce qui n'a pas à écouter, ou pas sur toutes les adresses : adresses d'écoute de PowerDNS, du récurseur, de Kea, de PostgreSQL et de Valkey sur `nbx01`, de step-ca. Revois les contrôles d'accès applicatifs (`webserver-allow-from`, `incoming.allow_from`, `allow-axfr-ips`, `allow-dnsupdate-from`, `ALLOWED_HOSTS` de NetBox…). Pour un service de ton choix, mesure l'effet du confinement systemd (`systemd-analyze security <unité>`) et ajoute les protections qui ne gênent pas son fonctionnement.
3. **Le filtrage local.** Écris le rôle `pare_feu_local` (données par hôte, mêmes conventions que la matrice de `gw01` : chaque règle a un motif et une référence), son scénario Molecule, et applique-le hôte par hôte par le pipeline.
4. **La matrice de `gw01`.** Relis `host_vars/gw01/pare_feu.yml` à la lumière du module 06 : flux à ajouter (s'ils ne le sont pas déjà), flux devenus obsolètes (dnsmasq), motifs et références à jour. Applique.
5. **La preuve.** Refais le scan de l'étape 1 et compare ; teste chaque flux légitime du contexte (au moins un test par ligne). Mets à jour `docs/socle/matrice-flux.md` : elle renvoie à `pare_feu.yml` pour le transit et liste les flux internes à INFRA (renvoi aux variables du rôle `pare_feu_local`).

**Critères de réussite**
- [ ] `dns01`, `dns02`, `ca01` et `nbx01` filtrent leurs entrées (nftables, politique `drop`) par le rôle `pare_feu_local`.
- [ ] Depuis `runner01` : le port 5300 de `dns01`, le port 8004 de Kea, PostgreSQL de `nbx01` ne sont **pas** joignables ; l'API PowerDNS (8081), DNS (53), SSH (22) et HTTPS de NetBox et de `ca01` le sont.
- [ ] Depuis `adm01` : 5300, 8004 (Kea) et 8081 de `dns01` sont joignables.
- [ ] La matrice de `gw01` contient les flux de `dns02` (DNS, DHCP) et des sauvegardes applicatives du module ; `nft -c -f /etc/nftables.conf` passe sur `gw01`.
- [ ] `docs/socle/matrice-flux.md` sur `main` mentionne `dns02`, la CRL et les flux internes à INFRA.

**Vérification** : `lab/bin/check 06 30`

<details><summary>Indice 1</summary>

Une règle d'entrée locale doit aussi laisser passer les **réponses** aux connexions que l'hôte ouvre lui-même (état `established,related`), la boucle locale, et l'ICMP utile (PMTUD, ping de diagnostic). Le relais DHCP envoie depuis le port 67 vers le port 67 : ce n'est pas une connexion « établie » pour nftables.
</details>

<details><summary>Indice 2</summary>

PostgreSQL et Valkey n'ont aucune raison d'écouter ailleurs que sur la boucle locale de `nbx01`. Pour step-ca, l'adresse d'écoute est dans `ca.json` (`address`, `insecureAddress`). Pour Kea, ce sont les `socket-address` des sockets de contrôle et les URL des pairs.
</details>

**Pour aller plus loin** (facultatif) : appliquer `pare_feu_local` à `git01`, `runner01`, `s3-01` ; micro-segmentation par le pare-feu Proxmox (groupes de sécurité par rôle) et comparaison avec le filtrage dans l'invité ; [nftables wiki](https://wiki.nftables.org/), [`systemd-analyze security`](https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html).

---

### M06-E31 — ADR : flux d'autorité autour de la source de vérité  `RED` `★★`

> **Ticket PLAT-757** — *De : Claire Morel*
> On a maintenant cinq endroits qui « savent » quelque chose sur une VM : NetBox, Proxmox, l'état OpenTofu, PowerDNS, Kea. La semaine dernière, Karim a corrigé une adresse dans NetBox, Julien l'a corrigée dans le code OpenTofu, et la synchronisation de la nuit a remis l'ancienne valeur dans NetBox. Personne n'avait tort, personne n'avait raison.
> Écris l'ADR qui dit, pour chaque information, **qui fait foi**, dans quel sens elle circule, qui a le droit de l'écrire, et ce qu'on fait d'un écart.

**Objectifs pédagogiques**
- Distinguer intention (ce qui doit être) et réalité observée (ce qui est), et en tirer un sens de circulation pour chaque donnée.
- Décider d'une architecture de synchronisation et de ses garde-fous (écritures concurrentes, dérive, suppression).
- Rédiger une décision défendable, avec ses conséquences négatives.

**Prérequis** : M06-E11 à E15, M06-E17, M05 (état OpenTofu, dérive).
**Durée indicative** : 2 h.

**Travail demandé**
Rédige `docs/socle/adr/ADR-0060-flux-autorite-source-de-verite.md` (gabarit MADR de M00-E33, deux pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Lister les **informations** concernées (au moins : existence d'une VM, VMID, ressources CPU/mémoire/disque, adresse IP, nom DNS et PTR, rôle et étiquettes, statut — planifiée, active, décommissionnée —, adresse MAC, bail DHCP d'une VM sandbox, certificat d'un hôte) et, pour chacune, la **source qui fait foi** et les copies.
2. Comparer au moins trois options d'architecture (par exemple : NetBox fait foi pour l'intention et tout en découle ; le code OpenTofu fait foi et NetBox n'est qu'un reflet ; chaque outil fait foi pour son domaine avec des synchronisations croisées) avec leurs pour et contre.
3. Trancher, et dessiner (texte ou Mermaid) le sens des flux : qui écrit dans NetBox (humain, OpenTofu, script de synchronisation), qui lit.
4. Dire ce qui se passe en cas d'**écart** : détection (quel outil, quand), qui gagne, qui est prévenu, et le cas de la **suppression** (une VM disparue de Proxmox est-elle supprimée de NetBox ?).
5. Traiter les droits : quels jetons écrivent dans quoi (registre des secrets), et comment on empêche l'écriture concurrente du cas de Karim et Julien.
6. Lister les conséquences négatives et les actions induites (avec le module du workbook où elles seront traitées : M11 pour le bare-metal, M21 pour la supervision, M24/M25 pour les identités et les secrets…).

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en deux pages, et contient un tableau « information → source qui fait foi → copies → sens de synchronisation ».
- [ ] Au moins trois options réellement envisagées, avec pour et contre.
- [ ] Le cas de Karim et Julien est rejoué avec la décision : on sait qui gagne et comment l'éviter.
- [ ] La détection d'écart, la suppression et les droits d'écriture sont traités.
- [ ] Les conséquences négatives sont écrites, avec des actions datées ou rattachées à un module.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Une bonne règle : une information a **un seul** écrivain automatique. Les humains peuvent écrire là où se trouve l'intention ; les outils écrivent la réalité observée **à côté** de l'intention (champ, étiquette, journal de modifications), pas par-dessus.
</details>

<details><summary>Indice 2</summary>

Demande-toi, pour chaque information : si deux sources divergent, laquelle préfères-tu croire **pour agir** (créer, corriger) et laquelle pour **constater** (inventaire, audit) ? Les deux réponses peuvent être différentes.
</details>

**Pour aller plus loin** (facultatif) : les scripts et la notion de *custom script*/*event rule* de NetBox pour pousser un changement d'intention vers un pipeline ; le plugin `netbox-proxmox` ; [la notion de « source of truth » dans la documentation NetBox](https://netboxlabs.com/docs/netbox/).

---

### M06-E32 — Questions de production : services d'infrastructure  `Q` `★★★`

> **Ticket PLAT-758** — *De : Karim Benali*
> Avant de te confier l'astreinte sur les services socle, je veux t'entendre sur ces questions. Comme d'habitude : argumente, chiffre quand c'est possible, et dis de quoi dépend le « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur le comportement en production du DNS, du DHCP et de la PKI : cache, propagation, défaillances partielles, sécurité.
- Relier les choix du module à des risques concrets.

**Prérequis** : paliers 1 et 2, M06-E24 à E30.
**Durée indicative** : 1 h 30.

**Questions**

1. Tu changes l'adresse de `nbx01` dans la zone. Le TTL de l'enregistrement est de 3 600 s, celui du SOA négatif (*minimum*) de 300 s. Combien de temps, au pire, un client du lab peut-il obtenir l'ancienne adresse ? Qu'est-ce qui allonge ce délai (caches à plusieurs niveaux) ? Que fais-tu **la veille** d'un changement d'adresse planifié ?
2. QCM — `dns01` est éteint. Un client a `nameserver 10.10.20.10` puis `nameserver 10.10.20.16` dans `/etc/resolv.conf`, sans option. Pour chaque résolution :
   a) il interroge les deux en parallèle et prend la première réponse ;
   b) il interroge d'abord 10.10.20.10, attend l'expiration du délai (5 s par défaut), puis 10.10.20.16 ;
   c) il interroge 10.10.20.16 directement car la bibliothèque mémorise que 10.10.20.10 est mort ;
   d) il échoue, car seul le premier serveur est utilisé.
   Que changent `options timeout:1 attempts:2 rotate` ? Et un client qui utilise `systemd-resolved` ?
3. Le numéro de série de `par1.medisphere.internal` sur `dns02` est **supérieur** à celui de `dns01` (restauration d'une vieille sauvegarde sur `dns01`). Que se passe-t-il pour la réplication ? Comment corriges-tu proprement (arithmétique des numéros de série, RFC 1982) ?
4. Pourquoi TSIG plutôt qu'un filtrage par adresse pour les transferts de zone ? Qu'est-ce que TSIG ne protège pas ? Le secret `axfr-par1` fuite : quelles conséquences, quelles actions, dans quel ordre ?
5. Explique pourquoi un résolveur validant **refuse** une réponse dont la signature a expiré hier, et ce qui doit se passer côté primaire et secondaire pour que cela n'arrive jamais. Quelle est la conséquence d'une horloge en avance de deux jours sur un récurseur validant ?
6. QCM — Le récurseur de `dns01` a une ancre de confiance pour `par1.medisphere.internal`. On roule la clé de la zone (nouvelle CSK) sans mettre à jour l'ancre. Résultat :
   a) aucun effet, l'ancre ne sert qu'au premier démarrage ;
   b) les réponses de la zone sont servies sans le drapeau `ad` ;
   c) les réponses de la zone sont *bogus* : SERVFAIL pour les clients qui ne demandent pas `+cd` ;
   d) le récurseur bascule seul sur la nouvelle clé grâce à RFC 5011.
   Justifie, et dis ce que RFC 5011 changerait (et si le Recursor le met en œuvre pour une ancre configurée).
7. Kea en `hot-standby` : le lien entre `dns01` et `dns02` est coupé (pas les serveurs). Décris ce qui se passe avec `max-unacked-clients` à 0, puis à 10. Quel est le risque d'un « cerveau divisé » (*split brain*) en DHCP, et pourquoi est-il **moins** grave en `hot-standby` qu'il n'y paraît ? Que deviennent les baux à la réconciliation ?
8. Un serveur DHCP accorde des baux de 12 h. `dns01` et `dns02` tombent tous deux pendant 8 h. Que se passe-t-il pour les VMs sandbox déjà configurées ? À partir de quand perdent-elles leur adresse (T1, T2, fin de bail) ? Et pour celles qui démarrent pendant la panne ?
9. Pourquoi Kea transmet-il chaque bail au pair **avant** de répondre au client en HA ? Quel est le coût en latence, et que fait le paramètre `delayed-updates-limit` (à lire dans la doc) ?
10. QCM — Un certificat ACME de 30 jours, renouvelé à 15 jours de l'expiration, dont le renouvellement échoue en silence. La supervision alerte à 10 jours. De combien de jours d'avance dispose l'astreinte entre l'alerte et la panne ? Et si on était resté sur le seuil par défaut de `cert-renewer` (66 % de la durée de vie) ?
    a) 10 jours dans les deux cas ;
    b) 10 jours, puis 0 jour : l'alerte et le renouvellement coïncideraient ;
    c) 5 jours, puis 10 jours ;
    d) 15 jours dans les deux cas.
11. Compare la révocation par CRL, par OCSP (et l'agrafage OCSP), et les certificats de courte durée. Pourquoi les autorités publiques et les navigateurs vont-ils vers des durées de plus en plus courtes ? Quelle est la durée maximale des certificats TLS publics prévue pour 2029, et en quoi cela concerne-t-il une PKI **interne** ?
12. L'intermédiaire de `ca01` est compromis (clé volée). Liste les actions, dans l'ordre, en distinguant TLS et SSH. Que t'apporte le fait que la racine soit hors ligne ? Que t'aurait coûté une racine en ligne ?
13. Les certificats SSH d'utilisateur durent 16 h. Un collaborateur quitte l'entreprise à 10 h. Jusqu'à quand peut-il se connecter si on ne fait rien ? Quels mécanismes d'OpenSSH (`RevokedKeys`, KRL) et de step-ca permettent de faire mieux ?
14. NetBox est indisponible pendant 2 h. Quels services du socle sont touchés immédiatement ? Lesquels seulement quand on veut **changer** quelque chose ? Qu'en conclus-tu sur sa place dans l'architecture (plan de contrôle contre plan de données) ?
15. Le relais de `gw01` envoie chaque requête aux deux serveurs Kea. Pourquoi est-ce nécessaire en `hot-standby` (et pas seulement « pratique ») ? Que se passerait-il avec un relais qui n'envoie qu'à `dns01` ?
16. Tu dois ajouter un troisième site (PAR3) dans deux ans. Quelles décisions de ce module rendent l'extension simple, lesquelles la compliquent (zones, ancres DNSSEC, HA Kea à deux nœuds, CA unique) ?

Les réponses argumentées sont dans le corrigé.

---

### M06-E33 — Rédiger la politique de certification de la PKI  `RED` `★★`

> **Ticket SEC-759** — *De : Sophie Laurent*
> L'auditeur HDS demandera la politique de certification de notre PKI interne. Aujourd'hui, elle est dans la tête de deux personnes et dans un `ca.json`. Je veux un document que je peux remettre à un auditeur et qu'un nouvel arrivant peut appliquer : qui fait quoi, comment on obtient un certificat, combien de temps il vit, comment on le révoque, comment on protège les clés, comment on contrôle.

**Objectifs pédagogiques**
- Structurer une politique de certification (inspirée de la RFC 3647) adaptée à une PKI interne.
- Relier chaque engagement écrit à un mécanisme vérifiable (configuration, procédure, contrôle).
- Distinguer politique (ce qu'on s'engage à faire) et procédures (comment on le fait).

**Prérequis** : M06-E02, M06-E03, M06-E18 à E20, M06-E27 (durées, révocation), M06-E28 (sauvegarde de la CA).
**Durée indicative** : 2 h 30.

**Travail demandé**
Rédige `docs/socle/pki/politique-certification.md` dans `plateforme/medisphere` (4 à 6 pages, par MR, relue par Sophie — joue son rôle avec la grille du corrigé). Il doit au minimum couvrir :
1. **Objet et périmètre** : quelles autorités (racine, intermédiaire, CA SSH), quels usages (TLS serveur interne, client TLS, SSH hôte, SSH utilisateur), ce qui est **hors** périmètre (certificats publics, signature de code, messagerie).
2. **Rôles** : responsable de la PKI, opérateurs, porteurs de la racine (au moins deux personnes), auditeur ; séparation des tâches.
3. **Hiérarchie** : noms distinctifs, algorithmes, durées des autorités, emplacement et protection de chaque clé (racine hors ligne, intermédiaire en ligne chiffrée) ; extensions et contraintes (longueur de chemin, contraintes de noms si tu les mets en place).
4. **Enregistrement et émission** : par type de certificat, comment le demandeur prouve son identité ou son contrôle du nom (ACME HTTP-01, provisioner JWK et son mot de passe, provisioner SSH…), qui peut demander quoi.
5. **Durées et renouvellement** : le tableau de M06-E27, le seuil de renouvellement, la supervision.
6. **Révocation** : motifs, qui décide, délais, mécanismes (passive, CRL, KRL SSH) et leurs limites, publication.
7. **Protection et continuité** : sauvegarde (M06-E28), cérémonies (création de la racine, renouvellement de l'intermédiaire), compromission de l'intermédiaire, perte de la racine.
8. **Journalisation et contrôle** : quoi est journalisé, combien de temps, revue périodique, indicateurs.
9. **Gestion du document** : version, propriétaire, date de revue, historique.

**Critères de réussite**
- [ ] Les neuf rubriques sont présentes, et chaque engagement chiffré (durée, délai, nombre de personnes) est cohérent avec la configuration réelle de `ca01` (M06-E27).
- [ ] Les limites sont écrites honnêtement (CRL peu consultée, pas d'OCSP, clé de l'intermédiaire sur disque).
- [ ] Chaque procédure citée renvoie à un runbook existant (RB-061, RB-063…) ou à un ticket ouvert.
- [ ] Le document est sur `main` de `plateforme/medisphere`, au chemin imposé.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

La RFC 3647 propose un plan en neuf chapitres pensé pour les autorités publiques : garde l'ossature, supprime ce qui n'a pas de sens en interne (obligations juridiques envers des tiers, tarifs), et écris court. Une politique se relit en 15 minutes ; les procédures sont ailleurs.
</details>

<details><summary>Indice 2</summary>

Pour chaque phrase « nous garantissons… », demande-toi : **quel fichier** ou **quel contrôle** le prouve ? Si la réponse est « aucun », soit tu retires la phrase, soit tu ouvres un ticket pour la rendre vraie.
</details>

**Pour aller plus loin** (facultatif) : [RFC 3647](https://www.rfc-editor.org/rfc/rfc3647) ; les exigences de base du CA/Browser Forum (pour comparer avec une PKI publique) ; les recommandations de l'ANSSI sur les infrastructures de gestion de clés.

---

### M06-E34 — Un nouveau service complet en temps limité  `CHRONO` `★★★`

> **Ticket CHG-760** — *De : Claire Morel*
> Démonstration demandée par la direction : « combien de temps pour mettre en service un nouveau serveur interne, proprement ? ». Notre réponse doit être : moins d'une matinée, sans un geste manuel, avec la sécurité et la supervision dès le premier jour.
> Le dossier est prêt (ressources de l'exercice). Chrono en main.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **tes** runbooks (en particulier RB-060), ton code et la documentation officielle.
- Durée cible : **2 h 30** entre l'ouverture du dossier (T0) et le service vérifié (T5).
- Tout passe par le code et les pipelines (NetBox, OpenTofu, Ansible, `pare_feu.yml`). Un geste manuel est permis pour **constater**, jamais pour configurer ; s'il t'en faut un pour avancer, note-le dans la feuille de temps : c'est un défaut de ton outillage.
- Le service est **temporaire** : à la fin, après la vérification, tu le retires proprement (VM, NetBox, DNS, supervision, flux), toujours par le code.

**Prérequis** : RB-060 (M06-E23), M06-E24 à E30.
**Durée** : 2 h 30 chronométrées + 30 minutes de retour d'expérience.

**Dossier** : [`ressources/M06-E34/dossier-chrono.md`](../ressources/M06-E34/dossier-chrono.md) (le besoin, les contraintes, la page à servir, la feuille de temps). Lis-le à T0, pas avant.

**Critères de réussite**
- [ ] Le service décrit dans le dossier est en service à T5, et toutes les exigences du dossier sont satisfaites (vérification ci-dessous, **avant** le retrait).
- [ ] La feuille de temps est remplie (T0 à T6), avec les gestes manuels éventuels et leur raison ; le temps total jusqu'à T5 est inférieur à 2 h 30 (sinon, améliore ton outillage et refais l'exercice).
- [ ] Le retour d'expérience (une demi-page) est rédigé, et RB-060 mis à jour par MR.
- [ ] Après le retrait, plus rien ne reste du service (VM, objets NetBox, enregistrements DNS, entrée de supervision, flux).

**Vérification** : `lab/bin/check 06 34` (à lancer à T5, **avant** le retrait ; le retrait est contrôlé par le mini-projet M06-E46).

**Pour aller plus loin** (facultatif) : refais l'exercice en visant 1 h, puis demande-toi ce qu'il faudrait pour que l'équipe de Julien le fasse **seule** (catalogue de services, module 28).
