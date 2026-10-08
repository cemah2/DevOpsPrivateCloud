# Module 08 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les fichiers complets sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `fichiers/M08-EXX/ceph/…` = chemins de `plateforme/ceph`, `…/ansible/…` = `plateforme/ansible`, `…/infra/…` = `plateforme/infra`, `…/medisphere/…` = la documentation ; les autres fichiers (scripts d'exercice, politiques JSON) se posent dans `~/m08/eXX/`. On **superpose** les dossiers dans l'ordre (E10, E11…) ; un fichier d'un exercice plus récent remplace le précédent, et le dossier [`M08-E23/ceph/`](fichiers/M08-E23/ceph/) est l'état final complet du projet `plateforme/ceph`. Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête), les `*.exemple` des modèles sans valeur réelle.

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Spécifications cephadm* : chaque spécification de `plateforme/ceph` (et les fichiers fautifs de la revue) a été chargée avec les classes `ServiceSpec`/`HostSpec` de `python-common` de Ceph **v20.2.3** (`ServiceSpec.from_json(...).validate()`) : les champs utilisés existent dans cette version (`only_bind_port_on_networks`, `first_virtual_router_id`, `health_check_interval`, `ssl_cert`/`ssl_key` séparés pour *ingress*, `location` des hôtes). Le gabarit haproxy de cephadm 20.2.3 a été lu : le frontal TLS charge `haproxy.pem` (et `haproxy.pem.key` si `ssl_key` est fourni), et le serveur RGW est contrôlé par `HEAD /`.
- *Syntaxe des commandes* : relevée dans la documentation Tentacle et, en cas de doute, dans le code 20.2.3 (`radosgw-admin account create|get|stats`, `user list --account-name`, `ceph fs subvolume authorize`, `ceph nfs export create cephfs … --client_addr`, `ceph orch osd rm --replace --zap`, `ceph orch certmgr`, `cephadm shell` qui transmet l'entrée standard au conteneur).
- *Scripts* : ShellCheck 0.11 et `bash -n` sur tous les scripts et les checks ; `yq` 4 sur les spécifications ; `jq` sur les politiques IAM. Les outils de `plateforme/ceph` (`verifier-specs.sh`, `tests/tester-regles.sh`, `tester-crush.sh`, `derive.sh`, `config-cluster.sh`, `rapport-capacite.sh`) ont été exécutés contre un **faux** `ceph` qui rejoue des sorties JSON plausibles : règles maison (les fichiers de Lucas échouent aux huit règles), cas fautifs rejetés, détection d'écarts. `crushtool` 19.2 (Ubuntu) a compilé et testé `config/crush-attendu.txt` (règles par baie complètes, EC 4+2 impossible). Les vérifications E14 et E20 ont tourné contre ce faux cluster (vertes, puis rouges sur un pool mal placé).
- *Ansible* : le rôle `ceph_client` étendu (E10) et son scénario Molecule passent `ansible-lint` 26.9 en profil `production` (ansible-core 2.21, `ansible.posix` 2.2).

**Non rejoués sur un cluster réel** : comportement fin des MDS en bascule, chemin exact du répertoire `.snap` d'un sous-volume v2, politique de provisioner step-ca (`policy.x509.allow.dns`) appliquée par le rôle `step_ca`, `ceph auth rotate` sur un mappage krbd ouvert, sortie JSON exacte de `radosgw-admin user list --account-name`, nom du service de restauration de LIO sous Debian 13 (`rtslib-fb-targetctl`), restriction `with` des capacités `mgr` sur les arguments booléens. Ils sont signalés « ⚠️ À vérifier sur ton lab » : signale tes retours.

**Où lancer les commandes.** `[root@ceph01 ~]#` = en root sur un nœud `_admin` (`ceph`, `rbd`, `rados`, `radosgw-admin` du paquet `ceph-common` 20.2.3, palier 1). `crushtool` est dans le paquet `ceph-base`, absent des nœuds : on le lance dans le conteneur de la release, `sudo cephadm shell --mount <dossier>:/mnt -- crushtool …`. Depuis `adm01`, une commande isolée : `ssh ceph01 sudo ceph …` (l'entrée standard est transmise : `ceph orch apply -i -`).

---

### M08-E10 — CephFS : volumes, sous-volumes et clients

**Solution**

Fichiers : [`outillage.sh`](fichiers/M08-E10/outillage.sh) (étapes 2 à 4 rejouables depuis `adm01`), [`mds.yaml`](fichiers/M08-E10/ceph/specs/mds.yaml) (export de la spécification produite), [`outils/ajouter-cle-ceph.sh`](fichiers/M08-E10/ansible/outils/ajouter-cle-ceph.sh) (clé cephx → Vault, sans copie en clair), le rôle [`ceph_client`](fichiers/M08-E10/ansible/roles/ceph_client/) étendu (montages CephFS) et son scénario [Molecule](fichiers/M08-E10/ansible/molecule/ceph_client/), [`ceph_client.yml`](fichiers/M08-E10/ansible/inventories/lab/group_vars/role_ceph_client/ceph_client.yml), [`vault-lab.yml.exemple`](fichiers/M08-E10/ansible/inventories/lab/group_vars/role_ceph_client/vault-lab.yml.exemple), [`fstab.extrait`](fichiers/M08-E10/fstab.extrait) (la ligne que produit le rôle).

1. **Lecture.** `ceph fs volume create` crée les deux pools (`cephfs.<vol>.meta`, `cephfs.<vol>.data`), le système de fichiers (`ceph fs new`) **et** demande à l'orchestrateur de déployer les MDS (service `mds.<vol>`) ; `ceph fs new` ne fait que la deuxième étape et suppose pools et MDS existants. Un sous-volume est un répertoire `/volumes/<groupe>/<sous-volume>/<uuid>` : le niveau `<uuid>` (format « v2 » des sous-volumes) permet de garder les instantanés d'un sous-volume supprimé (`--retain-snapshots`) et de le recréer sans collision ; le niveau `/volumes` isole ce que gère le module `volumes` de ce qu'un administrateur créerait à la racine. On ne monte donc jamais « `/plateforme/outillage` » : on demande le chemin (`getpath`).
2. **MDS et volume.**
   ```
   admin@adm01:~/src/ceph$ ssh ceph01 sudo ceph orch apply -i - < specs/hosts.yaml    # après la MR « mds » sur ceph01, ceph02
   [root@ceph01 ~]# ceph orch host ls                  # étiquettes
   [root@ceph01 ~]# ceph config set mds mds_cache_memory_limit 536870912
   [root@ceph01 ~]# ceph fs volume create cephfs "label:mds count:2"
   [root@ceph01 ~]# ceph fs status cephfs
   cephfs - 0 clients
   RANK  STATE            MDS               ACTIVITY     DNS    INOS   DIRS   CAPS
    0    active  cephfs.ceph01.abcdef  Reqs:    0 /s    10     13     12      0
          POOL            TYPE     USED  AVAIL
   cephfs.cephfs.meta  metadata  96.0k   …
   cephfs.cephfs.data    data       0    …
      STANDBY MDS
   cephfs.ceph02.ghijkl
   ```
   Les deux pools prennent la règle par défaut (`replicated_rule`, SSD et HDD mélangés) : E14 corrige cela. `ceph orch ls mds --export` donne la spécification du service (`service_id: cephfs`, `placement: {count: 2, label: mds}`), à versionner (E23).
3. **Sous-volumes.**
   ```
   [root@ceph01 ~]# ceph fs subvolumegroup create cephfs plateforme
   [root@ceph01 ~]# ceph fs subvolumegroup create cephfs applications
   [root@ceph01 ~]# ceph fs subvolume create cephfs outillage --group_name plateforme --size 10737418240
   [root@ceph01 ~]# ceph fs subvolume getpath cephfs outillage --group_name plateforme
   /volumes/plateforme/outillage/5f0c…
   [root@ceph01 ~]# ceph fs subvolume info cephfs outillage --group_name plateforme | grep -E 'bytes_quota|path'
   ```
   La taille s'exprime en **octets** ; elle devient le quota CephFS (`ceph.quota.max_bytes`) du répertoire.
4. **Client.**
   ```
   [root@ceph01 ~]# ceph fs subvolume authorize cephfs outillage outillage --group_name=plateforme --access_level=rw
   [root@ceph01 ~]# ceph auth get client.outillage
   [client.outillage]
   	key = AQ…
   	caps mds = "allow rw path=/volumes/plateforme/outillage/5f0c…"
   	caps mon = "allow r"
   	caps osd = "allow rw pool=cephfs.cephfs.data"
   ```
   `mon allow r` : lire les cartes (où sont les MDS et les OSD) ; `mds … path=` : opérations de métadonnées **sous ce chemin seulement** ; `osd … pool=` : lire et écrire les objets de données (le client écrit directement dans RADOS, le MDS n'y touche pas). ⚠️ À vérifier sur ton lab : selon la version, l'OSD peut être restreint en plus à l'espace de noms du sous-volume quand il a été créé avec `--namespace-isolated` ; sans cela, la restriction de chemin ne protège que les **métadonnées** : un client malveillant qui devine les noms d'objets pourrait lire d'autres données du pool (c'est écrit dans la page *Client Auth*). Pour un cloisonnement entre équipes (E31), on isole par espace de noms.
   **Clé dans le Vault, sans copie en clair** ([`ajouter-cle-ceph.sh`](fichiers/M08-E10/ansible/outils/ajouter-cle-ceph.sh), depuis la racine de `~/src/ansible`) :
   ```
   admin@adm01:~/src/ansible$ outils/ajouter-cle-ceph.sh client.outillage
   vault_ceph_cle_outillage ajoutée à inventories/lab/group_vars/role_ceph_client/vault-lab.yml (chiffré, identité lab).
   ```
   Le script lit la clé par `ssh ceph01 sudo ceph auth get-key` dans une variable du shell, la concatène au contenu déchiffré (`ansible-vault view`) et renvoie le tout dans `ansible-vault encrypt --output … -` : la clé ne passe ni par l'écran, ni par un fichier en clair, ni par une ligne de commande visible dans `ps` (`printf` est une commande interne de `bash`).
5. **Montage.** Essai à la main d'abord (copie temporaire de la clé, effacée ensuite) :
   ```
   admin@adm01:~$ ssh ceph01 sudo ceph auth get-key client.outillage | ssh cephcli01 'sudo install -m 600 /dev/stdin /root/essai.secret'
   admin@cephcli01:~$ sudo mkdir -p /mnt/outillage
   admin@cephcli01:~$ sudo mount -t ceph outillage@.cephfs=/volumes/plateforme/outillage/5f0c… /mnt/outillage \
       -o secretfile=/root/essai.secret,ms_mode=prefer-crc
   admin@cephcli01:~$ df -h /mnt/outillage
   Filesystem       Size  Used Avail Use% Mounted on
   10.10.30.51:3300,…:/volumes/plateforme/outillage/5f0c…   10G     0   10G   0% /mnt/outillage
   admin@cephcli01:~$ sudo umount /mnt/outillage && sudo shred -u /root/essai.secret
   ```
   La taille affichée est le **quota** du sous-volume. Puis le rôle : variable `ceph_client_cephfs` (point, utilisateur, chemin), tâches qui écrivent `/etc/ceph/<utilisateur>.secret` (0600, la clé seule, tirée de `ceph_client_cles`, `no_log`) et l'entrée `fstab` par `ansible.posix.mount` en `state: mounted` ; une assertion refuse un montage dont la clé n'est pas déclarée ; le scénario Molecule vérifie fichier de clé, entrée `fstab` v2, `secretfile`, `_netdev`, absence de `secret=`. Ligne produite ([`fstab.extrait`](fichiers/M08-E10/fstab.extrait)) :
   ```
   outillage@<FSID>.cephfs=/volumes/plateforme/outillage/<UUID>  /mnt/outillage  ceph  secretfile=/etc/ceph/outillage.secret,ms_mode=prefer-crc,noatime,_netdev  0  0
   ```
   `_netdev` fait attendre le réseau (sinon le montage échoue au démarrage, avant l'interface) ; `ms_mode=prefer-crc` fait parler le noyau en **msgr2** (port 3300) plutôt qu'en protocole v1 (port 6789) : c'est ce qui permettra le mode `secure` du palier 3. Le `fsid` est écrit en entier (le rôle le connaît) plutôt que laissé à `mount.ceph`. `uv run ansible-playbook playbooks/ceph-clients.yml`, puis `sudo systemctl reboot` sur `cephcli01` : `findmnt /mnt/outillage` montre le montage.
6. **Limites.**
   - Racine du volume avec `client.outillage` : `mount error: permission denied` (le MDS refuse le chemin `/`, hors de `path=`).
   - Quota réduit (`ceph fs subvolume resize cephfs outillage 1073741824 --group_name plateforme`), puis `dd if=/dev/zero of=/mnt/outillage/gros bs=4M count=300` : `dd: error writing '/mnt/outillage/gros': Disk quota exceeded` vers 1 Gio (l'application est un peu tardive : le client vérifie le quota par tranches, d'où un léger dépassement possible). On efface, puis `resize … 10737418240`.
7. **Instantanés.**
   ```
   [root@ceph01 ~]# ceph fs subvolume snapshot create cephfs outillage avant-essai --group_name plateforme
   admin@cephcli01:~$ ls /mnt/outillage/.snap/
   _avant-essai_1099511627776
   admin@cephcli01:~$ cp /mnt/outillage/.snap/_avant-essai_*/scripts/bascule.sh /mnt/outillage/scripts/
   [root@ceph01 ~]# ceph fs subvolume snapshot ls cephfs outillage --group_name plateforme
   ```
   L'instantané est pris sur le répertoire du sous-volume (le parent du niveau `<uuid>`) ; vu depuis le point de montage, il apparaît dans `.snap` sous la forme `_<nom>_<inode>` (instantané d'un ancêtre). ⚠️ À vérifier sur ton lab : le nom exact affiché dans `.snap`.
8. **Bascule.** `ceph orch ps --daemon-type mds` donne le nom du démon actif ; `ceph orch daemon stop mds.cephfs.ceph01.abcdef`. `ceph fs status` montre le rang 0 passer par `replay`, `reconnect`, `rejoin` puis `active` sur `ceph02`. L'écriture (`while true; do date >> /mnt/outillage/horloge; sleep 1; done`) se fige de quelques secondes à une quinzaine de secondes (le moniteur attend le *beacon* manquant, `mds_beacon_grace` = 15 s, sauf arrêt propre qui le prévient tout de suite), puis reprend seule : le client se reconnecte et reprend ses capacités. `ceph orch daemon start …` remet le démon en attente.

**Explications**

CephFS sépare **métadonnées** (arborescence, droits, verrous de cohérence entre clients : les *capabilities*) et **données** : le MDS ne fait que les premières, le client lit et écrit directement les objets dans les OSD. D'où les trois capacités du client (`mon`, `mds`, `osd`), et l'importance du MDS pour la latence des opérations de fichiers (ouvrir, lister, créer) mais pas pour le débit. Le MDS garde son état dans le pool de métadonnées : un MDS en attente peut reprendre le rang, il relit le journal et attend que les clients se reconnectent. Le module `volumes` du gestionnaire ajoute la notion de sous-volume (quota, chemin isolé, instantanés, autorisations), celle que consomment le CSI de Kubernetes (M16) et Manila d'OpenStack.

**Alternatives**
- *Client FUSE* (`ceph-fuse`) : suit les versions de Ceph plutôt que celles du noyau, plus lent ; utile si le noyau est ancien.
- *`ceph fs authorize`* au lieu de `subvolume authorize` : même résultat, mais il faut connaître le chemin ; l'interface `subvolume` garde la trace des clients autorisés (`authorized_list`) et sait les évincer (`evict`).
- *Clé dans `/etc/fstab`* (`secret=`) : lisible par tous (`/etc/fstab` est en 644) : à proscrire.
- *Montage par `systemd.mount`* plutôt que `fstab` : équivalent, plus explicite sur les dépendances.

**Pièges classiques**
- Oublier le point dans `outillage@.cephfs=` : le noyau attend `<utilisateur>@<fsid>.<fs>` ; le point seul laisse `mount.ceph` trouver le `fsid` dans `ceph.conf`.
- Monter sans `_netdev` : démarrage bloqué ou montage absent après redémarrage.
- Laisser le cache du MDS à 4 Gio par défaut sur un nœud de 6 Go qui porte déjà trois OSD : le MDS grossit avec le nombre de fichiers ouverts, jusqu'à l'OOM.
- Placer le volume sans étiquette : l'orchestrateur choisit deux hôtes au hasard, éventuellement `ceph03` qui portera RGW.
- Croire que la restriction de chemin isole les données (voir étape 4).

**En production chez MédiSphère**
Instantanés programmés (`snap-schedule`, conservation 7 jours / 4 semaines), supervision des sessions client et des alertes `MDS_SLOW_REQUEST`, `MDS_CACHE_OVERSIZED` (E24), MDS en *standby-replay* pour les volumes critiques, sous-volumes isolés par espace de noms pour les équipes (E31), sauvegarde des sous-volumes hors cluster (E25).

---

### M08-E11 — RGW : la passerelle S3 et son point d'entrée

**Solution**

Fichiers : [`specs/rgw.yaml`](fichiers/M08-E11/ceph/specs/rgw.yaml), [`specs/ingress.yaml`](fichiers/M08-E11/ceph/specs/ingress.yaml), [`outils/cert-ingress.sh`](fichiers/M08-E11/ceph/outils/cert-ingress.sh), unités [`ceph-cert-ingress.service`](fichiers/M08-E11/ceph/outils/systemd/ceph-cert-ingress.service) et [`.timer`](fichiers/M08-E11/ceph/outils/systemd/ceph-cert-ingress.timer), [`step_ca.yml.extrait`](fichiers/M08-E11/ansible/inventories/lab/group_vars/role_pki/step_ca.yml.extrait), [`vault-critique.yml.extrait`](fichiers/M08-E11/ansible/inventories/lab/group_vars/role_pki/vault-critique.yml.extrait), [`pare_feu.yml.extrait`](fichiers/M08-E11/ansible/inventories/lab/pare_feu.yml.extrait), [`registre-secrets.extrait.md`](fichiers/M08-E11/medisphere/registre-secrets.extrait.md).

1. **Lecture.** Au premier démarrage, RGW crée `.rgw.root` (configuration des *realms*/zones), `default.rgw.log`, `default.rgw.control`, `default.rgw.meta`, puis à la première écriture `default.rgw.buckets.index` et `default.rgw.buckets.data` (et `.non-ec`). keepalived porte la VIP sur un des hôtes d'*ingress* ; chaque keepalived vérifie son haproxy local (script de contrôle) et échange des annonces VRRP en **unicast** (défaut cephadm) avec les autres : si le maître se tait ou si son haproxy ne répond plus, un autre prend la VIP. Trois démons RGW et trois hôtes d'*ingress* : avec deux, la perte d'un nœud laisse **un seul** RGW (toute la charge sur lui, plus de redondance pendant la réparation) et un seul couple haproxy/keepalived ; c'est acceptable au lab, pas en production.
2. **RGW.**
   ```
   admin@adm01:~/src/ceph$ ssh ceph01 sudo ceph orch apply -i - < specs/hosts.yaml          # étiquette rgw (MR fusionnée)
   admin@adm01:~/src/ceph$ ssh ceph01 sudo ceph orch apply -i - --dry-run < specs/rgw.yaml
   admin@adm01:~/src/ceph$ ssh ceph01 sudo ceph orch apply -i - < specs/rgw.yaml
   admin@cephcli01:~$ curl -s http://10.10.30.52:8080/ | head -c 200
   <?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult …><Owner><ID>anonymous</ID>…
   [root@ceph01 ~]# ceph osd pool ls | grep rgw
   ```
   `networks: [10.10.30.0/24]` et `only_bind_port_on_networks: true` : le démon n'écoute que sur l'adresse du réseau public, pas sur le réseau de réplication.
3. **NetBox et DNS.** Adresse `10.10.30.200/24`, statut actif, rôle *VIP*, `dns_name: rgw.par1.medisphere.internal`, description « Point d'entrée S3 de ceph-par1 (ingress cephadm, PLAT-921) ». Au passage suivant de `medictl dns sync` (M06-E15) : `dig +short rgw.par1.medisphere.internal` → `10.10.30.200`, `dig +short -x 10.10.30.200` → le nom.
4. **Provisioner.**
   ```
   admin@adm01:~$ (umask 077; openssl rand -base64 24 > ~/.config/workbook/step-ceph-ingress.pass)
   admin@adm01:~$ cd "$(mktemp -d)"
   admin@adm01:/tmp/tmp.X$ step crypto jwk create ceph-ingress.pub.json ceph-ingress.key.json --kty EC --crv P-256 \
       --use sig --password-file ~/.config/workbook/step-ceph-ingress.pass
   admin@adm01:/tmp/tmp.X$ step crypto jose format < ceph-ingress.key.json   # → vault_step_ca_ceph_ingress_cle_chiffree
   ```
   Entrée ajoutée à `step_ca_provisioners` ([extrait](fichiers/M08-E11/ansible/inventories/lab/group_vars/role_pki/step_ca.yml.extrait)) :
   ```yaml
   - type: JWK
     name: ceph-ingress
     key: {use: sig, kty: EC, kid: "<KID>", crv: P-256, alg: ES256, x: "<X>", y: "<Y>"}
     encryptedKey: "{{ vault_step_ca_ceph_ingress_cle_chiffree }}"
     claims: {minTLSCertDuration: 1h, maxTLSCertDuration: 720h, defaultTLSCertDuration: 720h}
     policy:
       x509:
         allow:
           dns: [rgw.par1.medisphere.internal]
   ```
   MR, pipeline de `plateforme/ansible` (rôle `step_ca`, qui valide `ca.json` et revient en arrière si step-ca ne démarre pas, M06-E02), puis :
   ```
   admin@adm01:~$ step ca provisioner list | jq -r '.[].name'
   admin
   acme
   sshpop
   ceph-ingress
   admin@adm01:~$ step ca certificate essai.par1.medisphere.internal /tmp/e.crt /tmp/e.key --provisioner ceph-ingress \
       --provisioner-password-file ~/.config/workbook/step-ceph-ingress.pass
   … the request is not authorized … not allowed …
   ```
   (Libellé exact du refus selon la version : ⚠️ à vérifier sur ton lab ; ce qui compte est le refus.) La politique ne vaut que pour **ce** provisioner : les autres gardent leurs règles. Le registre des secrets reçoit la clé du provisioner (Vault `critique`, rotation annuelle) et le mot de passe (fichier de `adm01` + Vault `critique`).
5. **Émission.**
   ```
   admin@adm01:~$ install -d -m 700 ~/.config/workbook/ceph-ingress
   admin@adm01:~$ step ca certificate rgw.par1.medisphere.internal ~/.config/workbook/ceph-ingress/cert.pem \
       ~/.config/workbook/ceph-ingress/cle.pem --provisioner ceph-ingress \
       --provisioner-password-file ~/.config/workbook/step-ceph-ingress.pass --not-after 720h
   admin@adm01:~$ step certificate inspect --short ~/.config/workbook/ceph-ingress/cert.pem
   ```
   `step ca certificate` écrit la chaîne (feuille + intermédiaire), ce qu'attend haproxy ; la clé est créée en 600.
6. **Spécification et application.** [`ingress.yaml`](fichiers/M08-E11/ceph/specs/ingress.yaml) (sans certificat) :
   ```yaml
   service_type: ingress
   service_id: rgw.par1
   placement:
     label: rgw
   spec:
     backend_service: rgw.par1
     virtual_ip: 10.10.30.200/24
     frontend_port: 443
     monitor_port: 1967
     first_virtual_router_id: 80
     health_check_interval: 2s
   ```
   [`cert-ingress.sh`](fichiers/M08-E11/ceph/outils/cert-ingress.sh) assemble la spécification avec `yq` (`.spec.ssl_cert = load_str(…)`, `.spec.ssl_key = load_str(…)`), l'envoie par l'entrée standard de `ssh` à `sudo ceph orch apply -i -` sur `ceph01` : la clé ne touche **aucun disque** de `ceph01` (cephadm la stocke ensuite dans la base de configuration des moniteurs, d'où elle est déposée dans le conteneur haproxy). Sans argument il applique ; avec `--verifier`, il affiche seulement le `--dry-run`.
7. **Contrôles.**
   ```
   admin@adm01:~$ curl -sS https://rgw.par1.medisphere.internal/ -o /dev/null -w '%{http_code}\n'
   200
   admin@adm01:~$ openssl s_client -connect rgw.par1.medisphere.internal:443 -servername rgw.par1.medisphere.internal </dev/null 2>/dev/null \
       | openssl x509 -noout -issuer -subject -dates
   issuer=CN=MédiSphère Intermediate CA …
   [root@ceph01 ~]# ceph orch ps --service_name ingress.rgw.par1
   admin@adm01:~$ for h in ceph02 ceph03; do ssh $h ip -br addr show | grep -q 10.10.30.200 && echo "VIP sur $h"; done
   ```
   `curl` fait confiance à la racine du magasin système de `adm01` et `cephcli01` (rôle `ca_lab`) : pas d'option de contournement.
8. **Bascule.** `ceph orch daemon stop haproxy.rgw.par1.ceph02.xxxx` sur le nœud maître ; depuis `cephcli01` :
   ```
   admin@cephcli01:~$ while sleep 0.5; do printf '%s %s\n' "$(date +%T.%N | cut -c1-12)" \
       "$(curl -s -o /dev/null -m 2 -w '%{http_code}' https://rgw.par1.medisphere.internal/)"; done
   ```
   On lit 3 à 6 secondes de `000` : le script de contrôle de keepalived constate l'absence de haproxy, abaisse la priorité, l'autre keepalived prend la VIP et envoie un ARP gratuit. `ceph orch daemon start …` (le maître reprend la VIP s'il a la priorité la plus haute, nouvelle coupure courte : c'est le comportement par défaut, sans `nopreempt`).
9. **Renouvellement.** Le script fait : si `step certificate needs-renewal --expires-in 360h` dit « oui » (ou `--force`), `step ca renew --force` (TLS mutuel avec le certificat en cours, aucun mot de passe) ; si le certificat a **expiré** (renouvellement refusé, `allowRenewalAfterExpiry: false`), nouvelle émission avec le provisioner ; puis, si l'empreinte du certificat a changé ou si haproxy ne présente pas celui-ci, application de la spécification ; enfin vérification que la VIP présente bien la nouvelle empreinte. Les unités : `Type=oneshot`, `User=admin`, `OnFailure=ms-alerte@%n.service`, minuterie quotidienne (`OnCalendar=daily`, `RandomizedDelaySec=1h`, `Persistent=true`). Quotidien suffit : on renouvelle à 15 jours de l'échéance, il y a donc quinze tentatives avant l'expiration.
   ```
   admin@adm01:~$ sudo systemctl enable --now ceph-cert-ingress.timer
   admin@adm01:~$ ~/src/ceph/outils/cert-ingress.sh --force
   admin@adm01:~$ openssl s_client -connect rgw.par1.medisphere.internal:443 </dev/null 2>/dev/null | openssl x509 -noout -serial
   ```
10. **Flux.** Ligne de la matrice ([extrait](fichiers/M08-E11/ansible/inventories/lab/pare_feu.yml.extrait)) : transit `entree: $V_INFRA, sortie: $V_STOPUB, source: $RUNNER01, destination: 10.10.30.200, proto: tcp, ports: 443`, motif « runner01 → S3 de ceph-par1 (tests CI de MédiDoc) », réf. M08-E11 ; MR, pipeline (les deux passerelles reçoivent la même matrice), matrice documentaire. `curl` depuis `runner01` : 200.

**Explications**

Le service `ingress` est une petite **paire HA** générée par cephadm : un haproxy par hôte qui répartit vers tous les RGW (contrôle `HEAD /` toutes les 2 s, `balance static-rr`), un keepalived par hôte qui porte la VIP. haproxy écoute sur la VIP même quand elle n'est pas locale (cephadm active `net.ipv4.ip_nonlocal_bind`), d'où une bascule rapide. Le TLS se termine sur haproxy ; entre haproxy et RGW, le trafic est en HTTP sur le VLAN 30, réseau de stockage non routé vers les autres VLAN sauf par les passerelles filtrantes. Le certificat de service n'est pas obtenu par ACME parce que **rien ne peut répondre au défi** : on remplace la preuve de contrôle du nom (ACME) par une preuve de possession d'un secret (JWK) **limitée** à un nom et à 30 jours, puis on renouvelle par le certificat lui-même. C'est le même compromis que la politique de certification fait pour les certificats émis « à la main », en plus étroit.

**Alternatives**
- *Certificat auto-signé par cephadm* (`generate_cert: true` côté RGW, CA de `certmgr`) : renouvelé seul, mais signé par une autorité propre au cluster que chaque client devrait ajouter à sa confiance. Écarté : une seule racine de confiance pour MédiSphère.
- *ACME DNS-01* (enregistrement TXT posé dans PowerDNS par un client ACME comme `lego`) : la vraie preuve de contrôle du nom, sans port 80 ; un outil et un droit d'écriture dans la zone de plus. Bonne cible quand plusieurs services seront dans ce cas.
- *Publier RGW derrière `lb01`/`lb02`* (M07) : un seul point d'entrée HTTPS pour toute la plateforme, certificats ACME déjà gérés ; mais un saut de plus, et les répartiteurs de la DMZ deviennent un chemin critique du stockage. Ce sera le chemin d'une **publication** externe (MédiDoc vu d'Internet), pas de l'accès interne.
- *Trois RGW et trois hôtes d'ingress* : la recommandation de la documentation, à faire dès que la mémoire le permet (ou avec `ceph04`).

**Pièges classiques**
- `virtual_ip` sans masque, ou en `/32` : cephadm ne trouve pas d'interface ayant une adresse dans ce réseau, keepalived ne monte pas la VIP.
- RGW et haproxy sur le même port (443) des mêmes hôtes : conflit de port, l'un des deux ne démarre pas (E21).
- VRID par défaut (50) : sans conséquence ici, mais deux services *ingress* sur un même segment avec le même VRID se battent pour leurs VIP. Un VRID choisi et documenté évite la surprise.
- Mettre `ssl_cert` (et la clé) dans le fichier versionné, ou laisser une copie de la spécification complète dans `/tmp` de `ceph01`.
- Renouveler le certificat sans réappliquer la spécification : haproxy présente l'ancien jusqu'à l'expiration.
- Oublier le flux `runner01` → VIP sur **les deux** passerelles (même matrice : c'est le rôle `pare_feu` qui s'en charge).

**En production chez MédiSphère**
Trois RGW et trois haproxy, supervision du certificat présenté (sonde d'expiration de M06-E29 étendue à la VIP, alerte `CEPHADM_CERT_ERROR` de `certmgr`), statistiques haproxy (port 1967, `/metrics`) dans Prometheus, journal d'accès RGW centralisé (M22), limitation de débit par compte.

---

### M08-E12 — RGW : comptes, utilisateurs, quotas et politiques

**Solution**

Fichiers : [`medidoc.sh`](fichiers/M08-E12/medidoc.sh) (création du compte et des quotas, étapes 2), politiques [`medidoc-app.json`](fichiers/M08-E12/politiques/medidoc-app.json), [`medidoc-audit.json`](fichiers/M08-E12/politiques/medidoc-audit.json), [`medidoc-documents.json`](fichiers/M08-E12/politiques/medidoc-documents.json) (politique de compartiment), [`s3-medidoc.env.exemple`](fichiers/M08-E12/s3-medidoc.env.exemple).

1. **Lecture.** Les compartiments créés par un utilisateur d'un compte appartiennent **au compte** (propriétaire = identifiant `RGW…`), visibles de tous ses utilisateurs autorisés ; les quotas et statistiques portent sur le compte entier. Un utilisateur IAM d'un compte naît **sans aucune permission** (contrairement à un utilisateur RGW classique, qui peut créer des compartiments) : tout passe par une politique explicite. C'est le modèle d'AWS : le refus par défaut.
2. **Compte et quotas.**
   ```
   [root@ceph01 ~]# radosgw-admin account create --account-name=medidoc --email=medidoc@medisphere.internal
   { "id": "RGW62014877450193748", "tenant": "", "name": "medidoc", … }
   [root@ceph01 ~]# radosgw-admin user create --uid=medidoc-racine --display-name=medidoc-racine \
       --account-id=RGW62014877450193748 --account-root --gen-access-key --gen-secret
   [root@ceph01 ~]# radosgw-admin quota set --quota-scope=account --account-id=RGW62014877450193748 --max-size=20G
   [root@ceph01 ~]# radosgw-admin quota enable --quota-scope=account --account-id=RGW62014877450193748
   [root@ceph01 ~]# radosgw-admin quota set --quota-scope=bucket --account-id=RGW62014877450193748 --max-objects=1000000
   [root@ceph01 ~]# radosgw-admin quota enable --quota-scope=bucket --account-id=RGW62014877450193748
   [root@ceph01 ~]# radosgw-admin account get --account-name=medidoc
   ```
   La sortie de `user create` contient la clé secrète : lancée telle quelle, elle s'affiche à l'écran (et dans le défilement du terminal). Le script [`medidoc.sh`](fichiers/M08-E12/medidoc.sh) la fait passer de `ceph01` à `adm01` par un tube, dans un fichier 600 de `~/.config/workbook/`, sans l'afficher, et rappelle de la chiffrer dans le Vault `critique` puis d'effacer le fichier.
3. **Profil de l'utilisateur racine** (saisie interactive, rien dans l'historique) :
   ```
   admin@adm01:~$ aws configure --profile medidoc-racine          # clés saisies à l'invite
   admin@adm01:~$ aws configure set --profile medidoc-racine endpoint_url https://rgw.par1.medisphere.internal
   admin@adm01:~$ aws configure set --profile medidoc-racine s3.addressing_style path
   admin@adm01:~$ export AWS_PROFILE=medidoc-racine AWS_REQUEST_CHECKSUM_CALCULATION=when_required
   admin@adm01:~$ aws s3api create-bucket --bucket medidoc-documents
   admin@adm01:~$ aws s3api create-bucket --bucket medidoc-journaux
   admin@adm01:~$ aws s3api put-bucket-versioning --bucket medidoc-documents --versioning-configuration Status=Enabled
   admin@adm01:~$ aws iam create-user --user-name medidoc-app
   admin@adm01:~$ aws iam create-user --user-name medidoc-audit
   admin@adm01:~$ aws iam put-user-policy --user-name medidoc-app --policy-name documents-rw --policy-document file://politiques/medidoc-app.json
   admin@adm01:~$ aws iam put-user-policy --user-name medidoc-audit --policy-name lecture --policy-document file://politiques/medidoc-audit.json
   admin@adm01:~$ aws iam create-access-key --user-name medidoc-app > "$(mktemp -p ~/.config/workbook)"   # puis s3-medidoc-app.env, Vault lab
   ```
   ⚠️ `aws configure` (profil) écrit les clés dans `~/.aws/credentials` (600) : c'est un secret de plus sur `adm01`, à inscrire au registre, ou à supprimer (`aws configure set … ""`) après la séance. Le profil racine ne sert qu'à l'administration du compte.
   Politique de `medidoc-app` (extrait) : `s3:ListBucket` et `s3:GetBucketLocation` sur `arn:aws:s3:::medidoc-documents`, `s3:GetObject`, `s3:GetObjectVersion`, `s3:PutObject`, `s3:DeleteObject` sur `arn:aws:s3:::medidoc-documents/*`. Rien sur `medidoc-journaux`, aucun droit IAM.
   Politique de `medidoc-audit` : `s3:ListBucket`, `s3:ListBucketVersions`, `s3:GetBucketVersioning` (l'audit vérifie que le versionnage est actif) et `s3:GetObject`/`s3:GetObjectVersion` sur les deux compartiments.
4. **Politique de compartiment** ([`medidoc-documents.json`](fichiers/M08-E12/politiques/medidoc-documents.json)) : `Deny` de `s3:DeleteObjectVersion` (et `s3:PutBucketVersioning`, pour qu'on ne puisse pas suspendre le versionnage) aux deux utilisateurs IAM, nommés par leur ARN (`arn:aws:iam::RGW…:user/medidoc-app`). Pourquoi pas `"Principal": "*"` : un refus explicite l'emporte sur tout, **y compris sur l'utilisateur racine du compte** (la documentation des comptes le dit) ; le refus « à tout le monde sauf la racine » s'écrit donc en listant les principaux à refuser, ou avec `NotPrincipal` (⚠️ à vérifier sur ton lab : prise en charge de `NotPrincipal` par RGW). `aws s3api put-bucket-policy --bucket medidoc-documents --policy file://politiques/medidoc-documents.json`.
5. **Essais.**

   | Utilisateur | Action | Résultat | Pourquoi |
   |---|---|---|---|
   | `medidoc-app` | `aws s3 cp f.pdf s3://medidoc-documents/` | OK | `s3:PutObject` sur `/*` |
   | `medidoc-app` | `aws s3 rm s3://medidoc-documents/f.pdf` | OK, marqueur de suppression | versionnage : la version précédente reste |
   | `medidoc-app` | `aws s3api get-object --version-id <ID>` puis `copy-object` | OK : document restauré | `s3:GetObjectVersion` |
   | `medidoc-app` | `aws s3api delete-object --version-id <ID>` | `AccessDenied` | refus explicite de la politique de compartiment |
   | `medidoc-app` | `aws s3 ls s3://medidoc-journaux` | `AccessDenied` | aucun droit sur ce compartiment |
   | `medidoc-app` | `aws s3 mb s3://essai` | `AccessDenied` | pas de `s3:CreateBucket` |
   | `medidoc-audit` | `aws s3 ls`, `get-object` | OK | lecture |
   | `medidoc-audit` | `aws s3 cp` | `AccessDenied` | pas de `s3:PutObject` |
6. **Quota.** `radosgw-admin quota set --quota-scope=account --account-id=… --max-size=50M`, puis envoi d'objets de 10 Mio : au-delà, `An error occurred (QuotaExceeded) when calling the PutObject operation` (HTTP 403). Le quota est évalué sur des statistiques mises à jour de façon asynchrone : le dépassement peut être léger. Rétablir `--max-size=20G`, puis supprimer objets **et** versions (`aws s3api list-object-versions` → `delete-objects` avec la liste des `Versions` et des `DeleteMarkers`, profil racine).
7. **Sans comptes.** Un utilisateur RGW classique par application (`radosgw-admin user create`), éventuellement rangés dans un *tenant* `medidoc` pour isoler les noms de compartiments ; les droits fins passent par des politiques de compartiment, l'utilisateur ne peut pas créer ses propres utilisateurs ni clés : tout repasse par l'équipe plateforme avec `radosgw-admin`. Tentacle déprécie l'IAM au niveau *tenant* (rôles, politiques gérées par l'API IAM hors compte) parce que les **comptes** donnent le même modèle qu'AWS (propriété par le compte, utilisateur racine, IAM complet), avec une frontière d'administration nette ; garder deux modèles IAM parallèles compliquait la sécurité et l'évaluation des politiques.

**Explications**

Trois niveaux d'autorisation se combinent : la **politique d'identité** (ce que l'utilisateur IAM a le droit de faire), la **politique de compartiment** (ce que le compartiment accepte, de qui), et le refus explicite qui l'emporte sur tout. Le versionnage transforme une suppression en ajout (un marqueur) : la récupération d'un document supprimé par erreur est un geste de l'application, sans restauration de sauvegarde. Les quotas du compte protègent le cluster contre une seule équipe ; ceux des compartiments limitent les dérives (millions de petits objets qui gonflent l'index).

**Alternatives**
- *Un compte par environnement* (`medidoc-recette`, `medidoc-prod`) : frontière plus forte, quotas séparés ; à faire pour la production.
- *Rôles et STS* (`sts:AssumeRole`, ou `AssumeRoleWithWebIdentity` avec Keycloak au module 24) au lieu de clés longues pour l'application : plus de clé à faire tourner.
- *Object Lock* (rétention, compartiment créé avec `--object-lock-enabled-for-bucket`) : empêche même la racine de supprimer pendant la durée de rétention ; à réserver aux obligations légales (coût de stockage).

**Pièges classiques**
- Oublier `s3:ListBucket` sur le **compartiment** (et pas `/*`) : l'application ne peut pas lister, les SDK échouent sur un `HeadBucket`.
- Écrire les ARN d'utilisateur avec l'identifiant RGW (`--uid`) au lieu du nom IAM : dans un compte, les principaux sont nommés par leur nom.
- `Deny` avec `"Principal": "*"` : bloque aussi la racine, et plus personne ne peut nettoyer les versions (il faut alors retirer la politique, ce que la racine peut toujours faire).
- Vider un compartiment versionné avec `aws s3 rm --recursive` : il ne pose que des marqueurs ; le compartiment ne se supprime pas, le quota reste consommé.
- Clés de la racine utilisées par l'application « parce que ça marche ».

**En production chez MédiSphère**
Clés applicatives dans Vault (M25) avec rotation, accès de l'application par STS, journalisation des opérations S3 (`rgw_enable_ops_log` ou journaux d'accès) envoyée au SIEM, cycle de vie des versions non courantes, et la décision d'ADR-0080 (E30) sur la place de RGW face à SeaweedFS.

---

### M08-E13 — Cephx : des clients aux droits minimaux

**Solution**

Fichiers : [`cles-clientes.sh`](fichiers/M08-E13/cles-clientes.sh) (capacités et inventaire, depuis `adm01`), [`ceph_client.yml`](fichiers/M08-E13/ansible/inventories/lab/group_vars/role_ceph_client/ceph_client.yml), [`vault-lab.yml.exemple`](fichiers/M08-E13/ansible/inventories/lab/group_vars/role_ceph_client/vault-lab.yml.exemple), [`registre-secrets.extrait.md`](fichiers/M08-E13/medisphere/registre-secrets.extrait.md).

1. **Inventaire** (`ceph auth ls`) :

   | Groupe | Entités | Usage |
   |---|---|---|
   | Démons | `mon.`, `mgr.ceph0X.*`, `osd.N`, `mds.cephfs.*`, `client.rgw.par1.*`, `client.nfs.par1.*`, `client.crash.ceph0X`, `client.ceph-exporter.ceph0X` | une clé par démon, créée par cephadm et rangée dans le dossier du démon (`/var/lib/ceph/<FSID>/<démon>/keyring`) ; certaines ont des droits larges (un RGW a `mon 'allow *'`) : elles ne quittent pas l'hôte du démon |
   | Amorçage | `client.bootstrap-osd`, `-mds`, `-mgr`, `-rgw`, `-rbd`, `-rbd-mirror` | créer de nouvelles clés de démons d'un type donné |
   | Clients | `client.admin`, `client.rbd-test` (E06), `client.outillage` (E10), `client.nfs.par1.<n>…` d'un export (E16, utilisé par Ganesha) | humains et applications |

   `ceph.client.admin.keyring` : sur les trois nœuds `_admin` (`/etc/ceph/`, 600) et nulle part ailleurs ; `sudo find / -xdev -name 'ceph.client.admin.keyring' 2>/dev/null` sur `cephcli01` et `adm01` le confirme (le rôle `ceph_client` refuse d'ailleurs de la déposer).
2. **Capacités.** `allow rwx pool=rbd-test` donne tout sur tous les objets du pool, `x` compris (appel de méthodes des classes d'objets), mais rien d'autre ; `profile rbd pool=rbd-test` donne ce dont un client RBD a besoin et seulement cela : lecture/écriture des objets du pool, méthodes des classes `rbd` et `lock`, lecture des en-têtes des parents de clones… Côté `mon`, `profile rbd` autorise en plus le client à poser un *blocklist* : quand un client reprend le verrou exclusif d'une image dont le détenteur précédent ne répond plus, il doit le bannir pour qu'il ne puisse plus écrire. Sans ce droit, la reprise d'une image après la mort d'un client échoue. `mgr profile rbd` sert aux commandes RBD qui passent par le gestionnaire (corbeille différée, `rbd task`, statistiques `rbd perf`).
3. **Restriction réseau de `client.rbd-test`.**
   ```
   [root@ceph01 ~]# ceph auth caps client.rbd-test \
       mon 'profile rbd network 10.10.30.20/32' \
       osd 'profile rbd pool=rbd-test network 10.10.30.20/32' \
       mgr 'profile rbd pool=rbd-test'
   [root@ceph01 ~]# ceph auth get client.rbd-test
   ```
   `ceph auth caps` **remplace** l'ensemble des capacités : oublier `mgr` le supprimerait. La clé ne change pas : le trousseau déployé par le rôle reste valable, `/mnt/disque01` continue ; un démappage/remappage (`sudo systemctl restart rbdmap` hors heures, ou `rbd device unmap`/`map`) prouve que la nouvelle authentification passe depuis 10.10.30.20.
4. **`client.rbd-lecture`.**
   ```
   [root@ceph01 ~]# ceph auth get-or-create client.rbd-lecture \
       mon 'profile rbd' osd 'profile rbd-read-only pool=rbd-test' mgr 'profile rbd pool=rbd-test' >/dev/null
   admin@adm01:~/src/ansible$ outils/ajouter-cle-ceph.sh client.rbd-lecture
   ```
   Puis `ceph_client.yml` (entrée `client.rbd-lecture` dans `ceph_client_cles`), MR, `uv run ansible-playbook playbooks/ceph-clients.yml`. (`get-or-create` affiche le trousseau : la redirection vers `/dev/null` évite de le laisser dans le terminal.) Pas de restriction réseau ici : la clé servira depuis l'hôte de sauvegarde du palier 3, à ajouter alors.
5. **Preuves.**
   ```
   admin@cephcli01:~$ sudo rbd --id rbd-lecture ls rbd-test
   admin@cephcli01:~$ sudo rbd --id rbd-lecture create rbd-test/essai --size 1G
   rbd: create error: (1) Operation not permitted
   admin@cephcli01:~$ sudo rbd --id rbd-test create rbd-test/essai --size 1G && sudo rbd --id rbd-test rm rbd-test/essai
   [root@ceph02 ~]# rbd --id rbd-test --keyring /root/k ls rbd-test        # copie temporaire, effacée aussitôt
   … (13) Permission denied        # restriction réseau : la session est refusée
   [root@ceph02 ~]# shred -u /root/k
   ```
   ⚠️ À vérifier sur ton lab : l'erreur exacte côté client quand la restriction réseau refuse (`EACCES` à l'authentification ou à l'ouverture du pool).
6. **Rotation.** `ceph auth rotate client.rbd-lecture` produit une nouvelle clé. Une session déjà ouverte continue : elle est authentifiée et ses tickets restent valables jusqu'à leur renouvellement (`auth_service_ticket_ttl`, une heure par défaut) ; ⚠️ à vérifier sur ton lab : au renouvellement suivant du ticket, une session noyau (mappage krbd) avec l'ancienne clé peut échouer, ce qui transforme une rotation en coupure différée. Une nouvelle commande avec l'ancien trousseau échoue immédiatement (`auth: unable to authenticate`). Redéploiement : `outils/ajouter-cle-ceph.sh client.rbd-lecture` (remplace la valeur chiffrée), playbook. Procédure **sans interruption** retenue pour `client.rbd-test` :
   1. créer une **nouvelle** entité (`client.rbd-test-2026b`) avec les mêmes capacités ;
   2. la ranger dans le Vault, la déployer (rôle), basculer `ceph_client_rbdmap` sur le nouvel `id` au prochain créneau (démappage/remappage) ;
   3. vérifier les sessions (`ceph tell mon.* sessions`) : plus aucune avec l'ancienne entité ;
   4. supprimer l'ancienne (`ceph auth rm`) et sa variable du Vault.
   `ceph auth rotate` est réservé aux clés compromises, quand la coupure est préférable au risque.
7. **Registre** ([extrait](fichiers/M08-E13/medisphere/registre-secrets.extrait.md)) : nom de l'entité, usage, capacités, emplacement du trousseau, copie de référence (variable du Vault `lab`), propriétaire, rotation.

**Explications**

Cephx est une authentification à clé partagée de type Kerberos : le client prouve qu'il connaît sa clé au moniteur, reçoit des tickets de service chiffrés pour les autres démons, et chaque démon contrôle les **capacités** attachées à l'entité à chaque opération. Les profils regroupent des capacités cohérentes et évoluent avec les versions (un nouveau besoin de RBD est ajouté au profil, pas à chaque client). La restriction réseau est un second facteur bon marché : une clé volée ne sert pas depuis ailleurs. Les clés passent par le Vault et le rôle : une seule source, un historique, et aucune copie manuelle à retrouver le jour d'une rotation.

**Alternatives**
- *Espaces de noms RBD* (`rbd namespace create`, `profile rbd pool=rbd-test namespace=…`) : une clé par équipe dans un même pool ; c'est l'outil d'E31.
- *Une entité par usage et par hôte* (`client.rbd-cephcli01`) plutôt que par pool : plus fin encore, plus de clés à gérer ; utile quand plusieurs hôtes partagent un pool.

**Pièges classiques**
- `ceph auth caps` avec une seule capacité : les autres disparaissent (le client perd `mgr`, ou pire `mon`).
- `mon 'allow r'` au lieu de `mon 'profile rbd'` : tout marche… jusqu'au jour où un client doit reprendre le verrou d'une image (`rbd: … failed to blocklist`).
- Oublier la restriction réseau sur `mon` : la clé s'authentifie depuis n'importe où (puis échoue aux OSD), ce qui brouille le diagnostic.
- Copier un trousseau « pour tester » et l'oublier : chaque copie est un secret de plus à retrouver.
- Supprimer une clé « inutilisée » sans regarder les sessions.

**En production chez MédiSphère**
Revue trimestrielle des entités (comparaison `ceph auth ls` ↔ registre, script), alerte sur toute entité cliente non inscrite, rotation annuelle par nouvelle entité, aucune clé `client.admin` hors des nœuds `_admin` (contrôle du mini-projet), clés nominatives aux capacités limitées pour l'astreinte de niveau 1 (lecture : `mon 'allow r' mgr 'allow r'`).

---

### M08-E14 — CRUSH : règles par classe et domaines de panne

**Solution**

Fichiers : [`hierarchie-crush.sh`](fichiers/M08-E14/hierarchie-crush.sh) (étapes 3 à 5, idempotent, avec attente de `HEALTH_OK`), [`carte-ajouts.txt`](fichiers/M08-E14/carte-ajouts.txt) (ajouts à la carte décompilée), [`tester-regles.sh`](fichiers/M08-E14/tester-regles.sh) (tests hors ligne).

1. **Lecture.**
   ```
   [root@ceph01 ~]# mkdir -p /root/e14 && ceph osd getcrushmap -o /root/e14/crush.bin
   [root@ceph01 ~]# cephadm shell --mount /root/e14:/mnt -- crushtool -d /mnt/crush.bin -o /mnt/crush.txt
   ```
   (`crushtool` vient du conteneur ; les fichiers restent dans `/root/e14` du nœud, puis `scp` vers `~/m08/e14/` sur `adm01`. [`tester-regles.sh`](fichiers/M08-E14/tester-regles.sh) se lance de la même façon, monté avec le dossier.) Dans la carte, chaque OSD a sa classe (`device 0 osd.0 class ssd`) ; chaque *bucket* hôte a des identifiants « fantômes » par classe (`id -3 class ssd`). `ceph osd crush tree --show-shadow` montre ces arbres fantômes (`default~ssd`, `default~hdd`) : une règle `step take default class ssd` parcourt l'arbre fantôme, qui ne contient que les OSD de cette classe. `replicated_rule` : `take default` (toute la racine, toutes classes), `chooseleaf firstn 0 type host` (choisir autant d'hôtes distincts que de répliques, puis un OSD feuille dans chacun), `emit`.
2. **Hors ligne.** [`carte-ajouts.txt`](fichiers/M08-E14/carte-ajouts.txt) ajoute `datacenter par1`, les trois `rack`, rattache les hôtes et définit :
   ```
   rule ssd-baie {
   	id 1
   	type replicated
   	step take default class ssd
   	step chooseleaf firstn 0 type rack
   	step emit
   }
   ```
   (et `hdd-baie`, id 2). [`tester-regles.sh`](fichiers/M08-E14/tester-regles.sh) compile la carte et lance, pour chaque règle, `crushtool -i carte.bin --test --rule <id> --num-rep 3 --show-bad-mappings` (aucune ligne attendue) et `--show-utilization` (répartition à peu près égale entre les OSD de la classe), puis vérifie avec `--show-mappings` qu'aucun résultat ne contient deux OSD de la même baie. Une règle `class nvme` : `crushtool -c` refuse de compiler (code de sortie 1 : la classe n'existe pas dans la carte). Une règle qui compile mais ne peut pas être satisfaite (classe sans assez d'OSD, ou plus de répliques que de baies : `--num-rep 4`) donne au contraire des lignes `bad mapping rule … result [11,8,5]` (moins d'OSD que demandé) : c'est exactement ce que provoque la panne d'E36 en ligne.
3. **En ligne.**
   ```
   [root@ceph01 ~]# ceph osd crush add-bucket par1 datacenter
   [root@ceph01 ~]# ceph osd crush move par1 root=default
   [root@ceph01 ~]# for b in a b c; do ceph osd crush add-bucket par1-baie-$b rack; ceph osd crush move par1-baie-$b datacenter=par1; done
   [root@ceph01 ~]# ceph osd crush move ceph01 rack=par1-baie-a
   [root@ceph01 ~]# ceph -s          # attendre HEALTH_OK
   [root@ceph01 ~]# ceph osd crush move ceph02 rack=par1-baie-b
   …
   ```
   Le déplacement d'un hôte change les identifiants intermédiaires de la hiérarchie : CRUSH recalcule et **une partie** des PG change d'OSD (de quelques pour cent à 30 % d'objets *misplaced* selon le hasard des calculs), même si le domaine de panne effectif ne change pas. Les données restent disponibles pendant le mouvement (copies existantes servies, `backfill` en arrière-plan).
4. **Règles.**
   ```
   [root@ceph01 ~]# ceph osd crush rule create-replicated ssd-baie default rack ssd
   [root@ceph01 ~]# ceph osd crush rule create-replicated hdd-baie default rack hdd
   [root@ceph01 ~]# ceph osd crush rule dump ssd-baie
   ```
   Les étapes produites sont les mêmes que celles de la carte hors ligne (`take default class ssd` apparaît sous la forme `"item_name": "default~ssd"`).
5. **Pools.** Pour chaque pool répliqué : `ceph osd pool set <pool> crush_rule ssd-baie`, puis attendre `HEALTH_OK` (le script le fait). Ordre conseillé : `.mgr`, `cephfs.cephfs.meta`, index et métadonnées RGW, puis les gros pools (`rbd-test`, `cephfs.cephfs.data`, `default.rgw.buckets.data`). Le pourcentage *misplaced* du changement de règle est élevé (proche de la part des copies qui étaient sur les HDD : environ un tiers), parce que la règle exclut désormais trois OSD. Choix argumenté possible : `default.rgw.buckets.data` sur `hdd-baie` (gros objets, peu de latence demandée) ; le corrigé garde tout sur SSD tant que l'ADR-0080 n'a pas tranché. Règle par défaut :
   ```
   [root@ceph01 ~]# ceph osd crush rule dump ssd-baie -f json | jq .rule_id      # (jq sur adm01)
   1
   [root@ceph01 ~]# ceph config set global osd_pool_default_crush_rule 1
   ```
6. **Contrôle.** `ceph pg ls-by-pool rbd-test` : colonne `UP`/`ACTING` `[4,8,1]p4` ; `ceph osd find 4` (hôte) et `ceph osd crush get-device-class osd.4` (classe) pour trois PG.
7. **Réponses.** Les métadonnées CephFS et les index RGW sont des **omap** (paires clé-valeur dans RocksDB) consultées à chaque opération de fichier ou de liste d'objets : leur latence est celle de tout le service, alors qu'elles pèsent peu. Sur HDD, chaque `ls`, chaque `PUT` attend un disque à 100 IOPS. Si les **deux** SSD d'un hôte tombent, la règle `ssd-baie` ne peut plus placer la copie de cette baie (aucun autre SSD dans la baie, et les deux autres baies ont déjà une copie) : les PG restent `undersized+degraded` avec deux copies ; les écritures continuent tant que `min_size` (2) est atteint. Une seconde panne dans une autre baie les bloquerait.

**Explications**

CRUSH est un calcul pseudo-aléatoire déterministe : à partir de l'identifiant d'un PG et de la carte, chaque client et chaque OSD calcule les mêmes OSD, sans table centrale. La hiérarchie dit **ce que deux copies ne doivent pas partager** (un hôte, une baie, une salle), les classes disent **sur quels disques** chercher. Changer la carte change le résultat du calcul pour une partie des PG : c'est un mouvement de données, à planifier. On construit en ligne par des commandes atomiques (ajout de *bucket*, déplacement) plutôt qu'en injectant une carte éditée à la main : une faute de frappe dans une carte injectée peut déplacer **toutes** les données ou rendre des PG impossibles à placer.

**Alternatives**
- *Injection de la carte testée* (`ceph osd setcrushmap -i`) : un seul mouvement de données au lieu de plusieurs ; acceptable si la carte injectée a été testée avec `crushtool --test --compare` contre l'ancienne, et sur un cluster en maintenance.
- *Domaine de panne `host` et baies seulement « documentaires »* : plus simple, mais ne protège pas d'une panne d'alimentation de baie.
- *`location` dans `hosts.yaml`* : seulement pour les hôtes **ajoutés** ensuite (E18) ; il ne déplace pas un hôte existant.

**Pièges classiques**
- Créer les baies sans les rattacher à la racine (`move … root=default`) : la règle `take default` ne les voit pas, les OSD déplacés dessous « disparaissent » des règles, PG inactifs.
- `osd_pool_default_crush_rule ssd-baie` (le nom) : refusé ou ignoré selon la version ; il faut l'identifiant.
- Changer la règle de tous les pools d'un coup : récupération concurrente sur tous les pools, latence en hausse pour les clients.
- Oublier `.mgr` et les pools RGW (créés tard, par d'autres) : `ceph osd pool ls detail | grep -v 'crush_rule 1'` les montre.
- Tester une règle sur le cluster plutôt qu'hors ligne : une règle impossible rend les PG du pool inactifs jusqu'à correction.

**En production chez MédiSphère**
Hiérarchie qui reflète la salle (salle, rangée, baie), alimentée depuis NetBox (DCIM : baies et positions), tests hors ligne de toute modification de carte dans la CI de `plateforme/ceph` (E23), changements de règle pool par pool dans une fenêtre, avec `osd_mclock_profile` choisi selon la priorité (clients ou récupération, E29).

---

### M08-E15 — Codes d'effacement

**Solution**

Fichiers : [`ec.sh`](fichiers/M08-E15/ec.sh), [`regle-ec-test.txt`](fichiers/M08-E15/regle-ec-test.txt) (règle *indep* de test hors ligne).

1. **Lecture.** k=2, m=1 : 3 *chunks* par objet sur 3 OSD distincts (ici, de trois baies) ; surcoût brut (k+m)/k = **1,5** (contre 3 en réplication ×3) ; **une** perte tolérée sans perte de données. Avec m=1, Ceph pose `min_size` = k = 2 (la formule est k + min(1, m−1)) : le pool continue d'écrire avec un *chunk* manquant, c'est-à-dire **sans aucune redondance** ; une seconde panne pendant cette fenêtre perd les écritures faites entre-temps. La documentation recommande k+1 pour qu'une écriture ne soit jamais acquittée sans au moins une redondance ; avec k=2, m=1 et `min_size` = 3, la perte d'un seul OSD bloque les écritures. C'est tout le dilemme de m=1. ⚠️ À vérifier sur ton lab : `ceph osd pool get rbd-ec-donnees min_size`.
2. **Profil.**
   ```
   [root@ceph01 ~]# ceph osd erasure-code-profile set ec-21-hdd k=2 m=1 crush-device-class=hdd crush-failure-domain=rack
   [root@ceph01 ~]# ceph osd erasure-code-profile get ec-21-hdd
   crush-device-class=hdd
   crush-failure-domain=rack
   crush-root=default
   k=2
   m=1
   plugin=isa
   technique=reed_sol_van
   …
   ```
   k=4, m=2 avec domaine `rack` exige 6 baies (ou 6 hôtes) : il n'y en a que 3. Test hors ligne : la règle [`regle-ec-test.txt`](fichiers/M08-E15/regle-ec-test.txt) (`type erasure`, `chooseleaf indep 0 type rack`) ajoutée à la carte d'E14, `crushtool --test --rule 3 --num-rep 6 --show-bad-mappings` : chaque entrée donne un résultat incomplet (`[a,b,c,2147483647,2147483647,2147483647]`, la valeur `0x7fffffff` = « aucun OSD trouvé ») ; en ligne, le pool serait **inactif**.
3. **Pool.**
   ```
   [root@ceph01 ~]# ceph osd pool create rbd-ec-donnees erasure ec-21-hdd
   [root@ceph01 ~]# ceph osd pool set rbd-ec-donnees allow_ec_overwrites true
   [root@ceph01 ~]# ceph osd pool application enable rbd-ec-donnees rbd
   ```
   `allow_ec_optimizations` : le corrigé l'**active**, argument : pool neuf, usage RBD (petites écritures), cluster tout en Tentacle, et l'irréversibilité ne coûte rien sur un pool sans historique. ⚠️ Un pool optimisé ne peut plus être lu par des OSD d'une version antérieure : on ne l'active qu'une fois tous les OSD en Tentacle et sans retour arrière de version prévu. Le refus argumenté est aussi accepté.
4. **Image.**
   ```
   [root@ceph01 ~]# rbd create rbd-test/archives-ec --size 10G --data-pool rbd-ec-donnees
   [root@ceph01 ~]# rbd info rbd-test/archives-ec | grep data_pool
   	data_pool: rbd-ec-donnees
   admin@cephcli01:~$ sudo rbd --id rbd-test device map rbd-test/archives-ec
   ```
   ⚠️ La clé `client.rbd-test` n'a de droits que sur `rbd-test` : il faut ajouter `profile rbd pool=rbd-ec-donnees` à ses capacités `osd` (`ceph auth caps`, en répétant **toutes** les capacités, restriction réseau d'E13 comprise ; [`ec.sh`](fichiers/M08-E15/ec.sh) le fait), sinon l'écriture des données échoue avec `Operation not permitted`. Après `mkfs.xfs` et 2 Gio écrits : `ceph df detail` montre `STORED` ≈ 2 Gio et `USED` ≈ 3 Gio pour `rbd-ec-donnees`, quand le même volume en réplication ×3 aurait consommé ≈ 6 Gio.
5. **Perte d'un OSD.** `ceph orch daemon stop osd.<ID-HDD-CEPH03>` : lecture possible (reconstruction à partir des deux *chunks* restants : lecture dégradée, plus de calcul) ; écriture possible si `min_size` = 2, bloquée si `min_size` = 3 ; PG `active+undersized+degraded` (ou `undersized+degraded+peered`, inactifs, avec `min_size` = 3). Il n'y a **aucun** autre OSD `hdd` dans la baie C : le cluster ne peut pas reconstruire, il attend le retour de l'OSD. `ceph orch daemon start osd.<ID>` puis `HEALTH_OK`.
6. **Tableau pour Claire** (neuf disques de 64 Gio : six SSD, trois HDD, avant `ceph04`) :

   | Option | Capacité utile (brute ÷ surcoût, avant marge) | Pannes tolérées | Pendant une panne | Petites écritures | Recommandation |
   |---|---|---|---|---|---|
   | Réplication ×3 SSD | 384 / 3 ≈ 128 Gio | 2 copies perdues | lecture/écriture normales | rapides | images, bases, métadonnées |
   | Réplication ×3 HDD | 192 / 3 = 64 Gio | 2 | normales | lentes | peu d'intérêt |
   | EC 2+1 HDD | 192 / 1,5 = 128 Gio | 1 | lecture dégradée ; écriture sans redondance (`min_size` 2) ou bloquée (3) | les plus lentes (*read-modify-write*, atténué par FastEC) | **archives froides**, à condition d'accepter l'exposition pendant une panne ; mieux : EC 4+2 dès six baies |

**Explications**

Un code d'effacement découpe un objet en k morceaux de données et calcule m morceaux de parité ; n'importe quels k morceaux parmi k+m suffisent à reconstruire. Il économise de la place au prix du calcul, de la latence (une écriture touche k+m OSD, une écriture partielle doit relire la bande) et d'une exigence forte sur le **nombre de domaines de panne** (k+m au minimum, k+m+1 pour pouvoir reconstruire ailleurs). Sur trois baies, l'EC n'a guère de sens au-delà de la démonstration ; il devient intéressant avec 6 à 10 domaines (4+2, 8+3). RBD et CephFS gardent leurs métadonnées (omap) dans un pool répliqué : l'EC ne porte que les données.

**Alternatives**
- *Réplication ×2 sur HDD* : surcoût de 2 (contre 1,5), une seule panne tolérée, et la tentation de `min_size` 1 pour continuer d'écrire pendant une panne, c'est-à-dire le pire des choix (E21).
- *Archives dans RGW en EC* (pool de données RGW en EC, index en répliqué) : l'usage le plus naturel de l'EC (gros objets écrits une fois) ; la stratégie d'ADR-0080.
- *Archives hors cluster* (`pbs01`, `s3-01`) : séparation des risques ; c'est E25.

**Pièges classiques**
- Oublier `allow_ec_overwrites` : RBD refuse d'utiliser le pool comme `--data-pool`.
- Créer l'image **dans** le pool EC (`rbd create rbd-ec-donnees/…`) : refusé (omap).
- Croire qu'on peut changer k ou m plus tard : le profil est figé, il faut un nouveau pool et une migration (`rbd migration`).
- Oublier les capacités du client sur le pool de données.
- Arrêter deux OSD `hdd` « pour voir ».

**En production chez MédiSphère**
EC réservé à RGW et aux archives quand le cluster comptera au moins six hôtes répartis sur six baies, `min_size` = k+1, supervision des PG `undersized` avec une alerte plus urgente que pour un pool répliqué (la redondance est déjà consommée), FastEC activé après la montée de version de tous les OSD.

---

### M08-E16 — Exports NFS

**Solution**

Fichiers : [`specs/nfs.yaml`](fichiers/M08-E16/ceph/specs/nfs.yaml), [`nfs.sh`](fichiers/M08-E16/nfs.sh), [`export-legacy-rdv.json`](fichiers/M08-E16/export-legacy-rdv.json) (export tel que renvoyé par `export info`, modifiable par `export apply`).

1. **Lecture.** La configuration de Ganesha (blocs `EXPORT`) est stockée dans **RADOS**, pool `.nfs`, espace de noms du cluster NFS (`par1`) ; chaque démon Ganesha la lit au démarrage et est notifié des changements. `--ingress` déploie aussi un service `ingress` devant les démons (haproxy en TCP ou VIP seule avec `keepalive-only`) : HA du point d'entrée NFS. Pas ici : un seul démon (mémoire), et un NFS « haute disponibilité » exige plusieurs démons, une VIP et un délai de grâce maîtrisé, à concevoir pour la production.
2. **Cluster.**
   ```
   admin@adm01:~/src/ceph$ ssh ceph01 sudo ceph orch apply -i - < specs/hosts.yaml    # étiquette nfs (MR fusionnée)
   [root@ceph01 ~]# ceph fs subvolume create cephfs legacy-rdv --group_name applications --size 5368709120
   [root@ceph01 ~]# ceph nfs cluster create par1 "label:nfs count:1"
   [root@ceph01 ~]# ceph nfs cluster info par1
   { "par1": { "backend": [ { "hostname": "ceph01", "ip": "10.10.30.51", "port": 2049 } ], "virtual_ip": null } }
   ```
3. **Export.**
   ```
   [root@ceph01 ~]# P=$(ceph fs subvolume getpath cephfs legacy-rdv --group_name applications)
   [root@ceph01 ~]# ceph nfs export create cephfs --cluster-id par1 --pseudo-path /legacy-rdv --fsname cephfs \
       --path "$P" --client_addr 10.10.30.20 --squash root_squash
   [root@ceph01 ~]# ceph nfs export info par1 /legacy-rdv
   ```
   Champs : `access_type: "none"` (personne par défaut), `clients: [{addresses: ["10.10.30.20"], access_type: "rw", squash: "root_squash"}]`, `protocols: [4]`, `transports: ["TCP"]`, `security_label`, `sectype` (`sys` : identité Unix déclarée par le client, aucune authentification forte), `fsal: {name: "CEPH", fs_name: "cephfs", user_id: "nfs.par1.cephfs…"}` : le gestionnaire a créé une **clé cephx propre à l'export** (`client.nfs.par1…`), limitée au chemin exporté ; c'est elle que Ganesha utilise pour parler à CephFS.
4. **Montage.**
   ```
   admin@cephcli01:~$ sudo apt-get install -y nfs-common && sudo mkdir -p /mnt/legacy-rdv
   admin@cephcli01:~$ sudo mount -t nfs -o vers=4.2 10.10.30.51:/legacy-rdv /mnt/legacy-rdv
   admin@cephcli01:~$ sudo touch /mnt/legacy-rdv/essai-root && ls -ln /mnt/legacy-rdv/essai-root
   -rw-r--r-- 1 65534 65534 0 … essai-root
   ```
   `root_squash` : root du client devient `nobody` (65534). Pour le dossier de l'application, on passe par une opération faite **côté CephFS** (montage noyau d'administration, ou depuis un client sans *squash*) : `mkdir pieces-jointes && chown 1000:1000 pieces-jointes` (uid de `admin` sur `cephcli01`) ; puis `admin` y écrit par NFS. Autre voie : désactiver temporairement le *squash* le temps de créer l'arborescence (étape 6 montre comment modifier l'export).
5. **Refus.** Depuis `ceph02` : `mount.nfs: access denied by server while mounting 10.10.30.51:/legacy-rdv`. En NFSv3 depuis `cephcli01` (`-o vers=3`) : `mount.nfs: requested NFS version or transport protocol is not supported` (NFSv3 non activé sur le cluster : `--enable-nfsv3` à la création, Squid et suivants).
6. **Modification par fichier.**
   ```
   [root@ceph01 ~]# ceph nfs export info par1 /legacy-rdv > /root/export.json
   (dans le fichier : "access_type": "ro" dans le bloc clients)
   [root@ceph01 ~]# ceph nfs export apply par1 -i /root/export.json
   ```
   Le démon est notifié, le client voit `Read-only file system` à la prochaine écriture (sans remontage). Retour en `rw` de la même façon. Le JSON est versionnable : c'est la forme qu'on gardera dans `plateforme/ceph` (E23).
7. **Production.** Deux démons au moins et une VIP (`ingress`, mode `haproxy-protocol` pour que Ganesha voie l'adresse réelle des clients, nécessaire aux ACL par adresse, ou `keepalive-only`), délai de grâce de Ganesha (90 s par défaut : pendant une bascule, les clients NFSv4 récupèrent leurs verrous), sauvegarde du sous-volume (instantanés + export hors cluster), surveillance du port 2049 et des sessions, `sectype krb5` si les clients s'y prêtent.

**Explications**

NFS-Ganesha est un serveur NFS en espace utilisateur dont le « FSAL CEPH » parle directement à CephFS avec `libcephfs` : pas de montage intermédiaire. L'orchestrateur le déploie et le gestionnaire gère ses exports, rangés dans RADOS pour que tous les démons partagent la même configuration. L'ACL par adresse et le `root_squash` ne sont **pas** une authentification (une machine qui usurpe 10.10.30.20 sur le VLAN 30 passe) : c'est un cloisonnement de réseau, cohérent avec un VLAN de stockage fermé.

**Alternatives**
- *Montage CephFS natif* par l'application : plus performant, cloisonnement cephx ; impossible ici (application non modifiable).
- *Serveur NFS du noyau* (`nfs-kernel-server`) sur `cephcli01` réexportant un montage CephFS : fonctionne, mais un point unique de plus, hors de la gestion de Ceph.
- *Export RGW* (pour aller plus loin) : du NFS au-dessus d'objets, avec des sémantiques limitées.

**Pièges classiques**
- `--path` omis : l'export publie **la racine** du volume, tous les sous-volumes compris.
- Pas de `--client_addr` : export ouvert à tout le VLAN (et au-delà si un flux le permet).
- Créer les dossiers de l'application en root à travers NFS avec `root_squash` : `Permission denied`, ou des fichiers à `nobody`.
- Supposer NFSv3 (les vieux clients le demandent) : il faut l'activer explicitement et ouvrir les ports annexes (`rpcbind`, `mountd`).

**En production chez MédiSphère**
Point d'entrée NFS en HA (deux démons, VIP déclarée dans NetBox), exports décrits dans `plateforme/ceph` et appliqués par la procédure d'E23, alerte sur la perte d'un démon Ganesha, et une date de fin : l'export disparaît avec la migration de Legacy-RDV.

---
### M08-E17 — Exporter un bloc en iSCSI

**Solution**

Fichiers : [`cible-iscsi.sh`](fichiers/M08-E17/cible-iscsi.sh) (configuration LIO sur `cephcli01`, secret CHAP lu dans un fichier ; versionné dans `outils/` de `plateforme/ansible`), [`ceph_client.yml`](fichiers/M08-E17/ansible/inventories/lab/group_vars/role_ceph_client/ceph_client.yml) et [`vault-lab.yml.exemple`](fichiers/M08-E17/ansible/inventories/lab/group_vars/role_ceph_client/vault-lab.yml.exemple) (clé et image par le rôle), [`m08-initiateur.tf.extrait`](fichiers/M08-E17/infra/envs/ceph/m08-initiateur.tf.extrait), [`initiateur.sh`](fichiers/M08-E17/initiateur.sh).

1. **Contexte.** `ceph-iscsi` (passerelle `tcmu-runner` + `rbd-target-api`) est déclarée non maintenue : elle dépendait de composants du noyau et d'espace utilisateur peu suivis, et l'industrie passe à **NVMe over Fabrics** (NVMe/TCP), que Ceph fournit par sa passerelle `nvmeof` (service cephadm `nvmeof`, groupes de passerelles, multichemin ANA cohérent). La solution du ticket a un **point unique de défaillance** : si `cephcli01` redémarre, l'initiateur perd le LUN le temps du redémarrage (et retente pendant `replacement_timeout`) ; s'il tombe, plus de LUN jusqu'à sa réparation. Pas de multichemin possible : deux cibles LIO sur deux hôtes qui exportent la même image n'ont pas de coordination des réservations SCSI ni des caches.
2. **Image et `rbdmap`.**
   ```
   [root@ceph01 ~]# rbd create rbd-test/iscsi-scan --size 20G
   [root@ceph01 ~]# ceph auth get-or-create client.iscsi-cephcli01 mon 'profile rbd network 10.10.30.20/32' \
       osd 'profile rbd pool=rbd-test network 10.10.30.20/32' mgr 'profile rbd pool=rbd-test'
   ```
   `outils/ajouter-cle-ceph.sh client.iscsi-cephcli01`, puis dans `ceph_client.yml` : la clé dans `ceph_client_cles`, l'image dans `ceph_client_rbdmap` (`{image: rbd-test/iscsi-scan, id: iscsi-cephcli01}`) ; MR, playbook. Le rôle écrit `/etc/ceph/rbdmap` (`rbd-test/iscsi-scan id=iscsi-cephcli01,keyring=/etc/ceph/ceph.client.iscsi-cephcli01.keyring`) et active `rbdmap.service`. Redémarrage, `ls -l /dev/rbd/rbd-test/iscsi-scan`. L'ordre au démarrage compte : `rbdmap.service` doit passer **avant** la restauration de LIO ; le script ajoute une surcharge systemd (`After=rbdmap.service`, `Requires=rbdmap.service`) au service de restauration.
3. **Cible.** [`cible-iscsi.sh`](fichiers/M08-E17/cible-iscsi.sh) enchaîne (en root sur `cephcli01`) :
   ```
   targetcli /backstores/block create name=iscsi-scan dev=/dev/rbd/rbd-test/iscsi-scan
   targetcli /iscsi create iqn.2026-10.internal.medisphere.par1:cephcli01.legacy
   targetcli /iscsi/<IQN>/tpg1/luns create /backstores/block/iscsi-scan
   targetcli /iscsi/<IQN>/tpg1/portals delete 0.0.0.0 3260
   targetcli /iscsi/<IQN>/tpg1/portals create 10.10.30.20 3260
   targetcli /iscsi/<IQN>/tpg1/acls create iqn.2026-10.internal.medisphere.par1:m08-initiateur
   targetcli /iscsi/<IQN>/tpg1/acls/<IQN-INIT> set auth userid=scan-legacy password=<lu dans un fichier 600>
   targetcli /iscsi/<IQN>/tpg1 set attribute authentication=1 generate_node_acls=0
   targetcli saveconfig
   ```
   Le secret CHAP est lu par le script dans `/root/chap-scan-legacy` (600, déposé depuis le Vault puis effacé) et passé à `targetcli` par son **entrée standard** (`targetcli` lit des commandes sur stdin) : il n'apparaît ni dans `ps` ni dans un historique. Il apparaît en revanche **en clair** dans `/etc/rtslib-fb-target/saveconfig.json` (600, root) : c'est la limite de LIO, à inscrire au registre des secrets. Le chargement au démarrage est assuré par le service de restauration de `python3-rtslib-fb` (⚠️ à vérifier sur ton lab : `rtslib-fb-targetctl.service` sous Debian 13 ; `systemctl list-unit-files | grep -i rtslib`).
4. **Initiateur.** VM 2086 par l'état `ceph` ([extrait](fichiers/M08-E17/infra/envs/ceph/m08-initiateur.tf.extrait) : module `vm-noeud`, famille `debian13`, comme `cephcli01` ; étiquette `env-m08`, VNet `vstopub`, 10.10.30.21, MTU 9000, adresse **réservée** puis libérée dans NetBox). [`initiateur.sh`](fichiers/M08-E17/initiateur.sh) :
   ```
   root@m08-initiateur:~# apt-get install -y open-iscsi xfsprogs
   root@m08-initiateur:~# echo 'InitiatorName=iqn.2026-10.internal.medisphere.par1:m08-initiateur' > /etc/iscsi/initiatorname.iscsi
   root@m08-initiateur:~# systemctl restart iscsid
   root@m08-initiateur:~# iscsiadm -m discovery -t sendtargets -p 10.10.30.20
   10.10.30.20:3260,1 iqn.2026-10.internal.medisphere.par1:cephcli01.legacy
   root@m08-initiateur:~# iscsiadm -m node -T <IQN> -p 10.10.30.20 --op update -n node.session.auth.authmethod -v CHAP
   root@m08-initiateur:~# iscsiadm -m node -T <IQN> -p 10.10.30.20 --op update -n node.session.auth.username -v scan-legacy
   root@m08-initiateur:~# iscsiadm -m node -T <IQN> -p 10.10.30.20 --op update -n node.session.auth.password -v "$(cat /root/chap)"
   root@m08-initiateur:~# iscsiadm -m node -T <IQN> -p 10.10.30.20 --login
   root@m08-initiateur:~# lsblk -o NAME,SIZE,TRAN,VENDOR,MODEL      # sdb 20G iscsi LIO-ORG iscsi-scan
   root@m08-initiateur:~# mkfs.xfs /dev/sdb && mount /dev/sdb /mnt && echo test > /mnt/preuve
   ```
   (Le `$(cat …)` place le secret dans la ligne de commande d'`iscsiadm` le temps de l'appel, visible dans `ps` : acceptable sur une VM jetable sans autre utilisateur ; sinon, éditer `/etc/iscsi/nodes/…/default`.)
5. **Mauvais secret** : `iscsiadm: Login failed … authorization failure` (code 24) ; sur la cible, `journalctl -k` : `iSCSI Login negotiation failed` / `CHAP … mismatch` (libellé noyau à lire sur ton lab).
6. **Redémarrage de la cible.** Le `dd` se fige ; l'initiateur journalise `connection … error`, tente de se reconnecter ; la session revient seule si `cephcli01` est revenu avant `node.session.timeo.replacement_timeout` (120 s par défaut) ; au-delà, les E/S en attente échouent vers la couche supérieure (erreurs XFS, système de fichiers à remonter). Ici, un redémarrage de Debian prend 30 à 60 s : reprise sans erreur, après relecture du LUN.
7. **Ménage.** `umount /mnt`, `iscsiadm -m node -T <IQN> -p 10.10.30.20 --logout`, retrait de la VM de l'état `ceph` (MR, pipeline) et de son adresse dans NetBox. La cible reste configurée (le corrigé la garde : elle est le service du ticket) ; sinon `targetcli clearconfig confirm=True`, retrait de l'image de `ceph_client_rbdmap` (playbook) et `rbd rm` de l'image **après** avoir vérifié qu'elle n'est plus mappée.

**Explications**

LIO est la cible SCSI du noyau Linux : un *backstore* (ici un périphérique bloc, l'image RBD mappée par krbd) est présenté comme LUN d'une cible iSCSI, derrière un portail (adresse, port) et des ACL (IQN d'initiateurs, CHAP). Ceph n'intervient qu'en dessous : le serveur LIO est un client RBD ordinaire. Toute la fiabilité d'iSCSI repose donc sur ce client unique, ce qui est l'opposé de l'architecture de Ceph (aucun point unique) : d'où l'abandon de ce modèle au profit d'une passerelle intégrée et multichemin.

**Alternatives**
- *Passerelle NVMe-oF de Ceph* (`ceph orch apply nvmeof …`, `ceph nvme-gw`, CLI `nvmeof`) : la voie supportée, multichemin, mais exige un initiateur NVMe/TCP (pas le cas de l'appareil d'InfoGér) ; mémoire importante (SPDK).
- *`tgt`* (cible en espace utilisateur, avec un *backstore* `rbd` direct via `librbd`) : évite krbd, mais projet peu actif.
- *Disque RBD attaché à une VM* qui partage en SMB/NFS : si l'appareil parlait autre chose qu'iSCSI.

**Pièges classiques**
- Donner `/dev/rbd0` au *backstore* : après un redémarrage, l'ordre des mappages change et LIO exporte la mauvaise image.
- Laisser le portail par défaut sur `0.0.0.0:3260` : la cible écoute aussi sur d'autres interfaces.
- `generate_node_acls=1` (mode démo) : n'importe quel initiateur se connecte.
- Restauration de LIO avant `rbdmap` au démarrage : le *backstore* pointe vers un périphérique absent, la cible démarre sans LUN.
- Deux initiateurs sur le même LUN avec XFS : corruption.

**En production chez MédiSphère**
Ce ticket a une date de fin (départ de l'appareil) inscrite dans la fiche ; sauvegarde de l'image (instantanés RBD et `export-diff`, E25) ; supervision du port 3260 et de la session ; pour tout nouveau besoin de bloc hors Ceph, NVMe-oF.

---

### M08-E18 — Étendre le cluster : un quatrième nœud

**Solution**

Fichiers : [`ceph04.tf.extrait`](fichiers/M08-E18/infra/envs/ceph/ceph04.tf.extrait), [`specs/hosts.yaml`](fichiers/M08-E18/ceph/specs/hosts.yaml), [`CHG-928-ceph04.md`](fichiers/M08-E18/medisphere/docs/stockage/changements/CHG-928-ceph04.md).

1. **Fiche** ([modèle rempli](fichiers/M08-E18/medisphere/docs/stockage/changements/CHG-928-ceph04.md)). Estimation : `ceph04` apporte 2 SSD sur 8 (25 % de la capacité SSD) et 1 HDD sur 4. Avec le domaine `rack`, la baie A double sa capacité SSD mais **reçoit toujours exactement une copie** de chaque PG : CRUSH répartit la copie de la baie A entre `ceph01` et `ceph04`, donc environ la **moitié** des copies de la baie A migrent vers `ceph04`, soit à peu près un sixième des données totales du cluster (1/3 des copies sont en baie A, la moitié bouge). Les baies B et C ne bougent presque pas. Durée : volume à déplacer ÷ débit de *backfill* observé (quelques dizaines de Mo/s au lab avec le profil mClock par défaut).
2. **VM.** Une entrée `ceph04 = 4` dans `noeuds_ceph` ([extrait](fichiers/M08-E18/infra/envs/ceph/ceph04.tf.extrait)) : le `for_each` d'E02 produit la VM (deux cartes `vstopub`/`vstoclu` en MTU 9000, trois disques OSD de séries `ceph04-ssd1`, `ceph04-ssd2`, `ceph04-hdd1`) et son nom DNS ; plan relu en MR (rien à modifier sur `ceph01-03`), `apply` protégé. NetBox : VM `ceph04`, interfaces `ens18`/`ens19`, adresses 10.10.30.54/24 (`dns_name` `ceph04.par1.medisphere.internal`) et 10.10.31.54/24 (sans nom). Rôle `ceph_noeud` (Podman, chrony, `lvm2`, `cephadm` et `ceph-common` 20.2.3, compte de l'orchestrateur, MTU) ; `ceph04` ajouté à `ceph_noeuds` de `group_vars/env_m08/ceph.yml`. Contrôles :
   ```
   admin@ceph04:~$ ping -c 3 -M do -s 8972 10.10.30.51 && ping -c 3 -M do -s 8972 10.10.31.51
   admin@ceph04:~$ lsblk -o NAME,SIZE,ROTA,TYPE,MOUNTPOINT      # sdb/sdc ROTA 0, sdd ROTA 1, vides
   ```
3. **Clé de l'orchestrateur.** `ceph cephadm get-pub-key` donne la clé publique ; depuis E03, le rôle `ceph_noeud` la pose pour le compte `cephadm` (`ceph_noeud_cle_orchestrateur`, valeur publique versionnée) : rien à faire de plus que de jouer le rôle sur `ceph04`. Contrôle : `sudo cephadm check-host` sur `ceph04`, puis `ceph cephadm check-host ceph04 10.10.30.54` depuis `ceph01`. (La documentation montre `ssh-copy-id -f -i /etc/ceph/ceph.pub root@<hôte>` : c'est le cas d'un amorçage avec l'utilisateur `root`, pas le nôtre.)
4. **Prévision.** La spécification OSD d'E04 (placement par étiquette `osd`) couvre `ceph04` dès qu'il porte l'étiquette. Choix du corrigé : entrée **progressive** (`ceph config set osd osd_crush_initial_weight 0` avant l'ajout) puis montée du poids en deux paliers, et profil mClock `balanced` pendant l'opération (le défaut, `high_client_ops`, ralentit volontairement la récupération ; `high_recovery_ops` la favorise au détriment des clients). Sur un cluster de lab presque vide, l'entrée directe est tout aussi défendable : l'important est d'avoir **choisi**.
5. **Ajout.** Document ajouté à [`hosts.yaml`](fichiers/M08-E18/ceph/specs/hosts.yaml) :
   ```yaml
   service_type: host
   hostname: ceph04
   addr: 10.10.30.54
   labels:
     - osd
   location:
     rack: par1-baie-a
   ```
   `ssh ceph01 sudo ceph orch apply -i - --dry-run < hosts.yaml`, puis sans `--dry-run`. Si le nom de `ceph04` dans le cluster ne correspond pas à son nom d'hôte (`hostname` court), cephadm refuse : c'est voulu.
6. **Suivi.**
   ```
   [root@ceph01 ~]# ceph orch host ls
   [root@ceph01 ~]# ceph orch ps ceph04          # crash, ceph-exporter, osd.9, osd.10, osd.11
   [root@ceph01 ~]# ceph osd tree                # ceph04 sous par1-baie-a, OSD de poids 0
   [root@ceph01 ~]# ceph osd crush reweight osd.9 0.03125    # puis 0.0625 ; idem 10 et 11
   [root@ceph01 ~]# ceph -s                      # "x/y objects misplaced", "recovery: N MiB/s"
   ```
   Durée mesurée à noter dans la fiche, avec l'écart à l'estimation (au lab, l'écart vient surtout du profil mClock et de la latence des disques virtuels).
7. **Clôture.** `ceph config rm osd osd_crush_initial_weight`, `ceph config rm osd osd_mclock_profile` (retour au défaut), poids égaux aux tailles (`ceph osd df tree`, colonne `WEIGHT` ≈ 0,0625), `HEALTH_OK`, fiche fermée par MR.

**Explications**

Un ajout d'hôte cephadm, c'est : un hôte joignable en SSH par `root` avec la clé du cluster, Python 3, Podman, LVM, une heure synchronisée ; `ceph orch host add` (ou la spécification) ; puis les services dont le placement inclut l'hôte s'y déploient (crash, exporter, OSD par la spécification). L'emplacement CRUSH initial évite de passer par `root default` puis de déplacer l'hôte : un seul mouvement de données. Le poids CRUSH est la part de données qu'un OSD reçoit ; l'entrer à zéro puis le monter étale le mouvement dans le temps.

**Alternatives**
- *Ajout par `ceph orch host add ceph04 10.10.30.54 --labels osd`* puis `ceph osd crush move` : deux mouvements de données si l'hôte arrive sous la racine.
- *Drapeaux `norebalance`/`nobackfill`* pendant l'ajout, levés à l'heure choisie : contrôle de **quand** le mouvement a lieu, pas de son ampleur.
- *Module `balancer`* : après l'ajout, il affine la répartition (mode `upmap`), sans remplacer le poids.

**Pièges classiques**
- Oublier le MTU 9000 sur une des cartes de `ceph04` : les petits paquets passent, les gros se perdent, les OSD de `ceph04` « battent » (marqués `down` puis `up`) : c'est la panne d'E42.
- Disques non vides (reste de LVM d'une image) : `ceph orch device ls` les montre `Available: No` ; il faut les vider (`ceph orch device zap`, en vérifiant deux fois l'hôte).
- Laisser `osd_crush_initial_weight 0` en place : le prochain OSD (remplacement d'E19) entrera vide et le restera.
- Placement de la spécification OSD par liste d'hôtes (`hosts: [ceph01, ceph02, ceph03]`) : `ceph04` reste sans OSD.

**En production chez MédiSphère**
RB-081 (ajouter un nœud) dérivé de cette fiche ; ajout dans une fenêtre de faible charge, suivi de la latence client (E24), équilibrage final par le module `balancer`, inventaire NetBox (DCIM : baie, position, numéros de série des disques).

---

### M08-E19 — Retirer et remplacer un OSD

**Solution**

Fichier : [`correspondance-osd-disque.sh`](fichiers/M08-E19/correspondance-osd-disque.sh) (de l'OSD au disque virtuel Proxmox, en lecture seule).

1. **Correspondance.**
   ```
   [root@ceph01 ~]# ceph osd metadata 9 | grep -E '"devices"|device_ids|hostname'
       "device_ids": "sdb=QEMU_QEMU_HARDDISK_ceph04-ssd1",
       "devices": "sdb",
       "hostname": "ceph04",
   [root@ceph01 ~]# ceph device ls-by-host ceph04
   root@pve01:~# qm config 2084 | grep -E '^scsi'
   scsi1: ssd-lab:vm-2084-disk-1,discard=on,iothread=1,serial=ceph04-ssd1,size=64G,ssd=1
   ```
   Le module `vm-noeud` donne à chaque disque d'OSD un numéro de série explicite (`ceph04-ssd1`…, E02), visible dans l'invité **et** dans la configuration de la VM : la correspondance OSD → `sdb` → `ceph04-ssd1` → `scsi1` → volume `vm-2084-disk-1` est sûre. (Les valeurs exactes de `device_ids`, l'ordre des options de `qm config` : ⚠️ à lire sur ton lab.) Le script la reconstruit pour tous les OSD d'un hôte.
2. **Questions au cluster.**
   ```
   [root@ceph01 ~]# ceph osd ok-to-stop 9
   {"ok_to_stop":true,"osds":[9],"num_ok_pgs":…,"num_not_ok_pgs":0}
   [root@ceph01 ~]# ceph osd safe-to-destroy 9
   Error EBUSY: OSD(s) 9 have N pgs currently mapped to them.
   ```
   `ok-to-stop` : arrêter l'OSD maintenant ne rend **aucun** PG inactif (chaque PG garde au moins `min_size` copies). `safe-to-destroy` : détruire l'OSD maintenant ne fait perdre **aucune** donnée, ce qui n'est vrai qu'une fois l'OSD vidé (aucun PG ne s'y trouve plus, toutes les copies sont ailleurs). Le premier sert aux maintenances, le second aux retraits.
3. **Retrait.**
   ```
   [root@ceph01 ~]# ceph orch osd rm 9 --replace --zap
   Scheduled OSD(s) for replacement
   [root@ceph01 ~]# ceph orch osd rm status
   OSD  HOST    STATE     PGS  REPLACE  FORCE  ZAP   DRAIN STARTED AT
   9    ceph04  draining  37   True     False  True  …
   [root@ceph01 ~]# ceph osd tree | grep osd.9
    9    ssd  0.06250          osd.9   destroyed         0  1.00000
   ```
   L'OSD est marqué `out`, ses PG migrent vers l'autre SSD de la baie A (`osd.0` ou `osd.1` de `ceph01`, ou l'autre SSD de `ceph04`), puis il est détruit (état `destroyed`, identifiant et place CRUSH conservés) et son disque effacé.
   ⚠️ Avec `--zap` et une spécification gérée, le disque effacé **redevient disponible** et cephadm peut recréer un OSD dessus aussitôt, avant le remplacement « physique ». Au lab, c'est sans conséquence (le disque est sain) ; en production, on met la spécification en `unmanaged: true` le temps du remplacement, ou on retire sans `--zap` quand le disque est réellement mort (il n'y a rien à effacer). Si l'OSD est déjà revenu, le remplacement du disque (étape 4) refait le geste proprement : retrait `--replace` de nouveau, sans `--zap`, puis disque neuf.
4. **Disque.** Sur `pve01` (⚠️ VM 2084 seulement, disque `scsi1` seulement, vérifié deux fois) :
   ```
   root@pve01:~# qm set 2084 --delete scsi1                 # le disque passe en « unused0 »
   root@pve01:~# qm disk unlink 2084 --idlist unused0 --force   # suppression du volume
   root@pve01:~# qm set 2084 --scsi1 ssd-lab:64,ssd=1,discard=on,iothread=1,serial=ceph04-ssd1
   admin@ceph04:~$ lsblk                                    # sdb 64G, vide
   [root@ceph01 ~]# ceph orch device ls ceph04 --refresh
   ```
   (Mêmes options qu'à la création : `ssd=1` donne `rotational=0`, donc la classe `ssd` ; même numéro de série, pour que la correspondance et l'inventaire restent vrais. OpenTofu verra ensuite un disque recréé hors de lui : `tofu plan` doit être **vide** si les options sont identiques, sinon on aligne le code ou on laisse OpenTofu reprendre la main par un `apply` relu.)
5. **Recréation.** Au rafraîchissement suivant de l'inventaire (quelques minutes, ou tout de suite après `--refresh`), cephadm applique la spécification : le nouvel OSD prend l'identifiant **9** (le premier identifiant `destroyed` de l'hôte), revient à son poids, et le *backfill* le remplit. `HEALTH_OK` à la fin.
6. **Réponses.** Sans `--replace` : l'OSD est **purgé** (retiré de la carte CRUSH et de la carte des OSD) ; le nouveau disque recevra un nouvel identifiant (le plus petit libre) et la carte CRUSH change deux fois (retrait puis ajout) : deux mouvements de données au lieu d'un. Panne réelle : l'OSD est déjà `down`, puis `out` après 10 minutes ; la récupération a commencé seule. Il ne reste qu'à attendre la fin de la récupération (plus aucun PG `degraded` lié à cet OSD), vérifier `safe-to-destroy`, retirer (`--replace`, sans `--zap` : le disque est illisible), remplacer, contrôler. Les étapes « vider l'OSD » disparaissent (c'est la récupération qui l'a fait) ; les contrôles restent.

**Explications**

Retirer un OSD proprement, c'est faire migrer ses données **avant** de le détruire, pour ne jamais descendre sous trois copies (le *backfill* copie vers la nouvelle place pendant que l'ancienne copie existe encore). L'état `destroyed` garde l'identifiant et la position CRUSH : le nouvel OSD reprend exactement la place de l'ancien, et la carte CRUSH ne bouge pas, donc seules les données de cet OSD sont déplacées. L'orchestrateur enchaîne les étapes (`out`, attente, `destroy`, `zap`) et refuse un OSD qui n'est pas sûr à détruire.

**Alternatives**
- *`ceph osd out 9`, attendre, `ceph orch daemon stop osd.9`, `ceph osd destroy 9 --yes-i-really-mean-it`* : les étapes à la main, utiles quand l'orchestrateur est indisponible.
- *Retrait à poids progressif* (`ceph osd crush reweight osd.9 0` par paliers) : étale le mouvement pour un gros OSD.

**Pièges classiques**
- Supprimer le disque virtuel **avant** la fin de la vidange : l'OSD tombe pendant que des PG n'ont pas fini de migrer, le cluster se retrouve dégradé.
- Se tromper de disque dans Proxmox (`scsi2` au lieu de `scsi1`) : un second OSD tombe ; si c'était l'autre SSD de la baie A, des PG perdent la copie de la baie.
- Oublier `ssd=1` sur le disque neuf : sans `crush_device_class` dans la spécification, l'OSD reviendrait en classe `hdd` ; avec la classe écrite dans `osd.ssd` (E04), c'est le filtre `rotational: 0` qui ne le reconnaît plus, et aucun OSD n'est recréé.
- Retirer avec `--force` parce que « c'est long » : `--force` ignore le contrôle de sûreté.

**En production chez MédiSphère**
RB-080 (E22), voyant de localisation (`ceph device light on`) pour le technicien de salle, suivi SMART par le module `devicehealth`, stock de disques de remplacement, et ticket fournisseur ouvert dès le premier signe (secteurs réalloués, erreurs de lecture), pas à la panne.

---

### M08-E20 — Capacité, quotas et seuils de remplissage

**Solution**

Fichiers : [`seuils-quotas.sh`](fichiers/M08-E20/seuils-quotas.sh), [`outils/rapport-capacite.sh`](fichiers/M08-E20/ceph/outils/rapport-capacite.sh).

1. **Calcul** (avec `ceph04` : 8 SSD et 4 HDD de 64 Gio).
   - SSD : 512 Gio bruts, en réplication ×3 répartie sur trois baies. La baie A a 4 SSD (256 Gio), les baies B et C 2 SSD chacune (128 Gio). Chaque PG a **une** copie par baie : la capacité utile est limitée par la baie la plus petite, **128 Gio** (la baie A ne se remplira qu'à moitié). `MAX AVAIL` d'un pool `ssd-baie` le reflète (Ceph calcule la place disponible à partir de l'OSD qui se remplira le premier, en tenant compte du ratio `full`).
   - Perte d'un SSD de la baie **B** (2 SSD) : ses copies ne peuvent aller que sur l'autre SSD de la baie B, qui reçoit le double. Pour ne pas dépasser `full` (0,95), chaque SSD des baies B et C doit rester sous **47,5 %** ; pour ne pas dépasser `backfillfull` (0,85, la récupération s'arrête avant), sous **42,5 %**. Dans la baie A (4 SSD), un SSD perdu répartit sa charge sur trois : limite ≈ 64 %.
   - HDD (EC 2+1, une copie par baie) : 4 HDD, mais la baie B et la baie C n'en ont qu'**un** : la perte d'un HDD dans B ou C ne peut pas être reconstruite (pas d'autre HDD dans la baie), le pool reste dégradé jusqu'au remplacement : la marge ne sert à rien pour cette panne, c'est le remplacement rapide qui compte.
2. **Seuils.** Les seuils de Nadia (alerte à 75 %) préviennent **après** le point où la perte d'un SSD des baies B ou C ne peut plus être absorbée (~42 %). Conclusion : les seuils globaux d'OSD restent des garde-fous (`nearfull` 0,75, `backfillfull` 0,85, `full` 0,95, posés), mais l'alerte de **planification** doit porter sur le remplissage des SSD des petites baies, à 40 %, dans la supervision (E24) et dans le rapport. `nearfull` déclenche `OSD_NEARFULL` (avertissement) ; `backfillfull` empêche un OSD de **recevoir** des données de récupération (`OSD_BACKFILLFULL`, PG `backfill_toofull`) ; `full` bloque **toutes les écritures** du cluster (`OSD_FULL`), y compris les suppressions qui demanderaient de l'espace de journal.
   ```
   [root@ceph01 ~]# ceph osd set-nearfull-ratio 0.75
   [root@ceph01 ~]# ceph osd set-backfillfull-ratio 0.85
   [root@ceph01 ~]# ceph osd dump | grep ratio
   full_ratio 0.95
   backfillfull_ratio 0.85
   nearfull_ratio 0.75
   ```
3. **Quotas et taille cible.**
   ```
   [root@ceph01 ~]# ceph osd pool set-quota rbd-test max_bytes 107374182400
   [root@ceph01 ~]# ceph osd pool set-quota rbd-ec-donnees max_bytes 64424509440
   [root@ceph01 ~]# ceph osd pool set rbd-test target_size_ratio 0.5
   [root@ceph01 ~]# ceph osd pool autoscale-status
   ```
   Le quota porte sur les données **stockées** (avant réplication) : 100 Gio de `rbd-test` consomment 300 Gio bruts. `target_size_ratio` dit à l'autoscaler la part de la capacité que le pool **finira** par occuper : il dimensionne le nombre de PG pour l'avenir au lieu de le faire grandir par à-coups (chaque changement de `pg_num` déplace des données).
4. **Surengagement.** `rbd du -p rbd-test` : colonne `PROVISIONED` (somme des tailles déclarées) contre `USED`. Exemple : 20 (iSCSI) + 10 (EC, données ailleurs) + images d'E06 ≈ 40 Gio promis pour 6 Gio utilisés. Si toutes se remplissaient, le quota du pool (100 Gio) bloquerait d'abord **ce pool** : les clients RBD verraient des écritures en attente puis en erreur (`EDQUOT`) ; sans quota, ce serait le cluster entier au seuil `full`.
5. **Pool plein.**
   ```
   [root@ceph01 ~]# ceph osd pool create essai-plein --rule ssd-baie
   [root@ceph01 ~]# ceph osd pool set-quota essai-plein max_bytes 2147483648
   [root@ceph01 ~]# ceph osd pool application enable essai-plein rados
   [root@ceph01 ~]# rados bench -p essai-plein 120 write -b 4M --no-cleanup
   …
   [root@ceph01 ~]# ceph health detail
   HEALTH_WARN 1 pool(s) full
   [WRN] POOL_FULL: 1 pool(s) full
       pool 'essai-plein' is full (reached quota's max_bytes: 2 GiB)
   ```
   Le banc se bloque (les écritures attendent) ou échoue selon l'option `full_try`. Au seuil `full` du **cluster**, ce serait `HEALTH_ERR`, `OSD_FULL`, et toutes les écritures de tous les pools bloquées, RBD et CephFS compris. Suppression :
   ```
   [root@ceph01 ~]# ceph config set mon mon_allow_pool_delete true
   [root@ceph01 ~]# ceph osd pool delete essai-plein essai-plein --yes-i-really-really-mean-it
   [root@ceph01 ~]# ceph config set mon mon_allow_pool_delete false
   ```
   ⚠️ Le nom du pool est saisi **deux fois** : relis-le avant d'appuyer sur Entrée.
6. **Rapport.** [`rapport-capacite.sh`](fichiers/M08-E20/ceph/outils/rapport-capacite.sh) lit `ceph df detail`, `ceph osd df tree`, `ceph osd dump` et `ceph osd pool ls detail` (quotas), en JSON, et calcule capacité brute et utile par classe, remplissage et marge par pool, OSD le plus rempli, et l'alerte de planification (40 % des SSD des baies à deux SSD). Le **surengagement RBD** (`rbd du`, `rbd ls -l`) demande de lire les en-têtes d'images, donc des droits OSD sur les pools : il est facultatif (`--rbd`, avec une clé `profile rbd-read-only` comme `client.rbd-lecture`). Pour le reste, `client.rapport` avec `mon 'allow r' mgr 'allow r'` suffit : ce sont des lectures de cartes et de statistiques détenues par les moniteurs et le gestionnaire ; aucune donnée d'utilisateur n'est lisible.
   ```
   [root@ceph01 ~]# ceph auth get-or-create client.rapport mon 'allow r' mgr 'allow r'
   admin@ceph01:~/src/ceph$ sudo CEPH_ID=rapport CEPH_KEYRING=/etc/ceph/ceph.client.rapport.keyring outils/rapport-capacite.sh
   == Capacité ceph-par1 (2026-10-21 10:12) ==
   Classe  Brut     Utilisé  Utile (×3 / baie)  Seuil planif.
   ssd     512 Gio  9 %      128 Gio             40 % des SSD des baies B et C
   …
   Pool              Stocké   Quota    Marge   MAX AVAIL
   rbd-test          6.1 Gio  100 Gio  94 %    …
   OSD le plus rempli : osd.4 (ceph02, ssd) 11 %
   ```

**Explications**

Ceph ne raisonne pas en « disque plein » mais en **OSD le plus plein** : un seul OSD au seuil `full` bloque les écritures du cluster entier, parce qu'un PG qui écrit sur cet OSD ne peut plus garantir ses copies. La capacité utile dépend donc de la règle CRUSH, du domaine de panne, de l'équilibre entre OSD (le module `balancer`) et de la panne qu'on veut pouvoir absorber, bien plus que de la somme des disques. Les quotas cloisonnent la saturation par pool ; les seuils protègent le cluster ; la supervision et le rapport permettent d'**acheter des disques avant**.

**Alternatives**
- *Seuils plus bas* (`full` à 0,90) : plus de marge pour les urgences (on peut temporairement remonter à 0,95 pour supprimer), au prix de 5 % de capacité.
- *Quotas par espace de noms RBD ou par sous-volume* (E31) plutôt que par pool : plus fins, par équipe.

**Pièges classiques**
- Lire `ceph df` `AVAIL` (brut global) au lieu de `MAX AVAIL` du pool.
- Ignorer le déséquilibre des baies (4 SSD contre 2) : la capacité est celle de la petite baie.
- Laisser `mon_allow_pool_delete` à `true` après un nettoyage.
- Remonter `full_ratio` à 0,98 pour « débloquer » un cluster plein sans libérer de place : il se rebloque aussitôt, plus près du vrai mur (BlueStore a besoin d'espace libre pour lui-même).

**En production chez MédiSphère**
Rapport hebdomadaire envoyé à Claire, prévision de croissance (pente sur 30 jours dans Prometheus, M21), seuil de commande de matériel à 40 % des SSD de la plus petite baie (délai de livraison compris), quotas par équipe, et règle d'équilibre : des baies de capacité égale (ce que l'ajout de `ceph04` dans une seule baie ne respecte pas : le mini-projet le relève).

---

### M08-E21 — Revue : spécifications et règles CRUSH du stagiaire

**Réponses à l'étape 1.** Deux moniteurs (`ceph21`, `ceph22`), dont un sur le **réseau de réplication** (10.20.31.52) : les clients et `ceph23` ne le joindront pas. Les trois copies d'un objet de `sauvegardes` : en fait **deux** (`size 2`), choisies par `par2-ssd` parmi des **OSD** sans contrainte d'hôte : les deux peuvent être sur le même nœud. `client.admin` : sur les quatre hôtes `_admin`, dont `pbs01` (le serveur de sauvegarde de PAR2, qui détient donc de quoi détruire le cluster qu'il sauvegarde). Un disque ajouté à un nœud : la spécification `all: true` gérée en fait un OSD dans la minute, quel que soit son usage prévu (disque de journal, disque ZFS, disque d'un autre service).

**Revue** (ordre de traitement ; gravité dans **notre** contexte)

| N° | Fichier : ligne(s) | Défaut | Cat. | Gravité | Impact chez nous | Correction |
|---|---|---|---|---|---|---|
| 1 | `ingress.yaml` : 13-23 ; MR | Clé privée (et certificat) dans le dépôt | Sécu. | Critique | Quiconque lit le dépôt peut se faire passer pour le S3 de PAR2 (interception des sauvegardes de `pbs01`) ; la clé reste dans l'historique | Clé **révoquée et remplacée** ; `ssl_cert`/`ssl_key` ajoutés à l'application (E11), jamais versionnés ; contrôle automatique « pas de bloc `PRIVATE KEY` » dans la CI (E23) |
| 2 | `crush-ajouts.txt` : 9 | `chooseleaf … type osd` : domaine de panne = OSD | Dispo. | Critique | Les copies d'un PG peuvent être sur deux disques d'un même nœud : la perte d'un nœud (redémarrage compris) rend des PG inactifs, voire perd des données (avec `size 2`) | `step chooseleaf firstn 0 type host` (ou `rack` si la hiérarchie existe) ; règle créée par `ceph osd crush rule create-replicated par2-ssd default host ssd` et testée avec `crushtool --test` |
| 3 | `pools.sh` : 5-6 | `size 2`, `min_size 1` | Dispo. | Critique | Avec `min_size 1`, des écritures sont acquittées avec **une seule** copie ; une seconde panne avant la récupération les perd définitivement (cas classique de perte de données Ceph) | `size 3`, `min_size 2` (défauts) ; si la place manque, EC sur plus de nœuds, jamais `min_size 1` |
| 4 | `mon.yaml` : 4 | Deux moniteurs | Dispo. | Critique | Quorum = majorité de 2 = 2 : la perte d'**un** moniteur arrête tout le cluster (aucune E/S possible sans quorum). Deux moniteurs sont **moins** disponibles qu'un seul | `count: 3` (un par nœud) ; nombre impair, 3 ou 5 |
| 5 | `hosts.yaml` : 13 | `ceph22` ajouté par son adresse **cluster** (10.20.31.52) | Dispo. | Élevée | cephadm administre l'hôte et place le moniteur sur cette adresse (réseau non routé) : clients, `ceph23` et `pbs01` ne joignent pas ce moniteur ; avec le n° 4, plus de quorum à la première panne | `addr: 10.20.30.52` (réseau public) ; `public_network` posé au bootstrap |
| 6 | `hosts.yaml` : 6, 15, 24, 28-32 ; MR | `_admin` sur tous les nœuds **et sur `pbs01`** | Sécu. | Élevée | `client.admin` sur le serveur de sauvegarde : une compromission de `pbs01` détruit à la fois le cluster et les sauvegardes. Les nœuds `_admin` multipliés multiplient les copies de la clé | `_admin` sur les seuls nœuds du cluster (un par baie suffit) ; `pbs01` n'est **pas** un hôte du cluster : il reçoit une clé cliente dédiée (`profile rbd-read-only` sur les pools sauvegardés, restriction réseau, E13/E25) |
| 7 | `osd.yaml` : 9-10 | `osd_memory_target` = 4 Gio par OSD sur des nœuds de 6 Go qui en portent 3 | Perf./Dispo. | Élevée | 12 Gio visés pour 6 Go de mémoire : les OSD grossissent jusqu'à l'OOM du noyau, qui tue un OSD (ou le MON) au hasard, sous charge. Le test de Lucas, sans charge, n'a pas vu le cache se remplir | 1 Gio par OSD (valeur du module, au-dessus du minimum `osd_memory_target_min`), `osd_memory_target_autotune` laissé à `false` sur des nœuds partagés |
| 8 | `osd.yaml` : 5-8 ; MR | `host_pattern: '*'` et `all: true`, service géré | Expl. | Élevée | Tout disque vide de n'importe quel hôte devient un OSD, sans distinction de classe ; un disque effacé pour réparation (E19) redevient OSD aussitôt ; avec `pbs01` hôte (n° 6), ses disques vides aussi | Deux services `osd.ssd` et `osd.hdd` filtrés (`rotational: 0/1`, `size`), placement par étiquette `osd` ; `unmanaged: true` pendant les remplacements |
| 9 | `rgw.yaml` : 8 ; `ingress.yaml` : 4-5, 9 | RGW sur 443 et haproxy sur 443 sur les **mêmes** hôtes | Dispo. | Élevée | Conflit de port : haproxy (VIP:443) ou RGW (*:443) ne démarre pas ; selon l'ordre, la VIP répond par un RGW en HTTP sur 443, ou ne répond pas | `rgw_frontend_port: 8080` (et `networks: [10.20.30.0/24]`), haproxy seul sur 443 |
| 10 | `pools.sh` : 9 | Profil EC 2+1 avec `crush-failure-domain=osd` | Dispo. | Élevée | Deux *chunks* d'un même objet sur un même nœud : la perte d'un nœud perd deux *chunks* sur trois, donc l'objet | `crush-failure-domain=host` ; et avec trois nœuds, `min_size` à surveiller (E15) |
| 11 | `crush-ajouts.txt` : 14-20 ; `pools.sh` : 14 | Métadonnées CephFS sur HDD | Perf. | Moyenne | Chaque opération de fichier (lister, créer, ouvrir) attend un HDD : CephFS inutilisable sous charge, même si les données sont peu volumineuses | Règle SSD pour `cephfs.cephfs.meta` |
| 12 | `pools.sh` : 21 ; MR | Utilisateur S3 `demo` **administrateur** RGW, clé et secret faibles écrits dans le script | Sécu. | Élevée | Tout lecteur du dépôt a un compte administrateur S3 (lecture de tous les compartiments, dont les sauvegardes) | Supprimer `demo` ; un compte RGW (E12) par usage, clés générées (`--gen-secret`), dans le Vault ; jamais `--admin` pour un usage applicatif |
| 13 | `ingress.yaml` : 8 | VIP en `/32` | Dispo. | Moyenne | cephadm choisit l'interface qui a une adresse **dans le réseau** de la VIP : avec `/32`, aucune ; keepalived ne monte pas la VIP (ou la monte au mauvais endroit) | `virtual_ip: 10.20.30.200/24` |
| 14 | `ingress.yaml` : 11-12 | `monitor_user`/`monitor_password` à `admin`/`admin` | Sécu. | Moyenne | Statistiques haproxy (et page `/stats` qui permet de voir les serveurs) accessibles avec un mot de passe connu | Laisser cephadm générer le mot de passe (ou le poser à l'application depuis le Vault) |
| 15 | `mds.yaml` : 5 | Un seul MDS | Dispo. | Moyenne | Pas de MDS en attente : la perte du nœud `ceph23` arrête CephFS jusqu'au redéploiement | `count: 2` (un actif, un en attente) sur deux nœuds différents |
| 16 | `pools.sh` : 16-18 | Autoscaler désactivé globalement, `nearfull` à 0,95 et `full` à 0,97 | Expl. | Moyenne | 32 PG fixes quel que soit le volume ; alerte de remplissage **au** mur (0,95), aucune marge pour récupérer après une panne | Autoscaler actif (taille cible par pool), seuils d'E20 (0,75 / 0,85 / 0,95) |
| 17 | `crush-ajouts.txt` : 6 ; MR | Carte injectée à la main (`setcrushmap`) sans test | Expl. | Faible | Une faute de frappe déplace toutes les données ou rend des PG inactifs ; aucune trace de revue | Commandes `ceph osd crush rule create-replicated`, ou carte testée par `crushtool --test` dans la CI |
| 18 | MR ; `ingress.yaml` : 4-5 | Deux RGW et deux haproxy pour une passerelle « de secours » | Dispo. | Faible | La perte d'un nœud laisse un seul RGW ; acceptable au début, à documenter | Trois si la mémoire le permet, sinon la limite écrite dans le README |

Défauts mineurs acceptés : `count_per_host: 1` (redondant), l'absence de `networks:` pour le moniteur (le `public_network` du bootstrap suffit).

**Premier traité : n° 1**, parce qu'il est **déjà** effectif (la clé est dans l'historique de la MR, lisible par tous ceux qui ont accès au projet) et que corriger le fichier ne suffit pas : il faut révoquer le certificat et en émettre un autre. Viennent ensuite ceux qui perdent des données ou arrêtent le cluster **à la première panne** (2, 3, 4, 10), puis 5 et 6 (quorum, clé d'administration), 7 et 9 (services qui ne tiennent pas), le reste.

**Versions corrigées** (dans [`fichiers/M08-E21/`](fichiers/M08-E21/)) :
```yaml
# mon.yaml
service_type: mon
placement:
  count: 3
  label: mon
```
```yaml
# osd.yaml
service_type: osd
service_id: ssd
placement:
  label: osd
spec:
  data_devices:
    rotational: 0
    size: '60G:70G'
---
service_type: osd
service_id: hdd
placement:
  label: osd
spec:
  data_devices:
    rotational: 1
    size: '60G:70G'
```
(`osd_memory_target` = 1 Gio posé par `ceph config set osd osd_memory_target 1073741824`, comme au palier 1.)
```yaml
# ingress.yaml — sans certificat ni clé (ajoutés à l'application)
service_type: ingress
service_id: rgw.par2
placement:
  label: rgw
spec:
  backend_service: rgw.par2
  virtual_ip: 10.20.30.200/24
  frontend_port: 443
  monitor_port: 1967
```
```
rule par2-ssd {
	id 1
	type replicated
	step take default class ssd
	step chooseleaf firstn 0 type host
	step emit
}
```

**Question de fond.** Trois nœuds en réplication ×2 sur un site de secours, c'est économiser sur le seul endroit où l'on n'a pas le droit de perdre : la copie de secours. Avec `size 2`, toute panne laisse **une** copie ; avec `min_size 1` on écrit sans filet, avec `min_size 2` on s'arrête à la première panne. Mieux : réplication ×3 (la capacité du site se dimensionne pour cela) ou, si le volume l'impose, un code d'effacement sur **plus** de nœuds (4+2 sur six nœuds). Et surtout : un cluster Ceph à PAR2 n'est un secours de `ceph-par1` que s'il en reçoit les données : réplication asynchrone `rbd-mirror` (mode instantanés) pour les images, synchronisation multisite RGW pour les objets, `cephfs-mirror` pour les fichiers, à travers le tunnel `wg0`, avec un RPO mesuré. Sans cela, c'est un second cluster indépendant, pas un PRA (F5). Enfin, la sauvegarde de `pbs01` ne doit pas dépendre du cluster qu'elle protège : `pbs01` est une cible **hors** Ceph, par conception.

**Conseils à Lucas.** Teste avec la mémoire, les disques et le réseau de la cible, et **sous charge** (un `rados bench` d'une heure aurait montré l'OOM du n° 7). Teste les pannes, pas seulement le démarrage : arrête un nœud et regarde le quorum et les PG. Et relis ce que tu versionnes comme si le dépôt était public : un secret dans un fichier de configuration est un secret publié.

**Grille d'auto-évaluation** (Karim relit comme une MR ; 2 points par ligne, 20 au total, acceptable à 14)

| Critère | 0 | 1 | 2 |
|---|---|---|---|
| Défauts critiques (1 à 4) | un oublié | tous, impact vague | tous, impact concret chez nous |
| Défauts élevés (5 à 10, 12) | moins de 4 | 4 à 6 | les 7 |
| Quorum à deux moniteurs expliqué | non | « il faut un nombre impair » | majorité de 2, effet de la perte d'un MON |
| Le n° 1 traité par une **révocation** | non | clé déplacée | révoquée, remplacée, déplacée, contrôle en CI |
| Corrections précises (champ, valeur, commande) | rares | la plupart | toutes |
| Lien `osd_memory_target` ↔ mémoire du nœud | absent | signalé | calculé (3 × 4 Gio > 6 Go) |
| Conflit de port RGW / haproxy | absent | signalé | expliqué avec la correction |
| Ordre de traitement justifié | absent | sans justification | justifié |
| Question de fond | absente | avis | argumentée (`min_size`, EC, réplication vers PAR2) |
| Ton de la revue | jugement de la personne | neutre | utile : explique et propose |

---

### M08-E22 — Runbook : remplacer un disque défaillant

**Solution** : [`RB-080-remplacer-un-disque.md`](fichiers/M08-E22/medisphere/docs/stockage/runbooks/RB-080-remplacer-un-disque.md).

Ce qui fait la valeur du runbook (à comparer avec le tien) :
- **Un tableau d'entrée** « ce que je vois → où aller » : alerte `OSD_DOWN` seule ; `OSD_DOWN` + PG `degraded` ; PG `inactive`/`incomplete`/`down` (arrêt, escalade immédiate) ; `HEALTH_ERR` autre ; disque signalé par SMART mais OSD `up` (remplacement préventif).
- **Une qualification en lecture seule** d'abord (`ceph -s`, `ceph health detail`, `ceph osd tree down`, `ceph osd find <ID>`, `ceph device ls-by-host`), avec, pour chaque commande, ce qu'il faut y lire.
- **Des points d'arrêt explicites** : plus d'un OSD `down` dans des **baies différentes** ; un PG non `active` ; `ceph osd safe-to-destroy` qui refuse alors que la récupération est finie ; tout doute sur le disque physique. À chaque point d'arrêt : appeler l'astreinte de niveau 2 (Plateforme), ne rien faire d'autre.
- **La décision « attendre »** : en panne réelle, l'OSD passe `out` seul après 10 minutes et la récupération démarre ; on n'intervient pas tant que des PG sont `degraded` à cause de lui (le disque n'apporte plus rien, mais les autres copies se reconstruisent). `noout` n'est **pas** un geste de panne : il sert aux maintenances prévues (redémarrage d'un nœud).
- **Le retrait** (`ceph orch osd rm <ID> --replace`, sans `--zap` si le disque est mort, suivi par `ceph orch osd rm status`), la localisation (`ceph device light on <DEVID> ident`), le remplacement par le technicien, le contrôle (nouvel OSD, même identifiant, classe correcte, `HEALTH_OK`), la clôture (`ceph crash archive-all` après lecture, voyant éteint, ticket fournisseur).
- **Les interdits**, en encadré : `ceph osd purge` ou `ceph osd lost` (escalade obligatoire : ces commandes déclarent des données perdues) ; `--force` ; `ceph orch device zap` sur un disque non identifié deux fois ; redémarrer un autre nœud pendant une récupération ; baisser `min_size` « pour débloquer ».
- **La transposition au lab** : « remplacement physique » = détacher/supprimer/ajouter le disque virtuel de la VM (commandes `qm` d'E19, avec la vérification du `scsiN`).
- **Retour arrière** : avant la destruction, `ceph orch osd rm stop <ID>` remet l'OSD en service ; après, il n'y a pas de retour : on va jusqu'au remplacement.
- **Historique** : version, date, auteur, exercice joué (E22) et écarts constatés.

**Pièges classiques**
- Un runbook qui raconte (« on retire l'OSD ») au lieu de prescrire (« lance … ; tu dois voir … ; sinon, va à … »).
- Pas de critère d'escalade : l'astreinte de niveau 1 « essaie des choses » sur un cluster dégradé.
- Recopier `--zap` d'E19 : sur un disque mort, il échoue (ou attend) ; sur le mauvais disque, il détruit un OSD sain.
- Ignorer le cas « disque qui faiblit mais OSD `up` » : c'est le meilleur moment pour remplacer (aucune donnée en danger).

**En production chez MédiSphère**
RB-080 joué deux fois par an par chaque membre de l'astreinte sur le cluster de préproduction, relié à l'alerte `OSD_DOWN` (lien dans l'alerte, E24), mis à jour après chaque utilisation réelle (post-mortem si l'intervention a dévié).

---

### M08-E23 — Le cluster décrit par le code

**Solution** (une solution possible, celle du corrigé)

Fichiers : le projet complet [`fichiers/M08-E23/ceph/`](fichiers/M08-E23/ceph/) : [`README.md`](fichiers/M08-E23/ceph/README.md), [`.gitlab-ci.yml`](fichiers/M08-E23/ceph/.gitlab-ci.yml), [`.yamllint.yml`](fichiers/M08-E23/ceph/.yamllint.yml), [`specs/`](fichiers/M08-E23/ceph/specs/) (huit spécifications), [`config/`](fichiers/M08-E23/ceph/config/) (état déclaratif hors spécifications : règles CRUSH, profils EC, pools, quotas, seuils, options), [`outils/`](fichiers/M08-E23/ceph/outils/) (`appliquer.sh`, `verifier-specs.sh`, `tester-crush.sh`, `derive.sh`, `config-cluster.sh`, `cert-ingress.sh`, `rapport-capacite.sh`, `lib.sh`, unités systemd), [`tests/`](fichiers/M08-E23/ceph/tests/) (un cas fautif par règle maison et une carte CRUSH fautive, `tester-regles.sh`), [`.gitleaks.toml`](fichiers/M08-E23/ceph/.gitleaks.toml) (exception pour le faux bloc de clé d'un cas fautif), et côté `plateforme/ansible` : [`pare_feu.yml.extrait`](fichiers/M08-E23/ansible/inventories/lab/pare_feu.yml.extrait).

**Périmètre.** Le projet existe depuis E03 (`bootstrap/`, `specs/hosts.yaml`, `mon.yaml`, `mgr.yaml`), E04 (`osd.yaml`) et E05 (`outils/pool-repliquee.sh`) : on le complète. Dans le dépôt : les huit spécifications (services cephadm), l'état déclaratif hors spécifications sous forme d'un fichier de valeurs (`config/cluster.yaml` : règles, profils EC, pools avec règle, quota, application et taille cible ; seuils ; options `ceph config` ; hiérarchie CRUSH attendue, vérifiée seulement) appliqué et vérifié par `outils/config-cluster.sh`, les exports NFS (`config/nfs/legacy-rdv.json`), la carte CRUSH attendue (`config/crush-attendu.txt`, pour les tests hors ligne). Hors du dépôt : les clés cephx (créées par commande, sauvegardées chiffrées, E25), le certificat et la clé du point d'entrée (sur `adm01`), les comptes RGW (E12, données d'administration du service), la carte CRUSH binaire (produite).

**Validation de MR** (`.gitlab-ci.yml`, sur `runner01`) :
- `yamllint` (fichiers à plusieurs documents) ;
- `outils/verifier-specs.sh` : règles maison, chacune avec un cas fautif dans `tests/cas-fautifs/` que le job `tests-regles` vérifie **rejeté** :
  1. `mon` : nombre impair, ≥ 3 (`count`, ou nombre d'hôtes portant l'étiquette du placement) ;
  2. aucune adresse d'hôte hors de 10.10.30.0/24 ;
  3. `_admin` sur trois hôtes au plus, tous des nœuds `ceph0N` ;
  4. `ingress` : `virtual_ip` avec masque /24, pas de `ssl_cert`/`ssl_key`/`monitor_password` dans le fichier ;
  5. aucun bloc `PRIVATE KEY` dans le dépôt ;
  6. ports : le `frontend_port` d'un *ingress* différent du port de son service RGW ;
  7. OSD : pas de `all: true`, filtres `rotational` présents, aucun `osd_memory_target` > 1,5 Gio (3 OSD par nœud de 6 Go) ;
  8. MDS : `count` ≥ 2 ;
- `outils/tester-crush.sh` : `crushtool --test` de `config/crush-attendu.txt` (aucun *bad mapping*, aucune baie en double pour `ssd-baie`, `hdd-baie`, `ec-21-hdd`) ; testé à la rédaction avec `crushtool` 19.2 sur cette carte ; `crushtool` vient du paquet `ceph-base` de Debian 13 sur `runner01` (Reef, compatible pour un test de carte) ;
- `gitleaks` (gabarit `qualite.yml`).

**Application : décision.** L'application reste sur **`adm01`**, par `outils/appliquer.sh` : il affiche le `ceph orch apply --dry-run` de chaque spécification modifiée (ou de toutes), demande une confirmation, applique, puis lance `derive.sh`. Arguments (README) :
- *Flux* : appliquer depuis la CI demanderait à `runner01` de joindre les moniteurs (3300) **et** le gestionnaire actif (6800-7568, port dynamique, qui change à chaque bascule) sur les trois nœuds, ou un accès SSH à `ceph01` ; c'est ouvrir le plan de contrôle du stockage à une machine qui exécute le code de tous les projets du groupe (exécuteur `shell` partagé).
- *Droits* : `orch apply` exige une clé avec écriture sur le gestionnaire (`mgr 'allow rw'` ou au moins `allow command "orch apply"`) ; la restriction aux seules simulations (`with dry_run=true`) n'est pas garantie pour un argument booléen (⚠️ non vérifié) : une clé de CI capable de simuler serait capable d'appliquer, c'est-à-dire de supprimer des services.
- *Rythme* : quelques changements par mois, chacun relu et suivi en direct (mouvements de données) ; l'automatisation n'apporte pas de vitesse utile, elle retire l'humain qui regarde `ceph -s`.
- *Ce que la CI fait quand même* : la **dérive**, en lecture seule (voir ci-dessous), et toutes les validations hors ligne.
La décision sera revue quand un exécuteur dédié au stockage (étiquette `ceph`, hôte isolé) existera.

**Dérive.** `outils/derive.sh` exporte `ceph orch ls --export`, normalise les deux côtés (`yq -P 'sort_keys(..)'`, suppression des champs ajoutés par cephadm : `status`, `events`, `unmanaged: false`, et des blocs `ssl_cert`/`ssl_key` du côté du cluster), compare service par service, signale aussi les services présents d'un seul côté, et vérifie l'état déclaratif (`config-cluster.sh --verifier`). Il tourne dans un **pipeline planifié** (`derive`, chaque nuit) sur `runner01`, avec la clé `client.ci-lecture` (`mon 'allow r' mgr 'allow r'`, restreinte à 10.10.20.15) en variable protégée et masquée (fichier) ; ce sont les **seuls** flux ouverts : `runner01` → 10.10.30.51-53 TCP 3300 et 6800-7568 ([extrait](fichiers/M08-E23/ansible/inventories/lab/pare_feu.yml.extrait)). Un écart fait échouer le pipeline (notification GitLab à l'équipe) ; le même script sert à la main sur `adm01`.

**Démonstration.** MR qui passe `mon.yaml` à `count: 2` : le job `verifier-specs` échoue (« règle 1 : nombre de moniteurs pair ou < 3 ») ; MR refermée sans fusion, gardée comme preuve.

**Services par défaut** (hors `specs/`, listés dans le README) : `crash`, `ceph-exporter` (et la pile de supervision si elle est déployée un jour) ; ils n'ont pas de paramètres propres au lab.

**Explications**

cephadm est déjà déclaratif : une spécification appliquée devient l'intention du gestionnaire, qui réconcilie (déploie, retire, redéploie). Le dépôt n'invente donc rien ; il **garde** l'intention hors du cluster (relecture, historique, restauration après une perte du gestionnaire) et la confronte à la réalité. Ce qui n'est pas exprimable en spécification (CRUSH, pools, `ceph config`) devient un état déclaratif minimal appliqué par un script idempotent : moins élégant qu'un opérateur, mais vérifiable. La séparation « la CI lit, l'humain écrit » est un choix de risque, explicite et révisable, pas une limite technique.

**Alternatives**
- *Application par la CI* sur un exécuteur dédié au VLAN 30, avec une clé `mgr` d'écriture et un job manuel protégé : défendable si les changements se multiplient ; la variante est décrite dans le README.
- *Rôles Ansible* (`ceph_specs`) qui poussent les spécifications : l'outil commun du socle, mais un niveau d'indirection de plus au-dessus d'un orchestrateur déjà déclaratif.
- *cephadm-ansible* (dépôt officiel) : utile pour préparer les hôtes, pas pour gérer les services.
- *Rook* (M16) : le cluster décrit par des ressources Kubernetes, réconciliées en continu.

**Pièges classiques**
- Comparer les exports bruts : des écarts permanents (ordre des clés, champs par défaut) qui font ignorer la vraie dérive.
- Versionner la sortie de `ceph orch ls --export` telle quelle, certificat d'*ingress* compris.
- Oublier les services créés par d'autres commandes (`mds.cephfs` par `fs volume create`, `nfs.par1` par `nfs cluster create`) : ils existent sans fichier jusqu'à ce qu'on les exporte.
- Règles maison sans cas fautif : elles ne prouvent pas qu'elles détectent quoi que ce soit.
- Donner à la CI la clé `client.admin` « pour la dérive ».

**En production chez MédiSphère**
Le dépôt `plateforme/ceph` devient la source de reconstruction du cluster (avec la sauvegarde de configuration d'E25), étiqueté à chaque changement, lié aux fiches de changement ; la dérive alimente un tableau de bord (M21) ; les règles maison s'enrichissent à chaque incident (E35-E43).
