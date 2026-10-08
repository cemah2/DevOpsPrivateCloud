# Module 07 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les fichiers complets sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `fichiers/M07-EXX/ansible/…` = chemins de `plateforme/ansible`, `…/infra/…` = `plateforme/infra`, `…/outils/…` = `plateforme/outils`, `…/medisphere/…` = la documentation ; `pve01/`, `gw01/`, `hap01/`, `net01/` = fichiers posés à la main sur ces hôtes. On **superpose** les dossiers dans l'ordre (palier 1, puis E10, E11…) : un fichier d'un exercice plus récent remplace le précédent. Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête), les `*.exemple` des modèles sans valeur réelle. Les rôles `frr`, `keepalived` et `nginx_web` sont ceux du palier 1 (M07-E06/E07, M07-E08) : ce palier n'en change que les **données**.

**Ce qui a été testé, ce qui ne l'a pas été.**
- *Rendu des modèles* (ansible-core 2.21) avec les variables du corrigé, puis validation par l'outil de chaque service : `vtysh --dryrun` (**FRR 10.7.1**) sur les configurations de `spine01`, `leaf01`, `srv01` (E14), `gw01` et `leaf01` (E16), `gw01` et `lyo-gw01` (E19), et sur `frr-bordure.conf.propose` (E23) ; `haproxy -c` sur `hap01` (E10, E11) et les répartiteurs (E12, E13) avec **HAProxy 2.8** (la 3.2 n'était pas installable dans l'environnement de rédaction : directives choisies parmi celles qui existent depuis 2.2 au moins, ⚠️ à revalider sur ta 3.2) ; `keepalived -t` (**keepalived 2.2.8**) sur le rendu de l'instance des répartiteurs ; `nft -c` sur la matrice complète de fin de palier (rôle `pare_feu`, modèle M07-E13, filtre `regle_nft`).
- *Profil `datacenter` de FRR* : lu dans le module YANG de déviations embarqué dans `bgpd` 10.7.1 : `ebgp-requires-policy` à `false`, temporisateurs 3/9 s, `connect-retry` 10 s, `deterministic-med` à `false`, `import-check` à `true`.
- *ansible-lint* (profil `production`) sur les rôles `haproxy`, `wireguard`, `routes_statiques`, la tâche `emettre.yml` de `certificats_acme`, les playbooks et scénarios Molecule du palier, avec les rôles du palier 1 : aucune erreur. *ShellCheck* 0.11 et `bash -n` : checks, `ms-diag-chemin`, scripts de `pve01`, `gw01`, `net01`.

**Non rejoués sur un lab réel** : tout ce qui demande les VMs (sessions BGP établies, ECMP effectif, bascules VRRP, émission ACME relayée, DNAT, MTU 9000 dans les invités, LACP entre veth). Points signalés « ⚠️ À confirmer » dans le texte : signale tes retours.

---

### M07-E10 — Répartir un service HTTP avec HAProxy

**Solution**

Fichiers : rôle [`haproxy`](fichiers/M07-E10/ansible/roles/haproxy/) (`defaults`, `tasks/main.yml`, `tasks/depot.yml`, `handlers`, `templates/haproxy.cfg.j2`, `meta`), [`host_vars/hap01/haproxy.yml`](fichiers/M07-E10/ansible/inventories/lab/host_vars/hap01/haproxy.yml), [`group_vars/all/depots.yml.extrait`](fichiers/M07-E10/ansible/inventories/lab/group_vars/all/depots.yml.extrait), [`playbooks/m07-hap01.yml`](fichiers/M07-E10/ansible/playbooks/m07-hap01.yml), scénario [`molecule/haproxy`](fichiers/M07-E10/ansible/molecule/haproxy/), [`maquette.tf.extrait`](fichiers/M07-E10/infra/envs/m07-maquette/maquette.tf.extrait).

1. **Empreinte de la clé.**
   ```
   admin@adm01:~$ curl -fsSL https://haproxy.debian.net/haproxy-archive-keyring.gpg -o /tmp/haproxy.gpg
   admin@adm01:~$ gpg --show-keys --with-fingerprint /tmp/haproxy.gpg
   ```
   Seconde source : la page d'accueil du dépôt (instructions par version), l'annonce sur la liste `haproxy@formilux.org`, ou un serveur de clés interrogé par l'identifiant long. L'empreinte (40 caractères, sans espace, en majuscules) va dans `group_vars/all/depots.yml` ; le rôle refuse de continuer si la clé téléchargée ne la porte pas (même méthode que Kea, M06-E16).
2. **Le rôle.** Les choix qui comptent :
   - `global` et `defaults` sont **dans le modèle** (communs à tous les hôtes : journal, chroot, socket, versions TLS) ; les sections de l'hôte sont une **liste de lignes** (`haproxy_sections`). Modéliser chaque directive d'HAProxy en YAML coûterait cher pour rien : la configuration reste lisible, et `haproxy -c` la valide entière.
   - `validate: haproxy -c -f %s` : un rendu invalide n'est jamais posé ; le gestionnaire **recharge** (`systemctl reload haproxy`) : en mode maître-processus (`haproxy -Ws`, unité du paquet), de nouveaux processus prennent la configuration, les anciens finissent leurs connexions.
   - `log stdout format short local0 info` : journal dans `journalctl -u haproxy`, sans rsyslog ni `/dev/log` dans le chroot.
   - contrôle final sur le **service rendu** : `show info` par la socket donne la version chargée (`Version: 3.2.…`).
   - sections `tls: true` rendues seulement si un certificat existe (prévu pour E11 : voir ci-dessous).
3. **Molecule** : `nginx_web` (rôle de E08) sur le port 8080 de l'instance comme serveur ; `verify.yml` vérifie service, version 3.2, serveur `UP` (champ 18 de `show stat`), absence du frontend TLS sans certificat (amorçage), droits de la configuration (0640, groupe `haproxy`), refus d'une directive inconnue par `haproxy -c`.
4. **`hap01`** : entrée `hap01` dans `local.vms` de `maquette.tf`, `tofu apply` ; la VM est dans le groupe `m07_hap` de l'inventaire Proxmox. `host_vars/hap01/haproxy.yml` : section `resolvers lab` (dns01, dns02), `fe_web` sur `:80` avec `option forwardfor`, `be_web` (contrôle `http-check send meth GET uri /sante ver HTTP/1.1 hdr Host …`, `expect status 200`, `default-server inter 2s fall 3 rise 2 resolvers lab init-addr last,libc,none`), `listen stats` sur `127.0.0.1:8404`.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook -i inventories/lab/proxmox.yml playbooks/m07-hap01.yml
   ```
5. **Répartition** : les six réponses alternent `X-Serveur: srv01` / `srv02`. Dans `show stat`, `be_web/srv01` et `srv02` : `UP`, `L7OK`.
6. **Panne d'un serveur.** Nginx arrêté sur `srv01` : le contrôle suivant échoue en `L4CON` (connexion refusée) ; au troisième échec (≈ 4 à 6 s), `srv01` passe `DOWN` (`Server be_web/srv01 is DOWN, reason: Layer4 connection problem` dans le journal). **Entre-temps**, une requête sur deux part vers `srv01` : la connexion est refusée et HAProxy réessaie (`retries 3` par défaut, sur le **même** serveur sans `option redispatch`) puis renvoie 503 au client. Avec une requête toutes les 0,5 s, compter 4 à 6 erreurs. Au retour de Nginx : deux contrôles réussis (≈ 2 à 4 s) et `srv01` est `UP`. Ajouter `option redispatch 1` fait réessayer **ailleurs** dès le premier échec de connexion : plus aucune erreur visible pour un serveur arrêté proprement.
7. **Drain et maintenance.**
   ```
   admin@hap01:~$ echo "set server be_web/srv02 state drain" | sudo socat stdio unix-connect:/run/haproxy/admin.sock
   admin@hap01:~$ echo "show servers state be_web" | sudo socat stdio unix-connect:/run/haproxy/admin.sock
   ```
   `drain` : plus aucune **nouvelle** connexion (sauf persistance par cookie), les connexions en cours continuent, les contrôles de santé continuent (le serveur reste « vivant » aux yeux d'HAProxy). `maint` : plus aucune nouvelle connexion, contrôles **arrêtés**, et le serveur est signalé en maintenance dans les statistiques. Pour un client déjà connecté : rien ne change dans les deux cas (HAProxy ne coupe pas une connexion établie, sauf `shutdown sessions server`). `state ready` remet en service. L'état posé par la socket **ne survit pas** à un redémarrage (rechargement : oui, s'il est conservé par `server-state-file`, non configuré ici).
8. **Journal.** Exemple :
   ```
   … fe_web be_web/srv01 0/0/1/2/3 200 312 - - ---- 1/1/0/0/0 0/0 "GET / HTTP/1.1"
   ```
   `TR/Tw/Tc/Tr/Ta` = 0/0/1/2/3 ms : attente de la requête complète, file d'attente, connexion au serveur, réponse du serveur (en-têtes), durée totale. `----` : terminaison normale. `sC--` : délai de connexion au serveur dépassé (`s` = côté serveur, `C` = pendant la connexion) ; `SC--` : le **serveur** a refusé ou fermé la connexion pendant son établissement (`S`), typiquement un RST d'un Nginx arrêté ; `SH--` : le serveur a coupé pendant l'envoi des en-têtes.

**Explications**

Un contrôle de santé **actif** est une requête périodique, indépendante du trafic : HAProxy sait qu'un serveur est mort avant qu'un client ne le découvre, et le sait encore quand plus aucun client n'arrive. `fall`/`rise` évitent l'oscillation sur une erreur isolée ; le prix est un délai de détection (`inter × fall`). Un contrôle de niveau 7 (`option httpchk`) attrape ce qu'un contrôle TCP ne voit pas : une application qui accepte les connexions mais répond 500. La section `resolvers` sert ici à suivre la reconstruction de la maquette (nouvelles adresses) : sans elle, un nom n'est résolu qu'au démarrage.

**Alternatives**
- *Configuration modélisée champ par champ* (frontends, ACL, serveurs en YAML) : utile pour générer des centaines de services identiques ; illisible pour quelques services hétérogènes.
- *Paquet Debian 3.0* : support plus long chez Debian, mais pas la branche LTS retenue (PLAN §6) ; la 3.4 LTS (dossier `conf.d`, backends dynamiques par la CLI) est une évolution à évaluer.
- *Page de statistiques sur le réseau* avec authentification : à réserver à MGMT et à protéger (E28).

**Pièges classiques**
- `server srv01 srv01.par1…:80` sans `check` : aucun contrôle, HAProxy envoie au serveur mort jusqu'à ce que les clients se plaignent.
- Oublier l'en-tête `Host` dans le contrôle : un serveur qui sert plusieurs sites (ou NetBox, E13) répond 400 au contrôle.
- `systemctl restart haproxy` au lieu de `reload` : toutes les connexions en cours sont coupées.
- Lire `show stat` avec `cut -d,` sans repérer les colonnes : l'en-tête (`# pxname,svname,…`) donne les numéros ; ils ne changent pas entre versions mineures, mais de nouvelles colonnes s'ajoutent en fin de ligne.
- Socket en `mode 666` (vu en E21) : n'importe quel compte local administre HAProxy.

**En production chez MédiSphère**
Contrôles alignés sur un vrai point de santé applicatif (base joignable, dépendances), `option redispatch` et `retry-on` réglés par service, état des serveurs exporté vers Prometheus (exportateur intégré, M21), journal envoyé à la collecte (M22) avec un format qui garde les temps et les codes de terminaison.

---

### M07-E11 — Nginx en reverse proxy : TLS et comparaison

**Solution**

Fichiers : [`emettre.yml`](fichiers/M07-E11/ansible/roles/certificats_acme/tasks/emettre.yml) (rôle `certificats_acme`, version E11) et [`defaults-main.yml.extrait`](fichiers/M07-E11/ansible/roles/certificats_acme/defaults-main.yml.extrait), [`host_vars/hap01/haproxy.yml`](fichiers/M07-E11/ansible/inventories/lab/host_vars/hap01/haproxy.yml) et [`certificats.yml`](fichiers/M07-E11/ansible/inventories/lab/host_vars/hap01/certificats.yml), [`playbooks/m07-hap01.yml`](fichiers/M07-E11/ansible/playbooks/m07-hap01.yml) (version E11), [`pare_feu.yml.extrait`](fichiers/M07-E11/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait), [`hap01/nginx-mandataire.conf`](fichiers/M07-E11/hap01/nginx-mandataire.conf).

1. **Flux** : une règle de transit `iifname ens19.20`, source `ca01`, sortie `ens19.99`, TCP 80 (« défi ACME HTTP-01 de ca01 vers la maquette »), à retirer avec la maquette (E46).
2. **Défi relayé.** `step ca certificate --http-listen <adresse:port>` fait écouter le serveur de défi temporaire ailleurs que sur `:80` (option prévue pour fonctionner derrière un mandataire) ; le rôle reçoit un champ facultatif `ecoute_http`, absent pour tous les hôtes existants (comportement de M06-E18 inchangé). HAProxy : `acl defi_acme path_beg /.well-known/acme-challenge/` et `use_backend be_acme if defi_acme`, `be_acme` = `server step 127.0.0.1:8402` sans contrôle (le serveur n'existe que pendant l'émission).
   **Amorçage** : le rôle `haproxy` cherche des `*.crt` dans `/etc/haproxy/certs` **avant** de rendre le modèle ; une section `tls: true` n'est rendue que s'il en trouve. Le playbook enchaîne `haproxy` (port 80 seul) → `certificats_acme` → `haproxy` (TLS). Solution générale, réutilisée telle quelle par les répartiteurs (E12). ⚠️ À confirmer : `--http-listen` sur ta version de step-cli (`step ca certificate --help`).
3. **TLS.** HAProxy : `bind :443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1` ; `ssl-load-extra-del-ext` (global) fait chercher `hap01.key` à côté de `hap01.crt` (sinon HAProxy cherche `hap01.crt.key`). Nginx : site posé à la main (`nginx-mandataire.conf`), `listen 8443 ssl`, mêmes fichiers (Nginx lit la clé en root au démarrage), site par défaut du paquet retiré pour libérer le port 80. Le rechargement après renouvellement : `systemctl try-reload-or-restart haproxy.service nginx.service` (ne fait rien à un service absent).
   ```
   admin@adm01:~$ R=/usr/local/share/ca-certificates/medisphere-root-ca.crt
   admin@adm01:~$ curl -sS --cacert $R -D - -o /dev/null https://hap01.par1.medisphere.internal/ | grep -i x-serveur
   admin@adm01:~$ curl -sS --cacert $R -D - -o /dev/null https://hap01.par1.medisphere.internal:8443/ | grep -i x-serveur
   ```
4. **Comparaison** (mesures typiques ; les tiennes peuvent différer de quelques requêtes) :

   | Critère | HAProxy 3.2 | Nginx 1.26 (libre) |
   |---|---|---|
   | Ce que voit `srv01` | source = `hap01`, `X-Forwarded-For` = client (`option forwardfor`) | idem (`proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for`) |
   | `srv01` arrêté, 1 requête/s | 0 à 3 erreurs avant `DOWN` (contrôle actif : 3 × 2 s) ; 0 avec `option redispatch` | **0 erreur** grâce à `proxy_next_upstream error` (rejoue ailleurs) mais **chaque** requête vers `srv01` paie une tentative de connexion, jusqu'à `max_fails` en `fail_timeout` |
   | Retour de `srv01` | 2 contrôles réussis (≈ 4 s), sans trafic | après `fail_timeout` (10 s), **au hasard d'une vraie requête** (pas de contrôle actif dans l'édition libre) |
   | Renouvellement du certificat | rechargement, connexions conservées | rechargement, connexions conservées |
   | État des serveurs sans journaux | `show stat`, `show servers state`, page de statistiques, exportateur Prometheus | `stub_status` (compteurs globaux), rien par serveur |
   | Retirer un serveur à chaud | `set server … state drain` (socket) | modifier la configuration et recharger |
5. **Réponse à Julien** (exemple) : « Sur le même service et le même certificat, les deux terminent TLS et transmettent l'adresse du client de la même façon. La différence est dans l'exploitation : HAProxy sait qu'un serveur est mort ou revenu sans attendre qu'un client le découvre, on peut retirer un serveur pour maintenance à chaud et voir l'état de chaque serveur sans lire de journaux ; Nginx libre ne fait que des contrôles passifs et se pilote par rechargement. Pour un point d'entrée partagé par plusieurs applications et des opérations de maintenance fréquentes, je recommande HAProxy (ADR-0071). Nginx reste le bon outil **derrière** : servir les fichiers statiques de MédiAgenda, faire du cache, et c'est lui que ton équipe continuera d'utiliser dans les conteneurs. »

**Explications**

Le défi HTTP-01 prouve qu'on contrôle le **nom**, donc ce qui répond sur le port 80 de l'adresse du nom : qu'un mandataire relaie la requête vers le vrai demandeur ne change rien à la preuve (c'est le même hôte). L'amorçage est le problème classique de la terminaison TLS automatisée : le service qui sert le défi ne doit pas dépendre du certificat qu'il permet d'obtenir.

**Alternatives**
- *DNS-01* (step-ca le permet) : pas de port 80, certificats possibles avant que le service n'existe ; il faut une clé d'écriture DNS (PowerDNS, TSIG) sur l'hôte : risque plus large.
- *Client ACME intégré à HAProxy 3.2* (section `acme`, aperçu technique) : plus d'outil externe ; trop jeune pour le socle.
- *Nginx Plus* ou Nginx ≥ 1.27.3 : `resolve` dans l'amont ; les contrôles actifs restent réservés à l'édition commerciale.

**Pièges classiques**
- Laisser le site `default` de Nginx : il prend le port 80, HAProxy ne démarre plus.
- `crt /etc/haproxy/certs/` sans `ssl-load-extra-del-ext` : « unable to load SSL private key » (HAProxy cherche `hap01.crt.key`).
- Ouvrir le port 80 de **tout** le VLAN 99 à **tout** INFRA « pour que ça marche ».
- Comparer les deux mandataires avec une requête par minute : les différences de détection sont invisibles ; il faut du trafic continu **et** du silence.

**En production chez MédiSphère**
Nginx n'est pas déployé sur les répartiteurs ; la comparaison et la réponse à Julien sont versées à l'ADR-0071. Le flux ACME vers la sandbox disparaît avec la maquette.

---

### M07-E12 — Déployer les répartiteurs `lb01` et `lb02`

**Solution**

Fichiers : [`socle/repartiteurs.tf`](fichiers/M07-E12/infra/socle/repartiteurs.tf), [`group_vars/role_lb/keepalived.yml`](fichiers/M07-E12/ansible/inventories/lab/group_vars/role_lb/keepalived.yml), [`haproxy.yml`](fichiers/M07-E12/ansible/inventories/lab/group_vars/role_lb/haproxy.yml), [`certificats.yml`](fichiers/M07-E12/ansible/inventories/lab/group_vars/role_lb/certificats.yml), `host_vars/lb01/lb.yml`, `host_vars/lb02/lb.yml`, [`playbooks/repartiteurs.yml`](fichiers/M07-E12/ansible/playbooks/repartiteurs.yml), [`site.yml.extrait`](fichiers/M07-E12/ansible/playbooks/site.yml.extrait), [`pare_feu.yml.extrait`](fichiers/M07-E12/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait), [`ADR-0071`](fichiers/M07-E12/medisphere/docs/socle/adr/ADR-0071-haproxy-points-entree.md).

1. **OpenTofu** (RB-060, étape 2) : `module "repartiteur"` (`for_each` sur lb01/lb02) avec `vm-debian` v2.1.0, `vnet = "vdmz"`, `reseau_prefixe = "10.10.70.0/24"`, `ipv4_imposee` ; `module "dns_repartiteur"` (A + PTR) ; la VIP : `netbox_ip_address` (10.10.70.200/24, `role = "vip"`, `dns_name = "lb.par1.medisphere.internal"`, sans interface : elle se déplace) et son nom par `enregistrement-dns`. Ordre de démarrage 3 posé en root (`qm set … --startup order=3`).
2. **Flux** (et seulement ceux-là) : `runner01` → `lb01`/`lb02` TCP 22 (pipeline Ansible) ; `lb01`/`lb02` → `ca01` TCP 443 (ACME, renouvellements TLS et SSH) ; `ca01` → `lb01`, `lb02`, VIP TCP 80 (défi). DNS, NTP, Internet et MGMT → DMZ existent déjà (`ens19.70` est dans `LAB_IFS`). VRRP et relais du défi entre répartiteurs restent **dans** le VLAN 70 : `gw01` ne les voit pas.
3. **keepalived** : le rôle de E08 suffit. `VI_DMZ`, `interface: eth0`, `vrid: 170`, `etat_initial: BACKUP`, `preemption: false`, `source: "{{ lb_adresse }}"`, `pairs` **calculés** (`groups['role_lb'] | difference([inventory_hostname]) | map('extract', hostvars, 'lb_adresse')`), `vips: [10.10.70.200/24]`, script `chk_haproxy` = `systemctl is-active --quiet haproxy.service` **sans poids** (FAULT ⇒ la VIP part). Priorités 150/100 en `host_vars`. **Sans préemption** : un `lb01` qui revient ne reprend pas la VIP (une coupure de moins) ; le retour est manuel (RB-070).
4. **HAProxy** : `fe_http` (`:80`, redirection 301 sauf défi), `fe_publication` (TLS, `/sante` répondu par HAProxy lui-même, `default_backend be_aucun` → 503), `be_acme` avec **les deux** répartiteurs (`retries 2`, `retry-on conn-failure`, `option redispatch 1`). Écoute sur **toutes** les adresses : chaque répartiteur se teste en direct (`curl --resolve`), y compris celui qui attend ; pas besoin de `net.ipv4.ip_nonlocal_bind` (indispensable, lui, si l'on n'écoute **que** la VIP : un BACKUP ne pourrait pas lier une adresse qu'il ne porte pas).
5. **Certificat** : par répartiteur, noms `lb.par1…` (premier : celui que demandent les clients) et `lbNN.par1…`, `ecoute_http: ":8402"`. Le défi passe par la VIP, donc par le maître ; `be_acme` envoie la requête vers l'un des deux ports 8402 ; celui qui n'écoute pas refuse (RST) et HAProxy réessaie sur l'autre. `repartiteurs.yml` : `serial: 1`, `order: sorted`, `any_errors_fatal`, puis un contrôle d'ensemble « une et une seule VIP portée ». ⚠️ À confirmer : comportement de `retry-on conn-failure` + `redispatch` quand le premier serveur choisi refuse la connexion (sinon, mettre le répartiteur demandeur en premier par `balance first`).
6. **Bascule mesurée** :
   ```
   admin@adm01:~$ while :; do printf '%s %s\n' "$(date +%T.%N | cut -c1-12)" \
       "$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 --cacert $R https://lb.par1.medisphere.internal/sante)"; sleep 0.2; done
   admin@lb01:~$ sudo systemctl stop haproxy
   ```
   Le script échoue deux fois (`interval 2`, `fall 2`) : 2 à 4 s d'erreurs, puis `lb02` prend la VIP (ARP gratuit) et répond. `systemctl start haproxy` sur `lb01` : `lb01` repasse BACKUP, la VIP **reste** sur `lb02` (pas de préemption). `qm shutdown 1010` (si `lb01` est maître) : keepalived s'arrête proprement et annonce une priorité 0 : bascule en moins d'une seconde. Un arrêt brutal (`qm stop`) : bascule après le délai de détection (3 × `advert_int` + temps de biais, ≈ 3,6 s).
7. **ADR-0071** : voir le fichier ; l'essentiel est dans « Décision » (cinq points vérifiables) et « Conséquences » (connexions coupées à la bascule, dépendance au DNS et à la PKI au démarrage).

**Explications**

VRRP élit un maître par priorité ; le maître annonce sa présence (`advert_int`) et répond à l'ARP pour la VIP ; les autres attendent `Master_Down_Interval` (3 × l'intervalle + biais) sans annonce avant de prendre la VIP. VRRP v3 n'a plus d'authentification (celle de v2 était un mot de passe en clair) : l'unicast et le filtrage protègent mieux. Les scripts de suivi lient la VIP à la **santé du service** : sans eux, keepalived garderait la VIP sur un hôte dont HAProxy est arrêté.

**Alternatives**
- *Préemption avec délai* (`preempt_delay 60`) : la VIP revient seule sur `lb01` une minute après son retour (deux bascules au lieu d'une).
- *Écoute sur la seule VIP* avec `ip_nonlocal_bind=1` : isole les services par adresse (plusieurs VIP, plusieurs certificats) ; perd le test direct du BACKUP.
- *Défi ACME DNS-01* : aucune dépendance au maître ; une clé d'écriture DNS sur des hôtes exposés en DMZ.
- *Certificat émis une fois et copié sur les deux* (Vault) : renouvellement à orchestrer à la main ; écarté.

**Pièges classiques**
- Même VRID qu'une autre instance du VLAN (le 70, en E25) : même MAC virtuelle `00:00:5e:00:01:46`, les deux paires se perturbent.
- Pair unicast copié-collé (l'hôte se désigne lui-même) : il n'entend jamais l'autre, double maître dès que les priorités s'inversent (E21).
- Script avec un **poids** trop faible (+2 sur 150/100) : HAProxy arrêté sur le maître ne déclenche aucune bascule.
- Tester la bascule en arrêtant **keepalived** au lieu d'HAProxy : on prouve que keepalived bascule, pas qu'il suit le service.
- `vips` sans masque : la VIP est posée en /32, sans route du sous-réseau associée : sans effet ici, trompeur plus tard.

**En production chez MédiSphère**
Supervision de l'état VRRP des deux répartiteurs et des certificats (E29) ; mise à jour par RB-070 ; mesures de bascule consignées (E32) ; pare-feu local des répartiteurs (seuls 80, 443, SSH depuis MGMT et `runner01`, VRRP et 8402 depuis le pair) à ajouter avec le durcissement (le filtre `regle_nft` ne connaît pas encore le protocole 112 de VRRP : à étendre, E28).

---

### M07-E13 — Publier GitLab et NetBox derrière les répartiteurs

**Solution** (une solution possible, celle du corrigé)

Fichiers : [`group_vars/role_lb/haproxy.yml`](fichiers/M07-E13/ansible/inventories/lab/group_vars/role_lb/haproxy.yml) et [`certificats.yml`](fichiers/M07-E13/ansible/inventories/lab/group_vars/role_lb/certificats.yml) (version E13), [`gitlab.rb.extrait`](fichiers/M07-E13/ansible/inventories/lab/host_vars/git01/gitlab.rb.extrait), [`netbox.yml.extrait`](fichiers/M07-E13/ansible/inventories/lab/host_vars/nbx01/netbox.yml.extrait), modèle [`nftables.conf.j2`](fichiers/M07-E13/ansible/roles/pare_feu/templates/nftables.conf.j2) du rôle `pare_feu` (chaîne `prerouting`) et [`defaults-main.yml.extrait`](fichiers/M07-E13/ansible/roles/pare_feu/defaults-main.yml.extrait), [`pare_feu.yml.extrait`](fichiers/M07-E13/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait), [`socle/publication.tf`](fichiers/M07-E13/infra/socle/publication.tf), [`publication-services.md`](fichiers/M07-E13/medisphere/docs/socle/publication-services.md).

- **Noms** : A `gitlab.par1…` et `netbox.par1…` → 10.10.70.200, **sans PTR** (`ptr = false` du module `enregistrement-dns` : le PTR de la VIP reste `lb.par1…`).
- **Certificats** : un par nom publié (`gitlab.crt`, `netbox.crt`, plus `lb.crt`) sur chaque répartiteur, tous relayés par `be_acme`. Un certificat par nom plutôt qu'un certificat à plusieurs noms : publier un service, c'est **ajouter** une entrée ; le rôle `certificats_acme` ne réémet un certificat existant que si son **premier** nom ne se vérifie plus, il ne verrait pas un nom ajouté à la liste.
- **Routage par nom** : `bind :443 ssl crt /etc/haproxy/certs/ strict-sni` (un SNI inconnu échoue à la poignée de main au lieu de recevoir un certificat qui ne lui correspond pas) ; `http-request set-var(txn.hote) req.hdr(host),field(1,:),lower` puis `use_backend … if { var(txn.hote) -m str gitlab.par1… }` ; défaut `be_aucun` (503).
- **Re-chiffrement vérifié** : `server git01 10.10.20.12:443 ssl verify required ca-file <racine> sni str(git01.par1…) verifyhost git01.par1… check check-sni git01.par1…`. Trois éléments : la racine qui valide la chaîne, le nom attendu, le SNI envoyé — pour la requête **et** pour le contrôle (`check-sni`).
- **Contrôles applicatifs** : GitLab `GET /-/readiness` (200 seulement si Rails, base et Redis répondent) ; il n'est servi qu'aux adresses de `monitoring_whitelist` : on y ajoute les deux répartiteurs. NetBox : `GET /login/` avec `Host: netbox.par1…`.
- **GitLab** (`gitlab.rb`, à la main, instantané avant) : `external_url 'https://gitlab.par1.medisphere.internal'` ; certificat d'omnibus **explicite** (`nginx['ssl_certificate']`… vers le certificat `git01`, sinon omnibus chercherait `/etc/gitlab/ssl/gitlab.par1….crt`) ; mandataires de confiance (`nginx['real_ip_trusted_addresses']`, `real_ip_header`, `gitlab_rails['trusted_proxies']`) ; `gitlab_rails['gitlab_ssh_host'] = 'git01.par1…'` pour les URL de clone SSH. `gitlab-ctl reconfigure`. Le nom `git01.par1…` continue de fonctionner (le nginx d'omnibus n'a qu'un serveur sur 443, il répond quel que soit l'en-tête `Host`) : `runner01` et les checks n'ont rien à changer ; les jobs, eux, clonent par `CI_SERVER_URL`, donc par les répartiteurs (d'où le flux INFRA → VIP:443).
- **NetBox** : `netbox_allowed_hosts: [nbx01.par1…, netbox.par1…]` (Django répond 400 à un `Host` inconnu). ⚠️ À confirmer : si la connexion échoue en 403 « CSRF verification failed », ajouter `CSRF_TRUSTED_ORIGINS = ['https://netbox.par1.medisphere.internal']` au modèle de `configuration.py` (le rôle `netbox` de M06 ne l'expose pas encore).
- **Bordure** : le modèle du rôle `pare_feu` gagne une chaîne `prerouting` (`type nat hook prerouting priority dstnat`) alimentée par `pare_feu_dnat` ; règle `iifname $WAN ip saddr $LAN_MAISON ip daddr $GW01_WAN tcp dport 443 dnat to $VIP_LB:443`, **plus** la règle de transit WAN → VIP:443 (la traduction ne vaut pas autorisation). Autres flux : DMZ → `git01`/`nbx01`:443, INFRA → VIP:443, `wg1` → VIP:443.
- **LAN maison** : le poste résout les noms publiés vers `<IP-GW01-WAN>` (`/etc/hosts` ou DNS de la box) et fait confiance à la racine MédiSphère (procédure dans `publication-services.md`).
- **Retour arrière** : `external_url` d'origine + reconfigure ; nom retiré de `netbox_allowed_hosts` ; noms publiés retirés (OpenTofu) ; `pare_feu_dnat` vidé et règles retirées.

Contrôles :
```
admin@adm01:~$ for n in gitlab netbox; do curl -s -o /dev/null -w "$n %{http_code}\n" --cacert $R https://$n.par1.medisphere.internal/; done
admin@adm01:~$ ssh lb01 'echo "show stat" | sudo socat stdio unix-connect:/run/haproxy/admin.sock' | awk -F, '$2 ~ /git01|nbx01/ {print $1, $2, $18, $37}'
admin@adm01:~$ timeout 3 bash -c 'exec 3<>/dev/tcp/10.10.70.200/22' || echo "22 fermé : attendu"
```

**Explications**

Le SNI choisit le **certificat** pendant la poignée de main ; l'en-tête `Host` choisit le **backend** une fois la requête déchiffrée. Les deux coïncident presque toujours, mais un client HTTP/2 peut réutiliser une connexion pour un autre nom couvert par le même certificat : router sur `Host` est donc le bon critère. Le re-chiffrement garde le trafic chiffré dans le socle (exigence HDS de Sophie) ; la vérification du certificat du serveur empêche un tiers du VLAN 20 de se faire passer pour `git01`. La traduction de destination se fait avant le routage : le filtrage de transit voit la VIP comme destination.

**Alternatives**
- *Passthrough TLS* (`mode tcp`, routage par `req.ssl_sni`) : le serveur garde la terminaison TLS, mais plus de contrôle HTTP, plus d'en-têtes, plus d'adresse client (sauf PROXY protocol).
- *Garder `external_url` sur `git01`* et publier un alias : les liens générés par GitLab contournent les répartiteurs ; à éviter.
- *CNAME* `gitlab` → `lb` : une résolution de plus, un seul A à changer si la VIP bougeait ; équivalent ici.

**Pièges classiques**
- `verify none` « pour commencer » : il reste en production (E21).
- `verifyhost` oublié : la chaîne est vérifiée, pas le nom ; n'importe quel certificat de la PKI est accepté.
- `/-/readiness` sans `monitoring_whitelist` : 404 au contrôle, GitLab `DOWN` alors qu'il va bien.
- DNAT sans règle de transit (ou l'inverse) ; DNAT sans `ip daddr $GW01_WAN` : tout HTTPS **traversant** `gw01` depuis le LAN serait détourné.
- `external_url` changé sans fixer le chemin du certificat : nginx d'omnibus ne démarre plus (ou Let's Encrypt s'active seul si `letsencrypt['enable']` n'est pas faux).

**En production chez MédiSphère**
Règles de limitation sur les pages de connexion, en-têtes de sécurité (HSTS), page d'erreur maison, statistiques protégées : E28. Exposition Internet réelle derrière un vrai pare-feu et un WAF éventuel ; ici, seulement le LAN maison.

---

### M07-E14 — Fabric leaf-spine : BGP unnumbered et ECMP

**Solution**

Fichiers : [`group_vars/m07_fabric/frr.yml`](fichiers/M07-E14/ansible/inventories/lab/group_vars/m07_fabric/frr.yml), `host_vars/{spine01,spine02,leaf01,leaf02,srv01,srv02}/frr.yml` (version E14, [exemple leaf01](fichiers/M07-E14/ansible/inventories/lab/host_vars/leaf01/frr.yml)), [`playbooks/m07-fabric.yml`](fichiers/M07-E14/ansible/playbooks/m07-fabric.yml).

1. **Pourquoi un seul AS pour les spines.** Une leaf réannonce aux spines ce qu'elle a appris d'un spine (elle n'a pas de politique « vallée-libre » par défaut). Avec un AS commun, `spine01` reçoit de `leaf02` une route dont l'AS_PATH contient déjà 65100 et la rejette (prévention des boucles) : aucun chemin spine → leaf → spine. Avec des AS distincts, ces chemins existeraient, plus longs mais utilisables en cas de panne, et la convergence explorerait des chemins absurdes (*path hunting*). Les leaves ne se parlent pas : tout trafic leaf → leaf passe par **un** spine, à coût égal, ce qui rend l'ECMP prévisible ; un lien direct créerait un chemin préféré et casserait la symétrie.
2. **Rôle** : inchangé (E06) ; seules les données changent.
3. **Données** : voisins `{interface: eth1, groupe: SPINES, …}` côté leaf, `{interface: eth1, as_distant: 65101, groupe: LEAVES, route_map_entree: RM-LEAF01-IN}` côté spine ; `PL-FABRIC` étendue (boucles /32, liens /31, 10.10.41.0/24 le 32, 10.10.20.0/24) ; chaque leaf annonce `PL-LOCAL` (sa boucle, son lien et la boucle de son serveur, par `network` : la route statique vers la boucle du serveur la fait exister dans la table) ; `maximum_paths: 8`. Serveurs : FRR sans protocole (`frr_bgp: {}`, `frr_routage_ipv4: false`), boucle sur `lo`, route `10.10.255.0/24 via` leur leaf. Les /31 posés par cloud-init restent : les sessions sont sur les adresses `fe80::` (`show bgp summary` montre `eth1`, `eth2` comme voisins).
4. **Profil `datacenter`** : temporisateurs BGP 3/9 s, `connect-retry` 10 s, journal des changements de voisins, `deterministic-med` désactivé, `import-check` activé, affichage des noms d'hôte… et **`ebgp-requires-policy` désactivé**. Le rôle reste en `traditional` (aucune ligne `frr defaults`) : la politique obligatoire ne dépend d'aucune valeur par défaut, et les temporisateurs voulus sont écrits (`timers bgp 3 9` dans `m07_bgp_options_fabric`).
5. **ECMP** :
   ```
   root@leaf01:~# ip route show 10.10.255.12
   10.10.255.12 nhid 42 proto bgp metric 20
           nexthop via inet6 fe80::…:a1 dev eth1 weight 1
           nexthop via inet6 fe80::…:b2 dev eth2 weight 1
   root@leaf01:~# vtysh -c 'show bgp ipv4 unicast 10.10.255.12'     # deux chemins « multipath », un « best »
   root@srv01:~# for p in $(seq 5201 5208); do iperf3 -c 10.10.255.22 -B 10.10.255.21 -p $p -t 5 & done   # (serveurs iperf3 -s -p … sur srv02)
   root@spine01:~# ip -s link show eth2 ; root@spine02:~# ip -s link show eth2      # compteurs : les deux augmentent
   ```
   Le *next-hop* IPv4 annoncé est une adresse IPv6 lien-local (RFC 8950) ; zebra l'installe tel quel (`via inet6`). `net.ipv4.fib_multipath_hash_policy = 1` : hachage sur adresses **et** ports ; à 0 (défaut), tous les flux entre deux boucles prennent le même spine. `multipath-relax` n'est pas nécessaire ici (les deux chemins ont le même AS_PATH `65100 65102`) ; il le deviendrait si les spines avaient des AS distincts.
6. **Convergence** : `ip link set eth1 down` → zebra voit l'interface tomber, la session est fermée immédiatement, le chemin retiré en quelques millisecondes : 0 à 1 paquet perdu. Lien « muet » (`nft add rule netdev … drop` ou règle `inet` sur `eth1`) : l'interface reste UP, BGP attend l'expiration du *hold timer* (9 s) : ≈ 45 pings perdus à 0,2 s (la moitié des flux, ceux hachés sur ce lien). BFD détecterait en moins d'une seconde.

**Explications**

Le BGP *unnumbered* supprime la gestion des adresses de liens (des centaines dans une vraie fabric) : un voisin = une interface. Il s'appuie sur IPv6 (annonces de routeur pour découvrir l'adresse lien-local du voisin) et sur la capacité *extended next-hop* pour transporter de l'IPv4 avec un *next-hop* IPv6. L'ECMP repose sur deux conditions : BGP considère les chemins équivalents (`maximum-paths`, critères de décision égaux) et le noyau les installe en une route à plusieurs *next-hops* ; la répartition est **par flux** (hachage), jamais par paquet (pas de réordonnancement TCP).

**Alternatives**
- *OSPF* (ou IS-IS) dans la fabric + BGP seulement aux bords : fréquent en entreprise ; BGP partout simplifie (un seul protocole, politiques uniformes) — c'est le modèle de la RFC 7938.
- *iBGP avec réflecteurs de routes* : un seul AS, mais il faut un IGP pour les *next-hops* et des réflecteurs.
- *EVPN/VXLAN* au-dessus de la fabric (M09, SDN EVPN de Proxmox) : pour étendre des segments de niveau 2 au-dessus du routage.

**Pièges classiques**
- IPv6 désactivé sur l'interface (`disable_ipv6=1`) : pas d'adresse `fe80::`, la session ne monte jamais.
- `maximum-paths` absent : un seul chemin installé, l'autre spine ne sert à rien.
- Profil `datacenter` posé « pour les temporisateurs » : la politique eBGP obligatoire disparaît sans bruit.
- Mot de passe TCP-MD5 sur un voisin désigné par l'interface : ⚠️ à confirmer sur ta version ; si la session reste en *Active*, retire le mot de passe du groupe sur les liens de fabric (liens point à point isolés, VNets dédiés) et note-le.
- Mesurer l'ECMP avec **un** flux `iperf3` : un flux = un chemin.

**En production chez MédiSphère**
BFD sur toutes les sessions de fabric, supervision du nombre de *next-hops* (alerte si une leaf n'en a plus qu'un), politiques par communautés plutôt que par préfixes, et la même logique côté Kubernetes (Cilium BGP, M15).

---

### M07-E15 — Jumbo frames sur les réseaux de stockage

**Solution**

Fichiers : [`CHG-825`](fichiers/M07-E15/medisphere/docs/socle/changements/CHG-825-jumbo-frames.md), [`pve01/interfaces-vmbr1.extrait`](fichiers/M07-E15/pve01/interfaces-vmbr1.extrait), [`pve01/sdn-zone-lab.sh`](fichiers/M07-E15/pve01/sdn-zone-lab.sh), [`gw01/interfaces.extrait`](fichiers/M07-E15/gw01/interfaces.extrait), [`gw01/nic-mtu.sh`](fichiers/M07-E15/gw01/nic-mtu.sh), [`maquette.tf.extrait`](fichiers/M07-E15/infra/envs/m07-maquette/maquette.tf.extrait), [`main.tf.extrait`](fichiers/M07-E15/infra/envs/m07-maquette/main.tf.extrait).

1. **Fiche** : voir CHG-825 ; ordre « du plus large au plus étroit » (pont, zone, routeur, VMs), retour arrière dans l'ordre inverse.
2. **Départ** : tout à 1500. `ping -M do -s 1473` entre deux VMs : erreur **locale** immédiate (`ping: local error: message too long, mtu=1500`) : le noyau de l'émetteur connaît le MTU de son interface.
3. **Déroulé** :
   ```
   root@pve01:~# cp -a /etc/network/interfaces /root/interfaces.avant-chg825
   root@pve01:~# nano /etc/network/interfaces          # « mtu 9000 » dans le bloc vmbr1
   root@pve01:~# ifreload -a && ip -d link show vmbr1 | head -n 1
   root@pve01:~# ./sdn-zone-lab.sh                     # zone lab : mtu 9000, puis pvesh set /cluster/sdn
   root@gw01:~#  nano /etc/network/interfaces          # mtu 9000 sur ens19 et ens19.30, mtu 1500 ÉCRIT ailleurs
   root@pve01:~# ./nic-mtu.sh                          # net1 de la VM 1000 : mtu=9000, même MAC
   root@pve01:~# qm pending 1000                       # en attente ? alors redémarrage de gw01 dans la fenêtre
   ```
   Si seul `ens19` passe à 9000 : les sous-interfaces existantes gardent 1500 **jusqu'à leur prochaine création** (redémarrage, `ifdown/ifup`), où elles hériteront de 9000. C'est le piège : tout semble correct jusqu'au redémarrage suivant. D'où le MTU **écrit** sur chaque sous-interface. Le changement de `net1` : à chaud si l'option *hotplug* de la VM inclut `network` (la carte est débranchée puis rebranchée : `ens19` et toutes ses sous-interfaces tombent, ifupdown ne les remonte pas forcément seul), sinon en attente. Le plus sûr : changement en attente + redémarrage contrôlé de `gw01` dans la fenêtre. ⚠️ À confirmer sur ton lab (option `hotplug` de la VM 1000).
4. **VMs de test** : cartes ajoutées **à la fin** de `cartes` (`eth2`, `eth3`), `mtu = 9000` (nouvelle clé lue par `try()` dans `main.tf`), adresses par cloud-init ; `tofu apply -replace='proxmox_virtual_environment_vm.maquette["srv01"]'` (et `srv02`), vider leurs lignes de `~/.ssh/known_hosts.m07`, rejouer `m07-web.yml` et `m07-fabric.yml`. Dans l'invité : `ip -br link` → `eth2`, `eth3` en 9000 (Proxmox annonce le MTU au pilote virtio). ⚠️ À confirmer : si l'invité reste à 1500, la configuration réseau de cloud-init impose un MTU ; le fixer dans le `ipconfig` n'est pas possible, utiliser alors `mtu=1` côté Proxmox ou un fichier netplan.
5. **Bout en bout** :
   ```
   root@srv01:~# ping -c 3 -M do -s 8972 10.10.31.251        # VLAN 31 : OK
   root@srv01:~# ping -c 3 -M do -s 8972 10.10.30.1          # gw01 : OK
   root@srv01:~# ip route add 10.10.20.0/24 via 10.10.30.1
   root@srv01:~# ping -c 2 -M do -s 8972 10.10.20.10
   From 10.10.30.1 icmp_seq=1 Frag needed and DF set (mtu = 1500)
   root@srv01:~# ip route del 10.10.20.0/24 via 10.10.30.1
   ```
   C'est **`gw01`** qui répond : il route vers `ens19.20` (1500) et renvoie l'ICMP *fragmentation needed* avec le MTU de sortie. Le noyau de `srv01` met ce MTU en cache pour la destination (`ip route get 10.10.20.10` affiche `mtu 1500` quelques minutes). Le pare-feu de `gw01` laisse passer ces ICMP (`ct state related`).
6. **Rien n'a bougé** : `adm01`, `dns01` à 1500 ; `vmbr0` à 1500 ; sous-interfaces 10, 20, 40, 50, 52, 60, 70, 99 de `gw01` à 1500.
7. **Journal** : un MTU différent **sur un même lien** (deux extrémités d'un même domaine de diffusion) ne produit aucun message : la trame trop grande est simplement jetée par le récepteur ou le pont ; seuls les **routeurs** émettent des ICMP. TCP annonce un MSS (MTU de l'interface − 40) à l'ouverture : deux hôtes à 9000 échangent des segments de 8960 ; s'ils traversent un lien à 1500 sans PMTUD fonctionnelle, la connexion s'établit (petits paquets) puis se fige au premier gros segment — le symptôme d'E38. Geneve ajoute ≈ 50 octets d'en-têtes (plus les options) : avec 1500 sur le VLAN 51, les VMs d'OpenStack devraient descendre à ≈ 1450 ; avec 9000, elles gardent 1500 (M10).

⚠️ À confirmer sur ton lab : la documentation SDN de Proxmox VE ne décrit l'option `mtu` que pour les zones QinQ, VXLAN et EVPN ; l'API l'accepte pour une zone VLAN (`pvesh usage /cluster/sdn/zones/{zone} -v`). Si, après `pvesh set /cluster/sdn`, les ponts des VNets (`/sys/class/net/vstopub/mtu`) restent à 1500, c'est que la zone VLAN n'applique pas l'option : retire-la (`sdn-zone-lab.sh --annuler`), et note que les ponts des VNets suivent alors le plus petit MTU de leurs ports (sous-interface de `vmbr1` créée à 9000, ports `tap` des VMs) — la vérification de bout en bout de l'étape 5 reste le seul juge.

**Explications**

Le MTU d'un pont est un **plafond** : un pont à 9000 transporte des trames de 1500 sans rien changer ; c'est l'extrémité (carte de VM, sous-interface du routeur) qui décide. D'où l'approche : infrastructure capable de 9000 partout (zone `lab` entière), MTU effectif choisi VLAN par VLAN aux extrémités.

**Alternatives**
- *Une zone SDN séparée* (`stockage`, MTU 9000) pour les VNets 30, 31, 51 : la zone `lab` reste à 1500, intention plus visible ; deux zones sur le même pont à gérer, VNets à déplacer (recréation des cartes des VMs).
- *`mtu=1` sur les cartes* (MTU du pont) : tout VLAN passerait à 9000 côté VM, à l'inverse de l'objectif.
- *MSS clamping* (`tcp option maxseg size set rt mtu` dans nftables) sur `gw01` : contourne les trous noirs PMTUD pour TCP ; un filet, pas une conception.

**Pièges classiques**
- Changer le MTU d'un VLAN sans le faire **aux deux bouts** : rien ne casse… jusqu'au premier gros transfert.
- Filtrer tout l'ICMP « par sécurité » : PMTUD meurt, les gros transferts se figent.
- Oublier que `ens19.<VLAN>` héritera du MTU de `ens19` au prochain démarrage.
- Appliquer la zone SDN sans `pvesh set /cluster/sdn` : rien ne change, la vérification « passe » sur l'ancienne valeur.

**En production chez MédiSphère**
MTU décrit dans NetBox (champ des interfaces et des VLAN), contrôlé par une sonde (`ping -M do -s 8972` entre nœuds Ceph, M08) ; changements de MTU toujours par fiche, jamais pendant une reconstruction Ceph.

---

### M07-E16 — FRR sur la bordure : préparer le BGP de la plateforme

**Solution**

Fichiers : [`group_vars/role_routeur/frr.yml`](fichiers/M07-E16/ansible/inventories/lab/group_vars/role_routeur/frr.yml), [`host_vars/gw01/frr.yml`](fichiers/M07-E16/ansible/inventories/lab/host_vars/gw01/frr.yml), [`host_vars/leaf01/frr.yml`](fichiers/M07-E16/ansible/inventories/lab/host_vars/leaf01/frr.yml) (version E16), [`playbooks/bordure-frr.yml`](fichiers/M07-E16/ansible/playbooks/bordure-frr.yml), scénario [`molecule/frr_bordure`](fichiers/M07-E16/ansible/molecule/frr_bordure/), [`pare_feu.yml.extrait`](fichiers/M07-E16/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait).

1. **Qui annonce quoi** :

   | Flèche | Préfixes | Filtre |
   |---|---|---|
   | fabric (`leaf01`) → bordure | boucles 10.10.255.0/24 (/32), 10.10.41.0/24 | `RM-BORDURE-OUT` (leaf01), `RM-FABRIC-IN` (gw01) |
   | bordure → fabric | 10.10.20.0/24 | `RM-FABRIC-OUT` (gw01), `RM-BORDURE-IN` (leaf01) |
   | `leaf01` → spines | ses préfixes + 10.10.20.0/24 | `RM-SPINES-OUT` (leaf01), `PL-LEAF01` (spines) |
   | K8s → bordure (M15) | 10.10.41.0/24 | `RM-K8S-IN` |
   | bordure → K8s | rien | `RM-K8S-OUT` (refus explicite) |
2. **Bordure** : listes `PL-DEPUIS-FABRIC`, `PL-DEPUIS-K8S`, `PL-VERS-FABRIC` ; route-maps dont `RM-K8S-OUT` = `deny 10` (intention explicite) ; groupe `K8S` (AS 65040, politiques) ; voisin 10.10.99.251 (AS 65101) ; `reseaux: [10.10.20.0/24]` ; dans `frr_config_supplementaire` : `bgp listen range 10.10.40.0/24 peer-group K8S`, `bgp listen limit 16`, `neighbor K8S shutdown`, `neighbor 10.10.99.251 update-source {{ frr_update_source_leaf01 }}`. `host_vars/gw01/frr.yml` : `frr_router_id: 10.10.10.2`, `frr_update_source_leaf01: 10.10.99.1`. Molecule `frr_bordure` : les **mêmes** données, adresse de documentation sur `lo`, vérification de ce que FRR a chargé (`show running-config`, `show route-map RM-K8S-OUT`).
3. **`leaf01`** : voisins de bordure en liste (`frr_voisins_bordure`, complétée en E24/E25) auxquels on ajoute `RM-BORDURE-IN/OUT` ; `RM-SPINES-OUT` laisse aussi passer 10.10.20.0/24 (la fabric doit joindre INFRA). **Adresse source** : aujourd'hui `gw01` n'a qu'une adresse sur le VLAN 99 ; en E25 il en aura deux (`.2` propre et la VIP `.1`), et une session qui partirait de la VIP changerait de passerelle à chaque bascule. On fixe la source dès maintenant (`update-source`), et `leaf01` désigne la bordure par son adresse **propre**.
4. **Application** :
   ```
   admin@adm01:~$ ms-snapshot --prefix avant-m07e16 1000
   root@gw01:~# ip route > /root/routes.avant-m07e16
   ```
   Pipeline : pare-feu (`gw01-pare-feu.yml`), puis `bordure-frr.yml`, puis `m07-fabric.yml` (`leaf01`).
5. **Vérifications** :
   ```
   root@gw01:~# vtysh -c 'show bgp summary'
   root@gw01:~# vtysh -c 'show bgp ipv4 unicast neighbors 10.10.99.251 routes'
   root@gw01:~# ip route show proto bgp
   10.10.255.1 nhid 18 via 10.10.99.251 dev ens19.99 proto bgp metric 20
   …
   admin@adm01:~$ ping -c 2 10.10.255.1
   ```
   `received-routes` exige `soft-reconfiguration inbound` sur ce voisin (garder une copie des routes **avant** politique) ; inutile en régime normal, coûteux en mémoire sur de grosses tables : on l'active pour un diagnostic, puis on le retire. Le ping de `adm01` vers `spine01` : aller par `gw01` (route BGP) puis `leaf01` puis la fabric ; retour par la route par défaut de `spine01` (`eth0`, VLAN 99, `gw01`) : asymétrique mais cohérent pour l'état de `gw01` (les deux sens passent par `ens19.99`).
6. **Expériences** : (a) `leaf01` annonce 10.10.10.0/24 et 0.0.0.0/0 : ils arrivent sur `gw01` (`show bgp … received-routes` si la copie est activée) mais sont **refusés** par `RM-FABRIC-IN` : rien dans la table ni dans le noyau ; (b) route-map de sortie retirée sur `leaf01` : `ebgp-requires-policy` → `leaf01` n'envoie **plus rien** (`(Policy)` dans `show bgp summary` de `leaf01`), la bordure perd les boucles ; (c) AS faux : `gw01` journalise *Bad Peer AS* et envoie une notification OPEN (*Bad Peer AS*), la session ne monte pas.

**Explications**

Une bordure accepte par défaut **rien** (RFC 8212) ; les politiques explicites disent ce qui entre et ce qui sort. Les listes de préfixes sont l'outil de base : `10.10.255.0/24 ge 32` = « des /32 dans ce /24, et rien d'autre ». Le groupe K8S en écoute passive (`bgp listen range`) accepte des voisins **dynamiques** dans une plage d'adresses : les nœuds Kubernetes apparaîtront sans modifier la bordure ; fermé (`shutdown`), il n'accepte personne.

**Alternatives**
- *Communautés* : la fabric marque ses préfixes (`65101:100`), la bordure filtre sur la communauté ; plus souple quand les préfixes se multiplient.
- *Voisins K8s déclarés un par un* : plus explicite, une MR par nœud ajouté ; l'écoute de plage est le standard pour les CNI qui parlent BGP.
- *Sans `update-source`* : fonctionne jusqu'en E25.

**Pièges classiques**
- Faute de frappe dans un nom de route-map : selon le contexte, refus total ou acceptation totale ; `show route-map` et `show bgp neighbors … ` (ligne « Route map for incoming advertisements ») le révèlent.
- `network 10.10.20.0/24` sur un routeur qui ne l'a pas exactement dans sa table : rien n'est annoncé, sans erreur.
- Port 179 ouvert à tout le VLAN 99 : n'importe quelle VM de la sandbox tenterait une session.
- `systemctl restart frr` pour appliquer : toutes les sessions tombent ; `reload` (frr-reload.py) n'envoie que les différences.

**En production chez MédiSphère**
Supervision des sessions et du nombre de préfixes reçus par voisin (E29), BFD vers les nœuds K8s, plafond de préfixes (`maximum-prefix`) sur chaque voisin externe, et la même configuration sur `gw02` par héritage du groupe (E24).

---

### M07-E17 — Open vSwitch : bonds LACP, VLAN et miroir de port

**Solution**

Fichiers : [`net01/m07-e17-ovs.sh`](fichiers/M07-E17/net01/m07-e17-ovs.sh), [`net01/m07-e17-ovs.service`](fichiers/M07-E17/net01/m07-e17-ovs.service).

1. **Script** : `monter` crée ce qui manque (`ip netns add`, paires veth, `ip link add bond0 type bond mode 802.3ad miimon 100 lacp_rate fast xmit_hash_policy layer3+4`, sous-interfaces `bond0.10/20`, `ovs-vsctl --may-exist add-br/add-bond/add-port`), crée le miroir s'il n'existe pas ; `demonter` défait tout ; `etat` affiche LACP et bonds des deux côtés. Installation : `systemctl disable --now m07-bond.service m07-ovs.service` (labos de E04 et E05, mêmes noms d'espaces de noms et de pont), script dans `/usr/local/sbin/`, unité dans `/etc/systemd/system/`, `systemctl enable --now m07-e17-ovs.service`. Oublier la désactivation de `m07-ovs.service` : au redémarrage suivant, deux unités se disputent `br-lab` et celle de E05 vide la table OpenFlow.
2. **LACP** :
   ```
   root@net01:~# ovs-appctl lacp/show bond-srv
   root@net01:~# ovs-appctl bond/show bond-srv          # lacp_status: negotiated ; member veth-w1: enabled
   root@net01:~# ip netns exec ns-srv cat /proc/net/bonding/bond0
   ```
   De chaque côté : *actor* (soi) et *partner* (l'autre) avec identifiant système (MAC), priorité, clé, port. Les deux membres d'un même agrégat ont le **même** partenaire et la même clé. Drapeaux de l'état d'un port : *activity* (LACP actif : émet sans attendre), *timeout* (court = trames chaque seconde, `lacp_rate fast`/`lacp-time=fast`), *aggregation* (agrégeable), *synchronization* (dans le bon agrégat), *collecting*/*distributing* (reçoit/émet du trafic). Un membre utile est `collecting` **et** `distributing`.
3. **VLAN** : `ns-a10` → 172.16.10.1 et `ns-a20` → 172.16.20.1 OK ; `ns-a10` → 172.16.20.1 : rien (même avec une route, le VLAN 10 et le VLAN 20 sont deux domaines de diffusion ; aucun routeur entre eux). `tcpdump -eni veth-w1` : `ethertype 802.1Q (0x8100), length …: vlan 10, p 0, ethertype IPv4` ; sur `veth-w10` (port d'accès), les trames n'ont **pas** d'étiquette.
4. **Miroir** : `tcpdump -ni mir0` montre les trames qui entrent et sortent par `bond-srv` (avec leurs étiquettes) : le ping de `ns-a10` vers `bond0.10` y apparaît dans les deux sens. Le trafic de `ns-a20` vers… lui-même (ou un hôte inexistant) ne passe pas par le bond : il n'est pas copié. Coût en production : chaque trame copiée double la charge du port de sortie (qui peut saturer et perdre des copies), et le port miroir voit **tout**, données sensibles comprises (contrôle d'accès strict).
5. **Panne** : `ip link set veth-w1 down` → `veth-s1` voit sa porteuse tomber (`miimon 100` : détection en 100 ms côté Linux), OVS retire le membre (`member veth-w1: disabled`) : 0 à 1 paquet perdu. Panne **côté serveur** sans perte de porteuse côté OVS (ex. `ip link set veth-s1 nomaster` dans `ns-srv`) : OVS ne reçoit plus de LACPDU sur ce membre et le retire à l'expiration (3 × 1 s en mode rapide, 90 s en mode lent) : c'est le cas où LACP vaut mieux qu'un agrégat statique.
6. **Redémarrage** : OVS retrouve `br-lab` et ses ports dans sa base (ports sans interface, en erreur), l'unité recrée espaces de noms et veth ; `--may-exist` rend la reconstruction silencieuse.

**Explications**

LACP (802.1AX, ex-802.3ad) négocie l'agrégat : chaque côté sait que l'autre agrège les mêmes liens, et un lien qui ne transmet plus (sans tomber électriquement) est retiré par l'absence de trames LACP. `balance-tcp` (OVS) et `layer3+4` (Linux) répartissent par flux. Le trunk OVS (`trunks=10,20`) laisse passer les trames étiquetées de ces VLAN ; un port `tag=10` est un port d'accès : il retire l'étiquette en sortie et l'ajoute en entrée.

**Alternatives**
- *Bond Linux des deux côtés* (E04) : même LACP, pas de VLAN ni de miroir de commutateur.
- *Miroir par `tc`* (`tc filter … action mirred egress mirror dev …`) sur un pont Linux : possible, moins lisible.
- *Configuration persistante* par `ifupdown`/netplan dans des espaces de noms : non gérée nativement ; l'unité systemd est la solution simple.

**Pièges classiques**
- Asservir un membre **UP** à un bond Linux : refus (« Device or resource busy » selon la version) ; l'arrêter d'abord.
- Ajouter à OVS une interface qui est dans un autre espace de noms : OVS ne la voit pas (port en erreur `could not open network device`).
- Mode LACP différent des deux côtés (`lacp=passive` des deux côtés : aucun n'initie, rien ne se négocie) — c'est l'une des pannes d'E40.
- Oublier `miimon` sur le bond Linux : aucune surveillance du lien, un membre mort reste dans l'agrégat (E40).

**En production chez MédiSphère**
Sur les hyperviseurs (M09) : bond LACP sur deux commutateurs empilés (MLAG), LACP rapide, VLAN étiquetés par-dessus, MTU 9000 pour le stockage ; la sonde de détection d'intrusion branchée sur un miroir des liens montants, gérée par l'équipe sécurité.

---

### M07-E18 — Raccorder le site de Lyon en WireGuard

**Solution**

Fichiers : rôle [`wireguard`](fichiers/M07-E18/ansible/roles/wireguard/) et rôle [`routes_statiques`](fichiers/M07-E18/ansible/roles/routes_statiques/), [`group_vars/role_routeur/wireguard.yml`](fichiers/M07-E18/ansible/inventories/lab/group_vars/role_routeur/wireguard.yml), [`vault-critique.yml.exemple`](fichiers/M07-E18/ansible/inventories/lab/group_vars/role_routeur/vault-critique.yml.exemple), [`host_vars/lyo-gw01/wireguard.yml`](fichiers/M07-E18/ansible/inventories/lab/host_vars/lyo-gw01/wireguard.yml), [`host_vars/lyo-pc01/routes.yml`](fichiers/M07-E18/ansible/inventories/lab/host_vars/lyo-pc01/routes.yml), [`playbooks/m07-lyo1.yml`](fichiers/M07-E18/ansible/playbooks/m07-lyo1.yml), [`pare_feu.yml.extrait`](fichiers/M07-E18/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait).

1. **Clés** (rien en clair sur disque ni à l'écran) :
   ```
   admin@adm01:~/src/ansible$ wg genkey | tee >(wg pubkey > /tmp/wg2-gw01.pub) \
       | uv run ansible-vault encrypt_string --vault-id critique@outils/vault-pass-client.sh \
         --stdin-name vault_wireguard_wg2_cle_privee >> inventories/lab/group_vars/role_routeur/vault-critique.yml
   ```
   Même chose pour `lyo-gw01` avec l'identité `lab`, dans `host_vars/lyo-gw01/vault-lab.yml`. Les clés **publiques** vont en clair chez le pair, puis `/tmp/*.pub` est effacé.
2. **Rôle** : schéma `{nom, adresse, port, cle_privee, table, mtu, post_up, pilotage, pairs: [{nom, cle_publique, endpoint, allowed_ips, keepalive}]}` ; fichier 0600 dans `/etc/wireguard` (0700), `no_log` ; changement de pairs appliqué par `wg syncconf` (le tunnel ne tombe pas) ; `pilotage: transition` = fichier posé, unité ni activée ni lancée (E26) ; contrôle final `wg show <if> listen-port`.
3. **Configuration** : `gw01` : `10.255.2.1/24`, port 51822, `Table = off`, `PostUp = ip route replace 10.30.0.0/16 dev %i`, pair `AllowedIPs = 10.255.2.2/32, 10.30.0.0/16`. `lyo-gw01` : `10.255.2.2/24`, port 51822, `PostUp` vers 10.10.20.0/24 et 10.10.70.0/24, pair `AllowedIPs = 10.255.2.1/32, 10.10.20.0/24, 10.10.70.0/24`, `Endpoint = 10.10.99.1:51822`, `PersistentKeepalive = 25`. `lyo-gw01` route (`ip_forward`). `lyo-pc01` : deux routes ciblées par 10.30.10.1 (rôle `routes_statiques`, unité systemd indépendante de netplan).
4. **Matrice** : entrée UDP 51822 depuis 10.10.99.250 seulement ; règle DNS existante complétée de `$NET_LYO1` ; `wg2` → VIP:443 ; `wg2` → INFRA et DMZ en `echo-request`. Rien de PAR1 vers Lyon, rien vers MGMT.
5. **Vérifications** :
   ```
   root@gw01:~# wg show wg2                           # latest handshake: … seconds ago ; transfer
   admin@lyo-pc01:~$ dig +short -b 10.30.10.10 @10.10.20.10 gitlab.par1.medisphere.internal
   admin@lyo-pc01:~$ curl -sS -o /dev/null -w '%{http_code}\n' --cacert /usr/local/share/ca-certificates/medisphere-root-ca.crt https://gitlab.par1.medisphere.internal/users/sign_in
   admin@lyo-pc01:~$ ip route get 10.10.10.10         # par eth0 (administration), pas par 10.30.10.1
   ```
6. **Expériences** : (a) 10.10.70.0/24 retiré des `AllowedIPs` côté `lyo-gw01` : la route `10.10.70.0/24 dev wg2` existe toujours, mais WireGuard ne trouve **aucun pair** dont la liste contient la destination : sur `lyo-gw01`, `ping 10.10.70.200` échoue immédiatement (`sendmsg: Required key not available`) ; pour `lyo-pc01`, les paquets routés par `lyo-gw01` vers la DMZ sont refusés par WireGuard, qui renvoie un ICMP « hôte injoignable » (⚠️ à confirmer : `ping` affiche `Destination Host Unreachable` venant de 10.30.10.1). Dans l'autre sens, une réponse venant de 10.10.70.x serait elle aussi jetée à l'entrée du tunnel (source hors liste). Le DNS (10.10.20.0/24) continue de marcher : la panne est **partielle**, le piège classique. (b) Route 10.10.0.0/16 via le tunnel sur `lyo-pc01` : la réponse SSH vers 10.10.10.10 part par `eth1` → `lyo-gw01` → `wg2` (si autorisé) ou nulle part ; `gw01` voit arriver par `wg2` un paquet d'une connexion qu'il a vue sortir par `ens19.99` : la session SSH se fige (et la règle de transit n'autorise de toute façon pas `wg2` → MGMT).

> Note de cohérence : l'introduction du module annonce que E18 « remplace la route par défaut » de `lyo-pc01`. Le corrigé garde la route par défaut d'administration et pose des routes **ciblées** : c'est ce qui évite le routage asymétrique de l'expérience (b). Les deux fonctionnent pour le trafic de l'agence ; la version ciblée garde l'administration intacte.

**Explications**

`AllowedIPs` est à la fois le filtre d'entrée (une source hors liste est jetée après déchiffrement) et la table de routage du tunnel (une destination est envoyée au pair dont la liste la contient). `Table = off` sépare les deux rôles : WireGuard filtre, le routage est décidé ailleurs (ici `PostUp`, en E19 BGP). L'agence initie et entretient la session (`PersistentKeepalive`) : c'est le modèle d'un site derrière une box.

**Alternatives**
- *Table automatique* (`Table` absent) : `wg-quick` crée une route par `AllowedIPs` ; simple, mais le routage dynamique ne pourra plus décider.
- *IPsec* (strongSwan) : interopérable avec des équipements d'opérateur ; plus complexe à exploiter.
- *Tout PAR1 ouvert à l'agence* : moins de lignes, et l'administration du socle joignable depuis un poste d'agence.

**Pièges classiques**
- Clé privée dans le dépôt « parce que le dépôt est privé ».
- `AllowedIPs = 0.0.0.0/0` côté bordure : tout Internet routable vers l'agence, et n'importe quelle source acceptée.
- Oublier `ip_forward` sur `lyo-gw01` : le tunnel monte, `lyo-gw01` lui-même joint PAR1, `lyo-pc01` non.
- Oublier `$NET_LYO1` dans la règle DNS : tout marche par adresse, rien par nom.

**En production chez MédiSphère**
Deux tunnels (un par passerelle de bordure, E26), supervision de la dernière poignée de main (E29), rotation des clés documentée, et un pare-feu local sur le routeur d'agence.

---

### M07-E19 — Routage dynamique à travers le tunnel

**Solution** (une solution possible, celle du corrigé)

Fichiers : [`group_vars/all/sites.yml`](fichiers/M07-E19/ansible/inventories/lab/group_vars/all/sites.yml), [`group_vars/role_routeur/frr.yml`](fichiers/M07-E19/ansible/inventories/lab/group_vars/role_routeur/frr.yml) et [`wireguard.yml`](fichiers/M07-E19/ansible/inventories/lab/group_vars/role_routeur/wireguard.yml) (version E19), [`host_vars/lyo-gw01/frr.yml`](fichiers/M07-E19/ansible/inventories/lab/host_vars/lyo-gw01/frr.yml) et [`wireguard.yml`](fichiers/M07-E19/ansible/inventories/lab/host_vars/lyo-gw01/wireguard.yml), [`playbooks/m07-lyo1.yml`](fichiers/M07-E19/ansible/playbooks/m07-lyo1.yml) (version E19), [`pare_feu.yml.extrait`](fichiers/M07-E19/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait) et la [matrice complète de fin de palier](fichiers/M07-E19/ansible/inventories/lab/host_vars/gw01/pare_feu.yml).

- **Liste unique** : `sites_lyo1_reseaux_par1: [{seq: 10, prefixe: 10.10.20.0/24}, {seq: 20, prefixe: 10.10.70.0/24}]` dans `group_vars/all/sites.yml`. Elle devient : la liste `PL-VERS-LYO1` (`map('combine', {'action': 'permit'})`) et les `network` de la bordure ; la liste d'entrée `PL-DEPUIS-PAR1` de `lyo-gw01` ; les `AllowedIPs` du pair PAR1 côté `lyo-gw01` (`map(attribute='prefixe')`). La matrice des flux reste écrite à part : elle autorise des **services**, et sa relecture en MR est le garde-fou humain.
- **Politiques** : bordure : `RM-LYO1-IN` = 10.30.0.0/16 `le 24`, `maximum-prefix 50` ; `RM-LYO1-OUT` = la liste unique. `lyo-gw01` (AS 65030) : `RM-PAR1-IN` = la liste unique, `RM-PAR1-OUT` = 10.30.0.0/16 exactement.
- **Agrégat** : `ip route 10.30.0.0/16 blackhole` + `network 10.30.0.0/16` sur `lyo-gw01`.
- **WireGuard** : `post_up` retirés ; `AllowedIPs` de `gw01` vers Lyon = 10.255.2.2/32 + 10.30.0.0/16 (tout ce que `RM-LYO1-IN` peut accepter) ; côté Lyon = 10.255.2.1/32 + la liste unique.
- **Matrice** : entrée TCP 179 sur `wg2` depuis 10.255.2.2.
- **Plan de bascule** : (1) pare-feu (BGP dans `wg2`) ; (2) FRR sur la bordure puis sur `lyo-gw01` : la session monte **dans le tunnel existant** et installe des routes identiques aux statiques (aucune coupure) ; (3) WireGuard sans `post_up`, puis redémarrage de `wg2` des deux côtés (un `PostUp` retiré n'est pas défait par `wg syncconf`) : les routes statiques disparaissent avec l'interface, la session se rétablit (connexion TCP neuve) et réinstalle les routes. Coupure attendue : le temps de remonter `wg2` + l'établissement BGP (temporisateur de reconnexion) : 5 à 30 s ; mesurer depuis `lyo-pc01` avec `ping -i 0.5 10.10.20.10`. Retour arrière : réappliquer la version E18 des deux fichiers WireGuard et redémarrer `wg2`, retirer le voisin LYO1.
- **Preuves** : ajouter `{seq: 30, prefixe: 10.10.40.0/24}` à la liste unique → après application, `lyo-gw01` apprend 10.10.40.0/24 et l'accepte dans `AllowedIPs` sans autre modification (la matrice, elle, n'ouvre encore aucun service vers le VLAN 40 : c'est voulu). Puis faire annoncer 10.10.10.0/24 par `lyo-gw01` (`network` + route `blackhole`) : la bordure le refuse (`RM-LYO1-IN`), rien dans sa table.

**Explications**

Trois mécanismes décident du même flux : la politique BGP (ce qui est **annoncé** et **accepté**), `AllowedIPs` (ce que WireGuard **laisse passer**), la matrice (ce que `gw01` **autorise**). S'ils divergent, la panne est silencieuse : route installée mais paquets jetés par WireGuard, ou autorisés mais jamais routés. Les dériver d'une seule donnée supprime la classe de pannes la plus courante. La route *blackhole* d'agrégat est la pratique standard : annoncer un préfixe stable sans dépendre de l'état d'une interface.

**Alternatives**
- *OSPF dans le tunnel* : convient entre sites d'une même organisation ; BGP donne des politiques plus explicites et prépare les sites tiers.
- *Redistribuer les routes connectées* de Lyon avec une route-map : moins stable qu'un agrégat (chaque sous-réseau apparaît et disparaît).
- *`AllowedIPs = 10.10.0.0/16`* côté Lyon et filtrage par BGP seul : moins de couplage, mais WireGuard n'est plus une seconde barrière.

**Pièges classiques**
- `network 10.30.0.0/16` sans route : rien n'est annoncé.
- `AllowedIPs` non élargi alors que BGP accepte plus : trou noir (route présente, paquets jetés).
- Oublier le port 179 dans la matrice : la session reste en *Active*, les routes statiques retirées, l'agence coupée.
- Retirer les routes statiques **avant** que la session ne monte.

**En production chez MédiSphère**
Un fichier « sites » par agence, généré depuis NetBox (préfixes du site et services ouverts), BFD sur la session, alerte sur l'absence de préfixes reçus, second tunnel par `gw02` avec préférence locale.

---

### M07-E20 — Méthode de diagnostic réseau

**Solution**

Fichiers : [`outils/bin/ms-diag-chemin`](fichiers/M07-E20/outils/bin/ms-diag-chemin), [`RB-072`](fichiers/M07-E20/medisphere/docs/socle/runbooks/RB-072-diagnostic-reseau.md).

1. **Situations** : (a) ARP sans réponse : `ip neigh` (`FAILED`/`INCOMPLETE`), `tcpdump -eni <tap> arp` sur `pve01`, `bridge vlan show` (la carte est-elle dans le bon VLAN ?), sous-interface de `gw01` UP ; (b) SYN sans réponse : `tcpdump` aux bornes, `nft monitor trace`, `conntrack -L` (`SYN_SENT`), route de **retour** (`ip route get … from … iif …`) ; (c) refus immédiat : `ss -ltnp` sur la destination (service, adresse d'écoute), règle `reject` ; (d) gros transferts figés : `ping -M do`, `tracepath`, ICMP *frag needed* filtré, MTU des deux bouts ; (e) MGMT oui, sandbox non : la matrice (règles par interface d'entrée), `nft list ruleset`, compteurs ; (f) agrégat : `/proc/net/bonding/bond0`, `ovs-appctl bond/show`, `lacp/show`.
2. **Cas rejoués** (extraits attendus) : `adm01` → `hap01` : sur `gw01`, SYN vu sur `ens19.10` puis `ens19.99`, SYN-ACK en retour ; sur `pve01`, `bridge fdb show br vmbr1 | grep <MAC de hap01>` donne le port `tap2079i0` ; `tcpdump -eni tap2079i0 port 443`. `lyo-pc01` → 10.10.20.10 : `lyo-pc01` → `via 10.30.10.1 dev eth1` ; `lyo-gw01` → `dev wg2` ; `gw01` → `dev ens19.20` ; retour : `ip route get 10.30.10.10 from 10.10.20.10 iif ens19.20` → `dev wg2`. `srv01` → INFRA par le VLAN 30 : ICMP *frag needed* de 10.10.30.1, `mtu = 1500` (E15).
3. **Trace nftables** : table `inet trace`, chaîne `prerouting` de priorité −350, règle `meta nftrace set 1` limitée à la source et à la destination ; `nft monitor trace` montre chaque règle évaluée (`rule … (verdict accept)` ou `policy drop`) ; `nft delete table inet trace`.
4. **`ms-diag-chemin`** : lecture seule ; sections numérotées, OK/KO orientés ; code 0/1/2 ; exécution distante par SSH en `BatchMode` ; validation des arguments (aucune injection dans les commandes distantes). Exemple :
   ```
   admin@adm01:~$ ms-diag-chemin --depuis srv01 --mtu 9000 10.10.31.251
   Chemin srv01 → 10.10.31.251 (MTU attendu 9000), …
   == 1. Résolution (ce que la machine croit)
   OK  10.10.31.251 → 10.10.31.251
   == 2. Route choisie par le noyau …
   10.10.31.251 dev eth3 src 10.10.31.250 uid 1000
   …
   == 5. MTU sans fragmentation (DF) : 9000 octets
   OK  des paquets de 9000 octets passent sans fragmentation
   ```
5. **RB-072** : voir le fichier (cadrage, tableau symptôme → piste, relevé automatique, une section par couche, capture aux bornes, correction par le code, clôture).

**Explications**

La méthode est une **descente** : ce que la machine croit (configuration : résolution, route, voisin), puis ce qui se passe (mesures : ICMP, MTU, chemin, TCP), puis où le paquet disparaît (captures aux bornes). La moitié des pannes réseau sont des **retours** : un aller correct dont la réponse prend un autre chemin, refusé par un pare-feu à état ou par `rp_filter`.

**Alternatives**
- *mtr* (relevé continu de perte par saut) ; *pwru* (trace eBPF dans le noyau) ; *`ip monitor`* (changements de routes et de voisins en direct).
- Un outil de diagnostic en Python (`medictl diag`) : sorties structurées (JSON) pour la supervision ; le Bash suffit ici et tourne partout.

**Pièges classiques**
- Ne regarder que l'aller.
- Capturer sur la mauvaise interface (`ens19` sans `-e` : on ne voit pas le VLAN ; `ens19.20` : on ne voit pas les autres).
- Laisser une table de trace (ou une capture de plusieurs Go dans `/var/tmp`).
- « Corriger » à la main et oublier : le rôle `pare_feu` réécrira au prochain passage, la panne reviendra.

**En production chez MédiSphère**
RB-072 est le point d'entrée de l'astreinte pour tout ticket réseau ; `ms-diag-chemin` est installé sur `adm01` et sur les postes d'astreinte ; les cas résolus alimentent le tableau des symptômes.

---

### M07-E21 — Revue : les répartiteurs du stagiaire

**Réponses à l'étape 1.** **Administrer** : tout compte local de `lb01`/`lb02` (socket en `mode 666 level admin`) et, sur le réseau, quiconque joint le port 8404 (toutes les adresses) avec `admin:admin` (`stats admin if TRUE` : mise en maintenance des serveurs depuis la page). **HAProxy s'arrête sur `lb01`** : `killall -0 haproxy` échoue, le poids `+2` n'est plus ajouté : `lb01` passe de 152 à 150, `lb02` reste à 102 : **pas de bascule**, la VIP reste sur un répartiteur qui ne sert plus rien (et si `killall` n'est pas installé — paquet `psmisc` —, le script échoue en permanence sur les deux hôtes). **Démarrage simultané** : `lb01` démarre en MASTER (priorité 150, préemption par défaut), envoie ses annonces à `lb02` (qui passe BACKUP) ; `lb02`, lui, envoie ses annonces **à lui-même** (`unicast_peer` = sa propre adresse) : `lb01` ne l'entend jamais. Tout va bien… tant que `lb01` est le plus prioritaire. Le jour où `lb02` doit devenir maître alors que `lb01` est vivant (priorité abaissée par un script correctement réglé, par exemple), `lb01` n'entend rien et se croit seul : **deux maîtres**, deux ARP gratuits pour 10.10.70.200.

**Revue** (ordre de traitement ; gravité dans **notre** socle)

| N° | Fichier : ligne(s) | Défaut | Cat. | Gravité | Impact chez nous | Correction |
|---|---|---|---|---|---|---|
| 1 | `haproxy.cfg` : 52-57 | Page de statistiques sur toutes les adresses, `admin:admin`, `stats admin if TRUE` | Sécu. | Critique | Depuis le VPN, la sandbox, le LAN maison (DNAT) ou Lyon selon la matrice : mise en maintenance de GitLab et NetBox par n'importe qui | `bind 127.0.0.1:8404` (tunnel SSH), pas de `stats admin` ; exposition éventuelle en E28 : MGMT seulement, comptes hachés en Vault |
| 2 | `haproxy.cfg` : 8 | Socket `mode 666 level admin` | Sécu. | Critique | Tout processus local (un compte compromis, un service) arrête, vide ou redirige les backends | `mode 660` (root et groupe `haproxy`), `level admin` réservé à root |
| 3 | `keepalived-lb02.conf` : 24-26 | `unicast_peer` = l'adresse de `lb02` lui-même (copier-coller) | HA | Critique | Double maître latent dès que `lb02` doit prendre la main avec `lb01` vivant ; VIP qui saute entre deux MAC, connexions coupées au hasard | `unicast_peer { 10.10.70.10 }` ; mieux : pairs **calculés** depuis l'inventaire (rôle, E12) |
| 4 | `keepalived-lb0*.conf` : 7-11 | Script `killall -0` avec `weight 2` (sans `fall`/`rise`) | HA | Élevée | HAProxy arrêté sur le maître : aucune bascule (150 contre 102) ; `killall` peut manquer (psmisc) | Script `systemctl is-active --quiet haproxy.service`, **sans poids** (FAULT ⇒ bascule), `fall 2 rise 2` ; si poids : négatif et supérieur à l'écart (`-60`) |
| 5 | `keepalived-lb0*.conf` : 16 | `virtual_router_id 70` | HA | Élevée | En E25, le VRID 70 est celui de la passerelle du VLAN 70 : même MAC virtuelle (`00:00:5e:00:01:46`) pour deux VIP du même VLAN, les deux paires se perturbent | VRID 170 (PLAN §4.9) |
| 6 | `haproxy.cfg` : 36-37 | `ssl verify none` vers les serveurs d'application | Sécu. | Élevée | N'importe quelle machine du VLAN 40 qui prend l'adresse d'un serveur reçoit les données de santé déchiffrées | `verify required ca-file <racine> verifyhost app0N.par1…` ; certificats ACME des serveurs (pas d'autosigné) |
| 7 | `haproxy.cfg` : 36-37 | Aucun `check` sur les serveurs de MédiAgenda | Fonct. | Élevée | Un serveur arrêté reçoit une requête sur deux jusqu'à intervention humaine | `option httpchk`, `http-check send … uri /sante`, `check` sur chaque serveur |
| 8 | `haproxy.cfg` : 22-24 | MédiAgenda servi **en clair** sur le port 80 (pas de redirection) | Sécu. | Élevée | Données de santé (rendez-vous) en clair entre le client et la VIP : non conforme HDS | `http-request redirect scheme https code 301` (sauf défi ACME), aucun `use_backend` applicatif sur `fe_http` |
| 9 | `haproxy.cfg` : 7 | `maxconn 50` global | Fonct. | Élevée | Au-delà de 50 connexions simultanées (GitLab + NetBox + MédiAgenda, WebSockets comprises), les suivantes attendent puis échouent | Retirer (HAProxy calcule une valeur à partir des limites du système) ou dimensionner après mesure (E32) |
| 10 | `haproxy.cfg` : 17-19 | `timeout client/server 1h` partout, pas de `timeout http-request` | Fonct./Sécu. | Moyenne | Connexions lentes ou abandonnées gardées une heure (épuisement, *slowloris*) ; le besoin (export PDF) ne concerne qu'un backend | `timeout client 30s`, `timeout server 30s`, `timeout http-request 10s` ; `timeout server 300s` dans `be_agenda` seulement |
| 11 | `haproxy.cfg` : 9 | `ssl-min-ver TLSv1.0` | Sécu. | Moyenne | TLS 1.0/1.1 dépréciés (RFC 8996), contraires à la politique de la PKI | `ssl-min-ver TLSv1.2` (bind et serveurs) |
| 12 | `haproxy.cfg` : 27-31 | Ni `option forwardfor` ni `X-Forwarded-Proto` | Expl. | Moyenne | MédiAgenda journalise l'adresse des répartiteurs pour tous les patients ; liens générés en `http://` | `option forwardfor`, `http-request set-header X-Forwarded-Proto https` |
| 13 | `keepalived-lb01.conf` : 14 | `state MASTER` + préemption implicite | HA | Moyenne | `lb01` qui revient reprend la VIP : une seconde coupure des connexions (contraire à ADR-0071) | `state BACKUP` des deux côtés, `nopreempt` |
| 14 | `keepalived-lb0*.conf` : 19-22 | Bloc `authentication` (PASS) avec VRRP v3 | Sécu. | Faible | Sans effet en v3 (pas d'authentification dans le protocole ; ⚠️ keepalived l'ignore avec un avertissement, à confirmer) : fausse impression de sécurité, mot de passe en clair dans le dépôt | Retirer ; la protection vient de l'unicast et du filtrage |
| 15 | `haproxy.cfg` : 28-30 | Pas de `strict-sni`, `hdr(host)` comparé sans normalisation du port | Fonct. | Faible | Un client sans SNI reçoit un certificat quelconque ; `Host: agenda…:443` n'est routé nulle part | `strict-sni` ; `set-var(txn.hote) req.hdr(host),field(1,:),lower` |

**Premier traité : n° 1**, parce qu'il est exploitable **tout de suite** depuis des réseaux larges (un navigateur suffit) et touche les services déjà publiés (GitLab, NetBox) ; puis n° 2 (accès local), n° 3 (double maître latent : il n'attend qu'une maintenance pour se déclencher), puis 4 à 9.

**Lignes corrigées** : [`haproxy.cfg.corrige`](fichiers/M07-E21/haproxy.cfg.corrige), [`keepalived.conf.corrige`](fichiers/M07-E21/keepalived.conf.corrige).

**Conseils à Lucas.** Une haute disponibilité se teste en faisant tomber **le service** (arrêter HAProxy, pas keepalived), puis la machine, puis le réseau, et en regardant ce que voit un **client** pendant ce temps (une boucle de requêtes). Teste aussi ce qui doit **échouer** : la page de statistiques depuis une autre VM, un serveur arrêté qui ne doit plus recevoir de requêtes. Et compare les deux fichiers keepalived ligne à ligne : ce qui doit différer (adresse, priorité, pair) est exactement ce qu'un copier-coller laisse identique.

**Grille d'auto-évaluation** (2 points par ligne, 20 au total, acceptable à 14)

| Critère | 0 | 1 | 2 |
|---|---|---|---|
| Défauts critiques (1, 2, 3) | aucun | un ou deux | les trois |
| Défauts élevés (4 à 9) | moins de 3 | 3 ou 4 | 5 ou 6 |
| Impact « chez nous » | générique | partiel | concret pour chaque défaut |
| Corrections | vagues | partielles | directive et valeur |
| Réponses de l'étape 1 | absentes | partielles | complètes (dont le double maître) |
| Ordre de traitement | absent | non justifié | justifié |
| Lignes corrigées | absentes | partielles | complètes et cohérentes |
| Conseils de test | absents | « tester plus » | tester la panne et l'échec |
| Ton | jugement | neutre | utile au destinataire |
| Mineurs (13 à 15) | aucun | un | deux ou plus |

---

### M07-E22 — Runbook : maintenance d'un répartiteur

**Solution**

Fichier : [`RB-070-maintenance-repartiteur.md`](fichiers/M07-E22/medisphere/docs/socle/runbooks/RB-070-maintenance-repartiteur.md).

Points qui font la qualité de ce runbook :
- **Contrôles d'entrée bloquants** : une seule VIP portée, l'autre répartiteur répond en direct et voit tous les serveurs `UP`, ses services actifs. Sans cela, la procédure peut laisser les deux répartiteurs hors service.
- **Déplacer la VIP en arrêtant keepalived** (et non HAProxy) sur le maître : keepalived annonce une priorité 0 en s'arrêtant, l'autre prend la VIP en moins d'une seconde ; HAProxy continue de servir les connexions déjà établies sur l'adresse propre, le temps qu'elles se terminent (`CurrConns` par la socket).
- **Durée d'attente justifiée** : au plus 10 minutes ; les WebSockets de GitLab (`timeout tunnel 1h`) ne se termineront pas d'elles-mêmes, on accepte de les couper.
- **Retour à la situation nominale** séparé, dans sa propre fenêtre (pas de préemption) ; rester sur `lb02` maître est une situation saine.
- **Reconstruction** : renvoi à RB-060, et ce qui est propre aux répartiteurs (ACME relayé par l'autre, qui tient la VIP).
- **Mesure** : la coupure vue par un client (boucle `curl` sur `/sante`) est notée dans le ticket : moins d'une seconde pour un déplacement contrôlé, 2 à 4 s si l'on arrête HAProxy, ≈ 3,6 s pour un arrêt brutal de la VM.

**Pièges classiques** (de rédaction) : écrire « arrêter le répartiteur » sans dire lequel porte la VIP ; oublier l'instantané ; ne pas prévoir le cas où l'autre répartiteur tombe **pendant** la maintenance (contrôle continu, retour arrière de l'étape 2) ; supposer que la VIP revient seule sur `lb01`.

**En production chez MédiSphère**
Mise à jour hebdomadaire par un pipeline planifié qui enchaîne RB-070 sur `lb02` puis `lb01`, avec les contrôles d'entrée comme garde-fous et un arrêt au premier écart ; fenêtre annoncée aux équipes de développement pour l'étape « maître ».

---

### M07-E23 — Revue : la configuration BGP du prestataire

**Étape 1.** Le routeur d'InfoGér (AS 65000) parle à un transit (AS 64600), à l'agence (AS 65030) et à n'importe quel hôte de 10.10.0.0/16 qui se présente (écoute passive, n'importe quel AS externe). Il **accepte** tout du transit et de l'agence (aucune politique, `ebgp-requires-policy` désactivé), et des « clients » tout ce qui tombe dans 10.0.0.0/8, jusqu'aux /32. Il **annonce** à tout le monde l'agrégat 10.10.0.0/16, tous ses réseaux connectés et toutes ses routes statiques, plus tout ce qu'il a appris (rien ne filtre la sortie) : le transit reçoit les routes de l'agence et des clients, l'agence reçoit celles du transit.

**Revue**

| N° | Ligne(s) | Défaut | Cat. | Gravité | Conséquence si on le reprenait | Correction |
|---|---|---|---|---|---|---|
| 1 | 20 (et l'absence de `route-map … out`) | `no bgp ebgp-requires-policy`, aucune politique de sortie | Sécu. | Critique | Tout ce que la bordure apprend repart vers tous les voisins : routes de Kubernetes vers Lyon, de Lyon vers la fabric… et vers un futur transit, fuite de préfixes privés | Retirer la ligne (RFC 8212) ; une route-map d'entrée **et** de sortie par voisin |
| 2 | 32, 30, 12, 40 | Écoute passive sur tout 10.10.0.0/16, `remote-as external`, liste `10.0.0.0/8 le 32` | Sécu. | Critique | Toute VM de la sandbox (mot de passe connu) ouvre une session et annonce 10.10.20.10/32 : le DNS du lab est détourné (le /32 l'emporte sur le /24) | Écoute limitée au VLAN 40 (K8s) et à l'AS 65040, groupe fermé tant qu'inutile, entrée limitée à 10.10.41.0/24 (E16) |
| 3 | 35-37 | `network 10.10.0.0/16`, `redistribute connected`, `redistribute static` sans filtre | Sécu. | Critique | MGMT, le VLAN de stockage, le WAN et les routes *blackhole* annoncés à l'agence (contraire à la politique : pas de MGMT hors PAR1) | Annoncer explicitement les réseaux ouverts (`network` + liste unique, E19), aucune redistribution non filtrée |
| 4 | 24, 27, 31 | Même mot de passe TCP-MD5 en clair pour tous les voisins, dans un document | Sécu. | Élevée | Le connaître, c'est pouvoir se faire passer pour n'importe quel voisin ; il est désormais diffusé | Dans le tunnel WireGuard : inutile ; ailleurs : un secret par voisin, en Vault, renouvelé |
| 5 | 21 | `timers bgp 1 3` | Stabilité | Élevée | Dans un tunnel sur Internet, trois secondes de gigue font tomber la session : oscillation des routes de l'agence | Défauts (60/180) et BFD si une détection rapide est nécessaire |
| 6 | 13, 16 | `AGENCE` = 10.30.0.0/16 `le 32`, aucun `maximum-prefix` | Stabilité | Moyenne | L'agence peut injecter des milliers de /32 ; une erreur de configuration chez elle remplit la table de la bordure | `le 24`, `maximum-prefix 50` |
| 7 | 28 | `ebgp-multihop 255` sur un voisin directement connecté (tunnel) | Sécu. | Moyenne | Supprime la protection du TTL : une session peut être ouverte depuis n'importe où sur le chemin | Retirer (voisin direct) ; `ttl-security hops 1` si l'on veut l'imposer |
| 8 | 39 | `allowas-in` vers l'agence | Stabilité | Moyenne | Accepte des routes qui contiennent déjà l'AS 65000 : boucles possibles ; inutile dans notre topologie | Retirer |
| 9 | 19 (absence) | Pas de `bgp router-id` | Stabilité | Moyenne | FRR choisit la plus haute adresse : après E25, ce peut être une VIP, **identique** sur `gw01` et `gw02` → sessions refusées | `bgp router-id` fixe et propre à chaque passerelle (10.10.10.2, 10.10.10.3) |
| 10 | 5-7 | `log syslog debugging`, `debug bgp updates` en production | Expl. | Moyenne | Journal saturé (chaque mise à jour), perte de performance ; les vrais messages noyés | `log syslog informational` ; débogage activé ponctuellement, puis retiré |
| 11 | 2 et notes | Configuration de FRR 8.4, même AS 65000 que le nôtre | Expl. | Faible | Syntaxe ancienne (comportements par défaut différents) ; pendant une migration où les deux bordures coexisteraient, l'AS identique fait rejeter les routes de l'une par l'autre (boucle d'AS) | Relire contre FRR 10.7 ; planifier la coexistence avec des AS distincts |

**À garder** : le principe d'une route *blackhole* qui ancre un agrégat annoncé (repris sur `lyo-gw01`, E19) ; un filtre d'**entrée** propre à l'agence (`AGENCE-IN`, à resserrer) ; les descriptions des voisins ; `service integrated-vtysh-config` (un seul fichier).

**Configuration proposée** : [`frr-bordure.conf.propose`](fichiers/M07-E23/frr-bordure.conf.propose) (session LYO1 seule, telle que le rôle `frr` la produit).

**Avis à InfoGér** (exemple) : « Merci pour la transmission de la configuration de rt-bord-01. Nous ne la reprendrons pas telle quelle. Elle a fonctionné dans votre contexte, mais trois points sont incompatibles avec nos exigences : la désactivation de la politique eBGP obligatoire, qui fait réannoncer à chaque voisin tout ce qui est appris des autres ; l'écoute passive ouverte à tout notre réseau interne, qui permettrait à n'importe quel hôte de détourner un service par une route plus précise ; la redistribution non filtrée, qui annoncerait notre réseau d'administration à l'agence. S'y ajoutent des temporisateurs trop courts pour un lien à travers Internet et un secret partagé diffusé. Nous gardons le principe de l'agrégat ancré sur une route nulle et le filtrage d'entrée de l'agence. Notre configuration est décrite dans notre outil de gestion de configuration, relue par revue de code, et applique une politique explicite à chaque voisin. Pour la transition, nous vous demandons : la liste des préfixes réellement annoncés par vos clients hébergés, l'état actuel des sessions et leur historique d'incidents, et le renouvellement du secret des sessions encore actives, désormais public. »

**En production chez MédiSphère**
Toute configuration reçue d'un tiers passe par la même revue que celle d'un stagiaire ; la bordure n'accepte que des configurations produites par le rôle `frr` à partir de données relues.
