# Module 08 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`tofu-modules/`, `infra/`, `ansible/`, `ceph/` pour `plateforme/ceph`, `medisphere/`). Ne copie que ce que l'exercice ajoute ou modifie.

**Ce qui a été vérifié à la rédaction** :
- `vm-noeud` et `envs/ceph` (nœuds et `cephcli01`, avec et sans les disques ZFS) passent `tofu validate` et `tofu fmt -check` avec OpenTofu 1.13 et les fournisseurs réels (`bpg/proxmox` 0.116, `e-breuninger/netbox` 5.8, `mmianl/powerdns` 2.5) ;
- les rôles `ceph_noeud`, `ceph_client`, `ca_lab` 1.2.0, les playbooks et les scénarios Molecule passent `ansible-lint` 26 (profil `production`) avec `community.general` 13.5 et `ansible.posix` 2.2 ;
- le paquet `cephadm-20.2.3-0.el10.noarch.rpm` de `download.ceph.com/rpm-20.2.3/el10/noarch/` : signature RSA/SHA256 par la clé `E84AC2C0460F3994` (empreinte complète `08B7 3419 AC32 B4E9 66C1 A330 E84A C2C0 460F 3994`), création du compte `cephadm` (dossier `/var/lib/cephadm`, `.ssh/authorized_keys`) par le script de pré-installation, dépendances `lvm2`, `python3`, `openssh-server` ;
- `cephadm 20.2.3` : aide complète de `bootstrap` (options citées ici), image par défaut `quay.io/ceph/ceph:v20` (étiquette flottante), écriture de `osd_memory_target_autotune = true` dans la section `[osd]` **seulement si** la configuration initiale n'en dit rien, déploiement de `ceph-exporter` lié à la pile de supervision ;
- tous les scripts (`amorcer.sh`, `pool-repliquee.sh`, checks) passent `shellcheck -x` et `bash -n` ; les spécifications passent `yamllint`.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- le déploiement complet sur trois VM Rocky 10 (amorçage, OSD, client) : l'environnement de rédaction n'avait ni Proxmox ni Rocky 10 ; les sorties montrées sont **représentatives**, pas copiées ;
- les dépendances de `ceph-common` 20.2.3 sur EL10 (EPEL et CRB supposés nécessaires, comme sur EL9) ; le paquet `epel-release` dans le dépôt « extras » de Rocky 10 ;
- le contexte SELinux de `/var/lib/cephadm/.ssh` : le rôle le force à `ssh_home_t` ; si la politique de Rocky 10 le fait déjà, la tâche ne change rien ;
- la valeur exacte calculée par le réglage automatique de la mémoire (E04, étape 6) : elle dépend de la mémoire vue par cephadm ;
- les messages exacts des refus cephx (E06, étape 4) et du refus de suppression de pool (E05) : cités d'après la documentation et le code, à comparer avec les tiens ;
- la référence `?ref=v2.2.0` de `plateforme/tofu-modules` : mets l'étiquette publiée par ta MR de `vm-noeud` (si le module 07 a déjà publié une v2.2.0, ce sera la suivante).

---

### M08-E01 — Test de positionnement : stockage

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, relis les « Concepts clés » de l'introduction avant E03 ; les questions 13 à 19 sont reprises en profondeur dans tout le module (E05, E07, E14, E15, E35-E38).

**Réponses argumentées — disques et performances**

**1. IOPS, débit, latence.** IOPS : opérations d'E/S par seconde (petites, aléatoires en général). Débit : volume par seconde (Mo/s, grandes E/S séquentielles). Latence : durée d'une opération, de la demande à l'acquittement. Ordres de grandeur : disque dur 7 200 tr/min ≈ 80-150 IOPS aléatoires, 150-250 Mo/s séquentiels, 5-10 ms ; SSD SATA ≈ 50 000-90 000 IOPS, 500 Mo/s (plafond SATA), 0,1 ms ; NVMe ≈ 300 000 à plus d'un million d'IOPS, 3-7 Go/s, 20-100 µs. Une base transactionnelle sent d'abord la **latence** des petites écritures synchrones (chaque validation attend son `fsync`) : c'est elle qui limite le nombre de transactions par seconde, bien avant le débit. Dans Ceph, chaque écriture traverse en plus le réseau deux fois (client → primaire → répliques) : la latence réseau s'ajoute à celle des disques.

**2. Réponse B.** `fsync()` rend la main quand les données du fichier et les métadonnées nécessaires pour les relire sont sur un support persistant ; le noyau envoie au disque un ordre de vidage de son cache d'écriture (FLUSH/FUA). A décrit un simple `write()`. C est faux : la réplication est l'affaire d'une couche au-dessus (Ceph, RAID). D est faux : c'est une obligation, pas un indice ; mais un disque qui **ment** (cache volatile sans protection, ordres de vidage ignorés) peut la trahir, d'où les SSD « à protection contre la perte d'alimentation » recommandés pour Ceph.

**3. Amplification d'écriture.** Le rapport entre ce qui est réellement écrit sur le support et ce que l'application a demandé. Sources : le système de fichiers (journal, métadonnées, copie sur écriture), la réplication (×3 dans Ceph), l'alignement (une écriture de 4 Kio dans un bloc de 16 Kio, ou un code d'effacement qui réécrit une bande entière), la base de métadonnées de BlueStore (RocksDB, compactions), et dans le SSD le ramasse-miettes du contrôleur (une page ne s'écrit qu'après effacement d'un bloc entier). Elle use les SSD et consomme de la bande passante.

**4. TRIM.** Le système de fichiers signale au support les blocs qu'il n'utilise plus. Pour un SSD, le contrôleur peut les effacer à l'avance (moins d'amplification). Pour un disque virtuel mince, l'hyperviseur peut **rendre** l'espace au stockage sous-jacent (`discard=on` sur le disque Proxmox, comme dans `vm-noeud`). Sans TRIM, un disque mince ne fait que grossir : les blocs effacés dans l'invité restent alloués sur l'hôte. Même logique pour une image RBD : allouée à la demande, elle ne rend l'espace qu'avec `discard`.

**Réponses argumentées — redondance locale**

**5. RAID.** Sur 6 disques de 4 To : RAID 1 (miroirs par paires, en pratique RAID 10) et RAID 10 : 12 To utiles, une panne par paire tolérée (au moins 1, au plus 3 si chacune touche une paire différente), pénalité en écriture ×2 ; RAID 5 : 20 To, 1 panne, pénalité ×4 (lire données et parité, écrire données et parité) ; RAID 6 : 16 To, 2 pannes, pénalité ×6. Le RAID 5 sur gros disques durs : la reconstruction lit **tous** les autres disques en entier (des heures, voire des jours), pendant lesquels une seconde panne ou une simple erreur de lecture irrécupérable (probabilité non négligeable sur 20 To lus) fait perdre la grappe.

**6. Réponse B.** Si le courant coupe entre l'écriture d'un bloc de données et celle de la parité de sa bande, la parité ne correspond plus aux données ; on ne le saura qu'à la reconstruction suivante, qui produira des données fausses. A, C et D sont des soucis réels mais différents (C est justement la **parade** matérielle : un cache protégé par batterie qui termine les écritures). ZFS (RAID-Z) et Ceph n'ont pas ce trou : écritures en copie sur écriture et transactions.

**7. Corruption silencieuse.** Un bit change sur le support (usure, firmware, câble, mémoire) sans erreur signalée : le disque rend une donnée fausse comme si elle était bonne. Un système à sommes de contrôle calcule une empreinte de chaque bloc à l'écriture, la range **ailleurs** (dans le bloc parent pour ZFS), et la vérifie à chaque lecture ; avec une copie (miroir) ou de la parité, il lit la bonne version et réécrit la mauvaise. Le *scrub* relit **tout** volontairement pour trouver et réparer les erreurs avant qu'on en ait besoin. Ceph fait l'équivalent : sommes de contrôle de BlueStore à chaque lecture, *scrub* (métadonnées) et *deep-scrub* (données) qui comparent les copies entre OSD.

**8. Instantané ≠ sauvegarde.** (1) Il vit **sur le même stockage** : la perte du pool, du disque ou du cluster l'emporte avec les données. (2) Il partage les blocs non modifiés avec l'original : une corruption de ces blocs touche les deux. (3) Il est dans le **même domaine d'administration** : un attaquant ou une erreur qui a les droits de supprimer les données peut supprimer les instantanés. Et souvent : pas de rétention longue, pas de copie hors site, pas de restauration testée. Une sauvegarde est une copie **indépendante**, ailleurs, protégée, testée (M08-E25).

**Réponses argumentées — stockage en réseau**

**9. Bloc, fichier, objet.** Bloc : le client voit un disque (blocs numérotés), il y met **son** système de fichiers ; les métadonnées sont chez le client ; iSCSI, FC, NVMe-oF, RBD ; disques de VMs, bases de données. Fichier : le client voit une arborescence partagée ; les métadonnées (noms, droits, verrous) sont chez le serveur ; NFS, SMB, CephFS ; partages entre plusieurs machines. Objet : le client voit des objets (clé → données + métadonnées) dans des compartiments, par une API HTTP ; pas de modification en place, pas d'arborescence réelle ; S3, Swift, RGW ; documents, sauvegardes, artefacts, données d'applications « cloud ».

**10. Réponse B.** Un système de fichiers « local » comme XFS suppose qu'un seul noyau l'écrit : chacun garde en mémoire sa vision des blocs libres et des métadonnées, et écrase les changements de l'autre. Corruption assurée, souvent en quelques minutes. A est faux (XFS n'est pas un système de fichiers en grappe : il faudrait GFS2 ou OCFS2, ou un système partagé comme CephFS). C et D sont faux : la cible ne sait rien des systèmes de fichiers ; elle sert des blocs à qui y a droit. C'est la raison d'être du verrou exclusif de RBD (`exclusive-lock`) et des options de mappage exclusif.

**11. Réseau de réplication.** Pour que le trafic interne (réplication, récupération après panne, battements de cœur) ne concurrence pas les clients, et inversement, et pour pouvoir dimensionner et isoler chacun. Pour 1 Gio écrit avec 3 copies : 1 Gio sur le réseau public (client → OSD primaire), 2 Gio sur le réseau cluster (primaire → deux secondaires). Pendant une récupération, le réseau cluster peut être saturé pendant des heures : c'est là qu'il protège les clients. (Ceph recommande de ne le séparer que si on a de bonnes raisons : un seul réseau rapide et redondant suffit souvent ; dans notre lab, la séparation sert surtout à l'apprendre.)

**12. Trames jumbo.** Moins de paquets pour le même volume (6 fois moins entre 1500 et 9000), donc moins d'interruptions et de traitement par paquet, un peu moins d'en-têtes : utile pour les gros transferts. Le risque : un seul maillon à 1500 sur le chemin (carte, pont, commutateur, VNet) et les grandes trames sont **jetées** sans bruit ; si le message ICMP « fragmentation nécessaire » est filtré, la découverte du MTU échoue (« trou noir ») : les connexions s'établissent (petits paquets), puis se figent dès qu'un gros transfert commence. C'est la panne M08-E42 et M07-E38. D'où le test `ping -M do -s 8972` dans le rôle `ceph_noeud`.

**Réponses argumentées — systèmes distribués**

**13. Quorum.** La majorité stricte des membres, seule autorisée à décider : deux groupes séparés ne peuvent pas avoir **tous les deux** la majorité, donc il ne peut y avoir deux décisions contradictoires (*split-brain*). Avec 2 moniteurs, la majorité est 2 : la perte d'un seul arrête tout (pire qu'un seul !). Avec 3, on tolère 1 perte. Avec 4, la majorité est 3 : on ne tolère toujours qu'1 perte, avec un membre de plus à faire tomber en panne et à synchroniser. D'où les nombres impairs : 3 ou 5.

**14. Réponse B.** Dans la salle B, le système ne peut pas savoir si la salle A est morte ou simplement coupée et continue d'écrire. Un système cohérent refuse d'écrire sans la majorité. A est le choix d'un système « disponible » (AP), qui devra réconcilier des écritures contradictoires : inacceptable pour un disque de VM. C est le *split-brain* lui-même. D est une variante de A pour l'administrateur. Ceph est cohérent : sans quorum de moniteurs, plus de changement de carte ; sans `min_size` copies, plus d'E/S sur le PG.

**15. CAP.** En cas de partition réseau, un système distribué doit choisir entre la **cohérence** (toutes les lectures voient la dernière écriture, ou une erreur) et la **disponibilité** (toute requête reçoit une réponse). Un stockage bloc de VMs doit être **CP** : un disque qui renverrait des données anciennes ou contradictoires corromprait les systèmes de fichiers des VMs ; mieux vaut que l'E/S attende.

**16. Placement par calcul.** Avantages : pas de table centrale à interroger à chaque E/S (pas de goulet, pas de point unique de défaillance sur le chemin des données), chaque client calcule lui-même où lire et écrire, la carte est petite et change rarement. Inconvénient principal : quand la topologie change (ajout ou perte d'un disque, d'un hôte), le calcul donne d'autres résultats pour une partie des données, qui **doivent bouger** ; un bon algorithme (CRUSH, hachage cohérent) limite ce mouvement à la proportion nécessaire, sans pouvoir l'annuler.

**17. Domaine de panne.** Un ensemble de composants qui peuvent tomber ensemble pour une même cause. Du plus petit au plus grand : disque (OSD), hôte, baie (alimentation, commutateur de haut de baie), rangée ou salle, site. Pour trois serveurs dans une même baie : l'**hôte** (chaque copie sur un serveur différent) ; la baie ne peut pas être un domaine de panne puisqu'il n'y en a qu'une : sa perte reste un risque à couvrir par une sauvegarde hors site (M08-E25) ou un second site.

**18. Réplication et codes d'effacement.** 3 copies : 200 % de surcoût (3 To bruts pour 1 utile), 2 pannes tolérées, écriture simple (envoyer trois fois), reconstruction simple (recopier une copie), lecture d'un seul OSD. 4 + 2 : 50 % de surcoût (6 morceaux pour 4 de données), 2 pannes tolérées, écriture plus coûteuse (calcul, et réécriture partielle d'une bande pour une petite modification), reconstruction qui doit lire 4 morceaux pour en refaire 1, besoin d'au moins 6 domaines de panne. On réserve les codes d'effacement aux gros volumes froids (objet, sauvegardes) ; la réplication aux disques de VMs et aux métadonnées (M08-E15).

**Réponses argumentées — exploitation**

**19. Attendre avant de reconstruire.** Beaucoup d'« absences » sont courtes : redémarrage, mise à jour, câble réinséré. Reconstruire immédiatement déplacerait des centaines de Gio pour rien, chargerait les disques et le réseau, puis les redéplacerait au retour. Ceph attend 10 minutes (`mon_osd_down_out_interval`) avant de sortir un OSD absent. Mais attendre trop longtemps prolonge la période où les données n'ont que 2 copies sur 3 : une seconde panne pendant cette fenêtre fait passer certaines données à 1 copie (plus d'écriture), une troisième les perd. Le compromis se règle, et se suspend volontairement (`noout`) pendant une maintenance.

**20. Indicateurs.** Exemples : remplissage (alerte à 75 %, critique à 85 %, Ceph refuse d'écrire à 95 % par défaut) ; état de santé et redondance (toute donnée sous son nombre de copies depuis plus de 15 minutes, tout PG inactif immédiatement) ; latence des E/S (p99 des écritures au-dessus d'un seuil mesuré en temps normal, par exemple 3 fois la référence) ; erreurs disque (SMART, erreurs de lecture, *scrub* qui trouve des incohérences) ; et pour un système distribué, le quorum (un moniteur absent : alerte, deux : critique). M08-E24 met cela en place.

---

### M08-E02 — Préparer les nœuds Ceph

**Solution**

*A. Avant d'écrire.*

1. cephadm attend : Python 3, systemd, Podman ou Docker, une synchronisation du temps (chrony), LVM2 (les OSD sont des volumes logiques), SSH. Tentacle documente Rocky Linux 10 comme plateforme prise en charge depuis 20.2.2 (paquets et hôte de conteneurs) ; aucun paquet pour Debian 13 sur `download.ceph.com` (seulement bookworm, jammy, noble), et le paquet `cephadm` de Debian 13 est en 18.2 (Reef) : il amorcerait un cluster Reef ou refuserait l'image Tentacle (`--allow-mismatched-release`).
2. Image Rocky :
   ```
   admin@adm01:~$ ssh root@pve01 'qm list | grep rocky10-gold'
   admin@adm01:~$ ssh root@pve01 'qm config <VMID-CURRENT> | grep -E "^(tags|description)"'
   ```
   Le manifeste dans la description dit ce que contient l'image. Plus sûr : une VM d'essai (2087) clonée de l'image, puis `ls /etc/pki/ca-trust/source/anchors/` et `trust list | grep -i medisph`. Si `medisphere-provisoire.crt` est encore là, la variable de famille de `plateforme/images` (M03-E25, `fichiers/ca/`) n'a été changée que pour Debian en M06-E03 : corrige, pipeline, nouvelle image `rocky10` `current`, destruction de 2087.
3. Étiquettes : trois entrées dans le fichier de données de `outils/netbox/` (M06-E05), `uv run modeliser.py --dry-run` puis sans. Sans elles, le fournisseur NetBox refuse de créer la VM (étiquette inconnue).

*B. Le module et les VMs.* Fichiers : [`tofu-modules/vm-noeud/`](fichiers/M08-E02/tofu-modules/vm-noeud/) (`versions.tf`, `variables.tf`, `netbox.tf`, `main.tf`, `outputs.tf`, `README.md`) et [`infra/envs/ceph/`](fichiers/M08-E02/infra/envs/ceph/) (`versions.tf`, `providers.tf`, `variables.tf`, `ceph.tf`, `terraform.tfvars.exemple`).

L'appel des trois nœuds tient en un bloc `for_each` sur une table `nom => numéro`, d'où se déduisent VMID et adresses :
```hcl
module "ceph" {
  for_each = var.noeuds_ceph            # { ceph01 = 1, ceph02 = 2, ceph03 = 3 }
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=v2.2.0"
  vmid     = 2080 + each.value
  famille  = "rocky10"
  cartes = [
    { vnet = "vstopub", prefixe = "10.10.30.0/24", ipv4 = "10.10.30.${50 + each.value}", mtu = 9000, passerelle = true },
    { vnet = "vstoclu", prefixe = "10.10.31.0/24", ipv4 = "10.10.31.${50 + each.value}", mtu = 9000 },
  ]
  disques_donnees = [
    { taille_go = 64, datastore = "ssd-lab", ssd = true, serie = "${each.key}-ssd1" },
    { taille_go = 64, datastore = "ssd-lab", ssd = true, serie = "${each.key}-ssd2" },
    { taille_go = 64, datastore = "hdd-bulk", ssd = false, serie = "${each.key}-hdd1" },
  ]
  # …
}
```
Le plan crée, par nœud : une VM NetBox, deux interfaces, deux adresses, l'IP primaire, la VM Proxmox, puis A et PTR (trois nœuds : 24 ressources). L'ordre vient des références : la VM Proxmox lit `netbox_ip_address.carte[*].ip_address` pour cloud-init, donc elle attend NetBox.

6. Sur `pve01` :
   ```
   root@pve01:~# qm config 2081 | grep -E '^(cpu|net|scsi|scsihw)'
   cpu: x86-64-v3
   net0: virtio=BC:24:11:…,bridge=vstopub,mtu=9000
   net1: virtio=BC:24:11:…,bridge=vstoclu,mtu=9000
   scsi0: local-nvme:vm-2081-disk-0,discard=on,iothread=1,size=20G,ssd=1
   scsi1: ssd-lab:vm-2081-disk-1,backup=0,discard=on,iothread=1,serial=ceph01-ssd1,size=64G,ssd=1
   scsi2: ssd-lab:vm-2081-disk-2,backup=0,discard=on,iothread=1,serial=ceph01-ssd2,size=64G,ssd=1
   scsi3: hdd-bulk:vm-2081-disk-3,backup=0,discard=on,iothread=1,serial=ceph01-hdd1,size=64G
   scsihw: virtio-scsi-single
   ```
   Dans le nœud :
   ```
   [root@ceph01 ~]# lsblk -d -o NAME,SIZE,ROTA,SERIAL
   NAME SIZE ROTA SERIAL
   sda   20G    0 
   sdb   64G    0 ceph01-ssd1
   sdc   64G    0 ceph01-ssd2
   sdd   64G    1 ceph01-hdd1
   ```
   Le noyau lit la **vitesse de rotation** que le disque SCSI annonce (page VPD « Block Device Characteristics ») : avec `ssd=1`, Proxmox passe `rotation_rate=1` à QEMU, qui annonce « non rotatif » ; sans, QEMU n'annonce rien et le noyau garde sa valeur par défaut : rotatif. L'information est donc **déclarée** par l'hyperviseur, pas mesurée : la vérité sur le support physique (SSD ou disque dur de `pve01`) n'arrive dans la VM que parce que le code l'a dit. L'ordre `sdb`, `sdc`, `sdd` n'est pas garanti d'un démarrage à l'autre ; les numéros de série (`/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_ceph01-ssd1`), si.

*C. Ansible.*

7. [`ca_lab` 1.2.0](fichiers/M08-E02/ansible/collections/ansible_collections/medisphere/socle/) : variables de famille dans `vars/Debian.yml` et `vars/RedHat.yml` (dossier d'ancres, commande, magasin consolidé), `include_vars` sur `os_family`, module `package` au lieu d'`apt`. Version **mineure** : nouvelle fonctionnalité, aucun changement pour les consommateurs Debian (SemVer). Sur Rocky : ancre dans `/etc/pki/ca-trust/source/anchors/`, `update-ca-trust extract`, vérification dans `/etc/pki/tls/certs/ca-bundle.crt`.
8. [`inventories/lab/netbox-ceph.yml`](fichiers/M08-E02/ansible/inventories/lab/netbox-ceph.yml) et [`ansible.cfg.extrait`](fichiers/M08-E02/ansible/ansible.cfg.extrait) (`inventory = …/netbox.yml,…/netbox-ceph.yml`). Les filtres `tag` de l'API NetBox se combinent en **ET** : `?tag=socle&tag=env-m08` ne renvoie que les objets qui portent **les deux** étiquettes, c'est-à-dire rien. Deux sources dans le même dossier partagent les `group_vars`. Le garde-fou de `site.yml` compte les membres de `socle` : les nœuds Ceph n'en sont pas.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph env_m08
   @env_m08:
     |--@role_ceph:
     |  |--ceph01
     |  |--ceph02
     |  |--ceph03
   ```
9. Rôle [`ceph_noeud`](fichiers/M08-E02/ansible/roles/ceph_noeud/) : `preconditions.yml` (Rocky 10, nom d'hôte, SELinux), `depot.yml` (clé par empreinte, CRB, EPEL, deux dépôts `noarch` et `x86_64` de **rpm-20.2.3**), `paquets.yml` (prérequis, `cephadm-20.2.3` et `ceph-common-20.2.3` par nom-version, vérification de `cephadm version`), `orchestrateur.yml` (compte, sudoers validé par `visudo -cf`, contexte `ssh_home_t`, clé publique quand elle existe), `reseau.yml` (MTU dans le profil NetworkManager, MTU effectif, `ping -M do -s 8972` vers les autres nœuds sur les deux réseaux), `controles.yml` (chrony, `cephadm check-host`). Scénario [`molecule/ceph_noeud/`](fichiers/M08-E02/ansible/molecule/ceph_noeud/) : instance 2049 `rocky10`, une carte en 1500, `ceph_noeud_verifier_reseau: false`, une clé publique de test ; `verify.yml` contrôle les versions, l'épinglage du dépôt, sudo, le contexte SELinux, `permitrootlogin no`, `check-host`.
   ```
   admin@adm01:~/src/ansible$ uv run molecule test -s ceph_noeud
   ```
   Dépôt **de la version** plutôt que `rpm-tentacle` : `rpm-tentacle` reçoit chaque nouvelle 20.2.x ; avec `dnf-automatic` (actif dans l'image dorée, correctifs de sécurité), un nœud pourrait passer seul en 20.2.4 pendant que les autres restent en 20.2.3, et `cephadm` ne serait plus de la version du cluster. Avec `rpm-20.2.3`, il n'existe rien de plus récent dans le dépôt : la montée de version est **un changement de variable**, en M08-E26.
10. [`playbooks/ceph-noeuds.yml`](fichiers/M08-E02/ansible/playbooks/ceph-noeuds.yml) : garde-fou (≥ 3 nœuds, adresse de connexion = adresse publique du plan), `serial: 1`, `max_fail_percentage: 0`. Pas de `base` : il est écrit pour Debian (`apt`, `unattended-upgrades`), et l'image dorée Rocky contient déjà l'équivalent (chrony vers la passerelle du VLAN, journal persistant, `dnf-automatic` en mode sécurité, durcissement de M03-E25). Rendre `base` multi-familles est une bonne idée de suite (ticket à ouvrir), pas un prérequis.
    ```
    admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ceph-noeuds.yml --check --diff
    admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ceph-noeuds.yml
    …
    TASK [ceph_noeud : Trames jumbo vers les autres nœuds, réseaux public et cluster] ***
    ok: [ceph01] => (item=10.10.30.52)
    ok: [ceph01] => (item=10.10.31.52)
    …
    PLAY RECAP ***
    ceph01 : ok=… changed=… failed=0
    ```
    Second passage : `changed=0`.
11. Registre des secrets : rien de nouveau (aucune clé créée ; la clé publique du cluster n'existe pas encore). Matrice des flux : rien sur les passerelles, tout reste dans les VLAN 30 et 31 ; noter dans la matrice que le pare-feu **local** des nœuds est tenu par cephadm (firewalld).

Le check vérifie la configuration Proxmox (CPU, mémoire, cartes et MTU, disques et leur présentation), le DNS, NetBox, l'état de chaque nœud (système, versions, dépôt, services, SELinux, root, compte `cephadm`, racine de confiance, MTU, adresses, nom d'hôte), les trames jumbo et le code sur `main`.

**Explications**

- **Un module à côté, pas une version majeure.** `vm-debian` v2 a des consommateurs (le socle, `envs/lab-m06`) qui n'ont besoin ni de plusieurs cartes ni de disques de données. Le transformer aurait imposé une v3 à tous. `vm-noeud` reprend ses **noms** d'entrées (`nom`, `vmid`, `etiquettes`, `cle_ssh_admin`, `netbox_cluster`…) : passer de l'un à l'autre ne demande pas de réapprendre. C'est la réponse à la question « un second module ou une variable `famille` ? » du « pour aller plus loin » de M05-E13 : la famille est une variable de `vm-noeud`, mais le module simple reste simple.
- **Un nom sur une seule adresse.** Le DNS n'annonce que l'adresse publique. Un nom (ou un PTR) sur 10.10.31.5N ferait répondre le DNS avec une adresse injoignable depuis `adm01` (VLAN non routé) ; et cephadm, s'il résolvait les noms (il ne le fait pas ici : adresses explicites en E03), pourrait choisir la mauvaise.
- **Pourquoi `cephadm` et pas root.** Le module `cephadm` du gestionnaire actif ouvre des sessions SSH vers tous les nœuds pour déployer et reconfigurer. Avec `root`, il faudrait autoriser `PermitRootLogin` sur des hôtes dont la politique (M04-E11) l'interdit. Avec un compte dédié et sudo sans mot de passe, la puissance est la même (sudo ALL), mais elle est **nommée**, journalisée (`sudo` laisse une trace par commande), révocable sans toucher à root, et cohérente avec la règle « jamais root en SSH ».
- **SELinux reste actif.** Les conteneurs de cephadm tournent avec les contextes que Podman leur donne ; le seul point à traiter est le `.ssh` d'un compte dont le dossier n'est pas sous `/home`. Désactiver SELinux « pour que ça marche » aurait été une régression de sécurité de toute la machine pour un problème d'étiquette sur un dossier.
- **MTU : vérifier plutôt que supposer.** La carte Proxmox en `mtu=9000` annonce le MTU à l'invité (fonctionnalité `host_mtu` de virtio-net), mais NetworkManager peut appliquer celui de son profil. Le rôle fixe le profil (persistant), puis teste ce qui compte vraiment : un paquet de 9000 octets **non fragmentable** entre nœuds, sur chaque réseau. Un échec ici, c'est une panne évitée en E04.

**Alternatives**

- **Étendre `vm-debian` en v3** (cartes et disques en listes, famille) : un seul module à maintenir, mais une version majeure pour tout le socle. Défendable dans une équipe qui a peu de consommateurs.
- **Ressource `proxmox_virtual_environment_vm` directe dans `envs/ceph`** : rapide, mais duplique la logique NetBox/cloud-init et sera recopiée pour OpenStack (M10). C'est ce que le ticket refuse.
- **cephadm en root** (comportement par défaut, clé dans `/root/.ssh/authorized_keys`, `PermitRootLogin prohibit-password`) : plus simple, c'est ce que suit la documentation ; mais contraire à notre durcissement et moins traçable.
- **Paquets `cephadm` par `curl`** depuis `download.ceph.com/rpm-20.2.3/el10/noarch/cephadm` (binaire « zipapp ») : la documentation le propose, mais aucune somme de contrôle n'est publiée à côté. Le RPM signé est vérifiable (`gpgcheck`) et crée le compte `cephadm`.
- **Inventaire statique** (`inventories/ceph/hosts.yml`) : rapide, mais une seconde vérité à côté de NetBox.

**Pièges classiques**

- Oublier `x86-64-v3` (ou `host`) : le noyau de Rocky 10 s'arrête au démarrage (« CPU not supported »). Le module le déduit de la famille.
- `ssd=1` sur le disque de `hdd-bulk` (copier-coller) : l'OSD sera classé `ssd`, et la règle CRUSH « ssd » du palier 2 mettra des données « rapides » sur un disque dur.
- Désigner les disques par `/dev/sdX` dans la suite (spécification d'OSD, ZFS) : l'ordre peut changer au démarrage.
- Laisser les disques d'OSD dans la sauvegarde PBS (`backup=1` par défaut dans Proxmox) : 576 Gio sauvegardés chaque nuit, inutilisables seuls (un OSD sans les autres ne se restaure pas). La sauvegarde des données Ceph se fait au niveau Ceph (E25).
- Un nom ou un PTR sur l'adresse du réseau cluster dans NetBox : publié par `medictl dns sync` (M06-E15), il ferait résoudre `ceph01` vers une adresse non routée.
- Le contexte SELinux du `.ssh` de `cephadm` oublié : l'amorçage réussit sur `ceph01` (connexion locale), puis l'ajout de `ceph02` échoue avec un message SSH peu clair (`Permission denied (publickey)`) ; `ausearch -m avc -ts recent` sur `ceph02` montre le refus.
- `sudoers` écrit sans `validate` : une faute de frappe et sudo ne fonctionne plus pour personne, Ansible compris (il ne reste que la console `qm terminal`).
- Rocky 10 et `ifcfg` : NetworkManager n'utilise plus les fichiers `ifcfg` mais des profils *keyfile* ; modifier `/etc/sysconfig/network-scripts/` n'a aucun effet.

**En production chez MédiSphère**

Des serveurs dédiés : CPU et mémoire dimensionnés selon les recommandations (au moins 4 Go par OSD sur disque rapide), disques NVMe pour les données ou au moins pour RocksDB/WAL des disques durs, deux liens 25 Gbit/s agrégés (LACP) par réseau, commutateurs redondants, MTU vérifié à chaque changement réseau. L'inventaire du matériel est dans NetBox (DCIM) et les numéros de série des disques permettent de retrouver le disque à remplacer dans la baie (RB-080). Le compte de l'orchestrateur pourrait utiliser un **certificat SSH** signé par notre CA (cephadm le prévoit), avec vérification des clés d'hôte.

---

### M08-E03 — Amorcer le cluster avec cephadm

**Solution**

*A. Préparer.*

1. Correspondances : image → `--image` (globale) ; moniteur → `--mon-ip 10.10.30.51` ; réseau cluster → `--cluster-network 10.10.31.0/24` ; compte SSH → `--ssh-user cephadm` ; configuration initiale → `--config` ; pas de pile de supervision → `--skip-monitoring-stack`. Réponses :
   - sans `--image`, cephadm 20.2.3 prend `quay.io/ceph/ceph:v20` : une étiquette **flottante**, qui désigne la dernière 20.x publiée le jour du téléchargement ; deux nœuds ajoutés à deux moments différents pourraient tirer deux versions ;
   - sans `osd_memory_target_autotune` dans la section `[osd]` de la configuration initiale, l'amorçage l'y met à `true` (code de cephadm ; avertissement de la documentation : « cephadm enables osd_memory_target_autotune on bootstrap ») ;
   - `--initial-dashboard-password`, `--registry-password` et `--registry-username` passent un secret en argument : visibles dans `ps` et l'historique.
2. Fichiers : [`ceph/bootstrap/initial-ceph.conf`](fichiers/M08-E03/ceph/bootstrap/initial-ceph.conf), [`ceph/bootstrap/amorcer.sh`](fichiers/M08-E03/ceph/bootstrap/amorcer.sh), [`ceph/.yamllint`](fichiers/M08-E03/ceph/.yamllint), [`ceph/README.md`](fichiers/M08-E03/ceph/README.md). Le script vérifie l'hôte, la version de `cephadm`, l'absence de cluster (`/etc/ceph/ceph.conf`, `cephadm ls`), les deux adresses, le compte et son sudo, `cephadm check-host`, puis lance :
   ```
   cephadm --image quay.io/ceph/ceph:v20.2.3 bootstrap \
     --mon-ip 10.10.30.51 \
     --cluster-network 10.10.31.0/24 \
     --ssh-user cephadm \
     --config initial-ceph.conf \
     --skip-monitoring-stack
   ```

*B. Amorcer.*

3. `ms-snapshot --dry-run 2081 2082 2083`, puis `ms-snapshot --prefix avant-amorcage 2081 2082 2083` (si ton stockage `hdd-bulk` ne prend pas les instantanés, une destruction-recréation par OpenTofu fait le même office : le rôle remet tout en place en dix minutes).
4. Sur `ceph01` :
   ```
   admin@adm01:~$ scp -r ~/src/ceph/bootstrap ceph01:
   admin@adm01:~$ ssh ceph01
   [admin@ceph01 ~]$ sudo bash bootstrap/amorcer.sh
   OK      cephadm 20.2.3
   OK      aucun cluster existant
   …
   Verifying podman|docker is present...
   …
   Pulling container image quay.io/ceph/ceph:v20.2.3...
   Ceph version: ceph version 20.2.3 (…) tentacle (stable)
   …
   Creating mon...
   …
   Generating ssh key...
   Wrote public SSH key to /etc/ceph/ceph.pub
   Adding key to cephadm@localhost authorized_keys...
   …
   Ceph Dashboard is now available at:
        URL: https://ceph01.par1.medisphere.internal:8443/
       User: admin
   Password: <généré>
   …
   Bootstrap complete.
   ```
   Note le fsid (`ceph fsid`) et le mot de passe.
5. Inventaire :
   ```
   [root@ceph01 ~]# ls -l /etc/ceph/
   -rw-------. 1 root root  151 … ceph.client.admin.keyring
   -rw-r--r--. 1 root root  … ceph.conf
   -rw-r--r--. 1 root root  … ceph.pub
   -rw-r--r--. 1 root root   92 … rbdmap
   [root@ceph01 ~]# cephadm ls --no-detail | jq -r '.[].name'
   mon.ceph01
   mgr.ceph01.xxxxxx
   crash.ceph01
   [root@ceph01 ~]# systemctl list-units 'ceph*' --no-legend
   [root@ceph01 ~]# podman ps --format '{{.Names}} {{.Image}}'
   [root@ceph01 ~]# firewall-cmd --list-services
   ceph ceph-mon cockpit dhcpv6-client ssh
   ```
   La clé SSH **privée** de l'orchestrateur est dans le magasin `config-key` des moniteurs (`mgr/cephadm/ssh_identity_key`) : lisible par toute entité qui a le droit de lire ce magasin (`client.admin`) et par le mgr. La clé de `client.admin` est dans `/etc/ceph/ceph.client.admin.keyring` (root, 600) sur chaque nœud `_admin`, et dans la base des moniteurs. Aucune des deux ne doit quitter le cluster.
6. Observations :
   ```
   [root@ceph01 ~]# ceph -s
     cluster:
       id:     <FSID>
       health: HEALTH_WARN
               OSD count 0 < osd_pool_default_size 3
     services:
       mon: 1 daemons, quorum ceph01 (age 2m)
       mgr: ceph01.xxxxxx(active, since 1m)
       osd: 0 osds: 0 up, 0 in
   [root@ceph01 ~]# ceph config get mgr container_image
   quay.io/ceph/ceph@sha256:<empreinte>
   ```
   `HEALTH_WARN` : aucun OSD, donc impossible de satisfaire `osd_pool_default_size 3` ; normal avant E04. L'image : cephadm remplace l'étiquette par son **empreinte** (`mgr/cephadm/use_repo_digest`, actif par défaut) : même si quelqu'un repoussait une autre image sous l'étiquette `v20.2.3`, les nœuds tireraient la même.

*C. Les autres nœuds.*

7. Inventaire : [`group_vars/env_m08/ceph.yml`](fichiers/M08-E03/ansible/inventories/lab/group_vars/env_m08/ceph.yml) (`ceph_fsid`, `ceph_image`), [`group_vars/role_ceph/ceph_noeud.yml`](fichiers/M08-E03/ansible/inventories/lab/group_vars/role_ceph/ceph_noeud.yml) (`ceph_noeud_cle_orchestrateur` = contenu de `ceph cephadm get-pub-key`). Puis `uv run ansible-playbook playbooks/ceph-noeuds.yml --tags ceph_noeud_orchestrateur`. Sur `ceph02` : la clé est dans `/var/lib/cephadm/.ssh/authorized_keys`, pas dans `/root/.ssh/authorized_keys` (qui n'existe peut-être pas).
8. Spécifications : [`specs/mon.yaml`](fichiers/M08-E03/ceph/specs/mon.yaml), [`specs/mgr.yaml`](fichiers/M08-E03/ceph/specs/mgr.yaml), [`specs/hosts.yaml`](fichiers/M08-E03/ceph/specs/hosts.yaml).
   ```
   [root@ceph01 ~]# ceph orch apply -i ceph/specs/mon.yaml --dry-run
   [root@ceph01 ~]# ceph orch apply -i ceph/specs/mon.yaml
   [root@ceph01 ~]# ceph orch apply -i ceph/specs/mgr.yaml
   [root@ceph01 ~]# ceph orch apply -i ceph/specs/hosts.yaml
   Added host 'ceph01' with addr '10.10.30.51'
   Added host 'ceph02' with addr '10.10.30.52'
   Added host 'ceph03' with addr '10.10.30.53'
   [root@ceph01 ~]# ceph -W cephadm
   ```
   Ordre : `mon` et `mgr` **d'abord**. À l'amorçage, le service `mon` a un placement par défaut (jusqu'à 5 moniteurs sur les hôtes du réseau public) : si les hôtes arrivent avant la spécification, cephadm commence à placer des moniteurs selon ce défaut, puis les déplace. Avec les placements par étiquette en place, l'ajout des hôtes étiquetés déclenche directement le bon déploiement. La spécification de `ceph01` (déjà présent) met à jour son adresse et ses étiquettes sans rien recréer.
9. Vérifications :
   ```
   [root@ceph01 ~]# ceph mon dump
   0: [v2:10.10.30.51:3300/0,v1:10.10.30.51:6789/0] mon.ceph01
   1: [v2:10.10.30.52:3300/0,v1:10.10.30.52:6789/0] mon.ceph02
   2: [v2:10.10.30.53:3300/0,v1:10.10.30.53:6789/0] mon.ceph03
   [root@ceph01 ~]# ceph orch host ls
   HOST    ADDR         LABELS              STATUS
   ceph01  10.10.30.51  _admin,mon,mgr,osd
   ceph02  10.10.30.52  _admin,mon,mgr,osd
   ceph03  10.10.30.53  _admin,mon,mgr,osd
   [root@ceph01 ~]# ceph orch ls --export
   ```
   L'export redonne les spécifications, avec les services créés par l'amorçage (`crash`, placement `*`). Ce qui n'est pas dans `plateforme/ceph` (le service `crash`) peut y être ajouté pour que le dépôt décrive **tout** (M08-E23).
10. `ceph mgr fail` : le gestionnaire en attente devient actif en quelques secondes ; `ceph mgr services` donne une nouvelle URL du tableau de bord (sur l'autre nœud). D'où la remarque de l'introduction : l'URL du tableau de bord suit le mgr actif (le service `mgmt-gateway` de Tentacle, ou un répartiteur, donne une adresse stable : palier 3).

*D. Le tableau de bord et les secrets.*

11. Tunnel : `ssh -L 8443:10.10.30.51:8443 admin@adm01` (le bastion autorise le transfert TCP, M04-E11), puis `https://localhost:8443`. Le navigateur refuse le certificat auto-signé : écart noté, à corriger au palier 3 (certificat step-ca).
12. Mot de passe :
    ```
    admin@adm01:~$ (umask 077; openssl rand -base64 24 > ~/.config/workbook/ceph-dashboard.pass)
    admin@adm01:~$ ssh ceph01 'sudo ceph dashboard ac-user-set-password admin -i -' < ~/.config/workbook/ceph-dashboard.pass
    admin@adm01:~$ cd ~/src/ansible && { printf 'vault_ceph_dashboard_admin_mdp: "'; cat ~/.config/workbook/ceph-dashboard.pass | tr -d '\n'; printf '"\n'; } \
        | uv run ansible-vault encrypt --encrypt-vault-id lab --output inventories/lab/group_vars/env_m08/vault-lab.yml -
    ```
    Le fichier `group_vars/env_m08/vault-lab.yml` est entièrement chiffré sous l'identité `lab` ([modèle](fichiers/M08-E03/ansible/inventories/lab/group_vars/env_m08/vault-lab.yml.exemple)). Si la politique de mots de passe du tableau de bord refuse le mot de passe généré (longueur, classes de caractères), `--force-password` existe : préfère générer un mot de passe conforme. Registre des secrets : `client.admin` (nœuds `_admin`, base des moniteurs ; détenteurs : équipe Plateforme), clé SSH de l'orchestrateur (`config-key` ; rotation : `ceph cephadm generate-key` puis redéploiement de la clé publique), mot de passe du tableau de bord (Vault `lab`, fichier 600 sur `adm01`).

Le check vérifie le quorum et les adresses des moniteurs, les gestionnaires, les réseaux, la configuration mémoire et le verrou des pools, les versions et l'image, les hôtes et leurs étiquettes, les placements, l'absence de pile de supervision, la clé de l'orchestrateur sur chaque nœud (et son absence chez root), les fichiers des nœuds `_admin`, le fsid de l'inventaire, le mot de passe rangé, le code sur `main`.

**Explications**

- **Ce que fait l'amorçage.** Il crée le premier moniteur (et donc la carte des moniteurs, le fsid, les clés `mon.` et `client.admin`), le premier gestionnaire, active le module `cephadm`, génère la clé SSH du cluster, pose l'étiquette `_admin` sur l'hôte, applique les services par défaut (`crash`, et sans `--skip-monitoring-stack` : `ceph-exporter`, Prometheus, Grafana, Alertmanager, node-exporter), active le tableau de bord. Tout le reste passe par l'orchestrateur.
- **La configuration initiale.** Les options de `--config` sont « assimilées » : versées dans la base de configuration des moniteurs, puis le `ceph.conf` local est réduit au minimum (fsid, moniteurs). C'est pourquoi on les retrouve dans `ceph config dump` et nulle part ailleurs. La ligne `osd_memory_target_autotune = false` n'est pas décorative : sans elle, cephadm activerait le réglage automatique et écrirait des cibles **par hôte** qui l'emporteraient sur notre 1 Gio (E04).
- **Déclaratif.** Une spécification décrit un état ; cephadm le maintient. Si un moniteur disparaît (nœud détruit), cephadm en redéploie un sur un hôte étiqueté `mon` disponible. C'est aussi pourquoi on ne « supprime » pas un démon à la main : on change la spécification (ou on étiquette `_no_schedule`).
- **`_admin` sur les trois nœuds.** Les vérifications du workbook, l'astreinte et les pannes du palier 4 (perte de `ceph01`) ont besoin d'un `ceph` utilisable ailleurs que sur `ceph01`. Le prix : le trousseau `client.admin` sur trois machines au lieu d'une. C'est un compromis à écrire dans la politique de stockage (E33).

**Alternatives**

- **`--apply-spec`** : l'amorçage applique en une fois un fichier contenant hôtes et services. Pratique pour un lab reconstruit souvent ; mais la clé SSH du cluster doit alors déjà être sur les autres nœuds (option `--ssh-private-key`/`--ssh-public-key` avec une clé générée à l'avance, donc une clé à gérer hors du cluster).
- **Amorcer avec la pile de supervision** : Prometheus, Grafana et Alertmanager clés en main ; environ 1,5 à 2 Go de mémoire de plus. Notre supervision passe par le module `prometheus` du mgr, interrogé par la supervision commune (M08-E24, puis M21).
- **`--allow-fqdn-hostname`** avec des noms complets : utile quand les noms courts ne sont pas uniques. Chez nous, ils le sont.

**Pièges classiques**

- Lancer `cephadm bootstrap` sans `--image` (étiquette flottante) ou avec `--image` **après** `bootstrap` (refus : option inconnue de la sous-commande).
- Relancer l'amorçage après un échec partiel sans nettoyer (`cephadm rm-cluster --fsid <FSID> --force`) : deux clusters sur un même hôte.
  > ⚠️ **Attention** : `cephadm rm-cluster` supprime **tout** le cluster désigné sur l'hôte, données des OSD comprises si on lui demande de les effacer. Avant E04, il n'y a rien à perdre ; après, c'est un geste de destruction.
- Ajouter les hôtes sans adresse (`ceph orch host add ceph02`) : cephadm résout le nom par le DNS. Ça marche… jusqu'au jour où le DNS ne répond plus ou renvoie autre chose.
- Oublier `--cluster-network` : tout passe par le réseau public, sans erreur ni alerte. On ne s'en aperçoit qu'en regardant les compteurs des cartes (ou `ceph osd dump` : adresses `cluster_addr`).
- Le mot de passe du tableau de bord passé en argument (`--initial-dashboard-password`, ou `echo motdepasse | …` tapé au clavier : il reste dans l'historique du shell).
- Un nœud dont le temps dérive (chrony en panne) : `MON_CLOCK_SKEW`, puis élections répétées (M08-E38).

**En production chez MédiSphère**

L'amorçage se fait une fois par cluster, à partir d'un dépôt relu, avec une fiche de changement. Les spécifications s'appliquent par le pipeline (M08-E23) et `ceph orch ls --export` est comparé au dépôt chaque nuit (dérive). Le tableau de bord est derrière la passerelle de gestion (`mgmt-gateway`) ou un répartiteur, en HTTPS avec un certificat de la PKI et une authentification centrale (OIDC, M24). Le trousseau `client.admin` n'est plus utilisé au quotidien : chaque personne et chaque outil a son identité cephx et ses droits (M08-E13, E27).

---

### M08-E04 — Les OSD : spécifications et classes de disques

**Solution**

1. Inventaire :
   ```
   [root@ceph01 ~]# ceph orch device ls --wide
   HOST    PATH      TYPE  DEVICE ID                        SIZE  AVAILABLE  REFRESHED  REJECT REASONS
   ceph01  /dev/sdb  ssd   QEMU_QEMU_HARDDISK_ceph01-ssd1   64.0G  Yes        …
   ceph01  /dev/sdc  ssd   QEMU_QEMU_HARDDISK_ceph01-ssd2   64.0G  Yes        …
   ceph01  /dev/sdd  hdd   QEMU_QEMU_HARDDISK_ceph01-hdd1   64.0G  Yes        …
   …
   ```
   Le disque système n'apparaît pas comme disponible (partitions, système de fichiers, LVM). `cephadm ceph-volume inventory` donne la même vue, côté hôte, avec les raisons de refus. Les numéros de série posés par OpenTofu forment l'identifiant du périphérique.
2. [`ceph/specs/osd.yaml`](fichiers/M08-E04/ceph/specs/osd.yaml) : deux services, `rotational: 0` / `1`, `size: '50G:100G'`, `crush_device_class` explicite, placement par l'étiquette `osd`.
   ```
   [root@ceph01 ~]# ceph orch apply -i ceph/specs/osd.yaml --dry-run
   WARNING! Dry-Runs are snapshots of a certain point in time and are bound
   to the current inventory setup. …
   OSDSPEC PREVIEWS
   +---------+------+--------+----------+----+-----+
   |SERVICE  |NAME  |HOST    |DATA      |DB  |WAL  |
   +---------+------+--------+----------+----+-----+
   |osd      |ssd   |ceph01  |/dev/sdb  |-   |-    |
   |osd      |ssd   |ceph01  |/dev/sdc  |-   |-    |
   |osd      |hdd   |ceph01  |/dev/sdd  |-   |-    |
   …
   ```
   Une prévisualisation vide au premier essai : l'orchestrateur n'a pas encore d'inventaire frais des hôtes ; elle se complète au rafraîchissement suivant (`ceph orch device ls --refresh`, puis relancer).
3. `ceph orch apply -i ceph/specs/osd.yaml`, puis `ceph orch ps --daemon-type osd` jusqu'à neuf `running` : quelques minutes (création des volumes LVM, préparation BlueStore, démarrage).
4. Classes :
   ```
   [root@ceph01 ~]# ceph osd tree
   ID  CLASS  WEIGHT   TYPE NAME        STATUS  REWEIGHT  PRI-AFF
   -1         0.52734  root default
   -3         0.17578      host ceph01
    0    ssd  0.06250          osd.0        up   1.00000  1.00000
    3    ssd  0.06250          osd.3        up   1.00000  1.00000
    6    hdd  0.06250          osd.6        up   1.00000  1.00000
   …
   [root@ceph01 ~]# ceph osd metadata 6 | grep -E '"(bluestore_bdev_rotational|devices|device_ids)"'
       "bluestore_bdev_rotational": "1",
       "device_ids": "sdd=QEMU_QEMU_HARDDISK_ceph01-hdd1",
       "devices": "sdd",
   ```
   La classe vient ici de la spécification (`crush_device_class`), qui l'impose à la création ; sans elle, l'OSD la déduit de la rotation au démarrage (`osd_class_update_on_start`). Pour voir une contradiction : comparer `bluestore_bdev_rotational` (métadonnées) et la classe (arbre) ; c'est ce que fait le check.
5. Sur un disque d'OSD :
   ```
   [root@ceph01 ~]# lsblk /dev/sdb
   NAME                                       MAJ:MIN  SIZE TYPE
   sdb                                          8:16    64G disk
   └─ceph--<uuid>-osd--block--<uuid>          253:2    64G lvm
   [root@ceph01 ~]# lvs -o lv_name,vg_name,lv_tags | grep -o 'ceph.osd_id=[0-9]*\|ceph.type=[a-z]*'
   ```
   Un groupe de volumes par disque, un volume logique « block » : BlueStore écrit directement dessus (données, et sa propre base de métadonnées RocksDB sur un petit système de fichiers interne, BlueFS). Pas de système de fichiers POSIX : pas de journal en double, pas de cache de pages en double, des sommes de contrôle et une compression à lui. Les étiquettes LVM (`ceph.osd_id`, `ceph.osd_fsid`, `ceph.cluster_fsid`…) permettent à `ceph-volume` de réactiver l'OSD au démarrage.
6. Mémoire :
   ```
   [root@ceph01 ~]# ceph config get osd.0 osd_memory_target
   1073741824
   [root@ceph01 ~]# ceph orch ps --daemon-type osd
   NAME   HOST    … MEM USE  MEM LIM  VERSION
   osd.0  ceph01  …  310M     1024M   20.2.3
   [root@ceph01 ~]# ceph config set osd.0 osd_memory_target_autotune true
   … (quelques minutes)
   [root@ceph01 ~]# ceph config dump | grep osd_memory_target
   osd                 basic     osd_memory_target            1073741824
   osd                 advanced  osd_memory_target_autotune   false
   osd      host:ceph01 basic    osd_memory_target            <valeur calculée>
   osd.0               advanced  osd_memory_target_autotune   true
   ```
   cephadm a calculé une cible pour l'hôte de `osd.0` (70 % de la mémoire de l'hôte, moins ce que consomment les démons non réglés, divisé par le nombre d'OSD réglés) et l'a écrite avec le masque `host:ceph01` : plus précis que `osd`, il l'emporte pour **tous** les OSD de `ceph01`, y compris ceux dont le réglage automatique est désactivé. La valeur exacte dépend de la mémoire vue par cephadm (à confirmer sur ton lab). Retour :
   ```
   [root@ceph01 ~]# ceph config rm osd.0 osd_memory_target_autotune
   [root@ceph01 ~]# ceph config rm osd/host:ceph01 osd_memory_target
   [root@ceph01 ~]# ceph config dump | grep osd_memory_target
   ```
7. Capacité :
   ```
   [root@ceph01 ~]# ceph df
   --- RAW STORAGE ---
   CLASS     SIZE    AVAIL    USED  RAW USED  %RAW USED
   hdd    192 GiB  192 GiB  …
   ssd    384 GiB  384 GiB  …
   TOTAL  576 GiB  …
   --- POOLS ---
   POOL  ID  PGS  STORED  OBJECTS  USED  %USED  MAX AVAIL
   .mgr   1    1   …                              ~ 180 GiB
   ```
   Le poids CRUSH vaut la taille du disque en Tio (64 Gio ≈ 0,0625). `MAX AVAIL` d'un pool tient compte de la réplication (÷ 3), du seuil de remplissage (`full_ratio` 95 %) et de l'OSD le **plus plein** du jeu de la règle : c'est une estimation prudente de ce qu'on peut encore écrire, pas l'espace libre brut.
8. MR, puis `ceph orch ls osd --export` : mêmes filtres et placement que le fichier (cephadm ajoute ses champs par défaut, comme `filter_logic: AND` et `objectstore: bluestore`).

Le check vérifie le nombre et l'état des OSD, leur répartition par hôte et par classe, la cohérence classe/rotation, les disques utilisés, les deux services et leurs filtres, l'absence de `all-available-devices`, la cible mémoire sans masque d'hôte, la santé et le fichier sur `main`.

**Explications**

- **Spécification par filtres.** Les noms `/dev/sdX` dépendent de l'ordre de découverte au démarrage ; un filtre « rotatif, entre 50 et 100 Go » désigne les mêmes disques quel que soit leur nom, et en désigne de nouveaux identiques si on en ajoute (c'est le comportement voulu pour une extension, M08-E18). Le filtre de taille protège contre l'imprévu : un disque de 8 Gio ajouté pour ZFS ou un essai ne deviendra jamais un OSD.
- **Deux services.** On pourra modifier l'un sans l'autre (chiffrer les OSD `ssd`, mettre `osd.hdd` en `unmanaged` pendant une intervention), et les compter séparément dans `ceph orch ls`.
- **Masques de configuration.** Ordre de précédence : `global` < type de démon (`osd`) < masque (`osd/host:ceph01`, `osd/class:ssd`) < démon (`osd.0`). Le réglage automatique travaille au niveau de l'hôte : il ne voit pas qu'on a décidé une valeur pour la classe `osd`.

**Alternatives**

- **`all: true`** ou `--all-available-devices` : le plus simple, et dangereux dès qu'un disque est ajouté pour un autre usage (ce que refuse le ticket). Si on l'utilise, le mettre aussitôt en `unmanaged: true`.
- **Désigner les disques par chemin** (`paths:` avec `/dev/disk/by-id/…`) : précis, mais une spécification par hôte, à modifier à chaque remplacement de disque.
- **Garder le réglage automatique** avec `mgr/cephadm/autotune_memory_target_ratio` réduit : adapté à des nœuds hyperconvergés où la mémoire libre varie (M09) ; sur des nœuds dédiés et petits, une valeur fixe est plus prévisible.

**Pièges classiques**

- Appliquer une spécification sans `service_id` : refusée par les versions récentes (mélange avec les OSD créés hors spécification).
- Un disque qui a servi (table de partitions, signature LVM) n'est pas « disponible » : `ceph orch device zap <hôte> <chemin> --force` l'efface.
  > ⚠️ **Attention** : `zap` détruit le contenu du disque désigné. Vérifie l'hôte **et** le chemin, et que ce n'est pas le disque d'un OSD en service (`ceph-volume lvm list`).
- Corriger une classe après coup avec `ceph osd crush set-device-class` sans `rm-device-class` d'abord : refusé (une classe existe déjà) ; et une classe changée déplace des données si des règles par classe existent.
- Croire `MEM USE` de `ceph orch ps` : c'est la mémoire du conteneur à l'instant ; la cible est un objectif pour les caches de BlueStore, pas une limite stricte (un OSD peut la dépasser pendant une récupération).

**En production chez MédiSphère**

Les OSD de disques durs ont leur base RocksDB/WAL sur un NVMe partagé (`db_devices`), au prix d'un domaine de panne commun (la perte du NVMe emporte tous les OSD qu'il sert). Les OSD sont chiffrés (`encrypted: true`, M08-E27). La cible mémoire est de 4 à 8 Gio par OSD selon le support. Chaque disque a son numéro de série dans NetBox, relié à sa baie et à son emplacement : la procédure de remplacement (RB-080) part de `ceph device ls` (identifiant du disque) et finit par la LED de localisation (`ceph device light on`).

---

### M08-E05 — Pools répliqués et groupes de placement

**Solution**

1. Calcul : 9 OSD × 100 PG visés par OSD ÷ 3 copies = 300, arrondi à la puissance de 2 la plus proche : 256 pour un pool qui aurait **toute** la capacité. Un pool vide et non `bulk` démarre bas (32 PG avec les valeurs par défaut de Tentacle, `osd_pool_default_pg_num`) et l'autoscaler le fait grossir quand ses données le justifient (écart d'un facteur 3 avec la cible avant d'agir).
   ```
   [root@ceph01 ~]# ceph osd pool autoscale-status
   POOL       SIZE  TARGET SIZE  RATE  RAW CAPACITY   RATIO  TARGET RATIO  EFFECTIVE RATIO  BIAS  PG_NUM  NEW PG_NUM  AUTOSCALE  BULK
   .mgr      …                    3.0        576.0G  0.0000                                1.0       1              on         False
   rbd-test     0                 3.0        576.0G  0.0000                                1.0      32              on         False
   ```
2. [`ceph/outils/pool-repliquee.sh`](fichiers/M08-E05/ceph/outils/pool-repliquee.sh) :
   ```
   [root@ceph01 ~]# bash ceph/outils/pool-repliquee.sh --simuler rbd-test rbd
   + pool rbd-test
         ceph osd pool create rbd-test
   ~ rbd-test size → 3
   …
   [root@ceph01 ~]# bash ceph/outils/pool-repliquee.sh rbd-test rbd
   [root@ceph01 ~]# bash ceph/outils/pool-repliquee.sh rbd-test rbd
   = pool rbd-test existe
   = rbd-test size 3
   = rbd-test min_size 2
   = rbd-test autoscaler actif
   = rbd-test application rbd
   ```
   En simulation, un pool absent n'a pas de valeurs : le script affiche toutes les corrections qu'il ferait.
3. `ceph pg ls-by-pool rbd-test` : pour chaque PG, `UP` (les OSD que CRUSH désigne maintenant) et `ACTING` (ceux qui servent réellement les E/S) ; ils diffèrent pendant un remappage (l'ancien jeu sert en attendant que le nouveau ait les données). Le premier OSD de `ACTING` est le **primaire** : il reçoit les E/S du client, ordonne les écritures, les envoie aux secondaires et n'acquitte qu'après leurs réponses ; il pilote aussi la récupération et le *scrub* du PG.
4. Objets :
   ```
   [root@ceph01 ~]# dd if=/dev/urandom of=/tmp/essai bs=1M count=4
   [root@ceph01 ~]# for i in 1 2 3; do rados -p rbd-test put essai-$i /tmp/essai; done
   [root@ceph01 ~]# ceph osd map rbd-test essai-1
   osdmap e57 pool 'rbd-test' (2) object 'essai-1' -> pg 2.5a3e0f1c (2.1c) -> up ([4,0,8], p4) acting ([4,0,8], p4)
   [root@ceph01 ~]# ceph osd find 4 | jq -r .host
   ```
   Le nom de l'objet est haché, le résultat modulo le nombre de PG donne le PG (`2.1c`), CRUSH donne la liste d'OSD. Les trois OSD sont toujours sur trois hôtes différents : `replicated_rule` choisit des **hôtes** distincts (`chooseleaf firstn 0 type host`), puis un OSD dans chacun. `ceph osd map` calcule le placement **même pour un objet qui n'existe pas** : c'est un calcul, pas une recherche.
5. `essai-pg` en `size 4` :
   ```
   [root@ceph01 ~]# ceph osd pool set essai-pg size 4
   [root@ceph01 ~]# ceph health detail
   HEALTH_WARN Degraded data redundancy: … pgs undersized
   [WRN] PG_DEGRADED: Degraded data redundancy: 32 pgs undersized
       pg 3.0 is stuck undersized for …, current state active+undersized, last acting [2,7,4]
   ```
   La règle exige des hôtes distincts ; il n'y en a que trois : la quatrième copie n'a nulle part où aller. Les PG restent `active` (3 ≥ `min_size` 2) mais `undersized`, et le resteront tant qu'il n'y aura pas un quatrième hôte. `ceph osd pool set essai-pg size 3` les ramène à `active+clean`.
6. `min_size 1` : le pool accepte d'écrire avec **une seule** copie. Scénario : deux nœuds tombent, les écritures continuent sur le dernier OSD de chaque PG ; ce disque meurt avant le retour des deux autres (ou les deux autres reviennent avec des données plus anciennes) : les écritures faites pendant ce temps n'existent nulle part ailleurs, elles sont perdues. Avec `min_size 2`, les E/S s'arrêtent : indisponibilité, mais aucune donnée acquittée n'est perdue.
7. Suppression :
   ```
   [root@ceph01 ~]# ceph osd pool delete essai-pg
   Error EPERM: WARNING: this will *PERMANENTLY DESTROY* all data stored in pool essai-pg.  If you are
   *ABSOLUTELY CERTAIN* that is what you want, pass the pool name *twice*, followed by
   --yes-i-really-really-mean-it.
   [root@ceph01 ~]# ceph osd pool delete essai-pg essai-pg --yes-i-really-really-mean-it
   Error EPERM: pool deletion is disabled; you must first set the mon_allow_pool_delete config option to true before you can destroy a pool
   [root@ceph01 ~]# ceph config set mon mon_allow_pool_delete true
   [root@ceph01 ~]# ceph osd pool delete essai-pg essai-pg --yes-i-really-really-mean-it
   pool 'essai-pg' removed
   [root@ceph01 ~]# ceph config set mon mon_allow_pool_delete false
   [root@ceph01 ~]# ceph config get mon mon_allow_pool_delete
   false
   ```
8. `for i in 1 2 3; do rados -p rbd-test rm essai-$i; done`, `rm /tmp/essai`, MR de l'outil, `ceph -s` : `HEALTH_OK`.

Le check vérifie le pool (taille, `min_size`, autoscaler, application, puissance de 2, règle par hôte), l'état des PG et la santé, la disparition de `essai-pg` et des objets d'essai, le verrou reposé, l'outil sur `main`.

**Explications**

- **Pourquoi des PG.** Suivre l'emplacement et l'état de chaque objet (des millions) coûterait trop cher ; on suit des PG (des centaines). La récupération, le *scrub*, le comptage des copies se font par PG. Trop peu de PG : répartition grossière (un OSD peut porter beaucoup plus que les autres) et récupération peu parallèle. Trop : mémoire et CPU des OSD, bavardage du *peering*. L'autoscaler vise ~100 PG (copies comprises) par OSD.
- **`rbd pool init`** déclare l'application `rbd` et crée les objets de service du pool (répertoire des images, etc.). `ceph osd pool application enable … rbd` seul suffit à faire taire l'alerte, mais pas à préparer le pool.
- **`size` / `min_size`.** `size` est le nombre de copies visées ; `min_size` le seuil en dessous duquel le PG cesse de servir les E/S. 3/2 est le défaut et la règle de MédiSphère : on tolère une panne sans interruption, deux sans perte.

**Alternatives**

- **Pools déclarés par Ansible** (module de commande ou collection communautaire) plutôt qu'un script : l'idempotence est la même ; le script vit dans `plateforme/ceph`, au plus près des spécifications, et se lance là où est `ceph`. Le choix définitif est celui du projet (M08-E23).
- **`pg_num` fixé à la main** avec l'autoscaler en `warn` : utile pour des pools dont on connaît la taille finale et où l'on veut éviter tout mouvement imprévu ; la `target_size_ratio` ou le drapeau `bulk` donnent le même résultat en gardant l'autoscaler.

**Pièges classiques**

- `min_size 1` « pour que ça continue de marcher » pendant une panne : c'est échanger une indisponibilité contre un risque de perte de données. Si on le fait sciemment pour sortir d'une crise, on le remet à 2 juste après, et on l'écrit dans le post-mortem.
- Oublier de reposer `mon_allow_pool_delete` : le prochain `pool delete` (le mauvais pool, une faute de frappe, un script) passera sans filet.
- Créer un pool sans application : `POOL_APP_NOT_ENABLED` en permanence, qu'on finit par ignorer, et qui masque les vraies alertes.
- Confondre `ceph osd pool set … pg_num` et le nombre de PG réellement en place : la division est progressive (`pg_num_target`), suivie dans `ceph osd pool ls detail`.

**En production chez MédiSphère**

Un pool par usage et par équipe (M08-E31), créé par le code avec ses quotas, sa règle CRUSH par classe et sa `target_size_ratio` estimée. Les suppressions de pool passent par une fiche de changement, avec une sauvegarde vérifiée et une seconde personne ; le verrou `mon_allow_pool_delete` est surveillé (alerte s'il reste à `true` plus d'une heure).

---

### M08-E06 — RBD : images, snapshots et clones

**Solution**

*A. Le client.*

1. [`infra/envs/ceph/cephcli01.tf`](fichiers/M08-E06/infra/envs/ceph/cephcli01.tf) : module `vm-noeud`, famille `debian13`, une carte `vstopub` en 9000 avec passerelle, étiquettes `env-m08`, `role-ceph-client`. Plan : 7 ressources (NetBox, VM, DNS).
2. Utilisateur :
   ```
   [root@ceph01 ~]# ceph auth get-or-create client.rbd-test mon 'profile rbd' osd 'profile rbd pool=rbd-test' >/dev/null
   [root@ceph01 ~]# ceph auth get client.rbd-test
   [client.rbd-test]
           key = AQ…==
           caps mon = "profile rbd"
           caps osd = "profile rbd pool=rbd-test"
   ```
   `profile rbd` côté moniteur : lire les cartes (pour savoir où sont les OSD) et pouvoir **mettre sur liste de blocage** (*blocklist*) un autre client qui détenait le verrou exclusif d'une image (reprise après le crash d'une VM). Côté OSD avec `pool=rbd-test` : lire et écrire les objets d'images RBD du seul pool `rbd-test`, et les objets de service nécessaires (en lecture sur les pools parents en cas de clone inter-pool). Rangement dans Vault sans copie en clair : le fichier entier est produit chiffré, la clé ne passe que par un tube.
   ```
   admin@adm01:~/src/ansible$ { printf 'vault_ceph_cle_rbd_test: "'; ssh ceph01 'sudo ceph auth get-key client.rbd-test'; printf '"\n'; } \
       | uv run ansible-vault encrypt --encrypt-vault-id lab \
           --output inventories/lab/group_vars/role_ceph_client/vault-lab.yml -
   admin@adm01:~/src/ansible$ head -n 1 inventories/lab/group_vars/role_ceph_client/vault-lab.yml
   $ANSIBLE_VAULT;1.2;AES256;lab
   ```
   (`-` : lire l'entrée standard ; [modèle du contenu](fichiers/M08-E06/ansible/inventories/lab/group_vars/role_ceph_client/vault-lab.yml.exemple).) Pour l'ajouter plus tard à un fichier existant : `uv run ansible-vault edit …`.
3. Configuration minimale :
   ```
   [root@ceph01 ~]# ceph config generate-minimal-conf
   # minimal ceph.conf for <FSID>
   [global]
           fsid = <FSID>
           mon_host = [v2:10.10.30.51:3300/0,v1:10.10.30.51:6789/0] [v2:10.10.30.52:3300/0,v1:10.10.30.52:6789/0] [v2:10.10.30.53:3300/0,v1:10.10.30.53:6789/0]
   ```
   Rôle [`ceph_client`](fichiers/M08-E06/ansible/roles/ceph_client/) (modèle `ceph.conf.j2` qui produit exactement cette forme, un trousseau par client en 600, refus de `client.admin`, `rbdmap`, `fstab` en `noauto`), [`group_vars/role_ceph_client/ceph_client.yml`](fichiers/M08-E06/ansible/inventories/lab/group_vars/role_ceph_client/ceph_client.yml), [`group_vars/env_m08/ceph.yml`](fichiers/M08-E06/ansible/inventories/lab/group_vars/env_m08/ceph.yml) (ajout de `ceph_moniteurs`), [`playbooks/ceph-clients.yml`](fichiers/M08-E06/ansible/playbooks/ceph-clients.yml), [`molecule/ceph_client/`](fichiers/M08-E06/ansible/molecule/ceph_client/). Avant la création de l'image (étape 5), laisse `ceph_client_rbdmap` et `ceph_client_montages` vides, ou applique avec `--skip-tags` : `rbdmap` ne peut pas mapper une image qui n'existe pas.
4. Droits :
   ```
   root@cephcli01:~# rbd --id rbd-test ls rbd-test
   root@cephcli01:~# rados --id rbd-test -p .mgr ls
   error listing objects: (1) Operation not permitted
   root@cephcli01:~# ceph --id rbd-test osd pool create interdit
   Error EACCES: access denied
   ```
   `ceph --id rbd-test -s` : le profil rbd donne la lecture des cartes au moniteur ; selon les versions, l'état s'affiche en entier ou partiellement (la partie servie par le gestionnaire exige des droits `mgr` que le client n'a pas). À noter tel que ton lab le montre.

*B. Une image.*

5. ```
   root@cephcli01:~# rbd --id rbd-test create rbd-test/disque01 --size 10G
   root@cephcli01:~# rbd --id rbd-test info rbd-test/disque01
   rbd image 'disque01':
           size 10 GiB in 2560 objects
           order 22 (4 MiB objects)
           features: layering, exclusive-lock, object-map, fast-diff, deep-flatten
   root@cephcli01:~# rbd --id rbd-test du rbd-test/disque01
   NAME      PROVISIONED  USED
   disque01       10 GiB   0 B
   ```
   Objets de 4 Mio (`order 22`), allocation à la demande : rien n'est écrit tant que le client n'écrit pas. Les fonctionnalités sont celles par défaut du client (18.2), toutes prises en charge par le `krbd` du noyau 6.12 de Debian 13.
6. ```
   root@cephcli01:~# rbd --id rbd-test device map rbd-test/disque01
   /dev/rbd0
   root@cephcli01:~# mkfs.xfs /dev/rbd0 && mkdir -p /mnt/disque01 && mount /dev/rbd0 /mnt/disque01
   root@cephcli01:~# cp -a /usr/share/doc /mnt/disque01/ && dd if=/dev/urandom of=/mnt/disque01/bloc bs=1M count=300
   root@cephcli01:~# (cd /mnt/disque01 && find . -type f -exec sha256sum {} + | sort > /root/disque01.sha256)
   root@cephcli01:~# rbd --id rbd-test du rbd-test/disque01
   ```
   `rbd du` : environ ce qui a été écrit (plus les métadonnées XFS) ; `ceph df` : `STORED` augmente d'autant, `USED` (brut) de **trois fois** autant (réplication).
7. Rôle avec `ceph_client_rbdmap` et `ceph_client_montages` remplis, `uv run ansible-playbook playbooks/ceph-clients.yml`, puis `sudo reboot`. Au retour, `findmnt /mnt/disque01` et `sha256sum -c /root/disque01.sha256`. Sans `noauto`, le générateur de `fstab` de systemd crée une unité de montage attendue au démarrage, **avant** que `rbdmap` ait mappé l'image : échec, et selon les options, démarrage en mode de secours. `rbdmap` monte lui-même les entrées `fstab` des images qu'il vient de mapper.

*C. Instantanés et clones.*

8. ```
   root@cephcli01:~# rbd --id rbd-test snap create rbd-test/disque01@avant-maj
   root@cephcli01:~# rm -rf /mnt/disque01/doc && echo test > /mnt/disque01/nouveau
   root@cephcli01:~# umount /mnt/disque01 && rbd --id rbd-test device unmap /dev/rbd0
   root@cephcli01:~# rbd --id rbd-test snap rollback rbd-test/disque01@avant-maj
   Rolling back to snapshot: 100% complete...done.
   root@cephcli01:~# systemctl reload rbdmap        # remappe et remonte
   root@cephcli01:~# cd /mnt/disque01 && sha256sum -c --quiet /root/disque01.sha256 && echo identique
   ```
   Avant le retour arrière, il faut **démonter et démapper** : le retour réécrit les objets de l'image sous le système de fichiers ; un XFS monté garderait en mémoire une vision qui ne correspond plus au disque (corruption). Pour un instantané **cohérent** d'un système de fichiers en service, on le fige d'abord (`fsfreeze -f`, ou l'option `--quiesce` du mappage) ; ici l'instantané a été pris système monté, cohérent « comme après une coupure de courant » (XFS rejoue son journal).
9. ```
   root@cephcli01:~# rbd --id rbd-test snap protect rbd-test/disque01@avant-maj
   root@cephcli01:~# rbd --id rbd-test clone rbd-test/disque01@avant-maj rbd-test/disque01-clone
   root@cephcli01:~# rbd --id rbd-test info rbd-test/disque01-clone | grep parent
           parent: rbd-test/disque01@avant-maj
   root@cephcli01:~# rbd --id rbd-test children rbd-test/disque01@avant-maj
   rbd-test/disque01-clone
   root@cephcli01:~# rbd --id rbd-test du rbd-test/disque01-clone
   NAME            PROVISIONED  USED
   disque01-clone       10 GiB   0 B
   root@cephcli01:~# rbd --id rbd-test device map rbd-test/disque01-clone
   /dev/rbd1
   root@cephcli01:~# mkdir -p /mnt/clone && mount /dev/rbd1 /mnt/clone
   mount: /mnt/clone: wrong fs type, bad option, bad superblock on /dev/rbd1 … 
   root@cephcli01:~# dmesg | tail -n 1
   XFS (rbd1): Filesystem has duplicate UUID … - can't mount
   root@cephcli01:~# mount -o nouuid /dev/rbd1 /mnt/clone && echo ecrit > /mnt/clone/fichier-du-clone
   root@cephcli01:~# umount /mnt/clone && rbd --id rbd-test device unmap /dev/rbd1
   ```
   Le clone n'occupe rien : il lit chez son parent tout ce qu'il n'a pas réécrit (copie sur écriture). XFS refuse deux systèmes de fichiers de même UUID montés en même temps ; `nouuid` le permet ponctuellement, `xfs_admin -U generate /dev/rbd1` (démonté) donne au clone une identité propre si on le garde.
10. ```
    root@cephcli01:~# rbd --id rbd-test flatten rbd-test/disque01-clone
    Image flatten: 100% complete...done.
    root@cephcli01:~# rbd --id rbd-test info rbd-test/disque01-clone | grep -c parent
    0
    root@cephcli01:~# rbd --id rbd-test du rbd-test/disque01-clone
    ```
    Après aplatissement, le clone a recopié chez lui tout ce qu'il lisait chez son parent : il n'a plus de lien, il occupe autant que les données de l'instantané. On aplatit un clone qui doit vivre longtemps pour pouvoir supprimer (ou faire évoluer) son parent, et pour qu'une panne ou une erreur sur le parent ne le touche pas. L'instantané reste protégé (`rbd snap ls` : `protected: true`) : il ne peut plus être supprimé par erreur.
11. MR (rôle, VM, clé chiffrée), registre des secrets : `client.rbd-test` (Vault `lab`, trousseau sur `cephcli01` ; rotation : nouvelle clé pour le client, puis mise à jour du Vault et du trousseau par le rôle ; procédure écrite en M08-E13).

Le check vérifie la VM et son nom, les droits exacts de `client.rbd-test`, le trousseau du client (et l'absence de `client.admin`), le `ceph.conf` du client, la lecture du pool avec les seuls droits du client, l'image et sa taille, l'instantané protégé, le clone aplati, le montage et sa persistance, le code sur `main` et la clé chiffrée.

**Explications**

- **Le client calcule seul.** `rbd` lit les cartes chez un moniteur (une fois), puis parle **directement** aux OSD primaires des objets de l'image. Les moniteurs ne voient passer aucune donnée. `/dev/rbd0` est un périphérique bloc du noyau (`krbd`) ; QEMU utilise plutôt `librbd` en espace utilisateur (M09, M10).
- **Le verrou exclusif.** Avec `exclusive-lock`, un seul client écrit à la fois dans une image ; un second mappage en écriture prend le verrou au premier (coopérativement). `object-map` et `fast-diff` permettent de savoir quels objets existent sans les lister : `rbd du`, les exports différentiels (E25) et l'aplatissement en profitent.
- **Clones et format 2.** Historiquement, un instantané doit être protégé avant d'être cloné. Les clones « v2 » (Mimic et suivantes) n'exigent plus cette protection si `require_min_compat_client` est au moins `mimic` ; la protection reste un garde-fou utile contre la suppression d'un instantané parent.

**Alternatives**

- **`rbd-nbd`** (espace utilisateur) au lieu de `krbd` : toutes les fonctionnalités de la bibliothèque, quelle que soit la version du noyau ; plus lent, et le processus doit survivre.
- **Client Tentacle sur Debian** : pas de paquets `download.ceph.com` pour trixie ; on pourrait utiliser `cephadm shell` sur un client (conteneur), au prix d'une dépendance à Podman. Le client 18.2 de Debian suffit (compatibilité des clients sur plusieurs versions).
- **Clé dans un fichier `secretfile`** et `keyring=` explicite : même résultat ; le nom par défaut `/etc/ceph/ceph.client.<id>.keyring` évite de le répéter.

**Pièges classiques**

- Copier `ceph.client.admin.keyring` sur le client « pour aller plus vite » : ce client devient administrateur de tout le cluster (le rôle le refuse).
- `profile rbd` sans `pool=` côté OSD : accès à **tous** les pools RBD.
- Retour arrière sur une image montée, ou deux clients qui montent le même XFS en écriture (question 10 d'E01) : corruption.
- Oublier de démapper avant de supprimer une image : `rbd rm` refuse (« image still has watchers ») ; `rbd status` montre qui la tient.
- Monter un clone sans `nouuid` et conclure qu'il est corrompu.
- Le pare-feu : depuis un autre VLAN que le 30, un client doit joindre les moniteurs (3300, 6789) **et** tous les OSD (6800-7568) : c'est la ligne de matrice des clients OpenStack et Kubernetes (M10, M16).

**En production chez MédiSphère**

Les clients RBD sont les hyperviseurs (Proxmox, OpenStack) et le pilote CSI de Kubernetes, chacun avec son identité cephx et ses pools. Les instantanés applicatifs passent par un gel du système de fichiers (agent QEMU, `fsfreeze`) ; les clones servent aux environnements de test de MédiAgenda (copie instantanée d'un volume de production anonymisé, aplatie au-delà d'une semaine). Les clés client tournent annuellement.

---

### M08-E07 — Lire l'état d'un cluster

**Solution**

1. Référence : `ceph -s` se lit par blocs — `cluster` (fsid, santé), `services` (moniteurs et quorum, gestionnaire actif et remplaçants, OSD up/in), `data` (pools, objets, occupation, états des PG), `io` (débit et opérations clientes, récupération). Le reste détaille un bloc.
2. ```
   [root@ceph01 ~]# ceph -w                                       # second terminal
   [root@ceph01 ~]# ceph orch daemon stop osd.4
   Scheduled to stop osd.4 on host 'ceph02'
   …  cluster [WRN] Health check failed: 1 osds down (OSD_DOWN)
   …  cluster [WRN] Health check failed: Degraded data redundancy: … objects degraded (…%), … pgs degraded (PG_DEGRADED)
   [root@ceph01 ~]# ceph pg stat
   … active+undersized+degraded, … active+clean
   ```
   L'OSD est `down` mais reste `in` ; ses PG sont `active+undersized+degraded` (2 copies sur 3, E/S servies). Au bout de `mon_osd_down_out_interval` (600 s par défaut), il passe `out` : CRUSH recalcule, d'autres OSD reçoivent ses PG, la récupération (*backfill*) recopie les données pour retrouver 3 copies. `ceph orch daemon start osd.4` : il revient, les données reviennent vers lui (mouvement inverse).
3. Avec `ceph osd set noout` posé avant : l'OSD reste `in` indéfiniment, aucune recopie ; `HEALTH_WARN` affiche aussi `OSDMAP_FLAGS: noout flag(s) set`. Après redémarrage et `active+clean`, `ceph osd unset noout`. Un drapeau oublié : la prochaine **vraie** panne ne sera jamais réparée automatiquement, la fenêtre à 2 copies dure jusqu'à ce que quelqu'un s'en aperçoive.
4. ```
   [root@ceph01 ~]# ceph osd out 7
   marked out osd.7.
   [root@ceph01 ~]# ceph -s
       pgs:     …  active+remapped+backfilling
       recovery: 45 MiB/s, 11 objects/s
   [root@ceph01 ~]# ceph osd in 7
   ```
   Aucune perte de redondance : l'OSD sorti sert encore ses données pendant qu'elles sont copiées ailleurs (`remapped`). L'aller-retour déplace environ la part de données de l'OSD (≈ 1/9 des données des pools concernés), deux fois.
5. Journaux : `ceph log last 30` (journal du cluster, tenu par les moniteurs), `ceph crash ls` (plantages collectés par le service `crash`), et sur l'hôte : les démons écrivent sur leur sortie standard, Podman la passe à **journald** ; `cephadm logs --name osd.4` est un raccourci de `journalctl -u ceph-<FSID>@osd.4`. Pas de fichier dans `/var/log/ceph/` sauf si `log_to_file` est activé (option `--log-to-file` à l'amorçage).
6. Fiche : [`medisphere/docs/stockage/lire-etat-ceph.md`](fichiers/M08-E07/medisphere/docs/stockage/lire-etat-ceph.md).
7. Retour à la référence : `ceph osd dump | grep flags` (aucun drapeau d'exploitation), `ceph osd tree` (tous `up`, `REWEIGHT 1.00000`), `ceph health detail` (rien, pas de `mutes`), `ceph crash ls-new` (vide, ou `ceph crash archive-all` après lecture).

Le check vérifie l'absence de drapeaux, les neuf OSD `up`/`in` avec leur poids, les démons OSD en fonctionnement, l'absence d'alertes en sourdine et de plantages non acquittés, `HEALTH_OK`, et le contenu de la fiche.

**Explications**

- **`down` et `out` sont deux choses.** `down` : l'OSD ne répond plus (constaté par ses pairs et les moniteurs). `out` : il ne compte plus pour le placement. Ceph sépare les deux pour ne pas recopier des centaines de Gio à chaque redémarrage.
- **`degraded` et `undersized`.** `undersized` : le PG a moins d'OSD que `size` dans son jeu. `degraded` : des objets ont moins de copies que prévu. Les deux disent « redondance réduite », pas « données perdues ». Les états graves sont ceux qui suppriment `active` (`inactive`, `incomplete`, `down`, `peering` qui dure) : plus d'E/S.

**Alternatives**

- **Tableau de bord** (« Overview » en Tentacle) : la même information, graphique ; utile en appui, mais la fiche d'astreinte doit marcher même quand le mgr (qui sert le tableau de bord) ne répond plus.
- **`ceph orch host maintenance enter`** pour une maintenance de nœud : pose les drapeaux nécessaires et arrête les démons de l'hôte proprement (vérifie d'abord que c'est sûr). Plus complet que `noout` à la main ; à connaître (RB-081).

**Pièges classiques**

- Arrêter un OSD avec `systemctl stop` sur l'hôte : cephadm ne le sait pas forcément, et `ceph orch ps` peut le montrer en erreur ; passer par `ceph orch daemon stop`.
- Mettre `noout` « pour être tranquille » pendant une investigation et partir sans le lever.
- `ceph health mute` sans durée : l'alerte disparaît pour toujours.
- Paniquer devant `HEALTH_WARN` : la plupart des avertissements se lisent sereinement. `HEALTH_ERR` et les PG inactifs, eux, sont des incidents.

**En production chez MédiSphère**

La fiche est liée depuis chaque alerte de stockage (M08-E24) ; elle est relue après chaque incident (post-mortem). Les drapeaux d'exploitation posés depuis plus d'une heure déclenchent une alerte. Les gestes autorisés sans l'équipe sont limités à la lecture, `noout` pour une maintenance planifiée, et le redémarrage d'un démon.

---

### M08-E08 — ZFS : le stockage local en rappel

**Solution**

1. [`infra/envs/ceph/cephcli01.tf`](fichiers/M08-E08/infra/envs/ceph/cephcli01.tf) : `disques_donnees` avec deux disques de 8 Gio (`cephcli01-zfs1`, `cephcli01-zfs2`). Le plan annonce `~ update in-place` sur `module.cephcli01.proxmox_virtual_environment_vm.vm` (et sur la VM NetBox, dont la taille de disque change) : aucune recréation. Dans la VM :
   ```
   root@cephcli01:~# ls -l /dev/disk/by-id/ | grep zfs
   scsi-0QEMU_QEMU_HARDDISK_cephcli01-zfs1 -> ../../sdb
   scsi-0QEMU_QEMU_HARDDISK_cephcli01-zfs2 -> ../../sdc
   ```
2. [`playbooks/zfs-local.yml`](fichiers/M08-E08/ansible/playbooks/zfs-local.yml). ZFS est sous licence CDDL, jugée incompatible avec la GPL du noyau : Debian ne distribue pas de module compilé dans `main`, mais les sources dans `contrib`, compilées **sur la machine** par DKMS. À chaque nouveau noyau, DKMS recompile le module (en-têtes du nouveau noyau nécessaires : d'où `linux-headers-amd64`) ; si la compilation échoue (noyau trop récent pour la version de ZFS), le pool ne s'importe plus au redémarrage : on garde l'ancien noyau dans le menu de démarrage.
3. ```
   root@cephcli01:~# zpool create -o ashift=12 zlocal mirror \
       /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cephcli01-zfs1 \
       /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cephcli01-zfs2
   root@cephcli01:~# zpool status zlocal
     pool: zlocal
    state: ONLINE
   config:
           NAME                                         STATE     READ WRITE CKSUM
           zlocal                                       ONLINE       0     0     0
             mirror-0                                   ONLINE       0     0     0
               scsi-0QEMU_QEMU_HARDDISK_cephcli01-zfs1  ONLINE       0     0     0
               scsi-0QEMU_QEMU_HARDDISK_cephcli01-zfs2  ONLINE       0     0     0
   ```
   `by-id` : le nom suit le disque, pas l'ordre de découverte. `ashift=12` : blocs de 4 Kio (2¹²), adaptés aux SSD et disques modernes ; fixé à la création de chaque groupe de disques (*vdev*), immuable ensuite ; trop petit, chaque écriture devient une lecture-modification-écriture sur le support.
4. ```
   root@cephcli01:~# zfs create -o compression=zstd -o atime=off zlocal/donnees
   root@cephcli01:~# cp -a /var/log /usr/share/doc /zlocal/donnees/ && dd if=/dev/urandom of=/zlocal/donnees/alea bs=1M count=200
   root@cephcli01:~# zfs get compressratio,used,logicalused zlocal/donnees
   ```
   Les journaux et la documentation se compressent bien (rapport 3 à 5), les données aléatoires pas du tout ; ZFS n'essaie pas indéfiniment : un bloc qui ne gagne pas assez est stocké tel quel.
5. ```
   root@cephcli01:~# zfs snapshot zlocal/donnees@j1
   root@cephcli01:~# rm -rf /zlocal/donnees/doc && echo nouveau > /zlocal/donnees/nouveau
   root@cephcli01:~# zfs diff zlocal/donnees@j1
   -       /zlocal/donnees/doc
   …
   +       /zlocal/donnees/nouveau
   root@cephcli01:~# cp /zlocal/donnees/.zfs/snapshot/j1/doc/bash/README* /tmp/
   root@cephcli01:~# zfs rollback zlocal/donnees@j1
   root@cephcli01:~# echo jour2 > /zlocal/donnees/jour2 && zfs snapshot zlocal/donnees@j2
   ```
6. ```
   root@cephcli01:~# zfs send -nv zlocal/donnees@j1
   total estimated size is 412M
   root@cephcli01:~# zfs send zlocal/donnees@j1 | zfs receive zlocal/copie
   root@cephcli01:~# zfs send -nv -i @j1 zlocal/donnees@j2
   total estimated size is 13.5K
   root@cephcli01:~# zfs send -i @j1 zlocal/donnees@j2 | zfs receive zlocal/copie
   root@cephcli01:~# zfs list -t snapshot -r zlocal
   ```
   Le flux incrémental ne contient que les blocs changés entre les deux instantanés : des Kio au lieu de centaines de Mio. Pour une sauvegarde hors site, on enverrait le flux par SSH vers une autre machine (`zfs send … | ssh pbs-ou-autre zfs receive …`), éventuellement chiffré de bout en bout (`zfs send --raw` d'un dataset chiffré : la cible n'a jamais la clé).
7. ```
   root@cephcli01:~# zpool offline zlocal scsi-0QEMU_QEMU_HARDDISK_cephcli01-zfs2
   root@cephcli01:~# dd if=/dev/urandom of=/zlocal/donnees/pendant bs=1M count=50
   root@cephcli01:~# zpool status zlocal | grep -E 'state|zfs2'
    state: DEGRADED
               scsi-0QEMU_QEMU_HARDDISK_cephcli01-zfs2  OFFLINE      0     0     0
   root@cephcli01:~# zpool online zlocal scsi-0QEMU_QEMU_HARDDISK_cephcli01-zfs2
   root@cephcli01:~# zpool status zlocal | grep scan
     scan: resilvered 50.3M in 00:00:01 with 0 errors on …
   root@cephcli01:~# zpool scrub zlocal && sleep 30 && zpool status zlocal | grep scan
     scan: scrub repaired 0B in 00:00:12 with 0 errors on …
   ```
   La resynchronisation ne recopie que ce qui a été écrit pendant l'absence (ZFS sait quels blocs ont changé depuis, par leur numéro de transaction) : 50 Mio, pas 8 Gio. C'est l'équivalent de ce que fait Ceph pour un OSD revenu avant de passer `out` (récupération par journal des PG plutôt que *backfill* complet).
8. `systemctl is-enabled zfs-import-cache zfs-mount zfs.target` : `enabled` (activés par le paquet). Après `reboot`, `zpool status zlocal` : `ONLINE`.
9. Comparaison :

   | Mécanisme | ZFS (une machine) | Ceph (le cluster) |
   |---|---|---|
   | Redondance | miroir ou RAID-Z entre disques d'un hôte | réplication ou codes d'effacement entre **hôtes** |
   | Corruption | somme de contrôle de chaque bloc, réparation depuis l'autre copie ; `scrub` | sommes de contrôle de BlueStore à la lecture ; `scrub` (métadonnées) et `deep-scrub` (données) entre copies |
   | Instantanés, clones | du dataset ou du volume, instantanés, clones, `promote` | de l'image RBD, de CephFS (dossier `.snap`), clones RBD, aplatissement |
   | Compression | par dataset (`lz4`, `zstd`) | par pool ou par OSD (BlueStore) |
   | Réplication à distance | `zfs send/receive` incrémental | `rbd export-diff`/`import-diff`, `rbd-mirror`, multisite RGW, `cephfs-mirror` |
   | Unité de panne tolérée | un disque (miroir), deux (RAID-Z2) ; **pas** l'hôte | un ou plusieurs hôtes (domaine de panne), selon la règle |
   | Extension | ajouter un vdev (pas de rééquilibrage des données existantes) ; agrandir chaque disque | ajouter des OSD ou des hôtes : rééquilibrage automatique |

Le check vérifie les disques de la VM et leur déclaration dans le code, le module chargé, l'état et la composition du pool (miroir, `by-id`, pas de périphérique RBD), un *scrub* sans erreur, la remontée au démarrage, la compression, les instantanés et la réception (au moins deux instantanés communs).

**Explications**

- **Copie sur écriture.** ZFS n'écrase jamais un bloc en place : il écrit ailleurs puis bascule le pointeur. Un instantané ne coûte rien à créer (on garde l'ancien pointeur), et une coupure de courant laisse toujours un état cohérent (pas de trou d'écriture, question 6 d'E01).
- **Pourquoi ce détour.** Ceph ne remplace pas ZFS partout : le disque système d'un nœud, les journaux, un serveur isolé gardent un stockage local. Et `pve01` en a peut-être un. Savoir lire un `zpool status` fait partie du métier.

**Alternatives**

- **mdadm + LVM + XFS** : la pile classique Linux ; pas de sommes de contrôle des données (corruption silencieuse non détectée), instantanés LVM coûteux. Plus simple, dans le noyau.
- **Btrfs** : sommes de contrôle et instantanés dans le noyau ; RAID 5/6 encore déconseillé.
- **ZFS de `trixie-backports`** (2.4) : plus récent, utile pour les nouveaux noyaux ; on préfère la version de la distribution pour un rappel.

**Pièges classiques**

- `zpool create … /dev/sdb /dev/sdc` sans le mot-clé `mirror` : un pool **sans redondance** (agrégat), la perte d'un disque perd tout.
- Désigner les disques par `/dev/sdX` : après un redémarrage où l'ordre change, `zpool import` s'en sort souvent, mais les messages et les remplacements deviennent trompeurs.
- `zfs receive -F` sans comprendre : il ramène la cible à l'instantané commun en jetant ce qui a été écrit depuis sur la cible.
- Un pool ZFS **sur** une image RBD (ou l'inverse) : deux couches de redondance et de copie sur écriture empilées, des performances et des modes de panne imprévisibles.
- Toucher au ZFS de `pve01` en pensant être sur `cephcli01` : vérifie toujours l'invite.

**En production chez MédiSphère**

ZFS sur les serveurs qui gardent du stockage local de valeur (sauvegardes locales, `pbs01` s'il était réinstallé), avec *scrub* mensuel planifié, alertes sur l'état des pools (ZED, l'agent d'événements de ZFS) et sur les erreurs, et réplication `zfs send` chiffrée hors site. Sur les nœuds Ceph, pas de ZFS : les disques sont à Ceph, le système sur un simple miroir.

---

### M08-E09 — Questions : architecture de Ceph

**Barème** : 2 points par question, total sur 24. Une réponse qui cite une observation du lab (sortie, mesure, message) vaut mieux qu'une réponse de cours.

**1. Chemin d'une écriture.** Le noyau de `cephcli01` (`krbd`) découpe l'écriture : 4 Kio à l'offset X tombent dans l'objet `rbd_data.<id>.<X ÷ 4 Mio>`. Le client connaît la carte des OSD et la carte CRUSH (lues au mappage auprès d'un moniteur, réseau public, port 3300) : il calcule le PG (hachage du nom de l'objet) puis la liste d'OSD (CRUSH), et envoie l'écriture **directement au primaire** (réseau public). Le primaire l'écrit (BlueStore, avec sa base RocksDB pour les métadonnées) et l'envoie en parallèle aux deux secondaires sur le **réseau cluster** ; quand les deux ont confirmé l'avoir rendue persistante, il acquitte au client. Les moniteurs ne sont **pas** sur le chemin : ils n'interviennent que si la carte change (OSD qui tombe, client qui se reconnecte).

**2. Moniteurs isolés, gestionnaire absent.** Sans quorum, aucune carte ne peut changer : un OSD qui tombe ne sera pas marqué `down`, un client qui démarre ne pourra pas s'authentifier ni lire la carte, les commandes `ceph` ne répondent plus. Mais les clients **déjà connectés** continuent leurs E/S vers les OSD tant que rien ne change (ils ont la carte) — jusqu'à ce que leurs tickets cephx expirent (de l'ordre de l'heure). Sans gestionnaire actif : les données restent servies, mais plus d'orchestrateur (`ceph orch`), plus de tableau de bord, plus de métriques, plus d'autoscaler ni de rééquilibrage, et `ceph -s` affiche des statistiques figées ; un remplaçant prend la main en quelques secondes (E03, étape 10).

**3. Réponse C.** Avec deux nœuds sur trois arrêtés, chaque PG n'a plus qu'un OSD vivant : 1 < `min_size` 2, les PG passent `undersized+degraded+peered` (inactifs) et les E/S **se bloquent** : le processus du client attend (état `D` dans `ps`), sans erreur, jusqu'au retour d'un nœud. A serait le comportement avec `min_size 1` (risque de perte, E05). B : Ceph ne renvoie pas d'erreur d'E/S dans ce cas ; les lectures aussi attendent, car un PG inactif ne sert rien. D n'existe pas. Et de toute façon, deux moniteurs sur trois sont tombés : plus de quorum.

**4. Pourquoi des PG.** Suivre chaque objet (des millions) coûterait trop cher en mémoire, en échanges et en calcul à chaque changement de topologie ; les PG regroupent les objets en quelques centaines d'unités de placement, de récupération et de *scrub*. Avec 2 PG pour tout un pool, toutes les données vivraient sur 2 × 3 = 6 OSD au plus, et la perte d'un OSD obligerait à recopier la moitié du pool par un seul flux. Avec 100 000 PG, chaque OSD en porterait des dizaines de milliers : mémoire, CPU, temps de *peering* après chaque changement, carte énorme. D'où la cible de ~100 par OSD et l'autoscaler.

**5. Mauvaise classe.** Sans `crush_device_class` dans la spécification, l'OSD prend la classe déduite de `rotational` : avec `ssd=1` sur le disque de `hdd-bulk`, il serait classé `ssd`. Rien ne le signalerait : le cluster serait `HEALTH_OK`. On s'en apercevrait au palier 2, quand une règle « classe ssd » enverrait des données rapides sur un disque dur (latence élevée sur certains PG, OSD lent dans `ceph osd perf`), ou en comparant les classes au matériel. Le check d'E04 compare justement la classe aux métadonnées de rotation : il ne détecterait **pas** cette erreur-là (les deux mentent ensemble) ; seul le code de l'infrastructure (`ssd = false` sur `hdd-bulk`) fait foi.

**6. Conteneurs.** Avantages : une seule image (donc une seule version, toutes dépendances comprises) pour tous les démons et tous les hôtes ; montée de version par remplacement d'image, démon par démon, sans gestionnaire de paquets (M08-E26) ; indépendance vis-à-vis de la distribution hôte (les dépendances sont dans l'image). Inconvénients : une couche de plus à diagnostiquer (journaux dans journald, `cephadm shell`, `podman`), dépendance à un registre d'images (à recopier en interne pour un site isolé), et une image volumineuse à tirer sur chaque nœud.

**7. Réponse B.** Le magasin `config-key` n'est pas chiffré pour ses lecteurs : toute entité dont les capacités permettent de le lire (`client.admin`, ou un client à qui l'on aurait donné `mon 'allow r'` trop large selon les versions) peut récupérer la clé privée, et cette clé ouvre une session `cephadm` (sudo) sur **tous** les nœuds. La version 20.2.4 corrige justement une faille où le magasin était lisible par n'importe quelle clé cephx (CVE-2026-50152, M08-E26). A est faux (le stockage est en clair pour qui a le droit de lire) ; C et D décrivent qui **utilise** la clé, pas qui peut la lire.

**8. Réglage automatique de la mémoire.** Il calcule une cible par hôte à partir de 70 % de la mémoire totale ; sur un nœud de 6 Go partagé avec un moniteur et un gestionnaire, la valeur obtenue peut dépasser ce que l'on veut réserver, et elle change avec ce que cephadm mesure. Nous voulons une valeur **décidée**, la même partout, inscrite dans le code (1 Gio). Il est un bon choix sur des nœuds dédiés et homogènes où les OSD peuvent prendre toute la mémoire disponible, avec un rapport ajusté (`autotune_memory_target_ratio`) sur des nœuds hyperconvergés.

**9. Client 18.2, cluster 20.2.** Pas de problème : Ceph garantit la compatibilité des clients de versions antérieures (protocole et fonctionnalités négociés à la connexion) ; le cluster peut exiger un minimum (`require_min_compat_client`), ici bien en dessous. Dans le client, la bibliothèque et la commande (`rbd`, `ceph`) dépendent du paquet ; le **chemin des données** de `/dev/rbd0` dépend du **noyau** (`krbd`, ici celui de Debian 13) : c'est lui qui doit gérer les fonctionnalités de l'image (`object-map`, `fast-diff`, `deep-flatten`, msgr2). Une fonctionnalité trop récente pour le noyau fait échouer le mappage (« image uses unsupported features »), M08-E39.

**10. Profils et vol de trousseau.** `profile rbd` (moniteur) : lire les cartes, et mettre sur liste de blocage un client qui tenait un verrou exclusif. `profile rbd pool=rbd-test` (OSD) : lire et écrire les images RBD du seul pool `rbd-test`. Un voleur du trousseau peut lire, modifier, supprimer toutes les images de `rbd-test` (y compris celles d'autres usages du même pool) et bloquer les clients légitimes ; rien en dehors. Avec `client.admin` : tout le cluster (supprimer les pools, lire la clé SSH de l'orchestrateur donc devenir root sur les nœuds, créer des clés). D'où un client par usage, et des pools ou des espaces de noms (*namespaces*) par équipe (M08-E31).

**11. Plus petites pannes.** ZFS en miroir sur une machine : **inaccessibles** dès que la machine s'arrête (alimentation, carte mère, noyau) ; **détruites** à la perte des deux disques (ou d'un incident qui touche la machine entière : incendie, contrôleur qui écrit n'importe quoi). Ceph 3 copies, `min_size` 2, domaine de panne hôte : **inaccessibles** (pour certains PG) à la perte de deux hôtes (ou de deux moniteurs : plus de quorum) ; **détruites** à la perte simultanée de trois disques portant les trois copies d'un même PG sur trois hôtes différents, ou des trois hôtes (ou de la salle : d'où la sauvegarde hors du cluster, M08-E25).

**12. Versions flottantes.** Scénario : le cluster est amorcé en 20.2.3 avec l'image `v20` ; deux mois plus tard sort 20.2.5 ; on ajoute `ceph04` (E18) ou on redéploie un démon après une panne : cephadm (si l'image n'avait pas été résolue en empreinte) ou un nœud tire `v20` = 20.2.5. Le cluster tourne en versions mélangées sans que personne l'ait décidé (`ceph versions` le montre). Côté paquets, `rpm-tentacle` et `dnf-automatic` font passer `cephadm` et `ceph-common` d'un nœud en 20.2.5 lors d'une mise à jour de sécurité nocturne, pas les autres ; un jour, `cephadm` d'une version tente de gérer des démons d'une autre. Et les étapes particulières de certaines versions (20.2.4 : CVE à corriger dans un ordre précis) sont sautées. Avec des versions épinglées partout, une montée de version est un changement décidé, relu, et testé (M08-E26).
