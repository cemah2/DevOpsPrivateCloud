# k3s sous le capot (M18-E23)

> Relevés faits le <AAAA-MM-JJ> sur `k3s01` (k3s v1.36.5+k3s1, SQLite) et sur le banc `k3s-ha01` (etcd) / `k3s-ha02` (agent). Les valeurs entre crochets sont à remplacer par tes relevés.

## 1. Processus et ports

```
systemd : k3s.service
└─ k3s server                      ← un seul processus : API, ordonnanceur, contrôleurs, kine, kubelet, kube-proxy, superviseur
   ├─ containerd                   ← binaire extrait dans /var/lib/rancher/k3s/data/<hachage>/bin/
   │  └─ containerd-shim-runc-v2   ← un par pod (les conteneurs survivent à l'arrêt du service : KillMode=process)
   └─ …
```

| Port | Qui | Rôle |
|---|---|---|
| 6443 | `k3s server` | superviseur (`/cacerts`, `/ping`, enregistrement des agents) **et** API Kubernetes, sur le même port |
| [6444] | `k3s server` (local) ; `k3s agent` (local) | écouteur interne de l'API derrière le superviseur ; répartiteur local de l'agent |
| 10250 | kubelet | API du kubelet (journaux, `exec`, métriques) |
| 10257, 10259 | contrôleur, ordonnanceur | 127.0.0.1 seulement |
| 2379-2380 | etcd intégré | serveurs en `--cluster-init` seulement (`k3s-ha01`) |
| 8472/udp | Flannel | VXLAN entre nœuds |

## 2. Données

| Donnée | Emplacement |
|---|---|
| Base (SQLite) | `/var/lib/rancher/k3s/server/db/state.db` (+ `-wal`, `-shm`) |
| Base (etcd intégré) | `/var/lib/rancher/k3s/server/db/etcd/` ; instantanés `server/db/snapshots/` |
| Jeton du serveur | `/var/lib/rancher/k3s/server/token` (et `agent-token`) |
| PKI | `/var/lib/rancher/k3s/server/tls/` (et dans la base, chiffrée par le jeton) |
| Configuration | `/etc/rancher/k3s/config.yaml`, `config.yaml.d/`, `registries.yaml` |
| Kubeconfig d'administration | `/etc/rancher/k3s/k3s.yaml` |
| containerd | socket `/run/k3s/containerd/containerd.sock`, configuration générée `agent/etc/containerd/config.toml`, gabarit `config-v3.toml.tmpl`, miroirs `agent/etc/containerd/certs.d/` |
| Modules | `/var/lib/rancher/k3s/server/manifests/` → objets `AddOn` ; `HelmChart` pour les charts |
| Identité de l'agent | `/etc/rancher/node/password` ↔ Secret `kube-system/<nœud>.node-password.k3s` |

## 3. kine : la vie d'une clé

Schéma : `id` (révision), `name`, `created`, `deleted`, `create_revision`, `prev_revision`, `lease`, `value`, `old_value`.

| Étape | Lignes ajoutées | `id` | `created` | `deleted` | `prev_revision` |
|---|---|---|---|---|---|
| création | 1 | [N] | 1 | 0 | 0 |
| modification 1 | 1 | [N+k] | 0 | 0 | N |
| modification 2 | 1 | [N+m] | 0 | 0 | N+k |
| suppression | 1 | [N+p] | 0 | 1 | N+m |

kine n'écrit qu'en ajout (comme le MVCC d'etcd) ; il sert les *watch* en relisant les lignes d'`id` supérieur ; il compacte en supprimant les anciennes versions et note sa révision de compactage dans la ligne `compact_rev_key`. etcd fait la même chose nativement (Raft, MVCC sur bbolt), avec `create_revision`, `mod_revision`, `version`.

## 4. Superviseur et agent

- `/cacerts` et `/ping` sans authentification ; l'API exige un certificat ou un jeton.
- L'agent vérifie l'empreinte de `/cacerts` contre son jeton (`K10<empreinte>::…`), obtient ses certificats, puis parle au serveur par son répartiteur local (`kubelet.kubeconfig` → `https://127.0.0.1:[6444]`), qui suit la liste des serveurs. Ajouter un serveur ne demande rien aux agents.
- Un manifeste retiré de `server/manifests/` **ne supprime pas** ses objets (constaté avec `addon-temoin`, conforme à la doc) ; `--disable` désinstalle.

## 5. kubeadm → k3s

| Je cherche (kubeadm, `k8s-par1`) | Sur k3s |
|---|---|
| pods statiques `/etc/kubernetes/manifests/` | aucun : composants dans le processus `k3s` |
| journal de kube-apiserver (`crictl logs`) | `journalctl -u k3s` |
| `/etc/kubernetes/pki/` | `/var/lib/rancher/k3s/server/tls/` (+ base) |
| `admin.conf` | `/etc/rancher/k3s/k3s.yaml` |
| `/var/lib/etcd` | `server/db/state.db` (SQLite) ou `server/db/etcd/` |
| `etcdctl snapshot save` | `k3s etcd-snapshot save` (etcd) ; copie à froid de `server/db/` + jeton (SQLite) |
| `kubeadm join` + jeton d'amorçage | `k3s agent --server … --token …` (superviseur) |
| `/etc/containerd/config.toml` + `certs.d/` | `agent/etc/containerd/config.toml` généré, `registries.yaml` |
| `crictl` (socket `/run/containerd/`) | `k3s crictl` (socket `/run/k3s/containerd/`) |
| `kubeadm upgrade apply` + paquets | remplacer le binaire (system-upgrade-controller) |
| `kubeadm certs renew` | renouvellement automatique au démarrage s'il reste moins de 120 jours (à vérifier), `k3s certificate rotate` |
| Cilium installé à part | Flannel, CoreDNS, local-path, metrics-server, ServiceLB, Traefik intégrés (`--disable`) |

## 6. Cinq commandes pour l'agence de Lyon

1. `systemctl status k3s` / `k3s-agent` et `journalctl -u k3s -b --no-pager | grep -m 20 -Ei 'error|fatal'`
2. `curl -sk https://<serveur>:6443/ping` (le superviseur répond-il ?)
3. `sudo k3s crictl ps -a` (les conteneurs tournent-ils ?)
4. `sudo k3s etcd-snapshot ls` (dernier instantané local et S3)
5. `sudo k3s check-config` (prérequis noyau)
