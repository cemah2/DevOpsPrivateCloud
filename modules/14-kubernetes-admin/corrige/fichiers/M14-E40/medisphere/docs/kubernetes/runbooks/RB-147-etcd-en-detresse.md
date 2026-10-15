# RB-147 — etcd en détresse

| | |
|---|---|
| Cluster | `k8s-par1`, etcd empilé (3 membres, `k8s-cp01-03`), 3.6 (kubeadm 1.36) |
| Points d'accès | clients `https://10.10.40.51-53:2379`, pairs `:2380`, métriques `http://127.0.0.1:2381` |
| Rédigé | M14-E40 (INC-4140) |
| Voir aussi | RB-141 (restaurer etcd), RB-144 (remplacer un nœud de contrôle, M14-E29) |

## 0. Préparer `etcdctl` (sur un nœud de contrôle **sain**)

```
admin@k8s-cp01:~$ export ETCDCTL_API=3 \
  ETCDCTL_ENDPOINTS=https://10.10.40.51:2379,https://10.10.40.52:2379,https://10.10.40.53:2379 \
  ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
  ETCDCTL_CERT=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  ETCDCTL_KEY=/etc/kubernetes/pki/etcd/healthcheck-client.key
admin@k8s-cp01:~$ sudo -E etcdctl member list -w table
admin@k8s-cp01:~$ sudo -E etcdctl endpoint status -w table
admin@k8s-cp01:~$ sudo -E etcdctl endpoint health
admin@k8s-cp01:~$ sudo -E etcdctl alarm list
```

Règle du quorum : 3 membres, il en faut **2** pour écrire. Avec un membre en panne, plus aucun geste sur les deux autres sans nécessité.

## 1. États d'un membre

| Observation | Lecture | Suite |
|---|---|---|
| conteneur `etcd` en redémarrage, `failed to open database` | données du membre illisibles | § 2 Remplacer |
| `rejected connection … x509 … not yet valid` / `expired` | temps ou certificats | § 3 Rendre (temps), RB-143 (certificats) |
| `database space exceeded`, alarme `NOSPACE` | quota d'espace atteint | § 4 Espace |
| membre sain mais lent (`took too long`, `fsync`) | disque | mesurer (`etcd_disk_wal_fsync_duration_seconds`), stockage `local-nvme` |
| 2 membres sur 3 perdus | plus de quorum | RB-141 (restauration), décision de l'astreinte |

## 2. Remplacer un membre (données perdues)

1. Vérifier que les **deux autres** sont sains (`endpoint health`).
2. Sur le nœud : manifeste hors de `/etc/kubernetes/manifests/` et attendre l'arrêt du conteneur (`crictl ps --name etcd`) **avant** tout retrait : un membre retiré qui tourne encore redémarre en boucle dans un cluster qui ne le connaît plus.
3. `etcdctl member remove <ID>` depuis un nœud sain : l'identifiant du membre **malade**, relu deux fois ; puis, sur le nœud, dossier `/var/lib/etcd/member` mis de côté.
4. `etcdctl member add <NOM> --peer-urls=https://<IP>:2380` ; reporter `--initial-cluster` affiché et `--initial-cluster-state=existing` dans le manifeste.
5. Manifeste remis ; le membre rattrape par instantané du leader ; vérifier `endpoint status` (même révision).
6. Supprimer le dossier mis de côté.

## 3. Rendre ce qui manque (temps)

- `timedatectl`, `chronyc tracking` ; `sudo systemctl enable --now chrony && sudo chronyc makestep`.
- Si SSH refuse ton certificat d'utilisateur (« pas encore valide ») : console (`qm terminal <VMID>`).
- etcd, kube-apiserver et kubelet du nœud reviennent seuls ; chercher pourquoi le service de temps était arrêté.

## 4. Espace : alarme NOSPACE

```
admin@k8s-cp01:~$ sudo -E etcdctl get "" --from-key --keys-only | grep -v '^$' | cut -d/ -f2 | sort | uniq -c
admin@k8s-cp0X:~$ sudo grep quota /etc/kubernetes/manifests/etcd.yaml
```

Dans cet ordre :
1. Trouver ce qui remplit : clés hors de `/registry/` (à supprimer par `etcdctl del --prefix`), ou objets Kubernetes trop nombreux ou trop gros (à supprimer **par l'API**, jamais dans etcd).
2. `etcdctl compact <révision courante>`.
3. `etcdctl --endpoints=<un membre> defrag`, **un membre à la fois**, le leader en dernier.
4. Corriger la cause du dépassement (quota par défaut 2 Gio ; une valeur explicite se fixe dans `etcd.local.extraArgs` de la configuration kubeadm, donc dans le code).
5. `etcdctl alarm disarm`, `alarm list` vide, essai d'écriture (`kubectl create configmap … --dry-run=server` puis réel).

## Interdit tant qu'il reste un quorum

- restaurer un instantané (RB-141) : on perdrait tout ce qui a été écrit depuis ;
- `member remove` d'un membre sain, `defrag --cluster`, écritures directes dans `/registry/` ;
- arrêter ou redémarrer un second nœud de contrôle.

## Surveillance (module 21)

`etcd_server_has_leader`, `etcd_mvcc_db_total_size_in_bytes` rapporté au quota (alerte à 70 %), `etcd_disk_wal_fsync_duration_seconds`, écart d'horloge des nœuds, âge du dernier instantané dans `s3-01`.
