# RB-181 — Restaurer un cluster selon sa distribution

| | |
|---|---|
| Portée | Clusters k3s (etcd intégré ou SQLite), RKE2, Talos ; cluster de gestion Cluster API (`k3s01`). Pour kubeadm (`k8s-par1`) : **RB-141** |
| Quand | Perte de quorum etcd sans retour possible, corruption, suppression massive d'objets, perte du cluster de gestion |
| Quand **pas** | Un seul membre etcd perdu sur trois : on le remplace (rejoindre), on ne restaure pas. Un objet supprimé : Velero (M16) ou le dépôt |
| Source des instantanés | `s3://etcd-m18/` sur `s3-01` (`k3s-ha/`, `rke2/`, `talos/`, `gestion/`), identité `etcd-m18`, `~/.config/workbook/s3-etcd-m18.env` |
| Rédigé par | Équipe Plateforme — M18-E14 |

> ⚠️ Une restauration remplace **tout** l'état du cluster par celui de l'instantané. Tout ce qui a été écrit après est perdu (RPO = âge de l'instantané). Annonce-la, arrête les déploiements (CI, GitOps), et note l'heure de la décision : c'est le début du RTO.

## 1. Avant toute restauration (toutes distributions)

1. Confirmer qu'on ne peut pas retrouver le quorum (membres etcd : `k3s`/`rke2` → `etcdctl` avec les certificats de `server/tls/etcd/` ; Talos → `talosctl etcd members`, `talosctl service etcd`).
2. Choisir l'instantané : le plus récent **antérieur** à l'incident. Le télécharger, le déchiffrer s'il est chiffré, vérifier son intégrité (`etcdutl snapshot status`).
3. Réunir les secrets d'identité du cluster : **jeton du serveur** (k3s, RKE2 : `server/token`, Vault `lab`) ; **`talos-secrets.yaml`** et configurations des machines (Talos).
4. Faire, si possible, un instantané de l'état actuel (même abîmé) : c'est le retour arrière.

## 2. k3s, etcd intégré

Un serveur (banc `k3s-ha01`) :
```
admin@k3s-ha01:~$ sudo systemctl stop k3s
admin@k3s-ha01:~$ sudo k3s server --cluster-reset --cluster-reset-restore-path=<NOM> --etcd-s3 <OPTIONS-S3>
# ou, instantané local : --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<NOM> --etcd-s3=false
admin@k3s-ha01:~$ sudo systemctl start k3s
```
Plusieurs serveurs : arrêter **tous** les serveurs ; réinitialiser sur le premier ; le démarrer ; sur les autres, déplacer `/var/lib/rancher/k3s/server/db/` puis démarrer un par un. Les agents se reconnectent seuls.

Options S3 : celles du fragment `config.yaml.d/50-etcd-s3.yaml` (relues par `k3s server`), le Secret `etcd-s3-config-secret` n'est **pas** lu pendant une restauration. Sur un hôte neuf : `--token=<JETON-SAUVEGARDÉ>`, puis supprimer à la main les anciens objets `Node` qui n'existent plus.

## 3. k3s sur SQLite (`k3s01`, cluster de gestion)

```
admin@adm01:~$ ( set -a; . ~/.config/workbook/s3-etcd-m18.env; set +a
>   aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 cp s3://etcd-m18/gestion/<ARCHIVE> . )
admin@adm01:~$ age -d -i <CLÉ-PRIVÉE> <ARCHIVE> | ssh k3s01 'sudo -n tee /root/restauration.tar.gz >/dev/null'
admin@k3s01:~$ sudo systemctl stop k3s
admin@k3s01:~$ sudo mv /var/lib/rancher/k3s/server/db /var/lib/rancher/k3s/server/db.avant-restauration
admin@k3s01:~$ sudo tar -C /var/lib/rancher/k3s -xzf /root/restauration.tar.gz && sudo rm /root/restauration.tar.gz
admin@k3s01:~$ sudo systemctl start k3s
```
(La clé privée `age` est en Vault `critique` : `ansible-vault view` dans un tube, jamais sur disque en clair.)

## 4. RKE2 (trois serveurs)

```
admin@rke2-0N:~$ sudo systemctl stop rke2-server && sudo rke2-killall.sh        # sur les TROIS, d'abord
admin@rke2-01:~$ sudo rke2 server --cluster-reset --cluster-reset-restore-path=<NOM> --etcd-s3 <OPTIONS-S3>
admin@rke2-01:~$ sudo systemctl start rke2-server
admin@rke2-0N:~$ sudo mv /var/lib/rancher/rke2/server/db /var/lib/rancher/rke2/server/db.avant-restauration   # 02 et 03
admin@rke2-0N:~$ sudo systemctl start rke2-server                              # 02, attendre Ready, puis 03
```
`rke2-killall.sh` arrête aussi les conteneurs : sans lui, les conteneurs etcd restent vivants sous leurs *shims* et gardent les ports 2379-2380.

## 5. Cluster de gestion perdu (`k3s01`)

Les clusters de charge de travail **continuent de tourner** ; ils ne sont plus ni réparés, ni mis à l'échelle, ni mis à jour.
1. Reconstruire la VM et k3s par le code (`plateforme/infra` état `m18`, rôle `k3s`), même version.
2. Soit restaurer l'archive SQLite (§3) : retour à l'identique, contrôleurs compris ;
3. soit installer les **mêmes** versions de fournisseurs (`clusterctl init --core cluster-api:v1.12.<N> --infrastructure proxmox:v0.9.<N> --ipam in-cluster:<N>`), puis :
   ```
   admin@adm01:~$ age -d -i <CLÉ-PRIVÉE> capi-essai-<DATE>.tar.gz.age | tar -xz -C <DOSSIER>
   admin@adm01:~$ clusterctl move --from-directory <DOSSIER> --kubeconfig ~/.config/workbook/m18/k3s01.kubeconfig
   ```
4. Vérifier `clusterctl describe cluster capi-essai -n capi-essai`, puis effacer `<DOSSIER>`.

## 6. Talos

```
admin@adm01:~$ export TALOSCONFIG=~/.config/workbook/m18/talosconfig
admin@adm01:~$ talosctl -n 10.10.99.85 get machinetype                     # doit être controlplane (jamais init)
admin@adm01:~$ talosctl -n 10.10.99.85 reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL
admin@adm01:~$ talosctl -n 10.10.99.85 service etcd                        # attendre « Preparing »
admin@adm01:~$ talosctl -n 10.10.99.85 bootstrap --recover-from=./<INSTANTANÉ>.db
# instantané copié depuis /var/lib/etcd/member/snap/db (talosctl cp) : ajouter --recover-skip-hash-check
admin@adm01:~$ talosctl -n 10.10.99.85 health
```
Ne jamais effacer `STATE` sur le nœud de contrôle : il repartirait en maintenance sans configuration. Un nœud perdu se reconstruit depuis sa configuration sauvegardée (`talosctl get mc v1alpha1 -o yaml | yq .spec`) et `talos-secrets.yaml`.

## 7. Après (toutes distributions)

- Nœuds `Ready`, pods système prêts, témoin ou objet de référence lu.
- Contrôleurs qui gardaient un état plus récent (Cluster API, opérateurs) : vérifier qu'ils ont relu l'état (k3s, RKE2 et Talos gèrent la révision etcd ; pour un kubeadm, voir RB-141 et `--bump-revision`).
- Relancer les déploiements, noter RTO et RPO dans `docs/kubernetes/distributions/tests/restaurations.md`, garder `etcd-old-*` / `db.avant-restauration` 7 jours puis les supprimer.
