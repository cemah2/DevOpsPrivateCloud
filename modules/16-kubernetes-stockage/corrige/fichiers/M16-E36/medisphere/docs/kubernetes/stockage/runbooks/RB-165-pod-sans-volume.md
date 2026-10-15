# RB-165 — Un pod n'obtient pas son volume (ContainerCreating, Multi-Attach)

| | |
|---|---|
| Périmètre | `k8s-par1`, volumes ceph-csi (`ceph-rbd`, `ceph-rbd-retain`, `cephfs`) |
| Déclencheurs | pod en `ContainerCreating` plus de 2 min avec un volume ; événement `FailedAttachVolume`, `FailedMount`, `Multi-Attach error` |
| Rédigé après | INC-4342 (M16-E36), INC-4343 (M16-E37) |
| Gestes interdits sans validation | suppression forcée d'un pod (`--force --grace-period=0`), retrait d'un finaliseur de PV ou de VolumeAttachment, teinte `out-of-service` sur un nœud non prouvé éteint |

## 1. Situer l'étage (5 min)

```
admin@adm01:~$ kubectl describe pod <POD> -n <ESPACE> | sed -n '/Events/,$p'
admin@adm01:~$ k8s-suivre-volume.sh <ESPACE> <PVC>          # plateforme/outils (M16-E44)
```

| Événement | Étage | Aller à |
|---|---|---|
| `Multi-Attach error … already used by pod(s)` / `already exclusively attached` | contrôleur attach/detach : le volume RWO est encore attaché à un autre nœud | §4 |
| `AttachVolume.Attach failed` / `attachdetach-controller … timed out` | csi-attacher (provisioner) | §2 |
| `MountVolume.MountDevice failed … driver name rbd.csi.ceph.com not found in the list of registered CSI drivers` | pilote absent du nœud | §3.1 |
| `MountVolume.MountDevice failed … rbd: map failed … (110) Connection timed out` | réseau nœud → moniteurs | §3.2 |
| `MountVolume.MountDevice failed … (1) Operation not permitted` / `(13) Permission denied` | identité Ceph du Secret de nœud | §3.3 |
| `MountVolume.SetUp failed` | NodePublish (montage *bind*, droits `fsGroup`) | journal du kubelet |

## 2. Attachement

`kubectl get volumeattachment -o wide | grep <PV>` ; `kubectl logs -n ceph-csi <provisioner-leader> -c csi-attacher --tail=50` (leader : `kubectl get lease -n ceph-csi`). Pour RBD, `ControllerPublishVolume` ne fait presque rien : un échec ici est presque toujours le sidecar (pas de leader, droits RBAC).

## 3. Côté nœud

Trouver le *nodeplugin* du nœud : `kubectl get pods -n ceph-csi -l component=nodeplugin --field-selector spec.nodeName=<NŒUD> -o wide` ; journaux : `-c csi-rbdplugin` (appels `NodeStageVolume`, commande `rbd map`) et, sur le nœud, `sudo journalctl -u kubelet --since -15min | grep -i csi`.

### 3.1 Pilote absent
- `kubectl get csinode <NŒUD> -o jsonpath='{.spec.drivers[*].name}'` ; pod *nodeplugin* présent sur le nœud ?
- Sinon : affinité, `nodeSelector`, tolérances du DaemonSet comparés aux étiquettes et teintes du nœud ; état du DaemonSet (`DESIRED` = nombre de travailleurs).
- Correctif : valeurs Helm `nodeplugin.*` dans `plateforme/k8s/composants/ceph-csi/values-rbd.yaml`, puis `task appliquer`.

### 3.2 Moniteurs injoignables depuis le nœud
- Sur le nœud : `ip -br addr` (carte VLAN 30, 10.10.30.8x), `ip route get 10.10.30.51`, `ping -c2 -M do -s 8972 10.10.30.51`, `timeout 3 bash -c '</dev/tcp/10.10.30.51/3300'` (et 6789).
- Pare-feu local : `sudo nft list ruleset` ; toute table qui ne vient ni de Cilium ni du rôle Ansible du nœud est suspecte (origine, date). Les volumes déjà montés gardent leurs sessions : ne pas conclure « tout va bien » sur la foi des pods existants.
- Correctif : configuration du nœud par Ansible (rôle de la carte VLAN 30, pare-feu) ; jamais de règle posée à la main sans MR.

### 3.3 Identité refusée
- Secret utilisé : paramètres `csi.storage.k8s.io/node-stage-secret-name` / `-namespace` de la StorageClass.
- Comparer des **empreintes**, jamais des valeurs : `kubectl get secret … -o jsonpath='{.data.userKey}' | base64 -d | sha256sum` contre `sudo ceph auth get-key client.<ID> | sha256sum` sur `ceph01`.
- Correctif : recréer le Secret par le script de `plateforme/k8s` depuis la copie de Vault (jamais à la main), puis relancer le pod.

## 4. Multi-Attach : un volume RWO encore attaché à un nœud perdu

1. **Établir l'état du nœud d'origine** : `kubectl get node`, `ping`, `ssh`, `qm status <VMID>` sur `pve01`, et côté Ceph `sudo rbd status <pool>/<image>` (observateurs et adresses). Écrire la conclusion : *vivant*, *à moitié vivant* (SSH oui, kubelet non), *éteint*.
2. **Nœud réparable rapidement** (kubelet arrêté, réseau) : le réparer. Le kubelet démonte, Kubernetes détache, le nouveau pod démarre. Rien d'autre à faire.
3. **Nœud éteint et qui le restera** (preuve : VM arrêtée, ou alimentation coupée) : arrêt non gracieux.
   ```
   admin@adm01:~$ kubectl taint node <NŒUD> node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
   ```
   Les pods du nœud sont supprimés de force et leurs volumes détachés ; le nouveau pod s'attache. Noter l'heure.
4. **Ne jamais poser la teinte sur un nœud qui tourne encore** (même « à moitié ») : deux nœuds monteraient le même ext4, corruption assurée. Si le nœud ne peut pas être éteint de façon sûre, l'isoler d'abord (arrêt de la VM, ou blocage côté Ceph de ses adresses : `ceph osd blocklist add <ADRESSE>`), puis seulement poser la teinte.
5. **Retour du nœud** : quand il est `Ready` et que ses anciens pods ont disparu, retirer la teinte : `kubectl taint node <NŒUD> node.kubernetes.io/out-of-service-`. Vérifier : un seul `VolumeAttachment` par PV RWO, aucun pod `Terminating`.

## 5. Vérification de sortie

`lab/bin/check 16 36` et `lab/bin/check 16 37` verts ; `k8s-suivre-volume.sh` sur le PVC concerné ; témoins `temoin-rbd` et `temoin-cephfs` prêts.

## 6. À automatiser (actions ouvertes)
- Alerte « pod en ContainerCreating avec volume depuis plus de 5 min » (M21).
- Contrôle `ms-verif-k8s-stockage` : pilotes dans CSINode et moniteurs joignables depuis chaque travailleur.
- Clôture automatique des nœuds perdus : NetworkFence (csi-addons) ou agent de *fencing* Proxmox, à évaluer (ticket PLAT).
