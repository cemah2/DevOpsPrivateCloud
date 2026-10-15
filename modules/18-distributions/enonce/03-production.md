# Module 18 — Palier 3 : Production

Les distributions ont toutes été installées par le code : k3s sur `k3s01`, RKE2 durci sur `rke2-01..03`, Talos sur `talos-01..03`, et un cluster `capi-essai` créé par Cluster API depuis `k3s01`, devenu cluster de gestion. Claire Morel ne veut pas d'un catalogue de démonstrations. Elle veut savoir ce que chaque option coûte **le jour où il faut l'exploiter** : monter de version, réparer, sauvegarder, restaurer, durcir. Elle veut aussi un ADR qui tranche, et la preuve qu'un cluster de recette éphémère se monte pour une équipe en moins d'une heure.

> ⚠️ **Rappel mémoire** : jamais plus de ≈ 30 Go en plus du socle. `k8s-par1` reste **arrêté** pendant tout le palier (procédure d'arrêt de `docs/kubernetes/cluster.md`, M14-E05). Les VMs du module sont déclarées démarrées dans OpenTofu (`started = true`) : un `qm shutdown` serait défait au prochain `tofu apply`. Un banc qui ne sert pas se **détruit** et se **reconstruit par le code** :
> - RKE2 : groupe `rke2` de `envs/m18`, puis le playbook `m18.yml` (≈ 15 min) ;
> - Talos : groupe `talos`, puis `talos/generer.sh`, `talos/appliquer.sh <nœud> --maintenance` et `talosctl bootstrap`, avec le **même** paquet `~/.config/workbook/m18/talos-secrets.yaml` (≈ 10 min ; même CA, même `talosconfig`) ;
> - banc k3s etcd : variable `k3s_ha_noeuds`.
>
> `capi-essai` se met **au repos** sans être détruit :
> 1. mets le `Cluster` en pause (`spec.paused: true`), sinon le `MachineHealthCheck` remplacerait les machines éteintes ;
> 2. arrête ses VMs depuis `pve01` (`qm shutdown`, travailleurs puis nœud de contrôle) ;
> 3. au réveil : `qm start` dans l'ordre inverse, nœuds `Ready`, puis lève la pause.
>
> L'enveloppe de chaque exercice :

| Exercice | Allumé | Mémoire approx. |
|---|---|---|
| E13 | `k3s01` + `capi-essai` (1 CP + 2 à 3 travailleurs, plus une machine de surplus pendant les remplacements) ; `m18-dev01` pour la construction de l'image, **avant** les remplacements | 4 + 16 à 20 Go, ou 4 + 12 + 8 Go pendant la construction |
| E14 | `k3s01` + `capi-essai` (ou au repos) + un banc à la fois : `k3s-ha01/02` (4 Go), puis RKE2 (12 Go), puis Talos (9 Go) | ≤ 28 Go |
| E15 | `k3s01` + RKE2 + Talos, `capi-essai` au repos | 25 Go |
| E16 | profil **openstack** (M10) + `ceph-par1` + `m18-dev01` ; tout le reste du module détruit ou au repos | ≈ 58 Go (dérogation, voir l'exercice) |
| E18 | `m18-dev01` (ou `k3s01` + VMs CAPI) | 8 Go |

> ⚠️ **Le cluster de gestion `k3s01` porte l'état de `capi-essai`** (objets Cluster API, Secret `capi-essai-proxmox` avec le jeton Proxmox, kubeconfig d'administration du cluster de charge de travail). Avant toute action sur `k3s01` (redémarrage, conversion de base, chiffrement), fais une copie de secours de cet état (E14, étape 1) et vérifie que `clusterctl describe cluster capi-essai -n capi-essai` est vert. Ne détruis jamais une VM 5180-5189 à la main : c'est Cluster API qui les possède.

**Chemin imposé** (introduction du module) :
- le code du module vit dans `plateforme/distributions` (clone `~/src/distributions`) : `k3s/`, `rke2/`, `talos/` (correctifs, jamais de secret en clair), `capi/` (manifestes de `capi-essai`), `kind/`, `k3d/` ;
- les VMs vivent dans `plateforme/infra/envs/m18/` (module `vm-noeud`, étiquette `env-m18`), les rôles dans `plateforme/ansible` (`k3s`, `rke2`, `outils_distributions`) ;
- la documentation va dans `docs/kubernetes/distributions/` de `plateforme/medisphere` (`adr/`, `runbooks/`, `tests/`).

Chaque changement passe par une MR et un pipeline vert. Les fichiers d'accès des clusters d'essai sont sous `~/.config/workbook/m18/` (mode 600) : `k3s01.kubeconfig`, `rke2.kubeconfig`, `talosconfig`, `talos.kubeconfig`, `talos-secrets.yaml`, `capi-essai.kubeconfig` ; ce palier ajoute `k3s-ha.kubeconfig` (banc recréé en E14), `talosconfig-sauvegarde` (E14) et `recette-mediagenda.kubeconfig` (E18). `kind-gestion.kubeconfig` a disparu au pivot (E12).

**État de départ attendu** (fin du palier 2) :
- `k3s01` : k3s v1.36.5+k3s1 sur SQLite, cluster de gestion Cluster API 1.12 (pivot de M18-E12) avec CAPMOX 0.9 et le fournisseur IPAM *in-cluster* ;
- `capi-essai` : 1 nœud de contrôle + 2 travailleurs en Kubernetes v1.36.4, template 9060 `tpl-capi-ubuntu2404-k136`, VIP 10.10.40.210, Cilium par `ClusterResourceSet` ; objets dans l'espace `capi-essai` du cluster de gestion ;
- RKE2 (`rke2-01..03`, trois serveurs v1.36.5+rke2r1, Rocky Linux 10, profil CIS) et Talos (`talos-01..03`, 10.10.99.85-87, cluster `talos-essai`, Talos v1.14.2, Kubernetes v1.36.5) : **détruits** en fin de M18-E04 et M18-E06, reconstruits par le code quand un exercice en a besoin (voir ci-dessus) ;
- `lab/bin/check 18 12` est vert.

**Ordre conseillé** : E13 → E14 → E15 → E17 → E18, et E16 quand tu as le temps (facultatif). L'ADR (E17) s'écrit après les mesures de E13 à E15. **Durée totale indicative** : 12 à 16 h (sans E16).

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 18 XX`). Les clusters d'essai n'ont pas de compte `wb-checks` : les contrôles lisent avec les kubeconfig de `~/.config/workbook/m18/`, **en lecture seule** (aucune commande d'écriture), et lisent les nœuds par SSH (`sudo -n` pour des lectures seulement) ou par `talosctl` (lectures). C'est l'exception documentée du module.

---

### M18-E13 — Cycle de vie par Cluster API : montée de version, réparation, mise à l'échelle  `LAB` `★★★`

> **Ticket PLAT-1913** — *De : Karim Benali* — *Copie : Claire Morel*
> On nous vend Cluster API avec une phrase : « un cluster se gère comme un Deployment ». Avant d'écrire ça dans un ADR, je veux le voir sur `capi-essai`. Un travailleur qui meurt est remplacé sans qu'on y touche. On ajoute et on retire un travailleur par une ligne de YAML. Et on passe en 1.36.5 avec une nouvelle image de nœud, sans SSH sur les nœuds et sans interrompre une charge témoin. Chronomètre tout : ces chiffres iront dans le comparatif.

**Objectifs pédagogiques**
- Relier les objets Cluster API entre eux : `Cluster`, `KubeadmControlPlane` (KCP), `MachineDeployment` (MD), `MachineSet`, `Machine`, `ProxmoxMachine`, VM Proxmox, `Node`.
- Écrire et éprouver un `MachineHealthCheck` en API `v1beta2`, et comprendre ses garde-fous.
- Monter un cluster de version par **remplacement** de machines (changement de version et de template d'infrastructure), dans le bon ordre, et mesurer l'effet sur une charge.

**Prérequis** : M18-E09 (image-builder), M18-E10 (`capi-essai`), M18-E12 (pivot vers `k3s01`) ; M14-E16 (PDB, drain).
**Durée indicative** : 4 h (dont 1 h de construction d'image).

**Contexte technique**
- Cluster de gestion : `k3s01` (`~/.config/workbook/m18/k3s01.kubeconfig`), espace `capi-essai`. Cluster de charge de travail : `~/.config/workbook/m18/capi-essai.kubeconfig`.
- VMs créées par CAPMOX dans la plage `vmIDRange` 5180-5189, adresses 10.10.40.150-169 (pool `capi-essai-v4-icip`, créé par CAPMOX à partir du `ipv4Config` du `ProxmoxCluster`). Un remplacement crée une machine **avant** d'en supprimer une : compte les VMID et les adresses disponibles avant de lancer quoi que ce soit.
- Nouvelle image : VMID **9061** `tpl-capi-ubuntu2404-k136-2`, Kubernetes **v1.36.5**, construite comme en E09 sur `m18-dev01`. À la fin, 9061 porte les étiquettes `capi` et `current`, et 9060 ne porte plus `current` (il reste en place tant qu'une machine en dépend).
- Charge témoin dans `capi-essai` : un Deployment `temoin` de 3 réplicas (image `registry.k8s.io/pause:3.10`) dans l'espace `wb-essais`, protégé par un PDB `minAvailable: 2`. Le cluster de charge de travail tire ses images par le cache Harbor (miroirs `hosts.toml` posés par les manifestes de E10).
- Les objets Cluster API qui portent des gabarits (`ProxmoxMachineTemplate`, `KubeadmConfigTemplate`) sont **immuables** par convention : on en crée un nouveau, sous un nouveau nom, et on change la référence.

> ⚠️ **Attention** : un remplacement complet crée et détruit des VMs dans le pool `lab`. Avant de commencer, vérifie que la mémoire libre de `pve01` couvre une VM de plus que la taille du cluster (`free -g` sur `pve01`), que `k8s-par1` est arrêté, et que tu sais revenir en arrière : on revient à l'état précédent en remettant les anciennes références (version et template) dans les manifestes, ce qui déclenche un nouveau remplacement. On ne supprime jamais un `Machine` d'un nœud de contrôle unique à la main.

**Travail demandé**
1. **Lire.** Depuis `adm01`, dessine la chaîne des objets de `capi-essai` :
   - `clusterctl describe cluster capi-essai -n capi-essai --show-conditions all` ;
   - `kubectl get cluster,kcp,md,ms,machines,proxmoxmachines -n capi-essai -o wide` (kubeconfig du cluster de gestion) ;
   - pour une machine : son `ProxmoxMachine`, le VMID et le nœud Proxmox (`status`), le `providerID` du `Node` correspondant dans le cluster de charge de travail.

   Note dans ton compte rendu quelles étiquettes portent les `Machine` des travailleurs et du plan de contrôle : tu en auras besoin pour les sélecteurs.
2. **Charge témoin.** Déploie le Deployment `temoin` et son PDB dans le cluster de charge de travail (manifeste versionné dans `capi/capi-essai/essais/`). Lance en parallèle, depuis `adm01`, une boucle qui note chaque seconde le nombre de pods `temoin` prêts. Elle tourne pendant les étapes 3 à 5.
3. **Réparation automatique.** Écris `capi/capi-essai/mhc-travailleurs.yaml` : un `MachineHealthCheck` (`cluster.x-k8s.io/v1beta2`) qui ne vise **que** les machines du `MachineDeployment` des travailleurs. Il doit déclarer un nœud malade quand `Ready` est `Unknown` ou `False` depuis 5 minutes, et laisser 15 minutes à une machine neuve pour rejoindre le cluster. Le seuil d'arrêt (*short-circuit*) doit permettre de réparer **une** machine sur deux, et pas deux. Lis la page *Configure a MachineHealthCheck* du livre Cluster API **de la version 1.12** pour les noms de champs, puis valide le manifeste par le serveur (`--dry-run=server`) avant de l'appliquer par MR.
   - Arrête brutalement un travailleur depuis `pve01` (`qm stop <VMID>`), puis chronomètre : passage du `Node` en `Unknown`, machine marquée malade (`kubectl get mhc`, conditions de la `Machine`), suppression, nouvelle VM, nouveau `Node` `Ready`.
   - Explique pourquoi on ne pose pas le même `MachineHealthCheck` sur le plan de contrôle de `capi-essai`, et à partir de combien de nœuds de contrôle on le poserait.
4. **Mise à l'échelle.** Passe les travailleurs à 3 par un changement du manifeste (MR), puis reviens à 2 en choisissant **toi-même** la machine supprimée. Observe le *drain* : que fait le PDB du témoin ?
5. **Montée de version.**
   - Construis le template 9061 (Kubernetes v1.36.5) avec image-builder, comme en E09, et déplace l'étiquette `current`.
   - Prépare les nouveaux `ProxmoxMachineTemplate` (plan de contrôle et travailleurs). Décide explicitement la stratégie de remplacement de chaque groupe : surplus et indisponibilité permis.
   - Monte **d'abord** le plan de contrôle (version du KCP et référence au nouveau gabarit dans la même MR), attends qu'il soit entièrement à jour, **puis** les travailleurs.
   - Pendant ce temps, suis les machines (`clusterctl describe`, `kubectl get machines -w`), les membres etcd et la boucle témoin.
6. **Documenter.**
   - `docs/kubernetes/distributions/runbooks/RB-182-montee-version-capi.md` : préalables (compatibilité CAPI/fournisseur/version, image construite et testée, mémoire, VMID, adresses), ordre, commandes de suivi, critères d'arrêt, retour arrière.
   - `docs/kubernetes/distributions/tests/cycle-de-vie-capi.md` : chronologies et durées mesurées aux étapes 3 à 5, nombre minimal de pods témoins prêts observé.

**Critères de réussite**
- [ ] Un `MachineHealthCheck` vise les travailleurs de `capi-essai` (et eux seuls), avec des conditions `Ready` `Unknown`/`False`, un délai ≤ 10 min, un délai de démarrage ≥ 10 min et un seuil d'arrêt qui permet exactement une réparation sur deux machines ; ses machines sont toutes saines.
- [ ] Le plan de contrôle et les travailleurs sont en v1.36.5. Toutes les machines sont `Running` et à jour, et elles ont été clonées depuis le template 9061.
- [ ] Les nœuds du cluster de charge de travail sont `Ready` et leurs kubelets en v1.36.5 ; le `MachineDeployment` a ses réplicas prêts (2 ou plus).
- [ ] 9061 porte `capi` et `current`, 9060 ne porte plus `current`.
- [ ] Le `MachineHealthCheck` et les nouveaux gabarits sont sur `main` de `plateforme/distributions` ; RB-182 et le compte rendu chronométré sont publiés.

**Vérification** : `lab/bin/check 18 13`

<details><summary>Indice 1</summary>

Le contrôleur de `MachineDeployment` pose sur chaque machine qu'il crée une étiquette qui porte le nom du MD. Le KCP pose la sienne sur les machines du plan de contrôle. Regarde `kubectl get machines -n capi-essai --show-labels` avant d'écrire le sélecteur.
</details>

<details><summary>Indice 2</summary>

Un seuil en pourcentage s'arrondit **vers le bas**. Calcule ce que donne « 40 % » sur deux machines.
</details>

<details><summary>Indice 3</summary>

Ce n'est pas le changement du template Proxmox qui déclenche un remplacement, c'est le changement **de la spécification** du KCP ou du MD : version, référence à un autre gabarit, configuration d'amorçage. Un `ProxmoxMachineTemplate` modifié sur place ne déclenche rien : les machines existantes n'en savent rien, seules les futures en héritent.
</details>

**Pour aller plus loin** (facultatif) : passe le plan de contrôle à 3 réplicas, ajoute un `MachineHealthCheck` pour lui et `remediation` dans le KCP (`maxRetry`, `retryPeriodSeconds`), puis arrête un nœud de contrôle. Compare avec le remplacement manuel d'un nœud de contrôle kubeadm (M14-E29). Reviens à 1 réplica à la fin : la mémoire du lab ne suit pas.

---

### M18-E14 — Sauvegarder et restaurer selon la distribution  `LAB` `★★★`

> **Ticket PLAT-1914** — *De : Nadia Roussel* — *Copie : Sophie Laurent*
> Pour `k8s-par1`, on a RB-141 et une restauration chronométrée. Pour les autres distributions, rien. Avant que l'ADR ne retienne quoi que ce soit, je veux pour chacune une sauvegarde automatique, hors de la machine, et une **vraie** restauration faite et chronométrée. Et le cluster de gestion : si on perd `k3s01`, on perd la mémoire de tous les clusters CAPI ?

**Objectifs pédagogiques**
- Sauvegarder l'état d'un cluster selon son magasin : SQLite (kine) de k3s, etcd intégré de k3s et de RKE2, etcd de Talos, et l'état Cluster API d'un cluster de gestion.
- Envoyer les instantanés hors de la machine, vers `s3-01`, sans secret dans un dépôt.
- Restaurer réellement chaque distribution et comparer avec la procédure kubeadm de M14-E24 (RB-141).

**Prérequis** : M14-E24 (etcd, RB-141), M18-E03, M18-E04, M18-E05, M18-E07 (code du banc k3s HA), M18-E12 ; M05 (compartiments S3, politiques).
**Durée indicative** : 4 à 5 h.

**Contexte technique**
- **Banc k3s etcd** : `k3s01` tourne sur SQLite. Pour pratiquer l'etcd intégré de k3s, recrée par le code de M18-E07 deux VMs jetables : `k3s-ha01` (5191, serveur `--cluster-init`) et `k3s-ha02` (5192, **agent**), v1.36.5+k3s1, 2 Go chacune (variable `k3s_ha_noeuds` de `plateforme/infra/envs/m18/`, rôle `k3s`). Kubeconfig : `~/.config/workbook/m18/k3s-ha.kubeconfig`. Le banc reste en place jusqu'au palier 4 (M18-E19) et il est détruit au mini-projet.
- **Stockage objet** : compartiment `etcd-m18` sur `s3-01` (`https://s3-01.par1.medisphere.internal:8333`), versionné, dossiers `k3s-ha/`, `rke2/`, `talos/`, `gestion/`. Identité dédiée `etcd-m18` : lister, lire, écrire, **jamais supprimer** (la purge est faite par le cycle de vie, posé par l'administrateur, comme en M14-E24). Identifiants : Ansible Vault `lab` pour les nœuds, `~/.config/workbook/s3-etcd-m18.env` (600) sur `adm01`.
- k3s et RKE2 lisent des fragments de configuration dans `/etc/rancher/<k3s|rke2>/config.yaml.d/*.yaml`. La configuration des instantanés va dans un fragment dédié, **`config.yaml.d/50-etcd-s3.yaml`** (600, il contient les clés S3), posé par le rôle. Les noms des options `etcd-s3-*` sont dans la page *etcd-snapshot* de chaque documentation.
- Noms dans `gestion/` : l'archive de la base de `k3s01` porte `k3s01` dans son nom, l'export Cluster API porte `capi` (par exemple `k3s01-<horodatage>.tar.gz.age`, `capi-essai-<date>.tar.gz.age`) ; le `talosconfig` de sauvegarde est `~/.config/workbook/m18/talosconfig-sauvegarde`.
- Témoin de restauration : dans chaque cluster, une ConfigMap `temoin-restauration` dans l'espace `wb-essais`, avec `etat=avant-instantane` au moment de l'instantané, passée à `apres-instantane` juste après.
- Flux : `k3s-ha01`, `rke2-01..03` (`vsandbox`) → `s3-01` 8333 est à ouvrir sur la bordure (rôle `pare_feu`, `group_vars/role_routeur/pare_feu.yml`, `docs/socle/matrice-flux.md`). Talos est sauvegardé depuis `adm01` (MGMT, déjà autorisé).

> ⚠️ **Attention** : une restauration remplace **tout** l'état du cluster par celui de l'instantané. Tu le fais sur des clusters d'essai, jamais sur `k8s-par1`. Avant chaque restauration : instantané **frais** vérifié et copié hors de la machine, jeton du serveur sauvegardé (k3s, RKE2), secrets Talos (`talos-secrets.yaml`) à portée de main. Les commandes de restauration déplacent l'ancienne base (`etcd-old-<horodatage>`) : ne la supprime qu'une fois le cluster vérifié.

**Travail demandé**
1. **Le cluster de gestion d'abord** (`k3s01`, SQLite).
   - Lis la page *Backup and Restore* de k3s : qu'est-ce qui suffit à sauvegarder un serveur SQLite ? Pourquoi le **jeton du serveur** en fait partie ?
   - Fais une sauvegarde à froid cohérente de `k3s01` (arrêt bref du service, copie, redémarrage). Mesure l'interruption du cluster de gestion. Chiffre l'archive avec `age` (comme en M14-E24) et envoie-la dans `gestion/`.
   - Exporte aussi l'état Cluster API de `capi-essai` dans un dossier, avec `clusterctl move --to-directory` (lis `clusterctl move --help` : cette commande n'efface rien côté source). Ce que ce dossier contient de secret (Secret `capi-essai-proxmox`, kubeconfig) impose son chiffrement : traite-le comme l'archive précédente.
   - Écris dans RB-181 ce qu'on fait si `k3s01` est perdu : restauration de la base, ou nouveau cluster de gestion et `clusterctl move --from-directory`. Que deviennent les VMs de `capi-essai` pendant ce temps ?
2. **k3s, etcd intégré.**
   - Recrée le banc `k3s-ha01`/`k3s-ha02`, ouvre le flux vers `s3-01`, puis configure par le rôle `k3s` (variables et Vault) les instantanés planifiés : toutes les 6 h, 8 conservés en local, envoi dans `k3s-ha/`, CA MédiSphère, adressage du compartiment par chemin.
   - Prends un instantané à la demande. Liste-le avec `k3s etcd-snapshot ls` **et** par l'objet `ETCDSnapshotFile`.
   - Restaure le serveur depuis l'instantané stocké dans S3 (procédure « single server » de la doc). L'agent doit revenir seul. Le témoin doit valoir `avant-instantane`.
3. **RKE2, trois serveurs.**
   - Reconstruis le banc RKE2 par le code s'il est détruit (introduction du palier).
   - Même configuration (dossier `rke2/`, toutes les 6 h, 8 conservés), par le rôle `rke2`.
   - Instantané à la demande, puis restauration selon la procédure « multiple servers » de la doc RKE2. Avant de commencer, réponds par écrit : que se passe-t-il si `rke2-server` tourne encore sur `rke2-02` ou `rke2-03` pendant la réinitialisation de `rke2-01` ? Et si les conteneurs etcd de `rke2-01` tournent encore ? Les scripts installés par le paquet sous `/usr/bin/` t'aideront à les arrêter.
4. **Talos.**
   - Reconstruis `talos-essai` par le code s'il est détruit, avec le même paquet de secrets.
   - Crée un `talosconfig` dédié à la sauvegarde, avec le **seul** rôle `os:etcd:backup` (`talosctl config new --help`), en 600 : `~/.config/workbook/m18/talosconfig-sauvegarde`. Vérifie qu'il ne permet pas de lire la configuration d'une machine.
   - Écris `talos/outils/etcd-instantane.sh` dans `plateforme/distributions` : instantané par `talosctl etcd snapshot`, contrôle de l'empreinte (`etcdutl snapshot status`), chiffrement `age`, envoi dans `talos/`.
   - Restaure le cluster selon la page *Disaster Recovery* de Talos 1.14 : réinitialisation de la partition `EPHEMERAL` de `talos-01`, attente de l'état `Preparing` d'etcd, `talosctl bootstrap --recover-from`. Vérifie les nœuds et le témoin.
5. **Comparer et documenter.**
   - `docs/kubernetes/distributions/runbooks/RB-181-restaurer-selon-distribution.md` : une section par distribution, plus le cluster de gestion, et une ligne de renvoi vers RB-141 pour kubeadm.
   - `docs/kubernetes/distributions/tests/restaurations.md` : pour chaque distribution, la date, la taille de l'instantané, le RPO (écart entre l'instantané et l'incident simulé), le RTO mesuré (de la décision de restaurer au témoin lu), et les écarts par rapport à la doc. Ajoute un tableau qui compare avec la restauration kubeadm de M14-E24 : commandes, nombre de nœuds touchés, ce que fait l'outil à ta place (`--bump-revision`, identifiants de membres, certificats), ce qu'il faut sauvegarder **en plus** de l'instantané.

**Critères de réussite**
- [ ] `k3s-ha01` et les trois serveurs RKE2 ont des instantanés planifiés envoyés dans `etcd-m18` (dossiers `k3s-ha/` et `rke2/`), le dernier de moins de 7 h, et aucun secret S3 n'est sur `main` d'un dépôt.
- [ ] Le dossier `talos/` contient un instantané chiffré (`age`) de moins de 7 jours ; le `talosconfig` de sauvegarde n'a que le rôle `os:etcd:backup`.
- [ ] Le dossier `gestion/` contient une archive chiffrée de `k3s01` et une de l'export `clusterctl move --to-directory`.
- [ ] Dans chaque cluster restauré qui est allumé au moment du contrôle, le témoin vaut `avant-instantane`. Les nœuds sont `Ready`.
- [ ] RB-181 et le compte rendu des restaurations sont publiés, avec les RTO et RPO mesurés et la comparaison avec kubeadm.

**Vérification** : `lab/bin/check 18 14`. Allume au moins un banc restauré avant de la lancer. Le contrôle lit le compartiment avec l'identité `etcd-m18`, les témoins des clusters allumés, et signale ceux qui sont éteints.

<details><summary>Indice 1</summary>

Les options `etcd-s3-*` acceptent un fichier de CA, un dossier, un type d'adressage et une région. SeaweedFS ignore la région, mais le client en envoie une. L'option qui désigne le point d'accès attend un **nom d'hôte et un port**, pas une URL.
</details>

<details><summary>Indice 2</summary>

Une restauration depuis S3 se lance avec les options S3 sur la ligne de commande et le **nom** de l'instantané seul. Le Secret de configuration S3 (`etcd-s3-config-secret`), s'il existe, ne sert pas à la restauration. Et le jeton : si celui du fichier de configuration ne correspond pas à celui de l'instantané, le serveur ne démarre pas.
</details>

<details><summary>Indice 3</summary>

Pour Talos, la restauration n'est permise que si etcd est en état `Preparing` sur le nœud de contrôle, ce qui veut dire : plus de données etcd locales. C'est ce que fait la réinitialisation de la seule partition `EPHEMERAL`. La configuration de la machine, elle, est dans `STATE`, et tu la gardes.
</details>

**Pour aller plus loin** (facultatif) : planifie les instantanés Talos **depuis le cluster** plutôt que depuis `adm01`. Il faut une `CronJob` qui parle à l'API Talos avec un compte de service Talos de rôle `os:etcd:backup`. Cherche dans la doc Talos 1.14 comment on autorise l'accès à l'API Talos depuis Kubernetes. Que gagne-t-on et que perd-on par rapport au script ?

---

### M18-E15 — Durcissement comparé  `LAB` `★★`

> **Ticket SEC-1915** — *De : Sophie Laurent*
> RKE2 se dit « durci », Talos se dit « sûr par construction », k3s se dit « léger ». Je veux des faits. Les ports ouverts, les comptes, ce qui est appliqué par défaut, et un passage de kube-bench. Je ne te demande pas de durcir quoi que ce soit au-delà, ce sera le module 26, avec une seule exception : le cluster de gestion `k3s01` détient le jeton Proxmox et le kubeconfig d'administration de `capi-essai`, et ses Secrets sont aujourd'hui en clair dans sa base. Ça, je le veux corrigé cette semaine.

**Objectifs pédagogiques**
- Lire ce que fait réellement un profil de durcissement (RKE2 `profile: cis`) et ce que garantit l'architecture (Talos), par l'observation.
- Utiliser kube-bench en connaissant ses limites : version du référentiel, chemins propres à chaque distribution, faux positifs.
- Chiffrer les Secrets au repos d'un cluster k3s existant.

**Prérequis** : M18-E03, M18-E04, M18-E05 ; M14-E28 (chiffrement des Secrets). Bancs RKE2 et Talos reconstruits par le code, `capi-essai` au repos (introduction du palier).
**Durée indicative** : 3 h.

**Contexte technique**
- kube-bench **0.16.0** (binaire de la publication GitHub d'Aqua Security, empreinte à vérifier sur `checksums.txt` de la publication). Il est utilisé ici en **aperçu**, depuis le nœud, sans rien corriger : le module 26 l'industrialisera.
- Les référentiels de kube-bench (dossier `cfg/` de l'archive) ne suivent pas Kubernetes de près : relève, dans `cfg/config.yaml`, la version la plus récente pour un Kubernetes générique, pour RKE2 et pour k3s, et compare-les à 1.36.
- Talos n'a ni SSH ni shell. Tout s'observe par `talosctl` : `service`, `processes`, `netstat`, `mounts`, `read`, `get` (consulte `talosctl --help`).
- Procédure de chiffrement de k3s sur un cluster **existant** : page *secrets-encrypt* de la doc k3s (commandes `status`, `enable`, `rotate-keys`).

> ⚠️ **Attention** : le chiffrement des Secrets de `k3s01` touche le cluster de gestion de `capi-essai`. Avant de commencer, refais l'archive à froid de E14 (étape 1) et vérifie-la. Suis la procédure de la doc **dans l'ordre**, avec les redémarrages qu'elle exige : la doc prévient qu'une rotation mal menée peut corrompre le cluster pour de bon.

**Travail demandé**
1. **RKE2.** Relève, sur `rke2-01`, ce que le profil `cis` a changé et vérifie-le par l'observation :
   - utilisateur du processus etcd, droits des fichiers de `/etc/rancher/rke2/` et `/var/lib/rancher/rke2/agent/` ;
   - paramètres noyau exigés et leur source ;
   - politique Pod Security appliquée par défaut et espaces exemptés : tente de créer, dans l'espace `default`, un pod qui demande `hostNetwork: true`, et lis le refus ;
   - NetworkPolicy créées par RKE2 ;
   - mode SELinux de Rocky 10 et contexte des processus RKE2.
2. **kube-bench sur RKE2.** Lance kube-bench sur `rke2-01` (cibles `master`, `node`, `etcd`, `policies`) avec le référentiel RKE2 le plus récent de l'archive, puis avec le référentiel générique le plus récent. Pour les deux passages, compte PASS, FAIL et WARN. Classe **chaque** FAIL : vrai écart, faux positif de chemin ou de version, ou contrôle manuel. Garde les rapports (`--json`) dans `docs/kubernetes/distributions/durcissement/`.
3. **Talos.** Inventorie la surface de `talos-01` :
   - ports en écoute et processus qui les tiennent ;
   - services du système ;
   - systèmes de fichiers montés en lecture seule ;
   - ligne de commande du noyau ;
   - rôles disponibles dans l'API Talos ;
   - politique Pod Security par défaut du serveur d'API.

   Peut-on lancer kube-bench sur Talos ? Essaie ou argumente. Note ce qui le rend difficile et ce qui le rend moins utile.
4. **k3s01, cluster de gestion.**
   - Lance kube-bench avec le référentiel k3s le plus récent, puis relève : l'état du chiffrement (`k3s secrets-encrypt status`), les droits de `/etc/rancher/k3s/k3s.yaml` et de `/var/lib/rancher/k3s/server/token`, l'audit (actif ou non).
   - Chiffre les Secrets de `k3s01` selon la procédure de la doc (MR sur le rôle `k3s` pour l'option du fichier de configuration). Vérifie ensuite qu'un Secret lu directement dans la base SQLite n'apparaît plus en clair : tu as fait la même preuve sur etcd en M14-E28.
5. **Tableau.** `docs/kubernetes/distributions/durcissement.md`. Une ligne par critère, une colonne par distribution : kubeadm (`k8s-par1`, d'après ce que tu as fait au M14), k3s, RKE2, Talos. Critères au minimum :
   - accès à l'OS ;
   - ports exposés ;
   - utilisateur d'etcd ;
   - Pod Security par défaut ;
   - NetworkPolicy par défaut ;
   - chiffrement des Secrets ;
   - audit ;
   - confinement de l'OS (SELinux, AppArmor, système immuable) ;
   - mises à jour de l'OS ;
   - résultat kube-bench (avec sa version de référentiel) ;
   - effort estimé pour atteindre le référentiel CIS.

   Termine par trois lignes « ce que le module 26 devra traiter ».

**Critères de réussite**
- [ ] Sur les trois serveurs RKE2, le profil `cis` est actif, etcd tourne sous l'utilisateur `etcd`, et les paramètres noyau du profil sont appliqués.
- [ ] `k3s01` : `k3s secrets-encrypt status` affiche `Enabled` et une étape de rotation terminée ; l'option est dans le rôle `k3s` sur `main` ; `capi-essai` est toujours vert vu du cluster de gestion.
- [ ] Les rapports kube-bench (RKE2 avec deux référentiels, k3s) sont publiés, et chaque FAIL est classé.
- [ ] `durcissement.md` contient le tableau à quatre colonnes et les critères demandés.

**Vérification** : `lab/bin/check 18 15`. Avant de la lancer : retire Talos s'il est encore là (sa partie est finie), puis réveille `capi-essai` (≈ 28 Go avec RKE2 et `k3s01`) : le contrôle lit RKE2 et vérifie que le cluster de gestion voit toujours `capi-essai` disponible.

<details><summary>Indice 1</summary>

Avec le profil `cis`, RKE2 applique la politique Pod Security par un fichier de configuration d'admission, pas par des étiquettes sur les espaces de noms. Cherche le fichier sous `/etc/rancher/rke2/` et l'argument du serveur d'API qui le désigne (manifeste statique sous `/var/lib/rancher/rke2/agent/pod-manifests/`).
</details>

<details><summary>Indice 2</summary>

kube-bench cherche les fichiers et les processus là où son référentiel le lui dit. Un FAIL sur « le fichier X a les droits 600 » alors que X n'existe pas sur ce nœud n'est pas un écart. Un FAIL sur un argument du serveur d'API, lui, peut l'être. Lis la commande `audit` du contrôle dans le rapport JSON avant de conclure.
</details>

<details><summary>Indice 3</summary>

Pour la preuve du chiffrement sur `k3s01`, la base est un fichier SQLite et kine y range les objets dans une table. Copie la base à chaud dans un dossier temporaire (en `root`), puis interroge la copie, jamais l'original. Un Secret chiffré commence par un préfixe qui nomme le fournisseur, comme dans etcd.
</details>

---

### M18-E16 — Cluster API sur OpenStack (facultatif)  `LIBRE` `★★★★`

> **Ticket PLAT-1916** — *De : Claire Morel* — *Copie : Karim Benali*
> Si on retient Cluster API, il doit fonctionner sur les deux socles qu'on a construits : Proxmox et OpenStack. Fais-moi un essai avec CAPO, le fournisseur OpenStack, sur le projet `plateforme`. Je veux savoir ce qui change pour nous, pas un tutoriel.

**Objectifs pédagogiques**
- Concevoir un cluster de gestion compatible avec un fournisseur donné, à partir de sa matrice de compatibilité et de son contrat Cluster API.
- Créer un cluster de charge de travail sur OpenStack par Cluster API et comparer ce que le fournisseur délègue au cloud (réseau, répartiteur, IP flottantes, images) avec CAPMOX.

**Prérequis** : M10 (profil **openstack** reconstructible, projet `plateforme`, `ext-net`, Octavia), M18-E09, M18-E10, M18-E13.
**Durée indicative** : 6 à 8 h.

**Contexte technique**
- Version cible : CAPO **0.15.x** (PLAN §6). Relève dans le dépôt du fournisseur, **au tag** : la matrice de compatibilité du README, le contrat Cluster API déclaré dans `metadata.yaml` et la version de Cluster API dans `go.mod`. Compare avec le cluster de gestion `k3s01`, qui est figé en Cluster API 1.12 par CAPMOX.
- Le profil openstack (≈ 48 Go avec `ceph-par1`) dépasse l'enveloppe du module : pour cet exercice, **tout** le reste du module est éteint, sauf `m18-dev01` (et `k3s01` si ton choix l'exige). C'est la seule dérogation du module ; écris-la dans le compte rendu.
- OpenStack : `https://openstack.par1.medisphere.internal` (VIP 10.10.50.201), projet `plateforme`, réseau externe `ext-net`, IP flottantes 10.10.52.200-249, Octavia avec le fournisseur OVN (M10).

**Contraintes**
- Les identifiants OpenStack du cluster de gestion sont ceux d'un compte de service dédié du projet `plateforme`, avec des droits limités au projet, jamais `admin`. Ils ne sont dans aucun dépôt.
- Image de nœud construite par image-builder à partir de la même définition qu'en E09 (cible OpenStack ou QEMU puis import dans Glance), avec Kubernetes v1.36.x.
- Cluster `capo-essai` : 1 nœud de contrôle et 1 travailleur, CNI Cilium, point d'accès de l'API sur une IP flottante de `ext-net`. Le choix entre une IP flottante simple et un répartiteur Octavia est argumenté.
- Les nouveaux flux réseau (cluster de gestion → API OpenStack, cluster de gestion → API du cluster de charge de travail) sont ouverts de façon ciblée sur la bordure, puis reportés dans la matrice des flux.
- Manifestes versionnés dans `capi/capo-essai/` de `plateforme/distributions`.
- En fin d'exercice, `capo-essai` est supprimé **par Cluster API**. Aucun serveur, port, volume, groupe de sécurité ni répartiteur `capo-essai` ne reste dans le projet. Le profil openstack est éteint ou détruit comme au M10.

**Critères de réussite**
- [ ] Le choix du couple Cluster API / CAPO et de l'emplacement du cluster de gestion est justifié par des sources lues au tag (README, `metadata.yaml`, `go.mod`).
- [ ] `capo-essai` a eu ses deux nœuds `Ready`, avec une charge témoin, et une capture de `clusterctl describe` est dans le compte rendu.
- [ ] Aucune ressource `capo-essai` ne reste dans le projet `plateforme`.
- [ ] `docs/kubernetes/distributions/capo.md` compare CAPMOX et CAPO sur au moins six points : réseau, adresses, point d'accès de l'API, images, identité, nettoyage, maturité. Il contient les flux ajoutés et la dérogation mémoire.

**Vérification** : `lab/bin/check 18 16` (le contrôle du projet OpenStack n'a lieu que si le profil est allumé ; sinon il est signalé ignoré).

<details><summary>Indice 1</summary>

Deux fournisseurs d'infrastructure peuvent cohabiter dans le même cluster de gestion seulement s'ils acceptent tous les deux la version du *core* Cluster API qui y est installée. Si ce n'est pas le cas, rien n'interdit un second cluster de gestion, éphémère.
</details>

<details><summary>Indice 2</summary>

CAPO crée lui-même le réseau, le sous-réseau, le routeur et les groupes de sécurité du cluster, sauf si tu lui en désignes d'existants. Lis les champs du `OpenStackCluster` qui commencent par `managed` et ceux qui désignent le réseau externe.
</details>

---

### M18-E17 — ADR : stratégie de distribution de MédiSphère  `RED` `★★`

> **Ticket PLAT-1917** — *De : Claire Morel* — *Copie : Karim Benali, Sophie Laurent, Nadia Roussel, Julien Petit*
> Trois besoins sont sur la table : le cluster de production (`k8s-par1`, aujourd'hui en kubeadm), un petit cluster dans l'agence de Lyon (deux ou trois machines, personne sur place), et des clusters de recette éphémères pour les équipes. Tu as tout essayé. Écris l'ADR-0180 : quelle distribution pour quel besoin, comment on gère leur cycle de vie, et ce qu'on ne fera pas. Je le présente au comité d'architecture.

**Objectifs pédagogiques**
- Décider à partir de mesures faites sur le lab (E02 à E15), pas de réputations.
- Distinguer le choix de la **distribution** (comment Kubernetes est assemblé) de celui de l'**outil de cycle de vie** (qui crée, monte et répare les clusters).
- Écrire une décision qui assume ses conséquences : compétences, sauvegardes, supervision, sortie.

**Prérequis** : M18-E01 à M18-E15 (au minimum E03 à E05, E10, E13, E14, E15) ; ADR-0140 et ADR-0141 (M14).
**Durée indicative** : 2 h 30.

**Travail demandé**
Rédige `docs/kubernetes/distributions/adr/ADR-0180-strategie-distribution.md` (gabarit MADR de M00-E33, trois pages au plus), par MR sur `plateforme/medisphere`. L'ADR doit au minimum :
1. Poser le **contexte** : les trois besoins, les contraintes (HDS, souveraineté, équipe de cinq personnes, Proxmox et OpenStack comme socles, Harbor comme seule source d'images, budget mémoire), l'existant (`k8s-par1`, ADR-0140 et ADR-0141).
2. Lister des **critères** pondérés et dire d'où vient chaque mesure. Au minimum :
   - temps d'installation ;
   - empreinte mémoire au repos ;
   - durcissement par défaut (E15) ;
   - montée de version (E06, E07, E13) ;
   - sauvegarde et restauration (E14 : RTO, nombre d'étapes manuelles) ;
   - réparation automatique ;
   - dépendance à un éditeur et pérennité du projet ;
   - compétences de l'équipe et outillage commun (kubectl, Helm, GitOps à venir) ;
   - compatibilité avec l'écosystème du bloc C (Cilium, ceph-csi, CloudNativePG).
3. Évaluer au moins quatre **options** pour chaque besoin : kubeadm (+ Ansible), k3s, RKE2, Talos, et, pour le cycle de vie, Cluster API (CAPMOX, CAPO) contre un outil propre à la distribution (system-upgrade-controller, `talosctl`, rôles Ansible).
4. **Trancher** besoin par besoin. Dire explicitement :
   - si `k8s-par1` change de distribution, et quand ;
   - où vit le cluster de gestion Cluster API, s'il est retenu, comment il est sauvegardé (E14) et qui le surveille ;
   - ce que devient le template 9060/9061 et le compte `wb-capi` à la fin du module.
5. Lister les **conséquences** négatives et les actions, chacune rattachée à un module ou datée. Exemples :
   - deuxième chaîne de sauvegarde ;
   - images de nœuds à reconstruire chaque mois ;
   - CAPMOX en 0.x et sa compatibilité Proxmox VE 9 constatée en E08 ;
   - Talos sans SSH pour l'astreinte ;
   - GitOps au M20 ;
   - supervision au M21 ;
   - durcissement au M26.
6. Dire ce qui ferait **revenir** sur la décision (critères de réexamen).

**Critères de réussite**
- [ ] L'ADR suit le gabarit, tient en trois pages, et contient un tableau critères × options pondéré dont chaque note renvoie à une mesure (exercice, compte rendu) ou à une source.
- [ ] Les trois besoins sont tranchés séparément. Le choix de distribution et celui de l'outil de cycle de vie sont distincts.
- [ ] Le sort de `k8s-par1`, du cluster de gestion, du template et du compte `wb-capi` est écrit.
- [ ] Les conséquences négatives sont rattachées à un module ou à une date, et les critères de réexamen sont posés.

Auto-évaluation : grille fournie dans le corrigé.

<details><summary>Indice 1</summary>

Un critère qui a la même note pour toutes les options ne départage rien : retire-le, ou trouve une mesure qui les distingue. Et une option qui gagne partout est souvent mal évaluée sur la compétence de l'équipe ou sur la sortie.
</details>

<details><summary>Indice 2</summary>

« Cluster API » n'est pas une distribution : un cluster CAPMOX est un cluster kubeadm. Le choix de Cluster API se juge donc sur ce qu'il remplace (OpenTofu + Ansible + runbooks de montée de version) et sur ce qu'il ajoute (un cluster de plus à exploiter, des fournisseurs en 0.x).
</details>

---

### M18-E18 — Un cluster de recette éphémère en temps limité  `CHRONO` `★★★`

> **Ticket DEV-1918** — *De : Julien Petit* — *Copie : Claire Morel*
> La recette partagée est encombrée : deux branches de MédiAgenda attendent leur tour. Si vous savez me donner un cluster jetable, avec MédiAgenda 1.1.0 dessus, déployée par le chart signé, et que je peux jeter après, je prends. Claire veut savoir combien de temps ça prend, de la demande au premier `/sante` vert.

**Règles de l'exercice**
- Conditions d'examen. Tu n'as ni corrigé ni autres notes que **tes** runbooks, ton code et la documentation officielle.
- Durée cible : **60 minutes** entre l'ouverture du dossier (T0) et le service vérifié (T4). La destruction (T5) se fait après le contrôle et se chronomètre à part.
- Tu choisis l'outil selon ce qui marche sur **ton** lab : k3d sur `m18-dev01` ou un cluster Cluster API depuis `k3s01`. Le choix et sa raison sont écrits dans la feuille de temps.
- Tout passe par le code : un fichier de cluster versionné dans `plateforme/distributions`, un fichier de valeurs versionné, une commande pour créer et une pour détruire (Taskfile). Aucun `kubectl edit` ni `helm upgrade --set` ne doit rester en place à T4.

**Prérequis** : M18-E02 (k3d) ou M18-E10/E13 (Cluster API) ; M17-E08 (chart publié et signé), M17-E18 (MédiAgenda 1.1.0) ; M16 (CloudNativePG).
**Durée** : 60 minutes chronométrées + 20 minutes de retour d'expérience.

**Dossier** : [`ressources/E18-dossier-chrono.md`](../ressources/E18-dossier-chrono.md) (le besoin, les exigences, la feuille de temps). Lis-le à T0, pas avant.

**Critères de réussite**
- [ ] Toutes les exigences du dossier sont satisfaites à T4 (vérification ci-dessous).
- [ ] La feuille de temps est remplie (T0 à T5), avec les gestes manuels éventuels et leur raison. Le temps T0 → T4 est inférieur à 60 minutes. Sinon, améliore ton code et refais l'exercice.
- [ ] Après T5, le cluster éphémère n'existe plus et son kubeconfig est supprimé.
- [ ] Le retour d'expérience (une demi-page) est rédigé et versé au dossier de l'ADR-0180.

**Vérification** : `lab/bin/check 18 18` (à lancer à T4, avant la destruction). Le contrôle interroge `/sante` à l'adresse de `WB_M18_RECETTE_URL` (`lab/lab.env`, par défaut `http://m18-dev01.par1.medisphere.internal:8080`) : si tu choisis Cluster API, renseigne-la avec l'adresse notée dans la feuille de temps.

**Pour aller plus loin** (facultatif) : refais l'exercice avec l'autre outil et compare les deux temps. Lequel des deux tiendrait si cinq équipes demandaient chacune un cluster le même jour ?
