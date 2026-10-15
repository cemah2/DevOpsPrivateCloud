# Module 16 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice : `k8s/` reproduit l'arborescence de `plateforme/k8s`, `infra/` celle de `plateforme/infra`, `ansible/` celle de `plateforme/ansible`, `ceph/` celle de `plateforme/ceph`, `medisphere/` celle de la documentation, `mediagenda-api/` celle du projet `mediagenda/api` (manifestes `k8s/recette/` de MédiAgenda), `essais/` les manifestes jetables de `wb-essais`. On **superpose** les dossiers dans l'ordre des exercices ; les `*.extrait` sont des morceaux à intégrer dans un fichier existant (l'emplacement est dit en tête), les `*.exemple` des modèles sans valeur réelle. `<FSID>` est à remplacer partout par la sortie de `ceph fsid`.

**Ce qui a été vérifié hors cluster** (documentation et outils, sans `k8s-par1` réel) :
- les charts `ceph-csi-rbd` et `ceph-csi-cephfs` **3.18.1** (téléchargés du dépôt `https://ceph.github.io/csi-charts`) : lecture de `values.yaml` et des gabarits ; `helm template` (Helm 4.3) avec les values du corrigé : configuration des moniteurs, `ceph.conf`, placement, réplicas conformes ; **aucun objet de même nom** entre les deux releases une fois les trois ConfigMaps de CephFS renommées (elles entrent en collision sans cela) ; noms produits : `ceph-csi-rbd-nodeplugin`, `ceph-csi-rbd-provisioner`, `ceph-csi-cephfs-…`, étiquettes de pods `app=ceph-csi-<pilote>,component=nodeplugin|provisioner` ;
- la documentation de ceph-csi **au tag v3.18.1** : `docs/capabilities.md` (droits RBD et CephFS, création avec `--key-type=aes`), `docs/rbd/deploy.md` et `docs/cephfs/deploy.md` (paramètres des classes, `mapOptions`, `kernelMountOptions`, `mounter`), `deploy/csi-config-map-sample.yaml` (`csiConfig`, `cephFS.subvolumeGroup` qui doit exister) ;
- la page `rbd(8)` de Ceph 20.2 : options `ms_mode=legacy|crc|secure|prefer-crc|prefer-secure` du mappage noyau (Linux ≥ 5.11), `abort_on_full` ;
- external-snapshotter **v8.6.0** : `kubectl kustomize` des sources amont à l'étiquette (6 CRD, contrôleur dans `kube-system`, 2 réplicas) ; le manifeste du contrôleur cite encore l'image `v8.5.0`, d'où la surcharge ; l'image `registry.k8s.io/sig-storage/snapshot-controller:v8.6.0` existe ; les CRD de groupes de snapshots servent `v1beta1`, `v1beta2` **et** `v1` (stockage en `v1beta2`) ;
- tous les manifestes (essais, classes, espace, rendus Helm) passent `kubeconform -strict` avec les schémas de Kubernetes 1.36 ;
- le rôle `k8s_reseau_stockage` et son playbook passent `ansible-lint` 26.9 (profil `production`, ansible-core 2.21, `community.general` 13) ; les expressions de calcul (adresse, MAC, présence de la carte, carte configurée) ont été évaluées sur des faits simulés ;
- l'image `valkey/valkey:8.1` (celle du M14 ; la 9.1 existe, la montée de version n'est pas l'objet de ce module) : utilisateur et groupe 999, `WORKDIR /data`, point d'entrée qui ne change les droits que s'il démarre en root ;
- scripts (`installer.sh`, `ceph-csi-secrets.sh`) et vérifications : ShellCheck 0.11 (`-x`) et `bash -n` ; les vérifications ont été exécutées sur des réponses simulées de l'API (cas conforme et cas fautifs) pour s'assurer qu'elles vont au bout et passent au rouge quand il le faut.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- l'ensemble sur un vrai `k8s-par1` raccordé à `ceph-par1` : les sorties montrées sont **représentatives**, pas copiées ;
- le changement d'identifiant d'instance cloud-init quand Proxmox ajoute un `ipconfig1` (E05, d'après le fonctionnement du lecteur NoCloud de Proxmox), et le redémarrage éventuel de la VM par le fournisseur `bpg/proxmox` pendant l'`apply` ;
- le masquage par Cilium du trafic des pods du *provisioner* vers le VLAN 30 (E05, étape 7) : il dépend du mode de masquage retenu au M15 (iptables ou BPF) et de la détection de `eth1` par l'agent ;
- le format `krbd:ms_mode=secure` de `mapOptions` (documenté), et le comportement du noyau 6.12 avec des moniteurs listés en `:3300` ;
- les messages exacts : refus RWOP, refus RWX de RBD, éviction d'un `emptyDir`, `EDQUOT` de CephFS, lignes `GRPC call` des journaux du pilote ;
- l'annotation `meta.helm.sh/release-name` posée par Helm 4 sur les objets d'une release (vérification E07) ;
- la recherche de code de l'API GitLab (`scope=blobs`) utilisée par la vérification E05.
- les versions du noyau citées pour les fonctionnalités krbd (`object-map`, `fast-diff` depuis Linux 5.3) : la vérification qui compte est le mappage réel sans `feature set mismatch` sur le 6.12 des travailleurs (E06, étape 9) ;
- le droit restreint `mgr 'allow rw module=volumes'` pour `client.k8s-cephfs` (E07), cité comme piste.
- l'adoption par le StatefulSet `valkey` recréé (E08, étape 8) des pods orphelins du M14 : retrait de `valkey-2` et `valkey-1`, puis remplacement de `valkey-0` par un pod qui monte son PVC (comportement documenté du contrôleur, ordre observé à confirmer).

---

### M16-E01 — Test de positionnement : stockage dans Kubernetes

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, relis les « Concepts clés » de l'introduction et la page *Volumes* de Kubernetes avant E03 ; les questions 6 à 12 sont reprises en E02-E08, les questions 13 à 17 aux paliers 2 et 3 (Velero, CloudNativePG).

**Réponses argumentées — montages et systèmes de fichiers**

**1. Montage lié.** Rendre visible un répertoire (ou un fichier) existant à un second endroit de l'arborescence : `mount --bind /srv/donnees /mnt/vue` ; les deux chemins désignent les mêmes inodes, rien n'est copié. Usages hors conteneurs : exposer un sous-répertoire dans un *chroot*, remonter un répertoire en lecture seule (`mount -o remount,bind,ro`), masquer un répertoire en montant autre chose par-dessus. C'est exactement ce que fait le kubelet (par le pilote CSI) pour donner un volume à un pod : un montage lié du point de montage global vers le répertoire du pod (E04, E44).

**2. Propagation.** `private` : les montages faits d'un côté ne sont pas vus de l'autre. `shared` : les montages et démontages se propagent dans les deux sens entre les espaces de noms du même groupe de pairs. `slave` : on reçoit ce qui est monté chez le maître, sans renvoyer ses propres montages. Un pilote CSI de nœud tourne dans un conteneur mais monte des volumes **pour d'autres conteneurs** : ses montages doivent remonter vers l'hôte (où le kubelet et les autres pods les voient), d'où `mountPropagation: Bidirectional` (partage dans les deux sens) sur les répertoires du kubelet, qui exige un conteneur privilégié. Sans cela, le volume serait monté… seulement dans l'espace de noms du pilote.

**3. Réponse B.** En montage `hard`, le client NFS réessaie indéfiniment : le processus attend en état `D`, non interruptible (même `kill -9` n'agit qu'au retour du serveur). A décrit le montage `soft` (après `timeo`/`retrans`), qui rend des erreurs d'E/S, avec un risque de corruption applicative. C : le cache de pages accepte des écritures, mais `fsync` ou la pression mémoire bloqueront aussi. D n'existe pas. Un volume RBD dont le cluster ne répond plus se comporte comme B : c'est pourquoi on n'arrête jamais `ceph-par1` sous des volumes montés (règle 3 du module).

**4. ext4 et XFS.** Agrandissement à chaud : les deux (`resize2fs`, `xfs_growfs` sur le point de montage) ; c'est ce que fait `NodeExpandVolume` (E11). Réduction : ext4 seulement, et **démonté** ; XFS ne se réduit jamais. Clone : deux XFS de même UUID ne se montent pas sur le même hôte sans `nouuid` (M08-E06) ; ext4 n'a pas cette garde. ceph-csi ajoute d'ailleurs `nouuid` aux montages XFS (le commentaire de la classe d'exemple le dit), parce que les clones de volumes sont courants.

**5. Bloc ou système de fichiers.** Un périphérique bloc est une suite d'octets adressables : c'est le processus (ou son système de fichiers à lui) qui l'organise. Un système de fichiers monté est déjà organisé (fichiers, droits, cache) par le noyau. Préfèrent le bloc : les bases qui gèrent leurs propres E/S directes (certaines configurations d'Oracle, Ceph lui-même pour ses OSD, une VM KubeVirt dont le disque est un volume), et les applications qui partagent un disque entre nœuds avec leur propre protocole. Dans Kubernetes : `volumeMode: Block` (E11).

**Réponses argumentées — pods et volumes**

**6. Durées de vie.** Fichier dans `/tmp` (couche inscriptible du conteneur) : (a) **perdu** au redémarrage du conteneur (une nouvelle couche est créée depuis l'image) ; (b) perdu ; (c) perdu. Dans un `emptyDir` : (a) **conservé** (le volume appartient au pod, pas au conteneur) ; (b) perdu (`rollout restart` crée de **nouveaux** pods) ; (c) conservé si le pod n'a pas été supprimé entre-temps et revient sur le même nœud (un pod lié à un nœud redémarré est relancé par le kubelet avec ses volumes) — mais un pod de Deployment évincé ou replanifié ailleurs repart vide. Seul un volume persistant survit à tout cela (E02, étape 2).

**7. Réponse B.** `ReadWriteOnce` = un **nœud** à la fois. Les pods placés sur le nœud qui a monté le volume démarrent tous les trois (ils partagent le volume, ce qui est rarement ce qu'on veut) ; ceux placés ailleurs restent en `ContainerCreating` avec `Multi-Attach error` (ou en `Pending` si le pilote déclare une topologie). A serait RWX. C est le comportement d'un StatefulSet avec `volumeClaimTemplates`, pas d'un Deployment. D : l'API ne vérifie pas cette cohérence.

**8. StatefulSet.** Garanties : (1) identité **stable** : nom (`valkey-0`), nom DNS par le Service sans tête, et **son** PVC (`donnees-valkey-0`) qui le suit d'un nœud à l'autre ; (2) **ordre** : création, mise à jour et suppression une instance à la fois, dans l'ordre des ordinaux (par défaut) ; (3) « **au plus un** » pod par identité : le contrôleur ne recrée pas `valkey-0` tant que l'ancien n'est pas confirmé arrêté, pour ne jamais avoir deux écrivains sur le même volume. Un Deployment donne des noms aléatoires, partage un éventuel PVC entre tous ses pods et peut avoir temporairement deux pods (surplus de la mise à jour).

**9. PV, PVC, StorageClass.** PV : un morceau de stockage réel, décrit pour le cluster (objet **de cluster**). PVC : une demande de stockage d'une application (objet **d'espace de noms**). StorageClass : un modèle qui dit comment fabriquer un PV à la demande (pilote, paramètres, politique) — objet de cluster. Le PVC est le seul que manipulent les équipes.

**10. Réponse B.** Le finaliseur `kubernetes.io/pvc-protection` retient le PVC en `Terminating` tant qu'un pod l'utilise ; il disparaît quand le dernier pod s'arrête (E03, étape 7). Même mécanisme pour un PV lié (`kubernetes.io/pv-protection`). A est ce que la protection empêche. C : l'API accepte la demande (elle pose seulement `deletionTimestamp`). D : un PVC supprimé libère son PV, il ne le laisse pas attaché.

**11. Nœud éteint brutalement.** Le nœud passe `NotReady`/`Unknown` après le délai de grâce du contrôleur de nœuds (de l'ordre de 40 à 50 s), reçoit le *taint* `node.kubernetes.io/unreachable:NoExecute` ; les pods le tolèrent 300 s par défaut, puis sont marqués pour suppression. (a) Deployment sans volume : de nouveaux pods sont créés ailleurs au bout d'environ **5 minutes**, même si les anciens restent affichés `Terminating` (ils ne peuvent être confirmés supprimés sans le kubelet). (b) StatefulSet avec RWO : **rien ne repart** tant que l'ancien pod n'est pas supprimé pour de bon, parce que le plan de contrôle ne sait pas si le nœud est mort ou seulement isolé et écrit encore. Il faut lever le doute : *taint* `node.kubernetes.io/out-of-service` (arrêt non gracieux) ou suppression forcée après avoir **vérifié** que le nœud est éteint (E08, étape 5 ; E37).

**12. Secret.** Toute identité qui a `get` (ou `list`, `watch`) sur les Secrets de l'espace `ceph-csi`, et toute personne qui peut créer un pod dans cet espace (elle monte le Secret) ; plus, par nature, les administrateurs du cluster et quiconque lit etcd ou ses sauvegardes. Il est stocké dans **etcd**, chiffré au repos depuis M14-E28 (fournisseur `secretbox` après la rotation de clé de cet exercice ; la clé de chiffrement est dans le fichier de configuration, sur les nœuds de contrôle) ; dans l'API, il n'est qu'encodé en base64. D'où : RBAC strict sur `ceph-csi`, Pod Security et contrôle d'admission qui empêchent de monter le Secret ailleurs, et une identité Ceph minimale (le jour où la clé fuit, elle ne donne que `k8s-rbd`).

**Réponses argumentées — protection des données**

**13. RPO et RTO.** RPO (*Recovery Point Objective*) : la quantité de données qu'on accepte de perdre, exprimée en temps (« au plus 5 minutes d'écritures ») ; RTO (*Recovery Time Objective*) : la durée maximale d'indisponibilité (« reprise en moins d'une heure »). Pour MédiAgenda : RPO 5 min (des rendez-vous pris et perdus sont des patients qui viennent pour rien), RTO 1 h en heures ouvrées. Le RPO dépend de la **fréquence** des copies hors du système (archivage des WAL en continu : quelques secondes à minutes ; sauvegarde nocturne : 24 h) ; le RTO de la **vitesse de restauration** (taille des données, débit depuis le S3, automatisation, procédure répétée) et du temps de décision. Palier 2 (E19) et 3 (E32, E34).

**14. Cohérence.** *Crash-consistent* : l'état du disque tel qu'il serait après une coupure de courant à l'instant de l'instantané (écritures en vol perdues, rien de réordonné) ; *application-consistent* : l'application a été mise dans un état propre (transactions validées, tampons vidés, gel) avant l'instantané. Un instantané du disque d'un PostgreSQL en marche est *crash-consistent* : PostgreSQL sait redémarrer depuis un tel état (il rejoue ses WAL, comme après une panne), **si** les WAL et les données sont sur le **même** instantané atomique. Ce n'est pas grave pour PostgreSQL, ça l'est pour une application qui écrit sur plusieurs volumes sans coordination, ou pour un système de fichiers sans journal.

**15. Réponse B.** `rsync` copie les fichiers à des instants différents pendant que PostgreSQL les modifie : la copie mélange des pages d'époques différentes. Elle n'est récupérable qu'avec la procédure de sauvegarde de base (`pg_backup_start`/`pg_backup_stop`, ou `pg_basebackup`) **et** les WAL de toute la durée de la copie. A est faux (l'atomicité vaut pour une page, pas pour le répertoire). C : deux copies incohérentes ne font pas une copie cohérente. D : Ceph ne change rien à la cohérence d'une copie de fichiers. C'est le travail de CloudNativePG et du plugin Barman Cloud (E19).

**16. Synchrone ou asynchrone.** Synchrone : la validation attend qu'au moins une réplique ait écrit (ou reçu) le WAL : RPO **nul** si le primaire meurt, au prix de la latence réseau sur chaque validation ; si la réplique synchrone tombe, les validations **attendent** (blocage) sauf à prévoir plusieurs candidates ou un repli. Asynchrone : la validation n'attend pas : latence minimale, mais les dernières transactions validées peuvent être perdues à la bascule (RPO = retard de réplication). CloudNativePG permet les deux (E25, E40).

**17. Bases dans Kubernetes.** Pour : le même outillage que les applications (déclaratif, GitOps, sauvegardes et bascules automatisées par un opérateur mûr comme CloudNativePG), des environnements de test créés en minutes (clones), la densité. Contre : une couche de plus entre la base et le disque (CSI, réseau de stockage, ordonnanceur qui peut déplacer le pod), des compétences doubles (DBA **et** Kubernetes) pour diagnostiquer, et des modes de défaillance nouveaux (nœud injoignable avec volume attaché, mise à jour du cluster qui draine les nœuds de la base). La réponse de MédiSphère : oui, avec un opérateur, du stockage maîtrisé et des sauvegardes hors cluster testées (ADR-0160).

**Réponses argumentées — le lien avec Ceph**

**18. `exclusive-lock`.** Un verrou coopératif : un seul client à la fois **écrit** l'image (indispensable à `object-map`/`fast-diff`, dont l'index serait sinon corrompu par deux écrivains). Un client qui veut écrire demande le verrou au détenteur, qui le cède. S'il a disparu sans le rendre (nœud mort), le nouveau client constate que le détenteur ne répond plus, le met sur **liste de blocage** (*blocklist*) auprès des moniteurs — d'où le besoin de `profile rbd` côté moniteur — puis prend le verrou : les OSD refuseront désormais les écritures de l'ancien client s'il revenait. Le verrou protège la cohérence de l'image, pas celle d'un système de fichiers monté deux fois (ce qu'empêchent RWO et le StatefulSet).

**19. RBD ou CephFS.** (a) PostgreSQL : **RBD** (un seul écrivain, latence faible, système de fichiers local au nœud, instantanés et clones rapides). (b) Pièces jointes partagées de deux instances : **CephFS** (plusieurs nœuds lisent et écrivent les mêmes fichiers, RWX) — ou mieux, du stockage objet. (c) Journaux AOF de Valkey : **RBD** (un seul processus, écritures séquentielles, aucun partage).

**20. Surallocation.** Oui : le quota d'un pool porte sur les octets **stockés**, et une image RBD n'occupe que ce qui y a été écrit ; la somme des tailles des PVC n'est pas contrôlée par Ceph (seulement par les quotas de Kubernetes, E20). Le jour où le pool atteint son quota, Ceph le marque plein (`POOL_FULL`) et **refuse les écritures** dans ce pool, pour tous ses clients à la fois. Côté pod : par défaut, le noyau **bloque** les écritures en attente que la condition se lève (processus en état `D`, application figée), sauf option `abort_on_full` au mappage (erreur `ENOSPC`). Panne pratiquée en M16-E38.

---

### M16-E02 — Volumes éphémères, `emptyDir` et `hostPath`

**Solution**

Fichiers : [`e02-ephemere.yaml`](fichiers/M16-E02/essais/e02-ephemere.yaml) (ConfigMap et pod), [`e02-gourmand.yaml`](fichiers/M16-E02/essais/e02-gourmand.yaml), [`e02-hostpath.yaml`](fichiers/M16-E02/essais/e02-hostpath.yaml).

*A. La couche du conteneur et `emptyDir`*

1. Le pod `e02-ephemere` : utilisateur 65534, `seccompProfile: RuntimeDefault`, capacités retirées, `allowPrivilegeEscalation: false` (le profil `restricted`, plus strict que ce qu'exige l'espace) ; trois volumes ; une boucle qui sort en erreur dès que `/tmp/arret` existe.
   ```
   admin@adm01:~$ kubectl apply -f ~/m16/e02/e02-ephemere.yaml
   admin@adm01:~$ kubectl -n wb-essais get pod e02-ephemere -o wide
   NAME           READY   STATUS    RESTARTS   AGE   IP             NODE
   e02-ephemere   1/1     Running   0          12s   10.240.2.31    k8s-w02
   ```
2. Redémarrage du **conteneur**, puis recréation du **pod** :
   ```
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- touch /tmp/arret
   admin@adm01:~$ kubectl -n wb-essais get pod e02-ephemere           # RESTARTS 1 après quelques secondes
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- wc -l /tmp/couche /travail/journal
          1 /tmp/couche
          2 /travail/journal
   admin@adm01:~$ kubectl -n wb-essais delete pod e02-ephemere && kubectl apply -f ~/m16/e02/e02-ephemere.yaml
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- wc -l /tmp/couche /travail/journal
          1 /tmp/couche
          1 /travail/journal
   ```
   La couche inscriptible meurt avec le **conteneur** ; l'`emptyDir` avec le **pod**. Refais l'étape du `touch` une fois sur le pod recréé : la vérification attend `RESTARTS` ≥ 1.
3. Le répertoire sur le nœud :
   ```
   admin@adm01:~$ kubectl -n wb-essais get pod e02-ephemere -o jsonpath='{.metadata.uid} {.spec.nodeName}{"\n"}'
   8d1f…-…  k8s-w02
   admin@k8s-w02:~$ sudo ls /var/lib/kubelet/pods/8d1f…/volumes/
   kubernetes.io~empty-dir  kubernetes.io~projected
   admin@k8s-w02:~$ sudo ls -l /var/lib/kubelet/pods/8d1f…/volumes/kubernetes.io~empty-dir/
   drwxrwsrwx 2 root 65534 4096 … cache        ← tmpfs (findmnt le montre)
   drwxrwxrwx 2 root root  4096 … travail
   admin@k8s-w02:~$ findmnt -T /var/lib/kubelet ; df -h /var/lib/kubelet
   ```
   `travail` est sur le disque **système** du nœud (60 Gio sur `local-nvme`), le même que les images de containerd et les journaux. Des pods qui remplissent leurs `emptyDir` remplissent ce disque : au-delà des seuils d'éviction du kubelet (`nodefs.available`, `imagefs.available`), le nœud passe en `DiskPressure` et **évince** des pods, y compris ceux qui n'y sont pour rien. D'où `sizeLimit` et les demandes de `ephemeral-storage`.

*B. Les limites*

4. `e02-gourmand` écrit 150 Mio dans un `emptyDir` limité à 100 Mio :
   ```
   admin@adm01:~$ kubectl apply -f ~/m16/e02/e02-gourmand.yaml ; sleep 90
   admin@adm01:~$ kubectl -n wb-essais get pod e02-gourmand -o jsonpath='{.status.phase} {.status.reason}{"\n"}'
   Failed Evicted
   admin@adm01:~$ kubectl -n wb-essais get events --field-selector involvedObject.name=e02-gourmand
   … Warning  Evicted  … Usage of EmptyDir volume "brouillon" exceeds the limit "100Mi".
   admin@adm01:~$ kubectl -n wb-essais delete pod e02-gourmand
   ```
   L'écriture elle-même **réussit** (rien ne limite le système de fichiers du nœud à 100 Mio) : c'est le **gestionnaire d'éviction du kubelet**, qui mesure périodiquement l'occupation des volumes locaux, qui tue le pod après coup. Le délai (de quelques secondes à une minute) est celui de sa boucle de surveillance.
5. Le volume en mémoire :
   ```
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- df -h /cache
   Filesystem    Size   Used  Available Use% Mounted on
   tmpfs         32.0M     0      32.0M   0% /cache
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- dd if=/dev/zero of=/cache/gros bs=1M count=64
   dd: error writing '/cache/gros': No space left on device
   33+0 records in
   32+0 records out
   admin@adm01:~$ kubectl top pod -n wb-essais e02-ephemere      # la mémoire du pod a pris ~32 Mio
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- rm /cache/gros
   ```
   Le tmpfs a la taille de `sizeLimit` (à défaut, celle de la mémoire allouable au pod) ; ses pages sont comptées dans la **mémoire du conteneur** qui les écrit, donc dans sa limite (128 Mio) : un `sizeLimit` supérieur à la limite mémoire mènerait à un `OOMKilled` plutôt qu'à `ENOSPC`. Un `emptyDir` en mémoire est rapide et ne laisse rien sur disque (utile pour des clés de déchiffrement temporaires : ceph-csi s'en sert, volume `keys-tmp-dir`), mais il se paie en mémoire.

*C. Les volumes projetés*

6. Lecture et décodage du jeton (charge utile seulement, dans le terminal) :
   ```
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- ls -la /config
   lrwxrwxrwx … etiquettes -> ..data/etiquettes
   lrwxrwxrwx … ..data -> ..2026_10_08_09_41_12.1234567
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- cat /config/niveau /config/limite-memoire /config/etiquettes
   INFO
   128
   app.kubernetes.io/name="e02-ephemere"
   medisphere.internal/exercice="m16-e02"
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- cat /config/jeton | python3 -c '
   import sys, json, base64
   p = sys.stdin.read().split(".")[1]; p += "=" * (-len(p) % 4)
   c = json.loads(base64.urlsafe_b64decode(p)); print(c["aud"], c["exp"] - c["iat"], c["sub"])'
   ['wb-essais'] 600 system:serviceaccount:wb-essais:default
   ```
   Le jeton est lié au pod (revendication `kubernetes.io` : pod, UID) et le kubelet le renouvelle avant expiration (à 80 % de sa durée). Changement de la ConfigMap :
   ```
   admin@adm01:~$ kubectl -n wb-essais patch configmap e02-config --type merge -p '{"data":{"niveau":"DEBUG"}}'
   admin@adm01:~$ for i in $(seq 1 20); do kubectl -n wb-essais exec e02-ephemere -- cat /config/niveau; sleep 10; done
   admin@adm01:~$ kubectl -n wb-essais exec e02-ephemere -- printenv NIVEAU
   INFO
   ```
   Le fichier change après une à deux minutes (période de synchronisation du kubelet plus la durée de son cache) : le kubelet écrit un nouveau répertoire horodaté et bascule le lien `..data` d'un coup (le changement est atomique pour le lecteur). La variable d'environnement, elle, est figée au démarrage du processus ; et un fichier monté par `subPath` n'est **jamais** mis à jour.

*D. `hostPath`*

7. Refus dans `wb-essais` :
   ```
   admin@adm01:~$ kubectl apply -f ~/m16/e02/e02-hostpath.yaml -l medisphere.internal/essai=refuse
   Error from server (Forbidden): error when creating "…": pods "e02-hote" is forbidden: violates PodSecurity "baseline:latest": hostPath volumes (volume "pki")
   ```
   C'est le contrôleur d'admission **Pod Security** (intégré à l'API, réglé par les étiquettes de l'espace, M14-E18) : `baseline` et `restricted` interdisent tous deux les volumes `hostPath`.
8. Dans un espace `privileged` :
   ```
   admin@adm01:~$ kubectl apply -f ~/m16/e02/e02-hostpath.yaml -l medisphere.internal/essai=privilegie
   admin@adm01:~$ kubectl -n wb-privilegie exec e02-hote -- ls -l /pki-du-noeud
   -rw------- 1 root root 2814 … kubelet-client-2026-10-02-….pem
   lrwxrwxrwx 1 root root   59 … kubelet-client-current.pem -> /var/lib/kubelet/pki/kubelet-client-2026-10-02-….pem
   -rw-r--r-- 1 root root 2290 … kubelet.crt
   -rw------- 1 root root 1679 … kubelet.key
   admin@adm01:~$ kubectl delete namespace wb-privilegie
   ```
   Le conteneur tourne en root (rien ne l'en empêche ici) et voit la **clé privée du kubelet** : avec elle, on s'authentifie auprès de l'API **comme le nœud** (lire les Secrets des pods du nœud, modifier son statut). Avec `hostPath: /`, on réécrit n'importe quel fichier de l'hôte (clé SSH de `root`, unités systemd) ; avec `/run/containerd/containerd.sock`, on lance n'importe quel conteneur hors de tout contrôle ; avec `/var/lib/kubelet/pods`, on lit les Secrets montés par les autres pods. Pouvoir créer un pod dans un espace `privileged`, c'est être root sur le nœud. C'est aussi pourquoi l'espace `ceph-csi` (E06), privilégié par nécessité, ne contient que les pilotes et n'est accessible qu'à la Plateforme.

**Explications**

Trois durées de vie : celle du **conteneur** (couche inscriptible), celle du **pod** (`emptyDir`, volumes projetés), celle d'un **objet de l'API indépendant** (PVC, E03). Les volumes projetés ne sont pas du stockage : le kubelet matérialise des objets de l'API (ConfigMap, Secret, API descendante, jeton) en fichiers, en lecture seule, et les met à jour. `hostPath` n'est pas un volume persistant mais une fenêtre sur le nœud : les données y restent si le pod revient sur **le même** nœud, ce qui en fait au mieux un volume local mal géré (E03 montre la version propre, `local`), au pire une faille.

**Alternatives**
- `ephemeral.volumeClaimTemplate` (volume éphémère **générique**) : un vrai PVC, créé et supprimé avec le pod, sur `ceph-rbd` après E06 ; pour des fichiers temporaires volumineux qui ne doivent pas charger le disque des nœuds.
- Volume `image` (GA en 1.36, containerd 2.1+) : monter le contenu d'une image OCI en lecture seule (modèles, jeux de données).
- `readOnlyRootFilesystem: true` + `emptyDir` pour les seuls répertoires inscriptibles nécessaires : la pratique recommandée pour les applications (MédiAgenda, E08).

**Pièges classiques**
- Croire qu'un `emptyDir` survit à un `rollout restart` ou à un drain : il meurt avec le pod.
- Oublier `sizeLimit` et `resources.limits.ephemeral-storage` : un pod bavard remplit le disque du nœud et en fait évincer d'autres.
- Un `emptyDir` en mémoire plus grand que la limite mémoire du conteneur : `OOMKilled` au lieu d'une erreur d'écriture.
- Monter une ConfigMap par `subPath` et s'étonner qu'elle ne se mette jamais à jour.
- Contourner Pod Security en étiquetant un espace d'application `privileged` « pour que ça marche » : c'est donner root sur les nœuds à tous ceux qui y déploient.

**En production chez MédiSphère**
Quotas d'espace de noms sur `requests.ephemeral-storage` et `limits.ephemeral-storage` (E20), `LimitRange` qui fixe une valeur par défaut, `readOnlyRootFilesystem` exigé par une politique d'admission (M26, Kyverno), espaces `privileged` listés et revus (seulement `ceph-csi` et les composants qui l'exigent), et supervision du disque des nœuds (`kubelet_volume_stats_*`, `DiskPressure`, M21).

---

### M16-E03 — PV, PVC et StorageClass : le cycle de vie d'un volume

**Solution**

Fichiers : [`e03-volume-local.yaml`](fichiers/M16-E03/essais/e03-volume-local.yaml) (classe et PV), [`e03-pvc-pods.yaml`](fichiers/M16-E03/essais/e03-pvc-pods.yaml), [`e03-partage.yaml`](fichiers/M16-E03/essais/e03-partage.yaml).

*A. Le décor*

1. Aucune classe, aucun PV au départ :
   ```
   admin@adm01:~$ kubectl get sc,pv
   No resources found
   ```
   Un PVC sans `storageClassName`, sans classe par défaut, reste sans classe : il ne peut se lier qu'à un PV **sans** classe. Le jour où une classe par défaut apparaît (E06), le contrôleur lui **attribue rétroactivement** cette classe (comportement stable depuis Kubernetes 1.28) et il sera provisionné par ceph-csi. D'où la règle : `storageClassName: ""` explicite pour un PVC qui vise un PV statique sans classe.
2. Le répertoire, la classe et le PV :
   ```
   admin@k8s-w01:~$ sudo mkdir -p /srv/wb-local/e03 && sudo chmod 0777 /srv/wb-local/e03
   admin@adm01:~$ kubectl apply -f ~/m16/e03/e03-volume-local.yaml
   admin@adm01:~$ kubectl get pv e03-local-w01
   NAME            CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   …
   e03-local-w01   1Gi        RWO            Retain           Available           local-manuel
   ```

*B. Liaison*

3. ```
   admin@adm01:~$ kubectl apply -f ~/m16/e03/e03-pvc-pods.yaml -l medisphere.internal/objet=pvc
   admin@adm01:~$ kubectl -n wb-essais describe pvc e03-donnees | tail -3
     Normal  WaitForFirstConsumer  …  waiting for first consumer to be created before binding
   ```
   Liaison **différée** : la classe le demande, pour que le planificateur choisisse d'abord le nœud du pod en tenant compte de tout (ressources, *taints*, affinité **du PV**), puis que le PVC soit lié à un PV compatible avec ce nœud.
4. ```
   admin@adm01:~$ kubectl apply -f ~/m16/e03/e03-pvc-pods.yaml -l medisphere.internal/objet=ecrivain
   admin@adm01:~$ kubectl -n wb-essais get pod e03-ecrivain -o wide ; kubectl -n wb-essais get pvc e03-donnees
   e03-ecrivain   1/1  Running  …  k8s-w01
   e03-donnees    Bound    e03-local-w01   1Gi   RWO   local-manuel
   admin@k8s-w01:~$ tail -2 /srv/wb-local/e03/trace
   1791451230 e03-ecrivain
   1791451240 e03-ecrivain
   ```
   Le planificateur (greffon *VolumeBinding*) n'a retenu que `k8s-w01`, le seul nœud que l'affinité du PV autorise. La capacité affichée est celle du **PV** (1 Gio) : un PVC se lie à un PV d'au moins la taille demandée et en reçoit toute la capacité. Avec un volume `local`, rien ne l'empêche d'ailleurs d'écrire au-delà : c'est un répertoire du disque du nœud, sans quota.
5. `e03-lecteur` démarre **sur `k8s-w01`** et lit le fichier : `ReadWriteOnce` limite à **un nœud**, pas à un pod. Deux pods du même nœud partagent le volume.
6. ```
   admin@adm01:~$ kubectl apply -f ~/m16/e03/e03-partage.yaml
   admin@adm01:~$ kubectl -n wb-essais describe pod e03-partage | tail -2
     Warning  FailedScheduling  …  0/6 nodes are available: 3 node(s) didn't find available persistent volumes to bind, 3 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }. …
   admin@adm01:~$ kubectl delete -f ~/m16/e03/e03-partage.yaml
   ```
   Aucun PV de la classe n'offre `ReadWriteMany` : le planificateur ne trouve aucun nœud où le lier. `ReadWriteOncePod` n'est pris en charge que par les volumes **CSI** ; un PV `local` est un type intégré à Kubernetes, sans pilote CSI : impossible de l'essayer ici (E06).

*C. Libération et réutilisation*

7. ```
   admin@adm01:~$ kubectl -n wb-essais delete pvc e03-donnees --wait=false
   admin@adm01:~$ kubectl -n wb-essais get pvc e03-donnees -o jsonpath='{.status.phase} {.metadata.deletionTimestamp} {.metadata.finalizers}{"\n"}'
   Bound 2026-10-08T09:58:02Z ["kubernetes.io/pvc-protection"]
   admin@adm01:~$ kubectl -n wb-essais delete pod e03-ecrivain e03-lecteur
   admin@adm01:~$ kubectl get pv e03-local-w01
   e03-local-w01   1Gi   RWO   Retain   Released   wb-essais/e03-donnees   local-manuel
   ```
   Le PVC (en `Terminating`, phase encore `Bound`) disparaît quand plus aucun pod ne l'utilise ; le PV passe `Released` : `Retain` le garde, avec ses données (`trace` est intact sur le nœud).
8. Un nouveau `e03-donnees` reste `Pending` : le PV `Released` garde `spec.claimRef` avec l'**UID** de l'ancien PVC, que le nouveau n'a pas. Décision d'administrateur, ici : rendre le volume **à la même équipe**, sous le même nom de PVC, donc garder la réservation sans l'UID :
   ```
   admin@adm01:~$ kubectl get pv e03-local-w01 -o jsonpath='{.spec.claimRef}{"\n"}'
   {"apiVersion":"v1","kind":"PersistentVolumeClaim","name":"e03-donnees","namespace":"wb-essais","resourceVersion":"…","uid":"5b0c…"}
   admin@adm01:~$ kubectl patch pv e03-local-w01 --type json \
       -p '[{"op":"remove","path":"/spec/claimRef/uid"},{"op":"remove","path":"/spec/claimRef/resourceVersion"}]'
   admin@adm01:~$ kubectl get pv e03-local-w01          # Available, réservé à wb-essais/e03-donnees
   admin@adm01:~$ kubectl apply -f ~/m16/e03/e03-pvc-pods.yaml -l medisphere.internal/objet=pvc
   admin@adm01:~$ kubectl apply -f ~/m16/e03/e03-pvc-pods.yaml -l medisphere.internal/objet=ecrivain
   admin@k8s-w01:~$ awk '{print strftime("%T", $1), $2}' /srv/wb-local/e03/trace | sed -n '1p;$p'
   ```
   Le nouveau pod ajoute ses lignes à la suite des anciennes. Pour donner le volume à **une autre** équipe, on **efface** d'abord les données (`sudo find /srv/wb-local/e03 -mindepth 1 -delete` sur le nœud, après accord du propriétaire et, en production, après sauvegarde ou destruction tracée), puis on retire `claimRef` en entier (`{"op":"remove","path":"/spec/claimRef"}`) : le PV redevient `Available` pour n'importe quel PVC compatible. C'est exactement ce que la politique `Recycle` (dépréciée) faisait sans discernement, et ce que `Delete` fait par le pilote (E06).
9. `volumeMode: Block` : le pod reçoit un **périphérique** (`volumeDevices`, `devicePath: /dev/xvda`) au lieu d'un répertoire (`volumeMounts`) ; personne ne formate. Exige un PV bloc (un disque local entier, une image RBD) : E11.
10. `kubectl -n wb-essais delete pod e03-ecrivain` ; PV, PVC et classe restent jusqu'à la vérification. Après : `kubectl -n wb-essais delete pvc e03-donnees && kubectl delete pv e03-local-w01 && kubectl delete sc local-manuel`, puis `sudo rm -rf /srv/wb-local` sur `k8s-w01`.

**Explications**

Le contrôleur PV/PVC (dans `kube-controller-manager`) fait l'appariement : un PVC se lie au plus petit PV disponible compatible (classe, modes d'accès, `volumeMode`, taille, sélecteur, affinité si la liaison est différée), et la liaison est **bidirectionnelle** et exclusive (`spec.volumeName` du PVC, `spec.claimRef` du PV). La politique de récupération ne s'applique qu'à la **libération** : `Retain` ne fait rien (l'administrateur décide), `Delete` demande au pilote de détruire le stockage. Un volume `local` est la forme honnête de `hostPath` : objet de l'API, affinité de nœud explicite, que le planificateur respecte ; mais la donnée reste prisonnière du nœud : si `k8s-w01` est drainé (E05), le pod ne peut aller **nulle part**.

**Alternatives**
- *Local Static Provisioner* (sig-storage) : découvre les disques montés sous un répertoire et crée les PV `local` tout seul ; bonne solution pour des disques NVMe locaux de bases répliquées par l'application (Kafka, Cassandra), pas pour une base unique.
- Pré-liaison par `claimRef` (nom et espace, sans UID) dès la création du PV : garantit qu'un PV précis ira à un PVC précis (migration, restauration d'un volume existant).
- `volumeName` dans le PVC : la même chose, vue du côté de la demande.

**Pièges classiques**
- PVC sans `storageClassName: ""` qui vise un PV statique : le jour où une classe par défaut existe, il est provisionné dynamiquement au lieu d'être lié au PV prévu.
- `Immediate` avec des volumes locaux : le PVC se lie au PV d'un nœud où le pod ne peut pas aller (ressources, *taint*), et le pod reste `Pending` pour toujours.
- Retirer `claimRef` sans regarder ce qu'il y a dans le volume : les données d'une équipe deviennent celles d'une autre.
- Supprimer le PV d'un volume `Retain` en croyant supprimer les données : seul l'objet disparaît, le répertoire (ou l'image) reste, sans plus personne pour s'en souvenir.
- Oublier que `ReadWriteOnce` permet plusieurs pods sur le même nœud (deux instances d'une base sur le même volume, si elles se retrouvent sur le même nœud).

**En production chez MédiSphère**
Les équipes ne voient que des classes (E12, E20) ; aucun PV statique n'est créé à la main, sauf restauration ou migration documentée (RB-161). Les PV `Released` sont listés par la supervision (E27) et traités dans la semaine, avec le propriétaire.

---

### M16-E04 — Comprendre CSI

**Solution**

Fichier : [`docs/kubernetes/stockage/csi.md`](fichiers/M16-E04/medisphere/docs/kubernetes/stockage/csi.md).

*A. La spécification, et un cluster qui ne sait encore rien*

1. Appels (spécification CSI 1.x, sections *Identity*, *Controller*, *Node*) :

   | Appel | Ce qu'il fait | Obligatoire ? |
   |---|---|---|
   | `GetPluginInfo`, `GetPluginCapabilities`, `Probe` (Identity) | nom et version du pilote, services offerts, santé | oui |
   | `CreateVolume` / `DeleteVolume` | crée / détruit le volume dans le stockage (ici : une image RBD) | si la capacité `CREATE_DELETE_VOLUME` est annoncée |
   | `ControllerPublishVolume` / `Unpublish` | rend le volume accessible depuis un nœud (attacher un disque à une machine) | si `PUBLISH_UNPUBLISH_VOLUME` |
   | `ValidateVolumeCapabilities`, `ControllerGetCapabilities` | vérifie qu'un volume convient à un usage ; liste les capacités | oui |
   | `CreateSnapshot` / `DeleteSnapshot` / `ListSnapshots` | instantanés | si annoncé |
   | `ControllerExpandVolume` | agrandit le volume côté stockage | si annoncé |
   | `NodeStageVolume` / `Unstage` | prépare le volume **une fois par nœud** (mapper, formater si besoin, monter dans un répertoire global) | si `STAGE_UNSTAGE_VOLUME` |
   | `NodePublishVolume` / `Unpublish` | met le volume à disposition **d'un pod** (montage lié dans son répertoire) | oui |
   | `NodeExpandVolume` | agrandit le système de fichiers sur le nœud | si annoncé |
   | `NodeGetInfo`, `NodeGetCapabilities` | identité et topologie du nœud ; capacités | oui |

2. États : `CREATED` → (`ControllerPublishVolume`) `NODE_READY` → (`NodeStageVolume`) `VOL_READY` → (`NodePublishVolume`) `PUBLISHED`, et le chemin inverse. Deux étapes côté nœud parce que les coûts diffèrent : préparer un volume (mappage krbd, `fsck`, `mkfs` au premier usage, montage) se fait **une fois par nœud** ; le publier (un montage lié, éventuellement en lecture seule) se fait **par pod**. Deux pods du même nœud sur un même volume = un *stage*, deux *publish*.
3. ```
   admin@adm01:~$ kubectl get csidrivers
   No resources found
   admin@adm01:~$ kubectl get csinode k8s-w01 -o jsonpath='{.spec.drivers}{"\n"}'
   null
   admin@k8s-w01:~$ sudo ls /var/lib/kubelet/plugins_registry/ /var/lib/kubelet/plugins/
   /var/lib/kubelet/plugins/:
   /var/lib/kubelet/plugins_registry/:
   ```
   Le cluster sait qu'il **peut** recevoir des pilotes (un `CSINode` par nœud, créé par le kubelet), et rien de plus : sans pilote, seuls les volumes intégrés (`emptyDir`, `local`, projetés…) fonctionnent.
4. Sidecars : `external-provisioner` (PVC → `CreateVolume`, crée le PV), `external-attacher` (`VolumeAttachment` → `ControllerPublishVolume`), `external-resizer` (PVC agrandi → `ControllerExpandVolume`), `external-snapshotter` (sidecar `csi-snapshotter` : `VolumeSnapshotContent` → `CreateSnapshot` ; le **contrôleur** de snapshots, commun à tous les pilotes, est un composant à part dans `kube-system`, E06), `livenessprobe` (expose `Probe` en HTTP pour les sondes). Ils tournent **à côté de la partie Controller**, dans le pod du *provisioner*. `node-driver-registrar` tourne **à côté de la partie Node**, dans le DaemonSet : il inscrit le pilote auprès du kubelet. `NodeStageVolume` et `NodePublishVolume` sont appelés par le **kubelet**, directement sur la socket du pilote du nœud : aucun sidecar.

*B. Un vrai pilote*

5. ```
   admin@adm01:~$ kubectl -n ceph-csi get pod -l app=ceph-csi-rbd,component=provisioner -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'
   csi-rbdplugin csi-provisioner csi-resizer csi-snapshotter csi-attacher csi-rbdplugin-controller liveness-prometheus
   admin@adm01:~$ kubectl -n ceph-csi get pod -l app=ceph-csi-rbd,component=nodeplugin -o jsonpath='{.items[0].spec.containers[*].name}{"\n"}'
   csi-rbdplugin driver-registrar liveness-prometheus
   ```
   Le pilote est `csi-rbdplugin` (image `cephcsi`), présent dans les deux pods (en mode *controller* dans l'un, *node* dans l'autre) ; `csi-rbdplugin-controller` est un contrôleur propre à ceph-csi (réplication, réglages), `liveness-prometheus` le *livenessprobe* et les métriques.
6. ```
   admin@adm01:~$ kubectl get csidriver rbd.csi.ceph.com -o yaml | grep -A6 '^spec:'
   spec:
     attachRequired: true
     fsGroupPolicy: File
     podInfoOnMount: true
     seLinuxMount: true
     …
   admin@adm01:~$ kubectl get csinode k8s-w01 -o jsonpath='{.spec.drivers[*].name}{"\n"}' ; kubectl get csinode k8s-cp01 -o jsonpath='{.spec.drivers}{"\n"}'
   rbd.csi.ceph.com
   null
   admin@k8s-w01:~$ sudo ls /var/lib/kubelet/plugins_registry/ /var/lib/kubelet/plugins/rbd.csi.ceph.com/
   rbd.csi.ceph.com-reg.sock
   csi.sock
   ```
   `attachRequired: true` : Kubernetes passe par un `VolumeAttachment` et attend `attached` avant de monter (pour RBD, `ControllerPublishVolume` ne fait presque rien, mais le passage par l'attacheur sert de verrou logique « ce volume est à ce nœud »). `podInfoOnMount` : le kubelet transmet au pilote le nom, l'espace et l'UID du pod. `fsGroupPolicy: File` : le kubelet applique `fsGroup` au volume (E08). Les nœuds de contrôle n'ont pas le pilote : pas de *nodeplugin* (sélecteur de nœud des values, E06).
7. Suivi d'une recréation de pod :
   ```
   admin@adm01:~$ kubectl get volumeattachment -w                       # terminal 1
   admin@adm01:~$ kubectl -n wb-essais delete pod e06-essai && kubectl apply -f ~/m16/e06/e06-essai.yaml
   admin@adm01:~$ kubectl -n wb-essais get events --sort-by=.lastTimestamp | tail
   … Normal  Scheduled               pod/e06-essai  Successfully assigned wb-essais/e06-essai to k8s-w03
   … Normal  SuccessfulAttachVolume  pod/e06-essai  AttachVolume.Attach succeeded for volume "pvc-1b2c…"
   admin@adm01:~$ kubectl -n ceph-csi get lease | grep -i attacher            # qui est leader ?
   admin@adm01:~$ kubectl -n ceph-csi logs <PROVISIONER-LEADER> -c csi-attacher --since=10m | grep -i -E 'attach|detach' | tail
   admin@adm01:~$ kubectl -n ceph-csi logs <NODEPLUGIN-DE-k8s-w03> -c csi-rbdplugin --since=10m | grep -E 'GRPC (call|response)' | tail
   … GRPC call: /csi.v1.Node/NodeStageVolume
   … GRPC call: /csi.v1.Node/NodePublishVolume
   admin@k8s-w03:~$ sudo journalctl -u kubelet --since "-10 min" | grep -E 'MountDevice|SetUp succeeded'
   ```
   Ordre observé : planification, `VolumeAttachment` créé puis `attached: true` (`ControllerPublishVolume` sur le *provisioner* leader), `NodeStageVolume` puis `NodePublishVolume` sur le *nodeplugin* du nouveau nœud, démarrage du conteneur. À la suppression : `NodeUnpublishVolume`, `NodeUnstageVolume` (sur l'ancien nœud), puis `ControllerUnpublishVolume` et disparition du `VolumeAttachment`. ⚠️ À vérifier sur ton lab : la forme exacte des lignes `GRPC call` (niveau de journalisation 5 du chart par défaut).
8. Création et suppression d'un volume :
   ```
   admin@adm01:~$ kubectl -n wb-essais create -f - <<'EOF'
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata: {name: e04-jetable}
   spec: {accessModes: [ReadWriteOnce], resources: {requests: {storage: 1Gi}}}
   EOF
   admin@adm01:~$ kubectl -n ceph-csi logs <PROVISIONER-LEADER> -c csi-provisioner --since=5m | grep e04-jetable
   … "Started provisioning" PVC="wb-essais/e04-jetable" … "Successfully provisioned" …
   admin@adm01:~$ kubectl -n ceph-csi logs <PROVISIONER-LEADER> -c csi-rbdplugin --since=5m | grep -E 'GRPC call: /csi.v1.Controller/(Create|Delete)Volume'
   admin@adm01:~$ kubectl get pv $(kubectl -n wb-essais get pvc e04-jetable -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.csi}{"\n"}'
   {"driver":"rbd.csi.ceph.com","fsType":"ext4","volumeAttributes":{"clusterID":"<FSID>","imageFeatures":"layering,…","imageName":"csi-vol-6f2a…","journalPool":"k8s-rbd","pool":"k8s-rbd",…},"volumeHandle":"0001-0024-<FSID>-0000000000000003-6f2a…", …}
   admin@adm01:~$ kubectl -n wb-essais delete pvc e04-jetable
   ```
   Le `volumeHandle` encode le cluster, le pool (son identifiant) et l'UUID de l'image : c'est tout ce que le pilote recevra dans les appels suivants. ceph-csi tient aussi un **journal** (objets `csi.volumes.default` et `csi.volume.<uuid>` dans le pool) qui relie le nom de la demande Kubernetes à l'image : c'est lui qui rend `CreateVolume` idempotent (un appel répété après une coupure ne crée pas deux images).
9. La fiche du corrigé est un modèle : le tableau « étape → appel → qui → où → trace → journal » et la liste ordonnée des commandes devant un `ContainerCreating`.

**Explications**

CSI découple Kubernetes des stockages : le cœur de Kubernetes ne connaît que des objets (`PersistentVolume`, `VolumeAttachment`, `CSINode`) et le kubelet ne connaît que quelques appels gRPC ; tout le savoir-faire « Ceph » est dans le pilote. Les sidecars sont des contrôleurs génériques, les mêmes pour tous les pilotes, qui traduisent des objets de l'API en appels gRPC sur une socket Unix locale. Conséquence pour le diagnostic : chaque étape a **un** acteur et **un** journal, et il suffit de savoir à quelle étape on est bloqué (le `VolumeAttachment` dit si l'attachement est fait) pour savoir où lire.

**Alternatives**
- Le pilote de démonstration `csi-driver-host-path` (v1.18) : instructif, mais son installation (espace `default`, pods privilégiés, CRD de snapshots en prérequis) doublonne E06 ; on le lit plutôt sur GitHub.
- `kubectl get --raw /api/v1/nodes/<nœud>/proxy/metrics | grep storage_operation` : les durées des opérations de volume vues par le kubelet (supervision, E27).

**Pièges classiques**
- Lire les journaux d'un réplica non leader du *provisioner* et conclure « il ne se passe rien ».
- Chercher `NodeStageVolume` dans le *provisioner* : c'est le *nodeplugin* **du nœud du pod**.
- Croire qu'un pilote sans `VolumeAttachment` est cassé : CephFS en a un (attacheur activé dans le chart), d'autres pilotes non (`attachRequired: false`).
- Confondre le contrôleur de snapshots (commun, `kube-system`) et le sidecar `csi-snapshotter` (dans chaque pilote).

**En production chez MédiSphère**
La fiche `csi.md` est la première page lue par l'astreinte sur un incident de volume (lien depuis RB-160) ; les journaux des pilotes partent vers la plateforme de journaux (M22) avec des requêtes enregistrées (`GRPC error`) ; les métriques des opérations de volume (`storage_operation_duration_seconds`) alimentent une alerte sur les montages lents (M21).

---

### M16-E05 — Raccorder les travailleurs au réseau de stockage

**Solution**

Fichiers : [`noeuds.tf.extrait`](fichiers/M16-E05/infra/envs/k8s/noeuds.tf.extrait) (état `k8s`), rôle [`k8s_reseau_stockage`](fichiers/M16-E05/ansible/roles/k8s_reseau_stockage/) (tâches, gabarit netplan, protection cloud-init, `README.md`), [`playbooks/k8s-reseau-stockage.yml`](fichiers/M16-E05/ansible/playbooks/k8s-reseau-stockage.yml), [`matrice-flux.md.extrait`](fichiers/M16-E05/medisphere/docs/socle/matrice-flux.md.extrait).

*A. Préparer sans rien casser*

1. État de départ :
   ```
   admin@k8s-w01:~$ ip -br link | grep -v lxc ; ip route | head -3 ; ls /etc/netplan/
   eth0   UP   bc:24:11:40:00:61 …
   default via 10.10.40.1 dev eth0 proto static
   50-cloud-init.yaml
   admin@k8s-w01:~$ sudo cloud-init query instance_id
   7f3c0e4d…                                    ← à noter
   admin@k8s-w01:~$ sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
   256 SHA256:Qm8…  root@k8s-w01 (ED25519)    ← à noter
   admin@adm01:~$ kubectl get node k8s-w01 -o wide        # INTERNAL-IP 10.10.40.61
   ```
   La configuration réseau vient de **cloud-init**, au premier démarrage, à partir du lecteur que Proxmox fabrique avec `ipconfig0` (`50-cloud-init.yaml` ; la carte y est reconnue par sa MAC et nommée `eth0`, comme au M14). On n'y touche pas : la carte de stockage suit la même convention et s'appellera `eth1`.
2. `qm config 2144` montre `net0`, `ipconfig0` et le lecteur `ide2: local-nvme:vm-2144-cloudinit`. Proxmox régénère ce lecteur (*NoCloud*) quand la configuration change, et l'identifiant d'instance de ses métadonnées est une **empreinte** des données utilisateur et réseau : ajouter `ipconfig1` le change. Au démarrage suivant, cloud-init croit voir une nouvelle machine et rejoue ses modules « par instance ». Les deux effets redoutés : (1) **les clés d'hôte SSH sont régénérées** (`ssh_deletekeys: true` dans le `cloud.cfg` de Debian), donc ne correspondent plus au certificat d'hôte signé par la CA SSH (M06) ni aux `known_hosts` ; (2) **le réseau est réécrit** depuis le nouveau lecteur, avec des options qui ne sont pas les nôtres (pas de MTU explicite, adresse de la seconde carte décrite par `ipconfig1`), en concurrence avec notre fichier. ⚠️ À vérifier sur ton lab : compare `sudo cloud-init query instance_id` avant et après l'étape 5.
3. Le rôle (voir son `README.md`) : `cloud_init.yml` (fichier `99-medisphere-k8s.cfg` : `network: {config: disabled}` et `ssh_deletekeys: false`), `modules.yml` (`/etc/modules-load.d/ceph-csi.conf`), `reseau.yml` (netplan dans un dossier de répétition, `netplan generate --root-dir`, mise en place ; drain, redémarrage et attente seulement si la carte est présente **et** sans son adresse), `verifications.yml` (adresse et MTU, une seule route par défaut, `ping -M do -s 8972` vers les trois moniteurs, adresse interne Kubernetes inchangée, étiquette, `uncordon` si le rôle a drainé). La décision de redémarrer compare l'**état réel** (faits) à l'état voulu : le fichier netplan a pu être posé à l'étape 4 alors que la carte n'existait pas encore, et son « changed » ne veut plus rien dire au moment où la carte apparaît.
4. ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-reseau-stockage.yml --diff
   …
   TASK [k8s_reseau_stockage : Drainer le nœud (depuis adm01)] … skipping
   TASK [k8s_reseau_stockage : Vérifications et étiquette du nœud] … skipping
   PLAY RECAP  k8s-w01 : ok=12 changed=4 …   (fichiers posés, modules chargés ; aucun redémarrage)
   ```

*B. Un travailleur à la fois*

5. ```
   admin@adm01:~$ kubectl drain k8s-w01 --ignore-daemonsets --delete-emptydir-data
   admin@adm01:~/src/infra/envs/k8s$ tofu plan
     # module.noeud["k8s-w01"].proxmox_virtual_environment_vm.vm will be updated in-place
     + network_device { bridge = "vstopub" … mac_address = "BC:24:11:30:00:61" … mtu = 9000 }
     ~ initialization { + ip_config { + ipv4 { + address = "10.10.30.81/24" } } … }
     # … netbox (interface et adresse de la carte 1) will be created
   Plan: 2 to add, 1 to change, 0 to destroy.
   ```
   (Noms des ressources NetBox du module à titre indicatif.) Une ligne `must be replaced` sur la VM est une erreur : on ne recrée pas un nœud pour lui ajouter une carte. MR, pipeline, `apply`. La carte est ajoutée à chaud (le branchement à chaud des cartes réseau est actif par défaut dans Proxmox) ; selon la version du fournisseur, la VM peut redémarrer à la fin de l'`apply` : la protection de l'étape 4 est déjà en place, et le nœud est drainé.
6. ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-reseau-stockage.yml -l k8s-w01
   TASK [k8s_reseau_stockage : Drainer le nœud (depuis adm01)] … changed
   TASK [k8s_reseau_stockage : Redémarrer le nœud] … changed
   TASK [k8s_reseau_stockage : Joindre chaque moniteur en 9000 octets …] … ok (×3)
   TASK [k8s_reseau_stockage : Étiqueter le nœud raccordé au réseau de stockage] … changed
   TASK [k8s_reseau_stockage : Remettre en service le nœud que ce rôle a drainé] … changed
   admin@k8s-w01:~$ ip -d link show eth1 | head -2 ; ip -4 addr show eth1 | grep inet
   3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000 …
       inet 10.10.30.81/24 brd 10.10.30.255 scope global eth1
   admin@k8s-w01:~$ ip route ; ip route get 10.10.30.52
   default via 10.10.40.1 dev eth0 proto static
   10.10.30.0/24 dev eth1 proto kernel scope link src 10.10.30.81
   10.10.40.0/24 dev eth0 proto kernel scope link src 10.10.40.61
   10.10.30.52 dev eth1 src 10.10.30.81
   admin@k8s-w01:~$ ping -M do -s 8972 -c 3 -I eth1 10.10.30.51        # 3 réponses, 0 % de perte
   admin@k8s-w01:~$ sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub   # empreinte INCHANGÉE
   admin@adm01:~$ kubectl get node k8s-w01 -o wide                          # INTERNAL-IP toujours 10.10.40.61
   ```
   Si l'`apply` avait déjà redémarré la VM, la carte est configurée au démarrage par netplan, le rôle ne redémarre pas, vérifie et étiquette : remets alors le nœud en service toi-même (`kubectl uncordon k8s-w01`). L'adresse interne du nœud ne change pas parce que le kubelet retient l'adresse de la carte de la **route par défaut** quand `node-ip` n'est pas fixé (si ton M14 l'a fixé, c'est encore mieux).
7. Un pod ordinaire sur `k8s-w01` :
   ```
   admin@adm01:~$ kubectl -n wb-essais run e05-test --rm -it --restart=Never \
       --image=registry.par1.medisphere.internal/dockerhub/library/debian:trixie-slim \
       --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k8s-w01"}}}' \
       -- bash -c 'for i in 1 2 3; do timeout 3 bash -c "</dev/tcp/10.10.30.51/3300" && echo ouvert; sleep 2; done'
   ouvert
   admin@k8s-w01:~$ sudo tcpdump -ni eth1 -c 4 host 10.10.30.51 and port 3300
   10.10.30.81.41874 > 10.10.30.51.3300: Flags [S] …
   10.10.30.51.3300 > 10.10.30.81.41874: Flags [S.] …
   admin@adm01:~$ hubble observe --to-ip 10.10.30.51 --last 20
   … wb-essais/e05-test (ID:…) -> 10.10.30.51:3300 (world) to-stack FORWARDED (TCP Flags: SYN)
   ```
   Le paquet quitte le pod (10.240.x.y), Cilium le remet à la pile de l'hôte (`to-stack`), la table de routage l'envoie par `eth1`, et il est **masqué** par l'adresse du nœud sur cette carte (10.10.30.81) : Cilium masque tout ce qui sort du réseau des pods vers l'extérieur du cluster. `ceph01` répond donc directement à 10.10.30.81, dans le VLAN 30. Si le paquet partait avec l'adresse du pod, `ceph01` répondrait par sa passerelle (`gw01`), qui ne connaît pas 10.240.0.0/16 : silence. ⚠️ À vérifier sur ton lab : avec le masquage **BPF** de Cilium, `eth1` doit figurer parmi les cartes que gère l'agent (`kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose | grep -i -A3 masquerading`) ; s'il n'y est pas, redémarre l'agent de ce nœud (`kubectl -n kube-system delete pod -l k8s-app=cilium --field-selector spec.nodeName=k8s-w01`). Ce chemin est celui des pods du *provisioner* de ceph-csi, qui ne sont pas en `hostNetwork` (E06).
8. Même chose pour `k8s-w02` (2145, .62 → .82), puis `k8s-w03` (2146, .63 → .83) : une MR OpenTofu chacun (l'entrée passe à `true`), un drain chacun.

*C. Documenter*

9. Lignes de la matrice : voir l'extrait. NetBox : `Adresses IP` → 10.10.30.81-83, affectées à l'interface 1 de chaque VM. La MR explique que `group_vars/role_routeur/pare_feu.yml` ne change pas : la bordure ne voit jamais ce flux (même VLAN, aucune route).

**Explications**

Le choix « une carte par VLAN, sans passerelle » est celui des clients Ceph depuis le module 08 (`cephcli01`) et d'OpenStack (M10) : le réseau public de Ceph est un réseau **de stockage**, pas un réseau d'accès. Le chemin direct évite trois problèmes à la fois : la charge et la latence de la bordure sur chaque E/S, le filtrage d'une plage de ports large (6800-7568 pour les OSD), et le MTU (le VLAN 40 est à 1500 ; le VLAN 30 en 9000 de bout en bout). Sans `set-name`, udev donnerait à la nouvelle carte son nom prévisible (`ens19` pour `net1`) : le fichier netplan la renomme `eth1`, dans la convention de `eth0` posée par cloud-init (M14), et c'est ce nom que citent le rôle, les checks et la documentation. Le rôle ne prend pas possession de tout le réseau du nœud (comme `noeud_openstack` le fait au M10) : il **ajoute** une carte, et neutralise seulement ce que cloud-init pourrait refaire derrière lui. Le redémarrage d'un nœud drainé, plutôt qu'un `netplan apply` à chaud, évite que `systemd-networkd`, reconfiguré, ne retire des routes ou des règles posées par Cilium, et prouve que la configuration tient au démarrage.

**Alternatives**
- `netplan apply` à chaud, nœud non drainé : plus rapide, mais pari sur la cohabitation de `systemd-networkd` et de Cilium ; si tu le tentes, sur un nœud drainé, avec `ManageForeignRoutes=no` et `ManageForeignRoutingPolicyRules=no` dans `networkd.conf` (recommandation de la documentation de Cilium pour les systèmes à `systemd-networkd`).
- Carte **sans adresse** dans OpenTofu (pas d'`ipconfig1`, donc pas de changement du lecteur cloud-init) et adresse posée par Ansible seulement : supprime le risque cloud-init, mais l'adresse n'est plus dans NetBox par le module : IPAM incomplet. Écartée.
- VLAN 30 en sous-interface de `eth0` (une seule carte, VLAN étiqueté par l'invité) : possible sur un trunk, mais la carte des nœuds est sur un VNet non étiqueté, et on mélangerait le MTU 1500 et 9000 sur la même interface parente.
- Passer par la bordure (ouvrir 3300 et 6800-7568 du VLAN 40 vers le VLAN 30) : la solution de facilité, refusée par le ticket.

**Pièges classiques**
- Ajouter la carte sans protéger cloud-init : nouvelles clés d'hôte SSH (alarme `REMOTE HOST IDENTIFICATION HAS CHANGED`, certificat d'hôte invalide), voire carte principale renommée.
- Une passerelle sur la seconde carte : deux routes par défaut, trafic Kubernetes asymétrique.
- MTU 9000 dans l'invité mais pas sur la carte Proxmox (ou l'inverse) : le `ping -M do -s 8972` échoue, les petites requêtes passent, les gros transferts se figent (M08-E42).
- Étiqueter le nœud avant d'avoir vérifié le réseau : les pods de ceph-csi s'y installent et les volumes restent en `ContainerCreating`.
- Drainer les trois travailleurs à la suite sans attendre que les pods soient revenus : la recette (et ses budgets d'interruption) ne s'en remet pas.
- `kubectl` de l'Ansible lancé avec `become` sur `adm01` : il cherche `/root/.kube/config`.

**En production chez MédiSphère**
Deux cartes de stockage en agrégat (LACP sur deux commutateurs) par travailleur, MTU vérifié en continu par la supervision (sonde `ping -M do` des nœuds vers les moniteurs, M21) ; l'étiquette `medisphere.internal/stockage-ceph` posée par l'outillage de construction des nœuds (Cluster API, M18 ; F1) et une alerte sur tout travailleur sans elle.

---

### M16-E06 — ceph-csi : des volumes RBD sur `ceph-par1`

**Solution**

Fichiers : [`espaces/ceph-csi.yaml`](fichiers/M16-E06/k8s/espaces/ceph-csi.yaml), [`composants/snapshot-controller/kustomization.yaml`](fichiers/M16-E06/k8s/composants/snapshot-controller/kustomization.yaml), [`values-rbd.yaml`](fichiers/M16-E06/k8s/composants/ceph-csi/values-rbd.yaml), [`installer.sh`](fichiers/M16-E06/k8s/composants/ceph-csi/installer.sh), classes [`ceph-rbd.yaml`](fichiers/M16-E06/k8s/composants/ceph-csi/classes/ceph-rbd.yaml) et [`ceph-rbd-retain.yaml`](fichiers/M16-E06/k8s/composants/ceph-csi/classes/ceph-rbd-retain.yaml), [`outils/ceph-csi-secrets.sh`](fichiers/M16-E06/k8s/outils/ceph-csi-secrets.sh), [`secrets/ceph-csi.yml.exemple`](fichiers/M16-E06/k8s/secrets/ceph-csi.yml.exemple), [`Taskfile.yml.extrait`](fichiers/M16-E06/k8s/Taskfile.yml.extrait), essais [`e06-essai.yaml`](fichiers/M16-E06/essais/e06-essai.yaml), [`e06-unique.yaml`](fichiers/M16-E06/essais/e06-unique.yaml), [`e06-garde.yaml`](fichiers/M16-E06/essais/e06-garde.yaml) ; documentation [`ceph-csi.md`](fichiers/M16-E06/medisphere/docs/kubernetes/stockage/ceph-csi.md), [`registre-secrets.extrait.md`](fichiers/M16-E06/medisphere/registre-secrets.extrait.md).

*A. Côté Ceph*

1. ```
   [admin@ceph01 ~]$ sudo ceph fsid
   3f1c2a9e-…                                                   ← <FSID>
   [admin@ceph01 ~]$ sudo ceph mon dump 2>/dev/null | grep mon\\.
   0: [v2:10.10.30.51:3300/0,v1:10.10.30.51:6789/0] mon.ceph01
   1: [v2:10.10.30.52:3300/0,v1:10.10.30.52:6789/0] mon.ceph02
   2: [v2:10.10.30.53:3300/0,v1:10.10.30.53:6789/0] mon.ceph03
   [admin@ceph01 ~]$ sudo ceph osd pool ls detail | grep k8s-rbd
   pool 12 'k8s-rbd' replicated size 3 min_size 2 crush_rule 1 … application rbd … max_bytes 21474836480
   [admin@ceph01 ~]$ sudo ceph auth get client.k8s | grep caps
   	caps mgr = "profile rbd pool=k8s-rbd"
   	caps mon = "profile rbd"
   	caps osd = "profile rbd pool=k8s-rbd"
   [admin@ceph01 ~]$ sudo ceph config get mon ms_service_mode
   secure
   ```
   Les droits sont exactement ceux de `docs/capabilities.md` (RBD). Le droit **mgr** sert aux opérations que ceph-csi délègue au module `rbd_support` du gestionnaire : suppression asynchrone des images (corbeille RBD et tâche de purge) et aplatissement des clones en tâche de fond (`ceph rbd task add …`) ; sans lui, une suppression ou un clone profond échoue ou bloque le *provisioner*.
2. La clé, du cluster au Vault, sans fichier en clair :
   ```
   admin@adm01:~/src/k8s$ mkdir -p secrets
   admin@adm01:~/src/k8s$ { printf 'ceph_csi_rbd_cle: "'; ssh ceph01 'sudo ceph auth get-key client.k8s'; printf '"\n'; } \
       | (cd ~/src/ansible && uv run ansible-vault encrypt --vault-id critique@outils/vault-pass-client.sh \
            --output ~/src/k8s/secrets/ceph-csi.yml -)
   admin@adm01:~/src/k8s$ head -1 secrets/ceph-csi.yml
   $ANSIBLE_VAULT;1.2;AES256;critique
   ```
   Si M08-E46 avait rangé la clé dans une variable d'un `vault-critique.yml` de `plateforme/ansible`, supprime-la de là (MR) : une seule copie de référence, celle que lit le script. Registre : voir l'extrait.

*B. Les fondations dans le cluster*

3. Le *sidecar* `csi-snapshotter` du pilote observe les `VolumeSnapshotContent` dès son démarrage : sans les CRD, il échoue (et le pod du *provisioner* redémarre en boucle) ; sans le contrôleur, les `VolumeSnapshot` ne sont jamais traités. D'où l'ordre « CRD et contrôleur, puis pilote » du README d'external-snapshotter.
   ```
   admin@adm01:~/src/k8s$ kubectl kustomize composants/snapshot-controller | grep -E '^kind:|image:'
   admin@adm01:~/src/k8s$ kubectl apply --server-side -k composants/snapshot-controller
   admin@adm01:~/src/k8s$ kubectl get crd | grep snapshot.storage.k8s.io
   volumesnapshotclasses.snapshot.storage.k8s.io    …
   volumesnapshotcontents.snapshot.storage.k8s.io   …
   volumesnapshots.snapshot.storage.k8s.io          …
   admin@adm01:~/src/k8s$ kubectl -n kube-system rollout status deploy/snapshot-controller
   ```
   `--server-side` : les CRD sont volumineuses, et l'annotation `last-applied-configuration` d'une application côté client dépasserait la taille permise pour les plus grosses. Les CRD de groupes de snapshots sont installées aussi (v1beta2 en stockage, v1 servie) : on ne s'en sert pas dans ce module.
4. `privileged` parce que le *nodeplugin* est privilégié (mapper un périphérique, monter), en `hostNetwork` (le noyau joint Ceph depuis l'espace réseau de l'hôte) et `hostPID`, et monte `/dev`, `/sys`, `/lib/modules`, `/var/lib/kubelet` (propagation `Bidirectional`) : rien de cela n'est admis en `baseline`. Le gabarit `templates/nodeplugin-daemonset.yaml` du chart le montre ligne à ligne.

*C. ceph-csi RBD*

5. `values-rbd.yaml` : `csiConfig` (une entrée : `clusterID` = fsid, trois moniteurs en `:3300`), `cephconf` (modes `secure` pour les bibliothèques des conteneurs), sélecteur de nœud et tolérance du *nodeplugin*, 2 réplicas de *provisioner* sur les nœuds étiquetés. Ni Secret (il viendrait de Git) ni StorageClass (une classe par défaut ne doit pas disparaître sur un `helm uninstall`, et une release n'en porte qu'une) : `secret.create` et `storageClass.create` restent à `false` (défaut du chart).
   ```
   admin@adm01:~/src/k8s$ helm repo add ceph-csi https://ceph.github.io/csi-charts
   admin@adm01:~/src/k8s$ composants/ceph-csi/installer.sh --rendu | less
   ```
6. ```
   admin@adm01:~/src/k8s$ kubectl apply -f espaces/ceph-csi.yaml
   admin@adm01:~/src/k8s$ composants/ceph-csi/installer.sh
   → ceph-csi-rbd 3.18.1
   …
   admin@adm01:~$ kubectl -n ceph-csi get pod -o wide
   ceph-csi-rbd-nodeplugin-4kq7d          3/3  Running  …  k8s-w01
   ceph-csi-rbd-nodeplugin-9xw2m          3/3  Running  …  k8s-w02
   ceph-csi-rbd-nodeplugin-t8hzc          3/3  Running  …  k8s-w03
   ceph-csi-rbd-provisioner-6d9c…-ab12c   7/7  Running  …  k8s-w01
   ceph-csi-rbd-provisioner-6d9c…-zz9k1   7/7  Running  …  k8s-w03
   ```
   Trois *nodeplugin* (un par travailleur étiqueté), aucun sur les nœuds de contrôle ; deux *provisioner* sur deux travailleurs différents (anti-affinité du chart).
7. Le script lit le Vault en mémoire (`ansible-vault view`), contrôle la forme de la clé, et crée chaque Secret par `kubectl create secret … --dry-run=client -o yaml | kubectl apply --server-side -f -`, la clé passant par une substitution de processus (ni `ps`, ni disque). `verifier` compare, par empreinte SHA-256 tronquée, Vault, Secret et `ceph auth get-key`, sans rien afficher :
   ```
   admin@adm01:~/src/k8s$ outils/ceph-csi-secrets.sh appliquer
   [OK] rbd : Secret ceph-csi/csi-rbd-secret (userID=k8s) à jour
   [--] cephfs : variable ceph_csi_cephfs_cle absente du Vault, ignoré
   admin@adm01:~/src/k8s$ outils/ceph-csi-secrets.sh verifier
   [OK] rbd : Secret identique au Vault
   [OK] rbd : Vault identique à Ceph (client.k8s)
   ```
   `userID` est `k8s`, **sans** `client.` (le pilote l'ajoute).
8. Fonctionnalités d'image : `layering` (clones), `exclusive-lock` (un écrivain, prérequis des deux suivantes), `object-map` et `fast-diff` (occupation et différences rapides : `rbd du`, sauvegardes incrémentales, snapshots), `deep-flatten` (aplatir un clone même si son parent a des instantanés) : toutes gérées par krbd depuis longtemps (Linux 5.3 pour les plus récentes, `object-map`/`fast-diff` ; ⚠️ à confirmer par le mappage réel), donc par le 6.12 des travailleurs. `journaling` (miroir RBD par journal) n'est **pas** géré par krbd : une image qui l'aurait ne se mapperait pas (`RBD image feature set mismatch`). `mapOptions: "krbd:ms_mode=secure"` : le noyau parle msgr2 en mode chiffré, sans repli (le défaut récent est `prefer-crc`, qui aboutirait aussi en `secure` face à `ceph-par1`, mais par négociation : on l'impose plutôt que de le subir). `discard` : les blocs libérés par ext4 retournent au pool (sous quota).
   ```
   admin@adm01:~/src/k8s$ kubectl apply -f composants/ceph-csi/classes/
   admin@adm01:~/src/k8s$ kubectl get sc
   NAME                 PROVISIONER        RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION
   ceph-rbd (default)   rbd.csi.ceph.com   Delete          Immediate           true
   ceph-rbd-retain      rbd.csi.ceph.com   Retain          Immediate           true
   local-manuel         kubernetes.io/no-provisioner   Retain   WaitForFirstConsumer   false
   ```

*D. Un volume de bout en bout*

9. ```
   admin@adm01:~$ kubectl apply -f ~/m16/e06/e06-essai.yaml
   admin@adm01:~$ kubectl -n wb-essais get pvc e06-essai
   e06-essai   Bound   pvc-1b2c…   1Gi   RWO   ceph-rbd
   admin@adm01:~$ kubectl -n wb-essais logs e06-essai
   /donnees/temoin: OK
   admin@adm01:~$ kubectl get pv pvc-1b2c… -o jsonpath='{.spec.csi.volumeAttributes.imageName}{"\n"}'
   csi-vol-8e1f…
   [admin@ceph01 ~]$ sudo rbd info k8s-rbd/csi-vol-8e1f… | grep -E 'size|features'
   	size 1 GiB in 256 objects
   	features: layering, exclusive-lock, object-map, fast-diff, deep-flatten
   [admin@ceph01 ~]$ sudo rbd du k8s-rbd/csi-vol-8e1f…          # ≈ 100 Mio utilisés + métadonnées ext4
   [admin@ceph01 ~]$ sudo rbd status k8s-rbd/csi-vol-8e1f…       # observateur : 10.10.30.8N
   admin@k8s-w02:~$ lsblk -o NAME,SIZE,MOUNTPOINTS /dev/rbd0
   rbd0   1G /var/lib/kubelet/pods/…/volumes/kubernetes.io~csi/pvc-1b2c…/mount
             /var/lib/kubelet/plugins/kubernetes.io/csi/rbd.csi.ceph.com/…/globalmount
   admin@k8s-w02:~$ ss -tn dst 10.10.30.0/24
   ESTAB 0 0 10.10.30.82:43210 10.10.30.51:3300     ← moniteur, msgr2
   ESTAB 0 0 10.10.30.82:51122 10.10.30.52:6804     ← OSD
   …
   ```
   Pas une connexion vers 6789. Le mode (`secure`) ne se lit pas avec `ss` : il est garanti par `ms_mode=secure` au mappage et par `ms_service_mode secure` côté Ceph (qui refuserait `crc`). Le fichier de 100 Mio et sa somme sont dans le volume.
10. ```
    admin@adm01:~$ kubectl cordon k8s-w02 && kubectl -n wb-essais delete pod e06-essai && kubectl apply -f ~/m16/e06/e06-essai.yaml
    admin@adm01:~$ kubectl -n wb-essais get pod e06-essai -o wide -w     # Running sur un autre nœud
    admin@adm01:~$ kubectl -n wb-essais logs e06-essai                   # /donnees/temoin: OK
    admin@adm01:~$ kubectl uncordon k8s-w02
    ```
    De 10 à 30 s environ : démontage et démappage sur l'ancien nœud, détachement, attachement, mappage et montage sur le nouveau. Le verrou exclusif passe d'un client à l'autre sans liste de blocage (l'ancien l'a rendu proprement).
11. ```
    admin@adm01:~$ sed 's/<NOEUD>/k8s-w02/' ~/m16/e06/e06-unique.yaml | kubectl apply -f -
    admin@adm01:~$ kubectl -n wb-essais describe pod e06-unique-b | tail -2
      Warning  FailedScheduling  …  0/6 nodes are available: 1 node has pod using PersistentVolumeClaim with the same name and ReadWriteOncePod access mode, …
    admin@adm01:~$ kubectl -n wb-essais delete pod e06-unique-a e06-unique-b ; kubectl -n wb-essais delete pvc e06-unique
    ```
    En RWO, le second pod aurait démarré sur le même nœud (E03, étape 5). RWOP est appliqué par le **planificateur** (et revérifié par le kubelet) : un seul pod, dans tout le cluster.
12. ```
    admin@adm01:~$ kubectl apply -f ~/m16/e06/e06-garde.yaml ; kubectl -n wb-essais wait --for=condition=Ready pod/e06-garde
    admin@adm01:~$ PV=$(kubectl -n wb-essais get pvc e06-garde -o jsonpath='{.spec.volumeName}') ; echo $PV
    admin@adm01:~$ kubectl delete -f ~/m16/e06/e06-garde.yaml
    admin@adm01:~$ kubectl get pv $PV                        # Released
    admin@adm01:~$ IMG=$(kubectl get pv $PV -o jsonpath='{.spec.csi.volumeAttributes.imageName}') ; echo $IMG
    [admin@ceph01 ~]$ sudo rbd info k8s-rbd/<IMG>            # l'image existe toujours
    admin@adm01:~$ kubectl get pv -o custom-columns=PV:.metadata.name,IMAGE:.spec.csi.volumeAttributes.imageName | grep <IMG>
    admin@adm01:~$ kubectl delete pv $PV
    [admin@ceph01 ~]$ sudo rbd rm k8s-rbd/<IMG>
    ```
    Avec `Retain`, ni le *provisioner* ni Kubernetes ne touchent à l'image : supprimer le PV ne supprime que l'objet. Le ménage est un geste d'administrateur, en deux temps, après vérification du nom (fiche, §6). Si `rbd rm` répond que l'image a des instantanés ou est encore ouverte (`rbd status`), on cherche pourquoi avant d'aller plus loin.
13. Fiche `ceph-csi.md` : modèle dans les fichiers. MR sur `plateforme/k8s` (relire le diff : `git diff --cached | grep -i -E 'userKey|AQ[A-Za-z0-9+/]{30}'` ne doit rien trouver), MR sur `plateforme/medisphere`.

**Explications**

ceph-csi en mode « Ceph externe » n'a besoin que de trois choses : savoir **où** est le cluster (`csiConfig` : fsid et moniteurs ; le `clusterID` relie chaque classe à son cluster), **qui** il est (le Secret référencé par la classe pour chaque type d'opération), et **quoi** créer (les paramètres de la classe). Tout le reste est générique. Le chemin des données passe par le **noyau** du nœud (krbd), pas par le pod : le *nodeplugin* ne fait que piloter le mappage et le montage, puis s'efface ; un redémarrage du *nodeplugin* n'interrompt pas les E/S des volumes montés. Le chemin de contrôle (création, suppression, clones) passe par les bibliothèques Ceph du *provisioner*, depuis un pod masqué derrière l'adresse `eth1` du nœud. Les Secrets ne sont qu'un relais : la référence est le Vault, la vérité est Ceph, et `verifier` contrôle que les trois concordent.

**Alternatives**
- **ceph-csi-operator** (celui qu'utilise Rook) : un opérateur qui gère les pilotes à partir de ressources `Driver`, `CephConnection`, `ClientProfile` ; recommandé par la documentation de ceph-csi pour les nouveaux déploiements. Écarté ici pour voir les pièces une par une ; à réévaluer dans l'ADR-0160 (E30).
- **Rook en mode externe** (`CephCluster` avec `external.enable: true`) : Rook gère ceph-csi et sa configuration à partir d'un cluster cephadm existant (script `create-external-cluster-resources.py`). Plus intégré, mais une couche de plus et des identités créées par le script, hors de `allocations.yaml`.
- **`rbd-nbd`** (mappage en espace utilisateur, `mounter: rbd-nbd`) : gère `journaling` et les dernières fonctionnalités, mais les E/S passent par un processus du *nodeplugin* : son redémarrage coupe les volumes. Réservé aux cas où krbd ne suffit pas.
- Secret créé par le chart depuis les values, values chiffrées (SOPS, M25) : possible, mais le secret vivrait dans Git, même chiffré, et chaque rotation serait une MR.

**Pièges classiques**
- Moniteurs en `:6789` dans `csiConfig` : l'outil `rbd` du *nodeplugin* lit une adresse en `:6789` comme une adresse **msgr1** ; avec `ms_mode=secure` (ou sans `ms_mode` : son défaut est `prefer-crc`, donc msgr2), il ne garde que les adresses msgr2 et n'en trouve aucune : `rbd: failed to get mon address (possible ms_mode mismatch)`, pod en `ContainerCreating`. Seul `ms_mode=legacy` mapperait, en msgr1, **en clair**.
- `userID: client.k8s` dans le Secret : authentification refusée (`client.client.k8s`).
- `journaling` dans `imageFeatures` : les images se créent, puis aucun pod ne démarre (`feature set mismatch`).
- Oublier les CRD de snapshots avant le pilote : *provisioner* en `CrashLoopBackOff` (conteneur `csi-snapshotter`).
- Deux classes marquées par défaut : l'API choisit la plus récente, sans prévenir ; la vérification exige qu'il n'y en ait qu'une.
- `rbd rm` sur l'image d'un PV encore `Bound` (copié-collé du mauvais nom) : données perdues, pod en erreur d'E/S.
- `kubectl apply` côté client d'un Secret : l'annotation `last-applied-configuration` en recopie le contenu.

**En production chez MédiSphère**
Pilotes et classes appliqués par GitOps (M20) ; Secrets alimentés par External Secrets depuis Vault/OpenBao (M25), rotation planifiée et vérifiée par `verifier` dans la CI ; identité `client.k8s` restreinte aux adresses des travailleurs (`network 10.10.30.80/29`, « pour aller plus loin » de E05) ; supervision des pilotes (métriques `csi_*`, opérations en échec) et des images orphelines (E27).

---

### M16-E07 — ceph-csi : des volumes partagés CephFS

**Solution**

Fichiers : [`allocations.yaml.extrait`](fichiers/M16-E07/ceph/allocations.yaml.extrait), [`ceph-allocations.sh.extrait`](fichiers/M16-E07/ceph/outils/ceph-allocations.sh.extrait), [`values-cephfs.yaml`](fichiers/M16-E07/k8s/composants/ceph-csi/values-cephfs.yaml), classe [`cephfs.yaml`](fichiers/M16-E07/k8s/composants/ceph-csi/classes/cephfs.yaml), [`secrets/ceph-csi.yml.exemple`](fichiers/M16-E07/k8s/secrets/ceph-csi.yml.exemple), essais [`e07-partage.yaml`](fichiers/M16-E07/essais/e07-partage.yaml), [`e07-rbd-rwx.yaml`](fichiers/M16-E07/essais/e07-rbd-rwx.yaml), section de la fiche [`ceph-csi.md.extrait`](fichiers/M16-E07/medisphere/docs/kubernetes/stockage/ceph-csi.md.extrait).

*A. Côté Ceph, par le code*

1. ```
   [admin@ceph01 ~]$ sudo ceph fs status cephfs | head -4
   [admin@ceph01 ~]$ sudo ceph fs subvolumegroup ls cephfs
   [{"name": "plateforme"}, {"name": "applications"}, {"name": "mediagenda"}, …]
   [admin@ceph01 ~]$ sudo ceph fs ls
   name: cephfs, metadata pool: cephfs.cephfs.meta, data pools: [cephfs.cephfs.data ]
   ```
   Droits de la documentation (CephFS) : `mon 'allow r fsname=cephfs'` (lire les cartes, limité à ce système de fichiers) ; `mgr 'allow rw'` (appeler le module `volumes` du gestionnaire, qui crée, agrandit, photographie et supprime les sous-volumes : c'est par lui que passe le *provisioner*) ; `osd 'allow rwx tag cephfs metadata=cephfs, allow rw tag cephfs data=cephfs'` (pools de métadonnées et de données du système de fichiers, désignés par leur étiquette d'application plutôt que par leur nom) ; `mds 'allow r fsname=cephfs path=/volumes, allow rws fsname=cephfs path=/volumes/csi'` (lire l'arborescence des volumes, écrire seulement sous le groupe `csi`, `s` pour manipuler les instantanés). `mgr 'allow rw'` est **large** : il ouvre tous les modules du gestionnaire qui acceptent des commandes en écriture, pas seulement `volumes`. C'est la principale raison d'une identité **séparée** : si `client.k8s` l'avait, la fuite de la clé RBD donnerait aussi la main sur le gestionnaire. (Restreindre à `mgr 'allow rw module=volumes'` est envisageable : ⚠️ non testé avec ceph-csi 3.18, qui appelle aussi d'autres commandes du gestionnaire.)
2. `allocations.yaml` : identité `client.k8s-cephfs` et section `groupes` ; `ceph-allocations.sh` : fonction `groupes()` (même style que `equipe()` : créer si absent, aligner le plafond sans jamais réduire, aucune suppression), appelée entre identités et équipes.
   ```
   admin@adm01:~/src/ceph$ CEPH_ADMIN=ceph01 outils/ceph-allocations.sh appliquer --simuler
   À FAIRE  identité client.k8s-cephfs absente
   À FAIRE  groupe de sous-volumes cephfs/csi absent
   …
   admin@adm01:~/src/ceph$ CEPH_ADMIN=ceph01 outils/ceph-allocations.sh appliquer && outils/ceph-allocations.sh verifier
   conforme à …/allocations.yaml
   [admin@ceph01 ~]$ sudo ceph fs subvolumegroup info cephfs csi | grep bytes_quota
       "bytes_quota": 21474836480,
   ```
   L'identité est créée avec le type de clé préféré du cluster, `aes` (M08-E27), sans afficher la clé (`-o /dev/null` dans l'outil).
3. Ajout au Vault en rechiffrant le fichier entier depuis un tube (commande complète dans le modèle `ceph-csi.yml.exemple`), puis :
   ```
   admin@adm01:~/src/k8s$ outils/ceph-csi-secrets.sh appliquer && outils/ceph-csi-secrets.sh verifier
   [OK] rbd : …
   [OK] cephfs : Secret ceph-csi/csi-cephfs-secret (userID=k8s-cephfs) à jour
   …
   [OK] cephfs : Vault identique à Ceph (client.k8s-cephfs)
   ```

*B. Le pilote CephFS*

4. Les deux charts créent par défaut `ceph-csi-config`, `ceph-config` et `ceph-csi-encryption-kms-config` : la seconde installation dans `ceph-csi` échouerait (`ConfigMap "ceph-csi-config" … exists and cannot be imported into the current release`). On renomme celles de CephFS (`configMapName`, `cephConfConfigMapName`, `kmsConfigMapName`) ; le chart utilise ces noms pour les créer **et** pour les monter. Le reste (DaemonSet, Deployment, comptes, rôles, Services de métriques) dérive du nom de la release. Les ports de métriques du *nodeplugin* (en `hostNetwork`) diffèrent déjà dans les deux charts (8080 pour RBD, 8081 pour CephFS) : pas de conflit de port sur l'hôte.
   ```
   admin@adm01:~/src/k8s$ composants/ceph-csi/installer.sh --rendu | grep -A2 '^kind: ConfigMap'
   ```
5. ```
   admin@adm01:~/src/k8s$ composants/ceph-csi/installer.sh
   → ceph-csi-rbd 3.18.1
   → ceph-csi-cephfs 3.18.1
   admin@adm01:~$ kubectl -n ceph-csi get cm
   ceph-config  ceph-config-cephfs  ceph-csi-config  ceph-csi-config-cephfs  ceph-csi-encryption-kms-config  ceph-csi-encryption-kms-config-cephfs  …
   admin@adm01:~$ kubectl get csidriver ; kubectl get csinode k8s-w01 -o jsonpath='{.spec.drivers[*].name}{"\n"}'
   cephfs.csi.ceph.com  rbd.csi.ceph.com
   rbd.csi.ceph.com cephfs.csi.ceph.com
   ```

*C. Un volume partagé*

6. ```
   admin@adm01:~$ kubectl apply -f ~/m16/e07/e07-partage.yaml
   admin@adm01:~$ kubectl -n wb-essais get pod -l app.kubernetes.io/name=e07-ecrivains -o wide     # deux nœuds
   admin@adm01:~$ kubectl -n wb-essais logs e07-lecteur --tail=6
   e07-ecrivains-7b9…-k2m4p 1791452010
   e07-ecrivains-7b9…-q8r1z 1791452011
   …
   [admin@ceph01 ~]$ sudo ceph fs subvolume ls cephfs --group_name csi
   [{"name": "csi-vol-2d4e…"}]
   [admin@ceph01 ~]$ sudo ceph fs subvolume info cephfs csi-vol-2d4e… --group_name csi | grep -E 'bytes_quota|path'
   admin@k8s-w01:~$ findmnt -t ceph -o SOURCE,TARGET,OPTIONS | head -2
   k8s-cephfs@<FSID>.cephfs=/volumes/csi/csi-vol-2d4e…/… /var/lib/kubelet/plugins/kubernetes.io/csi/cephfs.csi.ceph.com/…/globalmount rw,…,name=k8s-cephfs,ms_mode=secure,…
   ```
   Les deux écrivains alternent dans le même fichier : un vrai système de fichiers partagé, cohérent entre nœuds (le MDS distribue les *capabilities*).
7. ```
   admin@adm01:~$ P=$(kubectl -n wb-essais get pod -l app.kubernetes.io/name=e07-ecrivains -o name | head -1)
   admin@adm01:~$ kubectl -n wb-essais exec $P -- df -h /partage
   …   1.0G   …   /partage
   admin@adm01:~$ kubectl -n wb-essais exec $P -- dd if=/dev/zero of=/partage/gros bs=1M count=1536
   dd: error writing '/partage/gros': Disk quota exceeded
   admin@adm01:~$ kubectl -n wb-essais exec $P -- rm /partage/gros
   ```
   La limite est le **quota CephFS** du sous-volume (`ceph.quota.max_bytes` = taille du PVC), appliqué par le client noyau ; `df` le montre comme taille du système de fichiers. L'erreur arrive à 1 Gio environ (le client peut dépasser de quelques Mio avant d'apprendre l'occupation exacte du MDS).
8. ```
   admin@adm01:~$ kubectl apply -f ~/m16/e07/e07-rbd-rwx.yaml
   admin@adm01:~$ kubectl -n wb-essais describe pvc e07-rbd-rwx | tail -2
     Warning  ProvisioningFailed  …  failed to provision volume with StorageClass "ceph-rbd": rpc error: code = InvalidArgument desc = multi node access modes are only supported on rbd `block` type volumes
   admin@adm01:~$ kubectl delete -f ~/m16/e07/e07-rbd-rwx.yaml
   ```
   Deux noyaux qui montent le même ext4 le corrompent : ceph-csi refuse RWX en mode `Filesystem`. En mode `Block`, il l'accepte (l'application reçoit un disque partagé et doit savoir le partager : système de fichiers en grappe, migration de VM).
9. Section de la fiche : voir l'extrait.

**Explications**

Pour CephFS, ceph-csi ne crée pas d'image : il demande au module `volumes` du gestionnaire un **sous-volume** (un répertoire isolé avec quota, sous `/volumes/csi/`), puis le nœud le monte avec le client noyau, sous l'identité `k8s-cephfs`. Le groupe `csi` est la frontière : tout ce que Kubernetes crée y est, son plafond borne la somme, et les droits MDS de l'identité ne vont pas au-delà. L'outil d'allocations du M08 gardait les groupes **d'équipes** ; il gagne la notion de groupe **de consommateur**, dont le contenu est géré par le consommateur lui-même : c'est la même discipline (tout est décrit et vérifié), appliquée à un client qui crée ses propres sous-volumes.

**Alternatives**
- `client.k8s` étendu aux droits CephFS (une seule identité, un seul Secret) : plus simple, mais une fuite donne alors les deux, et le droit mgr large s'ajoute à l'identité RBD. Écarté.
- Volume CephFS **dédié** à Kubernetes (`ceph fs volume create k8s`) : isolement complet (MDS, pools), au prix d'un MDS de plus à faire tourner sur des nœuds à 6 Go ; envisageable en production.
- Pilote NFS de ceph-csi (`nfs.csi.ceph.com`, par NFS-Ganesha de Ceph) : des clients qui ne parlent pas Ceph, mais une passerelle de plus sur le chemin.
- Stockage objet (RGW) pour les pièces jointes : la vraie cible pour Legacy-RDV et MédiDoc (E46).

**Pièges classiques**
- Installer le second chart sans renommer ses ConfigMaps : échec de la release, ou pire, avec `--force-replace`, une ConfigMap de RBD réécrite par CephFS (le pilote RBD perd ses moniteurs).
- Oublier de créer le groupe `csi` : `CreateVolume` échoue (`subvolume group 'csi' does not exist`) ; le pilote ne le crée pas.
- `mounter` laissé vide : le pilote choisit selon ce qu'il trouve ; un montage `ceph-fuse` ignore `kernelMountOptions`, et passe par un processus du *nodeplugin* (coupé à son redémarrage).
- Croire qu'un PVC `cephfs` de 1 Gio « réserve » 1 Gio : c'est un plafond, l'espace n'est consommé qu'à l'écriture ; c'est le plafond du groupe qui protège le cluster.
- Utiliser `cephfs` pour une base de données « pour pouvoir la déplacer » : RBD se déplace aussi, et une base sur un système de fichiers réseau partagé paie chaque `fsync` au MDS.

**En production chez MédiSphère**
CephFS réservé aux cas de partage justifiés (liste dans la fiche, revue à chaque demande de classe), plafond du groupe suivi (alerte à 80 %), instantanés de sous-volumes par `cephfs-snap` (E10) et sauvegarde par Velero (E17) ; à terme, migration des pièces jointes vers RGW.

---

### M16-E08 — StatefulSet et volumes par instance

**Solution**

Fichiers : [`e08-valkey.yaml`](fichiers/M16-E08/essais/e08-valkey.yaml) (état final), [`k8s/recette/30-valkey.yaml`](fichiers/M16-E08/mediagenda-api/k8s/recette/30-valkey.yaml) (projet `mediagenda/api`).

*A. Le patron, dans `wb-essais`*

1. Avec `replicas: 3` et sans politique de rétention :
   ```
   admin@adm01:~$ kubectl apply -f ~/m16/e08/e08-valkey.yaml ; kubectl -n wb-essais get pod,pvc -l app.kubernetes.io/name=e08-valkey -w
   pod/e08-valkey-0  0/1 Pending → ContainerCreating → Running 1/1
   pvc/donnees-e08-valkey-0  Bound  pvc-…  1Gi  RWO  ceph-rbd
   pod/e08-valkey-1  … (seulement quand e08-valkey-0 est prêt)
   …
   admin@adm01:~$ kubectl -n wb-essais run e08-dns --rm -it --restart=Never --image=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37 -- nslookup e08-valkey-1.e08-valkey.wb-essais.svc.cluster.local
   ```
   Ordre strict (`OrderedReady`) : un pod ne naît que lorsque le précédent est **prêt** ; PVC `donnees-e08-valkey-N` ; noms `e08-valkey-N.e08-valkey.wb-essais.svc.cluster.local`.
2. ```
   admin@adm01:~$ kubectl -n wb-essais exec e08-valkey-1 -- valkey-cli SET essai "$(date)"
   admin@adm01:~$ kubectl get volumeattachment -w &                     # suivi
   admin@adm01:~$ kubectl -n wb-essais delete pod e08-valkey-1
   admin@adm01:~$ kubectl -n wb-essais get pod e08-valkey-1 -o wide      # même nom, nœud quelconque
   admin@adm01:~$ kubectl -n wb-essais exec e08-valkey-1 -- valkey-cli GET essai
   "Thu Oct  8 10:12:41 UTC 2026"
   ```
   Le pod recréé porte le **même nom** et remonte le **même** PVC ; s'il change de nœud, le `VolumeAttachment` est supprimé puis recréé pour le nouveau. La clé est revenue depuis le fichier AOF (`/data/appendonlydir/`).
3. `kubectl -n wb-essais scale sts e08-valkey --replicas=1` : les pods 2 puis 1 s'arrêtent (ordre inverse), les PVC `-1` et `-2` **restent** `Bound` (défaut `Retain`). `--replicas=3` : les pods reviennent sur leurs PVC, les données avec.
4. ```
   admin@adm01:~$ kubectl -n wb-essais patch sts e08-valkey --type merge \
       -p '{"spec":{"persistentVolumeClaimRetentionPolicy":{"whenScaled":"Delete","whenDeleted":"Retain"}}}'
   admin@adm01:~$ IMG=$(kubectl get pv $(kubectl -n wb-essais get pvc donnees-e08-valkey-2 -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.csi.volumeAttributes.imageName}')
   admin@adm01:~$ kubectl -n wb-essais scale sts e08-valkey --replicas=2
   admin@adm01:~$ kubectl -n wb-essais get pvc | grep e08            # -0 et -1 seulement
   [admin@ceph01 ~]$ sudo rbd info k8s-rbd/<IMG>                       # « No such file or directory » (classe Delete)
   ```
   Le contrôleur pose une référence de propriété sur le PVC de l'instance retirée et le ramasse-miettes le supprime ; la classe `Delete` emporte le PV et l'image. Quand utiliser quoi : **cache** jetable → `Delete`/`Delete` (rien à garder, pas de ménage) ; **base répliquée** (chaque instance peut être reconstruite depuis les autres) → `whenScaled: Delete` pour ne pas laisser de vieux réplicas, `whenDeleted: Retain` contre la suppression accidentelle ; **base unique** ou données sans autre copie → `Retain`/`Retain` (le défaut), et le ménage reste une décision humaine. (Le fichier du corrigé est l'état final de cette étape.)
5. Si le nœud de `e08-valkey-0` ne répond plus : le nœud passe `NotReady` (une quarantaine de secondes), son *taint* `unreachable` fait évincer ses pods au bout de 300 s ; le pod est marqué pour suppression mais l'objet **reste** (le kubelet n'est pas là pour confirmer l'arrêt), et le contrôleur du StatefulSet ne crée **pas** de second `e08-valkey-0` : garantie « au plus un ». Le `VolumeAttachment` reste lui aussi. Pour lever le doute, quand on **sait** que le nœud est éteint : *taint* `node.kubernetes.io/out-of-service=nodeshutdown:NoExecute` (arrêt non gracieux, stable depuis Kubernetes 1.28) : les pods du nœud sont supprimés de force, les volumes détachés sans attendre le démontage, et le pod repart ailleurs. Le risque si le nœud est en réalité vivant mais isolé : deux écrivains sur la même image ; le verrou exclusif de RBD et la liste de blocage limitent les dégâts (l'ancien client ne peut plus écrire une fois bloqué), mais un système de fichiers déjà monté des deux côtés peut être corrompu avant. D'où : ne jamais forcer sans avoir constaté l'arrêt (console Proxmox, `qm status`). Pratique : E37.

*B. Le Valkey de recette*

6. ```
   admin@adm01:~$ kubectl -n mediagenda-recette get deploy,sts,svc,netpol,pvc -o wide
   admin@adm01:~$ kubectl -n mediagenda-recette get configmap mediagenda-api-config -o jsonpath='{.data.MEDIAGENDA_VALKEY_URL}{"\n"}'
   redis://valkey-0.valkey:6379/0
   admin@adm01:~$ kubectl -n mediagenda-recette get svc valkey -o jsonpath='{.spec.clusterIP} {.spec.selector}{"\n"}'
   None {"app.kubernetes.io/name":"valkey"}
   admin@adm01:~$ kubectl -n mediagenda-recette get netpol -o yaml | grep -B2 -A6 valkey
   ```
   L'existant est le StatefulSet `valkey` du M14 (trois pods `valkey-0..2`, `emptyDir`) derrière le Service sans tête `valkey` ; l'API ne parle qu'au primaire, `valkey-0.valkey`. Note les étiquettes que sélectionnent le Service et les politiques (`app.kubernetes.io/name: valkey` dans le corrigé du M14) : le nouveau Valkey doit les porter, et garder le même nom et le même `serviceName` pour que l'URL reste valable.
7. Le StatefulSet : image du cache Harbor épinglée (VAP du M14), `restricted` (999, `fsGroup` 999 avec `OnRootMismatch`, capacités retirées, `seccompProfile`, système de fichiers racine en lecture seule), AOF chaque seconde, mémoire plafonnée avec éviction LRU, `Retain`/`Retain`, une instance, Service sans tête `valkey` inchangé (le fichier le décrit encore, tel quel).
   ```
   admin@adm01:~/src/mediagenda-api$ kubectl apply --dry-run=server -f k8s/recette/30-valkey.yaml
   service/valkey unchanged (server dry run)
   The StatefulSet "valkey" is invalid: spec: Forbidden: updates to statefulset spec for fields other than 'replicas', 'ordinals', 'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and 'minReadySeconds' are forbidden
   ```
   Le refus est attendu : il confirme que `volumeClaimTemplates` ne s'ajoute pas en place (étape 8). Pour valider Pod Security et la VAP sans ce conflit, essaie le même StatefulSet sous un autre nom : `yq '(select(.kind == "StatefulSet") | .metadata.name) = "valkey-essai"' k8s/recette/30-valkey.yaml | kubectl apply --dry-run=server -f -` : aucun avertissement de Pod Security, aucun refus de la VAP (message du refus ci-dessus représentatif).
8. Bascule. `volumeClaimTemplates` (comme `serviceName` et le sélecteur) est un champ **immuable** : on ne l'ajoute pas au StatefulSet du M14. On supprime donc l'**objet** StatefulSet sans ses pods, puis on applique le nouveau, qui adopte les pods existants (même nom, mêmes étiquettes) :
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette delete sts valkey --cascade=orphan     # les pods valkey-0..2 continuent de servir
   admin@adm01:~/src/mediagenda-api$ kubectl apply -f k8s/recette/30-valkey.yaml
   admin@adm01:~$ kubectl -n mediagenda-recette get pod,pvc -l app.kubernetes.io/name=valkey -w
   pod/valkey-2  Terminating                    ← ordinaux au-delà de replicas: 1, retirés un par un
   pod/valkey-1  Terminating
   pvc/donnees-valkey-0  Bound  …  1Gi  RWO  ceph-rbd
   pod/valkey-0  Terminating → Pending → ContainerCreating → Running 1/1   ← nouvelle révision, avec son PVC
   admin@adm01:~$ kubectl -n mediagenda-recette rollout status sts/valkey
   admin@adm01:~$ for i in $(seq 1 30); do curl -s -o /dev/null -w '%{http_code} ' https://mediagenda-recette.apps.par1.medisphere.internal/pret; sleep 1; done; echo
   200 200 503 503 503 200 200 …
   admin@adm01:~$ curl -s "https://mediagenda-recette.apps.par1.medisphere.internal/api/v1/creneaux?date=2026-10-09" >/dev/null
   admin@adm01:~$ kubectl -n mediagenda-recette exec valkey-0 -- valkey-cli DBSIZE
   (integer) 1
   ```
   Le contrôleur adopte les trois pods orphelins, retire `valkey-2` puis `valkey-1` (au-delà de `replicas`), puis remplace `valkey-0`, dont la révision n'est plus la bonne, par un pod qui monte `donnees-valkey-0`. Si `valkey-0` n'est pas remplacé de lui-même (stratégie `OnDelete` restée sur l'ancien objet, par exemple), supprime-le : `kubectl -n mediagenda-recette delete pod valkey-0`. `/pret` répond 503 pendant les quelques secondes où `valkey-0` est absent (provisionnement, attachement et montage du volume, démarrage), ce que le ticket accepte ; le cache repart vide une dernière fois. ⚠️ Sans `--cascade=orphan`, la suppression emporte les trois pods d'un coup et la coupure dure jusqu'à l'application du nouveau fichier.
9. ```
   admin@adm01:~$ kubectl -n mediagenda-recette exec valkey-0 -- valkey-cli DBSIZE                # avant
   admin@adm01:~$ N=$(kubectl -n mediagenda-recette get pod valkey-0 -o jsonpath='{.spec.nodeName}')
   admin@adm01:~$ kubectl drain $N --ignore-daemonsets --delete-emptydir-data
   admin@adm01:~$ kubectl -n mediagenda-recette get pod valkey-0 -o wide -w                      # ailleurs, Running
   admin@adm01:~$ kubectl -n mediagenda-recette exec valkey-0 -- valkey-cli DBSIZE                # même nombre (hors expirations)
   admin@adm01:~$ kubectl uncordon $N
   ```
   Le cache est revenu avec son volume : plus de démarrage à froid. Les clés expirées entre-temps (TTL 60 s des créneaux) ont disparu, c'est normal. MR des manifestes.

**Explications**

Le StatefulSet ne fait rien de magique pour les données : il fabrique un PVC par identité à partir du modèle, et garantit qu'une identité n'existe qu'une fois. La persistance vient de la classe (`ceph-rbd`) ; la **survie au déplacement** vient de ce que le volume est un objet du cluster, pas du nœud. `fsGroup` est indispensable dès qu'on refuse root : un ext4 neuf a une racine `root:root 0755`, et l'image Valkey, lancée directement en 999, saute l'étape où elle corrigeait les droits ; le kubelet le fait à sa place parce que le `CSIDriver` annonce `fsGroupPolicy: File`. `OnRootMismatch` évite de reparcourir tout le volume à chaque montage.

**Alternatives**
- Garder les trois instances du M14 en leur donnant chacune un volume (`donnees-valkey-0..2`) : trois fois les volumes pour des répliques qui, sans Sentinel, ne prennent jamais le relais ; c'est la réplication **avec** bascule (Sentinel ou un opérateur, M27) qui rendra des répliques utiles, avec ou sans disque.
- Persistance RDB seule (instantanés périodiques) : moins d'écritures que l'AOF, mais une perte jusqu'au dernier instantané ; pour un cache, suffisant.
- `ReadWriteOncePod` dans le modèle de volume : garantie supplémentaire contre deux pods du même nœud ; redondant avec la garantie du StatefulSet, mais gratuit.
- `podManagementPolicy: Parallel` : création et suppression simultanées ; utile quand les instances sont indépendantes (pas d'ordre de démarrage), comme ici dans `wb-essais`.

**Pièges classiques**
- Renommer le StatefulSet ou changer son `serviceName` « pour repartir propre » : le nom `valkey-0.valkey` que vise l'API ne résout plus, `/pret` reste à 503 jusqu'à la correction de la ConfigMap et le redémarrage de l'API.
- Étiquettes du nouveau Valkey différentes de l'ancien : le Service ne le trouve pas, les politiques réseau du M15 le bloquent, `/pret` reste à 503.
- Oublier `fsGroup` en `restricted` : Valkey démarre, ne peut pas écrire son AOF (`Permission denied`), et redémarre en boucle.
- `whenScaled: Delete` sur une base unique : un `scale` à 0 « pour la maintenance » détruit les données.
- Forcer la suppression d'un pod de StatefulSet sur un nœud injoignable sans avoir vérifié que le nœud est éteint.

**En production chez MédiSphère**
Valkey de production en réplication avec Sentinel (M27), persistance AOF sur `ceph-rbd`, `PodDisruptionBudget` (une instance au plus en maintenance), anti-affinité par baie (`topology.kubernetes.io/zone`, M14-E14), et une alerte sur le taux de défauts de cache (`mediagenda_cache_total{resultat="defaut"}`, M21). Le même patron (StatefulSet, modèle de volume, `fsGroup`, Retain) sert de base de comparaison pour PostgreSQL, que CloudNativePG gère toutefois sans StatefulSet (E18).

---

### M16-E09 — Questions : stockage et CSI

**Barème** : 2 points par question, total sur 24. Une réponse qui cite une observation du lab (sortie, mesure, message) vaut mieux qu'une réponse de cours.

**1. Chemin d'une écriture.** Le processus écrit dans `/donnees` : le noyau la place dans le **cache de pages** d'ext4 (montage lié du pod → `globalmount` → `/dev/rbd0`). Au vidage (ou au `fsync`), ext4 envoie des requêtes bloc à `/dev/rbd0` ; le pilote **krbd** découpe en objets de 4 Mio (`rbd_data.<id>.<numéro>`), calcule le PG et l'OSD primaire par CRUSH (cartes obtenues des moniteurs au mappage), et envoie l'écriture **directement au primaire**, depuis `eth1` (10.10.30.8N), sur le VLAN 30, en msgr2 **chiffré** (`ms_mode=secure`). Le primaire écrit (BlueStore) et réplique vers deux secondaires sur le réseau **cluster** (VLAN 31) ; quand les trois ont rendu l'écriture persistante, il acquitte krbd, qui acquitte ext4. Ni Kubernetes, ni le *nodeplugin*, ni les moniteurs ne sont sur ce chemin (observé : `ss -tn` montre des connexions vers les OSD 68xx, et un redémarrage du *nodeplugin* n'interrompt pas l'écriture). Avec `exclusive-lock` et `object-map`, la première écriture d'un objet met aussi à jour l'index d'occupation.

**2. Réponse B.** Les paramètres d'une StorageClass ne servent qu'à **créer** les volumes ; ce qui en reste est recopié dans le PV (`volumeAttributes`). Une image déjà créée garde ses fonctionnalités (on les modifie à la main, avec `rbd feature enable/disable`, quand c'est possible). A : le montage ne relit pas la classe. C : aucun pilote ne recrée un volume existant. D : la phase d'un PV ne dépend que de son PVC. D'ailleurs, une StorageClass ne se modifie pas : `kubectl apply` refuse le changement des paramètres (champ immuable), d'où le `delete` puis `apply` de l'énoncé.

**3. Permissions du *nodeplugin*.** `privileged` : mapper un périphérique (`/sys/bus/rbd`, `/dev`), charger des modules, monter des systèmes de fichiers ; sans lui, ni mappage ni montage. `hostNetwork` : le client noyau (krbd, CephFS) parle à Ceph depuis l'espace réseau de **l'hôte** (c'est lui qui a la carte `eth1`) ; sans, il faudrait faire exécuter le mappage dans un autre espace réseau (`netNamespaceFilePath` de `csiConfig`), plus complexe. `mountPropagation: Bidirectional` : les montages faits dans le conteneur remontent vers l'hôte, où le kubelet et le pod du client les voient ; sans, le volume ne serait monté que dans le conteneur du pilote et le pod verrait un répertoire vide. (Et `hostPID` : retrouver les processus de l'hôte, utile au pilote pour certaines opérations de montage.)

**4. Réseau du *provisioner*.** Ses requêtes (librados : création, suppression, clones) partent de l'adresse du **pod** (10.240.x.y), quittent le pod par l'interface de Cilium, sont remises à la pile de l'hôte, routées par `eth1` (route connectée 10.10.30.0/24) et **masquées** par l'adresse 10.10.30.8N : `ceph01-03` répondent au nœud, dans le VLAN 30 (observé en E05, étape 7, `tcpdump` sur `eth1`). Si le masquage cessait (par exemple, masquage BPF qui ne gère pas `eth1`), les paquets partiraient avec l'adresse du pod, les moniteurs répondraient par leur passerelle `gw01`, qui ne connaît pas 10.240.0.0/16 : plus aucune création ni suppression de volume (PVC `Pending`), alors que les volumes déjà montés continueraient de fonctionner (le *nodeplugin* est en `hostNetwork`). Panne type de M16-E35/E36.

**5. 3300 et `ms_mode=secure`.** `ms_service_mode secure` côté `ceph-par1` ne s'applique qu'à **msgr2** : un client en msgr1 (port 6789, protocole sans mode `secure`) passe **en clair** (M08-E27, Q expert). Lister les moniteurs en `:3300` seulement et imposer `ms_mode=secure` au mappage et au montage garantit que le noyau n'emprunte jamais msgr1, même si les moniteurs l'annoncent encore. Avec `10.10.30.51:6789` dans la configuration et `ms_mode=secure`, l'outil `rbd` (qui prépare le mappage pour le noyau) classe cette adresse en msgr1, ne garde que les adresses msgr2 et n'en a plus aucune : échec du mappage (`rbd: failed to get mon address (possible ms_mode mismatch)`, pod en `ContainerCreating`). Le défaut de `rbd` sans `ms_mode` est `prefer-crc` (msgr2) : même échec. Seul `ms_mode=legacy` (ou un client ancien) mapperait en msgr1, et tout « marcherait », en clair. Pour CephFS, c'est le noyau qui reçoit directement l'option : son défaut, à lui, est `legacy` (msgr1), d'où `ms_mode=secure` obligatoire dans `kernelMountOptions` avec des moniteurs en `:3300`.

**6. Réponse B.** Le mappage RBD et le montage CephFS sont faits par le **noyau** des travailleurs, qui s'authentifie lui-même auprès des moniteurs avec la clé transmise ; Linux 6.12 ne connaît pas le type `aes256k` (introduit par Ceph 20.2.4 contre CVE-2025-30156 ; le client noyau ne l'apprend qu'à partir de Linux 7.0 d'après l'avis, M08-E27). La documentation de ceph-csi crée d'ailleurs ses identités avec `--key-type=aes`. A est faux (les bibliothèques du conteneur le connaîtraient peut-être, mais elles ne mappent pas). C : `aes256k` est justement fait pour tous, démons et clients. D : la taille d'un Secret n'a rien à voir.

**7. Modes d'accès.** RWO : en E03, deux pods du **même nœud** montent le volume local ; c'est l'attachement (un nœud) qui est exclusif : appliqué par le planificateur pour les volumes à topologie, par l'attacheur et le kubelet (erreur `Multi-Attach`) pour les autres, et, pour RBD, renforcé par le verrou exclusif de Ceph. RWOP : en E06, le second pod reste `Pending` même sur le même nœud : appliqué par le **planificateur** (et revérifié par le kubelet), pilotes CSI seulement. RWX : en E07, deux pods sur deux nœuds écrivent le même fichier ; appliqué par… personne côté Kubernetes : c'est le **pilote** qui accepte (CephFS) ou refuse (RBD en mode fichier, `InvalidArgument`) de créer un tel volume, et le système de fichiers partagé qui assure la cohérence.

**8. `Retain`.** Il protège contre la **suppression du PVC** (erreur de manipulation, `helm uninstall`, suppression de l'espace de noms) : le PV passe `Released`, l'image reste. Il ne protège **pas** : contre une erreur **dans** le volume (fichiers effacés, base corrompue, rançongiciel), qui atteint l'image vivante ; contre la perte du pool ou du cluster ; contre un administrateur qui supprime le PV **et** l'image (`rbd rm`) ou le pool ; ni contre l'oubli (un PV `Released` sans propriétaire finit supprimé « pour faire de la place »). Il faut des **sauvegardes** hors cluster (Velero, E16-E17) et des instantanés (E10).

**9. `discard` et quota.** `discard` fait envoyer par ext4 une commande d'effacement (TRIM) pour chaque bloc libéré ; krbd la traduit en suppression ou en mise à zéro d'objets RADOS : l'espace revient au pool. Sans elle, les fichiers supprimés continuent d'occuper le pool (l'image ne fait que grossir jusqu'à sa taille nominale). `rbd du` montre, par image, la taille provisionnée et l'espace **utilisé** (rapide grâce à `fast-diff`) ; `ceph df` montre, par pool, les octets **stockés** (avant réplication) et l'espace brut consommé (×3), et le quota (`MAX AVAIL` borné par lui). Le jour où `k8s-rbd` atteint 20 Gio stockés : `POOL_FULL`, écritures refusées par les OSD ; les pods voient leurs écritures **bloquées** (état `D`), sans erreur, jusqu'à ce qu'on lève le quota ou libère de l'espace — sauf `abort_on_full` au mappage (`ENOSPC`). Panne M16-E38.

**10. `fsGroup`.** Au premier montage, le kubelet a parcouru le volume (vide, donc instantané) et donné le groupe 999 aux fichiers et répertoires, avec le bit *setgid* sur les répertoires (les fichiers créés ensuite héritent du groupe) et l'écriture pour le groupe : Valkey, qui tourne en 999 sans être root, peut écrire `/data`. Sans `OnRootMismatch` (politique `Always`), il le refait **à chaque montage** : sur un volume de plusieurs centaines de Gio et des millions de fichiers, cela retarde le démarrage du pod de plusieurs minutes (le pod reste en `ContainerCreating`) ; `OnRootMismatch` ne le refait que si la racine n'a pas déjà les bons droits.

**11. Persister un cache.** Pour : un cache vide après chaque drain reporte **toute** la charge sur PostgreSQL au pire moment (pendant une maintenance, quand une partie du cluster est déjà indisponible) et dégrade les temps de réponse (constaté par Julien) ; le coût est faible (1 Gio sur `ceph-rbd`, une écriture AOF par seconde) ; et c'est l'occasion d'apprendre le patron StatefulSet sur un composant simple avant PostgreSQL. Contre : un cache doit pouvoir être perdu à tout moment ; le persister masque un défaut de conception (une application qui ne supporte pas un cache froid) et ajoute une dépendance à Ceph pour un composant qui n'en avait pas besoin (un Ceph lent ralentit le cache). La rendraient inutile : la réplication **avec bascule** de Valkey (Sentinel ou opérateur, M27 ; les répliques sans bascule du M14 ne protégeaient pas du drain du nœud de `valkey-0`), ou une application qui « réchauffe » son cache progressivement et une base dimensionnée pour le cache froid.

**12. Réponse B.** Le pod est marqué pour suppression (éviction après la tolérance de 300 s), mais l'objet reste lié au nœud injoignable, et le contrôleur du StatefulSet ne crée pas de nouveau `valkey-0` tant que l'ancien n'a pas disparu : il ne peut pas savoir si le nœud est arrêté ou seulement isolé et encore en train d'écrire. A est le comportement souhaité… après l'arrêt non gracieux (*taint* `out-of-service`) ou une suppression forcée, sur décision humaine. C : un StatefulSet ne compense jamais par une autre identité. D : rien ne supprime un PVC dans ce cas (et la politique `Retain` l'interdirait de toute façon).
