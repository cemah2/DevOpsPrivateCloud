# Module 10 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les fichiers complets sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `fichiers/M10-EXX/openstack/…` = chemins de `plateforme/openstack` (racine du dépôt : `etc/kolla/…`, `heat/…`, `outils/…`), `…/infra/…` = `plateforme/infra`, `…/ansible/…` = `plateforme/ansible`, `…/medisphere/…` = la documentation. On **superpose** les dossiers dans l'ordre des exercices ; un fichier d'un exercice plus récent remplace le précédent. Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête), les `*.exemple` des modèles sans valeur réelle.

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Kolla-Ansible* : sources de la branche `stable/2026.1` (22.2.x) lues pour chaque chemin de surcharge et chaque variable cités (rôles `glance`, `cinder`, `nova`, `nova-cell`, `neutron`, `octavia`, `horizon` ; `group_vars/all/*.yml`) ; options de la CLI (`--configdir`, `--vault-id`, `-t`, `-l`) lues dans `kolla_ansible/ansible.py`.
- *Neutron* (calcul de la MTU Geneve : `type_tunnel.py`, `type_geneve.py`), *Nova*, *Heat*, *Octavia* (politiques par défaut), *Keystone* (implications de rôles du `bootstrap`), *oslo.policy* (valeurs par défaut) : sources 2026.1 lues.
- *python-openstackclient 10.3.0* avec `python-heatclient`, `python-octaviaclient`, `osc-placement` : chaque commande et option du corrigé contrôlée par `--help`.
- *OpenTofu 1.13.1* : `tofu fmt` et `tofu validate` de `envs/openstack-projets` avec `terraform-provider-openstack/openstack` **3.4.0** (sans backend).
- Collection `openstack.cloud` (branche principale) : le module `role_assignment` n'a pas d'option d'héritage (d'où le script de E23) ; `identity_role` crée un rôle.
- Gabarit HOT, `globals.d/*.yml` et politiques : YAML valide ; `_9999-custom-settings.py` : `py_compile`. Scripts et vérifications : ShellCheck 0.11 et `bash -n` ; les vérifications ont été exécutées « à vide » (API injoignables) pour s'assurer qu'elles vont au bout et ne donnent aucun faux positif sans lab.

**Non rejoués sur un lab réel** : le déploiement Kolla lui-même (enchaînements, redémarrages, durées), les droits cephx minimaux en fonctionnement (clonage, sauvegarde incrémentale), le comportement exact d'OVN (répartiteur, métadonnées, MTU), Horizon (champ de domaine, politiques recopiées), l'import OpenTofu avec un identifiant issu d'une source de données, la lecture des métadonnées par les gabarits Jinja de cloud-init. Ils sont signalés « ⚠️ À vérifier sur ton lab » : signale tes retours.

**Convention des commandes.** `kolla-ansible <action>` = `uv run kolla-ansible <action> -i inventaire/multinode --configdir etc/kolla`, lancé depuis `~/src/openstack` (l'identité Vault `critique` vient de l'`ansible.cfg` du projet, E03). Les réglages de Kolla de ce palier vont dans `etc/kolla/globals.d/<NN>-<sujet>.yml`, lus après `globals.yml` : ils remplacent ses valeurs (par exemple `enable_cinder: "no"` du palier 1).

---

### M10-E10 — Brancher OpenStack sur Ceph

**Solution**

Fichiers : [`globals.d/10-ceph.yml`](fichiers/M10-E10/openstack/etc/kolla/globals.d/10-ceph.yml), [`passwords.yml.extrait`](fichiers/M10-E10/openstack/etc/kolla/passwords.yml.extrait), [`glance.conf`](fichiers/M10-E10/openstack/etc/kolla/config/glance.conf), [`ceph.conf.exemple`](fichiers/M10-E10/openstack/etc/kolla/config/ceph.conf.exemple), trousseaux-gabarits sous [`config/`](fichiers/M10-E10/openstack/etc/kolla/config/), [`outils/ceph-conf-clients.sh`](fichiers/M10-E10/openstack/outils/ceph-conf-clients.sh), [`outils/recreer-images.sh`](fichiers/M10-E10/openstack/outils/recreer-images.sh).

1. **Inventaire.**
   ```
   admin@adm01:~$ export OS_CLOUD=medisphere-admin
   admin@adm01:~$ openstack image list --long -c Name -c "Disk Format" -c Size -c Visibility
   admin@adm01:~$ openstack image show -c stores -c properties debian-13
   admin@adm01:~$ openstack server list --all-projects --long -c Name -c Status -c Host
   ```
   Images en `qcow2`, `stores: file`. Décision du corrigé : **recréer** les deux images depuis leur source officielle (somme vérifiée, comme en E06) plutôt que les exporter : la source est la référence, l'export d'une image déjà importée ne prouve rien de plus et double le temps de transfert. Les propriétés de E06 (`os_distro`, `os_version`, `hw_disk_bus`, `hw_scsi_model`, `hw_qemu_guest_agent`) sont notées pour être reposées.

2. **Côté Ceph.**
   ```
   [admin@ceph01 ~]$ sudo cephadm shell -- ceph osd pool ls detail | grep -E "images|volumes|vms|backups"
   [admin@ceph01 ~]$ sudo cephadm shell -- ceph osd pool application get volumes
   [admin@ceph01 ~]$ for c in glance cinder cinder-backup nova; do sudo cephadm shell -- ceph auth get client.$c; done 2>/dev/null
   ```
   Si M08-E46 ne les a pas créés (sinon, comparer les droits à ceux-ci) :
   ```
   [admin@ceph01 ~]$ sudo cephadm shell
   [ceph: root@ceph01 /]# for p in images volumes vms backups; do ceph osd pool create $p; rbd pool init $p; done
   [ceph: root@ceph01 /]# ceph auth get-or-create client.glance mon 'profile rbd' osd 'profile rbd pool=images' mgr 'profile rbd pool=images'
   [ceph: root@ceph01 /]# ceph auth get-or-create client.cinder mon 'profile rbd' osd 'profile rbd pool=volumes, profile rbd-read-only pool=images' mgr 'profile rbd pool=volumes'
   [ceph: root@ceph01 /]# ceph auth get-or-create client.cinder-backup mon 'profile rbd' osd 'profile rbd pool=backups' mgr 'profile rbd pool=backups'
   [ceph: root@ceph01 /]# ceph auth get-or-create client.nova mon 'profile rbd' osd 'profile rbd pool=vms, profile rbd-read-only pool=images' mgr 'profile rbd pool=vms'
   ```
   Pourquoi ces accès croisés :
   - `client.cinder` **lit** `images` : un volume créé depuis une image est un **clone** de l'instantané de l'image (pas une copie) ; il écrit `volumes`.
   - `client.nova` lit `images` (clone de l'image vers `vms/<uuid>_disk`) et écrit `vms`. Les volumes attachés, eux, sont ouverts par libvirt avec la clé de **Cinder** (secret `cinder_rbd_secret_uuid`) : Nova n'a pas besoin de `volumes`.
   - `cinder-backup` lit le volume source avec `client.cinder` (Kolla lui pose les deux trousseaux) et écrit `backups` avec `client.cinder-backup`.
   - La page *Block Devices and OpenStack* de Ceph donne aussi `vms` à `client.cinder` : c'est pour le cas par défaut de Kolla où Nova **utilise** la clé de Cinder. Avec une clé `client.nova` séparée, on retire `vms` à Cinder. ⚠️ À vérifier sur ton lab : démarrage depuis un volume, migration à chaud et sauvegarde d'un volume attaché doivent fonctionner avec ces droits.

   Le `ceph.conf` client : `outils/ceph-conf-clients.sh` lance `ceph config generate-minimal-conf` sur `ceph01`, retire les tabulations et le dépose dans `etc/kolla/config/{glance,cinder,nova}/ceph.conf`. Il ne contient que le `fsid` et les trois MON (v2 et v1) : pas de secret.

3. **Côté dépôt.** Deux façons de ne pas mettre de clé en clair :
   - *trousseaux chiffrés* (`ansible-vault encrypt` sur chaque fichier) : Ansible déchiffre les gabarits Vault à la volée, mais un fichier chiffré ne se relit pas en MR et chaque rotation réécrit six fichiers ;
   - *trousseaux-gabarits* (choix du corrigé) : chaque trousseau contient `key = {{ ceph_cle_<service> }}` ; les quatre clés sont des entrées de `passwords.yml`, déjà chiffré par l'identité `critique` et passé par Kolla comme variables. Les trousseaux se relisent, une rotation ne touche qu'un fichier. Kolla copie les trousseaux avec le module `template` et en extrait la clé par une recherche `template` pour les secrets libvirt (rôle `nova-cell`, tâche `external_ceph`) : les deux évaluent le Jinja. ⚠️ À vérifier sur ton lab : `sudo cat /etc/kolla/glance-api/ceph/ceph.client.glance.keyring` sur `osctl01` montre la vraie clé.

   Emplacements (documentation *External Ceph* 2026.1) : `glance/ceph.client.glance.keyring` ; `cinder/cinder-volume/ceph.client.cinder.keyring` ; `cinder/cinder-backup/ceph.client.cinder.keyring` **et** `ceph.client.cinder-backup.keyring` ; `nova/ceph.client.nova.keyring` **et** `ceph.client.cinder.keyring` (volumes attachés). Réglages : `globals.d/10-ceph.yml` ; `ceph_nova_user: "nova"` est indispensable, sinon Nova prend la clé de Cinder. `show_image_direct_url = True` dans `glance.conf` : sans lui, Nova et Cinder ne connaissent pas l'emplacement RBD de l'image et la **téléchargent** à chaque création ; le risque cité par Kolla (emplacement visible des utilisateurs) est acceptable avec un seul magasin et sans accès cephx pour les utilisateurs.

4. **Déploiement.**
   ```
   admin@adm01:~$ for p in plateforme mediagenda-dev; do openstack server list --project $p -f value -c ID | xargs -r openstack server delete --wait; done
   admin@adm01:~/src/openstack$ kolla-ansible prechecks
   admin@adm01:~/src/openstack$ kolla-ansible deploy
   ```
   `reconfigure` ne crée pas de nouveaux services : il régénère la configuration et redémarre ce qui a changé. L'arrivée de Cinder (conteneurs, base de données, utilisateur et points d'accès Keystone, règles HAProxy) demande `deploy` (sans étiquette, ou `-t cinder,glance,nova,haproxy` si tu maîtrises les dépendances ; le corrigé prend `deploy` complet, idempotent). Contrôles :
   ```
   admin@adm01:~$ openstack volume service list
   | cinder-scheduler | osctl01        | nova | enabled | up |
   | cinder-volume    | osctl01@rbd-1  | nova | enabled | up |
   | cinder-backup    | osctl01        | nova | enabled | up |
   admin@oscmp01:~$ sudo docker exec nova_libvirt virsh secret-list
   ```
   Deux secrets libvirt : `rbd_secret_uuid` (clé de `client.nova`, disques éphémères) et `cinder_rbd_secret_uuid` (clé de `client.cinder`, volumes). Libvirt présente la clé à QEMU, qui ouvre lui-même l'image RBD : aucun disque n'est monté sur le calcul.

5. **Images.**
   ```
   admin@adm01:~/src/openstack$ outils/recreer-images.sh debian-13 \
       https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2 \
       https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS \
       os_distro=debian os_version=13 hw_disk_bus=scsi hw_scsi_model=virtio-scsi hw_qemu_guest_agent=yes
   [admin@ceph01 ~]$ sudo cephadm shell -- rbd ls -l images
   NAME                                       SIZE  PARENT  FMT  PROT  LOCK
   3c1f…                                       3 GiB          2
   3c1f…@snap                                  3 GiB          2  yes
   ```
   (Même chose pour `rocky-10` avec l'image *GenericCloud* et son `CHECKSUM` ; supprimer les anciennes images `file` une fois les nouvelles vérifiées.) L'instantané protégé `snap` est le point d'ancrage des clones : un clone RBD part toujours d'un instantané, jamais d'une image qui pourrait changer.

6. **Instances.**
   ```
   admin@adm01:~$ export OS_CLOUD=medisphere-plateforme
   admin@adm01:~$ time openstack server create --wait --image debian-13 --flavor m1.petit --key-name cle-adm01 --network reseau-plateforme e10-vm
   [admin@ceph01 ~]$ sudo cephadm shell -- rbd info vms/<uuid de e10-vm>_disk | grep parent
       parent: images/3c1f…@snap
   admin@adm01:~$ openstack server create --wait --image debian-13 --boot-from-volume 10 --flavor m1.petit --key-name cle-adm01 --network reseau-plateforme e10-vol
   admin@adm01:~$ openstack server show e10-vol -c volumes_attached ; openstack volume list
   ```
   Création de `e10-vm` : quelques secondes de stockage (un clone ne copie rien), contre le téléchargement et la conversion de l'image sur le calcul au palier 1. Le disque de `e10-vol` est `volumes/volume-<id>`, lui aussi clone de l'image. Par défaut (`--boot-from-volume` sans `--delete-on-termination`), le volume **survit** à la suppression de l'instance.

7. **qcow2.** Ceph ne sait cloner que des images RBD brutes : un qcow2 est un format de fichier avec ses propres métadonnées. Nova (`images_type = rbd`) détecte que l'image n'est pas clonable, la **télécharge**, la convertit en raw sur le calcul puis l'importe dans `vms` : lent, coûteux en disque local, et à chaque création. Cinder fait de même pour un volume. D'où la règle : images raw sur Ceph.

**Explications**

Kolla ne déploie pas Ceph : il se contente de poser, dans chaque conteneur qui en a besoin, un `ceph.conf` et un trousseau, et de renseigner les options RBD des services (`[rbd]` de Glance, section `rbd-1` de Cinder, `[libvirt] images_type = rbd` de Nova). Les quatre identités séparées limitent le rayon d'une fuite : la clé de Glance ne permet pas d'effacer les disques des instances. Le clonage copie-sur-écriture (*layering* RBD) est ce qui rend OpenStack sur Ceph efficace : une image de 3 Go sert de base à cent instances, chacune n'occupe que ce qu'elle a modifié.

**Alternatives**
- *Glance multi-magasins* (`file` + `rbd` en parallèle, puis copie par `openstack image import --method copy-image`) : migration sans recréation, mais demande l'import interopérable et laisse un temps deux sources de vérité.
- *Import avec conversion* (greffon *image conversion* de Glance) : on téléverse le qcow2, Glance le convertit ; pratique pour les équipes, coûteux sur `osctl01`.
- *Clé unique pour Nova et Cinder* (défaut de Kolla) : plus simple, documenté partout, mais une seule identité pour deux services.

**Pièges classiques**
- `ceph_nova_user` oublié : Nova cherche `ceph.client.cinder.keyring` dans `nova/` et utilise les droits de Cinder ; tout marche, et le moindre privilège est perdu sans que rien ne le signale.
- Tabulations du `generate-minimal-conf` laissées : échec de fusion INI au déploiement.
- Se fier à la page *External Ceph*, qui place encore `cinder-volume` sur le groupe `[storage]` : depuis 2026.1, l'inventaire d'exemple les rattache au groupe `cinder` (enfant de `control`) ; un inventaire ancien, sans ce groupe, ne déploie aucun `cinder-volume`. Lis `[cinder-volume:children]` dans **ton** `inventaire/multinode`.
- Image qcow2 téléversée après la bascule : instances lentes à créer, disque local du calcul qui se remplit. `openstack image list --long` montre le format.
- Instances du palier 1 non supprimées avant la bascule de Nova : elles passent en `ERROR` au prochain redémarrage (Nova cherche `vms/<uuid>_disk`).
- `kolla-mergepwd --clean` lors d'une mise à jour (E28) : supprime les entrées `ceph_cle_*` qu'il ne connaît pas.

**En production chez MédiSphère**
Pools dédiés par classe de performance (volumes `ssd`, sauvegardes `hdd`, M08), une règle CRUSH par usage, `rbd_thin_provisioning` de Glance, une rotation annuelle des clés cephx (une à la fois : nouvelle clé, `reconfigure`, retrait de l'ancienne), et la supervision de la capacité des pools couplée aux quotas d'OpenStack (E13).

---

### M10-E11 — Cinder : volumes, types, snapshots, sauvegardes

**Solution**

Fichiers : [`config/cinder.conf`](fichiers/M10-E11/openstack/etc/kolla/config/cinder.conf), [`outils/types-volumes.sh`](fichiers/M10-E11/openstack/outils/types-volumes.sh).

1. **Types et QoS** (`types-volumes.sh`, idempotent) :
   ```
   admin@adm01:~$ openstack volume type create --public --property volume_backend_name=rbd-1 ceph-standard
   admin@adm01:~$ openstack volume type create --public --property volume_backend_name=rbd-1 ceph-iops-limite
   admin@adm01:~$ openstack volume qos create --consumer front-end --property total_iops_sec=500 --property total_bytes_sec=104857600 qos-500iops
   admin@adm01:~$ openstack volume qos associate qos-500iops ceph-iops-limite
   ```
   Puis la surcharge `cinder.conf` (`default_volume_type = ceph-standard`), MR, `kolla-ansible reconfigure -t cinder`. Contrôle : `openstack volume type list --default` → `ceph-standard` ; `openstack volume create --size 1 essai && openstack volume show essai -c type` → `ceph-standard` ; suppression de `essai`. L'ordre compte : le type doit exister avant que le service ne le désigne comme défaut.

2. **Volume et données.**
   ```
   admin@adm01:~$ export OS_CLOUD=medisphere-plateforme
   admin@adm01:~$ openstack server create --wait --image debian-13 --flavor m1.petit --key-name cle-adm01 --network reseau-plateforme e11-vm
   admin@adm01:~$ openstack volume create --size 10 --type ceph-iops-limite vol-essai
   admin@adm01:~$ openstack server add volume e11-vm vol-essai
   debian@e11-vm:~$ lsblk            # sdb (bus scsi de l'image) ou vdb
   debian@e11-vm:~$ sudo mkfs.ext4 -L donnees /dev/sdb && sudo mkdir -p /srv/donnees && sudo mount /dev/sdb /srv/donnees
   debian@e11-vm:~$ sudo dd if=/dev/urandom of=/srv/donnees/fichier bs=1M count=200 status=none && sha256sum /srv/donnees/fichier | tee ~/somme
   ```
   (Accès SSH : par l'IP flottante de E08, ou par la console.)

3. **QoS.** `sudo apt-get install -y fio` puis `sudo fio --name=lecture --filename=/srv/donnees/fio --size=1G --rw=randread --bs=4k --iodepth=32 --direct=1 --runtime=30 --time_based --ioengine=libaio`. Comme le volume a été créé directement avec le type limité, la limite s'applique dès l'attachement ; pour comparer, crée un volume `ceph-standard` le temps de la mesure. Nova lit la QoS **à l'attachement** et l'écrit dans la définition libvirt du disque : modifier la QoS d'un volume attaché n'a d'effet qu'au rattachement (ou à un redémarrage dur de l'instance). Preuve :
   ```
   admin@oscmp01:~$ sudo docker exec nova_libvirt virsh dumpxml <nom libvirt de e11-vm> | grep -A4 iotune
       <iotune>
         <total_bytes_sec>104857600</total_bytes_sec>
         <total_iops_sec>500</total_iops_sec>
   ```
   (`openstack server show e11-vm -c OS-EXT-SRV-ATTR:host -c OS-EXT-SRV-ATTR:instance_name`, en administrateur, donne le calcul et le nom libvirt.) Résultat attendu : ~500 IOPS au lieu de plusieurs milliers.

4. **Instantané et clone.**
   ```
   admin@adm01:~$ openstack volume snapshot create --volume vol-essai --force snap-essai
   admin@adm01:~$ openstack volume create --snapshot snap-essai vol-clone
   [admin@ceph01 ~]$ sudo cephadm shell -- rbd children volumes/volume-<id vol-essai>@snapshot-<id snap-essai>
   volumes/volume-<id vol-clone>
   admin@adm01:~$ openstack volume snapshot delete snap-essai ; openstack volume snapshot show snap-essai -c status
   ```
   Un volume attaché demande `--force` avec les microversions anciennes de l'API (la 3.66 l'a rendu inutile ; le client l'accepte toujours). Cinder ne fige **pas** le système de fichiers : l'instantané est cohérent « comme après une coupure de courant » (journal ext4 rejoué au montage), pas cohérent pour une application. La suppression de `snap-essai` échoue : le pilote RBD refuse de retirer un instantané dont un clone dépend (l'instantané revient `available` et le journal de `cinder-volume` dit « snapshot is busy » ou équivalent ; ⚠️ libellé à vérifier sur ta version). Solutions : supprimer `vol-clone` d'abord, ou l'**aplatir** (`rbd_flatten_volume_from_snapshot = True` pour les clones futurs, ce qui copie toutes les données).

5. **Sauvegardes.**
   ```
   admin@adm01:~$ openstack volume backup create --force --name sauv-essai vol-essai
   debian@e11-vm:~$ echo "modif" | sudo tee -a /srv/donnees/fichier >/dev/null
   admin@adm01:~$ openstack volume backup create --force --incremental --name sauv-essai-inc vol-essai
   admin@adm01:~$ openstack volume backup show sauv-essai-inc -c is_incremental -c status
   [admin@ceph01 ~]$ sudo cephadm shell -- rbd ls -l backups
   admin@adm01:~$ openstack volume create --size 10 --type ceph-standard vol-restaure
   admin@adm01:~$ openstack volume backup restore sauv-essai vol-restaure
   admin@adm01:~$ openstack server add volume e11-vm vol-restaure
   debian@e11-vm:~$ sudo mount -o ro /dev/sdc /mnt && sha256sum /mnt/fichier ; cat ~/somme
   ```
   Le pilote Ceph de cinder-backup sait faire des sauvegardes **différentielles** natives entre deux clusters ou pools RBD (`rbd export-diff` / `import-diff`) : dans `backups`, on trouve une image de base `volume-<id>.backup.base` et ses instantanés. Le contenu restauré a la somme de l'étape 2 (sauvegarde complète, avant la modification). ⚠️ À vérifier sur ton lab : selon la version, la première sauvegarde d'un volume RBD vers un pool RBD est déjà « incrémentale » côté Ceph même sans `--incremental` ; lis `is_incremental` et les objets réellement créés.

6. **Agrandissement en ligne.**
   ```
   admin@adm01:~$ openstack --os-volume-api-version 3.42 volume set --size 20 vol-essai
   debian@e11-vm:~$ lsblk /dev/sdb ; sudo resize2fs /dev/sdb ; df -h /srv/donnees
   ```
   Sans la microversion 3.42, l'API refuse l'agrandissement d'un volume `in-use`. Nova notifie l'instance (événement `volume-extended`) et QEMU agrandit le disque à chaud ; le système de fichiers reste à agrandir.

7. **Pour Julien.** L'instantané vit **dans le même pool** que le volume : il protège d'une erreur (migration de schéma ratée), se restaure en secondes (nouveau volume depuis l'instantané), mais disparaît avec le pool ou le cluster. La sauvegarde est une **copie** dans le pool `backups` : elle survit à la suppression du volume et de ses instantanés, mais pas à la perte de `ceph-par1` (même cluster) : il faudra une copie hors du cluster (M10-E25 : `pbs01` ou `s3-01`). Pour PostgreSQL, un instantané de bloc donne une base « après coupure de courant » : PostgreSQL sait redémarrer dessus, mais la bonne pratique reste `pg_basebackup` ou un instantané pris après `pg_backup_start()`, ou un gel du système de fichiers (`fsfreeze`, agent QEMU) ; et une sauvegarde logique (`pg_dump`) pour les retours arrière fins.

**Explications**

Le type de volume est l'interface entre ce que demande l'utilisateur (un nom lisible) et ce que fait le planificateur de Cinder (`volume_backend_name` → backend `rbd-1`). Les QoS « front-end » sont appliquées par l'hyperviseur (libvirt `iotune`), donc par instance et par disque, quel que soit le stockage ; les QoS « back-end » dépendent du pilote (RBD n'en a pas d'équivalent complet). Instantanés et clones sont gratuits sur Ceph (copie sur écriture), mais ils créent des **dépendances** : l'arbre parent-enfant de RBD explique la plupart des suppressions refusées.

**Alternatives**
- *QoS côté Ceph* (`rbd_qos_iops_limit` par image ou par pool) : protège le cluster de tous les clients, mais n'est pas piloté par le type de volume de Cinder.
- *Sauvegarde vers S3* (`cinder_backup_driver: "s3"`, `s3-01` ou RGW) : copie hors de `ceph-par1`, au prix de transferts complets plus lents.
- *Type « multiattach »* pour des clusters applicatifs à disque partagé : hors besoin ici.

**Pièges classiques**
- `default_volume_type` posé avant la création du type : toutes les créations sans `--type` échouent.
- QoS modifiée sur un volume attaché, « sans effet » : Nova ne la relit qu'à l'attachement.
- Restaurer une sauvegarde **par-dessus** le volume d'origine attaché : la restauration exige un volume `available` ; on restaure dans un nouveau volume, puis on bascule.
- `--force` oublié sur un volume attaché avec un vieux client : 400 « volume is in-use ».
- Croire qu'une sauvegarde dans `backups` protège de la perte de Ceph.

**En production chez MédiSphère**
Types par classe de service (`ssd`, `hdd`, chiffré), QoS par défaut sur **tous** les types (même large) pour qu'aucun client ne sature le cluster, sauvegardes planifiées par les équipes (CI) avec rétention, copie hors cluster (E25), et alerte quand une sauvegarde planifiée manque.

---

### M10-E12 — Le réseau externe intégré au lab

**Solution**

Fichiers : [`neutron.conf`](fichiers/M10-E12/openstack/etc/kolla/config/neutron.conf), [`neutron/ml2_conf.ini`](fichiers/M10-E12/openstack/etc/kolla/config/neutron/ml2_conf.ini), [`pare_feu.yml.extrait`](fichiers/M10-E12/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`docs/cloud/reseau-externe.md`](fichiers/M10-E12/medisphere/docs/cloud/reseau-externe.md).

1. **Le chemin.**
   ```
   admin@adm01:~$ export OS_CLOUD=medisphere-plateforme
   admin@adm01:~$ openstack server create --wait --image debian-13 --flavor m1.petit --key-name cle-adm01 --network reseau-plateforme --security-group ssh-icmp-admin e12-vm
   admin@gw01:~$ sudo tcpdump -ni ens19.52 icmp and host 1.1.1.1
   IP 10.10.52.2xx > 1.1.1.1: ICMP echo request …          # adresse de passerelle du routeur
   admin@adm01:~$ openstack floating ip create ext-net ; openstack server add floating ip e12-vm <IP-FLOTTANTE>
   IP <IP-FLOTTANTE> > 1.1.1.1: ICMP echo request …
   admin@osctl01:~$ sudo docker exec ovn_northd ovn-nbctl lr-nat-list neutron-<id du routeur>
   TYPE             GATEWAY_PORT  EXTERNAL_IP    LOGICAL_IP
   dnat_and_snat                  <IP-FLOTTANTE> 172.16.10.y
   snat                           10.10.52.2xx   172.16.10.0/24
   ```
   Ensuite la bordure applique son propre masquage vers Internet (adresse WAN) : un paquet d'instance subit **deux** traductions avant Internet.

2. **La politique** : voir [`reseau-externe.md`](fichiers/M10-E12/medisphere/docs/cloud/reseau-externe.md) (entrant : MGMT, VPN sur 22/80/443/ICMP ; sortant : DNS, NTP/NTS vers la passerelle, HTTP/HTTPS vers Internet ; tout le reste refusé).

3. **L'application** : voir l'extrait. Le point délicat est que `ens19.52` est dans `LAB_IFS`, utilisé à la fois par la règle **de sortie** générique et par les règles **d'entrée** NTP/NTS. On ne retire donc pas `ens19.52` de `LAB_IFS` : on crée `LAB_IFS_INTERNET` (tout sauf `ens19.52`) pour la seule règle générique de sortie, puis on ajoute la règle ciblée HTTP/HTTPS. La règle DNS existante (source 10.10.0.0/16) couvre déjà le VLAN 52 ; la politique par défaut `drop` de la chaîne `forward` fait le reste. Contrôles :
   ```
   debian@e12-vm:~$ sudo apt-get update                         # OK
   debian@e12-vm:~$ timeout 5 bash -c '</dev/tcp/1.1.1.1/25' ; echo $?        # 124 (filtré)
   debian@e12-vm:~$ timeout 5 bash -c '</dev/tcp/10.10.20.12/443' ; echo $?   # 124 (filtré)
   debian@e12-vm:~$ getent hosts deb.debian.org                 # résolu par 10.10.20.10
   ```

4. **La MTU.**
   ```
   admin@adm01:~$ openstack network show reseau-plateforme -c mtu ; openstack network show ext-net -c mtu
   | mtu | 1442 |        | mtu | 1500 |
   debian@e12-vm:~$ ping -M do -s 1414 -c 2 <autre instance>     # 1414 + 28 = 1442 : passe ; 1415 : « message too long »
   ```
   Neutron : `min(global_physnet_mtu, path_mtu) − 20 − max_header_size` = `1500 − 20 − 38` = 1442 (Kolla règle `max_header_size = 38` pour Geneve). Pour 1500 dans les réseaux des projets, il faut 1558 : `path_mtu = 1558`. Mais `min(global_physnet_mtu, path_mtu)` reste 1500 tant que `global_physnet_mtu` vaut 1500 : on le monte à 9000 (la vraie capacité d'OS-TUN), et on protège `ext-net` (flat sur le VLAN 52 à 1500) par `physical_network_mtus = physnet1:1500`. On ne donne **pas** 8942 : tout trafic vers `ext-net`, le lab ou Internet (1500) dépendrait de la découverte de PMTU (ICMP « fragmentation nécessaire » générés par le routeur OVN et souvent filtrés par les pare-feu d'instance) ; 1500 est la valeur que toutes les images attendent.
   ```
   admin@adm01:~/src/openstack$ kolla-ansible reconfigure -t neutron
   admin@osctl01:~$ sudo grep -E 'global_physnet_mtu|path_mtu|physical_network_mtus' /etc/kolla/neutron-server/neutron.conf /etc/kolla/neutron-server/ml2_conf.ini
   admin@adm01:~$ for n in $(openstack network list --internal -f value -c ID --os-cloud medisphere-admin); do openstack --os-cloud medisphere-admin network set --mtu 1500 $n; done
   debian@e12-vm:~$ sudo dhclient -r && sudo dhclient    # ou redémarrage ; puis ip link : mtu 1500
   debian@e12-vm:~$ ping -M do -s 1472 -c 2 <autre instance>     # passe
   ```
   (`openstack network list --internal` exclut `ext-net`. Sur Debian 13, le client DHCP peut être `networkd` : `sudo networkctl reconfigure <interface>`, ou un redémarrage.)

5. **NetBox** : *IPAM → IP Ranges → Add* : 10.10.52.200/24 à 10.10.52.249/24, statut « actif », description « IP flottantes et passerelles de routeurs OpenStack (ext-net) — gérée par Neutron », et l'option « marquer comme entièrement utilisée » (`mark_utilized` en 4.6 ; ⚠️ nom du champ à confirmer dans ta version). Ainsi `available-ips` de NetBox ne propose jamais ces adresses (M06-E13).

6. **Réponses.** Sans IP flottante, l'instance n'est **pas** joignable depuis `adm01` : son adresse (172.16.10.y) n'est routée nulle part hors de son routeur OVN, qui ne fait que du SNAT sortant. Une instance d'un autre projet ne la joint pas non plus (autre réseau, autre routeur) sauf par IP flottante. Pour **aucune** sortie : pas de routeur du tout (réseau isolé), ou un routeur créé par un administrateur avec `--disable-snat` (le SNAT désactivé, seules les IP flottantes sortent). Le choix se fait par projet, avec la politique de la bordure en filet de sécurité.

**Explications**

OVN implémente le routeur dans des flux OpenFlow : le port de passerelle du routeur est hébergé sur le *gateway chassis* (`osctl01`, seul nœud qui a `br-ex` sur `ens21`), et le trafic Nord-Sud de toutes les instances y passe (sauf avec les IP flottantes distribuées). La bordure ne voit que des adresses de `ext-net` : elle peut filtrer par VLAN et par destination, pas par instance ni par projet. D'où les deux niveaux : la politique **d'entreprise** sur la bordure (ce qu'aucune équipe ne peut ouvrir), les groupes de sécurité pour le reste (ce que chaque équipe ouvre chez elle).

**Alternatives**
- *Mandataire HTTP* (ou miroir APT interne) pour la sortie : remplace « tout Internet en 80/443 » par une liste de dépôts, avec journal. À prévoir (écart noté dans le document).
- *Pas de NAT de bordure pour le VLAN 52* et annonce BGP de 10.10.52.0/24 vers un vrai routeur : hors périmètre du lab.
- *Groupe de sécurité par défaut durci* (règles sortantes retirées) : agit par instance, pas par réseau ; contournable par l'équipe.

**Pièges classiques**
- Retirer `ens19.52` de `LAB_IFS` : le VLAN 52 perd aussi NTP et NTS (règles d'entrée), et les instances dérivent.
- Monter `global_physnet_mtu` sans `physical_network_mtus` : `ext-net`… garde 1500 (MTU fixée à la création), mais tout **nouveau** réseau flat ou VLAN naîtrait à 9000 sur un VLAN à 1500 : trames perdues en silence.
- `path_mtu = 9000` « parce que le réseau le permet » : instances à 8942, connexions qui se figent dès qu'un gros paquet sort vers le lab.
- Oublier les réseaux existants : leur MTU reste 1442 jusqu'au `network set --mtu`.
- Tester le filtrage depuis `adm01` au lieu de l'instance : MGMT a tous les droits.

**En production chez MédiSphère**
Journal des flux refusés du VLAN 52 (module 22), alertes sur les volumes sortants anormaux, mandataire sortant authentifié par projet, et revue trimestrielle de `reseau-externe.md` avec la RSSI.

---

### M10-E13 — Projets et quotas pour les équipes

**Solution**

Fichiers : [`docs/cloud/capacite.md`](fichiers/M10-E13/medisphere/docs/cloud/capacite.md), [`outils/quotas-equipes.sh`](fichiers/M10-E13/openstack/outils/quotas-equipes.sh).

1. **Capacité.**
   ```
   admin@adm01:~$ uv tool install --reinstall python-openstackclient --with python-heatclient --with python-octaviaclient --with osc-placement
   admin@adm01:~$ export OS_CLOUD=medisphere-admin
   admin@adm01:~$ openstack resource provider list
   admin@adm01:~$ openstack resource provider inventory list <uuid de oscmp01>
   | resource_class | allocation_ratio | min_unit | max_unit | reserved | step_size | total |
   | VCPU           |              4.0 |        1 |        4 |        0 |         1 |     4 |
   | MEMORY_MB      |              1.0 |        1 |     7960 |      512 |         1 |  7960 |
   | DISK_GB        |              1.0 |        1 |      … |        0 |         1 |    … |
   admin@adm01:~$ openstack resource provider usage show <uuid>
   admin@oscmp01:~$ free -m
   ```
   Mémoire utilisable par calcul ≈ (7 960 − 512) × 1.0 ≈ 7 450 Mio, mais `free -m` montre ≈ 1,3 Gio déjà pris par le système et les conteneurs : la réserve de 512 Mio ment. Décision (appliquée en E20) : `reserved_host_memory_mb = 2048`, soit ≈ 5 900 Mio utilisables par calcul et ≈ 11 800 Mio au total. Les quotas se dimensionnent **dès maintenant** sur cette valeur. `DISK_GB` : chaque calcul annonce la capacité du pool `vms` ; la somme compte deux fois le même espace, et la vraie limite est `ceph df`.

2. **Table** : voir `capacite.md` (mémoire : 2 048 + 3 072 + 6 144 = 11 264 Mio ≤ 11 800 ; vCPU : 17 ≤ 32 avec le ratio 4:1 ; production ≥ recette).

3. **Application** : `quotas-equipes.sh` (`openstack quota set` par identifiant de projet, pour éviter l'ambiguïté de nom entre domaines), contrôle `openstack quota show --usage <projet>`.

4. **Preuve.** Avec le cloud d'un membre (`medisphere-mediagenda-dev`) :
   ```
   admin@adm01:~$ openstack --os-cloud medisphere-mediagenda-dev server create --flavor m1.grand --image debian-13 --no-network e13-trop
   Quota exceeded for ram: Requested 4096, but already used 0 of 3072 ram (HTTP 403) (Request-ID: req-…)
   ```
   Le refus vient de **l'API** (`nova-api` contrôle le quota avant de créer quoi que ce soit), code 403, immédiat. À l'inverse, un manque de **capacité** (quota respecté mais calculs pleins) est détecté plus tard par l'ordonnanceur : instance en `ERROR`, « No valid host was found » (M10-E35).

5. **Gabarit réservé.**
   ```
   admin@adm01:~$ openstack flavor create --private --vcpus 2 --ram 4096 --disk 40 --description "Base de données de MédiAgenda (prod)" m1.prod-db
   admin@adm01:~$ openstack flavor set --project $(openstack project show -f value -c id --domain medisphere mediagenda-prod) m1.prod-db
   admin@adm01:~$ openstack --os-cloud medisphere-mediagenda-dev flavor list --all | grep prod-db   # rien
   ```

6. **Qui peut quoi.**
   ```
   admin@adm01:~$ openstack role assignment list --effective --names --project mediagenda-dev --project-domain medisphere
   admin@adm01:~$ openstack user create --domain medisphere --password-prompt essai-admin
   admin@adm01:~$ openstack role add --user essai-admin --user-domain medisphere --project mediagenda-dev --project-domain medisphere admin
   admin@adm01:~$ openstack --os-cloud essai-admin server list --all-projects        # (cloud jetable, projet mediagenda-dev)
   … les instances de TOUS les projets …
   admin@adm01:~$ openstack user delete --domain medisphere essai-admin              # et retrait du cloud jetable
   ```
   La règle `context_is_admin` de Nova vaut `role:admin` : elle ne regarde **pas** le projet. Un `admin` « de projet » est administrateur de tout le cloud (et de Keystone : il peut se donner d'autres rôles). Conclusion écrite dans `capacite.md` : jamais `admin` sur un projet d'équipe.

**Explications**

Deux mécanismes se superposent. Les **quotas** (par projet, vérifiés à l'API) disent ce qu'un projet a le droit de demander ; **Placement** (inventaires, réserves, ratios) dit ce que le cloud peut réellement donner, et l'ordonnanceur s'y réfère. Des quotas dont la somme dépasse la capacité ne protègent personne : la recette peut consommer la mémoire que la production croyait avoir. Ici, la somme des quotas de mémoire est sous la capacité réelle : la production a une part garantie, sans réservation explicite.

**Alternatives**
- *Surallocation de la mémoire* (`ram_allocation_ratio` > 1) : plus d'instances, risque d'échange ou de tueur OOM sur les calculs ; à éviter avec des bases de données.
- *Agrégats d'hôtes* (production sur `oscmp02`, recette sur `oscmp01`, filtres de l'ordonnanceur ou traits Placement) : isolation physique, au prix de la moitié de la capacité pour chacun.
- *Unified limits* (limites dans Keystone) : une seule source pour les limites de tous les services ; Nova et Glance les savent appliquer en 2026.1, pas tous les services.

**Pièges classiques**
- `openstack quota set --ram 3072 mediagenda-dev` avec un client authentifié dans un autre domaine : « No project with a name … » ; utiliser l'identifiant, ou `--project-domain`.
- Oublier les quotas réseau : un projet peut créer 100 réseaux et 50 IP flottantes par défaut, et vider le pool d'`ext-net` (50 adresses).
- Tester le quota avec `medisphere-admin` : l'administrateur… respecte les quotas du projet ciblé, mais crée dans **son** projet par défaut ; le test ne prouve rien.
- Confondre « Quota exceeded » (API, 403) et « No valid host » (ordonnanceur, instance en `ERROR`).

**En production chez MédiSphère**
Revue mensuelle `quota show --usage` contre capacité (rapport de E33), alerte quand un projet dépasse 80 % de son quota, et quotas tenus en code (E15) avec une MR comme seul chemin de hausse.

---

### M10-E14 — Heat : des piles d'infrastructure

**Solution**

Fichiers : [`heat/pile-recette.yaml`](fichiers/M10-E14/openstack/heat/pile-recette.yaml), [`heat/recette-dev.env.yaml`](fichiers/M10-E14/openstack/heat/recette-dev.env.yaml).

1. **Gabarit** : paramètres contraints (`glance.image`, `nova.flavor` + liste autorisée, `nova.keypair`, `neutron.network`, `net_cidr`, `range` 1-50), ressources, sorties `ip_flottante`, `url`, `volume`.
   ```
   admin@adm01:~/src/openstack$ export OS_CLOUD=medisphere-mediagenda-dev
   admin@adm01:~/src/openstack$ openstack orchestration template validate -t heat/pile-recette.yaml -e heat/recette-dev.env.yaml
   ```
2. **Création.**
   ```
   admin@adm01:~/src/openstack$ openstack stack create --wait -t heat/pile-recette.yaml -e heat/recette-dev.env.yaml recette-e14
   admin@adm01:~/src/openstack$ openstack stack event list recette-e14
   admin@adm01:~/src/openstack$ openstack stack output show recette-e14 url -c output_value -f value
   admin@adm01:~$ curl -s http://<IP-FLOTTANTE>/
   MédiAgenda recette — recette-e14-web
   ```
   Heat construit un graphe de dépendances à partir des références (`get_resource`, `get_param` de ressources, `get_attr`) et des `depends_on`, puis crée en **parallèle** tout ce qui ne dépend de rien : réseau, routeur, groupe de sécurité, volume partent ensemble ; le sous-réseau attend le réseau ; le port attend sous-réseau et groupe ; l'instance attend le port ; l'attachement attend instance et volume ; l'IP flottante attend le port **et** l'interface du routeur (dépendance explicite : Neutron refuse d'associer une IP flottante à un port dont le sous-réseau n'est pas relié à un routeur externe).
3. **Mise à jour.**
   ```
   admin@adm01:~/src/openstack$ openstack stack update --dry-run -t heat/pile-recette.yaml -e heat/recette-dev.env.yaml \
       --parameter gabarit=m1.moyen --parameter taille_volume=10 recette-e14
   … resource_identity …  updated: [serveur, volume]   replaced: []   unchanged: […]
   admin@adm01:~/src/openstack$ openstack stack update --wait -t heat/pile-recette.yaml -e heat/recette-dev.env.yaml \
       --parameter gabarit=m1.moyen --parameter taille_volume=10 recette-e14
   ```
   `flavor` d'`OS::Nova::Server` a `flavor_update_policy: RESIZE` par défaut : Heat redimensionne et **confirme** lui-même ; `size` d'`OS::Cinder::Volume` s'agrandit en place (Heat gère le volume attaché ; ⚠️ à vérifier sur ton lab : selon la version, Heat détache puis rattache le volume pendant l'opération). Aucune ressource remplacée : même IP flottante, mêmes données. Pense à mettre `gabarit: m1.moyen` et `taille_volume: 10` dans le fichier d'environnement (sinon la prochaine mise à jour sans `--parameter` reviendrait en arrière) et à le committer.
4. **Dérive.** Une règle ajoutée à la main au groupe de sécurité est **ignorée** par la mise à jour suivante : Heat compare l'ancien gabarit au nouveau, pas le gabarit à la réalité. La règle reste, invisible du code. Avec `--converge`, Heat compare à l'état réel observé et remet le groupe conforme (option de `stack update` du client 2026.1). OpenTofu, lui, rafraîchit l'état réel à chaque plan et propose de supprimer la règle.
5. **Échec.** `--parameter taille_volume=500` : refusé à la validation (`range`). Pour un vrai dépassement de quota, mets la limite haute du gabarit au-dessus du quota de Go : la pile passe `CREATE_FAILED` / `UPDATE_FAILED` avec le message de Cinder (« VolumeSizeExceedsAvailableQuota »). Repartir : `openstack stack update --rollback enabled …` (retour automatique à l'état précédent en cas d'échec), ou correction puis nouvelle mise à jour ; pour une création ratée, `stack delete`.
6. **Heat ou OpenTofu.** Heat : intégré au cloud (rien à installer pour les équipes, pas d'état à héberger), réagit dans le cloud (autoscaling, signaux), visible dans Horizon. OpenTofu : un seul outil pour Proxmox, NetBox, PowerDNS **et** OpenStack, plan lisible en MR, détection de la dérive, état versionné. Pour la recette de MédiAgenda, intégrée à leur CI et à nos MR, le corrigé retient OpenTofu (E31) ; Heat reste pertinent pour des piles autonomes que les équipes manipulent dans Horizon.

**Explications**

Une pile Heat est un objet du cloud : elle a un propriétaire (le projet), un état, un historique d'événements, et Heat agit avec un jeton de **délégation** (*trust*) de l'utilisateur qui l'a créée. Les politiques de mise à jour sont propres à chaque propriété : la documentation de chaque type de ressource dit « Can be updated without replacement » ou « Updates cause replacement ».

**Alternatives**
- *`OS::Heat::ResourceGroup`* pour N instances identiques (un gabarit imbriqué par instance).
- *Gabarit + fichier d'environnement par environnement* (`recette-dev.env.yaml`, `recette-prod.env.yaml`) : un code, plusieurs paramétrages.

**Pièges classiques**
- IP flottante sans dépendance sur l'interface du routeur : échec aléatoire selon l'ordre parallèle.
- Paramètre passé seulement en ligne de commande : oublié à la mise à jour suivante (Heat réutilise les paramètres précédents avec `--existing`, pas sans).
- Pile supprimée, volume « orphelin » : non, Heat supprime ce qu'il a créé ; mais un volume créé **à la main** et attaché par la pile reste.
- `heat_template_version` trop récent (`2023-…`) : n'existe pas, le dernier est `2021-04-16`.

**En production chez MédiSphère**
Gabarits versionnés et validés en CI (`openstack orchestration template validate` contre un projet de test), quotas de piles Heat, et suppression automatique des piles de recette inactives.

---

### M10-E15 — OpenTofu et le provider OpenStack

**Solution**

Fichiers : [`envs/openstack-projets/`](fichiers/M10-E15/infra/envs/openstack-projets/) (`versions.tf`, `chiffrement.tf`, `providers.tf`, `variables.tf`, `main.tf`, `imports.tf`, `outputs.tf`, `terraform.tfvars`, `README.md`), [`adm01/creer-identite-tofu.sh`](fichiers/M10-E15/adm01/creer-identite-tofu.sh), [`openstack-tofu.env.exemple`](fichiers/M10-E15/openstack-tofu.env.exemple), [`gitlab-ci-openstack-projets.extrait.yml`](fichiers/M10-E15/infra/gitlab-ci-openstack-projets.extrait.yml).

1. **Identité.**
   ```
   admin@adm01:~$ OS_CLOUD=medisphere-admin ./creer-identite-tofu.sh
   ```
   Le script ([`adm01/creer-identite-tofu.sh`](fichiers/M10-E15/adm01/creer-identite-tofu.sh), sur le modèle de l'identité de la sonde de E26) crée `svc-tofu` dans `Default` (mot de passe tapé), lui donne `admin` sur le projet `admin`, puis, **en tant que `svc-tofu`** (Keystone l'impose : une application credential se crée pour soi), crée `tofu-openstack-projets` avec une expiration à 90 jours et écrit l'identifiant et le secret **directement** dans `~/.config/workbook/openstack-tofu.env` (600), sans les afficher. Le mot de passe de `svc-tofu` est ensuite remplacé par une valeur aléatoire oubliée. L'application credential porte les rôles de son propriétaire **au moment de son usage** : si `svc-tofu` perd `admin` sur `admin`, elle ne peut plus s'authentifier avec ce rôle ; si le compte est désactivé ou supprimé, elle cesse de fonctionner. `--unrestricted` lui permettrait de créer d'autres application credentials et des *trusts* (une fuite deviendrait une persistance) : on ne le met pas.

2. **Configuration** : voir les fichiers. Points clés : provider sans aucun argument d'authentification (variables `OS_*`), `insecure = false` et `OS_CACERT` vers la racine MédiSphère ; `for_each = var.projets` ; `tenant_id` sur chaque ressource Neutron (un administrateur crée **pour** le projet) ; seulement des ressources `openstack_networking_*` pour le réseau (rien de supprimé en 3.0) ; étiquettes `tofu`.

3. **Import.** `imports.tf` : trois blocs `import` avec `for_each`, identifiants `<id du projet>/RegionOne`. Plan attendu :
   ```
   admin@adm01:~/src/infra/envs/openstack-projets$ . ../../outils/charger-acces.sh && tofu init && tofu plan
   openstack_compute_quotaset_v2.q["mediagenda-dev"]: Preparing import…
   …
   Plan: 6 to import, 14 to add, 0 to change, 0 to destroy.
   ```
   « 0 to change » prouve que `terraform.tfvars` reprend exactement les quotas de E13. ⚠️ À vérifier sur ton lab : l'identifiant d'import référence une source de données ; si ta version d'OpenTofu refuse (valeur inconnue au plan), écris les identifiants des projets en dur dans le bloc. Après l'apply, retirer `imports.tf` (MR suivante).

4. **Pipeline** : extrait `.gitlab-ci.yml` (`plan:openstack-projets` en MR, `apply:openstack-projets` manuel sur `main`, `resource_group`). Variables protégées et masquées : `OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET`. `runner01` doit joindre la VIP externe 10.10.50.201 sur 5000 (Keystone) et les ports des API de Nova (8774), Neutron (9696), Cinder (8776) : flux INFRA → VLAN 50 à ouvrir dans la matrice ([extrait](fichiers/M10-E15/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), ref M10-E15 ; Octavia 9876 y figure déjà pour E16) ; et le catalogue doit annoncer des points d'accès **publics** que `runner01` résout (`OS_INTERFACE=public`).

5. **Vérification.**
   ```
   admin@adm01:~$ openstack network list --project mediagenda-dev --long -c Name -c Tags
   admin@adm01:~$ openstack network show mediagenda-dev-net -c mtu        # 1500 (path_mtu de E12)
   admin@adm01:~$ openstack quota set --instances 10 <id de mediagenda-prod>
   admin@adm01:~/src/infra/envs/openstack-projets$ tofu plan
   ~ openstack_compute_quotaset_v2.q["mediagenda-prod"]  instances: 10 -> 4
   ```
   La dérive est visible ; l'apply la corrige.

6. **Réponses.** Le réseau appartient au projet (`tenant_id`) pour que l'équipe le voie, y attache ses instances, et que ses quotas comptent ses ports ; un réseau de `plateforme` partagé par RBAC serait visible de l'équipe mais pas à elle (elle ne pourrait pas y ajouter un sous-réseau). Les ressources de quota ont une suppression **sans effet** (documentation du provider) : un `tofu destroy` retire les quotas de l'état et laisse les valeurs en place ; RB-100 prévoit leur remise à zéro.

**Explications**

Une application credential est un secret **lié à un utilisateur et à un projet**, révocable sans toucher au mot de passe de l'utilisateur, avec expiration, et éventuellement limité par des règles d'accès : c'est l'équivalent d'un jeton d'API. OpenTofu ne fait qu'appeler les mêmes API que la CLI ; ce qu'il ajoute, c'est l'état (ce qu'il possède), le plan (ce qu'il va faire) et la revue. Séparer la création des **projets** (code d'identité de E05, Ansible) du **socle** (OpenTofu) évite qu'un `destroy` raté supprime un projet et tout ce qu'il contient.

**Alternatives**
- *Projets aussi en code* (`openstack_identity_project_v3`, attributions par `openstack_identity_role_assignment_v3`) : tout en un endroit ; un état qui peut supprimer un projet, donc `prevent_destroy` obligatoire.
- *Une application credential par projet* (rôle `member` seulement, une configuration racine par équipe) : moindre privilège réel, mais les quotas restent hors de portée d'un membre.
- *Heat* (E14) pour le socle : intégré, mais sans plan relu en MR.

**Pièges classiques**
- `tenant_id` oublié sur une règle de groupe de sécurité : la règle est créée dans `plateforme`, et Neutron refuse (groupe d'un autre projet) ou, pire, elle atterrit ailleurs.
- `openstack_compute_secgroup_v2` ou `openstack_compute_floatingip_v2` recopiés d'un vieux tutoriel : erreur « resource type not supported » avec le provider 3.x.
- Secret de l'application credential perdu : il n'est affiché qu'une fois ; on en recrée une, on ne le « retrouve » pas.
- Expiration oubliée : la CI échoue un lundi, 90 jours plus tard. Alerte à J-15 dans le registre des secrets.
- `OS_CACERT` absent sur `runner01` : `x509: certificate signed by unknown authority`, ou pire, quelqu'un ajoute `insecure = true`.

**En production chez MédiSphère**
Rotation automatisée de l'application credential (nouvelle, mise à jour de la variable CI, suppression de l'ancienne), règles d'accès restreignant les chemins d'API, plan de dérive nocturne comme pour les autres états, et alerte si un quota diffère du code.

---

### M10-E16 — Octavia : répartiteurs de charge à la demande

**Solution**

Fichiers : [`globals.d/16-octavia.yml`](fichiers/M10-E16/openstack/etc/kolla/globals.d/16-octavia.yml), [`config/octavia.conf`](fichiers/M10-E16/openstack/etc/kolla/config/octavia.conf), [`outils/lb-e16.sh`](fichiers/M10-E16/openstack/outils/lb-e16.sh), [`cloud-init/web-user-data.yaml`](fichiers/M10-E16/openstack/cloud-init/web-user-data.yaml), [`octavia.tf`](fichiers/M10-E16/infra/envs/openstack-projets/octavia.tf).

1. **Limites du fournisseur OVN** (documentation *ovn-octavia-provider*, *Limitations*) : protocoles **TCP, UDP et SCTP** seulement, donc **pas de L7** (pas de routage par chemin ni par en-tête, pas d'écouteur HTTP/HTTPS, pas de terminaison TLS) ; un écouteur et son pool ont le même protocole ; un seul algorithme, **`SOURCE_IP_PORT`** (ni `ROUND_ROBIN`, ni `LEAST_CONNECTIONS`) ; contrôles de santé TCP et UDP-CONNECT (pas SCTP) ; pas de mélange IPv4/IPv6 dans les membres. Ce qu'on gagne : aucune VM d'amphore (ni image à construire, ni mémoire consommée sur nos calculs de 8 Go, ni certificats), et la haute disponibilité est intrinsèque (flux injectés sur tous les nœuds) : pas de *failover* à gérer.

2. **Activation.** `globals.d/16-octavia.yml` et `octavia.conf` (`default_provider_driver = ovn`). En ne listant que `ovn`, les valeurs par défaut de Kolla (`group_vars/all/octavia.yml`) font `octavia_auto_configure: false` et `enable_octavia_jobboard: false` : pas de ressources d'amphores, pas de Valkey. Déploiement : `kolla-ansible deploy -t octavia,horizon` (le panneau « Load Balancers » de Horizon est activé par `enable_horizon_octavia`, qui suit `enable_octavia` : il faut redéployer Horizon). Contrôles :
   ```
   admin@adm01:~$ openstack loadbalancer provider list
   | name | description  |
   | ovn  | OVN provider |
   admin@osctl01:~$ sudo docker ps --format '{{.Names}}' | grep octavia
   octavia_api  octavia_driver_agent  octavia_worker  octavia_health_manager  octavia_housekeeping
   ```
   Utiles sans amphores : `octavia_api` (API), `octavia_driver_agent` (reçoit les mises à jour de statut d'OVN, déployé quand `neutron_plugin_agent` vaut `ovn`). `worker`, `health_manager`, `housekeeping` sont déployés par le rôle mais n'ont rien à faire sans amphores (ils consomment un peu de mémoire ; les retirer demanderait de sortir du rôle standard : non).

3. **Quota** : `openstack loadbalancer quota set --loadbalancer 2 --listener 4 --pool 4 --member 20 --healthmonitor 4 <projet>` pour les deux projets de MédiAgenda ; dans le code, `octavia.tf` (`openstack_lb_quota_v2` existe dans le provider 3.4, import `<projet>/RegionOne`) ; ligne « Répartiteurs » de `capacite.md`.

4. **Création** (`lb-e16.sh`, en membre de `mediagenda-dev`). Les essais refusés :
   ```
   admin@adm01:~$ openstack loadbalancer listener create --protocol HTTP --protocol-port 80 lb-e16
   Provider 'ovn' does not support a requested option: OVN provider does not support HTTP protocol (HTTP 501)
   admin@adm01:~$ openstack loadbalancer pool create --protocol TCP --lb-algorithm ROUND_ROBIN --listener ecoute-80
   Provider 'ovn' does not support a requested option: OVN provider does not support ROUND_ROBIN algorithm (HTTP 501)
   ```
   (Libellés à vérifier sur ta version ; le code 501 « not implemented » et la mention du fournisseur sont la règle.) Un membre du projet suffit : en 2026.1, la règle `load-balancer:write` d'Octavia est `rule:load-balancer:member_and_owner` = `rule:project-member`, appliquée parce qu'oslo.policy active `enforce_new_defaults` par défaut depuis la série 2024.2. ⚠️ À vérifier sur ton lab : si Julien reçoit un 403, ton Octavia applique encore les anciennes règles ; donne alors au groupe `equipe-mediagenda` le rôle `load-balancer_member` (Kolla le crée, `octavia_required_roles`) sur `mediagenda-dev`, dans le code d'identité de E05.

5. **IP flottante** sur `vip_port_id`, puis :
   ```
   admin@adm01:~$ for i in $(seq 10); do curl -s http://<IP-FLOTTANTE>/; done | sort | uniq -c
        10 e16-web2
   admin@adm01:~$ for i in $(seq 10); do curl -s --local-port $((40000+i)) http://<IP-FLOTTANTE>/; done | sort | uniq -c
         6 e16-web1
         4 e16-web2
   ```
   `SOURCE_IP_PORT` hache le couple (adresse, port) source : chaque nouvelle connexion de `curl` prend un port éphémère différent, la répartition existe ; mais les tests depuis une seule machine se concentrent souvent, et un client derrière un NAT unique (toute une agence) suit toujours le même hachage pour une même connexion.

6. **Panne d'un membre.** `sudo systemctl stop nginx` sur `e16-web1` : `openstack loadbalancer member list pool-web -c name -c operating_status` passe `ERROR` après `delay × max_retries` (≈ 10 s ici) ; les nouvelles connexions ne vont plus que vers `e16-web2`. Le contrôle de santé OVN part d'un port de service créé dans le sous-réseau des membres (`ovn-lb-hm-<id du sous-réseau>`) : si le groupe de sécurité des membres ne l'autorise pas, **tous** les membres sont `ERROR` (piège classique, d'où l'autorisation du CIDR du projet dans `e16-web`).

7. **Dans OVN.**
   ```
   admin@osctl01:~$ sudo docker exec ovn_northd ovn-nbctl lb-list
   UUID   LB            PROTO  VIP              IPs
   …      ovn-lb-…      tcp    192.168.110.x:80 192.168.110.a:80,192.168.110.b:80
   ```
   Le répartiteur est un objet de la base nord d'OVN, attaché au commutateur logique et au routeur ; `ovn-controller` le traduit en flux OpenFlow sur **chaque** nœud qui en a besoin. Le trafic d'un client est réparti là où il entre (le *gateway chassis* pour l'IP flottante, le calcul de l'instance cliente pour un trafic interne) : pas de VM, pas de processus unique à perdre.

8. **Réponse à Julien.** Le répartiteur OVN fait le L4. Pour HTTPS et le routage par chemin, deux voies : (a) publier MédiAgenda par `lb01`/`lb02` (HAProxy du module 07, certificat ACME, règles par chemin) vers l'IP flottante du répartiteur OVN, quand l'application sortira du lab ; (b) dans le projet, deux instances HAProxy (ou nginx) derrière le répartiteur OVN en TCP 443, qui terminent TLS et routent par chemin. Le fournisseur `amphora` ferait tout cela en libre-service, mais coûte une VM (1 Go) par répartiteur et une chaîne de construction d'image : non retenu pour notre capacité (ADR-0100, E30).

**Explications**

Octavia est une API (objets : répartiteur, écouteur, pool, membre, contrôle de santé) et des **fournisseurs** qui l'implémentent. `amphora` crée une VM HAProxy par répartiteur (L7 complet, TLS par Barbican) ; `ovn` traduit les objets en répartiteurs OVN natifs (L4 distribué). Le choix du fournisseur est donc un choix de fonctionnalités, pas seulement de technique.

**Alternatives**
- *Fournisseur amphora* : tout le L7 et le TLS, au prix d'images, d'un réseau de gestion, de certificats et de mémoire.
- *Répartiteur dans le projet* (HAProxy + keepalived sur deux instances, avec une adresse « allowed-address-pair ») : la méthode d'avant Octavia, entièrement à la charge de l'équipe.

**Pièges classiques**
- `--provider ovn` oublié et défaut non changé : « Provider 'amphora' is not enabled ».
- Groupe de sécurité des membres sans le port de service du contrôle de santé : tous les membres en `ERROR`.
- IP flottante associée au port d'une **instance** au lieu de `vip_port_id`.
- Tester depuis un membre vers l'adresse virtuelle : selon la version d'OVN, le retour vers soi-même (*hairpin*) peut ne pas fonctionner.

**En production chez MédiSphère**
Quotas Octavia par projet, contrôle de santé obligatoire (politique de revue), supervision du statut des membres (E26), et publication externe seulement par `lb01`/`lb02` avec TLS.

---

### M10-E17 — Horizon et l'accès des équipes

**Solution**

Fichiers : [`globals.d/17-horizon.yml`](fichiers/M10-E17/openstack/etc/kolla/globals.d/17-horizon.yml), [`horizon/_9999-custom-settings.py`](fichiers/M10-E17/openstack/etc/kolla/config/horizon/_9999-custom-settings.py), [`pare_feu.yml.extrait`](fichiers/M10-E17/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait).

1. **Depuis le VPN** : délai dépassé. Horizon appelle Keystone, Nova, Neutron **depuis le conteneur `horizon`** (points d'accès internes, VIP .200) : le navigateur n'a besoin que du port 443 de la VIP externe… et du 6080 (noVNC) dès qu'il ouvre une console, car la page de console charge un `iframe` vers `https://openstack.par1.medisphere.internal:6080/`. Deux flux, rien d'autre.
2. **Multi-domaines** : `horizon_keystone_multidomain: "yes"` et `horizon_keystone_domain_choices` à deux entrées (liste déroulante, `medisphere` d'abord) ; `_9999-custom-settings.py` : `SESSION_TIMEOUT = 1800`, `SESSION_COOKIE_AGE = 1800`, `OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = "medisphere"`. Vérifié par `python3 -m py_compile` avant la MR. `kolla-ansible deploy -t horizon` (ou `reconfigure -t horizon`), puis :
   ```
   admin@osctl01:~$ sudo cat /etc/kolla/horizon/_9999-custom-settings.py
   admin@osctl01:~$ sudo grep -E 'MULTIDOMAIN|DOMAIN_DROPDOWN' /etc/kolla/horizon/_9998-kolla-settings.py
   OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
   OPENSTACK_KEYSTONE_DOMAIN_DROPDOWN = True
   ```
3. **Flux** : une ligne, VPN → 10.10.50.201, TCP 443 et 6080 (extrait). Les ports des API ne sont pas ouverts au VPN : décision de sécurité reportée au palier 3.
4. **Julien** : domaine `medisphere`, il voit ses projets dans le sélecteur ; console et redémarrage dans `mediagenda-dev` ; `mediagenda-prod` : en `reader` (E13), il voit les instances sans les boutons d'action (Horizon évalue les politiques). S'il n'a aucun rôle sur un projet, ce projet n'apparaît pas.
5. **clouds.yaml** : *Identité → Application credentials → Créer*, puis « Télécharger le fichier clouds.yaml » : `auth_type: v3applicationcredential`, `auth_url`, identifiant et **secret**, `region_name`, `interface`. Il manque la confiance TLS : sur le poste de Julien, la racine MédiSphère dans le magasin du système, ou `cacert:` dans le fichier. Le secret est dans ce fichier : il se range comme une clé privée (600, hors de tout dépôt).
6. **Contrôles.**
   ```
   admin@adm01:~$ curl -sI https://openstack.par1.medisphere.internal/auth/login/ | grep -iE 'set-cookie|strict-transport|x-frame'
   admin@adm01:~$ curl -sI http://openstack.par1.medisphere.internal/ | head -3
   admin@adm01:~$ openssl s_client -connect openstack.par1.medisphere.internal:443 -servername openstack.par1.medisphere.internal </dev/null 2>/dev/null | openssl x509 -noout -issuer -dates
   ```
   Cookies `Secure` (Kolla les pose quand TLS est actif) ; HSTS absent (à décider au palier 3) ; le port 80 de la VIP externe répond par une **redirection** vers HTTPS (Kolla publie Horizon en 443 quand `kolla_enable_tls_external` est actif, et ajoute un *frontend* `horizon_external_redirect` sur le port 80 : rôle `horizon`, 22.2.0).

**Explications**

Horizon est une application Django sans base de données propre (sessions en cache memcached ou Valkey) : chaque clic devient des appels d'API faits **au nom de l'utilisateur**, avec son jeton. Il ne donne donc aucun droit de plus que la CLI. Le multi-domaine change seulement la page de connexion (champ ou liste de domaines) : sans lui, Horizon authentifie tout le monde dans le domaine `Default`, où nos comptes n'existent pas.

**Alternatives**
- *Champ libre* plutôt que liste déroulante (une seule entrée dans `horizon_keystone_domain_choices`) : ne révèle pas la liste des domaines, oblige à connaître le nom.
- *Skyline* (nouveau tableau de bord, rôle Kolla `skyline`) : interface moderne, moins de panneaux ; à évaluer.

**Pièges classiques**
- Erreur de syntaxe dans `_9999-custom-settings.py` : Horizon répond 500 partout.
- Ouvrir 443 mais pas 6080 : tout fonctionne sauf la console (« Failed to connect to server »).
- Domaine `medisphere` oublié dans les choix : liste déroulante sans le bon domaine.
- Secret d'application credential envoyé par courriel avec le `clouds.yaml`.

**En production chez MédiSphère**
Authentification unique (WebSSO, module 24), HSTS et en-têtes de sécurité vérifiés à chaque mise à jour, journal des connexions à Horizon envoyé à la journalisation centrale, et session courte imposée.

---

### M10-E18 — Métadonnées et cloud-init dans OpenStack

**Solution**

Fichiers : [`nova/vendordata.json`](fichiers/M10-E18/openstack/etc/kolla/config/nova/vendordata.json) (et sa source lisible [`cloud-init/vendordata.source.yaml`](fichiers/M10-E18/openstack/cloud-init/vendordata.source.yaml)), [`cloud-init/e18-user-data.yaml`](fichiers/M10-E18/openstack/cloud-init/e18-user-data.yaml), [`docs/cloud/diagnostic-cloud-init.md`](fichiers/M10-E18/medisphere/docs/cloud/diagnostic-cloud-init.md).

1. **Le chemin.**
   ```
   debian@e18-vm:~$ curl -s http://169.254.169.254/openstack/latest/meta_data.json | jq '{uuid, name, meta}'
   debian@e18-vm:~$ curl -s http://169.254.169.254/openstack/latest/vendor_data.json
   admin@oscmp01:~$ sudo ip netns | grep ovnmeta
   ovnmeta-<id du réseau>
   admin@oscmp01:~$ sudo ip netns exec ovnmeta-<id du réseau> ip -4 a | grep 169.254
   admin@osctl01:~$ sudo grep "GET /openstack/latest/meta_data.json" /var/log/kolla/nova/nova-metadata.log | tail -2
   ```
   L'instance parle à 169.254.169.254 sur son réseau ; OVN dirige ce trafic vers le port de métadonnées du réseau, dont l'autre extrémité est l'espace de noms `ovnmeta-…` **du calcul de l'instance**, où un `haproxy` lancé par `neutron_ovn_metadata_agent` ajoute les en-têtes d'identification (identifiant d'instance, signé par `metadata_proxy_shared_secret`) et relaie vers `nova-metadata` sur `osctl01`.
2. **Données utilisateur** (`e18-user-data.yaml`, gabarit Jinja de cloud-init) et création :
   ```
   admin@adm01:~$ openstack server create --wait --image debian-13 --flavor m1.petit --key-name cle-adm01 --network reseau-plateforme \
       --security-group ssh-icmp-admin --property role=web --user-data e18-user-data.yaml e18-vm
   debian@e18-vm:~$ cloud-init status --long ; cat /etc/medisphere/role
   web
   debian@e18-vm:~$ cloud-init query ds.meta_data.meta
   ```
   ⚠️ À vérifier sur ton lab : le chemin `ds.meta_data.meta.role` (lis `cloud-init query --all`) ; s'il diffère, adapte le gabarit.
3. **Données fournisseur.** `vendordata.json` : un objet JSON dont la clé `cloud-init` contient un document `#cloud-config` (racine MédiSphère par `ca_certs`, chrony vers 10.10.52.1 par `ntp`). Kolla le copie dans `nova-api` et `nova-metadata` et pose `vendordata_jsonfile_path` (rôle `nova`, tâche `config`). `kolla-ansible reconfigure -t nova`, contrôle `sudo cat /etc/kolla/nova-metadata/vendordata.json` sur `osctl01`. Dans une instance **recréée** : `chronyc sources` montre 10.10.52.1 ; `ls /usr/local/share/ca-certificates/` contient le certificat posé par cloud-init. Les données utilisateur **l'emportent** : si elles contiennent `ntp:`, leur valeur remplace celle des données fournisseur (fusion par clé de haut niveau) ; un utilisateur peut même désactiver les données fournisseur (`vendor_data: {enabled: false}`). Ce sont des réglages **par défaut**, pas une politique imposée : la politique imposée, c'est la bordure (E12).
4. **Sans DHCP.**
   ```
   admin@adm01:~$ openstack network create e18-sans-dhcp
   admin@adm01:~$ openstack subnet create --network e18-sans-dhcp --subnet-range 192.168.180.0/24 --no-dhcp --dns-nameserver 10.10.20.10 e18-sans-dhcp
   admin@adm01:~$ openstack router add subnet <routeur du projet> e18-sans-dhcp
   admin@adm01:~$ openstack server create --wait … --network e18-sans-dhcp e18-cd       # sans config drive
   admin@adm01:~$ openstack console log show e18-cd | grep -iE "dhcp|169.254|ci-info"
   ```
   Sans config drive : aucune adresse (pas de DHCP), aucune métadonnée (pas de port de métadonnées dans ce réseau), cloud-init attend puis abandonne ; pas de clé SSH. Avec `--use-config-drive` : un disque `config-2` porte les mêmes fichiers, dont `network_data.json` (adresse fixe allouée par Neutron, passerelle, DNS) ; cloud-init écrit une configuration **statique**. L'instance est joignable (par une IP flottante, ou depuis une autre instance).
5. **Agent arrêté.** `sudo docker stop neutron_ovn_metadata_agent` sur le calcul, nouvelle instance forcée sur ce calcul (`--availability-zone nova:oscmp01`, administrateur) : la console montre des tentatives vers 169.254.169.254 qui échouent (≈ 120 s) ; l'instance démarre sans clé SSH ni paquets. Journaux : rien côté `nova-metadata` (la requête n'arrive jamais), erreurs dans `neutron-ovn-metadata-agent.log` au redémarrage de l'agent. Les instances **existantes** ne sont pas touchées (cloud-init ne lit les métadonnées qu'au premier démarrage, sauf modules « par démarrage »). `sudo docker start neutron_ovn_metadata_agent`.
6. **Runbook pour Nadia** : `diagnostic-cloud-init.md`.

**Explications**

Trois sources, trois propriétaires : les **métadonnées** viennent d'OpenStack (identité, clés, réseau, propriétés `--property`), les **données utilisateur** de l'équipe (une par instance, figées à la création), les **données fournisseur** de l'opérateur (les mêmes pour toutes les instances). cloud-init les fusionne avec une priorité claire : utilisateur > fournisseur. Le service de métadonnées n'est qu'un moyen de transport ; le config drive en est un autre, indépendant du réseau.

**Alternatives**
- *`force_config_drive = True`* (surcharge `nova.conf`) : config drive pour toutes les instances, plus de dépendance au service de métadonnées au premier démarrage ; les données restent figées (pas de mise à jour des métadonnées visibles par l'instance).
- *Données fournisseur dynamiques* (`DynamicJSON`) : un service externe calcule les données par instance ; puissant, mais un point de panne de plus au démarrage.
- *Image dorée* qui contient déjà la CA et la configuration de chrony (module 03) : rien à transmettre, mais une image par cloud.

**Pièges classiques**
- `#cloud-config` qui n'est pas la toute première ligne (ou précédée d'une ligne vide) : données ignorées. Avec un gabarit Jinja, `## template: jinja` en premier, `#cloud-config` en second.
- `vendordata.json` invalide (JSON) : `nova-api` refuse de démarrer ou ignore le fichier ; `jq .` avant la MR.
- Données fournisseur modifiées, instances existantes inchangées : elles ne relisent pas.
- Un réseau sans DHCP et une image sans prise en charge du config drive.

**En production chez MédiSphère**
`force_config_drive` pour les réseaux de production, données fournisseur versionnées et relues comme du code, supervision de `neutron_ovn_metadata_agent` sur chaque calcul (E26) et test de démarrage d'une instance de contrôle chaque nuit.

---

### M10-E19 — Exploiter le calcul : migrer, évacuer, désactiver

**Solution**

1. **État.**
   ```
   admin@adm01:~$ export OS_CLOUD=medisphere-admin
   admin@adm01:~$ openstack compute service list --service nova-compute --long
   admin@adm01:~$ openstack hypervisor list --long
   admin@adm01:~$ openstack server list --all-projects --host oscmp02 -c Name -c Status
   admin@adm01:~$ openstack resource provider allocation show <uuid de e19-a>
   ```
2. **Maintenance.**
   ```
   admin@adm01:~$ openstack compute service set --disable --disable-reason "CHG-1129 mise à jour noyau" oscmp02 nova-compute
   admin@adm01:~$ openstack server create --wait … e19-test ; openstack server show e19-test -c OS-EXT-SRV-ATTR:host   # oscmp01
   debian@e19-test:~$ ping -D -i 0.2 <adresse de e19-a> | tee ping.log           # pendant la migration
   admin@adm01:~$ openstack server migrate --live-migration --host oscmp01 --wait e19-a
   admin@adm01:~$ openstack server migrate --live-migration --host oscmp01 --wait e19-b
   admin@adm01:~$ openstack server list --all-projects --host oscmp02          # vide
   root@pve01:~# qm reboot 2103                                                 # à la place de la mise à jour
   admin@adm01:~$ openstack compute service set --enable oscmp02 nova-compute
   admin@adm01:~$ openstack server migrate --host oscmp02 --wait e19-a          # à froid
   admin@adm01:~$ openstack server migration confirm e19-a                      # VERIFY_RESIZE -> ACTIVE
   admin@adm01:~$ openstack server migration list --server e19-a -c "Migration Type" -c Status -c "Source Node" -c "Dest Node"
   ```
   Coupure vue par le `ping` : quelques paquets perdus au plus (la bascule finale dure une fraction de seconde) ; disque sur Ceph : seule la mémoire est copiée. La migration à froid **arrête** l'instance, la redémarre sur l'autre calcul et attend une **confirmation** : c'est la même mécanique qu'un redimensionnement, qui laisse la possibilité de revenir (`migration revert`) tant qu'on n'a pas confirmé. Nova confirme seul après `resize_confirm_window` si cette option est réglée (0 = jamais, valeur par défaut).
3. **Redimensionnement.** `openstack server resize --flavor m1.moyen --wait e19-b` → `VERIFY_RESIZE` ; `openstack server resize confirm e19-b` → `ACTIVE`. Non confirmé : l'instance reste en `VERIFY_RESIZE`, l'ancienne allocation reste comptée dans Placement (sur l'hôte source, au nom de la migration), et elle bloque d'autres opérations ; `revert` reviendrait à `m1.petit`.
4. **Panne.**
   ```
   admin@adm01:~$ openstack server create --wait … --availability-zone nova:oscmp02 e19-evac ; (écrire un fichier dans e19-evac)
   root@pve01:~# qm stop 2103 && qm status 2103          # status: stopped — isolement constaté
   admin@adm01:~$ watch -n5 openstack compute service list --service nova-compute
   admin@adm01:~$ openstack server show e19-evac -c status -c OS-EXT-SRV-ATTR:host   # ACTIVE, oscmp02 (Nova ne sait rien)
   admin@adm01:~$ openstack server evacuate --host oscmp01 --wait e19-evac
   ```
   Nova voit `oscmp02` `down` après `service_down_time` (60 s) sans battement de cœur. Pendant ce temps, l'instance apparaît toujours `ACTIVE` sur `oscmp02` : Nova ne sait pas qu'elle est morte. L'évacuation n'est acceptée que si le service est `down` ; l'hôte cible est facultatif (l'ordonnanceur choisit ; préciser l'hôte, microversion récente, contourne une partie des filtres). Disque sur Ceph : l'instance est **recréée** sur `oscmp01` avec **son** disque `vms/<uuid>_disk` (fichier présent) ; sur disque local, elle aurait été reconstruite depuis l'image.
5. **Retour.** `qm start 2103` ; au démarrage, `nova-compute` lit les migrations de type `evacuation` dont il est la source et détruit les domaines libvirt correspondants (journal : « Deleting instance as it has been evacuated from this host ») ; `sudo docker exec nova_libvirt virsh list --all` sur `oscmp02` ne la montre plus. Sans cette garde, l'instance redémarrerait sur `oscmp02` et écrirait sur le même disque que sa copie : corruption.
6. **Qui éteint ?** L'isolement (*fencing*) est fait par la supervision ou par un service dédié : coupure d'alimentation par l'IPMI/iLO (module 11), ou Masakari (moniteurs d'hôtes et d'instances, Pacemaker/Corosync pour décider qu'un hôte est mort, puis évacuation automatique). Jamais un humain qui « pense » que le calcul est mort.

**Explications**

`disable` agit sur l'**ordonnanceur** (plus de nouvelles instances) ; `down` est un **constat** (plus de battement de cœur) ou une **déclaration** (`--down`, *forced down*) ; migrer et évacuer sont deux opérations différentes : la migration a besoin des **deux** calculs vivants (copie de la mémoire, à chaud, ou arrêt-relance, à froid), l'évacuation reconstruit l'instance à partir de son disque, sans la source. Placement suit chaque étape par des allocations « au nom de la migration » : c'est ce qui permet d'annuler proprement.

**Alternatives**
- *Migration à chaud avec copie du disque* (`--block-migration`) : pour des disques locaux ; inutile et plus lent ici.
- *Client historique `nova host-evacuate-live`* : vider un hôte en une commande ; avec le client `openstack`, une boucle sur `server list --host`.

**Pièges classiques**
- Évacuer sans isoler : deux instances sur un disque.
- Oublier de réactiver le service après maintenance : capacité perdue en silence (l'ordonnanceur l'ignore).
- `--down` posé et jamais retiré : le service redémarré reste considéré mort (`--up` pour le retirer).
- Migration à froid jamais confirmée : instances en `VERIFY_RESIZE` qui bloquent les opérations suivantes.

**En production chez MédiSphère**
RB-102 (évacuation, palier 3), Masakari ou une supervision qui coupe l'alimentation par l'iLO, fenêtres de maintenance annoncées aux équipes, et `server group` en `anti-affinity` pour que les deux instances applicatives d'une équipe ne soient jamais sur le même calcul.

---

### M10-E20 — Kolla au quotidien : surcharges, reconfiguration, journaux

**Solution**

Fichiers : [`nova/nova-compute.conf`](fichiers/M10-E20/openstack/etc/kolla/config/nova/nova-compute.conf), [`nova/oscmp02/nova.conf`](fichiers/M10-E20/openstack/etc/kolla/config/nova/oscmp02/nova.conf), [`outils/comparer-config.sh`](fichiers/M10-E20/openstack/outils/comparer-config.sh), [`README-changer-la-configuration.extrait.md`](fichiers/M10-E20/openstack/README-changer-la-configuration.extrait.md).

1. **Emplacements** (rôle `nova-cell`, tâche « Copying over nova.conf », dans `.venv/share/kolla-ansible/ansible/roles/nova-cell/tasks/config.yml`) : le gabarit du rôle, puis `global.conf`, `nova.conf`, `nova/<service>.conf` (ex. `nova/nova-compute.conf`), `nova/<hôte>/nova.conf` (relu dans 22.2.0 : il n'y a **pas** de `nova/<hôte>/<service>.conf` pour Nova). Fusion dans cet ordre, le dernier gagne.
2. **Surcharges** : `nova/nova-compute.conf` (réserve, tous les calculs, seulement `nova-compute`), `nova/oscmp02/nova.conf` (ratio, ce seul hôte). Prévisualisation :
   ```
   admin@adm01:~/src/openstack$ kolla-ansible genconfig -t nova
   admin@adm01:~/src/openstack$ outils/comparer-config.sh oscmp02 nova_compute /etc/kolla/nova-compute/nova.conf /etc/nova/nova.conf
   +cpu_allocation_ratio = 2.0
   +reserved_host_memory_mb = 2048
   admin@adm01:~/src/openstack$ outils/comparer-config.sh oscmp01 nova_compute /etc/kolla/nova-compute/nova.conf /etc/nova/nova.conf
   +reserved_host_memory_mb = 2048
   ```
   `genconfig` écrit dans `/etc/kolla/<service>/` sur les nœuds **sans** redémarrer ; le conteneur garde sa copie (`/etc/nova/nova.conf`, recopiée par `kolla_set_configs` au démarrage) : la différence entre les deux est exactement ce que le prochain redémarrage appliquera.
3. **`validate-config -t nova`** : passe la configuration générée à `oslo-config-validator` avec le schéma de Nova : options inconnues (faute de frappe), sections inexistantes, valeurs hors type. Il ne verra jamais une **valeur** valide mais fausse (2.0 au lieu de 0.2), une option au mauvais endroit mais existante, ni l'effet d'un réglage sur l'ordonnanceur.
4. **Application.** `kolla-ansible reconfigure -t nova` : `nova_compute` redémarre sur les **deux** calculs (sa configuration a changé partout : la réserve), et sur aucun autre conteneur (`nova_libvirt`, `nova_ssh` lisent aussi `nova/oscmp02/nova.conf`, mais leur fichier généré n'a changé que de lignes qu'ils n'utilisent pas… ⚠️ à vérifier : si leur `nova.conf` généré change, Kolla les redémarre aussi ; regarde la colonne *Status* de `docker ps`). Placement :
   ```
   admin@adm01:~$ openstack resource provider inventory show <uuid oscmp02> VCPU -c allocation_ratio
   2.0
   admin@adm01:~$ openstack resource provider inventory show <uuid oscmp02> MEMORY_MB -c reserved
   2048
   ```
   `nova-compute` pousse ses inventaires dans Placement à chaque cycle de mise à jour (et au démarrage). Ce que la configuration fixe ne se modifie donc plus à la main dans Placement : si quelqu'un change le ratio par l'API de Placement, `nova-compute` remet le sien au cycle suivant.
5. **Journaux.** Surcharge `neutron.conf` `[DEFAULT] debug = True`, `reconfigure -t neutron`, création d'un port, `sudo grep req-<id> /var/log/kolla/neutron/neutron-server.log` (l'identifiant de requête est renvoyé par `openstack --debug`), retrait, `reconfigure -t neutron`. Rotation : le conteneur `cron` exécute `logrotate` sur `/var/log/kolla/` (configuration générée par Kolla, quotidienne avec rétention) ; `fluentd` lit aussi ces fichiers pour la journalisation centrale quand elle est activée.
6. **Conteneurs malsains.**
   ```
   admin@adm01:~$ for h in osctl01 oscmp01 oscmp02; do ssh $h 'sudo docker ps --filter health=unhealthy --format "{{.Names}}"'; done
   admin@oscmp01:~$ sudo docker inspect --format '{{json .Config.Healthcheck}}' nova_libvirt
   {"Test":["CMD-SHELL","virsh version --daemon"],"Interval":30000000000,"Timeout":30000000000,…}
   ```
   Le contrôle de santé de `nova_libvirt` demande au démon libvirt sa version : s'il ne répond pas, le conteneur passe `unhealthy` après `Retries` échecs. Les services API ont `healthcheck_curl` sur leur port ; les agents, `healthcheck_port` (connexion à RabbitMQ établie). Un conteneur malsain n'est **pas** redémarré par Docker : Kolla compte sur la supervision (E26).
7. **README** : extrait fourni.

**Explications**

Kolla sépare trois choses : le **dépôt** (ce qu'on veut), la **configuration générée** sur chaque nœud (`/etc/kolla/<service>/`, ce que Kolla a calculé), et la **configuration du conteneur** (ce qui tourne). Un `reconfigure` régénère la deuxième et redémarre les conteneurs dont la deuxième ne correspond plus à la troisième. Modifier la deuxième à la main ne survit pas au passage suivant ; modifier la troisième (`docker exec … vi`) ne survit pas au redémarrage.

**Alternatives**
- *Variables Kolla* plutôt que surcharges (ex. `nova_libvirt_cpu_mode`, `openstack_logging_debug`) : testées par Kolla, documentées ; quand elles existent, elles gagnent.
- *Variables d'hôte* dans l'inventaire (`oscmp02 nova_cpu_allocation_ratio=2.0`) utilisées dans une surcharge Jinja : une seule surcharge pour tous les hôtes.

**Pièges classiques**
- `reconfigure` sans étiquette : tous les rôles repassent, des dizaines de conteneurs redémarrent.
- `--limit oscmp02` avec Nova : déconseillé par la documentation (problèmes connus avec `register`).
- Surcharge au mauvais nom de fichier (`nova/nova_compute.conf` avec un tiret bas) : ignorée sans erreur.
- Mode `debug` laissé : journaux énormes et données sensibles.

**En production chez MédiSphère**
`genconfig` + comparaison exécutés par la CI de `plateforme/openstack` sur une MR (artefact « ce qui va changer »), reconfigurations dans des fenêtres annoncées, et alerte sur tout conteneur `unhealthy` depuis plus de cinq minutes.

---

### M10-E21 — Revue : la configuration Kolla du prestataire

**Réponses à l'étape 1.** Les API répondraient sur **10.10.50.1**, l'adresse de la passerelle du VLAN 50 (VIP VRRP de `gw01`/`gw02`), avec un keepalived en **VRID 50** sur le même VLAN que celui des passerelles : conflit VRRP, le VLAN 50 perd sa passerelle. Sur `osctl01`, Kolla brancherait **`ens18`** (l'interface d'administration et d'API) dans le pont `br-ex` : `osctl01` perdrait son adresse en plein déploiement. Les services liraient et écriraient Ceph avec **`client.admin`** : tous les droits sur tout le cluster, y compris les pools de Kubernetes (M16) et de RGW.

**Revue** (ordre de traitement ; gravité dans **notre** lab)

| N° | Fichier : ligne(s) | Défaut | Cat. | Gravité | Impact chez nous | Correction |
|---|---|---|---|---|---|---|
| 1 | `config/glance/ceph.client.glance.keyring` ; `globals.yml` : 52-53 | Trousseau `client.admin` (droits `allow *`) fourni en clair et utilisé par Glance et Cinder (et Nova, qui hérite de l'utilisateur de Cinder) | Sécu. | Critique | Une compromission d'un conteneur OpenStack donne tout `ceph-par1` (pools de M16, RGW de MédiDoc, configuration du cluster) ; la clé est dans une archive transmise par un tiers : à considérer **brûlée** si elle était réelle | Clés `client.glance`, `client.cinder`, `client.cinder-backup`, `client.nova` à moindre privilège (E10) ; jamais de `client.admin` hors des nœuds Ceph ; trousseaux-gabarits, clés dans `passwords.yml` chiffré ; rotation de la clé admin si elle a circulé |
| 2 | `globals.yml` : 19, 22 | VIP interne 10.10.50.1 = passerelle du VLAN 50 ; `keepalived_virtual_router_id: "50"` = VRID de la passerelle du VLAN 50 (PLAN §4.9 : VRID = numéro de VLAN) | Fonct. | Critique | Deux routeurs VRRP différents se disputent l'adresse .1 avec le même VRID : le VLAN 50 perd sa passerelle (OS-API, donc toutes les API, coupées du lab), bascules en boucle | `kolla_internal_vip_address: "10.10.50.200"`, `keepalived_virtual_router_id: "150"` (unique sur le VLAN 50) |
| 3 | `globals.yml` : 17 | `neutron_external_interface: "ens18"`, l'interface d'API | Fonct. | Critique | Kolla ajoute `ens18` au pont OVS `br-ex` : l'adresse 10.10.50.51 devient inutilisable, `osctl01` injoignable pendant le déploiement (console pour réparer) | `neutron_external_interface: "ens21"` (OS-EXT, sans adresse, sur `osctl01` seulement) |
| 4 | `multinode` : 3-5 | `ansible_user=root` et mot de passe root en clair dans l'inventaire | Sécu. | Critique | Mot de passe root identique sur les trois nœuds, dans un dépôt ; connexion root par mot de passe ouverte (contraire au durcissement M04-E11) | Utilisateur `admin` + clé SSH + `become` (comme le reste du lab), rien dans l'inventaire |
| 5 | `globals.yml` : 60 | `keystone_admin_password` en clair dans `globals.yml` | Sécu. | Critique | Mot de passe d'administration du cloud dans Git ; `globals.yml` et `passwords.yml` sont passés tous deux en variables supplémentaires ; `passwords.yml`, chargé après, l'emporte : la ligne est sans effet sur le déploiement, mais le secret est dans Git (et la prochaine personne qui « corrige » l'ordre de chargement aurait deux sources de vérité) | Retirer la ligne ; le mot de passe est généré par `kolla-genpwd` dans `passwords.yml` (Vault `critique`), remis par la procédure du registre des secrets ; mot de passe à changer s'il a servi |
| 6 | `globals.yml` : 10-11 | Registre d'images du prestataire, en HTTP (`docker_registry_insecure`) | Sécu. | Critique | Les conteneurs qui tiennent nos données de santé seraient construits et servis par un tiers qui part, sans TLS ni signature : chaîne d'approvisionnement hors de contrôle | Registre officiel (`quay.io/openstack.kolla`, défaut) ou miroir interne (module 13) avec TLS ; ligne `docker_registry_insecure` supprimée |
| 7 | `globals.yml` : 24-25 | TLS désactivé, interne et externe | Sécu. | Élevée | Mots de passe et jetons en clair sur le VLAN 50 et depuis le VPN ; Horizon en HTTP | `kolla_enable_tls_external: "yes"` avec le certificat step-ca de `openstack.par1.medisphere.internal` (E04) ; TLS interne au palier 3 (E27) |
| 8 | `globals.yml` : 6 | `openstack_release: "master"` | Fonct. | Élevée | Images de la branche de développement, sans rapport avec Kolla-Ansible 22 (2026.1) : schémas de base et options incompatibles, mises à jour imprévisibles | Supprimer : Kolla utilise la série de sa version (`2026.1`) ; épingler par `openstack_tag` seulement avec une politique de version (E28) |
| 9 | `globals.yml` : 28 | `neutron_plugin_agent: "openvswitch"` | Fonct. | Élevée | Pas d'OVN : pas de fournisseur OVN pour Octavia (E16), agents L3/DHCP à part, architecture différente de toute notre documentation | `neutron_plugin_agent: "ovn"` (ce n'est **pas** le défaut) |
| 10 | `globals.yml` : 16 ; absence de `storage_interface` | Tunnels et trafic Ceph sur `ens18` (VLAN 50, MTU 1500) | Fonct. | Élevée | Réseaux Geneve plafonnés à 1442 et mêlés au trafic d'API ; trafic Ceph routé par la bordure vers le VLAN 30 (pare-feu, débit, MTU 1500 face aux 9000 de Ceph) | `tunnel_interface: "ens19"` (OS-TUN, MTU 9000), `storage_interface: "ens20"` (STOR-PUB) |
| 11 | `globals.yml` : 51, 54 | `nova_backend_ceph` avec `ceph_nova_pool_name: "volumes"` | Fonct. | Élevée | Disques éphémères des instances dans le pool des volumes Cinder : quotas et sauvegardes faussés, règles CRUSH différentes ignorées, nettoyage dangereux | `ceph_nova_pool_name` laissé au défaut `vms` ; `ceph_nova_user: "nova"` |
| 12 | `multinode` (tout le fichier) ; ligne 23 | Inventaire réduit aux groupes du haut, `[storage]` vide | Fonct. | Élevée | Sans les groupes de services de l'exemple 2026.1 (`[cinder:children]`, `[cinder-volume:children]`, `[kolla_logs:children]`…), Kolla ne sait où placer aucun service : déploiement en échec ou services absents ; avec l'inventaire d'une version antérieure, `cinder-volume` suivrait `[storage]`, vide : aucun volume | Inventaire régénéré à partir de l'exemple de la version installée (`outils/inventaire.sh`, E03) ; `osctl01` dans `[storage]` aussi (documentation *External Ceph*) |
| 13 | `globals.yml` : 34-35 | Sauvegardes Cinder vers un partage NFS `10.0.0.5` | Sécu./Fonct. | Élevée | Adresse hors de notre plan (réseau du prestataire ?) : soit les sauvegardes échouent, soit des copies de volumes de santé partent vers un tiers | `cinder_backup_driver: "ceph"` (défaut), pool `backups` ; copie hors site par E25 |
| 14 | `multinode` : 10-13, 15-16 | Calculs dans `[network]`, contrôleur dans `[compute]` | Fonct. | Moyenne | `oscmp01-02` n'ont pas d'`ens21` : création de `br-ex` en échec ou passerelles OVN sur des nœuds sans sortie ; instances placées sur `osctl01` (16 Go partagés avec tous les services) | `[network]` : `osctl01` ; `[compute]` : `oscmp01`, `oscmp02` |
| 15 | `config/glance/ceph.conf` : 3-6 | Lignes indentées par des tabulations ; un seul MON ; trousseau `client.admin` | Fonct. | Moyenne | L'analyseur INI de Kolla refuse les tabulations (déploiement en échec) ; un seul MON : la perte de `ceph01` coupe Glance alors que Ceph tient ; renvoie au défaut 1 | Fichier produit par `ceph config generate-minimal-conf`, tabulations retirées, trois MON ; ligne `keyring` supprimée (chemin par défaut du trousseau de l'utilisateur) |
| 16 | `globals.yml` : 21 | `kolla_external_fqdn: "openstack.infoger-sante.local"`, VIP externe = VIP interne | Fonct./Sécu. | Moyenne | Nom d'un autre client, inconnu de notre DNS ; certificat impossible à émettre par step-ca ; pas de séparation interne/externe | `kolla_external_vip_address: "10.10.50.201"`, `kolla_external_fqdn: "openstack.par1.medisphere.internal"`, `kolla_internal_fqdn: "openstack-int.par1.medisphere.internal"` |
| 17 | `globals.yml` : 39 | Octavia avec le seul fournisseur `amphora`, sans image ni réseau de gestion | Fonct. | Moyenne | Kolla tente l'enregistrement automatique (réseau de gestion VLAN par défaut, gabarit 1 Go) qui échoue ou crée des ressources inutilisables ; aucun répartiteur utilisable | `octavia_provider_drivers: "ovn:OVN provider"`, `octavia_provider_agents: "ovn"` (E16) |
| 18 | `globals.yml` : 42-44 | Prometheus, Grafana, OpenSearch activés | Expl. | Moyenne | Plusieurs Gio de mémoire sur `osctl01` (16 Go pour tout le contrôle) : OOM des services OpenStack ; la supervision du lab est prévue au module 21 | Désactivés ; sonde légère E26, puis module 21 |
| 19 | `globals.yml` : 57 | `nova_compute_virt_type: "qemu"` | Fonct. | Moyenne | Émulation logicielle : instances dix fois plus lentes alors que nos calculs ont la virtualisation imbriquée (CPU `host`) | Supprimer (défaut `kvm`) |
| 20 | `globals.yml` : 45 | `openstack_logging_debug: "True"` | Expl./Sécu. | Moyenne | Journaux volumineux, contenus de requêtes journalisés, disques de `osctl01` remplis | Supprimer (défaut `False`) ; `debug` ponctuel par surcharge (E20) |
| 21 | `globals.yml` : 48 | `glance_backend_file: "yes"` avec `glance_backend_ceph` | Fonct. | Faible | Deux magasins, images réparties selon le défaut : une partie sur le disque de `osctl01`, non clonables par Nova | Supprimer (le défaut se déduit : `file` seulement si aucun autre) |
| 22 | `globals.yml` : 5, 7 | `kolla_base_distro: "ubuntu"` ; `kolla_install_type` | Expl. | Faible | Images Ubuntu sur des hôtes Debian : fonctionne (conteneurs), mais écart avec notre standard (`debian`, E03) ; `kolla_install_type` n'existe plus depuis Zed : signe d'une configuration de 2022 jamais relue | `kolla_base_distro: "debian"` ; supprimer `kolla_install_type` |
| 23 | `globals.yml` : 29 | `enable_neutron_provider_networks: "yes"` | Fonct. | Faible | Ponts externes créés sur les calculs, qui n'ont pas d'interface externe | Supprimer (pas de réseau provider sur les calculs) |

**Ordre de traitement.** (1) La clé `client.admin` : elle est **déjà** sortie du cluster (archive d'un tiers) ; si elle est réelle, c'est une rotation immédiate, indépendamment de toute décision sur OpenStack. (2) VIP et VRID : appliquée telle quelle, cette configuration coupe la passerelle du VLAN 50 **au premier déploiement**, avant même qu'OpenStack ne fonctionne, et touche le socle. (3) `ens18` dans `br-ex` : perte de `osctl01` pendant le déploiement. Viennent ensuite les secrets en clair (4, 5), la chaîne d'approvisionnement (6), le TLS (7), puis ce qui empêche le service de fonctionner (8 à 13).

**Lignes corrigées de `globals.yml`**
```yaml
kolla_base_distro: "debian"
network_interface: "ens18"
tunnel_interface: "ens19"
storage_interface: "ens20"
neutron_external_interface: "ens21"
kolla_internal_vip_address: "10.10.50.200"
kolla_external_vip_address: "10.10.50.201"
kolla_internal_fqdn: "openstack-int.par1.medisphere.internal"
kolla_external_fqdn: "openstack.par1.medisphere.internal"
keepalived_virtual_router_id: "150"
kolla_enable_tls_external: "yes"
neutron_plugin_agent: "ovn"
enable_cinder: "yes"
enable_cinder_backup: "yes"
enable_heat: "yes"
enable_horizon: "yes"
enable_octavia: "yes"
octavia_provider_drivers: "ovn:OVN provider"
octavia_provider_agents: "ovn"
glance_backend_ceph: "yes"
cinder_backend_ceph: "yes"
nova_backend_ceph: "yes"
ceph_nova_user: "nova"
# supprimées : openstack_release, kolla_install_type, docker_registry*, docker_namespace,
# kolla_enable_tls_internal (palier 3), enable_neutron_provider_networks, cinder_backup_driver,
# cinder_backup_share, enable_prometheus, enable_grafana, enable_central_logging,
# openstack_logging_debug, glance_backend_file, ceph_glance_user, ceph_cinder_user,
# ceph_nova_pool_name, nova_compute_virt_type, keystone_admin_password
```

**Pour la direction.** Une configuration d'OpenStack n'est pas un produit qu'on installe, c'est la description d'un réseau, d'un stockage et de règles de sécurité **précis**. Celle-ci décrivait le réseau d'un autre client : appliquée chez nous, elle aurait coupé une partie du réseau du laboratoire dès la première heure, en utilisant l'adresse de notre routeur. Elle donnait aussi à OpenStack la clé « maître » de tout notre stockage, laissait des mots de passe d'administration en clair, et faisait venir les logiciels d'un serveur du prestataire, sans contrôle. La « demi-journée » annoncée aurait été suivie de jours de réparation et d'un audit HDS défavorable. Reprendre l'idée (Kolla-Ansible, Ceph) était juste ; reprendre le fichier ne l'était pas. Le coût caché d'un « clé en main » est la revue complète qu'il faut de toute façon faire : ici, 23 écarts sur 60 lignes.

**Grille d'auto-évaluation** (2 points par ligne, 20 au total, acceptable à 14)

| Critère | 0 | 1 | 2 |
|---|---|---|---|
| Défauts critiques (1 à 6) | moins de 4 | 4 ou 5 | les 6 |
| Défauts élevés (7 à 13) | moins de 4 | 4 à 6 | les 7 |
| Conflit VIP/VRID expliqué avec le PLAN | non | constaté | expliqué (VRRP, VRID = VLAN, effet sur le socle) |
| `ens18` dans `br-ex` compris | non | « mauvaise interface » | perte d'adresse expliquée |
| La clé `client.admin` traitée par une rotation | non | clé remplacée dans la config | rotation + clés à moindre privilège |
| Corrections précises (variable, valeur) | rares | la plupart | toutes |
| Inventaire relu (`multinode`) | non | un défaut | deux défauts |
| Ordre de traitement justifié | absent | sans justification | justifié |
| Texte pour la direction | absent | technique | compréhensible, chiffré, sans jargon |
| Ton de la revue | jugement du prestataire | neutre | factuel, utile |

---

### M10-E22 — Runbook : accueillir une équipe sur OpenStack

**Proposition de corrigé** : [`RB-100-accueillir-une-equipe.md`](fichiers/M10-E22/medisphere/docs/cloud/runbooks/RB-100-accueillir-une-equipe.md).

Ce qui fait la qualité du runbook, et que la relecture (Nadia, Sophie) doit trouver :
- **Un formulaire** en tête : sans responsable ni besoin chiffré, on ne commence pas. C'est ce qui évite les quotas « au jugé ».
- **L'ordre des dépendances** : capacité vérifiée → projets → groupe et rôles → socle en code (qui a besoin des projets) → accès CI (qui a besoin du rôle) → remise → contrôle **par un membre**. Le contrôle par `medisphere-admin` ne prouve rien (l'administrateur voit tout).
- **Les interdits explicites** : jamais `admin` sur un projet d'équipe ; jamais de rôle à une personne plutôt qu'au groupe ; jamais de secret dans un ticket ou un courriel ; application credential de la CI au nom d'un **compte de service** (elle meurt avec son propriétaire).
- **La remise des secrets** : mot de passe initial par un canal séparé, secret de l'application credential directement dans les variables protégées de la CI.
- **Le retrait** dans l'ordre inverse, en commençant par les ressources des projets (sinon ports, IP flottantes et volumes orphelins), puis le socle OpenTofu, la remise à zéro des quotas (le `destroy` ne les touche pas : E15), les accès, les projets (désactivés d'abord, pour l'audit).
- **Les pièges** vécus pendant le module : chevauchement de sous-réseau, rôle `support` oublié (pas d'héritage, par choix), double propriété projet/OpenTofu.

**Points fréquemment manqués** : l'étape « capacité » (on crée une équipe de trop) ; le contrôle final par un membre ; la ligne au registre des secrets ; le retrait des variables CI de l'équipe ; la désactivation (plutôt que suppression) des comptes des personnes qui partent, utile à l'audit.

**Grille** (auto-évaluation, une ligne = un point, acceptable à 8 sur 11) : formulaire ; prérequis de capacité ; ordre des étapes ; contrôles par étape ; jamais `admin` ; remise des secrets ; CI par compte de service ; contrôle par un membre ; retour arrière ; retrait complet dans le bon ordre ; pièges.

---

### M10-E23 — Politiques d'accès et rôles de lecture

**Solution**

Fichiers : [`nova/policy.yaml`](fichiers/M10-E23/openstack/etc/kolla/config/nova/policy.yaml), [`horizon/nova_policy.yaml`](fichiers/M10-E23/openstack/etc/kolla/config/horizon/nova_policy.yaml), [`donnees/identite.yml.extrait`](fichiers/M10-E23/openstack/donnees/identite.yml.extrait), [`playbooks/identite.yml.extrait`](fichiers/M10-E23/openstack/playbooks/identite.yml.extrait), [`outils/attribution-audit-heritee.sh`](fichiers/M10-E23/openstack/outils/attribution-audit-heritee.sh), [`docs/cloud/roles.md`](fichiers/M10-E23/medisphere/docs/cloud/roles.md).

1. **Comprendre** (politiques de Nova 2026.1, `nova/policies/base.py` et `servers.py`) :
   - `reader` : `servers:index`, `servers:detail`, `servers:show` (règle `project_reader_or_admin`) ; rien en écriture.
   - `member` : tout ce que fait `reader`, plus `servers:create`, `delete`, `reboot`, `start`, `stop`, `resize`, consoles (`project_member_or_admin`).
   - `manager` : `project_manager_api` sert à quelques actions « de gestion du projet » (et `admin` → `manager` → `member` → `reader`) ; en pratique, pour une instance, il fait ce que fait `member`.
   - `admin` sur `mediagenda-dev` : `context_is_admin` vaut `role:admin`, sans condition de projet : administrateur de tout (E13).
2. **Audit.** Comptes `sophie.laurent` et `nadia.roussel`, groupes `equipe-securite` et `equipe-support`, rôle `support` : ajoutés au code d'identité de E05 (extraits ; la tâche « Rôles personnalisés » utilise `openstack.cloud.identity_role`), puis `uv run ansible-playbook playbooks/identite.yml`. Le module `openstack.cloud.role_assignment` ne sait pas exprimer une attribution **héritée** (pas d'option d'héritage, vérifié dans la collection) : elle est posée par un script relu en MR et mentionnée dans `donnees/identite.yml`.
   ```
   admin@adm01:~/src/openstack$ OS_CLOUD=medisphere-admin outils/attribution-audit-heritee.sh
   admin@adm01:~$ openstack project create --domain medisphere essai-heritage
   admin@adm01:~$ openstack role assignment list --effective --names --user sophie.laurent --user-domain medisphere
   | reader | sophie.laurent@medisphere | | mediagenda-dev@medisphere | … | True |
   | reader | sophie.laurent@medisphere | | essai-heritage@medisphere | … | True |
   admin@adm01:~$ openstack project delete --domain medisphere essai-heritage
   admin@adm01:~$ openstack --os-cloud medisphere-audit volume create --size 1 interdit
   Policy doesn't allow volume:create to be performed. (HTTP 403)
   ```
   L'attribution héritée (`--inherited`, extension OS-INHERIT de Keystone) sur le domaine s'applique à **tous** ses projets, y compris ceux créés plus tard, et pas au domaine lui-même. Lectures avec `medisphere-audit` : `server list`, `volume list`, `network list`, `stack list` (Heat : `project_reader`), `loadbalancer list` (Octavia : `load-balancer:read` accepte `project-reader`) : toutes autorisées.
3. **Support.** `support` sur les **deux** projets, pas sur le domaine : le support n'a pas à toucher aux instances de `plateforme` (administration du cloud), ni à celles d'un futur projet sensible avant qu'on le décide (pas d'héritage, par choix, signalé dans RB-100). Lecture : le corrigé donne aussi `reader` (attribution) plutôt que d'étendre les règles de lecture : `reader` sert à **tous** les services (volumes, réseaux, piles) dont le support a besoin pour comprendre une panne, sans surcharge de politique à maintenir. Politique : cinq règles, chacune `rule:project_member_or_admin or (role:support and project_id:%(project_id)s)`.
4. **Vérifier avant de déployer.**
   ```
   admin@osctl01:~$ sudo docker exec nova_api oslopolicy-sample-generator --namespace nova --output-file /tmp/nova-defaut.yaml
   admin@osctl01:~$ sudo docker exec nova_api grep -E '^"os_compute_api:servers:(reboot|start|stop)"' /tmp/nova-defaut.yaml
   #"os_compute_api:servers:reboot": "rule:project_member_or_admin"
   admin@adm01:~/src/openstack$ uv run yamllint -d relaxed etc/kolla/config/nova/policy.yaml
   ```
   Le fichier d'exemple de **notre** version confirme les règles par défaut (lignes commentées). ⚠️ À vérifier sur ton lab : `oslopolicy-checker` (vérifier une règle avec un jeton enregistré) peut aussi servir ; sa syntaxe demande un fichier d'accès (`--access`). Déploiement : `kolla-ansible reconfigure -t nova,horizon` ; contrôle `sudo cat /etc/kolla/nova-api/policy.yaml` et `/etc/kolla/horizon/nova_policy.yaml` sur `osctl01`.
5. **Tests** avec `medisphere-support` (projet `mediagenda-dev`) :
   ```
   admin@adm01:~$ openstack --os-cloud medisphere-support server list                # OK (reader)
   admin@adm01:~$ openstack --os-cloud medisphere-support server reboot e16-web1     # OK (support)
   admin@adm01:~$ openstack --os-cloud medisphere-support console log show e16-web1 | tail -3   # OK
   admin@adm01:~$ openstack --os-cloud medisphere-support server delete e16-web1
   Policy doesn't allow os_compute_api:servers:delete to be performed. (HTTP 403)
   admin@adm01:~$ openstack --os-cloud medisphere-support volume create --size 1 x                       # 403
   admin@adm01:~$ openstack --os-cloud medisphere-support security group rule create --protocol tcp e16-web   # 403
   ```
   Dans Horizon, Nadia voit les instances, et dans le menu d'actions « Redémarrer », « Arrêter », « Démarrer », « Console », « Journal » ; pas « Supprimer » ni « Redimensionner ». ⚠️ À vérifier sur ton lab : sans la copie `horizon/nova_policy.yaml`, Horizon masque ces boutons (il croit le droit absent) alors que l'API l'accepte.
6. **Matrice** : `roles.md`.

**Explications**

Depuis la série 2024.2, oslo.policy applique par défaut les « nouvelles politiques » (rôles `reader`/`member`/`manager`/`admin`, portée vérifiée) et l'option `enforce_scope` est en cours de retrait : on ne revient plus aux anciennes règles « admin ou propriétaire ». Chaque service définit ses règles **dans son code** ; un fichier `policy.yaml` ne contient que les règles qu'on **change**, réécrites entières. C'est pour cela qu'on part toujours du fichier d'exemple de la version installée : une règle copiée d'une autre version peut ouvrir ou fermer plus que prévu. Horizon ne fait qu'**afficher** selon ses propres copies des politiques : l'API reste la seule autorité.

**Alternatives**
- *Donner `member` au support* : rien à maintenir, mais le support peut tout supprimer ; refusé par la RSSI.
- *Rôle `support` hérité sur le domaine* : un projet de plus ne demande rien ; mais les projets sensibles futurs seraient ouverts par défaut.
- *Lecture par la politique* (ajouter `role:support` aux règles `servers:show`/`index`) : pas d'attribution `reader`, mais une surcharge par service pour chaque lecture.

**Pièges classiques**
- Oublier la copie pour Horizon : boutons absents, tickets « le droit ne marche pas ».
- Écrire `role:support` sans `project_id:%(project_id)s` : le support devient « support global » sur toutes les instances de tous les projets.
- Recopier la règle par défaut de mémoire (`rule:admin_or_owner`, ancienne règle) : comportement d'avant les nouvelles politiques.
- Support sans `reader` : 404 au lieu de 403 (Nova ne « trouve » pas l'instance), diagnostic trompeur.
- `--inherited` oublié : Sophie a `reader` sur le **domaine** (gérer les métadonnées du domaine), pas sur ses projets.

**En production chez MédiSphère**
Tests automatisés des politiques (un jeu de comptes de test par rôle, exécuté après chaque mise à jour et chaque MR de `policy.yaml`), revue des surcharges à chaque mise à jour de série (RB-101), et rôles portés par les groupes de l'annuaire fédéré (module 24) plutôt que par des comptes locaux.
