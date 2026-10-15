# Module 16 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Les fichiers.** Les fichiers complets sont dans [`fichiers/`](fichiers/), un dossier par exercice, sous la forme d'un **extrait des projets** : `fichiers/M16-EXX/k8s/…` = chemins de `plateforme/k8s`, `…/ansible/…` = `plateforme/ansible`, `…/infra/…` = `plateforme/infra`, `…/medisphere/…` = la documentation ; `…/essais/…` se posent dans `~/m16/eXX/` (objets jetables de `wb-essais`). On **superpose** les dossiers dans l'ordre (E10, E11…) : un fichier d'un exercice plus récent remplace le précédent (exemple : les classes d'instantanés d'E17 remplacent celles d'E10). Les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête), les `*.exemple` des modèles sans valeur réelle. `<FSID>` est le fsid de `ceph-par1` (`ceph fsid`), comme au palier 1.

**Ce qui a été vérifié, ce qui ne l'a pas été.**
- *Documentation lue aux versions de référence* : external-snapshotter au tag `v8.6.0` (le manifeste du contrôleur y référence encore l'image `v8.5.0`, d'où la surcharge d'image du palier 1) ; Rook 1.21.0 (*Quickstart*, *Prerequisites*, *CephCluster CRD*, *Cleanup*, `PendingReleaseNotes.md`, valeurs des charts `rook-ceph` et `rook-ceph-cluster` 1.21.0) ; Longhorn 1.13.0 (*Installation Requirements*, *Uninstall*, *Setting a Backup Target*, valeurs du chart 1.13.0, CRD `BackupTarget`) ; Velero 1.18.4 (*CSI*, *CSI Snapshot Data Movement*, *File System Backup*, *self-signed certificates* : `caCert` déprécié au profit de `caCertRef`, options de `velero install` dans le code, `CRON_TZ` dans *Backup reference*) et plugin AWS 1.14.4 (`backupstoragelocation.md`) ; chart Velero 12.2.1 ; CloudNativePG 1.30.1 (*Backup*, *Recovery*, *Replication*, *Connecting from an application*, référence d'API, image par défaut dans `pkg/versions/versions.go`, bibliothèque cron `robfig/cron` v1.2.0 dans `go.mod`) et plugin Barman Cloud 0.15.1 (*Installation*, *Usage*, *Object Store Providers*, *Retention Policies*, *Parameters*, référence d'API `ObjectStore`, manifeste de la version) ; charts `cnpg/cloudnative-pg` 0.29.1 et `cnpg/plugin-barman-cloud` 0.8.1. Les étiquettes d'images utilisées (`postgresql:18.6-minimal-trixie`, `plugin-barman-cloud-sidecar:v0.15.1`, `snapshot-controller:v8.6.0`) existent sur leurs registres (vérifié le 08/10/2026), ainsi que l'archive `velero-v1.18.4-linux-amd64.tar.gz` et son empreinte dans `CHECKSUM`.
- *Manifestes* : tous les manifestes de `fichiers/M16-E10` à `M16-E23` passent `kubeconform -strict` (Kubernetes 1.36, schémas des CRD de snapshots, Velero, CNPG, Barman Cloud et `CiliumNetworkPolicy` produits par `outils/schemas-crd.sh` d'E23) **et** un `kubectl apply --dry-run=server` sur un `kube-apiserver` 1.36.5 de test (avec etcd 3.6.8) où les CRD des charts aux versions de référence ont été installées. La `ValidatingAdmissionPolicy` d'E20, la `LimitRange` et le contrôleur `DefaultStorageClass` ont été **exécutés** sur ce serveur : les messages de refus cités en E20 sont ceux obtenus.
- *Charts* : `helm template` (Helm 4.3) des charts Rook 1.21.0 (opérateur et cluster), Longhorn 1.13.0, Velero 12.2.1, CNPG 0.29.1 et Barman Cloud 0.8.1 avec les valeurs du corrigé : rendu sans erreur ; on y a contrôlé la section `storage` et la classe non par défaut de Rook, la classe non par défaut de Longhorn, la BSL et les arguments `--features=EnableCSI`/`--uploader-type=kopia` de Velero, `OPERATOR_IMAGE_NAME` et `SIDECAR_IMAGE` pointant vers Harbor pour CNPG.
- *Ansible* : `k8s-rook-prerequis.yml`, `k8s-rook-nettoyage.yml`, `k8s-longhorn-prerequis.yml` et le rôle `longhorn_prerequis` passent `ansible-lint` en profil `production` (collections `community.general` et `ansible.posix`).
- *Scripts et checks* : ShellCheck et `bash -n` sur tous les scripts, checks compris ; `outils/schemas-crd.sh` exécuté (38 schémas). Les checks dont les contrôles reposent sur l'API ont été exécutés contre le serveur de test, avec des objets conformes puis fautifs.

**Non rejoués sur un cluster réel** (aucun `k8s-par1` disponible pour la rédaction) : temps et comportement fins des instantanés et clones ceph-csi, chemin exact des disques sous `/dev/disk/by-id/` (série QEMU), démarrage effectif de Rook 1.21 avec les ressources réduites, jobs `rook-ceph-cleanup`, reconstruction des réplicas Longhorn, désinstallation Longhorn, sauvegardes et restaurations Velero (Kopia, *data mover*), comportement de SeaweedFS avec Kopia et Barman, archivage et PITR CNPG avec le plugin, besoins réseau exacts des pods CNPG sous Cilium. Ils sont signalés « ⚠️ À vérifier sur ton lab » : signale tes retours.

**Où lancer les commandes.** `admin@adm01:~$` avec ton kubeconfig personnel (groupe `medisphere:plateforme-admins`) ; `admin@adm01:~/src/k8s$` à la racine du clone de `plateforme/k8s` ; `[root@ceph01 ~]#` pour observer `ceph-par1` ; `admin@k8s-w01:~$` (SSH, `sudo`) pour les nœuds. Les vérifications se lancent depuis `adm01` (`lab/bin/check 16 XX`).

---

### M16-E10 — Snapshots et clones de volumes

**Solution**

Fichiers : [`rbac/wb-checks-stockage.yaml`](fichiers/M16-E10/k8s/rbac/wb-checks-stockage.yaml), [`classes/ceph-rbd-snap.yaml`](fichiers/M16-E10/k8s/composants/ceph-csi/classes/ceph-rbd-snap.yaml), [`classes/cephfs-snap.yaml`](fichiers/M16-E10/k8s/composants/ceph-csi/classes/cephfs-snap.yaml), essais [`10-sources.yaml`](fichiers/M16-E10/essais/10-sources.yaml), [`20-instantanes.yaml`](fichiers/M16-E10/essais/20-instantanes.yaml), [`30-restaurations.yaml`](fichiers/M16-E10/essais/30-restaurations.yaml).

1. **Vérifications.** Le ClusterRole ne donne que `get`, `list`, `watch` sur les groupes du stockage, plus `get` sur `nodes/proxy` et `nodes/stats` (le résumé du kubelet, lu par les checks d'E11 et E27).
   ```
   admin@adm01:~/src/k8s$ kubectl apply -f rbac/wb-checks-stockage.yaml     # après la MR
   admin@adm01:~$ kubectl auth can-i list volumesnapshots -A --as=system:serviceaccount:wb-system:wb-checks
   yes
   admin@adm01:~$ kubectl auth can-i create volumesnapshots -n wb-essais --as=system:serviceaccount:wb-system:wb-checks
   no
   admin@adm01:~$ kubectl auth can-i get secrets -n ceph-csi --as=system:serviceaccount:wb-system:wb-checks
   no
   ```
   `nodes/proxy` en `get` permet de lire `/stats/summary`, `/metrics`, `/pods` d'un kubelet, **pas** d'exécuter dans un pod (`exec` et `attach` demandent `create` sur `pods/exec`) ; il permet par contre de lire les journaux des conteneurs (`/containerLogs`) : c'est un droit de lecture large, à garder pour des comptes de supervision. ⚠️ À vérifier sur ton lab : selon la configuration d'autorisation du kubelet (`webhook`, défaut de kubeadm), les sous-ressources `nodes/stats` et `nodes/proxy` sont celles que le kubelet demande à l'API.
2. **Lecture.**
   - Un instantané **dynamique** : on crée le `VolumeSnapshot` ; le `snapshot-controller` crée le `VolumeSnapshotContent` correspondant (et le lie, comme le contrôleur de liaison lie PVC et PV) ; le *sidecar* `csi-snapshotter`, à côté du provisionneur du pilote, voit ce `VolumeSnapshotContent` et appelle `CreateSnapshot` sur le pilote, puis renseigne `readyToUse`, `restoreSize`, `snapshotHandle`. Le contrôleur est **commun** à tout le cluster ; le *sidecar* est **propre** à chaque pilote.
   - `deletionPolicy: Retain` sur la classe : supprimer le `VolumeSnapshot` laisse le `VolumeSnapshotContent` et l'instantané dans Ceph (comme `Retain` pour un PV) ; il faut nettoyer à la main.
   - Supprimer le PVC source : pour ceph-csi RBD, l'instantané **survit** (ceph-csi le garde sur une image intermédiaire qui lui est propre, voir l'étape 5) ; on peut toujours restaurer. Pour CephFS, l'instantané appartient au sous-volume : ceph-csi garde le sous-volume tant qu'il a des instantanés (*retain snapshots*) ⚠️ à vérifier sur ta version.
3. **État des lieux.**
   ```
   admin@adm01:~$ kubectl get crd | grep snapshot.storage
   volumesnapshotclasses.snapshot.storage.k8s.io    …
   volumesnapshotcontents.snapshot.storage.k8s.io   …
   volumesnapshots.snapshot.storage.k8s.io          …
   admin@adm01:~$ kubectl -n kube-system get deploy snapshot-controller -o wide
   admin@adm01:~$ kubectl -n kube-system get lease | grep -i snapshot
   snapshot-controller-leader   snapshot-controller-6d…-abcde   …
   admin@adm01:~$ kubectl -n ceph-csi get pod -l app=ceph-csi-rbd,component=provisioner -o jsonpath='{.items[0].spec.containers[*].name}'
   csi-rbdplugin csi-provisioner csi-resizer csi-snapshotter csi-attacher csi-rbdplugin-controller liveness-prometheus
   admin@adm01:~$ kubectl -n ceph-csi logs deploy/ceph-csi-rbd-provisioner -c csi-snapshotter --since=1h | tail
   ```
   Le nom exact du `Lease` dépend de la version du contrôleur. Le *sidecar* tourne sur chaque réplique du provisionneur, avec sa propre élection.
4. **Classes d'instantanés.** Les deux fichiers dans `composants/ceph-csi/classes/`, puis `composants/ceph-csi/installer.sh` (il réapplique aussi les StorageClasses, sans changement) :
   ```
   admin@adm01:~$ kubectl get volumesnapshotclass
   NAME            DRIVER                DELETIONPOLICY   AGE
   ceph-rbd-snap   rbd.csi.ceph.com      Delete           10s
   cephfs-snap     cephfs.csi.ceph.com   Delete           10s
   ```
   L'annotation `snapshot.storage.kubernetes.io/is-default-class: "true"` (et non `storageclass.kubernetes.io/…`) désigne la classe par défaut **par pilote** : un `VolumeSnapshot` sans `volumeSnapshotClassName` prend celle du pilote de son PVC. Deux classes par défaut pour un même pilote : la création d'un instantané sans classe échoue.
5. **RBD.**
   ```
   admin@adm01:~/m16/e10$ kubectl apply -f 10-sources.yaml
   admin@adm01:~/m16/e10$ kubectl -n wb-essais exec donnees -- bash -c 'date > /donnees/rdv.txt; sha256sum /donnees/rdv.txt'
   3f2a…  /donnees/rdv.txt
   admin@adm01:~/m16/e10$ kubectl apply -f 20-instantanes.yaml
   admin@adm01:~$ kubectl -n wb-essais get volumesnapshot -w
   NAME         READYTOUSE   SOURCEPVC   RESTORESIZE   SNAPSHOTCLASS   SNAPSHOTCONTENT        …
   donnees-s1   true         donnees     1Gi           ceph-rbd-snap   snapcontent-9b1c…
   [root@ceph01 ~]# rbd ls k8s-rbd
   csi-snap-5e0a…           ← l'« instantané » de Kubernetes
   csi-vol-1d7c…            ← le volume de donnees
   [root@ceph01 ~]# rbd snap ls k8s-rbd/csi-snap-5e0a…
   [root@ceph01 ~]# rbd info k8s-rbd/csi-snap-5e0a…    # parent : csi-vol-1d7c…@…, ou rien après aplatissement
   ```
   ceph-csi ne garde pas un simple `rbd snap` sur l'image du volume : il prend un instantané RBD, en fait un **clone** (`csi-snap-…`), pose sur ce clone son propre instantané et retire celui de l'image source. Ainsi, le volume source peut être supprimé ou agrandi indépendamment, et la profondeur de clones est contrôlée (aplatissement en arrière-plan au-delà des seuils `rbdsoftmaxclonedepth`/`rbdhardmaxclonedepth`, 4 et 8 par défaut). ⚠️ À vérifier sur ton lab : la forme exacte (nombre d'images, présence ou non d'un instantané sur le clone) dépend de la version de ceph-csi.
   Puis on modifie `rdv.txt`, on applique `30-restaurations.yaml` et on compare :
   ```
   admin@adm01:~$ kubectl -n wb-essais exec lecteur -- sha256sum /restauree/rdv.txt     # même empreinte qu'avant la modification
   ```
6. **Clone.** `donnees-clone` (`dataSource` de type `PersistentVolumeClaim`) : même classe (même pilote) que la source, **même espace de noms**, taille ≥ source ; le mode de volume doit être identique. ceph-csi fait un instantané temporaire de la source, un clone, puis retire l'instantané : côté Ceph, une image `csi-vol-…` de plus, éventuellement avec un parent jusqu'à son aplatissement.
7. **CephFS.**
   ```
   [root@ceph01 ~]# ceph fs subvolume ls cephfs --group_name csi
   [root@ceph01 ~]# ceph fs subvolume snapshot ls cephfs <SOUS-VOLUME> --group_name csi
   [root@ceph01 ~]# ceph fs clone status cephfs <SOUS-VOLUME-RESTAURE> --group_name csi
   {"status": {"state": "in-progress", …}}
   ```
   Avec un fichier de 300 Mio : la restauration RBD est quasi immédiate (copie sur écriture : on ne copie rien tant qu'on n'écrit pas) ; la restauration CephFS prend le temps de **copier** les 300 Mio (un clone de sous-volume CephFS est une copie complète faite par le MDS et le gestionnaire, asynchrone) : le PVC reste `Pending` tant que le clone n'est pas `complete`. Sur des volumes de plusieurs centaines de Gio, cela compte en heures.
8. **Ce qu'un instantané n'est pas.** Les blocs de `donnees-s1` sont dans le pool `k8s-rbd`, sur les mêmes OSD que le volume, et partagent ses blocs non modifiés : perdre le pool (ou `ceph-par1`, ou les droits d'écriture de quelqu'un qui supprime tout) fait perdre l'instantané **avec** l'original. Un instantané de volume est cohérent au niveau **bloc** (comme une coupure de courant) : PostgreSQL redémarre dessus en rejouant ses WAL, mais rien ne garantit la cohérence d'une application qui écrit dans plusieurs volumes, ni d'un fichier à moitié écrit dans le cache d'une application. C'est un outil de retour arrière rapide, pas une sauvegarde (Velero, E16-E17 ; CNPG, E19).

**Explications**
L'API des instantanés reproduit le modèle PV/PVC : une classe (paramètres du pilote, politique de suppression), un objet demandé dans l'espace (`VolumeSnapshot`), un objet de cluster qui représente la réalité (`VolumeSnapshotContent`). Restaurer ou cloner, c'est **provisionner** un nouveau volume avec une source (`dataSource`) : c'est le provisionneur, pas le *snapshotter*, qui fait le travail. La différence de coût entre RBD (copie sur écriture) et CephFS (copie complète) vient du stockage, pas de Kubernetes.

**Alternatives**
- `dataSourceRef` (plus récent que `dataSource`) accepte aussi des sources d'autres types (*volume populators*) et des sources d'un autre espace (avec `ReferenceGrant`, fonction alpha `CrossNamespaceVolumeDataSource`) : inutile ici.
- CephFS : un volume restauré « superficiel » (`backingSnapshot: "true"` dans une classe dédiée, lecture seule) monte directement l'instantané sans copie ; utile pour lire une sauvegarde (le *data mover* de Velero s'en sert), pas pour reprendre une écriture.

**Pièges classiques**
- Restaurer dans une **autre classe** (instantané `cephfs-snap` vers un PVC `ceph-rbd`) : refusé, un pilote ne restaure que ses instantanés.
- Oublier le `apiGroup: snapshot.storage.k8s.io` dans `dataSource` : le PVC est créé **vide**, sans erreur visible (la source inconnue est ignorée), ou reste `Pending` selon la version. Vérifie toujours le contenu restauré.
- Croire que `readyToUse: true` veut dire « copié ailleurs » : il veut dire « l'instantané existe dans Ceph ».
- Laisser s'accumuler des instantanés : ils coûtent de la place (blocs divergents) et ralentissent certaines opérations ; ceph-csi aplatit au-delà de `maxsnapshotsonimage` (450).

**En production chez MédiSphère**
Des instantanés avant chaque migration de schéma (Julien), supprimés après validation ; un quota d'objets `count/volumesnapshots.snapshot.storage.k8s.io` par équipe (E20) ; la supervision des `VolumeSnapshot` non prêts depuis plus de 10 minutes (M21) ; et toujours une vraie sauvegarde hors de Ceph à côté.

---

### M16-E11 — Agrandir un volume, volumes en mode bloc

**Solution**

Fichiers : [`occupation.sh`](fichiers/M16-E11/occupation.sh), [`bloc.yaml`](fichiers/M16-E11/essais/bloc.yaml), [`wb-essai-fige.yaml`](fichiers/M16-E11/essais/wb-essai-fige.yaml).

1. **Occupation.**
   ```
   admin@adm01:~$ kubectl -n wb-essais exec donnees -- bash -c 'head -c 850M /dev/zero > /donnees/remplissage; df -h /donnees'
   admin@adm01:~$ N=$(kubectl -n wb-essais get pod donnees -o jsonpath='{.spec.nodeName}')
   admin@adm01:~$ kubectl get --raw "/api/v1/nodes/$N/proxy/stats/summary" \
       | jq '.pods[].volume[]? | select(.pvcRef.name == "donnees") | {pvcRef, usedBytes, capacityBytes}'
   admin@adm01:~$ kubectl get --raw "/api/v1/nodes/$N/proxy/metrics" | grep 'kubelet_volume_stats_used_bytes{.*persistentvolumeclaim="donnees"'
   admin@adm01:~/m16/e11$ ./occupation.sh 80
   ESPACE   PVC      NOEUD    UTILISE  CAPACITE  TAUX
   wb-essais donnees k8s-w02  851Mi    974Mi     87%
   ```
   La capacité vue (≈ 974 Mi pour 1 Gio) est celle du système de fichiers ext4 (métadonnées et blocs réservés déduits). Le kubelet ne publie ces chiffres que pour les volumes **montés** sur son nœud, et les rafraîchit périodiquement (environ une minute).
2. **Agrandir en ligne.**
   ```
   admin@adm01:~$ kubectl -n wb-essais patch pvc donnees -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
   admin@adm01:~$ kubectl -n wb-essais describe pvc donnees | sed -n '/Events/,$p'
     Normal  Resizing                   external-resizer rbd.csi.ceph.com  External resizer is resizing volume pvc-…
     Normal  ExternalExpanding          volume_expand                      waiting for an external controller to expand this PVC
     Normal  FileSystemResizeRequired   external-resizer rbd.csi.ceph.com  Require file system resize of volume on node
     Normal  FileSystemResizeSuccessful kubelet                            MountVolume.NodeExpandVolume succeeded for volume "pvc-…" k8s-w02
   admin@adm01:~$ kubectl -n wb-essais exec donnees -- df -h /donnees      # ≈ 2,0G
   ```
   Deux étapes : le *sidecar* `csi-resizer` appelle `ControllerExpandVolume` (ceph-csi agrandit l'image RBD : `rbd resize`) et pose la condition `FileSystemResizePending` ; puis le kubelet du nœud qui monte le volume appelle `NodeExpandVolume` (ceph-csi lance `resize2fs` sur le périphérique mappé), sans démonter. Le pod n'est pas redémarré. L'ordre exact et le libellé des événements varient légèrement selon les versions.
3. **Réduire** : refusé à l'admission, par validation de l'API (`spec.resources.requests.storage: Forbidden: field can not be less than status.capacity`). Depuis la reprise d'agrandissement échoué (*RecoverVolumeExpansionFailure*, GA en 1.34), on peut **revenir** à une taille plus petite que la dernière demande, mais jamais en dessous de la capacité réelle (`status.capacity`) : c'est fait pour annuler une demande trop grande qui échoue (quota Ceph), pas pour réduire un volume. Réduire un volume, c'est créer un nouveau PVC plus petit et copier (E29).
4. **CephFS** : `bytes_quota` du sous-volume passe à 2147483648. Il n'y a ni bloc à agrandir ni système de fichiers à étendre : la taille d'un volume CephFS est un **quota** posé sur un répertoire (`ceph.quota.max_bytes`), que le client noyau applique ; pas d'étape nœud.
5. **Classe sans agrandissement.**
   ```
   admin@adm01:~/m16/e11$ kubectl apply -f wb-essai-fige.yaml
   admin@adm01:~$ kubectl -n wb-essais patch pvc fige -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
   Error from server (Forbidden): persistentvolumeclaims "fige" is forbidden: only dynamically provisioned pvc can be resized and the storageclass that provisions the pvc must support resize
   admin@adm01:~/m16/e11$ kubectl delete -f wb-essai-fige.yaml
   ```
   Refus **immédiat**, par l'admission (contrôleur `PersistentVolumeClaimResize` de l'API), avant que le pilote ne soit consulté.
6. **Mode bloc.**
   ```
   admin@adm01:~/m16/e11$ kubectl apply -f bloc.yaml
   admin@adm01:~$ kubectl -n wb-essais exec bloc-essai -- bash -c 'ls -l /dev/xvda; lsblk; echo MEDISPHERE | dd of=/dev/xvda bs=512 seek=2048 conv=fsync; dd if=/dev/xvda bs=512 skip=2048 count=1 2>/dev/null | head -c 11'
   brw-rw---- 1 root disk 252, 16 … /dev/xvda
   rbd1  252:16  0  1G  0 disk
   MEDISPHERE
   admin@adm01:~$ kubectl -n wb-essais patch pvc bloc -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
   admin@adm01:~$ kubectl -n wb-essais exec bloc-essai -- lsblk /dev/xvda     # 2G, après quelques secondes
   ```
   Le pod voit le périphérique `rbdN` mappé par le noyau du nœud, sans système de fichiers : rien à étendre, l'agrandissement s'arrête à `ControllerExpandVolume` (plus la prise en compte de la nouvelle taille du périphérique sur le nœud).
7. **Journal.** Le mode bloc sert aux logiciels qui gèrent eux-mêmes leur disque : bases et moteurs de stockage qui veulent des E/S directes sans double cache (certaines bases, des OSD Ceph dans Rook sur PVC), et surtout les **machines virtuelles** dans Kubernetes (KubeVirt, OpenShift Virtualization) qui reçoivent un disque brut. RBD peut être `ReadWriteMany` en mode bloc parce que le périphérique bloc partagé ne suppose aucun système de fichiers : c'est ce qui permet la migration à chaud d'une VM (deux nœuds ouvrent le même disque pendant la bascule). La cohérence est alors à la charge de l'application (une seule écrit, ou un système de fichiers en grappe comme OCFS2/GFS2) ; en mode fichier, ext4 monté sur deux nœuds se corromprait, d'où le refus de ceph-csi.

**Explications**
L'agrandissement est déclaratif : on change la demande, deux contrôleurs (le *resizer* du pilote, puis le kubelet) font converger la réalité, et l'état est visible dans les conditions du PVC. Il n'est possible que si la classe le permet (`allowVolumeExpansion`) **et** que le pilote implémente les appels correspondants.

**Alternatives**
- Si le pilote ne sait pas agrandir en ligne, le kubelet fait l'étape nœud au prochain montage (redémarrage du pod).
- Pour des volumes qui grossissent sans cesse (journaux), mieux vaut un stockage objet ou une rotation qu'un agrandissement répété.

**Pièges classiques**
- Agrandir un PVC lié à un StatefulSet : il faut agrandir **chaque** PVC ; changer `volumeClaimTemplates` d'un StatefulSet existant est refusé (champ immuable), et ne s'applique de toute façon qu'aux futurs PVC.
- Le quota de stockage (E20) compte la nouvelle taille demandée : un agrandissement peut être refusé par le quota de l'espace ou par le quota du pool `k8s-rbd` (le PVC reste alors en `Resizing` avec une erreur du pilote).
- `df` lu dans le pod juste après le `patch` : l'étape nœud n'a pas encore eu lieu.

**En production chez MédiSphère**
Une alerte « PVC rempli à plus de 80 % » (série `kubelet_volume_stats_used_bytes` / `…_capacity_bytes`, M21) et une consigne de l'astreinte : agrandir en ligne, noter dans le ticket, prévenir l'équipe ; pour les bases CNPG, agrandir dans le `Cluster` (`spec.storage.size`), l'opérateur s'occupe des PVC.

---

### M16-E12 — Classes de stockage : défaut, topologie, liaison différée

**Solution**

Fichiers : [`classes-essai.yaml`](fichiers/M16-E12/essais/classes-essai.yaml), [`pvc-essais.yaml`](fichiers/M16-E12/essais/pvc-essais.yaml), catalogue [`docs/kubernetes/stockage/classes.md`](fichiers/M16-E12/medisphere/docs/kubernetes/stockage/classes.md).

1. **Paramètres.** Voir le tableau du catalogue. `clusterID` désigne l'entrée de la ConfigMap `ceph-csi-config` (moniteurs) ; `pool` le pool RBD ; `imageFeatures` les fonctions des images créées (celles que krbd 6.12 sait monter) ; `mapOptions` les options passées au noyau au mappage (`ms_mode=secure`) ; `csi.storage.k8s.io/fstype` le système de fichiers créé au premier montage. Les paramètres `csi.storage.k8s.io/*-secret-*` sont interprétés par les *sidecars* et le kubelet, pas par ceph-csi : `provisioner-secret` pour `CreateVolume`/`DeleteVolume` (provisionneur), `controller-expand-secret` pour `ControllerExpandVolume` (*resizer*), `controller-publish-secret` pour `ControllerPublishVolume` (*attacher*), `node-stage-secret` pour `NodeStageVolume` (kubelet : c'est lui qui transmet la clé au plugin du nœud pour mapper). Modifiables après création : **rien**, sauf les annotations et étiquettes (c'est ainsi qu'on change la classe par défaut).
2. **Deux classes par défaut.** Le PVC reçoit `wb-essai-defaut2`, la plus **récente** : depuis 1.26, avec plusieurs classes par défaut, l'admission choisit la dernière créée au lieu de refuser le PVC. C'est commode pendant une migration de classe par défaut, dangereux par accident : tous les nouveaux PVC changent de pilote sans prévenir.
3. **Zéro classe par défaut.**
   ```
   admin@adm01:~$ kubectl annotate sc ceph-rbd storageclass.kubernetes.io/is-default-class-        # ⚠️ quelques minutes au plus
   admin@adm01:~/m16/e12$ kubectl apply -f pvc-essais.yaml --selector=…   # ou le seul document sans-classe
   admin@adm01:~$ kubectl -n wb-essais get pvc sans-classe -o jsonpath='{.status.phase} {.spec.storageClassName}{"\n"}'
   Pending                                   ← aucun événement : personne n'est chargé de ce PVC
   admin@adm01:~$ kubectl annotate sc ceph-rbd storageclass.kubernetes.io/is-default-class=true
   admin@adm01:~$ kubectl -n wb-essais get pvc sans-classe -w
   sans-classe   Bound   pvc-…   1Gi   RWO   ceph-rbd   …
   ```
   Le contrôleur de liaison attribue la classe par défaut aux PVC **sans** `storageClassName` dès qu'elle réapparaît (attribution rétroactive, GA en 1.28). `classe-vide` (`storageClassName: ""`) reste `Pending` pour toujours : la chaîne vide signifie « un PV statique sans classe », jamais de provisionnement ni d'attribution rétroactive. Vérifie à la fin : `kubectl get sc` montre `ceph-rbd (default)`.
4. **Liaison différée.** Le PVC `differee` reste `Pending` avec l'événement `WaitForFirstConsumer` (« waiting for first consumer to be created before binding »). Le pod au `nodeSelector` impossible reste `Pending` (`didn't match Pod's node affinity/selector`) et **aucune image n'est créée** dans `k8s-rbd`. La même expérience sur `ceph-rbd` (`Immediate`) crée l'image tout de suite, alors que le pod ne démarrera jamais. Coûts d'`Immediate` : le volume consomme le quota (de l'espace et du pool) pour rien ; un PVC oublié laisse une image orpheline ; avec un stockage à topologie (disque local, Ceph par baie), le volume est créé **avant** de savoir où ira le pod, qui peut ne plus pouvoir être placé (volume dans la baie A, pod qui ne tient que dans la baie B).
5. **Topologie.** Le pod `baie-a` arrive sur le nœud de la zone `par1-baie-a` (celui que le M14-E14 y a placé) : c'est l'**ordonnanceur** qui l'a décidé, en filtrant les nœuds par les termes d'`allowedTopologies` de la classe (le plugin de liaison des volumes compare ces termes aux étiquettes des nœuds) ; le provisionneur a ensuite créé le volume, sans contrainte particulière. `kubectl get csinode -o yaml` montre que `rbd.csi.ceph.com` n'annonce **aucune** `topologyKeys`, et le PV créé n'a pas de `nodeAffinity` : la contrainte ne vaut que pour le premier pod ; un pod suivant qui utilise ce PVC peut aller dans n'importe quelle baie, et les données, elles, sont réparties par CRUSH sur toutes les baies. Avec un pilote qui annonce sa topologie (Longhorn avec ses étiquettes de zone, un stockage local, un ceph-csi configuré avec `--domainlabels` et des pools par baie `topologyConstrainedPools`), le PV porterait une `nodeAffinity` et les données seraient réellement dans la baie.
6. **Nettoyage.**
   ```
   admin@adm01:~/m16/e12$ kubectl delete -f pvc-essais.yaml --ignore-not-found
   admin@adm01:~/m16/e12$ kubectl delete -f classes-essai.yaml --ignore-not-found
   admin@adm01:~$ kubectl get sc
   ```
7. **Catalogue** : voir le fichier ; la position retenue est de garder `ceph-rbd` en `Immediate` (pilote sans topologie, changement visible pour les équipes, recréation de la classe), et `WaitForFirstConsumer` pour toute future classe à topologie.

**Explications**
Trois acteurs décident du sort d'un PVC : l'**admission** (classe par défaut, quotas, politiques), le **contrôleur de liaison** (`Immediate` ou attente du premier pod, liaison à un PV existant), l'**ordonnanceur** (avec `WaitForFirstConsumer`, il choisit le nœud en tenant compte des contraintes de volume, puis annote le PVC). Le pilote n'intervient qu'après.

**Alternatives**
- Passer `ceph-rbd` en `WaitForFirstConsumer` est défendable (pas de volume orphelin) : il faut alors supprimer et recréer la classe (sans effet sur les PV existants) dans une fenêtre annoncée, et prévenir les équipes que `Pending` sans pod devient normal (et adapter RB-160).

**Pièges classiques**
- Retirer l'annotation par défaut « juste un instant » pendant qu'un opérateur crée des PVC (CNPG, Velero en restauration) : ils naissent sans classe et restent bloqués jusqu'au retour de l'annotation.
- Croire qu'`allowedTopologies` place les **données** : il place le premier pod.
- Copier une classe avec `kubectl get -o yaml` sans retirer `metadata.uid`, `resourceVersion`, l'annotation `kubectl.kubernetes.io/last-applied-configuration` et l'annotation par défaut : on crée une seconde classe par défaut.

**En production chez MédiSphère**
Le catalogue est la référence des équipes ; une classe ne naît que par MR (relue par Karim) avec sa ligne dans le catalogue, son quota (E20) et son entrée dans la VAP. Un contrôle (check, puis alerte M21) vérifie en continu qu'il y a exactement une classe par défaut.

---

### M16-E13 — Rook : un Ceph dans le cluster

**Solution**

Fichiers : [`travailleurs.tf.extrait`](fichiers/M16-E13/infra/envs/k8s/travailleurs.tf.extrait), [`k8s-rook-prerequis.yml`](fichiers/M16-E13/ansible/playbooks/k8s-rook-prerequis.yml), [`espaces/rook-ceph/00-namespace.yaml`](fichiers/M16-E13/k8s/espaces/rook-ceph/00-namespace.yaml), [`operator-values.yaml`](fichiers/M16-E13/k8s/composants/rook/operator-values.yaml), [`cluster-values.yaml`](fichiers/M16-E13/k8s/composants/rook/cluster-values.yaml), [`rook-essai.yaml`](fichiers/M16-E13/essais/rook-essai.yaml).

1. **Lecture.**
   - L'**opérateur** (`rook-ceph-operator`) fait tout : il lit le `CephCluster`, crée les MON (un déploiement par MON, `rook-ceph-mon-a/b/c`, chacun avec un Service à adresse fixe : c'est l'« adresse » du MON), le MGR, puis lance sur chaque nœud de `storage.nodes` un *job* `rook-ceph-osd-prepare-<nœud>` ; il crée aussi les identités cephx des pilotes CSI (`client.csi-rbd-provisioner`, `client.csi-rbd-node`…) et leurs Secrets (`rook-csi-rbd-provisioner`, `rook-csi-rbd-node`), et confie les pilotes à **ceph-csi-operator** (ressources `Driver`, `CephConnection`, `ClientProfile` du groupe `csi.ceph.io`).
   - Le *job* de préparation examine les disques désignés et appelle `ceph-volume` (mode `raw` ou `lvm`) pour en faire un OSD BlueStore ; il échoue (et se relance) si un disque préparé n'apparaît pas ensuite (changement 1.21). L'opérateur crée ensuite un déploiement `rook-ceph-osd-<ID>` par OSD.
   - L'état des MON (base RocksDB, clés) est sous `dataDirHostPath` (`/var/lib/rook/<espace>/mon-a/…`) **sur le nœud** : c'est un `hostPath`. Si ce répertoire reste après une désinstallation, un nouveau cluster qui démarre sur le même nœud trouve un MON de l'**ancien** cluster (autre fsid, autres clés) et ne forme jamais de quorum.
   - Le **mode externe** (`CephCluster` avec `external.enable: true`) ne crée aucun démon Ceph : Rook n'installe que les pilotes CSI et les branche sur un cluster existant (ici, ce serait `ceph-par1`), à partir des identités créées par le script `create-external-cluster-resources.py`. Notre cluster d'essai est l'inverse : un Ceph complet **dans** Kubernetes.
2. **Disques.** Plan : `# module.travailleurs["k8s-w01"].proxmox_virtual_environment_vm.vm will be updated in-place` (×3), un bloc `disk` ajouté (`interface = "scsi1"`), **aucun** `-/+`. Après `apply`, sans redémarrage (ajout à chaud de disque SCSI) :
   ```
   admin@k8s-w01:~$ lsblk -o NAME,SIZE,SERIAL,FSTYPE,MOUNTPOINTS
   sdb    32G k8s-w01-rook
   admin@k8s-w01:~$ ls -l /dev/disk/by-id/ | grep rook
   scsi-0QEMU_QEMU_HARDDISK_k8s-w01-rook -> ../../sdb
   ```
   ⚠️ À vérifier sur ton lab : le nom `by-id` dépend du modèle de contrôleur SCSI et de la série ; s'il diffère, corrige le chemin dans le playbook **et** dans `cluster-values.yaml`. Le nom `sdb`, lui, peut changer d'un démarrage à l'autre : on ne l'utilise jamais.
3. **Prérequis.** `uv run ansible-playbook playbooks/k8s-rook-prerequis.yml --check --diff`, puis sans `--check`. Le playbook échoue si le disque n'existe pas, ne fait pas 32 Gio ou porte une signature : c'est la protection contre un ordre de disques inattendu. `lvm2` sert à `ceph-volume` (il tourne dans le conteneur mais agit sur les métadonnées LVM du nœud ; sans `lvm2` sur l'hôte, les volumes ne sont pas réactivés au démarrage).
4. **Espace** : voir le fichier ; l'exception PSA est écrite dans l'annotation et dans la documentation (`docs/kubernetes/stockage/` et le registre des exceptions PSA du M14-E18 s'il existe).
5. **Opérateur.** Valeurs minimales (ressources, pas de supervision). Après installation :
   ```
   admin@adm01:~$ kubectl get crd | grep -cE 'ceph.rook.io|csi.ceph.io'
   27
   admin@adm01:~$ kubectl -n rook-ceph get pods
   ceph-csi-controller-manager-…   1/1  Running
   rook-ceph-operator-…            1/1  Running
   ```
6. **Cluster.** Le fichier de valeurs du corrigé est rendu et vérifié par `helm template` (voir l'en-tête du corrigé). Points de revue : `useAllNodes: false`, `useAllDevices: false`, trois `nodes` avec leur seul disque `…-rook` ; `requireMsgr2: true` ; `keyType: aes` ; `mon.count: 3`, `mgr.count: 1` ; ressources réduites ; tolérance du *taint* `dedie=bdd` (sinon le MON et l'OSD de `k8s-w03` ne démarrent pas) ; `cephBlockPools` avec `isDefault: false` (le rendu porte `storageclass.kubernetes.io/is-default-class: "false"`), `cephFileSystems: []`, `cephObjectStores: []`, aucune classe d'instantanés.
7. **Démarrage.** Ordre observé : MON a, b, c (quelques minutes), MGR, *jobs* `rook-ceph-osd-prepare-k8s-w0N` (`Completed`), OSD 0, 1, 2, puis les pilotes `rook-ceph.rbd.csi.ceph.com-ctrlplugin-…` et `-nodeplugin-…`.
   ```
   admin@adm01:~$ kubectl -n rook-ceph logs job/rook-ceph-osd-prepare-k8s-w01 -c provision | tail
   admin@adm01:~$ kubectl -n rook-ceph get cephcluster
   NAME        DATADIRHOSTPATH   MONCOUNT   AGE   PHASE   MESSAGE                        HEALTH      EXTERNAL   FSID
   rook-ceph   /var/lib/rook     3          9m    Ready   Cluster created successfully   HEALTH_OK              5b1c…
   admin@k8s-w01:~$ lsblk /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_k8s-w01-rook     # désormais un OSD (LVM ou raw)
   admin@k8s-w01:~$ sudo ls /var/lib/rook /var/lib/rook/rook-ceph
   ```
   Un `HEALTH_WARN` fréquent et explicable : `mon is allowing insecure global_id reclaim` (disparaît seul), `1 pool(s) do not have an application enabled` (rare avec Rook), avertissements de mémoire faible sur les OSD (cible de 1,5 Gio).
8. **Un volume** : `kubectl apply -f rook-essai.yaml` ; `kubectl -n wb-essais get pvc rook-essai` → `Bound`, `kubectl get pv <PV> -o jsonpath='{.spec.csi.driver}'` → `rook-ceph.rbd.csi.ceph.com`. Un PVC sans classe reçoit toujours `ceph-rbd`.
9. **Empreinte** (ordre de grandeur constaté en conditions similaires, à remplacer par tes mesures) : `rook-ceph` ≈ 25 pods, 3 à 4,5 Gio de mémoire au total (3 OSD × 0,9-1,4 Gio, 3 MON × 0,2-0,4 Gio, MGR 0,4-0,6 Gio, pilotes CSI, opérateurs) et 27 CRD ; `ceph-csi` (Ceph externe) ≈ 8 pods, 0,4-0,6 Gio. Rook déplace dans le cluster Kubernetes la mémoire et les disques que `ceph-par1` consomme aujourd'hui dans ses propres VMs ; il ajoute un opérateur à comprendre. Qui saurait réparer : `ceph-par1` est exploité depuis le M08 avec cephadm, runbooks à l'appui ; un Rook en panne demande de savoir à la fois Ceph **et** l'opérateur (réconciliation, CR, *jobs*), et ses démons meurent avec leur nœud Kubernetes.

**Explications**
Rook transforme Ceph en ressources Kubernetes : l'état voulu est dans les CR (`CephCluster`, `CephBlockPool`…), l'opérateur converge. On gagne une installation déclarative et intégrée (les pilotes CSI viennent avec, les clés sont créées et rangées en Secrets) ; on perd la séparation des domaines de panne : le stockage du cluster dépend du cluster, une montée de version de Kubernetes devient une opération Ceph, et les nœuds doivent porter disques et mémoire pour Ceph en plus des applications.

**Alternatives**
- Manifestes de `deploy/examples` (`crds.yaml`, `common.yaml`, `csi-operator.yaml`, `operator.yaml`, `cluster.yaml`) plutôt que les charts : même résultat, plus verbeux à adapter.
- Rook en **mode externe** vers `ceph-par1` : remplacerait les charts ceph-csi d'E06 par l'opérateur ceph-csi de Rook, avec les mêmes identités ; à considérer dans l'ADR.

**Pièges classiques**
- `useAllDevices: true` (défaut du chart) sur des nœuds qui ont d'autres disques : Rook prend tout disque sans signature, y compris celui que tu prépares pour Longhorn.
- Laisser `isDefault: true` (défaut du chart) : deux classes par défaut, la plus récente (Rook) gagne, et tous les nouveaux PVC partent sur un Ceph d'essai qu'on va détruire.
- Oublier la tolérance du *taint* de `k8s-w03` : deux MON sur trois, et un OSD manquant ; ou réduire trop la mémoire des OSD (en dessous de ~1 Gio, OOM au premier remplissage).
- Une clé CSI en `aes256k` (défaut futur de Ceph) : les nœuds 6.12 refusent de monter.

**En production chez MédiSphère**
Ce cluster n'ira pas en production (décision de Claire, ADR-0160) ; s'il le devait : nœuds de stockage dédiés (étiquettes, *taints*), trois MGR/MON répartis par baie, chiffrement des OSD, supervision par le module `prometheus` du MGR (M21), et sauvegarde des CR **et** de `/var/lib/rook` des MON (procédure de reprise après perte des MON de la documentation Rook).

---

### M16-E14 — Rook : exploiter puis démonter proprement

**Solution**

Fichiers : [`k8s-rook-nettoyage.yml`](fichiers/M16-E14/ansible/playbooks/k8s-rook-nettoyage.yml) ; le pod écrivain est celui d'E13 ([`rook-essai.yaml`](fichiers/M16-E13/essais/rook-essai.yaml)).

1. **Administrer.**
   ```
   admin@adm01:~$ alias tb='kubectl -n rook-ceph exec deploy/rook-ceph-tools --'
   admin@adm01:~$ tb ceph -s
   admin@adm01:~$ tb ceph osd tree
   admin@adm01:~$ tb ceph auth ls | grep -A3 'client.csi'
   client.csi-rbd-node
   	key: AQ…
   	caps: [mgr] allow rw
   	caps: [mon] profile rbd
   	caps: [osd] profile rbd
   admin@adm01:~$ tb ceph config dump | grep -E 'osd_memory_target|ms_' 
   ```
   `osd_memory_target` est posé par OSD, dérivé de la limite mémoire (1,5 Gio) ; `ms_mode`/`ms_cluster_mode` en `secure`/`crc` selon `requireMsgr2` et `encryption`. ⚠️ À vérifier sur ton lab : le type de clé (`aes`) n'apparaît pas toujours dans `auth ls` ; `ceph auth get client.csi-rbd-node -f json` le montre selon la version.
2. **Le CR fait foi.**
   ```
   admin@adm01:~$ tb ceph osd pool set rook-essai size 2
   admin@adm01:~$ kubectl -n rook-ceph annotate cephblockpool rook-essai medisphere.internal/essai="$(date +%s)" --overwrite
   admin@adm01:~$ sleep 60; tb ceph osd pool get rook-essai size
   size: 3
   ```
   L'opérateur réconcilie le pool sur l'état du CR (`replicated.size: 3`) et efface la modification manuelle. ⚠️ Toutes les modifications d'un champ ne déclenchent pas la réconciliation du même contrôleur ; si `size` reste à 2, redémarre l'opérateur (`kubectl -n rook-ceph rollout restart deploy/rook-ceph-operator`). Le rôle des spécifications de `plateforme/ceph` (M08-E23) est tenu ici par les **CR**, et la détection de dérive de M08 par la **boucle de réconciliation** : ce qui n'est pas dans un CR (une option `ceph config set` ad hoc) n'est pas protégé, ce qui l'est est rétabli, qu'on le veuille ou non.
3. **Perte d'un OSD.**
   ```
   admin@adm01:~$ kubectl -n rook-ceph scale deploy rook-ceph-operator --replicas=0
   admin@adm01:~$ kubectl -n rook-ceph scale deploy rook-ceph-osd-1 --replicas=0      # 14:02
   admin@adm01:~$ tb ceph -s       # 1 osds down ; Degraded data redundancy: …/… objects degraded, 33 pgs undersized
   admin@adm01:~$ kubectl -n wb-essais exec rook-essai -- tail -3 /d/horodatage.log     # l'écriture continue
   …14:13 : osd.1 marked out after 600 s ; récupération impossible (domaine host, 3 copies, 2 hôtes restants) : PG restent undersized+degraded, actifs.
   admin@adm01:~$ kubectl -n rook-ceph scale deploy rook-ceph-osd-1 --replicas=1      # 14:15
   admin@adm01:~$ kubectl -n rook-ceph scale deploy rook-ceph-operator --replicas=1
   admin@adm01:~$ tb ceph -s       # HEALTH_OK vers 14:17
   ```
   Avec trois copies et `min_size` 2, la perte d'un OSD laisse les PG actifs : l'écriture ne s'interrompt pas (quelques secondes de latence au moment de la détection). Après `mon_osd_down_out_interval` (600 s), l'OSD est marqué `out` ; comme le domaine de panne est `host` et qu'il ne reste que deux hôtes, Ceph ne peut pas reconstituer la troisième copie : les PG restent `undersized` jusqu'au retour de l'OSD. Le PDB géré par Rook (`managePodBudgets`) aurait empêché un `kubectl drain` de faire la même chose sur deux nœuds à la fois.
4. **Séquence de démontage** (celle du corrigé, d'après *Cleanup* 1.21) :

   | # | Geste | Contrôle pour continuer |
   |---|---|---|
   | 1 | Supprimer les consommateurs : pod et PVC `rook-essai` (`wb-essais`) | `kubectl get pv -o json \| jq '[.items[] \| select(.spec.csi.driver \| startswith("rook-ceph."))] \| length'` → 0 |
   | 2 | Supprimer la classe `rook-ceph-block` et le pool (par le chart : retirer `cephBlockPools` puis `helm upgrade`, ou `kubectl delete cephblockpool rook-essai`) | `kubectl -n rook-ceph get cephblockpool` vide ; `tb ceph osd pool ls` sans `rook-essai` |
   | 3 | `kubectl -n rook-ceph patch cephcluster rook-ceph --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'` | `kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.spec.cleanupPolicy.confirmation}'` |
   | 4 | `helm uninstall rook-ceph-cluster -n rook-ceph` (supprime le `CephCluster`) | `kubectl -n rook-ceph get cephcluster` vide |
   | 5 | Attendre les *jobs* `cluster-cleanup-job-k8s-w0N` (nom à relever) | trois *jobs* `Complete` ; journal d'un *job* lu |
   | 6 | `kubectl -n rook-ceph delete operatorconfigs.csi.ceph.io,drivers.csi.ceph.io,clientprofiles.csi.ceph.io,clientprofilemappings.csi.ceph.io,cephconnections.csi.ceph.io --all` | aucune ressource `csi.ceph.io` dans l'espace |
   | 7 | `helm uninstall rook-ceph -n rook-ceph` | plus de pod dans l'espace |
   | 8 | Supprimer les CRD restantes : `kubectl get crd -o name \| grep -E 'ceph.rook.io\|csi.ceph.io' \| xargs -r kubectl delete` | `kubectl get crd \| grep -cE 'ceph.rook.io\|csi.ceph.io'` → 0 |
   | 9 | `kubectl delete namespace rook-ceph` (et retrait de `espaces/rook-ceph/` et `composants/rook/` par MR) | espace absent |
   | 10 | Nœuds : `k8s-rook-nettoyage.yml` | `wipefs -n` vide, `/var/lib/rook` absent, `dmsetup ls` sans `ceph--` |

   ⚠️ Avant l'étape 8, vérifie que **seules** les CRD de Rook et de ceph-csi-operator sont listées : les CRD d'instantanés (`snapshot.storage.k8s.io`) ne doivent pas y être. Le nom des *jobs* de nettoyage (`cluster-cleanup-job-<nœud>` dans les versions récentes) est à relever dans `kubectl -n rook-ceph get jobs`.
5. **Cluster** : voir les étapes 1 à 5. Les *jobs* de nettoyage effacent `dataDirHostPath` et le contenu des disques (méthode `quick` par défaut : en-têtes et LVM) sur chaque nœud qui portait des démons. S'ils ne démarrent pas, c'est presque toujours qu'un volume de Rook existe encore.
6. **Opérateur** : étapes 6 à 9. Si l'espace reste `Terminating`, chercher la ressource qui le retient (commande `kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n rook-ceph` de la documentation) ; retirer un *finalizer* seulement si l'opérateur n'existe plus, en le notant.
7. **Nœuds.**
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-rook-nettoyage.yml --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-rook-nettoyage.yml -e confirmer_effacement=oui
   admin@k8s-w01:~$ sudo wipefs -n /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_k8s-w01-rook    # aucune ligne
   admin@k8s-w01:~$ sudo ls /var/lib/rook     # No such file or directory
   ```
   Le playbook refuse si l'espace `rook-ceph` existe encore, si le disque ne fait pas 32 Gio, s'il est monté ou porte un système de fichiers courant ; il est rejouable (idempotent sauf l'effacement, sans effet sur un disque vide).
8. **Bilan pour l'ADR** (exemple) : *avantages* — déclaratif de bout en bout, pilotes et identités CSI fournis, réparation automatique de la configuration (le CR fait foi), RGW et CephFS à la demande par des CR, *ObjectBucketClaim* ; *inconvénients* — 3 à 4,5 Gio de mémoire et trois disques de plus sur chaque cluster Kubernetes, stockage qui partage le sort du cluster (montées de version liées, panne de nœud = panne de stockage), deuxième façon d'exploiter Ceph (cephadm pour `ceph-par1`), démontage long et risqué (cette séquence en dix étapes), compétences doubles pour l'astreinte.

**Explications**
L'ordre est dicté par les dépendances : les volumes empêchent la suppression propre du cluster (et les *jobs* de nettoyage) ; le cluster empêche la suppression de l'opérateur (ses *finalizers*) ; l'opérateur et ses CRD doivent partir avant l'espace ; et les nœuds gardent un état que Kubernetes ne voit pas (`/var/lib/rook`, LVM, en-têtes BlueStore) : la dernière étape est hors du cluster.

**Alternatives**
- Sans `cleanupPolicy`, tout le nettoyage des nœuds est manuel (section *Delete the data on hosts*) : c'est ce que fait le playbook, qui sert donc aussi de filet si les *jobs* ont échoué.
- Le *job* `deploy/examples/cleanup-job.yaml` nettoie un nœud oublié par l'opérateur.

**Pièges classiques**
- Supprimer l'espace `rook-ceph` d'abord : l'opérateur disparaît avant d'avoir retiré ses *finalizers*, l'espace reste `Terminating`, les CR sont orphelins.
- Supprimer les CRD avant les CR : les CR deviennent illisibles (et les *finalizers* impossibles à retirer proprement).
- Effacer un disque par son nom court (`/dev/sdb`) : après un redémarrage, ce peut être un autre disque.
- `rm -rf /dev/mapper/ceph--*` sur un nœud qui aurait d'autres OSD LVM : ici aucun, mais c'est à vérifier à chaque fois.

**En production chez MédiSphère**
Tout retrait de composant de stockage suit un runbook relu, avec le tableau « geste / contrôle » ci-dessus, une fenêtre annoncée, et une vérification finale par un check. Les disques sont ensuite **détruits** par OpenTofu (mini-projet), pas laissés « vides » indéfiniment.

---

### M16-E15 — Longhorn : du stockage répliqué sur les nœuds

**Solution**

Fichiers : [`travailleurs.tf.extrait`](fichiers/M16-E15/infra/envs/k8s/travailleurs.tf.extrait), rôle [`longhorn_prerequis`](fichiers/M16-E15/ansible/roles/longhorn_prerequis/) et [`k8s-longhorn-prerequis.yml`](fichiers/M16-E15/ansible/playbooks/k8s-longhorn-prerequis.yml), [`00-namespace.yaml`](fichiers/M16-E15/k8s/espaces/longhorn-system/00-namespace.yaml), [`values.yaml`](fichiers/M16-E15/k8s/composants/longhorn/values.yaml), [`lh-essai.yaml`](fichiers/M16-E15/essais/lh-essai.yaml), [`cible-sauvegarde.sh`](fichiers/M16-E15/essais/cible-sauvegarde.sh), identité S3 dans [`seaweedfs.yml.extrait`](fichiers/M16-E16/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait) (lignes commentées `longhorn-essai`).

1. **Lecture.** Les données d'un volume sont des **fichiers** (fichiers creux par instantané) sous `/var/lib/longhorn/replicas/<volume>-<id>/` sur chaque nœud qui porte un réplica. Le **moteur** (un processus par volume, dans l'*instance manager* du nœud du pod) reçoit les E/S du pod par un périphérique iSCSI local et les **réplique lui-même**, en synchrone, vers chaque réplica par le réseau des pods : pas de serveur central. iSCSI sert de tuyau entre le noyau (bloc) et le moteur en espace utilisateur (moteur V1). Le moteur V2 (SPDK, NVMe/TCP, GA en 1.13) remplace iSCSI et le moteur V1 pour de meilleures performances, au prix de cœurs dédiés (*polling*), de *hugepages* et de disques en mode bloc : déraisonnable sur nos travailleurs de 4 vCPU.
2. **Disques et nœuds.** Plan OpenTofu : un disque ajouté par VM, en place. Le rôle refuse un disque qui ne fait pas 32 Gio ou qui porte un autre système de fichiers que l'ext4 étiqueté `longhorn`. `longhornctl` :
   ```
   admin@adm01:~$ curl -fsSLO https://github.com/longhorn/cli/releases/download/v1.13.0/longhornctl-linux-amd64
   admin@adm01:~$ sha256sum longhornctl-linux-amd64        # à comparer à l'empreinte publiée avec la version
   admin@adm01:~$ install -m 0755 longhornctl-linux-amd64 ~/.local/bin/longhornctl
   admin@adm01:~$ longhornctl check preflight --kubeconfig ~/.kube/config
   ```
   ⚠️ À vérifier sur ton lab : `longhornctl check preflight` lance un DaemonSet de contrôle dans le cluster (il lui faut un espace où il peut tourner privilégié) ; ses options exactes sont dans `longhornctl check preflight --help`. Résultat attendu : `iscsid` actif, `nfs-common`, `cryptsetup`, `dmsetup` présents, module `iscsi_tcp` chargé, propagation de montage `rshared` sur `/var/lib/kubelet`.
3. **Installation.** Le rendu (`helm template … --kube-version 1.36.5`) montre `is-default-class: "false"`, `default-data-path: /var/lib/longhorn/`, `deleting-confirmation-flag: false`. Après installation :
   ```
   admin@adm01:~$ kubectl -n longhorn-system get nodes.longhorn.io
   NAME      READY   ALLOWSCHEDULING   SCHEDULABLE   AGE
   k8s-w01   True    true              True          3m
   …
   admin@adm01:~$ kubectl get sc       # ceph-rbd (default), ceph-rbd-retain, cephfs, longhorn
   ```
   Les nœuds de contrôle n'apparaissent pas : le gestionnaire (DaemonSet) ne tolère pas leur *taint*. ⚠️ À vérifier sur ton lab : si `k8s-w03` porte encore `dedie=bdd:NoSchedule`, il n'y a pas de gestionnaire Longhorn dessus (donc pas de réplica) : tolère-le (valeurs `longhornManager.tolerations`, `longhornDriver.tolerations`, et réglage `taintToleration`) ou constate qu'on ne peut alors avoir que deux réplicas par volume.
4. **Volume répliqué.**
   ```
   admin@adm01:~/m16/e15$ kubectl apply -f lh-essai.yaml          # seulement PVC + pod à cette étape
   admin@adm01:~$ kubectl -n longhorn-system get volumes.longhorn.io
   admin@adm01:~$ kubectl -n longhorn-system get replicas.longhorn.io -o custom-columns=NOM:.metadata.name,NOEUD:.spec.nodeID,ETAT:.status.currentState
   admin@k8s-w02:~$ sudo ls -lsh /var/lib/longhorn/replicas/pvc-*/
   volume-head-000.img  volume-head-000.img.meta  volume.meta
   ```
5. **Casser un réplica.**
   ```
   admin@adm01:~$ kubectl -n longhorn-system delete replicas.longhorn.io <REPLICA-SUR-UN-AUTRE-NŒUD>
   admin@adm01:~$ kubectl -n longhorn-system get volumes.longhorn.io <VOLUME> -w -o custom-columns=ROBUSTESSE:.status.robustness
   degraded … healthy
   ```
   Le volume passe `degraded`, Longhorn recrée un réplica (sur le même nœud ou un autre, selon l'anti-affinité) et le reconstruit en copiant les données d'un réplica sain : quelques dizaines de secondes pour 2 Gio peu remplis. Le pod continue d'écrire : le moteur sert les E/S avec les réplicas restants.
6. **Instantané et sauvegarde.** `longhorn-snap` (`type: snap`) crée un instantané **sur les réplicas** (un nouveau fichier de différences) : même limite que les instantanés Ceph, il vit avec le volume. La sauvegarde exige une cible :
   ```
   admin@adm01:~/m16/e15$ ./cible-sauvegarde.sh poser
   admin@adm01:~$ kubectl -n longhorn-system get backuptargets.longhorn.io default -o jsonpath='{.status.available}'
   true
   admin@adm01:~$ kubectl apply -f lh-essai.yaml                  # la classe longhorn-bak et lh-essai-bak
   admin@adm01:~$ (set -a; . ~/.config/workbook/s3-longhorn-essai.env; set +a; aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls --recursive s3://longhorn-essai/ | head)
   backupstore/volumes/…/pvc-…/volume.cfg
   backupstore/volumes/…/pvc-…/backups/backup_backup-….cfg
   backupstore/volumes/…/pvc-…/blocks/…/….blk
   ```
   Une sauvegarde Longhorn découpe le volume en blocs de 2 Mio, compressés et dédupliqués, et un fichier de description par sauvegarde : elle est **incrémentale** et restaurable dans un autre cluster qui voit la même cible. `lh-restauree` (dataSource vers `lh-essai-bak`) restaure depuis S3 ; la comparaison des empreintes de `horodatage.log` (jusqu'à l'heure de la sauvegarde) confirme. ⚠️ À vérifier sur ton lab : avec SeaweedFS, Longhorn peut exiger `VIRTUAL_HOSTED_STYLE` absent (adressage par chemin, défaut) et une région quelconque dans l'URL ; si la cible reste indisponible, lis le journal du gestionnaire.
7. **Mesures** (exemple de démarche) : `dd if=/dev/zero of=/d/essai bs=4M count=256 oflag=direct` trois fois dans `lh-essai` et dans un pod sur `ceph-rbd`. Attendu : Longhorn sur `hdd-bulk` nettement plus lent en écriture que `ceph-rbd` sur OSD `ssd-lab`, la réplication synchrone à trois passant par le réseau des pods (VXLAN, MTU 1500) ; la comparaison honnête demanderait des disques de même classe (E28).
8. **Retrait.**
   ```
   admin@adm01:~$ kubectl -n wb-essais delete pod lh-essai --ignore-not-found
   admin@adm01:~$ kubectl -n wb-essais delete volumesnapshot lh-essai-snap lh-essai-bak --ignore-not-found
   admin@adm01:~$ kubectl -n wb-essais delete pvc lh-essai lh-restauree --ignore-not-found
   admin@adm01:~$ kubectl delete volumesnapshotclass longhorn-snap longhorn-bak
   admin@adm01:~/m16/e15$ ./cible-sauvegarde.sh retirer
   admin@adm01:~$ kubectl -n longhorn-system patch settings.longhorn.io deleting-confirmation-flag --type merge -p '{"value":"true"}'
   admin@adm01:~$ helm uninstall longhorn -n longhorn-system --timeout 10m
   admin@adm01:~$ kubectl get crd | grep -c longhorn.io ; kubectl get csidriver driver.longhorn.io
   admin@adm01:~$ kubectl delete namespace longhorn-system
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-longhorn-prerequis.yml -e longhorn_prerequis_etat=absent
   ```
   Le *job* `longhorn-uninstall` (crochet `pre-delete` du chart) supprime les ressources de Longhorn puis les CRD ; il échoue tant que le drapeau vaut `false`. Côté S3 : MR qui retire l'identité et le compartiment (le rôle `seaweedfs` ne supprime pas un compartiment de lui-même : `weed shell` → `s3.bucket.delete -name longhorn-essai`, fait à la main par l'administrateur S3, consigné), `shred -u ~/.config/workbook/s3-longhorn-essai.env`, ligne retirée du registre des secrets.
9. **Avis pour l'ADR** (exemple) : *avantages* — installation en une commande, interface claire, sauvegarde S3 incrémentale intégrée et restaurable ailleurs, instantanés et clones, aucun cluster de stockage à exploiter ; *inconvénients* — performances limitées par la réplication synchrone en espace utilisateur et le réseau des pods, disques et mémoire pris sur les travailleurs (comme Rook), privilèges élevés et iSCSI sur chaque nœud, deuxième système de stockage à côté de `ceph-par1` qui existe et que l'équipe maîtrise, pas de stockage objet ni de fichier natif (RWX par un serveur NFS par volume).

**Explications**
Longhorn est un stockage **par volume** : chaque volume a son moteur et ses réplicas, ce qui isole les pannes et simplifie le modèle, mais multiplie les processus et fait passer toute la réplication par le réseau du cluster. Les deux retraits (Rook, Longhorn) montrent la même leçon : un stockage dans le cluster laisse des traces **sur les nœuds** que Kubernetes ne connaît pas.

**Alternatives**
- `longhornctl install preflight` installe lui-même les dépendances des nœuds ; on préfère le rôle Ansible (code relu, rejouable, réversible).
- Désinstallation par `kubectl` (`uninstall.yaml`) si Longhorn a été installé par manifeste.

**Pièges classiques**
- `persistence.defaultClass: true` (défaut du chart) : deuxième classe par défaut.
- `open-iscsi` 2.1.12 : attachements en échec (avertissement de la documentation 1.13).
- Supprimer l'espace `longhorn-system` avant la désinstallation : CRD et *finalizers* orphelins, volumes bloqués.
- Poser une règle de cycle de vie S3 sur le compartiment de Longhorn : interdit par la documentation (Longhorn gère lui-même ses blocs).

**En production chez MédiSphère**
Longhorn n'est pas retenu (ADR-0160) ; il resterait une option pour un site sans Ceph (agence avec k3s, M18), avec sa sauvegarde S3 vers PAR1.

---

### M16-E16 — Velero : sauvegarder des espaces de noms

**Solution**

Fichiers : identités et compartiments [`seaweedfs.yml.extrait`](fichiers/M16-E16/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait) et [`vault.yml.extrait`](fichiers/M16-E16/ansible/inventories/lab/host_vars/s3-01/vault.yml.extrait), [`espaces/velero/00-namespace.yaml`](fichiers/M16-E16/k8s/espaces/velero/00-namespace.yaml), [`outils/secrets-sauvegarde.sh`](fichiers/M16-E16/k8s/outils/secrets-sauvegarde.sh), [`outils/installer-velero-cli.sh`](fichiers/M16-E16/k8s/outils/installer-velero-cli.sh), [`composants/velero/values.yaml`](fichiers/M16-E16/k8s/composants/velero/values.yaml), [`planifications.yaml`](fichiers/M16-E16/k8s/composants/velero/planifications.yaml), [`velero-essai.yaml`](fichiers/M16-E16/essais/velero-essai.yaml), [`matrice-flux.md.extrait`](fichiers/M16-E16/medisphere/docs/socle/matrice-flux.md.extrait).

1. **Lecture.** Une sauvegarde Velero est un dossier `backups/<nom>/` du compartiment : l'archive `<nom>.tar.gz` (chaque ressource de l'API en JSON, rangée par groupe, ressource et espace), le journal, la liste des ressources, l'état des volumes (instantanés, sauvegardes Kopia) et des métadonnées (`velero-backup.json`). Non sauvegardé par défaut : les ressources de **cluster** non liées aux espaces sauvegardés (Velero inclut celles qui sont référencées, comme les PV, et `--include-cluster-resources` élargit), les **données** des volumes (sauf méthode explicite, E17), les objets exclus par défaut (événements, `nodes`, objets de Velero lui-même). Un objet qui existe déjà n'est **pas** remplacé : il est ignoré avec un avertissement (`--existing-resource-policy update` tente une mise à jour). Velero restaure **un** espace ou **un** objet, ailleurs ou sous un autre nom, sans toucher au reste, et ses sauvegardes sont hors du cluster ; l'instantané etcd est le seul moyen de reconstruire le **plan de contrôle** (tout, à un instant, y compris RBAC, CRD et Velero lui-même), mais il est global et ne contient aucune donnée de volume.
2. **S3.** Dans le rôle `seaweedfs` (M05) : identité `velero` limitée au compartiment, compartiment **sans** versionnage (justification dans l'extrait : Velero et Kopia suppriment eux-mêmes ce qui expire ; sans règle de cycle de vie, chaque suppression laisserait une version cachée et remplirait `s3-01`). Clés générées et rangées comme au M05-E10 (Vault `lab`, `s3-velero.env` en 600, registre des secrets). Contrôle :
   ```
   admin@adm01:~$ (set -a; . ~/.config/workbook/s3-velero.env; set +a
   >   aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls s3://velero-k8s-par1/ && echo autorisé
   >   aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls s3://tofu-state/ || echo refusé)
   autorisé
   An error occurred (AccessDenied) …
   refusé
   ```
   Flux : la règle VLAN 40 → 10.10.20.14:8333 du M14 vise 10.10.40.0/24 ; les pods sont masqués derrière l'adresse de leur nœud (Cilium) : rien à ouvrir. Un essai depuis un pod : `kubectl run -n wb-essais s3 --rm -it --image=registry.par1.medisphere.internal/dockerhub/curlimages/curl:8.16.0 --restart=Never -- curl -sS -o /dev/null -w '%{http_code}\n' https://s3-01.par1.medisphere.internal:8333/` → `403` (joint, refusé sans identité) ; un délai d'attente voudrait dire flux bloqué. ⚠️ Le certificat de `s3-01` est signé par la racine MédiSphère : `curl` dans une image publique ne la connaît pas, ajoute `--cacert` (fichier monté) ou constate seulement la connexion TCP (`-k` pour **ce seul essai de flux**, jamais ailleurs).
3. **CLI.** `outils/installer-velero-cli.sh` : télécharge l'archive et `CHECKSUM`, exige que l'empreinte publiée soit celle figée dans le script (relue en MR), installe ; `velero version --client-only` → `Version: v1.18.4`.
4. **Secret et espace.** `kubectl apply -f espaces/velero/00-namespace.yaml`, puis `outils/secrets-sauvegarde.sh velero`. Le script lit le fichier `.env` (refus s'il n'est pas en 600), fabrique le fichier d'identifiants dans une substitution de processus (`<(printf …)`), et le passe à `kubectl create secret … --dry-run=client -o yaml | kubectl apply -f -` : la clé ne passe ni sur une ligne de commande (visible dans `ps`) ni dans un fichier.
5. **Installation.** Les valeurs (rendues sans erreur par `helm template`) : image `velero/velero:v1.18.4` (la version applicative du chart est 1.18.2), plugin en conteneur d'initialisation, `snapshotsEnabled: false` (aucune `VolumeSnapshotLocation`), `credentials.existingSecret: velero-s3` (monté sous `/credentials/cloud`), `deployNodeAgent: true` avec la tolérance du *taint* de `k8s-w03`, `configuration.features: EnableCSI`, `uploaderType: kopia`, une BSL `s3-01` par défaut avec `caCert` (racine en base 64) et `s3ForcePathStyle: "true"` (SeaweedFS ne sert pas l'adressage virtuel), `s3Url`, `region`.
   ```
   admin@adm01:~$ velero backup-location get
   NAME    PROVIDER   BUCKET/PREFIX     PHASE       LAST VALIDATED   ACCESS MODE   DEFAULT
   s3-01   aws        velero-k8s-par1   Available   …                ReadWrite     true
   admin@adm01:~$ kubectl -n velero get ds node-agent -o wide     # 3/3 sur les travailleurs
   admin@adm01:~$ velero client config set features=EnableCSI
   ```
   Si la BSL reste `Unavailable` : `kubectl -n velero logs deploy/velero | grep -i backupstoragelocation` donne la cause (identifiants, `x509: certificate signed by unknown authority`, compartiment). `caCert` est **déprécié** en 1.18 au profit de `caCertRef` (référence de Secret) ; le chart 12.2.1 ne sait écrire que `caCert`, on le garde et on migrera quand le chart le permettra (la CA est publique : la versionner ne pose pas de problème).
6. **Première sauvegarde.**
   ```
   admin@adm01:~/m16/e16$ kubectl apply -f velero-essai.yaml
   admin@adm01:~$ velero backup create essai-1 --include-namespaces wb-essais --wait
   admin@adm01:~$ velero backup describe essai-1 --details | sed -n '1,40p'
   admin@adm01:~$ velero backup download essai-1 -o /tmp/essai-1.tar.gz && mkdir -p /tmp/essai-1 && tar -xzf /tmp/essai-1.tar.gz -C /tmp/essai-1
   admin@adm01:~$ jq -r '.data.jeton' /tmp/essai-1/resources/secrets/namespaces/wb-essais/velero-essai.json | base64 -d
   ceci-est-un-faux-secret-de-test
   admin@adm01:~$ rm -rf /tmp/essai-1 /tmp/essai-1.tar.gz
   ```
   Les Secrets sont dans l'archive, **en clair** (base 64) : quiconque lit `velero-k8s-par1` lit tous les Secrets des espaces sauvegardés. Conséquences : identité S3 dédiée et limitée au compartiment, accès au compartiment réservé à Velero et à l'administrateur S3, chiffrement côté serveur ou des sauvegardes à étudier (E32), copie hors site chiffrée (F5). `velero backup download` passe par une URL signée vers `s3-01` : `adm01` doit joindre `s3-01:8333` (MGMT joint tout).
7. **Restaurations.**
   ```
   # (a) un seul objet
   admin@adm01:~$ kubectl -n wb-essais delete deploy velero-essai
   admin@adm01:~$ velero restore create r-deploy --from-backup essai-1 --include-resources deployments --selector app.kubernetes.io/name=velero-essai --wait
   # (b) objet existant modifié
   admin@adm01:~$ kubectl -n wb-essais patch cm velero-essai -p '{"data":{"message":"version 2"}}'
   admin@adm01:~$ velero restore create r-cm --from-backup essai-1 --include-resources configmaps --wait
   admin@adm01:~$ velero restore describe r-cm        # Warnings: … already exists in cluster … ; la ConfigMap garde « version 2 »
   admin@adm01:~$ velero restore create r-cm-maj --from-backup essai-1 --include-resources configmaps --existing-resource-policy update --wait
   # (c) tout l'espace (après avoir vérifié ce qu'il contient)
   admin@adm01:~$ kubectl delete namespace wb-essais
   admin@adm01:~$ velero restore create r-tout --from-backup essai-1 --wait
   ```
   ⚠️ Pour (c), `wb-essais` contient encore les objets d'E10-E11 (PVC et instantanés) : leurs **données** ne sont pas dans `essai-1` (sauvegarde sans volumes) ; Velero recrée des PVC qui se provisionnent **vides**. Soit tu acceptes de les perdre (essais terminés, E10 et E11 vérifiés), soit tu fais (c) sur un espace de test dédié. `--existing-resource-policy update` met à jour les objets qui diffèrent, sauf ceux que Velero ne sait pas mettre à jour (il le dit en avertissement).
8. **Planification.** `CRON_TZ=Europe/Paris 30 2 * * *` (sans préfixe, l'expression est en UTC) ; `velero schedule describe mediagenda-dev-quotidienne` montre la prochaine exécution. Déclenchement immédiat : `velero backup create --from-schedule mediagenda-dev-quotidienne --wait`. La ressource versionnée (`planifications.yaml`) est appliquée par `kubectl apply` ; `useOwnerReferencesInBackup: false` évite que la suppression de la planification n'emporte ses sauvegardes.
9. **Ce qui manque pour une perte totale** : un cluster neuf avec Velero installé à l'identique et la BSL `s3-01` en **lecture seule** (`accessMode: ReadOnly`, pour ne rien effacer de l'existant), les mêmes noms de classes (ou un remappage), les CRD des opérateurs présentes avant la restauration de leurs CR, des volumes sauvegardés hors de Ceph (E17), les Secrets du stockage recréés par la plateforme, et une copie des sauvegardes hors de `s3-01` (qui est une VM de PAR1). C'est l'objet d'E24 et de F5.

**Explications**
Velero est un client de l'API : il lit les objets (avec ses propres droits, très larges), les écrit dans un magasin d'objets, et les recrée par l'API à la restauration, en appliquant des règles (ordre de restauration, objets existants, remappages). Le magasin est la seule source de vérité des sauvegardes : la synchronisation périodique (`backupSyncPeriod`) recrée les objets `Backup` d'un cluster neuf à partir du compartiment.

**Alternatives**
- `velero install` (CLI) plutôt que le chart : plus simple, mais l'installation n'est plus décrite par des valeurs versionnées que le M17 (Helmfile) reprendra ; avec `--secret-file`, il faut un fichier d'identifiants sur disque.
- Une identité S3 en lecture seule pour un second cluster qui ne fait que restaurer (PRA).

**Pièges classiques**
- Oublier `s3ForcePathStyle: "true"` : la BSL peut paraître disponible, mais téléchargements et restaurations échouent (le SDK vise `velero-k8s-par1.s3-01…`).
- `insecureSkipTLSVerify: "true"` « pour que ça marche » : interdit (et inutile avec `caCert`).
- Une planification sans `CRON_TZ` : décalage d'une ou deux heures selon la saison.
- Restaurer par-dessus un espace existant en croyant écraser : rien n'est remplacé sans `--existing-resource-policy`.

**En production chez MédiSphère**
Une planification par espace d'équipe (quotidienne, 7 jours ; hebdomadaire, 5 semaines) étiquetée pour la supervision, une alerte sur les sauvegardes `Failed`/`PartiallyFailed` (M21), un test de restauration mensuel dans `wb-restauration` (E24) et la politique de sauvegarde (E32) qui dit qui peut lire le compartiment.

---

### M16-E17 — Velero : volumes, Kopia et snapshots CSI

**Solution**

Fichiers : classes d'instantanés étiquetées [`ceph-rbd-snap.yaml`](fichiers/M16-E17/k8s/composants/ceph-csi/classes/ceph-rbd-snap.yaml) et [`cephfs-snap.yaml`](fichiers/M16-E17/k8s/composants/ceph-csi/classes/cephfs-snap.yaml), [`planifications.yaml`](fichiers/M16-E17/k8s/composants/velero/planifications.yaml), [`vol-essai.yaml`](fichiers/M16-E17/essais/vol-essai.yaml), [`remplir.sh`](fichiers/M16-E17/essais/remplir.sh) ; sous-commande `velero-kopia` de [`secrets-sauvegarde.sh`](fichiers/M16-E16/k8s/outils/secrets-sauvegarde.sh).

1. **Lecture.**

   | Méthode | Où sont les données à la fin | Qui lit, depuis quoi | Cohérence |
   |---|---|---|---|
   | *fs-backup* (Kopia par `node-agent`) | dépôt Kopia dans `velero-k8s-par1` (`kopia/<espace>/`) | le `node-agent` du nœud du pod lit **les fichiers du volume monté**, en service | aucune : fichiers lus pendant qu'ils changent |
   | instantané CSI seul | dans **Ceph** (`VolumeSnapshotContent` gardé, instantané RBD/CephFS) ; l'archive ne contient que les références | le pilote CSI | instantané : cohérent au niveau bloc (coupure de courant) |
   | instantané CSI + *data mover* | dépôt Kopia dans `velero-k8s-par1` ; l'instantané est **supprimé** de Ceph après la copie | un pod de déplacement monte un volume créé **depuis l'instantané** et le lit avec Kopia | celle de l'instantané (bloc) |

2. **Mot de passe des dépôts.** Il rejoint le Vault `critique` de `plateforme/k8s`, à côté de `secrets/ceph-csi.yml` (E06) :
   ```
   admin@adm01:~$ kubectl -n velero get backuprepositories       # « No resources found » : on peut encore le changer
   admin@adm01:~/src/k8s$ openssl rand -base64 48 | tr -d '\n' > /dev/shm/kopia
   admin@adm01:~/src/k8s$ ( cd ~/src/ansible && printf 'velero_kopia_mot_de_passe: "%s"\n' "$(cat /dev/shm/kopia)" \
   >     | uv run ansible-vault encrypt --encrypt-vault-id critique --output ~/src/k8s/secrets/velero.yml - )
   admin@adm01:~/src/k8s$ outils/secrets-sauvegarde.sh velero-kopia < /dev/shm/kopia && shred -u /dev/shm/kopia
   secrets-sauvegarde : velero/velero-repo-credentials à jour
   ```
   `/dev/shm` est en mémoire : le mot de passe ne touche pas le disque ; il ne passe pas non plus sur une ligne de commande (`printf` est une commande interne du shell). Pour le rejouer (cluster reconstruit) : `(cd ~/src/ansible && uv run ansible-vault view ~/src/k8s/secrets/velero.yml) | yq -r '.velero_kopia_mot_de_passe' | outils/secrets-sauvegarde.sh velero-kopia`. Le script refuse dès qu'un `BackupRepository` existe : changer ce mot de passe après coup rend les dépôts existants illisibles (documentation *File System Backup*). Ligne au registre des secrets : portée « tous les dépôts Kopia de Velero de `k8s-par1` », emplacements « Vault `critique` (`plateforme/k8s/secrets/velero.yml`), Secret `velero/velero-repo-credentials` », rotation « jamais (nouveau dépôt) ».
3. **Étiquettes** : `velero.io/csi-volumesnapshot-class: "true"` sur une seule classe par pilote ; `composants/ceph-csi/installer.sh` les applique.
4. **Application d'essai** : `kubectl apply -f vol-essai.yaml`, puis `./remplir.sh` (200 fichiers de 1 Mio par volume, `MANIFESTE` à la racine).
5. **fs-backup.**
   ```
   admin@adm01:~$ velero backup create vol-fs --include-namespaces wb-essais --selector app.kubernetes.io/name=vol-essai \
       --default-volumes-to-fs-backup --snapshot-volumes=false --wait
   admin@adm01:~$ kubectl -n velero get podvolumebackups -l velero.io/backup-name=vol-fs
   admin@adm01:~$ aws … s3 ls s3://velero-k8s-par1/kopia/wb-essais/ | head
   ```
   Option de sauvegarde plutôt qu'annotation : le choix reste dans la commande ou la planification (l'annotation `backup.velero.io/backup-volumes` sur le modèle de pod du StatefulSet marche aussi, mais lie la méthode de sauvegarde au manifeste de l'application). Le `--selector` limite la sauvegarde aux objets étiquetés (le StatefulSet, ses pods, et ses PVC qui portent les étiquettes du modèle) ; ⚠️ à vérifier : les PVC créés par `volumeClaimTemplates` portent les étiquettes de `metadata.labels` du gabarit de volume, pas celles du pod ; s'ils ne sont pas pris, retire le sélecteur.
6. **Instantanés sans déplacement.**
   ```
   admin@adm01:~$ velero backup create vol-snap --include-namespaces wb-essais --selector app.kubernetes.io/name=vol-essai --snapshot-volumes --wait
   admin@adm01:~$ kubectl get volumesnapshotcontent | grep velero     # gardés (VolumeSnapshot supprimés de l'espace, contenus retenus)
   [root@ceph01 ~]# rbd ls k8s-rbd | grep csi-snap
   admin@adm01:~$ velero backup delete vol-snap --confirm             # Velero supprime aussi les instantanés dans Ceph
   ```
   Les données ne sont **que** dans Ceph : la sauvegarde ne survit pas à la perte de `ceph-par1`. C'est rapide et utile pour un retour arrière local ; ce n'est pas ce que demande Sophie.
7. **Déplacement des données.**
   ```
   admin@adm01:~$ velero backup create vol-dm --include-namespaces wb-essais --selector app.kubernetes.io/name=vol-essai --snapshot-move-data --wait
   admin@adm01:~$ kubectl -n velero get datauploads -o wide -l velero.io/backup-name=vol-dm
   NAME           STATUS      …   BYTES DONE   TOTAL BYTES   INCREMENTAL BYTES   …
   vol-dm-xxxx    Completed       210 MiB      210 MiB       210 MiB
   admin@adm01:~/m16/e17$ ./remplir.sh modifier
   admin@adm01:~$ velero backup create vol-dm-2 --include-namespaces wb-essais --selector app.kubernetes.io/name=vol-essai --snapshot-move-data --wait
   admin@adm01:~$ kubectl -n velero get datauploads -o wide -l velero.io/backup-name=vol-dm-2   # INCREMENTAL ≈ 10 MiB pour /rbd
   ```
   Pendant la sauvegarde, un PVC et un pod temporaires apparaissent dans `velero` (volume créé depuis l'instantané) : c'est le *data mover*. Pour CephFS, ce volume est une copie complète du sous-volume (restauration d'instantané CephFS, E10) : plus lent ; la documentation de Velero permet de désigner une classe « superficielle » (`backingSnapshot`) pour ces volumes de lecture (configuration `backupPVC` du `node-agent`) ⚠️ à vérifier sur ta version.
8. **Restaurations prouvées.**
   ```
   admin@adm01:~$ kubectl -n wb-essais delete sts vol-essai && kubectl -n wb-essais delete pvc -l app.kubernetes.io/name=vol-essai
   admin@adm01:~$ kubectl -n wb-essais get pvc | grep vol-essai || echo "plus de PVC"     # vérifier AVANT de restaurer
   admin@adm01:~$ time velero restore create r-vol-fs --from-backup vol-fs --wait
   admin@adm01:~/m16/e17$ ./remplir.sh verifier
   == /rbd
   tout est OK
   == /fs
   tout est OK
   ```
   Même chose avec `vol-dm` (suivre `kubectl -n velero get datadownloads`). Pour *fs-backup*, Velero injecte dans le pod restauré un conteneur d'initialisation `restore-wait` (image de Velero) qui attend que le `node-agent` ait réécrit les fichiers. ⚠️ Dans les espaces `mediagenda-*`, la politique d'images du M14 refuse ce conteneur s'il vient de `docker.io/velero/velero` : la ConfigMap `fs-restore-action-config` de Velero permet d'en changer l'image (pour E24).
9. **Cohérence.** Copier les fichiers d'un PostgreSQL en marche donne des pages à des instants différents et des WAL qui ne correspondent pas : ce n'est pas une sauvegarde, au mieux un état « après plantage » non garanti. Les *hooks* Velero (`pre.hook.backup.velero.io/command` sur le pod) peuvent geler l'application (`fsfreeze`, `pg_backup_start`) avant l'instantané ; pour PostgreSQL, la sauvegarde de l'opérateur (WAL + base, E19) est faite pour cela, restaure à la seconde près et est vérifiée par CNPG. Choix : **Valkey** (cache reconstructible, persistance AOF) → instantané + *data mover*, ou même rien ; **fichiers de MédiDoc** (CephFS ou S3) → *data mover* pour CephFS, et pour le S3, la réplication/versionnage du magasin d'objets ; **base** → CNPG, et Velero ne sauvegarde que les objets (`Cluster`, `ObjectStore`, Secrets), pas les PVC des instances.
10. **Planification** : `snapshotVolumes: true`, `snapshotMoveData: true`, `defaultVolumesToFsBackup: false` dans le modèle de `mediagenda-dev-quotidienne`.

**Explications**
Velero délègue la lecture des données : au pilote CSI pour l'instantané, à Kopia pour la copie. Kopia découpe les données en blocs dédupliqués et chiffrés (avec le mot de passe du dépôt), d'où des sauvegardes incrémentales efficaces et la nécessité de protéger ce mot de passe (sans lui, les sauvegardes sont illisibles ; avec lui et le compartiment, elles sont lisibles). Le *data mover* combine les deux : un instantané cohérent, puis une copie qui quitte le stockage d'origine.

**Alternatives**
- Les instantanés CNPG par CSI (`method: volumeSnapshot`) pour des bases volumineuses, plus WAL dans S3.
- Une copie des instantanés RBD vers un autre cluster Ceph (miroir RBD) : hors périmètre, mais c'est la voie « stockage » de la reprise d'activité.

**Pièges classiques**
- Deux `VolumeSnapshotClass` étiquetées pour Velero sur le même pilote : Velero ne sait pas laquelle prendre.
- Restaurer alors que les PVC existent encore (bloqués par `pvc-protection`) : la restauration des volumes est ignorée, le StatefulSet repart sur… rien de restauré.
- Oublier que `--snapshot-move-data` exige le `node-agent` : la sauvegarde est refusée à la validation (changement 1.18).

**En production chez MédiSphère**
Pour chaque volume, la méthode est écrite dans la politique de sauvegarde (E32) ; le mot de passe Kopia est au Vault `critique` et dans l'enveloppe de reprise d'activité (F5) ; les tests de restauration vérifient des **empreintes**, pas des statuts.

---

### M16-E18 — CloudNativePG : la base de MédiAgenda

**Solution**

Fichiers : [`espaces/cnpg-system/00-namespace.yaml`](fichiers/M16-E18/k8s/espaces/cnpg-system/00-namespace.yaml), [`composants/cloudnative-pg/values.yaml`](fichiers/M16-E18/k8s/composants/cloudnative-pg/values.yaml), [`composants/plugin-barman-cloud/values.yaml`](fichiers/M16-E18/k8s/composants/plugin-barman-cloud/values.yaml), [`40-reseau-postgresql.yaml`](fichiers/M16-E18/k8s/espaces/mediagenda-recette/40-reseau-postgresql.yaml), [`50-mediagenda-db.yaml`](fichiers/M16-E18/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml), [`55-mediagenda-migration.yaml`](fichiers/M16-E18/k8s/espaces/mediagenda-recette/55-mediagenda-migration.yaml), [`api-base.extrait.yaml`](fichiers/M16-E18/k8s/espaces/mediagenda-recette/api-base.extrait.yaml).

1. **Lecture.**
   - La **bascule** est décidée par l'**opérateur** : il surveille chaque instance (le gestionnaire d'instance, PID 1 du pod, expose son état sur le port 8000) et, si le primaire disparaît, promeut la réplique la plus avancée et met à jour les étiquettes (`cnpg.io/instanceRole=primary`). Pas de Patroni ni d'etcd dédié : l'API Kubernetes est la source de vérité.
   - L'application vise le Service `mediagenda-db-rw`, dont le sélecteur suit l'étiquette du primaire : après une bascule, les nouvelles connexions arrivent sur le nouveau primaire, sans changement d'adresse. Les connexions ouvertes sont coupées : l'application doit se reconnecter (le pool psycopg de MédiAgenda le fait).
   - `synchronous` avec `method: any`, `number: 1` : chaque validation attend qu'**au moins une** réplique l'ait écrite ; `dataDurability: required` interdit de dégrader ce réglage quand il n'y a plus assez de répliques : les écritures **attendent** au lieu de continuer sans copie. Coût : latence d'écriture (un aller-retour réseau), et disponibilité en écriture réduite si les deux répliques tombent. `preferred` choisirait la disponibilité.
   - Pas de StatefulSet : CNPG gère chaque instance (pod et PVC) individuellement, pour choisir **quelle** instance redémarrer, promouvoir, recréer (un StatefulSet impose l'ordre et l'identité des pods, et ne sait rien du rôle primaire/réplique).
2. **Opérateur et plugin.** Points clés des valeurs : `image.repository` de l'opérateur vers `registry.par1.medisphere.internal/ghcr/cloudnative-pg/cloudnative-pg` (le rendu contient `OPERATOR_IMAGE_NAME` avec ce préfixe, que l'opérateur injecte comme conteneur d'initialisation `bootstrap-controller` dans les pods PostgreSQL) ; `image` et `sidecarImage` du plugin vers le même cache (le rendu contient `SIDECAR_IMAGE: registry.par1…/ghcr/cloudnative-pg/plugin-barman-cloud-sidecar:v0.15.1`).
   ```
   admin@adm01:~/src/k8s$ kubectl apply -f espaces/cnpg-system/00-namespace.yaml
   admin@adm01:~$ kubectl get crd | grep -E 'cnpg.io'
   admin@adm01:~$ kubectl -n cnpg-system get deploy
   NAME                  READY
   cnpg-cloudnative-pg   1/1
   plugin-barman-cloud   1/1
   admin@adm01:~$ kubectl -n cnpg-system get certificate      # barman-cloud-client, barman-cloud-server : READY True
   admin@adm01:~$ kubectl cnpg version                        # Build: {Version:1.30.1 …}
   ```
   L'option `--create-namespace` de la commande donnée est sans effet si l'espace existe déjà (créé depuis `espaces/`, avec ses étiquettes PSA). ⚠️ À vérifier sur ton lab : le nom exact du déploiement du plugin installé par le chart (`plugin-barman-cloud` avec ce nom de *release*) ; `kubectl -n cnpg-system get deploy` le donne.
3. **Réseau.** Une `NetworkPolicy` d'entrée (opérateur depuis `cnpg-system` sur 8000 et 5432, instances entre elles, API MédiAgenda et Job de migration sur 5432) et une `CiliumNetworkPolicy` de sortie (entité `kube-apiserver` sur 6443, instances entre elles). Le DNS est déjà autorisé par la politique du M15. Avec Cilium, l'API Kubernetes vue d'un pod est l'entité `kube-apiserver` (adresses des nœuds de contrôle, identité réservée) : une `NetworkPolicy` standard en `ipBlock` sur 10.10.40.51-53 ne la couvre pas. Le port 6443 est celui des kube-apiserver **après** traduction du Service `kubernetes` (10.96.0.1:443) : la politique s'applique au paquet traduit. ⚠️ À vérifier sur ton lab : si une instance ne démarre pas (`initdb` bloqué, journal « dial tcp 10.96.0.1:443: i/o timeout »), regarde `hubble observe --namespace mediagenda-recette --verdict DROPPED`.
4. **Le cluster.**
   ```
   admin@adm01:~/src/k8s$ kubectl apply -f espaces/mediagenda-recette/50-mediagenda-db.yaml
   admin@adm01:~$ kubectl -n mediagenda-recette get pods -l cnpg.io/cluster=mediagenda-db -w
   mediagenda-db-1-initdb-xxxxx   0/1   Completed
   mediagenda-db-1                1/1   Running
   mediagenda-db-2-join-xxxxx     0/1   Completed
   mediagenda-db-2                1/1   Running
   mediagenda-db-3 …
   admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette
   Cluster Summary
   Name:                mediagenda-recette/mediagenda-db
   PostgreSQL Image:    registry.par1.medisphere.internal/ghcr/cloudnative-pg/postgresql:18.6-minimal-trixie
   Primary instance:    mediagenda-db-1
   Status:              Cluster in healthy state
   Instances:           3
   Ready instances:     3
   …
   ```
   Refus possibles et leur cause : `violates PodSecurity "restricted"` (un champ ajouté à la main ; CNPG produit des pods conformes à `restricted`), `admission webhook … denied` / politique d'images du M14 (image hors de Harbor : opérateur ou PostgreSQL), `exceeded quota: quota-equipe` (ressources ou nombre de pods/Secrets), `0/6 nodes are available … didn't tolerate taint` (tolérance absente pour `k8s-w03`). Lis `kubectl -n mediagenda-recette describe cluster mediagenda-db` et les événements de l'espace.
5. **Exploration.**
   ```
   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -c 'SELECT pg_is_in_recovery();' -c "SELECT application_name, sync_state FROM pg_stat_replication;" -c 'SHOW synchronous_standby_names;'
    pg_is_in_recovery
   -------------------
    f
    application_name | sync_state
   ------------------+------------
    mediagenda-db-2  | quorum
    mediagenda-db-3  | quorum
    synchronous_standby_names
   --------------------------------------------
    ANY 1 ("mediagenda-db-2","mediagenda-db-3")
   admin@adm01:~$ kubectl -n mediagenda-recette get pdb
   mediagenda-db           …   ← répliques
   mediagenda-db-primary   …   ← le primaire ne s'évince pas sans bascule
   admin@adm01:~$ kubectl -n mediagenda-recette get endpointslices -l kubernetes.io/service-name=mediagenda-db-rw
   ```
   `sync_state = quorum` correspond à `ANY 1 (…)` : n'importe laquelle des deux répliques suffit.
6. **Bascule de l'application.** Patch du Deployment de l'API (extrait) : `MEDIAGENDA_DB_URL` depuis la clé `uri` de `mediagenda-db-app` (forme `postgresql://mediagenda:<MOT-DE-PASSE>@mediagenda-db-rw.mediagenda-recette:5432/mediagenda`). Ordre : Job de migration, puis redéploiement de l'API.
   ```
   admin@adm01:~/src/k8s$ kubectl apply -f espaces/mediagenda-recette/55-mediagenda-migration.yaml
   admin@adm01:~$ kubectl -n mediagenda-recette logs job/mediagenda-migration       # V1, V2 appliquées
   admin@adm01:~$ kubectl -n mediagenda-recette rollout status deploy/mediagenda-api
   admin@adm01:~$ curl -s https://mediagenda-recette.apps.par1.medisphere.internal/pret
   admin@adm01:~$ curl -s -X POST https://mediagenda-recette.apps.par1.medisphere.internal/api/v1/rendez-vous -H 'Content-Type: application/json' \
       -d '{"patient":"Patient Essai 1","praticien":"dr-morel","debut":"2026-11-02T09:00:00+01:00","duree_minutes":30,"motif":"Essai"}'
   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -d mediagenda -c 'SELECT count(*) FROM rendez_vous;'
   ```
   Le Secret `mediagenda-db-app` contient le mot de passe généré par CNPG : il n'est dans aucun dépôt. Le nom du Deployment (`mediagenda-api`) et l'étiquette des pods (`app.kubernetes.io/name: mediagenda-api`) sont ceux du M14 : adapte les fichiers si tu les as nommés autrement.
7. **Retrait du jetable** : MR qui supprime le Deployment (ou StatefulSet) et le Service du PostgreSQL du M14, et la politique réseau qui le concernait ; `kubectl -n mediagenda-recette get all,pvc | grep -i postgres` ne montre plus que `mediagenda-db-*`.
8. **Quotas** : `kubectl describe quota -n mediagenda-recette` : 3 pods, 300m/1,5 Gi de requêtes, 3/3 Gi de limites pour les instances, plus les Secrets générés (`-app`, `-replication`, `-ca`, `-server`…), 3 PVC de 5 Gio (15 Gio sur `ceph-rbd`) à reporter dans E20.

**Explications**
CNPG fait de PostgreSQL une ressource déclarative : on décrit le nombre d'instances, le stockage, les paramètres, la réplication ; l'opérateur crée les pods, les PVC, les Services, les Secrets, les PDB, et pilote PostgreSQL de l'intérieur (gestionnaire d'instance). Chaque instance a **son** volume RBD : la réplication est celle de PostgreSQL, pas celle du stockage ; Ceph, lui, réplique chaque volume trois fois en dessous. Trois instances × trois copies : neuf copies des données, choix à discuter dans l'ADR (E30).

**Alternatives**
- Une seule instance sur un volume répliqué par Ceph (moins de mémoire, bascule = redémarrage du pod sur un autre nœud, 1 à 2 minutes) : défendable pour du développement.
- Le chart `cnpg/cluster` pour déclarer le `Cluster` : une couche de plus, inutile ici.
- Le manifeste `cnpg-1.30.1.yaml` à la place du chart de l'opérateur.

**Pièges classiques**
- Image PostgreSQL par une étiquette flottante (`18`, `latest`) : une mise à jour non décidée au prochain redémarrage.
- Oublier que l'image de l'**opérateur** entre dans les pods de la base : la politique d'images refuse le pod pour un conteneur d'initialisation qu'on n'a pas écrit.
- `podAntiAffinityType: preferred` (défaut) : deux instances peuvent se retrouver sur le même nœud après une indisponibilité, et une panne de nœud emporte alors le primaire **et** une réplique.
- Connecter l'application à `mediagenda-db-r` ou `-ro` pour écrire.

**En production chez MédiSphère**
Mêmes principes en production (`mediagenda-prod`), avec des nœuds dédiés aux bases (*taint* `dedie=bdd`), des requêtes de ressources mesurées, `sslmode=verify-full`, PgBouncer (`Pooler` CNPG) devant la base, et la supervision des métriques de l'exporteur intégré (port 9187, M21).

---

### M16-E19 — CloudNativePG : sauvegarde continue et restauration à un instant donné

**Solution**

Fichiers : [`60-cnpg-s3.yaml`](fichiers/M16-E19/k8s/espaces/mediagenda-recette/60-cnpg-s3.yaml), [`50-mediagenda-db.yaml`](fichiers/M16-E19/k8s/espaces/mediagenda-recette/50-mediagenda-db.yaml) (avec `plugins`), [`70-mediagenda-db-sauvegarde.yaml`](fichiers/M16-E19/k8s/espaces/mediagenda-recette/70-mediagenda-db-sauvegarde.yaml), [`40-reseau-postgresql.yaml`](fichiers/M16-E19/k8s/espaces/mediagenda-recette/40-reseau-postgresql.yaml) (sortie S3), [`mediagenda-db-pitr.yaml`](fichiers/M16-E19/essais/mediagenda-db-pitr.yaml), [`reinjecter.sh`](fichiers/M16-E19/essais/reinjecter.sh) ; identité `cnpg` dans [`seaweedfs.yml.extrait`](fichiers/M16-E16/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait) ; sous-commande `cnpg` de [`secrets-sauvegarde.sh`](fichiers/M16-E16/k8s/outils/secrets-sauvegarde.sh).

1. **Lecture.**
   - Les WAL sont envoyés par le ***sidecar*** du plugin (conteneur `plugin-barman-cloud` injecté dans chaque pod d'instance), que PostgreSQL appelle par son `archive_command` (à travers le gestionnaire d'instance et l'interface CNPG-I) ; seul le primaire archive. Le *sidecar* lance `barman-cloud-wal-archive` vers S3.
   - Une sauvegarde de base est une copie physique du répertoire de données (`barman-cloud-backup`), prise **à chaud** entre `pg_backup_start` et `pg_backup_stop` : les pages copiées peuvent être incohérentes entre elles, ce sont les WAL de la période (archivés) qui rendent la copie cohérente à la restauration. Par défaut, elle est prise sur une réplique (`target: prefer-standby`).
   - Pour une restauration à un instant donné, CNPG choisit la dernière sauvegarde de base **terminée avant** la cible (`targetTime`), la restaure, puis rejoue les WAL archivés jusqu'à la cible.
   - Si l'archivage échoue, PostgreSQL **garde** les WAL non archivés dans `pg_wal` (il ne recycle jamais un WAL non archivé) : le volume du primaire se remplit, jusqu'à l'arrêt de la base quand il est plein. La condition `ContinuousArchiving` passe à `False` : c'est l'alerte à surveiller (E27, E41).
2. **S3 et secrets.** Identité `cnpg` et compartiment `cnpg-k8s-par1` (sans versionnage : Barman applique lui-même la rétention ; la documentation du plugin recommande, pour se protéger d'un effacement malveillant, versionnage + verrou d'objet + cycle de vie : à décider dans la politique de sauvegarde, E32). `outils/secrets-sauvegarde.sh cnpg mediagenda-recette` crée `cnpg-s3` et `medisphere-ca`. Ajout à la politique de sortie : `toCIDR: 10.10.20.14/32` port 8333.
3. **ObjectStore et archivage.**
   ```
   admin@adm01:~/src/k8s$ kubectl apply -f espaces/mediagenda-recette/40-reseau-postgresql.yaml -f espaces/mediagenda-recette/60-cnpg-s3.yaml
   admin@adm01:~/src/k8s$ kubectl apply -f espaces/mediagenda-recette/50-mediagenda-db.yaml   # ajoute spec.plugins : redémarrage une à une
   admin@adm01:~$ kubectl -n mediagenda-recette get pod mediagenda-db-1 -o jsonpath='{.spec.initContainers[*].name} | {.spec.containers[*].name}{"\n"}'
   bootstrap-controller plugin-barman-cloud | postgres
   admin@adm01:~$ kubectl -n mediagenda-recette get cluster mediagenda-db -o jsonpath='{.status.conditions[?(@.type=="ContinuousArchiving")].status}{"\n"}'
   True
   admin@adm01:~$ kubectl cnpg psql mediagenda-db -n mediagenda-recette -- -c 'SELECT pg_switch_wal();'
   admin@adm01:~$ (set -a; . ~/.config/workbook/s3-cnpg.env; set +a; aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls --recursive s3://cnpg-k8s-par1/mediagenda-db/wals/ | tail -3)
   ```
   Le *sidecar* est un conteneur d'initialisation à redémarrage permanent (`restartPolicy: Always`, conteneur *sidecar* natif de Kubernetes, GA en 1.33) : il apparaît dans `initContainers`. ⚠️ À vérifier sur ton lab : forme exacte de l'injection selon la version du plugin. Si `ContinuousArchiving` reste `False` : journal du conteneur `plugin-barman-cloud` du primaire (`kubectl -n mediagenda-recette logs mediagenda-db-1 -c plugin-barman-cloud`) — identifiants, CA, compartiment, flux.
4. **Sauvegardes.**
   ```
   admin@adm01:~$ kubectl cnpg backup mediagenda-db -n mediagenda-recette --method=plugin --plugin-name=barman-cloud.cloudnative-pg.io
   admin@adm01:~$ kubectl -n mediagenda-recette get backups.postgresql.cnpg.io -w      # « backup » seul est ambigu avec Velero
   NAME                        AGE   CLUSTER         METHOD   PHASE       ERROR
   mediagenda-db-20261104…     40s   mediagenda-db   plugin   completed
   admin@adm01:~/src/k8s$ kubectl apply -f espaces/mediagenda-recette/70-mediagenda-db-sauvegarde.yaml
   admin@adm01:~$ kubectl -n mediagenda-recette get scheduledbackup mediagenda-db-quotidienne -o jsonpath='{.status.nextScheduleTime}{"\n"}'
   admin@adm01:~$ kubectl -n mediagenda-recette get objectstore cnpg-s3 -o jsonpath='{.status.serverRecoveryWindow}{"\n"}'
   {"mediagenda-db":{"firstRecoverabilityPoint":"2026-11-04T13:05:12Z","lastSuccessfulBackupTime":"2026-11-04T13:05:40Z",…}}
   ```
   Cron CNPG : `0 15 1 * * *` = secondes 0, minute 15, heure 1, chaque jour (en UTC, l'heure du pod de l'opérateur). La bibliothèque utilisée par CNPG (`robfig/cron` v1) accepte aussi cinq champs **mais les lit comme « secondes minutes heures jour mois »** : `15 1 * * *` voudrait dire « à la seconde 15 de la minute 1 de **chaque heure** » (voir E21).
5. **Préparer l'incident** : dix créations par l'API, `date -Is` → `T=2026-11-04T14:32:10+01:00` (exemple), une minute d'attente, `DELETE FROM rendez_vous WHERE praticien = 'dr-morel';`, deux créations, `SELECT pg_switch_wal();` (pour que le WAL qui contient la suppression **et** l'instant T soit archivé : la restauration ne peut atteindre que ce qui est dans l'archive).
6. **Restaurer à T.** `sed "s/<T>/$T/" mediagenda-db-pitr.yaml | kubectl apply -f -` ; suivre `mediagenda-db-pitr-1-full-recovery-…` :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette logs -f job/mediagenda-db-pitr-1-full-recovery -c full-recovery | grep -E 'backup|recovery|restored log file|stopping'
   … "Target backup found" "backupId":"20261104T130512" …
   … LOG: restored log file "000000010000000000000006" from archive
   … LOG: recovery stopping before commit of transaction 812, time 2026-11-04 14:33:15+01
   … LOG: pausing at the end of recovery / redo done …
   admin@adm01:~$ kubectl cnpg status mediagenda-db-pitr -n mediagenda-recette
   ```
   Le nom exact du *job* (`-full-recovery`) et du conteneur sont à lire dans `kubectl -n mediagenda-recette get jobs`. La politique réseau couvre ces pods (étiquette `cnpg.io/cluster: mediagenda-db-pitr`). ⚠️ À vérifier sur ton lab : la limite de 30 Gio de `ceph-rbd` dans le quota d'E20 (si E20 est déjà fait) : 3 × 5 + 5 Gio = 20 Gio, ça passe.
7. **Vérifier.**
   ```
   admin@adm01:~$ for c in mediagenda-db mediagenda-db-pitr; do echo "== $c"; kubectl cnpg psql $c -n mediagenda-recette -- -d mediagenda -Atc \
       "SELECT praticien, count(*) FROM rendez_vous GROUP BY 1 ORDER BY 1;"; done
   ```
   Dans `mediagenda-db-pitr` : les rendez-vous de `dr-morel` sont présents, les deux créés après T absents. Temps total typique sur ce lab : 2 à 5 minutes (instance, restauration de la base de quelques Mio, rejeu de quelques WAL) — note le tien.
8. **Réparer sans tout restaurer** : `./reinjecter.sh dr-morel` copie les seules lignes de ce praticien de `mediagenda-db-pitr` vers `mediagenda-db` (`COPY … TO STDOUT` → `COPY … FROM STDIN` dans une table temporaire → `INSERT … OVERRIDING SYSTEM VALUE … ON CONFLICT (id) DO NOTHING`) : les identifiants d'origine sont conservés, rien de ce qui a été créé après T n'est écrasé. C'est presque toujours la bonne réponse à une erreur humaine : on ne remplace pas une base vivante par une restauration, on y **recopie** ce qui manque.
9. **Nettoyage.** `kubectl -n mediagenda-recette delete cluster mediagenda-db-pitr` (les PVC sont supprimés avec le cluster). Le cluster restauré n'avait pas de `.spec.plugins` : il n'archivait rien. Pour le garder comme nouveau primaire, il faudrait lui ajouter le plugin avec un **autre** `serverName` (paramètre `serverName: mediagenda-db-v2` dans `.spec.plugins[].parameters`) : CNPG refuse d'archiver dans un emplacement qui contient déjà l'archive d'un autre serveur (« Expected empty archive »), précisément pour ne pas mélanger deux historiques.
10. **Runbook** : [`RB-162-restaurer-postgresql-instant-donne.md`](fichiers/M16-E19/medisphere/docs/kubernetes/stockage/runbooks/RB-162-restaurer-postgresql-instant-donne.md). Il attend : l'instant **avec fuseau** et une marge avant ; la vérification de la fenêtre (`serverRecoveryWindow`, `ContinuousArchiving`, `pg_switch_wal()`) **avant** de créer quoi que ce soit ; un cluster d'enquête séparé sans archivage ; la vérification avec l'équipe ; deux sorties (réinjection sélective, la plus fréquente ; bascule vers la base restaurée avec un **nouveau** `serverName`) ; les gestes interdits (restaurer par-dessus la base vivante, archiver sous le nom de serveur d'origine) ; le RTO noté au ticket. E34 le joue en temps limité.

**Explications**
Sauvegarde continue = une copie de base régulière + **tous** les WAL entre deux copies. On peut ainsi restaurer à n'importe quelle seconde de la fenêtre de rétention (`retentionPolicy: 14d` : le plugin supprime les sauvegardes et WAL qui ne servent plus à aucune restauration dans les 14 derniers jours). Le plugin Barman Cloud sort cette fonction de l'opérateur (CNPG-I) : `ObjectStore` décrit le magasin, le `Cluster` déclare quel plugin archive et vers quel magasin ; l'ancien `spec.backup.barmanObjectStore` est déprécié en 1.30 et disparaît en 1.31.

**Alternatives**
- Sauvegardes de base par instantanés de volumes (`method: volumeSnapshot`, classe `ceph-rbd-snap`) plus WAL par le plugin : restauration plus rapide des grosses bases, mais la base reste dans Ceph tant qu'on ne la copie pas ailleurs.
- `pg_dump` logique périodique : utile pour l'archivage applicatif et les montées majeures, pas pour une restauration à la seconde.

**Pièges classiques**
- Renseigner `serverName` dans l'`ObjectStore` (le plugin exige qu'il reste vide), ou réutiliser le nom d'un cluster existant pour un nouveau cluster qui archive : mélange ou écrasement d'archives.
- Une heure de cible sans fuseau : lue en UTC, une ou deux heures d'écart.
- Oublier `pg_switch_wal()` (ou attendre `archive_timeout`, 5 minutes par défaut chez CNPG) : l'instant T n'est pas encore dans l'archive, la restauration s'arrête avant.
- `ScheduledBackup` sans `method: plugin` : CNPG tente la méthode intégrée, qui échoue faute de `barmanObjectStore`.
- Supprimer `mediagenda-db-pitr` **avant** de vérifier : refaire toute la restauration.

**En production chez MédiSphère**
RPO de quelques minutes (archivage continu, `archive_timeout`), RTO mesuré à chaque essai mensuel (restauration dans `wb-restauration`, E24 et E34), compartiment protégé contre l'effacement (verrou d'objet ou copie vers PAR2, E32), alerte sur `ContinuousArchiving=False` et sur l'âge de la dernière sauvegarde (M21), et RB-162 (écrit à l'étape 10) pour la restauration à un instant donné.

---

### M16-E20 — Quotas de stockage et classes par équipe

**Solution**

Fichiers : [`mediagenda-dev/30-quota-stockage.yaml`](fichiers/M16-E20/k8s/espaces/mediagenda-dev/30-quota-stockage.yaml), [`mediagenda-recette/30-quota-stockage.yaml`](fichiers/M16-E20/k8s/espaces/mediagenda-recette/30-quota-stockage.yaml), [`admission/classes-stockage.yaml`](fichiers/M16-E20/k8s/admission/classes-stockage.yaml), [`annotations.extrait.yaml`](fichiers/M16-E20/k8s/espaces/annotations.extrait.yaml), [`refus.sh`](fichiers/M16-E20/essais/refus.sh).

1. **Lecture.** Un quota de stockage compte la **taille demandée** (`spec.resources.requests.storage`) de chaque PVC de l'espace, quel que soit son état (`Pending`, `Bound`, et même un PVC dont le volume est vide) : pas l'occupation réelle. Un agrandissement est recompté : la nouvelle demande doit tenir dans le quota (sinon le `patch` est refusé). Les PVC en cours de suppression ne libèrent le quota qu'une fois supprimés.
2. **Consommation de `mediagenda-recette`** avant les quotas : 3 PVC `mediagenda-db-N` de 5 Gio (`ceph-rbd`) + `donnees-valkey-0` (E08, 1 Gio d'après le palier 1 : vérifie) = 16 Gio sur 30 ; une restauration PITR (E19) ajoute 5 Gio. Si le quota était trop bas, CNPG ne pourrait plus **recréer** une instance perdue (PVC refusé : le cluster reste à deux instances) ni agrandir le stockage (`spec.storage.size`) : c'est pourquoi on garde une marge d'au moins une instance et d'une restauration.
3. **Quotas et LimitRanges** : un `ResourceQuota` séparé `quota-stockage` (deux quotas s'appliquent ensemble, chacun sur ses ressources) et une `LimitRange` `limites-pvc` de type `PersistentVolumeClaim`.
   ```
   admin@adm01:~$ kubectl describe quota quota-stockage -n mediagenda-dev
   Resource                                                       Used  Hard
   --------                                                       ----  ----
   ceph-rbd-retain.storageclass.storage.k8s.io/persistentvolumeclaims  0     0
   ceph-rbd-retain.storageclass.storage.k8s.io/requests.storage   0     0
   ceph-rbd.storageclass.storage.k8s.io/requests.storage          …     10Gi
   cephfs.storageclass.storage.k8s.io/requests.storage            0     2Gi
   count/volumesnapshots.snapshot.storage.k8s.io                  0     5
   persistentvolumeclaims                                         …     10
   requests.storage                                               …     10Gi
   ```
4. **VAP.** Trois variables CEL (annotation lue dans `namespaceObject`, liste nettoyée, classe du PVC), deux validations (une annotation doit exister ; la classe doit y figurer), messages construits par `messageExpression`. Liaison sur les espaces qui portent `medisphere.internal/equipe`, d'abord en `[Warn, Audit]` (les créations passent, avec un avertissement côté client et une annotation dans le journal d'audit du M14-E27), puis `[Deny]`. Les chaînes CEL sont entre guillemets doubles : les apostrophes du français y sont permises.
5. **Essais** (les cinq premiers messages ont été obtenus sur un `kube-apiserver` 1.36 de test avec les fichiers du corrigé ; les trois derniers donnent la forme attendue, non rejouée) :

   | Essai | Qui refuse | Message |
   |---|---|---|
   | PVC de 20 Gio | LimitRange `limites-pvc` | `maximum storage usage per PersistentVolumeClaim is 5Gi, but request is 20Gi` |
   | PVC `ceph-rbd-retain` | VAP (avant le quota) | `ValidatingAdmissionPolicy 'classes-stockage' with binding 'classes-stockage' denied request: classe de stockage « ceph-rbd-retain » refusée dans mediagenda-dev ; classes autorisées : ceph-rbd, cephfs` |
   | PVC sans classe | personne : `DefaultStorageClass` l'a rempli avec `ceph-rbd` avant la VAP | créé |
   | PVC `storageClassName: ""` | VAP | `… classe de stockage « (vide) » refusée dans mediagenda-dev …` |
   | Espace sans annotation | VAP | `… l'espace mediagenda-dev n'a pas d'annotation medisphere.internal/classes-stockage : aucune classe de stockage autorisée (demande à l'équipe Plateforme)` |
   | 11ᵉ PVC | quota | `exceeded quota: quota-stockage, requested: persistentvolumeclaims=1, used: persistentvolumeclaims=10, limited: persistentvolumeclaims=10` |
   | 6ᵉ instantané | quota | `exceeded quota: quota-stockage, requested: count/volumesnapshots.snapshot.storage.k8s.io=1, …` |
   | Annotation de l'espace | RBAC | `namespaces "mediagenda-dev" is forbidden: User "julien.petit" cannot patch resource "namespaces" …` |

   Les quatre premiers se testent en `--dry-run=server` (`refus.sh`) : admission, `LimitRange` et quotas sont évalués sans rien créer. Pour le onzième PVC et le sixième instantané, il faut créer réellement les objets précédents (le quota compte ce qui existe), puis les supprimer. Quand plusieurs garde-fous s'appliquent, l'ordre est : mutation (classe par défaut) → validations intégrées (`LimitRange`, `ResourceQuota`) et politiques (VAP) ; le premier refus arrête la requête. ⚠️ À vérifier sur ton lab : l'ordre exact entre `ResourceQuota` et VAP (le quota est évalué en dernier, après les autres validations, pour ne pas consommer de quota sur une requête refusée).
6. **CNPG** : `kubectl cnpg destroy mediagenda-db 3 -n mediagenda-recette` supprime l'instance 3 et son PVC ; l'opérateur recrée `mediagenda-db-4` (nouveau PVC de 5 Gio, accepté par la VAP et le quota) par clonage depuis le primaire. ⚠️ `destroy` supprime le PVC de l'instance : ne le fais jamais sur le primaire, et vérifie `kubectl cnpg status` avant.
7. **Documentation** : `docs/kubernetes/stockage/quotas.md` (tableau des plafonds, règle « marge d'une instance et d'une restauration », procédure de demande : ticket `PLAT-`, MR sur `espaces/<espace>/30-quota-stockage.yaml` relue par Claire, vérification de la capacité du pool `k8s-rbd` côté Ceph, `ceph df`).

**Explications**
Trois mécanismes, trois questions : la `LimitRange` borne **un** objet, le quota borne la **somme** d'un espace, la VAP dit **ce qui est permis** (quelle classe). Le quota par classe (`<classe>.storageclass.storage.k8s.io/…`) est la façon native d'interdire une classe (plafond 0), mais son message (« exceeded quota ») n'explique rien à l'équipe ; la VAP donne un message clair et couvre le cas de la chaîne vide. Mettre la liste dans une **annotation d'espace** plutôt que dans une ConfigMap de paramètres empêche l'équipe de s'ouvrir elle-même une classe : elle ne peut pas modifier l'objet `Namespace`.

**Alternatives**
- `paramKind` (ConfigMap ou CRD de paramètres) avec un `paramRef` dans un espace de la plateforme : plus riche (une liste par équipe dans un seul objet), mais un objet de plus à gérer.
- Kyverno (M26) : même règle en YAML, avec rapports de conformité.
- Ne rien interdire et compter sur les quotas : `ceph-rbd-retain` resterait possible jusqu'au premier refus de quota, avec un message obscur.

**Pièges classiques**
- Un seul `ResourceQuota` avec tout dedans, modifié par plusieurs MR : conflits ; deux objets séparés (équipe, stockage) sont plus lisibles.
- Oublier `count/volumesnapshots…` : les instantanés n'occupent pas de quota de stockage mais occupent Ceph.
- Une VAP sans `failurePolicy: Fail` explicite : défaut `Fail`, mais l'écrire évite le doute ; avec `Ignore`, une erreur d'expression laisse tout passer.
- Une erreur de syntaxe CEL (apostrophe dans une chaîne entre apostrophes) : la politique est créée, mais son statut (`status.typeChecking`) signale l'erreur et la validation échoue à l'exécution ; lis `kubectl get vap classes-stockage -o yaml`.

**En production chez MédiSphère**
Chaque nouvel espace d'équipe naît avec son quota de stockage et son annotation (gabarit d'espace du M14-E33) ; la somme des quotas est comparée à la capacité du pool `k8s-rbd` (on accepte une sursouscription mesurée) ; les refus de la VAP en mode `Audit` sont relus avant tout durcissement.

---

### M16-E21 — Revue : les manifestes *stateful* du stagiaire

**Réponses à l'étape 1.** Deux pods `postgres-0` et `postgres-1` partagent **un** PVC RWO (`pg-donnees`) : au mieux le second reste bloqué (`Multi-Attach error` s'il est sur un autre nœud), au pire les deux démarrent sur le même nœud et deux `postgres` écrivent dans le même répertoire de données (corruption) ; une troisième « copie » existe en CNPG (`medidoc-db`, deux instances). Les sauvegardes CNPG partent dans `s3://cnpg-k8s-par1/` (le compartiment de **MédiAgenda**), en HTTP vers un point d'accès qui n'écoute qu'en HTTPS, avec l'`ObjectStore` qui force `serverName: mediagenda-db` : s'il était utilisé, MédiDoc écrirait ses WAL **dans l'archive de MédiAgenda**. Supprimer le StatefulSet ne supprime pas `pg-donnees` (PVC hors gabarit), mais la politique de rétention `Delete` montre l'intention : avec des `volumeClaimTemplates`, les données partiraient avec lui. Les volumes de « rapide » sont montés avec **`client.admin`** (Secret `ceph-admin`).

**Revue** (18 défauts ; les gravités sont celles d'une application sur `k8s-par1`) :

| N° | Fichier | Défaut | Catégorie | Gravité | Impact chez nous | Correction |
|---|---|---|---|---|---|---|
| 1 | `10-secrets.yaml` | Clé `client.admin` et clés S3 en clair dans le dépôt (« dépôt privé ») | sécurité | **critique** | Quiconque lit le dépôt (ou son historique, ses copies, la CI) administre `ceph-par1` en entier et lit les archives S3 | Supprimer le fichier **et** révoquer les clés (rotation `client.admin`, nouvelle identité S3) : un secret poussé est compromis. Secrets créés par script depuis le Vault (`outils/secrets-sauvegarde.sh cnpg medidoc-dev`) |
| 2 | `00-storageclass.yaml` | Secrets du pilote = `ceph-admin` (identité `client.admin`) | sécurité | **critique** | Le pilote, et tout nœud qui monte un volume, détient la clé d'administration du cluster Ceph | Classe supprimée : utiliser `ceph-rbd` (identité `client.k8s` limitée au pool) |
| 3 | `50-objectstore.yaml` | `serverName: mediagenda-db` dans l'`ObjectStore` | données | **critique** | WAL et sauvegardes de MédiDoc écrits dans l'archive de MédiAgenda : la restauration de MédiAgenda devient impossible ou fausse | `serverName` toujours vide dans l'`ObjectStore` (documentation du plugin) ; compartiment dédié |
| 4 | `30-postgres-maison.yaml` | Deux réplicas, un seul PVC RWO partagé (pas de `volumeClaimTemplates`), aucune réplication | données | **critique** | `Multi-Attach` ou deux PostgreSQL sur les mêmes fichiers : corruption ; « HA » illusoire | Supprimer ce fichier (CNPG suffit) ; sinon `replicas: 1` et `volumeClaimTemplates` |
| 5 | `00-storageclass.yaml` | Annotation « par défaut » sur `rapide` | exploitation | élevée | Deux classes par défaut : la plus récente (`rapide`) prend **tous** les PVC sans classe du cluster, de toutes les équipes, avec `client.admin` et `Retain` | Pas de classe ; ou annotation retirée |
| 6 | `00-storageclass.yaml` | `journaling` dans `imageFeatures` | exploitation | élevée | krbd 6.12 ne gère pas `journaling` : images créées, **montage refusé** (pod en `ContainerCreating`) | Fonctions de `ceph-rbd` (`layering,exclusive-lock,object-map,fast-diff,deep-flatten`) |
| 7 | `40-cnpg-cluster.yaml` | `spec.backup.barmanObjectStore` (archivage intégré) | exploitation | élevée | Déprécié en CNPG 1.30, **retiré en 1.31** : la montée de version de l'opérateur casse la sauvegarde ; sans `endpointCA`, TLS refusé de toute façon | Plugin Barman Cloud : `spec.plugins` + `ObjectStore` |
| 8 | `40` / `50` | Compartiment et identité S3 de MédiAgenda réutilisés | sécurité | élevée | MédiDoc peut lire et **effacer** les sauvegardes de MédiAgenda (et inversement) | Compartiment `cnpg-medidoc-dev` et identité dédiée (MR sur le rôle `seaweedfs`) |
| 9 | `50-objectstore.yaml` | `endpointURL` en `http://`, sans `endpointCA` | sécurité | élevée | `s3-01` n'écoute qu'en HTTPS : archivage en échec, WAL qui s'accumulent jusqu'à remplir le volume ; en clair si un jour ça répondait | `https://…:8333` et `endpointCA` (Secret `medisphere-ca`) |
| 10 | `60-scheduledbackup.yaml` | `"0 2 * * *"` : cinq champs ; CNPG attend six champs (secondes en tête) et sa bibliothèque (`robfig/cron` v1) lit ces cinq champs comme `seconde=0 minute=2 heure=* …` | exploitation | élevée | Une sauvegarde de base **chaque heure** à hh:02:00 (vingt-quatre par jour), pas une par nuit | `"0 0 2 * * *"` |
| 11 | `60-scheduledbackup.yaml` | Pas de `method: plugin` | exploitation | élevée | Méthode intégrée par défaut : la sauvegarde échoue (plus de `barmanObjectStore`) | `method: plugin`, `pluginConfiguration.name: barman-cloud.cloudnative-pg.io` |
| 12 | `70-velero-schedule.yaml` | `includedNamespaces: ["*"]` dans un fichier d'équipe | sécurité | élevée | Sauvegarde de **tout** le cluster (Secrets de toutes les équipes) sous la responsabilité de MédiDoc ; doublon des planifications de la plateforme | `medidoc-dev` seulement ; fichier de la plateforme (`composants/velero/planifications.yaml`) |
| 13 | `70-velero-schedule.yaml` | `defaultVolumesToFsBackup: true` (copie de fichiers de PostgreSQL à chaud) ; `snapshotMoveData: false` | données | élevée | Copie incohérente de la base présentée comme une sauvegarde ; et sans déplacement, rien ne quitte Ceph | Base sauvegardée par CNPG, PVC des instances exclus ; autres volumes : `snapshotMoveData: true` |
| 14 | `20-pvc-partage.yaml` | `ReadWriteMany` sans classe (donc RBD), 50 Gio | exploitation | moyenne | `ProvisioningFailed` (RWX impossible sur RBD en mode fichier) ; 50 Gio hors des bornes d'un espace de dev | `storageClassName: cephfs`, taille raisonnable (5 Gio) |
| 15 | `30-postgres-maison.yaml` | `hostPath` `/srv/medidoc-sauvegardes`, `postgres:latest` de Docker Hub, mot de passe en clair dans `env`, pas de `securityContext` ni de ressources, `whenDeleted: Delete` | sécurité / exploitation | moyenne | Refusé par PSA `restricted` (`hostPath`, non-root) et par la politique d'images (registre, `:latest`) ; sauvegardes sur le disque d'un nœud ; mot de passe lisible par tous ceux qui lisent le StatefulSet | Fichier supprimé (défaut 4) |
| 16 | `40-cnpg-cluster.yaml` | `enablePodAntiAffinity: false`, image `ghcr.io/…:18` (hors Harbor, étiquette flottante), 1 Gio sur `rapide`, pas de ressources | exploitation | moyenne | Les deux instances peuvent être sur le même nœud ; pod refusé par la politique d'images ; volume vite plein ; montée de version subie | Anti-affinité, image Harbor `18.6-minimal-trixie`, `ceph-rbd` 5 Gio, ressources |
| 17 | `00-storageclass.yaml` | `reclaimPolicy: Retain`, `allowVolumeExpansion: false`, classe « rapide » sur le même pool que `ceph-rbd` | exploitation | faible | Images orphelines à chaque suppression de PVC ; pas d'agrandissement ; nom trompeur (même pool, mêmes disques) | Pas de classe dédiée |
| 18 | `70-velero-schedule.yaml` | Pas de `CRON_TZ`, TTL d'un an (`8760h`) | exploitation | faible | Heure en UTC ; sauvegardes (avec données de santé) gardées un an sans décision de rétention | `CRON_TZ=Europe/Paris`, TTL de la politique de sauvegarde (E32) |

**Ordre de traitement.** D'abord le **défaut 1** (et 2) : un secret poussé est compromis dès maintenant, quel que soit le sort de la MR ; il faut révoquer `client.admin` et les clés S3 aujourd'hui, purger l'historique ne suffit pas. Puis 3 (risque immédiat sur les sauvegardes d'une **autre** équipe), puis 4, 5, 6 (pertes de données ou blocage de tout le cluster dès l'application), puis le reste.

**Fichiers corrigés** : [`corrige/`](fichiers/M16-E21/corrige/) (`20-pvc-partage.yaml`, `40-cnpg-cluster.yaml`, `50-objectstore.yaml`, `60-scheduledbackup.yaml`, `70-velero-schedule.yaml`) ; **supprimés** : `00-storageclass.yaml` (utiliser `ceph-rbd`), `10-secrets.yaml` (script et Vault), `30-postgres-maison.yaml` (CNPG). Le check accepte aussi des versions corrigées de `00` et `30` si tu préfères les garder, à condition qu'elles respectent ses règles.

**Question de fond.** Non : une « base maison en attendant » coûte plus cher que CNPG, qui existe déjà sur le cluster (E18) et se déclare en vingt lignes. Le StatefulSet maison n'a ni réplication, ni bascule, ni sauvegarde, ni montée de version encadrée, et ses défauts (volume partagé, `hostPath`, mot de passe en clair) se retrouveraient en recette « parce que ça marche en dev ». Pour un environnement de développement : un `Cluster` CNPG d'**une** ou deux instances, sans réplication synchrone, petite rétention, mêmes fichiers qu'en recette à quelques valeurs près (Kustomize, M17). À garder du StatefulSet de Lucas : l'idée d'un volume par instance (qu'il faut écrire avec `volumeClaimTemplates`) et le réflexe de vouloir des sauvegardes — à condition qu'elles quittent le nœud et le cluster.

**Conseils à Lucas sur sa façon de tester** : kind n'a ni Ceph, ni PSA `restricted`, ni nos politiques d'admission, ni `s3-01` : « vert sur kind » ne prouve que la syntaxe. Teste dans `wb-essais` sur `k8s-par1`, lis les **événements** autant que les statuts, et pour une sauvegarde, prouve une restauration.

**Explications**
La revue d'objets de données se fait en suivant les données : où elles sont écrites (volume, nœud, pool), par qui (identité), où partent les copies (compartiment, chemin, serveur), combien de temps, et ce qui se passe à la suppression. Les défauts les plus graves ne sont pas des erreurs de syntaxe : ce sont des **collisions** (un compartiment, un nom de serveur, une classe par défaut partagés) et des **secrets**.

**Pièges classiques**
- Corriger le fichier de secrets en le « chiffrant » sans révoquer : l'historique Git a déjà la valeur en clair.
- Corriger la planification CNPG en ajoutant un sixième champ **à la fin** (`0 2 * * * *`) : seconde 0, minute 2, chaque heure, encore.

**En production chez MédiSphère**
Les règles du check d'E21 deviennent des contrôles de CI des dépôts d'équipe (kubeconform + règles `yq`, puis Kyverno au M26) ; les identités S3 et Ceph sont toujours par équipe et par usage.

---

### M16-E22 — Runbook : un PVC reste Pending

**Solution**

Fichier : [`RB-160-pvc-pending.md`](fichiers/M16-E22/medisphere/docs/kubernetes/stockage/runbooks/RB-160-pvc-pending.md).

Points que le corrigé attend :
- le **tableau d'entrée** par message, parce que l'astreinte arrive avec un message, pas avec une hypothèse ;
- la distinction entre « le PVC existe et attend » (événements du PVC) et « le PVC n'a jamais été créé » (erreur chez le demandeur : `kubectl`, contrôleur du StatefulSet, opérateur CNPG, Velero), avec **où** lire l'erreur dans chaque cas ;
- `WaitForFirstConsumer` traité comme un état **normal** ;
- la frontière des responsabilités : manifeste → développeur ; quotas et classes → demande à la plateforme ; pilote, Secrets, classe par défaut → plateforme ; Ceph → équipe Ceph ;
- les gestes interdits (PV `hostPath` « pour débloquer », *finalizers*, classe par défaut, `client.admin`) et un retour arrière (ne supprimer qu'un PVC jamais lié) ;
- le jeu sur trois cas réels. Ce qui manque souvent au premier jet : le cas des PVC créés par un **contrôleur** (l'erreur n'est pas sur le PVC), le cas de la chaîne vide, et la commande qui montre si un PVC a déjà été lié (`spec.volumeName`).

**Explications**
Un runbook de niveau 1 n'explique pas le stockage : il dit, pour chaque symptôme, quoi regarder, quoi faire, quoi ne pas faire, et quand passer la main. Son ordre est celui du coût du diagnostic : lire le PVC et ses événements (gratuit) avant les journaux du pilote, avant Ceph.

**Pièges classiques**
- Un runbook qui commence par « vérifier Ceph » : la cause est presque toujours dans le manifeste ou le quota.
- Des commandes sans résultat attendu : à 3 h du matin, on ne sait pas si ce qu'on voit est normal.
- Oublier les droits du public visé : l'astreinte n'a pas accès à `ceph01` ni aux Secrets.

**En production chez MédiSphère**
RB-160 est lié depuis l'alerte « PVC Pending depuis plus de 10 minutes » (M21) et rejoué à chaque changement de classe ou de pilote (E33) ; les pannes d'E35 servent d'exercice pour l'astreinte.

---

### M16-E23 — Le stockage du cluster décrit par le code

**Solution**

Fichiers : [`Taskfile.yml.extrait`](fichiers/M16-E23/k8s/Taskfile.yml.extrait), [`outils/derive-stockage.sh`](fichiers/M16-E23/k8s/outils/derive-stockage.sh), [`outils/schemas-crd.sh`](fichiers/M16-E23/k8s/outils/schemas-crd.sh), [`gitlab-ci-stockage.yml.extrait`](fichiers/M16-E23/k8s/ci/gitlab-ci-stockage.yml.extrait), [`docs/stockage.md`](fichiers/M16-E23/k8s/docs/stockage.md) ; plus les fichiers des exercices précédents (palier 1 et E10-E20), qui constituent l'état final.

Démarche :
1. **Inventaire de l'existant** : `helm list -A` (releases et versions de chart), `kubectl get sc,volumesnapshotclass,vap,vapb`, `kubectl get quota,limitrange -A`, `kubectl -n velero get schedules,bsl`, `kubectl -n mediagenda-recette get cluster,objectstore,scheduledbackup`, et pour chaque release `helm get values <release> -n <espace> -o yaml` comparé au fichier du dépôt (c'est ce que fait `derive-stockage.sh`). Tout ce qui existe dans le cluster et pas dans le dépôt (un `helm upgrade --set` d'un soir, une classe créée à la main) est soit ajouté au dépôt, soit supprimé du cluster. Rook et Longhorn ne doivent plus apparaître nulle part.
2. **Versions** : chaque version de chart est écrite dans le dépôt (variables du `Taskfile`, valeur par défaut de `installer.sh` pour ceph-csi) ; une version passée en variable d'environnement a une valeur par défaut versionnée.
3. **Ordre** : `task stockage:appliquer` enchaîne instantanés → Secrets → ceph-csi (StorageClasses et classes d'instantanés) → Velero → CNPG → garde-fous → base. Rejouée : `helm upgrade` d'une release inchangée crée une révision sans modification des objets ; `kubectl apply` répond `unchanged` ; la preuve est `task stockage:derive` en sortie 0, consignée dans le journal.
4. **Secrets** : `stockage:secrets` appelle `outils/ceph-csi-secrets.sh appliquer` (Vault `critique`) et `outils/secrets-sauvegarde.sh` (fichiers 600 de `~/.config/workbook/`) ; `velero-kopia` n'est pas rejoué automatiquement (mot de passe à ne jamais changer). Chaque script a son mode de vérification qui dit ce qui manque.
5. **CI** : `yamllint` ; recherche de motifs de clés (en plus de Gitleaks du gabarit `qualite.yml`) ; rendu des charts aux versions du dépôt avec les valeurs du dépôt ; `kubeconform -strict` sur les rendus **et** les manifestes, avec les schémas des CRD produits par `outils/schemas-crd.sh` (snapshots, Velero, CNPG, Barman Cloud, `CiliumNetworkPolicy`) ; ShellCheck. MR de démonstration réaliste : une `ScheduledBackup` sans `pluginConfiguration` passe le schéma mais une règle maison (`yq`) peut l'attraper ; plus simplement, un champ mal orthographié (`retentionPolice`) ou un type faux (`instances: "trois"`) dans un `Cluster` : `kubeconform -strict` le rejette.
6. **Documentation** : `docs/stockage.md` (périmètre, ordre, secrets, ce qui n'est pas dans le dépôt).

**Explications**
« Décrit par le code » veut dire trois choses vérifiables : le dépôt suffit pour reconstruire (avec les secrets, qui ont leur propre source), le cluster ne contient rien d'autre (détection de dérive), et une erreur est attrapée **avant** le cluster (CI). Les données, elles, ne sont pas dans le dépôt : elles sont dans les sauvegardes, que le dépôt sait produire et restaurer.

**Alternatives**
- Helmfile (M17) remplacera les tâches Helm du `Taskfile` (reprise des releases existantes sans réinstallation) ; Argo CD (M20) remplacera l'application depuis `adm01` et la détection de dérive.
- `helm diff` (plugin) pour montrer le changement avant chaque `helm upgrade`.

**Pièges classiques**
- Laisser les versions de chart dans la tête de quelqu'un (`helm upgrade` sans `--version`) : la reconstruction installe autre chose.
- Une CI qui valide les manifestes sans les schémas des CRD : `kubeconform` ignore (ou refuse, avec `-strict`) les objets inconnus et ne vérifie rien d'utile.
- Versionner les valeurs **rendues** d'une release (`helm get values -a`) : elles contiennent les valeurs par défaut du chart et, pour certains charts, des secrets.

**En production chez MédiSphère**
Le même découpage par domaine (réseau au M15, stockage ici) donne un dépôt de plateforme reconstructible ; la détection de dérive tourne chaque nuit et alerte ; chaque MR du stockage passe la CI et une relecture de Karim.
