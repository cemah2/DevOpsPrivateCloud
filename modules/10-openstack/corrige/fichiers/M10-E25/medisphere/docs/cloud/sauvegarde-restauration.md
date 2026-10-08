# Sauvegarde et restauration du cloud OpenStack

> Propriétaire : équipe Plateforme. Créé par PLAT-1151 (M10-E25). Dernier test de restauration : voir [`tests/restauration.md`](tests/restauration.md).

## 1. Ce qui fait l'état du cloud, et comment il est protégé

| Élément | Où | Perte sans protection | Protection | RPO |
|---|---|---|---|---|
| Bases MariaDB de tous les services (Keystone, Nova, Neutron, Glance, Cinder, Placement, Heat, Octavia) | `osctl01`, volume Docker `mariadb` | Tout le plan de contrôle : projets, quotas, utilisateurs, instances, volumes, réseaux, IP flottantes | Mariabackup complet chaque nuit (01:30, `adm01`) → PBS `par1/openstack` (02:10, `osctl01`), chiffré | 24 h au pire |
| Configuration Kolla (`globals.yml`, `globals.d/`, `config/`, inventaire) | GitLab `plateforme/openstack` | Reconstruire à l'identique devient impossible | Git + sauvegarde de GitLab (M01-E28) | dernier commit |
| `passwords.yml` | GitLab, chiffré (Vault `critique`) | Tous les mots de passe internes | Git ; mot de passe Vault `critique` sur *paperkey* hors ligne | dernier commit |
| Certificats des VIP | ACME (step-ca), renouvelés automatiquement (E27) | Réémis en minutes | aucune (réémission) | — |
| Clés Fernet de Keystone | `osctl01`, volume `keystone_fernet_tokens` | Tous les jetons en cours invalides (reconnexion de tous) | Jointes à l'archive PBS (inutiles après 3 jours : rotation) | 24 h |
| Bases OVN Nord et Sud | `osctl01`, volumes `ovn_nb_db`, `ovn_sb_db` | Réseau logique | **Aucune** : reconstruites depuis la base Neutron (`neutron-ovn-db-sync-util`, Neutron fait foi) | — |
| RabbitMQ | `osctl01`, volume `rabbitmq` | Messages en transit | Aucune : état transitoire, files recréées au démarrage | — |
| Disques des instances, volumes, images | `ceph-par1`, pools `vms`, `volumes`, `images` | Données des équipes | Réplication Ceph (3 copies) ; Cinder Backup (pool `backups`, **même cluster** : voir §5) | — |
| Image MariaDB en service | `osctl01` | Restauration impossible ou risquée (format, version de `mariabackup`) | Nom et empreinte joints à l'archive PBS (`image-mariadb.txt`) | — |

## 2. Chaîne de sauvegarde

```
01:30  adm01    wb-openstack-mariabackup.service
                  uv run kolla-ansible mariadb-backup --full (identité Vault « critique » par script client)
                  → osctl01, volume mariadb_backup : full-<date>/mysqlbackup-<date>.qp.xbc.xbs.gz
                     + last_full_file
02:10  osctl01  wb-backup-socle.service (rôle sauvegarde_pbs, élément « openstack »)
                  refus si la dernière complète a plus de 26 h ou si gzip -t échoue
                  → PBS ds-lab, ns par1/openstack, host/osctl01, chiffré (clé pbs-osctl01.key)
                  puis purge locale des full-*/incr-* de plus de 7 jours
échec  ms-alerte@ (journal, priorité crit) sur l'hôte concerné
```

Contrôle hebdomadaire de restaurabilité, sans rien toucher : `sudo /usr/local/sbin/preparer-sauvegarde.sh verifier` sur `osctl01` (extraction et `--prepare` dans un conteneur jetable de la même image, contrôle des bases présentes, effacement).

## 3. Restaurer la base (même nœud)

**Quand** : corruption ou suppression massive dans la base, erreur humaine grave (projet supprimé avec ses ressources), échec d'une montée de version qui a migré les schémas. **Pas** pour récupérer une ressource isolée : on la recrée.

**Avant** (décision du responsable de la plateforme, communication aux équipes : « API indisponibles, instances non touchées ») :
1. Instantané des trois nœuds : `ms-snapshot --prefix avant-restau 2101 2102 2103`.
2. `HEALTH_OK` de `ceph-par1`.
3. Choisir la sauvegarde : la dernière complète locale (`last_full_file`), ou la rapatrier de PBS (§4).
4. Noter l'heure de la sauvegarde : c'est le point de retour (RPO réel = heure de l'incident − heure de la sauvegarde).

**Étapes** (procédure *MariaDB database backup and restore* de Kolla 2026.1, cas d'un seul nœud) :

```
root@osctl01:~# /usr/local/sbin/preparer-sauvegarde.sh preparer        # extraction + --prepare, même image
admin@adm01:~/src/openstack$ uv run kolla-ansible stop -i inventaire/multinode --configdir etc/kolla \
                               -t mariadb --yes-i-really-really-mean-it
root@osctl01:~# IMAGE=$(docker inspect -f '{{.Config.Image}}' mariadb)
root@osctl01:~# docker run --rm -it --volumes-from mariadb --name dbrestore -v mariadb_backup:/backup "$IMAGE" /bin/bash
(dbrestore) $ rm -rf /var/lib/mysql/* /var/lib/mysql/.[!.]*
(dbrestore) $ mariabackup --copy-back --target-dir /backup/restore/full
(dbrestore) $ exit
root@osctl01:~# docker start mariadb
root@osctl01:~# docker logs --tail 50 mariadb
```

**Après** :
1. Attendre `healthy` sur `mariadb` et `proxysql` ; redémarrer les conteneurs qui ont perdu leurs connexions s'ils ne se rétablissent pas seuls (`docker ps --filter health=unhealthy`).
2. `openstack compute service list`, `network agent list`, `volume service list` : tout `up`.
3. **Réconciliation** (§6) : toujours.
4. Supprimer `/backup/restore` (contient une copie complète de la base).
5. Compte rendu dans `tests/restauration.md` ou dans le post-mortem.

Si MariaDB ne démarre pas (Galera refuse d'amorcer) : `uv run kolla-ansible mariadb-recovery -i inventaire/multinode --configdir etc/kolla`. En dernier recours : retour à l'instantané des trois nœuds.

## 4. Rapatrier une sauvegarde depuis PBS

`osctl01` lit son propre espace de noms (jeton `wb-backup@pbs!osctl01`, droits `DatastoreBackup` : il lit **ses** sauvegardes) :

```
root@osctl01:~# set -a; . /etc/wb-backup/pbs-osctl01.env; set +a
root@osctl01:~# proxmox-backup-client snapshot list host/osctl01 --ns par1/openstack
root@osctl01:~# proxmox-backup-client restore host/osctl01/<HORODATAGE> socle.pxar /var/tmp/restau-pbs \
                  --ns par1/openstack --keyfile /etc/wb-backup/pbs-osctl01.key
root@osctl01:~# cat /var/tmp/restau-pbs/openstack/image-mariadb.txt          # image à utiliser
root@osctl01:~# MP=$(docker volume inspect -f '{{.Mountpoint}}' mariadb_backup)
root@osctl01:~# install -d "$MP/full-pbs" && cp /var/tmp/restau-pbs/openstack/mysqlbackup-*.gz "$MP/full-pbs/"
root@osctl01:~# echo "/backup/full-pbs/$(basename /var/tmp/restau-pbs/openstack/mysqlbackup-*.gz)" > "$MP/last_full_file"
```

Puis §3. Sur un `osctl01` **reconstruit** (disque perdu) : redéploiement par Kolla depuis le dépôt (même version de `kolla-ansible`, mêmes images : comparer avec `images-en-service.txt`), puis restauration de la base, puis clés Fernet (`keystone_fernet_tokens`, si l'archive a moins de 3 jours), puis réconciliation.

## 5. Ce que cette sauvegarde ne couvre pas

- **Données des instances et des volumes** : elles sont dans Ceph. Cinder Backup les copie dans le pool `backups` du **même** cluster : cela protège d'une erreur (volume supprimé, données écrasées), pas de la perte du cluster. Cible à atteindre (module F5) : Cinder Backup vers le stockage S3 de `s3-01` ou un second cluster à PAR2.
- **Bases OVN** : volontairement non sauvegardées ; Neutron fait foi et `neutron-ovn-db-sync-util` les reconstruit (mode `repair`).
- **Configuration générée** sur les nœuds (`/etc/kolla`) : régénérée par Kolla depuis le dépôt ; elle contient tous les mots de passe en clair, on évite donc de la multiplier dans les sauvegardes.

## 6. Réconciliation après restauration (orphelins et incohérences)

Une base restaurée revient à l'heure de la sauvegarde ; Ceph, les hyperviseurs et OVN, non. Tout ce qui a été créé ou supprimé entre la sauvegarde et l'incident est incohérent.

| Cas | Symptôme | Détection | Action |
|---|---|---|---|
| Volume créé après la sauvegarde | Image RBD sans volume | `rbd ls volumes` (sur `ceph01` : `sudo cephadm shell -- rbd ls volumes`) comparé à `openstack volume list --all-projects -f value -c ID` (nom RBD = `volume-<ID>`) | Prévenir le projet ; exporter si demandé (`rbd export`), puis supprimer, tracé |
| Instance créée après | Domaine libvirt et disque `vms/<uuid>_disk` inconnus de Nova | `virsh list --all` dans `nova_libvirt` comparé à `openstack server list --all-projects --host <hôte>` ; `rbd ls vms` | Arrêter le domaine, archiver puis supprimer le disque |
| Instance supprimée après | Instance `ACTIVE` dans Nova, plus de domaine ni de disque | `openstack server list --all-projects` puis `virsh` ; `rbd info vms/<uuid>_disk` | Passer l'instance en erreur puis la supprimer |
| Réseau, port, IP flottante créés ou supprimés après | Écart Neutron ↔ OVN | `neutron-ovn-db-sync-util --ovn-neutron_sync_mode log` dans le conteneur `neutron_server` | Mode `repair` après relecture du journal |
| Image envoyée après | Image RBD `images/<id>` inconnue de Glance | `rbd ls images` comparé à `openstack image list -f value -c ID` | Supprimer (ses instantanés `snap` d'abord) |

Script de comparaison volumes ↔ RBD (lecture seule) :

```
admin@adm01:~$ comm -13 <(openstack --os-cloud medisphere-admin volume list --all-projects -f value -c ID | sed 's/^/volume-/' | sort) \
                        <(ssh ceph01 sudo cephadm shell -- rbd ls volumes 2>/dev/null | sort)
```

Chaque ligne affichée est une image RBD de volume que Cinder ne connaît pas.

## 7. Objectifs et mesures

- **RPO** visé : 24 h (une complète par nuit). Pour descendre à 1 h : incrémentales horaires (second timer, `--incremental`), au prix d'une restauration plus longue (préparation de la chaîne complète + incrémentales).
- **RTO** mesuré : voir `tests/restauration.md` (≈ 25 min sur le lab de référence, dont 10 de réconciliation).
