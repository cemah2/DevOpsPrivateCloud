# ceph-csi : le stockage persistant de `k8s-par1`

> Propriétaire : équipe Plateforme · Origine : PLAT-1705/1706 (M16-E05, E06), DEV-1707 (E07) · Code : `plateforme/k8s` (`espaces/ceph-csi.yaml`, `composants/snapshot-controller/`, `composants/ceph-csi/`, `outils/ceph-csi-secrets.sh`, `secrets/ceph-csi.yml`), `plateforme/ceph` (`allocations.yaml`), `plateforme/infra` (`envs/k8s`), `plateforme/ansible` (rôle `k8s_reseau_stockage`)
> Fonctionnement détaillé d'un volume : [`csi.md`](csi.md).

## 1. Architecture

```
k8s-w01-03 (étiquette medisphere.internal/stockage-ceph=oui)          ceph-par1 (Tentacle 20.2.4)
 eth0 10.10.40.6N  (Kubernetes, VLAN 40)                          MON 10.10.30.51-53:3300 (msgr2 secure)
 eth1 10.10.30.8N  MTU 9000 ──────────── VLAN 30, sans bordure ── OSD/MDS 10.10.30.51-53:6800-7568
   ├─ ceph-csi-rbd-nodeplugin  (DaemonSet, privilégié, hostNetwork)  pool k8s-rbd (quota 20 Gio)
   ├─ ceph-csi-cephfs-nodeplugin (E07)                                CephFS cephfs, groupe csi (20 Gio)
   └─ ceph-csi-rbd-provisioner / -cephfs-provisioner (2 réplicas sur deux travailleurs, leader élu)
kube-system : snapshot-controller (external-snapshotter v8.6.0, 2 réplicas)
```

- Seuls les travailleurs raccordés portent des pods de ceph-csi (sélecteur de nœud sur l'étiquette posée par le rôle `k8s_reseau_stockage` **après** vérification du MTU et des routes). Les nœuds de contrôle n'ont ni carte de stockage, ni pilote.
- Les pods du *provisioner* ne sont pas en `hostNetwork` : leur trafic vers Ceph sort masqué par l'adresse `eth1` du nœud.
- Images : `quay.io/cephcsi/cephcsi:v3.18.1` et sidecars `registry.k8s.io/sig-storage/…`, tirées par le cache Harbor (aucune référence modifiée).

## 2. Identités, clés et Secrets

| Identité cephx | Droits | Secret Kubernetes | Clé de référence |
|---|---|---|---|
| `client.k8s` | `mon 'profile rbd'`, `osd 'profile rbd pool=k8s-rbd'`, `mgr 'profile rbd pool=k8s-rbd'` | `ceph-csi/csi-rbd-secret` (`userID: k8s`) | `plateforme/k8s/secrets/ceph-csi.yml`, `ceph_csi_rbd_cle` (Vault `critique`) |
| `client.k8s-cephfs` (E07) | droits CephFS de la documentation ceph-csi, limités à `fsname=cephfs` et au groupe `csi` | `ceph-csi/csi-cephfs-secret` (`userID: k8s-cephfs`) | même fichier, `ceph_csi_cephfs_cle` |

- Type de clé **`aes`** : les clients noyau des travailleurs (Linux 6.12) ne savent pas utiliser `aes256k` (M08-E27). À revoir quand les nœuds auront un noyau qui le gère.
- Les Secrets ne viennent **que** du Vault : `outils/ceph-csi-secrets.sh appliquer`. `outils/ceph-csi-secrets.sh verifier` compare par empreinte Vault, Secret et Ceph (à lancer après chaque rotation et dans la recette).
- **Rotation** d'une clé (procédure) : `ceph auth rotate client.k8s` sur `ceph01` (le pilote garde ses sessions jusqu'au renouvellement des tickets), nouvelle clé rangée dans le Vault (même tube qu'à la création), `appliquer`, puis `verifier` ; les nouveaux montages utilisent la nouvelle clé, les montages en cours se ré-authentifient (⚠️ à éprouver avant de le faire en production : M16-E26).

## 3. Classes

| Classe | Pilote | Usage | Paramètres clés | Récupération |
|---|---|---|---|---|
| `ceph-rbd` (**par défaut**) | `rbd.csi.ceph.com` | bloc RWO (bases, Valkey, applications) | pool `k8s-rbd`, `layering,exclusive-lock,object-map,fast-diff,deep-flatten`, ext4, `krbd:ms_mode=secure`, `discard` | `Delete` |
| `ceph-rbd-retain` | `rbd.csi.ceph.com` | données à ne pas perdre sur une suppression de PVC | idem | `Retain` |
| `cephfs` (E07) | `cephfs.csi.ceph.com` | fichier partagé RWX | `fsName: cephfs`, `mounter: kernel`, `kernelMountOptions: ms_mode=secure` | `Delete` |

Une classe ne se modifie pas (paramètres immuables) : on en crée une nouvelle et on migre (M16-E29).

## 4. Installer, vérifier, mettre à jour

```
admin@adm01:~/src/k8s$ task stockage:ceph-csi        # snapshots, espace, pilotes, classes
admin@adm01:~/src/k8s$ task stockage:secrets         # Secrets depuis Vault, puis vérification
admin@adm01:~/src/k8s$ kubectl -n ceph-csi get ds,deploy,pod -o wide
admin@adm01:~/src/k8s$ kubectl get csidrivers ; kubectl get csinode -o custom-columns=NOEUD:.metadata.name,PILOTES:.spec.drivers[*].name
admin@adm01:~/src/k8s$ kubectl get sc
```

Mise à jour d'une version corrective (3.18.x) : changer `CEPH_CSI_VERSION`, `installer.sh --rendu` comparé à la version en place, MR, `installer.sh` ; le *nodeplugin* se met à jour nœud par nœud (`RollingUpdate`), les volumes montés ne sont pas démontés. Procédure complète : M16-E33.

## 5. Retrouver une image depuis un PV (et inversement)

```
admin@adm01:~$ kubectl get pv <PV> -o jsonpath='{.spec.csi.volumeAttributes.pool}/{.spec.csi.volumeAttributes.imageName}{"\n"}'
k8s-rbd/csi-vol-0c1d…
[admin@ceph01 ~]$ sudo rbd info k8s-rbd/csi-vol-0c1d…
[admin@ceph01 ~]$ sudo rbd status k8s-rbd/csi-vol-0c1d…        # quel client (nœud) l'a mappée
admin@adm01:~$ kubectl get pv -o custom-columns=PV:.metadata.name,IMAGE:.spec.csi.volumeAttributes.imageName,PVC:.spec.claimRef.name,ETAT:.status.phase
```

Images sans PV (orphelines) : comparer `rbd ls k8s-rbd | grep '^csi-vol-'` à la colonne `IMAGE` ci-dessus ; une image orpheline se signale, ne se supprime **qu'après** avoir vérifié qu'aucun PV (même `Released`) ni instantané ne la référence.

## 6. Ménage d'un PV `Released` (classe `ceph-rbd-retain`)

1. Lire le PV : PVC d'origine (`spec.claimRef`), image (`volumeAttributes.imageName`), et décider avec l'équipe propriétaire : réutiliser (retirer `claimRef`, E03), copier, ou supprimer.
2. Pour supprimer : `kubectl delete pv <PV>` (l'image reste), puis, sur `ceph01`, `sudo rbd rm k8s-rbd/<image>` après avoir revérifié le nom et l'absence de PV qui la cite.
   ⚠️ `rbd rm` est définitif.

## 7. Dépendances et ordre d'arrêt

Un volume monté dépend de `ceph-par1` à chaque écriture. Arrêt : `k8s-par1` d'abord, `ceph-par1` ensuite ; démarrage dans l'ordre inverse (règle 3 du module). Un nœud qui perd le VLAN 30 garde ses pods en E/S bloquées (processus en état `D`) : M16-E36.
