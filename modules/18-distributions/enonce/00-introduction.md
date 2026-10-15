# Module 18 — Introduction : distributions et cycle de vie des clusters

## Une étude, pas une conversion

Mardi, 14 h. Le comité d'architecture vient de finir. `k8s-par1` tient depuis le module 14 : kubeadm, trois nœuds de contrôle, une VIP, des montées de version faites à la main en suivant RB-142. Personne ne veut le changer. Mais trois demandes sont arrivées en même temps sur le bureau de Claire Morel.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Julien Petit, Nadia Roussel
> **Objet** : Distributions Kubernetes — étude comparative et essais réels
>
> Bonjour,
>
> Trois besoins, une même question : « kubeadm partout, ou autre chose ? »
>
> 1. **L'agence de Lyon** ouvre au printemps. Elle aura un petit serveur, pas d'équipe sur place, et quelques services locaux (impression, cache de l'agenda, sonde réseau). Il faut un cluster léger, qui se mette à jour sans que quelqu'un se déplace.
> 2. **Les équipes de développement** veulent des clusters de recette jetables, créés en quelques minutes, détruits le soir. Julien ne veut plus attendre un ticket pour chaque essai.
> 3. **Sophie** voudrait réduire la surface d'attaque des nœuds : pas de SSH, pas de paquets installés à la main, un système de fichiers en lecture seule. Elle a entendu parler de Talos Linux et du profil CIS de RKE2.
>
> Je ne veux pas une opinion : je veux des **essais sur le lab**, mesurés, et un **ADR** (ADR-0180) qui tranche la stratégie de distribution et de cycle de vie des clusters de MédiSphère. Kind et k3d pour les postes de développement, k3s pour l'agence, RKE2 pour le durcissement, Talos pour l'OS immuable, et **Cluster API** pour gérer des clusters comme des ressources, sur notre Proxmox.
>
> Contraintes : `k8s-par1` reste notre cluster de référence et ne doit pas en souffrir (on l'arrête pendant les essais lourds, on le redémarre vert à la fin) ; la mémoire de `pve01` n'est pas extensible ; tout ce qui sera conservé passe par le code, comme d'habitude. Ce qui n'est pas retenu est détruit en fin d'étude.
>
> Karim te fait d'abord passer en revue ce que tu sais des distributions.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 18, MédiSphère a une stratégie écrite et éprouvée (étiquette `distributions-v1` du dépôt `plateforme/medisphere`, au mini-projet) :

- un poste de développement **`m18-dev01`** (Docker, kind, k3d, clusterctl, image-builder) et des clusters de développement décrits par des fichiers de configuration versionnés ;
- un cluster **k3s** monoœud sur **`k3s01`** (l'agence simulée), puis un banc **k3s haute disponibilité** à etcd intégré sur trois VMs jetables, mis à jour automatiquement par le *system-upgrade-controller* ;
- un cluster **RKE2** de trois nœuds au **profil CIS** sur Rocky Linux 10 ;
- un cluster **Talos Linux 1.14** de trois nœuds, piloté par son API (`talosctl`), corrigé par *patches* et monté de version sans SSH ;
- **Cluster API** : un cluster de gestion amorcé dans kind, le fournisseur Proxmox **CAPMOX**, une image de nœud construite par **image-builder**, un cluster de charge de travail **`capi-essai`** sur le VLAN 40, puis le **pivot** du cluster de gestion vers `k3s01` ;
- au palier 3 et au mini-projet : cycle de vie par Cluster API, sauvegarde et restauration selon la distribution, durcissement comparé, l'ADR-0180 et le tableau comparatif mesuré, un cluster de recette éphémère, puis le nettoyage complet.

Le **palier 1** (ce fichier et `01-decouverte.md`) fait le panorama, puis monte une distribution par exercice : kind et k3d, k3s, RKE2, Talos. Le **palier 2** (`02-operationnel.md`) les exploite : correctifs et montée de version de Talos, k3s en haute disponibilité avec mises à jour automatiques, puis Cluster API de bout en bout, de l'amorçage dans kind au pivot.

## Architecture du module

```
  adm01 (1001, MGMT 10.10.10.10) — kubectl 1.36 · helm 4 · talosctl 1.14 · clusterctl 1.12 · ~/src/{infra,ansible,distributions}
  ~/.config/workbook/m18/ : kubeconfigs et talosconfig des clusters d'essai (600)
        │ (MGMT joint tout le lab)
  ═════╪═════════════════════ gw01 / gw02 (VIP .1) ═══════════════════════════════════════════════════════
        │                                                                     │ 8006 (IPSet capi) │
  VLAN 99 SANDBOX 10.10.99.0/24 (DHCP Kea + DDNS)                              ▼                   │
  ┌──────────────────────┐ ┌──────────────┐ ┌───────────────────────┐ ┌─────────────────────┐     pve01
  │ m18-dev01 (2188)     │ │ k3s01 (2181) │ │ rke2-01..03 (2182-84) │ │ talos-01..03        │     API Proxmox
  │ Docker 29 · kind     │ │ k3s 1.36     │ │ Rocky 10 · RKE2 1.36  │ │ (2185-87) Talos 1.14│     :8006
  │ k3d · clusterctl     │ │ SQLite       │ │ profil CIS, SELinux   │ │ .85 .86 .87 statiq. │       ▲
  │ image-builder        │ │ agence LYO1  │ │ 3 serveurs (etcd)     │ │ API :50000, pas SSH │       │
  │ ┌─────────────────┐  │ │ puis cluster │ └───────────────────────┘ └─────────────────────┘       │
  │ │kind « gestion » │──┼─┼─de gestion ──┼────────────── clusterctl move (E12) ──────────────────────┤
  │ │CAPI + CAPMOX    │  │ │ (E12)        │   k3s-ha01..03 (5191-5193, jetables, E07)              │
  │ └─────────────────┘  │ └──────────────┘                                                         │
  └──────────────────────┘                    │ 6443 (vers la VIP du cluster capi-essai)            │
                                              ▼                                                     │
  VLAN 40 K8S 10.10.40.0/24 ─────────────────────────────────────────────────────────────────────────┘
     k8s-par1 (.51-.63, VIP .200) : ARRÊTÉ pendant les essais lourds
     capi-essai : VMs 5180-5189 créées par CAPMOX depuis le template 9060, adresses .150-.169 (IPAM in-cluster),
                  VIP du plan de contrôle .210 (kube-vip), Cilium 1.20 par ClusterResourceSet
```

Points structurants :

- **Une distribution = un essai = des VMs jetables.** Tout le module vit dans l'état OpenTofu **`envs/m18`** de `plateforme/infra` (étiquette `env-m18`). Détruire le module ne touche ni au socle ni à `k8s-par1`.
- **Le code des essais** va dans un nouveau projet GitLab, **`plateforme/distributions`** (clone `~/src/distributions` sur `adm01`) : `kind/`, `k3d/`, `k3s/`, `rke2/`, `talos/` (des *patches*, jamais de secrets), `capi/` (manifestes Cluster API). Les rôles Ansible (`k3s`, `rke2`, `outils_distributions`) vont dans `plateforme/ansible`, la documentation dans `plateforme/medisphere` (`docs/kubernetes/distributions/`).
- **Talos n'a ni SSH ni Ansible.** On le configure par son API, avec des fichiers de configuration générés et des *patches* versionnés. C'est le seul essai dont les VMs ne sont pas dans l'inventaire Ansible.
- **Cluster API inverse la relation.** Ce n'est plus OpenTofu qui crée les VMs des nœuds, c'est un contrôleur qui tourne **dans un cluster** (le cluster de gestion) et qui appelle l'API de Proxmox. Le cluster de gestion naît dans kind (jetable), puis on le **pivote** vers `k3s01`, qui devient durable.
- **La mémoire est le facteur limitant.** `k8s-par1` est arrêté, et on n'allume jamais tout à la fois (tableau ci-dessous).

### Hôtes du module

| Hôte | VMID | Réseau | Système | Ressources | Étiquettes Proxmox | Exercices |
|---|---|---|---|---|---|---|
| `k3s01` | 2181 | `vsandbox` DHCP, MAC `bc:24:11:99:18:81` | Debian 13 (image dorée `current`) | 2 vCPU, 4 Go, 32 Gio | `env-m18`, `role-k3s` | E03, E12 (et suite) |
| `rke2-01..03` | 2182-2184 | `vsandbox` DHCP, MAC `…:18:82` à `:84` | **Rocky Linux 10** (image dorée `current`) | 2 vCPU, 4 Go, 32 Gio | `env-m18`, `role-rke2` | E04 |
| `talos-01..03` | 2185-2187 | `vsandbox` **adresses fixes** 10.10.99.85-87, MAC `…:18:85` à `:87` | Talos Linux 1.14, image *nocloud* | 2 vCPU, 3 Go, 20 Gio | `env-m18`, `role-talos` | E05, E06 |
| `m18-dev01` | 2188 | `vsandbox` DHCP, MAC `…:18:88` | Debian 13 | 4 vCPU, 8 Go, 60 Gio | `env-m18`, `role-m18-dev` | E02, E08-E12 |
| `k3s-ha01..03` | 5191-5193 | `vsandbox` DHCP, MAC `…:18:91` à `:93` | Debian 13 (clone lié) | 2 vCPU, 2 Go, 20 Gio | `env-m18`, `role-k3s-ha` | E07 (trois serveurs, détruites à la fin de l'exercice) ; E14 à E23 (`k3s-ha01` serveur, `k3s-ha02` agent) ; E25 (démonstration) |
| VMs de `capi-essai` | 5180-5189 | VLAN 40, 10.10.40.150-169, VIP 10.10.40.210 | Ubuntu 24.04 (template 9060, puis 9061) | 2 vCPU, 4 Go, 32 Gio | posées par CAPMOX : `env-m18`, `capi-essai` | E10 à E13, E21 |
| VMs jetables de contrôle | 5189 (E08), 5188 (E09) | `vsandbox` | clone d'un template | — | — | contrôle préalable de CAPMOX, essai du template ; supprimées aussitôt |
| `tpl-capi-ubuntu2404-k136` | 9060 | — | Ubuntu 24.04 + Kubernetes 1.36.4 | — | `capi`, `current`, `k8s-v1.36.4` | E09 |
| `tpl-capi-ubuntu2404-k136-2` | 9061 | — | Ubuntu 24.04 + Kubernetes 1.36.5 | — | `capi`, `current`, `k8s-v1.36.5` (9060 perd `current`) | E13 |

Pourquoi des exceptions :

- **Talos a des adresses fixes.** Le client `talosctl` et les certificats de l'API Talos et de Kubernetes visent un point d'accès stable (`talos-01.par1.medisphere.internal`). Un bail DHCP peut changer, et Talos en mode maintenance n'annonce pas forcément son nom au DDNS. Les adresses 10.10.99.85-87 sont dans la plage « nœuds de clusters » (`.50-.99`) de `vsandbox`, hors du pool DHCP (`.100-.199`) ; elles arrivent dans l'invité par le lecteur cloud-init de Proxmox (format *nocloud*), et leurs noms sont publiés par OpenTofu.
- **RKE2 sur Rocky Linux 10.** La matrice de support de RKE2 1.36 (SUSE) liste SLES, RHEL et dérivés (dont Rocky 10), et Ubuntu, mais **pas Debian**. On reste dans le supporté.
- **`k3s-ha01..03` en 5191-5193.** Ce sont des VMs de bac à sable (PLAN §4.6) : clones liés de l'image dorée, hors NetBox, décrites par un inventaire Ansible statique, détruites dès la vérification faite.
- **Les VMs de `capi-essai`** ne sont pas décrites dans `envs/m18` : c'est CAPMOX qui les crée et les détruit. OpenTofu ne doit **jamais** les voir (pas d'import, pas de source de données qui les liste sans filtre).

### Budget mémoire

`pve01` a 128 Go. Socle v3 (`gw01/02`, `adm01`, `dns01/02`, `ca01`, `git01`, `nbx01`, `s3-01`, `runner01/02`, `lb01/02`, `reg01`) ≈ 37 Go. Règle du module : **pas plus de ≈ 30 Go en plus du socle**, donc `k8s-par1` (36 Go) arrêté et une seule famille d'essais allumée à la fois en plus de `m18-dev01`.

| Exercices | Présent en plus du socle | Total approx. |
|---|---|---|
| E02 | `m18-dev01` (8) | ≈ 45 Go |
| E03 | `m18-dev01`, `k3s01` (4) | ≈ 49 Go |
| E04 | `m18-dev01`, `k3s01`, `rke2-01..03` (12) ; groupe `rke2` retiré à la fin | ≈ 61 Go |
| E05-E06 | `m18-dev01`, `k3s01`, `talos-01..03` (9) ; groupe `talos` retiré à la fin de E06 | ≈ 58 Go |
| E07 | `m18-dev01`, `k3s01`, `k3s-ha01..03` (6), détruites à la fin | ≈ 55 Go |
| E08-E12 | `m18-dev01`, `k3s01`, VMs de `capi-essai` (3 × 4) | ≈ 61 Go |

Les familles retirées (`rke2`, `talos`) sont reconstruites par le code au palier 3 (même `groupes`, même playbook ; pour Talos, même bundle de secrets) : la reconstruction fait partie de la comparaison.

### Ports et flux du module

| Flux | Port | Exercice | État sur `gw01`/`gw02` |
|---|---|---|---|
| `adm01` → toutes les VMs du module (SSH, API Kubernetes, API Talos) | 22, 6443, 9345, 50000 | tous | existant : MGMT joint tout le lab |
| VMs de `vsandbox` → Internet (paquets, images, Image Factory, GitHub) | 443, 80 | tous | existant (« lab vers Internet ») |
| VMs de `vsandbox` → `reg01` (cache Harbor) | 443 | E03-E06 | existant (M13-E02) |
| nœuds d'un même cluster entre eux (etcd, superviseur RKE2, VXLAN, kubelet, API Talos) | 2379-2381, 6443, 9345, 8472/udp, 10250, 50000-50001 | E03-E07 | même VLAN : ne traverse pas la passerelle |
| `m18-dev01` → VMs de build d'image-builder (SSH), VMs de build → serveur HTTP de Packer sur `m18-dev01` | 22, 8000-9000 | E09 | même VLAN |
| **`m18-dev01`, `k3s01` → API de `pve01`** | 8006 | E08-E12 | **à ouvrir** : bordure **et** pare-feu Proxmox (IPSet dédié `capi`) |
| **`m18-dev01`, `k3s01` → API du cluster `capi-essai`** (VIP et nœuds) | 6443 | E10-E12 | **à ouvrir** : `vsandbox` → 10.10.40.150-169 et 10.10.40.210 |
| nœuds de `capi-essai` → `reg01`, `dns01/02`, Internet, NTP de la passerelle | 443, 53, 123 | E10 | existant (M14) |
| **`k3s-ha01`, `rke2-01..03` (`vsandbox`) → `s3-01`** (instantanés etcd) | 8333 | E14 | **à ouvrir** (provisoire) |
| **cluster de gestion éphémère sur `m18-dev01` → API OpenStack et IP flottantes** | 443, 6443 | E16 (facultatif) | **à ouvrir** (provisoire) |

Tous les flux **à ouvrir** de ce tableau sont provisoires : le mini-projet les retire (règles de la bordure, IPSet `capi` et règle 8006 du pare-feu de `pve01`), sauf décision contraire écrite dans l'ADR-0180.

Tout nouveau flux suit la règle du bloc A : une ligne commentée dans `group_vars/role_routeur/pare_feu.yml` (motif, exercice), une ligne dans `docs/socle/matrice-flux.md`, et pour `pve01`, une règle du pare-feu Proxmox.

---

## Le chemin imposé

1. **OpenTofu** : état **`envs/m18`** de `plateforme/infra` (clé `envs/m18/terraform.tfstate` dans `tofu-state`). VMs Debian et Rocky par le module **`vm-noeud`** (v2.4, carte DHCP depuis M12-E02) ; VMs Talos et VMs jetables par des ressources dédiées, écrites dans le même état. Le choix des familles présentes se fait par variables (`groupes`, `k3s_ha_noeuds`), jamais à la main dans Proxmox : une famille qu'on ne sert plus est **retirée** (ses VMs sont détruites) et reconstruite par le code quand on en a de nouveau besoin. Un `qm shutdown` ne tient pas : le prochain `tofu apply` redémarre toute VM décrite (`started = true`).
2. **Ansible** : source d'inventaire **`inventories/lab/netbox-m18.yml`** (étiquette `env-m18`, groupes `env_m18`, `role_m18_dev`, `role_k3s`, `role_rke2`) et inventaire statique `inventories/lab/m18-k3s-ha.yml` (groupe `k3s_ha`) pour les VMs jetables ; rôles communs (`base`, `ssh_durci`, `ca_lab`, `ssh_ca_hote`, `ssh_ca_utilisateur`), puis `docker_engine` (M12), `outils_k8s` (M14), et les nouveaux **`outils_distributions`**, **`k3s`**, **`rke2`** ; playbook **`playbooks/m18.yml`**.
3. **`plateforme/distributions`** (créé en E02) : fichiers de configuration des distributions, *patches* Talos, manifestes Cluster API ; relu en MR comme le reste. Aucun secret, aucun fichier généré qui en contient (configurations machine de Talos, kubeconfigs).
4. **Secrets** : jetons de k3s et RKE2 en Ansible Vault `lab` ; bundle de secrets Talos dans `~/.config/workbook/m18/talos-secrets.yaml` (600) **et** chiffré (Vault `lab`) dans `plateforme/distributions` ; jeton Proxmox de Cluster API dans `~/.config/workbook/pve-capi.env` (600), injecté dans le cluster de gestion par un Secret créé depuis l'entrée standard, jamais par un fichier versionné.
5. **Documentation** : `plateforme/medisphere`, dossier **`docs/kubernetes/distributions/`** (fiche de chaque essai, vérification préalable CAPMOX, cluster de gestion ; au palier 3 : tableau comparatif, ADR-0180 dans `adr/`, runbooks RB-180 et suivants) ; la matrice des flux et le registre des secrets restent dans `docs/socle/`.

**Mesure.** L'ADR-0180 comparera des chiffres. Dès le premier essai, note dans `docs/kubernetes/distributions/mesures.md` : temps d'installation (de `tofu apply` à « tous les nœuds Ready »), mémoire consommée au repos (`free -m` sur les nœuds, `talosctl memory` pour Talos), nombre de commandes ou de fichiers nécessaires, version de Kubernetes obtenue. Mesure toujours de la même façon.

---

## Concepts clés

**Ce qu'est une « distribution ».** Kubernetes est un ensemble de binaires (kube-apiserver, kubelet…) qu'il faut installer, configurer, relier par une PKI et compléter (réseau des pods, DNS, stockage). Une distribution fait des choix à ta place et les emballe : comment on installe, quel runtime, quelle base de données, quel CNI, quelles valeurs de sécurité par défaut, comment on monte de version. kubeadm est l'outil d'amorçage du projet : il fait le minimum et te laisse le reste (M14).

**kind et k3d : des nœuds dans des conteneurs.** Chaque « nœud » est un conteneur Docker qui fait tourner systemd, containerd et le kubelet. kind (*Kubernetes IN Docker*) utilise kubeadm dans des images `kindest/node` ; k3d fait tourner k3s dans des conteneurs `rancher/k3s`. Démarrage en secondes, destruction sans trace, mais rien de ce qui touche au vrai réseau, au vrai stockage ou au noyau ne s'y teste fidèlement. Outils de poste de développement et de CI, jamais de production.

**k3s : un binaire.** Un seul exécutable qui contient le plan de contrôle, le kubelet, containerd, flannel, CoreDNS, un contrôleur Helm, un répartiteur de charge de services (*ServiceLB*), un provisionneur de volumes locaux et Traefik. Base de données : **SQLite** par *kine* (une couche qui traduit l'API d'etcd) pour un nœud unique, ou **etcd intégré** (`--cluster-init`) pour la haute disponibilité. Pensé pour la périphérie (*edge*) et les petites machines.

**RKE2 : k3s en version durcie.** Même conception (un superviseur, un binaire), mais composants en pods statiques, etcd par défaut, images construites et scannées par SUSE, et un **profil CIS** qui vérifie l'hôte (paramètres noyau, utilisateur `etcd`) et applique des réglages restrictifs (Pod Security `restricted`, *NetworkPolicies*, droits des fichiers). Vise les environnements réglementés.

**Talos Linux : l'OS est l'API.** Un système minimal, en lecture seule, sans shell ni SSH ni gestionnaire de paquets, dont la seule interface est une API gRPC authentifiée par TLS mutuel (port 50000). Toute la configuration tient dans des documents YAML (*machine configuration*) appliqués par `talosctl` ; on la modifie par *patches* ; on monte de version en remplaçant l'image entière (schéma A/B, retour arrière possible). Les extensions système (agent QEMU, pilotes) s'ajoutent à la construction de l'image par l'**Image Factory**.

**Cluster API (CAPI) : des clusters comme des objets.** Un **cluster de gestion** porte des contrôleurs et des CRD ; un objet `Cluster` y décrit un **cluster de charge de travail**. Le contrôleur d'**infrastructure** (ici CAPMOX) crée les machines (des VMs Proxmox clonées d'un template) ; le contrôleur d'**amorçage** (kubeadm) génère leur cloud-init ; le contrôleur de **plan de contrôle** (`KubeadmControlPlane`) les fait devenir nœuds de contrôle, et les `MachineDeployment` font les travailleurs, comme un Deployment fait des pods. Monter de version, c'est changer une version ou un template dans un objet ; réparer, c'est remplacer une machine. Le cluster de gestion est précieux : on l'amorce dans un cluster jetable (kind), puis on le **pivote** (`clusterctl move`) vers un cluster durable.

**L'image de nœud.** Cluster API ne configure pas un OS générique : il clone un **template** qui contient déjà containerd, kubelet, kubeadm à la bonne version. Le projet **image-builder** (Packer + Ansible) produit ces templates, un par version de Kubernetes.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6, relevées le 2026-10-15) | kind **0.33.0** (nœuds `kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed` : il n'existe pas d'image 1.36.5 pour kind 0.33) ; k3d **5.9.0** (son k3s par défaut est **v1.35.5-k3s1** : toujours passer l'image) avec `rancher/k3s:v1.36.5-k3s1` ; k3s **v1.36.5+k3s1** (canal `stable`) ; RKE2 **v1.36.5+rke2r1** (RPM `rke2-server-1.36.5~rke2r1-0.el10`) ; Talos **v1.14.1** puis **v1.14.2** (talosctl 1.14.2), Kubernetes **v1.36.4** puis **v1.36.5** (Talos 1.14 installe 1.37 si on ne fixe rien) ; system-upgrade-controller **v0.20.2** ; Cluster API / clusterctl **v1.12.11** ; CAPMOX **v0.9.1** (API `v1alpha2`) ; IPAM *in-cluster* **v1.1.1** ; kube-vip **v1.2.4** ; image-builder **v0.1.55** (Ubuntu 24.04.4) ; Cilium **1.20.2** ; au palier 3 : kube-bench **0.16.0** (E15), CAPO **0.15.x** (E16, facultatif) |
| Changements de comportement | Talos 1.14 : la plupart des champs du document `v1alpha1` sont **dépréciés** au profit de documents séparés (`KubeletConfig`, `KubeNodeConfig`, `RegistryMirrorConfig`, `TimeSyncConfig`, `UnattendedInstallConfig`…), un champ déprécié et son document de remplacement s'excluent ; l'image `ghcr.io/siderolabs/installer` n'est plus publiée (installeurs de l'Image Factory). RKE2 1.36 : Traefik est l'Ingress par défaut (ingress-nginx déprécié, retiré en 1.37). CAPMOX : sans clé `insecure` dans le Secret d'identifiants, **la vérification TLS de l'API Proxmox est désactivée**. Détails dans les exercices |
| État OpenTofu | `envs/m18` (`plateforme/infra`) : variables `groupes` (`dev`, `k3s`, `rke2`, `talos`) et `k3s_ha_noeuds` |
| Projets | `plateforme/distributions` (E02) ; `plateforme/ansible` : rôles `outils_distributions`, `k3s`, `rke2`, playbook `m18.yml`, sources `netbox-m18.yml` et `m18-k3s-ha.yml` ; `plateforme/images` : dossier `capi/` (E09) ; `plateforme/medisphere` : `docs/kubernetes/distributions/` |
| Clusters | `dev` (kind et k3d, sur `m18-dev01`) ; `k3s01` (agence, SQLite) ; `rke2` (3 serveurs) ; `talos-essai` (1 nœud de contrôle `talos-01`, 2 travailleurs) ; `k3s-ha` (3 serveurs, etcd intégré) ; `gestion` (kind, cluster de gestion amorcé) ; `capi-essai` (1 nœud de contrôle, 2 travailleurs) |
| Fichiers locaux sur `adm01` (600) | `~/.config/workbook/m18/` : `k3s01.kubeconfig`, `rke2.kubeconfig`, `talosconfig`, `talos.kubeconfig`, `talos-secrets.yaml`, `k3s-ha.kubeconfig`, `kind-gestion.kubeconfig` (jusqu'au pivot de E12), `capi-essai.kubeconfig`, puis au palier 3 `talosconfig-sauvegarde` (E14) et `recette-mediagenda.kubeconfig` (E18) ; `~/.config/workbook/pve-capi.env` (compte `wb-capi@pve!capi`), `~/.config/workbook/s3-etcd-m18.env` (E14) |
| Cluster API | espace `capi-essai` du cluster de gestion ; compte Proxmox `wb-capi@pve` + jeton `wb-capi@pve!capi`, rôle `WBCapi` ; Secret d'identifiants `capi-essai-proxmox` (par `credentialsRef`) ; template 9060 ; VMID 5180-5189 (`vmIDRange`) ; adresses 10.10.40.150-169 (`ipv4Config` du `ProxmoxCluster`, réservoir créé par CAPMOX : `capi-essai-v4-icip`) ; VIP 10.10.40.210 |
| Brouillons | `~/m18/eXX/` sur `adm01` et `m18-dev01` (non versionnés, sans secret) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05) |
| `<NOEUD>` | Nom du nœud Proxmox de `pve01` (celui de `pvesh get /nodes`) |
| `<IP-PVE01>` | Adresse de `pve01` sur le LAN maison (PLAN §4.1) |
| `<IP-M18-DEV01>`, `<IP-K3S01>` | Adresses DHCP (stables : MAC imposée) de `m18-dev01` et `k3s01`, lues dans le DNS |
| `<VERSION-TOFU-MODULES>` | Étiquette de `plateforme/tofu-modules` qui contient `vm-noeud` v2.4 (M12-E02) |
| `<SECRET>` | Secret d'un jeton Proxmox (affiché une seule fois à sa création) : il ne va que dans un fichier 600 de `~/.config/workbook/` |

### Variables de `lab/lab.env`

Les vérifications du module ont des valeurs par défaut qui conviennent au lab. Tu peux les surcharger dans `lab/lab.env` :

```
WB_M18_DIR="$HOME/.config/workbook/m18"     # kubeconfigs et talosconfig des clusters d'essai
WB_M18_DEV=m18-dev01                        # poste de développement (SSH : admin)
WB_M18_K3S=k3s01
WB_M18_RKE2="rke2-01 rke2-02 rke2-03"
WB_M18_TALOS="10.10.99.85 10.10.99.86 10.10.99.87"
WB_M18_RECETTE_URL="http://m18-dev01.par1.medisphere.internal:8080"   # /sante du cluster de recette (E18)
WB_OS_CLOUD_PLATEFORME=medisphere-plateforme   # nuage de clouds.yaml lu par le contrôle de E16 (facultatif)
WB_M18_TEMPLATES_CONSERVES=0                # E25 : l'ADR-0180 garde-t-il les templates 9060-9069 ?
WB_M18_WBCAPI_CONSERVE=0                    # E25 : l'ADR-0180 garde-t-il le compte wb-capi ?
```

Les vérifications lisent les clusters d'essai avec leurs **kubeconfigs d'administration** (fichiers ci-dessus), en commandes de lecture seulement (`get`) : ces clusters sont jetables et n'ont pas de compte `wb-checks`. `k8s-par1` garde son compte de vérification, et le contrôle de sortie du module est `lab/bin/check 14 46`.

---

## Règles du module

1. **Arrêter `k8s-par1` proprement avant les essais lourds**, avec la procédure du M14 : travailleurs d'abord (`qm shutdown 2146`, `2145`, `2144`), puis les nœuds de contrôle (`2143`, `2142`, `2141`) ; redémarrage dans l'ordre inverse (nœuds de contrôle d'abord). Vérifie avant de l'arrêter qu'il est vert (`lab/bin/check 14 46`) et note-le dans `mesures.md` : c'est la référence de fin de module.
2. **Le contexte est toujours explicite.** Tu auras jusqu'à sept clusters. Toute commande `kubectl` d'écriture porte `--kubeconfig` ou `--context` ; `talosctl` porte `--talosconfig` (ou la variable `TALOSCONFIG`) et `--nodes`. Une écriture sur le mauvais cluster est l'erreur la plus probable de ce module.
   > ⚠️ **Attention** : `kubectl delete cluster capi-essai` sur le cluster de gestion **détruit les VMs** Proxmox correspondantes ; `talosctl reset` efface le disque du nœud visé ; `k3s-uninstall.sh` et `rke2-uninstall.sh` effacent le nœud et ses données. Relis la cible avant d'appuyer sur Entrée.
3. **Pas de `curl | sh`.** Les scripts d'installation (k3s, RKE2) sont téléchargés à une version précise, relus, et leur empreinte SHA-256 est fixée dans le rôle Ansible. Les binaires (kind, k3d, clusterctl, talosctl) sont vérifiés par la somme publiée avec la version.
4. **Pas de vérification TLS désactivée** (`--insecure-skip-tls-verify`, `insecure: true`, `curl -k`). Deux outils du module la désactivent **par défaut** (CAPMOX, et le gabarit Packer d'image-builder) : tu la réactives. Seule exception assumée : `talosctl apply-config --insecure` sur un nœud en maintenance, qui n'a encore aucune identité (le canal est chiffré, mais non authentifié ; on le dit, on le limite au premier contact).
5. **Rien de ce que CAPMOX crée ne se modifie à la main dans Proxmox.** Une VM de `capi-essai` arrêtée, supprimée ou redimensionnée à la main sera « réparée » par le contrôleur, ou le contrôleur se bloquera. On agit sur les objets du cluster de gestion.
6. **Fin de module** (mini-projet) : toutes les VMs 2181-2188, 5180-5189, 5191-5193 détruites (sauf choix contraire écrit dans l'ADR-0180), template 9060 conservé ou supprimé selon l'ADR, compte `wb-capi` supprimé s'il n'est pas conservé, `k8s-par1` redémarré et vert.

---

## Préparer l'environnement

Vérifie l'état d'entrée et la mémoire :

```
admin@adm01:~$ lab/bin/check 14 46
admin@adm01:~$ lab/bin/check 17 25
admin@adm01:~$ ssh root@pve01 'free -g | head -2; qm list | grep -E " 90(1|2|3|4)[0-9] "'
admin@adm01:~$ cd ~/src/ansible && uv run ansible-inventory --graph socle
```

Le premier contrôle (mini-projet du M14) doit être vert : c'est l'état que tu rendras en fin de module. Le second (M17, `packaging-v1`) garantit le chart `mediagenda` publié dans Harbor, dont le palier 3 se sert. La troisième commande montre la mémoire libre (il en faut une trentaine de Go **après** l'arrêt de `k8s-par1`) et les images dorées Debian (9010-9029) et Rocky (9030-9049) : il en faut une `current` de chaque famille.

Arrête ensuite `k8s-par1` (règle 1) et crée le dossier des fichiers locaux :

```
admin@adm01:~$ install -d -m 700 ~/.config/workbook/m18 ~/m18
```

Le projet `plateforme/distributions` est créé en E02 (même modèle que `plateforme/k8s` : branche `main` protégée, MR obligatoire, gabarits de CI `qualite.yml` du M01, `yamllint` sur tous les YAML).

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 18 <XX>`. Elles sont en lecture seule : configuration Proxmox lue sur `pve01`, SSH vers les VMs Debian et Rocky, `talosctl get` avec ton `talosconfig`, `kubectl get` avec les kubeconfigs des clusters d'essai, API GitLab en lecture.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M18-EXX/` : `infra/` reproduit `plateforme/infra`, `ansible/` reproduit `plateforme/ansible`, **`distributions/`** reproduit `plateforme/distributions`, `images/` reproduit `plateforme/images`, `medisphere/` la documentation.
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé

```
E01 ─ E02 ─ E03 ─ E04 ─ E05            (palier 1)
              │           │
              │           E06          (palier 2)
              E07
E02 ─ E08 ─ E09 ─ E10 ─ E11 ─ E12
       ↑ vérification préalable CAPMOX : son résultat décide de E10 (CAPMOX ou repli CAPD)
```

1. **E01** — à froid, avant toute manipulation.
2. **E02 → E05** — une distribution par exercice ; E02 crée l'environnement OpenTofu, le projet `plateforme/distributions` et `m18-dev01`, dont tout le reste dépend.
3. **E06** juste après E05 (même cluster Talos) ; **E07** après E03 (même rôle `k3s`).
4. **E08 → E12** dans l'ordre strict : Cluster API se construit pièce par pièce. E11 (revue) se fait idéalement après E10, quand tu as écrit tes propres manifestes.
5. **Paliers 3 à 5** : l'ordre est donné en tête de chaque fichier (E13 → E14 → E15 → E17 → E18, E16 facultatif ; puis les pannes E19 à E22 une à une, E23, E24 ; enfin le mini-projet E25).

Durée indicative (somme des durées des exercices) : palier 1, 12 à 14 heures ; palier 2, 16 à 19 heures ; palier 3, 14 à 17 heures (sans E16) ; palier 4, 7 à 9 heures ; mini-projet, 8 à 12 heures.

## Pour aller plus loin

- kind : <https://kind.sigs.k8s.io/docs/user/configuration/> · k3d : <https://k3d.io/stable/usage/configfile/>
- k3s : <https://docs.k3s.io/> (architecture, configuration, registres privés, HA à etcd intégré, mises à jour automatiques)
- RKE2 : <https://docs.rke2.io/> (guide de durcissement CIS, SELinux, problèmes connus) · matrice de support : <https://www.suse.com/suse-rke2/support-matrix/all-supported-versions/rke2-v1-36>
- Talos Linux 1.14 : <https://docs.siderolabs.com/talos/v1.14/> (Proxmox, *nocloud*, *patches*, carte des documents de configuration, montée de version) · Image Factory : <https://factory.talos.dev/>
- Cluster API : <https://cluster-api.sigs.k8s.io/> (concepts, `clusterctl move`, matrice des versions) · CAPMOX : <https://github.com/ionos-cloud/cluster-api-provider-proxmox/tree/v0.9.1/docs> · image-builder : <https://image-builder.sigs.k8s.io/capi/providers/proxmox>
