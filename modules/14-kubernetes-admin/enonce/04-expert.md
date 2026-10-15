# Module 14 — Palier 4 : Expert

`k8s-par1` est en service : trois nœuds de contrôle derrière la VIP de l'API, trois travailleurs, Cilium, des équipes, des quotas, des rôles, de l'admission, un etcd sauvegardé, un cluster monté en 1.36, audité et chiffré. Nadia Roussel repose la question du début du module : « Quand un nœud tombe, quand etcd souffre, quand les certificats expirent, qui sait quoi faire à 4 h du matin ? » Karim Benali a préparé huit pannes, toutes de celles que racontent les post-mortems publics et les examens d'administration : un nœud perdu, des pods qui ne partent pas, des images qui ne se tirent pas, des conteneurs qui redémarrent en boucle, une API injoignable, un etcd malade, des accès refusés, un DNS muet. Une astreinte en combine trois. Puis tu descends sous le capot, de `kubectl apply` jusqu'au processus dans son cgroup, et tu passes les questions qu'on pose en entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres à Kubernetes :
- **Kubernetes raconte ce qu'il fait.** Les conditions d'un objet (`kubectl describe`, section `Conditions`), ses événements (`kubectl get events --sort-by=.lastTimestamp`, `kubectl events`) et le champ `status` disent presque toujours ce qui bloque. Lis-les en entier avant de modifier quoi que ce soit.
- **Situe l'étage.** Un pod passe par l'API (authentification, autorisation, admission), etcd, l'ordonnanceur, le kubelet, le runtime (containerd, runc), le réseau (Cilium, CoreDNS). Chaque étage a ses outils : `kubectl`, `kubectl auth can-i`, `etcdctl`, `journalctl -u kubelet`, `crictl`, `journalctl -u containerd`. Quand l'API ne répond plus, `kubectl` ne sert à rien : passe sur les nœuds.
- **Le code fait foi.** Une réparation à chaud est permise pour rétablir le service ; si elle touche ce qui est décrit dans `plateforme/k8s` (manifestes, espaces, RBAC, admission) ou dans les rôles Ansible des nœuds (`containerd`, `k8s_noeud`, `k8s_plan_controle`, `k8s_travailleur`), reporte-la ensuite par une MR, sinon le prochain `task appliquer` ou le prochain passage d'Ansible la défera, ou remettra la panne.

> **Rappels** : tout se lance depuis `adm01`. Ton kubeconfig personnel (`~/.kube/config`, groupe `medisphere:plateforme-admins`) sert au quotidien ; `admin.conf` et `super-admin.conf` sont en Vault `critique` et ne sortent qu'en **bris de glace**, avec une ligne dans ton journal (qui, quand, pourquoi). Les nœuds se joignent en SSH (`admin` + `sudo`) ; sur un nœud, `crictl` parle à containerd (`/run/containerd/containerd.sock`), les manifestes des pods statiques sont dans `/etc/kubernetes/manifests/`, les certificats dans `/etc/kubernetes/pki/`.

## Règles du jeu des pannes (M14-E35 à M14-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 14 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 à 6 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (ta configuration diffère de celle du corrigé), le script en essaie une autre. Une injection prend de quelques secondes à trois minutes : le script attend que Kubernetes constate la panne.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 14 35`) : il doit être vert. Le script refuse d'ailleurs de casser un cluster qui ne va pas bien (API muette par la VIP, nœud pas `Ready`, membre etcd qui ne répond pas).
- **Témoins.** À la première injection, le script crée l'espace **`wb-pannes`** (profil Pod Security `restricted`) et une petite application d'équipe qui sert de témoin, qu'il ne supprime jamais :
  - `agenda` : MédiAgenda (deux réplicas, image du projet `medisphere` de Harbor, Secret de tirage `harbor-pull` copié d'un de tes espaces, sondes `/sante` et `/pret`), avec `postgres` et `valkey` **jetables** (`emptyDir` : le stockage persistant arrive au module 16) ;
  - `sonde-api` : un pod qui lit l'API toutes les 10 s avec son propre compte de service, et n'est prêt que si la dernière lecture a réussi ;
  - `sonde-dns` : un pod qui n'est prêt que s'il résout un nom interne au cluster **et** un nom MédiSphère (`registry.par1.medisphere.internal`) ;
  - un `ResourceQuota` et un `LimitRange` d'espace.

  Les témoins tirent leurs images à chaque démarrage (`imagePullPolicy: Always`). Ils ne gênent ni le mini-projet ni les modules suivants ; tu peux supprimer `wb-pannes` après la recette (M14-E46), toi-même. Si le script ne trouve pas d'image MédiAgenda (aucun pod ni étiquette `v*` dans Harbor), renseigne `WB_M14_IMAGE_AGENDA` dans `lab/lab.env` avec la référence complète de ton image.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les nœuds, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 14 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte M14-E43 et le mini-projet) : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation.
- Les pannes n'agissent que sur les nœuds de `k8s-par1` (SSH, ou agent QEMU depuis `pve01` quand SSH peut être perdu) et sur les objets des espaces du workbook (`wb-*`, `mediagenda-*`) et des composants de plateforme (`kube-system`). **Jamais deux nœuds de contrôle à la fois**, sauf l'astreinte M14-E43, qui prend d'abord un instantané etcd et le vérifie. Jamais sur `pve01`, son réseau ou son pare-feu, jamais sur `pbs01`, jamais sur une VM hors du pool `lab`. Aucune donnée n'est détruite : tout fichier ou objet modifié est sauvegardé avant.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/kubernetes/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M14-E43 et les runbooks.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Accès de secours** : M14-E39 peut te priver de `kubectl`, M14-E41 peut rendre ton kubeconfig inutilisable, M14-E40 peut rendre un nœud de contrôle injoignable en SSH. Vérifie **avant** d'injecter que tu sais : entrer sur `k8s-cp01-03` sans SSH (console série `qm terminal 2141` depuis `pve01`, sortie par `Ctrl+O`, ou agent QEMU : `qm guest cmd 2141 ping` doit répondre) ; parler à un kube-apiserver en direct, sans la VIP (`--server https://10.10.40.51:6443`) ; sortir `admin.conf` de Vault et le détruire ensuite.

> ⚠️ **Les gestes interdits du palier**, sauf mention explicite dans ta démarche avec sa justification : `kubectl delete node`, `kubeadm reset` sur un nœud de contrôle, `etcdctl member remove` d'un membre **sain**, toute restauration d'etcd depuis un instantané (RB-141) tant qu'il reste un quorum, `kubectl delete namespace` d'un espace d'équipe, toute modification de deux nœuds de contrôle à la fois. Aucune des pannes ne demande de reconstruire le cluster.

---

### M14-E35 — Panne : un nœud est NotReady  `BF` `★★`

> **Ticket INC-4135** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection : selon le cas, un nœud `NotReady` signalé par l'alerte du matin, ou des pods évincés d'un nœud qui refuse les nouveaux.)* Lucas propose de « supprimer le nœud et de le rejoindre » : n'en fais rien avant d'avoir trouvé la cause.

**Objectifs pédagogiques**
- Relier l'état `Ready` d'un nœud à ce qui le produit : le kubelet qui renouvelle son bail (`Lease` de `kube-node-lease`) et met à jour ses conditions, le runtime qu'il interroge (CRI), les seuils d'éviction.
- Descendre les étages sur le nœud : unité systemd, journal du kubelet, configuration (`/var/lib/kubelet/config.yaml`, `kubeadm-flags.env`, `/etc/default/kubelet`), containerd, certificat client, ressources (mémoire, swap, disque).
- Appliquer et compléter RB-140 (M14-E22) sans geste destructeur.

**Prérequis** : M14-E20, M14-E22 (RB-140), M14-E26 (certificats du kubelet) ; `lab/bin/check 14 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la panne touche un **travailleur**. Le contrôleur de nœuds passe un nœud `NotReady` (puis `Unknown`) quand son bail n'est plus renouvelé pendant `node-monitor-grace-period` (40 s par défaut) ; il pose alors les taints `node.kubernetes.io/not-ready` ou `unreachable`, et les pods qui ne les tolèrent pas sont évincés après `tolerationSeconds` (300 s par défaut). Un nœud peut aussi rester `Ready` mais se protéger (conditions `DiskPressure`, `MemoryPressure`, `PIDPressure`) en évinçant des pods.

**Injection** : `lab/bin/break 14 35` (6 variantes).

**Travail demandé**
1. Constate sans rien toucher : conditions du nœud (`kubectl describe node`), date du dernier renouvellement de son bail, taints posées, événements. Depuis quand ? Que va faire Kubernetes de lui-même, et dans combien de temps ? Les pods du nœud tournent-ils encore (vérifie-le sur le nœud) ?
2. Descends les étages sur le nœud concerné : kubelet (état de l'unité, journal), containerd, configuration, ressources. Note dans ton journal l'étage en cause et la ligne de journal qui le prouve.
3. Trouve la cause racine et corrige-la **sans** supprimer ni rejoindre le nœud. Si la cause est une intervention humaine, retrouve-la (fichier, date, commentaire, journal systemd).
4. Vérifie le retour : nœud `Ready`, taints retirées, pods du nœud de nouveau suivis.
5. Complète RB-140 (`docs/kubernetes/runbooks/RB-140-*.md`) : un arbre de décision par étage (kubelet, configuration du kubelet, containerd, swap, certificat client, disque), avec pour chacun la commande qui le prouve et le correctif ; ajoute ce qui aurait dû alerter avant Nadia.

**Critères de réussite**
- [ ] Les six nœuds sont `Ready`, sans condition de pression, aucun nœud n'est resté cordonné.
- [ ] Sur chaque travailleur : kubelet actif et activé, containerd actif avec une configuration lisible, aucun swap actif ni déclaré, certificat client du kubelet signé par la CA du cluster, `/var/lib/containerd` occupé à moins de 85 %.
- [ ] RB-140 couvre les six étages ; ton journal contient les conditions initiales du nœud, l'étage en cause et sa preuve.

**Vérification** : `lab/bin/check 14 35`

<details><summary>Indice 1</summary>

`kubectl get lease -n kube-node-lease <nœud> -o yaml` (champ `renewTime`) dit quand le kubelet a parlé pour la dernière fois. Sur le nœud : `systemctl status kubelet`, `journalctl -u kubelet -b --no-pager | tail -n 50`, `systemctl status containerd`. Un kubelet qui redémarre en boucle laisse une ligne d'erreur explicite juste avant chaque arrêt.
</details>

<details><summary>Indice 2</summary>

Si le kubelet tourne mais que l'API le refuse, regarde ce qu'il présente : `/etc/kubernetes/kubelet.conf` désigne son certificat client ; `openssl x509 -noout -issuer -subject -dates` et `openssl verify -CAfile /etc/kubernetes/pki/ca.crt` le jugent. La documentation kubeadm (*Troubleshooting kubeadm*, « Kubelet client certificate rotation fails ») décrit la régénération d'un `kubelet.conf` depuis un nœud de contrôle.
</details>

<details><summary>Indice 3</summary>

Pour un nœud qui évince : `df -h /var/lib/containerd`, puis `du -xh --max-depth=2 /var/lib/containerd | sort -h | tail`. Ce qui appartient à containerd (images, couches) se nettoie par containerd et le kubelet (`crictl rmi --prune`, ramasse-miettes d'images), pas à la main ; ce qui n'a rien à y faire se retire, après avoir vérifié ce que c'est.
</details>

**Pour aller plus loin** : mesure le délai entre l'arrêt du kubelet et le passage `NotReady`, puis jusqu'à l'éviction des pods d'un Deployment ; compare avec les valeurs documentées (*Nodes*, *Taint based evictions*). Écris dans RB-140 ce que ce délai implique pour les StatefulSets.

---

### M14-E36 — Panne : des pods restent Pending  `BF` `★★`

> **Ticket INC-4136** — *De : Julien Petit*
> La nouvelle version de l'agenda de test (`agenda`, espace `wb-pannes`) ne se déploie pas : `kubectl rollout status` attend sans fin. L'ancienne version répond encore. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Suivre une mise à jour progressive qui bloque, du Deployment au ReplicaSet puis au pod, et savoir où chaque étage écrit son refus (événements du ReplicaSet, condition `PodScheduled` du pod).
- Lire un message de l'ordonnanceur (`0/6 nodes are available: …`) et l'associer à sa cause : quota, taint, ressources demandées, affinité.
- Corriger au bon endroit (objet de l'équipe, objet de l'espace ou état du nœud) et le reporter dans le code.

**Prérequis** : M14-E10, M14-E14, M14-E16 ; `lab/bin/check 14 36` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : aucune cause n'est liée au stockage (les volumes persistants arrivent au module 16). Un pod refusé par un quota n'est **pas** créé du tout : on ne le voit pas dans `kubectl get pods`. Les zones des nœuds (`topology.kubernetes.io/zone`) ont été posées en M14-E14 ; `k8s-w03` porte la taint `dedie=bdd:NoSchedule`.

**Injection** : `lab/bin/break 14 36` (4 variantes).

**Travail demandé**
1. Suis la chaîne : état du Deployment et de ses ReplicaSets (lequel est nouveau, combien de pods veut-il, combien en a-t-il), pods et leur phase, événements de l'espace triés par date.
2. Explique le blocage en une phrase en citant le message exact (ordonnanceur ou contrôleur de ReplicaSet) et l'objet qui le produit.
3. Corrige à la racine. Si l'objet fautif appartient à l'équipe (manifeste du déploiement) ou à l'espace (quota), dis où il aurait dû être corrigé dans le code (`plateforme/k8s/espaces/` ou dépôt de l'équipe) ; si c'est l'état d'un nœud, retrouve qui l'a modifié.
4. Vérifie que la mise à jour se termine (`rollout status`) et que l'ancienne version a disparu.
5. Commence RB-145 « Un pod ne démarre pas » (`docs/kubernetes/runbooks/`) avec une section `## Pending` : les causes, le message de chacune, la commande qui la confirme.

**Critères de réussite**
- [ ] Le déploiement `agenda` est entièrement à jour et disponible ; aucun pod `Pending` depuis plus de 2 minutes dans les espaces `wb-*` et `mediagenda-*`.
- [ ] Le quota de `wb-pannes` laisse au moins deux pods de marge ; aucune taint `maintenance` ne reste sur les nœuds ; au moins deux travailleurs acceptent des pods sans tolérance.
- [ ] RB-145 contient sa section `Pending` ; ton journal contient le message exact du refus.

**Vérification** : `lab/bin/check 14 36`

<details><summary>Indice 1</summary>

`kubectl -n wb-pannes get deploy,rs,pods -o wide`, puis `kubectl -n wb-pannes describe rs <nouveau-rs>` (section `Events`) et `kubectl -n wb-pannes describe pod <pod-pending>`. `kubectl get events -n wb-pannes --sort-by=.lastTimestamp` met tout dans l'ordre.
</details>

<details><summary>Indice 2</summary>

Le message de l'ordonnanceur compte les nœuds par raison : additionne-les, ils font 6. `kubectl describe resourcequota -n wb-pannes`, `kubectl get nodes -o custom-columns=NOM:.metadata.name,TAINTS:.spec.taints`, `kubectl describe node <travailleur>` (section `Allocatable` et `Allocated resources`) et `kubectl get nodes -L topology.kubernetes.io/zone` répondent chacun à une des raisons possibles.
</details>

**Pour aller plus loin** : reproduis chaque cause dans `wb-essais` avec un pod minimal et compare le message ; essaie `kubectl create -f … --dry-run=server` contre un quota plein : que dit l'API, et pourquoi le ReplicaSet, lui, ne peut pas te répondre aussi directement ?

---

### M14-E37 — Panne : ImagePullBackOff  `BF` `★★`

> **Ticket INC-4137** — *De : Julien Petit*
> *(Le détail s'affiche à l'injection : selon le cas, la nouvelle version de l'agenda de test ou un outil d'équipe tout juste déployé reste en `ErrImagePull` puis `ImagePullBackOff`.)* Remets-le en état sans contourner Harbor, son cache ni sa politique de signature.

**Objectifs pédagogiques**
- Lire la raison exacte d'un échec de tirage dans les événements du pod (`401 Unauthorized`, `not found`, `x509`, délai dépassé) et la relier à son étage : référence d'image, identifiants, configuration du runtime, registre.
- Reproduire un tirage sur le nœud, hors Kubernetes, avec `crictl pull` (avec et sans identifiants) et lire le journal de containerd.
- Connaître la chaîne Secret de tirage → kubelet → CRI → `hosts.toml` → Harbor (projet, cache, robot).

**Prérequis** : M14-E19 (Harbor, `hosts.toml`, `robot$k8s-pull`), M13 (projets, caches, robots) ; `lab/bin/check 14 37` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : le projet `medisphere` de Harbor est privé ; les caches publics (`dockerhub`, `quay`, `ghcr`, `k8s`) sont joints par les nœuds grâce aux fichiers `/etc/containerd/certs.d/<registre>/hosts.toml` (M14-E02, rôle `containerd`), que containerd relit à chaque tirage. Le robot `robot$k8s-pull` et son jeton sont en Vault ; les journaux de Harbor (`/var/log/harbor/` sur `reg01`, M13) disent qui a tiré quoi.

**Injection** : `lab/bin/break 14 37` (4 variantes).

**Travail demandé**
1. Lis l'événement d'échec du pod en entier et classe-le : référence (nom, étiquette, digest), authentification, résolution par le runtime, transport (TLS, réseau).
2. Reproduis sur le nœud où le pod est placé : `crictl pull` avec la même référence, puis, si c'est un problème d'identifiants, avec les identifiants du robot (sans les afficher ni les laisser dans l'historique). Lis `journalctl -u containerd` au moment du tirage.
3. Si c'est utile, vérifie côté Harbor : l'artefact existe-t-il (digest, étiquette) ? Qui a demandé quoi, avec quel compte ?
4. Corrige à la racine (objet Kubernetes, Secret, configuration de containerd par son rôle Ansible) et vérifie que le pod démarre en tirant **par Harbor**.
5. Complète RB-145 avec une section `## ImagePullBackOff` : une ligne par message d'erreur typique, sa cause, la commande qui la prouve.

**Critères de réussite**
- [ ] Aucun conteneur en `ErrImagePull` ni `ImagePullBackOff` dans `kube-system`, `wb-*`, `mediagenda-*`.
- [ ] `agenda` est disponible, avec l'image du projet `medisphere` de Harbor et le Secret de tirage `harbor-pull` ; si l'outil d'équipe `outil-rapport` existe, il est disponible.
- [ ] Le `hosts.toml` de `docker.io` de chaque travailleur pointe vers le cache Harbor ; RB-145 contient sa section `ImagePullBackOff`.

**Vérification** : `lab/bin/check 14 37`

<details><summary>Indice 1</summary>

`kubectl -n wb-pannes describe pod <pod>` : l'événement `Failed` contient la réponse du registre. `kubectl -n wb-pannes get pod <pod> -o jsonpath='{.spec.imagePullSecrets}'` et les événements de type `Warning` qui parlent de *pull secrets* disent ce que le kubelet a réellement utilisé.
</details>

<details><summary>Indice 2</summary>

Sur le nœud : `sudo crictl pull <référence>` (anonyme) puis `sudo crictl pull --creds "$UTILISATEUR:$JETON" <référence>` avec des variables lues sans écho (`read -rs`). Pour un Secret de tirage : `kubectl get secret … -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq 'del(.auths[].password, .auths[].auth)'` montre sa structure sans exposer le secret. `cat /etc/containerd/certs.d/*/hosts.toml` et la documentation de containerd (*Registry Configuration*) expliquent la résolution.
</details>

**Pour aller plus loin** : depuis Kubernetes 1.35, le kubelet sait vérifier qu'un pod a le droit d'utiliser une image **déjà présente** sur le nœud (fonction *KubeletEnsureSecretPulledImages*, à vérifier sur ta version : état, réglages `imagePullCredentialsVerificationPolicy`). Explique quel risque cela ferme pour des équipes qui partagent les travailleurs.

---

### M14-E38 — Panne : CrashLoopBackOff  `BF` `★★`

> **Ticket INC-4138** — *De : Julien Petit*
> Lucas a poussé hier soir une « petite mise à jour de configuration » de l'agenda de test (`agenda`, espace `wb-pannes`). Le nouveau pod démarre, s'arrête, redémarre… `RESTARTS` monte. L'ancienne version tient encore le service. Trouve sans deviner, corrige, et explique à Lucas comment il aurait pu le voir avant de livrer.

**Objectifs pédagogiques**
- Distinguer les façons de mourir d'un conteneur : sortie du processus (code), échec de démarrage par le runtime, mise à mort par le kubelet (sonde de vivacité), par le noyau (OOM), et ce que montre chacune (`lastState.terminated.reason`, `exitCode`, événements, journaux).
- Lire les journaux d'un conteneur qui n'existe plus (`kubectl logs --previous`) et ceux d'un conteneur qui n'a jamais démarré (événements, `crictl`).
- Relier la configuration du déploiement au contrat de l'application (`apps/mediagenda/README.md` : variables, sondes, port, arrêt).

**Prérequis** : M14-E08 (sondes, ressources), M14-E20 ; `lab/bin/check 14 38` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 14 38` (4 variantes).

**Travail demandé**
1. Relève, pour le pod en échec : `restartCount`, `state`, `lastState` (raison, code de sortie, dates), événements. Classe la mort selon les quatre façons de l'objectif 1.
2. Lis ce que le conteneur a dit avant de mourir ; s'il n'a rien dit, explique pourquoi et trouve l'information ailleurs.
3. Compare le déploiement avec sa révision précédente (`kubectl rollout history … --revision=N`, `kubectl diff`) et avec le contrat de l'application.
4. Corrige (retour arrière ou correctif, justifie ton choix) et vérifie que le déploiement se termine sans nouveau redémarrage.
5. Complète RB-145 avec une section `## CrashLoopBackOff` : un tableau « ce que je vois → ce que ça veut dire → commande suivante ».
6. Réponds à Lucas : quelle vérification avant livraison (dans la CI de l'équipe ou par `kubectl apply --dry-run=server`, `kubectl diff`) aurait attrapé le problème, et laquelle ne l'aurait pas attrapé ?

**Critères de réussite**
- [ ] Aucun conteneur en `CrashLoopBackOff` ni en erreur de démarrage dans `wb-*` et `mediagenda-*` ; `agenda` est disponible et aucun de ses pods n'a redémarré plus de deux fois.
- [ ] Le déploiement respecte le contrat de MédiAgenda : variables obligatoires fournies, sonde de vivacité sur `/sante` au port de l'application, limite de mémoire d'au moins 128 Mi, commande de l'image conservée.
- [ ] RB-145 (sections `Pending`, `ImagePullBackOff`, `CrashLoopBackOff`) est publié par MR ; ta réponse à Lucas est dans ton journal.

**Vérification** : `lab/bin/check 14 38`

<details><summary>Indice 1</summary>

`kubectl -n wb-pannes get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState}'` ; `kubectl -n wb-pannes logs <pod> --previous` ; `kubectl -n wb-pannes describe pod <pod>` (événements `Unhealthy`, `Killing`, `BackOff`). Un code de sortie 137 n'a qu'une poignée d'explications ; un code 2 de MédiAgenda en a une seule, écrite dans son README.
</details>

<details><summary>Indice 2</summary>

`kubectl -n wb-pannes rollout history deploy/agenda`, puis `--revision=<N>` pour deux révisions consécutives : la différence est souvent toute la réponse. Pour un conteneur qui ne démarre jamais, sur le nœud : `sudo crictl ps -a --name agenda` et `sudo crictl inspect <id>`.
</details>

**Pour aller plus loin** : mesure la progression du délai de *back-off* (10 s, 20 s, 40 s… plafonné à 5 min) entre deux redémarrages ; lis la page *Pod Lifecycle* et explique pourquoi une sonde de vivacité qui teste une dépendance (la base) transforme une panne de base en tempête de redémarrages.

---

### M14-E39 — Panne : l'API ne répond plus  `BF` `★★★`

> **Ticket INC-4139** — *De : Nadia Roussel ou Karim Benali* — priorité selon le cas
> *(Le détail s'affiche à l'injection : selon le cas, plus personne ne joint l'API, un des trois kube-apiserver redémarre en boucle, ou `kubectl` échoue « une fois sur trois » sur une erreur de certificat.)* InfoGér a travaillé sur les nœuds de contrôle cette nuit.

**Objectifs pédagogiques**
- Parcourir le chemin d'une requête : nom `k8s-api.par1.medisphere.internal` → VIP 10.10.40.200 (keepalived, VRRP) → HAProxy en 8443 → un kube-apiserver en 6443 → etcd local, et tester chaque maillon **séparément**.
- Diagnostiquer un kube-apiserver en pod statique quand l'API est inutilisable : manifeste, `crictl`, journaux du conteneur, `journalctl -u kubelet`.
- Comprendre ce que la haute disponibilité couvre (perte d'un nœud entier) et ce qu'elle ne couvre pas (un maillon défaillant qui ne se déclare pas défaillant, un certificat incohérent entre nœuds).

**Prérequis** : M14-E03, M14-E04, M14-E26, M14-E29 ; M07 (keepalived, HAProxy) ; `lab/bin/check 14 39` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la configuration de keepalived est dans `/etc/keepalived/keepalived.conf`, celle de HAProxy dans `/etc/haproxy/haproxy.cfg` (socket d'administration `/run/haproxy/admin.sock`, M07-E28) ; les deux viennent du rôle `k8s_plan_controle` (M14-E03), qui s'appuie sur les rôles `keepalived` et `haproxy` du M07. Un seul nœud de contrôle est touché.

**Injection** : `lab/bin/break 14 39` (4 variantes).

**Travail demandé**
1. Triage : la VIP répond-elle en TCP sur 8443 (depuis `adm01`) ? Quel nœud la porte ? Chaque kube-apiserver répond-il en direct sur 6443 (`curl -k https://<ip>:6443/livez`, puis avec vérification du certificat) ? Note chaque réponse.
2. Sur le nœud en cause : état des services (keepalived, HAProxy), état des backends vus par HAProxy, filtrage, pod statique du kube-apiserver (`crictl ps -a`, `crictl logs`), certificat présenté. Avance maillon par maillon, sans redémarrer quoi que ce soit avant d'avoir une hypothèse.
3. Corrige à la racine. Si le défaut vient d'une modification d'un fichier géré par Ansible, la correction passe par le rôle : rejoue-le en `--check --diff` sur le nœud pour **prouver** l'écart, puis applique-le.
4. Explique pourquoi la haute disponibilité n'a pas suffi dans ton cas, et ce qu'il faudrait changer pour qu'elle suffise (contrôle de keepalived, contrôles de santé de HAProxy, cohérence des certificats).
5. Rédige `RB-146 — L'API ne répond plus` dans `docs/kubernetes/runbooks/` : un test par maillon dans l'ordre, l'accès sans VIP, l'accès en bris de glace, ce qu'il ne faut pas faire.

**Critères de réussite**
- [ ] L'API répond par la VIP ; chacun des trois kube-apiserver répond en direct avec un certificat valable pour le nom **et** l'adresse de la VIP.
- [ ] HAProxy et keepalived actifs sur les trois nœuds, VIP portée par un seul ; keepalived suit son contrôle de santé s'il en définit un ; aucune règle de filtrage ne jette le 8443 ; le manifeste du kube-apiserver vise l'etcd local.
- [ ] RB-146 est publié ; ton journal contient le résultat de chaque test du triage et la preuve de la cause.

**Vérification** : `lab/bin/check 14 39`

<details><summary>Indice 1</summary>

Depuis `adm01` : `nc -vz -w 3 10.10.40.200 8443`, `curl -k https://10.10.40.200:8443/livez`, puis la même chose vers 10.10.40.51-53 en 6443. `kubectl --server https://10.10.40.52:6443 get nodes` contourne la VIP (le certificat doit alors contenir l'adresse visée). « Connexion refusée », « délai dépassé » et « erreur TLS » ne désignent pas le même maillon.
</details>

<details><summary>Indice 2</summary>

Sur un nœud de contrôle : `ip -br addr`, `systemctl status keepalived haproxy`, `journalctl -t Keepalived_vrrp -t keepalived --since -2h`, `echo 'show stat' | sudo socat stdio /run/haproxy/admin.sock | cut -d, -f1,2,18`, `sudo nft list ruleset`, `sudo crictl ps -a --name kube-apiserver`, `sudo crictl logs <id> 2>&1 | tail`. Pour un certificat : `openssl s_client -connect <ip>:6443 </dev/null | openssl x509 -noout -ext subjectAltName`.
</details>

<details><summary>Indice 3</summary>

kubeadm refuse de réutiliser un certificat existant qui ne correspond plus à la configuration ; il ne le remplace pas non plus de lui-même. La configuration du cluster est dans le ConfigMap `kubeadm-config` de `kube-system` ; lis `kubeadm init phase certs apiserver --help`. Le kubelet surveille `/etc/kubernetes/manifests/` : un fichier modifié y est appliqué, un fichier de sauvegarde laissé dans ce dossier aussi.
</details>

**Pour aller plus loin** : ajoute à ton lab un contrôle qui compare, sur les trois nœuds, l'empreinte des SAN du certificat `apiserver.crt` et l'état des backends HAProxy, et propose où l'exécuter (minuterie sur `adm01`, pipeline planifié) en attendant la supervision du module 21.

---

### M14-E40 — Panne : un membre etcd est en détresse  `BF` `★★★`

> **Ticket INC-4140** — *De : Karim Benali ou Nadia Roussel*
> *(Le détail s'affiche à l'injection : selon le cas, un membre etcd signalé en échec, ou plus aucune écriture possible dans le cluster.)* Un instantané etcd de sécurité a été pris avant l'incident : il ne sert qu'en dernier recours.

**Objectifs pédagogiques**
- Évaluer un etcd en difficulté avec ses propres outils : `etcdctl member list`, `endpoint status` et `endpoint health` sur les trois membres, `alarm list`, journaux du membre ; savoir ce qu'on peut faire avec un quorum de 2 sur 3, et ce qu'on ne fait pas.
- Remplacer proprement un membre dont les données sont perdues (retrait, nettoyage, ré-ajout), sans restauration d'instantané.
- Comprendre le quota d'espace d'etcd, l'alarme `NOSPACE`, la différence entre compactage (historique) et défragmentation (fichier), et le lien avec le temps (certificats, horloges).

**Prérequis** : M14-E24 (etcd, RB-141), M14-E29 (perte et remplacement d'un nœud de contrôle) ; M00 (temps synchronisé) ; `lab/bin/check 14 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : etcd est empilé (un membre par nœud de contrôle, pod statique `etcd-k8s-cp0X`, données dans `/var/lib/etcd`, certificats dans `/etc/kubernetes/pki/etcd/`). Points d'accès clients : `https://10.10.40.51-53:2379`, pairs en 2380, métriques en `http://127.0.0.1:2381`. `etcdctl` et `etcdutl` sont sur les nœuds de contrôle (M14-E24) ; utilise `healthcheck-client.crt` pour les lectures. Un seul membre est touché.

> ⚠️ **Attention** : avec un membre hors service, un seul faux pas sur un **autre** nœud de contrôle coûte le quorum, et donc l'API. Ne redémarre, ne modifie et ne retire rien d'autre que le membre en cause ; avant tout `member remove`, vérifie deux fois l'identifiant (celui du membre malade, jamais d'un sain) et que les deux autres sont en bonne santé. Garde ton instantané de M14-E24 à portée.

**Injection** : `lab/bin/break 14 40` (3 variantes).

**Travail demandé**
1. Constate depuis un nœud **sain** : liste des membres, santé et état de chacun (leader, révision, taille de la base, taille utilisée), alarmes. Combien de membres faut-il pour écrire ? Combien en reste-t-il ?
2. Sur le nœud du membre en cause (ou sur le cluster entier si tout refuse d'écrire) : journaux du conteneur etcd (`crictl logs`), manifeste, données, horloge, certificats. Formule la cause en une phrase avec sa preuve.
3. Corrige sans perte : selon la cause, rends au membre ce qui lui manque, ou remplace-le (procédure de M14-E29 et RB-144), ou libère de l'espace (trouve ce qui remplit la base, supprime-le si et seulement si ce n'est pas un objet de Kubernetes, compacte, défragmente membre par membre, lève l'alarme) et retire la cause du dépassement.
4. Vérifie : trois membres sains, aucune alarme, écritures possibles (`kubectl create configmap essai-e40 -n wb-essais --dry-run=server`, puis pour de vrai et supprime-le).
5. Rédige `RB-147 — etcd en détresse` (`docs/kubernetes/runbooks/`) : les états possibles d'un membre, l'arbre « rendre / remplacer / restaurer », les commandes interdites tant qu'il reste un quorum, l'alarme `NOSPACE` pas à pas.

**Critères de réussite**
- [ ] Trois membres démarrés et en bonne santé, aucune alarme, aucune clé hors de `/registry/`.
- [ ] Sur chaque nœud de contrôle : quota d'espace etcd par défaut ou d'au moins 2 Gio, horloge synchronisée, écart avec `adm01` inférieur à 5 s.
- [ ] RB-147 est publié ; ton journal contient l'état initial des trois membres et la preuve de la cause ; aucune restauration d'instantané n'a été faite.

**Vérification** : `lab/bin/check 14 40`

<details><summary>Indice 1</summary>

Sur un nœud sain : `sudo ETCDCTL_API=3 etcdctl --endpoints=https://10.10.40.51:2379,https://10.10.40.52:2379,https://10.10.40.53:2379 --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/healthcheck-client.crt --key /etc/kubernetes/pki/etcd/healthcheck-client.key endpoint status -w table` (puis `endpoint health`, `member list -w table`, `alarm list`). Une variable d'environnement par option (`ETCDCTL_ENDPOINTS`, `ETCDCTL_CACERT`…) allège la suite.
</details>

<details><summary>Indice 2</summary>

`sudo crictl ps -a --name etcd` puis `sudo crictl logs <id> 2>&1 | tail -n 30` sur le nœud en cause. Un membre qui ne peut pas ouvrir sa base, un membre qui ne fait plus confiance à ses pairs et un cluster qui refuse d'écrire laissent trois messages très différents. `timedatectl`, `chronyc tracking` et `openssl x509 -noout -dates` répondent à la question du temps ; SSH peut te lâcher dans un cas : la console te reste.
</details>

<details><summary>Indice 3</summary>

Pour l'espace : `etcdctl get "" --from-key --keys-only | cut -d/ -f2 | sort | uniq -c`, puis la documentation *etcd — Maintenance* (*Space quota*, *Defragmentation*, *History compaction*) : l'ordre des opérations compte, et la défragmentation se fait **un membre à la fois**. Le quota d'un membre se lit dans son manifeste ; la valeur par défaut est documentée.
</details>

**Pour aller plus loin** : compare la taille physique et la taille utilisée de la base (`dbSize`, `dbSizeInUse`) sur trois semaines de fonctionnement du lab ; propose dans RB-147 un seuil d'alerte et une défragmentation planifiée (à quelle heure, avec quelle précaution pour le leader).

---

### M14-E41 — Panne : accès refusé  `BF` `★★★`

> **Ticket INC-4141** — *De : selon le cas, toi-même, Julien Petit ou Nadia Roussel*
> *(Le détail s'affiche à l'injection : `Unauthorized` sur ton propre poste, `Forbidden` pour une équipe, une création de pod refusée, ou une application qui ne lit plus l'API.)* Rends l'accès, ni plus ni moins qu'avant, sans `admin.conf` sauf bris de glace justifié.

**Objectifs pédagogiques**
- Distinguer les trois portes de l'API et leurs messages : authentification (`401 Unauthorized`), autorisation (`403 Forbidden … cannot <verbe> resource …`), admission (`admission webhook` / `ValidatingAdmissionPolicy … denied request`, Pod Security).
- Interroger l'API sur les droits d'un autre (`kubectl auth can-i --as … --as-group …`, `--list`), lire une chaîne RBAC (sujet → liaison → rôle → règles) et le journal d'audit (M14-E27).
- Corriger une identité humaine (certificat client, M14-E12) et une identité de charge de travail (compte de service, jeton lié, M14-E13) sans élargir les droits.

**Prérequis** : M14-E11, M14-E12, M14-E13, M14-E18, M14-E27 ; `lab/bin/check 14 41` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Injection** : `lab/bin/break 14 41` (4 variantes).

**Travail demandé**
1. Classe le refus : quelle porte, quel message exact, quelle identité (utilisateur, groupes) l'API a-t-elle vue ? Si c'est ton accès qui est en cause, trouve une identité de secours **légitime** avant de sortir `admin.conf`.
2. Remonte la chaîne : pour l'authentification, le certificat présenté (émetteur, sujet, dates) ; pour l'autorisation, les liaisons qui devraient s'appliquer et leurs sujets exacts ; pour l'admission, la politique qui refuse et son expression ; pour un compte de service, ce que voit le pod (jeton monté, identité, droits).
3. Retrouve dans le journal d'audit (M14-E27) qui a modifié l'objet en cause et quand, si c'est un objet de l'API.
4. Corrige à la racine, au bon endroit (`outils/kubeconfig-personnel.sh`, `plateforme/k8s/rbac/`, `plateforme/k8s/admission/`), sans donner un droit de plus que nécessaire ; pour une politique de sécurité, corrige-la sans la désactiver et teste-la (`--dry-run=server`, `validationActions: [Warn]` le temps d'un essai).
5. Rédige `RB-148 — Accès refusé` (`docs/kubernetes/runbooks/`) : un tableau message → porte → première commande, et la procédure de bris de glace (où est `admin.conf`, qui l'autorise, comment on le détruit après usage, comment on trace son usage).

**Critères de réussite**
- [ ] Ton kubeconfig personnel est accepté par l'API, hors du groupe `system:masters`, avec un certificat valable plus de 24 h.
- [ ] Le groupe `medisphere:mediagenda-devs` a son RoleBinding dans `mediagenda-dev` ; un pod avec un volume `emptyDir` est admis dans `wb-pannes` ; les témoins `postgres` et `sonde-api` sont disponibles et `sonde-api` n'a que son rôle.
- [ ] RB-148 est publié ; ton journal contient le message exact du refus, l'identité vue par l'API et, s'il y a lieu, l'entrée d'audit de la modification.

**Vérification** : `lab/bin/check 14 41`

<details><summary>Indice 1</summary>

`kubectl auth whoami` dit qui tu es pour l'API (quand elle t'accepte). `kubectl config view --raw --minify -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -subject -issuer -dates` dit ce que tu présentes. `kubectl auth can-i --list -n mediagenda-dev --as julien.petit --as-group medisphere:mediagenda-devs` dit ce qu'une équipe peut faire.
</details>

<details><summary>Indice 2</summary>

Un refus d'admission cite la politique et la liaison (`kubectl get validatingadmissionpolicies,validatingadmissionpolicybindings`) ; le message d'un ReplicaSet qui ne peut pas créer ses pods est dans ses événements. Pour un compte de service : `kubectl -n wb-pannes logs deploy/sonde-api`, `kubectl auth can-i list pods -n wb-pannes --as system:serviceaccount:wb-pannes:sonde-api`, puis la liaison et ses sujets **champ par champ**.
</details>

**Pour aller plus loin** : écris un test qui, pour chaque groupe MédiSphère et chaque espace, compare `kubectl auth can-i --list` à une matrice attendue versionnée dans `plateforme/k8s/rbac/` ; il deviendra un job de CI au module 19.

---

### M14-E42 — Panne : le DNS du cluster ne répond plus  `BF` `★★★`

> **Ticket INC-4142** — *De : Nadia Roussel ou Julien Petit*
> *(Le détail s'affiche à l'injection : selon le cas, des erreurs « no such host » dans plusieurs équipes, ou une nouvelle version de l'agenda de test qui ne trouve plus sa base.)* Les nœuds eux-mêmes résolvent normalement.

**Objectifs pédagogiques**
- Suivre une résolution de nom depuis un pod : `/etc/resolv.conf` du pod (serveur, domaines de recherche, `ndots`), `dnsPolicy`, Service `kube-dns`, pods CoreDNS, Corefile (zones, greffons `kubernetes`, `forward`, `cache`, `reload`), récurseurs de MédiSphère.
- Tester chaque maillon séparément depuis un pod de diagnostic (`nslookup`, `dig` dans un conteneur éphémère, M14-E20) et depuis un nœud.
- Corriger un composant de plateforme géré par kubeadm sans le casser au prochain `kubeadm upgrade`.

**Prérequis** : M14-E07, M14-E20, M14-E25 ; M06 (récurseurs `dns01`/`dns02`) ; `lab/bin/check 14 42` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : CoreDNS est installé par kubeadm (déploiement `coredns` et ConfigMap `coredns` dans `kube-system`, Service `kube-dns` en 10.96.0.10). Le Corefile transmet ce qui n'est pas `cluster.local` au résolveur des nœuds (au module 15, il pointera explicitement vers `dns01`/`dns02`). Pas de NetworkPolicy dans le cluster (elles arrivent au module 15) : n'en cherche pas.

**Injection** : `lab/bin/break 14 42` (4 variantes).

**Travail demandé**
1. Reproduis depuis un pod : un nom de Service court, un nom complet `*.svc.cluster.local`, un nom MédiSphère, un nom Internet. Note lesquels passent. Lis le `/etc/resolv.conf` du pod.
2. Teste les maillons : Service `kube-dns` et ses points d'accès, pods CoreDNS (état, journaux), Corefile, résolution directe vers l'adresse d'un pod CoreDNS, puis vers les récurseurs depuis un nœud.
3. Trouve la cause racine ; si c'est une modification de configuration, retrouve-la (événements, journal d'audit, annotations).
4. Corrige sans supprimer ni recréer CoreDNS ; vérifie les quatre résolutions de l'étape 1 et la disponibilité de `sonde-dns`.
5. Rédige `RB-149 — DNS du cluster` (`docs/kubernetes/runbooks/`) : schéma du chemin d'une requête, un test par maillon, les pièges (`ndots:5`, `dnsPolicy`, cache, `reload`, boucle de transfert), et comment la modification du Corefile doit être portée par le code.

**Critères de réussite**
- [ ] `coredns` a au moins deux réplicas, tous disponibles, et `kube-dns` au moins deux points d'accès prêts ; le Corefile sert `cluster.local` et transfère vers le résolveur des nœuds ou `dns01`/`dns02`.
- [ ] `sonde-dns` et `agenda` (en `dnsPolicy` par défaut) sont disponibles.
- [ ] RB-149 est publié ; ton journal contient les quatre résolutions de l'étape 1, avant et après.

**Vérification** : `lab/bin/check 14 42`

<details><summary>Indice 1</summary>

`kubectl -n wb-pannes exec deploy/sonde-dns -- cat /etc/resolv.conf`, puis `nslookup` des quatre noms ; `kubectl -n kube-system get deploy,pods,endpointslices -l k8s-app=kube-dns` ; `kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20`. Pour un pod d'une application : `kubectl get pod <pod> -o jsonpath='{.spec.dnsPolicy}'`.
</details>

<details><summary>Indice 2</summary>

`kubectl -n kube-system get configmap coredns -o yaml` ; la page *Customizing DNS Service* et la documentation des greffons de CoreDNS (`forward`, `cache`, `reload`) disent ce qu'est un Corefile valide et combien de temps une modification met à être prise en compte. `kubectl debug -it <pod> --image=registry.par1.medisphere.internal/dockerhub/library/busybox:1.37 --target=<conteneur>` donne des outils dans un pod qui n'en a pas.
</details>

**Pour aller plus loin** : mesure combien de requêtes DNS déclenche une seule résolution de `registry.par1.medisphere.internal` depuis un pod avec `ndots:5` (journaux de CoreDNS avec le greffon `log` activé **temporairement**), puis avec le nom terminé par un point ; écris la recommandation pour les équipes.

---

### M14-E43 — Astreinte : le cluster en détresse  `BF` `★★★★`

> **Ticket INC-4150** — *De : Nadia Roussel (responsable astreinte)* — priorité P1
> Tu es d'astreinte. Jeudi, 4 h 05 : plusieurs remontées sur le cluster `k8s-par1` (le détail s'affiche à l'injection). La recette de MédiAgenda commence à 8 h sur ce cluster : il doit être sain d'ici là. Tiens-moi informée toutes les 30 minutes, puis rédige le post-mortem avec le modèle de l'équipe.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples sur un cluster : trier, prioriser par dépendances (accès à l'API et etcd avant tout, puis nœuds, puis DNS et admission, puis charges de travail), éviter qu'une panne en masque une autre.
- Protéger le cluster pendant l'incident : pas de geste interdit du palier, un seul nœud de contrôle à la fois sauf nécessité argumentée, instantané etcd en dernier recours seulement.
- Communiquer pendant l'incident et rédiger un post-mortem sans recherche de coupable.

**Prérequis** : M14-E35 à M14-E42 (au moins une variante de chacun).
**Durée indicative** : 2 h 30 de rétablissement + 45 min de post-mortem.

**Contexte technique** : le script tire **trois** pannes distinctes parmi celles de M14-E35 à M14-E42 (au plus une parmi E36, E37 et E38), avec une variante au hasard pour chacune, et les injecte ensemble. C'est le seul exercice où deux nœuds de contrôle peuvent être touchés en même temps : le script prend d'abord un **instantané etcd** et le vérifie ; il te dit où il se trouve. Les symptômes peuvent se recouvrir (une API muette masque tout le reste ; un nœud perdu ressemble à un problème de DNS quand CoreDNS y tournait). `--variante N` (1 à 40) force le trio, pas les variantes. `--annuler` retire les trois. Modèle de post-mortem : [`modules/00-lab/ressources/M00-E46/modele-post-mortem.md`](../../00-lab/ressources/M00-E46/modele-post-mortem.md).

**Injection** : `lab/bin/break 14 43`

**Travail demandé**
1. **Triage (10 min max)** : liste les symptômes, leur impact métier (qui ne peut plus faire quoi ?) et une hypothèse de regroupement. Vérifie d'abord tes instruments : ton `kubectl`, l'API par la VIP et en direct, SSH et console vers chaque nœud, `etcdctl` depuis un nœud de contrôle. Envoie la première communication.
2. **Diagnostic** : traite les pannes dans un ordre que tu justifies par les dépendances. Tiens ton journal horodaté ; garde les sorties qui prouvent chaque cause.
3. **Rétablissement** : corrige chaque cause racine ; après chaque correction, relance **tous** tes tests de départ.
4. **Clôture** : communication de fin d'incident, `--annuler` pour clore, puis post-mortem dans `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-4150.md`, publié par MR.

**Critères de réussite**
- [ ] Toutes les vérifications de M14-E35 à M14-E42 sont vertes (le contrôle les rejoue toutes) et aucune panne n'est encore marquée active.
- [ ] Le post-mortem existe, contient une chronologie horodatée, les trois causes racines, des extraits de commandes de diagnostic, l'analyse de la détection (qu'est-ce qui aurait dû alerter avant Nadia ?), des actions correctives avec responsable et échéance, et aucun secret.
- [ ] Le journal contient au moins quatre communications d'incident espacées d'environ 30 minutes ; si tu as utilisé `admin.conf`, le post-mortem dit quand, pourquoi, et quand il a été détruit.

**Vérification** : `lab/bin/check 14 43`

<details><summary>Indice 1</summary>

Ordre des dépendances : point d'accès de l'API (VIP, HAProxy, kube-apiserver) et etcd (quorum, espace) → ton identité → nœuds (kubelet, runtime) → composants de plateforme (CoreDNS, admission) → charges de travail (ordonnancement, images, démarrage). Une panne plus bas fausse les tests de tout ce qui est au-dessus.
</details>

<details><summary>Indice 2</summary>

Les contrôles `lab/bin/check 14 35` à `14 42` sont des sondes ciblées : lance-les pendant le triage pour cartographier ce qui est rouge. Un contrôle rouge n'est pas forcément une panne injectée : ce peut être la conséquence d'une autre (un pod `Pending` sur un cluster dont deux travailleurs sont perdus, un DNS muet parce que CoreDNS ne peut pas être recréé).
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), et chronomètre le temps jusqu'au **premier diagnostic juste** en plus du temps de rétablissement : c'est le chiffre que la supervision du module 21 doit faire baisser.

---

### M14-E44 — Sous le capot : du `kubectl apply` au conteneur  `LAB` `★★★★`

> **Ticket PLAT-1544** — *De : Karim Benali*
> Pendant les pannes, tout le monde a parlé de « watch », de « l'ordonnanceur qui place », du « kubelet qui lance » comme de choses magiques. Je veux que tu saches **montrer** le chemin complet d'un pod : la requête à l'API et ce qu'en voient les contrôleurs, la décision de placement (et la faire toi-même), puis ce que fait le nœud jusqu'au processus dans son cgroup, en le prouvant à chaque étape avec un outil différent. Compte rendu pour les prochains arrivants.

**Objectifs pédagogiques**
- Parler à l'API sans `kubectl` : authentification par certificat client, *list* et *watch*, `resourceVersion`, concurrence optimiste (`409 Conflict`), expiration d'un *watch* (`410 Gone`), signets (*bookmarks*) ; relier ces mécanismes aux *informers* des contrôleurs.
- Comprendre l'ordonnanceur en le remplaçant : un pod confié à un ordonnanceur qui n'existe pas, lié à la main par la sous-ressource `binding`.
- Suivre le pod sur le nœud : kubelet → CRI (`crictl`) → containerd (`ctr -n k8s.io`) → shim → runc ; conteneur `pause` et espaces de noms partagés ; cgroup du pod et traduction des `requests`/`limits` (QoS) en `cpu.max`, `cpu.weight`, `memory.max`.

**Prérequis** : M14-E06, M14-E08, M14-E12, M14-E20 ; M12-E09 et M12-E44 (conteneurs sous le capot).
**Durée indicative** : 3 h.

**Contexte technique**
- Travaille dans `~/capot` sur `adm01` (crée-le en 700). Tu y extrais **temporairement** ton certificat client et ta clé depuis `~/.kube/config` : supprime-les à la fin (le contrôle vérifie qu'aucune clé privée ne reste dans ce dossier).
- L'espace d'essai est `wb-essais` ; le pod d'étude s'appelle `capot`. Image : `registry.par1.medisphere.internal/dockerhub/library/busybox:1.37`.
- Sur un travailleur, `crictl` et `ctr` lisent containerd ; les espaces de noms de containerd utilisés par Kubernetes sont dans `k8s.io`. Les cgroups sont en v2 avec le pilote systemd (`/sys/fs/cgroup/kubepods.slice/…`).

> ⚠️ **Attention** : `ctr` et `crictl` savent aussi **arrêter** et **supprimer** (`ctr task kill`, `crictl rm`, `crictl rmp`, `ctr images rm`). Dans cet exercice, seules les commandes de lecture sont permises sur les nœuds (`ls`, `ps`, `pods`, `inspect`, `inspectp`, `info`, `images`, `stats`). Un conteneur supprimé sous le kubelet est recréé, mais c'est un geste à ne pas prendre l'habitude de faire en production.

**Travail demandé**
1. **L'API à la main.** Extrais dans `~/capot` ton certificat, ta clé et la CA du cluster (`kubectl config view --raw --minify -o jsonpath=…`, `base64 -d`, `chmod 600`). Avec `curl --cacert --cert --key`, liste les ConfigMaps de `wb-essais` (`GET /api/v1/namespaces/wb-essais/configmaps`) et relève le `metadata.resourceVersion` de la **liste**. Lance un *watch* à partir de cette version (`?watch=1&resourceVersion=<rv>&allowWatchBookmarks=true`) dans un terminal ; dans un autre, crée, modifie puis supprime une ConfigMap `capot` avec `kubectl`. Relève les événements `ADDED`, `MODIFIED`, `DELETED` et leurs versions.
2. **Concurrence optimiste.** Lis la ConfigMap `capot` recréée, modifie-la avec `kubectl`, puis renvoie avec `curl -X PUT` l'ancienne version (avec son ancien `resourceVersion`). Relève le code et le message. Puis relance un *watch* depuis une version très ancienne (la toute première relevée, après plus de 5 minutes et quelques écritures dans le cluster) : que répond l'API ? Compare avec ce que fait `kubectl get configmaps -n wb-essais -w -v=6`.
3. **L'ordonnanceur, c'est toi.** Crée le pod `capot` (manifeste à écrire : `schedulerName: ordonnanceur-manuel`, une limite de 200m CPU et 64 Mi de mémoire pour une demande moitié moindre, profil `restricted` respecté, commande qui dort longtemps). Constate qu'il reste `Pending` sans aucun événement de l'ordonnanceur ; relève qui détient le bail de l'ordonnanceur par défaut (`kubectl -n kube-system get lease kube-scheduler -o yaml`). Puis lie-le toi-même à `k8s-w02` par un `POST` d'un objet `Binding` sur `…/pods/capot/binding` avec `curl`. Constate le démarrage et les événements.
4. **Le kubelet et le CRI.** Sur `k8s-w02` : `crictl pods --name capot`, `crictl inspectp <id>` (espace réseau, adresse, `runtimeHandler`), `crictl ps --pod <id>`, `crictl inspect <id-conteneur>` (PID, `cgroupsPath`, espec OCI), `ctr -n k8s.io containers ls` et `ctr -n k8s.io tasks ls` (retrouve le conteneur `pause` et celui de busybox), arbre des processus depuis le `containerd-shim-runc-v2` (`ps -ef --forest` ou `pstree -p`).
5. **Cgroups et espaces de noms.** À partir du PID : `cat /proc/<pid>/cgroup`, puis dans le dossier du cgroup du conteneur et de celui du pod : `cpu.max`, `cpu.weight`, `memory.max`, `memory.current`. Retrouve la classe QoS du pod (`kubectl get pod capot -o jsonpath='{.status.qosClass}'`) et le chemin `kubepods-<qos>.slice`. Compare `ls -l /proc/<pid>/ns/` du conteneur busybox et du conteneur `pause` : lesquels sont partagés ? Entre dans l'espace réseau du pod avec `nsenter -t <pid> -n ip -br addr` et compare à l'adresse du pod.
6. **Compte rendu.** Rédige `docs/kubernetes/analyses/du-apply-au-conteneur.md` : `## L'API : list, watch et resourceVersion` (étapes 1-2), `## L'ordonnanceur` (étape 3), `## Le kubelet et le CRI` (étape 4), `## Cgroups et espaces de noms` (étape 5, avec le nom du nœud et les valeurs relevées), puis `## Réponses aux questions`. Aucune clé, aucun jeton, aucun contenu de certificat dans le compte rendu. Publie-le par MR, puis supprime le contenu de `~/capot`. Laisse le pod `capot` en place jusqu'au contrôle.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Pourquoi les contrôleurs utilisent-ils *list* puis *watch* plutôt que d'interroger l'API en boucle ? Que fait un *informer* quand il reçoit `410 Gone` ?
2. Que garantit `resourceVersion` et que ne garantit-il pas (ordre, valeur numérique, comparaison entre types d'objets) ? Pourquoi ne faut-il pas le comparer comme un nombre ?
3. Qu'a vérifié l'API quand tu as créé l'objet `Binding` (droits, état du pod) ? Quel droit RBAC un ordonnanceur personnalisé doit-il avoir ?
4. Pourquoi tous les conteneurs d'un pod partagent-ils l'espace réseau du conteneur `pause`, et pas forcément l'espace des PID ? Que change `shareProcessNamespace: true` ?
5. Comment le kubelet traduit-il `requests.cpu` et `limits.cpu` en `cpu.weight` et `cpu.max` ? Que se passe-t-il quand un conteneur dépasse `limits.cpu`, et quand il dépasse `limits.memory` ?
6. Que se passe-t-il pour les conteneurs d'un nœud si containerd s'arrête ? Et si le kubelet s'arrête ? (Relie à M14-E35.)
7. Que contient la sortie de `crictl inspectp` que `kubectl describe pod` ne montre pas, et pourquoi est-ce utile en panne ?

**Critères de réussite**
- [ ] Le compte rendu existe, est commité, contient les sections demandées, cite `resourceVersion`, *watch*, `binding`, `crictl`, `pause` et les cgroups, et mentionne le nœud réel du pod `capot`.
- [ ] Les 7 questions sont traitées ; aucune clé ni jeton dans le compte rendu.
- [ ] Le pod `capot` de `wb-essais` est en marche sur un travailleur avec `schedulerName: ordonnanceur-manuel` et des limites ; `~/capot` ne contient plus de clé privée.

**Vérification** : `lab/bin/check 14 44`

<details><summary>Indice 1</summary>

`curl -sS --cacert ca.crt --cert moi.crt --key moi.key "https://k8s-api.par1.medisphere.internal:8443/api/v1/namespaces/wb-essais/configmaps" | jq .metadata` ; pour le *watch*, ajoute `-N` (pas de mise en tampon) : chaque ligne est un événement JSON. La page *Kubernetes API Concepts* (sections *Efficient detection of changes*, *Resource versions*) explique les codes que tu vas rencontrer.
</details>

<details><summary>Indice 2</summary>

Un `Binding` est un petit objet : `apiVersion: v1`, `kind: Binding`, `metadata.name` = nom du pod, `target` = référence au nœud (`apiVersion: v1`, `kind: Node`, `name`). Envoie-le en JSON avec `-H 'Content-Type: application/json' --data @binding.json`. Consulte `kubectl explain binding` (l'objet est marqué déprécié dans l'API, à vérifier sur ta version, mais c'est toujours la sous-ressource `pods/binding` qu'utilise l'ordonnanceur).
</details>

<details><summary>Indice 3</summary>

`crictl inspect <id> | jq '.info.pid, .info.runtimeSpec.linux.cgroupsPath'` ; avec le pilote systemd, `cgroupsPath` a la forme `<tranche>:<préfixe>:<id>` et le dossier réel est sous `/sys/fs/cgroup/kubepods.slice/`. `systemd-cgls --unit kubepods.slice` donne l'arborescence.
</details>

**Pour aller plus loin** : suis la même création de pod dans le journal d'audit (M14-E27) : combien de requêtes, de quels utilisateurs (toi, `system:kube-scheduler`, `system:node:k8s-w02`), dans quel ordre ? Ajoute la chronologie au compte rendu.

---

### M14-E45 — Questions expert : Kubernetes  `Q` `★★★`

> **Ticket PLAT-1545** — *De : Karim Benali*
> Dernière étape avant la recette de Kubernetes v1 : ces questions, je les pose en entretien pour un poste d'ingénieur plateforme. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes de Kubernetes manipulés dans ce module (API, etcd, ordonnancement, kubelet, runtime, réseau du cluster, sécurité, cycle de vie).
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M14-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Décris le chemin d'un `kubectl apply` d'un Deployment jusqu'au processus qui tourne sur un nœud : quels composants interviennent, dans quel ordre, qui écrit quoi dans etcd, qui lit quoi par *watch* ?
2. QCM — Un cluster a trois membres etcd. Deux tombent en même temps. Que se passe-t-il ?
   a) l'API continue de servir les lectures et les écritures depuis le membre restant ; b) l'API refuse les écritures, les lectures cohérentes (*linearizable*) échouent, les pods déjà lancés continuent de tourner ; c) les kubelets arrêtent tous les pods par sécurité ; d) le membre restant devient leader et le cluster se reconfigure à un membre.
3. Pourquoi etcd et pas une base relationnelle ? Qu'apportent le modèle MVCC, les révisions et le *watch* à Kubernetes ? Pourquoi faut-il compacter et défragmenter ?
4. Explique les admissions dans l'ordre : authentification, autorisation, admission mutante, validation du schéma, admission validante. Où se placent Pod Security, une `ValidatingAdmissionPolicy`, une `MutatingAdmissionPolicy` (GA en 1.36) et un *webhook* ? Que se passe-t-il quand un *webhook* en `failurePolicy: Fail` est injoignable ?
5. QCM — Un pod a `requests.memory: 128Mi` et `limits.memory: 256Mi`. Le nœud manque de mémoire. Quelle affirmation est vraie ?
   a) le pod est protégé tant qu'il reste sous 256 Mi ; b) le pod est de classe `Burstable` et peut être évincé par le kubelet avant les pods `Guaranteed`, et tué par le noyau s'il dépasse 256 Mi ; c) le kubelet réduit sa limite à 128 Mi ; d) seuls les pods `BestEffort` peuvent être évincés.
6. Différence entre un conteneur tué par le noyau (OOM) et une éviction par le kubelet : qui décide, sur quel critère, ce que voit l'utilisateur, ce qui se passe ensuite pour un pod de Deployment et pour un pod nu.
7. Comment fonctionne la haute disponibilité de `kube-controller-manager` et `kube-scheduler` ? Que se passe-t-il si deux instances se croient leader ?
8. Comment l'ordonnanceur choisit-il un nœud (filtrage, score, liaison) ? Pourquoi un pod peut-il rester `Pending` alors qu'un nœud « a de la place » au sens de `kubectl top` ?
9. QCM — Tu draines un nœud qui porte un pod d'un Deployment à 2 réplicas avec une PDB `minAvailable: 2`. Que se passe-t-il ?
   a) le drain supprime le pod et la PDB est ignorée ; b) le drain attend indéfiniment (ou jusqu'à son délai) car l'éviction est refusée ; c) le drain réussit car la PDB ne concerne que les suppressions volontaires de l'utilisateur ; d) le drain crée d'abord un troisième pod puis évince l'ancien.
10. Qu'est-ce qu'un jeton de compte de service lié (*bound*) ? Que vérifie l'API à sa présentation ? Pourquoi les Secrets `kubernetes.io/service-account-token` sont-ils devenus une exception à justifier (celui de `wb-checks` en est une) ?
11. kubeadm : pourquoi `admin.conf` (groupe `kubeadm:cluster-admins`) **et** `super-admin.conf` (`system:masters`) ? Pourquoi `system:masters` est-il dangereux même pour un administrateur ?
12. Que se passe-t-il quand la CA du cluster expire ? Et quand le certificat `apiserver-kubelet-client` expire ? Comment le sais-tu à l'avance, et que fait `kubeadm upgrade` de ces certificats ?
13. Cilium remplace-t-il kube-proxy dans `k8s-par1` au module 14 ? Quel composant traduit un Service ClusterIP en règles, et qu'est-ce qui change quand Cilium le remplace (module 15) ?
14. QCM — Un pod en `dnsPolicy: ClusterFirst` résout `registry.par1.medisphere.internal`. Avec `ndots:5`, quelle est la première requête envoyée ?
    a) `registry.par1.medisphere.internal.` ; b) `registry.par1.medisphere.internal.wb-pannes.svc.cluster.local.` ; c) `registry.` ; d) aucune : le nom est résolu par le kubelet.
15. Pourquoi Kubernetes refuse-t-il par défaut de démarrer le kubelet avec du swap, et qu'a changé *NodeSwap* (GA en 1.34) ? Pourquoi kubeadm exige-t-il toujours un réglage explicite ?
16. cgroup v1 : pourquoi le kubelet 1.35+ refuse-t-il de démarrer dessus par défaut ? Quel rapport entre le pilote de cgroups de containerd (`SystemdCgroup`) et celui du kubelet depuis que le kubelet le lit dans le CRI ?
17. Décris une montée de version mineure kubeadm sur un cluster HA : ordre des composants, règle de décalage de versions (*version skew*), ce qu'on vérifie avant, comment on revient en arrière si le deuxième nœud de contrôle échoue.
18. Chiffrement des Secrets au repos : que protège `aescbc` avec une clé dans un fichier sur les nœuds de contrôle, et que ne protège-t-il pas ? Qu'apporte `kms` v2 ? Comment vérifie-t-on qu'un Secret est réellement chiffré ?
19. Restaurer etcd depuis un instantané sur un cluster HA kubeadm : pourquoi faut-il restaurer **tous** les membres avec un nouveau cluster logique, et que deviennent les objets créés après l'instantané (pods, baux, jetons) ?
20. Un nœud est `NotReady`. Décris ta démarche, des premières commandes jusqu'à la décision « réparer » ou « remplacer », et les commandes que tu t'interdis tant que tu n'as pas la réponse.

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 9 : *Kubernetes Components*, *Kubernetes API Concepts*, *Controlling Access to the Kubernetes API*, *Admission Control*, *Pod Quality of Service Classes*, *Node-pressure Eviction*, *Scheduling Framework*, *Disruptions*, et la documentation d'etcd (*Data model*, *Failure modes*) ; ton compte rendu de M14-E44.
</details>

<details><summary>Indice 2</summary>

Pour 10 à 20 : *Service Account Tokens*, *PKI certificates and requirements*, *Certificate Management with kubeadm*, *Virtual IPs and Service Proxies*, *DNS for Services and Pods*, *Swap memory management*, *About cgroup v2*, *Upgrading kubeadm clusters*, *Version Skew Policy*, *Encrypting Confidential Data at Rest*, *Operating etcd clusters for Kubernetes* ; tes journaux de M14-E35 à M14-E42.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible, sans geste interdit), à présenter à Karim.
