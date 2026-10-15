# RB-143 — Les certificats de `k8s-par1` : inventaire, échéances, renouvellement

| | |
|---|---|
| **Surveillance** | `k8s-certificats.timer` sur `adm01` (chaque lundi, seuil 30 jours, `ms-alerte@`) → `outils/certificats-echeances.sh` de `plateforme/k8s` |
| **Renouvellement normal** | chaque montée de version (RB-142) renouvelle les certificats feuilles des nœuds de contrôle ; une montée au moins tous les quatre mois (ADR-0141) : le renouvellement manuel est l'exception |
| **Échéance des CA** | `ca`, `etcd-ca`, `front-proxy-ca` : 10 ans à partir de l'amorçage (M14-E04, <DATE-D-AMORÇAGE>) → rotation à **planifier un an avant**, soit <DATE + 9 ans> |
| **Références** | [Certificate Management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/), [PKI certificates and requirements](https://kubernetes.io/docs/setup/best-practices/certificates/), [Kubelet TLS bootstrapping](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/), [Manual Rotation of CA Certificates](https://kubernetes.io/docs/tasks/tls/manual-rotation-of-ca-certificates/) |

## 1. Inventaire

| Certificat (nœuds de contrôle) | Émis par | Sujet / usage | Durée | Renouvelé par |
|---|---|---|---|---|
| `pki/ca.crt` | lui-même | CA du cluster | 10 ans | personne (rotation manuelle, §7) |
| `pki/apiserver.crt` | `ca` | serveur, SAN : `kubernetes`, `kubernetes.default…`, `10.96.0.1`, IP du nœud, VIP `10.10.40.200`, `k8s-api.par1.medisphere.internal` | 1 an | kubeadm (montée, `certs renew`) |
| `pki/apiserver-kubelet-client.crt` | `ca` | client du serveur d'API vers les kubelets (CN=`kube-apiserver-kubelet-client`, sans groupe, lié par la ClusterRoleBinding `kubeadm:apiserver-kubelet-client` au rôle `system:kubelet-api-admin` depuis 1.35.5 et 1.36.1 ; avant : O=`kubeadm:cluster-admins`) | 1 an | kubeadm |
| `pki/front-proxy-ca.crt` / `front-proxy-client.crt` | lui-même / `front-proxy-ca` | agrégation d'API (metrics-server) | 10 ans / 1 an | personne / kubeadm |
| `pki/etcd/ca.crt` | lui-même | CA d'etcd | 10 ans | personne |
| `pki/etcd/server.crt`, `peer.crt` | `etcd-ca` | etcd (clients, pairs), SAN : nom et IP du nœud | 1 an | kubeadm |
| `pki/etcd/healthcheck-client.crt` | `etcd-ca` | client local (sondes, instantanés E24) | 1 an | kubeadm |
| `pki/apiserver-etcd-client.crt` | `etcd-ca` | client du serveur d'API vers etcd | 1 an | kubeadm |
| `pki/sa.key` / `sa.pub` | — | clé de signature des jetons de comptes de service (pas un certificat, pas d'échéance) | — | personne |
| `admin.conf` | `ca` | O=`kubeadm:cluster-admins` (lié par RBAC) | 1 an | kubeadm ; copie en Vault à mettre à jour |
| `super-admin.conf` (`k8s-cp01` seulement) | `ca` | O=`system:masters` (contourne le RBAC) | 1 an | kubeadm ; copie en Vault |
| `controller-manager.conf`, `scheduler.conf` | `ca` | identités des composants | 1 an | kubeadm |

| Certificat (tous les nœuds) | Émis par | Durée | Renouvelé par |
|---|---|---|---|
| kubelet, client (`/var/lib/kubelet/pki/kubelet-client-current.pem`, lien vers le fichier daté) | `ca`, par CSR `kubernetes.io/kube-apiserver-client-kubelet` | 1 an | le kubelet (`rotateCertificates`), CSR approuvée automatiquement par le gestionnaire de contrôleurs |
| kubelet, service (port 10250, `kubelet-server-current.pem`) | `ca`, par CSR `kubernetes.io/kubelet-serving` (depuis E26 ; auto-signé avant) | 1 an | le kubelet demande, **un humain approuve** (§5) |

Identités personnelles (`~/.kube/config`, certificats de 7 jours, E06, E12) : renouvelées par `outils/kubeconfig-personnel.sh`, hors de ce runbook.

## 2. Lire les échéances

```
admin@adm01:~/src/k8s$ outils/certificats-echeances.sh            # tout, tous les nœuds
admin@k8s-cp01:~$ sudo kubeadm certs check-expiration              # vue de kubeadm (un nœud)
admin@adm01:~$ openssl s_client -connect k8s-cp01.par1.medisphere.internal:6443 </dev/null 2>/dev/null | openssl x509 -noout -enddate
```

La troisième commande montre ce que le **processus** sert : après un `certs renew` sans redémarrage, le disque et le processus divergent.

## 3. Renouveler (nœuds de contrôle, un à la fois)

Préalables : instantané etcd vérifié (`task etcd:instantane`), trois membres sains.

```
admin@k8s-cp01:~$ sudo kubeadm certs renew all
admin@k8s-cp01:~$ sudo install -d -m 700 /root/manifests-renouv && sudo cp -a /etc/kubernetes/manifests/. /root/manifests-renouv/
admin@k8s-cp01:~$ for c in kube-apiserver kube-controller-manager kube-scheduler etcd; do
>   sudo mv /etc/kubernetes/manifests/$c.yaml /root/manifests-renouv/$c.en-cours.yaml
>   while sudo crictl ps --name "^$c\$" -q | grep -q .; do sleep 2; done
>   sudo mv /root/manifests-renouv/$c.en-cours.yaml /etc/kubernetes/manifests/$c.yaml
>   sleep 25
> done
admin@adm01:~$ kubectl get --raw /readyz && kubectl -n kube-system get pods -l tier=control-plane -o wide | grep k8s-cp01
admin@adm01:~$ openssl s_client -connect k8s-cp01.par1.medisphere.internal:6443 </dev/null 2>/dev/null | openssl x509 -noout -startdate -enddate
```

Puis `k8s-cp02`, puis `k8s-cp03`, seulement si le nœud précédent est revenu et etcd sain (`etcdctl endpoint health --cluster`). Le kubelet relit `kubelet.conf` seul ; les composants du plan de contrôle, non (d'où les redémarrages).

## 4. Mettre à jour les kubeconfigs du coffre

```
admin@adm01:~/src/k8s$ ssh k8s-cp01 sudo cat /etc/kubernetes/admin.conf \
>   | uv run --project ~/src/ansible ansible-vault encrypt --vault-id critique@$HOME/src/ansible/outils/vault-pass-client.sh \
>     --output secrets/admin.conf.vault
admin@adm01:~/src/k8s$ ssh k8s-cp01 sudo cat /etc/kubernetes/super-admin.conf | … --output secrets/super-admin.conf.vault
admin@adm01:~/src/k8s$ git switch -c certs/renouvellement-$(date +%Y%m%d) && git add secrets/ && git commit -m "chore(secrets): kubeconfigs de bris de glace renouvelés"
```

Jamais de fichier en clair dans le clone ; registre des secrets : nouvelle échéance.

## 5. Certificats de service des kubelets

Activation (une fois, E26) : `serverTLSBootstrap: true` dans le ConfigMap `kube-system/kubelet-config` (et dans `cluster/kubeadm-config.yaml`), puis `playbooks/k8s-kubelet-config.yml` (`kubeadm upgrade node phase kubelet-config` et redémarrage, un nœud à la fois).

À chaque demande (à l'activation, puis environ tous les ans, à 70-90 % de la durée de vie) :

```
admin@adm01:~$ kubectl get csr --field-selector spec.signerName=kubernetes.io/kubelet-serving
admin@adm01:~$ kubectl get csr <CSR> -o jsonpath='{.spec.username}{"\n"}'
admin@adm01:~$ kubectl get csr <CSR> -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -text | grep -A1 -E 'Subject:|Alternative'
admin@adm01:~$ kubectl certificate approve <CSR>
```

Approuver **seulement** si : demandeur `system:node:<NŒUD>` ; sujet `CN=system:node:<NŒUD>, O=system:nodes` ; noms alternatifs = le nom court du nœud et **son** adresse 10.10.40.x (rien d'autre). Une demande qui réclame un autre nom ou une autre adresse est une tentative d'usurpation : refuser (`kubectl certificate deny`) et ouvrir un incident SEC.

Une demande non approuvée n'arrête rien : le kubelet tourne, mais le port 10250 n'a pas de certificat de service valide ; metrics-server (`kubectl top`), `kubectl logs/exec/port-forward` vers ce nœud échouent. L'alerte du lundi le signale (« certificat de service absent »).

## 6. Si un certificat a expiré

- **Feuille d'un nœud de contrôle** (`x509: certificate has expired` pour `kubectl`, composants en erreur) : sur chaque nœud de contrôle, `kubeadm certs renew all` fonctionne **hors ligne** (il n'utilise que la CA sur le disque), puis redémarrages du §3, puis `admin.conf` du nœud pour revenir dans l'API.
- **Client du kubelet** d'un nœud resté éteint au-delà de l'échéance : le nœud reste `NotReady` ; suivre la page *Troubleshooting kubeadm* (« Kubelet client certificate rotation fails ») : régénérer `kubelet.conf` depuis un nœud de contrôle (`kubeadm kubeconfig user` ou phase `kubeconfig kubelet`), ou le plus simple ici : retirer le nœud et le rejoindre (RB-144 pour un nœud de contrôle, E17 pour un travailleur).

## 7. Rotation des CA (à planifier, non jouée)

Procédure de la documentation *Manual Rotation of CA Certificates* : nouvelle CA ajoutée **à côté** de l'ancienne (paquets de confiance), redistribution à tous les composants et kubelets, réémission des feuilles, retrait de l'ancienne CA ; toutes les identités personnelles et `admin.conf` sont réémises ; les jetons de comptes de service ne dépendent pas de la CA (clé `sa.key`). Prévoir une journée et une répétition sur un cluster jetable (M18). Alternative réaliste à 10 ans : reconstruire un cluster neuf et y migrer les charges (GitOps, M20).
