# Module 06 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Dans ce palier, « j'ai redémarré le service et ça remarche » est presque toujours faux : un redémarrage efface la preuve (cache, état chargé, règle posée à chaud) sans corriger la cause, qui revient au prochain passage du code ou au prochain redémarrage.

Les scripts d'injection sont dans `corrige/pannes/` (`_m06-commun.sh` contient les fonctions partagées : remplacements de texte mémorisés et réversibles sans écraser une réparation, exécution par l'agent QEMU, lancement d'Ansible comme l'apprenant, VM sonde). Chaque modification est journalisée sur l'hôte touché dans `/var/lib/workbook/pannes.log` (copies d'origine dans `/var/lib/workbook/M06-EXX.*`), et sur `adm01` dans `~/.local/state/workbook/M06-EXX/`.

Les sorties reproduites sont **représentatives** : numéros, horodatages, empreintes et formulations exactes varient selon les versions. Elles suivent la documentation de PowerDNS Authoritative 5.0 / Recursor 5.4, de Kea 3.0, de step-ca 0.30, d'OpenSSH 10 (Debian 13) et de NetBox 4.6.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- format exact de `pdnsutil zone show` (lignes `ID = n (CSK), flags = 257, tag = …, Active …`) et de `pdnsutil metadata get` (`PRESIGNED = 1`), sur lesquels s'appuient les scripts de E41 et E42 ;
- comportement de Kea 3.0 quand `interfaces-config` désigne une interface absente (E36 v3) : selon la version, la configuration est refusée ou le serveur démarre sans socket sur cette interface — dans les deux cas plus aucun bail n'est servi ;
- message exact de Kea 3.0 pour un fichier de baux hors de `/var/lib/kea` (E36 v4) : la documentation annonce un refus de démarrer, le libellé reproduit ici est représentatif ;
- client DHCP de l'image dorée Debian 13 (netplan/systemd-networkd) : un redémarrage de la VM sonde ne réutilise pas le bail précédent (E36) ;
- authentification par jeton v2 (`nbt_…`) du plugin `netbox.netbox.nb_inventory` 3.23 et forme exacte des URL affichées par `-vvv` (E40) ;
- libellés exacts du journal de `sshd` (OpenSSH 10) pour un principal absent ou une clé révoquée (E38).

---

## Méthode commune aux pannes des services socle

1. **Reproduire sans intermédiaire.** Pas de `ping nom` ni de navigateur : `dig @<serveur> -p <port>`, `openssl s_client`, `ssh -o ControlPath=none -vvv`, `curl -sS -o /dev/null -w '%{http_code}'`, `nsupdate`. Chaque commande vise **un** maillon.
2. **Cartographier la chaîne.** Chaque service du module est une chaîne : client → récurseur → autoritaire → base ; client → relais → Kea → D2 → PowerDNS ; client → magasin de confiance → chaîne présentée → horloge ; client SSH → `sshd` (algorithmes, CA, principaux, KRL). Teste les maillons dans l'ordre et note le premier qui échoue.
3. **Lire l'état chargé, pas seulement le fichier.** `sshd -T`, `rec_control get-parameter`, `rec_control get-tas`, `pdnsutil metadata get`, `kea-dhcp4 -t` (et la commande `config-get` du socket de contrôle), `nft list ruleset`, `nginx -T`.
4. **Chercher ce qui a bougé.** `find /etc -newer <fichier témoin>`, `ls -lt`, journal des modifications de NetBox, `git status` des projets, `--check --diff` du rôle Ansible concerné : la différence entre ce que produirait le code et ce qui est en place **est** souvent la panne.
5. **Corriger à la source, puis faire converger le code.** Une correction à chaud est permise pour rétablir le service ; elle n'est pas finie tant que le rôle Ansible, OpenTofu ou NetBox ne produit pas le même état (second passage : `changed=0`, `No changes`).
6. **Vider ce qui doit l'être, et rien de plus.** Cache d'**un** nom (`rec_control wipe-cache`), rechargement d'**un** service ; jamais de redémarrage global « pour voir ».
7. **Prévenir** : quelle sonde de `ms-verif-services`, quel test Molecule, quelle règle de pipeline aurait vu la panne avant l'utilisateur ?

---

### M06-E35 — Panne : un nom interne ne se résout plus

**Démarche de diagnostic**

*Symptôme* : la sonde de supervision (qui interroge explicitement `dns01`) est rouge pour `git01.par1.medisphere.internal` ; une partie seulement des jobs de CI échoue ; Internet se résout.

*Hypothèses* : récurseur qui ne relaie plus la zone ; autoritaire arrêté ou qui ne sert plus la zone ; enregistrement absent de la zone (et de sa source) ; réponse négative en cache ; client qui interroge un autre serveur.

**Étape 1 — Interroger chaque résolveur, sans le résolveur système.**

```
admin@adm01:~$ for s in 10.10.20.10 10.10.20.16; do dig @$s git01.par1.medisphere.internal +noall +comments +answer +authority | grep -E 'status|IN'; done
admin@adm01:~$ dig @10.10.20.10 nbx01.par1.medisphere.internal +short
admin@adm01:~$ dig @10.10.20.10 deb.debian.org +short
```

Pourquoi certains jobs passent : `/etc/resolv.conf` de `runner01` liste deux résolveurs. La bibliothèque C (glibc) passe au suivant sur un délai dépassé, un `SERVFAIL` ou un `REFUSED`, **pas** sur un `NXDOMAIN` (réponse définitive). Selon la variante, la redondance masque donc la panne ou non : c'est la première information à noter.

**Étape 2 — Séparer récurseur et autoritaire sur `dns01`.**

```
admin@dns01:~$ dig @127.0.0.1 -p 5300 git01.par1.medisphere.internal +norecurse
admin@dns01:~$ systemctl status pdns pdns-recursor --no-pager
admin@dns01:~$ sudo journalctl -u pdns -u pdns-recursor --since -2h --no-pager | tail -n 40
admin@dns01:~$ sudo rec_control get-parameter recursor.forward_zones
```

**Variante 1 — relais vers le mauvais port.**

```
admin@adm01:~$ dig @10.10.20.10 git01.par1.medisphere.internal
;; ->>HEADER<<- opcode: QUERY, status: SERVFAIL, id: 41823
admin@dns01:~$ dig @127.0.0.1 -p 5300 git01.par1.medisphere.internal +short
10.10.20.12
admin@dns01:~$ sudo rec_control get-parameter recursor.forward_zones
recursor.forward_zones:
- zone: par1.medisphere.internal
  forwarders: [127.0.0.1:5301, 10.10.20.16:5301]
…
admin@dns01:~$ sudo ss -lunp | grep -E ':530[01]'
UNCONN 0 0 127.0.0.1:5300 0.0.0.0:* users:(("pdns_server",…))
```

L'autoritaire répond, le récurseur interroge un port où personne n'écoute (aucun relais ne répond, `dns02` compris) : `SERVFAIL`, et la glibc bascule sur `dns02`, d'où les jobs qui passent. Cause racine : une modification de `recursor.yml` (5300 → 5301) faite hors du rôle `powerdns_recursor`. Correctif : `ansible-playbook playbooks/site.yml --limit dns01 --tags powerdns_recursor --check --diff` montre la différence ; l'application du rôle la corrige et redémarre le récurseur (*handler*).

**Variante 2 — zone relayée mal nommée.**

```
admin@adm01:~$ dig @10.10.20.10 git01.par1.medisphere.internal
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 7741
;; flags: qr rd ra ad; …
;; AUTHORITY SECTION:
.                       86400   IN      SOA     a.root-servers.net. nstld.verisign-grs.com. 2026100700 …
```

Le `NXDOMAIN` porte le SOA **de la racine** : la racine a prouvé (NSEC signé) que `internal.` n'existe pas. La question est donc partie sur Internet : le récurseur ne relaie plus la zone. `rec_control get-parameter recursor` (ou le fichier `recursor.yml`) montre `zone: medisphere.interne` et `zone: par1.medisphere.interne` (faute de frappe francisée, sur la zone parente aussi : relayée seule, elle aurait continué de servir `par1`). Selon tes ancres (M06-E26), le récurseur rend ce `NXDOMAIN` (avec ou sans `ad`) ou un `SERVFAIL` (l'ancre positive de `par1` ne trouve plus aucune clé) : dans les deux cas, `dig +cd` montre le SOA de la racine en autorité, et c'est lui qui signe le diagnostic. ⚠️ À vérifier sur ta version (interaction ancre négative de `medisphere.internal` / ancre positive de `par1`, voir M06-E26). Avec un `NXDOMAIN`, la glibc **ne bascule pas** sur `dns02` (réponse définitive) : selon l'ordre des résolveurs, tout ou partie des clients échoue ; avec un `SERVFAIL`, elle bascule, d'où les jobs qui passent. Cause racine et correctif : comme la variante 1 (modification hors du rôle ; application du rôle). Pense au cache négatif : après correction, les noms demandés pendant la panne restent `NXDOMAIN` jusqu'à expiration ; `rec_control wipe-cache 'par1.medisphere.internal$'` (le `$` vide toute la zone) le règle.

**Variante 3 — enregistrement supprimé, puis cache négatif.**

```
admin@dns01:~$ dig @127.0.0.1 -p 5300 git01.par1.medisphere.internal
;; status: NXDOMAIN
;; AUTHORITY SECTION:
par1.medisphere.internal. 300 IN SOA dns01.par1.medisphere.internal. hostmaster.medisphere.internal. 2026100705 …
admin@dns01:~$ dig @10.10.20.16 -p 5300 git01.par1.medisphere.internal +short      # le secondaire a suivi (NOTIFY)
admin@dns01:~$ sudo -u pdns pdnsutil zone list par1.medisphere.internal | grep -c git01
0
```

Le SOA est celui de **ta** zone : le nom n'existe plus chez toi, et le secondaire a suivi (série incrémentée, NOTIFY, IXFR). Qui l'a retiré ? Le journal de l'autoritaire ne trace pas les modifications faites par `pdnsutil` ; la série et la date de la zone donnent l'heure. Remonte à la **source** : si la zone est générée depuis NetBox (M06-E15) ou par OpenTofu (M06-E14), le `plan` ou la synchronisation en mode `--dry-run` montre l'enregistrement à recréer. Corrige par cette source (`tofu apply`, synchronisation), jamais par un `pdnsutil rrset add` à la main qui serait effacé ou dupliqué au prochain passage.

Puis le piège : l'autoritaire répond de nouveau `10.10.20.12`, mais le récurseur répond toujours `NXDOMAIN`.

```
admin@adm01:~$ dig @10.10.20.10 git01.par1.medisphere.internal | grep -E 'status|SOA'
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN
par1.medisphere.internal. 274 IN SOA …
```

Le TTL de la ligne SOA **décroît** d'une requête à l'autre : c'est la réponse négative mise en cache (RFC 2308), pour la plus petite des deux valeurs : TTL du SOA et champ *minimum* du SOA, plafonnée par `recordcache.max_negative_ttl` (3600 s par défaut). Correctif ciblé :

```
admin@dns01:~$ sudo rec_control wipe-cache git01.par1.medisphere.internal
wiped 2 records, 1 negative records, 1 packets
```

(Même chose sur le récurseur de `dns02`.) Avec le SOA de M06-E06 (TTL et *minimum* de 300 s), la réponse négative disparaît seule en cinq minutes au plus ; un *minimum* d'une heure ou plus, fréquent dans les modèles, ferait durer la panne bien après la réparation. Prévention : garder ce *minimum* court pour la zone interne, et faire vider par la synchronisation le cache des noms qu'elle crée.

**Variante 4 — base de l'autoritaire illisible.**

```
admin@dns01:~$ systemctl status pdns --no-pager
● pdns.service - PowerDNS Authoritative Server
     Active: activating (auto-restart) (Result: exit-code) …
admin@dns01:~$ sudo journalctl -u pdns -n 20 --no-pager
… gsqlite3: … unable to open database file …
admin@dns01:~$ grep -hE '^(launch|gsqlite3-database|lmdb-filename)' /etc/powerdns/pdns.conf /etc/powerdns/pdns.d/*.conf
launch=gsqlite3
gsqlite3-database=/var/lib/powerdns/pdns.sqlite3
admin@dns01:~$ ls -l /var/lib/powerdns/
-rw------- 1 root root 1638400 … pdns.sqlite3
```

Le service tourne sous le compte `pdns` et ne peut plus ouvrir sa base (propriétaire `root`, mode 600). Même constat sur `dns02` (`dig @10.10.20.16 -p 5300 …` ne répond plus, `ls -l` identique) : le récurseur, qui relaie vers les deux serveurs faisant autorité, n'en trouve aucun qui réponde, d'où le `SERVFAIL`. Les dates (`ls -l --time-style=full-iso`, `stat`) et le journal racontent un « script d'audit des droits » passé en root sur les deux serveurs DNS. Correctif : `sudo chown pdns:pdns /var/lib/powerdns/pdns.sqlite3 && sudo chmod 640 …` (les droits exacts que pose ton rôle `powerdns_auth`), puis `systemctl restart pdns`, **sur les deux hôtes**. Mieux : le rôle `powerdns_auth` gère le propriétaire et le mode de la base (un passage du pipeline aurait corrigé, et la détection de dérive l'aurait signalé), et toute procédure qui touche la base (restauration RB-061, M06-E28) se termine par un `chown` et un contrôle `pdnsutil zone check`. Note : si un seul des deux serveurs avait été touché, les clients n'auraient rien vu (le récurseur interroge l'autre) : c'est le rôle de la redondance… et la raison pour laquelle il faut une sonde **par maillon**.

**Vérification** : `lab/bin/check 06 35`, puis `lab/bin/break 06 35 --annuler` pour clore.

**Explications**

Un récurseur PowerDNS consulte d'abord ses `forward_zones` : pour un nom de `par1.medisphere.internal`, il pose la question (sans récursion, bit RD à 0) aux relais déclarés et accepte leur réponse faisant autorité. Si la zone n'y figure pas, il fait une résolution itérative depuis la racine, comme pour n'importe quel nom. `.internal` est réservé à l'usage privé (ICANN, 2024) et la racine prouve son absence par une réponse signée. Les réponses (positives et négatives) sont mises en cache selon leur TTL ; une réponse négative ne disparaît pas parce que la donnée revient à la source.

**Alternatives**
- `recursor.forward_zones_file` (fichier rechargeable par `rec_control reload-zones`) plutôt que la liste en ligne : modifiable sans redémarrage.
- Autoritaire et récurseur sur des machines séparées : isolation meilleure, plus de VMs.
- `dnsdist` en frontal : routage par zone, *health checks* des relais, cache commun.

**Pièges classiques**
- Tester avec `ping git01` ou `getent hosts` : la glibc a peut-être basculé sur `dns02`, et tu ne vois pas la panne.
- Ignorer la section d'autorité : elle dit **qui** a répondu `NXDOMAIN`.
- Recréer l'enregistrement à la main dans PowerDNS : la synchronisation suivante le supprime (ou le duplique).
- Redémarrer le récurseur pour « vider le cache » : ça marche, mais c'est une coupure de service de tout le lab et ça efface la preuve.

**En production chez MédiSphère**
Sondes par maillon (récurseurs, autoritaires sur 5300, série du secondaire), alerte sur le taux de `SERVFAIL` (métrique `servfail-answers` de `rec_control get-all`, exportée au module 21), modifications de configuration uniquement par les rôles, et SOA *minimum* court pour les zones internes.

---

### M06-E36 — Panne : les VMs sandbox n'obtiennent plus d'adresse

**Démarche de diagnostic**

*Symptôme* : les nouvelles VMs du VLAN 99 n'ont qu'une adresse `fe80::` ; la VM sonde 2064 non plus.

*Hypothèses*, dans l'ordre du chemin : le DISCOVER n'atteint pas le relais ; le relais ne le transmet pas ; il est filtré en route ; Kea ne le reçoit pas ; Kea le reçoit mais ne répond pas (configuration, plage, sous-réseau) ; la réponse n'atteint pas le relais ; le relais ne la renvoie pas au client.

**Étape 1 — Deux points de capture pendant un redémarrage de la sonde.**

```
root@pve01:~# qm reboot 2064 &
root@pve01:~# tcpdump -c 10 -eni tap2064i0 port 67 or port 68
root@gw01:~# tcpdump -c 10 -ni any port 67 or port 68
admin@dns01:~$ sudo tcpdump -c 10 -ni ens18 port 67
```

Lecture : sur `tap2064i0`, des `DHCP-Discover` en broadcast depuis `0.0.0.0.68`. Sur `gw01`, le même DISCOVER arrive sur `ens19.99`, puis (si le relais fait son travail) repart en unicast `10.10.99.1.67 > 10.10.20.10.67`, avec `giaddr 10.10.99.1`. Sur `dns01`, il arrive, et l'OFFER repart vers `10.10.99.1.67`. Le premier point où le paquet n'apparaît plus désigne l'étage.

**Variante 1 — relais qui n'écoute plus pour le VLAN 99.** Le DISCOVER arrive sur `ens19.99` de `gw01`, rien ne repart vers `dns01`.

```
root@gw01:~# grep -Eh '^[[:space:]]*dhcp-relay' /etc/dnsmasq.conf /etc/dnsmasq.d/*.conf
dhcp-relay=10.10.99.11,10.10.20.10
dhcp-relay=10.10.99.11,10.10.20.16
root@gw01:~# ip -4 -br addr show ens19.99
ens19.99@ens19   UP   10.10.99.1/24
```

Le premier champ de `dhcp-relay` est l'adresse **locale** de l'interface sur laquelle le relais reçoit les requêtes des clients (et qu'il met dans `giaddr`) : 10.10.99.11 n'existe sur aucune interface. Correctif : rétablir `10.10.99.1` par le code qui gère ce fichier (M06-E25), redémarrer dnsmasq, retester.

**Variante 2 — réponses des serveurs jetées sur `gw01`.** Le DISCOVER part vers `dns01`, l'OFFER revient (on le voit sur `dns01` et sur `ens19.20` de `gw01`), mais rien ne repart vers le client.

```
root@gw01:~# nft -a list chain inet filter input | head -n 8
        ip saddr 10.10.20.0/24 udp sport 67 counter packets 14 bytes 4844 drop comment "durcissement INC-3342" # handle 97
…
root@gw01:~# grep -c 'INC-3342' /etc/nftables.conf
0
```

La réponse de Kea est destinée à `gw01` lui-même (10.10.99.1, port 67) : elle passe par la chaîne `input`, où une règle insérée **à chaud** en tête la jette (ses compteurs montent à chaque essai). Elle n'est pas dans `/etc/nftables.conf` : `grep -c 'INC-3342' /etc/nftables.conf` → 0. C'est une dérive. Correctif : `nft delete rule inet filter input handle 97` (ou mieux, réappliquer le rôle `pare_feu`, qui recharge le jeu de règles complet depuis le fichier). Prévention : la détection de dérive du M04 compare-t-elle le jeu de règles **chargé** au fichier ? Si elle ne regarde que le fichier, elle n'a rien vu : ajoute au rôle `pare_feu` une vérification « `nft list ruleset` = rendu du modèle ».

**Variante 3 — Kea configuré sur une interface absente.** Rien n'arrive dans Kea : selon la version, le service refuse de démarrer, ou il tourne sans écouter sur `ens18`.

```
admin@dns01:~$ sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
… DHCPSRV_… interface ens19 … (message variable selon la version)
admin@dns01:~$ sudo ss -lunp 'sport = :67'
admin@dns01:~$ sudo grep -n '"interfaces"' /etc/kea/kea-dhcp4.conf
5:        "interfaces": [ "ens19" ]
admin@dns01:~$ ip -br link
lo UNKNOWN …   ens18 UP …
```

Même constat sur `dns02` (le changement a été « poussé partout »). Correctif : rétablir l'interface réelle (`ens18`) dans le modèle du rôle `kea_dhcp4`, appliquer, vérifier `ss -lunp` (Kea écoute sur `10.10.20.10:67`). Prévention : `"service-sockets-require-all": true` fait échouer Kea au démarrage si une socket ne s'ouvre pas, au lieu de tourner à vide ; et le test Molecule vérifie l'écoute effective.

**Variante 4 — fichier de baux hors du dossier autorisé.**

```
admin@dns01:~$ systemctl status isc-kea-dhcp4-server --no-pager
     Active: failed (Result: exit-code)
admin@dns01:~$ sudo journalctl -u isc-kea-dhcp4-server -n 20 --no-pager
… DHCP4_CONFIG_LOAD_FAIL configuration error using file: /etc/kea/kea-dhcp4.conf, reason: … invalid path specified: '/tmp', supported path is '/var/lib/kea'
```

Depuis Kea 2.7.9 (donc en 3.0), les fichiers de baux doivent résider dans le dossier de données compilé (`/var/lib/kea` pour les paquets ISC) : c'est une correction de sécurité (un fichier de configuration modifié ne doit pas permettre d'écrire n'importe où avec les droits de Kea). Beaucoup de tutoriels plus anciens écrivent un chemin libre. Correctif : nom de fichier seul (`"name": "kea-leases4.csv"`) dans le rôle, appliquer sur les deux serveurs. Les baux en cours n'ont pas été perdus (le fichier de `/var/lib/kea` est intact).

**Vérification** : redémarre la sonde, `qm guest cmd 2064 network-get-interfaces` → adresse 10.10.99.1xx ; le bail apparaît dans `/var/lib/kea/kea-leases4.csv` ; `lab/bin/check 06 36` ; puis `lab/bin/break 06 36 --annuler` (détruit la VM 2064).

**Explications**

Un relais DHCP reçoit le broadcast du client sur une interface, écrit l'adresse de cette interface dans `giaddr` et transmet en unicast au serveur, depuis et vers le port 67. Kea choisit le sous-réseau dont le préfixe contient `giaddr` et répond **au relais** (port 67), qui renvoie au client. Trois acteurs, deux sens : la panne est quelque part sur ce trajet, et deux captures bien placées suffisent toujours à la localiser.

**Alternatives**
- Relais Kea plutôt que dnsmasq ? Kea ne fournit pas de relais ; `isc-dhcp-relay` est en fin de vie. Les routeurs du bloc B (FRR, M07) n'ont pas de relais DHCP intégré : dnsmasq reste un choix raisonnable.
- `perfdhcp` (outil de Kea) pour tester sans VM.

**Pièges classiques**
- Capturer uniquement sur le serveur : on ne voit pas qu'aucun paquet n'arrive, faute de point de comparaison.
- Corriger la règle nftables à la main sans regarder pourquoi la détection de dérive ne l'a pas vue.
- Avec la haute disponibilité, corriger un seul serveur : le partenaire reprend la charge, puis la panne revient au retour du premier.

**En production chez MédiSphère**
Sonde DHCP active (requête relayée réelle toutes les 5 minutes) ; alerte sur l'état HA (`ha-heartbeat`) et sur le taux d'occupation de la plage ; aucune règle nftables posée à chaud qui ne soit retranscrite dans `pare_feu.yml` le jour même.

---

### M06-E37 — Panne : certificat refusé

**Démarche de diagnostic**

*Symptôme* (selon le ticket affiché) : un client refuse un certificat, un autre l'accepte.

*Hypothèses* : chaîne incomplète ; certificat émis par une autre CA ; nom absent du SAN ; client sans la racine ; horloge du client hors de la période de validité ; certificat réellement expiré (renouvellement en panne).

**Étape 1 — Ce que présente le serveur, ce qu'en pense le client.**

```
admin@adm01:~$ openssl s_client -connect 10.10.20.13:443 -servername nbx01.par1.medisphere.internal -showcerts </dev/null 2>/dev/null \
  | grep -E '^ *[0-9] s:|^ *i:|Verify return code'
admin@adm01:~$ curl -v https://nbx01.par1.medisphere.internal/ -o /dev/null 2>&1 | grep -E 'SSL certificate|issuer|expire'
```

**Variante 1 — chaîne incomplète sur `nbx01`.**

```
 0 s:CN = nbx01.par1.medisphere.internal
   i:O = MédiSphère, CN = MédiSphère Intermediate CA
Verify return code: 21 (unable to verify the first certificate)
```

Un seul certificat présenté (la feuille). `adm01` n'a que la racine : il ne peut pas relier la feuille à la racine sans l'intermédiaire. Le navigateur de Claire, lui, a vu cet intermédiaire auparavant (cache des intermédiaires de Firefox, ou téléchargement par l'extension *Authority Information Access*) et complète la chaîne en silence : c'est pourquoi elle ne voit rien. Cause racine : le fichier pointé par `ssl_certificate` (`nginx -T | grep ssl_certificate`) ne contient plus que la feuille, après un renouvellement qui a écrit le mauvais fichier (ou un script qui a « nettoyé » la chaîne). Correctif : le client ACME doit écrire la **chaîne complète** (`step ca certificate` et `step ca renew` écrivent feuille + intermédiaire par défaut ; avec certbot, utiliser `fullchain.pem`), puis `nginx -t && systemctl reload nginx`. Vérification : `Verify return code: 0 (ok)` et deux blocs `BEGIN CERTIFICATE`.

**Variante 2 — certificat de `git01` signé par une autre CA.**

```
 0 s:CN = git01.par1.medisphere.internal
   i:O = MédiSphère, CN = MédiSphère CA provisoire
Verify return code: 20 (unable to get local issuer certificate)
admin@git01:~$ sudo ls -l --time-style=full-iso /etc/gitlab/ssl/
admin@git01:~$ sudo openssl x509 -in /etc/gitlab/ssl/git01.par1.medisphere.internal.crt -noout -issuer -dates -fingerprint
```

L'émetteur s'appelle comme l'ancienne CA provisoire, retirée des magasins en M06-E03 : plus personne ne lui fait confiance (et même si l'ancienne racine était encore installée, la signature ne correspondrait pas : c'est une autre clé). Les dates du fichier montrent qu'il a été remplacé hier soir : la « restauration de la configuration » d'InfoGér a remis un ancien `/etc/gitlab/ssl/`. Correctif : redemander un certificat par la voie normale (le client ACME de `git01`, M06-E18 : relancer l'unité de renouvellement ou `step ca certificate` avec le provisioner `acme`), le déposer, `gitlab-ctl hup nginx`. Prévention : la procédure de restauration de GitLab (M01) exclut `/etc/gitlab/ssl` (le certificat se réobtient en une minute ; le restaurer réintroduit un certificat périmé ou d'une autre CA), et la sonde d'expiration vérifie aussi **l'émetteur**.

**Variantes 3 et 4 — tout est juste côté serveurs, seul `runner01` refuse.**

```
admin@adm01:~$ ssh runner01 sudo journalctl -u gitlab-runner -n 5 --no-pager
… x509: certificate signed by unknown authority …                 (variante 3)
… tls: failed to verify certificate: x509: certificate has expired or is not yet valid … (variante 4)
```

*Variante 3* : la racine n'est plus dans le magasin de `runner01`.

```
admin@runner01:~$ ls -l /usr/local/share/ca-certificates/ /etc/ssl/certs/ | grep -i medisphere
admin@runner01:~$ curl -sS https://git01.par1.medisphere.internal -o /dev/null
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

Fichier supprimé et `update-ca-certificates --fresh` : la racine a disparu de `/etc/ssl/certs/ca-certificates.crt`. Le runner (Go) charge le magasin au démarrage : il a fallu un redémarrage du service (« après les mises à jour ») pour que la panne apparaisse, ce qui explique le décalage entre la modification et le symptôme. Correctif : réappliquer le rôle `ca_lab` sur `runner01` (qui redépose la racine et lance `update-ca-certificates`), puis `systemctl restart gitlab-runner`.

*Variante 4* : l'horloge de `runner01` est en avance de 45 jours, chrony est arrêté. Tous les certificats de 30 jours paraissent expirés, **et** ton certificat SSH d'utilisateur (16 h) aussi : `ssh runner01` est refusé (`sshd` compare la validité à **son** horloge). Entrée par l'agent :

```
root@pve01:~# qm guest exec 1007 -- date
root@pve01:~# qm guest exec 1007 -- systemctl is-active chrony
inactive
root@pve01:~# qm guest exec 1007 -- systemctl start chrony
root@pve01:~# qm guest exec 1007 -- chronyc makestep
root@pve01:~# qm guest exec 1007 -- chronyc tracking
```

`chronyc makestep` corrige l'horloge d'un saut (chrony ne la ramènerait sinon que très lentement : `makestep` du fichier de configuration ne s'applique qu'aux premières mesures). Cause racine à trouver : pourquoi chrony était-il arrêté ? (reprise d'un instantané, service masqué, désactivé ?). Prévention : sonde d'écart d'horloge sur chaque hôte (`chronyc tracking`, seuil 1 s), et redémarrage des services sensibles au temps après une correction.

**Vérification** : `lab/bin/check 06 37`, puis `lab/bin/break 06 37 --annuler`.

**Explications**

La vérification d'un certificat serveur répond à quatre questions indépendantes : la chaîne mène-t-elle à une ancre de **ce client** ? Chaque signature est-elle valide ? Le nom demandé est-il dans le SAN ? L'heure **du client** est-elle dans la période de chaque certificat ? Le serveur doit envoyer la feuille et les intermédiaires (RFC 8446 §4.4.2), jamais la racine (inutile) ; le client, lui, n'a que des racines.

**Alternatives**
- Installer l'intermédiaire dans les magasins des clients : masque les serveurs mal configurés, et complique la rotation de l'intermédiaire. À éviter.
- Épingler la racine dans les clients applicatifs (variable `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`) : utile pour Python (`certifi` n'a pas la racine MédiSphère), mais à documenter.

**Pièges classiques**
- Se fier au navigateur.
- `curl -k` ou `GIT_SSL_NO_VERIFY=1` « pour avancer » : on désactive précisément ce qui protège.
- Corriger l'horloge sans redémarrer les services qui ont mis en cache des jetons ou des sessions TLS.
- Oublier que les certificats SSH sont aussi datés.

**En production chez MédiSphère**
Sonde `ms-verif-services` sur chaque service : chaîne complète, émetteur attendu, nom, jours restants (alerte à 10 jours) ; écart d'horloge sur chaque hôte ; la restauration d'une configuration n'inclut jamais de certificat.

---

### M06-E38 — Panne : connexion SSH par certificat refusée

**Démarche de diagnostic**

*Symptôme* : `Permission denied (publickey)` vers un seul hôte, avec un certificat valide accepté ailleurs.

*Hypothèses*, dans l'ordre où `sshd` examine un certificat : algorithme non accepté ; CA non reconnue (`TrustedUserCAKeys`) ; certificat hors validité (horloge) ; principal non autorisé (`AuthorizedPrincipalsFile`) ; clé révoquée (`RevokedKeys`) ; options critiques (`source-address`).

**Étape 1 — Le client.**

```
admin@adm01:~$ ssh -o ControlPath=none -vvv nbx01 true 2>&1 | grep -E 'Offering|Server accepts|Authentications that can continue|send_pubkey_test|denied'
debug1: Offering public key: /home/admin/.ssh/id_ed25519 ED25519-CERT SHA256:… explicit
debug3: send_pubkey_test: no mutual signature algorithm          (variante 3)
debug1: Authentications that can continue: publickey
admin@adm01:~$ ssh-keygen -Lf ~/.ssh/id_ed25519-cert.pub | sed -n '1,12p'
        Type: ssh-ed25519-cert-v01@openssh.com user certificate
        Signing CA: ED25519 SHA256:Uq3… (using ssh-ed25519)
        Valid: from 2026-10-08T06:58:00 to 2026-10-08T22:59:00
        Principals:
                admin
```

**Étape 2 — Le serveur, par l'accès de secours.**

```
root@pve01:~# qm guest exec 1005 -- journalctl -u ssh -n 20 --no-pager
root@pve01:~# qm guest exec 1005 -- sshd -T | grep -E 'trustedusercakeys|authorizedprincipalsfile|pubkeyacceptedalgorithms|revokedkeys'
root@pve01:~# qm guest exec 1005 -- ls -l --time-style=full-iso /etc/ssh/sshd_config.d/
```

Si le journal est trop laconique, passe temporairement `LogLevel VERBOSE` dans un fichier de `sshd_config.d/` **placé avant** les autres (premier lu, première valeur retenue), recharge, essaie, puis retire-le ; consigne-le dans ton journal.

**Variante 1 — `TrustedUserCAKeys` contient la mauvaise CA.**

```
… sshd[2214]: error: Authentication key ED25519-CERT SHA256:… is not signed by a trusted CA … (libellé à vérifier selon ta version)
root@pve01:~# qm guest exec 1005 -- ssh-keygen -lf /etc/ssh/ssh_user_ca.pub
256 SHA256:9fX… CA SSH MédiSphère (redéploiement) (ED25519)
```

L'empreinte ne correspond pas au `Signing CA` de ton certificat : le fichier contient la clé de la CA **d'hôte** (celle de `@cert-authority` dans ton `known_hosts`). Confusion classique : step-ca a deux clés SSH (`step ssh config --roots` pour les utilisateurs, `--host --roots` pour les hôtes). Correctif : le rôle `ssh_ca_utilisateur` redépose la bonne clé ; recharge `sshd`. Et la question de Sophie : une CA d'hôte acceptée pour les utilisateurs signifierait que **toute clé d'hôte signée** permettrait de se connecter en tant qu'utilisateur… si quelqu'un savait fabriquer un certificat d'utilisateur avec elle. Deux clés, deux rôles, jamais mélangées.

**Variante 2 — principal absent.**

```
… sshd[2214]: error: Certificate does not contain an authorized principal
root@pve01:~# qm guest exec 1005 -- cat /etc/ssh/auth_principals/admin
Admin
```

Les principaux sont comparés de façon **exacte** (casse comprise). `Admin` n'est pas `admin`. Correctif par le rôle (le fichier est un modèle du rôle), et un test Molecule qui se connecte avec un certificat.

**Variante 3 — algorithmes de certificats exclus.**

```
root@pve01:~# qm guest exec 1005 -- sshd -T | grep pubkeyacceptedalgorithms
pubkeyacceptedalgorithms ssh-ed25519,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256
root@pve01:~# qm guest exec 1005 -- cat /etc/ssh/sshd_config.d/00-anssi.conf
```

Le certificat se présente avec l'algorithme `ssh-ed25519-cert-v01@openssh.com` : absent de la liste, il n'est même pas examiné (le client affiche `no mutual signature algorithm`). Le fichier `00-anssi.conf`, lu avant `01-ssh-durci.conf`, impose sa valeur (première valeur lue). Un durcissement recopié d'un guide qui ne prévoyait pas de certificats. Correctif : supprimer ce fichier non géré, et si un durcissement des algorithmes est voulu, l'écrire **dans le rôle `ssh_durci`** en incluant `ssh-ed25519-cert-v01@openssh.com` (et `ecdsa-sha2-nistp256-cert-v01@openssh.com` si besoin). Prévention : le rôle `ssh_durci` refuse (ou signale) tout fichier de `sshd_config.d/` qu'il ne gère pas.

**Variante 4 — clé révoquée.**

```
… sshd[2214]: error: Authentication key ED25519-CERT SHA256:… revoked by file /etc/ssh/revoked_keys
root@pve01:~# qm guest exec 1005 -- ssh-keygen -Qf /etc/ssh/revoked_keys /tmp/admin.pub
/tmp/admin.pub (admin@adm01): REVOKED
```

(Copie d'abord ta clé publique dans la VM par l'agent, par exemple avec `qm guest exec 1005 -- tee /tmp/admin.pub` et `--pass-stdin 1`.) La liste de révocation (KRL) contient **ta** clé : révoquer une clé révoque aussi tous les certificats portant cette clé. Quelqu'un a révoqué la mauvaise clé lors de la perte du portable de Lucas. Correctif : régénérer la KRL avec la bonne liste (c'est la source de la révocation, M06-E27, qui doit la produire), la déployer par le rôle, recharger ; et vérifier que la clé de Lucas est bien révoquée, elle.

**Pourquoi tu n'as pas eu besoin de la clé de bris de glace** : l'agent QEMU donne un accès root sans réseau ni authentification SSH, tant que `pve01` est joignable. La clé de `secours` sert quand l'agent n'est pas là (VM sans agent, `pve01` inaccessible, console seulement). Si tu l'as utilisée, le journal doit dire pourquoi l'agent ne suffisait pas.

**Vérification** : `lab/bin/check 06 38`, puis `lab/bin/break 06 38 --annuler`.

**Explications**

Pour une authentification par certificat d'utilisateur, `sshd` vérifie l'algorithme (`PubkeyAcceptedAlgorithms`), la signature de la CA (`TrustedUserCAKeys`), la validité, la révocation (`RevokedKeys`, qui peut viser la clé, le numéro de série ou l'identifiant du certificat), puis les principaux : si `AuthorizedPrincipalsFile` est défini, l'un des principaux du certificat doit y figurer ; sinon, le nom de l'utilisateur doit être l'un des principaux. Le fichier `authorized_keys` n'intervient pas (sauf lignes `cert-authority`).

**Alternatives**
- Principaux par rôle (`astreinte`, `plateforme`) plutôt que par compte : un certificat ouvre plusieurs comptes selon le rôle de la personne.
- `AuthorizedPrincipalsCommand` (principaux calculés depuis un annuaire, M24).

**Pièges classiques**
- Tester en profitant d'une connexion multiplexée encore ouverte.
- Se rabattre sur la clé de bris de glace dès le premier refus.
- Corriger sur l'hôte sans corriger le rôle : la panne revient (ou la correction disparaît) au prochain passage.

**En production chez MédiSphère**
Test de connexion **par certificat seul** dans la supervision et dans Molecule ; aucun fichier de `sshd_config.d/` hors du code ; KRL produite par la PKI et distribuée par Ansible ; journal `VERBOSE` permanent sur les bastions (il trace l'empreinte et l'identifiant de chaque certificat utilisé : exigence HDS de traçabilité).

---

### M06-E39 — Panne : NetBox en erreur

**Démarche de diagnostic**

*Symptôme* : page d'erreur sur l'interface et l'API.

**Étape 1 — Le code HTTP.**

```
admin@adm01:~$ for p in / /api/status/; do curl -s -o /dev/null -w "%{http_code} $p\n" https://nbx01.par1.medisphere.internal$p; done
```

`502` : nginx n'a pas de réponse de gunicorn (gunicorn arrêté ou n'écoute pas où nginx l'attend). `400` : Django refuse la requête (souvent `ALLOWED_HOSTS`). `500` : Django a levé une exception (base, cache, configuration).

**Étape 2 — Couche par couche sur `nbx01`.**

```
admin@nbx01:~$ curl -sI http://127.0.0.1:8001/ | head -n 1
admin@nbx01:~$ sudo ss -ltnp | grep -E ':80(01|02)|:6379|:6380|:5432'
admin@nbx01:~$ sudo journalctl -u netbox -n 40 --no-pager | tail -n 15
admin@nbx01:~$ sudo find /etc /opt/netbox -newer /opt/netbox/netbox/netbox/settings.py -type f 2>/dev/null | head
```

**Variante 1 — PostgreSQL refuse la base de NetBox (500).**

```
… django.db.utils.OperationalError: connection failed: … FATAL:  pg_hba.conf rejects connection for host "127.0.0.1", user "netbox", database "netbox", no encryption
admin@nbx01:~$ sudo head -n 5 /etc/postgresql/17/main/pg_hba.conf
# Durcissement InfoGér (audit 2026) : accès direct à la base netbox interdit
local   netbox   all   reject
host    netbox   all   127.0.0.1/32   reject
```

`pg_hba.conf` est lu de haut en bas, la **première** ligne qui correspond s'applique : les lignes `reject` en tête interdisent tout accès à la base, y compris celui de NetBox (et du `pg_dump` des sauvegardes de M06-E28). Correctif : retirer ces lignes (le rôle `netbox` gère `pg_hba.conf` : `--check --diff` les montre), `systemctl reload postgresql`, puis `systemctl restart netbox netbox-rq` (les connexions persistantes, `CONN_MAX_AGE`, ont été cassées). Si l'audit voulait restreindre l'accès, la bonne règle est `scram-sha-256` pour l'utilisateur `netbox` depuis `127.0.0.1` uniquement, pas un rejet.

**Variante 2 — Valkey n'écoute plus sur le port attendu (500).**

```
… redis.exceptions.ConnectionError: Error 111 connecting to localhost:6379. Connection refused.
admin@nbx01:~$ sudo ss -ltnp | grep valkey
LISTEN 0 511 127.0.0.1:6380 … valkey-server
admin@nbx01:~$ grep -n '^port' /etc/valkey/valkey.conf
```

NetBox utilise Valkey (compatible Redis) pour le cache et les files de tâches (`REDIS` dans `configuration.py`). Port changé d'un côté seulement. Correctif : rétablir `port 6379` par le rôle (ou, si le changement était voulu, changer les deux côtés dans le même changement), redémarrer `valkey-server`, puis `netbox` et `netbox-rq`. `/api/status/` montre ensuite `rq-workers-running` ≥ 1.

**Variante 3 — `ALLOWED_HOSTS` réduit (400).**

```
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://nbx01.par1.medisphere.internal/
400
admin@nbx01:~$ grep -n ALLOWED_HOSTS /opt/netbox/netbox/netbox/configuration.py
12:ALLOWED_HOSTS = ['nbx01']  # INC-3345 : nom court seulement, demandé par l'audit
```

Django compare l'en-tête `Host` de chaque requête à `ALLOWED_HOSTS` et répond `400 Bad Request` en cas de désaccord (protection contre l'empoisonnement d'en-tête *Host*). Les clients utilisent le FQDN. Correctif : `ALLOWED_HOSTS = ['nbx01.par1.medisphere.internal']` (et rien d'autre : ni `'*'`, ni l'adresse IP si personne ne l'utilise), par le rôle, redémarrage de `netbox`.

**Variante 4 — gunicorn sur un autre port (502).**

```
admin@nbx01:~$ curl -sI http://127.0.0.1:8001/ | head -n 1
curl: (7) Failed to connect to 127.0.0.1 port 8001 …
admin@nbx01:~$ grep -n '^bind' /opt/netbox/gunicorn.py
bind = '127.0.0.1:8002'
admin@nbx01:~$ sudo nginx -T 2>/dev/null | grep proxy_pass
        proxy_pass http://127.0.0.1:8001;
```

nginx et gunicorn ne parlent plus du même port. Correctif : un seul des deux fichiers est faux (celui qui diffère du rôle) ; le rôle gère les deux à partir d'**une** variable, ce qui rend cette incohérence impossible par le code.

**Vérification** : `lab/bin/check 06 39`, la synchronisation Proxmox → NetBox (`medictl netbox sync --dry-run`) et l'inventaire NetBox fonctionnent ; puis `lab/bin/break 06 39 --annuler`.

**Explications**

NetBox est une application Django derrière gunicorn (serveur WSGI, processus Python) et nginx (TLS, fichiers statiques, mandataire). Chaque couche a son mode d'échec et son code : nginx sans amont → 502 ; Django qui refuse → 400/403 ; Django qui plante → 500 et une pile d'appel dans le journal de `netbox`. Le journal de la couche **au-dessus** de celle qui casse dit toujours laquelle appeler ensuite.

**Pièges classiques**
- Redémarrer nginx sur un 502 : nginx va bien.
- Mettre `ALLOWED_HOSTS = ['*']` « pour débloquer ».
- Corriger à la main sans faire converger le rôle : le prochain passage remet la panne… ou la détection de dérive alerte sur ta correction.

**En production chez MédiSphère**
Sonde `/api/status/` (code, version, workers RQ) ; un *handler* du rôle `netbox` qui vérifie le service après chaque redémarrage ; les changements d'InfoGér passent par MR comme les autres.

---

### M06-E40 — Panne : l'inventaire NetBox ne renvoie plus d'hôtes

**Démarche de diagnostic**

*Symptôme* : le garde-fou de `site.yml` (M04-E39) arrête le contrôle de dérive : groupe `socle` vide avec l'inventaire NetBox.

*Hypothèses* : configuration de l'inventaire (fichier du dépôt modifié) ; données de NetBox (étiquette, statut, rattachement) ; droits du jeton ; NetBox injoignable (ce serait une erreur, pas un inventaire vide).

**Étape 1 — Ce que fait le plugin.**

```
admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/netbox.yml --graph
@all:
  |--@ungrouped:
admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/netbox.yml --graph -vvv 2>&1 | grep -E 'Fetching|https://' | head
admin@adm01:~/src/ansible$ git status --short
```

(Remplace `netbox.yml` par le nom de ton fichier d'inventaire NetBox.)

**Étape 2 — Rejouer les requêtes à la main.**

```
admin@adm01:~$ T=$(cat ~/.config/workbook/netbox-checks.token)
admin@adm01:~$ curl -s -H "Authorization: Bearer $T" "https://nbx01.par1.medisphere.internal/api/virtualization/virtual-machines/?tag=socle&limit=0" | jq '.count'
admin@adm01:~$ curl -s -H "Authorization: Bearer $T" "https://nbx01.par1.medisphere.internal/api/virtualization/virtual-machines/?limit=0" \
  | jq -r '.results[] | [.name, .status.value, ([.tags[].slug] | join(","))] | @tsv'
```

**Variante 1 — étiquette renommée.** La seconde requête montre les VMs, mais avec l'étiquette `socle-par1` ; la première renvoie 0. Le journal des modifications (`/api/core/object-changes/?changed_object_type=extras.tag`) dit qui a renommé l'étiquette et quand. Tous les regroupements (`group_by: [tags]`) et filtres (`query_filters: [tag: socle]`) qui s'appuient sur le **slug** sont tombés d'un coup. Correctif : rétablir le slug `socle` dans NetBox ; si le besoin (distinguer PAR1 et PAR2) est réel, il se traite par le **site** (`group_by: [sites]`), pas en renommant une étiquette consommée par le code. Prévention : l'ADR-0060 déclare les étiquettes `socle` et `role-*` comme un **contrat** (création et renommage par MR uniquement, en code : script ou OpenTofu).

**Variante 2 — statut des VMs changé.** Les VMs sont là, avec l'étiquette, mais au statut `planned` ; l'inventaire filtre `status: active`. Le journal des modifications montre une modification en masse par le compte d'automatisation, juste après une exécution de la synchronisation : le script a été lancé avec un mauvais statut (ou a mal traduit l'état Proxmox). Correctif : remettre `active` (ou relancer la synchronisation corrigée) et ajouter au script un garde-fou : refuser de changer le statut de plus de N objets d'un coup sans `--force`. Si ton inventaire ne filtre pas sur le statut, cette variante n'a pas d'effet : demande-toi alors s'il **devrait** filtrer (une VM `decommissioning` doit-elle encore recevoir `site.yml` ?).

**Variante 3 — configuration de l'inventaire.** `git status` montre le fichier d'inventaire modifié : `virtual_machines: false` (exemple recopié d'un inventaire d'équipements physiques). Le plugin n'interroge plus du tout `/api/virtualization/virtual-machines/`. Correctif : `git restore` (ou `git diff` pour voir qui l'a écrit et pourquoi), et ajouter au pipeline une vérification « groupe `socle` des deux inventaires identique ».

**Vérification** : `lab/bin/check 06 40`, puis le contrôle de dérive (pipeline planifié lancé à la main) ; `lab/bin/break 06 40 --annuler`.

**Explications**

Le plugin `nb_inventory` interroge l'API (équipements et/ou machines virtuelles selon `devices` et `virtual_machines`), applique `query_filters` côté NetBox, puis construit les groupes (`group_by`, `keyed_groups`) et les variables (`compose`) côté Ansible. Un filtre qui ne correspond plus à rien n'est pas une erreur : c'est une liste vide, valide. D'où l'importance du garde-fou de M04-E39, qui transforme « rien à faire » en échec explicite.

**Pièges classiques**
- Désactiver le garde-fou pour faire passer le pipeline.
- Corriger la donnée sans corriger le script qui l'a produite.
- Confondre nom et slug d'une étiquette.

**En production chez MédiSphère**
Les étiquettes et statuts consommés par l'automatisation sont des données protégées (droits NetBox restreints, journal surveillé) ; la CI compare les inventaires ; la synchronisation a un mode `--dry-run` obligatoire en MR et des limites de volume.

---

### M06-E41 — Panne : SERVFAIL sur la zone signée

**Démarche de diagnostic**

*Symptôme* : `SERVFAIL` sur tous les noms de la zone interne via `dns01` ; Internet fonctionne.

**Étape 1 — Validation ou données ?**

```
admin@adm01:~$ dig @10.10.20.10 git01.par1.medisphere.internal +short
admin@adm01:~$ dig @10.10.20.10 git01.par1.medisphere.internal +cd +short
10.10.20.12
```

Avec `+cd` (*checking disabled*), la réponse arrive : les données sont là, c'est la **validation** qui échoue (réponse *bogus*). Active la journalisation des échecs :

```
admin@dns01:~$ sudo rec_control set-dnssec-log-bogus yes      # ou dnssec.log_bogus: true dans recursor.yml puis rechargement
admin@dns01:~$ dig @127.0.0.1 git01.par1.medisphere.internal >/dev/null; sudo journalctl -u pdns-recursor -n 10 --no-pager
```

**Étape 2 — La chaîne de confiance, maillon par maillon.**

```
admin@dns01:~$ dig @127.0.0.1 -p 5300 +dnssec +multi par1.medisphere.internal DNSKEY
admin@dns01:~$ sudo -u pdns pdnsutil zone show par1.medisphere.internal
admin@dns01:~$ sudo -u pdns pdnsutil zone export-ds par1.medisphere.internal
admin@dns01:~$ sudo rec_control get-tas
admin@dns01:~$ sudo -u pdns pdnsutil metadata get par1.medisphere.internal
```

**Variante 1 — ancre de confiance erronée.**

```
admin@dns01:~$ sudo rec_control get-tas
Configured Trust Anchors:
.          20326 8 2 e06d44b8…
par1.medisphere.internal.  31337 13 2 5c2e…9a40
admin@dns01:~$ sudo -u pdns pdnsutil zone export-ds par1.medisphere.internal | grep ' 2 '
par1.medisphere.internal. IN DS 31337 13 2 5c2e…9a4f ; ( SHA256 digest )
```

Même étiquette (31337), même algorithme, empreinte différente au dernier caractère : l'ancre a été recopiée à la main. Le récurseur ne trouve aucun DNSKEY dont le DS corresponde à l'ancre : toute la zone est *bogus*. Correctif : l'ancre est produite par le code (le rôle `powerdns_recursor` lit `pdnsutil zone export-ds` ou une variable alimentée par lui), jamais recopiée ; application du rôle, redémarrage du récurseur (ou `rec_control reload-yaml`, qui recharge les ancres depuis la 5.2).

**Variante 2 — zone passée en *presigned* sur le primaire.**

```
admin@dns01:~$ sudo -u pdns pdnsutil metadata get par1.medisphere.internal
PRESIGNED = 1
…
admin@dns01:~$ dig @127.0.0.1 -p 5300 +dnssec par1.medisphere.internal DNSKEY +short
(rien)
```

Avec `PRESIGNED`, PowerDNS ne signe plus à la volée : il sert les RRSIG et DNSKEY **stockés** dans la base… qu'une zone signée en direct n'a pas. Pour un récurseur qui a une ancre, une zone qui ne présente aucune DNSKEY est *bogus*. La commande était destinée au **secondaire** (qui stocke les signatures reçues par AXFR). Correctif : `sudo -u pdns pdnsutil zone unset-presigned par1.medisphere.internal`, `pdnsutil zone increase-serial` (pour que `dns02` reprenne la zone signée par IXFR/AXFR), puis vider le cache des récurseurs pour la zone (`rec_control wipe-cache 'par1.medisphere.internal$'`). Aucune clé n'a été touchée.

**Variante 3 — roulement de KSK raté.**

```
admin@dns01:~$ sudo -u pdns pdnsutil zone show par1.medisphere.internal | grep ^ID
ID = 1 (CSK), flags = 257, tag = 31337, algo = 13, bits = 256	Inactive	Published	( ECDSAP256SHA256 )
ID = 2 (KSK), flags = 257, tag = 50212, algo = 13, bits = 256	Active	Published	( ECDSAP256SHA256 )
```

Une nouvelle clé (tag 50212) signe la zone, l'ancienne (31337) est désactivée ; l'ancre du récurseur désigne toujours 31337. Plus rien ne relie l'ancre aux signatures. Deux stratégies :

1. **Revenir en arrière** : exporter **d'abord** toutes les clés (`pdnsutil zone export-key par1.medisphere.internal 1 > ~/cles-zone/1.private` et idem pour 2, fichiers 600 hors dépôt), réactiver 31337 (`pdnsutil zone activate-key … 1`), garder 50212 publiée mais inactive pour le futur roulement, ou la retirer (`remove-key`) après export. Service rétabli immédiatement.
2. **Terminer le roulement** : ajouter le DS de 50212 aux ancres des **deux** récurseurs (les deux DS côte à côte pendant la transition), attendre l'expiration des TTL du DNSKEY, puis retirer 31337. Possible, mais plus long et le service reste coupé tant que les récurseurs n'ont pas la nouvelle ancre.

En incident, la stratégie 1 rétablit le service ; le roulement se refait ensuite proprement. La procédure correcte (pré-publication) : publier la nouvelle clé **inactive** (ou active en double signature), ajouter son DS à l'ancre de tous les validateurs, attendre au moins le TTL du DNSKEY + la propagation, basculer la signature, attendre, retirer l'ancienne clé, puis l'ancien DS. Le roulement raté a sauté l'étape « ajouter le DS à l'ancre ».

**Étape 3 — Validateur indépendant.**

```
admin@adm01:~$ ssh dns01 sudo -u pdns pdnsutil zone export-ds par1.medisphere.internal | awk '$3 == "DS" && $6 == 2 { printf "trust-anchors {\n  %s initial-ds %s %s %s \"%s\";\n};\n", $1, $4, $5, $6, $7 }' > /tmp/ancre.conf   # à adapter au format exact
admin@adm01:~$ delv @10.10.20.10 -a /tmp/ancre.conf git01.par1.medisphere.internal A +root=par1.medisphere.internal
; fully validated
```

(Avec `delv`, la zone interne étant sans parent signé, on fournit l'ancre de la zone elle-même ; vérifie les options `-a` et `+root` dans `man delv` de ta version.)

**Vérification** : drapeau `ad` sur `dns01` **et** `dns02`, `lab/bin/check 06 41`, puis `lab/bin/break 06 41 --annuler`.

**Explications**

Un validateur part d'une ancre (un DS ou un DNSKEY de confiance), vérifie que l'ensemble DNSKEY de la zone est signé par une clé correspondant à l'ancre, puis que chaque réponse est signée (RRSIG) par une clé de cet ensemble, et que les absences sont prouvées (NSEC/NSEC3). Un seul maillon faux rend la zone *bogus* : le récurseur répond `SERVFAIL` plutôt que de donner une réponse non vérifiée. C'est le but : une validation qui « laisse passer en cas de doute » ne protège de rien.

**Pièges classiques**
- Désactiver la validation (`process` ou NTA permanente) pour rétablir le service, et oublier de la remettre.
- Supprimer une clé sans l'avoir exportée : le retour arrière devient impossible.
- Oublier le récurseur de `dns02`, ou le secondaire qui sert encore l'ancienne zone (série non incrémentée).

**En production chez MédiSphère**
Roulements par playbook avec contrôles à chaque étape ; ancre générée depuis la zone par le code ; sonde DNSSEC (drapeau `ad` sur chaque récurseur, cohérence ancre ↔ DS) ; NTA réservée à l'incident, avec date de fin.

---

### M06-E42 — Panne : les baux n'apparaissent plus dans le DNS

**Démarche de diagnostic**

*Symptôme* : bail accordé, nom absent du DNS (direct et inverse) pour les nouveaux baux.

**Étape 1 — Chaque maillon.**

```
admin@dns01:~$ sudo grep sbx /var/lib/kea/kea-leases4.csv | tail -n 3
admin@dns01:~$ sudo journalctl -u isc-kea-dhcp4-server --since -30min --no-pager | grep -E 'DDNS|NCR' | tail
admin@dns01:~$ sudo journalctl -u isc-kea-dhcp-ddns-server --since -30min --no-pager | tail
admin@dns01:~$ sudo journalctl -u pdns --since -30min --no-pager | grep -i update | tail
```

**Étape 2 — Rejouer la mise à jour à la main** (clé dans un fichier 600 au format TSIG de BIND, jamais en ligne de commande) :

```
admin@dns01:~$ cat > /tmp/sonde.nsupdate <<'EOF'
server 127.0.0.1 5300
zone par1.medisphere.internal
update add test-ddns.par1.medisphere.internal 60 TXT "essai"
send
update delete test-ddns.par1.medisphere.internal TXT
send
EOF
admin@dns01:~$ sudo sh -c 'umask 077; printf "key \"ddns-kea\" { algorithm hmac-sha256; secret \"%s\"; };\n" "$(cat /etc/kea/tsig-ddns-kea.secret)" > /root/ddns-kea.key'
admin@dns01:~$ sudo nsupdate -k /root/ddns-kea.key -d /tmp/sonde.nsupdate 2>&1 | grep -E 'status|rcode|TSIG'
admin@dns01:~$ sudo rm -f /root/ddns-kea.key
```

(Le secret est lu dans le fichier `secret-file` de `kea-dhcp-ddns` — `/etc/kea/tsig-ddns-kea.secret` avec le rôle `kea_ddns` de M06-E17 — et le fichier de clé au format BIND n'existe que le temps de l'essai, en 600. Adapte l'algorithme à celui de ta configuration.)

**Variante 1 — secret différent des deux côtés.** `kea-dhcp-ddns` journalise une réponse refusée du serveur ; `nsupdate` avec le secret de Kea reçoit un refus et `pdns` journalise un échec de vérification TSIG pour la clé `ddns-kea`. Comparer les secrets **sans les afficher** :

```
admin@dns01:~$ sudo -u pdns pdnsutil tsigkey list | awk '$1 ~ /^ddns-kea/ { printf "%s", $NF }' | sha256sum
admin@dns01:~$ sudo cat /etc/kea/tsig-ddns-kea.secret | tr -d '\n' | sha256sum
```

Empreintes différentes : la « rotation » n'a été faite que côté Kea. Correctif : décider quel secret fait foi (en général : en générer un nouveau), le mettre des **deux** côtés par le code (Vault `critique`, rôles `kea_ddns` et `powerdns_auth`), redémarrer `kea-dhcp-ddns`.

**Variante 2 — `dnsupdate=no`.** `nsupdate` reçoit `REFUSED`, le journal de `pdns` indique que les mises à jour sont désactivées. `grep -rn dnsupdate /etc/powerdns/` montre la modification. Correctif par le rôle `powerdns_auth`, redémarrage de `pdns`.

**Variante 3 — clé autorisée sur la zone inexistante.**

```
admin@dns01:~$ sudo -u pdns pdnsutil metadata get par1.medisphere.internal TSIG-ALLOW-DNSUPDATE
TSIG-ALLOW-DNSUPDATE = ddns-kea-2026
admin@dns01:~$ sudo -u pdns pdnsutil tsigkey list
ddns-kea. hmac-sha256. ****
```

La zone exige désormais une clé qui n'existe pas : toute mise à jour (même correctement signée par `ddns-kea`) est refusée. Rotation préparée sur la zone, jamais terminée. Correctif : `sudo -u pdns pdnsutil metadata set par1.medisphere.internal TSIG-ALLOW-DNSUPDATE ddns-kea` (pendant une rotation, la métadonnée peut lister **les deux** clés : `metadata add`), par le rôle.

**Variante 4 — Kea n'envoie plus rien.** `nsupdate` fonctionne ; `kea-dhcp-ddns` ne reçoit rien ; le journal de `kea-dhcp4` ne mentionne plus de NCR.

```
admin@dns01:~$ sudo grep -n '"enable-updates"' /etc/kea/kea-dhcp4.conf
"enable-updates": false
```

`dhcp-ddns.enable-updates` contrôle la connexion de `kea-dhcp4` à D2 ; `ddns-send-updates` (vrai par défaut) contrôle l'envoi par portée. Les deux doivent être vrais (manuel de Kea, tableau « Enabling and disabling DDNS updates »). Correctif par le rôle `kea_dhcp4`, sur `dns01` **et** `dns02`.

**Rattraper les baux accordés pendant la panne.** Options : attendre leur renouvellement (avec `ddns-update-on-renew: false`, le renouvellement ne republie pas le nom s'il n'a pas changé : les noms resteraient absents jusqu'à un nouveau bail) ; forcer un nouveau bail côté client (`networkctl renew` ou redémarrage de la VM) ; ou republier depuis l'API de Kea (commande `lease4-resend-ddns` du hook `lease_cmds`, chargé depuis M06-E25 : une commande par bail, par le socket de contrôle). La dernière est la seule qui n'impose rien aux clients.

**Vérification** : un bail neuf apparaît dans le DNS direct et inverse ; `lab/bin/check 06 42` ; `lab/bin/break 06 42 --annuler`.

**Explications**

RFC 2136 définit la mise à jour dynamique (prérequis, ajouts, suppressions) ; RFC 8945 la signature TSIG (HMAC sur le message, l'heure et le nom de la clé, avec une tolérance d'horloge `fudge`, 300 s par défaut). Côté PowerDNS : `dnsupdate=yes` active le mécanisme ; l'adresse source doit être autorisée (réglage global `allow-dnsupdate-from`, 127.0.0.0/8 par défaut, ou métadonnée `ALLOW-DNSUPDATE-FROM`) ; si la zone a une métadonnée `TSIG-ALLOW-DNSUPDATE`, la mise à jour doit **en plus** être signée par l'une de ces clés.

**Pièges classiques**
- Afficher le secret pour le comparer (historique du shell, ticket, journal).
- Tourner une clé d'un seul côté.
- Corriger sur `dns01` en oubliant `dns02` (le serveur de secours en cas de bascule HA).

**En production chez MédiSphère**
Rotation TSIG par playbook (deux clés autorisées pendant la transition) ; sonde « bail actif ↔ nom publié » ; alertes sur les compteurs d'erreurs de `kea-dhcp-ddns` (`statistic-get-all`).

---

### M06-E43 — Astreinte : les services socle en panne

**Démarche**

1. **Triage** : lister les symptômes affichés, puis vérifier les instruments dans l'ordre des dépendances : SSH par IP vers chaque hôte (`for h in dns01 dns02 ca01 nbx01 git01 runner01; do ssh -o ControlPath=none $h true && echo $h ok; done`), agent QEMU, `dig @10.10.20.10` et `@10.10.20.16` explicites, `curl` vers `ca01`, `nbx01`, `git01`. Puis lancer `lab/bin/check 06 35` à `06 42` pour la carte.
2. **Priorisation** par dépendances : réseau → DNS (E35, E41) → temps et PKI (E37) → accès (E38) → DHCP (E36, E42) → NetBox (E39) → consommateurs (E40). Exemple : avec E37 (chaîne de `nbx01`) et E40 (étiquette), l'inventaire NetBox échoue d'abord sur TLS ; tant que E37 n'est pas réparée, impossible de voir E40. Avec E39 et E40, NetBox en 500 masque le renommage d'étiquette.
3. **Communication** (modèle) : « 07 h 25 — INC-3350 — Statut : en cours. Impact : la CI échoue (certificat refusé), l'inventaire NetBox est vide. Cause : deux anomalies distinctes identifiées, correction de la première en cours. Prochaine communication : 07 h 55. »
4. **Post-mortem** : chronologie horodatée (détection, premières hypothèses, fausses pistes, corrections), deux causes racines (et leurs causes contributives : modifications hors du code, absence de sonde), détection (qu'est-ce qui aurait dû alerter avant Nadia ?), actions (responsable, échéance) : par exemple sondes par maillon, vérification « jeu de règles chargé = fichier », test Molecule par certificat SSH, contrat des étiquettes NetBox.

**Grille d'auto-évaluation**
- [ ] Les instruments ont été vérifiés avant le diagnostic (aucune conclusion tirée d'un test qui dépendait d'un service en panne).
- [ ] L'ordre de traitement est justifié par les dépendances.
- [ ] Chaque correction a été suivie d'une reprise de **tous** les tests de départ.
- [ ] Trois communications au moins, avec statut, impact, prochaine étape, prochaine heure.
- [ ] Post-mortem sans coupable, causes racines distinctes des déclencheurs, actions vérifiables.

---

### M06-E44 — Sous le capot : une résolution DNS et une émission ACME pas à pas

**Solution**

Compte rendu de référence : [`fichiers/M06-E44/resolution-et-acme.md`](fichiers/M06-E44/resolution-et-acme.md).

*1. Nom interne.*

```
admin@dns01:~$ sudo rec_control wipe-cache nbx01.par1.medisphere.internal
admin@dns01:~$ sudo rec_control trace-regex 'nbx01\.par1\.medisphere\.internal' - &
admin@dns01:~$ sudo tcpdump -ni lo -vv port 5300 -c 20 &
admin@adm01:~$ dig @10.10.20.10 nbx01.par1.medisphere.internal; dig @10.10.20.10 nbx01.par1.medisphere.internal
admin@dns01:~$ sudo rec_control trace-regex          # arrêt de la trace
```

Lecture attendue : à froid, le récurseur envoie à 127.0.0.1:5300 une question `A?` sans RD (`[1au]`, pas de `+` dans le résumé de `tcpdump`), avec EDNS et le bit DO (`[1au] … ar: . OPT UDPsize=1232 OK`) ; puis, pour valider, `DNSKEY? par1.medisphere.internal.` (à moins que l'ensemble DNSKEY soit déjà en cache) ; la réponse revient avec `aa` et des RRSIG. La trace du récurseur affiche le choix du relais, la réponse, puis l'état de validation (`Secure`). À chaud, plus aucun paquet sur le port 5300 : la réponse sort du cache (le TTL affiché par `dig` a diminué).

*2. Nom d'Internet.* La trace montre la descente : requête vers une racine (`a.root-servers.net`…) pour le TLD, vers les serveurs du TLD pour le domaine, puis vers les serveurs du domaine ; requêtes DS à chaque délégation et DNSKEY de chaque zone pour la validation. Pour un sous-domaine inexistant d'un domaine signé : `NXDOMAIN` accompagné d'enregistrements NSEC ou NSEC3 (et leurs RRSIG) qui prouvent l'absence. `delv @10.10.20.10 <nom>` affiche `; negative response, fully validated`.

*3. Cache négatif.* `dig @10.10.20.10 nexiste-pas.par1.medisphere.internal` deux fois : le TTL de la ligne SOA de la section d'autorité diminue entre les deux. Sa valeur initiale est le minimum du TTL du SOA et du champ *minimum* du SOA (RFC 2308 §5), plafonné par `recordcache.max_negative_ttl` (3600 s par défaut).

*4. ACME à la main.*

```
admin@adm01:~$ curl -s https://ca01.par1.medisphere.internal/acme/acme/directory | jq
{
  "newNonce": "https://ca01.par1.medisphere.internal/acme/acme/new-nonce",
  "newAccount": "https://ca01.par1.medisphere.internal/acme/acme/new-account",
  "newOrder": "https://ca01.par1.medisphere.internal/acme/acme/new-order",
  "revokeCert": "https://ca01.par1.medisphere.internal/acme/acme/revoke-cert",
  "keyChange": "https://ca01.par1.medisphere.internal/acme/acme/key-change"
}
admin@adm01:~$ curl -sI https://ca01.par1.medisphere.internal/acme/acme/new-nonce | grep -i replay-nonce
Replay-Nonce: c0ZzbFBkS3…
```

Chaque requête suivante est un objet JWS (RFC 7515) signé par la clé du compte, qui contient le *nonce* et l'URL : `curl` seul ne sait pas signer.

*5. ACME de bout en bout.*

```
admin@ca01:~$ sudo journalctl -u step-ca -f                     # dans un second terminal
admin@dns02:~$ systemctl is-active cert-renewer@kea.service      # « inactive » : le port 80 est libre
admin@dns02:~$ sudo tcpdump -ni ens18 -A 'tcp port 80 and host 10.10.20.11' -c 20 &
admin@dns02:~$ d=$(sudo mktemp -d) && sudo chmod 700 "$d"
admin@dns02:~$ sudo step ca certificate dns02.par1.medisphere.internal "$d/essai.crt" "$d/essai.key" \
    --provisioner acme --standalone --ca-url https://ca01.par1.medisphere.internal --root /usr/local/share/ca-certificates/medisphere-root-ca.crt
✔ Provisioner: acme (ACME)
Using Standalone Mode HTTP challenge to validate dns02.par1.medisphere.internal .. done!
Waiting for Order to be 'ready' for finalization .. done!
Finalizing Order .. done!
✔ Certificate: …/essai.crt
admin@dns02:~$ sudo step certificate inspect "$d/essai.crt" --short
admin@dns02:~$ sudo rm -rf "$d"
```

Pourquoi `dns02` et pas `ca01` : depuis M06-E27, l'écouteur HTTP de la CRL (`insecureAddress`) occupe le port 80 de `ca01`, et le client autonome ne pourrait pas s'y lier.

Correspondance journal ↔ RFC 8555 : `new-nonce` (§7.2) → `new-account` (§7.3) → `new-order` (§7.4, liste des identifiants) → `authz` (§7.5, une autorisation par nom) → `challenge` (§7.5.1, le client signale qu'il est prêt) → requête de step-ca vers `http://dns02.par1.medisphere.internal/.well-known/acme-challenge/<jeton>` (visible dans la capture sur `dns02`, réponse = jeton + empreinte de la clé du compte, §8.3) → `finalize` (§7.4, CSR) → `certificate` (téléchargement de la chaîne). Le certificat : la durée par défaut du provisioner `acme` (`defaultTLSCertDuration`, 30 jours depuis M06-E27), SAN `dns02.par1.medisphere.internal`, émetteur « MédiSphère Intermediate CA », EKU `serverAuth, clientAuth`.

**Réponses aux questions d'analyse**

1. Une zone de `forward_zones` est traitée comme si les relais faisaient autorité : le récurseur leur pose des questions **non récursives** (RD=0) et attend des réponses `aa`. Avec `forward_zones_recurse`, il envoie RD=1 : les relais doivent être des récurseurs (cas d'un relais vers un autre résolveur, pas vers un autoritaire).
2. De l'ancre locale `dnssec.trustanchors` (DS de la zone), qui joue le rôle du DS absent du parent. Sans ancre, la zone n'a pas de chaîne depuis la racine, et la racine **prouve** que `internal.` n'existe pas ; un nom relayé serait-il alors *bogus* ou *insecure* ? Le récurseur cherche une preuve de non-sécurité pour la zone ; la seule réponse signée qu'il peut obtenir est celle de la racine, qui contredit l'existence du nom : le résultat est un échec de validation. C'est pourquoi il faut soit une ancre, soit une NTA pour la zone interne.
3. À froid, de l'ordre de 6 à 12 requêtes (selon ce qui est déjà en cache : NS et DNSKEY de la racine, du TLD…) ; à chaud, 0 vers l'extérieur. L'*aggressive NSEC caching* (RFC 8198) permet au récurseur de répondre `NXDOMAIN` lui-même pour tout nom couvert par un NSEC/NSEC3 déjà validé en cache, sans reposer la question.
4. Le *nonce* empêche le rejeu d'une requête signée interceptée (§6.5). La signature JWS lie chaque requête à la clé du compte : seule la personne qui détient cette clé peut commander, finaliser ou révoquer pour ce compte, et la réponse au défi contient l'empreinte de cette clé (un tiers ne peut pas valider pour toi).
5. Le serveur ACME (step-ca) se connecte au port 80 de l'adresse obtenue en **résolvant le nom demandé** : le défi prouve que le demandeur contrôle ce que le DNS désigne pour ce nom. Pour un service sans HTTP : `tls-alpn-01` (port 443, extension ALPN `acme-tls/1`) ou `dns-01` ; pour un nom générique : seulement `dns-01` (un TXT `_acme-challenge.<nom>`), qui suppose de pouvoir écrire dans la zone (RFC 2136 ou API PowerDNS).
6. Un certificat de 30 jours n'est exploitable par un voleur de clé que jusqu'à son expiration : la fenêtre est courte et le renouvellement automatique remplace la révocation dans la plupart des cas. step-ca permet la révocation dite passive (le renouvellement est refusé pour un certificat révoqué, sans liste publiée) ; CRL et OCSP sont disponibles selon la version et la configuration (à vérifier dans la documentation de ta version), mais beaucoup de clients ne les consultent pas.
7. Exemples : la trace du récurseur aurait localisé E35 v1/v2 (relais vers 5301, ou question partie vers la racine) et E41 (ligne de validation `Bogus` avec la raison) ; le journal de step-ca et la capture du port 80 auraient localisé un défi `http-01` qui échoue (DNS, port 80 filtré, mauvais hôte), cause fréquente de certificats non renouvelés avant une panne de type E37.

**Pièges classiques**
- Laisser `trace-regex` actif : le fichier de trace grossit à chaque requête correspondante.
- Lancer le client ACME autonome sur un hôte où le port 80 est déjà pris (nginx de `nbx01`) : le défi échoue avec un message trompeur.
- Garder la clé de l'essai.

---

### M06-E45 — Questions expert : DNS, DHCP, PKI

**Réponses**

1. Un autoritaire répond pour les zones qu'il héberge et seulement pour elles (réponses `aa`), sans cache ni récursion ; un récurseur cherche n'importe quel nom pour ses clients, met en cache, valide. Les mêler expose l'autoritaire aux attaques visant les récurseurs (empoisonnement de cache, amplification, saturation par des clients) et fait que les clients voient les données locales **sans** passer par la logique de résolution (une zone mal déléguée « marche » en interne et pas ailleurs). Séparés, chacun a ses ACL, ses ressources et ses mises à jour.
2. **b**. Le SOA de la racine en autorité signifie que c'est la racine qui a répondu `NXDOMAIN` : la question est partie sur Internet, donc la zone n'est plus relayée. a) donnerait le SOA de `par1.medisphere.internal` ; c) donnerait `SERVFAIL` (relais muet) ; d) donnerait `SERVFAIL` (réponse *bogus*), pas `NXDOMAIN`.
3. Mise en cache des réponses `NXDOMAIN` et `NODATA` (RFC 2308) pour une durée égale au minimum du TTL du SOA renvoyé et de son champ *minimum*, plafonnée par le récurseur. Pendant ce temps, le récurseur répond `NXDOMAIN` sans réinterroger : un enregistrement créé après une première question reste invisible jusqu'à expiration ou vidage ciblé.
4. Le secondaire compare le série du SOA du primaire au sien (à l'expiration de `refresh`, ou à réception d'un NOTIFY, RFC 1996) ; s'il est plus grand (arithmétique des numéros de série, RFC 1982), il transfère : IXFR (différences, RFC 1995) ou AXFR (zone complète). Si le série diminue, le secondaire considère sa copie plus récente et ne transfère plus : la zone diverge jusqu'à ce que le série « repasse » au-dessus (ou qu'on force un AXFR / qu'on utilise la technique de l'enroulement du série).
5. TSIG signe le message DNS entier (avec le nom de la clé, l'algorithme, l'heure et la tolérance `fudge`) par HMAC avec un secret partagé. Il protège l'intégrité et authentifie l'émetteur (transferts, mises à jour, NOTIFY) ; il ne chiffre rien et ne protège pas les clients finaux (c'est DNSSEC qui protège les données). L'horloge compte parce que l'heure signée doit être dans la fenêtre `fudge` (300 s par défaut) : c'est la protection contre le rejeu.
6. **b**. Il faut le mécanisme activé (`dnsupdate=yes`), une source autorisée (globale ou par zone) et, si la zone a `TSIG-ALLOW-DNSUPDATE`, une signature valide par l'une de ces clés. a) ne suffit pas si la zone exige une clé (ou si la source n'est pas autorisée) ; c) la clé importée n'autorise rien à elle seule ; d) sans `dnsupdate=yes`, rien n'est accepté.
7. La KSK signe l'ensemble DNSKEY et son empreinte (DS) est publiée chez le parent ; la ZSK signe les données ; une CSK fait les deux (choix par défaut de PowerDNS). Le DS chez le parent prolonge la chaîne de confiance depuis la racine ; une ancre locale la remplace quand le parent n'existe pas ou n'est pas signé. `.internal` n'est pas délégué dans la racine (réservé à l'usage privé) : aucun DS ne peut y être publié, et la racine prouve même son absence.
8. Pré-publication : publier la nouvelle KSK (DNSKEY) ; attendre que l'ancien ensemble DNSKEY ait expiré des caches (TTL) ; publier le nouveau DS chez le parent ou **dans toutes les ancres** ; attendre le TTL du DS ; basculer la signature de l'ensemble DNSKEY ; retirer l'ancien DS, attendre, retirer l'ancienne clé. Dans M06-E41 v3, l'ancienne clé a été désactivée avant que le DS de la nouvelle soit dans les ancres.
9. NSEC chaîne les noms existants en clair : on peut énumérer toute la zone. NSEC3 chaîne des condensés salés des noms : l'énumération demande une attaque par dictionnaire. Des itérations élevées coûtent cher aux validateurs (déni de service) pour un gain faible ; RFC 9276 recommande 0 itération supplémentaire et pas de sel, et les validateurs récents traitent les itérations élevées comme *insecure*.
10. Avec relais : DISCOVER (broadcast du client, relayé en unicast avec `giaddr`), OFFER (du serveur au relais, puis au client), REQUEST (relayé), ACK. Kea choisit le sous-réseau dont le préfixe contient `giaddr` (ou d'après `relay` / classes si configurés). Le `subnet-id` est la clé des baux en base : s'il change (ou est renuméroté automatiquement en réordonnant les sous-réseaux, comme avant), les baux existants ne correspondent plus à leur sous-réseau ; Kea 3 l'exige donc explicitement.
11. *hot-standby* : un serveur sert, l'autre suit (les baux lui sont envoyés) et prend le relais si le premier tombe. *load-balancing* : les deux servent, chacun une moitié des clients (hachage). *passive-backup* : un seul sert, des sauvegardes reçoivent les baux sans jamais servir automatiquement. En coupure entre partenaires, chacun voit l'autre comme défaillant après le délai configuré : en *hot-standby*, le serveur en attente passe en *partner-down* et sert ; si le primaire sert encore des clients que le secondaire voit aussi, la même adresse peut être attribuée deux fois (d'où `max-unacked-clients` et `max-response-delay`, qui exigent la preuve que des clients restent sans réponse).
12. **b**. Depuis Kea 2.7.9 (donc 3.0), les fichiers de baux doivent être dans le dossier de données compilé (`/var/lib/kea` avec les paquets ISC) : la configuration est refusée et le serveur ne démarre pas. a) était le comportement des versions anciennes ; c) et d) ne correspondent à aucune version.
13. Le DHCID (RFC 4701) enregistre une empreinte de l'identité du client à côté de son A/PTR : avant de remplacer ou supprimer un nom, D2 vérifie que c'est bien le même client qui l'avait publié. Sans cela, deux clients qui annoncent le même nom d'hôte s'écraseraient mutuellement. `ddns-conflict-resolution-mode` règle ce comportement (vérification stricte avec DHCID, sans DHCID, ou aucune).
14. La racine ne sert qu'à signer des intermédiaires : hors ligne, sa clé n'est exposée qu'aux cérémonies. L'intermédiaire, en ligne, signe au quotidien ; s'il est compromis, on le révoque et on en émet un nouveau sans changer l'ancre installée partout. `pathlen` limite la profondeur des CA en dessous (`pathlen:0` sur l'intermédiaire : il ne peut pas créer de sous-CA). Compromission de l'intermédiaire : tous les certificats qu'il a émis deviennent suspects ; on révoque l'intermédiaire, on en crée un nouveau et on réémet (ACME rend cette réémission rapide).
15. Le client n'a que les racines : sans intermédiaire présenté, il ne peut pas construire la chaîne. Les navigateurs complètent avec un cache d'intermédiaires déjà vus ou via AIA : la configuration fausse « marche » chez l'administrateur et échoue pour les outils (curl, Python, Go). Piège : on croit le service sain parce que le navigateur l'accepte.
16. `http-01` : port 80 du nom, simple, pas de générique. `dns-01` : enregistrement TXT, aucun port à ouvrir, génériques possibles, mais il faut un accès en écriture à la zone (secret sensible). `tls-alpn-01` : port 443, utile quand seul 443 est ouvert. Pour `s3-01` (8333 seulement) : `dns-01` par l'API PowerDNS ou RFC 2136 (aucun port, pas de serveur HTTP à ajouter), ou `http-01` en ouvrant temporairement 80 depuis `ca01` (flux INFRA → INFRA, rien à ouvrir sur `gw01`) avec le client en mode autonome. Le premier est plus propre si la clé d'écriture DNS est bien cantonnée.
17. Pour : exposition limitée dans le temps, rotation testée en permanence, pas de dépendance aux CRL/OCSP (souvent ignorées par les clients). Contre : dépendance forte à la disponibilité de la CA et du renouvellement (une PKI en panne trois jours casse tout), horloges critiques. CRL et OCSP deviennent secondaires ; la révocation passive (refus de renouveler) suffit dans la plupart des cas.
18. `known_hosts`/`authorized_keys` : une confiance par clé, à distribuer partout et à maintenir. Certificats : une confiance par CA, des identités avec validité, principaux et options, révocables en masse. Les principaux sont les noms que le certificat autorise (comptes ou rôles). `@cert-authority` (CA d'hôte, côté client) et `TrustedUserCAKeys` (CA d'utilisateur, côté serveur) ont des rôles opposés : la même clé permettrait à un hôte compromis de signer… des certificats acceptés pour des utilisateurs, ou l'inverse. Deux clés, deux rôles.
19. **b**. Le certificat est présenté avec l'algorithme `ssh-ed25519-cert-v01@openssh.com` ; s'il n'est pas dans `PubkeyAcceptedAlgorithms`, `sshd` ne l'examine pas (`no mutual signature algorithm` côté client). a) ed25519 est l'algorithme recommandé ; c) la CA peut être de n'importe quel type accepté ; d) les deux directives sont indépendantes.
20. Selon l'ADR-0060 : NetBox fait foi pour l'**intention** (adresse, rôle, statut), Proxmox pour la **réalité d'exécution**. La VM n'existe pas : soit elle doit exister (NetBox dit `active`) et il faut la créer par OpenTofu, soit elle a été détruite hors procédure et NetBox (puis le DNS, généré depuis NetBox) doivent passer à `decommissioning`/`offline` puis être nettoyés. On ne tranche pas seul : on cherche dans le journal des modifications qui l'a retirée et pourquoi. Prévention : création et destruction uniquement par le code (OpenTofu met à jour NetBox), synchronisation qui **signale** les écarts au lieu de les corriger en silence, et DNS généré depuis NetBox (un nom ne survit pas à son objet).

**Grille d'auto-évaluation** : 16/20 au moins avec des réponses argumentées ; reprends les exercices liés à chaque erreur (E35/E41 pour le DNS, E36/E42 pour Kea, E37/E38 pour la PKI).
