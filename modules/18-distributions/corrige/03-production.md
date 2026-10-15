# Module 18 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

Fichiers de solution : `corrige/fichiers/M18-E13/` à `M18-E18/`. Les chemins `distributions/…` sont relatifs au dépôt `plateforme/distributions`, `ansible/…` à `plateforme/ansible`, `infra/…` à `plateforme/infra`, `medisphere/…` à `plateforme/medisphere`.

**Vérifié pendant la rédaction** (sources lues au tag ou dans la doc de la version) :
- types Go de Cluster API **v1.12.11** (`api/core/v1beta2`, `api/controlplane/kubeadm/v1beta2`, `api/ipam/v1beta2`) : champs `rollout`, `checks`, `remediation.triggerIf`, `remediationStrategy` devenu `remediation` (`maxRetry`, `retryPeriodSeconds`, `minHealthyPeriodSeconds`), annotation `cluster.x-k8s.io/delete-machine` ;
- types de CAPMOX **v0.9.1** (`api/v1alpha2`) : `templateID`, `sourceNode`, `templateSelector`, `vmIDRange`, raisons de la condition `VirtualMachineProvisioned` ;
- docs k3s (*etcd-snapshot*, *Backup and Restore*, *secrets-encrypt*, *token*), RKE2 (*Backup and Restore*, *CIS Hardening Guide*), Talos 1.14 (*Disaster Recovery*, référence `talosctl`) ;
- CAPO **v0.15.0** : README (matrice), `metadata.yaml` (contrat `v1beta2`), `go.mod` (`sigs.k8s.io/cluster-api v1.14.1`) ;
- kube-bench **v0.16.0** : `cfg/config.yaml` (correspondances de versions).

Les manifestes YAML ont été contrôlés avec `yamllint` et `kubeconform` (schémas Kubernetes 1.36 ; les CRD Cluster API et CAPMOX ne sont pas dans les schémas publics, elles ont été relues à la main contre les types Go).

**Non testé en conditions réelles** : toutes les manipulations sur Proxmox VE 9 (CAPMOX n'y est pas documenté), les durées citées (ordres de grandeur attendus, à remplacer par tes mesures), la restauration Talos 1.14 de bout en bout, et le comportement exact de la purge S3 de k3s et RKE2 face à une identité sans droit de suppression (voir E14).

---

### M18-E13 — Cycle de vie par Cluster API : montée de version, réparation, mise à l'échelle

**Solution**

Fichiers : [`mhc-travailleurs.yaml`](fichiers/M18-E13/distributions/capi/capi-essai/mhc-travailleurs.yaml), [témoin](fichiers/M18-E13/distributions/capi/capi-essai/essais/temoin.yaml), [nouveaux gabarits](fichiers/M18-E13/distributions/capi/capi-essai/gabarits-k136-2.yaml), [extrait KCP et MD](fichiers/M18-E13/distributions/capi/capi-essai/montee-v1.36.5.extrait.yaml), [variables image-builder](fichiers/M18-E13/images/capi/ubuntu-2404-k136-2.json) (dans `plateforme/images`, avec le `construire.sh` de E09), [boucle témoin](fichiers/M18-E13/distributions/capi/outils/suivi-temoin.sh), [RB-182](fichiers/M18-E13/medisphere/docs/kubernetes/distributions/runbooks/RB-182-montee-version-capi.md), [compte rendu](fichiers/M18-E13/medisphere/docs/kubernetes/distributions/tests/cycle-de-vie-capi.md).

*1. Lecture.*

```
admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/k3s01.kubeconfig
admin@adm01:~$ clusterctl describe cluster capi-essai -n capi-essai --show-conditions all
admin@adm01:~$ kubectl get cluster,kcp,md,ms,machines,proxmoxmachines -n capi-essai -o wide
admin@adm01:~$ kubectl get machines -n capi-essai --show-labels
admin@adm01:~$ kubectl get proxmoxmachine -n capi-essai <NOM> -o jsonpath='{.spec.virtualMachineID} {.status.proxmoxNode}{"\n"}'
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/capi-essai.kubeconfig get nodes \
>   -o custom-columns=NOM:.metadata.name,PROVIDER:.spec.providerID,VERSION:.status.nodeInfo.kubeletVersion
```

Chaîne : `Cluster` → `KubeadmControlPlane` (gabarit `ProxmoxMachineTemplate` du plan de contrôle, configuration kubeadm intégrée) et `MachineDeployment` → `MachineSet` (une par version de la spécification) → `Machine` → `ProxmoxMachine` (VMID, nœud Proxmox, adresses) + `KubeadmConfig` (données d'amorçage cloud-init) → VM → `Node` (`providerID: proxmox://<UUID SMBIOS>`, injecté par `kubeletExtraArgs` du gabarit). Étiquettes utiles : `cluster.x-k8s.io/cluster-name=capi-essai` sur toutes les machines, `cluster.x-k8s.io/deployment-name=capi-essai-travailleurs` (nom du MD de E10) sur les travailleurs, `cluster.x-k8s.io/control-plane` (et `cluster.x-k8s.io/control-plane-name`) sur le plan de contrôle.

*2. Témoin* : appliquer [`temoin.yaml`](fichiers/M18-E13/distributions/capi/capi-essai/essais/temoin.yaml) dans le cluster de charge de travail, puis lancer la boucle dans un `tmux` :

```
admin@adm01:~/src/distributions$ capi/outils/suivi-temoin.sh | tee ~/capi-temoin-$(date +%F).log
```

Elle écrit une ligne par seconde (`heure prêts/désirés`) et la valeur minimale à l'arrêt.

*3. MachineHealthCheck.* Points clés du [manifeste](fichiers/M18-E13/distributions/capi/capi-essai/mhc-travailleurs.yaml) :
- `selector.matchLabels: {cluster.x-k8s.io/deployment-name: capi-essai-travailleurs}` : le MD seul, jamais le plan de contrôle ;
- `checks.unhealthyNodeConditions` : `Ready` `Unknown` et `Ready` `"False"`, `timeoutSeconds: 300` (les guillemets autour de `False` sont obligatoires : sans eux, YAML lit un booléen et le serveur refuse le champ) ;
- `checks.nodeStartupTimeoutSeconds: 900` : un clone complet sur `local-nvme`, le premier démarrage, cloud-init, `kubeadm join` et le tirage des images prennent plusieurs minutes. Avec le défaut de 10 minutes, une machine lente serait supprimée **pendant** son démarrage, et la suivante aussi : boucle de remplacement ;
- `remediation.triggerIf.unhealthyLessThanOrEqualTo: 1` : **un nombre**, pas un pourcentage. « 40 % » de 2 machines donne 0,8, arrondi vers le bas à 0 : rien ne serait jamais réparé. « 50 % » donnerait 1 aujourd'hui, mais 1 aussi à 3 machines, et 2 à 4 : le nombre absolu dit exactement ce qu'on veut (une réparation à la fois sur ce petit cluster). Si les deux travailleurs tombent ensemble, c'est probablement le réseau ou Proxmox : réparer ne ferait qu'empirer.

```
admin@adm01:~/src/distributions$ kubectl apply --dry-run=server -f capi/capi-essai/mhc-travailleurs.yaml
admin@adm01:~/src/distributions$ kubectl apply -f capi/capi-essai/mhc-travailleurs.yaml     # après fusion de la MR
admin@adm01:~$ kubectl get mhc -n capi-essai
NAME                      CLUSTER      EXPECTEDMACHINES   MAXUNHEALTHY   CURRENTHEALTHY   AGE
capi-essai-travailleurs   capi-essai   2                  1              2                30s
```

(Les colonnes affichées dépendent de la version, à vérifier sur la tienne.) Test :

```
root@pve01:~# qm stop <VMID-DU-TRAVAILLEUR>
admin@adm01:~$ kubectl get machines -n capi-essai -w
admin@adm01:~$ kubectl get events -n capi-essai --field-selector reason=MachineMarkedUnhealthy -w
```

Chronologie attendue (ordres de grandeur, à remplacer par tes mesures) :

| T | Événement |
|---|---|
| 0 | `qm stop` |
| ≈ 40 s à 1 min | `Node` en `Ready=Unknown` (bail du kubelet non renouvelé) ; les pods `temoin` du nœud restent comptés tant qu'ils ne sont pas évincés |
| ≈ 5 min | éviction par le contrôleur de nœuds (`tolerationSeconds: 300` par défaut) : les pods sont recréés ailleurs |
| ≈ 6 min | la `Machine` reçoit la condition `HealthCheckSucceeded=False`, puis `OwnerRemediated=False` ; le `MachineSet` la supprime |
| ≈ 6 à 8 min | drain (rapide : Cluster API n'attend pas les pods d'un nœud injoignable déjà marqués pour suppression), suppression de la VM par CAPMOX, libération de l'adresse |
| ≈ 8 à 15 min | nouvelle `Machine`, clone, démarrage, `kubeadm join`, `Node` `Ready` |

Pourquoi pas de MHC sur le plan de contrôle : avec un seul nœud de contrôle, le remplacer veut dire supprimer **le seul** membre etcd. Le KCP refuse une réparation qui ferait perdre le quorum : une réparation n'est possible qu'à partir de deux machines de contrôle déjà initialisées, et n'a de sens qu'à trois (on perd un membre sur trois, on en recrée un). Pour un plan de contrôle unique, la réponse à la panne est la sauvegarde (E14), pas la réparation automatique.

*4. Mise à l'échelle* : `spec.replicas: 3` dans le manifeste du MD (MR, puis `kubectl apply`), ou `kubectl scale md capi-essai-travailleurs -n capi-essai --replicas 3` pour l'essai **suivi immédiatement** d'un commit qui l'écrit (sinon le prochain `apply` du dépôt reviendrait à 2). Retour à 2 en choisissant la machine :

```
admin@adm01:~$ kubectl annotate machine -n capi-essai <MACHINE> cluster.x-k8s.io/delete-machine=oui
admin@adm01:~$ kubectl scale md capi-essai-travailleurs -n capi-essai --replicas 2
```

La valeur de l'annotation est libre : sa seule présence donne la priorité à la suppression. Sans elle, le `MachineSet` choisit selon `spec.deletion.order` du MD (`Random` par défaut en v1beta2 ; `Newest` et `Oldest` existent). Pendant le drain, le PDB `minAvailable: 2` du témoin fait attendre l'éviction du troisième pod tant que son remplaçant n'est pas prêt : la boucle ne descend jamais sous 2. C'est le même mécanisme qu'en M14-E17, mais déclenché par le contrôleur de `Machine`.

*5. Montée de version.*

Image :

```
admin@m18-dev01:~/src/images$ NOEUD=<NOEUD> VARS=capi/ubuntu-2404-k136-2.json ETIQUETTES='capi;k8s-v1.36.5' capi/construire.sh --valider
admin@m18-dev01:~/src/images$ NOEUD=<NOEUD> VARS=capi/ubuntu-2404-k136-2.json ETIQUETTES='capi;k8s-v1.36.5' capi/construire.sh
root@pve01:~# qm set 9061 --tags 'capi;current;k8s-v1.36.5'
root@pve01:~# qm set 9060 --tags 'capi;k8s-v1.36.4'
```

(Même script que E09 : le fichier de variables `capi/ubuntu-2404-k136-2.json` de `plateforme/images` ne change que le VMID, le nom et les versions ; `construire.sh` accepte désormais `VARS`. Contrôle du template et clone d'essai en 5188 comme en E09, avant de déplacer `current`.) Ordre et raisons :
- **nouveaux gabarits sous de nouveaux noms** (`capi-essai-plan-controle-1365`, `capi-essai-travailleurs-1365`, copies exactes des gabarits `…-1364` de E10 où seuls le nom et `templateID` changent) : un `ProxmoxMachineTemplate` est la recette des machines **futures** ; le modifier en place ne remplacerait rien, et les machines créées ensuite (réparation, mise à l'échelle) n'auraient pas la même image que les autres ;
- **plan de contrôle d'abord** : la politique de décalage interdit un kubelet plus récent que le serveur d'API. Le KCP remplace la machine de contrôle (surplus de 1 : une 2e machine de contrôle rejoint etcd, puis l'ancienne est retirée du membre etcd et supprimée). Avec un seul nœud de contrôle, `maxSurge: 0` est impossible ; le KCP crée toujours avant de supprimer ;
- **travailleurs ensuite** : `rollout.strategy.rollingUpdate.maxSurge: 1`, `maxUnavailable: 0` : une machine neuve `Ready` avant chaque suppression, drain respectant le PDB ;
- le KCP et le MD peuvent recevoir leur nouvelle version dans la même MR, mais c'est déconseillé : Cluster API ne séquence pas les deux objets entre eux (seul un `ClusterClass` avec topologie le fait). On fait deux MR, ou une MR et deux applications.

Suivi :

```
admin@adm01:~$ clusterctl describe cluster capi-essai -n capi-essai
admin@adm01:~$ kubectl get kcp,md -n capi-essai -w
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/capi-essai.kubeconfig get nodes -w
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/capi-essai.kubeconfig -n kube-system exec etcd-<NŒUD> -- \
>   etcdctl --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/server.crt \
>   --key /etc/kubernetes/pki/etcd/server.key member list -w table
```

Pendant le remplacement du plan de contrôle, etcd passe à **deux** membres le temps de la jonction : une panne de l'un des deux à ce moment fait perdre le quorum. C'est le moment le plus fragile d'un plan de contrôle unique, et une raison de plus pour en avoir trois en production.

Retour arrière : remettre `version: v1.36.4` et les anciens gabarits (qui pointent sur 9060) déclenche un nouveau remplacement vers l'ancienne image. Cela ne marche que si 9060 existe encore : on ne supprime pas l'ancien template avant la fin de la période d'observation (RB-182).

*6. Documentation* : modèles fournis.

**Explications**

Cluster API applique au cluster la logique d'un `Deployment` : une spécification désirée (version, gabarit), des contrôleurs qui comparent avec l'existant et remplacent ce qui diffère, jamais de modification en place d'un nœud (« immutable infrastructure »). D'où ses propriétés : une montée de version est un remplacement de machines, pas un `apt upgrade` ; un nœud malade se remplace, il ne se répare pas ; l'image du nœud fait partie de la version. Le prix : il faut des images construites et testées à l'avance (E09), une plage de VMID et d'adresses qui supporte le surplus, et un cluster de gestion qui reste disponible et sauvegardé (E14).

**Alternatives**
- `ClusterClass` et `Cluster.spec.topology` : une seule ligne `version:` dans le `Cluster`, et le contrôleur de topologie séquence plan de contrôle puis travailleurs, avec des crochets (*runtime hooks*) avant et après. Plus élégant pour plusieurs clusters ; plus d'abstraction à apprendre. CAPMOX fournit des gabarits `ClusterClass`.
- `templateSelector.matchTags` au lieu de `templateID` : l'image suit l'étiquette `current`. Pratique, mais **dangereux** : déplacer l'étiquette change silencieusement l'image des futures machines (réparation, mise à l'échelle) sans remplacement des existantes. Si on l'utilise, on porte la version dans les étiquettes (`k8s-v1.36.5`) et on crée quand même de nouveaux gabarits.
- Remédiation externe (`remediation.templateRef`, ex. redémarrage par l'hyperviseur plutôt que remplacement) : utile quand le remplacement coûte cher (bare metal).

**Pièges classiques**
- Seuil en pourcentage arrondi à 0 sur un petit pool.
- `nodeStartupTimeoutSeconds` trop court : boucle de remplacements.
- Un MHC dont le sélecteur attrape aussi le plan de contrôle, ou deux MHC qui se chevauchent.
- Modifier un `ProxmoxMachineTemplate` en place et croire avoir monté de version.
- Monter les travailleurs avant le plan de contrôle.
- Plage `vmIDRange` ou pool d'adresses sans place pour le surplus : la machine neuve reste en `Provisioning` (c'est la panne de M18-E21).
- Supprimer 9060 juste après la montée : plus de retour arrière, et plus de réparation possible pour une machine restée sur l'ancien gabarit.
- `kubectl scale` sans commit : le dépôt et le cluster divergent.

**En production chez MédiSphère**
Trois nœuds de contrôle et un MHC dessus, `remediation.maxRetry` sur le KCP, `ClusterClass` partagée par tous les clusters, images reconstruites chaque mois par un pipeline (M19) et testées sur un cluster de recette avant d'être étiquetées, alertes sur les machines bloquées (M21), changement de version déclaré et suivi en GitOps (M20).

---

### M18-E14 — Sauvegarder et restaurer selon la distribution

**Solution**

Fichiers : stockage objet ([extrait `seaweedfs`](fichiers/M18-E14/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait), [politique](fichiers/M18-E14/infra/outils/s3/politique-etcd-m18.json), [cycle de vie](fichiers/M18-E14/infra/outils/s3/cycle-de-vie-etcd-m18.json), [`s3-etcd-m18.env`](fichiers/M18-E14/adm01/s3-etcd-m18.env.exemple)) ; [pare-feu](fichiers/M18-E14/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; banc : [variables OpenTofu](fichiers/M18-E14/infra/envs/m18/banc-k3s.auto.tfvars.extrait), [inventaire](fichiers/M18-E14/ansible/inventories/lab/host_vars/) ; extension des rôles : [`k3s`](fichiers/M18-E14/ansible/roles/k3s/tasks/etcd_s3.yml) et [gabarit](fichiers/M18-E14/ansible/roles/k3s/templates/50-etcd-s3.yaml.j2), [`rke2`](fichiers/M18-E14/ansible/roles/rke2/tasks/etcd_s3.yml) et [gabarit](fichiers/M18-E14/ansible/roles/rke2/templates/50-etcd-s3.yaml.j2) ; [modèle Vault](fichiers/M18-E14/ansible/inventories/lab/group_vars/all/vault-lab-s3-m18.yml.exemple) ; scripts ([`gestion-sauvegarde.sh`](fichiers/M18-E14/distributions/k3s/outils/gestion-sauvegarde.sh), [`talos/outils/etcd-instantane.sh`](fichiers/M18-E14/distributions/talos/outils/etcd-instantane.sh)) ; [RB-181](fichiers/M18-E14/medisphere/docs/kubernetes/distributions/runbooks/RB-181-restaurer-selon-distribution.md), [compte rendu](fichiers/M18-E14/medisphere/docs/kubernetes/distributions/tests/restaurations.md).

*0. Stockage objet* : comme en M14-E24, identité `etcd-m18` (lecture, écriture, liste), compartiment versionné, **politique** qui refuse la suppression et la modification du versionnage, **cycle de vie** qui purge à 14 jours (`k3s-ha/`, `rke2/`), 30 jours (`talos/`, `gestion/`). Flux `vsandbox → s3-01:8333` ouvert pour le **réseau** `vsandbox` (les nœuds sont en DHCP : pas d'adresse fixe à cibler), avec la référence de l'exercice et un rappel de fermeture au mini-projet.

*1. Cluster de gestion* (`k3s01`). La doc dit : pour SQLite, copier `/var/lib/rancher/k3s/server/db/` **et** le jeton (`/var/lib/rancher/k3s/server/token`). Le jeton sert de phrase de passe (PBKDF2) pour chiffrer les données d'amorçage (CA, clés de comptes de service) rangées dans la base : une base sans son jeton ne redémarre pas. Le script [`gestion-sauvegarde.sh`](fichiers/M18-E14/distributions/k3s/outils/gestion-sauvegarde.sh), lancé depuis `adm01` :
- arrête `k3s` sur `k3s01` (les conteneurs continuent : l'unité est en `KillMode=process`, seuls le serveur d'API et les contrôleurs, donc CAPI, s'arrêtent) ;
- archive `server/db/`, `server/token` et `server/cred/`, `server/tls/` ;
- redémarre, attend `readyz`, chiffre par `age` et envoie dans `gestion/`.

L'interruption mesurée est de l'ordre de 20 à 40 s. Pendant ce temps, `capi-essai` **continue de tourner** : un cluster de charge de travail ne dépend pas de son cluster de gestion pour fonctionner, seulement pour être modifié ou réparé. Export Cluster API :

```
admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/k3s01.kubeconfig
admin@adm01:~$ d=$(mktemp -d) && clusterctl move -n capi-essai --to-directory "$d" \
>   && tar -C "$d" -czf - . | age -R ~/src/distributions/outils/age-sauvegardes-m18.pub > capi-essai-$(date +%F).tar.gz.age \
>   && rm -rf "$d"
admin@adm01:~$ ( set -a; . ~/.config/workbook/s3-etcd-m18.env; set +a
>   aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 cp capi-essai-$(date +%F).tar.gz.age s3://etcd-m18/gestion/ )
```

`--to-directory` écrit un fichier YAML par objet : il **n'efface rien** et ne met pas en pause la source (contrairement à un `move` vers un cluster). Le dossier contient le Secret `capi-essai-proxmox` (jeton Proxmox) et le Secret `capi-essai-kubeconfig` : d'où le chiffrement immédiat et l'effacement du dossier. Si `k3s01` est perdu (RB-181 §5) :
- les VMs de `capi-essai` continuent de tourner ;
- on reconstruit un cluster de gestion par le code (VM, rôle `k3s`, `clusterctl init` avec les **mêmes** versions), puis on restaure l'archive de la base (même jeton), **ou** on fait `clusterctl move --from-directory` dans un cluster de gestion neuf ;
- tant que ce n'est pas fait, pas de mise à l'échelle, pas de réparation, pas de rotation de certificats par le KCP.

*2. k3s etcd intégré.* Banc : `k3s_ha_noeuds = ["k3s-ha01", "k3s-ha02"]`, puis le rôle `k3s` avec `k3s_role: server` et `k3s_cluster_init: true` sur `k3s-ha01`, `k3s_role: agent` et `k3s_url: https://k3s-ha01.par1.medisphere.internal:6443` sur `k3s-ha02`. Configuration S3 par un fragment `config.yaml.d/50-etcd-s3.yaml` en 600 ([gabarit](fichiers/M18-E14/ansible/roles/k3s/templates/50-etcd-s3.yaml.j2)) :
- `etcd-snapshot-schedule-cron: "0 */6 * * *"` et `etcd-snapshot-retention: 8` (local, par nœud) ;
- `etcd-s3-endpoint: s3-01.par1.medisphere.internal:8333` (hôte et port, **sans** `https://`) ;
- `etcd-s3-endpoint-ca` : la racine MédiSphère ; `etcd-s3-bucket-lookup-type: path` (le compartiment dans le chemin, pas dans le nom d'hôte, que le DNS du lab ne résout pas) ;
- `etcd-s3-folder: k3s-ha`, `etcd-s3-retention: 60`.

Purge S3 : k3s supprime dans le compartiment les instantanés au-delà de `etcd-s3-retention` (rétention **globale** au cluster). L'identité `etcd-m18` n'a pas le droit de supprimer : on fixe donc une rétention S3 plus grande que ce que le cycle de vie laisse vivre (14 jours × 4 par jour = 56 < 60), si bien que k3s n'a jamais rien à supprimer. Ce que fait k3s d'une suppression refusée (erreur journalisée seulement, ou échec de l'envoi) **n'a pas été vérifié** : regarde `journalctl -u k3s` après le 61e instantané, ou abaisse temporairement la rétention pour le voir. C'est un compromis assumé : la sauvegarde ne peut pas être effacée par un nœud compromis.

```
admin@k3s-ha01:~$ sudo k3s etcd-snapshot save --name avant-essai
admin@k3s-ha01:~$ sudo k3s etcd-snapshot ls
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/k3s-ha.kubeconfig get etcdsnapshotfile
```

`k3s etcd-snapshot ls` lit le disque local **et** S3 vus de ce nœud ; `ETCDSnapshotFile` est la vue du cluster entier, lisible à distance (c'est ce que lit le contrôle). Restauration depuis S3 (procédure « single server ») :

```
admin@k3s-ha01:~$ sudo systemctl stop k3s
admin@k3s-ha01:~$ sudo k3s server --cluster-reset --etcd-s3 --etcd-s3-endpoint s3-01.par1.medisphere.internal:8333 \
>   --etcd-s3-endpoint-ca /usr/local/share/ca-certificates/medisphere-root-ca.crt --etcd-s3-bucket etcd-m18 \
>   --etcd-s3-folder k3s-ha --etcd-s3-bucket-lookup-type path --etcd-s3-access-key <CLÉ> --etcd-s3-secret-key <SECRET> \
>   --cluster-reset-restore-path=<NOM-DE-L-INSTANTANÉ>
… Managed etcd cluster membership has been reset, restart without --cluster-reset flag now.
admin@k3s-ha01:~$ sudo systemctl start k3s
```

Les clés S3 passent ici sur la ligne de commande (visible dans `ps` le temps de la commande) : lance-la depuis un `sudo -i` avec `HISTCONTROL=ignorespace` et une espace en tête, ou lis-les depuis le fragment (`sudo k3s server --cluster-reset --config /etc/rancher/k3s/config.yaml …` relit déjà `config.yaml.d/` : seules les options absentes du fragment sont à donner). L'agent `k3s-ha02` se reconnecte seul : son jeton et la CA n'ont pas changé.

*3. RKE2.* Même fragment (`/etc/rancher/rke2/config.yaml.d/50-etcd-s3.yaml`, `etcd-s3-folder: rke2`, `etcd-s3-retention: 200` : 3 nœuds × 4 par jour × 14 jours = 168). Réponses :
- si `rke2-server` tourne encore sur `rke2-02` ou `rke2-03`, leurs membres etcd forment toujours un cluster de **deux** membres avec l'ancien état (quorum de 2 sur 3) : ils continuent d'accepter des écritures, et quand `rke2-01` redémarre seul avec l'état restauré, on a deux histoires divergentes. D'où : arrêter les trois avant de commencer ;
- arrêter le service ne suffit pas : l'unité tue `kubelet` et `containerd` à l'arrêt, mais les **conteneurs** etcd et kube-apiserver tournent encore sous leurs *shims*, ports 2379/2380 occupés. `rke2-killall.sh` (installé dans `/usr/bin/` par le paquet) arrête tout. C'est la seule commande qui interrompt les charges du nœud.

```
admin@rke2-0N:~$ sudo systemctl stop rke2-server && sudo rke2-killall.sh            # sur les trois
admin@rke2-01:~$ sudo rke2 server --cluster-reset --cluster-reset-restore-path=<NOM> --etcd-s3 …   # options S3 comme ci-dessus
admin@rke2-01:~$ sudo systemctl start rke2-server
admin@rke2-0N:~$ sudo mv /var/lib/rancher/rke2/server/db /var/lib/rancher/rke2/server/db.avant-restauration   # sur 02 et 03
admin@rke2-0N:~$ sudo systemctl start rke2-server                                  # 02, puis 03
```

La doc dit « supprimer » `server/db` sur les autres serveurs ; on le **déplace**, pour garder un retour arrière jusqu'à la vérification.

*4. Talos.*

```
admin@adm01:~$ talosctl --talosconfig ~/.config/workbook/m18/talosconfig -n 10.10.99.85 \
>   config new --roles os:etcd:backup --crt-ttl 8760h ~/.config/workbook/m18/talosconfig-sauvegarde
admin@adm01:~$ chmod 600 ~/.config/workbook/m18/talosconfig-sauvegarde
admin@adm01:~$ talosctl --talosconfig ~/.config/workbook/m18/talosconfig-sauvegarde -n 10.10.99.85 get mc
… PermissionDenied …
```

(`config new` crée un certificat client signé par l'API Talos : il faut une identité `os:admin` pour le demander. Le nouveau fichier reprend les points d'accès du contexte courant ; vérifie-les dans le fichier.) Le [script](fichiers/M18-E14/distributions/talos/outils/etcd-instantane.sh) fait l'instantané, contrôle l'empreinte avec `etcdutl snapshot status` (etcd 3.6 de Talos 1.14 ; l'outil de M14 en 3.6 lit le format), chiffre par `age` et envoie dans `talos/`. Restauration (page *Disaster Recovery* 1.14) :

```
admin@adm01:~$ export TALOSCONFIG=~/.config/workbook/m18/talosconfig
admin@adm01:~$ talosctl -n 10.10.99.85 etcd snapshot ~/talos-avant.db
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/talos.kubeconfig -n wb-essais patch configmap temoin-restauration \
>   -p '{"data":{"etat":"apres-instantane"}}'
admin@adm01:~$ talosctl -n 10.10.99.85 reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL
admin@adm01:~$ talosctl -n 10.10.99.85 service etcd          # attendre STATE Preparing
admin@adm01:~$ talosctl -n 10.10.99.85 bootstrap --recover-from=$HOME/talos-avant.db
admin@adm01:~$ talosctl -n 10.10.99.85 health --control-plane-nodes 10.10.99.85 --worker-nodes 10.10.99.86,10.10.99.87
```

La configuration de la machine est dans `STATE`, intacte : le nœud redémarre avec son identité, ses certificats et son rôle. `bootstrap --recover-from` envoie l'instantané au nœud, qui restaure etcd et le redémarre ; les travailleurs n'ont rien à faire. Le nœud `init` est obsolète et incompatible avec la restauration : vérifie par `talosctl get machinetype` que `talos-01` est `controlplane`.

*5. Comparaison* (à compléter avec tes mesures, [modèle](fichiers/M18-E14/medisphere/docs/kubernetes/distributions/tests/restaurations.md)) :

| | kubeadm (M14-E24, RB-141) | k3s | RKE2 | Talos |
|---|---|---|---|---|
| Instantané | `etcdctl snapshot save` + minuterie maison | intégré, planifié, S3 natif | intégré, planifié, S3 natif | `talosctl etcd snapshot`, planification à faire |
| Restauration | `etcdutl snapshot restore` sur **chaque** membre, manifeste etcd modifié | une option sur un serveur, les autres se vident et rejoignent | idem k3s | une commande, depuis le poste |
| Révision et identifiants | `--bump-revision`, `--mark-compacted` à la main ; identifiants recalculés | gérés par l'outil | gérés | gérés |
| À sauvegarder en plus | `/etc/kubernetes/pki` (CA, `sa.key`), configuration kubeadm, clés de chiffrement | **jeton du serveur** | **jeton du serveur** | **secrets Talos** et configurations des machines |
| Étapes manuelles (lab) | ≈ 15 | ≈ 3 | ≈ 6 (3 nœuds) | ≈ 4 |

**Explications**

Les quatre distributions sauvegardent la même chose : l'état etcd (ou SQLite), plus les **secrets qui donnent l'identité du cluster**. Ce sont eux qui manquent dans les restaurations ratées : la PKI de kubeadm, le jeton de k3s et RKE2, le paquet de secrets de Talos. k3s et RKE2 rangent la PKI **dans** la base, chiffrée par le jeton : c'est pratique (un fichier suffit), mais le jeton devient une clé maîtresse. Talos la range dans la configuration de la machine, d'où l'importance de `talos-secrets.yaml` (Vault et `~/.config/workbook/m18/`). Le cluster de gestion Cluster API ajoute une couche : perdre son état ne casse pas les clusters de charge de travail, mais en fait des orphelins que plus rien ne répare ni ne met à jour.

**Alternatives**
- Velero (M16) pour les objets applicatifs : complémentaire, ne recrée pas un plan de contrôle.
- Sauvegarde PBS des VMs : ramène un membre ancien qui se présente avec une identité existante ; à réserver à une reconstruction complète (comme RB-141 §10).
- Talos : planification par une `CronJob` (pour aller plus loin), ou Omni (offre commerciale de Sidero, hors périmètre).
- k3s sur base externe (PostgreSQL par kine) : la sauvegarde devient celle de la base, avec ses outils (CloudNativePG, M16).

**Pièges classiques**
- Restaurer k3s ou RKE2 avec un jeton différent : le serveur refuse de démarrer.
- Laisser tourner un autre serveur RKE2 (ou ses conteneurs) pendant la réinitialisation.
- Donner l'URL complète (`https://…`) à `etcd-s3-endpoint`, ou oublier `bucket-lookup-type: path`.
- Utiliser le Secret `etcd-s3-config-secret` pour la restauration : il n'est pas lu à ce moment-là.
- Réinitialiser `STATE` au lieu d'`EPHEMERAL` sur le nœud de contrôle Talos : il repart en maintenance, sans configuration.
- Garder l'export `--to-directory` en clair.

**En production chez MédiSphère**
Restauration trimestrielle chronométrée de chaque distribution retenue par l'ADR (preuve HDS), alerte sur l'âge du dernier instantané (M21), copie des archives du cluster de gestion vers PAR2, jeton des serveurs et secrets Talos dans Vault (M25).

---

### M18-E15 — Durcissement comparé

**Solution**

Fichiers : [rôle `k3s` (chiffrement)](fichiers/M18-E15/ansible/roles/k3s/defaults/main.yml.extrait), [script de preuve](fichiers/M18-E15/distributions/k3s/outils/preuve-chiffrement.sh), [lancement de kube-bench](fichiers/M18-E15/distributions/outils/kube-bench.sh), [`durcissement.md`](fichiers/M18-E15/medisphere/docs/kubernetes/distributions/durcissement.md).

*1. RKE2* :

```
admin@rke2-01:~$ ps -o user=,label=,cmd= -C etcd
etcd   system_u:system_r:container_t:s0:c…  etcd --config-file=/var/lib/rancher/rke2/server/db/etcd/config
admin@rke2-01:~$ sudo stat -c '%a %U %n' /etc/rancher/rke2/* /var/lib/rancher/rke2/agent/pod-manifests/*
admin@rke2-01:~$ sysctl vm.panic_on_oom vm.overcommit_memory kernel.panic kernel.panic_on_oops
admin@rke2-01:~$ cat /usr/share/rke2/rke2-cis-sysctl.conf
admin@rke2-01:~$ sudo grep -o 'admission-control-config-file=[^"]*' /var/lib/rancher/rke2/agent/pod-manifests/kube-apiserver.yaml
admin@rke2-01:~$ sudo cat /etc/rancher/rke2/rke2-pss.yaml
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/rke2.kubeconfig get networkpolicy -A
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/rke2.kubeconfig -n default run essai-hote --image=registry.k8s.io/pause:3.10 \
>   --overrides='{"spec":{"hostNetwork":true}}' --dry-run=server
Error from server (Forbidden): pods "essai-hote" is forbidden: violates PodSecurity "restricted:latest": host namespaces (hostNetwork=true), …
admin@rke2-01:~$ getenforce
Enforcing
```

Le nom exact du fichier PSA (`rke2-pss.yaml`) est celui de la doc RKE2 actuelle, **à vérifier sur ta version** (le serveur d'API le désigne, c'est la source de vérité). Exemptions : `kube-system`, `compliance-operator-system`, `tigera-operator`. Les NetworkPolicy posées par le profil limitent `kube-system`, `kube-public` et `default` au trafic interne à l'espace (exceptions DNS, métriques, webhooks).

*2. kube-bench* : [script](fichiers/M18-E15/distributions/outils/kube-bench.sh). L'archive 0.16.0 contient au plus `rke2-cis-1.9` (et les variantes plus anciennes), `k3s-cis-1.9`, et le générique `cis-1.12` (Kubernetes 1.32 à 1.34) : **aucun référentiel ne couvre 1.36**. kube-bench refuse de deviner (`--version 1.36` ne correspond à rien) : on force `--benchmark`. Ce qu'on observe en général, à confirmer par ton propre classement :
- avec `rke2-cis-1.9`, la plupart des contrôles passent ; restent des WARN « manuels » (politiques, RBAC, Secrets en variables) et quelques FAIL liés à des arguments que RKE2 fixe autrement (ex. chemins de fichiers de configuration du kubelet) ;
- avec `cis-1.12` générique, beaucoup de FAIL de **chemin** : les contrôles cherchent `/etc/kubernetes/manifests/…`, qui n'existe pas sur RKE2. Ce sont des faux positifs, pas des écarts : un rapport kube-bench ne se lit jamais sans son référentiel.

*3. Talos* :

```
admin@adm01:~$ export TALOSCONFIG=~/.config/workbook/m18/talosconfig
admin@adm01:~$ talosctl -n 10.10.99.85 netstat -l -t -u -p
admin@adm01:~$ talosctl -n 10.10.99.85 service
admin@adm01:~$ talosctl -n 10.10.99.85 processes
admin@adm01:~$ talosctl -n 10.10.99.85 mounts | grep -E ' / |squashfs'
admin@adm01:~$ talosctl -n 10.10.99.85 read /proc/cmdline
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/talos.kubeconfig -n default run essai-priv --image=registry.k8s.io/pause:3.10 \
>   --overrides='{"spec":{"containers":[{"name":"essai-priv","image":"registry.k8s.io/pause:3.10","securityContext":{"privileged":true}}]}}' \
>   --dry-run=server
Error from server (Forbidden): … violates PodSecurity "baseline:latest": privileged …
```

Observations attendues :
- ports : 50000 (`apid`), 50001 (`trustd`, nœuds de contrôle), 6443, 2379-2380, 10250, ports du CNI ; **pas** de 22 ;
- services du système : une poignée (`apid`, `machined`, `trustd`, `containerd`, `cri`, `etcd`, `kubelet`, `udevd`, plus l'extension `qemu-guest-agent`), pas de gestionnaire de paquets, pas de shell ;
- racine en SquashFS en lecture seule ; noyau avec les réglages KSPP (`init_on_alloc`, `slab_nomerge`, `pti=on`…) dans `/proc/cmdline` ;
- rôles de l'API : `os:admin`, `os:operator`, `os:reader`, `os:etcd:backup` ;
- Pod Security : `baseline` imposé, `restricted` en audit et avertissement, par la configuration d'admission que Talos génère.

kube-bench sur Talos : il lui faut un pod privilégié avec `hostPID` et les dossiers de l'hôte montés, donc un espace exempté de la politique `baseline` : le lancer, c'est déjà affaiblir le cluster. Et ses contrôles de fichiers visent des chemins (`/etc/kubernetes/…`) qui n'existent pas sous Talos. Résultat attendu : beaucoup de FAIL de chemin, peu d'information. La bonne preuve, pour Talos, est l'inventaire ci-dessus et la configuration du serveur d'API.

*4. k3s01* :

```
admin@k3s01:~$ sudo k3s secrets-encrypt status
Encryption Status: Disabled, no configuration file found
admin@k3s01:~$ sudo k3s secrets-encrypt enable
```

puis `k3s_secrets_encryption: true` dans le rôle (qui ajoute `secrets-encryption: true` au fichier de configuration), application, redémarrage par le gestionnaire du rôle, `sudo k3s secrets-encrypt rotate-keys`, second redémarrage, et :

```
admin@k3s01:~$ sudo k3s secrets-encrypt status
Encryption Status: Enabled
Current Rotation Stage: reencrypt_finished
Server Encryption Hashes: All hashes match
```

La procédure sur un cluster existant n'existe qu'à partir des versions de mars 2026 (v1.33.10, v1.34.6, v1.35.3) : la 1.36.5 l'a. Preuve : [`preuve-chiffrement.sh`](fichiers/M18-E15/distributions/k3s/outils/preuve-chiffrement.sh) copie la base à chaud avec `sqlite3 .backup` (cohérent, sans arrêter k3s), lit la valeur de `/registry/secrets/capi-essai/capi-essai-proxmox` dans la table `kine` et n'affiche que ses 20 premiers octets : `k8s:enc:aescbc:v1:…` (ou `secretbox`). Avant le chiffrement, on y voyait `k8s\0` suivi du protobuf, où le jeton se lisait avec `strings`. Le script efface la copie.

*5. Tableau* : [modèle](fichiers/M18-E15/medisphere/docs/kubernetes/distributions/durcissement.md).

**Explications**

Trois approches du durcissement. RKE2 applique un **profil** : il règle Kubernetes selon le CIS et vérifie l'hôte au démarrage, mais l'OS reste un Linux généraliste (SSH, paquets, comptes) à durcir à part. Talos réduit la **surface** : rien à durcir sur l'OS parce qu'il n'y a presque rien, et la gestion passe par une API à TLS mutuel et rôles. k3s et kubeadm fournissent les réglages, pas les choix : c'est à toi de les faire, avec un guide (k3s a son propre *CIS Hardening Guide*). Aucun des trois ne remplace l'admission (M26 : Kyverno), la détection (Falco, Tetragon) ni l'identité (M24).

**Alternatives**
- `compliance-operator` de Rancher (CIS par kube-bench dans le cluster, rapports CRD) pour RKE2 ; Kubescape (M26) pour une vue plus large que le CIS.
- Pour k3s, le guide de durcissement de k3s (paramètres noyau, PSA, audit, NetworkPolicy) plutôt qu'un profil.

**Pièges classiques**
- Lire un FAIL sans regarder la commande d'audit du contrôle.
- Croire qu'un profil CIS durcit l'OS.
- Chiffrer les Secrets de k3s sans les redémarrages de la procédure, ou sur un cluster sans sauvegarde.
- Prouver le chiffrement en interrogeant la base vivante en écriture (risque de verrou ou de corruption) : toujours une copie.

**En production chez MédiSphère**
Passages de kube-bench automatisés et versionnés avec leur référentiel (M26), exceptions écrites et revues, chiffrement des Secrets par KMS avec Vault (M25), surveillance de la dérive des réglages (M21).

---

### M18-E16 — Cluster API sur OpenStack (facultatif)

**Solution**

Fichiers : [manifestes `capo-essai`](fichiers/M18-E16/distributions/capi/capo-essai/), [configuration kind du cluster de gestion éphémère](fichiers/M18-E16/distributions/kind/gestion-capo.yaml), [extrait pare-feu](fichiers/M18-E16/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [`capo.md`](fichiers/M18-E16/medisphere/docs/kubernetes/distributions/capo.md).

*Compatibilité* (lue au tag v0.15.0) :
- le README ne liste la 0.15 nulle part : sa matrice s'arrête à « v0.14 → CAPI ≥ v1.12 » ;
- `metadata.yaml` déclare le contrat `v1beta2` pour la 0.15 (comme CAPI 1.12) ;
- `go.mod` importe `sigs.k8s.io/cluster-api v1.14.1` (la 0.14 importait v1.12.1).

`clusterctl` 1.12 accepterait donc d'installer CAPO 0.15 (même contrat), mais le fournisseur a été construit et testé contre CAPI 1.14 : rien ne garantit qu'il fonctionne avec un *core* 1.12, et `k3s01` ne peut pas passer en 1.14 à cause de CAPMOX (≤ 1.12). Deux choix défendables :
- **retenu ici** : un cluster de gestion **éphémère** kind sur `m18-dev01`, avec Cluster API **1.14.x** et CAPO **0.15.x**, détruit après l'essai ;
- ou CAPO **0.14.x** dans `k3s01` (annoncé pour CAPI ≥ 1.12), en assumant l'écart avec la version du PLAN.

C'est un vrai résultat pour l'ADR : deux fournisseurs dans un même cluster de gestion lient leurs versions, et un fournisseur en retard (CAPMOX) bloque tous les autres.

*Construction* (résumé ; les étapes de M10 et E09 sont réutilisées) :
1. Profil openstack reconstruit (`task openstack:deployer` du M10), compte de service `svc-capi` du projet `plateforme` avec le rôle `member` (CAPO crée réseaux, ports, groupes de sécurité, serveurs, IP flottantes, répartiteurs : `member` suffit), `clouds.yaml` restreint en 600 sur `m18-dev01`.
2. Image : `make build-qemu-ubuntu-2404` dans image-builder (mêmes variables Kubernetes que 9061), puis `openstack image create --disk-format qcow2 --file … ubuntu-2404-kube-v1.36.5` dans le projet `plateforme`.
3. Cluster de gestion : `kind create cluster --config kind/gestion-capo.yaml` (image `kindest/node` 1.36), `clusterctl` 1.14 ; `clusterctl init --infrastructure openstack:v0.15.x` ; CAPO demande aussi l'ORC (*OpenStack Resource Controller*) à partir de la 0.12 pour les images : vérifie la page *Getting started* de ta version.
4. Manifestes, en API **`infrastructure.cluster.x-k8s.io/v1beta2`** (version stockée des CRD de CAPO 0.15, celle de son contrat ; la `v1beta1` est encore servie mais ses champs diffèrent) : Secret `capo-essai-cloud-config` (`clouds.yaml` + CA MédiSphère), référencé par `identityRef` (`type: Secret`, `cloudName`, `name`) ; `OpenStackCluster` avec `externalNetwork.filter.name: ext-net`, `managedSubnets` (réseau créé par CAPO, 10.6.0.0/24), `apiServer.floatingIP` choisie dans 10.10.52.200-249 et **pas** de `apiServer.managedLoadBalancer` (aucun répartiteur), `managedSecurityGroups` ; `OpenStackMachineTemplate` (`flavor.filter.name: m1.medium`, `image.filter.name`, clé SSH) ; KCP et MD comme pour CAPMOX ; Cilium par `ClusterResourceSet`. Les noms de champs de la [solution](fichiers/M18-E16/distributions/capi/capo-essai/) ont été validés contre les CRD de `infrastructure-components.yaml` v0.15.0 ; relis quand même `kubectl explain openstackcluster.spec --api-version=infrastructure.cluster.x-k8s.io/v1beta2` sur ton cluster de gestion.
   Les kubelets sont lancés avec `cloud-provider: external` (gabarits de CAPO) : il faut donc **installer l'OpenStack Cloud Controller Manager** (projet `cloud-provider-openstack`, chart `openstack-cloud-controller-manager`, à une version qui suit Kubernetes 1.36) dans `capo-essai`, avec un Secret `cloud-config` qui reprend le compte `svc-capi`. Sans lui, les nœuds gardent la taint `node.cloudprovider.kubernetes.io/uninitialized` (ni adresses ni étiquettes de zone posées par le cloud) et CoreDNS reste `Pending` : le cluster ne devient jamais sain. On l'applique par un second `ClusterResourceSet` (ou par Helm une fois l'API joignable). *À vérifier sur ton lab* : version du chart et contenu exact de `cloud.conf`.
5. IP flottante simple plutôt qu'Octavia : un seul nœud de contrôle, pas de répartition à faire ; Octavia (fournisseur OVN) ajoute un répartiteur par cluster et allonge la création de plusieurs minutes. Avec trois nœuds de contrôle, Octavia devient la bonne réponse (pas de kube-vip à gérer).
6. Flux ouverts (extrait) : `vsandbox` → 10.10.50.201 TCP 443 (API publiques derrière HAProxy de Kolla : Keystone, Nova, Neutron, Glance, Octavia en HTTPS) et → 10.10.52.200-249 TCP 6443 (API du cluster de charge de travail).
7. Suppression : `kubectl delete cluster capo-essai` (jamais les serveurs à la main : CAPO supprimerait ensuite des ressources déjà absentes et bloquerait sur ses finaliseurs), puis `openstack server list`, `port list`, `security group list`, `floating ip list`, `loadbalancer list` filtrés sur `capo-essai`, tous vides. Puis `kind delete cluster --name gestion-capo`.

**Explications**

CAPO délègue au cloud ce que CAPMOX doit faire lui-même ou faire faire par d'autres : réseau et sous-réseau (Neutron) au lieu d'un VNet et d'un pool IPAM *in-cluster* ; point d'accès de l'API par IP flottante ou répartiteur Octavia au lieu de kube-vip ; groupes de sécurité au lieu du pare-feu Proxmox ; images Glance au lieu de templates ; identité par projet Keystone au lieu d'un jeton à pool. C'est ce qui fait d'OpenStack un meilleur socle pour Cluster API quand on veut beaucoup de clusters : le cloud fournit les primitives, le fournisseur les orchestre.

**Pièges classiques**
- Installer CAPO dans le cluster de gestion de CAPMOX sans lire les versions : contrôleurs qui redémarrent en boucle ou webhooks incompatibles.
- Un `clouds.yaml` avec le compte `admin`.
- Supprimer les serveurs dans Horizon plutôt que le `Cluster`.
- Oublier l'ouverture de 6443 vers les IP flottantes : le cluster de gestion ne voit jamais le nœud de contrôle et le KCP reste bloqué.
- `cloud-provider: external` sans cloud controller manager : nœuds marqués par la taint `uninitialized`, CoreDNS `Pending`, cluster jamais sain.
- Recopier un exemple CAPO en `v1beta1` (`apiServerFloatingIP`, `flavor: m1.medium`) : refusé ou converti sans que tu relises les champs de la `v1beta2`.

**En production chez MédiSphère**
Si OpenStack devient le socle des clusters des équipes : `ClusterClass` par gabarit, un compte de service par projet, Octavia pour les points d'accès, cluster de gestion dédié et sauvegardé, versions de fournisseurs suivies par Renovate (M13).

---

### M18-E17 — ADR : stratégie de distribution de MédiSphère

**Proposition de solution** : [ADR-0180](fichiers/M18-E17/medisphere/docs/kubernetes/distributions/adr/ADR-0180-strategie-distribution.md). Ce n'est pas **la** réponse : une autre décision bien argumentée sur tes mesures vaut autant. La proposition retient :
- **production** (`k8s-par1`) : kubeadm + Ansible, **sans changement** pendant la durée du workbook. ADR-0140 et ADR-0141 restent valables, le savoir-faire est acquis, les runbooks existent. RKE2 est réexaminé à la prochaine refonte (critère : effort de durcissement mesuré au M26) ;
- **agence de Lyon** : **k3s** (empreinte, binaire unique, etcd intégré à trois nœuds, montée de version par system-upgrade-controller, sauvegarde S3 native) ; Talos en option si l'agence n'a vraiment personne (pas de SSH, mais aussi pas de dépannage sans `talosctl`) ;
- **recettes éphémères** : **k3d** sur une VM partagée pour la journée (E18 : quelques minutes), Cluster API réservé à des clusters de recette **sur VMs** qui doivent ressembler à la production. Cluster API n'est **pas** retenu pour la production à ce stade : CAPMOX est en 0.x, non documenté sur Proxmox VE 9, et lie les versions de Cluster API (E16) ;
- fin de module : template 9060/9061 **supprimés** (reconstructibles par le code), compte `wb-capi` **supprimé** (recréé par le code de M18-E08 si l'ADR est révisé), `k3s01` détruit.

**Grille d'auto-évaluation** (sur 20)

| Critère | Points |
|---|---|
| Contexte complet : trois besoins, contraintes HDS et souveraineté, existant (ADR-0140/0141) | 3 |
| Critères pondérés, chaque note sourcée par un exercice ou une mesure | 4 |
| Au moins quatre options par besoin, distribution et outil de cycle de vie séparés | 3 |
| Décision par besoin, formulée comme une règle applicable | 3 |
| Sort de `k8s-par1`, du cluster de gestion (et de sa sauvegarde), du template, de `wb-capi` | 2 |
| Conséquences négatives rattachées à un module ou datées | 3 |
| Critères de réexamen | 1 |
| Trois pages au plus, gabarit respecté | 1 |

**Pièges classiques**
- Comparer « Cluster API » et « k3s » comme deux distributions.
- Retenir Talos sans dire qui fera l'astreinte d'un système sans SSH.
- Oublier que le cluster de gestion est un cluster de plus, avec ses sauvegardes et sa supervision.
- Un tableau sans source (« RKE2 est plus sûr »).

---

### M18-E18 — Un cluster de recette éphémère en temps limité

Le `CHRONO` n'a pas de corrigé à suivre pas à pas : voici une solution de référence pour **après** l'exercice. Fichiers : [configuration k3d](fichiers/M18-E18/distributions/k3d/recette-mediagenda.yaml), [miroirs k3s](fichiers/M18-E18/distributions/k3d/registries.yaml), [valeurs](fichiers/M18-E18/distributions/k3d/recette-mediagenda-values.yaml), [Taskfile](fichiers/M18-E18/distributions/Taskfile.yml), [script](fichiers/M18-E18/distributions/k3d/outils/recette.sh).

**Choix de l'outil** : k3d sur `m18-dev01`. Création en une à deux minutes, aucune VMID ni adresse du VLAN 40 consommée, destruction instantanée. Cluster API (création d'une VM par nœud, 8 à 15 min) se justifierait si l'équipe devait tester le comportement sur des nœuds réels (stockage, réseau, panne de nœud).

**Déroulé de référence** (temps observés attendus : T1 ≈ 3 min, T2 ≈ 5 min, T3 ≈ 10 min, T4 ≈ 15 à 25 min) :
1. `task recette:creer` lance [`recette.sh creer`](fichiers/M18-E18/distributions/k3d/outils/recette.sh) depuis `adm01`. Le script :
   - copie la configuration et les miroirs sur `m18-dev01` et y lance `k3d cluster create --config` ;
   - récupère le kubeconfig en 600 (point d'accès réécrit vers `m18-dev01.par1.medisphere.internal`) ;
   - installe l'opérateur CloudNativePG (même version de chart que le Helmfile de `plateforme/k8s`, par le cache Harbor) ;
   - crée l'espace étiqueté et le Secret `harbor-pull` depuis `harbor-k8s-pull.env` ;
   - vérifie la signature du chart (`cosign verify --key ~/medisphere/docs/registre/cosign.pub --insecure-ignore-tlog=true` sur le digest), puis installe la release.
2. Image de k3s par le cache Harbor : `image: registry.par1.medisphere.internal/dockerhub/rancher/k3s:v1.36.5-k3s1` dans la configuration k3d. Le démon Docker de `m18-dev01` doit faire confiance à la CA MédiSphère (`/etc/docker/certs.d/registry.par1.medisphere.internal/ca.crt`, rôle `docker_engine` du M12).
3. Images des pods par les miroirs de k3s (`registries.yaml` monté par k3d) : `docker.io` → cache `dockerhub`, `ghcr.io` → cache `ghcr`, `registry.k8s.io` → cache `k8s`, avec la CA (montée dans les nœuds par `volumes`).
4. Valeurs : `medisphere.environnement: recette`, `httpRoute.enabled: false`, `networkPolicy.enabled: false`, `service.type: LoadBalancer`, `postgresql.cnpg.enabled: true` avec `storageClass: local-path`, `valkey.enabled: true`. Pour les politiques réseau : Flannel, le CNI de k3s, ne les applique pas, mais k3s embarque un contrôleur de NetworkPolicy (kube-router) qui, lui, les applique. Les `NetworkPolicy` standard du chart n'autorisent l'entrée que depuis la Gateway de `k8s-par1` (espace `passerelles`) : sur k3d, elles bloqueraient le trafic venu de ServiceLB. On les désactive et on l'écrit dans le retour d'expérience ; les `CiliumNetworkPolicy`, elles, feraient échouer l'installation (CRD absent).
5. Accès : ServiceLB de k3s sur le port 8000 du nœud, publié par le répartiteur de k3d sur le port **8080** de `m18-dev01` (`ports: 8080:8000@loadbalancer`).

Points de contrôle de T4 : voir `lab/bin/check 18 18`. T5 : `task recette:detruire` (`k3d cluster delete`, suppression du kubeconfig) ; quelques secondes.

**Pièges classiques**
- k3d 5.9 sans `--image` : k3s du canal stable au moment de la compilation de k3d (pas 1.36.5).
- Oublier la CA dans les nœuds k3d : `x509: certificate signed by unknown authority` au tirage par le cache.
- Garder `networkPolicy.enabled: true` : les `CiliumNetworkPolicy` n'ont pas de CRD (échec de l'installation) et les `NetworkPolicy` standard, appliquées par le contrôleur intégré de k3s, coupent l'accès par ServiceLB.
- Le stockage `ceph-rbd` des valeurs par défaut : le `Cluster` CloudNativePG reste `Pending` (PVC sans classe).
- Installer avant d'avoir vérifié la signature.

**Retour d'expérience attendu** : le temps passe dans les tirages d'images (premier passage) et l'opérateur CNPG ; cinq équipes le même jour tiennent sur `m18-dev01` en mémoire (≈ 1,5 Go par cluster) mais pas en ports publiés sans convention (un port par équipe) ni en contrôle d'accès (tout le monde est administrateur de son cluster et de la VM). Pour que Julien le fasse seul : un pipeline (M19) ou une `ApplicationSet` (M20), et à terme vCluster (M28), qui donne un cluster virtuel dans `k8s-par1` sans VM.
