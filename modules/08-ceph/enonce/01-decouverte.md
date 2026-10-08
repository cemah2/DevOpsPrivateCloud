# Module 08 — Palier 1 : Découverte

Avant d'écrire une ligne de spécification, il faut des machines qui conviennent : trois nœuds Rocky Linux 10 créés par le code, avec deux réseaux en *jumbo frames* et des disques que Ceph classera correctement. Ce palier les prépare, amorce le cluster `ceph-par1` avec cephadm, déploie les OSD par spécification, crée un premier pool répliqué et une première image RBD consommée par un vrai client, puis t'apprend à lire l'état d'un cluster sans paniquer. Un détour par ZFS rappelle ce qu'un stockage local sait faire, pour mieux mesurer ce que Ceph change. Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : module 07 terminé (`lab/bin/check 07 46` vert : bordure redondante, MTU 9000 sur les VLAN 30 et 31) ; modules 03 à 06 (image dorée Rocky `current`, rôles et Molecule, OpenTofu et NetBox, PKI). Lis [`00-introduction.md`](00-introduction.md), en particulier le chemin imposé, les faits techniques et les règles du module.

---

### M08-E01 — Test de positionnement : stockage  `Q` `★★`

> **Ticket PLAT-901** — *De : Karim Benali*
> Le rituel : une heure, par écrit, sans moteur de recherche ni IA, sans rien exécuter. Disques, RAID, systèmes de fichiers, réseau de stockage, cohérence, répartition : tout ce que Ceph suppose acquis et que l'on croit savoir parce qu'on a déjà monté un NAS. Réponds même là où tu hésites : le raisonnement compte.

**Objectifs pédagogiques**
- Évaluer tes acquis sur le stockage local et réseau avant d'aborder un système distribué.
- Repérer les notions à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Disques et performances*

1. Définis **IOPS**, **débit** et **latence**. Pour chacune, donne un ordre de grandeur pour un disque dur 7 200 tr/min, un SSD SATA et un SSD NVMe. Laquelle des trois une base de données transactionnelle remarque-t-elle en premier ?

2. *(QCM)* Une application écrit 4 Kio puis appelle `fsync()`. Que garantit le retour de `fsync()` ?
   - A. Que les données sont dans le cache de page du noyau
   - B. Que les données (et les métadonnées nécessaires pour les relire) sont sur un support persistant, cache d'écriture du disque compris si le disque respecte les ordres de vidage
   - C. Que les données sont répliquées sur un second disque
   - D. Rien : `fsync()` n'est qu'un indice pour le noyau

3. Qu'est-ce que l'**amplification d'écriture** ? Donne deux sources différentes d'amplification entre une écriture applicative et les cellules d'un SSD.

4. À quoi sert la commande **TRIM** (ou `discard`) ? Que se passe-t-il, côté hyperviseur, pour un disque virtuel « mince » (*thin provisioning*) quand l'invité ne l'envoie jamais ?

*Redondance locale*

5. Compare RAID 1, RAID 5, RAID 6 et RAID 10 : capacité utile sur 6 disques de 4 To, pannes tolérées, pénalité en écriture. Pourquoi le RAID 5 est-il déconseillé avec de gros disques durs ?

6. *(QCM)* Le « trou d'écriture » (*write hole*) du RAID 5 logiciel se produit quand :
   - A. Un disque est plus lent que les autres
   - B. Une coupure de courant survient entre l'écriture des données et celle de la parité d'une même bande
   - C. Le contrôleur n'a pas de batterie
   - D. On mélange des disques de tailles différentes

7. Qu'est-ce que la **corruption silencieuse** (*bit rot*) ? Comment un système de fichiers à sommes de contrôle (ZFS, Btrfs) la détecte-t-il et, avec de la redondance, la répare-t-il ? Qu'est-ce qu'un *scrub* ?

8. Un instantané (*snapshot*) n'est pas une sauvegarde. Donne trois raisons précises.

*Stockage en réseau*

9. Distingue stockage **bloc**, **fichier** et **objet** : ce que le client voit, qui gère les métadonnées, un protocole et un usage typiques pour chacun.

10. *(QCM)* Deux serveurs montent le même LUN iSCSI et y créent chacun un système de fichiers XFS monté en écriture. Que se passe-t-il ?
    - A. Rien de grave : XFS gère les accès concurrents
    - B. Les deux noyaux écrivent sans se coordonner : le système de fichiers est corrompu
    - C. La cible iSCSI refuse la seconde connexion
    - D. Le second montage est automatiquement en lecture seule

11. Pourquoi sépare-t-on souvent le trafic de **réplication** du trafic des clients sur un système de stockage distribué ? Pour une écriture cliente de 1 Gio dans un système à 3 copies, combien de données circulent sur chaque réseau ?

12. Qu'apportent les **trames jumbo** (MTU 9000) à un réseau de stockage, et quel est le risque principal quand un seul équipement du chemin reste à 1500 ?

*Systèmes distribués*

13. Qu'est-ce qu'un **quorum** ? Pourquoi trois moniteurs plutôt que deux, et pourquoi pas quatre ?

14. *(QCM)* Un cluster de stockage à 3 copies perd la liaison entre deux salles : la salle A garde 2 nœuds sur 3, la salle B en garde 1. Que devrait faire un système **cohérent** dans la salle B ?
    - A. Continuer à accepter les écritures, puis fusionner au retour du lien
    - B. Refuser les écritures (et souvent les lectures) tant qu'il n'a pas la majorité
    - C. Élire un nouveau chef local
    - D. Basculer en lecture seule mais accepter les écritures de l'administrateur

15. Énonce le théorème **CAP** en une phrase. Où placerais-tu un système de stockage bloc qui sert les disques de VMs ? Pourquoi ?

16. Un système qui place les données par **calcul** (fonction de hachage + carte de la topologie) plutôt que par **table de correspondance** centrale : avantages, inconvénient principal.

17. Qu'est-ce qu'un **domaine de panne** ? Donne quatre niveaux possibles, du plus petit au plus grand, et dis lequel tu choisirais pour trois serveurs dans une même baie.

18. Compare **réplication** (3 copies) et **codes d'effacement** (4 + 2) : surcoût en capacité, pannes tolérées, coût en écriture et en reconstruction.

*Exploitation*

19. Un disque d'un système redondant tombe en panne à 3 h du matin. Pourquoi est-il souvent préférable que le système **attende** quelques minutes avant de reconstruire les données ailleurs ? Et pourquoi ne faut-il pas qu'il attende trop longtemps ?

20. Cite trois indicateurs que tu superviserais en priorité sur n'importe quel système de stockage, avec un seuil d'alerte pour chacun.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour chaque mécanisme de redondance, pose-toi trois questions : combien de copies (ou de morceaux) existent, qu'est-ce qui doit être écrit **ensemble** pour que ce soit cohérent, et qui décide quand un morceau manque.
</details>

<details><summary>Indice 2</summary>

Pour les questions de systèmes distribués, raisonne sur le pire cas : deux moitiés qui ne se voient plus et qui croient chacune être seules. Que faudrait-il pour qu'elles n'écrivent pas des choses contradictoires ?
</details>

**Pour aller plus loin** (facultatif) : refais ce test à la fin du module (M08-E46), sans relire le corrigé, et compare.

---

### M08-E02 — Préparer les nœuds Ceph  `LAB` `★★`

> **Ticket PLAT-902** — *De : Karim Benali* — *Copie : Claire Morel*
> Trois nœuds pour `ceph-par1`. Tentacle ne prend pas Debian 13 comme hôte : ce sera Rocky Linux 10, notre image dorée. Notre module `vm-debian` ne sait faire qu'une carte réseau et pas de disque de données ; il nous faut deux réseaux en 9000 et trois disques d'OSD par nœud. Pas de copier-coller : un module pour les nœuds de cluster, qui servira encore pour OpenStack. Côté système, prépare ce que cephadm attend, mais pas plus : pas de démon Ceph installé à la main, pas de root en SSH, pas de SELinux désactivé « pour que ça marche ». Et je veux la preuve que le réseau passe des trames de 9000 octets entre les nœuds **avant** qu'on y mette des données.

**Objectifs pédagogiques**
- Concevoir un module OpenTofu générique (plusieurs cartes et MTU, disques de données, famille d'image) à côté d'un module existant, sans le casser.
- Présenter à une VM des disques que Ceph classe correctement (non rotatif, rotatif) et comprendre d'où vient l'information.
- Préparer un hôte pour cephadm (moteur de conteneurs, LVM, temps, compte de l'orchestrateur, dépôt de version épinglé et vérifié) sur la famille Red Hat, avec SELinux actif.
- Étendre un rôle partagé de collection à une seconde famille d'OS (version mineure).

**Prérequis** : M07-E46 (MTU 9000 sur les VLAN 30 et 31) ; M06-E13, M06-E14 (adresses NetBox, noms DNS par OpenTofu) ; M06-E12 (inventaire NetBox) ; M06-E03 (rôle `ca_lab`) ; M03-E25 (image dorée Rocky) ; M04-E24 (Molecule).
**Durée indicative** : 5 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VMs | `ceph01-03`, VMID 2081-2083, pool `lab`, étiquettes `env-m08` et `role-ceph` ; 2 vCPU (CPU `x86-64-v3` au minimum), 6144 Mo ; démarrage manuel (pas d'`onboot`) |
| Disques | `scsi0` système 20 Gio sur `local-nvme` ; `scsi1`, `scsi2` : 64 Gio sur `ssd-lab`, présentés SSD ; `scsi3` : 64 Gio sur `hdd-bulk`, présenté rotatif ; contrôleur `virtio-scsi-single` ; disques de données **exclus des sauvegardes PBS** ; numéro de série lisible (`ceph01-ssd1`…) |
| Réseau | `net0` (ens18) sur `vstopub`, 10.10.30.5N/24, passerelle 10.10.30.1 ; `net1` (ens19) sur `vstoclu`, 10.10.31.5N/24, sans passerelle ; MTU 9000 sur les deux ; DNS 10.10.20.10 et 10.10.20.16 ; noms `ceph0N.par1.medisphere.internal` (A et PTR) sur l'adresse publique seulement |
| Code | module `vm-noeud` dans `plateforme/tofu-modules` (nouvelle version mineure du dépôt) ; état `envs/ceph` dans `plateforme/infra` (clé `envs/ceph/terraform.tfstate`) |
| NetBox | étiquettes `env-m08`, `role-ceph`, `role-ceph-client` à ajouter au modèle (script de M06-E05) ; interfaces `ens18`, `ens19` |
| Ansible | source d'inventaire `inventories/lab/netbox-ceph.yml` (étiquette `env-m08`) ; groupes `env_m08`, `role_ceph` ; faits partagés dans `group_vars/env_m08/ceph.yml` (`ceph_noeuds` : adresses publique et cluster de chaque nœud) ; rôle `ceph_noeud` ; playbook `playbooks/ceph-noeuds.yml` ; scénario Molecule `ceph_noeud`, instance 2049, famille `rocky10` |
| Paquets Ceph | `cephadm` et `ceph-common` en **20.2.3**, du dépôt `https://download.ceph.com/rpm-20.2.3/el10/` (sous-dossiers `noarch` et `x86_64`), paquets signés par la clé `https://download.ceph.com/keys/release.asc` (empreinte `08B7 3419 AC32 B4E9 66C1 A330 E84A C2C0 460F 3994`) ; `ceph-common` dépend de paquets d'EPEL et de CRB |
| Orchestrateur | le paquet `cephadm` crée un compte système `cephadm` (dossier `/var/lib/cephadm`) : c'est lui que l'orchestrateur utilisera en SSH (E03), avec sudo sans mot de passe |
| Collection | `medisphere.socle` 1.1.x : `ca_lab` ne connaît que Debian |

**Travail demandé**

*A. Avant d'écrire*

1. Lis la page « Requirements » de cephadm et la liste des plateformes prises en charge par Tentacle. Note dans ton journal ce que cephadm attend d'un hôte, et pourquoi Debian 13 ne convient pas ici.
2. Vérifie que ton image dorée Rocky `current` contient la **racine MédiSphère** et plus la CA provisoire : M06-E03 a peut-être seulement reconstruit l'image Debian. Si ce n'est pas le cas, reconstruis et publie une image `rocky10` par le pipeline de `plateforme/images` avant de continuer.
3. Ajoute au modèle NetBox (script de données de M06-E05) les étiquettes `env-m08`, `role-ceph`, `role-ceph-client`.

*B. Le module et les VMs*

4. Écris le module `vm-noeud` à côté de `vm-debian` (pas dedans : explique pourquoi dans son README). Exigences :
   - famille d'image `debian13` ou `rocky10`, type de CPU déduit de la famille, imposable ;
   - de une à quatre cartes, chacune avec son VNet, son préfixe NetBox, son adresse **imposée**, son MTU (1500 ou 9000) ; une seule carte porte la passerelle ; seule la première porte le nom DNS ;
   - disques de données en nombre variable, chacun avec son stockage, sa présentation SSD ou rotative, son numéro de série, et exclu par défaut des sauvegardes ;
   - VM, interfaces et adresses enregistrées dans NetBox **avant** la VM, comme `vm-debian` v2 ;
   - erreurs de saisie refusées au plan (validations).
   Publie-le (MR, nouvelle version mineure du dépôt).
5. Écris l'environnement `envs/ceph` (versions, fournisseurs, *backend*, variables) et les trois nœuds, plus leurs noms DNS. Lis le plan : combien de ressources, dans quel ordre ? `apply` par le pipeline.
6. Sur `pve01`, lis la configuration d'une VM (`qm config 2081`) : retrouve le MTU des cartes, la présentation des disques. Dans `ceph01`, vérifie `lsblk -d -o NAME,SIZE,ROTA,SERIAL` : les deux disques de `ssd-lab` doivent être non rotatifs, celui de `hdd-bulk` rotatif. D'où le noyau tient-il cette information, puisque les trois disques sont des fichiers ou des volumes logiques sur `pve01` ?

*C. Ansible*

7. Fais évoluer `ca_lab` pour la famille Red Hat (dossier d'ancres et commande de reconstruction propres à la famille, vérification dans le magasin consolidé de la famille), sans changer son comportement sur Debian. Version de la collection, CHANGELOG.
8. Ajoute la source d'inventaire de l'environnement Ceph. Pourquoi ne suffit-il pas d'ajouter une ligne `- tag: env-m08` aux filtres de `inventories/lab/netbox.yml` ? Vérifie que le garde-fou de `site.yml` (neuf hôtes dans `socle`) n'est pas affecté.
9. Écris le rôle `ceph_noeud` et son scénario Molecule. Exigences :
    - refus de tout autre système que Rocky Linux 10 ; nom d'hôte égal au nom d'inventaire ; SELinux reste en *enforcing* ;
    - dépôt Ceph **de la version** (pas « tentacle » : pourquoi ?), clé importée **seulement** si son empreinte est la bonne, `gpgcheck` actif ;
    - `cephadm` et `ceph-common` en 20.2.3 exactement, vérifiés après installation ; Podman, LVM2, chrony, firewalld actifs ;
    - compte `cephadm` : sudo sans mot de passe (fichier validé avant mise en place), `.ssh` avec le contexte SELinux que `sshd` accepte, clé publique du cluster déposée **quand elle sera connue** (variable vide pour l'instant) ;
    - MTU fixé dans le profil NetworkManager de chaque carte et vérifié ; trames de 9000 octets **sans fragmentation** vers les autres nœuds, sur les deux réseaux ;
    - pour finir, `cephadm check-host`.
    Le scénario Molecule tourne sur une instance Rocky à une carte : adapte les attentes réseau par des variables, pas par des conditions dans le rôle.
10. Écris `playbooks/ceph-noeuds.yml` : rôles communs (`ssh_durci`, `ca_lab`, `ssh_ca_hote`, `ssh_ca_utilisateur`) puis `ceph_noeud`, **un nœud à la fois**. Pourquoi pas le rôle `base` ? Applique-le par le pipeline ; second passage : `changed=0`.
11. Mets à jour l'inventaire de la plateforme et le registre des secrets (rien de nouveau : dis pourquoi), et la matrice des flux (rien sur les passerelles : dis pourquoi).

**Critères de réussite**
- [ ] Les VMs 2081-2083 sont créées par OpenTofu (`envs/ceph`, module `vm-noeud`), conformes au contexte technique : CPU, mémoire, deux cartes en MTU 9000 sur `vstopub` et `vstoclu`, trois disques de données (deux présentés SSD sur `ssd-lab`, un rotatif sur `hdd-bulk`), hors sauvegarde.
- [ ] `ceph01-03` sont résolus en A et PTR sur leur adresse publique et décrits dans NetBox (IP primaire publique).
- [ ] Sur chaque nœud : Rocky Linux 10, SELinux *enforcing*, firewalld actif, temps synchronisé, `cephadm` et `ceph-common` en 20.2.3 du dépôt épinglé et vérifié, compte `cephadm` prêt, root interdit en SSH, racine MédiSphère de confiance.
- [ ] ens18 et ens19 sont en MTU 9000 ; des paquets de 9000 octets non fragmentés passent entre les nœuds sur les deux réseaux ; le réseau cluster n'a pas de passerelle.
- [ ] `vm-noeud`, `envs/ceph`, le rôle `ceph_noeud`, son scénario Molecule et la source d'inventaire sont sur `main` ; la collection `medisphere.socle` est en 1.2.x ; un second passage du playbook donne `changed=0`.

**Vérification** : `lab/bin/check 08 02`

<details><summary>Indice 1</summary>

Dans le fournisseur `bpg/proxmox`, une carte réseau a un attribut `mtu` et un disque les attributs `ssd`, `backup` et `serial` ; `initialization` accepte un bloc `ip_config` **par carte**, dans l'ordre des cartes. Un bloc `dynamic` sur la liste des cartes sert deux fois. Côté invité, l'attribut que lit Ceph est `/sys/block/sdX/queue/rotational` : regarde ce que Proxmox passe à QEMU quand `ssd=1`.
</details>

<details><summary>Indice 2</summary>

Les filtres d'étiquettes de l'API de NetBox se combinent en **ET**. Pour le dépôt : le module `ansible.builtin.rpm_key` a une option qui vérifie l'empreinte ; `ansible.builtin.yum_repository` écrit un fichier `.repo`. Pour sudo : l'option `validate` du module `copy`. Pour SELinux : `community.general.sefcontext` puis `restorecon`. Pour EPEL et CRB sur Rocky : `community.general.dnf_config_manager` et le paquet `epel-release`.
</details>

<details><summary>Indice 3</summary>

`ping -M do -s 8972` : `-M do` interdit la fragmentation, 8972 + 28 octets d'en-têtes (IP 20, ICMP 8) = 9000. Le MTU d'une carte NetworkManager se lit et se règle par la propriété `802-3-ethernet.mtu` du profil (`nmcli -g … connection show <profil>`), et s'applique à chaud par `nmcli device reapply`. Le rôle `base` installe `unattended-upgrades` et parle `apt` : regarde ce que l'image dorée Rocky contient déjà.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Hardware recommendations » de Ceph et compare avec nos nœuds (2 vCPU, 6 Go, 3 OSD de 64 Gio) : qu'est-ce qui serait refusé en production, et qu'est-ce que le lab nous empêchera d'observer ?

---

### M08-E03 — Amorcer le cluster avec cephadm  `LAB` `★★`

> **Ticket PLAT-903** — *De : Claire Morel*
> Les nœuds sont prêts, on crée `ceph-par1`. L'amorçage ne se fait qu'une fois dans la vie d'un cluster : je veux qu'il soit écrit, relu et rejouable sur un lab vierge. Ensuite, plus aucun geste « à la main » sur les nœuds : ce que Ceph fait tourner est décrit dans un nouveau projet `plateforme/ceph`. Image épinglée : je ne veux pas découvrir dans six mois qu'un nœud a tiré une autre version que les deux autres. Et pas de pile Prometheus/Grafana embarquée pour l'instant, on n'a pas la mémoire.

**Objectifs pédagogiques**
- Amorcer un cluster avec `cephadm bootstrap` et comprendre ce qu'il crée (démons, fichiers, clés, configuration).
- Choisir les options d'amorçage qui comptent : réseau public et réseau cluster, image épinglée, compte SSH de l'orchestrateur, configuration initiale, services non voulus.
- Ajouter des hôtes et placer les moniteurs et les gestionnaires par des **spécifications** déclaratives.
- Situer les secrets créés (trousseau `client.admin`, clé SSH de l'orchestrateur, mot de passe du tableau de bord).

**Prérequis** : M08-E02.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Projet | `plateforme/ceph` à créer (configuré comme les autres projets `plateforme/*`, script `gitlab-proteger-projet.sh` de M01-E11), clone `~/src/ceph` ; dossiers `bootstrap/` et `specs/` ; `.yamllint` |
| Amorçage | sur `ceph01`, une seule fois ; image `quay.io/ceph/ceph:v20.2.3` ; moniteur sur 10.10.30.51 ; réseau cluster 10.10.31.0/24 ; compte SSH de l'orchestrateur `cephadm` ; sans la pile de supervision ; configuration initiale (fichier `bootstrap/initial-ceph.conf`) : réplication 3/2, suppression des pools verrouillée, `osd_memory_target` 1 Gio fixe |
| Hôtes | `ceph01-03`, adresses publiques 10.10.30.51-53, étiquettes `_admin`, `mon`, `mgr`, `osd` |
| Services | 3 moniteurs (étiquette `mon`), 2 gestionnaires (étiquette `mgr`) ; spécifications `specs/hosts.yaml`, `specs/mon.yaml`, `specs/mgr.yaml` |
| Inventaire | `ceph_fsid` dans `group_vars/env_m08/ceph.yml` ; clé publique de l'orchestrateur dans `group_vars/role_ceph/ceph_noeud.yml` (`ceph_noeud_cle_orchestrateur`) |
| Tableau de bord | compte `admin` ; nouveau mot de passe dans Vault `lab` (`vault_ceph_dashboard_admin_mdp`, `group_vars/env_m08/vault-lab.yml`) et dans `~/.config/workbook/ceph-dashboard.pass` (600) sur `adm01` |

**Travail demandé**

*A. Préparer*

1. Lis l'aide complète de l'amorçage : `cephadm bootstrap --help` sur `ceph01`, et la page « Deploying a New Ceph Cluster ». Pour chaque option du contexte technique, trouve l'option correspondante. Puis réponds dans ton journal : quelle image cephadm prendrait-il si tu ne lui en donnais aucune ? Que fait-il de `osd_memory_target_autotune` si ta configuration initiale n'en dit rien ? Qu'est-ce qui, parmi les options possibles, ferait passer un secret en argument de commande ?
2. Crée `plateforme/ceph`. Écris `bootstrap/initial-ceph.conf` (chaque option commentée) et un script `bootstrap/amorcer.sh` qui vérifie les préalables (bon hôte, bonne version de `cephadm`, adresses présentes, compte de l'orchestrateur prêt, **aucun cluster existant**) avant de lancer l'amorçage. MR relue, fusion.
   > ⚠️ **Attention** : un second amorçage sur un hôte qui porte déjà un cluster ne « répare » rien : il crée un **autre** cluster (autre fsid). Le script doit refuser.

*B. Amorcer*

3. Fais un instantané des trois nœuds (`ms-snapshot --prefix avant-amorcage 2081 2082 2083`) : sur un lab, c'est le moyen le plus rapide de recommencer.
4. Copie le dépôt sur `ceph01` et lance l'amorçage. Lis toute la sortie : fsid, URL et mot de passe du tableau de bord, commandes conseillées.
5. Inventaire de ce qui a été créé sur `ceph01` : `/etc/ceph/` (fichiers et droits), `cephadm ls`, unités systemd `ceph-<FSID>@…`, conteneurs (`podman ps`), règles firewalld ajoutées. Note où sont la clé SSH **privée** de l'orchestrateur et la clé de `client.admin`, et qui peut les lire.
6. Observe : `ceph -s`, `ceph config dump`, `ceph config get mgr container_image`, `ceph orch ls`, `ceph orch ps`. Pourquoi la santé n'est-elle pas `HEALTH_OK` ? Que vaut l'image des démons, et pourquoi n'est-ce plus exactement ce que tu as passé à l'amorçage ?

*C. Les autres nœuds, par le code*

7. Range le fsid et la clé publique de l'orchestrateur (`ceph cephadm get-pub-key`) dans l'inventaire, puis rejoue `ceph-noeuds.yml` : la clé arrive dans `~cephadm/.ssh/authorized_keys` de chaque nœud. Vérifie qu'elle n'est **pas** dans celui de root.
8. Écris `specs/mon.yaml`, `specs/mgr.yaml` et `specs/hosts.yaml`. Applique-les depuis `ceph01` (d'abord avec `--dry-run` quand c'est possible), dans un ordre que tu justifies. Suis le déploiement (`ceph -W cephadm`, `ceph orch ps`).
9. Vérifie : trois moniteurs en quorum (adresses v2 et v1), un gestionnaire actif et un en attente, trois hôtes avec leurs étiquettes, `ceph.conf` et `client.admin` copiés sur `ceph02` et `ceph03`. Compare `ceph orch ls --export` avec tes fichiers.
10. Bascule le gestionnaire actif (`ceph mgr fail`) et observe qui prend la main, en combien de temps, et ce que devient l'URL du tableau de bord (`ceph mgr services`).

*D. Le tableau de bord et les secrets*

11. Ouvre le tableau de bord avec le mot de passe affiché à l'amorçage, par un tunnel SSH à travers le bastion (`ssh -L 8443:<IP-DU-MGR-ACTIF>:8443 admin@adm01` depuis ton poste, puis `https://localhost:8443`). Le certificat est auto-signé : note-le comme écart (il sera remplacé par un certificat de notre PKI au palier 3), ne l'ajoute à aucun magasin de confiance.
12. Change le mot de passe de `admin` **sans le mettre dans la ligne de commande** ; range-le dans Vault `lab` et dans `~/.config/workbook/ceph-dashboard.pass`. Inscris au registre des secrets : trousseau `client.admin` (emplacements), clé SSH de l'orchestrateur, mot de passe du tableau de bord.
13. Supprime les instantanés d'avant l'amorçage une fois tout vérifié. Fais une MR pour les spécifications et l'inventaire.

**Critères de réussite**
- [ ] Le cluster répond depuis `ceph01` ; trois moniteurs en quorum sur 10.10.30.51-53 (msgr2 et msgr1), un gestionnaire actif et un en attente.
- [ ] `public_network` = 10.10.30.0/24, `cluster_network` = 10.10.31.0/24 ; `osd_memory_target` = 1 Gio et réglage automatique désactivé ; suppression des pools verrouillée.
- [ ] Tous les démons sont en 20.2.3 ; l'image configurée est épinglée (version ou empreinte), jamais une étiquette flottante ; aucune pile Prometheus/Grafana/Alertmanager/node-exporter.
- [ ] Les trois hôtes sont déclarés avec leur adresse publique et les étiquettes `_admin`, `mon`, `mgr`, `osd` ; les services `mon` et `mgr` sont placés par étiquette.
- [ ] La clé de l'orchestrateur est autorisée pour `cephadm` (et pas pour root) sur chaque nœud.
- [ ] `ceph_fsid` de l'inventaire correspond au cluster ; le mot de passe du tableau de bord a été changé et rangé (600) ; `bootstrap/` et `specs/` sont sur `main` de `plateforme/ceph`.

**Vérification** : `lab/bin/check 08 03`

<details><summary>Indice 1</summary>

`--image` est une option **globale** de cephadm : elle se place avant la sous-commande. Les options du réseau cluster, du compte SSH, de la configuration initiale et de la pile de supervision sont dans l'aide de `bootstrap`. Une option de la section `[osd]` d'un fichier passé par `--config` est versée dans la base de configuration des moniteurs.
</details>

<details><summary>Indice 2</summary>

Une spécification d'hôte a pour `service_type` la valeur `host`, et les champs `hostname`, `addr`, `labels` ; plusieurs documents YAML se séparent par `---` dans un même fichier. Les placements par étiquette s'écrivent `placement: {label: …}`, avec `count` si besoin. L'hôte d'amorçage est déjà dans le cluster : regarde ce que fait la spécification d'un hôte existant.
</details>

<details><summary>Indice 3</summary>

Les commandes `ceph` qui attendent un contenu (mot de passe, clé, fichier de spécification) le lisent par `-i <fichier>`, et `-i -` lit l'entrée standard : depuis `adm01`, une redirection depuis ton fichier en 600 évite que le mot de passe apparaisse dans `ps`, dans l'historique ou sur le disque de `ceph01`. Cherche la sous-commande `ac-user-set-password` du module `dashboard`.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Deployment with CA signed SSH keys » de cephadm : l'orchestrateur peut se connecter avec un **certificat** SSH signé par notre CA (M06-E19) plutôt qu'avec une clé brute, et la configuration SSH par défaut de cephadm (`ceph cephadm get-ssh-config`) ne vérifie pas les clés d'hôte. Que faudrait-il pour que l'orchestrateur vérifie l'identité des nœuds ?

---

### M08-E04 — Les OSD : spécifications et classes de disques  `LAB` `★★`

> **Ticket PLAT-904** — *De : Karim Benali*
> Neuf disques, neuf OSD. Je ne veux pas voir `--all-available-devices` : le jour où quelqu'un ajoute un disque à un nœud pour autre chose, il deviendrait un OSD dans la minute. Une spécification qui dit **quels** disques, par leurs caractéristiques, pas par leur nom `/dev/sdX` qui peut changer au redémarrage. Les classes `ssd` et `hdd` doivent être justes : on s'en servira pour placer les pools au palier 2. Et vérifie qu'un OSD n'a pas plus de mémoire que ce qu'on a décidé : nos nœuds n'ont que 6 Go.

**Objectifs pédagogiques**
- Inventorier les périphériques vus par l'orchestrateur et comprendre ce qui rend un disque « disponible ».
- Écrire une spécification d'OSD par filtres (rotation, taille), la prévisualiser, l'appliquer.
- Vérifier la classe CRUSH de chaque OSD et son origine.
- Comprendre la hiérarchie de la configuration de Ceph (global, classe de démon, démon, masque d'hôte) sur un exemple réel : la cible mémoire des OSD.

**Prérequis** : M08-E03.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Disques candidats : `scsi1`, `scsi2` (64 Gio, `ssd-lab`, non rotatifs), `scsi3` (64 Gio, `hdd-bulk`, rotatif) sur chaque nœud ; le disque système (20 Gio) ne doit jamais être touché.
- Spécification : `specs/osd.yaml` de `plateforme/ceph`, deux services : `osd.ssd` (disques non rotatifs) et `osd.hdd` (disques rotatifs), placés par l'étiquette `osd`, classe CRUSH écrite explicitement, filtre de taille qui exclurait un petit disque ajouté plus tard.
- Mémoire : `osd_memory_target` = 1 Gio, réglage automatique désactivé (configuration initiale de E03).

**Travail demandé**
1. `ceph orch device ls --wide` : quels disques sont « disponibles », lesquels ne le sont pas, et pourquoi (lis la colonne des raisons) ? Sur `ceph01`, compare avec `lsblk -d -o NAME,SIZE,ROTA,SERIAL` et avec `cephadm ceph-volume inventory`. Retrouve les numéros de série posés par OpenTofu.
2. Écris `specs/osd.yaml`. Prévisualise (`--dry-run`) : combien d'OSD, sur quels hôtes, quels périphériques, pour chaque service ? Si la prévisualisation ne montre rien, attends quelques minutes et relance : pourquoi ?
3. Applique. Suis la création (`ceph -W cephadm`, `ceph orch ps --daemon-type osd`, `ceph osd tree`). Combien de temps pour neuf OSD ?
4. Vérifie chaque classe : `ceph osd tree`, `ceph osd crush class ls`, et pour un OSD de chaque classe `ceph osd metadata <ID>` (champs de rotation, périphérique). La classe affichée vient-elle de la spécification ou de la détection automatique ? Comment le saurais-tu si les deux étaient contradictoires ?
5. Sur un nœud, regarde ce que `ceph-volume` a construit sur un disque d'OSD : `lsblk`, `sudo lvs -o lv_name,vg_name,lv_tags`. Où BlueStore range-t-il ses données, et pourquoi n'y a-t-il pas de système de fichiers ?
6. Mémoire : lis la valeur effective de `osd_memory_target` pour `osd.0` et la colonne `MEM LIMIT` de `ceph orch ps`. Puis, à titre d'essai, active le réglage automatique pour **un** OSD (`ceph config set osd.0 osd_memory_target_autotune true`), attends quelques minutes, regarde `ceph config dump | grep osd_memory_target` : que s'est-il passé, et pourquoi ce réglage écrasait-il notre valeur ? Remets la configuration dans l'état décidé et vérifie qu'aucune valeur par hôte ne subsiste.
7. Lis `ceph osd df tree` et `ceph df` : capacité brute, capacité par classe, poids CRUSH de chaque OSD (d'où vient la valeur ?). Pourquoi `ceph df` affiche-t-il une capacité disponible bien inférieure à 9 × 64 Gio ?
8. Publie `specs/osd.yaml` (MR). Vérifie que `ceph orch ls osd --export` correspond au fichier.

**Critères de réussite**
- [ ] Neuf OSD `up` et `in`, trois par hôte : deux de classe `ssd`, un de classe `hdd`, chacun sur un disque de données (jamais le disque système).
- [ ] La classe de chaque OSD correspond à la nature de son disque (rotatif ⇒ `hdd`, non rotatif ⇒ `ssd`).
- [ ] Les services `osd.ssd` et `osd.hdd` existent, placés par l'étiquette `osd`, filtrés par rotation ; aucun service `osd.all-available-devices`.
- [ ] `osd_memory_target` vaut 1 Gio pour les OSD, sans valeur par hôte qui l'emporterait.
- [ ] Le cluster est en `HEALTH_OK` ; `specs/osd.yaml` est sur `main`.

**Vérification** : `lab/bin/check 08 04`

<details><summary>Indice 1</summary>

L'orchestrateur rafraîchit l'inventaire des disques périodiquement : `ceph orch device ls --refresh` le force. Un disque n'est « disponible » que s'il n'a ni partition, ni table de partitions, ni signature LVM, ni système de fichiers, et qu'il est assez grand.
</details>

<details><summary>Indice 2</summary>

Dans une spécification d'OSD, les filtres vont sous `spec.data_devices` (`rotational`, `size` avec des bornes `MIN:MAX`) ; `crush_device_class` se place sous `spec`. Les filtres se combinent en ET. Les métadonnées d'un OSD contiennent `bluestore_bdev_rotational`.
</details>

<details><summary>Indice 3</summary>

La configuration de Ceph a des **masques** : une valeur peut viser `osd` (tous les OSD), `osd.3`, ou `osd/host:ceph02` (les OSD d'un hôte). La plus précise l'emporte. Le réglage automatique de cephadm écrit des valeurs par hôte : `ceph config rm <qui> <option>` retire une valeur. Le label d'hôte `_no_autotune_memory` existe aussi : lis sa description.
</details>

**Pour aller plus loin** (facultatif) : lis la section « Additional Options » des spécifications d'OSD (`encrypted`, `osds_per_device`, `db_devices`). Sur un vrai nœud avec des disques durs et un NVMe, comment écrirais-tu la spécification pour mettre la base RocksDB de chaque OSD rotatif sur le NVMe ? Qu'est-ce que la panne du NVMe emporterait alors ?

---

### M08-E05 — Pools répliqués et groupes de placement  `LAB` `★★`

> **Ticket PLAT-905** — *De : Karim Benali*
> Premier pool, `rbd-test`, pour les essais en bloc. Avant qu'on en crée des dizaines, je veux que tu saches ce qu'est un PG, d'où vient leur nombre, où va un objet et pourquoi, et ce que valent vraiment `size` et `min_size`. Écris un petit outil qui crée un pool conforme à nos règles et qu'on puisse relancer sans risque. Et entraîne-toi à supprimer un pool **proprement** : le jour où il le faudra en production, ce ne sera pas le moment de découvrir le verrou.

**Objectifs pédagogiques**
- Créer un pool répliqué, lui associer une application, régler `size` et `min_size`.
- Comprendre les PG : leur rôle, leur nombre (autoscaler, cible par OSD), leur placement par CRUSH.
- Suivre un objet de son nom à ses OSD.
- Observer ce que fait le cluster quand une règle ne peut pas être satisfaite.
- Supprimer un pool par la procédure prévue, et reposer le verrou.

**Prérequis** : M08-E04.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Pool `rbd-test` : répliqué, `size 3`, `min_size 2`, application `rbd`, règle CRUSH par défaut (`replicated_rule`, domaine de panne : l'hôte), autoscaler actif.
- Pool d'essai : `essai-pg`, créé puis **supprimé** pendant l'exercice.
- Objets d'essai écrits avec `rados` : noms commençant par `essai-`, supprimés en fin d'exercice.
- Outil : `outils/pool-repliquee.sh` dans `plateforme/ceph`, lancé en root sur un nœud `_admin`.

**Travail demandé**
1. Lis la page « Placement Groups » de la documentation : rôle des PG, autoscaler, `mon_target_pg_per_osd`, drapeau `bulk`. Calcule à la main le nombre de PG que viserait l'autoscaler pour un seul gros pool répliqué à 3 sur nos 9 OSD, puis compare à ce qu'il fera (`ceph osd pool autoscale-status`) une fois le pool créé.
2. Écris `outils/pool-repliquee.sh` : il crée le pool s'il manque, corrige `size`, `min_size`, le mode de l'autoscaler et l'application s'ils diffèrent, dit ce qu'il fait, a un mode simulation, **refuse** `min_size` inférieur à 2 et ne supprime jamais rien. Lance-le en simulation, puis pour de vrai pour `rbd-test`, puis une seconde fois.
3. Observe le pool : `ceph osd pool ls detail`, `ceph osd pool get rbd-test all`, `ceph pg ls-by-pool rbd-test` (états, OSD de chaque PG). Que représentent les colonnes `UP` et `ACTING` ? Quel OSD est le **primaire** d'un PG, et que fait-il de plus que les autres ?
4. Écris trois objets d'essai avec `rados -p rbd-test put essai-1 <fichier>`… Pour chacun, `ceph osd map rbd-test essai-1` : dans quel PG, sur quels OSD, sur quels hôtes ? Les trois copies sont-elles toujours sur trois hôtes différents ? Pourquoi ?
5. Crée le pool `essai-pg` avec l'outil, puis passe-le en `size 4`. Que dit `ceph -s` ? Lis l'état des PG (`ceph pg ls-by-pool essai-pg`, `ceph health detail`) et explique-le avec la règle CRUSH (`ceph osd crush rule dump replicated_rule`). Puis remets `size 3`.
6. Mets `min_size 1` sur `essai-pg` à la main (l'outil le refuse : c'est voulu). Réfléchis : quel scénario de panne ce réglage transforme-t-il en perte de données ? Remets 2.
7. Supprime `essai-pg` : essaie d'abord sans lever le verrou et lis le message ; puis lève le verrou, supprime (lis la syntaxe exigée), **repose le verrou**, vérifie.
   > ⚠️ **Attention** : relis deux fois le nom du pool avant de valider. Une suppression de pool est immédiate et définitive : aucun instantané de Ceph ne la rattrape.
8. Supprime les objets d'essai de `rbd-test` (`rados rm`). Publie l'outil (MR). Vérifie `HEALTH_OK`.

**Critères de réussite**
- [ ] `rbd-test` existe : `size 3`, `min_size 2`, application `rbd`, autoscaler actif, nombre de PG en puissance de 2, règle CRUSH répartissant les copies par hôte.
- [ ] Tous les PG sont `active+clean` ; aucune alerte de pool sans application ni de nombre de PG inadapté ; `HEALTH_OK`.
- [ ] `essai-pg` n'existe plus ; `mon_allow_pool_delete` est revenu à `false` ; aucun objet `essai-*` ne reste dans `rbd-test`.
- [ ] `outils/pool-repliquee.sh` est sur `main` de `plateforme/ceph`.

**Vérification** : `lab/bin/check 08 05`

<details><summary>Indice 1</summary>

L'autoscaler vise environ `mon_target_pg_per_osd` **copies** de PG par OSD, toutes copies comptées : nombre d'OSD × cible ÷ taille de réplication, arrondi à une puissance de 2, partagé entre les pools selon leur capacité attendue (ou leur drapeau `bulk`). Un petit pool sans données démarre bas et grossit avec ses données.
</details>

<details><summary>Indice 2</summary>

`ceph osd pool ls detail --format json` donne `size`, `min_size`, `pg_autoscale_mode`, `application_metadata` : de quoi comparer sans analyser du texte. Pour `rbd`, `rbd pool init` fait plus que déclarer l'application. La suppression d'un pool exige le nom deux fois et une option au nom explicite ; le verrou se lève et se repose par `ceph config set mon …`.
</details>

<details><summary>Indice 3</summary>

Une règle `chooseleaf … type host` demande des hôtes **distincts** : avec trois hôtes, une quatrième copie n'a nulle part où aller. Un PG qui a moins d'OSD que `size` est `undersized` ; il reste `active` tant qu'il en a au moins `min_size`.
</details>

**Pour aller plus loin** (facultatif) : `ceph pg dump pgs_brief` donne la liste de tous les PG et de leurs OSD : écris une ligne de `jq` qui compte combien de PG chaque OSD porte comme primaire, et compare à la répartition idéale. Lis ce que fait le module `balancer` du mgr (`ceph balancer status`).

---

### M08-E06 — RBD : images, snapshots et clones  `LAB` `★★`

> **Ticket DEV-906** — *De : Julien Petit*
> On nous dit que les disques des VMs et les volumes de Kubernetes seront « des images RBD ». Avant d'y croire, je veux voir un disque Ceph monté sur une machine ordinaire, le remplir, revenir en arrière par un instantané, en faire une copie instantanée pour un environnement de test, et que tout ça survive à un redémarrage. Et surtout : que cette machine n'ait **pas** les clés de tout le cluster, seulement celles de son pool.

**Objectifs pédagogiques**
- Créer un client Ceph minimal : `ceph.conf` réduit aux moniteurs, utilisateur cephx limité à un pool par un **profil**.
- Créer, mapper (krbd), formater, monter une image RBD ; la rendre persistante au démarrage.
- Utiliser les instantanés (création, retour arrière), les clones (protection, copie à la demande, aplatissement).
- Lire l'occupation réelle d'une image (allocation à la demande).

**Prérequis** : M08-E05 ; M08-E02 (module `vm-noeud`).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VM | `cephcli01`, VMID 2085, Debian 13, pool `lab`, étiquettes `env-m08`, `role-ceph-client` ; 2 vCPU, 2 Go, 20 Gio ; une carte sur `vstopub`, 10.10.30.20/24, passerelle 10.10.30.1, MTU 9000 ; `envs/ceph/cephcli01.tf`, module `vm-noeud` (famille `debian13`) |
| Client cephx | `client.rbd-test`, profil RBD sur le seul pool `rbd-test` ; clé dans Vault `lab` (`vault_ceph_cle_rbd_test`, `group_vars/role_ceph_client/vault-lab.yml`) |
| Rôle | `ceph_client` : `ceph-common` (Debian 13 : 18.2), `/etc/ceph/ceph.conf` minimal (fsid, moniteurs : `ceph_moniteurs` dans `group_vars/env_m08/ceph.yml`), trousseaux en 600, `/etc/ceph/rbdmap`, montages ; playbook `playbooks/ceph-clients.yml` ; scénario Molecule `ceph_client`, instance 2048 |
| Images | `rbd-test/disque01` (10 Gio, XFS, monté sur `/mnt/disque01`, persistant) ; instantané `disque01@avant-maj` (protégé) ; clone `rbd-test/disque01-clone` (aplati en fin d'exercice) |

**Travail demandé**

*A. Le client*

1. Déclare `cephcli01` dans `envs/ceph` et son nom DNS ; `apply` par le pipeline.
2. Sur `ceph01`, crée l'utilisateur `client.rbd-test` avec les profils RBD limités au pool (`ceph auth get-or-create …`). Lis ses capacités (`ceph auth get`). Que permet exactement `profile rbd` côté moniteur, et côté OSD avec `pool=rbd-test` ? Range la clé dans Vault `lab` sans qu'elle passe par un fichier en clair hors de `ceph01` (ou alors supprimé aussitôt).
3. Sur `ceph01`, lis ce que produirait un client minimal : `ceph config generate-minimal-conf`. Écris le rôle `ceph_client` (et son scénario Molecule) : paquets, `ceph.conf` minimal produit depuis l'inventaire, un trousseau par client (jamais `client.admin` : le rôle le refuse), images à mapper au démarrage et leurs montages. Applique `ceph-clients.yml`.
4. Depuis `cephcli01`, vérifie que le client voit le cluster **avec ses seuls droits** : `ceph --id rbd-test -s` (que répond-il ?), `rbd --id rbd-test ls rbd-test`, puis deux commandes hors de ses droits : lire un autre pool (`rados --id rbd-test -p .mgr ls`) et créer un pool : note les messages.

*B. Une image, un système de fichiers*

5. Crée `rbd-test/disque01` (10 Gio) **depuis `cephcli01`**. `rbd info` : taille des objets, fonctionnalités activées. `rbd du` : combien d'espace occupé ?
6. Mappe-la (`rbd device map … --id rbd-test`), formate-la en XFS, monte-la sur `/mnt/disque01`. Écris-y quelques centaines de Mio de données (garde une somme de contrôle). `rbd du` à nouveau, `ceph df` sur `ceph01` : qu'est-ce qui a bougé, et d'un facteur combien ?
7. Rends le montage persistant par le rôle (`rbdmap` et `fstab`), redémarre `cephcli01`, vérifie que `/mnt/disque01` est revenu avec ses données. Pourquoi l'entrée `fstab` doit-elle porter `noauto` ?

*C. Instantanés et clones*

8. Crée l'instantané `disque01@avant-maj`. Modifie les données (supprime un dossier, écris un fichier). Reviens à l'instantané (`rbd snap rollback`) : que faut-il faire **avant** côté client, et pourquoi ? Vérifie la somme de contrôle. Remonte.
9. Protège l'instantané, clone-le en `rbd-test/disque01-clone`. `rbd info` du clone (parent), `rbd children`, `rbd du` des deux : combien occupe le clone ? Mappe le clone, monte-le ailleurs (`/mnt/clone`) : XFS refuse-t-il ? Pourquoi, et comment monter quand même ce **double** du système de fichiers ? Écris dans le clone, démonte, démappe.
10. Aplatis le clone (`rbd flatten`). Que devient son lien avec le parent, et son occupation ? Pourquoi aplatit-on un clone destiné à vivre longtemps ? Laisse l'instantané `avant-maj` protégé (il servira en E25).
11. Publie le rôle, la VM et la clé chiffrée (MR). Inscris `client.rbd-test` au registre des secrets.

**Critères de réussite**
- [ ] `cephcli01` (2085) est créée par OpenTofu, conforme au contexte technique (une seule carte, `vstopub`, MTU 9000), résolue par le DNS.
- [ ] `client.rbd-test` a exactement `mon 'profile rbd'` et `osd 'profile rbd pool=rbd-test'` ; son trousseau est en 600 sur `cephcli01`, qui n'a **aucun** trousseau `client.admin` ; le `ceph.conf` du client désigne le bon cluster.
- [ ] `rbd-test/disque01` fait 10 Gio, porte l'instantané protégé `avant-maj` ; `rbd-test/disque01-clone` existe et n'a plus de parent.
- [ ] `/mnt/disque01` est monté en XFS depuis `rbd-test/disque01`, et revient seul après un redémarrage (rbdmap actif, entrée `fstab` en `noauto`).
- [ ] Le rôle `ceph_client`, `cephcli01.tf` et la clé chiffrée sous l'identité `lab` sont sur `main`.

**Vérification** : `lab/bin/check 08 06`

<details><summary>Indice 1</summary>

`ceph auth get-or-create client.X mon '…' osd '…'` crée l'utilisateur et affiche son trousseau ; `ceph auth get-key client.X` n'affiche que la clé. Pour la passer dans un fichier Vault sans copie en clair sur `adm01`, `ansible-vault encrypt` sait lire l'entrée standard (nom de fichier `-`) et écrire le fichier chiffré ailleurs (`--output`) : un tube depuis `ssh ceph01 …` suffit. Côté client, `--id rbd-test` fait chercher `/etc/ceph/ceph.client.rbd-test.keyring`.
</details>

<details><summary>Indice 2</summary>

`rbdmap` lit `/etc/ceph/rbdmap` (une image et ses paramètres par ligne : `id=`, `keyring=`), mappe les images au démarrage, puis monte les entrées de `fstab` qui pointent vers `/dev/rbd/<pool>/<image>`. Un montage sans `noauto` serait tenté par systemd **avant** que l'image existe. Le retour à un instantané réécrit l'image : un système de fichiers monté pendant ce temps ne le saurait pas.
</details>

<details><summary>Indice 3</summary>

Un clone porte le **même** système de fichiers que son parent, donc le même UUID XFS : le noyau refuse de monter deux fois le même UUID. L'option de montage `nouuid` le permet ponctuellement ; `xfs_admin -U generate` donne au clone un UUID à lui (à faire démonté). Les clones de « format 2 » n'exigent plus de protéger l'instantané quand tous les clients sont assez récents : regarde `ceph osd get-require-min-compat-client`.
</details>

**Pour aller plus loin** (facultatif) : mesure le temps d'un `rbd clone` d'une image de 10 Gio pleine et celui d'un `rbd cp` : explique l'écart. Lis la page « RBD Layering » et ce qu'est la fonctionnalité `deep-flatten`.

---

### M08-E07 — Lire l'état d'un cluster  `LAB` `★`

> **Ticket PLAT-907** — *De : Nadia Roussel*
> À partir du mois prochain, mes collègues d'astreinte auront Ceph dans leur périmètre. Ils savent lire un `top` et un `journalctl`, pas un `ceph -s`. Il me faut une fiche d'une page : quelles commandes, dans quel ordre, ce qui est grave et ce qui ne l'est pas, et les deux ou trois gestes autorisés sans réveiller l'équipe. Mais avant d'écrire, je veux que tu aies **vu** un cluster dégradé et revenir à la normale, pas seulement lu la documentation.

**Objectifs pédagogiques**
- Lire `ceph -s`, `ceph health detail`, l'arbre des OSD, l'état des PG, la capacité, les démons de l'orchestrateur.
- Provoquer sans risque des états dégradés connus (OSD arrêté, OSD sorti, drapeau d'exploitation) et lire leur signature.
- Connaître le rôle et le danger des drapeaux (`noout` et ses voisins).
- Rédiger une fiche d'astreinte utile.

**Prérequis** : M08-E06 (le cluster porte des données).
**Durée indicative** : 2 h.

**Contexte technique**
- Toutes les commandes se lancent sur un nœud `_admin`. Les manipulations portent sur **un seul OSD à la fois**, toujours remis en service avant la suivante.
- Livrable : `docs/stockage/lire-etat-ceph.md` dans `plateforme/medisphere` (MR relue par `nadia.roussel`).

**Travail demandé**
1. État de référence : `ceph -s`, `ceph health detail`, `ceph osd tree`, `ceph osd df tree`, `ceph df`, `ceph pg stat`, `ceph orch ls`, `ceph orch ps`, `ceph versions`, `ceph mon stat`. Pour chaque bloc de `ceph -s`, écris dans ton journal ce qu'il signifie.
2. Dans un second terminal, laisse tourner `ceph -w`. Arrête un OSD par l'orchestrateur (`ceph orch daemon stop osd.<ID>`). Observe : quels messages, quel état de santé, quels états de PG ? Au bout de combien de temps l'OSD passe-t-il `out` ? Que se passe-t-il alors ? (Lis `mon_osd_down_out_interval`.)
3. Remets l'OSD en service, attends `HEALTH_OK`. Recommence en posant d'abord `noout` : qu'est-ce qui change ? Lève le drapeau. Pourquoi un drapeau oublié est-il dangereux ?
4. Sors un OSD **vivant** du placement (`ceph osd out <ID>`) : `remapped`, `backfilling` ; suis la recopie dans `ceph -s` (lignes `recovery` et `io`). Remets-le `in`. Combien de temps et combien de données pour cet aller-retour ?
5. Lis les journaux : `ceph log last 30`, `ceph crash ls`, et le journal d'un démon côté hôte (`cephadm logs --name osd.<ID>` ou `journalctl -u ceph-<FSID>@osd.<ID>`). Où sont les journaux des démons, puisqu'ils tournent en conteneur ?
6. Rédige la fiche (une à deux pages) : les commandes des trente premières secondes, comment localiser la brique en cause, comment lire un état de PG, les gestes sûrs (avec leurs pièges), ce qu'on note dans le ticket. MR, relecture.
7. Vérifie que le cluster est revenu exactement à l'état de référence : aucun drapeau, aucun OSD `out`, aucune alerte en sourdine, aucun plantage non acquitté.

**Critères de réussite**
- [ ] Le cluster est en `HEALTH_OK`, neuf OSD `up` et `in` avec leur poids d'origine, tous les démons OSD en fonctionnement.
- [ ] Aucun drapeau d'exploitation (`noout`, `norebalance`…) n'est posé ; aucune alerte n'est mise en sourdine ; aucun plantage n'est en attente d'acquittement.
- [ ] La fiche `docs/stockage/lire-etat-ceph.md` est sur `main` de `plateforme/medisphere` et couvre au moins `ceph health detail`, `ceph osd tree`, `ceph orch ps`, les états `active+clean` et le drapeau `noout`.

**Vérification** : `lab/bin/check 08 07`

<details><summary>Indice 1</summary>

`ceph -s` se lit de haut en bas : santé, services (mon, mgr, osd et leurs nombres), données (pools, objets, occupation, états des PG), activité (E/S clientes, récupération). Un PG `active+clean` est sain ; tout autre état dit **ce qui manque**.
</details>

<details><summary>Indice 2</summary>

Un OSD `down` reste `in` pendant `mon_osd_down_out_interval` secondes (600 par défaut) : Ceph attend un éventuel retour avant de recopier. `noout` suspend ce passage à `out` pour **tous** les OSD. `ceph osd out` d'un OSD vivant déclenche une recopie sans perte de redondance : c'est la façon douce de vider un disque.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Health checks » et classe les dix codes qui te semblent les plus probables dans notre lab selon qu'ils justifient un réveil la nuit ou un ticket le lendemain. Cette liste servira en M08-E24 (supervision).

---

### M08-E08 — ZFS : le stockage local en rappel  `LAB` `★★`

> **Ticket PLAT-908** — *De : Karim Benali*
> Avant d'aller plus loin dans Ceph, un détour : beaucoup de nos serveurs garderont des disques locaux (journaux, caches, et `pve01` lui-même). ZFS est la référence du stockage local fiable : sommes de contrôle, miroir, compression, instantanés, réplication incrémentale. Fais-le sur `cephcli01`, sur deux petits disques ajoutés par le code. Et compare : ce que ZFS fait sur **une** machine, Ceph le fait comment sur **trois** ?

**Objectifs pédagogiques**
- Installer ZFS sur Debian 13 (section `contrib`, module DKMS) et comprendre pourquoi il n'est pas dans `main`.
- Créer un pool en miroir sur des identifiants de disques stables, des datasets avec leurs propriétés.
- Utiliser instantanés, retour arrière, envoi et réception (complet puis incrémental).
- Simuler la perte d'un disque du miroir, puis le *scrub*.
- Mettre en regard les mécanismes de ZFS et ceux de Ceph.

**Prérequis** : M08-E06 (`cephcli01`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Disques : deux disques de 8 Gio sur `ssd-lab`, présentés SSD, numéros de série `cephcli01-zfs1` et `cephcli01-zfs2`, ajoutés à `cephcli01` **par OpenTofu** (la VM ne doit pas être recréée).
- Paquets : `zfs-dkms`, `zfsutils-linux` (Debian 13, section `contrib`), en-têtes du noyau ; installés par un playbook `playbooks/zfs-local.yml` de `plateforme/ansible`. Le pool et les datasets se créent à la main : c'est le geste qu'on révise.
- Noms : pool `zlocal` (miroir), datasets `zlocal/donnees` (compressé) et `zlocal/copie` (reçu par `zfs receive`).

> ⚠️ **Attention** : `pve01` a peut-être un pool ZFS qui porte tes VMs personnelles. Aucune commande de cet exercice ne se lance sur `pve01`. Sur `cephcli01`, vérifie trois fois les périphériques avant `zpool create` : `/dev/disk/by-id/…cephcli01-zfs1` et `…zfs2`, jamais le disque système ni un `/dev/rbd*`.

**Travail demandé**
1. Ajoute les deux disques à `cephcli01` dans `envs/ceph`. Lis le plan : la VM doit être **modifiée en place**, pas remplacée. `apply`. Vérifie dans `cephcli01` (`lsblk`, `ls -l /dev/disk/by-id/`).
2. Écris et applique `playbooks/zfs-local.yml` (section `contrib`, paquets, chargement du module). Pourquoi ZFS est-il dans `contrib` et compilé sur place par DKMS ? Que se passera-t-il à la prochaine mise à jour du noyau ?
3. Crée le pool `zlocal` en miroir, avec des chemins `by-id` et `ashift=12`. Lis `zpool status`, `zpool list`, `zfs list`. Pourquoi `by-id` plutôt que `/dev/sdb` ? Que fixe `ashift`, et pourquoi ne peut-on plus le changer ?
4. Crée `zlocal/donnees` avec une compression (`lz4` ou `zstd`) et `atime=off`. Copie-y des données compressibles (journaux, sources) et d'autres qui ne le sont pas ; lis `compressratio`, `used`, `logicalused`.
5. Instantanés : crée `zlocal/donnees@j1`, modifie, `zfs diff`, récupère un fichier depuis `.zfs/snapshot/`, puis reviens entièrement à `@j1` (`zfs rollback`). Crée `@j2` après une nouvelle modification.
6. Réplication : envoie `@j1` vers `zlocal/copie` (`zfs send | zfs receive`), puis l'incrément `@j1 → @j2`. Compare les tailles des deux flux (`zfs send -nv`). Où cela servirait-il pour une sauvegarde hors site ?
7. Panne : mets un disque du miroir hors ligne (`zpool offline`), écris des données, lis `zpool status` (état `DEGRADED`), remets-le en ligne, observe la resynchronisation (*resilver*) : combien de données recopiées, et pourquoi si peu ? Lance un `scrub` et lis son résultat.
8. Vérifie que le pool revient au redémarrage de `cephcli01` (services `zfs-import-cache`, `zfs-mount`). Redémarre pour le prouver.
9. Comparaison, dans ton journal, sous forme de tableau : redondance (miroir / réplication), détection de corruption (sommes de contrôle / *scrub* et *deep-scrub*), instantanés, clones, compression, réplication à distance (`zfs send` / `rbd export-diff`, `rbd-mirror`), unité de panne, extension de capacité.

**Critères de réussite**
- [ ] `cephcli01` a deux disques de 8 Gio sur `ssd-lab`, déclarés dans `envs/ceph/cephcli01.tf` (VM modifiée, pas recréée).
- [ ] Le pool `zlocal` est en ligne, en miroir de deux disques désignés par leur identifiant `by-id` ; un *scrub* s'est terminé sans erreur ; le pool revient seul au démarrage.
- [ ] `zlocal/donnees` est compressé et a au moins deux instantanés ; `zlocal/copie` a été reçu par `zfs send/receive` et partage au moins deux instantanés avec la source (complet + incrémental).

**Vérification** : `lab/bin/check 08 08`

<details><summary>Indice 1</summary>

Debian 13 range ses sources au format deb822 dans `/etc/apt/sources.list.d/debian.sources` : la ligne `Components:` liste les sections. `zfs-dkms` compile le module contre les en-têtes du noyau **en cours** : le méta-paquet `linux-headers-amd64` suit les mises à jour du noyau.
</details>

<details><summary>Indice 2</summary>

`zpool create -o ashift=12 zlocal mirror /dev/disk/by-id/… /dev/disk/by-id/…`. L'envoi incrémental : `zfs send -i @j1 zlocal/donnees@j2 | zfs receive zlocal/copie` ; la cible ne doit pas avoir été modifiée depuis l'instantané commun (sinon `-F`, qui revient en arrière sur la cible : lis bien ce qu'il fait).
</details>

**Pour aller plus loin** (facultatif) : lis la page « ZFS on Linux » de la documentation de Proxmox VE : comment `pve01` utilise-t-il (peut-être) ZFS, et pourquoi Proxmox recommande-t-il de ne **pas** mettre ZFS au-dessus d'un contrôleur RAID matériel ? Lis aussi ce que sont `special` et `dedup` dans un pool, et pourquoi la déduplication est rarement une bonne idée.

---

### M08-E09 — Questions : architecture de Ceph  `Q` `★★`

> **Ticket PLAT-909** — *De : Karim Benali*
> Avant le palier 2, je veux savoir si tu as compris ce que tu as monté, pas seulement si ça marche. Réponds par écrit, en t'appuyant sur ce que tu as observé : sorties de commandes, temps mesurés, messages d'erreur.

**Objectifs pédagogiques**
- Expliquer l'architecture de Ceph et les choix faits au palier 1.
- Relier ce qui a été observé aux mécanismes (quorum, CRUSH, PG, réplication, cephx, orchestrateur).

**Prérequis** : M08-E02 à M08-E07.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds aux 12 questions.

1. Décris le chemin d'une écriture de 4 Kio par `cephcli01` dans `rbd-test/disque01`, du noyau du client jusqu'à l'acquittement : quels démons interviennent, sur quel réseau passe chaque échange, qui calcule où écrire, et quand l'écriture est-elle acquittée ? Les moniteurs sont-ils sur le chemin ?
2. Les trois moniteurs perdent tous le contact entre eux pendant 10 minutes, mais restent joignables par les clients et les OSD. Que continue de fonctionner, et que non ? Et si c'est le gestionnaire actif qui disparaît ?
3. *(QCM)* Le pool `rbd-test` est en `size 3, min_size 2`. Deux des trois nœuds s'arrêtent brutalement. Que voit `cephcli01` ?
   - A. Les lectures et les écritures continuent sur la copie restante
   - B. Les lectures continuent, les écritures échouent avec une erreur
   - C. Les E/S sur les PG concernés se bloquent (le processus attend) jusqu'au retour d'au moins un nœud
   - D. Le client bascule automatiquement sur un autre pool
4. Pourquoi Ceph place-t-il les données par **PG** plutôt qu'objet par objet ? Qu'arriverait-il avec 2 PG pour tout le pool ? Et avec 100 000 ?
5. En E04, la classe `hdd` de l'OSD sur `hdd-bulk` vient de la spécification **et** de la détection. Imagine que Proxmox présente ce disque avec `ssd=1` et que ta spécification ne fixe pas `crush_device_class` : que se passerait-il, et quand t'en apercevrais-tu ?
6. Pourquoi cephadm exécute-t-il chaque démon dans un conteneur, avec une image unique pour tous ? Cite deux avantages pour l'exploitation et un inconvénient.
7. *(QCM)* La clé SSH **privée** de l'orchestrateur est rangée dans le stockage `config-key` des moniteurs. Qui peut la lire ?
   - A. Personne : elle est chiffrée par les moniteurs
   - B. Toute entité cephx dont les capacités permettent de lire ce stockage (`client.admin` notamment) ; et toute faille qui l'expose donne root sur tous les nœuds
   - C. Seulement le compte `cephadm` des nœuds
   - D. Seulement le gestionnaire actif
8. Le réglage automatique de la mémoire des OSD est actif par défaut avec cephadm. Pourquoi l'avons-nous désactivé ? Dans quel type d'architecture serait-il un bon choix ?
9. `cephcli01` utilise `ceph-common` 18.2 de Debian, le cluster est en 20.2. Est-ce un problème ? Qu'est-ce qui, dans le client, dépend vraiment de la version (et qu'est-ce qui dépend du noyau) ?
10. Dans `ceph auth get client.rbd-test`, que permettent `profile rbd` pour le moniteur et `profile rbd pool=rbd-test` pour les OSD ? Que pourrait faire un attaquant qui vole ce trousseau ? Et s'il volait celui de `client.admin` ?
11. ZFS en miroir sur deux disques d'une même machine, Ceph à 3 copies sur trois machines : pour chacun, quelle est la plus petite panne qui rend les données **inaccessibles**, et la plus petite qui les **détruit** ?
12. Le dépôt des nœuds est `rpm-20.2.3`, l'image est `v20.2.3`. Qu'aurait-on risqué avec `rpm-tentacle` et `quay.io/ceph/ceph:v20` ? Décris le scénario concret, sur trois mois.

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 12 questions, en citant au moins trois observations faites dans le lab (sortie de commande, temps mesuré, message d'erreur).
- [ ] Tu as noté chaque réponse avec la grille du corrigé et listé ce qui reste flou.

<details><summary>Indice</summary>

Pour chaque question, distingue le **plan de contrôle** (moniteurs, gestionnaires, orchestrateur : cartes, décisions, déploiement) et le **plan de données** (clients et OSD : lectures, écritures, réplication). Beaucoup de réponses tiennent dans cette distinction.
</details>

**Pour aller plus loin** (facultatif) : transforme les questions 2, 7 et 11 en entrées du registre des risques de l'équipe (risque, probabilité, impact, mesure en place, mesure à venir) : Sophie Laurent en aura besoin pour la politique de stockage (M08-E33).
