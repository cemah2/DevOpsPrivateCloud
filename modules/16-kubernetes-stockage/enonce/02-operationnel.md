# Module 16 — Palier 2 : Opérationnel

Le palier 1 a raccordé `k8s-par1` à `ceph-par1` : les travailleurs joignent le VLAN 30, ceph-csi provisionne des volumes RBD (`ceph-rbd`, `ceph-rbd-retain`) et CephFS (`cephfs`), Valkey tourne en StatefulSet sur un vrai volume. Ce palier traite les tickets du quotidien d'une équipe qui exploite des **données** dans Kubernetes : photographier, cloner, agrandir un volume ; choisir la bonne classe ; comparer honnêtement deux autres façons de faire du stockage dans le cluster (Rook, Longhorn) et les **retirer proprement** ; sauvegarder et restaurer des espaces de noms et leurs volumes hors du cluster (Velero) ; installer la base PostgreSQL de MédiAgenda avec un opérateur (CloudNativePG), avec archivage continu et restauration à un instant donné ; poser des garde-fous par équipe. Tu termines en relisant le travail de Lucas, en écrivant le runbook « PVC Pending » et en mettant tout le stockage du cluster sous forme de code.

> **Rappels du module** (introduction) : toute VM ou tout disque passe par OpenTofu (état `k8s` de `plateforme/infra`, module `vm-noeud`), toute configuration de nœud par Ansible (`plateforme/ansible`), tout objet Kubernetes durable par une MR sur `plateforme/k8s` (clone `~/src/k8s` sur `adm01`) puis `task appliquer` ; la documentation va dans `plateforme/medisphere` (`docs/kubernetes/stockage/`). Helm sert ici d'**installateur** : les commandes sont données, le packaging est enseigné au module 17. Les essais se font dans `wb-essais` ; les brouillons et le journal de chaque exercice dans `~/m16/eXX/` sur `adm01`. Aucun secret dans un dépôt : fichiers 600 de `~/.config/workbook/`, Ansible Vault (`lab`, `critique`), Secrets Kubernetes créés par script.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Cluster | `k8s-par1` (Kubernetes 1.36), commandes depuis `adm01` avec ton kubeconfig personnel (`admin@adm01:~$ kubectl …`) ; nœuds en SSH (`admin@k8s-w01:~$`, `sudo`) |
| Pilotes CSI du palier 1 | `rbd.csi.ceph.com` et `cephfs.csi.ceph.com` (ceph-csi 3.18, espace `ceph-csi`, *releases* `ceph-csi-rbd` et `ceph-csi-cephfs` installées par `composants/ceph-csi/installer.sh`, qui applique aussi `composants/ceph-csi/classes/`) ; Secrets `csi-rbd-secret` et `csi-cephfs-secret` dans `ceph-csi` (créés par `outils/ceph-csi-secrets.sh`) ; `clusterID` = fsid de `ceph-par1` ; nœuds raccordés étiquetés `medisphere.fr/stockage-ceph=oui` |
| Classes | `ceph-rbd` (par défaut), `ceph-rbd-retain`, `cephfs` (palier 1) ; ce palier ajoute temporairement `rook-ceph-block` (E13-E14) et `longhorn` (E15), puis les retire |
| Snapshots | external-snapshotter **8.6** (CRD `snapshot.storage.k8s.io/v1`, `snapshot-controller` dans `kube-system`), installé en E06 (`composants/snapshot-controller/`) ; classes d'instantanés `ceph-rbd-snap` et `cephfs-snap` (E10) |
| Disques de comparaison | par travailleur : `scsi1` 32 Go sur `ssd-lab`, série `k8s-w0N-rook` (Rook, E13) ; `scsi2` 32 Go sur `hdd-bulk`, série `k8s-w0N-lh` (Longhorn, E15). Retirés par OpenTofu au mini-projet |
| Rook (E13-E14) | 1.21.0, charts `rook-release/rook-ceph` et `rook-release/rook-ceph-cluster`, espace `rook-ceph` (temporaire) |
| Longhorn (E15) | 1.13.0, chart `longhorn/longhorn`, espace `longhorn-system` (temporaire), données sous `/var/lib/longhorn` |
| S3 du socle | `https://s3-01.par1.medisphere.internal:8333` (SeaweedFS, rôle `seaweedfs`, M05) ; identités et compartiments ajoutés : `velero` → `velero-k8s-par1` (E16), `cnpg` → `cnpg-k8s-par1` (E18), `longhorn-essai` → `longhorn-essai` (E15, supprimés en fin d'exercice) ; clés dans `~/.config/workbook/s3-<identité>.env` (600) et le Vault `lab` |
| Velero (E16-E17) | 1.18.4 (chart `vmware-tanzu/velero` 12.2.1), plugin AWS 1.14.4, espace `velero`, emplacement de sauvegarde (BSL) `s3-01` ; CLI `velero` 1.18.4 sur `adm01` |
| CloudNativePG (E18-E19) | opérateur 1.30.1 (chart `cnpg/cloudnative-pg` 0.29.1) et plugin Barman Cloud 0.15.1 (chart `cnpg/plugin-barman-cloud` 0.8.1), espace `cnpg-system` ; cluster `mediagenda-db` (espace `mediagenda-recette`), `ObjectStore` `cnpg-s3` ; plugin `kubectl cnpg` par krew |
| Images | toutes par Harbor : dans `mediagenda-*`, la politique d'admission du M14 exige le préfixe `registry.par1.medisphere.internal/` ; le cache `ghcr` s'écrit `registry.par1.medisphere.internal/ghcr/<chemin>` |
| Vérifications | compte `wb-checks` (lecture, sans Secrets) ; ce palier lui ajoute la lecture des ressources de stockage (E10) |

Durée indicative du palier : 32 à 40 heures. Ordre conseillé :

```
E10 ─ E11 ─ E12
E13 ─ E14 ─ E15          (les disques de comparaison ; Rook est démonté avant Longhorn)
E10 ─ E16 ─ E17          (Velero a besoin des classes de snapshots)
E18 ─ E19 ─ E20
E21, E22 (quand tu veux, après E19)
E23 (en dernier : il reprend tout)
```

---

### M16-E10 — Snapshots et clones de volumes  `LAB` `★★`

> **Ticket DEV-1710** — *De : Julien Petit*
> Avant chaque migration de schéma en recette, je veux pouvoir « prendre une photo » du volume et y revenir en deux minutes si la migration tourne mal. Et j'aimerais une copie de la base de recette pour tester une migration lourde sans toucher à l'originale. Sur l'ancienne plateforme, InfoGér mettait une demi-journée à faire ça.

**Objectifs pédagogiques**
- Comprendre l'API des instantanés de Kubernetes (`VolumeSnapshotClass`, `VolumeSnapshot`, `VolumeSnapshotContent`) et le rôle du `snapshot-controller` et du *sidecar* `csi-snapshotter`.
- Créer un instantané, restaurer un volume depuis un instantané, cloner un volume, pour RBD et pour CephFS.
- Voir ce que ces opérations font réellement dans Ceph, et ce qu'un instantané n'est **pas** (une sauvegarde).

**Prérequis** : M16-E06 (contrôleur de snapshots, classe `ceph-rbd`) et M16-E07 (`cephfs`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- external-snapshotter 8.6 (CRD et `snapshot-controller`) a été installé en E06, **avant** les pilotes, et les charts ceph-csi contiennent le *sidecar* `csi-snapshotter` dans le provisionneur : tout est prêt, sauf les **classes** d'instantanés. On n'utilise que `VolumeSnapshot` (v1) ; les instantanés de groupe (`VolumeGroupSnapshot`) sont hors périmètre (leur statut d'API est ambigu dans la 8.6).
- Classes d'instantanés : `ceph-rbd-snap` (pilote `rbd.csi.ceph.com`) et `cephfs-snap` (pilote `cephfs.csi.ceph.com`), chacune **par défaut pour son pilote**, `deletionPolicy: Delete`. Leurs paramètres : `clusterID` et le Secret de l'instantaneur (le même que celui du provisionneur).
- Rangement dans `plateforme/k8s` : `composants/ceph-csi/classes/ceph-rbd-snap.yaml` et `composants/ceph-csi/classes/cephfs-snap.yaml`, à côté des StorageClasses : `installer.sh` d'E06 les appliquera avec elles.
- Les vérifications lisent des ressources que le ClusterRole `wb-checks` du M14 ne couvre peut-être pas (instantanés, et plus tard Velero, CloudNativePG, Rook, Longhorn). Ajoute un ClusterRole `wb-checks-stockage` en **lecture seule** (`get`, `list`, `watch`), lié au compte de service `wb-checks` de `wb-system`, sur les groupes `snapshot.storage.k8s.io`, `velero.io`, `postgresql.cnpg.io`, `barmancloud.cnpg.io`, `ceph.rook.io`, `csi.ceph.io`, `longhorn.io`, `admissionregistration.k8s.io` (politiques), `networking.k8s.io` et `cilium.io` (politiques réseau), `storage.k8s.io`, plus `get` sur `nodes/proxy` (résumé de statistiques du kubelet) : `plateforme/k8s/rbac/wb-checks-stockage.yaml`.
- Objets d'essai, dans `wb-essais` : PVC `donnees` (`ceph-rbd`, 1 Gio) et `partage` (`cephfs`, 1 Gio, RWX), chacun monté par un pod qui y écrit un fichier ; instantanés `donnees-s1` et `partage-s1` ; PVC `donnees-restauree` (depuis `donnees-s1`), `donnees-clone` (clone de `donnees`), `partage-restauree` (depuis `partage-s1`). Garde-les jusqu'à E11 : E11 s'en sert.

**Travail demandé**
1. **Vérifications.** Écris `rbac/wb-checks-stockage.yaml` (ClusterRole + ClusterRoleBinding), MR, application. Prouve qu'il suffit et qu'il ne donne rien de plus : `kubectl auth can-i list volumesnapshots -A --as=system:serviceaccount:wb-system:wb-checks`, puis la même question pour `create` et pour `secrets`.
2. **Lecture.** Lis la page *Volume Snapshots* de la documentation Kubernetes et la page *Snapshot* de la documentation ceph-csi (RBD et CephFS). Réponds dans `~/m16/e10/journal.md` : qui crée le `VolumeSnapshotContent` d'un instantané dynamique ? Que fait le `snapshot-controller`, que fait le *sidecar* `csi-snapshotter` ? Que change `deletionPolicy: Retain` sur une classe d'instantanés ? Que devient l'instantané si on supprime le PVC source ?
3. **État des lieux.** Vérifie ce qu'E06 a installé : CRD (`kubectl get crd | grep snapshot.storage`), contrôleur (deux réplicas, un seul *leader* : journal du contrôleur et objet `Lease` de `kube-system`), *sidecar* `csi-snapshotter` dans les pods du provisionneur RBD et CephFS (`kubectl -n ceph-csi get pod <POD> -o jsonpath='{.spec.containers[*].name}'`) et son journal. Note ce que tu vois avant de créer quoi que ce soit.
4. **Classes d'instantanés.** Écris les deux fichiers de classes, MR, application (`composants/ceph-csi/installer.sh`, ou `kubectl apply -f` des deux fichiers). Vérifie : `kubectl get volumesnapshotclass`.
5. **RBD : instantané et restauration.** Dans `wb-essais`, crée `donnees` et un pod qui y écrit `rdv.txt` et note son empreinte (`sha256sum`). Crée l'instantané `donnees-s1` ; suis-le jusqu'à `readyToUse: true` (`kubectl get volumesnapshot -w`, puis `describe` du `VolumeSnapshotContent`). Côté Ceph (`ceph01`), regarde ce qui est apparu dans `k8s-rbd` (`rbd ls`, `rbd snap ls`, `rbd info`). Modifie `rdv.txt`. Crée `donnees-restauree` depuis l'instantané, monte-le dans un second pod et compare les empreintes.
6. **RBD : clone.** Crée `donnees-clone`, clone direct de `donnees` (sans instantané explicite). Note dans le journal les contraintes que tu rencontres ou que la documentation impose (classe, taille, espace de noms) et ce que ceph-csi crée côté Ceph pour un clone.
7. **CephFS.** Même chose avec `partage` (instantané `partage-s1`, restauration `partage-restauree`). Mesure le temps de restauration de chacun des deux pilotes avec un fichier de 300 Mio et explique l'écart (sur `ceph01` : `ceph fs subvolume ls cephfs --group_name csi`, `ceph fs clone status`).
8. **Ce qu'un instantané n'est pas.** Réponds dans le journal : où sont physiquement les blocs de `donnees-s1` ? Que reste-t-il si le pool `k8s-rbd` est perdu ? Un instantané pris pendant que PostgreSQL écrit est-il cohérent ?

**Critères de réussite**
- [ ] Le compte `wb-checks` lit les instantanés, mais ne peut ni en créer ni lire de Secret.
- [ ] Les trois CRD `volumesnapshot*` (v1) existent ; `snapshot-controller` tourne dans `kube-system` en 8.6 (installé en E06).
- [ ] `ceph-rbd-snap` et `cephfs-snap` existent, chacune par défaut pour son pilote, en `deletionPolicy: Delete`.
- [ ] Dans `wb-essais` : `donnees-s1` et `partage-s1` sont prêts ; `donnees-restauree` et `partage-restauree` sont liés et viennent d'un instantané ; `donnees-clone` est lié et vient de `donnees`.
- [ ] Le journal répond aux questions des étapes 2, 6, 7 et 8.

**Vérification** : `lab/bin/check 16 10`

<details><summary>Indice 1</summary>

Le contrôleur de snapshots observe les objets `VolumeSnapshot` ; le *sidecar* `csi-snapshotter` observe les `VolumeSnapshotContent` et appelle le pilote. Le nom du *leader* est dans le champ `holderIdentity` du `Lease` du contrôleur (`kubectl -n kube-system get lease`).
</details>

<details><summary>Indice 2</summary>

La classe d'instantanés par défaut se désigne par une **annotation**, comme pour les classes de stockage, mais son nom n'est pas le même : cherche-le dans la page *Volume Snapshot Classes*. Les noms des paramètres de Secret d'un instantané suivent le même schéma que ceux d'une StorageClass (`csi.storage.k8s.io/…-secret-name`).
</details>

<details><summary>Indice 3</summary>

Restaurer ou cloner, c'est créer un **nouveau** PVC avec un champ `dataSource` (ou `dataSourceRef`) : `kind` vaut `VolumeSnapshot` (avec son `apiGroup`) ou `PersistentVolumeClaim` (sans `apiGroup`). La taille demandée ne peut pas être inférieure à celle de la source.
</details>

**Pour aller plus loin** (facultatif) : pré-provisionne un `VolumeSnapshotContent` pour un instantané RBD créé **à la main** sur `ceph01` (`rbd snap create`), lie-le à un `VolumeSnapshot` et restaure-le : c'est la voie d'import de données existantes dans le cluster.

---

### M16-E11 — Agrandir un volume, volumes en mode bloc  `LAB` `★★`

> **Ticket INC-4311** — *De : Nadia Roussel*
> Cette nuit, l'alerte « disque plein à 95 % » de la base de test d'InfoGér m'a réveillée, et la seule solution qu'ils connaissaient, c'était « on arrête, on copie sur un disque plus grand, on redémarre ». Chez nous, je veux savoir : peut-on agrandir un volume **sans arrêter** l'application ? Où voit-on qu'un volume se remplit, sans attendre la supervision ? Et Karim parle de volumes « en mode bloc » pour certains logiciels : qu'est-ce que ça change ?

**Objectifs pédagogiques**
- Agrandir un PVC en ligne et suivre les deux étapes de l'agrandissement (contrôleur puis nœud).
- Lire l'occupation d'un volume depuis le kubelet, sans Prometheus.
- Utiliser un volume en `volumeMode: Block` et comprendre ce qui le distingue d'un volume de système de fichiers.

**Prérequis** : M16-E10 (objets de `wb-essais`).
**Durée indicative** : 1 h 30.

**Contexte technique**
- `ceph-rbd` et `cephfs` ont été créées avec `allowVolumeExpansion: true` (palier 1). Les charts ceph-csi déploient le *sidecar* `csi-resizer`.
- Le kubelet publie l'occupation de chaque volume monté dans son résumé de statistiques : `kubectl get --raw "/api/v1/nodes/<NŒUD>/proxy/stats/summary"` (section `pods[].volume[]`), et dans ses métriques (`/metrics` du kubelet, séries `kubelet_volume_stats_*`).
- Objets : `donnees` passe à 2 Gio, `partage` à 2 Gio ; nouveau PVC `bloc` (`ceph-rbd`, 1 Gio, `volumeMode: Block`), monté par un pod `bloc-essai` en `/dev/xvda`.
- Classe d'essai `wb-essai-fige` : mêmes paramètres que `ceph-rbd`, mais `allowVolumeExpansion: false`, supprimée en fin d'exercice.

**Travail demandé**
1. Remplis `donnees` à environ 90 % depuis son pod. Retrouve ce taux dans le résumé du kubelet du nœud qui porte le pod (un `jq` qui sort `pvcRef`, `usedBytes`, `capacityBytes`), puis dans `/metrics` du kubelet. Écris le petit script `~/m16/e11/occupation.sh` qui affiche le taux d'occupation de tous les PVC montés du cluster.
2. Agrandis `donnees` à 2 Gio **sans arrêter le pod**. Suis l'opération : conditions du PVC (`kubectl get pvc donnees -o yaml`), événements (`kubectl describe pvc`), taille vue par `df` dans le pod. Note dans le journal l'ordre des événements et qui les émet.
3. Essaie de **réduire** `donnees` à 1 Gio : note le message. Lis dans la documentation ce que permet la reprise d'un agrandissement échoué (*Recovering from Failure when Expanding Volumes*) et à quelles conditions.
4. Agrandis `partage` (CephFS) à 2 Gio. Côté Ceph, regarde ce qui a changé (`ceph fs subvolume info cephfs <SOUS-VOLUME> --group_name csi`, champ `bytes_quota`). Pourquoi est-ce instantané ?
5. Crée `wb-essai-fige`, un PVC dessus, et tente de l'agrandir : quel composant refuse, et à quel moment ? Supprime ensuite PVC et classe.
6. **Mode bloc.** Crée `bloc` et `bloc-essai` (le conteneur voit un périphérique, pas un répertoire : `volumeDevices`). Dans le pod, écris des données directement sur le périphérique (`dd`), relis-les, regarde ce que montrent `lsblk` et `ls -l /dev/xvda`. Agrandis `bloc` à 2 Gio : que voit le pod, et pourquoi n'y a-t-il pas d'étape « système de fichiers » ?
7. Réponds dans le journal : quels logiciels tirent parti d'un volume en mode bloc ? Pourquoi un volume RBD peut-il être `ReadWriteMany` **en mode bloc** et pas en mode fichier ? Qui doit alors garantir la cohérence ?

**Critères de réussite**
- [ ] `donnees` et `partage` ont une capacité d'au moins 2 Gio, sans redémarrage de leur pod (`restartCount` inchangé, pod de même âge).
- [ ] `bloc` est en `volumeMode: Block`, lié, d'au moins 2 Gio, utilisé par `bloc-essai` en `volumeDevices`.
- [ ] La classe `wb-essai-fige` n'existe plus.
- [ ] `~/m16/e11/occupation.sh` existe, est exécutable et affiche un taux par PVC ; le journal répond aux étapes 2, 3, 6 et 7.

**Vérification** : `lab/bin/check 16 11`

<details><summary>Indice 1</summary>

`kubectl patch pvc donnees -p '…'` ou `kubectl edit` : seul `spec.resources.requests.storage` change. Pour un pilote qui sait agrandir « à chaud », l'étape nœud se fait au prochain passage du kubelet sur le volume monté : laisse-lui une minute.
</details>

<details><summary>Indice 2</summary>

Dans un pod, un volume en mode bloc se déclare sous `volumeDevices` (avec `devicePath`) et non sous `volumeMounts`. `lsblk` n'est pas toujours dans les images minimales : une image Debian (par le cache Harbor) contient `util-linux`.
</details>

**Pour aller plus loin** (facultatif) : lis la KEP des `VolumeAttributesClass` (GA en 1.34) : quels attributs d'un volume pourrait-on modifier à chaud avec un pilote qui les gère, et ceph-csi 3.18 en gère-t-il ?

---

### M16-E12 — Classes de stockage : défaut, topologie, liaison différée  `LAB` `★★`

> **Ticket PLAT-1712** — *De : Karim Benali*
> On va bientôt avoir plusieurs classes (et deux de plus pendant la comparaison Rook/Longhorn). Je veux que l'équipe sache exactement ce qui se passe quand un PVC ne dit pas de classe, quand il y a deux classes par défaut, ou zéro ; quand un volume est créé (à la demande ou au premier pod) et pourquoi c'est important ; et si on peut forcer des volumes à rester dans une baie. Fais les essais, et écris le catalogue des classes de `k8s-par1` : ce qu'elles valent, à qui elles servent, ce qu'on ne doit pas faire avec.

**Objectifs pédagogiques**
- Maîtriser la classe par défaut (zéro, une, deux) et l'attribution rétroactive.
- Comprendre `volumeBindingMode` (`Immediate`, `WaitForFirstConsumer`) et l'interaction entre ordonnanceur et provisionneur.
- Utiliser `allowedTopologies` et comprendre ce qu'il fait quand le pilote n'annonce pas de topologie.
- Lire et justifier chaque paramètre d'une StorageClass ceph-csi.

**Prérequis** : M16-E06, M16-E07 ; M14-E14 (étiquettes `topology.kubernetes.io/zone` = `par1-baie-a/b/c` sur les nœuds).
**Durée indicative** : 2 h.

**Contexte technique**
- Classes d'essai, toutes **supprimées en fin d'exercice** : `wb-essai-defaut2` (copie de `ceph-rbd` marquée par défaut), `wb-essai-differee` (copie de `ceph-rbd` en `WaitForFirstConsumer`), `wb-essai-baie-a` (copie de `wb-essai-differee`, limitée à la zone `par1-baie-a`).
- Le contrôleur d'admission `DefaultStorageClass` est actif sur kubeadm ; l'attribution rétroactive de la classe par défaut aux PVC qui n'en ont pas est GA depuis Kubernetes 1.28.
- Catalogue : `docs/kubernetes/stockage/classes.md` dans `plateforme/medisphere`.

> ⚠️ **Attention** : l'étape 3 retire **pendant quelques minutes** la classe par défaut du cluster. Tout PVC créé sans classe pendant ce temps (par une autre personne, un opérateur, un chart) reste sans classe. Préviens (ticket), fais-le hors des essais d'autres modules, note l'heure, et remets l'annotation dès l'essai terminé ; vérifie à la fin qu'il y a exactement une classe par défaut.

**Travail demandé**
1. **Lecture des paramètres.** Explique dans `~/m16/e12/journal.md`, ligne par ligne, la StorageClass `ceph-rbd` telle qu'elle est dans le cluster (`kubectl get sc ceph-rbd -o yaml`) : `provisioner`, chaque paramètre (`clusterID`, `pool`, `imageFeatures`, `csi.storage.k8s.io/fstype`, les cinq paramètres de Secret et ce que chacun sert à appeler), `reclaimPolicy`, `allowVolumeExpansion`, `volumeBindingMode`, `mountOptions` éventuelles. Lesquels sont modifiables après création ?
2. **Deux classes par défaut.** Crée `wb-essai-defaut2`. Crée un PVC sans classe : laquelle reçoit-il ? Que dit la documentation sur ce cas depuis 1.26 ? Supprime le PVC et `wb-essai-defaut2`.
3. **Zéro classe par défaut** (voir l'avertissement). Retire l'annotation de `ceph-rbd`, crée un PVC `sans-classe` sans classe : état, événements, `spec.storageClassName`. Remets l'annotation et observe `sans-classe` dans la minute qui suit. Quelle différence entre un PVC **sans** `storageClassName` et un PVC avec `storageClassName: ""` ? Prouve-le.
4. **Liaison différée.** Crée `wb-essai-differee`, puis un PVC dessus : état et événement. Crée un pod qui le monte avec un `nodeSelector` impossible (étiquette inexistante) : que se passe-t-il côté Ceph (`rbd ls k8s-rbd` avant et après) ? Corrige le pod. Compare avec la même expérience en `Immediate` sur `ceph-rbd`. Écris dans le journal deux situations réelles où `Immediate` coûte (quotas, volumes orphelins, topologie).
5. **Topologie.** Crée `wb-essai-baie-a` et un pod sans `nodeSelector` qui monte un PVC de cette classe. Sur quel nœud arrive-t-il, et qui l'a décidé ? Regarde les topologies qu'annonce le pilote (`kubectl get csinode -o yaml`, `topologyKeys`) et le champ `nodeAffinity` du PV créé : explique pourquoi la contrainte ne suit pas le volume. Qu'est-ce qui changerait avec un pilote qui annonce sa topologie (Longhorn, un stockage local, un Ceph par baie) ?
6. **Nettoyage.** Supprime pods, PVC d'essai et les trois classes `wb-essai-*`. Vérifie qu'il ne reste qu'une classe par défaut.
7. **Catalogue.** Écris `docs/kubernetes/stockage/classes.md` (MR) : pour chaque classe de `k8s-par1`, son usage, ses paramètres significatifs, sa politique de récupération, ses limites (modes d'accès, snapshots, agrandissement), qui peut l'utiliser ; la règle de la classe par défaut et la position de l'équipe sur `WaitForFirstConsumer` pour `ceph-rbd` (argumentée : changer de mode impose de recréer la classe).

**Critères de réussite**
- [ ] Il existe exactement une classe par défaut, `ceph-rbd` ; aucune classe `wb-essai-*` ne reste.
- [ ] Aucun PVC d'essai de cet exercice ne reste dans `wb-essais` (`sans-classe` compris).
- [ ] `docs/kubernetes/stockage/classes.md` est sur `main` de `plateforme/medisphere` et décrit les trois classes.
- [ ] Le journal répond aux étapes 1, 3, 4 et 5.

**Vérification** : `lab/bin/check 16 12`

<details><summary>Indice 1</summary>

Les champs d'une StorageClass sont presque tous immuables : `kubectl apply` d'une version modifiée échoue. Pour en « changer », on la supprime et on la recrée : les PV existants ne sont pas touchés (ils ont copié ce dont ils ont besoin), mais ce qui la référence par son nom (PVC futurs, charts) doit suivre.
</details>

<details><summary>Indice 2</summary>

Avec `WaitForFirstConsumer`, c'est l'**ordonnanceur** qui choisit d'abord le nœud, puis le provisionneur crée le volume en tenant compte de ce choix (annotation `volume.kubernetes.io/selected-node` sur le PVC). `allowedTopologies` est lu à ce moment-là, en comparant ses termes aux étiquettes des nœuds.
</details>

<details><summary>Indice 3</summary>

Pour une copie de classe : `kubectl get sc ceph-rbd -o yaml`, retire `uid`, `resourceVersion`, `creationTimestamp`, les annotations de gestion, change le nom (et ce que l'essai demande). `kubectl neat` (krew) fait ce ménage.
</details>

---

### M16-E13 — Rook : un Ceph dans le cluster  `LAB` `★★★`

> **Ticket PLAT-1713** — *De : Claire Morel*
> Avant de signer l'ADR du stockage de `k8s-par1`, je veux une comparaison honnête. Notre choix de départ est un Ceph **externe**, exploité par l'équipe avec cephadm. L'autre école, c'est un Ceph **dans** Kubernetes, piloté par un opérateur : Rook. Monte-le pour de vrai sur nos travailleurs, avec des disques à lui, et dis-moi ce que ça coûte (mémoire, disques, complexité) et ce que ça apporte. On le démontera ensuite : je ne veux pas de deuxième Ceph en production.

**Objectifs pédagogiques**
- Comprendre le modèle opérateur de Rook (CRD `CephCluster`, `CephBlockPool`…, réconciliation) et ce qu'il automatise par rapport à cephadm.
- Préparer des nœuds pour des OSD (disques bruts, `lvm2`, noyau) par le code.
- Installer Rook 1.21 et un cluster minimal par Helm, avec des valeurs maîtrisées (ressources, disques désignés, `msgr2`).
- Mesurer l'empreinte de la solution.

**Prérequis** : M16-E06 (ceph-csi externe, pour comparer), M16-E12 (une seule classe par défaut) ; M05 (OpenTofu, module `vm-noeud`), M08 (Ceph).
**Durée indicative** : 4 h.

**Contexte technique**
- Disques : un disque de 32 Go par travailleur, sur `ssd-lab`, en `scsi1`, série `k8s-w0N-rook` (attribut `serie` de `disques_donnees` du module `vm-noeud`) ; vu dans l'invité sous `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_k8s-w0N-rook` (vérifie le nom exact sur un nœud). Rook ne doit consommer **que** ce disque : désigne-le par ce chemin, jamais par `useAllDevices`.
- Rook 1.21.0 : chart opérateur `rook-release/rook-ceph` (dépôt `https://charts.rook.io/release`) et chart de cluster `rook-release/rook-ceph-cluster`, tous deux en **1.21.0**, espace `rook-ceph`. Depuis 1.21, les pilotes CSI de Rook sont gérés par **ceph-csi-operator** (sous-chart de l'opérateur) ; leurs noms sont préfixés par l'espace de l'opérateur (`rook-ceph.rbd.csi.ceph.com`) et ne se heurtent donc pas à ceux d'E06. Rook 1.21 exige `msgr2` par défaut (noyau 5.11 ou plus : Debian 13 a 6.12) et l'image Ceph par défaut est `quay.io/ceph/ceph:v20.2.4`.
- Cluster minimal : 3 MON, 1 MGR, 3 OSD (un par travailleur), tableau de bord en TLS, *toolbox* activée, **aucun** système de fichiers ni magasin d'objets ; un pool répliqué `rook-essai` (3 copies, domaine de panne `host`) et sa classe `rook-ceph-block`, **pas** par défaut. Les clés CSI de Rook doivent être de type `aes` (nœuds en noyau 6.12) : le chart a une valeur pour cela.
- Mémoire : les valeurs par défaut du chart réservent 4 Gio par OSD, 1 Gio par MON, 512 Mio par MGR : impossible sur des travailleurs de 8 Go qui portent déjà MédiAgenda. Fixe des ressources réalistes (≈ 1 Gio par OSD, 256 Mio de requête par MON) et retiens que Rook dérive `osd_memory_target` de la limite mémoire de l'OSD.
- Sécurité : les démons Ceph de Rook ont besoin de privilèges (accès aux disques, `hostPath` sous `/var/lib/rook`). L'espace `rook-ceph` reçoit donc le niveau PSA `privileged`, comme l'espace `ceph-csi` d'E06 : c'est une exception à inscrire dans la documentation.
- Code : disques dans `plateforme/infra` (`envs/k8s/`), prérequis des nœuds dans `plateforme/ansible` (`playbooks/k8s-rook-prerequis.yml`), espace et valeurs Helm dans `plateforme/k8s` (`espaces/rook-ceph/`, `composants/rook/operator-values.yaml`, `composants/rook/cluster-values.yaml`).

> ⚠️ **Attention** : un OSD efface le disque qu'on lui donne. Avant d'installer le chart de cluster, vérifie **sur chaque travailleur** que le chemin désigné est bien le disque de 32 Go vide (`lsblk -o NAME,SIZE,SERIAL,FSTYPE,MOUNTPOINTS`) et qu'aucune valeur ne dit « tous les nœuds, tous les disques » (`useAllNodes`, `useAllDevices`). Au moindre doute, arrête-toi.

**Travail demandé**
1. **Lecture.** Lis *Rook → Quickstart*, *Prerequisites* et *CephCluster CRD* (sections *Storage Selection Settings*, *Network*, *Resources*) de la documentation 1.21. Réponds dans `~/m16/e13/journal.md` : qui crée les MON, les OSD, les clés des pilotes CSI ? Que fait un *job* `rook-ceph-osd-prepare` ? Où Rook range-t-il l'état d'un MON sur le nœud, et pourquoi ce répertoire doit-il disparaître avant toute réinstallation ? Quelle est la différence entre ce cluster et le mode **externe** de Rook ?
2. **Disques.** Ajoute le disque aux trois travailleurs dans `envs/k8s/` (MR sur `plateforme/infra`). Lis le plan : il doit annoncer une **modification en place** des trois VMs, sans remplacement. Applique, puis vérifie sur chaque nœud que le disque est vu, vide, et sous quel chemin stable.
3. **Prérequis des nœuds.** Écris `playbooks/k8s-rook-prerequis.yml` (paquet `lvm2`, module `rbd` chargé au démarrage, contrôle que le disque désigné n'a aucune signature) ; MR, pipeline, application sur `k8s_travailleurs`.
4. **Espace de noms.** `espaces/rook-ceph/00-namespace.yaml` avec le niveau PSA `privileged` (en `enforce`, `audit` et `warn`) et un commentaire qui justifie l'exception ; MR, application.
5. **Opérateur.** Écris `composants/rook/operator-values.yaml` (ressources de l'opérateur modestes, rien d'autre que nécessaire) ; puis :
   ```
   admin@adm01:~$ helm repo add rook-release https://charts.rook.io/release
   admin@adm01:~$ helm show values rook-release/rook-ceph --version 1.21.0 > ~/m16/e13/operator-defauts.yaml
   admin@adm01:~/src/k8s$ helm upgrade --install rook-ceph rook-release/rook-ceph --version 1.21.0 \
       -n rook-ceph -f composants/rook/operator-values.yaml --wait
   ```
   Liste les CRD installées (`kubectl get crd | grep -E 'rook|csi.ceph.io'`) et les pods de l'espace.
6. **Cluster.** Écris `composants/rook/cluster-values.yaml` à partir de `helm show values rook-release/rook-ceph-cluster --version 1.21.0` : image Ceph, `msgr2` exigé, nombre de MON et de MGR, ressources, tableau de bord, *toolbox*, sélection explicite des trois nœuds et de leur disque, pool `rook-essai` et classe `rook-ceph-block` non par défaut, pas de système de fichiers ni de magasin d'objets, pas de classe d'instantanés. Fais relire le fichier (MR) **avant** d'installer :
   ```
   admin@adm01:~/src/k8s$ helm template rook-ceph-cluster rook-release/rook-ceph-cluster --version 1.21.0 \
       -n rook-ceph -f composants/rook/cluster-values.yaml > ~/m16/e13/cluster-rendu.yaml
   admin@adm01:~/src/k8s$ helm upgrade --install rook-ceph-cluster rook-release/rook-ceph-cluster --version 1.21.0 \
       -n rook-ceph -f composants/rook/cluster-values.yaml
   ```
   Dans `cluster-rendu.yaml`, vérifie la section `storage` du `CephCluster` et le champ `isDefault` de la classe.
7. **Démarrage.** Suis la création (`kubectl -n rook-ceph get pods -w`) : MON, MGR, *jobs* de préparation des OSD, OSD, pilotes CSI de Rook. Lis le journal d'un *job* de préparation. Attends `kubectl -n rook-ceph get cephcluster` en `Ready` et `HEALTH_OK` (ou un `HEALTH_WARN` que tu sais expliquer). Sur un travailleur, regarde ce qu'est devenu le disque (`lsblk`) et `/var/lib/rook`.
8. **Un volume.** Dans `wb-essais`, crée un PVC `rook-essai` sur `rook-ceph-block` (1 Gio) et un pod qui y écrit. Vérifie que le PVC sans classe d'un autre essai irait toujours sur `ceph-rbd`.
9. **Empreinte.** Relève la mémoire et le processeur consommés par l'espace `rook-ceph` (`kubectl top pods -n rook-ceph`, somme), le nombre de pods, d'objets CRD, et compare dans le journal avec ce que `k8s-par1` consomme pour parler à `ceph-par1` (espace `ceph-csi`). Note aussi : qui, chez nous, saurait réparer chacune des deux solutions à 3 h du matin ?

**Critères de réussite**
- [ ] L'espace `rook-ceph` est en PSA `privileged` ; l'opérateur et le cluster sont installés en 1.21.0.
- [ ] Le `CephCluster` est prêt avec 3 MON, au moins 1 MGR et 3 OSD répartis sur les trois travailleurs, `msgr2` exigé.
- [ ] Le pool `rook-essai` est prêt ; la classe `rook-ceph-block` existe et n'est **pas** par défaut ; `ceph-rbd` reste la seule classe par défaut.
- [ ] Le PVC `rook-essai` de `wb-essais` est lié par le pilote de Rook.
- [ ] Sur chaque travailleur, le disque `k8s-w0N-rook` existe (32 Go) ; le journal contient l'empreinte mesurée.

**Vérification** : `lab/bin/check 16 13` (à lancer **avant** le démontage d'E14).

<details><summary>Indice 1</summary>

Dans `cephClusterSpec.storage` du chart : `useAllNodes: false`, `useAllDevices: false`, puis une liste `nodes` où chaque `name` est la valeur de l'étiquette `kubernetes.io/hostname` du nœud et chaque `devices[].name` peut être un chemin udev complet.
</details>

<details><summary>Indice 2</summary>

Le chart de cluster crée par défaut un pool, un système de fichiers **et** un magasin d'objets, chacun avec sa classe, et la classe du pool est marquée par défaut. Les listes `cephFileSystems` et `cephObjectStores` vides suffisent à n'en créer aucun ; regarde `cephBlockPools[].storageClass`.
</details>

<details><summary>Indice 3</summary>

Si les OSD n'apparaissent pas : journal du *job* `rook-ceph-osd-prepare-<nœud>` (conteneur `provision`), puis `lsblk -f` sur le nœud. Un disque qui porte la moindre signature (table de partitions, LVM) est ignoré, et c'est voulu.
</details>

**Pour aller plus loin** (facultatif) : lis la page *External Storage Cluster* de Rook : quelles ressources faudrait-il créer pour que Rook gère seulement les pilotes CSI vers `ceph-par1` (script `create-external-cluster-resources.py`), et que gagnerait-on par rapport aux charts ceph-csi d'E06 ?

---

### M16-E14 — Rook : exploiter puis démonter proprement  `LAB` `★★★`

> **Ticket PLAT-1714** — *De : Karim Benali*
> Avant de démonter, je veux trois choses de ton essai Rook : comment on administre ce Ceph au quotidien (et ce qui se passe quand on contourne l'opérateur), comment il encaisse la perte d'un OSD, et la preuve qu'on sait le **retirer** sans laisser de traces : un disque « presque effacé » ou un `/var/lib/rook` oublié, c'est le prochain cluster qui démarre avec de vieux MON. Suis l'ordre officiel, à la lettre.

**Objectifs pédagogiques**
- Administrer un cluster Rook (*toolbox*, ressources personnalisées) et comprendre la réconciliation : le CR fait foi.
- Observer la perte et le retour d'un OSD sous un opérateur.
- Démonter Rook dans l'ordre officiel de la documentation 1.21 et vérifier sur les nœuds qu'il ne reste rien.

**Prérequis** : M16-E13.
**Durée indicative** : 3 h.

**Contexte technique**
- *Toolbox* : déploiement `rook-ceph-tools` (activé en E13) ; `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph …`.
- Arrêter un OSD sous Rook : l'opérateur recrée ce qu'on lui retire. Pour une panne simulée, on **suspend** d'abord l'opérateur (zéro réplica), puis on arrête le déploiement de l'OSD ; on relance dans l'ordre inverse.
- Démontage : page *Cleanup* (`Storage-Configuration/ceph-teardown`) de la documentation 1.21. Retenir : applications et classes d'abord ; `cleanupPolicy` du `CephCluster` (`confirmation: yes-really-destroy-data`) **avant** sa suppression, pour que les *jobs* `rook-ceph-cleanup` effacent `dataDirHostPath` et les disques ; ressources de ceph-csi-operator ; opérateur ; puis contrôle et nettoyage des nœuds (`sgdisk --zap-all`, effacement des en-têtes, *device mapper* `ceph-*`).
- Les **disques** restent attachés aux VMs (vides) : ils sont retirés par OpenTofu au mini-projet.
- RGW (magasin d'objets Rook) : facultatif, en « Pour aller plus loin ».

> ⚠️ **Attention** : le démontage détruit toutes les données du Ceph de Rook ; c'est voulu. Ce qui ne doit **jamais** être touché : les disques système des nœuds, le Ceph **externe** `ceph-par1` et les pilotes d'E06 (`rbd.csi.ceph.com`, `cephfs.csi.ceph.com`, espace `ceph-csi`), les CRD d'instantanés (communes). Avant chaque `sgdisk` ou `dd`, relis le chemin `/dev/disk/by-id/…-rook` et vérifie sa taille. Une commande de nettoyage copiée d'Internet qui « supprime tous les `/dev/mapper/ceph-*` » ne s'exécute que sur un nœud qui n'a **aucun** autre usage de Ceph en LVM (c'est notre cas : le Ceph externe n'a pas d'OSD sur les travailleurs ; vérifie-le).

**Travail demandé**
1. **Administrer.** Depuis la *toolbox* : `ceph -s`, `ceph osd tree`, `ceph df`, `ceph auth ls` (repère les clés des pilotes CSI de Rook et leur type), `ceph config dump` (repère ce que Rook a réglé, dont `osd_memory_target`). Note dans `~/m16/e14/journal.md` ce que tu trouves.
2. **Le CR fait foi.** Dans la *toolbox*, passe la réplication de `rook-essai` à 2 (`ceph osd pool set rook-essai size 2`). Puis provoque une réconciliation du pool (modifie un champ anodin du `CephBlockPool`, par exemple une annotation, ou redémarre l'opérateur) et regarde ce que devient `size`. Conclus dans le journal : qu'est-ce qui, chez Rook, joue le rôle des spécifications de `plateforme/ceph` ?
3. **Perte d'un OSD.** Avec le pod d'E13 qui écrit en continu dans `rook-essai` (une ligne horodatée par seconde) : suspends l'opérateur, arrête le déploiement d'un OSD, observe `ceph -s` (PG dégradés), l'écriture du pod, `ceph osd tree`. Attends au moins 10 minutes : que fait Ceph (`mon_osd_down_out_interval`) ? Relance l'OSD puis l'opérateur ; observe la récupération jusqu'à `HEALTH_OK`. Note les heures et les états.
4. **Démontage, préparation.** Écris d'abord, dans le journal, la séquence complète que tu vas suivre (d'après la page *Cleanup*), avec pour chaque étape la commande et le contrôle qui t'autorise à passer à la suivante. Fais-la relire (Karim) avant de commencer.
5. **Démontage, cluster.** Supprime le pod et le PVC `rook-essai` de `wb-essais` ; vérifie qu'aucun PV n'utilise plus le pilote `rook-ceph.rbd.csi.ceph.com`. Pose la `cleanupPolicy`, puis retire le cluster (chart `rook-ceph-cluster`). Suis les *jobs* `rook-ceph-cleanup` sur chaque nœud jusqu'à leur fin et lis le journal de l'un d'eux.
6. **Démontage, opérateur.** Supprime les ressources de ceph-csi-operator qui restent, puis l'opérateur (chart `rook-ceph`), puis les CRD restantes (`ceph.rook.io`, `csi.ceph.io`) et l'espace `rook-ceph`. Retire les fichiers de Rook de `plateforme/k8s` par MR (garde les valeurs dans l'historique Git, c'est la trace de l'essai).
7. **Nœuds.** Sur chaque travailleur : `/var/lib/rook` a-t-il disparu ? Le disque `…-rook` porte-t-il encore une signature (`wipefs -n`, `lsblk -f`, `pvs`) ? Reste-t-il des entrées `/dev/mapper/ceph-*` ? Complète le nettoyage par le code (tâche ou playbook `k8s-rook-nettoyage.yml`, qui refuse de s'exécuter si le disque ciblé ne fait pas 32 Go ou s'il est monté).
8. **Bilan.** Dans le journal : temps passé, incidents, ce que tu ferais différemment ; puis, pour l'ADR (E30), trois avantages et trois inconvénients de Rook **chez MédiSphère**, chiffrés quand c'est possible.

**Critères de réussite**
- [ ] L'espace `rook-ceph` n'existe plus ; aucune CRD `*.ceph.rook.io` ni `*.csi.ceph.io` ne reste ; aucun `CSIDriver`, PV ni StorageClass de Rook.
- [ ] Les pilotes d'E06 (`rbd.csi.ceph.com`, `cephfs.csi.ceph.com`) et les CRD d'instantanés sont toujours là ; `ceph-rbd` est toujours la classe par défaut.
- [ ] Sur chaque travailleur : `/var/lib/rook` n'existe plus ; le disque `k8s-w0N-rook` est présent et ne porte aucune signature ; aucun `/dev/mapper/ceph-*`.
- [ ] Le journal contient les observations de la panne d'OSD (heures et états) et la séquence de démontage relue.

**Vérification** : `lab/bin/check 16 14`

<details><summary>Indice 1</summary>

Pour suspendre l'opérateur : `kubectl -n rook-ceph scale deploy rook-ceph-operator --replicas=0`. Les déploiements d'OSD s'appellent `rook-ceph-osd-<ID>`. Le chart de l'opérateur a aussi une valeur `scaleDownOperator`, pensée pour les outils GitOps.
</details>

<details><summary>Indice 2</summary>

`helm uninstall` du chart de cluster supprime le `CephCluster` : la `cleanupPolicy` doit donc être posée **avant**, par `kubectl patch` (ou par les valeurs, puis `helm upgrade`). Les *jobs* de nettoyage ne démarrent pas tant que des volumes de Rook existent encore.
</details>

<details><summary>Indice 3</summary>

Si l'espace reste en `Terminating`, la documentation explique comment retrouver la ressource qui le retient et comment retirer un *finalizer* : à ne faire **que** si l'opérateur n'est plus là pour le faire lui-même, et en notant pourquoi.
</details>

**Pour aller plus loin** (facultatif, avant le démontage) : crée un `CephObjectStore` minimal (une instance RGW) et un `ObjectBucketClaim` ; lis le Secret et la ConfigMap produits : comment une application obtiendrait-elle ainsi un compartiment S3 « à la demande » ? Compare avec les comptes RGW faits à la main au M08-E12.

---

### M16-E15 — Longhorn : du stockage répliqué sur les nœuds  `LAB` `★★`

> **Ticket PLAT-1715** — *De : Claire Morel*
> Deuxième candidat : Longhorn. Pas de Ceph du tout, des réplicas de volumes sur les disques des nœuds, une interface web, des sauvegardes vers S3 intégrées. Beaucoup d'équipes l'adorent pour sa simplicité. Monte-le, casse un réplica, fais une sauvegarde, et mesure ; puis retire-le proprement, comme Rook. J'attends des chiffres et un avis.

**Objectifs pédagogiques**
- Comprendre l'architecture de Longhorn (gestionnaire, moteur, réplicas, *instance managers*) et ses prérequis de nœud.
- Installer Longhorn 1.13 sur des disques dédiés, sans qu'il devienne la classe par défaut.
- Observer la reconstruction d'un réplica ; distinguer instantané Longhorn et sauvegarde Longhorn vers S3.
- Retirer Longhorn par sa procédure officielle et nettoyer les nœuds.

**Prérequis** : M16-E14 (Rook démonté), M16-E10 (CRD d'instantanés).
**Durée indicative** : 3 h.

**Contexte technique**
- Disques : 32 Go par travailleur sur `hdd-bulk`, `scsi2`, série `k8s-w0N-lh`, formaté en ext4 (étiquette `longhorn`) et monté sur `/var/lib/longhorn` (chemin par défaut de Longhorn) par Ansible.
- Prérequis des nœuds (moteur V1, celui qu'on utilise) : `open-iscsi` avec `iscsid` actif et le module `iscsi_tcp`, client NFSv4 (`nfs-common`), `cryptsetup`, `dmsetup`, propagation des montages. Debian 13 fournit `open-iscsi` 2.1.11 : la documentation 1.13 met en garde contre la **2.1.12**, à ne jamais installer. L'outil `longhornctl` 1.13.0 (binaire publié dans les versions de `longhorn/cli`) sait contrôler ces prérequis.
- Longhorn 1.13.0 : chart `longhorn/longhorn` (`https://charts.longhorn.io`), espace `longhorn-system` en PSA `privileged` ; Kubernetes 1.34 au minimum. Par défaut, le chart crée une classe `longhorn` **marquée par défaut** : à empêcher.
- Sauvegarde « en aperçu » : identité `longhorn-essai` et compartiment `longhorn-essai` sur `s3-01` (rôle `seaweedfs`, MR), clés dans `~/.config/workbook/s3-longhorn-essai.env` ; Secret `longhorn-s3` dans `longhorn-system` (clés `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINTS`, `AWS_CERT` = CA MédiSphère) ; cible de sauvegarde de la forme `s3://<compartiment>@<région>/`. Identité et compartiment sont **supprimés** en fin d'exercice.
- Interface : `kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80` depuis `adm01` ; elle n'est **pas** publiée (pas d'authentification par défaut).
- Code : `plateforme/infra` (disques), `plateforme/ansible` (rôle `longhorn_prerequis`, variable `longhorn_prerequis_etat: present|absent`, playbook `k8s-longhorn-prerequis.yml`), `plateforme/k8s` (`espaces/longhorn-system/`, `composants/longhorn/values.yaml`).

**Travail demandé**
1. **Lecture.** Lis *Longhorn → Concepts* et *Installation Requirements* (1.13). Réponds dans `~/m16/e15/journal.md` : où sont écrites les données d'un volume ? Qui réplique (le nœud du pod ou un serveur central) ? Pourquoi iSCSI ? Que change le moteur V2 et pourquoi ne l'utilise-t-on pas ici ?
2. **Disques et nœuds.** Ajoute le disque `scsi2` aux travailleurs (OpenTofu, modification en place). Écris le rôle `longhorn_prerequis` (paquets, `iscsid`, module, système de fichiers, montage ; en `absent` : démontage, effacement de la signature du seul disque `…-lh`, retrait des paquets et du service) avec un scénario Molecule ou, à défaut, un `--check --diff` documenté ; MR, application en `present`. Contrôle avec `longhornctl check preflight` (empreinte du binaire vérifiée).
3. **Installation.** `espaces/longhorn-system/00-namespace.yaml` (PSA `privileged`, justifié) et `composants/longhorn/values.yaml` (classe non par défaut, 3 réplicas, chemin des données, confirmation de suppression laissée à `false` pour l'instant) ; MR, puis :
   ```
   admin@adm01:~$ helm repo add longhorn https://charts.longhorn.io
   admin@adm01:~/src/k8s$ helm upgrade --install longhorn longhorn/longhorn --version 1.13.0 \
       -n longhorn-system -f composants/longhorn/values.yaml --wait --timeout 10m
   ```
   Vérifie les pods, les nœuds et disques vus par Longhorn (`kubectl -n longhorn-system get nodes.longhorn.io`, interface), et qu'il n'y a toujours qu'une classe par défaut.
4. **Un volume répliqué.** Dans `wb-essais`, PVC `lh-essai` (`longhorn`, 2 Gio) et un pod qui écrit en continu. Trouve ses réplicas (`kubectl -n longhorn-system get replicas.longhorn.io`) et le nœud de chacun. Sur un nœud, retrouve les fichiers du réplica sous `/var/lib/longhorn/replicas/`.
5. **Casser un réplica.** Supprime le réplica d'un nœud qui ne porte pas le pod : état du volume (`Degraded`), reconstruction, durée. L'écriture du pod s'est-elle interrompue ?
6. **Instantané et sauvegarde.** Crée une `VolumeSnapshotClass` `longhorn-snap` (instantané local, type `snap`) et prends un instantané CSI du PVC. Puis configure la cible de sauvegarde vers `longhorn-essai` et crée une **sauvegarde** Longhorn (depuis l'interface ou par une classe de type `bak`) ; regarde ce qu'elle a déposé dans le compartiment (`aws s3 ls --recursive`). Restaure-la dans un nouveau volume et compare.
7. **Mesures.** Relève l'empreinte (mémoire, pods) de `longhorn-system` et le débit d'écriture séquentielle de `lh-essai` comparé à un volume `ceph-rbd` (un simple `dd` avec `oflag=direct`, 1 Gio, trois mesures : le vrai banc d'essai est en E28). Note-les dans le journal avec le contexte (disques `hdd-bulk` contre OSD sur `ssd-lab`).
8. **Retrait.** Supprime pods, PVC, instantanés, la classe `longhorn-snap`, la cible de sauvegarde ; passe le réglage `deleting-confirmation-flag` à `true` ; `helm uninstall` (le *job* de désinstallation doit réussir) ; vérifie qu'il ne reste ni CRD `longhorn.io`, ni `CSIDriver`, ni espace. Rejoue le rôle en `absent`. Supprime l'identité et le compartiment `longhorn-essai` (MR) et le fichier `s3-longhorn-essai.env`. Retire les fichiers Longhorn de `plateforme/k8s` (MR).
9. **Avis.** Dans le journal, pour l'ADR : trois avantages et trois inconvénients de Longhorn chez MédiSphère, chiffrés.

**Critères de réussite**
- [ ] Le journal contient la reconstruction du réplica (durée, états), le contenu du compartiment après la sauvegarde, et les mesures de l'étape 7.
- [ ] L'espace `longhorn-system` n'existe plus ; aucune CRD `*.longhorn.io`, aucun `CSIDriver` `driver.longhorn.io`, aucune classe ni PV Longhorn ; aucun PVC `lh-*` dans `wb-essais`.
- [ ] Sur chaque travailleur : `/var/lib/longhorn` n'est plus monté ; le disque `k8s-w0N-lh` existe et ne porte aucune signature ; `iscsid` n'est plus actif.
- [ ] `ceph-rbd` reste la seule classe par défaut ; aucune clé `longhorn-essai` ne reste dans `~/.config/workbook/`.

**Vérification** : `lab/bin/check 16 15` (contrôle l'état **après** le retrait).

<details><summary>Indice 1</summary>

Dans les valeurs du chart : `persistence.defaultClass`, `persistence.defaultClassReplicaCount`, `defaultSettings.defaultDataPath`, `defaultSettings.deletingConfirmationFlag`. La cible de sauvegarde par défaut se règle par `defaultBackupStore.backupTarget` et `defaultBackupStore.backupTargetCredentialSecret`, ou après coup sur la ressource `BackupTarget` `default`.
</details>

<details><summary>Indice 2</summary>

Une `VolumeSnapshotClass` de Longhorn a le pilote `driver.longhorn.io` et un paramètre `type` qui vaut `snap` (instantané dans le cluster) ou `bak` (sauvegarde vers la cible). C'est le même objet Kubernetes pour deux choses très différentes.
</details>

<details><summary>Indice 3</summary>

Le *job* de désinstallation échoue tant que `deleting-confirmation-flag` vaut `false` : c'est une protection, lis son journal. Le réglage est une ressource `settings.longhorn.io` de `longhorn-system`.
</details>

---

### M16-E16 — Velero : sauvegarder des espaces de noms  `LAB` `★★`

> **Ticket PLAT-1716** — *De : Nadia Roussel*
> La semaine dernière, un développeur d'une autre équipe a lancé un `kubectl delete -f` sur le mauvais dossier. Sur notre cluster, ce serait quoi la procédure ? L'instantané etcd du M14, c'est **tout** le cluster, à une heure près, et le restaurer remet aussi à zéro tout ce que les autres ont fait depuis. Il me faut de quoi restaurer **un** espace de noms, ou même **un** objet, sans toucher au reste, avec des sauvegardes rangées hors du cluster.

**Objectifs pédagogiques**
- Comprendre ce que Velero sauvegarde (ressources de l'API, métadonnées, volumes à part) et où (emplacement de sauvegarde S3).
- Installer Velero 1.18 avec le plugin AWS vers le S3 du socle, en TLS vérifié avec la CA MédiSphère, sans secret dans un dépôt.
- Sauvegarder, planifier, filtrer, restaurer des ressources ; lire les journaux d'une sauvegarde et d'une restauration.

**Prérequis** : M05-E10 (rôle `seaweedfs`), M14-E24 (sauvegarde etcd, pour comparer), M16-E10 (classes d'instantanés, pour E17).
**Durée indicative** : 3 h.

**Contexte technique**
- S3 : identité `velero` limitée au compartiment `velero-k8s-par1` (`Read`, `Write`, `List`), ajoutés par MR dans `host_vars/s3-01/seaweedfs.yml` et le Vault (`vault.yml` de `s3-01`) ; décide et justifie le versionnage du compartiment. Clés dans `~/.config/workbook/s3-velero.env` (variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, 600) et au registre des secrets.
- Flux : les pods sortent par l'adresse de leur nœud (VLAN 40). Le flux VLAN 40 → `s3-01` TCP 8333 a été ouvert au M14 pour l'instantané etcd : vérifie qu'il couvre les travailleurs, et ajoute la ligne « Velero » à `docs/socle/matrice-flux.md`.
- Velero 1.18.4 par le chart `vmware-tanzu/velero` **12.2.1** (`https://vmware-tanzu.github.io/helm-charts`), dont la version applicative par défaut est 1.18.2 : fixe l'image `velero/velero:v1.18.4`. Plugin `velero/velero-plugin-for-aws:v1.14.4` (conteneur d'initialisation). Espace `velero` en PSA `privileged` (le `node-agent` d'E17 monte `/var/lib/kubelet/pods` du nœud).
- Emplacement de sauvegarde (BSL) : nom `s3-01`, par défaut, fournisseur `aws`, compartiment `velero-k8s-par1`, configuration `region`, `s3ForcePathStyle`, `s3Url` (`https://s3-01.par1.medisphere.internal:8333`), CA MédiSphère dans `caCert` (en base 64 : le chart 12.2.1 ne gère pas encore `caCertRef`, la voie recommandée par la documentation 1.18). Pas d'emplacement d'instantanés natif (`VolumeSnapshotLocation`) : les volumes passent par CSI et Kopia (E17).
- Identifiants : Secret `velero-s3` (clé `cloud`, au format d'un fichier d'identifiants AWS) créé par le script `outils/secrets-sauvegarde.sh` de `plateforme/k8s` à partir de `s3-velero.env`, **sans** passer par un fichier en clair ni la ligne de commande ; le chart l'utilise sans le créer (`credentials.existingSecret`).
- Fonctions activées dès l'installation (utilisées en E17) : `node-agent`, `EnableCSI`.
- CLI : `velero` 1.18.4 sur `adm01` (archive `velero-v1.18.4-linux-amd64.tar.gz` des versions GitHub, vérifiée par le fichier `CHECKSUM` publié à côté), installée par un script ou par le rôle de ton poste d'administration.
- Essais : une petite application dans `wb-essais` (Deployment `velero-essai`, ConfigMap, Secret de test, Service), puis l'espace `mediagenda-dev`.

**Travail demandé**
1. **Lecture.** Lis *Velero → How Velero works*, *Backup Storage Locations*, *Backup reference*, *Restore reference*. Réponds dans `~/m16/e16/journal.md` : que contient une sauvegarde dans le compartiment (fichiers, format) ? Qu'est-ce qui n'est **pas** sauvegardé par défaut ? Comment Velero restaure-t-il un objet qui existe déjà ? Qu'apporte Velero par rapport à l'instantané etcd, et l'inverse ?
2. **S3.** Ajoute l'identité et le compartiment par MR (`plateforme/ansible`), clés générées comme au M05, rangées sans passer par l'écran. Vérifie depuis `adm01` avec `s3-velero.env` : liste du compartiment autorisée, liste d'un autre compartiment refusée.
3. **CLI.** Installe `velero` 1.18.4 sur `adm01` (empreinte vérifiée). `velero version --client-only`.
4. **Secret et espace.** `espaces/velero/00-namespace.yaml` (PSA `privileged`, justifié) ; écris `outils/secrets-sauvegarde.sh` (sous-commande `velero` pour l'instant : lit `s3-velero.env`, crée ou met à jour `velero-s3` par `kubectl apply`, n'affiche jamais la clé, refuse si le fichier n'est pas en 600) ; MR, application, exécution.
5. **Installation.** Écris `composants/velero/values.yaml` (image, plugin, BSL `s3-01`, `caCert`, Secret existant, pas de `VolumeSnapshotLocation`, `node-agent`, `EnableCSI`, ressources) ; rends-le (`helm template … | less`) et vérifie qu'aucun secret n'y figure ; MR, puis :
   ```
   admin@adm01:~$ helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
   admin@adm01:~/src/k8s$ helm upgrade --install velero vmware-tanzu/velero --version 12.2.1 \
       -n velero -f composants/velero/values.yaml --wait
   admin@adm01:~$ velero backup-location get
   ```
   La BSL doit être `Available`. Sinon, lis le journal du déploiement `velero` (`kubectl -n velero logs deploy/velero`).
6. **Première sauvegarde.** Déploie l'application d'essai dans `wb-essais`, puis `velero backup create essai-1 --include-namespaces wb-essais --wait`. Lis `velero backup describe essai-1 --details` et `velero backup logs essai-1`. Regarde le contenu du compartiment (`aws s3 ls --recursive s3://velero-k8s-par1/`) et télécharge l'archive des ressources (`velero backup download`) : ouvre-la, trouve le Secret de test. Que conclus-tu sur la protection de ce compartiment ?
7. **Restaurations.** (a) Supprime le Deployment `velero-essai` et restaure **seulement** lui (`--include-resources`, `--selector`). (b) Modifie la ConfigMap, puis restaure-la sans la supprimer : que se passe-t-il, et que change `--existing-resource-policy update` ? (c) Supprime tout l'espace `wb-essais` **après** avoir vérifié qu'il ne contient plus rien d'utile aux autres exercices du palier, et restaure-le en entier. Pour chaque cas, `velero restore describe` et la liste des avertissements.
8. **Planification.** Crée une planification `mediagenda-dev-quotidienne` de l'espace `mediagenda-dev` (tous les jours à 02 h 30, heure de Paris : vérifie comment Velero interprète le fuseau), conservée 7 jours (`--ttl`), avec l'étiquette `medisphere.internal/sauvegarde: quotidienne`. Déclenche-la tout de suite (`velero backup create --from-schedule`). Range sa définition dans `composants/velero/planifications.yaml` (une ressource `Schedule`), MR.
9. **Ce qui manque.** Note dans le journal ce qu'il faudrait pour que cette sauvegarde serve en cas de perte de `k8s-par1` entier (cluster neuf, même nom de classes, BSL en lecture seule…) : tu le pratiqueras en E24.

**Critères de réussite**
- [ ] L'espace `velero` est en PSA `privileged` ; Velero tourne en 1.18.4 avec le plugin AWS 1.14.4 ; le `node-agent` tourne sur les trois travailleurs.
- [ ] La BSL `s3-01` est `Available` et par défaut, vers `velero-k8s-par1`, en HTTPS sans `insecureSkipTLSVerify`.
- [ ] Le Secret `velero-s3` existe ; `s3-velero.env` est en 600 ; aucune clé n'est dans `plateforme/k8s` (le check cherche les motifs de clé dans les fichiers de `composants/velero/`).
- [ ] Une sauvegarde de `wb-essais` est `Completed` et au moins trois restaurations sont `Completed` (ou `PartiallyFailed` expliqué dans le journal).
- [ ] La planification `mediagenda-dev-quotidienne` existe (TTL 168 h) et a produit au moins une sauvegarde `Completed`.

**Vérification** : `lab/bin/check 16 16`

<details><summary>Indice 1</summary>

Le fichier d'identifiants attendu par le plugin AWS est un INI à une section `[default]` avec `aws_access_key_id` et `aws_secret_access_key`. `kubectl create secret generic … --from-file=cloud=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -` le fabrique sans fichier temporaire, si l'entrée standard vient d'un `printf` alimenté par des variables lues dans le fichier `.env`.
</details>

<details><summary>Indice 2</summary>

Dans les valeurs du chart : `image.tag`, `initContainers` (le plugin copie son binaire dans le volume `plugins`), `configuration.backupStorageLocation` (une liste), `configuration.features`, `credentials.useSecret` et `credentials.existingSecret`, `snapshotsEnabled`, `deployNodeAgent`. `caCert` attend le PEM **encodé en base 64** (`base64 -w0`).
</details>

<details><summary>Indice 3</summary>

Une planification Velero accepte une expression cron à cinq champs, éventuellement précédée de `CRON_TZ=<fuseau>`. Une restauration ne remplace jamais un objet existant par défaut : elle l'ignore et le signale.
</details>

---

### M16-E17 — Velero : volumes, Kopia et snapshots CSI  `LAB` `★★★`

> **Ticket SEC-1717** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> Une sauvegarde qui ne contient que des fichiers YAML ne sauve pas les données. Et un instantané qui reste dans le même Ceph que l'original n'est pas une sauvegarde : si `ceph-par1` brûle, il brûle avec. Je veux savoir, volume par volume, **où** sont les copies et combien de temps on met à les relire. Et je veux la preuve d'une restauration, pas une capture d'écran de l'interface.

**Objectifs pédagogiques**
- Distinguer les trois façons qu'a Velero de traiter un volume : sauvegarde de fichiers par `node-agent` (Kopia), instantané CSI laissé dans le stockage, instantané CSI **déplacé** vers S3 (*data mover*).
- Choisir la méthode par volume (annotations, options de sauvegarde, valeurs par défaut) et comprendre les risques de cohérence.
- Restaurer des volumes et prouver l'intégrité des données.

**Prérequis** : M16-E16, M16-E10.
**Durée indicative** : 3 h.

**Contexte technique**
- Velero 1.18 n'utilise plus Restic pour sauvegarder : la sauvegarde de fichiers (*fs-backup*) et le *data mover* passent par **Kopia** (dépôt par espace de noms sous le préfixe `kopia/` du compartiment), exécuté par le `node-agent` et des pods de déplacement de données. Le mot de passe des dépôts Kopia est dans le Secret `velero-repo-credentials` de `velero`, créé à l'installation avec une valeur par défaut : on le remplace **avant** la première sauvegarde de volumes, par une valeur tirée au hasard et rangée dans le Vault `critique` (la changer ensuite rendrait illisibles les dépôts existants).
- Instantanés CSI : Velero choisit, pour chaque pilote, la `VolumeSnapshotClass` qui porte l'étiquette `velero.io/csi-volumesnapshot-class: "true"` ; pose-la sur `ceph-rbd-snap` et `cephfs-snap` (dans leurs fichiers de `composants/ceph-csi/classes/`).
- Application d'essai `vol-essai` dans `wb-essais` : un StatefulSet d'un réplica avec deux volumes, `donnees-rbd` (`ceph-rbd`, 1 Gio) et `donnees-fs` (`cephfs`, 1 Gio), chacun rempli de 200 fichiers aléatoires dont tu gardes la liste d'empreintes (`sha256sum` dans un fichier `MANIFESTE` à la racine du volume).
- Sauvegardes attendues (noms) : `vol-fs` (sauvegarde de fichiers des deux volumes), `vol-snap` (instantanés CSI sans déplacement), `vol-dm` (instantanés CSI déplacés vers S3).

**Travail demandé**
1. **Lecture.** Lis *File System Backup*, *CSI Snapshot Support* et *CSI Snapshot Data Movement* (1.18). Réponds dans `~/m16/e17/journal.md` : pour chacune des trois méthodes, où sont les données à la fin de la sauvegarde ? Qui lit les blocs, et depuis quoi (volume en service, instantané) ? Laquelle donne une copie cohérente d'un volume en cours d'écriture ? Que devient l'instantané CSI d'une sauvegarde `vol-dm` une fois la copie terminée ?
2. **Mot de passe des dépôts.** Remplace la valeur de `velero-repo-credentials` (clé `repository-password`) par une valeur aléatoire, rangée au Vault `critique` et au registre des secrets ; ajoute ce cas à `outils/secrets-sauvegarde.sh` (sous-commande `velero-kopia`, qui refuse de changer un mot de passe si un dépôt Kopia existe déjà : `kubectl -n velero get backuprepositories`).
3. **Étiquettes.** Pose l'étiquette Velero sur les deux classes d'instantanés (MR).
4. **Application d'essai.** Déploie `vol-essai`, remplis les volumes, écris les manifestes d'empreintes.
5. **Sauvegarde de fichiers.** `vol-fs` : sauvegarde de `wb-essais` en *fs-backup* pour les volumes de `vol-essai` (annotation `backup.velero.io/backup-volumes` ou option `--default-volumes-to-fs-backup` : choisis et justifie). Suis les `PodVolumeBackup` (`kubectl -n velero get podvolumebackups -w`) ; regarde le préfixe `kopia/wb-essais/` du compartiment.
6. **Instantanés sans déplacement.** `vol-snap` : sauvegarde avec instantanés CSI (`--snapshot-volumes`), **sans** déplacement. Où sont les données ? Regarde les `VolumeSnapshot` et `VolumeSnapshotContent` créés, et côté Ceph les images de `k8s-rbd`. Que se passe-t-il si tu supprimes la sauvegarde (`velero backup delete vol-snap`) ?
7. **Déplacement des données.** `vol-dm` : instantanés CSI déplacés vers S3 (`--snapshot-move-data`). Suis les `DataUpload` (`-o wide` : octets transférés, octets incrémentaux), puis lance une seconde sauvegarde `vol-dm-2` après avoir modifié 10 fichiers : compare les octets incrémentaux.
8. **Restaurations prouvées.** Pour `vol-fs` et `vol-dm` : supprime le StatefulSet **et** ses PVC, restaure, puis vérifie toutes les empreintes depuis le pod restauré (`sha256sum -c MANIFESTE`). Mesure chaque durée. Suis les `PodVolumeRestore` ou `DataDownload`.
9. **Cohérence.** Réponds dans le journal : pourquoi une sauvegarde de fichiers d'un PostgreSQL en marche n'est-elle pas une sauvegarde de la base ? Que proposent les *hooks* Velero (`pre.hook.backup.velero.io/command`) et pourquoi, pour PostgreSQL, préférera-t-on la sauvegarde propre à l'opérateur (E19) ? Quelle méthode retiens-tu pour Valkey, pour les fichiers de MédiDoc, pour une base ?
10. **Planification.** Mets à jour `mediagenda-dev-quotidienne` pour que ses volumes partent hors de Ceph (choisis la méthode), MR ; déclenche-la et vérifie.

**Critères de réussite**
- [ ] Le mot de passe des dépôts Kopia est au registre des secrets ; `outils/secrets-sauvegarde.sh` (sur `main` de `plateforme/k8s`) gère la sous-commande `velero-kopia` (le check ne lit pas les Secrets : la valeur elle-même relève de l'auto-évaluation).
- [ ] `ceph-rbd-snap` et `cephfs-snap` portent l'étiquette `velero.io/csi-volumesnapshot-class: "true"`.
- [ ] Les sauvegardes `vol-fs` et `vol-dm` sont `Completed` ; `vol-fs` a des `PodVolumeBackup` terminés, `vol-dm` des `DataUpload` terminés ; au moins une `DataDownload` ou un `PodVolumeRestore` est terminé.
- [ ] `vol-essai` restauré tourne ; le journal contient les deux vérifications `sha256sum -c` (« OK » partout) et les durées.
- [ ] La planification `mediagenda-dev-quotidienne` déplace les volumes (méthode visible dans sa définition).

**Vérification** : `lab/bin/check 16 17`

<details><summary>Indice 1</summary>

Sans annotation ni option, un volume CSI dont la classe a un instantané étiqueté pour Velero est sauvegardé par instantané quand `--snapshot-volumes` est vrai (c'est le défaut). `--default-volumes-to-fs-backup` bascule tous les volumes sur la sauvegarde de fichiers ; `backup.velero.io/backup-volumes-excludes` en écarte.
</details>

<details><summary>Indice 2</summary>

Le *data mover* crée, dans l'espace `velero`, un PVC à partir de l'instantané puis un pod qui le lit : il faut que la classe sache créer un volume depuis un instantané (c'est le cas de `ceph-rbd` et de `cephfs` depuis E10) et que le quota de `velero`, s'il y en a un, le permette.
</details>

<details><summary>Indice 3</summary>

Pour la restauration, Velero recrée le PVC **avant** le pod. Si un PVC de même nom existe encore (suppression bloquée par un *finalizer* `kubernetes.io/pvc-protection` tant qu'un pod l'utilise), la restauration du volume est ignorée : vérifie que tout a vraiment disparu avant de restaurer.
</details>

---

### M16-E18 — CloudNativePG : la base de MédiAgenda  `LAB` `★★`

> **Ticket DEV-1718** — *De : Julien Petit*
> En recette, notre PostgreSQL est toujours le conteneur « jetable » du M14 : un redémarrage, et on perd tout. Je ne veux pas apprendre à administrer PostgreSQL en StatefulSet maison. On m'a parlé de CloudNativePG : trois instances, bascule automatique, l'application qui suit sans qu'on lui change d'adresse. Peux-tu le mettre en place pour la recette et rebrancher l'API dessus ?

**Objectifs pédagogiques**
- Comprendre ce qu'apporte un opérateur PostgreSQL (CNPG) : instances, services `-rw`/`-ro`/`-r`, Secrets générés, réplication, PDB, mises à jour.
- Installer l'opérateur et le plugin Barman Cloud (pour E19) dans `cnpg-system`, avec des images tirées par Harbor.
- Déclarer un cluster `mediagenda-db` de trois instances sur `ceph-rbd` qui respecte les politiques de l'espace (PSA `restricted`, images, politiques réseau, quotas).
- Rebrancher MédiAgenda sur la nouvelle base.

**Prérequis** : M15 (cert-manager, politiques réseau de `mediagenda-recette`), M14-E18 (politique d'admission des images), M16-E06.
**Durée indicative** : 3 h.

**Contexte technique**
- Opérateur : chart `cnpg/cloudnative-pg` **0.29.1** (opérateur 1.30.1, dépôt `https://cloudnative-pg.github.io/charts`), nom de *release* `cnpg`, espace `cnpg-system`. Plugin : chart `cnpg/plugin-barman-cloud` **0.8.1** (plugin 0.15.1), *release* `plugin-barman-cloud`, **dans le même espace** que l'opérateur (exigence du plugin) ; il crée ses certificats TLS internes par cert-manager.
- Images : la politique d'admission de `mediagenda-*` exige `registry.par1.medisphere.internal/`. Les pods PostgreSQL contiennent l'image PostgreSQL **et** l'image de l'opérateur (conteneur d'initialisation), et plus tard celle du *sidecar* du plugin : les trois doivent donc passer par le cache `ghcr` de Harbor, par les valeurs des charts et par `imageName` du `Cluster` (`…/ghcr/cloudnative-pg/postgresql:18.6-minimal-trixie`).
- Cluster `mediagenda-db`, espace `mediagenda-recette` : 3 instances, PostgreSQL 18.6, `storage` 5 Gio sur `ceph-rbd`, base `mediagenda` dont le propriétaire est `mediagenda` (initialisation `initdb`), une instance par travailleur au plus (anti-affinité **obligatoire**), réplication synchrone d'au moins une réplique, ressources déclarées (les pods doivent tenir dans le quota et la LimitRange du M14). Si le *taint* `dedie=bdd:NoSchedule` du M14-E14 est toujours sur `k8s-w03`, les instances doivent le tolérer.
- Services créés par CNPG : `mediagenda-db-rw` (primaire), `mediagenda-db-ro` (répliques), `mediagenda-db-r` (toutes) ; Secret `mediagenda-db-app` (clés `username`, `password`, `uri`, `host`, `dbname`…).
- Réseau : `mediagenda-recette` est en refus par défaut (M15). Les instances doivent joindre l'API Kubernetes (le gestionnaire d'instance la consulte), les autres instances (5432), et seront jointes par l'opérateur (`cnpg-system`, ports 8000 et 5432) et par l'API MédiAgenda (5432). E19 ajoutera la sortie vers `s3-01:8333`. Fichier : `espaces/mediagenda-recette/40-reseau-postgresql.yaml`.
- Plugin `kubectl cnpg` sur `adm01` par krew (`kubectl krew install cnpg`) : même version que l'opérateur.
- Le PostgreSQL « jetable » du M14 et son Service sont retirés une fois l'API basculée.

**Travail demandé**
1. **Lecture.** Lis *CloudNativePG → Architecture*, *Instance pod*, *Service management*, *Connecting from an application*, *Replication* (section synchrone) de la documentation 1.30. Réponds dans `~/m16/e18/journal.md` : qui décide de la bascule ? Comment l'application suit-elle le primaire sans changer d'adresse ? Que garantit `dataDurability: required` et que coûte-t-il ? Pourquoi CNPG n'utilise-t-il pas de StatefulSet ?
2. **Opérateur et plugin.** Écris `composants/cloudnative-pg/values.yaml` et `composants/plugin-barman-cloud/values.yaml` (images par Harbor, rien d'autre que nécessaire) ; MR ; puis :
   ```
   admin@adm01:~$ helm repo add cnpg https://cloudnative-pg.github.io/charts
   admin@adm01:~/src/k8s$ helm upgrade --install cnpg cnpg/cloudnative-pg --version 0.29.1 \
       -n cnpg-system --create-namespace -f composants/cloudnative-pg/values.yaml --wait
   admin@adm01:~/src/k8s$ helm upgrade --install plugin-barman-cloud cnpg/plugin-barman-cloud --version 0.8.1 \
       -n cnpg-system -f composants/plugin-barman-cloud/values.yaml --wait
   admin@adm01:~$ kubectl krew install cnpg && kubectl cnpg version
   ```
   (Range l'espace `cnpg-system` dans `espaces/` comme les autres.) Vérifie les CRD (`postgresql.cnpg.io`, `barmancloud.cnpg.io`), les certificats émis pour le plugin (`kubectl -n cnpg-system get certificate`) et que le déploiement du plugin est prêt.
3. **Réseau.** Écris les politiques de l'étape « Réseau » (une politique d'entrée et une de sortie au moins ; pour l'API Kubernetes, la politique standard ne suffit pas avec Cilium : regarde ce qu'offre `CiliumNetworkPolicy`). MR, application.
4. **Le cluster.** Écris `espaces/mediagenda-recette/50-mediagenda-db.yaml` ; MR ; application. Suis la création (`kubectl cnpg status mediagenda-db -n mediagenda-recette`, pods, *jobs* `-initdb` et `-join`, PVC). Si un pod est refusé (admission, quota, politique), lis l'événement et corrige le manifeste, pas la politique.
5. **Exploration.** `kubectl cnpg psql mediagenda-db -n mediagenda-recette` : `SELECT pg_is_in_recovery();`, `SELECT application_name, sync_state FROM pg_stat_replication;`, `SHOW synchronous_standby_names;`. Regarde les PDB créés, les étiquettes des pods (`cnpg.io/instanceRole`), les points d'accès des trois services.
6. **Bascule de l'application.** Modifie le Deployment de l'API MédiAgenda (celui du M14, dans `plateforme/k8s` ou dans ton dépôt de manifestes de recette) : `MEDIAGENDA_DB_URL` vient de la clé `uri` du Secret `mediagenda-db-app`. Applique la migration du schéma (`python -m mediagenda.migrate`) par un Job avant de redémarrer l'API. Vérifie `/pret`, crée trois rendez-vous par l'API publiée (`https://mediagenda-recette.apps.par1.medisphere.internal`) et retrouve-les dans la base.
7. **Retrait du jetable.** Supprime l'ancien PostgreSQL du M14 et son Service (MR). Vérifie que plus rien ne le référence.
8. **Quotas.** Relève ce que consomme le cluster dans le quota de `mediagenda-recette` (`kubectl describe quota -n mediagenda-recette`) et note-le pour E20.

**Critères de réussite**
- [ ] L'opérateur 1.30.1 et le plugin Barman Cloud 0.15.1 tournent dans `cnpg-system`, avec des images de `registry.par1.medisphere.internal` ; `kubectl cnpg` est installé.
- [ ] `mediagenda-db` est en état sain avec 3 instances prêtes, sur trois nœuds différents, en PostgreSQL 18 (image de Harbor), sur des PVC `ceph-rbd` ; au moins une réplique synchrone.
- [ ] Les politiques réseau de l'étape 3 existent ; l'API MédiAgenda lit `MEDIAGENDA_DB_URL` dans `mediagenda-db-app` et répond 200 sur `/pret`.
- [ ] La table `rendez_vous` de `mediagenda` contient au moins trois lignes ; l'ancien PostgreSQL jetable n'existe plus dans `mediagenda-recette`.

**Vérification** : `lab/bin/check 16 18`

<details><summary>Indice 1</summary>

Dans les valeurs du chart de l'opérateur, `image.repository` sert aussi à fabriquer la variable `OPERATOR_IMAGE_NAME` : c'est elle que l'opérateur injecte dans les pods PostgreSQL. Dans celles du plugin, il y a `image` et `sidecarImage`, chacune avec `registry` et `repository`.
</details>

<details><summary>Indice 2</summary>

Dans le `Cluster` : `affinity.enablePodAntiAffinity`, `affinity.podAntiAffinityType`, `affinity.topologyKey`, `affinity.tolerations` ; `postgresql.synchronous` (`method`, `number`, `dataDurability`) ; `bootstrap.initdb` (`database`, `owner`) ; `resources`. Lis `kubectl explain cluster.spec --api-version=postgresql.cnpg.io/v1` champ par champ.
</details>

<details><summary>Indice 3</summary>

Les pods d'instance portent l'étiquette `cnpg.io/cluster: mediagenda-db` (y compris ceux des *jobs* d'initialisation) : c'est un bon sélecteur pour les politiques. Avec Cilium, l'API Kubernetes est une entité (`kube-apiserver`) et non une adresse : une règle `ipBlock` sur les adresses des nœuds ne l'atteint pas.
</details>

**Pour aller plus loin** (facultatif) : exige TLS vérifié entre l'API et la base (`sslmode=verify-full`, CA du Secret `mediagenda-db-ca`) et compare avec la connexion par défaut de libpq (`sslmode=prefer`).

---

### M16-E19 — CloudNativePG : sauvegarde continue et restauration à un instant donné  `LAB` `★★★`

> **Ticket SEC-1719** — *De : Sophie Laurent* — *Copie : Julien Petit*
> Trois instances, c'est de la disponibilité, pas une sauvegarde : un `DELETE` sans `WHERE` est répliqué en une milliseconde sur les trois. Pour la recette, et demain pour la production, j'exige : un archivage continu des journaux de transactions hors du cluster, une sauvegarde complète chaque nuit, une rétention de 14 jours, et la preuve qu'on sait remettre la base **telle qu'elle était à 14 h 32** dans un cluster à part, sans toucher à celui qui tourne.

**Objectifs pédagogiques**
- Configurer l'archivage continu des WAL et des sauvegardes de base avec le **plugin Barman Cloud** (`ObjectStore`, `.spec.plugins`) au lieu de `barmanObjectStore`, déprécié dans CNPG 1.30.
- Planifier des sauvegardes (`ScheduledBackup`), fixer une rétention, vérifier l'état de l'archivage.
- Restaurer à un instant donné (PITR) dans un nouveau cluster et vérifier le résultat.

**Prérequis** : M16-E18.
**Durée indicative** : 3 h 30.

**Contexte technique**
- S3 : identité `cnpg`, compartiment `cnpg-k8s-par1` (`Read`, `Write`, `List`), MR sur le rôle `seaweedfs` ; clés dans `~/.config/workbook/s3-cnpg.env`. Secret `cnpg-s3` dans `mediagenda-recette` (clés `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY`) et Secret `medisphere-ca` (clé `ca.crt`, CA MédiSphère), créés par `outils/secrets-sauvegarde.sh` (sous-commande `cnpg`).
- `ObjectStore` `cnpg-s3` (`barmancloud.cnpg.io/v1`) dans `mediagenda-recette` : `destinationPath` `s3://cnpg-k8s-par1/`, `endpointURL` `https://s3-01.par1.medisphere.internal:8333`, `endpointCA`, identifiants, compression des WAL et des données, `retentionPolicy` de 14 jours, ressources du *sidecar*. Le champ `serverName` de l'`ObjectStore` doit rester **vide** : le nom de serveur (par défaut le nom du cluster) se règle, si besoin, dans les paramètres du plugin côté `Cluster`.
- Le `Cluster` déclare le plugin `barman-cloud.cloudnative-pg.io` avec `isWALArchiver: true` et le paramètre `barmanObjectName: cnpg-s3`. Le modifier redémarre les instances une à une (le primaire en dernier, par bascule).
- Sauvegarde planifiée : `ScheduledBackup` `mediagenda-db-quotidienne`, méthode `plugin`, tous les jours à 01 h 15 ; l'expression cron de CNPG a **six** champs (secondes en tête).
- Restauration : nouveau cluster `mediagenda-db-pitr` dans `mediagenda-recette`, **une** instance, amorcé par `bootstrap.recovery` depuis un `externalClusters` qui lit `cnpg-s3` avec `serverName: mediagenda-db`, cible `recoveryTarget.targetTime` avec un fuseau explicite. Il n'archive **pas** ses propres WAL (sinon il écrirait dans le même compartiment sous un autre nom de serveur : à faire exprès, jamais par accident). Il est supprimé après vérification et après le passage du check.
- Réseau : la sortie des instances (et des pods de restauration) vers 10.10.20.14:8333 s'ajoute à la politique d'E18.
- Supervision provisoire : conditions `ContinuousArchiving` et `LastBackupSucceeded` du `Cluster`, statut `serverRecoveryWindow` de l'`ObjectStore`, `kubectl cnpg status`.

**Travail demandé**
1. **Lecture.** Lis la documentation du plugin Barman Cloud 0.15 (*Usage*, *Object Store Providers*, *Retention Policies*, *Migration from in-tree*) et *Recovery* de CNPG 1.30. Réponds dans `~/m16/e19/journal.md` : qui envoie les WAL vers S3, et depuis quel conteneur ? Que contient une sauvegarde de base, comment est-elle prise sans arrêter le primaire ? Comment CNPG choisit-il la sauvegarde de départ d'une restauration à un instant donné ? Que se passe-t-il pour le primaire si l'archivage échoue pendant des heures ?
2. **S3 et secrets.** Identité et compartiment (MR), fichier `s3-cnpg.env`, sous-commande `cnpg` de `secrets-sauvegarde.sh`, Secrets créés. Ajoute la sortie vers `s3-01` à la politique réseau des instances.
3. **ObjectStore et archivage.** Écris `espaces/mediagenda-recette/60-cnpg-s3.yaml` et ajoute le plugin au `Cluster` ; MR, application. Suis le redémarrage des instances. Vérifie : condition `ContinuousArchiving` à `True`, préfixe `mediagenda-db/wals/` dans le compartiment. Force un changement de WAL (`SELECT pg_switch_wal();` dans `kubectl cnpg psql`) et retrouve le fichier archivé.
4. **Sauvegardes.** Lance une sauvegarde à la demande (`kubectl cnpg backup … --method=plugin --plugin-name=barman-cloud.cloudnative-pg.io`), suis la ressource `Backup` jusqu'à `completed`. Écris `espaces/mediagenda-recette/70-mediagenda-db-sauvegarde.yaml` (`ScheduledBackup`), MR, application ; vérifie la prochaine exécution prévue. Regarde `status.serverRecoveryWindow` de `cnpg-s3`.
5. **Préparer l'incident.** Crée dix rendez-vous par l'API. Note l'heure exacte (avec fuseau) **T**. Attends une minute, puis, dans `kubectl cnpg psql`, supprime tous les rendez-vous d'un praticien (`DELETE FROM rendez_vous WHERE praticien = '…';`) et crée-en deux nouveaux. Force un changement de WAL.
6. **Restaurer à T.** Écris `~/m16/e19/mediagenda-db-pitr.yaml` (une instance, mêmes images, `ceph-rbd`, récupération depuis `cnpg-s3` jusqu'à T). Applique. Suis le *job* de récupération (`-full-recovery`), son journal (quelle sauvegarde de base, quels WAL), jusqu'à l'instance prête.
7. **Vérifier.** Compare `mediagenda-db` et `mediagenda-db-pitr` : les rendez-vous supprimés sont-ils revenus ? Les deux créés après T sont-ils absents ? Note les heures et le temps total de restauration (du `kubectl apply` à la première requête réussie).
8. **Réparer sans tout restaurer.** Explique dans le journal (et fais-le) comment réinjecter **seulement** les lignes perdues dans `mediagenda-db` depuis `mediagenda-db-pitr` (`pg_dump --data-only --table` avec un filtre, ou `\copy`), sans écraser ce qui a été fait depuis.
9. **Nettoyage.** Après le passage du check : supprime `mediagenda-db-pitr` et ses PVC. Explique pourquoi ses WAL n'ont pas été archivés et ce qu'il aurait fallu changer si l'on voulait le garder comme nouveau primaire.
10. **Runbook.** Écris **RB-162** (`docs/kubernetes/stockage/runbooks/RB-162-restaurer-postgresql-instant-donne.md` dans `plateforme/medisphere`, format des runbooks du socle) à partir de ce que tu viens de faire : qualifier l'instant et la fenêtre de restauration, créer le cluster d'enquête, vérifier avec l'équipe, réparer (réinjection sélective ou bascule vers la base restaurée), clôturer, gestes interdits, escalade. Il servira tel quel en E34.

**Critères de réussite**
- [ ] L'`ObjectStore` `cnpg-s3` est en HTTPS avec `endpointCA`, rétention `14d`, sans `serverName` ; le `Cluster` `mediagenda-db` utilise le plugin comme archiveur de WAL et n'a **pas** de `spec.backup.barmanObjectStore`.
- [ ] La condition `ContinuousArchiving` de `mediagenda-db` est `True` ; au moins une `Backup` en méthode `plugin` est terminée ; `serverRecoveryWindow` de `mediagenda-db` est renseigné.
- [ ] La `ScheduledBackup` `mediagenda-db-quotidienne` existe (six champs, méthode `plugin`).
- [ ] `mediagenda-db-pitr` existe (au moment du check), a été amorcé par `recovery` avec un `targetTime` à fuseau explicite, et sa table `rendez_vous` diffère de celle de `mediagenda-db` comme attendu (le journal le montre).
- [ ] La politique réseau des instances autorise la sortie vers `s3-01` sur le seul port 8333.
- [ ] RB-162 est sur `main` de `plateforme/medisphere` (il cite `targetTime` et la réinjection sélective).

**Vérification** : `lab/bin/check 16 19`

<details><summary>Indice 1</summary>

Pour la clé `endpointCA`, l'`ObjectStore` attend une référence de Secret (`name`, `key`). Pour la compression, regarde les sous-objets `wal` et `data` de `configuration` (même schéma que l'ancien `barmanObjectStore`).
</details>

<details><summary>Indice 2</summary>

Une `Backup` ou une `ScheduledBackup` par plugin a `method: plugin` et `pluginConfiguration.name`. Sans `method`, CNPG 1.30 prend encore la méthode intégrée (dépréciée), qui échouera faute de `barmanObjectStore`.
</details>

<details><summary>Indice 3</summary>

Pour la restauration, `externalClusters[].plugin` a la même forme que `spec.plugins[]` (nom du plugin, `parameters` avec `barmanObjectName` et `serverName`) ; `bootstrap.recovery.source` désigne cet `externalClusters` par son nom. Une heure sans fuseau est lue en UTC.
</details>

**Pour aller plus loin** (facultatif) : lis la page *Volume snapshots* de CNPG : une sauvegarde de base par instantané CSI (`method: volumeSnapshot`, classe `ceph-rbd-snap`) plus les WAL du plugin donne-t-elle une restauration plus rapide ? Où seraient alors les données de base ?

---

### M16-E20 — Quotas de stockage et classes par équipe  `LAB` `★★`

> **Ticket PLAT-1720** — *De : Claire Morel* — *Copie : Julien Petit*
> Le stockage Ceph n'est pas infini, et l'équipe MédiAgenda n'est que la première. Je veux des plafonds par équipe et par classe (combien de gigaoctets, combien de volumes, combien d'instantanés), et je ne veux pas qu'une équipe puisse demander une classe qui ne lui est pas destinée — en particulier `ceph-rbd-retain`, dont les volumes survivent à leur PVC et finissent oubliés. Que ce soit visible : un refus doit dire **pourquoi**.

**Objectifs pédagogiques**
- Poser des quotas de stockage globaux et par classe (`<classe>.storageclass.storage.k8s.io/requests.storage`, `…/persistentvolumeclaims`), et des quotas d'objets (`count/volumesnapshots.snapshot.storage.k8s.io`).
- Encadrer la taille des PVC par une `LimitRange`.
- Restreindre les classes autorisées par espace avec une `ValidatingAdmissionPolicy` (CEL), sans donner à l'équipe le moyen de lever la restriction.

**Prérequis** : M14-E10 (quotas des espaces `mediagenda-*`), M14-E18 (VAP), M16-E18.
**Durée indicative** : 2 h.

**Contexte technique**
- Les espaces `mediagenda-dev` et `mediagenda-recette` ont déjà un quota `quota-equipe` (processeur, mémoire, objets) et une LimitRange `limites-defaut` (M14-E10). Ajoute un quota séparé `quota-stockage` et une LimitRange `limites-pvc` dans chacun : `espaces/<espace>/30-quota-stockage.yaml`.
- Plafonds décidés par Claire :

  | | `mediagenda-dev` | `mediagenda-recette` |
  |---|---|---|
  | Stockage total demandé | 10 Gio | 40 Gio |
  | dont `ceph-rbd` | 10 Gio | 30 Gio |
  | dont `cephfs` | 2 Gio | 10 Gio |
  | dont `ceph-rbd-retain` | 0 | 0 |
  | Nombre de PVC | 10 | 20 |
  | Nombre d'instantanés | 5 | 20 |
  | Taille d'un PVC | 1 à 5 Gio | 1 à 10 Gio |

- Classes autorisées : chaque espace d'équipe (étiquette `medisphere.internal/equipe`) porte une **annotation** `medisphere.internal/classes-stockage` (liste séparée par des virgules, ex. `ceph-rbd,cephfs`). Une annotation d'espace ne peut être modifiée que par qui peut modifier l'objet `Namespace` (cluster), ce que les groupes `medisphere:mediagenda-devs` ne peuvent pas (M14-E11) ; une ConfigMap dans l'espace, elle, serait modifiable par l'équipe. La politique : `admission/classes-stockage.yaml` (une `ValidatingAdmissionPolicy` `classes-stockage` et sa liaison), sur la création des PVC, avec un message qui cite la classe demandée et les classes autorisées.
- Le contrôleur d'admission `DefaultStorageClass` (mutant) passe **avant** les politiques de validation : un PVC sans classe arrive à la VAP avec la classe par défaut déjà renseignée.
- Les PVC créés par un opérateur (CNPG, StatefulSet, Velero en restauration) passent aussi par l'admission.

**Travail demandé**
1. Lis *Resource Quotas* (section *Storage Resource Quota*), *Limit Ranges* (type `PersistentVolumeClaim`) et *Validating Admission Policy* (`namespaceObject`, `messageExpression`, `validationActions`). Note dans `~/m16/e20/journal.md` : qu'est-ce qu'un quota compte pour un PVC (demandé ou réellement occupé) ? Un PVC agrandi (E11) est-il recompté ?
2. Calcule, avant d'écrire, ce que `mediagenda-recette` consomme déjà (E18 : instances PostgreSQL, Valkey) et vérifie que les plafonds le permettent. Que se passerait-il pour `mediagenda-db` si le quota était trop bas au moment d'une bascule ou d'un agrandissement ?
3. Écris les quotas et LimitRanges des deux espaces ; MR, application ; `kubectl describe quota quota-stockage -n mediagenda-dev`.
4. Écris la VAP et sa liaison ; pose les annotations (`ceph-rbd,cephfs` pour les deux espaces) ; MR, application. Commence avec `validationActions: [Warn, Audit]`, regarde ce qu'elle aurait refusé, puis passe en `Deny`.
5. Essais dans `mediagenda-dev`, en te faisant passer pour Julien (`--as=julien.petit --as-group=medisphere:mediagenda-devs`) : PVC de 20 Gio ; PVC sur `ceph-rbd-retain` ; PVC sans classe ; PVC `storageClassName: ""` ; onzième PVC ; sixième instantané ; modification de l'annotation de l'espace. Pour chaque essai, note **qui** refuse (LimitRange, quota, VAP, RBAC) et le message exact.
6. Vérifie que `mediagenda-db` peut toujours créer une instance (supprime le PVC et le pod d'une réplique avec `kubectl cnpg destroy mediagenda-db <N> -n mediagenda-recette` et regarde CNPG la recréer).
7. Documente les plafonds et la procédure de demande d'augmentation dans `docs/kubernetes/stockage/quotas.md` (MR).

**Critères de réussite**
- [ ] `quota-stockage` existe dans les deux espaces avec les valeurs du tableau (stockage total, par classe, nombre de PVC, nombre d'instantanés) ; `limites-pvc` borne la taille des PVC.
- [ ] La VAP `classes-stockage` est liée en `Deny` aux espaces portant `medisphere.internal/equipe` ; les deux espaces portent l'annotation `ceph-rbd,cephfs`.
- [ ] La politique refuse `ceph-rbd-retain` dans les espaces d'équipe (le check, en lecture seule, examine la politique, sa liaison et les annotations ; tes essais réels sont dans le journal).
- [ ] `mediagenda-db` a toujours 3 instances prêtes après l'étape 6.
- [ ] `docs/kubernetes/stockage/quotas.md` est sur `main` ; le journal contient le tableau des refus de l'étape 5.

**Vérification** : `lab/bin/check 16 20`

<details><summary>Indice 1</summary>

Dans une VAP, `object.spec.storageClassName` peut être absent ou vide ; `namespaceObject.metadata.annotations` est une table qui peut ne pas contenir la clé (`in`, `has()`). La fonction `split(',')` des chaînes est disponible dans le CEL de Kubernetes.
</details>

<details><summary>Indice 2</summary>

Une ressource de quota par classe s'écrit `<nom-de-classe>.storageclass.storage.k8s.io/requests.storage`. Un quota d'objets pour une ressource d'un autre groupe s'écrit `count/<ressource>.<groupe>`.
</details>

---

### M16-E21 — Revue : les manifestes *stateful* du stagiaire  `REV` `★★`

> **Ticket PLAT-1721** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas a préparé l'environnement de développement de MédiDoc (`medidoc-dev`) : une classe « rapide », une base PostgreSQL maison en StatefulSet « en attendant », une base CNPG avec sauvegarde, une planification Velero. Il dit que « tout est vert sur son cluster kind ». Fais-lui une vraie revue avant qu'on l'applique sur `k8s-par1` : chaque défaut, sa gravité, ce qu'il casserait **chez nous**, la correction.

**Objectifs pédagogiques**
- Relire des manifestes de stockage et de données comme ils s'appliqueront réellement : classes, modes d'accès, StatefulSet, opérateur PostgreSQL, sauvegardes.
- Repérer les défauts de données (perte, incohérence), de sécurité (secrets, identités Ceph), d'exploitation (classe par défaut, API dépréciées, planifications).
- Produire des corrections applicables et vérifiables.

**Prérequis** : M16-E10 à M16-E20.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `ressources/E21-manifestes-lucas/` (`MR-lucas.md`, `00-storageclass.yaml`, `10-secrets.yaml`, `20-pvc-partage.yaml`, `30-postgres-maison.yaml`, `40-cnpg-cluster.yaml`, `50-objectstore.yaml`, `60-scheduledbackup.yaml`, `70-velero-schedule.yaml`). Les clés qu'ils contiennent sont **fictives**.
- Cible : `medidoc-dev` sur `k8s-par1` (PSA `restricted`, politique d'images du M14, politiques réseau du M15, VAP d'E20), Ceph externe `ceph-par1`, S3 `s3-01`.
- Livrables dans `~/m16/e21/` : `revue.md` (le tableau) et `corrige/` (les fichiers corrigés, **mêmes noms**, sauf ceux que tu proposes de supprimer, à lister dans `revue.md`).

**Travail demandé**
1. Lis tout sans rien noter. Puis réponds : combien de copies de la base PostgreSQL de MédiDoc existeront, sur quels volumes ? Où partent ses sauvegardes, et écrasent-elles quelque chose ? Que se passe-t-il quand on supprime le StatefulSet ? Quelle identité Ceph monte les volumes de la classe « rapide » ?
2. Rédige la revue en tableau dans `revue.md` : n°, fichier et ligne(s), défaut, catégorie (données, sécurité, exploitation, performance), gravité (critique, élevée, moyenne, faible), impact concret chez nous, correction.
3. Classe les défauts par ordre de traitement et justifie le premier.
4. Écris les fichiers corrigés dans `~/m16/e21/corrige/`.
5. Question de fond (dix lignes) : pour une base de développement, Lucas a-t-il raison de vouloir « une base maison en attendant » ? Que proposerais-tu, et que garderais-tu de son StatefulSet ?

**Critères de réussite**
- [ ] Au moins 12 défauts identifiés dans `revue.md`, dont tous les défauts critiques et élevés du corrigé (auto-évaluation).
- [ ] Les fichiers corrigés passent les règles du check (classe non par défaut, fonctions d'image RBD compatibles avec krbd, aucune identité d'administration Ceph, pas de RWX sur RBD en mode fichier, volumes par instance, rétention des PVC, CNPG sans `barmanObjectStore`, `ObjectStore` HTTPS avec CA et chemin dédié, planification CNPG à six champs en méthode `plugin`, Velero qui déplace les données, aucun secret).
- [ ] La question de fond reçoit une réponse argumentée.

**Vérification** : `lab/bin/check 16 21` (contrôle les fichiers de `~/m16/e21/corrige/`)

<details><summary>Indice 1</summary>

Pour chaque champ, demande-toi ce qu'il devient sur **notre** cluster et non sur kind : quel pilote, quelle identité Ceph, quel noyau sur les nœuds, quelles politiques d'admission. Pour chaque nom de compartiment ou de serveur, demande-toi qui d'autre écrit au même endroit.
</details>

<details><summary>Indice 2</summary>

Un StatefulSet sans `volumeClaimTemplates` partage un même PVC entre toutes ses instances. Les fonctions d'image RBD que le pilote noyau 6.12 ne sait pas monter font échouer le montage, pas la création.
</details>

<details><summary>Indice 3</summary>

Relis chaque expression cron en comptant les champs, et chaque objet de sauvegarde en te demandant : « si `ceph-par1` disparaît, qu'est-ce qui reste ? »
</details>

---

### M16-E22 — Runbook : un PVC reste Pending  `RED` `★★`

> **Ticket PLAT-1722** — *De : Nadia Roussel*
> « Mon pod est en Pending, `describe` dit `unbound immediate PersistentVolumeClaims` » : c'est le ticket que je vais recevoir le plus souvent des développeurs. Écris-moi le runbook pour l'astreinte de niveau 1 : comment on sait en deux minutes si c'est leur manifeste, un quota, notre classe, le pilote, ou Ceph, quoi faire dans chaque cas, et quand t'appeler.

**Objectifs pédagogiques**
- Transformer les essais du module (E06, E10-E12, E18, E20) en un arbre de diagnostic exécutable par quelqu'un d'autre.
- Distinguer ce qui relève de l'utilisateur, de la plateforme et de Ceph, et les gestes interdits.

**Prérequis** : M16-E12, M16-E20.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Runbook : `docs/kubernetes/stockage/runbooks/RB-160-pvc-pending.md` dans `plateforme/medisphere`, au format des runbooks du socle (objet, déclencheur, prérequis, étapes numérotées avec commande et résultat attendu, contrôles, retour arrière, escalade, historique).
- Public : astreinte de niveau 1, droits `medisphere:lecture` sur le cluster (M14-E11) plus `kubectl describe` dans les espaces d'équipe ; pas d'accès à `ceph01`.
- Causes à couvrir au minimum : classe inexistante ou mal orthographiée ; aucune classe par défaut (ou PVC `storageClassName: ""` sans PV statique) ; `WaitForFirstConsumer` (Pending **normal**) ; quota ou LimitRange ; refus d'admission (VAP d'E20) ; provisionneur arrêté ou en erreur (pods `ceph-csi`, *leader election*) ; Secret du provisionneur absent ou faux ; Ceph injoignable ou plein (quota du pool `k8s-rbd`) ; mode d'accès impossible pour la classe (RWX sur RBD) ; restauration depuis un instantané absent ou d'une autre classe.

**Travail demandé**
1. Écris RB-160 : un tableau « message ou symptôme → section » en tête, puis l'arbre de diagnostic dans l'ordre le moins coûteux (lire le PVC et ses événements, la classe, le quota, l'admission, puis le provisionneur, puis Ceph), chaque étape avec la commande exacte et ce qu'on doit voir.
2. Pour chaque cause : qui corrige (développeur, astreinte, plateforme), le geste, son contrôle, son retour arrière ; et ce qu'il ne faut **jamais** faire (créer à la main un PV `hostPath` « pour débloquer », retirer un *finalizer* de PVC, supprimer la classe par défaut pour la recréer en urgence, donner la clé `client.admin` au pilote).
3. Les conditions d'escalade (vers toi, vers l'équipe Ceph) et ce qu'il faut joindre au ticket.
4. Joue le runbook sur trois cas réels que tu provoques toi-même dans `wb-essais` (classe mal orthographiée, quota, RWX sur `ceph-rbd`) et note ce qui manquait.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] RB-160 est sur `main` de `plateforme/medisphere`, au format des runbooks, avec le tableau d'entrée.
- [ ] Chaque cause listée a son diagnostic (commande, résultat attendu), son correctif et son responsable ; les gestes interdits et l'escalade sont explicites.
- [ ] Le runbook a été joué sur trois cas ; ce qui manquait a été corrigé.

<details><summary>Indice 1</summary>

Les événements d'un PVC Pending disent presque toujours qui bloque : `ProvisioningFailed` (pilote, avec le message de ceph-csi), `WaitForFirstConsumer`, `ExternalProvisioning` qui dure (personne ne répond), `FailedBinding`. Un refus d'admission ou de quota, lui, n'est pas un événement du PVC : le PVC n'a jamais été créé, l'erreur est chez celui qui l'a demandé (`kubectl`, contrôleur du StatefulSet, opérateur).
</details>

<details><summary>Indice 2</summary>

Pour un PVC créé par un contrôleur, l'erreur d'admission est dans les événements du **contrôleur** (StatefulSet, `Cluster` CNPG) : le runbook doit dire où regarder.
</details>

---

### M16-E23 — Le stockage du cluster décrit par le code  `LIBRE` `★★★`

> **Ticket PLAT-1723** — *De : Karim Benali*
> Le stockage de `k8s-par1` a été construit en vingt exercices, et une partie n'existe que dans le cluster : un `helm upgrade` lancé un soir, une classe créée à la main, un Secret recréé « vite fait ». Je veux que `plateforme/k8s` décrive **tout** le stockage et les données de la plateforme, que tout s'applique par une procédure unique et idempotente, qu'aucun secret ne soit dans le dépôt, et que la CI attrape les erreurs avant qu'elles n'arrivent sur le cluster. Le jour où on reconstruit le cluster (E24, F5), c'est ce dépôt qui fera foi.

**Objectifs pédagogiques**
- Concevoir le périmètre « stockage et données » du dépôt de configuration du cluster (composants, classes, politiques, sauvegardes, espaces).
- Séparer les valeurs (versionnées) des secrets (créés par script depuis les fichiers de `adm01` et les Vaults).
- Construire une application idempotente et des contrôles de CI pertinents.

**Prérequis** : M16-E06 à M16-E20 ; M14-E23 (cluster reconstructible depuis `plateforme/k8s`).
**Durée indicative** : 4 h à 6 h.

**Contexte technique**
- Projet `plateforme/k8s` (M14), `Taskfile.yml`, pipeline existant. Fichiers attendus au minimum (le check les cherche sur `main`) :
  - `composants/ceph-csi/values-rbd.yaml`, `composants/ceph-csi/values-cephfs.yaml`, `composants/ceph-csi/installer.sh` (palier 1) ;
  - `composants/snapshot-controller/kustomization.yaml` (palier 1) ;
  - `composants/ceph-csi/classes/` : `ceph-rbd.yaml`, `ceph-rbd-retain.yaml`, `cephfs.yaml`, `ceph-rbd-snap.yaml`, `cephfs-snap.yaml` ;
  - `composants/velero/values.yaml`, `composants/velero/planifications.yaml` ;
  - `composants/cloudnative-pg/values.yaml`, `composants/plugin-barman-cloud/values.yaml` ;
  - `admission/classes-stockage.yaml` ; `espaces/mediagenda-dev/30-quota-stockage.yaml`, `espaces/mediagenda-recette/30-quota-stockage.yaml` ;
  - `espaces/mediagenda-recette/50-mediagenda-db.yaml`, `60-cnpg-s3.yaml`, `70-mediagenda-db-sauvegarde.yaml` ;
  - `outils/ceph-csi-secrets.sh` (palier 1) et `outils/secrets-sauvegarde.sh` (Velero, Kopia, CNPG), appelés ensemble par une tâche `stockage:secrets` ;
  - `docs/stockage.md` (README du périmètre).
- Les versions des charts sont fixées **dans le dépôt** (pas sur la ligne de commande de quelqu'un). Helmfile arrive au M17 : ici, une tâche `task` par composant suffit.
- Exécution de l'application : depuis `adm01` (comme au M14 ; GitOps au M20).

**Travail demandé**
Complète `plateforme/k8s` par MR. Contraintes :
- l'état réel et le dépôt concordent : chaque *release* Helm du stockage (`ceph-csi-rbd`, `ceph-csi-cephfs`, `velero`, `cnpg`, `plugin-barman-cloud`) a ses valeurs et sa version de chart dans le dépôt (une version passée en variable d'environnement a une valeur par défaut versionnée), et les valeurs déployées sont celles du dépôt ; chaque classe, classe d'instantanés, quota, politique d'admission du cluster est dans le dépôt ; ce qui a été retiré (Rook, Longhorn) n'y est plus ;
- une tâche unique (`task stockage:appliquer`) applique tout dans le bon ordre (CRD avant contrôleurs, contrôleur d'instantanés avant classes d'instantanés, Secrets avant les *releases* qui les utilisent, opérateur avant `Cluster`) ; rejouée sur un cluster à jour, elle ne change rien (prouve-le : `helm diff` si tu l'installes, ou `kubectl diff` et `helm get values` comparés au dépôt) ;
- **aucun secret** dans le dépôt ; la tâche `stockage:secrets` crée ou met à jour chaque Secret du stockage depuis le Vault ou les fichiers 600 de `~/.config/workbook/`, n'affiche aucune valeur, et sait dire ce qui manque (sous-commande `verifier` de chaque script) ;
- un pipeline de MR qui valide au moins : YAML, rendu des charts avec les valeurs du dépôt (`helm template`), schémas des manifestes y compris des CRD utilisées (`kubeconform` avec les schémas des CRD que tu exportes), ShellCheck des scripts, recherche de secrets ; une MR de démonstration montre le pipeline rejetant une erreur réaliste ;
- `docs/stockage.md` : périmètre, ordre d'application, secrets (où, qui, rotation), ce qui n'est pas dans le dépôt et pourquoi (données, instantanés, sauvegardes).

**Critères de réussite**
- [ ] Les fichiers attendus sont sur `main` de `plateforme/k8s` ; aucun ne contient de clé (motifs de clés S3, cephx, mots de passe).
- [ ] Les StorageClasses et classes d'instantanés du cluster ont les mêmes paramètres que celles du dépôt ; la version de chart et l'image de Velero et de CNPG déployées sont celles du dépôt.
- [ ] Le dernier pipeline de `main` est réussi ; une MR de démonstration montre un rejet.
- [ ] `task stockage:appliquer` rejouée ne modifie rien (preuve dans le journal `~/m16/e23/journal.md`).

**Vérification** : `lab/bin/check 16 23`

<details><summary>Indice 1</summary>

`helm get values <release> -n <espace> -o yaml` donne les valeurs **fournies** à une *release* ; comparées (après normalisation par `yq -P 'sort_keys(..)'`) au fichier du dépôt, elles disent s'il y a dérive. `helm list -A -o json` donne la version de chart de chaque *release*.
</details>

<details><summary>Indice 2</summary>

`kubeconform` ne connaît pas les CRD : il lui faut leurs schémas JSON. On les produit depuis les CRD du cluster ou des charts (`openapiV3Schema`), avec un petit script versionné, et on les donne par `-schema-location`.
</details>

<details><summary>Indice 3</summary>

Ordre : ce qui définit des types (CRD) → ce qui les sert (contrôleurs, opérateurs, pilotes) → ce qui les utilise (classes, `Cluster`, `ObjectStore`, planifications). Un script de Secrets idempotent s'écrit avec `kubectl create … --dry-run=client -o yaml | kubectl apply -f -`.
</details>

**Pour aller plus loin** (facultatif) : écris une détection de dérive planifiée (minuterie sur `adm01`) qui compare chaque jour l'état du stockage du cluster au dépôt et prévient par `ms-alerte@` en cas d'écart.
