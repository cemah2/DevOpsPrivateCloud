# Module 18 — Palier 2 : Opérationnel

Le palier 1 a monté chaque distribution une fois. Ce palier les **exploite** : on corrige un cluster Talos par des *patches* versionnés et on le monte de version sans jamais s'y connecter ; on donne à k3s la haute disponibilité et des mises à jour automatiques, comme il les aurait à l'agence. Puis on construit Cluster API pièce par pièce : les concepts et le cluster de gestion amorcé dans kind (avec la vérification préalable de compatibilité entre CAPMOX et Proxmox VE 9), l'image de nœud, un premier cluster de charge de travail `capi-essai` sur le VLAN 40, la revue des manifestes de Lucas, et enfin le **pivot** du cluster de gestion vers `k3s01`, qui devient durable.

> **Rappels du module** (introduction) : les VMs passent par l'état `envs/m18` (variables `groupes` et `k3s_ha_noeuds`) ; une famille qu'on ne sert plus est **retirée**, pas arrêtée ; les fichiers d'accès vont dans `~/.config/workbook/m18/` (600) ; tout est relu en MR (`plateforme/distributions`, `plateforme/ansible`, `plateforme/infra`, `plateforme/images`) ; aucune vérification TLS désactivée (deux outils de ce palier le font par défaut : CAPMOX et le gabarit Proxmox d'image-builder). `k8s-par1` reste arrêté.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Talos | `talos-essai`, `talos-01` (10.10.99.85, contrôle), `talos-02/03` (.86, .87) ; v1.14.1 → **v1.14.2** ; Kubernetes 1.36.4 → **1.36.5** ; installeur `factory.talos.dev/nocloud-installer/<schéma>:<version>` ; `talos/` de `plateforme/distributions` |
| Banc k3s HA | `k3s-ha01..03` (5191-5193, clones liés, `vsandbox` DHCP, 2 Go), etcd intégré ; k3s v1.36.4+k3s1 → v1.36.5+k3s1 par system-upgrade-controller **v0.20.2** ; `~/.config/workbook/m18/k3s-ha.kubeconfig` |
| Cluster API | CAPI / clusterctl **v1.12.11**, CAPMOX **v0.9.1**, IPAM *in-cluster* **v1.1.1** ; repli : fournisseur Docker (CAPD) v1.12.11 |
| Cluster de gestion | kind `gestion` sur `m18-dev01` (E08-E11), API `https://m18-dev01.par1.medisphere.internal:6443`, `~/.config/workbook/m18/kind-gestion.kubeconfig` ; puis `k3s01` (E12) |
| Compte Proxmox | `wb-capi@pve`, jeton `wb-capi@pve!capi`, rôles `WBCapi` (pool `lab`) et `WBCapiAudit` ; stockage dédié `capi-iso` ; `~/.config/workbook/pve-capi.env` (`PROXMOX_URL`, `PROXMOX_TOKEN`, `PROXMOX_SECRET`) |
| Image de nœud | template **9060** `tpl-capi-ubuntu2404-k136` (Ubuntu 24.04.4, Kubernetes 1.36.4), étiquettes `capi`, `k8s-v1.36.4`, puis `current` ; image-builder **v0.1.55** sur `m18-dev01`, jeton `wb-packer@pve!packer` (M03) |
| `capi-essai` | espace `capi-essai` du cluster de gestion ; 1 nœud de contrôle + 2 travailleurs ; VMID 5180-5189 ; adresses 10.10.40.150-169 ; VIP 10.10.40.210 ; Cilium 1.20.2 par ClusterResourceSet ; `~/.config/workbook/m18/capi-essai.kubeconfig` |
| Flux à ouvrir (E08) | `m18-dev01`, `k3s01` → `pve01:8006` (bordure + IPSet `capi` du pare-feu Proxmox) ; → 10.10.40.150-169 et .210, port 6443 |
| Documentation | `docs/kubernetes/distributions/` : `talos.md`, `k3s.md` (HA), `capmox-pve9.md`, `image-noeud.md`, `cluster-api.md` |

Durée indicative du palier : 11 à 15 heures. Ordre conseillé :

```
E06 (juste après E05)      E07 (après E03)
E08 ─ E09 ─ E10 ─ E11 ─ E12
```

---

### M18-E06 — Talos : correctifs de configuration et montée de version  `LAB` `★★★`

> **Ticket CHG-1906** — *De : Nadia Roussel*
> Si on garde Talos, je veux savoir ce qu'on fait le jour où il faut changer un réglage sur tous les nœuds, ou appliquer un correctif de sécurité. Sur le cluster d'essai, trois changements : l'heure du lab au lieu d'un serveur public, les images par notre Harbor, et plus aucune donnée envoyée chez l'éditeur. Puis la montée de version de Talos et de Kubernetes, nœud par nœud, avec une vraie procédure. Et je veux que le dépôt dise toujours la vérité sur ce qui tourne.

**Objectifs pédagogiques**
- Modifier la configuration d'un cluster Talos par des *patches* versionnés (documents multi-documents de Talos 1.14 : ajout, fusion, suppression), en dry-run d'abord.
- Monter Talos (image entière, schéma A/B) et Kubernetes (`upgrade-k8s`) de version, sans SSH, en gardant le dépôt cohérent avec les nœuds.
- Comprendre ce qui redémarre et ce qui ne redémarre pas.

**Prérequis** : M18-E05 (cluster `talos-essai` sain).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Trois *patches* communs, un par sujet, dans `talos/patches/commun/` (appliqués par `generer.sh` à tous les nœuds), plus un *patch* pour les travailleurs dans `talos/patches/worker/` :
  - temps : la passerelle de `vsandbox` (10.10.99.1) comme seul serveur NTP ;
  - découverte : plus de service de découverte public ;
  - miroirs : `docker.io`, `quay.io`, `ghcr.io`, `registry.k8s.io` par le cache Harbor (mêmes chemins qu'au M14-E19), et la racine MédiSphère reconnue par les nœuds ; la racine n'est **pas** recopiée dans le dépôt : elle est lue sur `adm01` (`/usr/local/share/ca-certificates/medisphere-root-ca.crt`) au moment de la génération ;
  - travailleurs : étiquettes `node-role.kubernetes.io/worker=""` et `medisphere.internal/distribution=talos`.
- Montée de version visée : Talos **v1.14.2**, Kubernetes **v1.36.5**. Talos 1.14 ne publie plus d'installeur sur `ghcr.io` : l'installeur vient de l'Image Factory, **avec le même schéma** que l'image d'origine (sinon l'extension `qemu-guest-agent` disparaît).
- Un seul nœud de contrôle : sa montée de version coupe l'API Kubernetes et l'API Talos du cluster pendant son redémarrage. Prévois-le dans la procédure (et dis-le à Nadia).

**Travail demandé**
1. Écris les *patches*. Pour chacun, cherche dans la configuration générée si le document existe déjà : le *patch* doit-il l'ajouter, le fusionner ou le supprimer ? (Lis la page *Configuration Patches* de Talos 1.14 et la carte des documents.)
2. Étends `generer.sh` pour qu'il ajoute la racine MédiSphère (document approprié, construit à la volée). Régénère, valide.
3. Applique d'abord en **dry-run** sur chaque nœud, lis le différentiel, puis applique pour de bon. Pour chaque changement, note si le nœud a redémarré, et vérifie :
   ```
   admin@adm01:~/src/distributions$ talos/appliquer.sh talos-02 --essai
   admin@adm01:~$ talosctl -n 10.10.99.86 get timeservers
   admin@adm01:~$ talosctl -n 10.10.99.86 list -r /etc/cri/conf.d        # où Talos écrit la configuration des registres
   admin@adm01:~$ talosctl -n 10.10.99.86 get members
   ```
   Démontre qu'une image publique est désormais tirée par Harbor (un pod `docker.io/library/busybox:1.37` dans un espace d'essai, puis le journal du projet `dockerhub`).
4. **Montée de version de Talos.** Écris `talos/monter.sh` (ou une procédure équivalente) : nœud de contrôle d'abord, puis chaque travailleur, un par un, santé du cluster vérifiée entre deux nœuds. Avant de lancer, change `versions.env` (MR) : pourquoi **avant** ? Pendant la montée de `talos-01`, observe ce qui reste disponible (pods des travailleurs, API). Après : `talosctl get extensions` montre-t-il toujours l'agent QEMU ?
   > ⚠️ **Attention** : `talosctl upgrade` redémarre le nœud. Un seul nœud à la fois, et jamais sans que `talosctl health` soit revenu vert. Retour arrière possible par `talosctl rollback` (partition précédente), à connaître avant de commencer.
5. **Montée de Kubernetes.** `talosctl upgrade-k8s` en `--dry-run`, lis le plan, puis applique. Ensuite, régénère la configuration et vérifie par `appliquer.sh <nœud> --essai` qu'appliquer le dépôt ne changerait **plus rien** sur aucun nœud.
6. Complète `talos.md` (procédure de changement, procédure de montée de version, ce qui redémarre) et `mesures.md` (durée de la montée de version, indisponibilité observée de l'API). Une fois `lab/bin/check 18 06` vert, retire `"talos"` de `groupes` (le palier 3 reconstruit le cluster avec le même bundle de secrets).

**Critères de réussite**
- [ ] Les trois nœuds sont en Talos v1.14.2, avec l'extension `qemu-guest-agent` et le schéma d'origine.
- [ ] Les trois kubelets et le plan de contrôle sont en Kubernetes v1.36.5.
- [ ] Chaque nœud a 10.10.99.1 comme serveur de temps, les quatre miroirs Harbor, la racine MédiSphère, et plus de service de découverte.
- [ ] `talos-02` et `talos-03` portent les deux étiquettes de travailleur.
- [ ] `plateforme/distributions` (`main`) contient les *patches*, `versions.env` en v1.14.2 / 1.36.5 et la procédure de montée de version ; aucun fichier généré.
- [ ] `talos.md` décrit la procédure de changement et de montée de version.

**Vérification** : `lab/bin/check 18 06`

<details><summary>Indice 1</summary>

Un *patch* stratégique est un fragment de documents : un document absent de la configuration est **ajouté**, un document présent (même `kind`, même `name` s'il est nommé) est **fusionné**, et `$patch: delete` retire un document entier. Cherche `kind: DiscoveryServiceConfig` dans `controlplane.yaml`.
</details>

<details><summary>Indice 2</summary>

`talosctl apply-config` accepte `--dry-run` : il compare la configuration envoyée à celle du nœud et dit si un redémarrage serait nécessaire. Le mode `auto` (par défaut) n'en déclenche que si le changement l'exige.
</details>

<details><summary>Indice 3</summary>

`talosctl upgrade-k8s` modifie la configuration machine **des nœuds** (images du kubelet et du plan de contrôle). Si ton dépôt garde l'ancienne version, la prochaine application du dépôt redescend les nœuds.
</details>

---

### M18-E07 — k3s : haute disponibilité intégrée et mises à jour automatiques  `LAB` `★★★`

> **Ticket PLAT-1907** — *De : Claire Morel*
> Si l'agence de Lyon grossit, un seul serveur ne suffira plus. Montre-moi ce que donne k3s sur trois machines, sans base de données externe, et comment il se met à jour tout seul la nuit sans que personne se déplace. Fais-le sur des VMs jetables : je ne veux pas voir trois machines de plus traîner après.

**Objectifs pédagogiques**
- Monter un cluster k3s à trois serveurs avec etcd intégré (`--cluster-init`), en réutilisant le rôle `k3s`.
- Créer et détruire un banc de VMs jetables par le code (clones liés, hors NetBox, inventaire statique).
- Installer le *system-upgrade-controller* et écrire un plan de montée de version (version, concurrence, isolement, fenêtre).
- Observer etcd intégré : membres, perte d'un serveur.

**Prérequis** : M18-E03 (rôle `k3s`).
**Durée indicative** : 3 h.

**Contexte technique**
- VMs `k3s-ha01..03` (5191-5193) : clones **liés** de l'image dorée Debian 13 `current` (règle M03 : clones liés pour le jetable), 2 vCPU, 2 Go, 20 Gio, `vsandbox` DHCP, MAC `bc:24:11:99:18:91` à `:93`, étiquettes `env-m18`, `role-k3s-ha`. `vm-noeud` refuse ces VMID (plage 2000-2999) et inscrirait les VMs dans NetBox : écris une ressource dédiée dans `envs/m18` (`k3s-ha.tf`), pilotée par une variable `k3s_ha_noeuds`, et un inventaire Ansible **statique** (`inventories/lab/m18-k3s-ha.yml`, groupe `k3s_ha`).
- Version installée : **v1.36.4+k3s1** ; version visée par le plan : **v1.36.5+k3s1**. Le script `install.sh` des deux tags est le même (même empreinte).
- `k3s-ha01` amorce etcd ; `k3s-ha02` et `k3s-ha03` le rejoignent par `https://k3s-ha01.par1.medisphere.internal:6443`. Pas de répartiteur : c'est une limite à noter.
- Jeton : Vault `lab`, `vault_k3s_jeton_k3s_ha` (`group_vars/k3s_ha/vault-lab.yml`).
- system-upgrade-controller **v0.20.2**, manifestes pris à l'URL de la version (`https://github.com/rancher/system-upgrade-controller/releases/download/v0.20.2/…`), plan dans `k3s/suc/` de `plateforme/distributions`.
- Le budget : six Go de plus pendant l'exercice (RKE2 et Talos sont déjà retirés).

**Travail demandé**
1. Écris `k3s-ha.tf` (clone lié, même matériel que ci-dessus) et applique avec les trois noms. MR.
2. Écris l'inventaire statique, les variables du groupe `k3s_ha` et le jeu du playbook `m18.yml` : socle commun, puis rôle `k3s` en série, `k3s-ha01` en premier. Une variable du rôle doit empêcher Ansible de « corriger » la version quand le contrôleur de montée l'aura changée : laquelle, et pourquoi ?
3. Joue le playbook, récupère `~/.config/workbook/m18/k3s-ha.kubeconfig` (contexte `k3s-ha`). Observe :
   ```
   admin@k3s-ha01:~$ sudo k3s kubectl get nodes
   admin@k3s-ha01:~$ sudo ls /var/lib/rancher/k3s/server/db/
   admin@k3s-ha01:~$ sudo k3s etcd-snapshot list
   ```
   Où sont les données ? Combien de membres etcd ? Les trois nœuds sont-ils tous nœuds de contrôle ?
4. **Perte d'un serveur.** Arrête `k3s-ha03` (`qm shutdown 5193`) : l'API répond-elle ? Arrête aussi `k3s-ha02` : et maintenant ? Redémarre-les et vérifie le retour à trois membres.
   > ⚠️ **Attention** : avec deux serveurs sur trois arrêtés, etcd perd son quorum : l'API ne répond plus et rien ne s'écrit. Redémarre-les tout de suite après l'observation ; ne fais jamais cela sur un cluster qui compte.
5. **Mises à jour automatiques.** Installe le contrôleur (kustomize avec les deux URL de la version et ton plan), écris un plan `serveurs` : version explicite, un nœud à la fois, nœud isolé pendant sa montée, une fenêtre horaire (en semaine, en journée pour l'essai). Applique, puis suis la montée :
   ```
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/k3s-ha.kubeconfig -n system-upgrade get plans,jobs,pods -w
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/k3s-ha.kubeconfig get nodes -w
   ```
   Relance ensuite le playbook : il ne doit rien changer à la version.
6. Note dans `k3s.md` la section « haute disponibilité et mises à jour automatiques » (ce qu'il faudrait de plus à l'agence : adresse d'enregistrement stable, fenêtre, sauvegarde) et la mesure dans `mesures.md`. Une fois `lab/bin/check 18 07` vert, **détruis le banc** (`k3s_ha_noeuds = []`) et supprime `k3s-ha.kubeconfig`.

**Critères de réussite**
- [ ] `k3s-ha01..03` (5191-5193) sont des clones liés de l'image Debian `current`, avec les MAC, la mémoire et les étiquettes demandées.
- [ ] Le cluster a trois nœuds `Ready`, de rôle `control-plane,etcd`, en **v1.36.5+k3s1** ; etcd intégré a trois membres (dossier `db/etcd` sur chaque nœud).
- [ ] system-upgrade-controller v0.20.2 tourne dans `system-upgrade` ; le plan `serveurs` vise v1.36.5+k3s1, concurrence 1, `cordon`, avec une fenêtre, et a été appliqué aux trois nœuds.
- [ ] Le rôle `k3s` ne touche plus la version sur ce banc (playbook rejoué sans changement).
- [ ] `k3s-ha.tf`, `m18-k3s-ha.yml`, `group_vars/k3s_ha/` et `k3s/suc/` sont sur `main` ; `k3s.md` a sa section HA.

**Vérification** : `lab/bin/check 18 07` (à lancer **avant** de détruire le banc)

<details><summary>Indice 1</summary>

Avec `bpg/proxmox`, un clone lié s'écrit `clone { full = false … }`. La source de données `proxmox_virtual_environment_vms` filtrée par étiquettes (`gold`, `debian13`, `current`) et `template = true` retrouve l'image dorée, comme dans `vm-noeud`.
</details>

<details><summary>Indice 2</summary>

Le *system-upgrade-controller* lance, pour chaque nœud choisi par le plan, un Job privilégié qui remplace le binaire k3s sur l'hôte et redémarre le service. Il suit l'avancement par des étiquettes sur les nœuds (`plan.upgrade.cattle.io/<plan>`) ; la documentation de k3s (« Automated Upgrades ») donne un plan complet à adapter.
</details>

<details><summary>Indice 3</summary>

Hors de la fenêtre, le contrôleur ne crée aucun Job : si rien ne se passe, regarde l'heure, le fuseau de la fenêtre, et le statut du plan (`kubectl get plan serveurs -o yaml`).
</details>

---

### M18-E08 — Cluster API : concepts et cluster de gestion  `LAB` `★★`

> **Ticket PLAT-1908** — *De : Claire Morel*
> Julien veut des clusters de recette créés à la demande. La piste sérieuse, c'est Cluster API sur notre Proxmox, avec le fournisseur d'IONOS (CAPMOX). Avant d'y passer une semaine : vérifie que ça marche **chez nous**, avec Proxmox VE 9 et des droits minimaux. Leur documentation ne parle pas de la 9. Je veux une conclusion écrite, et un plan B si c'est non.

**Objectifs pédagogiques**
- Situer les objets et les fournisseurs de Cluster API (cœur, amorçage, plan de contrôle, infrastructure, IPAM) et le rôle du cluster de gestion.
- Amorcer un cluster de gestion dans kind et y installer les fournisseurs à des versions fixées.
- Mener une **vérification préalable** de compatibilité (versions, droits Proxmox VE 9, appels d'API réels avec le jeton du fournisseur) et décider d'un repli.
- Ouvrir les flux nécessaires de façon ciblée.

**Prérequis** : M18-E02 (`m18-dev01`, clusterctl), M18-E03 (`k3s01`, futur cluster de gestion) ; M03-E02 et M03-E15 (comptes Proxmox à droits minimaux, IPSet du pare-feu Proxmox).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Versions : Cluster API **v1.12.11** (le README de CAPMOX v0.9.1 n'annonce que CAPI 1.11 et 1.12, alors que CAPI 1.14 existe), CAPMOX **v0.9.1**, IPAM *in-cluster* **v1.1.1**. Toujours explicites dans `clusterctl init` (sinon il prend la dernière version de chaque fournisseur).
- Cluster de gestion d'amorçage : kind `gestion` sur `m18-dev01`, un nœud, image kind à l'empreinte de E02. Son API doit être joignable depuis `adm01` et les vérifications : `https://m18-dev01.par1.medisphere.internal:6443` (port fixe, nom dans le certificat). Kubeconfig : `~/.config/workbook/m18/kind-gestion.kubeconfig` sur `adm01`, contexte `kind-gestion`.
- **Aucun identifiant Proxmox dans le contrôleur** : CAPMOX accepte de démarrer sans identifiants globaux, chaque cluster apportant les siens (`credentialsRef`, E10). C'est ce que tu fais.
- Compte Proxmox : `wb-capi@pve`, jeton `wb-capi@pve!capi` (séparation des privilèges, expiration), ACL sur l'utilisateur **et** le jeton (M03). Rôle personnalisé `WBCapi` sur `/pool/lab` ; `Sys.Audit` sur `/` (sans propagation) et `/nodes` ; `PVEDatastoreUser` sur `local-nvme` ; `PVESDNUser` sur `/sdn/zones/lab/vk8s`. CAPMOX téléverse une ISO cloud-init par VM dans **le premier stockage de contenu `iso` qu'il voit** : donne-lui un stockage dédié, **`capi-iso`** (répertoire `/mnt/hdd-bulk/capi-iso`, contenu `iso` seulement), avec `PVEDatastoreAdmin` sur ce seul stockage (téléverser et supprimer ses ISO), et aucun droit sur `hdd-bulk`.
- La liste des privilèges de `WBCapi` se déduit des appels de CAPMOX (clonage, configuration, alimentation, agent QEMU, exécution de `cloud-init status` par l'agent). En Proxmox VE 9, `VM.Monitor` n'existe plus.
- Identifiants sur `adm01` et `m18-dev01` : `~/.config/workbook/pve-capi.env` (600) : `PROXMOX_URL=https://<IP-PVE01>:8006`, `PROXMOX_TOKEN=wb-capi@pve!capi`, `PROXMOX_SECRET=<SECRET>`. Ancre TLS de `pve01` : `~/.config/workbook/pve-root-ca.pem` (M02-E08), à installer sur `m18-dev01` et `k3s01`.
- Flux : `m18-dev01` et `k3s01` vers `pve01:8006` (bordure **et** pare-feu Proxmox : IPSet dédié `capi`), et vers 10.10.40.150-169 et 10.10.40.210 en 6443 (E10).
- **Repli** si la vérification échoue : le fournisseur Docker (CAPD, `--infrastructure docker:v1.12.11`) dans un cluster kind qui monte le socket Docker de `m18-dev01` ; les exercices E10 à E12 se font alors avec des « machines » conteneurs.

**Travail demandé**
1. **Concepts.** Lis « Concepts » du livre de Cluster API et `clusterctl generate provider --infrastructure proxmox:v0.9.1 --describe`. Dessine dans `docs/kubernetes/distributions/cluster-api.md` les objets d'un cluster (Cluster, ProxmoxCluster, KubeadmControlPlane, MachineDeployment, MachineSet, Machine, ProxmoxMachine, KubeadmConfig) et qui crée qui.
2. **Le compte Proxmox.** Écris `capi/pve-compte-capi.sh` (dans `plateforme/distributions`, sur le modèle de `pve-packer-compte.sh` du M03), relis-le, lance-le sur `pve01`. Range le secret.
   > ⚠️ **Attention** : le script modifie `pve01` (nouveau stockage dans `/etc/pve/storage.cfg`, rôles, ACL). Relis-le avant ; retour arrière : `pveum user delete wb-capi@pve`, `pveum role delete WBCapi`, `pveum role delete WBCapiAudit`, `pvesm remove capi-iso`.
3. **Les flux.** Ajoute les deux règles à la matrice de la bordure (`group_vars/role_routeur/pare_feu.yml`), l'IPSet `capi` et la règle 8006 au pare-feu de `pve01` (méthode de M03-E15), les lignes de `matrice-flux.md`. Installe l'ancre de `pve01` sur `m18-dev01` et `k3s01` (jeu du playbook).
4. **La vérification préalable.** Écris `capi/preflight-pve.sh` : avec le **jeton de CAPMOX**, depuis `m18-dev01`, enchaîne les appels qu'il fera (version, ressources, état du nœud, stockages `iso` visibles, téléversement puis suppression d'une ISO dans `capi-iso`, clonage complet d'un template du pool vers le VMID 5189, configuration de la VM, suppression), TLS vérifié, et s'arrête à la première réponse inattendue.
   > ⚠️ **Attention** : le script crée puis supprime une VM. Il ne doit **jamais** supprimer une VM qu'il n'a pas créée : vérifie avant le clonage que 5189 est libre, et ne nettoie que ce que le script a créé.
5. **Le cluster de gestion.** Écris `kind/gestion.yaml`, crée le cluster, récupère le kubeconfig sur `adm01` (serveur `https://m18-dev01.par1.medisphere.internal:6443`). Écris `capi/versions.env` et `capi/init.sh` (versions explicites, aucune variable `PROXMOX_*`), installe :
   ```
   admin@adm01:~/src/distributions$ capi/init.sh ~/.config/workbook/m18/kind-gestion.kubeconfig proxmox
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/kind-gestion.kubeconfig get providers -A
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m18/kind-gestion.kubeconfig get crd | grep -c x-k8s.io
   ```
   Lis le Secret `capmox-manager-credentials` (ses clés, pas besoin des valeurs) et les variables d'environnement du déploiement `capmox-controller-manager` : que se passerait-il si tu avais exporté `PROXMOX_URL`, `PROXMOX_TOKEN` et `PROXMOX_SECRET` avant `clusterctl init` ? Que vaut alors la vérification TLS ?
6. **La conclusion.** `docs/kubernetes/distributions/capmox-pve9.md` : ce que dit l'amont, ce qui a été créé, le résultat de chaque étape, la décision (CAPMOX ou repli), et la procédure de repli (fichier `kind/gestion-capd.yaml` prêt, même s'il ne sert pas).

**Critères de réussite**
- [ ] Le compte `wb-capi@pve`, son jeton `capi` (séparation des privilèges, expiration), les rôles `WBCapi` et `WBCapiAudit`, le stockage `capi-iso` et les ACL existent sur `pve01` ; le jeton n'a aucun droit sur `hdd-bulk` ; `~/.config/workbook/pve-capi.env` est en 600.
- [ ] Depuis `m18-dev01`, l'API de `pve01` répond avec TLS vérifié ; l'IPSet `capi` et la règle 8006 existent dans le pare-feu de `pve01` ; la matrice de la bordure contient les deux règles.
- [ ] Le cluster kind `gestion` répond depuis `adm01` sur `https://m18-dev01.par1.medisphere.internal:6443`, kubeconfig en 600.
- [ ] Les fournisseurs `cluster-api` et `kubeadm` (×2) en v1.12.11, `proxmox` en v0.9.1, `in-cluster` en v1.1.1 sont installés et leurs contrôleurs disponibles ; CAPMOX n'a **aucun** identifiant global.
- [ ] `capmox-pve9.md` est sur `main` avec une décision explicite ; `capi/` contient `versions.env`, `init.sh`, `pve-compte-capi.sh`, `preflight-pve.sh`.

**Vérification** : `lab/bin/check 18 08`

<details><summary>Indice 1</summary>

Pour exposer l'API d'un cluster kind hors de l'hôte, regarde `networking.apiServerAddress` et `apiServerPort` dans la configuration de kind ; pour ajouter un nom au certificat, un `kubeadmConfigPatches` sur la `ClusterConfiguration` (`apiServer.certSANs`).
</details>

<details><summary>Indice 2</summary>

`pveum role add` refuse un privilège qui n'existe pas : c'est un premier test de compatibilité, gratuit. La page *User Management* de Proxmox VE 9 liste les privilèges `VM.GuestAgent.*`. Pour la liste de `WBCapi`, pars des droits de `PVEVMAdmin` et retire ce que CAPMOX n'appelle jamais (console, sauvegarde, migration, instantanés…).
</details>

<details><summary>Indice 3</summary>

Le déploiement de CAPMOX lit ses identifiants globaux dans un Secret rendu par `clusterctl` à partir des variables `PROXMOX_*` ; vides, il démarre sans client et attend un `credentialsRef` par cluster. La page *advanced setups* de CAPMOX dit ce qu'il fait par défaut de la vérification TLS.
</details>

---

### M18-E09 — Une image de nœud pour Cluster API  `LAB` `★★★`

> **Ticket PLAT-1909** — *De : Karim Benali*
> CAPMOX clone un template ; ce template, c'est nous qui le fabriquons, comme nos images dorées. Le projet image-builder de Kubernetes sait le faire pour Proxmox. Je veux un template Ubuntu 24.04 avec Kubernetes 1.36.4, construit par le code, avec le même compte Packer que nos images, et sans désactiver la vérification TLS au passage — je sais que leur gabarit le fait.

**Objectifs pédagogiques**
- Construire une image de nœud Kubernetes avec image-builder (Packer + Ansible) pour Proxmox, à une version fixée.
- Adapter un outil amont sans le *forker* : fichier de variables, corrections locales affichées et justifiées.
- Relier le template à la description du cluster (version de Kubernetes, étiquettes, stockage).

**Prérequis** : M03 (Packer, `wb-packer@pve!packer`, ISO sur `hdd-bulk`), M18-E08 (flux `m18-dev01` → `pve01`, ancre TLS).
**Durée indicative** : 3 h (dont 30 à 45 min de construction).

**Contexte technique**
- image-builder **v0.1.55**, cloné à l'étiquette sur `m18-dev01` dans `~/m18/image-builder` (hors dépôt) ; cible `make build-proxmox-ubuntu-2404` dans `images/capi/` ; `make deps-proxmox` installe la version de Packer et les greffons qu'il attend.
- Variables d'environnement d'image-builder pour Proxmox : `PROXMOX_URL` (avec `/api2/json`), `PROXMOX_USERNAME` (identifiant **du jeton**), `PROXMOX_TOKEN` (**secret** du jeton), `PROXMOX_NODE`, `PROXMOX_ISO_POOL`, `PROXMOX_BRIDGE`, `PROXMOX_STORAGE_POOL`. Attention : CAPMOX appelle `PROXMOX_TOKEN` l'identifiant et `PROXMOX_SECRET` le secret (la documentation de dépannage de CAPMOX le signale).
- Compte : `wb-packer@pve!packer` du M03 (`~/.config/workbook/pve-packer.env`, à copier en 600 sur `m18-dev01`). Il n'a de droits que sur le pool `lab`, `local-nvme`, `vsandbox` et en **lecture** sur `hdd-bulk`.
- Le template : VMID **9060**, nom `tpl-capi-ubuntu2404-k136`, Kubernetes **v1.36.4** (paquets `1.36.4-1.1` de pkgs.k8s.io), disque **brut** (`local-nvme` est un stockage bloc : LVM-thin ou ZFS), étiquettes `capi` et `k8s-v1.36.4` à la construction, `current` posée **après** contrôle.
- L'ISO Ubuntu 24.04.4 (`ubuntu-24.04.4-live-server-amd64.iso`, empreinte SHA-256 `e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433`, celle du fichier `ubuntu-2404.json` d'image-builder v0.1.55) est déposée **à l'avance** sur `hdd-bulk` (le jeton de Packer ne peut pas y écrire).
- La VM de build est sur `vsandbox` (DHCP) ; elle télécharge sa configuration d'installation automatique au serveur HTTP de Packer sur `m18-dev01` (même VLAN), puis Packer s'y connecte en SSH et y joue les rôles Ansible d'image-builder.

**Travail demandé**
1. Dépose l'ISO sur `hdd-bulk` depuis `pve01` (l'API `download-url` du stockage vérifie l'empreinte).
2. Clone image-builder à l'étiquette, lis `images/capi/packer/proxmox/packer.json` et `ubuntu-2404.json`, et la page *Building Images for Proxmox VE*. Repère : comment le nom et le VMID du template sont fixés ; d'où viennent les versions de Kubernetes ; ce qui empêche le jeton `wb-packer` de créer la VM de build ; ce qui désactive la vérification TLS.
3. Dans `plateforme/images`, crée `capi/` : un fichier de variables Packer (`ubuntu-2404-k136.json`, passé par `PACKER_VAR_FILES`) et un script `construire.sh` qui clone à l'étiquette, applique **et affiche** les corrections locales du gabarit (TLS vérifié ; pool `lab` ; étiquettes), charge les identifiants depuis le fichier 600 sans les afficher, et lance la construction. MR.
4. Valide (`construire.sh --valider`), puis construis. Pendant la construction, suis la VM sur `pve01` (`qm list`, console) et les étapes Ansible dans la sortie.
5. Contrôle le template : Kubernetes, containerd, `cloud-init` et agent QEMU installés, aucune clé SSH ni mot de passe de build laissé, configuration Proxmox (agent, disque brut, pool, étiquettes). Clone-le à la main en 5188 (clone lié, sur `vsandbox`), démarre, connecte-toi, vérifie `kubeadm version`, `kubelet --version`, `crictl --version`, puis supprime la VM.
6. Pose l'étiquette `current`, écris `docs/kubernetes/distributions/image-noeud.md` (construction, contrôle, une image par version de Kubernetes, durée de vie des templates).

**Critères de réussite**
- [ ] Le template 9060 `tpl-capi-ubuntu2404-k136` existe, dans le pool `lab`, sur `local-nvme`, disque brut, agent activé, étiquettes `capi`, `current`, `k8s-v1.36.4` ; c'est le seul template étiqueté `capi` et `current`.
- [ ] Aucune VM de build ni VM d'essai ne reste (pas de VMID 5188 ni de VM `ubuntu-2404` hors template).
- [ ] `plateforme/images` (`main`) contient `capi/ubuntu-2404-k136.json` (VMID, nom, versions 1.36.4, disque brut) et `capi/construire.sh`, qui remet la vérification TLS.
- [ ] `image-noeud.md` est sur `main`.

**Vérification** : `lab/bin/check 18 09`

<details><summary>Indice 1</summary>

Les fichiers de variables passés par `PACKER_VAR_FILES` sont ajoutés **après** ceux de l'OS sur la ligne de commande de Packer : leurs valeurs l'emportent. Le nom du template vient de la variable `artifact_name`, le VMID de `vmid`.
</details>

<details><summary>Indice 2</summary>

Certaines valeurs du gabarit ne sont **pas** des variables (elles sont écrites en dur dans `builders[0]`). Pour les changer sans *forker*, modifie le fichier dans ton clone avec `jq`, montre le `git diff`, et remets-le à l'état d'origine avant chaque construction (`git checkout -- …`).
</details>

<details><summary>Indice 3</summary>

Le jeton de Packer a `VM.Allocate` sur `/pool/lab` seulement : Proxmox n'accepte la création d'une VM que si la requête la place dans ce pool. Le greffon Proxmox de Packer a une option pour cela ; le gabarit d'image-builder ne la renseigne pas.
</details>

---

### M18-E10 — CAPMOX : un cluster de charge de travail sur Proxmox  `LAB` `★★★`

> **Ticket DEV-1910** — *De : Julien Petit*
> On y est presque : je voudrais un premier cluster créé par Cluster API, pour voir à quoi ça ressemble de notre côté. Un nœud de contrôle, deux travailleurs, notre Kubernetes 1.36, nos images par Harbor. Si ça marche, on en fera un par équipe de recette.

**Objectifs pédagogiques**
- Décrire un cluster de charge de travail avec les objets de Cluster API et de CAPMOX (API `v1alpha2`), et le créer.
- Fournir les identifiants au fournisseur par cluster, avec vérification TLS, sans secret dans le dépôt.
- Maîtriser les adresses (IPAM *in-cluster*, VIP du plan de contrôle par kube-vip), les VMID et les étiquettes des VMs créées.
- Installer le CNI par un `ClusterResourceSet` ; suivre la création des machines et diagnostiquer.

**Prérequis** : M18-E08 (cluster de gestion, décision de la vérification préalable), M18-E09 (template 9060).
**Durée indicative** : 3 h 30.

**Contexte technique**
- Objets dans l'espace `capi-essai` du cluster de gestion, fichiers dans `capi/capi-essai/` de `plateforme/distributions`. Pars de `templates/cluster-template.yaml` de CAPMOX v0.9.1 (`clusterctl generate cluster capi-essai --infrastructure proxmox:v0.9.1 --list-variables` puis la génération), puis adapte-le : c'est un point de départ, pas une configuration MédiSphère.
- Cluster `capi-essai` : Kubernetes **v1.36.4** (celui du template 9060), un nœud de contrôle et deux travailleurs, 2 vCPU, 4 Go, 32 Gio chacun ; pods 10.244.0.0/16, services 10.96.0.0/12.
- Infrastructure : template 9060 sur le nœud `<NOEUD>`, clone **complet** sur `local-nvme` (sans changer de format : stockage bloc), pool `lab`, étiquettes `env-m18` et `capi-essai`, VMID **5180-5189** (champ `vmIDRange` des `ProxmoxMachineTemplate`), carte sur le VNet **`vk8s`** (VLAN 40).
- Adresses : 10.10.40.150-169 (bloc `ipv4Config` du `ProxmoxCluster` : CAPMOX en fait lui-même un réservoir `InClusterIPPool`), passerelle 10.10.40.1, résolveurs 10.10.20.10 et 10.10.20.16, NTP 10.10.40.1 ; VIP du plan de contrôle **10.10.40.210**, portée par kube-vip **v1.2.4** en pod statique.
- kube-vip et Kubernetes ≥ 1.29 : pendant `kubeadm init`, `admin.conf` n'a pas encore de droits ; le gabarit de CAPMOX contient un correctif (`super-admin.conf`) : garde-le, et comprends-le.
- Identifiants : Secret `capi-essai-proxmox` dans `capi-essai`, référencé par `ProxmoxCluster.spec.credentialsRef`. Clés lues par CAPMOX v0.9.1 : `url`, `token`, `secret`, `insecure`, `root_ca`. **Sans clé `insecure`, CAPMOX ne vérifie pas le certificat** (lis `pkg/scope/cluster.go` de CAPMOX si tu en doutes). Le Secret se crée par un script depuis les fichiers 600 de `adm01` (`capi/identifiants.sh`), jamais depuis un fichier versionné.
- Nœuds : racine MédiSphère (fichier depuis un Secret `medisphere-root-ca` de l'espace) et `hosts.toml` vers le cache Harbor (le containerd de l'image d'image-builder lit `/etc/containerd/certs.d`).
- CNI : Cilium **1.20.2**, rendu par `helm template` (valeurs dans `capi/cilium/values.yaml` : API par la VIP, pods 10.244.0.0/16), emballé dans un ConfigMap `cilium`, appliqué par un `ClusterResourceSet` `cilium` aux clusters étiquetés `cni=cilium`.
- Mémoire : trois VMs de 4 Go. RKE2 et Talos sont retirés.
- Si la vérification préalable de E08 a conclu au **repli CAPD** : fais l'exercice avec `DockerCluster` / `DockerMachineTemplate` (gabarit `--flavor development` de CAPD) ; les critères qui portent sur Proxmox ne s'appliquent pas, le check le signale.

**Travail demandé**
1. Génère le gabarit de CAPMOX, lis chaque objet, puis écris tes fichiers (`00-espace.yaml`, `10-cluster.yaml`, `20-plan-controle.yaml`, `25-travailleurs.yaml`, `30-crs-cilium.yaml`). Valide-les contre l'API du cluster de gestion **avant** de créer quoi que ce soit (`kubectl apply --dry-run=server`).
2. Écris et lance `capi/identifiants.sh` ; écris `capi/cilium/generer-crs.sh` et applique le ConfigMap.
3. Crée le cluster et suis-le :
   ```
   admin@adm01:~$ export KUBECONFIG=~/.config/workbook/m18/kind-gestion.kubeconfig
   admin@adm01:~/src/distributions$ kubectl apply -f capi/capi-essai/
   admin@adm01:~$ clusterctl describe cluster capi-essai -n capi-essai --show-conditions all
   admin@adm01:~$ kubectl -n capi-essai get machines,proxmoxmachines,ipaddressclaims -o wide -w
   admin@adm01:~$ kubectl -n capmox-system logs deploy/capmox-controller-manager -f
   root@pve01:~# qm list | awk '$1 >= 5180 && $1 <= 5189'
   ```
   Note l'ordre dans lequel les choses se passent (adresse réservée, clone, ISO cloud-init, démarrage, agent, `kubeadm init`, VIP, jonctions).
4. Récupère le kubeconfig (`clusterctl get kubeconfig`) dans `~/.config/workbook/m18/capi-essai.kubeconfig` (600). Vérifie les nœuds, Cilium, la VIP, et qu'une image publique passe par Harbor.
5. Regarde dans Proxmox ce que CAPMOX a créé (nom des VMs, étiquettes, description, ISO dans `capi-iso`, disques) et dans le cluster de gestion le réservoir d'adresses créé par CAPMOX. Que se passerait-il si tu arrêtais une de ces VMs dans l'interface de Proxmox ?
6. Complète `cluster-api.md` (section `capi-essai`) et `mesures.md` (temps de `kubectl apply` à trois nœuds `Ready`, et de quoi il dépend).

**Critères de réussite**
- [ ] Dans le cluster de gestion, `capi-essai` est provisionné, son plan de contrôle disponible, et ses trois machines `Running`.
- [ ] Ses VMs ont des VMID de 5180 à 5189, sont dans le pool `lab`, sur `vk8s`, avec les étiquettes `env-m18` et `capi-essai`, clonées du template 9060.
- [ ] Le cluster `capi-essai` a trois nœuds `Ready` en v1.36.4, aux adresses de 10.10.40.150-169 ; la VIP 10.10.40.210 répond en 6443 ; Cilium est prêt sur les trois nœuds.
- [ ] Le Secret d'identifiants a `insecure` à `false` et une ancre `root_ca` ; le `ClusterResourceSet` `cilium` est appliqué au cluster.
- [ ] `~/.config/workbook/m18/capi-essai.kubeconfig` est en 600 ; `capi/capi-essai/`, `capi/identifiants.sh` et `capi/cilium/` sont sur `main`, sans aucun secret.

**Vérification** : `lab/bin/check 18 10`

<details><summary>Indice 1</summary>

`clusterctl generate cluster … --list-variables` dit quelles variables le gabarit attend ; toutes ne te concernent pas, puisque tu réécris les fichiers. Les champs de CAPMOX se lisent aussi dans les CRD installées : `kubectl explain proxmoxmachinetemplate.spec.template.spec --recursive`.
</details>

<details><summary>Indice 2</summary>

Une machine bloquée se diagnostique de l'objet vers la VM : `kubectl describe proxmoxmachine` (conditions, message), journal du contrôleur CAPMOX, tâches de `pve01` (`/var/log/pve/tasks/`), console de la VM (cloud-init, `kubeadm`), puis `journalctl -u kubelet` en SSH avec la clé de `adm01` déclarée dans le `KubeadmConfig`.
</details>

<details><summary>Indice 3</summary>

Si le nœud de contrôle démarre mais que l'init de kubeadm attend indéfiniment l'API sur 10.10.40.210, regarde le pod statique de kube-vip sur la VM (`crictl logs`) : avec quel kubeconfig tourne-t-il, et ce kubeconfig a-t-il des droits à ce moment-là ?
</details>

---

### M18-E11 — Revue : les manifestes Cluster API du stagiaire  `REV` `★★`

> **Ticket PLAT-1911** — *De : Karim Benali*
> Lucas a ouvert une MR pour un second cluster, `recette-agenda`, en partant du gabarit de CAPMOX et de la documentation. Il dit que `--dry-run=client` passe. Fais-moi une vraie revue avant que quelqu'un l'applique : je compte au moins douze problèmes, dont trois qui m'empêcheraient de dormir.

**Objectifs pédagogiques**
- Relire des manifestes Cluster API et CAPMOX : sécurité, adressage, cohérence avec l'image et le plan, droits, quorum.
- Distinguer ce qu'une validation locale voit (syntaxe) de ce que voit l'API (schémas des CRD, webhooks) et de ce qui ne se voit qu'à l'exécution.
- Rédiger une revue utile (gravité, preuve, correctif).

**Prérequis** : M18-E10.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers de la MR : `ressources/E11-capi-stagiaire/` (description `LISEZMOI.md`, `identifiants.yaml`, `cluster.yaml`, `plan-controle.yaml`, `travailleurs.yaml`, `crs.yaml`).
- Référence : ton `capi-essai` (E10), la carte des hôtes et des adresses du module, PLAN §4.2 et §4.6, la documentation et les CRD de CAPMOX v0.9.1.
- Le LAN maison est `<LAN-MAISON>` (par exemple 192.168.1.0/24) ; `pve01` y a l'adresse `<IP-PVE01>`.
- Plan d'adressage du module pour un **second** cluster CAPMOX sur le VLAN 40 (il n'existe pas encore, c'est celui de Lucas) : nœuds 10.10.40.170-179, VIP 10.10.40.211 ; les VMID restent dans la plage du module, 5180-5189, partagée avec `capi-essai`.

**Travail demandé**
1. Relis les fichiers sans rien appliquer. Puis valide-les contre l'API du cluster de gestion (`kubectl apply --dry-run=server`, dans un espace d'essai) : quels défauts l'API voit-elle que `--dry-run=client` ne voyait pas ?
2. Écris la revue dans `capi/revue-lucas/REVUE.md` de `plateforme/distributions` : un défaut par ligne de liste (`- `), avec sa gravité (bloquant, majeur, mineur), ce qui se passerait, et le correctif.
3. Corrige les manifestes dans `capi/revue-lucas/` (mêmes noms de fichiers, cluster toujours nommé `recette-agenda`, cohérent avec le plan du module : il doit pouvoir coexister avec `capi-essai`). Ne l'applique **pas** : la mémoire du lab ne le permet pas.
4. Réponds à Lucas dans la MR (trois paragraphes : ce qui est bien, les trois défauts les plus graves, comment tester la prochaine fois).

**Critères de réussite**
- [ ] `capi/revue-lucas/REVUE.md` liste au moins douze défauts, gravité et correctif compris.
- [ ] Les manifestes corrigés ne contiennent aucun secret et passent la validation de l'API ; les adresses, les VMID, la VIP, le réseau des pods, la version de Kubernetes et le VNet sont cohérents avec le plan et avec le template 9060.
- [ ] Le plan de contrôle a un nombre impair de nœuds, des ressources suffisantes pour kubeadm ; kube-vip a une version fixée et le correctif `super-admin.conf`.

**Vérification** : `lab/bin/check 18 11`

<details><summary>Indice 1</summary>

Classe les défauts par famille : secrets et droits ; adresses et réseau (plages, VIP, DNS, VNet, réseau des pods) ; cohérence image/version/stockage ; disponibilité (quorum, ressources) ; ce qui ne marchera jamais (champs, sélecteurs, étiquettes) ; ce qui marchera mais nous exposera.
</details>

<details><summary>Indice 2</summary>

Compare les `vmIDRange` à la carte des VMID du module, l'adresse du point d'accès à la plage des nœuds, et l'étiquette du `Cluster` au sélecteur du `ClusterResourceSet`. Et regarde qui a la clé SSH déclarée.
</details>

---

### M18-E12 — Pivoter le cluster de gestion  `LAB` `★★★`

> **Ticket PLAT-1912** — *De : Nadia Roussel*
> Si j'ai bien compris, tout `capi-essai` dépend d'un cluster kind qui tourne dans un conteneur sur une VM de développement. Le jour où quelqu'un redémarre `m18-dev01` ou fait `kind delete`, plus personne ne sait réparer ni monter de version ce cluster. Je veux un cluster de gestion qui ne disparaît pas, sauvegardé, documenté, et la preuve qu'on peut y déplacer ce qui existe sans casser `capi-essai`.

**Objectifs pédagogiques**
- Préparer un cluster de gestion durable (`k3s01`) et y installer les mêmes fournisseurs.
- Déplacer (*pivot*) les objets de Cluster API d'un cluster de gestion à un autre avec `clusterctl move`, sans toucher au cluster de charge de travail.
- Vérifier que le nouveau cluster de gestion réconcilie (mise à l'échelle) et retirer l'ancien proprement.

**Prérequis** : M18-E10 (`capi-essai` sain), M18-E03 (`k3s01`).
**Durée indicative** : 2 h.

**Contexte technique**
- Cible : `k3s01` (k3s v1.36.5, SQLite, 4 Go), kubeconfig `~/.config/workbook/m18/k3s01.kubeconfig`. Ses flux vers `pve01:8006` et vers l'API de `capi-essai` sont déjà ouverts (E08 : `M18_GESTION` et IPSet `capi` contiennent son adresse).
- Les fournisseurs de la cible doivent être **aux mêmes versions** que ceux de la source (documentation de `clusterctl move`), installés sans identifiants globaux (même `capi/init.sh`).
- `clusterctl move` met le cluster en pause sur la source, recrée les objets sur la cible (sans leur `status`), puis les supprime de la source. Ce qu'il déplace : les objets de l'espace liés au `Cluster` (références de propriété) et ceux qui portent l'étiquette `clusterctl.cluster.x-k8s.io/move`.
- Toutes les machines doivent être `Running` avant le déplacement (aucune création ou suppression en cours).

**Travail demandé**
1. Vérifie l'état de départ : `capi-essai` sain, machines `Running`, rien en cours. Note les noms des machines et les VMID.
2. Installe les fournisseurs sur `k3s01` (`capi/init.sh`), compare les versions avec la source. Vérifie la mémoire de `k3s01` ensuite.
3. Fais une copie de sécurité des objets de `capi-essai` (`clusterctl move --to-directory`). Où la ranges-tu, sachant ce qu'elle contient ?
4. `clusterctl move … --dry-run`, lis ce qui serait déplacé (le Secret d'identifiants et le Secret `medisphere-root-ca` y sont-ils ? pourquoi ?), puis déplace pour de bon. Écris la séquence dans `capi/pivot.sh`.
5. Vérifie depuis `k3s01` : cluster disponible, mêmes machines, mêmes VMID, aucune VM recréée ; `capi-essai` n'a vu aucune interruption (ses nœuds, ses pods). Prouve que le nouveau cluster de gestion **réconcilie** : passe le `MachineDeployment` à trois travailleurs, attends le nœud, reviens à deux.
6. Retire l'ancien : `kind delete cluster --name gestion` sur `m18-dev01`, supprime `kind-gestion.kubeconfig`, efface la copie de sécurité. Complète `cluster-api.md` (pivot, protection et sauvegarde du cluster de gestion, ce qui se passe si `k3s01` tombe).

**Critères de réussite**
- [ ] Sur `k3s01` : les cinq fournisseurs aux versions de E08 et leurs contrôleurs disponibles ; `capi-essai` (espace `capi-essai`) provisionné, plan de contrôle disponible, deux travailleurs, trois machines `Running`.
- [ ] Les VMs 5180-5189 de `capi-essai` sont celles d'avant le pivot (aucune recréée) ; ses trois nœuds sont `Ready`.
- [ ] Le Secret `capi-essai-proxmox` est sur `k3s01` (avec `insecure` à `false`) ; plus aucun objet de `capi-essai` sur le cluster kind, qui n'existe plus ; `kind-gestion.kubeconfig` a disparu.
- [ ] `capi/pivot.sh` et la section « pivot » de `cluster-api.md` sont sur `main`.

**Vérification** : `lab/bin/check 18 12`

<details><summary>Indice 1</summary>

Le cluster de gestion n'a pas besoin de joindre les nœuds de `capi-essai` en SSH, mais il doit joindre l'API de `pve01` (CAPMOX) et l'API de `capi-essai` (le contrôleur du plan de contrôle y lit l'état d'etcd et des nœuds). Si les machines passent en échec juste après le déplacement, commence par là.
</details>

<details><summary>Indice 2</summary>

`--to-directory` écrit les objets en YAML **avec les Secrets**. Un dossier 700 sur `adm01`, effacé après la vérification, ou un fichier chiffré : pas un dossier du dépôt, pas `/tmp`.
</details>

<details><summary>Indice 3</summary>

Un objet qui n'est relié au `Cluster` par aucune référence de propriété et qui ne porte pas l'étiquette de déplacement **reste** sur la source : sur la cible, les machines nouvelles (mise à l'échelle) ne trouveraient alors pas leur fichier.
</details>
