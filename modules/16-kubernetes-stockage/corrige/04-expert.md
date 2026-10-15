# Module 16 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Avec le stockage, « j'ai supprimé le pod et ça remarche » est doublement faux : la suppression efface la preuve (événements, état de l'attachement) et peut aggraver la situation (un second nœud qui monte le même volume, une base qui bascule sur une réplique en retard).

Les scripts d'injection sont dans `corrige/pannes/` (`_m16-commun.sh` contient les fonctions partagées : sauvegarde et restauration ciblées des objets Kubernetes, commandes `ceph` sur le nœud admin, témoins, contrôle de santé avant injection). Chaque objet Kubernetes modifié est sauvegardé sur `adm01` dans `~/.local/state/workbook/k8s/M16-EXX/` (fichiers 600), chaque modification d'hôte est journalisée dans `/var/lib/workbook/pannes.log` de l'hôte, et l'heure de chaque injection est notée dans `~/.local/state/workbook/m16-injections/` : les contrôles s'en servent pour exiger une preuve **postérieure** à l'incident (une sauvegarde, une bascule, un instantané).

Les sorties reproduites sont **représentatives** : noms d'objets, identifiants, durées et formulations exactes varient selon ton cluster et les versions. Elles suivent la documentation de Kubernetes 1.36, ceph-csi 3.18.1, external-snapshotter 8.6, Velero 1.18 (plugin AWS 1.14), CloudNativePG 1.30 et du plugin Barman Cloud 0.15, et les fichiers de solution des paliers précédents (`fichiers/M16-E06`, `E07`, `E16`, `E18`, `E19`).

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- Ensemble des scripts de panne : écrits contre les manifestes et chartes de référence (rendu `helm template` de `ceph-csi-rbd` 3.18.1, manifestes d'external-snapshotter 8.6.0, CRD du plugin Barman Cloud 0.15.1), validés par `shellcheck` et `kubeconform`, mais **pas exécutés sur un cluster**. La restauration ciblée (`m16_restaurer`) passe par `kubectl create --dry-run=client --validate=false -o json`, qui a besoin de l'API du cluster pour reconnaître le type.
- E35 v3 : formulation exacte du refus par le quota (`exceeded quota` ou `status unknown for quota` pendant les premières secondes).
- E36 v1 : code d'erreur exact de `rbd map` avec une mauvaise clé (`(1) Operation not permitted` attendu, avec `libceph: … auth … error` dans `dmesg`) ; v2 : la table nftables ajoutée cohabite avec les règles de Cilium (`kubeProxyReplacement`) sans effet de bord ; v3 : étiquette `medisphere.internal/stockage-ceph` posée par le rôle de M16-E05 et lue par les valeurs de M16-E06.
- E37 : délai de détachement forcé du contrôleur attach/detach en 1.36 (`--disable-force-detach-on-timeout`, valeur par défaut à lire dans `kube-controller-manager --help`) ; nom du conteneur du témoin pour `crictl`.
- E38 v3 : syntaxe `ceph auth rotate --key-type=aes256k` (reprise du corrigé M08-E27) et longueur des clés `aes256k` ; v2 : comportement de ceph-csi quand la création d'image attend un pool plein (délai dépassé puis `Aborted` attendus).
- E39 v1 : délai de prise en compte par Velero d'un Secret modifié (propagation du volume monté par le kubelet, puis validation de l'emplacement) ; étiquette `name=node-agent` des pods du DaemonSet.
- E40 v3 : acceptation par le webhook de CloudNativePG de `synchronous.number: 2` avec 3 instances, et rechargement de `synchronous_standby_names` sans redémarrage ; v2 : effet de la clôture d'une réplique sur la réplication synchrone `dataDurability: required`.
- E41 : relecture par le conteneur auxiliaire du plugin d'un `ObjectStore` ou d'un Secret modifié sans redémarrage du pod (attendue d'après la documentation du plugin) ; nom du conteneur auxiliaire (`plugin-barman-cloud` dans les versions lues).
- E42 v2 : recréation d'une `VolumeSnapshotClass` et reprise automatique d'un `VolumeSnapshotContent` en erreur après correction ; étiquette `app.kubernetes.io/name=snapshot-controller` des pods du contrôleur.
- E44 : empreinte SHA-256 du `volumeHandle` dans le chemin `globalmount` (Kubernetes ≥ 1.25 environ) ; présence d'un `VolumeAttachment` pour CephFS (le CSIDriver du chart 3.18.1 déclare `attachRequired: true`).

---

## Méthode commune aux pannes de stockage dans Kubernetes

1. **Lire les événements de chaque objet de la chaîne**, dans l'ordre : contrôleur (StatefulSet, Deployment) → pod → PVC → PV → VolumeAttachment → VolumeSnapshot/Content. Chaque contrôleur écrit ses échecs sur l'objet qu'il traite ; c'est presque toujours la phrase de l'événement qui désigne l'étage.
2. **Situer l'étage et son composant** : admission (quotas, politiques) ; planification (sélecteurs, teintes, anti-affinités, topologie) ; provisionnement (`csi-provisioner` + `csi-rbdplugin` du provisioner *leader*) ; attachement (contrôleur attach/detach de `kube-controller-manager`, `csi-attacher`) ; montage (kubelet du nœud, `csi-rbdplugin` du *nodeplugin* **de ce nœud**) ; stockage (`ceph-par1` vu par `client.k8s`, `s3-01` vu par `velero` ou `cnpg`). Pour la base : Cluster CloudNativePG → instance → PostgreSQL (`pg_stat_replication`, `pg_stat_archiver`) → conteneur du plugin → S3.
3. **Chercher ce qui a bougé** : journal d'audit de Kubernetes (M14-E27, `/var/log/kubernetes/audit/` sur les nœuds de contrôle : `verb`, `objectRef`, `user.username`), journal d'audit de Ceph (`ceph log last 200 debug audit`), différence avec le code (`kubectl diff -f`, `helm diff` si installé, ou `helm get values` comparé aux valeurs de `plateforme/k8s`), outils de vérification des paliers précédents (`outils/ceph-csi-secrets.sh verifier`, `outils/ceph-allocations.sh verifier`).
4. **Protéger avant d'agir** : jamais deux écrivains sur un volume RWO ; pour la base, savoir quelle est la dernière transaction archivée hors du cluster avant de toucher à quoi que ce soit.
5. **Corriger à la racine, puis faire converger le code** : une valeur Helm, une classe, un Secret recréé depuis Vault, une identité Ceph réalignée sur `allocations.yaml`. Une réparation à chaud non reportée revient au prochain `task appliquer` — ou la panne revient.
6. **Prévenir** : quel contrôle de `ms-verif-k8s-stockage` (M16-E27), quelle étape de pipeline, quelle règle d'admission aurait vu la panne avant l'utilisateur ?

---

### M16-E35 — Panne : le PVC reste Pending

**Démarche de diagnostic**

*Symptômes* : `temoin-e35` à 0/1. Variantes 1, 2 et 4 : un PVC `donnees-temoin-e35-0` en `Pending`, un pod en `Pending` (« pod has unbound immediate PersistentVolumeClaims »). Variante 3 : ni PVC ni pod.

*Hypothèses* : classe nommée inexistante ; pas de classe du tout (ni nommée, ni par défaut) ; création du PVC refusée par l'admission (quota) ; provisioner absent ou qui ne voit pas le PVC ; pilote qui échoue (traité en E38).

**Étape 1 — Les objets et leurs événements.**

```
admin@adm01:~$ kubectl get sts,pod,pvc -n wb-essais -l app.kubernetes.io/name=temoin-e35
admin@adm01:~$ kubectl describe sts temoin-e35 -n wb-essais | sed -n '/Events/,$p'
admin@adm01:~$ kubectl describe pvc donnees-temoin-e35-0 -n wb-essais | sed -n '/Events/,$p'
```

L'étape 2 du travail (un PVC de 1 Gio créé à la main sans classe, puis avec `storageClassName: ceph-rbd`) sépare tout de suite « problème du manifeste » et « problème du cluster ».

**Variante 1 — classe inexistante.**

```
Events:
  Warning  ProvisioningFailed  persistentvolume-controller  storageclass.storage.k8s.io "ceph-rbd-ssd" not found
admin@adm01:~$ kubectl get storageclass
NAME                 PROVISIONER           RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION
ceph-rbd (default)   rbd.csi.ceph.com      Delete          Immediate           true
ceph-rbd-retain      rbd.csi.ceph.com      Retain          Immediate           true
cephfs               cephfs.csi.ceph.com   Delete          Immediate           true
```

Le manifeste vient d'un autre cluster (InfoGér nommait ses classes par type de disque). Le PVC à la main avec `ceph-rbd` se lie : le cluster va bien. Correctif : la classe d'un `volumeClaimTemplates` est immuable, il faut recréer le StatefulSet.

```
admin@adm01:~$ kubectl get sts temoin-e35 -n wb-essais -o yaml > temoin-e35.yaml   # puis corriger storageClassName, retirer status/uid/resourceVersion
admin@adm01:~$ kubectl delete sts temoin-e35 -n wb-essais
admin@adm01:~$ kubectl delete pvc donnees-temoin-e35-0 -n wb-essais                # Pending : aucun volume derrière, aucune donnée
admin@adm01:~$ kubectl apply -f temoin-e35.yaml
```

Avant de supprimer un PVC, vérifie toujours qu'il n'est **pas** `Bound` : un PVC lié porte des données, et `reclaimPolicy: Delete` les effacerait. Le correctif durable est dans le dépôt de l'équipe de Julien (classe `ceph-rbd`, ou pas de classe du tout pour hériter de la classe par défaut).

**Variante 2 — plus de classe par défaut.**

```
Events:
  Normal   FailedBinding  persistentvolume-controller  no persistent volumes available for this claim and no storage class is set
admin@adm01:~$ kubectl get storageclass            # plus aucune « (default) »
admin@adm01:~$ kubectl get sc ceph-rbd -o jsonpath='{.metadata.annotations}'
{"storageclass.kubernetes.io/is-default-class":"false", …}
```

Le gabarit ne nomme pas de classe (c'est voulu : il hérite de la classe par défaut). Quelqu'un a passé l'annotation à `false` (journal d'audit : `verb: patch`, `objectRef.resource: storageclasses`, l'utilisateur). Correctif : réappliquer la classe **depuis le code** (`composants/ceph-csi/classes/ceph-rbd.yaml` porte l'annotation à `"true"`, M16-E06) :

```
admin@adm01:~/src/k8s$ kubectl apply -f composants/ceph-csi/classes/ceph-rbd.yaml      # ou : task appliquer
admin@adm01:~$ kubectl get pvc -n wb-essais -w     # donnees-temoin-e35-0 reçoit la classe et se lie seul
```

Depuis Kubernetes 1.28, l'attribution rétroactive de la classe par défaut fait le reste : rien à recréer.

**Variante 3 — quota.**

```
admin@adm01:~$ kubectl get pvc -n wb-essais -l app.kubernetes.io/name=temoin-e35    # rien
Events (StatefulSet):
  Warning  FailedCreate  statefulset-controller  create Claim donnees-temoin-e35-0 for Pod temoin-e35-0 in StatefulSet
           temoin-e35 failed error: persistentvolumeclaims "donnees-temoin-e35-0" is forbidden: exceeded quota:
           stockage-equipe, requested: ceph-rbd.storageclass.storage.k8s.io/persistentvolumeclaims=1,
           used: ceph-rbd.storageclass.storage.k8s.io/persistentvolumeclaims=1, limited: …=1
admin@adm01:~$ kubectl get resourcequota -n wb-essais stockage-equipe -o yaml
```

Le quota (annotation « CHG-1735 plafond provisoire ») n'est pas dans `plateforme/k8s/espaces/` : il a été posé à la main. Il plafonne le **nombre** de PVC de la classe au nombre existant. Correctif : selon la décision d'équipe, le supprimer ou le remplacer par le quota décrit dans le code (M16-E20 : capacité par classe, pas un nombre figé), par MR puis `task appliquer`. Le contrôleur de StatefulSet réessaie (avec un délai croissant) : le PVC puis le pod apparaissent sans autre action.

**Variante 4 — provisioner arrêté.**

```
Events:
  Normal  ExternalProvisioning  persistentvolume-controller  Waiting for a volume to be created either by the external
          provisioner 'rbd.csi.ceph.com' or manually by the system administrator. If volume creation is delayed, please
          verify that the provisioner is running and correctly registered.
admin@adm01:~$ kubectl get deploy -n ceph-csi
NAME                          READY   UP-TO-DATE   AVAILABLE
ceph-csi-rbd-provisioner      0/0     0            0
ceph-csi-cephfs-provisioner   2/2     2            2
```

`0/0` (et non `0/2`) : ce n'est pas une panne de pod, quelqu'un a mis le Deployment à zéro (audit : `verb: patch` ou `update` sur `deployments/scale`). Correctif par le code : `helm upgrade` de la release `ceph-csi-rbd` avec `composants/ceph-csi/values-rbd.yaml` (`provisioner.replicaCount: 2`, M16-E06), ou `task appliquer`. Un `kubectl scale --replicas=2` rétablit le service tout de suite mais doit rester identique aux valeurs.

**Clôture commune** : `lab/bin/break 16 35 --annuler` (supprime `temoin-e35`, objet de test), puis `lab/bin/check 16 35`. RB-160 complété (une section par cause, avec la phrase exacte de l'événement).

**Explications**

Un PVC dynamique traverse quatre décisions : l'admission (quotas, politiques) décide qu'il **existe** ; le contrôleur de volumes persistants (`persistentvolume-controller` de `kube-controller-manager`) décide de **sa classe** et délègue au provisioner externe dont le nom figure dans la classe ; le sidecar `csi-provisioner` du pilote (un seul *leader*) appelle `CreateVolume` ; le contrôleur lie le PV créé au PVC. Chaque décision écrit sur un objet différent : quota → StatefulSet (le PVC n'existe pas), classe → PVC, provisioner → PVC (rien dans ses journaux s'il ne tourne pas), pilote → PVC (`ProvisioningFailed` avec le message du pilote). Dans un StatefulSet, les PVC des `volumeClaimTemplates` sont créés par le contrôleur de StatefulSet avant le pod, ne sont jamais modifiés ensuite, et ne sont supprimés que si `persistentVolumeClaimRetentionPolicy` le demande.

**Alternatives**
- Pour la variante 1, `kubectl delete sts --cascade=orphan` garde le pod pendant la recréation : utile pour une application en service, inutile ici (le pod est `Pending`).
- Une `ValidatingAdmissionPolicy` qui refuse un PVC dont la classe n'existe pas ou n'est pas autorisée à l'espace (M16-E20) aurait transformé la panne 1 en refus immédiat et explicite au déploiement.

**Pièges classiques**
- Supprimer un PVC `Bound` « pour le recréer avec la bonne classe » : avec `reclaimPolicy: Delete`, les données partent avec lui.
- Mettre une seconde classe par défaut pour « débloquer » : Kubernetes accepte plusieurs classes par défaut et choisit la plus récente, source de surprises durables.
- Chercher dans les journaux du provisioner un PVC qu'il n'a jamais vu (quota, classe inexistante) : silence n'est pas santé.
- Relancer les pods du provisioner sans regarder `0/0` : un Deployment à zéro ne crée aucun pod à relancer.

**En production chez MédiSphère**
Sonde `ms-verif-k8s-stockage` : PVC `Pending` depuis plus de 5 min (déjà au M16-E27), exactement une classe par défaut, répliques du provisioner égales aux valeurs. Classe par défaut et quotas uniquement par `plateforme/k8s` (GitOps au M20 : une modification à la main serait annulée et signalée). Admission : liste des classes autorisées par espace.

---

### M16-E36 — Panne : le pod reste en ContainerCreating

**Démarche de diagnostic**

*Symptômes* : PVC `temoin-e36` `Bound`, pod planifié sur le nœud demandé (appelé `k8s-w0N` ci-dessous), conteneur en attente `ContainerCreating`. Les témoins et la base, ailleurs ou sur ce nœud, fonctionnent.

*Hypothèses* : attachement en échec ; pilote non enregistré sur ce nœud ; `NodeStageVolume` en échec (identité, réseau vers les moniteurs, module ou outil du nœud) ; `NodePublishVolume` en échec (droits, `fsGroup`).

**Étape 1 — Cadrer.** `kubectl describe pod` donne l'étage par le préfixe de l'événement : `AttachVolume.Attach failed` (contrôleur), `MountVolume.MountDevice failed` (staging sur le nœud), `MountVolume.SetUp failed` (publication). Le pod de test épinglé sur un autre travailleur (étape 1 du travail) monte un volume : le problème est propre au nœud, ou à une opération que seuls les **nouveaux** montages font.

```
admin@adm01:~$ kubectl get volumeattachment -o custom-columns=PV:.spec.source.persistentVolumeName,NŒUD:.spec.nodeName,ATTACHÉ:.status.attached | grep "$(kubectl get pvc temoin-e36 -n wb-essais -o jsonpath='{.spec.volumeName}')"
admin@k8s-w0N:~$ sudo journalctl -u kubelet --since -15min | grep -i -E 'csi|mount' | tail
```

**Variante 1 — Secret de nœud faux.**

```
Warning  FailedMount  MountVolume.MountDevice failed for volume "pvc-…" : rpc error: code = Internal desc = rbd: map failed
  with error an error (exit status 1) occurred while running rbd args: [--id k8s -m 10.10.30.51:3300,… --keyfile=***stripped***
  map k8s-rbd/csi-vol-… --device-type krbd --options noudev,ms_mode=secure], rbd error output: rbd: sysfs write failed
  … rbd: map failed: (1) Operation not permitted
admin@k8s-w0N:~$ sudo dmesg -T | tail -n 3
… libceph: mon0 (2)10.10.30.51:3300 … auth … error -1      # (libellé exact selon le noyau)
```

L'attachement est fait, le pilote répond, les moniteurs sont joints : c'est l'**authentification** qui échoue. La classe désigne un seul Secret pour toutes les opérations (`csi-rbd-secret`, espace `ceph-csi`, M16-E06) ; le provisionnement de `temoin-e36` avait réussi avant la panne, mais tout nouveau volume échouerait aussi. Preuve sans afficher de clé, par l'outil de M16-E06 :

```
admin@adm01:~/src/k8s$ outils/ceph-csi-secrets.sh verifier
[KO] rbd : la clé du Secret diffère de celle du Vault
[OK] rbd : Vault identique à Ceph (client.k8s)
```

Le Secret a été modifié à la main (audit Kubernetes : `verb: patch`, `objectRef.name: csi-rbd-secret`). Correctif : `outils/ceph-csi-secrets.sh appliquer` (recrée le Secret depuis Vault), puis supprimer le pod en attente pour qu'il retente immédiatement (sinon le kubelet retente avec un délai croissant). Le kubelet relit le Secret à chaque `NodeStageVolume` : aucun redémarrage de ceph-csi n'est nécessaire.

**Variante 2 — moniteurs injoignables depuis le nœud.**

```
Warning  FailedMount  MountVolume.MountDevice failed … rbd: map failed: (110) Connection timed out
admin@k8s-w0N:~$ timeout 3 bash -c '</dev/tcp/10.10.30.51/3300' ; echo $?
124
admin@k8s-w0M:~$ timeout 3 bash -c '</dev/tcp/10.10.30.51/3300' ; echo $?      # un autre travailleur
0
admin@k8s-w0N:~$ ip route get 10.10.30.51
10.10.30.51 dev eth1 src 10.10.30.8N …            # le bon chemin (VLAN 30), la route n'est pas en cause
admin@k8s-w0N:~$ ping -c2 -M do -s 8972 10.10.30.51                                # ICMP passe, MTU bon
admin@k8s-w0N:~$ sudo nft list ruleset | grep -B4 -A2 'dport { 3300, 6789 }'
table inet filtrage_stockage {
        chain sortie {
                type filter hook output priority filter; policy accept;
                ip daddr { 10.10.30.51, 10.10.30.52, 10.10.30.53 } tcp dport { 3300, 6789 } ct state new counter packets 42 bytes 2520 drop comment "InfoGér durcissement INC-2026-0412"
```

Le ping passe, TCP 3300 non : un filtrage. La table n'est ni de Cilium ni du rôle Ansible du nœud ; son compteur monte à chaque tentative de `rbd map`. `ct state new` explique pourquoi les volumes **déjà** montés sur ce nœud fonctionnent : leurs sessions vers les moniteurs et les OSD sont établies et passent. Mais ils perdraient l'accès au premier redémarrage de pod, et le client noyau ne pourrait plus se reconnecter à un autre moniteur. Correctif : `sudo nft delete table inet filtrage_stockage` (jamais `nft flush ruleset`, qui effacerait aussi ce que Cilium et le nœud ont posé), puis vérifier l'absence de la même table sur les autres travailleurs et interroger InfoGér : un durcissement passe par le rôle Ansible et la matrice des flux, pas par une commande à la main. La table, posée à chaud, aurait disparu au redémarrage du nœud : la panne aurait « guéri » sans explication.

**Variante 3 — nœud sans pilote.**

```
Warning  FailedMount  MountVolume.MountDevice failed for volume "pvc-…" : kubernetes.io/csi: attacher.MountDevice failed to create
  newCsiDriverClient: driver name rbd.csi.ceph.com not found in the list of registered CSI drivers
admin@adm01:~$ kubectl get csinode k8s-w0N -o jsonpath='{.spec.drivers[*].name}'
cephfs.csi.ceph.com
admin@adm01:~$ kubectl get ds -n ceph-csi ceph-csi-rbd-nodeplugin
NAME                      DESIRED   CURRENT   READY   NODE SELECTOR
ceph-csi-rbd-nodeplugin   2         2         2       medisphere.internal/stockage-ceph=oui
admin@adm01:~$ kubectl get node k8s-w0N -L medisphere.internal/stockage-ceph        # colonne vide
```

Le DaemonSet n'a que 2 pods voulus pour 3 travailleurs : `k8s-w0N` ne porte plus l'étiquette qui le désigne comme raccordé au stockage (M16-E05/E06). Le pod *nodeplugin* a été retiré, `node-driver-registrar` a désinscrit le pilote. Le pilote CephFS est toujours là si son DaemonSet n'a pas le même sélecteur, d'où une panne « RBD seulement ». Correctif à la racine : rejouer le rôle Ansible `k8s_reseau_stockage` (M16-E05) qui pose l'étiquette après avoir vérifié la carte VLAN 30, plutôt qu'un `kubectl label` à la main (qui n'est acceptable qu'en urgence, reporté ensuite). L'audit Kubernetes donne qui a retiré l'étiquette (`verb: patch` sur `nodes`). Les volumes déjà montés sur ce nœud restent montés, mais ne pourraient plus être démontés proprement (le kubelet a besoin du pilote pour `NodeUnpublish`/`NodeUnstage`) : un drain du nœud resterait bloqué.

*Repli du script* : si le DaemonSet n'a pas ce sélecteur, la panne ajoute au DaemonSet une affinité `NotIn [k8s-w0N]` ; même diagnostic (DESIRED à 2), correction par `helm upgrade` avec les valeurs de `plateforme/k8s`.

**Clôture commune** : `temoin-e36` prêt sur son nœud, `lab/bin/break 16 36 --annuler`, `lab/bin/check 16 36`, RB-165 publié ([modèle](fichiers/M16-E36/medisphere/docs/kubernetes/stockage/runbooks/RB-165-pod-sans-volume.md)).

**Explications**

Le montage d'un volume CSI se fait en deux temps sur le nœud. `NodeStageVolume` (une fois par volume et par nœud) : pour RBD, `rbd map` avec l'identité du Secret de nœud et les moniteurs de la ConfigMap, puis formatage éventuel et montage dans le répertoire global du nœud. `NodePublishVolume` (une fois par pod) : montage *bind* du répertoire global dans celui du pod. Le kubelet ne parle au pilote que s'il est **enregistré** sur le nœud (socket déclaré par `node-driver-registrar`, visible dans `CSINode`). Les trois variantes cassent trois préconditions différentes du staging : l'enregistrement (v3), le réseau vers les moniteurs (v2), l'identité (v1).

**Alternatives**
- Pour v1, recréer le Secret à la main depuis la clé de Ceph (`ceph auth get-key`) fonctionne, mais fait de Ceph la source de vérité au lieu de Vault : si la clé de Ceph avait été changée aussi, on propagerait l'erreur.
- Pour v3, supprimer le `nodeSelector` du DaemonSet « pour que ça marche partout » : le pilote tournerait sur des nœuds sans carte VLAN 30, et les montages y échoueraient en délai dépassé (variante 2 sans le filtrage).

**Pièges classiques**
- Lire les journaux du *nodeplugin* d'un autre nœud que celui du pod.
- Conclure « le réseau est bon » parce que les volumes existants fonctionnent (sessions établies).
- Afficher la clé du Secret (`kubectl get secret -o yaml`, `base64 -d`) dans un terminal partagé ou un journal : compare des empreintes.
- Déplacer le pod sur un autre nœud : le service revient, la panne reste, et le ticket demandait l'inverse.

**En production chez MédiSphère**
Contrôle par nœud dans `ms-verif-k8s-stockage` (pilotes dans `CSINode`, moniteurs joignables en 3300 depuis le nœud) ; vérification périodique `ceph-csi-secrets.sh verifier` en CI planifiée ; les règles nftables des nœuds uniquement par Ansible, avec une alerte si une table inconnue apparaît (Falco ou Tetragon au M26).

---

### M16-E37 — Panne : le volume est déjà attaché ailleurs

**Démarche de diagnostic**

*Symptômes* : un travailleur `NotReady` (appelé `k8s-w0N`), l'ancien pod de `temoin-rbd` en `Terminating` sur ce nœud, le nouveau en `ContainerCreating` sur un autre nœud avec :

```
Warning  FailedAttachVolume  attachdetach-controller  Multi-Attach error for volume "pvc-…" Volume is already used by pod(s) temoin-rbd-…-xxxxx
```

*Hypothèses* : le volume RWO est encore attaché au nœud perdu ; le contrôleur attach/detach attend la preuve qu'il n'est plus utilisé ; reste à savoir si le nœud perdu peut encore écrire.

**Étape 1 — Ce que Kubernetes croit.**

```
admin@adm01:~$ kubectl get volumeattachment -o custom-columns=PV:.spec.source.persistentVolumeName,NŒUD:.spec.nodeName,ATTACHÉ:.status.attached | grep pvc-…
pvc-…   k8s-w0N   true
admin@adm01:~$ kubectl get node k8s-w0N -o jsonpath='{.status.volumesAttached}{"\n"}{.status.volumesInUse}'
```

Le nœud déclare encore le volume « en usage » (dernier état connu). Le contrôleur n'a aucun moyen de savoir si le conteneur écrit toujours : il refuse de détacher, donc d'attacher ailleurs. C'est voulu.

**Étape 2 — Ce qui est vrai.** Accès au nœud, état de la VM, et Ceph :

```
admin@adm01:~$ ssh k8s-w0N true && echo joignable
root@pve01:~# qm status 2145
[admin@ceph01 ~]$ sudo rbd status k8s-rbd/csi-vol-…
Watchers:
        watcher=10.10.30.8N:0/123456789 client.4567 cookie=…          # le nœud perdu tient encore l'image
```

**Variante 1 — nœud à moitié mort (kubelet arrêté).**

SSH répond, la VM tourne, `systemctl status kubelet` : `inactive (dead)`. `sudo crictl ps -a --name temoin` : conteneur `Exited` (il a été arrêté : plus d'écrivain, mais l'image est toujours mappée et montée). Le nœud est **réparable tout de suite** : c'est la voie la plus sûre.

```
admin@k8s-w0N:~$ sudo journalctl -u kubelet -n 20 --no-pager        # arrêt propre : quelqu'un l'a arrêté (qui : journalctl _COMM=systemctl)
admin@k8s-w0N:~$ sudo systemctl start kubelet
admin@adm01:~$ kubectl get nodes -w            # Ready en moins d'une minute
```

Le kubelet revenu constate que l'ancien pod est supprimé, démonte (`NodeUnpublish`, `NodeUnstage` : `rbd unmap`), met à jour `volumesInUse` ; le contrôleur détache, puis attache au nouveau nœud ; le nouveau pod démarre. Aucune procédure forcée.

**Variante 2 — nœud éteint (et qui doit le rester).**

`qm status 2145` : `stopped` ; `rbd status` : plus aucun observateur depuis l'adresse du nœud (le client a disparu avec la VM ; le verrou exclusif de l'image sera repris par le nouveau client). La preuve d'arrêt est faite : arrêt non gracieux.

```
admin@adm01:~$ kubectl taint node k8s-w0N node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
admin@adm01:~$ kubectl get pods -n wb-essais -o wide -w        # l'ancien pod disparaît, le nouveau démarre
admin@adm01:~$ kubectl get volumeattachment | grep pvc-…        # un seul, vers le nouveau nœud
```

La teinte provoque la suppression forcée des pods du nœud qui ne la tolèrent pas et autorise le contrôleur attach/detach à détacher sans attendre le démontage. Quand InfoGér donne son feu vert : `qm start 2145`, attendre `Ready`, vérifier qu'aucun pod ancien ne revient, **puis** retirer la teinte (`kubectl taint node k8s-w0N node.kubernetes.io/out-of-service-`). Sans la teinte, selon la version et `--disable-force-detach-on-timeout`, le contrôleur détache de force au bout de 6 min ou attend indéfiniment : dans les deux cas, ce n'est pas une décision qu'on laisse à un minuteur.

*Effet de bord à commenter* : `mediagenda-db` avait peut-être une instance sur ce nœud. Avec l'anti-affinité requise (une instance par nœud), elle ne peut être replanifiée ailleurs : le cluster tourne sur deux instances jusqu'au retour du nœud. Si c'était le primaire, CloudNativePG a basculé seul (`kubectl cnpg status`).

**Clôture commune** : nœuds `Ready`, aucune teinte restée, un seul `VolumeAttachment`, `lab/bin/break 16 37 --annuler`, `lab/bin/check 16 37`, RB-165 complété (§4 du [modèle](fichiers/M16-E36/medisphere/docs/kubernetes/stockage/runbooks/RB-165-pod-sans-volume.md)).

**Explications**

Pour un volume RWO, le contrôleur attach/detach garantit « au plus un nœud » à partir de son état du monde réel (`VolumeAttachment`, `node.status.volumesAttached`). Il ne détache d'un nœud que lorsque le kubelet de ce nœud a confirmé le démontage (`volumesInUse`). Un nœud injoignable ne confirme rien : le volume reste attaché, et le nouveau pod attend. La teinte `out-of-service` (arrêt non gracieux, GA en 1.28) est la façon pour un humain (ou un automate de clôture) d'**affirmer** que le nœud est arrêté. Kubernetes la croit sur parole. Si l'affirmation est fausse (variante 1 : le nœud tourne, l'image est mappée), deux nœuds peuvent monter le même ext4 : ce système de fichiers n'est pas fait pour deux écrivains, la corruption est probable. Le verrou exclusif de RBD (`exclusive-lock`) ne protège pas : il passe de client en client de façon coopérative, il sérialise les écritures mais ne les empêche pas. La vraie protection côté Ceph est la **liste de blocage** (`ceph osd blocklist add <adresse>`), que ceph-csi automatise par `NetworkFence`.

**Alternatives**
- Variante 1 : la teinte aurait aussi rétabli le service, au prix du risque décrit ; acceptable seulement après avoir arrêté la VM ou bloqué ses adresses dans Ceph.
- Automate de clôture (*fencing*) : un opérateur qui, sur perte d'un nœud, l'éteint par l'API Proxmox (ou l'iLO en physique), bloque ses adresses côté Ceph, pose la teinte, puis la retire au retour (Medik8s *Node Healthcheck* et *Self Node Remediation*, ou csi-addons). À évaluer : il faut lui confier un jeton Proxmox.

**Pièges classiques**
- `kubectl delete pod --force --grace-period=0` sur l'ancien pod : il disparaît de l'API, mais le volume reste attaché au nœud pour le contrôleur ; le Multi-Attach persiste (et l'on a perdu une trace).
- Supprimer le `VolumeAttachment` à la main ou retirer son finaliseur : on court-circuite la seule protection.
- Poser la teinte sur un nœud « qui ne répond plus en SSH » sans regarder la VM : un nœud saturé (mémoire, disque) peut encore écrire.
- Oublier de retirer la teinte : plus aucun pod ne s'y planifie, le nœud semble sain mais vide.

**En production chez MédiSphère**
Procédure d'astreinte écrite (RB-165 §4) avec la preuve d'arrêt obligatoire (`qm status` ou iLO) ; alerte « nœud NotReady > 2 min » ; étude d'un automate de clôture (ticket PLAT) ; `ReadWriteOncePod` pour les volumes qui ne doivent jamais avoir deux pods, même sur un seul nœud.

---

### M16-E38 — Panne : Ceph refuse de créer les volumes

**Démarche de diagnostic**

*Symptômes* : `temoin-e38` `Pending` avec `ProvisioningFailed`. Les volumes montés : intacts (v1, v3, pour l'instant), ou figés en écriture (v2).

*Hypothèses* : droits de `client.k8s` ; quota ou remplissage de `k8s-rbd` ; clé de `client.k8s` différente de celle des Secrets ; santé de `ceph-par1` (MON, OSD : pas touchés par cette panne, mais à éliminer).

**Étape 1 — L'erreur du pilote.**

```
admin@adm01:~$ kubectl get lease -n ceph-csi                         # le leader du provisioner RBD
admin@adm01:~$ kubectl logs -n ceph-csi <leader> -c csi-rbdplugin --since=15m | grep -i -E 'error|failed' | tail -n 5
```

**Étape 2 — Le côté Ceph, vu comme le code le décrit.**

```
[admin@ceph01 ~]$ sudo ceph health detail
[admin@ceph01 ~]$ sudo ceph auth get client.k8s -f json | jq '.[0].caps'
[admin@ceph01 ~]$ sudo ceph osd pool get-quota k8s-rbd ; sudo ceph df detail | grep -E 'POOL|k8s-rbd'
[admin@ceph01 ~]$ sudo ceph log last 200 debug audit | grep -E '"prefix": "(auth|osd pool set-quota)'
admin@adm01:~/src/ceph$ outils/ceph-allocations.sh verifier
admin@adm01:~/src/k8s$ outils/ceph-csi-secrets.sh verifier
```

**Variante 1 — droits « réalignés sur la documentation ».**

```
E… GRPC error: rpc error: code = Internal desc = failed to create rbd image: rbd: ret=-1, Operation not permitted
"osd": "profile rbd pool=kubernetes", "mgr": "profile rbd pool=kubernetes", "mon": "profile rbd"
… cmd=[{"prefix": "auth caps", "entity": "client.k8s", …}]: finished      # audit : qui, quand
```

Le tutoriel « Block Devices and Kubernetes » de Ceph utilise un pool `kubernetes` : Lucas a copié les droits de l'exemple. `ceph-allocations.sh verifier` signale l'écart avec `allocations.yaml`. Correctif : `outils/ceph-allocations.sh appliquer --simuler` puis `appliquer` (l'outil remet les droits du code, sans toucher à la clé). Impact sur les volumes montés : leurs sessions gardent les droits de leurs titres en cours, jusqu'au renouvellement (de l'ordre de `auth_service_ticket_ttl`, une heure par défaut) ; après, chaque écriture serait refusée et le système de fichiers renverrait des erreurs d'E/S (selon son réglage `errors=` : poursuite, remontage en lecture seule ou panique). D'où la consigne d'annuler au-delà d'une heure.

**Variante 2 — quota du pool saturé.**

```
[WRN] POOL_FULL: 1 pool(s) full
    pool 'k8s-rbd' is full (running out of quota)
QUOTA BYTES  … 1.2 GiB   USED … 1.2 GiB
E… GRPC error: rpc error: code = DeadlineExceeded …  /  code = Aborted desc = an operation with the given Volume ID … already exists
```

La création attend (le pool refuse toute écriture), le sidecar abandonne au délai, réessaie, et ceph-csi répond `Aborted` tant que la première tentative est encore en cours. Les volumes existants de `k8s-rbd` sont **figés** en écriture : les témoins passent à 0/1 au bout d'une minute, la base de recette ne valide plus de transaction. Aucune donnée n'est perdue : le client noyau attend. Audit : `osd pool set-quota … max_bytes` avec une valeur égale à l'occupation. Correctif : remettre le quota du code (`config/cluster.yaml` de `plateforme/ceph`, 20 Gio au M08-E46) par l'outil de configuration du M08 (`outils/config-cluster.sh --appliquer`), puis vérifier que les écritures reprennent (témoins prêts, `kubectl cnpg status`). Ne pas « supprimer le quota » : il protège le reste de `ceph-par1` d'un emballement de Kubernetes.

**Variante 3 — clé renouvelée en `aes256k`.**

```
E… failed to connect to the cluster … (1) Operation not permitted        # ou : error connecting to the cluster: permission denied
admin@adm01:~/src/k8s$ outils/ceph-csi-secrets.sh verifier
[OK] rbd : Secret identique au Vault
[KO] rbd : la clé du Vault n'est plus celle de client.k8s dans Ceph (rotation ?)
[admin@ceph01 ~]$ sudo ceph auth get-key client.k8s | wc -c                      # longueur différente des autres clés clientes
… cmd=[{"prefix": "auth rotate", "entity": "client.k8s", "key_type": "aes256k"}]   # audit
```

Lucas a appliqué à `client.k8s` la procédure de M08-E27 (« passer les clés au nouveau type »), qui renouvelle aussi la valeur de la clé. Deux problèmes se cumulent : la clé de Ceph ne correspond plus à celle des Secrets et de Vault ; et le client noyau 6.12 des travailleurs ne sait pas utiliser ce type (M08-E27), même avec la bonne valeur. Deux corrections possibles :
- **remettre la clé de référence** (celle de Vault, type `aes`) : les Secrets, Vault et les volumes déjà montés retrouvent une clé cohérente, rien à redémarrer. C'est la bonne option ici. Sur `ceph01`, construire un trousseau temporaire (`umask 077`, dans `/dev/shm`) avec la clé de Vault et les droits de `allocations.yaml`, l'importer par `ceph auth import -i`, l'effacer (`shred -u`) ;
- distribuer une **nouvelle** clé `aes` (`ceph auth rotate --key-type=aes client.k8s`, puis Vault et `ceph-csi-secrets.sh appliquer`) : correct pour les nouveaux montages, mais chaque volume déjà mappé garde l'ancienne clé et perd l'accès à son prochain renouvellement de titre ; il faudrait redémarrer tous les pods à volume RBD. À réserver à une fuite de clé, dans une fenêtre annoncée.

**Clôture commune** : `temoin-e38` lié, témoins prêts, `ceph-allocations.sh verifier` et `ceph-csi-secrets.sh verifier` sans écart, `lab/bin/break 16 38 --annuler`, `lab/bin/check 16 38`. RB-160 : section « le provisionnement échoue côté Ceph » (code d'erreur → cause, et la question « les volumes montés sont-ils menacés, et dans combien de temps ? »).

**Explications**

ceph-csi crée une image avec librbd dans le conteneur `csi-rbdplugin` du provisioner, sous l'identité du Secret de provisionnement : chaque appel ouvre une session vers les moniteurs (authentification, titres), puis écrit les objets de l'image et l'omap du journal de ceph-csi dans `k8s-rbd`. Les droits OSD `profile rbd pool=k8s-rbd` autorisent exactement ces opérations sur ce pool ; les droits mgr servent aux tâches asynchrones (suppression différée par la corbeille). Les volumes montés, eux, utilisent le client noyau avec la même identité, authentifiée au moment du `rbd map` : ils ne voient un changement de droits ou de clé qu'au renouvellement de leurs titres, et un pool plein immédiatement.

**Alternatives**
- Identités séparées pour le provisionnement et le montage (deux Secrets, deux entités cephx) : un incident sur l'une ne bloque pas l'autre ; plus d'objets à gérer.
- Clé `aes256k` utilisable avec `rbd-nbd` (client en espace utilisateur, bibliothèques de Ceph 20.2.4 dans le conteneur) : au prix des performances et de la robustesse (un redémarrage du *nodeplugin* coupe les volumes NBD).

**Pièges classiques**
- Élargir les droits (`allow rwx`, `allow *`) pour « débloquer » : la panne disparaît, la dette de sécurité reste.
- Supprimer le quota : `k8s-rbd` peut alors remplir les OSD partagés avec OpenStack.
- Remplacer seulement le Secret par la nouvelle clé (v3) : les nouveaux volumes échouent encore (type de clé), et les anciens tomberont dans l'heure.
- Afficher `ceph auth get client.k8s` (la clé apparaît) dans un ticket.

**En production chez MédiSphère**
Dérive de `ceph-par1` contrôlée par le pipeline planifié de `plateforme/ceph` (M08) ; alerte quota de `k8s-rbd` > 80 % ; renouvellement de clé du consommateur Kubernetes par une procédure écrite (fenêtre, ordre : Vault, Secret, Ceph, redémarrage contrôlé des pods) ; type `aes256k` quand les nœuds auront un noyau qui le gère (ticket SEC du M08).

---
### M16-E39 — Panne : la sauvegarde Velero échoue

**Démarche de diagnostic**

*Symptômes* : la sauvegarde `temoin-AAAAMMJJ-HHMM` est `FailedValidation` ou `Failed` (variantes 1 à 3 : l'emplacement `s3-01` est `Unavailable`), ou `PartiallyFailed` (variante 4 : un volume n'est pas sauvegardé).

*Hypothèses* : identifiants S3 ; compartiment ou préfixe ; TLS (CA) ; réseau vers `s3-01:8333` (bordure, M14) ; `node-agent` absent ou en échec sur un nœud ; dépôt Kopia (mot de passe, `velero-repo-credentials`).

**Étape 1 — Phase et emplacement.**

```
admin@adm01:~$ velero backup get
admin@adm01:~$ velero backup-location get
NAME    PROVIDER   BUCKET/PREFIX      PHASE         LAST VALIDATED   ACCESS MODE   DEFAULT
s3-01   aws        velero-k8s-par1    Unavailable   …                ReadWrite     true
admin@adm01:~$ kubectl get bsl s3-01 -n velero -o jsonpath='{.status.message}{"\n"}'
admin@adm01:~$ velero backup describe temoin-… --details ; velero backup logs temoin-… | grep -i error
```

**Variantes 1 à 3 — reproduire depuis le cluster.** Un pod jetable dans `wb-essais` avec l'image `amazon/aws-cli` du cache Harbor (ou `curl --aws-sigv4`), qui monte le Secret `velero-s3` (fichier `cloud` au format AWS, variable `AWS_SHARED_CREDENTIALS_FILE`) et la CA MédiSphère, et lance `aws s3 ls s3://velero-k8s-par1 --endpoint-url https://s3-01.par1.medisphere.internal:8333 --ca-bundle …` : il reproduit exactement ce que fait le plugin AWS, sans jamais afficher de clé. (Penser aux politiques réseau de `wb-essais`, M15 : une sortie vers 10.10.20.14:8333 à autoriser pour ce pod de test, puis à retirer.)

- **v1 — identifiants** : `SignatureDoesNotMatch` (clé secrète fausse, identifiant d'accès connu). Compare les empreintes de `aws_secret_access_key` du Secret et de `~/.config/workbook/s3-velero.env` : elles diffèrent ; l'audit Kubernetes montre la modification du Secret. Correctif : `outils/secrets-sauvegarde.sh velero` (M16-E16) recrée `velero-s3` depuis le fichier de référence ; Velero relit le fichier monté après sa propagation par le kubelet (une minute environ) et la validation suivante remet l'emplacement `Available`.
- **v2 — compartiment** : `NoSuchBucket` ou `AccessDenied` sur `velero-k8s-par01`. `helm get values velero -n velero` ou l'objet `BackupStorageLocation` diffèrent de `composants/velero/values.yaml` (`bucket: velero-k8s-par1`). Le compte `velero` n'a de droits que sur son compartiment (rôle `seaweedfs`, M16-E16) : la faute de frappe ne peut rien créer ailleurs, c'est voulu. Correctif : `helm upgrade` de la release avec les valeurs du code (le chart gère l'emplacement).
- **v3 — CA** : `x509: certificate signed by unknown authority`. Le piège : le `caCert` posé porte le **même nom** (« MediSphere Root CA »).
  ```
  admin@adm01:~$ kubectl get bsl s3-01 -n velero -o jsonpath='{.spec.objectStorage.caCert}' | base64 -d | openssl x509 -noout -subject -fingerprint -sha256
  admin@adm01:~$ openssl x509 -noout -subject -fingerprint -sha256 -in /usr/local/share/ca-certificates/medisphere-root-ca.crt
  ```
  Sujets identiques, empreintes différentes : ce n'est pas la racine de la PKI. Correctif : `helm upgrade` avec les valeurs du code (`caCert` = base64 de la vraie racine). Un nom ne prouve rien, une empreinte si.

**Variante 4 — `node-agent` absent d'un nœud.**

```
admin@adm01:~$ velero backup describe temoin-… --details | sed -n '/Pod Volume Backups/,$p'
  Failed:  wb-essais/temoin-rbd-…: donnees
admin@adm01:~$ kubectl get podvolumebackups -n velero -o wide | grep temoin
… Failed   … k8s-w0N   … node-agent pod is not running in node k8s-w0N      # (libellé selon la version)
admin@adm01:~$ kubectl get ds node-agent -n velero
NAME         DESIRED   CURRENT   READY
node-agent   2         2         2
admin@adm01:~$ kubectl get ds node-agent -n velero -o jsonpath='{.spec.template.spec.affinity}'
{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{…"operator":"NotIn","values":["k8s-w0N"]…}}}
```

La sauvegarde de fichiers (Kopia) d'un volume est faite par le `node-agent` **du nœud où tourne le pod** (il lit le volume monté sous `/var/lib/kubelet/pods`). Sans agent sur `k8s-w0N`, le volume du témoin est ignoré, le reste passe : `PartiallyFailed`. Correctif : `helm upgrade` avec les valeurs du code (aucune affinité, tolérance `dedie=bdd`), DESIRED revient à 3.

**Étape finale commune — prouver la sauvegarde et la restauration.**

```
admin@adm01:~$ velero backup create wb-essais-$(date +%H%M) --include-namespaces wb-essais --default-volumes-to-fs-backup --wait
admin@adm01:~$ velero backup describe wb-essais-HHMM --details     # Phase: Completed ; Pod Volume Backups: Completed 2 (ou plus)
admin@adm01:~$ velero restore create --from-backup wb-essais-HHMM --namespace-mappings wb-essais:wb-restauration --wait
admin@adm01:~$ kubectl get pods,pvc -n wb-restauration              # témoins restaurés, prêts
admin@adm01:~$ kubectl exec -n wb-restauration deploy/temoin-rbd -- cat /donnees/battement
admin@adm01:~$ kubectl delete namespace wb-restauration            # nettoyage (volumes restaurés supprimés : classe Delete)
```

Puis `lab/bin/break 16 39 --annuler`, `lab/bin/check 16 39`, RB-166 ([modèle](fichiers/M16-E39/medisphere/docs/kubernetes/stockage/runbooks/RB-166-sauvegarde-velero-en-echec.md)).

**Explications**

Velero sépare l'**emplacement** (où vont les métadonnées et les données : `BackupStorageLocation`, validé chaque minute par le serveur, qui ouvre une session S3 avec le plugin AWS) et le **transport des volumes** (`node-agent` pour Kopia ou pour le déplacement des données d'instantanés CSI). Une sauvegarde vers un emplacement `Unavailable` est refusée d'emblée (`FailedValidation`) : bon comportement, qui rend la panne visible tout de suite. Un défaut de transport ne touche que les volumes concernés : `PartiallyFailed`, plus traître, car la sauvegarde « existe ». Velero 1.18 ne propose plus Restic pour sauvegarder : Kopia seulement.

**Alternatives**
- `spec.credential` sur l'emplacement (un Secret par emplacement) plutôt que le fichier monté : utile avec plusieurs emplacements ; même diagnostic.
- `caCertRef` (référence à un Secret) au lieu de `caCert` en clair dans l'objet, quand le chart le permettra (noté au M16-E16).

**Pièges classiques**
- Se contenter de `velero backup get` : `PartiallyFailed` passe facilement pour un succès.
- Reprendre l'identifiant et la clé dans un terminal pour tester : ils finissent dans l'historique du shell.
- Créer le compartiment « qui manque » (v2) avec un compte administrateur : on valide la faute de frappe.
- Tester la restauration dans l'espace d'origine : les objets existants sont ignorés (politique par défaut `none`), la restauration paraît réussie sans rien prouver.

**En production chez MédiSphère**
Contrôle de l'emplacement `Available` et de l'âge de la dernière sauvegarde réussie par planification (M16-E27), test de restauration mensuel automatisé dans `wb-restauration` (M29), alertes au M21 sur `velero_backup_partial_failure_total` et `velero_backup_failure_total`.

---

### M16-E40 — Panne : la base PostgreSQL ne bascule plus

**Démarche de diagnostic**

*Symptômes* (répétition de Lucas) : v1, le drain du nœud du primaire est refusé ; v2 et v3, la bascule et le drain passent, puis les écritures de MédiAgenda restent bloquées.

*Hypothèses* : budget de disruption ; instance non candidate (clôturée, en retard, non prête) ; réplication synchrone qui ne peut plus être satisfaite pendant la maintenance ; nœud ou place manquants pour replanifier (anti-affinité requise : normal pendant un drain).

**Étape 1 — État de référence et filet.**

```
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette
admin@adm01:~$ kubectl get pdb -n mediagenda-recette -o custom-columns=NOM:.metadata.name,MIN:.spec.minAvailable,MAX:.spec.maxUnavailable,SÉLECTEUR:.spec.selector.matchLabels,PROPRIÉTAIRE:.metadata.ownerReferences[0].kind
admin@adm01:~$ kubectl get cluster mediagenda-db -n mediagenda-recette -o jsonpath='{.metadata.annotations}{"\n"}{.spec.postgresql.synchronous}{"\n"}'
```

La section *Continuous Backup* de `kubectl cnpg status` (dernier WAL archivé, première date de restauration possible) répond à « de quoi repartirait-on ». Mesure de la coupure (pod jetable) :

```
admin@adm01:~$ kubectl run -n mediagenda-recette sonde-ecriture --rm -it --restart=Never \
    --image=registry.par1.medisphere.internal/dockerhub/library/postgres:18 \
    --overrides='{"spec":{"containers":[{"name":"sonde-ecriture","image":"registry.par1.medisphere.internal/dockerhub/library/postgres:18","stdin":true,"tty":true,"env":[{"name":"URI","valueFrom":{"secretKeyRef":{"name":"mediagenda-db-app","key":"uri"}}}]}]}}' -- bash
root@sonde-ecriture:/# psql "$URI" -c 'create table if not exists sonde_bascule (t timestamptz default now())'
root@sonde-ecriture:/# while true; do timeout 2 psql "$URI" -qc 'insert into sonde_bascule default values' >/dev/null 2>&1 && echo "$(date +%T) ok" || echo "$(date +%T) ÉCHEC"; sleep 0.5; done
```

Le pod a besoin d'une politique réseau qui l'autorise à joindre PostgreSQL (refus par défaut de `mediagenda-recette`, M15-E17) : réutilise l'étiquette de l'API ou crée une politique temporaire. La table de test se supprime à la fin.

**Variante 1 — PDB superposé.**

```
admin@adm01:~$ kubectl drain k8s-w0N --ignore-daemonsets --delete-emptydir-data
error when evicting pods/"mediagenda-db-1" -n "mediagenda-recette" (will retry after 5s): This pod has more than one
PodDisruptionBudget, which the eviction subresource does not support.
NOM                          MIN   …  SÉLECTEUR                                                   PROPRIÉTAIRE
mediagenda-db                …        map[cnpg.io/cluster:mediagenda-db cnpg.io/instanceRole:replica]   Cluster
mediagenda-db-primary        1        map[cnpg.io/cluster:mediagenda-db cnpg.io/instanceRole:primary]   Cluster
mediagenda-db-maintenance    3        map[cnpg.io/cluster:mediagenda-db]                                <none>
```

L'API d'éviction refuse toute éviction d'un pod couvert par plusieurs PDB : ni CloudNativePG ni le drain ne peuvent rien. Le troisième PDB n'a pas de propriétaire et n'est pas dans le code (annotation « CHG-1738 » : une protection provisoire jamais retirée). Correctif : le supprimer, après avoir vérifié qu'aucun changement en cours n'en dépend. Puis maintenance (étape finale).

**Variante 2 — une réplique clôturée.**

```
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette
Instances status
Name             …  Status    Replication role   Node
mediagenda-db-1  …  OK        Primary            k8s-w0N
mediagenda-db-2  …  Fenced    Standby (…)        k8s-w0M
mediagenda-db-3  …  OK        Standby (sync)     k8s-w0P
admin@adm01:~$ kubectl get cluster mediagenda-db -n mediagenda-recette -o jsonpath='{.metadata.annotations.cnpg\.io/fencedInstances}'
["mediagenda-db-2"]
```

Si Lucas promeut `mediagenda-db-2`, la promotion est refusée (instance clôturée). S'il draine : CloudNativePG bascule sur `mediagenda-db-3` (seule candidate), l'ancien primaire est évincé et reste `Pending` (anti-affinité requise), et il ne reste **aucune** réplique saine : `show synchronous_standby_names` attend une réplique synchrone, `pg_stat_replication` est vide, et avec `dataDurability: required` chaque validation attend. C'est « ça bascule mal ». Cause : une clôture posée pour un « diagnostic disque » et jamais levée (audit : `patch` sur le Cluster). Avant de la lever, vérifie que la raison n'existe plus (journal de l'instance, place du volume). Correctif :

```
admin@adm01:~$ kubectl cnpg fencing off mediagenda-db mediagenda-db-2 -n mediagenda-recette
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette      # 3 instances OK, réplication en flux
```

Si les écritures sont déjà bloquées (drain fait), `kubectl uncordon` du nœud drainé ramène l'instance évincée, qui redevient réplique synchrone : les validations reprennent.

**Variante 3 — réplication synchrone mal réglée.**

```
admin@adm01:~$ kubectl exec -n mediagenda-recette mediagenda-db-1 -c postgres -- psql -tAc 'show synchronous_standby_names'
ANY 2 ("mediagenda-db-2","mediagenda-db-3")
admin@adm01:~$ kubectl get cluster mediagenda-db -n mediagenda-recette -o jsonpath='{.spec.postgresql.synchronous}'
{"dataDurability":"required","method":"any","number":2}
admin@adm01:~/src/k8s$ kubectl diff -f espaces/mediagenda-recette/50-mediagenda-db.yaml     # number: 1 dans le code
```

Tant que les trois instances tournent, deux répliques synchrones existent : rien ne se voit. Pendant le drain, l'instance évincée reste `Pending` : il ne reste qu'une réplique, PostgreSQL en attend deux, et avec `dataDurability: required` les validations attendent indéfiniment. Règle : avec N instances et une durabilité exigée, `number` ≤ N − 2 pour supporter la perte (ou le drain) d'une instance ; ici 1. Correctif : réappliquer le manifeste du code (`task appliquer`) ; `synchronous_standby_names` se recharge sans redémarrage.

**Étape finale commune — la maintenance.**

```
admin@adm01:~$ kubectl cnpg promote mediagenda-db mediagenda-db-3 -n mediagenda-recette   # une réplique saine, sur un autre nœud
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette                     # nouveau primaire, réplique synchrone présente
admin@adm01:~$ kubectl drain k8s-w0N --ignore-daemonsets --delete-emptydir-data --timeout=10m
#   (l'instance évincée reste Pending : attendu)
admin@adm01:~$ kubectl uncordon k8s-w0N
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-recette                     # 3 instances, réplication en flux
```

Coupure mesurée par la sonde : de l'ordre de quelques secondes au `promote` (fermeture des connexions, promotion, bascule du Service `-rw`), aucune au drain si la bascule a été faite avant. Puis `lab/bin/break 16 40 --annuler`, `lab/bin/check 16 40`, RB-167 ([modèle](fichiers/M16-E40/medisphere/docs/kubernetes/stockage/runbooks/RB-167-mediagenda-db-bascule-archivage.md)), section A.

**Explications**

Une bascule CloudNativePG est un arrêt propre du primaire suivi de la promotion d'une réplique **candidate** : prête, non clôturée, la plus avancée. Les deux PDB que CloudNativePG gère (primaire : au moins 1 ; répliques : au plus une indisponible) rendent le drain sûr : le drain cordonne le nœud, l'opérateur voit son primaire sur un nœud non planifiable et bascule d'abord, puis l'éviction de l'ancien primaire, devenu réplique, est permise. Tout ce qui s'ajoute à ce mécanisme (un PDB de plus, une clôture, une exigence de réplication synchrone plus forte que ce que le cluster peut offrir pendant la maintenance) le casse sans bruit, jusqu'au jour où l'on s'en sert. La réplication synchrone avec `dataDurability: required` échange de la disponibilité contre la garantie qu'une transaction validée existe sur au moins `number` répliques : bon choix pour des données de santé, à condition de dimensionner `number` pour l'état dégradé.

**Alternatives**
- `dataDurability: preferred` : les écritures continuent quand les répliques synchrones manquent (la garantie tombe temporairement) ; choix de disponibilité, à écrire dans la politique (M16-E32).
- `nodeMaintenanceWindow` (ancien mécanisme) : déconseillé par la documentation au profit des PDB.

**Pièges classiques**
- `enablePDB: false` « le temps de la maintenance » : plus rien n'empêche d'évincer le primaire avant la bascule.
- `kubectl delete pod` du primaire pour « forcer » : c'est une bascule non préparée (*failover*), avec la perte possible des dernières transactions en asynchrone.
- Lever une clôture sans en connaître la raison.
- Prendre l'instance `Pending` pendant le drain pour la panne : avec l'anti-affinité requise et trois nœuds, c'est le comportement attendu.

**En production chez MédiSphère**
Répétition de maintenance trimestrielle sur la recette avec mesure de la coupure ; contrôle `ms-verif-k8s-stockage` : aucune instance clôturée depuis plus de 4 h, aucun PDB sans propriétaire sur les pods de base ; règle de revue de MR : `synchronous.number` ≤ `instances − 2`.

---

### M16-E41 — Panne : l'archivage des WAL est bloqué

**Démarche de diagnostic**

*Symptômes* : condition `ContinuousArchiving` à `False`, `kubectl cnpg status` signale l'échec d'archivage, `pg_stat_archiver.failed_count` augmente, `last_failed_time` plus récent que `last_archived_time`.

*Hypothèses* : identifiants ; compartiment ou chemin ; TLS (CA) ; réseau vers `s3-01` (bordure, politiques réseau de l'espace) ; conteneur du plugin en échec ; `ObjectStore` désigné par le Cluster absent ou mal nommé.

**Étape 1 — Dater et mesurer le risque.**

```
admin@adm01:~$ kubectl exec -n mediagenda-recette <PRIMAIRE> -c postgres -- psql -tAxc 'select * from pg_stat_archiver'
archived_count     | 1842
last_archived_wal  | 000000010000000000000041
last_archived_time | 2026-… 01:12:07
failed_count       | 37
last_failed_wal    | 000000010000000000000042
last_failed_time   | 2026-… 01:49:55
admin@adm01:~$ kubectl exec -n mediagenda-recette <PRIMAIRE> -c postgres -- bash -c 'du -sh /var/lib/postgresql/data/pgdata/pg_wal; df -h /var/lib/postgresql/data'
```

Depuis `last_archived_time`, rien n'est sorti du cluster : la restauration à un instant donné n'est possible que **jusqu'à** cet instant. Les segments restent dans `pg_wal` (5 Gio de volume au M16-E18) : à quelques Mio par heure en recette, la base tient des jours ; en production, il faudrait agrandir le volume tout de suite (M16-E11).

**Étape 2 — La cause, dans le conteneur du plugin.**

```
admin@adm01:~$ kubectl get pod <PRIMAIRE> -n mediagenda-recette -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}{"\n"}'
admin@adm01:~$ kubectl logs -n mediagenda-recette <PRIMAIRE> -c plugin-barman-cloud --since=30m | grep -i -E 'error|fail' | tail -n 5
admin@adm01:~/src/k8s$ kubectl diff -f espaces/mediagenda-recette/60-cnpg-s3.yaml
```

- **v1 — identifiants** : `SignatureDoesNotMatch` dans la sortie de `barman-cloud-wal-archive`. `kubectl diff` sur l'`ObjectStore` ne montre rien : la référence est bonne, c'est le **contenu** du Secret `cnpg-s3` qui a changé (empreinte de `ACCESS_SECRET_KEY` comparée à celle de `~/.config/workbook/s3-cnpg.env`). Correctif : `outils/secrets-sauvegarde.sh cnpg mediagenda-recette` (M16-E19).
- **v2 — compartiment** : `NoSuchBucket` ou `AccessDenied` pour `cnpg-k8s-par1-wal`. `kubectl diff` montre `destinationPath: s3://cnpg-k8s-par1-wal/` au lieu de `s3://cnpg-k8s-par1/`. Le compte `cnpg` n'a de droits que sur son compartiment : rien n'a été écrit ailleurs. Correctif : réappliquer `60-cnpg-s3.yaml`.
- **v3 — CA** : `SSL: CERTIFICATE_VERIFY_FAILED` (bibliothèque Python de barman-cloud). `kubectl diff` montre `endpointCA.name: cnpg-s3-ca-2026` au lieu de `medisphere-ca`, un Secret créé le jour de la panne ; son certificat porte le nom de la racine MédiSphère mais pas son empreinte (`openssl x509 -fingerprint`, comme en M16-E39 v3). Correctif : réappliquer `60-cnpg-s3.yaml`, puis supprimer le Secret intrus après avoir vérifié que rien d'autre ne le référence.

Mesure indépendante, si le journal ne suffit pas : pod jetable dans l'espace avec `amazon/aws-cli`, les **mêmes** Secrets montés et la même CA, `aws s3 ls s3://cnpg-k8s-par1/mediagenda-db/wals/ --endpoint-url https://s3-01.par1.medisphere.internal:8333 --ca-bundle …`.

**Étape 3 — Rattraper et prouver la continuité.**

```
admin@adm01:~$ kubectl exec -n mediagenda-recette <PRIMAIRE> -c postgres -- psql -tAc 'select pg_switch_wal()'
admin@adm01:~$ kubectl exec -n mediagenda-recette <PRIMAIRE> -c postgres -- psql -tAxc 'select archived_count, last_archived_wal, last_failed_time from pg_stat_archiver'
admin@adm01:~$ set -a; . ~/.config/workbook/s3-cnpg.env; set +a        # lecture seule, dans un sous-shell de préférence
admin@adm01:~$ aws s3 ls --recursive s3://cnpg-k8s-par1/mediagenda-db/wals/ --endpoint-url https://s3-01.par1.medisphere.internal:8333 | awk '{print $4}' | sed 's#.*/##; s/\..*//' | sort | tail -n 40
admin@adm01:~$ kubectl cnpg backup mediagenda-db -n mediagenda-recette --method plugin --plugin-name barman-cloud.cloudnative-pg.io
```

`archived_count` rattrape le nombre de segments en retard, `last_failed_time` ne bouge plus. La liste des segments est continue (noms hexadécimaux consécutifs, sans trou entre `…41` et le dernier) : PostgreSQL n'efface un segment de `pg_wal` qu'une fois archivé, l'archivage reprend là où il s'était arrêté, **aucun WAL n'est perdu** tant que le volume ne s'est pas rempli. Réponse à Sophie : pendant la panne, restauration possible jusqu'à `last_archived_time` (01:12:07 dans l'exemple) ; après la reprise, jusqu'à l'instant présent. Puis `lab/bin/break 16 41 --annuler`, `lab/bin/check 16 41`, RB-167 section B.

**Explications**

À chaque segment de 16 Mio rempli (ou toutes les `archive_timeout` secondes, 5 min par défaut dans CloudNativePG), PostgreSQL appelle sa commande d'archivage : le gestionnaire d'instance de CloudNativePG la transmet, par CNPG-I, au conteneur auxiliaire du plugin Barman Cloud, qui lit l'`ObjectStore` et ses Secrets et lance `barman-cloud-wal-archive` vers S3. Tout échec est rendu à PostgreSQL, qui garde le segment et réessaie. La condition `ContinuousArchiving` du Cluster et `pg_stat_archiver` le rendent visible ; la seule vraie menace est le remplissage du volume (le primaire s'arrêterait). Le plugin remplace l'archivage intégré `barmanObjectStore`, déprécié en 1.30 et supprimé en 1.31.

**Alternatives**
- Un second `ObjectStore` (autre site, F5) pour les WAL : le plugin ne gère qu'un archiveur de WAL par Cluster, mais la réplication du compartiment côté S3 donne une seconde copie.
- `archive_timeout` plus court pour réduire le RPO : plus de segments (presque vides) à stocker.

**Pièges classiques**
- « Réparer » en pointant l'`ObjectStore` vers un compartiment neuf sans nouvelle sauvegarde de base : les WAL archivés ensuite n'ont pas de base pour être rejoués.
- Supprimer des segments de `pg_wal` pour faire de la place : perte définitive de la fenêtre de restauration (et souvent de la base).
- Afficher les identifiants S3 en diagnostiquant ; ou les écrire dans l'`ObjectStore` en clair au lieu de références à des Secrets.
- Croire la panne réparée parce que `ContinuousArchiving` repasse à `True` : vérifier la continuité des segments.

**En production chez MédiSphère**
Alerte « dernier WAL archivé il y a plus de 10 min » et « `pg_wal` > 50 % du volume » (métriques de l'instance, M21) ; volume de base avec marge et classe extensible ; test de restauration à un instant donné mensuel (M16-E34) ; Secrets S3 gérés par External Secrets depuis Vault au M25.

---

### M16-E42 — Panne : le snapshot ne se termine jamais

**Démarche de diagnostic**

*Symptômes* : `VolumeSnapshot temoin-rbd-HHMM` avec `READYTOUSE` vide ou `false`.

*Hypothèses* : `snapshot-controller` absent, arrêté ou sans droits (aucun statut, aucun contenu) ; sidecar `csi-snapshotter` ou pilote en échec (contenu créé, en erreur) ; classe d'instantané incohérente (contenu en erreur) ; CRD absente (la création du `VolumeSnapshot` aurait été refusée : pas ce cas).

**Étape 1 — Lire l'état, il désigne l'étage.**

```
admin@adm01:~$ kubectl get volumesnapshot -n wb-essais temoin-rbd-HHMM -o yaml | sed -n '/^status/,$p'
admin@adm01:~$ kubectl get volumesnapshotcontent -o custom-columns=NOM:.metadata.name,VS:.spec.volumeSnapshotRef.name,PRÊT:.status.readyToUse,ERREUR:.status.error.message | grep temoin
```

**Variante 1 — contrôleur arrêté** : aucun statut, aucun contenu.

```
admin@adm01:~$ kubectl get deploy snapshot-controller -n kube-system
NAME                  READY   UP-TO-DATE   AVAILABLE
snapshot-controller   0/0     0            0
```

Mis à zéro à la main (audit). Correctif : réappliquer la kustomisation du code (`composants/snapshot-controller/`, M16-E06), 2 répliques avec élection de leader. Le contrôleur traite l'instantané en attente dès son démarrage.

**Variante 2 — classe fausse** : contenu créé, en erreur.

```
ERREUR: … failed to get input parameters to create snapshot for content snapcontent-…: "cannot get credentials for snapshot
        content \"snapcontent-…\": failed to get secret ceph-csi-rbd/csi-rbd-secret …"           # (libellé selon la version)
admin@adm01:~$ kubectl get volumesnapshotclass ceph-rbd-snap -o jsonpath='{.parameters}'
{"clusterID":"…","csi.storage.k8s.io/snapshotter-secret-name":"csi-rbd-secret","csi.storage.k8s.io/snapshotter-secret-namespace":"ceph-csi-rbd"}
admin@adm01:~$ kubectl get storageclass ceph-rbd -o jsonpath='{.parameters.csi\.storage\.k8s\.io/provisioner-secret-namespace}'
ceph-csi
```

La classe a été recréée (date de création récente) avec un espace de noms qui n'existe pas : le sidecar ne trouve pas le Secret. Correctif : réappliquer `ceph-rbd-snap` depuis le code ; si `kubectl apply` refuse de modifier les paramètres, supprimer puis recréer la classe (sans effet sur les instantanés existants, qui gardent leurs références). Le sidecar réessaie le contenu en erreur ; sinon, supprimer l'instantané **en attente** (il n'a créé aucune image) et en redemander un.

**Variante 3 — contrôleur sans droits** : aucun statut, aucun contenu, mais les pods du contrôleur tournent.

```
admin@adm01:~$ kubectl logs -n kube-system deploy/snapshot-controller --tail=20
… volumesnapshots.snapshot.storage.k8s.io is forbidden: User "system:serviceaccount:kube-system:snapshot-controller" cannot list resource "volumesnapshots" …
admin@adm01:~$ kubectl get clusterrolebinding snapshot-controller-role
Error from server (NotFound): clusterrolebindings.rbac.authorization.k8s.io "snapshot-controller-role" not found
```

Le `ClusterRoleBinding` des manifestes d'external-snapshotter a été supprimé (« ménage des RBAC orphelins », audit `delete clusterrolebindings`). Correctif : réappliquer la kustomisation du code (elle inclut `rbac-snapshot-controller.yaml`), puis relancer les pods du contrôleur pour qu'ils repartent sans attendre leur prochaine tentative.

**Clôture commune** : l'instantané en attente devient prêt ; un nouvel instantané du témoin est prêt ; une sauvegarde Velero avec `--snapshot-move-data` de `wb-essais` se termine (M16-E17) ; `lab/bin/break 16 42 --annuler`, `lab/bin/check 16 42`, RB-166 section 4.

**Explications**

Les instantanés CSI ont deux moitiés. Le **contrôleur commun** (`snapshot-controller`, un par cluster) surveille les `VolumeSnapshot`, crée le `VolumeSnapshotContent` correspondant à partir de la classe et lie les deux. Le **sidecar** `csi-snapshotter` (dans le pod du provisioner du pilote) surveille les contenus de son pilote et appelle `CreateSnapshot` avec le Secret désigné par la classe. Sans contrôleur (v1, v3), rien n'est créé : aucun statut. Avec une classe fausse (v2), le contrôleur fait sa part, le sidecar échoue : le contenu porte l'erreur. Velero, quand il déplace les données d'instantanés, attend que l'instantané soit prêt : toutes ses sauvegardes de volumes se bloquent derrière.

**Alternatives**
- Contrôleur de snapshots fourni par le chart d'un pilote ou par la distribution : à éviter avec plusieurs pilotes (un seul contrôleur par cluster, versions des CRD à garder cohérentes).

**Pièges classiques**
- Supprimer et réinstaller les CRD `snapshot.storage.k8s.io` : tous les `VolumeSnapshot` et `VolumeSnapshotContent` disparaissent ; les images d'instantanés restent dans Ceph sans plus personne pour les gérer.
- Retirer les finaliseurs d'un instantané bloqué pour « nettoyer » : même effet, en plus petit.
- Ne regarder que le `VolumeSnapshot` : l'erreur est souvent seulement sur le contenu.

**En production chez MédiSphère**
Contrôle « instantanés non prêts depuis plus de 10 min » et « snapshot-controller disponible » (M16-E27) ; RBAC des composants uniquement par `plateforme/k8s` (et par Argo CD au M20, qui recréerait le lien supprimé) ; revue des « ménages RBAC » : un objet sans propriétaire Helm n'est pas forcément orphelin.

---
### M16-E43 — Astreinte : les données de MédiAgenda sont en danger

Il n'y a pas de solution unique : la combinaison est tirée parmi 12 (une panne de chaque famille, variantes au hasard). Le corrigé donne la **méthode de tri**, les interactions à connaître et la grille du post-mortem ; le diagnostic de chaque panne est celui des exercices M16-E35 à M16-E42.

**Démarche de diagnostic**

*1. Tri (15 min).* Pour chaque remontée, deux questions : *quelle donnée est exposée, et à quel risque ?* et *combien de temps avant que le risque se réalise ?*

| Famille | Risque sur les données | Horloge |
|---|---|---|
| A. Archivage des WAL (E41) | restauration à un instant donné bloquée à l'heure de la panne ; `pg_wal` qui grossit | heures (place du volume) ; chaque minute écrite est hors de la fenêtre de restauration |
| A. Bascule (E40) | aucune perte tant qu'on ne force rien ; écritures figées si la maintenance a commencé | immédiate si les écritures sont bloquées, sinon jusqu'à la maintenance |
| B. Velero (E39) | aucune sauvegarde d'espace valide ce soir | jusqu'à la prochaine sauvegarde planifiée |
| B. Instantanés (E42) | sauvegardes Velero de volumes bloquées derrière | idem |
| C. Volumes (E35, E36, E38) | aucune perte, création ou montage impossible ; E38 v2 fige toutes les écritures du pool | immédiate pour E38 v2, sinon jusqu'au prochain déploiement |
| C. Nœud perdu (E37) | **risque de double écriture** si l'on force ; une instance de base en moins | immédiate |

Ordre type : d'abord ce qui peut **corrompre ou perdre** (E37 avant toute procédure forcée, E38 v2 qui fige la base), puis ce qui empêche de **restaurer** (E41, puis E39/E42), enfin ce qui empêche de **créer** (E35, E36, E38 v1/v3). Écris l'ordre et la raison dans le journal avant d'agir : c'est ce que relira le post-mortem.

*2. Protéger.* Si l'archivage est en panne et que la base écrit, la dernière sauvegarde de base et le dernier WAL archivé fixent la fenêtre de restauration ; si la réparation risque de durer, un `pg_dump` logique de `mediagenda` vers `adm01` (chiffré, hors dépôt) est une protection rapide et indépendante de S3. Si un nœud est perdu, ne poser aucune teinte avant la preuve d'arrêt.

*3. Interactions à connaître.*
- E42 (instantanés bloqués) fait échouer ou pendre les sauvegardes Velero avec déplacement des données, sans que l'emplacement soit en cause : corriger E42 avant de conclure sur Velero.
- E37 (nœud perdu) fait basculer la base si le primaire y était, et la laisse sur deux instances (anti-affinité requise) ; E40 est alors exclu par l'injecteur (combinaisons exclues : E40 avec E36 ou E37).
- E38 v2 (pool plein) bloque aussi l'écriture des instantanés RBD et ralentit tout : sa correction fait souvent « disparaître » d'autres symptômes.
- Une panne réparée doit être **close** (`lab/bin/break 16 43 --annuler` à la fin) : l'annulation ne revient sur aucune réparation.

*4. Vérifier la restaurabilité avant de clore.* `velero backup create … --include-namespaces mediagenda-recette --wait` complète ; `kubectl cnpg backup mediagenda-db …` terminée et archivage à jour (`kubectl cnpg status`) ; un PVC de test créé et monté sur chaque travailleur (pod épinglé) ; `lab/bin/check 16 43` vert.

*5. Communication.* Points de 30 min au format : état (ce qui est rétabli, ce qui ne l'est pas), risque restant sur les données, prochaine action, heure du prochain point. Pas de cause annoncée avant d'être prouvée.

**Post-mortem attendu** (`docs/socle/post-mortems/AAAA-MM-JJ-INC-4350.md`, modèle du M00) : chronologie à la minute (injection, détection, chaque hypothèse, chaque correction, retour à la normale), impact (données exposées, durée de non-restaurabilité, écritures bloquées), causes racines (une par panne, puis le facteur commun : **des changements faits à la main hors du code** — Secret, classe, quota, PDB, clôture, étiquette de nœud), ce qui a bien marché (témoins, contrôles, runbooks), actions avec responsable et échéance : une **détection** par panne (contrôle `ms-verif-k8s-stockage`, alerte M21), une **prévention** par panne (GitOps M20 qui annule les dérives, admission, revue), et une action transverse (droits d'écriture de Lucas sur les composants de plateforme, M24).

**Explications**

L'astreinte entraîne ce que les exercices isolés n'entraînent pas : choisir quoi ne **pas** faire tout de suite, reconnaître qu'une panne en masque une autre, et ne déclarer la fin qu'après avoir prouvé la restaurabilité, puisque c'est elle que la recette de 8 h exige.

**Alternatives**
- Traiter dans l'ordre d'arrivée des remontées : plus simple à suivre, mais une base qui ne s'archive plus attend alors derrière un PVC Pending, et la fenêtre de restauration se dégrade pendant ce temps ; le tri par risque sur les données reste la règle.
- Répartir les trois pannes entre plusieurs personnes (en équipe) : plus rapide, à condition d'un responsable d'incident qui tient la chronologie et décide des priorités, et d'un canal unique pour les points.

**Pièges classiques**
- Traiter dans l'ordre d'arrivée des remontées.
- Corriger trois choses à la fois puis ne plus savoir laquelle a réparé quoi.
- Clore sans sauvegarde ni restauration vérifiées : « tout est vert » sauf le seul critère qui compte.
- Post-mortem qui accuse Lucas : les causes sont l'absence de garde-fous (droits, GitOps, admission), pas une personne.

**En production chez MédiSphère**
Exercices d'astreinte trimestriels avec ces scénarios (M29 : injection de pannes), indicateurs suivis (délai de détection, délai de rétablissement, durée de non-restaurabilité), revue des post-mortems en comité de changement.

---

### M16-E44 — Sous le capot : du PVC au bloc monté

**Solution**

Les sorties sont abrégées et représentatives (identifiants, empreintes et noms varient). Le modèle de note est dans [`fichiers/M16-E44/medisphere/docs/kubernetes/stockage/du-pvc-au-bloc.md`](fichiers/M16-E44/medisphere/docs/kubernetes/stockage/du-pvc-au-bloc.md), l'outil dans [`fichiers/M16-E44/outils/k8s-suivre-volume.sh`](fichiers/M16-E44/outils/k8s-suivre-volume.sh) (lecture seule, `shellcheck` propre).

*1. Observation.* Le provisioner a deux répliques ; chaque sidecar élit son leader par un `Lease` :

```
admin@adm01:~$ kubectl get lease -n ceph-csi
NAME                               HOLDER
external-attacher-leader-rbd-csi-ceph-com      ceph-csi-rbd-provisioner-…-abcde
external-resizer-rbd-csi-ceph-com              ceph-csi-rbd-provisioner-…-abcde
external-snapshotter-leader-rbd-csi-ceph-com   ceph-csi-rbd-provisioner-…-abcde
rbd-csi-ceph-com                               ceph-csi-rbd-provisioner-…-abcde         # csi-provisioner
```

*2. `CreateVolume`.*

```
csi-provisioner : … "Started provisioning" PVC="wb-essais/exploration"
csi-rbdplugin   : ID: 41 Req-ID: pvc-3f1c… GRPC call: /csi.v1.Controller/CreateVolume
                  ID: 41 Req-ID: pvc-3f1c… generated Volume ID (0001-0024-<FSID>-0000000000000005-7a0e…) and image name (csi-vol-7a0e…)
                  ID: 41 Req-ID: pvc-3f1c… created image k8s-rbd/csi-vol-7a0e… backed for request name pvc-3f1c…
csi-provisioner : … "Successfully provisioned volume" PV="pvc-3f1c…"
admin@adm01:~$ kubectl get pv pvc-3f1c… -o jsonpath='{.spec.csi}' | jq
{ "driver": "rbd.csi.ceph.com", "fsType": "ext4",
  "volumeHandle": "0001-0024-<FSID>-0000000000000005-7a0e…",
  "volumeAttributes": { "clusterID": "<FSID>", "imageName": "csi-vol-7a0e…", "journalPool": "k8s-rbd", "pool": "k8s-rbd", … } }
[admin@ceph01 ~]$ sudo rbd info k8s-rbd/csi-vol-7a0e…            # features : layering, exclusive-lock, object-map, fast-diff, deep-flatten
[admin@ceph01 ~]$ sudo rados -p k8s-rbd listomapvals csi.volumes.default
csi.volume.pvc-3f1c…
value (36 bytes) : 7a0e…                                         # nom du PV → UUID
[admin@ceph01 ~]$ sudo rados -p k8s-rbd listomapvals csi.volume.7a0e…   # UUID → nom de l'image, nom de la requête, propriétaire…
```

Le `volumeHandle` encode la version, le `clusterID`, l'identifiant du pool (5 ici, `ceph osd pool ls detail`) et l'UUID : le pilote retrouve l'image sans annuaire. L'annuaire omap sert l'**idempotence** : si `CreateVolume` est rejoué pour le même nom de PV (délai dépassé, redémarrage du sidecar), ceph-csi retrouve l'image déjà créée au lieu d'en créer une seconde ; c'est aussi lui qui rend possible l'erreur `Aborted … already exists` vue en M16-E38 v2.

*3. Attachement, staging, publication.*

```
admin@adm01:~$ kubectl get volumeattachment | grep pvc-3f1c…
csi-5c2e…   rbd.csi.ceph.com   pvc-3f1c…   k8s-w02   true
csi-attacher    : … "Attaching" VolumeAttachment="csi-5c2e…" ; ControllerPublishVolume … succeeded
csi-rbdplugin (nodeplugin de k8s-w02) :
  ID: 17 Req-ID: 0001-0024-… GRPC call: /csi.v1.Node/NodeStageVolume
  ID: 17 Req-ID: 0001-0024-… rbd: map mon 10.10.30.51:3300,10.10.30.52:3300,10.10.30.53:3300
  ID: 17 Req-ID: 0001-0024-… rbd image: k8s-rbd/csi-vol-7a0e… was successfully mapped at /dev/rbd0
  ID: 17 Req-ID: 0001-0024-… mkfs.ext4 … ; mount /dev/rbd0 → …/globalmount/0001-0024-…
  ID: 18 Req-ID: 0001-0024-… GRPC call: /csi.v1.Node/NodePublishVolume
```

Le `VolumeAttachment` est créé par le contrôleur attach/detach de `kube-controller-manager`, marqué attaché par `csi-attacher` après un `ControllerPublishVolume` qui, pour RBD, ne fait presque rien (le vrai « attachement » est le `rbd map` du staging) : il existe pour que Kubernetes applique la règle « un nœud » des volumes RWO et sache quand détacher (M16-E37).

*4. Sur le nœud.*

```
admin@k8s-w02:~$ lsblk | grep rbd
rbd0   251:0  0   1G  0 disk /var/lib/kubelet/pods/9d4b…/volumes/kubernetes.io~csi/pvc-3f1c…/mount
                             /var/lib/kubelet/plugins/kubernetes.io/csi/rbd.csi.ceph.com/8e1f…/globalmount/0001-0024-…
admin@k8s-w02:~$ for d in /sys/bus/rbd/devices/*; do echo "$d $(cat $d/pool)/$(cat $d/name)"; done
/sys/bus/rbd/devices/0 k8s-rbd/csi-vol-7a0e…
admin@k8s-w02:~$ printf '%s' '0001-0024-…' | sha256sum          # 8e1f… : le dossier du montage global
admin@k8s-w02:~$ PID=$(sudo crictl inspect "$(sudo crictl ps -q --name exploration)" | jq .info.pid)
admin@k8s-w02:~$ sudo nsenter -t "$PID" -m findmnt /donnees
TARGET    SOURCE    FSTYPE OPTIONS
/donnees  /dev/rbd0 ext4   rw,relatime,discard,…
[admin@ceph01 ~]$ sudo rbd status k8s-rbd/csi-vol-7a0e…
Watchers:  watcher=10.10.30.82:0/2718281828 client.24617 cookie=…        # le client noyau de k8s-w02, par sa carte VLAN 30
```

Le montage global (un par volume et par nœud) porte le système de fichiers ; le montage du pod (un par pod) est un *bind* du global, et c'est lui que le runtime monte dans l'espace de noms de montage du conteneur. Deux pods du même nœud partagent le montage global, d'où la nécessité de `ReadWriteOncePod` quand on veut un seul pod.

*5. Suppression.* `NodeUnpublishVolume` (le *bind* disparaît), `NodeUnstageVolume` (démontage global, `rbd unmap`, `/dev/rbd0` disparaît, plus d'observateur), `ControllerUnpublishVolume` (le `VolumeAttachment` disparaît), puis, à la suppression du PVC (classe en `Delete`), `DeleteVolume` : ceph-csi déplace l'image dans la **corbeille** RBD (`rbd trash ls k8s-rbd`) et programme sa purge par une tâche du mgr (d'où les droits mgr de `client.k8s`), puis retire les entrées omap.

*6. CephFS.* `ceph fs subvolume ls cephfs --group_name csi` montre `csi-vol-…`, `getpath` son chemin `/volumes/csi/csi-vol-…/<uuid>` ; sur chaque nœud, un montage `ceph` du sous-volume (client noyau, `findmnt -t ceph`), puis un *bind* par pod. Le CSIDriver du chart 3.18.1 déclare `attachRequired: true` : un `VolumeAttachment` existe par nœud, mais il n'y a pas de règle « un seul nœud » pour un volume RWX. Le RWX est possible parce que CephFS est un système de fichiers **distribué** avec cohérence gérée par le MDS (capacités, verrous) ; un ext4 sur RBD suppose un seul noyau propriétaire du système de fichiers.

*7-8.* Note et outil : voir les fichiers de solution ; l'outil est fusionné par MR dans `plateforme/outils`.

**Explications**

CSI découpe la vie d'un volume en appels idempotents, chacun porté par un composant et un objet : `CreateVolume`/`DeleteVolume` (provisioner, PV), `ControllerPublish`/`Unpublish` (attacher, `VolumeAttachment`), `NodeStage`/`Unstage` (kubelet et *nodeplugin*, montage global), `NodePublish`/`Unpublish` (kubelet et *nodeplugin*, montage du pod). Pour chaque panne du palier, l'étage s'est lu sur l'objet ou le journal de l'appel concerné : c'est la carte de diagnostic que la note doit transmettre.

**Alternatives**
- Observer par les métriques et traces plutôt que par les journaux : `csi_operations_seconds` du kubelet et des sidecars, traces des appels gRPC quand le pilote les expose ; c'est l'outillage du M21-M23, moins précis aujourd'hui que les journaux à la verbosité 5.
- `kubectl-df-pv`, `kubectl get --raw` vers `/api/v1/nodes/<N>/proxy/stats/summary`, ou un outil comme `rbd-nbd`/`rbd device list` pour la vue côté nœud : utiles en complément, mais ils ne relient pas à eux seuls PVC, PV, image, attachement et montage, ce que fait `k8s-suivre-volume.sh`.

**Pièges classiques**
- Faire l'exploration sur un témoin ou une base : un `nsenter` ou un `findmnt` ne casse rien, mais un démontage « pour voir » casse tout.
- Supprimer une image `csi-vol-…` à la main (Q10 de M16-E45).
- Confondre le nom du PV (`pvc-…`, choisi par le provisioner externe) et celui de l'image (`csi-vol-…`, choisi par ceph-csi).

**En production chez MédiSphère**
L'outil `k8s-suivre-volume.sh` est cité dans RB-160, RB-165 et RB-166 ; la note sert de support de formation des nouveaux arrivants et d'annexe de l'ADR-0160.

---

### M16-E45 — Questions expert : stockage dans Kubernetes

**1.** Non : `accessModes` d'un PVC lié est immuable ; il faut un nouveau PVC (copie, M16-E29) ou recréer le PV en `Retain` et un PVC en RWOP qui s'y lie. RWOP garantit qu'**un seul pod** du cluster utilise le volume (le planificateur et le kubelet le refusent à un second pod, même sur le même nœud, ce que RWO permet). Il n'apporte **pas** de garantie quand un nœud est injoignable : Kubernetes croit l'ancien pod en vie (ou le supprime de force avec `out-of-service`), et rien n'empêche le nœud perdu d'écrire : seule une clôture (arrêt, liste de blocage Ceph) le fait.

**2. Réponse (b).** Le contrôleur attach/detach ne connaît l'état « attaché à tel nœud » que par l'objet `VolumeAttachment` ; c'est lui qui applique la règle « un nœud » des volumes RWO et attend le détachement avant d'attacher ailleurs. (a) faux : le périphérique est trouvé par le pilote au staging ; (c) faux : `attachRequired: false` est permis (et utilisé par des pilotes sans notion d'attachement) ; (d) faux : Kubernetes ne pose aucun verrou dans Ceph (le verrou exclusif de RBD est géré par le client RBD lui-même, et coopératif).

**3.** `Immediate` : le volume est accessible depuis tous les travailleurs, rien à attendre, et l'erreur de provisionnement apparaît dès la création du PVC, pas au premier pod. `WaitForFirstConsumer` devient indispensable dès qu'il y a une **topologie** : stockage local (`local`, Longhorn en mode données locales, disques des travailleurs), zones ou sites (un volume de PAR2 inaccessible de PAR1), ou contraintes de nœud du pod (affinités) qui doivent passer avant le choix du volume.

**4.** Supprimer le pod ne change rien pour le contrôleur attach/detach : il attend que le kubelet du nœud confirme le démontage, et un nœud injoignable ne confirme rien. La teinte `out-of-service` est une **affirmation humaine** que le nœud est arrêté : Kubernetes supprime alors de force ses pods et détache leurs volumes sans attendre. Posée sur un nœud qui tourne, elle permet à un second nœud de mapper et monter la même image : deux noyaux écrivent dans le même ext4, qui n'a pas de coordination entre nœuds → corruption (métadonnées, journal). Le verrou exclusif de RBD passe d'un client à l'autre sans les empêcher d'écrire chacun à leur tour. Ceph protège par la **liste de blocage** : `ceph osd blocklist add <adresse>` (ou `NetworkFence` de csi-addons) rejette toute écriture de l'ancien client.

**5.** Velero crée un instantané CSI, l'expose dans un pod, et Kopia lit le volume **en entier** mais ne transfère que les **blocs (morceaux) nouveaux** par déduplication contre son dépôt : environ 2 Gio (compressés) plus les métadonnées. La restauration, elle, réécrit les 50 Gio dans un nouveau volume (Kopia réassemble les morceaux) : le RTO dépend de la taille totale, pas de la dernière différence. Un instantané CSI seul reste **dans Ceph** : rapide à prendre et à restaurer (clone), mais perdu avec le cluster Ceph ; ce n'est pas une sauvegarde hors site.

**6.** Une copie de fichiers d'un PostgreSQL en marche n'est pas cohérente (pages modifiées pendant la lecture, WAL non rejoué) ; un instantané CSI est cohérent au crash (PostgreSQL saura repartir, comme après une coupure de courant), mais sans PITR, sans vérification, et lié au moment de l'instantané. La sauvegarde de référence de la base est CloudNativePG (base + WAL archivés : restauration à la seconde). Dans Velero : exclure les volumes de la base (`backup.velero.io/backup-volumes-excludes` sur les pods ou étiquette `velero.io/exclude-from-backup=true` sur les PVC, à vérifier sur ta version), garder les objets (Cluster, Secrets, Services) pour reconstruire, la donnée venant de la restauration CloudNativePG (politique M16-E32).

**7.** Avec `s3-01` : jusqu'au dernier WAL archivé, il y a environ 6 h (base de 20 h + WAL jusqu'au début de la panne). Avec `pg_wal` du primaire, s'il est intact : jusqu'à l'instant présent, en rejouant les segments locaux (restauration plus délicate : copier les segments, ou simplement réparer l'archivage, qui les enverra). Si le volume du primaire se remplit, PostgreSQL ne peut plus écrire de WAL et s'arrête (PANIC) : la base est indisponible, et un redémarrage ne règle rien tant que l'archivage ou la place ne sont pas rétablis. D'où l'alerte sur `pg_wal`.

**8. Réponse (b).** En réplication asynchrone, une transaction est validée dès qu'elle est écrite dans le WAL **local** du primaire ; une réplique peut ne pas l'avoir reçue. Pour une bascule planifiée (*switchover*), CloudNativePG arrête proprement le primaire et attend que la réplique choisie ait reçu le WAL jusqu'à l'arrêt : en pratique, rien n'est perdu. Pour un drain qui force les choses ou une bascule non planifiée (*failover*), les transactions non reçues sont perdues. (a) faux en *failover* ; (c) faux : le point de contrôle n'a pas de rôle dans ce qui est répliqué ; (d) faux : l'archivage est une copie à part, la réplication en flux ne l'attend pas. Avec `mediagenda-db` en synchrone `dataDurability: required`, la réponse devient (a) même en *failover* : toute transaction validée existe sur une réplique synchrone.

**9.** (1) `rbd-nbd` (ou le montage par le client en espace utilisateur) dans le *nodeplugin* : il utilise les bibliothèques de Ceph du conteneur ceph-csi, qui peuvent connaître `aes256k` ; coût : performances moindres, et un redémarrage ou une mise à jour du *nodeplugin* coupe les volumes montés (à gérer par les fonctions de reprise de ceph-csi), donc une exploitation plus délicate. (2) Monter le noyau des travailleurs (noyau rétroporté ou distribution plus récente pour les nœuds, qui sait utiliser `aes256k`, Linux 7.0 d'après l'avis du M08) : coût de qualification, sortie du noyau Debian supporté, et image dorée à refaire. Dans les deux cas, renouveler ensuite la clé selon la procédure (Vault, Secret, Ceph, remontage contrôlé).

**10.** Le nom du PV est choisi par le provisioner externe, pas par ceph-csi ; `CreateVolume` doit être **idempotent** (rejoué après un délai dépassé, il ne doit pas créer une seconde image) : ceph-csi réserve d'abord le nom de requête dans l'omap, puis crée l'image, et retrouve l'image au rejeu. L'omap porte aussi les métadonnées nécessaires aux clones, instantanés et chiffrement. Image supprimée à la main, PV conservé : le PV est « lié » à un volume qui n'existe plus ; le prochain montage échoue (`image not found`), la suppression du PV échoue côté pilote ou laisse des entrées omap orphelines. PV supprimé sans passer par le pilote (classe `Retain`, ou finaliseur retiré) : l'image et son entrée omap restent dans `k8s-rbd`, invisibles de Kubernetes, et consomment le quota : c'est ce qu'il faut chercher quand le pool se remplit sans PVC correspondants (`rbd ls k8s-rbd` comparé aux `volumeAttributes.imageName` des PV).

**11.** *Rook (Ceph dans le cluster)* : un seul outil et un seul cycle de vie (déclaratif, GitOps) ; pas de dépendance à une équipe et à des VMs de stockage séparées ; données au plus près des charges (nœuds hyperconvergés). *ceph-csi vers `ceph-par1`* : le cluster Ceph survit à la perte ou à la reconstruction de `k8s-par1` (données hors du cluster qu'on reconstruit) ; un seul Ceph pour Kubernetes, OpenStack et le RGW de MédiDoc, déjà exploité, supervisé, sauvegardé (M08) ; mises à jour de Kubernetes et de Ceph découplées. Ce qui fait pencher l'ADR-0160 dans ce lab : la séparation des domaines de panne (reconstruire `k8s-par1` sans toucher aux données) et la mémoire (Rook sur les travailleurs ajoute MON, MGR et OSD à des nœuds de 8 Go) ; Rook en mode « externe » reste une option si l'on veut ses CRD sans ses démons.

**12.** Le kubelet obtient ces statistiques par l'appel CSI `NodeGetVolumeStats` (ou par `statfs` pour certains volumes intégrés) ; un `hostPath` n'est pas un volume géré à capacité définie, il ne remonte pas ces métriques. Pour CephFS, la métrique reflète ce que `statfs` du montage renvoie : avec un quota de sous-volume, le client noyau de CephFS remonte la taille et l'occupation **du quota** (option `quota` des montages récents, à vérifier) ; sans quota, la capacité du système de fichiers entier, partagée avec les autres sous-volumes, ce qui rend le pourcentage trompeur. Et l'occupation d'un sous-volume se met à jour avec un léger retard (statistiques récursives du MDS).
