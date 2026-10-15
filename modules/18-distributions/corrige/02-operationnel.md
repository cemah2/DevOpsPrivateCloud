# Module 18 — Palier 2 : Opérationnel — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Fichiers complets dans [`fichiers/`](fichiers/) : `M18-E06/` (patches et scripts Talos, `versions.env` monté), `M18-E07/` (`k3s-ha.tf`, inventaire statique, variables, playbook v4, `k3s/suc/`, fiche k3s complétée), `M18-E08/` (kind `gestion` et `gestion-capd`, `capi/versions.env`, `init.sh`, `pve-compte-capi.sh`, `preflight-pve.sh`, extrait de la matrice de la bordure, playbook v5, `capmox-pve9.md`), `M18-E09/` (`plateforme/images` : `capi/`, fiche `image-noeud.md`), `M18-E10/` (`capi/capi-essai/`, `capi/identifiants.sh`, `capi/cilium/`, `cluster-api.md`), `M18-E11/` (`capi/revue-lucas/`), `M18-E12/` (`capi/pivot.sh`, `cluster-api.md` complété).

**Ce qui a été vérifié à la rédaction** (2026-10-15) :
- Talos : *patches* de E06 fusionnés par `talos/generer.sh` (version E06) avec un bundle de test ; configuration produite validée (`talosctl validate --mode cloud`) ; contrôlé dans le résultat : quatre `RegistryMirrorConfig`, `TimeSyncConfig`, `TrustedRootsConfig`, plus de `discovery.talos.dev`, étiquettes fusionnées dans `KubeNodeConfig`, kubelet `v1.36.5` ; options de `talosctl` 1.14.2 lues dans son aide (`upgrade --image`, `upgrade-k8s --to --dry-run`, `apply-config --dry-run`, `health`, `list -r`) ; documentation 1.14 (*Upgrading Talos*, *Time*, *Configuration Patches*) ;
- k3s HA : `k3s-ha.tf` passe `tofu validate` (avec le reste d'`envs/m18`) ; manifestes de system-upgrade-controller v0.20.2 présents à l'URL de la version (image `rancher/system-upgrade-controller:v0.20.2`, espace `system-upgrade`, compte `system-upgrade`) ; image `rancher/k3s-upgrade:v1.36.5-k3s1` présente ; champs du plan conformes à la documentation de k3s (*Automated Upgrades*) ;
- Cluster API : composants de CAPI v1.12.11 (cœur, kubeadm ×2, CAPD), CAPMOX v0.9.1 et IPAM in-cluster v1.1.1 téléchargés ; leurs CRD converties en schémas JSON stricts, et **tous les manifestes** (`capi-essai`, `revue-lucas`, et ceux de Lucas) validés contre eux par `kubeconform -strict` (les défauts de schéma de Lucas, comme `matchPolicy: subset`, sont bien refusés) ; lecture du code de CAPMOX v0.9.1 (`api/v1alpha2`, `pkg/scope/cluster.go` : clés `url`, `token`, `secret`, `insecure`, `root_ca` du Secret et TLS désactivé si `insecure` absente ; `cmd/main.go` : démarrage sans identifiants globaux ; `pkg/kubernetes/ipam` : réservoir `<cluster>-v4-icip` ; `internal/service/vmservice` : `vmIDRange`, `pool`, `tags`, recherche de template par étiquettes, `cloud-init status` par l'agent ; `internal/controller` : ownerRef sur le Secret ; go-proxmox v0.8.1 : ISO téléversée dans le premier stockage `iso`) ; `clusterctl` 1.12.11 : options d'`init`, `move` (`--to-kubeconfig`, `--to-directory`, `--dry-run`, `-n`), `generate cluster --list-variables`, `generate provider --describe`, fournisseurs connus (`proxmox`, `in-cluster`, `docker`) ;
- matrice de compatibilité de CAPI (branche release-1.13 : Kubernetes 1.36 accepté par CAPI ≥ 1.12.8 ; la page de l'étiquette v1.12.11 s'arrête à 1.35, elle n'est pas à jour) ;
- image-builder v0.1.55 : `packer/proxmox/packer.json` (`insecure_skip_tls_verify: true` écrit en dur, pas de `pool`), `ubuntu-2404.json` (ISO 24.04.4 et empreinte), `packer/config/kubernetes.json` et `containerd.json` (défauts 1.36.1, containerd 2.3.2), gabarit containerd (`config_path = "/etc/containerd/certs.d"`), Makefile (`PACKER_VAR_FILES`, `deps-proxmox`, `build-proxmox-ubuntu-2404`) ;
- privilèges de Proxmox VE 9 (*User Management*) : `VM.GuestAgent.Audit`, `…Unrestricted`, absence de `VM.Monitor`, `Datastore.AllocateTemplate` pour téléverser une ISO ;
- tous les scripts : `shellcheck -x`, `bash -n` ; manifestes : `yamllint`.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- **la compatibilité de CAPMOX v0.9.1 avec Proxmox VE 9** : c'est l'objet de la vérification préalable de E08, que seul ton lab peut trancher ; `preflight-pve.sh` n'a pas été exécuté contre un vrai `pve01` ;
- la liste exacte des privilèges de `WBCapi` (déduite du code, en particulier `VM.GuestAgent.Unrestricted` pour l'exécution de `cloud-init status` par l'agent) ;
- la visibilité des stockages par le jeton (CAPMOX doit choisir `capi-iso` parce qu'il ne voit que lui) ;
- la construction d'image-builder avec `iso_file` et `iso_url` vide (si Packer refuse, passe le jeton de Packer en écriture sur `hdd-bulk` le temps de la construction et laisse `iso_url`), et les options `pool` et `tags` ajoutées au gabarit ;
- le retour de kube-vip à `admin.conf` après l'init (`postKubeadmCommands`) ;
- la taille du ConfigMap de Cilium (le rendu de 1.20.2 doit tenir sous 1 Mio ; il dépasse 256 Kio, d'où `--server-side`) ;
- `clusterctl move` du kind de `m18-dev01` vers `k3s01` (aucun cluster démarré à la rédaction), et le déplacement du Secret `medisphere-root-ca` par l'étiquette `clusterctl.cluster.x-k8s.io/move` ;
- les sorties de commandes montrées sont **représentatives**.

---

### M18-E06 — Talos : correctifs de configuration et montée de version

**Solution**

*1. Les patches* ([`talos/patches/`](fichiers/M18-E06/distributions/talos/patches/)) :

| Fichier | Document | Opération | Pourquoi |
|---|---|---|---|
| `commun/10-ntp.yaml` | `TimeSyncConfig` | **ajout** (absent de la configuration générée : Talos utilise alors `time.cloudflare.com`) | source de temps du lab |
| `commun/20-sans-decouverte.yaml` | `DiscoveryServiceConfig` (`name: default`) | **suppression** (`$patch: delete`) | plus de service public `discovery.talos.dev` |
| `commun/30-miroirs.yaml` | 4 × `RegistryMirrorConfig` (`name: docker.io`…) | **ajout** (documents nommés) | cache Harbor, `overridePath: true` |
| `worker/10-etiquettes.yaml` | `KubeNodeConfig` | **fusion** (le document existe, les clés de `labels` s'ajoutent) | étiquettes des travailleurs |
| *(généré)* `racine-medisphere.yaml` | `TrustedRootsConfig` (`name: medisphere-root-ca`) | **ajout** | Harbor en TLS |

*2. `generer.sh` (version E06)* ([fichier](fichiers/M18-E06/distributions/talos/generer.sh)) construit à la volée un document `TrustedRootsConfig` à partir de `/usr/local/share/ca-certificates/medisphere-root-ca.crt` (indenté sous `certificates: |`), l'ajoute en `--config-patch`, et s'arrête si la racine est absente. La racine est publique, mais la recopier dans le dépôt ferait deux sources de vérité ; on la lit là où `ca_lab` l'a posée.

*3. Application.*
```
admin@adm01:~/src/distributions$ talos/generer.sh
admin@adm01:~/src/distributions$ talos/appliquer.sh talos-02 --essai
Dry run summary:
Applied configuration without a reboot (skipped in dry-run).
Config diff:
+apiVersion: v1alpha1
+kind: TimeSyncConfig
…
-apiVersion: v1alpha1
-kind: DiscoveryServiceConfig
…
admin@adm01:~/src/distributions$ for n in talos-01 talos-02 talos-03; do talos/appliquer.sh "$n"; done
admin@adm01:~$ talosctl -n 10.10.99.86 get timeservers
NODE          NAMESPACE   TYPE               ID            VERSION   TIMESERVERS
10.10.99.86   network     TimeServerStatus   timeservers   2         ["10.10.99.1"]
admin@adm01:~$ talosctl -n 10.10.99.86 list -r /etc/cri/conf.d
admin@adm01:~$ talosctl -n 10.10.99.86 get members        # vide : plus de découverte
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/talos.kubeconfig get nodes --show-labels | grep distribution=talos
```
Aucun de ces changements ne redémarre le nœud (le résumé du dry-run le dit) : temps, miroirs, racines, étiquettes et découverte sont appliqués à chaud par les contrôleurs de Talos. Ce qui redémarre : un changement d'installation, de disque, de noyau (arguments), certains changements réseau ; le mode `auto` décide et le dry-run l'annonce. Preuve du cache : un pod `docker.io/library/busybox:1.37` dans un espace d'essai, puis le journal du projet `dockerhub` de Harbor (tirage depuis 10.10.99.86 ou .87).

*4. Montée de Talos.* [`talos/monter.sh`](fichiers/M18-E06/distributions/talos/monter.sh) : ordre « nœud de contrôle puis travailleurs » lu dans `noeuds.txt`, version actuelle lue par `talosctl version`, `talosctl upgrade --image factory.talos.dev/nocloud-installer/<schéma>:v1.14.2 --wait` (draine le nœud, écrit la nouvelle image sur la partition inactive, redémarre), puis `talosctl health` avant le nœud suivant ; `--essai` montre le plan. `versions.env` change **avant** ([fichier](fichiers/M18-E06/distributions/talos/versions.env)) : le script y lit la version visée, et toute configuration régénérée ensuite porte l'installeur 1.14.2 ; dans l'autre ordre, une application du dépôt entre deux nœuds remettrait l'installeur 1.14.1 dans la configuration (sans effet immédiat, mais une réinstallation repartirait en 1.14.1).
```
admin@adm01:~/src/distributions$ talos/monter.sh talos --essai
== 10.10.99.85 : Talos v1.14.1 → v1.14.2 (factory.talos.dev/nocloud-installer/ce4c9805…:v1.14.2)
…
admin@adm01:~/src/distributions$ talos/monter.sh talos
admin@adm01:~$ talosctl -n 10.10.99.85,10.10.99.86,10.10.99.87 get extensions
```
Pendant la montée de `talos-01` (≈ 2 à 3 min) : l'API Kubernetes et l'API Talos du point d'accès ne répondent plus (un seul nœud de contrôle, etcd à un membre) ; les pods des travailleurs continuent de tourner et de servir, mais rien ne peut être planifié ni modifié. Après : l'extension `qemu-guest-agent` et l'extension virtuelle `schematic` (`ce4c9805…`) sont toujours là, parce que l'installeur porte **le même schéma**.

*5. Montée de Kubernetes.*
```
admin@adm01:~/src/distributions$ talos/monter.sh kubernetes --essai
automatically detected the lowest Kubernetes version 1.36.4
checking for removed Kubernetes component flags
checking for removed Kubernetes API resource versions
…
> "10.10.99.85": kube-apiserver: v1.36.4 -> 1.36.5
…
admin@adm01:~/src/distributions$ talos/monter.sh kubernetes
admin@adm01:~/src/distributions$ talos/generer.sh && for n in talos-01 talos-02 talos-03; do talos/appliquer.sh "$n" --essai; done
```
`upgrade-k8s` modifie la configuration machine de chaque nœud (images du kubelet, du kube-apiserver…, manifestes de démarrage) dans l'ordre plan de contrôle puis kubelets. Après, la configuration régénérée depuis le dépôt (`KUBERNETES_VERSION=1.36.5`) ne doit plus montrer aucune différence : c'est la preuve que le dépôt « dit la vérité ».

*6.* [`talos.md`](fichiers/M18-E05/medisphere/docs/kubernetes/distributions/talos.md) complété (procédures) ; mesures : ≈ 10 à 12 min pour les trois nœuds, ≈ 3 min d'API indisponible pendant le nœud de contrôle, ≈ 4 min pour `upgrade-k8s`. Puis `groupes` sans `talos`.

**Explications**

Talos sépare deux choses qu'un nœud Debian mélange : **l'image** (noyau, système, extensions : on la remplace en bloc, avec retour arrière A/B) et **la configuration** (documents YAML : on la corrige par *patch*, souvent à chaud). Il n'y a pas de troisième état. La conséquence pratique : un changement est toujours un *patch* dans le dépôt, une régénération, un dry-run et une application ; une montée de version est un changement de fichier de versions et une commande. Le dry-run d'`apply-config` est l'équivalent du `tofu plan`.

Les deux montées sont indépendantes : `talosctl upgrade` change Talos sans toucher à Kubernetes (depuis Talos 1.0), `upgrade-k8s` change Kubernetes sans changer d'image. On peut les faire dans l'ordre que l'on veut, à condition de respecter la matrice (Talos 1.14 supporte Kubernetes 1.33 à 1.37).

**Alternatives**

- `talosctl patch mc --patch @fichier` sur un nœud vivant : rapide, mais la modification n'est pas dans le dépôt ; à réserver au dépannage, et à reporter aussitôt.
- `--mode staged` : la configuration est appliquée au prochain redémarrage (utile pour regrouper un changement avec une montée de version).
- Fournisseur OpenTofu `siderolabs/talos` : la même boucle (configuration, application, montée de version) en `tofu apply` ; ou Omni pour une flotte.
- Miroirs avec `skipFallback: true` : plus aucune sortie vers les registres publics (parc isolé), au prix d'une dépendance totale à Harbor.

**Pièges classiques**

- Installeur `metal-installer`, ou schéma vide (`376567…`) : la montée enlève l'agent QEMU, et le nœud, *nocloud*, peut perdre ses réglages de plateforme.
- Deux nœuds montés en même temps : sur un cluster à un nœud de contrôle, c'est sans risque pour etcd, mais deux travailleurs drainés à la fois peuvent violer les PDB et couper un service.
- `versions.env` oublié après `upgrade-k8s` : la prochaine application du dépôt **redescend** les images du kubelet (Talos l'accepte, Kubernetes le supporte mal).
- Écrire `machine.time.servers` (forme `v1alpha1` dépréciée) **et** un `TimeSyncConfig` : un champ déprécié et son document de remplacement s'excluent, la configuration est refusée.
- `$patch: delete` sans `name: default` sur un document nommé : le *patch* ne trouve pas le document à supprimer.

**En production chez MédiSphère**

Trois nœuds de contrôle (montées sans coupure de l'API), une fenêtre de changement par CHG, un instantané etcd avant chaque montée (`talosctl etcd snapshot`, palier 3), les images de l'Image Factory mises en cache dans Harbor (installeurs compris), une revue des notes de version de chaque version de Talos (ruptures de documents de configuration), et une CI sur `plateforme/distributions` qui régénère et valide la configuration à chaque MR.

---

### M18-E07 — k3s : haute disponibilité intégrée et mises à jour automatiques

**Solution**

1. [`k3s-ha.tf`](fichiers/M18-E07/infra/envs/m18/k3s-ha.tf) : `for_each = toset(var.k3s_ha_noeuds)`, VMID `5190 + dernier chiffre`, MAC `bc:24:11:99:18:9N`, `clone { full = false }` depuis la source de données de l'image dorée Debian `current`, `initialization` en DHCP avec le compte `admin` et la clé de `adm01`.
   ```
   admin@adm01:~/src/infra/envs/m18$ tofu apply -var 'k3s_ha_noeuds=["k3s-ha01","k3s-ha02","k3s-ha03"]'
   ```
   (ou dans `terraform.tfvars`, ce qui se relit mieux en MR). Un clone lié démarre en quelques secondes et ne copie pas le disque ; en contrepartie le template ne peut pas être supprimé tant que le banc existe.

2. [`m18-k3s-ha.yml`](fichiers/M18-E07/ansible/inventories/lab/m18-k3s-ha.yml) (groupe `k3s_ha`, noms DDNS), [`group_vars/k3s_ha/k3s.yml`](fichiers/M18-E07/ansible/inventories/lab/group_vars/k3s_ha/k3s.yml), [`host_vars/k3s-ha01/k3s.yml`](fichiers/M18-E07/ansible/inventories/lab/host_vars/k3s-ha01/k3s.yml) (`k3s_cluster_init: true`, pas d'URL), playbook [`m18.yml`](fichiers/M18-E07/ansible/playbooks/m18.yml) (deux jeux pour `k3s_ha` : socle léger, puis `k3s` en `order: sorted`, `serial: 1`). La variable : **`k3s_gere_version: false`**. Le rôle installe toujours un k3s absent, mais ne relance pas le script si la version installée diffère de l'inventaire : sinon, après la montée par le contrôleur (1.36.5), le prochain passage d'Ansible réinstallerait 1.36.4 (le script ne refuse pas de redescendre).

3. Observation :
   ```
   admin@k3s-ha01:~$ sudo k3s kubectl get nodes
   NAME       STATUS   ROLES                       AGE   VERSION
   k3s-ha01   Ready    control-plane,etcd,master   9m    v1.36.4+k3s1
   k3s-ha02   Ready    control-plane,etcd,master   6m    v1.36.4+k3s1
   k3s-ha03   Ready    control-plane,etcd,master   3m    v1.36.4+k3s1
   admin@k3s-ha01:~$ sudo ls /var/lib/rancher/k3s/server/db/
   etcd  snapshots
   admin@k3s-ha01:~$ sudo k3s etcd-snapshot list
   ```
   Trois membres etcd (un par serveur), données dans `server/db/etcd/` ; plus de `state.db` : c'est etcd, pas SQLite. Trois nœuds de contrôle, sans taint par défaut (ils acceptent les charges : à l'agence, sur trois petites machines, c'est voulu). Kubeconfig : même méthode qu'en E03 (`127.0.0.1` → `k3s-ha01.par1.medisphere.internal`, contexte `k3s-ha`).

4. Perte de serveurs :
   ```
   root@pve01:~# qm shutdown 5193
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/k3s-ha.kubeconfig get nodes     # répond ; k3s-ha03 NotReady après ≈ 40 s
   root@pve01:~# qm shutdown 5192
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/k3s-ha.kubeconfig get nodes     # délai dépassé, ou « etcdserver: request timed out »
   root@pve01:~# qm start 5192 && qm start 5193
   ```
   Un membre perdu : quorum 2/3, tout fonctionne. Deux perdus : `k3s-ha01` reste seul, etcd refuse les lectures linéarisables et les écritures, le kube-apiserver de `k3s-ha01` ne répond plus utilement. Les pods déjà lancés continuent de tourner.

5. [`k3s/suc/`](fichiers/M18-E07/distributions/k3s/suc/) : `kustomization.yaml` (deux URL de la version v0.20.2 + `plan-serveurs.yaml`), plan `serveurs` (`version: v1.36.5+k3s1`, `concurrency: 1`, `cordon: true`, sélecteur `node-role.kubernetes.io/control-plane In ["true"]`, `serviceAccountName: system-upgrade`, `upgrade.image: rancher/k3s-upgrade`, fenêtre en semaine 9 h-17 h, `Europe/Paris`).
   ```
   admin@adm01:~/src/distributions$ kubectl --kubeconfig ~/.config/workbook/m18/k3s-ha.kubeconfig apply -k k3s/suc/
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/k3s-ha.kubeconfig -n system-upgrade get plans -o wide
   NAME       IMAGE                 CHANNEL   VERSION        COMPLETE   MESSAGE   APPLYING
   serveurs   rancher/k3s-upgrade             v1.36.5+k3s1   False                ["k3s-ha01"]
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/k3s-ha.kubeconfig get nodes -w
   k3s-ha01   Ready,SchedulingDisabled   control-plane,etcd,master   25m   v1.36.4+k3s1
   k3s-ha01   Ready                      control-plane,etcd,master   26m   v1.36.5+k3s1
   …
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/m18.yml --limit k3s_ha --diff    # changed=0
   ```
   Le contrôleur crée un Job par nœud (`apply-serveurs-on-k3s-ha01-with-…`), qui isole le nœud, remplace `/usr/local/bin/k3s` sur l'hôte (montage de `/` en `/host`), redémarre le service, rend le nœud, et pose l'étiquette `plan.upgrade.cattle.io/serveurs=<empreinte>` ; puis passe au suivant.

6. [`k3s.md`](fichiers/M18-E07/medisphere/docs/kubernetes/distributions/k3s.md) (section HA) ; mesures : ≈ 6 min pour le banc (VMs + playbook), ≈ 2 min par nœud pour la montée. Puis :
   ```
   admin@adm01:~/src/infra/envs/m18$ tofu apply -var 'k3s_ha_noeuds=[]'
   admin@adm01:~$ rm ~/.config/workbook/m18/k3s-ha.kubeconfig
   ```

**Explications**

etcd intégré fait de k3s une distribution HA sans base externe : chaque serveur est un membre etcd, et k3s gère l'adhésion (le premier en `cluster-init`, les suivants par l'API du premier, avec le jeton). La différence avec SQLite n'est pas que la redondance : etcd coûte plus de mémoire et d'E/S, et exige un nombre impair de serveurs. Le *system-upgrade-controller* transforme une montée de version en objet : un plan dit **quoi** (version), **où** (sélecteur de nœuds), **comment** (concurrence, isolement, drain éventuel) et **quand** (fenêtre). C'est ce qui permet à une agence sans équipe de se mettre à jour la nuit.

**Alternatives**

- **Canal** (`channel: https://update.k3s.io/v1-release/channels/stable`) au lieu de `version` : mise à jour sans MR dès que le canal bouge ; pratique, mais une montée non relue arrive un jour de mauvaise surprise. Chez MédiSphère : version explicite.
- **Base externe** (PostgreSQL par kine) : deux serveurs suffisent, mais la base devient le point unique et à sauvegarder.
- **Un serveur + agents** : moins de mémoire, aucune HA du plan de contrôle.
- **vm-noeud étendu** aux VMID 5000-5999 : écart à la règle du module (`vm-noeud` est pour les VMs d'environnement, dans NetBox) ; une ressource jetable dédiée est plus honnête.

**Pièges classiques**

- Démarrer les trois serveurs en parallèle : deux d'entre eux tentent de joindre un etcd qui n'existe pas encore.
- Mettre `cluster-init: true` sur les trois : trois clusters etcd séparés.
- Plan avec `drain: {force: true}` copié d'un exemple : évince les pods sans respecter les PDB.
- Oublier `k3s_gere_version: false` : Ansible et le contrôleur se battent, le nœud monte, redescend, remonte.
- Fenêtre en UTC lue comme une heure de Paris : rien ne se passe pendant deux heures.
- Détruire le banc avant `lab/bin/check 18 07`.

**En production chez MédiSphère**

À Lyon, trois petites machines : une VIP (kube-vip) devant 6443, la fenêtre la nuit, un instantané etcd envoyé vers PAR1 avant la fenêtre, une alerte si un plan reste incomplet ou un nœud isolé au matin (M21), et la version du plan relue en MR comme toute autre.

---

### M18-E08 — Cluster API : concepts et cluster de gestion

**Solution**

*1. Concepts.* Le graphe des objets (section de [`cluster-api.md`](fichiers/M18-E10/medisphere/docs/kubernetes/distributions/cluster-api.md)) :

```
Cluster ──infrastructureRef──► ProxmoxCluster (VIP, adresses, identifiants) ──► InClusterIPPool <cluster>-v4-icip
   └──controlPlaneRef──► KubeadmControlPlane ──crée──► Machine (×N, contrôle)
                              │ machineTemplate.infrastructureRef        ├──► ProxmoxMachine (clone d'un ProxmoxMachineTemplate) ──► VM Proxmox
                              └ kubeadmConfigSpec                        └──► KubeadmConfig ──► Secret de données cloud-init
MachineDeployment ──crée──► MachineSet ──crée──► Machine (travailleurs) ──► ProxmoxMachine + KubeadmConfig (KubeadmConfigTemplate)
ClusterResourceSet ──(clusterSelector)──► applique des ConfigMap/Secret dans le cluster créé
```
Le cœur (`capi-controller-manager`) gère Cluster, Machine, MachineSet, MachineDeployment, ClusterResourceSet ; le fournisseur d'amorçage kubeadm transforme un `KubeadmConfig` en données cloud-init ; le fournisseur de plan de contrôle kubeadm gère le `KubeadmControlPlane` (et parle à l'API et à etcd du cluster créé) ; CAPMOX crée les VMs ; l'IPAM in-cluster attribue les adresses demandées par CAPMOX (objets `IPAddressClaim` → `IPAddress`). `clusterctl generate provider --infrastructure proxmox:v0.9.1 --describe` montre les CRD, l'espace `capmox-system`, et les variables du gabarit (`PROXMOX_URL`, `PROXMOX_TOKEN`, `PROXMOX_SECRET` avec une valeur par défaut vide).

*2. Le compte.* [`capi/pve-compte-capi.sh`](fichiers/M18-E08/distributions/capi/pve-compte-capi.sh). La liste de `WBCapi`, privilège par privilège, est commentée dans le script ; ce qui manque volontairement par rapport à `PVEVMAdmin` : `VM.Console`, `VM.Backup`, `VM.Migrate`, `VM.Snapshot*`, `VM.Replicate`, `VM.GuestAgent.FileRead/FileWrite/FileSystemMgmt`. `pveum role add` refusant tout privilège inconnu, la création du rôle est déjà un test : avec `VM.Monitor` (droits d'exemples anciens), Proxmox VE 9 répond par une erreur.
```
root@pve01:~# bash pve-compte-capi.sh
>>> Secret du jeton ci-dessous (« value ») : copie-le MAINTENANT dans ~/.config/workbook/pve-capi.env sur adm01.
┌──────────────┬──────────────────────────────────────┐
│ key          │ value                                │
╞══════════════╪══════════════════════════════════════╡
│ full-tokenid │ wb-capi@pve!capi                     │
│ value        │ xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx │
└──────────────┴──────────────────────────────────────┘
== droits effectifs du jeton sur /pool/lab
…
admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/pve-capi.env && editor ~/.config/workbook/pve-capi.env
PROXMOX_URL=https://<IP-PVE01>:8006
PROXMOX_TOKEN=wb-capi@pve!capi
PROXMOX_SECRET=<SECRET>
admin@adm01:~$ scp -p ~/.config/workbook/pve-capi.env ~/.config/workbook/pve-packer.env m18-dev01:.config/workbook/
```
(Sur `m18-dev01`, crée d'abord `~/.config/workbook` en 700.) Le stockage dédié `capi-iso` est la seule entrée « iso » que le jeton voit : CAPMOX (go-proxmox, `StorageISO`) y déposera ses ISO. Sans lui, il prendrait le premier stockage `iso` visible (`hdd-bulk`, ou `local`) et il faudrait lui donner `Datastore.Allocate` sur un stockage partagé avec nos ISO et nos sauvegardes.

*3. Les flux.* [Extrait de la matrice de la bordure](fichiers/M18-E08/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [lignes de `matrice-flux.md`](fichiers/M18-E08/medisphere/docs/socle/matrice-flux.md.extrait). Sur `pve01`, méthode de M03-E15 :
```
root@pve01:~# pvesh create /cluster/firewall/ipset --name capi --comment "Clusters de gestion Cluster API (M18-E08)"
root@pve01:~# pvesh create /cluster/firewall/ipset/capi --cidr <IP-M18-DEV01> --comment m18-dev01
root@pve01:~# pvesh create /cluster/firewall/ipset/capi --cidr <IP-K3S01> --comment k3s01
root@pve01:~# pvesh create /cluster/firewall/rules --type in --action ACCEPT --source +capi --proto tcp --dport 8006 --enable 1 --comment "API pour CAPMOX et image-builder (M18-E08)"
root@pve01:~# pve-firewall compile | grep -n capi
```
L'ancre de `pve01` est déposée sur `m18-dev01` et `k3s01` par le dernier jeu du playbook ([`m18.yml`](fichiers/M18-E08/ansible/playbooks/m18.yml)).

*4. La vérification préalable.* [`capi/preflight-pve.sh`](fichiers/M18-E08/distributions/capi/preflight-pve.sh) : en-tête d'authentification dans un fichier 600 (`curl -H @fichier`), TLS vérifié par le magasin du système, arrêt à la première erreur, et un nettoyage qui ne supprime **que** ce que le script a créé (drapeaux `CLONE_CREE`, `ISO_CREEE`, refus si 5189 existe).
```
admin@m18-dev01:~/src/distributions$ NOEUD=<NOEUD> capi/preflight-pve.sh
== Version de Proxmox VE (TLS vérifié, jeton accepté)
Proxmox VE 9.2.x (9.2)
== Ressources visibles par le jeton (pool lab seulement)
…
== Stockages visibles : CAPMOX téléverse dans le PREMIER stockage « iso » qu'il voit
capi-iso
== Téléversement puis suppression d'une ISO dans capi-iso (Datastore.AllocateTemplate)
== Clonage complet du template 9000 vers 5189 dans le pool lab (VM.Clone, VM.Allocate, AllocateSpace)
…
Vérification préalable : tous les appels ont réussi avec le jeton wb-capi@pve!capi.
```
Ce que le script ne couvre pas : l'agent QEMU et l'exécution de `cloud-init status` (il faudrait une VM démarrée avec l'agent) ; ils sont vérifiés à la première machine de E10, dernière ligne du tableau de `capmox-pve9.md`.

*5. Le cluster de gestion.* [`kind/gestion.yaml`](fichiers/M18-E08/distributions/kind/gestion.yaml) (`apiServerAddress: "0.0.0.0"`, `apiServerPort: 6443`, `certSANs` par `kubeadmConfigPatches`).
```
admin@m18-dev01:~$ kind create cluster --config ~/src/distributions/kind/gestion.yaml
admin@adm01:~$ ssh m18-dev01 kind get kubeconfig --name gestion \
    | sed 's#https://0.0.0.0:6443#https://m18-dev01.par1.medisphere.internal:6443#' \
    | install -m 600 /dev/stdin ~/.config/workbook/m18/kind-gestion.kubeconfig
admin@adm01:~/src/distributions$ capi/init.sh ~/.config/workbook/m18/kind-gestion.kubeconfig proxmox
Fetching providers
Installing cert-manager version="v1.19.x"
Waiting for cert-manager to be available...
Installing provider="cluster-api" version="v1.12.11" targetNamespace="capi-system"
Installing provider="bootstrap-kubeadm" version="v1.12.11" targetNamespace="capi-kubeadm-bootstrap-system"
Installing provider="control-plane-kubeadm" version="v1.12.11" targetNamespace="capi-kubeadm-control-plane-system"
Installing provider="infrastructure-proxmox" version="v0.9.1" targetNamespace="capmox-system"
Installing provider="ipam-in-cluster" version="v1.1.1" targetNamespace="capi-ipam-in-cluster-system"
NAMESPACE                           NAME                    AGE   TYPE                     PROVIDER      VERSION
capi-ipam-in-cluster-system         ipam-in-cluster         …     IPAMProvider             in-cluster    v1.1.1
capi-kubeadm-bootstrap-system       bootstrap-kubeadm       …     BootstrapProvider        kubeadm       v1.12.11
capi-kubeadm-control-plane-system   control-plane-kubeadm   …     ControlPlaneProvider     kubeadm       v1.12.11
capi-system                         cluster-api             …     CoreProvider             cluster-api   v1.12.11
capmox-system                       infrastructure-proxmox  …     InfrastructureProvider   proxmox       v0.9.1
```
(La version de cert-manager est celle que choisit clusterctl 1.12.11.) Le Secret `capmox-manager-credentials` a trois clés `url`, `token`, `secret`, **vides** ; le déploiement les lit en variables `PROXMOX_*` ; vides, CAPMOX démarre sans client global (`setupProxmoxClient` rend `nil`). Si tu avais exporté les variables avant `clusterctl init`, le jeton serait dans ce Secret, utilisable par **tout** cluster décrit dans le cluster de gestion, et le client global tournerait avec `PROXMOX_INSECURE=true` par défaut : **sans vérification TLS** (il faudrait `--proxmox-root-cert-file` et `PROXMOX_INSECURE=false`).

*6. La conclusion.* [`capmox-pve9.md`](fichiers/M18-E08/medisphere/docs/kubernetes/distributions/capmox-pve9.md), et le repli prêt : [`kind/gestion-capd.yaml`](fichiers/M18-E08/distributions/kind/gestion-capd.yaml) et `capi/init.sh … docker`.

**Explications**

Cluster API applique au cycle de vie des clusters la logique des contrôleurs de Kubernetes. Le cluster de gestion est un cluster comme un autre : c'est ce qui le rend à la fois simple (on l'amorce avec kind) et précieux (il porte la description et les identifiants). La vérification préalable n'est pas de la prudence excessive : la documentation de CAPMOX ne dit rien de Proxmox VE 9, dont le modèle de privilèges a changé ; rejouer **avec le jeton réel** les appels que fera le contrôleur transforme une incertitude en résultat, en dix minutes, sans rien casser.

**Alternatives**

- `PVEVMAdmin` sur `/pool/lab` (suggestion de démarrage de CAPMOX) : plus simple, mais ouvre console, sauvegarde, instantanés et migration de toutes les VMs du pool, socle compris.
- Un pool `capi` dédié (proposé par la documentation de CAPMOX, déjà envisagé au M03) : limiterait le jeton aux VMs de Cluster API et aux templates ; écart au pool unique `lab` de PLAN §4.3 bis, à proposer dans l'ADR-0180.
- Identifiants globaux dans `clusterctl.yaml` : un cluster de gestion à un seul « locataire » ; plus simple, moins sûr, et à recopier à chaque pivot.
- Cluster de gestion d'amorçage directement sur `k3s01` : possible, mais montrer le pivot est le but de E12.

**Pièges classiques**

- `clusterctl init --infrastructure proxmox` sans version : CAPI 1.14 et une version de CAPMOX qui ne le supporte pas (« missing MachineDeployment strategy », webhooks introuvables : page de dépannage de CAPMOX).
- Limite de l'API GitHub (60 requêtes par heure sans authentification) quand on rejoue `clusterctl init` : un jeton GitHub en lecture (`GITHUB_TOKEN`) dans l'environnement, jamais dans un dépôt.
- `kind` exposé sur `0.0.0.0` sans le nom dans `certSANs` : le kubeconfig de `adm01` échoue sur le certificat, et la tentation de `insecure-skip-tls-verify` revient.
- IPSet avec la mauvaise adresse (bail Kea changé) : `preflight-pve.sh` reste bloqué sans réponse (délai dépassé, pas un refus).
- Oublier l'ACL sur le **jeton** (séparation des privilèges) : l'utilisateur a les droits, le jeton n'en a aucun (intersection).

**En production chez MédiSphère**

Un compte et un jeton par cluster de gestion, expirant, renouvelés par procédure ; un pool dédié aux VMs de Cluster API ; le stockage `capi-iso` purgé des ISO orphelines ; la vérification préalable rejouée à chaque montée de version de Proxmox ou de CAPMOX (dans la CI, contre un environnement de recette) ; une veille sur les tickets de CAPMOX.

---

### M18-E09 — Une image de nœud pour Cluster API

**Solution**

1. L'ISO, téléchargée par `pve01` lui-même, empreinte vérifiée :
   ```
   root@pve01:~# pvesh create /nodes/<NOEUD>/storage/hdd-bulk/download-url --content iso \
       --filename ubuntu-24.04.4-live-server-amd64.iso \
       --url https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso \
       --checksum e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433 --checksum-algorithm sha256
   ```

2. Lecture du gabarit : le nom vient de `artifact_name` (défaut `<build_name>-kube-<kubernetes_semver>`), le VMID de `vmid` (vide par défaut : prochain libre) ; les versions de Kubernetes de `packer/config/kubernetes.json` (1.36.1 par défaut en v0.1.55) ; `builders[0]` contient `"insecure_skip_tls_verify": true` **en dur** et aucune option `pool` : avec le jeton `wb-packer` (`VM.Allocate` sur `/pool/lab` seulement), la création de la VM de build sans pool est refusée (« Permission check failed (/vms/…, VM.Allocate) »).

3. [`capi/ubuntu-2404-k136.json`](fichiers/M18-E09/images/capi/ubuntu-2404-k136.json) (VMID 9060, nom, `kubernetes_series` v1.36, `kubernetes_semver` v1.36.4, `kubernetes_deb_version` 1.36.4-1.1, `disk_format` raw, ISO déposée `iso_file`, `iso_url` vide) et [`capi/construire.sh`](fichiers/M18-E09/images/capi/construire.sh) : clone à l'étiquette (vérifiée par `git describe --exact-match`), remise à zéro du gabarit puis trois corrections par `jq` (TLS vérifié, `pool: lab`, `tags`), `git diff` affiché, identifiants lus dans `pve-packer.env` et passés en variables d'environnement à image-builder (convention inverse de CAPMOX), `PACKER_VAR_FILES`, `make`.

4. Construction :
   ```
   admin@m18-dev01:~/src/images$ NOEUD=<NOEUD> capi/construire.sh --valider
   admin@m18-dev01:~/src/images$ NOEUD=<NOEUD> capi/construire.sh 2>&1 | tee ~/m18/e09/build.log
   ==> proxmox-iso.ubuntu-2404: Creating VM
   ==> proxmox-iso.ubuntu-2404: Starting HTTP server on port 8xxx
   ==> proxmox-iso.ubuntu-2404: Typing the boot command
   ==> proxmox-iso.ubuntu-2404: Waiting for SSH to become available...
   ==> proxmox-iso.ubuntu-2404: Provisioning with Ansible...
   …
   ==> proxmox-iso.ubuntu-2404: Converting VM to template
   Build 'proxmox-iso.ubuntu-2404' finished after 31 minutes.
   ```

5. Contrôle :
   ```
   root@pve01:~# qm config 9060 | grep -E 'name|agent|scsi0|tags|template'
   agent: 1
   name: tpl-capi-ubuntu2404-k136
   scsi0: local-nvme:base-9060-disk-0,size=20G
   tags: capi;k8s-v1.36.4
   template: 1
   root@pve01:~# pvesh get /pools/lab --output-format json | jq '.members[] | select(.vmid == 9060) | .name'
   root@pve01:~# qm clone 9060 5188 --name m18-essai-image --pool lab && qm set 5188 --net0 virtio,bridge=vsandbox --ipconfig0 ip=dhcp --sshkeys ~/adm01.pub && qm start 5188
   admin@adm01:~$ ssh ubuntu@<IP-5188> 'kubeadm version -o short; kubelet --version; crictl --version; sudo ls /home'
   root@pve01:~# qm stop 5188 && qm destroy 5188 --purge
   ```
   (Le compte par défaut de l'image cloud-init d'image-builder pour Ubuntu est `ubuntu` ; le compte de build `builder` doit avoir disparu de `/home` et de `/etc/passwd` : image-builder le supprime à la fin.) Le clone en `local-nvme` (clone lié, VM jetable) se fait ici à la main, en root, une fois : c'est un contrôle, pas un environnement.

6. `current` :
   ```
   root@pve01:~# qm set 9060 --tags 'capi;current;k8s-v1.36.4'
   ```
   et [`image-noeud.md`](fichiers/M18-E09/medisphere/docs/kubernetes/distributions/image-noeud.md).

**Explications**

image-builder est un assemblage Packer (créer la VM, installer l'OS, convertir en template) + Ansible (rôles `containerd`, `kubernetes`, `sysprep`…) maintenu par le projet Cluster API. Il garantit que le template contient exactement ce que kubeadm attend à une version donnée, images du plan de contrôle préchargées (le nœud démarre sans dépendre des registres). Le travail d'intégration est celui du M03 : un compte à droits minimaux, une ISO déposée, la vérification TLS, une étiquette `current` posée après contrôle. Ne pas *forker* l'outil (corrections locales, affichées, rejouées à chaque construction) permet de suivre ses versions.

**Alternatives**

- **Image cloud Ubuntu + script** (sans image-builder) : un `cloud-init` qui installe containerd et kubeadm au premier démarrage : plus simple, mais chaque nœud télécharge et configure à sa création (lent, dépend d'Internet, non reproductible).
- **Flatcar** (image-builder sait le faire, CAPMOX a un gabarit) : OS immuable pour nœuds Cluster API, à rapprocher de Talos.
- **CAPI + Talos** (fournisseurs d'amorçage et de plan de contrôle `talos`, listés par `clusterctl config repositories`) : plus de template Ubuntu à construire, l'image Talos suffit.
- **Construction en CI** sur `runner01` (comme les images dorées, M03-E15) : le chemin cible ; ici sur `m18-dev01` parce que l'essai ne justifie pas encore un pipeline.

**Pièges classiques**

- `PROXMOX_TOKEN` rempli avec l'identifiant du jeton (convention de CAPMOX) : authentification refusée.
- Disque `qcow2` (défaut) sur un stockage bloc : erreur de création du disque.
- `kubernetes_semver` changé sans `kubernetes_deb_version` : les paquets installés ne sont pas ceux du nom du template.
- Un deuxième template étiqueté `capi;current` : une sélection par étiquettes (`templateSelector`) devient ambiguë et CAPMOX refuse de provisionner.
- Laisser tourner la VM d'essai 5188 (elle est dans la plage du module, mais pas dans le plan).
- `--on-error=ask` d'image-builder dans une session non interactive : le build attend une réponse.

**En production chez MédiSphère**

Pipeline dans `plateforme/images` (job manuel par version de Kubernetes, sur `runner01`), test automatique du template (clone, démarrage, `kubeadm` et `kubelet` aux bonnes versions, scan des paquets), signature des métadonnées de construction (manifeste Packer), politique de rétention N/N-1, et reconstruction mensuelle pour les correctifs de l'OS.

---

### M18-E10 — CAPMOX : un cluster de charge de travail sur Proxmox

**Solution**

1. Gabarit puis fichiers. `clusterctl generate cluster capi-essai --infrastructure proxmox:v0.9.1 --kubernetes-version v1.36.4 --control-plane-machine-count 1 --worker-machine-count 2 --list-variables` liste `CONTROL_PLANE_ENDPOINT_IP`, `NODE_IP_RANGES`, `GATEWAY`, `IP_PREFIX`, `DNS_SERVERS`, `BRIDGE`, `PROXMOX_SOURCENODE`, `TEMPLATE_VMID`, `VM_SSH_KEYS`, `BOOT_VOLUME_DEVICE`… Le gabarit sert de modèle ; les fichiers réécrits ([`capi/capi-essai/`](fichiers/M18-E10/distributions/capi/capi-essai/)) changent : pods en `10.244.0.0/16` (le gabarit dit `192.168.0.0/16`), `credentialsRef`, `allowedNodes`, `vmIDRange`, `pool`, `tags`, `storage`, **pas** de `format: qcow2`, NTP, compte `admin` (le gabarit crée `root`), racine et miroirs, kube-vip `v1.2.4` (le gabarit : `v0.7.1`) avec son correctif `super-admin.conf` gardé et un retour à `admin.conf` après l'init.
   ```
   admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/kind-gestion.kubeconfig
   admin@adm01:~$ kubectl explain proxmoxmachinetemplate.spec.template.spec.vmIDRange
   admin@adm01:~/src/distributions$ kubectl apply --dry-run=server -f capi/capi-essai/00-espace.yaml && kubectl create namespace capi-essai
   admin@adm01:~/src/distributions$ kubectl apply --dry-run=server -f capi/capi-essai/
   ```

2. Identifiants et CNI :
   ```
   admin@adm01:~/src/distributions$ capi/identifiants.sh ~/.config/workbook/m18/kind-gestion.kubeconfig
   NAME                 TYPE     DATA   AGE
   capi-essai-proxmox   Opaque   5      1s
   medisphere-root-ca   Opaque   1      1s
   admin@adm01:~/src/distributions$ capi/cilium/generer-crs.sh | kubectl apply --server-side -f -
   ```
   [`identifiants.sh`](fichiers/M18-E10/distributions/capi/identifiants.sh) construit le Secret par `jq` (valeurs lues dans `pve-capi.env` et `pve-root-ca.pem`, jamais sur la ligne de commande) : `insecure: "false"`, `root_ca`, étiquettes `platform.ionos.com/secret-type` et `clusterctl.cluster.x-k8s.io/move`. [`generer-crs.sh`](fichiers/M18-E10/distributions/capi/cilium/generer-crs.sh) rend Cilium 1.20.2 avec [`values.yaml`](fichiers/M18-E10/distributions/capi/cilium/values.yaml) (API par la VIP) et l'emballe dans le ConfigMap `cilium` ; `--server-side` parce que le manifeste dépasse les 256 Kio de l'annotation d'un `apply` classique.

3. Création :
   ```
   admin@adm01:~/src/distributions$ kubectl apply -f capi/capi-essai/
   admin@adm01:~$ kubectl -n capi-essai get inclusterippools,ipaddressclaims,ipaddresses
   NAME                                                         ADDRESSES                       TOTAL   FREE   USED
   inclusterippool.ipam.cluster.x-k8s.io/capi-essai-v4-icip     ["10.10.40.150-10.10.40.169"]   20      19     1
   admin@adm01:~$ clusterctl describe cluster capi-essai -n capi-essai
   NAME                                                          REPLICAS  AVAILABLE  READY  UP TO DATE  AGE
   Cluster/capi-essai                                            3/3       3          3      3           12m
   ├─ClusterInfrastructure - ProxmoxCluster/capi-essai
   ├─ControlPlane - KubeadmControlPlane/capi-essai-plan-controle 1/1       1          1      1           12m
   │ └─Machine/capi-essai-plan-controle-xxxxx                    1         1          1      1           12m
   └─Workers
     └─MachineDeployment/capi-essai-travailleurs                 2/2       2          2      2           12m
       └─2 Machines...
   root@pve01:~# qm list | awk '$1 >= 5180 && $1 <= 5189'
         5180 capi-essai-plan-controle-xxxxx running    4096   32.00 …
         5181 capi-essai-travailleurs-xxxxx-yyyyy running 4096 32.00 …
         5182 capi-essai-travailleurs-xxxxx-zzzzz running 4096 32.00 …
   ```
   Ordre observé : `IPAddressClaim` (adresse réservée) → clone du template en 5180 (tâche `qmclone`) → redimensionnement du disque, CPU, mémoire, carte `vk8s`, étiquettes → ISO `user-data-5180.iso` téléversée dans `capi-iso` et montée en `ide0` → démarrage → attente de l'agent QEMU → `cloud-init status` par l'agent → cloud-init joue `preKubeadmCommands`, `kubeadm init` ; kube-vip (avec `super-admin.conf`) prend la VIP 10.10.40.210 → le contrôleur du plan de contrôle joint l'API par la VIP → les travailleurs sont créés (5181, 5182) et joignent → le CRS applique Cilium → nœuds `Ready`. CAPMOX démonte ensuite l'ISO.

4. Accès :
   ```
   admin@adm01:~$ clusterctl get kubeconfig capi-essai -n capi-essai | install -m 600 /dev/stdin ~/.config/workbook/m18/capi-essai.kubeconfig
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/capi-essai.kubeconfig get nodes -o wide
   NAME                                   STATUS   ROLES           AGE   VERSION   INTERNAL-IP
   capi-essai-plan-controle-xxxxx         Ready    control-plane   11m   v1.36.4   10.10.40.150
   capi-essai-travailleurs-xxxxx-yyyyy    Ready    <none>          8m    v1.36.4   10.10.40.151
   capi-essai-travailleurs-xxxxx-zzzzz    Ready    <none>          8m    v1.36.4   10.10.40.152
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/capi-essai.kubeconfig -n kube-system rollout status ds/cilium
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/kind-gestion.kubeconfig -n capi-essai get clusterresourcesetbindings
   ```

5. Dans Proxmox : noms = noms des `Machine`, étiquettes `capi`, `k8s-v1.36.4` (héritées du template, `current` comprise : à savoir), `env-m18`, `capi-essai` (posées par CAPMOX), description vide (sauf `description:`), disque brut 32 Gio sur `local-nvme`. Une VM arrêtée dans l'interface : le nœud passe `NotReady`, la `Machine` reste `Running` côté CAPI (CAPMOX ne redémarre pas une VM arrêtée, et sans `MachineHealthCheck`, personne ne remplace la machine ; palier 3) : c'est la règle 5 du module, on n'agit pas dans Proxmox.

6. [`cluster-api.md`](fichiers/M18-E10/medisphere/docs/kubernetes/distributions/cluster-api.md) ; mesures : ≈ 10 à 15 min de `kubectl apply` à trois nœuds `Ready` (clone complet des disques, démarrage, cloud-init) : surtout le clone (copie de 20 Gio sur `local-nvme`) et le tirage des images de Cilium.

**Repli CAPD** (si E08 a conclu ainsi) : `kind/gestion-capd.yaml`, `capi/init.sh <kubeconfig> docker`, puis `clusterctl generate cluster capi-essai --flavor development --infrastructure docker:v1.12.11 --kubernetes-version v1.36.4 --control-plane-machine-count 1 --worker-machine-count 2 > capi-essai-capd.yaml` (gabarit ClusterClass : `CLUSTER_TOPOLOGY=true`) ; même suivi (`clusterctl describe`), les « machines » sont des conteneurs `capi-essai-*` sur `m18-dev01` ; Cilium par le même ConfigMap avec `k8sServiceHost` adapté (adresse du répartiteur de CAPD). Le check signale les contrôles Proxmox non applicables.

**Explications**

Trois mécanismes à retenir. **Les identifiants par cluster** (`credentialsRef`) : le contrôleur n'a aucun droit par lui-même ; chaque cluster apporte un Secret dans son espace, ce qui permet plusieurs comptes ou plusieurs Proxmox, et fait suivre les identifiants lors d'un pivot. **Les adresses** : CAPMOX n'utilise pas le DHCP ; il demande une adresse au réservoir qu'il a créé depuis `ipv4Config` et l'écrit dans la configuration réseau cloud-init de la VM ; la VIP, elle, n'est dans aucun réservoir : c'est kube-vip, sur le nœud de contrôle, qui la porte par ARP. **Le correctif kube-vip** : depuis Kubernetes 1.29, `admin.conf` appartient au groupe `kubeadm:cluster-admins`, lié aux droits seulement **après** le démarrage de l'API ; pendant `kubeadm init`, kube-vip avec `admin.conf` ne peut lire ni écrire son bail, ne prend pas la VIP, et kubeadm attend une API qu'il joint… par la VIP. D'où `super-admin.conf` (`system:masters`) le temps de l'init.

**Alternatives**

- **ClusterClass** (`templates/cluster-class-cilium.yaml` de CAPMOX, `CLUSTER_TOPOLOGY=true`) : un cluster devient un objet court (`topology`), les variantes sont centralisées ; idéal pour « un cluster par équipe » (palier 3, E18), plus abstrait pour apprendre.
- **`templateSelector`** au lieu de `templateID` : le template est choisi par étiquettes (`matchPolicy: exact|uniqueSubset|bestSubset`) ; souple pour les montées de version, ambigu si deux templates correspondent.
- **CNI par le fournisseur d'extensions Helm** de CAPI (`HelmChartProxy`) : Cilium réconcilié et monté de version depuis le cluster de gestion ; un fournisseur de plus.
- **IPAM global** (`GlobalInClusterIPPool`) partagé par plusieurs clusters : une seule plage pour toute la recette.

**Pièges classiques**

- Secret sans `insecure` : CAPMOX fonctionne… sans vérifier le certificat. Rien ne le signale.
- `KubeadmControlPlane.version` différente du Kubernetes du template : kubeadm échoue (binaires absents) et la machine boucle.
- VIP dans la plage des nœuds : un nœud reçoit l'adresse de la VIP.
- Pas de `pool: lab` : clone refusé (`VM.Allocate`), la `ProxmoxMachine` reste en erreur de permission.
- ConfigMap du CRS trop gros pour `kubectl apply` classique ; ou CRS dont le sélecteur ne correspond pas à l'étiquette du `Cluster` : nœuds `NotReady` pour toujours.
- `kubectl delete -f capi/capi-essai/` pour nettoyer : supprime les objets dans le désordre (le `ProxmoxCluster` avant les machines) et peut laisser des VMs ; on supprime le `Cluster`, CAPI fait le reste.
- Modifier un `ProxmoxMachineTemplate` en place : interdit (immuable par webhook) ; on en crée un nouveau.

**En production chez MédiSphère**

ClusterClass `medisphere-recette` (palier 3), trois nœuds de contrôle, `MachineHealthCheck`, un pool et un VLAN dédiés aux clusters de recette, la VIP et les plages déclarées dans NetBox, des quotas (nombre de clusters par équipe, VMID), le kubeconfig administrateur remplacé par OIDC (M24), et la destruction automatique des clusters de recette le soir (E18).

---

### M18-E11 — Revue : les manifestes Cluster API du stagiaire

**Solution**

1. Validation par l'API (espace d'essai, cluster de gestion) :
   ```
   admin@adm01:~/m18/e11$ sed 's/namespace: recette-agenda/namespace: revue-essai/' ressources/E11-capi-stagiaire/*.yaml > tout.yaml
   admin@adm01:~/m18/e11$ kubectl --kubeconfig ~/.config/workbook/m18/kind-gestion.kubeconfig create namespace revue-essai
   admin@adm01:~/m18/e11$ kubectl --kubeconfig ~/.config/workbook/m18/kind-gestion.kubeconfig apply --dry-run=server -f tout.yaml
   The ProxmoxMachineTemplate "recette-agenda-control-plane" is invalid: spec.template.spec.templateSelector.matchPolicy:
   Unsupported value: "subset": supported values: "exact", "uniqueSubset", "bestSubset"
   ```
   L'API voit ce que `--dry-run=client` ignore : les schémas des CRD (`matchPolicy`), les règles CEL (par exemple `full` obligatoire avec `format`), les webhooks de CAPI et CAPMOX. Elle ne voit pas les incohérences avec le plan (adresses, VMID, VNet, version de l'image), ni la sécurité (secret dans le dépôt, root, TLS).

2. La revue : [`capi/revue-lucas/REVUE.md`](fichiers/M18-E11/distributions/capi/revue-lucas/REVUE.md), 23 défauts classés. Les trois qui empêchent de dormir : **le jeton `root@pam` en clair dans le dépôt** (à révoquer, branche à purger), **sans vérification TLS** (Secret sans `insecure: "false"`), et **la VIP dans la plage des nœuds de `capi-essai`** (collision d'adresses avec un cluster existant). Les autres bloquants : version 1.36.5 contre une image 1.36.4, plan de contrôle à deux nœuds.

3. Les manifestes corrigés : [`capi/revue-lucas/`](fichiers/M18-E11/distributions/capi/revue-lucas/) (`cluster.yaml`, `plan-controle.yaml`, `travailleurs.yaml`, `crs.yaml`, et [`identifiants.md`](fichiers/M18-E11/distributions/capi/revue-lucas/identifiants.md) à la place du Secret). Pour coexister avec `capi-essai` : adresses 10.10.40.170-179, VIP 10.10.40.211, même plage de VMID 5180-5189 (CAPMOX prend le premier VMID libre : dix VMs au plus pour les deux clusters), ConfigMap `cilium` dans l'espace `recette-agenda`, rendu avec `k8sServiceHost: 10.10.40.211`. Ils passent `kubectl apply --dry-run=server`.

4. Réponse à Lucas (modèle) :
   > Bonne idée de partir du gabarit et de tout mettre dans le code, et merci d'avoir séparé les fichiers par rôle : c'est lisible. Trois choses bloquent : le Secret ne doit jamais être dans le dépôt (le jeton `root@pam!capi` est désormais public : je l'ai révoqué, il faudra purger la branche) ; sans `insecure: "false"` et `root_ca`, CAPMOX envoie ce jeton sans vérifier le certificat de `pve01` ; et la VIP `.155` est dans la plage d'adresses de `capi-essai`, elle aurait été donnée à un nœud. Le reste est dans `REVUE.md`, du plus grave au moins grave.
   >
   > Pour tester la prochaine fois : `kubectl apply --dry-run=server` contre le cluster de gestion, dans un espace d'essai, voit les schémas et les webhooks ; `--dry-run=client` ne voit que le YAML. Et relis toujours le tableau des adresses et des VMID du module avant de choisir une valeur.

**Explications**

Une revue de manifestes Cluster API vérifie trois couches : ce que l'API refuse (schéma), ce qui ne marchera pas sans que l'API le sache (version contre image, sélecteurs, pool, stockage), et ce qui marchera en nous exposant (secrets, TLS, root, clés personnelles, adresses qui chevauchent). Les deux dernières couches sont le vrai travail de revue.

**Alternatives**

- Une CI sur `plateforme/distributions` : `kubeconform` avec les schémas des CRD installées (convertis comme à la rédaction de ce corrigé), Gitleaks, et un contrôle maison des plages (adresses, VMID) contre un fichier de référence.
- Des règles d'admission sur le cluster de gestion (Kyverno au M26) : interdire `insecure` absent, imposer `pool: lab`, une plage de VMID par espace.

**Pièges classiques**

- S'arrêter à ce que signale l'API.
- Corriger le Secret en retirant la valeur mais laisser le fichier (et l'historique).
- Changer la VIP sans changer la plage (ou l'inverse) : les deux clusters se chevauchent encore.
- Mettre `templateID` **et** `templateSelector` : le sélecteur est ignoré, ce qui trompe le lecteur.

**En production chez MédiSphère**

Les manifestes de clusters ne sont plus écrits à la main : un `Cluster` court par équipe à partir d'une ClusterClass relue, des variables validées (plages par équipe dans NetBox), Gitleaks bloquant en CI, et des jetons Proxmox par cluster de gestion.

---

### M18-E12 — Pivoter le cluster de gestion

**Solution**

1. État de départ : `clusterctl describe cluster capi-essai -n capi-essai` vert, `kubectl -n capi-essai get machines -o wide` (trois `Running`), `qm list` (5180-5182). Note les noms des machines.

2. Fournisseurs sur `k3s01` :
   ```
   admin@adm01:~/src/distributions$ capi/init.sh ~/.config/workbook/m18/k3s01.kubeconfig proxmox
   admin@adm01:~$ ssh k3s01 free -m | sed -n 2p      # ≈ 1,4 à 1,8 Go utilisés avec cert-manager et les cinq contrôleurs
   ```
   L'ancre de `pve01` est sur `k3s01` (playbook de E08) et son adresse est dans `M18_GESTION` et l'IPSet `capi` : CAPMOX y joindra `pve01` dès le déplacement.

3. Copie de sécurité dans `~/m18/e12/avant-pivot` (dossier 700) : `--to-directory` écrit **tous** les objets, Secrets en clair compris (identifiants Proxmox, autorités du cluster `capi-essai` : `capi-essai-ca`, `capi-essai-etcd`, `capi-essai-kubeconfig`…). Effacée à la fin, ou chiffrée (Vault `critique`) si on la garde.

4. Pivot ([`capi/pivot.sh`](fichiers/M18-E12/distributions/capi/pivot.sh)) :
   ```
   admin@adm01:~/src/distributions$ capi/pivot.sh --essai
   == Fournisseurs : source et cible doivent être identiques
   == Machines de la source : aucune en cours de création ou de suppression
   Performing move...
   Discovering Cluster API objects
   Moving Cluster API objects Clusters=1
   Moving Cluster API objects ClusterClasses=0
   Creating objects in the target cluster
   …
   admin@adm01:~/src/distributions$ capi/pivot.sh
   ```
   Sont déplacés : `Cluster`, `ProxmoxCluster`, `KubeadmControlPlane`, `MachineDeployment`, `MachineSet`, `Machine`, `ProxmoxMachine`, `KubeadmConfig`, les `*Template`, le réservoir `capi-essai-v4-icip`, `IPAddressClaim`/`IPAddress`, le `ClusterResourceSet` et sa liaison, les Secrets du cluster (autorités, kubeconfig, données d'amorçage), **et** `capi-essai-proxmox` (référence de propriété posée par CAPMOX) **et** `medisphere-root-ca` (étiquette `clusterctl.cluster.x-k8s.io/move` posée par `identifiants.sh` : sans elle, il resterait sur la source, et une machine créée après le pivot n'aurait pas son fichier). Le ConfigMap `cilium` porte aussi l'étiquette.

5. Vérification :
   ```
   admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/k3s01.kubeconfig
   admin@adm01:~$ clusterctl describe cluster capi-essai -n capi-essai
   admin@adm01:~$ kubectl -n capi-essai get machines -o wide            # mêmes noms qu'en 1
   root@pve01:~# qm list | awk '$1 >= 5180 && $1 <= 5189'               # mêmes VMID, uptime inchangé
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/capi-essai.kubeconfig get nodes
   admin@adm01:~$ kubectl -n capi-essai scale machinedeployment capi-essai-travailleurs --replicas 3
   admin@adm01:~$ kubectl -n capi-essai get machines -w                 # une nouvelle machine, VMID 5183
   admin@adm01:~$ kubectl -n capi-essai scale machinedeployment capi-essai-travailleurs --replicas 2
   ```
   `capi-essai` ne voit rien : ses nœuds, son etcd et ses pods ne dépendent pas du cluster de gestion ; seuls la réparation, la mise à l'échelle et les montées de version en dépendent. La mise à l'échelle prouve que CAPMOX (sur `k3s01`) joint `pve01` avec le Secret déplacé, et que l'IPAM et le CRS ont suivi.

6. Retrait :
   ```
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/kind-gestion.kubeconfig -n capi-essai get all,secrets      # plus rien de capi-essai
   admin@m18-dev01:~$ kind delete cluster --name gestion
   admin@adm01:~$ rm ~/.config/workbook/m18/kind-gestion.kubeconfig && rm -rf ~/m18/e12/avant-pivot
   ```
   [`cluster-api.md`](fichiers/M18-E12/medisphere/docs/kubernetes/distributions/cluster-api.md) (section pivot et protection).

**Explications**

`clusterctl move` copie un graphe d'objets : il part des `Cluster` de l'espace, suit les références de propriété, ajoute les objets étiquetés « move », met le cluster en pause sur la source, recrée sur la cible **sans les `status`** (que les contrôleurs reconstruisent en observant l'infrastructure), puis supprime de la source en retirant les finaliseurs (sinon CAPMOX supprimerait les VMs). C'est pourquoi les fournisseurs doivent être identiques et le cluster stable : un objet en cours de création n'aurait pas d'état cohérent à reconstruire. Le cluster de charge de travail ne bouge pas : seul son « gardien » change.

**Alternatives**

- **Cluster de gestion auto-géré** : on pivote `capi-essai` dans lui-même (il se gère) ; plus de cluster dédié, mais une panne de `capi-essai` empêche sa propre réparation.
- **Cluster de gestion lui-même créé par Cluster API** (amorçage dans kind, création d'un cluster de gestion CAPMOX, pivot dedans) : le schéma complet du livre de CAPI ; une VM de plus.
- **Sauvegarde/restauration** par `--to-directory`/`--from-directory` : documentées comme ayant les mêmes limites que `move` (pas une stratégie de sauvegarde à part entière) ; la vraie sauvegarde est celle de la base de `k3s01` (palier 3).
- **Velero** sur le cluster de gestion (M16) : sauvegarde des objets, à condition de respecter l'ordre et la pause de CAPI à la restauration.

**Pièges classiques**

- Fournisseurs de la cible en version plus ancienne (ou installés sans `--ipam in-cluster`) : objets refusés ou non réconciliés.
- Pivot pendant une mise à l'échelle ou une montée de version : objets incohérents sur la cible.
- Secret sans référence de propriété ni étiquette « move » : resté sur la source, perdu au `kind delete`.
- `k3s01` qui ne joint pas `pve01` (IPSet, ancre TLS) : les machines restent `Running` mais toute nouvelle machine échoue ; le symptôme apparaît plus tard, à la première mise à l'échelle.
- `kind delete` avant d'avoir vérifié la cible : plus de retour arrière (sauf la copie de sécurité).
- Laisser la copie `--to-directory` en clair dans `~/m18/` ou `/tmp`.

**En production chez MédiSphère**

Un cluster de gestion dédié et redondant (trois nœuds, ou un k3s HA), sauvegardé (base + export chiffré des objets), supervisé (contrôleurs, conditions des clusters), accessible à l'équipe Plateforme seulement, avec des jetons Proxmox expirants renouvelés par procédure ; un runbook (RB-180, palier 4) pour une machine bloquée, et une procédure de reconstruction du cluster de gestion depuis l'export.
