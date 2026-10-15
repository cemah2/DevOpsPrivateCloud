# Module 16 — Palier 4 : Expert

Le stockage de `k8s-par1` est en service : ceph-csi vers `ceph-par1` (RBD et CephFS), instantanés, Velero vers `s3-01`, `mediagenda-db` sous CloudNativePG avec son archivage continu. Nadia Roussel pose la question de tous les paliers 4 : « Et à 3 h du matin, quand un volume ne se monte plus ou que la base ne se sauvegarde plus, qui sait quoi faire ? » Karim Benali a préparé huit pannes, toutes de celles que racontent les forums et les post-mortems publics : un PVC qui reste `Pending`, un pod bloqué en `ContainerCreating`, un volume « déjà attaché ailleurs », Ceph qui refuse de créer des images, une sauvegarde Velero en échec, une base qui ne bascule plus, des WAL qui ne partent plus, un instantané qui ne se termine jamais. Une astreinte en combine trois. Puis tu suis un volume du PVC jusqu'au bloc monté sur le nœud, et tu passes les questions qu'on pose en entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec trois règles propres au stockage dans Kubernetes :
- **Chaque étage a son témoin.** Un volume traverse l'API (PVC, PV, StorageClass, VolumeAttachment, CSINode), des contrôleurs (provisioner, attacher, snapshotter, contrôleur attach/detach de `kube-controller-manager`), le pilote CSI (pod *controller* et pod *nodeplugin*), le kubelet du nœud, puis le stockage (`ceph-par1`, `s3-01`). Les événements de l'objet (`kubectl describe`, `kubectl get events --field-selector involvedObject.name=…`) disent presque toujours à quel étage ça bloque ; les journaux du composant de cet étage disent pourquoi.
- **Ne transforme jamais une panne en perte de données.** Supprimer un PVC ou un PV, retirer un finaliseur, forcer la suppression d'un pod qui tient encore son volume, effacer un `VolumeSnapshotContent`, supprimer une CRD, promouvoir une réplique « pour voir », réinitialiser un ObjectStore : ces gestes sont **interdits** dans ce palier tant que tu n'as pas prouvé qu'ils ne détruisent rien. Aucune des pannes n'en a besoin.
- **Répare là où la configuration vit.** Les composants ont été installés par Helm avec des valeurs versionnées dans `plateforme/k8s` (M16-E23), les identités Ceph sont décrites dans `plateforme/ceph` (`allocations.yaml`), les trousseaux et clés sont en Ansible Vault. Une réparation à chaud est permise pour rétablir le service ; elle doit être reportée ensuite dans le code par une MR, sinon le prochain `helm upgrade` ou la prochaine application des allocations la défera — ou recassera.

> **Rappels** : tout se lance depuis `adm01`, avec ton identité Kubernetes (`~/.kube/config`). Les travailleurs `k8s-w01-03` se joignent en SSH (`admin` + sudo) ; `ceph-par1` depuis son nœud admin (`ceph01`, variable `WB_CEPH_ADMIN` de `lab/lab.env`), avec la CLI `ceph` ou `sudo cephadm shell`. Le plugin `kubectl cnpg` et la CLI `velero` sont installés sur `adm01` (M16-E16, M16-E18). La documentation va dans `~/medisphere` (variable `WB_DEPOT`), publiée par MR.

## Règles du jeu des pannes (M16-E35 à M16-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 16 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a de 2 à 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab, le script en essaie une autre. Une injection prend d'une à cinq minutes : le script attend que la panne soit **constatée** (un ticket n'annonce jamais une panne inexistante).
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 16 35`) : il doit être vert (sauf la ligne « sauvegarde depuis l'incident » des exercices qui en ont une). Le script de panne refuse de casser un cluster qui n'est pas sain : travailleurs `Ready` et non cordonnés, ceph-csi complet, témoins disponibles ; pour les pannes de la base, `mediagenda-db` avec ses trois instances prêtes ; pour Velero, un emplacement de sauvegarde `Available`.
- **Témoins.** À la première injection, le script crée dans l'espace `wb-essais` (s'ils n'existent pas) deux **témoins** qui jouent le rôle des applications et qu'il ne supprime jamais :
  - le PVC `temoin-rbd` (classe `ceph-rbd`, RWO, 1 Gio) et le Deployment `temoin-rbd` ;
  - le PVC `temoin-cephfs` (classe `cephfs`, RWX, 1 Gio) et le Deployment `temoin-cephfs`.

  Chaque pod écrit l'heure dans `/donnees/battement` toutes les 10 s ; sa sonde de disponibilité échoue si le battement a plus d'une minute. Un témoin `0/1` signifie donc « ce volume n'écrit plus ». Certaines pannes créent en plus un objet de test (`temoin-e35`, `temoin-e36`, `temoin-e38`, un instantané…) que l'annulation retire. Lis les manifestes des témoins (`kubectl get deploy,pvc -n wb-essais -o yaml`) : ils ne contiennent aucune cause. Tu pourras supprimer les témoins toi-même après la recette (M16-E46).
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les hôtes, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 16 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne (sinon elle reste marquée active et bloque l'astreinte M16-E43 et le mini-projet) : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation. Puis lance le contrôle.
- Les pannes n'agissent que sur `k8s-par1` (espaces `wb-essais` et `mediagenda-recette`, composants `ceph-csi`, `velero`, `kube-system/snapshot-controller`), sur les travailleurs `k8s-w01-03` et, côté `ceph-par1`, **uniquement** sur les objets du consommateur Kubernetes (identité `client.k8s`, quota du pool `k8s-rbd`) : jamais un moniteur, un OSD, ni le pool d'un autre consommateur. Jamais sur `s3-01`, `pve01` (hors arrêt d'une VM de travailleur, voir plus bas), `pbs01`. **Aucune donnée n'est détruite** : aucun PVC, PV, image RBD, instantané existant ni objet S3 n'est supprimé ; tout objet modifié est sauvegardé avant.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/kubernetes/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M16-E43.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Effets de bord annoncés.** M16-E37 fait **tomber un travailleur** (kubelet arrêté ou VM coupée net) : tous les pods de ce nœud vivent la panne, y compris, peut-être, une instance de `mediagenda-db` (qui doit basculer seule : c'est son rôle). Une variante de M16-E38 fige **toutes** les écritures du pool `k8s-rbd`, dont celles de la base de recette : les écritures attendent, rien n'est perdu. Deux variantes de M16-E38 privent `client.k8s` de ses accès ; les volumes déjà montés ne s'en aperçoivent qu'au renouvellement de leurs titres d'authentification : **au-delà d'une heure sur M16-E38, annule** la panne et reprends plus tard. Ne lance pas ces exercices pendant une démonstration de MédiAgenda.

> ⚠️ **Accès de secours.** Pour M16-E37, vérifie **avant** d'injecter que tu sais entrer sur un travailleur sans SSH : console série (`qm terminal 2144` depuis `pve01`, sortie par `Ctrl+O`) et agent QEMU (`qm guest cmd 2144 ping` doit répondre). Garde aussi sous la main le chemin du bris de glace Kubernetes (`admin.conf` en Ansible Vault `critique`, M14-E06).

> ⚠️ **Avant toute action sur un volume, pose-toi deux questions** et écris la réponse dans ton journal : « qui peut écrire sur ce volume en ce moment, et depuis quel nœud ? » et « si je fais ça, qu'est-ce qui garantit qu'un seul nœud écrira ensuite ? ». Pour une base PostgreSQL, ajoute : « quelle est la dernière transaction archivée hors du cluster ? ».

---

### M16-E35 — Panne : le PVC reste Pending  `BF` `★★`

> **Ticket INC-4341** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection.)* Notre petite application de test `temoin-e35`, déployée ce matin dans `wb-essais` avec un manifeste « qui marchait la semaine dernière », reste à 0/1 : son volume n'est jamais prêt.

**Objectifs pédagogiques**
- Suivre la chaîne de décision d'un volume dynamique : PVC → StorageClass (explicite ou par défaut) → admission (quotas) → provisioner externe → pilote CSI → PV → liaison.
- Lire les événements d'un PVC et d'un StatefulSet, et reconnaître la phrase propre à chaque cause.
- Corriger un `volumeClaimTemplates` sans perdre de données ni laisser d'orphelin, et mettre à jour RB-160 (M16-E22).

**Prérequis** : M16-E06, M16-E08, M16-E12, M16-E20, M16-E22 ; `lab/bin/check 16 35` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : depuis Kubernetes 1.28, un PVC sans classe créé alors qu'aucune classe n'est par défaut reste `Pending`, puis reçoit **rétroactivement** la classe par défaut dès qu'il en existe une. Les champs `volumeClaimTemplates` d'un StatefulSet et `storageClassName` d'un PVC sont immuables. Le provisioner RBD est le Deployment `ceph-csi-rbd-provisioner` (espace `ceph-csi`), dont le conteneur `csi-provisioner` surveille les PVC de sa classe.

**Injection** : `lab/bin/break 16 35` (4 variantes).

**Travail demandé**
1. Constate sans rien modifier : état du StatefulSet, de ses pods et de ses PVC. Lis les événements **de chaque objet** concerné. À quel étage la chaîne s'arrête-t-elle : admission, choix de la classe, provisioner, pilote ?
2. Vérifie que la cause est locale à `temoin-e35` ou qu'elle touche aussi les autres équipes : un PVC de 1 Gio créé à la main dans `wb-essais` (puis supprimé) se lie-t-il ?
3. Trouve la cause racine et corrige-la **là où elle vit** (manifeste de l'application, objet de cluster, valeurs Helm de `plateforme/k8s`, objets d'espace). Si l'application doit être recréée, fais-le sans laisser de PVC orphelin.
4. Vérifie que `temoin-e35` démarre, et que son volume est sur la bonne classe.
5. Complète RB-160 (`docs/kubernetes/stockage/runbooks/`) avec la cause que tu as rencontrée : symptôme exact (phrase de l'événement), commande qui la prouve, correctif, prévention.

**Critères de réussite**
- [ ] `temoin-e35` a sa réplique prête et son volume est lié sur une classe existante (`ceph-rbd`).
- [ ] Il existe exactement une classe par défaut, `ceph-rbd` ; le provisioner RBD a toutes ses répliques ; aucun quota de `wb-essais` n'est saturé.
- [ ] Ton journal contient l'événement qui a désigné l'étage en cause ; RB-160 est complété et publié.

**Vérification** : `lab/bin/check 16 35`

<details><summary>Indice 1</summary>

`kubectl describe pvc` et `kubectl describe statefulset` ne racontent pas la même chose : le premier parle du **volume** (classe, provisioner), le second de ce que le contrôleur de StatefulSet a réussi ou non à **créer**. Si aucun PVC n'existe, la réponse est dans les événements du StatefulSet.
</details>

<details><summary>Indice 2</summary>

`kubectl get storageclass` (colonne `(default)`), `kubectl get resourcequota -n wb-essais -o yaml` (sections `hard` et `used`), `kubectl get deploy -n ceph-csi` et `kubectl logs -n ceph-csi deploy/ceph-csi-rbd-provisioner -c csi-provisioner --tail=50`. Un PVC qui attend « que le volume soit créé par le provisioner externe » sans qu'aucun journal du provisioner n'en parle a une explication simple.
</details>

<details><summary>Indice 3</summary>

Pour changer la classe d'un `volumeClaimTemplates`, il faut recréer le StatefulSet ; le PVC déjà créé, lui, n'est jamais modifié ni supprimé par le contrôleur. Regarde `persistentVolumeClaimRetentionPolicy` (M16-E08) avant de supprimer quoi que ce soit, et liste les PVC après coup.
</details>

**Pour aller plus loin** : écris une règle de pipeline pour `plateforme/k8s` qui refuse un manifeste dont `storageClassName` vise une classe absente de la liste des classes du cluster (rendu `kubectl kustomize` ou `helm template`, puis `yq`).

---

### M16-E36 — Panne : le pod reste en ContainerCreating  `BF` `★★★`

> **Ticket INC-4342** — *De : Julien Petit*
> *(Le détail du ticket s'affiche à l'injection.)* L'application de test `temoin-e36` (`wb-essais`) doit tourner sur un travailleur précis, où l'équipe épingle ses essais de performance. Son volume a été créé sans problème (PVC `Bound`), mais le pod reste en `ContainerCreating`. Ne déplace pas l'application.

**Objectifs pédagogiques**
- Distinguer les étages d'un montage CSI côté nœud : enregistrement du pilote (CSINode, `node-driver-registrar`), attachement (VolumeAttachment), `NodeStageVolume` (secret de nœud, carte du volume, moniteurs), `NodePublishVolume`.
- Lire les journaux du kubelet et du pod *nodeplugin* **du bon nœud**, et tester le réseau de stockage depuis le nœud lui-même.
- Savoir quel Secret sert à quelle opération CSI (provisionnement, extension, montage) et où il est déclaré.

**Prérequis** : M16-E04, M16-E05, M16-E06, M16-E23 ; `lab/bin/check 16 36` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la StorageClass `ceph-rbd` nomme, par des paramètres `csi.storage.k8s.io/*-secret-name` et `*-secret-namespace`, les Secrets utilisés par chaque opération (M16-E06). Les pods *nodeplugin* (DaemonSet `ceph-csi-rbd-nodeplugin`) sont en `hostNetwork` : ils joignent les moniteurs (10.10.30.51-53, ports 3300 et 6789) par la carte VLAN 30 du travailleur (M16-E05). Les sessions déjà établies par les volumes montés survivent à bien des pannes que les **nouveaux** montages ne supportent pas.

**Injection** : `lab/bin/break 16 36` (3 variantes).

**Travail demandé**
1. Reproduis et cadre : le pod est-il planifié, sur quel nœud ? Que disent ses événements (`FailedAttachVolume`, `FailedMount`, autre) ? Les autres pods à volume de ce nœud (témoins, base) fonctionnent-ils ? Un pod de test épinglé sur un **autre** travailleur monte-t-il un volume ?
2. Descends les étages pour ce nœud : le pilote y est-il enregistré, le pod *nodeplugin* y tourne-t-il, l'attachement existe-t-il ? Que disent le kubelet du nœud et le conteneur `csi-rbdplugin` du *nodeplugin* de ce nœud ?
3. Si l'échec vient de l'accès à Ceph, teste-le **depuis le nœud** (et pas depuis `adm01`) : moniteurs joignables sur quels ports, par quelle interface ? Si c'est une question d'identité, sans lire de clé en clair, établis quel Secret est utilisé et si son contenu correspond à l'identité Ceph.
4. Corrige à la racine (et dans le code : valeurs Helm de `plateforme/k8s`, script de création des Secrets depuis Vault, configuration du nœud par Ansible) ; vérifie que `temoin-e36` démarre **sur son nœud**.
5. Rédige `RB-165 — Un pod n'obtient pas son volume` (`docs/kubernetes/stockage/runbooks/`) : arbre de décision « planifié ? attaché ? pilote enregistré ? NodeStage ? NodePublish ? », avec pour chaque branche la commande et le journal qui tranchent. Tu le compléteras en M16-E37.

**Critères de réussite**
- [ ] `temoin-e36` est prêt sur le travailleur indiqué par le ticket.
- [ ] Le pilote `rbd.csi.ceph.com` est enregistré et son *nodeplugin* prêt sur chaque travailleur ; chaque travailleur joint les trois moniteurs sur le port 3300.
- [ ] Ton journal contient la ligne de journal (kubelet ou *nodeplugin*) qui a prouvé la cause ; la correction est reportée dans le code (MR) ; RB-165 est publié.

**Vérification** : `lab/bin/check 16 36`

<details><summary>Indice 1</summary>

`kubectl describe pod` puis, sur le nœud du pod : `sudo journalctl -u kubelet --since -15min | grep -i -E 'mount|csi|attach'`. Côté Kubernetes : `kubectl get csinode <nœud> -o yaml`, `kubectl get volumeattachment | grep <pv>`, `kubectl get pods -n ceph-csi -o wide`. Le nom du pod *nodeplugin* d'un nœud se trouve avec `--field-selector spec.nodeName=<nœud>`.
</details>

<details><summary>Indice 2</summary>

`kubectl logs -n ceph-csi <nodeplugin-du-nœud> -c csi-rbdplugin --tail=80` montre l'appel `NodeStageVolume` et la commande `rbd map` qu'il lance, avec son code d'erreur : « délai dépassé », « opération non permise » et « pilote introuvable » ne mènent pas au même étage. Sur le nœud, `timeout 3 bash -c '</dev/tcp/10.10.30.51/3300'`, `ip route get 10.10.30.51` et ce que le pare-feu local du nœud laisse passer (`sudo nft list ruleset`).
</details>

<details><summary>Indice 3</summary>

Sans afficher de secret : `kubectl get secret <nom> -n <espace> -o jsonpath='{.data.userKey}' | base64 -d | sha256sum` d'un côté, `sudo ceph auth get-key client.<id> | sha256sum` sur `ceph01` de l'autre. Et pour un pilote absent d'un seul nœud, compare la spécification du DaemonSet (affinités, sélecteurs, tolérances) aux étiquettes et teintes du nœud.
</details>

**Pour aller plus loin** : ajoute à la sonde `ms-verif-k8s-stockage` (M16-E27) un contrôle « pour chaque travailleur : pilotes RBD et CephFS enregistrés dans CSINode, moniteurs joignables sur 3300 depuis le nœud ».

---

### M16-E37 — Panne : le volume est déjà attaché ailleurs  `BF` `★★`

> **Ticket INC-4343** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection.)* Un travailleur est tombé cette nuit. Kubernetes a relancé ailleurs le pod du témoin `temoin-rbd`, mais ce pod reste en `ContainerCreating` : son volume « serait déjà attaché ». Fais-le repartir au plus vite, sans risquer ses données.

**Objectifs pédagogiques**
- Comprendre pourquoi Kubernetes refuse d'attacher un volume RWO à un second nœud (`Multi-Attach error`) et ce que fait le contrôleur attach/detach quand le premier nœud ne répond plus.
- Appliquer la procédure d'**arrêt non gracieux** d'un nœud (teinte `node.kubernetes.io/out-of-service`) en sachant quand elle est sûre, et quand elle ne l'est pas.
- Relier l'objet `VolumeAttachment`, le champ `volumesAttached` du nœud et l'état réel du volume côté Ceph (verrou exclusif, observateurs de l'image).

**Prérequis** : M16-E06, M16-E08, M16-E36 (RB-165) ; M14-E17 (cordon, drain) ; `lab/bin/check 16 37` vert avant l'injection ; accès de secours aux travailleurs vérifié (voir les règles du jeu).
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : le contrôleur attach/detach (dans `kube-controller-manager`) ne détache un volume d'un nœud injoignable qu'après avoir obtenu la preuve que plus personne ne l'utilise ; il attend au moins `maxWaitForUnmountDuration` (6 min), et selon la version et l'option `--disable-force-detach-on-timeout`, il détache ensuite de force ou attend indéfiniment (à vérifier sur ta version : lis les options de `kube-controller-manager`). La [procédure d'arrêt non gracieux](https://kubernetes.io/docs/concepts/cluster-administration/node-shutdown/#non-graceful-node-shutdown) est documentée par Kubernetes. Côté Ceph, `rbd status` liste les clients qui observent une image ; `ceph osd blocklist` empêche un client donné d'écrire.

**Injection** : `lab/bin/break 16 37` (2 variantes).

**Travail demandé**
1. Constate : état des nœuds, des deux pods du témoin (l'ancien, le nouveau), événement exact du nouveau pod. Liste les `VolumeAttachment` du PV du témoin : vers quel nœud ?
2. Avant toute action, réponds dans ton journal : le nœud tombé peut-il encore écrire sur le volume ? Comment le sais-tu (accès au nœud, état de la VM, observateurs de l'image RBD côté Ceph) ? Que se passerait-il si deux nœuds écrivaient en même temps sur ce système de fichiers ext4 ?
3. Choisis la voie de rétablissement adaptée à la variante, et applique-la :
   - si le nœud peut être réparé sans délai, répare-le et laisse Kubernetes faire ;
   - si le nœud doit rester arrêté (le ticket le dit), applique la procédure d'arrêt non gracieux **après** avoir prouvé que le nœud est éteint, et vérifie qu'un seul nœud tient le volume ensuite.
4. Quand le témoin est reparti, remets le nœud en service (variante « VM arrêtée » : InfoGér donne son feu vert dès que le témoin tourne), retire tout ce que tu as posé pour la procédure, et vérifie qu'il ne reste ni pod `Terminating`, ni attachement en double.
5. Complète RB-165 avec la branche « Multi-Attach / nœud perdu » : comment prouver qu'un nœud est éteint, quand poser la teinte, quand ne **jamais** la poser, comment la retirer ; et ce que MédiSphère devrait automatiser (clôture ou *fencing* du nœud, bloquage côté Ceph).

**Critères de réussite**
- [ ] Tous les nœuds sont `Ready`, kubelet actif sur les trois travailleurs, aucune teinte `out-of-service` restée posée.
- [ ] `temoin-rbd` a un seul pod, prêt ; le volume du témoin n'a qu'un `VolumeAttachment`, vers le nœud de son pod.
- [ ] Ton journal contient la réponse argumentée de l'étape 2 et la preuve de l'arrêt du nœud avant toute procédure forcée ; RB-165 est complété.

**Vérification** : `lab/bin/check 16 37`

<details><summary>Indice 1</summary>

`kubectl get nodes`, `kubectl get pods -n wb-essais -o wide`, `kubectl describe pod <nouveau>`, `kubectl get volumeattachment -o custom-columns=PV:.spec.source.persistentVolumeName,NŒUD:.spec.nodeName,ATTACHÉ:.status.attached`. Le champ `status.volumesAttached` du nœud tombé (`kubectl get node <nœud> -o yaml`) dit ce que Kubernetes croit encore attaché là-bas.
</details>

<details><summary>Indice 2</summary>

Avant d'accuser le nœud de vivre ou de mourir : `ping`, `ssh`, `qm status <VMID>` sur `pve01`, et côté Ceph `sudo rbd status k8s-rbd/<image>` (le nom de l'image est dans `spec.csi.volumeAttributes` du PV). Un nœud qui répond en SSH mais dont kubelet est arrêté n'est pas un nœud éteint.
</details>

<details><summary>Indice 3</summary>

La page *Node Shutdowns* de la documentation Kubernetes décrit la teinte, son effet (suppression forcée des pods, détachement des volumes) et sa condition d'emploi. Lis-la en entier avant de taper la commande, et note dans ton journal l'heure de la pose et celle du retrait.
</details>

**Pour aller plus loin** : ceph-csi propose une ressource `NetworkFence` (via csi-addons) pour bloquer côté Ceph les clients d'un nœud perdu ; lis sa documentation et décris dans RB-165 ce qu'elle apporterait à MédiSphère et ce qu'il faudrait installer.

---

### M16-E38 — Panne : Ceph refuse de créer les volumes  `BF` `★★★`

> **Ticket INC-4344** — *De : Karim Benali*
> *(Le détail du ticket s'affiche à l'injection.)* Depuis une maintenance de Lucas sur `ceph-par1` « côté Kubernetes », aucun nouveau volume `ceph-rbd` ne se crée : le PVC de test `temoin-e38` reste `Pending` sur des erreurs de provisionnement. Vérifie aussi que les volumes déjà montés ne sont pas menacés.

**Objectifs pédagogiques**
- Lire une erreur de provisionnement de bout en bout : événement du PVC, journaux du conteneur `csi-rbdplugin` du provisioner, puis l'état de `ceph-par1` vu par l'identité du consommateur.
- Vérifier les droits cephx d'une identité, le quota d'un pool, le type et la valeur d'une clé, **sans** exposer la clé.
- Évaluer le risque pour les volumes existants (sessions établies, renouvellement des titres, pool plein) avant de corriger, et remettre l'état décrit par le code (`allocations.yaml` de `plateforme/ceph`, trousseau en Vault).

**Prérequis** : M16-E06, M16-E23 ; M08-E05, M08-E13, M08-E27 et M08-E46 (droits, quotas, types de clés, allocations) ; `lab/bin/check 16 38` vert avant l'injection.
**Durée indicative** : 45 min (temps cible ; au-delà d'une heure, annule — voir les règles du jeu).

**Contexte technique** : `client.k8s` a été créée au M08 avec les droits de la documentation de ceph-csi ; ses droits de référence sont dans `allocations.yaml` (`plateforme/ceph`) et son trousseau en Ansible Vault (M16-E06). Les clients noyau de Debian 13 (6.12) n'utilisent que des clés de type `aes` (M08-E27). Un titre cephx a une durée de vie limitée (`auth_service_ticket_ttl`) : un client garde ses droits du moment jusqu'au renouvellement.

**Injection** : `lab/bin/break 16 38` (3 variantes).

**Travail demandé**
1. Constate : événements de `temoin-e38`, journaux du conteneur `csi-rbdplugin` du provisioner **leader** (`kubectl get lease -n ceph-csi`) pour la tentative de création. Quel code d'erreur Ceph (permission, authentification, quota, délai) ?
2. Côté `ceph-par1`, compare l'état réel de ce que Kubernetes consomme à l'état décrit par le code : droits de `client.k8s`, quota et occupation de `k8s-rbd`, santé du cluster, clé de l'identité (empreinte, pas valeur) comparée à celle du Secret de ceph-csi et à celle de Vault. Retrouve ce qui a changé et quand (journal d'audit de Ceph, M08-E35).
3. Évalue l'impact sur les volumes **existants** : la base de recette et les témoins écrivent-ils encore ? Combien de temps tiendront-ils dans l'état actuel ? Note la réponse avant de corriger.
4. Corrige en revenant à l'état du code (et pas en élargissant les droits, ni en supprimant un quota par principe). Si la clé a changé, choisis entre « remettre la clé de référence » et « distribuer une nouvelle clé » en pesant ce que chaque option fait aux volumes déjà montés, et justifie.
5. Vérifie que `temoin-e38` se lie et démarre, que les témoins sont prêts, et que l'outil de dérive de `plateforme/ceph` ne signale plus d'écart. Complète RB-160 (section « le provisionnement échoue côté Ceph »).

**Critères de réussite**
- [ ] `temoin-e38` est lié et son pod tourne ; les témoins sont prêts.
- [ ] `client.k8s` a ses profils `rbd` sur `k8s-rbd` (moniteurs, OSD, mgr) et aucun droit `allow *` ; `k8s-rbd` n'est ni plein ni presque plein, son quota garde au moins 20 % de marge.
- [ ] Ton journal contient le code d'erreur initial, la preuve de la modification (audit Ceph ou comparaison au code) et ton analyse de l'impact sur les volumes montés ; RB-160 est complété.

**Vérification** : `lab/bin/check 16 38`

<details><summary>Indice 1</summary>

`kubectl describe pvc temoin-e38 -n wb-essais`, puis le provisioner : `kubectl logs -n ceph-csi <pod-leader> -c csi-rbdplugin --since=15m | grep -i -E 'error|failed'`. Les erreurs de librbd et de librados portent un numéro (`(1) Operation not permitted`, `(13) Permission denied`, `(122) Disk quota exceeded`, `(110) Connection timed out`…) : c'est lui qui désigne la famille de cause.
</details>

<details><summary>Indice 2</summary>

Sur `ceph01` : `sudo ceph auth get client.k8s -f json | jq '.[0].caps'` (les droits seulement), `sudo ceph osd pool get-quota k8s-rbd`, `sudo ceph df detail`, `sudo ceph health detail`, `sudo ceph log last 200 debug audit | grep -E 'auth|quota'`. Pour la clé, compare des empreintes (`sha256sum`), jamais des valeurs, et regarde si le format de la clé ressemble à celui des autres clés clientes.
</details>

<details><summary>Indice 3</summary>

L'outil d'allocations de `plateforme/ceph` (M08-E31, `verifier`) dit l'écart entre l'état réel et `allocations.yaml`. Pour une clé, `ceph auth import` remet un trousseau complet (clé et droits) ; pense à ce que deviennent alors les Secrets de ceph-csi et la copie en Vault.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-k8s-stockage` une alerte « quota de `k8s-rbd` utilisé à plus de 80 % » et une alerte « droits de `client.k8s` différents d'`allocations.yaml` ».

---

### M16-E39 — Panne : la sauvegarde Velero échoue  `BF` `★★`

> **Ticket INC-4345** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection.)* La sauvegarde Velero de contrôle de `wb-essais` lancée ce matin n'a pas abouti, après un « ménage dans la configuration de Velero » par Lucas. Remets les sauvegardes en état, relance une sauvegarde de `wb-essais` (volumes compris) et montre qu'elle est complète.

**Objectifs pédagogiques**
- Diagnostiquer Velero par étages : emplacement de sauvegarde (`BackupStorageLocation`, sa validation périodique), identifiants, TLS vers `s3-01`, compartiment, puis transport des volumes (`node-agent`, `PodVolumeBackup`, `DataUpload`).
- Lire `velero backup describe --details` et `velero backup logs`, et les journaux du serveur Velero et des `node-agent`.
- Vérifier une sauvegarde : complète, avec ses volumes, et restaurable.

**Prérequis** : M16-E16, M16-E17, M16-E24 ; `lab/bin/check 16 39` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : Velero 1.18 valide chaque emplacement de sauvegarde à intervalle régulier (`spec.validationFrequency`, une minute par défaut) et refuse de lancer une sauvegarde vers un emplacement `Unavailable`. Les identifiants S3 viennent d'un Secret (fichier au format AWS, clé `cloud` dans le chart officiel, ou `spec.credential` de l'emplacement). La CA de la PKI MédiSphère est donnée par `spec.objectStorage.caCert`. Le compartiment est `velero-k8s-par1` sur `s3-01` (compte `velero`, M16-E16).

**Injection** : `lab/bin/break 16 39` (4 variantes).

**Travail demandé**
1. Constate : phase de la sauvegarde de test et de l'emplacement (`velero backup-location get`), détails et journaux de la sauvegarde. L'échec est-il global (l'emplacement) ou partiel (certains volumes) ?
2. Remonte l'étage en cause par la mesure : pour un problème d'emplacement, reproduis l'accès à `s3-01` **depuis le cluster** avec les mêmes paramètres (un pod jetable avec un client S3 ou `curl` et la CA, dans `wb-essais`), sans jamais afficher de clé ; pour un problème de volume, trouve quel volume et quel nœud.
3. Retrouve ce qui a changé (compare aux valeurs Helm de `plateforme/k8s`, au fichier `~/.config/workbook/s3-velero.env` et à l'emplacement attendu) et corrige là où vit la configuration.
4. Relance une sauvegarde de `wb-essais` avec ses volumes et prouve qu'elle est complète (phase, nombre d'éléments, volumes sauvegardés, taille), puis restaure-la dans `wb-restauration` (M16-E24) pour vérifier qu'elle est exploitable ; nettoie la restauration ensuite.
5. Rédige `RB-166 — Une sauvegarde Velero échoue` (`docs/kubernetes/stockage/runbooks/`) : par phase de la sauvegarde (`FailedValidation`, `Failed`, `PartiallyFailed`), où regarder et quoi vérifier.

**Critères de réussite**
- [ ] L'emplacement de sauvegarde est `Available`, vers `velero-k8s-par1`, avec la CA MédiSphère ; `node-agent` tourne sur chaque travailleur.
- [ ] Une sauvegarde de `wb-essais` lancée **après** l'incident est `Completed`, volumes compris, et sa restauration de contrôle a réussi.
- [ ] Ton journal contient le message d'erreur initial, la mesure qui a désigné l'étage et la preuve de la restauration ; RB-166 est publié.

**Vérification** : `lab/bin/check 16 39`

<details><summary>Indice 1</summary>

`velero backup-location get`, `kubectl get backupstoragelocation -n velero -o yaml` (champs `status.phase`, `status.message`, `lastValidationTime`), `velero backup describe <nom> --details`, `velero backup logs <nom>`, `kubectl logs -n velero deploy/velero --since=30m | grep -i -E 'error|unavailable'`.
</details>

<details><summary>Indice 2</summary>

Les messages d'un client S3 sont précis : `SignatureDoesNotMatch` ou `InvalidAccessKeyId`, `NoSuchBucket` ou `AccessDenied`, `x509: certificate signed by unknown authority` ne désignent pas le même objet. Pour un volume en échec, `kubectl get podvolumebackups -n velero` (ou `datauploads`) et `kubectl get pods -n velero -o wide` : sur quel nœud aurait-il fallu un agent ?
</details>

**Pour aller plus loin** : ajoute à `ms-verif-k8s-stockage` un contrôle « dernière sauvegarde de chaque planification terminée depuis moins de 26 h » et « emplacement `Available` ».

---

### M16-E40 — Panne : la base PostgreSQL ne bascule plus  `BF` `★★★`

> **Ticket INC-4346** — *De : Nadia Roussel*
> *(Le détail du ticket s'affiche à l'injection.)* Ce soir, maintenance noyau du travailleur qui porte le primaire de `mediagenda-db`. Procédure prévue : basculer le primaire sur une réplique, drainer le nœud, (maintenance simulée), le remettre en service. La répétition de Lucas a échoué : « ça ne bascule pas, ou ça bascule mal ». Fais la maintenance complète ce soir, sans perte de données et avec la coupure d'écriture la plus courte possible.

**Objectifs pédagogiques**
- Connaître ce qui conditionne une bascule CloudNativePG (*switchover*) et ce qui la rend sûre : réplique prête et alignée, état de clôture (*fencing*), PDB du primaire et des répliques, réplication synchrone (nombre de répliques exigé, `dataDurability`), place disponible pour replanifier.
- Comprendre l'interaction entre `kubectl drain`, l'API d'éviction et les PodDisruptionBudget (y compris le cas de plusieurs PDB pour un même pod).
- Conduire une maintenance de nœud qui porte un primaire : bascule maîtrisée, mesure de la coupure, retour à l'état nominal.

**Prérequis** : M16-E18, M16-E25 ; M14-E16 (PDB), M14-E17 (drain) ; `lab/bin/check 16 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : CloudNativePG crée deux PDB par cluster (un pour le primaire, un pour les répliques) et, quand le nœud d'un primaire est drainé, bascule d'abord le primaire sur une réplique (documentation *Kubernetes Upgrade and Maintenance*). `mediagenda-db` impose une instance par nœud (anti-affinité requise, M16-E18) : pendant le drain d'un travailleur, l'instance évincée reste `Pending` jusqu'au retour du nœud, et le cluster tourne sur deux instances ; ses réglages de réplication synchrone (M16-E18) doivent le supporter. `kubectl cnpg status mediagenda-db -n mediagenda-recette` donne l'état des instances, la réplication et le décalage ; `kubectl cnpg promote` demande une bascule vers une instance donnée. Pendant une bascule, les connexions au Service `mediagenda-db-rw` sont coupées quelques secondes.

**Injection** : `lab/bin/break 16 40` (3 variantes).

**Travail demandé**
1. Avant tout : prends l'état de référence (`kubectl cnpg status`, PDB, nœuds), et vérifie que la dernière sauvegarde et l'archivage des WAL sont à jour : si la maintenance tourne mal, de quoi repartirait-on ?
2. Lance d'abord une boucle d'écriture qui mesure la coupure (indice 3), puis rejoue la répétition de Lucas pas à pas, en observant à chaque étape : simulation du drain (`kubectl drain <nœud> --dry-run=server --ignore-daemonsets --delete-emptydir-data`), promotion d'une réplique, drain réel. Note le message exact qui bloque, ou l'instant où les écritures s'arrêtent. Si les écritures restent bloquées plus de 2 min, remets le nœud en service (`kubectl uncordon`) et analyse à froid.
3. Trouve la cause racine (objet en trop, état d'une instance, état d'un nœud) et qui l'a introduite ; corrige-la sans contourner les protections de CloudNativePG (ne désactive pas `enablePDB`, ne force pas la suppression d'un pod de la base).
4. Fais la maintenance : bascule maîtrisée, drain, attente, remise en service (`uncordon`). Mesure la coupure d'écriture vue par MédiAgenda (boucle d'écriture sur l'API, ou `psql` en boucle sur `mediagenda-db-rw` depuis un pod jetable) et vérifie l'état final (`kubectl cnpg status` : 3 instances, réplication en flux).
5. Rédige `RB-167 — mediagenda-db : bascule et maintenance de nœud` (`docs/kubernetes/stockage/runbooks/`) : prérequis vérifiés avant de commencer, commandes, critères d'arrêt, retour arrière. Tu le compléteras en M16-E41.

**Critères de réussite**
- [ ] `mediagenda-db` a ses 3 instances prêtes, aucune clôturée, phase saine ; seuls les PDB de CloudNativePG couvrent ses pods ; aucun nœud n'est cordonné.
- [ ] Le primaire a changé depuis l'incident (la bascule de la maintenance a eu lieu).
- [ ] Ton journal contient le message bloquant, la cause et la coupure d'écriture mesurée ; RB-167 est publié.

**Vérification** : `lab/bin/check 16 40`

<details><summary>Indice 1</summary>

`kubectl get pdb -n mediagenda-recette -o wide` (qui couvre quels pods ? qui a créé chaque PDB : regarde `ownerReferences`), `kubectl get nodes` (colonne `STATUS`), `kubectl get cluster mediagenda-db -n mediagenda-recette -o yaml` (annotations, `status.instancesStatus`, `status.readyInstances`).
</details>

<details><summary>Indice 2</summary>

Le message de l'API d'éviction est explicite quand plusieurs budgets couvrent un même pod ; celui de `kubectl cnpg promote` l'est aussi quand l'instance visée n'est pas candidate (la page *Fencing* de la documentation CloudNativePG dit comment une instance est clôturée). Si, après la bascule, les écritures attendent, compare `show synchronous_standby_names` et `select application_name, state, sync_state from pg_stat_replication` sur le primaire : combien de répliques synchrones PostgreSQL attend-il, combien en a-t-il ?
</details>

<details><summary>Indice 3</summary>

Pour mesurer la coupure : un pod jetable `postgres:18` (image du cache Harbor) dans `mediagenda-recette`, avec le Secret `mediagenda-db-app`, et une boucle qui insère une ligne horodatée toutes les 0,5 s dans une table de test, en notant les échecs. N'oublie pas les politiques réseau de refus par défaut de l'espace (`refus-par-defaut`, M15).
</details>

**Pour aller plus loin** : compare une bascule déclenchée par le drain avec un `kubectl cnpg promote` explicite avant le drain : laquelle coupe le moins, et pourquoi ? Lis la section `switchoverDelay` / `smartShutdownTimeout` de la documentation CloudNativePG.

---

### M16-E41 — Panne : l'archivage des WAL est bloqué  `BF` `★★★`

> **Ticket INC-4347** — *De : Sophie Laurent*
> *(Le détail du ticket s'affiche à l'injection.)* Contrôle HDS : pour `mediagenda-db`, les WAL ne partent plus vers `s3-01` alors que la base reçoit des écritures. Notre engagement de restauration à un instant donné (RB-162, politique de sauvegarde) n'est plus tenu. Remets l'archivage en marche, prouve qu'aucun WAL n'a été perdu et dis-moi jusqu'où on aurait pu restaurer pendant la panne.

**Objectifs pédagogiques**
- Suivre le chemin d'un WAL : `archive_command` de PostgreSQL → gestionnaire d'instance → conteneur auxiliaire du plugin Barman Cloud → `barman-cloud-wal-archive` → `s3-01`.
- Lire `pg_stat_archiver`, la condition `ContinuousArchiving` du Cluster, l'état de l'`ObjectStore` et les journaux du conteneur du plugin.
- Évaluer la fenêtre de restauration réelle pendant une panne d'archivage (dernier WAL archivé, dernière sauvegarde de base) et la protéger (espace disque de `pg_wal`).

**Prérequis** : M16-E19, M16-E25, M16-E32 ; `lab/bin/check 16 41` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : avec le plugin Barman Cloud (0.15), la configuration S3 est dans l'`ObjectStore` `cnpg-s3` (espace `mediagenda-recette`) : `destinationPath`, `endpointURL`, `endpointCA`, `s3Credentials` (références à des Secrets). Le Cluster le désigne par `.spec.plugins[].parameters.barmanObjectName`. Chaque pod de la base porte un conteneur auxiliaire du plugin (nomme-le avec `kubectl get pod <pod> -o jsonpath='{.spec.containers[*].name}'` ou dans les `initContainers` selon la version). Tant que l'archivage échoue, PostgreSQL **garde** les WAL non archivés dans `pg_wal`.

**Injection** : `lab/bin/break 16 41` (3 variantes).

**Travail demandé**
1. Constate et date : condition `ContinuousArchiving`, `kubectl cnpg status` (section *Continuous Backup*), `pg_stat_archiver` sur le primaire (dernier WAL archivé, dernier échec, nombre d'échecs). Depuis quand l'archivage échoue-t-il ?
2. Mesure le risque immédiat : place occupée par `pg_wal` et place libre sur le volume du primaire. Combien de temps la base tient-elle à ce rythme d'écriture ?
3. Trouve la cause dans les journaux du conteneur du plugin sur le primaire, puis prouve-la par une mesure indépendante (accès à `s3-01` avec les mêmes paramètres depuis un pod jetable de l'espace, sans afficher de clé).
4. Corrige dans l'`ObjectStore` ou ses Secrets, et dans le code (`plateforme/k8s`, script de création des Secrets). Force un changement de segment (`select pg_switch_wal();`) et vérifie que l'arriéré se vide (le compteur `archived_count` rattrape, `last_failed_time` ne bouge plus).
5. Prouve qu'aucun WAL n'est perdu : la suite des segments archivés dans `s3-01` est continue sur la période de la panne (liste des objets du préfixe `wals/` du compartiment, ou `barman-cloud-wal-restore` à blanc). Lance une sauvegarde de base, puis réponds à Sophie : quelle était la fenêtre de restauration à chaque instant de la panne ?
6. Complète RB-167 avec la section « archivage des WAL bloqué ».

**Critères de réussite**
- [ ] La condition `ContinuousArchiving` est vraie ; l'`ObjectStore` `cnpg-s3` vise `s3://cnpg-k8s-par1/…` sur `s3-01` avec la CA MédiSphère ; le plugin est l'archiveur de WAL du Cluster.
- [ ] Une sauvegarde de base de `mediagenda-db` lancée après l'incident est terminée.
- [ ] Ton journal contient la plage de la panne, la preuve de continuité des WAL et ta réponse à Sophie ; RB-167 est complété.

**Vérification** : `lab/bin/check 16 41`

<details><summary>Indice 1</summary>

`kubectl exec -n mediagenda-recette <primaire> -c postgres -- psql -tAc 'select * from pg_stat_archiver'` ; `kubectl cnpg status mediagenda-db -n mediagenda-recette` ; `kubectl get objectstore cnpg-s3 -n mediagenda-recette -o yaml` ; `kubectl logs -n mediagenda-recette <primaire> -c <conteneur-du-plugin> --since=30m | grep -i -E 'error|fail'`.
</details>

<details><summary>Indice 2</summary>

Un client S3 dit clairement s'il s'agit d'une signature, d'un compartiment, d'un droit ou d'un certificat. Compare chaque référence de l'`ObjectStore` (noms des Secrets, clés, chemin, CA) à ce que tu as écrit dans `plateforme/k8s` au M16-E19, champ par champ.
</details>

<details><summary>Indice 3</summary>

Les WAL d'un serveur sont rangés sous `<destinationPath>/<nom-du-serveur>/wals/<timeline+segment>/`. Des noms de segments consécutifs (hexadécimal) sur toute la période prouvent la continuité ; un trou serait une perte de fenêtre de restauration.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-k8s-stockage` l'alerte « dernier WAL archivé il y a plus de 10 min » à partir des métriques du port 9187 de l'instance (`cnpg_pg_stat_archiver_seconds_since_last_archival`, à vérifier sur ta version : `curl` sur le pod).

---

### M16-E42 — Panne : le snapshot ne se termine jamais  `BF` `★★`

> **Ticket INC-4348** — *De : Karim Benali*
> *(Le détail du ticket s'affiche à l'injection.)* L'instantané du volume témoin demandé avant un essai (`VolumeSnapshot temoin-rbd-HHMM`, espace `wb-essais`) n'est toujours pas prêt vingt minutes plus tard. Les sauvegardes Velero qui déplacent les données de snapshots CSI vont toutes rester bloquées pareil.

**Objectifs pédagogiques**
- Connaître les deux moitiés des instantanés CSI : le **contrôleur commun** (`snapshot-controller`, qui crée les `VolumeSnapshotContent`) et le **sidecar** `csi-snapshotter` du pilote (qui appelle `CreateSnapshot`).
- Lire le statut d'un `VolumeSnapshot` et de son `VolumeSnapshotContent` (présents ? `readyToUse` ? `error` ?) et en déduire l'étage en cause.
- Vérifier la cohérence d'une `VolumeSnapshotClass` avec sa StorageClass.

**Prérequis** : M16-E10, M16-E17 ; `lab/bin/check 16 42` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : external-snapshotter 8.6 : CRD `snapshot.storage.k8s.io/v1` et Deployment `snapshot-controller` dans `kube-system` (installés au M16-E06 depuis les manifestes du projet). Le sidecar `csi-snapshotter` tourne dans les pods `ceph-csi-rbd-provisioner`. La classe `ceph-rbd-snap` porte, comme la StorageClass, le `clusterID` et les références du Secret utilisé pour créer l'instantané.

**Injection** : `lab/bin/break 16 42` (3 variantes).

**Travail demandé**
1. Constate : le `VolumeSnapshot` a-t-il un statut ? un `VolumeSnapshotContent` lié ? un message d'erreur ? Chaque réponse désigne un étage différent : écris lequel.
2. Vérifie l'étage désigné par ses journaux et son état (contrôleur : pods, journaux, droits ; sidecar : journaux de `csi-snapshotter` ; classe : comparaison champ par champ avec `ceph-rbd`).
3. Corrige à la racine, dans le code (manifestes du contrôleur et classe dans `plateforme/k8s`), sans supprimer ni recréer de CRD.
4. Vérifie que l'instantané en attente se termine, puis demande un **nouvel** instantané du témoin et vérifie qu'il est prêt. Vérifie aussi qu'une sauvegarde Velero avec déplacement des données de snapshots se termine (M16-E17).
5. Complète RB-166 avec la section « instantané bloqué ».

**Critères de réussite**
- [ ] `snapshot-controller` est disponible et son compte de service a ses droits ; `ceph-rbd-snap` est cohérente avec `ceph-rbd` (pilote, `clusterID`, espace du Secret).
- [ ] Aucun instantané de `wb-essais` n'est en attente depuis plus de 10 minutes ; un instantané demandé après l'incident est prêt.
- [ ] Ton journal contient l'état du `VolumeSnapshot` au départ et l'étage que tu en as déduit ; RB-166 est complété.

**Vérification** : `lab/bin/check 16 42`

<details><summary>Indice 1</summary>

`kubectl describe volumesnapshot <nom> -n wb-essais`, `kubectl get volumesnapshotcontent | grep <nom>`. Un instantané **sans aucun statut** n'a été vu par personne ; un instantané avec un contenu en erreur a été vu par tout le monde, et c'est l'appel au pilote qui a échoué.
</details>

<details><summary>Indice 2</summary>

`kubectl get deploy,pods -n kube-system -l app.kubernetes.io/name=snapshot-controller`, `kubectl logs -n kube-system deploy/snapshot-controller --tail=50`, `kubectl logs -n ceph-csi <provisioner-leader> -c csi-snapshotter --tail=50`, `diff <(kubectl get volumesnapshotclass ceph-rbd-snap -o yaml) <(…)` contre ce qui est dans `plateforme/k8s`.
</details>

**Pour aller plus loin** : la CRD `VolumeSnapshotContent` protège les instantanés par des finaliseurs. Explique dans RB-166 ce qui arriverait aux instantanés existants (et aux images RBD derrière) si quelqu'un supprimait la CRD « pour la réinstaller proprement ».

---

### M16-E43 — Astreinte : les données de MédiAgenda sont en danger  `BF` `★★★★`

> **Ticket INC-4350** — *De : Nadia Roussel (responsable astreinte)* — *priorité P1*
> *(Le détail s'affiche à l'injection : trois remontées en vingt minutes.)* La recette de MédiAgenda reprend à 8 h avec des données réelles anonymisées. À ce moment-là, la base doit être restaurable à un instant donné, sauvegardée hors du cluster, et les volumes doivent se créer et se monter.

**Objectifs pédagogiques**
- Traiter plusieurs incidents simultanés : trier, prioriser par risque sur les **données** (et pas par ordre d'arrivée), protéger avant de réparer.
- Communiquer pendant l'incident (points réguliers) et après (post-mortem sans reproche).
- Vérifier la restaurabilité de bout en bout avant de déclarer l'incident clos.

**Prérequis** : M16-E35 à M16-E42 ; `lab/bin/check 16 43` vert avant l'injection (aucune panne M16 active).
**Durée indicative** : 2 h (rétablissement) + 45 min (post-mortem).

**Contexte technique** : trois pannes parmi celles des exercices M16-E35 à M16-E42, une de chaque famille : la base (bascule ou archivage), les sauvegardes (Velero ou instantanés), les volumes (création, montage, nœud perdu, Ceph). Les variantes peuvent être différentes de celles que tu as rencontrées. Modèle de post-mortem : `modules/00-lab/ressources/M00-E46/modele-post-mortem.md`.

**Injection** : `lab/bin/break 16 43` (12 combinaisons ; l'injection prend jusqu'à dix minutes).

**Travail demandé**
1. **Tri (15 min)** : pour chaque remontée, l'impact sur les données (risque de perte, de corruption, de non-restaurabilité) et sur le service. Décide de l'ordre de traitement et écris pourquoi. Premier point à Nadia dans ton journal.
2. **Protéger** : avant de réparer quoi que ce soit, assure-toi que la donnée la plus exposée est protégée (exemple : si l'archivage des WAL est en panne et que la base écrit, quelle est la dernière sauvegarde utilisable, et faut-il en lancer une autre ailleurs ?).
3. **Rétablir** chaque panne avec la démarche des exercices précédents (étage, preuve, correctif dans le code), un point toutes les 30 min dans ton journal.
4. **Vérifier la restaurabilité** avant de clore : une sauvegarde Velero de `mediagenda-recette` complète, une sauvegarde de base CloudNativePG terminée et l'archivage à jour, un volume de test créé et monté sur chaque travailleur.
5. **Post-mortem** `docs/kubernetes/post-mortems/AAAA-MM-JJ-INC-4350.md` : chronologie, impact, causes racines (une par panne, et ce qu'elles ont en commun), ce qui a bien marché, actions (responsable, échéance) dont au moins une **détection** et une **prévention** par panne.

**Critères de réussite**
- [ ] `lab/bin/check 16 43` est entièrement vert (il rejoue les contrôles de M16-E35 à M16-E42).
- [ ] Ton journal montre le tri initial, l'ordre de traitement justifié et les points de 30 min.
- [ ] Le post-mortem est publié (MR fusionnée) avec chronologie, causes racines et actions.

**Vérification** : `lab/bin/check 16 43`

<details><summary>Indice 1</summary>

Une panne qui empêche de **restaurer** passe avant une panne qui empêche de **créer**. Une panne qui peut faire **perdre** une donnée (disque qui se remplit, deux écrivains) passe avant tout le reste.
</details>

<details><summary>Indice 2</summary>

Les pannes peuvent se masquer : un instantané bloqué fait échouer une sauvegarde Velero qui n'a, par ailleurs, aucun problème d'emplacement ; un nœud perdu fait aussi basculer la base. Après chaque correction, relance le contrôle de l'exercice correspondant (`lab/bin/check 16 3X`) pour savoir ce qui reste.
</details>

**Pour aller plus loin** : refais l'astreinte avec une autre combinaison, en t'imposant d'écrire **avant** d'agir la commande qui prouvera ta correction.

---

### M16-E44 — Sous le capot : du PVC au bloc monté  `LAB` `★★★★`

> **Ticket PLAT-1744** — *De : Karim Benali*
> Pendant les pannes, tu as vu passer des `NodeStageVolume`, des `globalmount`, des `/dev/rbd0` et des `csi-vol-…` sans toujours savoir qui fait quoi. Je veux une note qui suive **un** volume réel, du PVC jusqu'au bloc monté dans le conteneur et jusqu'à l'image dans Ceph, avec les commandes pour le refaire, et un petit outil qui le fasse pour n'importe quel PVC pendant une astreinte.

**Objectifs pédagogiques**
- Relier chaque objet et chaque appel CSI à son effet concret : `CreateVolume` → image RBD et ses métadonnées omap ; `ControllerPublishVolume` → `VolumeAttachment` ; `NodeStageVolume` → `rbd map` et montage global ; `NodePublishVolume` → montage *bind* dans le répertoire du pod.
- Lire les journaux des sidecars et du pilote avec leurs identifiants de requête, et retrouver les montages sur le nœud.
- Comparer RBD (bloc, RWO) et CephFS (fichier, RWX) au même niveau de détail.

**Prérequis** : M16-E04, M16-E06, M16-E07, M16-E36, M16-E37 ; M12 (espaces de noms de montage) ; M08 (RBD, CephFS, omap).
**Durée indicative** : 3 h.

**Contexte technique** : ceph-csi 3.18 journalise ses appels gRPC à la verbosité 5 (valeur `logLevel` du chart), les sidecars à la verbosité 1 (`sidecarLogLevel`). Le répertoire du kubelet est `/var/lib/kubelet`. ceph-csi range la correspondance « nom de volume Kubernetes ↔ image » dans des objets omap du pool (`csi.volumes.default`, `csi.volume.<uuid>`). Travaille sur un **nouveau** PVC et un **nouveau** pod dans `wb-essais` (pas sur les témoins), que tu supprimeras à la fin.

**Travail demandé**
1. **Avant** de créer quoi que ce soit, prépare l'observation : suis en continu les journaux des conteneurs `csi-provisioner`, `csi-attacher` et `csi-rbdplugin` du provisioner *leader*, et du `csi-rbdplugin` des trois *nodeplugin* :
   ```
   admin@adm01:~$ kubectl get lease -n ceph-csi
   admin@adm01:~$ kubectl logs -n ceph-csi <pod-leader> -c csi-provisioner -f --since=1s
   ```
2. Crée un PVC `exploration` (`ceph-rbd`, 1 Gio). Relève : l'appel `CreateVolume` et sa durée, le nom du PV, le `volumeHandle` et les `volumeAttributes` du PV, l'image RBD créée. Côté Ceph :
   ```
   [admin@ceph01 ~]$ sudo rbd info k8s-rbd/<IMAGE>
   [admin@ceph01 ~]$ sudo rados -p k8s-rbd listomapvals csi.volumes.default
   ```
   Retrouve dans l'omap le lien entre le nom du PV et l'image. Pourquoi ceph-csi en a-t-il besoin (pense à l'idempotence de `CreateVolume`) ?
3. Crée un pod `exploration` qui monte ce PVC. Relève, dans l'ordre : le `VolumeAttachment` (qui le crée, qui le marque attaché, que fait `ControllerPublishVolume` pour RBD ?), l'appel `NodeStageVolume` et la commande `rbd map` dans le journal du *nodeplugin*, puis `NodePublishVolume`.
4. Sur le nœud du pod, retrouve le périphérique et les deux montages :
   ```
   admin@k8s-w0N:~$ lsblk
   admin@k8s-w0N:~$ for d in /sys/bus/rbd/devices/*; do echo "$d $(cat $d/pool)/$(cat $d/name)"; done
   admin@k8s-w0N:~$ findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS | grep -E 'rbd|kubernetes.io~csi'
   ```
   Explique le rôle du montage `…/plugins/kubernetes.io/csi/rbd.csi.ceph.com/<empreinte>/globalmount` et celui de `/var/lib/kubelet/pods/<UID>/volumes/kubernetes.io~csi/<PV>/mount`. Vérifie dans l'espace de noms de montage du conteneur (`crictl inspect` pour le PID, puis `nsenter -t <PID> -m findmnt /chemin`) ce que voit le processus. Côté Ceph, `rbd status` : qui observe l'image, depuis quelle adresse ?
5. Supprime le pod, puis le PVC, et relève les appels inverses (`NodeUnpublishVolume`, `NodeUnstageVolume`, `ControllerUnpublishVolume`, `DeleteVolume`) et leur effet (montages, périphérique, `VolumeAttachment`, image, omap). Où va l'image supprimée (corbeille RBD) ?
6. Refais les étapes 2 à 5 en version courte avec un PVC `cephfs` (RWX) monté par **deux** pods sur deux nœuds : sous-volume (`ceph fs subvolume ls cephfs --group_name csi`, `getpath`), montages `ceph` sur chaque nœud, `VolumeAttachment` (en existe-t-il, et pourquoi ?). Qu'est-ce qui rend le RWX possible ici et impossible avec RBD ?
7. Rédige `docs/kubernetes/stockage/du-pvc-au-bloc.md` : un schéma (texte ou Mermaid) des étages, un tableau « appel CSI → composant → effet observable → commande pour le voir », les sorties réelles abrégées de ton exploration (noms `csi-vol-…`, `/dev/rbdN`, chemins), et ce que chaque étage implique pour le diagnostic (renvoie aux pannes M16-E35 à M16-E42).
8. Écris `k8s-suivre-volume.sh` dans `plateforme/outils` : à partir d'un espace et d'un PVC, il affiche (en lecture seule) la classe, le PV, le pilote, l'image ou le sous-volume, les `VolumeAttachment`, le nœud et le pod qui l'utilisent, et la commande à lancer sur le nœud pour voir les montages. `shellcheck` propre, `--help`, MR.

**Critères de réussite**
- [ ] La note `du-pvc-au-bloc.md` est publiée et contient les noms réels de ton exploration (PV `pvc-…`, image `csi-vol-…` du pool `k8s-rbd`, `/dev/rbdN`, `globalmount`, chemin du pod), les quatre appels CSI de la mise en service, le `VolumeAttachment`, les observateurs de l'image et la correspondance omap, et la partie CephFS.
- [ ] `k8s-suivre-volume.sh` est fusionné dans `plateforme/outils` et donne une sortie juste pour un PVC RBD et un PVC CephFS.
- [ ] Les objets `exploration` sont supprimés et aucune image orpheline ne reste dans `k8s-rbd` (hors corbeille).

**Vérification** : `lab/bin/check 16 44`

<details><summary>Indice 1</summary>

Chaque appel gRPC de ceph-csi est journalisé avec un identifiant de requête (`ID: N Req-ID: …`) : filtre sur cet identifiant pour suivre une requête d'un bout à l'autre, et compare les horodatages entre le provisioner et le *nodeplugin*.
</details>

<details><summary>Indice 2</summary>

`kubectl get pv <pv> -o jsonpath='{.spec.csi}'` donne le `volumeHandle` (qui contient le `clusterID`, l'identifiant du pool et un UUID) et les attributs (`imageName`, `pool`, `journalPool`). Le nom de l'image est `csi-vol-<UUID>` ; l'objet omap `csi.volume.<UUID>` décrit l'image, `csi.volumes.default` fait l'annuaire. Le nom du dossier qui porte `globalmount` dérive du `volumeHandle` (empreinte SHA-256 dans les versions récentes de Kubernetes, nom du PV dans les anciennes) : vérifie-le avec `printf '%s' <volumeHandle> | sha256sum`.
</details>

<details><summary>Indice 3</summary>

Pour `nsenter`, il faut être root sur le nœud : `sudo crictl ps --name <conteneur>`, `sudo crictl inspect <ID> | jq .info.pid`. Un montage *bind* a la même source que le montage global : `findmnt -o TARGET,SOURCE,MAJ:MIN` le montre.
</details>

**Pour aller plus loin** : suis de la même façon un agrandissement en ligne (`ControllerExpandVolume` puis `NodeExpandVolume`, `resize2fs`) et un clone (M16-E10) : qu'est-ce qui change côté Ceph ? Lis la [spécification CSI](https://github.com/container-storage-interface/spec/blob/master/spec.md), section *RPC Interactions* et *Volume Lifecycle*.

---

### M16-E45 — Questions expert : stockage dans Kubernetes  `Q` `★★★`

> **Ticket PLAT-1745** — *De : Claire Morel*
> Avant la recette, je fais passer à chacun les questions qu'on posera aux candidats du futur poste « ingénieur stockage plateforme ». Réponds par écrit, en justifiant ; quand c'est un QCM, dis aussi pourquoi les autres réponses sont fausses.

**Objectifs pédagogiques**
- Mobiliser les mécanismes vus dans le module pour raisonner sur des situations nouvelles.
- Justifier un choix d'exploitation par son effet sur la sûreté des données.

**Prérequis** : M16-E01 à M16-E44.
**Durée indicative** : 1 h 30.

**Questions**

1. Un PVC RWO est monté par un pod sur `k8s-w01`. Tu passes le PVC en `ReadWriteOncePod` dans un nouveau manifeste. Est-ce possible sur un PVC existant ? Quelle garantie supplémentaire `ReadWriteOncePod` apporte-t-elle par rapport à `ReadWriteOnce`, et laquelle n'apporte-t-elle **pas** (pense à un nœud injoignable) ?
2. QCM — Le pilote RBD a `attachRequired: true`, alors que `ControllerPublishVolume` ne fait presque rien pour RBD. Pourquoi garder l'attachement ? (a) pour que le kubelet sache quel périphérique utiliser ; (b) pour que le contrôleur attach/detach applique la règle « un seul nœud » des volumes RWO et attende le détachement avant de réattacher ailleurs ; (c) parce que CSI l'impose à tous les pilotes ; (d) pour que l'image soit verrouillée dans Ceph.
3. `ceph-rbd` est en `volumeBindingMode: Immediate` ou `WaitForFirstConsumer` (M16-E12) : pour un cluster Ceph externe joignable de tous les travailleurs, quel choix fais-tu et pourquoi ? Quand l'autre choix devient-il indispensable ?
4. Explique pourquoi la suppression d'un pod sur un nœud injoignable ne libère pas son volume, et pourquoi la teinte `out-of-service` le libère. Quel est le risque exact si on la pose sur un nœud qui tourne encore, avec un volume ext4 sur RBD ? Comment Ceph peut-il t'en protéger ?
5. Un Velero avec `snapshotMoveData` sauvegarde un volume de 50 Gio dont 2 Gio ont changé depuis la veille. Que transfère Kopia vers `s3-01`, et que coûte la restauration ? En quoi est-ce différent d'un simple instantané CSI ?
6. Une sauvegarde Velero de `mediagenda-recette` (volumes par Kopia) contient le volume de `mediagenda-db`. Pourquoi cette copie n'est-elle pas une sauvegarde fiable de la base, et que faut-il faire à la place (ou en plus) ? Que faudrait-il exclure de Velero, et comment ?
7. L'archivage des WAL échoue depuis 6 h ; la dernière sauvegarde de base date de 20 h. Jusqu'à quel instant peux-tu restaurer avec ce qui est dans `s3-01` ? Et avec ce qui est encore dans `pg_wal` du primaire ? Que se passe-t-il si le volume du primaire se remplit ?
8. QCM — Pendant une bascule CloudNativePG déclenchée par un drain, quelles données peuvent être perdues avec la réplication asynchrone par défaut ? (a) aucune, CloudNativePG attend que la réplique ait tout rejoué ; (b) les transactions validées sur l'ancien primaire et pas encore reçues par la réplique promue ; (c) toutes les transactions depuis le dernier point de contrôle ; (d) les WAL non archivés.
9. Le client noyau de Debian 13 ne connaît pas les clés `aes256k`. Propose deux façons d'utiliser quand même des clés du nouveau type pour ceph-csi, avec leurs coûts (pense au montage par `rbd-nbd` ou par le client en espace utilisateur, et à la montée de noyau).
10. Pourquoi ceph-csi range-t-il des métadonnées dans l'omap du pool (`csi.volumes.default`) plutôt que de déduire tout du nom du PV ? Que se passe-t-il si un administrateur supprime une image RBD `csi-vol-…` à la main sans supprimer le PV ? Et l'inverse ?
11. Rook sur les disques des travailleurs ou ceph-csi vers un Ceph externe : donne trois arguments d'exploitation (pas de performance) pour chaque option dans le contexte de MédiSphère, et dis ce qui a fait pencher l'ADR-0160.
12. Le kubelet expose `kubelet_volume_stats_used_bytes` pour un volume RBD mais pas pour un volume `hostPath`. Pourquoi ? Pour un volume CephFS, que mesure cette métrique, et quelle limite a-t-elle quand le sous-volume a un quota ?

---

*Fin du palier 4. Le mini-projet (`05-mini-projet.md`) livre l'état `k8s-stockage-v1`.*
