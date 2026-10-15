# Module 16 — Introduction : le stockage et les données dans Kubernetes

## Des pods qui oublient tout

Lundi, 9 h 10. `k8s-par1` tourne depuis deux modules : trois nœuds de contrôle, trois travailleurs, Cilium, une Gateway qui publie MédiAgenda en HTTPS avec un nom automatique. Julien est content. Nadia beaucoup moins : vendredi soir, un simple `kubectl drain` de `k8s-w02` pour une mise à jour du noyau a vidé le Valkey de recette, et la base PostgreSQL de MédiAgenda tourne toujours sur un volume « jetable » que personne n'ose redémarrer. Claire Morel a convoqué l'équipe.

> **De** : Claire Morel — Responsable infrastructure
> **À** : toi
> **Cc** : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit
> **Objet** : Kubernetes — on arrête de perdre des données
>
> Bonjour,
>
> Le cluster sait faire tourner des applications sans état. Il ne sait pas encore garder une donnée. Aujourd'hui :
> - la base de MédiAgenda vit sur un volume qui disparaît avec son pod (on l'a assumé au module 14, ce n'était pas une solution) ;
> - Valkey repart vide à chaque déplacement de pod ;
> - Legacy-RDV, quand il arrivera dans le cluster, aura besoin d'un répertoire partagé entre ses instances pour ses pièces jointes ;
> - personne ne sait restaurer un espace de noms supprimé par erreur.
>
> On a déjà un stockage d'entreprise : `ceph-par1`, que l'équipe exploite depuis le module 08, avec un pool `k8s-rbd` et une identité `client.k8s` préparés pour ce jour-là. Le principe est tranché : **le stockage persistant de `k8s-par1` s'appuie sur `ceph-par1`**. Mais je signerai l'ADR après une comparaison honnête avec les deux alternatives que tout le monde me cite, Rook et Longhorn, que tu installeras, exploiteras et retireras proprement.
>
> Ce que je veux à la fin du module :
> 1. des volumes à la demande : bloc (RBD) par défaut, fichier partagé (CephFS) quand c'est justifié, avec instantanés, clones et agrandissement ;
> 2. des sauvegardes **hors du cluster** (Velero vers `s3-01`) et une restauration d'espace de noms testée ;
> 3. PostgreSQL exploité par un opérateur (CloudNativePG), répliqué, sauvegardé en continu, restaurable à la minute près ;
> 4. le chiffrement, la supervision, la mesure et la mise à jour de tout cela, et les runbooks des pannes classiques.
>
> Karim rappelle les règles : « une carte réseau, c'est OpenTofu ; une configuration de nœud, c'est un rôle Ansible ; un composant du cluster, ce sont des values et des manifestes dans `plateforme/k8s` ; un secret, c'est Vault et le registre ; jamais une clé cephx dans Git ». Sophie veut des données chiffrées en transit et au repos, et des identités Ceph minimales. Nadia veut savoir ce qui se passe quand un nœud tombe avec un volume monté, et comment on restaure. Julien veut des PVC qui passent `Bound` sans ticket.
>
> Premier jalon : le modèle de stockage compris, les travailleurs raccordés au réseau de stockage, ceph-csi en service, et le Valkey de recette qui survit à un drain. Karim te fait d'abord passer le test habituel.
> Claire

---

## Ce que tu construis dans ce module

À la fin du module 16, MédiSphère a ses **données Kubernetes v1** (étiquette `k8s-stockage-v1` du dépôt `plateforme/medisphere`) :

- les **travailleurs** `k8s-w01-03` raccordés au VLAN 30 (STOR-PUB) par une seconde carte en MTU 9000 : ils parlent à `ceph-par1` sans traverser la bordure ;
- **ceph-csi 3.18** (pilotes RBD et CephFS, espace `ceph-csi`) en mode « Ceph externe » vers `ceph-par1`, avec trois classes de stockage : `ceph-rbd` (par défaut), `ceph-rbd-retain`, `cephfs` ; le contrôleur de **snapshots** (external-snapshotter 8.6) ;
- une comparaison pratiquée de **Rook 1.21** (un Ceph dans le cluster) et de **Longhorn 1.13** (stockage répliqué sur les disques des nœuds), puis leur **retrait complet** ;
- **Velero 1.18** : sauvegarde des espaces de noms et de leurs volumes vers `s3-01` (Kopia, déplacement des données des snapshots CSI), restauration testée ailleurs ;
- **CloudNativePG 1.30** : la base `mediagenda-db` (PostgreSQL 18, 3 instances), sauvegarde continue par le plugin Barman Cloud vers `s3-01`, restauration à un instant donné ;
- le chiffrement, la supervision (sans Prometheus, qui arrive au M21), les mesures de performance, les mises à jour sans interruption, l'ADR-0160, la politique de sauvegarde et les runbooks RB-160 à RB-167.

Le **palier 1** (ce fichier et `01-decouverte.md`) pose le modèle (volumes éphémères, PV, PVC, StorageClass, CSI), raccorde les travailleurs au réseau de stockage, installe ceph-csi pour RBD puis CephFS et passe le Valkey de MédiAgenda en StatefulSet persistant.

## Architecture du module

```
                       adm01 (1001) 10.10.10.10 — VLAN 10 MGMT : kubectl, helm, ssh, checks
                       ~/src/k8s (plateforme/k8s) · ~/src/infra (envs/k8s) · ~/src/ansible · ~/src/ceph
                                       │
   ═══════════════ gw01 / gw02 (VIP .1, VRRP, FRR AS 65000) — routage et filtrage entre VLAN ══════════════
            │                                                                     │
  VLAN 40 K8S 10.10.40.0/24 (MTU 1500)                                  VLAN 20 INFRA
  ────┬────────┬────────┬───────────────┬───────────────┬───────────────     s3-01 :8333 (Velero, CNPG)
      │.51-.53 │        │.61            │.62            │.63                 reg01 :443 (images)
  ┌───┴─────┐  │  ┌─────┴──────┐  ┌─────┴──────┐  ┌─────┴──────┐
  │k8s-cp01-│  │  │ k8s-w01    │  │ k8s-w02    │  │ k8s-w03    │   ceph-csi : nodeplugin sur chaque
  │03       │  │  │ eth0 .61   │  │ eth0 .62   │  │ eth0 .63   │   travailleur (krbd, montages CephFS),
  │(taint : │  │  │ eth1 .81   │  │ eth1 .82   │  │ eth1 .83   │   provisioner sur deux travailleurs
  │ pas de  │  │  │ (E05)      │  │ (E05)      │  │ (E05)      │   (création, attachement, snapshots)
  │ volumes)│  │  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
  └─────────┘  │        │.81            │.82            │.83
               │  ──────┴───────────────┴───────────────┴─────────────────────────────────────────
               │  VLAN 30 STOR-PUB 10.10.30.0/24 · MTU 9000 · même VLAN que les MON et OSD : pas de bordure
               │  ──────┬───────────────┬───────────────┬──────────────────────┬───────────────
               │        │.51            │.52            │.53                   │.200 (VIP RGW)
               │  ┌─────┴──────┐  ┌─────┴──────┐  ┌─────┴──────┐
               │  │ ceph01     │  │ ceph02     │  │ ceph03     │   ceph-par1 (M08) : MON 3300 (msgr2,
               │  │ MON MGR MDS│  │ MON MGR MDS│  │ MON MDS    │   mode secure), OSD 6800-7568,
               │  │ OSD×3      │  │ OSD×3 RGW  │  │ OSD×3 RGW  │   pool k8s-rbd, CephFS « cephfs »
               │  └────────────┘  └────────────┘  └────────────┘   (groupe de sous-volumes csi)
```

Points structurants :

- **Un réseau de stockage, pas une route.** Les travailleurs reçoivent une carte sur le VLAN 30, sans passerelle. Le trafic RBD et CephFS (gros, sensible à la latence, en *jumbo frames*) reste dans le VLAN des moniteurs et des OSD. Passer par la bordure obligerait `gw01`/`gw02` à router et filtrer chaque écriture, et casserait le MTU 9000 (le VLAN 40 est à 1500).
- **Seuls les travailleurs portent des volumes.** Les nœuds de contrôle gardent leur *taint* par défaut et n'ont pas de carte de stockage : aucun pod de ceph-csi ni aucun volume n'y tourne. Les pods de ceph-csi sont placés par une étiquette de nœud posée par l'Ansible de E05 (« ce nœud est raccordé »).
- **ceph-csi ne déploie pas Ceph.** Il traduit les demandes de Kubernetes (créer, attacher, monter, agrandir, photographier un volume) en appels à un cluster Ceph existant, avec une identité cephx à droits limités. Les images RBD sont mappées par le **noyau** des travailleurs (krbd, Linux 6.12) et les CephFS montés par le client noyau : c'est ce qui impose le type de clé cephx `aes` (M08-E27) et le mode `secure` de msgr2 (port 3300).
- **Deux clusters, une seule dépendance.** Un pod qui a un volume RBD monté dépend de `ceph-par1` à chaque écriture. Arrêter `ceph-par1` sous des volumes montés fige les E/S des nœuds (processus en état `D`, démontage impossible) : voir les règles du module.

### Objets du module

| Élément | Valeur | Exercice |
|---|---|---|
| Carte STOR-PUB des travailleurs | `net1` sur le VNet `vstopub`, `eth1` dans l'invité, 10.10.30.81-83/24 (`k8s-w01-03`), MTU 9000, sans passerelle, MAC `bc:24:11:30:00:61-63` | E05 |
| Étiquette des nœuds raccordés | `medisphere.internal/stockage-ceph=oui` (posée après vérification du réseau de stockage) | E05 |
| Contrôleur de snapshots | external-snapshotter 8.6 : CRD `snapshot.storage.k8s.io/v1`, `snapshot-controller` dans `kube-system` | E06 |
| ceph-csi | espace `ceph-csi` (PSA `privileged`), releases Helm `ceph-csi-rbd` et `ceph-csi-cephfs` (charts 3.18.1) | E06, E07 |
| Identités Ceph | `client.k8s` (RBD, pool `k8s-rbd`, M08-E46) ; `client.k8s-cephfs` (CephFS, groupe `csi`, E07) ; clés de type `aes` | E06, E07 |
| Secrets Kubernetes | `ceph-csi/csi-rbd-secret`, `ceph-csi/csi-cephfs-secret`, créés depuis Vault par `outils/ceph-csi-secrets.sh` (jamais dans Git) | E06, E07 |
| StorageClasses | `ceph-rbd` (par défaut, `Delete`), `ceph-rbd-retain` (`Retain`), `cephfs` (RWX) | E06, E07 |
| Valkey de MédiAgenda | StatefulSet `valkey` (espace `mediagenda-recette`), PVC `donnees-valkey-0` sur `ceph-rbd` | E08 |
| VolumeSnapshotClasses | `ceph-rbd-snap`, `cephfs-snap` | E10 |
| Disques de comparaison | 32 Go `ssd-lab` (`scsi1`, Rook) et 32 Go `hdd-bulk` (`scsi2`, Longhorn) par travailleur, retirés en fin de module | E13-E15 |
| Velero | espace `velero`, BSL vers `s3-01`, compartiment `velero-k8s-par1`, compte SeaweedFS `velero` | E16-E17 |
| CloudNativePG | opérateur dans `cnpg-system`, cluster `mediagenda-db` (`mediagenda-recette`), `ObjectStore` `cnpg-s3`, compartiment `cnpg-k8s-par1`, compte `cnpg` | E18-E19 |

### Ports et flux du palier 1

| Flux | Port | Exercice | État sur `gw01`/`gw02` |
|---|---|---|---|
| `adm01` → API du cluster (VIP 10.10.40.200) | 8443 | tous | existant (MGMT joint tout le lab) |
| `adm01` → nœuds (SSH) et → `ceph01-03` (SSH) | 22 | E02-E08 | existant |
| travailleurs (10.10.30.81-83) → MON (`ceph01-03`) | 3300 (msgr2) | E05-E08 | **même VLAN 30** : ne traverse pas la bordure ; à écrire dans la matrice des flux |
| travailleurs → OSD et MDS (`ceph01-03`) | 6800-7568 | E06-E08 | même VLAN 30 |
| nœuds → `reg01` (images des pilotes, par le cache Harbor) | 443 | E06 | existant (M14) |
| `adm01` → `ceph.github.io`, `github.com` (charts, manifestes) | 443 | E06 | existant (« lab vers Internet ») |

Aucune règle nouvelle sur les passerelles au palier 1. Le flux « travailleurs → `ceph-par1` » est **intra-VLAN** : il s'écrit quand même dans la matrice des flux (`docs/socle/matrice-flux.md`), parce que la matrice décrit qui parle à qui, pas seulement ce que filtre la bordure. Le port 6789 (msgr1) n'est **pas** utilisé : tout passe en msgr2 chiffré.

---

## Le chemin imposé

1. **OpenTofu** : la carte de stockage des travailleurs s'ajoute dans l'état **`k8s`** de `plateforme/infra` (module `vm-noeud`), comme toutes les cartes depuis M08 ; les adresses arrivent dans NetBox par le module.
2. **Ansible** : la configuration réseau de la nouvelle carte, les modules noyau et l'étiquette du nœud viennent d'un rôle (`k8s_reseau_stockage`, E05), joué un travailleur à la fois, nœud drainé.
3. **`plateforme/k8s`** : tout composant du cluster (espaces de noms, values Helm, StorageClasses, manifestes du contrôleur de snapshots, scripts) est dans le dépôt, relu en MR, appliqué depuis `adm01` (`task …` ou le script du composant). **Helm** est encore un **installateur** : les commandes sont données ; tu l'apprendras au module 17.
4. **`plateforme/ceph`** : les identités et le groupe de sous-volumes de Kubernetes sont décrits dans `allocations.yaml` et appliqués par `outils/ceph-allocations.sh` (M08-E31), jamais créés à la main.
5. **Secrets** : les clés cephx des pilotes sont en Ansible Vault (identité `critique`) dans `plateforme/k8s/secrets/ceph-csi.yml` ; les Secrets Kubernetes sont créés **depuis le Vault** par un script, sans fichier en clair ; registre des secrets à jour. (Vault/OpenBao et External Secrets arrivent au module 25.)
6. **Documentation** : dans `plateforme/medisphere`, dossier **`docs/kubernetes/stockage/`** (fiches, runbooks RB-160 et suivants, ADR-0160, politique de sauvegarde) ; matrice des flux dans `docs/socle/matrice-flux.md`.

Une manipulation à la main n'est permise que pour **explorer** (un pod d'essai dans `wb-essais`, une commande d'observation sur un nœud ou sur `ceph01`), ou quand l'énoncé la demande explicitement.

---

## Concepts clés

Une synthèse pour se repérer ; la documentation officielle (liens en fin de fichier) et les exercices approfondissent.

**Volumes éphémères.** Un conteneur écrit dans sa couche inscriptible, perdue à chaque redémarrage du conteneur. Un volume `emptyDir` vit aussi longtemps que le **pod** (sur le disque du nœud, ou en mémoire avec `medium: Memory`). `configMap`, `secret`, `downwardAPI` et `projected` injectent des fichiers fournis par l'API. `hostPath` monte un répertoire du nœud : c'est une porte vers l'hôte, que les profils `baseline` et `restricted` de Pod Security interdisent.

**PersistentVolume (PV).** Un objet **de cluster** qui décrit un morceau de stockage réel (une image RBD, un sous-volume CephFS, un disque local) : capacité, modes d'accès, politique de récupération, et la façon de l'atteindre. Créé par un administrateur (statique) ou par un *provisioner* (dynamique).

**PersistentVolumeClaim (PVC).** Une **demande** de stockage faite dans un espace de noms : « 10 Gio, en lecture-écriture par un seul nœud, de la classe `ceph-rbd` ». Le contrôleur de liaison associe chaque PVC à un PV, une fois pour toutes (relation un pour un). Un pod ne connaît que le PVC.

**StorageClass.** Le **catalogue** : un nom, un *provisioner* (le pilote), des paramètres propres au pilote (pool, fonctionnalités d'image, options de montage), une politique de récupération (`Delete` ou `Retain`), l'agrandissement permis ou non, et le moment de la liaison (`Immediate` ou `WaitForFirstConsumer`). Une classe peut être marquée « par défaut ». Ses paramètres sont figés : on ne modifie pas une classe, on en crée une autre.

**Modes d'accès.** `ReadWriteOnce` (RWO) : en écriture par **un nœud** (plusieurs pods du même nœud peuvent le monter) ; `ReadWriteOncePod` (RWOP) : par **un seul pod** (pilotes CSI seulement) ; `ReadOnlyMany` ; `ReadWriteMany` (RWX) : par plusieurs nœuds à la fois, ce qui exige un système de fichiers partagé (CephFS, NFS) ou un usage en mode bloc par une application qui sait le partager. `volumeMode` : `Filesystem` (le pilote formate et monte) ou `Block` (le pod reçoit le périphérique brut).

**CSI (Container Storage Interface).** Une spécification gRPC entre l'orchestrateur et le pilote de stockage : services *Identity*, *Controller* (créer, supprimer, attacher, agrandir, photographier) et *Node* (préparer le volume sur le nœud, le monter dans le pod). Côté Kubernetes, des **sidecars** génériques (`external-provisioner`, `external-attacher`, `external-resizer`, `external-snapshotter`, `node-driver-registrar`) observent l'API et appellent le pilote ; le **kubelet** appelle la partie *Node*. Objets : `CSIDriver`, `CSINode`, `VolumeAttachment`.

**Snapshots.** `VolumeSnapshotClass`, `VolumeSnapshot`, `VolumeSnapshotContent` : des CRD et un contrôleur (external-snapshotter) que le cluster n'a pas d'origine. Un instantané CSI vit **dans le même stockage** que le volume : ce n'est pas une sauvegarde.

**StatefulSet.** Des pods à identité stable (`valkey-0`, `valkey-1`), créés et arrêtés dans l'ordre, chacun avec **son** PVC issu d'un modèle (`volumeClaimTemplates`) qui lui survit, sauf politique contraire (`persistentVolumeClaimRetentionPolicy`).

**Opérateurs et sauvegardes.** Rook et CloudNativePG sont des **opérateurs** : des contrôleurs qui réconcilient en continu des ressources de haut niveau (`CephCluster`, `Cluster` PostgreSQL) en objets Kubernetes. Velero sauvegarde des objets de l'API **et** des volumes (copie de fichiers par Kopia, ou instantanés CSI dont les données sont déplacées vers le S3), et sait les restaurer ailleurs.

---

## Faits techniques du module

| Élément | Valeur |
|---|---|
| Versions (PLAN §6) | Kubernetes **1.36** (`k8s-par1`), ceph-csi **3.18.1** (charts `ceph-csi-rbd` et `ceph-csi-cephfs` de `https://ceph.github.io/csi-charts`, image `quay.io/cephcsi/cephcsi:v3.18.1`), external-snapshotter **8.6.0**, Rook **1.21**, Longhorn **1.13**, Velero **1.18** (plugin AWS **1.14**), CloudNativePG **1.30** (plugin Barman Cloud **0.15**, PostgreSQL **18**), Helm **4.3** ; Ceph Tentacle **20.2.4** côté `ceph-par1` |
| Changements de version | voir [`annexes/versions-bloc-C.md`](../../../annexes/versions-bloc-C.md), section « Stockage » : ceph-csi testé jusqu'à Kubernetes 1.36 ; CRD et contrôleur de snapshots à installer **avant** le pilote ; Rook 1.21 exige msgr2 ; Longhorn 1.13 exige Kubernetes ≥ 1.34 ; Restic retiré de Velero (Kopia seul) ; `barmanObjectStore` intégré à CNPG déprécié (plugin Barman Cloud) |
| `ceph-par1` | fsid `<FSID>` (`ceph fsid`), MON 10.10.30.51-53, port **3300** seulement (msgr2, `ms_service_mode secure` depuis M08-E27) ; pool `k8s-rbd` (règle `ssd-baie`, application `rbd`, quota 20 Gio, M08-E46) ; CephFS `cephfs` (MDS actif et en attente, M08-E10) |
| Identités cephx | `client.k8s` : `mon 'profile rbd'`, `osd 'profile rbd pool=k8s-rbd'`, `mgr 'profile rbd pool=k8s-rbd'` (M08-E46) ; `client.k8s-cephfs` : droits de la documentation ceph-csi pour CephFS, limités au groupe `csi` (E07). Type de clé **`aes`** : le noyau 6.12 des travailleurs ne sait pas utiliser `aes256k` (M08-E27) |
| Espaces de noms | `ceph-csi` (pilotes), `kube-system` (contrôleur de snapshots), `wb-essais` (essais, PSA `baseline`), `mediagenda-recette` et `mediagenda-dev` (PSA `restricted`, politiques réseau de refus par défaut du M15 (`refus-par-defaut`)) ; puis `rook-ceph` et `longhorn-system` (temporaires), `velero`, `cnpg-system`, `wb-restauration` |
| Projets | `plateforme/infra` : `envs/k8s/` (état `k8s`) ; `plateforme/ansible` : rôle `k8s_reseau_stockage`, playbook `playbooks/k8s-reseau-stockage.yml` ; `plateforme/k8s` : `espaces/ceph-csi.yaml`, `composants/snapshot-controller/`, `composants/ceph-csi/` (values, classes, `installer.sh`), `outils/ceph-csi-secrets.sh`, `secrets/ceph-csi.yml` (Vault `critique`) ; `plateforme/ceph` : `allocations.yaml` ; `plateforme/medisphere` : `docs/kubernetes/stockage/` |
| Groupes d'inventaire Ansible | `k8s_par1`, `k8s_plan_controle`, `k8s_travailleurs` (M14) |
| Images | tirées par le cache Harbor (`hosts.toml` de containerd, M14-E19) : `quay.io/cephcsi/…`, `registry.k8s.io/sig-storage/…` sans changer les références ; dans `mediagenda-*`, la ValidatingAdmissionPolicy du M14 exige des références `registry.par1.medisphere.internal/…` explicites |
| Accès | `~/.kube/config` (identité `<MOI>`, groupe `medisphere:plateforme-admins`) pour agir ; les vérifications lisent avec `wb-checks` (`WB_K8S_KUBECONFIG`), qui ne lit **pas** les Secrets |
| Fichiers locaux sur `adm01` (600, `~/.config/workbook/`) | `s3-longhorn-essai.env` (E15, supprimé au retrait de Longhorn), `s3-velero.env` (compte `velero`, E16), `s3-cnpg.env` (compte `cnpg`, E19), `k8s-supervision-stockage.kubeconfig` (E27), `s3-medidoc-app.env` (compte RGW `medidoc-app`, existant depuis M08-E12, E46) ; aucun pour le palier 1 (les clés cephx ne passent que par Vault) |
| Brouillons | `~/m16/eXX/` sur `adm01` (non versionnés, **sans secret**) |

### Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<MOI>` | Ton compte GitLab personnel (M01-E05), aussi ton identité Kubernetes (M14-E06) |
| `<FSID>` | Identifiant de `ceph-par1` (`ceph fsid` sur `ceph01`) ; ceph-csi l'utilise comme `clusterID` |
| `<VERSION-TOFU-MODULES>` | Étiquette de `plateforme/tofu-modules` utilisée par l'état `k8s` (celle qui contient `vm-noeud` avec MAC imposée, v2.3.0 ou suivante) |

### Variables de `lab/lab.env`

Deux variables nouvelles, facultatives : `WB_M16_API_URL` (URL publiée de MédiAgenda en recette, `https://mediagenda-recette.apps.par1.medisphere.internal` par défaut) et `WB_M16_IMAGE_TEMOIN` (image des pods témoins des pannes, `registry.par1.medisphere.internal/dockerhub/library/busybox:1.37` par défaut). Les vérifications du module utilisent sinon celles des modules 08 et 14 : `WB_CEPH_ADMIN` (nœud `_admin` où lancer `ceph` et `rbd`, `ceph01` par défaut), `WB_K8S_KUBECONFIG`, `WB_K8S_ADMIN_KUBECONFIG` (pannes), `WB_K8S_WORKERS`, `WB_K8S_CP`, `WB_PVE_HOST`, `WB_STORAGE_SSD`, `WB_STORAGE_BULK`, `WB_SRC`, `WB_DEPOT`, et les jetons en lecture de GitLab et de NetBox. Si `ceph01` est arrêté, mets `WB_CEPH_ADMIN=ceph02` le temps de vérifier.

---

## Règles du module

1. **`reclaimPolicy: Delete` efface vraiment.** Supprimer un PVC d'une classe `Delete` supprime l'image RBD ou le sous-volume CephFS, et ses données, sans corbeille. Supprimer un **espace de noms** supprime tous ses PVC. Avant toute suppression de PVC ou d'espace de noms qui porte des données, vérifie ce qui est dedans (`kubectl get pvc -n <espace>`) et sa sauvegarde.
   > ⚠️ **Attention** : `kubectl delete namespace mediagenda-recette` emporte la base de recette, le Valkey et leurs volumes. Les essais se font dans `wb-essais`.
2. **`ceph-par1` est partagé.** Kubernetes n'y touche que le pool `k8s-rbd` et le groupe de sous-volumes `csi` du volume `cephfs`. Aucune commande de ce module ne vise les pools ou les identités d'OpenStack (`images`, `volumes`, `vms`, `backups`), des équipes (`rbd-equipes`) ou de test (`rbd-test`), ni les moniteurs et les OSD. Une commande `rbd rm` ou `ceph fs subvolume rm` se relit deux fois, nom de l'image et pool compris.
3. **Ordre d'arrêt et de démarrage.** Arrêt : d'abord ce qui monte des volumes Ceph (au minimum, `k8s-par1` entier : travailleurs, puis nœuds de contrôle), **ensuite** `ceph-par1` (procédure du M08 : drapeaux `noout`… puis `ceph03`, `ceph02`, `ceph01`). Démarrage : `ceph-par1` d'abord, jusqu'à `HEALTH_OK` (ou l'état connu), **puis** `k8s-par1`. Un travailleur qui démarre sans Ceph laisse ses pods en `ContainerCreating` ; un Ceph qui s'arrête sous des volumes montés fige les nœuds.
4. **Un travailleur à la fois.** Tout changement d'un travailleur (carte réseau, redémarrage, disque ajouté) se fait nœud **drainé**, un seul à la fois, et le suivant seulement quand le précédent est `Ready`, raccordé et que les pods sont revenus. Le playbook de E05 est en `serial: 1`.
5. **Aucune clé cephx en clair** : ni dans Git, ni dans un manifeste, ni dans un fichier temporaire, ni en argument de commande, ni dans un ticket. Elles passent par des tubes (`ssh ceph01 'sudo ceph auth get-key …' | …`) vers Ansible Vault, et du Vault vers l'API Kubernetes.
6. **Pas de vérification TLS désactivée** (`curl -k`, `--insecure-skip-tls-verify`) : la CA MédiSphère est installée partout depuis M06.
7. **Mémoire.** Le module demande le socle v3 (≈ 37 Go), `k8s-par1` (≈ 36 Go) et `ceph-par1` (3 × 6 Go) : ≈ 91 Go sur 128. Rook et Longhorn (E13-E15) chargent surtout les travailleurs : ne les fais pas tourner en même temps, et retire chacun avant le suivant. Arrête les profils lourds des autres modules (`hv-par1`, OpenStack, `m15-essai`).

---

## Préparer `adm01`

Les outils viennent des modules 14 et 15 (kubectl 1.36, Helm 4.3, krew, cilium et hubble). Vérifie avant de commencer :

```
admin@adm01:~$ lab/bin/check 15 46
admin@adm01:~$ lab/bin/check 08 46
admin@adm01:~$ kubectl version ; helm version --short
admin@adm01:~$ kubectl get nodes -o wide
admin@adm01:~$ ssh ceph01 'sudo ceph -s'
admin@adm01:~$ ssh ceph01 'sudo ceph osd pool get-quota k8s-rbd ; sudo ceph auth get client.k8s' | grep -v 'key ='
```

Les deux premiers contrôles (mini-projets des modules 15 et 08) doivent être verts : ce module part de `k8s-reseau-v1` et de `stockage-v1`. Le dernier montre le quota du pool `k8s-rbd` et les droits de `client.k8s` (la ligne de la clé est filtrée : prends l'habitude). Si `ceph-par1` était arrêté depuis le module 08, redémarre-le **avant** `k8s-par1` (règle 3) et attends `HEALTH_OK`.

Les outils des paliers suivants (CLI `velero`, extension `kubectl cnpg`) s'installent dans leurs exercices.

---

## Indices, corrigé, vérifications

- Les vérifications se lancent depuis `adm01` : `lab/bin/check 16 <XX>`. Elles sont en lecture seule : objets Kubernetes lus avec `wb-checks`, configuration Proxmox lue sur `pve01`, état des nœuds en SSH, commandes `ceph` et `rbd` **d'observation** sur le nœud `_admin` (`WB_CEPH_ADMIN`), NetBox et GitLab en lecture. Elles ne lisent jamais un Secret.
- Les indices sont progressifs : ouvre-les un par un, seulement quand tu bloques.
- Le corrigé (`corrige/`) donne une solution, le *pourquoi*, les alternatives, les pièges et la vision production. Les fichiers complets sont dans `corrige/fichiers/M16-EXX/` : `k8s/` reproduit l'arborescence de `plateforme/k8s`, `infra/` celle de `plateforme/infra`, `ansible/` celle de `plateforme/ansible`, `ceph/` celle de `plateforme/ceph`, `medisphere/` celle de la documentation, `mediagenda-api/` celle du projet `mediagenda/api` (manifestes `k8s/recette/` de MédiAgenda), `essais/` les manifestes jetables de `wb-essais`. Même quand ta vérification est verte, lis « Pièges classiques ».
- Les scripts de panne (`corrige/pannes/`, palier 4) révèlent les causes : ne les lis pas avant d'avoir résolu.

## Ordre conseillé du palier 1

```
E01 ─ E02 ─ E03 ─ E04 (partie A) ─ E05 ─ E06 ─ E04 (partie B) ─ E07 ─ E08 ─ E09
```

1. **E01** — positionnement, à froid.
2. **E02 → E03** — le modèle, sans pilote : volumes éphémères, puis PV et PVC posés à la main.
3. **E04, partie A** — la spécification CSI et ce que le cluster sait déjà (rien).
4. **E05 → E06** — le réseau de stockage, puis ceph-csi RBD. **E04, partie B** observe le pilote installé.
5. **E07** — CephFS, une fois RBD en service.
6. **E08** — StatefulSet, sur `ceph-rbd`.
7. **E09** — en dernier.

Durée indicative du palier 1 : 14 à 18 heures.

## Pour aller plus loin

- Stockage dans Kubernetes : <https://kubernetes.io/docs/concepts/storage/> (volumes, PV, StorageClasses, snapshots, volumes éphémères)
- Spécification CSI : <https://github.com/container-storage-interface/spec/blob/master/spec.md> · documentation des développeurs CSI (sidecars, objets) : <https://kubernetes-csi.github.io/docs/>
- ceph-csi : <https://github.com/ceph/ceph-csi> (dossier `docs/`, en particulier `capabilities.md`, `rbd/deploy.md`, `cephfs/deploy.md`) et la page *Block Devices and Kubernetes* de Ceph : <https://docs.ceph.com/en/tentacle/rbd/rbd-kubernetes/>
- StatefulSets : <https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/>
- Pod Security Standards : <https://kubernetes.io/docs/concepts/security/pod-security-standards/>
