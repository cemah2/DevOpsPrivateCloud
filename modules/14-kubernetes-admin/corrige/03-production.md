# Module 14 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- format JSON de `etcdutl snapshot status -w json` (champs `revision`, `totalKey`) et sortie de `etcdutl version` (« etcdutl version: 3.6.x ») sur lesquels s'appuient le script d'instantané, le rôle et les checks ;
- `rclone` du paquet Debian 13 avec SeaweedFS (fournisseur `Other`, `--s3-no-check-bucket`, relecture par `lsjson`) ; prise en charge par SeaweedFS 4.4x de la politique de compartiment `etcd-k8s-par1` (refus de `DeleteObject` pour une identité) et des règles de **cycle de vie** par préfixe (`Expiration`, `NoncurrentVersionExpiration`) — à défaut, purge mensuelle à la main avec l'identité d'administration, écrite dans RB-141 ;
- restauration d'un etcd empilé de kubeadm avec `--bump-revision`/`--mark-compacted` : comportement de Cilium 1.20 après la restauration (identités et `CiliumEndpoint` recréés par le redémarrage des agents et de l'opérateur, d'après le principe des *informers* ; non mesuré) ;
- `kubeadm upgrade apply v1.36.5 --yes` et l'ordre exact des composants affiché par kubeadm 1.36 ; promotion des membres etcd apprenants lors d'une jonction (`EtcdLearnerMode`, à relire dans le CHANGELOG de ta version) ;
- `kubeadm init phase control-plane apiserver --config` avec un fichier fait d'une `ClusterConfiguration` et d'une `InitConfiguration` propre au nœud, et `kubeadm init phase upload-config kubeadm --config` sur un cluster existant (méthode de la page *Reconfiguring a kubeadm cluster*) ; alternative `kubeadm upgrade node phase control-plane` non testée ;
- sujet du certificat `apiserver-kubelet-client` en 1.36 (groupe `kubeadm:cluster-admins` d'après les notes de 1.29 ; vérifie avec `openssl x509 -noout -subject`) ;
- noms de fichiers et de variables posés par les paliers 1 et 2 et repris ici : nom de la VIP et des variables `k8s_version`/`k8s_image_pause` du rôle `k8s_noeud` (repris de la solution de M14-E02), `secrets/admin.conf.vault`, étiquette de sélection des liaisons d'admission de E18, mode d'installation de metrics-server (E20), nom du Service de MédiAgenda (`mediagenda-api`). Si les tiens diffèrent, la logique est la même.

**Rappel** : aucune nouvelle VM dans ce palier. Fichiers de solution : `corrige/fichiers/M14-E24/` à `M14-E31/`, `M14-E33/`, `M14-E34/`.

---

### M14-E24 — Sauvegarder et restaurer etcd

**Solution**

Fichiers : rôle [`etcd_instantane`](fichiers/M14-E24/ansible/roles/etcd_instantane/) (script [`etcd-instantane`](fichiers/M14-E24/ansible/roles/etcd_instantane/files/etcd-instantane.sh), script de restauration d'un membre [`etcd-restaurer-membre`](fichiers/M14-E24/ansible/roles/etcd_instantane/files/etcd-restaurer-membre.sh), unités), [variables du groupe](fichiers/M14-E24/ansible/inventories/lab/group_vars/k8s_plan_controle/etcd_instantane.yml), minutes par nœud (`host_vars/k8s-cp0N/etcd_instantane.yml`), [modèle de Vault](fichiers/M14-E24/ansible/inventories/lab/group_vars/all/vault-critique-s3.yml.exemple), [playbook](fichiers/M14-E24/ansible/playbooks/k8s-etcd-instantane.yml) ; stockage objet : [extrait du rôle `seaweedfs`](fichiers/M14-E24/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait), [politique](fichiers/M14-E24/infra/outils/s3/politique-etcd-k8s-par1.json), [cycle de vie](fichiers/M14-E24/infra/outils/s3/cycle-de-vie-etcd-k8s-par1.json) ; [pare-feu](fichiers/M14-E24/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; `plateforme/k8s` : [`outils/etcd-instantane.sh`](fichiers/M14-E24/k8s/outils/etcd-instantane.sh), [Taskfile](fichiers/M14-E24/k8s/Taskfile.yml.extrait) ; [`s3-etcd.env`](fichiers/M14-E24/adm01/s3-etcd.env.exemple) ; documentation : [RB-141](fichiers/M14-E24/medisphere/docs/kubernetes/runbooks/RB-141-restaurer-etcd.md), [compte rendu](fichiers/M14-E24/medisphere/docs/kubernetes/tests/restauration-etcd.md).

*1. Lecture* (réponses attendues) :
- `etcdctl snapshot save` demande l'état **cohérent** au membre (flux de l'instantané par l'API, avec une empreinte d'intégrité vérifiée à la restauration) ; copier `member/snap/db` d'un membre vivant peut perdre ce qui est encore dans le WAL et n'a pas d'empreinte (`--skip-hash-check` obligatoire à la restauration).
- En 3.6, la restauration et `snapshot status` ne sont plus dans `etcdctl` (déprécié en 3.5, retiré) : `etcdutl` travaille **hors ligne** sur des fichiers, `etcdctl` parle à un serveur.
- Tous les serveurs d'API doivent être arrêtés : un serveur d'API encore connecté à un membre non restauré continuerait d'écrire dans l'ancien état ; et les caches des composants (*informers*) contiennent un état **plus récent** que l'instantané.
- `--bump-revision N` ajoute N à la révision de l'instantané : la révision ne recule jamais pour les clients. `--mark-compacted` marque toutes les révisions jusque-là comme compactées : tout *watch* qui reprend depuis une révision ancienne reçoit « compacted » et doit **relister**, ce qui vide les caches périmés. Sans eux, des contrôleurs gardent des objets fantômes ou ratent des changements.
- La restauration réécrit l'identifiant de membre et de cluster (calculés à partir de la composition et du jeton) : un membre restauré ne peut pas rejoindre par erreur l'ancien cluster s'il en reste un morceau vivant.
- Une seule VM restaurée depuis PBS ramène un membre ancien qui se présente avec l'identité d'un membre existant : rejeté au mieux, perturbateur au pire (RB-141 §10). Il se traite comme un nœud neuf (RB-144).

*2. Premier instantané à la main* :

```
admin@adm01:~$ install -d -m 700 /tmp/etcd-cp01 && for f in ca.crt healthcheck-client.crt healthcheck-client.key; do
>   ssh k8s-cp01 sudo cat /etc/kubernetes/pki/etcd/$f > /tmp/etcd-cp01/$f; done; chmod 600 /tmp/etcd-cp01/*
admin@adm01:~$ export ETCDCTL_ENDPOINTS=https://10.10.40.51:2379 ETCDCTL_CACERT=/tmp/etcd-cp01/ca.crt \
>   ETCDCTL_CERT=/tmp/etcd-cp01/healthcheck-client.crt ETCDCTL_KEY=/tmp/etcd-cp01/healthcheck-client.key
admin@adm01:~$ etcdctl member list -w table
admin@adm01:~$ etcdctl endpoint status --cluster -w table
admin@adm01:~$ etcdctl get /registry/ --prefix --keys-only | head -20
admin@adm01:~$ etcdctl get /registry/ --prefix --keys-only | grep -c .
admin@adm01:~$ rm -rf /tmp/etcd-cp01; unset ETCDCTL_ENDPOINTS ETCDCTL_CACERT ETCDCTL_CERT ETCDCTL_KEY
```

L'arborescence est `/registry/<ressource>/<espace>/<nom>` (`/registry/deployments/wb-essais/mediagenda-api`, `/registry/secrets/…`) ; les valeurs sont des objets en **protobuf** (préfixe `k8s\0`), lisibles en partie avec `strings` : c'est l'argument de E28. Le port client 2379 des nœuds de contrôle est joignable depuis `adm01` (MGMT joint tout le lab) ; le certificat client voyage dans `/tmp` le temps de la commande, puis est effacé. L'instantané sur le nœud : `sudo etcdctl … snapshot save /var/backups/etcd/premier.db` puis `sudo etcdutl snapshot status /var/backups/etcd/premier.db -w table` (quelques Mo, quelques milliers de clés sur le lab).

*3. Stockage objet* : MR sur `plateforme/ansible` (identité `etcd-k8s`, compartiment versionné) et application du rôle `seaweedfs` sur `s3-01` (SIGHUP, sans redémarrage). Puis, avec l'identité d'administration, dans un sous-shell :

```
admin@adm01:~/src/infra$ ( set -a; . ~/.config/workbook/s3-admin.env; set +a
>   aws s3api put-bucket-policy --bucket etcd-k8s-par1 --policy file://outils/s3/politique-etcd-k8s-par1.json
>   aws s3api put-bucket-lifecycle-configuration --bucket etcd-k8s-par1 --lifecycle-configuration file://outils/s3/cycle-de-vie-etcd-k8s-par1.json )
admin@adm01:~$ ( set -a; . ~/.config/workbook/s3-etcd.env; set +a
>   echo essai | aws s3 cp - s3://etcd-k8s-par1/essai.txt && aws s3 rm s3://etcd-k8s-par1/essai.txt )
upload: - to s3://etcd-k8s-par1/essai.txt
delete failed: s3://etcd-k8s-par1/essai.txt An error occurred (AccessDenied) …
```

(`aws` avec le profil `s3-socle` de M05, qui porte le point d'accès.) Le refus de suppression est voulu : un nœud de contrôle compromis (ou un script de nettoyage fautif) ne peut pas effacer les sauvegardes ; c'est le **cycle de vie**, posé par l'administrateur, qui purge. Rétention retenue : `horaire/` 3 jours (≈ 216 objets de quelques Mo), `quotidien/` 35 jours (≈ 105 objets) : quelques Go au plus sur `s3-01`. L'objet `essai.txt` reste (supprime-le avec l'identité d'administration). Registre des secrets : identité `etcd-k8s` (Vault `critique`, nœuds, `s3-etcd.env`), et la politique dans `plateforme/infra/outils/s3/`.

*4. Chiffrement* :

```
admin@adm01:~$ age-keygen 2>/dev/null | (cd ~/src/k8s && uv run --project ~/src/ansible ansible-vault encrypt \
>   --vault-id critique@$HOME/src/ansible/outils/vault-pass-client.sh --output secrets/etcd-instantane-age.cle)
admin@adm01:~/src/k8s$ uv run --project ~/src/ansible ansible-vault view --vault-id critique@… secrets/etcd-instantane-age.cle | grep -m1 'public key'
# public key: age1…
```

La clé ne touche jamais le disque en clair ; la copie papier se fait depuis `ansible-vault view` (impression, coffre). La clé publique va dans `group_vars/k8s_plan_controle/etcd_instantane.yml`. Pourquoi `age` plutôt qu'un chiffrement symétrique : les nœuds n'ont **que** la clé publique ; un nœud compromis ne peut pas déchiffrer les instantanés des autres ni les anciens.

*5. Rôle et minuterie* : voir les fichiers. Points clés du script : instantané du membre **local** après un `endpoint health` (un membre en retard donnerait un instantané en retard) ; `snapshot status` avant tout envoi ; chiffrement puis envoi, avec relecture de la taille de l'objet ; trace `dernier-succes` (horodatage, objet, révision) **seulement** à la fin ; secrets passés à `rclone` par l'environnement, jamais en argument (visibles dans `ps`). Le rôle vérifie l'empreinte de l'archive d'etcd (valeur relevée dans `SHA256SUMS` de la version : `curl -sL https://github.com/etcd-io/etcd/releases/download/v3.6.6/SHA256SUMS | grep linux-amd64.tar.gz`) et n'installe que `etcdctl`/`etcdutl`. Règle de pare-feu `K8S_CP` → `S3_01:8333`. Test de l'alerte :

```
admin@k8s-cp01:~$ sudo sed -i 's/^ETCD_S3_CLE_SECRETE=.*/ETCD_S3_CLE_SECRETE=faux/' /etc/etcd-instantane/s3.env
admin@k8s-cp01:~$ sudo systemctl start etcd-instantane.service; journalctl -t ms-alerte -o cat --since -5min
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-etcd-instantane.yml --limit k8s-cp01    # rétablit
```

*6. Restauration* : RB-141 pas à pas (§3 à §6), avec le script `etcd-restaurer-membre` sur chaque nœud. Témoin et scénario :

```
admin@adm01:~$ kubectl -n wb-essais create configmap temoin-restauration --from-literal=etat=avant-instantane
admin@adm01:~/src/k8s$ task etcd:instantane            # note l'objet et l'heure
admin@adm01:~$ kubectl -n wb-essais patch configmap temoin-restauration -p '{"data":{"etat":"apres-instantane"}}'
admin@adm01:~$ kubectl delete namespace wb-essais
```

Puis RB-141 §3 (téléchargement de **cet** objet, déchiffrement, `snapshot status`, copie sur les trois nœuds, empreintes identiques), §4 (`etcd-restaurer-membre arreter` sur les trois), §5 (`restaurer` sur les trois, même composition et même jeton), §6 (`etcd` sur les trois à la suite, `endpoint health --cluster`, `plan` sur les trois, kubelets, Cilium, CoreDNS).

*7. Après* :

```
admin@adm01:~$ kubectl get nodes
admin@adm01:~$ kubectl -n wb-essais get configmap temoin-restauration -o jsonpath='{.data.etat}{"\n"}'
avant-instantane
admin@k8s-cp01:~$ sudo etcdctl … endpoint status --cluster -w table      # RAFT INDEX, REVISION > 1000000000
admin@adm01:~$ kubectl -n wb-essais get pods
```

L'espace est revenu, avec ses objets ; les pods sont **recréés** par le kubelet (leurs conteneurs avaient été tués à la suppression) ; PostgreSQL et Valkey repartent vides (volumes jetables) : etcd n'a jamais contenu de données applicatives. Cilium : `cilium status` peut montrer des endpoints à régénérer ; le redémarrage de l'agent et de l'opérateur (RB-141 §6.4) remet les identités en ordre.

*8. Documentation* : RB-141 et le compte rendu (modèles fournis). Sauvegarde PBS : vérifie dans Proxmox que les VMs 2141-2146 sont dans une tâche de sauvegarde vers `pbs01` (la tâche `lab-nuit` couvre le pool `lab` ; l'espace de noms `par1/k8s` se règle dans le stockage PBS de la tâche ou par une tâche dédiée, comme les autres environnements). RB-141 §10 dit à quoi elles servent.

**Explications**

etcd est un magasin clé-valeur répliqué par Raft : chaque écriture est validée par une majorité de membres, chaque membre garde tout. Un instantané est une copie cohérente de la base à une révision donnée ; la restaurer crée une **nouvelle** base, et donc un nouveau cluster etcd, que l'on démarre à trois d'un coup. Ce qui n'est pas dans etcd n'est pas sauvegardé par cet exercice : les données des volumes (M16, Velero), les images (Harbor), les fichiers des nœuds (`/etc/kubernetes/pki` — **les certificats et la clé `sa.key` ne sont pas dans etcd** : sur une reconstruction complète, ils viennent des VMs ou d'une sauvegarde de `/etc/kubernetes/pki`, à ajouter si l'on veut pouvoir restaurer sur des VMs neuves), les fichiers d'audit et de chiffrement (rôles Ansible, Vault).

**Alternatives**
- Instantané de volume (disque de la VM) : simple, mais pas cohérent entre trois membres et lié à la VM.
- etcd externe sauvegardé à part : même principe, un cluster de plus.
- Velero (M16) : sauvegarde **objet par objet** par l'API (et les volumes) ; restaure un espace sans toucher au reste du cluster. Complémentaire, pas un remplaçant : il ne sait pas recréer un plan de contrôle.
- Envoi vers PBS (`proxmox-backup-client`, comme M08-E25) : déduplication et rétention gérées par PBS, hors site ; plus lourd à installer sur les nœuds.

**Pièges classiques**
- Restaurer un seul membre, ou les trois depuis des instantanés différents.
- Laisser un serveur d'API tourner pendant la restauration.
- Garder la copie des manifestes **dans** `/etc/kubernetes/manifests/` (le kubelet la lance).
- Supprimer `/var/lib/etcd` au lieu de le déplacer : plus de retour arrière.
- Oublier `--bump-revision`/`--mark-compacted` : contrôleurs et Cilium incohérents pendant des heures.
- Un instantané jamais restauré « parce que la sonde est verte » ; une clé privée `age` perdue ; une clé de chiffrement des Secrets absente (E28).
- Un `etcdutl` d'une autre version que le membre (E25 : les outils suivent la montée).

**En production chez MédiSphère**
Test de restauration trimestriel chronométré sur un cluster jetable (preuve HDS), restauration automatisée par playbook, alerte « dernier instantané de plus de 2 h » dans la supervision (M21), copie hors site des quotidiens vers PAR2, sauvegarde chiffrée de `/etc/kubernetes/pki` pour pouvoir reconstruire sur des VMs neuves.

---

### M14-E25 — Monter le cluster de version : 1.35 → 1.36

**Solution**

Fichiers : [playbook](fichiers/M14-E25/ansible/playbooks/k8s-montee-version.yml) et ses [tâches par nœud](fichiers/M14-E25/ansible/playbooks/taches/montee-noeud.yml), [variables de version](fichiers/M14-E25/ansible/inventories/lab/group_vars/k8s_par1/versions.yml.extrait), [outils etcd](fichiers/M14-E25/ansible/inventories/lab/group_vars/k8s_plan_controle/etcd_instantane.yml.extrait), [`kubeadm-config.yaml`](fichiers/M14-E25/k8s/cluster/kubeadm-config.yaml.extrait), [boucle témoin](fichiers/M14-E25/adm01/boucle-temoin.sh), [RB-142](fichiers/M14-E25/medisphere/docs/kubernetes/runbooks/RB-142-monter-de-version.md), [compte rendu](fichiers/M14-E25/medisphere/docs/kubernetes/tests/montee-1.36.md).

*1. Lecture* (à la date de rédaction ; relis le CHANGELOG de **ta** cible) :

| Changement 1.36 | Touche `k8s-par1` ? |
|---|---|
| kubeadm 1.36 : etcd 3.6.8-0, CoreDNS v1.14.2, pause 3.10.2 | **oui** : etcd et CoreDNS remplacés par `upgrade apply` ; l'image *pause* de containerd est à aligner (rôle `containerd`) ; les outils etcd des nœuds aussi |
| *Feature gate* kubeadm `ControlPlaneKubeletLocalMode` supprimé | seulement s'il est posé dans `featureGates` : vérifier `cluster/kubeadm-config.yaml` (non posé dans la solution de référence) |
| `NodeLocalCRISocket` GA : le socket CRI est stocké localement par nœud | transparent ; kubeadm migre pendant `upgrade node` (à observer : `/var/lib/kubelet/instance-config.yaml`, à vérifier sur ta version) |
| Volume `gitRepo` désactivé ; `Service.spec.externalIPs` déprécié (avertissements) | non (aucun manifeste ne les utilise ; `kubectl get svc -A -o json \| jq '.items[] \| select(.spec.externalIPs)'` le prouve) |
| Prise en charge des *flex-volumes* retirée de kubeadm | non |
| Métriques renommées (`etcd_bookmark_total`, `volume_operation_errors_total`) | pas encore (supervision au M21) |
| cgroup v1 refusé (depuis 1.35) | non (Debian 13 en cgroup v2) |

Ordre officiel : nœud de contrôle = dépôt, kubeadm, `upgrade plan`/`apply` (premier) ou `upgrade node` (autres), **drain**, kubelet et kubectl, `daemon-reload` + redémarrage du kubelet, `uncordon` ; travailleur = dépôt, kubeadm (et kubectl), `upgrade node` (qui ne fait que la configuration du kubelet), drain, kubelet, redémarrage, `uncordon`. Modules complémentaires : depuis 1.28, CoreDNS et kube-proxy ne sont mis à jour qu'**après le dernier** nœud de contrôle (un CoreDNS récent sur un plan de contrôle encore ancien pouvait casser). Décalages : kubelet jusqu'à trois mineures de retard sur l'API (jamais d'avance), kubectl ±1. `/etc/kubernetes/tmp/` : copies des manifestes (`kubeadm-backup-manifests-*`) et des données du membre etcd local (`kubeadm-backup-etcd-*`). Certificats : renouvelés par `upgrade apply`/`node` (sauf `--certificate-renewal=false`). `cluster/kubeadm-config.yaml` est déjà en v1beta4 : `kubeadm config validate` passe, pas de `migrate`.

*2. Plan* : RB-142 §2-§3 (le plan de changement est la copie du runbook remplie pour la date). MR ouverte avec les variables de l'extrait ; pipeline vert ; non fusionnée.

*3. Charge témoin* : `adm01/boucle-temoin.sh mediagenda-recette mediagenda-api` dans un `tmux`. La boucle passe par `kubectl port-forward`, donc par l'API : un échec simultané d'un `/readyz` est imputable à l'API, pas à MédiAgenda (ce que dit le bilan). Pour une mesure plus fidèle, un pod client dans l'espace (image MédiAgenda, boucle `python -c` avec `urllib` vers le Service) fait l'affaire.

*4. Premier nœud* : RB-142 §4 (commandes complètes). Sortie de `upgrade plan` : tableau « Components that must be upgraded manually after you have upgraded the control plane » (kubelet), puis le tableau des versions (kube-apiserver, kube-controller-manager, kube-scheduler, kube-proxy, CoreDNS, etcd) et celui des configurations de composants. `upgrade apply` montre `[upgrade/staticpods]` pour chaque composant, avec la copie dans `/etc/kubernetes/tmp/`. Durée typique : 5 à 10 minutes, l'essentiel en tirage d'images (par le cache Harbor).

*5. Playbook* : voir les fichiers. Le dépôt passe par les tâches `depot.yml` du rôle `k8s_noeud` (même fichier, même clé, même contrôle d'empreinte) ; les paquets non, parce que le rôle installe les trois d'un coup alors que l'ordre documenté les sépare (et le rôle refuse un changement de version sur un nœud membre sans `k8s_noeud_changement_version`). Rejouable : un nœud dont le kubelet (vu par l'API) **et** `kubeadm` sont à la cible est sauté ; le premier nœud de contrôle qui voit `kubeadm-config` en ancienne version fait `apply`, les autres `node`. `serial: 1` + `any_errors_fatal` : arrêt au premier échec, le nœud fautif reste cordonné (le `rescue` le dit). Le drain et l'`uncordon` se font depuis `adm01` avec **ton** identité (traçable dans l'audit à partir de E27).

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-montee-version.yml -e k8s_cible=1.36.5
```

*6. Après* : RB-142 §7. Avertissement typique dans le journal de kubeadm ou de containerd : l'image *pause* configurée dans containerd (3.10.1) diffère de celle attendue par kubeadm (3.10.2). Corriger `k8s_image_pause` (dont dérive `containerd_image_sandbox`), rejouer le rôle `containerd` **nœud par nœud** (le redémarrage de containerd ne tue pas les conteneurs : les *shims* restent). Puis `etcd_instantane_outils_version: 3.6.8` (et son empreinte), rôle `etcd_instantane`. Fusion de la MR, rôles rejoués : `changed=0`.

*7. Runbook* : modèle fourni.

**Explications**

kubeadm ne gère pas les paquets : il remplace les **manifestes statiques** du plan de contrôle (le kubelet redémarre les pods), met à jour etcd (son pod statique aussi), les ConfigMaps de configuration et les modules complémentaires. Le kubelet, lui, est un paquet système : c'est le changement de paquet qui fait la montée du nœud. D'où les deux mouvements, et la politique de décalage qui permet de les faire à des moments différents. Le drain avant le changement de mineure du kubelet est exigé parce que le kubelet relance tous les conteneurs (le hachage de leur spécification change) et que la compatibilité de l'état local du kubelet entre mineures n'est pas garantie.

**Alternatives**
- `UpgradeConfiguration` v1beta4 (`apply.kubernetesVersion`, `certificateRenewal`, `etcdUpgrade`…) avec `kubeadm upgrade apply --config` : la même chose déclarée dans un fichier versionné.
- Remplacer les nœuds au lieu de les monter (nouvelle VM en 1.36 qui rejoint, ancienne retirée) : l'approche de Cluster API (M18) ; plus propre, mais demande la capacité d'un nœud de plus.
- Une distribution qui orchestre la montée (RKE2 *system-upgrade-controller*, Talos `talosctl upgrade-k8s`) : ADR-0140.

**Pièges classiques**
- Sauter une mineure, ou monter les travailleurs avant le plan de contrôle.
- `apt-get upgrade` sans version : paquets épinglés ignorés, ou non épinglés montés trop loin.
- Lancer `upgrade apply` sur deux nœuds de contrôle.
- Drainer un travailleur sans capacité ailleurs ou avec une PDB à 0 perturbation autorisée : le drain ne finit jamais.
- Oublier le dépôt de la nouvelle mineure : `apt-cache madison kubeadm` ne montre pas la 1.36.
- Oublier l'image *pause*, les outils etcd, le code (la MR) : le prochain passage d'Ansible redescend un réglage ou réinstalle l'ancien dépôt.

**En production chez MédiSphère**
Répétition sur un cluster jetable de même version la veille ; fenêtre annoncée ; Renovate qui ouvre la MR de version ; supervision des nœuds et des API dépréciées (M21) ; correctifs mensuels avec le même playbook.

---

### M14-E26 — Les certificats du cluster

**Solution**

Fichiers : [RB-143](fichiers/M14-E26/medisphere/docs/kubernetes/runbooks/RB-143-renouveler-les-certificats.md) (inventaire complet au §1), [`outils/certificats-echeances.sh`](fichiers/M14-E26/k8s/outils/certificats-echeances.sh), [unités de `adm01`](fichiers/M14-E26/adm01/systemd/), [`KubeletConfiguration`](fichiers/M14-E26/k8s/cluster/kubeadm-config.yaml.extrait), [playbook de configuration du kubelet](fichiers/M14-E26/ansible/playbooks/k8s-kubelet-config.yml), [metrics-server](fichiers/M14-E26/k8s/composants/metrics-server/values.yaml.extrait).

*1. Inventaire* : RB-143 §1. Réponses : les certificats ont été renouvelés en E25 parce que `kubeadm upgrade apply`/`node` renouvelle les certificats du nœud par défaut (d'où « une montée par an au moins suffit »). Le jour où une **CA** expire, plus aucun certificat qu'elle a signé n'est accepté : tout le cluster s'arrête, et `kubeadm certs renew` ne renouvelle pas les CA (rotation manuelle, RB-143 §7). Les durées : `certificateValidityPeriod` (défaut 8760 h) et `caCertificateValidityPeriod` (défaut 87600 h) dans la `ClusterConfiguration` v1beta4 ; elles ne s'appliquent qu'aux certificats **émis** ensuite (amorçage, `renew`).

```
admin@k8s-cp01:~$ sudo kubeadm certs check-expiration
admin@k8s-cp01:~$ for f in $(sudo find /etc/kubernetes/pki -name '*.crt'); do echo "== $f"; sudo openssl x509 -in $f -noout -subject -issuer -enddate -ext subjectAltName 2>/dev/null; done
admin@k8s-w01:~$ sudo ls -l /var/lib/kubelet/pki/ ; sudo grep client-certificate /etc/kubernetes/kubelet.conf
```

*2. Renouvellement* : RB-143 §3 (un nœud à la fois, vérification par `openssl s_client` sur 6443 et 2379 : `notBefore` à l'heure du renouvellement), §4 (kubeconfigs du coffre).

*3. Kubelet client* : `kubelet.conf` pointe vers `/var/lib/kubelet/pki/kubelet-client-current.pem`, lien vers `kubelet-client-<date>.pem`. À 70-90 % de la durée de vie, le kubelet crée une CSR `kubernetes.io/kube-apiserver-client-kubelet` ; le **gestionnaire de contrôleurs** l'approuve (contrôleur `csrapproving`, grâce au ClusterRoleBinding `kubeadm:node-autoapprove-certificate-rotation` posé par kubeadm) et la signe avec la CA. `kubectl get csr` montre ces demandes `Approved,Issued`. Un nœud éteint au-delà de l'échéance ne peut plus s'authentifier pour demander le renouvellement : RB-143 §6.

*4. Kubelet service* :

```
admin@adm01:~$ openssl s_client -connect k8s-w01.par1.medisphere.internal:10250 </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject
issuer=CN=k8s-w01-ca@1760000000          # auto-signé par le kubelet
admin@adm01:~$ kubectl -n kube-system edit configmap kubelet-config       # serverTLSBootstrap: true dans data.kubelet
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-kubelet-config.yml
admin@adm01:~$ kubectl get csr --field-selector spec.signerName=kubernetes.io/kubelet-serving
admin@adm01:~$ kubectl get csr <CSR> -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -text | grep -A1 -E 'Subject:|Alternative'
        Subject: O = system:nodes, CN = system:node:k8s-w01
            X509v3 Subject Alternative Name:
                DNS:k8s-w01, IP Address:10.10.40.61
admin@adm01:~$ kubectl certificate approve <CSR>
```

(Le `edit` est possible pour un premier essai ; la référence est le contenu versionné de `cluster/kubeadm-config.yaml`, appliqué au ConfigMap par la même MR.) Six demandes, six lectures, six approbations. Vérification : `outils/certificats-echeances.sh` (ligne `kubelet-serving` de chaque nœud).

*5. metrics-server* : retirer `--kubelet-insecure-tls` des values de E20 (`args: []`, extrait ; les `args` du chart s'ajoutent aux arguments par défaut), `helm upgrade` avec la même version du chart, puis `kubectl -n kube-system rollout status deployment/metrics-server` et `kubectl top nodes`. Dans un an, six nouvelles demandes `kubelet-serving` attendront : l'alerte du lundi (« certificat de service absent ») ou `kubectl get csr` le diront, et RB-143 §5 dit quoi faire.

*6. Surveillance et runbook* : script et unités fournis (installés sur `adm01` par `task install:systeme` de `plateforme/k8s`, sur le modèle des `ms-verif-*`), RB-143.

**Explications**

Trois CA, parce que trois confiances différentes : `ca` (tout ce qui parle à l'API, et l'API aux kubelets), `etcd-ca` (seuls les membres et le serveur d'API parlent à etcd : un certificat de l'API ne doit pas ouvrir etcd), `front-proxy-ca` (le serveur d'API qui relaie vers une API agrégée comme metrics-server s'identifie avec un certificat que l'API agrégée sait distinguer d'un client ordinaire). Les certificats de service des kubelets ne sont pas approuvés automatiquement parce que l'approbation affirme « ce kubelet a droit à ce nom et à cette adresse », ce que l'API ne peut pas vérifier seule : sans contrôle, un kubelet compromis pourrait obtenir un certificat au nom d'un autre nœud.

**Alternatives**
- Approbateur automatique (`kubelet-csr-approver`) qui vérifie nom et adresses contre une liste de réseaux : supprime le geste humain annuel ; à n'utiliser qu'avec ses contrôles d'adresses.
- Durées plus courtes (`certificateValidityPeriod`) : moins de risque en cas de vol, plus de renouvellements ; cohérent avec une montée de version tous les quatre mois.
- CA externe (mode *external CA* de kubeadm) avec step-ca : centralisation, mais kubeadm ne renouvelle plus rien.

**Pièges classiques**
- `kubeadm certs renew` sans redémarrage : le disque dit « 365 jours », le processus sert l'ancien certificat jusqu'à son expiration.
- Oublier `super-admin.conf` (un seul nœud) ou les copies du coffre.
- Approuver toutes les CSR en bloc (`kubectl get csr -o name | xargs kubectl certificate approve`).
- Poser `serverTLSBootstrap` seulement dans `/var/lib/kubelet/config.yaml` : effacé à la montée suivante.
- Retirer `--kubelet-insecure-tls` **avant** d'avoir des certificats de service signés : metrics-server tombe.

**En production chez MédiSphère**
Supervision des échéances par métriques (M21) en plus de la minuterie ; rotation des CA répétée sur un cluster jetable avant l'échéance ; identités humaines par OIDC (M24) pour ne plus distribuer de certificats clients.

---

### M14-E27 — Auditer l'API

**Solution**

Fichiers : rôle [`k8s_audit`](fichiers/M14-E27/ansible/roles/k8s_audit/) et sa [politique](fichiers/M14-E27/ansible/roles/k8s_audit/files/politique.yaml), [playbook](fichiers/M14-E27/ansible/playbooks/k8s-api-fichiers.yml), [`kubeadm-config.yaml`](fichiers/M14-E27/k8s/cluster/kubeadm-config.yaml.extrait), [`outils/reconfigurer-apiserver.sh`](fichiers/M14-E27/k8s/outils/reconfigurer-apiserver.sh), [compte rendu d'enquête](fichiers/M14-E27/medisphere/docs/kubernetes/tests/enquete-audit.md).

*1. Lecture* : la **première** règle qui correspond s'applique. `Metadata` : utilisateur, groupes, verbe, ressource, espace, nom, adresses, agent, code de réponse, horodatages — sans corps. `RequestResponse` sur les Secrets écrirait leur contenu en clair dans un fichier lisible par root et copié partout (rotation, centralisation) : on recrée la fuite que E28 veut fermer. Les `watch` et `list` sont nombreux et volumineux : au niveau `RequestResponse`, chaque `list` de pods écrirait toute la liste ; c'est le premier facteur de volume et de charge (l'audit est **synchrone** pour le backend de fichier, en mode `blocking` par défaut). Rotation : `--audit-log-maxage`, `--audit-log-maxbackup`, `--audit-log-maxsize` (et `--audit-log-compress`).

*2. Politique* : fichier fourni, commenté règle par règle.

*3. Activation* :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-api-fichiers.yml          # politique sur les 3 nœuds
admin@adm01:~/src/k8s$ git pull                                                              # MR fusionnée (extraArgs, extraVolumes)
admin@adm01:~/src/k8s$ task etcd:instantane
admin@adm01:~/src/k8s$ outils/reconfigurer-apiserver.sh k8s-cp01
admin@adm01:~$ kubectl -n kube-system get pod kube-apiserver-k8s-cp01 -o jsonpath='{.spec.containers[0].command}' | tr ',' '\n' | grep audit
admin@adm01:~/src/k8s$ outils/reconfigurer-apiserver.sh k8s-cp02 && outils/reconfigurer-apiserver.sh k8s-cp03
admin@adm01:~/src/k8s$ outils/reconfigurer-apiserver.sh --televerser k8s-cp01
admin@adm01:~$ kubectl -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | grep audit
```

Le script construit pour **chaque** nœud un fichier fait de la `ClusterConfiguration` du dépôt et d'une `InitConfiguration` avec **son** adresse annoncée, garde une copie du manifeste hors de `/etc/kubernetes/manifests/`, régénère le manifeste du serveur d'API (`kubeadm init phase control-plane apiserver`), affiche le `diff` (lis-le : seules les options d'audit et les volumes doivent changer), attend `/readyz` et revient en arrière sinon. Sans `--televerser` (`kubeadm init phase upload-config kubeadm`), le ConfigMap `kubeadm-config` garderait l'ancienne configuration : la **prochaine** `kubeadm upgrade` régénérerait les manifestes **sans** l'audit, sans rien dire.

*4. Mesure* :

```
admin@k8s-cp01:~$ sudo ls -l /var/log/kubernetes/audit/ ; sudo wc -l /var/log/kubernetes/audit/audit.log
admin@adm01:~$ ssh k8s-cp01 "sudo cat /var/log/kubernetes/audit/audit.log" | jq -r '.user.username' | sort | uniq -c | sort -rn | head
admin@adm01:~$ ssh k8s-cp01 "sudo cat /var/log/kubernetes/audit/audit.log" | jq -r '"\(.verb) \(.objectRef.resource // .requestURI)"' | sort | uniq -c | sort -rn | head
```

Ordre de grandeur sur le lab avec cette politique : quelques dizaines de Mo par heure et par nœud, dominés par les comptes de service des contrôleurs (Cilium, metrics-server, gestionnaire de contrôleurs) en `Metadata`. S'il en faut moins : une règle `None` pour les lectures (`get`, `list`, `watch`) des comptes de service de `kube-system` sur les ressources qu'ils surveillent, **jamais** pour leurs écritures. 1 Go par nœud (10 × 100 Mo, compressés) couvre alors plusieurs jours, pas 30 : c'est la raison de la centralisation au M22.

*5. Enquête* : commandes et réponse dans le [compte rendu](fichiers/M14-E27/medisphere/docs/kubernetes/tests/enquete-audit.md). Pour rejouer la scène avec l'identité de Julien : `kubectl --kubeconfig ~/e12/julien.petit.kubeconfig -n mediagenda-dev create deployment rdv-essai-audit --image=<IMAGE-MEDIAGENDA>` (le kubeconfig de E12) ; le hasard : `(( RANDOM % 2 ))`. Le Secret témoin : `kubectl -n mediagenda-dev create secret generic temoin-audit --from-literal=x=y`. Point important de la réponse : `sourceIPs` montre l'adresse du nœud qui porte HAProxy, pas celle du poste.

**Explications**

L'audit est une étape du traitement de chaque requête par le serveur d'API, après l'authentification : il sait **qui** (identité authentifiée, et l'identité usurpée si `--as`), **quoi** (verbe, objet), **comment ça s'est terminé** (code). Il ne voit que ce qui passe par **ce** serveur d'API : trois serveurs, trois journaux. Le niveau se choisit par règle, et la politique est un compromis entre preuve et volume — et entre preuve et confidentialité.

**Alternatives**
- Backend *webhook* vers un collecteur : pas de fichiers locaux, mais une dépendance réseau dans le chemin des requêtes (mode `batch` recommandé).
- Politique par défaut « tout en `Metadata` » : simple et sûre, mais ne dit pas **ce qui** a été changé dans un objet.
- Outils d'analyse de l'audit en temps réel (Falco avec la source `k8saudit`) : détection, au M26.

**Pièges classiques**
- Mettre les règles générales avant les exceptions (les Secrets passent en `RequestResponse`).
- Oublier le volume des journaux (`DirectoryOrCreate`) ou le monter en lecture seule : le serveur d'API ne démarre pas.
- Modifier seulement les manifestes : la montée de version suivante efface tout.
- Appliquer les trois nœuds d'un coup avec une politique invalide : plus d'API.
- Chercher dans un seul des trois journaux.

**En production chez MédiSphère**
Centralisation (M22) avec conservation conforme à la politique HDS (un an au moins pour les actions d'administration), alertes sur les actions sensibles (`system:masters`, lecture de Secrets hors des comptes de service attendus, `exec` en production), revue mensuelle des accès.

---

### M14-E28 — Chiffrer les Secrets dans etcd

**Solution**

Fichiers : rôle [`k8s_chiffrement`](fichiers/M14-E28/ansible/roles/k8s_chiffrement/), [étapes et état final](fichiers/M14-E28/ansible/inventories/lab/group_vars/k8s_plan_controle/chiffrement.yml), [modèle de Vault](fichiers/M14-E28/ansible/inventories/lab/group_vars/k8s_plan_controle/vault-critique-chiffrement.yml.exemple), [playbook](fichiers/M14-E28/ansible/playbooks/k8s-api-fichiers.yml), [`kubeadm-config.yaml`](fichiers/M14-E28/k8s/cluster/kubeadm-config.yaml.extrait), [`outils/secrets-en-clair.sh`](fichiers/M14-E28/k8s/outils/secrets-en-clair.sh), [analyse](fichiers/M14-E28/medisphere/docs/kubernetes/securite/chiffrement-secrets.md).

*1. Lecture* : avec `identity` en premier, etcd stocke l'objet en protobuf (préfixe `k8s\0`), lisible. Un Secret écrit en clair **reste** en clair après l'activation tant qu'il n'est pas réécrit. `aescbc` : « non recommandé » (oracle de remplissage du mode CBC) ; `aesgcm` : « non recommandé sauf rotation automatisée » (nonce aléatoire, rotation toutes les 200 000 écritures) ; `secretbox` (XSalsa20 + Poly1305) est le seul fournisseur local qui n'est pas déconseillé, avec une réserve : des primitives « relativement récentes », qui peuvent ne pas être acceptées dans les environnements soumis à une revue poussée — exactement le cas d'un hébergeur HDS. D'où la cible KMS v2 (M25), et `secretbox` d'ici là, réserve écrite dans l'analyse. Clé : dans le fichier de configuration, sur le disque des nœuds de contrôle, pour tous les fournisseurs locaux. KMS v2 : la clé maîtresse reste dans un service externe, le serveur d'API n'a que des clés de données chiffrées.

*2. Constat* :

```
admin@adm01:~$ kubectl -n wb-essais create secret generic temoin-chiffrement --from-literal=motdepasse=TEMOIN-E28-visible
admin@k8s-cp01:~$ sudo etcdctl … get /registry/secrets/wb-essais/temoin-chiffrement --print-value-only | hexdump -C | head -12
00000000  6b 38 73 00 0a 0c 0a 02  76 31 12 06 53 65 63 72  |k8s.....v1..Secr|
…                                                            |…TEMOIN-E28-visible…|
admin@k8s-cp01:~$ sudo strings /var/backups/etcd/etcd-k8s-cp01-*.db | grep -m1 TEMOIN-E28
```

*3. Activation sans coupure* : étape 1 (`[identity, aescbc(cle-2026-10)]`) par le rôle sur les trois nœuds (`playbooks/k8s-api-fichiers.yml`), **puis** MR `kubeadm-config` et `outils/reconfigurer-apiserver.sh` nœud par nœud et `--televerser` ; à ce stade, tous savent lire `aescbc` mais personne n'écrit chiffré. Étape 2 (`[aescbc, identity]`) par le rôle ; le rechargement automatique fait le reste (≈ 1 minute par nœud ; le rôle attend 90 s). Vérification **par serveur d'API** : écrire un Secret à travers chaque nœud et lire son préfixe.

```
admin@adm01:~$ for n in 1 2 3; do kubectl --server https://10.10.40.5$n:6443 -n wb-essais create secret generic essai-cp0$n --from-literal=a=b; done
admin@k8s-cp01:~$ for n in 1 2 3; do sudo etcdctl … get /registry/secrets/wb-essais/essai-cp0$n --print-value-only | head -c 30; echo; done
k8s:enc:aescbc:v1:cle-2026-10:…
```

*4. Réécriture* :

```
admin@adm01:~$ kubectl get secrets --all-namespaces -o json | kubectl replace -f -
admin@adm01:~/src/k8s$ outils/secrets-en-clair.sh
     41 aescbc:cle-2026-10
```

*5. Rotation* (étapes 3 à 5 de `chiffrement.yml`, chacune sur les trois nœuds avant la suivante) : nouvelle clé `secretbox` en deuxième position, puis en première, `kubectl get secrets -A -o json | kubectl replace -f -`, `outils/secrets-en-clair.sh` → `41 secretbox:cle-2026-11`, puis retrait de `aescbc` et d'`identity`. L'ancienne clé reste dans le Vault 35 jours : les instantanés etcd pris avant la réécriture contiennent des Secrets chiffrés par elle.

*6. Analyse* : modèle fourni (tableau des menaces, conséquences pour RB-141, KMS v2).

**Explications**

Le chiffrement au repos est fait par le serveur d'API, juste avant l'écriture dans etcd et juste après la lecture : etcd ne voit que des octets chiffrés, préfixés par le fournisseur et le **nom** de la clé (c'est ce qui permet d'en avoir plusieurs pendant une rotation). Tout ce qui passe par l'API reçoit le Secret déchiffré : la confidentialité vis-à-vis des utilisateurs reste l'affaire du RBAC.

**Alternatives**
- KMS v2 vers Vault (M25) : la vraie réponse au vol d'un disque de nœud de contrôle.
- Chiffrer aussi les ConfigMaps ou des ressources personnalisées : coût en CPU et en complexité pour des objets qui ne devraient pas contenir de secrets ; préférer corriger les applications.
- Secrets hors de Kubernetes (External Secrets, Vault Agent, M25) : le Secret Kubernetes n'est plus la source.

**Pièges classiques**
- Activer `[aescbc, identity]` directement sur un des trois serveurs d'API : les deux autres ne lisent plus les Secrets qu'il écrit.
- Oublier la réécriture : les anciens Secrets restent en clair, `etcdctl get` le montre.
- Retirer l'ancienne clé avant la réécriture : Secrets illisibles (E32, question 12).
- Monter le **fichier** au lieu du dossier : le rechargement automatique ne voit pas le remplacement.
- Clé générée avec une fausse longueur (texte, pas 32 octets aléatoires) : le serveur d'API refuse de démarrer.
- Afficher `etcdctl get` sans `hexdump` dans un terminal partagé ou un ticket.

**En production chez MédiSphère**
KMS v2 avec Vault dès le M25, rotation annuelle tracée au registre, contrôle périodique automatique (`outils/secrets-en-clair.sh` en minuterie, alerte s'il reste du clair).

---

### M14-E29 — Perdre un nœud de contrôle

**Solution**

Fichiers : [RB-144](fichiers/M14-E29/medisphere/docs/kubernetes/runbooks/RB-144-remplacer-un-noeud-de-controle.md), [compte rendu](fichiers/M14-E29/medisphere/docs/kubernetes/tests/perte-plan-controle.md).

*1. Avant* :

```
admin@k8s-cp01:~$ sudo etcdctl … endpoint status --cluster -w table            # colonne IS LEADER
admin@adm01:~$ for n in k8s-cp01 k8s-cp02 k8s-cp03; do ssh $n "ip -br addr | grep -q 10.10.40.200 && hostname"; done
admin@adm01:~$ kubectl -n kube-system get lease kube-controller-manager kube-scheduler -o custom-columns=NOM:.metadata.name,TITULAIRE:.spec.holderIdentity
admin@adm01:~$ kubectl get pods -A -o wide --field-selector spec.nodeName=k8s-cp02
```

Pour rendre l'essai plus instructif : faire de `k8s-cp02` le leader etcd (`etcdctl move-leader <ID-cp02>`) et le maître VRRP (arrêter puis relancer keepalived sur le maître actuel ; attention au `nopreempt` du M07, qui fige le maître). Ce n'est pas obligatoire.

*2. Panne* : `root@pve01:~# qm stop 2142` ; observations attendues dans le compte rendu (ordres de grandeur) : la VIP bascule en 1 à 3 s (annonces VRRP manquées) ; HAProxy retire `k8s-cp02` après ses sondes ; etcd élit un nouveau leader en moins de 2 s (délai d'élection de l'ordre de 1 s) ; les baux sont repris en 15 s environ (durée du bail) ; le nœud passe `NotReady` au bout d'environ 40 à 50 s (`--node-monitor-grace-period` du gestionnaire de contrôleurs : lis la valeur par défaut de ta version), avec les taints `node.kubernetes.io/unreachable` ; les pods qui y tournaient (CoreDNS par exemple) sont évincés au bout de 300 s (tolérances `tolerationSeconds: 300` ajoutées par l'admission `DefaultTolerationSeconds`) et recréés ailleurs ; pods statiques et DaemonSets ne bougent pas. Créer un Deployment fonctionne : 2 membres sur 3 forment un quorum. Un second nœud perdu : plus de quorum, plus d'écriture (`etcdserver: request timed out`, puis serveurs d'API en erreur) ; les pods existants continuent de tourner.

*3. Retour* : `qm start 2142` ; le membre etcd rattrape le leader (journal, `endpoint status` : `RAFT INDEX` qui rejoint les autres), le kubelet relance les pods statiques, le nœud redevient `Ready` en une à deux minutes.

*4. Remplacement* : RB-144 §2 dans l'ordre. Ce qu'on observe :

```
admin@k8s-cp02:~$ sudo kubeadm reset -f
[reset] Reading configuration from the cluster...
[preflight] Running pre-flight checks
W… [reset] No kubeadm config, using etcd pod spec to get data directory     (selon la version)
[reset] Deleted contents of the etcd data directory: /var/lib/etcd
… The reset process does not clean CNI configuration … iptables … kubeconfig files …
admin@k8s-cp01:~$ sudo etcdctl … member list -w table          # pendant la jonction : k8s-cp02 IS LEARNER = true, puis false
```

Le point qui piège : sans `playbooks/k8s-api-fichiers.yml` **avant** la jonction, le serveur d'API de `k8s-cp02` démarre avec `--audit-policy-file` et `--encryption-provider-config` qui pointent vers des fichiers absents (la jonction reprend la `ClusterConfiguration` du ConfigMap) : il ne démarre pas, la jonction échoue en attente du plan de contrôle.

*5. Documentation* : modèles fournis.

**Explications**

Trois membres, quorum de deux : la panne d'un membre ne change rien aux écritures, mais on n'a plus de marge. La VIP et HAProxy font que les clients ne voient pas quel serveur d'API répond ; les baux font qu'un seul gestionnaire de contrôleurs et un seul ordonnanceur agissent à la fois. Retirer le membre avant de rejoindre est indispensable : etcd refuse un membre qui se présente avec un nom déjà inscrit mais un autre identifiant, et un cluster de quatre membres dont un mort a un quorum de **trois** — plus fragile que trois membres sains.

**Alternatives**
- Remplacer la VM entière par le code (`tofu apply -replace`) : plus long, mais prouve que le nœud est reconstructible (E23) ; même procédure etcd.
- Cinq membres : tolère deux pertes, au prix de la mémoire et de la latence d'écriture.

**Pièges classiques**
- `member remove` du mauvais identifiant (celui d'un membre sain : on perd le quorum si un autre tombe ensuite).
- Retirer le membre avant d'avoir arrêté l'etcd du nœud : il redémarre en boucle dans un cluster qui ne le connaît plus.
- Oublier `kubectl delete node` : la jonction réutilise l'objet `Node` avec ses anciens taints et étiquettes (ou échoue selon la version).
- Clé de certificats expirée (plus de 2 h) au moment de la jonction.
- Arrêter un deuxième nœud de contrôle « pour voir ».

**En production chez MédiSphère**
Alerte « membre etcd absent » et « nœud de contrôle NotReady » (M21), astreinte qui applique RB-144, exercice de perte d'un nœud de contrôle chaque trimestre (M29 : tests de résilience).

---

### M14-E30 — Politique de cycle de vie des versions Kubernetes

**Solution**

Modèle : [ADR-0141](fichiers/M14-E30/medisphere/docs/kubernetes/adr/ADR-0141-cycle-de-vie-des-versions.md).

**Explications**

La politique répond à quatre questions vérifiables : où se tient-on (N-1), dans quel délai bouge-t-on (90 jours après le feu vert de l'écosystème, au plus tard 4 mois avant la fin de support), à quelle vitesse applique-t-on les correctifs (un mois, 72 h pour une faille critique), et qui décide que l'écosystème est prêt (une liste de contrôle tenue par la Plateforme). Les dates de fin de support (1.35 : 28/02/2027 ; 1.36 : 28/06/2027 ; 1.37 : 28/10/2027) et les compatibilités sont celles relevées le 8 octobre 2026 : elles **doivent** être relues, c'est le cœur de la politique.

**Alternatives** (également défendables)
- Rester sur N (dernière) dès que l'écosystème la supporte, sans attendre : plus de travail, plus de fenêtre.
- Cadence fixe (une montée par trimestre à date fixe) plutôt que des délais : plus prévisible pour les équipes, mais peut tomber avant que l'écosystème ne soit prêt.

**Pièges classiques**
- Une politique sans chiffres (« on monte régulièrement »).
- Ignorer l'écosystème : la 1.37 « parce qu'elle est sortie », et Cilium hors support.
- Oublier qu'on ne saute pas de mineure : un retard de deux mineures, ce sont deux montées.
- Oublier les correctifs, qui sont l'essentiel des correctifs de sécurité.

**En production chez MédiSphère**
Renovate ouvre les MR de version, la liste de contrôle devient un ticket gabarit, et la politique est revue à chaque sortie de mineure.

**Grille d'auto-évaluation**
- [ ] Les dates de fin de support et les compatibilités sont sourcées et datées.
- [ ] La décision contient des délais chiffrés et une règle d'écosystème sous forme de liste.
- [ ] La 1.37 a une date prévue et une liste de ce qui la bloque.
- [ ] Les correctifs et l'exception de sécurité sont traités.
- [ ] Les responsabilités sont nommées.

---

### M14-E31 — ADR : distribution et topologie de `k8s-par1`

**Solution**

Modèle : [ADR-0140](fichiers/M14-E31/medisphere/docs/kubernetes/adr/ADR-0140-distribution-et-topologie.md).

**Explications**

Une ADR d'exploitation s'écrit avec ce qu'on a vécu : les durées de E24, E25 et E29, les pièges rencontrés (image *pause*, fichiers absents à la jonction, adresse annoncée par nœud) et ce qu'ils coûteraient avec une autre option. La décision de référence garde kubeadm et la topologie actuelle, parce que l'équipe sait maintenant l'exploiter et qu'aucune option ne supprime la vraie contrainte (l'écosystème) ; elle fixe aussi la condition pour la remplacer (mesures du M18).

**Alternatives** (décisions également défendables)
- RKE2 en production après le M18 : durcissement CIS par défaut et etcd intégré, au prix d'une dépendance à SUSE.
- Talos : sécurité et immuabilité, rupture d'outillage ; défendable pour un nouveau cluster, pas pour une migration immédiate.
- kube-vip à la place de keepalived + HAProxy : moins de composants hors de Kubernetes, un composant de plus dans le chemin critique.

**Pièges classiques**
- Comparer des listes de fonctionnalités au lieu de critères d'exploitation mesurés.
- Oublier le coût en mémoire du lab (etcd externe, cinq nœuds de contrôle).
- Ne pas dire quand et comment l'ADR serait revue.

**En production chez MédiSphère**
L'ADR est revue après le M18 avec les mêmes mesures sur RKE2 et Talos, et à chaque nouveau cluster.

**Grille d'auto-évaluation**
- [ ] Les quatre axes (distribution, etcd, point d'accès, taille) sont traités sur les mêmes critères.
- [ ] Au moins trois mesures ou incidents du module sont cités.
- [ ] La décision est motivée, ses conséquences et sa condition de remplacement sont écrites.

---

### M14-E32 — Questions de production : Kubernetes

**1. Quorum.** Quorum = ⌊N/2⌋ + 1. Trois membres : quorum de 2, on peut en perdre **un**. Quatre membres : quorum de 3, on ne peut toujours en perdre qu'**un** — un quatrième membre ajoute une machine qui peut tomber sans ajouter de tolérance, et rend les écritures plus lentes (une majorité plus grande à attendre). D'où les nombres impairs (3, 5). Sans quorum : plus aucune écriture ni lecture cohérente ; les serveurs d'API échouent ; mais les **pods déjà lancés tournent** (le kubelet garde son état), les Services continuent de fonctionner (règles kube-proxy/Cilium déjà en place), CoreDNS répond depuis son cache tant que ses pods vivent. Rien de nouveau ne peut être planifié, rien ne se répare.

**2. Réponse b.** Deux membres sur trois perdus = quorum perdu sans retour : on restaure **tous** les membres depuis un instantané (RB-141), cluster etcd neuf, puis on recrée les nœuds perdus et on les rejoint. a) est impossible : `member remove` est une écriture, qui exige le quorum. d) ramène des membres anciens avec d'anciennes identités : incohérence garantie. c) `--force-new-cluster` sur le survivant est **parfois** une option : il redémarre le membre survivant comme un cluster d'un seul membre **avec ses données**, ce qui évite de perdre ce qui a été écrit depuis le dernier instantané ; condition : être certain que les deux autres membres ne reviendront jamais (sinon deux clusters divergent) ; risque : la documentation d'etcd le déconseille fortement, et le membre survivant pouvait être en retard. Choix raisonné : instantané si récent, `--force-new-cluster` si l'instantané est trop ancien et que le survivant était à jour (vérifier sa révision), avec une copie de son répertoire avant tout.

**3. Restauration impossible le jour J.** (1) La clé privée `age` perdue ou illisible → test de restauration trimestriel ; (2) la clé de chiffrement des Secrets de l'époque détruite (E28) → registre des secrets et rétention des clés, test de restauration qui lit un Secret ; (3) instantanés illisibles (corruption, envoi tronqué) → `snapshot status` avant envoi et relecture de la taille, test périodique ; (4) objets supprimés par la rétention ou par un compte compromis → politique qui interdit la suppression, versionnage, surveillance du nombre d'objets ; (5) `etcdutl` d'une version incompatible → outils alignés à chaque montée (E25) ; (6) procédure jamais jouée, personne ne sait l'appliquer → RB-141 répété ; (7) les certificats et `sa.key` absents sur des VMs neuves → sauvegarde de `/etc/kubernetes/pki`. Une sonde verte ne prouve qu'une chose : qu'un fichier a été envoyé.

**4. Sans saut de révision ni compactage.** La révision recule : les clients qui reprennent un *watch* depuis leur dernière révision connue (plus grande que celle du cluster restauré) attendent des événements qui n'arriveront jamais, ou reçoivent des événements dont les numéros ont déjà été vus ; les caches des *informers* (gestionnaire de contrôleurs, ordonnanceur, kubelet, Cilium, opérateurs) gardent des objets qui n'existent plus ou ratent des créations. Symptômes : pods fantômes, Services sans points d'accès à jour, contrôleurs qui ne réagissent pas, identités Cilium incohérentes, jusqu'au redémarrage des composants ou à l'expiration de leur cache. D'où `--bump-revision` + `--mark-compacted`, et le redémarrage ordonné.

**5. Réponse b.** `kubeadm upgrade apply` est idempotent : on relance la même commande, qui reprend là où l'état le demande. a) est excessif : les autres membres etcd sont sains, le quorum aussi. c) est faux : kubeadm 1.36 sait finir une montée commencée. d) n'est utile que si la relance échoue et que kubeadm n'a pas pu revenir en arrière seul : `/etc/kubernetes/tmp/kubeadm-backup-manifests-*` (manifestes d'avant) et `kubeadm-backup-etcd-*` (données du membre local d'avant) permettent de remettre le nœud dans son état antérieur à la main. La documentation cite aussi `kubeadm upgrade apply --force` pour sortir d'un état incohérent sans changer de version.

**6. Travailleur resté en 1.35.** Supporté : un kubelet peut avoir jusqu'à **trois** mineures de retard sur le serveur d'API (politique actuelle). Jusqu'à la fin de support de la 1.35 (28/02/2027) pour les correctifs, et techniquement jusqu'à un plan de contrôle en 1.38. À la montée 1.37 du plan de contrôle, il reste dans la politique (1.35 = N-2), mais kubeadm vérifie la politique de décalage dans `upgrade plan` ; et aucune montée de ce nœud vers 1.37 ne sera possible sans passer par 1.36 (kubeadm ne saute pas de mineure, même pour un kubelet). La vraie question est le drain bloqué : une PDB à 0 perturbation autorisée ou un pod sans contrôleur, à corriger.

**7. Drain avant une mineure.** Le kubelet d'une nouvelle mineure relance tous les conteneurs (hachage de spécification modifié) et la compatibilité de son état local (points de contrôle, plugins) entre mineures n'est pas garantie ; drainer d'abord évite des redémarrages sauvages et respecte les PDB. Un correctif ne change en général ni l'un ni l'autre, d'où la pratique, mais la documentation demande le drain pour les mineures. Un pod sans contrôleur : `kubectl drain` refuse sans `--force` ; avec `--force`, il est **supprimé** et ne revient jamais.

**8. Certificats expirés.** Sur **chaque** nœud de contrôle, l'un après l'autre : `kubeadm certs check-expiration` (constat), `kubeadm certs renew all` (fonctionne hors ligne avec la CA du disque), redémarrage des pods statiques (manifestes retirés puis remis) ; puis `admin.conf` neuf pour reprendre la main dans l'API ; copies du coffre et `~/.kube/config` des administrateurs. Kubelets : leur certificat **client** a lui aussi environ un an ; s'il est expiré, le kubelet ne peut plus renouveler par CSR : RB-143 §6 (régénérer `kubelet.conf` ou rejoindre le nœud). Prévention : une montée de version au moins par an (ADR-0141) renouvelle tout ; la minuterie d'échéances alerte à 30 jours.

**9. Réponse d.** Le kubelet attend un certificat de service qui ne vient pas : le port 10250 n'a pas de certificat de service valide (pas de repli sur l'auto-signé quand `serverTLSBootstrap` est actif), les connexions TLS vers lui échouent — metrics-server, `kubectl logs`, `exec`, `port-forward`, `attach` (le serveur d'API se connecte au kubelet). Mais le kubelet tourne, le nœud est `Ready`, les pods tournent. a) faux : le kubelet démarre. b) est une **conséquence** de d), pas toute la réponse. c) était vrai **avant** l'activation.

**10. Tout en `RequestResponse`.** Sécurité : le contenu des Secrets, des jetons (`TokenRequest`) et des ConfigMaps est écrit en clair dans les journaux et leurs copies. Disponibilité : volume énorme (chaque `list` complet), disque des nœuds de contrôle plein (etcd et le serveur d'API sur le même disque), latence des requêtes (backend synchrone). Exploitation : coût de stockage et de recherche, et des données personnelles dans les journaux (RGPD).

**11. Copie de `/var/lib/etcd`.** Avec `secretbox`, les Secrets de cette copie sont chiffrés : **sans** le fichier `/etc/kubernetes/chiffrement/configuration.yaml`, illisibles. La sauvegarde PBS **entière** de la VM contient les deux : lisibles. Un compte avec `get secrets` lit les Secrets de l'espace en clair par l'API : le chiffrement au repos ne fait rien contre lui. Conclusion : le chiffrement au repos local protège les **copies d'etcd séparées des nœuds** (instantanés) ; KMS protège aussi contre la copie d'un nœud entier, en sortant la clé maîtresse ; aucun ne remplace le RBAC.

**12. Réponse b.** Le serveur d'API essaie les fournisseurs restants pour déchiffrer, aucun ne connaît la clé nommée dans le préfixe : erreur à la lecture (`failed to decrypt`… ), les pods qui montent ces Secrets ne démarrent plus, les contrôleurs qui les lisent échouent. a) faux : rien n'est réécrit automatiquement. c) faux : la configuration est valide, le serveur démarre. d) faux : `identity` ne lit que ce qui est en clair. Sortie : remettre l'ancienne clé dans la configuration (d'où sa conservation dans le Vault), attendre le rechargement, réécrire tous les Secrets, puis seulement retirer l'ancienne clé.

**13. VIP et HAProxy sur les nœuds de contrôle.** Pas d'autre machine à maintenir et pas de dépendance à une autre équipe (méthode keepalived + HAProxy de la documentation kubeadm). HAProxy écoute sur 8443 parce que le serveur d'API du nœud occupe déjà 6443 sur toutes les adresses du nœud, VIP comprise. Si keepalived met la VIP sur un nœud dont le serveur d'API est arrêté, ce n'est pas grave tant que **HAProxy** tourne : il envoie aux serveurs d'API vivants des autres nœuds. Si HAProxy lui-même est arrêté sur le maître VRRP, la VIP ne répond plus : d'où le script de suivi de keepalived (M14-E03) qui fait perdre la VIP à un nœud dont HAProxy est mort.

**14. Cinq nœuds de contrôle.** Tolérance : deux pertes au lieu d'une. Latence d'écriture : un peu plus élevée (quorum de 3 à attendre, plus de pairs à alimenter). Mémoire : deux VMs de 4 Go de plus, que le lab n'a pas. Montée de version : deux nœuds de plus à passer un à un. Je l'accepterais pour un cluster de production où la perte simultanée de deux nœuds est plausible (deux salles, maintenance d'un hyperviseur portant deux nœuds) et où le budget le permet ; pas pour le lab, où les trois nœuds de contrôle sont de toute façon sur le même `pve01`.

---

### M14-E33 — Accueillir une équipe sur le cluster

**Solution** (une solution possible ; `LIBRE` : d'autres choix sont valables s'ils respectent les contraintes)

Fichiers dans `plateforme/k8s` : [`espaces/medidoc-dev/`](fichiers/M14-E33/k8s/espaces/medidoc-dev/) (`00-namespace.yaml`, `10-quota.yaml`, `20-limites.yaml`, `30-comptes-service.yaml`, mêmes conventions que `mediagenda-dev` en E10-E19), [`rbac/40-medidoc.yaml`](fichiers/M14-E33/k8s/rbac/40-medidoc.yaml), [gabarit](fichiers/M14-E33/k8s/gabarits/equipe/) et [`outils/nouvelle-equipe.sh`](fichiers/M14-E33/k8s/outils/nouvelle-equipe.sh) ; dans `plateforme/medisphere` : [procédure d'accueil](fichiers/M14-E33/medisphere/docs/kubernetes/accueil-equipe.md), [fiche de l'équipe](fichiers/M14-E33/medisphere/docs/kubernetes/equipes/medidoc.md).

Déroulé : `outils/nouvelle-equipe.sh medidoc dev`, ajustement de l'enveloppe et du responsable, MR, `task appliquer` ; `outils/secret-tirage.sh medidoc-dev` (E19) ; identité du référent comme en E12 (CSR avec `O=medisphere:medidoc-devs`, durée courte, approbation après lecture) ; essais :

```
admin@adm01:~$ kubectl auth can-i create deployments -n medidoc-dev --as amelie.durand --as-group medisphere:medidoc-devs
yes
admin@adm01:~$ kubectl auth can-i get secrets -n medidoc-dev --as amelie.durand --as-group medisphere:medidoc-devs
yes
admin@adm01:~$ kubectl auth can-i update resourcequota/enveloppe -n medidoc-dev --as amelie.durand --as-group medisphere:medidoc-devs
no
admin@adm01:~$ kubectl auth can-i create rolebindings -n medidoc-dev --as amelie.durand --as-group medisphere:medidoc-devs
no
admin@adm01:~$ kubectl auth can-i list pods -n mediagenda-dev --as amelie.durand --as-group medisphere:medidoc-devs
no
admin@adm01:~$ kubectl -n medidoc-dev run essai-latest --image=registry.par1.medisphere.internal/medisphere/medidoc:latest --dry-run=server
Error from server (Forbidden): … (Pod Security « restricted » et/ou ValidatingAdmissionPolicy medisphere-images)
```

(`amelie.durand` : nom du référent de l'exemple ; prends celui que tu as choisi.) Le pod de test MédiDoc, avec le contexte de sécurité qu'exige `restricted` (`runAsNonRoot`, `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`), démarre ; il n'est pas prêt (`/readyz` fait un `HeadBucket` sur S3, qui n'est pas configuré) : c'est attendu, la configuration S3 arrive au M16.

Lecture hors de l'espace : **aucune**, comme MédiAgenda. Les besoins avancés (voir les étiquettes de son espace pour comprendre un refus, lister les classes de priorité ou de stockage) se servent par la fiche de l'équipe et les messages d'erreur ; si l'équipe insiste, un ClusterRole limité à `get` sur `namespaces` avec `resourceNames: [medidoc-dev]` est une réponse précise.

**Explications**

L'espace porte lui-même ses règles : les étiquettes Pod Security et l'étiquette `medisphere.internal/equipe`, que la liaison `medisphere-images` de E18 sélectionne (`Exists`). L'équipe ne peut pas modifier son espace (aucun droit sur `namespaces` en écriture), donc ne peut pas desserrer ces règles. Le ResourceQuota sur `requests`/`limits` impose que chaque conteneur déclare ses ressources : le LimitRange donne des valeurs par défaut pour que l'oubli ne se traduise pas par un refus incompréhensible. Le compte `default` porte le Secret de tirage : les manifestes de l'équipe n'ont rien à savoir de Harbor. Les droits réutilisent les ClusterRoles agrégés de E11 : ajouter une équipe, c'est deux RoleBindings, pas un nouveau rôle à relire.

**Alternatives**
- ClusterRole intégré `edit` dans un RoleBinding : acceptable (il ne donne ni les quotas ni le RBAC), mais plus large que nécessaire (usurpation des comptes de service de l'espace, PVC) et hors du modèle d'agrégation de E11.
- Un Role propre à l'équipe : lisible, mais à maintenir équipe par équipe.
- Hiérarchie d'espaces ou outil multi-locataires (Capsule) : utile au-delà de quelques équipes.
- Gabarit par Kustomize ou chart (M17), appliqué par GitOps (M20) : l'accueil devient une MR de l'équipe elle-même.

**Pièges classiques**
- Donner `admin` « pour simplifier » (RoleBindings et quotas modifiables, donc tout le reste aussi).
- Oublier le LimitRange : chaque pod sans ressources est refusé par le quota.
- Oublier l'étiquette `medisphere.internal/equipe` : la politique d'images ne s'applique pas, sans aucun message.
- Lier `medisphere-secrets-edition` en recette ou en production.
- Un ClusterRoleBinding vers `view` : l'équipe lit les autres espaces (sauf les Secrets).

**En production chez MédiSphère**
Registre des équipes dans `plateforme/k8s`, accueil par MR de l'équipe, GitOps (M20), identités par Keycloak (M24) et groupes synchronisés, NetworkPolicies par défaut (M15).

---

### M14-E34 — Examen blanc d'administration

**Solution** (déroulé de référence ; à ne lire qu'après ta tentative chronométrée)

Objets de référence : [`solution.yaml`](fichiers/M14-E34/solution.yaml) (tâches 1 à 8, 10, 11, 14) et [`rdv-examen-repare.yaml`](fichiers/M14-E34/rdv-examen-repare.yaml) (tâche 9). En examen, on va plus vite à l'impératif, en générant puis complétant :

```
admin@adm01:~$ kubectl create namespace wb-examen --dry-run=client -o yaml > t1.yaml          # + étiquettes
admin@adm01:~$ kubectl -n wb-examen create quota quota-examen --hard=pods=15,requests.cpu=2,requests.memory=4Gi,limits.memory=6Gi
admin@adm01:~$ kubectl -n wb-examen create configmap api-examen-config --from-literal=MEDIAGENDA_DB_URL=… --from-literal=…
admin@adm01:~$ kubectl -n wb-examen create deployment api-examen --image=<IMAGE-MEDIAGENDA> --replicas=3 --dry-run=client -o yaml > t3.yaml
admin@adm01:~$ kubectl -n wb-examen expose deployment api-examen --port=80 --target-port=8000
admin@adm01:~$ kubectl -n wb-examen create pdb api-examen --selector=app=api-examen --min-available=2
admin@adm01:~$ kubectl -n wb-examen create serviceaccount lecteur-examen
admin@adm01:~$ kubectl -n wb-examen create role lecture-pods --verb=get,list,watch --resource=pods,pods/log
admin@adm01:~$ kubectl -n wb-examen create rolebinding lecteur-examen --role=lecture-pods --serviceaccount=wb-examen:lecteur-examen
admin@adm01:~$ kubectl -n wb-examen create cronjob purge-examen --image=<IMAGE-MEDIAGENDA> --schedule='*/15 * * * *' --dry-run=client -o yaml -- python -c "print('purge')" > t8.yaml
admin@adm01:~$ kubectl label node k8s-w01 examen.medisphere.internal/frontal=oui
admin@adm01:~$ kubectl taint node k8s-w03 examen=maintenance:NoSchedule
admin@adm01:~$ kubectl create priorityclass examen-haute --value=100000 --preemption-policy=Never
admin@k8s-cp01:~$ sudo etcdctl … snapshot save /var/backups/etcd/examen-blanc.db && sudo etcdutl snapshot status /var/backups/etcd/examen-blanc.db -w table
admin@k8s-cp01:~$ sudo etcdctl … endpoint status --cluster -w table           # leader ; version
admin@adm01:~$ kubectl get ciliumnode k8s-w02 -o jsonpath='{.spec.ipam.podCIDRs[0]}'
```

Tâche 9, démarche : `kubectl -n wb-examen get deploy,rs,pods` → aucun pod : `kubectl -n wb-examen describe rs` → *exceeded quota* (64Gi demandés, quota de 4Gi) ; correction des ressources → pods en `CrashLoopBackOff` : `kubectl logs` → variable `MEDIAGENDA_VALKEY_URL` manquante ; correction → pods `Running` mais pas `Ready` : `describe pod` → sonde de disponibilité en échec sur 8080 ; correction → pods prêts mais `kubectl -n wb-examen get endpointslices -l kubernetes.io/service-name=rdv-examen` vide : sélecteur du Service `app: rdv` ; correction. Quatre défauts, quatre couches (admission, application, sonde, Service).

Tâche 4 : le piège est la politique par défaut `nodeTaintsPolicy: Ignore` : `k8s-w03` (taint `dedie=bdd`) et les nœuds de contrôle comptent comme des zones vides, et la troisième réplique devient inordonnançable (écart de 2 avec la zone « vide »). `nodeTaintsPolicy: Honor` ne compte que les nœuds que le pod tolère : les réplicas se répartissent 2/1 entre `par1-baie-a` et `par1-baie-b`.

Tâche 11 : le piège est le taint `dedie=bdd:NoSchedule` posé sur `k8s-w03` en E14 ; un pod qui ne tolère que le nouveau taint reste `Pending` (`describe` : « untolerated taint »).

Tâche 13 : `version_etcd` se lit dans `endpoint status` (colonne VERSION) ou l'image du pod etcd (`3.6.8-0` → `3.6.8`) ; le leader change si un membre redémarre entre ta réponse et la vérification (le check l'accepte s'il correspond au leader au moment du check : réponds tard).

**Explications**

Un examen de gestes : la vitesse vient des commandes impératives avec `--dry-run=client -o yaml` (un squelette juste, qu'on complète), de `kubectl explain` (champ exact : `kubectl explain deployment.spec.template.spec.topologySpreadConstraints`), et d'une méthode de diagnostic par couches (objet → contrôleur → pod → conteneur → réseau).

**Alternatives**
Écrire tout en YAML depuis la documentation : plus lent, mais plus sûr pour les objets riches (CronJob, affinités).

**Pièges classiques**
- Oublier `-n wb-examen` : objets créés dans `default` (le check ne les trouve pas).
- `nodeSelector` à la tâche 10 au lieu d'une affinité obligatoire.
- `concurrencyPolicy` oublié, `timeZone` mal orthographiée (`Europe/Paris`).
- La PriorityClass créée avec la préemption par défaut (`PreemptLowerPriority`).
- Ne pas vérifier l'instantané (`snapshot status`).

**En production chez MédiSphère**
Cet examen sert de grille d'entrée dans l'astreinte `k8s-par1` ; les gestes lents identifiés deviennent des fiches réflexes.
