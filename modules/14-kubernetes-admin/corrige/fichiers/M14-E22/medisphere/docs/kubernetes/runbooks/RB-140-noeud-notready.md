# RB-140 — Kubernetes : un nœud est `NotReady`

| | |
|---|---|
| Cluster | `k8s-par1` (kubeadm 1.35/1.36), contrôle `k8s-cp01-03` (10.10.40.51-53), travailleurs `k8s-w01-03` (10.10.40.61-63), API `https://k8s-api.par1.medisphere.internal:8443` |
| Déclencheur | `kubectl get nodes` montre `NotReady` (ou `Unknown`) ; pods `Terminating`/`Pending` signalés par une équipe ; plus tard alerte `KubeNodeNotReady` (M21) |
| Accès | kubeconfig personnel (groupe `medisphere:plateforme-admins`), SSH `admin` vers les nœuds, console Proxmox de `pve01`. **Pas** `admin.conf` (bris de glace) |
| Rédigé | M14-E22 (PLAT-1522), à partir de CHG-1517 et de M14-E20 ; rejoué sur les pannes de M14-E35 |
| Durée | 10 à 20 min de diagnostic ; reconstruction d'un travailleur ≈ 30 min (`docs/kubernetes/reconstruction.md`) |
| Renvoie vers | RB-141 (restaurer etcd), RB-143 (certificats), `docs/kubernetes/reconstruction.md` |

## Règles

- **Un seul nœud à la fois.** Deux nœuds ou plus `NotReady`, ou un nœud de contrôle **et** l'API lente : escalade immédiate (étape 0).
- **Interdit** tant que l'étape 3 n'a pas conclu : `kubectl delete node`, `kubeadm reset`, destruction de la VM, `drain --force`, `drain --disable-eviction`.
- Ne jamais redémarrer **deux** nœuds de contrôle à la suite sans avoir vu le premier revenir (`Ready` et membre etcd sain).
- Chaque commande passée est notée dans le journal de l'incident (`docs/kubernetes/journal/`).

## 0. Escalader tout de suite si

- plus d'un nœud est `NotReady` ;
- l'API ne répond plus ou répond en plus de 5 s (`time kubectl get --raw /readyz`) ;
- le nœud est un nœud de contrôle **et** un autre nœud de contrôle a un souci (quorum etcd : 2 sur 3) ;
- `k8s-w03` est touché pendant les heures de recette (les bases de recette y sont).

Escalade : Karim Benali (plateforme), puis Claire Morel.

## 1. Constater (5 min, sans rien modifier)

```
admin@adm01:~$ kubectl get nodes -o wide
admin@adm01:~$ kubectl describe node <NŒUD> | sed -n '/Conditions:/,/Addresses:/p'
admin@adm01:~$ kubectl get lease -n kube-node-lease <NŒUD> -o jsonpath='{.spec.renewTime}{"\n"}'
admin@adm01:~$ kubectl get pods -A -o wide --field-selector spec.nodeName=<NŒUD>
admin@adm01:~$ kubectl get events -A --field-selector involvedObject.kind=Node,involvedObject.name=<NŒUD> --sort-by=.lastTimestamp | tail
```

| Observation | Sens |
|---|---|
| `Ready=Unknown`, « Kubelet stopped posting node status », bail non renouvelé | le kubelet ne parle plus à l'API : VM arrêtée, réseau, kubelet arrêté, API injoignable **depuis le nœud** |
| `Ready=False` avec un message (`container runtime is down`, `PLEG is not healthy`, `NetworkPluginNotReady`) | le kubelet parle, mais déclare un problème : runtime, CNI |
| `MemoryPressure` / `DiskPressure` / `PIDPressure` = `True` | ressources du nœud épuisées : le kubelet évince déjà des pods |

**Ce qui se passe tout seul (à ne pas « corriger ») :**

| Délai après la panne | Effet |
|---|---|
| ≈ 50 s | le contrôleur de nœuds (`--node-monitor-grace-period`, 50 s par défaut depuis 1.32) passe `Ready` à `Unknown` et pose les taints `node.kubernetes.io/unreachable` (ou `not-ready`) en `NoSchedule` et `NoExecute` |
| 300 s | les pods sans tolérance plus longue sont **évincés** (tolérance de 300 s ajoutée à chaque pod) et recréés ailleurs par leurs contrôleurs. Les pods de DaemonSet restent. Les pods de StatefulSet restent `Terminating` tant que le nœud n'a pas confirmé (jamais deux fois le même ordinal) |
| | les données `emptyDir` du nœud (Valkey, PostgreSQL jetable du M14) sont **perdues** pour les pods recréés |

## 2. Diagnostiquer (du plus probable au moins probable, du moins risqué au plus risqué)

| # | Question | Commande | Si oui / si non |
|---|---|---|---|
| 1 | La VM tourne-t-elle ? | `root@pve01:~# qm status <VMID>` (2141-2146) ; console Proxmox | arrêtée → `qm start <VMID>`, étape 4 ; figée (console muette) → `qm reset <VMID>` (⚠️ arrêt brutal), étape 4 |
| 2 | Le nœud répond-il ? | `ping -c3 <IP>` ; `ssh <NŒUD>` depuis `adm01` | non, VM en marche → réseau : console Proxmox, `ip -br a`, `ip route` ; plusieurs nœuds → escalade (bordure, `pve01`) |
| 3 | Le kubelet tourne-t-il ? | `systemctl status kubelet` ; `journalctl -u kubelet --since -15min` | arrêté → `sudo systemctl start kubelet` ; en boucle → lire la **première** erreur (configuration, certificat, swap) |
| 4 | containerd tourne-t-il ? | `systemctl status containerd` ; `sudo crictl info \| head` ; `sudo crictl ps` | arrêté ou sans réponse → `sudo systemctl restart containerd` (les conteneurs survivent) ; vérifier `SystemdCgroup = true` dans `/etc/containerd/config.toml` |
| 5 | Le disque est-il plein ? | `df -h / /var/lib/containerd /var/lib/kubelet` ; `df -i /` | > 90 % → `sudo crictl rmi --prune`, `sudo journalctl --vacuum-size=200M` ; chercher la cause (journaux, `emptyDir` sans limite) |
| 6 | La mémoire ? | `free -m` ; `journalctl -k \| grep -i -E 'oom\|out of memory'` | OOM du kubelet ou de containerd → redémarrer le service ; trouver le pod sans limite (`kubectl top pod -A --sort-by=memory`) |
| 7 | Le swap est-il revenu ? | `swapon --show` | oui → `sudo swapoff -a`, puis trouver ce qui l'a réactivé (`/etc/fstab`, unité `.swap`) ; le rôle `k8s_noeud` le désactive à la convergence |
| 8 | Le certificat du kubelet ? | `sudo openssl x509 -noout -dates -in /var/lib/kubelet/pki/kubelet-client-current.pem` ; journal : `x509: certificate has expired` | expiré → RB-143 |
| 9 | L'horloge ? | `timedatectl` ; `chronyc tracking` | décalage de plus de quelques secondes → `sudo chronyc makestep`, puis voir pourquoi (NTP de `gw01`/`gw02`) |
| 10 | Le réseau des pods (Cilium) ? | `kubectl -n kube-system get pods -o wide \| grep <NŒUD>` ; `cilium status --context k8s-par1` | agent Cilium en échec → supprimer son pod (recréé par le DaemonSet), lire ses journaux |
| 11 | L'API est-elle joignable **depuis le nœud** ? | `curl -sk https://k8s-api.par1.medisphere.internal:8443/livez` sur le nœud | non, mais oui depuis `adm01` → DNS du nœud, flux vers la VIP |

**Nœud de contrôle** : en plus, `sudo crictl ps --name 'etcd|kube-apiserver'`, santé du membre etcd (RB-141), qui porte la VIP (`ip -br a | grep 10.10.40.200` sur les trois), `systemctl status keepalived haproxy`. Tant que deux nœuds de contrôle sur trois vont bien, le cluster fonctionne : **ne rien précipiter**.

## 3. Agir (de la moins risquée à la plus risquée)

| Action | Risque | Prérequis | Retour arrière |
|---|---|---|---|
| Redémarrer le kubelet | nul pour les conteneurs | cause comprise ou probable | — |
| Redémarrer containerd | faible (conteneurs conservés) | idem | — |
| Isoler : `kubectl drain <NŒUD> --ignore-daemonsets --delete-emptydir-data --timeout=10m` | évictions (PDB respectés), `emptyDir` perdus | le nœud répond encore ; ⚠️ jamais `k8s-w03` sans prévenir les équipes (bases) | `kubectl uncordon <NŒUD>` |
| Redémarrer la VM (`sudo systemctl reboot`, sinon `qm reboot <VMID>`) | arrêt des pods du nœud | drain fait si possible ; ⚠️ nœud de contrôle : les deux autres sains | — |
| Retirer et reconstruire un travailleur | élevé (opération longue) | conclusion écrite au journal ; accord de Karim | `docs/kubernetes/reconstruction.md` |
| Remplacer un nœud de contrôle | très élevé (membre etcd) | **escalade** ; instantané etcd récent vérifié | procédure de remplacement du membre etcd (M14-E29), RB-141 |

## 4. Revenir à la normale

- [ ] `kubectl get node <NŒUD>` : `Ready`, sans `SchedulingDisabled` ; plus de taint `not-ready`/`unreachable`.
- [ ] Pods de DaemonSet (Cilium, `sonde-noeud`) `Running` sur le nœud.
- [ ] `kubectl get pdb -A` : `ALLOWED DISRUPTIONS` ≥ 1 partout où il y a plusieurs réplicas.
- [ ] Aucun pod `Pending` ni `Terminating` depuis plus de 5 min.
- [ ] Nœud reconstruit : `task etiquettes` rejouée ; `kubectl get node <NŒUD> -L topology.kubernetes.io/zone`.
- [ ] Nœud de contrôle : trois membres etcd sains, une seule VIP portée.
- [ ] Bases jetables (M14) : prévenir l'équipe si PostgreSQL ou Valkey ont été recréés ; relancer la migration (Job `mediagenda-migration-*`).

## 5. Après l'incident

Compte rendu dans `docs/kubernetes/journal/` (chronologie, cause, durée), ticket de prévention (supervision du disque, du swap, des certificats : M21), mise à jour de ce runbook si une branche manquait.

## Questions de relecture (Karim)

- *« Pourquoi ne pas supprimer tout de suite le nœud pour que les pods repartent ? »* — Ils repartent déjà seuls après 5 min ; supprimer le nœud ne débloque que les pods de StatefulSet, au prix d'un nœud à reconstruire. Seulement à l'étape 3, en connaissance de cause.
- *« Un pod de StatefulSet reste `Terminating` sur le nœud mort ? »* — Rien tant que le nœud peut revenir. S'il ne reviendra pas : `kubectl delete node`, ou en dernier recours `kubectl delete pod --force --grace-period=0` après avoir **vérifié** que la VM est arrêtée (sinon deux instances du même ordinal).
- *« Et si c'est l'API qui est en panne ? »* — Tous les nœuds passent `NotReady` ensemble : ce n'est plus ce runbook, c'est l'étape 0 et le runbook « API injoignable ».

## Historique

| Date | Auteur | Changement |
|---|---|---|
| `<DATE>` | `<MOI>` | Création (M14-E22) |
