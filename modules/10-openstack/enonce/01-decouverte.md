# Module 10 — Palier 1 : Découverte

Le cloud de MédiSphère part de trois VMs vides. Ce palier les prépare par le chemin habituel (OpenTofu, rôle Ansible), installe Kolla-Ansible dans un environnement isolé sur `adm01`, met toute la configuration du déploiement dans un dépôt dont les secrets sont chiffrés, et déploie OpenStack. Puis il fait le tour des services que toute requête traverse : Keystone (le domaine de MédiSphère, ses projets, ses groupes), Glance (des images vérifiées), Nova (gabarits, clés, une première instance) et Neutron avec OVN (un routeur, une IP flottante, une instance joignable depuis `adm01`). Le palier s'ouvre et se ferme sur un questionnaire.

Prérequis : module 08 terminé (`lab/bin/check 08 46` vert) ; M07-E15 (MTU 9000 sur les VLAN 30, 31 et 51) ; module 06 (NetBox, PowerDNS, step-ca) ; modules 04 et 05 (rôles, Vault à deux identités, OpenTofu, pipelines). Lis [`00-introduction.md`](00-introduction.md), en particulier l'architecture, le plan réseau des nœuds, le chemin imposé et les règles du module.

---

### M10-E01 — Test de positionnement : IaaS et OpenStack  `Q` `★★`

> **Ticket PLAT-1101** — *De : Karim Benali*
> Le rituel, version cloud : virtualisation, réseau virtuel, identité, conteneurs, et ce que tu crois savoir d'OpenStack. Par écrit, sans moteur de recherche ni IA, sans rien exécuter, une heure. Beaucoup de gens « connaissent OpenStack » parce qu'ils ont lancé une instance sur un cloud public ; ce module va te faire **l'opérer**. Réponds même là où tu hésites.

**Objectifs pédagogiques**
- Évaluer tes acquis sur les notions que le module met en œuvre : virtualisation matérielle, réseau virtuel, identité et jetons, conteneurs, automatisation.
- Repérer les notions à travailler avant les exercices qui les mobilisent.

**Prérequis** : aucun.
**Durée indicative** : 1 h (+ 30 min d'auto-correction).

**Travail demandé**

Réponds aux 20 questions. Pour les QCM, justifie ton choix en une ou deux phrases.

*Cloud et IaaS*

1. Cite les cinq caractéristiques d'un service de *cloud computing* selon la définition du NIST (SP 800-145). Pour chacune, dis si un cluster Proxmox avec une interface web (module 09) la remplit, et ce qui lui manque.

2. *(QCM)* Dans un IaaS, qui décide sur quel hyperviseur tourne une instance ?
   - A. L'utilisateur, qui choisit l'hyperviseur au moment de la création
   - B. L'ordonnanceur du service de calcul, selon les ressources disponibles et des règles
   - C. L'opérateur, qui place chaque instance à la main
   - D. Le premier hyperviseur qui répond

3. Un **quota** et une **capacité** : définis les deux. Un projet a un quota de 20 vCPU, le cloud a 16 vCPU physiques libres. Que se passe-t-il quand le projet demande 18 vCPU ? Et si le cloud surréserve (*overcommit*) les vCPU d'un facteur 4 ?

*Virtualisation*

4. Qu'apportent les extensions VT-x/AMD-V à un hyperviseur ? Qu'est-ce que la **virtualisation imbriquée**, et que faut-il, côté hôte et côté VM intermédiaire, pour qu'une VM puisse elle-même lancer des VMs accélérées par KVM ? Que se passe-t-il si ce n'est pas le cas ?

5. *(QCM)* Le type de CPU `host` d'une VM Proxmox :
   - A. donne à l'invité le même modèle de CPU et les mêmes extensions que l'hôte physique
   - B. donne à l'invité un CPU générique compatible avec tous les hôtes d'un cluster
   - C. réserve un cœur physique entier à la VM
   - D. désactive la migration à chaud de la VM, et rien d'autre

6. Disque d'instance au format **qcow2** ou **raw** : différences (allocation, instantanés, performances). Pourquoi un stockage Ceph RBD préfère-t-il des images `raw` ?

*Réseau virtuel*

7. Pourquoi encapsuler le trafic entre VMs (VXLAN, Geneve) plutôt que de donner un VLAN à chaque réseau de client ? Cite deux avantages et un coût.

8. Une trame Ethernet de 1500 octets de charge est encapsulée en Geneve sur IPv4. Quelle MTU faut-il sur le réseau physique pour qu'elle passe sans fragmentation ? Inversement, si le réseau physique est à 1500, quelle MTU doit-on annoncer aux VMs (ordre de grandeur, justifié) ?

9. Qu'est-ce qu'une **IP flottante** ? Décris le trajet d'un `ping` de `adm01` vers l'IP flottante d'une VM : quelles traductions d'adresses, où, dans quel sens.

10. *(QCM)* Un groupe de sécurité de cloud est le plus proche de :
    - A. une ACL sans état sur un routeur
    - B. un pare-feu à états appliqué sur chaque port virtuel de VM
    - C. un VLAN privé
    - D. une règle de NAT

11. Un réseau « fournisseur » (*provider network*) et un réseau « de projet » (*self-service*) : qui les crée, comment ils atteignent le réseau physique, lequel peut porter des IP flottantes.

*Identité*

12. Distingue **authentification** et **autorisation**. Dans un système à jetons, que contient un jeton, combien de temps vit-il, et pourquoi les jetons courts sont-ils préférables à des mots de passe envoyés à chaque requête ?

13. Un développeur doit pouvoir créer des VMs dans le projet de recette de son équipe, et seulement **voir** celles de la production. Décris les objets d'identité minimaux (utilisateurs, groupes, projets, rôles) et leurs liens.

14. Pourquoi un script d'automatisation (pipeline de CI, OpenTofu) ne devrait-il pas utiliser le mot de passe d'un humain ? Que doit offrir un système d'identité pour l'éviter ?

*Conteneurs et automatisation*

15. Pourquoi déployer des services d'infrastructure (bases, files de messages, API) **en conteneurs** plutôt qu'en paquets du système ? Cite deux avantages et deux inconvénients pour l'exploitation.

16. *(QCM)* Un conteneur est lancé avec `--network host`. Cela signifie :
    - A. il n'a pas de réseau
    - B. il partage la pile réseau de l'hôte (interfaces, ports, routes)
    - C. il a sa propre interface pontée sur celle de l'hôte
    - D. il ne peut joindre que l'hôte

17. Deux projets d'automatisation sur le même poste exigent des versions incompatibles d'ansible-core (l'un ≥ 2.21, l'autre < 2.21). Comment les faire cohabiter proprement ? Quel risque y a-t-il à partager le dossier des collections Ansible entre les deux ?

18. Un fichier de mots de passe généré par un outil de déploiement doit être versionné avec le reste de la configuration. Comment ? Et que perd-on si on ne le versionne pas ?

*OpenStack*

19. Cite les services d'OpenStack qui interviennent quand un utilisateur crée une instance avec un disque, sur un réseau, à partir d'une image, et le rôle de chacun en une phrase.

20. *(QCM)* Dans OpenStack, un **gabarit** (*flavor*) définit :
    - A. le système d'exploitation de l'instance
    - B. les ressources (vCPU, mémoire, disques) et des propriétés de placement
    - C. le réseau de l'instance
    - D. le projet propriétaire de l'instance

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 20 questions avant d'ouvrir le corrigé.
- [ ] Tu as noté chaque réponse avec la grille (0, 1 ou 2 points) et calculé ton score sur 40.
- [ ] Tu as noté les thèmes à retravailler et les exercices du module qui les mobilisent.

<details><summary>Indice 1</summary>

Pour les questions de réseau, dessine les en-têtes : Ethernet externe, IP externe, UDP, en-tête Geneve, puis la trame d'origine. Compte les octets de chaque couche.
</details>

<details><summary>Indice 2</summary>

Pour l'identité, sépare **qui tu es** (utilisateur, groupe, domaine), **où tu agis** (projet), **ce que tu as le droit d'y faire** (rôle, interprété par les politiques de chaque service).
</details>

**Pour aller plus loin** (facultatif) : la définition du NIST, SP 800-145 (deux pages) : <https://csrc.nist.gov/pubs/sp/800/145/final>. Refais ce test à la fin du module (M10-E46) sans relire le corrigé, et compare.

---

### M10-E02 — Préparer les nœuds OpenStack  `LAB` `★★`

> **Ticket PLAT-1102** — *De : Karim Benali* — *Copie : Claire Morel*
> Trois VMs, quatre réseaux, deux MTU, du KVM imbriqué : c'est là que les déploiements d'OpenStack ratent, rarement dans OpenStack lui-même. Je veux les nœuds **déclarés** (OpenTofu, NetBox, DNS) et **préparés** par un rôle Ansible, avec des noms d'interface qui ne bougent pas quand on reconstruit. Et je veux la preuve, avant le moindre conteneur, que les jumbo frames passent, que KVM est utilisable dans les calculs et que l'heure est juste partout.

**Objectifs pédagogiques**
- Traduire un plan réseau de nœuds (cartes, VLAN, MTU, adresses) en code OpenTofu, NetBox et Ansible.
- Comprendre les prérequis d'un nœud OpenStack : interfaces stables, carte externe sans adresse, MTU de bout en bout, virtualisation imbriquée, temps.
- Prendre possession du réseau d'un hôte par Ansible, avec un accès de secours.

**Prérequis** : M05-E46, M06-E13/E14 (NetBox, module `enregistrement-dns`) et M08-E02 (module `vm-noeud`) ; M07-E15 (MTU 9000 sur `vmbr1` et les VLAN 30/51) ; M04 (rôles communs, inventaire dynamique) ; M02-E11 (`ms-snapshot`).
**Durée indicative** : 3 h 30.

**Contexte technique**

| Élément | Valeur |
|---|---|
| VMs | voir l'introduction, « Hôtes du module » et « Plan réseau des nœuds » : `osctl01` (2101, 4 vCPU, 16 Go, 80 Go), `oscmp01`/`oscmp02` (2102/2103, 4 vCPU, 8 Go, 40 Go, CPU `host`) ; disque système sur `local-nvme` ; pool `lab` ; étiquettes `env-m10` et `role-openstack` (à créer dans NetBox si elles n'existent pas) |
| Cartes | `net0` `vosapi`, `net1` `vostun` (`mtu=9000`), `net2` `vstopub` (`mtu=9000`), `net3` `vosext` (`osctl01` seulement) ; MAC `bc:24:11:<VLAN>:00:<suffixe>` (suffixe = 51, 52, 53) ; pare-feu Proxmox désactivé sur les cartes |
| Code | état `envs/openstack` de `plateforme/infra` (clé `envs/openstack/terraform.tfstate`, même backend que les autres états) ; module `vm-noeud` de M08-E02 (plusieurs cartes, famille `debian13`, type de CPU), à compléter à l'étape 2 ; module `enregistrement-dns` pour A et PTR |
| Noms | `osctl01`, `oscmp01`, `oscmp02` dans `par1.medisphere.internal` (adresse OS-API) ; `openstack.par1.medisphere.internal` → 10.10.50.201 et `openstack-int.par1.medisphere.internal` → 10.10.50.200 (sans PTR : ce sont des services) |
| Ansible | `plateforme/ansible` : groupe d'inventaire `role_openstack` (étiquette `role-openstack`) ; rôles communs puis rôle `noeud_openstack` ; playbook `playbooks/openstack-noeuds.yml` |
| Réseau dans l'invité | `netplan` (cloud-init de l'image dorée le rend) ; le rôle prend la main : fichier `/etc/netplan/60-openstack.yaml`, configuration réseau de cloud-init désactivée |
| Temps | chrony vers la passerelle du VLAN 50 (10.10.50.1), comme tout le lab |

> ⚠️ **Attention** : le rôle `noeud_openstack` **remplace la configuration réseau** des nœuds et les **redémarre**. Une erreur (MAC, adresse, nom) peut rendre un nœud injoignable en SSH. Avant le premier passage : vérifie la console série (`root@pve01:~# qm terminal 2101`, sortie par `Ctrl+O`) et l'agent QEMU (`qm guest cmd 2101 ping`) des trois VMs ; prends un instantané (`ms-snapshot --prefix avant-reseau 2101 2102 2103`). Retour arrière : depuis la console, supprime `/etc/netplan/60-openstack.yaml` et `/etc/cloud/cloud.cfg.d/99-openstack-reseau.cfg`, lance `cloud-init clean --configs network` puis redémarre (ou reviens à l'instantané). Ces VMs sont neuves : rien d'autre n'en dépend.

**Travail demandé**

*A. Constater avant de construire*

1. Sur `pve01`, **sans rien modifier**, constate que la virtualisation imbriquée est active et que `vmbr1` et les VNets `vostun` et `vstopub` acceptent 9000 octets. Note dans ton journal ce que deviendrait une instance si `oscmp01` n'avait pas les extensions de virtualisation (option `nova_compute_virt_type` de Kolla, dont tu chercheras la valeur par défaut).

*B. Le code des VMs*

2. Lis l'interface du module `vm-noeud` (M08-E02 : nœuds de cluster à plusieurs cartes, type de CPU, adresses imposées) à sa dernière version publiée. Il lui manque deux choses pour nos nœuds : une **MAC imposée** par carte et une carte **sans adresse**. Étends-le (MR sur `plateforme/tofu-modules`) : ajout rétrocompatible, donc version **mineure**. Les cartes restent enregistrées dans NetBox (interface pour toutes, adresse pour les cartes adressées). Une carte sans adresse doit venir **après** toutes les cartes adressées : explique pourquoi dans le `README` du module (indice : comment Proxmox numérote `ipconfigN`).
3. Écris l'état `envs/openstack` : les trois VMs selon le plan, MAC selon la règle, puis les noms DNS des nœuds et des deux VIP. Plan relu en MR, `apply` par le pipeline. Pose l'ordre de démarrage en root (`osctl01` avant les calculs).
4. Vérifie dans Proxmox (`qm config`), dans NetBox (interfaces et adresses des VMs) et dans le DNS (A et PTR des nœuds, A des VIP).

*C. La préparation par Ansible*

5. Vérifie que l'inventaire dynamique range les trois VMs dans `role_openstack`, ajoute leurs clés d'hôte au `known_hosts` du projet (ou fais-leur confiance par la CA SSH de M06 si leurs certificats d'hôte sont émis) et applique les rôles communs.
6. Écris le rôle `noeud_openstack` :
   - il désactive la configuration réseau de cloud-init et écrit un `netplan` complet : chaque interface est reconnue par son **adresse MAC** et **renommée** (`ens18` à `ens21`), adresses et MTU selon le plan, la carte externe sans aucune adresse (ni IPv4, ni IPv6 de lien local, ni autoconfiguration) ;
   - les MAC et les adresses se **calculent** à partir du suffixe du nœud (une seule règle, la même que dans OpenTofu) : aucune table recopiée ;
   - la syntaxe est validée avant mise en place (`netplan generate`), le changement déclenche un redémarrage contrôlé, et le rôle vérifie **après** redémarrage noms, adresses et MTU ;
   - sur les calculs, il vérifie que `/dev/kvm` existe et que le module KVM est chargé ;
   - il vérifie que l'horloge est synchronisée.
   Passe `ansible-lint` (profil `production`). Pas de scénario Molecule pour ce rôle : dis dans le `README` du rôle pourquoi une instance Molecule à une carte ne le testerait pas, et ce qui le teste à la place.
7. Applique par le pipeline. Prouve ensuite, nœud par nœud : les noms et MTU des interfaces, l'absence d'adresse sur `ens21`, un `ping` de 8972 octets **sans fragmentation** entre nœuds sur le VLAN 51 et vers `ceph01` (10.10.30.51) sur le VLAN 30, la synchronisation de l'horloge, `/dev/kvm` sur les calculs.
8. Mets à jour la documentation : inventaire (`docs/cloud/inventaire-openstack.md` : VMs, cartes, MAC, adresses, rôles Kolla) et matrice des flux (rien de nouveau à cette étape : dis pourquoi).

**Critères de réussite**
- [ ] Les VMs 2101-2103 sont déclarées dans `envs/openstack` de `plateforme/infra` et conformes au plan (nom, vCPU, mémoire, CPU `host` sur les calculs, cartes sur les bons VNets avec la bonne MAC, MTU 9000 sur `net1` et `net2`, pas de pare-feu sur les cartes, étiquettes `env-m10` et `role-openstack`, pool `lab`).
- [ ] `osctl01`, `oscmp01`, `oscmp02` ont leurs A et PTR ; `openstack` et `openstack-int` résolvent vers 10.10.50.201 et 10.10.50.200.
- [ ] Sur chaque nœud : `ens18`, `ens19`, `ens20` portent les adresses du plan, `ens19` et `ens20` sont en MTU 9000 ; sur `osctl01`, `ens21` est montée **sans** adresse IPv4 ni IPv6.
- [ ] Un `ping -M do -s 8972` passe entre les nœuds sur le VLAN 51 et vers 10.10.30.51 sur le VLAN 30.
- [ ] `/dev/kvm` existe sur `oscmp01` et `oscmp02` ; l'horloge des trois nœuds est synchronisée.
- [ ] Le rôle `noeud_openstack` est sur `main` de `plateforme/ansible` ; un second passage du playbook donne `changed=0`.

**Vérification** : `lab/bin/check 10 02`

<details><summary>Indice 1</summary>

Côté Proxmox, le paramètre d'une carte `mtu=9000` (cartes virtio seulement) annonce la MTU à l'invité ; il ne peut pas dépasser celle du pont. Le fournisseur `bpg/proxmox` expose `mac_address`, `mtu` et `firewall` dans `network_device`, et `ip_config` dans `initialization` (une entrée par carte, **dans l'ordre**). Côté NetBox, un `netbox_interface` et un `netbox_ip_address` par carte adressée.
</details>

<details><summary>Indice 2</summary>

Avec netplan, une interface définie par `match: {macaddress: …}` et `set-name: …` est renommée au démarrage (netplan génère une règle `.link` pour udev). Deux fichiers qui définissent **la même interface sous deux noms** se contredisent : c'est pourquoi il faut retirer la configuration de cloud-init (`network: {config: disabled}` dans `/etc/cloud/cloud.cfg.d/`) et supprimer le fichier qu'il a généré. Pour une carte sans aucune adresse : `dhcp4: false`, `dhcp6: false`, `accept-ra: false`, `link-local: []`.
</details>

<details><summary>Indice 3</summary>

Pour calculer une MAC dans un modèle Jinja : le suffixe vient du dernier octet de `ansible_host`, le VLAN est une constante par carte ; `'%02d' | format(…)` n'est pas nécessaire puisque 30, 50, 51, 52 et 51-53 s'écrivent déjà sur deux chiffres hexadécimaux valides. Pour la vérification après redémarrage, `ansible.builtin.reboot` puis une nouvelle collecte des faits (`ansible.builtin.setup`, `gather_subset: network`).
</details>

**Pour aller plus loin** (facultatif) : lis la page « Hosts » de la documentation de Kolla (variables d'interface par hôte : `network_interface`, `api_interface`, `tunnel_interface`, `storage_interface`, `neutron_external_interface`) et imagine un nœud dont les interfaces portent des noms différents des autres : où mettrais-tu ses valeurs, sachant que `globals.yml` a la **priorité la plus haute** ? [Kolla : *Multinode Deployment*](https://docs.openstack.org/kolla-ansible/2026.1/user/multinode.html), [netplan : référence YAML](https://netplan.readthedocs.io/en/stable/netplan-yaml/).

---

### M10-E03 — Préparer Kolla-Ansible  `LAB` `★★`

> **Ticket PLAT-1103** — *De : Karim Benali*
> Kolla-Ansible 22 refuse ansible-core 2.21, et notre projet `plateforme/ansible` est en 2.21. Pas question de rétrograder l'un pour l'autre : deux environnements. Je veux un projet GitLab `plateforme/openstack` qui contient **tout** ce qu'il faut pour reconstruire le cloud — version de Kolla figée, inventaire, `globals.yml` commenté, mots de passe **chiffrés** — et rien qui ne se régénère. Relis l'ADR-0101 avant de commencer : elle dit ce qu'on a écarté et pourquoi.

**Objectifs pédagogiques**
- Isoler un outil de déploiement et ses dépendances (Python, ansible-core, collections) dans un projet `uv` dédié.
- Comprendre ce que contient une configuration Kolla : `globals.yml`, `passwords.yml`, inventaire, surcharges, certificats.
- Versionner un fichier de secrets généré, chiffré par Ansible Vault, et l'exploiter sans jamais le déchiffrer sur disque.
- Choisir les options structurantes d'un déploiement (distribution des images, pilote réseau, VIP) en connaissant les valeurs par défaut.

**Prérequis** : M10-E02 ; M04-E30 (Vault à deux identités, `outils/vault-pass-client.sh`) ; M01 (projets GitLab protégés, gabarits de CI).
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| ADR | [`ressources/M10-E03/ADR-0101-kolla-ansible.md`](../ressources/M10-E03/ADR-0101-kolla-ansible.md), à verser dans `docs/cloud/adr/` de `plateforme/medisphere` |
| Projet | GitLab `plateforme/openstack` (branche `main` protégée, fusion par MR, gabarits `qualite.yml` de `plateforme/ci-templates`), clone `~/src/openstack` sur `adm01` |
| Environnement | projet `uv`, Python 3.13 ; `kolla-ansible` figé à la dernière 22.x publiée (22.2.0 à la rédaction) ; `ansible-core` 2.20.x ; `openstacksdk` (pour les playbooks des objets du cloud, E05) |
| Collections | celles de Kolla (`kolla-ansible install-deps`) et `openstack.cloud` (pour E05), installées **dans le projet** (`./collections`, ignoré par Git) |
| Configuration | `etc/kolla/globals.yml`, `etc/kolla/passwords.yml`, `etc/kolla/config/`, `etc/kolla/certificates/` ; inventaire `inventaire/multinode` (+ `inventaire/host_vars/`) ; utilisé avec `--configdir etc/kolla` |
| Valeurs imposées | `kolla_base_distro: "debian"` ; `openstack_release: "2026.1"` ; `kolla_internal_vip_address: "10.10.50.200"`, `kolla_internal_fqdn: "openstack-int.par1.medisphere.internal"` ; `kolla_external_vip_address: "10.10.50.201"`, `kolla_external_fqdn: "openstack.par1.medisphere.internal"` ; `keepalived_virtual_router_id: "150"` ; `network_interface: "ens18"`, `tunnel_interface: "ens19"`, `storage_interface: "ens20"` ; interface externe `ens21` sur `osctl01` seulement ; pilote réseau **OVN** ; TLS externe (certificat en E04) ; pas de Cinder ni d'Octavia au palier 1 ; pas de Prometheus (mémoire) |
| Inventaire | `osctl01` dans `control`, `network`, `monitoring`, `storage` ; `oscmp01`, `oscmp02` dans `compute` ; connexion `admin` + `become` ; `deployment` = `localhost` |
| Secrets | `passwords.yml` chiffré sous l'identité `critique` (`$ANSIBLE_VAULT;1.2;AES256;critique`) ; mot de passe Vault de M04-E30 |

**Travail demandé**

1. Lis l'ADR-0101 et la page « Quick Start » de Kolla-Ansible 2026.1. Note dans ton journal : les étapes que tu vas reproduire, celles que tu vas faire autrement (pourquoi), et la limite de version d'ansible-core.
2. Crée le projet GitLab et son clone. Initialise le projet `uv` : version de Kolla-Ansible figée, ansible-core contraint, `openstacksdk`. Vérifie la version d'ansible-core **de ce projet**, puis celle de `~/src/ansible` : deux versions différentes cohabitent sur `adm01`. Réponds : que se passerait-il avec un seul environnement ? Avec des collections partagées dans `~/.ansible/collections` ?
3. Écris un `ansible.cfg` propre au projet : collections dans `./collections`, identité Vault `critique` par le script client de M04-E30 (copié dans `outils/`), réglages de performance recommandés par Kolla s'il y en a. Installe les dépendances de Kolla et `openstack.cloud`, vérifie **où** elles ont atterri.
4. Récupère les exemples fournis **par le paquet installé** (`share/kolla-ansible/` de l'environnement) : `globals.yml`, `passwords.yml`, inventaire `multinode`. Pourquoi partir des exemples de la version installée plutôt que d'un tutoriel, pour l'inventaire en particulier (relis les notes de version 2026.1) ?
5. Remplis l'inventaire (seulement les groupes du haut ; les groupes de services restent ceux de l'exemple) et `inventaire/host_vars/osctl01.yml` (interface externe). Remplis `globals.yml` avec les valeurs imposées, **en commentant chaque ligne modifiée** (pourquoi cette valeur, quel est le défaut). Les variables communes à tous les nœuds vont dans `globals.yml`, celles d'un seul nœud dans l'inventaire : pourquoi cette règle (précédence) ?
6. Génère les mots de passe, chiffre `passwords.yml` sous l'identité `critique` **sans qu'il existe un instant en clair dans le dépôt** (ni dans un commit, ni dans l'index), et prouve que Kolla saura le lire : une commande de Kolla qui charge la configuration sans rien déployer (cherche dans `kolla-ansible --help`) doit passer. Inscris le fichier au registre des secrets (emplacement, identité Vault, qui le déchiffre, procédure de rotation : palier 3).
7. `.gitignore` (collections, environnement virtuel, fichiers générés), `README.md` (prérequis, commande type, ce qui est versionné et pourquoi), pipeline minimal de MR : `yamllint` et un contrôle qui **échoue** si un fichier de `etc/kolla/` qui doit être chiffré ne l'est pas (`passwords.yml`, et plus tard tout `*.pem` ou `*.keyring` de `etc/kolla/`). Fusionne par MR. Verse l'ADR-0101 dans `docs/cloud/adr/`.

**Critères de réussite**
- [ ] `~/src/openstack` est un clone de `plateforme/openstack` ; `pyproject.toml` et `uv.lock` sont versionnés ; `uv run kolla-ansible` donne une version 22.x et `uv run ansible --version` une version 2.20.x, alors que `~/src/ansible` reste en 2.21.x.
- [ ] Les collections de Kolla et `openstack.cloud` sont installées dans le projet, pas dans `~/.ansible/collections`.
- [ ] `globals.yml` porte les valeurs imposées (distribution `debian`, OVN, VIP et noms, VRID 150, interfaces) ; l'interface externe n'est **pas** dans `globals.yml` mais dans l'inventaire de `osctl01`.
- [ ] L'inventaire range `osctl01` dans `control`, `network`, `monitoring`, `storage` et les calculs dans `compute`.
- [ ] `passwords.yml` est chiffré sous l'identité `critique` sur `main`, et ne l'a jamais été en clair dans l'historique.
- [ ] Le pipeline de MR échoue sur un `passwords.yml` en clair (preuve : une MR d'essai, refermée sans fusion).

**Vérification** : `lab/bin/check 10 03`

<details><summary>Indice 1</summary>

Avec `uv`, un projet sans paquet à publier : `uv init --bare` (ou `--no-package`), puis `uv add` avec des contraintes de version (`'kolla-ansible==22.2.*'`, `'ansible-core>=2.20,<2.21'`). Les exemples de configuration sont sous `.venv/share/kolla-ansible/` : `etc_examples/kolla/` et `ansible/inventory/`. Dans `ansible.cfg`, la clé `collections_path` (section `[defaults]`) décide où `ansible-galaxy` installe et où Ansible cherche.
</details>

<details><summary>Indice 2</summary>

`kolla-genpwd` accepte un chemin (`--passwords`). Pour ne jamais avoir le fichier en clair dans le dépôt : génère-le **hors** du dossier du dépôt (dossier temporaire en 700), chiffre-le là-bas avec `ansible-vault encrypt --encrypt-vault-id critique`, puis déplace le résultat. `ansible-vault view` permet de relire une valeur sans écrire de fichier en clair.
</details>

<details><summary>Indice 3</summary>

Parmi les actions de `kolla-ansible`, `prechecks` touche les nœuds ; d'autres se contentent de charger la configuration et l'inventaire (essaie une collecte de faits sur `localhost`, ou la validation de configuration… après avoir lu ce que chacune fait). Pour le contrôle de chiffrement en CI : la première ligne d'un fichier chiffré par Vault commence par `$ANSIBLE_VAULT;`.
</details>

**Pour aller plus loin** (facultatif) : Kolla sait lire et écrire ses mots de passe dans HashiCorp Vault (`kolla-writepwd`, `kolla-readpwd`) : compare avec Ansible Vault (module 25). Lis le chapitre « Ansible tuning » de la documentation de Kolla. [Kolla : *Quick Start*](https://docs.openstack.org/kolla-ansible/2026.1/user/quickstart.html), [Kolla : *Operating Kolla*](https://docs.openstack.org/kolla-ansible/2026.1/user/operating-kolla.html).

---

### M10-E04 — Déployer OpenStack  `LAB` `★★`

> **Ticket PLAT-1104** — *De : Claire Morel* — *Copie : Sophie Laurent*
> On déploie. Keystone, Glance, Placement, Nova, Neutron avec OVN, Heat et Horizon. L'API publique sur `openstack.par1.medisphere.internal`, en **HTTPS** avec un certificat de notre PKI dès le premier jour : Sophie ne veut pas voir un mot de passe passer en clair, même au labo. Je veux un compte rendu : durée de chaque étape, ce qui a échoué et pourquoi, et ce qui tourne où.

**Objectifs pédagogiques**
- Enchaîner les étapes d'un déploiement Kolla (`bootstrap-servers`, `prechecks`, `pull`, `deploy`, `post-deploy`) et comprendre ce que fait chacune.
- Fournir à HAProxy un certificat externe sans laisser de clé privée en clair dans le dépôt.
- Ouvrir des flux de façon ciblée dans la matrice de la bordure.
- Vérifier un déploiement : conteneurs et leur état de santé, catalogue, services de calcul, agents OVN.

**Prérequis** : M10-E03 ; M06-E18 (ACME de `ca01`) ; M07-E30 (matrice des flux v2, commune à `gw01` et `gw02`).
**Durée indicative** : 5 h (dont une bonne part d'attente).

**Contexte technique**
- Certificat externe : sujet et SAN `openstack.par1.medisphere.internal`, émis par le provisioner ACME `acme` de `ca01` (30 jours). Kolla attend, pour HAProxy, **un seul fichier** contenant le certificat (chaîne complète) **et** sa clé : `etc/kolla/certificates/haproxy.pem` par défaut (`kolla_external_fqdn_cert`). Dans le dépôt, ce fichier est **chiffré** sous l'identité `critique` (Ansible déchiffre de lui-même un fichier Vault qu'il copie).
- Le défi ACME HTTP-01 se fait sur le port 80 du nom demandé, donc de la VIP externe 10.10.50.201… qui n'existe pas encore avant le déploiement. Pour la **première** émission, `osctl01` porte la VIP à la main, le temps du défi, avec le client `step` (paquet du dépôt Smallstep, comme sur `adm01`). Le renouvellement automatique par Kolla est l'objet de M10-E27 ; d'ici là, le corrigé donne la procédure de renouvellement manuel (`step ca renew`), à jouer avant l'échéance.
- Flux nouveaux (matrice `pare_feu.yml`, commune aux deux passerelles) : `osctl01` (10.10.50.51) → `ca01` TCP 443 ; `ca01` (10.10.20.11) → 10.10.50.201 TCP 80.
- Services du palier 1 : ceux du cœur d'OpenStack que Kolla active par défaut (Keystone, Glance, Placement, Nova, Neutron, Heat, Horizon) ; Cinder (E10) et Octavia (E16) viendront plus tard. Glance range ses images sur `osctl01` (stockage `file`), Nova les disques des instances sur les calculs.
- Mot de passe administrateur : `keystone_admin_password` de `passwords.yml`.

> ⚠️ **Attention** : (1) avant de poser la VIP à la main, vérifie que **personne** ne la porte (`arping` depuis `osctl01`) : une adresse en double sur le VLAN 50 coupe les deux machines. Retire-la dès le certificat obtenu (et au plus tard avant le `deploy`, sinon keepalived la trouvera déjà présente). (2) `bootstrap-servers` installe Docker, modifie `/etc/hosts` et des réglages système des trois nœuds : prends un instantané des trois (`ms-snapshot --prefix avant-kolla 2101 2102 2103`) ; le retour arrière d'un déploiement raté est ce retour à l'instantané, pas un nettoyage à la main.

**Travail demandé**

*A. Le certificat externe*

1. Ajoute les deux flux à la matrice (MR, pipeline de `plateforme/ansible`). Prépare `osctl01` : client `step` et confiance dans `ca01` (par le code : le point d'entrée `client` du rôle `step_ca` de M06-E02 s'applique à d'autres groupes que `role_bastion`).
2. Émets le certificat : VIP posée à la main, défi ACME en mode autonome sur `osctl01`, VIP retirée. Rapatrie certificat et clé sur `adm01`, construis le fichier attendu par HAProxy, chiffre-le, supprime **toute** copie en clair (sur `osctl01` aussi). Inspecte le certificat (émetteur, SAN, durée). Ajoute la racine MédiSphère (publique) dans `etc/kolla/certificates/ca/`. Inscris la clé au registre des secrets et l'échéance dans ton journal.
3. Active le TLS externe dans `globals.yml` (commenté). Un script qui fait les étapes 2 et 3 sera bienvenu : il servira à chaque reconstruction.

*B. Le déploiement*

4. `bootstrap-servers` : lis d'abord ce qu'il va faire (documentation, tâches du rôle `baremetal` de l'environnement). Lance-le, puis constate sur un nœud : version de Docker, `/etc/hosts`, groupes de l'utilisateur.
5. `prechecks`, puis `pull` (mesure le temps et l'espace disque consommé sur chaque nœud), puis `deploy`. Note la durée de chaque étape. Si une étape échoue : lis le message, corrige **dans le dépôt**, relance la même étape. Chaque échec et sa correction vont dans le compte rendu.
6. `post-deploy` : où sont écrits `admin-openrc.sh` et `clouds.yaml` ? Pourquoi ne les utilises-tu pas tels quels (relis l'URL d'authentification qu'ils contiennent, et leur emplacement) ?
7. Écris `~/.config/openstack/clouds.yaml` (cloud `medisphere-admin` : projet `admin`, domaine `Default`, point d'accès **public**, racine MédiSphère comme autorité de confiance) et `secure.yaml` (600, mot de passe lu avec `ansible-vault view`). Obtiens un jeton.

*C. Vérifier*

8. Relève : les conteneurs de chaque nœud et ceux qui ne sont pas `healthy` ; le catalogue (`openstack endpoint list`), en distinguant interfaces `public` et `internal` ; les services de calcul ; les agents réseau (avec OVN : lesquels, et pourquoi pas d'agent L3 ni DHCP) ; les hyperviseurs. Sur `osctl01`, retrouve les VIP et le VRID dans la configuration de keepalived générée.
9. Compte rendu `docs/cloud/changements/CHG-1104-deploiement-initial.md` : versions (Kolla, images), durées, incidents, état final, échéance du certificat. Fusionne `globals.yml` et le reste par MR.

**Critères de réussite**
- [ ] Les VIP 10.10.50.200 et 10.10.50.201 sont portées par `osctl01` ; keepalived y est configuré avec le VRID 150.
- [ ] `https://openstack.par1.medisphere.internal:5000/v3` répond avec un certificat émis par la PKI MédiSphère, valide pour ce nom, vérifiable avec la seule racine MédiSphère.
- [ ] `openstack --os-cloud medisphere-admin token issue` fonctionne depuis `adm01` ; les points d'accès `public` du catalogue sont en `https://openstack.par1.medisphere.internal`.
- [ ] Deux services `nova-compute` (`oscmp01`, `oscmp02`) sont activés et `up` ; les contrôleurs OVN des trois nœuds sont vivants ; aucun conteneur n'est `unhealthy`.
- [ ] Les images en service sont des images `debian` de la série 2026.1.
- [ ] Dans le dépôt : `etc/kolla/certificates/haproxy.pem` est chiffré sous l'identité `critique` ; aucune clé privée en clair n'existe sur `adm01` ni sur `osctl01` hors des emplacements de Kolla ; `secure.yaml` est en 600 et `clouds.yaml` ne contient aucun mot de passe.

**Vérification** : `lab/bin/check 10 04`

<details><summary>Indice 1</summary>

Le client `step` sait obtenir un certificat ACME en mode autonome : `step ca certificate <nom> <crt> <key> --provisioner acme --standalone` (il écoute sur le port 80 le temps du défi, donc sous `sudo`). Pour poser une adresse le temps d'une opération : `ip addr add …/24 dev ens18`, puis `ip addr del`. `arping -D` détecte une adresse déjà utilisée.
</details>

<details><summary>Indice 2</summary>

Le fichier d'HAProxy est la concaténation, dans cet ordre, du certificat, de l'intermédiaire, puis de la clé. `ansible-vault encrypt --encrypt-vault-id critique` le chiffre ; le module `copy` d'Ansible (celui qu'utilise Kolla pour déposer les certificats) déchiffre une source Vault de lui-même, à condition que l'identité soit disponible. Vérifie, après le `deploy`, ce qu'il y a sur `osctl01` dans `/etc/kolla/haproxy/`.
</details>

<details><summary>Indice 3</summary>

Pour la santé : `docker ps --filter health=unhealthy` et `docker ps --format '{{.Names}} {{.Status}}'`. Pour les agents réseau avec OVN : `openstack network agent list` montre des agents « OVN Controller Gateway agent », « OVN Controller agent », « OVN Metadata agent ». Dans `clouds.yaml`, la clé `cacert` désigne le magasin de confiance ; sans elle, le client Python utilise sa propre liste d'autorités (paquet `certifi`), qui ne connaît pas MédiSphère.
</details>

**Pour aller plus loin** (facultatif) : lis le `haproxy.cfg` généré sur `osctl01` (`/etc/kolla/haproxy/`) et retrouve, pour Keystone, le *frontend* interne, le *frontend* externe et le *backend*. Compare la configuration générée de Nova (`/etc/kolla/nova-api/nova.conf`) à ce que tu aurais écrit à la main d'après le guide d'installation. [Kolla : *TLS*](https://docs.openstack.org/kolla-ansible/2026.1/admin/tls.html), [Kolla : *Operating Kolla*](https://docs.openstack.org/kolla-ansible/2026.1/user/operating-kolla.html).

---

### M10-E05 — Keystone : domaines, projets, rôles  `LAB` `★★`

> **Ticket SEC-1105** — *De : Sophie Laurent* — *Copie : Julien Petit*
> Avant que la moindre équipe n'entre : un **domaine** MédiSphère, séparé du domaine `Default` où vivent l'administrateur et les comptes de service ; un projet par équipe et par environnement ; des droits donnés à des **groupes**, jamais à des personnes une par une ; trois rôles seulement (lecture, membre, administration). Julien doit pouvoir travailler dans la recette de MédiAgenda et seulement regarder la production. Et pour les robots (OpenTofu, CI) : pas de mot de passe d'humain, montre-moi ce que Keystone propose.

**Objectifs pédagogiques**
- Manipuler le modèle d'identité de Keystone : domaines, projets, utilisateurs, groupes, rôles et attributions, portée d'un jeton.
- Décrire ces objets par du code (collection `openstack.cloud`), secrets en Vault.
- Configurer des clients (`clouds.yaml`, `secure.yaml`) pour plusieurs identités.
- Découvrir les *application credentials* (« identifiants d'application » : un secret délégué par un utilisateur, limité à un projet, à des rôles et à une durée, révocable ; le module garde le terme anglais, celui de la CLI et de la documentation) pour l'automatisation.

**Prérequis** : M10-E04.
**Durée indicative** : 3 h.

**Contexte technique**

| Élément | Valeur |
|---|---|
| Domaine | `medisphere` (description : « Équipes de MédiSphère ») |
| Projets (domaine `medisphere`) | `plateforme`, `mediagenda-dev`, `mediagenda-prod` |
| Groupes (domaine `medisphere`) | `equipe-plateforme` : `<MOI>`, `karim.benali` ; `equipe-mediagenda` : `julien.petit` |
| Attributions | `equipe-plateforme` : `member` sur `plateforme`, `reader` sur `mediagenda-dev` et `mediagenda-prod` ; `equipe-mediagenda` : `member` sur `mediagenda-dev`, `reader` sur `mediagenda-prod` |
| Code | `plateforme/openstack` : `playbooks/identite.yml` (collection `openstack.cloud`, cloud `medisphere-admin`), données dans `donnees/identite.yml` ; mots de passe des comptes dans `donnees/vault-identite.yml` (Vault `critique`) |
| Clients | `~/.config/openstack/clouds.yaml` : `medisphere-admin` (E04), `medisphere-plateforme` (`<MOI>`, projet `plateforme`), `medisphere-mediagenda-dev` (`julien.petit`, projet `mediagenda-dev`) ; mots de passe dans `secure.yaml` (600) |

**Travail demandé**

*A. Explorer (domaine jetable `essai-e05`)*

1. Liste les domaines, projets, utilisateurs et rôles existants. Quels comptes vivent dans `Default` et à quoi servent-ils ? Quels rôles Keystone a-t-il créés à l'amorçage, et lesquels s'impliquent l'un l'autre (`openstack implied role list`) ?
2. Dans un domaine jetable `essai-e05`, crée par la CLI un projet, un groupe, un utilisateur (mot de passe saisi au clavier), mets-le dans le groupe, attribue `member` au groupe sur le projet. Obtiens un jeton **en tant que cet utilisateur** limité au projet (variables `OS_*` d'un seul shell ou cloud temporaire) et inspecte-le : à quoi sert la portée ? Que se passe-t-il si tu demandes un jeton limité à un projet où il n'a aucun rôle ?
3. Supprime tout le domaine d'essai : pourquoi faut-il le **désactiver** d'abord ? Que deviennent ses utilisateurs ?

*B. Le domaine de MédiSphère, par le code*

4. Écris `playbooks/identite.yml` et ses données : domaine, projets, groupes, utilisateurs, appartenance aux groupes, attributions de rôles, selon le tableau. Les mots de passe viennent de Vault et ne sont posés **qu'à la création** (un humain change le sien ensuite). Aucune tâche ne doit afficher un mot de passe, même en mode verbeux. Un second passage ne change rien.
5. Applique-le. Vérifie les attributions effectives de `julien.petit` (avec la résolution des groupes) et du groupe `equipe-mediagenda`.

*C. Les clients*

6. Ajoute à `clouds.yaml` les clouds `medisphere-plateforme` et `medisphere-mediagenda-dev`, mots de passe dans `secure.yaml`. Prouve : `julien.petit` liste les serveurs de `mediagenda-dev` ; il **ne peut pas** obtenir de jeton pour `plateforme` ; avec un jeton sur `mediagenda-prod`, il peut lister mais pas créer (essaie de créer un groupe de sécurité : quel code HTTP ?).

*D. Les robots*

7. En tant que `<MOI>` sur `plateforme`, crée une *application credential* `ac-essai-e05` limitée au rôle `member`, avec une date d'expiration (une journée), et utilise-la dans un cloud temporaire (`auth_type: v3applicationcredential`) pour lister les réseaux. Réponds dans ton journal : qui la possède, que devient-elle si l'utilisateur perd son rôle ou est supprimé, pourquoi `--unrestricted` est dangereux, où rangerait-on le secret pour OpenTofu en CI (palier 2). Supprime-la.

**Critères de réussite**
- [ ] Le domaine `medisphere` existe, activé, avec les projets `plateforme`, `mediagenda-dev`, `mediagenda-prod` et les groupes `equipe-plateforme`, `equipe-mediagenda`.
- [ ] `<MOI>`, `karim.benali` et `julien.petit` existent dans le domaine `medisphere` et appartiennent à leur groupe ; les rôles sont attribués aux **groupes** selon le tableau, aucun rôle n'est attribué directement à un utilisateur sur ces projets.
- [ ] Le domaine `essai-e05` et l'*application credential* `ac-essai-e05` n'existent plus.
- [ ] Les clouds `medisphere-plateforme` et `medisphere-mediagenda-dev` obtiennent un jeton ; `clouds.yaml` ne contient aucun mot de passe et `secure.yaml` est en 600.
- [ ] `playbooks/identite.yml` est sur `main` de `plateforme/openstack`, ses mots de passe chiffrés sous l'identité `critique` ; un second passage donne `changed=0`.

**Vérification** : `lab/bin/check 10 05`

<details><summary>Indice 1</summary>

Les commandes utiles : `openstack domain create|set|delete`, `project create --domain`, `group create --domain`, `user create --domain … --password-prompt`, `group add user`, `role add --group … --group-domain … --project … --project-domain …`, `role assignment list --names --effective`. Pour un jeton d'un autre utilisateur sans toucher à `clouds.yaml` : un sous-shell avec `OS_AUTH_URL`, `OS_USERNAME`, `OS_USER_DOMAIN_NAME`, `OS_PROJECT_NAME`, `OS_PROJECT_DOMAIN_NAME`, `OS_IDENTITY_API_VERSION=3` et un mot de passe lu par `read -s`.
</details>

<details><summary>Indice 2</summary>

Collection `openstack.cloud` : `identity_domain`, `project`, `identity_group`, `identity_user` (paramètre `update_password`), `group_assignment`, `role_assignment`. Lis leur documentation **dans ton environnement** (`uv run ansible-doc openstack.cloud.role_assignment`) : les paramètres qui désignent un domaine diffèrent d'un module à l'autre. Les modules lisent `clouds.yaml` et `secure.yaml` de `~/.config/openstack/` (paramètre `cloud`).
</details>

<details><summary>Indice 3</summary>

`secure.yaml` a la même structure que `clouds.yaml` (`clouds: <nom>: auth: password: …`) : le client fusionne les deux. Un 403 (`Forbidden`) dit « authentifié, mais pas autorisé » ; un 401 dit « pas authentifié ». Une *application credential* se crée avec `openstack application credential create` ; son secret n'est affiché qu'une fois.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Default roles » de Keystone (rôles `reader`, `member`, `admin`, portée système, domaine, projet) et l'état de `enforce_scope` / `enforce_new_defaults` dans les services de 2026.1 ; tu y reviendras en E23. Imagine la fédération de ce domaine avec Keycloak (module 24) : que deviendraient les mots de passe ? [Keystone : *Default roles*](https://docs.openstack.org/keystone/2026.1/admin/service-api-protection.html), [*Application credentials*](https://docs.openstack.org/keystone/2026.1/user/application_credentials.html), [collection `openstack.cloud`](https://docs.ansible.com/ansible/latest/collections/openstack/cloud/).

---

### M10-E06 — Glance : les images  `LAB` `★`

> **Ticket DEV-1106** — *De : Julien Petit*
> Il nous faut du Debian 13 (toutes nos VMs) et du Rocky 10 (un partenaire nous impose une distribution de la famille Red Hat pour son agent). Des images **officielles** et vérifiées, pas un fichier trouvé on ne sait où. Rocky ne concerne que l'équipe Plateforme pour l'instant : je ne veux pas la voir dans ma liste tant qu'elle n'est pas validée.

**Objectifs pédagogiques**
- Publier une image dans Glance avec sa somme vérifiée de bout en bout (source officielle → poste → Glance).
- Comprendre les formats (`qcow2`, `raw`) et les propriétés d'image qui changent le comportement de Nova.
- Maîtriser la visibilité des images (`public`, `private`, `shared`, `community`) et le partage entre projets.

**Prérequis** : M10-E04 ; M10-E05 (projets) pour le partage.
**Durée indicative** : 1 h 30.

**Contexte technique**
- Sources : Debian 13 *genericcloud* amd64, `https://cloud.debian.org/images/cloud/trixie/latest/` (fichier `debian-13-genericcloud-amd64.qcow2`, sommes dans `SHA512SUMS`) ; Rocky Linux 10 *GenericCloud* x86_64, `https://dl.rockylinux.org/pub/rocky/10/images/x86_64/` (fichier `Rocky-10-GenericCloud-Base.latest.x86_64.qcow2`, somme dans le fichier `.CHECKSUM` voisin).
- Glance range pour l'instant ses images sur le disque de `osctl01` (stockage `file`) ; elles passeront sur Ceph au palier 2 (E10), où le format comptera.
- Noms et propriétés : `debian-13` (`os_distro=debian`, `os_version=13`) et `rocky-10` (`os_distro=rocky`, `os_version=10`) ; pour les deux : `hw_disk_bus=scsi`, `hw_scsi_model=virtio-scsi`, `hw_qemu_guest_agent=yes`, `os_type=linux`. Rocky 10 exige un CPU `x86-64-v3` (AVX2…) : avec KVM, Nova présente par défaut aux instances un modèle proche du CPU de l'hôte, ce qui suffit sur `pve01` ; note-le pour le jour où un calcul aurait un CPU plus ancien.
- Visibilité : `debian-13` publique ; `rocky-10` partagée avec le seul projet `plateforme`.
- Brouillons : `~/m10/e06/`.

**Travail demandé**
1. Télécharge les deux images et leurs fichiers de sommes dans `~/m10/e06/`. Vérifie les sommes. Pour Debian, va plus loin : le fichier `SHA512SUMS` est-il lui-même signé ? Que faudrait-il pour vérifier la signature, et qu'est-ce que cela prouve de plus ?
2. Inspecte chaque image (`qemu-img info`) : format, taille virtuelle, taille du fichier. Explique la différence. Réponds dans ton journal : pourquoi faudra-t-il convertir ces images en `raw` quand Glance et Nova seront sur Ceph (E10), et combien de place prendrait alors l'image Debian ?
3. Publie `debian-13` (publique, propriétés du contexte). Compare la somme calculée par Glance (`os_hash_algo`, `os_hash_value`) à celle du fichier publié par Debian : la chaîne de confiance est-elle complète ?
4. Publie `rocky-10` avec la visibilité `shared` et les propriétés du contexte ; partage-la avec `plateforme`. Liste les images en tant que `julien.petit` puis en tant que `<MOI>` : qui la voit, avant et après que le projet `plateforme` a **accepté** le partage ?
5. Explique dans ton journal l'effet de chaque propriété posée : sur quel matériel virtuel l'instance verra son disque, ce que permet `hw_qemu_guest_agent` (et ce qu'il faut **dans** l'image pour que ce soit utile), et l'intérêt de `os_distro` pour un outil qui consomme le catalogue.
6. Supprime les fichiers téléchargés de `~/m10/e06/` une fois les images publiées et vérifiées.

**Critères de réussite**
- [ ] `debian-13` est active, publique, au format `qcow2` (elle passera en `raw` en E10), avec les propriétés demandées.
- [ ] `rocky-10` est active, en visibilité `shared`, avec les propriétés demandées ; le projet `plateforme` en est membre et a accepté le partage ; `julien.petit` ne la voit pas.
- [ ] Les deux images ont une somme SHA-512 calculée par Glance.

**Vérification** : `lab/bin/check 10 06`

<details><summary>Indice 1</summary>

`sha512sum --check --ignore-missing SHA512SUMS` vérifie seulement les fichiers présents. `qemu-img` est dans le paquet `qemu-utils`. `openstack image create --file … --disk-format qcow2 --container-format bare --property clé=valeur …` ; `--public`, `--shared`, `--private`, `--community`.
</details>

<details><summary>Indice 2</summary>

Partage : `openstack image add project <image> <projet>` (avec `--project-domain`) côté propriétaire ; côté projet invité, `openstack image set --accept <image>` (ou `openstack image member …` selon ta version de la CLI). Tant que le membre est `pending`, l'image n'apparaît pas dans la liste par défaut du projet invité.
</details>

**Pour aller plus loin** (facultatif) : l'importation interopérable de Glance (`openstack image create --import`, méthodes `web-download` et `glance-direct`) et la conversion de format côté serveur (*image conversion plugin*). Construire ses propres images Debian pour OpenStack avec Packer (module 03) : que changerait-on ? [Glance : *Useful image properties*](https://docs.openstack.org/glance/2026.1/admin/useful-image-properties.html), [Debian : images cloud](https://cloud.debian.org/images/cloud/).

---

### M10-E07 — Nova : gabarits, clés et première instance  `LAB` `★★`

> **Ticket DEV-1107** — *De : Julien Petit*
> On peut avoir trois tailles standard, comme chez les fournisseurs publics ? Petit, moyen, grand, et pas de taille sur mesure à chaque demande. Et je voudrais voir une première machine démarrer, même sans réseau public pour l'instant, pour comprendre ce que je vais demander.

**Objectifs pédagogiques**
- Définir un catalogue de gabarits adapté à la capacité réelle des calculs.
- Comprendre les paires de clés (appartenance, usage par cloud-init) et le réseau minimal d'une instance.
- Suivre la vie d'une instance : états, ordonnancement, hyperviseur choisi, domaine libvirt, journal de console.

**Prérequis** : M10-E05 (projet `plateforme`, cloud `medisphere-plateforme`), M10-E06 (image `debian-13`).
**Durée indicative** : 2 h 30.

**Contexte technique**
- Gabarits publics : `m1.petit` (1 vCPU, 1024 Mio, disque 10 Go), `m1.moyen` (2 vCPU, 2048 Mio, 20 Go), `m1.grand` (2 vCPU, 4096 Mio, 40 Go). Décrits par du code : `playbooks/catalogue.yml` et `donnees/catalogue.yml` de `plateforme/openstack`.
- Paire de clés : `cle-adm01`, appartenant à `<MOI>`, clé publique de `~/.ssh/id_ed25519.pub` de `adm01`.
- Réseau du projet `plateforme` : `reseau-plateforme`, sous-réseau `sous-reseau-plateforme` 172.16.10.0/24, passerelle 172.16.10.1, DHCP, résolveurs 10.10.20.10 et 10.10.20.16. Pas de routeur dans cet exercice (E08).
- Première instance : `essai01`, projet `plateforme`, `m1.petit`, `debian-13`, `cle-adm01`, sur `reseau-plateforme`. Elle sert encore en E08.
- Dans un conteneur Kolla : `sudo docker exec nova_libvirt virsh list --all` sur un calcul.

**Travail demandé**
1. Relève la capacité des calculs vue par Nova (`openstack hypervisor show` : vCPU, mémoire, disque) et les rapports de surréservation par défaut (cherche `cpu_allocation_ratio`, `ram_allocation_ratio`, `disk_allocation_ratio` et la mémoire réservée à l'hôte dans la documentation de Nova 2026.1). Combien de `m1.grand` peut-on lancer au plus ? Pourquoi est-ce peu, et pourquoi ne pas surréserver la mémoire ?
2. Écris le catalogue de gabarits par le code, applique, vérifie. Pourquoi un gabarit est-il plutôt immuable (que se passe-t-il pour les instances existantes si on le modifie) ?
3. En tant que `<MOI>`, importe ta clé publique. Qui peut voir et utiliser cette paire ? Un collègue du même projet peut-il lancer une instance avec ta clé ?
4. En tant que `<MOI>`, crée le réseau et le sous-réseau de `plateforme`. Note la MTU que Neutron a choisie pour ce réseau : d'où vient-elle (tu y reviendras en E08) ?
5. Lance `essai01`. Suis ses états (`BUILD`, `ACTIVE`) et ses événements (`openstack server event list`). En tant qu'administrateur, trouve sur quel calcul elle tourne, et sur ce calcul le domaine libvirt correspondant et son disque. Lis le journal de console : cloud-init a-t-il fini ? Quelle adresse a-t-elle reçue ? A-t-il pu joindre le service de métadonnées (cherche la clé SSH injectée) ?
6. Arrête, démarre, redémarre `essai01` ; relève l'état de Nova et celui de libvirt à chaque étape. Ouvre la console graphique (`openstack console url show`) depuis le navigateur de ton poste : quel service répond, sur quelle VIP ?

**Critères de réussite**
- [ ] Les gabarits `m1.petit`, `m1.moyen`, `m1.grand` existent, publics, avec exactement les ressources demandées ; `playbooks/catalogue.yml` est sur `main`.
- [ ] La paire de clés `cle-adm01` appartient à `<MOI>` et correspond à la clé publique de `adm01`.
- [ ] `reseau-plateforme` (projet `plateforme`) a un sous-réseau 172.16.10.0/24 avec DHCP et les deux résolveurs du lab.
- [ ] `essai01` est `ACTIVE` dans `plateforme`, en `m1.petit`, à partir de `debian-13`, avec `cle-adm01`, une adresse dans 172.16.10.0/24 ; son journal de console montre la fin de cloud-init.

**Vérification** : `lab/bin/check 10 07`

<details><summary>Indice 1</summary>

`openstack.cloud.compute_flavor` (paramètres `ram`, `vcpus`, `disk`, `is_public`). Dans Kolla, les rapports d'allocation et `reserved_host_memory_mb` se surchargent dans `etc/kolla/config/nova.conf` (ou `nova/nova-compute.conf`) : ne le fais pas ici, note seulement ce que tu ferais.
</details>

<details><summary>Indice 2</summary>

`openstack server show essai01 -c OS-EXT-SRV-ATTR:host -c OS-EXT-SRV-ATTR:instance_name` (en administrateur) donne le calcul et le nom du domaine libvirt (`instance-0000000N`). `openstack console log show essai01 | tail` ; cloud-init affiche les empreintes des clés d'hôte et une ligne « Cloud-init … finished ».
</details>

**Pour aller plus loin** (facultatif) : propriétés de gabarit (`hw:cpu_policy`, `quota:disk_read_iops_sec`…) et agrégats d'hôtes ; gabarits privés réservés à un projet. [Nova : *Flavors*](https://docs.openstack.org/nova/2026.1/user/flavors.html), [Nova : *Overcommitting CPU and RAM*](https://docs.openstack.org/nova/2026.1/admin/scheduling.html).

---

### M10-E08 — Neutron et OVN : réseaux, routeurs, IP flottantes  `LAB` `★★`

> **Ticket PLAT-1108** — *De : Karim Benali*
> `essai01` tourne, mais personne ne peut la joindre. Il faut le réseau externe — VLAN 52, passerelle de la bordure, une plage d'IP flottantes —, un routeur pour le projet, un groupe de sécurité et une IP flottante. Et je veux que tu saches **où** passe le paquet : quelle machine fait la traduction, quel flux OVN, quelle MTU. C'est ce qu'on te demandera le jour où une IP flottante ne répond plus.

**Objectifs pédagogiques**
- Créer un réseau externe de type fournisseur (*flat*) et comprendre son lien avec l'interface physique (`physnet1`, `br-ex`).
- Router un réseau de projet vers l'extérieur (SNAT) et publier une instance par IP flottante (DNAT).
- Écrire des groupes de sécurité minimaux.
- Lire la traduction OVN d'un réseau Neutron (bases *Northbound* et *Southbound*, passerelle) et la MTU d'un réseau Geneve.

**Prérequis** : M10-E07 (`essai01`).
**Durée indicative** : 3 h.

**Contexte technique**
- Réseau externe : `ext-net`, administré par l'équipe Plateforme (projet `admin`), `--external`, type `flat`, réseau physique `physnet1` (associé par Kolla au pont `br-ex` et à `ens21` de `osctl01`) ; sous-réseau `ext-sous-reseau` 10.10.52.0/24, passerelle 10.10.52.1 (VIP de la bordure), **sans DHCP**, plage d'allocation 10.10.52.200-10.10.52.249, résolveurs 10.10.20.10 et 10.10.20.16. Décrit par du code : `playbooks/reseau-externe.yml` de `plateforme/openstack`.
- Projet `plateforme` : routeur `routeur-plateforme` (passerelle sur `ext-net`, interface sur `sous-reseau-plateforme`) ; groupe de sécurité `ssh-icmp-admin` : SSH et ICMP entrants depuis 10.10.10.0/24 (MGMT) seulement.
- Bordure : le VLAN 52 est routé par `gw01`/`gw02` ; MGMT joint tout le lab ; rien à ouvrir dans cet exercice. L'intégration complète du VLAN 52 (sortie vers Internet, DNS, VPN) est l'objet de M10-E12.
- OVN dans les conteneurs de `osctl01` : `ovn_nb_db` (`ovn-nbctl`), `ovn_sb_db` (`ovn-sbctl`), `openvswitch_vswitchd` (`ovs-vsctl`, `ovs-ofctl`).

**Travail demandé**
1. Avant de créer quoi que ce soit, constate sur `osctl01` : le pont `br-ex` et son port `ens21` ; la correspondance `physnet1:br-ex` déclarée à OVN ; le fait que `osctl01` soit une **passerelle** OVN et pas les calculs. Où Kolla l'a-t-il décidé ?
2. Écris et applique `playbooks/reseau-externe.yml`. Pourquoi pas de DHCP ? Pourquoi `--external` suffit-il pour que les projets y branchent leurs routeurs, sans `--share` ? Quelle MTU Neutron a-t-il donnée à `ext-net`, et laquelle à `reseau-plateforme` (E07) ? Explique l'écart à partir de l'en-tête Geneve et de l'option `global_physnet_mtu` de Neutron, et dis pourquoi la MTU 9000 du VLAN 51 ne change pas celle des réseaux de projet (palier 2 : E12).
3. En tant que `<MOI>`, crée le routeur, branche-le sur `ext-net` et sur ton sous-réseau. Relève l'adresse prise par la passerelle du routeur sur `ext-net`.
4. Crée le groupe de sécurité, attache-le à `essai01`. Pourquoi le groupe `default` ne suffit-il pas, et pourquoi ne pas l'ouvrir à `0.0.0.0/0` ?
5. Crée une IP flottante, associe-la à `essai01`. Depuis `adm01` : `ping`, puis `ssh debian@<IP-FLOTTANTE>`. Dans l'instance : l'adresse privée, la route par défaut, la MTU de l'interface, le résolveur.
6. Lis la traduction OVN : le commutateur logique et le routeur logique de ton projet (`ovn-nbctl show`), les règles NAT du routeur (`lr-nat-list`), la passerelle choisie (`ovn-sbctl show`, *chassis* et ports de passerelle). Décris dans ton journal le trajet aller et retour d'un `ping` de `adm01` vers l'IP flottante : interfaces, VLAN, traductions, nœud.
7. Garde le réseau, le routeur et le groupe de sécurité : ils servent au palier 2. Garde aussi `essai01` et son IP flottante jusqu'au palier 2 : E10 la supprimera avant de changer le stockage de Nova (libère alors l'IP flottante). Rédige `docs/cloud/reseau-projets.md` : le modèle (réseau externe, routeur par projet, groupes), les noms, les MTU, ce qu'un projet peut et ne peut pas faire.

**Critères de réussite**
- [ ] `ext-net` est externe, de type `flat` sur `physnet1`, MTU 1500 ; son sous-réseau 10.10.52.0/24 a la passerelle 10.10.52.1, pas de DHCP, la plage d'allocation 10.10.52.200-249 ; `playbooks/reseau-externe.yml` est sur `main`.
- [ ] `routeur-plateforme` (projet `plateforme`) a sa passerelle sur `ext-net` et une interface sur `sous-reseau-plateforme`.
- [ ] Le groupe `ssh-icmp-admin` n'autorise en entrée que TCP 22 et ICMP, depuis 10.10.10.0/24.
- [ ] `essai01` a une IP flottante de 10.10.52.200-249 ; elle répond au `ping` et en SSH (port 22) depuis `adm01`.
- [ ] `reseau-plateforme` a une MTU de 1442 (réseau Geneve ; E12 la portera à 1500).
- [ ] `docs/cloud/reseau-projets.md` est sur `main` de `plateforme/medisphere`.

**Vérification** : `lab/bin/check 10 08`

<details><summary>Indice 1</summary>

`sudo docker exec openvswitch_vswitchd ovs-vsctl show` liste les ponts ; la correspondance et le rôle de passerelle sont dans les `external_ids` de la table `Open_vSwitch` (`ovs-vsctl get open . external_ids`) : regarde `ovn-bridge-mappings` et `ovn-cms-options`. Comparer avec un calcul.
</details>

<details><summary>Indice 2</summary>

`openstack.cloud.network` (`external`, `provider_network_type`, `provider_physical_network`) et `openstack.cloud.subnet` (`is_dhcp_enabled`, `gateway_ip`, `allocation_pool_start`, `allocation_pool_end`, `dns_nameservers`). Côté CLI : `router create`, `router set --external-gateway`, `router add subnet`, `security group create`, `security group rule create --protocol … --dst-port … --remote-ip …`, `floating ip create`, `server add floating ip`.
</details>

<details><summary>Indice 3</summary>

Dans `ovn-nbctl lr-nat-list neutron-<ID-ROUTEUR>`, une règle `snat` couvre tout le sous-réseau (sortie des instances sans IP flottante), une règle `dnat_and_snat` relie une IP flottante à une adresse privée. Le port de passerelle du routeur (`lrp-…`) est « lié » à un *chassis* : celui de `osctl01`. Le surcoût Geneve retenu par Neutron (`max_header_size` du pilote, plus l'en-tête IP) explique 1500 − 1442.
</details>

**Pour aller plus loin** (facultatif) : les IP flottantes distribuées (`neutron_ovn_distributed_fip`) : ce qu'elles changent au trajet et ce qu'elles exigent des calculs (une carte sur le VLAN 52 chacun). Les réseaux fournisseurs VLAN pour brancher une instance directement sur un VLAN du lab. [Kolla : *Neutron*](https://docs.openstack.org/kolla-ansible/2026.1/reference/networking/neutron.html), [Neutron : *OVN*](https://docs.openstack.org/neutron/2026.1/admin/ovn/), [Neutron : *MTU considerations*](https://docs.openstack.org/neutron/2026.1/admin/config-mtu.html).

---

### M10-E09 — Questions : architecture d'OpenStack  `Q` `★★`

> **Ticket PLAT-1109** — *De : Karim Benali*
> Tu as tout déployé et tout essayé. Maintenant, sans clavier : je veux savoir si tu as compris ce que tu as fait. Ce sont les questions que Nadia posera aux prochaines recrues de l'astreinte.

**Objectifs pédagogiques**
- Consolider le modèle d'architecture d'OpenStack et de son déploiement par Kolla.
- Relier chaque symptôme probable au service qui le produit.

**Prérequis** : M10-E02 à M10-E08.
**Durée indicative** : 1 h 30.

**Travail demandé**

Réponds par écrit, en t'appuyant sur ce que tu as observé dans ton lab.

1. Décris le chemin d'un `openstack server create` depuis `adm01` jusqu'au démarrage du domaine libvirt : quels services, dans quel ordre, par quel canal (HTTP à travers HAProxy, RabbitMQ, base de données). Où intervient Placement ? Où intervient Neutron ?
2. Pourquoi `nova-compute` ne parle-t-il **jamais** directement à la base de données ? Quel service le fait pour lui, et pour quelle raison de sécurité ?
3. *(QCM)* Le catalogue de Keystone contient pour chaque service des points d'accès `public`, `internal` et `admin`. Dans ton déploiement, que se passe-t-il ?
   - A. Les trois existent et pointent vers la même URL
   - B. `public` pointe vers la VIP externe en HTTPS, `internal` vers la VIP interne en HTTP ; l'interface `admin` n'est plus utilisée par la plupart des services
   - C. Seul `public` existe : les services se parlent sans Keystone
   - D. `internal` pointe vers l'adresse réelle de `osctl01`, sans passer par HAProxy
4. Une instance est `ACTIVE` mais ne répond pas au `ping` sur son IP flottante. Liste, du plus probable au moins probable, cinq causes possibles dans ton architecture, et pour chacune la commande qui la confirme ou l'écarte.
5. Que perd-on si `osctl01` redémarre ? Distingue ce qui s'arrête pour les **utilisateurs de l'API**, pour les **instances déjà lancées** sans IP flottante, et pour celles **avec** IP flottante. Pourquoi cette différence ?
6. *(QCM)* Avec OVN, le service DHCP des réseaux de projet est rendu par :
   - A. un agent `neutron-dhcp-agent` sur `osctl01`
   - B. `ovn-controller` sur le nœud où tourne l'instance, à partir des flux logiques
   - C. le service de métadonnées
   - D. la bordure `gw01`
7. Pourquoi Kolla déploie-t-il **HAProxy et keepalived** sur un déploiement à un seul contrôleur, où ils ne répartissent rien entre plusieurs serveurs ? Cite deux raisons.
8. Les fichiers de `/etc/kolla/<service>/` sur un nœud et ceux de `etc/kolla/config/` dans ton dépôt : qui écrit quoi, dans quel ordre, et comment un fichier arrive-t-il jusque dans le conteneur ? Que se passe-t-il pour une modification faite à la main sur le nœud ?
9. *(QCM)* `passwords.yml` est perdu, le cloud tourne. Quelle affirmation est vraie ?
   - A. Aucune conséquence : `kolla-genpwd` en régénère un identique
   - B. Le prochain `reconfigure` avec un nouveau fichier changerait tous les mots de passe dans la configuration sans les changer dans les bases et RabbitMQ : le cloud tomberait
   - C. Kolla relit les mots de passe dans les conteneurs au prochain passage
   - D. Seul Horizon est concerné
10. Pourquoi les images Kolla sont-elles étiquetées par série et distribution (`2026.1-debian-trixie`) plutôt que par version exacte ? Quel risque cela crée-t-il pour la reproductibilité, et comment le maîtriser (indice : palier 3, E28) ?
11. Glance en stockage `file` sur `osctl01`, Nova sur disques locaux des calculs : cite trois fonctions d'un cloud que cette configuration empêche ou rend fragiles, et le service qui les rétablira au palier 2.
12. Pourquoi l'utilisateur `julien.petit` reçoit-il un 403 en voulant créer un groupe de sécurité dans `mediagenda-prod`, alors que la requête a bien été authentifiée ? Quel composant a pris la décision, et sur la base de quoi ?
13. Un collègue propose de donner le rôle `admin` sur le projet `admin` à l'équipe MédiAgenda « pour qu'ils soient autonomes ». Explique pourquoi c'est très différent de `admin` sur `mediagenda-dev`, puis pourquoi même ce dernier est à éviter.
14. Le VLAN 52 n'est branché que sur `osctl01`. Quelles conséquences sur la capacité et la disponibilité des IP flottantes ? Que faudrait-il pour s'en affranchir ?
15. *(QCM)* La MTU du réseau `reseau-plateforme` est 1442. Une instance envoie un paquet de 1442 octets vers une autre instance du même réseau sur l'autre calcul. Que se passe-t-il ?
    - A. Le paquet est fragmenté par `ovn-controller`
    - B. Il est encapsulé en Geneve (environ 1500 octets) et traverse le VLAN 51 sans fragmentation
    - C. Il est rejeté : la MTU du VLAN 51 est 9000
    - D. Il passe par `osctl01`, qui le route

**Critères de réussite**
- [ ] Tu as répondu par écrit aux 15 questions avant d'ouvrir le corrigé.
- [ ] Pour les questions 4 et 5, tu as vérifié au moins une affirmation sur ton lab (commande et résultat notés).
- [ ] Tu as noté ton score (2 points par question, sur 30) et les points à revoir.

<details><summary>Indice 1</summary>

Pour la question 1, relis les journaux de ta création d'`essai01` : `openstack server event show essai01 <ID-REQUETE>` et, sur `osctl01`, `/var/log/kolla/nova/` (le même identifiant de requête `req-…` apparaît dans plusieurs fichiers). M10-E44 fera ce voyage en détail.
</details>

<details><summary>Indice 2</summary>

Pour la question 5 : le plan de **contrôle** (API, ordonnancement, bases) et le plan de **données** (trafic des instances) ne passent pas par les mêmes machines. Demande-toi, pour chaque paquet d'une instance, s'il traverse `osctl01`.
</details>

**Pour aller plus loin** (facultatif) : lis la page « Architecture » du guide d'installation d'OpenStack et compare avec ton déploiement. [OpenStack : *Logical architecture*](https://docs.openstack.org/install-guide/get-started-logical-architecture.html).
