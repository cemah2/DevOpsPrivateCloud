# Module 10 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- format exact des sorties JSON de la CLI `openstack` 10.x sur lesquelles s'appuient les checks et `ms-verif-openstack` (`compute service list --long` avec `Disabled Reason`, `network agent list` avec `Alive` booléen, `quota show` en objet ou en liste `Resource`/`Limit`, `access rule list`, `loadbalancer status show`) ;
- règles d'accès des application credentials avec le joker `/**` et la découverte des versions des API (E26) ; type de service `volumev3` ou `block-storage` dans le catalogue de Kolla 2026.1 ;
- rôle `letsencrypt` de Kolla pointé vers step-ca (client lego, confiance dans la racine par `kolla_copy_ca_into_containers`, défi HTTP-01 sur la VIP **interne**) ; si le défi interne échoue, la variante DNS-01 de `securite.md` §3 s'applique ;
- noms des bases dans une sauvegarde Mariabackup et fichier d'état de la préparation (`mariadb_backup_checkpoints` ou `xtrabackup_checkpoints`), propriétaire des fichiers après `--copy-back` (procédure officielle reprise telle quelle) ;
- effet de la recréation du conteneur `nova_libvirt` (mise à jour E28) sur les instances en marche : la mesure de continuité tranche ;
- `ovn-sbctl` dans le conteneur `ovn_sb_db` (E29) et `ovn-appctl … cluster/status` (chemin du socket de contrôle, E24) ;
- valeurs mesurées des documents de référence (durées de reprise, interruptions) : indicatives, à remplacer par les tiennes ;

**Instances d'essai du palier** (toutes détruites à la fin de leur exercice, vérifié par les checks) : `ha-essai*` (E24), `secu-essai*` (E27), `maj-essai*` (E28), `evac-essai*` (E29). Projets temporaires : `essai-restauration` (E25), `medinotif-essai` (E34, retiré après la vérification).

---

### M10-E24 — La haute disponibilité du plan de contrôle

**Solution**

Fichiers : [`docs/cloud/haute-disponibilite.md`](fichiers/M10-E24/medisphere/docs/cloud/haute-disponibilite.md) (document de référence complet), [`outils/mesure-continuite.sh`](fichiers/M10-E24/openstack/outils/mesure-continuite.sh) (dans `plateforme/openstack`, resservi en E28 et E29), [`inventaire/multinode.3-controleurs.exemple`](fichiers/M10-E24/openstack/inventaire/multinode.3-controleurs.exemple), [extrait de `globals` à trois contrôleurs](fichiers/M10-E24/openstack/etc-kolla-globals-3-controleurs.extrait.yml).

*1. Cartographie.* Sur `osctl01`, une quarantaine de conteneurs ; sur chaque calcul une dizaine. Le classement attendu est le tableau §2 du document de référence. Les données des services à état se lisent ainsi :

```
root@osctl01:~# docker volume ls --format '{{.Name}}' | sort
root@osctl01:~# docker inspect -f '{{range .Mounts}}{{.Name}}:{{.Destination}} {{end}}' mariadb rabbitmq ovn_nb_db ovn_sb_db keystone_fernet
```

*2. Points d'entrée.*

```
root@osctl01:~# grep -E 'virtual_router_id|priority|unicast|track_script' /etc/kolla/keepalived/keepalived.conf
root@osctl01:~# ip -br -4 addr show dev ens18          # 10.10.50.51/24 10.10.50.200/32 10.10.50.201/32
```

Page de statistiques : `http://10.10.50.51:1984/` dans un navigateur depuis `adm01` (tunnel SSH ou poste via VPN) ; identifiant `haproxy`, mot de passe lu par `uv run ansible-vault view etc/kolla/passwords.yml | grep '^haproxy_password'` dans **un autre** terminal. On y voit un *frontend* par API sur la VIP interne et un sur la VIP externe (suffixe `_external`), Horizon sur l'externe.

VRID 50 : les passerelles `gw01`/`gw02` font du VRRP sur le VLAN 50 avec le VRID 50 (= numéro de VLAN, M07). Deux instances keepalived d'un même VRID sur le même segment : chacune reçoit des annonces qu'elle croit de son groupe mais avec des adresses virtuelles différentes, les rejette (journal *invalid ip count* ou équivalent), et selon les priorités l'une peut se déclarer maître à tort. La VIP .1 de la passerelle peut basculer sans raison : panne réseau du VLAN entier, difficile à relier au déploiement OpenStack. Visible par `tcpdump -ni ens18 vrrp` (deux émetteurs pour le même VRID) et par les journaux de keepalived des deux côtés.

*3. Services à état.*

```
root@osctl01:~# docker exec -it mariadb mariadb -u root -p -e "SHOW STATUS LIKE 'wsrep_cluster_size'; SHOW STATUS LIKE 'wsrep_local_state_comment';"
root@osctl01:~# docker exec rabbitmq rabbitmqctl cluster_status
root@osctl01:~# docker exec rabbitmq rabbitmqctl list_queues name type | awk 'NR > 2 {print $NF}' | sort | uniq -c
root@osctl01:~# docker exec ovn_nb_db ls /var/run/ovn/        # repérer le socket de contrôle (*.ctl)
root@osctl01:~# docker exec ovn_nb_db ovn-appctl -t /var/run/ovn/ovnnb_db.ctl cluster/status OVN_Northbound
```

Taille Galera 1, état `Synced`. RabbitMQ 4.2 : une très large majorité de files `quorum` (Kolla 2026.1 les rend obligatoires), quelques files exclusives ou *stream* pour les diffusions. OVN : un membre, chef de lui-même. Jeton émis avant la panne : toujours valide après (Fernet est autoporteur ; seuls les clés et l'horloge comptent).

*4-5. Mesures* :

```
admin@adm01:~/src/openstack$ openstack --os-cloud medisphere-admin server create --flavor m1.petit --image debian-13 \
                               --network reseau-plateforme --security-group ssh-icmp-admin --key-name cle-adm01 \
                               --availability-zone nova:oscmp01 --os-project-name plateforme --wait ha-essai01
```

(Ou `--host oscmp01` avec `--os-compute-api-version 2.74`. La zone `nova:<hôte>` est une syntaxe d'administrateur qui contourne l'ordonnanceur ; `--host` passe par lui.) Même chose pour `ha-essai02` sur `oscmp02`, puis une IP flottante sur `ha-essai01`.

```
admin@adm01:~/src/openstack$ outils/mesure-continuite.sh lancer -d /tmp/ha -f <IP-FLOTTANTE> -p <IP-PRIVÉE-HA-ESSAI02>
root@osctl01:~# docker stop haproxy; sleep 120; docker start haproxy
root@osctl01:~# docker stop rabbitmq; sleep 180; docker start rabbitmq
root@pve01:~# qm stop 2101; sleep 300; qm start 2101
admin@adm01:~/src/openstack$ outils/mesure-continuite.sh arreter -d /tmp/ha && outils/mesure-continuite.sh analyser -d /tmp/ha
```

Résultats attendus (tableau §5 du document de référence) :
- **HAProxy arrêté** : toutes les API tombent ; rien d'autre. keepalived voit son script de surveillance échouer et baisse la priorité… sans autre nœud, les VIP restent, sans service derrière.
- **RabbitMQ arrêté** : Keystone et les **lectures** (qui ne passent que par la base) fonctionnent ; une création reste en `BUILD` (le conducteur ne reçoit pas le message) puis passe en `ERROR` ; après `service_down_time` (60 s par défaut dans Nova), les `nova-compute` qui n'ont plus rafraîchi leur état via RabbitMQ sont `down`. Les agents OVN restent vivants : ils ne dépendent pas de RabbitMQ (OVN a sa base, l'état « vivant » des agents vient de la base Sud). Au redémarrage, les services se reconnectent (1 à 2 min).
- **Arrêt brutal** : est-ouest ininterrompu (flux déjà programmés dans OVS des calculs), nord-sud coupé (passerelle sur `osctl01`), API coupées. Au redémarrage, MariaDB redémarre seule si l'arrêt n'a pas laissé Galera dans un état incertain ; sinon le conteneur boucle et `kolla-ansible mariadb-recovery` (lancé depuis `adm01`) amorce le cluster depuis le nœud le plus avancé.

*6-7.* Document de référence ; le plan à trois contrôleurs y est chiffré (§6). Le point le plus souvent oublié : avec un seul nœud **réseau**, trois contrôleurs ne protègent pas les IP flottantes si la passerelle n'est pas répartie (groupe `network` = les trois).

**Explications**

Kolla sépare clairement trois couches. Les **API** sont sans état : HAProxy et keepalived suffisent à les rendre redondantes. Les **services à état** (MariaDB/Galera, RabbitMQ, bases OVN en Raft) ont besoin d'un **quorum** : une majorité de membres doit se voir pour écrire, d'où le nombre impair. Le **plan de données** (OVS, `ovn-controller`, libvirt/QEMU, Ceph) ne dépend du plan de contrôle que pour les changements : c'est ce qui rend une panne du contrôleur bien moins grave qu'on ne le croit… sauf pour ce qui est centralisé dans le plan de données lui-même, ici la passerelle OVN.

**Alternatives**
- Contrôleurs « HA » en actif/passif (Pacemaker) : modèle ancien, Kolla ne le propose pas.
- Séparer le nœud réseau du contrôleur : la passerelle survit à une panne du plan de contrôle (et inversement), au prix d'une VM de plus.
- IP flottantes distribuées : plus de point unique pour le nord-sud, mais `ext-net` doit arriver sur chaque calcul (carte OS-EXT et `br-ex` partout).

**Pièges classiques**
- Mesurer avec un `ping` lancé **depuis** `adm01` vers l'adresse privée : impossible (réseau de projet) ; la mesure est-ouest se fait **dans** une instance et doit survivre à la coupure de la session SSH (d'où `nohup`).
- Conclure « tout tombe » parce qu'Horizon ne répond plus.
- Oublier qu'un arrêt brutal de Galera peut exiger `mariadb-recovery` : sans la commande sous la main, la reprise prend une heure de recherche.
- VRID laissé à la valeur par défaut de Kolla (51) : il ne collisionne pas avec les passerelles du VLAN 50… mais avec celles du VLAN 51 si un jour il est routé. D'où 150, choisi et documenté.

**En production chez MédiSphère**
Trois contrôleurs (dont la passerelle) sur trois serveurs physiques dans des alimentations et commutateurs distincts ; `keepalived_traffic_mode: unicast` ; essai de panne trimestriel (un contrôleur arrêté brutalement) avec ces mêmes mesures, consigné ; alertes sur la taille du cluster Galera et le nombre de membres Raft d'OVN (module 21).

---

### M10-E25 — Sauvegarder et restaurer OpenStack

**Solution**

Fichiers : [`globals.d/25-sauvegarde.yml`](fichiers/M10-E25/openstack/etc/kolla/globals.d/25-sauvegarde.yml) ; rôle [`openstack_mariabackup`](fichiers/M10-E25/ansible/roles/openstack_mariabackup/) (unités de `adm01`) et [`host_vars/adm01/openstack_mariabackup.yml`](fichiers/M10-E25/ansible/inventories/lab/host_vars/adm01/openstack_mariabackup.yml) ; rôle [`sauvegarde_pbs`](fichiers/M10-E25/ansible/roles/sauvegarde_pbs/) de M06-E28 **complet**, étendu (élément `openstack` dans [`files/wb-backup-socle.sh`](fichiers/M10-E25/ansible/roles/sauvegarde_pbs/files/wb-backup-socle.sh), variables `sauvegarde_pbs_os_*`, script de vérification [`preparer-sauvegarde.sh`](fichiers/M10-E25/openstack/outils/preparer-sauvegarde.sh)) ; [`host_vars/osctl01/sauvegarde_pbs.yml`](fichiers/M10-E25/ansible/inventories/lab/host_vars/osctl01/sauvegarde_pbs.yml), [modèle Vault](fichiers/M10-E25/ansible/inventories/lab/host_vars/osctl01/vault-sauvegarde.yml.exemple), [`playbooks/sauvegardes.yml`](fichiers/M10-E25/ansible/playbooks/sauvegardes.yml), [extrait de `pare_feu.yml`](fichiers/M10-E25/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; [`pbs01/pbs-jeton-openstack.sh`](fichiers/M10-E25/pbs01/pbs-jeton-openstack.sh) ; documentation [`sauvegarde-restauration.md`](fichiers/M10-E25/medisphere/docs/cloud/sauvegarde-restauration.md) et [`tests/restauration.md`](fichiers/M10-E25/medisphere/docs/cloud/tests/restauration.md).

*1. Ce qui fait l'état* : tableau §1 de `sauvegarde-restauration.md`. Le point clé de la lecture : **Neutron fait foi**, OVN est une projection de la base Neutron ; `neutron-ovn-db-sync-util` (modes `log` et `repair`) réécrit les bases OVN à partir de Neutron. On ne sauvegarde donc pas les bases OVN : on sauvegarde Neutron.

*2. Activer* :

```
admin@adm01:~/src/openstack$ uv run kolla-ansible reconfigure -i inventaire/multinode --configdir etc/kolla -t mariadb
admin@adm01:~/src/openstack$ time uv run kolla-ansible mariadb-backup -i inventaire/multinode --configdir etc/kolla --full
root@osctl01:~# MP=$(docker volume inspect -f '{{.Mountpoint}}' mariadb_backup); cat "$MP/last_full_file"; du -sh "$MP"/full-*
```

La sous-commande s'appelle `mariadb-backup` (avec un tiret) dans Kolla-Ansible 22.x ; `--full` est la valeur par défaut, `--incremental` l'autre choix. Elle lance un conteneur jetable `mariabackup` sur le nœud MariaDB, avec la même image que le conteneur `mariadb`. Le fichier : `full-<JJ-MM-AAAA-epoch>/mysqlbackup-<…>.qp.xbc.xbs.gz`, quelques dizaines de Mo compressés pour un cloud neuf. Impact sur les API : aucun mesurable (sauvegarde à chaud, verrou bref en fin de copie).

*3. `adm01`* : rôle `openstack_mariabackup`. Le service tourne en `admin` dans `~/src/openstack` : `kolla-ansible` charge **toujours** `passwords.yml` (`-e @…/passwords.yml`), même pour une sauvegarde qui n'en a pas besoin ; l'`ansible.cfg` du projet fournit l'identité `critique` par le script client `outils/vault-pass-client.sh`, qui lit le mot de passe dans `~/.config/workbook/ansible-vault-critique.pass` (600). L'unité le redit explicitement (`ANSIBLE_VAULT_IDENTITY_LIST`, même valeur) pour ne pas dépendre du dossier courant. Rien de secret dans l'unité. Deuxième piège, plus sournois : la **connexion SSH** de Kolla à 01:30. Les certificats d'utilisateur de 16 h (M06-E20) auront expiré : d'où une clé dédiée sans phrase (`~/.ssh/kolla-auto`, `ANSIBLE_PRIVATE_KEY_FILE`), autorisée sur les nœuds pour le seul compte de déploiement, restreinte par `from="10.10.10.10"` dans `authorized_keys`.

```
admin@adm01:~$ sudo systemd-analyze verify /etc/systemd/system/wb-openstack-mariabackup.service
admin@adm01:~$ sudo systemctl start wb-openstack-mariabackup.service && systemctl show -p Result wb-openstack-mariabackup.service
```

*4. Envoyer à PAR2* : décisions de l'élément `openstack` :
- **fichier de sauvegarde** : oui, après `gzip -t` (une archive tronquée envoyée chaque nuit est pire que pas de sauvegarde : on y croit) ;
- **image MariaDB** (nom et identifiant) et **empreintes de toutes les images** : oui, quelques Ko ; sans elles, on ne sait pas avec quelle version de `mariabackup` préparer ;
- **clés Fernet** : oui, chiffrées dans l'archive ; utiles seulement dans les trois jours (fenêtre de rotation), elles évitent de déconnecter tout le monde après une reconstruction rapide ;
- **`/etc/kolla` généré** : **non** : il contient tous les mots de passe en clair et se régénère depuis le dépôt.

Puis jeton PBS (`pbs-jeton-openstack.sh` sur `pbs01`), clé de chiffrement créée sur `adm01` (`proxmox-backup-client key create /tmp/pbs-osctl01.key --kdf none`, *paperkey*, copie hors ligne, Vault, `shred -u`), flux, pipeline de `plateforme/ansible` (`playbooks/sauvegardes.yml --limit osctl01,adm01`). Vérification du catalogue :

```
root@osctl01:~# set -a; . /etc/wb-backup/pbs-osctl01.env; set +a
root@osctl01:~# proxmox-backup-client snapshot list host/osctl01 --ns par1/openstack
root@osctl01:~# proxmox-backup-client catalog dump host/osctl01/<HORODATAGE> --ns par1/openstack --keyfile /etc/wb-backup/pbs-osctl01.key
```

*5-6. Restauration* : `sauvegarde-restauration.md` §3. La préparation (`preparer-sauvegarde.sh preparer`) se fait **avant** d'arrêter MariaDB : elle prend une minute et ne touche à rien ; si elle échoue, on n'a rien cassé. Résultat attendu : services `up` en quelques minutes ; `essai-restauration` absent ; tout ce qui précède la sauvegarde présent.

*7. Orphelins* :

```
admin@adm01:~$ openstack --os-cloud medisphere-admin volume list --all-projects -f value -c ID | sed 's/^/volume-/' | sort > /tmp/cinder
admin@adm01:~$ ssh ceph01 sudo cephadm shell -- rbd ls volumes 2>/dev/null | sort > /tmp/rbd
admin@adm01:~$ comm -13 /tmp/cinder /tmp/rbd            # volume-<id-de-essai-restauration-vol>
[root@ceph01 ~]# cephadm shell -- rbd info volumes/volume-<ID>      # taille 1 Gio, date de création après la sauvegarde
[root@ceph01 ~]# cephadm shell -- rbd snap ls volumes/volume-<ID>   # aucun instantané (sinon : purge d'abord)
[root@ceph01 ~]# cephadm shell -- rbd rm volumes/volume-<ID>
```

Trace dans le compte rendu (identifiant, taille, date, décision). Méthode générale : §6 du document.

**Explications**

Mariabackup copie les fichiers InnoDB à chaud en suivant le journal de reprise (*redo log*), puis la phase `--prepare` rejoue ce journal pour obtenir des fichiers cohérents : c'est pour cela qu'une sauvegarde **non préparée** n'est pas restaurable, et qu'il faut la même version de l'outil. La restauration remplace tout le répertoire de données : elle ramène **tous** les services au même instant, ce qui est cohérent pour le plan de contrôle… mais pas avec le monde extérieur (Ceph, hyperviseurs, OVN) qui, lui, a continué. D'où la réconciliation, systématique.

**Alternatives**
- `mysqldump` par base (`--single-transaction`) : restauration sélective d'un service (Keystone seul) possible, mais plus lent et sans incrémentales ; utile en complément pour « récupérer un projet supprimé » sans tout remonter.
- Instantanés Proxmox de `osctl01` (PBS) : restaurent tout le nœud, y compris des états incohérents si la VM n'est pas arrêtée proprement ; bon filet, mauvaise sauvegarde de base.
- Réplication Galera vers un nœud à PAR2 : continuité, pas sauvegarde (une suppression se réplique aussi).

**Pièges classiques**
- Croire que Kolla purge : le volume `mariadb_backup` remplit `/var/lib/docker` en quelques semaines (et c'est alors MariaDB qui s'arrête).
- Sauvegarder sans jamais préparer : on découvre le jour J que l'image a changé (mise à jour E28) et que la sauvegarde ne se prépare plus avec la nouvelle version.
- Restaurer sans instantané des trois nœuds, ou sans noter l'heure de la sauvegarde (RPO inconnu).
- Supprimer l'image RBD orpheline sans vérifier qu'aucun volume ne la référence, ou sans prévenir le projet (c'étaient peut-être des données).
- Laisser `/backup/restore` après coup : une copie complète de la base, lisible par root sur le nœud.

**En production chez MédiSphère**
Incrémentales horaires et complète quotidienne ; test de restauration trimestriel sur un environnement isolé (pas en production) ; contrôle automatique `preparer-sauvegarde.sh verifier` chaque semaine avec alerte ; `mysqldump` de Keystone en plus (restauration fine des identités) ; Cinder Backup vers un stockage objet hors du cluster Ceph (F5).

---

### M10-E26 — Superviser OpenStack

**Solution**

Fichiers (projet `plateforme/outils`) : [`bin/ms-verif-openstack`](fichiers/M10-E26/outils/bin/ms-verif-openstack), [`etc/ms-verif-openstack.conf`](fichiers/M10-E26/outils/etc/ms-verif-openstack.conf), [tests bats](fichiers/M10-E26/outils/tests/bats/ms-verif-openstack.bats) (15 tests, dont un rouge par domaine), [unités](fichiers/M10-E26/outils/systemd/), [extrait du Taskfile](fichiers/M10-E26/outils/Taskfile-install-extrait.yml), [extrait du guide d'astreinte](fichiers/M10-E26/outils/docs/astreinte-openstack-extrait.md) ; identité : [`creer-identite-supervision.sh`](fichiers/M10-E26/adm01/creer-identite-supervision.sh), [règles d'accès](fichiers/M10-E26/adm01/regles-acces-supervision.json), [extrait de `clouds.yaml`](fichiers/M10-E26/adm01/clouds.yaml.extrait).

*1. Lecture.* Une application credential est attachée à un utilisateur **et** un projet, porte un sous-ensemble des rôles de l'utilisateur, une expiration facultative, et des **règles d'accès** facultatives : liste de `{service, method, path}` ; toute requête qui ne correspond à aucune règle est refusée par le service lui-même (le jeton porte les règles). Par défaut il est *restreint* (`unrestricted: false`) : il ne peut pas créer d'autres application credentials ni de fiducies. `openstack --debug compute service list` montre deux appels au service `compute` : la découverte de version (`GET /` ou `GET /v2.1/`) puis `GET /v2.1/os-services`. Une règle limitée à `/v2.1/os-services` casse la découverte : d'où `path: "/**"` avec `method: GET`, qui revient à « lecture seule sur ce service ».

*2. L'identité.* Les politiques par défaut de Nova 2026.1 réservent `os-services` aux administrateurs (le rôle `reader` du projet ne suffit pas, et la portée « système » n'est plus la voie retenue par Nova). Compromis : `svc-supervision` reçoit `admin` sur le projet `admin`, mais son application credential n'autorise que `GET` sur `compute`, `network`, `volumev3`/`block-storage`, `load-balancer`. Preuve d'écriture refusée, sans effet :

```
admin@adm01:~$ openstack --os-cloud medisphere-supervision server list --all-projects -f value -c Name | head -3   # lit
admin@adm01:~$ openstack --os-cloud medisphere-supervision network create essai-interdit                           # HTTP 403/401 : refusé
admin@adm01:~$ openstack --os-cloud medisphere-admin network list --name essai-interdit -f value | wc -l             # 0
```

Registre des secrets : identifiant `supervision-adm01`, emplacement `~/.config/openstack/secure.yaml` (600), portée (GET sur cinq services, tous projets), propriétaire équipe Plateforme, échéance (expiration à un an, à ajouter avec `--expiration`), risque accepté : un voleur du secret lit tout l'inventaire du cloud, sans pouvoir le modifier.

*3. Journaux* : `/var/log/kolla/<service>/` sur chaque nœud (lien vers le volume `kolla_logs`), écrits par les services eux-mêmes ; `fluentd` (conteneur présent même sans journalisation centrale) les lit et les transmettrait à OpenSearch si `enable_central_logging` était actif ; la rotation est assurée par le conteneur `cron` (logrotate de Kolla). M22 : Grafana Alloy ou la sortie de fluentd vers Loki, à décider alors.

*4-5.* Script et unités : fichiers. Le durcissement de M06-E29 s'applique, avec deux adaptations : `ProtectHome=read-only` (la sonde lit `~/.config/openstack` et `~/.ssh`) et un `XDG_CACHE_HOME` en `/tmp` privé (la CLI écrit un cache).

*6. Le rouge* (exemples, tous réversibles) :

| Domaine | Provocation | Retour |
|---|---|---|
| Certificats | *drop-in* `seuil-absurde.conf` | suppression du *drop-in*, `daemon-reload` |
| Calcul | `docker stop nova_compute` sur `oscmp02`, attendre 90 s | `docker start nova_compute` |
| Calcul (raison) | `openstack compute service set --disable oscmp02 nova-compute` (sans raison) | `--enable` |
| Réseau | `docker stop ovn_controller` sur `oscmp01` 2 min (le trafic continue : flux déjà programmés) | `docker start` |
| Octavia | répartiteur d'essai dont le membre a une adresse inexistante → `OFFLINE`/`ERROR` | suppression |
| Nœuds | `docker stop cron` sur un nœud | `docker start cron` |

**Explications**

Une sonde « de service » interroge ce que voit l'utilisateur ou l'ordonnanceur (Nova croit-il ce calcul vivant ?), pas seulement ce que voit `systemctl`. Les deux sont complémentaires : un conteneur `healthy` dont le service n'est pas enregistré, ou un service `up` dont le conteneur redémarre en boucle, sont deux pannes distinctes.

**Alternatives**
- `kolla-ansible check` (état des conteneurs, lancé depuis l'hôte de déploiement) : utile à la main, trop lourd pour toutes les 15 minutes et sans contrôle fonctionnel.
- `openstack-exporter` + Prometheus (`enable_prometheus_openstack_exporter`) : la cible du module 21.
- Rôle `reader` et une politique personnalisée pour `os-services` (surcharge `nova/policy.yaml` dans `etc/kolla/config/`) : plus propre en droits, mais une politique maison à maintenir à chaque montée de version.

**Pièges classiques**
- Une application credential sans règles d'accès pour la sonde : c'est un administrateur complet stocké en clair dans un fichier de `adm01`.
- Des règles d'accès trop étroites qui cassent la découverte de version : la sonde échoue toujours, on finit par l'ignorer.
- `docker ps` sans `sudo -n` : la commande échoue, la sortie est vide… et « aucun conteneur malade » devient un faux succès (la sonde le traite en `KO`).
- Oublier les services désactivés : un calcul « désactivé pour maintenance » depuis trois mois réduit la capacité sans que personne ne le voie (d'où la règle « désactivé avec raison »).

**En production chez MédiSphère**
La sonde reste comme contrôle de bout en bout (synthétique) une fois Prometheus en place ; le guide d'astreinte est relu après chaque incident ; l'identifiant de la sonde expire et se renouvelle par une procédure écrite.

---

### M10-E27 — Sécuriser OpenStack

**Solution**

Fichiers (projet `plateforme/openstack`) : [`globals.d/27-securite.yml`](fichiers/M10-E27/openstack/etc/kolla/globals.d/27-securite.yml), [`config/keystone.conf`](fichiers/M10-E27/openstack/etc/kolla/config/keystone.conf), [`config/horizon/_9999-custom-settings.py`](fichiers/M10-E27/openstack/etc/kolla/config/horizon/_9999-custom-settings.py), [`certificates/ca/`](fichiers/M10-E27/openstack/etc/kolla/certificates/ca/LISEZMOI.md), [`outils/dispenser-comptes-service.sh`](fichiers/M10-E27/openstack/outils/dispenser-comptes-service.sh), [`outils/verifier-tls-vip.sh`](fichiers/M10-E27/openstack/outils/verifier-tls-vip.sh) ; [extrait de `pare_feu.yml`](fichiers/M10-E27/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; [`docs/cloud/securite.md`](fichiers/M10-E27/medisphere/docs/cloud/securite.md).

*Ordre d'application* (une fenêtre, instantané des trois nœuds) :
1. `outils/dispenser-comptes-service.sh` (avant toute politique de verrouillage) : comptes de service de Kolla, `svc-tofu` (E15) et `svc-supervision` (E26) ;
2. MR avec `27-securite.yml`, `keystone.conf`, `_9999-custom-settings.py`, la racine dans `certificates/ca/medisphere-root-ca.crt` ; retrait de `certificates/haproxy.pem` (chiffré, posé à la main en M10-E04) du dépôt **après** le premier certificat ACME servi (tant que lego n'a rien obtenu, HAProxy garde le fichier déjà copié sur le nœud) ;
3. flux : `ca01` → VIP:80, `osctl01` → `ca01:443` (pipeline de `plateforme/ansible`, `gw01` puis `gw02`) ;
4. `uv run kolla-ansible reconfigure -i inventaire/multinode --configdir etc/kolla` (toutes les configurations changent : URL internes, confiance, base en TLS) ;
5. `uv run kolla-ansible post-deploy …` (nouveau `admin-openrc.sh`) ; `clouds.yaml` : rien à changer pour l'interface `public` ; ajouter `cacert` si absent ;
6. vérifications : `outils/verifier-tls-vip.sh`, `openstack endpoint list --interface internal`, `ms-verif-openstack` (ajouter `openstack-int…:5000` à ses points TLS).

*2. Effets de bord.* Dans les valeurs par défaut de Kolla, `database_enable_tls_internal` vaut `yes` dès que le TLS interne **et** ProxySQL sont actifs : les services parlent alors à ProxySQL en TLS. C'est voulu, mais c'est une source classique de panne générale si la confiance (`openstack_cacert`, copie de la racine) n'est pas en place **dans le même** `reconfigure`. Restent en clair : RabbitMQ, *backend* HAProxy → services, migration libvirt, bases OVN, Ceph (authentifié, non chiffré) : tableau §2 de `securite.md`.

*3. ACME.* Rôle `letsencrypt` de Kolla : conteneur `letsencrypt_lego` (client lego, `cron` toutes les 4 h, journal `/var/log/kolla/letsencrypt/letsencrypt-lego.log`) et `letsencrypt_webserver` (sert `/.well-known/acme-challenge/` derrière HAProxy, port 80 des VIP), certificats poussés dans HAProxy par SSH (`haproxy_ssh`). Deux détails décisifs :
- `letsencrypt_cert_valid_days: "15"` : lego renouvelle quand il reste **moins** de N jours ; avec 30 (défaut) et des certificats de 30 jours, il renouvellerait à chaque passage — six certificats par jour et par VIP, au mépris de la politique de M06-E27 ;
- `enable_letsencrypt: "yes"` en **chaîne** : un gabarit d'HAProxy compare la valeur à `'yes'` pour laisser passer les défis sans redirection vers HTTPS.

Preuve du premier renouvellement : `verifier-tls-vip.sh` avant/après (dates et empreinte), ou forcer en abaissant temporairement le seuil à 30 et en relançant la tâche (`docker exec letsencrypt_lego …` : lis la crontab du conteneur pour la commande exacte), puis remettre 15.

*4.* Verrouillage :

```
admin@adm01:~$ openstack --os-cloud medisphere-admin user create --domain medisphere --password-prompt essai-verrou
admin@adm01:~$ openstack --os-cloud medisphere-admin role add --user essai-verrou --user-domain medisphere --project plateforme --project-domain medisphere reader
admin@adm01:~$ for i in 1 2 3 4 5 6; do OS_PASSWORD=faux openstack --os-auth-url https://openstack.par1.medisphere.internal:5000/v3 \
                 --os-username essai-verrou --os-user-domain-name medisphere --os-project-name plateforme \
                 --os-project-domain-name medisphere token issue >/dev/null 2>&1; echo "essai $i : $?"; done
```

(Le faux mot de passe passe par l'environnement d'une seule commande, jamais un vrai secret.) Puis le **bon** mot de passe est refusé pendant 15 minutes (journal de Keystone : *account is locked*). Suppression du compte. Horizon : `SESSION_TIMEOUT = 1800` (posé en E17) n'est qu'un délai d'inactivité tant que `SESSION_REFRESH` vaut `True` (défaut) ; `SESSION_REFRESH = False` en fait une limite absolue, et `SESSION_EXPIRE_AT_BROWSER_CLOSE = True` supprime le cookie à la fermeture du navigateur. Le fichier `_9999-custom-settings.py` de E17 est **complété**, pas remplacé : le domaine par défaut (`OPENSTACK_KEYSTONE_DEFAULT_DOMAIN`) y reste.

*5. Cloisonnement* : depuis `secu-essai01` (IP flottante, groupe SSH depuis MGMT) :

```
debian@secu-essai01:~$ timeout 5 bash -c 'exec 3<>/dev/tcp/10.10.50.200/5000' && echo OUVERT || echo fermé
debian@secu-essai01:~$ timeout 5 bash -c 'exec 3<>/dev/tcp/10.10.50.51/3306' && echo OUVERT || echo fermé
debian@secu-essai01:~$ curl -sI https://deb.debian.org | head -1
root@gw01:~# nft list ruleset | grep -c nft-fwd-drop ; journalctl -k --since -5min | grep nft-fwd-drop | grep 10.10.52.
```

*6. Rotation* : `securite.md` §5. `kolla-genpwd` ne remplit que les clés **vides** : vider précisément celles à faire tourner. L'ancien mot de passe d'`admin` est refusé ; `glance image list` fonctionne (le nouveau mot de passe de base est posé par `reconfigure` : Kolla met à jour l'utilisateur MariaDB et la configuration de Glance).

**Explications**

Le TLS interne protège le trafic entre clients internes (services, CLI de `adm01`, OpenTofu) et la VIP interne ; l'externe protège les utilisateurs. Sans TLS *backend*, HAProxy → service reste en clair, mais sur le même nœud (un contrôleur) : le gain du *backend* ne vaut sa complexité qu'à trois contrôleurs. ACME automatise ce qu'un humain oublierait ; la politique de durées de M06-E27 (30 jours, renouvellement à 15) s'applique au cloud comme au socle.

**Alternatives**
- Certificats obtenus sur `adm01` par DNS-01 (API de PowerDNS) et poussés par `reconfigure -t loadbalancer` : ne dépend pas d'un flux entrant vers les VIP ; plus de pièces à maintenir.
- `kolla_externally_managed_cert` avec un agent (`step ca renew --daemon`) sur `osctl01` : Kolla ne touche plus aux certificats ; il faut alors recharger HAProxy soi-même.
- Pare-feu sur les nœuds eux-mêmes : Kolla ne gère que firewalld pour les ports externes ; avec Docker qui écrit ses propres règles, un pare-feu d'hôte maison est délicat : filtrer à la bordure (inter-VLAN) est plus sûr.

**Pièges classiques**
- Activer le verrouillage avant de dispenser les comptes de service : une erreur de mot de passe pendant une rotation verrouille `nova` ou `neutron`, et tout le cloud s'arrête 15 minutes… puis recommence.
- `kolla_copy_ca_into_containers` sans `openstack_cacert` : certains clients Python ignorent le magasin du système.
- Oublier `kolla_admin_openrc_cacert` : `admin-openrc.sh` ne marche plus en TLS interne.
- Racine **privée** ou clé d'HAProxy dans le dépôt : seul le certificat public de la racine va dans `certificates/ca/`.
- Tester le cloisonnement depuis `adm01` : il est en MGMT, autorisé ; le test se fait depuis une instance.
- Faire tourner `rabbitmq_password` « pour voir » : arrêt de tous les services et destruction des volumes RabbitMQ (procédure *Password Rotation*).

**En production chez MédiSphère**
Fédération Keycloak (module 24) pour les humains, plus de mots de passe locaux hors bris de glace ; RabbitMQ et libvirt en TLS dès trois contrôleurs ; scan de configuration (module 26) ; revue annuelle de `securite.md` par la RSSI, risques acceptés signés et datés.

---

### M10-E28 — Mettre à jour OpenStack

**Solution**

Fichiers : [`outils/photographier-images.sh`](fichiers/M10-E28/openstack/outils/photographier-images.sh) (`plateforme/openstack`) ; [RB-101](fichiers/M10-E28/medisphere/docs/cloud/runbooks/RB-101-mettre-a-jour-openstack.md) ; [CHG-1154](fichiers/M10-E28/medisphere/docs/cloud/changements/CHG-1154-mise-a-jour-2026.1.md).

*La procédure.* La page *Operating Kolla* le dit en tête de *Upgrade procedure* : la procédure décrite (avec `kolla-ansible upgrade`) est celle d'une **montée de série** ; **au sein d'une série**, il suffit en général de mettre à jour le paquet `kolla-ansible`, de télécharger les images (`pull`) et de relancer **`kolla-ansible deploy`**. C'est ce que fait RB-101.

```
admin@adm01:~/src/openstack$ uv lock --upgrade-package kolla-ansible && uv sync --frozen
admin@adm01:~/src/openstack$ uv run kolla-ansible install-deps
admin@adm01:~/src/openstack$ outils/photographier-images.sh ~/medisphere/docs/cloud/changements/CHG-1154-avant.tsv
admin@adm01:~/src/openstack$ uv run kolla-ansible prechecks -i inventaire/multinode --configdir etc/kolla
admin@adm01:~/src/openstack$ uv run kolla-ansible pull -i inventaire/multinode --configdir etc/kolla
admin@adm01:~/src/openstack$ outils/photographier-images.sh --perimes
```

`--perimes` liste les conteneurs dont l'image ne correspond plus à celle que désigne l'étiquette : c'est exactement ce que `deploy` recréera. Fenêtre : `deploy`, vérifications, photographie après, comparaison. Si tu étais déjà sur la dernière 22.x publiée, `uv lock` ne change rien et seul le `pull` apporte des images nouvelles : la fiche le dit.

*Interruption.* Avec un seul contrôleur, deux redémarrages coupent les API : MariaDB (1 à 2 min) et RabbitMQ (2 min + reconnexions) ; les API elles-mêmes, recréées une à une, donnent des erreurs ponctuelles. Le plan de données subit au plus des coupures de quelques secondes au redémarrage d'`openvswitch_vswitchd` (passerelle et calculs). L'effet de la recréation de `nova_libvirt` sur les instances en marche est à **mesurer** (CHG-1154 §3) : c'est l'un des points que la photographie et la mesure de continuité prouvent.

*Retour arrière.* RB-101 §6. Les instantanés `avant-maj` des trois nœuds sont le filet ; les anciennes images, conservées jusqu'à la clôture, permettent un retour plus fin (retag + `deploy-containers`). `kolla-ansible prune-images` supprime les images Kolla qui ne sont plus utilisées par un conteneur : après clôture seulement.

**Explications**

L'étiquette `2026.1-debian-trixie` est mobile : Kolla reconstruit et republie les images de la branche stable. Deux nœuds qui font `pull` à une semaine d'intervalle n'ont pas les mêmes images sous la même étiquette ; un `pull` sans `deploy` laisse les conteneurs sur l'ancienne image (ils ont été créés avec un **identifiant** d'image, pas une étiquette). Le check de l'exercice repose sur cette différence. Pour maîtriser ce qui tourne, la production utilise un registre local avec des étiquettes immuables (`openstack_tag_suffix`, ou un registre miroir et un `openstack_tag` daté).

**Alternatives**
- `kolla-ansible upgrade` pour une mise à jour mineure : fonctionne en général (il fait plus : migrations de schémas, ordre strict), mais ce n'est pas la procédure documentée pour ce cas, et il est plus long.
- Mise à jour service par service (`deploy -t nova`) : réduit le périmètre, mais l'ordre des dépendances devient ton problème ; utile pour un correctif ciblé urgent.
- Construire ses propres images (Kolla, `kolla-build`) : contrôle total (paquets, correctifs), coût de maintenance élevé.

**Pièges classiques**
- `pull` sans `deploy` : on croit avoir mis à jour, rien n'a changé.
- `--limit` sur une mise à jour : documentation explicite, bogues connus (Nova).
- `prune-images` le jour même : le retour arrière rapide disparaît.
- Une mise à jour d'ansible-core au-delà de 2.20 dans le même `uv lock` : Kolla 2026.1 refuse ≥ 2.21 (contrainte du projet à garder dans `pyproject.toml`).
- Fusionner la MR avant la fenêtre : le prochain pipeline ou le prochain `deploy` de quelqu'un d'autre fait le changement hors fenêtre.

**En production chez MédiSphère**
Registre Harbor (module 13) avec copie datée des images Kolla, analyse de vulnérabilités, signature ; environnement de recette Kolla qui reçoit chaque mise à jour une semaine avant ; mise à jour mensuelle planifiée ; trois contrôleurs pour une interruption des API de quelques secondes.

---

### M10-E29 — Ajouter et retirer un nœud de calcul

**Solution**

Fichiers : [`outils/vider-noeud-calcul.sh`](fichiers/M10-E29/openstack/outils/vider-noeud-calcul.sh) (`plateforme/openstack`), [RB-102](fichiers/M10-E29/medisphere/docs/cloud/runbooks/RB-102-evacuer-un-noeud-de-calcul.md) (procédure complète, historique).

*1. Capacité* : `vider-noeud-calcul.sh -n oscmp02 "…"`. Avec deux `m1.petit` par calcul et ≈ 5,8 Gio allouables par calcul (≈ 7,8 Gio vus par Nova − 2 048 Mio réservés en E20, ratio 1.0), `oscmp01` absorbe sans peine les instances d'essai (4 Gio). Mais la **mémoire réelle** de la VM `oscmp01` (`free -m`) compte aussi : QEMU ajoute ~10 % par instance, et la VM imbriquée elle-même a besoin de mémoire pour les conteneurs Kolla.

*3. Vider* : le script désactive avec raison, puis `openstack server migrate --live-migration --wait` pour chaque instance (sans hôte cible : l'ordonnanceur vérifie la capacité). Avec Ceph, seule la mémoire est copiée : la coupure mesurée est de l'ordre de la centaine de millisecondes (quelques paquets perdus).

*4. Sortir* : `kolla-ansible stop … --yes-i-really-really-mean-it --limit oscmp02`, inventaire par MR, suppression des agents réseau et du service de calcul (`--os-compute-api-version 2.53` : identifiants UUID des services). La suppression du service supprime le fournisseur de ressources de Placement **s'il n'a plus d'allocations** ; le châssis OVN disparaît avec la suppression de l'agent « OVN Controller » (sinon `ovn-sbctl chassis-del`).

*5. Réintégrer* : `bootstrap-servers`, `pull`, `deploy` limités à `oscmp02` (la documentation autorise `--limit` pour un **calcul** ajouté ; ce n'est pas le cas pour les contrôleurs). Kolla découvre le nouvel hôte dans la cellule pendant `deploy`. Un seul fournisseur `oscmp02` doit exister. Puis `--enable` et migration de `evac-essai02` vers `oscmp02` (`--host oscmp02`).

**Explications**

Nova distingue la **migration** (l'instance tourne, l'hôte source est vivant) et l'**évacuation** (l'hôte est mort : l'instance redémarre ailleurs à partir de son disque). Avec un stockage partagé (Ceph), les deux sont rapides, mais l'évacuation est un redémarrage et exige d'être **sûr** que l'hôte est mort (sinon deux QEMU écrivent le même disque). Placement suit les ressources par fournisseur ; un fournisseur orphelin du même nom empêche le nouvel `nova-compute` de s'enregistrer proprement (conflit de nom), d'où le soin du nettoyage.

**Alternatives**
- Ne pas retirer le nœud d'OpenStack pour une intervention courte : désactiver, vider, arrêter la VM, redémarrer, réactiver. Plus simple ; c'est le bon choix pour un redémarrage de noyau. Le retrait complet se justifie pour un remplacement long ou un changement d'identité.
- Watcher (stratégies de consolidation, de maintenance) : automatise le vidage.

**Pièges classiques**
- `kolla-ansible stop` sans `--limit` : arrêt de tout le cloud.
- `bootstrap-servers` sans `--limit` sur une plateforme en service : redémarrage possible de Docker sur tous les nœuds.
- Supprimer le service de calcul **avant** d'avoir vidé : instances orphelines (l'hôte n'existe plus pour Nova), à évacuer.
- Oublier la réactivation : le nœud est sain, rien n'y va.
- Évacuer un calcul simplement isolé (RabbitMQ, horloge) : doublon d'instance sur le même disque Ceph, corruption.

**En production chez MédiSphère**
Agrégats d'hôtes (recette / production) pour vider sans toucher aux instances de production ; Masakari ou un *fencing* par l'iLO avant toute évacuation automatique ; RB-102 rejoué à chaque maintenance, historique tenu.

---

### M10-E30 — ADR : choix réseau et répartiteurs

**Modèle de réponse** : [`ADR-0100-reseau-ovn-et-repartiteurs.md`](fichiers/M10-E30/medisphere/docs/cloud/adr/ADR-0100-reseau-ovn-et-repartiteurs.md).

**Ce que la correction regarde**

| Critère | Attendu |
|---|---|
| Forme | ADR du dépôt (contexte, facteurs, options, décision, conséquences, statut, date, décideurs) ; une ADR pour deux décisions liées, avec la raison |
| Options réseau | ML2/OVN, ML2/OVS (agents L3/DHCP, ou DVR) ; mention du **retrait** de Linux Bridge (une option qui n'existe plus n'est pas une option) |
| Options répartiteurs | fournisseur OVN, amphora, pas d'Octavia |
| Limites du fournisseur OVN | L4 (TCP, UDP, SCTP), **`SOURCE_IP_PORT` seul**, pas de terminaison TLS, pas de L7, adresse **source préservée** (pas de SNAT), contrôles de santé TCP/UDP-CONNECT/SCTP (pas HTTP) |
| Coût d'amphora | une VM par répartiteur (deux en actif/passif), image, réseau de gestion, certificats, sur des calculs de 8 Go |
| Faits sourcés | E16, E24 (continuité est-ouest sans contrôleur, nord-sud coupé), E31 (groupes de sécurité et adresse cliente), documentation |
| Conséquences pour les équipes | ce que Julien ne peut pas demander, comment contourner |
| Conditions de révision | mesurables (nombre de demandes L7/TLS, capacité, exigence réglementaire), effort de retour arrière évalué |

**Pièges classiques**
- Comparer sur la popularité (« amphora, c'est ce que tout le monde utilise ») sans critère.
- Oublier que le fournisseur OVN n'existe qu'avec ML2/OVN : les deux décisions ne sont pas indépendantes.
- Affirmer des performances non mesurées.
- Des conditions de révision vagues (« si le besoin évolue »).

---

### M10-E31 — Le libre-service pour MédiAgenda

**Solution de référence**

Fichiers : module [`openstack-env-app`](fichiers/M10-E31/tofu-modules/openstack-env-app/) (`plateforme/tofu-modules`, validé par `tofu validate` avec le provider 3.4) ; dépôt de l'équipe [`recette-infra`](fichiers/M10-E31/recette-infra/) (`mediagenda/recette-infra` : `versions.tf`, `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`, `.gitlab-ci.yml`) ; [`docs/cloud/libre-service.md`](fichiers/M10-E31/medisphere/docs/cloud/libre-service.md).

*Mise en place côté plateforme* (une fois par équipe, idéalement dans l'état OpenTofu des projets de E15 et dans RB-100) :
1. groupe GitLab `mediagenda`, projet `recette-infra`, Julien *Maintainer* ; `plateforme/tofu-modules` autorise ce projet dans sa liste d'accès par jeton de job (*CI/CD job token allowlist*) ;
2. compartiment S3 `tofu-state-mediagenda` et identité SeaweedFS `tofu-mediagenda` limitée à ce compartiment (actions `Read`, `Write`, `List`, `Tagging` sur lui seul) ; les identités de la plateforme n'ont pas à y accéder, et réciproquement ;
3. compte de service `svc-ci-mediagenda` (domaine `Default`, comme tous les comptes de service ; rôle `member` sur `mediagenda-dev` seulement : RB-100, étape « accès CI ») ; application credential **créée en tant que lui** (variables `OS_*` d'un seul shell, mot de passe lu par `read -s`), avec expiration :
   ```
   admin@adm01:~$ openstack application credential create recette-infra-ci --role member --expiration 2027-10-31T00:00:00
   ```
   secret transmis directement dans la variable masquée du projet GitLab (jamais par courriel ni ticket) ;
4. variables du projet GitLab (liste en tête du `.gitlab-ci.yml`), protégées, branche `main` protégée.

*Conception du module.* Ce que l'équipe choisit (préfixe, plage, nombre et taille, page, clients, accès d'administration temporaire) est variable, avec validations ; ce que la plateforme impose (fournisseur OVN, aucun port ouvert à tous, pas d'IP flottante sur les instances, anti-affinité souple, étiquettes) ne l'est pas. Trois choix techniques à retenir :
- **groupes de sécurité et OVN** : port 80 ouvert aux **clients** (`clients_http`) et au **sous-réseau** des membres (les contrôles de santé du fournisseur OVN partent d'une adresse de ce sous-réseau) ; ouvrir seulement au sous-réseau donne un répartiteur `ONLINE` et des clients sans réponse ;
- **volume attaché au démarrage** (`block_device`, `boot_index = -1`) : cloud-init le trouve au premier démarrage ; il est formaté une seule fois et monté par UUID, retrouvé par son numéro de série (identifiant Cinder) ;
- **accès d'administration** : pas d'IP flottante permanente ; `acces_admin = true` par MR crée une IP flottante temporaire sur la première instance, SSH limité à MGMT et au VPN.

*Preuves* :

```
admin@adm01:~$ for i in $(seq 20); do curl -s http://<IP-FLOTTANTE>/ | grep -o 'agenda-recette-app0[0-9]'; done | sort | uniq -c
admin@adm01:~$ openstack --os-cloud medisphere-admin loadbalancer status show agenda-recette-lb
admin@adm01:~$ timeout 4 bash -c 'exec 3<>/dev/tcp/<IP-FLOTTANTE>/22' || echo "22 fermé : attendu"
```

`SOURCE_IP_PORT` : chaque nouvelle connexion de `curl` a un port source différent, la répartition est donc aléatoire mais touche les deux instances sur 20 requêtes.

*Reproductibilité* : pipeline `detruire` (variable `DETRUIRE=agenda-recette`) puis `appliquer` : 8 à 12 minutes, dont l'essentiel pour l'installation de nginx et la création du répartiteur ; le job `appliquer` enchaîne un second `plan -detailed-exitcode` qui prouve l'idempotence.

**Explications**

Le libre-service repose sur trois séparations : le **code** (module de la plateforme, valeurs de l'équipe), les **droits** (application credential `member` limitée au projet, quotas fixés par la plateforme), l'**état** (compartiment et phrase propres à l'équipe). La plateforme garde la main sur l'évolution du module (MR, étiquettes) ; l'équipe garde la main sur le moment où elle l'adopte.

**Alternatives**
- Heat (E14) en libre-service : natif, sans état externe, mais moins répandu dans les équipes et moins outillé en CI.
- Un seul dépôt plateforme avec un répertoire par équipe : plus simple à relire, mais l'équipe dépend des MR de la plateforme — ce que Julien veut éviter.
- Catalogue de services (Backstage, module 28) qui génère le dépôt de l'équipe.

**Pièges classiques**
- Application credential `admin` « pour que ça marche » : un pipeline d'équipe qui peut tout faire sur le cloud.
- État de l'équipe dans le compartiment de la plateforme avec des identifiants partagés.
- Membres du répartiteur ajoutés par adresse codée en dur.
- `ROUND_ROBIN` demandé au fournisseur OVN : refus à la création (seul `SOURCE_IP_PORT` est pris en charge).
- `ignore_changes` oublié sur `user_data` : la moindre retouche de la page **recrée** les instances (et l'attachement du volume).

**En production chez MédiSphère**
Module publié avec un journal des changements, testé (OpenTofu `test`, module 29) ; application credentials renouvelées automatiquement avant expiration ; destruction planifiée des recettes inutilisées ; coûts par projet dans le rapport mensuel (E33).

---

### M10-E32 — Questions de production : OpenStack

1. **Réponse b.** Le domaine QEMU tourne indépendamment du plan de contrôle ; le trafic entre instances du même réseau (et même entre réseaux via le routeur OVN distribué) est commuté par les flux OVS déjà programmés par `ovn-controller` sur chaque calcul. L'IP flottante passe par le *gateway chassis* `osctl01` : coupée. (a) faux : `nova-compute` n'arrête pas les instances quand il perd le plan de contrôle. (c) faux : le DHCP d'OVN est répondu **localement** par `ovn-controller` de chaque calcul, à partir des flux en place ; les renouvellements fonctionnent tant que le calcul vit (et le bail par défaut est long). (d) faux pour le nord-sud. Avec `neutron_ovn_distributed_fip`, les IP flottantes des instances sortent par leur propre calcul : elles survivraient ; le SNAT des instances sans IP flottante reste centralisé.
2. Galera et Raft exigent une **majorité** pour écrire. À deux, la perte d'un nœud laisse 1/2 : pas de majorité, le survivant refuse les écritures (ou il faut l'amorcer à la main, au risque d'un cerveau divisé). Un nœud seul n'a pas ce problème (1/1) : deux nœuds sont donc **moins** disponibles qu'un seul, avec deux fois plus de pannes possibles. Trois nœuds tolèrent une panne ; quatre en tolèrent toujours une seule (majorité 3/4) pour un coût supérieur ; cinq en tolèrent deux.
3. **Réponse c** (impossible). Un quota dépassé est refusé par l'API **avant** l'ordonnancement, avec un message de quota (HTTP 403, *Quota exceeded*), pas « No valid host ». (a) se voit dans `openstack compute service list` (calculs `down`) et dans les journaux du *scheduler* (aucun hôte candidat) ; (b) dans Placement (`allocation candidate list --resource MEMORY_MB=…`) et dans le journal du *scheduler* ; (d) dans les propriétés de l'image (`openstack image show`) et les traits des fournisseurs (`resource provider trait list`).
4. Mémoire allouable par calcul : ≈ 7 960 Mio vus par Nova (`MEMORY_MB` de Placement) − 2 048 réservés (E20) ≈ 5 900 Mio × 1.0 → **5** `m1.petit` (7 avec la réserve par défaut de 512 Mio, qui sous-estime ce que consomment le système et les conteneurs de Kolla) ; vCPU : 4 × 4.0 = 16. La mémoire limite. Au-delà de 1.0, on promet plus que la mémoire physique : en cas d'usage réel, l'hôte échange ou l'OOM tue un QEMU ; sur une VM imbriquée de 8 Go, c'est aussi la VM elle-même qui se met à échanger dans `pve01`, et toutes les instances ralentissent ensemble.
5. Redémarrage de MariaDB : toutes les API répondent 500/503 (ou des délais), Horizon affiche des erreurs, les créations en cours peuvent finir en `ERROR`. Redémarrage de RabbitMQ : les lectures fonctionnent, les actions asynchrones (créations, attachements) restent en suspens ou échouent, les services se reconnectent. À trois contrôleurs, Kolla redémarre les membres **un par un** (Galera reste en quorum, RabbitMQ aussi) : interruption de quelques secondes. `--limit` : les rôles de Kolla enregistrent des faits sur tous les hôtes d'un groupe (`register`, `delegate_to`) ; limiter l'exécution casse ces calculs (bogues connus, Nova cité par la documentation).
6. Attendre Kolla-Ansible 23.x **final** (les rôles suivent les changements d'OpenStack : configuration, migrations, dépendances) ; lire les notes de version de chaque service ; monter `kolla-ansible` et **ansible-core à la plage qu'il exige** (nouveau `uv lock`, peut-être une contrainte différente de < 2.21) ; `install-deps` ; comparer inventaire et `globals.yml` aux exemples ; fusionner `passwords.yml` (`kolla-genpwd` sur l'exemple, `kolla-mergepwd`) ; `pull`, `prechecks`, puis **`kolla-ansible upgrade`** (migrations de schémas, ordre des services). SLURP : montée d'une série « .1 » à la suivante « .1 » en sautant la « .2 » (2026.1 → 2027.1), prise en charge par OpenStack ; RabbitMQ ne saute pas deux versions majeures : étape intermédiaire (procédure SLURP de Kolla). Toujours sur une recette d'abord, sauvegarde vérifiée.
7. **Perdu** : tout ce qui a été créé, modifié ou supprimé dans OpenStack entre 01:30 et 16:00 (projets, utilisateurs, quotas, instances, volumes, réseaux, IP flottantes). **Orphelin** : volumes et images créés après (images RBD sans Cinder ni Glance), instances créées après (domaines libvirt et disques `vms/` inconnus de Nova). **Incohérent** : instances supprimées après (Nova les croit `ACTIVE`), IP flottantes réattribuées, réseaux OVN créés ou supprimés après (écart Neutron/OVN). Une base de plan de contrôle décrit le monde ; restaurer la description ne restaure pas le monde : il faut comparer et corriger (réconciliation).
8. **Réponse c** (fausse). La rotation crée une nouvelle clé « en attente », promeut l'ancienne en attente au rang de clé primaire et garde les anciennes primaires comme secondaires pendant `fernet_token_expiry + fernet_token_allow_expired_window` (défaut de Kolla : 1 j + 2 j = `fernet_key_rotation_interval` de 3 jours) : les jetons en cours restent valides. (a) vrai (chiffrement authentifié, pas de stockage). (b) vrai : chaque Keystone ne valide que les jetons chiffrés avec une clé qu'il possède. (d) vrai : la date d'expiration est dans le jeton ; un nœud en avance le juge expiré.
9. Ordre : (1) **révoquer** l'application credential (`application credential delete` par son propriétaire, ou désactivation du compte de service) ; (2) relire ce qu'elle a fait (journaux de Keystone et des API : application credential dans les jetons) ; (3) en créer une nouvelle, mettre à jour la variable masquée ; (4) purger le journal de pipeline (et ses artefacts), chercher pourquoi le masquage a échoué (secret qui ne respecte pas les contraintes de masquage, `set -x`) ; (5) incident de sécurité tracé. Limitent les dégâts dans E31 : rôle `member` sur un seul projet, expiration, quotas, état chiffré avec une autre phrase, pas d'accès aux autres équipes. Aggravants : rôle `admin`, application credential `unrestricted`, absence d'expiration, même application credential pour plusieurs projets.
10. Instance → réseau de projet (Geneve) → routeur OVN (distribué) → SNAT sur l'adresse du routeur dans `ext-net` (10.10.52.x) via la passerelle `osctl01` → VLAN 52 → bordure (10.10.52.1) → routage vers le VLAN 20. La seule barrière est la **matrice de la bordure** (et les groupes de sécurité en sortie, ouverts par défaut). La règle « VLAN 52 → VLAN 50 interdit » protège le plan de contrôle, pas le socle : si la bordure autorise VLAN 52 → VLAN 20 au-delà du DNS, une instance compromise atteint GitLab, NetBox, step-ca. D'où la liste blanche : DNS du socle, Internet, rien d'autre.
11. Avec Ceph, Nova clone l'image (copie à la volée, *copy-on-write* RBD) si elle est en **raw** dans le pool `images` : création d'instance en secondes, pas de place consommée. Un qcow2 ne peut pas être cloné par RBD : chaque création télécharge l'image, la convertit en raw et l'écrit en entier dans `vms` (minutes, 10 Go de disque virtuel écrits pour une image de 2 Go), à chaque instance. Prévention : n'autoriser que `raw` dans `disk_formats` de Glance pour les envois des équipes, ou l'importation interopérable avec conversion (`image import`, greffon `image_conversion`) ; images publiques maintenues par la plateforme.
12. Avantages : images reproductibles, identiques sur tous les nœuds, mises à jour atomiques (un conteneur recréé), retour arrière par image ; correctifs publiés par le projet Kolla (reconstruction de la branche stable). Inconvénients : on dépend du rythme de reconstruction de Kolla (pas des annonces de sécurité Debian), étiquettes mobiles (« quelle version tourne ? » demande les empreintes), images à analyser soi-même (Trivy, module 13). Pour l'auditeur : photographie des empreintes (E28) et registre local avec étiquettes immuables.
13. C'est une copie, pas une sauvegarde au sens 3-2-1 : même cluster, même site, mêmes administrateurs. Elle protège d'une suppression ou d'une corruption logique d'un volume (on restaure la copie), pas de la perte du cluster Ceph, d'une erreur d'administration du cluster, ni d'un sinistre à PAR1. Cible : Cinder Backup vers le stockage S3 (`s3-01`, autre machine) puis réplication vers PAR2 (PBS ou second S3), avec une copie hors ligne des clés.
14. 99,9 % sur 30 jours = 43 minutes d'arrêt. Aujourd'hui, une seule mise à jour (E28) consomme ~10 minutes d'API, un redémarrage du contrôleur ~7 minutes, une restauration ~25 minutes : le budget est épuisé en un incident. Il manque : trois contrôleurs (et la passerelle répartie), un registre d'images maîtrisé, des mises à jour sans interruption, des sauvegardes hors site testées, une supervision avec alertes (module 21) et une astreinte formée, et une mesure de la disponibilité (SLI) pour savoir où l'on en est.

---

### M10-E33 — Rapport de capacité et de consommation

**Modèles** : [`rapport-2026-10.md`](fichiers/M10-E33/medisphere/docs/cloud/capacite/rapport-2026-10.md), script de collecte [`ms-capacite-openstack`](fichiers/M10-E33/outils/bin/ms-capacite-openstack) (`plateforme/outils`).

**Ce que la correction regarde**

| Critère | Attendu |
|---|---|
| Capacité allouable | Placement : `(total − reserved) × allocation_ratio` par classe de ressources et par hôte ; ratios et réservations expliqués |
| Trois notions distinguées | capacité allouable, allocations (gabarits), consommation réelle (`free`, charge) — et quotas, qui ne réservent rien |
| Projets | quotas et usage (`limits show --absolute`), heures consommées (`openstack usage list`) ; somme des quotas comparée à la capacité |
| Stockage | stocké, brut (× 3), disponible avant `nearfull` ; provisionné (Cinder) contre écrit (`rbd du`) |
| Marge | en nombre d'instances par gabarit, avec la ressource limitante (mémoire) |
| Recommandation | chiffrée (date de saturation, action, coût), lisible par une non-spécialiste |
| Reproductibilité | script versionné, données brutes datées ; « ce que le rapport ne mesure pas » |

**Pièges classiques**
- Utiliser `openstack hypervisor stats show` ou les champs `vcpus`/`memory_mb` de `hypervisor show` : supprimés à partir de la micro-version 2.88 de l'API compute ; Placement fait foi.
- Additionner les quotas et les présenter comme une consommation.
- Oublier la réplication de Ceph (« 576 Gio disponibles » pour 192 Gio de données réelles).
- Raisonner en Go provisionnés : l'allocation fine fait que l'écrit est bien plus faible… jusqu'au jour où il ne l'est plus.

---

### M10-E34 — Un environnement complet en temps limité

Pas de corrigé à consulter pendant l'exercice (conditions d'examen). Après coup, le déroulé de référence (≈ 1 h 15 de T0 à T4) :

| Jalon | Gestes | Temps |
|---|---|---|
| T0 → T1 | MR sur le code d'identité (`donnees/identite.yml`) : projet `medinotif-essai` (description CHG-1160), groupe `equipe-medinotif` (`member`), `lucas.martin` (`reader`, compte créé s'il n'existe pas, mot de passe initial en Vault) ; `playbooks/identite.yml`. Puis MR sur `envs/openstack-projets` : entrée `medinotif-essai` de `terraform.tfvars` (quotas). La configuration de E15 crée aussi un socle réseau par projet (`<projet>-net`), alors que le dossier impose ses noms : le déroulé de référence rend `cidr` facultatif (`optional(string)`, réseau créé seulement s'il est donné), modification utile aussi à RB-100 ; l'autre voie acceptable est `openstack quota set`, geste manuel consigné dans la feuille de temps. Plan, revue, fusion, apply | 25 min |
| T1 → T2 | CLI (ou module de E31 sans répartiteur) : réseau, sous-réseau 192.168.60.0/24 avec les deux résolveurs, routeur, `router set --external-gateway`, groupe `medinotif-ssh` (TCP 22 depuis 10.10.10.0/24 et 10.255.1.0/24, TCP 22 et ICMP `--remote-group medinotif-ssh`) | 10 min |
| T2 → T3 | paire `medinotif-cle` (en tant qu'utilisateur du projet : les paires de clés appartiennent à un **utilisateur**), `worker01` Rocky 10 avec cloud-init (XFS sur le volume, `/srv/file`, `fstab` par UUID, `nofail`), volume de 10 Go attaché au démarrage, IP flottante ; `worker02` Debian 13 | 20 min |
| T3 → T4 | preuves : `ssh rocky@<IP>` puis `ssh debian@<IP-PRIVÉE>` (agent SSH transféré, `-A`, ou `ProxyJump`), `ping` ; identifiants de `lucas.martin` : `server list` OK, `volume create` → HTTP 403 ; `lab/bin/check 10 34` | 15 min |
| T4 → T5 | retrait : ressources du projet (ordre : IP flottante, instances, volume, routeur, sous-réseau, réseau, groupe), puis RB-100 à l'envers : entrée retirée de `envs/openstack-projets` (apply) et quotas remis à 0, groupe et rôles retirés, projet désactivé puis supprimé (`donnees/identite.yml` nettoyé) | 15 min |

**Points d'attention**
- Une paire de clés créée par l'administrateur n'est pas visible par les utilisateurs du projet (elle appartient à l'utilisateur qui l'a créée) : la créer avec le compte qui crée les instances.
- Le rebond SSH vers `worker02` vient de `worker01` (192.168.60.x), pas de MGMT : la règle « SSH entre membres » s'écrit avec `--remote-group medinotif-ssh` (et pas avec la plage 192.168.60.0/24, qui ouvrirait à tout le sous-réseau, y compris aux futures instances d'autres groupes).
- L'image `rocky-10` n'est partagée qu'avec le projet `plateforme` (M10-E06) : il faut l'ajouter au projet `medinotif-essai` (`openstack image add project rocky-10 <ID-PROJET>`, puis acceptation par le projet : `openstack image set --accept rocky-10` avec ses identifiants) — un piège qui coûte facilement dix minutes.
- Rocky Linux 10 exige un CPU `x86-64-v3` : les calculs ont un CPU `host`, c'est bon ; une instance qui ne démarre pas (*kernel panic* précoce dans la console) le rappellerait.
- Retrait : un projet supprimé avec des ressources dedans laisse des orphelins (Keystone ne supprime pas les ressources des autres services) : vider d'abord.

**Retour d'expérience type** : le temps se perd dans la revue de la MR des projets (dépendance humaine) et dans cloud-init du volume ; amélioration : RB-100 enrichi d'un modèle de MR « nouvelle équipe » et d'un module « environnement minimal » dérivé de E31.
