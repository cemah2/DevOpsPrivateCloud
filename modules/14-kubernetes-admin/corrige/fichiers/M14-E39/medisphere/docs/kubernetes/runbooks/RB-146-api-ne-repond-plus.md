# RB-146 — L'API Kubernetes ne répond plus

| | |
|---|---|
| Cluster | `k8s-par1` — `https://k8s-api.par1.medisphere.internal:8443` (VIP 10.10.40.200, VRID 140) |
| Chemin | nom → VIP (keepalived) → HAProxy 8443 → kube-apiserver 6443 (×3) → etcd local |
| Rédigé | M14-E39 (INC-4139) |
| Ne pas faire | redémarrer keepalived ou HAProxy « pour voir », `kubeadm certs renew` sur un certificat aux mauvais SAN, laisser une copie de manifeste dans `/etc/kubernetes/manifests/` |

## 1. Un test par maillon (depuis `adm01`)

```
admin@adm01:~$ dig +short k8s-api.par1.medisphere.internal                        # 10.10.40.200
admin@adm01:~$ nc -vz -w 3 10.10.40.200 8443                                      # refus / délai / ok
admin@adm01:~$ curl -sk -o /dev/null -w '%{http_code}\n' https://10.10.40.200:8443/livez
admin@adm01:~$ for i in 51 52 53; do echo -n "10.10.40.$i "; curl -sk -o /dev/null -w '%{http_code}\n' https://10.10.40.$i:6443/livez; done
admin@adm01:~$ for i in 51 52 53; do openssl s_client -connect 10.10.40.$i:6443 </dev/null 2>/dev/null | openssl x509 -noout -ext subjectAltName | tr -d '\n'; echo; done
admin@adm01:~$ for h in k8s-cp01 k8s-cp02 k8s-cp03; do ssh $h 'echo "$(hostname) $(ip -br -4 addr | grep -c 10.10.40.200)"'; done
```

| Résultat | Maillon | Suite |
|---|---|---|
| nom ne résout pas | DNS (`par1`) | RB-072 (M07) |
| VIP : refus, serveurs directs : 200 | HAProxy sur le porteur de la VIP | § 2 |
| VIP : délai, serveurs directs : 200 | filtrage sur le porteur | § 2 |
| VIP portée par 0 ou 2 nœuds | keepalived (VRRP) | § 2 |
| un serveur direct en échec | kube-apiserver ou son etcd | § 3, RB-147 |
| x509 intermittent, SAN différents d'un nœud à l'autre | certificat | § 4, RB-143 |

## 2. Porteur de la VIP

```
admin@k8s-cp0X:~$ systemctl is-active keepalived haproxy
admin@k8s-cp0X:~$ sudo ss -ltnp | grep -E ':8443|:6443'
admin@k8s-cp0X:~$ grep -nE 'vrrp_script|track_script' /etc/keepalived/keepalived.conf
admin@k8s-cp0X:~$ echo 'show stat' | sudo socat stdio /run/haproxy/admin.sock | cut -d, -f1,2,18
admin@k8s-cp0X:~$ sudo nft list ruleset | grep -n 8443
```

- Dérive par rapport au code : `uv run ansible-playbook playbooks/k8s-cluster.yml --limit k8s-cp0X --tags point_acces --check --diff`, puis sans `--check`.
- Un `vrrp_script` doit être suivi (`track_script`) ; son contrôle doit tester le chemin réel (HAProxy puis un kube-apiserver), pas seulement un processus.
- Aucune table nftables posée à la main ; le filtrage de l'API se décide dans la matrice des flux.

## 3. Un kube-apiserver en échec

```
admin@k8s-cp0X:~$ sudo crictl ps -a --name kube-apiserver
admin@k8s-cp0X:~$ sudo crictl logs <ID> 2>&1 | tail -n 30
admin@k8s-cp0X:~$ sudo journalctl -u kubelet --since -30min | grep -i apiserver | tail
admin@k8s-cp0X:~$ sudo ls -la /etc/kubernetes/manifests/
```

- Le manifeste est un pod statique : le kubelet applique tout fichier du dossier. Corriger le fichier (ou le régénérer : `kubeadm init phase control-plane apiserver --config …`), ne jamais y laisser de copie.
- Erreurs vers etcd : vérifier `--etcd-servers=https://127.0.0.1:2379` puis RB-147.

## 4. Certificat de service incohérent

- `kubeadm certs check-expiration` ne voit pas un SAN manquant : comparer les SAN des trois nœuds (§ 1).
- Régénération sur le nœud en cause : mettre de côté `apiserver.crt`/`apiserver.key`, `kubeadm init phase certs apiserver --config <ClusterConfiguration du ConfigMap kubeadm-config>`, vérifier les SAN affichés (nom et adresse de la VIP, adresse du nœud), relancer le conteneur. `kubeadm certs renew` reprend les SAN de l'ancien certificat : inutile ici.

## 5. Accès sans VIP et bris de glace

- Sans VIP : `kubectl --server https://10.10.40.5X:6443 …` (les SAN contiennent l'adresse de chaque nœud).
- Bris de glace : `admin.conf` (Vault `critique`, `plateforme/k8s` `secrets/`), déchiffré dans un fichier 600 de `/dev/shm`, utilisé, puis détruit ; une ligne dans le journal d'incident (qui, quand, pourquoi). `super-admin.conf` seulement si RBAC lui-même est cassé.
