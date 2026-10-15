# RB-144 — Un nœud de contrôle de `k8s-par1` est perdu : redémarrer ou remplacer

| | |
|---|---|
| **Portée** | **un** nœud de contrôle sur trois (`k8s-cp0N`) : son membre etcd, son serveur d'API, sa part de la VIP |
| **Hors portée** | deux nœuds de contrôle perdus ou plus : quorum etcd perdu → **RB-141** |
| **Effet de la panne** | aucun pour les utilisateurs si le reste est sain : la VIP bascule (keepalived, quelques secondes), HAProxy retire le serveur d'API mort, etcd garde son quorum (2/3), le gestionnaire de contrôleurs et l'ordonnanceur se réélisent (baux de 15 s environ) |
| **Risque** | pendant la panne, **plus aucune tolérance** : un deuxième nœud de contrôle perdu arrête les écritures de tout le cluster |
| **Durée mesurée** | remplacement complet : <DURÉE> (`docs/kubernetes/tests/perte-plan-controle.md`) |

Dans ce runbook, `etcdctl …` signifie `etcdctl` avec les variables `ETCDCTL_ENDPOINTS`, `ETCDCTL_CACERT`, `ETCDCTL_CERT`, `ETCDCTL_KEY` de RB-141 §6 (membre local, certificat `healthcheck-client`).

## 1. Diagnostiquer : redémarrer ou remplacer ?

```
admin@adm01:~$ kubectl get nodes ; kubectl -n kube-system get pods -o wide --field-selector spec.nodeName=k8s-cp0N
admin@k8s-cp01:~$ sudo etcdctl … member list -w table ; sudo etcdctl … endpoint status --cluster -w table
root@pve01:~# qm status 214N
```

| Constat | Décision |
|---|---|
| VM arrêtée, plantée, injoignable, disque intact | **Redémarrer** la VM : le membre etcd rattrape seul le leader, le kubelet relance les pods statiques. Fin. |
| VM revenue mais etcd du nœud en boucle (données corrompues, `member … has already been bootstrapped`, base illisible) | **Remplacer le membre** (§2), sur la même VM |
| Disque perdu, VM détruite | **Remplacer le nœud** : VM recréée par OpenTofu (`tofu apply -replace` dans `plateforme/infra/envs/k8s`), rôles Ansible, puis §2 à partir de l'étape 3 |
| Deux nœuds de contrôle dans un de ces états | RB-141 |

## 2. Remplacer le membre et le nœud

Préalables : instantané etcd vérifié pris sur un nœud **sain** (`task etcd:instantane NOEUD=k8s-cp01`), les deux autres membres sains.

1. **Arrêter le plan de contrôle du nœud** (s'il tourne encore), pour qu'il ne redémarre pas dans un cluster qui ne le connaît plus :
   `admin@k8s-cp0N:~$ sudo install -d -m 700 /root/manifests-retires && sudo mv /etc/kubernetes/manifests/*.yaml /root/manifests-retires/` ; `sudo systemctl stop etcd-instantane.timer`.
2. **Retirer le membre** depuis un nœud sain :
   `admin@k8s-cp01:~$ sudo etcdctl … member list -w table` → identifiant de `k8s-cp0N` (vérifie **deux fois** le nom et l'URL de pair) → `sudo etcdctl … member remove <ID>` → `member list` : deux membres.
3. **Retirer le nœud de l'API** : `kubectl drain k8s-cp0N --ignore-daemonsets --delete-emptydir-data --force` (le nœud est souvent `NotReady` : le drain peut ne rien évincer) puis `kubectl delete node k8s-cp0N`.
4. **Nettoyer le nœud** (même VM) : `sudo kubeadm reset -f` (il essaie de retirer le membre local : « already removed » est attendu), puis ce que `reset` ne fait pas : `sudo rm -rf /etc/cni/net.d/* /root/manifests-retires`, règles du pare-feu local posées par Cilium (un redémarrage de la VM les efface). Sur une VM neuve : rien.
5. **Rejouer les rôles du nœud** (`containerd`, `k8s_noeud`, `k8s_plan_controle` sans la jonction, **`playbooks/k8s-api-fichiers.yml`** : politique d'audit et configuration de chiffrement **avant** la jonction, sinon le serveur d'API du nouveau nœud ne démarre pas).
6. **Préparer la jonction** depuis un nœud sain :
   `admin@k8s-cp01:~$ sudo kubeadm init phase upload-certs --upload-certs` (clé de certificats, valable 2 h) et `sudo kubeadm token create --print-join-command`.
7. **Joindre** : rôle `k8s_plan_controle` (il joint si `/etc/kubernetes/kubelet.conf` est absent) ou à la main :
   `admin@k8s-cp0N:~$ sudo kubeadm join k8s-api.par1.medisphere.internal:8443 --token <JETON> --discovery-token-ca-cert-hash sha256:<EMPREINTE> --control-plane --certificate-key <CLE> --apiserver-advertise-address 10.10.40.5N`.
   kubeadm ajoute le membre etcd comme **apprenant**, attend qu'il ait rattrapé le leader, puis le promeut (`member list` : `IS LEARNER` passe à `false`).
8. **Rejouer le rôle `etcd_instantane`** sur le nœud, puis `sudo systemctl start etcd-instantane.service`.

## 3. Vérifier

- `member list` : trois membres, tous `started`, aucun apprenant ; `endpoint health --cluster` : trois `healthy`.
- `kubectl get nodes` : `k8s-cp0N` `Ready`, âge récent ; ses quatre pods statiques `Running` ; `kubectl -n kube-system get pod kube-apiserver-k8s-cp0N -o yaml | grep -E 'audit-policy|encryption-provider'`.
- `curl -sk https://10.10.40.5N:6443/readyz` depuis `adm01` ; état des serveurs dans HAProxy (les trois `UP`).
- Instantané réussi depuis ce nœud (`/var/lib/etcd-instantane/dernier-succes`).

## 4. Pourquoi pas « juste restaurer la VM depuis PBS » ?

La sauvegarde de la nuit contient un membre etcd **ancien** qui porte l'identité d'un membre encore inscrit au cluster : au mieux il est rejeté, au pire il perturbe le cluster. Une VM restaurée se traite comme une VM neuve (§2 complet).
