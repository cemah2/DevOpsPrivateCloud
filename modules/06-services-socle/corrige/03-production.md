# Module 06 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- format exact des sorties de `pdnsutil` 5.0 (`zone list-all`, `tsigkey list`, `metadata get`, `zone show` : « Zone is not actively secured ») sur lesquelles s'appuient les tâches idempotentes des rôles ; ordre des arguments de `pdnsutil zone add-key` (RB-064) ;
- émission ACME d'un certificat portant une **adresse IP** (`step ca certificate --san <IP>`, défi HTTP-01 sur l'adresse) avec step-ca 0.30 et step 0.31 ; vérification du nom d'hôte par le client HTTPS de Kea ; fichier de certificat contenant feuille + intermédiaire (la documentation de Kea dit ce cas « non pris en charge », voir E25) ;
- utilisateur du service des paquets ISC de Kea (`_kea` dans le corrigé) ;
- interaction, dans le Recursor 5.4, entre l'ancre négative de la zone parente `medisphere.internal` et l'ancre positive de `par1.medisphere.internal` (le drapeau `ad` tranche ; solution de repli décrite en E26) ;
- comportement de step-ca à l'approche de l'expiration de l'intermédiaire (certificats raccourcis ou refusés) ; confinement systemd proposé pour step-ca (`SystemCallFilter`) ;
- noms des variables des rôles et du module `vm-debian` produits aux paliers 1 et 2 : les fichiers de ce corrigé les nomment de façon cohérente entre eux ; si les tiens diffèrent, la logique est la même.

**Rappel des VMID du palier** : 2065 `m06-client` (E25), 2066-2067 instances Molecule à deux nœuds (`powerdns_replication`, `kea_ha`) et à un nœud (`pare_feu_local`, sur 2066), 2068 `m06-restau` (E28), 2069 `stat01` (E34).

---

### M06-E24 — DNS secondaire `dns02` : transferts de zone et TSIG

**Solution**

Fichiers : [`infra/socle/dns02.tf`](fichiers/M06-E24/infra/socle/dns02.tf) ; dans `plateforme/ansible`, inventaire : [`group_vars/role_dns/powerdns_auth.yml`](fichiers/M06-E24/ansible/inventories/lab/group_vars/role_dns/powerdns_auth.yml) (remplace celui de M06-E06), [`group_vars/role_dns/powerdns_recursor.yml`](fichiers/M06-E24/ansible/inventories/lab/group_vars/role_dns/powerdns_recursor.yml), [`host_vars/dns01/powerdns_auth.yml`](fichiers/M06-E24/ansible/inventories/lab/host_vars/dns01/powerdns_auth.yml), [`host_vars/dns02/powerdns_auth.yml`](fichiers/M06-E24/ansible/inventories/lab/host_vars/dns02/powerdns_auth.yml), [`host_vars/dns01/powerdns_recursor.yml`](fichiers/M06-E24/ansible/inventories/lab/host_vars/dns01/powerdns_recursor.yml), [`host_vars/dns02/powerdns_recursor.yml`](fichiers/M06-E24/ansible/inventories/lab/host_vars/dns02/powerdns_recursor.yml), [extrait de `vault-critique.yml`](fichiers/M06-E24/ansible/inventories/lab/group_vars/role_dns/vault-critique.yml.extrait) ; rôle `powerdns_auth` (celui de M06-E06, étendu) : [`defaults/main.yml`](fichiers/M06-E24/ansible/roles/powerdns_auth/defaults/main.yml), [`templates/medisphere.conf.j2`](fichiers/M06-E24/ansible/roles/powerdns_auth/templates/medisphere.conf.j2), [`tasks/main.yml`](fichiers/M06-E24/ansible/roles/powerdns_auth/tasks/main.yml), [`tasks/replication.yml`](fichiers/M06-E24/ansible/roles/powerdns_auth/tasks/replication.yml), [`tasks/verifications.yml`](fichiers/M06-E24/ansible/roles/powerdns_auth/tasks/verifications.yml) ; le rôle `powerdns_recursor` de M06-E07 ne change pas ; [`playbooks/dns01.yml`](fichiers/M06-E24/ansible/playbooks/dns01.yml) ; scénario [`molecule/powerdns_replication/`](fichiers/M06-E24/ansible/molecule/powerdns_replication/) et jobs CI ([extrait](fichiers/M06-E24/ansible/gitlab-ci-molecule-m06.yml)).

*1. Lecture* (réponses attendues dans le journal) :
- Le primaire envoie un NOTIFY quand le numéro de série d'une zone de type *primary* change (vérifié toutes les `xfr-cycle-interval` secondes, 60 par défaut). Destinataires par défaut : **les adresses des serveurs cités dans les NS** de la zone, **sur le port 53**, filtrées par `only-notify` (défaut : tout le monde), plus `also-notify` et la métadonnée `ALSO-NOTIFY`, qui reçoivent toujours.
- Le secondaire qui reçoit un NOTIFY (venant d'une adresse qui est un primaire de la zone) interroge le SOA du primaire et, si le numéro est plus grand, transfère (AXFR, ou IXFR si possible).
- Sans NOTIFY, le secondaire interroge le SOA à chaque intervalle *refresh* du SOA (3 h typiquement), réessaie toutes les *retry* en cas d'échec, et **cesse de servir** la zone après *expire* sans contact.
- `allow-axfr-ips` ne s'applique qu'aux transferts **sans** TSIG : un client qui présente une clé TSIG autorisée transfère depuis n'importe quelle adresse. La clé devient donc la vraie protection ; l'adresse (et le filtrage de E30) sont une défense en profondeur.

*2. L'hôte* (RB-060) : `dns02.tf` appelle le module `vm-debian` v2 de M06-E13 avec une **adresse imposée** (`ipv4_imposee = "10.10.20.16"` : le PLAN fixe l'adresse, on ne prend pas « la première libre ») ; le module enregistre l'intention dans NetBox (VM, interface, adresse, adresse primaire) **avant** de créer la VM (clone complet, ordre de démarrage 2), puis le module `enregistrement-dns` de M06-E14 crée A et PTR (TTL long : hôte permanent). Les NS des zones, eux, restent l'affaire d'Ansible (`powerdns_auth_ns`, point 3). Plan attendu : une douzaine d'ajouts (objets NetBox, VM, enregistrements), **aucune modification** des autres VMs ; si le plan veut modifier une VM importée en M05, arrête-toi (dérive à comprendre avant d'appliquer).

```
admin@adm01:~/src/infra/socle$ tofu plan -out=dns02.plan     # en local pour relire ; l'apply passe par la MR
admin@adm01:~/src/ansible$ uv run ansible-inventory --graph role_dns
@role_dns:
  |--dns01
  |--dns02
admin@adm01:~$ ssh -o ControlPath=none dns02 true    # aucune question d'empreinte : clé d'hôte signée (M06-E19)
```

*3. Le primaire.* Le gabarit [`medisphere.conf.j2`](fichiers/M06-E24/ansible/roles/powerdns_auth/templates/medisphere.conf.j2) (déposé dans `/etc/powerdns/pdns.d/`) produit sur `dns01` :

```
primary=yes
secondary=no
only-notify=
also-notify=10.10.20.16:5300
allow-axfr-ips=127.0.0.0/8
send-signed-notify=yes
```

`only-notify=` vide coupe les NOTIFY automatiques vers les NS : sans lui, `dns01` notifierait 10.10.20.16:53 (le **récurseur** de `dns02`, qui répond `REFUSED`) et 10.10.20.10:53 (son propre récurseur) — sans gravité, mais du bruit dans les journaux et un piège de diagnostic. `also-notify` vise le bon port.

Le type de chaque zone vient de l'inventaire (`type: primary` sur `dns01`, `secondary` sur `dns02`, calculé par la variable d'inventaire `dns_type_zones`) et `zones.yml` (M06-E06) le pose sur le primaire. Depuis M06-E14/E15, `par1`, `par2` et les deux zones inverses sont en `contenu: api` (écrites par OpenTofu, `medictl dns sync` et Kea) : seule la zone parente est encore générée, avec ses NS tirés de `powerdns_auth_ns` (désormais `dns01` **et** `dns02`) ; la zone parente `medisphere.internal` délègue `par1` et `par2` aux deux serveurs, avec la colle. Ensuite, [`replication.yml`](fichiers/M06-E24/ansible/roles/powerdns_auth/tasks/replication.yml) : import de la clé (secret passé par variable d'environnement, `no_log`), association de la clé à chaque zone, NS des zones pilotées par l'API (M06-E14) alignés sur `powerdns_auth_ns`. `pdnsutil` tourne **sous le compte `pdns`** (propriétaire de la base SQLite, comme dans M06-E06) :

```
admin@dns01:~$ sudo -u pdns pdnsutil zone list-all primary
admin@dns01:~$ sudo -u pdns pdnsutil zone list-all native        # une zone ici = jamais transférée en tant que primaire
admin@dns01:~$ sudo -u pdns pdnsutil zone set-kind par2.medisphere.internal primary
admin@dns01:~$ sudo -u pdns pdnsutil tsigkey activate par1.medisphere.internal axfr-par1 primary   # métadonnée TSIG-ALLOW-AXFR
```

Une zone créée par l'API sans champ `kind` est `Native` : elle n'est répliquée que par la base (réplication SQL), jamais par AXFR/NOTIFY. C'est le piège principal de l'exercice : tout « marche » sur `dns01`, rien n'arrive sur `dns02`.

*4. Le secondaire.* Sur `dns02` : `secondary=yes`, pas d'API, zones déclarées et clé associée :

```
admin@dns02:~$ sudo -u pdns pdnsutil zone create-secondary par1.medisphere.internal 10.10.20.10:5300
admin@dns02:~$ sudo -u pdns pdnsutil tsigkey activate par1.medisphere.internal axfr-par1 secondary  # métadonnée AXFR-MASTER-TSIG
admin@dns02:~$ sudo pdns_control retrieve par1.medisphere.internal
```

(Avant la 5.0 : `create-slave-zone`, `activate-tsig-key … slave` ; l'ancienne syntaxe est encore acceptée.) Le récurseur de `dns02` relaie les zones internes vers `127.0.0.1:5300` puis `10.10.20.10:5300` (variable `dns_relais_internes` de `host_vars/dns0X/powerdns_recursor.yml`, reprise par `powerdns_recursor_zones_relayees` dans `group_vars`) : si l'autoritaire local est arrêté, le récurseur interroge celui de l'autre hôte. Le playbook [`dns01.yml`](fichiers/M06-E24/ansible/playbooks/dns01.yml) (nom conservé depuis M06-E16 : il configure tout le groupe `role_dns`) passe `dns01` puis `dns02` (`serial: 1`, `order: sorted`, `any_errors_fatal`).

*5. Molecule* : deux instances (2066 primaire, 2067 secondaire), zone d'essai `essai.molecule.internal`, clé TSIG **de test**. La vérification modifie un enregistrement sur le primaire et attend qu'il arrive sur le secondaire en moins de 30 s (bien moins que le *refresh* du SOA : c'est le NOTIFY qui est prouvé), puis prouve le refus d'un AXFR sans clé et l'acceptation avec. Le scénario surcharge les bornes de VMID et les étiquettes Molecule du commun (2066-2067, `env-m06`) dans son propre `group_vars`.

*6. Preuves* :

```
admin@adm01:~$ for z in par1.medisphere.internal par2.medisphere.internal 10.10.in-addr.arpa 20.10.in-addr.arpa; do …; done
par1.medisphere.internal 2026100714 2026100714
par2.medisphere.internal 2026100302 2026100302
10.10.in-addr.arpa 2026100711 2026100711
20.10.in-addr.arpa 2026100301 2026100301
admin@adm01:~$ dig @10.10.20.10 -p 5300 par1.medisphere.internal AXFR
; Transfer failed.
admin@dns01:~$ sudo journalctl -u pdns --since -5min | grep -Ei 'notif|axfr'
… Queued notification of domain 'par1.medisphere.internal' to 10.10.20.16:5300
… AXFR-out zone 'par1.medisphere.internal', client '10.10.20.16:…', transfer initiated
admin@dns02:~$ sudo journalctl -u pdns --since -5min | grep -Ei 'notif|axfr'
… Received NOTIFY for par1.medisphere.internal from 10.10.20.10:… for which we are secondary
… AXFR-in zone: 'par1.medisphere.internal', primary: '10.10.20.10', zone committed with serial number 2026100715
```

(Libellés indicatifs.) Délai mesuré typique : 1 à 60 s entre l'écriture et le service par `dns02` — le primaire ne regarde les numéros de série qu'à chaque cycle (`xfr-cycle-interval`), sauf écriture par l'API, qui notifie aussitôt. Transfert avec la clé, sans secret sur la ligne de commande :

```
admin@adm01:~$ install -m 600 /dev/null /tmp/axfr.key
admin@adm01:~$ cat > /tmp/axfr.key      # key "axfr-par1" { algorithm hmac-sha256; secret "<SECRET>"; };  puis Ctrl-D
admin@adm01:~$ dig -k /tmp/axfr.key @10.10.20.10 -p 5300 par1.medisphere.internal AXFR | tail -3
admin@adm01:~$ shred -u /tmp/axfr.key
```

*7. Les clients* : variable `resolveurs` du module `vm-debian` (cloud-init des VMs créées par OpenTofu : prise en compte au prochain clonage seulement — pour les VMs existantes, c'est le rôle `base` qui fait foi), variable du rôle `base` qui gère `/etc/resolv.conf` ou systemd-resolved, et `kea_dhcp4_dns: [10.10.20.10, 10.10.20.16]` (option `domain-name-servers`). Dans `pare_feu.yml`, la règle DNS de M00-E13 prend les deux destinations ([extrait](fichiers/M06-E25/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait)), ainsi que la sortie Internet des récurseurs (si tu as choisi la récursion depuis la racine en M06-E07 ; avec des résolveurs amont, idem vers eux).

*8. La panne* :
- PowerDNS Authoritative arrêté sur `dns01` : aucun effet visible ; le récurseur de `dns01` bascule sur `10.10.20.16:5300` (latence de la première requête, le temps que le récurseur marque l'autoritaire local injoignable).
- VM `dns01` arrêtée : avec `glibc` sans option, chaque résolution attend **5 s** (délai par défaut) sur 10.10.20.10 avant d'essayer 10.10.20.16 ; × 2 tentatives par défaut, × A et AAAA : une connexion SSH peut mettre 10 à 20 s à démarrer. Réglage retenu dans le rôle `base` : `options timeout:1 attempts:2` (et pas `rotate`, pour garder `dns01` comme résolveur préféré quand il vit). Avec systemd-resolved, le serveur courant change dès le premier échec et le délai est bien plus court (il se souvient du serveur qui répond).

**Explications**

La réplication DNS standard repose sur trois mécanismes indépendants : **NOTIFY** (le primaire prévient), **SOA** (le secondaire compare les numéros de série) et **AXFR/IXFR** (le transfert lui-même, en TCP). TSIG (RFC 8945) signe chaque message avec un secret partagé (HMAC) et un horodatage : il authentifie l'émetteur et protège l'intégrité, mais ne chiffre rien (la zone circule en clair : sans importance ici, tout est interne). PowerDNS stocke les clés dans la base (`tsigkeys`) et leur usage par zone dans des métadonnées (`TSIG-ALLOW-AXFR` côté primaire, `AXFR-MASTER-TSIG` côté secondaire) ; le NOTIFY est signé avec la clé de la zone (`send-signed-notify`). Le récurseur, lui, ne participe pas : il relaie les questions sur les zones internes à « un » serveur faisant autorité, et c'est la présence de **deux** relais dans sa configuration qui rend la résolution interne robuste.

**Alternatives**
- **Réplication par la base** (deux PowerDNS sur la même base PostgreSQL, ou réplication SQLite/LMDB) : pas d'AXFR, cohérence immédiate, mais un SPOF (la base) et un couplage fort ; c'est le modèle « Native ».
- **Zones catalogues** (RFC 9432, PowerDNS 4.7+) : le secondaire découvre seul les zones du primaire ; à adopter dès que le nombre de zones augmente (modules 10, 15).
- **Autosecondary** (`autosecondary=yes`, supernotify) : le secondaire crée une zone quand un primaire de confiance la notifie ; plus simple que les catalogues, moins contrôlé.
- **Un seul « vrai » secondaire caché** (*hidden primary*) : `dns01` ne serait plus annoncé dans les NS ; utile quand les autoritaires sont exposés (DMZ), sans intérêt ici.

**Pièges classiques**
- Zones en type `Native` : rien n'est jamais notifié ni transféré.
- NOTIFY envoyés au port 53 des récurseurs (NS par défaut) : `only-notify=` vide et `also-notify` avec le port 5300.
- Croire que `allow-axfr-ips` protège quand TSIG est actif.
- Oublier `gsqlite3-dnssec=yes` : sans lui, pas de métadonnées, donc pas de TSIG (erreurs à l'import de la clé).
- Secret TSIG dans une ligne de commande (`dig -y`), dans un fichier versionné, ou affiché par Ansible (pas de `no_log`).
- Annoncer `dns02` aux clients avant de l'avoir validé : 50 % des requêtes vont vers un serveur vide.
- Configurer les deux serveurs en même temps : un rôle cassé coupe le DNS de tout le lab.

**En production chez MédiSphère**
Trois serveurs faisant autorité au moins (dont un à PAR2, M07-M09), zones catalogues, supervision du numéro de série et de l'âge du dernier transfert (E29, puis M21), rotation annuelle de la clé TSIG (procédure : import de la nouvelle clé des deux côtés, bascule de la métadonnée, retrait de l'ancienne), et anycast des récurseurs (module 07) plutôt que deux adresses dans `resolv.conf`.

---

### M06-E25 — Kea en haute disponibilité

**Solution**

Fichiers : rôle `kea_dhcp4` (celui de M06-E16/E17, étendu) : [`defaults/main.yml`](fichiers/M06-E25/ansible/roles/kea_dhcp4/defaults/main.yml), [`templates/kea-dhcp4.conf.j2`](fichiers/M06-E25/ansible/roles/kea_dhcp4/templates/kea-dhcp4.conf.j2), [`tasks/main.yml`](fichiers/M06-E25/ansible/roles/kea_dhcp4/tasks/main.yml) ; [rôle `kea_ddns`, `tasks/main.yml`](fichiers/M06-E25/ansible/roles/kea_ddns/tasks/main.yml) ; rôle [`relais_dhcp`](fichiers/M06-E25/ansible/roles/relais_dhcp/) ; inventaire : [`group_vars/role_dns/kea.yml`](fichiers/M06-E25/ansible/inventories/lab/group_vars/role_dns/kea.yml), [extrait de `vault-critique.yml`](fichiers/M06-E25/ansible/inventories/lab/group_vars/role_dns/vault-critique.yml.extrait), [`host_vars/dns01/certificats.yml`](fichiers/M06-E25/ansible/inventories/lab/host_vars/dns01/certificats.yml), [`host_vars/dns02/certificats.yml`](fichiers/M06-E25/ansible/inventories/lab/host_vars/dns02/certificats.yml), [`host_vars/gw01/relais_dhcp.yml`](fichiers/M06-E25/ansible/inventories/lab/host_vars/gw01/relais_dhcp.yml), [extrait de `pare_feu.yml`](fichiers/M06-E25/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait) ; [`playbooks/dns01.yml`](fichiers/M06-E25/ansible/playbooks/dns01.yml), [`playbooks/gw01-pare-feu.yml`](fichiers/M06-E25/ansible/playbooks/gw01-pare-feu.yml) ; scénario [`molecule/kea_ha/`](fichiers/M06-E25/ansible/molecule/kea_ha/) ; runbook [RB-062](fichiers/M06-E25/medisphere/docs/socle/runbooks/RB-062-dhcp-kea-ha.md).

*1. Lecture et choix.*
- `hot-standby` plutôt que `load-balancing` : une seule plage de 100 adresses, peu de clients, et un diagnostic simple (un seul serveur répond, toujours le même). `load-balancing` demanderait de couper la plage en deux (classes `HA_dns01`/`HA_dns02`) et diviserait par deux la capacité de chacun en cas de panne de l'autre… pour un gain de charge inutile ici. `passive-backup` n'a pas de bascule automatique.
- `heartbeat-delay` 10 s (fréquence des battements) ; `max-response-delay` 60 s (sans réponse pendant ce délai, la communication est réputée interrompue) ; `max-ack-delay` 5 s (un client dont le champ `secs` dépasse ce délai est « non acquitté ») ; `max-unacked-clients` **0** : bascule dès que `max-response-delay` est écoulé, sans attendre de constater des clients sans réponse. La documentation le recommande quand le trafic est faible : avec une valeur > 0, un primaire tombé la nuit dans un lab sans client ne serait jamais déclaré mort. Prix à payer : en cas de coupure du **lien** entre pairs (les deux vivants), le standby passe aussi en `partner-down` et deux serveurs répondent (voir E32, question 7).
- `restrict-commands` (vrai par défaut depuis Kea 3.0) : l'écouteur dédié n'exécute que les commandes du protocole HA. `require-client-certs` (paramètre de la relation, vrai par défaut) : l'écouteur dédié exige un certificat client valide. **Authentification basique** : `basic-auth-user`/`basic-auth-password(-file)` d'un pair ajoutent un en-tête aux requêtes **envoyées** à ce pair ; la vérification se fait côté récepteur… or l'écouteur dédié n'a pas de liste de clients à vérifier (un fil de la liste kea-users de janvier 2026 rapporte qu'il accepte n'importe quels identifiants). Conclusion retenue : l'authentification **réelle** des pairs est le **TLS mutuel** ; l'authentification basique sert au socket de contrôle (8004), où des `clients` sont déclarés.

*2. Certificats* : aucun code nouveau. Le rôle `certificats_acme` de M06-E18 reçoit une entrée par hôte ([`host_vars/dns01/certificats.yml`](fichiers/M06-E25/ansible/inventories/lab/host_vars/dns01/certificats.yml)) : identifiant `kea`, noms `[dns01.par1.medisphere.internal, 10.10.20.10]`, fichiers `/etc/kea/tls/kea.crt` et `kea.key`, groupe `_kea` (Kea lit la clé après avoir abandonné les droits root), commande de rechargement `systemctl try-restart isc-kea-dhcp4-server`. Émission ACME en mode autonome (rien n'écoute sur le port 80 de `dns01`), renouvellement par `cert-renewer@kea.timer`, seuil de E27. Le playbook `dns01.yml` applique `certificats_acme` **avant** `kea_dhcp4` : le gabarit de Kea ne référence que des fichiers déjà présents (une assertion du rôle le vérifie).

```
admin@dns01:~$ sudo step certificate inspect /etc/kea/tls/kea.crt --short
X.509v3 TLS Certificate (ECDSA P-256) [Serial: 1234…]
  Subject:     dns01.par1.medisphere.internal
  Issuer:      MédiSphère Intermediate CA
  Provisioner: acme [ACME]
  Valid from:  2026-10-07T09:12:00Z
          to:  2026-11-06T09:13:00Z
admin@dns01:~$ sudo openssl x509 -in /etc/kea/tls/kea.crt -noout -ext subjectAltName,extendedKeyUsage
X509v3 Subject Alternative Name:
    DNS:dns01.par1.medisphere.internal, IP Address:10.10.20.10
X509v3 Extended Key Usage:
    TLS Web Server Authentication, TLS Web Client Authentication
```

⚠️ À vérifier sur ta version : (a) l'émission ACME d'un identifiant IP ; si step-ca la refuse, émets le certificat avec le provisioner `admin` (jeton à usage unique fourni à Ansible pour la première émission, renouvellement par mTLS ensuite) ; (b) la documentation de Kea indique que les fichiers PEM contenant **plusieurs** certificats ne sont « pas pris en charge » ; `step` écrit la feuille **et** l'intermédiaire dans `kea.crt`. Avec OpenSSL, la chaîne est normalement envoyée correctement. Si la poignée de main échoue (`journalctl -u isc-kea-dhcp4-server` : erreur de vérification côté pair), sépare la feuille (`kea.crt`) et pointe `trust-anchor` vers un **répertoire** contenant racine et intermédiaire, préparé par `openssl rehash`.

*3. Le rôle* : un seul gabarit ([`kea-dhcp4.conf.j2`](fichiers/M06-E25/ansible/roles/kea_dhcp4/templates/kea-dhcp4.conf.j2)) ; `this-server-name` vaut le nom de l'hôte, l'adresse d'écoute vient des faits. Extrait du rendu sur `dns02` :

```json
"hooks-libraries": [
  { "library": "libdhcp_lease_cmds.so" },
  { "library": "libdhcp_ha.so", "parameters": { "high-availability": [ {
      "this-server-name": "dns02", "mode": "hot-standby",
      "heartbeat-delay": 10000, "max-response-delay": 60000, "max-ack-delay": 5000, "max-unacked-clients": 0,
      "restrict-commands": true, "require-client-certs": true,
      "trust-anchor": "/usr/local/share/ca-certificates/medisphere-root-ca.crt",
      "cert-file": "/etc/kea/tls/kea.crt", "key-file": "/etc/kea/tls/kea.key",
      "multi-threading": { "enable-multi-threading": true, "http-dedicated-listener": true,
                           "http-listener-threads": 2, "http-client-threads": 2 },
      "peers": [
        { "name": "dns01", "url": "https://10.10.20.10:8001/", "role": "primary", "auto-failover": true },
        { "name": "dns02", "url": "https://10.10.20.16:8001/", "role": "standby", "auto-failover": true } ] } ] } } ]
```

Le socket de contrôle de M06-E17 passe en HTTPS sur 10.10.20.x:8004 (même port, adresse de service au lieu de la boucle locale) avec deux comptes : `kea-api` (administration, celui de M06-E17) et `supervision` (`kea_dhcp4_api_comptes_supplementaires`), dont les mots de passe sont dans des fichiers (`directory` + `password-file`) déposés depuis Vault ; `cert-required: false` sur ce socket (les clients n'ont pas de certificat ; le serveur est authentifié par TLS, le client par mot de passe). Un socket Unix local reste pour `kea-shell` et la sauvegarde (E28). `kea-dhcp4 -t` valide chaque rendu avant installation (`validate:` du module `template`).

DDNS en bascule : `kea_ddns` appliqué aux **deux** hôtes, serveur DNS cible `kea_ddns_serveur: 10.10.20.10` (port 5300) pour les deux ; les tâches « côté PowerDNS » du rôle (clé, métadonnées) ne tournent que sur le primaire ([modification](fichiers/M06-E25/ansible/roles/kea_ddns/tasks/main.yml)). Sur `dns01`, 10.10.20.16 est ajouté à `allow-dnsupdate-from` (`powerdns_auth_dnsupdate_autorises`, E24) et à la métadonnée `ALLOW-DNSUPDATE-FROM` (`kea_ddns_autorises`), la clé `ddns-kea` restant exigée (`TSIG-ALLOW-DNSUPDATE`).

*4. Mise en service* : `dns01` d'abord. Seul, il passe par `waiting` puis, faute de pair, en `partner-down` après `max-response-delay` : il sert normalement. Puis `dns02` : `waiting` → `syncing` (il récupère tous les baux de `dns01` par `lease4-get-page`) → `ready` → les deux en `hot-standby`.

```
admin@adm01:~$ curl -s … -d '{"command": "status-get"}' https://10.10.20.10:8004/ | jq '.[0].arguments["high-availability"]'
[ { "ha-mode": "hot-standby",
    "ha-servers": { "local": { "role": "primary", "state": "hot-standby", "scopes": ["dns01"], … },
                    "remote": { "role": "standby", "last-state": "hot-standby", "in-touch": true, "clock-skew": 0, … } } } ]
```

`status-get` est refusé sur 8001 pour deux raisons : l'écouteur exige un certificat client (la poignée de main TLS échoue avant même HTTP) et, même avec un certificat, `restrict-commands` limite cet écouteur aux commandes HA.

*5. Le relais* : rôle [`relais_dhcp`](fichiers/M06-E25/ansible/roles/relais_dhcp/) — une ligne `dhcp-relay=10.10.99.1,<serveur>` par serveur (dnsmasq relaie alors chaque requête à chacun, `man dnsmasq`). Côté `pare_feu.yml` : les réponses de `dns02` au `giaddr` (chaîne `input` de `gw01`) et les renouvellements *unicast* vers `dns02` (un client dont le bail vient de `dns02` après une bascule renouvelle directement auprès de lui, à T1). Preuve :

```
root@gw01:~# tcpdump -ni any 'udp port 67' -c 6
… ens19.99 In  IP 0.0.0.0.68 > 255.255.255.255.67: BOOTP/DHCP, Request …           (DISCOVER du client)
… ens19.20 Out IP 10.10.20.1.67 > 10.10.20.10.67: BOOTP/DHCP, Request …             (relayé à dns01)
… ens19.20 Out IP 10.10.20.1.67 > 10.10.20.16.67: BOOTP/DHCP, Request …             (relayé à dns02)
… ens19.20 In  IP 10.10.20.10.67 > 10.10.99.1.67: BOOTP/DHCP, Reply …               (seul dns01 répond)
```

Note l'adresse source des requêtes relayées : **10.10.20.1** (adresse de `gw01` dans INFRA), pas 10.10.99.1 (qui n'est que le `giaddr` dans le paquet). Elle comptera pour le filtrage local de E30.

*6. Bascule* (valeurs typiques) :
1. Kea arrêté sur `dns01` à T0 : `dns02` reste en `hot-standby` tant que `max-response-delay` n'est pas écoulé, puis passe en `partner-down` vers T0 + 60 à 70 s (au battement suivant). Un nouveau client (2065 avec une nouvelle MAC : `qm set 2065 --net0 virtio,bridge=vsandbox` puis redémarrage) obtient un bail de `dns02` ; le renouvellement de l'ancien client aussi. Le nom `sbxNN` est mis à jour par le `kea-dhcp-ddns` de `dns02` vers `dns01:5300` (PowerDNS de `dns01` tourne toujours : seul Kea est arrêté).
2. Redémarrage de Kea sur `dns01` : `waiting` → `syncing` (il récupère les baux accordés par `dns02` pendant la panne) → `ready` → `hot-standby` sur les deux. Aucun bail perdu.
3. Maintenance : `ha-maintenance-start` envoyé à `dns02` (celui qui reste) : `dns02` en `partner-in-maintenance`, `dns01` en `in-maintenance` ; arrêt de `dns01` : `dns02` passe **immédiatement** en `partner-down` (pas d'attente de 60 s, aucune requête perdue). Au retour, synchronisation et retour en `hot-standby` ; `ha-maintenance-cancel` n'est nécessaire que si on renonce à la maintenance avant d'arrêter le serveur.

*7.* [RB-062](fichiers/M06-E25/medisphere/docs/socle/runbooks/RB-062-dhcp-kea-ha.md) ; `qm destroy 2065 --purge`.

**Explications**

Le hook HA de Kea n'est pas le protocole « DHCP failover » d'ISC DHCP : il n'y a pas de partage de plage négocié, mais une **réplication synchrone des baux** (chaque bail accordé est envoyé au pair par `lease4-update` avant la réponse au client) et une **machine à états** pilotée par les battements. En `hot-standby`, une seule « portée » (*scope*) existe, servie par le primaire ; le standby la reprend en `partner-down`. Le relais doit envoyer les requêtes aux deux serveurs : c'est ainsi que le standby peut, quand `max-unacked-clients` > 0, observer que des clients réessaient sans réponse (champ `secs`) avant de déclarer le primaire mort. Depuis Kea 2.7, les serveurs portent eux-mêmes leur socket de contrôle HTTP(S) ; l'agent de contrôle (`kea-ctrl-agent`) est supprimé en 3.2 : on ne l'installe plus.

**Alternatives**
- `load-balancing` (deux plages, deux portées) : utile quand la charge le justifie ; double le travail de diagnostic.
- Un troisième serveur `backup` (PAR2) : copie des baux pour la reprise après sinistre, sans bascule automatique.
- Base de baux partagée (PostgreSQL) au lieu de `memfile` + HA : pas de réplication par le hook, mais une base à rendre elle-même hautement disponible.
- Relais `isc-dhcp-relay` : en fin de vie avec ISC DHCP ; le relais de Kea n'existe pas (Kea est un serveur).

**Pièges classiques**
- Kea démarré sur `dns02` **avant** la configuration HA : deux serveurs indépendants distribuent la même plage.
- Pairs avec des sous-réseaux différents (`id` différent, plage différente) : les mises à jour de baux sont rejetées.
- Même port pour le socket de contrôle et l'écouteur HA (la doc le signale : le serveur ne peut pas ouvrir ses sockets).
- Noms DNS dans les URL des pairs : refusés, il faut des adresses IP (d'où l'adresse dans le certificat).
- Horloges désynchronisées de plus de 60 s : la paire passe en `terminated`.
- Croire que `basic-auth-*` protège l'écouteur dédié.
- Oublier les règles de `gw01` pour `dns02` : après une bascule, les réponses de `dns02` meurent sur le pare-feu, et les clients n'obtiennent plus rien… exactement quand on a besoin du secours.
- Certificat renouvelé mais illisible par l'utilisateur du service (droits) : Kea échoue au rechargement suivant.

**En production chez MédiSphère**
Paire répartie sur deux hyperviseurs (règle d'anti-affinité, module 09), supervision de l'état HA et de l'âge du dernier battement (E29 puis M21), test de bascule trimestriel inscrit au calendrier, réservations et plages générées depuis NetBox (ADR-0060), et réflexion sur un `max-unacked-clients` > 0 dès que le trafic DHCP le permet (protection contre le *split brain*).

---

### M06-E26 — DNSSEC sur la zone interne

**Solution**

Fichiers : [`powerdns_auth/tasks/dnssec.yml`](fichiers/M06-E26/ansible/roles/powerdns_auth/tasks/dnssec.yml), [`group_vars/role_dns/dnssec.yml`](fichiers/M06-E26/ansible/inventories/lab/group_vars/role_dns/dnssec.yml), rôle `powerdns_recursor` de M06-E07 étendu : [`templates/recursor.yml.j2`](fichiers/M06-E26/ansible/roles/powerdns_recursor/templates/recursor.yml.j2) (ancres positives), [`defaults/main.yml`](fichiers/M06-E26/ansible/roles/powerdns_recursor/defaults/main.yml) (état final, `powerdns_recursor_ancres` ajoutée), [`tasks/configuration.yml`](fichiers/M06-E26/ansible/roles/powerdns_recursor/tasks/configuration.yml) qui inclut [`tasks/ancres.yml`](fichiers/M06-E26/ansible/roles/powerdns_recursor/tasks/ancres.yml) ; runbook [RB-064](fichiers/M06-E26/medisphere/docs/socle/runbooks/RB-064-dnssec-roulement-csk.md).

*1. Préparation* : `grep gsqlite3-dnssec /etc/powerdns/pdns.d/medisphere.conf` → `yes` (le gabarit du rôle l'impose depuis M06-E06 ; sans lui, `zone secure` échoue). Choix **NSEC** : la zone est interne, son contenu est déjà demandable par tout client du lab, l'énumération par NSEC n'apprend rien de nouveau à un attaquant déjà dans le réseau ; NSEC est plus simple à lire (`dig` montre les noms voisins) et n'a aucun coût de calcul. NSEC3 se justifierait pour une zone publique ; s'il est choisi, en mode **broad** (paramètres `1 0 0 -` : RFC 9276, aucune itération, pas de sel) : le mode *narrow* calcule les NSEC3 à la volée et ne peut pas être transféré au secondaire.

*2. Signature* :

```
admin@dns01:~$ sudo -u pdns pdnsutil zone secure par1.medisphere.internal
admin@dns01:~$ sudo -u pdns pdnsutil zone show par1.medisphere.internal
This is a Primary zone
Last SOA serial number we notified: 2026100716 == 2026100716 (serial in the database)
Zone has NSEC semantics
keys:
ID = 1 (CSK), flags = 257, tag = 40312, algo = 13, bits = 256    Active   Published  ( ECDSAP256SHA256 )
CSK DNSKEY = par1.medisphere.internal. IN DNSKEY 257 3 13 mdsswUyr3DPW132mOi8V9xESWE8jTo0d… ; ( ECDSAP256SHA256 )
DS = par1.medisphere.internal. IN DS 40312 13 2 8a7f… ; ( SHA256 digest )
DS = par1.medisphere.internal. IN DS 40312 13 4 d1c9… ; ( SHA-384 digest )
```

(Valeurs illustratives.) Une seule clé combinée (CSK, *flags* 257), ECDSA P-256 (algorithme 13), active et publiée : c'est le comportement de `zone secure` depuis PowerDNS 4.0. Les RRSIG ont une *inception* au jeudi précédent et une *expiration* environ trois semaines plus tard ; PowerDNS les recalcule chaque semaine (signature en ligne, à la volée, avec cache). La non-existence d'un nom est prouvée par un enregistrement NSEC signé qui couvre l'intervalle (« entre `git01` et `nbx01`, rien »), et le SOA signé dans la section *authority*.

*3. Le secondaire* : oui, la zone transférée contient DNSKEY, RRSIG et NSEC. `dns02` a posé **lui-même** la métadonnée `PRESIGNED = 1` en détectant des enregistrements DNSSEC dans l'AXFR (`pdnsutil metadata get par1.medisphere.internal PRESIGNED`) : il sert les signatures telles quelles, sans clé. Problème : les signatures changent chaque semaine, mais le numéro de série, lui, ne change que si une donnée change. Sans écriture pendant trois semaines, `dns02` servirait des RRSIG **expirées** (SERVFAIL pour les clients validants). Réglage retenu : `default-soa-edit-signed=INCEPTION-INCREMENT` sur `dns01` (dans le gabarit) — le numéro de série **servi** évolue avec la date d'*inception* des signatures ; `dns02` voit un numéro plus grand à son rafraîchissement suivant et retransfère la zone signée à neuf.

*4. Code* : [`dnssec.yml`](fichiers/M06-E26/ansible/roles/powerdns_auth/tasks/dnssec.yml) ne signe que les zones listées **et pas encore signées** (`zone show` → « not actively secured ») ; il ne génère jamais de clé pour une zone déjà signée. Second passage : `changed=0`.

*5. Ancres* : DS en SHA-256 relevé avec `pdnsutil zone export-ds`, reporté dans `powerdns_recursor_ancres`, que le gabarit de M06-E07, étendu, écrit sous `dnssec.trustanchors`. M06-E07 n'avait posé aucune ancre négative sur `par1` lui-même (sinon : la retirer) ; celles de `medisphere.internal` (la zone parente, non signée, qui couvre aussi `par2`) et des zones inverses restent (`powerdns_recursor_nta`). Le récurseur retient pour un nom de `par1` l'ancre la plus proche (celle de `par1`) : le drapeau `ad` le prouve. ⚠️ À vérifier sur ta version : si `ad` n'apparaît pas tant que l'ancre négative de `medisphere.internal` existe, deux replis propres : signer aussi la zone parente (DS de `par1` publié dans `medisphere.internal`, une seule ancre sur `medisphere.internal`, et `par2` devient « non sécurisée » par simple absence de DS), ou remplacer l'ancre négative du parent par des ancres négatives sur `par2.medisphere.internal` et chaque nom non signé. Application sur `dns02` d'abord (`--limit dns02`) : le gestionnaire du rôle redémarre le Recursor (cache perdu, sans conséquence à cette échelle) ; à la main, pendant un roulement, `rec_control reload-yaml` recharge les ancres sans redémarrage.

```
admin@adm01:~$ dig +dnssec @10.10.20.16 git01.par1.medisphere.internal A | grep flags
;; flags: qr rd ra ad; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1
admin@adm01:~$ dig +cd +dnssec @10.10.20.16 git01.par1.medisphere.internal A | grep flags
;; flags: qr rd ra cd; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1
admin@dns02:~$ sudo rec_control get-tas
Configured Trust Anchors:
.
	20326 8 2 e06d44b80b8f1d39a95c0b0d7c65d08458e880409bbc683457104237c7f8ec8d
	38696 8 2 683d2d0acb8c9b712a1948b27f741219298d0a450d612c483af444a4c0fb2b16
par1.medisphere.internal.
	40312 13 2 8a7f…
```

`ad` : le récurseur a validé la chaîne (de l'ancre à la réponse). Avec `+cd` (*checking disabled*), le client demande les données sans validation : pas de `ad`, et une réponse *bogus* serait renvoyée au lieu d'un SERVFAIL — c'est l'outil de diagnostic quand une zone tombe en SERVFAIL. `isc.org` revient toujours avec `ad` (ancre de la racine), `pbs01.par2…` et les PTR se résolvent sans `ad`.

*6. Ce qui arrive après* : oui, signé sans intervention. PowerDNS signe **à la réponse** (signature en ligne) : un enregistrement ajouté par l'API (OpenTofu) ou par DNS UPDATE (Kea) est signé à la première question ; l'API et le traitement des mises à jour dynamiques rectifient la zone (champs `ordername`/`auth` nécessaires à NSEC). Seules des insertions SQL directes exigeraient `pdnsutil zone rectify`.

*7. Roulement* : [RB-064](fichiers/M06-E26/medisphere/docs/socle/runbooks/RB-064-dnssec-roulement-csk.md) — pré-publication de la nouvelle clé, double DS dans l'ancre, attente des TTL, bascule de la signature, attente, retrait ; et la variante d'urgence.

**Explications**

DNSSEC n'authentifie pas un serveur, il authentifie des **données** : chaque RRset est signé (RRSIG) par une clé dont la partie publique (DNSKEY) est elle-même authentifiée par son parent (DS)… jusqu'à une **ancre de confiance**. Pour une zone privée sans parent signé, la chaîne s'arrête à une ancre configurée localement : c'est un « îlot de sécurité ». Le récurseur valide en partant de l'ancre la plus proche du nom demandé ; sans ancre pour `par1.medisphere.internal`, il partirait de la racine, qui **prouve** que `.internal` n'existe pas : d'où, avant cet exercice, une ancre négative (validation désactivée pour la zone). Le bénéfice ici est concret : une VM compromise d'INFRA qui répondrait à la place de `dns01` (usurpation ARP, faux serveur DHCP) ne peut plus faire accepter un faux `git01` ou un faux `ca01` aux récurseurs ; et le défi HTTP-01 de l'ACME, qui repose sur la résolution du nom par `ca01`, s'appuie désormais sur des réponses authentifiées.

**Alternatives**
- KSK + ZSK séparées : roulements de ZSK sans toucher aux ancres ; plus de procédures, intérêt surtout quand le parent est un registre externe.
- Signature hors ligne (`ldns-signzone`, OpenDNSSEC) et zone pré-signée importée : clés hors du serveur, mais plus de mises à jour dynamiques simples.
- Délégation signée depuis une zone parente interne `medisphere.internal` (elle-même ancre unique) : une seule ancre pour plusieurs zones de site ; à envisager quand `par2` sera signée.
- DNS sur TLS/HTTPS entre clients et récurseurs : protège le transport du dernier kilomètre, complémentaire (DNSSEC ne chiffre rien).

**Pièges classiques**
- Poser l'ancre **avant** d'avoir vérifié la signature sur les deux serveurs faisant autorité.
- Oublier `SOA-EDIT` pour un secondaire pré-signé : panne différée de trois semaines, sans cause apparente.
- Oublier de retirer l'ancre négative posée sur la zone elle-même : la validation ne sert à rien (pas de `ad`), et personne ne s'en aperçoit.
- Utiliser NSEC3 *narrow* avec un secondaire.
- Copier dans l'ancre le DS SHA-384 et le SHA-256 « pour être sûr » : sans danger, mais à garder cohérent au roulement (RB-064).
- Un rôle qui relance `zone secure` à chaque passage, ou une restauration de base antérieure à un roulement : nouvelle clé, ancre périmée, SERVFAIL général.

**En production chez MédiSphère**
Toutes les zones internes signées (inverses comprises) sous une zone parente unique, une seule ancre distribuée par Ansible, supervision de l'expiration des RRSIG et de la cohérence ancre/clé (E29 en donne une première version), roulement annuel répété d'abord sur une zone d'essai, et validation activée aussi sur les clients sensibles.

---

### M06-E27 — La PKI en production : durées de vie, renouvellement, révocation

**Solution**

Fichiers : rôle `step_ca` de M06-E02 : [`templates/ca.json.j2`](fichiers/M06-E27/ansible/roles/step_ca/templates/ca.json.j2) (écouteur HTTP et CRL ajoutés), [`defaults/main.yml`](fichiers/M06-E27/ansible/roles/step_ca/defaults/main.yml) (état final), [`group_vars/role_pki/step_ca.yml`](fichiers/M06-E27/ansible/inventories/lab/group_vars/role_pki/step_ca.yml) (remplace celui de M06-E02 : durées, CRL) ; rôle `certificats_acme` de M06-E18 : [`templates/cert-renewer@.service.j2`](fichiers/M06-E27/ansible/roles/certificats_acme/templates/cert-renewer@.service.j2), [`defaults/main.yml`](fichiers/M06-E27/ansible/roles/certificats_acme/defaults/main.yml) (état final, `certificats_acme_seuil` ajoutée) ; runbook [RB-063](fichiers/M06-E27/medisphere/docs/socle/runbooks/RB-063-revoquer-un-certificat.md).

*1. État des lieux* :

```
admin@adm01:~$ step certificate inspect /usr/local/share/ca-certificates/medisphere-root-ca.crt --short
admin@adm01:~$ curl -s --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://ca01.par1.medisphere.internal/intermediates.pem | step certificate inspect --short -
admin@ca01:~$ sudo jq '{global: .authority.claims, provisioners: [.authority.provisioners[] | {name, type, claims}]}' /etc/step-ca/config/ca.json
admin@nbx01:~$ systemctl list-timers 'cert-renewer@*'; sudo grep -h ssl_certificate /etc/nginx/sites-enabled/*
```

Tableau type (une ligne par certificat en service) :

| Hôte | Fichier | Service | Émetteur | Expire | Renouvellement |
|---|---|---|---|---|---|
| `git01` | `/etc/gitlab/ssl/git01.par1.medisphere.internal.crt` | NGINX de GitLab | Intermediate | +30 j | `cert-renewer@gitlab` (M06-E18) |
| `nbx01` | `/etc/ssl/netbox/nbx01.par1.medisphere.internal.crt` | nginx | Intermediate | +30 j | `cert-renewer@netbox` (M06-E18) |
| `dns01`, `dns02` | `/etc/kea/tls/kea.crt` | Kea | Intermediate | +30 j | `cert-renewer@kea` |
| `s3-01` | `/etc/seaweedfs/tls/s3-01.par1.medisphere.internal.crt` (ACME depuis M06-E18) | SeaweedFS | Intermediate | +30 j | `cert-renewer@s3` (M06-E18) |
| `gw01` | certificat NTS (M06-E21) | chrony | Intermediate | +30 j | selon M06-E21 |

*2. Durées* : le rôle `step_ca` de M06-E02 génère déjà `ca.json` d'un gabarit, avec les `claims` globaux et par provisioner tirés de l'inventaire : la politique tient donc en **variables** ([`step_ca.yml`](fichiers/M06-E27/ansible/inventories/lab/group_vars/role_pki/step_ca.yml) : `step_ca_claims` global, puis les `claims` de chaque provisioner). Le gabarit gagne deux blocs optionnels, `insecureAddress` et `crl`. La mise en place reste celle de M06-E02 : copie de sauvegarde, redémarrage, contrôle de `/health`, et **retour à l'ancien fichier** si step-ca ne repart pas (un défaut supérieur au maximum, ou un maximum supérieur au maximum global, l'empêche de démarrer).

```
admin@adm01:~$ step ca provisioner list | jq '.[] | {name, type, claims}'
{ "name": "admin", "type": "JWK",  "claims": { "defaultTLSCertDuration": "24h", "maxTLSCertDuration": "168h" } }
{ "name": "acme",  "type": "ACME", "claims": { "defaultTLSCertDuration": "720h", "maxTLSCertDuration": "720h" } }
…
admin@adm01:~$ step ca certificate essai.par1.medisphere.internal /tmp/e.crt /tmp/e.key --provisioner admin --not-after 240h
error creating certificate: … requested duration of 240h0m0s is more than the authorized maximum certificate duration of 168h0m0s
```

Même refus pour un certificat SSH d'utilisateur de 24 h (`--not-after 24h` : maximum 16 h). `step ca provisioner update acme --x509-max-dur 720h` ferait la même chose à chaud ; mais si Ansible gère `ca.json`, le pipeline suivant écrase toute modification manuelle (ou, pire, une modification non reportée dans le code disparaît sans que personne s'en souvienne) : une seule source, le code.

*3. Renouvellement* : dans le rôle `certificats_acme`, l'unité gabarit [`cert-renewer@.service`](fichiers/M06-E27/ansible/roles/certificats_acme/templates/cert-renewer@.service.j2) (déjà générée par le rôle depuis M06-E18) reçoit le seuil : `ExecCondition=/usr/bin/step certificate needs-renewal --expires-in {{ certificats_acme_seuil }} ${CERT_LOCATION}`, avec `certificats_acme_seuil: 360h` (15 jours ; `step` n'accepte pas l'unité `d`). Une seule variable pour tout le socle, appliquée par le pipeline à chaque hôte qui porte le rôle. Preuve sur `nbx01` :

```
admin@adm01:~$ echo | openssl s_client -connect nbx01.par1.medisphere.internal:443 2>/dev/null | openssl x509 -noout -fingerprint -sha256 -enddate
admin@nbx01:~$ sudo env STEPPATH=/etc/step step ca renew --force /etc/ssl/netbox/nbx01.par1.medisphere.internal.crt /etc/ssl/netbox/nbx01.par1.medisphere.internal.key && sudo systemctl reload nginx
admin@adm01:~$ echo | openssl s_client -connect nbx01.par1.medisphere.internal:443 2>/dev/null | openssl x509 -noout -fingerprint -sha256 -enddate
```

L'empreinte change, la date de fin recule de 30 jours. (Lancer `systemctl start cert-renewer@netbox.service` ne renouvelle **pas** si le seuil n'est pas atteint : c'est voulu, l'`ExecCondition` sort en « condition non remplie », sans échec.)

*4. Révocation passive* :

```
admin@adm01:~$ step ca certificate essai-revocation.par1.medisphere.internal e.crt e.key --provisioner admin --not-after 2h
admin@adm01:~$ step ca renew --force e.crt e.key                       # succès
admin@adm01:~$ step certificate inspect e.crt --format json | jq -r .serial_number
293847561092837465…
admin@adm01:~$ step ca revoke 293847561092837465… --reasonCode 4 --reason "exercice M06-E27"
admin@adm01:~$ step ca renew --force e.crt e.key
error renewing certificate: … certificate has been revoked
```

Elle protège contre la **prolongation** (un voleur de clé ne peut pas renouveler) ; elle ne protège pas un client qui vérifie le certificat : `curl` ou un navigateur l'accepteraient jusqu'à son expiration (ils ne consultent pas `ca01`).

*5. Révocation active* : `crl.enabled`, `generateOnRevoke`, écouteur HTTP `insecureAddress: ":80"` (capacité `CAP_NET_BIND_SERVICE` déjà donnée en E02 pour 443) ; flux : tout le lab et le VPN doivent pouvoir lire la CRL (c'est une donnée publique) — MGMT et VPN joignent déjà INFRA, le filtrage local de `ca01` (E30) l'ouvre.

```
admin@adm01:~$ step crl inspect --ca /usr/local/share/ca-certificates/medisphere-root-ca.crt http://ca01.par1.medisphere.internal/1.0/crl
Certificate Revocation List (CRL):
    Data:
        Version: 2 (0x1)
        Signature algorithm: ECDSA-SHA256
        Issuer: CN=MédiSphère Intermediate CA,O=MédiSphère
        Last Update: 2026-10-07T10:42:11Z
        Next Update: 2026-10-08T10:42:11Z
    Revoked Certificates:
        Serial Number: 293847561092837465… (0x…)
            Revocation Date: 2026-10-07T10:41:58Z
            CRL Entry Extensions:
                X509v3 CRL Reason Code: Superseded
admin@adm01:~$ openssl verify -crl_check -CAfile chaine.pem -CRLfile crl.pem e.crt
error 23 at 0 depth lookup: certificate revoked
```

(Préparation de `chaine.pem` et `crl.pem` : RB-063 §3.) Aujourd'hui, **aucun** client du socle ne consulte la CRL d'office : nos certificats n'ont pas de point de distribution, et `curl`, GitLab, NetBox, Kea ne la chargent pas. Conclusion : en cas de clé compromise, la vraie protection est la **durée courte** (30 jours au pire) **plus** le remplacement immédiat du certificat **plus** le retrait de la confiance là où elle est accordée (service arrêté ou nouvelle clé). La CRL sert à l'audit, aux vérifications explicites, et aux clients qu'on configurera (proxys mTLS, modules 15 et 24).

*6. Fin de vie de la CA* : intermédiaire créé par `step ca init` en E02 (10 ans par défaut : vérifie la tienne). Date limite pour un certificat de 30 jours « valide jusqu'au bout » : expiration de l'intermédiaire − 30 jours. Rappels : expiration − 1 an (préparer la cérémonie), expiration − 3 mois (dernier délai). La racine : expiration − 2 ans (nouvelle racine, recouvrement des deux ancres sur tous les hôtes, comme en E03). Procédure : RB-063 §6 (crise) et la cérémonie de la politique (E33).

*7.* [RB-063](fichiers/M06-E27/medisphere/docs/socle/runbooks/RB-063-revoquer-un-certificat.md).

**Explications**

step-ca applique les `claims` au moment de l'émission : défaut si le demandeur ne précise rien, refus au-delà du maximum. La hiérarchie est simple : un provisioner hérite des `claims` globaux pour ce qu'il ne définit pas, et ne peut pas dépasser le maximum global. Le renouvellement (`step ca renew`) s'authentifie par **mTLS avec le certificat lui-même** : pas de provisioner, pas de défi, d'où la révocation passive (le serveur refuse de prolonger un numéro de série révoqué). La CRL est l'autre moitié : une liste signée, datée, que le **client** doit aller chercher et consulter. Les deux ensemble restent faibles face aux durées courtes, qui ne demandent rien au client : c'est la tendance de toute l'industrie (certificats publics à 47 jours en 2029, question 11 de E32).

**Alternatives**
- OCSP : non fourni par step-ca libre ; les navigateurs l'abandonnent au profit des CRL agrégées et des durées courtes.
- Durées encore plus courtes (7 jours, voire 24 h) avec renouvellement fréquent : excellent en théorie, exige une supervision irréprochable du renouvellement.
- Gestion des provisioners par l'API d'administration de step-ca (`authority.enableAdmin`, provisioners en base) plutôt que par `ca.json` : plus dynamique, moins visible en revue de code.
- PKI de Vault/OpenBao (module 25), qui sait aussi émettre de courte durée et publier une CRL.

**Pièges classiques**
- Défaut supérieur au maximum, ou maximum d'un provisioner supérieur au maximum global : step-ca refuse de démarrer, plus aucune émission **ni renouvellement** dans le socle.
- Modifier un provisioner à la main (`step ca provisioner update`) alors qu'Ansible gère `ca.json`.
- Seuil de renouvellement par défaut (66 %) avec des certificats de 30 jours et une alerte à 10 jours : alerte et renouvellement coïncident, l'astreinte n'a aucune marge.
- Écrire `15d` dans `--expires-in` : step attend des heures (`360h`).
- Révoquer un certificat en service « pour voir ».
- Confondre numéro de série décimal (step) et hexadécimal (openssl).
- Croire qu'une CRL publiée protège : encore faut-il qu'un client la lise.

**En production chez MédiSphère**
Politique publiée (E33), revue trimestrielle des provisioners, supervision des échecs de renouvellement (journal des `cert-renewer@` vers le SIEM, module 22), points de distribution de CRL dans les certificats des services qui feront du mTLS, et intermédiaire dans un HSM ou un KMS (module 25).

---

### M06-E28 — Sauvegarder et restaurer les services socle

**Solution** (une solution possible ; `LIBRE` : d'autres choix sont valables s'ils respectent les contraintes)

Fichiers : rôle [`sauvegarde_pbs`](fichiers/M06-E28/ansible/roles/sauvegarde_pbs/) (script [`wb-backup-socle.sh`](fichiers/M06-E28/ansible/roles/sauvegarde_pbs/files/wb-backup-socle.sh), unités, gabarits), variables par hôte ([`dns01`](fichiers/M06-E28/ansible/inventories/lab/host_vars/dns01/sauvegarde_pbs.yml), [`ca01`](fichiers/M06-E28/ansible/inventories/lab/host_vars/ca01/sauvegarde_pbs.yml), [`nbx01`](fichiers/M06-E28/ansible/inventories/lab/host_vars/nbx01/sauvegarde_pbs.yml)), [modèle de Vault](fichiers/M06-E28/ansible/inventories/lab/group_vars/socle/vault-sauvegardes.yml.exemple), [`playbooks/sauvegardes.yml`](fichiers/M06-E28/ansible/playbooks/sauvegardes.yml), script PBS [`pbs-jetons-socle.sh`](fichiers/M06-E28/pbs01/pbs-jetons-socle.sh), extraits de pare-feu ([`gw01`](fichiers/M06-E28/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait), [`pbs01`](fichiers/M06-E28/pbs01/pbs01-nftables-extrait.nft)), runbook [RB-061](fichiers/M06-E28/medisphere/docs/socle/runbooks/RB-061-restaurer-un-service-socle.md).

*Analyse par service* (ce qui fait l'état, comment le copier de façon cohérente, quel secret faut-il pour le relire) :

| Service | Données | Copie cohérente | Secrets nécessaires à la relecture |
|---|---|---|---|
| PowerDNS | base SQLite (zones, clés DNSSEC, clés TSIG, métadonnées) | API de sauvegarde de SQLite (`sqlite3 … ".backup …"`), en ligne, puis `PRAGMA integrity_check` | aucun (mais la base **contient** des secrets : clés DNSSEC privées, TSIG) |
| Kea | baux (`memfile`, CSV réécrit par le processus *Lease File Cleanup*) | `lease4-get-all` sur le socket local (export JSON fait par Kea lui-même) + copie des CSV | mots de passe du socket de contrôle (Vault) |
| NetBox | PostgreSQL, fichiers téléversés (`media`), `configuration.py` | `pg_dump -Fc` (instantané transactionnel), archive de `media` | `SECRET_KEY`, `API_TOKEN_PEPPERS` (Vault **et** archive chiffrée) |
| step-ca | `/etc/step-ca` (configuration, base Badger, certificats, clé chiffrée de l'intermédiaire, clés SSH chiffrées) | **arrêt** de step-ca le temps de la copie (Badger : un seul processus, pas d'export en ligne), redémarrage garanti par `trap` ; quelques secondes, l'ACME réessaie | mot de passe de l'intermédiaire (Vault, **exclu** de l'archive) |
| `dns02` | rien de propre | — | — |

`dns02` : pas de sauvegarde applicative. Ses zones sont une copie de `dns01` (AXFR), ses baux une copie de ceux de `dns01` (HA), sa configuration est le code. Le reconstruire = OpenTofu + Ansible, il se remplit seul. La sauvegarde de VM de la nuit suffit pour un retour rapide.

*Mise en œuvre* : un rôle, un script générique piloté par `WB_ELEMENTS`, une configuration non secrète (`/etc/wb-backup/socle.conf`) et deux secrets par hôte (`pbs-<hôte>.env`, `pbs-<hôte>.key`, `root:root 600`, depuis Vault `critique`). Timer : `dns01` 01:55, `ca01` 02:00, `nbx01` 02:05 (après `git01` 01:15, avant `lab-nuit` 02:30), `OnFailure=ms-alerte@%n.service`. Le dépôt `pbs-client` est configuré avec le trousseau officiel dont l'**empreinte** est vérifiée (`get_url` avec `checksum`, valeur publiée dans la documentation PBS). Côté PBS, [`pbs-jetons-socle.sh`](fichiers/M06-E28/pbs01/pbs-jetons-socle.sh) crée les espaces de noms `par1/<hôte>` et les jetons limités (`DatastoreBackup` sur leur espace ; les droits d'un jeton sont l'intersection avec ceux de `wb-backup@pbs`).

Clés de chiffrement : générées sur `adm01` (`proxmox-backup-client key create /tmp/pbs-<hôte>.key --kdf none`), *paperkey* imprimée et copie hors ligne **avant** de les mettre dans Vault, puis `shred -u` du fichier temporaire. Elles ne passent jamais par `pbs01`.

*Sophie : qui peut lire la clé de l'intermédiaire ?* La sauvegarde de `ca01` contient la clé de l'intermédiaire **chiffrée** (par son mot de passe, absent de l'archive), dans une archive chiffrée côté client (clé `pbs-ca01.key`, présente sur `ca01`, dans Vault et hors ligne). Pour l'utiliser, il faut donc : la clé PBS de `ca01` **et** un accès en lecture à `par1/ca01` **et** le mot de passe de l'intermédiaire (Vault `critique`). Un administrateur de PBS seul ne peut rien ; un administrateur de `ca01` peut déjà tout (il a la clé en clair en mémoire du service). La clé racine n'y est pas : le script refuse de sauvegarder si une clé racine est trouvée sous `/etc/step-ca`, et `/etc/step-ca` est copié **en arborescence** pour que le catalogue PBS le prouve :

```
admin@ca01:~$ sudo bash -c 'set -a; . /etc/wb-backup/pbs-ca01.env; set +a; proxmox-backup-client catalog dump host/ca01/<HORODATAGE> --ns par1/ca01 --keyfile /etc/wb-backup/pbs-ca01.key' | grep -E 'secrets|ca.json'
d "/socle.pxar.didx/stepca/etc/step-ca/secrets"
f "/socle.pxar.didx/stepca/etc/step-ca/secrets/intermediate_ca_key" …
f "/socle.pxar.didx/stepca/etc/step-ca/config/ca.json" …
```

*Restauration de test* (VM 2068, détail dans RB-061 §6) : VM isolée par un filtrage d'entrée local avant toute copie de secret ; données rapatriées par `adm01` ; rôles Ansible appliqués à 2068 avec un inventaire de test et l'émission ACME désactivée ; preuves par service (numéro de série des zones, `/api/status/` et liste des VMs **avec le jeton de production des checks** — preuve que les *peppers* sont restaurés —, `/health` et un certificat d'essai vérifié par la racine). Feuille de temps typique :

| Service | Étapes dominantes | RTO typique |
|---|---|---|
| PowerDNS | installation par le rôle, copie de la base | 10 min |
| NetBox | rôle `netbox` (installation de NetBox et de ses dépendances Python), `pg_restore` | 25 à 40 min |
| step-ca | paquet, copie de l'arborescence, mot de passe depuis Vault | 10 min |

RPO : ≤ 24 h pour NetBox et step-ca ; quasi nul pour le DNS et le DHCP tant que `dns02` existe.

**Explications**

Une sauvegarde **applicative** est portable (autre machine, autre version d'OS) et cohérente (chaque outil fournit son export transactionnel) ; elle complète la sauvegarde de VM, qui est plus rapide pour un retour sur place. La difficulté de ce module est moins technique que **conceptuelle** : chaque service contient des secrets (clés DNSSEC, TSIG, clé de l'intermédiaire, `SECRET_KEY`, *peppers*), et une restauration **réveille** ces secrets ailleurs. D'où le chiffrement côté client, la séparation entre l'archive et le mot de passe de la clé de l'intermédiaire, l'isolement de la VM de test, et le nettoyage final.

**Alternatives**
- Sauvegarde de VM seule (`lab-nuit`) + test de restauration de VM : plus simple, mais pas de restauration partielle (une zone, un objet NetBox) et pas de portabilité.
- Réplication en continu (PostgreSQL en flux vers PAR2, PowerDNS secondaire à PAR2) : RPO quasi nul, mais ce n'est pas une sauvegarde (une erreur se réplique).
- `pg_dump` de NetBox vers le stockage S3 du socle (`s3-01`) : même site, pas de chiffrement côté client sans outil supplémentaire.
- Export des objets NetBox par l'API (YAML) en plus de la base : lisible par un humain, utile pour l'audit, pas pour une restauration complète.

**Pièges classiques**
- Copier `pdns.sqlite3` ou la base Badger à chaud avec `cp`.
- Restaurer NetBox sans les mêmes `SECRET_KEY`/`API_TOKEN_PEPPERS` : tous les jetons v2 invalides.
- Restaurer une base DNS ancienne sur `dns01` sans relever les numéros de série : `dns02` garde ses données (plus récentes), les deux serveurs divergent.
- Mettre le mot de passe de l'intermédiaire dans la même archive que la clé.
- Laisser la VM de test joignable par les autres VMs sandbox, ou oublier de la détruire.
- Un jeton PBS partagé par tous les hôtes : un hôte compromis lit (ou purge) les sauvegardes des autres.
- Oublier la règle d'entrée de `pbs01` (PBS filtre lui-même ses entrées, M00-E21).

**En production chez MédiSphère**
Synchronisation de `par1/*` vers un second datastore hors site (module 09), vérification automatique quotidienne d'un fichier témoin restauré, test de restauration semestriel chronométré (preuve d'audit HDS), alerte « sauvegarde de plus de 26 h » étendue aux espaces `par1/<hôte>` (`ms-verif-sauvegardes`, M02-E26).

---

### M06-E29 — Superviser les services socle et l'expiration des certificats

**Solution**

Fichiers (projet `plateforme/outils`) : [`bin/ms-verif-services`](fichiers/M06-E29/outils/bin/ms-verif-services), [`etc/ms-verif-services.conf`](fichiers/M06-E29/outils/etc/ms-verif-services.conf), tests [`tests/bats/ms-verif-services.bats`](fichiers/M06-E29/outils/tests/bats/ms-verif-services.bats), unités [`ms-verif-services.service`](fichiers/M06-E29/outils/systemd/ms-verif-services.service) et [`.timer`](fichiers/M06-E29/outils/systemd/ms-verif-services.timer), [drop-in de test](fichiers/M06-E29/outils/systemd/seuil-absurde.conf.exemple), [extrait du Taskfile](fichiers/M06-E29/outils/Taskfile-install-extrait.yml), [extrait de `docs/astreinte.md`](fichiers/M06-E29/outils/docs/astreinte-extrait.md). Le script et ses tests s'appuient sur `lib/ms-commun.sh`, la bibliothèque du projet (M02-E20, [référence](../../02-scripting/corrige/fichiers/M02-E20/outils/lib/ms-commun.sh)) : ils se lancent dans `plateforme/outils`, pas isolés dans le dossier du corrigé.

*1. Points TLS* : `git01:443`, `nbx01:443`, `ca01:443`, `s3-01:8333`, `dns01:8004`, `dns02:8004` (et `gw01:4460` si ton NTS de M06-E21 est joignable depuis `adm01`). Rangés dans `etc/ms-verif-services.conf`, versionné dans `plateforme/outils` et installé sous `/usr/local/etc` : ajouter un point = une MR relue, sans toucher au script (c'est ce que fera E34). La génération depuis NetBox (services ou étiquette `tls` sur les adresses) est la cible : elle évite l'oubli d'un service, mais ajoute une dépendance de la sonde à NetBox… qui est lui-même surveillé par la sonde. Choix du corrigé : fichier aujourd'hui, génération quand NetBox aura des objets *service* fiables (ADR-0060, action induite).

*2. Identités* : jeton NetBox v2 créé pour un compte de service `svc-supervision` (même convention que `svc-automatisation`, E10) sans permission d'écriture (groupe avec permissions « view » seulement), essayé en écriture → 403 ; inscrit au registre des secrets. Kea : l'authentification basique n'a **pas de rôles** (le hook RBAC est réservé aux abonnés ISC) : le compte `supervision` peut techniquement tout faire (y compris `config-set`). Risque accepté et écrit au registre, limité par : fichier 600 sur `adm01` seulement, socket filtré à `adm01` (E30), mot de passe différent de celui de `kea-api`, rotation semestrielle. Alternative plus stricte : une sonde locale sur `dns01`/`dns02` via le socket Unix, qui publie seulement son résultat.

*3. Le script* : une fonction par domaine, une ligne `OK`/`KO` par contrôle sur la sortie standard, un bilan, code 1 dès une anomalie **ou** un contrôle impossible (outil absent, identité illisible ou trop ouverte, réponse vide, configuration vide). Points d'attention : identifiants transmis à `curl` par un fichier de configuration lu sur l'entrée standard (`-K -`), jamais en argument ; réponse de Kea dans une **liste** (`.[0]`) ; `statistic-get` (commande intégrée) pour `subnet[99].total-addresses` et `subnet[99].assigned-addresses` ; certificats vérifiés par `openssl s_client -verify_return_error -verify_hostname` (la poignée de main échoue si la chaîne ou le nom ne sont pas bons) puis `x509 -checkend`. Les 12 tests bats remplacent `dig`, `curl` et `openssl` par des fonctions ; chaque domaine a au moins un test rouge.

*4. Unités* : copie de M02-E26 (oneshot, `User=admin`, durcissement, `OnFailure=ms-alerte@%n.service`), timer `*:0/15` avec `Persistent=true`. `systemd-analyze verify` puis `systemctl enable --now ms-verif-services.timer` ; `systemctl list-timers ms-verif-services.timer`.

*5. Le rouge* (exemples réversibles, un par domaine) :

| Domaine | Échec provoqué | Retour |
|---|---|---|
| Certificats | drop-in `MS_VERIF_SEUIL_CERTS=400` ([exemple](fichiers/M06-E29/outils/systemd/seuil-absurde.conf.exemple)) | suppression du drop-in, `daemon-reload` |
| DNS | `systemctl stop pdns-recursor` sur `dns02` une minute | `start` |
| Réplication | `pdns` arrêté sur `dns02`, puis un enregistrement de test ajouté sur `dns01` (les numéros de série divergent tant que `dns02` est arrêté ; la sonde voit aussi l'absence de SOA sur `dns02`) | `start` sur `dns02`, suppression de l'enregistrement de test |
| DNSSEC | ancre négative ajoutée **à chaud** sur `dns02` (`sudo rec_control add-nta par1.medisphere.internal test-E29`) : la zone n'est plus validée, plus de drapeau `ad` | `sudo rec_control clear-nta par1.medisphere.internal` |
| DHCP | `ha-maintenance-start` sur `dns02` (état `partner-in-maintenance`, pas `hot-standby`) | `ha-maintenance-cancel` |
| NetBox | `systemctl stop netbox` une minute | `start` |
| PKI | `systemctl stop step-ca` une minute (aucun renouvellement prévu dans la minute ; vérifie `list-timers`) | `start` |

Dans le journal : `journalctl -t ms-alerte -o cat --since -1h` → `ÉCHEC ms-verif-services.service sur adm01 …` suivi des lignes `KO`.

*6.* [Extrait de `docs/astreinte.md`](fichiers/M06-E29/outils/docs/astreinte-extrait.md) : une ligne par `KO`, dans l'ordre de dépendance (DNS d'abord).

**Explications**

Une sonde de **service** pose la question de l'utilisateur (« est-ce que je peux résoudre, obtenir un bail, joindre NetBox, faire confiance à ce certificat ? ») plutôt que celle de l'administrateur (« le processus tourne-t-il ? ») : un `pdns-recursor` actif qui ne peut plus joindre ses relais, un Kea en `partner-down`, un certificat valide mais à 3 jours de l'expiration, passent tous les contrôles de processus. Le principe de M02-E26 vaut doublement ici : l'absence de réponse n'est jamais une bonne nouvelle.

**Alternatives**
- Prometheus et ses *exporters* (blackbox_exporter pour DNS/HTTP/TLS, exporter Kea, exporter PowerDNS) : la cible du module 21 ; la sonde actuelle en préfigure les règles.
- Monit, Nagios/Icinga (*checks* tout faits) : une brique de plus à exploiter pour un gain limité à ce stade.
- Supervision du renouvellement lui-même (échec d'une unité `cert-renewer@`) en plus de l'expiration : complémentaire (alerte plus tôt) ; l'expiration reste le filet.

**Pièges classiques**
- Un `dig +short` qui ne renvoie rien considéré comme « pas d'erreur ».
- Vérifier l'expiration sans vérifier la chaîne et le nom (un certificat auto-signé valide 10 ans passe).
- Identifiants dans la ligne de commande de `curl` (visibles dans `ps`) ou dans le script installé.
- Une alerte toutes les 15 minutes pendant toute la durée d'un incident (fatigue d'alerte) : mémoriser l'état et n'alerter qu'au changement est le premier « pour aller plus loin ».
- Jeton NetBox « de lecture » qui hérite en fait des droits d'un administrateur (jeton créé pour son propre compte).

**En production chez MédiSphère**
Sondes reprises dans Prometheus (blackbox_exporter, module 21), alertes routées par Alertmanager vers l'astreinte avec déduplication et silences, tableau de bord des expirations de certificats, et revue mensuelle des alertes déclenchées (bruit, alertes manquées).

---

### M06-E30 — Durcir les services et mettre à jour la matrice des flux

**Solution**

Fichiers : rôle [`pare_feu_local`](fichiers/M06-E30/ansible/roles/pare_feu_local/), scénario [Molecule](fichiers/M06-E30/ansible/molecule/pare_feu_local/), variables ([communes](fichiers/M06-E30/ansible/inventories/lab/group_vars/socle/pare_feu_local.yml), [`dns01`](fichiers/M06-E30/ansible/inventories/lab/host_vars/dns01/pare_feu_local.yml), [`dns02`](fichiers/M06-E30/ansible/inventories/lab/host_vars/dns02/pare_feu_local.yml), [`ca01`](fichiers/M06-E30/ansible/inventories/lab/host_vars/ca01/pare_feu_local.yml), [`nbx01`](fichiers/M06-E30/ansible/inventories/lab/host_vars/nbx01/pare_feu_local.yml)), [`playbooks/pare-feu-local.yml`](fichiers/M06-E30/ansible/playbooks/pare-feu-local.yml), matrice complète de `gw01` après le module ([`host_vars/gw01/pare_feu.yml`](fichiers/M06-E30/ansible/inventories/lab/host_vars/gw01/pare_feu.yml)), [drop-in de confinement de step-ca](fichiers/M06-E30/ansible/roles/step_ca/files/20-durcissement.conf), [tableau des réglages attendus](fichiers/M06-E30/durcissement-services.md), [`docs/socle/matrice-flux.md`](fichiers/M06-E30/medisphere/docs/socle/matrice-flux.md).

*1. Constat* (exemple depuis `runner01`, avant) :

```
admin@runner01:~$ nmap -sT -p- --open 10.10.20.10 10.10.20.13
Nmap scan report for dns01.par1.medisphere.internal (10.10.20.10)
22/tcp   open  ssh
53/tcp   open  domain
5300/tcp open  mmcc
8004/tcp open  unknown
8001/tcp open  vcom-tunnel
8081/tcp open  blackice-icecap
Nmap scan report for nbx01.par1.medisphere.internal (10.10.20.13)
22/tcp  open  ssh
80/tcp  open  http
443/tcp open  https
```

(PostgreSQL et Valkey n'apparaissent pas sur `nbx01` si elles écoutent bien sur la boucle locale, ce que Debian fait par défaut : à vérifier avec `ss -tlnp`, pas à supposer.)

*2. Les services d'abord* : le [tableau](fichiers/M06-E30/durcissement-services.md) résume l'état attendu ; la plupart des réglages sont déjà dans les rôles (E24, E25, E27). Points souvent oubliés : `webserver-allow-from` de PowerDNS (pas `0.0.0.0/0`), `incoming.allow_from` du récurseur (sinon résolveur ouvert à PAR2 et au VPN sans contrôle), `ALLOWED_HOSTS` de NetBox (pas `*`), absence d'API sur `dns02`. Confinement systemd : `systemd-analyze security step-ca.service` avant/après le [drop-in](fichiers/M06-E30/ansible/roles/step_ca/files/20-durcissement.conf) (exemple : 9,2 « UNSAFE » → 2,1 « OK » ; ta valeur dépend de l'unité installée en E02). Les unités de PowerDNS et Kea fournies par les paquets sont déjà largement confinées : on les mesure, on ne les touche pas sans raison.

*3. Le filtrage local* : [`pare_feu_local`](fichiers/M06-E30/ansible/roles/pare_feu_local/) reprend le mécanisme de M04-E17 (validation `nft -c`, minuterie de retour armée, confirmation par une **nouvelle** connexion SSH et des ports testés depuis le contrôleur) et les conventions de la matrice (filtre `medisphere.socle.regle_nft`, motif + référence). Deux garde-fous : refus de s'appliquer à `gw01`, et refus d'un jeu de règles sans flux SSH explicite. Points de vigilance des règles :
- les requêtes DHCP relayées arrivent de **10.10.20.1** (adresse de `gw01` dans INFRA, port source 67), pas de 10.10.99.1 ; les renouvellements *unicast* arrivent du VLAN 99 (port source 68) ;
- `ca01` doit joindre le port 80 des hôtes qui obtiennent un certificat ACME (défi HTTP-01) ;
- les ports vérifiés depuis le contrôleur doivent être ouverts **depuis `runner01`** (le pipeline) autant que depuis `adm01`, sinon le pipeline déclenche le retour arrière à chaque passage : d'où `53` et `8081` sur `dns01`, pas `5300` ni `8004`.

Ordre d'application : `dns02`, `ca01`, `nbx01`, puis `dns01` dans un jeu séparé.

*4. La matrice de `gw01`* : ajouts (DNS et DHCP de `dns02`, sauvegardes, NTS et défi ACME de `gw01` selon M06-E21) ; aucun flux supprimé, mais les règles « vers dns01 » de M00-E13/E14 sont réécrites « vers dns01 et dns02 » ; `sem01` (M04-E28, détruite) retirée de la règle SSH de `runner01`. La CRL et l'ACME n'ajoutent rien sur `gw01` : MGMT et le VPN joignent déjà INFRA, et aucune VM sandbox n'a besoin de `ca01`.

*5. La preuve* (après) :

```
admin@runner01:~$ nmap -sT -p 22,53,5300,8004,8001,8081 10.10.20.10
PORT     STATE    SERVICE
22/tcp   open     ssh
53/tcp   open     domain
5300/tcp filtered mmcc
8004/tcp filtered unknown
8001/tcp filtered vcom-tunnel
8081/tcp open     blackice-icecap
```

`filtered` (politique `drop`) et non `closed` : le scanner n'obtient même pas de refus. Les flux légitimes sont testés un par un (le check E30 en fait une partie). [`matrice-flux.md`](fichiers/M06-E30/medisphere/docs/socle/matrice-flux.md) renvoie au code pour chaque type de passage et liste les flux ajoutés par le module.

**Explications**

Un pare-feu central ne filtre que ce qui le traverse. Dans un VLAN « à plat », le seul contrôle entre deux hôtes est celui de chaque hôte : sans lui, la compromission de `runner01` (qui exécute du code de pipeline, donc la cible la plus probable du socle) donne un accès direct à l'API de PowerDNS, au socket de Kea et à la base de NetBox. Le filtrage local est la défense en profondeur classique ; la micro-segmentation (pare-feu Proxmox par VM, ou politiques réseau de Kubernetes au module 15) en est la version centralisée. La règle d'or reste de corriger d'abord **à la source** : un service qui n'écoute pas n'a pas besoin d'être filtré.

**Alternatives**
- Pare-feu Proxmox au niveau des VMs (groupes de sécurité par rôle) : centralisé et indépendant de l'invité (une VM compromise ne peut pas le désactiver) ; à combiner plutôt qu'à opposer, mais attention à l'activation globale (M00-E27).
- VLAN dédié par service (DNS, PKI, NetBox) : chaque flux traverse `gw01` ; plus de VLANs à gérer, routage de tout le trafic socle.
- `ufw`/`firewalld` : surcouches lisibles, mais une syntaxe de plus ; nftables est déjà l'outil du socle.

**Pièges classiques**
- Oublier `ct state established,related accept` : les réponses aux requêtes sortantes de l'hôte (DNS amont, NTP, PBS) sont bloquées.
- Filtrer le DHCP relayé sur 10.10.99.1 au lieu de 10.10.20.1.
- Vérifications du rôle impossibles depuis le pipeline → retour arrière permanent, incompréhensible.
- Appliquer à `dns01` et `dns02` en même temps.
- Une règle `ip saddr` dans une table `inet` qui oublie l'IPv6 : sans conséquence ici (pas d'IPv6 dans le lab), à retenir pour plus tard.
- Mettre à jour la matrice de `gw01` sans scanner : la matrice dit ce qu'on veut, le scan dit ce qui est.

**En production chez MédiSphère**
Filtrage local sur tous les hôtes du socle (le rôle s'étend à `git01`, `runner01`, `s3-01`), scan de conformité hebdomadaire comparé à la matrice (écart = alerte), journalisation des rejets centralisée (module 22), et revue semestrielle de la matrice avec la RSSI.

---

### M06-E31 — ADR : flux d'autorité autour de la source de vérité

**Exemple de rédaction** : [`ADR-0060-flux-autorite-source-de-verite.md`](fichiers/M06-E31/ADR-0060-flux-autorite-source-de-verite.md). D'autres décisions sont défendables (l'option 2, « tout en Git », l'est pour une équipe très orientée code) : ce qui compte est la cohérence du tableau, le sens unique de chaque flux et le traitement honnête des écarts.

**Grille d'auto-évaluation** (Karim relit comme une MR ; 2 points par ligne, 20 au total, acceptable à 14)

| Critère | 0 | 1 | 2 |
|---|---|---|---|
| Gabarit MADR, deux pages | absent | partiel | complet, se lit sans contexte |
| Tableau information → source → écrivain → copies | absent | moins de 8 informations | 10 informations ou plus, dont MAC, bail et certificat |
| Un seul écrivain automatique par information | non | quelques exceptions non justifiées | oui, ou exceptions justifiées |
| Options | une seule | deux, ou options factices | trois réelles, pour et contre honnêtes |
| Schéma des flux | absent | flux bidirectionnels ambigus | sens unique, qui écrit et qui lit |
| Cas Karim/Julien rejoué | absent | décrit sans mécanisme | mécanisme qui l'empêche (droits, propriété des objets) |
| Écarts | non traités | détection seulement | détection, décision, alerte, correction **à la source** |
| Suppression | non traitée | « on supprime » sans garde-fou | règle explicite (statut, étiquette, pas de suppression automatique) |
| Droits et jetons | absents | cités | rattachés au registre des secrets, moindre privilège |
| Conséquences négatives et actions | absentes | listées sans suite | actions rattachées à des modules ou datées |

**Pièges classiques**
- Écrire « NetBox est la source de vérité » sans dire **de quoi** : Proxmox reste la vérité de ce qui tourne, Kea celle des baux.
- Synchronisation bidirectionnelle « pour être sûr » : c'est la cause de l'incident.
- Supprimer automatiquement dans NetBox ce qui a disparu de Proxmox : une VM arrêtée par erreur efface son intention.
- Oublier que NetBox indisponible ne doit pas arrêter le DNS ni le DHCP.

---

### M06-E32 — Questions de production : services d'infrastructure

1. **Ancienne adresse** : au pire TTL de l'enregistrement (3 600 s) **par niveau de cache** : le cache du récurseur (`dns01`/`dns02`) et celui du client (systemd-resolved, `nscd`, cache d'une application ou d'une JVM qui ignore le TTL). Si un client a demandé le nom juste avant le changement, il peut garder l'ancienne réponse 1 h, et un récurseur qui l'a mise en cache aussi : en pratique jusqu'à ~1 h (TTL), davantage avec des caches applicatifs. Le TTL négatif (*minimum* du SOA, 300 s) concerne un **nouveau** nom demandé avant sa création. La veille : baisser le TTL de l'enregistrement à 60-300 s (et attendre l'ancien TTL pour que la baisse soit vue de tous), changer, vérifier, remonter le TTL. Option de secours : `rec_control wipe-cache nbx01.par1.medisphere.internal` sur les deux récurseurs.

2. **Réponse b.** La bibliothèque C interroge les serveurs dans l'ordre, attend `timeout` (5 s par défaut) avant de passer au suivant, et recommence `attempts` fois (2 par défaut) ; elle ne mémorise pas l'état entre deux processus (a : faux, pas de parallélisme ; c : faux, aucune mémoire ; d : faux, le second est bien utilisé). Avec `timeout:1 attempts:2`, le délai tombe à 1 s par serveur mort ; `rotate` répartit la charge entre les serveurs (round-robin) mais fait perdre la préférence pour `dns01`. systemd-resolved, lui, garde un « serveur courant » et en change dès qu'il ne répond pas : après un premier échec, les requêtes suivantes vont directement à `dns02`.

3. **Série du secondaire supérieure** : le secondaire ne transfère que si le numéro du primaire est **plus grand** (arithmétique RFC 1982, modulo 2³²). Ici il ne transfère plus rien : `dns02` sert des données plus récentes que `dns01`, les clients obtiennent des réponses différentes selon le serveur. Correction : porter le numéro de `dns01` au-dessus de celui de `dns02` (`pdnsutil zone increase-serial` répété, ou édition du SOA). Si l'écart est énorme ou si l'on doit « reculer », on utilise le saut RFC 1982 : ajouter 2³¹−1 en une ou deux étapes (le numéro « fait le tour »), en laissant le secondaire transférer entre les étapes ; ou, plus simple dans notre cas, supprimer la zone sur `dns02` et la redéclarer (transfert complet), au prix de quelques secondes sans la zone sur `dns02`.

4. **TSIG plutôt que filtrage par adresse** : une adresse source s'usurpe (en UDP surtout, et dans le même VLAN avec de l'usurpation ARP) ; TSIG authentifie chaque message par un secret partagé et protège son intégrité, avec une fenêtre de temps contre le rejeu. Il ne chiffre pas (la zone circule en clair) et n'authentifie que les **deux serveurs** (rien pour les clients). Fuite de `axfr-par1` : quiconque l'a peut transférer les zones depuis **n'importe quelle adresse** (TSIG contourne `allow-axfr-ips`) — fuite d'inventaire — et, si la même clé était acceptée pour les mises à jour, modifier des enregistrements (ce n'est pas le cas : `ddns-kea` est une autre clé). Actions : (1) nouvelle clé générée et mise en Vault ; (2) importée et associée sur les deux serveurs (pipeline) ; (3) ancienne clé supprimée (`pdnsutil tsigkey delete`) ; (4) vérification des transferts ; (5) recherche de la cause de la fuite et revue des journaux de transferts (`AXFR-out` vers des adresses inconnues) ; (6) mise à jour du registre des secrets.

5. **Signature expirée** : un RRSIG porte une période de validité (*inception*, *expiration*) ; hors de cette période, la signature ne prouve plus rien (sinon une réponse capturée resterait rejouable indéfiniment). Le validateur refuse : réponse *bogus*, SERVFAIL. Côté primaire, la signature en ligne renouvelle les RRSIG chaque semaine ; côté secondaire pré-signé, la zone doit être retransférée avant l'expiration des signatures : `SOA-EDIT` (INCEPTION-INCREMENT) fait évoluer le numéro de série avec les signatures, et le *refresh* du SOA (quelques heures) garantit que le secondaire le remarque bien avant les trois semaines de validité. Horloge d'un récurseur en avance de deux jours : les signatures émises « dans le futur » pour lui restent valides (*inception* passée), mais celles qui expirent dans moins de deux jours lui paraissent déjà expirées : SERVFAIL aléatoires sur les zones signées, y compris Internet. Le temps est une dépendance de sécurité (M00-E45, M06-E21).

6. **Réponse c.** L'ancre ne correspond plus à aucune DNSKEY publiée : la chaîne ne peut pas être validée, la zone est *bogus*, SERVFAIL pour les clients qui ne mettent pas `+cd` (a : faux, l'ancre sert à chaque validation ; b : faux, l'absence de `ad` correspond à une zone *insecure*, pas *bogus* ; d : faux, voir ci-dessous). RFC 5011 permet à un validateur de suivre automatiquement le roulement d'une clé (nouvelle KSK publiée et signée par l'ancienne, période d'attente de 30 jours) ; le Recursor ne met pas en œuvre RFC 5011 pour les ancres configurées (il gère l'ancre de la racine par ses mises à jour et le fichier `trustanchorfile`) : ⚠️ à vérifier dans la documentation de ta version ; dans tous les cas, notre procédure (RB-064) ne compte pas dessus.

7. **Lien coupé en `hot-standby`** : avec `max-unacked-clients: 0`, chaque serveur constate la perte de battements après `max-response-delay` et passe en `partner-down` : le standby se met à répondre **aussi**. Avec 10 : le standby surveille les requêtes que le relais lui envoie ; tant que les clients ne réessaient pas (le primaire leur répond), il ne bascule pas ; il ne bascule que si plus de 10 clients restent sans réponse au-delà de `max-ack-delay`. *Split brain* : deux serveurs distribuent la même plage sans se le dire, avec un risque d'adresse attribuée deux fois. Moins grave qu'il n'y paraît en `hot-standby` : la plupart des clients existants renouvellent auprès de **leur** serveur (`unicast` à T1) et gardent leur adresse ; seuls les nouveaux clients et les DISCOVER peuvent recevoir deux offres, et Kea vérifie ses propres baux. À la reconnexion, la synchronisation compare les baux ; les conflits sont rejetés (`max-rejected-lease-updates`) et doivent être traités à la main. D'où le choix à expliciter (fait en E25) et la valeur > 0 en production.

8. **Les deux serveurs tombent 8 h** (baux de 12 h, T1 à 6 h, T2 à 10,5 h) : les VMs déjà configurées gardent leur adresse ; à T1 elles tentent de renouveler en *unicast* (échec, rien de grave), à T2 en *broadcast* (échec) ; elles ne perdent l'adresse qu'**à la fin du bail** (12 h). Une VM dont le bail a été obtenu 5 h avant la panne arrive à fin de bail 7 h après le début de la panne : elle perd son adresse avant le retour (8 h). Les VMs qui démarrent pendant la panne n'obtiennent rien (pas d'adresse, ou une adresse APIPA selon l'OS). Leçon : la durée des baux est un **RTO** du DHCP ; des baux plus longs donnent plus de marge, au prix d'une plage qui se libère plus lentement.

9. **Bail envoyé au pair avant la réponse** : si le serveur répondait d'abord et tombait juste après, le pair ignorerait ce bail et pourrait l'attribuer à un autre client : doublon d'adresse. La synchronisation préalable garantit que tout bail confirmé au client existe sur les deux serveurs. Coût : un aller-retour HTTP(S) entre pairs par DHCPREQUEST (quelques millisecondes en local, davantage entre sites ; le *parking* des paquets le rend transparent pour le client). `delayed-updates-limit` autorise, quand le pair est injoignable (état `communication-interrupted` en `load-balancing`), à accumuler un nombre limité de mises à jour à envoyer plus tard plutôt que de bloquer : ⚠️ à relire dans la documentation de Kea 3.0 (le paramètre s'applique au mode `load-balancing`).

10. **Réponse b.** Avec un renouvellement à 15 jours de l'expiration et une alerte à 10 jours, l'astreinte dispose de **10 jours** entre l'alerte et l'expiration (et l'échec de renouvellement s'est produit 5 jours avant l'alerte). Avec le seuil par défaut (66 % de 30 jours = renouvellement à 10 jours de l'expiration), le renouvellement et l'alerte tombent **au même moment** : on alerte sur un certificat qui est peut-être en train d'être renouvelé, puis, s'il a échoué, la marge n'est plus que celle du seuil d'alerte… et l'alerte arrive sans le préavis qu'elle était censée donner (a : faux ; c : inversé ; d : faux).

11. **CRL, OCSP, durées courtes** : la CRL est une liste signée, téléchargée et mise en cache par le client (simple, mais grosse et datée) ; OCSP interroge un répondeur pour **un** certificat (frais, mais requête à chaque connexion, fuite de vie privée, et en cas d'indisponibilité les clients « échouent ouvert ») ; l'agrafage OCSP fait fournir la réponse OCSP par le serveur (corrige la vie privée et la latence, peu déployé). Les durées courtes n'exigent rien du client. Les navigateurs et le CA/Browser Forum vont vers des durées de plus en plus courtes (ballot SC-081 : 200 jours en 2026, 100 jours en 2027, **47 jours en mars 2029**) et Let's Encrypt a arrêté son service OCSP en 2025. Pour une PKI interne, c'est un encouragement à l'automatisation complète (ACME partout) : à 47 jours, aucun renouvellement manuel ne tient.

12. **Intermédiaire compromis** : (1) arrêter `step-ca` (plus d'émission ni de renouvellement) ; (2) cérémonie avec la racine hors ligne : nouvel intermédiaire, nouvelle clé ; (3) révoquer l'ancien intermédiaire dans une CRL signée par la racine et la publier ; (4) redémarrer `step-ca` avec le nouvel intermédiaire ; (5) TLS : réémettre **tous** les certificats (pipeline, ACME) — les anciens restent valides pour les clients qui ne lisent pas la CRL, d'où l'urgence ; (6) SSH : les clés de la CA SSH sont-elles compromises aussi (même disque) ? Si oui, nouvelles clés de CA SSH, redistribution de `@cert-authority` et `TrustedUserCAKeys` par Ansible, réémission des certificats d'hôte et d'utilisateur ; (7) post-mortem. Racine hors ligne : **aucune** ancre de confiance à changer sur les hôtes, l'incident se règle côté serveur. Avec une racine en ligne compromise : nouvelle PKI complète, ancre à remplacer partout (période de recouvrement comme en E03), certificats clients à réémettre.

13. **Départ à 10 h, certificats de 16 h** : un certificat émis à 8 h vaut jusqu'à minuit : le collaborateur peut se connecter jusqu'à 14 h de plus si on ne fait rien (s'il a encore son poste et sa clé). Mieux : désactiver son identité à la source (il ne peut plus **obtenir** de certificat le lendemain), `step ssh revoke` (pas de renouvellement), et surtout une **KRL** (`ssh-keygen -k` produit une liste de révocation binaire par clé, numéro de série ou identifiant) distribuée dans `RevokedKeys` de sshd par Ansible : effet immédiat. Les durées courtes font le reste.

14. **NetBox indisponible 2 h** : rien n'est touché **immédiatement** dans le plan de données : DNS, DHCP, certificats, SSH fonctionnent (ils ne consultent pas NetBox). Sont bloqués : la création d'une VM par OpenTofu (allocation d'adresse), l'inventaire Ansible (si l'inventaire NetBox est le seul : d'où l'intérêt de garder l'inventaire Proxmox en secours), les synchronisations. NetBox est un **plan de contrôle** : sa disponibilité conditionne les changements, pas le service ; on peut donc viser une disponibilité moindre (sauvegarde restaurée en 30 min, E28) que pour le DNS (redondé, E24).

15. **Relais vers les deux en `hot-standby`** : nécessaire, pas seulement pratique. (a) En `partner-down`, le standby doit **recevoir** les requêtes pour y répondre : si le relais n'envoie qu'à `dns01`, la bascule de Kea est inutile, aucun client ne joint `dns02`. (b) Avec `max-unacked-clients` > 0, le standby détecte un primaire muet en observant le trafic que le relais lui envoie. Un relais qui n'envoie qu'à `dns01` ferait de `gw01` le vrai point unique de défaillance du DHCP.

16. **Troisième site** : rendent l'extension simple — zones par site (`par3.medisphere.internal`), secondaires par AXFR (ajouter un secondaire = une adresse dans `also-notify` et une clé, ou une zone catalogue), NetBox modélisé par site, ACME (n'importe quel hôte du nouveau site obtient un certificat), certificats SSH (une ancre `@cert-authority *.medisphere.internal` couvre tout). La compliquent — ancres DNSSEC par zone (une de plus à distribuer, sauf si on passe à une zone parente signée unique), HA Kea limitée à une paire par relation (une paire par site, ou `load-balancing` avec un `backup`), CA unique à PAR1 (un site isolé ne peut plus renouveler : prévoir une durée qui couvre une coupure, ou un intermédiaire par site signé par la même racine), et le temps (sources NTS locales).

---

### M06-E33 — Rédiger la politique de certification de la PKI

**Exemple de rédaction** : [`politique-certification.md`](fichiers/M06-E33/politique-certification.md). Les valeurs entre chevrons sont celles de **ton** `ca01` (durées des autorités, mécanismes d'amorçage SSH choisis en E19/E20) : une politique qui ne dit pas la vérité sur la configuration est pire que pas de politique.

**Grille de relecture « Sophie »** (2 points par ligne, 20 au total ; acceptable à 14, aucun 0 sur les lignes marquées *)

| Critère | 0 | 1 | 2 |
|---|---|---|---|
| Périmètre et hors-périmètre * | absent | périmètre seul | les deux, avec les usages |
| Rôles et séparation des tâches * | absent | rôles listés | deux porteurs de la racine, opérateurs, auditeur, séparation explicite |
| Hiérarchie et protection des clés * | absente | autorités listées | DN, algorithmes, durées, emplacement et protection de chaque clé |
| Émission | absente | « par ACME » | par type : mécanisme, preuve, demandeur |
| Durées et renouvellement * | absentes | durées seules | tableau identique à `ca.json`, seuil, supervision |
| Révocation * | absente | « on révoque » | motifs, décideur, délais, mécanismes **et leurs limites** |
| Continuité | absente | sauvegarde citée | sauvegarde, cérémonies, compromission, perte de la racine |
| Contrôle | absent | journaux cités | journaux, durée, revue, indicateurs |
| Honnêteté | limites cachées | une limite citée | limites écrites avec la compensation |
| Gestion du document | absente | version | version, propriétaire, revue, historique |

**Pièges classiques**
- Recopier un modèle de politique publique (obligations envers des tiers, assurance, tarifs) : illisible et faux.
- Promettre ce que la configuration ne fait pas (« OCSP disponible », « clé de l'intermédiaire en HSM »).
- Mélanger politique et procédure : les commandes vont dans les runbooks.
- Oublier les certificats SSH, qui sont aussi émis par `ca01`.

---

### M06-E34 — Un nouveau service complet en temps limité

Exercice chronométré : pas de corrigé à consulter pendant l'épreuve. Après coup, compare ta solution à celle-ci et remplis la [grille](fichiers/M06-E34/grille-chrono.md).

**Solution de référence**

Fichiers : [`envs/lab-m06/stat01.tf`](fichiers/M06-E34/infra/envs/lab-m06/stat01.tf), rôle [`statut`](fichiers/M06-E34/ansible/roles/statut/), [`host_vars/stat01/certificats.yml`](fichiers/M06-E34/ansible/inventories/lab/host_vars/stat01/certificats.yml), [`host_vars/stat01/pare_feu_local.yml`](fichiers/M06-E34/ansible/inventories/lab/host_vars/stat01/pare_feu_local.yml), [`playbooks/statut.yml`](fichiers/M06-E34/ansible/playbooks/statut.yml), [ligne de supervision](fichiers/M06-E34/outils/etc/ms-verif-services.conf.diff).

1. **T0 → T1** : état OpenTofu **séparé** (`envs/lab-m06`) — un `tofu destroy` du service temporaire ne peut pas toucher le socle. Module `vm-debian` v2 de M06-E13 avec `plage_adresses` (une adresse contenue dans la plage statique INFRA) au lieu d'`ipv4_imposee` : le module demande à NetBox la première adresse libre de la plage (10.10.20.17 sur un socle conforme au PLAN, puisque .10 à .16 sont prises), l'enregistre, puis crée la VM (clone complet, pool `lab` par défaut). Module `enregistrement-dns` de M06-E14 pour A et PTR, avec un TTL court (service temporaire).
2. **T1 → T2** : MR, pipeline, `apply`. L'hôte apparaît dans l'inventaire (étiquette `role-statut` → groupe `role_statut`), sa clé d'hôte est signée par le rôle `ssh_ca_hote` au premier passage.
3. **T2 → T3** : le certificat est une entrée de plus pour le rôle `certificats_acme` de M06-E18 (identifiant `statut`, groupe `www-data`) : émission en mode autonome, nginx arrêté le temps du défi (`avant_emission`/`apres_emission`, sans effet au premier passage où nginx n'existe pas encore), renouvellement par `cert-renewer@statut` avec le seuil de 15 jours de E27, sans aucun code nouveau. Puis le rôle `statut` : il vérifie que le certificat est là, installe nginx, dépose la page telle quelle et le site (HTTPS, TLS 1.2 minimum, port 80 réduit à la redirection). `pare_feu_local` : 443 depuis MGMT, VPN, INFRA ; 80 depuis `ca01`.
4. **T3 → T4** : une ligne dans `etc/ms-verif-services.conf` (MR sur `plateforme/outils`, `task install:systeme` sur `adm01`) ; décision de sauvegarde : **aucune sauvegarde applicative** — le service n'a pas de données propres (page et configuration dans Git), la VM est de toute façon couverte par `lab-nuit` (pool `lab`).
5. **T5** : `lab/bin/check 06 34`.
6. **T6** : MR inverse sur `outils`, `tofu destroy` de l'environnement (VM, objets NetBox, enregistrements DNS en une fois), vérification : `qm status 2069` (absente), `dig @10.10.20.10 stat01.par1.medisphere.internal` (NXDOMAIN, aussi sur `dns02`), NetBox (aucune VM `stat01`, adresse libérée).

**Aucune règle `gw01`** (exigence 7) : MGMT joint tout le lab, le VPN d'administration joint le port 443 d'INFRA (M06-E20) ; SANDBOX ne doit pas joindre la page, et c'est le comportement par défaut. Ajouter une règle « pour être sûr » serait une erreur de matrice.

**Retour d'expérience type** : ce qui coûte le plus de temps la première fois, c'est l'ordre nginx/ACME et les droits de la clé ; les gestes manuels typiques (à outiller) : relancer le pipeline Ansible à la main après l'`apply` OpenTofu (un déclencheur de pipeline en aval le ferait), installer la configuration de la sonde sur `adm01` (un rôle `adm01` le ferait), vérifier l'adresse attribuée dans l'interface de NetBox (la sortie `stat01_ipv4` suffit). Descendre sous une heure : un « gabarit de service » (module OpenTofu + rôle Ansible paramétrés) qui produit tout le reste ; c'est le chemin vers le catalogue de services du module 28.

**Pièges classiques**
- Écrire l'adresse à la main « parce que c'est plus rapide » : c'est précisément ce que l'exercice mesure.
- Mettre la VM dans l'état `socle` : son retrait devient un `tofu destroy -target`, risqué.
- Oublier l'étiquette de rôle : l'hôte n'apparaît dans aucun groupe, le playbook ne le voit pas.
- Émission ACME en mode autonome avec nginx déjà lancé (port 80 occupé) : d'où l'arrêt de nginx le temps du défi.
- Laisser des traces au retrait : ligne de supervision (alerte toutes les 15 minutes dès le lendemain), objets NetBox (adresse « prise » pour toujours), enregistrement PTR orphelin.
