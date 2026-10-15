# Module 14 — Introduction : administrer Kubernetes

## Des conteneurs, mais où les faire tourner ?

Lundi, 9 h 05. Les images de MédiAgenda, MédiDoc et MédiNotif sont construites en CI sans privilège, signées, scannées, rangées dans Harbor. Julien Petit a posé la question qui fâche au point hebdomadaire : « Très bien, et on les lance où ? Sur `ctr02` à la main, comme au module 12 ? » Claire Morel a répondu par un message à toute l'équipe.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Kubernetes — on construit le nôtre, et on le comprend
>
> Bonjour,
>
> Le comité d'architecture a tranché : nos applications tourneront sur **Kubernetes**, dans PAR1, sur des VMs de `pve01`. Pas de distribution « clés en main » pour commencer : nous installons avec **kubeadm**, l'outil de référence du projet, pour que l'équipe Plateforme sache ce que fait chaque composant le jour où il tombe. On comparera les distributions plus tard (M18), en connaissance de cause.
>
> Ce que je veux à la fin du module :
> 1. un cluster **`k8s-par1`** de trois nœuds de contrôle et trois travailleurs, **décrit par le code** (OpenTofu pour les VMs, Ansible pour les nœuds, un projet `plateforme/k8s` pour ce qu'on applique au cluster) et reconstructible ;
> 2. un plan de contrôle **redondant** : on doit pouvoir perdre un nœud de contrôle sans perdre l'API ni etcd ;
> 3. des équipes qui ne se marchent pas dessus : espaces de noms, quotas, rôles, comptes de service, règles d'admission ;
> 4. l'exploitation : sauvegarde **et restauration** d'etcd, montée de version 1.35 → 1.36, certificats, audit, chiffrement des Secrets ;
> 5. des runbooks : nœud `NotReady`, pods `Pending`, `ImagePullBackOff`, `CrashLoopBackOff`, API injoignable, etcd en détresse, DNS du cluster.
>
> Sophie veut des **identités nominatives**, des droits minimaux, un audit, et aucun `system:masters` qui traîne. Julien veut déployer MédiAgenda en recette sans attendre trois jours un ticket. Nadia veut savoir quoi faire quand un nœud tombe à 3 h du matin. Karim rappelle la règle : « une VM, c'est OpenTofu ; une configuration, c'est un rôle Ansible testé ; ce qu'on applique au cluster, c'est une MR ».
>
> Premier jalon : six nœuds préparés, un point d'accès d'API redondant, un cluster amorcé, Cilium, et MédiAgenda qui répond dans un espace d'essai. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 14, MédiSphère a son cluster Kubernetes **v1** (étiquette `k8s-v1` du dépôt `plateforme/medisphere`), consommé par tous les modules suivants (réseau au M15, stockage au M16, packaging au M17, CI et GitOps aux M19-M20, observabilité, sécurité, plateforme de développement) et par les workbooks finaux :

- **`k8s-par1`** : Kubernetes installé par **kubeadm** en **1.35.x** puis monté en **1.36.x** (palier 3), etcd **empilé** sur trois nœuds de contrôle, trois travailleurs, runtime **containerd 2.3** ;
- un point d'accès d'API **hautement disponible** : VIP keepalived 10.10.40.200 (`k8s-api.par1.medisphere.internal`), HAProxy en 8443 sur chaque nœud de contrôle ;
- le réseau des pods par **Cilium 1.20** (kube-proxy conservé au M14, remplacé au M15) ;
- le projet GitLab **`plateforme/k8s`** : configuration kubeadm du cluster, composants, espaces de noms, RBAC, admission, outils ; appliqué depuis `adm01` par une procédure unique (`task appliquer`), en attendant le GitOps du M20 ;
- des identités personnelles à durée courte, un compte de service en lecture pour les vérifications, des rôles par équipe, Pod Security et des politiques d'admission ;
- la sauvegarde d'etcd vers `s3-01` et sa restauration réelle, la montée de version, la gestion des certificats, l'audit, le chiffrement des Secrets ; ADR-0140 et ADR-0141, runbooks RB-140 à RB-143.

Le **palier 1** (ce fichier et `01-decouverte.md`) crée et prépare les nœuds par le code, monte le point d'accès de l'API, amorce le cluster à la main pour comprendre chaque étape, joint les autres nœuds et installe Cilium, puis le fait rejouer par Ansible. Il installe les outils de `adm01`, crée ton identité personnelle et celle des vérifications, et déploie MédiAgenda dans un espace d'essai. Le palier s'ouvre et se ferme sur un questionnaire.

## Architecture du module

```
                 adm01 (1001) 10.10.10.10 — VLAN 10 MGMT : joint tout le lab
                 kubectl 1.36 · helm 4 · k9s · cilium · hubble · etcdctl · ~/src/{infra,ansible,k8s}
                                         │  https://k8s-api.par1.medisphere.internal:8443
   ═══════════════════════ gw01 / gw02 (VIP .1, VRRP) — routage, filtrage, NTP ═════════════════════
                                         │
  VLAN 40 K8S 10.10.40.0/24 · MTU 1500 · passerelle 10.10.40.1          VIP API 10.10.40.200:8443
  ──────┬────────────────────┬────────────────────┬──────────────────────────┬─────────┬─────────┬──
        │ .51                │ .52                │ .53                      │ .61     │ .62     │ .63
  ┌─────┴────────────┐ ┌─────┴────────────┐ ┌─────┴────────────┐       ┌────┴───┐ ┌───┴────┐ ┌──┴─────┐
  │ k8s-cp01 (2141)  │ │ k8s-cp02 (2142)  │ │ k8s-cp03 (2143)  │       │k8s-w01 │ │k8s-w02 │ │k8s-w03 │
  │ keepalived 140   │ │ keepalived 140   │ │ keepalived 140   │       │ (2144) │ │ (2145) │ │ (2146) │
  │ HAProxy :8443 ─┐ │ │ HAProxy :8443    │ │ HAProxy :8443    │       │        │ │        │ │        │
  │ apiserver:6443◄┼─┼─┼─► apiserver:6443 │ │ apiserver :6443  │       │ kubelet│ │ kubelet│ │ kubelet│
  │ etcd ◄─────────┼─┼─┼─► etcd ◄─────────┼─┼─► etcd           │       │ pods   │ │ pods   │ │ pods   │
  │ ctrl-mgr, sched│ │ │ ctrl-mgr, sched  │ │ ctrl-mgr, sched  │       │        │ │        │ │        │
  │ kubelet        │ │ │ kubelet          │ │ kubelet          │       │        │ │        │ │        │
  │ containerd 2.3 │ │ │ containerd 2.3   │ │ containerd 2.3   │       │ cd 2.3 │ │ cd 2.3 │ │ cd 2.3 │
  │ cilium, k-proxy│ │ │ cilium, k-proxy  │ │ cilium, k-proxy  │       │ cilium │ │ cilium │ │ cilium │
  └────────────────┴─┘ └──────────────────┘ └──────────────────┘       └────────┘ └────────┘ └────────┘
   2 vCPU · 4 Go · 40 Gio                                               4 vCPU · 8 Go · 60 Gio
   pods 10.240.0.0/16 (un /24 par nœud, Cilium, tunnel VXLAN) · services 10.96.0.0/16 · cluster.local

  k8s-w04 (2147, .64) : ajout et retrait d'un nœud (M14-E17), détruit en fin de module.
  reg01 (registry.par1.medisphere.internal) : images de MédiAgenda (projet medisphere, robot$k8s-pull).
```

Points structurants :

- **etcd empilé.** Chaque nœud de contrôle porte un membre etcd, à côté du kube-apiserver qui le lit en local. Trois membres : on en perd un sans perdre le quorum (2 sur 3), pas deux. Topologie la plus simple, documentée par kubeadm ; l'alternative (etcd externe sur trois VMs de plus) est discutée dans l'ADR-0140 (palier 3).
- **Une VIP devant les trois API.** Tous les clients (les kubelets, les contrôleurs, toi) parlent à `k8s-api.par1.medisphere.internal:8443`. keepalived fait flotter l'adresse 10.10.40.200 entre les trois nœuds de contrôle ; HAProxy, présent sur chacun, répartit en TCP vers les trois kube-apiserver. Le port de la VIP n'est pas 6443 parce que kube-apiserver écoute déjà 6443 sur le même hôte. C'est la méthode « keepalived et HAProxy » de la documentation kubeadm, avec les rôles du module 07.
- **Les composants du plan de contrôle sont des pods statiques.** Le kubelet de chaque nœud de contrôle lit `/etc/kubernetes/manifests/` et lance etcd, kube-apiserver, kube-controller-manager, kube-scheduler, sans passer par l'API. C'est ce qui permet au cluster de démarrer « de lui-même ».
- **Le runtime n'est pas celui de Debian.** Debian 13 livre containerd 1.7, incompatible avec Kubernetes 1.36 : on installe `containerd.io` 2.3 (LTS) du dépôt Docker, et on lui donne une configuration adaptée au kubelet (cgroups systemd, image pause de kubeadm).
- **kubeadm d'abord à la main, puis par le code.** Tu amorces le cluster et tu joins deux nœuds à la main, une fois, pour comprendre ; ensuite le rôle Ansible joint les autres et rejoue tout sans rien changer.

### Hôtes du module

| Hôte | VMID | Adresse (VLAN 40) | MAC | Ressources | Étiquettes | Rôles Ansible | Exercice |
|---|---|---|---|---|---|---|---|
| `k8s-cp01` | 2141 | 10.10.40.51 | `bc:24:11:40:00:51` | 2 vCPU, 4 Go, 40 Gio `local-nvme` | `env-k8s`, `role-k8s-cp` | `containerd`, `k8s_noeud`, `k8s_plan_controle` | E02-E05 |
| `k8s-cp02` | 2142 | 10.10.40.52 | `bc:24:11:40:00:52` | idem | idem | idem | E02-E05 |
| `k8s-cp03` | 2143 | 10.10.40.53 | `bc:24:11:40:00:53` | idem | idem | idem | E02-E05 |
| `k8s-w01` | 2144 | 10.10.40.61 | `bc:24:11:40:00:61` | 4 vCPU, 8 Go, 60 Gio `local-nvme` | `env-k8s`, `role-k8s-worker` | `containerd`, `k8s_noeud`, `k8s_travailleur` | E02-E05 |
| `k8s-w02` | 2145 | 10.10.40.62 | `bc:24:11:40:00:62` | idem | idem | idem | E02-E05 |
| `k8s-w03` | 2146 | 10.10.40.63 | `bc:24:11:40:00:63` | idem | idem | idem | E02-E05 |
| `k8s-w04` | 2147 | 10.10.40.64 | `bc:24:11:40:00:64` | idem | idem | idem | E17 (détruit en fin de module) |

VMID du module : 2140-2149 (pool `lab`). 2140, 2148 libres pour tes essais ; 2149 réservé à l'instance Molecule du scénario `k8s_noeud` (E02). Image dorée : Debian 13 `current` (M03). Pas de démarrage automatique : le cluster s'arrête et redémarre à la main (règle 3 ci-dessous).

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur `gw01`/`gw02` |
|---|---|---|---|
| `adm01` → nœuds (SSH) et VIP de l'API | 22, 8443 | E02-E08 | existant : MGMT joint tout le lab |
| nœuds de contrôle entre eux : VRRP v3 unicast (VRID 140), etcd, kube-apiserver | IP 112, 2379-2380, 6443 | E03-E05 | même VLAN : ne traverse pas la passerelle |
| tous les nœuds → kube-apiserver (par la VIP), kubelet ← plan de contrôle | 8443, 6443, 10250 | E04-E05 | même VLAN |
| tous les nœuds entre eux : Cilium (VXLAN, santé, Hubble) | UDP 8472, TCP 4240, 4244 | E05 | même VLAN |
| nœuds → Internet (`pkgs.k8s.io`, `download.docker.com`, `registry.k8s.io`, `quay.io`, `docker.io`) | 443 | E02-E07 | existant (« lab vers Internet ») |
| nœuds → `reg01` (Harbor) | 443 | E07 | existant (M13-E02) |
| nœuds → `dns01`/`dns02`, passerelle (NTP) | 53, 123 | E02 | existant |

Aucune règle nouvelle sur les passerelles au palier 1 : tu documentes quand même ces flux dans la matrice (E02, E03). Les images publiques viennent directement d'Internet jusqu'en M14-E19, qui les fait passer par les caches de Harbor.

---

## Le chemin imposé

1. **OpenTofu** : les VMs sont déclarées dans l'état **`envs/k8s`** de `plateforme/infra` (un état à part : détruire le cluster ne touche jamais le socle), avec le module **`vm-noeud`** de `plateforme/tofu-modules` (M08-E02, v2.3 depuis M10-E02 pour les MAC imposées) ; noms DNS par `enregistrement-dns`, adresses dans NetBox.
2. **Ansible** : les nœuds entrent dans l'inventaire par leurs étiquettes NetBox ; groupes **`k8s_par1`**, **`k8s_plan_controle`**, **`k8s_travailleurs`** ; les rôles communs (`base`, `ssh_durci`, `ca_lab`, `ssh_ca_hote`, `ssh_ca_utilisateur`) puis **`containerd`**, **`k8s_noeud`**, **`k8s_plan_controle`** (qui réutilise `keepalived` et `haproxy` du M07), **`k8s_travailleur`** ; les faits partagés du cluster dans `group_vars/k8s_par1/kubernetes.yml`.
3. **`plateforme/k8s`** (créé en E04) : ce qu'on applique **au cluster** — `cluster/kubeadm-config.yaml`, `composants/`, `espaces/`, `rbac/`, `admission/`, `outils/`, `Taskfile.yml`. Relu en MR, appliqué depuis `adm01` à partir de `main` (`task diff`, `task appliquer`). Le contexte kubectl est toujours explicite.
4. **Secrets** : `admin.conf` et `super-admin.conf` chiffrés en Vault `critique` dans `plateforme/k8s` (`secrets/`) ; identités personnelles à 7 jours ; fichiers 600 de `~/.config/workbook/` ; rien en clair dans un dépôt, rien en argument de commande.
5. **Documentation** : dans `plateforme/medisphere`, dossier **`docs/kubernetes/`** (fiche du cluster, accès, runbooks RB-140 et suivants, ADR-0140 et ADR-0141) ; la matrice des flux et le registre des secrets restent dans `docs/socle/`.

Une manipulation à la main n'est permise que pour **explorer** (une commande `kubectl get`, un essai dans l'espace `wb-essais`), ou quand l'énoncé la demande comme geste à connaître (amorcer le cluster, joindre un nœud, une fois chacun).

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**L'API d'abord.** Tout Kubernetes tourne autour d'une API REST (le **kube-apiserver**) qui stocke des **objets** (Pod, Deployment, Service, Node…) : chacun a une *spec* (l'état voulu) et un *status* (l'état observé). Personne ne « lance » rien directement : on écrit un objet, et des boucles de contrôle font converger le réel vers lui.

**etcd.** La base clé-valeur distribuée (consensus Raft) où l'API range tous les objets. Seul le kube-apiserver lui parle. Perdre etcd, c'est perdre le cluster : sa sauvegarde est la sauvegarde du cluster (M14-E24).

**Contrôleurs et ordonnanceur.** Le **kube-controller-manager** fait tourner des dizaines de boucles (un Deployment crée un ReplicaSet, qui crée des Pods ; un nœud qui ne répond plus est marqué…). Le **kube-scheduler** choisit un nœud pour chaque pod qui n'en a pas, d'après ses demandes de ressources et ses contraintes. Avec trois nœuds de contrôle, un seul contrôleur et un seul ordonnanceur sont actifs à la fois (élection par un objet Lease).

**kubelet et runtime.** Sur chaque nœud, le **kubelet** lit les pods qui lui sont attribués et les fait exister par le **CRI** (Container Runtime Interface) de **containerd**, qui crée les conteneurs avec runc. Chaque pod a un conteneur « pause » qui tient ses espaces de noms Linux (réseau, IPC).

**Réseau.** Trois réseaux : celui des **nœuds** (VLAN 40), celui des **pods** (10.240.0.0/16 : chaque pod a une adresse joignable de tout le cluster, fournie par le **CNI**, ici Cilium) et celui des **Services** (10.96.0.0/16 : adresses virtuelles stables devant un groupe de pods, traduites par **kube-proxy** ou Cilium). **CoreDNS** résout `mediagenda-api.wb-essais.svc.cluster.local`.

**Objets de base.** Un **Pod** (un ou plusieurs conteneurs qui partagent réseau et volumes) est jetable ; un **Deployment** maintient N pods identiques et les remplace progressivement ; un **Service** leur donne une adresse et un nom stables, en sélectionnant les pods par leurs **étiquettes** ; un **ConfigMap** et un **Secret** portent la configuration ; un **Namespace** cloisonne les noms, les droits et les quotas.

**Sondes et ressources.** La sonde de **vivacité** (*liveness*) dit si le conteneur doit être redémarré ; celle de **disponibilité** (*readiness*) s'il doit recevoir du trafic ; celle de **démarrage** (*startup*) protège un démarrage lent. Les **demandes** (*requests*) servent à l'ordonnancement, les **limites** (*limits*) au plafonnement par les cgroups ; leur combinaison donne la **classe QoS** du pod (Guaranteed, Burstable, BestEffort), qui décide qui part en premier quand un nœud manque de mémoire.

**Authentification et autorisation.** Une requête à l'API est **authentifiée** (certificat client, jeton de compte de service, OIDC au M24), **autorisée** (RBAC : rôles et liaisons), puis passe l'**admission** (contrôles et mutations, M14-E18). Kubernetes ne connaît pas d'« utilisateurs » : il lit un nom et des groupes dans le certificat ou le jeton.

**kubeadm.** Il ne crée pas de VM et n'installe aucun paquet : il génère la PKI du cluster, écrit les manifestes statiques et les kubeconfigs, attend que le plan de contrôle réponde, pose le RBAC de base, CoreDNS et kube-proxy, puis permet aux autres nœuds de rejoindre avec un **jeton d'amorçage**. Le reste (runtime, paquets, CNI, point d'accès) est à ta charge : c'est l'objet des rôles Ansible.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | Kubernetes **1.35.9** (paquets `1.35.9-1.1` de `pkgs.k8s.io/core:/stable:/v1.35/deb/`), puis **1.36.x** en M14-E25 ; etcd **3.6.6** et CoreDNS **1.13.1** de kubeadm 1.35.9 (`kubeadm config images list`) ; image pause `registry.k8s.io/pause:3.10.1` ; containerd.io **2.3.x** (dépôt Docker, runc 1.5 inclus) ; Cilium **1.20.2** par la CLI cilium **0.20.1** ; Hubble CLI 1.20.2 ; kubectl **1.36** sur `adm01` ; Helm **4.3** ; k9s 0.51 ; krew 0.5 ; etcdctl/etcdutl **3.6.6** |
| Changements de version | voir [`annexes/versions-bloc-C.md`](../../../annexes/versions-bloc-C.md), section « Kubernetes » : cgroup v1 refusé depuis 1.35, kubeadm v1beta4 (`extraArgs` en liste `name`/`value`, v1beta3 supprimée en 1.37), `super-admin.conf` depuis 1.29, ipvs déprécié, `kubeadm config validate`, containerd 2.x et `config.toml` (schéma version 4 en 2.3) |
| Cluster | `k8s-par1` ; `controlPlaneEndpoint: k8s-api.par1.medisphere.internal:8443` ; pods 10.240.0.0/16, services 10.96.0.0/16, domaine `cluster.local` ; kube-proxy en mode `iptables` explicite ; certificats feuilles 1 an, CA 10 ans |
| Point d'accès | VIP 10.10.40.200 (enregistrement A `k8s-api` dans `par1`, adresse de rôle « vip » dans NetBox), keepalived VRRP v3 unicast **VRID 140** (priorités 150/120/100, sans préemption), HAProxy 3.2 en TCP sur 10.10.40.200:8443 vers les kube-apiserver :6443 |
| Projets | `plateforme/infra` : `envs/k8s/` (état `envs/k8s/terraform.tfstate`) ; `plateforme/ansible` : rôles `containerd`, `k8s_noeud`, `k8s_plan_controle`, `k8s_travailleur`, `outils_k8s`, playbooks `k8s-noeuds.yml`, `k8s-cluster.yml`, `outils-k8s.yml`, source d'inventaire `inventories/lab/netbox-k8s.yml`, faits partagés `group_vars/k8s_par1/` ; **`plateforme/k8s`** (créé en E04) ; `mediagenda/api` : manifestes d'essai `k8s/essais/` (E07-E08) ; `plateforme/medisphere` : `docs/kubernetes/` |
| Groupes d'inventaire | `k8s_par1` (tous les nœuds, étiquette `env-k8s`), `k8s_plan_controle` (`role-k8s-cp`), `k8s_travailleurs` (`role-k8s-worker`) |
| Espaces de noms du workbook | `wb-system` (compte de service des vérifications), `wb-essais` (essais des exercices) ; `mediagenda-dev`, `mediagenda-recette` en M14-E10 |
| Identités | `<MOI>` (certificat client 7 jours, groupe `medisphere:plateforme-admins`, contexte `k8s-par1` de `~/.kube/config`) ; `wb-system/wb-checks` (lecture sans Secrets, `~/.config/workbook/k8s-checks.kubeconfig`) ; `admin.conf`, `super-admin.conf` chiffrés dans `plateforme/k8s` `secrets/` |
| Secrets du palier 1 | Vault `critique` : `secrets/admin.conf.vault`, `secrets/super-admin.conf.vault` (`plateforme/k8s`) ; sur `adm01` (600) : `~/.config/workbook/k8s-checks.kubeconfig`, `~/.config/workbook/harbor-k8s-pull.env` (robot `robot$k8s-pull` du M13 : `HARBOR_USER=…`, `HARBOR_PASSWORD=…`) ; dans le cluster : Secrets `harbor-pull`, `postgresql`/`mediagenda-db` de `wb-essais` (jamais versionnés) |
| Documentation | `docs/kubernetes/` dans `plateforme/medisphere` : `cluster.md` (E05), `acces.md` (E06), puis runbooks RB-140 à RB-143 et ADR-0140/0141 ; journal de diagnostic et post-mortems dans `docs/socle/journal/` et `docs/socle/post-mortems/` |
| Brouillons | `~/m14/eXX/` sur `adm01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05), aussi ton identité dans le cluster (CN de ton certificat) |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` |
| `<VERSION-TOFU-MODULES>` | Étiquette de `plateforme/tofu-modules` qui contient `vm-noeud` v2.3 (M10-E02 ; `v2.3.0` si la numérotation a suivi) |
| `<VERSION-MEDIAGENDA>` | Dernière étiquette immuable de l'image `medisphere/mediagenda-api` publiée par le pipeline de M13-E09 (ex. `v1.0.0`) |

### Variables de `lab/lab.env`

Elles existent déjà dans `lab/lab.env.example` (section « Module 14 »), avec des valeurs par défaut qui conviennent au lab :

```
WB_K8S_KUBECONFIG="$HOME/.config/workbook/k8s-checks.kubeconfig"  # compte de service wb-checks (lecture)
WB_K8S_ADMIN_KUBECONFIG="$HOME/.kube/config"                       # utilisé par les scripts de panne
WB_K8S_CP="k8s-cp01 k8s-cp02 k8s-cp03"                             # nœuds de contrôle (SSH : admin)
WB_K8S_WORKERS="k8s-w01 k8s-w02 k8s-w03"
```

Vérifie aussi que `WB_MOI` (ton compte, bloc A) est renseigné : le check de E06 contrôle ton certificat. Avant E06, le kubeconfig des vérifications n'existe pas : les checks de E04 et E05 lisent alors le cluster par SSH sur `k8s-cp01` (avec `sudo`, en lecture) et le signalent.

---

## Règles du module

1. **Un geste destructif se relit deux fois.** `kubeadm reset`, `kubectl delete node`, `kubectl delete namespace`, `etcdctl member remove`, `kubeadm init` sur un nœud qui porte déjà un cluster, `rm` dans `/etc/kubernetes/` ou `/var/lib/etcd/` : vérifie le **contexte** (`kubectl config current-context`), le **nœud** (`hostname`), l'état d'etcd, et demande-toi ce qui se passe si tu t'es trompé de cible.
   > ⚠️ **Attention** : `kubeadm reset` sur un nœud de contrôle retire son membre etcd du cluster et efface ses certificats ; sur deux nœuds de contrôle, il détruit le quorum et donc le cluster. Il n'y a pas de corbeille.
2. **Jamais deux nœuds de contrôle à la fois.** Redémarrage, mise à jour de paquets, changement de configuration : un seul nœud de contrôle, et le suivant seulement quand `kubectl get nodes` est revenu à l'état de départ et qu'etcd a ses trois membres. Les playbooks sont en `serial: 1`.
3. **Arrêter et redémarrer le cluster proprement.** Le cluster est conservé pour la suite du workbook : tu l'arrêteras souvent pour libérer 36 Go de mémoire.
   - **arrêt** (sur `pve01`) : les travailleurs d'abord (`qm shutdown 2146`, `2145`, `2144`), puis les nœuds de contrôle (`2143`, `2142`, `2141`) ;
   - **démarrage** : les nœuds de contrôle d'abord (`qm start 2141`, `2142`, `2143` : il en faut deux pour qu'etcd ait son quorum et que l'API réponde), puis les travailleurs ; contrôle : `kubectl get nodes`, `cilium status`.
   Un cluster arrêté plus d'un an a des certificats expirés : la première commande au redémarrage sera alors `kubeadm certs check-expiration` (M14-E26).
4. **Le contexte est toujours explicite.** Dans les scripts et le `Taskfile.yml`, `--context k8s-par1` ; dans le terminal, vérifie le contexte avant toute écriture. Le M18 ajoutera d'autres clusters : prends l'habitude maintenant.
5. **Pas de vérification TLS désactivée** (`--insecure-skip-tls-verify`, `curl -k`, `verify none`) ni de secret en argument de commande (jetons, mots de passe) : fichier en 600, entrée standard, ou Vault. `admin.conf` ne quitte un nœud de contrôle que chiffré.
6. **`wb-essais` est jetable, les autres espaces non.** Tu peux vider `wb-essais` quand tu veux ; `kube-system`, `wb-system` et les espaces des équipes se modifient par `plateforme/k8s`. Les données de PostgreSQL et de Valkey de ce palier sont **volontairement jetables** (`emptyDir`) : le stockage persistant arrive au M16.
7. **Mémoire.** Socle v3 (≈ 37 Go) + 3 × 4 Go + 3 × 8 Go ≈ **73 Go**, jusqu'à 81 Go avec `k8s-w04` (E17). Avant de commencer, arrête `ceph-par1` (procédure du M08) et tout environnement lourd des modules précédents ; `ceph-par1` ne revient qu'au M16.

---

## Préparer `adm01`

Les outils Kubernetes de `adm01` (kubectl, Helm, k9s, cilium, hubble, etcdctl) sont installés par un rôle Ansible en M14-E05, au moment où tu en as besoin ; krew et ses greffons en E06. Vérifie d'abord l'état d'entrée :

```
admin@adm01:~$ lab/bin/check 13 25
admin@adm01:~$ lab/bin/check 07 46
admin@adm01:~$ cd ~/src/infra && tofu version
admin@adm01:~$ cd ~/src/ansible && uv run ansible-inventory --graph socle
admin@adm01:~$ ssh -o BatchMode=yes root@pve01 'qm list | grep -E " 90(1|2)[0-9] " | grep deb13'
admin@adm01:~$ ssh root@pve01 'free -g | head -2'
```

Le premier contrôle (mini-projet du module 13) doit être vert : Harbor sert l'image signée de MédiAgenda et le robot `robot$k8s-pull` existe. Le deuxième (mini-projet du module 07) garantit la bordure et les rôles `keepalived`/`haproxy`. L'avant-dernier montre tes images dorées Debian (9010-9029) : il en faut une étiquetée `current`. Le dernier : il te faut environ 75 Go libres.

Range les identifiants du robot de tirage dans un fichier 600 (ils viennent de Harbor ou de ton Vault, M13-E03) :

```
admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/harbor-k8s-pull.env
admin@adm01:~$ editor ~/.config/workbook/harbor-k8s-pull.env      # HARBOR_USER=robot$k8s-pull  HARBOR_PASSWORD=…
```

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 14 <XX>`. Elles sont en lecture seule : configuration Proxmox lue sur `pve01`, état des nœuds en SSH, `kubectl get` avec le compte de service `wb-checks` (à partir de E06), questions DNS, NetBox et GitLab en lecture.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M14-EXX/` : `ansible/` reproduit l'arborescence de `plateforme/ansible`, `infra/` celle de `plateforme/infra`, **`k8s/` celle de `plateforme/k8s`**, `mediagenda-api/` celle de `mediagenda/api`, `medisphere/` celle de la documentation. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05 ─ E06 ─ E07 ─ E08 ─ E09
```

1. **E01** — positionnement, à froid.
2. **E02 → E06** — dans l'ordre strict : chaque exercice construit sur le précédent (nœuds, point d'accès, amorçage, jonctions et réseau, accès). Les checks de E07 et suivants ont besoin du compte `wb-checks` créé en E06.
3. **E07 → E08** — MédiAgenda dans `wb-essais`, puis sa configuration, ses sondes et ses ressources.
4. **E09** — en dernier : il demande d'avoir pratiqué.

Durée indicative du palier 1 : 16 à 20 heures.

## Pour aller plus loin

- Composants de Kubernetes : <https://kubernetes.io/docs/concepts/overview/components/>
- Installer kubeadm, prérequis : <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/> · runtimes de conteneurs : <https://kubernetes.io/docs/setup/production-environment/container-runtimes/>
- Haute disponibilité avec kubeadm : <https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/> · options d'équilibrage (keepalived, HAProxy) : <https://github.com/kubernetes/kubeadm/blob/main/docs/ha-considerations.md>
- API de configuration kubeadm v1beta4 : <https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/>
- PKI et certificats : <https://kubernetes.io/docs/setup/best-practices/certificates/>
- Cilium, installation : <https://docs.cilium.io/en/v1.20/gettingstarted/k8s-install-default/>
- *Kubernetes the Hard Way* (Kelsey Hightower) : tout ce que kubeadm fait à ta place, à la main.
