# Module 09 — Palier 2 : Opérationnel

Le palier 1 a monté le cluster `hv-par1` : trois nœuds Proxmox VE 9.2 installés sans clavier, deux liens Corosync, un quorum que tu sais expliquer, un QDevice monté puis retiré, des stockages locaux (`local-lvm`, `zfs-local`), le pont `vmbr1` des invités et un template `tpl-nested-debian13` (199). Les VMs tournent, mais chacune vit sur les disques de **son** nœud : la migration recopie tout, la perte d'un nœud emporte ses VMs, personne n'a de droits nominatifs, rien n'est sauvegardé hors site et tout se fait à la main sur `hv01`. Ce palier fait du cluster une plateforme qu'on exploite au quotidien : un stockage partagé (Ceph hyperconvergé, puis le Ceph de PAR1), la haute disponibilité avec les règles de Proxmox VE 9, la réplication ZFS pour ce qui reste local, les sauvegardes chiffrées vers PAR2, des réseaux d'invités définis au niveau du cluster (SDN, jusqu'à l'EVPN), des droits par équipe, une API pilotée par le code, des mises à jour sans interruption de service, et un runbook de maintenance que l'astreinte peut suivre.

> **Rappels du module** (introduction) : toute nouvelle VM du lab passe par OpenTofu (état `hv` de `plateforme/infra` pour les nœuds), toute configuration durable par un rôle Ansible appliqué par le pipeline de `plateforme/ansible`, tout nouveau flux par la matrice des flux (`group_vars/role_routeur/pare_feu.yml`, commune aux deux passerelles depuis M07-E24), tout secret par Ansible Vault et le registre des secrets. Les invités **imbriqués** (VMID 100-199, à l'intérieur du cluster) sont des objets de travail : tu les crées à la main ou par le code selon l'exercice. Les vérifications se lancent depuis `adm01` et lisent les nœuds en SSH (alias `hv01`, `hv02`, `hv03` de `~/.ssh/config`, connexion `root`).

> ⚠️ **Règles du palier** : ne modifie rien sur `pve01` (ses ponts, son pare-feu, ses stockages) ; `ceph01-03` ne sont démarrées que pour M09-E12 ; toute intervention sur `pbs01` (M09-E15) est annoncée et réversible ; avant d'intervenir sur un nœud, vérifie que tu as un accès de secours (`qm terminal 2091` depuis `pve01`, console série du nœud imbriqué).

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Nœuds | `hv01` 2091, `hv02` 2092, `hv03` 2093 ; MGMT 10.10.10.51-53 (`vmbr0`), COROSYNC 10.10.32.51-53, Ceph public 10.10.30.71-73, Ceph cluster 10.10.31.71-73 (MTU 9000), trunk des invités sur `vmbr1` (VLAN-aware). FQDN `hvNN.par1.medisphere.internal` |
| Stockages existants (palier 1) | `local` (répertoire), `local-lvm` (LVM-thin), `zfs-local` (pool ZFS `tank` sur le disque de 32 Go de chaque nœud, même nom partout) |
| Disques libres par nœud | deux disques de 48 Go (`ssd-lab` de `pve01`) réservés aux OSD Ceph |
| Stockages créés au palier 2 | `ceph-vm` (RBD hyperconvergé, E10), `ceph-par1-rbd` (RBD externe, E12, retiré en fin d'exercice), `pbs-par2` (PBS, E15) |
| Ceph hyperconvergé | Squid 19.2 (`pveceph`, dépôt `no-subscription`) ; public 10.10.30.0/24, cluster 10.10.31.0/24 ; MON et MGR sur les trois nœuds ; 2 OSD par nœud ; pool `ceph-vm` size 3 / min_size 2 ; `osd_memory_target` 1 Gio |
| Invités imbriqués du palier | 199 `tpl-nested-debian13` (template, M09-E06) ; 101 `app01` et 102 `app02` (M09-E07), 103 `app03` (E11) — HA en E13 ; 104-106 essais d'E11 (détruits) ; 110 `rep01` (réplication, E14) ; 127 `restau01` (restaurations de test d'E15, détruite après chaque essai ; même VMID et même usage qu'en M09-E29) ; 130-139 `rec01`… (OpenTofu, E18) ; 140-141 `evpn01-02` (SDN, E16) ; 150 `legacy-rdv01` (import, E23). 120-129 sont réservés au palier 3. 1 vCPU, 1 Go de mémoire chacun sauf mention |
| Point d'accès de l'API (E18) | VIP keepalived 10.10.10.200, `hv.par1.medisphere.internal`, VRID 110, rôle Ansible `pve_cluster` |
| PBS (E15) | `pbs01` (10.20.10.10, à travers `wg0`), datastore `ds-lab`, namespace `par1/hv`, utilisateur `wb-hv@pbs`, jeton `wb-hv@pbs!hv-par1` |
| SDN (E16) | zone VLAN `invites` (pont `vmbr1`), VNet `vinv99` (VLAN 99) ; contrôleur EVPN `evpnhv` (AS 65090) ; zone EVPN `evhv` ; VNets `vevpn1` 10.90.1.0/24 et `vevpn2` 10.90.2.0/24 |
| Droits (E17) | groupes `hv-admins`, `hv-ops` ; pools `prod`, `recette` ; rôle `WBTofuHV`, jeton `wb-tofu-hv@pve!tofu` (`~/.config/workbook/pve-tofu-hv.env` sur `adm01`) |
| Documentation | `docs/virtualisation/` de `plateforme/medisphere` ; runbooks `docs/virtualisation/runbooks/` (RB-090 en E22) |
| Brouillons | `~/m09/eXX/` sur `adm01` (non versionnés, jamais de secret) |

**Ordre conseillé**

```
E10 ─ E11 ─┬─ E12
           ├─ E13 ─ E20 ─ E22
           ├─ E14
           ├─ E15
           └─ E23
E16 ─ E17 ─ E18 ─ E19
E21 (à tout moment après E13)
```

E10 et E11 d'abord : presque tout le reste suppose le stockage partagé. E13 (HA) précède E20 (évacuation, équilibrage) et E22 (le runbook de maintenance s'appuie sur les deux). E17 (droits) précède E18 (le jeton d'OpenTofu). E19 (mises à jour) vient en dernier : il réutilise le mode maintenance et le code d'E18.

Durée indicative du palier 2 : 26 à 32 heures.

---

### M09-E10 — Ceph hyperconvergé  `LAB` `★★`

> **Ticket PLAT-1020** — *De : Karim Benali*
> Tant que les disques des VMs sont sur `local-lvm`, une migration recopie tout le disque et la perte d'un nœud perd ses VMs. InfoGér faisait tourner Ceph directement sur ses hyperviseurs, en Squid : on reproduit exactement ce parc pour apprendre à le maintenir avant de le moderniser (la montée en Tentacle viendra en E28). Trois MON, trois copies, et pas un octet de trafic Ceph sur le réseau d'administration ou sur Corosync.

**Objectifs pédagogiques**
- Déployer Ceph avec l'outillage intégré de Proxmox VE (`pveceph`) : dépôt, réseaux public et cluster, moniteurs, gestionnaires, OSD, pool.
- Comprendre ce que Proxmox VE gère pour toi (configuration dans `/etc/pve/ceph.conf`, clés, stockage) et ce qui reste du Ceph « normal » (commandes `ceph`, `ceph config`).
- Dimensionner Ceph pour des nœuds à 12 Go de mémoire.

**Prérequis** : M09-E08 (trois nœuds, quorum à trois voix) ; M08 (concepts Ceph : MON, MGR, OSD, PG, CRUSH, `size`/`min_size`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Proxmox VE 9.2 propose Squid 19.2 et Tentacle 20.2 (Tentacle par défaut pour une nouvelle installation) ; dépôt sans abonnement.
- Réseaux : public 10.10.30.0/24 (cartes `net2` des nœuds, 10.10.30.71-73), cluster 10.10.31.0/24 (`net3`, 10.10.31.71-73), MTU 9000 de bout en bout depuis M07-E15. Le cluster `ceph-par1` du module 08 (10.10.30.51-53) partage le VLAN 30 : il est arrêté, et de toute façon les deux clusters ne se voient pas (`fsid` et moniteurs différents).
- Disques OSD : les deux disques de 48 Go de chaque nœud, vierges, de numéros de série `hvNN-osd1` et `hvNN-osd2` (`/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_hvNN-osd1`, M09-E03). Le disque ZFS (`hvNN-zfs`, 32 Go) et le disque système (`hvNN-systeme`, 32 Go) ne doivent pas être touchés : désigne les disques par leur numéro de série et vérifie leur taille, jamais par leur nom (`/dev/sdX` peut changer d'un démarrage à l'autre).
- Mémoire : un OSD vise 4 Gio par défaut. Avec deux OSD, un MON et un MGR par nœud, sur 12 Go, il reste peu pour les invités.

> ⚠️ **Attention** : `pveceph osd create` efface le disque désigné. Vérifie trois fois la taille et le numéro de série avant de valider : une erreur de disque détruit le pool `tank` (réplication d'E14) ou le système du nœud. Retour arrière d'un OSD créé par erreur : `pveceph osd destroy <ID> --cleanup 1` après l'avoir sorti (`ceph osd out`) et arrêté.

**Travail demandé**
1. Sur chaque nœud, vérifie que les cartes Ceph sont à MTU 9000 de bout en bout : un `ping` de 8972 octets, sans fragmentation, vers les deux autres nœuds, sur les deux réseaux. Note le résultat.
2. Installe Ceph **Squid** depuis le dépôt sans abonnement sur les trois nœuds (`pveceph install`, lis son aide pour les options de dépôt et de version). Quel fichier de dépôt a été écrit ? Où est-il ?
3. Initialise la configuration Ceph du cluster avec les deux réseaux, depuis **un seul** nœud. Lis `/etc/pve/ceph.conf` : pourquoi n'est-ce pas `/etc/ceph/ceph.conf`, et qu'est devenu ce dernier ?
4. Crée un moniteur et un gestionnaire sur chaque nœud. Combien de MGR sont actifs ? Pourquoi trois MON et pas deux ou quatre ?
5. Avant de créer les OSD, règle `osd_memory_target` à 1 Gio dans la base de configuration de Ceph (pas dans un fichier), et explique ce que cette valeur limite et ce qu'elle ne limite pas.
6. Crée les six OSD (deux par nœud). Vérifie leur classe de périphérique et leur place dans l'arbre CRUSH.
7. Crée le pool `ceph-vm` (3 copies, `min_size` 2, ajustement automatique des PG actif) et le stockage Proxmox du même nom, en une opération. Lis l'entrée créée dans `/etc/pve/storage.cfg` : qu'est-ce qui la distingue d'un stockage RBD externe ?
8. Contrôle : `ceph -s` en `HEALTH_OK`, `ceph osd df tree`, `pvesm status`. Si l'état n'est pas `HEALTH_OK`, lis chaque avertissement (`ceph health detail`) et règle-le avant de continuer.
9. Écris dans ton journal ce qui se passe, en nombre de copies et en disponibilité des écritures, si (a) un OSD tombe, (b) un nœud entier tombe, (c) deux nœuds tombent.

**Critères de réussite**
- [ ] `ceph -s` : `HEALTH_OK`, 3 MON en quorum, 1 MGR actif et 2 en attente, 6 OSD `up` et `in`.
- [ ] Réseau public 10.10.30.0/24 et réseau cluster 10.10.31.0/24 dans `/etc/pve/ceph.conf` ; les OSD écoutent sur ces deux réseaux.
- [ ] `osd_memory_target` = 1073741824 dans la base de configuration.
- [ ] Pool `ceph-vm` : size 3, min_size 2, application `rbd`, autoscale `on` ; stockage `ceph-vm` actif sur les trois nœuds.
- [ ] Les démons Ceph sont en version 19.2 (Squid) sur les trois nœuds.

**Vérification** : `lab/bin/check 09 10`

<details><summary>Indice 1</summary>

`pveceph help install --verbose` et `pveceph help pool create --verbose` donnent les options exactes ; la page *Deploy Hyper-Converged Ceph Cluster* de la documentation suit le même ordre que l'exercice. `lsblk -o NAME,SIZE,SERIAL,TYPE,MOUNTPOINTS` et `ls -l /dev/disk/by-id/` désignent un disque sans ambiguïté.
</details>

<details><summary>Indice 2</summary>

`ceph config set <qui> <option> <valeur>` écrit dans la base des moniteurs ; `ceph config get osd.0 osd_memory_target` et `ceph config show osd.0` (valeur effective du démon) te disent si c'est pris en compte. Une valeur en octets évite toute ambiguïté d'unité.
</details>

<details><summary>Indice 3</summary>

Un `HEALTH_WARN` juste après la création du pool vient souvent du nombre de PG (l'autoscaler n'a pas encore tourné) ou de l'horloge (`clock skew`) : `ceph health detail` dit lequel. Pour l'horloge, regarde `chronyc tracking` sur chaque nœud : quelle est leur source de temps ?
</details>

**Pour aller plus loin** (facultatif) : la documentation de Proxmox VE (*Deploy Hyper-Converged Ceph Cluster*, <https://pve.proxmox.com/pve-docs/chapter-pveceph.html>) recommande des réseaux et des disques dédiés ; compare ses recommandations de mémoire avec ce que tu as configuré. Lis aussi le guide de dimensionnement de Ceph : <https://docs.ceph.com/en/squid/start/hardware-recommendations/>.

---

### M09-E11 — Stockage partagé et migration à chaud  `LAB` `★★`

> **Ticket PLAT-1021** — *De : Claire Morel*
> Le jour où on fera la maintenance d'un nœud en production, je ne veux pas d'interruption de service perceptible. Montre-moi, chiffres à l'appui, ce que coûte une migration à chaud quand le disque est sur Ceph, et ce qu'elle coûte quand il est local. Et que nos VMs de travail et le template vivent désormais sur le stockage partagé.

**Objectifs pédagogiques**
- Déplacer des disques de VM vers un stockage partagé, à chaud.
- Comprendre ce que transfère une migration à chaud (mémoire, état des périphériques, disques locaux) et mesurer l'interruption réelle.
- Distinguer clone complet et clone lié sur un stockage RBD.

**Prérequis** : M09-E06 (template 199, script `outils/hv/creer-tpl-nested.sh`), M09-E07 (premières VMs, migration), M09-E10.
**Durée indicative** : 2 h.

**Contexte technique**
- VMs de travail : `app01` (101) et `app02` (102), créées en M09-E07 (clones complets sur `zfs-local`, pont `vmbr1` VLAN 99, DHCP) ; `app03` (103), à créer ici sur le même modèle, directement sur `ceph-vm`. 1 vCPU, 1 Go.
- Le template 199 est aujourd'hui sur `local-lvm` de `hv01` : il doit passer sur `ceph-vm`. Le script de M09-E06 sait le fabriquer sur un autre stockage.
- La migration utilise pour l'instant le réseau par défaut (celui de l'adresse du nœud, MGMT) : le réseau de migration dédié est l'objet de M09-E27.
- Pour mesurer une coupure, un `ping` à intervalle court depuis `adm01` vers la VM suffit (le VLAN 99 est joignable depuis MGMT).

**Travail demandé**
1. Avant de toucher au template : liste les VMs qui en dépendent (clones liés) et décide comment le mettre sur `ceph-vm` (le déplacer, ou le reconstruire avec le script de M09-E06). Justifie dans ton journal.
2. Déplace les disques de `app01` et `app02` de `zfs-local` vers `ceph-vm` **pendant qu'elles tournent** ; note la durée et ce que montre la tâche. Que devient l'ancien volume ? Crée `app03` (103), clone complet de 199 sur `ceph-vm`.
3. Crée deux clones de 199 sur `ceph-vm`, l'un complet, l'autre lié (VMID 104 et 105, à supprimer à la fin de l'étape). Compare leur place réelle dans le pool (`rbd du`) et leur lien au template (`rbd info`). Que se passerait-il si tu supprimais le template ?
4. Mesure : lance un `ping -i 0.2` vers `app01` depuis `adm01`, migre-la à chaud de `hv01` vers `hv02`, puis arrête le `ping`. Nombre de paquets perdus, durée de la migration, durée du *downtime* annoncée dans le journal de la tâche.
5. Même mesure avec une VM dont le disque est sur `local-lvm` (VMID 106, clone complet, détruite ensuite) : quelle option faut-il ajouter, que transfère la migration en plus, combien de temps cela prend-il ?
6. Réponds dans ton journal : pourquoi la migration à chaud d'une VM dont le disque est sur Ceph ne copie-t-elle pas le disque ? Qu'est-ce qui empêcherait une migration à chaud même avec un stockage partagé (pense au matériel virtuel et au type de CPU) ?

**Critères de réussite**
- [ ] Le template 199 et les disques de `app01` à `app03` sont sur `ceph-vm` ; aucun disque des VMs 101-103 ne reste sur un stockage local.
- [ ] Le journal des tâches du cluster montre au moins une migration à chaud (`qmigrate`) réussie de `app01`.
- [ ] Les VMs d'essai 104 à 106 n'existent plus.
- [ ] Ton journal donne les mesures des deux migrations et répond aux questions des étapes 1, 3 et 6.

**Vérification** : `lab/bin/check 09 11`

<details><summary>Indice 1</summary>

`qm disk move` (lis son aide : que fait `--delete` ?) ; `qm migrate` (options `--online`, `--with-local-disks`). Le journal de tâche d'une migration se lit dans l'interface ou par `pvesh get /nodes/<nœud>/tasks/<UPID>/log`.
</details>

<details><summary>Indice 2</summary>

Un clone lié RBD est un *clone* Ceph d'un instantané protégé du disque du template (`base-199-disk-0@__base__`). Tant qu'il existe, l'instantané ne peut pas être supprimé ; `rbd children` le montre.
</details>

<details><summary>Indice 3</summary>

Le type de CPU d'une VM doit exister sur le nœud de destination. Ici les trois nœuds ont le même CPU virtuel ; dans un vrai parc hétérogène, c'est la raison des types `x86-64-v2-AES` et suivants.
</details>

**Pour aller plus loin** (facultatif) : la section *Online Migration* de `qm(1)` (<https://pve.proxmox.com/pve-docs/qm.1.html>) ; le principe du *pre-copy* de la mémoire et de l'*auto-converge* de QEMU (<https://www.qemu.org/docs/master/devel/migration/main.html>).

---

### M09-E12 — Consommer le Ceph de PAR1  `LAB` `★★★`

> **Ticket PLAT-1022** — *De : Karim Benali*
> Le Ceph hyperconvergé, c'est bien pour un petit cluster ; mais on a déjà `ceph-par1` (module 08), avec plus de disques, et OpenStack va s'y brancher. Je veux savoir si `hv-par1` peut y poser des disques de VM proprement : un pool à lui, une identité qui ne voit que ce pool, la clé nulle part ailleurs que là où elle doit être. Et ensuite tu ranges tout : ce pool n'a pas vocation à rester.

**Objectifs pédagogiques**
- Raccorder un cluster Proxmox VE à un cluster Ceph externe (RBD) avec une identité CephX à privilèges minimaux.
- Transporter une clé sans la laisser traîner, et savoir où Proxmox VE la range.
- Comprendre ce qui arrive aux VMs quand le stockage externe disparaît, et retirer proprement un stockage.

**Prérequis** : M08 (cluster `ceph-par1`, cephadm, CephX, pools RBD) ; M09-E10, M09-E11.
**Durée indicative** : 2 h 30.

**Contexte technique**
- `ceph-par1` : Tentacle 20.2, cephadm, nœuds `ceph01-03` (Rocky Linux 10), moniteurs 10.10.30.51-53 sur le VLAN 30. Les nœuds `hv01-03` sont sur le même VLAN (10.10.30.71-73) : aucun routage, aucun flux à ouvrir sur la bordure.
- Pool à créer sur `ceph-par1` : `hv-par1` (application `rbd`). Identité : `client.hv-par1`, capacités `profile rbd` limitées à ce pool.
- Stockage Proxmox à créer : `ceph-par1-rbd` (contenu `images`).
- Mémoire : `ceph01-03` (6 Go chacune) s'ajoutent au profil le temps de l'exercice ; vérifie la mémoire libre de `pve01` avant de les démarrer, et arrête-les à la fin.
- Secrets : la clé de `client.hv-par1` va dans Ansible Vault (identité `critique`) et au registre des secrets ; elle ne passe ni par un dépôt, ni par `adm01` en clair, ni en argument de commande.

> ⚠️ **Attention** : tu interviens sur `ceph-par1`, que les modules 10 et 16 consommeront. Ne touche à aucun pool existant ; la suppression du pool `hv-par1` (étape 8) demande d'autoriser temporairement la suppression de pools : remets l'interdiction **immédiatement** après. Retour arrière : supprimer le stockage `ceph-par1-rbd`, l'identité et le pool `hv-par1`, dans cet ordre.

**Travail demandé**
1. Démarre `ceph01-03`, attends `HEALTH_OK` (ou explique chaque avertissement).
2. Sur `ceph-par1` : crée le pool `hv-par1`, initialise-le pour RBD, puis crée `client.hv-par1` avec les capacités minimales. Écris dans ton journal ce que permet `profile rbd` sur `mon`, `osd` et `mgr`, et pourquoi on ne donne pas simplement le trousseau `client.admin`.
3. Transporte le trousseau de `ceph01` vers `hv01` sans écrire la clé sur `adm01` ni sur un disque intermédiaire. Range une copie dans Vault (`critique`).
4. Ajoute le stockage `ceph-par1-rbd` sur le cluster (moniteurs, pool, identité, trousseau). Où Proxmox VE a-t-il rangé la clé ? Avec quels droits ? Supprime la copie de travail sur `hv01`.
5. Prouve les limites de l'identité : depuis `hv01`, avec `client.hv-par1`, liste les images du pool `hv-par1`, puis essaie de lister un pool du module 08 (par exemple celui des volumes RBD) ; essaie aussi de créer un pool. Note les erreurs.
6. Déplace à chaud le disque de `app03` vers `ceph-par1-rbd`, vérifie l'image côté `ceph-par1` (`rbd ls`, `rbd info`), et fais tourner la VM dix minutes. Puis, pendant qu'elle tourne, arrête **un** nœud de `ceph-par1` : que voit la VM ? Redémarre-le.
7. Réponds dans ton journal : que se passerait-il pour `app03` si les trois nœuds de `ceph-par1` s'arrêtaient ? Pourquoi est-ce une raison de plus de ne pas mélanger, dans un même cluster Proxmox, des VMs HA et un stockage externe sans supervision commune ?
8. Range : remets le disque de `app03` sur `ceph-vm`, retire le stockage `ceph-par1-rbd` du cluster, supprime l'identité et le pool `hv-par1` de `ceph-par1` (avec l'autorisation temporaire évoquée plus haut), vérifie qu'aucun fichier de clé `hv-par1` ne reste sur les nœuds, retire le secret du Vault et du registre (ou marque-le révoqué), puis arrête `ceph01-03`.
9. Rédige `docs/virtualisation/stockage-externe.md` : la procédure de raccordement, les capacités, l'emplacement de la clé, la procédure de retrait, et ce que tu as observé en étape 6.

**Critères de réussite**
- *Pendant l'exercice* (étapes 2 à 7) :
  - [ ] `ceph-par1-rbd` est actif sur les trois nœuds ; il désigne les trois moniteurs, le pool `hv-par1` et l'identité `hv-par1`.
  - [ ] La clé est dans `/etc/pve/priv/ceph/`, et nulle part ailleurs sur les nœuds.
  - [ ] Les capacités de `client.hv-par1` se limitent à `profile rbd` sur le pool `hv-par1`.
- *Après le rangement* (étapes 8 et 9) :
  - [ ] `ceph-par1-rbd` n'existe plus ; le pool `hv-par1` et `client.hv-par1` n'existent plus sur `ceph-par1` ; la suppression de pools est de nouveau interdite.
  - [ ] `docs/virtualisation/stockage-externe.md` est dans le dépôt de documentation.

**Vérification** : `lab/bin/check 09 12` — lance-la deux fois : avant le rangement (elle contrôle le raccordement), puis après (elle contrôle le rangement).

<details><summary>Indice 1</summary>

Sur un hôte cephadm, les commandes `ceph` et `rbd` s'exécutent dans `cephadm shell -- …`. La sortie standard d'une commande lancée en SSH peut être envoyée directement à l'entrée standard d'une autre commande lancée en SSH sur un autre hôte : la clé ne touche alors aucun disque intermédiaire.
</details>

<details><summary>Indice 2</summary>

La section *Ceph RADOS Block Devices* de `pvesm(1)` décrit l'option `--keyring` et l'emplacement où la clé est conservée. Pour agir avec l'identité restreinte depuis `hv01`, `rbd` accepte `--id`, `-m` (moniteurs) et `--keyring`.
</details>

<details><summary>Indice 3</summary>

La suppression d'un pool est protégée par l'option des moniteurs `mon_allow_pool_delete` ; lis-la, change-la, puis remets-la, avec `ceph config`. Avant de supprimer un stockage Proxmox, `pvesm list ceph-par1-rbd` doit être vide.
</details>

**Pour aller plus loin** (facultatif) : un `ceph.conf` propre au stockage (`/etc/pve/priv/ceph/<STOCKAGE>.conf`) permet des réglages client (cache, journalisation) ; lis la référence de configuration RBD : <https://docs.ceph.com/en/tentacle/rbd/rbd-config-ref/>. Les espaces de noms RBD (`rbd namespace`) permettent de partager un pool entre plusieurs clients isolés : quand serait-ce préférable à un pool par client ?

---

### M09-E13 — Haute disponibilité : ressources et règles  `LAB` `★★★`

> **Ticket PLAT-1023** — *De : Nadia Roussel*
> Chez InfoGér, quand un hyperviseur tombait la nuit, l'astreinte redémarrait les VMs à la main sur un autre, une par une, en espérant ne pas les démarrer deux fois. Je veux que le cluster le fasse seul, qu'on sache exactement où chaque VM a le droit d'aller, et que les deux frontaux d'une même application ne se retrouvent jamais sur le même nœud. Et je veux comprendre ce que je lis dans `ha-manager status` avant d'être réveillée par lui.

**Objectifs pédagogiques**
- Placer des VMs sous la gestion du gestionnaire HA de Proxmox VE (ressources, états demandés, politique de relance).
- Exprimer des contraintes de placement avec les **règles HA** de Proxmox VE 9 (affinité de nœud, affinité entre ressources), qui remplacent les groupes HA.
- Lire l'état du CRM et des LRM, et comprendre le rôle du *watchdog* dans le *fencing*.

**Prérequis** : M09-E11 (`app01-03` sur `ceph-vm`) ; M09-E09 (questions sur le quorum et la HA).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Proxmox VE 9 : les groupes HA sont **dépréciés** et convertis en règles d'affinité de nœud ; l'option `nofailback` des groupes est devenue l'option `failback` des ressources. Tout se configure par `ha-manager` (ou l'API `/cluster/ha/…`), et se lit dans `/etc/pve/ha/`.
- Contraintes de Nadia :
  - `app01` (VMID 101, la base de données de démonstration) tourne de préférence sur `hv01`, sinon sur `hv02`, et sur `hv03` seulement si les deux autres sont indisponibles. Règle `app01-preferences`.
  - `app02` et `app03` (102, 103, les deux frontaux) ne sont jamais sur le même nœud. Règle `frontaux-separes`.
  - Chaque ressource : une relance sur place, puis un déplacement au plus, avant de déclarer l'échec.
- Les nœuds sont des VMs : leur *watchdog* est le *softdog* du noyau, il n'y a pas de *watchdog* matériel. Ne coupe pas de nœud dans cet exercice : le test de *fencing* est l'objet de M09-E24.

> ⚠️ **Attention** : ne tue jamais `watchdog-mux`, `pve-ha-crm` ni `pve-ha-lrm` sur un nœud qui porte des ressources HA (la documentation le dit : redémarrage immédiat du nœud possible). Pour sortir une ressource de la HA en urgence : `ha-manager set vm:<ID> --state ignored` (le nœud ne s'en occupe plus), puis `ha-manager remove`.

**Travail demandé**
1. Avant toute ressource : `ha-manager status`. Que signifient les lignes `quorum`, `master` et `lrm` ? Pourquoi le CRM n'a-t-il pas de maître actif ?
2. Ajoute `app01`, `app02`, `app03` comme ressources HA avec l'état demandé `started` et la politique de relance de Nadia. Observe l'évolution de `ha-manager status` pendant la minute qui suit : quel nœud devient maître, quels LRM passent `active` ?
3. Crée les deux règles. Lis `/etc/pve/ha/rules.cfg`. Observe ce que fait le CRS juste après la création de chaque règle (qui bouge, vers où, pourquoi).
4. Expériences, une à une, en notant ce que fait la HA et en combien de temps :
   - (a) migre `app01` vers `hv03` par `ha-manager` : où se trouve-t-elle deux minutes plus tard, et pourquoi (option `failback`) ?
   - (b) demande la migration de `app03` vers le nœud où tourne `app02` : que répond ou que fait la HA ?
   - (c) sur le nœud de `app02`, tue brutalement le processus QEMU de la VM (`kill -9` sur le PID de `/run/qemu-server/102.pid`) : que fait le LRM ?
   - (d) arrête `app02` avec `qm shutdown 102` : quel état demandé lis-tu ensuite dans `ha-manager config` ? Redémarre-la.
5. Lis la section *Fencing* de `ha-manager(1)` et réponds dans ton journal : qui arme le *watchdog* de chaque nœud, quand, et que se passe-t-il pour un nœud qui perd le quorum en portant une ressource HA ? Où vois-tu l'état du *fencing* dans `ha-manager status` ?
6. Pourquoi le stockage partagé est-il une condition de la HA ? Que ferait la HA d'une ressource dont le disque est sur `local-lvm` ?

**Critères de réussite**
- [ ] `vm:101`, `vm:102`, `vm:103` sont des ressources HA, état demandé `started`, `max_restart` 1 et `max_relocate` 1, toutes `started` dans `ha-manager status`.
- [ ] La règle `app01-preferences` (affinité de nœud, non stricte, priorités `hv01` > `hv02` > `hv03`) et la règle `frontaux-separes` (affinité de ressources négative) existent et sont actives.
- [ ] `app01` tourne sur `hv01` ; `app02` et `app03` tournent sur deux nœuds différents.
- [ ] Aucune ressource HA en état `error` ; le gestionnaire HA a un maître.
- [ ] Ton journal répond aux questions des étapes 1, 4, 5 et 6.

**Vérification** : `lab/bin/check 09 13`

<details><summary>Indice 1</summary>

`ha-manager help rules add --verbose` liste les deux types de règles et leurs options (`--resources`, `--nodes` avec priorités `nœud:priorité`, `--strict`, `--affinity`). Une priorité plus **grande** est préférée.
</details>

<details><summary>Indice 2</summary>

`ha-manager status --verbose` donne l'état complet (JSON) du maître et des LRM ; `journalctl -u pve-ha-crm -u pve-ha-lrm -f` sur deux nœuds à la fois montre les décisions en direct. Une commande `qm` sur une VM gérée par la HA n'est pas exécutée directement : elle est transmise au gestionnaire HA.
</details>

<details><summary>Indice 3</summary>

Pour le *watchdog* : `systemctl status watchdog-mux`, `ls -l /dev/watchdog*`, `lsmod | grep softdog`. Le LRM d'un nœud n'ouvre le *watchdog* que s'il a des ressources à gérer.
</details>

**Pour aller plus loin** (facultatif) : la documentation complète du gestionnaire HA, dont le simulateur `pve-ha-simulator` qui rejoue des pannes sans cluster : <https://pve.proxmox.com/pve-docs/chapter-ha-manager.html>. Lis la liste des contrôles de faisabilité des règles (*Rule Conflicts and Errors*) : quelles combinaisons de règles sont désactivées d'office ?

---

### M09-E14 — Réplication ZFS entre nœuds  `LAB` `★★`

> **Ticket PLAT-1024** — *De : Karim Benali*
> Tout ne mérite pas Ceph : trois copies synchrones coûtent cher en disque et en latence. Pour les VMs qui tolèrent de perdre quelques minutes d'écritures, InfoGér utilisait la réplication ZFS de Proxmox. Mets-la en place sur une VM de démonstration, mesure ce qu'on perd vraiment, et dis-moi quand je dois la préférer à Ceph.

**Objectifs pédagogiques**
- Configurer la réplication asynchrone de Proxmox VE (`pvesr`) sur un stockage ZFS local.
- Comprendre le mécanisme (instantanés ZFS, envoi incrémental, horaires, limitation de débit) et le RPO qui en résulte.
- Migrer une VM répliquée, et savoir ce que la HA peut ou non faire avec une réplication.

**Prérequis** : M09-E06 (stockage `zfs-local`, pool `tank` sur chaque nœud), M09-E13.
**Durée indicative** : 1 h 30.

**Contexte technique**
- La réplication exige un stockage ZFS **du même nom**, sur un pool **du même nom**, sur la source et les cibles : c'est pourquoi `zfs-local`/`tank` existe à l'identique sur les trois nœuds depuis le palier 1.
- VM de démonstration : `rep01` (VMID 110), clone complet de 199 avec son disque sur `zfs-local`, sur `hv01`.
- Tâches à créer : vers `hv02` et vers `hv03`, toutes les 10 minutes, débit limité à 20 Mo/s. Identifiants imposés par Proxmox : `<VMID>-<n>`.
- Le transfert passe en SSH entre nœuds, par le réseau de migration (ici MGMT, tant que M09-E27 ne l'a pas changé).

**Travail demandé**
1. Crée `rep01` et vérifie que son disque est un *zvol* de `tank` sur `hv01`.
2. Crée les deux tâches de réplication. Lance la première synchronisation sans attendre l'horaire et suis-la (`pvesr status`, journal de la tâche).
3. Sur la source et sur une cible, liste les instantanés ZFS du disque de `rep01`. Comment s'appellent-ils, combien en reste-t-il après plusieurs passages, et pourquoi ?
4. Mesure le RPO : écris un fichier horodaté dans `rep01` toutes les minutes pendant 25 minutes (une ligne de `cron` ou une boucle), puis lis l'état du disque répliqué **sans démarrer la VM sur la cible** (un instantané de réplication se clone et se monte en lecture). Quelle est la dernière ligne présente ? Compare avec l'horaire.
5. Migre `rep01` vers `hv02` à chaud. Combien de données ont été transférées, comparé à une migration avec disques locaux non répliqués (E11) ? Que sont devenues les tâches de réplication (source, cibles) après la migration ?
6. Réponds dans ton journal :
   - (a) Si `hv02` tombe pendant que `rep01` y tourne, que peut faire la HA, et avec quelle perte de données ?
   - (b) Pourquoi une VM répliquée sous HA devrait-elle être limitée par une règle d'affinité de nœud **stricte** aux nœuds qui ont une copie ?
   - (c) Ceph ou réplication ZFS : trois critères de choix, pour MédiSphère.
7. Remets `rep01` sur `hv01` ; garde-la et ses deux tâches : le palier 4 s'en sert.

**Critères de réussite**
- [ ] `rep01` (110) existe, son disque est sur `zfs-local`.
- [ ] Deux tâches de réplication de 110, vers les deux autres nœuds, horaire `*/10`, débit 20 ; dernière synchronisation de moins de 30 minutes, sans échec en cours.
- [ ] Les deux nœuds cibles ont une copie du disque de `rep01` avec un instantané de réplication.
- [ ] Ton journal donne le RPO mesuré et répond aux questions de l'étape 6.

**Vérification** : `lab/bin/check 09 14`

<details><summary>Indice 1</summary>

`pvesr help create-local-job --verbose` ; `pvesr schedule-now <ID>` lance une tâche hors horaire ; `pvesr status` résume l'état de toutes les tâches du nœud.
</details>

<details><summary>Indice 2</summary>

`zfs list -t snapshot -r tank` ; un instantané se monte par un clone (`zfs clone`) ou s'expose comme périphérique bloc (le *zvol* `…@instantané` n'est pas directement montable). Pense à **détruire** ton clone de lecture : il bloquerait la réplication suivante.
</details>

<details><summary>Indice 3</summary>

La migration d'une VM répliquée ne transfère que ce qui a changé depuis la dernière synchronisation ; ensuite, Proxmox **inverse** les tâches. Lis `/etc/pve/replication.cfg` avant et après.
</details>

**Pour aller plus loin** (facultatif) : chapitre *Storage Replication* (<https://pve.proxmox.com/pve-docs/chapter-pvesr.html>) ; option `replication` de `datacenter.cfg` (réseau dédié à la réplication) ; ce que la réplication **ne** fait **pas** : une sauvegarde (une suppression ou un chiffrement par un rançongiciel se réplique aussi).

---

### M09-E15 — Sauvegarder le cluster vers PBS  `LAB` `★★`

> **Ticket PLAT-1025** — *De : Sophie Laurent*
> Les VMs du cluster seront des VMs de production : sauvegardées chaque nuit à PAR2, **chiffrées côté client** (le site de secours ne doit pas pouvoir lire nos données de santé), avec un compte qui peut sauvegarder mais pas effacer, et une restauration testée — pas « testable ». Je veux aussi savoir où est la clé de chiffrement, et comment on la retrouve le jour où `hv-par1` a brûlé.

**Objectifs pédagogiques**
- Raccorder un cluster à Proxmox Backup Server avec un compte, un jeton et un *namespace* dédiés, à privilèges minimaux.
- Chiffrer les sauvegardes côté client, et organiser la conservation de la clé hors du cluster.
- Planifier une tâche de sauvegarde de cluster, puis restaurer : VM complète, restauration à chaud (*live-restore*), fichier isolé.

**Prérequis** : M00 (PBS, datastore `ds-lab`, namespace `par1`, stockage `pbs-par2` de `pve01`, tâche d'élagage) ; M09-E11.
**Durée indicative** : 2 h 30.

**Contexte technique**
- `pbs01` : 10.20.10.10, PBS 4.x, datastore `ds-lab`. Namespace à créer : `par1/hv` (sous `par1`). Compte : `wb-hv@pbs`, jeton `wb-hv@pbs!hv-par1`, rôle `DatastoreBackup` sur ce seul namespace, pour l'utilisateur **et** le jeton.
- Stockage à créer sur `hv-par1` : `pbs-par2` (même nom que sur `pve01`, mais c'est un autre cluster : rien n'est partagé), empreinte du certificat de `pbs01` épinglée.
- Flux : les nœuds (MGMT 10.10.10.51-53) vers `pbs01` TCP 8007, à travers la bordure et `wg0`. Vérifie dans la matrice des flux s'il est déjà couvert, et décide s'il faut une ligne explicite.
- Clé de chiffrement : générée par Proxmox VE (sans phrase de passe), à conserver dans Vault (`critique`) **et** sur papier (*paperkey*), au registre des secrets.
- Tâche de sauvegarde : `hv-nuit`, toutes les VMs du cluster, mode `snapshot`, chaque jour à 03:15 (après la sauvegarde de `pve01` à 02:30). La rétention est appliquée **par PBS**.
- VM de restauration : `restau01` (VMID 127), détruite après chaque essai.

> ⚠️ **Attention** : tu modifies `pbs01`, qui garde les sauvegardes de tout le lab. Avant : relève l'état (`proxmox-backup-manager acl list`, `user list`, liste des namespaces) pour pouvoir revenir en arrière. Ne touche ni à `wb-backup@pbs` ni au namespace `par1` lui-même. Retour arrière : supprimer le jeton, l'ACL, l'utilisateur `wb-hv@pbs`, puis le namespace `par1/hv` **vide**.

**Travail demandé**
1. Sur `pbs01` : crée le namespace, l'utilisateur, le jeton et les ACL. Vérifie les droits effectifs du jeton sur `par1/hv` **et** sur `par1`.
2. Lis la tâche d'élagage de `par1` (M00) : s'appliquera-t-elle aux sauvegardes de `par1/hv` ? Justifie par son paramètre de profondeur. Décide s'il faut une tâche propre à `par1/hv` et fais-le.
3. Sur le cluster : ajoute `pbs-par2` avec le jeton (secret saisi sans écho ni historique), le namespace, l'empreinte, et une clé de chiffrement générée automatiquement. Où sont rangés le secret et la clé ? Sur quels nœuds sont-ils lisibles ?
4. Mets la clé à l'abri : copie dans Vault (`critique`) sans écrire la clé en clair sur `adm01`, version papier (*paperkey*), registre des secrets. Explique dans ton journal pourquoi une clé qui n'existe que dans `/etc/pve` ne protège de rien le jour du sinistre.
5. Crée la tâche `hv-nuit`, puis lance-la une fois tout de suite. Lis le journal : chiffrement annoncé ? Volume transféré à la deuxième exécution ?
6. Restaurations, chacune dans `restau01` (127) sur `ceph-vm`, avec des adresses MAC uniques et la carte réseau débranchée, puis destruction :
   - (a) restauration complète de `app02` ; durée ;
   - (b) restauration à chaud (*live-restore*) : à partir de quand la VM démarre-t-elle ? Quel est le risque si `pbs01` devient injoignable pendant l'opération ?
   - (c) restauration d'un seul fichier (`/etc/hostname` de `app03`) sans restaurer la VM.
7. Côté `pbs01`, vérifie que les sauvegardes de `par1/hv` sont bien chiffrées (colonne ou champ de chiffrement), et lance une vérification (*verify*) du namespace.

**Critères de réussite**
- [ ] Sur `pbs01` : namespace `par1/hv` ; `wb-hv@pbs` et son jeton ont `DatastoreBackup` sur `/datastore/ds-lab/par1/hv` et rien de plus large.
- [ ] Sur `hv-par1` : stockage `pbs-par2` actif, namespace `par1/hv`, jeton `wb-hv@pbs!hv-par1`, empreinte épinglée, clé de chiffrement configurée.
- [ ] Tâche `hv-nuit` activée, quotidienne à 03:15, mode `snapshot`, toutes les VMs, sans élagage côté client.
- [ ] Au moins une sauvegarde chiffrée de moins de 48 heures pour `app01`, `app02` et `app03`.
- [ ] `restau01` (127) n'existe plus ; la clé est dans Vault et au registre des secrets.

**Vérification** : `lab/bin/check 09 15`

<details><summary>Indice 1</summary>

Le module 00 a fait la même chose pour `pve01` (M00-E22 et son corrigé) : `proxmox-backup-manager user create`, `user generate-token`, `acl update`, `user permissions`. Un namespace imbriqué se crée par son chemin complet.
</details>

<details><summary>Indice 2</summary>

`pvesm help add --verbose` : options `--namespace`, `--fingerprint`, `--encryption-key` (lis la valeur spéciale qu'elle accepte). La section *Proxmox Backup Server* de `pvesm(1)` dit où sont rangés mot de passe et clé, et comment produire la *paperkey*.
</details>

<details><summary>Indice 3</summary>

`qmrestore --help` : `--unique`, `--live-restore`, `--storage`. Pour la restauration d'un fichier : interface web (*Restauration de fichier* sur la sauvegarde) ou `proxmox-file-restore` sur un nœud, qui a besoin de la clé.
</details>

**Pour aller plus loin** (facultatif) : une **clé maîtresse** RSA (`--master-pubkey`) ajoute à chaque sauvegarde une copie chiffrée de la clé, récupérable avec la clé privée maîtresse conservée hors ligne ; compare avec la *paperkey*. Synchronisation de `ds-lab` vers un second PBS (*sync jobs*, *pull*) : <https://pbs.proxmox.com/docs/managing-remotes.html>.

---

### M09-E16 — SDN du cluster : zones, VNets et EVPN  `LAB` `★★★`

> **Ticket PLAT-1026** — *De : Karim Benali*
> Aujourd'hui, chaque VM du cluster est branchée sur `vmbr1` avec une étiquette VLAN tapée à la main : une faute de frappe et la VM atterrit dans le mauvais réseau. Je veux que les réseaux des invités soient des **objets du cluster**, nommés, avec des droits. Et puisqu'OpenStack et Kubernetes vont nous parler de VXLAN et de BGP EVPN, monte un réseau EVPN interne au cluster : deux sous-réseaux routés entre eux, qui suivent les VMs quand elles migrent. Il ne sort pas du cluster pour l'instant.

**Objectifs pédagogiques**
- Définir les réseaux des invités au niveau du cluster avec le SDN de Proxmox VE : zone, VNet, sous-réseau, application de la configuration.
- Monter une zone EVPN (VXLAN + BGP EVPN par FRR) avec passerelle *anycast*, et comprendre le rôle du contrôleur, du VRF et du MTU.
- Utiliser l'IPAM intégré.

**Prérequis** : M07 (VLAN, MTU, BGP, FRR) ; M09-E06 (`vmbr1` VLAN-aware sur les nœuds, trunk `net4`) ; M09-E11.
**Durée indicative** : 3 h.

**Contexte technique**
- Zone VLAN `invites` sur le pont `vmbr1` des nœuds ; VNet `vinv99` (étiquette 99) : le VLAN SANDBOX du lab (DHCP Kea, passerelle 10.10.99.1). Les identifiants de zone et de VNet font **8 caractères au plus**.
- EVPN : contrôleur `evpnhv` (AS 65090, plan d'AS du PLAN), pairs = adresses MGMT des trois nœuds (10.10.10.51-53) ; zone `evhv`, VNI du VRF 10090, MTU 1450 ; VNets `vevpn1` (VNI 11001, 10.90.1.0/24, passerelle 10.90.1.1) et `vevpn2` (VNI 11002, 10.90.2.0/24, passerelle 10.90.2.1). Pas de nœud de sortie (*exit node*) : ces réseaux ne sont pas routés vers le lab.
- FRR : le SDN utilise le paquet `frr` **des dépôts Proxmox** et `frr-pythontools`. N'ajoute pas sur les nœuds le dépôt FRR du module 07 (deb.frrouting.org).
- VMs de test : `evpn01` (140) sur `vevpn1`, adresse 10.90.1.10/24, et `evpn02` (141) sur `vevpn2`, 10.90.2.10/24, sur deux nœuds différents ; accès par la console (`qm terminal`) : elles ne sont pas joignables depuis `adm01`.

> ⚠️ **Attention** : l'application de la configuration SDN recharge le réseau de **tous** les nœuds (`ifreload`). Une erreur sur `vmbr0` couperait l'administration du nœud et un lien Corosync. Avant d'appliquer : vérifie que `/etc/network/interfaces` de chaque nœud se termine par l'inclusion des fichiers du SDN, et garde une console série ouverte (`qm terminal 2091` depuis `pve01`). Retour arrière : supprimer la zone ou le VNet fautif et réappliquer.

**Travail demandé**
1. Prépare les nœuds (FRR et ses outils, service activé, inclusion des fichiers du SDN). Vérifie que FRR ne porte aucune configuration héritée.
2. Crée la zone `invites` et le VNet `vinv99`, applique. Que crée Proxmox sur chaque nœud (`ip -d link show vinv99`, `/etc/network/interfaces.d/sdn`) ? Branche `app01` sur `vinv99` à la place de `vmbr1` + étiquette, sans changer son adresse.
3. Crée le contrôleur EVPN, la zone `evhv`, les VNets `vevpn1`, `vevpn2` et leurs sous-réseaux (IPAM `pve`), applique. Lis la configuration FRR générée sur un nœud : sessions BGP, famille `l2vpn evpn`, VRF.
4. Contrôle le plan de contrôle : sur chaque nœud, les sessions EVPN vers les deux autres sont établies ; quelles routes de type 2 et 5 vois-tu une fois les VMs démarrées ?
5. Crée `evpn01` et `evpn02` (clones de 199, adresses statiques par cloud-init, passerelle = adresse *anycast* du VNet). Depuis `evpn01`, joins `evpn02` : par où passe le paquet (`tcpdump` sur l'interface VXLAN d'un nœud) ?
6. Lance un `ping` continu d'`evpn01` vers `evpn02`, migre `evpn02` à chaud vers le troisième nœud : combien de paquets perdus ? Pourquoi la passerelle *anycast* rend-elle la migration transparente ?
7. Réponds dans ton journal : pourquoi un MTU de 1450 dans la zone EVPN alors que MGMT est à 1500 ? Que faudrait-il pour que `vevpn1` soit joignable depuis le lab (et quels risques pour la bordure) ? Que fait l'IPAM `pve`, et que ne fait-il pas, comparé à NetBox ?

**Critères de réussite**
- [ ] Zone VLAN `invites` (pont `vmbr1`) et VNet `vinv99` (étiquette 99) appliqués sur les trois nœuds ; `app01` est branchée sur `vinv99`.
- [ ] Contrôleur `evpnhv` (AS 65090, trois pairs), zone EVPN `evhv` (VRF 10090, MTU 1450), VNets `vevpn1`/`vevpn2` avec leurs sous-réseaux et passerelles ; configuration appliquée, rien en attente.
- [ ] Sur chaque nœud, deux sessions BGP EVPN établies.
- [ ] `evpn01` et `evpn02` existent sur deux nœuds différents, branchées sur `vevpn1` et `vevpn2`.

**Vérification** : `lab/bin/check 09 16`

<details><summary>Indice 1</summary>

La configuration se fait dans l'interface (*Datacenter → SDN*) ou par l'API (`pvesh create /cluster/sdn/zones …`, `…/vnets`, `…/vnets/<vnet>/subnets`, `…/controllers`) ; rien n'est actif tant que tu n'as pas **appliqué** (`pvesh set /cluster/sdn`). La page *Software-Defined Network* de la documentation liste les options de chaque type.
</details>

<details><summary>Indice 2</summary>

`vtysh -c 'show bgp l2vpn evpn summary'`, `vtysh -c 'show evpn vni'`, `vtysh -c 'show bgp l2vpn evpn route type 2'`. Le trafic VXLAN se voit sur l'interface d'administration du nœud en UDP 4789.
</details>

<details><summary>Indice 3</summary>

Dans une zone EVPN, chaque nœud porte l'adresse de passerelle de chaque VNet (même IP, même MAC). La VM qui migre garde la même passerelle, déjà présente sur le nœud d'arrivée ; le nouveau nœud annonce l'adresse MAC/IP de la VM en BGP.
</details>

**Pour aller plus loin** (facultatif) : les *fabrics* SDN de Proxmox VE 9 (OpenFabric, OSPF, et WireGuard ou BGP en 9.2) construisent le réseau sous-jacent et la liste des pairs à ta place : <https://pve.proxmox.com/pve-docs/chapter-pvesdn.html>. Les nœuds de sortie (*exit nodes*) et le SNAT : que faudrait-il ajouter côté `gw01`/`gw02` (sessions BGP en AS 65000) pour annoncer 10.90.0.0/16 au lab ?

---

### M09-E17 — Droits, pools et jetons du cluster  `LAB` `★★`

> **Ticket SEC-1027** — *De : Sophie Laurent*
> Sur le cluster, tout le monde travaille en `root@pam`. Pour l'audit HDS, il me faut : des comptes **nominatifs**, des droits par groupe et non par personne, l'astreinte capable de démarrer et redémarrer les VMs de production sans pouvoir les supprimer ni toucher au cluster, et un compte technique pour l'automatisation qui ne peut créer des VMs que dans la recette. Chaque droit doit pouvoir se justifier en une phrase.

**Objectifs pédagogiques**
- Organiser les droits de Proxmox VE : utilisateurs, groupes, rôles, chemins d'ACL, pools, propagation.
- Créer un rôle personnalisé à privilèges minimaux et un jeton à privilèges séparés pour l'automatisation.
- Vérifier des droits effectifs plutôt que des intentions.

**Prérequis** : M00 (comptes `wb-admin@pve`, `wb-automation@pve`) ; M05-E03 (rôle `WBTofu`, privilèges d'OpenTofu) ; M09-E11, M09-E16.
**Durée indicative** : 2 h.

**Contexte technique**
- Domaine d'authentification `pve` (comptes locaux au cluster) ; la fédération LDAP/OIDC viendra au module 24, la double authentification en M09-E26.
- Groupes : `hv-admins` (administration complète du cluster) ; `hv-ops` (astreinte : voir tout, démarrer, arrêter, redémarrer, ouvrir la console des VMs des pools `prod` et `recette`, rien d'autre).
- Comptes : `<MOI>@pve` (toi, `hv-admins`) ; `nadia.roussel@pve` (`hv-ops`).
- Pools : `prod` (`app01-03`, `rep01`) et `recette` (VMs 130-139 qu'OpenTofu créera en E18).
- Compte technique : `wb-tofu-hv@pve`, jeton `wb-tofu-hv@pve!tofu` (privilèges séparés, expiration à un an), rôle personnalisé `WBTofuHV` : ce dont a besoin le provider `bpg/proxmox` pour **cloner le template 199** vers le pool `recette`, sur `ceph-vm`, branché sur `vinv99`, le configurer, le **démarrer** (Proxmox VE 9.2 exige `VM.PowerMgmt` pour démarrer une VM après sa création), lire ses adresses par l'agent, et le détruire.
- Le secret du jeton va dans `~/.config/workbook/pve-tofu-hv.env` (600) sur `adm01` (variables `PROXMOX_VE_ENDPOINT` et `PROXMOX_VE_API_TOKEN`, comme `pve-tofu.env` au M05) et au registre des secrets.

**Travail demandé**
1. Lis la section *User Management* de la documentation : comment se combinent les ACL d'un utilisateur, de ses groupes et d'un jeton à privilèges séparés ? Que fait la propagation ? Qu'est-ce qu'un pool apporte aux ACL ?
2. Crée les pools et place-y les VMs. Crée les groupes, les deux comptes nominatifs (mots de passe saisis sans écho) et les ACL des groupes. Pour `hv-ops`, choisis des rôles **prédéfinis** et justifie chaque chemin.
3. Écris la liste des privilèges de `WBTofuHV` en partant de celle de `WBTofu` (M05-E03) : qu'est-ce qui change dans un cluster (migration ? template partagé ? zone SDN différente ?) et dans Proxmox VE 9.2 ? Crée le rôle, le compte, le jeton et ses ACL, chemin par chemin. Fais-en un script rejouable (comme au M05).
4. Vérifie les droits **effectifs** : `pveum user permissions` pour `nadia.roussel@pve` (sur `/pool/prod`, `/vms/101`, `/nodes/hv01`) et pour le jeton (sur `/`, `/pool/recette`, `/vms/101`). Le jeton ne doit rien avoir sur `/` ni sur `/pool/prod`.
5. Teste en conditions réelles : connecte-toi à l'interface en tant que Nadia, redémarre `app02`, essaie de supprimer `app03` et d'ouvrir le shell de `hv01`. Avec le jeton (`curl` sur l'API, en-tête passé par un fichier ou l'entrée standard, autorité du cluster `/etc/pve/pve-root-ca.pem` copiée sur `adm01` et passée en `--cacert` : elle n'entrera dans le magasin du système qu'en E18), lis `/cluster/resources` : quelles VMs vois-tu ?
6. Réponds dans ton journal : pourquoi un jeton à privilèges **séparés** (`privsep`) plutôt qu'un jeton qui hérite de son utilisateur ? Pourquoi les ACL sur des **groupes** et des **pools** plutôt que sur des personnes et des VMID ?

**Critères de réussite**
- [ ] Pools `prod` (101, 102, 103, 110) et `recette` ; groupes `hv-admins` et `hv-ops` ; `<MOI>@pve` dans `hv-admins`, `nadia.roussel@pve` dans `hv-ops`.
- [ ] `hv-ops` a les droits de démarrage/arrêt/console sur `prod` et `recette` mais pas `VM.Allocate` ni `Sys.Modify`.
- [ ] Rôle `WBTofuHV` avec `VM.PowerMgmt`, sans `Sys.*`, `Permissions.*`, `Datastore.Allocate`, `Pool.Allocate` ; jeton `wb-tofu-hv@pve!tofu` à privilèges séparés, avec expiration, sans aucun droit sur `/` ni sur `/pool/prod`.
- [ ] `pve-tofu-hv.env` en 600 sur `adm01` ; le jeton répond à l'API depuis `adm01`.

**Vérification** : `lab/bin/check 09 17`

<details><summary>Indice 1</summary>

Rôles prédéfinis utiles : `PVEAuditor` (lecture), `PVEVMUser` (utilisation des VMs : alimentation, console, CD-ROM, sauvegarde), `PVETemplateUser` (cloner un template). `pveum role list` les détaille. Les droits d'un jeton à privilèges séparés sont l'**intersection** de ceux du jeton et de ceux de l'utilisateur.
</details>

<details><summary>Indice 2</summary>

Le provider clone 199 : il lui faut un droit sur `/vms/199` (le template n'est pas dans `recette`). Pour brancher une carte sur un VNet : `SDN.Use` sur `/sdn/zones/<zone>/<vnet>`. Pour poser un disque : `Datastore.AllocateSpace` sur `/storage/<stockage>`.
</details>

<details><summary>Indice 3</summary>

`pveum user token permissions <utilisateur> <jeton> --path <chemin>` donne les droits effectifs d'un jeton. Un `curl` qui lit `/api2/json/cluster/resources` avec l'en-tête `Authorization: PVEAPIToken=<utilisateur>!<jeton>=<secret>` vérifie le tout de bout en bout.
</details>

**Pour aller plus loin** (facultatif) : la section *Permission Management* de `pveum(1)` (<https://pve.proxmox.com/pve-docs/pveum.1.html>), et les privilèges ajoutés ou retirés par Proxmox VE 9 (`VM.Replicate`, disparition de `VM.Monitor`) dans les notes de version.

---

### M09-E18 — Piloter le cluster par le code  `LIBRE` `★★★`

> **Ticket PLAT-1028** — *De : Julien Petit*
> L'équipe MédiAgenda veut des VMs de recette sur le nouveau cluster comme elle en avait sur `pve01` : par une MR, pas par un ticket. Mais je lis que votre point d'entrée, c'est l'adresse de `hv01` : si `hv01` est en maintenance, plus de pipeline ? Il me faut une adresse du cluster qui marche tant qu'il reste un nœud vivant, et un certificat qui ne fasse pas hurler les outils.

**Objectifs pédagogiques**
- Concevoir un point d'accès stable et sûr à l'API d'un cluster sans répartiteur de charge.
- Étendre le chemin imposé (OpenTofu, Ansible, CI, secrets, flux) à un second « hyperviseur » qui n'est pas `pve01`.
- Résoudre la question du certificat d'un nom partagé par plusieurs serveurs.

**Prérequis** : M05 (OpenTofu, `bpg/proxmox`, état distant chiffré, pipeline de `plateforme/infra`) ; M07 (keepalived, VRRP) ; M06 (DNS, PKI) ; M09-E17.
**Durée indicative** : 5 h à 7 h.

**Contexte technique**
- Point d'accès choisi par l'équipe (décision du PLAN) : une VIP keepalived 10.10.10.200 sur le réseau MGMT, nommée `hv.par1.medisphere.internal`, VRID 110, portée par l'un des nœuds du cluster, posée par un rôle Ansible `pve_cluster` dans `plateforme/ansible`. L'adresse de la VIP doit suivre un nœud **sain** (membre d'un cluster qui a le quorum, API en service).
- Le certificat que présente chaque nœud sur le port 8006 est aujourd'hui signé par l'autorité **du cluster** (créée à la formation du cluster) et ne contient que les noms et adresses du nœud.
- État OpenTofu : `envs/hv-invites` dans `plateforme/infra` (même compartiment `tofu-state`, état chiffré, verrou natif) ; provider `bpg/proxmox` à la version épinglée du projet ; jeton `wb-tofu-hv@pve!tofu` d'E17. La CI (`runner01`, VLAN INFRA) doit pouvoir planifier et appliquer.
- VMs à livrer : deux VMs de recette `rec01`, `rec02` (VMID 130, 131), clones de 199 dans le pool `recette`, sur `ceph-vm`, branchées sur `vinv99`, adresse par DHCP, étiquette Proxmox `tofu`, démarrées.

**Travail demandé**
Livre, par MR sur les projets concernés, de quoi créer et détruire des VMs de recette sur `hv-par1` par le pipeline, à travers un point d'accès qui survit à la perte de n'importe quel nœud. Contraintes :
- la VIP n'est portée que par un nœud sain ; elle bascule seule en moins de dix secondes quand ce nœud perd le quorum, son API, ou s'arrête ; elle ne « rebondit » pas inutilement quand il revient ;
- le nom `hv.par1.medisphere.internal` est publié par le chemin du module 06 (NetBox, DNS) ;
- **TLS vérifié partout** : ni `insecure = true`, ni `curl -k`. Le certificat présenté par la VIP est valide pour ce nom, quel que soit le nœud qui la porte, et son renouvellement est prévu. Compare au moins deux façons d'y arriver dans la MR, et justifie celle que tu retiens ;
- les secrets (jeton, et toute clé que ta solution introduit) ne sont ni dans un dépôt, ni sur une ligne de commande ; le registre des secrets est à jour ;
- tout nouveau flux réseau (la CI vers l'API du cluster…) passe par la matrice des flux ;
- `tofu plan` sur `main` est vide après l'`apply` ; un `destroy` ne laisse rien ;
- la démonstration : `rec01` et `rec02` créées par le pipeline ; puis arrête le nœud qui porte la VIP (proprement, après l'avoir mis en maintenance) et relance un `plan` depuis la CI : il doit passer sans rien changer ; remets le nœud en service.

**Critères de réussite**
- [ ] `hv.par1.medisphere.internal` résout en 10.10.10.200 ; `https://hv.par1.medisphere.internal:8006` présente un certificat valide (vérifié par le magasin de confiance d'`adm01` et de `runner01`).
- [ ] keepalived tourne sur les trois nœuds ; la VIP est portée par exactement un nœud ; elle a basculé lors de la démonstration.
- [ ] `envs/hv-invites` est sur `main` de `plateforme/infra`, avec un provider épinglé et un état distant chiffré ; le rôle `pve_cluster` est sur `main` de `plateforme/ansible`.
- [ ] `rec01` (130) et `rec02` (131) existent dans le pool `recette`, étiquetées `tofu`, sur `ceph-vm`, démarrées ; aucune autre VM ne porte l'étiquette `tofu` en dehors de `recette`.
- [ ] La MR compare les solutions de certificat et documente le renouvellement.

**Vérification** : `lab/bin/check 09 18`

<details><summary>Indice 1</summary>

Un script de suivi de keepalived peut interroger l'état local du cluster (quorum) et du service d'API ; la priorité de l'instance dépend alors de la santé du nœud. Relis ce que tu as fait au module 07 sur les annonces *unicast*, l'option qui empêche la reprise automatique, et les VRID déjà utilisés dans le lab.
</details>

<details><summary>Indice 2</summary>

Un certificat valable pour un nom porté tour à tour par trois serveurs : soit chaque nœud en possède un qui contient **aussi** ce nom, soit le nom est servi par un intermédiaire. Pour un défi ACME HTTP-01, demande-toi quel nœud reçoit la requête de validation de `ca01` quand le nom est celui de la VIP. Lis ce que `pvenode cert set` et le stockage des certificats de nœud (`/etc/pve/nodes/<nœud>/`) permettent.
</details>

<details><summary>Indice 3</summary>

Le provider `bpg/proxmox` (Go) vérifie le certificat avec le magasin du système, comme au M05 pour `pve01` (M03-E02 a installé l'ancre de `pve01` sur `adm01` et `runner01`). Le job `validate` des MR n'a pas besoin du jeton ; le `plan` si.
</details>

**Pour aller plus loin** (facultatif) : un répartiteur (`lb01`/`lb02`, M07) devant les trois API, avec contrôle de santé : ce qu'il apporterait (répartition, un seul certificat) et ce qu'il coûterait (dépendance du cluster envers la DMZ, sessions de la console). La ressource `proxmox_virtual_environment_cluster_options` du provider gère `datacenter.cfg` : quels réglages du cluster mettrais-tu dans le code ?

---

### M09-E19 — Mises à jour progressives des nœuds  `LAB` `★★`

> **Ticket CHG-1029** — *De : Nadia Roussel*
> Les nœuds ont des mises à jour en attente, dont un noyau. Fenêtre jeudi 21 h. Règles du jeu : un nœud à la fois, les VMs ne s'arrêtent pas, Ceph ne commence pas à recopier des données parce qu'un nœud redémarre, et on ne passe au nœud suivant que si le précédent est revenu **en entier**. Je veux la procédure en code, pas dans ta tête.

**Objectifs pédagogiques**
- Mettre à jour un cluster Proxmox VE avec Ceph hyperconvergé nœud par nœud, sans interruption des VMs.
- Enchaîner mode maintenance HA, drapeaux Ceph, mise à jour, redémarrage et contrôles de retour, et les automatiser.
- Savoir ce qui distingue une mise à jour mineure d'une montée de version majeure.

**Prérequis** : M04 (playbooks, `serial`, `pre_tasks`/`post_tasks`) ; M09-E10, M09-E13 ; idéalement M09-E18 (rôle et inventaire des nœuds).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Dépôts des nœuds : `no-subscription` de Proxmox VE et de Ceph (Squid), au format deb822 (`/etc/apt/sources.list.d/*.sources`). Le dépôt `enterprise` doit être désactivé (sans abonnement, il renvoie 401).
- Proxmox demande `apt full-upgrade` (ou `dist-upgrade`), jamais `apt upgrade`, sur un nœud Proxmox VE.
- Pendant le redémarrage d'un nœud, ses OSD disparaissent : sans précaution, Ceph les marque `out` au bout de `mon_osd_down_out_interval` et recopie leurs données ailleurs.
- Inventaire Ansible des nœuds : groupe `hv_par1` de `inventories/lab/hv.yml` (connexion `root`, M09-E03), à côté du playbook `playbooks/hv.yml` du rôle `pve_noeud`. Exécution depuis `adm01`, ou depuis le pipeline si tu l'as raccordé en E18.

> ⚠️ **Attention** : ne mets jamais deux nœuds en maintenance en même temps : avec un seul nœud actif, Ceph passe sous `min_size` (écritures bloquées) et la HA n'a plus de place. Retour arrière d'un nœud qui ne redémarre pas sur le nouveau noyau : choisir l'ancien noyau au démarrage (console série depuis `pve01`), puis `proxmox-boot-tool kernel pin` ; laisser `noout` et la maintenance actifs jusqu'au retour.

**Travail demandé**
1. Relève l'état de départ sur chaque nœud : versions (`pveversion -v`), noyau en cours, paquets en attente, dépôts actifs. Vérifie que le cluster et Ceph sont sains.
2. Fais le premier nœud à la main, en notant chaque commande et son contrôle : mise en maintenance HA (et attente de l'évacuation), drapeau Ceph adapté, mise à jour, redémarrage si un noyau ou des bibliothèques l'exigent, contrôles de retour (quorum, OSD, services, HA), sortie de maintenance, retrait du drapeau. Combien de temps a duré la fenêtre pour ce nœud ?
3. Écris le playbook `playbooks/hv-mise-a-jour.yml` dans `plateforme/ansible` qui fait la même chose pour tous les nœuds, **un à la fois**, en s'arrêtant au premier contrôle en échec. Il doit pouvoir être relancé après une interruption sans laisser de nœud en maintenance ni de drapeau Ceph oublié.
4. Passe `ansible-lint` (profil `production`), puis applique-le aux deux nœuds restants. Pendant ce temps, garde un `ping` vers `app01` et `app02` : combien de paquets perdus au total ?
5. Réponds dans ton journal : qu'est-ce qui changerait pour une montée de version **majeure** (Proxmox VE 9 → 10) ? Cherche l'outil de vérification que Proxmox fournit pour chaque montée majeure et ce qu'il contrôle. Pourquoi la montée de Ceph (E28) ne se fait-elle pas avec ce playbook ?

**Critères de réussite**
- [ ] Les trois nœuds ont la même version de `pve-manager` et tournent sur le noyau le plus récent installé.
- [ ] Aucun dépôt `enterprise` actif ; dépôts `no-subscription` de Proxmox VE et de Ceph présents.
- [ ] Aucun nœud en maintenance HA ; drapeau `noout` (ou `noout` du nœud) absent ; Ceph `HEALTH_OK`.
- [ ] `playbooks/hv-mise-a-jour.yml` est sur `main` de `plateforme/ansible`, propre pour `ansible-lint`, et fonctionne par un seul nœud à la fois.

**Vérification** : `lab/bin/check 09 19`

<details><summary>Indice 1</summary>

`ha-manager crm-command node-maintenance enable <nœud>` ; le nœud a fini d'évacuer quand plus aucune ressource HA « active » n'y tourne (`ha-manager status`). Côté Ceph, compare `ceph osd set noout` et `ceph osd set-group noout <hôte>` : lequel limite l'effet au seul nœud ?
</details>

<details><summary>Indice 2</summary>

`needrestart` ou la présence de `/var/run/reboot-required` (et la comparaison du noyau en cours avec le plus récent installé) disent s'il faut redémarrer. Dans Ansible : `serial: 1`, `any_errors_fatal`, `ansible.builtin.reboot` avec un `test_command`, `until`/`retries` pour attendre un état.
</details>

<details><summary>Indice 3</summary>

Pour qu'une relance après interruption soit sûre, le playbook doit commencer par **constater** l'état (un nœud déjà en maintenance, un drapeau déjà posé) et le traiter, pas seulement poser et retirer dans le même passage. Un bloc `block`/`rescue`/`always` aide à ne pas laisser un drapeau posé quand une tâche échoue — mais réfléchis : veux-tu vraiment retirer `noout` si le nœud n'est pas revenu ?
</details>

**Pour aller plus loin** (facultatif) : la page *Upgrade from 8 to 9* du wiki Proxmox (<https://pve.proxmox.com/wiki/Upgrade_from_8_to_9>) et son outil `pve8to9` : quels contrôles réutiliserais-tu pour la prochaine majeure ? Lis le fonctionnement de `proxmox-boot-tool`.

---

### M09-E20 — Évacuer un nœud, équilibrer la charge  `LAB` `★★`

> **Ticket PLAT-1030** — *De : Claire Morel*
> Deux choses que j'ai vues chez InfoGér et que je ne veux plus voir. Un : un technicien redémarre un nœud « pour voir », les VMs restent figées dessus pendant tout le redémarrage. Deux : après trois mois, toutes les VMs sont sur le même nœud parce que c'est là qu'on les avait démarrées, et il sature pendant que les autres dorment. Proxmox VE 9.2 sait équilibrer ; règle-le, et montre-moi les limites.

**Objectifs pédagogiques**
- Choisir la politique d'arrêt HA et la tester : ce qui arrive aux VMs HA quand on arrête ou redémarre un nœud.
- Évacuer un nœud (mode maintenance, migration de masse) et comprendre la différence entre ressources HA et VMs non HA.
- Configurer le planificateur de ressources du cluster (CRS) et l'équilibrage automatique de Proxmox VE 9.2 ; savoir désarmer la HA pour une intervention sur le réseau du cluster.

**Prérequis** : M09-E13.
**Durée indicative** : 2 h.

**Contexte technique**
- Réglages du cluster dans `/etc/pve/datacenter.cfg` (interface : *Datacenter → Options*) : politique d'arrêt HA (`ha: shutdown_policy=…`), planificateur (`crs: ha=…`, `ha-rebalance-on-start`, options `ha-auto-rebalance*` de 9.2).
- Choix de Claire : un nœud qu'on arrête ou redémarre **migre** d'abord ses VMs HA ; le planificateur tient compte de la charge **réelle** (CPU et mémoire consommés, pas seulement configurés) ; démarrer une VM HA arrêtée la place sur le nœud le plus adapté ; l'équilibrage automatique est actif, avec un seuil de déséquilibre de 40 %.
- 9.2 apporte aussi `ha-manager crm-command disarm-ha` / `arm-ha` : relâcher tous les *watchdogs* du cluster le temps d'une intervention qui risque de faire perdre le quorum (réseau, Corosync).

> ⚠️ **Attention** : pendant que la HA est désarmée, une panne de nœud n'est ni détectée ni traitée. Garde la fenêtre la plus courte possible et réarme avant de quitter ton poste ; vérifie `ha-manager status` après chaque commande.

**Travail demandé**
1. Lis la section *Shutdown Policy* de `ha-manager(1)`. Avec la politique par défaut, redémarre `hv02` (`reboot`) et observe ce qu'il advient de ses VMs HA. Note le temps d'indisponibilité de chaque VM.
2. Applique la politique de Claire, recommence le même redémarrage, compare.
3. Évacue `hv03` pour une intervention longue (mode maintenance), y compris d'éventuelles VMs **non** HA (par exemple `evpn02`) : comment les déplaces-tu toutes en une commande ? Que se passe-t-il pour `rep01` si elle y est (disque local répliqué) ? Sors `hv03` de maintenance : où reviennent les VMs ?
4. Configure le planificateur et l'équilibrage automatique selon les choix de Claire. Puis crée un déséquilibre (place toutes les VMs démarrées sur `hv01`, charge CPU dans deux d'entre elles avec `stress-ng` ou une boucle) et observe pendant dix minutes : quelles migrations l'équilibreur déclenche-t-il, à quel rythme ? Quelle ressource ne bouge pas, et pourquoi (règles d'E13) ?
5. Désarme la HA en mode `freeze`, observe `ha-manager status` (état du *fencing*, des LRM), puis réarme. Dans quel cas choisirais-tu le mode `ignore` ?
6. Réponds dans ton journal : pourquoi l'équilibrage automatique ne concerne-t-il que les ressources HA ? Quel risque y a-t-il à régler un seuil trop bas dans un cluster de trois nœuds ?

**Critères de réussite**
- [ ] `datacenter.cfg` : politique d'arrêt `migrate` ; planificateur `dynamic`, `ha-rebalance-on-start` actif, équilibrage automatique actif avec un seuil de 40.
- [ ] Aucun nœud en maintenance ; la HA est armée ; toutes les ressources HA sont `started`.
- [ ] Les VMs HA démarrées ne sont pas toutes sur le même nœud, et les règles d'E13 sont respectées.
- [ ] Ton journal compare les deux redémarrages (étapes 1 et 2) et répond aux questions des étapes 3, 4 et 6.

**Vérification** : `lab/bin/check 09 20`

<details><summary>Indice 1</summary>

`pvesh set /cluster/options --crs '…' --ha '…'` modifie `datacenter.cfg` (les options et leurs valeurs sont dans `datacenter.cfg(5)`). La migration de toutes les VMs d'un nœud : `pvenode migrateall` (lis ses options, en particulier pour les disques locaux).
</details>

<details><summary>Indice 2</summary>

Le mode maintenance et la politique `migrate` ne déplacent que les ressources HA. L'équilibreur ne s'active qu'avec un planificateur qui mesure la charge (`static` ou `dynamic`) ; il attend que le déséquilibre dépasse le seuil pendant plusieurs tours (*hold duration*).
</details>

<details><summary>Indice 3</summary>

Une ressource exclue de l'équilibrage (`--auto-rebalance 0`) ou contrainte par une règle d'affinité stricte ne sera pas déplacée. La règle négative `frontaux-separes` restreint aussi les déplacements possibles.
</details>

**Pour aller plus loin** (facultatif) : sections *Cluster Resource Scheduling* et *Disarming HA for Cluster Maintenance* de `ha-manager(1)` (<https://pve.proxmox.com/pve-docs/ha-manager.1.html>) ; compare avec le DRS de VMware (seuils, recommandations manuelles ou automatiques).

---

### M09-E21 — Revue : la configuration de cluster du stagiaire  `REV` `★★`

> **Ticket PLAT-1031** — *De : Karim Benali* — *Copie : Lucas Martin*
> Lucas a préparé la configuration « de référence » du futur cluster de recette, à copier sur les nœuds après installation. Il l'a testée sur sa sandbox et tout est vert. Avant qu'on la fusionne, fais-lui une revue sérieuse : ce qui casserait le jour d'une panne, ce qui ouvrirait une porte, ce qui est simplement faux. Pour chaque défaut, l'impact chez nous et la correction.

**Objectifs pédagogiques**
- Relire une configuration Corosync, une configuration HA et une configuration de stockage comme elles se comporteront **en panne**, pas seulement au démarrage.
- Repérer les défauts de quorum, de placement, de partage de stockage et de privilèges.
- Rédiger une revue utile à son destinataire.

**Prérequis** : M09-E04, M09-E05, M09-E09 ; M09-E10 à M09-E15.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `ressources/M09-E21/` — `MR-lucas.md` (la description de la MR), `corosync.conf`, `ha-resources.cfg`, `ha-rules.cfg`, `storage.cfg`. Mots de passe et empreintes **fictifs**.
- Cluster visé : trois nœuds `hv01-03` avec la même architecture réseau que `hv-par1` (MGMT, COROSYNC, Ceph public et cluster), Ceph hyperconvergé, Ceph de PAR1 en stockage externe, PBS à PAR2.
- Lucas a testé sur trois VMs sans panne, sans pare-feu, seul utilisateur.

**Travail demandé**
1. Lis tout sans rien noter. Puis réponds : combien de voix au total, quel quorum, et quels nœuds peuvent tomber sans perte de quorum ? Par où passe le trafic Corosync ? Qui peut lire et modifier ce trafic ?
2. Pour chaque règle HA, décris ce que fera le gestionnaire HA : au démarrage, à la perte de `hv01`, à la perte de `hv02`. Lesquelles seront rejetées d'office ?
3. Pour chaque stockage, dis ce que pourrait faire un attaquant qui obtient `root` sur un nœud, et ce que ferait une migration à chaud.
4. Rédige la revue en tableau : n°, fichier et ligne(s), défaut, catégorie (sécurité, disponibilité, fonctionnement), gravité (critique, élevée, moyenne, faible), impact concret, correction.
5. Classe les défauts par ordre de traitement et justifie les deux premiers.
6. Propose les versions corrigées des quatre fichiers (les lignes qui changent).
7. Trois lignes de conseils à Lucas sur sa façon de tester une configuration de cluster.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 9 défauts identifiés, dont tous les défauts critiques et élevés du corrigé.
- [ ] Le calcul du quorum est juste et montre le scénario de panne qui le fait perdre.
- [ ] Chaque défaut a un impact concret dans notre lab et une correction précise (option, valeur, commande).

<details><summary>Indice 1</summary>

Pour le quorum : additionne les `quorum_votes`, calcule la majorité stricte, puis retire chaque nœud tour à tour. Lis `votequorum(5)` sur `two_node` : pour combien de nœuds cette option est-elle prévue, et qu'active-t-elle implicitement ?
</details>

<details><summary>Indice 2</summary>

Relis la liste des contrôles de faisabilité des règles HA dans `ha-manager(1)` (*Rule Conflicts and Errors*) : combien de règles d'affinité de nœud une ressource peut-elle avoir ? Combien de ressources une règle négative peut-elle séparer sur trois nœuds ?
</details>

<details><summary>Indice 3</summary>

Que signifie l'option `shared` d'un stockage pour Proxmox ? Elle ne **rend** pas un stockage partagé : elle **déclare** qu'il l'est. Que fera la migration d'une VM dont le disque est déclaré partagé sur un LVM local ?
</details>

**Pour aller plus loin** (facultatif) : écris les contrôles automatiques (un script lancé en CI sur la MR) qui auraient attrapé les quatre défauts les plus graves : somme des voix, chiffrement Corosync, `shared` sur un stockage local, identité `admin` ou `root@pam` dans `storage.cfg`.

---

### M09-E22 — Runbook : maintenance d'un nœud  `RED` `★★`

> **Ticket PLAT-1032** — *De : Nadia Roussel*
> Le jour où il faudra changer une barrette mémoire sur un nœud à 2 h du matin, ce ne sera pas forcément toi. Écris **RB-090** : sortir un nœud du cluster pour une intervention (logicielle ou matérielle, courte ou longue) et le remettre en service, sans interruption des VMs et sans réveiller Ceph. Je le jouerai sur `hv02`.

**Objectifs pédagogiques**
- Transformer les gestes d'E13, E19 et E20 en procédure exécutable par quelqu'un d'autre.
- Rendre chaque étape vérifiable, et prévoir les cas où elle échoue.
- Distinguer intervention courte (redémarrage) et longue (nœud éteint plusieurs heures), et leurs conséquences sur Ceph et la HA.

**Prérequis** : M09-E13, M09-E14, M09-E19, M09-E20.
**Durée indicative** : 2 h.

**Contexte technique**
- Emplacement : `docs/virtualisation/runbooks/RB-090-maintenance-noeud.md` dans `plateforme/medisphere`, sur le modèle des runbooks des modules précédents (RB-060 au M06).
- Cas à couvrir : redémarrage (noyau, micrologiciel) ; arrêt de quelques heures (matériel) ; nœud qui ne revient pas à l'heure prévue.
- Le runbook s'appuie sur ce qui existe : mode maintenance HA, politique d'arrêt `migrate` (E20), drapeaux Ceph (E19), réplication ZFS (E14), sauvegardes (E15), accès de secours (console série depuis `pve01`, puis iLO ou équivalent en production).

**Travail demandé**
Rédige RB-090 avec au moins : quand l'utiliser et quand ne pas l'utiliser (nœud déjà en panne → RB-091), prérequis (accès, droits, état du cluster et de Ceph, capacité des autres nœuds à absorber la charge, sauvegarde récente), contrôles d'entrée, étapes numérotées (chacune : commande ou écran, résultat attendu, que faire sinon), traitement des VMs non HA et des VMs à disque local répliqué, gestion de Ceph selon la durée de l'intervention, remise en service et retour des VMs, contrôles de sortie, retour arrière (abandon en cours de route), communication (qui prévenir, quand), pièges connus. Joue-le sur `hv02`, corrige chaque hésitation, fais-le relire par MR (Nadia et Karim).

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Quelqu'un qui n'a pas fait le module l'exécute sans question ; chaque étape a son contrôle et sa conduite en cas d'échec.
- [ ] La capacité des nœuds restants est vérifiée **avant** l'évacuation (mémoire, Ceph `min_size`).
- [ ] Le cas « intervention longue » traite Ceph (drapeaux, durée) et l'éventualité de laisser Ceph reconstruire.
- [ ] Aucun drapeau, aucun mode maintenance ne peut rester posé à la fin (contrôle de sortie explicite).

**Pour aller plus loin** (facultatif) : marque dans le runbook les étapes déjà automatisées par le playbook d'E19 et celles qui demandent un jugement humain ; propose un playbook `hv-maintenance.yml` (entrée/sortie de maintenance seulement) que l'astreinte lancerait.

---

### M09-E23 — Importer une VM venue d'ailleurs  `LAB` `★★`

> **Ticket PLAT-1033** — *De : Claire Morel*
> InfoGér nous a enfin livré l'export de Legacy-RDV, l'ancienne prise de rendez-vous : une OVA sortie de leur VMware, une fiche de deux lignes, et le mot de passe « à demander au support sous dix jours ». On ne va pas attendre. Importe-la dans le cluster, rends-la conforme à nos standards de VM (pilotes, agent, accès) et dis-moi ce qu'il faudra prévoir pour les vingt suivantes.

**Objectifs pédagogiques**
- Importer une VM au format OVA/OVF dans Proxmox VE (ligne de commande et assistant d'import), et vérifier son intégrité avant.
- Adapter le matériel virtuel d'une VM venue d'un autre hyperviseur : contrôleur de disque, carte réseau, type de CPU, agent.
- Reprendre la main sur une VM dont on n'a pas les identifiants, proprement.

**Prérequis** : M09-E11 ; M03 (cloud-init) ; M00 (agent QEMU).
**Durée indicative** : 2 h.

**Contexte technique**
- Ressources : `ressources/M09-E23/` (fiche d'InfoGér, `generer-ova.sh` qui fabrique l'OVA, modèle de descripteur). Lis le `README.md` du dossier : il dit où et comment générer l'OVA (sur `hv01`, dans le dossier d'import du stockage `local`).
- VM cible : `legacy-rdv01`, VMID 150, disque sur `ceph-vm`, VNet `vinv99` (DHCP), pool `prod`.
- Nos standards : contrôleur `virtio-scsi-single`, carte `virtio`, CPU `x86-64-v2-AES` (ou `host` si justifié), agent QEMU actif et répondant, console série, cloud-init pour l'utilisateur `admin` et ta clé SSH.
- Pas d'ESXi dans le lab : l'assistant d'import depuis ESXi est en « pour aller plus loin ».

**Travail demandé**
1. Génère l'OVA, puis, avant tout import, vérifie-la : liste du contenu, ordre des fichiers, somme du disque contre le manifeste, et lis le descripteur. Que déclare-t-il (CPU, mémoire, contrôleur, carte, micrologiciel, type de système) ?
2. Active le contenu « import » sur le stockage `local` (si ce n'est fait) et regarde l'OVA dans l'interface : que propose l'assistant d'import ? Ne lance pas l'import par l'assistant.
3. Importe en ligne de commande : extrais l'archive dans un dossier de travail, simule l'import (`--dryrun`), puis importe vers `ceph-vm` sous le VMID 150. Que récupère la commande du descripteur, et que laisse-t-elle de côté ?
4. Démarre la VM telle quelle et observe la console : démarre-t-elle ? Puis mets-la aux standards (contrôleur, carte réseau sur `vinv99`, CPU, console série, agent) et redémarre-la.
5. Reprends la main sans le mot de passe d'InfoGér : l'image a cloud-init actif. Ajoute un lecteur cloud-init avec l'utilisateur `admin` et ta clé publique, réseau en DHCP. Connecte-toi en SSH, installe l'agent QEMU, désinstalle ce qui ne sert plus (outils VMware s'ils sont présents), vérifie que l'agent répond depuis le nœud.
6. Place la VM dans le pool `prod`, et fais-en une première sauvegarde par `pbs-par2`.
7. Écris dans ton journal la liste de contrôle pour les vingt VMs suivantes (Linux et Windows) : intégrité, matériel, pilotes, réseau, identité (MAC, `machine-id`, clés SSH d'hôte), agent, sauvegarde, et ce qui diffère pour une VM Windows.

**Critères de réussite**
- [ ] `legacy-rdv01` (150) existe, disque sur `ceph-vm`, contrôleur `virtio-scsi-single`, carte `virtio` sur `vinv99`, CPU différent du type par défaut de l'OVA, console série.
- [ ] L'agent QEMU est activé dans la configuration et répond.
- [ ] Aucun disque SATA/IDE (hors lecteur cloud-init) ni carte `e1000`/`vmxnet3` ne reste ; la VM est dans le pool `prod`.
- [ ] Une sauvegarde de 150 existe sur `pbs-par2`.

**Vérification** : `lab/bin/check 09 23`

<details><summary>Indice 1</summary>

Une OVA est une archive `tar` ; le descripteur `.ovf` doit être le premier fichier. Le manifeste `.mf` contient des lignes `SHA256(fichier)= somme`. `qm help importovf --verbose` ; la section *Importing Virtual Machines* de `qm(1)` décrit les deux voies (CLI et assistant).
</details>

<details><summary>Indice 2</summary>

Un noyau Linux « cloud » n'embarque pas forcément le pilote du contrôleur SCSI LSI émulé : si la VM ne trouve pas son disque racine, c'est la première piste. `qm set 150 --scsihw …`, `--net0 virtio,bridge=…`, `--cpu …`, `--serial0 socket`, `--agent enabled=1`.
</details>

<details><summary>Indice 3</summary>

Un lecteur cloud-init se crée sur un stockage (`--ide2 <stockage>:cloudinit` ou `--scsi1 …`) ; `--ciuser`, `--sshkeys`, `--ipconfig0 ip=dhcp`. Cloud-init ne rejoue la configuration que si l'identifiant d'instance change : c'est le cas d'un nouveau lecteur Proxmox.
</details>

**Pour aller plus loin** (facultatif) : l'assistant d'import ESXi (stockage de type `esxi`, <https://pve.proxmox.com/wiki/Migrate_to_Proxmox_VE>) et les pilotes VirtIO pour Windows (<https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers>). Le workbook final F4 simule une migration VMware → Proxmox à plus grande échelle.
