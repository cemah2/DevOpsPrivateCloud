# RB-166 — Une sauvegarde Velero échoue (ou un instantané ne se termine pas)

| | |
|---|---|
| Périmètre | Velero 1.18 (espace `velero`), emplacement vers `s3-01` `velero-k8s-par1`, instantanés CSI (`ceph-rbd-snap`, `cephfs-snap`) |
| Déclencheurs | sauvegarde `FailedValidation`, `Failed`, `PartiallyFailed`, ou `InProgress` depuis plus d'une heure ; `VolumeSnapshot` non prêt depuis plus de 10 min |
| Rédigé après | INC-4345 (M16-E39), INC-4348 (M16-E42) |

## 1. Phase de la sauvegarde → étage

```
admin@adm01:~$ velero backup get
admin@adm01:~$ velero backup describe <NOM> --details
admin@adm01:~$ velero backup logs <NOM> | grep -i -E 'error|fail' | head
admin@adm01:~$ velero backup-location get
```

| Phase | Ce que Velero dit | Étage |
|---|---|---|
| `FailedValidation` | « backup storage location … is unavailable » / data mover sans node-agent | emplacement (§2) ou configuration |
| `Failed` | erreur d'objet S3 à l'écriture des métadonnées | emplacement (§2) |
| `PartiallyFailed` | `PodVolumeBackup` ou `DataUpload` en échec pour certains volumes | volumes (§3) |
| `InProgress` / `WaitingForPluginOperations` sans fin | instantané CSI jamais prêt | instantanés (§4) |

## 2. Emplacement indisponible
- `kubectl get bsl -n velero -o yaml` : `status.message` donne l'erreur S3 exacte.
- Reproduire depuis le cluster (pod jetable dans `wb-essais`, client S3 avec les identifiants du compte `velero` montés depuis le même Secret, CA MédiSphère) :
  `SignatureDoesNotMatch`/`InvalidAccessKeyId` → identifiants (Secret, `~/.config/workbook/s3-velero.env`, rotation faite d'un seul côté) ;
  `NoSuchBucket`/`AccessDenied` sur un nom inattendu → compartiment ou préfixe de l'emplacement ;
  `x509: certificate signed by unknown authority` → `caCert` de l'emplacement.
- Correctif : valeurs Helm de `plateforme/k8s/composants/velero/` et script de création du Secret ; la validation suivante (≤ 1 min) remet l'emplacement `Available`.

## 3. Volumes en échec
- `kubectl get podvolumebackups,datauploads -n velero` (colonnes nœud, phase, message).
- `node-agent` présent sur le nœud du pod ? `kubectl get ds node-agent -n velero` (`DESIRED` = nombre de travailleurs), `kubectl get pods -n velero -o wide`.
- Correctif : affinités et tolérances du DaemonSet dans les valeurs Helm ; relancer la sauvegarde.

## 4. Instantané qui ne se termine pas
- `kubectl describe volumesnapshot <NOM> -n <ESPACE>` puis son `VolumeSnapshotContent` :
  - aucun statut, aucun contenu → `snapshot-controller` (`kubectl get deploy,pods -n kube-system -l app.kubernetes.io/name=snapshot-controller`, journaux : `forbidden` → ClusterRoleBinding manquant) ;
  - contenu présent avec `status.error` → appel au pilote : `kubectl logs -n ceph-csi <provisioner-leader> -c csi-snapshotter` et `-c csi-rbdplugin`, et comparaison de la `VolumeSnapshotClass` avec la StorageClass (pilote, `clusterID`, Secret du snapshotter et son espace).
- **Jamais** supprimer ni recréer les CRD `snapshot.storage.k8s.io` : leurs objets disparaîtraient, et avec eux le suivi des instantanés existants dans Ceph.

## 5. Vérification de sortie
Nouvelle sauvegarde `Completed` (volumes compris), restaurée dans `wb-restauration` puis nettoyée ; `lab/bin/check 16 39` et `lab/bin/check 16 42` verts.
