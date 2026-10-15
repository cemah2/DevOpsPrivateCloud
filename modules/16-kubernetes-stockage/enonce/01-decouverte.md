# Module 16 — Palier 1 : Découverte

Avant de brancher le moindre pilote, il faut savoir **où** un conteneur écrit et ce qui survit à quoi. Ce palier commence par les volumes éphémères, puis pose à la main un PersistentVolume pour comprendre la liaison avec un PVC et son cycle de vie, et lit la spécification CSI. Il raccorde ensuite les travailleurs au réseau de stockage de `ceph-par1` par le code, installe ceph-csi pour le bloc (RBD) puis pour le fichier partagé (CephFS), observe le pilote au travail, et termine par le Valkey de MédiAgenda passé en StatefulSet persistant. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : modules 14 et 15 terminés (`lab/bin/check 15 46` vert), module 08 (`lab/bin/check 08 46` vert : `ceph-par1`, pool `k8s-rbd`, identité `client.k8s`, CephFS). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les règles du module (ordre d'arrêt des deux clusters).

> **Rappels du module** : une carte réseau passe par OpenTofu (état `k8s`), une configuration de nœud par un rôle Ansible joué nœud drainé, un composant du cluster par `plateforme/k8s` (MR), une identité Ceph par `plateforme/ceph` (`allocations.yaml`), une clé cephx par Ansible Vault (`critique`) et jamais par Git. Les essais se font dans `wb-essais`. Les commandes `kubectl` d'action se lancent depuis `adm01` avec ton identité (`~/.kube/config`) ; les commandes Ceph en root sur `ceph01` (`admin@ceph01:~$ sudo ceph …` ou `[admin@ceph01 ~]$ sudo ceph …`).

---

### M16-E01 — Test de positionnement : stockage dans Kubernetes  `Q` `★★`

> **Ticket PLAT-1701** — *De : Karim Benali*
> Le rituel, comme à chaque module : une heure, par écrit, sans moteur de recherche ni IA, sans rien exécuter. Montages Linux, cycle de vie des pods, sauvegarde et cohérence des données : ce que le stockage de Kubernetes suppose acquis. Réponds même là où tu hésites, le raisonnement compte.

**Objectifs pédagogiques**
- Évaluer tes acquis sur les montages Linux, les volumes de Kubernetes et la protection des données avant de construire le stockage du cluster.
- Repérer les notions à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Montages et systèmes de fichiers sous Linux*

1. Qu'est-ce qu'un **montage lié** (*bind mount*) ? Donne un exemple de commande et un usage hors conteneurs.

2. Les espaces de noms de montage ont une **propagation** : `private`, `shared`, `slave`. Explique chacune en une phrase. Pourquoi un processus qui monte des volumes **pour d'autres conteneurs** a-t-il besoin d'une propagation particulière ?

3. *(QCM)* Un client NFS monté en `hard` perd son serveur au milieu d'une écriture. Le processus qui écrit :
   - A. Reçoit immédiatement une erreur `EIO`
   - B. Reste bloqué en état `D` (sommeil non interruptible) jusqu'au retour du serveur
   - C. Écrit dans le cache local et continue sans attendre
   - D. Est tué par le noyau au bout de 60 secondes

4. Compare **ext4** et **XFS** sur trois points : agrandissement à chaud, réduction, comportement quand on monte deux fois le même système de fichiers cloné.

5. Quelle est la différence entre un périphérique **bloc** donné à un processus et un **système de fichiers** monté pour lui ? Cite une application qui préfère le premier.

*Pods et volumes*

6. Un conteneur écrit un fichier dans `/tmp`. Dis si le fichier survit : (a) à un redémarrage du conteneur par le kubelet, (b) à la suppression du pod par un `kubectl rollout restart`, (c) à un redémarrage du nœud. Même question pour un fichier écrit dans un volume `emptyDir`.

7. *(QCM)* Un Deployment de 3 réplicas monte **un** PVC en `ReadWriteOnce`. Les trois pods :
   - A. Démarrent et partagent le volume, quel que soit leur nœud
   - B. Démarrent si et seulement s'ils sont placés sur le même nœud ; les autres restent bloqués
   - C. Reçoivent chacun leur propre PVC
   - D. Sont refusés par l'API

8. Pourquoi une base de données se déploie-t-elle en **StatefulSet** plutôt qu'en Deployment ? Donne deux garanties précises du StatefulSet.

9. En une phrase chacun : **PersistentVolume**, **PersistentVolumeClaim**, **StorageClass**. Lequel est un objet d'espace de noms ?

10. *(QCM)* Tu supprimes un PVC encore monté par un pod en marche. Il se passe :
    - A. Le PVC disparaît et le pod reçoit des erreurs d'E/S
    - B. Le PVC passe en `Terminating` et n'est supprimé qu'après l'arrêt du dernier pod qui l'utilise
    - C. L'API refuse la suppression
    - D. Le PVC est supprimé, le PV reste attaché au pod

11. Un travailleur s'éteint brutalement. Que deviennent, et au bout de combien de temps environ, (a) les pods d'un Deployment sans volume, (b) le pod d'un StatefulSet qui monte un volume RWO ?

12. Le pilote de stockage a besoin d'une clé pour parler à Ceph. Elle sera dans un **Secret**. Qui peut la lire dans le cluster ? Où est-elle stockée, et sous quelle forme depuis M14-E28 ?

*Protection des données*

13. Définis **RPO** et **RTO**. Donne un exemple chiffré pour la base de MédiAgenda et dis ce qui les détermine techniquement.

14. Distingue un instantané **cohérent après plantage** (*crash-consistent*) et un instantané **cohérent applicativement**. Lequel obtiens-tu en photographiant le disque d'un PostgreSQL en marche, et est-ce grave ?

15. *(QCM)* Copier le répertoire de données d'un PostgreSQL **en marche** avec `rsync` donne :
    - A. Une sauvegarde valide, car PostgreSQL écrit de façon atomique
    - B. Une copie probablement incohérente, inutilisable sans les WAL de la période de copie et une procédure de sauvegarde de base
    - C. Une copie valide si on la fait deux fois de suite
    - D. Une copie valide si le volume est sur Ceph

16. Réplication **synchrone** et **asynchrone** d'une base : effet sur le RPO, sur la latence des écritures, et ce qui se passe quand la réplique tombe.

17. Donne deux arguments **pour** et deux arguments **contre** l'exécution de bases de données dans Kubernetes.

*Le lien avec Ceph*

18. Rappelle à quoi sert la fonctionnalité **`exclusive-lock`** d'une image RBD. Que se passe-t-il quand un client qui tenait le verrou disparaît sans le rendre ?

19. RBD ou CephFS : lequel pour (a) la base PostgreSQL, (b) les pièces jointes partagées par deux instances de Legacy-RDV, (c) les journaux d'un Valkey ? Justifie.

20. Le pool `k8s-rbd` a un quota de 20 Gio. Les images RBD sont allouées à la demande. Les équipes créent des PVC dont la somme des tailles atteint 50 Gio. Est-ce possible ? Que se passe-t-il le jour où le pool atteint son quota, côté Ceph et côté pod ?

**Critères de réussite**
- [ ] Les 20 réponses sont rédigées avant toute consultation du corrigé.
- [ ] Auto-correction faite avec le barème du corrigé ; les notions à revoir sont notées dans ton journal de bord.

<details><summary>Indice 1</summary>

Pour les questions sur les pods, raisonne en « durée de vie » : celle du conteneur, celle du pod, celle du nœud, celle d'un objet de l'API. Chaque type de volume s'attache à l'une d'elles.
</details>

<details><summary>Indice 2</summary>

Pour la question 11, pense à ce que le plan de contrôle **sait** quand un nœud ne répond plus : il ne sait pas si le nœud est éteint ou seulement coupé du réseau, et donc si le volume est encore utilisé.
</details>

---

### M16-E02 — Volumes éphémères, `emptyDir` et `hostPath`  `LAB` `★`

> **Ticket DEV-1702** — *De : Julien Petit*
> Hier, MédiDoc a perdu ses fichiers temporaires de conversion au milieu d'un traitement : le conteneur a redémarré. Un collègue propose de « monter un répertoire du nœud, comme ça c'est persistant ». Sophie a répondu « non » en majuscules. Avant qu'on ait des volumes Ceph, j'aimerais savoir précisément où un conteneur peut écrire, ce qui survit à quoi, et pourquoi le répertoire du nœud est une mauvaise idée.

**Objectifs pédagogiques**
- Distinguer la couche inscriptible du conteneur, `emptyDir` (disque et mémoire) et les volumes projetés, et leur durée de vie.
- Limiter un `emptyDir` (`sizeLimit`) et observer ce que fait le kubelet quand la limite est dépassée.
- Comprendre ce qu'un volume `hostPath` donne à un pod, et le refus de Pod Security.

**Prérequis** : M14-E18 (Pod Security Admission), espace `wb-essais`.
**Durée indicative** : 1 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Espace | `wb-essais` (PSA `baseline` en `enforce`, M14-E18) |
| Image d'essai | `registry.par1.medisphere.internal/dockerhub/library/busybox:1.37` (cache Harbor) |
| Objets à laisser en place | ConfigMap `e02-config` ; pod `e02-ephemere` (conteneur `app`) avec trois volumes : `travail` (`emptyDir` sur disque, `sizeLimit` 200 Mio), `cache` (`emptyDir` en mémoire, `sizeLimit` 32 Mio), `config` (`projected` : la ConfigMap, l'API descendante et un jeton de compte de service d'audience `wb-essais`, 600 s) |
| Espace temporaire | `wb-privilegie` (PSA `privileged`), créé pour l'étape 6 et **supprimé** à la fin |

**Travail demandé**

*A. La couche du conteneur et `emptyDir`*

1. Écris le pod `e02-ephemere` dans `~/m16/e02/` : au démarrage, le conteneur ajoute une ligne horodatée dans `/tmp/couche` (sa couche inscriptible) **et** dans `/travail/journal` (le volume `travail`), puis attend ; il se termine en erreur dès que le fichier `/tmp/arret` existe. Respecte au passage le profil `restricted` (utilisateur non root, capacités retirées, `seccompProfile`), même si l'espace n'exige que `baseline`.
2. Crée `/tmp/arret` dans le conteneur (`kubectl exec`). Le kubelet redémarre le conteneur : compte les lignes des deux fichiers. Supprime puis recrée le pod : compte encore. Écris dans `~/m16/e02/notes.md` ce qui survit à quoi.
3. Trouve sur le nœud le répertoire qui porte `travail` : l'UID du pod (`kubectl get pod -o jsonpath`) et `/var/lib/kubelet/pods/<UID>/volumes/` sur le travailleur (lecture seule, `sudo ls`). Sur quel disque du nœud est-il ? Que se passerait-il si plusieurs pods remplissaient leurs `emptyDir` ?

*B. Les limites*

4. Crée un second pod `e02-gourmand` avec un `emptyDir` de `sizeLimit` 100 Mio, qui y écrit 150 Mio (`dd`). Observe son état et ses événements pendant une minute. Qui a agi, et sur quel critère ? Supprime-le.
5. Dans `e02-ephemere`, écris 64 Mio dans `/cache` (le volume en mémoire). Que dit `df -h /cache` dans le conteneur, quel message obtiens-tu, et à quelle ressource du pod cette mémoire est-elle comptée ? Efface le fichier.

*C. Les volumes projetés*

6. Lis les fichiers de `/config` : la ConfigMap, les étiquettes et la limite mémoire exposées par l'API descendante, le jeton. Décode la charge utile du jeton (sans le recopier ailleurs que dans ton terminal) : audience, expiration. Modifie une clé de la ConfigMap : combien de temps faut-il pour que le fichier change dans le pod ? Et une variable d'environnement tirée de la même ConfigMap ?

*D. `hostPath`*

7. Essaie de créer dans `wb-essais` un pod qui monte en `hostPath` le répertoire `/var/lib/kubelet/pki` du nœud. Note le message exact et qui le produit.
   > ⚠️ **Attention** : l'étape suivante crée un espace **sans aucune restriction** de Pod Security. N'y lance que le pod de l'énoncé, en lecture seule, et supprime l'espace à la fin de l'étape. Ne lis le contenu d'aucun fichier de clé.
8. Crée l'espace `wb-privilegie` (étiquette `pod-security.kubernetes.io/enforce: privileged`) et le même pod, volume en lecture seule. Liste (`ls -l`, sans `cat`) ce que le pod voit. Écris dans tes notes, en trois phrases, ce que pourrait faire quelqu'un qui a seulement le droit de créer des pods dans un espace `privileged`. Supprime l'espace `wb-privilegie`.

**Critères de réussite**
- [ ] Le pod `e02-ephemere` tourne dans `wb-essais` avec les trois volumes du contexte technique (tailles, médium, sources projetées, audience et durée du jeton) et un contexte de sécurité compatible `restricted`.
- [ ] Son conteneur a redémarré au moins une fois (`RESTARTS` ≥ 1) et `/travail/journal` a plus de lignes que `/tmp/couche`.
- [ ] Le pod `e02-gourmand` n'existe plus ; l'espace `wb-privilegie` n'existe plus.
- [ ] Aucun pod des espaces `wb-*` et `mediagenda-*` ne monte de volume `hostPath`, et `wb-essais` n'est pas en `privileged`.

**Vérification** : `lab/bin/check 16 02`

<details><summary>Indice 1</summary>

`kubectl explain pod.spec.volumes.emptyDir` et `kubectl explain pod.spec.volumes.projected.sources` donnent tous les champs. Un `exit 1` dans une boucle `while sleep 2; do … done` suffit à arrêter le conteneur ; `restartPolicy` par défaut d'un pod fait le reste.
</details>

<details><summary>Indice 2</summary>

Le kubelet surveille l'occupation des volumes locaux à intervalles réguliers : le dépassement d'un `sizeLimit` se lit dans les **événements** du pod et dans son `status.reason`. Pour le volume en mémoire, compare la taille montrée par `df` avec `sizeLimit` et avec la limite mémoire du conteneur.
</details>

<details><summary>Indice 3</summary>

Un fichier projeté est un **lien symbolique** vers un répertoire horodaté que le kubelet remplace d'un coup : regarde `ls -la /config`. Une variable d'environnement, elle, est fixée au démarrage du processus. Pour décoder un jeton JWT, la charge utile est la deuxième partie (séparateur `.`), en base64url.
</details>

**Pour aller plus loin** (facultatif) : lis la page *Ephemeral Volumes* (volumes éphémères **génériques**, `ephemeral.volumeClaimTemplate`) : en quoi diffèrent-ils d'un `emptyDir` une fois ceph-csi installé (E06) ? Et les volumes d'image (`image`, GA en 1.36) ?

---

### M16-E03 — PV, PVC et StorageClass : le cycle de vie d'un volume  `LAB` `★★`

> **Ticket PLAT-1703** — *De : Karim Benali*
> Avant d'installer un pilote qui fait tout tout seul, je veux que tu aies fait une fois à la main ce qu'il fera : un PV posé par l'admin, un PVC demandé par une équipe, la liaison, la libération, la réutilisation. Avec un disque local, pour voir aussi ce que ça coûte d'attacher une donnée à un nœud. Et je veux savoir ce que veulent dire RWO, RWOP et RWX sans regarder la doc.

**Objectifs pédagogiques**
- Créer un PV statique (`local`) et une StorageClass sans *provisioner* ; lier un PVC, comprendre `WaitForFirstConsumer`.
- Suivre les phases d'un PV et d'un PVC (`Available`, `Bound`, `Released`), les finaliseurs de protection, la politique `Retain`.
- Éprouver les modes d'accès et la contrainte de nœud d'un volume local.

**Prérequis** : M16-E02.
**Durée indicative** : 2 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Répertoire du volume | `/srv/wb-local/e03` sur `k8s-w01`, créé à la main pour l'essai (`sudo mkdir -p`, propriétaire `root`, mode `0777`) |
| StorageClass | `local-manuel` : aucun *provisioner* (`kubernetes.io/no-provisioner`), liaison différée, **pas** classe par défaut |
| PV | `e03-local-w01` : 1 Gio, `ReadWriteOnce`, `Filesystem`, `local.path` = le répertoire, affinité de nœud `k8s-w01`, `Retain`, classe `local-manuel` |
| PVC | `wb-essais/e03-donnees` : 500 Mio, `ReadWriteOnce`, classe `local-manuel` |
| Pods | `e03-ecrivain`, `e03-lecteur` (busybox de E02, profil `restricted` sauf l'utilisateur : root pour écrire dans le répertoire du nœud) |

**Travail demandé**

*A. Le décor*

1. Lis `kubectl explain pv.spec`, `pvc.spec`, `storageclass` (champs `provisioner`, `reclaimPolicy`, `volumeBindingMode`, `allowVolumeExpansion`) et `kubectl get sc,pv -A`. Le cluster a-t-il une classe par défaut ? Que deviendrait un PVC sans `storageClassName` aujourd'hui, et le jour où une classe par défaut apparaîtra ?
2. Crée le répertoire sur `k8s-w01`, puis `local-manuel` et `e03-local-w01`. Phase du PV ?

*B. Liaison*

3. Crée le PVC `e03-donnees`. Phase ? Lis ses événements : pourquoi n'est-il pas lié tout de suite ?
4. Crée `e03-ecrivain`, qui monte le PVC sur `/donnees` et y ajoute une ligne horodatée toutes les 10 s dans `/donnees/trace`. Où est-il placé, et qui l'a décidé ? Quelle **capacité** affiche maintenant le PVC, et pourquoi pas 500 Mio ? Vérifie le fichier sur le nœud.
5. Crée `e03-lecteur`, qui monte le même PVC et affiche `trace`. Démarre-t-il ? Sur quel nœud ? Qu'est-ce que cela dit de `ReadWriteOnce` ?
6. Crée un PVC `e03-partage` en `ReadWriteMany` dans la même classe, et un pod qui le monte. Lis l'état du pod et les événements. Supprime-les. Pourquoi le mode `ReadWriteOncePod` ne peut-il pas être essayé ici ? (Tu l'essaieras en E06.)

*C. Libération et réutilisation*

7. Supprime le PVC **pendant** que les pods tournent : état du PVC, finaliseurs (`kubectl get pvc -o jsonpath='{.metadata.finalizers}'`) ? Supprime les deux pods : que deviennent le PVC, puis le PV ? Les données sur le nœud ?
8. Recrée `e03-donnees` à l'identique. Se lie-t-il au PV ? Lis `spec.claimRef` du PV. En tant qu'administrateur, rends le PV de nouveau disponible **sans effacer les données** (elles appartiennent à l'équipe qui les retrouve), puis vérifie que le nouveau PVC se lie et qu'un nouveau `e03-ecrivain` retrouve les lignes d'avant. Écris dans `~/m16/e03/notes.md` la procédure, et ce qu'il faudrait faire en plus si le volume devait servir à **une autre** équipe.
9. Lis `kubectl explain pvc.spec.volumeMode`. Que changerait `Block` pour le pod ? (Pratique en E11.)
10. Supprime le pod `e03-ecrivain`. Garde le PV, la classe et le PVC lié jusqu'à la vérification : ensuite, ils pourront disparaître (E05 drainera `k8s-w01`).

**Critères de réussite**
- [ ] La StorageClass `local-manuel` n'a pas de *provisioner*, lie en différé et n'est pas la classe par défaut.
- [ ] Le PV `e03-local-w01` est conforme au contexte technique et lié (`Bound`) au PVC `wb-essais/e03-donnees`, lui-même `Bound` dans `local-manuel`, **après** avoir été libéré et réutilisé (le PVC lié est plus récent que le PV de plusieurs minutes).
- [ ] `/srv/wb-local/e03/trace` sur `k8s-w01` contient des lignes écrites avant **et** après la réutilisation.
- [ ] Il ne reste ni PVC `e03-partage` ni pod `e03-*` dans `wb-essais`.

**Vérification** : `lab/bin/check 16 03`

<details><summary>Indice 1</summary>

Un volume `local` exige une affinité de nœud (`spec.nodeAffinity.required`) : c'est elle que lit le planificateur, et c'est pour cela que la documentation conseille `WaitForFirstConsumer` avec ce type de volume. Un PVC en attente de son premier consommateur l'écrit dans ses événements.
</details>

<details><summary>Indice 2</summary>

Un PV `Released` garde la référence (`claimRef`) du PVC disparu, UID compris : aucun autre PVC ne peut s'y lier, même homonyme. C'est l'administrateur qui décide quoi faire des données, puis qui retire ou corrige cette référence (`kubectl patch pv … --type json`).
</details>

<details><summary>Indice 3</summary>

Pour réserver un PV à un PVC précis avant même que le PVC existe, on remplit soi-même `spec.claimRef` (nom et espace, sans UID). Pour un PVC qui ne doit **jamais** recevoir la classe par défaut, on écrit `storageClassName: ""` explicitement : depuis Kubernetes 1.28, un PVC sans classe reçoit rétroactivement la classe par défaut quand elle apparaît.
</details>

**Pour aller plus loin** (facultatif) : lis le projet *sig-storage-local-static-provisioner* : que fait-il de plus que ton PV écrit à la main, et pourquoi reste-t-il utile pour des disques NVMe locaux de bases de données répliquées par l'application ?

---

### M16-E04 — Comprendre CSI  `LAB` `★★`

> **Ticket PLAT-1704** — *De : Karim Benali*
> Dans trois semaines, quelqu'un d'astreinte verra un pod bloqué en `ContainerCreating` avec un message `rpc error: code = Internal desc = …`. Il faudra savoir quel composant a appelé quoi, sur quelle machine, et où lire le journal. Lis la spécification, puis regarde un vrai pilote travailler, et écris la fiche que tu aurais voulu trouver.

**Objectifs pédagogiques**
- Connaître les trois services CSI (Identity, Controller, Node) et les appels du cycle de vie d'un volume.
- Relier chaque appel au composant Kubernetes qui le déclenche (sidecars, kubelet) et à l'objet qu'il crée ou met à jour (`PersistentVolume`, `VolumeAttachment`, `CSINode`).
- Retrouver ces étapes dans les événements et les journaux d'un pilote réel.

**Prérequis** : M16-E03 pour la partie A ; M16-E06 pour la partie B.
**Durée indicative** : 2 h (partie A : 45 min ; partie B : 1 h 15).

**Contexte technique**

| Élément | Valeur |
|---|---|
| Spécification | <https://github.com/container-storage-interface/spec/blob/master/spec.md> (sections *RPC Interface* et *Volume Lifecycle*) |
| Pilote observé (partie B) | ceph-csi RBD de E06 : `CSIDriver` `rbd.csi.ceph.com` ; pods `ceph-csi-rbd-provisioner-…` (plusieurs conteneurs) et `ceph-csi-rbd-nodeplugin-…` (un par travailleur) dans `ceph-csi` |
| Volume observé | PVC `wb-essais/e06-essai` et pod `e06-essai` de E06 |
| Fiche à écrire | `docs/kubernetes/stockage/csi.md` dans `plateforme/medisphere` |

**Travail demandé**

*A. La spécification, et un cluster qui ne sait encore rien (avant E05)*

1. Dans la spécification, liste les appels des trois services. Pour chacun de ceux-ci : `CreateVolume`, `ControllerPublishVolume`, `NodeStageVolume`, `NodePublishVolume`, `NodeExpandVolume`, `CreateSnapshot`, dis en une ligne ce qu'il fait et s'il est **obligatoire** pour un pilote.
2. Lis le schéma de cycle de vie d'un volume (états `CREATED`, `NODE_READY`, `VOL_READY`, `PUBLISHED`). Pourquoi deux étapes côté nœud (*stage* puis *publish*) ?
3. Sur le cluster : `kubectl get csidrivers`, `kubectl get csinodes -o yaml` (champ `drivers`), et sur `k8s-w01` : `sudo ls /var/lib/kubelet/plugins_registry/ /var/lib/kubelet/plugins/`. Que sait le cluster du stockage avant tout pilote ?
4. Dans la documentation des développeurs CSI (<https://kubernetes-csi.github.io/docs/>), trouve le rôle de chaque *sidecar* : `external-provisioner`, `external-attacher`, `external-resizer`, `external-snapshotter`, `node-driver-registrar`, `livenessprobe`. Lesquels tournent à côté de la partie *Controller* du pilote, lesquels à côté de la partie *Node* ? Qui, côté Kubernetes, appelle `NodeStageVolume` ?

*B. Un vrai pilote (après E06)*

5. Liste les conteneurs des pods du *provisioner* et du *nodeplugin* (`kubectl get pod -o jsonpath='{.spec.containers[*].name}'`). Rapproche-les de ta liste de l'étape 4. Lequel est le pilote lui-même ?
6. Lis le `CSIDriver` `rbd.csi.ceph.com` (`attachRequired`, `podInfoOnMount`, `fsGroupPolicy`) et le `CSINode` d'un travailleur, puis d'un nœud de contrôle. Refais l'étape 3 sur `k8s-w01`.
7. Supprime puis recrée le pod `e06-essai` (même PVC) et suis l'opération : `kubectl get volumeattachment -w` dans un terminal, les événements du pod dans un autre. Puis lis les journaux : conteneur `csi-attacher` du *provisioner* (leader), conteneur `csi-rbdplugin` du *nodeplugin* du nœud qui reçoit le pod (cherche les appels gRPC). Retrouve, avec leurs heures, `ControllerPublishVolume`, `NodeStageVolume`, `NodePublishVolume`. Et à la suppression, les appels inverses.
8. Crée un PVC jetable `e04-jetable` (1 Gio, classe par défaut) et retrouve dans les journaux du conteneur `csi-provisioner` et `csi-rbdplugin` du *provisioner* l'appel `CreateVolume`, puis l'objet PV créé (`spec.csi.volumeHandle`, `volumeAttributes`). Supprime-le et retrouve `DeleteVolume`.
9. Écris `docs/kubernetes/stockage/csi.md` : un tableau « étape → appel CSI → qui appelle → où ça tourne → objet ou trace visible → où lire le journal », de la création du PVC à sa suppression, avec tes heures observées ; et la liste des commandes à lancer, dans l'ordre, devant un pod en `ContainerCreating`. MR, fusion.

**Critères de réussite**
- [ ] Le `CSIDriver` `rbd.csi.ceph.com` existe, et chaque travailleur raccordé (et seulement eux) le déclare dans son `CSINode`.
- [ ] Un `VolumeAttachment` attaché relie le PV du PVC `e06-essai` au nœud où tourne le pod `e06-essai`.
- [ ] Il ne reste pas de PVC `e04-jetable`.
- [ ] `docs/kubernetes/stockage/csi.md` est sur `main` et nomme les appels `CreateVolume`, `ControllerPublishVolume`, `NodeStageVolume`, `NodePublishVolume` et l'objet `VolumeAttachment`.

**Vérification** : `lab/bin/check 16 04` (après E06)

<details><summary>Indice 1</summary>

Un pod de *provisioner* a plusieurs réplicas, mais un seul **leader** par sidecar travaille : les autres attendent. Le bail (`kubectl get lease -n ceph-csi`) dit qui. Les journaux d'un pod non leader sont presque vides.
</details>

<details><summary>Indice 2</summary>

`kubectl logs -n ceph-csi <pod> -c <conteneur> --since=10m | grep -E 'GRPC call|GRPC response'` : le pilote ceph-csi journalise chaque appel reçu (les secrets sont masqués). Côté nœud, le kubelet journalise aussi ses opérations de volume : `journalctl -u kubelet --since "-10 min"` sur le travailleur.
</details>

<details><summary>Indice 3</summary>

`NodeStageVolume` prépare le volume **une fois par nœud** dans un répertoire global du kubelet (`…/plugins/kubernetes.io/csi/…/globalmount`) ; `NodePublishVolume` le monte (montage lié) dans le répertoire **du pod**. Deux pods du même nœud sur le même volume RWO : un *stage*, deux *publish*. Le détail des montages est l'objet de M16-E44.
</details>

---

### M16-E05 — Raccorder les travailleurs au réseau de stockage  `LAB` `★★`

> **Ticket PLAT-1705** — *De : Karim Benali*
> Les travailleurs n'ont qu'une carte, sur le VLAN 40. Pour joindre les moniteurs et les OSD de `ceph-par1`, ils passeraient par la bordure : chaque écriture de chaque volume routée et filtrée par `gw01`, en 1500 octets. Non. Donne-leur une carte sur le VLAN 30, en *jumbo frames*, sans passerelle, par le code, un nœud à la fois et nœud drainé. Et je veux que rien ne change pour Kubernetes : même adresse de nœud, même routage par défaut.
>
> *Sophie Laurent, en copie* : et je veux que la clé SSH des nœuds ne change pas au passage. On a déjà vu cloud-init régénérer les clés d'hôte d'une VM pour une modification de son lecteur.

**Objectifs pédagogiques**
- Ajouter une carte à des VMs existantes par OpenTofu sans les recréer, et la configurer par Ansible (netplan, MTU, sans passerelle).
- Protéger un nœud contre les effets de bord de cloud-init quand la configuration de son lecteur change.
- Appliquer un changement de nœud sans interruption de service : drain, changement, vérification, remise en service, un nœud à la fois.

**Prérequis** : M14 (état `k8s`, rôles des nœuds, drain), M10-E02 (cartes à MAC imposée, netplan), M07-E15 (MTU 9000 sur le VLAN 30).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Cartes | `net1` des seuls travailleurs `k8s-w01-03` (2144-2146) : VNet `vstopub`, MTU 9000, MAC `bc:24:11:30:00:61`, `:62`, `:63` ; adresse 10.10.30.81, .82, .83/24 (règle : dernier octet de l'adresse VLAN 40 + 20), **sans passerelle** ; nom `eth1` dans l'invité |
| OpenTofu | état `k8s` (`plateforme/infra`, `envs/k8s/`), module `vm-noeud` (`?ref=<VERSION-TOFU-MODULES>`) : liste `cartes` des travailleurs ; adresses enregistrées dans NetBox par le module |
| Ansible | rôle `k8s_reseau_stockage` (nouveau), playbook `playbooks/k8s-reseau-stockage.yml` sur le groupe `k8s_travailleurs`, `serial: 1` ; fichier netplan `/etc/netplan/60-stockage.yaml` ; modules noyau `rbd` et `ceph` chargés au démarrage ; étiquette de nœud `medisphere.internal/stockage-ceph=oui` posée **après** vérification |
| Moniteurs | 10.10.30.51, .52, .53 (ports 3300 et 6789 en écoute ; seul 3300 servira) |
| Documentation | ligne « travailleurs → `ceph-par1` » dans `docs/socle/matrice-flux.md` |

**Travail demandé**

*A. Préparer sans rien casser*

1. Sur `k8s-w01` : `ip -br link`, `ip route`, `ls /etc/netplan/`, `sudo cloud-init query instance_id` (note la valeur), `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` (note l'empreinte), `kubectl get node k8s-w01 -o wide` (adresse interne). Qui a écrit la configuration réseau actuelle du nœud ?
2. Sur `pve01`, lis `qm config 2144` (cartes, lecteur cloud-init) et la documentation de Proxmox sur cloud-init : d'où vient l'identifiant d'instance que voit cloud-init, et que fera cloud-init au prochain démarrage si cet identifiant change ? Note les deux effets qui inquiètent Sophie et Karim.
3. Écris le rôle `k8s_reseau_stockage` : il empêche cloud-init de reprendre la main sur le réseau et de régénérer les clés d'hôte, charge les modules noyau, écrit et **valide** (`netplan generate` dans un dossier de répétition) le fichier netplan de la carte reconnue par sa MAC, puis, **seulement** si la carte est présente et pas encore configurée, draine le nœud, le redémarre, vérifie la carte (adresse, MTU, aucune route par défaut, ping sans fragmentation de 9000 octets vers les trois moniteurs) et pose l'étiquette. Un nœud déjà conforme ne doit être ni drainé ni redémarré.
4. Joue le playbook sur les trois travailleurs **avant** d'ajouter les cartes. Qu'a-t-il fait sur chacun ? (Rien ne doit avoir redémarré.)

*B. Un travailleur à la fois*

5. `kubectl drain k8s-w01 --ignore-daemonsets --delete-emptydir-data`. Ajoute la carte de `k8s-w01` seulement dans l'état `k8s` ; `tofu plan` : lis-le (la VM doit être **modifiée**, pas remplacée ; NetBox reçoit une interface et une adresse). MR, `apply` par le pipeline. Selon la version du fournisseur, l'`apply` peut redémarrer la VM : c'est pour cela que le nœud est drainé.
6. Joue le playbook limité à `k8s-w01`. Vérifie toi-même : `ip -d link show eth1` (MTU), `ip route` (aucune route par défaut par `eth1`), `ping -M do -s 8972 -c 3 -I eth1 10.10.30.51`, `ip route get 10.10.30.52` (par quelle carte ?), empreinte de la clé d'hôte, `sudo cloud-init query instance_id`, adresse interne du nœud. Remets le nœud en service (`kubectl uncordon`) si le playbook ne l'a pas fait, et attends que les pods reviennent.
7. Depuis un pod **non** `hostNetwork` placé sur `k8s-w01` (image Debian du cache Harbor, `kubectl run … --overrides` avec un `nodeSelector`), teste `timeout 3 bash -c '</dev/tcp/10.10.30.51/3300'`. Le paquet sort par quelle carte, avec quelle adresse source ? Pourquoi est-ce que ça marche (ou pas) ? Observe pendant le test, sur `k8s-w01` : `sudo tcpdump -ni eth1 -c 4 host 10.10.30.51 and port 3300`, et depuis `adm01` : `hubble observe --to-ip 10.10.30.51 --last 20`.
8. Recommence 5 et 6 pour `k8s-w02`, puis `k8s-w03`.

*C. Documenter*

9. Ajoute à `docs/socle/matrice-flux.md` la ligne des travailleurs vers `ceph-par1` (sources, destinations, ports, VLAN, « intra-VLAN : pas de règle sur la bordure ») et explique dans la MR pourquoi `group_vars/role_routeur/pare_feu.yml` ne change pas. Vérifie dans NetBox les trois adresses.

**Critères de réussite**
- [ ] Les VMs 2144-2146 ont une carte `net1` sur `vstopub`, MTU 9000, avec la MAC du contexte ; les VMs 2141-2143 n'ont aucune carte sur `vstopub`.
- [ ] Sur chaque travailleur, `eth1` porte la bonne adresse en MTU 9000, sans route par défaut, et un ping de 9000 octets sans fragmentation joint les trois moniteurs ; l'adresse interne du nœud Kubernetes est restée celle du VLAN 40.
- [ ] Les fichiers de protection de cloud-init et netplan sont en place, et les modules `rbd` et `ceph` sont chargés.
- [ ] Les trois travailleurs (et seulement eux) portent l'étiquette `medisphere.internal/stockage-ceph=oui`, sont `Ready` et planifiables.
- [ ] NetBox connaît 10.10.30.81-83 ; le rôle, le playbook et la modification de l'état `k8s` sont sur `main` ; la matrice des flux cite 10.10.30.81-83.

**Vérification** : `lab/bin/check 16 05`

<details><summary>Indice 1</summary>

Le lecteur cloud-init de Proxmox porte des métadonnées dont l'identifiant d'instance dépend du contenu de la configuration (utilisateur et réseau). Ajouter une carte adressée ajoute un `ipconfig1` : nouvel identifiant, donc « nouvelle instance » pour cloud-init au démarrage suivant. Les modules de cloud-init « par instance » se rejouent alors. Lis `/etc/cloud/cloud.cfg` sur un nœud : `ssh_deletekeys`, et la clé `network` qu'on peut poser dans `/etc/cloud/cloud.cfg.d/`.
</details>

<details><summary>Indice 2</summary>

Le rôle `noeud_openstack` du M10 (E02) montre la forme : MAC attendue vérifiée, fichier netplan validé à côté par `netplan generate --root-dir`, mise en place, redémarrage contrôlé. Ici, la carte principale reste à cloud-init (son fichier `50-cloud-init.yaml` ne bouge pas) : seul un fichier **en plus** décrit `eth1`. Pourquoi un redémarrage plutôt qu'un `netplan apply` sur un nœud où Cilium gère ses propres routes et règles ?
</details>

<details><summary>Indice 3</summary>

Pour décider s'il faut redémarrer, compare l'état réel (`ansible_facts`, adresses de `eth1`) à l'état voulu, plutôt que de compter sur le « changed » de la tâche qui écrit le fichier : le fichier a pu être posé à l'étape 4, alors que la carte n'existait pas encore. Les commandes `kubectl` (drain, étiquette) se lancent sur `adm01` par `delegate_to: localhost`, sans `become`.
</details>

**Pour aller plus loin** (facultatif) : limite `client.k8s` aux adresses des travailleurs (capacités cephx avec `network 10.10.30.80/29`, M08-E13). Qu'est-ce que cela protège, et que faut-il prévoir pour `k8s-w04` ou un nœud remplacé ?

---

### M16-E06 — ceph-csi : des volumes RBD sur `ceph-par1`  `LAB` `★★`

> **Ticket PLAT-1706** — *De : Claire Morel*
> C'est le jalon que tout le monde attend : un PVC qui passe `Bound` tout seul, sur `ceph-par1`. Le pool `k8s-rbd` et l'identité `client.k8s` sont prêts depuis le module 08. Je veux une classe par défaut pour les équipes, une classe qui garde les données quand on supprime le PVC, et que Sophie retrouve ses exigences : la clé hors de Git, des échanges chiffrés avec Ceph.

**Objectifs pédagogiques**
- Installer le contrôleur de snapshots et ceph-csi RBD en mode « Ceph externe » (configuration des moniteurs, identité, Secret), et en comprendre chaque réglage.
- Créer des StorageClasses RBD adaptées au noyau des nœuds (fonctionnalités d'image, système de fichiers, chiffrement en transit, politique de récupération).
- Suivre un volume de bout en bout : PVC, PV, image RBD, périphérique sur le nœud ; éprouver `ReadWriteOncePod`, `Delete` et `Retain`.

**Prérequis** : M16-E05 ; M08-E46 (`k8s-rbd`, `client.k8s`), M08-E27 (msgr2 `secure`, type de clé).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Contrôleur de snapshots | external-snapshotter **v8.6.0** : CRD (`client/config/crd`) et `snapshot-controller` (`deploy/kubernetes/snapshot-controller`, espace `kube-system`) ; image `registry.k8s.io/sig-storage/snapshot-controller:v8.6.0` ; dans `plateforme/k8s/composants/snapshot-controller/` (Kustomize) |
| Espace | `ceph-csi`, Pod Security `privileged` (`plateforme/k8s/espaces/ceph-csi.yaml`) |
| Chart | `ceph-csi-rbd` **3.18.1** du dépôt `https://ceph.github.io/csi-charts` (nom local `ceph-csi`), release `ceph-csi-rbd` ; values dans `composants/ceph-csi/values-rbd.yaml` ; installation par `composants/ceph-csi/installer.sh` |
| Configuration du cluster Ceph | `clusterID` = `<FSID>` ; moniteurs `10.10.30.51:3300`, `10.10.30.52:3300`, `10.10.30.53:3300` (msgr2 seulement) |
| Placement | *nodeplugin* et *provisioner* uniquement sur les nœuds `medisphere.internal/stockage-ceph=oui` ; 2 réplicas de *provisioner* |
| Identité | `client.k8s` (Secret `ceph-csi/csi-rbd-secret`, clés `userID` = `k8s`, `userKey`) ; clé en Vault `critique` : `plateforme/k8s/secrets/ceph-csi.yml`, variable `ceph_csi_rbd_cle` ; Secret créé par `outils/ceph-csi-secrets.sh` |
| StorageClass `ceph-rbd` | **par défaut** ; pool `k8s-rbd` ; fonctionnalités d'image `layering,exclusive-lock,object-map,fast-diff,deep-flatten` ; `ext4` ; mappage en msgr2 `secure` ; `Delete` ; agrandissement permis ; option de montage `discard` |
| StorageClass `ceph-rbd-retain` | identique, mais `Retain` et non par défaut |
| Essais (`wb-essais`) | PVC `e06-essai` (1 Gio, classe par défaut) et pod `e06-essai` (à laisser en place : E04 et E10 s'en servent) ; PVC `e06-unique` (RWOP) ; PVC `e06-garde` (`ceph-rbd-retain`) |

**Travail demandé**

*A. Côté Ceph*

1. Sur `ceph01` : `ceph fsid`, `ceph mon dump` (adresses v2 et v1 des moniteurs), `ceph osd pool ls detail | grep k8s-rbd`, `ceph osd pool application get k8s-rbd`, `ceph osd pool get-quota k8s-rbd`, `ceph auth get client.k8s | grep caps`, `ceph config get mon ms_service_mode`. Compare les droits de `client.k8s` à la page `docs/capabilities.md` de ceph-csi 3.18.1. Pourquoi des droits **mgr** ?
2. Range la clé de `client.k8s` dans `plateforme/k8s/secrets/ceph-csi.yml`, chiffré par l'identité Vault `critique`, **sans** qu'elle passe par un fichier en clair (un tube depuis `ssh ceph01 'sudo ceph auth get-key client.k8s'`). Si M08-E46 l'avait déjà rangée ailleurs, il ne doit rester qu'**une** copie de référence : mets le registre des secrets à jour.

*B. Les fondations dans le cluster*

3. Lis le `README` d'external-snapshotter v8.6.0 : pourquoi les CRD et le contrôleur de snapshots doivent-ils exister **avant** le pilote ? Écris `composants/snapshot-controller/kustomization.yaml` (sources amont épinglées à `v8.6.0`, image du contrôleur en `v8.6.0`), relis le rendu (`kubectl kustomize`), applique (`kubectl apply --server-side -k`). Vérifie les CRD et le contrôleur.
4. Écris `espaces/ceph-csi.yaml` et applique-le. Pourquoi `privileged` ? Liste ce que le *nodeplugin* demande à l'hôte (lis le gabarit `nodeplugin-daemonset.yaml` du chart : `helm pull ceph-csi/ceph-csi-rbd --version 3.18.1 --untar`).

*C. ceph-csi RBD*

5. Lis `values.yaml` du chart. Écris `values-rbd.yaml` : configuration du cluster (`csiConfig`), `cephconf` (exige le mode `secure` côté client), placement des pods, réplicas, et **rien d'autre** (ni StorageClass ni Secret créés par le chart : dis pourquoi dans la MR). Relis le rendu complet (`helm template … | less`).
6. Écris `installer.sh`, puis installe :
   ```
   admin@adm01:~/src/k8s$ helm repo add ceph-csi https://ceph.github.io/csi-charts
   admin@adm01:~/src/k8s$ composants/ceph-csi/installer.sh
   ```
   Le script doit faire, pour chaque pilote dont les values existent : `helm upgrade --install ceph-csi-<pilote> ceph-csi/ceph-csi-<pilote> --version 3.18.1 --namespace ceph-csi --values …/values-<pilote>.yaml --wait`, puis appliquer les classes. Où tournent les pods ? Combien de *nodeplugin* ?
7. Écris `outils/ceph-csi-secrets.sh` (modes `appliquer` et `verifier`) : il lit les clés dans le Vault, crée ou met à jour les Secrets dans `ceph-csi` sans jamais écrire ni afficher une clé, et en mode `verifier` compare (par empreinte) la clé du Vault, celle du Secret et celle de Ceph. Lance `appliquer` puis `verifier`.
8. Écris et applique les classes `ceph-rbd` et `ceph-rbd-retain`. Avant, vérifie dans la documentation de ceph-csi et dans la page *RBD Kernel Module* de Ceph que le noyau 6.12 des travailleurs gère chaque fonctionnalité d'image que tu demandes ; dis pourquoi `journaling` n'y est pas.

*D. Un volume de bout en bout*

9. Dans `wb-essais`, crée le PVC `e06-essai` (sans classe) et le pod `e06-essai` qui y écrit un fichier de 100 Mio et sa somme de contrôle. Retrouve : le PV, l'image (`spec.csi.volumeAttributes.imageName`), l'image dans le pool (`rbd ls -l k8s-rbd`, `rbd info k8s-rbd/<image>` : fonctionnalités), le périphérique sur le nœud (`lsblk`, `findmnt -t ext4`), les connexions du nœud vers les moniteurs et les OSD (`ss -tn`) : quel port, quel mode ?
10. Fais partir le pod sur un autre travailleur (`kubectl cordon` du nœud, suppression du pod, `kubectl uncordon`) : les données sont-elles là ? Combien de temps a pris le démarrage ?
11. Crée `e06-unique` en `ReadWriteOncePod` et deux pods qui le montent, **sur le même nœud**. Que se passe-t-il pour le second ? Compare avec E03, étape 5. Supprime-les.
12. Crée `e06-garde` (classe `ceph-rbd-retain`, 1 Gio), lie-le par un pod, puis supprime pod et PVC. État du PV ? L'image existe-t-elle encore ? Fais le ménage en administrateur : vérifie le nom de l'image dans le PV, supprime le PV, puis l'image.
    > ⚠️ **Attention** : `rbd rm` est définitif. Copie le nom de l'image depuis `kubectl get pv <pv> -o jsonpath='{.spec.csi.volumeAttributes.imageName}'`, vérifie le pool (`k8s-rbd`) et qu'**aucun** PV ne la référence encore avant de la supprimer.
13. Écris la fiche d'exploitation `docs/kubernetes/stockage/ceph-csi.md` (architecture, identités et Secrets, classes, commandes d'installation, de vérification et de mise à jour, correspondance PV ↔ image). MR sur `plateforme/k8s` (sans secret en clair : relis le diff), sur `plateforme/medisphere`, registre des secrets.

**Critères de réussite**
- [ ] Les CRD `snapshot.storage.k8s.io` existent et `snapshot-controller` (v8.6.0) est disponible dans `kube-system`.
- [ ] L'espace `ceph-csi` est en `privileged` ; le *nodeplugin* RBD (chart 3.18.1) tourne sur les trois travailleurs et nulle part ailleurs, le *provisioner* a 2 réplicas prêts.
- [ ] La configuration du pilote désigne `ceph-par1` par son fsid et ses moniteurs en 3300 seulement.
- [ ] `ceph-rbd` est la **seule** classe par défaut et a les paramètres du contexte technique ; `ceph-rbd-retain` est en `Retain`.
- [ ] Le PVC `e06-essai` est lié dans `ceph-rbd`, le pod `e06-essai` tourne, son image existe dans `k8s-rbd` ; aucun PV `Released` ni image orpheline (image `csi-vol-…` sans PV) ne reste dans `k8s-rbd`.
- [ ] Les travailleurs parlent aux moniteurs sur 3300 et jamais sur 6789.
- [ ] `secrets/ceph-csi.yml` est chiffré sous l'identité `critique` sur `main`, ainsi que les values, les classes, l'espace, le contrôleur de snapshots et les deux scripts.

**Vérification** : `lab/bin/check 16 06`

<details><summary>Indice 1</summary>

Le chart crée par défaut une ConfigMap `ceph-csi-config` à partir de `csiConfig` (un tableau : une entrée par cluster Ceph, `clusterID` et `monitors`), et une ConfigMap `ceph-config` à partir de `cephconf` (le `ceph.conf` que voient les outils Ceph dans les conteneurs). Le `clusterID` est le lien entre une StorageClass et une entrée de `csiConfig`.
</details>

<details><summary>Indice 2</summary>

Les paramètres d'une StorageClass RBD sont décrits dans `docs/rbd/deploy.md` de ceph-csi : `clusterID`, `pool`, `imageFeatures`, `mapOptions` (format `<mounter>:options`, le noyau étant `krbd`), `csi.storage.k8s.io/fstype`, et les couples `…-secret-name` / `…-secret-namespace` pour la création, l'agrandissement, la publication et la préparation sur le nœud. Les options de mappage du noyau sont dans la page `rbd(8)`, section *Kernel rbd (krbd) options* : cherche `ms_mode`.
</details>

<details><summary>Indice 3</summary>

Pour le script des Secrets : `kubectl create secret generic … --from-literal=userID=k8s --from-file=userKey=<(printf '%s' "$cle") --dry-run=client -o yaml | kubectl apply --server-side -f -`. La substitution de processus évite la clé dans la ligne de commande (visible dans `ps`) ; `--server-side` évite l'annotation `last-applied-configuration`, qui recopierait le Secret entier. `ansible-vault view` lit le fichier chiffré ; `yq` en extrait une variable.
</details>

**Pour aller plus loin** (facultatif) : lis les métriques du *nodeplugin* (`kubectl -n ceph-csi port-forward svc/ceph-csi-rbd-nodeplugin-http-metrics 8080:8080` puis `curl -s localhost:8080/metrics | grep -v '^#' | head`). Lesquelles serviront à la supervision du palier 3 ?

---

### M16-E07 — ceph-csi : des volumes partagés CephFS  `LAB` `★★`

> **Ticket DEV-1707** — *De : Julien Petit*
> Quand Legacy-RDV arrivera dans le cluster (on en parle pour le final F4), il tournera en deux instances, et ses pièces jointes (`uploads/`) doivent être vues des deux : aujourd'hui, la seconde instance répond 404 sur les fichiers de la première. Le module 08 avait préparé un export NFS ; dans Kubernetes, je voudrais simplement un PVC « partagé ». Et j'ai entendu qu'un volume RBD ne pouvait pas faire ça : pourquoi ?
>
> *Karim, en commentaire* : identité Ceph **séparée** pour CephFS, décrite dans `allocations.yaml`, avec un plafond pour tout ce que Kubernetes mettra dans CephFS.

**Objectifs pédagogiques**
- Préparer CephFS pour un consommateur Kubernetes : groupe de sous-volumes plafonné, identité aux droits documentés.
- Installer ceph-csi CephFS à côté de RBD dans le même espace, sans collision.
- Utiliser un volume `ReadWriteMany` depuis plusieurs nœuds, en éprouver le quota, et comprendre pourquoi RBD ne fait pas de RWX en mode fichier.

**Prérequis** : M16-E06 ; M08-E10 (CephFS, sous-volumes), M08-E31 (`ceph-allocations.sh`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| CephFS | volume `cephfs` (M08-E10) ; groupe de sous-volumes **`csi`**, plafond 20 Gio, dans `allocations.yaml` (`plateforme/ceph`) : la section qui manque à l'outil est à ajouter (MR) |
| Identité | `client.k8s-cephfs` : droits de `docs/capabilities.md` de ceph-csi 3.18.1 pour CephFS, avec `fsname=cephfs` et le groupe `csi` ; type de clé `aes` ; Secret `ceph-csi/csi-cephfs-secret` (`userID` = `k8s-cephfs`) ; clé en Vault : variable `ceph_csi_cephfs_cle` du même fichier |
| Chart | `ceph-csi-cephfs` **3.18.1**, release `ceph-csi-cephfs`, espace `ceph-csi`, values `composants/ceph-csi/values-cephfs.yaml` ; ConfigMaps renommées `ceph-csi-config-cephfs`, `ceph-config-cephfs`, `ceph-csi-encryption-kms-config-cephfs` |
| StorageClass `cephfs` | `fsName: cephfs`, client noyau, `ms_mode=secure` au montage, `Delete`, agrandissement permis, non par défaut |
| Essais (`wb-essais`) | PVC `e07-partage` (1 Gio, RWX) ; Deployment `e07-ecrivains` (2 réplicas sur deux nœuds différents) ; pod `e07-lecteur` ; PVC `e07-rbd-rwx` (l'essai qui échoue) |

**Travail demandé**

*A. Côté Ceph, par le code*

1. Sur `ceph01` : `ceph fs status cephfs`, `ceph fs subvolumegroup ls cephfs`, `ceph fs ls` (pools de métadonnées et de données). Lis la section CephFS de `docs/capabilities.md` de ceph-csi : explique chaque capacité (`mon`, `mgr`, `osd`, `mds`) et ce que le droit `mgr "allow rw"` ouvre de plus que les autres identités du cluster.
2. Dans `plateforme/ceph`, ajoute à `allocations.yaml` l'identité `client.k8s-cephfs` et une section pour les groupes de sous-volumes des consommateurs (le groupe `csi`, 20 Gio), et à `outils/ceph-allocations.sh` la fonction qui la vérifie et l'applique (même style que les équipes : `verifier`, `appliquer --simuler`, rien de supprimé). MR, `appliquer`, `verifier` sans écart.
3. Ajoute la clé de `client.k8s-cephfs` au fichier Vault de E06, toujours sans fichier en clair (le fichier entier se rechiffre à partir d'un tube : `ansible-vault view` du fichier existant, suivi de la nouvelle ligne). Le script de E06 crée le second Secret : `appliquer`, `verifier`.

*B. Le pilote CephFS*

4. Lis `values.yaml` du chart `ceph-csi-cephfs` 3.18.1 et compare-le à celui de RBD. Quels objets les deux charts créeraient-ils **sous le même nom** dans l'espace `ceph-csi` ? Écris `values-cephfs.yaml` en conséquence, avec le groupe de sous-volumes dans `csiConfig` et le même placement que RBD. `helm template` : vérifie qu'aucun nom ne se répète avec la release RBD (`kubectl get cm -n ceph-csi`).
5. `installer.sh` (qui installe maintenant les deux pilotes), puis la classe `cephfs`. Vérifie le `CSIDriver` et les `CSINode`.

*C. Un volume partagé*

6. Crée `e07-partage` (RWX) et le Deployment `e07-ecrivains` : deux réplicas, obligatoirement sur deux nœuds différents, qui ajoutent chacun une ligne `<nom du pod> <heure>` toutes les 5 s dans `/partage/journal`. Un pod `e07-lecteur` affiche les 20 dernières lignes. Les deux écrivains apparaissent-ils ? Retrouve le sous-volume (`ceph fs subvolume ls cephfs --group_name csi`, `ceph fs subvolume info …`) et le montage sur un nœud (`findmnt -t ceph`) : quelles options ?
7. Dans un écrivain, `df -h /partage`, puis écris 1,5 Gio dans le volume (`dd`). Quel message, à quel moment ? D'où vient la limite ? Efface le fichier.
8. Crée `e07-rbd-rwx` : 1 Gio, classe `ceph-rbd`, `ReadWriteMany`, mode `Filesystem`. Lis les événements. Pourquoi ceph-csi refuse-t-il, et dans quel cas accepterait-il un RBD partagé ? Supprime-le.
9. Complète `docs/kubernetes/stockage/ceph-csi.md` (section CephFS : quand choisir `cephfs` plutôt que `ceph-rbd`, ce que vaut le quota, l'exemple de Legacy-RDV). MR.

**Critères de réussite**
- [ ] `client.k8s-cephfs` a exactement les droits documentés ; le groupe `csi` existe dans `cephfs` avec un plafond de 20 Gio ; `allocations.yaml` et l'outil étendu sont sur `main` et `verifier` ne signale aucun écart.
- [ ] Le *nodeplugin* CephFS tourne sur les trois travailleurs, son *provisioner* a 2 réplicas prêts, sa configuration désigne le même cluster (fsid, moniteurs en 3300) et le groupe `csi`, sans collision de noms avec RBD.
- [ ] La classe `cephfs` a les paramètres du contexte technique et n'est pas par défaut.
- [ ] `e07-partage` est lié en RWX ; `e07-ecrivains` a 2 pods prêts sur deux nœuds différents ; un sous-volume existe dans le groupe `csi` ; `e07-rbd-rwx` n'existe plus.

**Vérification** : `lab/bin/check 16 07`

<details><summary>Indice 1</summary>

Les deux charts ont les mêmes valeurs par défaut pour les noms des ConfigMaps qu'ils créent (`configMapName`, `cephConfConfigMapName`, `kmsConfigMapName`) : dans un même espace, la seconde installation échouerait (objet déjà possédé par une autre release). Les noms des Deployments, DaemonSets, comptes de service et rôles dérivent du nom de la release : pas de collision.
</details>

<details><summary>Indice 2</summary>

Un sous-volume CephFS créé par ceph-csi reçoit un **quota** CephFS égal à la taille demandée par le PVC ; le client noyau le fait respecter (`EDQUOT`). Pour les options de montage noyau, la classe accepte `kernelMountOptions` (voir `docs/cephfs/deploy.md`) ; `mounter: kernel` évite que le pilote choisisse `ceph-fuse`.
</details>

<details><summary>Indice 3</summary>

Pour le Deployment sur deux nœuds : une anti-affinité de pods **obligatoire** (`requiredDuringSchedulingIgnoredDuringExecution`, `topologyKey: kubernetes.io/hostname`). Pour RBD en RWX : un système de fichiers comme ext4 ne supporte pas deux noyaux qui l'écrivent ; lis le message du *provisioner*, il dit dans quel mode de volume le partage est permis.
</details>

**Pour aller plus loin** (facultatif) : compare avec l'export NFS `/legacy-rdv` du module 08 (M08-E16) : qui gère les droits, la haute disponibilité, le chiffrement en transit, la sauvegarde ? Et avec un stockage objet, que le README de Legacy-RDV présente comme « mieux » ?

---

### M16-E08 — StatefulSet et volumes par instance  `LAB` `★★`

> **Ticket DEV-1708** — *De : Julien Petit*
> Vendredi, le drain de `k8s-w02` a vidé le Valkey de recette. MédiAgenda est reparti en mode dégradé, toutes les requêtes de créneaux sont retombées sur PostgreSQL pendant que le cache se reconstruisait, et la recette des rappels SMS est tombée au milieu. Je sais que c'est « juste un cache », mais je veux qu'il survive à un déplacement de pod. Et j'aimerais comprendre ce que deviennent les volumes quand on réduit ou supprime un StatefulSet, avant qu'on y mette PostgreSQL.
>
> *Nadia, en commentaire* : et dites-moi ce qui se passe si le nœud **meurt** au lieu d'être drainé.

**Objectifs pédagogiques**
- Utiliser `volumeClaimTemplates` : un PVC par instance, identité et volume stables à travers les déplacements.
- Maîtriser ce que deviennent les PVC à la réduction et à la suppression (`persistentVolumeClaimRetentionPolicy`).
- Passer un composant réel (Valkey de MédiAgenda, en `restricted`) d'un volume jetable à un volume persistant sans interruption du service.

**Prérequis** : M16-E06 ; M14-E15 (StatefulSet), M14-E18 (PSA `restricted`, VAP), M15 (politiques réseau de `mediagenda-recette`).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Image | `registry.par1.medisphere.internal/dockerhub/valkey/valkey:8.1` (utilisateur 999, données dans `/data`) |
| Essai (`wb-essais`) | StatefulSet `e08-valkey` (Service sans tête `e08-valkey`), modèle de volume `donnees` 1 Gio `ceph-rbd` ; état final : **2** réplicas, politique `whenScaled: Delete`, `whenDeleted: Retain` |
| Existant (M14-E21) | StatefulSet `valkey` de trois instances (`valkey-0` primaire, deux répliques, `emptyDir`), Service sans tête `valkey`, URL de l'API `redis://valkey-0.valkey:6379/0` (ConfigMap `mediagenda-api-config`) ; manifeste `k8s/recette/30-valkey.yaml` du projet `mediagenda/api` |
| Recette (`mediagenda-recette`) | StatefulSet `valkey` d'**une** instance (décision de Karim et Julien : sans Sentinel, les deux répliques n'assurent aucune bascule et l'API ne parle qu'à `valkey-0` ; la réplication avec bascule viendra au M27), même Service sans tête `valkey` comme `serviceName`, même URL ; PVC `donnees-valkey-0` 1 Gio `ceph-rbd` ; politique `Retain` / `Retain` ; persistance AOF ; profil `restricted` ; mêmes étiquettes que l'ancien Valkey (le Service et les politiques réseau du M15 les sélectionnent) |
| Application | `https://mediagenda-recette.apps.par1.medisphere.internal/pret` répond 200 quand PostgreSQL **et** Valkey répondent |

**Travail demandé**

*A. Le patron, dans `wb-essais`*

1. Écris `e08-valkey` : 3 réplicas, Service sans tête, persistance AOF (`--appendonly yes`), contexte de sécurité `restricted` (utilisateur et groupe 999, `fsGroup` 999), sondes `valkey-cli ping`, modèle de volume `donnees`. Observe l'ordre de création des pods et des PVC (`kubectl get pod,pvc -w`). Noms des PVC ? Nom DNS de chaque instance ?
2. Écris une clé dans `e08-valkey-1` (`kubectl exec … -- valkey-cli SET essai "$(date)"`). Supprime le pod `e08-valkey-1` : quel nom porte le pod recréé, quel PVC monte-t-il, sur quel nœud ? La clé est-elle là ? Suis le `VolumeAttachment` pendant l'opération.
3. Réduis à 1 réplica, puis remonte à 3 : que sont devenus les PVC pendant ce temps, et les données ?
4. Pose la politique `persistentVolumeClaimRetentionPolicy` (`whenScaled: Delete`, `whenDeleted: Retain`) et réduis à 2 réplicas. Que devient `donnees-e08-valkey-2`, son PV, son image RBD ? Écris dans `~/m16/e08/notes.md` quand chaque combinaison de la politique a du sens (cache, base répliquée, base unique).
5. Nadia : un nœud qui **meurt**. Sans le provoquer, lis la page *StatefulSet* (garantie « au plus un » pod par identité) et celle des *non-graceful node shutdown* : que fait le contrôleur du StatefulSet si le nœud de `e08-valkey-0` ne répond plus, que faudrait-il pour que le pod reparte ailleurs, et quel est le risque si on force ? (La panne est pratiquée en M16-E37.)

*B. Le Valkey de recette*

6. Relève l'existant : `kubectl -n mediagenda-recette get deploy,sts,svc,netpol,pvc -o wide`, l'URL Valkey de l'API (ConfigMap `mediagenda-api-config`), les étiquettes de l'ancien Valkey et les sélecteurs du Service et des politiques réseau qui le concernent.
7. Écris le StatefulSet `valkey` du contexte technique dans `k8s/recette/30-valkey.yaml` du projet `mediagenda/api` (il remplace celui du M14). Vérifie qu'il est accepté par Pod Security `restricted` et par la ValidatingAdmissionPolicy du M14 (`kubectl apply --dry-run=server`).
8. Bascule : remplace l'ancien StatefulSet par le nouveau (un champ au moins ne se modifie pas en place : lequel ?), attends qu'il soit prêt et qu'il ne reste qu'un pod Valkey, vérifie `/pret` et le nombre de clés (`valkey-cli DBSIZE`) après quelques requêtes de créneaux. Combien de temps `/pret` a-t-il répondu 503, s'il l'a fait ?
9. Draine le nœud du pod `valkey-0`, attends qu'il reparte ailleurs, `uncordon`. `DBSIZE` avant et après ? `/pret` ? MR des manifestes.

**Critères de réussite**
- [ ] `wb-essais/e08-valkey` a 2 réplicas prêts, la politique `whenScaled: Delete` / `whenDeleted: Retain`, et exactement les PVC `donnees-e08-valkey-0` et `-1` (liés, `ceph-rbd`).
- [ ] `mediagenda-recette/valkey` est un StatefulSet d'1 réplica prêt, au profil `restricted` (non root, 999, capacités retirées, `seccompProfile`), image du contexte technique, persistance AOF activée, politique `Retain`/`Retain`, dont le `serviceName` est le Service sans tête `valkey`.
- [ ] Le PVC `donnees-valkey-0` est lié dans `ceph-rbd` ; il n'y a plus d'autre Valkey (répliques `valkey-1`/`valkey-2`, Deployment, pod avec `emptyDir`/`hostPath`) dans `mediagenda-recette`.
- [ ] `https://mediagenda-recette.apps.par1.medisphere.internal/pret` répond 200.

**Vérification** : `lab/bin/check 16 08`

<details><summary>Indice 1</summary>

Le nom d'un PVC issu d'un modèle est `<nom du modèle>-<nom du StatefulSet>-<ordinal>`. Le StatefulSet ne le supprime jamais de lui-même, sauf politique `persistentVolumeClaimRetentionPolicy` (stable depuis Kubernetes 1.32). Le champ `serviceName` désigne un Service sans tête qui doit exister pour que les noms `…-0.<service>` résolvent.
</details>

<details><summary>Indice 2</summary>

L'image Valkey démarre en root pour corriger les droits de `/data`, puis abandonne ses privilèges ; lancée directement en utilisateur 999 (`restricted`), elle saute cette étape. Ce sont alors `fsGroup` (le kubelet ajuste le groupe du volume, `fsGroupPolicy: File` du `CSIDriver`) et `fsGroupChangePolicy` qui rendent le volume inscriptible. `readOnlyRootFilesystem: true` est possible : Valkey n'écrit que dans `/data`.
</details>

<details><summary>Indice 3</summary>

L'API vise `valkey-0.valkey` : le nom d'un pod derrière le Service sans tête. Si le StatefulSet garde son nom, son `serviceName` et ses étiquettes, l'adresse ne change pas. Pour le champ qui ne se modifie pas, regarde les options de `kubectl delete` sur le sort des objets dépendants, et ce que fait un StatefulSet des pods qui portent déjà son nom et correspondent à son sélecteur.
</details>

**Pour aller plus loin** (facultatif) : Valkey en réplication (un primaire, deux répliques) avec Sentinel ou le futur opérateur : que changent les identités stables ? Pourquoi CloudNativePG (E18) ne gère-t-il **pas** ses pods par un StatefulSet ?

---

### M16-E09 — Questions : stockage et CSI  `Q` `★★`

> **Ticket PLAT-1709** — *De : Karim Benali*
> Tu as posé un PV à la main, raccordé les nœuds, installé deux pilotes et déplacé des volumes. Avant le palier 2, je veux voir si tu sais expliquer ce que tu as fait. Appuie tes réponses sur ce que tu as observé.

**Objectifs pédagogiques**
- Expliquer le fonctionnement et les limites du stockage CSI de `k8s-par1`.
- Relier une observation (un état, un message, une mesure) à son mécanisme.

**Prérequis** : M16-E02 à M16-E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 12 questions, en citant une observation du lab quand c'est possible.

1. Suis une écriture de 4 Kio faite par le pod `e06-essai` dans `/donnees`, du processus jusqu'aux disques des OSD : quelles couches traverse-t-elle sur le nœud, sur quel réseau, avec quel chiffrement, et à quel moment l'écriture est-elle acquittée ?

2. *(QCM)* Tu modifies `imageFeatures` dans la StorageClass `ceph-rbd` (par `kubectl delete` puis `kubectl apply`). Les PV existants :
   - A. Reçoivent les nouvelles fonctionnalités au prochain montage
   - B. Ne changent pas : les paramètres d'une classe ne servent qu'à la création
   - C. Sont recréés par le *provisioner*
   - D. Passent en `Released`

3. Pourquoi le *nodeplugin* tourne-t-il en `privileged`, avec `hostNetwork` et une propagation de montage `Bidirectional` ? Que perdrait-on avec chacune de ces permissions en moins ?

4. Le *provisioner* n'est pas en `hostNetwork`. Par quel chemin réseau, avec quelle adresse source, ses requêtes atteignent-elles les moniteurs ? Qu'est-ce qui casserait si Cilium ne masquait plus ce trafic ?

5. Pourquoi lister les moniteurs en `:3300` seulement, et imposer `ms_mode=secure` côté noyau alors que `ceph-par1` refuse déjà le mode `crc` ? Que se passerait-il avec `10.10.30.51:6789` dans la configuration ?

6. *(QCM)* Le type de clé de `client.k8s` est `aes` et pas `aes256k`, parce que :
   - A. ceph-csi 3.18 ne connaît pas `aes256k`
   - B. C'est le **noyau** des travailleurs (6.12) qui s'authentifie pour mapper les images et monter CephFS, et il ne sait pas utiliser `aes256k`
   - C. `aes256k` est réservé aux démons
   - D. Kubernetes limite la taille des Secrets

7. `ReadWriteOnce`, `ReadWriteOncePod`, `ReadWriteMany` : pour chacun, ce que tu as observé en E03, E06 et E07, et ce qui l'applique (planificateur, kubelet, pilote, Ceph).

8. Que protège la politique `Retain`, et contre quoi ne protège-t-elle **pas** ? Donne deux façons de perdre quand même les données d'un PVC de `ceph-rbd-retain`.

9. Le pool `k8s-rbd` a un quota de 20 Gio et les images sont allouées à la demande. Que fait l'option de montage `discard` ? Que mesures-tu avec `rbd du` et avec `ceph df` ? Que verra un pod le jour où le quota est atteint ?

10. `fsGroup` et `fsGroupChangePolicy: OnRootMismatch` : qu'a fait le kubelet sur le volume du Valkey de recette au premier montage, et pourquoi `OnRootMismatch` compte-t-il pour un volume de plusieurs centaines de Gio ?

11. Persister un **cache** : défends la décision prise pour le Valkey de recette, puis donne le meilleur argument contre. Qu'est-ce qui la rendrait inutile ?

12. *(QCM)* Le nœud qui porte `valkey-0` s'éteint brutalement. Au bout de 10 minutes :
    - A. Le pod a été recréé sur un autre nœud et a remonté son volume
    - B. Le pod est marqué en cours de suppression mais reste lié à l'ancien nœud ; aucun nouveau `valkey-0` ne démarre tant que l'ancien n'est pas confirmé arrêté
    - C. Le StatefulSet a créé `valkey-1` pour compenser
    - D. Le PVC a été détaché et supprimé

**Critères de réussite**
- [ ] Les 12 réponses sont rédigées, avec une observation du lab pour au moins six d'entre elles.
- [ ] Auto-correction faite avec le barème du corrigé.

<details><summary>Indice 1</summary>

Pour la question 1, sépare le chemin **de données** (page cache, système de fichiers, périphérique bloc `rbd`, messager du noyau, OSD primaire, répliques) du chemin **de contrôle** (moniteurs, cartes, verrou exclusif) : seul le premier est sur la route de chaque écriture.
</details>

<details><summary>Indice 2</summary>

Pour la question 12, relis tes notes de E08 (étape 5) : la garantie « au plus un » du StatefulSet, et ce qu'il faut pour lever le doute sur un nœud injoignable (*taint* `node.kubernetes.io/out-of-service`).
</details>
