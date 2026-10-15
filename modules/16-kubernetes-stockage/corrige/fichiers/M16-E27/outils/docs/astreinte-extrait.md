## Stockage Kubernetes (`ms-verif-k8s-stockage`)

La sonde tourne toutes les 10 minutes sur `adm01` ; chaque échec déclenche `ms-alerte`. Message : une ligne `KO <famille> <détail>` par anomalie.

### Ce que révèle chaque famille

| Famille | Panne typique | Délai de détection |
|---|---|---|
| `pvc` | classe inexistante, plus de classe par défaut, quota, provisionneur arrêté, Ceph qui refuse (M16-E35, E38) | 15 min + 10 min |
| `pv` | suppression d'image en échec (droits cephx, image encore mappée) | 10 min |
| `attachement` | VolumeAttachment en erreur, *Multi-Attach* (E37) | 10 min |
| `pilotes` | *nodeplugin* absent ou en erreur sur un nœud, contrôleur arrêté (E36) | 10 min |
| `snapshots` | contrôleur de snapshots arrêté, classe de snapshot fausse (E42) | 30 min + 10 min |
| `volumes` | volume plein (octets ou inodes) | 10 min |
| `velero` | BSL indisponible (identifiants, CA, compartiment), sauvegarde en échec (E39) | 26 h (âge) ; BSL : 10 min |
| `cnpg`, `archivage`, `sauvegarde`, `replication` | base dégradée, archivage des WAL bloqué (E41), réplica en retard ou arrêté (E40) | 10 min ; sauvegarde : 26 h |
| `api` | API injoignable, jeton de la sonde expiré | 10 min |

### Les trois premières commandes

| Famille | Commandes |
|---|---|
| `pvc` | `kubectl describe pvc -n <ns> <pvc>` (événements) ; `kubectl get sc` ; `kubectl logs -n ceph-csi deploy/ceph-csi-rbd-provisioner -c csi-provisioner --tail=50` |
| `pv`, `attachement` | `kubectl describe pv <pv>` ; `kubectl get volumeattachment -o wide \| grep <pv>` ; `kubectl get nodes` |
| `pilotes` | `kubectl get pods -n ceph-csi -o wide` ; `kubectl describe pod -n ceph-csi <pod>` ; `kubectl logs -n ceph-csi <pod> -c csi-rbdplugin --tail=50` |
| `snapshots` | `kubectl get volumesnapshot -A` ; `kubectl describe volumesnapshot -n <ns> <nom>` ; `kubectl logs -n kube-system deploy/snapshot-controller --tail=50` |
| `volumes` | `kubectl exec -n <ns> <pod> -- df -h <point>` ; qui écrit quoi ; agrandir (`allowVolumeExpansion`) |
| `velero` | `velero backup-location get` ; `velero backup describe <dernière> --details` ; `velero backup logs <dernière> \| grep -i error` |
| `cnpg`… | `kubectl cnpg status <cluster> -n <ns>` ; `kubectl get backups.postgresql.cnpg.io -n <ns>` ; `kubectl logs -n <ns> <primaire> -c plugin-barman-cloud --tail=50` |

### Réveiller quelqu'un ?

- **Oui, tout de suite** : `archivage` (le RPO s'allonge et le disque du primaire se remplit), `cnpg` sur `mediagenda-*` (base dégradée), `volumes` au-delà de 90 % sur une base, `pilotes` sur plus d'un nœud, `api`.
- **Le matin** : `snapshots` en recette, `velero` âge dépassé une fois (la planification suivante peut réussir), `pv` `Released`, `replication` d'un réplica en recette.
