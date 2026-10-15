# Module 14 — Palier 1 : Découverte

Avant le premier `kubectl apply`, il faut des machines prêtes, un point d'accès qui survive à la perte d'un nœud et un cluster dont tu connais chaque fichier. Ce palier crée les six nœuds par le code et les prépare pour kubeadm, monte la VIP de l'API avec keepalived et HAProxy, amorce le cluster **à la main** pour lire ce que kubeadm écrit, joint les autres nœuds, installe Cilium, puis laisse Ansible rejouer le tout sans rien changer. Il te donne ensuite une identité personnelle, crée le compte des vérifications, et déploie MédiAgenda dans un espace d'essai avec sa configuration, ses sondes et ses ressources. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : modules 12 et 13 terminés (`lab/bin/check 13 25` vert : image signée de MédiAgenda dans Harbor, robot `robot$k8s-pull`) ; module 07 (rôles `keepalived` et `haproxy`, bordure) ; modules 03 à 06 (image dorée Debian `current`, rôles et Molecule, OpenTofu et NetBox, PKI, DNS). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les règles du module.

---

### M14-E01 — Test de positionnement : Kubernetes  `Q` `★★`

> **Ticket PLAT-1501** — *De : Karim Benali*
> Le rituel : une heure, par écrit, sans moteur de recherche ni IA, sans rien exécuter. Conteneurs, réseau, PKI, systèmes distribués, et ce que tu crois savoir de Kubernetes parce que tu as lu un article. Réponds même là où tu hésites : je regarde le raisonnement, pas la note.

**Objectifs pédagogiques**
- Évaluer tes acquis sur ce que Kubernetes suppose (conteneurs, réseau Linux, TLS, consensus) avant de l'installer.
- Repérer les notions à travailler et les exercices du module qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Conteneurs et Linux*

1. Un conteneur est « un processus avec des espaces de noms et des cgroups ». Cite quatre espaces de noms Linux et ce que chacun isole. Que limitent les cgroups ?

2. *(QCM)* Deux conteneurs d'un même pod Kubernetes peuvent se parler par `localhost`. Pourquoi ?
   - A. Kubernetes ajoute une route vers `127.0.0.1` dans chaque conteneur
   - B. Ils partagent le même espace de noms réseau, tenu par un conteneur du pod qui ne fait rien d'autre
   - C. Le kubelet relaie le trafic entre eux
   - D. Ils sont dans le même cgroup

3. Qu'est-ce que l'interface **CRI** ? Pourquoi Kubernetes a-t-il cessé de parler directement à Docker (« dockershim », 1.24) ?

4. Que se passe-t-il, côté noyau, quand un conteneur dépasse sa limite de mémoire ? Et sa limite de CPU ? Pourquoi la réponse n'est-elle pas la même ?

5. Le kubelet et le runtime doivent utiliser le **même pilote de cgroups** (`systemd` ou `cgroupfs`). Que risque-t-on s'ils diffèrent ?

*Réseau*

6. Un nœud Linux doit avoir `net.ipv4.ip_forward = 1` pour héberger des pods. Pourquoi ? À quoi sert le module `br_netfilter` ?

7. Un **Service** de type ClusterIP a l'adresse 10.96.12.7. Aucune interface du cluster ne porte cette adresse. Comment un paquet envoyé à 10.96.12.7:80 arrive-t-il pourtant à un pod ?

8. *(QCM)* Les pods de deux nœuds différents doivent se joindre par leurs adresses (10.240.x.y). Le réseau physique des nœuds (VLAN 40) ne connaît pas ces adresses. Quelle solution ne fonctionne **pas** ?
   - A. Encapsuler les paquets entre nœuds (VXLAN, Geneve)
   - B. Annoncer les réseaux des pods aux routeurs (BGP)
   - C. Ajouter sur chaque nœud une route statique vers le réseau de pods de chaque autre nœud, quand tous les nœuds sont sur le même segment
   - D. Faire du NAT source sur l'adresse du nœud pour tout le trafic entre pods

9. Pourquoi un résolveur DNS qui a `options ndots:5` et cinq domaines de recherche peut-il envoyer six requêtes pour résoudre `api.exemple.com` ?

*TLS et PKI*

10. Un client TLS se connecte à `https://k8s-api.par1.medisphere.internal:8443`. Qu'est-ce qui doit figurer dans le certificat du serveur pour que la vérification réussisse ? Et si le client se connecte par l'adresse IP ?

11. Qu'est-ce qu'une **authentification mutuelle** TLS ? Dans un certificat client, où un serveur peut-il lire un nom d'utilisateur et des groupes ?

12. *(QCM)* Un certificat client valable un an a fuité. On veut l'invalider tout de suite. Sans infrastructure de révocation (CRL, OCSP) côté serveur, que peut-on faire ?
    - A. Le supprimer du poste de l'utilisateur
    - B. Rien qui l'invalide, sinon changer l'autorité qui l'a signé (ou attendre son expiration) ; on peut seulement retirer les droits liés à ce qu'il contient
    - C. Le renouveler : l'ancien devient invalide
    - D. Changer la clé privée du serveur

13. Pourquoi des certificats **courts** (quelques jours) sont-ils souvent préférés à une infrastructure de révocation ?

*Systèmes distribués*

14. etcd utilise **Raft**. Avec 3 membres, combien peuvent tomber sans perte d'écriture ? Avec 4 ? Avec 5 ? Pourquoi ne déploie-t-on jamais 2 membres ?

15. Que veut dire, pour une API, être **déclarative** plutôt qu'impérative ? Donne un exemple de chacune.

16. *(QCM)* Trois instances d'un même contrôleur tournent pour la haute disponibilité. Comment éviter qu'elles agissent toutes les trois en même temps sur les mêmes objets ?
    - A. Chacune traite un tiers des objets, tiré au hasard
    - B. Une élection : une seule détient un bail (renouvelé régulièrement), les autres attendent qu'il expire
    - C. Elles agissent toutes, les conflits sont résolus par etcd
    - D. Une seule est démarrée, les autres sont arrêtées par systemd

17. Une VIP (VRRP) devant trois serveurs d'API : qu'est-ce qui se passe pour les connexions TCP déjà ouvertes quand la VIP change de nœud ? Qu'est-ce qui doit se passer côté client ?

*Kubernetes, ce que tu en sais*

18. Cite les composants d'un nœud de contrôle et ceux d'un nœud de travail, avec une phrase sur le rôle de chacun.

19. Quelle est la différence entre un **Pod**, un **ReplicaSet** et un **Deployment** ? Pourquoi ne crée-t-on presque jamais de Pod directement ?

20. Un collègue écrit dans un ticket : « j'ai mis `latest` sur l'image et `imagePullPolicy: Always`, comme ça on a toujours la dernière version ». Donne trois raisons de refuser.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions de réseau, suis un paquet : d'où part-il, quelle adresse de destination porte-t-il, qui le transforme (règle netfilter, encapsulation) et à quel moment.
</details>

<details><summary>Indice 2</summary>

Pour les questions de systèmes distribués, raisonne sur la panne : qui doit être d'accord pour qu'une écriture soit acceptée, et que se passe-t-il quand la moitié du cluster ne voit plus l'autre ?
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M14-E46), sans relire le corrigé, et compare.

---

### M14-E02 — Préparer les nœuds  `LAB` `★★`

> **Ticket PLAT-1502** — *De : Karim Benali* — *Copie : Claire Morel*
> Six nœuds pour `k8s-par1` : trois de contrôle, trois de travail, Debian 13, notre image dorée. Les VMs par OpenTofu avec `vm-noeud`, dans un état à part. Côté système, prépare ce que kubeadm attend et rien de plus : un runtime **compatible** (le containerd de Debian ne l'est pas avec la 1.36 qu'on visera), des paquets Kubernetes **épinglés** à la version qu'on a choisie, pas de swap. Et je veux que la vérification soit celle de kubeadm lui-même, pas « ça a l'air bon ». Pas de `curl | sh`, pas de clé de dépôt prise sans vérifier son empreinte.

**Objectifs pédagogiques**
- Réutiliser un module OpenTofu existant pour un nouvel environnement, avec des adresses et des MAC imposées par le plan.
- Comprendre ce qu'un nœud doit offrir à kubeadm : runtime CRI, pilote de cgroups, image pause, modules et paramètres noyau, swap, paquets.
- Configurer containerd 2.3 pour Kubernetes et vérifier sa configuration **effective**.
- Épingler des versions de paquets (préférence APT, `apt-mark hold`) et vérifier les dépôts par empreinte de clé.
- Utiliser les contrôles préalables de kubeadm comme critère de réussite.

**Prérequis** : M13-E25 ; M10-E02 (module `vm-noeud` v2.3, MAC imposée) ; M06-E12 à E14 (NetBox, inventaire NetBox, noms DNS par OpenTofu) ; M04-E24 (Molecule) ; M03 (image dorée Debian `current`).
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VMs | voir le tableau « Hôtes du module » de l'introduction : `k8s-cp01-03` (2141-2143) et `k8s-w01-03` (2144-2146), pool `lab`, famille `debian13`, pas de démarrage automatique ; `k8s-w04` (2147) n'est **pas** créé maintenant (M14-E17) |
| Réseau | une seule carte, VNet `vk8s`, adresse imposée 10.10.40.5N ou .6N/24, passerelle 10.10.40.1, MAC `bc:24:11:40:00:<dernier octet>`, MTU 1500 ; résolveurs 10.10.20.10 et 10.10.20.16 ; noms `k8s-cp0N`, `k8s-w0N` (A et PTR) dans `par1.medisphere.internal` |
| Code | état `envs/k8s` de `plateforme/infra` (clé `envs/k8s/terraform.tfstate`), module `vm-noeud?ref=<VERSION-TOFU-MODULES>` ; une variable `avec_k8s_w04` (faux par défaut) prépare l'exercice E17 |
| NetBox | étiquettes `env-k8s`, `role-k8s-cp`, `role-k8s-worker` à ajouter au modèle (script de M06-E05) |
| Ansible | source d'inventaire `inventories/lab/netbox-k8s.yml` (étiquette `env-k8s`) produisant les groupes `k8s_par1`, `k8s_plan_controle`, `k8s_travailleurs` ; faits partagés dans `group_vars/k8s_par1/kubernetes.yml` (version, réseaux, point d'accès, table des nœuds) ; rôles `containerd` et `k8s_noeud` ; playbook `playbooks/k8s-noeuds.yml` ; scénario Molecule `k8s_noeud`, instance 2149 |
| Runtime | paquet `containerd.io` **2.3.x** du dépôt `https://download.docker.com/linux/debian` (suite `trixie`, composant `stable`), clé `https://download.docker.com/linux/debian/gpg`, empreinte `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88` ; `config.toml` géré par le rôle |
| Kubernetes | `kubelet`, `kubeadm`, `kubectl` en **1.35.9-1.1**, dépôt `https://pkgs.k8s.io/core:/stable:/v1.35/deb/`, clé `Release.key` du même dossier, empreinte `DE15 B144 86CD 377B 9E87 6E1A 2346 54DA 9A29 6436` |

**Travail demandé**

*A. Avant d'écrire*

1. Lis les pages « Installing kubeadm » et « Container Runtimes » de la documentation de Kubernetes (liens dans l'introduction). Note dans ton journal ce que kubeadm attend d'un nœud, et pour chaque point qui le fournira (image dorée, rôle commun, nouveau rôle).
2. Sur une VM d'essai (2140, clone lié de l'image `current`, détruite ensuite), regarde ce que Debian 13 propose : `apt-cache policy containerd runc`. Compare avec la page des versions de containerd prises en charge par Kubernetes (`RELEASES.md` de containerd). Note la conclusion.
3. Ajoute les trois étiquettes au modèle NetBox.

*B. Les VMs*

4. Écris l'environnement `envs/k8s` : versions et *backend*, fournisseurs, variables, `noeuds.tf` (six nœuds par une table, plan de contrôle et travailleurs avec leurs gabarits), `dns.tf`. Une seule règle pour déduire adresse et MAC du nom : écris-la en commentaire, elle servira aussi à l'inventaire Ansible. Lis le plan, puis `apply` par le pipeline de `plateforme/infra`.
5. Sur `pve01`, lis `qm config 2141` : retrouve la MAC, le VNet, la description posée par le module. Dans un nœud, `ip -br addr` : comment s'appelle la carte, et qui lui a donné ce nom ?

*C. Ansible*

6. Ajoute la source d'inventaire et les groupes. Pourquoi ne pas réutiliser les groupes produits automatiquement par les étiquettes (`role_k8s_cp`…) ? Contrôle : `uv run ansible-inventory --graph k8s_par1`.
7. Écris les faits partagés du cluster (`group_vars/k8s_par1/kubernetes.yml`) : nom, version complète, révision des paquets, image pause attendue par kubeadm, point d'accès (nom, VIP, ports, VRID), réseaux des pods et des services, interface, table des nœuds (adresse ; priorité VRRP pour les nœuds de contrôle). Comment connais-tu l'image pause attendue par kubeadm 1.35.9 sans avoir encore installé kubeadm ?
8. Écris le rôle **`containerd`**. Exigences :
   - refus de tout autre système que Debian 13 ; dépôt Docker en format deb822, clé importée **seulement** si son empreinte est la bonne ; paquets `containerd` et `runc` de Debian absents ;
   - `containerd.io` limité à la branche 2.3 par une **préférence APT** (les correctifs 2.3.x passent, pas une 2.4) ;
   - `/etc/containerd/config.toml` possédé par le rôle, **validé avant d'être posé**, ne contenant que ce qui diffère des défauts : greffon CRI actif, `SystemdCgroup = true` pour runc, image du bac à sable épinglée, dossier des `hosts.toml` déclaré (les miroirs viendront en E19 : prévois une variable, vide pour l'instant) ;
   - `/etc/crictl.yaml` ; service actif ; un contrôle final qui lit la configuration **effective** de containerd et la compare à l'inventaire.
   Lis le fichier `config.toml` livré par le paquet `containerd.io` avant de l'écraser : qu'est-ce qui le rend inutilisable par le kubelet ? Quelle version de schéma attend containerd 2.3 (`containerd config default | head -1`) ?
9. Écris le rôle **`k8s_noeud`**. Exigences :
   - refus de tout autre système que Debian 13, d'un nom d'hôte différent du nom d'inventaire, d'un nœud en cgroup v1 ;
   - swap désactivé et neutralisé dans `/etc/fstab` ; modules `overlay` et `br_netfilter` chargés et déclarés au démarrage ; `net.ipv4.ip_forward` et `net.bridge.bridge-nf-call-iptables` à 1, persistants ;
   - dépôt `pkgs.k8s.io` **de la mineure** (pourquoi pas un dépôt unique ?), clé vérifiée par son empreinte ; `kubelet`, `kubeadm`, `kubectl` à la version exacte, puis retenus (`apt-mark hold`) ; `kubelet` activé ;
   - un **garde-fou** : sur un nœud déjà membre d'un cluster, le rôle refuse de changer la version des paquets, sauf autorisation explicite (variable) ;
   - deux contrôles pour finir : l'image pause de containerd est celle que liste `kubeadm config images list` pour la version visée ; les **contrôles préalables de kubeadm** passent (`kubeadm init phase preflight`, sans rien modifier : cherche l'option dans `--help`), sur un nœud qui n'a pas encore rejoint de cluster.
10. Écris le scénario Molecule `k8s_noeud` (instance 2149, 2 vCPU, 2 Go) qui applique les deux rôles et vérifie de l'extérieur : versions et états des paquets, configuration effective de containerd, swap, modules, contrôles préalables.
11. Écris `playbooks/k8s-noeuds.yml` : un garde-fou d'inventaire (chaque nœud dans la table du plan, adresse de connexion conforme, groupe cohérent avec l'étiquette), puis les rôles communs et les deux nouveaux rôles, **un nœud à la fois**. Pourquoi « un nœud à la fois » dès maintenant, alors que le cluster n'existe pas encore ? Applique-le ; second passage : `changed=0`.
12. Sur `k8s-cp01`, lance toi-même les contrôles préalables de kubeadm et lis chaque ligne, avertissements compris. Puis `sudo crictl info | jq .status` et `sudo containerd config dump | grep -nE 'SystemdCgroup|sandbox|config_path'`.
13. Mets à jour la matrice des flux (rien sur les passerelles : dis pourquoi) et le registre des secrets (rien de nouveau : dis pourquoi).

**Critères de réussite**
- [ ] Les VMs 2141-2146 sont créées par OpenTofu (`envs/k8s`, module `vm-noeud`), conformes au tableau des hôtes : nom, étiquettes, pool, vCPU, mémoire, disque, carte sur `vk8s` avec la MAC du plan, sans démarrage automatique.
- [ ] Les six noms sont résolus en A et PTR ; les six VMs sont actives dans NetBox avec leur IP primaire.
- [ ] Sur chaque nœud : Debian 13, nom d'hôte conforme, cgroup v2, pas de swap, modules et paramètres noyau en place, `containerd.io` 2.3.x épinglé, CRI actif avec cgroups systemd et l'image pause de kubeadm, `kubelet`/`kubeadm`/`kubectl` en 1.35.9-1.1 retenus, kubelet activé.
- [ ] Les contrôles préalables de kubeadm passent sur chaque nœud (avertissements lus et expliqués dans ton journal).
- [ ] `envs/k8s`, les rôles, le scénario Molecule, la source d'inventaire, les faits partagés et le playbook sont sur `main` ; un second passage du playbook donne `changed=0`.

**Vérification** : `lab/bin/check 14 02`

<details><summary>Indice 1</summary>

Le module `vm-noeud` v2.3 accepte une `mac` par carte. La configuration réseau de cloud-init générée par Proxmox **nomme** les cartes d'après leur ordre. Pour le dépôt de Kubernetes : regarde comment s'écrit un dépôt « plat » (sans composants) au format deb822 dans `man sources.list`. Pour la préférence APT : `man apt_preferences`, champ `Pin: version`.
</details>

<details><summary>Indice 2</summary>

`containerd --config <fichier> config dump` charge un fichier, le fusionne avec les défauts et l'affiche, sans démon : c'est un validateur tout trouvé pour l'option `validate` du module `template`. Les chemins des options du greffon CRI ont changé entre containerd 1.7 et 2.x : pars de `containerd config default`, pas d'un article de blog. Pour l'image pause, la liste des images d'une version de kubeadm se lit aussi avec le binaire `kubeadm` de cette version téléchargé seul sur `dl.k8s.io`.
</details>

<details><summary>Indice 3</summary>

Les filtres d'étiquettes de l'API NetBox se combinent en ET (M08-E02) : une source d'inventaire par environnement. Le greffon `netbox.netbox.nb_inventory` accepte les options « construites » d'Ansible (`compose`, `keyed_groups`, `groups`). Les contrôles préalables de kubeadm sans configuration demandent la dernière version stable à Internet : donne-leur un fichier minimal qui fixe la version.
</details>

**Pour aller plus loin** (facultatif) : compare avec la façon dont `kubespray` (le projet Ansible de la communauté) prépare un nœud : ce qu'il fait de plus, ce qu'il fait autrement.

---

### M14-E03 — Le point d'accès de l'API : keepalived et HAProxy  `LAB` `★★`

> **Ticket PLAT-1503** — *De : Claire Morel* — *Copie : Karim Benali, Nadia Roussel*
> Avant même d'amorcer le cluster, je veux son adresse définitive. Tout ce qui parlera à l'API, les kubelets compris, utilisera un **nom** qui ne désigne aucune machine en particulier : si `k8s-cp01` tombe, rien ne doit avoir à changer d'adresse. Reprends ce qu'on a fait pour les répartiteurs au module 07 : keepalived, HAProxy, les mêmes rôles, les mêmes conventions. Nadia veut pouvoir dire en une commande qui porte l'adresse.

**Objectifs pédagogiques**
- Comprendre pourquoi un cluster kubeadm hautement disponible exige un point d'accès stable **avant** l'amorçage (`controlPlaneEndpoint`).
- Réutiliser les rôles `keepalived` et `haproxy` du M07 depuis un rôle de plus haut niveau, avec des variables calculées.
- Configurer HAProxy en TCP (le TLS va jusqu'au kube-apiserver) et des contrôles de santé qui s'adaptent à l'état du nœud.
- Observer un point d'accès dont tous les serveurs sont en panne : ce qu'on voit, ce que le client reçoit.

**Prérequis** : M14-E02 ; M07-E12 (répartiteurs : VRRP unicast, sans préemption, `chk_haproxy`) ; M07-E28 (rôle `haproxy` de production).
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VIP | 10.10.40.200/24, nom `k8s-api.par1.medisphere.internal` (A seulement, TTL 300), adresse de rôle « vip » dans NetBox, déclarée dans `envs/k8s` (`api.tf`) |
| VRRP | keepalived, VRRP v3 **unicast**, VRID **140**, priorités `k8s-cp01` 150, `k8s-cp02` 120, `k8s-cp03` 100, tous en état initial BACKUP, **sans préemption**, interface du VLAN 40 ; script de suivi d'HAProxy |
| HAProxy | 3.2 (rôle `haproxy`, dépôt haproxy.debian.net) ; frontend `fe_k8s_api` sur **10.10.40.200:8443**, backend `be_k8s_api` vers 10.10.40.51-53:**6443**, mode TCP, répartition circulaire ; écoute sur la VIP même quand le nœud ne la porte pas |
| Rôle | `k8s_plan_controle`, première partie (étiquette Ansible `point_acces`) ; playbook `playbooks/k8s-cluster.yml` (groupe `k8s_plan_controle`, un nœud à la fois) |

**Travail demandé**

1. Lis, dans la documentation kubeadm, la page « Creating Highly Available Clusters with kubeadm » et le document « Options for Software Load Balancing » (introduction). Réponds dans ton journal : pourquoi `controlPlaneEndpoint` doit-il être fixé **dès** `kubeadm init` ? Pourquoi le port de la VIP diffère-t-il ici de 6443 ?
2. Ajoute `api.tf` à `envs/k8s` : l'adresse dans NetBox (rôle « vip », sans interface), le nom DNS **sans PTR**. Pourquoi pas de PTR ? Pipeline, puis `dig +short k8s-api.par1.medisphere.internal`.
3. Commence le rôle `k8s_plan_controle` : la partie « point d'accès » appelle les rôles `keepalived` et `haproxy` (`include_role`) avec des variables **calculées** à partir des faits partagés (les pairs VRRP d'un nœud sont les deux autres nœuds de contrôle ; une ligne `server` par nœud de contrôle). Exigences :
   - le frontend et le backend en mode **TCP**, avec des délais d'inactivité adaptés aux connexions longues de l'API (*watch*, `logs -f`, `exec`) ;
   - un contrôle de santé des backends qui **dépend de l'état du nœud** : tant que la CA du cluster n'existe pas sur le nœud, une simple connexion TCP ; dès qu'elle existe, une requête HTTPS `GET /readyz` dont le certificat est **vérifié** par cette CA (jamais `verify none`) ;
   - l'instance VRRP reprend les conventions du M07 (unicast, pas de préemption, suivi d'HAProxy).
   Que se passerait-il, à l'amorçage, si le contrôle de santé était tout de suite en HTTPS vérifié ?
4. Écris la première version de `playbooks/k8s-cluster.yml` : le rôle sur le groupe `k8s_plan_controle`, un nœud à la fois dans l'ordre, arrêt au premier échec ; puis un contrôle d'ensemble « une et une seule VIP portée ». Applique avec `--tags point_acces` (`--check --diff` d'abord).
5. Observe :
   ```
   admin@adm01:~$ for n in k8s-cp01 k8s-cp02 k8s-cp03; do echo "== $n"; ssh $n ip -br -4 addr show eth0; done
   admin@adm01:~$ ssh k8s-cp01 'echo "show stat" | sudo socat stdio unix-connect:/run/haproxy/admin.sock' | cut -d, -f1,2,18,37
   admin@adm01:~$ curl -v --max-time 5 https://k8s-api.par1.medisphere.internal:8443/
   ```
   Qui porte la VIP, et pourquoi lui ? Dans quel état sont les trois serveurs, et pourquoi ? Que répond `curl`, et à quelle étape la connexion échoue-t-elle (TCP, TLS, HTTP) ?
6. Teste la bascule.
   > ⚠️ **Attention** : n'arrête qu'un nœud à la fois, et relance-le avant de passer à la suite. Aucune charge ne tourne encore : c'est le meilleur moment pour ce test.
   Arrête HAProxy sur le nœud qui porte la VIP (`sudo systemctl stop haproxy`), observe la VIP partir (`journalctl -u keepalived -f` sur les trois nœuds), relance HAProxy : la VIP revient-elle ? Pourquoi ?
7. Documente : matrice des flux (VRRP, 6443, 8443 : ce qui traverse la bordure et ce qui ne la traverse pas), et une section « Point d'accès de l'API » dans ton brouillon de fiche du cluster (`~/m14/e03/`, elle deviendra `docs/kubernetes/cluster.md` en E05).

**Critères de réussite**
- [ ] `k8s-api.par1.medisphere.internal` résout 10.10.40.200 ; l'adresse est dans NetBox (rôle « vip »).
- [ ] Un et un seul nœud de contrôle porte la VIP ; `adm01` ouvre une connexion TCP vers 10.10.40.200:8443.
- [ ] Sur les trois nœuds : keepalived actif (VRID 140, unicast vers les deux autres, sans préemption, suivi d'HAProxy) ; HAProxy actif, configuration valide, écoute 10.10.40.200:8443 en mode TCP, trois serveurs déclarés vers :6443 et contrôlés.
- [ ] La bascule a été testée et le comportement (retour ou non de la VIP) expliqué dans ton journal.
- [ ] `api.tf`, la partie « point d'accès » du rôle et le playbook sont sur `main` ; la matrice des flux mentionne 8443.

**Vérification** : `lab/bin/check 14 03`

<details><summary>Indice 1</summary>

Au M07, les variables de `keepalived` et d'`haproxy` venaient de `group_vars/role_lb/`. Ici, un rôle les **fournit** : `include_role` accepte des `vars:` sur la tâche, et un `set_fact` peut construire une liste de lignes avant. Le rôle `haproxy` rend les sections telles quelles (`haproxy_sections`) : rien n'empêche une section `mode tcp` dans un fichier dont `defaults` est en `mode http`.
</details>

<details><summary>Indice 2</summary>

Dans HAProxy, un contrôle de santé HTTP sur un backend TCP s'écrit avec `option httpchk` et les directives `http-check` (`connect ssl`, `send`, `expect`) ; la vérification du certificat du serveur contrôlé se règle sur la ligne `server` ou `default-server` (`verify`, `ca-file`). `/readyz` du kube-apiserver est lisible sans authentification. Pour savoir si la CA existe, le module `stat` suffit.
</details>

<details><summary>Indice 3</summary>

Sans préemption, un nœud de priorité plus haute qui revient ne reprend pas la VIP : c'est le comportement voulu (M07-E12, ADR-0071). Pour savoir quel nœud la porte sans se connecter aux trois : `ip neigh` sur `adm01` après un `ping` de la VIP montre une MAC… que tu as choisie en E02.
</details>

**Pour aller plus loin** (facultatif) : kube-vip fait la même chose (VIP et répartition) en pod statique, sans keepalived ni HAProxy. Lis sa documentation « static pods » et note la difficulté qu'il pose à l'amorçage depuis Kubernetes 1.29 (`super-admin.conf`). Elle sera discutée dans l'ADR-0140 (M14-E31).

---

### M14-E04 — Amorcer le cluster avec kubeadm  `LAB` `★★`

> **Ticket PLAT-1504** — *De : Karim Benali* — *Copie : Sophie Laurent*
> On amorce `k8s-par1` sur `k8s-cp01`. À la main, une fois, parce que je veux que tu aies lu ce que kubeadm écrit avant de laisser Ansible le faire. La configuration vient d'un fichier relu en MR dans un nouveau projet `plateforme/k8s`, pas de drapeaux tapés au clavier.
>
> **Ticket SEC-1504** — *De : Sophie Laurent*
> kubeadm crée deux fichiers d'administrateur. L'un des deux donne `system:masters`, qu'on ne peut retirer à personne. Je ne veux le voir nulle part en clair, ni sur un nœud, ni dans un dépôt. L'autre, chiffré aussi, et utilisé seulement en bris de glace.

**Objectifs pédagogiques**
- Écrire une configuration kubeadm v1beta4 et la valider avant usage.
- Amorcer un plan de contrôle et comprendre chaque phase de `kubeadm init`.
- Lire ce que kubeadm produit : manifestes statiques, PKI, kubeconfigs, configuration du kubelet, ConfigMaps du cluster.
- Distinguer `admin.conf` et `super-admin.conf`, et les protéger.

**Prérequis** : M14-E03.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet | `plateforme/k8s` (nouveau, groupe `plateforme`, `main` protégée, fusion par MR, gabarits `qualite.yml` et `release.yml`), copie de travail `~/src/k8s` sur `adm01` |
| Fichier | `cluster/kubeadm-config.yaml` : ClusterConfiguration, KubeletConfiguration, KubeProxyConfiguration ; **aucune** donnée propre à un nœud (le rôle `k8s_plan_controle` ajoute l'InitConfiguration du nœud et dépose le tout dans `/etc/kubernetes/kubeadm/kubeadm-config.yaml`, en 600) |
| Valeurs | `clusterName: k8s-par1` ; `kubernetesVersion: v1.35.9` ; `controlPlaneEndpoint: k8s-api.par1.medisphere.internal:8443` ; pods 10.240.0.0/16 ; services 10.96.0.0/16 ; `cluster.local` ; SAN du kube-apiserver : le nom et la VIP ; certificats feuilles 1 an, CA 10 ans ; kubelet `cgroupDriver: systemd` ; kube-proxy `mode: iptables` |
| Rôle | `k8s_plan_controle`, seconde partie (étiquette `kubeadm`) : fichier du nœud **validé** (`kubeadm config validate`) ; amorçage automatique **désactivé** par défaut (variable) ; chemin du fichier du cluster sur `adm01` passé en variable |
| Secrets | `secrets/admin.conf.vault`, `secrets/super-admin.conf.vault` chiffrés par Ansible Vault, identité `critique` ; `.gitignore` qui refuse tout kubeconfig, clé ou certificat en clair |

**Travail demandé**

*A. Le projet et le fichier*

1. Crée `plateforme/k8s` (README avec l'arborescence prévue, `.gitignore`, `.yamllint.yaml`, `secrets/README.md`). Lis `kubeadm config print init-defaults` (sur `k8s-cp01`) et la référence de l'API v1beta4 : repère les champs de ton fichier. Lesquels ont changé de forme par rapport à v1beta3 ?
2. Écris `cluster/kubeadm-config.yaml`. Pour chaque valeur, un commentaire qui dit **pourquoi**. MR, relecture (par toi-même avec la liste de la question 1), fusion.
3. Complète le rôle `k8s_plan_controle` : lecture du fichier du cluster sur le contrôleur (refus s'il contient une InitConfiguration ou un mauvais `controlPlaneEndpoint`), ajout de l'InitConfiguration **du nœud** (adresse annoncée, nom, `node-ip` du kubelet), dépôt validé ; recherche d'un nœud de contrôle qui porte déjà un cluster ; amorçage seulement si c'est explicitement demandé. Applique avec `--tags kubeadm` : le fichier doit apparaître sur les trois nœuds de contrôle, et **rien d'autre** ne doit se passer.

*B. L'amorçage*

4. Sur `k8s-cp01`, valide puis regarde ce qui se passerait :
   ```
   root@k8s-cp01:~# kubeadm config validate --config /etc/kubernetes/kubeadm/kubeadm-config.yaml
   root@k8s-cp01:~# kubeadm config images pull --config /etc/kubernetes/kubeadm/kubeadm-config.yaml
   root@k8s-cp01:~# kubeadm init --config /etc/kubernetes/kubeadm/kubeadm-config.yaml --upload-certs --dry-run | less
   ```
   > ⚠️ **Attention** : le `--dry-run` écrit ses fichiers dans un dossier temporaire sous `/etc/kubernetes/tmp/` (le chemin est affiché) : supprime-le ensuite. La sortie de l'amorçage réel contient un **jeton d'amorçage** et une **clé de déchiffrement des certificats** : ne la colle ni dans un ticket, ni dans ton journal versionné.
5. Amorce :
   ```
   root@k8s-cp01:~# kubeadm init --config /etc/kubernetes/kubeadm/kubeadm-config.yaml --upload-certs
   ```
   Relève la liste des phases affichées (`[preflight]`, `[certs]`, `[kubeconfig]`…) et, pour chacune, ce qu'elle a produit. Combien de temps le plan de contrôle a-t-il mis à répondre, et qui l'a démarré, puisqu'aucune API n'existait ?
6. Pendant ce temps, sur un autre nœud de contrôle, regarde l'état des backends d'HAProxy : quand `k8s-cp01` passe-t-il UP ? Relance la partie `point_acces` du rôle sur `k8s-cp01` : qu'est-ce qui change dans son `haproxy.cfg`, et pourquoi maintenant ?

*C. Lire ce que kubeadm a écrit*

7. Les **manifestes statiques** (`/etc/kubernetes/manifests/`) : pour `kube-apiserver.yaml`, relève les options qui concernent etcd, les certificats clients, les comptes de service et l'autorisation. Comment le kubelet sait-il qu'il doit lire ce dossier ?
8. La **PKI** (`/etc/kubernetes/pki/`) : `kubeadm certs check-expiration`. Combien de CA ? Lesquelles signent quoi ? Lis les noms alternatifs du certificat du kube-apiserver (`openssl x509 -noout -ext subjectAltName`).
9. Les **kubeconfigs** (`/etc/kubernetes/*.conf`) : pour `admin.conf` et `super-admin.conf`, relève le sujet du certificat client (`O=`, `CN=`). Lequel passe par le RBAC, et par quelle liaison (`kubectl get clusterrolebinding …`) ? Lequel le contourne ? Que se passerait-il si quelqu'un supprimait cette liaison ?
10. Le **kubelet** : `/var/lib/kubelet/config.yaml`, `/var/lib/kubelet/kubeadm-flags.env`, l'unité systemd et son complément de kubeadm (`systemctl cat kubelet`). Les **ConfigMaps** du cluster : `kubeadm-config`, `kubelet-config`, `kube-proxy` dans `kube-system`.
11. L'état du cluster : `kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes,pods -A -o wide`. Pourquoi le nœud est-il `NotReady` et CoreDNS `Pending` ? Est-ce grave ?

*D. Les secrets*

12. Chiffre `admin.conf` et `super-admin.conf` dans `plateforme/k8s/secrets/` (identité Vault `critique`) **sans** qu'ils passent en clair sur le disque d'`adm01` ; MR. Puis retire `super-admin.conf` de `k8s-cp01`.
   > ⚠️ **Attention** : avant de supprimer le fichier du nœud, vérifie que la copie chiffrée se déchiffre (`ansible-vault view … | head -3`) et qu'elle est sur `main`. Sans elle, il faudrait la régénérer à partir de la CA (`kubeadm init phase kubeconfig super-admin`, à vérifier sur ta version).
13. Inscris les deux fichiers et la CA du cluster au registre des secrets (où, qui, rotation, révocation).

**Critères de réussite**
- [ ] `plateforme/k8s` existe ; `cluster/kubeadm-config.yaml` (v1beta4, sans donnée de nœud) est sur `main` ; le fichier du nœud est sur les trois nœuds de contrôle, en 600.
- [ ] `k8s-cp01` porte un plan de contrôle : quatre manifestes statiques, kubelet en cgroups systemd ; l'API répond `ok` sur `/readyz` **par la VIP**, en TLS vérifié par la CA du cluster.
- [ ] La configuration enregistrée dans le cluster (`kubeadm-config`, `kube-proxy`) correspond au fichier : nom, version, point d'accès, réseaux, mode de kube-proxy ; le certificat du kube-apiserver couvre le nom et la VIP.
- [ ] `admin.conf` et `super-admin.conf` sont chiffrés (Vault `critique`) dans `plateforme/k8s` ; `super-admin.conf` n'est plus sur le nœud ; aucun fichier sensible en clair dans le dépôt.
- [ ] Ton journal explique chaque phase de `kubeadm init` et la différence entre les deux kubeconfigs d'administration.

**Vérification** : `lab/bin/check 14 04`

<details><summary>Indice 1</summary>

En v1beta4, plusieurs listes de paires « clé: valeur » sont devenues des listes d'objets `name`/`value` (`extraArgs`, `kubeletExtraArgs`) ; les délais sont regroupés ; deux champs fixent la durée des certificats. `kubeadm config validate` est strict : un champ inconnu est une erreur. Un document YAML qui ne contient que des commentaires n'est pas accepté par kubeadm.
</details>

<details><summary>Indice 2</summary>

`ansible-vault encrypt` sait lire l'entrée standard et écrire où on lui dit (`--output`) ; `ssh k8s-cp01 sudo cat …` écrit sur la sortie standard. L'identité de chiffrement se choisit par `--encrypt-vault-id`. L'`ansible.cfg` de `plateforme/ansible` connaît déjà l'identité `critique` : lance la commande depuis ce dossier.
</details>

<details><summary>Indice 3</summary>

Le kubelet démarre les pods statiques sans API ; il ne peut pas encore enregistrer son nœud comme `Ready` tant qu'aucun CNI n'a écrit de configuration dans `/etc/cni/net.d/`. Regarde les conditions du nœud (`kubectl describe node`) et le journal du kubelet (`journalctl -u kubelet`).
</details>

**Pour aller plus loin** (facultatif) : relis le kube-apiserver de `kubeadm init --dry-run` et compare-le à une installation « à la main » (*Kubernetes the Hard Way*) : quelles options kubeadm choisit-il pour toi, et lesquelles faudrait-il ajouter pour l'audit (M14-E27) et le chiffrement des Secrets (M14-E28) ?

---

### M14-E05 — Joindre les nœuds et installer Cilium  `LAB` `★★`

> **Ticket PLAT-1505** — *De : Karim Benali* — *Copie : Nadia Roussel*
> Un nœud de contrôle, ce n'est pas de la haute disponibilité. Joins `k8s-cp02` et un travailleur à la main pour connaître le geste, puis laisse le rôle joindre les autres : je veux la preuve qu'il sait le faire, et qu'il ne fait plus rien quand tout est en place. Ensuite le réseau des pods : **Cilium**, en gardant kube-proxy pour l'instant (on le remplacera au M15). Nadia veut une fiche du cluster d'une page.

**Objectifs pédagogiques**
- Joindre des nœuds de contrôle et de travail : jeton d'amorçage, empreinte de la CA, clé de certificats, et ce que chacun protège.
- Automatiser les jonctions dans un rôle idempotent, sans secret qui traîne.
- Installer un CNI et vérifier le réseau des pods de bout en bout.
- Vérifier un plan de contrôle hautement disponible (etcd, API, VIP).

**Prérequis** : M14-E04.
**Durée indicative** : 4 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Jonctions | à la main : `k8s-cp02` (plan de contrôle) et `k8s-w01` ; par le rôle : `k8s-cp03` (`k8s_plan_controle`), `k8s-w02`, `k8s-w03` (`k8s_travailleur`) |
| Outils de `adm01` | rôle `outils_k8s` (playbook `playbooks/outils-k8s.yml`) : `kubectl` 1.36.5-1.1 (pkgs.k8s.io v1.36), `helm` 4.3 (dépôt APT `https://packages.buildkite.com/helm-linux/helm-debian/any/`, clé à empreinte `DDF7 8C3E 6EBB 2D2C C223 C95C 62BA 89D0 7698 DBC6`), et en binaires amont vérifiés par leur somme SHA-256 publiée : k9s 0.51.0, cilium CLI 0.20.1, hubble 1.20.2, etcdctl/etcdutl 3.6.6 |
| Cilium | **1.20.2** installé par `cilium install --version 1.20.2 --values composants/cilium/values.yaml` ; valeurs : nom du cluster, `k8sServiceHost`/`k8sServicePort` = la VIP, `kubeProxyReplacement: "false"`, tunnel VXLAN, IPAM `cluster-pool` 10.240.0.0/16 en /24, relais Hubble activé, interface Hubble désactivée |
| `plateforme/k8s` | `composants/cilium/values.yaml`, `Taskfile.yml` (tâches `noeuds`, `cilium`, `cilium-maj`, `valider`, `diff`, `appliquer`, contexte `k8s-par1` explicite) |
| Accès depuis `adm01` | jusqu'à ton identité personnelle (E06) : `admin.conf` déchiffré dans le dossier de session en mémoire (`$XDG_RUNTIME_DIR`), effacé après usage (procédure de `secrets/README.md`) |

**Travail demandé**

*A. Les outils de adm01*

1. Écris le rôle `outils_k8s` et son playbook. Exigences : clés de dépôt vérifiées par empreinte ; `kubectl` à la version exacte et retenu ; binaires amont **vérifiés par la somme publiée avec la version**, installés dans un dossier par version et liés dans `/usr/local/bin` (pourquoi cette organisation ?). Applique. Pourquoi kubectl 1.36 contre un cluster 1.35 ? Jusqu'où peut-on aller ?

*B. Joindre à la main*

2. Sur `k8s-cp01`, prépare la jonction d'un nœud de contrôle : un jeton d'amorçage de courte durée (`kubeadm token create --help`), la clé de déchiffrement des certificats (la clé affichée par `kubeadm init --upload-certs` a-t-elle encore cours ? `kubeadm init phase upload-certs --help`), l'empreinte de la clé publique de la CA (méthode de la documentation, ou `--print-join-command`). Pour chacun des trois : que protège-t-il, et contre qui ?
3. Joins `k8s-cp02` au plan de contrôle (`kubeadm join … --control-plane --certificate-key …`, avec l'adresse annoncée du nœud).
   > ⚠️ **Attention** : la commande contient le jeton et la clé de certificats. Ne la laisse pas dans l'historique du shell (`HISTCONTROL=ignorespace` et une espace en tête, ou `history -d`) ; supprime le jeton après usage (`kubeadm token delete`).
   Pendant la jonction, suis `kubectl get nodes -w` depuis `k8s-cp01`. Après : combien de membres etcd ? (`kubectl -n kube-system exec etcd-k8s-cp01 -- etcdctl … member list`, certificats dans `/etc/kubernetes/pki/etcd/`.)
4. Joins `k8s-w01` comme travailleur. Qu'est-ce qu'un travailleur reçoit du plan de contrôle, et qu'est-ce qu'il ne reçoit pas ? Qui a approuvé la demande de certificat de son kubelet (`kubectl get csr`) ?

*C. Le réseau des pods*

5. Écris `composants/cilium/values.yaml` (seulement ce qui diffère des défauts du chart ou ce qu'on veut voir écrit, avec un commentaire par valeur). Compare avec `helm show values cilium/cilium --version 1.20.2`. Pourquoi faire passer les agents par la VIP plutôt que par le Service `kubernetes` ?
6. Installe Cilium depuis `adm01` : déchiffre `admin.conf` dans le dossier de session (`secrets/README.md`), fais pointer `KUBECONFIG` dessus et renomme son contexte (`kubernetes-admin@k8s-par1`) en `k8s-par1`, le nom qu'exige le `Taskfile.yml` ; puis `task cilium`. Ensuite :
   ```
   admin@adm01:~/src/k8s$ cilium status --context k8s-par1
   admin@adm01:~/src/k8s$ kubectl --context k8s-par1 get nodes -o wide
   admin@adm01:~/src/k8s$ kubectl --context k8s-par1 get ciliumnodes -o custom-columns=NOEUD:.metadata.name,PODS:.spec.ipam.podCIDRs
   admin@adm01:~/src/k8s$ kubectl --context k8s-par1 -n kube-system get pods -o wide
   ```
   Les nœuds passent-ils `Ready` ? Quel /24 chaque nœud a-t-il reçu, et qui l'a attribué ? Pourquoi la version de Cilium est-elle passée explicitement à la CLI ?
7. Lance le test de connectivité de Cilium (`cilium connectivity test --help`) et lis ce qu'il vérifie. Supprime ensuite l'espace de noms qu'il a créé.

*D. Le code fait le reste*

8. Écris le rôle `k8s_travailleur` et complète `k8s_plan_controle` pour **joindre** les nœuds qui ne sont pas membres : jeton à durée courte créé sur un nœud de contrôle qui porte le cluster, fichier de jonction (JoinConfiguration v1beta4) en 600 **validé** puis détruit, jeton révoqué juste après, aucune valeur secrète dans la sortie d'Ansible. Un nœud de contrôle qui vient de joindre attend que son kube-apiserver soit prêt, puis repasse HAProxy en contrôle HTTPS.
9. Complète `playbooks/k8s-cluster.yml` (plan de contrôle puis travailleurs, un nœud à la fois) et ajoute au `Taskfile.yml` la tâche `noeuds` qui le lance avec le bon chemin du fichier du cluster. `task noeuds` : `k8s-cp03`, `k8s-w02` et `k8s-w03` rejoignent. Second passage : `changed=0`, sur les **six** nœuds.
10. Vérifie la haute disponibilité : trois membres etcd démarrés, trois kube-apiserver UP dans HAProxy (sur chaque nœud), CoreDNS sur deux nœuds, `kubectl -n kube-system get lease` (qui détient les baux du contrôleur et de l'ordonnanceur ?).
11. Rédige `docs/kubernetes/cluster.md` (une page : composition, point d'accès, gestes courants, arrêt et démarrage, liens) et efface le kubeconfig de bris de glace du dossier de session.

**Critères de réussite**
- [ ] Six nœuds `Ready` en v1.35.9, avec leur adresse du plan ; les nœuds de contrôle portent le rôle `control-plane` et leur *taint*, les travailleurs aucun.
- [ ] etcd a trois membres démarrés ; etcd, kube-apiserver, kube-controller-manager et kube-scheduler sont prêts sur les trois nœuds de contrôle ; HAProxy voit les trois kube-apiserver UP par un contrôle `/readyz` en TLS.
- [ ] Cilium 1.20 : agents prêts sur les six nœuds, opérateur et relais Hubble disponibles, IPAM `cluster-pool` 10.240.0.0/16 (/24 par nœud), kube-proxy conservé, agents connectés par la VIP ; CoreDNS prêt ; espace du test de connectivité supprimé.
- [ ] `adm01` a kubectl 1.36, Helm 4.3, cilium 0.20, hubble 1.20, etcdctl 3.6.6 et k9s, installés par le rôle `outils_k8s`.
- [ ] Les rôles, le playbook complet, `values.yaml`, `Taskfile.yml` et `docs/kubernetes/cluster.md` sont sur `main` ; `task noeuds` donne `changed=0` au second passage.

**Vérification** : `lab/bin/check 14 05`

<details><summary>Indice 1</summary>

La clé de déchiffrement des certificats partagés et le Secret `kubeadm-certs` expirent au bout de deux heures : `kubeadm init phase upload-certs --upload-certs` en produit de nouveaux. L'empreinte attendue par `--discovery-token-ca-cert-hash` est celle de la **clé publique** de la CA, au format `sha256:<hex>` (page « kubeadm join » de la documentation, section « discovery »).
</details>

<details><summary>Indice 2</summary>

Dans un rôle, une tâche peut s'exécuter sur un autre hôte que celui en cours (`delegate_to`) : c'est ainsi qu'un nœud qui rejoint obtient un jeton créé sur un nœud de contrôle. `no_log: true` cache la sortie d'une tâche. Un bloc `always` s'exécute même si la jonction échoue : c'est là que l'on détruit le fichier et révoque le jeton.
</details>

<details><summary>Indice 3</summary>

Les nœuds de contrôle portent le *taint* `node-role.kubernetes.io/control-plane:NoSchedule` : les pods du test de connectivité et CoreDNS vont donc sur les travailleurs. Si un agent Cilium reste en `Init`, regarde ses conteneurs d'initialisation (`kubectl describe pod`) : c'est souvent l'accès à l'API par l'adresse donnée dans les valeurs.
</details>

**Pour aller plus loin** (facultatif) : `hubble observe --context k8s-par1 -n kube-system --protocol dns` (avec `cilium hubble port-forward` en arrière-plan) montre les requêtes DNS du cluster en direct. Le M15 en fera un outil de diagnostic.

---

### M14-E06 — kubectl, kubeconfig et k9s  `LAB` `★`

> **Ticket PLAT-1506** — *De : Karim Benali*
> Fini le bris de glace pour travailler. Chacun son identité, nominative, courte, renouvelée par un script ; plus jamais d'`admin.conf` sur `adm01`. Et prends le temps d'apprendre kubectl correctement : `explain`, les sorties, `--dry-run=server`, `diff`. Ça t'économisera des heures.
>
> **Ticket SEC-1506** — *De : Sophie Laurent*
> Les vérifications automatiques du workbook ont besoin de lire le cluster. Un compte de service dédié, **en lecture**, sans accès aux Secrets, et je veux que l'exception sur la durée de son jeton soit écrite quelque part.

**Objectifs pédagogiques**
- Comprendre la structure d'un kubeconfig (clusters, utilisateurs, contextes) et l'identité qu'il porte.
- Émettre une identité personnelle à durée courte et la lier à des droits par son groupe.
- Créer un compte de service en lecture seule et l'utiliser hors du cluster.
- Utiliser kubectl efficacement : `explain`, `-o jsonpath`, `--dry-run=server`, `diff`, `auth can-i`, `auth whoami`, greffons krew, k9s.

**Prérequis** : M14-E05.
**Durée indicative** : 2 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Identité personnelle | certificat client CN=`<MOI>`, O=`medisphere:plateforme-admins`, **7 jours**, émis sur `k8s-cp01` par `kubeadm kubeconfig user` (avec le fichier `/etc/kubernetes/kubeadm/kubeadm-config.yaml`) ; rangé dans `~/.kube/config` (600), cluster, utilisateur et contexte nommés `k8s-par1`, `<MOI>`, `k8s-par1` ; script `outils/kubeconfig-personnel.sh <MOI>` de `plateforme/k8s` |
| Droits | ClusterRoleBinding `medisphere:plateforme-admins` : groupe `medisphere:plateforme-admins` → ClusterRole `cluster-admin` (`rbac/plateforme-admins.yaml`) |
| Espaces | `wb-system`, `wb-essais` (`espaces/`) |
| Vérifications | compte de service `wb-system/wb-checks` (sans montage automatique de jeton) ; jeton durable porté par un Secret `wb-checks-jeton` de type `kubernetes.io/service-account-token` (**exception** documentée) ; ClusterRole **agrégée** `wb-checks` (sélecteur d'étiquette `workbook.medisphere.internal/checks: "true"`) et ClusterRole `wb-checks-base` étiquetée : lecture (`get`, `list`, `watch`) de tout **sauf les Secrets**, `get` sur `services/proxy`, `create` sur `subjectaccessreviews`, URL de santé ; liaison `wb-checks`. Convention pour la suite du workbook : chaque module qui a besoin de lire de nouvelles ressources ajoute une ClusterRole `wb-checks-<thème>` portant la même étiquette, sans toucher à celles-ci ; script `outils/kubeconfig-checks.sh` qui écrit `~/.config/workbook/k8s-checks.kubeconfig` (600) |
| Application | `task diff`, `task appliquer` (server-side apply, gestionnaire de champs `plateforme-k8s`) |
| Greffons krew | `ctx`, `ns`, `neat` |

**Travail demandé**

*A. Ton identité*

1. Lis un kubeconfig : `kubectl config view` (et `--raw` : que change l'option ?). Où sont le point d'accès, la CA, l'identité ? Que contient le certificat client de `admin.conf` ?
2. Applique `rbac/plateforme-admins.yaml` (MR d'abord) avec le kubeconfig de bris de glace. Pourquoi lier un **groupe** plutôt que ton nom ?
3. Écris `outils/kubeconfig-personnel.sh`. Exigences : nom validé ; certificat demandé à `k8s-cp01` par SSH (`kubeadm kubeconfig user --help`) avec ton nom, ton groupe et 7 jours ; la clé privée n'est jamais écrite en clair hors de `~/.kube/config` (dossier de session en mémoire pendant le script) ; contrôles avant de ranger (sujet, chaîne de confiance, point d'accès) ; noms stables dans `~/.kube/config` (un renouvellement **remplace**) ; une option qui affiche seulement l'identité et la date d'expiration.
4. Lance-le, puis :
   ```
   admin@adm01:~$ kubectl auth whoami
   admin@adm01:~$ kubectl auth can-i '*' '*'
   admin@adm01:~$ kubectl auth can-i --list --namespace kube-system | head
   ```
   Efface le kubeconfig de bris de glace s'il traîne encore dans le dossier de session. Comment révoquerais-tu ton certificat avant son expiration ? (Lis la question 12 de E01 et sa correction.)

*B. kubectl, sérieusement*

5. Fais le tour suivant et note dans ton journal une ligne utile par commande :
   - `kubectl api-resources` (colonnes `SHORTNAMES`, `NAMESPACED`), `kubectl explain deployment.spec.strategy --recursive` ;
   - `kubectl get nodes -o wide`, `-o yaml`, `-o jsonpath='{.items[*].status.nodeInfo.kubeletVersion}'`, `-o custom-columns=…`, `--sort-by`, `-l`, `--field-selector` ;
   - `kubectl -n wb-essais create deployment essai --image=registry.k8s.io/pause:3.10.1 --dry-run=client -o yaml` puis la même chose avec `--dry-run=server` : quelle différence, et quand l'une attrape-t-elle une erreur que l'autre ne voit pas ?
   - `kubectl diff -f` sur un fichier modifié ; `kubectl apply --server-side` et `--show-managed-fields`.
6. Installe krew dans ton compte (méthode de la documentation de krew, en vérifiant la somme de l'archive) puis les greffons `ctx`, `ns`, `neat`. À quoi sert `neat` quand on veut repartir d'un objet existant pour écrire un manifeste ?

*C. Le compte des vérifications*

7. Écris `espaces/wb-system.yaml`, `espaces/wb-essais.yaml` et `rbac/wb-checks.yaml` (compte de service, Secret du jeton, ClusterRole agrégée, ClusterRole de base étiquetée, liaison). RBAC n'a pas de « tout sauf » : comment exclure les Secrets ? Pourquoi une ClusterRole **agrégée** (pense aux modules 15 à 29) ? Pourquoi `subjectaccessreviews` plutôt que le droit d'emprunter une identité ?
8. MR, puis `task diff` et `task appliquer`. Vérifie avec `kubectl auth can-i --as=system:serviceaccount:wb-system:wb-checks get secrets -A` (toi, tu as le droit d'emprunter) et la même question pour `get pods`.
9. Écris `outils/kubeconfig-checks.sh` : lit le jeton et la CA du Secret avec ton identité, écrit le kubeconfig des vérifications en 600 **sans** que le jeton apparaisse dans un argument de commande, contrôle l'identité obtenue (elle lit les nœuds, ne lit pas les Secrets, n'écrit pas). Lance-le, puis `lab/bin/check 14 06`.
10. Documente dans `docs/kubernetes/acces.md` : les quatre identités (personnelle, vérifications, bris de glace, bris de glace ultime), les règles, l'**exception** du jeton durable de `wb-checks` (pourquoi, compensations, révocation) et la **règle d'extension** de `wb-checks` (comment un module ajoute des droits de lecture, ce qu'il ne doit jamais ajouter, comment le vérifier). Ajoute la ligne au registre des secrets.

*D. k9s*

11. Lance `k9s --readonly --context k8s-par1`. Trouve sans aide : les pods de `kube-system` triés par nœud, les journaux d'un agent Cilium, les événements du cluster, la vue `:pulses` et `:xray deploy`. Quelle est la différence avec `--readonly` absent ?

**Critères de réussite**
- [ ] `~/.kube/config` (600) contient ton identité (CN=`<MOI>`, O=`medisphere:plateforme-admins`, 7 jours au plus) dans le contexte courant `k8s-par1` ; `kubectl auth whoami` la confirme ; aucune copie d'`admin.conf` ou de `super-admin.conf` ne reste sur `adm01`.
- [ ] `wb-system`, `wb-essais`, la liaison `medisphere:plateforme-admins` et les objets de `wb-checks` sont appliqués par `task appliquer` (gestionnaire `plateforme-k8s`).
- [ ] `~/.config/workbook/k8s-checks.kubeconfig` (600) identifie `system:serviceaccount:wb-system:wb-checks`, qui lit les nœuds mais ne peut ni lire les Secrets, ni supprimer un pod, ni emprunter une identité.
- [ ] krew (`ctx`, `ns`, `neat`) et k9s fonctionnent ; les scripts, les manifestes et `docs/kubernetes/acces.md` (identités, exception, règle d'extension de `wb-checks`) sont sur `main`.

**Vérification** : `lab/bin/check 14 06`

<details><summary>Indice 1</summary>

`kubeadm kubeconfig user` signe avec la CA du nœud et écrit le kubeconfig sur la sortie standard. `kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -noout -subject` affiche le sujet d'un certificat embarqué. `kubectl config set-cluster`, `set-credentials` (avec `--embed-certs`) et `set-context` écrivent dans le kubeconfig désigné par `KUBECONFIG`.
</details>

<details><summary>Indice 2</summary>

Une ClusterRole agrégée a un `aggregationRule` et **pas** de `rules` écrites à la main : le contrôleur d'agrégation les calcule. Avec le *server-side apply*, ne pas écrire un champ, c'est ne pas en revendiquer la propriété. Le contrôleur des jetons remplit `data.token` et `data.ca.crt` d'un Secret annoté `kubernetes.io/service-account.name` quelques instants après sa création.
</details>

<details><summary>Indice 3</summary>

`printf` est une commande interne du shell : ce que tu lui passes n'apparaît pas dans la liste des processus. `kubectl auth can-i` répond `no` avec le code de sortie 1 : dans un script en `set -e`, prévois-le.
</details>

**Pour aller plus loin** (facultatif) : lis la documentation des jetons liés (`kubectl create token --duration`, `TokenRequest`) : quelle durée maximale le serveur accepte-t-il par défaut, et comment la limiter ? M14-E13 y revient.

---

### M14-E07 — Pods, Deployments et Services : MédiAgenda sur le cluster  `LAB` `★★`

> **Ticket DEV-1507** — *De : Julien Petit*
> On a enfin une image signée de l'API dans Harbor. Je voudrais la voir tourner sur le vrai cluster, à deux exemplaires, avec sa base et son cache, même jetables, et pouvoir faire un `curl` dessus depuis mon poste. Pas besoin que ce soit beau, je veux comprendre comment ça s'emboîte : Pods, Deployments, Services. Mets les manifestes dans notre dépôt, on les reprendra.

**Objectifs pédagogiques**
- Écrire un Deployment, un Service ClusterIP et leurs étiquettes, et comprendre le lien sélecteur → pods → points de terminaison.
- Tirer une image privée de Harbor avec un Secret de tirage.
- Lancer les migrations de schéma avant l'application (conteneur d'initialisation).
- Joindre un Service depuis le poste d'administration (`port-forward`) et lire le chemin d'une requête.

**Prérequis** : M14-E06 ; M13-E09 (image `medisphere/mediagenda-api` publiée et signée) ; M12-E08 (commande de migration de MédiAgenda).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Espace | `wb-essais` |
| API | Deployment `mediagenda-api`, **2 réplicas**, image `registry.par1.medisphere.internal/medisphere/mediagenda-api:<VERSION-MEDIAGENDA>` ; port 8000 nommé `http` ; Service ClusterIP `mediagenda-api` port 80 → `http` |
| Variables | `MEDIAGENDA_DB_URL` (`postgresql://mediagenda:<MOT-DE-PASSE>@postgresql:5432/mediagenda`), `MEDIAGENDA_VALKEY_URL` (`redis://valkey:6379/0`) ; voir `apps/mediagenda/README.md` |
| Base | Deployment `postgresql`, 1 réplica, image `docker.io/library/postgres:18-trixie`, base et compte `mediagenda`, mot de passe dans un Secret `postgresql` (clé `mot-de-passe`), données en `emptyDir` (**jetables**), Service `postgresql` port 5432 |
| Cache | Deployment `valkey`, 1 réplica, image `docker.io/valkey/valkey:8.1`, sans persistance, Service `valkey` port 6379 |
| Tirage | Secret `harbor-pull` de type `kubernetes.io/dockerconfigjson` pour `registry.par1.medisphere.internal`, avec le robot `robot$k8s-pull` (`~/.config/workbook/harbor-k8s-pull.env`) |
| Dépôt | `mediagenda/api`, dossier `k8s/essais/` (`mediagenda-api.yaml`, `postgresql.yaml`, `valkey.yaml`) ; **aucun Secret versionné** |
| Étiquettes | `app.kubernetes.io/name`, `app.kubernetes.io/part-of: mediagenda`, `app.kubernetes.io/component` |

**Travail demandé**

1. Avant d'écrire, un pod à la main pour sentir l'objet :
   ```
   admin@adm01:~$ kubectl -n wb-essais run essai --image=docker.io/library/debian:trixie-slim --restart=Never -- sleep 600
   admin@adm01:~$ kubectl -n wb-essais get pod essai -o wide
   admin@adm01:~$ kubectl -n wb-essais describe pod essai
   admin@adm01:~$ kubectl -n wb-essais delete pod essai
   ```
   Lis les événements de `describe` dans l'ordre : qui fait quoi (ordonnanceur, kubelet) ? Sur quel nœud est-il, et pourquoi pas sur un nœud de contrôle ?
2. Crée les Secrets **sans** que le mot de passe ni le jeton du robot passent dans un argument de commande ni dans un fichier versionné : le mot de passe de PostgreSQL (généré, gardé dans un fichier 600 de `~/m14/e07/` le temps de l'exercice) ; le Secret de tirage `harbor-pull` construit à partir de `harbor-k8s-pull.env` (format `.dockerconfigjson` : lis la page « Pull an Image from a Private Registry »).
3. Écris `valkey.yaml` et `postgresql.yaml` (Deployment + Service chacun). Pourquoi un `emptyDir`, et qu'est-ce qui le fait disparaître ? Pourquoi la stratégie `Recreate` pour PostgreSQL ?
4. Écris `mediagenda-api.yaml` : Deployment à 2 réplicas avec un **conteneur d'initialisation** qui applique les migrations (la commande du service de migration de ton `compose.yaml`), puis l'API ; l'URL de la base construite à partir du Secret **sans** écrire le mot de passe dans le manifeste (cherche « dependent environment variables ») ; le Secret de tirage ; un Service ClusterIP. Les deux pods lancent les migrations en même temps : est-ce un problème ? (Lis `migrate.py`.)
5. Applique (`kubectl apply -f k8s/essais/`), puis observe : `kubectl -n wb-essais get deploy,rs,pods,svc,endpointslices -o wide`. Dessine dans ton journal le lien Deployment → ReplicaSet → Pods, et Service → EndpointSlice → Pods. Qu'est-ce qui relie un Service à ses pods ?
6. Depuis `adm01` :
   ```
   admin@adm01:~$ kubectl -n wb-essais port-forward service/mediagenda-api 8000:80
   ```
   et, dans un autre terminal, `curl -s localhost:8000/sante`, la création d'un rendez-vous (exemple du README de l'application), `curl -s localhost:8000/api/v1/rendez-vous`. Par où passe la requête, de `curl` jusqu'au pod ? (Indice : ce n'est pas le Service.)
7. Expérimente :
   - supprime un pod de l'API : que se passe-t-il, en combien de temps ?
   - `kubectl -n wb-essais scale deployment mediagenda-api --replicas=3`, puis reviens à 2 dans le **fichier** et réapplique : qui a raison ?
   - supprime le pod PostgreSQL : que deviennent tes rendez-vous ? Que fait l'API pendant ce temps (`kubectl logs`) ? Recrée un rendez-vous ensuite.
   - change une étiquette d'un pod de l'API pour qu'il ne corresponde plus au sélecteur (`kubectl label pod … app.kubernetes.io/name=quarantaine --overwrite`) : que font le ReplicaSet et le Service ? Supprime ce pod orphelin ensuite.
8. MR sur `mediagenda/api` avec les trois fichiers (et un `README` court dans `k8s/essais/` : ce que c'est, ce que ce n'est pas).

**Critères de réussite**
- [ ] Dans `wb-essais` : `mediagenda-api` a 2 réplicas prêts, tirés de Harbor par une étiquette de version (jamais `latest`) avec le Secret `harbor-pull` ; leurs migrations se sont terminées sans erreur ; les pods tournent sur des travailleurs.
- [ ] `postgresql` (stratégie `Recreate`) et `valkey` ont chacun un réplica prêt, données en `emptyDir` ; les trois Services sont de type ClusterIP ; `mediagenda-api` a deux points de terminaison prêts.
- [ ] `GET /sante` répond `ok` à travers le Service, et au moins un rendez-vous existe (`GET /api/v1/rendez-vous`).
- [ ] Les trois manifestes sont sur `main` de `mediagenda/api` ; aucun mot de passe ni jeton n'y figure.

**Vérification** : `lab/bin/check 14 07`

<details><summary>Indice 1</summary>

Un `.dockerconfigjson` est un JSON `{"auths": {"<registre>": {"auth": "<base64 de utilisateur:motdepasse>"}}}`. `kubectl create secret generic <nom> --type=kubernetes.io/dockerconfigjson --from-file=.dockerconfigjson=<fichier>` en fait un Secret. Le fichier peut vivre dans le dossier de session en mémoire le temps de la commande ; `$` dans le nom du robot se protège en shell.
</details>

<details><summary>Indice 2</summary>

Dans `env`, une valeur peut référencer une variable définie **plus haut dans la même liste** par `$(NOM)`. Un conteneur d'initialisation doit se terminer avec le code 0 pour que les conteneurs principaux démarrent ; s'il échoue, `kubectl logs <pod> -c <nom>`.
</details>

<details><summary>Indice 3</summary>

`kubectl port-forward` ouvre un tunnel par le serveur d'API jusqu'au kubelet du nœud, qui relaie vers **un** pod choisi au départ : il ne répartit pas. Les données d'un `emptyDir` vivent tant que le pod vit sur ce nœud.
</details>

**Pour aller plus loin** (facultatif) : `kubectl -n wb-essais run client --rm -it --image=docker.io/library/debian:trixie-slim -- bash`, puis dans le pod `getent hosts mediagenda-api` et `cat /etc/resolv.conf` : explique chaque ligne (`search`, `ndots`). M14-E42 y reviendra par la panne.

---

### M14-E08 — ConfigMaps, Secrets, sondes et ressources  `LAB` `★★`

> **Ticket DEV-1508** — *De : Julien Petit* — *Copie : Sophie Laurent*
> Ça marche, mais Karim a relu nos manifestes et il les a rendus avec quatre commentaires : « la configuration est en dur », « le mot de passe a le même nom de Secret que la base de test », « aucune sonde : Kubernetes enverra du trafic à un pod qui démarre », « pas de ressources : le premier pic mangera le nœud ». Et Sophie demande que le conteneur ne tourne pas en root et ne puisse rien écrire hors de ce qui est prévu. On corrige tout ça, toujours dans `wb-essais`.

**Objectifs pédagogiques**
- Séparer la configuration (ConfigMap) des secrets (Secret) et les injecter en variables d'environnement.
- Choisir et régler les trois sondes (démarrage, vivacité, disponibilité) d'après le comportement réel de l'application.
- Poser des demandes et des limites de ressources, et prévoir la classe QoS qui en résulte.
- Durcir le contexte de sécurité d'un conteneur sans casser l'application.

**Prérequis** : M14-E07.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| ConfigMap | `mediagenda-api-config` : `MEDIAGENDA_LOG_LEVEL`, `MEDIAGENDA_LOG_FORMAT`, `MEDIAGENDA_FUSEAU`, `MEDIAGENDA_CACHE_TTL`, `MEDIAGENDA_DELAI_ARRET`, `MEDIAGENDA_VALKEY_URL` ; fichier `k8s/essais/mediagenda-api-config.yaml` |
| Secret | `mediagenda-db` (clé `mot-de-passe`), utilisé par PostgreSQL et par l'API ; créé hors du dépôt ; l'ancien Secret `postgresql` disparaît |
| Sondes de l'API | `GET /sante` : vivacité, ne touche ni la base ni le cache ; `GET /pret` : disponibilité, 200 si PostgreSQL **et** Valkey répondent, 503 sinon ; démarrage : `/sante` (README de l'application) |
| Arrêt | uvicorn laisse `MEDIAGENDA_DELAI_ARRET` secondes (20) aux requêtes en cours après SIGTERM |
| Classes QoS visées | API : **Burstable** ; PostgreSQL : **Guaranteed** ; Valkey : au choix, justifié |
| Sécurité de l'API | non-root (l'image tourne sous l'UID 10001), pas d'élévation de privilèges, aucune capacité, système de fichiers racine en lecture seule, profil seccomp par défaut du runtime |

**Travail demandé**

1. Lis `apps/mediagenda/README.md` (configuration, points d'accès, arrêt propre) et `kubectl explain pod.spec.containers.livenessProbe`. Pour chaque sonde, note : ce qu'elle doit vérifier pour MédiAgenda, ce qui se passe quand elle échoue, et la pire erreur de réglage possible.
2. Écris le ConfigMap et branche-le dans l'API (`envFrom`). Crée le Secret `mediagenda-db` (mêmes précautions qu'en E07) et fais-le utiliser par PostgreSQL et l'API. Que se passe-t-il pour PostgreSQL, dont les données existent déjà avec l'ancien mot de passe ? Comment l'expliques-tu, et que fais-tu (ces données sont jetables) ?
3. Modifie une valeur du ConfigMap (`MEDIAGENDA_LOG_LEVEL: DEBUG`), réapplique : les pods la voient-ils ? Que faut-il faire, et pourquoi Kubernetes ne le fait-il pas tout seul pour des variables d'environnement ? Remets `INFO`.
4. Ajoute les trois sondes à l'API, et une sonde de disponibilité (au moins) à PostgreSQL et à Valkey. Règle les délais : combien de temps le démarrage peut-il prendre au plus avant que la vivacité compte ? Combien d'échecs avant un redémarrage ?
5. Provoque et observe (`kubectl get pods -w`, `kubectl describe`, `kubectl get endpointslices -w` dans d'autres terminaux) :
   - mets Valkey à 0 réplica : que deviennent les pods de l'API (redémarrés ? retirés du Service ?) et pourquoi ? Que répondrait `/api/v1/creneaux` (README : mode dégradé) ? Remets 1 réplica ;
   - imagine qu'on ait mis `/pret` en sonde de **vivacité** : décris, sans le faire, ce qui se serait passé pendant la panne de Valkey.
6. Ajoute les demandes et limites : API Burstable, PostgreSQL Guaranteed, Valkey au choix (borne aussi sa mémoire côté Valkey : pourquoi ?). Vérifie la classe obtenue (`kubectl get pod -o jsonpath='{.status.qosClass}'`) et la place réservée sur les nœuds (`kubectl describe node k8s-w01`, section « Allocated resources »). Pourquoi pas de limite de CPU sur l'API ?
7. Durcis l'API (contexte de sécurité du pod et du conteneur). Qu'est-ce qui casse avec un système de fichiers racine en lecture seule, et comment le corriges-tu sans le désactiver ? Vérifie avec `kubectl exec … -- id` et une tentative d'écriture dans `/app`.
8. Vérifie l'arrêt propre : délai de grâce du pod supérieur à `MEDIAGENDA_DELAI_ARRET`. Lance `kubectl -n wb-essais rollout restart deployment mediagenda-api` pendant qu'une boucle `curl` tourne dans le `port-forward` : des erreurs ? (Le *port-forward* suit un seul pod : ce test a une limite, laquelle ?)
9. MR sur `mediagenda/api` : manifestes mis à jour, ConfigMap, et une note dans `k8s/essais/README.md` sur ce qui reste à faire pour une vraie recette (stockage persistant : M16 ; publication : M15 ; NetworkPolicy : M15 ; admission : M14-E18).

**Critères de réussite**
- [ ] La configuration de l'API vient du ConfigMap `mediagenda-api-config` (sans aucun mot de passe) ; le mot de passe vient du Secret `mediagenda-db` par référence, jamais écrit en clair dans un manifeste.
- [ ] L'API a une sonde de démarrage et une de vivacité sur `/sante`, une de disponibilité sur `/pret` ; le démarrage laisse au moins 30 s ; PostgreSQL et Valkey ont une sonde de disponibilité.
- [ ] Demandes et limites posées : pods de l'API en Burstable, PostgreSQL en Guaranteed ; délai de grâce de l'API supérieur à `MEDIAGENDA_DELAI_ARRET`.
- [ ] L'API tourne non-root, sans élévation de privilèges, racine en lecture seule ; `/pret` répond `pret` avec PostgreSQL et Valkey `ok`, et le Service a deux points de terminaison prêts.
- [ ] Les manifestes et le ConfigMap sont sur `main` de `mediagenda/api` ; aucun Secret n'y est versionné.

**Vérification** : `lab/bin/check 14 08`

<details><summary>Indice 1</summary>

Une sonde a quatre réglages qui comptent : `periodSeconds`, `timeoutSeconds`, `failureThreshold`, et (pour la disponibilité) `successThreshold`. La sonde de démarrage suspend les deux autres tant qu'elle n'a pas réussi : durée maximale = période × seuil d'échecs. Pour PostgreSQL, `pg_isready` existe dans l'image.
</details>

<details><summary>Indice 2</summary>

La classe QoS se déduit des demandes et limites de **tous** les conteneurs du pod, conteneurs d'initialisation compris dans le calcul des ressources effectives. Guaranteed exige des limites égales aux demandes, pour le CPU **et** la mémoire, partout.
</details>

<details><summary>Indice 3</summary>

Python et uvicorn écrivent parfois dans un dossier temporaire : un `emptyDir` (éventuellement en mémoire) monté sur `/tmp` suffit. PostgreSQL n'initialise son dossier de données qu'à la **première** exécution sur un dossier vide : il ne relit pas `POSTGRES_PASSWORD` ensuite.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Pod Quality of Service Classes » et la section « Node-pressure Eviction » : dans quel ordre le kubelet évincerait-il tes pods si `k8s-w01` manquait de mémoire ? M14-E38 et M14-E36 y reviennent par la panne.

---

### M14-E09 — Questions : architecture de Kubernetes  `Q` `★★`

> **Ticket PLAT-1509** — *De : Karim Benali*
> Tu as monté le cluster et déployé une application. Avant d'ouvrir les droits aux équipes, je veux vérifier que tu sais ce qui se passe entre les composants. Par écrit, sans documentation, en t'appuyant sur ce que tu as vu sur `k8s-par1`.

**Objectifs pédagogiques**
- Relier les composants entre eux : qui parle à qui, par quel protocole, avec quelle identité.
- Expliquer le chemin d'une demande, de `kubectl apply` au conteneur, et d'un paquet, du client au pod.
- Raisonner sur les pannes d'un plan de contrôle hautement disponible.

**Prérequis** : M14-E02 à M14-E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 16 questions. Appuie-toi sur ce que tu as observé sur `k8s-par1` (fichiers, commandes) quand c'est possible.

1. Dessine le chemin d'un `kubectl apply -f mediagenda-api.yaml` jusqu'aux conteneurs qui tournent : chaque composant traversé, ce qu'il lit, ce qu'il écrit, et dans quel ordre. Où s'arrêterait-il si l'ordonnanceur était en panne ? Et si le contrôleur de ReplicaSet l'était ?
2. Quels composants parlent à etcd ? Pourquoi ce choix d'architecture ?
3. Le kube-apiserver de `k8s-cp02` lit etcd sur `https://127.0.0.1:2379`. Que se passe-t-il pour lui si le membre etcd **local** tombe, alors que les deux autres vont bien ?
4. *(QCM)* `k8s-cp01` et `k8s-cp02` s'arrêtent en même temps. Que reste-t-il ?
   - A. Tout fonctionne : `k8s-cp03` a une copie complète d'etcd
   - B. L'API ne peut plus écrire, et en pratique ne répond plus ; les pods déjà lancés continuent de tourner sur les travailleurs
   - C. Les pods des travailleurs s'arrêtent immédiatement
   - D. etcd bascule en lecture seule et l'API continue de servir les lectures et les écritures en attente
5. Pourquoi le kube-controller-manager et le kube-scheduler tournent-ils sur les trois nœuds de contrôle, mais n'agissent-ils que sur un seul ? Où le vois-tu sur `k8s-par1` ?
6. Le kubelet de `k8s-w02` parle à l'API par la VIP. Avec quelle identité (nom, groupes), et qu'est-ce qui l'empêche de modifier les objets d'un **autre** nœud ?
7. Comment le kubelet a-t-il démarré etcd et kube-apiserver sur `k8s-cp01`, alors qu'aucune API n'existait ? Que se passe-t-il si tu modifies `/etc/kubernetes/manifests/kube-scheduler.yaml` ?
8. Un pod de MédiAgenda sur `k8s-w01` envoie une requête à `postgresql:5432`. Décris chaque étape : résolution du nom (qui répond, quelle adresse), traduction de l'adresse du Service (qui, où, comment), trajet vers le pod PostgreSQL sur `k8s-w03` (quelle encapsulation, quelles adresses dans quel en-tête).
9. *(QCM)* Tu supprimes le DaemonSet `kube-proxy`. Les pods existants peuvent-ils encore joindre `postgresql:5432` ?
   - A. Non, plus aucun Service ne fonctionne immédiatement
   - B. Oui pendant un temps : les règles déjà écrites restent dans le noyau des nœuds, mais plus rien ne les met à jour (nouveaux Services, pods qui changent d'adresse)
   - C. Oui, Cilium prend le relais automatiquement
   - D. Non, CoreDNS cesse de répondre
10. Que fait le conteneur `pause` d'un pod ? Que se passe-t-il si le conteneur de l'API redémarre : l'adresse du pod change-t-elle ? Et si le **pod** est recréé ?
11. Différence entre `readinessProbe` et `livenessProbe` du point de vue du **kubelet**, du **Service** et de l'**utilisateur final**. Pourquoi `/pret` en vivacité est-il une erreur grave ?
12. Classes QoS : un nœud manque de mémoire. Dans quel ordre le kubelet évince-t-il un pod BestEffort, un pod Burstable qui dépasse ses demandes, un pod Guaranteed ? Qu'est-ce qui est différent quand c'est le **noyau** (OOM killer) qui agit ?
13. `admin.conf`, `super-admin.conf`, ton kubeconfig personnel, celui de `wb-checks` : pour chacun, comment l'API authentifie la requête, comment elle l'autorise, et comment on retire l'accès.
14. Pourquoi HAProxy est-il en mode **TCP** et pas en mode HTTP devant le kube-apiserver ? Que perdrait-on (au moins deux choses) en terminant le TLS sur HAProxy ?
15. kubeadm a créé trois CA (cluster, etcd, front-proxy) et une paire de clés pour les comptes de service. À quoi sert chacune ? Qu'est-ce qui casserait si la clé des comptes de service différait d'un nœud de contrôle à l'autre ?
16. Tu dois monter le cluster en 1.36 dans six mois. D'après ce que tu as installé, liste tout ce qui a une version et doit suivre (ou rester compatible) : au moins huit éléments.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 16 questions, en citant ce que tu as observé sur `k8s-par1` pour au moins six d'entre elles.
- [ ] Tu as noté chaque réponse (0, 1 ou 2 points) avec le corrigé et identifié les notions à revoir.

<details><summary>Indice 1</summary>

Le serveur d'API est le seul à toucher etcd ; tous les autres composants **observent** l'API (*watch*) et y écrivent leurs décisions. Cherche, pour chaque composant, la ressource qu'il surveille.
</details>

<details><summary>Indice 2</summary>

Pour le trajet d'un paquet, `iptables-save -t nat | grep <adresse du Service>` sur un nœud, `kubectl get ciliumnodes` et `cilium status --verbose` donnent les pièces du puzzle. Pour l'identité des kubelets : `openssl x509` sur `/var/lib/kubelet/pki/kubelet-client-current.pem`.
</details>

**Pour aller plus loin** (facultatif) : le M14-E44 (« Sous le capot ») refait la question 1 avec les mains : `curl` sur l'API avec un certificat, observation d'un *watch*, `crictl` sur le nœud.
