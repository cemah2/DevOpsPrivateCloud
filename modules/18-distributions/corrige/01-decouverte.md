# Module 18 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné : `infra/` pour `plateforme/infra`, `ansible/` pour `plateforme/ansible`, `distributions/` pour `plateforme/distributions`, `medisphere/` pour la documentation. Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie : `M18-E02/` (état `envs/m18`, source d'inventaire, rôle `outils_distributions`, playbook v1, kind, k3d), `M18-E03/` (rôle `k3s`, playbook v2, manifestes de l'agence), `M18-E04/` (rôle `rke2`, playbook v3, essai CIS), `M18-E05/` (`talos.tf`, schéma, scripts et patches Talos).

**Ce qui a été vérifié à la rédaction** (2026-10-15) :
- `envs/m18` (`versions.tf`, `providers.tf`, `variables.tf`, `hotes.tf` + `talos.tf`) passe `tofu fmt -check` et `tofu validate` avec OpenTofu 1.13.0 et les fournisseurs réels (`bpg/proxmox` 0.116.0 et 0.116.1, `e-breuninger/netbox` 5.8, `mmianl/powerdns` 2.5), modules `vm-noeud` v2.4 (corrigé M12-E02) et `enregistrement-dns` (corrigé M06-E14) pris en local ; `proxmox_download_file` existe dans 0.116.0 (l'ancien nom `proxmox_virtual_environment_download_file` est déprécié) ;
- versions et artefacts : canaux k3s et RKE2 (`update.k3s.io`, `update.rke2.io` : `stable` = v1.36.5) ; script `install.sh` de k3s aux tags v1.36.4+k3s1 et v1.36.5+k3s1 (même empreinte `46177d4c…fbfad`, différente de celle de `get.k3s.io`, plus récent) ; dépôt RPM `rke2/latest/1.36/centos/10/x86_64` (paquets `rke2-server-1.36.0` à `1.36.5~rke2r1-0.el10`) et `common/centos/10/noarch` (`rke2-selinux-0.23-2.el10`), clé `C8CFF216455126E9B9C918BE925EA29AE257814A` ; images `kindest/node:v1.36.4` (empreinte des notes de version de kind 0.33.0 ; **pas** de `v1.36.5`), `rancher/k3s:v1.36.4-k3s1` et `v1.36.5-k3s1`, `ghcr.io/siderolabs/kubelet:v1.36.4` et `v1.36.5`, `docker.io/traefik/whoami:v1.11.0` ; empreintes de kind 0.33.0, k3d 5.9.0 (son k3s par défaut affiché par `k3d version` : **v1.35.5-k3s1**), clusterctl 1.12.11, talosctl 1.14.2 ;
- Talos : schéma soumis à l'Image Factory (`POST /schematics` → `ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515`, identique à celui de la documentation Proxmox de Talos) ; image `nocloud-amd64.raw.zst` v1.14.1 téléchargée (233 Mo, empreinte `2ce91eaa…724d`, stable entre deux téléchargements) ; installeur `factory.talos.dev/nocloud-installer/<schéma>:v1.14.2` présent ; `talosctl gen config` 1.14.2 exécuté : la configuration produite est **multi-documents** (`UnattendedInstallConfig`, `HostnameConfig auto: stable`, `KubeletConfig`, `KubeNodeConfig`, `DiscoveryServiceConfig` vers `discovery.talos.dev`…) ; `talos/generer.sh` exécuté avec un bundle de secrets de test, *patch* de nœud fusionné (`talosctl machineconfig patch`) et `talosctl validate --mode cloud` sans erreur ; lecture du code de la plateforme *nocloud* de Talos 1.14.2 (nom d'hôte repris du `user-data` de Proxmox, `#cloud-config` ignoré comme configuration machine) ;
- RKE2 : guide de durcissement CIS, pages SELinux, *Known Issues* (firewalld, NetworkManager), Pod Security (`/etc/rancher/rke2/rke2-pss.yaml`), Traefik par défaut en 1.36 (documentation à jour) ; matrice de support SUSE de RKE2 1.36 (pas de Debian, Rocky 10.0 à 10.2) ;
- configuration de containerd de l'image `kindest/node:v1.36.4` lue dans l'image (format **v2**, sans `config_path`) ; `k3d config migrate` accepte `k3d/dev.yaml` (schéma `k3d.io/v1alpha5`) ;
- rôles `outils_distributions`, `k3s`, `rke2`, playbooks et sources d'inventaire : `ansible-lint` 26.9 (profil `production`, ansible-core 2.21 ; rôles des modules précédents remplacés par des bouchons, donc non relus ici) ; manifestes : `yamllint` et `kubeconform -strict` ; scripts et checks : `shellcheck -x`, `bash -n`.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- aucun cluster n'a été démarré : l'environnement de rédaction n'avait ni Proxmox, ni cgroup v2 (kind 1.36 y refuse de démarrer, c'est d'ailleurs le comportement attendu de Kubernetes ≥ 1.35 sur cgroup v1). Les sorties montrées sont **représentatives** ;
- le nom d'hôte des nœuds Talos tiré du `user-data` de Proxmox, puis remplacé par le *patch* `HostnameConfig` ; l'absence d'annonce DDNS des nœuds Talos (d'où les adresses fixes) ;
- la décompression `zst` par Proxmox de l'image Talos (`decompression_algorithm`) et l'import du disque par `file_id` sur `local-nvme` (LVM-thin ou ZFS) ;
- les délais de premier démarrage de RKE2 (tirage des images du plan de contrôle) : `async: 900` dans le rôle ;
- l'effet exact de `--disable=servicelb` sur un k3s déjà démarré (documenté : composant retiré) ;
- la politique de redémarrage des conteneurs de kind après un redémarrage de l'hôte (lis-la avec `docker inspect`).

---

### M18-E01 — Questions : panorama des distributions Kubernetes

**Barème** : 2 points par question, total sur 32. Au-dessous de 16, relis les « Concepts clés » de l'introduction ; les questions 4-6 sont reprises en E02, 7-8 en E03 et E07, 9-10 en E04, 11-12 en E05-E06, 13-16 en E08-E12.

**1. Ce que kubeadm ne fait pas.** Installer un runtime (containerd) et le configurer pour le kubelet (cgroups systemd, image pause) ; installer les paquets kubelet/kubectl et les tenir à une version ; fournir un CNI (le réseau des pods) ; fournir un point d'accès redondant devant les API (VIP, répartiteur) ; une classe de stockage par défaut ; un contrôleur Ingress ; la sauvegarde planifiée d'etcd ; des mises à jour automatiques ; un durcissement de l'hôte (paramètres noyau, profils). k3s et RKE2 embarquent runtime, CNI, CoreDNS, stockage local (k3s), Ingress, un contrôleur Helm, des instantanés etcd planifiés et une méthode de montée de version (system-upgrade-controller) ; RKE2 ajoute un profil CIS.

**2. Conformité CNCF.** Elle garantit que la distribution passe la suite de tests de conformité (Sonobuoy) d'une version de Kubernetes : les API stables se comportent comme l'amont, un manifeste portable s'y applique. Elle ne garantit **rien** sur la sécurité par défaut, la qualité du support, la durée de vie des versions, les performances, la facilité de montée de version, ni le comportement des composants ajoutés (Ingress, stockage). k3s, RKE2 et Talos sont certifiés ; kind aussi (c'est l'outil de test de Kubernetes lui-même).

**3. Réponse B.** RKE2 et k3s suivent les versions mineures de l'amont, publiées en général dans les jours qui suivent un correctif (canaux `stable`, `latest`, par mineure) ; kubeadm *est* l'amont. A est faux (pas de branche principale en production) ; C est faux : RKE2 a un cycle de support documenté par SUSE ; D est faux : le canal `latest` de RKE2 est en 1.37 au moment de la rédaction, comme l'amont. Les vraies raisons de choisir RKE2 sont ailleurs : durcissement par défaut, support commercial possible, cycle de vie intégré.

**4. Un nœud kind.** Un conteneur Docker à partir de l'image `kindest/node`, qui exécute **systemd** comme PID 1, et sous lui **containerd** et le **kubelet** ; sur le nœud de contrôle, les composants du plan de contrôle sont des pods statiques lancés par ce kubelet, comme avec kubeadm (c'est kubeadm qui installe). Mode privilégié : le kubelet et containerd doivent créer des espaces de noms et des cgroups pour **leurs** conteneurs, monter des systèmes de fichiers (overlay), charger des règles iptables/nftables ; un conteneur ordinaire n'en a pas le droit. Conséquence : un utilisateur qui crée des clusters kind est root sur l'hôte (comme tout membre du groupe `docker`).

**5. Ce que kind ne teste pas fidèlement.** (a) Le **réseau réel** : tous les nœuds partagent le pont Docker de l'hôte, pas de MTU réelle, pas de BGP vers la bordure, pas de pannes de lien → on teste sur `k8s-par1` ou un cluster de VMs. (b) Le **stockage** : `local-path` dans un conteneur ; ni ceph-csi, ni instantanés réels, ni détachement de volume quand un nœud tombe → cluster de VMs. (c) Le **noyau et l'OS** : un seul noyau pour tous les nœuds (celui de l'hôte), donc ni montée de version de l'OS, ni différences de modules noyau, ni cgroups réellement isolés → VMs. On peut ajouter : les montées de version du cluster (kind recrée, il ne monte pas), la perte d'un nœud (arrêter un conteneur n'est pas perdre une machine), les performances.

**6. Image locale introuvable.** `docker images` montre le magasin d'images **du démon Docker** de l'hôte. Les nœuds kind (ou k3d) sont des conteneurs qui ont **leur propre containerd** et leur propre magasin ; le kubelet demande l'image à ce containerd, qui ne la trouve pas et tente un registre (`docker.io/library/mediagenda-api`), où elle n'existe pas. Corrections : (1) la charger dans les nœuds (`kind load docker-image`, `k3d image import`) avec `imagePullPolicy: IfNotPresent` et une étiquette autre que `latest` ; (2) la pousser dans un registre que les nœuds joignent (registre local du poste, ou Harbor `medisphere` avec un robot), ce qui ressemble davantage à la production.

**7. kine et SQLite.** *kine* (« kine is not etcd ») est une couche qui expose l'API gRPC d'etcd (celle que le kube-apiserver utilise) et la traduit vers une base SQL : SQLite (par défaut pour un serveur k3s unique), PostgreSQL, MySQL ou NATS. SQLite suffit pour **un seul serveur** : petit site, poste, CI ; il consomme moins de mémoire et d'E/S qu'etcd. On perd : la haute disponibilité (un seul fichier sur un seul nœud), les outils d'etcd (instantanés `etcdctl`, défragmentation) ; on ne peut pas ajouter un second serveur sans changer de base (migration vers etcd intégré par `--cluster-init`, voir E07, ou base externe).

**8. Réponse B.** L'état du cluster (objets de l'API, PKI, jeton) est dans `/var/lib/rancher/k3s/server/` du serveur ; les agents ne le répliquent pas (A faux) ; Harbor stocke des images, pas des objets (C faux) ; k3s recrée une base **vide** et une nouvelle PKI s'il ne trouve rien (D faux : on obtient un autre cluster, auquel les agents n'ont plus confiance). D'où, à l'agence : sauvegarde du dossier `server/` (base **et** `tls/`, token) et manifestes reconstructibles depuis Git (palier 3, E14).

**9. Le profil CIS de RKE2.** Au démarrage avec `profile: cis`, RKE2 **vérifie** que les paramètres noyau exigés (ceux de `rke2-cis-sysctl.conf` : `vm.panic_on_oom=0`, `vm.overcommit_memory=1`, `kernel.panic=10`, `kernel.panic_on_oops=1`) ont les bonnes valeurs, que l'utilisateur et le groupe `etcd` existent, et refuse de démarrer sinon ; il pose `protect-kernel-defaults` sur le kubelet, fait tourner etcd sous `etcd`, applique Pod Security `restricted`, des NetworkPolicies dans les espaces de base et des droits restrictifs. Il ne modifie pas l'hôte parce que c'est l'OS qui en est responsable (gestion de configuration, durcissement de l'OS, image dorée) : un binaire qui changerait des paramètres noyau ou créerait des comptes en silence serait lui-même un problème d'audit, et pourrait contredire la politique de l'hôte.

**10. Le superviseur.** Le processus `rke2 server` (ou `k3s server`) est un superviseur qui lance et surveille les composants, et sert sur 9345 (RKE2 ; sur k3s, le même service est multiplexé sur 6443) l'API d'**enregistrement** : un nœud qui rejoint s'y authentifie avec le jeton, récupère la CA et ses certificats, la configuration commune (options critiques identiques sur tous les serveurs), puis lance son kubelet. Le port 6443 est le kube-apiserver, l'API Kubernetes elle-même, pour les clients et les kubelets une fois enregistrés. D'où deux ports à ouvrir devant les serveurs RKE2 et une adresse d'enregistrement stable.

**11. Talos sans SSH.** Journaux du kubelet : `talosctl -n <ip> logs kubelet` (ou `dmesg`, `logs machined`). NTP : *patch* de la configuration (`TimeSyncConfig` en 1.14) appliqué par `talosctl patch mc` ou `apply-config`. Agent QEMU : ce n'est pas un paquet, c'est une **extension système** intégrée à l'image par l'Image Factory (schéma) : on change de schéma, donc d'image, par `talosctl upgrade --image <installeur du nouveau schéma>`. Correctif du noyau : nouvelle version de Talos (le noyau fait partie de l'image), `talosctl upgrade` nœud par nœud ; retour arrière par le schéma A/B (`talosctl rollback`).

**12. Réponse B.** La surface d'attaque se réduit parce qu'il n'y a **rien** à attaquer en dehors de l'API (pas de shell, pas de démon SSH, pas d'interpréteurs ni d'outils), que le système est en lecture seule (un attaquant qui obtient l'exécution de code ne peut pas installer de persistance sur le système) et que l'état est entièrement décrit (image signée + configuration) : un nœud douteux se réinstalle à l'identique. A : le chiffrement du disque est une option de Talos, mais ce n'est pas lui qui réduit la surface ; C : l'API Talos (50000) et le kubelet écoutent ; D : les composants tournent en conteneurs, certains privilégiés.

**13. Gestion et charge de travail.** Le cluster de **gestion** porte les CRD et contrôleurs de Cluster API et les objets qui décrivent les autres clusters ; un cluster de **charge de travail** est un cluster décrit par ces objets, où tournent les applications. Un cluster peut se gérer lui-même (*self-hosted* : on pivote ses objets dans lui-même), c'est même un schéma documenté. Risque : une panne ou une erreur sur ce cluster empêche aussi de le **réparer** par Cluster API (les contrôleurs qui devraient remplacer la machine en panne tournent sur elle), et une montée de version mal engagée se bloque elle-même. Chez MédiSphère : un petit cluster de gestion distinct (`k3s01` en E12), sauvegardé.

**14. Les fournisseurs.** **Infrastructure** (ici CAPMOX ; CAPO pour OpenStack, CAPD pour Docker) : crée les machines et l'infrastructure du cluster (VMs clonées, adresses, VIP éventuelle) ; **amorçage** (*bootstrap*, kubeadm) : génère les données cloud-init qui font d'une machine un nœud (`kubeadm init`/`join`) ; **plan de contrôle** (`KubeadmControlPlane`) : gère le nombre et la version des nœuds de contrôle, les certificats, le remplacement un par un. Plus le **cœur** (Cluster, Machine, MachineDeployment…) et, chez nous, l'**IPAM** *in-cluster*. Passer de Proxmox à OpenStack ne change que le fournisseur d'infrastructure (et les objets `*Template` qui lui sont propres) ; kubeadm reste.

**15. Amorcer dans kind, puis pivoter.** Il faut un cluster Kubernetes pour faire tourner Cluster API… y compris pour créer le premier cluster. kind en fournit un en une minute, jetable, sur un poste ; on y crée le cluster de gestion durable (ou on en prépare un autre), on y installe les fournisseurs, puis `clusterctl move` déplace les objets. Garder le cluster de gestion dans kind sur un poste : il disparaît avec le poste (ou une mise en veille), personne ne le sauvegarde, les contrôleurs ne tournent pas en permanence (pas de réparation automatique, pas de réconciliation la nuit), et les identifiants Proxmox vivent sur un portable. C'est l'objet de E12.

**16. Monter de version par un objet.** Changer `spec.version` du `KubeadmControlPlane` (et le template de machine) déclenche un **remplacement progressif** : CAPI crée une nouvelle machine à la nouvelle version (clonée d'un nouveau template), attend qu'elle soit nœud de contrôle et membre etcd sain, puis retire une ancienne (drain, retrait du membre etcd, suppression de la VM), et ainsi de suite ; même chose pour les travailleurs avec le `MachineDeployment` (`maxSurge`/`maxUnavailable`). Les machines sont **immuables** : on ne les met pas à jour, on les remplace. D'où une nouvelle image : le template contient kubelet/kubeadm/containerd à la version voulue ; un `apt upgrade` sur des VMs existantes ferait diverger les nœuds de leur description et serait invisible pour CAPI (et défait au prochain remplacement).

---

### M18-E02 — kind et k3d : des clusters de développement

**Solution**

*1. L'environnement OpenTofu.* Fichiers dans [`fichiers/M18-E02/infra/envs/m18/`](fichiers/M18-E02/infra/envs/m18/). L'idée : une table `local.catalogue` de toutes les VMs Debian et Rocky du module, filtrée par `var.groupes`, passée au module `vm-noeud` v2.4 :

```hcl
hotes = { for nom, h in local.catalogue : nom => h if contains(var.groupes, h.groupe) }
…
cartes = [{ vnet = "vsandbox", ipv4 = "dhcp", mac = format("bc:24:11:99:18:%02d", each.value.vmid % 100) }]
```

```
admin@adm01:~/src/infra/envs/m18$ set -a; source ~/.config/workbook/pve-tofu.env; source ~/.config/workbook/netbox-tofu.env; source ~/.config/workbook/powerdns-api.env; set +a
admin@adm01:~/src/infra/envs/m18$ tofu init && tofu plan -out m18.plan
admin@adm01:~/src/infra/envs/m18$ tofu apply m18.plan
admin@adm01:~/src/infra/envs/m18$ tofu output hotes
```

Le fournisseur PowerDNS est déclaré dès maintenant (il servira aux nœuds Talos en E05) ; ses variables sont éphémères et sensibles, comme dans `envs/k8s`.

*2. Inventaire et playbook.* [`netbox-m18.yml`](fichiers/M18-E02/ansible/inventories/lab/netbox-m18.yml) est la copie de `netbox-m12.yml` avec l'étiquette `env-m18` ; ajoute-le à la ligne `inventory` d'`ansible.cfg`. Le playbook [`m18.yml`](fichiers/M18-E02/ansible/playbooks/m18.yml) (version de E02) : rôles communs sur `env_m18`, puis `docker_engine`, `outils_k8s`, `outils_distributions` et une tâche `sysctl` (limites inotify) sur `role_m18_dev`, et `outils_distributions` sur `adm01` avec `outils_distributions_choix: [clusterctl, talosctl]` ([`host_vars/adm01/`](fichiers/M18-E02/ansible/inventories/lab/host_vars/adm01/outils_distributions.yml)).

```
admin@adm01:~/src/ansible$ uv run ansible-inventory --graph env_m18
@env_m18:
  |--m18-dev01
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/m18.yml --limit m18-dev01,adm01
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/m18.yml --limit m18-dev01,adm01   # 0 changement
```

Le rôle [`outils_distributions`](fichiers/M18-E02/ansible/roles/outils_distributions/) suit `outils_k8s` : dossier versionné, `get_url` avec `checksum: sha256:<empreinte>`, lien dans `/usr/local/bin`. Différence volontaire : les empreintes sont **écrites dans le rôle** au lieu d'être lues dans un fichier de sommes à l'exécution. Deux raisons concrètes : le fichier de sommes de k3d nomme le binaire `_dist/k3d-linux-amd64` (le module `get_url` ne le retrouverait pas), et clusterctl n'en publie pas pour v1.12.11.

*3. Le projet.* `plateforme/distributions` sur le modèle de `plateforme/k8s` : protection de `main`, MR obligatoire, `.gitlab-ci.yml` qui inclut `qualite.yml` (pre-commit : Gitleaks, `yamllint`, `shellcheck` sur `*.sh`). Sur `m18-dev01`, clone HTTPS en lecture (`git clone https://git01.par1.medisphere.internal/plateforme/distributions.git ~/src/distributions`) : pas de clé SSH de poussée sur une VM jetable.

*4. kind.* [`kind/dev.yaml`](fichiers/M18-E02/distributions/kind/dev.yaml) : trois nœuds, même image à l'empreinte, deux montages (dossier `certs.d/` du dépôt, racine MédiSphère de l'hôte) et un *patch* de containerd. Le *patch* vient de la lecture de `/etc/containerd/config.toml` dans l'image : format **v2** (`version = 2`), sans `config_path` ; la clé à ajouter est donc `[plugins."io.containerd.grpc.v1.cri".registry] config_path = "/etc/containerd/certs.d"`. Les `hosts.toml` ([`kind/certs.d/`](fichiers/M18-E02/distributions/kind/certs.d/)) sont ceux de M14-E19, avec `ca =` vers la racine montée et `server =` en repli.

```
admin@m18-dev01:~$ time kind create cluster --config ~/src/distributions/kind/dev.yaml
Creating cluster "dev" ...
 ✓ Ensuring node image (kindest/node:v1.36.4) 🖼
 ✓ Preparing nodes 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
real    1m31s
admin@m18-dev01:~$ kubectl --context kind-dev get nodes
NAME                STATUS   ROLES           AGE   VERSION
dev-control-plane   Ready    control-plane   62s   v1.36.4
dev-worker          Ready    <none>          41s   v1.36.4
dev-worker2         Ready    <none>          41s   v1.36.4
admin@m18-dev01:~$ docker exec dev-worker ps -e | head
    PID TTY          TIME CMD
      1 ?        00:00:00 systemd
     94 ?        00:00:00 systemd-journal
    106 ?        00:00:01 containerd
    214 ?        00:00:02 kubelet
    …
admin@m18-dev01:~$ docker exec dev-worker cat /etc/containerd/certs.d/docker.io/hosts.toml | head -5
```

*5. Image locale.*

```
admin@m18-dev01:~/m18/e02$ cat Dockerfile
FROM docker.io/library/busybox:1.37
USER 65534
CMD ["sh", "-c", "echo 'MédiSphère : image locale chargée'; sleep 3600"]
admin@m18-dev01:~/m18/e02$ docker build -t medisphere/essai:local .
admin@m18-dev01:~$ kubectl --context kind-dev run essai --image=medisphere/essai:local --image-pull-policy=IfNotPresent
admin@m18-dev01:~$ kubectl --context kind-dev get pod essai     # ErrImagePull : docker.io/medisphere/essai:local
admin@m18-dev01:~$ kind load docker-image medisphere/essai:local --name dev
admin@m18-dev01:~$ kubectl --context kind-dev delete pod essai && kubectl --context kind-dev run essai --image=medisphere/essai:local --image-pull-policy=IfNotPresent
admin@m18-dev01:~$ kubectl --context kind-dev logs essai
MédiSphère : image locale chargée
admin@m18-dev01:~$ k3d image import medisphere/essai:local --cluster dev
```

L'image construite par Docker 29 est dans son magasin containerd (stockage d'images containerd par défaut, M12), mais dans **l'espace de noms de Docker** (`moby`) du containerd de l'**hôte**, alors que le kubelet du nœud kind interroge **son** containerd (espace `k8s.io`) dans son conteneur. `kind load` fait un `docker save` puis un import dans chaque nœud ; `k3d image import` passe par un conteneur outil qui fait la même chose.

*6. k3d.* [`k3d/dev.yaml`](fichiers/M18-E02/distributions/k3d/dev.yaml) : `image:` fixée (k3d 5.9.0 prendrait v1.35.5-k3s1), `registries.config` contient le texte d'un `registries.yaml` de k3s, `volumes` monte la racine, `--disable=traefik` sur le serveur.

```
admin@m18-dev01:~$ free -m | sed -n 2p
admin@m18-dev01:~$ time k3d cluster create --config ~/src/distributions/k3d/dev.yaml
admin@m18-dev01:~$ kubectl --context k3d-dev get nodes -o wide
NAME               STATUS   ROLES                  AGE   VERSION        …
k3d-dev-agent-0    Ready    <none>                 20s   v1.36.5+k3s1
k3d-dev-agent-1    Ready    <none>                 20s   v1.36.5+k3s1
k3d-dev-server-0   Ready    control-plane,master   28s   v1.36.5+k3s1
admin@m18-dev01:~$ docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}'
```

*7. Limites.* Un Service `LoadBalancer` reste `<pending>` dans kind (aucun contrôleur) et reçoit l'adresse des conteneurs nœuds dans k3d (ServiceLB). Après redémarrage de `m18-dev01`, les conteneurs de kind sont relancés par Docker (politique de redémarrage des conteneurs nœuds, à lire avec `docker inspect -f '{{.HostConfig.RestartPolicy}}' dev-control-plane`) mais kind ne promet pas que le cluster revienne sain ; k3d se relance par `k3d cluster start dev`. `kubectl top nodes` : erreur dans kind (pas de metrics-server), valeurs dans k3d. Fichiers [`kind/README.md`](fichiers/M18-E02/distributions/kind/README.md), [`k3d/README.md`](fichiers/M18-E02/distributions/k3d/README.md).

*8. Documentation.* [`poste-dev.md`](fichiers/M18-E02/medisphere/docs/kubernetes/distributions/poste-dev.md), [`mesures.md`](fichiers/M18-E02/medisphere/docs/kubernetes/distributions/mesures.md) (ordres de grandeur à remplacer par tes mesures).

**Explications**

kind et k3d sont deux réponses au même besoin. kind installe un vrai kubeadm dans des conteneurs : ses nœuds ressemblent à ceux de `k8s-par1` (manifestes statiques, fichiers de kubeadm), c'est l'outil de test du projet Kubernetes et de Cluster API (il servira de cluster d'amorçage en E08). k3d emballe k3s : plus léger et plus rapide, avec ServiceLB et metrics-server, mais une autre distribution que la production. Un poste de développement peut avoir les deux ; le choix dépend de ce qu'on teste.

L'empreinte de l'image n'est pas un détail : kind publie une image de nœud **par version de kind** (elle dépend de l'outil qui l'a construite) ; une étiquette `v1.36.4` peut être reconstruite par une version ultérieure de kind et ne plus convenir à 0.33. C'est pour cela que les notes de version insistent sur `@sha256`.

**Alternatives**

- **minikube** : une VM ou un conteneur, un seul nœud par défaut, beaucoup d'extensions ; plus lourd, moins scriptable que kind pour la CI.
- **Registre local** partagé par les clusters (`k3d registry create`, registre `registry:3` du M12) au lieu du chargement d'images : plus proche du flux réel, plus rapide quand les images sont grosses.
- **Rancher Desktop / Docker Desktop** : clusters intégrés sur les postes macOS/Windows des développeurs ; hors du lab.
- `vm-noeud` avec une carte DHCP et le groupe `dev` plutôt qu'une ressource ad hoc : c'est le choix fait, pour que `m18-dev01` soit une VM comme les autres (NetBox, inventaire, rôles communs).

**Pièges classiques**

- Oublier `image:` dans k3d : on obtient k3s 1.35 sans s'en rendre compte (`kubectl get nodes` l'affiche, encore faut-il regarder).
- Une étiquette kind sans empreinte : un nœud construit pour une autre version de kind peut ne pas démarrer, avec des erreurs obscures dans `kubeadm init`.
- `hostPath` relatif dans `extraMounts` : utilise des chemins absolus (le dépôt est dans `~/src/distributions` du compte `admin`).
- `imagePullPolicy: Always` (ou l'étiquette `:latest`, qui l'implique) avec une image chargée : le kubelet tente quand même de la tirer et échoue.
- Mémoire : un cluster kind de trois nœuds plus un k3d de trois nœuds consomment plusieurs Go ; `m18-dev01` (8 Go) devra aussi porter le cluster de gestion de E08 et image-builder en E09 : supprime les clusters `dev` avant.
- Mettre des identifiants (robot Harbor, jeton) dans `kind/` ou `k3d/` : les caches Harbor sont publics en tirage, aucun secret n'est nécessaire ici.

**En production chez MédiSphère**

Le poste de référence devient une image (Packer, M03) ou un environnement de développement standard (`devcontainer`) ; les fichiers `kind/` et `k3d/` sont repris par les dépôts des équipes ; en CI (M19), kind sert aux tests d'intégration des charts (`ct install`). On ne met jamais de données réelles dans ces clusters, et le groupe `docker` n'est donné qu'à des comptes qui sont déjà administrateurs de leur poste.

---

### M18-E03 — k3s : un cluster léger pour l'agence

**Solution**

1. `groupes = ["dev", "k3s"]` dans `terraform.tfvars`, MR, `tofu apply` (≈ 1 min 30 pour la VM). Inventaire : `k3s01` entre dans `env_m18` et `role_k3s` par ses étiquettes.

2. Le script :
   ```
   admin@adm01:~/m18/e03$ curl -fsSLo install.sh 'https://raw.githubusercontent.com/k3s-io/k3s/v1.36.5%2Bk3s1/install.sh'
   admin@adm01:~/m18/e03$ sha256sum install.sh
   46177d4c99440b4c0311b67233823a8e8a2fc09693f6c89af1a7161e152fbfad  install.sh
   admin@adm01:~/m18/e03$ grep -o 'INSTALL_K3S_[A-Z_]*' install.sh | sort -u
   ```
   Ce qu'on y lit : `setup_env` choisit `server` ou `agent` (d'après `INSTALL_K3S_EXEC`, ou la présence de `K3S_URL`) ; `download_and_verify` télécharge `sha256sum-amd64.txt` de la version et vérifie le binaire ; `create_env_file` recopie les variables `K3S_*` de l'environnement dans `/etc/systemd/system/k3s.service.env` (c'est pourquoi on ne lui passe **pas** `K3S_TOKEN`) ; il crée `k3s-killall.sh` et `k3s-uninstall.sh`, et les liens `kubectl`, `crictl`, `ctr`. Sa version à `get.k3s.io` est plus récente (empreinte différente) : figer le script **du tag** garde le même installateur pour la même version. Fichier [`k3s/README.md`](fichiers/M18-E03/distributions/k3s/README.md).

3. Le rôle [`k3s`](fichiers/M18-E03/ansible/roles/k3s/) : préconditions ; script téléchargé dans `/usr/local/lib/k3s/install-<version>.sh` avec `checksum` ; jeton dans `/etc/rancher/k3s/jeton` (600, `no_log`) ; `config.yaml` = `k3s_config` fusionné avec `token-file`, et selon le cas `cluster-init` ou `server` ; `registries.yaml` depuis `k3s_miroirs` ; installation **seulement** si `k3s --version` ne donne pas la version voulue (ou si `k3s_gere_version` est faux, jamais pour une montée : utile en E07) ; service activé ; attente de `/readyz`.

4. Variables : [`host_vars/k3s01/k3s.yml`](fichiers/M18-E03/ansible/inventories/lab/host_vars/k3s01/k3s.yml), [`group_vars/role_k3s/k3s.yml`](fichiers/M18-E03/ansible/inventories/lab/group_vars/role_k3s/k3s.yml) (miroirs) et le Vault ([exemple](fichiers/M18-E03/ansible/inventories/lab/group_vars/role_k3s/vault-lab.yml.exemple)) :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-vault create --vault-id lab@outils/vault-pass-client.sh inventories/lab/group_vars/role_k3s/vault-lab.yml
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/m18.yml --limit k3s01 --diff
   ```
   Le `config.yaml` rendu :
   ```yaml
   disable:
     - traefik
     - servicelb
   node-name: k3s01
   tls-san:
     - k3s01.par1.medisphere.internal
   token-file: /etc/rancher/k3s/jeton
   write-kubeconfig-mode: '0600'
   ```

5. Observation :
   ```
   admin@k3s01:~$ sudo k3s kubectl get pods -A
   NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
   kube-system   coredns-…                                 1/1     Running   0          2m
   kube-system   local-path-provisioner-…                  1/1     Running   0          2m
   kube-system   metrics-server-…                          1/1     Running   0          2m
   admin@k3s01:~$ sudo ls /var/lib/rancher/k3s/server/manifests/ /var/lib/rancher/k3s/server/db/
   /var/lib/rancher/k3s/server/manifests/:
   ccm.yaml  coredns.yaml  local-storage.yaml  metrics-server  rolebindings.yaml  runtimes.yaml
   /var/lib/rancher/k3s/server/db/:
   state.db  state.db-shm  state.db-wal
   admin@k3s01:~$ sudo cat /var/lib/rancher/k3s/agent/etc/containerd/certs.d/docker.io/hosts.toml
   # File generated by k3s. DO NOT EDIT. …
   [host."https://registry.par1.medisphere.internal/v2/dockerhub"]
     capabilities = ["pull", "resolve"]
     override_path = true
     ca = ["/usr/local/share/ca-certificates/medisphere-root-ca.crt"]
   ```
   Pas de `traefik.yaml` dans `manifests/`, pas de pods `svclb-*` ni `helm-install-traefik-*` : les deux composants sont désactivés. Note : sans `cluster-init`, la base est SQLite par kine.

6. Kubeconfig :
   ```
   admin@adm01:~$ ssh k3s01 sudo cat /etc/rancher/k3s/k3s.yaml \
       | sed -e 's#https://127.0.0.1:6443#https://k3s01.par1.medisphere.internal:6443#' -e 's/: default$/: k3s01/' \
       | install -m 600 /dev/stdin ~/.config/workbook/m18/k3s01.kubeconfig
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/k3s01.kubeconfig get nodes
   NAME    STATUS   ROLES           AGE   VERSION
   k3s01   Ready    control-plane   6m    v1.36.5+k3s1
   ```
   Le `sed` renomme cluster, utilisateur et contexte `default` en `k3s01` (le kubeconfig de k3s utilise `default` pour les trois) ; aucune option TLS particulière : le certificat porte le nom (`tls-san`), la CA est celle du kubeconfig. `install -m 600 /dev/stdin` crée le fichier directement en 600.

7. L'agence : [`k3s/agence/`](fichiers/M18-E03/distributions/k3s/agence/) (espace en `restricted`, `whoami` en utilisateur 65534 sur le port 8080 : l'image écoute en 80 par défaut, ce qui exigerait root).
   ```
   admin@adm01:~/src/distributions$ kubectl --kubeconfig ~/.config/workbook/m18/k3s01.kubeconfig apply -f k3s/agence/
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/k3s01.kubeconfig -n agence get pods -o wide
   ```
   Dans Harbor, projet `dockerhub` : dépôt `dockerhub/traefik/whoami`, étiquette `v1.11.0`, dernier tirage récent.

8. Fiche [`k3s.md`](fichiers/M18-E03/medisphere/docs/kubernetes/distributions/k3s.md) ; mesures : ≈ 1 min 30 pour la VM, ≈ 1 min pour le playbook, ≈ 500 à 600 Mo de mémoire utilisée au repos (k3s seul), trois fichiers de configuration.

**Explications**

k3s n'est pas « Kubernetes allégé » : ce sont les mêmes binaires Kubernetes, compilés dans un seul exécutable avec containerd et des composants choisis, et une base qui peut ne pas être etcd. La légèreté vient de là (un seul processus, SQLite) et des valeurs par défaut (flannel VXLAN, local-path). Les composants embarqués sont des manifestes que le serveur applique depuis `server/manifests/` (Helm controller pour Traefik) ; `--disable` les retire et les empêche de revenir. Tout passe par `config.yaml` : un argument oublié sur une ligne de commande ne se relit pas en MR, un fichier si.

Le `registries.yaml` de k3s est traduit au démarrage en `hosts.toml` de son containerd embarqué : c'est le même mécanisme qu'au M14, avec un format différent. Un point d'accès dont le chemin n'est ni vide, ni `/`, ni `/v2` (ici `/v2/dockerhub`) est utilisé tel quel (`override_path`, lu dans `pkg/agent/containerd/config.go` de k3s).

**Alternatives**

- **Rôle communautaire** (`k3s-io/k3s-ansible`) : complet, mais un rôle de plus à relire et à suivre ; le nôtre fait trente tâches et colle à nos conventions.
- **Binaire et service écrits par le rôle**, sans le script : possible (le binaire et sa somme sont publiés), mais il faudrait réécrire le service, les scripts de nettoyage et les liens ; le script figé fait cela sans surprise.
- **Installation hors ligne** (*air-gap*) : `INSTALL_K3S_SKIP_DOWNLOAD` et l'archive d'images `k3s-airgap-images-amd64.tar.zst` déposées par Ansible ; utile pour une agence derrière une liaison fragile (à considérer dans l'ADR).
- **Garder ServiceLB** pour publier un service sur l'adresse de la machine : simple, mais il ouvre des ports sur l'hôte par Service ; à l'agence, la passerelle et un Ingress feront mieux.

**Pièges classiques**

- `curl -sfL https://get.k3s.io | sh -` : on exécute un script non relu, d'une version qui change, en root.
- `K3S_TOKEN` passé au script : il finit en clair dans `/etc/systemd/system/k3s.service.env`.
- `tls-san` oublié : le kubeconfig de `adm01` échoue (`x509: certificate is valid for k3s01, localhost, … not k3s01.par1.medisphere.internal`), et la tentation est `--insecure-skip-tls-verify`.
- `write-kubeconfig-mode: 644` (vu dans beaucoup de tutoriels) : tout compte local lit un kubeconfig administrateur.
- Modifier `/var/lib/rancher/k3s/agent/etc/containerd/certs.d/…` à la main : k3s le réécrit au démarrage depuis `registries.yaml`.
- Oublier l'espace de noms en `restricted` : k3s n'impose aucun niveau Pod Security par défaut.

**En production chez MédiSphère**

À l'agence : machine physique ou VM sur un petit hyperviseur, sauvegarde du dossier `server/` vers PAR1 (instantanés et copie hors site, palier 3), images en cache local (miroir embarqué de k3s ou archive *air-gap*) pour survivre à une coupure de la liaison, montées de version par system-upgrade-controller (E07) dans une fenêtre définie, identités nominatives (OIDC au M24) à la place du kubeconfig administrateur, supervision remontée vers PAR1 (M21).

---

### M18-E04 — RKE2 : un cluster durci

**Solution**

1. `groupes = ["dev", "k3s", "rke2"]`, `tofu apply` : trois clones Rocky 10 (`famille = "rocky10"` → CPU `x86-64-v3` dans `vm-noeud`).

2. [`rke2/README.md`](fichiers/M18-E04/distributions/rke2/README.md) : tableau « hôte / RKE2 / toi ». À retenir : le profil **vérifie** les paramètres noyau et l'utilisateur `etcd` et refuse de démarrer sinon ; il **applique** `protect-kernel-defaults`, etcd sous `etcd`, Pod Security `restricted`, des NetworkPolicies dans `kube-system`, `kube-public`, `default`, des droits 600.

3. Le rôle [`rke2`](fichiers/M18-E04/ansible/roles/rke2/) :
   - clé importée **avec** son empreinte (`rpm_key fingerprint:`) puis deux dépôts `yum_repository` (`common/centos/10/noarch`, `1.36/centos/10/x86_64`) ;
   - `kernel-modules-extra` (nf_conntrack sur RHEL 10) ;
   - groupe et utilisateur système `etcd` (sans dossier personnel, `/sbin/nologin`), dans `/etc/passwd` (le guide rappelle que l'annuaire NSS ou systemd-userdb ne convient pas) ;
   - firewalld arrêté et désactivé, fichier `/etc/NetworkManager/conf.d/rke2-canal.conf` ;
   - paquet `rke2-server-1.36.5~rke2r1` (il tire `rke2-common` et `rke2-selinux`) ;
   - copie de `/usr/share/rke2/rke2-cis-sysctl.conf` en `/etc/sysctl.d/60-rke2-cis.conf` puis redémarrage de `systemd-sysctl` **seulement** si le fichier vient d'être posé (installation neuve, avant RKE2) ;
   - `config.yaml` (`rke2_config` + `token-file` + `node-name`, et `server: https://rke2-01…:9345` sauf sur le premier serveur), `registries.yaml` ;
   - démarrage (`async: 900`, le premier démarrage tire les images), attente de `/readyz`.
   Le playbook ([`m18.yml`](fichiers/M18-E04/ansible/playbooks/m18.yml)) joue le rôle avec `order: sorted` et `serial: 1` : `rke2-01` d'abord (il amorce etcd), puis `rke2-02`, puis `rke2-03`, chacun seulement quand le précédent répond.

4. Variables [`group_vars/role_rke2/rke2.yml`](fichiers/M18-E04/ansible/inventories/lab/group_vars/role_rke2/rke2.yml) ; Vault `vault_rke2_jeton`.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/m18.yml --limit role_rke2 --diff
   ```
   ≈ 12 à 15 min pour les trois nœuds.

5. Observation :
   ```
   [admin@rke2-01 ~]$ sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes
   NAME      STATUS   ROLES                       AGE   VERSION
   rke2-01   Ready    control-plane,etcd,master   14m   v1.36.5+rke2r1
   rke2-02   Ready    control-plane,etcd,master   8m    v1.36.5+rke2r1
   rke2-03   Ready    control-plane,etcd,master   3m    v1.36.5+rke2r1
   [admin@rke2-01 ~]$ ps -o user=,comm= -C etcd
   etcd     etcd
   [admin@rke2-01 ~]$ sudo ls -ld /var/lib/rancher/rke2/server/db/etcd
   drwx------. 3 etcd etcd 37 … /var/lib/rancher/rke2/server/db/etcd
   [admin@rke2-01 ~]$ sudo grep -A8 'defaults' /etc/rancher/rke2/rke2-pss.yaml
       defaults:
         enforce: "restricted"
         …
       exemptions:
         namespaces: [kube-system, compliance-operator-system, tigera-operator]
   [admin@rke2-01 ~]$ ps -eZ | grep 'rke2 server'
   system_u:system_r:container_runtime_t:s0 1234 ? 00:01:20 rke2
   ```
   Le libellé de rôle `master` affiché à côté de `control-plane` peut varier selon la version : l'essentiel est `control-plane,etcd`.

6. Kubeconfig (même méthode qu'en E03, `127.0.0.1` → `rke2-01.par1.medisphere.internal`, `default` → `rke2`) dans `~/.config/workbook/m18/rke2.kubeconfig`. Puis :
   ```
   admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/rke2.kubeconfig
   admin@adm01:~$ kubectl get networkpolicies -A
   NAMESPACE     NAME                                  POD-SELECTOR   AGE
   default       default-network-policy                <none>         15m
   kube-public   default-network-policy                <none>         15m
   kube-system   default-network-dns-policy            k8s-app=kube-dns   15m
   kube-system   default-network-policy                <none>         15m
   …
   admin@adm01:~/src/distributions$ kubectl apply -f rke2/essai-cis/espace.yaml
   admin@adm01:~/src/distributions$ kubectl apply --dry-run=server -f rke2/essai-cis/pod-refuse.yaml
   Error from server (Forbidden): error when creating "rke2/essai-cis/pod-refuse.yaml": pods "refuse" is forbidden:
   violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "attente" must set
   securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (…), runAsNonRoot != true (…),
   seccompProfile (…)
   admin@adm01:~/src/distributions$ kubectl apply -f rke2/essai-cis/pod-conforme.yaml && kubectl -n essai-cis get pod conforme
   ```
   Les noms exacts des NetworkPolicies peuvent différer selon la version : ce qui compte, c'est qu'il y en ait dans les trois espaces de base et **aucune** dans `essai-cis`. Manifestes : [`rke2/essai-cis/`](fichiers/M18-E04/distributions/rke2/essai-cis/).

7. Fiche [`rke2.md`](fichiers/M18-E04/medisphere/docs/kubernetes/distributions/rke2.md) ; mesures (≈ 13 min, ≈ 1,6 à 1,9 Go utilisés par nœud au repos) ; arrêt des trois VMs.

**Explications**

RKE2 garde l'architecture de k3s (superviseur, configuration par fichier, jeton, enregistrement sur 9345) mais fait des choix de production : etcd systématique, composants du plan de contrôle en pods statiques (`/var/lib/rancher/rke2/agent/pod-manifests/`), images construites et scannées par SUSE, Canal par défaut, Traefik comme Ingress depuis 1.36 (ingress-nginx déprécié, retiré en 1.37), et le profil CIS. Le profil est un **contrat** : l'hôte fournit ce que RKE2 ne doit pas faire lui-même (comptes, noyau), RKE2 applique ce qui relève de Kubernetes. Le rôle Ansible matérialise la part de l'hôte, ce qui rend la chose auditable.

firewalld et Canal : Canal (Calico + flannel) écrit ses propres règles iptables/nftables ; firewalld, qui gère aussi les tables, peut les écraser lors d'un rechargement. La documentation de RKE2 recommande donc de le désactiver ; le filtrage se fait alors en amont (bordure) et par des politiques réseau (Calico). C'est un compromis à écrire dans la fiche : l'hôte n'a plus de pare-feu local géré par l'OS.

**Alternatives**

- **Script `get.rke2.io`** sur Rocky : il configure les mêmes dépôts RPM (méthode `rpm`), mais c'est un script de plus à relire ; déclarer les dépôts est plus lisible en Ansible.
- **Méthode tarball** : à éviter sur un nœud SELinux *enforcing* (ni `rke2-selinux` ni `selinux: true`).
- **Un serveur + deux agents** : plus proche d'un petit site, moins de mémoire, mais etcd sans quorum de secours ; trois serveurs reproduisent `k8s-par1` pour la comparaison.
- **Ubuntu 24.04** (supporté) : il faudrait une famille d'images de plus au catalogue ; Rocky 10 existe déjà (M03, M08).
- **Garder firewalld** en ouvrant les ports et en mettant les interfaces du CNI en zone de confiance : possible, documenté par la communauté, mais hors de la configuration supportée.

**Pièges classiques**

- Créer l'utilisateur `etcd` **après** le premier démarrage : RKE2 refuse de démarrer (« missing etcd user »), ou le dossier de données reste à root.
- Recharger les paramètres noyau sur un nœud en service : la documentation met en garde (le CNI règle ses propres paramètres).
- Démarrer les trois serveurs en même temps : les deux derniers tentent de joindre un superviseur qui n'existe pas encore ; `serial: 1` et le premier serveur d'abord.
- Oublier un nom dans `tls-san` : le kubeconfig de `adm01` échoue sur ce nom.
- Mettre `protect-kernel-defaults: false` en même temps que `profile: cis` : RKE2 sort en erreur.
- Croire que le profil couvre « tout le CIS » : les contrôles manuels (audit, RBAC, Secrets, politiques réseau des applications) restent à faire (E15).

**En production chez MédiSphère**

Une VIP (kube-vip ou keepalived) devant 9345 et 6443, des instantanés etcd planifiés envoyés vers `s3-01` (RKE2 sait le faire nativement, palier 3), le guide d'auto-évaluation CIS v2.0 tenu à jour avec nos réponses aux contrôles manuels, l'OS durci selon le CIS Rocky Linux, et des NetworkPolicies par défaut créées avec chaque espace d'équipe (Kyverno au M26 pourra les générer).

---

### M18-E05 — Talos Linux : un OS immuable piloté par API

**Solution**

*1. L'image.* Schéma [`talos-schema.yaml`](fichiers/M18-E05/infra/envs/m18/talos-schema.yaml) :
```
admin@adm01:~/src/infra/envs/m18$ curl -sS -X POST --data-binary @talos-schema.yaml https://factory.talos.dev/schematics
{"id":"ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515","schematic":"customization:\n    systemExtensions:\n …"}
```
Le schéma « vide » (`customization:` sans rien) a l'identifiant `376567988ad3…b4ba`. Les identifiants diffèrent parce qu'ils sont l'**empreinte du contenu** du schéma : la même liste d'extensions donne le même identifiant pour tout le monde, l'Image Factory n'a rien à mémoriser de plus, et l'identifiant suffit à reconstruire l'image pour n'importe quelle version (`/image/<id>/<version>/…`) ou l'installeur (`factory.talos.dev/nocloud-installer/<id>:<version>`). Corollaire : l'identifiant ne révèle pas le contenu (on ne peut pas lister les schémas des autres).

*2. Les VMs.* [`talos.tf`](fichiers/M18-E05/infra/envs/m18/talos.tf) : une ressource `proxmox_download_file` (Proxmox télécharge lui-même `nocloud-amd64.raw.zst` sur `hdd-bulk` en contenu `iso`, le décompresse, vérifie l'empreinte) et trois `proxmox_virtual_environment_vm` dont le disque est importé depuis ce fichier (`file_id`). Matériel : `scsi_hardware = "virtio-scsi-pci"`, `bios = "ovmf"` + `efi_disk` (`pre_enrolled_keys = false`), `machine = "q35"`, `memory.floating = 0`, agent activé, console série. Le bloc `initialization` crée le lecteur cloud-init de Proxmox avec l'adresse fixe, la passerelle et les résolveurs ; rien d'autre (pas de compte). Enregistrements DNS par `enregistrement-dns`.

```
admin@adm01:~/src/infra/envs/m18$ tofu apply      # groupes = ["dev", "k3s", "talos"] : RKE2 a été retiré en fin de E04
admin@adm01:~$ ssh root@pve01 qm terminal 2185
  … [talos] entering maintenance mode …
  [talos] this machine is reachable at: 10.10.99.85
```

Les VMs démarrent dès leur création (`started = true`) : sur la console, chaque nœud est en **mode maintenance** (aucune configuration machine), son adresse vient du lecteur cloud-init.

*3. La configuration.* Scripts [`talos/generer.sh`](fichiers/M18-E05/distributions/talos/generer.sh) et [`talos/appliquer.sh`](fichiers/M18-E05/distributions/talos/appliquer.sh), données [`versions.env`](fichiers/M18-E05/distributions/talos/versions.env), [`noeuds.txt`](fichiers/M18-E05/distributions/talos/noeuds.txt), patches [`noeuds/`](fichiers/M18-E05/distributions/talos/noeuds/), [`.gitignore`](fichiers/M18-E05/distributions/talos/.gitignore).
```
admin@adm01:~$ talosctl gen secrets -o ~/.config/workbook/m18/talos-secrets.yaml && chmod 600 ~/.config/workbook/m18/talos-secrets.yaml
admin@adm01:~/src/distributions$ uv --project ~/src/ansible run ansible-vault encrypt --vault-id lab@$HOME/src/ansible/outils/vault-pass-client.sh \
    --output talos/secrets/talos-secrets.yaml.vault ~/.config/workbook/m18/talos-secrets.yaml
admin@adm01:~/src/distributions$ talos/generer.sh
admin@adm01:~$ grep '^kind:' ~/.cache/m18/talos/controlplane.yaml | sort | uniq -c
```
`generer.sh` appelle `talosctl gen config talos-essai https://talos-01.par1.medisphere.internal:6443 --with-secrets … --kubernetes-version 1.36.4 --install-image factory.talos.dev/nocloud-installer/ce4c98…:v1.14.1 --with-docs=false --with-examples=false`, ajoute les patches communs ou par type s'il y en a (aucun en E05), puis valide les deux fichiers (`talosctl validate --mode cloud`). Le fichier généré contient un document `v1alpha1` réduit (type, autorité et jeton de la machine, `cluster.etcd`, quelques options) **et une vingtaine de documents** : `UnattendedInstallConfig` (installeur, disque `/dev/sda`), `ResolverConfig`, `VolumeConfig`, `HostnameConfig` (`auto: stable`), `KubeClusterConfig` (nom, point d'accès), `KubeNodeConfig` (étiquette et taint du plan de contrôle), `KubeletConfig` (`ghcr.io/siderolabs/kubelet:v1.36.4`), `KubeNetworkConfig` (10.244.0.0/16, 10.96.0.0/12), les autorités et la configuration du kube-apiserver, `KubeFlannelCNIConfig`, `KubeCoreDNSConfig`… Celui qui parle à l'extérieur : **`DiscoveryServiceConfig`**, point d'accès `https://discovery.talos.dev/`, le service de découverte public de Sidero Labs (les membres du cluster y publient des données chiffrées pour se trouver ; utile pour KubeSpan). Pour un hébergeur de données de santé souverain, c'est à retirer : E06 le fait.

*4. Premier contact.*
```
admin@adm01:~/src/distributions$ talosctl get disks --insecure --nodes 10.10.99.85     # sda : le disque importé
admin@adm01:~/src/distributions$ talos/appliquer.sh talos-01 --maintenance
admin@adm01:~/src/distributions$ talos/appliquer.sh talos-02 --maintenance
admin@adm01:~/src/distributions$ talos/appliquer.sh talos-03 --maintenance
```
`--insecure` parce qu'un nœud en maintenance n'a encore **aucune** identité : pas de certificat signé par la CA du cluster, il ne peut donc pas authentifier le client ni être authentifié par lui ; le canal est chiffré (TLS) mais sans vérification. Une fois la configuration appliquée, le nœud a sa PKI et n'accepte plus que le mTLS avec un client du `talosconfig` (rôle `os:admin`). C'est pourquoi on vérifie, avant, que l'adresse est bien la bonne VM (console Proxmox), et qu'on ne fait ce premier contact que sur `vsandbox`, depuis `adm01`. Le disque : l'image *nocloud* est déjà « installée » sur le disque importé ; `UnattendedInstallConfig` désigne `/dev/sda`, ce qui correspond (contrôleur SCSI).

*5. Amorçage.*
```
admin@adm01:~$ export TALOSCONFIG=~/.config/workbook/m18/talosconfig
admin@adm01:~$ talosctl config endpoint 10.10.99.85
admin@adm01:~$ talosctl config node 10.10.99.85
admin@adm01:~$ talosctl --nodes 10.10.99.85 bootstrap
admin@adm01:~$ talosctl --nodes 10.10.99.85 health
discovered nodes: ["10.10.99.85" "10.10.99.86" "10.10.99.87"]
waiting for etcd to be healthy: OK
waiting for etcd members to be consistent across nodes: OK
waiting for apid to be ready: OK
waiting for kubelet to be healthy: OK
waiting for all nodes to finish boot sequence: OK
waiting for all k8s nodes to report: OK
waiting for all control plane static pods to be running: OK
…
admin@adm01:~$ talosctl --nodes 10.10.99.85 kubeconfig ~/.config/workbook/m18/talos.kubeconfig && chmod 600 ~/.config/workbook/m18/talos.kubeconfig
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/talos.kubeconfig get nodes -o wide
NAME       STATUS   ROLES           AGE   VERSION   INTERNAL-IP   OS-IMAGE           KERNEL-VERSION   CONTAINER-RUNTIME
talos-01   Ready    control-plane   4m    v1.36.4   10.10.99.85   Talos (v1.14.1)    6.18.…-talos     containerd://2.3.6
talos-02   Ready    <none>          4m    v1.36.4   10.10.99.86   Talos (v1.14.1)    …
talos-03   Ready    <none>          4m    v1.36.4   10.10.99.87   Talos (v1.14.1)    …
```
`talosctl kubeconfig <fichier>` écrit un kubeconfig dont le contexte s'appelle `admin@talos-essai` (à ne pas confondre avec le contexte du `talosconfig`, nommé `talos-essai` par `gen config`). Le point d'accès (`endpoints`) est l'adresse à laquelle `talosctl` se connecte ; les nœuds (`--nodes`) sont ceux qui exécutent la commande (relayée par le point d'accès si besoin). Avec un seul nœud de contrôle, l'API Talos et l'API Kubernetes ont un seul point d'accès : pas de haute disponibilité (assumé pour l'essai ; une VIP de couche 2 `Layer2VIPConfig` le permettrait avec trois nœuds de contrôle).

*6. Vivre sans SSH.*
```
admin@adm01:~$ talosctl -n 10.10.99.85 service                      # apid, containerd, cri, etcd, kubelet, machined, trustd, udevd… ext-qemu-guest-agent
admin@adm01:~$ talosctl -n 10.10.99.86 logs kubelet --tail 50
admin@adm01:~$ talosctl -n 10.10.99.85 dmesg | head -40
admin@adm01:~$ talosctl -n 10.10.99.85 get extensions               # qemu-guest-agent, et « schematic ce4c9805… »
admin@adm01:~$ talosctl -n 10.10.99.85 memory ; talosctl -n 10.10.99.85 processes
admin@adm01:~$ talosctl -n 10.10.99.85 get hostname
admin@adm01:~$ talosctl -n 10.10.99.85 get hostnamespec --namespace network-config
admin@adm01:~$ talosctl dashboard
admin@adm01:~$ nc -zv -w 3 10.10.99.86 22      # refusé : aucun démon SSH
admin@adm01:~$ ssh root@pve01 qm agent 2186 network-get-interfaces | head    # l'agent QEMU répond
```
`get hostnamespec` montre les sources du nom : la plateforme (*nocloud*, nom repris du `user-data` de Proxmox), puis la configuration (`HostnameConfig` du patch, `auto: off`), qui l'emporte.

*7.* Fiche [`talos.md`](fichiers/M18-E05/medisphere/docs/kubernetes/distributions/talos.md) ; mesures : ≈ 2 min pour les VMs (hors premier téléchargement de l'image), ≈ 4 min de l'`apply-config` au cluster sain, ≈ 400 à 500 Mo utilisés sur un travailleur au repos.

**Explications**

Talos change la nature de l'exploitation : il n'y a plus d'état « à côté » de la configuration. Ce que tu modifierais sur un nœud Debian (paquets, fichiers, services) n'existe pas ; tout est soit dans l'image (noyau, extensions : schéma de l'Image Factory), soit dans la configuration machine (documents YAML, PKI incluse). Reproduire un nœud = même image + même configuration. C'est aussi pourquoi les secrets du cluster sont dans le bundle `talosctl gen secrets` : sans lui, on ne régénère pas la même configuration ; avec lui, on la régénère à l'identique à tout moment (le dépôt n'a que les *patches*).

La configuration multi-documents (Talos 1.12 à 1.14) remplace progressivement le gros document `v1alpha1` : un document par sujet, fusionné par `kind` (et `name` pour les documents nommés). Un *patch* stratégique est un fragment de documents ; un document inconnu de la configuration est ajouté, un document existant est fusionné, `$patch: delete` le retire. Un champ `v1alpha1` déprécié et son document de remplacement s'excluent : on écrit la nouvelle forme.

La plateforme *nocloud* : Talos lit au démarrage les métadonnées du lecteur `cidata` (ou du numéro de série SMBIOS), en tire réseau et nom d'hôte ; la configuration machine elle-même pourrait y être (`user-data`), mais celle de Proxmox est un `#cloud-config`, que Talos ignore comme configuration. D'où le mode maintenance puis `apply-config`.

**Alternatives**

- **ISO** `metal` de l'Image Factory et installation sur disque : la page Proxmox de Talos le décrit (boot ISO, mode maintenance, `apply-config`, installation sur `/dev/sda`) ; une étape de plus et une ISO à gérer.
- **Configuration par SMBIOS** (`ds=nocloud-net;s=http://…/`) : la VM télécharge sa configuration au démarrage, plus de `--insecure`, mais il faut un serveur HTTP qui sert des configurations contenant des clés (à protéger strictement).
- **Fournisseur OpenTofu `siderolabs/talos`** : génère secrets et configurations, applique, amorce, depuis le code ; les secrets finissent dans l'état OpenTofu (à chiffrer), mais tout le cycle devient un `tofu apply`. Bonne option pour la production, à discuter dans l'ADR.
- **Omni** (SaaS ou auto-hébergé, Sidero Labs) : gestion de flotte Talos ; hors périmètre.
- **Trois nœuds de contrôle + VIP** (`Layer2VIPConfig`) : vraie HA ; 3 Go × 3 en plus, hors budget du module.

**Pièges classiques**

- « VirtIO SCSI single » (la valeur par défaut de beaucoup de modèles et de `vm-noeud`) : l'amorçage se bloque d'après la documentation Talos.
- Ballon mémoire activé : Talos ne voit pas toute la mémoire.
- `talosctl bootstrap` lancé deux fois, ou sur un autre nœud : refus ou etcd séparé.
- Oublier `--kubernetes-version` : Talos 1.14 installe Kubernetes 1.37, que notre écosystème (Cilium 1.20, CAPMOX) ne suit pas.
- Prendre l'installeur `metal-installer` pour une image *nocloud*, ou le schéma vide : les montées de version perdent l'agent QEMU (l'installeur doit porter **le même schéma** que l'image).
- Versionner `controlplane.yaml` ou `talosconfig` « pour gagner du temps » : ils contiennent la CA du cluster et la clé administrateur (Gitleaks les signale).
- Confondre `endpoints` et `nodes` dans `talosctl` : commande envoyée au mauvais nœud, ou « connection refused » sur un travailleur pris pour point d'accès (les travailleurs exposent aussi l'API Talos, mais le relais se fait par les nœuds de contrôle).

**En production chez MédiSphère**

Image Factory **auto-hébergée** (ou au minimum un cache des images et installeurs dans Harbor) pour ne pas dépendre de `factory.talos.dev` ; service de découverte désactivé ou interne ; trois nœuds de contrôle et une VIP ; `talosconfig` personnels à durée courte (`talosctl config new --roles os:reader` pour la supervision) ; bundle de secrets en Vault (M25) ; sauvegardes etcd par `talosctl etcd snapshot` (palier 3) ; chiffrement des volumes système (TPM ou clé statique) ; supervision par DaemonSets (M21).
