# Module 18 — Palier 1 : Découverte

Avant de comparer, il faut avoir monté. Ce palier commence par un questionnaire de panorama, puis installe une distribution par exercice, chaque fois **par le code** : des clusters de développement dans des conteneurs (kind, k3d) sur un poste dédié, un k3s monoœud pour l'agence de Lyon, un RKE2 de trois nœuds au profil CIS, et un cluster Talos Linux piloté uniquement par son API. À chaque essai, tu notes les mêmes mesures dans `docs/kubernetes/distributions/mesures.md` : elles nourriront l'ADR-0180.

Prérequis : module 14 terminé (`lab/bin/check 14 46` vert), module 12 (rôle `docker_engine`), module 05 (OpenTofu, `vm-noeud` v2.4 avec carte DHCP depuis M12-E02), images dorées Debian 13 et Rocky 10 `current` (M03). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, le budget mémoire et les règles du module. `k8s-par1` est **arrêté** (règle 1).

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| État OpenTofu | `plateforme/infra`, `envs/m18/` ; variable `groupes` : `["dev"]` en E02, puis `"k3s"` (E03), `"rke2"` (E04), `"talos"` (E05) |
| VMs | `m18-dev01` 2188, `k3s01` 2181, `rke2-01..03` 2182-2184, `talos-01..03` 2185-2187 (introduction, tableau des hôtes) ; MAC `bc:24:11:99:18:<deux derniers chiffres du VMID>` |
| Projets | `plateforme/distributions` (clone `~/src/distributions`), `plateforme/ansible` (playbook `playbooks/m18.yml`, source `inventories/lab/netbox-m18.yml`), `plateforme/medisphere` (`docs/kubernetes/distributions/`) |
| Cache d'images | Harbor `registry.par1.medisphere.internal`, projets *proxy cache* `dockerhub`, `quay`, `ghcr`, `k8s` (M13) ; racine MédiSphère `/usr/local/share/ca-certificates/medisphere-root-ca.crt` (rôle `ca_lab`) |
| Fichiers locaux | `~/.config/workbook/m18/` sur `adm01` (700, fichiers 600) |
| Mesures | `docs/kubernetes/distributions/mesures.md` : une section par essai, mêmes rubriques (temps d'installation, mémoire au repos, nombre de fichiers ou de commandes, version obtenue, remarques) |

---

### M18-E01 — Questions : panorama des distributions Kubernetes  `Q` `★★`

> **Ticket PLAT-1901** — *De : Karim Benali*
> Avant de monter quoi que ce soit, je veux savoir ce que tu crois savoir. Une heure, à froid, sans documentation. On reparlera de tes réponses quand tu auras tout installé : c'est l'écart entre les deux qui m'intéresse.

**Objectifs pédagogiques**
- Situer kubeadm, kind, k3d, k3s, RKE2, Talos Linux et Cluster API les uns par rapport aux autres.
- Identifier les critères qui départagent des distributions (cible, base de données, surface d'attaque, montée de version, support).
- Préparer les questions auxquelles les essais du module devront répondre.

**Prérequis** : module 14.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 16 questions par écrit, dans `~/m18/e01/reponses.md`. Pour les QCM, justifie ton choix en une ou deux phrases. Garde le fichier : tu le reliras au mini-projet.

*Ce qu'est une distribution*

1. kubeadm est souvent présenté comme « l'installateur officiel ». Cite quatre choses que kubeadm **ne fait pas** et qu'une distribution comme k3s ou RKE2 fait à ta place.

2. Qu'est-ce que la certification **CNCF Kubernetes conformance** garantit d'une distribution ? Qu'est-ce qu'elle ne garantit pas ?

3. *(QCM)* Une équipe dit « on passe de kubeadm à RKE2 pour avoir un Kubernetes plus récent ». Quelle réponse est la bonne ?
   - A. C'est vrai : RKE2 suit la branche principale de Kubernetes, kubeadm les versions stables
   - B. C'est faux : les deux distribuent les mêmes versions mineures de Kubernetes, à quelques jours ou semaines près ; le choix ne porte pas sur la version
   - C. C'est vrai : RKE2 n'a pas de politique de support et livre tout de suite
   - D. C'est faux : RKE2 a toujours deux mineures de retard

*Clusters de développement*

4. kind et k3d font tourner des « nœuds » dans des conteneurs. Qu'est-ce qui tourne **dans** un conteneur nœud de kind ? Pourquoi faut-il le lancer en mode privilégié ?

5. Cite trois choses qu'on ne peut **pas** tester fidèlement dans un cluster kind, et pour chacune ce qu'on testerait à la place.

6. Une image construite sur ton poste (`docker build -t mediagenda-api:essai .`) n'est pas trouvée par un pod de ton cluster kind (`ErrImagePull`). Pourquoi, alors qu'elle est bien dans `docker images` ? Donne deux façons de corriger.

*Distributions légères et durcies*

7. k3s peut tourner avec **SQLite** ou avec **etcd intégré**. Qu'est-ce que *kine* ? Dans quel cas SQLite suffit-il, et qu'est-ce qu'on perd ?

8. *(QCM)* Un serveur k3s unique dans une agence, avec SQLite. Le disque de la VM meurt. Que perd-on ?
   - A. Rien : l'état du cluster est répliqué sur les agents
   - B. L'état du cluster (objets, certificats, jeton) : sans sauvegarde du dossier de données, il faut tout recréer
   - C. Seulement les pods en cours : les objets sont dans Harbor
   - D. Seulement les certificats : k3s reconstruit la base au démarrage

9. Que vérifie RKE2 au démarrage quand on lui donne le **profil CIS** ? Pourquoi ne modifie-t-il pas lui-même l'hôte ?

10. RKE2 et k3s ont un « superviseur » qui écoute sur un port à part (9345 pour RKE2). À quoi sert-il, par rapport au port 6443 du kube-apiserver ?

*Systèmes immuables*

11. Talos Linux n'a ni SSH, ni shell, ni gestionnaire de paquets. Comment fait-on, alors, pour : lire les journaux du kubelet ; changer le serveur NTP ; ajouter l'agent QEMU ; installer un correctif de sécurité du noyau ?

12. *(QCM)* Pourquoi un OS immuable réduit-il la surface d'attaque d'un nœud ?
   - A. Parce qu'il chiffre tout le disque
   - B. Parce qu'il n'y a ni binaire superflu, ni accès interactif, ni modification persistante possible hors de l'API, et que l'état du nœud se résume à une image signée plus une configuration déclarée
   - C. Parce qu'il refuse toute connexion réseau entrante
   - D. Parce que Kubernetes y tourne sans privilège root

*Cluster API*

13. Dans Cluster API, qu'est-ce qu'un **cluster de gestion** et un **cluster de charge de travail** ? Le cluster de gestion peut-il être aussi un cluster de charge de travail ? Avec quel risque ?

14. Cite les trois familles de fournisseurs (*providers*) d'une installation Cluster API classique et le rôle de chacune. Lequel change si on passe de Proxmox à OpenStack ?

15. Pourquoi amorce-t-on souvent un cluster de gestion dans **kind**, pour le déplacer ensuite (*pivot*) ailleurs ? Que se passerait-il si on gardait le cluster de gestion dans kind sur un poste ?

16. Avec Cluster API, monter un cluster de 1.36.4 en 1.36.5 consiste à changer une valeur dans un objet. Qu'est-ce qui se passe alors sur les machines ? Pourquoi a-t-on besoin d'une **nouvelle image de nœud** et pas seulement d'un `apt upgrade` ?

**Critères de réussite**
- [ ] Les 16 réponses sont écrites, les QCM justifiés.
- [ ] Auto-correction faite avec le corrigé ; tu as noté dans `reponses.md` les trois questions sur lesquelles tu t'es le plus trompé et l'exercice du module qui y répond.

**Vérification** : auto-évaluation avec le corrigé (pas de script).

<details><summary>Indice 1</summary>

Pour la question 1, repars de ce que tu as dû faire **en plus** de `kubeadm init` au M14 : runtime, paquets, réseau des pods, point d'accès redondant, sauvegarde, montée de version.
</details>

<details><summary>Indice 2</summary>

Pour Cluster API, pense à l'analogie avec un Deployment : un objet décrit l'état voulu, des contrôleurs le réalisent. Qui joue le rôle du kubelet quand la « chose » à créer est une VM ?
</details>

---

### M18-E02 — kind et k3d : des clusters de développement  `LAB` `★`

> **Ticket DEV-1902** — *De : Julien Petit*
> Pour tester un chart ou une migration, on attend que la plateforme nous ouvre un espace sur `k8s-par1`. Il me faudrait un vrai cluster jetable par développeur, sur un poste, qu'on crée en une commande et qu'on jette le soir. On a regardé kind et k3d, on ne sait pas choisir. Tu peux nous préparer un poste de référence, et les deux, avec les fichiers de configuration qu'on reprendra ?

**Objectifs pédagogiques**
- Créer l'environnement du module par le code (état `envs/m18`, projet `plateforme/distributions`, playbook `m18.yml`).
- Monter un cluster kind multi-nœuds et un cluster k3d à partir de fichiers de configuration versionnés, à une version de Kubernetes fixée.
- Charger une image locale dans un cluster sans registre, et brancher les clusters sur le cache Harbor.
- Constater les limites de ces clusters.

**Prérequis** : modules 05 (OpenTofu), 12 (rôle `docker_engine`), 14 (rôle `outils_k8s`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- VM `m18-dev01` (2188) : Debian 13, 4 vCPU, 8 Go, 60 Gio sur `local-nvme`, `vsandbox` en DHCP, MAC `bc:24:11:99:18:88`, étiquettes `env-m18` et `role-m18-dev`. Elle reçoit Docker Engine 29 (rôle `docker_engine` du M12), kubectl et Helm (rôle `outils_k8s` du M14), et les outils du module (nouveau rôle **`outils_distributions`**) : kind **0.33.0**, k3d **5.9.0**, clusterctl **1.12.11**, talosctl **1.14.2**. Sur `adm01`, seuls clusterctl et talosctl sont ajoutés.
- Versions de Kubernetes : kind 0.33 publie ses images de nœud avec leur empreinte dans ses notes de version, et **il faut utiliser l'empreinte** ; il n'y a pas d'image 1.36.5 pour kind 0.33 : prends `kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed`. k3d 5.9.0 démarre par défaut un k3s 1.35 : impose `rancher/k3s:v1.36.5-k3s1`.
- Les deux clusters s'appellent `dev` (contextes kubectl `kind-dev` et `k3d-dev`) et vivent sur `m18-dev01`. Topologie : un nœud de contrôle et deux travailleurs pour kind, un serveur et deux agents pour k3d.
- Le cache Harbor : les nœuds de kind utilisent containerd (fichiers `hosts.toml` sous `/etc/containerd/certs.d/`, comme au M14-E19) ; ceux de k3d lisent un `registries.yaml` de k3s. Les nœuds doivent faire confiance à la racine MédiSphère.

**Travail demandé**
1. **Environnement OpenTofu.** Crée `envs/m18/` dans `plateforme/infra` (même structure que `envs/m12` : `versions.tf` avec la clé d'état `envs/m18/terraform.tfstate`, `providers.tf`, `variables.tf`). Décris les VMs Debian et Rocky du module dans une table, avec le module `vm-noeud` v2.4, et une variable `groupes` (liste) qui choisit les familles créées : `dev` (`m18-dev01`), `k3s` (`k3s01`), `rke2` (`rke2-01..03`). Applique avec `groupes = ["dev"]` seulement. MR, relecture, `tofu plan` propre.
2. **Inventaire et playbook.** Ajoute la source `inventories/lab/netbox-m18.yml` (sur le modèle de `netbox-m12.yml`) et le playbook `playbooks/m18.yml` : rôles communs pour tout `env_m18`, puis `docker_engine`, `outils_k8s` et `outils_distributions` pour `role_m18_dev`. Écris le rôle `outils_distributions` (binaires amont vérifiés par la somme publiée, installés dans un dossier versionné et liés dans `/usr/local/bin`, comme `outils_k8s`). Vérifie :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph env_m18
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/m18.yml --check --diff
   ```
3. **Projet `plateforme/distributions`.** Crée-le (branche `main` protégée, MR, CI de qualité avec `yamllint`), clone-le sur `adm01` et sur `m18-dev01` (en lecture, par HTTPS).
4. **kind.** Écris `kind/dev.yaml` : nom, trois nœuds avec l'image ci-dessus, et le branchement sur le cache Harbor (lis la documentation de kind sur `containerdConfigPatches` et `extraMounts`). Crée le cluster, puis :
   ```
   admin@m18-dev01:~$ kind create cluster --config ~/src/distributions/kind/dev.yaml
   admin@m18-dev01:~$ kubectl --context kind-dev get nodes -o wide
   admin@m18-dev01:~$ docker ps --format '{{.Names}}\t{{.Image}}'
   ```
   Regarde ce qui tourne **dans** un nœud (`docker exec dev-worker ps -e`, `docker exec dev-worker crictl ps`).
5. **Une image locale.** Construis une petite image sur `m18-dev01` (`docker build -t medisphere/essai:local …`, par exemple un `FROM docker.io/library/busybox:1.37` qui affiche un message), lance un pod qui l'utilise dans `kind-dev`, constate l'échec, puis charge-la (`kind load docker-image`) et relance. Fais de même avec k3d plus loin (`k3d image import`). Explique dans `kind/README.md` pourquoi c'est nécessaire et ce que fait la commande.
6. **k3d.** Écris `k3d/dev.yaml` (schéma `k3d.io/v1alpha5`) : nom, un serveur, deux agents, image fixée, `registries.yaml` vers le cache Harbor, et désactive Traefik (on n'en veut pas sur un poste). Crée le cluster, compare : temps de création (`time`), mémoire de `m18-dev01` (`free -m`) avant et après chaque cluster.
7. **Limites.** Essaie : un Service `LoadBalancer` dans chaque cluster (que se passe-t-il ?) ; redémarrer `m18-dev01` (les clusters reviennent-ils ?) ; `kubectl top nodes`. Note tes observations dans `kind/README.md` et `k3d/README.md`.
8. **Documentation et mesures.** `docs/kubernetes/distributions/poste-dev.md` (ce qu'on installe, comment créer et jeter un cluster, ce qu'on ne doit pas y tester) ; section « kind » et « k3d » de `mesures.md`. Laisse les deux clusters `dev` en place jusqu'à la vérification, puis supprime-les si tu as besoin de mémoire.

**Critères de réussite**
- [ ] `m18-dev01` (2188) existe dans l'état `envs/m18`, avec les ressources, la MAC et les étiquettes du plan ; `uv run ansible-playbook playbooks/m18.yml` repasse sans changement.
- [ ] Sur `m18-dev01` : Docker 29.8, kind 0.33.0, k3d 5.9.0, kubectl 1.36, clusterctl 1.12.11, talosctl 1.14.2 ; sur `adm01` : clusterctl et talosctl aux mêmes versions.
- [ ] Le cluster `kind-dev` a trois nœuds `Ready` en v1.36.4 dont les conteneurs utilisent l'image à l'empreinte fixée ; ses nœuds ont un `hosts.toml` qui renvoie `docker.io` vers le cache Harbor.
- [ ] Le cluster `k3d-dev` a un serveur et deux agents `Ready` en v1.36.5+k3s1, sans Traefik.
- [ ] L'image `medisphere/essai:local` est présente sur les nœuds des deux clusters (chargée, pas tirée).
- [ ] `plateforme/distributions` (branche `main`) contient `kind/dev.yaml`, `k3d/dev.yaml` et leurs `README.md` ; `plateforme/medisphere` contient `docs/kubernetes/distributions/poste-dev.md` et `mesures.md`.

**Vérification** : `lab/bin/check 18 02`

<details><summary>Indice 1</summary>

`vm-noeud` accepte une carte `{ vnet = "vsandbox", ipv4 = "dhcp", mac = … }` depuis M12-E02. Pour n'allumer qu'une partie des VMs, filtre ta table avec un `for … if contains(var.groupes, …)`.
</details>

<details><summary>Indice 2</summary>

Un nœud kind est un conteneur : un fichier de l'hôte n'y existe que s'il est monté (`extraMounts`). Il faut y monter la racine MédiSphère et des `hosts.toml`, et dire à containerd où les lire (`config_path`). Pour k3d, la clé `registries.config` du fichier de configuration contient directement le texte du `registries.yaml` de k3s, et `files` permet de déposer un fichier dans les nœuds.
</details>

<details><summary>Indice 3</summary>

L'image construite par Docker est dans le magasin d'images **de Docker** sur `m18-dev01` ; les nœuds de kind ont **leur propre** containerd, dans leur conteneur. Aucun registre ne la connaît.
</details>

**Pour aller plus loin** (facultatif) : `ctlptl` ou un registre local partagé par les clusters (`k3d registry create`, registre `registry:3` du M12) pour éviter de charger chaque image à la main.

---

### M18-E03 — k3s : un cluster léger pour l'agence  `LAB` `★★`

> **Ticket PLAT-1903** — *De : Claire Morel*
> L'agence de Lyon aura une seule petite machine, pas d'informaticien, et une liaison qui tombe parfois. On veut y faire tourner trois ou quatre services. Essaie k3s sur une VM de la taille de ce qu'on achètera (2 cœurs, 4 Go). Je veux savoir ce qui est installé d'office, ce qu'on peut enlever, s'il sait tirer ses images de notre Harbor, et combien de temps ça prend de zéro à « ça marche ».

**Objectifs pédagogiques**
- Installer k3s à une version fixée, par un rôle Ansible, avec un script d'installation relu et figé.
- Connaître les composants embarqués (Traefik, ServiceLB, local-path, metrics-server, Helm controller) et désactiver ceux qui ne servent pas.
- Configurer k3s par fichier (`config.yaml`) plutôt que par arguments, et brancher containerd sur le cache Harbor (`registries.yaml`).
- Récupérer un kubeconfig utilisable depuis `adm01`.

**Prérequis** : M18-E02.
**Durée indicative** : 2 h 30.

**Contexte technique**
- VM `k3s01` (2181) : Debian 13, 2 vCPU, 4 Go, 32 Gio, `vsandbox` DHCP, MAC `bc:24:11:99:18:81`, étiquettes `env-m18`, `role-k3s` (groupe `k3s` de la variable `groupes`).
- k3s **v1.36.5+k3s1** (canal `stable` au 2026-10-15). Le script d'installation se télécharge **au tag de la version** (`https://raw.githubusercontent.com/k3s-io/k3s/v1.36.5%2Bk3s1/install.sh`) : c'est lui qui vérifie l'empreinte du binaire qu'il télécharge. Tu relis le script, tu fixes son empreinte SHA-256 dans le rôle, et le rôle refuse un script différent.
- Ce nœud unique garde la base par défaut de k3s (SQLite par *kine*) : pas de `--cluster-init`.
- Composants : l'agence n'a pas d'Ingress ni de répartiteur de services pour l'instant (ils viendront avec la passerelle de Lyon) : Traefik et ServiceLB sont désactivés ; le provisionneur `local-path` et metrics-server sont gardés.
- Le jeton du cluster (`token`) est un secret : Ansible Vault `lab`, variable `vault_k3s_jeton_k3s01`, dans `group_vars/role_k3s/vault-lab.yml`.
- Le certificat du kube-apiserver doit porter le nom `k3s01.par1.medisphere.internal` (le kubeconfig de `adm01` vise ce nom, pas une adresse DHCP).

**Travail demandé**
1. Ajoute `"k3s"` à `groupes` dans `envs/m18` ; MR, `tofu apply`. Mesure le temps à partir d'ici.
2. Télécharge le script d'installation au tag, **lis-le** (variables `INSTALL_K3S_*`, ce qu'il écrit dans `/etc/systemd/system/`, `/usr/local/bin/`, les scripts `k3s-killall.sh` et `k3s-uninstall.sh`), calcule son empreinte. Note dans `k3s/README.md` de `plateforme/distributions` les trois variables du script que le rôle utilise et pourquoi.
3. Écris le rôle **`k3s`** dans `plateforme/ansible`, générique (il servira en E07 pour un cluster à trois serveurs et au palier 3 pour un agent) : variables de version, de rôle du nœud (`server`/`agent`), d'amorçage etcd (`k3s_cluster_init`), d'URL du serveur à joindre, de configuration (`k3s_config`, rendue dans `/etc/rancher/k3s/config.yaml`) et de miroirs (`registries.yaml`). Le jeton n'apparaît jamais en argument : il va dans un fichier 600 référencé par la configuration. Le rôle ne relance pas le script si la bonne version est déjà installée.
4. Variables de `k3s01` (`host_vars/k3s01/k3s.yml`) : `write-kubeconfig-mode` 600, `tls-san`, désactivation de `traefik` et `servicelb`, et les miroirs `docker.io`, `quay.io`, `ghcr.io`, `registry.k8s.io` vers le cache Harbor (chemins `/v2/<projet>` de M14-E19). Joue le playbook.
5. Depuis `k3s01`, regarde ce que k3s a installé :
   ```
   admin@k3s01:~$ sudo k3s kubectl get pods -A
   admin@k3s01:~$ sudo ls /var/lib/rancher/k3s/server/manifests/ /var/lib/rancher/k3s/server/db/
   admin@k3s01:~$ sudo cat /var/lib/rancher/k3s/agent/etc/containerd/certs.d/docker.io/hosts.toml
   admin@k3s01:~$ systemctl status k3s --no-pager
   ```
6. Récupère le kubeconfig dans `~/.config/workbook/m18/k3s01.kubeconfig` (600) sur `adm01`, avec le serveur `https://k3s01.par1.medisphere.internal:6443` et un contexte nommé `k3s01` ; le fichier ne passe jamais par un dépôt.
7. Déploie un service d'essai de l'agence dans un espace `agence` : un Deployment `whoami` (image `docker.io/traefik/whoami:v1.11.0`, 2 réplicas) et un Service ClusterIP. Vérifie dans Harbor que l'image a été tirée par le cache (projet `dockerhub`). Fichiers dans `k3s/agence/` de `plateforme/distributions`.
8. Mesures (temps, mémoire au repos de `k3s01`, nombre de fichiers écrits) dans `mesures.md` ; fiche `docs/kubernetes/distributions/k3s.md` : composants embarqués, ce qui est désactivé et pourquoi, où sont les données, comment désinstaller.

**Critères de réussite**
- [ ] `k3s01` (2181) existe avec les ressources, la MAC et les étiquettes du plan.
- [ ] `k3s --version` donne v1.36.5+k3s1 ; le service `k3s` est actif ; la base est SQLite (`/var/lib/rancher/k3s/server/db/state.db`) ; le script d'installation conservé sur le nœud a l'empreinte fixée dans le rôle.
- [ ] Le nœud est `Ready` ; Traefik et ServiceLB sont absents, local-path et metrics-server présents.
- [ ] containerd de k3s renvoie `docker.io` vers `https://registry.par1.medisphere.internal/v2/dockerhub` ; le Deployment `agence/whoami` a deux pods prêts dont l'image vient du cache (dépôt `dockerhub/traefik/whoami` présent dans Harbor).
- [ ] `~/.config/workbook/m18/k3s01.kubeconfig` est en 600, vise `https://k3s01.par1.medisphere.internal:6443` et fonctionne sans option TLS particulière.
- [ ] Le rôle `k3s` et la fiche `k3s.md` sont sur `main`.

**Vérification** : `lab/bin/check 18 03`

<details><summary>Indice 1</summary>

Tout ce qu'on passe à `k3s server` en argument peut s'écrire dans `/etc/rancher/k3s/config.yaml` (clés = noms des options sans les tirets initiaux). Les listes (`disable`, `tls-san`) s'écrivent en listes YAML.
</details>

<details><summary>Indice 2</summary>

Le script n'a pas besoin du jeton si la configuration le donne (`token-file`). Pour qu'il n'installe que le binaire et le service sans rien décider à ta place, regarde `INSTALL_K3S_VERSION`, `INSTALL_K3S_EXEC` et `INSTALL_K3S_SKIP_START`.
</details>

<details><summary>Indice 3</summary>

Le kubeconfig écrit par k3s vise `https://127.0.0.1:6443`. Pour l'utiliser ailleurs, change le serveur, et vérifie que le nom que tu mets est dans le certificat du serveur (`openssl s_client -connect k3s01.par1.medisphere.internal:6443 </dev/null | openssl x509 -noout -ext subjectAltName`).
</details>

---

### M18-E04 — RKE2 : un cluster durci  `LAB` `★★`

> **Ticket SEC-1904** — *De : Sophie Laurent*
> Pour HDS et l'audit ISO, je dois montrer que nos nœuds respectent un référentiel. Le benchmark CIS Kubernetes est celui que les auditeurs connaissent. RKE2 annonce un profil CIS « intégré ». Je veux voir concrètement ce que ce profil vérifie, ce qu'il change dans le cluster, et ce qu'il reste à faire sur l'hôte. Trois nœuds, comme en production.

**Objectifs pédagogiques**
- Installer RKE2 sur trois serveurs (etcd à trois membres) par un rôle Ansible, sur un OS supporté.
- Appliquer le profil CIS : préparer l'hôte (paramètres noyau, utilisateur `etcd`) et observer ce que RKE2 change (Pod Security, NetworkPolicies, droits des fichiers).
- Faire fonctionner RKE2 avec SELinux en mode *enforcing* et comprendre ses interactions avec firewalld et NetworkManager.

**Prérequis** : M18-E03 (même logique de rôle).
**Durée indicative** : 3 h.

**Contexte technique**
- VMs `rke2-01..03` (2182-2184) : **Rocky Linux 10** (image dorée `rocky10` `current`, CPU `x86-64-v3`), 2 vCPU, 4 Go, 32 Gio, `vsandbox` DHCP, MAC `bc:24:11:99:18:82` à `:84`, étiquettes `env-m18`, `role-rke2`. Debian n'apparaît pas dans la matrice de support de RKE2 1.36 ; RHEL et ses dérivés, si.
- RKE2 **v1.36.5+rke2r1**, installé en **RPM** depuis `rpm.rancher.io` (dépôts `rke2/latest/common/centos/10/noarch` et `rke2/latest/1.36/centos/10/x86_64`, clé `https://rpm.rancher.io/public.key`) : paquet `rke2-server`, qui tire `rke2-common` et `rke2-selinux`. Pas de script d'installation ici : le rôle déclare le dépôt et le paquet épinglé.
- Trois serveurs, tous nœuds de contrôle et membres etcd. Adresse d'enregistrement : `https://rke2-01.par1.medisphere.internal:9345` (premier serveur ; pas de répartiteur dans l'essai, c'est une limite à noter). Le certificat de l'API porte les trois noms des nœuds.
- Jeton partagé : Ansible Vault `lab`, `vault_rke2_jeton`, dans `group_vars/role_rke2/vault-lab.yml`.
- RKE2 1.36 déploie par défaut Canal (CNI) et Traefik (Ingress) ; garde les défauts.
- Image dorée Rocky : `firewalld` actif, NetworkManager. Lis la page « Known Issues » de RKE2 avant d'installer.

**Travail demandé**
1. Ajoute `"rke2"` à `groupes` ; MR, `tofu apply` (mesure le temps).
2. Lis le guide de durcissement CIS de RKE2 (section « Host-level requirements ») et la page SELinux. Liste dans `rke2/README.md` de `plateforme/distributions` ce que l'**hôte** doit fournir, ce que **RKE2** fait avec `profile: cis`, et ce qui reste à ta charge.
3. Écris le rôle **`rke2`** : dépôts RPM (clé vérifiée par son empreinte), paquet épinglé, préparation de l'hôte exigée par le profil, réglage de firewalld et de NetworkManager conforme aux problèmes connus, `/etc/rancher/rke2/config.yaml` rendu depuis une variable `rke2_config`, `registries.yaml` vers le cache Harbor, démarrage **d'abord** du premier serveur, **puis** des deux autres un par un (`serial: 1`). Le jeton n'est jamais en argument.
4. Variables (`group_vars/role_rke2/rke2.yml`) : `profile: cis`, `token-file`, `tls-san`, `write-kubeconfig-mode`, et `server` pour les nœuds qui rejoignent. Joue le playbook.
5. Observe :
   ```
   [admin@rke2-01 ~]$ sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes
   [admin@rke2-01 ~]$ ps -o user=,comm= -C etcd
   [admin@rke2-01 ~]$ sudo ls -l /var/lib/rancher/rke2/server/db/ /etc/rancher/rke2/
   [admin@rke2-01 ~]$ sudo grep -A3 'defaults' /etc/rancher/rke2/rke2-pss.yaml
   [admin@rke2-01 ~]$ ps -eZ | grep 'rke2 server'
   ```
6. Récupère le kubeconfig (`~/.config/workbook/m18/rke2.kubeconfig`, 600, serveur `https://rke2-01.par1.medisphere.internal:6443`, contexte `rke2`). Puis, depuis `adm01` :
   - liste les NetworkPolicies créées par le profil, et les espaces exemptés de Pod Security ;
   - essaie de créer dans un espace `essai-cis` un pod `docker.io/library/busybox:1.37` sans `securityContext` (`kubectl apply --dry-run=server` d'abord) : lis le refus ;
   - écris un manifeste de pod qui **passe** le niveau `restricted` (fichier `rke2/essai-cis/pod-conforme.yaml`), applique-le, vérifie qu'il tourne.
7. Mesures (temps d'installation des trois nœuds, mémoire au repos) ; fiche `docs/kubernetes/distributions/rke2.md` : prérequis de l'hôte, effets du profil, SELinux, ce que tu montreras à l'auditeur. Une fois `lab/bin/check 18 04` vert, **retire** `"rke2"` de `groupes` (`tofu apply` détruit les trois VMs) : le palier 3 les reconstruit par le code (`groupes` et playbook), ce qui prouve au passage que l'essai est reproductible. Un simple `qm shutdown` ne suffit pas : le prochain `tofu apply` redémarre toute VM décrite (`vm-noeud` déclare `started = true`).

**Critères de réussite**
- [ ] `rke2-01..03` (2182-2184) existent, en Rocky Linux 10, avec les ressources, MAC et étiquettes du plan.
- [ ] Sur chaque nœud : `rke2-server` en 1.36.5~rke2r1, `rke2-selinux` installé, SELinux `Enforcing`, firewalld inactif, utilisateur et groupe `etcd` présents, paramètres noyau CIS chargés depuis `/etc/sysctl.d/60-rke2-cis.conf`, `profile: cis` dans `/etc/rancher/rke2/config.yaml`.
- [ ] etcd tourne sous l'utilisateur `etcd` ; le cluster a trois nœuds `Ready` de rôle `control-plane,etcd` en v1.36.5+rke2r1.
- [ ] La configuration Pod Security du kube-apiserver applique `restricted` par défaut ; le pod `essai-cis/conforme` tourne.
- [ ] `~/.config/workbook/m18/rke2.kubeconfig` en 600 vise `https://rke2-01.par1.medisphere.internal:6443`.
- [ ] Le rôle `rke2`, `rke2/README.md` et la fiche `rke2.md` sont sur `main`.

**Vérification** : `lab/bin/check 18 04`

<details><summary>Indice 1</summary>

Le profil ne crée ni l'utilisateur `etcd` ni le fichier de paramètres noyau dans `/etc/sysctl.d/` : il **vérifie**. Le paquet RPM livre un fichier de paramètres prêt à copier (le guide donne son chemin selon la méthode d'installation).
</details>

<details><summary>Indice 2</summary>

Si le premier serveur démarre et que les deux autres restent bloqués, regarde `journalctl -u rke2-server` sur un nœud qui rejoint : il parle au superviseur sur 9345 avant tout. Un pare-feu local qui le bloque se voit tout de suite.
</details>

<details><summary>Indice 3</summary>

Pour un pod `restricted` : pas de privilège ni d'escalade, toutes les capacités retirées, utilisateur non root, profil seccomp `RuntimeDefault`. `kubectl explain pod.spec.securityContext` et `…containers.securityContext` donnent les champs.
</details>

---

### M18-E05 — Talos Linux : un OS immuable piloté par API  `LAB` `★★★`

> **Ticket PLAT-1905** — *De : Karim Benali*
> Sophie a mis Talos dans la liste. Ça a l'air séduisant sur le papier, mais je veux voir comment on vit avec : pas de SSH, tout par API, une configuration YAML par nœud. Monte un petit cluster, un nœud de contrôle et deux travailleurs, sur notre Proxmox. Je veux que ce soit reproductible : l'image, la configuration générée, les correctifs par nœud, tout doit pouvoir se refaire à partir du dépôt, sans les secrets bien sûr.

**Objectifs pédagogiques**
- Obtenir une image Talos adaptée (Image Factory, schéma avec l'extension `qemu-guest-agent`, plateforme *nocloud*) et créer les VMs par OpenTofu.
- Générer la configuration d'un cluster (`talosctl gen secrets`, `gen config`), la personnaliser par *patches*, l'appliquer en mode maintenance, amorcer etcd.
- Exploiter un nœud sans shell : `dashboard`, `health`, `get`, `logs`, `services`, `dmesg`.
- Comprendre la configuration multi-documents de Talos 1.14.

**Prérequis** : M18-E02 (talosctl sur `adm01`) ; M05 (OpenTofu).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Image : Talos **v1.14.1** (E06 montera en 1.14.2), Kubernetes **v1.36.4** fixé explicitement (Talos 1.14 installe 1.37 par défaut). Schéma de l'Image Factory : la seule extension officielle `siderolabs/qemu-guest-agent`. Image disque **nocloud** pour amd64 ; sur Proxmox, OpenTofu la télécharge directement sur `hdd-bulk` (ressource `proxmox_download_file`, contenu `iso`, image compressée décompressée par Proxmox) et l'importe comme disque des VMs. L'empreinte du schéma est une donnée versionnée dans `plateforme/infra` (pas une valeur recopiée de l'interface web).
- VMs `talos-01..03` (2185-2187) : 2 vCPU, 3 Go **sans ballon mémoire** (Talos ne le gère pas), disque 20 Gio sur `local-nvme`, contrôleur **VirtIO SCSI** (pas « VirtIO SCSI single », qui bloque l'amorçage d'après la documentation Proxmox de Talos), BIOS UEFI (`ovmf`) avec disque EFI, machine `q35`, agent QEMU activé, console série. Réseau `vsandbox` avec **adresses fixes** 10.10.99.85, .86, .87/24, passerelle 10.10.99.1, résolveurs 10.10.20.10 et 10.10.20.16, données remises par le lecteur cloud-init de Proxmox (Talos lit le format *nocloud* ; il ignore un `user-data` de type `#cloud-config`). Noms `talos-01..03.par1.medisphere.internal` publiés par OpenTofu (module `enregistrement-dns`).
- Cluster `talos-essai`, point d'accès `https://talos-01.par1.medisphere.internal:6443` ; `talos-01` nœud de contrôle, `talos-02` et `talos-03` travailleurs.
- Secrets : le bundle `talosctl gen secrets` dans `~/.config/workbook/m18/talos-secrets.yaml` (600) **et** une copie chiffrée (Ansible Vault `lab`) dans `talos/secrets/` de `plateforme/distributions`. Les fichiers générés (`controlplane.yaml`, `worker.yaml`) contiennent les clés : ils ne sont jamais versionnés, on les régénère.
- `talosconfig` : `~/.config/workbook/m18/talosconfig` (600) ; kubeconfig : `~/.config/workbook/m18/talos.kubeconfig` (600).

**Travail demandé**
1. **L'image.** Écris le schéma (YAML) dans `plateforme/infra` et obtiens son identifiant par l'API de l'Image Factory (pas par l'interface web). Compare avec l'identifiant du schéma « vide » donné par la documentation : pourquoi sont-ils différents, et pourquoi l'identifiant suffit-il à retrouver l'image ?
2. **Les VMs.** Ajoute à `envs/m18` un fichier `talos.tf` (ressources `proxmox_download_file` et `proxmox_virtual_environment_vm`, enregistrements DNS) piloté par le groupe `talos`, avec le matériel imposé ci-dessus. Retire `"rke2"` de `groupes` si tu ne l'as pas fait en E04 (mémoire). MR, `tofu apply` : les VMs démarrent ; sur la console série (`qm terminal 2185`), chaque nœud est en **mode maintenance** et affiche son adresse.
3. **La configuration.** Dans `talos/` de `plateforme/distributions`, écris un script `generer.sh` qui génère la configuration dans un dossier temporaire hors du dépôt (`~/.cache/m18/talos/`, 700) à partir du bundle de secrets, avec la version de Kubernetes, l'image d'installation (installeur *nocloud* de l'Image Factory pour **ton** schéma) et les *patches* du dépôt. Pour ce premier essai, un seul *patch* par nœud, qui fixe son nom (`talos/noeuds/talos-0N.yaml`). Lis le fichier généré : quels documents contient-il ? lequel envoie des informations à un service extérieur à MédiSphère ?
   ```
   admin@adm01:~$ talosctl gen secrets -o ~/.config/workbook/m18/talos-secrets.yaml
   admin@adm01:~$ talosctl validate --mode cloud --config ~/.cache/m18/talos/controlplane.yaml
   ```
4. **Le premier contact.** Applique la configuration à chaque nœud en mode maintenance (`talosctl apply-config --insecure …`), le nœud de contrôle d'abord. Pourquoi `--insecure` ici, et seulement ici ?
5. **L'amorçage.** Configure ton `talosconfig` (points d'accès et nœuds), amorce etcd sur `talos-01` (**une seule fois**), récupère le kubeconfig, attends la santé du cluster :
   ```
   admin@adm01:~$ export TALOSCONFIG=~/.config/workbook/m18/talosconfig
   admin@adm01:~$ talosctl --nodes 10.10.99.85 bootstrap
   admin@adm01:~$ talosctl --nodes 10.10.99.85 health
   ```
   > ⚠️ **Attention** : `talosctl bootstrap` ne se lance qu'une fois, sur un seul nœud de contrôle, pour un cluster neuf. Relancé sur un cluster qui a déjà un etcd, il est refusé ou, sur un autre nœud, crée un second etcd séparé.
6. **Vivre sans SSH.** Retrouve, uniquement avec `talosctl` : la liste des services et leur état ; les 50 dernières lignes du kubelet de `talos-02` ; les messages du noyau au démarrage ; les extensions installées (dont le schéma) ; la mémoire et les processus ; le nom d'hôte et d'où il vient. Ouvre `talosctl dashboard`. Vérifie que le port 22 des nœuds est fermé. Note les commandes dans la fiche.
7. Mesures et fiche `docs/kubernetes/distributions/talos.md` (image et schéma, génération, ce qui est versionné et ce qui ne l'est pas, commandes d'exploitation, ce qui manque par rapport à un nœud Debian).

**Critères de réussite**
- [ ] `talos-01..03` (2185-2187) existent avec le matériel imposé (VirtIO SCSI, sans ballon, UEFI, agent) et les adresses 10.10.99.85-87 ; leurs noms DNS résolvent.
- [ ] Les trois nœuds répondent à `talosctl version` en Talos v1.14.x avec l'extension `qemu-guest-agent` et le schéma versionné dans `plateforme/infra`.
- [ ] Le cluster `talos-essai` a trois nœuds `Ready` (un `control-plane`, deux travailleurs) en Kubernetes v1.36.x, aux noms `talos-01..03`.
- [ ] Aucun nœud n'écoute en SSH.
- [ ] `talosconfig`, `talos.kubeconfig` et `talos-secrets.yaml` sont en 600 sous `~/.config/workbook/m18/` ; aucun fichier du dépôt `plateforme/distributions` ne contient de clé privée ni de jeton de cluster.
- [ ] `talos/generer.sh`, `talos/noeuds/` et la fiche `talos.md` sont sur `main`.

**Vérification** : `lab/bin/check 18 05`

<details><summary>Indice 1</summary>

L'Image Factory accepte un schéma en `POST` et rend un identifiant ; l'URL d'une image combine identifiant, version et format (`…/image/<id>/<version>/nocloud-amd64.raw.zst`, par exemple). Pour un disque, le fournisseur `bpg/proxmox` sait télécharger une image compressée (`decompression_algorithm`) et l'importer dans le disque d'une VM (`file_id`).
</details>

<details><summary>Indice 2</summary>

`talosctl gen config` accepte `--with-secrets`, `--kubernetes-version`, `--install-image` et des `--config-patch` ; `talosctl apply-config` accepte aussi `--config-patch`, ce qui permet un *patch* par nœud sur une base commune. En 1.14, le nom d'hôte est un document à part (`HostnameConfig`) : un *patch* qui ne précise que `hostname` ne suffit pas toujours, lis la page « Hostname ».
</details>

<details><summary>Indice 3</summary>

`talosctl` a deux notions : les **points d'accès** (`endpoints`, à qui le client se connecte) et les **nœuds** (`nodes`, qui exécute la commande, éventuellement relayée par le point d'accès). `talosctl config endpoint` et `talosctl config node` règlent les deux dans le `talosconfig`.
</details>

**Pour aller plus loin** (facultatif) : la fourniture de la configuration par le numéro de série SMBIOS (`ds=nocloud-net;s=http://…/`) : plus de `--insecure`, la VM démarre avec sa configuration. Que faudrait-il servir, et comment protéger le serveur qui la distribue ?
