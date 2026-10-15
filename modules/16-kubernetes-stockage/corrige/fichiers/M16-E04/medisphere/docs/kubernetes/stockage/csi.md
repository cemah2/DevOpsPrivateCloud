# CSI dans `k8s-par1` : qui fait quoi pour un volume

> Propriétaire : équipe Plateforme · Origine : PLAT-1704 (M16-E04) · Pilote de référence : ceph-csi 3.18.1 (RBD), voir [`ceph-csi.md`](ceph-csi.md)
> Les heures de la colonne « observé » viennent d'un essai du `<DATE>` (PVC `wb-essais/e06-essai`, pod recréé sur `k8s-w02`). Remplace-les par les tiennes.

## 1. Les acteurs

| Acteur | Où il tourne | Ce qu'il fait |
|---|---|---|
| `kube-controller-manager` (contrôleur PV/PVC, contrôleur d'attachement) | nœuds de contrôle | lie PVC et PV ; crée et supprime les `VolumeAttachment` |
| `csi-provisioner` (sidecar) | pod `ceph-csi-rbd-provisioner-…` (2 réplicas, un **leader**) | observe les PVC de ses classes → `CreateVolume`/`DeleteVolume` ; crée l'objet PV |
| `csi-attacher` (sidecar) | même pod | observe les `VolumeAttachment` → `ControllerPublishVolume`/`ControllerUnpublishVolume` ; met `status.attached` |
| `csi-resizer`, `csi-snapshotter` (sidecars) | même pod | agrandissement (`ControllerExpandVolume`) ; instantanés (`CreateSnapshot`, avec le `snapshot-controller` de `kube-system`) |
| `csi-rbdplugin` (le pilote, partie *Controller*) | même pod | parle à Ceph (librados/librbd) avec la clé de `client.k8s` : crée, supprime, agrandit les images |
| `driver-registrar` (sidecar `node-driver-registrar`) | pod `ceph-csi-rbd-nodeplugin-…` (un par travailleur) | inscrit le pilote auprès du kubelet (`/var/lib/kubelet/plugins_registry/`) → le nœud apparaît dans le `CSINode` |
| `csi-rbdplugin` (le pilote, partie *Node*) | même pod, `hostNetwork`, privilégié | `NodeStageVolume` (mappe l'image par krbd, formate si besoin, monte dans `globalmount`), `NodePublishVolume` (montage lié dans le pod), et leurs inverses |
| `kubelet` | chaque nœud | appelle la partie *Node* du pilote par sa socket `/var/lib/kubelet/plugins/rbd.csi.ceph.com/csi.sock` |

Aucun composant de Kubernetes ne parle à Ceph : seul le pilote le fait.

## 2. La vie d'un volume

| # | Étape | Appel CSI | Qui appelle | Où | Objet ou trace visible | Observé |
|---|---|---|---|---|---|---|
| 1 | PVC créé (classe `ceph-rbd`, liaison immédiate) | `CreateVolume` | `csi-provisioner` (leader) | pod du *provisioner* | événement `Provisioning` puis `ProvisioningSucceeded` du PVC ; image `csi-vol-<uuid>` dans `k8s-rbd` ; objet PV `pvc-<uid>` (`spec.csi.volumeHandle`) | `<hh:mm:ss>` |
| 2 | PVC lié au PV | — | contrôleur PV/PVC | plan de contrôle | PVC `Bound` | `<…>` |
| 3 | pod planifié sur un nœud | — | `kube-scheduler` | plan de contrôle | `spec.nodeName` du pod | `<…>` |
| 4 | volume attaché au nœud | `ControllerPublishVolume` | `csi-attacher` (sur un `VolumeAttachment` créé par le contrôleur d'attachement) | pod du *provisioner* | `VolumeAttachment` `csi-<hash>` : `attacher: rbd.csi.ceph.com`, `nodeName`, `status.attached: true` | `<…>` |
| 5 | volume préparé sur le nœud | `NodeStageVolume` | kubelet | *nodeplugin* du nœud | `/dev/rbd0` (`lsblk`), montage sur `…/plugins/kubernetes.io/csi/rbd.csi.ceph.com/<hash>/globalmount` ; journal du kubelet `MountVolume.MountDevice succeeded` | `<…>` |
| 6 | volume monté dans le pod | `NodePublishVolume` | kubelet | *nodeplugin* | montage lié dans `/var/lib/kubelet/pods/<uid>/volumes/kubernetes.io~csi/<pv>/mount` ; événement `SuccessfulAttachVolume` puis conteneur démarré | `<…>` |
| 7 | pod supprimé | `NodeUnpublishVolume` | kubelet | *nodeplugin* | montage du pod retiré | `<…>` |
| 8 | plus aucun pod du nœud ne l'utilise | `NodeUnstageVolume` | kubelet | *nodeplugin* | `globalmount` démonté, image démappée (`lsblk` ne la montre plus) | `<…>` |
| 9 | volume détaché | `ControllerUnpublishVolume` | `csi-attacher` | *provisioner* | `VolumeAttachment` supprimé | `<…>` |
| 10 | PVC supprimé (classe `Delete`) | `DeleteVolume` | `csi-provisioner` | *provisioner* | PV supprimé ; image absente de `rbd ls k8s-rbd` | `<…>` |

Agrandissement : `ControllerExpandVolume` (image agrandie, `csi-resizer`) puis `NodeExpandVolume` (système de fichiers agrandi, kubelet) : M16-E11. Instantané : `CreateSnapshot` (`csi-snapshotter`), M16-E10.

Ce que montre l'ordre : un pod en `ContainerCreating` est bloqué **entre 3 et 6**. Si le `VolumeAttachment` n'est pas `attached`, c'est côté *provisioner* (étape 4) ; s'il l'est, c'est côté nœud (étapes 5-6) : kubelet et *nodeplugin* **du nœud du pod**.

## 3. Devant un pod en `ContainerCreating`

1. `kubectl describe pod <pod>` : derniers événements (`FailedAttachVolume`, `FailedMount`, `MountVolume.MountDevice failed …`). Le message d'erreur du pilote y est recopié (`rpc error: code = … desc = …`).
2. `kubectl get pvc <pvc>` (lié ?) puis `kubectl get pv <pv> -o yaml` (pilote, `volumeHandle`, `volumeAttributes.imageName`).
3. `kubectl get volumeattachment | grep <pv>` : existe-t-il ? `attached` ? `status.attachError` ?
4. Le nœud déclare-t-il le pilote ? `kubectl get csinode <nœud> -o jsonpath='{.spec.drivers[*].name}'`. Le *nodeplugin* du nœud est-il prêt ? `kubectl -n ceph-csi get pod -o wide -l app=ceph-csi-rbd,component=nodeplugin`.
5. Journaux du *nodeplugin* **du nœud du pod** : `kubectl -n ceph-csi logs <pod-nodeplugin> -c csi-rbdplugin --since=15m | grep -E 'GRPC (call|error)|error'`.
6. Journaux du *provisioner* leader (bail : `kubectl -n ceph-csi get lease`) : conteneurs `csi-attacher`, `csi-provisioner`, `csi-rbdplugin`.
7. Sur le nœud : `journalctl -u kubelet --since "-15 min" | grep -i -E 'volume|csi'`, `lsblk`, `findmnt -t ext4`, `ss -tn dst 10.10.30.51` (le nœud joint-il les moniteurs ?).
8. Côté Ceph (`ceph01`) : `ceph -s`, `rbd status k8s-rbd/<image>` (qui tient l'image ?), `ceph osd blocklist ls`.

Runbook détaillé : RB-160 (PVC `Pending`, M16-E22) ; pannes pratiquées : M16-E35 à E37.

## 4. Références

- Spécification CSI : <https://github.com/container-storage-interface/spec/blob/master/spec.md> (*RPC Interface*, *Volume Lifecycle*).
- Sidecars et objets : <https://kubernetes-csi.github.io/docs/>.
- Ce qui se passe sous le capot (montages, `globalmount`, `rbd showmapped`) : M16-E44.
