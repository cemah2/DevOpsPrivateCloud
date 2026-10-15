# Module 14 — Palier 3 : Production

Le palier 2 a rendu `k8s-par1` utilisable : des espaces cloisonnés, des rôles, des identités, de l'admission, un ordonnancement maîtrisé, des images tirées par Harbor, et un cluster qui se reconstruit depuis `plateforme/k8s`. Mais rien n'est encore **exploitable** au sens de l'astreinte : etcd n'est sauvegardé nulle part (un `kubectl delete namespace` malheureux et tout est perdu), le cluster tourne dans une mineure qui sort de la fenêtre de support dans quelques mois, personne ne sait quand expirent les certificats, l'API ne garde aucune trace de qui fait quoi, et les Secrets sont écrits **en clair** dans etcd. Claire Morel veut un cluster qu'on sait sauvegarder, restaurer, monter de version et réparer quand un nœud de contrôle tombe ; Sophie Laurent veut l'audit et le chiffrement avant d'y mettre la moindre donnée de santé ; Nadia Roussel veut les runbooks. Ce palier fait passer `k8s-par1` en production, puis te fait accueillir une deuxième équipe et passer un examen blanc.

> ⚠️ **Rappel** : `k8s-par1` porte les modules 15 à 29. Ce palier touche à ce qui le fait vivre : etcd, les manifestes statiques du plan de contrôle, les paquets du kubelet, les certificats. Avant **toute** intervention sur un nœud de contrôle : (1) un instantané etcd de moins d'une heure, **vérifié** (à partir de E24 : `outils/etcd-instantane.sh`) ; (2) `kubectl get nodes` tout `Ready` et les trois membres etcd sains ; (3) une session SSH ouverte sur un **autre** nœud de contrôle ; (4) **un seul nœud de contrôle à la fois**, jamais deux (avec trois membres, etcd tolère la perte d'un seul). Ne laisse jamais de copie de sauvegarde dans `/etc/kubernetes/manifests/` : le kubelet y lit **tous** les fichiers et lancerait ta copie comme un second pod.

**Chemin imposé** (introduction du module) : la configuration du cluster vit dans `plateforme/k8s` (`cluster/kubeadm-config.yaml`, `outils/`, `Taskfile.yml`), la configuration des nœuds dans des **rôles Ansible** de `plateforme/ansible` (groupes `k8s_plan_controle`, `k8s_travailleurs`, `k8s_par1`) ; tout passe par une MR relue. Tout nouveau secret (clés S3, clés de chiffrement, `admin.conf` renouvelé) va en Ansible Vault `critique` et au **registre des secrets** ; tout nouveau flux qui traverse les passerelles va dans `group_vars/role_routeur/pare_feu.yml` et `docs/socle/matrice-flux.md`. La documentation va dans `docs/kubernetes/` de `plateforme/medisphere` (`adr/`, `runbooks/`, `tests/`).

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Cluster | `k8s-par1` : `k8s-cp01-03` (10.10.40.51-53, etcd empilé, keepalived VRID 140 + HAProxy 8443), `k8s-w01-03` (10.10.40.61-63) ; API `https://k8s-api.par1.medisphere.internal:8443` (VIP 10.10.40.200) ; kubeadm **1.35.x** au début du palier, **1.36.x** à partir de E25 |
| Versions des images de kubeadm | 1.35.9 : etcd `3.6.6-0`, CoreDNS `v1.13.1`, pause `3.10.1` ; 1.36.5 : etcd `3.6.8-0`, CoreDNS `v1.14.2`, pause `3.10.2` (lis toujours `kubeadm config images list` de **ta** version) |
| Accès | `~/.kube/config` sur `adm01` (identité `<MOI>`, groupe `medisphere:plateforme-admins`) ; `admin.conf` et `super-admin.conf` en Vault `critique` (`plateforme/k8s`, `secrets/`) ; SSH `admin` vers les nœuds, `sudo` |
| Outils etcd | `etcdctl` et `etcdutl` de la **même version que l'etcd de kubeadm**, sur `adm01` et (à partir de E24) sur les nœuds de contrôle, dans `/usr/local/bin` |
| Sauvegarde etcd (E24) | minuterie `etcd-instantane.timer` (horaire) sur les trois nœuds de contrôle ; stockage objet `s3-01` (`https://s3-01.par1.medisphere.internal:8333`), compartiment **`etcd-k8s-par1`**, identité **`etcd-k8s`** ; sur `adm01`, `~/.config/workbook/s3-etcd.env` (600) |
| Audit (E27) | politique `/etc/kubernetes/audit/politique.yaml`, journaux `/var/log/kubernetes/audit/` sur chaque nœud de contrôle |
| Chiffrement (E28) | `EncryptionConfiguration` dans `/etc/kubernetes/chiffrement/` sur chaque nœud de contrôle (root, 600) |
| Runbooks et ADR | RB-141 « restaurer etcd », RB-142 « monter le cluster de version », RB-143 « renouveler les certificats », RB-144 « remplacer un nœud de contrôle » ; ADR-0140 (distribution et topologie), ADR-0141 (politique de versions) |

**Ordre conseillé** : E24 → E25 → E26 → E27 → E28 → E29 → E30 → E31 → E32 → E33 → E34. La sauvegarde (E24) précède tout le reste : chaque exercice suivant commence par un instantané. La montée de version (E25) précède les changements de configuration du serveur d'API (E27, E28), et la perte d'un nœud de contrôle (E29) vient après eux exprès. **Durée totale indicative** : 30 à 36 h.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 14 XX`).

---

### M14-E24 — Sauvegarder et restaurer etcd  `LAB` `★★★`

> **Ticket PLAT-1524** — *De : Claire Morel* — *Copie : Nadia Roussel*
> Tout l'état de `k8s-par1` — chaque Deployment, chaque Secret, chaque rôle — tient dans les trois copies d'etcd. Trois copies dans la même salle, c'est de la disponibilité : un `kubectl delete` se réplique en quelques millisecondes. Les sauvegardes PBS des VMs ne sauveront rien non plus (je veux que tu m'expliques pourquoi).
> Je veux un instantané etcd toutes les heures, chiffré, hors du cluster, et une restauration **faite**, chronométrée, sur le vrai cluster. Pas promise.

**Objectifs pédagogiques**
- Comprendre ce que contient etcd, ce qu'un instantané capture et ce qu'il ne capture pas (volumes, images, fichiers des nœuds).
- Prendre, vérifier, chiffrer et envoyer hors du cluster des instantanés etcd, automatiquement, avec alerte en cas d'échec.
- Restaurer un etcd empilé de trois membres à partir d'un instantané : arrêt du plan de contrôle, `etcdutl snapshot restore` avec la nouvelle composition du cluster, saut de révision, redémarrage ordonné.
- Mesurer un RPO et un RTO réels et écrire RB-141.

**Prérequis** : M14-E04 et E05 (manifestes statiques, certificats d'etcd), M14-E23 (cluster décrit par le code), M05-E10 (`s3-01`, identités et politiques de compartiment), M06-E28 (sauvegardes, chiffrement côté client, registre des secrets), M02-E26 (`ms-alerte@`).
**Durée indicative** : 5 h.

**Contexte technique**
- etcd écoute les clients sur `https://127.0.0.1:2379` et `https://10.10.40.5N:2379` (TLS mutuel, CA `/etc/kubernetes/pki/etcd/ca.crt`) et ses pairs sur `https://10.10.40.5N:2380`. Le nom de chaque membre est le nom du nœud. Lis `/etc/kubernetes/manifests/etcd.yaml` : tous les chemins et options dont tu as besoin y sont.
- Destination : `s3-01`, compartiment **`etcd-k8s-par1`** (versionné), identité **`etcd-k8s`** limitée à ce compartiment (rôle `seaweedfs`, M05-E10). Le flux **VLAN 40 → `s3-01` TCP 8333** traverse les passerelles : s'il n'est pas déjà dans la matrice, ajoute-le.
- Chiffrement côté client avec **`age`** (paquet Debian) : les nœuds n'ont que la clé **publique** ; la clé privée est en Vault `critique` (`plateforme/k8s`, `secrets/`) avec une copie papier hors ligne. Envoi par **`rclone`** (paquet Debian).
- Fréquence : horaire, décalée par nœud (`k8s-cp01` à `:05`, `k8s-cp02` à `:25`, `k8s-cp03` à `:45`) ; rétention à décider (contrainte : la capacité de `s3-01`).
- Fichiers attendus sur `adm01` : `~/.config/workbook/s3-etcd.env` (identité `etcd-k8s`, 600). Scripts : `outils/etcd-instantane.sh` de `plateforme/k8s` (instantané **à la demande** depuis `adm01`, avant une opération) et, sur les nœuds de contrôle, un script de restauration d'un membre installé par le même rôle que la minuterie (il fait les gestes de l'étape 6 pour un nœud ; écris-le après l'avoir fait une fois à la main, ou pendant).

> ⚠️ **Attention** : l'étape 6 **arrête l'API du cluster entier** pendant plusieurs minutes et remplace l'état d'etcd. (1) Fais-la à un moment où rien d'autre ne dépend du cluster ; (2) prends l'instantané de référence toi-même juste avant, télécharge-le, déchiffre-le et vérifie-le (`etcdutl snapshot status`) **avant** d'arrêter quoi que ce soit ; (3) ne supprime jamais l'ancien répertoire de données : **déplace-le** (`/var/lib/etcd.avant-restauration-<DATE>`), c'est ton retour arrière ; (4) écris le retour arrière dans ton journal **avant** de commencer (remettre les anciens répertoires sur les trois nœuds, puis les manifestes) ; (5) les trois membres sont restaurés depuis **le même fichier**.

**Travail demandé**
1. **Lecture.** Dans la documentation Kubernetes (*Operating etcd clusters for Kubernetes*, sections *Backing up* et *Restoring*) et la documentation etcd 3.6 (*Disaster recovery*), réponds dans ton journal : quelle différence entre `etcdctl snapshot save` et copier `member/snap/db` ? Quel outil restaure en 3.6, et pourquoi pas `etcdctl` ? Pourquoi faut-il arrêter **tous** les serveurs d'API avant de restaurer ? Que font `--bump-revision` et `--mark-compacted`, et pourquoi sont-ils recommandés pour Kubernetes ? Pourquoi une restauration crée-t-elle un **nouveau** cluster etcd (identifiants de membres et de cluster) ? Enfin : pourquoi restaurer une **seule** VM de nœud de contrôle depuis PBS dans un cluster vivant est-il dangereux ?
2. **Premier instantané à la main.** Sur `adm01`, avec `etcdctl` de la bonne version et les certificats de `k8s-cp01` (récupérés en lecture, jamais copiés ailleurs que dans un dossier temporaire 700), liste les membres, l'état de chaque point d'accès (`endpoint status --cluster`), puis prends un instantané **sur le nœud** et vérifie-le avec `etcdutl snapshot status`. Relève sa taille, sa révision, son nombre de clés. Lis quelques clés (`get --prefix --keys-only /registry/ | head`) : à quoi ressemble l'arborescence ?
3. **Stockage objet.** Dans le rôle `seaweedfs` (MR sur `plateforme/ansible`) : identité `etcd-k8s` (lecture, écriture et listage du seul compartiment `etcd-k8s-par1`), compartiment versionné. Avec l'identité d'administration, pose une politique qui interdit à `etcd-k8s` de supprimer des objets ou des versions et de toucher au versionnage, et une règle de cycle de vie pour la rétention. Vérifie par l'essai inverse (une suppression avec `etcd-k8s` échoue). Crée `~/.config/workbook/s3-etcd.env`, inscris les deux secrets au registre.
4. **Chiffrement.** Crée la paire de clés `age`. Clé privée : chiffrée en Vault `critique` dans `plateforme/k8s/secrets/`, copie papier, jamais sur un nœud. Clé publique : variable non secrète du rôle.
5. **Le rôle et la minuterie.** Un rôle Ansible `etcd_instantane` pour le groupe `k8s_plan_controle` : `etcdctl`/`etcdutl` de la version d'etcd du cluster (archive officielle vérifiée par empreinte), `age`, `rclone`, secrets S3 (root, 600), script, unités systemd (`oneshot`, `OnFailure=ms-alerte@%n.service`, durcissement), minuterie horaire décalée par nœud, `Persistent=true`. Le script : instantané du membre **local**, vérification (`etcdutl snapshot status`), copie locale (rétention courte), chiffrement, envoi, contrôle de l'envoi, trace du dernier succès (horodatage et nom d'objet) dans `/var/lib/etcd-instantane/`, code retour non nul au moindre échec, aucun secret dans le journal. Ajoute la règle de pare-feu. Teste l'alerte en provoquant un échec (identité S3 fausse le temps d'un passage), puis rétablis.
6. **Restauration réelle.** Prépare le témoin : un ConfigMap `temoin-restauration` (clé `etat` = `avant-instantane`) dans `wb-essais`. Prends l'instantané de référence (`outils/etcd-instantane.sh`), note l'heure. Puis simule l'erreur humaine : passe `etat` à `apres-instantane` et **supprime l'espace `wb-essais`** entier. Restaure maintenant le cluster depuis l'instantané **de `s3-01`** (téléchargé, déchiffré, vérifié) en suivant la documentation : arrêt de tous les composants du plan de contrôle sur les trois nœuds, ancien répertoire déplacé, `etcdutl snapshot restore` sur chaque membre (nom, URL de pair, composition complète du cluster, jeton de cluster neuf, saut de révision, révisions marquées compactées), redémarrage d'etcd sur les trois nœuds, puis des autres composants, puis des kubelets. Chronomètre chaque étape.
7. **Après.** Vérifie : nœuds `Ready`, membres etcd (identifiants **nouveaux**), révision actuelle (supérieure au saut), `wb-essais` revenu avec son contenu, ConfigMap témoin à `avant-instantane`, pods de MédiAgenda relancés (et ce qui **n'est pas** revenu : les données des volumes jetables). Vérifie Cilium (`cilium status`) et relance ce qui doit l'être. Puis seulement, supprime les anciens répertoires de données.
8. **Documentation.** `docs/kubernetes/runbooks/RB-141-restaurer-etcd.md` (quand restaurer et quand **ne pas** restaurer, préalables, téléchargement et déchiffrement, ordre exact, retour arrière, vérifications, durée mesurée) et `docs/kubernetes/tests/restauration-etcd.md` (date, instantané utilisé, chronométrage de chaque étape, RPO et RTO mesurés, écarts). Enfin, vérifie que les VMs `k8s-*` sont bien dans une tâche de sauvegarde PBS (espace de noms `par1/k8s`) et écris dans RB-141 à quoi elles servent — et à quoi elles ne servent pas.

**Critères de réussite**
- [ ] Sur chaque nœud de contrôle, `etcd-instantane.timer` est actif, le dernier passage a réussi il y a moins de 2 h, les secrets S3 sont `root:root` en 600, `etcdctl` a la version de l'etcd du cluster.
- [ ] Le compartiment `etcd-k8s-par1` est versionné et contient, pour chaque nœud de contrôle, un objet de moins de 2 h **chiffré par `age`** ; une suppression avec l'identité `etcd-k8s` est refusée.
- [ ] La restauration a eu lieu : la révision etcd dépasse le saut, `wb-essais` existe et `temoin-restauration` vaut `avant-instantane`.
- [ ] RB-141 et le compte rendu de test (RPO, RTO mesurés) sont sur `main` de `plateforme/medisphere` ; `outils/etcd-instantane.sh` est sur `main` de `plateforme/k8s`, le rôle sur `main` de `plateforme/ansible`.
- [ ] Les VMs 2141-2146 ont une sauvegarde PBS de moins de 48 h dans `par1/k8s`.

**Vérification** : `lab/bin/check 14 24`

<details><summary>Indice 1</summary>

etcd de kubeadm n'active pas l'authentification par utilisateur : tout certificat client signé par la CA d'etcd a tous les droits. Le manifeste d'etcd et le répertoire `/etc/kubernetes/pki/etcd/` te disent quels certificats existent ; choisis-en un dont c'est le rôle (un client, pas le serveur). `etcdctl` lit aussi ses options dans des variables d'environnement `ETCDCTL_*`.
</details>

<details><summary>Indice 2</summary>

Pour arrêter un pod statique, on retire son manifeste de `/etc/kubernetes/manifests/` (vers un dossier **hors** de ce répertoire) et on attend que le kubelet l'arrête (`crictl ps`). Quand le répertoire de données existe déjà, etcd ignore les options `--initial-cluster*` de son manifeste : c'est `etcdutl snapshot restore` qui écrit la composition du cluster. Lis-les donc dans le manifeste pour les recopier exactement.
</details>

<details><summary>Indice 3</summary>

Un seul membre restauré ne démarre pas seul : il attend ses pairs pour former un quorum. Remets les trois manifestes d'etcd à peu près en même temps, attends `endpoint health --cluster`, et seulement ensuite les manifestes des autres composants. Après une restauration, les contrôleurs et les agents qui gardent un cache (kubelet, Cilium) doivent relire l'état : le saut de révision et le marquage « compacté » les y forcent, un redémarrage ordonné fait le reste.
</details>

**Pour aller plus loin** (facultatif) : la défragmentation (`etcdctl defrag`, outil `etcd-defrag`) et le quota d'espace (`--quota-backend-bytes`) ; un instantané vers PBS en plus de `s3-01` ; un etcd externe et ses sauvegardes ; [Operating etcd clusters](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/), [etcd — Disaster recovery](https://etcd.io/docs/v3.6/op-guide/recovery/).

---

### M14-E25 — Monter le cluster de version : 1.35 → 1.36  `LAB` `★★★`

> **Ticket CHG-1525** — *De : Claire Morel* — *Copie : Karim Benali, Julien Petit*
> La 1.35 sort du support en février 2027. L'écosystème que nous allons installer (Cilium, cert-manager, ceph-csi, CloudNativePG) suit la 1.36 et pas encore la 1.37 : on monte en **1.36**, dernier correctif. Contrainte : MédiAgenda en recette ne doit pas être interrompu, et je veux pouvoir rejouer cette montée tous les quatre mois sans réfléchir. Un playbook, un runbook, un compte rendu.

**Objectifs pédagogiques**
- Lire des notes de version et la politique de décalage de versions (*version skew*) et en tirer un plan.
- Monter de version un cluster kubeadm hautement disponible dans l'ordre documenté : dépôt de paquets, premier nœud de contrôle (`upgrade plan`, `upgrade apply`), autres nœuds de contrôle (`upgrade node`), kubelets, travailleurs un par un avec drainage.
- Comprendre ce que `kubeadm upgrade` fait seul (manifestes, etcd, CoreDNS, kube-proxy, certificats) et ce qu'il ne fait pas (CNI, paquets, runtime, outils).
- Industrialiser : playbook Ansible rejouable, RB-142.

**Prérequis** : M14-E24 (instantané vérifié), M14-E16 (PDB), M14-E17 (drain), M14-E23 (rôles des nœuds, `cluster/kubeadm-config.yaml`).
**Durée indicative** : 4 h.

**Contexte technique**
- Version actuelle : 1.35.x (celle installée en E04). Cible : **v1.36.5** (dernier correctif de la 1.36 à la rédaction ; prends le dernier au moment où tu le fais). Paquets `pkgs.k8s.io` : un dépôt **par mineure** (`/core:/stable:/v1.36/deb/`), versions de la forme `1.36.5-1.1`, épinglés (`apt-mark hold`) par le rôle `k8s_noeud`.
- Compatibilités à vérifier toi-même : Cilium 1.20 (sa page *requirements*), metrics-server (E20), kubectl 1.36 de `adm01`, containerd.io 2.3 (le `RELEASES.md` de containerd), la configuration kubeadm v1beta4 de `plateforme/k8s`.
- Charge témoin : MédiAgenda en `mediagenda-recette` (au moins deux réplicas et leur PDB, M14-E21). Une boucle de requêtes depuis `adm01` (via `kubectl port-forward` ou un pod client dans l'espace) qui journalise chaque échec.
- La version est dans le code à trois endroits au moins : la version des paquets des faits partagés (`group_vars/k8s_par1/kubernetes.yml`, M14-E02), `kubernetesVersion` de `cluster/kubeadm-config.yaml`, la version des outils etcd du rôle `etcd_instantane`. Et une quatrième, cachée : l'image *pause* que containerd épingle. Le rôle `k8s_noeud` refuse de changer la version d'un nœud déjà membre hors d'un playbook de montée : lis comment il l'autorise.

> ⚠️ **Attention** : (1) instantané etcd **juste avant** (`outils/etcd-instantane.sh`), vérifié ; (2) on ne saute **jamais** de mineure, et on ne redescend pas une mineure avec kubeadm : le retour arrière d'une montée réussie sur le plan de contrôle, c'est la restauration d'etcd (RB-141) et des paquets 1.35 — écris-le dans le plan ; (3) un seul nœud à la fois, et le nœud suivant seulement quand le précédent est `Ready` et ses pods revenus ; (4) le premier nœud de contrôle doit avoir `/etc/kubernetes/admin.conf`.

**Travail demandé**
1. **Lecture.** Lis le CHANGELOG 1.36 (*Urgent Upgrade Notes*, *Deprecation*, kubeadm), la page *Upgrading kubeadm clusters*, *Upgrading Linux nodes*, *Changing the Kubernetes package repository* et *Version Skew Policy*. Dans le ticket : les changements de 1.36 qui touchent **ce** cluster (et ceux qui ne le touchent pas, avec la raison) ; l'ordre officiel des étapes pour un nœud de contrôle et pour un travailleur ; quand les modules complémentaires (CoreDNS, kube-proxy) sont mis à jour en HA et pourquoi ; les décalages autorisés kubelet ↔ API et kubectl ↔ API ; ce que `kubeadm upgrade` sauvegarde dans `/etc/kubernetes/tmp/` ; ce qu'il fait des certificats. Vérifie que `cluster/kubeadm-config.yaml` passe `kubeadm config validate` avec kubeadm 1.36 et dis si `kubeadm config migrate` est nécessaire.
2. **Plan.** Écris le plan de changement : préalables (santé, instantané, sauvegarde PBS de la nuit, PDB, capacité pour drainer un travailleur), ordre des nœuds, critère de passage d'un nœud au suivant, durée estimée, retour arrière à chaque étape, communication. Ouvre la MR qui porte la nouvelle version **dans le code** (rôles et `kubeadm-config.yaml`) : elle sera fusionnée **après** la montée, quand le code décrira la réalité.
3. **Charge témoin.** Lance la boucle vers MédiAgenda 10 minutes **avant** : c'est ta ligne de base.
4. **Premier nœud de contrôle à la main** (`k8s-cp01`). Change le dépôt de paquets vers la 1.36, monte **seulement** `kubeadm`, lis `kubeadm upgrade plan` en entier (versions proposées, tableau des configurations de composants), lance `kubeadm upgrade apply v1.36.5`, puis drainage, `kubelet` et `kubectl`, redémarrage du kubelet, remise en service. Relève l'ordre des composants redémarrés et la durée de chaque étape ; regarde `/etc/kubernetes/tmp/`.
5. **Le reste par le playbook.** Écris un playbook `playbooks/k8s-montee-version.yml` qui fait, pour les autres nœuds de contrôle **puis** les travailleurs, un nœud à la fois : dépôt, `kubeadm`, `kubeadm upgrade node`, drainage (depuis `adm01`), `kubelet`/`kubectl`, redémarrage, attente du `Ready`, remise en service, contrôle de santé avant de passer au suivant. Il doit être **rejouable** (un nœud déjà à jour est sauté sans rien casser) et s'arrêter au premier échec. Lance-le.
6. **Après.** Vérifie les versions (nœuds, images du plan de contrôle, etcd, CoreDNS, kube-proxy, `kubeadm-config`), Cilium (`cilium status`), metrics-server (`kubectl top nodes`), l'avertissement éventuel de containerd sur l'image *pause* (et corrige le rôle `containerd`), les outils etcd des nœuds de contrôle **et** de `adm01` (rôle `outils_k8s`) : version alignée sur l'etcd du cluster. Fusionne la MR, rejoue les rôles des nœuds : aucun changement attendu. Arrête la boucle témoin et analyse son journal. Prends un instantané etcd de la 1.36.
7. **Runbook.** `docs/kubernetes/runbooks/RB-142-monter-de-version.md` : préalables, lecture des notes, ordre, commandes et playbook, critères de passage, retour arrière (y compris « la montée a échoué au milieu d'un nœud »), vérifications, nettoyage de `/etc/kubernetes/tmp/`, et ce que la montée **suivante** (1.37) devra vérifier en plus. Compte rendu dans `docs/kubernetes/tests/montee-1.36.md`.

**Critères de réussite**
- [ ] Les six nœuds sont `Ready`, aucun n'est en `SchedulingDisabled`, tous ont un kubelet `v1.36.x` ; `kubeadm-config` et les images du plan de contrôle, d'etcd, de CoreDNS et de kube-proxy sont celles de la 1.36.
- [ ] Sur chaque nœud, le dépôt de paquets est celui de la 1.36 (plus aucune référence à la 1.35), `kubeadm`, `kubelet` et `kubectl` sont épinglés ; l'image *pause* de containerd est celle de kubeadm 1.36 ; les outils etcd des nœuds de contrôle ont la version de l'etcd du cluster.
- [ ] Cilium est sain sur tous les nœuds.
- [ ] La boucle témoin n'a enregistré aucune interruption de MédiAgenda (des latences ponctuelles sont admises et commentées).
- [ ] `cluster/kubeadm-config.yaml` déclare la 1.36 sur `main` de `plateforme/k8s` ; le playbook est sur `main` de `plateforme/ansible` ; RB-142 et le compte rendu sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 14 25`

<details><summary>Indice 1</summary>

Le dépôt pkgs.k8s.io est décrit dans un fichier de `/etc/apt/sources.list.d/` et sa clé dans `/etc/apt/keyrings/` : la mineure figure dans l'URL. Un paquet épinglé (`hold`) ne se met pas à jour, même avec `apt-get install` sans version : il faut lever l'épingle, installer **la** version voulue, remettre l'épingle.
</details>

<details><summary>Indice 2</summary>

Depuis 1.28, `kubeadm upgrade apply` ne met à jour CoreDNS et kube-proxy qu'une fois **tous** les nœuds de contrôle passés : ne t'étonne pas de les voir encore en ancienne version après le premier nœud. Sur un travailleur, `kubeadm upgrade node` ne fait que récupérer la nouvelle configuration du kubelet : le changement de version, c'est le paquet `kubelet` et son redémarrage.
</details>

<details><summary>Indice 3</summary>

Dans le playbook, `serial: 1` et `any_errors_fatal: true` donnent « un nœud à la fois, arrêt au premier échec ». Le drainage et la remise en service se lancent depuis `adm01` (`delegate_to: localhost`, sans `become`), avec ton kubeconfig. Pour sauter un nœud déjà à jour, compare la version du kubelet du nœud (vue par l'API) à la cible.
</details>

**Pour aller plus loin** (facultatif) : `UpgradeConfiguration` (v1beta4) et `kubeadm upgrade apply --config` ; `kubeadm upgrade diff` ; la mise à jour des correctifs (1.36.5 → 1.36.6) avec le même playbook ; [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/), [Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/).

---

### M14-E26 — Les certificats du cluster  `LAB` `★★★`

> **Ticket SEC-1526** — *De : Sophie Laurent*
> Chez notre ancien infogérant, un cluster s'est arrêté net un dimanche matin : certificats expirés, un an jour pour jour après l'installation. Je veux l'inventaire de **tous** les certificats de `k8s-par1` (qui les émet, pour combien de temps, qui les renouvelle), une procédure de renouvellement testée, et la fin des certificats auto-signés des kubelets : metrics-server ne doit plus avoir besoin de désactiver la vérification TLS.

**Objectifs pédagogiques**
- Cartographier les trois autorités d'un cluster kubeadm (`ca`, `etcd-ca`, `front-proxy-ca`), les certificats feuilles, les kubeconfigs et leurs durées.
- Lire les échéances (`kubeadm certs check-expiration`, `openssl`) et renouveler manuellement (`kubeadm certs renew`), en redémarrant ce qui doit l'être.
- Comprendre la rotation des certificats du kubelet (client et service), activer les certificats de service signés (`serverTLSBootstrap`) et approuver les demandes **après les avoir lues**.
- Écrire RB-143 et la surveillance des échéances.

**Prérequis** : M14-E04 (PKI de kubeadm, `admin.conf` / `super-admin.conf`), M14-E12 (API CSR), M14-E20 (metrics-server), M14-E25 (certificats renouvelés par la montée).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Sur chaque nœud de contrôle : `/etc/kubernetes/pki/` et les kubeconfigs `/etc/kubernetes/*.conf` (`super-admin.conf` n'existe que sur le nœud d'amorçage). Sur chaque nœud : `/var/lib/kubelet/pki/` et `/etc/kubernetes/kubelet.conf`.
- Configuration du kubelet : ConfigMap `kubelet-config` (`kube-system`) et fichier local `/var/lib/kubelet/config.yaml` de chaque nœud (page *Reconfiguring a kubeadm cluster*).
- metrics-server (E20) tourne dans `kube-system`.
- `admin.conf` et `super-admin.conf` sont en Vault `critique` dans `plateforme/k8s` (`secrets/`) : un renouvellement les rend obsolètes.

> ⚠️ **Attention** : `kubeadm certs renew` ne recharge rien : les composants gardent l'ancien certificat en mémoire jusqu'à leur redémarrage. Redémarre-les **un nœud à la fois** (manifestes retirés puis remis, hors de `/etc/kubernetes/manifests/`), et vérifie la santé (API, etcd) entre deux nœuds. N'approuve **aucune** demande de certificat sans en avoir lu le contenu.

**Travail demandé**
1. **Inventaire.** Pour chaque certificat et kubeconfig d'un nœud de contrôle et d'un travailleur : autorité émettrice, sujet (CN, O), noms alternatifs, date de fin, qui le renouvelle (kubeadm à la montée de version, `kubeadm certs renew`, le kubelet lui-même, personne). Compare `kubeadm certs check-expiration` et `openssl x509 -noout -dates -subject -ext subjectAltName`. Réponds : pourquoi les certificats ont-ils déjà été renouvelés en E25 ? Que se passe-t-il le jour où une **CA** expire ? Que valent `certificateValidityPeriod` et `caCertificateValidityPeriod` dans **ta** configuration, et où les régler ?
2. **Renouvellement manuel.** Sur chaque nœud de contrôle, un à la fois : renouvelle tous les certificats gérés par kubeadm, redémarre les composants du plan de contrôle (y compris etcd), vérifie les nouvelles dates **dans les processus** (le certificat présenté par le port 6443 du nœud, celui d'etcd sur 2379) et pas seulement sur le disque. Mets à jour `admin.conf` et `super-admin.conf` en Vault (MR), sans jamais les écrire en clair dans un dépôt.
3. **Kubelet, certificat client.** Montre que le certificat client du kubelet tourne seul : `rotateCertificates`, lien `kubelet-client-current.pem`, CSR approuvées automatiquement (par qui ?). Explique ce qui se passe pour un nœud éteint plus longtemps que la durée de son certificat.
4. **Kubelet, certificat de service.** Regarde le certificat que présente le port 10250 d'un nœud : qui l'a signé ? Active `serverTLSBootstrap` (ConfigMap `kubelet-config` **et** fichier de chaque nœud, par le code), redémarre les kubelets un à un, lis chaque demande `kubernetes.io/kubelet-serving` (demandeur, noms et adresses demandés) et approuve celles qui sont légitimes. Vérifie le certificat servi par les six nœuds avec la CA du cluster.
5. **metrics-server.** Retire l'option qui désactive la vérification TLS des kubelets (si E20 l'a posée), vérifie `kubectl top nodes`. Quelles demandes restent à approuver dans un an, et comment le saurais-tu ?
6. **Surveillance et runbook.** Un script `outils/certificats-echeances.sh` (`plateforme/k8s`) qui lit, sur chaque nœud, les échéances (kubeadm, kubelet client et service) et sort en erreur sous un seuil (30 jours) ; une minuterie hebdomadaire `k8s-certificats.timer` sur `adm01` (service `k8s-certificats.service`) reliée à `ms-alerte@`. `docs/kubernetes/runbooks/RB-143-renouveler-les-certificats.md` : inventaire, échéances, renouvellement, redémarrages, kubeconfigs du coffre, demandes des kubelets, et la rotation de la CA (procédure de la documentation, non jouée ici) avec la date à laquelle il faudra s'en occuper.

**Critères de réussite**
- [ ] Sur les trois nœuds de contrôle, tous les certificats gérés par kubeadm ont plus de 180 jours devant eux et les autorités plus de 9 ans ; le serveur d'API et etcd de chaque nœud présentent les certificats renouvelés.
- [ ] `serverTLSBootstrap: true` est dans le ConfigMap `kubelet-config` ; le port 10250 des six nœuds présente un certificat signé par la CA du cluster et valide pour le nom du nœud ; aucune demande `kubelet-serving` n'attend depuis plus d'une heure.
- [ ] metrics-server ne désactive plus la vérification TLS et `kubectl top nodes` répond.
- [ ] `k8s-certificats.timer` est actif sur `adm01` ; `admin.conf` et `super-admin.conf` chiffrés sur `main` de `plateforme/k8s` ; RB-143 sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 14 26`

<details><summary>Indice 1</summary>

`kubeadm certs check-expiration` couvre les fichiers de `/etc/kubernetes/pki/` et les certificats **incorporés** aux kubeconfigs de kubeadm (`admin.conf`, `super-admin.conf`, `controller-manager.conf`, `scheduler.conf`), pas `kubelet.conf` : regarde vers quoi pointe ce dernier. `openssl s_client -connect <hôte>:<port> </dev/null | openssl x509 -noout -dates` montre ce que le processus sert vraiment.
</details>

<details><summary>Indice 2</summary>

Le gestionnaire de contrôleurs approuve automatiquement les demandes **client** des kubelets (bootstrap et renouvellement), jamais les demandes de **service** : un certificat de service dit « je suis tel nom, telle adresse », et l'API ne peut pas vérifier seule qu'un kubelet a droit à ces noms. D'où la lecture de chaque demande (`kubectl get csr <nom> -o jsonpath='{.spec.request}'`, décodée en base64, puis `openssl req -noout -text`).
</details>

<details><summary>Indice 3</summary>

Pendant une montée de version, kubeadm récupère le ConfigMap `kubelet-config` et **écrase** `/var/lib/kubelet/config.yaml` : un réglage posé seulement dans le fichier local disparaît à la montée suivante. Le ConfigMap est la référence, le fichier local en est une copie à rafraîchir (`kubeadm upgrade node phase kubelet-config`).
</details>

**Pour aller plus loin** (facultatif) : `--kubelet-certificate-authority` sur le serveur d'API (vérifier les kubelets aussi côté API) ; un approbateur automatique de demandes de service (`kubelet-csr-approver`) et ses contrôles ; cert-manager (M15) ; [Certificate Management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/), [Kubelet TLS bootstrapping](https://kubernetes.io/docs/reference/access-authn-authz/kubelet-tls-bootstrapping/).

---

### M14-E27 — Auditer l'API  `LAB` `★★★`

> **Ticket SEC-1527** — *De : Sophie Laurent* — *Copie : Julien Petit*
> Ce matin, le Deployment de test `rdv-essai-audit` de MédiAgenda a disparu de `mediagenda-dev`. Julien jure que ce n'est pas lui. Aujourd'hui, personne ne peut le prouver ni dans un sens ni dans l'autre.
> HDS et ISO 27001 exigent la traçabilité des actions d'administration. Je veux savoir qui a fait quoi, quand, depuis où, sur l'API — sans que les journaux d'audit deviennent eux-mêmes une fuite de données (le contenu des Secrets n'a rien à y faire) ni ne remplissent les disques.

**Objectifs pédagogiques**
- Comprendre le pipeline d'audit du serveur d'API : étapes (`RequestReceived`, `ResponseStarted`, `ResponseComplete`, `Panic`), niveaux (`None`, `Metadata`, `Request`, `RequestResponse`), règles évaluées dans l'ordre.
- Écrire une politique par niveaux : bruit écarté, Secrets et jetons en `Metadata`, écritures tracées, lectures sensibles tracées.
- Activer l'audit sur un plan de contrôle kubeadm HA **par la configuration du cluster** (et pas seulement dans les manifestes), avec rotation des fichiers.
- Mener une enquête dans les journaux (`jq`) et en tirer une réponse argumentée.

**Prérequis** : M14-E11 et E12 (rôles, identité de `julien.petit`), M14-E25 (`ClusterConfiguration` et montée de version), M14-E24 (instantané).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Politique : `/etc/kubernetes/audit/politique.yaml` sur les trois nœuds de contrôle, déposée par un rôle Ansible `k8s_audit`. Journaux : `/var/log/kubernetes/audit/audit.log` (JSON, une ligne par événement) et ses rotations.
- Disque des nœuds de contrôle : 40 Go, partagé avec etcd et les images. Rétention locale à décider (les journaux partiront vers une plateforme centrale au module 22).
- Une requête de `kubectl` passe par la VIP et HAProxy : elle peut atterrir sur **n'importe lequel** des trois serveurs d'API. Une enquête lit donc les trois journaux.
- La configuration du serveur d'API passe par `apiServer.extraArgs` et `apiServer.extraVolumes` de la `ClusterConfiguration` (v1beta4 : `extraArgs` est une liste de `{name, value}`), appliquée nœud par nœud (page *Reconfiguring a kubeadm cluster*).

> ⚠️ **Attention** : une erreur dans la politique ou dans un chemin monté empêche le serveur d'API de démarrer. Applique **un nœud de contrôle à la fois**, vérifie qu'il revient (`/readyz` sur son port 6443, pod `Running`) avant le suivant, et garde la copie de son manifeste **hors** de `/etc/kubernetes/manifests/` pour revenir en arrière. Instantané etcd avant de commencer.

**Travail demandé**
1. **Lecture.** Page *Auditing* et référence de l'API `audit.k8s.io/v1` : réponds dans ton journal : quelle règle s'applique quand plusieurs correspondent ? Que contient un événement au niveau `Metadata` ? Pourquoi `RequestResponse` sur les Secrets serait une faute ? Que coûte un niveau élevé sur les `watch` et les `list` ? Quelles options du serveur d'API règlent la rotation des fichiers ?
2. **Politique.** Écris la politique (dans le rôle `k8s_audit`, MR) : rien pour les requêtes de santé et le bruit identifié (lectures des composants système sur les baux, les points d'accès, les événements) ; `Metadata` pour Secrets, ConfigMaps, `tokenreviews`, `serviceaccounts/token` ; `Request` (ou `RequestResponse`, à justifier) pour les écritures sur les objets d'application, le RBAC et l'admission ; `Metadata` par défaut. Pas d'étape `RequestReceived`. Justifie chaque règle en commentaire.
3. **Activation par le code.** Dans `cluster/kubeadm-config.yaml` de `plateforme/k8s` : options d'audit (fichier de politique, chemin du journal, rotation : âge, nombre, taille, compression) et volumes montés (politique en lecture seule, répertoire des journaux). Fais aussi entrer la nouvelle `ClusterConfiguration` dans le ConfigMap `kubeadm-config` : explique ce qui arriverait à la **prochaine** montée de version si tu ne modifiais que les manifestes. Applique nœud par nœud et vérifie.
4. **Mesure.** Laisse tourner 30 minutes : taille produite par heure et par nœud, répartition des événements par utilisateur et par ressource. Ajuste la politique si un consommateur bruyant domine, recalcule la rétention locale possible.
5. **Enquête.** Rejoue la scène : avec l'identité de `julien.petit` (E12), puis la tienne, crée le Deployment `rdv-essai-audit` dans `mediagenda-dev`, puis qu'une **seule** des deux identités le supprime (choisis au hasard, sans regarder). Retrouve dans les journaux des trois nœuds : qui l'a supprimé, à quelle heure, depuis quelle adresse, avec quel client, par quel serveur d'API, avec quel code de réponse. Vérifie aussi qu'un Secret créé pour l'occasion apparaît en `Metadata` sans son contenu. Écris la réponse au ticket (avec la commande `jq` qui la prouve) dans `docs/kubernetes/tests/enquete-audit.md`, et ce qu'elle ne prouve **pas** (comptes partagés, `admin.conf`, adresse vue derrière HAProxy).

**Critères de réussite**
- [ ] Les trois serveurs d'API tournent avec la politique d'audit, un journal sous `/var/log/kubernetes/audit/` et une rotation bornée (âge, nombre, taille) ; ces options sont dans le ConfigMap `kubeadm-config` et dans `cluster/kubeadm-config.yaml` sur `main`.
- [ ] Chaque journal est écrit (événement de moins de 10 minutes) et ne contient aucune étape `RequestReceived`.
- [ ] Les événements sur les Secrets sont au niveau `Metadata`, sans corps de requête ni de réponse.
- [ ] La suppression de `mediagenda-dev/rdv-essai-audit` est retrouvée dans les journaux ; le compte rendu d'enquête est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 14 27`

<details><summary>Indice 1</summary>

La première règle qui correspond l'emporte : les exceptions (bruit en `None`, Secrets en `Metadata`) vont **avant** les règles générales. `omitStages` peut se poser au niveau de la politique entière. Une règle peut filtrer par `users`, `userGroups`, `verbs`, `resources` (groupe, ressources, sous-ressources), `namespaces` et `nonResourceURLs`.
</details>

<details><summary>Indice 2</summary>

Dans un manifeste statique, un fichier n'est visible du conteneur que s'il est monté : `extraVolumes` (nom, chemin hôte, chemin dans le pod, lecture seule, type de chemin). Pour régénérer le manifeste d'un nœud à partir d'une configuration, regarde `kubeadm init phase control-plane` ; pour mettre à jour le ConfigMap, `kubeadm init phase upload-config`. Attention à la partie **propre au nœud** (adresse annoncée) du fichier que tu passes.
</details>

<details><summary>Indice 3</summary>

Champs utiles d'un événement : `verb`, `objectRef` (`resource`, `namespace`, `name`), `user.username`, `user.groups`, `impersonatedUser`, `sourceIPs`, `userAgent`, `responseStatus.code`, `requestReceivedTimestamp`, `auditID`. `zcat -f` lit indifféremment les fichiers compressés et ceux qui ne le sont pas.
</details>

**Pour aller plus loin** (facultatif) : le *webhook backend* (envoi direct vers un collecteur), `--audit-log-mode=batch` et ses réglages ; l'audit d'etcd lui-même (il n'y en a pas : pourquoi l'accès aux certificats d'etcd doit être aussi protégé que la CA) ; [Auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/).

---

### M14-E28 — Chiffrer les Secrets dans etcd  `LAB` `★★★`

> **Ticket SEC-1528** — *De : Sophie Laurent*
> En lisant l'instantané etcd de E24 avec un simple `strings`, j'ai retrouvé le mot de passe PostgreSQL de MédiAgenda. Une sauvegarde volée, un disque de nœud de contrôle récupéré, un accès aux certificats d'etcd : et tous nos Secrets sont à nu.
> Je veux les Secrets chiffrés au repos, une rotation de clé **démontrée**, et une analyse de ce que ça protège vraiment — et de ce que ça ne protège pas. La liste de contrôle de l'audit cite `aescbc` ; lis la documentation et dis-moi si c'est encore le bon choix.

**Objectifs pédagogiques**
- Comprendre le chiffrement au repos du serveur d'API : `EncryptionConfiguration`, ordre des fournisseurs (le premier chiffre, tous déchiffrent), préfixe stocké dans etcd.
- Activer le chiffrement sur un plan de contrôle HA sans rendre un Secret illisible par un des serveurs d'API pendant la transition.
- Réécrire les Secrets existants, faire tourner une clé, et vérifier **dans etcd** (lecture brute).
- Situer les fournisseurs locaux (`aescbc`, `aesgcm`, `secretbox`) et KMS v2 (Vault au module 25) dans un modèle de menace.

**Prérequis** : M14-E24 (instantané, `etcdctl` sur les nœuds), M14-E27 (configuration du serveur d'API par le code, nœud par nœud).
**Durée indicative** : 3 h.

**Contexte technique**
- Fichier : `/etc/kubernetes/chiffrement/configuration.yaml` sur les trois nœuds de contrôle (root, 600, répertoire 700), déposé par un rôle Ansible `k8s_chiffrement` à partir de clés en Vault `critique`. Le répertoire est monté dans le pod du serveur d'API.
- Option de rechargement automatique du fichier : `--encryption-provider-config-automatic-reload` (lis la documentation : ce qu'elle change pour une rotation).
- Témoin : un Secret `temoin-chiffrement` dans `wb-essais`, créé **avant** l'activation.
- Lecture brute : `etcdctl get /registry/secrets/<espace>/<nom>` sur un nœud de contrôle, la sortie passée dans `hexdump -C` (jamais affichée telle quelle dans un terminal partagé ou un journal).

> ⚠️ **Attention** : (1) si un serveur d'API chiffre avec une clé qu'un autre ne connaît pas encore, ce dernier ne peut plus **lire** les Secrets concernés ; chaque étape doit être en place sur les **trois** nœuds avant la suivante ; (2) une clé perdue rend illisibles les Secrets qu'elle a chiffrés **et les instantanés etcd** qui les contiennent : la clé est en Vault et au registre **avant** d'être utilisée, et une ancienne clé n'est détruite qu'après la fin de la rétention des instantanés ; (3) instantané etcd avant de commencer.

**Travail demandé**
1. **Lecture.** Page *Encrypting Confidential Data at Rest* : réponds : que stocke etcd pour un Secret quand le premier fournisseur est `identity` ? Que se passe-t-il pour un Secret écrit en clair quand on active un fournisseur ? Pourquoi `aescbc` n'est-il plus recommandé ? Parmi les fournisseurs locaux, lequel la documentation ne déconseille-t-elle pas, et quelle réserve fait-elle à son sujet ? Où vit la clé dans chaque cas ? Qu'apporte KMS v2 ?
2. **Constat.** Crée `wb-essais/temoin-chiffrement` avec une valeur reconnaissable, lis-le brut dans etcd : que vois-tu ? Fais de même dans l'instantané de E24 (`strings`).
3. **Activation sans coupure.** Rôle `k8s_chiffrement` et `cluster/kubeadm-config.yaml` (options du serveur d'API, volume monté, MR). Déroule l'activation en étapes sûres pour trois serveurs d'API : d'abord une configuration où **tous** savent déchiffrer `aescbc` mais écrivent encore en clair, appliquée sur les trois ; ensuite seulement `aescbc` en premier. Entre deux étapes, vérifie sur chaque nœud que la configuration en vigueur est la bonne.
4. **Réécriture.** Recrée le témoin (ou modifie-le) et vérifie son préfixe dans etcd. Puis réécris **tous** les Secrets du cluster pour qu'aucun ne reste en clair, et vérifie-le sur l'ensemble des clés `/registry/secrets/` (un décompte, pas un affichage).
5. **Rotation.** Fais tourner la clé en suivant la documentation (nouvelle clé connue de tous → nouvelle clé en premier → réécriture → retrait de l'ancienne), en passant, pour la nouvelle clé, au fournisseur local que la documentation ne déconseille pas. Vérifie le nouveau préfixe et le nom de la clé dans etcd. Garde l'ancienne clé en Vault (pourquoi ?).
6. **Analyse.** Dans `docs/kubernetes/securite/chiffrement-secrets.md` (`plateforme/medisphere`) : contre quoi ce chiffrement protège (instantané volé, disque d'un nœud, accès direct à etcd sans les fichiers du nœud), contre quoi il ne protège pas (quiconque peut lire les Secrets par l'API, root d'un nœud de contrôle, la sauvegarde qui contient aussi la clé), conséquences pour RB-141 (restaurer un instantané exige la bonne clé : laquelle, où), calendrier de rotation, et le passage à KMS v2 avec Vault (M25). Mets RB-141 à jour.

**Critères de réussite**
- [ ] Les trois serveurs d'API ont l'option `--encryption-provider-config` (et le rechargement automatique), présente aussi dans `kubeadm-config` et sur `main` de `plateforme/k8s`.
- [ ] Sur chaque nœud de contrôle, le fichier de configuration est `root` en 600 et son premier fournisseur pour les Secrets n'est pas `identity`.
- [ ] Dans etcd, `wb-essais/temoin-chiffrement` et **tous** les autres Secrets portent le préfixe d'un fournisseur de chiffrement ; la clé en usage est celle de la rotation (fournisseur local non déconseillé par la documentation).
- [ ] L'analyse est sur `main` de `plateforme/medisphere` et RB-141 cite la clé de chiffrement parmi les préalables d'une restauration.

**Vérification** : `lab/bin/check 14 28`

<details><summary>Indice 1</summary>

Le serveur d'API essaie les fournisseurs dans l'ordre pour **lire** (le préfixe stocké dit lequel a chiffré), et n'utilise que le premier pour **écrire**. Une liste `[identity, aescbc]` lit tout et écrit en clair ; `[aescbc, identity]` écrit chiffré et lit encore les anciens Secrets en clair.
</details>

<details><summary>Indice 2</summary>

Une clé `aescbc` ou `secretbox` fait 32 octets aléatoires, encodés en base64. Pour réécrire un objet sans le modifier, la documentation propose une seule commande qui lit tous les Secrets et les remplace. Pour compter les clés etcd encore en clair, lis seulement les premiers octets de chaque valeur.
</details>

<details><summary>Indice 3</summary>

Avec le rechargement automatique, le serveur d'API relit le fichier quand il change : pas de redémarrage pour une rotation, mais un délai à attendre et à vérifier (journal du serveur d'API, métriques `apiserver_encryption_config_controller_*` sur `/metrics`). Le répertoire doit être monté (pas le fichier seul) pour qu'un remplacement de fichier soit visible dans le conteneur.
</details>

**Pour aller plus loin** (facultatif) : chiffrer aussi d'autres ressources (lesquelles ? à quel coût ?) ; la page *KMS provider* et la conception d'un plugin KMS v2 vers Vault (M25) ; [Encrypting Confidential Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/).

---

### M14-E29 — Perdre un nœud de contrôle  `LAB` `★★★`

> **Ticket PLAT-1529** — *De : Nadia Roussel*
> On me dit que le plan de contrôle est « redondant ». Je veux le **voir** : on coupe un nœud de contrôle sans prévenir, on regarde ce qui se passe minute par minute, et je veux savoir ce que fait l'astreinte. Ensuite, on fait comme si son disque était perdu : on le sort proprement du cluster et on le remplace. Et j'aurai un runbook.

**Objectifs pédagogiques**
- Observer la tolérance aux pannes d'un plan de contrôle empilé : quorum etcd, VIP keepalived, HAProxy, élection du gestionnaire de contrôleurs et de l'ordonnanceur, état du nœud et éviction des pods.
- Remplacer un membre etcd et un nœud de contrôle : retrait du membre, suppression du nœud, `kubeadm reset`, nouvelle jonction (`--control-plane`, clé de certificats).
- Comprendre pourquoi deux nœuds perdus sur trois, c'est une autre histoire.

**Prérequis** : M14-E03 à E05 (VIP, jonction), M14-E24 (instantané, `etcdctl`), M14-E27 et E28 (fichiers du serveur d'API sur les nœuds).
**Durée indicative** : 3 h.

**Contexte technique**
- Nœud sacrifié : **`k8s-cp02`** (VMID 2142). Arrêt brutal depuis `pve01` (`qm stop`), pas un arrêt propre.
- Mesures depuis `adm01` pendant tout l'exercice : une boucle sur `https://k8s-api.par1.medisphere.internal:8443/readyz` (une ligne horodatée par seconde) et une sur MédiAgenda ; dans un autre terminal, `kubectl get nodes -w` et les événements.
- La jonction du nouveau membre passe par le rôle `k8s_plan_controle` (E05) ou par les commandes de E05, au choix ; dans les deux cas, tout ce que le serveur d'API attend sur le disque (audit, chiffrement) doit être présent **avant**.
- Documentation : `docs/kubernetes/runbooks/RB-144-remplacer-un-noeud-de-controle.md` et `docs/kubernetes/tests/perte-plan-controle.md`.

> ⚠️ **Attention** : (1) instantané etcd vérifié et les trois membres sains **avant** ; (2) **un seul** nœud de contrôle hors service à tout moment : pendant tout l'exercice, ne touche ni à `k8s-cp01` ni à `k8s-cp03` ; (3) la commande `etcdctl member remove` vise un identifiant : vérifie deux fois que c'est celui de `k8s-cp02` ; (4) `kubeadm reset` ne se lance que sur `k8s-cp02` (relis l'invite).

**Travail demandé**
1. **Avant.** Relève l'état de référence : leader etcd, porteur de la VIP (maître VRRP), titulaires des baux `kube-controller-manager` et `kube-scheduler`, pods présents sur `k8s-cp02`, état des serveurs de HAProxy. Si `k8s-cp02` n'est ni leader etcd ni maître VRRP, demande-toi s'il faut forcer ces rôles sur lui pour rendre l'essai plus instructif (et comment).
2. **Panne.** Lance les mesures, coupe `k8s-cp02`. Pendant 10 minutes, note à la seconde près : la coupure éventuelle de l'API à travers la VIP, la bascule VRRP, l'élection etcd, les nouveaux titulaires des baux, le passage du nœud en `NotReady` (au bout de combien de temps, et pourquoi ce délai), les taints posés, ce qui arrive aux pods qui y tournaient et quand. Réponds : peut-on encore créer un Deployment ? Que dirait etcd si un second nœud tombait maintenant ?
3. **Retour.** Rallume `k8s-cp02`, observe son retour (rattrapage du membre etcd, ordre de retour des composants), et note la durée.
4. **Remplacement.** Considère maintenant que les données de `k8s-cp02` sont perdues. Dans l'ordre : arrête son plan de contrôle et son etcd, retire son membre etcd depuis un autre nœud, drainer puis supprimer l'objet `Node`, `kubeadm reset` sur `k8s-cp02` (et le nettoyage qu'il ne fait pas), puis nouvelle jonction comme nœud de contrôle. Observe l'arrivée du nouveau membre (statut d'apprenant, puis membre votant). Vérifie que la minuterie d'instantanés, l'audit et le chiffrement fonctionnent de nouveau sur ce nœud.
5. **Documentation.** RB-144 (diagnostic : redémarrer ou remplacer ? ; remplacement pas à pas ; vérifications ; et la limite : deux membres perdus → RB-141) et le compte rendu chronométré.

**Critères de réussite**
- [ ] etcd compte exactement trois membres (`k8s-cp01`, `k8s-cp02`, `k8s-cp03`), tous démarrés, votants et sains ; le membre de `k8s-cp02` est **nouveau** (créé après celui de `k8s-cp01`).
- [ ] Le nœud `k8s-cp02` est `Ready`, recréé lors de la nouvelle jonction ; ses pods statiques (etcd, serveur d'API avec audit et chiffrement, gestionnaire de contrôleurs, ordonnanceur) tournent.
- [ ] Les trois serveurs d'API répondent sur leur port 6443 et la VIP sur 8443 ; la minuterie `etcd-instantane.timer` de `k8s-cp02` a réussi un passage depuis la jonction.
- [ ] RB-144 et le compte rendu chronométré sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 14 29`

<details><summary>Indice 1</summary>

Les baux d'élection sont des objets `Lease` de `kube-system`. Le délai avant `NotReady` dépend d'une option du gestionnaire de contrôleurs (période de grâce de surveillance des nœuds), le délai d'éviction des pods des tolérances `not-ready`/`unreachable` que l'admission ajoute à chaque pod : lis les valeurs par défaut de ta version.
</details>

<details><summary>Indice 2</summary>

Retirer un membre etcd **avant** qu'il ne soit arrêté le fait redémarrer dans un cluster qui ne le connaît plus : arrête d'abord son pod statique. `kubeadm reset` sur un nœud de contrôle essaie lui-même de retirer le membre local : lis ce qu'il affiche quand c'est déjà fait. Il ne nettoie ni la configuration CNI, ni les règles du pare-feu du nœud, ni les fichiers que tes rôles ont posés.
</details>

<details><summary>Indice 3</summary>

Les certificats partagés du plan de contrôle sont déposés chiffrés dans le cluster pour deux heures par `kubeadm init phase upload-certs --upload-certs`, qui affiche la clé à passer à la jonction ; `kubeadm token create --print-join-command` donne le reste. Depuis quelques versions, kubeadm ajoute un nouveau membre etcd comme **apprenant** avant de le promouvoir.
</details>

**Pour aller plus loin** (facultatif) : remplacer `k8s-cp02` par une VM **reconstruite** depuis le code (`tofu apply -replace`, même nom, même adresse, même MAC) ; passer à cinq membres etcd (et ce que ça coûte) ; [Operating etcd — Replacing a failed member](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#replacing-a-failed-etcd-member), [Creating HA clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/).

---

### M14-E30 — Politique de cycle de vie des versions Kubernetes  `RED` `★★`

> **Ticket PLAT-1530** — *De : Claire Morel*
> La montée en 1.36 s'est bien passée, mais elle a été décidée parce que j'ai vu passer une date de fin de support. Je ne veux plus que nos montées de version dépendent de ce que je lis par hasard. Écris-moi une politique : quand on monte, jusqu'où, à quel rythme, avec quelles vérifications, et qui décide.

**Objectifs pédagogiques**
- Connaître le cycle de vie des versions de Kubernetes (trois mineures maintenues, environ quatorze mois de correctifs, une mineure tous les quatre mois environ) et la politique de décalage.
- Tenir compte de l'écosystème : une mineure n'est utilisable que si les composants dont on dépend la supportent.
- Rédiger une ADR et en tirer un calendrier.

**Prérequis** : M14-E25 (montée de version), lecture de *Kubernetes Release Cycle* et *Version Skew Policy*.
**Durée indicative** : 2 h.

**Travail demandé**

Rédige `docs/kubernetes/adr/ADR-0141-cycle-de-vie-des-versions.md` (gabarit d'ADR du socle) :
1. **Contexte** : fenêtre de support des mineures 1.35, 1.36, 1.37 (dates de fin à relever sur la page officielle), la 1.37 sortie en août 2026, les composants dont `k8s-par1` dépend ou dépendra (Cilium 1.20, cert-manager 1.21, ceph-csi 3.18, CloudNativePG 1.30, Velero 1.18, Helm 4, metrics-server, et Cluster API/CAPMOX au M18) avec les mineures que chacun annonce supporter.
2. **Options** comparées : suivre la dernière mineure dès sa sortie ; rester à N-1 (une mineure de retard sur la dernière) ; monter seulement quand la fin de support approche ; et ta proposition.
3. **Décision** : position cible (N-1 ? N ?), délai maximal après une sortie, rythme des correctifs (dans quel délai, et l'exception pour une faille critique), condition « écosystème » (qui vérifie quoi avant de déclarer une mineure utilisable), environnement d'essai (une montée se joue d'abord où ?), interdiction de sauter une mineure et conséquence en cas de retard.
4. **Conséquences** : calendrier des 18 prochains mois (dates prévues des montées 1.37 et 1.38 sous conditions), charge de travail, ce qui bloque aujourd'hui la 1.37, outillage nécessaire (veille des versions par Renovate au M13, playbook E25, RB-142).
5. **Responsabilités** et révision de la politique.

**Critères de réussite**
- [ ] L'ADR respecte le gabarit (contexte, options, décision, conséquences, statut) et cite ses sources (pages officielles, notes de compatibilité des composants), avec leur date de lecture.
- [ ] La décision est vérifiable : des délais chiffrés, une règle d'écosystème écrite comme une liste de contrôle, un calendrier.
- [ ] La 1.37 est traitée explicitement : ce qui manque pour la déclarer utilisable, et qui le vérifie.

<details><summary>Indice 1</summary>

La page *Releases* de kubernetes.io donne pour chaque mineure la date de fin de maintenance ; la page *Version Skew Policy* dit de combien de mineures le kubelet peut être en retard et pourquoi kubectl peut être une mineure devant ou derrière. Une mineure « N-1 » est soutenue par l'amont presque aussi longtemps que N, mais pas tout à fait : calcule la marge.
</details>

<details><summary>Indice 2</summary>

Les fenêtres de compatibilité de l'écosystème se lisent dans la page *requirements* de Cilium, la page *supported releases* de cert-manager et de CloudNativePG, le README de ceph-csi, la matrice de compatibilité de Velero et celle de Cluster API. Elles bougent à chaque version de ces composants : la politique doit dire **qui** les relit **quand**.
</details>

**Pour aller plus loin** (facultatif) : relie la politique aux images dorées (M03) et à Renovate (M13) : une montée de version du cluster comme une MR qui change une seule variable.

---

### M14-E31 — ADR : distribution et topologie de `k8s-par1`  `RED` `★★`

> **Ticket PLAT-1531** — *De : Karim Benali*
> On a construit `k8s-par1` avec kubeadm, etcd empilé, une VIP keepalived et HAProxy, trois et trois. C'était le choix du comité, pour apprendre. Maintenant qu'on l'a exploité (sauvegarde, montée de version, perte d'un nœud), je veux une ADR qui dise si on garde ce choix pour la production, ou ce qu'on changerait, chiffres et retours d'expérience à l'appui.

**Objectifs pédagogiques**
- Comparer des distributions et des topologies de Kubernetes sur des critères d'exploitation mesurés dans ce module.
- Argumenter un choix à partir de l'expérience (temps passé, incidents, risques) et non d'une liste de fonctionnalités.

**Prérequis** : M14-E24 à E29 ; lecture de la page kubeadm *Options for Highly Available topology* et de la documentation de présentation de RKE2 et de Talos (le module 18 les pratique).
**Durée indicative** : 2 h.

**Travail demandé**

Rédige `docs/kubernetes/adr/ADR-0140-distribution-et-topologie.md` :
1. **Contexte** : exigences (HDS, souveraineté, compétence de l'équipe, taille actuelle et prévue du parc, budget mémoire du lab), ce que le module a coûté (durées mesurées en E24, E25, E26, E29 : reprends tes comptes rendus).
2. **Options** sur quatre axes, chacun avec avantages, inconvénients et risque principal : **distribution** (kubeadm, RKE2, Talos, k3s ; une distribution commerciale à titre de comparaison) ; **etcd** (empilé ou externe) ; **point d'accès de l'API** (keepalived + HAProxy sur les nœuds de contrôle, kube-vip, répartiteurs externes `lb01`/`lb02`) ; **taille** (3 + 3 ; 3 + N ; 5 nœuds de contrôle ; nœuds de contrôle qui portent aussi des charges).
3. **Décision** et **conséquences** (ce qui change ou non dans `plateforme/k8s`, effort de migration éventuel, ce qu'il faudrait mesurer au M18 pour réviser l'ADR).

**Critères de réussite**
- [ ] Chaque option est évaluée sur les mêmes critères (installation, montée de version, sauvegarde/restauration, sécurité par défaut, surface d'administration, compétences, dépendance à un éditeur).
- [ ] La décision s'appuie sur au moins trois mesures ou incidents réels du module, cités.
- [ ] Les conséquences disent ce qui sera revu au M18 (distributions) et à quelle condition l'ADR serait remplacée.

<details><summary>Indice 1</summary>

etcd empilé : moins de machines, mais la perte d'un nœud de contrôle retire à la fois un serveur d'API et un membre etcd. etcd externe : couplage réduit, mais trois VMs de plus, leurs certificats, leurs sauvegardes et leurs montées de version. Pose la question en mémoire disponible sur `pve01` et en nombre d'objets à maintenir.
</details>

<details><summary>Indice 2</summary>

Pour le point d'accès, relis E03 et E29 : qu'est-ce qui a basculé, en combien de temps, et qu'est-ce qui aurait été différent avec une VIP portée par un pod statique (kube-vip, et le contournement `super-admin.conf` qu'il exige à l'amorçage) ou par les répartiteurs de la DMZ (flux à ouvrir, dépendance à une autre équipe) ?
</details>

---

### M14-E32 — Questions de production : Kubernetes  `Q` `★★★`

> **Ticket PLAT-1532** — *De : Karim Benali*
> Avant de te mettre d'astreinte sur `k8s-par1`, je veux t'entendre sur ces questions. Argumente, chiffre quand c'est possible, et dis de quoi dépend le « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur le comportement en production d'un cluster kubeadm : etcd, versions, certificats, audit, chiffrement, pannes du plan de contrôle.
- Relier les choix du module à des risques concrets.

**Prérequis** : paliers 1 et 2, M14-E24 à E31.
**Durée indicative** : 1 h 30.

**Questions**

1. Le cluster a trois membres etcd. Combien peut-on en perdre sans perdre les écritures ? Et avec quatre membres ? Pourquoi ne recommande-t-on jamais un nombre pair ? Qu'est-ce qui continue de fonctionner (pods existants, Services, DNS du cluster) quand etcd a perdu son quorum ?
2. QCM — Deux nœuds de contrôle sur trois sont définitivement perdus (disques détruits). Le troisième tourne. Que fais-tu ?
   a) `etcdctl member remove` des deux membres perdus depuis le troisième, puis nouvelles jonctions ;
   b) restauration depuis un instantané (RB-141), cluster etcd neuf, puis nouvelles jonctions ;
   c) redémarrage d'etcd sur le survivant avec `--force-new-cluster`, puis nouvelles jonctions ;
   d) restauration des deux VMs depuis PBS.
   Justifie, et dis laquelle des réponses fausses est **parfois** une option, à quelle condition et avec quel risque.
3. Ton instantané etcd horaire tourne depuis trois mois, et la sonde est verte. Qu'est-ce qui pourrait quand même rendre ta restauration impossible le jour J ? Donne au moins quatre causes, et pour chacune le contrôle qui l'aurait détectée.
4. Pendant une restauration, tu oublies `--bump-revision` et `--mark-compacted`. Le cluster redémarre et semble sain. Quels symptômes peux-tu voir dans les heures qui suivent, et chez quels composants ?
5. QCM — Pendant `kubeadm upgrade apply v1.36.5` sur `k8s-cp01`, la VM s'arrête brutalement au milieu. Au redémarrage :
   a) le cluster est perdu, il faut restaurer etcd ;
   b) tu relances `kubeadm upgrade apply v1.36.5` : la commande est idempotente ;
   c) tu dois d'abord redescendre `kubeadm` en 1.35 ;
   d) tu restaures les manifestes depuis `/etc/kubernetes/tmp/` puis tu continues avec `upgrade node`.
   Justifie, et dis à quoi sert `/etc/kubernetes/tmp/` dans ce cas.
6. Le cluster est en 1.36 sur le plan de contrôle et deux travailleurs, le troisième travailleur est resté en 1.35 depuis deux mois parce que son drain bloquait. Est-ce supporté ? Jusqu'à quand ? Que se passe-t-il à la montée en 1.37 du plan de contrôle ?
7. Pourquoi faut-il drainer un nœud avant de changer la **mineure** de son kubelet, alors qu'un changement de correctif s'en passe souvent ? Que devient un pod non géré par un contrôleur pendant un `kubectl drain` ?
8. Un dimanche matin, plus rien ne répond : `kubectl` renvoie `x509: certificate has expired or is not yet valid`. Le cluster a 13 mois et n'a jamais été mis à jour. Décris ta démarche, dans l'ordre, nœud par nœud, et ce qui se passe pour les kubelets.
9. QCM — Tu as activé `serverTLSBootstrap` et tu n'approuves pas les demandes. Que se passe-t-il ?
   a) les kubelets refusent de démarrer ;
   b) `kubectl logs` et `kubectl exec` échouent sur ces nœuds ;
   c) les kubelets gardent leur certificat auto-signé et tout continue ;
   d) le port 10250 n'a plus de certificat de service ; ce qui s'y connecte en TLS échoue (metrics-server, `kubectl logs`, `exec`), mais le kubelet et les pods tournent.
   Justifie.
10. La politique d'audit met tout en `RequestResponse`. Cite trois conséquences concrètes, dont au moins une de sécurité et une de disponibilité.
11. Un attaquant a obtenu une copie de `/var/lib/etcd` de `k8s-cp01` (copie du disque). Les Secrets sont chiffrés par `secretbox`. Peut-il les lire ? Et s'il a obtenu la sauvegarde PBS **entière** de la VM ? Et s'il a un compte avec `get secrets` sur un espace ? Que conclus-tu sur l'intérêt de KMS ?
12. QCM — Tu fais tourner la clé de chiffrement et tu supprimes l'ancienne clé de la configuration **avant** d'avoir réécrit les Secrets. Que se passe-t-il ?
    a) rien, les Secrets sont réécrits automatiquement avec la nouvelle clé ;
    b) les Secrets chiffrés avec l'ancienne clé deviennent illisibles par l'API (erreurs à la lecture, échecs des pods qui les montent) ;
    c) le serveur d'API refuse de démarrer ;
    d) les Secrets sont lus en clair grâce au fournisseur `identity`.
    Justifie, et dis comment tu t'en sors.
13. Pourquoi la VIP de l'API et HAProxy tournent-ils sur les nœuds de contrôle eux-mêmes, et pourquoi HAProxy écoute-t-il sur 8443 et non 6443 ? Que se passe-t-il si keepalived bascule la VIP vers un nœud dont le serveur d'API est arrêté ?
14. Un collègue propose de passer `k8s-par1` à cinq nœuds de contrôle « pour être plus sûr ». Qu'est-ce que cela change pour la tolérance, la latence d'écriture, la mémoire du lab, la durée d'une montée de version ? Dans quel cas l'accepterais-tu ?

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 14 questions, en chiffrant quand c'est possible et en justifiant chaque QCM (y compris pourquoi les autres options sont fausses).
- [ ] Au moins cinq réponses s'appuient sur une mesure ou un compte rendu de ce palier (E24 à E29).
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) avec le corrigé et listé les notions à revoir avant l'astreinte.

<details><summary>Indice 1</summary>

Pour etcd, raisonne en majorité stricte : combien de membres doivent répondre pour qu'une écriture soit validée, et combien de pannes cela laisse. Pour une restauration, distingue ce qui manque à l'**instantané** de ce qui manque au **cluster** autour (certificats, clés, versions).
</details>

<details><summary>Indice 2</summary>

Pour les certificats et le chiffrement, demande-toi à chaque fois : qui détient la clé, qui la lit au démarrage, et que se passe-t-il pour un composant qui a gardé l'ancienne en mémoire.
</details>

Les réponses argumentées sont dans le corrigé.

---

### M14-E33 — Accueillir une équipe sur le cluster  `LIBRE` `★★★`

> **Ticket DEV-1533** — *De : Claire Morel* — *Copie : Sophie Laurent*
> L'équipe MédiDoc (stockage de documents médicaux, service Go) passe sur Kubernetes au module 16. Elle a besoin dès maintenant de son espace de développement sur `k8s-par1`, avec les mêmes règles que MédiAgenda — et je veux que l'accueil d'une équipe devienne une procédure, pas une semaine d'allers-retours. Sophie veut que l'équipe ne puisse rien voir ni rien casser en dehors de chez elle.

**Objectifs pédagogiques**
- Concevoir et livrer, par le code, un espace d'équipe complet et cloisonné.
- Transformer l'accueil en procédure reproductible (gabarit, documentation, vérifications).

**Prérequis** : M14-E10 à E13, E18, E19 ; M14-E27 (l'audit trace les actions de l'équipe).
**Durée indicative** : 4 h.

**Contexte technique**
- Équipe : groupe Kubernetes **`medisphere:medidoc-devs`** (certificats clients émis par l'API CSR comme en E12, un premier compte pour le référent de l'équipe, à toi de le nommer selon la convention `prenom.nom`) ; projet GitLab `medidoc/medidoc` (M12) ; images dans le projet Harbor `medisphere` (`registry.par1.medisphere.internal/medisphere/medidoc:<version>`).
- Espace : **`medidoc-dev`**. Enveloppe accordée par Claire : 2 vCPU et 4 Gio demandés au plus, 4 vCPU et 8 Gio en limites, 20 pods, aucun Service `LoadBalancer` ni `NodePort` (la publication arrive au M15).
- MédiDoc a besoin de lire ses propres Secrets et de créer des Deployments, Services, ConfigMaps, Secrets, Jobs et CronJobs dans son espace ; elle ne doit ni modifier ses quotas, ni ses rôles, ni les étiquettes de son espace.

**Contraintes**
- Tout est dans `plateforme/k8s` (`espaces/`, `rbac/`, `admission/` si besoin), appliqué par `task appliquer` après MR ; aucune création à la main.
- Les règles d'admission de E18 (Pod Security `restricted`, registre imposé, pas d'étiquette `latest`) s'appliquent à `medidoc-dev` sans modifier les politiques existantes, seulement par la façon dont l'espace est décrit.
- Les images se tirent par le robot `robot$k8s-pull` (E19), sans que l'équipe ait à le configurer dans ses manifestes.
- Le kubeconfig remis au référent : certificat court (même politique que E12), point d'accès par la VIP, aucun droit hors de son espace sauf la lecture de ce qui lui est utile (lesquels ? à justifier).
- La procédure d'accueil est générique : accueillir une troisième équipe ne demande que de remplir un gabarit.

**Critères de réussite**
- [ ] `medidoc-dev` existe avec un ResourceQuota conforme à l'enveloppe et un LimitRange qui donne des valeurs par défaut ; Pod Security `restricted` y est appliqué en `enforce`.
- [ ] Une ValidatingAdmissionPolicyBinding existante s'applique à `medidoc-dev` ; un pod qui viole une des règles y est refusé (essai consigné).
- [ ] Le groupe `medisphere:medidoc-devs` a un RoleBinding dans `medidoc-dev` et aucun droit en écriture ailleurs ; il ne peut ni modifier le ResourceQuota ni créer de RoleBinding (essais `kubectl auth can-i --as … --as-group …` consignés).
- [ ] Le compte de service `default` de `medidoc-dev` tire les images par le Secret du robot ; un pod de test MédiDoc démarre.
- [ ] La description de l'espace est sur `main` de `plateforme/k8s` ; la procédure d'accueil (`docs/kubernetes/accueil-equipe.md`) et la fiche de l'équipe (`docs/kubernetes/equipes/medidoc.md`) sont sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 14 33`

<details><summary>Indice 1</summary>

Une politique d'admission ne s'applique qu'aux espaces que sa liaison sélectionne : relis comment tes liaisons de E18 choisissent leurs espaces (étiquettes ? noms ?) et décris `medidoc-dev` pour qu'il en fasse partie. Même raisonnement pour Pod Security : ce sont des étiquettes de l'espace — et qui peut les modifier ?
</details>

<details><summary>Indice 2</summary>

Les rôles intégrés `edit` et `view` sont des ClusterRoles agrégés : `edit` dans un RoleBinding ne donne de droits que dans cet espace, mais regarde ce qu'il contient (les ResourceQuota ? les RoleBindings ? les Secrets ?) avant de le choisir plutôt qu'un rôle à toi.
</details>

**Pour aller plus loin** (facultatif) : un gabarit d'espace par Kustomize (M17) ou par un chart ; l'accueil en libre-service par MR sur un registre des équipes, appliqué par GitOps (M20).

---

### M14-E34 — Examen blanc d'administration  `CHRONO` `★★★`

> **Ticket PLAT-1534** — *De : Claire Morel*
> Tu vas prendre l'astreinte de `k8s-par1`. Avant, je veux te voir enchaîner des gestes d'administration courants, vite et juste, sans filet. Deux heures, quatorze tâches, sur le vrai cluster.

**Objectifs pédagogiques**
- Enchaîner sous contrainte de temps les gestes d'administration du module (objets, ordonnancement, RBAC, nœuds, etcd), sans corrigé.
- Mesurer tes gestes lents ou hésitants et en tirer un plan de travail.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **tes** runbooks et la documentation officielle de Kubernetes (kubernetes.io, etcd.io), comme à l'examen CKA. `kubectl explain`, `--help` et `--dry-run=client -o yaml` sont tes amis.
- Durée : **2 h** entre l'ouverture du sujet (T0) et la fin (T1). Chaque tâche a un poids ; on vise 70 % des points.
- Ici, les commandes manuelles sont **permises** (c'est un examen de gestes, pas de code) : tout ce que tu crées vit dans l'espace `wb-examen` et sur les objets nommés par le sujet, et sera supprimé à la fin.
- Avant T0 : instantané etcd vérifié, cluster sain (`lab/bin/check 14 25` vert).

**Prérequis** : paliers 1 à 3 du module.
**Durée** : 2 h chronométrées + 30 minutes de retour d'expérience.

**Sujet** : [`ressources/E34-examen-blanc/sujet.md`](../ressources/E34-examen-blanc/sujet.md) (quatorze tâches, leur poids et le barème) et le manifeste fourni [`ressources/E34-examen-blanc/rdv-examen.yaml`](../ressources/E34-examen-blanc/rdv-examen.yaml). Lis le sujet à T0, pas avant.

**Critères de réussite**
- [ ] `lab/bin/check 14 34`, lancé à T1, valide au moins 70 % des points (le script affiche le score par tâche).
- [ ] La feuille de temps du sujet est remplie (heure de fin de chaque tâche), avec les tâches abandonnées et pourquoi.
- [ ] Le retour d'expérience (une demi-page dans `docs/kubernetes/tests/examen-blanc.md`) liste les gestes lents ou hésitants et ce que tu vas travailler ; puis le nettoyage demandé en fin de sujet est fait.

**Vérification** : `lab/bin/check 14 34` (à lancer à T1, **avant** le nettoyage).

**Pour aller plus loin** (facultatif) : refais l'examen une semaine plus tard en visant 1 h 15 ; ajoute deux tâches de ton cru et le contrôle qui les vérifie.
