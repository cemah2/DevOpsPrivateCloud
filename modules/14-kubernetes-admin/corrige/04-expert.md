# Module 14 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Avec Kubernetes, « j'ai supprimé le pod et ça remarche » est presque toujours faux : le contrôleur recrée le même pod avec la même configuration, et la preuve (événements, `lastState`, journaux du conteneur précédent) part avec lui.

Les scripts d'injection sont dans `corrige/pannes/` : `_m14-commun.sh` contient les fonctions partagées (exécution sur les nœuds par SSH ou par l'agent QEMU, `etcdctl` du nœud ou du conteneur etcd, sauvegarde et restauration d'objets en JSON nettoyé, contrôle de santé avant injection, création des **témoins** à partir de `_m14-temoins.yaml`). Chaque modification de fichier est journalisée sur le nœud touché dans `/var/lib/workbook/pannes.log`, et les objets d'origine sont gardés sur `adm01` dans `~/.local/state/workbook/M14-EXX/`.

> **Remarque sur le journal d'audit** : les scripts de panne agissent avec **ton** kubeconfig (`WB_K8S_ADMIN_KUBECONFIG`). Quand tu cherches dans le journal d'audit (M14-E27) qui a modifié un objet, c'est donc ton propre nom que tu trouveras, à l'heure de l'injection. En production, ce serait celui d'InfoGér ou de Lucas : c'est exactement pour cela que chaque intervenant a une identité nominative et qu'on ne partage pas `admin.conf`.

Les sorties reproduites sont **représentatives** : noms de pods, identifiants, adresses et formulations exactes varient selon ton cluster et les versions (Kubernetes 1.36, containerd 2.3, etcd 3.6, CoreDNS 1.14, Cilium 1.20, Debian 13).

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- Les témoins (`_m14-temoins.yaml`) ont été validés par schéma (kubeconform) mais pas déployés sur `k8s-par1` : image `postgres:18-trixie` en utilisateur 999 avec un `emptyDir` monté sur `/var/lib/postgresql` (nouvel emplacement de `PGDATA` des images 18), `valkey/valkey:8.1` en utilisateur 999, MédiAgenda forcé en utilisateur 10001 (si ton image exige un autre UID, corrige `runAsUser` dans le fichier avant la première injection).
- E35 v2 : libellé exact de l'erreur du kubelet sur l'option retirée (`unknown flag: --pod-infra-container-image`).
- E35 v3 : formulation de l'erreur TOML de containerd 2.3.
- E35 v5 : comportement du gestionnaire de certificats du kubelet face à un certificat valide en dates mais signé par une autre autorité (attendu : `Unauthorized` et aucune tentative de ré-amorçage, `bootstrap-kubelet.conf` ayant été supprimé après la jonction).
- E37 v3 : si ton `hosts.toml` de `docker.io` contient un `server` de repli vers Docker Hub, containerd essaie ce serveur après l'échec du cache, le tirage réussit par Internet et la variante est sautée (c'est en soi un constat à corriger : le cache est contourné sans bruit).
- E39 v4 : rechargement du certificat de service par le kube-apiserver (le script relance le conteneur pour ne pas en dépendre).
- E40 v1 : message exact d'etcd 3.6 sur une base bbolt dont les deux pages de méta sont écrasées (attendu : `failed to open database` / `invalid database`).
- E40 v2 : avec l'horloge reculée de 400 jours, `sshd` du nœud peut refuser ton certificat d'utilisateur SSH (« pas encore valide ») ; la clé seule passe si `authorized_keys` la contient encore. Le script agit par l'agent QEMU pour ne pas en dépendre.
- E40 v3 : l'alarme `NOSPACE` est levée par le membre au quota réduit lors des écritures directes ; le nombre de clés écrites avant l'alarme dépend de la taille de ta base.
- E44 : comportement du *watch* avec une `resourceVersion` ancienne : le cache de *watch* du kube-apiserver peut encore servir des versions compactées dans etcd tant qu'elles sont dans sa fenêtre ; l'erreur `410` (`Expired`) peut donc demander plus d'écritures ou de temps que prévu.

---

## Méthode commune aux pannes de Kubernetes

1. **Lire ce que Kubernetes dit.** `kubectl describe` (conditions, événements), `kubectl get events -A --sort-by=.lastTimestamp`, `status` en YAML. Un message d'erreur cite presque toujours l'objet et la règle qui bloquent.
2. **Situer l'étage.** API (VIP, HAProxy, kube-apiserver, certificats) → etcd (quorum, espace, temps) → identité et droits (401, 403, admission) → ordonnanceur (`PodScheduled`) → kubelet (bail, conditions) → runtime (containerd, `hosts.toml`, CRI) → application (journaux, code de sortie, sondes) → DNS et réseau.
3. **Chercher ce qui a bougé.** `kubectl rollout history`, `kubectl diff` contre le code de `plateforme/k8s`, journal d'audit (M14-E27), `ansible-playbook … --check --diff` sur un nœud (la dérive par rapport aux rôles), `journalctl --since`, dates de modification des fichiers (`ls -l --time-style=full-iso`), commentaires laissés dans les fichiers.
4. **Protéger avant d'agir.** Un seul nœud de contrôle à la fois ; instantané etcd récent connu ; jamais `kubectl delete node`, `kubeadm reset`, `etcdctl member remove` d'un membre sain sans nécessité prouvée.
5. **Corriger à la racine, puis faire converger le code.** Un objet corrigé à la main est reporté dans `plateforme/k8s` (ou dans le dépôt de l'équipe) ; un fichier de nœud corrigé à la main est reproduit par le rôle Ansible, rejoué sur le nœud.
6. **Prévenir** : quel contrôle (check du workbook aujourd'hui, alerte Prometheus au module 21, test de CI au module 19) aurait vu la panne avant l'utilisateur ?

---

### M14-E35 — Panne : un nœud est NotReady

**Démarche de diagnostic**

*Symptômes* : variantes 1 à 5, un travailleur `NotReady`, taints `node.kubernetes.io/unreachable` (ou `not-ready`) posées, puis éviction des pods après 300 s ; variante 6, nœud `Ready` mais `DiskPressure`, taint `node.kubernetes.io/disk-pressure:NoSchedule`, pods évincés.

*Hypothèses* : kubelet arrêté ou incapable de démarrer (configuration, option, swap) ; kubelet qui tourne mais ne joint pas l'API (certificat, réseau) ; runtime absent ; ressources du nœud (disque, mémoire, PID).

**Étape 1 — Constater sans toucher.**

```
admin@adm01:~$ kubectl get nodes
NAME       STATUS     ROLES           AGE   VERSION
k8s-w02    NotReady   <none>          12d   v1.36.5
…
admin@adm01:~$ kubectl describe node k8s-w02 | sed -n '/Conditions:/,/Addresses:/p'
  Type             Status    LastHeartbeatTime   Reason              Message
  Ready            Unknown   …                   NodeStatusUnknown   Kubelet stopped posting node status.
admin@adm01:~$ kubectl get lease -n kube-node-lease k8s-w02 -o jsonpath='{.spec.renewTime}{"\n"}'
2026-10-20T06:31:12.104512Z
admin@adm01:~$ kubectl get node k8s-w02 -o jsonpath='{.spec.taints}'
[{"effect":"NoSchedule","key":"node.kubernetes.io/unreachable",…},{"effect":"NoExecute","key":"node.kubernetes.io/unreachable",…}]
```

`Unknown` avec « Kubelet stopped posting node status » : le kubelet ne parle plus du tout (variantes 1 à 5). `False` avec un message (« container runtime is down », « PLEG is not healthy ») : le kubelet parle, mais un étage sous lui est en panne (variante 3). Sur le nœud, les conteneurs tournent encore (`sudo crictl ps` si containerd répond, sinon `ps -ef | grep containerd-shim`) : un nœud `NotReady` n'est pas un nœud arrêté. Kubernetes évincera ses pods (taint `NoExecute`, 300 s de tolérance par défaut) et les recréera ailleurs ; les pods de StatefulSet, eux, ne sont **pas** recréés tant que l'ancien n'est pas confirmé arrêté.

**Étape 2 — Descendre les étages sur le nœud.**

```
admin@k8s-w02:~$ systemctl status kubelet --no-pager
admin@k8s-w02:~$ sudo journalctl -u kubelet -b --no-pager | tail -n 40
admin@k8s-w02:~$ systemctl status containerd --no-pager
```

**Variante 1 — kubelet arrêté et désactivé.**

```
admin@k8s-w02:~$ systemctl status kubelet --no-pager
○ kubelet.service - kubelet: The Kubernetes Node Agent
     Loaded: loaded (/usr/lib/systemd/system/kubelet.service; disabled; preset: enabled)
    Drop-In: /usr/lib/systemd/system/kubelet.service.d
             └─10-kubeadm.conf
     Active: inactive (dead) since …
admin@k8s-w02:~$ sudo journalctl -b --no-pager | grep -E 'Stopped kubelet|Removed .*kubelet'
… systemd[1]: Stopped kubelet.service - kubelet: The Kubernetes Node Agent.
… systemctl[…]: Removed '/etc/systemd/system/multi-user.target.wants/kubelet.service'.
```

Arrêt propre, pas un plantage : quelqu'un a fait `systemctl disable --now kubelet` (souvent « pour qu'il ne redémarre pas pendant la maintenance », puis oublié). `disabled` est le piège : un `start` répare jusqu'au prochain redémarrage du nœud. Correctif : `sudo systemctl enable --now kubelet`. Le rôle `k8s_noeud` doit imposer `enabled: true` et `state: started` (un `--check --diff` le montre).

**Variante 2 — option retirée du kubelet.**

```
admin@k8s-w02:~$ sudo journalctl -u kubelet -b --no-pager | tail -n 3
… kubelet[…]: E… run.go:72] "command failed" err="failed to parse kubelet flag: unknown flag: --pod-infra-container-image"
… systemd[1]: kubelet.service: Main process exited, code=exited, status=1/FAILURE
admin@k8s-w02:~$ systemctl cat kubelet | grep -i environment
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/etc/default/kubelet
admin@k8s-w02:~$ cat /etc/default/kubelet
# IG-2231 (InfoGér) : image sandbox explicite, comme sur l ancien cluster
KUBELET_EXTRA_ARGS="--pod-infra-container-image=registry.par1.medisphere.internal/k8s/pause:3.10.2"
```

Le kubelet redémarre toutes les 10 s (`Restart=always`) et échoue aussitôt. L'option `--pod-infra-container-image` a été **supprimée** en 1.35 (PLAN §6, relevé des versions) : l'image sandbox est désormais celle du runtime (`pinned_images` de containerd, rôle `containerd`). Une recette copiée d'un ancien cluster casse le kubelet au redémarrage suivant. Correctif : retirer la ligne (ou restaurer le fichier tel que le rôle `k8s_noeud` le produit, s'il le gère), `sudo systemctl restart kubelet`. Vérifier que l'image sandbox voulue est bien celle de containerd : `sudo containerd config dump | grep -A2 pinned_images`.

**Variante 3 — configuration de containerd invalide.**

```
admin@adm01:~$ kubectl describe node k8s-w02 | grep -A1 'Ready '
  Ready   False   …   KubeletNotReady   container runtime is down
admin@k8s-w02:~$ systemctl status containerd --no-pager
× containerd.service - containerd container runtime
     Active: failed (Result: exit-code) …
admin@k8s-w02:~$ sudo journalctl -u containerd -b --no-pager | tail -n 3
… containerd[…]: containerd: failed to load TOML from /etc/containerd/config.toml: … expected ']' …
admin@k8s-w02:~$ tail -n 4 /etc/containerd/config.toml
# IG-2232 (InfoGér) : miroir docker.io « comme avant »
[plugins."io.containerd.cri.v1.images".registry.mirrors."docker.io"
  endpoint = ["https://registry.par1.medisphere.internal/v2/dockerhub"]
```

Le kubelet tourne et le dit : `container runtime is down` (il ne joint plus `/run/containerd/containerd.sock`). Les conteneurs déjà lancés survivent (leurs `containerd-shim-runc-v2` restent), mais plus rien ne démarre et le nœud est `NotReady`. Deux erreurs dans l'ajout : la table TOML n'est pas fermée (erreur de syntaxe), et la méthode elle-même (`registry.mirrors` dans `config.toml`) est l'ancienne : containerd 2 utilise `config_path` et les `hosts.toml` (M14-E02, M14-E19), qui existent déjà pour `docker.io`. Correctif : rejouer le rôle `containerd` (qui rend `config.toml` depuis son modèle) sur le nœud, ou retirer les lignes ajoutées ; valider avec `sudo containerd config dump >/dev/null` **avant** de relancer ; `sudo systemctl restart containerd`, puis le kubelet se reconnecte seul.

> **Et `SystemdCgroup = false` ?** C'était la panne classique de containerd 1.x : un pilote de cgroups différent entre containerd (`cgroupfs`) et le kubelet (`systemd`) faisait échouer les pods. Depuis 1.34 (*KubeletCgroupDriverFromCRI*), le kubelet **lit** le pilote dans le CRI : il suit containerd et l'incohérence n'existe plus sous cette forme. Ce qui reste vrai : sur un hôte géré par systemd en cgroup v2, `cgroupfs` est déconseillé (deux gestionnaires de cgroups concurrents) et le rôle `containerd` doit imposer `SystemdCgroup = true`. Ce n'est plus une cause de `NotReady`, c'est pourquoi cette variante n'est pas injectée.

**Variante 4 — swap réactivé.**

```
admin@k8s-w02:~$ sudo journalctl -u kubelet -b --no-pager | grep -i swap | tail -n 1
… "command failed" err="failed to run Kubelet: running with swap on is not supported, please disable swap or set --fail-swap-on flag to false"
admin@k8s-w02:~$ swapon --show
NAME               TYPE SIZE USED PRIO
/swap-infoger.img  file   1G   0B   -2
admin@k8s-w02:~$ grep swap /etc/fstab
/swap-infoger.img none swap sw 0 0  # IG-2233 : mémoire de secours
```

`failSwapOn` vaut `true` par défaut dans la configuration du kubelet ; *NodeSwap* (GA en 1.34) permet d'utiliser du swap avec `LimitedSwap`, mais seulement si on l'a voulu et réglé (`failSwapOn: false`, `memorySwap.swapBehavior`). Correctif : `sudo swapoff /swap-infoger.img`, retirer la ligne de `/etc/fstab`, supprimer le fichier, `sudo systemctl restart kubelet`. Le rôle `k8s_noeud` (M14-E02) désactive le swap et doit aussi **retirer** toute ligne `swap` de `fstab`, sinon un redémarrage remet la panne.

**Variante 5 — certificat client du kubelet d'une autre autorité.**

```
admin@k8s-w02:~$ sudo journalctl -u kubelet -b --no-pager | grep -m3 -i unauthorized
… "Error updating node status, will retry" err="error getting node \"k8s-w02\": Unauthorized"
admin@k8s-w02:~$ grep client-certificate /etc/kubernetes/kubelet.conf
    client-certificate: /var/lib/kubelet/pki/kubelet-client-current.pem
admin@k8s-w02:~$ sudo ls -l /var/lib/kubelet/pki/
… kubelet-client-2026-10-17-06-12-41.pem
… kubelet-client-2026-10-09-11-02-15.pem
… kubelet-client-current.pem -> /var/lib/kubelet/pki/kubelet-client-2026-10-17-06-12-41.pem
admin@k8s-w02:~$ sudo openssl verify -CAfile /etc/kubernetes/pki/ca.crt /var/lib/kubelet/pki/kubelet-client-current.pem
CN = system:node:k8s-w02, O = system:nodes
error 20 at 0 depth lookup: unable to get local issuer certificate
```

Le kubelet tourne et présente un certificat au bon nom (`system:node:k8s-w02`, groupe `system:nodes`), dans ses dates, mais signé par une autorité que l'API ne connaît pas (elle aussi s'appelle `kubernetes` : `openssl x509 -noout -issuer` ne suffit pas, il faut `openssl verify`). L'API le traite en inconnu : `401 Unauthorized`. La rotation automatique ne peut rien : elle s'authentifie avec ce même certificat. Deux correctifs :
- **s'il reste un certificat valide** dans `/var/lib/kubelet/pki/` (le précédent, vérifié par `openssl verify` et `-checkend`), refaire pointer le lien : `sudo ln -sfn /var/lib/kubelet/pki/kubelet-client-<date-valide>.pem /var/lib/kubelet/pki/kubelet-client-current.pem`, `sudo systemctl restart kubelet`, puis supprimer le faux fichier ;
- **sinon**, la procédure de la documentation kubeadm (*Troubleshooting kubeadm*, « Kubelet client certificate rotation fails ») : sur un nœud de contrôle, `sudo kubeadm kubeconfig user --org system:nodes --client-name system:node:k8s-w02 > kubelet.conf` (adapter le nom du cluster et le `server` à `https://k8s-api.par1.medisphere.internal:8443`, ou passer `--config` avec la `ClusterConfiguration`), copier ce fichier en `/etc/kubernetes/kubelet.conf` sur le nœud (600, root), relancer le kubelet, attendre la recréation de `kubelet-client-current.pem`, puis remplacer dans `kubelet.conf` les données intégrées par `client-certificate` et `client-key` pointant vers `/var/lib/kubelet/pki/kubelet-client-current.pem`, et relancer.

Le transfert du `kubelet.conf` régénéré se fait par `scp` entre nœuds ou par `adm01`, jamais par un dépôt ; le fichier contient une clé privée.

**Variante 6 — disque plein.**

```
admin@adm01:~$ kubectl describe node k8s-w02 | grep -E 'DiskPressure|disk-pressure'
  DiskPressure   True   …   KubeletHasDiskPressure   kubelet has disk pressure
Taints:          node.kubernetes.io/disk-pressure:NoSchedule
admin@adm01:~$ kubectl get events -A --field-selector reason=Evicted --sort-by=.lastTimestamp | tail -n 3
… Evicted   The node was low on resource: ephemeral-storage. …
admin@k8s-w02:~$ df -h /var/lib/containerd
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        59G   57G  2.4G  96% /
admin@k8s-w02:~$ sudo du -xh --max-depth=1 /var/lib/containerd | sort -h | tail -n 3
admin@k8s-w02:~$ sudo ls -lh /var/lib/containerd
-rw-r--r-- 1 root root  49G … export-images-infoger.tar
drwxr-xr-x … io.containerd.content.v1.content
…
```

Le kubelet compare l'espace libre du système de fichiers de ses pods (`nodefs`) et de ses images (`imagefs`, ici le même) à ses seuils d'éviction (`nodefs.available<10%`, `imagefs.available<15%` par défaut) : il lance le ramasse-miettes d'images, pose `DiskPressure`, refuse les nouveaux pods et évince des pods (les `BestEffort` d'abord). Évincer ne libère rien ici : le fichier n'appartient à aucun pod. Il n'appartient pas non plus à containerd (aucun des dossiers `io.containerd.*`, absent de `sudo ctr -n k8s.io content ls`) : c'est un export laissé là. Après avoir vérifié ce qu'il est (`file`, date, auteur dans le journal du nœud ou le ticket d'InfoGér), on le **déplace** si quelqu'un en a besoin, sinon on le supprime. La condition retombe après `evictionPressureTransitionPeriod` (5 min par défaut). Les pods évincés restent en `Failed` : `kubectl get pods -A --field-selector=status.phase=Failed` puis suppression, pour la lisibilité.

**Clôture commune** : nœud `Ready`, taints `unreachable`/`not-ready`/`disk-pressure` retirées par le contrôleur, `lab/bin/check 14 35`, puis `lab/bin/break 14 35 --annuler`. RB-140 complété : `corrige/fichiers/M14-E35/medisphere/docs/kubernetes/runbooks/RB-140-ajout-palier-4.md` (sections à fusionner dans ton RB-140).

**Explications**

L'état `Ready` est une **déclaration du kubelet**, renouvelée par son bail (`Lease`, toutes les 10 s) et ses mises à jour de statut. Le contrôleur de nœuds ne voit pas la machine : il voit des baux qui vieillissent. D'où deux familles : « le kubelet ne parle plus » (`Unknown`, variantes 1, 2, 4, 5) et « le kubelet parle et se plaint » (`False` ou condition de pression, variantes 3 et 6). Dans tous les cas, la machine et ses conteneurs peuvent très bien tourner.

**Alternatives**

Remplacer le nœud (drain, retrait, reconstruction par OpenTofu et Ansible, M14-E17 et M14-E23) est une réponse valable quand la cause est matérielle ou inconnue après le temps imparti : c'est l'intérêt d'avoir des nœuds reconstructibles. Mais ici chaque cause est une **dérive** qui reviendrait sur le nœud reconstruit si elle vient d'un mauvais rôle, et qui disparaîtrait sans explication si elle vient d'une intervention manuelle : il faut la comprendre d'abord.

**Pièges classiques**
- Supprimer le nœud (`kubectl delete node`) : ses pods sont supprimés de l'API et recréés ailleurs, et le kubelet, s'il revient, réenregistre un nœud neuf ; on a perdu la preuve et provoqué une interruption.
- `systemctl start kubelet` sans `enable` (variante 1), `swapoff -a` sans corriger `fstab` (variante 4) : la panne revient au prochain redémarrage.
- Croire un certificat sur son nom et ses dates (variante 5) : seul `openssl verify` contre la CA du cluster tranche.
- Vider `/var/lib/containerd` à la main (variante 6) : on casse le magasin d'images et de couches de containerd. On nettoie par `crictl rmi --prune`, et seulement ce qui ne lui appartient pas à la main.

**En production chez MédiSphère**

Alerte sur `kube_node_status_condition` (`Ready` différent de `True` depuis plus de 2 min) et sur l'espace libre des nœuds (module 21) ; détection de dérive Ansible planifiée (`--check --diff`) sur les nœuds ; plus aucune intervention manuelle d'InfoGér sur les nœuds : ils passent par une MR sur les rôles.

---

### M14-E36 — Panne : des pods restent Pending

**Démarche de diagnostic**

*Symptômes* : `kubectl rollout status deploy/agenda` attend ; l'ancienne version sert encore (avec 2 réplicas, `maxUnavailable` à 25 % arrondi à 0 : aucun ancien pod n'est retiré tant que le nouveau n'est pas prêt).

*Hypothèses* : le nouveau pod n'est pas créé (quota, admission) ; il est créé mais pas placé (taint, ressources, affinité, nœuds cordonnés) ; il est placé mais ne démarre pas (image, configuration : M14-E37, E38).

**Étape 1 — La chaîne Deployment → ReplicaSet → pod.**

```
admin@adm01:~$ kubectl -n wb-pannes get deploy,rs,pods -l app.kubernetes.io/name=agenda -o wide
NAME                     READY   UP-TO-DATE   AVAILABLE
deployment.apps/agenda   2/2     1            2
NAME                                DESIRED   CURRENT   READY
replicaset.apps/agenda-6c9f7d8b5d   1         1         0        ← nouveau
replicaset.apps/agenda-7d4b9c6f8c   2         2         2        ← ancien
NAME                          READY   STATUS    NODE
pod/agenda-6c9f7d8b5d-x2kqp   0/1     Pending   <none>
…
```

Variante 1 : le nouveau ReplicaSet a `DESIRED 1`, `CURRENT 0`, et **aucun** pod nouveau n'apparaît. Variantes 2 à 4 : un pod `Pending` sans nœud.

**Variante 1 — quota de pods atteint.**

```
admin@adm01:~$ kubectl -n wb-pannes describe rs agenda-6c9f7d8b5d | tail -n 3
  Warning  FailedCreate  …  replicaset-controller  Error creating: pods "agenda-6c9f7d8b5d-…" is forbidden: exceeded quota: wb-pannes, requested: pods=1, used: pods=6, limited: pods=6
admin@adm01:~$ kubectl -n wb-pannes describe resourcequota wb-pannes
Name:       wb-pannes
Resource    Used  Hard
--------    ----  ----
pods        6     6
…
admin@adm01:~$ kubectl -n wb-pannes get resourcequota wb-pannes -o jsonpath='{.metadata.annotations}'
{"medisphere.internal/ticket":"PLAT-1536 (Lucas) : quota resserré"}
```

Le quota est vérifié **à l'admission** : le pod n'existe jamais, seul le contrôleur de ReplicaSet le sait (dans ses événements). Une mise à jour progressive a besoin d'au moins `maxSurge` pods de marge : un quota ajusté au nombre exact de pods bloque toute livraison. Correctif : remettre la valeur du code (`plateforme/k8s/espaces/`, ici celle du témoin, 20) — `kubectl -n wb-pannes patch resourcequota wb-pannes --type merge -p '{"spec":{"hard":{"pods":"20"}}}'` dans le lab, une MR en vrai — et retirer l'annotation. Le ReplicaSet réessaie seul.

**Variante 2 — taints de maintenance.**

```
admin@adm01:~$ kubectl -n wb-pannes describe pod agenda-6c9f7d8b5d-x2kqp | tail -n 2
  Warning  FailedScheduling  …  default-scheduler  0/6 nodes are available: 1 node(s) had untolerated taint {dedie: bdd}, 2 node(s) had untolerated taint {maintenance: infoger}, 3 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }. preemption: 0/6 nodes are available: 6 Preemption is not helpful for scheduling.
admin@adm01:~$ kubectl get nodes -o custom-columns=NOM:.metadata.name,TAINTS:.spec.taints[*].key
```

Le message additionne les nœuds par raison (1 + 2 + 3 = 6). `maintenance=infoger:NoSchedule` sur `k8s-w01` et `k8s-w02`, en plus de `dedie=bdd` sur `k8s-w03` : plus aucun travailleur n'accepte un pod ordinaire. Les pods déjà placés restent (`NoSchedule` ne chasse personne), d'où l'impression que « tout marche sauf les livraisons ». Une maintenance se fait par `kubectl cordon`/`drain` puis `uncordon` (M14-E17), visible dans `kubectl get nodes` (`SchedulingDisabled`) ; une taint posée à la main ne se voit pas dans cette liste. Correctif : `kubectl taint node k8s-w01 maintenance=infoger:NoSchedule-` (idem `k8s-w02`), après avoir vérifié avec InfoGér que la maintenance est finie.

**Variante 3 — demande de mémoire impossible.**

```
  Warning  FailedScheduling  …  0/6 nodes are available: 1 node(s) had untolerated taint {dedie: bdd}, 2 Insufficient memory, 3 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }. …
admin@adm01:~$ kubectl describe node k8s-w01 | sed -n '/Allocatable:/,/System Info/p' | grep memory
  memory:             7896496Ki
admin@adm01:~$ kubectl -n wb-pannes rollout history deploy/agenda --revision=<N> | grep -A2 Requests
      memory:  10Gi
```

L'ordonnanceur place selon les **demandes** (`requests`), comparées à la mémoire **allouable** du nœud (capacité moins réservations du système et du kubelet), jamais selon l'usage réel (`kubectl top`). 10 Gi ne tiennent sur aucun travailleur de 8 Go. Correctif : `kubectl -n wb-pannes rollout undo deploy/agenda` (la révision précédente était saine), puis corriger le manifeste de l'équipe. Un `LimitRange` avec un `max` aurait refusé ce pod à l'admission, avec un message plus clair que `Pending` : c'est la prévention.

**Variante 4 — affinité vers une baie qui n'existe pas.**

```
  Warning  FailedScheduling  …  0/6 nodes are available: 1 node(s) had untolerated taint {dedie: bdd}, 2 node(s) didn't match Pod's node affinity/selector, 3 …
admin@adm01:~$ kubectl get nodes -L topology.kubernetes.io/zone
admin@adm01:~$ kubectl -n wb-pannes get deploy agenda -o jsonpath='{.spec.template.spec.affinity}' | jq .
… "values": ["par1-baie-d"] …
```

Les zones de M14-E14 sont `par1-baie-a` à `-c` ; `requiredDuringScheduling…` est une exigence, pas une préférence. Correctif : `rollout undo`, puis, si l'intention était de répartir les pods entre baies, une `topologySpreadConstraints` sur `topology.kubernetes.io/zone` (M14-E14) plutôt qu'une affinité.

**Clôture** : `kubectl -n wb-pannes rollout status deploy/agenda` se termine, l'ancien ReplicaSet est à 0, `lab/bin/check 14 36`, `--annuler`. RB-144 : `corrige/fichiers/M14-E38/medisphere/docs/kubernetes/runbooks/RB-144-pod-ne-demarre-pas.md` (sections `Pending`, `ImagePullBackOff`, `CrashLoopBackOff`).

**Explications**

Trois composants peuvent refuser un pod, chacun à sa manière : l'**admission** (quota, LimitRange, Pod Security, politiques) refuse la création — le pod n'existe pas et l'erreur est chez le créateur (ici le ReplicaSet) ; l'**ordonnanceur** refuse le placement — le pod existe, `Pending`, avec `PodScheduled=False` et un événement `FailedScheduling` qui détaille chaque nœud ; le **kubelet** refuse ou rate le démarrage — le pod est placé (M14-E37, E38).

**Alternatives**

`kubectl rollout undo` est le correctif le plus rapide quand la révision précédente était saine (variantes 3 et 4) ; il ne corrige rien pour un quota ou des taints (variantes 1 et 2), qui ne sont pas dans le déploiement. Pour les taints, `kubectl uncordon` ne sert à rien : il ne retire que la taint `node.kubernetes.io/unschedulable`.

**Pièges classiques**
- Chercher le pod refusé par un quota dans `kubectl get pods` : il n'existe pas.
- Ajouter des tolérances à l'application pour « passer » les taints de maintenance : on transforme une erreur d'exploitation en dette dans le manifeste de l'équipe.
- Lire `kubectl top nodes` pour juger de la place : l'ordonnanceur ne regarde que les demandes.

**En production chez MédiSphère**

Quotas et LimitRanges uniquement par le code (`plateforme/k8s/espaces/`), avec une marge documentée pour `maxSurge` ; alerte sur les pods `Pending` depuis plus de 5 minutes (`kube_pod_status_phase`, module 21) ; maintenance des nœuds uniquement par `cordon`/`drain` (RB-140, M14-E17).

---

### M14-E37 — Panne : ImagePullBackOff

**Démarche de diagnostic**

*Symptômes* : un pod en `ErrImagePull`, puis `ImagePullBackOff` (le kubelet espace ses essais).

*Hypothèses* : référence fausse (nom, étiquette, digest) ; identifiants absents ou faux ; résolution du registre par containerd (`hosts.toml`) ; transport (TLS, réseau, bordure) ; politique de Harbor (signature, vulnérabilités).

**Étape 1 — L'événement complet.**

```
admin@adm01:~$ kubectl -n wb-pannes describe pod <pod> | sed -n '/Events:/,$p'
```

**Variante 1 — Secret de tirage périmé.**

```
  Warning  Failed  …  kubelet  Failed to pull image "registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.2.0": failed to pull and unpack image "…": failed to resolve reference "…": failed to authorize: failed to fetch oauth token: unexpected status from GET request to https://registry.par1.medisphere.internal/service/token?scope=repository%3Amedisphere%2Fmediagenda-api%3Apull&service=harbor-registry: 401 Unauthorized
admin@adm01:~$ kubectl -n wb-pannes get secret harbor-pull -o jsonpath='{.metadata.annotations}'
{"medisphere.internal/restaure-depuis":"sauvegarde-2026-06"}
admin@adm01:~$ kubectl -n wb-pannes get secret harbor-pull -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq 'del(.auths[].password, .auths[].auth)'
{ "auths": { "registry.par1.medisphere.internal": { "username": "robot$k8s-pull" } } }
```

`401` à la demande de jeton : le registre a reçu des identifiants et les refuse. Le nom du robot est bon ; reste le secret. Côté Harbor, le journal (`/var/log/harbor/core.log` sur `reg01`) montre l'échec d'authentification du robot. Preuve sur le nœud, sans rien écrire dans l'historique :

```
admin@k8s-w01:~$ read -rs JETON          # jeton du robot, copié depuis Vault
admin@k8s-w01:~$ sudo crictl pull --creds 'robot$k8s-pull':"$JETON" registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.2.0 && unset JETON
Image is up to date for sha256:…
```

Correctif : recréer le Secret depuis la source de vérité (Vault, comme en M14-E19 : `kubectl create secret docker-registry harbor-pull --docker-server=… --docker-username='robot$k8s-pull' --docker-password="$JETON" --dry-run=client -o yaml | kubectl apply -f -`), puis `kubectl -n wb-pannes rollout restart deploy/agenda`. Jamais restaurer un Secret d'identifiants depuis une vieille sauvegarde : les robots se renouvellent.

**Variante 2 — Secret de tirage mal nommé.**

```
  Warning  FailedToRetrieveImagePullSecret  …  kubelet  Unable to retrieve some image pull secrets (harbor-pul); attempting to pull the image may not succeed.
  Warning  Failed  …  kubelet  Failed to pull image "…": … pull access denied, repository does not exist or may require authorization: … 401 Unauthorized
```

Le kubelet ne trouve pas le Secret nommé, le **signale** (événement de type `Warning`, souvent noyé), puis tire en anonyme ; le projet `medisphere` est privé. Correctif : `kubectl -n wb-pannes rollout undo deploy/agenda` ou corriger le nom ; prévention : une règle d'admission (VAP) qui vérifie que les `imagePullSecrets` des espaces d'équipe valent `harbor-pull`, ou le Secret porté par le compte de service par défaut de l'espace (M14-E19).

**Variante 3 — `hosts.toml` de `docker.io` faux.**

```
  Warning  Failed  …  kubelet  Failed to pull image "docker.io/library/busybox:1.37": … failed to resolve reference "docker.io/library/busybox:1.37": docker.io/library/busybox:1.37: not found
admin@k8s-w02:~$ sudo journalctl -u containerd --since -10min --no-pager | grep -i busybox | tail -n 2
… trying next host - response was http.StatusNotFound … host=registry.par1.medisphere.internal …
admin@k8s-w02:~$ cat /etc/containerd/certs.d/docker.io/hosts.toml
server = "https://registry-1.docker.io"     # présent ou non selon ton rôle
[host."https://registry.par1.medisphere.internal/v2/docker-hub"]
  capabilities = ["pull", "resolve"]
  override_path = true
```

Les images MédiAgenda (référencées par `registry.par1.medisphere.internal/…`) passent ; celles nommées `docker.io/…` ne passent plus, sur **tous** les travailleurs : un fichier commun a changé (même dérive partout = rôle mal rejoué). Le chemin du cache est `/v2/dockerhub` (le nom du projet de cache Harbor, M13-E04), pas `/v2/docker-hub`. Correctif : rejouer le rôle `containerd` (`--check --diff` montre l'écart), containerd relit `hosts.toml` à chaque tirage (pas de redémarrage). Constat à écrire dans le journal : si ton fichier contient un `server` de repli vers Docker Hub et que la bordure laisse les nœuds sortir, un cache cassé est **contourné sans bruit** (et les tirages anonymes de Docker Hub sont limités en nombre). Décide-le explicitement dans le rôle.

**Variante 4 — digest inexistant.**

```
  Warning  Failed  …  kubelet  Failed to pull image "registry.par1.medisphere.internal/medisphere/mediagenda-api@sha256:5e1f0c…": … not found
admin@adm01:~$ crane digest registry.par1.medisphere.internal/medisphere/mediagenda-api:v1.2.0   # ou l'API de Harbor, M13
sha256:…  (différent)
```

Épingler par digest est une bonne pratique (immuable, M12-E04) ; un digest recopié à la main est une faute de frappe garantie. Correctif : `rollout undo`, puis épingler le digest **lu** dans Harbor (ou produit par le pipeline de signature, M13-E09).

**Clôture** : le pod démarre, et la preuve qu'il tire **par Harbor** est dans les journaux de Harbor (`/var/log/harbor/registryctl.log` ou `proxy.log` sur `reg01`, M14-E19) ; `lab/bin/check 14 37`, `--annuler`.

**Explications**

Le kubelet ne tire rien lui-même : il demande au runtime par le CRI (`PullImage`, avec les identifiants trouvés dans les `imagePullSecrets` du pod ou de son compte de service). containerd résout le registre avec `config_path` (`/etc/containerd/certs.d/<registre>/hosts.toml`), puis parle au registre (jeton, manifeste, couches). `ErrImagePull` est la première erreur, `ImagePullBackOff` l'attente entre deux essais (jusqu'à 5 min).

**Alternatives**

Pour les identifiants, un Secret de tirage par espace (M14-E19) ou un fournisseur d'identifiants du kubelet (*kubelet credential provider*, binaire sur le nœud), qui évite de copier des Secrets dans chaque espace ; au module 25, External Secrets synchronisera le jeton du robot depuis OpenBao.

**Pièges classiques**
- Corriger en passant l'image en `imagePullPolicy: IfNotPresent` : ça « marche » sur les nœuds qui ont déjà l'image, et ça masque la panne ailleurs.
- Afficher le jeton du robot dans le terminal ou l'historique pour « tester ».
- Contourner le cache en tirant directement de Docker Hub : limites de débit, et plus de trace dans Harbor.

**En production chez MédiSphère**

Alerte sur `ImagePullBackOff` (événements, `kube_pod_container_status_waiting_reason`, module 21) ; renouvellement du jeton du robot planifié et distribué par le code (Vault au module 25) ; test du `hosts.toml` dans la validation du rôle `containerd` (Molecule, M04).

---

### M14-E38 — Panne : CrashLoopBackOff

**Démarche de diagnostic**

*Symptômes* : nouveau pod qui redémarre, `RESTARTS` qui monte, `CrashLoopBackOff` entre deux essais.

*Hypothèses* : le processus sort (configuration, commande, code) ; le runtime ne peut pas le démarrer (exécutable introuvable, droits) ; le kubelet le tue (sonde de vivacité) ; le noyau le tue (OOM).

**Étape 1 — Comment est-il mort ?**

```
admin@adm01:~$ kubectl -n wb-pannes get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState}' | jq .
admin@adm01:~$ kubectl -n wb-pannes describe pod <pod> | sed -n '/Last State/,/Ready/p;/Events:/,$p'
admin@adm01:~$ kubectl -n wb-pannes rollout history deploy/agenda
```

| `lastState.terminated` | Événements | Lecture |
|---|---|---|
| `reason: Error`, `exitCode: 2` | `BackOff` | le processus sort de lui-même : lire ses journaux |
| `reason: Completed` ou `Error` (0 ou 143) | `Unhealthy … Liveness probe failed`, `Killing` | le kubelet l'a tué |
| `reason: OOMKilled`, `exitCode: 137` | `BackOff` | le noyau l'a tué : limite de mémoire |
| `reason: StartError`, `exitCode: 128` | `Failed … executable file not found` | il n'a jamais démarré |

**Variante 1 — variable obligatoire renommée.**

```
admin@adm01:~$ kubectl -n wb-pannes logs <pod> --previous
{"horodatage": "…", "niveau": "CRITICAL", "journal": "mediagenda", "message": "configuration invalide : variable(s) obligatoire(s) absente(s) : MEDIAGENDA_VALKEY_URL"}
admin@adm01:~$ kubectl -n wb-pannes get deploy agenda -o jsonpath='{.spec.template.spec.containers[0].env[*].name}'
MEDIAGENDA_DB_URL MEDIAGENDA_CACHE_URL MEDIAGENDA_VERSION
```

Code 2 et message clair : c'est le comportement documenté de MédiAgenda (`apps/mediagenda/README.md`). La variable a été renommée (`MEDIAGENDA_CACHE_URL` n'existe pas dans l'application).

**Variante 2 — sonde de vivacité « harmonisée ».**

```
  Warning  Unhealthy  …  kubelet  Liveness probe failed: Get "http://10.240.2.57:8080/healthz": dial tcp 10.240.2.57:8080: connect: connection refused
  Normal   Killing    …  kubelet  Container agenda failed liveness probe, will be restarted
```

L'application est saine (ses journaux le disent, `/sante` répond sur 8000) ; la sonde interroge le contrat de **MédiDoc** (`/healthz`, 8080). Le kubelet la tue toutes les 10 s environ (`periodSeconds: 5`, `failureThreshold: 2`). `--previous` montre un arrêt propre après SIGTERM : rien d'anormal côté application.

**Variante 3 — OOMKilled.**

```
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
admin@adm01:~$ kubectl -n wb-pannes get deploy agenda -o jsonpath='{.spec.template.spec.containers[0].resources}'
{"limits":{"cpu":"500m","memory":"32Mi"},"requests":{"cpu":"100m","memory":"32Mi"}}
```

Python, FastAPI, uvicorn et le pool de connexions occupent largement plus de 32 Mi dès le démarrage (mesuré au M14-E08 : de l'ordre de 80 à 120 Mi). Le noyau tue le processus quand le cgroup dépasse `memory.max` (M14-E44). `kubectl logs --previous` est souvent vide ou tronqué : le processus n'a pas eu le temps d'écrire.

**Variante 4 — commande introuvable.**

```
    Last State:     Terminated
      Reason:       StartError
      Message:      failed to create containerd task: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: exec: "mediagenda-api": executable file not found in $PATH
```

Pas de journal du tout : le processus n'a jamais existé. `command` remplace l'`ENTRYPOINT` de l'image (M12-E05) ; la commande de l'image (lue par `crane config …` ou `skopeo inspect --config`) est la bonne.

**Correctif commun** : `kubectl -n wb-pannes rollout undo deploy/agenda` (la révision précédente est saine, vérifiée par `rollout history --revision`), puis la correction dans le manifeste de l'équipe. Vérification : `rollout status` se termine, `RESTARTS` reste à 0 pendant quelques minutes.

**Réponse à Lucas (modèle)** : « `kubectl apply --dry-run=server` et `kubectl diff` n'auraient rien vu : ta configuration est valide pour l'API, c'est l'application qui la refuse (variable), ou le nœud (mémoire, commande), ou la sonde qui ne correspond pas à l'application. Ce qui l'aurait vue : un déploiement dans `mediagenda-dev` **avec attente** (`kubectl rollout status --timeout=120s` dans la CI, qui échoue si le pod ne devient pas prêt), un test de démarrage de l'image avec ses variables (`docker run` en CI, M12), et une relecture du contrat de l'application (README) dans la MR. Et un `rollout undo` automatique si l'attente échoue (`helm upgrade --rollback-on-failure` au module 17, Argo CD au module 20). »

**Explications**

`CrashLoopBackOff` n'est pas une erreur, c'est l'**attente** du kubelet entre deux redémarrages (10 s, doublée à chaque échec, plafonnée à 5 min, remise à zéro après 10 min de fonctionnement). La cause est toujours dans `lastState` et dans les événements, et presque toujours dans les journaux du conteneur **précédent**.

**Alternatives**

Corriger directement le déploiement (`kubectl edit`, `kubectl set env`) est valable dans le lab ; en équipe, le correctif part du dépôt (et `rollout undo` est un pansement qui sera écrasé au prochain déploiement s'il n'est pas reporté).

**Pièges classiques**
- `kubectl logs` sans `--previous` : on lit le conteneur qui vient de redémarrer, pas celui qui est mort.
- Relever la limite de mémoire « à 2 Gi pour être tranquille » : on masque une fuite et on fausse l'ordonnancement.
- Mettre la base dans la sonde de vivacité (`/pret` au lieu de `/sante`) : une panne de base devient une tempête de redémarrages.

**En production chez MédiSphère**

Alerte sur les redémarrages (`kube_pod_container_status_restarts_total`, augmentation sur 15 min, module 21) ; déploiements de la CI avec attente et retour arrière automatique ; contrat des applications (variables, sondes, ports) écrit dans leur README et vérifié par un test de chart (M17).

---

### M14-E39 — Panne : l'API ne répond plus

**Démarche de diagnostic**

*Symptômes* : variantes 1 et 2, `Unable to connect to the server` (refus ou délai) ; variante 3, un kube-apiserver qui redémarre ; variante 4, erreurs x509 intermittentes.

*Hypothèses* : maillon VIP (keepalived), maillon répartiteur (HAProxy, filtrage), maillon serveur (kube-apiserver, sa configuration, son certificat), maillon etcd (M14-E40).

**Étape 1 — Triage maillon par maillon, depuis `adm01`.**

```
admin@adm01:~$ nc -vz -w 3 10.10.40.200 8443
admin@adm01:~$ curl -sk -o /dev/null -w '%{http_code}\n' https://10.10.40.200:8443/livez
admin@adm01:~$ for i in 51 52 53; do printf '%s ' 10.10.40.$i; curl -sk -o /dev/null -w '%{http_code}\n' https://10.10.40.$i:6443/livez; done
admin@adm01:~$ for h in k8s-cp01 k8s-cp02 k8s-cp03; do ssh $h 'hostname; ip -br -4 addr | grep 10.10.40.200'; done
```

| VIP 8443 | Direct 6443 | Lecture |
|---|---|---|
| refusé | 200 ×3 | rien n'écoute sur la VIP : HAProxy (variante 1) |
| délai | 200 ×3 | quelque chose jette les paquets vers la VIP (variante 2) |
| 200 | 200 ×2, échec ×1 | un kube-apiserver en panne, masqué par HAProxy (variante 3) |
| 200 (ou x509 une fois sur trois) | 200 ×3 avec `-k` | certificat incohérent sur un nœud (variante 4) |

**Variante 1 — HAProxy arrêté, VIP restée en place.**

```
admin@k8s-cp02:~$ systemctl is-active haproxy keepalived
inactive
active
admin@k8s-cp02:~$ sudo ss -ltnp | grep 8443
admin@k8s-cp02:~$ tail -n 2 /etc/keepalived/keepalived.conf
# IG-2241 (InfoGér) : suivi retiré, la VIP basculait « sans raison »
admin@k8s-cp02:~$ grep -n -E 'vrrp_script|track_script' /etc/keepalived/keepalived.conf
5:vrrp_script chk_apiserver {
```

Le nœud porte la VIP, keepalived est content, mais personne n'écoute en 8443. Le `vrrp_script` existe encore mais n'est plus suivi par l'instance (`track_script` retiré) : keepalived ne baisse plus sa priorité quand le contrôle échoue, la VIP ne bascule plus. Preuve de la dérive et correctif par le code :

```
admin@adm01:~/src/ansible$ ansible-playbook playbooks/k8s.yml --limit k8s-cp02 --tags keepalived,haproxy --check --diff
… -    track_script {
… -        chk_apiserver
… -    }
admin@adm01:~/src/ansible$ ansible-playbook playbooks/k8s.yml --limit k8s-cp02 --tags keepalived,haproxy
```

(Noms de playbook et d'étiquettes : ceux de ton `plateforme/ansible`, M14-E03.) Le rôle remet `track_script` et relance HAProxy (`state: started`).

**Variante 2 — filtrage du 8443.**

```
admin@k8s-cp02:~$ systemctl is-active haproxy && sudo ss -ltnp | grep 8443
active
LISTEN 0 4096 *:8443 *:* users:(("haproxy",…))
admin@k8s-cp02:~$ curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:8443/livez
200
admin@k8s-cp02:~$ sudo nft list ruleset | grep -B3 8443
table inet durcissement_infoger {
	chain entree {
		type filter hook input priority -5; policy accept;
		iifname != "lo" tcp dport 8443 drop comment "IG-2242 : API réservée au réseau d'administration"
```

Tout va bien **vu du nœud** (y compris le contrôle de keepalived, qui passe par la boucle locale), rien ne passe **vu du réseau**. Correctif : `sudo nft delete table inet durcissement_infoger` ; la table n'est pas persistante (elle disparaîtrait au redémarrage, ce qui rendrait la panne « intermittente » et encore plus trompeuse). Le filtrage voulu par InfoGér (l'API réservée à certains réseaux) se fait par la matrice des flux de la bordure (`group_vars/role_routeur/pare_feu.yml`, rôle `pare_feu`) et, sur les nœuds, par le rôle de pare-feu des nœuds s'il existe, jamais par une table posée à la main.

**Variante 3 — un kube-apiserver qui ne joint plus etcd.**

```
admin@adm01:~$ kubectl -n kube-system get pods -l component=kube-apiserver
kube-apiserver-k8s-cp03   0/1   CrashLoopBackOff   6 …
admin@k8s-cp03:~$ sudo crictl ps -a --name kube-apiserver
admin@k8s-cp03:~$ sudo crictl logs <id> 2>&1 | grep -m2 -i etcd
W… grpc: addrConn.createTransport failed to connect to {Addr: "127.0.0.1:2381", …}. Err: connection error: desc = "transport: authentication handshake failed: tls: first record does not look like a TLS handshake"
admin@k8s-cp03:~$ sudo grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
    - --etcd-servers=https://127.0.0.1:2381
```

HAProxy a retiré ce serveur de la rotation (contrôle de santé) : les clients ne voient rien, la redondance est réduite à deux. Le port 2381 est celui des **métriques** d'etcd, en HTTP. Correctif : remettre `--etcd-servers=https://127.0.0.1:2379` dans le manifeste (le kubelet relance le pod statique de lui-même), ou régénérer le manifeste par kubeadm (`sudo kubeadm init phase control-plane apiserver --config <fichier>` avec la configuration du cluster, à vérifier sur ta version). Ne laisse **aucune** copie de sauvegarde `.yaml` dans `/etc/kubernetes/manifests/` : le kubelet lancerait un second kube-apiserver.

**Variante 4 — certificat de service sans le nom de la VIP.**

```
admin@adm01:~$ for i in 51 52 53; do echo "== $i"; openssl s_client -connect 10.10.40.$i:6443 </dev/null 2>/dev/null | openssl x509 -noout -ext subjectAltName; done
== 52
X509v3 Subject Alternative Name:
    DNS:k8s-cp02, DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, IP Address:10.96.0.1, IP Address:10.10.40.52
```

HAProxy fait du TCP en 8443 : le client parle TLS **avec le kube-apiserver choisi**, et vérifie son certificat contre le nom qu'il a demandé (`k8s-api.par1.medisphere.internal`). Une connexion sur trois tombe sur `k8s-cp02`, dont le certificat a été réémis sans le nom ni l'adresse de la VIP. Correctif sur `k8s-cp02` :

```
admin@k8s-cp02:~$ sudo install -d -m 700 /root/certs-ig-2244 && sudo mv /etc/kubernetes/pki/apiserver.{crt,key} /root/certs-ig-2244/
admin@k8s-cp02:~$ sudo kubectl --kubeconfig /etc/kubernetes/admin.conf -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | sudo tee /root/cluster-config.yaml >/dev/null
admin@k8s-cp02:~$ sudo kubeadm init phase certs apiserver --config /root/cluster-config.yaml
[certs] Generating "apiserver" certificate and key
[certs] apiserver serving cert is signed for DNS names [k8s-api.par1.medisphere.internal k8s-cp02 kubernetes …] and IPs [10.96.0.1 10.10.40.52 10.10.40.200]
admin@k8s-cp02:~$ sudo crictl stop $(sudo crictl ps -q --name '^kube-apiserver$')   # le kubelet le relance avec le nouveau certificat
```

Le fichier ne contient qu'une `ClusterConfiguration` : kubeadm détecte l'adresse d'annonce par l'interface de la route par défaut (vérifie qu'il s'agit bien de 10.10.40.52 dans la sortie ; sinon, ajoute une `InitConfiguration` avec `localAPIEndpoint.advertiseAddress`). `admin.conf` est utilisé ici localement sur un nœud de contrôle, pour lire un ConfigMap : c'est un usage de bris de glace à noter si ton identité personnelle ne marche pas sur ce nœud ; sinon, lis le ConfigMap depuis `adm01` et copie le fichier. Supprime `/root/cluster-config.yaml` et, après vérification, `/root/certs-ig-2244/`.

**Clôture** : les quatre tests du triage au vert, `lab/bin/check 14 39`, `--annuler`. RB-145 : `corrige/fichiers/M14-E39/medisphere/docs/kubernetes/runbooks/RB-145-api-ne-repond-plus.md`.

**Pourquoi la haute disponibilité n'a pas suffi** : elle protège contre la perte d'un **nœud entier** (M14-E29). Ici, un maillon s'est mis en défaut **sans se déclarer défaillant** : HAProxy arrêté sur un nœud qui garde la VIP faute de suivi (v1), un filtre invisible des contrôles locaux (v2), un certificat valide mais faux qu'aucun contrôle de santé ne vérifie (v4). Seule la variante 3 était couverte par la HA (HAProxy a écarté le serveur), et elle a quand même réduit la marge à zéro sans alerte. À changer : contrôle keepalived qui teste le chemin complet par l'adresse du nœud (et pas la boucle locale), suivi obligatoire vérifié par le rôle, contrôle externe du certificat (SAN) de chaque serveur, alerte sur les backends HAProxy `DOWN`.

**Explications**

Chaque maillon a son test et son message : refus TCP (rien n'écoute), délai (quelque chose jette), erreur TLS (un certificat), code HTTP 5xx ou `livez` en échec (le serveur ou son etcd). Tester la VIP **et** chaque serveur en direct sépare tout de suite le chemin des serveurs.

**Alternatives**

kube-vip en pod statique remplace keepalived et HAProxy (VIP portée par un élu du plan de contrôle, ADR-0140) : moins de pièces, mais un démarrage plus délicat (`super-admin.conf` pendant l'initialisation, relevé des versions). Un répartiteur externe (les `lb01`/`lb02` du M07) sort le point d'accès du plan de contrôle, au prix d'une dépendance de plus.

**Pièges classiques**
- `kubeadm certs renew apiserver` pour la variante 4 : `renew` reprend les attributs (dont les SAN) **du certificat existant**, pas ceux de la configuration ; on renouvelle le mauvais certificat.
- Laisser une copie du manifeste dans `/etc/kubernetes/manifests/` (`kube-apiserver.yaml.bak`).
- Redémarrer keepalived « pour voir » : on peut faire basculer la VIP vers un nœud qui a le même défaut, et perdre la preuve.

**En production chez MédiSphère**

Sonde externe de l'API par la VIP et par serveur (durée, code, SAN, date d'expiration) ; alerte sur les backends HAProxy (`haproxy_server_status`, module 21) ; toute modification des nœuds de contrôle par MR sur les rôles ; changement de certificat par la procédure RB-143.

---

### M14-E40 — Panne : un membre etcd est en détresse

**Démarche de diagnostic**

*Symptômes* : variantes 1 et 2, un membre en échec (`endpoint health`), cluster fonctionnel sur deux membres ; variante 3, toutes les écritures refusées (`etcdserver: mvcc: database space exceeded`).

*Hypothèses* : membre arrêté ou qui ne démarre pas (données, configuration) ; membre isolé (réseau, TLS, temps) ; cluster en alarme (espace).

**Étape 1 — État des trois membres, depuis un nœud sain.**

```
admin@k8s-cp01:~$ export ETCDCTL_API=3 ETCDCTL_ENDPOINTS=https://10.10.40.51:2379,https://10.10.40.52:2379,https://10.10.40.53:2379 \
  ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt ETCDCTL_CERT=/etc/kubernetes/pki/etcd/healthcheck-client.crt ETCDCTL_KEY=/etc/kubernetes/pki/etcd/healthcheck-client.key
admin@k8s-cp01:~$ sudo -E etcdctl member list -w table
admin@k8s-cp01:~$ sudo -E etcdctl endpoint status -w table
admin@k8s-cp01:~$ sudo -E etcdctl endpoint health
admin@k8s-cp01:~$ sudo -E etcdctl alarm list
```

Deux membres sur trois suffisent pour écrire (majorité de 3) ; un de plus en moins et l'API s'arrête.

**Variante 1 — base corrompue.**

```
https://10.10.40.53:2379 is unhealthy: failed to commit proposal: context deadline exceeded
admin@k8s-cp03:~$ sudo crictl ps -a --name etcd
… Exited … etcd   7 …
admin@k8s-cp03:~$ sudo crictl logs <id> 2>&1 | tail -n 3
{"level":"panic","msg":"failed to open database","path":"/var/lib/etcd/member/snap/db","error":"invalid database",…}
```

La base bbolt du membre ne s'ouvre plus. On ne répare pas une base bbolt à la main : on **remplace le membre**, ses données viendront des deux autres (procédure de M14-E29, RB-141 section « remplacer un membre »). Un seul nœud est touché à la fois ; on vérifie avant chaque commande que les deux autres membres sont sains.

```
admin@k8s-cp01:~$ sudo -E etcdctl member list -w table | grep k8s-cp03      # relever l'identifiant (ID) de k8s-cp03
admin@k8s-cp01:~$ sudo -E etcdctl member remove <ID-K8S-CP03>
admin@k8s-cp03:~$ sudo mv /etc/kubernetes/manifests/etcd.yaml /root/etcd.yaml && sleep 30 && sudo crictl ps -a --name etcd
admin@k8s-cp03:~$ sudo mv /var/lib/etcd/member /root/etcd-member-corrompu-$(date +%F)
admin@k8s-cp01:~$ sudo -E etcdctl member add k8s-cp03 --peer-urls=https://10.10.40.53:2380
ETCD_INITIAL_CLUSTER="k8s-cp01=https://10.10.40.51:2380,k8s-cp02=https://10.10.40.52:2380,k8s-cp03=https://10.10.40.53:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"
```

Dans `/root/etcd.yaml`, vérifie (ou corrige) `--initial-cluster=` avec la valeur affichée et `--initial-cluster-state=existing` (indispensable si le membre est celui de `kubeadm init`, dont le manifeste d'origine décrit un cluster d'un seul membre ; ces options ne servent qu'au démarrage sur un dossier vide), puis `sudo mv /root/etcd.yaml /etc/kubernetes/manifests/`. Le membre rattrape les données par un instantané envoyé par le leader. Supprime le dossier corrompu une fois les trois membres sains (il contient des Secrets, chiffrés depuis M14-E28 mais pas tous les objets).

**Variante 2 — horloge reculée.**

```
admin@k8s-cp02:~$ sudo crictl logs $(sudo crictl ps -q --name '^etcd$') 2>&1 | grep -m1 x509
{"level":"warn","msg":"rejected connection","remote-addr":"10.10.40.51:…","error":"tls: failed to verify certificate: x509: certificate has expired or is not yet valid: current time 2025-09-15T… is before 2026-10-08T…"}
admin@k8s-cp02:~$ timedatectl
               Local time: lun. 2025-09-15 …
System clock synchronized: no
              NTP service: inactive
```

Si `ssh admin@k8s-cp02` est refusé (certificat d'utilisateur SSH « pas encore valide » pour un nœud qui vit en 2025), passe par la console (`qm terminal 2142` depuis `pve01`). Les certificats des pairs (émis en 2026) ne sont « pas encore valides » pour ce nœud : il refuse ses pairs et ses pairs ne peuvent pas lui parler ; le kubelet du nœud et son kube-apiserver sont touchés de la même façon. Correctif : `sudo systemctl enable --now chrony`, `sudo chronyc makestep`, `chronyc tracking` (`Leap status : Normal`, écart de quelques millisecondes). etcd, le kube-apiserver et le kubelet du nœud reviennent seuls. Cherche ensuite pourquoi le service de temps était arrêté (`journalctl -u chrony`, commandes passées) et vérifie que le rôle de base (M00, M04) l'impose démarré et activé.

**Variante 3 — alarme NOSPACE.**

```
admin@adm01:~$ kubectl -n wb-essais create configmap essai --from-literal=a=b
error: failed to create configmap: etcdserver: mvcc: database space exceeded
admin@k8s-cp01:~$ sudo -E etcdctl alarm list
memberID:… alarm:NOSPACE
admin@k8s-cp01:~$ sudo -E etcdctl endpoint status -w table      # DB SIZE de k8s-cp03 bien plus grande que les autres ? IN USE ?
admin@k8s-cp03:~$ sudo grep quota /etc/kubernetes/manifests/etcd.yaml
    - --quota-backend-bytes=…            (quelques dizaines de Mio)
admin@k8s-cp01:~$ sudo -E etcdctl get "" --from-key --keys-only | grep -v '^$' | cut -d/ -f2 | sort | uniq -c
     64 infoger
   1873 registry
```

Un membre a un quota d'espace minuscule (le défaut est 2 Gio) ; des clés « de test » hors de `/registry` l'ont rempli ; dès qu'un membre dépasse son quota, etcd lève l'alarme `NOSPACE` pour **tout** le cluster, qui n'accepte plus que lectures et suppressions. L'ordre compte :

```
admin@k8s-cp01:~$ sudo -E etcdctl del /infoger/ --prefix                          # pas un objet de Kubernetes : supprimable
admin@k8s-cp01:~$ REV=$(sudo -E etcdctl endpoint status --endpoints=https://10.10.40.51:2379 -w json | jq '.[0].Status.header.revision')
admin@k8s-cp01:~$ sudo -E etcdctl compact "$REV"                                  # retire l'historique jusqu'à REV
admin@k8s-cp01:~$ for ep in https://10.10.40.51:2379 https://10.10.40.52:2379 https://10.10.40.53:2379; do sudo -E etcdctl --endpoints=$ep defrag; done
admin@k8s-cp03:~$ sudo sed -i '/--quota-backend-bytes=/d' /etc/kubernetes/manifests/etcd.yaml   # membre redémarré, seul
admin@k8s-cp01:~$ sudo -E etcdctl endpoint health && sudo -E etcdctl alarm disarm && sudo -E etcdctl alarm list
```

La suppression ne libère rien dans le fichier ; le compactage rend l'espace réutilisable dans la base ; la défragmentation rend l'espace au système de fichiers (et bloque le membre pendant l'opération : un à la fois). Le manifeste corrigé doit l'être aussi dans le code (la `ClusterConfiguration`, `etcd.local.extraArgs`, si tu fixes un quota explicite). Ne supprime **jamais** des clés `/registry/…` pour faire de la place : ce sont des objets de Kubernetes, à supprimer par l'API (`kubectl delete`) s'il le faut.

**Clôture** : trois membres sains, aucune alarme, écriture d'essai réussie, `lab/bin/check 14 40`, `--annuler`. RB-146 : `corrige/fichiers/M14-E40/medisphere/docs/kubernetes/runbooks/RB-146-etcd-en-detresse.md`.

**Explications**

etcd est un journal répliqué par Raft : un membre qui ne lit plus ses données (v1) ou ne fait plus confiance à ses pairs (v2) est simplement hors du quorum, que les deux autres maintiennent. L'alarme d'espace (v3) est une protection : mieux vaut un cluster en lecture seule qu'un disque plein qui corromprait la base. Compactage et défragmentation sont deux opérations distinctes : la première porte sur l'historique MVCC (les révisions), la seconde sur le fichier bbolt.

**Alternatives**

Restaurer un instantané (RB-141) n'a de sens que si le quorum est **perdu** ; avec deux membres sains, c'est perdre toutes les écritures depuis l'instantané pour rien. Pour la v1, `kubeadm join phase control-plane-join etcd` peut refaire l'ajout du membre à la place des commandes `etcdctl` (à vérifier sur ta version : il attend une configuration de jonction complète).

**Pièges classiques**
- `member remove` du mauvais identifiant : on retire un membre sain et on tombe à un membre, sans quorum.
- Retirer le membre et relancer le pod sans vider son dossier de données : il redémarre avec son ancien identifiant et est rejeté.
- Défragmenter les trois membres en même temps (`--cluster`) : trois membres bloqués, l'API suspendue.
- `alarm disarm` avant d'avoir libéré l'espace : l'alarme revient à la prochaine écriture.

**En production chez MédiSphère**

Alertes sur `etcd_server_has_leader`, `etcd_mvcc_db_total_size_in_bytes` (par rapport au quota), le temps de `fsync` et l'écart d'horloge des nœuds (module 21) ; défragmentation planifiée membre par membre, jamais sur le leader en premier ; aucune écriture directe dans etcd hors procédure.

---

### M14-E41 — Panne : accès refusé

**Démarche de diagnostic**

*Symptômes* : variante 1, `Unauthorized` pour toi ; variante 2, `Forbidden` pour une équipe ; variante 3, une création de pod refusée ; variante 4, une application qui reçoit 403.

*Hypothèses* : authentification (certificat, jeton), autorisation (liaison, rôle, sujet), admission (politique), identité de charge de travail (compte de service, jeton monté).

**Variante 1 — ton certificat a expiré.**

```
admin@adm01:~$ kubectl get nodes
error: You must be logged in to the server (Unauthorized)
admin@adm01:~$ kubectl config view --raw --minify -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -subject -issuer -dates
subject=O=medisphere:plateforme-admins, CN=<MOI>
issuer=CN=kubernetes
notBefore=Sep  8 04:05:00 2026 GMT
notAfter=Sep 15 04:05:00 2026 GMT
```

`401` : l'API n'a même pas regardé tes droits. Le certificat est bien signé par la CA du cluster, à ton nom et dans ton groupe, mais expiré. Correctif : `outils/kubeconfig-personnel.sh` (M14-E06). Point à vérifier dans **ton** script : s'il renouvelle en passant par l'API des CSR avec ton identité courante, il ne peut pas fonctionner avec un certificat déjà expiré. Il faut alors une identité de secours légitime : `kubeadm kubeconfig user --client-name <MOI> --org medisphere:plateforme-admins --validity-period 168h` sur un nœud de contrôle (SSH, sudo, CA du cluster), ou `admin.conf` en bris de glace (Vault `critique`, ligne dans le journal, fichier détruit après). Dans les deux cas, corrige le script pour qu'il prévienne **avant** l'expiration (date affichée à chaque usage, minuterie qui avertit à J-1). Pas de révocation possible d'un certificat client dans Kubernetes (M14-E12) : c'est pour cela qu'ils sont courts.

**Variante 2 — sujet de RoleBinding mal orthographié.**

```
admin@adm01:~$ kubectl auth can-i --list -n mediagenda-dev --as julien.petit --as-group medisphere:mediagenda-devs | head -n 4
Resources                                       Non-Resource URLs   Resource Names   Verbs
selfsubjectreviews.authentication.k8s.io        []                  []               [create]
…                                               (plus rien d'autre)
admin@adm01:~$ kubectl -n mediagenda-dev get rolebindings -o custom-columns=NOM:.metadata.name,ROLE:.roleRef.name,SUJETS:.subjects[*].name
mediagenda-devs   mediagenda-dev-edition   medisphere:mediagenda-dev
admin@k8s-cp01:~$ sudo jq -c 'select(.objectRef.resource=="rolebindings" and .verb=="patch") | {t:.requestReceivedTimestamp,u:.user.username,n:.objectRef.name}' /var/log/kubernetes/audit/audit.log
```

(Le nom de ta liaison et de ton rôle sont ceux de M14-E11.) Le sujet vise `medisphere:mediagenda-dev` au lieu du groupe `medisphere:mediagenda-devs` ; RBAC compare des chaînes, sans erreur ni avertissement. Le journal d'audit est réparti sur les trois nœuds de contrôle (chacun journalise les requêtes qu'il a servies) : cherche sur les trois. Correctif : réappliquer le code (`task appliquer` dans `plateforme/k8s`, le fichier de `rbac/` est juste), et vérifier avec `auth can-i --list`.

**Variante 3 — politique d'admission trop large.**

```
admin@adm01:~$ kubectl -n wb-pannes describe rs -l app.kubernetes.io/name=postgres | tail -n 1
  Warning  FailedCreate  …  Error creating: pods "postgres-…" is forbidden: ValidatingAdmissionPolicy 'sec-volumes-locaux' with binding 'sec-volumes-locaux' denied request: Les volumes locaux sont interdits sur les nœuds partagés (SEC-1541).
admin@adm01:~$ kubectl get validatingadmissionpolicy sec-volumes-locaux -o jsonpath='{.spec.validations[0].expression}{"\n"}'
!has(object.spec.volumes) || object.spec.volumes.all(v, !has(v.hostPath) && !has(v.emptyDir))
```

L'intention de Sophie (« pas de `hostPath` ») est légitime ; l'expression interdit aussi `emptyDir`, qui n'est pas un accès au système de fichiers de l'hôte mais un dossier jetable du pod (limitable par `sizeLimit`). Correctif sans désactiver la sécurité : corriger l'expression en `!has(object.spec.volumes) || object.spec.volumes.all(v, !has(v.hostPath))`, la tester d'abord en `validationActions: [Warn]` ou par `kubectl apply --dry-run=server` d'un pod avec `emptyDir` et d'un pod avec `hostPath`, puis repasser en `Deny`, et la mettre dans `plateforme/k8s/admission/` par MR relue par Sophie. Le ReplicaSet de `postgres` réessaie avec un délai croissant : `kubectl -n wb-pannes rollout restart deploy/postgres` accélère. Note que le profil Pod Security `restricted` de l'espace interdit **déjà** `hostPath` : la politique faisait doublon sur ces espaces.

**Variante 4 — sujet de compte de service dans le mauvais espace.**

```
admin@adm01:~$ kubectl -n wb-pannes logs deploy/sonde-api --tail=2
2026-… lecture de l'API : ECHEC
admin@adm01:~$ kubectl auth can-i list pods -n wb-pannes --as system:serviceaccount:wb-pannes:sonde-api
no
admin@adm01:~$ kubectl -n wb-pannes get rolebinding sonde-api -o jsonpath='{.subjects}'
[{"kind":"ServiceAccount","name":"sonde-api","namespace":"default"}]
```

Un sujet `ServiceAccount` est identifié par son nom **et** son espace : `default/sonde-api` n'existe même pas, et RBAC ne le vérifie pas. Correctif : remettre `namespace: wb-pannes` (dans le code de l'équipe). Le pod n'a pas besoin d'être relancé : son jeton est bon, ce sont ses droits qui manquaient.

**Clôture** : `lab/bin/check 14 41`, `--annuler`. RB-147 : `corrige/fichiers/M14-E41/medisphere/docs/kubernetes/runbooks/RB-147-acces-refuse.md`.

**Explications**

Trois portes, trois codes : authentification (`401`, l'API ne sait pas qui tu es), autorisation (`403 … cannot <verbe> resource <ressource>`, l'API sait qui tu es et te refuse), admission (`403` ou `422` avec le nom de la politique ou du *webhook*). Le message dit toujours quelle porte, et souvent quel objet.

**Alternatives**

Pour les identités humaines, OIDC (module 24) remplace les certificats clients : expiration courte, révocation par le fournisseur d'identité, groupes centralisés. Pour la v3, un mode `Audit` puis `Warn` avant `Deny` est la manière normale de déployer une politique (M14-E18).

**Pièges classiques**
- Sortir `super-admin.conf` « pour aller vite » : `system:masters` contourne RBAC et ne se révoque pas ; même `admin.conf` doit rester une exception tracée.
- Donner `edit` au niveau du cluster à l'équipe pour « débloquer » (v2) : on élargit au lieu de corriger.
- Supprimer la politique (v3) au lieu de la corriger : la RSSI apprend la régression au prochain audit.

**En production chez MédiSphère**

Matrice de droits attendue versionnée et testée (`auth can-i --list` par groupe et par espace, en CI au module 19) ; alerte sur les `403` en hausse dans le journal d'audit (module 22) ; certificats clients courts avec avertissement avant expiration, puis OIDC (module 24).

---

### M14-E42 — Panne : le DNS du cluster ne répond plus

**Démarche de diagnostic**

*Symptômes* : variantes 1 à 3, `sonde-dns` pas prête, erreurs de résolution dans les pods ; variante 4, `agenda` pas prêt (`/pret` : `postgresql: indisponible`).

*Hypothèses* : pas de serveur (CoreDNS arrêté) ; serveur qui ne démarre pas (configuration) ; serveur qui répond mal (transfert, zone) ; pod qui n'interroge pas le bon serveur (`dnsPolicy`, `dnsConfig`).

**Étape 1 — Quatre résolutions depuis un pod.**

```
admin@adm01:~$ for n in postgres kubernetes.default.svc.cluster.local registry.par1.medisphere.internal deb.debian.org; do
  printf '%-40s ' $n; kubectl -n wb-pannes exec deploy/sonde-dns -- nslookup $n >/dev/null 2>&1 && echo ok || echo ÉCHEC; done
admin@adm01:~$ kubectl -n wb-pannes exec deploy/sonde-dns -- cat /etc/resolv.conf
search wb-pannes.svc.cluster.local svc.cluster.local cluster.local par1.medisphere.internal
nameserver 10.96.0.10
options ndots:5
```

**Étape 2 — Les maillons.**

```
admin@adm01:~$ kubectl -n kube-system get deploy,pods -l k8s-app=kube-dns -o wide
admin@adm01:~$ kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns
admin@adm01:~$ kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
admin@adm01:~$ kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}'
```

**Variante 1 — zéro réplica.** `deployment.apps/coredns 0/0`, aucun point d'accès derrière `kube-dns` : toutes les requêtes expirent (`connection timed out; no servers could be reached`). L'annotation `medisphere.internal/ticket: IG-2251 : économie de ressources` dit le reste. Correctif : `kubectl -n kube-system scale deploy coredns --replicas=2` et retrait de l'annotation. Deux réplicas au minimum, sur deux nœuds (ce que fait kubeadm par anti-affinité préférentielle) : c'est le composant le plus critique du cluster après l'API. À vérifier sur ta version : si `kubeadm upgrade` réapplique le module CoreDNS, il peut remettre le nombre de réplicas par défaut ; le nombre voulu doit être écrit dans le code.

**Variante 2 — Corefile invalide.**

```
coredns-…   0/1   CrashLoopBackOff
admin@adm01:~$ kubectl -n kube-system logs coredns-… --previous
/etc/coredns/Corefile:NN - Error during parsing: Unknown directive 'cache_ttl'
```

CoreDNS relit son Corefile à chaud (greffon `reload`) et **garde l'ancienne configuration** si la nouvelle est invalide : la panne ne se déclare qu'au redémarrage des pods (ici provoqué, en vrai au premier redémarrage de nœud ou à la prochaine montée de version, parfois des semaines plus tard). Correctif : retirer la ligne (la durée de cache se règle dans le bloc `cache 30 { … }`), vérifier le Corefile, `kubectl -n kube-system rollout restart deploy/coredns`.

**Variante 3 — transfert vers un résolveur qui n'existe pas.**

```
postgres                                 ok
kubernetes.default.svc.cluster.local     ok
registry.par1.medisphere.internal        ÉCHEC
deb.debian.org                           ÉCHEC
admin@adm01:~$ kubectl -n kube-system logs -l k8s-app=kube-dns --tail=3
[ERROR] plugin/errors: 2 registry.par1.medisphere.internal. A: read udp 10.240.1.23:41812->10.10.20.250:53: i/o timeout
```

La zone `cluster.local` est servie par le greffon `kubernetes` ; tout le reste part par `forward`, ici vers 10.10.20.250 (aucun hôte). Correctif : `forward . /etc/resolv.conf` (les récurseurs des nœuds, `dns01`/`dns02`) ; le module 15 écrira `forward . 10.10.20.10 10.10.20.16` explicitement. Le greffon `reload` prend la modification en compte en une à deux minutes (journal : `plugin/reload: Running configuration SHA512 = …`).

**Variante 4 — `dnsPolicy: Default` dans l'application.**

```
admin@adm01:~$ kubectl -n wb-pannes get pod <nouveau-pod> -o jsonpath='{.spec.dnsPolicy}{"\n"}'
Default
admin@adm01:~$ kubectl -n wb-pannes debug -it <nouveau-pod> --image=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37 --target=agenda -- cat /etc/resolv.conf
nameserver 10.10.20.10
nameserver 10.10.20.16
search par1.medisphere.internal
```

`Default` ne veut **pas** dire « par défaut » : c'est « comme le nœud ». Le pod interroge les récurseurs de MédiSphère, qui ne connaissent pas `postgres.wb-pannes.svc.cluster.local`. La valeur par défaut est `ClusterFirst`. Correctif : `rollout undo`, puis retrait du champ dans le manifeste de l'équipe. (Le conteneur éphémère `kubectl debug` respecte le profil `restricted` de l'espace si ta version de kubectl propose `--profile=restricted` ; sinon, utilise la sonde DNS pour comparer.)

**Clôture** : quatre résolutions au vert (sauf Internet si la bordure ne le permet pas depuis le VLAN 40 : note-le), `sonde-dns` prête, `lab/bin/check 14 42`, `--annuler`. RB-148 : `corrige/fichiers/M14-E42/medisphere/docs/kubernetes/runbooks/RB-148-dns-du-cluster.md`.

**Explications**

Le pod interroge ce que dit son `/etc/resolv.conf`, écrit par le kubelet selon `dnsPolicy` ; en `ClusterFirst`, c'est l'adresse du Service `kube-dns`, traduite par kube-proxy vers les pods CoreDNS ; CoreDNS répond aux noms du cluster depuis l'API, et transmet les autres. Avec `ndots:5`, un nom de moins de cinq points est d'abord essayé avec chaque domaine de recherche : cinq requêtes ratées avant la bonne pour un nom externe.

**Alternatives**

NodeLocal DNSCache (un cache sur chaque nœud) réduit la charge de CoreDNS et les délais ; un Corefile géré par le code (Helm au module 17, GitOps au module 20) évite les modifications à la main du ConfigMap.

**Pièges classiques**
- Supprimer et recréer le déploiement CoreDNS : on perd la configuration kubeadm et on coupe le DNS de tout le cluster pendant la manœuvre.
- Chercher une NetworkPolicy : il n'y en a pas encore (module 15).
- Ajouter des `hostAliases` dans l'application pour « contourner » : on cache la panne pour un pod et on la laisse pour tous les autres.

**En production chez MédiSphère**

Sonde de résolution interne et externe depuis un pod (c'est le rôle de `sonde-dns`) ; alerte sur les erreurs `SERVFAIL` et la latence de CoreDNS (`coredns_dns_responses_total`, module 21) ; Corefile dans le code, testé (`coredns -conf … -plugins` ou un pod d'essai) avant application.

---

### M14-E43 — Astreinte : le cluster en détresse

**Démarche**

1. **Triage** : symptômes affichés, puis instruments dans l'ordre des dépendances : `kubectl get --raw /livez` (VIP), `curl -k` en direct sur chaque kube-apiserver, `kubectl auth whoami`, SSH et console vers les six nœuds, `etcdctl endpoint health` et `alarm list` depuis un nœud de contrôle, puis `lab/bin/check 14 35` à `14 42` pour la carte.
2. **Priorisation** par dépendances : point d'accès de l'API (E39) et etcd (E40) → ton identité (E41 v1) → nœuds (E35) → plateforme (E42, E41 v3) → charges de travail (E36, E37, E38, E41 v2/v4). Exemples : avec E39 v1 et E36, aucune analyse de l'ordonnancement n'est possible tant que l'API est muette ; avec E40 v3 et E38, le `rollout undo` échoue (`database space exceeded`) : d'abord l'espace d'etcd ; avec E35 et E42, des pods CoreDNS évincés du nœud perdu peuvent faire croire à une panne de DNS, et une vraie panne de DNS peut se cacher derrière ; avec E41 v1 et E39, tu n'as ni identité ni point d'accès : `admin.conf` en direct sur un kube-apiserver sain (`--server https://10.10.40.5x:6443`) est un bris de glace justifié, à écrire dans le post-mortem.
3. **Deux nœuds de contrôle touchés** (E39 et E40 tirés ensemble) : un seul à la fois **dans tes corrections** ; vérifie le quorum après chaque geste sur un nœud de contrôle. L'instantané du script ne sert que si le quorum est perdu (RB-141).
4. **Communication** (modèle) : « 04 h 20 — INC-4150 — Statut : en cours. Impact : plus aucun déploiement possible (API injoignable par la VIP), applications déjà en place non touchées. Cause : trois anomalies distinctes ; la première (point d'accès de l'API sur `k8s-cp02`) est corrigée, la seconde (membre etcd de `k8s-cp03`) est en cours. Risque pour la recette de 8 h : faible si la troisième est traitée avant 6 h. Prochaine communication : 04 h 50. »
5. **Post-mortem** : chronologie horodatée (détection, hypothèses, fausses pistes, corrections), extraits des commandes qui ont prouvé chaque cause, trois causes racines et leurs causes contributives (interventions sans MR, absence de sondes externes, contrôle keepalived local, quota etcd non surveillé…), détection (qu'est-ce qui aurait dû alerter avant Nadia ?), usage éventuel d'`admin.conf` (heure, raison, destruction), actions avec responsable et échéance. Exemple : `corrige/fichiers/M14-E43/medisphere/docs/kubernetes/post-mortems/2026-10-22-INC-4150.md`.

**Grille d'auto-évaluation**
- [ ] Les instruments ont été vérifiés avant le diagnostic (aucune conclusion tirée d'une commande qui passait par une API muette ou un etcd en alarme).
- [ ] Aucun geste interdit du palier ; un seul nœud de contrôle modifié à la fois ; l'instantané n'a pas été restauré (ou sa restauration est justifiée par une perte de quorum prouvée).
- [ ] L'ordre de traitement est justifié par les dépendances ; chaque correction est suivie d'une reprise de **tous** les tests de départ.
- [ ] Quatre communications au moins, avec statut, impact, prochaine étape, prochaine heure.
- [ ] Post-mortem sans coupable, causes racines distinctes des déclencheurs, actions vérifiables, aucun secret.

---

### M14-E44 — Sous le capot : du `kubectl apply` au conteneur

**Solution**

Compte rendu modèle : `corrige/fichiers/M14-E44/medisphere/docs/kubernetes/analyses/du-apply-au-conteneur.md` ; manifeste du pod : `corrige/fichiers/M14-E44/capot.yaml` ; objet de liaison : `corrige/fichiers/M14-E44/binding.json`.

**1. L'API à la main.**

```
admin@adm01:~$ install -d -m 700 ~/capot && cd ~/capot
admin@adm01:~/capot$ kubectl config view --raw --minify -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d > moi.crt
admin@adm01:~/capot$ (umask 077; kubectl config view --raw --minify -o jsonpath='{.users[0].user.client-key-data}' | base64 -d > moi.key)
admin@adm01:~/capot$ kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt
admin@adm01:~/capot$ API=https://k8s-api.par1.medisphere.internal:8443; C=(--cacert ca.crt --cert moi.crt --key moi.key)
admin@adm01:~/capot$ RV=$(curl -sS "${C[@]}" "$API/api/v1/namespaces/wb-essais/configmaps" | jq -r .metadata.resourceVersion); echo $RV
1843211
admin@adm01:~/capot$ curl -sSN "${C[@]}" "$API/api/v1/namespaces/wb-essais/configmaps?watch=1&resourceVersion=$RV&allowWatchBookmarks=true" | jq -c '{type, rv: .object.metadata.resourceVersion, nom: .object.metadata.name}'
{"type":"ADDED","rv":"1843390","nom":"capot"}
{"type":"MODIFIED","rv":"1843402","nom":"capot"}
{"type":"BOOKMARK","rv":"1843466","nom":null}
{"type":"DELETED","rv":"1843471","nom":"capot"}
```

(Dans l'autre terminal : `kubectl -n wb-essais create configmap capot --from-literal=etape=1`, `kubectl -n wb-essais patch configmap capot -p '{"data":{"etape":"2"}}'`, `kubectl -n wb-essais delete configmap capot`.) Une liste a une `resourceVersion` (l'état de la collection à cet instant) ; un *watch* à partir de cette version reçoit **tout** ce qui s'est passé après, sans trou ni doublon. Les `BOOKMARK` ne portent qu'une version : ils permettent au client de reprendre plus loin sans tout relister.

**2. Concurrence optimiste et expiration.**

```
admin@adm01:~/capot$ curl -sS "${C[@]}" "$API/api/v1/namespaces/wb-essais/configmaps/capot" > ancienne.json
admin@adm01:~/capot$ kubectl -n wb-essais patch configmap capot -p '{"data":{"etape":"3"}}'
admin@adm01:~/capot$ curl -sS "${C[@]}" -X PUT -H 'Content-Type: application/json' --data @ancienne.json "$API/api/v1/namespaces/wb-essais/configmaps/capot" | jq '{code, reason, message}'
{"code":409,"reason":"Conflict","message":"Operation cannot be fulfilled on configmaps \"capot\": the object has been modified; please apply your changes to the latest version and try again"}
admin@adm01:~/capot$ curl -sSN "${C[@]}" "$API/api/v1/namespaces/wb-essais/configmaps?watch=1&resourceVersion=<TOUTE-PREMIÈRE-RV>" | head -n 1 | jq '.object | {code, reason, message}'
{"code":410,"reason":"Expired","message":"too old resource version: … (…)"}
```

Le `PUT` porte l'ancienne `resourceVersion` : l'API refuse d'écraser une modification qu'il n'a pas vue (verrouillage optimiste). Le *watch* trop ancien répond `200` puis un événement `ERROR` contenant le statut `410` : la version a quitté la fenêtre du cache de *watch* (et le compactage d'etcd, toutes les 5 minutes, l'a retirée de l'historique). Un *informer* qui reçoit `410` **reliste** puis reprend son *watch* à la version de la nouvelle liste. `kubectl get … -w -v=6` affiche exactement ces deux requêtes (`GET …?limit=500` puis `GET …?watch=true&resourceVersion=…`).

**3. L'ordonnanceur, c'est toi.**

```
admin@adm01:~/capot$ kubectl apply -f capot.yaml
admin@adm01:~/capot$ kubectl -n wb-essais get pod capot -o wide; kubectl -n wb-essais events --for pod/capot
NAME    READY   STATUS    NODE
capot   0/1     Pending   <none>
No events found in wb-essais.
admin@adm01:~/capot$ kubectl -n kube-system get lease kube-scheduler -o jsonpath='{.spec.holderIdentity}{"\n"}'
k8s-cp02_7f0d…
admin@adm01:~/capot$ curl -sS "${C[@]}" -X POST -H 'Content-Type: application/json' --data @binding.json "$API/api/v1/namespaces/wb-essais/pods/capot/binding" | jq '{status, code}'
{"status":"Success","code":201}
admin@adm01:~/capot$ kubectl -n wb-essais events --for pod/capot
Normal  Pulling  …  kubelet  Pulling image "registry.par1.medisphere.internal/dockerhub/library/busybox:1.37"
Normal  Started  …  kubelet  Started container capot
```

Aucun événement `Scheduled` : personne n'a ordonnancé ce pod (l'ordonnanceur par défaut ignore les pods dont `schedulerName` n'est pas le sien). La liaison écrit `spec.nodeName` ; le kubelet de `k8s-w02`, qui surveille les pods de son nœud par *watch*, le démarre. L'API a vérifié le droit `create` sur `pods/binding` et que le pod n'était pas déjà lié.

**4. Le kubelet et le CRI** (sur `k8s-w02`).

```
admin@k8s-w02:~$ sudo crictl pods --name capot
POD ID         CREATED   STATE   NAME    NAMESPACE   ATTEMPT   RUNTIME
3b1c…          2 min     Ready   capot   wb-essais   0         (default)
admin@k8s-w02:~$ sudo crictl inspectp 3b1c… | jq '.status.network.ip, (.info.runtimeSpec.linux.namespaces[] | select(.type=="network"))'
"10.240.2.88"
{"type":"network","path":"/var/run/netns/cni-…"}
admin@k8s-w02:~$ sudo crictl ps --pod 3b1c…
admin@k8s-w02:~$ sudo crictl inspect <id> | jq '.info.pid, .info.runtimeSpec.linux.cgroupsPath'
24517
"kubepods-burstable-pod5d2e….slice:cri-containerd:<id>"
admin@k8s-w02:~$ sudo ctr -n k8s.io containers ls | grep -E '3b1c|<id>'
3b1c…   registry.par1.medisphere.internal/k8s/pause:3.10.2     io.containerd.runc.v2
<id>    registry.par1.medisphere.internal/dockerhub/library/busybox:1.37   io.containerd.runc.v2
admin@k8s-w02:~$ ps -ef --forest | grep -A3 '[c]ontainerd-shim-runc-v2 -namespace k8s.io -id 3b1c'
root  24402  1  … /usr/bin/containerd-shim-runc-v2 -namespace k8s.io -id 3b1c… -address /run/containerd/containerd.sock
65535 24431 24402 … \_ /pause
65534 24517 24402 … \_ sleep 1000000
```

Un pod = un *sandbox* (le conteneur `pause`, qui tient les espaces de noms partagés) + ses conteneurs, tous fils d'un même shim (`containerd-shim-runc-v2`), lui-même rattaché à PID 1 : c'est pourquoi les conteneurs survivent à un arrêt de containerd (M14-E35 v3).

**5. Cgroups et espaces de noms.**

```
admin@k8s-w02:~$ cat /proc/24517/cgroup
0::/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod5d2e….slice/cri-containerd-<id>.scope
admin@k8s-w02:~$ d=/sys/fs/cgroup/kubepods.slice/kubepods-burstable.slice/kubepods-burstable-pod5d2e….slice
admin@k8s-w02:~$ cat $d/cri-containerd-<id>.scope/{cpu.max,cpu.weight,memory.max}
20000 100000
4
67108864
admin@k8s-w02:~$ sudo ls -l /proc/24517/ns /proc/24431/ns | grep -E 'net|ipc|uts|pid '
admin@k8s-w02:~$ sudo nsenter -t 24517 -n ip -br addr
eth0@if37   UP   10.240.2.88/32 …
```

`limits.cpu: 200m` → `cpu.max` = `20000 100000` (20 ms de calcul par période de 100 ms) ; `requests.cpu: 100m` → 102 parts (100 × 1024 / 1000), converties en `cpu.weight` cgroup v2 par la formule de runc `1 + ((parts − 2) × 9999) / 262142` = 4 ; `limits.memory: 64Mi` → `memory.max` = 67108864. Demandes inférieures aux limites : classe `Burstable`, d'où `kubepods-burstable.slice`. Le conteneur partage avec `pause` les espaces `net`, `ipc` et `uts` (mêmes numéros d'inode), pas `pid` ni `mnt`.

**Réponses aux questions d'analyse**

1. *List + watch* : un état complet une fois, puis seulement les changements, dans l'ordre, sans interroger en boucle (charge de l'API et d'etcd divisée d'autant). Sur `410`, l'*informer* reliste et repart de la version de la nouvelle liste ; ses gestionnaires reçoivent les différences.
2. `resourceVersion` garantit l'ordre des changements **pour un watch** et la détection des conflits d'écriture. C'est une valeur opaque : elle vient aujourd'hui de la révision d'etcd, mais la documentation interdit de la comparer comme un nombre ou entre types (*Resource versions* : à traiter comme une chaîne opaque, sauf les comparaisons explicitement autorisées).
3. L'API a vérifié l'authentification, le droit RBAC `create` sur `pods/binding` dans l'espace, que le pod existait et n'était pas déjà lié (`spec.nodeName` vide). Un ordonnanceur personnalisé a besoin, au minimum, de `get/list/watch` sur pods et nœuds, `create` sur `pods/binding`, `patch/update` sur `pods/status`, `create` sur les événements, et d'un bail s'il fait de l'élection.
4. Le réseau est une propriété du pod (une adresse, des ports partagés, `localhost` commun) : le conteneur `pause` tient l'espace réseau, qui survit aux redémarrages des conteneurs applicatifs. Les PID ne sont pas partagés par défaut (isolation, chaque conteneur a son PID 1) ; `shareProcessNamespace: true` les met dans un même espace (le `pause` devient PID 1, signaux et `/proc` visibles d'un conteneur à l'autre).
5. `requests.cpu` → poids (`cpu.weight`, partage proportionnel en cas de contention) ; `limits.cpu` → quota CFS (`cpu.max`) : au-delà, le conteneur est **ralenti** (*throttling*), jamais tué. Au-delà de `limits.memory`, le noyau tue un processus du cgroup (OOM, raison `OOMKilled`).
6. containerd arrêté : les conteneurs continuent (shims), mais rien ne démarre ni ne s'arrête et le kubelet déclare le runtime en panne (`NotReady`). Kubelet arrêté : les conteneurs continuent aussi, mais plus personne ne les surveille (sondes, redémarrages) ni ne renouvelle le bail du nœud : `Unknown`, puis éviction côté API au bout de 5 minutes (les pods sont recréés ailleurs alors que les anciens tournent peut-être encore).
7. `crictl inspectp` montre l'espace réseau réel (chemin `netns`), l'adresse vue par le runtime, le `runtimeHandler`, la spécification OCI du *sandbox*, les montages, les cgroups : ce qu'il faut pour aller voir sur le nœud (`nsenter`, `ip netns`) quand l'API ou le CNI racontent autre chose.

**Pièges classiques**
- Laisser `moi.key` dans `~/capot` ou dans l'historique (`history`) : c'est ta clé d'administrateur pour sept jours.
- Arrêter ou supprimer un conteneur avec `ctr` sous le kubelet : il est recréé, et l'état observé n'est plus le bon.
- Lire `cpu.shares` : c'est l'interface cgroup v1 ; en v2, `cpu.weight`.

---

### M14-E45 — Questions expert : Kubernetes

**Réponses**

1. `kubectl apply` envoie (côté serveur ou client) l'objet à l'API : authentification, autorisation, admission mutante, validation, admission validante, écriture dans etcd. Le contrôleur de Deployment (dans `kube-controller-manager`), qui surveille les Deployments par *watch*, crée un ReplicaSet ; le contrôleur de ReplicaSet crée les pods (sans nœud). L'ordonnanceur, qui surveille les pods sans `nodeName`, choisit un nœud et écrit une liaison. Le kubelet du nœud, qui surveille les pods de son nœud, demande au runtime par le CRI un *sandbox* (`RunPodSandbox` : `pause`, espaces de noms, réseau par le CNI Cilium), tire l'image, crée et démarre les conteneurs (containerd, shim, runc), puis remonte l'état par `pods/status`. Chaque écriture passe par l'API (jamais directement dans etcd), chaque composant lit par *watch*.
2. **QCM — réponse b.** Sans majorité (1 sur 3), etcd refuse les écritures et les lectures linéarisables ; l'API ne peut plus rien modifier, ses lectures cohérentes échouent ou expirent (certaines lectures peuvent encore être servies par le cache de *watch*). Les kubelets ne tuent pas les pods qui tournent (c ; ils gardent leur dernier état connu et l'API ne peut plus rien leur demander). a est faux (un membre seul n'a pas le quorum) ; d est faux (il faudrait reconstruire un cluster d'un membre à partir de ses données : `--force-new-cluster`, procédure de désastre).
3. etcd offre une cohérence forte par Raft, un modèle clé-valeur versionné (MVCC : chaque écriture crée une révision), des transactions conditionnelles (base du verrouillage optimiste) et le *watch* depuis une révision, qui est exactement ce dont l'API a besoin. Une base relationnelle le peut aussi (kine, utilisé par k3s), au prix d'une couche de traduction. Les anciennes révisions s'accumulent : le **compactage** (fait par le kube-apiserver toutes les 5 min) les retire de l'historique, la **défragmentation** rend au disque l'espace libéré dans le fichier bbolt.
4. Authentification → autorisation → admission **mutante** (greffons intégrés comme `ServiceAccount` ou `DefaultStorageClass`, `MutatingAdmissionPolicy`, *webhooks* mutants) → validation du schéma → admission **validante** (Pod Security, `ResourceQuota`, `ValidatingAdmissionPolicy`, *webhooks* validants) → etcd. Un *webhook* injoignable en `failurePolicy: Fail` fait refuser **toutes** les requêtes qu'il intercepte, y compris celles des composants : il faut exclure `kube-system` et les espaces de la plateforme par `namespaceSelector`, ou garder `Ignore` pour ce qui n'est pas de la sécurité. Les politiques CEL (VAP, MAP) s'exécutent dans l'API : pas de service à joindre, pas ce risque.
5. **QCM — réponse b.** Demande < limite : `Burstable`. Sous pression mémoire, le kubelet évince d'abord les pods qui dépassent leur demande, par priorité puis par excès d'usage, avant les `Guaranteed` ; et le noyau tue le conteneur s'il dépasse 256 Mi. a est faux (au-dessus de sa demande, il est candidat à l'éviction) ; c est faux (le kubelet ne modifie pas les limites) ; d est faux (`BestEffort` passent en premier, mais pas seuls).
6. **OOM** : décidé par le noyau, sur le cgroup du conteneur (dépassement de `memory.max`) ou du nœud ; le conteneur est tué et redémarré dans le **même** pod (`OOMKilled`, `restartCount` qui monte). **Éviction** : décidée par le kubelet, sur des seuils du nœud (`memory.available`, `nodefs.available`…) ; le pod entier passe en `Failed` (`Evicted`) et n'est pas redémarré ; un pod de Deployment est recréé ailleurs par son ReplicaSet, un pod nu est perdu.
7. Élection par bail (`Lease` `kube-controller-manager` et `kube-scheduler` dans `kube-system`) : une seule instance tient le bail et travaille, les autres attendent et le prennent s'il n'est pas renouvelé (durée 15 s, renouvellement 10 s par défaut). Le bail compare des durées observées localement, pas des heures absolues entre machines. Un leader qui ne parvient plus à renouveler s'arrête de lui-même avant l'échéance (`renewDeadline`) : deux leaders simultanés ne durent pas plus qu'un intervalle de renouvellement, et les écritures restent protégées par le verrouillage optimiste.
8. Filtrage (les nœuds possibles : taints, affinités, ports, ressources **demandées** contre allouables, volumes…), score (répartition, affinités préférentielles, équilibre), puis liaison (`pods/binding`). `kubectl top` montre l'usage réel ; l'ordonnanceur ne regarde que les demandes : un nœud peu chargé mais dont les pods ont beaucoup demandé est « plein ».
9. **QCM — réponse b.** `kubectl drain` passe par l'API d'éviction, qui respecte les PDB : avec `minAvailable: 2` pour 2 réplicas, aucune éviction n'est jamais permise, le drain réessaie jusqu'à son délai (`--timeout`). a est faux (le drain n'utilise pas `delete`, sauf `--disable-eviction`) ; c est faux (le drain **est** une perturbation volontaire, c'est précisément ce que couvrent les PDB) ; d est faux (le drain ne crée rien ; c'est à la mise à jour progressive que `maxSurge` crée un pod de plus).
10. Un jeton lié est un JWT émis par l'API (`TokenRequest`) pour une audience, avec une expiration, et **lié à un objet** (le pod) : l'API vérifie la signature, l'audience, l'expiration et que l'objet lié existe encore (même UID). Le kubelet le renouvelle avant expiration dans le volume projeté. Les Secrets `service-account-token` contiennent des jetons sans expiration ni lien, copiables et valables tant que le Secret existe : depuis 1.24 ils ne sont plus créés automatiquement, et les anciens inutilisés sont nettoyés (1.29+). Celui de `wb-checks` est une exception assumée (lecture seule, documentée, fichier 600) pour que les checks ne dépendent pas d'un renouvellement.
11. `admin.conf` est dans le groupe `kubeadm:cluster-admins`, lié à `cluster-admin` par une ClusterRoleBinding : il passe par RBAC, on peut le révoquer en supprimant la liaison. `super-admin.conf` est dans `system:masters`, que l'autorisation laisse tout faire **sans** consulter RBAC : il sert si RBAC est cassé, ne se révoque qu'en changeant la CA, et ne doit jamais sortir du coffre.
12. La CA qui expire rend tous les certificats signés par elle invalides : plus aucun composant ne s'authentifie, le cluster s'arrête (procédure longue de rotation de CA). `apiserver-kubelet-client` qui expire : l'API ne peut plus parler aux kubelets (`logs`, `exec`, `port-forward` échouent), le reste marche. `kubeadm certs check-expiration` le dit à l'avance (et une sonde le surveille, M14-E26) ; `kubeadm upgrade apply` et `upgrade node` renouvellent par défaut tous les certificats feuilles (pas la CA), d'où l'intérêt de monter de version au moins une fois par an.
13. Non : au module 14, Cilium est le CNI (adresses, routage, politiques) avec `kubeProxyReplacement=false` ; c'est **kube-proxy**, en mode `iptables`, qui traduit les Services (règles DNAT vers les points d'accès, sur chaque nœud). Au module 15, Cilium remplace kube-proxy par des programmes eBPF (équilibrage au niveau des sockets et du réseau), kube-proxy est retiré et ses règles nettoyées.
14. **QCM — réponse b.** Avec `ndots:5`, un nom qui a moins de cinq points est d'abord complété par chaque domaine de recherche, dans l'ordre (`wb-pannes.svc.cluster.local` en premier), puis essayé tel quel. a ne vient qu'en dernier (ou en premier si le nom se termine par un point) ; c n'existe pas ; d est faux (le kubelet écrit `resolv.conf`, il ne résout rien).
15. Le kubelet garantit la mémoire par les demandes, les limites et l'éviction ; un swap non maîtrisé rend tout cela imprévisible (latences, OOM tardifs). *NodeSwap* (GA en 1.34) permet un swap encadré (`LimitedSwap` : seuls les pods `Burstable` peuvent swapper, dans une proportion calculée). Le défaut reste `failSwapOn: true` : il faut le décider explicitement (et kubeadm l'exige pour démarrer avec du swap), parce qu'un swap présent par accident (M14-E35) ne doit pas être utilisé par surprise.
16. cgroup v1 n'a plus de développement côté noyau et manque de fonctions dont le kubelet dépend (PSI, comptabilité mémoire unifiée) : depuis 1.35, `failCgroupV1: true` par défaut. Depuis 1.34, le kubelet **lit** le pilote de cgroups dans le CRI : avec `SystemdCgroup = true` dans containerd, le kubelet utilise `systemd` ; l'ancienne incohérence entre les deux n'est plus possible, mais containerd doit être configuré correctement, car il décide pour les deux.
17. Lire les notes de version et les changements de l'écosystème (Cilium, cert-manager…), instantané etcd, `kubeadm upgrade plan`. Puis : dépôt `pkgs.k8s.io` de la nouvelle mineure, kubeadm sur le premier nœud de contrôle, `kubeadm upgrade apply`, puis `kubeadm upgrade node` sur les deux autres, un par un ; kubelet et kubectl de chaque nœud de contrôle (drain, mise à jour, `uncordon`) ; puis les travailleurs un par un. Règles : les kube-apiserver à au plus une mineure d'écart entre eux ; contrôleurs et ordonnanceur jamais plus récents que l'API ; kubelet jamais plus récent que l'API, jusqu'à trois mineures plus ancien ; kubectl à une mineure près. Pas de retour à une mineure inférieure avec kubeadm : si le deuxième nœud échoue, `kubeadm upgrade` remet ses manifestes d'origine (sauvegardes dans `/etc/kubernetes/tmp/`) ; on corrige et on recommence ; l'instantané etcd ne sert qu'en désastre.
18. `aescbc` avec une clé dans un fichier protège les données d'etcd et ses sauvegardes (un instantané volé est illisible), pas un attaquant qui a la main sur un nœud de contrôle (la clé est à côté) ni ce qu'on lit par l'API. La documentation le déconseille désormais (CBC, et clé sur l'hôte). `kms` v2 : chiffrement par enveloppe, la clé maîtresse reste dans un service externe (OpenBao au module 25), rotation sans réécriture immédiate, meilleures performances que v1. Vérification : `etcdctl get /registry/secrets/<espace>/<nom>` doit commencer par `k8s:enc:aescbc:v1:<clé>:` et ne contenir aucune valeur lisible (M14-E28).
19. Un instantané est l'état d'**un** point du journal ; on ne peut pas réinjecter un membre ancien dans un cluster qui a continué. On arrête les kube-apiserver (et etcd), on restaure le même instantané sur les trois membres avec `etcdutl snapshot restore` (nouveaux identifiants de membres et de cluster, `--initial-cluster` des trois), on redémarre. Tout ce qui a été créé après l'instantané disparaît de l'API : objets, baux, Endpoints ; les kubelets suppriment les pods qui n'existent plus dans l'API et les contrôleurs recréent ce qui manque ; les jetons émis après restent valides en signature mais peuvent être liés à des objets disparus. D'où RB-141, et une restauration réservée à la perte de quorum ou de données.
20. Démarche de RB-140 et de M14-E35 : conditions et bail du nœud (`describe node`, `get lease`), taints, événements ; sur le nœud : kubelet (unité, journal), runtime, configuration, ressources, certificat ; cause prouvée avant tout geste ; réparation sur place si la cause est logicielle ou de configuration, remplacement (drain, retrait, reconstruction par le code) si le matériel ou le système sont en cause, ou si le temps imparti est dépassé sans diagnostic. Interdits tant qu'on ne sait pas : `kubectl delete node`, `kubeadm reset`, suppression forcée des pods du nœud (`--force --grace-period=0`, surtout pour un StatefulSet : deux pods pourraient écrire les mêmes données).

**Grille d'auto-évaluation** : une réponse est juste si elle explique le **mécanisme** (pas seulement la commande) ; pour les QCM, si elle justifie l'élimination de chaque mauvaise option. Points faibles typiques : ordre de l'admission (4), *watch* et `resourceVersion` (1, M14-E44), règles de décalage de versions (17), restauration d'etcd (19) : refais M14-E44 et relis RB-141 et RB-142.
