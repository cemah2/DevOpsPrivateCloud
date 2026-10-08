# Module 10 — Palier 3 : Production

OpenStack tourne : Keystone, Glance, Nova, Neutron/OVN, Cinder, Heat, Horizon et Octavia répondent derrière les VIP, le stockage est sur `ceph-par1`, les projets de MédiAgenda existent, OpenTofu et Heat créent des environnements, Horizon est ouvert aux équipes. Mais rien de tout cela n'est encore un **service**. Personne ne sait ce qui s'arrête quand `osctl01` tombe, ni comment rendre la base d'hier ; aucune sonde ne dit que les calculs sont « down » avant que Julien ne l'écrive dans un ticket ; le trafic interne aux API circule en clair et le certificat externe expirera le jour où quelqu'un oubliera de le renouveler ; personne n'a jamais mis à jour Kolla, ni sorti un hyperviseur pour maintenance. Claire Morel veut une plateforme exploitable par l'astreinte de Nadia ; Sophie Laurent veut un plan de contrôle chiffré et cloisonné ; Julien veut que son équipe crée ses environnements **seule**. Ce palier fait passer le cloud en production.

> ⚠️ **Rappel** : `osctl01` porte **tout** le plan de contrôle (API, MariaDB, RabbitMQ, bases OVN, passerelle réseau des IP flottantes). Avant chaque intervention sur un nœud OpenStack :
> 1. vérifie l'accès de secours : console série (`qm terminal 2101` sur `pve01`, sortie par `Ctrl+O`) et agent QEMU (`qm guest cmd 2101 ping`) ;
> 2. prends un instantané des trois nœuds **ensemble** (`ms-snapshot --prefix avant-<sujet> 2101 2102 2103`, M02-E11) : un instantané d'un seul nœud n'a pas de sens pour un plan de contrôle qui parle aux calculs ;
> 3. vérifie que `ceph-par1` est `HEALTH_OK` : les exercices de ce palier lisent Ceph, ils ne le modifient pas (sauf le nettoyage explicitement demandé en E25) ;
> 4. note la commande de retour arrière **avant** de lancer la commande aller.
>
> Revenir à un instantané fait revenir **les trois nœuds** dans le passé, mais **pas** Ceph : un volume ou une image créés entre-temps deviennent orphelins. C'est un filet, pas une méthode.

**Chemin imposé** (introduction du module) : la configuration de Kolla vit dans le projet GitLab `plateforme/openstack` (clone `~/src/openstack` sur `adm01`) et change par MR ; ce palier range ses réglages dans des fichiers séparés `etc/kolla/globals.d/<NN>-<sujet>.yml` (Kolla-Ansible les lit après `globals.yml`, par ordre alphabétique) et ses surcharges de services dans `etc/kolla/config/`. Toute configuration d'un hôte **hors Kolla** (sauvegarde, sonde, unités systemd) passe par un rôle Ansible de `plateforme/ansible` ; tout flux traversant la bordure est une ligne de `host_vars/gw01/pare_feu.yml` (même matrice sur `gw02`) ; tout secret est en Vault (identité `critique`) et inscrit au registre des secrets ; la documentation va dans `plateforme/medisphere`, sous `docs/cloud/` (`adr/`, `runbooks/`, `tests/`, `changements/`, `capacite/`).

**Commandes** : comme en M10-E04, Kolla-Ansible est lancé depuis `~/src/openstack` par `uv run kolla-ansible <action> -i inventaire/multinode --configdir etc/kolla`, l'identité Vault `critique` étant fournie par l'`ansible.cfg` du projet (script client `outils/vault-pass-client.sh`, M10-E03). La CLI `openstack` (10.x, `uv tool`) utilise les clouds de `~/.config/openstack/clouds.yaml` (`medisphere-admin`, `medisphere-plateforme`, `medisphere-mediagenda-dev`).

**VMs** : aucune nouvelle VM Proxmox dans ce palier. Les instances d'essai sont des **instances OpenStack** (préfixes imposés dans chaque exercice), détruites à la fin de l'exercice qui les crée.

Les vérifications se lancent **depuis `adm01`** (`lab/bin/check 10 XX`). Elles lisent OpenStack avec le cloud désigné par `WB_OS_CLOUD` dans `lab/lab.env` (par défaut `medisphere-admin`) et les nœuds en SSH (compte `admin`, `sudo -n` en lecture).

**Ordre conseillé** : E24 → E25 → E26 → E27 → E28 → E29 → E30 → E31 → E33 → E32 → E34. Durée totale indicative : 28 à 34 heures.

---

### M10-E24 — La haute disponibilité du plan de contrôle  `LAB` `★★★`

> **Ticket PLAT-1150** — *De : Claire Morel*
> Le comité de direction me pose une question simple : « si le serveur de contrôle du cloud tombe, qu'est-ce qui s'arrête pour MédiAgenda, et combien de temps ? ». Je ne veux pas une intuition, je veux des **mesures**.
> Et puisqu'on n'a qu'un contrôleur, je veux le plan chiffré pour passer à trois : ce qui change dans la configuration, ce que ça coûte en mémoire, ce que ça protège vraiment. On ne le fait pas maintenant : on n'a pas les 48 Go.

**Objectifs pédagogiques**
- Classer les composants d'un déploiement Kolla : points d'entrée, services sans état, services à état, plan de données, passerelle réseau.
- Comprendre les mécanismes de haute disponibilité de Kolla : keepalived et HAProxy, MariaDB (Galera) derrière ProxySQL, RabbitMQ et ses files *quorum*, bases OVN en cluster Raft, memcached.
- Mesurer ce qu'une panne du contrôleur coupe, et ce qu'elle ne coupe **pas** (plan de données).
- Dimensionner un plan de contrôle à trois nœuds sans le déployer.

**Prérequis** : M10-E04 (déploiement), M10-E08 et E12 (réseau externe, IP flottantes), M10-E16 (Octavia), M10-E19 (exploiter le calcul), M07-E24 (VRRP et numéros de routeur virtuel).
**Durée indicative** : 3 h 30.

**Contexte technique**
- `osctl01` est dans les groupes `control`, `network`, `monitoring` et `storage` de l'inventaire ; `oscmp01` et `oscmp02` dans `compute`. Les VIP 10.10.50.200 (interne, `openstack-int.par1.medisphere.internal`) et 10.10.50.201 (externe, `openstack.par1.medisphere.internal`) sont portées par keepalived sur `ens18`, numéro de routeur virtuel **150** (le VRID 50 est celui des passerelles sur le VLAN 50).
- Configuration **générée** par Kolla sur les nœuds : `/etc/kolla/<service>/` ; journaux : `/var/log/kolla/<service>/` (lien vers le volume `kolla_logs`).
- Page de statistiques d'HAProxy : `http://10.10.50.51:1984/`, compte `haproxy`, mot de passe `haproxy_password` de `passwords.yml` (à lire avec `ansible-vault view`, **jamais** sur une ligne de commande).
- Instances d'essai, projet `plateforme`, gabarit `m1.petit`, image Debian 13, réseau `reseau-plateforme` du projet (M10-E07, E08), groupe de sécurité qui autorise ICMP et SSH depuis 10.10.10.0/24 : `ha-essai01` **sur `oscmp01`**, `ha-essai02` **sur `oscmp02`**, une IP flottante sur `ha-essai01`. Elles sont détruites à la fin de l'exercice.

> ⚠️ **Attention** : l'étape 5 arrête brutalement `osctl01`. Pendant ce temps, aucune API ne répond, Horizon est inaccessible, et une sauvegarde planifiée échouerait. Choisis un moment sans pipeline ni sauvegarde en cours, prends l'instantané des trois nœuds, et garde la console de `osctl01` ouverte. Retour arrière : `qm start 2101` ; si MariaDB ne redémarre pas seul après un arrêt brutal, la procédure de reprise de Kolla s'appelle depuis `adm01` (sous-commande `mariadb-recovery`). En dernier recours, reviens à l'instantané **des trois nœuds**.

**Travail demandé**
1. **Cartographie.** Sur chaque nœud, liste les conteneurs (`docker ps --format '{{.Names}}\t{{.Status}}'`). Classe-les dans un tableau à cinq colonnes : point d'entrée, API sans état, service à état (où sont ses données : volume Docker, base), plan de données (ce qui fait vivre une instance déjà démarrée), passerelle réseau. Pour chaque service à état, note où il garde ses données (`docker volume ls`, `docker inspect`).
2. **Points d'entrée.** Lis `/etc/kolla/keepalived/keepalived.conf` sur `osctl01` : numéro de routeur virtuel, mode des annonces (multicast ou unicast), priorité, script de surveillance. Retrouve les VIP sur `ens18` (`ip -br addr show ens18`). Sur la page de statistiques d'HAProxy, relève quels services écoutent sur la VIP interne, lesquels sur la VIP externe, lesquels sur les deux. Explique pourquoi un VRID de 50 sur ce VLAN aurait été une catastrophe silencieuse, et ce qui la rendrait visible.
3. **Les services à état.** Pour chacun, relève l'état « à un nœud » et ce que deviendrait la règle de quorum à trois :
   - MariaDB : taille du cluster Galera (`wsrep_cluster_size`, `wsrep_local_state_comment`) ; rôle de ProxySQL devant elle (qui parle à qui ?) ;
   - RabbitMQ : `rabbitmqctl cluster_status` et le **type** des files (`rabbitmqctl list_queues name type`) : combien de *quorum*, combien de *classic*, et pourquoi ;
   - OVN : état des bases Nord et Sud (cluster Raft, chef, membres) ;
   - memcached et les jetons Fernet de Keystone : que se passe-t-il pour un jeton émis juste avant une panne ?
4. **Préparer la mesure.** Crée `ha-essai01` et `ha-essai02` (placement imposé sur chaque calcul : c'est une opération d'administrateur), l'IP flottante, et vérifie que `ha-essai01` joint `ha-essai02` par son adresse privée. Depuis `adm01`, lance trois mesures horodatées en parallèle, à la seconde : (a) ping de l'IP flottante ; (b) depuis `ha-essai01` (session SSH ouverte **avant** la panne), ping de l'adresse privée de `ha-essai02` ; (c) une demande de jeton Keystone (`openstack token issue`) toutes les 5 secondes. Écris un petit script qui produit, pour chaque mesure, les intervalles d'indisponibilité.
5. **Trois pannes, du plus doux au plus dur.** Pour chacune : heure de début, ce que montrent les trois mesures, ce que montrent `openstack compute service list` et `openstack network agent list` une fois les API revenues, durée de reprise.
   1. `docker stop haproxy` sur `osctl01` pendant 2 minutes, puis redémarrage. Que fait keepalived ?
   2. `docker stop rabbitmq` pendant 3 minutes. Les lectures d'API fonctionnent-elles ? Une création d'instance ? Au bout de combien de temps les `nova-compute` apparaissent-ils `down`, et pourquoi ce délai ?
   3. arrêt **brutal** de la VM : `qm stop 2101` sur `pve01`, 5 minutes, puis `qm start 2101`. Mesure le temps jusqu'au retour de chaque service. MariaDB a-t-elle redémarré seule ?
6. **Analyse.** Rédige `docs/cloud/haute-disponibilite.md` dans `plateforme/medisphere` : la cartographie, les mesures (tableau composant / effet de la perte / ce qui continue / durée de reprise mesurée), et la réponse à la question de Claire en cinq lignes pour le comité de direction. Distingue nettement le **plan de contrôle** (créer, modifier, lister) et le **plan de données** (instances qui tournent, trafic est-ouest, trafic nord-sud par les IP flottantes, volumes).
7. **Le plan à trois.** Dans `plateforme/openstack`, ajoute un fichier `inventaire/multinode.3-controleurs.exemple` (non utilisé par les déploiements) qui décrit trois contrôleurs `osctl01-03` et ce qui change dans `globals.yml`. Dans la même page de documentation : mémoire, cœurs et adresses nécessaires, ordre d'ajout des contrôleurs (procédure officielle *Adding and removing hosts*), répartition de la passerelle OVN sur plusieurs nœuds, et ce que trois contrôleurs ne protègent **pas** (Ceph, la bordure, une erreur de configuration poussée partout).
8. **Ménage.** Détruis les instances `ha-essai*` et l'IP flottante ; vérifie que tous les conteneurs sont sains.

**Critères de réussite**
- [ ] Les VIP 10.10.50.200 et 10.10.50.201 sont portées par `ens18` de `osctl01` ; keepalived utilise le VRID 150 ; la page de statistiques d'HAProxy répond (authentifiée).
- [ ] Après les trois pannes, aucun conteneur n'est `unhealthy` ni arrêté ; tous les services de calcul, de réseau et de volume sont `up`.
- [ ] `docs/cloud/haute-disponibilite.md` est sur `main` de `plateforme/medisphere` : cartographie, durées de reprise **mesurées** pour les trois pannes, distinction plan de contrôle / plan de données, plan à trois contrôleurs chiffré.
- [ ] `inventaire/multinode.3-controleurs.exemple` est sur `main` de `plateforme/openstack`.
- [ ] Plus aucune instance `ha-essai*` n'existe.

**Vérification** : `lab/bin/check 10 24`

<details><summary>Indice 1</summary>

Dans OVN, une instance déjà démarrée n'a besoin ni de l'API Neutron ni des bases OVN pour transmettre ses paquets : `ovn-controller` a déjà programmé les flux dans Open vSwitch sur son hyperviseur. Le trafic qui sort par une IP flottante, lui, passe par un nœud **passerelle** (*gateway chassis*) quand les IP flottantes ne sont pas distribuées. Regarde où est la passerelle du routeur de ton projet.
</details>

<details><summary>Indice 2</summary>

Un `nova-compute` est déclaré `down` quand il n'a pas rafraîchi son état depuis `service_down_time` secondes (lis la valeur par défaut dans la référence de configuration de Nova). Pour placer une instance sur un hôte donné, regarde l'option `--host` de `openstack server create` (micro-version de l'API compute requise) ou la syntaxe `--availability-zone nova:<hôte>`.
</details>

<details><summary>Indice 3</summary>

Les commandes d'administration des bases s'exécutent **dans** les conteneurs (`docker exec`). Pour MariaDB, le client demande le mot de passe s'il n'est pas sur la ligne de commande (`-p` sans valeur) : lis-le dans `passwords.yml` avec `ansible-vault view` dans un autre terminal. Pour les bases OVN, `ovn-appctl` parle au processus par son socket de contrôle (`cluster/status`) : cherche le chemin du socket dans le conteneur.
</details>

**Pour aller plus loin** (facultatif) : les IP flottantes distribuées (`neutron_ovn_distributed_fip`) et leur coût (une carte externe sur chaque calcul) ; Masakari pour redémarrer les instances d'un calcul mort ; [Kolla : *Multinode deployment*](https://docs.openstack.org/kolla-ansible/2026.1/user/multinode.html), [*Adding and removing hosts*](https://docs.openstack.org/kolla-ansible/2026.1/user/adding-and-removing-hosts.html), [OpenStack HA Guide](https://docs.openstack.org/ha-guide/), [files *quorum* de RabbitMQ](https://www.rabbitmq.com/docs/quorum-queues).

---

### M10-E25 — Sauvegarder et restaurer OpenStack  `LAB` `★★★`

> **Ticket PLAT-1151** — *De : Nadia Roussel*
> Question de l'auditeur HDS : « montrez-moi la dernière restauration du cloud ». Réponse actuelle : rien. Si le disque de `osctl01` meurt, on perd la base de tous les services : les projets, les quotas, la liste des instances et de leurs volumes, les réseaux. Les données des instances sont dans Ceph, mais sans la base, personne ne sait plus à qui elles appartiennent.
> Je veux une sauvegarde quotidienne de la base OpenStack, chiffrée, envoyée à PAR2 comme les autres, et une restauration **réalisée**, chronométrée, avec ce qu'elle laisse derrière elle.

**Objectifs pédagogiques**
- Distinguer ce qui fait l'état d'un cloud OpenStack (base, configuration, secrets, clés, données des instances) et la façon de protéger chacun.
- Mettre en œuvre la sauvegarde à chaud de MariaDB fournie par Kolla (Mariabackup) et l'intégrer à la chaîne de sauvegarde du socle (PBS, chiffrement, alerte).
- Restaurer la base et comprendre la **divergence** entre une base restaurée et un stockage qui, lui, n'est pas revenu dans le passé.

**Prérequis** : M06-E28 (rôle `sauvegarde_pbs`, PBS, jetons par hôte), M02-E26 (`ms-alerte@`), M10-E10 et E11 (Cinder sur Ceph), M10-E24 (cartographie des états).
**Durée indicative** : 4 h.

**Contexte technique**
- Kolla sait prendre des sauvegardes complètes ou incrémentales de MariaDB avec **Mariabackup**, à chaud, sans interruption. La fonction se déclare dans la configuration (fichier `etc/kolla/globals.d/25-sauvegarde.yml`), demande une reconfiguration de MariaDB, puis se déclenche depuis l'hôte de déploiement par une sous-commande de `kolla-ansible`. Kolla ne planifie rien et ne purge rien : les fichiers s'accumulent dans le volume Docker `mariadb_backup` de `osctl01`. La restauration est **manuelle** (procédure de la documentation).
- Planification imposée :
  - sur `adm01`, unités `wb-openstack-mariabackup.service` (oneshot, `User=admin`, `OnFailure=ms-alerte@%n.service`) et `.timer` (tous les jours à **01:30**, rattrapage) : sauvegarde **complète** ;
  - sur `osctl01`, le rôle `sauvegarde_pbs` de M06-E28, étendu d'un élément **`openstack`** : à **02:10**, il vérifie qu'une sauvegarde complète de moins de 26 h existe, l'envoie à PBS avec ce qu'il faut pour la relire, puis purge les copies locales de plus de 7 jours. Mêmes noms qu'au M06 : script `/usr/local/sbin/wb-backup-socle.sh`, unités `wb-backup-socle.*`, secrets `/etc/wb-backup/pbs-osctl01.env` et `.key`.
- PBS : datastore `ds-lab`, espace de noms **`par1/openstack`**, identifiant de sauvegarde `host/osctl01`, jeton `wb-backup@pbs!osctl01` limité à cet espace de noms, chiffrement côté client (clé dans Vault `critique`, *paperkey* hors ligne).
- Flux : `osctl01` (10.10.50.51) → `pbs01:8007` à travers la bordure et le tunnel `wg0`.
- Ce qui n'est **pas** le sujet : les données des instances (pools `vms`, `volumes`, `images` de `ceph-par1`), protégées par la réplication de Ceph et par Cinder Backup (M10-E11).

> ⚠️ **Attention** : la restauration (étape 6) **écrase** la base de tous les services OpenStack. Fais-la seulement après (1) une sauvegarde complète vérifiée, (2) un instantané des trois nœuds (`ms-snapshot --prefix avant-restau 2101 2102 2103`), (3) un `HEALTH_OK` de Ceph. Retour arrière : retour à l'instantané des trois nœuds (et nettoyage des orphelins Ceph, voir étape 7). Ne restaure jamais une sauvegarde dont tu n'as pas d'abord **préparé** et inspecté le contenu.

**Travail demandé**
1. **Ce qui fait l'état.** Dans ton journal, un tableau : élément (bases MariaDB par service, configuration `plateforme/openstack`, mot de passe Vault `critique`, `passwords.yml`, certificats, clés Fernet de Keystone, bases OVN Nord et Sud, volumes Docker de RabbitMQ, données Ceph), où il est, ce qu'on perd sans lui, comment il est protégé (ou pourquoi il n'a pas besoin de l'être). Pour les bases OVN, lis ce que fait l'outil `neutron-ovn-db-sync-util` : qui est la source de vérité, Neutron ou OVN ?
2. **Activer.** Active Mariabackup par MR sur `plateforme/openstack`, applique, puis prends une sauvegarde complète à la main depuis `adm01`. Retrouve-la sur `osctl01` dans le volume `mariadb_backup` : nom, taille, durée de la sauvegarde, impact mesuré sur les API (boucle de jetons de E24).
3. **Planifier sur `adm01`.** Écris les deux unités `wb-openstack-mariabackup.*` dans le rôle Ansible qui gère déjà les outils de `adm01` (ou un rôle dédié, justifié). Le service doit pouvoir déverrouiller `passwords.yml` sans mot de passe sur sa ligne de commande ni dans son unité. Valide (`systemd-analyze verify`), active, et lance-le une fois par `systemctl start`.
4. **Envoyer à PAR2.** Étends le rôle `sauvegarde_pbs` : un élément `openstack` qui (a) échoue si la plus récente sauvegarde complète a plus de 26 h, (b) envoie le fichier de sauvegarde et ce qui est nécessaire pour le **restaurer** sur un `osctl01` reconstruit (version exacte de l'image MariaDB, empreintes des images en service, clés Fernet — décide et justifie pour chacun), (c) purge les copies locales de plus de 7 jours **après** un envoi réussi. Crée le jeton PBS, ses droits, la clé de chiffrement et sa *paperkey* ; ajoute le flux ; applique par le pipeline. Vérifie le catalogue de l'instantané dans PBS.
5. **Marqueurs.** Après la sauvegarde complète que tu vas restaurer, crée dans le domaine `medisphere` un projet `essai-restauration` et, dans le projet `plateforme`, un volume de 1 Go nommé `essai-restauration-vol`. Note leurs identifiants. Ils simulent « ce qui a été fait après la dernière sauvegarde ».
6. **Restaurer.** Suis la procédure *MariaDB database backup and restore* de Kolla 2026.1, adaptée à un seul nœud : préparation de la sauvegarde dans un conteneur jetable avec la **même image** que le conteneur `mariadb`, arrêt de MariaDB par Kolla, remplacement des données, redémarrage. Chronomètre chaque étape (feuille de temps). Puis vérifie : les services sont-ils tous `up` ? Le projet `essai-restauration` existe-t-il ? Le volume ? Les instances, réseaux et projets antérieurs à la sauvegarde sont-ils là ?
7. **Ce que la restauration laisse derrière elle.** Le volume `essai-restauration-vol` a disparu de Cinder… mais pas de Ceph. Retrouve l'image RBD correspondante dans le pool `volumes` (depuis `ceph01`, en lecture), prouve qu'aucun volume Cinder ne la référence, et supprime-la de façon tracée. Écris une méthode générale de détection des orphelins (images RBD sans volume, disques d'instance sans instance) pour l'après-restauration.
8. **Documenter.** Dans `plateforme/medisphere` : `docs/cloud/sauvegarde-restauration.md` (ce qui est sauvegardé, où, comment restaurer, orphelins, RPO réel) et une section datée dans `docs/cloud/tests/restauration.md` (feuille de temps, RTO mesuré, RPO). Mets à jour le registre des secrets (jeton PBS, clé de chiffrement, *paperkey*) et la matrice des flux.

**Critères de réussite**
- [ ] Mariabackup est activé par un fichier de `etc/kolla/globals.d/` ; le volume `mariadb_backup` de `osctl01` contient une sauvegarde complète de moins de 26 h, et aucune de plus de 8 jours.
- [ ] Sur `adm01`, `wb-openstack-mariabackup.timer` est actif et le dernier passage du service a réussi ; aucun secret dans l'unité.
- [ ] Sur `osctl01`, `wb-backup-socle.timer` est actif, le dernier passage a réussi, les secrets PBS sont en `root:root 600` ; PBS contient dans `par1/openstack` un instantané `host/osctl01` de moins de 48 h, chiffré ; le jeton est limité à cet espace de noms.
- [ ] Le flux `osctl01` → `pbs01:8007` est ouvert et documenté.
- [ ] Le projet `essai-restauration` n'existe pas ; aucune image RBD du pool `volumes` n'est orpheline.
- [ ] `docs/cloud/sauvegarde-restauration.md` et le compte rendu daté (RTO, RPO) sont sur `main`.

**Vérification** : `lab/bin/check 10 25`

<details><summary>Indice 1</summary>

La page de la documentation de Kolla dit d'où l'on peut déclencher une sauvegarde, et ce dont la commande a besoin. Elle ne dit pas que `kolla-ansible` charge **toujours** `passwords.yml` : dans ton projet, ce fichier est chiffré. Un service systemd qui tourne **dans le dossier du projet** profite de son `ansible.cfg` (identité Vault par script client) ; reste à savoir si ce script trouve, sous systemd, ce dont il a besoin. Et à 01:30, avec quelle clé SSH Kolla se connecte-t-il aux nœuds ?
</details>

<details><summary>Indice 2</summary>

Les sauvegardes Mariabackup sont des flux `mbstream` compressés : on ne les « ouvre » pas, on les **extrait** puis on les **prépare** (`--prepare`) avant toute copie. Préparer sans copier permet déjà de vérifier qu'une sauvegarde est restaurable, sans toucher à rien : c'est un bon test automatique.
</details>

<details><summary>Indice 3</summary>

Le nom d'une image RBD de volume Cinder est `volume-<identifiant du volume>`. Pour lister les images d'un pool sur un cluster cephadm sans installer de client : `sudo cephadm shell -- rbd ls <pool>` sur `ceph01`. Compare avec `openstack volume list --all-projects -f value -c ID`.
</details>

**Pour aller plus loin** (facultatif) : sauvegardes incrémentales horaires et leur restauration (chaîne de préparation) ; Cinder Backup vers le stockage S3 de `s3-01` plutôt que vers le même cluster Ceph ; [Kolla : *MariaDB database backup and restore*](https://docs.openstack.org/kolla-ansible/2026.1/admin/mariadb-backup-and-restore.html), [Mariabackup](https://mariadb.com/docs/server/server-usage/backup-and-restore/mariadb-backup/), [neutron-ovn-db-sync-util](https://docs.openstack.org/neutron/2026.1/ovn/troubleshooting.html).

---

### M10-E26 — Superviser OpenStack  `LAB` `★★`

> **Ticket PLAT-1152** — *De : Nadia Roussel*
> Lundi, `oscmp02` est resté « down » pour Nova pendant six heures : RabbitMQ avait redémarré, le service de calcul ne s'est pas reconnecté. On l'a appris par Julien : « No valid host ». Prometheus arrive au module 21 ; d'ici là, je veux pour le cloud ce qu'on a pour le socle : une sonde toutes les quinze minutes, une alerte si quelque chose ne va pas, et un guide qui me dit par où commencer.

**Objectifs pédagogiques**
- Surveiller OpenStack par ce qu'il **rend** (services enregistrés, agents vivants, répartiteurs, certificats) autant que par ses processus (conteneurs, vérifications de santé de Docker).
- Donner à une sonde une identité OpenStack qui ne peut **que lire**, avec les mécanismes de Keystone (identifiants d'application, règles d'accès).
- Savoir où sont les journaux d'un déploiement Kolla et préparer l'observabilité des modules 21 et 22.

**Prérequis** : M06-E29 (`ms-verif-services`, son fichier de configuration, ses tests), M02-E26 (`ms-alerte@`), M10-E23 (rôles et politiques), M10-E24.
**Durée indicative** : 3 h.

**Contexte technique**
- Script `bin/ms-verif-openstack` dans `plateforme/outils`, tests bats, installé sous `/usr/local/bin` par `task install:systeme` ; configuration versionnée `etc/ms-verif-openstack.conf` (installée en `/usr/local/etc/ms-verif-openstack.conf`). Options : `-s|--seuil-certificats JOURS` (défaut 10), `-q|--quiet`. Codes : 0 tout va bien, 1 au moins une anomalie **ou** un contrôle impossible, 2 usage.
- Unités sur `adm01` : `ms-verif-openstack.service` (oneshot, `User=admin`, `OnFailure=ms-alerte@%n.service`) et `.timer` (toutes les 15 minutes, rattrapage).
- Identité OpenStack de la sonde : utilisateur `svc-supervision` (domaine `Default`), et un **identifiant d'application** `supervision-adm01` de cet utilisateur, muni de **règles d'accès** qui n'autorisent que la méthode `GET`. Cloud `medisphere-supervision` dans `~/.config/openstack/clouds.yaml`, secret dans `~/.config/openstack/secure.yaml` (600).
- Contrôles des nœuds en SSH depuis `adm01` (compte `admin`, `sudo -n`) : état des conteneurs, espace disque.
- Contrôles attendus (au minimum) :

  | Domaine | Contrôle |
  |---|---|
  | Points d'entrée | Keystone répond sur la VIP externe (HTTPS vérifié) ; le certificat de chaque point TLS (VIP externe, VIP interne à partir de E27) expire dans plus de 10 jours |
  | Calcul | chaque `nova-*` activé est `up` ; un service désactivé l'est **avec une raison** |
  | Réseau | chaque agent OVN est vivant (`alive`) ; la passerelle OVN est présente |
  | Volumes | `cinder-scheduler`, `cinder-volume`, `cinder-backup` sont `up` |
  | Répartiteurs | aucun répartiteur Octavia en `ERROR` ni `OFFLINE` |
  | Conteneurs | sur chaque nœud, aucun conteneur `unhealthy`, aucun conteneur Kolla arrêté |
  | Disque | `/var/lib/docker` occupé à moins de 85 % sur chaque nœud |

**Travail demandé**
1. **Lecture.** Dans la documentation de Keystone, lis *Application credentials* (portée, rôles, `unrestricted`, règles d'accès : `service`, `method`, `path`, jokers). Quelles appels l'API de `openstack compute service list` fait-elle réellement (`--debug`) ? Qu'en déduis-tu pour écrire des règles d'accès qui ne cassent pas la découverte des versions des API ?
2. **L'identité.** Crée `svc-supervision` et donne-lui le rôle strictement nécessaire pour lister les services de calcul, de réseau et de volume (lis les politiques par défaut de Nova en 2026.1 : un lecteur suffit-il ?). Crée l'identifiant d'application avec des règles d'accès limitées à `GET` sur les services nécessaires. Prouve qu'il **lit** et qu'il ne peut **pas** créer (une création refusée, sans effet). Inscris-le au registre des secrets avec ce que tu acceptes comme risque.
3. **Les journaux.** Sur `osctl01`, retrouve les journaux de `nova-api`, `neutron-server`, `keystone` et `octavia-api`. Qui les écrit (fichier, `fluentd`) ? Combien de place prennent-ils, qui les fait tourner ? Écris dans ton journal ce que M22 (Loki) devra collecter et par quel chemin.
4. **Le script.** Écris `ms-verif-openstack` et ses tests bats (commandes `openstack`, `ssh`, `openssl` simulées par des fonctions). Même contrat que `ms-verif-services` : une ligne `OK`/`KO` par contrôle, un bilan, un contrôle impossible est un `KO`. Les nœuds, les points TLS et le cloud à utiliser viennent du fichier de configuration.
5. **Les unités.** Service, timer, alerte, durcissement comme en M06-E29 (le service doit lire `~/.config/openstack/` et utiliser SSH). Valide, active, vérifie la prochaine échéance.
6. **Le rouge.** Pour chaque domaine, provoque un échec réaliste et réversible (seuil de certificats à 400 jours par un *drop-in* ; `docker stop` du conteneur `nova_compute` de `oscmp02` deux minutes ; un service désactivé sans raison ; un répartiteur d'essai dont les membres n'existent pas…), constate l'alerte, remets en état.
7. **Le guide.** Complète `docs/astreinte.md` de `plateforme/outils` : pour chaque `KO` possible, que vérifier en premier, quels journaux, quel runbook.

**Critères de réussite**
- [ ] `ms-verif-openstack` est installé sous `/usr/local/bin` ; ses tests bats passent dans le pipeline de `plateforme/outils`.
- [ ] Le timer est actif (15 minutes, rattrapage) ; le service est oneshot, tourne en `admin`, déclenche `ms-alerte@` en cas d'échec et a déjà tourné sous systemd.
- [ ] Lancé maintenant, il répond 0 ; avec un seuil de 400 jours, 1 ; avec une option inconnue, 2.
- [ ] Le journal de `adm01` contient une alerte `ms-alerte` issue de ce service (moins de 30 jours).
- [ ] Les règles d'accès de l'identifiant d'application de `svc-supervision` n'autorisent que `GET` ; `secure.yaml` est en 600.

**Vérification** : `lab/bin/check 10 26`

<details><summary>Indice 1</summary>

Avec `openstack ... -f json`, chaque liste devient un tableau d'objets : `State`, `Status`, `Alive`, `Provisioning Status`, `Operating Status`… (les noms exacts de colonnes se lisent dans la sortie de ta version). `jq` fait le reste. Pour l'état de santé Docker, `docker ps` a un filtre `health=` et un filtre `status=`.
</details>

<details><summary>Indice 2</summary>

Une règle d'accès se décrit en JSON (`service`, `method`, `path`) ; le chemin accepte des jokers (`*` pour un segment, `**` pour plusieurs). Le **type** de service est celui du catalogue (`openstack catalog list`) : vérifie-le pour les volumes. Les règles se relisent avec `openstack access rule list`.
</details>

<details><summary>Indice 3</summary>

Les services systemd durcis avec `ProtectHome=` ne voient plus `/home` : pour un service qui **doit** lire `~/.config/openstack` et `~/.ssh`, regarde `ProtectHome=read-only`. SSH en mode non interactif : `BatchMode=yes`, et un délai court.
</details>

**Pour aller plus loin** (facultatif) : l'exportateur `openstack-exporter` et les exportateurs fournis par Kolla (`enable_prometheus_*`) pour le module 21 ; [*Application credentials*](https://docs.openstack.org/keystone/2026.1/user/application_credentials.html), [Kolla : *Central logging*](https://docs.openstack.org/kolla-ansible/2026.1/reference/logging-and-monitoring/central-logging-guide.html), [Kolla : *Troubleshooting Guide*](https://docs.openstack.org/kolla-ansible/2026.1/user/troubleshooting.html).

---

### M10-E27 — Sécuriser OpenStack  `LAB` `★★★`

> **Ticket SEC-1153** — *De : Sophie Laurent*
> Revue de sécurité du cloud avant l'ouverture à MédiAgenda. Mes constats :
> 1. tout le trafic interne aux API (VIP interne, ProxySQL, services entre eux) circule en clair sur le VLAN 50 ;
> 2. le certificat de la VIP externe a été posé à la main : le jour où il expire, le cloud s'arrête ;
> 3. aucune politique de verrouillage des comptes ; les sessions Horizon durent toute la journée ;
> 4. les instances des projets peuvent-elles joindre les API et les bases du plan de contrôle ? Personne ne sait ;
> 5. les mots de passe générés à l'installation n'ont jamais tourné, et certains ont été vus par InfoGér.
> Je veux un plan de remédiation appliqué, et ce qu'on laisse en clair, écrit et justifié.

**Objectifs pédagogiques**
- Chiffrer le point d'accès interne (TLS de la VIP interne) avec la PKI interne et faire confiance à cette PKI dans les conteneurs.
- Automatiser le renouvellement des certificats des VIP par ACME (step-ca) avec le mécanisme intégré de Kolla.
- Durcir Keystone (verrouillage, exceptions des comptes de service) et Horizon (sessions).
- Cloisonner le plan de contrôle par la matrice des flux, et faire tourner des secrets de `passwords.yml`.

**Prérequis** : M06-E18 et E27 (ACME, politique de durées : certificats serveur de 30 jours renouvelés à 15 jours), M06-E30 (durcissement, matrice des flux), M10-E04 (TLS externe), M10-E23, M10-E26.
**Durée indicative** : 4 h.

**Contexte technique**
- Kolla distingue TLS **externe** (VIP externe), TLS **interne** (VIP interne) et TLS **de bout en bout** (*backend*, entre HAProxy et chaque service). Ce palier active l'interne ; le *backend* est discuté, pas imposé.
- PKI : racine `/usr/local/share/ca-certificates/medisphere-root-ca.crt`. Point ACME de `ca01` : `https://ca01.par1.medisphere.internal/acme/acme/directory`. Kolla sait obtenir et renouveler les certificats des VIP par ACME (rôle `letsencrypt`, qui accepte un autre serveur ACME que Let's Encrypt) ; le défi HTTP-01 arrive sur le port 80 des VIP.
- Noms : VIP interne `openstack-int.par1.medisphere.internal` (10.10.50.200), VIP externe `openstack.par1.medisphere.internal` (10.10.50.201).
- Réglages de ce palier dans `etc/kolla/globals.d/27-securite.yml` ; surcharges de Keystone dans `etc/kolla/config/keystone.conf`, d'Horizon dans `etc/kolla/config/horizon/_9999-custom-settings.py`.
- Politique imposée : 5 échecs d'authentification consécutifs verrouillent un compte humain 15 minutes ; sessions Horizon de 30 minutes ; certificats des VIP de 30 jours au plus, renouvelés à 15 jours de l'expiration.
- Matrice des flux visée pour les VIP : VIP externe joignable depuis MGMT (10.10.10.0/24), le VPN d'administration (10.255.1.0/24) et `runner01` ; VIP interne seulement depuis le VLAN 50 et `adm01` ; **aucun** flux des IP des instances (VLAN 52) vers le VLAN 50 ; `ca01` vers les deux VIP sur le port 80 (défis ACME).

> ⚠️ **Attention** : (1) le passage de la VIP interne en TLS change **toutes** les URL internes du catalogue et la configuration de tous les services : fais-le dans une fenêtre, après instantané des trois nœuds, et garde la commande de retour (retrait du fichier `27-securite.yml` puis `reconfigure`). (2) Un verrouillage de compte qui s'applique aux comptes de **service** (`nova`, `neutron`, `glance`…) transforme une erreur de mot de passe en panne générale : traite-les **avant** d'activer la politique. (3) La rotation d'un mot de passe de base de données ou de RabbitMQ coupe les services concernés : lis la page *Password Rotation* de Kolla et choisis les secrets à faire tourner **parmi ceux qui se reconfigurent sans étape manuelle**.

**Travail demandé**
1. **État des lieux.** Pour chaque constat de Sophie, relève l'état actuel avec une preuve (catalogue `openstack endpoint list`, `openssl s_client` sur les deux VIP, `keystone.conf` généré, réglages d'Horizon, test de connexion depuis une instance vers 10.10.50.200:5000 et 10.10.50.51:3306, date de génération de `passwords.yml` dans l'historique Git).
2. **TLS interne et confiance.** Active le TLS de la VIP interne avec un certificat de la PKI interne ; fais en sorte que les conteneurs fassent confiance à la racine MédiSphère et que les services utilisent le magasin de confiance du système ; adapte le fichier `admin-openrc` généré par Kolla et tes `clouds.yaml`. Explique dans ton journal l'effet de bord sur la base de données (ProxySQL) et ce qui reste en clair (RabbitMQ, migration à chaud libvirt, bases OVN, Ceph).
3. **Renouvellement automatique.** Confie l'obtention et le renouvellement des certificats des **deux** VIP au mécanisme ACME intégré de Kolla, pointé vers `ca01`, avec un seuil de renouvellement conforme à la politique. Ouvre le flux du défi. Prouve un premier renouvellement (date et empreinte du certificat servi avant/après), et lis où le conteneur journalise ses tentatives. Si le mécanisme ne fonctionne pas avec step-ca sur ton lab, documente l'échec (message exact) et mets en place une alternative tenue par le code, sans entorse à la politique de durées.
4. **Keystone et Horizon.** Applique la politique de verrouillage par la surcharge de `keystone.conf` et dispense explicitement les comptes de service (et le compte de la sonde E26) du verrouillage. Prouve le verrouillage sur un compte d'essai `essai-verrou` (domaine `medisphere`), puis supprime-le. Règle la durée des sessions d'Horizon.
5. **Cloisonnement.** Dans `pare_feu.yml`, traduis la matrice visée ; prouve depuis une instance d'essai `secu-essai01` (projet `plateforme`, IP flottante) qu'elle ne joint **plus** ni la VIP interne, ni les nœuds du VLAN 50, mais qu'elle joint toujours Internet ; prouve depuis `adm01` et `runner01` que l'API externe répond. Détruis l'instance d'essai.
6. **Rotation.** Fais tourner `keystone_admin_password` et un mot de passe de base de données d'un service de ton choix (parmi ceux que la documentation dit applicables par `reconfigure`), par MR (le fichier reste chiffré) ; prouve que l'ancien mot de passe administrateur est refusé et que le service est sain. Liste les secrets qui demanderaient une procédure manuelle, avec leur impact.
7. **Documenter.** `docs/cloud/securite.md` : constats, remédiations, ce qui reste en clair et pourquoi, secrets et leur rotation, risques acceptés (signés par Sophie). Registre des secrets et matrice des flux à jour.

**Critères de réussite**
- [ ] Les points de terminaison `internal` du catalogue sont en `https://openstack-int.par1.medisphere.internal…` ; les deux VIP présentent un certificat émis par la PKI MédiSphère, valide pour leur nom, de 30 jours au plus, qui expire dans plus de 10 jours.
- [ ] Le renouvellement automatique des certificats des VIP est en place (conteneurs ACME de Kolla en service, ou alternative documentée dans `securite.md`).
- [ ] `keystone.conf` généré sur `osctl01` porte la politique de verrouillage (5 échecs, 15 minutes) ; les comptes de service de Nova, Neutron, Glance, Cinder et Placement, et `svc-supervision`, en sont dispensés ; le compte `essai-verrou` n'existe plus.
- [ ] Horizon ferme les sessions au bout de 30 minutes.
- [ ] `docs/cloud/securite.md` est sur `main` ; plus aucune instance `secu-essai*`.

**Vérification** : `lab/bin/check 10 27`

<details><summary>Indice 1</summary>

Lis la page *TLS* de l'administration de Kolla 2026.1 en entier : variables d'activation, fichiers attendus dans `certificates/` (certificat **et** clé dans un même fichier pour HAProxy), copie des autorités dans les conteneurs, variable du magasin de confiance des services pour Debian. La note sur les VIP interne et externe distinctes te concerne. Lis aussi, dans les valeurs par défaut de Kolla (`group_vars/all/`), comment `database_enable_tls_internal` est calculée.
</details>

<details><summary>Indice 2</summary>

Le rôle ACME de Kolla renouvelle un certificat quand il lui reste moins de `letsencrypt_cert_valid_days` jours : avec la valeur par défaut et des certificats de 30 jours de step-ca, que se passe-t-il à chaque passage ? Le conteneur client doit aussi faire confiance à `ca01` pour parler ACME en HTTPS.
</details>

<details><summary>Indice 3</summary>

La section `[security_compliance]` de Keystone ne s'applique qu'aux utilisateurs du pilote d'identité SQL. Un utilisateur peut être dispensé par une **option de compte** (voir `openstack user set --help`). Pour Horizon, les réglages Django de session se posent dans le fichier de réglages personnalisés que Kolla recopie.
</details>

**Pour aller plus loin** (facultatif) : TLS *backend* et certificats par nœud ; RabbitMQ en TLS (`rabbitmq_enable_tls`) ; libvirt en TLS pour la migration ; Barbican pour le chiffrement des volumes ; la fédération Keycloak (module 24) pour supprimer les mots de passe locaux ; [Kolla : *TLS*](https://docs.openstack.org/kolla-ansible/2026.1/admin/tls.html), [Kolla : *Password Rotation*](https://docs.openstack.org/kolla-ansible/2026.1/admin/password-rotation.html), [Keystone : *Security compliance*](https://docs.openstack.org/keystone/2026.1/admin/configuration.html), [OpenStack Security Guide](https://docs.openstack.org/security-guide/).

---

### M10-E28 — Mettre à jour OpenStack  `LAB` `★★★`

> **Ticket CHG-1154** — *De : Karim Benali*
> Kolla-Ansible a publié des correctifs sur la branche 2026.1, et les images `2026.1-debian-trixie` ont été reconstruites depuis notre déploiement (correctifs de sécurité de Debian et d'OpenStack). On applique. Mais proprement : fiche de changement, fenêtre annoncée, mesure de l'interruption, plan de retour arrière **testé dans sa logique**, et un runbook que Nadia pourra rejouer seule dans trois mois.
> Et on ne touche **pas** à 2026.2 : Kolla n'y est qu'en version candidate.

**Objectifs pédagogiques**
- Distinguer une mise à jour **au sein** d'une série d'une montée de série (*upgrade*), et appliquer la procédure officielle qui convient.
- Savoir ce qui change vraiment : paquet `kolla-ansible`, collections Ansible, images (étiquettes mobiles, empreintes).
- Préparer, exécuter et vérifier un changement sur un plan de contrôle sans redondance, en mesurant l'interruption.

**Prérequis** : M10-E03 (projet `uv`, `install-deps`), M10-E24 (mesures de continuité), M10-E25 (sauvegarde vérifiée), M05-E31 (montée de version délibérée d'un outil).
**Durée indicative** : 3 h 30, dont une fenêtre d'1 h.

**Contexte technique**
- Version de Kolla-Ansible épinglée dans `pyproject.toml`/`uv.lock` de `plateforme/openstack` ; contrainte d'ansible-core **≥ 2.19.1, < 2.21** ; collections Ansible installées par `kolla-ansible install-deps`.
- Les images de Kolla portent une étiquette **mobile** (`openstack_tag` vaut `2026.1-debian-trixie`) : la même étiquette désigne une image différente après chaque reconstruction. Seule l'**empreinte** (`RepoDigests`, identifiant d'image) dit ce qui tourne.
- Fiche de changement : `docs/cloud/changements/CHG-1154-mise-a-jour-2026.1.md` (impact, fenêtre, étapes, critères de réussite, critères d'abandon, retour arrière, communication). Runbook : `docs/cloud/runbooks/RB-101-mettre-a-jour-openstack.md`.
- Fenêtre annoncée à Julien et Nadia : 1 h, interruption des API acceptée (un seul contrôleur), aucune interruption du **plan de données** acceptée.

> ⚠️ **Attention** : (1) avant la fenêtre : sauvegarde complète de MariaDB **vérifiée** (préparée, E25), instantané des trois nœuds (`ms-snapshot --prefix avant-maj 2101 2102 2103`), `HEALTH_OK` de Ceph ; (2) n'utilise pas la commande de montée de **série** pour une mise à jour au sein d'une série sans avoir lu ce que la documentation recommande ; (3) l'option `--limit` est déconseillée par la documentation pour ces opérations ; (4) ne purge pas les anciennes images avant la clôture du changement : ce sont elles qui rendent un retour arrière rapide possible.

**Travail demandé**
1. **Ce qui a changé.** Relève la version de `kolla-ansible` installée et la dernière publiée de la série 22.x ; lis les notes de version (*release notes* de Kolla-Ansible, section 2026.1) entre les deux : correctifs, changements de comportement, notes de mise à jour. Si tu es déjà sur la dernière version publiée, le changement porte sur les images seules : note-le dans la fiche.
2. **Photographie avant.** Écris un script qui enregistre, pour chaque nœud et chaque conteneur Kolla, le nom, l'image, l'identifiant d'image et l'empreinte de dépôt (`docker inspect`), dans un fichier daté sous `docs/cloud/changements/`. Il resservira après la fenêtre.
3. **Préparation (hors fenêtre).** Par MR sur `plateforme/openstack` : mise à jour de `kolla-ansible` dans le projet `uv` (`uv lock`), collections (`install-deps`), comparaison de ton inventaire et de tes `globals` avec les exemples livrés par la nouvelle version (`diff`). Lance les vérifications préalables de Kolla et le **téléchargement** des images sur les nœuds : ces deux étapes n'interrompent rien. Compare les empreintes téléchargées avec la photographie : quelles images ont changé ?
4. **La fiche de changement.** Rédige CHG-1154 : impact attendu (quels conteneurs seront recréés, combien de temps sans API d'après tes mesures de E24), étapes, critères de réussite, critères d'**abandon** (à quel moment, sur quel symptôme, tu décides de revenir en arrière), retour arrière (instantanés **et** ce qu'ils ne couvrent pas), communication avant/pendant/après.
5. **La fenêtre.** Lance les mesures de continuité de E24 (IP flottante d'une instance d'essai `maj-essai01`, jeton toutes les 5 s), puis applique la procédure officielle de mise à jour au sein d'une série. Note l'heure de chaque étape.
6. **Vérification.** Photographie après, comparaison avec avant ; tous les conteneurs sains et lancés depuis l'image **téléchargée** ; services `up` ; test fonctionnel (instance créée, volume attaché, répartiteur OVN qui répond, Horizon). Mesure : durée totale, interruption des API, interruption du plan de données. Clôture la fiche.
7. **Runbook.** RB-101 : préparation, fenêtre, vérification, retour arrière, purge des anciennes images **après** clôture (`kolla-ansible prune-images` et ce qu'elle supprime), et une section « montée de série (2026.1 → 2026.2) : ce qui change » (sans l'exécuter).

**Critères de réussite**
- [ ] `uv.lock` de `plateforme/openstack` épingle la dernière `kolla-ansible` 22.x et un ansible-core < 2.21.
- [ ] Sur chaque nœud, chaque conteneur Kolla en service tourne sur l'image actuellement désignée par son étiquette (pas de conteneur resté sur l'ancienne image après un simple téléchargement) ; aucun conteneur n'est `unhealthy`.
- [ ] Tous les services de calcul, de réseau et de volume sont `up` ; plus aucune instance `maj-essai*`.
- [ ] CHG-1154 (avec mesures et clôture) et RB-101 sont sur `main` de `plateforme/medisphere`, avec les photographies avant/après.

**Vérification** : `lab/bin/check 10 28`

<details><summary>Indice 1</summary>

Lis la page *Operating Kolla* de la documentation 2026.1, et en particulier les deux notes encadrées au début de *Upgrade procedure* : la procédure décrite là n'est pas celle dont tu as besoin, mais une phrase te dit laquelle suivre.
</details>

<details><summary>Indice 2</summary>

`docker inspect -f '{{.Image}}' <conteneur>` donne l'identifiant de l'image **avec laquelle le conteneur a été créé** ; `docker image inspect -f '{{.Id}}' <dépôt>:<étiquette>` donne celui de l'image **actuellement** désignée par l'étiquette. Après un téléchargement sans redéploiement, les deux diffèrent.
</details>

<details><summary>Indice 3</summary>

Kolla ne recrée un conteneur que si quelque chose a changé pour lui (configuration, image). Un conteneur recréé hérite de ses volumes : les données ne bougent pas. MariaDB et RabbitMQ sont les deux redémarrages qui coupent tout : regarde leur ordre dans le journal d'Ansible.
</details>

**Pour aller plus loin** (facultatif) : un registre local (Harbor, module 13) avec des étiquettes **immuables** par version, pour choisir quand et quoi déployer ; les montées de série SLURP (une sur deux) ; [Kolla : *Operating Kolla*](https://docs.openstack.org/kolla-ansible/2026.1/user/operating-kolla.html), [notes de version de Kolla-Ansible 2026.1](https://docs.openstack.org/releasenotes/kolla-ansible/2026.1.html).

---

### M10-E29 — Ajouter et retirer un nœud de calcul  `LAB` `★★★`

> **Ticket PLAT-1155** — *De : Nadia Roussel*
> Le constructeur nous demande de remplacer une barrette mémoire de `oscmp02` (simulé : l'iDRAC a remonté des erreurs corrigées). Je veux que l'opération se fasse **sans couper une seule instance** de MédiAgenda : on vide le nœud, on le sort proprement d'OpenStack, on l'éteint, on le remet, on le réintègre, et on rééquilibre.
> Et je veux le runbook RB-102, parce que la prochaine fois ce sera à 3 h du matin et ce sera moi.

**Objectifs pédagogiques**
- Vider un hyperviseur par migration à chaud (stockage partagé Ceph) et comprendre ce qui rend la migration possible ou impossible.
- Retirer un nœud de calcul d'OpenStack sans laisser d'état orphelin (service Nova, fournisseur de ressources de Placement, agents et châssis OVN).
- Réintégrer un nœud avec Kolla-Ansible et rééquilibrer la charge.

**Prérequis** : M10-E19 (migrer, évacuer, désactiver), M10-E10 (disques éphémères sur Ceph), M10-E24.
**Durée indicative** : 3 h.

**Contexte technique**
- Procédure officielle : *Adding and removing hosts* de Kolla-Ansible 2026.1 (retrait et ajout de nœuds de calcul).
- Avec `nova_backend_ceph`, les disques des instances sont dans le pool `vms` : la migration à chaud ne copie que la mémoire.
- Le fournisseur de ressources (*resource provider*) de Placement porte le **nom d'hôte** du nœud. Un `oscmp02` réintégré qui retrouve un fournisseur orphelin du même nom ne s'enregistre pas proprement.
- Charge à protéger pendant l'exercice : deux instances `evac-essai01` et `evac-essai02` sur `oscmp02` (projet `plateforme`, une IP flottante sur la première), avec une mesure de continuité (E24) pendant toute l'opération. Elles sont détruites à la fin.
- Capacité : un calcul de 8 Go doit pouvoir accueillir les instances de l'autre. Vérifie-le **avant** de commencer.

> ⚠️ **Attention** : (1) instantané des trois nœuds avant de commencer ; (2) ne retire jamais un nœud qui porte encore une instance : une instance dont l'hôte a disparu de Nova ne se migre plus, elle s'**évacue** (redémarrage) ; (3) l'arrêt des conteneurs Kolla d'un nœud demande une option de confirmation explicite : lis-la et vérifie deux fois la limite d'hôtes avant de valider ; (4) la VM `oscmp02` n'est éteinte qu'une fois le nœud vide et sorti d'OpenStack.

**Travail demandé**
1. **Capacité.** Relève les inventaires et les consommations de Placement pour `oscmp01` et `oscmp02` (VCPU, MEMORY_MB, DISK_GB, ratios d'allocation). `oscmp01` peut-il absorber la charge de `oscmp02` ? Que se passe-t-il pour la mémoire réelle (pas allouée) de la VM `oscmp01` ?
2. **Préparation.** Crée `evac-essai01` et `evac-essai02` sur `oscmp02`, l'IP flottante, et lance la mesure de continuité.
3. **Vider.** Désactive le service de calcul de `oscmp02` **avec une raison** (référence du ticket). Migre à chaud chaque instance ; suis les migrations (`openstack server migration list`, journaux de `nova-compute` des deux côtés). Mesure la coupure vue par la mesure de continuité.
4. **Sortir.** Arrête les conteneurs Kolla de `oscmp02` par Kolla-Ansible, retire le nœud de l'inventaire par MR, supprime ses services Nova et ses agents réseau. Vérifie : fournisseur de ressources de Placement, châssis OVN dans la base Sud, `openstack hypervisor list`. Éteins la VM `oscmp02` (maintenance simulée : modifie un paramètre sans conséquence, par exemple la description de la VM dans Proxmox par OpenTofu).
5. **Réintégrer.** Remets le nœud dans l'inventaire, prépare-le (`bootstrap-servers` limité à lui, et ce que la documentation dit des risques de cette commande sur un système existant), télécharge les images, déploie. Vérifie l'enregistrement dans Nova et Placement (un seul fournisseur `oscmp02`), réactive le service, et rééquilibre en migrant `evac-essai02` vers `oscmp02`.
6. **Runbook.** RB-102 « évacuer un nœud de calcul » : maintenance planifiée (ce que tu viens de faire), panne d'un calcul (évacuation, `--on-shared-storage` implicite avec Ceph, forcer l'état `down` d'un service), réintégration, contrôles. Avec un historique daté : cet exercice comme première exécution (durées, coupure mesurée). Détruis les instances `evac-essai*`.

**Critères de réussite**
- [ ] `oscmp02` est de nouveau dans l'inventaire ; son `nova-compute` est `up` et activé ; un seul service de calcul par hôte.
- [ ] Placement contient exactement un fournisseur de ressources nommé `oscmp02`, avec un inventaire `VCPU` et `MEMORY_MB` ; aucun fournisseur orphelin.
- [ ] Un seul agent « OVN Controller » par calcul, tous vivants.
- [ ] RB-102 (avec l'historique de cette exécution et la coupure mesurée) est sur `main` de `plateforme/medisphere` ; plus aucune instance `evac-essai*`.

**Vérification** : `lab/bin/check 10 29`

<details><summary>Indice 1</summary>

Les commandes de Placement (`openstack resource provider …`, `allocation …`) viennent du greffon `osc-placement` de la CLI ; s'il manque, ajoute-le à l'outil installé par `uv tool` (option `--with`). Les inventaires et l'usage d'un fournisseur se lisent séparément.
</details>

<details><summary>Indice 2</summary>

Une migration à chaud échoue souvent pour des raisons banales : CPU différents (le modèle de CPU des invités doit être disponible des deux côtés), nom de l'hôte cible non résolu, flux de migration (libvirt) bloqué entre calculs. Lis l'erreur dans le journal de `nova-compute` de l'hôte **source**.
</details>

<details><summary>Indice 3</summary>

Supprimer le service de calcul d'un hôte supprime aussi son fournisseur de ressources… s'il ne porte plus d'allocations. Si des allocations restent (instance migrée mais allocation non nettoyée), le fournisseur reste : `openstack resource provider show <uuid> --allocations` te montre qui le retient.
</details>

**Pour aller plus loin** (facultatif) : agrégats d'hôtes et zones de disponibilité pour séparer recette et production ; Watcher pour rééquilibrer automatiquement ; [Kolla : *Adding and removing hosts*](https://docs.openstack.org/kolla-ansible/2026.1/user/adding-and-removing-hosts.html), [Nova : *Live-migrate instances*](https://docs.openstack.org/nova/2026.1/admin/live-migration-usage.html), [Nova : *Evacuate instances*](https://docs.openstack.org/nova/2026.1/admin/evacuate.html).

---

### M10-E30 — ADR : choix réseau et répartiteurs  `RED` `★★`

> **Ticket PLAT-1156** — *De : Claire Morel*
> On a choisi OVN et Octavia avec le fournisseur OVN au début du module, sur la recommandation de Karim, sans l'écrire. Le jour où quelqu'un demandera pourquoi on n'a pas « des amphores comme tout le monde », je veux une réponse écrite, avec ce qu'on a appris depuis : ce que ça nous coûte, ce que ça nous interdit, et à quel signal on reviendrait sur la décision.

**Objectifs pédagogiques**
- Formaliser une décision d'architecture a posteriori, avec des faits mesurés dans le module.
- Comparer ML2/OVN et ML2/Open vSwitch (agents L3 et DHCP), et Octavia OVN et Octavia amphora, sur des critères d'exploitation et non de popularité.
- Écrire les conséquences et les conditions de révision d'une décision.

**Prérequis** : M10-E08, E12, E16 (réseau, Octavia), M10-E24 (mesures de HA), M10-E31 recommandé (besoins de MédiAgenda), M06-E31 (format des ADR).
**Durée indicative** : 2 h.

**Contraintes**
- Fichier `docs/cloud/adr/ADR-0100-reseau-ovn-et-repartiteurs.md` dans `plateforme/medisphere`, au format des ADR du dépôt (contexte, options, décision, conséquences, statut, date), une ADR qui couvre deux décisions liées (ou deux ADR liées, justifié).
- Options comparées : pour le réseau, ML2/OVN et ML2/OVS (le mécanisme Linux Bridge a été retiré de Neutron : dis-le et pourquoi ça compte) ; pour les répartiteurs, fournisseur OVN, fournisseur amphora, et « pas d'Octavia » (HAProxy des équipes dans leurs instances).
- Critères au minimum : fonctions (L4/L7, terminaison TLS, algorithmes, contrôles de santé, préservation de l'adresse source), ressources consommées (mémoire du lab, images, réseau de gestion d'Octavia), haute disponibilité et temps de bascule, diagnostic (outils, compétences), sécurité, maturité et feuille de route, effort de migration ultérieur.
- Faits mesurés ou vérifiés dans le module (avec leur source : exercice, commande, page de documentation) ; aucune affirmation non vérifiable sur les performances.
- Conséquences opérationnelles explicites pour les équipes (ce que Julien ne pourra pas demander avec le fournisseur OVN) et **conditions de révision** (signaux mesurables qui rouvriraient la décision).
- Relecture simulée : Karim (technique), Julien (besoins), Sophie (sécurité), notée en bas du document.

**Critères de réussite**
- [ ] ADR-0100 est sur `main`, statut « acceptée », date et décideurs.
- [ ] Chaque option a ses avantages et inconvénients, chaque critère est renseigné pour chaque option, avec la source des faits.
- [ ] Les limites du fournisseur OVN sont exactes et complètes (protocoles, algorithme, TLS, L7, adresse source).
- [ ] Les conditions de révision sont mesurables.

**Pour aller plus loin** (facultatif) : [ovn-octavia-provider : limitations](https://docs.openstack.org/ovn-octavia-provider/2026.1/admin/driver.html), [Neutron : OVN](https://docs.openstack.org/neutron/2026.1/admin/ovn/index.html), [Octavia : *Provider feature support matrix*](https://docs.openstack.org/octavia/2026.1/user/feature-classification/index.html).

---

### M10-E31 — Le libre-service pour MédiAgenda  `LIBRE` `★★★`

> **Ticket DEV-1157** — *De : Julien Petit*
> Grâce à vous on a des projets, des quotas et un tableau de bord. Mais pour monter la recette de MédiAgenda, on vous ouvre encore un ticket. Ce que je veux : un dépôt à **nous**, dans lequel mon équipe décrit sa recette, et un pipeline qui la crée, la met à jour et la détruit, sans personne de la plateforme dans la boucle. Deux serveurs d'application derrière un répartiteur, un disque de données, une adresse joignable depuis le VPN.
> *Karim, en commentaire* : d'accord, à condition que la plateforme fournisse la brique (un module versionné), qu'ils ne puissent rien casser hors de leur projet, et qu'on puisse relire ce qu'ils font.

**Objectifs pédagogiques**
- Concevoir une offre en libre-service : un module OpenTofu de la plateforme, consommé par une équipe dans son propre dépôt, avec ses propres identifiants à privilèges minimaux.
- Assembler réseau, routeur, groupes de sécurité, instances, volume, répartiteur Octavia OVN et IP flottante en un environnement reproductible.
- Tenir compte des propriétés du fournisseur OVN dans la conception (adresse source préservée, algorithme, contrôles de santé).

**Prérequis** : M10-E13 (projets et quotas), M10-E15 (provider OpenStack, identifiants d'application), M10-E16 (Octavia OVN), M10-E18 (cloud-init), M05 (modules, état distant, pipeline plan/apply), M10-E30 recommandé.
**Durée indicative** : 5 h.

**Contraintes**
- Dépôt de l'équipe : projet GitLab **`mediagenda/recette-infra`** (groupe `mediagenda`, Julien *Maintainer*, toi *Developer*), qui appelle un module **`openstack-env-app`** publié dans `plateforme/tofu-modules` et référencé par une **étiquette** de version. Le module est générique (une autre équipe doit pouvoir s'en servir) ; le dépôt de l'équipe ne contient que des valeurs.
- OpenStack : tout dans le projet `mediagenda-dev`. Authentification par un **identifiant d'application** du projet, au rôle `member` (jamais `admin`), stocké en variables **protégées et masquées** du projet GitLab. Les quotas du projet ne sont pas modifiés.
- État OpenTofu sur `s3-01`, chiffré comme en M05-E27, inaccessible aux identifiants de l'équipe pour tout autre état que le sien (et inversement : les identifiants de la plateforme n'ont pas à être donnés à l'équipe).
- Pipeline : validation et plan sur chaque MR (plan visible dans la MR), application **manuelle** sur `main`, destruction manuelle protégée, et un plan nocturne qui signale la dérive.
- Ressources, avec ces noms (vérifiés) : réseau `agenda-recette-net`, sous-réseau `agenda-recette-sn` (plage privée de ton choix, sans chevauchement avec le lab), routeur `agenda-recette-rt` (passerelle `ext-net`), groupes de sécurité `agenda-recette-app` et `agenda-recette-admin`, instances `agenda-recette-app01` et `agenda-recette-app02` (Debian 13, `m1.petit`, une sur chaque calcul autant que possible), volume `agenda-recette-donnees` (5 Go, attaché à `app01`, formaté et monté par cloud-init), répartiteur `agenda-recette-lb` (fournisseur **OVN**, écoute TCP 80) avec un contrôle de santé, IP flottante associée à la VIP du répartiteur.
- Chaque instance sert, en HTTP sur le port 80, une page qui contient son **nom d'hôte** (serveur web au choix, installé par cloud-init). Aucune instance n'a d'IP flottante propre ; l'accès SSH d'administration passe par un moyen que tu choisis et justifies, ouvert seulement depuis MGMT et le VPN d'administration.
- Le répartiteur ne doit pas rendre les instances joignables par d'autres ports que 80 ; les groupes de sécurité doivent rester corrects avec le fournisseur OVN (réfléchis à l'adresse source que voient les instances, et à celle des contrôles de santé).
- Reproductibilité : `destroy` puis `apply` recréent l'environnement en moins de 15 minutes, sans geste manuel ; un second `apply` ne change rien.
- Documentation pour l'équipe : `docs/cloud/libre-service.md` dans `plateforme/medisphere` (ce que l'offre fournit, ce qu'elle ne fournit pas, comment demander une évolution, limites du répartiteur OVN), et le `README.md` du module (variables, sorties, exemple).

**Critères de réussite**
- [ ] Les ressources nommées existent dans `mediagenda-dev`, actives ; le répartiteur est du fournisseur `ovn`, `ACTIVE` et `ONLINE`, avec deux membres `ONLINE`.
- [ ] Depuis `adm01`, l'IP flottante du répartiteur répond en HTTP 200 sur le port 80, et des requêtes successives atteignent **les deux** instances ; le port 22 des instances n'est pas joignable par cette adresse.
- [ ] Le volume `agenda-recette-donnees` est attaché à `agenda-recette-app01`.
- [ ] `mediagenda/recette-infra` existe, son dernier pipeline de `main` a réussi, et il référence le module par une étiquette ; l'identifiant d'application utilisé n'a pas le rôle `admin`.
- [ ] `docs/cloud/libre-service.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 10 31`

<details><summary>Indice 1</summary>

Pars des besoins, pas des ressources : qu'est-ce que l'équipe doit pouvoir **choisir** (taille, nombre d'instances, page servie, plage du sous-réseau) et qu'est-ce que la plateforme **impose** (image, fournisseur du répartiteur, groupes de sécurité minimaux, étiquettes) ? Les premiers sont des variables du module, les seconds n'en sont pas.
</details>

<details><summary>Indice 2</summary>

Relis les limites du fournisseur OVN que tu as écrites en E30 : algorithme disponible, protocoles, et surtout le fait qu'il ne fait **pas** de traduction d'adresse source. Les contrôles de santé du fournisseur OVN ont, eux, une adresse source à part : cherche dans la documentation du fournisseur d'où ils partent.
</details>

<details><summary>Indice 3</summary>

Pour le cloisonnement des états, regarde ce que permettent les identités de SeaweedFS (actions par compartiment). Pour que le module soit relu, une MR sur `plateforme/tofu-modules` suivie d'une étiquette ; pour que l'équipe monte de version, une MR sur **son** dépôt qui change la référence.
</details>

**Pour aller plus loin** (facultatif) : un catalogue de services (Backstage, module 28) qui crée le dépôt de l'équipe à partir d'un modèle ; des environnements éphémères par MR ; des noms DNS pour les IP flottantes (Designate, fiche).

---

### M10-E32 — Questions de production : OpenStack  `Q` `★★★`

> **Ticket PLAT-1158** — *De : Karim Benali*
> Avant de te mettre d'astreinte sur le cloud, on fait le point. Argumente, chiffre quand tu peux, et dis toujours de quoi dépend ton « ça dépend ».

**Objectifs pédagogiques**
- Raisonner sur le comportement d'OpenStack en production : défaillances partielles, capacité, mises à jour, sécurité.
- Relier les choix du module (un contrôleur, OVN, Ceph, Kolla) à des risques concrets.

**Prérequis** : paliers 1 et 2, M10-E24 à E31.
**Durée indicative** : 1 h 30.

**Questions**

1. QCM — `osctl01` est arrêté depuis dix minutes. Lequel de ces énoncés est vrai pour une instance de MédiAgenda déjà démarrée sur `oscmp01`, sur un réseau de projet, avec une IP flottante ?
   a) elle est arrêtée par `nova-compute`, qui ne joint plus le plan de contrôle ;
   b) elle continue de tourner et de joindre les instances du même réseau, mais son IP flottante ne répond plus ;
   c) elle continue de tourner, mais perd son adresse IP à l'expiration de son bail DHCP ;
   d) tout continue normalement, y compris l'IP flottante.
   Justifie, et dis ce qui change avec `neutron_ovn_distributed_fip`, et ce qui se passe au bout de 24 h (bail DHCP d'OVN).
2. Pourquoi un cluster Galera de **deux** contrôleurs est-il plus fragile qu'un seul ? Même question pour RabbitMQ en files *quorum* et pour les bases OVN en Raft. Quel est le nombre minimal de contrôleurs qui tolère une panne, et pourquoi pas quatre ?
3. QCM — Une création d'instance échoue avec « No valid host was found ». Laquelle de ces causes est **impossible** ?
   a) `nova-compute` de chaque calcul est `down` (RabbitMQ) ;
   b) le gabarit demande plus de mémoire que la capacité allouable restante (ratio compris) ;
   c) le quota du projet en cœurs est dépassé ;
   d) l'image porte une propriété qui exige un trait qu'aucun hôte ne fournit.
   Explique où chacune des trois autres se voit (journaux, commandes).
4. Ratios d'allocation : `cpu_allocation_ratio` 4.0, `ram_allocation_ratio` 1.0 sur des calculs de 4 vCPU et 8 Go. Combien d'instances `m1.petit` (1 vCPU, 1 Go) peut-on placer par calcul, compte tenu de la mémoire réservée à l'hôte ? Pourquoi ne monte-t-on presque jamais le ratio de mémoire au-dessus de 1, et que se passe-t-il quand on le fait sur une VM imbriquée de 8 Go ?
5. La mise à jour de E28 a recréé MariaDB et RabbitMQ. Décris ce que voit un utilisateur pendant ces deux redémarrages (API, Horizon, instances en cours de création). Comment réduire l'interruption avec trois contrôleurs ? Pourquoi la documentation déconseille-t-elle `--limit` pour ces opérations ?
6. Que faudrait-il pour passer de 2026.1 à 2026.2 « Hibiscus » ? Cite les étapes de la procédure de montée de série de Kolla, ce qu'est une montée SLURP, et pourquoi on attend qu'une version de Kolla-Ansible **finale** soit publiée (et pas seulement OpenStack). Que change la contrainte d'ansible-core pour ton projet `uv` ?
7. La base MariaDB restaurée en E25 date de 01:30 ; l'incident a lieu à 16:00. Énumère ce que l'équipe perd, ce qui devient orphelin et ce qui devient incohérent (instances, volumes, IP flottantes, réseaux OVN). Pourquoi la restauration d'une base de plan de contrôle est-elle toujours suivie d'une **réconciliation** ?
8. QCM — Les jetons Fernet. Laquelle de ces affirmations est fausse ?
   a) un jeton Fernet n'est pas stocké en base : il est chiffré et se valide avec les clés du répertoire `fernet-keys` ;
   b) si les clés diffèrent entre deux nœuds Keystone, une partie des requêtes est refusée au hasard ;
   c) la rotation des clés invalide immédiatement tous les jetons en cours ;
   d) une horloge très décalée sur un nœud peut faire refuser des jetons valides.
   Justifie, en t'appuyant sur `fernet_token_expiry`, `fernet_token_allow_expired_window` et `fernet_key_rotation_interval` de Kolla.
9. Un identifiant d'application de la CI de MédiAgenda fuit dans un journal de pipeline. Quelles actions, dans quel ordre ? Qu'est-ce qui limite les dégâts dans ta conception de E31 ? Qu'est-ce qui les aurait aggravés ?
10. Les instances voient-elles les VLAN d'infrastructure ? Explique le chemin d'un paquet d'une instance vers 10.10.20.10 (DNS du socle) : réseau de projet, routeur OVN, SNAT sur `ext-net`, bordure. Quelle est la seule barrière, et pourquoi la règle « VLAN 52 → VLAN 50 interdit » de E27 ne suffit-elle pas à protéger le socle ?
11. Pourquoi les images doivent-elles être au format **raw** avec Ceph, et que se passe-t-il (temps, espace, Ceph) quand une équipe envoie un qcow2 de 2 Go dans Glance ? Comment l'empêcher (*image import*, conversion, `disk_formats`) ?
12. Kolla n'utilise pas les paquets Debian d'OpenStack mais des images. Avantages et inconvénients pour les correctifs de sécurité (qui les publie, quand, comment tu le sais), et pour l'audit HDS (« quelle version tourne en production ? »).
13. Cinder Backup écrit dans le pool `backups` du **même** cluster Ceph que les volumes. Est-ce une sauvegarde ? Contre quels risques protège-t-elle, contre lesquels non ? Propose une cible conforme à la règle 3-2-1 avec ce que le lab possède.
14. Le comité de direction veut « un cloud aussi fiable que le cloud public ». Que manque-t-il, concrètement, au déploiement du module pour viser 99,9 % de disponibilité du plan de contrôle sur un mois (combien de minutes d'arrêt par mois, quelles opérations les consomment aujourd'hui) ?

Les réponses argumentées sont dans le corrigé.

---

### M10-E33 — Rapport de capacité et de consommation  `RED` `★★`

> **Ticket PLAT-1159** — *De : Claire Morel*
> Le budget de l'an prochain se prépare. Je dois savoir ce qu'on consomme, qui le consomme, ce qu'il nous reste, et quand on sera plein, pour le calcul **et** pour le stockage. Un rapport d'une à deux pages, avec les chiffres, leur source, et une recommandation. Et je veux pouvoir le refaire chaque mois sans toi.

**Objectifs pédagogiques**
- Mesurer la capacité réelle d'un cloud OpenStack (Placement, ratios, réservations de l'hôte) et la distinguer de la consommation réelle (mémoire et CPU des hyperviseurs, octets dans Ceph).
- Attribuer la consommation aux projets (quotas, usage, `openstack usage`).
- Produire un rapport reproductible et une recommandation argumentée.

**Prérequis** : M10-E13 (quotas), M10-E29 (Placement), M08 (`ceph df`, pools, réplication).
**Durée indicative** : 2 h 30.

**Contraintes**
- Rapport `docs/cloud/capacite/rapport-AAAA-MM.md` dans `plateforme/medisphere`, une à deux pages, destiné à Claire (non spécialiste d'OpenStack).
- Contenu minimal : capacité **allouable** du calcul (VCPU, mémoire, par hôte et totale, ratios et réservations), allocations actuelles, consommation **réelle** des hyperviseurs ; quotas et usage par projet (domaine `medisphere`) ; stockage : pools `images`, `volumes`, `vms`, `backups` (octets stockés, octets bruts après réplication, place restante avant le seuil `nearfull` de Ceph), volumes **provisionnés** contre octets **écrits** (allocation fine) ; marge avant saturation en nombre d'instances `m1.petit` et `m1.moyen` ; tendance si tu as deux mesures ; recommandation.
- Chaque chiffre a sa source (commande, API) ; les commandes sont rassemblées dans un script de collecte versionné dans `plateforme/outils`, que Nadia peut relancer.
- `openstack hypervisor stats show` n'existe plus dans les micro-versions récentes de l'API compute : le rapport s'appuie sur Placement.
- Le rapport dit ce qu'il ne mesure pas (surcharge de l'imbrication, `pve01` partagé avec les autres profils du lab).

**Critères de réussite**
- [ ] Le rapport et le script de collecte sont sur `main` ; relancer le script reproduit les chiffres du rapport.
- [ ] La différence entre capacité allouée, quotas et consommation réelle est expliquée avec les chiffres du lab.
- [ ] Le stockage distingue octets stockés, octets bruts et espace provisionné.
- [ ] La recommandation est chiffrée (date ou seuil de saturation, action, coût).

**Pour aller plus loin** (facultatif) : CloudKitty pour la refacturation interne ; un export mensuel vers le module 21 ; [Placement : usage](https://docs.openstack.org/placement/2026.1/user/index.html), [osc-placement](https://docs.openstack.org/osc-placement/latest/), [Ceph : `ceph df`](https://docs.ceph.com/en/tentacle/rados/operations/monitoring/#checking-a-cluster-s-usage-stats).

---

### M10-E34 — Un environnement complet en temps limité  `CHRONO` `★★★`

> **Ticket CHG-1160** — *De : Claire Morel*
> Démonstration demandée par la direction : « combien de temps pour donner à une nouvelle équipe un environnement complet et sûr sur notre cloud ? ». Notre réponse doit être : moins d'une matinée, en suivant nos runbooks, sans contourner la sécurité.
> Le dossier est prêt. Chrono en main.

**Règles de l'exercice**
- Conditions d'examen : pas de corrigé, pas d'autres notes que **tes** runbooks (RB-100 en particulier), ton code et la documentation officielle.
- Durée cible : **2 h** entre l'ouverture du dossier (T0) et l'environnement vérifié (T4).
- Tout ce qui est durable (projet, groupe, quotas) passe par le code de la plateforme (état OpenTofu des projets, M10-E15) ; les ressources **dans** le projet peuvent être créées par le moyen de ton choix (CLI, Heat, OpenTofu), mais doivent pouvoir être recréées par quelqu'un d'autre à partir de ce que tu laisses.
- L'environnement est **temporaire** : après la vérification, tu le retires proprement, par le même chemin (il est vérifié absent par le mini-projet).

**Prérequis** : RB-100 (M10-E22), M10-E13, E15, E16, E27.
**Durée** : 2 h chronométrées + 30 minutes de retour d'expérience.

**Dossier** : [`ressources/M10-E34/dossier-chrono.md`](../ressources/M10-E34/dossier-chrono.md) (le besoin, les contraintes, la feuille de temps). Lis-le à T0, pas avant.

**Critères de réussite**
- [ ] L'environnement décrit dans le dossier est en service à T4, et toutes ses exigences sont satisfaites (vérification ci-dessous, **avant** le retrait).
- [ ] La feuille de temps est remplie (T0 à T5), avec les gestes manuels et leur raison ; le temps total jusqu'à T4 est inférieur à 2 h (sinon, améliore ton outillage et refais l'exercice).
- [ ] Le retour d'expérience (une demi-page) est rédigé, et RB-100 mis à jour par MR.
- [ ] Après le retrait, plus rien ne reste de l'environnement (vérifié par `lab/bin/check 10 46`).

**Vérification** : `lab/bin/check 10 34` (à lancer à T4, **avant** le retrait).

**Pour aller plus loin** (facultatif) : refais l'exercice en visant 45 minutes avec le module de E31 ; puis demande-toi ce qu'il faudrait pour que l'équipe le fasse seule de bout en bout (projet compris).
