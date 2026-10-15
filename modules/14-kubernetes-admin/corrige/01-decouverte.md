# Module 14 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`infra/` pour `plateforme/infra`, `ansible/` pour `plateforme/ansible`, `k8s/` pour `plateforme/k8s`, `mediagenda-api/` pour `mediagenda/api`, `medisphere/` pour la documentation). Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie : `M14-E02/` (VMs, inventaire, rôles `containerd` et `k8s_noeud`), `M14-E03/` (VIP, rôle `k8s_plan_controle` **complet**, première version du playbook), `M14-E04/` (projet `plateforme/k8s`, fichier du cluster), `M14-E05/` (rôles `k8s_travailleur` et `outils_k8s`, playbook complet, Cilium, `Taskfile.yml`), `M14-E06/` (espaces, RBAC, scripts d'accès), `M14-E07/` et `M14-E08/` (MédiAgenda).

**Ce qui a été vérifié à la rédaction** :
- `envs/k8s` (avec `api.tf`) passe `tofu fmt -check` et `tofu validate` avec OpenTofu 1.13.0 et les fournisseurs réels (`bpg/proxmox` 0.116, `e-breuninger/netbox` 5.8, `mmianl/powerdns` 2.5), les modules `vm-noeud` v2.3 et `enregistrement-dns` étant pris dans les corrigés des modules 08, 10 et 06 ;
- les rôles `containerd`, `k8s_noeud`, `k8s_plan_controle`, `k8s_travailleur`, `outils_k8s`, les playbooks, la source d'inventaire et le scénario Molecule passent `ansible-lint` 26.9 (profil `production`, ansible-core 2.21) ; les sections HAProxy calculées par `k8s_plan_controle` ont été rendues avec le gabarit du rôle `haproxy` (M07-E28) et validées par `haproxy -c` de HAProxy 3.2.25, dans les deux états (contrôle TCP, puis HTTPS vérifié) ;
- `config.toml` du rôle `containerd` validé par `containerd config dump` de **containerd.io 2.3.6** (paquet du dépôt Docker pour trixie) : le schéma courant de containerd 2.3 est la **version 4** (un fichier « version = 3 » est migré avec un avertissement), le paquet livre `disabled_plugins = ["cri"]`, `SystemdCgroup` vaut `false` et l'image pause `registry.k8s.io/pause:3.10.2` par défaut ;
- `kubeadm` **1.35.9** (binaire de dl.k8s.io) : `kubeadm config images list` (pause **3.10.1**, etcd **3.6.6-0**, CoreDNS **v1.13.1**), `kubeadm config validate` du fichier complet (InitConfiguration rendue par le rôle + fichier du cluster) et de la JoinConfiguration de jonction, `kubeadm init --dry-run` (manifestes, SAN du certificat, `kubeadm-flags.env`), `kubeadm init phase preflight --dry-run`, `kubeadm kubeconfig user --validity-period 168h` (sujet `O=medisphere:plateforme-admins, CN=<MOI>`, serveur = `controlPlaneEndpoint`) ;
- empreintes des clés de dépôt : Docker `9DC858229FC7DD38854AE2D88D81803C0EBFCD88`, pkgs.k8s.io v1.35 et v1.36 `DE15B14486CD377B9E876E1A234654DA9A296436` (expiration annoncée le **29/12/2026**, prolongée d'ordinaire par l'amont), Helm (buildkite) `DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6` ; paquets `kubelet 1.35.9-1.1` et `containerd.io 2.3.6-1~debian.13~trixie` présents dans les index ;
- le chart Cilium **1.20.2** rendu par `helm template` avec `composants/cilium/values.yaml` (clés du ConfigMap `cilium-config`, variables `KUBERNETES_SERVICE_HOST/PORT` de l'agent) ; CLI cilium 0.20.1 (sa version de Cilium par défaut est 1.20.1 : d'où `--version 1.20.2`), hubble 1.20.2, etcdctl 3.6.6, k9s 0.51.0, krew 0.5.0 : URL et sommes publiées vérifiées ;
- manifestes de `plateforme/k8s` et de MédiAgenda : `yamllint --strict` et `kubeconform -strict` ; l'image MédiAgenda du module 12 (UID 10001, `/app/migrations`, `MEDIAGENDA_MIGRATIONS_DIR`) démarre avec un système de fichiers racine en lecture seule et `/tmp` en tmpfs, et `python -m mediagenda.migrate` applique V1 et V2 sur `postgres:18-trixie` ; `valkey/valkey:8.1` répond à `valkey-cli ping` ;
- `Taskfile.yml` lu par Task 3.54 (`task --list`, `task --dry`) ; scripts `kubeconfig-personnel.sh`, `kubeconfig-checks.sh` et tous les checks : `shellcheck -x` et `bash -n` ; checks exécutés à vide (sans lab) sous `set -euo pipefail` sans erreur d'exécution, et filtres `jq` testés sur des objets représentatifs.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- le déploiement complet sur six VMs Debian 13 (amorçage, jonctions par le rôle, Cilium, MédiAgenda) : l'environnement de rédaction n'avait ni Proxmox ni cluster ; les sorties montrées sont **représentatives** ;
- le nom de la carte réseau dans l'invité : `eth0`, nommée par la configuration réseau de cloud-init générée par Proxmox (comme pour `vm-debian` au M07 et `vm-noeud` au M10) ; si la tienne s'appelle `ens18`, change `k8s_interface` dans `group_vars/k8s_par1/kubernetes.yml` ;
- le comportement de `kubeadm init phase upload-certs --upload-certs` lancé par le rôle sur un nœud de contrôle **joint** (et non sur celui qui a amorcé) : documenté comme possible sur tout nœud de contrôle, non exécuté ici ;
- la vérification de la chaîne du certificat du kube-apiserver par HAProxy pendant ses contrôles (`verify required ca-file` sur `default-server` avec `http-check connect ssl`) : configuration validée par `haproxy -c`, puis essayée contre un serveur TLS de test (`L7OK` avec la bonne CA, `L6RSP` avec une autre CA : la vérification est bien appliquée) ; pas contre un vrai kube-apiserver sain (un kube-apiserver dont etcd est absent tarde à répondre `/readyz` (contrôle d'etcd en attente) : `L7TOUT`, le serveur reste DOWN, ce qui est le comportement voulu) ;
- `get_url` avec `checksum: sha256:<URL>` sur un fichier de sommes qui ne contient **que** l'empreinte (`krew-linux_amd64.tar.gz.sha256` de la 0.5.0, constaté : une seule ligne de 64 caractères hexadécimaux, sans nom de fichier ; si tu l'automatises) : les autres fichiers de sommes utilisés contiennent bien « empreinte  nom » ;
- `kubeadm init phase kubeconfig super-admin` pour régénérer `super-admin.conf` à partir de la CA (E04, avertissement) : nom de phase lu dans l'aide de kubeadm 1.35, non exécuté ;
- la référence `?ref=v2.3.0` de `plateforme/tofu-modules` : mets l'étiquette réellement publiée par la MR de M10-E02.

---

### M14-E01 — Test de positionnement : Kubernetes

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, relis les « Concepts clés » de l'introduction avant E04 ; les questions 6 à 9 sont reprises en E05 et au M15, 10 à 13 en E04, E06 et E12, 14 à 17 en E03, E05, E24 et E29.

**Réponses argumentées — conteneurs et Linux**

**1. Espaces de noms et cgroups.** `pid` (numérotation des processus : le conteneur voit son processus en PID 1), `net` (interfaces, routes, règles netfilter, ports), `mnt` (points de montage, donc l'arborescence vue), `uts` (nom d'hôte), `ipc` (files de messages, mémoire partagée System V), `user` (correspondance des UID/GID : root dans le conteneur, non privilégié dehors), `cgroup` (vue de la hiérarchie des cgroups). Les **cgroups** ne cachent rien : ils **limitent et comptent** (mémoire, CPU, nombre de processus, E/S). Un conteneur sans cgroup ne voit pas les autres mais peut les affamer ; un conteneur sans espace de noms est limité mais voit tout.

**2. Réponse B.** Tous les conteneurs d'un pod rejoignent l'espace de noms réseau (et IPC) d'un premier conteneur créé par le runtime, le conteneur **pause** (`registry.k8s.io/pause`), qui ne fait que dormir. Ils ont donc la même interface `eth0`, la même adresse, le même `localhost`. A est faux (`127.0.0.1` est local à un espace de noms, il n'y a pas de route à ajouter) ; C est faux (le kubelet ne relaie aucun trafic de données) ; D est faux (un même cgroup ne partage pas le réseau ; chaque conteneur a d'ailleurs son propre cgroup, sous celui du pod).

**3. CRI.** Une API gRPC (*Container Runtime Interface*) entre le kubelet et le runtime : créer un bac à sable de pod, tirer une image, créer et démarrer un conteneur, lire ses journaux. Kubernetes a retiré en 1.24 le *dockershim*, un adaptateur maintenu par le projet lui-même pour parler à Docker, qui n'implémentait pas le CRI ; containerd et CRI-O l'implémentent nativement. Docker, lui, utilise containerd en dessous : on garde le même moteur sans l'étage supplémentaire. Conséquence pratique : sur un nœud, `docker ps` ne montre rien ; c'est `crictl` (ou `ctr -n k8s.io`) qu'on utilise (M14-E44).

**4. Limites.** Mémoire : le cgroup ne peut pas dépasser `memory.max` ; quand il l'atteint et que le noyau ne peut rien récupérer, l'**OOM killer** tue un processus du cgroup (le conteneur est `OOMKilled`, code 137). CPU : le cgroup est **étranglé** (*throttled*) : il n'a plus de temps CPU jusqu'à la période suivante (`cpu.max` : quota par période de 100 ms), il ralentit mais ne meurt pas. Différence de nature : la mémoire n'est pas « compressible » (on ne peut pas reprendre une page sans la perdre ou l'écrire ailleurs), le temps CPU l'est.

**5. Pilote de cgroups.** Avec systemd en init, deux gestionnaires de la même hiérarchie (systemd et le runtime en mode `cgroupfs`) se contredisent : systemd ignore les cgroups créés hors de lui, la vue des ressources du nœud est fausse, et sous pression le kubelet prend de mauvaises décisions. Avec containerd 1.x, un kubelet `systemd` et un containerd `cgroupfs` (la valeur par défaut de containerd : `SystemdCgroup = false`) donnaient des bacs à sable qui ne démarraient pas ou des pods qui redémarraient en boucle : c'était la panne classique. Depuis 1.34 (`KubeletCgroupDriverFromCRI`, stable), le kubelet **demande** le pilote au runtime (appel CRI `RuntimeConfig`, que containerd 2.x implémente) et **ignore** son propre `cgroupDriver` : les deux ne peuvent plus diverger. Le risque se déplace : un containerd resté en `cgroupfs` entraîne le kubelet avec lui, sans erreur visible, et l'on retrouve deux gestionnaires concurrents de la même hiérarchie. D'où `SystemdCgroup = true` imposé et contrôlé par le rôle `containerd` (E02) ; M14-E35 explique pourquoi ce n'est plus une cause de `NotReady`.

**Réponses argumentées — réseau**

**6. Routage et `br_netfilter`.** Les pods ont leurs propres adresses ; un nœud reçoit des paquets pour eux et les fait suivre vers leurs interfaces (veth), ou les envoie vers un autre nœud : c'est du **routage**, interdit par défaut (`ip_forward = 0`). `br_netfilter` fait passer le trafic **ponté** (entre interfaces d'un même pont Linux) par netfilter : sans lui, les règles de kube-proxy en mode iptables (traduction des adresses de Service) ne s'appliquent pas au trafic entre deux pods d'un même nœud reliés par un pont. Avec Cilium, qui n'utilise pas de pont, c'est moins critique, mais kube-proxy est conservé au M14 ; le paramètre `net.bridge.bridge-nf-call-iptables` n'existe d'ailleurs que si le module est chargé.

**7. ClusterIP.** L'adresse du Service est **virtuelle** : kube-proxy (ou Cilium) écrit sur **chaque nœud** des règles (iptables, nftables, ou eBPF) qui, à la sortie du pod client, remplacent l'adresse de destination 10.96.12.7:80 par celle d'un des pods du Service (DNAT), choisi au hasard. Le paquet repart vers une adresse de pod réelle. La réponse est retraduite grâce au suivi de connexions (conntrack). Personne ne « porte » 10.96.12.7 : on ne peut pas la *pinger* utilement, et elle ne marche que depuis un nœud ou un pod du cluster.

**8. Réponse D.** Un NAT source sur l'adresse du nœud **masque** l'adresse du pod émetteur : le pod destinataire voit l'adresse du nœud, pas celle du pod, ce que le modèle réseau de Kubernetes interdit (« tout pod joint tout pod sans NAT »), et la réponse ne saurait pas revenir au bon pod sans état supplémentaire. A (encapsulation : ce que fait Cilium au M14, VXLAN), B (BGP : M15 pour les Services, possible aussi pour les pods) et C (routes statiques entre nœuds d'un même segment : ce que fait le mode « routage natif » de Cilium avec `autoDirectNodeRoutes`, ou flannel *host-gw*) fonctionnent.

**9. `ndots:5`.** Un nom qui a **moins** de cinq points est d'abord essayé avec chaque domaine de recherche : `api.exemple.com.wb-essais.svc.cluster.local`, `api.exemple.com.svc.cluster.local`, `api.exemple.com.cluster.local`, puis les domaines de l'hôte, et enfin `api.exemple.com.` tel quel : jusqu'à six requêtes (et le double en IPv4 + IPv6). C'est la configuration par défaut des pods de Kubernetes, qui privilégie la résolution des noms courts de Services. Pour un nom externe appelé souvent, on écrit un point final (`api.exemple.com.`) ou on règle `dnsConfig`. M14-E42 en fait une panne.

**Réponses argumentées — TLS et PKI**

**10. Vérification du serveur.** Le certificat doit être signé par une autorité en laquelle le client a confiance (chaîne jusqu'à une racine connue : ici la CA du cluster), être en cours de validité, et contenir le **nom demandé** dans ses noms alternatifs (*Subject Alternative Name*, entrée `DNS:k8s-api.par1.medisphere.internal`) ; le champ `CN` n'est plus lu pour cela. Par adresse IP : il faut une entrée `IP Address:10.10.40.200` dans les SAN. D'où `apiServer.certSANs` (le nom **et** la VIP) dans la configuration kubeadm (E04).

**11. TLS mutuel.** Le serveur demande aussi un certificat au **client** et le vérifie contre sa propre liste d'autorités (pour le kube-apiserver : `--client-ca-file`, la CA du cluster). Kubernetes lit le nom d'utilisateur dans le `CN` du sujet et les groupes dans les champs `O` (un par groupe). C'est ainsi que `admin.conf` (O=`kubeadm:cluster-admins`) et ton certificat (O=`medisphere:plateforme-admins`) portent leurs groupes (E04, E06).

**12. Réponse B.** Le kube-apiserver ne consulte ni CRL ni OCSP pour les certificats clients : un certificat valide et signé par la CA est accepté jusqu'à son expiration. Le supprimer du poste (A) ne sert à rien si une copie existe ; le renouveler (C) crée un second certificat sans invalider le premier ; la clé du serveur (D) n'a rien à voir. Les seules parades : retirer les **droits** de ce que le certificat contient (supprimer la liaison RBAC de son groupe ou de son nom, ce qui touche tous les porteurs du groupe), ou changer la CA (tous les certificats du cluster). D'où des certificats **courts** (E06 : 7 jours) et des identités par OIDC à terme (M24).

**13. Certificats courts.** Une révocation exige que chaque serveur consulte une liste ou un répondeur, disponible, à jour, et sache quoi faire quand il ne répond pas (refuser : panne ; accepter : révocation inutile). Un certificat de quelques jours **expire** avant qu'un vol ait beaucoup de valeur, sans infrastructure ni dépendance ; en contrepartie, il faut automatiser le renouvellement (script, `cert-renewer`, ACME). C'est le choix de step-ca au M06 et de nos identités Kubernetes.

**Réponses argumentées — systèmes distribués**

**14. Quorum Raft.** Une écriture est validée quand la **majorité** des membres l'a enregistrée. 3 membres : majorité 2, une panne tolérée. 4 : majorité 3, toujours une seule panne tolérée (et un membre de plus à tomber). 5 : majorité 3, deux pannes. 2 membres : majorité 2, **aucune** panne tolérée, et deux fois plus de chances qu'un membre tombe qu'avec un seul : pire qu'un membre unique. D'où 3 nœuds de contrôle (etcd empilé) pour `k8s-par1`.

**15. Déclaratif.** Impératif : on donne des ordres (« lance trois conteneurs », `docker run` × 3) ; si l'un meurt, personne ne le relance. Déclaratif : on décrit l'état voulu (« ce Deployment a trois réplicas ») et des boucles de contrôle comparent en permanence l'état observé à l'état voulu et corrigent l'écart. On applique le même fichier dix fois sans effet de bord (idempotence), on voit l'écart (`kubectl diff`), on versionne l'état voulu (GitOps, M20). `kubectl create deployment` est un raccourci impératif qui crée un objet déclaratif.

**16. Réponse B.** Élection par **bail** (*lease*) : les instances tentent d'écrire un objet `Lease` (dans `kube-system` pour kube-controller-manager et kube-scheduler) ; celle qui réussit agit et renouvelle son bail toutes les quelques secondes ; les autres attendent son expiration. A rendrait chaque objet dépendant d'une seule instance sans tolérance de panne ; C produirait des actions en double (trois pods créés au lieu d'un) ; etcd ne « résout » pas des conflits applicatifs, il refuse seulement les écritures concurrentes sur une même version. D est ce qu'on veut éviter : une bascule manuelle.

**17. VIP et connexions ouvertes.** Les connexions TCP établies avec l'ancien porteur de la VIP sont **perdues** : le nouveau porteur ne connaît pas leur état et répond par un RST (ou rien). Les clients doivent détecter la coupure et **se reconnecter** : c'est ce que font kubectl, les kubelets et les contrôleurs (les *watch* sont relancés). La bascule n'est donc pas transparente, mais courte (quelques secondes). C'est aussi pourquoi on évite les bascules inutiles (pas de préemption, E03).

**Réponses argumentées — Kubernetes**

**18. Composants.** Nœud de contrôle : **kube-apiserver** (l'API, seul à parler à etcd, authentification, autorisation, admission), **etcd** (stockage des objets), **kube-controller-manager** (boucles de contrôle : Deployments, nœuds, comptes de service, jetons…), **kube-scheduler** (place les pods sur les nœuds) ; on y trouve aussi un kubelet et un runtime, qui font tourner ces composants en pods statiques. Nœud de travail : **kubelet** (fait exister les pods qui lui sont attribués, remonte leur état), **runtime** CRI (containerd), **kube-proxy** (règles des Services ; remplacé par Cilium au M15) et l'agent du **CNI** (Cilium). CoreDNS est une application du cluster, pas un composant de nœud.

**19. Pod, ReplicaSet, Deployment.** Un **Pod** est une instance : s'il meurt ou si son nœud tombe, il n'est pas recréé. Un **ReplicaSet** maintient N pods identiques à son modèle (en recrée si besoin) mais ne sait pas changer de modèle proprement. Un **Deployment** gère des ReplicaSets successifs : changer l'image crée un nouveau ReplicaSet et fait basculer les pods progressivement, avec historique et retour arrière (M14-E16). On ne crée de Pod directement que pour un essai jetable (E07, étape 1) ; même un traitement ponctuel passe par un Job.

**20. `latest` + `Always`.** (1) Pas de **reproductibilité** : deux pods créés à une heure d'écart peuvent tourner sur deux versions différentes, et un redémarrage fait changer la version en production sans aucune décision. (2) Pas de **retour arrière** : revenir à « l'image d'avant » n'a pas de sens si elle s'appelait aussi `latest`. (3) Pas de **traçabilité** ni de politique de confiance : notre signature Cosign (M13) porte sur un **digest**, et nos étiquettes `v*` sont immuables dans Harbor ; `latest` contourne tout cela. (4) `Always` fait dépendre chaque démarrage de pod du registre (panne de Harbor = pods qui ne redémarrent plus). La bonne pratique : une étiquette de version immuable, ou mieux un digest, et la politique par défaut (`IfNotPresent`). M14-E18 interdira `:latest` par une règle d'admission.

---

### M14-E02 — Préparer les nœuds

**Solution**

*A. Avant d'écrire.*

1. kubeadm attend : un Linux compatible (Debian 13, noyau 6.12) en **cgroup v2** (le kubelet 1.35 refuse cgroup v1), 2 vCPU et 1 700 Mo au moins sur un nœud de contrôle, une adresse et un nom d'hôte uniques (ainsi que l'adresse MAC et le `product_uuid` : Proxmox les génère uniques pour des clones complets), la connectivité entre nœuds sur les ports du plan de contrôle et du kubelet, **pas de swap** (sauf configuration explicite), un **runtime CRI** joignable, les modules `overlay` et `br_netfilter`, le routage IPv4, et les paquets `kubelet`, `kubeadm`, `kubectl` de la même version. Ce que chaque élément devient : l'image dorée (cgroup v2, chrony, sudo), les rôles communs (`base` : temps, journal, mises à jour de sécurité ; `ca_lab` : racine MédiSphère), et les deux nouveaux rôles pour le reste.
2. Sur la VM d'essai 2140 :
   ```
   admin@m14-essai:~$ apt-cache policy containerd runc | grep -E '^[a-z]|Candidate'
   containerd:
     Candidate: 1.7.24~ds1-…
   runc:
     Candidate: 1.1.…
   ```
   `RELEASES.md` de containerd : Kubernetes 1.36 exige containerd 2.2 ou plus récent (1.37 : 2.3 ou 2.4). Le paquet de Debian ne convient pas à la version **visée** (1.36 au palier 3) ; on prend `containerd.io` 2.3, branche LTS (prise en charge jusqu'en avril 2028), du dépôt Docker, qui inclut son propre runc 1.5.
3. Trois entrées dans le fichier de données du script de modélisation NetBox (M06-E05), `--dry-run` puis application.

*B. Les VMs.* Fichiers : [`infra/envs/k8s/`](fichiers/M14-E02/infra/envs/k8s/) (`versions.tf`, `providers.tf`, `variables.tf`, `noeuds.tf`, `dns.tf`, `terraform.tfvars.exemple`).

4. La table des nœuds tient en deux `locals` (plan de contrôle, travailleurs) fusionnés avec leurs gabarits ; `k8s-w04` n'apparaît que si `avec_k8s_w04 = true` (E17). La règle commune, écrite en tête de `noeuds.tf` : dernier octet de l'adresse = suffixe, MAC `bc:24:11:40:00:<suffixe>`, VMID écrit en clair. Le plan crée, par nœud : la VM NetBox, son interface, son adresse, l'IP primaire, la VM Proxmox, puis A et PTR : 6 × 7 = 42 ressources. L'ordre vient des références : la VM Proxmox lit l'adresse NetBox, le DNS lit les sorties du module.
   ```
   admin@adm01:~/src/infra/envs/k8s$ tofu plan -out plan.tfplan | tail -3
   Plan: 42 to add, 0 to change, 0 to destroy.
   ```
5. Sur `pve01` :
   ```
   root@pve01:~# qm config 2141 | grep -E '^(name|cores|memory|net0|scsi0|tags|onboot|description)'
   cores: 2
   description: k8s-par1 %3A plan de contrôle … Gérée par OpenTofu (module vm-noeud, plateforme/tofu-modules)…
   memory: 4096
   name: k8s-cp01
   net0: virtio=BC:24:11:40:00:51,bridge=vk8s,firewall=0
   scsi0: local-nvme:vm-2141-disk-0,discard=on,iothread=1,size=40G,ssd=1
   tags: env-k8s;role-k8s-cp
   ```
   Dans le nœud, `ip -br addr` montre `eth0` : la configuration réseau que Proxmox fournit à cloud-init décrit les cartes dans l'ordre et les **nomme** (`eth0`, `eth1`…) en les reconnaissant par leur MAC. C'est le même nommage qu'au M07 (`vm-debian`) ; d'où `k8s_interface: eth0` dans l'inventaire.

*C. Ansible.*

6. [`inventories/lab/netbox-k8s.yml`](fichiers/M14-E02/ansible/inventories/lab/netbox-k8s.yml) et [`ansible.cfg.extrait`](fichiers/M14-E02/ansible/ansible.cfg.extrait). Les `keyed_groups` produisent `env_k8s`, `role_k8s_cp`, `role_k8s_worker` ; les options `groups` (fonctionnalité « construite » du greffon) ajoutent les noms du plan, `k8s_par1`, `k8s_plan_controle`, `k8s_travailleurs`. Pourquoi des noms à part : ce sont des noms de **fonction** stables, utilisés par les rôles, les playbooks et les modules suivants ; les noms dérivés des étiquettes suivent une convention de modélisation qui peut changer (une étiquette renommée ne doit pas casser `k8s-cluster.yml`).
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph k8s_par1
   @k8s_par1:
     |--k8s-cp01
     |--k8s-cp02
     |--k8s-cp03
     |--k8s-w01
     |--k8s-w02
     |--k8s-w03
   ```
7. [`group_vars/k8s_par1/kubernetes.yml`](fichiers/M14-E02/ansible/inventories/lab/group_vars/k8s_par1/kubernetes.yml) et [`containerd.yml`](fichiers/M14-E02/ansible/inventories/lab/group_vars/k8s_par1/containerd.yml). L'image pause d'une version de kubeadm se lit **avant** toute installation avec le binaire seul : `curl -LO https://dl.k8s.io/release/v1.35.9/bin/linux/amd64/kubeadm` (vérifié par `kubeadm.sha256` publié à côté), puis `./kubeadm config images list --kubernetes-version v1.35.9` → `registry.k8s.io/pause:3.10.1`. Pour la 1.36 (E25) : 3.10.2. La valeur est **vérifiée** par le rôle `k8s_noeud`, pas seulement crue.
8. Rôle [`containerd`](fichiers/M14-E02/ansible/roles/containerd/) : `depot.yml` (clé par empreinte, source deb822, **préférence** `Pin: version 2.3.*` de priorité 1001), `configuration.yml` (retrait de `containerd`/`runc` de Debian, `containerd.io=2.3.*`, `config.toml` validé par `containerd --config %s config dump`, `hosts.toml` des miroirs — liste vide —, `crictl.yaml`), `controles.yml` (configuration effective, `crictl info`). Le `config.toml` livré par le paquet ne contient que `disabled_plugins = ["cri"]` (Docker utilise containerd sans CRI) : avec lui, le kubelet ne trouve aucun service CRI sur le socket. `containerd config default | head -1` affiche `version = 4` : containerd 2.3 a son schéma version 4 ; un fichier en version 3 (celui de containerd 2.0, et de la plupart des articles) est lu, mais migré à chaque démarrage avec un avertissement. Le fichier du rôle :
   ```toml
   version = 4
   disabled_plugins = []

   [plugins.'io.containerd.cri.v1.images']
     [plugins.'io.containerd.cri.v1.images'.pinned_images]
       sandbox = 'registry.k8s.io/pause:3.10.1'
     [plugins.'io.containerd.cri.v1.images'.registry]
       config_path = '/etc/containerd/certs.d'

   [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
     runtime_type = 'io.containerd.runc.v2'
     [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
       SystemdCgroup = true
   ```
9. Rôle [`k8s_noeud`](fichiers/M14-E02/ansible/roles/k8s_noeud/) : `preconditions.yml` (Debian 13, version, nom d'hôte, cgroup v2), `systeme.yml` (swap, `fstab`, modules, sysctl), `depot.yml` (dépôt plat `Suites: /`, clé retéléchargée à chaque passage et revérifiée), `paquets.yml` (outils, garde-fou de version, `=1.35.9-1.1`, `hold`, kubelet activé), `controles.yml` (image pause, `kubeadm init phase preflight --dry-run` avec un fichier minimal qui fixe la version). Un dépôt **par mineure** : pkgs.k8s.io publie chaque mineure à part, si bien qu'un `apt upgrade` ne peut jamais faire passer un nœud de 1.35 à 1.36 ; changer de mineure, c'est changer l'URL (E25). Le garde-fou (`k8s_noeud_changement_version`) empêche qu'un changement de `k8s_version` dans l'inventaire, relancé par erreur, mette à jour kubelet et kubeadm sur tous les nœuds sans `kubeadm upgrade` ni drain.
10. Scénario [`molecule/k8s_noeud/`](fichiers/M14-E02/ansible/molecule/k8s_noeud/) : instance 2149 (`debian13`, 2 vCPU, 2 Go, le minimum des contrôles de kubeadm), `converge.yml` (les deux rôles, faits passés en variables), `verify.yml` (états `hi` des paquets, configuration effective, swap, modules, `preflight`).
    ```
    admin@adm01:~/src/ansible$ uv run molecule test -s k8s_noeud
    ```
11. [`playbooks/k8s-noeuds.yml`](fichiers/M14-E02/ansible/playbooks/k8s-noeuds.yml) : un premier jeu sans connexion vérifie l'inventaire (table du plan, adresse, groupe) ; le second applique `base`, `ssh_durci`, `ca_lab`, `ssh_ca_hote`, `ssh_ca_utilisateur`, `containerd`, `k8s_noeud` en `serial: 1`. Pourquoi un nœud à la fois dès maintenant : le playbook sera **rejoué** sur un cluster vivant (correctifs, nouvelle version de containerd) ; un comportement qui change selon que le cluster existe ou non est un piège. Pour le tout premier passage seulement, `-e k8s_noeuds_serie=6` accélère.
    ```
    admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-noeuds.yml --check --diff
    admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-noeuds.yml -e k8s_noeuds_serie=6
    …
    TASK [k8s_noeud : Contrôles préalables de kubeadm (sans rien modifier)] ***
    ok: [k8s-cp01]
    …
    admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-noeuds.yml | tail -8   # changed=0 partout
    ```
12. Sur `k8s-cp01` :
    ```
    root@k8s-cp01:~# kubeadm init phase preflight --dry-run --config /var/lib/k8s_noeud/preflight.yaml
    [preflight] Running pre-flight checks
    [preflight] Would pull the required images (like 'kubeadm config images pull')
    root@k8s-cp01:~# rm -rf /etc/kubernetes/tmp/kubeadm-init-dryrun*
    ```
    Les avertissements possibles et leur sens : `Service-kubelet` (kubelet non activé : le rôle l'active), `Hostname … could not be reached` (le nom court ne se résout pas : vérifier le domaine de recherche posé par cloud-init), `HTTPProxy` (une variable `https_proxy` dans l'environnement : à proscrire, voir les pièges). `crictl info` doit montrer `RuntimeReady: true` et `NetworkReady: false` (« cni plugin not initialized ») : normal avant le CNI (E05).
13. Matrice des flux : rien sur les passerelles. Les nœuds sortent vers Internet et vers `reg01` par des règles déjà ouvertes ; le reste est interne au VLAN 40 (extrait en E03). Registre des secrets : rien de nouveau, aucun secret n'a été créé (les clés de dépôt sont **publiques**, leurs empreintes ne sont pas secrètes).

Le check vérifie, pour chaque nœud, la configuration Proxmox, le DNS, NetBox, le système (version, nom, cgroup v2, swap, modules, sysctl), le runtime (paquet, épinglage, configuration effective, image pause comparée à celle de kubeadm, `crictl info`), les paquets Kubernetes (version et `hold`), puis le code sur `main`. Il ne relance pas les contrôles préalables de kubeadm : même en `--dry-run`, ils écrivent dans `/etc/kubernetes/tmp/`.

**Explications**

- **Un runtime choisi par la version visée, pas par le confort.** Le containerd de Debian aurait fonctionné en 1.35, puis bloqué la montée en 1.36 (E25) : on aurait dû changer de runtime **sous** un cluster en service. Prendre tout de suite la branche LTS de containerd compatible avec la cible évite une migration risquée.
- **Configuration minimale, contrôle de l'effectif.** Écrire `containerd config default` en entier dans un gabarit fige aussi des centaines de valeurs par défaut qui changeront à la version suivante. Le fichier du rôle ne contient que nos décisions ; `containerd config dump` montre la fusion, et c'est **elle** que le contrôle compare à l'inventaire.
- **Épingler deux fois, différemment.** containerd.io : une préférence APT, parce qu'on veut les correctifs de la branche 2.3 (sécurité) sans changer de branche. Kubernetes : la version exacte et `hold`, parce que tout changement de version est une procédure (E25) ; en prime, le dépôt par mineure rend une montée accidentelle de mineure impossible.
- **Les contrôles de kubeadm comme critère.** `kubeadm init phase preflight` vérifie ce que kubeadm vérifiera au moment réel (runtime, version, ports, swap, modules, cgroups), avec les mêmes règles que lui : c'est un meilleur juge qu'une liste maison. Le `--dry-run` évite qu'il tire les images ; le fichier minimal évite qu'il interroge Internet pour « stable-1 ».

**Alternatives**

- **CRI-O** au lieu de containerd : runtime pensé pour Kubernetes seulement, versions alignées sur celles de Kubernetes (un dépôt par mineure, comme pkgs.k8s.io), utilisé par OpenShift. Défendable ; on garde containerd, déjà étudié au M12 (Docker 29 l'utilise) et LTS.
- **Le containerd de Debian rétroporté** (`trixie-backports`) : s'il existait en 2.x, il éviterait un dépôt tiers ; à surveiller, pas disponible à la rédaction.
- **kubespray** (Ansible de la communauté) : prépare et installe tout, multi-distributions, avec des centaines de variables. Bon outil, mais on veut ici comprendre chaque étape ; on le relira au M18.
- **Inventaire statique** du cluster : rapide, mais une seconde vérité à côté de NetBox (M06).

**Pièges classiques**

- Garder le `config.toml` du paquet `containerd.io` : le CRI est désactivé, `crictl info` échoue, kubeadm refuse (« container runtime is not running »).
- Un `config.toml` copié d'un article sur containerd 1.7 (`[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]`) : containerd 2.3 le migre ou ignore des clés, et `SystemdCgroup` peut rester à `false` sans erreur visible. Toujours vérifier `containerd config dump`.
- Une image pause différente de celle de kubeadm : simple avertissement de kubeadm, mais deux images tirées et une dépendance de plus à un registre (au M14-E19, la pause doit être dans le cache Harbor).
- `apt-mark hold` oublié : `apt upgrade` (ou `unattended-upgrades`, si le dépôt tombait dans ses origines) met à jour kubelet avant le plan de contrôle : le kubelet ne peut pas être plus récent que le kube-apiserver.
- Une variable `http_proxy`/`https_proxy` dans l'environnement de `root` au moment de `kubeadm init` : kubeadm la **recopie** dans les manifestes statiques du plan de contrôle (constaté à la rédaction avec `--dry-run`) ; le kube-apiserver enverrait alors son trafic vers ce mandataire. Sur les nœuds du lab, il n'y en a pas : vérifie quand même `env | grep -i proxy`.
- Une clé de dépôt expirée (celle de pkgs.k8s.io expire le 29/12/2026 sauf prolongation) : `apt update` refuse le dépôt (`EXPKEYSIG`). Le rôle retélécharge la clé et revérifie l'empreinte à chaque passage.
- Un pare-feu local (rôle `pare_feu_local` du M06) appliqué aux nœuds : il réécrit tout le jeu de règles nftables et efface celles de kube-proxy et de Cilium. Ces nœuds n'en ont pas (voir la matrice des flux).

**En production chez MédiSphère**

Des serveurs dédiés aux nœuds de contrôle (CPU et disque rapides pour etcd : la latence d'écriture du disque d'etcd est le premier indicateur de santé du cluster), des travailleurs dimensionnés par profil de charge, un dépôt APT **miroir** interne (pkgs.k8s.io, Docker) pour ne pas dépendre d'Internet ni d'une clé qui expire un jour de mise en production, et une image dorée « nœud Kubernetes » construite par Packer avec les deux rôles (le démarrage d'un nouveau nœud passe de vingt minutes à deux). Les versions de containerd et de Kubernetes sont suivies par Renovate (M13) et la politique de versions (ADR-0141, E30).

---

### M14-E03 — Le point d'accès de l'API : keepalived et HAProxy

**Solution**

1. `controlPlaneEndpoint` est écrit par `kubeadm init` dans **tous** les kubeconfigs (kubelets, contrôleurs, `admin.conf`), dans le ConfigMap `kubeadm-config` et, par son nom et son adresse, dans le certificat du kube-apiserver. Un cluster amorcé sans lui pointe partout vers l'adresse de `k8s-cp01` : le rendre redondant ensuite demanderait de régénérer certificats et kubeconfigs sur chaque nœud. Le port de la VIP diffère de 6443 parce qu'HAProxy tourne **sur** les nœuds de contrôle, où kube-apiserver écoute déjà 6443 sur toutes les adresses (y compris la VIP quand le nœud la porte) : deux processus ne peuvent pas écouter la même adresse et le même port. La documentation kubeadm (« ha-considerations ») propose exactement ce montage, avec 8443.
2. [`infra/envs/k8s/api.tf`](fichiers/M14-E03/infra/envs/k8s/api.tf) : `netbox_ip_address` de rôle `vip`, sans interface, et `enregistrement-dns` avec `ptr = false`. Pas de PTR : l'adresse ne désigne pas une machine ; un PTR « `k8s-api` » serait vrai pour le service mais trompeur dans un journal (on croirait qu'un hôte s'appelle ainsi) ; aucun composant ne lit ce PTR.
3. Rôle [`k8s_plan_controle`](fichiers/M14-E03/ansible/roles/k8s_plan_controle/), fichier `tasks/point_acces.yml` : un `stat` de `/etc/kubernetes/pki/ca.crt`, la construction des lignes `server` (une par nœud de contrôle, depuis `k8s_noeuds`), puis deux `include_role` avec des `vars:` de tâche. Les sections rendues sur `k8s-cp02` **avant** l'amorçage :
   ```
   frontend fe_k8s_api
       bind 10.10.40.200:8443
       mode tcp
       option tcplog
       timeout client 1h
       default_backend be_k8s_api

   backend be_k8s_api
       mode tcp
       balance roundrobin
       timeout server 1h
       default-server inter 3s fall 3 rise 2
       server k8s-cp01 10.10.40.51:6443 check
       server k8s-cp02 10.10.40.52:6443 check
       server k8s-cp03 10.10.40.53:6443 check
   ```
   et, dès que la CA existe sur le nœud :
   ```
       option httpchk
       http-check connect ssl
       http-check send meth GET uri /readyz
       http-check expect status 200
       default-server inter 3s fall 3 rise 2 verify required ca-file /etc/kubernetes/pki/ca.crt
   ```
   Le keepalived rendu : `vrrp_instance VI_K8S_API` sur `eth0`, `virtual_router_id 140`, priorité du nœud, `nopreempt`, `unicast_src_ip` du nœud et les deux autres en `unicast_peer`, VIP `10.10.40.200/24`, `track_script chk_haproxy`. Si le contrôle était tout de suite en HTTPS vérifié : avant l'amorçage, `ca-file /etc/kubernetes/pki/ca.crt` n'existe pas et `haproxy -c` **refuse** la configuration (fichier introuvable) ; le rôle échouerait, et sur `k8s-cp02`/`k8s-cp03` jusqu'à leur jonction. D'où le contrôle qui s'adapte.
4. [`playbooks/k8s-cluster.yml`](fichiers/M14-E03/ansible/playbooks/k8s-cluster.yml) (version E03) : `serial: 1`, `order: sorted`, `any_errors_fatal: true`, puis un jeu qui compte les porteurs de la VIP.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-cluster.yml --tags point_acces --check --diff
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-cluster.yml --tags point_acces
   ```
5. Observations :
   ```
   == k8s-cp01
   eth0             UP             10.10.40.51/24 10.10.40.200/24
   == k8s-cp02
   eth0             UP             10.10.40.52/24
   …
   admin@adm01:~$ ssh k8s-cp01 'echo "show stat" | sudo socat stdio unix-connect:/run/haproxy/admin.sock' | cut -d, -f1,2,18,37
   # pxname,svname,status,check_status
   fe_k8s_api,FRONTEND,OPEN,
   be_k8s_api,k8s-cp01,DOWN,L4CON
   be_k8s_api,k8s-cp02,DOWN,L4CON
   be_k8s_api,k8s-cp03,DOWN,L4CON
   be_k8s_api,BACKEND,DOWN,
   admin@adm01:~$ curl -v --max-time 5 https://k8s-api.par1.medisphere.internal:8443/
   *   Trying 10.10.40.200:8443...
   * Connected to k8s-api.par1.medisphere.internal (10.10.40.200) port 8443
   * TLS handshake … 
   * OpenSSL SSL_connect: Connection reset by peer / unexpected eof
   ```
   `k8s-cp01` porte la VIP : il a la plus haute priorité et, tous partant en BACKUP, l'élection initiale lui revient (s'il a démarré son keepalived en premier ou en même temps ; un nœud lancé seul plus tôt peut aussi la garder, sans préemption). Les serveurs sont `DOWN` (`L4CON` : connexion TCP refusée) : rien n'écoute 6443. `curl` : la connexion **TCP** réussit (HAProxy accepte sur le frontend), puis HAProxy, sans serveur disponible, ferme la connexion : la négociation **TLS** échoue. Un client qui ne verrait que « connection reset » pourrait croire à un problème de certificat : c'est un point d'accès sans backend.
6. Bascule : HAProxy arrêté sur `k8s-cp01`, le script `chk_haproxy` échoue deux fois, l'instance passe en FAULT, `k8s-cp02` (120) prend la VIP (`Entering MASTER STATE`). HAProxy relancé : `k8s-cp01` repasse BACKUP **et ne reprend pas** la VIP (`nopreempt`) ; c'est voulu : une bascule de moins, donc moins de connexions coupées. La VIP restera sur `k8s-cp02` jusqu'à sa prochaine panne ou une intervention.
7. Matrice des flux : [`matrice-flux.md.extrait`](fichiers/M14-E03/medisphere/docs/socle/matrice-flux.md.extrait) (palier 1 entier). Aucune règle de bordure nouvelle : `adm01` → VIP:8443 passe par la règle MGMT → tout.

Le check vérifie DNS et NetBox, l'unicité du porteur de la VIP, la connexion TCP depuis `adm01`, puis sur chaque nœud de contrôle : keepalived (actif, `keepalived -t`, VRID, source, pairs, `nopreempt`, suivi), HAProxy (actif, `haproxy -c`, écoute de la VIP, mode TCP, trois serveurs contrôlés sans maintenance), et le code. Il ne demande **pas** que les serveurs soient DOWN : il reste vert après l'amorçage.

**Explications**

- **TCP de bout en bout.** HAProxy ne termine pas le TLS : le client négocie directement avec un kube-apiserver. C'est indispensable à l'authentification par **certificat client** (le kube-apiserver doit voir le certificat du client) et aux connexions longues (*watch*, `exec` et `port-forward` en flux). D'où `mode tcp` et des délais d'une heure.
- **Contrôle de santé.** Un kube-apiserver peut accepter des connexions TCP sans être prêt (démarrage, etcd injoignable) : `/readyz` en dit plus. Le vérifier en HTTPS **vérifié** évite d'envoyer du trafic vers un usurpateur et respecte la règle « jamais `verify none` ». `/readyz` étant lisible sans authentification, HAProxy n'a besoin d'aucune identité.
- **Les rôles du M07, sans copier-coller.** `k8s_plan_controle` ne réécrit ni keepalived ni HAProxy : il calcule leurs données et les leur passe. Une correction du rôle `haproxy` (TLS, rechargement) profite aussi au cluster.

**Alternatives**

- **kube-vip** en pod statique : VIP (ARP ou BGP) et répartition, sans paquet sur l'hôte ; mais le pod a besoin de l'API pour son élection… pendant que l'API démarre ; depuis 1.29, `admin.conf` n'a plus de droits avant la fin de l'amorçage, d'où le contournement par `super-admin.conf` (documenté par kube-vip). Discuté dans l'ADR-0140.
- **Répartiteurs dédiés** (`lb01`/`lb02` du M07, ou deux VMs HAProxy de plus) : plan de contrôle et point d'accès séparés, panne d'un nœud de contrôle sans bascule de VIP ; un saut réseau de plus, et `lb01`/`lb02` sont dans la DMZ, pas faits pour l'API interne.
- **DNS à plusieurs adresses** (trois A pour `k8s-api`) : pas de VIP, mais les clients gardent l'adresse morte jusqu'à l'expiration du cache et ne savent pas tous essayer la suivante.
- **Répartiteur côté client** (chaque nœud a un HAProxy local vers les trois API, comme le fait kubespray) : pas de VIP du tout, mais les humains et les outils extérieurs ont toujours besoin d'un point d'accès.

**Pièges classiques**

- HAProxy qui écoute **6443** sur la VIP : conflit avec kube-apiserver, sur le seul nœud qui porte la VIP, au moment exact de l'amorçage.
- `net.ipv4.ip_nonlocal_bind` absent : HAProxy ne démarre pas sur les nœuds qui ne portent pas la VIP (`cannot bind socket`), et keepalived les met en FAULT (script de suivi) : plus aucun candidat.
- Un contrôle `option httpchk` en HTTP clair vers 6443 : le kube-apiserver ne parle que TLS ; tous les serveurs restent DOWN après l'amorçage.
- `verify none` « en attendant » : il reste. Le contrôle qui s'adapte à l'état du nœud règle le problème proprement.
- Un VRID déjà pris sur le VLAN 40 : celui de la passerelle du VLAN 40 est **40** (M07-E25). Deux instances avec le même VRID sur un segment se disputent la même MAC virtuelle (`00:00:5e:00:01:<VRID>`).
- Croire que le test de bascule échoue parce que la VIP ne revient pas : c'est l'effet voulu de `nopreempt`.

**En production chez MédiSphère**

Supervision de l'état VRRP (qui est MASTER, nombre de transitions) et des backends d'HAProxy (métriques Prometheus d'HAProxy, M21), alerte si la VIP change plus d'une fois par heure ou si moins de deux backends sont UP. Le runbook RB-140 et ses suivants commencent par « qui porte la VIP ». À plus grande échelle, la VIP de l'API peut être annoncée en BGP par les nœuds de contrôle vers les routeurs (comme les Services au M15), ce qui supprime la contrainte du même segment.

---

### M14-E04 — Amorcer le cluster avec kubeadm

**Solution**

*A. Le projet et le fichier.*

1. Projet : [`k8s/`](fichiers/M14-E04/k8s/) (`README.md`, `.gitignore`, `.yamllint.yaml`, `secrets/README.md`). Changements de forme de v1beta4 par rapport à v1beta3 : `extraArgs` (apiServer, controllerManager, scheduler, etcd) et `nodeRegistration.kubeletExtraArgs` deviennent des **listes** `{name, value}` (on peut répéter un argument) ; les délais sont regroupés dans `timeouts` (`controlPlaneComponentHealthCheck`, `discovery`, `kubeletHealthCheck`…), `apiServer.timeoutForControlPlane` disparaît ; apparaissent `certificateValidityPeriod`, `caCertificateValidityPeriod`, `encryptionAlgorithm`, `imagePullSerial` ; `UpgradeConfiguration` et `ResetConfiguration` existent. v1beta3 est dépréciée (supprimée en 1.37) : `kubeadm config migrate` convertit un ancien fichier.
2. [`cluster/kubeadm-config.yaml`](fichiers/M14-E04/k8s/cluster/kubeadm-config.yaml) : trois documents, commentés. Pas de `---` en tête : le rôle place le séparateur après l'InitConfiguration du nœud, et un document fait seulement de commentaires est refusé par kubeadm (« kind and apiVersion is mandatory »).
3. Seconde partie du rôle, `tasks/kubeadm.yml` : `lookup('file', …)` sur le contrôleur, contrôles de forme (`ClusterConfiguration` présente, pas d'`InitConfiguration`, bon `controlPlaneEndpoint`, pas de `---` initial), gabarit [`kubeadm-config.yaml.j2`](fichiers/M14-E03/ansible/roles/k8s_plan_controle/templates/kubeadm-config.yaml.j2) validé par `kubeadm config validate --config %s`, recherche d'un nœud qui porte `admin.conf` (sur les trois, par `delegate_to`), amorçage seulement si `k8s_plan_controle_amorcage_auto` et sur le premier nœud. En E04 :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-cluster.yml --tags kubeadm \
       -e k8s_plan_controle_fichier_cluster=$HOME/src/k8s/cluster/kubeadm-config.yaml
   …
   TASK [k8s_plan_controle : Aucun cluster et amorçage non demandé] ***
   ok: [k8s-cp01] => msg: Aucun nœud de contrôle ne porte de cluster. Le fichier … est prêt ; l'amorçage est un geste explicite…
   ```

*B. L'amorçage.*

4. `kubeadm config validate` répond `ok` ; `images pull` tire les sept images (`kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `kube-proxy` en v1.35.9, `coredns:v1.13.1`, `pause:3.10.1`, `etcd:3.6.6-0`) ; le `--dry-run` affiche les manifestes et les objets qui seraient créés (constaté à la rédaction : avertissement « port specified in controlPlaneEndpoint overrides bindPort in the controlplane address » sur chaque kubeconfig, attendu et sans conséquence).
5. Amorçage, phases dans l'ordre :

   | Phase | Ce qu'elle produit |
   |---|---|
   | `preflight` | les contrôles de E02, plus le tirage des images |
   | `certs` | CA du cluster, d'etcd, du *front-proxy* ; certificats du kube-apiserver (SAN : nom du nœud, `kubernetes.default…`, 10.96.0.1, 10.10.40.51, le nom et la VIP), du client kubelet, d'etcd (serveur, pair, santé), client etcd du kube-apiserver ; paire `sa.key`/`sa.pub` |
   | `kubeconfig` | `admin.conf`, `super-admin.conf`, `kubelet.conf`, `controller-manager.conf`, `scheduler.conf` |
   | `etcd` | manifeste statique `etcd.yaml` |
   | `control-plane` | manifestes `kube-apiserver.yaml`, `kube-controller-manager.yaml`, `kube-scheduler.yaml` |
   | `kubelet-start` | `/var/lib/kubelet/config.yaml`, `kubeadm-flags.env`, redémarrage du kubelet |
   | `wait-control-plane` | attente des contrôles de santé des composants (quelques dizaines de secondes) |
   | `upload-config` | ConfigMaps `kubeadm-config` et `kubelet-config` |
   | `upload-certs` | Secret `kubeadm-certs` (certificats partagés chiffrés, deux heures) et la clé |
   | `mark-control-plane` | étiquette et *taint* `node-role.kubernetes.io/control-plane` |
   | `bootstrap-token` | jeton, RBAC de l'amorçage TLS des kubelets, ConfigMap `cluster-info` |
   | `kubelet-finalize` | rotation du certificat client du kubelet |
   | `addon` | CoreDNS, kube-proxy |
   | `show-join-command` | les commandes de jonction (jeton et clé : **secrets**) |

   Personne n'a « démarré » le plan de contrôle par l'API : c'est le **kubelet**, qui surveille `/etc/kubernetes/manifests/` (`staticPodPath` de sa configuration) et lance ce qu'il y trouve.
6. Sur `k8s-cp02`, `show stat` : `k8s-cp01` passe `UP` dès que 6443 accepte les connexions (contrôle TCP, quelques secondes après le démarrage du kube-apiserver). Après avoir rejoué `--tags point_acces` sur `k8s-cp01`, son `haproxy.cfg` passe en contrôle `/readyz` HTTPS vérifié : la CA existe maintenant **sur ce nœud** (sur `k8s-cp02`/`k8s-cp03`, ce sera après leur jonction, E05).

*C. Lire ce que kubeadm a écrit.*

7. Options de `kube-apiserver.yaml` : etcd (`--etcd-servers=https://127.0.0.1:2379`, `--etcd-cafile`, `--etcd-certfile`, `--etcd-keyfile`) ; clients (`--client-ca-file=/etc/kubernetes/pki/ca.crt`, `--kubelet-client-certificate/-key` pour parler aux kubelets, `--requestheader-*` et `--proxy-client-*` pour l'agrégation d'API) ; comptes de service (`--service-account-issuer`, `--service-account-key-file=sa.pub`, `--service-account-signing-key-file=sa.key`) ; autorisation (`--authorization-mode=Node,RBAC`, `--enable-admission-plugins=NodeRestriction`). Le kubelet lit le dossier parce que sa configuration (`/var/lib/kubelet/config.yaml`) contient `staticPodPath: /etc/kubernetes/manifests`.
8. `kubeadm certs check-expiration` : les certificats feuilles et kubeconfigs expirent dans un an, les trois CA (`ca`, `etcd-ca`, `front-proxy-ca`) dans dix. La CA du cluster signe le kube-apiserver, les clients (kubelets, admins, contrôleurs) ; celle d'etcd, les certificats d'etcd et le client etcd du kube-apiserver ; celle du *front-proxy*, le client utilisé par l'agrégation d'API (metrics-server, E20).
   ```
   root@k8s-cp01:~# openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -ext subjectAltName
   X509v3 Subject Alternative Name:
       DNS:k8s-api.par1.medisphere.internal, DNS:k8s-cp01, DNS:kubernetes, DNS:kubernetes.default, DNS:kubernetes.default.svc, DNS:kubernetes.default.svc.cluster.local, IP Address:10.96.0.1, IP Address:10.10.40.51, IP Address:10.10.40.200
   ```
9. Sujets :
   ```
   root@k8s-cp01:~# for f in admin super-admin; do grep client-certificate-data /etc/kubernetes/$f.conf | awk '{print $2}' | base64 -d | openssl x509 -noout -subject; done
   subject=O = kubeadm:cluster-admins, CN = kubernetes-admin
   subject=O = system:masters, CN = kubernetes-super-admin
   ```
   `admin.conf` passe par le RBAC : la ClusterRoleBinding `kubeadm:cluster-admins` lie ce groupe à `cluster-admin` (créée pendant `kubeadm init`, en utilisant `super-admin.conf` justement). `super-admin.conf` porte `system:masters`, un groupe que le kube-apiserver **autorise d'office**, avant même le RBAC. Si quelqu'un supprimait `kubeadm:cluster-admins`, `admin.conf` perdrait tous ses droits ; `super-admin.conf` resterait tout-puissant : c'est l'outil de réparation de ce cas précis, et la raison pour laquelle Sophie ne veut le voir nulle part.
10. `kubeadm-flags.env` : `KUBELET_KUBEADM_ARGS="--hostname-override=k8s-cp01 --node-ip=10.10.40.51"` (le `node-ip` vient de notre InitConfiguration) ; `systemctl cat kubelet` montre le complément `10-kubeadm.conf` qui ajoute `--bootstrap-kubeconfig`, `--kubeconfig=/etc/kubernetes/kubelet.conf`, `--config=/var/lib/kubelet/config.yaml` et ce fichier d'environnement ; kubeadm 1.35 écrit aussi `/var/lib/kubelet/instance-config.yaml` (configuration propre à l'instance). ConfigMaps : `kubeadm-config` (la ClusterConfiguration, celle que relira `kubeadm upgrade`), `kubelet-config` (la KubeletConfiguration commune, distribuée aux nœuds qui rejoignent), `kube-proxy` (`config.conf` avec `mode: iptables`).
11. `NotReady` : condition `Ready=False`, message « container runtime network not ready: … cni plugin not initialized ». Aucun CNI n'a écrit de configuration dans `/etc/cni/net.d/` : le kubelet ne peut pas créer de bac à sable de pod réseau ordinaire. Les pods statiques (réseau de l'hôte) tournent ; CoreDNS (réseau de pod) attend un nœud prêt : `Pending`. Pas grave, c'est l'état attendu jusqu'à Cilium (E05).

*D. Les secrets.*

12. Chiffrement sans passage en clair sur le disque d'`adm01` :
    ```
    admin@adm01:~/src/ansible$ ssh k8s-cp01 sudo cat /etc/kubernetes/admin.conf \
        | uv run ansible-vault encrypt --encrypt-vault-id critique --output ~/src/k8s/secrets/admin.conf.vault -
    admin@adm01:~/src/ansible$ ssh k8s-cp01 sudo cat /etc/kubernetes/super-admin.conf \
        | uv run ansible-vault encrypt --encrypt-vault-id critique --output ~/src/k8s/secrets/super-admin.conf.vault -
    admin@adm01:~/src/ansible$ head -1 ~/src/k8s/secrets/admin.conf.vault
    $ANSIBLE_VAULT;1.2;AES256;critique
    admin@adm01:~/src/ansible$ uv run ansible-vault view ~/src/k8s/secrets/super-admin.conf.vault | head -3
    ```
    MR, fusion, puis sur `k8s-cp01` : `shred -u /etc/kubernetes/super-admin.conf`. kubeadm ne le crée que sur le nœud qui a amorcé ; les autres nœuds de contrôle n'auront que `admin.conf`.
13. Registre des secrets : [`registre-secrets.md.extrait`](fichiers/M14-E06/medisphere/docs/socle/registre-secrets.md.extrait) (lignes de E04 et E06).

Le check vérifie les fichiers de `k8s-cp01` (manifestes, fichier kubeadm en 600, `admin.conf` en 600, `super-admin.conf` absent, SAN, durée de la CA, kubelet), `/readyz` par la VIP en TLS vérifié, la configuration enregistrée (`kubeadm-config`, `kube-proxy`, version du nœud, liaison `kubeadm:cluster-admins`), puis le dépôt (fichier du cluster, deux secrets chiffrés en identité `critique`, aucun fichier sensible en clair). Avant E06, il lit le cluster par SSH avec `admin.conf` (commandes `get` seulement) et le signale.

**Explications**

- **Fichier du cluster d'un côté, nœud de l'autre.** Ce qui est commun (version, point d'accès, réseaux, composants) est relu en MR dans `plateforme/k8s` ; ce qui est propre au nœud (adresse annoncée, nom, `node-ip`) est calculé par le rôle à partir de la table des nœuds. Un seul fichier du cluster sert à l'amorçage, aux commandes de phase et, plus tard, à la reconstruction.
- **L'amorçage automatique est désactivé par défaut.** Un `kubeadm init` lancé par erreur sur un nœud qui ne voit pas les autres (réseau coupé) créerait un **second** cluster. Le rôle ne le fait que si on le lui demande explicitement (reconstruction depuis le code, E23, E46), et seulement s'il ne trouve `admin.conf` sur aucun nœud de contrôle.
- **Deux kubeconfigs d'administration depuis 1.29.** Avant, `admin.conf` portait `system:masters` : impossible de retirer ce droit à une copie qui a fuité. kubeadm a séparé l'usage courant (RBAC, révocable par la liaison) et le bris de glace ultime.

**Alternatives**

- **Drapeaux de `kubeadm init`** (`--control-plane-endpoint`, `--pod-network-cidr`…) : rapide pour un essai, mais rien n'est relu ni versionné, et certains réglages n'existent qu'en fichier.
- **Garder `super-admin.conf` sur le nœud** (comportement par défaut) : pratique pour réparer, mais toute personne root sur `k8s-cp01` (ou une sauvegarde de la VM) le possède. La copie chiffrée suffit ; la régénération à partir de la CA reste possible.
- **etcd externe** (trois VMs de plus, `etcd.external` dans la ClusterConfiguration) : panne d'un nœud de contrôle sans toucher etcd, mais six VMs pour le plan de contrôle et une PKI de plus. ADR-0140.

**Pièges classiques**

- Oublier `controlPlaneEndpoint` (ou le mettre sur l'adresse de `k8s-cp01`) : le cluster fonctionne… jusqu'à la perte de `k8s-cp01`.
- Mettre `podSubnet` en conflit avec un réseau existant (10.10.0.0/16, 10.20.0.0/16, 10.255.0.0/16) : des pods injoignables depuis le lab, ou des routes qui en cachent d'autres. 10.240.0.0/16 et 10.96.0.0/16 sont libres dans le plan d'adressage.
- Coller la sortie de `kubeadm init` dans un ticket : elle contient de quoi joindre un nœud de **contrôle** au cluster pendant deux heures (jeton + clé), c'est-à-dire récupérer la CA.
- Laisser le dossier du `--dry-run` sous `/etc/kubernetes/tmp/` : il contient une PKI de démonstration ; inoffensif mais trompeur au diagnostic.
- `kubectl` sur le nœud avec `KUBECONFIG=/etc/kubernetes/super-admin.conf` « parce que ça marche » : tout ce qui suit contourne le RBAC et l'audit le montrera (E27).
- Chiffrer avec l'identité `lab` au lieu de `critique` : `admin.conf` vaut le cluster entier, il relève de la même identité que `client.admin` de Ceph (M08) et les clés WireGuard de la bordure (M07).

**En production chez MédiSphère**

L'amorçage d'un cluster de production est une **procédure écrite** (fiche CHG, deux personnes) : fichier relu, `--dry-run` archivé, sortie de l'amorçage capturée dans un fichier chiffré puis détruite. `super-admin.conf` est découpé en deux parts (Vault et coffre physique) ou n'est pas conservé du tout : la régénération à partir de la CA, elle-même hors ligne, est le seul chemin. Le chiffrement des Secrets dans etcd (E28) et l'audit (E27) sont dans la configuration **dès** l'amorçage, pas ajoutés après.

---

### M14-E05 — Joindre les nœuds et installer Cilium

**Solution**

*A. Les outils de adm01.*

1. Rôle [`outils_k8s`](fichiers/M14-E05/ansible/roles/outils_k8s/) et [`playbooks/outils-k8s.yml`](fichiers/M14-E05/ansible/playbooks/outils-k8s.yml). Paquets : `kubectl=1.36.5-1.1` (retenu) et `helm=4.3.*`, clés vérifiées. Binaires : `get_url` avec `checksum: sha256:<URL du fichier de sommes>`, extraction dans `/opt/outils_k8s/<outil>-<version>/`, liens dans `/usr/local/bin`. Cette organisation garde l'ancienne version à côté de la nouvelle : un retour arrière est un changement de version dans l'inventaire, et `ls -l /usr/local/bin/cilium` dit laquelle est active. kubectl 1.36 contre un cluster 1.35 : la politique de compatibilité de Kubernetes accepte un client d'une mineure **au-dessus ou au-dessous** du kube-apiserver ; on prend tout de suite la version de la cible (E25), et kubectl 1.37 serait déjà hors politique avec un cluster 1.35.

*B. Joindre à la main.*

2. Sur `k8s-cp01` :
   ```
   root@k8s-cp01:~# kubeadm token create --ttl 30m --description "jonction manuelle k8s-cp02, k8s-w01 (E05)"
   7f3k2a.<16 caractères>
   root@k8s-cp01:~# kubeadm init phase upload-certs --upload-certs
   [upload-certs] Storing the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
   [upload-certs] Using certificate key:
   <64 caractères hexadécimaux>
   root@k8s-cp01:~# openssl x509 -pubkey -noout -in /etc/kubernetes/pki/ca.crt | openssl pkey -pubin -outform der | openssl dgst -sha256 -hex | sed 's/^.* //'
   <64 caractères hexadécimaux>
   ```
   La clé affichée par `kubeadm init --upload-certs` n'a plus cours si l'amorçage date de plus de deux heures (le Secret `kubeadm-certs` est supprimé à l'expiration) : on en produit une nouvelle. Ce que chacun protège :
   - le **jeton** authentifie le nœud qui arrive auprès de l'API (groupe `system:bootstrappers`) : il ne permet que de lire `cluster-info` et de demander un certificat de kubelet ; un voleur de jeton pourrait enregistrer un faux nœud pendant sa durée de vie ;
   - l'**empreinte de la CA** protège le nœud qui arrive : il vérifie que l'API qu'il contacte présente bien **notre** CA (un faux point d'accès ne la connaît pas) ; elle n'est pas secrète ;
   - la **clé de certificats** déchiffre le Secret `kubeadm-certs` qui contient la CA du cluster, celle d'etcd, celle du *front-proxy* et `sa.key` : avec le jeton, elle donne la PKI entière. C'est le secret le plus sensible de l'opération.
3. Sur `k8s-cp02` (une espace en tête de ligne, `HISTCONTROL=ignorespace`) :
   ```
   root@k8s-cp02:~#  kubeadm join k8s-api.par1.medisphere.internal:8443 --token 7f3k2a.<…> \
       --discovery-token-ca-cert-hash sha256:<empreinte> \
       --control-plane --certificate-key <clé> --apiserver-advertise-address 10.10.40.52
   …
   This node has joined the cluster and a new control plane instance was created
   ```
   Membres etcd :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n kube-system exec etcd-k8s-cp01 -- etcdctl --endpoints=https://127.0.0.1:2379 \
       --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
       --key=/etc/kubernetes/pki/etcd/healthcheck-client.key member list -w table
   +------------------+---------+----------+--------------------------+--------------------------+------------+
   |        ID        | STATUS  |   NAME   |        PEER ADDRS        |       CLIENT ADDRS       | IS LEARNER |
   | 5c2d…            | started | k8s-cp01 | https://10.10.40.51:2380 | https://10.10.40.51:2379 |      false |
   | a91e…            | started | k8s-cp02 | https://10.10.40.52:2380 | https://10.10.40.52:2379 |      false |
   ```
   Deux membres : le quorum est maintenant **2 sur 2**, aucune panne tolérée. Pas de pause entre le deuxième et le troisième nœud de contrôle.
4. Sur `k8s-w01` : la même commande sans `--control-plane` ni `--certificate-key`. Un travailleur reçoit la CA du cluster (pour vérifier l'API) et son propre certificat de kubelet ; il ne reçoit ni la clé de la CA, ni `sa.key`, ni les certificats d'etcd. Sa demande de certificat (CSR `node-csr-…`, signataire `kubernetes.io/kube-apiserver-client-kubelet`) a été approuvée automatiquement par le contrôleur `csrapproving` grâce au RBAC posé par kubeadm (`kubeadm:node-autoapprove-bootstrap`) : `kubectl get csr` la montre `Approved,Issued`. Supprimer le jeton : `kubeadm token delete 7f3k2a`.

*C. Le réseau des pods.*

5. [`composants/cilium/values.yaml`](fichiers/M14-E05/k8s/composants/cilium/values.yaml). La VIP plutôt que le Service `kubernetes` (10.96.0.1) : l'adresse du Service n'est traduite que par kube-proxy… ou par Cilium lui-même quand il le remplace (M15) ; un agent qui doit joindre l'API **pour** programmer la traduction ne peut pas passer par elle. Avec kube-proxy conservé, ce n'est pas strictement nécessaire au M14, mais le M15 n'aura rien à changer ici, et le démarrage d'un nœud ne dépend pas de kube-proxy.
6. Installation et contrôles :
   ```
   admin@adm01:~/src/k8s$ task cilium
   task: [cilium] cilium install --context k8s-par1 --version 1.20.2 --values composants/cilium/values.yaml
   🔮 Auto-detected Kubernetes kind: kubernetes
   ℹ️  Using Cilium version 1.20.2
   …
   admin@adm01:~/src/k8s$ kubectl --context k8s-par1 get ciliumnodes -o custom-columns=NOEUD:.metadata.name,PODS:.spec.ipam.podCIDRs
   NOEUD      PODS
   k8s-cp01   [10.240.0.0/24]
   k8s-cp02   [10.240.2.0/24]
   k8s-w01    [10.240.1.0/24]
   ```
   Les nœuds passent `Ready` dès que l'agent Cilium a écrit sa configuration CNI ; c'est l'**opérateur** Cilium qui attribue les /24 (IPAM `cluster-pool`), pas le kube-controller-manager (dont l'allocation de `podCIDR` n'est pas utilisée ici). La version est passée explicitement parce que la CLI 0.20.1 installe par défaut **sa** version de référence (1.20.1) : sans `--version`, la version du cluster dépendrait de la version de l'outil sur le poste de celui qui lance la commande.
7. `cilium connectivity test --context k8s-par1` crée un espace `cilium-test-1`, des clients et des serveurs sur plusieurs nœuds, et vérifie pod à pod (même nœud, autre nœud), pod vers Service, vers les nœuds, vers l'extérieur, la résolution DNS, et l'application de politiques réseau d'essai. Une dizaine de minutes ; les images de test viennent de `quay.io` (Internet). Puis `kubectl --context k8s-par1 delete namespace cilium-test-1`.

*D. Le code fait le reste.*

8. Rôle [`k8s_travailleur`](fichiers/M14-E05/ansible/roles/k8s_travailleur/) ; fichier [`tasks/jonction.yml`](fichiers/M14-E03/ansible/roles/k8s_plan_controle/tasks/jonction.yml) de `k8s_plan_controle` (livré complet dès E03). Les secrets de jonction naissent sur le nœud de référence (`delegate_to`), vivent le temps d'un `kubeadm join --config` (fichier JoinConfiguration en 600, validé), puis meurent dans un bloc `always` (fichier supprimé, jeton révoqué), même en cas d'échec ; `no_log: true` partout où passe un secret. Un nœud de contrôle qui vient de joindre attend son `/readyz` local puis rejoue le point d'accès : la CA est là, HAProxy passe en HTTPS vérifié.
9. [`playbooks/k8s-cluster.yml`](fichiers/M14-E05/ansible/playbooks/k8s-cluster.yml) (version complète) et [`Taskfile.yml`](fichiers/M14-E05/k8s/Taskfile.yml) :
   ```
   admin@adm01:~/src/k8s$ task noeuds
   …
   TASK [k8s_plan_controle : Lancer kubeadm join avec le fichier de jonction] ***
   skipping: [k8s-cp01]
   …
   changed: [k8s-cp03]
   …
   PLAY [Travailleurs de k8s-par1] ***
   …
   PLAY RECAP ***
   k8s-cp03 : ok=… changed=…
   k8s-w02  : ok=… changed=…
   k8s-w03  : ok=… changed=…
   admin@adm01:~/src/k8s$ task noeuds 2>&1 | grep -E '^k8s-' | awk '{print $1, $4}'
   k8s-cp01 changed=0
   …
   k8s-w03 changed=0
   ```
10. HA : trois membres etcd (même commande qu'en 3), `show stat` sur chaque nœud de contrôle (trois `UP`, `L7OK`), CoreDNS sur deux travailleurs, et :
    ```
    admin@adm01:~$ kubectl --context k8s-par1 -n kube-system get lease kube-controller-manager kube-scheduler -o custom-columns=NOM:.metadata.name,DETENTEUR:.spec.holderIdentity
    NOM                       DETENTEUR
    kube-controller-manager   k8s-cp01_6b0e…
    kube-scheduler            k8s-cp01_0c41…
    ```
11. [`docs/kubernetes/cluster.md`](fichiers/M14-E05/medisphere/docs/kubernetes/cluster.md). Puis `rm -f "$XDG_RUNTIME_DIR/k8s-admin.conf"`.

Le check vérifie les six nœuds (prêts, version, adresse, rôle et *taint*), le plan de contrôle (quatre composants prêts sur trois nœuds, trois membres etcd lus par `etcdctl member list` dans le conteneur etcd de `k8s-cp01`, trois backends UP par `/readyz`), Cilium (agents, opérateur, relais, configuration, adresse de l'API, /24 par nœud), CoreDNS, la disparition de l'espace de test, les outils de `adm01` et le code.

**Explications**

- **Joindre un plan de contrôle, c'est recevoir la PKI.** Le Secret `kubeadm-certs` évite de copier les CA à la main (scp), mais il fait de la clé de certificats l'équivalent de la CA pendant deux heures. D'où la création à la demande, l'usage immédiat et la destruction dans le rôle.
- **Le deuxième nœud de contrôle est le moment le plus fragile.** Avec deux membres, etcd n'a aucune marge ; si la jonction du troisième échoue en laissant un membre déclaré mais absent, le cluster est à la merci d'une seule panne. C'est pourquoi le rôle joint un nœud à la fois et arrête tout au premier échec (`any_errors_fatal`).
- **Cilium sans remplacer kube-proxy.** Les deux coexistent : kube-proxy traduit les Services (iptables), Cilium fournit les adresses de pods, le tunnel VXLAN entre nœuds, et l'observabilité (Hubble). Le M15 retire kube-proxy et active le reste (LB IPAM, BGP, Gateway API).

**Alternatives**

- **Calico** ou **Flannel** comme CNI : Flannel est minimal (pas de politiques réseau), Calico mature et répandu (BGP natif). Cilium est retenu au PLAN pour l'eBPF, Hubble, le remplacement de kube-proxy et la Gateway API (M15).
- **Helm directement** (`helm install cilium cilium/cilium -f values.yaml`) : c'est ce que fait la CLI en dessous ; la CLI ajoute des contrôles (`cilium status`, test de connectivité) et détecte l'environnement. Le M17 reprendra la release dans Helmfile sans la réinstaller.
- **Copier les certificats à la main** vers les nœuds de contrôle (sans `--upload-certs`) : pas de Secret temporaire dans le cluster, mais des fichiers de CA qui transitent par `adm01`.

**Pièges classiques**

- `--apiserver-advertise-address` oublié sur `k8s-cp02` : avec une seule carte, l'adresse détectée est la bonne ; avec deux (M16), le membre etcd pourrait annoncer la mauvaise.
- Le jeton et la clé de certificats dans l'historique du shell (`~/.bash_history` de root) ou dans un fichier de journal Ansible sans `no_log`.
- `kubeadm join` relancé sur un nœud dont la première tentative a échoué à moitié : il faut d'abord `kubeadm reset` sur **ce** nœud (et, pour un nœud de contrôle, vérifier qu'il n'a pas laissé un membre etcd : `etcdctl member list`, puis `member remove`).
  > ⚠️ **Attention** : `kubeadm reset` sur le mauvais nœud de contrôle retire un membre sain ; relis `hostname`.
- Installer Cilium sans `--version` : la CLI choisit sa version par défaut, et deux personnes de l'équipe obtiennent deux clusters différents.
- Une valeur `k8sServiceHost` sur l'**adresse** de `k8s-cp01` : tout marche jusqu'à la perte de `k8s-cp01`, et là, plus aucun agent Cilium ne redémarre.
- Le test de connectivité laissé en place : ses pods tournent et tirent des images ; il fausse les checks suivants.

**En production chez MédiSphère**

Les jonctions ne se font plus à la main du tout : un nouveau nœud est une VM (OpenTofu), un rôle (Ansible) et rien d'autre (E17, E23). La version de Cilium est suivie comme celle de Kubernetes (ADR-0141), le test de connectivité tourne après chaque mise à jour (cluster de recette d'abord). Les secrets de jonction ne passent jamais par un humain.

---

### M14-E06 — kubectl, kubeconfig et k9s

**Solution**

*A. Ton identité.*

1. `kubectl config view` masque les données sensibles (`DATA+OMITTED`, `REDACTED`) ; `--raw` les affiche. Un kubeconfig a trois listes : `clusters` (point d'accès et CA), `users` (identité : certificat et clé, ou jeton), `contexts` (un couple cluster/utilisateur, plus un espace par défaut), et un `current-context`. Le certificat client d'`admin.conf` : `O=kubeadm:cluster-admins, CN=kubernetes-admin` (E04).
2. [`rbac/plateforme-admins.yaml`](fichiers/M14-E06/k8s/rbac/plateforme-admins.yaml), appliqué avec le kubeconfig de bris de glace. Un **groupe** : l'arrivée ou le départ d'un membre de l'équipe ne touche pas au cluster (seulement aux certificats émis) ; et c'est le groupe qui figure dans le certificat, ce que l'API sait lire.
3. [`outils/kubeconfig-personnel.sh`](fichiers/M14-E06/k8s/outils/kubeconfig-personnel.sh). `kubeadm kubeconfig user --config /etc/kubernetes/kubeadm/kubeadm-config.yaml --client-name <MOI> --org medisphere:plateforme-admins --validity-period 168h` signe avec la CA du nœud et écrit un kubeconfig sur la sortie standard (serveur = `controlPlaneEndpoint`, cluster nommé `k8s-par1`). Le script en extrait CA, certificat et clé dans un dossier du tmpfs de session, vérifie le sujet (`subject=CN=<MOI>,O=medisphere:plateforme-admins`), la chaîne (`openssl verify`) et le point d'accès, puis range le tout sous des noms fixes (`set-cluster k8s-par1`, `set-credentials <MOI>`, `set-context k8s-par1`) : un renouvellement remplace l'entrée existante.
4. Résultats :
   ```
   admin@adm01:~$ ~/src/k8s/outils/kubeconfig-personnel.sh <MOI>
   Émission d'un certificat de 168h pour <MOI> (groupe medisphere:plateforme-admins) sur k8s-cp01…
   Contexte « k8s-par1 » prêt dans /home/admin/.kube/config ; certificat valable jusqu'au : <date + 7 jours>
   ATTRIBUTE   VALUE
   Username    <MOI>
   Groups      [medisphere:plateforme-admins system:authenticated]
   admin@adm01:~$ kubectl auth can-i '*' '*'
   yes
   ```
   Révoquer avant expiration : impossible pour le certificat lui-même (E01, question 12) ; on retire les droits du **groupe** (supprimer temporairement la liaison, ce qui touche toute l'équipe, puis lier nommément les autres le temps que le certificat expire) ou on attend au plus 7 jours. C'est le prix d'une identité sans infrastructure ; le M24 la remplace par OIDC (jetons d'une heure, comptes désactivables).

*B. kubectl.*

5. Lignes utiles (exemples) :
   - `kubectl api-resources --namespaced=false` : ce qui n'a pas d'espace de noms (nœuds, ClusterRoles, PersistentVolumes…) ;
   - `kubectl explain deployment.spec.strategy --recursive` : la documentation du schéma **du serveur** (donc de la bonne version), sans navigateur ;
   - `-o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'` : une ligne par nœud ;
   - `--sort-by=.metadata.creationTimestamp`, `-l app.kubernetes.io/part-of=mediagenda`, `--field-selector spec.nodeName=k8s-w01` ;
   - `--dry-run=client` ne fait que construire l'objet localement ; `--dry-run=server` l'envoie au serveur, qui le valide **entièrement** (schéma de la version réelle, valeurs par défaut, admission, quotas, PSA au M14-E18) sans l'enregistrer. Une faute de champ ou un refus d'admission n'est attrapé que par le second ;
   - `kubectl diff -f fichier.yaml` montre ce qu'un `apply` changerait (code 1 s'il y a des différences) ; `apply --server-side` laisse le serveur fusionner et enregistre **qui** possède chaque champ (`--show-managed-fields`).
6. krew : archive vérifiée avec le fichier `.sha256` de la version 0.5.0, qui ne contient **que** l'empreinte (pas le nom du fichier) : `sha256sum -c` ne le lit pas tel quel, on reconstruit la ligne (`echo "$(cat krew-linux_amd64.tar.gz.sha256)  krew-linux_amd64.tar.gz" | sha256sum -c`), `./krew-linux_amd64 install krew`, `PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"` dans `~/.bashrc`, puis `kubectl krew install ctx ns neat`. `kubectl neat` retire d'un objet lu (`kubectl get -o yaml`) tout ce que le serveur a ajouté (`status`, `managedFields`, `uid`, `resourceVersion`, valeurs par défaut) : on obtient un manifeste propre à partir d'un objet existant.

*C. Le compte des vérifications.*

7. [`espaces/`](fichiers/M14-E06/k8s/espaces/) et [`rbac/wb-checks.yaml`](fichiers/M14-E06/k8s/rbac/wb-checks.yaml). « Tout sauf les Secrets » : RBAC n'a que des autorisations, pas d'interdictions ; on **énumère** les ressources du groupe cœur (`""`) sans `secrets`, et on donne `*` sur les groupes qui n'ont pas de secrets (apps, batch, rbac…). L'agrégation : les modules suivants installeront des CRD (Gateway API, cert-manager, ceph-csi, Prometheus…) ; chacun ajoutera une ClusterRole de lecture **étiquetée**, que le contrôleur d'agrégation réunira dans `wb-checks` sans qu'on retouche ce fichier (c'est le mécanisme des rôles `view`/`edit`/`admin` de Kubernetes, M14-E11). `subjectaccessreviews` : un check peut demander « `julien.petit` peut-il supprimer un Deployment dans `mediagenda-dev` ? » sans **devenir** `julien.petit` ; le droit `impersonate`, lui, permettrait d'agir sous n'importe quelle identité, administrateurs compris.
8. Application et vérification :
   ```
   admin@adm01:~/src/k8s$ task diff && task appliquer
   admin@adm01:~$ kubectl auth can-i --as=system:serviceaccount:wb-system:wb-checks get secrets -A
   no
   admin@adm01:~$ kubectl auth can-i --as=system:serviceaccount:wb-system:wb-checks list pods -A
   yes
   ```
9. [`outils/kubeconfig-checks.sh`](fichiers/M14-E06/k8s/outils/kubeconfig-checks.sh) : attend que le contrôleur ait rempli le Secret, écrit le kubeconfig avec `printf` (commande interne : rien dans `ps`), le contrôle (identité, lecture des nœuds, refus sur les Secrets et la suppression de pods), puis le met en place en 600.
   ```
   admin@adm01:~$ ~/src/k8s/outils/kubeconfig-checks.sh
   OK : system:serviceaccount:wb-system:wb-checks lit le cluster, sans les Secrets, sans écrire.
   Écrit : /home/admin/.config/workbook/k8s-checks.kubeconfig
   admin@adm01:~$ lab/bin/check 14 06
   ```
10. [`docs/kubernetes/acces.md`](fichiers/M14-E06/medisphere/docs/kubernetes/acces.md) et [`registre-secrets.md.extrait`](fichiers/M14-E06/medisphere/docs/socle/registre-secrets.md.extrait). La section « Étendre les droits de wb-checks » est le contrat que suivent les modules 15 à 29 : une ClusterRole `wb-checks-<thème>` étiquetée `workbook.medisphere.internal/checks: "true"`, en lecture seule, jamais sur les Secrets ; `kubectl get clusterrole wb-checks -o yaml` montre aussitôt les règles agrégées.

*D. k9s.*

11. `:pods` puis `0` (tous les espaces) ou `:ns` → `kube-system` ; tri par colonne avec `Maj` + lettre (ex. `Maj-N` pour le nœud, selon la version) ; `l` sur un pod pour ses journaux ; `:events` ; `:pulses` (tableau de bord d'activité) ; `:xray deploy` (arbre Deployment → ReplicaSet → Pods → conteneurs). Sans `--readonly`, k9s permet de supprimer (`Ctrl-D`), éditer (`e`), tuer (`Ctrl-K`), ouvrir un shell (`s`) : avec une identité `cluster-admin`, un mauvais raccourci a les mêmes effets qu'un mauvais `kubectl delete`. Le mode lecture seule est le bon défaut pour observer (on peut l'inscrire dans `~/.config/k9s/config.yaml`).

Le check vérifie le kubeconfig des vérifications (600, identité, lecture des nœuds, refus sur les Secrets, la suppression et l'emprunt d'identité, point d'accès), les objets appliqués (espaces, agrégation, montage de jeton désactivé, liaison des administrateurs, gestionnaire de champs `plateforme-k8s`), ton certificat (sujet, durée, contexte, `auth whoami` avec **ton** kubeconfig), l'absence de copie d'`admin.conf` sur `adm01`, krew, k9s et le code.

**Explications**

- **Trois sortes d'identités.** Les humains (certificats courts, puis OIDC au M24), les programmes **dans** le cluster (comptes de service et jetons liés, montés dans les pods, E13), les programmes **hors** du cluster (ici un compte de service avec un jeton porté par un Secret). Chacune a son mode de révocation : retrait des droits du groupe, suppression du pod ou du compte, suppression du Secret.
- **Pourquoi un jeton durable est ici acceptable.** Les jetons liés (`TokenRequest`) sont la norme : courts, liés à un objet, rejetés si l'objet disparaît. Les vérifications du workbook tournent irrégulièrement pendant des mois ; un jeton de quelques heures obligerait à le régénérer avant chaque check, avec une identité d'administrateur. L'exception est écrite, compensée (lecture seule, sans Secrets, aucun pod ne le monte) et révocable en une commande.
- **Server-side apply et gestionnaire de champs.** `task appliquer` enregistre `plateforme-k8s` comme propriétaire des champs qu'il écrit. Un `kubectl edit` ultérieur sur ces champs entre en **conflit** au prochain `apply` : la dérive se voit, au lieu d'être écrasée en silence. C'est la préparation directe au GitOps du M20.

**Alternatives**

- **CertificateSigningRequest** par l'API (`kubectl certificate approve`) au lieu de `kubeadm kubeconfig user` : la clé privée naît sur `adm01` et ne voyage pas ; mais il faut déjà une identité qui fonctionne pour créer et approuver la demande. C'est la méthode de M14-E12 pour les développeurs.
- **Jeton lié de longue durée** (`kubectl create token wb-checks --duration=8760h`) : expiration réelle et liaison au compte ; la durée maximale peut être plafonnée par le serveur (`--service-account-max-token-expiration`) et il faudra le renouveler. Variante défendable de l'exception.
- **ClusterRole `view` intégrée** pour les vérifications : elle exclut déjà les Secrets, mais aussi les nœuds, les rôles, les objets de stockage et d'admission : trop pauvre pour vérifier les exercices.
- **kubectx/kubens** en binaires au lieu des greffons krew : mêmes outils ; krew a l'intérêt de gérer d'autres greffons (`neat`, `who-can`, `tree`).

**Pièges classiques**

- Garder `admin.conf` comme `~/.kube/config` « parce que c'est plus simple » : l'audit (E27) attribuera tout à `kubernetes-admin`, et une fuite du poste vaut le cluster pendant un an.
- Fusionner des kubeconfigs avec `KUBECONFIG=a:b kubectl config view --flatten` dans le mauvais ordre : en cas de noms identiques, c'est le **premier** fichier qui gagne ; un renouvellement ne remplace rien.
- Le jeton passé à `kubectl config set-credentials --token=…` : visible dans `ps` et dans l'historique.
- Une ClusterRole agrégée avec un champ `rules: []` écrit dans le manifeste : à chaque `apply`, on revendique un champ que le contrôleur réécrit ; les deux se battent.
- Oublier qu'un Secret de type `kubernetes.io/service-account-token` est **lisible** par quiconque peut lire les Secrets de `wb-system` : c'est aussi pour cela que `wb-checks` n'a pas ce droit, et que les administrateurs seuls l'ont.
- `kubectl auth can-i` utilisé dans un script en `set -e` : la réponse `no` sort avec le code 1.

**En production chez MédiSphère**

Identités humaines par **OIDC** (Keycloak, M24) : jetons courts, groupes gérés dans l'annuaire, comptes désactivés au départ d'une personne, et plus aucun certificat client personnel. Les comptes de service hors cluster (CI, supervision) reçoivent des jetons liés renouvelés par Vault (M25). Le bris de glace est testé deux fois par an (exercice de PRA, F5) et chaque usage déclenche une alerte de l'audit (E27).

---

### M14-E07 — Pods, Deployments et Services : MédiAgenda sur le cluster

**Solution**

1. Événements dans l'ordre : `Scheduled` (l'**ordonnanceur** a choisi un nœud : `Successfully assigned wb-essais/essai to k8s-w02`), `Pulling`, `Pulled`, `Created`, `Started` (le **kubelet** du nœud, par containerd). Pas de nœud de contrôle : leur *taint* `node-role.kubernetes.io/control-plane:NoSchedule` et l'absence de tolérance du pod.
2. Secrets, sans argument de commande ni fichier versionné :
   ```
   admin@adm01:~$ mkdir -p ~/m14/e07 && chmod 700 ~/m14/e07
   admin@adm01:~$ (umask 077; openssl rand -hex 24 | tr -d '\n' > ~/m14/e07/mdp-postgresql)
   admin@adm01:~$ kubectl -n wb-essais create secret generic postgresql --from-file=mot-de-passe=$HOME/m14/e07/mdp-postgresql
   admin@adm01:~$ ( set -a; . ~/.config/workbook/harbor-k8s-pull.env; set +a; umask 077
       jq -n --arg r registry.par1.medisphere.internal --arg a "$(printf '%s:%s' "$HARBOR_USER" "$HARBOR_PASSWORD" | base64 -w0)" \
         '{auths: {($r): {auth: $a}}}' > "$XDG_RUNTIME_DIR/dockerconfig.json" )
   admin@adm01:~$ kubectl -n wb-essais create secret generic harbor-pull --type=kubernetes.io/dockerconfigjson \
       --from-file=.dockerconfigjson="$XDG_RUNTIME_DIR/dockerconfig.json"
   admin@adm01:~$ rm -f "$XDG_RUNTIME_DIR/dockerconfig.json"
   ```
   Mot de passe en **hexadécimal** : il entre tel quel dans l'URL de connexion (`postgresql://mediagenda:<MOT-DE-PASSE>@postgresql…`) ; un mot de passe en base64 contient souvent un `/` (quatre fois sur dix environ pour 24 octets), que l'analyseur d'URL de libpq (psycopg) prend pour la fin de l'hôte : `invalid integer value … for connection option "port"`, et les migrations échouent. `outils/secret-mediagenda.sh` (E19) fait de même.
   (`printf` et `jq --arg` reçoivent les valeurs par l'environnement du sous-shell ; elles n'apparaissent que dans les arguments de `jq`, dans un sous-shell bref ; pour être strict, `jq` peut lire les valeurs par `$ENV` : `jq -n '$ENV.HARBOR_USER'`.)
3. [`valkey.yaml`](fichiers/M14-E07/mediagenda-api/k8s/essais/valkey.yaml), [`postgresql.yaml`](fichiers/M14-E07/mediagenda-api/k8s/essais/postgresql.yaml). Un `emptyDir` est un dossier créé sur le nœud à la création du pod et **supprimé avec lui** : suppression du pod, reprogrammation sur un autre nœud, drain. Il survit seulement au redémarrage d'un conteneur dans le même pod. `Recreate` : avec `RollingUpdate`, un nouveau pod PostgreSQL démarrerait avant l'arrêt de l'ancien ; sur un volume partagé (M16), deux instances écriraient les mêmes fichiers : corruption. On prend l'habitude dès maintenant. Image 18 : `PGDATA` est `/var/lib/postgresql/18/docker` et le volume se monte sur `/var/lib/postgresql`.
4. [`mediagenda-api.yaml`](fichiers/M14-E07/mediagenda-api/k8s/essais/mediagenda-api.yaml). L'URL de la base : `MEDIAGENDA_DB_MDP` lue dans le Secret, puis `value: postgresql://mediagenda:$(MEDIAGENDA_DB_MDP)@postgresql:5432/mediagenda` (variables dépendantes : Kubernetes remplace `$(NOM)` par une variable définie **plus haut**). Deux pods qui migrent en même temps : `migrate.py` prend un verrou consultatif PostgreSQL (`pg_advisory_lock`), applique chaque fichier dans une transaction et note ce qui est fait : le second attend, voit que tout est appliqué, et termine.
5. Après `kubectl apply -f k8s/essais/` :
   ```
   admin@adm01:~/src/mediagenda-api$ kubectl -n wb-essais get deploy,rs,pods,svc,endpointslices -o wide
   NAME                             READY   UP-TO-DATE   AVAILABLE
   deployment.apps/mediagenda-api   2/2     2            2
   …
   NAME                                        DESIRED   CURRENT   READY
   replicaset.apps/mediagenda-api-6d9f7c5b8c   2         2         2
   …
   NAME                                  READY   STATUS    IP            NODE
   pod/mediagenda-api-6d9f7c5b8c-7xk2p   1/1     Running   10.240.3.41   k8s-w02
   pod/mediagenda-api-6d9f7c5b8c-q8m4z   1/1     Running   10.240.4.17   k8s-w03
   …
   NAME                     TYPE        CLUSTER-IP     PORT(S)
   service/mediagenda-api   ClusterIP   10.96.48.211   80/TCP
   …
   NAME                                            ADDRESSTYPE   PORTS   ENDPOINTS
   endpointslice…/mediagenda-api-x7b2c             IPv4          8000    10.240.3.41,10.240.4.17
   ```
   Le Service et ses pods ne sont reliés que par le **sélecteur d'étiquettes** du Service ; le contrôleur des EndpointSlices tient la liste des adresses des pods qui correspondent **et** sont prêts. Le Deployment possède le ReplicaSet (`ownerReferences`), qui possède les pods.
6. `curl -s localhost:8000/sante` → `{"statut":"ok","version":"…"}` ; création d'un rendez-vous (`curl -s -X POST localhost:8000/api/v1/rendez-vous -H 'Content-Type: application/json' -d '{…}'`) → 201 ; liste → un élément. Le chemin : `curl` → `kubectl port-forward` (local) → **serveur d'API** (connexion en flux, par la VIP) → **kubelet** du nœud d'un des pods → port 8000 du pod. Le Service n'est utilisé que pour **choisir un pod** au démarrage du tunnel ; ensuite, tout va à ce pod-là.
7. Expériences :
   - pod supprimé : le ReplicaSet constate 1 pod sur 2 et en crée un nouveau en quelques secondes (nouveau nom, nouvelle adresse) ; le Service le reprend dès qu'il est prêt ;
   - `scale` à 3 puis `apply` du fichier à 2 : le fichier gagne (2), parce que `apply` réécrit `spec.replicas` ; c'est le comportement voulu tant que le fichier est la vérité (et ce qu'on supprimera du manifeste si un HPA pilote les réplicas, M28) ;
   - pod PostgreSQL supprimé : nouveau pod, nouvel `emptyDir`, base **vide** ; les rendez-vous ont disparu ; l'API journalise des erreurs de connexion pendant le redémarrage, puis des erreurs SQL (`relation … does not exist`) : le schéma n'existe plus, et les migrations ne tournent qu'au démarrage des pods de l'API. `kubectl -n wb-essais rollout restart deployment mediagenda-api` les rejoue. C'est **exactement** pourquoi le stockage persistant (M16) et un opérateur de base de données (M16, M27) existent ;
   - étiquette changée : le pod sort du sélecteur du ReplicaSet (qui n'en voit plus qu'un et en recrée un) **et** du Service (plus de trafic) ; il continue de tourner, orphelin. C'est une technique de diagnostic (isoler un pod malade sans le tuer). `kubectl -n wb-essais delete pod -l app.kubernetes.io/name=quarantaine`.
8. MR sur `mediagenda/api` (`k8s/essais/` et son README).

Le check vérifie, dans `wb-essais`, les trois Deployments (réplicas, image de Harbor par version, Secret de tirage, migrations terminées, `emptyDir`, `Recreate`, étiquettes, pods sur des travailleurs), les trois Services et les points de terminaison de l'API, puis `GET /sante` et la présence d'un rendez-vous à travers le mandataire du serveur d'API (`services/proxy`), et les fichiers sur `main`.

**Explications**

- **Étiquettes et sélecteurs, la colle de Kubernetes.** Rien ne relie « en dur » un Service à des pods, ni un ReplicaSet à ses pods : ce sont des requêtes sur des étiquettes, réévaluées en permanence. C'est souple (on isole un pod en changeant une étiquette) et dangereux (deux Deployments aux mêmes étiquettes se volent leurs pods ; un sélecteur trop large envoie du trafic ailleurs).
- **Un pod est jetable, ses données aussi sans volume persistant.** La démonstration de la base vidée est volontaire : tout le module 16 en découle.
- **Migrations en conteneur d'initialisation.** Simple et sûr ici grâce au verrou de `migrate.py`. Pour une application qui ne verrouille pas, on préférerait un Job unique lancé avant le déploiement (M14-E15, M20 avec les *hooks* d'Argo CD).

**Alternatives**

- **Secret de tirage sur le compte de service `default`** (`kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "harbor-pull"}]}'`) : tous les pods de l'espace en profitent sans l'écrire ; moins visible dans le manifeste. M14-E19 compare les deux et ajoute le cache Harbor.
- **Valkey et PostgreSQL hors du cluster** (VM, service managé) : c'est souvent le bon choix en production pour une base ; au M14, on veut voir les objets.
- **Service headless** (`clusterIP: None`) pour PostgreSQL : le nom résout directement l'adresse du pod ; utile avec un StatefulSet (M14-E15), sans intérêt ici.

**Pièges classiques**

- Le nom du robot Harbor contient `$` (`robot$k8s-pull`) : non protégé dans une commande shell, il devient `robot` suivi d'une variable vide ; erreur `401` au tirage, `ImagePullBackOff`.
- Le mot de passe en clair dans `value:` (ou dans un fichier `Secret` versionné en `stringData`) : il finit dans le dépôt de l'équipe de développement.
- Un sélecteur de Deployment changé après création : le champ `spec.selector` est **immuable** ; il faut supprimer et recréer.
- `targetPort` numérique qui ne correspond pas au port réel : le Service a des points de terminaison mais tout échoue (`connection refused`). Les ports **nommés** (`http`) évitent l'écart.
- Croire que `port-forward` teste le Service : il teste un pod. Pour tester le Service, il faut un client **dans** le cluster (pod de diagnostic, « pour aller plus loin »).

**En production chez MédiSphère**

Les manifestes de MédiAgenda deviennent un chart Helm (M17), déployé par Argo CD (M20) dans `mediagenda-recette` puis `mediagenda-prod`, avec des images épinglées par **digest** et vérifiées par signature à l'admission (M26). La base est un cluster CloudNativePG à trois instances avec sauvegarde vers S3 (M16, M27) ; le cache, un Valkey répliqué (M27). Le `port-forward` reste un outil de diagnostic, jamais un mode d'accès.

---

### M14-E08 — ConfigMaps, Secrets, sondes et ressources

**Solution**

Fichiers : [`mediagenda-api-config.yaml`](fichiers/M14-E08/mediagenda-api/k8s/essais/mediagenda-api-config.yaml), [`mediagenda-api.yaml`](fichiers/M14-E08/mediagenda-api/k8s/essais/mediagenda-api.yaml), [`postgresql.yaml`](fichiers/M14-E08/mediagenda-api/k8s/essais/postgresql.yaml), [`valkey.yaml`](fichiers/M14-E08/mediagenda-api/k8s/essais/valkey.yaml).

1. Pour MédiAgenda :

   | Sonde | Doit vérifier | En cas d'échec | Pire erreur de réglage |
   |---|---|---|---|
   | démarrage | que le processus répond (`/sante`) | le conteneur est redémarré si le seuil est dépassé | trop courte : un démarrage lent (migrations, pool) redémarre en boucle |
   | vivacité | que le processus **lui-même** répond (`/sante`, sans dépendance) | redémarrage du conteneur | sonde qui dépend de la base : une panne de PostgreSQL redémarre toutes les API en boucle |
   | disponibilité | que le pod peut servir (`/pret` : base **et** cache) | le pod sort des points de terminaison, sans redémarrage | absente : du trafic envoyé à un pod qui démarre ou dont les dépendances sont tombées |
2. `envFrom` sur le ConfigMap ; Secret `mediagenda-db` créé comme en E07 (`--from-file`), référencé par PostgreSQL et l'API. PostgreSQL ne relit **pas** `POSTGRES_PASSWORD` : le script d'entrée de l'image ne l'utilise que pour `initdb`, sur un dossier de données vide ; le compte garde l'ancien mot de passe, et l'API (nouveau mot de passe) échoue à l'authentification (`password authentication failed`). Données jetables : on supprime le pod PostgreSQL (nouvel `emptyDir`, nouvel `initdb`), puis `rollout restart` de l'API pour rejouer les migrations. En production, on change le mot de passe **dans** la base (`ALTER ROLE`) avant de changer le Secret.
3. Les variables d'environnement sont lues au démarrage du processus : les pods existants gardent l'ancienne valeur. Il faut redémarrer (`kubectl -n wb-essais rollout restart deployment mediagenda-api`). Kubernetes ne le fait pas seul : changer un ConfigMap ne change pas le **modèle** de pod du Deployment, donc aucun déploiement n'est déclenché. (Un volume ConfigMap, lui, est mis à jour dans le pod au bout d'une minute environ, mais l'application doit relire le fichier.) Les outils d'empaquetage ajoutent une empreinte du ConfigMap en annotation du modèle de pod pour forcer ce redémarrage (Kustomize `configMapGenerator`, M17).
4. Délais retenus pour l'API : démarrage `periodSeconds: 2`, `failureThreshold: 30` (60 s au plus) ; vivacité toutes les 10 s, 3 échecs (30 s) ; disponibilité toutes les 5 s, 2 échecs, délai de réponse 3 s (`/pret` peut attendre 2 s le pool de connexions quand la base est absente, constaté à la rédaction). PostgreSQL : `pg_isready` en démarrage (60 s) et disponibilité, connexion TCP en vivacité ; Valkey : `valkey-cli ping` en disponibilité, TCP en vivacité.
5. Valkey à 0 : en 10 s, les deux pods de l'API passent `0/1` (disponibilité en échec : `/pret` répond 503, `valkey: indisponible`) et sortent des EndpointSlices ; **aucun redémarrage** (vivacité sur `/sante`, toujours 200). Le Service n'a plus de point de terminaison : un client reçoit une erreur de connexion, alors que `/api/v1/creneaux` aurait pu répondre en mode dégradé. C'est un vrai choix de conception : `/pret` exige le cache, l'équipe de Julien pourrait préférer qu'il n'exige que la base (le cache étant optionnel) ; à noter pour eux. Avec `/pret` en **vivacité** : après 30 s, redémarrage des deux API, qui redémarreraient encore et encore tant que Valkey est absent (`CrashLoopBackOff`, attente croissante jusqu'à 5 minutes) ; au retour de Valkey, les pods seraient en pleine attente et l'application resterait indisponible plusieurs minutes de plus. Une panne d'une dépendance devient une panne de l'application.
6. QoS :
   ```
   admin@adm01:~$ kubectl -n wb-essais get pods -o custom-columns=POD:.metadata.name,QOS:.status.qosClass
   POD                               QOS
   mediagenda-api-…                  Burstable
   mediagenda-api-…                  Burstable
   postgresql-…                      Guaranteed
   valkey-…                          Burstable
   ```
   Valkey en Burstable avec `--maxmemory 96mb` et une limite à 128 Mi : Valkey évince ses propres clés (`allkeys-lru`) **avant** que le noyau ne le tue à la limite du cgroup. Pas de limite de CPU sur l'API : une limite étrangle le processus à chaque pic même quand le nœud a du CPU libre (latence en dents de scie) ; la **demande** suffit à garantir sa part. La mémoire, elle, a une limite : sans elle, une fuite mangerait le nœud. Sur le nœud, « Allocated resources » montre la somme des demandes : c'est ce que l'ordonnanceur compte, pas l'usage réel.
7. Avec `readOnlyRootFilesystem: true`, ce qui écrit hors des volumes casse : ici `/tmp` (fichiers temporaires de Python et des bibliothèques) ; un `emptyDir` en mémoire (`medium: Memory`, 16 Mi) monté sur `/tmp` le règle. `runAsNonRoot` fonctionne parce que l'image déclare un utilisateur **numérique** (10001) : le kubelet peut vérifier qu'il n'est pas 0. `kubectl exec … -- id` → `uid=10001(mediagenda)` ; `touch /app/x` → `Read-only file system`.
8. Délai de grâce de 30 s (> 20 s de `MEDIAGENDA_DELAI_ARRET`). Pendant le `rollout restart` : quelques erreurs possibles côté `curl` parce que le *port-forward* est attaché à **un** pod, qui finit par s'arrêter : le tunnel se coupe. Un vrai test de continuité passe par le Service, depuis un client du cluster (et le M15 le fera depuis l'extérieur par la Gateway). Pour un arrêt sans erreur côté Service, il faut aussi que le pod sorte des points de terminaison **avant** que l'application ne refuse les connexions : petite pause `preStop` (`sleep 5`) dans un vrai déploiement (M14-E16).
9. MR avec les quatre fichiers et la note.

Le check vérifie le ConfigMap (clés, aucun identifiant), la consommation par `envFrom`, le mot de passe par `secretKeyRef` et l'URL par `$(…)`, les trois sondes et la durée de démarrage, les sondes de PostgreSQL et Valkey, les ressources, les classes QoS observées, le délai de grâce, le contexte de sécurité, `/pret` (`pret`, `ok`, `ok`) à travers le mandataire de l'API, deux points de terminaison prêts, et l'absence de Secret versionné. Il ne lit **pas** les Secrets (`wb-checks` n'en a pas le droit).

**Explications**

- **Configuration et secrets séparés, pour des raisons différentes.** Un ConfigMap se relit, se compare, se versionne ; un Secret ne doit jamais l'être en clair. Les deux finissent en variables d'environnement ici ; au M25 (Vault, External Secrets), le Secret viendra d'un coffre, le ConfigMap restera dans Git.
- **Les sondes encodent un contrat.** L'application de Julien distingue « je suis vivant » et « je peux servir » : c'est ce qui permet à Kubernetes de ne pas confondre une panne de dépendance avec une panne de l'application. Une sonde mal choisie transforme une dégradation en panne totale.
- **Demandes, limites, QoS.** L'ordonnanceur place les pods sur leurs **demandes** ; les **limites** sont appliquées par le noyau ; la classe QoS (calculée sur tous les conteneurs du pod) décide de l'ordre d'éviction quand le nœud manque de mémoire. Une base en Guaranteed, c'est la dernière à partir.

**Alternatives**

- **Configuration en fichier** (volume ConfigMap monté) plutôt qu'en variables : se met à jour à chaud, permet des fichiers structurés ; MédiAgenda ne lit que l'environnement (facteur III des « 12 facteurs »), la question ne se pose pas.
- **Sonde gRPC ou `exec`** : `exec` lance un processus dans le conteneur à chaque sonde (coût, et l'image doit contenir l'outil) ; `httpGet` est le bon choix pour une API HTTP.
- **Limite de CPU partout** (souvent exigée par une politique) : défendable pour des équipes qui ne se connaissent pas (multi-tenance, M28) ; à combiner avec des demandes réalistes. Les quotas d'espace de noms (M14-E10) peuvent l'imposer.

**Pièges classiques**

- `initialDelaySeconds` grand sur la vivacité « pour laisser démarrer » au lieu d'une sonde de démarrage : un démarrage plus lent que prévu redémarre quand même, et un pod qui plante après le démarrage met longtemps à être détecté.
- `timeoutSeconds: 1` (la valeur par défaut) sur une sonde qui interroge une dépendance : sous charge, des échecs aléatoires.
- Une limite de mémoire égale à la demande « pour être Guaranteed » sur une application Python qui a des pics : `OOMKilled` réguliers (M14-E38).
- `readOnlyRootFilesystem` sans volume pour `/tmp` : l'application démarre puis échoue au premier fichier temporaire, parfois des heures plus tard.
- Penser que modifier un Secret change le mot de passe de la base : le Secret n'est qu'un **transport**.

**En production chez MédiSphère**

Des valeurs de ressources mesurées, pas devinées : métriques réelles (M21), recommandations du VPA (M28), revues trimestrielles. Les sondes de chaque application sont décrites dans ses normes (M12-E33) et vérifiées à l'admission (une politique Kyverno refuse un Deployment sans sonde de disponibilité, M26). Les Secrets viennent de Vault (M25), avec rotation sans redémarrage manuel (rechargement déclenché par External Secrets).

---

### M14-E09 — Questions : architecture de Kubernetes

**Barème** : 2 points par question, total sur 32. Une réponse qui cite une observation faite sur `k8s-par1` (fichier, commande) vaut mieux qu'une réponse de cours.

**1. De `kubectl apply` aux conteneurs.** `kubectl` envoie la requête (PATCH en *server-side apply*) au **kube-apiserver** par la VIP et HAProxy ; le serveur authentifie (certificat client), autorise (RBAC), passe l'admission (mutations puis validations), écrit le Deployment dans **etcd**. Le contrôleur de Deployments du **kube-controller-manager** (qui observe les Deployments par *watch*) crée un ReplicaSet ; le contrôleur de ReplicaSets crée deux Pods sans nœud (`spec.nodeName` vide). Le **kube-scheduler** (qui observe les pods sans nœud) choisit un nœud pour chacun et écrit la liaison (*binding*). Le **kubelet** du nœud choisi (qui observe les pods de **son** nœud) demande au runtime par le CRI : bac à sable (pause, réseau par le CNI Cilium), tirage de l'image, conteneur d'initialisation, conteneur principal ; il remonte le *status*. En parallèle, le contrôleur des EndpointSlices ajoute les pods prêts au Service. Ordonnanceur en panne : pods créés, restés `Pending` sans nœud. Contrôleur de ReplicaSets en panne : Deployment et ReplicaSet existent, aucun pod n'est créé.

**2. etcd.** Le seul **kube-apiserver**. Tous les autres composants passent par l'API : un seul point applique l'authentification, l'autorisation, l'admission, la validation des schémas et la gestion des versions d'objets (`resourceVersion`) ; etcd peut changer (version, chiffrement au repos, E28) sans que les composants le sachent ; et la charge sur etcd est maîtrisée (cache du kube-apiserver, *watch* mutualisés).

**3. Membre etcd local tombé.** kubeadm configure `--etcd-servers=https://127.0.0.1:2379` : le kube-apiserver de `k8s-cp02` ne parle **qu'à son** membre local. Membre local tombé : ce kube-apiserver ne peut plus lire ni écrire, `/readyz` échoue (vérification `etcd`) ; HAProxy le retire (contrôle `/readyz`), les deux autres servent. Le cluster reste disponible ; le nœud est dégradé. (On peut configurer les trois membres dans `--etcd-servers` : kubeadm ne le fait pas pour la topologie empilée.)

**4. Réponse B.** Un seul membre etcd sur trois : pas de quorum, aucune écriture possible ; le kube-apiserver restant ne peut pas confirmer ses lectures (lectures linéarisables par défaut) et `/readyz` échoue : l'API est en pratique inutilisable. Les kubelets des travailleurs continuent de faire tourner les pods qu'ils ont, sans recevoir de changement (ils réessaient de joindre l'API). A est faux : une copie complète ne suffit pas, il faut la majorité pour décider. C est faux : un kubelet ne tue pas ses pods parce que l'API est absente. D est faux : etcd n'a pas de mode « lecture seule » sans quorum ; il refuse. La restauration sur un seul membre est une procédure (M14-E24, E29).

**5. Élection.** Ces composants fonctionnent par boucles de contrôle sur l'ensemble des objets : deux instances actives feraient le travail deux fois (pods créés en double, décisions d'ordonnancement contradictoires). Chaque instance tente de prendre un bail ; une seule agit. Sur `k8s-par1` : `kubectl -n kube-system get lease kube-controller-manager kube-scheduler` (champ `holderIdentity`), et les journaux des instances en attente (`attempting to acquire leader lease…`).

**6. Identité du kubelet.** Certificat client `CN=system:node:k8s-w02`, `O=system:nodes` (`/var/lib/kubelet/pki/kubelet-client-current.pem`, renouvelé automatiquement). L'autorisateur **Node** (`--authorization-mode=Node,RBAC`) limite un kubelet aux objets liés à **son** nœud (ses pods, les Secrets et ConfigMaps de ses pods) ; l'admission **NodeRestriction** l'empêche de modifier l'objet Node d'un autre nœud ou de s'ajouter des étiquettes réservées. Un kubelet compromis ne lit donc pas les Secrets de tout le cluster.

**7. Pods statiques.** Le kubelet lit `staticPodPath` (`/etc/kubernetes/manifests`) et lance ce qu'il y trouve, sans API ; quand l'API existe, il y publie des pods « miroirs » (visibles par `kubectl`, non modifiables par elle). Modifier `kube-scheduler.yaml` : le kubelet détecte le changement (scrutation du dossier, environ 20 s) et **recrée** le pod. Une erreur de syntaxe fait disparaître le composant de ce nœud (E39 : manifeste cassé). On édite toujours une copie hors du dossier (sinon un fichier temporaire de l'éditeur peut être pris pour un manifeste).

**8. Pod → `postgresql:5432`.** (1) Résolution : le `resolv.conf` du pod pointe vers l'adresse du Service de CoreDNS (10.96.0.10) ; `postgresql` est complété par le domaine de recherche `wb-essais.svc.cluster.local` ; CoreDNS répond l'**adresse du Service** (10.96.x.y). (2) Traduction : à la sortie du pod, sur `k8s-w01`, les règles iptables de kube-proxy (`KUBE-SERVICES` → `KUBE-SVC-…` → `KUBE-SEP-…`) remplacent 10.96.x.y:5432 par l'adresse du pod PostgreSQL (10.240.4.z:5432). (3) Trajet : Cilium sait que 10.240.4.0/24 est sur `k8s-w03` ; il encapsule le paquet (en-tête intérieur : pod source 10.240.1.a → pod destination 10.240.4.z) dans de l'UDP/VXLAN port 8472 (en-tête extérieur : 10.10.40.61 → 10.10.40.63), le nœud de destination décapsule et remet au pod. La réponse suit le chemin inverse, et conntrack retraduit l'adresse source en celle du Service.

**9. Réponse B.** Les règles sont dans le noyau de chaque nœud ; supprimer le DaemonSet arrête les processus kube-proxy, pas les règles (il ne les nettoie pas en s'arrêtant). Les Services existants continuent de fonctionner tant que leurs pods ne changent pas ; un pod recréé (nouvelle adresse) ou un nouveau Service ne sont plus pris en compte. A est faux pour la même raison ; C est faux : Cilium ne remplace kube-proxy que s'il est configuré pour (`kubeProxyReplacement: true`, M15) ; D est faux : CoreDNS répond, mais ses propres clients le joignent… par un Service, ce qui fonctionne encore jusqu'à ce que ses pods changent.

**10. Pause.** Il tient les espaces de noms partagés du pod (réseau, IPC) et sert de « parent » ; il ne fait rien d'autre. Si le conteneur de l'API redémarre, le bac à sable (pause) reste : **même adresse**. Si le pod est recréé (nouveau pod, nouveau bac à sable), nouvelle adresse : c'est pourquoi on passe par un Service.

**11. Disponibilité et vivacité.** Kubelet : un échec de vivacité **redémarre** le conteneur ; un échec de disponibilité ne fait que changer la condition `Ready` du pod. Service : seul l'état de disponibilité compte ; un pod non prêt sort des EndpointSlices. Utilisateur : un redémarrage coupe ses requêtes en cours ; un retrait du Service est invisible s'il reste d'autres pods. `/pret` en vivacité : une panne de PostgreSQL ou de Valkey redémarre **toutes** les API en boucle (`CrashLoopBackOff`), ce qui retarde le retour du service bien après le retour de la dépendance, et ajoute une charge de reconnexion massive au moment où elle redémarre.

**12. Évictions et OOM.** Sous pression mémoire, le kubelet évince d'abord les pods **BestEffort**, puis les **Burstable** qui dépassent leurs demandes (classés par dépassement et priorité), et les **Guaranteed** en dernier (et ceux qui sont dans leurs demandes, en cas extrême). Le kubelet agit par **seuils** (`evictionHard`, par exemple `memory.available<100Mi`) et laisse un état explicite (`Evicted`, reprogrammation par le contrôleur). L'OOM killer du **noyau**, lui, agit quand un cgroup atteint sa limite (ou que le nœud n'a plus rien) : il tue un **processus** immédiatement, sans délai de grâce ; le conteneur est `OOMKilled` et redémarré sur place. Le score OOM (`oom_score_adj`) que le kubelet pose par classe QoS oriente ce choix dans le même ordre.

**13. Identités.**

| Kubeconfig | Authentification | Autorisation | Retrait de l'accès |
|---|---|---|---|
| `admin.conf` | certificat client, `O=kubeadm:cluster-admins` | RBAC : liaison `kubeadm:cluster-admins` → `cluster-admin` | supprimer la liaison (immédiat) ; le certificat reste valide un an |
| `super-admin.conf` | certificat client, `O=system:masters` | **aucune** : groupe autorisé d'office | changer la CA du cluster |
| personnel | certificat client 7 jours, `O=medisphere:plateforme-admins` | RBAC : liaison `medisphere:plateforme-admins` | expiration ; suppression de la liaison du groupe |
| `wb-checks` | jeton de compte de service (Secret) | RBAC : ClusterRole agrégée `wb-checks` | supprimer le Secret (ou le compte) : refus immédiat |

**14. HAProxy en TCP.** En terminant le TLS sur HAProxy : (1) le kube-apiserver ne verrait plus les **certificats clients** (seul HAProxy les recevrait) : il faudrait les relayer par des en-têtes et faire confiance à HAProxy pour l'authentification, ce qui ferait de lui un point d'usurpation d'identité ; (2) les flux longs (*watch*, `exec`, `attach`, `port-forward`, mises à niveau SPDY/WebSocket) seraient soumis aux délais et aux limites du mode HTTP ; (3) il faudrait gérer un certificat de plus, et le TLS de bout en bout (exigence HDS) serait rompu sur le dernier saut. En TCP, HAProxy ne fait que répartir des connexions.

**15. CA et clé des comptes de service.** CA du **cluster** : certificats du kube-apiserver, des kubelets (clients et, si demandé, serveurs), des administrateurs et des contrôleurs ; CA d'**etcd** : certificats serveur et pair d'etcd, client etcd du kube-apiserver et des contrôles de santé (une PKI séparée : un certificat du cluster ne donne pas accès à etcd) ; CA du **front-proxy** : le client que le kube-apiserver utilise pour relayer les requêtes vers les API agrégées (metrics-server), qui lui font confiance par cette CA. `sa.key`/`sa.pub` : signature et vérification des jetons de comptes de service. Si la clé différait d'un nœud de contrôle à l'autre, un jeton signé par un kube-apiserver serait rejeté par un autre : les pods verraient leurs requêtes refusées au hasard, selon le nœud choisi par HAProxy. D'où la distribution de `sa.key` aux nœuds de contrôle (Secret `kubeadm-certs`).

**16. Ce qui a une version.** Kubernetes (kubeadm, kubelet, kubectl, et l'image des composants), le dépôt pkgs.k8s.io (une mineure par dépôt), etcd (fixé par kubeadm), CoreDNS (fixé par kubeadm), l'image pause (configuration de containerd !), containerd et runc, kube-proxy, Cilium (matrice de compatibilité 1.33-1.36) et sa CLI, Hubble, kubectl et etcdctl de `adm01`, Helm, la configuration kubeadm (API v1beta4 ; `kubeadm config migrate`), les API des objets déployés (versions dépréciées, à vérifier avant la montée), Debian et son noyau (cgroups, eBPF pour Cilium), HAProxy et keepalived (moins critiques), et plus tard les composants des modules 15-16 (cert-manager, ceph-csi, Gateway API…) qui ont leur propre fenêtre de compatibilité. C'est la matière de l'ADR-0141 (E30) et de RB-142 (E25).
