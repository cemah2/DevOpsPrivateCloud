# Module 10 — Palier 2 : Opérationnel

Le palier 1 a livré un OpenStack qui démarre : Keystone et ses projets, des images, des gabarits, un réseau externe et des IP flottantes. Mais tout repose sur des choix de démonstration : Glance range ses images sur le disque de `osctl01`, Nova écrit les disques des instances sur les disques locaux de deux calculs, il n'existe aucun volume persistant, les réseaux des projets ont une MTU de 1442, les instances sortent sur Internet sans contrôle, et personne en dehors de toi ne sait s'en servir. Ce palier traite les tickets d'une équipe qui ouvre un cloud à ses premiers clients internes : brancher le stockage sur Ceph, donner des volumes et des sauvegardes, intégrer le réseau externe au lab et au pare-feu, dimensionner les projets, offrir Heat, OpenTofu, des répartiteurs de charge et le tableau de bord, maîtriser les métadonnées, exploiter les calculs et la configuration Kolla au quotidien. Tu termines par une revue, le runbook d'accueil d'une équipe et des politiques d'accès plus fines que « admin ou membre ».

> **Rappels du module** (introduction) : la configuration d'OpenStack vit dans le projet `plateforme/openstack` et ne change que par MR ; aucune modification à la main dans `/etc/kolla` sur les nœuds ; tout nouveau flux passe par la matrice des flux de la bordure ; tout secret est en Vault (identité `critique`) et au registre des secrets. Les vérifications se lancent depuis `adm01`. Les ressources d'essai de ce palier portent le préfixe de leur exercice (`e10-…`, `e11-…`) : supprime-les après la vérification, les quotas et la mémoire des calculs sont comptés.

**Ordre conseillé** : E10 → E11 → E12 → E13 → E14 → E15 → E16 → E17 → E18 → E19 → E20 → E21 → E22 → E23. E10 conditionne tout le reste (stockage) ; E12 conditionne les accès par IP flottante de E14, E16 et E18 ; E13 précède E15 (quotas repris en code) et E22. E21 peut se faire à tout moment.
**Durée indicative du palier** : 32 à 38 heures.

**Faits communs du palier**

| Élément | Valeur |
|---|---|
| Projet Kolla | `plateforme/openstack`, cloné dans `~/src/openstack` sur `adm01` (projet `uv` avec Kolla-Ansible 22.x et ansible-core 2.20, E03) : `etc/kolla/globals.yml`, réglages ajoutés par sujet dans `etc/kolla/globals.d/<NN>-<sujet>.yml` (lus après `globals.yml`, par ordre alphabétique ; dans ce palier, `NN` = numéro de l'exercice), `etc/kolla/passwords.yml` (chiffré, identité `critique`), `etc/kolla/config/` (surcharges des services), `inventaire/multinode` ; identité Keystone en code : `playbooks/identite.yml` et `donnees/identite.yml` (E05) |
| Commande Kolla | depuis `~/src/openstack` : `uv run kolla-ansible <action> -i inventaire/multinode --configdir etc/kolla [-t <étiquettes>]` (identité Vault `critique` fournie par l'`ansible.cfg` du projet, E03). Dans ce palier, on l'abrège en `kolla-ansible <action> [-t …]` |
| Accès à l'API | `~/.config/openstack/clouds.yaml` sur `adm01` : `medisphere-admin` (compte `admin`, projet `admin`, domaine `Default`), `medisphere-plateforme` (`<MOI>`, projet `plateforme`), `medisphere-mediagenda-dev` (`julien.petit`, projet `mediagenda-dev`) (E04, E05) ; mots de passe dans `secure.yaml` (600). Les vérifications utilisent `medisphere-admin` (variable `WB_OS_CLOUD`) et, pour les objets d'un projet, `medisphere-mediagenda-dev` (variable `WB_OS_CLOUD_DEV`) |
| Client | `openstack` 10.x (`uv tool`). Greffons ajoutés dans ce palier : `python-heatclient` (E14), `python-octaviaclient` (E16), `osc-placement` (E13). Ajout : `uv tool install python-openstackclient --with <greffon> …` (avec `--reinstall` si uv refuse de modifier un outil déjà installé) |
| Nœuds | `osctl01` (10.10.50.51), `oscmp01` (.52), `oscmp02` (.53) ; compte `admin` + sudo ; conteneurs Docker (`sudo docker ps`) ; configuration générée dans `/etc/kolla/<service>/`, journaux dans `/var/log/kolla/<service>/` |
| Ceph | `ceph-par1` : MON 10.10.30.51-53 (VLAN 30, joints directement par les nœuds OpenStack sur `ens20`), pools `images`, `volumes`, `vms`, `backups`, clients `client.glance`, `client.cinder`, `client.cinder-backup`, `client.nova` (M08-E46). Commandes Ceph : `[admin@ceph01 ~]$ sudo cephadm shell -- ceph …` |
| Réseau externe | `ext-net` (flat, `physnet1`), sous-réseau 10.10.52.0/24, passerelle 10.10.52.1 (VIP de la bordure), pool 10.10.52.200-249, sans DHCP (E08) |
| Ressources du palier 1 | images `debian-13` et `rocky-10` (E06), gabarits `m1.petit`, `m1.moyen`, `m1.grand`, paire de clés `cle-adm01` (E07) ; dans le projet `plateforme` : réseau `reseau-plateforme` (172.16.10.0/24), sous-réseau `sous-reseau-plateforme`, routeur `routeur-plateforme`, groupe de sécurité `ssh-icmp-admin` (SSH et ICMP depuis MGMT) (E08) |
| Rôles (E05) | `equipe-plateforme` : `member` sur `plateforme`, `reader` sur les projets de MédiAgenda ; `equipe-mediagenda` : `member` sur `mediagenda-dev`, `reader` sur `mediagenda-prod`. L'administration du cloud passe par le compte `admin` du domaine `Default` ; les comptes de service vivent dans `Default` |
| Documentation | `plateforme/medisphere`, dossier `docs/cloud/` (runbooks dans `docs/cloud/runbooks/`) |

---

### M10-E10 — Brancher OpenStack sur Ceph  `LAB` `★★★`

> **Ticket PLAT-1120** — *De : Karim Benali*
> Tant que les images dorment sur le disque de `osctl01` et les disques des instances sur ceux des calculs, notre cloud tient dans trois VMs qu'on ne peut ni perdre ni vider : pas de migration à chaud, pas de volume persistant, et la panne d'un calcul emporte ses instances. Le Ceph de PAR1 attend depuis le module 08 avec ses pools. Je veux tout dessus : images, disques des instances, volumes et sauvegardes de volumes. Chaque service avec **sa** clé cephx, rien de plus que ce dont il a besoin. Et aucune clé en clair dans le dépôt.

**Objectifs pédagogiques**
- Brancher Glance, Nova, Cinder et cinder-backup sur un Ceph externe avec Kolla-Ansible (procédure *External Ceph* de la série 2026.1).
- Donner à chaque service une identité cephx à moindre privilège, et comprendre pourquoi certains services lisent les pools des autres.
- Comprendre le clonage copie-sur-écriture d'une image vers un disque d'instance, et pourquoi il impose le format `raw`.
- Changer le stockage d'un service en production sans perdre ce qui existe (ou en décidant en connaissance de cause de le reconstruire).

**Prérequis** : M08-E46 (pools et clés préparés), M10-E04 (déploiement), M10-E06 (images), M10-E07, M10-E08.
**Durée indicative** : 4 h.

**Contexte technique**
- État laissé par le palier 1 : Glance en stockage `file` (le défaut de Kolla quand aucun autre n'est choisi), Nova sur disques locaux, Cinder non activé (`enable_cinder` vaut `false` par défaut). Relis ton `globals.yml` : si ton E04 diffère, adapte les étapes.
- Kolla 2026.1 (*External Ceph*) : variables `glance_backend_ceph`, `cinder_backend_ceph`, `nova_backend_ceph` ; utilisateurs et pools par défaut `glance`/`images`, `cinder`/`volumes`, `cinder-backup`/`backups`, `vms` pour Nova ; **`ceph_nova_user` vaut par défaut `ceph_cinder_user`**. Fichiers attendus sous `etc/kolla/config/` : `glance/ceph.conf`, `glance/ceph.client.glance.keyring`, `cinder/ceph.conf`, `cinder/cinder-volume/…`, `cinder/cinder-backup/…`, `nova/ceph.conf`, `nova/ceph.client.*.keyring` (la liste exacte est dans la documentation : lis-la en entier). Avec un Ceph externe, cinder-volume et cinder-backup tournent sur les hôtes du groupe `storage` de l'inventaire (`osctl01`).
- Kolla copie les trousseaux (*keyrings*) avec le module `template` d'Ansible : leur contenu est un gabarit Jinja, évalué avec les variables du déploiement (dont celles de `passwords.yml`).
- La documentation de Kolla prévient : `ceph config generate-minimal-conf` produit des lignes commençant par une tabulation, que l'analyseur INI de Kolla n'accepte pas.
- Droits recommandés par Ceph pour OpenStack : page *Block Devices and OpenStack* de la documentation de Ceph (profils `rbd` et `rbd-read-only`).
- Flux : `ens20` des trois nœuds est dans le VLAN 30 comme les MON et les OSD : rien ne traverse la bordure.

> ⚠️ **Attention** : changer le stockage de Nova rend **inutilisables** les instances existantes (Nova cherchera leur disque dans le pool `vms`), et désactiver le stockage `file` de Glance rend ses images illisibles. Fais l'inventaire de l'étape 1 et supprime les instances du palier 1 **avant** le déploiement. Retour arrière : annuler la MR (retour de `globals.yml` à l'état précédent), `kolla-ansible deploy`, puis recréer les images depuis leur source. Les données de Ceph ne sont pas touchées par un retour arrière : les pools gardent ce qui y a été écrit.

**Travail demandé**
1. **Inventaire.** Liste les images (format, taille, stockage `stores`), les instances et leurs hôtes. Pour chaque image, décide : recréée depuis sa source vérifiée, ou exportée puis réimportée ? Note les propriétés à conserver.
2. **Côté Ceph.** Sur `ceph01`, vérifie les quatre pools (application `rbd` activée, règle CRUSH, taille) et les quatre clés avec leurs droits. Crée ce qui manque. Pour chaque clé, écris dans ton journal **pourquoi** elle a accès à chaque pool : pourquoi `client.cinder` lit-il `images` ? Pourquoi `client.nova` ? Que fait `cinder-backup` avec le pool `volumes` ? Produis le `ceph.conf` minimal destiné aux clients.
3. **Côté dépôt.** Dans une branche de `plateforme/openstack` : fichiers `ceph.conf` et trousseaux aux emplacements attendus, **sans** clé en clair dans Git (choisis et justifie : trousseaux chiffrés par Ansible Vault, ou trousseaux-gabarits qui lisent la clé dans `passwords.yml`) ; `etc/kolla/globals.d/10-ceph.yml` (activer Cinder, cinder-backup et les trois backends, utilisateur cephx de Nova). Copie-sur-écriture : Nova ne clone une image que si Glance publie son emplacement Ceph (`show_image_direct_url`) ; lis l'avertissement de Kolla à son sujet et décide.
4. **Déploiement.** Supprime les instances du palier 1. `kolla-ansible prechecks`, puis le déploiement (une nouvelle famille de services apparaît : `reconfigure` suffit-il ?). Contrôle les conteneurs `cinder_*`, `openstack volume service list`, et sur un calcul les secrets de libvirt (`virsh secret-list` dans le conteneur `nova_libvirt`) : combien, et pourquoi ?
5. **Images.** Recrée les images de E06 au format **raw** (avec contrôle de somme et les mêmes propriétés). Retrouve-les dans le pool `images` : à quoi sert l'instantané `snap` que Glance y crée ?
6. **Instances.** Crée `e10-vm` (`debian-13`, `m1.petit`, projet `plateforme`) : où est son disque, et de quoi est-il le clone (`rbd info`) ? Mesure le temps de création, compare à celui d'une instance du palier 1. Crée ensuite `e10-vol` démarrée **depuis un volume** de 10 Go : dans quel pool est son disque ? Que devient-il si on supprime l'instance ?
7. Réponds dans ton journal : pourquoi une image qcow2 ne peut-elle pas être clonée par Ceph, et que fait Nova si on lui en donne une ?

**Critères de réussite**
- [ ] La configuration Kolla (branche `main`, `globals.yml` et `globals.d/`) active Cinder, cinder-backup et les backends Ceph de Glance, Cinder et Nova ; Nova utilise la clé `client.nova`.
- [ ] Aucune clé cephx en clair dans le dépôt ; aucune clé `client.admin` utilisée par OpenStack.
- [ ] Toutes les images actives sont au format raw, stockées dans `rbd`, et publient leur emplacement Ceph.
- [ ] `cinder-volume` et `cinder-backup` sont `up` ; le disque de `e10-vm` est dans `vms` et clone une image du pool `images` ; le disque de `e10-vol` est dans `volumes`.

**Vérification** : `lab/bin/check 10 10`

<details><summary>Indice 1</summary>

`ceph auth get client.cinder` affiche les droits ; `ceph osd pool application get <pool>` dit si le pool est marqué `rbd`. Les droits `profile rbd` sur `mon` et `osd`, plus `profile rbd pool=…` sur `mgr`, sont la recette documentée ; un profil `rbd-read-only` suffit là où on ne fait que lire.
</details>

<details><summary>Indice 2</summary>

Un trousseau de Ceph est un petit fichier INI : `[client.glance]` puis `key = …`. Si sa ligne `key` devient `key = {{ <variable> }}` et que la variable est dans `passwords.yml` (déjà chiffré), le dépôt ne contient plus que des gabarits. Attention à `kolla-mergepwd --clean` lors d'une mise à jour : il retire les entrées qu'il ne connaît pas.
</details>

<details><summary>Indice 3</summary>

Quand `ceph_nova_user` reste à sa valeur par défaut, Nova utilise la clé de Cinder et ne cherche pas `ceph.client.nova.keyring`. Le pool `vms` contient des objets `<uuid>_disk` ; `rbd info vms/<uuid>_disk` montre une ligne `parent:` quand le disque est un clone. `qemu-img convert -f qcow2 -O raw` transforme une image ; `qemu-img info` lit sa taille virtuelle.
</details>

**Pour aller plus loin** (facultatif) : l'option `rbd_thin_provisioning` de `glance_store` évite d'écrire les zéros d'une image raw ; la méthode d'import interopérable de Glance (`openstack image import`, greffon *image conversion*) convertit elle-même une image qcow2. Compare avec ta conversion manuelle.

---

### M10-E11 — Cinder : volumes, types, snapshots, sauvegardes  `LAB` `★★`

> **Ticket DEV-1121** — *De : Julien Petit*
> Pour la recette de MédiAgenda, il nous faut une base PostgreSQL dont les données survivent à la destruction de la VM, un instantané avant chaque migration de schéma, et une sauvegarde qu'on sait restaurer **nous-mêmes**. Autre chose : la dernière fois qu'on a lancé un test de charge sur l'ancien hébergement, toute la plateforme a ralenti. Notre base de recette ne doit pas pouvoir faire ça.

**Objectifs pédagogiques**
- Définir des types de volumes et une qualité de service (QoS) appliquée par l'hyperviseur.
- Créer, attacher, agrandir un volume ; en prendre un instantané, en faire un clone.
- Sauvegarder (complète, incrémentale) et restaurer un volume avec cinder-backup sur Ceph, et savoir ce que garantit, ou non, chaque opération.

**Prérequis** : M10-E10.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Backend Kolla : section `rbd-1` de `cinder.conf` (`volume_backend_name = rbd-1`). Cinder crée un type `__DEFAULT__` ; le type par défaut se règle par `default_volume_type` dans `cinder.conf` (surcharge `etc/kolla/config/cinder.conf`).
- Types attendus : `ceph-standard` (type par défaut) et `ceph-iops-limite`, associé à une spécification QoS `qos-500iops` (500 IOPS et 100 Mio/s au total, appliquées **côté hyperviseur**).
- Image `debian-13` : propriété `hw_disk_bus` posée en E06 (un volume attaché apparaît sous `/dev/sdX` ou `/dev/vdX` selon elle).
- Objets de l'exercice (projet `plateforme`) : instance `e11-vm` (`debian-13`, `m1.petit`), volume `vol-essai` (10 Go, type `ceph-iops-limite`), instantané `snap-essai`, clone `vol-clone`, sauvegardes `sauv-essai` (complète) et `sauv-essai-inc` (incrémentale), volume restauré `vol-restaure`.

**Travail demandé**
1. Crée les deux types et la spécification QoS, associe-les ; rends `ceph-standard` type par défaut par la surcharge de `cinder.conf` (MR, `kolla-ansible reconfigure -t cinder`). Vérifie qu'un volume créé sans `--type` prend `ceph-standard`.
2. Crée `e11-vm` et `vol-essai` ; attache le volume, formate-le (ext4), monte-le sur `/srv/donnees`, écris un fichier de 200 Mio de données aléatoires et note sa somme SHA-256.
3. **QoS.** Mesure les IOPS dans l'instance (`fio`, lecture aléatoire 4 kio) avant et après association de la QoS (détache et rattache le volume : pourquoi ?). Retrouve la limite dans la définition libvirt de l'instance (`virsh dumpxml` dans `nova_libvirt` du calcul qui l'héberge).
4. **Instantané et clone.** Prends `snap-essai` du volume **attaché** (Cinder demande-t-il une option ? que garantit-il de la cohérence du système de fichiers ?) ; crée `vol-clone` depuis l'instantané. Côté Ceph, montre le lien entre les trois objets. Essaie de supprimer `snap-essai` : que se passe-t-il, et pourquoi ?
5. **Sauvegardes.** Crée `sauv-essai` (complète), modifie le fichier, crée `sauv-essai-inc` (incrémentale). Observe le pool `backups`. Restaure `sauv-essai` dans un **nouveau** volume `vol-restaure`, attache-le, et compare la somme du fichier à celle de l'étape 2.
6. **Agrandissement.** Passe `vol-essai` à 20 Go **sans le détacher** (microversion de l'API des volumes nécessaire : laquelle ?), puis agrandis le système de fichiers dans l'instance.
7. Réponds dans ton journal pour Julien, en dix lignes : instantané ou sauvegarde, que protège chacun (erreur humaine, perte du pool, perte de Ceph) ? Que manque-t-il pour une base PostgreSQL cohérente ?

**Critères de réussite**
- [ ] `ceph-standard` est le type par défaut et désigne le backend `rbd-1` ; `ceph-iops-limite` porte la QoS `qos-500iops` (consommateur côté hyperviseur).
- [ ] `vol-essai` (20 Go, `ceph-iops-limite`) est attaché à `e11-vm` ; `snap-essai` et `vol-clone` existent.
- [ ] `sauv-essai` et `sauv-essai-inc` sont disponibles, la seconde est incrémentale ; `vol-restaure` existe.
- [ ] La définition libvirt de `e11-vm` contient la limite d'IOPS.

**Vérification** : `lab/bin/check 10 11`

<details><summary>Indice 1</summary>

`openstack volume qos create --consumer <consommateur> --property <clé>=<valeur>` puis `openstack volume qos associate`. Les clés de QoS côté hyperviseur sont celles de libvirt (`total_iops_sec`, `total_bytes_sec`…). Nova lit la QoS **à l'attachement**.
</details>

<details><summary>Indice 2</summary>

`rbd children` et `rbd info` montrent les liens parent-enfant ; le pilote RBD de Cinder ne peut pas retirer un instantané dont un clone dépend encore (option `rbd_flatten_volume_from_snapshot`). `openstack volume backup show` affiche `is_incremental` ; `rbd ls -l backups` montre ce que le pilote Ceph de cinder-backup a écrit.
</details>

<details><summary>Indice 3</summary>

L'agrandissement d'un volume attaché demande la microversion 3.42 de l'API des volumes (`--os-volume-api-version`). Dans l'instance, `lsblk` voit la nouvelle taille ; `resize2fs` agrandit ext4 en ligne.
</details>

**Pour aller plus loin** (facultatif) : un type de volume chiffré (`--encryption-provider luks`) demande un gestionnaire de clés (Barbican) : regarde ce que Kolla devrait déployer en plus. Et les transferts de volume entre projets (`openstack volume transfer request create`) : à quoi serviraient-ils entre la recette et la production ?

---

### M10-E12 — Le réseau externe intégré au lab  `LAB` `★★`

> **Ticket SEC-1122** — *De : Sophie Laurent* — *Copie : Karim Benali*
> Le VLAN 52 est routé par nos passerelles et sort sur Internet comme tout le lab, sans distinction. Or ce qui s'y trouve, ce sont des instances que **d'autres équipes** administrent, avec les images et les mots de passe qu'elles choisissent. Je veux la liste exacte de ce qui sort du VLAN 52 et de ce qui y entre, et rien d'autre : pas de GitLab, pas de NetBox, pas de courrier vers Internet. Karim ajoute que les réseaux des projets ont une MTU de 1442 alors que le réseau des tunnels est à 9000, et que les équipes vont s'y casser les dents.

**Objectifs pédagogiques**
- Suivre le chemin d'un paquet entre une instance, son routeur OVN, le VLAN 52 et la bordure (SNAT du routeur, DNAT/SNAT des IP flottantes).
- Écrire et appliquer la politique de flux du réseau des instances dans la matrice de la bordure.
- Comprendre comment Neutron calcule la MTU d'un réseau Geneve, et la régler pour offrir 1500 aux instances.
- Déclarer dans la source de vérité ce qu'OpenStack gère.

**Prérequis** : M07-E15 (MTU), M07-E24 (bordure redondante, matrice commune), M10-E08, M10-E10.
**Durée indicative** : 3 h.

**Contexte technique**
- Neutron (ML2) : la MTU d'un réseau Geneve vaut `min(global_physnet_mtu, path_mtu)` moins l'en-tête IP extérieur (20 octets en IPv4) moins `max_header_size` de `[ml2_type_geneve]` (Kolla le règle à 38) ; un réseau `flat` reçoit `min(global_physnet_mtu, physical_network_mtus[<physnet>])`. Kolla ne règle ni `global_physnet_mtu` (défaut 1500) ni `path_mtu`. La MTU d'un réseau est fixée **à sa création** ; elle se modifie ensuite par `openstack network set --mtu`.
- Physique : OS-TUN (VLAN 51) à 9000 de bout en bout ; OS-EXT (VLAN 52) et OS-API (VLAN 50) à 1500.
- Matrice des flux : `pare_feu.yml` de `plateforme/ansible`, commune à `gw01` et `gw02` depuis M07-E24. Aujourd'hui, l'interface `ens19.52` est dans `LAB_IFS` : elle profite de la règle générique « lab vers Internet » et des règles NTP ; le DNS du lab est ouvert à tout 10.10.0.0/16. MGMT joint tout le lab.
- Instances : utilisateur `debian` sur `debian-13` ; groupe de sécurité `ssh-icmp-admin` (E08 : SSH et ICMP depuis MGMT).
- NetBox : préfixe 10.10.52.0/24 (M06-E05) ; les adresses .1 à .3 sont celles de la bordure.

> ⚠️ **Attention** : tu modifies le pare-feu des **deux** passerelles. Passe par le pipeline de `plateforme/ansible`, garde une session SSH ouverte sur `gw01` et `gw02`, et vérifie la console (`qm terminal 1000` et `1009`) avant d'appliquer. Retour arrière : annuler la MR et rejouer le rôle `pare_feu`. Le changement de MTU touche les réseaux des projets : les instances ne prennent la nouvelle valeur qu'à leur prochain bail DHCP ou redémarrage. Pas d'action sur `pve01`.

**Travail demandé**
1. **Le chemin.** Crée `e12-vm` (projet `plateforme`, `reseau-plateforme`, groupe `ssh-icmp-admin`) **sans** IP flottante : depuis la console (`openstack console url show`), lance un `ping` vers 1.1.1.1 et capture sur la bordure (`tcpdump -ni ens19.52` sur la passerelle maîtresse). Quelle adresse source vois-tu ? Associe une IP flottante et recommence. Retrouve les deux traductions dans OVN (`ovn-nbctl lr-nat-list` dans le conteneur `ovn_northd`).
2. **La politique.** Écris dans `docs/cloud/reseau-externe.md` (projet `plateforme/medisphere`) la matrice voulue pour le VLAN 52 : entrant (qui joint les IP flottantes, sur quels ports), sortant (DNS, NTP, dépôts de paquets en HTTP/HTTPS vers Internet, rien vers les autres VLAN, rien d'autre vers Internet), avec la raison de chaque ligne. Fais-la valider par Sophie (MR).
3. **L'application.** Traduis-la dans `pare_feu.yml` : sors `ens19.52` de la règle générique de sortie sans casser les autres VLAN, ajoute les règles ciblées, et ce qu'il faut pour que les développeurs, sur le VPN d'administration, joignent leurs IP flottantes sur 22, 80 et 443. Applique par le pipeline. Contrôle depuis `e12-vm` : `apt-get update` fonctionne ; une connexion vers 1.1.1.1:25 et vers `git01:443` échoue ; la résolution DNS fonctionne.
4. **La MTU.** Mesure la MTU de `reseau-plateforme` et celle de `ext-net`, puis la plus grande trame qui passe depuis `e12-vm` vers une autre instance du même réseau (`ping -M do -s …`). Choisis les valeurs de `global_physnet_mtu`, `path_mtu` et `physical_network_mtus` pour que **les réseaux des projets soient à 1500** et que `ext-net` reste à 1500 ; justifie pourquoi tu ne donnes pas 8942 aux instances. Applique par surcharges (`neutron.conf`, `neutron/ml2_conf.ini`), `kolla-ansible reconfigure -t neutron`, puis corrige les réseaux existants. Recommence la mesure.
5. **La source de vérité.** Dans NetBox, déclare la plage 10.10.52.200-249 comme plage d'adresses gérée par OpenStack (description, statut, et l'option qui la marque comme entièrement utilisée), pour que personne ne l'alloue ailleurs (M06-E13).
6. Réponds dans ton journal : sans IP flottante, une instance est-elle joignable depuis `adm01` ? Depuis une autre instance d'un autre projet ? Que faudrait-il pour qu'une instance n'ait **aucune** sortie (pense au routeur et à `enable_snat`) ?

**Critères de réussite**
- [ ] `pare_feu.yml` (branche `main`) contient des règles commentées propres au VLAN 52, et la règle générique de sortie ne s'applique plus à `ens19.52`.
- [ ] Depuis `e12-vm` : dépôts Debian joignables en HTTP/HTTPS, DNS fonctionnel, `git01:443` et le port 25 d'Internet injoignables.
- [ ] `e12-vm` répond depuis `adm01` sur son IP flottante (ICMP et SSH).
- [ ] Tous les réseaux Geneve des projets ont une MTU de 1500, `ext-net` aussi ; la configuration générée de `neutron-server` contient tes réglages.
- [ ] La plage 10.10.52.200-249 existe dans NetBox.

**Vérification** : `lab/bin/check 10 12` (avec `e12-vm` démarrée et son IP flottante associée)

<details><summary>Indice 1</summary>

Sans IP flottante, le routeur OVN applique un SNAT vers son adresse de passerelle (une adresse de `ext-net`) ; avec, un `dnat_and_snat` vers l'IP flottante. Le conteneur `ovn_northd` porte les outils `ovn-nbctl` et `ovn-sbctl` (documentation Kolla, *Neutron*).
</details>

<details><summary>Indice 2</summary>

Pour obtenir 1500 dans un réseau Geneve, il faut un chemin de 1500 + 20 + 38 octets. Le minimum de `global_physnet_mtu` et `path_mtu` décide pour les tunnels ; `physical_network_mtus` protège les réseaux `flat` d'un `global_physnet_mtu` trop grand.
</details>

<details><summary>Indice 3</summary>

Dans la matrice, définis un nouvel ensemble d'interfaces sans `ens19.52` pour la règle générique de sortie, et garde `LAB_IFS` pour les règles d'entrée (NTP, NTS) qui doivent continuer à servir le VLAN 52. Les règles plus précises s'ajoutent ensuite, avec destination, protocole et ports.
</details>

**Pour aller plus loin** (facultatif) : les IP flottantes distribuées (`neutron_ovn_distributed_fip`) font sortir le trafic des IP flottantes directement par les calculs : que faudrait-il câbler sur `oscmp01-02` ? Et Designate (fiche du module) : publier `<instance>.<projet>.cloud.par1.medisphere.internal` dans PowerDNS.

---

### M10-E13 — Projets et quotas pour les équipes  `LAB` `★★`

> **Ticket PLAT-1123** — *De : Claire Morel*
> MédiAgenda arrive lundi avec ses deux projets. Je ne veux pas qu'une recette mal écrite mange la mémoire de la production, ni qu'une équipe découvre un quota en pleine mise en service. Dimensionne les quotas sur ce que nous avons **réellement**, pas sur des valeurs par défaut pensées pour un cloud de mille serveurs. Et dis-moi noir sur blanc qui peut faire quoi dans quel projet.

**Objectifs pédagogiques**
- Lire la capacité réelle du cloud dans Placement (inventaires, réserves, ratios de surallocation).
- Dimensionner et poser les quotas de calcul, de volumes et de réseau d'un projet, et vérifier qu'ils s'appliquent.
- Restreindre un gabarit à un projet ; tracer les attributions de rôles et comprendre pourquoi `admin` n'est jamais un rôle « de projet ».

**Prérequis** : M10-E05 (domaine, projets, groupes), M10-E10.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Projets du domaine `medisphere` : `plateforme`, `mediagenda-dev`, `mediagenda-prod` ; groupes `equipe-plateforme`, `equipe-mediagenda` et leurs rôles (E05, `donnees/identite.yml`).
- Calculs : 2 × (4 vCPU, 8 Go). Nova réserve par défaut 512 Mio par hôte (`reserved_host_memory_mb`) ; ratios initiaux : 4.0 pour le processeur, 1.0 pour la mémoire et le disque. Avec Ceph, chaque calcul annonce la capacité du pool `vms` comme s'il la possédait seul.
- Greffon `osc-placement` : `openstack resource provider list`, `… inventory list`, `… usage show`.
- Politique demandée par Claire : la production est prioritaire (sa part ne doit jamais être prise par la recette) ; la somme des quotas de mémoire des trois projets ne dépasse pas la mémoire réellement utilisable ; une marge pour les essais de l'équipe Plateforme.
- Gabarit réservé : `m1.prod-db` (2 vCPU, 4 Go, 40 Go), privé, accessible au seul projet `mediagenda-prod`.
- Les répartiteurs de charge (Octavia) ont leur propre quota : il sera posé en E16.

**Travail demandé**
1. Relève la capacité : pour chaque calcul, inventaires `VCPU`, `MEMORY_MB`, `DISK_GB` (total, réservé, ratio) et usage. Calcule la capacité **utilisable** et compare à ce que consomment vraiment les conteneurs de Kolla sur un calcul (`free -m`). Faut-il augmenter la réserve ? (tu le feras en E20.)
2. Construis dans `docs/cloud/capacite.md` la table des quotas des trois projets : instances, vCPU, mémoire, volumes, Go de volumes, instantanés, sauvegardes, IP flottantes, réseaux, routeurs, groupes de sécurité, ports. Justifie chaque ligne (une instance de base de données, deux serveurs d'application, un répartiteur…).
3. Applique-les (`openstack quota set`), puis vérifie avec `openstack quota show --usage`.
4. Prouve que le quota s'applique : avec le compte d'un membre de `mediagenda-dev`, demande une instance de trop (ou trop de mémoire). Quel message, quel code HTTP, à quel moment (API ou ordonnanceur) ?
5. Crée `m1.prod-db`, privé, et donne-le à `mediagenda-prod` seul. Montre qu'il est invisible depuis `mediagenda-dev`.
6. **Qui peut quoi.** Liste les attributions de rôles effectives des trois projets (`openstack role assignment list --effective --names`). Puis, avec un utilisateur jetable `essai-admin` à qui tu donnes `admin` **sur `mediagenda-dev` seulement**, liste les instances de `mediagenda-prod`. Qu'en conclus-tu ? Supprime `essai-admin`. Écris le tableau « qui peut faire quoi » demandé par Claire dans `docs/cloud/capacite.md`.

**Critères de réussite**
- [ ] Les quotas de `mediagenda-dev`, `mediagenda-prod` et `plateforme` ne sont plus les valeurs par défaut ; la somme de leurs quotas de mémoire ne dépasse pas la mémoire utilisable des calculs.
- [ ] `mediagenda-prod` a un quota de mémoire au moins égal à celui de `mediagenda-dev`.
- [ ] `m1.prod-db` est privé et accessible au seul projet `mediagenda-prod`.
- [ ] Aucun groupe ni utilisateur d'équipe n'a le rôle `admin` ; `essai-admin` n'existe plus.

**Vérification** : `lab/bin/check 10 13`

<details><summary>Indice 1</summary>

Mémoire utilisable d'un calcul = (`total` − `reserved`) × `allocation_ratio` de l'inventaire `MEMORY_MB`. Les quotas se posent par projet ; un quota de -1 signifie « illimité ».
</details>

<details><summary>Indice 2</summary>

`openstack flavor create --private` crée un gabarit que personne ne voit ; `openstack flavor set --project <projet> <gabarit>` donne l'accès. Pour tester avec les droits d'un membre, il te faut un cloud de `clouds.yaml` authentifié comme **lui**, pas comme administrateur.
</details>

<details><summary>Indice 3</summary>

Regarde la règle `context_is_admin` dans les politiques par défaut de Nova (`oslopolicy-sample-generator` ou la documentation *Nova policies*) : sur quoi porte-t-elle, le rôle seul ou le rôle **et** le projet ?
</details>

**Pour aller plus loin** (facultatif) : les *unified limits* de Keystone (limites enregistrées dans Keystone, appliquées par Nova et Glance) remplacent les quotas propres à chaque service. Lis la documentation de Nova à leur sujet : qu'est-ce qui change pour toi ?

---

### M10-E14 — Heat : des piles d'infrastructure  `LAB` `★★`

> **Ticket DEV-1124** — *De : Julien Petit*
> On sait maintenant créer une instance, un volume et une IP flottante… en douze commandes, dans le bon ordre, et on oublie toujours le groupe de sécurité. Je voudrais décrire **une** fois notre environnement de recette dans un fichier, le créer d'une commande, le modifier (plus de mémoire, un disque plus grand) et le supprimer proprement sans rien oublier derrière.

**Objectifs pédagogiques**
- Écrire un gabarit HOT : paramètres contraints, ressources et dépendances, sorties.
- Créer, prévisualiser une mise à jour, mettre à jour et supprimer une pile.
- Lire les événements d'une pile et comprendre ce que Heat remplace ou modifie en place.

**Prérequis** : M10-E10, M10-E11, M10-E12, M10-E13.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Heat 2026.1 : la dernière version de gabarit est `2021-04-16` (alias `wallaby`). Un membre du projet peut créer des piles (politiques par défaut). Client : greffon `python-heatclient` (`openstack stack …`).
- Gabarit : `heat/pile-recette.yaml` dans `plateforme/openstack`, fichier d'environnement `heat/recette-dev.env.yaml`.
- Contenu attendu : un réseau et un sous-réseau (DNS 10.10.20.10 et 10.10.20.16), un routeur relié à `ext-net`, un groupe de sécurité (SSH et HTTP depuis MGMT et le VPN d'administration), une instance (avec nginx installé par cloud-init), un volume attaché, une IP flottante associée.
- Pile de l'exercice : `recette-e14`, projet `mediagenda-dev`, créée avec le cloud `medisphere-mediagenda-dev`.

**Travail demandé**
1. Écris le gabarit : paramètres `image`, `gabarit`, `cle`, `reseau_externe`, `cidr`, `taille_volume` avec des **contraintes** (une image, un gabarit, une paire de clés qui existent ; une taille entre 1 et 50 Go) ; sorties `ip_flottante` et `url`. Valide-le (`openstack orchestration template validate`).
2. Crée la pile avec le fichier d'environnement. Suis les événements. Dans quel ordre Heat crée-t-il les ressources, et qui le décide ? Contrôle `http://<ip_flottante>/` depuis `adm01`.
3. Change le gabarit de l'instance (`m1.petit` → `m1.moyen`) et la taille du volume (5 → 10 Go). **Avant** d'appliquer, prévisualise (`--dry-run`) : quelles ressources seront modifiées en place, lesquelles remplacées ? Applique, puis vérifie que l'IP flottante et les données du volume n'ont pas changé.
4. Modifie à la main (CLI) le groupe de sécurité de la pile en ajoutant une règle. Que fait la mise à jour suivante ? Compare avec ce qu'aurait fait OpenTofu.
5. Fais échouer une création (taille de volume au-delà du quota) : état de la pile, message, et comment repartir (`--rollback`) ?
6. Réponds dans ton journal : Heat ou OpenTofu pour la recette de MédiAgenda (tu verras OpenTofu en E15) ? Trois arguments de chaque côté.

**Critères de réussite**
- [ ] `heat/pile-recette.yaml` (branche `main`) déclare la version `2021-04-16` (ou `wallaby`), des paramètres contraints et les sorties `ip_flottante` et `url`.
- [ ] La pile `recette-e14` existe dans `mediagenda-dev`, dans l'état `UPDATE_COMPLETE`, avec une instance en `m1.moyen` et un volume de 10 Go.
- [ ] La page servie par l'instance répond sur l'IP flottante de la sortie `ip_flottante`.

**Vérification** : `lab/bin/check 10 14` (puis supprime la pile : `openstack stack delete --wait recette-e14`)

<details><summary>Indice 1</summary>

Une contrainte de paramètre s'écrit `constraints: [{custom_constraint: glance.image}]` (ou `nova.flavor`, `nova.keypair`, `neutron.network`), ou `range: {min: …, max: …}`. `openstack orchestration resource type show OS::Nova::Server` décrit les propriétés et leur politique de mise à jour.
</details>

<details><summary>Indice 2</summary>

Les dépendances viennent des références (`get_resource`, `get_attr`) et des `depends_on` explicites. L'interface du routeur doit exister avant l'association d'IP flottante : sans elle, Neutron refuse (« External network … is not reachable from subnet … »).
</details>

<details><summary>Indice 3</summary>

Pour `OS::Nova::Server`, `flavor_update_policy` vaut `RESIZE` par défaut. Une propriété marquée « Updates cause replacement » recrée la ressource : lis le résultat de `--dry-run` colonne par colonne.
</details>

**Pour aller plus loin** (facultatif) : `OS::Heat::ResourceGroup` et un gabarit imbriqué pour créer N serveurs d'application ; `OS::Heat::SoftwareConfig` pour séparer la configuration de l'instance.

---

### M10-E15 — OpenTofu et le provider OpenStack  `LAB` `★★★`

> **Ticket PLAT-1125** — *De : Karim Benali*
> Les quotas posés à la main en E13, les réseaux des projets créés au fil des tickets : dans trois mois, personne ne saura pourquoi `mediagenda-prod` a trois IP flottantes et pas quatre. Je veux le « socle » de chaque projet d'équipe en code, dans `plateforme/infra`, revu par MR et appliqué par le pipeline comme le reste. Et pas avec ton mot de passe : un identifiant dédié, qui expire, qu'on peut révoquer.

**Objectifs pédagogiques**
- Configurer le provider `terraform-provider-openstack/openstack` 3.x avec une *application credential* et la PKI MédiSphère.
- Décrire le socle d'un projet (quotas, réseau, sous-réseau, routeur, groupes de sécurité) pour plusieurs projets avec `for_each`, sans les ressources supprimées en 3.0.
- Reprendre dans OpenTofu des objets créés à la main (import) et obtenir un plan vide.
- Brancher l'état dans le pipeline existant de `plateforme/infra`.

**Prérequis** : M05 (état distant, chiffrement, pipeline), M10-E13.
**Durée indicative** : 4 h.

**Contexte technique**
- Provider `terraform-provider-openstack/openstack` `~> 3.4` (PLAN §6). Supprimés en 3.0 : `openstack_compute_floatingip_v2`, `openstack_compute_floatingip_associate_v2`, `openstack_compute_secgroup_v2`. Ressources utiles : `openstack_compute_quotaset_v2`, `openstack_blockstorage_quotaset_v3`, `openstack_networking_quota_v2`, `openstack_networking_network_v2`, `openstack_networking_subnet_v2`, `openstack_networking_router_v2`, `openstack_networking_router_interface_v2`, `openstack_networking_secgroup_v2`, `openstack_networking_secgroup_rule_v2` ; sources de données `openstack_identity_project_v3`, `openstack_networking_network_v2`. Identifiants d'import des quotas : `<id du projet>/<région>` (région Kolla : `RegionOne`).
- Configuration racine : `envs/openstack-projets/` dans `plateforme/infra`, clé d'état `envs/openstack-projets/terraform.tfstate`, même backend et même chiffrement que les autres états (M05-E27).
- Périmètre : `mediagenda-dev` et `mediagenda-prod`. Les **projets eux-mêmes** et les attributions de rôles restent créés par RB-100 (E22) ; l'état reçoit les projets par leur nom.
- Identité : compte de service `svc-tofu` (domaine `Default`, comme les autres comptes de service), rôle `admin` sur le projet `admin` (poser des quotas et créer des ressources pour d'autres projets sont des opérations d'administrateur) ; *application credential* `tofu-openstack-projets`, expiration à 90 jours. Sur `adm01` : `~/.config/workbook/openstack-tofu.env` (600) ; en CI : variables protégées et masquées.
- Réseau de chaque projet : `<projet>-net`, `<projet>-sousreseau` (`mediagenda-dev` 192.168.110.0/24, `mediagenda-prod` 192.168.120.0/24, DNS 10.10.20.10 et 10.10.20.16), routeur `<projet>-routeur` relié à `ext-net` ; groupe de sécurité `<projet>-admin` (SSH depuis 10.10.10.0/24). Étiquette `tofu` sur ce qui est géré.

**Travail demandé**
1. Crée `svc-tofu` dans `Default` et son rôle (le code d'identité de E05 ne gère que le domaine `medisphere` : script relu en MR, mot de passe tapé, jamais en argument, puis oublié). Connecté comme lui, crée l'application credential. Réponds : que se passe-t-il pour l'application credential si `svc-tofu` perd son rôle ? Si on désactive le compte ? Que signifie `--unrestricted`, et pourquoi ne le mets-tu pas ?
2. Écris la configuration racine : versions, backend, chiffrement, provider (authentification par variables d'environnement, CA MédiSphère vérifiée, région), une variable `projets` (carte : nom → réseau, quotas), et les ressources avec `for_each`. Aucun secret dans le dépôt.
3. Les quotas posés en E13 existent déjà : importe-les (blocs `import` relus en MR) plutôt que de les écraser. `tofu plan` doit montrer des imports et des créations (réseaux), aucun changement de quota imprévu.
4. Branche l'état dans le pipeline (plan en MR, apply manuel protégé sur `main`, même gabarit que les autres états) ; applique par le pipeline.
5. Vérifie : `openstack network list --project mediagenda-dev`, une instance de test dans `mediagenda-dev-net` qui sort par son routeur. Modifie à la main un quota de `mediagenda-prod` : que montre le plan suivant ? Remets en ordre par le code.
6. Réponds : pourquoi le réseau d'un projet appartient-il à ce projet (`tenant_id`) et pas à `plateforme` ? Que fait un `tofu destroy` des quotas (lis la documentation des ressources de quota) ?

**Critères de réussite**
- [ ] `envs/openstack-projets/` est sur `main` de `plateforme/infra`, contraint le provider à `~> 3.4`, n'utilise aucune ressource supprimée en 3.0, et ne contient aucun secret.
- [ ] `mediagenda-dev-net` et `mediagenda-prod-net` existent dans leur projet, étiquetés `tofu`, MTU 1500, chacun relié à `ext-net` par son routeur.
- [ ] L'application credential `tofu-openstack-projets` existe, avec une date d'expiration ; `openstack-tofu.env` est en 600.
- [ ] Le pipeline de `plateforme/infra` contient un plan et un apply pour `openstack-projets`.

**Vérification** : `lab/bin/check 10 15`

<details><summary>Indice 1</summary>

Le provider lit `OS_AUTH_URL`, `OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET`, `OS_CACERT`, `OS_REGION_NAME` quand ses arguments sont absents. Avec ces variables, aucune ligne d'authentification n'est nécessaire dans `providers.tf`. Une application credential est liée à **un** projet : celui du jeton qui l'a créée.
</details>

<details><summary>Indice 2</summary>

Un bloc `import` accepte `for_each` et une expression d'identifiant (OpenTofu ≥ 1.7) : `id = "${data.openstack_identity_project_v3.p[each.key].id}/RegionOne"`. Le bloc peut être retiré une fois l'import appliqué.
</details>

<details><summary>Indice 3</summary>

`openstack_networking_router_v2` prend `external_network_id`, que la source de données `openstack_networking_network_v2` (`name = "ext-net"`, `external = true`) fournit. Un administrateur qui crée pour un autre projet renseigne `tenant_id` sur **chaque** ressource Neutron, y compris le groupe de sécurité et ses règles.
</details>

**Pour aller plus loin** (facultatif) : les *access rules* d'une application credential limitent les chemins d'API qu'elle peut appeler. Écris celles qui suffiraient à cet état (identité en lecture, quotas, réseau) et mesure ce que cela coûte en maintenance.

---

### M10-E16 — Octavia : répartiteurs de charge à la demande  `LAB` `★★★`

> **Ticket DEV-1126** — *De : Julien Petit*
> En recette, MédiAgenda tourne sur deux instances, et chaque redémarrage de l'une d'elles coupe la moitié des testeurs. Sur un cloud public, on aurait un répartiteur de charge en libre-service. On peut avoir ça ici ? Idéalement il ferait aussi le HTTPS et le routage par chemin, comme notre ancien HAProxy.

**Objectifs pédagogiques**
- Activer Octavia avec le **fournisseur OVN** (sans amphores) dans Kolla, et comprendre ce que ce choix implique.
- Créer un répartiteur, un écouteur, un pool, des membres et un contrôle de santé ; publier le répartiteur par une IP flottante.
- Connaître exactement les limites du fournisseur OVN, et répondre à Julien sur ce qu'il ne fera pas.

**Prérequis** : M10-E12, M10-E13.
**Durée indicative** : 3 h.

**Contexte technique**
- Kolla 2026.1 (*Octavia*, section *OVN provider*) : `enable_octavia: "yes"`, `octavia_provider_drivers: "ovn:OVN provider"`, `octavia_provider_agents: "ovn"`. Lis dans les valeurs par défaut du rôle ce que devient `octavia_auto_configure` quand le fournisseur `amphora` n'est pas listé. Le fournisseur par défaut d'Octavia est `amphora` (`[api_settings] default_provider_driver`).
- Documentation du fournisseur OVN (*ovn-octavia-provider*, section *Limitations*) : à lire **avant** de répondre à Julien.
- Client : greffon `python-octaviaclient` (`openstack loadbalancer …`).
- Objets (projet `mediagenda-dev`, réseau `mediagenda-dev-net` de E15) : instances `e16-web1`, `e16-web2` (nginx, page qui affiche le nom de l'instance), groupe de sécurité `e16-web` (HTTP depuis le sous-réseau du projet et depuis MGMT), répartiteur `lb-e16`, écouteur `ecoute-80` (TCP 80), pool `pool-web`, contrôle de santé TCP, IP flottante sur l'adresse virtuelle.
- Quota Octavia du projet : `openstack loadbalancer quota set`.

**Travail demandé**
1. Lis la section *Limitations* du fournisseur OVN et note pour Julien : protocoles, algorithmes, contrôles de santé, TLS, L7. Puis dis ce qui disparaît par rapport aux amphores (et ce qu'on y gagne : pas de VM, haute disponibilité intrinsèque).
2. Active Octavia par MR (`etc/kolla/globals.d/16-octavia.yml`, et la surcharge qui fait d'`ovn` le fournisseur par défaut). Déploie (`kolla-ansible deploy -t octavia,horizon` : pourquoi `horizon` ?). Contrôle `openstack loadbalancer provider list` et les conteneurs `octavia_*` : lesquels servent à quelque chose sans amphores ?
3. Pose le quota de répartiteurs de `mediagenda-dev` (et de `mediagenda-prod`), reporte-le dans `docs/cloud/capacite.md` et dans `envs/openstack-projets` si ta version du provider le permet.
4. En tant que membre de `mediagenda-dev`, crée les deux instances, puis le répartiteur et ses objets. Essaie d'abord un écouteur `HTTP` et un pool `ROUND_ROBIN` : messages ? Termine en TCP / `SOURCE_IP_PORT`.
5. Associe une IP flottante au port de l'adresse virtuelle. Depuis `adm01`, `curl` en boucle : la répartition est-elle visible ? Pourquoi peu, avec `SOURCE_IP_PORT` ?
6. Arrête nginx sur `e16-web1` : statut du membre, temps de détection, comportement côté client. Relance-le.
7. Montre le répartiteur dans OVN (`ovn-nbctl lb-list`) : où vit-il, et pourquoi n'y a-t-il pas de point unique de panne ?
8. Réponds à Julien (dix lignes) : comment obtenir HTTPS et le routage par chemin avec ce que nous avons (pense à `lb01`/`lb02` du module 07, ou à un HAProxy dans le projet derrière le répartiteur OVN) ?

**Critères de réussite**
- [ ] La configuration Kolla (branche `main`) active Octavia avec le seul fournisseur `ovn` ; `openstack loadbalancer provider list` ne propose pas `amphora`.
- [ ] `lb-e16` (fournisseur `ovn`) est `ACTIVE` et `ONLINE`, avec un écouteur TCP 80, un pool `SOURCE_IP_PORT` de deux membres et un contrôle de santé TCP.
- [ ] `http://<IP flottante de lb-e16>/` répond depuis `adm01`.
- [ ] `mediagenda-dev` a un quota de répartiteurs différent de la valeur par défaut.

**Vérification** : `lab/bin/check 10 16`

<details><summary>Indice 1</summary>

Avec un seul fournisseur listé, Kolla ne crée ni gabarit `amphora`, ni réseau de gestion, ni certificats, et désactive le *jobboard*. Sans changer `default_provider_driver`, un `loadbalancer create` sans `--provider` demande `amphora`… qui n'est pas activé.
</details>

<details><summary>Indice 2</summary>

L'adresse virtuelle d'un répartiteur est un port Neutron (`vip_port_id` dans `openstack loadbalancer show`). Une IP flottante s'associe à un port : `openstack floating ip set --port <port> <ip>`.
</details>

<details><summary>Indice 3</summary>

Le contrôle de santé OVN s'appuie sur un port de service créé dans le sous-réseau des membres : le groupe de sécurité des membres doit laisser passer ses sondes. `openstack loadbalancer status show lb-e16` affiche l'arbre complet des statuts.
</details>

**Pour aller plus loin** (facultatif) : le fournisseur `amphora` (fiche du module) : liste ce qu'il faudrait construire (image, réseau de gestion, certificats, gabarit) et la mémoire qu'il coûterait sur nos calculs.

---

### M10-E17 — Horizon et l'accès des équipes  `LAB` `★★`

> **Ticket DEV-1127** — *De : Julien Petit* — *Copie : Sophie Laurent*
> Toute l'équipe ne vit pas dans un terminal : nos testeuses veulent voir leurs instances, ouvrir une console, redémarrer une VM. Aujourd'hui, la page de connexion ne demande même pas le domaine et nos comptes `medisphere` n'y entrent pas. Sophie a ses conditions : HTTPS de bout en bout, session courte, et accès depuis le VPN seulement.

**Objectifs pédagogiques**
- Configurer Horizon dans Kolla (multi-domaines, réglages Django par surcharge) et le servir derrière le HAProxy de Kolla en HTTPS.
- Ouvrir les flux nécessaires à l'usage du tableau de bord (API, console noVNC) depuis le VPN d'administration.
- Remettre à un utilisateur un accès autonome (fichier `clouds.yaml`, application credential) depuis le tableau de bord.

**Prérequis** : M10-E04 (TLS externe), M10-E05, M10-E12.
**Durée indicative** : 2 h.

**Contexte technique**
- Horizon : `https://openstack.par1.medisphere.internal/` (VIP externe 10.10.50.201, port 443). Derrière HAProxy, le conteneur `horizon` écoute sur 8080.
- Kolla 2026.1 : `horizon_keystone_multidomain` (défaut `false`), `horizon_keystone_domain_choices` (dictionnaire ; plus d'une entrée → liste déroulante) ; réglages Django supplémentaires dans `etc/kolla/config/horizon/_9999-custom-settings.py`. Kolla pose déjà `SESSION_COOKIE_SECURE` et `CSRF_COOKIE_SECURE` quand TLS est activé.
- Exigences de Sophie : session de 30 minutes ; accès depuis le VPN d'administration (10.255.1.0/24) et MGMT seulement ; HTTPS uniquement ; aucune autre interface publiée.
- La console d'une instance passe par `nova-novncproxy`, publié sur la VIP externe, port 6080.

**Travail demandé**
1. Depuis ton poste (VPN), ouvre la page : que se passe-t-il ? Repère dans la matrice les flux qui manquent, pour Horizon **et** pour ce que fait le navigateur ensuite (console). Liste-les avant d'écrire quoi que ce soit.
2. Par MR sur `plateforme/openstack` : multi-domaines avec le domaine `medisphere` proposé en premier (`etc/kolla/globals.d/17-horizon.yml`), session de 30 minutes (`_9999-custom-settings.py`). Déploie (`-t horizon`). Contrôle le contenu de `/etc/kolla/horizon/_9999-custom-settings.py` sur `osctl01`.
3. Par MR sur `plateforme/ansible` : les flux du VPN vers 10.10.50.201 (443 et 6080 seulement). Applique.
4. Connecte-toi comme `julien.petit` (domaine `medisphere`). Change de projet, ouvre la console d'une instance de `mediagenda-dev`, redémarre-la. Que voit-il de `mediagenda-prod` ?
5. Depuis Horizon, comme Julien, crée une application credential et télécharge le `clouds.yaml` proposé. Que contient-il, et que manque-t-il pour qu'il fonctionne sur son poste (pense à la CA) ?
6. Vérifie depuis `adm01` : en-têtes de sécurité de la réponse (cookies `Secure`, HSTS ?), redirection de HTTP vers HTTPS, certificat présenté. Note ce qui manque pour la revue de sécurité du palier 3.

**Critères de réussite**
- [ ] `https://openstack.par1.medisphere.internal/` présente un certificat de la PKI MédiSphère et une page de connexion qui demande le domaine.
- [ ] Le dépôt contient le réglage multi-domaines et une durée de session de 1800 secondes, et la configuration générée de `horizon` aussi.
- [ ] La matrice des flux autorise le VPN d'administration vers 10.10.50.201 sur 443 et 6080, et seulement ces ports.
- [ ] Le port 6080 de la VIP externe répond.

**Vérification** : `lab/bin/check 10 17`

<details><summary>Indice 1</summary>

La page de Horizon appelle Keystone **depuis le serveur** (pas depuis ton navigateur) : seuls le port d'Horizon et celui de la console concernent le poste. Mais un utilisateur qui veut aussi la CLI depuis son poste aura besoin des ports des API : décide si c'est voulu.
</details>

<details><summary>Indice 2</summary>

`SESSION_TIMEOUT` est le réglage de Horizon (en secondes) ; Django a aussi `SESSION_COOKIE_AGE`. Le fichier `_9999-custom-settings.py` est un module Python : une erreur de syntaxe fait tomber tout le tableau de bord. Teste-le avec `python3 -m py_compile` avant la MR.
</details>

<details><summary>Indice 3</summary>

Le `clouds.yaml` d'une application credential contient `auth_type: v3applicationcredential`, l'identifiant et le secret, mais pas la confiance TLS : `cacert:` ou le magasin système du poste.
</details>

**Pour aller plus loin** (facultatif) : `haproxy_single_external_frontend` publie toutes les API sur le seul port 443, distinguées par nom d'hôte. Que faudrait-il en DNS et en certificats ? Et l'authentification unique (WebSSO, module 24).

---

### M10-E18 — Métadonnées et cloud-init dans OpenStack  `LAB` `★★`

> **Ticket PLAT-1128** — *De : Nadia Roussel*
> Trois tickets cette semaine pour des instances « sans clé SSH » ou « sans nginx » alors que l'équipe jure avoir tout mis dans les données utilisateur. Je veux comprendre comment une instance reçoit sa configuration, savoir le vérifier de l'intérieur, et avoir une règle pour les cas tordus (réseau sans DHCP, service de métadonnées en panne). Karim ajoute une demande : que **toutes** les instances fassent confiance à notre CA et prennent l'heure chez nous, sans dépendre de ce que chaque équipe écrit.

**Objectifs pédagogiques**
- Suivre le chemin d'une requête vers 169.254.169.254 avec OVN (agent de métadonnées, `nova-metadata`) et le comparer au *config drive*.
- Distinguer métadonnées, données utilisateur et données fournisseur (*vendor data*), et savoir qui gagne.
- Diagnostiquer cloud-init depuis l'instance.

**Prérequis** : M03 (cloud-init), M10-E12.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Avec OVN, chaque calcul exécute `neutron_ovn_metadata_agent` ; dans chaque réseau qui a un sous-réseau avec DHCP, un port de métadonnées sert 169.254.169.254 depuis un espace de noms `ovnmeta-<id du réseau>` du calcul, et relaie vers `nova-metadata`.
- Kolla : un fichier `etc/kolla/config/nova/vendordata.json` est copié dans les conteneurs de Nova et déclaré comme données fournisseur statiques. cloud-init lit la clé `cloud-init` de ces données et l'applique comme des données utilisateur ; les données utilisateur l'emportent ; un utilisateur peut les désactiver.
- Données fournisseur voulues : la racine « MédiSphère Root CA » (module `ca_certs`), chrony vers 10.10.52.1 (passerelle du VLAN 52).
- Objets (projet `plateforme`) : `e18-vm` (avec données utilisateur : nginx, un fichier `/etc/medisphere/role` contenant la valeur de la métadonnée `role`, IP flottante) ; réseau `e18-sans-dhcp` (sous-réseau 192.168.180.0/24 **sans** DHCP, relié au routeur du projet) et instance `e18-cd` sur ce réseau, avec *config drive*.

**Travail demandé**
1. Dans `e18-vm`, interroge le service : `/openstack/latest/meta_data.json`, `network_data.json`, `user_data`, `vendor_data.json`. Dans quel espace de noms du calcul le proxy écoute-t-il ? Suis la requête jusqu'au journal de `nova-metadata`.
2. Écris les données utilisateur de `e18-vm` (cloud-config) : paquets, fichier `/etc/medisphere/role` rempli à partir de la métadonnée `role` de l'instance (`--property role=web`). Diagnostique depuis l'instance : `cloud-init status --long`, `/var/log/cloud-init.log`, `cloud-init query`.
3. Données fournisseur : écris `vendordata.json` (CA, NTP), MR, `kolla-ansible reconfigure -t nova`. Recrée `e18-vm` et vérifie : la racine est dans le magasin de l'instance, chrony utilise 10.10.52.1. Que se passe-t-il si tes données utilisateur contiennent elles aussi `ntp:` ?
4. Crée `e18-sans-dhcp` et `e18-cd` **sans** config drive : que se passe-t-il au démarrage (console) ? Recrée-la **avec** `--use-config-drive` : comment l'instance obtient-elle son adresse ?
5. Expérience : arrête `neutron_ovn_metadata_agent` sur le calcul de `e18-vm`, recrée une instance sur ce calcul (`--host` ou `--availability-zone nova:<hôte>`, en administrateur) : symptômes, durée, journaux. Relance l'agent.
6. Écris pour Nadia, dans `docs/cloud/diagnostic-cloud-init.md`, la marche à suivre « l'instance ignore sa configuration » (de la console aux journaux des agents).

**Critères de réussite**
- [ ] `vendordata.json` est dans le dépôt (branche `main`) et dans la configuration générée de `nova-metadata` sur `osctl01`.
- [ ] Dans `e18-vm` : cloud-init a terminé sans erreur, `/etc/medisphere/role` contient `web`, chrony a 10.10.52.1 pour source.
- [ ] `e18-cd` est `ACTIVE`, avec config drive, sur un réseau sans DHCP, et a reçu son adresse.
- [ ] `neutron_ovn_metadata_agent` tourne sur les deux calculs.

**Vérification** : `lab/bin/check 10 18` (avec `e18-vm` et son IP flottante)

<details><summary>Indice 1</summary>

`sudo ip netns` sur le calcul liste les espaces `ovnmeta-…` ; `sudo ip netns exec ovnmeta-<id> ip a` montre 169.254.169.254. Le proxy y est un `haproxy` lancé par l'agent.
</details>

<details><summary>Indice 2</summary>

cloud-init expose les métadonnées à ses gabarits Jinja : une donnée utilisateur qui commence par `## template: jinja` peut utiliser `{{ ds.meta_data.meta.role }}` (vérifie le chemin exact avec `cloud-init query --all` dans l'instance).
</details>

<details><summary>Indice 3</summary>

Sans DHCP, pas de port de métadonnées dans le réseau. Le config drive est un petit disque (étiquette `config-2`) qui porte les mêmes fichiers, dont `network_data.json` : cloud-init en déduit une configuration réseau statique.
</details>

**Pour aller plus loin** (facultatif) : les données fournisseur **dynamiques** (`DynamicJSON`, `vendor_data2.json`) interrogent un service externe à chaque démarrage : imagine un service qui inscrirait l'instance dans NetBox. Quels risques (disponibilité, sécurité) ?

---

### M10-E19 — Exploiter le calcul : migrer, évacuer, désactiver  `LAB` `★★`

> **Ticket CHG-1129** — *De : Nadia Roussel*
> Jeudi, mise à jour du noyau de `oscmp02` avec redémarrage. MédiAgenda recette tourne dessus et l'équipe fait des démonstrations toute la semaine : on vide le calcul **sans** arrêter les instances, on le met à jour, on le remet en service. Et je veux qu'on ait répété le pire : un calcul qui meurt d'un coup, ses instances relancées ailleurs, sans les démarrer en double.

**Objectifs pédagogiques**
- Désactiver un calcul pour l'ordonnanceur, migrer à chaud et à froid, redimensionner, et confirmer.
- Évacuer les instances d'un calcul en panne, après l'avoir **isolé** (*fencing*), et comprendre ce que fait le calcul à son retour.
- Lire ce que Placement et Nova savent d'un calcul (services, hyperviseurs, allocations, migrations).

**Prérequis** : M10-E10 (disques sur Ceph), M10-E13.
**Durée indicative** : 3 h.

**Contexte technique**
- Avec les disques sur Ceph, une migration à chaud ne copie que la mémoire ; libvirt de chaque calcul joint celui de l'autre sur le réseau OS-API.
- Commandes : `openstack compute service set` (`--disable`, `--disable-reason`, `--down`), `openstack server migrate` (`--live-migration`, `--host`, `--wait`), `openstack server migration list|confirm|revert`, `openstack server resize`, `openstack server evacuate`, `openstack hypervisor list|show`, `openstack server list --host <hôte> --all-projects`. Certaines options demandent une microversion : `--os-compute-api-version`.
- Objets (projet `plateforme`) : `e19-a`, `e19-b` (`m1.petit`) sur `oscmp02`, `e19-evac` pour l'évacuation.
- Isolement d'un calcul « en panne » : arrêt brutal de sa VM (`qm stop 2103` sur `pve01`, VM du pool `lab`).

> ⚠️ **Attention** : évacuer une instance dont le calcul tourne encore la fait démarrer **deux fois** sur le même disque Ceph : corruption assurée. N'évacue qu'après avoir constaté que `oscmp02` est éteint (`qm status 2103`). Retour arrière : `qm start 2103`, attendre que `nova-compute` soit `up`, réactiver le service. Ne touche à rien d'autre sur `pve01`.

**Travail demandé**
1. Relève l'état : services de calcul, hyperviseurs, instances par hôte, allocations de Placement d'une instance (`openstack resource provider allocation show <uuid>`).
2. **Maintenance planifiée.** Désactive `oscmp02` avec une raison et un numéro de changement. Crée une instance : où va-t-elle ? Migre à chaud `e19-a` et `e19-b` vers `oscmp01` ; mesure la coupure vue de l'intérieur (un `ping` continu depuis une autre instance). Vérifie que `oscmp02` n'héberge plus rien. Redémarre `oscmp02` (à la place de la mise à jour), réactive-le, et ramène une instance par migration à froid (confirmation à donner : pourquoi ?).
3. **Redimensionnement.** Passe `e19-b` en `m1.moyen` : étapes, état `VERIFY_RESIZE`, confirmation ; et si on ne confirme pas ?
4. **Panne.** Place `e19-evac` sur `oscmp02`. Éteins brutalement `oscmp02` depuis `pve01`. Combien de temps avant que Nova le voie `down` ? Que fait `openstack server show e19-evac` ? Évacue-la vers `oscmp01` (la commande demande-t-elle l'hôte ?). Vérifie qu'elle a gardé son disque (fichier écrit avant la panne).
5. **Retour.** Redémarre `oscmp02`. Que fait `nova-compute` de l'instance évacuée en démarrant (journal `/var/log/kolla/nova/nova-compute.log`) ? Vérifie avec `virsh list --all` dans `nova_libvirt` qu'elle n'y existe plus.
6. Réponds : qui, dans un vrai centre de données, éteindrait le calcul en panne avant l'évacuation (pense à l'iLO du module 11, à Masakari) ? Note les commandes et les durées de cet exercice : elles alimenteront le runbook d'évacuation (RB-102).

**Critères de réussite**
- [ ] L'historique des migrations contient au moins une migration à chaud réussie et une migration à froid confirmée.
- [ ] `e19-evac` est `ACTIVE` sur `oscmp01` ; `oscmp02` ne l'héberge plus dans libvirt.
- [ ] Les deux services `nova-compute` sont `enabled` et `up` à la fin.
- [ ] `e19-b` est en `m1.moyen` et n'est plus en `VERIFY_RESIZE`.

**Vérification** : `lab/bin/check 10 19`

<details><summary>Indice 1</summary>

Un service désactivé reste `up` : il continue à gérer ses instances, l'ordonnanceur ne lui en donne simplement plus de nouvelles. `--disable-reason` apparaît dans `openstack compute service list --long`.
</details>

<details><summary>Indice 2</summary>

Nova considère un service `down` quand il n'a pas donné signe de vie depuis `service_down_time` (60 s par défaut). `--down` (*forced down*) dit à Nova de ne pas attendre : utile quand l'isolement est certain, dangereux sinon.
</details>

<details><summary>Indice 3</summary>

Au démarrage, `nova-compute` compare les instances de son hyperviseur aux migrations de type `evacuation` enregistrées pour lui, et détruit les copies locales de celles qui ont été évacuées. C'est pour cela que l'état de la migration compte.
</details>

**Pour aller plus loin** (facultatif) : Masakari (instances relancées automatiquement après la panne d'un calcul) : quelles briques Kolla déploierait-il, et sur quoi repose la détection ?

---

### M10-E20 — Kolla au quotidien : surcharges, reconfiguration, journaux  `LAB` `★★`

> **Ticket PLAT-1130** — *De : Karim Benali*
> J'ai vu passer trois MR où quelqu'un avait corrigé un fichier dans `/etc/kolla/nova-compute/` « pour tester », et un `reconfigure` sans étiquette qui a redémarré tout le cloud pendant la démo de Julien. On se met d'accord sur la façon de travailler : où se met une surcharge, comment on vérifie ce qu'elle va changer **avant**, comment on limite ce qu'on redémarre, où on lit les journaux. Premier cas concret : les calculs manquent de mémoire pour leurs propres conteneurs, et `oscmp02` doit être moins surchargé en processeur que `oscmp01`.

**Objectifs pédagogiques**
- Placer une surcharge au bon niveau (globale, par projet, par service, par hôte) et prévoir son effet.
- Générer et valider la configuration avant de l'appliquer ; limiter une reconfiguration par étiquettes ; savoir quel conteneur redémarre et pourquoi.
- Lire les journaux de Kolla (fichiers, conteneurs, contrôle de santé) et diagnostiquer un conteneur malsain.

**Prérequis** : M10-E13 (capacité mesurée), M10-E19.
**Durée indicative** : 2 h 30.

**Contexte technique**
- Kolla cherche les surcharges dans `etc/kolla/config/` : `<fichier>` (tous les services), `<projet>/<fichier>`, `<projet>/<service>.conf`, `<projet>/<hôte>/<fichier>` ; `global.conf` s'applique à tous les services oslo ; la liste exacte dépend du rôle (tâche `config` du rôle concerné). Les fichiers sont fusionnés section par section, et peuvent contenir du Jinja.
- Commandes : `kolla-ansible genconfig` (génère sans redémarrer), `kolla-ansible validate-config` (résultats dans `/var/log/kolla/config-validate` en cas d'écart), `reconfigure -t <étiquettes>`, `-l <hôtes>` (lis l'avertissement de la documentation sur `--limit`).
- Sur les nœuds : configuration générée `/etc/kolla/<service>/`, recopiée dans le conteneur au démarrage (`kolla_set_configs`) ; journaux `/var/log/kolla/<projet>/` ; `sudo docker ps --filter health=unhealthy`.
- Réglages voulus : `reserved_host_memory_mb = 2048` sur les deux calculs ; `cpu_allocation_ratio = 2.0` sur `oscmp02` seulement (4.0 reste la valeur sur `oscmp01`).

**Travail demandé**
1. Lis la tâche `config` du rôle `nova-cell` de ta version de Kolla (dans l'environnement `uv` de `~/src/openstack`) : liste les emplacements de surcharge que lit `nova-compute`.
2. Écris les deux surcharges au bon niveau. Avant toute MR : `kolla-ansible genconfig -t nova`, puis compare sur chaque calcul l'ancien et le nouveau `nova.conf` (garde une copie avant, ou compare au conteneur en cours : `docker exec nova_compute cat /etc/nova/nova.conf`). Seules tes lignes doivent changer.
3. `kolla-ansible validate-config -t nova` : que vérifie-t-il, et qu'est-ce qu'il ne verra jamais ?
4. Applique : `reconfigure -t nova`. Quels conteneurs ont redémarré, et sur quels nœuds (`docker ps` : colonne *Status*) ? Pourquoi `nova_compute` sur les deux calculs, alors qu'une surcharge ne concerne que `oscmp02` ? Vérifie dans Placement les inventaires `MEMORY_MB` (réservé) et `VCPU` (ratio) des deux calculs.
5. **Journaux.** Passe Neutron en `debug` pendant dix minutes (surcharge), reproduis une création de port, retrouve la requête dans `/var/log/kolla/neutron/neutron-server.log` par son `req-…`, puis retire le mode `debug`. Où et comment les journaux sont-ils tournés (conteneur `cron`) ?
6. **Conteneur malsain.** Liste les conteneurs `unhealthy` des trois nœuds. Lis la commande de contrôle de santé d'un conteneur (`docker inspect --format '{{json .Config.Healthcheck}}' <conteneur>`) et explique-la.
7. Écris dans le README de `plateforme/openstack` la section « Changer la configuration » : où, comment prévisualiser, quelles étiquettes, ce qui est interdit.

**Critères de réussite**
- [ ] Les surcharges sont dans le dépôt (branche `main`) au niveau voulu ; la configuration générée de `nova-compute` porte `reserved_host_memory_mb = 2048` sur les deux calculs et `cpu_allocation_ratio = 2.0` sur `oscmp02` seulement.
- [ ] Placement le confirme : `MEMORY_MB` réservé 2048 sur les deux calculs, ratio `VCPU` 2.0 sur `oscmp02` et différent sur `oscmp01`.
- [ ] Neutron n'est plus en mode `debug` ; aucun conteneur `unhealthy` sur les trois nœuds.
- [ ] Le README de `plateforme/openstack` contient la section « Changer la configuration ».

**Vérification** : `lab/bin/check 10 20`

<details><summary>Indice 1</summary>

Pour un réglage propre à un hôte, Kolla lit `<projet>/<nom d'hôte>/<fichier>` ; le nom d'hôte est celui de l'inventaire. Un réglage qui ne concerne que `nova-compute` peut aller dans `nova/nova-compute.conf`.
</details>

<details><summary>Indice 2</summary>

Un conteneur Kolla redémarre quand sa configuration générée change (gestionnaire « Restart … container »). Si `nova_compute` de `oscmp01` redémarre aussi, compare son `nova.conf` avant et après : qu'est-ce qui a changé chez lui ?
</details>

<details><summary>Indice 3</summary>

`debug = True` dans `[DEFAULT]` d'une surcharge `neutron.conf`, puis `reconfigure -t neutron`. Le niveau `debug` journalise les corps de requêtes de certains clients : à ne pas laisser en place.
</details>

**Pour aller plus loin** (facultatif) : Kolla accepte aussi des variables par hôte dans l'inventaire (`host_vars`). Quand préférer une variable de `globals.yml` à une surcharge INI ? Cherche une variable Kolla qui fait déjà ce que fait une de tes surcharges.

---

### M10-E21 — Revue : la configuration Kolla du prestataire  `REV` `★★`

> **Ticket PLAT-1131** — *De : Claire Morel* — *Copie : Karim Benali*
> Avant de partir, InfoGér nous avait proposé « une configuration Kolla clé en main, testée chez un autre client » pour notre cloud. Notre direction demande pourquoi on ne l'a pas simplement reprise. Fais-en une revue écrite : chaque défaut, sa gravité, ce qu'il aurait cassé **chez nous**, la correction. Elle me servira aussi à expliquer à la direction le coût caché d'une configuration « clé en main ».

**Objectifs pédagogiques**
- Relire une configuration Kolla-Ansible en la confrontant à l'architecture réelle (réseaux, VIP, VRRP, stockage, sécurité).
- Repérer les défauts de sécurité (secrets, TLS, clés trop puissantes, registre non vérifié) et de fonctionnement (adresses, interfaces, pilotes, versions).
- Rédiger une revue utile à deux publics : l'équipe et la direction.

**Prérequis** : M10-E04, M10-E10, M10-E12, M10-E16.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Fichiers : `ressources/M10-E21/` (`MR-infoger.md`, `globals.yml`, `multinode`, `config/glance/ceph.conf`, `config/glance/ceph.client.glance.keyring`). Les secrets qu'ils contiennent sont **fictifs**.
- Architecture voulue : celle du module (introduction, PLAN §4.9) et de ton dépôt actuel.

**Travail demandé**
1. Lis tout sans rien noter. Puis réponds : sur quelle adresse les API répondraient-elles ? Quelles interfaces Kolla toucherait-il sur `osctl01` ? Avec quelle identité Ceph les services liraient-ils et écriraient-ils ?
2. Rédige la revue en tableau : n°, fichier et ligne(s), défaut, catégorie (sécurité, fonctionnement, exploitation), gravité (critique, élevée, moyenne, faible), impact concret dans **notre** lab, correction.
3. Classe les défauts par ordre de traitement ; justifie les trois premiers.
4. Propose les lignes corrigées de `globals.yml`.
5. Pour la direction, dix lignes : pourquoi une configuration « testée ailleurs » ne se reprend pas telle quelle.

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Au moins 14 défauts identifiés, dont tous les défauts critiques et élevés du corrigé.
- [ ] Chaque défaut a un impact concret dans le lab et une correction précise (variable, valeur).
- [ ] Le texte pour la direction est compréhensible sans connaître OpenStack.

<details><summary>Indice 1</summary>

Confronte chaque adresse, chaque numéro VRRP et chaque nom d'interface au PLAN : à qui appartient déjà cette adresse ? Quel service utilise déjà ce VRID sur ce VLAN ? Que devient l'adresse d'une interface quand Kolla la branche dans un pont OVS ?
</details>

<details><summary>Indice 2</summary>

Pour chaque variable à `yes`/`no`, demande-toi quelle est la valeur par défaut de Kolla 2026.1, et si le fichier la change dans le bon sens. Relis aussi ce que Kolla attend comme utilisateur cephx de Nova, et ce que contient le trousseau fourni.
</details>

<details><summary>Indice 3</summary>

Cherche tout ce qui ressemble à un secret, à une version, à un registre, et tout ce qui consomme de la mémoire.
</details>

**Pour aller plus loin** (facultatif) : écris un contrôle automatique (script ou job de CI) qui aurait refusé ce `globals.yml` : VIP dans le plan d'adressage, VRID unique, interfaces distinctes, aucun mot de passe hors de `passwords.yml`.

---

### M10-E22 — Runbook : accueillir une équipe sur OpenStack  `RED` `★★`

> **Ticket PLAT-1132** — *De : Nadia Roussel* — *Copie : Claire Morel*
> Après MédiAgenda, MédiDoc et MédiNotif vont demander leurs projets. Je ne veux pas que ça dépende de toi : écris **RB-100**, de la demande de l'équipe à son premier `openstack server list` réussi, avec les contrôles, ce qu'on ne fait **jamais** (donner `admin`, partager un mot de passe), et la sortie d'une équipe. Je le jouerai avec une équipe fictive.

**Objectifs pédagogiques**
- Enchaîner Keystone, quotas, OpenTofu, accès et documentation en une procédure exécutable par l'astreinte.
- Rendre chaque étape vérifiable, réversible, et sûre (moindre privilège, secrets).
- Écrire aussi le chemin inverse : retirer une équipe sans laisser d'orphelins.

**Prérequis** : M10-E13, M10-E15, M10-E16, M10-E17, M10-E23 (rôles de lecture et de support, si tu l'as fait).
**Durée indicative** : 2 h.

**Contexte technique**
- Emplacement : `docs/cloud/runbooks/RB-100-accueillir-une-equipe.md` dans `plateforme/medisphere`, sur le modèle de RB-060 (M06-E23).
- Une équipe demande : un ou deux projets (dev, prod), des personnes (comptes déjà existants ou à créer dans le domaine `medisphere`), un volume de ressources, un accès pour sa CI.
- Les comptes Keystone sont locaux au domaine `medisphere` en attendant la fédération (module 24). Projets, groupes, comptes et attributions se déclarent dans le code d'identité de E05 (`donnees/identite.yml` de `plateforme/openstack`) ; les comptes de service, dans le domaine `Default`.
- Équipe fictive pour le jouer : `medidoc` (projets `medidoc-dev`, `medidoc-prod`, groupe `equipe-medidoc`).

**Travail demandé**
Rédige RB-100 avec au moins : quand l'utiliser et ce qui n'en relève pas ; informations à obtenir de l'équipe (formulaire) ; prérequis (droits, secrets, outils) ; étapes numérotées avec commande ou écran, résultat attendu et quoi faire sinon : projets et étiquettes, groupe et rôles (jamais `admin`), comptes et premier mot de passe (canal de remise), quotas et socle réseau (MR sur `envs/openstack-projets`), quotas Octavia, application credential de la CI (qui la crée, où elle est stockée, expiration), `clouds.yaml` et CA remis à l'équipe, accès Horizon et flux, contrôle final **par un membre de l'équipe** ; registre des secrets et documentation ; retrait d'une équipe (ordre inverse : ressources des projets, socle, quotas, rôles, comptes, projets) ; pièges connus. Joue-le avec `medidoc`, corrige chaque hésitation, puis fais-le relire par MR (Nadia, Sophie).

**Critères de réussite** (auto-évaluation avec le corrigé)
- [ ] Quelqu'un qui n'a pas fait le module l'exécute sans question ; chaque étape a son contrôle.
- [ ] L'ordre respecte les dépendances (projet avant socle réseau, groupe avant rôles, rôles avant contrôle par l'équipe).
- [ ] Aucun mot de passe ni secret ne transite en clair ; aucune étape ne donne `admin`.
- [ ] Le retrait ne laisse ni ressource orpheline (port, IP flottante, volume, répartiteur), ni rôle, ni application credential.

**Pour aller plus loin** (facultatif) : quelles étapes un pipeline pourrait-il enchaîner à partir d'un fichier de demande versionné (`equipes/<equipe>.yml`) ? Esquisse-le.

---

### M10-E23 — Politiques d'accès et rôles de lecture  `LAB` `★★★`

> **Ticket SEC-1133** — *De : Sophie Laurent*
> Deux demandes pour l'audit HDS. Moi, je dois pouvoir **tout voir** dans les projets des équipes, sans rien pouvoir modifier, et les nouveaux projets doivent m'être visibles sans que quelqu'un pense à m'ajouter. Nadia et le support doivent pouvoir redémarrer, arrêter et démarrer une instance « bloquée » d'une équipe, et lire sa console, mais ni la créer, ni la supprimer, ni toucher aux volumes ou aux réseaux. Aujourd'hui, la seule façon de les aider est de leur donner `member`, c'est-à-dire tout.

**Objectifs pédagogiques**
- Utiliser les rôles par défaut des politiques OpenStack 2026.1 (`reader`, `member`, `manager`, `admin`) et leur portée (*scope*), et les attributions héritées (`--inherited`).
- Écrire une politique personnalisée minimale pour un rôle nouveau, la déployer par Kolla (service **et** Horizon), et la tester sans rien casser.
- Prouver par des essais ce qu'un rôle permet et refuse.

**Prérequis** : M10-E05, M10-E13, M10-E17.
**Durée indicative** : 3 h.

**Contexte technique**
- OpenStack 2026.1 : les « nouvelles politiques par défaut » sont appliquées (`enforce_new_defaults` vaut `true` dans oslo.policy depuis la série 2024.2, et l'option `enforce_scope` est en cours de retrait : la vérification de portée est toujours faite). Keystone (`keystone-manage bootstrap`) crée les rôles `admin`, `manager`, `member`, `reader` et la chaîne d'implications `admin` → `manager` → `member` → `reader`.
- Nova : règles de base `project_reader_api`, `project_member_api`, `project_manager_api`, `context_is_admin` ; actions `os_compute_api:servers:reboot`, `…:start`, `…:stop`, `os_compute_api:os-console-output`, `os_compute_api:os-remote-consoles`… (référence : *Nova Policies* de la documentation 2026.1, ou `oslopolicy-sample-generator --namespace nova` dans le conteneur `nova_api`).
- Kolla : une surcharge `etc/kolla/config/<service>/policy.yaml` est déployée vers le service ; Horizon a ses propres copies (`etc/kolla/config/horizon/<service>_policy.yaml`) pour savoir quels boutons afficher.
- Comptes et groupes (domaine `medisphere`, à ajouter au code d'identité de E05 : `donnees/identite.yml`, mots de passe initiaux dans `donnees/vault-identite.yml`) : comptes `sophie.laurent` et `nadia.roussel` ; `sophie.laurent` dans un nouveau groupe `equipe-securite` ; `nadia.roussel` dans un nouveau groupe `equipe-support` ; nouveau rôle `support` (le playbook de E05 ne crée pas de rôle : ajoute la tâche, module `openstack.cloud.identity_role`). Clouds à ajouter sur `adm01` : `medisphere-audit` (`sophie.laurent`, projet `mediagenda-prod`) et `medisphere-support` (`nadia.roussel`, projet `mediagenda-dev`), mots de passe dans `secure.yaml`.

**Travail demandé**
1. **Comprendre.** Pour `reader`, `member`, `manager` : écris dans ton journal ce que chacun permet sur une instance de Nova, d'après la référence des politiques (trois actions par rôle). Que donne `admin` sur `mediagenda-dev` (rappel E13) ?
2. **Audit.** Dans le code d'identité de E05 (`donnees/identite.yml`, rejoué par `playbooks/identite.yml`), crée `equipe-securite`, ajoute Sophie, et donne au groupe `reader` sur le **domaine** `medisphere` en attribution **héritée** (si le module `role_assignment` de ta version de `openstack.cloud` ne sait pas exprimer l'héritage, fais cette attribution par la CLI et documente l'écart dans `donnees/identite.yml`). Crée un projet jetable `essai-heritage` : Sophie le voit-elle sans action supplémentaire ? Supprime-le. Avec `medisphere-audit`, liste les instances, volumes, réseaux et piles de `mediagenda-prod` ; puis essaie de créer un volume : code et message ?
3. **Support.** Toujours par le code d'identité : crée le rôle `support`, le groupe `equipe-support` (Nadia), et donne au groupe `support` sur `mediagenda-dev` et `mediagenda-prod` (pourquoi pas sur le domaine ?). Écris la surcharge de politique de Nova : `support` (dans le projet) peut `reboot`, `start`, `stop`, lire la sortie console et ouvrir une console distante ; rien d'autre ne change. Le support doit aussi **voir** les instances : `reader` en plus, ou la règle dans la politique ? Décide.
4. Avant de déployer : vérifie la syntaxe de ta politique (`oslopolicy-checker` ou `oslopolicy-policy-generator` dans le conteneur `nova_api`, à défaut un `yamllint`) et liste les règles qu'elle modifie. Déploie par MR (`-t nova,horizon`), avec la copie pour Horizon.
5. **Tester.** Avec `medisphere-support` : liste les instances de `mediagenda-dev`, redémarre une instance de test, affiche sa console ; puis essaie de la supprimer, de créer un volume, de changer un groupe de sécurité. Note chaque code. Dans Horizon, connecte-toi comme Nadia : quels boutons voit-elle ?
6. Écris la matrice « rôle × action » dans `docs/cloud/roles.md` (une colonne par rôle : `reader`, `support`, `member`, `manager`, `admin`), avec un renvoi vers la politique.

**Critères de réussite**
- [ ] `equipe-securite` a `reader` hérité sur le domaine `medisphere`, et rien d'autre ; Sophie a donc `reader`, et seulement `reader`, sur `mediagenda-dev` et `mediagenda-prod`.
- [ ] Le rôle `support` existe ; `equipe-support` l'a sur les deux projets de MédiAgenda, sans `member`.
- [ ] La politique de Nova du dépôt (branche `main`) mentionne `support`, et la configuration générée de `nova-api` et de Horizon la contient.
- [ ] Avec `medisphere-support`, la liste des instances de `mediagenda-dev` fonctionne ; avec `medisphere-audit`, celle de `mediagenda-prod` aussi.

**Vérification** : `lab/bin/check 10 23`

<details><summary>Indice 1</summary>

`openstack role add --group <groupe> --group-domain medisphere --domain medisphere --inherited reader` : l'attribution s'applique aux projets du domaine, pas au domaine lui-même. `openstack role assignment list --effective --user <utilisateur> --user-domain medisphere --names` montre ce qu'elle produit.
</details>

<details><summary>Indice 2</summary>

Une règle de politique se réécrit entière : `"os_compute_api:servers:reboot": "rule:project_member_or_admin or (role:support and project_id:%(project_id)s)"`. Garder la règle par défaut dans ta version, plutôt que la recopier de mémoire : lis-la dans le fichier d'exemple généré par ta version de Nova.
</details>

<details><summary>Indice 3</summary>

Avant de redémarrer, Nova doit **trouver** l'instance : la lecture (`os_compute_api:servers:show`) passe par sa propre règle. Sans droit de lecture, le support reçoit une erreur 404, pas 403.
</details>

**Pour aller plus loin** (facultatif) : le rôle `manager` (« chef de projet ») est encore inégalement pris en charge selon les services. Cherche dans la documentation 2026.1 de Nova et de Keystone ce qu'il permet, et s'il conviendrait à Julien pour gérer les membres de son équipe.
