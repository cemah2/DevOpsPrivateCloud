# RB-142 — Monter `k8s-par1` de version

| | |
|---|---|
| **Portée** | Kubernetes (kubeadm, kubelet, kubectl, plan de contrôle, etcd, CoreDNS, kube-proxy) de `k8s-par1` ; une mineure à la fois (N → N+1) ou un correctif (N.x → N.y) |
| **Politique** | ADR-0141 (quand et jusqu'où monter) |
| **Durée** | environ 2 h 30 pour six nœuds (première montée 1.35 → 1.36 : `docs/kubernetes/tests/montee-1.36.md`) |
| **Outils** | `plateforme/ansible` `playbooks/k8s-montee-version.yml` ; `plateforme/k8s` `task etcd:instantane` |
| **Références** | [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/), [Upgrading Linux nodes](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/upgrading-linux-nodes/), [Changing the package repository](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/), [Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/) |

## 1. Lire avant (J-7)

- CHANGELOG de la mineure cible : *Urgent Upgrade Notes*, *Deprecation*, *API Change*, et la section kubeadm. Pour chaque point : touche-t-il `k8s-par1` (option posée dans `cluster/kubeadm-config.yaml`, API utilisée par nos manifestes, *feature gate*, comportement du kubelet) ?
- `kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis` : APIs dépréciées encore appelées (et par qui : journal d'audit, `userAgent`).
- Compatibilité des composants (ADR-0141, liste de contrôle) : Cilium, metrics-server, et à partir du M15-M16 cert-manager, ceph-csi, CloudNativePG, Velero ; containerd (`RELEASES.md`) ; kubectl d'`adm01` et de la CI.
- `kubeadm config validate --config cluster/kubeadm-config.yaml` avec le **nouveau** kubeadm (binaire téléchargé sur `adm01`, pas installé) ; `kubeadm config migrate` seulement si l'API du fichier n'est plus lue par la nouvelle version.

## 2. Préparer (J-1)

- MR « montée vers <VERSION> » : `k8s_version` et `k8s_image_pause` (image *pause* de `kubeadm config images list` de la cible, dont dérive `containerd_image_sandbox`) dans `group_vars/k8s_par1/kubernetes.yml`, `etcd_instantane_outils_version` et son empreinte (version d'etcd de la cible), `kubernetesVersion` de `cluster/kubeadm-config.yaml`. Pipeline vert ; **fusion après** la montée.
- Capacité : drainer un travailleur doit laisser assez de place (`kubectl describe nodes | grep -A5 Allocated`) ; les PDB ne doivent pas bloquer un drain (`kubectl get pdb -A` : `ALLOWED DISRUPTIONS` ≥ 1 partout).
- Annonce aux équipes (Nadia) : fenêtre, effet attendu (aucun si les PDB et les réplicas sont corrects), contact.

## 3. Le jour J — préalables (go/no-go)

- [ ] `kubectl get nodes` : tout `Ready`, rien de cordonné ; `etcdctl endpoint health --cluster` : trois membres sains.
- [ ] `task etcd:instantane` (dans `~/src/k8s`) : instantané **vérifié** ; note son objet S3.
- [ ] Sauvegarde PBS de la nuit des VMs `k8s-*` réussie.
- [ ] Charge témoin lancée (`boucle-temoin.sh`) depuis 10 minutes, aucun échec.

## 4. Premier nœud de contrôle (`k8s-cp01`, à la main)

```
admin@k8s-cp01:~$ sudo sed -i 's#/v1.35/#/v1.36/#' /etc/apt/sources.list.d/kubernetes.sources
admin@k8s-cp01:~$ sudo apt-mark unhold kubeadm && sudo apt-get update && sudo apt-get install -y kubeadm='1.36.5-1.1' && sudo apt-mark hold kubeadm
admin@k8s-cp01:~$ kubeadm version -o short
admin@k8s-cp01:~$ sudo kubeadm upgrade plan v1.36.5
admin@k8s-cp01:~$ sudo kubeadm upgrade apply v1.36.5
admin@adm01:~$ kubectl drain k8s-cp01 --ignore-daemonsets --delete-emptydir-data
admin@k8s-cp01:~$ sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet='1.36.5-1.1' kubectl='1.36.5-1.1' && sudo apt-mark hold kubelet kubectl
admin@k8s-cp01:~$ sudo systemctl daemon-reload && sudo systemctl restart kubelet
admin@adm01:~$ kubectl wait --for=condition=Ready node/k8s-cp01 --timeout=5m && kubectl uncordon k8s-cp01
```

(Fichier et clé : ceux du rôle `k8s_noeud`, `kubernetes.sources` et `/etc/apt/keyrings/kubernetes.asc` ; la clé est la même pour toutes les mineures. Le playbook passe par les tâches `depot.yml` du rôle.) `upgrade plan` doit proposer la cible sans erreur de préflight et montrer le tableau des configurations de composants (`kubeproxy.config.k8s.io`, `kubelet.config.k8s.io`) : colonne « MANUAL UPGRADE REQUIRED » vide. `upgrade apply` remplace etcd, puis le serveur d'API, le gestionnaire de contrôleurs, l'ordonnanceur (un à un, avec retour arrière automatique si un composant ne revient pas), renouvelle les certificats du nœud, met à jour les ConfigMaps `kubeadm-config` et `kubelet-config`, mais **pas encore** CoreDNS ni kube-proxy (ils attendent le dernier nœud de contrôle).

Option documentée pour limiter le blocage des requêtes pendant le redémarrage d'etcd : `sudo killall -s SIGTERM kube-apiserver; sleep 20` juste avant `upgrade apply` (le kubelet relance le serveur d'API). La VIP envoie les requêtes ailleurs pendant ce temps.

## 5. Les autres nœuds (playbook)

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-montee-version.yml -e k8s_cible=1.36.5
```

Nœuds de contrôle restants (`kubeadm upgrade node` ; au dernier, CoreDNS et kube-proxy passent à la nouvelle version), puis travailleurs, un à la fois. Critère de passage au nœud suivant (vérifié par le playbook) : nœud `Ready` à la nouvelle version, remis en service, pods statiques prêts (nœuds de contrôle), `/readyz` à travers la VIP, Deployments témoins disponibles.

## 6. Si ça échoue

| Situation | Que faire |
|---|---|
| `upgrade plan` en erreur de préflight | Ne rien forcer : lire l'erreur (version de kubelet trop ancienne sur un nœud, composant non sain), corriger, relancer. `--ignore-preflight-errors` seulement pour une erreur comprise et notée dans le ticket. |
| `upgrade apply`/`node` échoue et kubeadm a fait son retour arrière | Le nœud tourne avec les anciens manifestes. Lire la sortie, `journalctl -u kubelet`, `crictl ps -a`, `crictl logs` du composant ; corriger ; **relancer la même commande** (idempotente). |
| Arrêt brutal au milieu (VM coupée) | Relancer la même commande. Sinon, les copies de `/etc/kubernetes/tmp/kubeadm-backup-manifests-<date>/` (manifestes) et `kubeadm-backup-etcd-<date>/` (données du membre local) se remettent à la main dans `/etc/kubernetes/manifests/` et `/var/lib/etcd/`, nœud par nœud. |
| Un travailleur ne revient pas `Ready` | Il reste cordonné ; le playbook s'arrête. `journalctl -u kubelet` (option supprimée ? image *pause* ?). Le plan de contrôle à N+1 accepte des kubelets jusqu'à N-2 : on peut finir les autres nœuds et revenir à celui-ci. |
| Le plan de contrôle est passé mais l'écosystème casse (CNI, opérateur) | Pas de retour à N avec kubeadm. Corriger vers l'avant (version compatible du composant). En dernier recours seulement : RB-141 avec l'instantané du §3 **et** paquets N réinstallés sur tous les nœuds — perte des changements depuis l'instantané. |

## 7. Après

- [ ] `kubectl get nodes -o wide` : six nœuds `Ready`, même version ; `kubectl -n kube-system get pods -o wide` : tout `Running`.
- [ ] Images : `kubectl -n kube-system get pods -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u`.
- [ ] `cilium status --wait` ; `kubectl top nodes` ; journal de containerd : plus d'avertissement sur l'image *pause* (rôle `containerd` rejoué, nœud par nœud).
- [ ] Fusion de la MR ; rejouer les rôles des nœuds : **aucun changement** attendu (sinon le code ne décrit pas la réalité).
- [ ] Nouvel instantané etcd (`task etcd:instantane`) : le premier de la nouvelle version.
- [ ] Nettoyage de `/etc/kubernetes/tmp/` sur les nœuds de contrôle, une semaine après (pas avant : c'est le retour arrière de dernier recours).
- [ ] Arrêter la charge témoin, consigner son bilan dans le compte rendu.

## 8. Pour la montée suivante (1.36 → 1.37)

- v1beta3 de la configuration kubeadm n'est plus lue : notre fichier est déjà en v1beta4 (vérifier quand même).
- 1.37 : kube-proxy avertit si `mode` n'est pas explicite ; le nôtre l'est (`iptables`), et au M15 kube-proxy est remplacé par Cilium.
- containerd : 1.37 exige 2.3 ou plus récent (la LTS 2.3 convient).
- La condition d'écosystème de l'ADR-0141 (Cilium, cert-manager, ceph-csi, CloudNativePG, Velero, CAPMOX) doit être remplie **avant** de planifier.
