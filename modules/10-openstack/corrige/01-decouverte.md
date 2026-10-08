# Module 10 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`openstack/` pour `plateforme/openstack`, `ansible/` pour `plateforme/ansible`, `infra/` pour `plateforme/infra`, `tofu-modules/` pour `plateforme/tofu-modules`, `medisphere/` pour `plateforme/medisphere`, `adm01/` pour des fichiers personnels de `adm01`). Ne copie que ce que l'exercice ajoute ou modifie.

**Ce qui a été vérifié à la rédaction** :
- le module `vm-debian` v2.2.0 et l'état `envs/openstack` passent `tofu validate` et `tofu fmt -check` avec `bpg/proxmox` 0.116.0, `e-breuninger/netbox` 5.8.0 et `mmianl/powerdns` 2.5 (modules référencés en chemins locaux pour le test) ;
- le rôle `noeud_openstack` et les playbooks `identite.yml`, `catalogue.yml`, `reseau-externe.yml` passent `ansible-lint` (profil `production`) ; les paramètres des modules `openstack.cloud` ont été relus dans la collection 2.6.0 (documentation embarquée et code : `identity_group` exige un **identifiant** de domaine, `role_assignment` a `group_domain` et `project_domain`) ; le modèle netplan a été rendu et relu pour `osctl01` et un calcul ;
- les scripts (`inventaire.sh`, `verifier-chiffrement.sh`, `certificat-externe.sh`, `publier-image.sh`) et les vérifications passent `shellcheck -x` et `bash -n` ; la logique `jq` des vérifications E04 à E08 a été rejouée contre des réponses JSON de la CLI ;
- les variables et procédures de Kolla-Ansible relues dans la documentation 2026.1 (Quick Start, Multinode, Operating Kolla, Neutron/OVN, TLS, External Ceph) et les notes de version 22.x (ansible-core 2.19 à 2.20, groupes `kolla_toolbox` et `kolla_logs`).

**Points non testés en conditions réelles**, à vérifier sur ta version et à signaler s'ils diffèrent :
- un déploiement complet de Kolla-Ansible 22.2.0 sur Debian 13 (pas de lab OpenStack dans l'environnement de rédaction) : durées, messages d'erreur et sorties de commandes sont donnés à titre d'**exemple** ;
- la prise en compte de l'`ansible.cfg` du projet (identité Vault) par `kolla-ansible` lancé depuis `~/src/openstack` ; à défaut, ajoute `--vault-id critique@outils/vault-pass-client.sh` (ou exporte `ANSIBLE_VAULT_IDENTITY_LIST`) ;
- le déchiffrement par Kolla d'un `haproxy.pem` chiffré par Vault (il repose sur le module `copy`, qui déchiffre les sources Vault) : si ta version copie le certificat autrement, garde le fichier chiffré dans le dépôt et déchiffre-le dans un dossier temporaire au moment du `deploy` ;
- le nom initial de la carte sans adresse avant le rôle (`ens21` attendu sur une machine i440fx ; le rôle la renomme de toute façon par sa MAC) ;
- la sortie exacte de `openstack network agent list` et `security group show` en JSON selon la version de la CLI 10.x ;
- l'étiquette `--tags loadbalancer` pour ne reconfigurer qu'HAProxy après un renouvellement de certificat.

---

### M10-E01 — Test de positionnement : IaaS et OpenStack

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 40. En dessous de 20, lis attentivement l'introduction du module (concepts clés) et le contexte technique de E02 et E08 avant de commencer ; les questions 7 à 11 sont reprises en E08, 12 à 14 en E05, 15 à 18 en E03-E04.

**Réponses argumentées — Cloud et IaaS**

**1. NIST.** Les cinq caractéristiques : (a) **libre-service à la demande** (l'utilisateur obtient des ressources sans intervention humaine du fournisseur) ; (b) **accès réseau étendu** (API et interfaces standard) ; (c) **mutualisation des ressources** (un *pool* partagé entre locataires, emplacement abstrait) ; (d) **élasticité rapide** (ressources obtenues et rendues vite, capacité qui paraît illimitée) ; (e) **service mesuré** (consommation mesurée, contrôlée, rapportée). Le cluster Proxmox du module 09 a (b) et (c) ; (a) seulement en partie (droits par pool, mais pas de quotas par locataire, pas de réseaux privés créés par l'utilisateur, pas de catalogue) ; (d) est limité par l'absence de quotas et de libre-service réseau ; (e) manque (aucune mesure par locataire). C'est la différence entre « virtualisation » et « cloud ».

**2. Réponse B.** L'ordonnanceur (`nova-scheduler`) choisit l'hôte d'après les ressources disponibles (Placement) et des filtres (zones, agrégats, affinités). A est faux : l'utilisateur ne voit pas les hyperviseurs (seul un administrateur peut forcer un hôte) ; C décrit l'hébergement traditionnel, l'inverse d'un IaaS ; D n'existe pas (le choix est calculé, pas une course).

**3. Quota et capacité.** Le **quota** est une limite **administrative** par projet (ce qu'il a le droit de consommer) ; la **capacité** est ce que l'infrastructure peut **réellement** fournir. 18 vCPU demandés avec un quota de 20 : le quota accepte. Sans surréservation, l'ordonnanceur ne trouve pas 18 vCPU libres (16 physiques) : échec de placement (« No valid host was found »). Avec un facteur 4, la capacité *virtuelle* est de 64 vCPU : la demande passe, au prix d'une contention si toutes les instances calculent en même temps. Les quotas additionnés peuvent dépasser la capacité (c'est le pari de la mutualisation) : l'opérateur surveille la capacité, pas les quotas.

**Réponses argumentées — Virtualisation**

**4. VT-x et virtualisation imbriquée.** VT-x/AMD-V ajoutent au processeur un mode d'exécution pour les invités (VMX, SVM) et la traduction d'adresses à deux niveaux (EPT/NPT) : l'invité s'exécute directement sur le CPU, l'hyperviseur n'intervient qu'aux sorties de VM. **Imbriquée** : une VM (L1) lance elle-même des VMs (L2) accélérées. Côté hôte (L0), le module KVM doit autoriser l'imbrication (`/sys/module/kvm_intel/parameters/nested` à `Y`) ; côté VM L1, le CPU virtuel doit exposer l'extension (`vmx`) : type de CPU `host` (ou drapeau ajouté au modèle). Sinon `/dev/kvm` n'existe pas dans L1 : Nova en `virt_type=kvm` ne peut pas démarrer d'instance (`nova-compute` le signale), et le seul repli est l'émulation logicielle de QEMU (`qemu`, TCG), dix à cinquante fois plus lente.

**5. Réponse A.** `host` recopie le modèle et les extensions du CPU physique (`host-passthrough`) : meilleures performances, extensions de virtualisation visibles (indispensable en E02). B décrit les modèles génériques (`x86-64-v2-AES`, défaut de notre image dorée) ; C confond avec l'épinglage de CPU (*CPU pinning*) ; D est faux par le « rien d'autre » : `host` complique bien la migration à chaud vers un hôte différent, mais ce n'est pas sa définition.

**6. qcow2 et raw.** **qcow2** : format de QEMU, alloué à la demande (le fichier grandit avec les données), instantanés internes, fichier de base (*backing file*) pour la copie sur écriture, compression ; un peu de surcoût en E/S (métadonnées). **raw** : les octets du disque, rien d'autre ; le plus rapide, pas de fonctions. Ceph RBD fait **lui-même** le provisionnement fin, les instantanés et les clones copie-sur-écriture : une image Glance `raw` dans le pool `images` peut être **clonée** instantanément pour chaque disque d'instance. Une image qcow2 dans RBD n'est qu'un blob opaque : Nova doit la télécharger et la convertir pour chaque instance (lent, copie complète). D'où la conversion en E10.

**Réponses argumentées — Réseau virtuel**

**7. Encapsulation.** Un VLAN par réseau de client : 4094 identifiants au plus, chaque réseau à déclarer sur tous les commutateurs, création qui dépend de l'équipe réseau. L'encapsulation (VXLAN, Geneve) transporte les trames des clients dans des paquets UDP entre hyperviseurs : (a) 16 millions d'identifiants, (b) réseaux créés par logiciel sans toucher au réseau physique, (c) plages d'adresses qui peuvent se chevaucher entre projets. Coût : octets d'en-tête (MTU), un peu de CPU, un dépannage plus difficile (il faut « regarder dans le tunnel »).

**8. MTU de Geneve.** Encapsulation IPv4 : IP externe 20 + UDP 8 + Geneve 8 (plus ses options éventuelles) + Ethernet interne 14 = **50 octets** au minimum (l'Ethernet externe ne compte pas dans la MTU). Pour transporter des trames de 1500 octets de charge : MTU physique ≥ 1550, davantage avec des options Geneve (OVN en utilise : Neutron réserve 38 octets d'en-tête Geneve, soit 58 avec l'IP). Inversement, sur un réseau physique à 1500, on annonce aux VMs 1500 − 58 = **1442** (c'est ce que tu verras en E07-E08). Une MTU physique de 9000 sur le VLAN des tunnels supprime le problème.

**9. IP flottante.** Une adresse du réseau **externe** associée à une instance par une traduction **1:1** sur le routeur virtuel. `ping` de `adm01` vers l'IP flottante : `adm01` → bordure → réseau externe → routeur du projet : **DNAT** (destination IP flottante → adresse privée) → réseau du projet → instance. Réponse : instance → routeur : **SNAT** (source adresse privée → IP flottante) → réseau externe → bordure → `adm01`. L'instance ne connaît que son adresse privée.

**10. Réponse B.** Un groupe de sécurité est un pare-feu **à états** (le retour d'une connexion autorisée passe sans règle) appliqué **à chaque port** d'instance, quelle que soit la topologie. A est faux (sans état, et sur un routeur) ; C est un mécanisme d'isolement de niveau 2 ; D est une traduction d'adresses, pas un filtrage.

**11. Fournisseur et projet.** Un réseau **fournisseur** est créé par l'**administrateur** et correspond à un réseau physique (flat ou VLAN, via une correspondance réseau physique → pont, `physnet1:br-ex`) : les paquets sortent tels quels sur le réseau physique. Un réseau **de projet** (*self-service*) est créé par les **utilisateurs**, encapsulé (Geneve), invisible du réseau physique ; il sort par un routeur virtuel. Les IP flottantes se prennent sur un réseau fournisseur marqué **externe**.

**Réponses argumentées — Identité**

**12. Authentification et autorisation.** **Authentification** : prouver qui on est (mot de passe, certificat, application credential). **Autorisation** : décider si cette identité a le droit de faire cette action ici. Un jeton (Keystone : jeton **Fernet**, chiffré, non stocké) porte l'utilisateur, la **portée** (projet, domaine ou système), les rôles, la date d'expiration (une heure par défaut dans Keystone). Avantages : le mot de passe n'est envoyé qu'une fois (pas à chaque appel ni à chaque service), le jeton expire vite, sa portée limite les dégâts s'il fuit, et les services n'ont pas à connaître les mots de passe.

**13. Modèle minimal.** Utilisateurs nominatifs (`julien.petit`…) dans un **groupe** `equipe-mediagenda` ; deux **projets** `mediagenda-dev` et `mediagenda-prod` ; attributions au **groupe** : `member` sur `mediagenda-dev`, `reader` sur `mediagenda-prod`. Un départ ou une arrivée = une appartenance au groupe, pas N attributions. C'est exactement E05.

**14. Robots.** Le mot de passe d'un humain donne **tous** ses droits, sur tous ses projets, sans date de fin ; il change quand l'humain le change (le pipeline casse), et ses actions sont attribuées à l'humain (traçabilité perdue). Il faut des identités de service ou, mieux, des **secrets délégués** : limités à un projet, à certains rôles, avec une expiration, révocables sans toucher au compte de la personne. Keystone : les *application credentials* (E05), les *trusts*.

**Réponses argumentées — Conteneurs et automatisation**

**15. Conteneurs pour l'infrastructure.** Pour : chaque service a ses dépendances figées dans son image (pas de conflit de bibliothèques Python entre Nova et Neutron sur un même hôte), mise à jour par remplacement d'image (et retour arrière par l'image précédente), même artefact testé en CI et déployé. Contre : une couche de plus à comprendre (images, volumes, configuration copiée au démarrage, réseau `host`), outillage de diagnostic à apprendre (`docker exec`, journaux), dépendance à un registre d'images et à la chaîne qui les construit (sécurité de la chaîne d'approvisionnement, module 13).

**16. Réponse B.** `--network host` : le conteneur utilise directement les interfaces, ports et routes de l'hôte (pas d'espace de noms réseau). C'est le choix de Kolla pour presque tous ses services (performances, simplicité des ports). A décrit `--network none` ; C décrit un pont ; D n'existe pas.

**17. Deux ansible-core.** Un environnement Python isolé par projet (projet `uv` avec son `uv.lock`) : chacun sa version d'ansible-core, de ses bibliothèques, de ses greffons. Les **collections** doivent l'être aussi (`collections_path` propre à chaque projet) : partagées dans `~/.ansible/collections`, la dernière installation écrase l'autre, et un projet peut se retrouver avec une collection incompatible avec sa version d'ansible-core (erreurs au chargement, ou pire, comportements différents). C'est E03.

**18. Fichier de mots de passe versionné.** On le chiffre au repos (Ansible Vault, SOPS) et on versionne la forme chiffrée ; la clé de déchiffrement vit ailleurs (gestionnaire de secrets, fichier 600 sur le poste de déploiement, variable protégée). Sans le versionner : un `git clone` ne suffit plus à reconstruire, et la perte du fichier est catastrophique (E09, question 9).

**Réponses argumentées — OpenStack**

**19. Services d'une création d'instance.** **Keystone** authentifie et fournit le catalogue ; **Nova** (API, conducteur, ordonnanceur, `nova-compute`) orchestre ; **Placement** dit quels hôtes ont les ressources et les réserve ; **Glance** fournit l'image ; **Neutron** crée le port (adresse, groupe de sécurité) et le branche ; **Cinder** fournit le volume s'il y en a un ; sur le calcul, **libvirt/QEMU** lance la VM. Dessous : MariaDB (état), RabbitMQ (messages internes de Nova), et ici OVN pour le réseau.

**20. Réponse B.** Un gabarit décrit les ressources (vCPU, mémoire, disque racine, éphémère, swap) et des propriétés (*extra specs*) utilisées au placement. A vient de l'image ; C de la demande de création ; D du jeton de l'utilisateur.

---

### M10-E02 — Préparer les nœuds OpenStack

**Solution**

*A. Constater sur `pve01` (lecture seule).*

```
root@pve01:~# cat /sys/module/kvm_intel/parameters/nested
Y
root@pve01:~# ip -d link show vmbr1 | grep -o 'mtu [0-9]*'
mtu 9000
root@pve01:~# pvesh get /cluster/sdn/zones/lab --output-format json | jq '{zone, type, mtu}'
root@pve01:~# ip link show | grep -E 'vostun|vstopub' | grep -o 'mtu [0-9]*' | sort -u
mtu 9000
```

`nova_compute_virt_type` vaut `kvm` par défaut dans Kolla. Sans extensions de virtualisation dans `oscmp01`, `nova-compute` ne trouve pas `/dev/kvm` : les instances partent en `ERROR` (le service peut même refuser de démarrer selon la version). Le repli `qemu` fonctionne, mais en émulation pure : inutilisable au-delà d'une démonstration.

*B. Le code des VMs.*

1. **Le module.** Le module `vm-debian` v2.1 ne porte qu'une carte, un type de CPU figé (`x86-64-v2-AES`) et aucune MAC. L'extension v2.2.0 (fichiers complets : [`tofu-modules/vm-debian/`](fichiers/M10-E02/tofu-modules/vm-debian/)) ajoute `type_cpu`, `mac_adresse`, `mtu`, `interface_principale` et `cartes_supplementaires`. Ajout **rétrocompatible** (toutes les nouvelles variables ont un défaut qui reproduit v2.1) : version mineure, commit `feat(vm-debian): cartes réseau supplémentaires, MAC, MTU et type de CPU`, étiquette `v2.2.0` posée par semantic-release. Deux validations protègent le `plan` : une carte adressée a une adresse **et** un préfixe ; les cartes sans adresse viennent **après** les cartes adressées.
   > Si ton M07 ou ton M08 a déjà étendu le module (gw02, nœuds Ceph à deux cartes), réutilise cette version et ajoute seulement ce qui manque ; garde le principe d'un ajout rétrocompatible.
2. **L'état `envs/openstack`** ([`infra/envs/openstack/`](fichiers/M10-E02/infra/envs/openstack/)) : `noeuds.tf` décrit les trois nœuds dans une `locals` et appelle le module avec `for_each` ; la règle des MAC et des adresses y est écrite une fois. `dns.tf` publie A et PTR des nœuds (module `enregistrement-dns`), les A des deux VIP sans PTR, et **réserve** les VIP dans NetBox (rôle `vip`) pour qu'aucune allocation automatique ne les donne un jour à une VM.
   ```
   admin@adm01:~/src/infra$ git switch -c feat/openstack-noeuds
   admin@adm01:~/src/infra$ tofu -chdir=envs/openstack init
   admin@adm01:~/src/infra$ tofu -chdir=envs/openstack plan
   …
   Plan: 27 to add, 0 to change, 0 to destroy.
   ```
   (Le nombre exact dépend de ta version des modules : 3 VMs, leurs objets NetBox, 5 enregistrements A, 3 PTR, 2 adresses réservées.) Avant le `plan`, crée les étiquettes `env-m10` et `role-openstack` dans NetBox : le module les y applique et échoue si elles n'existent pas. MR, relecture du plan, `apply` par le pipeline. Puis, en root :
   ```
   root@pve01:~# qm set 2101 --startup order=20 && qm set 2102 --startup order=21 && qm set 2103 --startup order=21
   ```
3. **Vérifier.**
   ```
   root@pve01:~# qm config 2101 | grep -E '^(name|cores|memory|cpu|tags|net[0-9])'
   cores: 4
   cpu: x86-64-v2-AES
   memory: 16384
   name: osctl01
   net0: virtio=BC:24:11:50:00:51,bridge=vosapi,firewall=0
   net1: virtio=BC:24:11:51:00:51,bridge=vostun,firewall=0,mtu=9000
   net2: virtio=BC:24:11:30:00:51,bridge=vstopub,firewall=0,mtu=9000
   net3: virtio=BC:24:11:52:00:51,bridge=vosext,firewall=0,mtu=1500
   tags: env-m10;role-openstack
   root@pve01:~# qm config 2102 | grep ^cpu
   cpu: host
   admin@adm01:~$ dig +short osctl01.par1.medisphere.internal; dig +short -x 10.10.50.52; dig +short openstack.par1.medisphere.internal
   10.10.50.51
   oscmp01.par1.medisphere.internal.
   10.10.50.201
   ```
   Dans NetBox, chaque VM a ses interfaces `ens18` (adresse primaire), `ens19`, `ens20` (adresses) et, pour `osctl01`, `ens21` sans adresse.

*C. La préparation par Ansible.*

4. Inventaire et confiance :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-inventory --graph role_openstack
   @role_openstack:
     |--oscmp01
     |--oscmp02
     |--osctl01
   admin@adm01:~/src/ansible$ for h in osctl01 oscmp01 oscmp02; do ssh-keyscan -t ed25519 "$h.par1.medisphere.internal"; done >> known_hosts
   ```
   (Si les clés d'hôte des VMs sont certifiées par la CA SSH de M06-E19, la ligne `@cert-authority` suffit et cette étape disparaît.) Ajoute aussi les alias `osctl01`, `oscmp01`, `oscmp02` à `~/.ssh/config` de `adm01` (les vérifications et le palier 4 s'en servent).
5. Le rôle `noeud_openstack` ([`ansible/roles/noeud_openstack/`](fichiers/M10-E02/ansible/roles/noeud_openstack/)) et le playbook [`playbooks/openstack-noeuds.yml`](fichiers/M10-E02/ansible/playbooks/openstack-noeuds.yml) : un premier jeu applique les rôles communs (`base`, `ssh_durci`, `medisphere.socle.ca_lab`), un second applique `noeud_openstack` avec `serial: 1` (un nœud à la fois, puisqu'il peut redémarrer). Le modèle `60-openstack.yaml.j2` produit, pour `osctl01` :
   ```yaml
   network:
     version: 2
     renderer: networkd
     ethernets:
       ens18:
         match:
           macaddress: "bc:24:11:50:00:51"
         set-name: ens18
         mtu: 1500
         dhcp4: false
         dhcp6: false
         accept-ra: false
         addresses:
           - "10.10.50.51/24"
         routes:
           - to: default
             via: 10.10.50.1
         nameservers:
           addresses: ["10.10.20.10", "10.10.20.16"]
           search: [par1.medisphere.internal]
       ens19: { … mtu: 9000, addresses: ["10.10.51.51/24"] }
       ens20: { … mtu: 9000, addresses: ["10.10.30.61/24"] }
       ens21:
         match:
           macaddress: "bc:24:11:52:00:51"
         set-name: ens21
         mtu: 1500
         dhcp4: false
         dhcp6: false
         accept-ra: false
         link-local: []
   ```
6. Application par le pipeline (ou, la première fois, depuis `adm01` après l'instantané) :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/openstack-noeuds.yml --diff
   …
   RUNNING HANDLER [noeud_openstack : Redémarrer le nœud] ****
   changed: [osctl01]
   …
   PLAY RECAP ****
   oscmp01 : ok=… changed=4 … failed=0
   ```
   Un second passage : `changed=0`.
7. Les preuves, depuis `adm01` :
   ```
   admin@adm01:~$ ssh osctl01 ip -br link
   lo      UNKNOWN 00:00:00:00:00:00 <LOOPBACK,UP,LOWER_UP>
   ens18   UP      bc:24:11:50:00:51 <BROADCAST,MULTICAST,UP,LOWER_UP>
   ens19   UP      bc:24:11:51:00:51 <BROADCAST,MULTICAST,UP,LOWER_UP>
   ens20   UP      bc:24:11:30:00:51 <BROADCAST,MULTICAST,UP,LOWER_UP>
   ens21   UP      bc:24:11:52:00:51 <BROADCAST,MULTICAST,UP,LOWER_UP>
   admin@adm01:~$ ssh osctl01 'ip -o addr show dev ens21 | wc -l; ip -o link show ens19 | grep -o "mtu [0-9]*"'
   0
   mtu 9000
   admin@adm01:~$ ssh osctl01 ping -c 2 -M do -s 8972 -I ens19 10.10.51.52
   8980 bytes from 10.10.51.52: icmp_seq=1 ttl=64 time=0.41 ms
   admin@adm01:~$ ssh oscmp02 ping -c 2 -M do -s 8972 -I ens20 10.10.30.51
   8980 bytes from 10.10.30.51: icmp_seq=1 ttl=64 time=0.38 ms
   admin@adm01:~$ ssh oscmp01 'ls -l /dev/kvm; timedatectl show -p NTPSynchronized --value'
   crw-rw---- 1 root kvm 10, 232 … /dev/kvm
   yes
   ```
8. Documentation : [`docs/cloud/inventaire-openstack.md`](fichiers/M10-E02/medisphere/docs/cloud/inventaire-openstack.md). Matrice des flux : rien de nouveau, parce que SSH vient de MGMT (qui joint tout le lab), que DNS, NTP et la sortie vers Internet existent pour tous les VLAN, que le VLAN 51 n'est pas routé et que le VLAN 30 relie directement les nœuds à Ceph.

**Explications**

- **Pourquoi renommer par MAC.** Trois sources de noms se disputent les cartes : cloud-init nomme `eth0`… les cartes qu'il configure (configuration réseau générée par Proxmox, M03), udev donne un nom « prévisible » (`ens18`…`ens21` d'après l'emplacement PCI) aux autres. Kolla exige un nom par rôle (`network_interface`, `tunnel_interface`…), identique sur tous les nœuds du même type et **stable** d'une reconstruction à l'autre. La seule propriété qui ne bouge pas est celle que **nous** fixons : la MAC, écrite par OpenTofu. netplan génère une règle `.link` (udev) qui renomme la carte au démarrage, et une configuration `systemd-networkd`.
- **Pourquoi désactiver le réseau de cloud-init.** Sinon deux fichiers décrivent la même carte sous deux noms (`eth0` par cloud-init, `ens18` par nous) : le résultat dépend de l'ordre de lecture. Avec `network: {config: disabled}`, cloud-init ne régénère plus `50-cloud-init.yaml` ; le réseau appartient au rôle.
- **Pourquoi les cartes sans adresse en dernier.** Proxmox associe `ipconfigN` à `netN` par leur numéro, et le fournisseur `bpg/proxmox` écrit les blocs `ip_config` dans l'ordre où on les déclare. Le module produit un bloc par carte **adressée** : une carte sans adresse au milieu décalerait les suivantes (l'adresse de `ens20` atterrirait sur `ens21`). La validation le refuse au `plan`, pas au premier démarrage.
- **Pourquoi la MTU à deux endroits.** `mtu=9000` sur la carte Proxmox annonce la MTU au pilote virtio de l'invité (et ne peut pas dépasser celle du pont) ; `mtu: 9000` dans netplan fixe celle que l'invité **utilise**. Le `ping -M do -s 8972` (8972 + 8 d'ICMP + 20 d'IP = 9000, fragmentation interdite) est la seule preuve de bout en bout : il traverse la carte de l'émetteur, le pont de `pve01` et la carte du destinataire.
- **Pourquoi `ens21` sans aucune adresse.** Kolla branche cette carte dans le pont Open vSwitch `br-ex` : elle devient un port de commutateur. Une adresse IPv4 ou même une adresse IPv6 de lien local sur elle ferait répondre le **nœud** sur le VLAN 52, à côté des routeurs virtuels ; l'autoconfiguration IPv6 (`accept-ra`) pourrait lui en donner une sans qu'on le demande.
- **Pourquoi `firewall=0` sur les cartes.** Le pare-feu de Proxmox, quand il est activé sur une carte, filtre par défaut les MAC source qui ne sont pas celle de la carte (`macfilter`). Sur `ens21` passent les MAC des ports de routeurs d'OVN (`fa:16:3e:…`) : elles seraient jetées.
- **Pourquoi l'heure.** RabbitMQ, MariaDB (Galera), Keystone (validité des jetons) et les certificats supportent mal les horloges qui dérivent ; le palier 4 (E39, E40) en fait des pannes.

**Alternatives**

- **Fichiers `.link` de systemd** écrits directement (ou `udev` rules) pour nommer les cartes, sans netplan : même résultat, plus bas niveau. netplan est ce que l'image dorée utilise déjà.
- **Configuration réseau par cloud-init** : un *snippet* `network-config` (v2) passé par `cicustom` (M05-E19) avec `match`/`set-name` ; le réseau est alors fixé dès le premier démarrage, sans redémarrage. Inconvénient : le changer recrée la VM (le module le documente) ; ici, Ansible peut le corriger sur place.
- **Garder les noms `eth0`-`eth3`** de cloud-init et l'interface sans adresse sous son nom prévisible : fonctionne tant que personne ne change l'ordre des cartes ni l'image ; c'est le pari qu'on refuse.
- **Un module OpenTofu dédié** (`vm-openstack`) plutôt qu'une extension de `vm-debian` : plus simple à lire, mais deux modules à maintenir pour 90 % de code commun.

**Pièges classiques**

- MTU 9000 sur la carte Proxmox alors que le VNet ou `vmbr1` est resté à 1500 : la VM démarre, `ip link` affiche 9000, mais le `ping -M do -s 8972` échoue (*Message too long* côté émetteur, ou rien). Vérifie M07-E15 d'abord.
- Un octet de MAC « décimal » qui n'est pas de l'hexadécimal valide : ici tout tombe juste (30, 50-53), mais un suffixe 9A, 100… casserait la règle. Elle est documentée : une évolution du plan d'adressage doit la revoir.
- Appliquer le rôle **sans** `serial: 1` : les trois nœuds redémarrent ensemble ; sans conséquence avant Kolla, désastreux après (tout le plan de contrôle et les deux calculs).
- Oublier les étiquettes NetBox `env-m10` et `role-openstack` : le module `vm-debian` échoue au moment d'enregistrer la VM dans NetBox.
- Fichier netplan en 644 : netplan avertit (fichier lisible par tous) ; en 600, il est muet. Le rôle écrit en 600.
- Croire qu'un `netplan apply` à distance est sans danger : renommer la carte qui porte la session SSH coupe Ansible au milieu d'une tâche. Le redémarrage contrôlé est plus sûr, et l'accès de secours (console série) est vérifié avant.
- Laisser DHCP actif sur `ens21` : rien ne répond sur le VLAN 52, mais le client DHCP retarde le démarrage et peut récupérer un jour une adresse d'un équipement de test.

**En production chez MédiSphère**

Des serveurs physiques, pas des VMs : deux cartes de 25 Gbit/s agrégées en LACP (M07), des VLAN étiquetés sur l'agrégat, les noms d'interface fixés de la même façon (par MAC ou par chemin PCI), l'installation par PXE et la description dans NetBox (M11). Les nœuds de calcul n'ont pas de « KVM imbriqué » mais le BIOS doit avoir VT-x/VT-d activés, ce que l'inventaire matériel vérifie. Le réseau des tunnels et celui du stockage restent séparés du réseau de gestion ; la MTU 9000 est testée à chaque mise en service et après chaque changement réseau (une sonde `ping -M do` dans la supervision, M21).

---

### M10-E03 — Préparer Kolla-Ansible

**Solution**

1. **Lecture.** Le « Quick Start » de 2026.1 installe Kolla-Ansible dans un environnement virtuel par `pip install git+https://opendev.org/openstack/kolla-ansible@<branche>`, copie `globals.yml` et `passwords.yml` dans `/etc/kolla`, lance `kolla-ansible install-deps`, `kolla-genpwd`, puis `bootstrap-servers`, `prechecks`, `deploy`, `post-deploy`. On fait **autrement** : version **figée** depuis PyPI dans un projet `uv` (reproductible, `uv.lock`) ; configuration dans le dépôt (`--configdir etc/kolla`) plutôt que dans `/etc/kolla` de `adm01` ; `passwords.yml` chiffré. Limite d'ansible-core : notes de version 2026.1, « Ansible 12 au minimum (ansible-core 2.19), 13 au maximum (ansible-core 2.20) ».
2. **Le projet.**
   ```
   admin@adm01:~/src$ git clone git@git01.par1.medisphere.internal:plateforme/openstack.git && cd openstack
   admin@adm01:~/src/openstack$ uv init --bare --python 3.13
   admin@adm01:~/src/openstack$ uv add 'kolla-ansible==22.2.0' 'ansible-core>=2.20,<2.21' 'openstacksdk>=4.0'
   admin@adm01:~/src/openstack$ uv run ansible --version | head -n 1
   ansible [core 2.20.x]
   admin@adm01:~/src/openstack$ (cd ~/src/ansible && uv run ansible --version | head -n 1)
   ansible [core 2.21.x]
   ```
   Fichier complet : [`pyproject.toml`](fichiers/M10-E03/openstack/pyproject.toml) (`[tool.uv] package = false`). Avec un seul environnement, il faudrait choisir : rétrograder `plateforme/ansible` (et perdre ce qui en dépend) ou casser Kolla. Avec des collections partagées, `kolla-ansible install-deps` installerait ses versions de `community.general`, `ansible.posix`… par-dessus celles de `plateforme/ansible` (ou l'inverse), et l'un des deux projets se retrouverait avec une collection qu'il n'a jamais testée.
3. **`ansible.cfg`** ([fichier](fichiers/M10-E03/openstack/ansible.cfg)) : `collections_path = ./collections`, `vault_identity_list = critique@outils/vault-pass-client.sh` (le script de M04-E30, copié dans `outils/`), `forks = 20`, `pipelining = True`.
   ```
   admin@adm01:~/src/openstack$ uv run kolla-ansible install-deps
   admin@adm01:~/src/openstack$ uv run ansible-galaxy collection install -r requirements.yml
   admin@adm01:~/src/openstack$ ls collections/ansible_collections/
   ansible  community  containers  openstack
   admin@adm01:~/src/openstack$ ls collections/ansible_collections/openstack/
   cloud  kolla
   admin@adm01:~/src/openstack$ ls ~/.ansible/collections/ansible_collections/openstack 2>&1
   ls: cannot access '…/openstack': No such file or directory
   ```
   (La liste exacte des collections installées par Kolla dépend de sa version.)
4. **Exemples de la version installée.**
   ```
   admin@adm01:~/src/openstack$ ls .venv/share/kolla-ansible/etc_examples/kolla/ .venv/share/kolla-ansible/ansible/inventory/
   globals.yml  passwords.yml
   all-in-one  multinode
   ```
   L'inventaire est le fichier le plus dépendant de la version : en 2026.1, le groupe `common` devient `kolla_toolbox`, `kolla_logs` apparaît, Cinder reçoit des groupes LVM. Un inventaire recopié d'un tutoriel de 2024 déploie sans erreur… et oublie des services. D'où [`outils/inventaire.sh`](fichiers/M10-E03/openstack/outils/inventaire.sh) : il assemble **nos** groupes principaux ([`inventaire/groupes-principaux.ini`](fichiers/M10-E03/openstack/inventaire/groupes-principaux.ini)) et les groupes de services de l'exemple **de la version installée** ; la CI vérifie que `inventaire/multinode` est à jour (`--verifier`).
5. **Inventaire et `globals.yml`.** [`globals.yml`](fichiers/M10-E03/openstack/etc/kolla/globals.yml) ne garde que les écarts au défaut, chacun commenté ; [`inventaire/host_vars/osctl01.yml`](fichiers/M10-E03/openstack/inventaire/host_vars/osctl01.yml) porte `neutron_external_interface: "ens21"` ; [`inventaire/group_vars/noeuds_openstack.yml`](fichiers/M10-E03/openstack/inventaire/group_vars/noeuds_openstack.yml) les paramètres de connexion (`ansible_user: admin`, `ansible_become: true`). La règle de précédence : Kolla passe `globals.yml` en `-e @globals.yml`, c'est-à-dire en **variables supplémentaires**, la priorité la plus haute d'Ansible ; une valeur qui y figure s'impose à **tous** les hôtes, aucune variable d'hôte ne peut la corriger. Une valeur propre à un hôte va donc dans l'inventaire, et elle **ne doit pas** figurer aussi dans `globals.yml`.
6. **Mots de passe.**
   ```
   admin@adm01:~/src/openstack$ d=$(mktemp -d) && chmod 700 "$d"
   admin@adm01:~/src/openstack$ cp .venv/share/kolla-ansible/etc_examples/kolla/passwords.yml "$d/"
   admin@adm01:~/src/openstack$ uv run kolla-genpwd --passwords "$d/passwords.yml"
   admin@adm01:~/src/openstack$ uv run ansible-vault encrypt --encrypt-vault-id critique "$d/passwords.yml"
   Encryption successful
   admin@adm01:~/src/openstack$ mv "$d/passwords.yml" etc/kolla/passwords.yml && rmdir "$d"
   admin@adm01:~/src/openstack$ head -n 1 etc/kolla/passwords.yml
   $ANSIBLE_VAULT;1.2;AES256;critique
   ```
   Preuve que Kolla le lit : une action qui charge toute la configuration mais ne modifie rien. `gather-facts` (collecte de faits sur les nœuds, en lecture) convient : Kolla passe `passwords.yml` à chaque `ansible-playbook`, et un échec de déchiffrement arrête tout dès le chargement.
   ```
   admin@adm01:~/src/openstack$ uv run kolla-ansible gather-facts -i inventaire/multinode --configdir etc/kolla
   …
   PLAY RECAP ****
   localhost : ok=… failed=0
   osctl01   : ok=… failed=0
   ```
   Sans l'identité (essaie en renommant temporairement `~/.config/workbook/ansible-vault-critique.pass`), le même appel échoue avec « Attempting to decrypt but no vault secrets found ». Pour lire une valeur sans fichier en clair : `uv run ansible-vault view etc/kolla/passwords.yml | grep '^keystone_admin_password:'`. Registre des secrets : « `plateforme/openstack`, `etc/kolla/passwords.yml` : mots de passe de tous les services OpenStack (bases, RabbitMQ, comptes de service, administrateur Keystone, clés Fernet initiales…), Ansible Vault `critique` ; déchiffré par : équipe Plateforme (poste `adm01`) ; rotation : M10-E27 ».
7. **Le dépôt.** [`.gitignore`](fichiers/M10-E03/openstack/.gitignore), [`README.md`](fichiers/M10-E03/openstack/README.md), [`.yamllint`](fichiers/M10-E03/openstack/.yamllint), [`.gitlab-ci.yml`](fichiers/M10-E03/openstack/.gitlab-ci.yml) et [`outils/verifier-chiffrement.sh`](fichiers/M10-E03/openstack/outils/verifier-chiffrement.sh). La MR d'essai :
   ```
   admin@adm01:~/src/openstack$ git switch -c essai/mot-de-passe-en-clair
   admin@adm01:~/src/openstack$ printf 'keystone_admin_password: essai\n' > etc/kolla/passwords.yml
   admin@adm01:~/src/openstack$ git commit -am "test: passwords.yml en clair (MR d'essai, à refermer)" && git push -u origin HEAD
   ```
   Le job `secrets-chiffres` échoue (« EN CLAIR : etc/kolla/passwords.yml ») — et Gitleaks (gabarit `qualite.yml`) aussi, selon ses règles. Referme la MR **sans fusion**, supprime la branche distante, puis `git switch main && git branch -D essai/mot-de-passe-en-clair`. Le faux mot de passe « essai » n'a jamais été un vrai secret : c'est la seule raison pour laquelle ce test est acceptable. ADR-0101 : copiée de [`ressources/M10-E03/`](../ressources/M10-E03/ADR-0101-kolla-ansible.md) dans `docs/cloud/adr/` de `plateforme/medisphere`, par MR.

**Explications**

- **Ce que contient une configuration Kolla.** `globals.yml` (choix communs), `passwords.yml` (tous les secrets, générés), l'inventaire (qui fait quoi, et les variables par hôte), `config/` (surcharges `.conf` fusionnées avec la configuration générée, par service, conteneur ou hôte), `certificates/` (TLS), et depuis peu `globals.d/` (fichiers lus après `globals.yml`, pratiques pour regrouper les réglages par sujet). Tout le reste (configuration de chaque service sur chaque nœud) est **produit** à chaque `deploy`/`reconfigure`.
- **`--configdir`.** Il désigne le dossier qui contient `globals.yml`, `passwords.yml`, `config/` et `certificates/`. Sur les **nœuds**, la configuration générée va toujours dans `/etc/kolla/<service>/` : ce sont deux choses différentes, malgré le nom.
- **Pourquoi `kolla-genpwd` dans un dossier temporaire.** Un fichier créé en clair dans le dossier du dépôt peut être ajouté par erreur (`git add .`) ; une fois dans un commit, même effacé ensuite, il est dans l'historique (et chez quiconque a récupéré la branche).

**Alternatives**

- **Installer depuis la branche Git** `stable/2026.1` (méthode du Quick Start) : on suit les correctifs en continu, sans attendre une publication ; moins reproductible (un `uv lock` fige le commit, mais il faut le faire exprès).
- **`/etc/kolla` sur `adm01`** comme dans la documentation, avec un lien vers le dépôt : marche, mais les droits (`root`), l'emplacement hors du dépôt et le risque d'éditer « à côté » du code plaident pour `--configdir`.
- **Kolla et HashiCorp Vault** (`kolla-writepwd`, `kolla-readpwd`) : les mots de passe vivent dans Vault, Kolla les lit au déploiement ; c'est l'étape suivante (module 25).
- **SOPS + age** pour chiffrer `passwords.yml` (module 25) : chiffrement par valeur, diffs lisibles ; Ansible Vault reste plus simple ici puisque l'outillage est Ansible.

**Pièges classiques**

- `uv add kolla-ansible` sans version : la dernière publiée sur PyPI, qui sera un jour une autre série (2026.2), avec un autre ansible-core.
- Lancer `kolla-ansible` depuis un autre dossier que la racine du dépôt : l'`ansible.cfg` du projet n'est pas lu (identité Vault, collections) — erreurs de déchiffrement ou de collections introuvables.
- Recopier un inventaire d'une autre version (groupes renommés : services absents sans erreur visible au déploiement).
- Mettre `neutron_external_interface` dans `globals.yml` « parce que c'est plus simple » : les `prechecks` échouent sur les calculs (l'interface `ens21` n'y existe pas) ou, pire, Kolla l'ajoute à `br-ex` partout où elle existe.
- `ansible-vault encrypt` sans `--encrypt-vault-id critique` : le fichier est chiffré sous l'identité par défaut, et `vault_id_match = True` refuse ensuite de le déchiffrer avec la bonne clé.
- Supprimer `etc/kolla/passwords.yml` ou le régénérer par erreur sur un cloud qui tourne : voir E09, question 9.

**En production chez MédiSphère**

Le dépôt `plateforme/openstack` est protégé comme `plateforme/ansible` (deux approbations sur les MR qui touchent `globals.yml` ou l'inventaire). La version de Kolla et les empreintes des images déployées sont notées dans chaque compte rendu de changement (E28). Les mots de passe migrent vers Vault/OpenBao (module 25) et sont tournés selon une politique (E27). Un registre d'images interne (Harbor, module 13) évite de dépendre de `quay.io` le jour d'un déploiement d'urgence.

---

### M10-E04 — Déployer OpenStack

**Solution**

*A. Le certificat externe.*

1. **Flux** : extrait [`pare_feu.yml.extrait`](fichiers/M10-E04/ansible/inventories/lab/host_vars/gw01/pare_feu.yml.extrait) (deux règles de transit, `ref: M10-E04`), MR sur `plateforme/ansible`, pipeline. Client `step` sur `osctl01` : [`playbooks/outils-pki.yml`](fichiers/M10-E04/ansible/playbooks/outils-pki.yml) étendu au groupe `role_openstack`.
   ```
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/outils-pki.yml --limit osctl01
   admin@adm01:~$ ssh osctl01 step version
   Smallstep CLI/0.31.x (linux/amd64)
   ```
2. **Émission** : [`outils/certificat-externe.sh`](fichiers/M10-E04/openstack/outils/certificat-externe.sh) fait tout, dans l'ordre, et refuse si la VIP répond déjà :
   ```
   admin@adm01:~/src/openstack$ outils/certificat-externe.sh emettre
   1/6 La VIP 10.10.50.201 doit être LIBRE sur le VLAN 50 (détection d'adresse en double depuis osctl01)…
   2/6 osctl01 porte 10.10.50.201 le temps du défi (retirée en sortie, même en cas d'erreur).
   3/6 Défi ACME HTTP-01 sur osctl01:80 (provisioner acme de ca01)…
   ✔ Provisioner: acme (ACME)
   Using Standalone Mode HTTP challenge to validate openstack.par1.medisphere.internal .. done!
   Waiting for Order to be 'ready' for finalization .. done!
   Finalizing Order .. done!
   ✔ Certificate: /tmp/tmp.XXXX/crt
   ✔ Private Key: /tmp/tmp.XXXX/key
   4/6 Contrôle : chaîne complète (feuille + intermédiaire) ?
   5/6 Chiffrement de la chaîne et de la clé dans etc/kolla/certificates/haproxy.pem (Vault « critique »)…
   Encryption successful
   6/6 Nettoyage de osctl01 (VIP retirée, dossier supprimé).
   subject=CN=openstack.par1.medisphere.internal
   issuer=O=MédiSphère, CN=MédiSphère Intermediate CA
   notAfter=…
   X509v3 Subject Alternative Name:
       DNS:openstack.par1.medisphere.internal
   ```
   La clé ne touche jamais le disque de `adm01` : `ssh osctl01 sudo cat …` alimente directement `ansible-vault encrypt … -` par un tube. Le script copie aussi la racine publique dans `etc/kolla/certificates/ca/medisphere-root-ca.crt`. Registre des secrets : « clé de la VIP externe d'OpenStack, dans `etc/kolla/certificates/haproxy.pem` (Vault `critique`), 30 jours, renouvelée par `certificat-externe.sh renouveler` puis par Kolla (M10-E27) ».
3. **`globals.yml`** : [version E04](fichiers/M10-E04/openstack/etc/kolla/globals.yml), `kolla_enable_tls_external: "yes"` et `kolla_external_fqdn_cert` (valeur par défaut, écrite pour la relecture).

*B. Le déploiement.* La commande type, depuis `~/src/openstack` : `uv run kolla-ansible <action> -i inventaire/multinode --configdir etc/kolla`.

4. **`bootstrap-servers`** (rôle `baremetal` : `.venv/share/kolla-ansible/ansible/roles/baremetal/`) : installe Docker CE depuis le dépôt de Docker et le SDK Python pour Ansible, crée le compte `kolla`, complète `/etc/hosts` avec les adresses `api_interface` des nœuds (`customize_etc_hosts`), règle quelques paramètres système et désactive le profil AppArmor de libvirt de l'hôte.
   ```
   admin@adm01:~$ ssh oscmp01 'sudo docker version --format "{{.Server.Version}}"; grep -E "osctl01|oscmp0" /etc/hosts'
   28.x
   10.10.50.51 osctl01
   10.10.50.52 oscmp01
   10.10.50.53 oscmp02
   ```
5. **`prechecks`**, **`pull`**, **`deploy`** : à titre d'ordre de grandeur sur `pve01` (à mesurer chez toi) : `prechecks` 2-4 min, `pull` 10-25 min selon le débit (plusieurs Go par nœud : `ssh osctl01 sudo docker system df`), `deploy` 25-45 min. Échecs typiques rencontrés à ce stade et leur correction **dans le dépôt** :
   - `prechecks` : « Hostname has to resolve uniquely to the IP address of api_interface » → `/etc/hosts` contenait encore `127.0.1.1 osctl01` (cloud-init) : corriger la gestion de `/etc/hosts` (option `manage_etc_hosts: false` de cloud-init dans l'image, ou tâche du rôle `noeud_openstack`), relancer `bootstrap-servers` puis `prechecks` ;
   - `prechecks` : interface externe introuvable sur un calcul → `neutron_external_interface` placée dans `globals.yml` ;
   - `deploy` : expiration au téléchargement d'une image → relancer `pull`, puis `deploy` (Kolla est idempotent).
6. **`post-deploy`** écrit dans le **dossier de configuration** (`etc/kolla/`, donc dans le dépôt) `admin-openrc.sh` et `clouds.yaml`, avec le mot de passe administrateur **en clair** et l'URL **interne** (`http://openstack-int.par1.medisphere.internal:5000`, sans TLS au palier 1). Le `.gitignore` les exclut ; on ne s'en sert pas sur `adm01`, qui passe par la VIP externe en HTTPS.
7. **Clients** : [`clouds.yaml`](fichiers/M10-E04/adm01/clouds.yaml) (cloud `medisphere-admin`) et `secure.yaml`, produit sans fichier intermédiaire ni affichage :
   ```
   admin@adm01:~/src/openstack$ (umask 077; uv run ansible-vault view etc/kolla/passwords.yml \
       | yq '{"clouds": {"medisphere-admin": {"auth": {"password": .keystone_admin_password}}}}' \
       > ~/.config/openstack/secure.yaml)
   admin@adm01:~$ openstack --os-cloud medisphere-admin token issue -c expires -c project_id
   ```

*C. Vérifier.*

8. Sur les nœuds et par l'API :
   ```
   admin@adm01:~$ for h in osctl01 oscmp01 oscmp02; do echo "== $h"; ssh $h 'sudo docker ps --format "{{.Names}} {{.Status}}" | sort; sudo docker ps -q --filter health=unhealthy | wc -l'; done
   admin@adm01:~$ export OS_CLOUD=medisphere-admin
   admin@adm01:~$ openstack endpoint list -c "Service Name" -c Interface -c URL --sort-column "Service Name"
   admin@adm01:~$ openstack compute service list
   +----+----------------+---------+----------+---------+-------+
   | ID | Binary         | Host    | Zone     | Status  | State |
   | …  | nova-scheduler | osctl01 | internal | enabled | up    |
   | …  | nova-conductor | osctl01 | internal | enabled | up    |
   | …  | nova-compute   | oscmp01 | nova     | enabled | up    |
   | …  | nova-compute   | oscmp02 | nova     | enabled | up    |
   admin@adm01:~$ openstack network agent list -c "Agent Type" -c Host -c Alive
   | OVN Controller Gateway agent | osctl01 | :-) |
   | OVN Controller agent         | oscmp01 | :-) |
   | OVN Metadata agent           | oscmp01 | :-) |
   | OVN Controller agent         | oscmp02 | :-) |
   | OVN Metadata agent           | oscmp02 | :-) |
   admin@adm01:~$ openstack hypervisor list
   admin@adm01:~$ ssh osctl01 'ip -br addr show ens18; sudo grep -E "virtual_router_id|virtual_ipaddress" -A3 /etc/kolla/keepalived/keepalived.conf'
   ens18  UP  10.10.50.51/24 10.10.50.200/32 10.10.50.201/32 …
   ```
   Points d'accès : `public` en `https://openstack.par1.medisphere.internal:<port>`, `internal` en `http://openstack-int.par1.medisphere.internal:<port>`. Avec OVN, il n'y a ni agent L3 ni agent DHCP : le routage, la traduction d'adresses et le DHCP sont des **flux logiques** compilés par `ovn-northd` et appliqués par `ovn-controller` sur chaque nœud ; `osctl01` est l'unique **passerelle** (« Gateway agent »), les calculs ont un contrôleur et un agent de métadonnées.
9. Compte rendu : modèle [`CHG-1104-deploiement-initial.md`](fichiers/M10-E04/medisphere/docs/cloud/changements/CHG-1104-deploiement-initial.md).

*Renouveler avant l'échéance (jusqu'à M10-E27).* Le cloud tourne, la VIP est portée par keepalived : pas de défi ACME, on renouvelle avec le certificat en cours.
```
admin@adm01:~/src/openstack$ outils/certificat-externe.sh renouveler
admin@adm01:~/src/openstack$ git commit -am "fix(tls): renouvellement du certificat de la VIP externe"
admin@adm01:~/src/openstack$ uv run kolla-ansible reconfigure -i inventaire/multinode --configdir etc/kolla -t loadbalancer
```
Le dossier temporaire est en mémoire (`/dev/shm`, 700) et effacé à la sortie du script.

**Explications**

- **Les étapes.** `bootstrap-servers` prépare l'**hôte** (moteur de conteneurs, comptes, `/etc/hosts`) ; `prechecks` vérifie sans rien changer (ports libres, noms, versions, interfaces, VIP non utilisées) ; `pull` télécharge les images, séparément du déploiement pour ne pas mélanger les erreurs de réseau et celles de configuration ; `deploy` génère la configuration de chaque service dans `/etc/kolla/<service>/`, crée les bases, les comptes de service, les points d'accès, puis lance les conteneurs dans l'ordre des dépendances ; `post-deploy` produit les fichiers d'accès de l'administrateur.
- **Comment la configuration atteint le conteneur.** Kolla dépose `config.json` et les fichiers du service dans `/etc/kolla/<service>/` ; au démarrage, le script `kolla_start` de l'image copie les fichiers aux bons endroits (droits compris), puis lance le processus. Une modification à la main de `/etc/kolla/<service>/` est donc prise en compte au prochain redémarrage… et écrasée au prochain `reconfigure`.
- **Le certificat d'HAProxy.** HAProxy lit un fichier qui contient le certificat, l'intermédiaire et la clé. Kolla le copie depuis `certificates/` vers `/etc/kolla/haproxy/` (et équivalents) sur les nœuds du groupe `loadbalancer` ; le module `copy` d'Ansible déchiffre un fichier Vault à la copie : le secret existe en clair **sur `osctl01`**, là où il sert, et nulle part ailleurs.
- **Pourquoi poser la VIP à la main pour la première émission.** Le défi HTTP-01 se fait sur l'adresse **du nom demandé** : `ca01` interroge `http://openstack.par1.medisphere.internal/.well-known/acme-challenge/…`, donc 10.10.50.201. Avant le déploiement, personne ne porte cette adresse ; après, c'est HAProxy qui écoute sur le port 80 de la VIP. Le temps d'une minute, `osctl01` la porte à la place de keepalived. La détection d'adresse en double (`arping -D`) évite de voler l'adresse d'un autre.
- **VRID 150.** Kolla configure keepalived en VRRP sur `network_interface` ; les passerelles du lab parlent VRRP sur le même VLAN avec le VRID 50. Deux routeurs virtuels de même numéro sur un même segment s'échangent des annonces qu'ils croient adressées à leur groupe : bascules intempestives, adresse virtuelle qui saute d'une machine à l'autre. Ici les passerelles font de l'unicast (M07), ce qui limite l'interférence, mais un VRID unique par segment reste la règle.

**Alternatives**

- **`kolla-ansible certificates`** : Kolla fabrique une petite autorité de test et les certificats ; la documentation précise qu'ils ne conviennent pas à la production (et il faudrait distribuer cette autorité à tous les clients).
- **Le client ACME de Kolla** (`enable_letsencrypt`, serveur ACME configurable, renouvellement automatique déployé sur HAProxy) pointé vers `ca01` : c'est la cible de M10-E27 ; au premier déploiement, il ajoute des inconnues (confiance du client ACME dans `ca01`, défi servi par HAProxy) qu'on préfère traiter séparément.
- **Provisioner JWK `admin`** de `ca01` : pas de défi, mais des certificats de 7 jours au plus depuis M06-E27 : intenable sans automatisation.
- **Défi DNS-01** (enregistrement TXT dans PowerDNS) : pas besoin de la VIP, et possible pour plusieurs noms ; exige un client ACME qui sache écrire dans PowerDNS (lego, certbot avec un greffon) : un outil de plus.

**Pièges classiques**

- Oublier `--configdir etc/kolla` : Kolla cherche `/etc/kolla/globals.yml` sur `adm01`, ne le trouve pas, ou pire en trouve un vieux.
- `haproxy.pem` dans le mauvais ordre (clé avant le certificat) ou sans l'intermédiaire : HAProxy démarre, mais les clients qui ne connaissent que la racine refusent la chaîne (« unable to get local issuer certificate »).
- La VIP posée à la main oubliée sur `ens18` : keepalived la croit déjà présente, `prechecks` signale l'adresse comme utilisée (« VIP already in use »), ou deux machines la portent. Le script la retire même en cas d'erreur (`trap`).
- Lancer `deploy` avant que le DNS de `openstack-int` ne résolve depuis les nœuds : les services reçoivent dans leur configuration une URL interne qu'ils ne savent pas joindre.
- Utiliser le `clouds.yaml` de `post-deploy` tel quel depuis `adm01` : URL interne, sans TLS, mot de passe en clair.
- Interpréter `:-)`/`XXX` de `network agent list` sans attendre : un agent met jusqu'à une minute à se déclarer après un redémarrage.
- `docker ps` sans `sudo` : refusé ; le compte `admin` n'est pas dans le groupe `docker` (et ne doit pas l'être : ce groupe vaut root).

**En production chez MédiSphère**

Trois contrôleurs (E24), une VIP externe publiée derrière les répartiteurs `lb01`/`lb02` de la DMZ plutôt que directement, TLS interne et de bout en bout, certificats renouvelés automatiquement et supervisés (M06-E29, M21), images tirées d'un registre interne et épinglées par empreinte, déploiement par un pipeline protégé avec approbation, fenêtre annoncée et compte rendu systématique.

---

### M10-E05 — Keystone : domaines, projets, rôles

**Solution**

*A. Explorer.*

1. État initial :
   ```
   admin@adm01:~$ export OS_CLOUD=medisphere-admin
   admin@adm01:~$ openstack domain list
   | default | Default | True | The default domain |
   admin@adm01:~$ openstack user list --domain Default -c Name
   admin  glance  heat  heat_domain_admin  neutron  nova  placement  …
   admin@adm01:~$ openstack role list -c Name
   admin  member  reader  service  …
   admin@adm01:~$ openstack implied role list
   | Prior Role | Implied Role |
   | admin      | member       |
   | member     | reader       |
   ```
   Le domaine `Default` contient l'administrateur et les **comptes de service** (un par service : Nova s'authentifie auprès de Neutron avec le compte `nova`, etc.) ; Heat a aussi son propre domaine (`heat_user_domain`) pour les utilisateurs qu'il crée dans les piles. Keystone a créé à l'amorçage `admin`, `member`, `reader` (et, selon la version, `service` et `manager`) ; `admin` implique `member`, qui implique `reader` : un `admin` a donc tous les droits d'un `member`.
2. Domaine jetable :
   ```
   admin@adm01:~$ openstack domain create essai-e05
   admin@adm01:~$ openstack project create --domain essai-e05 projet-essai
   admin@adm01:~$ openstack group create --domain essai-e05 groupe-essai
   admin@adm01:~$ openstack user create --domain essai-e05 --password-prompt utilisateur-essai
   admin@adm01:~$ openstack group add user --group-domain essai-e05 --user-domain essai-e05 groupe-essai utilisateur-essai
   admin@adm01:~$ openstack role add --group groupe-essai --group-domain essai-e05 --project projet-essai --project-domain essai-e05 member
   admin@adm01:~$ ( unset OS_CLOUD; read -rs -p "Mot de passe : " OS_PASSWORD; echo; export OS_PASSWORD
       export OS_AUTH_URL=https://openstack.par1.medisphere.internal:5000/v3 OS_IDENTITY_API_VERSION=3 \
              OS_USERNAME=utilisateur-essai OS_USER_DOMAIN_NAME=essai-e05 \
              OS_PROJECT_NAME=projet-essai OS_PROJECT_DOMAIN_NAME=essai-e05 \
              OS_CACERT=/usr/local/share/ca-certificates/medisphere-root-ca.crt
       openstack token issue
       OS_PROJECT_NAME=admin OS_PROJECT_DOMAIN_NAME=Default openstack token issue )
   ```
   Le premier jeton est limité à `projet-essai` (champ `project_id`) : toute action se fait **dans** ce projet, avec les rôles qu'on y a. Le second échoue (401 : « The request you have made requires authentication ») : Keystone refuse d'émettre un jeton pour un projet où l'utilisateur n'a aucun rôle.
3. Suppression :
   ```
   admin@adm01:~$ openstack domain delete essai-e05
   Failed to delete domain … : Cannot delete a domain that is enabled, please disable it first. (HTTP 403)
   admin@adm01:~$ openstack domain set --disable essai-e05 && openstack domain delete essai-e05
   ```
   Désactiver d'abord est un garde-fou (on ne supprime pas par erreur un domaine en service ; la désactivation invalide déjà les jetons de ses utilisateurs). La suppression emporte ses utilisateurs, groupes et projets **dans Keystone** ; les ressources des projets (instances, volumes) ne sont **pas** supprimées : elles deviennent orphelines. Ici, il n'y en a pas.

*B. Par le code.* [`playbooks/identite.yml`](fichiers/M10-E05/openstack/playbooks/identite.yml), [`donnees/identite.yml`](fichiers/M10-E05/openstack/donnees/identite.yml) et [`donnees/vault-identite.yml.exemple`](fichiers/M10-E05/openstack/donnees/vault-identite.yml.exemple) (à chiffrer sous `critique`).

4. Points d'attention vérifiés dans la collection `openstack.cloud` 2.6 : `identity_group` exige un **identifiant** de domaine (`domain_id`), d'où la réutilisation du résultat de `identity_domain` ; `role_assignment` a `group_domain` et `project_domain` pour **chercher** groupe et projet (le paramètre `domain` porterait le rôle sur le domaine lui-même) ; `identity_user` pose le mot de passe à la création seulement (`update_password: on_create`) et la tâche est en `no_log: true` ; l'appartenance aux groupes se fait par identifiants (un nom d'utilisateur n'est unique que dans son domaine).
   ```
   admin@adm01:~/src/openstack$ uv run ansible-vault encrypt --encrypt-vault-id critique donnees/vault-identite.yml
   admin@adm01:~/src/openstack$ uv run ansible-playbook playbooks/identite.yml
   …
   PLAY RECAP ****
   localhost : ok=7 changed=6 …
   admin@adm01:~/src/openstack$ uv run ansible-playbook playbooks/identite.yml | tail -n 2
   localhost : ok=7 changed=0 …
   ```
5. Vérification :
   ```
   admin@adm01:~$ openstack role assignment list --names --effective --user julien.petit --user-domain medisphere
   | Role   | User                    | Group | Project                    |
   | member | julien.petit@medisphere |       | mediagenda-dev@medisphere  |
   | reader | julien.petit@medisphere |       | mediagenda-dev@medisphere  |
   | reader | julien.petit@medisphere |       | mediagenda-prod@medisphere |
   admin@adm01:~$ openstack role assignment list --names --group equipe-mediagenda --group-domain medisphere
   | member |  | equipe-mediagenda@medisphere | mediagenda-dev@medisphere  |
   | reader |  | equipe-mediagenda@medisphere | mediagenda-prod@medisphere |
   ```
   `--effective` résout les groupes **et** les rôles impliqués (d'où `reader` sur `mediagenda-dev`, impliqué par `member`).

*C. Les clients.* [`clouds.yaml`](fichiers/M10-E05/adm01/clouds.yaml) complet (trois clouds) et [`secure.yaml.exemple`](fichiers/M10-E05/adm01/secure.yaml.exemple).

6. Preuves :
   ```
   admin@adm01:~$ openstack --os-cloud medisphere-mediagenda-dev server list
   (vide)
   admin@adm01:~$ openstack --os-cloud medisphere-mediagenda-dev --os-project-name plateforme token issue
   The request you have made requires authentication. (HTTP 401)
   admin@adm01:~$ openstack --os-cloud medisphere-mediagenda-dev --os-project-name mediagenda-prod security group list
   (liste)
   admin@adm01:~$ openstack --os-cloud medisphere-mediagenda-dev --os-project-name mediagenda-prod security group create essai
   Error while executing command: ForbiddenException: 403, rule:create_security_group is disallowed by policy
   ```

*D. Les robots.*

7. *Application credential* :
   ```
   admin@adm01:~$ openstack --os-cloud medisphere-plateforme application credential create ac-essai-e05 \
       --role member --expiration "$(date -u -d '+1 day' +%Y-%m-%dT%H:%M:%S)" --description "Essai M10-E05"
   | id     | <ID>     |
   | secret | <SECRET> |   ← affiché une seule fois
   admin@adm01:~$ t=$(mktemp) && chmod 600 "$t" && cat > "$t" <<'EOF'
   clouds:
     essai-ac:
       auth_type: v3applicationcredential
       auth:
         auth_url: https://openstack.par1.medisphere.internal:5000/v3
         application_credential_id: "<ID>"
         application_credential_secret: "<SECRET>"
       cacert: /usr/local/share/ca-certificates/medisphere-root-ca.crt
   EOF
   admin@adm01:~$ OS_CLIENT_CONFIG_FILE="$t" openstack --os-cloud essai-ac network list
   admin@adm01:~$ rm -f "$t"; openstack --os-cloud medisphere-plateforme application credential delete ac-essai-e05
   ```
   (Le secret est collé dans un fichier 600 par l'éditeur ou le *here-document*, jamais sur une ligne de commande.) Réponses : l'*application credential* appartient à l'**utilisateur** qui l'a créée, limitée au projet de son jeton et aux rôles choisis ; si l'utilisateur perd ces rôles sur le projet, elle cesse de fonctionner ; s'il est supprimé, elle est supprimée avec lui (d'où, en production, un compte de **service** nominatif, `svc-tofu-<équipe>`, pour porter celles des pipelines). `--unrestricted` lui permet de créer d'autres *application credentials* et des *trusts* : un secret volé deviendrait une porte permanente. Pour OpenTofu en CI : identifiant et secret en variables **protégées et masquées** du projet GitLab (palier 2, E15), puis dans Vault (module 25).

**Explications**

- **Domaine et projet.** Le domaine est un **espace de noms** et une frontière d'administration (un administrateur de domaine peut gérer ses utilisateurs et projets sans toucher aux autres) ; le projet est l'**unité de propriété** des ressources et des quotas. `Default` reste réservé à l'opérateur et aux services : une fédération future (Keycloak, module 24) se branchera sur `medisphere` sans risque pour les comptes de service.
- **Rôles aux groupes.** Arrivées et départs deviennent une seule opération (appartenance), l'audit lit des groupes au lieu de N lignes, et aucune « exception » ne s'accumule.
- **Portée d'un jeton.** Les politiques des services évaluent rôle **et** portée ; avec les politiques par défaut récentes (« secure RBAC »), `reader` peut lister, `member` créer et modifier dans son projet, `admin` (sur un projet) administrer le **service** entier : c'est pourquoi on ne donne jamais `admin` à une équipe (E09, question 13 ; E23).

**Alternatives**

- **CLI dans un script** idempotent (tests `show` avant `create`) : plus court à écrire, plus long à rendre idempotent et sûr pour les mots de passe.
- **OpenTofu** (`openstack_identity_project_v3`, `openstack_identity_role_assignment_v3`…) : même résultat, avec un état ; la gestion des **mots de passe** d'utilisateurs y est plus délicate (ils se retrouvent dans l'état). E15 décide où vit chaque objet ; ici, l'identité est de la configuration de plateforme, tenue par Ansible.
- **Fédération** (Keycloak en OIDC, module 24) : plus aucun mot de passe local, groupes venus de l'annuaire, *mapping* vers les projets.

**Pièges classiques**

- `openstack user create … --password <valeur>` : le mot de passe dans l'historique du shell et dans `ps`. `--password-prompt`, ou le code.
- Créer les groupes et projets **sans** `--domain` : ils atterrissent dans `Default`.
- Attribuer `member` à `equipe-mediagenda` « sur le domaine » au lieu des projets : selon les politiques, cela ne donne rien (ou trop).
- Oublier `--project-domain`/`--user-domain` : la CLI cherche dans `Default` et répond « No project with a name or ID of 'plateforme' exists ».
- Se tromper de cloud (`OS_CLOUD` exporté puis oublié) et créer en administrateur ce qu'on voulait créer en membre : les ressources appartiennent alors au projet `admin`.
- Chiffrer `vault-identite.yml` **après** l'avoir commité.

**En production chez MédiSphère**

Comptes humains fédérés (Keycloak, MFA) ; comptes locaux limités aux comptes de service et au bris de glace ; politique de verrouillage (E27) ; revue trimestrielle des appartenances aux groupes ; *application credentials* à expiration courte, portées par des comptes de service, inventoriées et renouvelées automatiquement ; journaux d'audit de Keystone (notifications CADF) envoyés à la centralisation des journaux (M22).

---

### M10-E06 — Glance : les images

**Solution**

1. Téléchargement et sommes (le script [`outils/publier-image.sh`](fichiers/M10-E06/openstack/outils/publier-image.sh) fait tout ; le voici à la main) :
   ```
   admin@adm01:~/m10/e06$ curl -fLO --proto '=https' https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
   admin@adm01:~/m10/e06$ curl -fLO --proto '=https' https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
   admin@adm01:~/m10/e06$ sha512sum --check --ignore-missing SHA512SUMS
   debian-13-genericcloud-amd64.qcow2: OK
   admin@adm01:~/m10/e06$ curl -fLO --proto '=https' https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2
   admin@adm01:~/m10/e06$ curl -fLO --proto '=https' https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2.CHECKSUM
   admin@adm01:~/m10/e06$ sha256sum --check --ignore-missing Rocky-10-GenericCloud-Base.latest.x86_64.qcow2.CHECKSUM
   Rocky-10-GenericCloud-Base.latest.x86_64.qcow2: OK
   ```
   La somme prouve que le fichier n'a pas été **altéré en route** par rapport au fichier de sommes… téléchargé du même serveur. Pour prouver qu'il vient bien de Debian, il faut que le fichier de sommes soit **signé** et vérifier la signature avec la clé publique de l'équipe qui publie les images (récupérée par un autre canal, par exemple le trousseau du paquet `debian-keyring`). Regarde dans le dossier s'il existe un fichier de signature à côté de `SHA512SUMS` (à confirmer pour la série trixie) ; Rocky publie une signature GPG de ses fichiers `CHECKSUM` (`.CHECKSUM.sig` ou équivalent, à confirmer) avec la clé de signature de Rocky.
2. Inspection :
   ```
   admin@adm01:~/m10/e06$ qemu-img info debian-13-genericcloud-amd64.qcow2
   file format: qcow2
   virtual size: 3 GiB (3221225472 bytes)
   disk size: 4xx MiB
   ```
   La taille **virtuelle** est celle du disque vu par l'invité ; la taille du **fichier** ne compte que les blocs écrits (qcow2 alloue à la demande). En `raw`, le fichier ferait la taille virtuelle (3 Gio, creux selon le système de fichiers) ; dans Ceph, l'image RBD est provisionnée finement : elle n'occupera que les blocs écrits, multipliés par la réplication. La conversion est nécessaire en E10 parce que Nova ne sait **cloner** (copie-sur-écriture RBD) qu'une image Glance `raw` : avec une qcow2, chaque instance déclenche un téléchargement et une conversion complète.
3. Publication de `debian-13` :
   ```
   admin@adm01:~$ openstack image create debian-13 --file ~/m10/e06/debian-13-genericcloud-amd64.qcow2 \
       --disk-format qcow2 --container-format bare --public \
       --property os_distro=debian --property os_version=13 --property os_type=linux \
       --property hw_disk_bus=scsi --property hw_scsi_model=virtio-scsi --property hw_qemu_guest_agent=yes
   admin@adm01:~$ openstack image show debian-13 -c os_hash_algo -c os_hash_value -f value
   sha512
   3e1c…
   admin@adm01:~$ grep debian-13-genericcloud-amd64.qcow2 ~/m10/e06/SHA512SUMS | cut -d' ' -f1
   3e1c…
   ```
   Glance calcule le SHA-512 de ce qu'il **reçoit** : identique à celui publié par Debian, la chaîne est complète (source → poste → Glance), au maillon de la signature près (étape 1).
4. `rocky-10` partagée :
   ```
   admin@adm01:~$ openstack image create rocky-10 --file … --disk-format qcow2 --container-format bare --shared --property …
   admin@adm01:~$ openstack image add project rocky-10 plateforme --project-domain medisphere
   | status | pending |
   admin@adm01:~$ openstack --os-cloud medisphere-plateforme image list | grep -c rocky-10
   0
   admin@adm01:~$ openstack --os-cloud medisphere-plateforme image set --accept rocky-10
   admin@adm01:~$ openstack --os-cloud medisphere-plateforme image list | grep rocky-10
   | … | rocky-10 | active |
   admin@adm01:~$ openstack --os-cloud medisphere-mediagenda-dev image list
   | … | debian-13 | active |
   ```
   Tant que le membre est `pending`, l'image n'apparaît pas dans la liste par défaut du projet invité (il peut l'utiliser s'il connaît son identifiant) : le partage est une **proposition** que le projet accepte ou rejette, pour qu'un tiers ne puisse pas inonder sa liste. `julien.petit` ne la voit jamais : `mediagenda-dev` n'est pas membre.
5. Propriétés :
   - `hw_disk_bus=scsi` + `hw_scsi_model=virtio-scsi` : le disque est présenté derrière un contrôleur **virtio-scsi** (`/dev/sda`) au lieu de virtio-blk (`/dev/vda`) ; virtio-scsi transmet le TRIM/`discard` (utile sur Ceph pour rendre l'espace) et accepte beaucoup de disques ;
   - `hw_qemu_guest_agent=yes` : Nova ajoute à l'instance le canal série de l'agent QEMU ; utile seulement si l'agent est **installé dans l'image** (ce n'est pas le cas de l'image *genericcloud* de Debian : cloud-init l'installera, `packages: [qemu-guest-agent]`). Il permet le gel des systèmes de fichiers pendant un instantané (`os_require_quiesce`) et le changement de mot de passe ;
   - `os_distro`, `os_version` : métadonnées normalisées (libosinfo) lues par les outils (tableau de bord, filtres d'OpenTofu ou de Heat, inventaires) ; `os_type=linux` sert à Nova pour formater un disque éphémère (système de fichiers par défaut).
6. `rm ~/m10/e06/*` (ou le script, qui nettoie seul).

**Explications**

Glance stocke des **octets** et des **métadonnées** ; il ne vérifie pas le contenu d'une image. La somme calculée à la réception (`os_hash_value`, algorithme `sha512` par défaut) permet à n'importe qui de vérifier plus tard ce qu'il démarre. La **visibilité** règle qui voit l'image : `public` (tout le monde ; réservé à l'administrateur par défaut), `private` (le projet propriétaire), `shared` (le propriétaire et les projets **membres** qui ont accepté), `community` (tout le monde peut l'utiliser, sans qu'elle encombre les listes par défaut).

**Alternatives**

- **Importation interopérable** (`openstack image create --import`, méthode `web-download`) : Glance télécharge lui-même l'image depuis l'URL ; pratique, mais la vérification de la somme par la source doit alors se faire après coup.
- **Images maison** construites par Packer (module 03, constructeur `openstack`) : agent QEMU, racine MédiSphère et durcissement inclus, publiées par un pipeline.
- **Conversion dès maintenant en `raw`** (`--format raw` du script) : prépare E10 mais occupe 3 Gio sur `osctl01` par image.

**Pièges classiques**

- `--disk-format raw` sur un fichier qcow2 (ou l'inverse) : l'image se publie, l'instance ne démarre pas (« No bootable device ») ou démarre sur un disque illisible.
- Deux images de même nom (Glance l'accepte) : `openstack server create --image debian-13` échoue (« More than one Image exists with the name »), et un outil qui choisit « la première » choisit au hasard.
- `hw_qemu_guest_agent=yes` avec un instantané « avec gel » sans agent dans l'invité : l'instantané échoue ou attend.
- Vérifier la somme avec un fichier de sommes téléchargé en HTTP, ou d'un miroir non officiel.

**En production chez MédiSphère**

Un catalogue d'images **maison** reconstruit chaque mois (correctifs), signé (Cosign, module 13) et publié par pipeline, avec des propriétés de cycle de vie (`medisphere_statut=current|deprecated`) et le retrait progressif des anciennes (passage en `community`, puis désactivation). Les images publiques de la distribution ne servent que de base aux constructions.

---

### M10-E07 — Nova : gabarits, clés et première instance

**Solution**

1. Capacité :
   ```
   admin@adm01:~$ openstack hypervisor list
   admin@adm01:~$ openstack hypervisor show oscmp01 -c vcpus -c memory_mb -c local_gb
   ```
   Les champs détaillés dépendent de la micro-version de l'API (les plus récentes renvoient surtout des informations d'inventaire ; la consommation se lit dans Placement, greffon `osc-placement` au palier 2). Valeurs par défaut de Nova 2026.1 : `initial_cpu_allocation_ratio` 4.0, `initial_ram_allocation_ratio` 1.0, `initial_disk_allocation_ratio` 1.0, `reserved_host_memory_mb` 512. Pour un calcul de 8 Go (≈ 7,7 Gio vus par Nova) : ≈ 7,2 Gio allouables ; un `m1.grand` (4 Gio) y tient une fois. Par la mémoire, **deux** `m1.grand` au plus (un par calcul). Par le **disque**, aucun au palier 1 : un `m1.grand` demande 40 Go de disque racine **local**, et le disque de 40 Go du calcul n'en a pas autant de libre (système, images Kolla) ; l'ordonnanceur répondra « No valid host was found ». Cela change en E10 (disques des instances sur Ceph). On ne surréserve pas la mémoire : un manque de mémoire se paie par l'OOM killer du calcul (instance tuée) ou par le *swap* de l'hôte (tout le calcul ralentit), là où un manque de CPU ne fait que ralentir.
2. Gabarits : [`playbooks/catalogue.yml`](fichiers/M10-E07/openstack/playbooks/catalogue.yml) et [`donnees/catalogue.yml`](fichiers/M10-E07/openstack/donnees/catalogue.yml).
   ```
   admin@adm01:~/src/openstack$ uv run ansible-playbook playbooks/catalogue.yml
   admin@adm01:~$ openstack flavor list
   | ID | Name     |  RAM | Disk | Ephemeral | VCPUs | Is Public |
   | …  | m1.grand | 4096 |   40 |         0 |     2 | True      |
   | …  | m1.moyen | 2048 |   20 |         0 |     2 | True      |
   | …  | m1.petit | 1024 |   10 |         0 |     1 | True      |
   ```
   Un gabarit est quasi immuable : l'API ne permet pas de modifier ses ressources (seulement sa description et ses propriétés) ; Nova **recopie** le gabarit dans chaque instance au moment de la création. Pour changer, on crée un nouveau gabarit, on redimensionne les instances (`server resize`) et on retire l'ancien.
3. Clé :
   ```
   admin@adm01:~$ openstack --os-cloud medisphere-plateforme keypair create --public-key ~/.ssh/id_ed25519.pub cle-adm01
   ```
   Une paire de clés appartient à un **utilisateur**, pas au projet : `karim.benali`, dans le même projet, ne la voit pas et ne peut pas lancer d'instance avec elle. (L'injection se fait au démarrage par les métadonnées : changer la paire ensuite ne change rien dans une instance existante.)
4. Réseau :
   ```
   admin@adm01:~$ export OS_CLOUD=medisphere-plateforme
   admin@adm01:~$ openstack network create reseau-plateforme
   admin@adm01:~$ openstack subnet create sous-reseau-plateforme --network reseau-plateforme \
       --subnet-range 172.16.10.0/24 --gateway 172.16.10.1 --dns-nameserver 10.10.20.10 --dns-nameserver 10.10.20.16
   admin@adm01:~$ openstack network show reseau-plateforme -c mtu -c provider:network_type
   | mtu | 1442 |
   ```
   (Un membre ne voit pas `provider:network_type` ; en administrateur : `geneve`.) La MTU vient du calcul de Neutron : MTU du réseau physique (`global_physnet_mtu`, 1500 par défaut) moins le surcoût de l'encapsulation Geneve (E08).
5. L'instance :
   ```
   admin@adm01:~$ openstack server create essai01 --flavor m1.petit --image debian-13 --key-name cle-adm01 \
       --network reseau-plateforme --wait
   admin@adm01:~$ openstack server event list essai01
   | Request ID | Server ID | Action | Start Time |
   | req-…      | …         | create | …          |
   admin@adm01:~$ openstack --os-cloud medisphere-admin server show essai01 -c OS-EXT-SRV-ATTR:host -c OS-EXT-SRV-ATTR:instance_name
   | OS-EXT-SRV-ATTR:host          | oscmp02           |
   | OS-EXT-SRV-ATTR:instance_name | instance-00000001 |
   admin@adm01:~$ ssh oscmp02 'sudo docker exec nova_libvirt virsh list --all; sudo docker exec nova_libvirt virsh domblklist instance-00000001'
    Id   Name                State
    1    instance-00000001   running
    Target   Source
    sda      /var/lib/nova/instances/<ID-INSTANCE>/disk
   admin@adm01:~$ openstack console log show essai01 | grep -E 'ci-info: \| +ens|Cloud-init v\. .* finished|ssh-ed25519'
   ```
   Le disque est un fichier qcow2 dont le **fichier de base** est l'image (cache `_base` du calcul) : copie-sur-écriture locale. Le journal de console montre l'adresse reçue par DHCP (172.16.10.x), les empreintes des clés d'hôte, la clé `cle-adm01` installée pour `debian` (preuve que le service de métadonnées a répondu), et « Cloud-init v. 25.1.x finished ».
6. Cycle de vie : `openstack server stop essai01` → Nova `SHUTOFF`, libvirt `shut off` ; `start` → `ACTIVE`/`running` ; `reboot` (doux, par ACPI) puis `reboot --hard` (coupure). `openstack server console url show essai01` donne une URL `https://openstack.par1.medisphere.internal:6080/vnc_lite.html?…` (ou `vnc_auto`) : c'est `nova-novncproxy`, publié par HAProxy sur la VIP **externe** ; le jeton de l'URL est à usage court.

**Explications**

Le parcours de la création : `nova-api` valide (quota, image, gabarit, réseau), enregistre l'instance et confie la suite à `nova-conductor` ; celui-ci demande une destination à `nova-scheduler`, qui interroge **Placement** (quels fournisseurs de ressources ont 1 vCPU, 1 Go, 10 Go ?) puis filtre et pondère, et **réserve** dans Placement ; le conducteur envoie la demande au `nova-compute` choisi (RabbitMQ), qui récupère l'image (Glance), demande le port à Neutron (OVN crée le port logique, l'adresse, les règles), écrit le XML libvirt et démarre le domaine, puis attend l'événement « port actif » de Neutron. E09 (question 1) et E44 reprennent ce trajet.

**Alternatives**

- Gabarits **privés** (`--private` + `flavor set --project`) pour un besoin ponctuel d'une équipe, plutôt qu'un gabarit public de plus.
- **Agrégats d'hôtes** et propriétés de gabarit (`aggregate_instance_extra_specs`) pour réserver des calculs à certains usages (production, GPU).
- **Config drive** (`--config-drive true`) plutôt que le service de métadonnées : utile quand le réseau de métadonnées n'est pas joignable (E18, E37).

**Pièges classiques**

- Créer le réseau en administrateur sans `--project` : il appartient au projet `admin`, invisible pour `plateforme`.
- Attendre une adresse joignable depuis `adm01` : le réseau du projet est privé et sans routeur (E08).
- Choisir `m1.grand` au palier 1 : « No valid host » par manque de disque local (pas un bogue).
- Lire `openstack server show` sans `--os-cloud medisphere-admin` : un membre ne voit pas les champs `OS-EXT-SRV-ATTR:*` (hôte, nom libvirt).
- Supprimer l'image `debian-13` alors que des instances l'utilisent : Glance la supprime, les instances tournent (leur disque a sa propre copie ou le cache `_base`), mais une reconstruction (`rebuild`) ou une évacuation devient impossible.

**En production chez MédiSphère**

Gabarits normalisés par famille (usage général, mémoire, calcul), alignés sur la capacité réelle des calculs (pas de gabarit qui ne tient sur aucun hôte), revus à chaque achat de matériel ; rapports d'allocation explicites dans la configuration (pas les défauts), mémoire réservée à l'hôte calculée (système, conteneurs Kolla, Ceph client) ; rapport de capacité régulier (E33).

---

### M10-E08 — Neutron et OVN : réseaux, routeurs, IP flottantes

**Solution**

1. Constats sur `osctl01` et un calcul :
   ```
   admin@adm01:~$ ssh osctl01 sudo docker exec openvswitch_vswitchd ovs-vsctl list-ports br-ex
   ens21
   patch-provnet-…-to-br-int
   admin@adm01:~$ ssh osctl01 sudo docker exec openvswitch_vswitchd ovs-vsctl get open . external_ids
   {…, ovn-bridge-mappings="physnet1:br-ex", ovn-cms-options="enable-chassis-as-gw", ovn-encap-ip="10.10.51.51", ovn-encap-type=geneve, …}
   admin@adm01:~$ ssh oscmp01 sudo docker exec openvswitch_vswitchd ovs-vsctl get open . external_ids
   {…, ovn-encap-ip="10.10.51.52", ovn-encap-type=geneve, …}       ← ni bridge-mappings, ni gw
   ```
   Kolla le décide d'après l'inventaire : les hôtes du groupe `network` reçoivent la carte externe dans `br-ex`, la correspondance `physnet1:br-ex` et l'option `enable-chassis-as-gw` (ils peuvent porter des ports de passerelle de routeurs) ; les calculs n'en ont pas tant que `neutron_ovn_distributed_fip` vaut `no` et qu'aucun réseau fournisseur n'est demandé sur eux. `ovn-encap-ip` est l'adresse de `tunnel_interface` : les tunnels Geneve passent bien par le VLAN 51.
2. Réseau externe : [`playbooks/reseau-externe.yml`](fichiers/M10-E08/openstack/playbooks/reseau-externe.yml) et [`donnees/reseau-externe.yml`](fichiers/M10-E08/openstack/donnees/reseau-externe.yml).
   ```
   admin@adm01:~/src/openstack$ uv run ansible-playbook playbooks/reseau-externe.yml
   admin@adm01:~$ openstack --os-cloud medisphere-admin network show ext-net -c router:external -c provider:network_type -c provider:physical_network -c mtu
   | mtu                       | 1500     |
   | provider:network_type     | flat     |
   | provider:physical_network | physnet1 |
   | router:external           | External |
   ```
   Pas de DHCP : aucune instance n'est branchée directement sur ce réseau ; ses adresses sont attribuées par Neutron aux passerelles de routeurs et aux IP flottantes, sans protocole. Un serveur DHCP y consommerait une adresse et répondrait à tout équipement du VLAN 52. `--external` donne aux projets le droit d'y brancher la **passerelle** de leurs routeurs et d'y prendre des IP flottantes ; `--share` leur donnerait en plus le droit d'y brancher des **instances** : exactement ce qu'on ne veut pas. MTU : `ext-net` est un réseau plat sur le réseau physique, 1500 (`global_physnet_mtu`) ; `reseau-plateforme` est encapsulé : 1500 − (38 octets d'en-tête Geneve réservés par la configuration Neutron de Kolla pour OVN + 20 d'en-tête IPv4) = **1442**. La MTU 9000 du VLAN 51 n'y change rien : Neutron calcule à partir de **sa** configuration (`global_physnet_mtu`, `path_mtu`), il ne mesure pas les cartes. Lui dire que le transport accepte 9000 permettrait des réseaux de projet à 8942, mais le trafic vers l'extérieur repasse à 1500 sur le VLAN 52 : à traiter proprement en E12, pas ici.
3. Routeur :
   ```
   admin@adm01:~$ export OS_CLOUD=medisphere-plateforme
   admin@adm01:~$ openstack router create routeur-plateforme
   admin@adm01:~$ openstack router set --external-gateway ext-net routeur-plateforme
   admin@adm01:~$ openstack router add subnet routeur-plateforme sous-reseau-plateforme
   admin@adm01:~$ openstack router show routeur-plateforme -c external_gateway_info -f json | jq -r '.external_gateway_info.external_fixed_ips[].ip_address'
   10.10.52.2xx
   ```
4. Groupe de sécurité :
   ```
   admin@adm01:~$ openstack security group create ssh-icmp-admin --description "SSH et ping depuis MGMT (adm01)"
   admin@adm01:~$ openstack security group rule create ssh-icmp-admin --ingress --protocol tcp --dst-port 22 --remote-ip 10.10.10.0/24
   admin@adm01:~$ openstack security group rule create ssh-icmp-admin --ingress --protocol icmp --remote-ip 10.10.10.0/24
   admin@adm01:~$ openstack server add security group essai01 ssh-icmp-admin
   ```
   Le groupe `default` n'autorise en entrée que le trafic venant des membres du **même** groupe : rien de l'extérieur. L'ouvrir à `0.0.0.0/0` exposerait toutes les instances de tous les projets (chaque projet a son `default`, et les nouvelles instances le reçoivent automatiquement) à tout ce qui atteint le VLAN 52.
5. IP flottante :
   ```
   admin@adm01:~$ openstack floating ip create ext-net -c floating_ip_address -f value
   10.10.52.2yy
   admin@adm01:~$ openstack server add floating ip essai01 10.10.52.2yy
   admin@adm01:~$ ping -c 3 10.10.52.2yy
   admin@adm01:~$ ssh debian@10.10.52.2yy 'ip -br a; ip r; ip -o link show | grep -o "mtu [0-9]*"; resolvectl status | grep "DNS Servers"'
   ens3   UP  172.16.10.x/24 …          (nom selon le bus de la carte)
   default via 172.16.10.1 dev ens3 …
   mtu 1442
   DNS Servers: 10.10.20.10 10.10.20.16
   ```
   L'instance ne connaît que son adresse privée ; sa MTU (1442) lui a été donnée par le DHCP d'OVN (option 26). Résoudre des noms depuis l'instance dépend de la matrice des flux du VLAN 52 (E12).
6. OVN :
   ```
   admin@adm01:~$ ssh osctl01 sudo docker exec ovn_nb_db ovn-nbctl show
   switch … (neutron-<ID-RESEAU>) (aka reseau-plateforme)
       port …  addresses: ["fa:16:3e:… 172.16.10.x"]
       port … type: router  router-port: lrp-…
   switch … (neutron-<ID-EXT-NET>) (aka ext-net)
       port provnet-…  type: localnet  addresses: ["unknown"]
   router … (neutron-<ID-ROUTEUR>) (aka routeur-plateforme)
       port lrp-…  networks: ["172.16.10.1/24"]
       port lrp-…  networks: ["10.10.52.2xx/24"]  gateway chassis: [<chassis-osctl01>]
       nat …  external ip: "10.10.52.2xx"  logical ip: "172.16.10.0/24"  type: "snat"
       nat …  external ip: "10.10.52.2yy"  logical ip: "172.16.10.x"     type: "dnat_and_snat"
   admin@adm01:~$ ssh osctl01 sudo docker exec ovn_sb_db ovn-sbctl show
   Chassis "<chassis-osctl01>"  hostname: osctl01  Encap geneve ip: "10.10.51.51"
       Port_Binding cr-lrp-…       ← port de passerelle du routeur, lié à osctl01
   Chassis "<chassis-oscmp02>"  hostname: oscmp02  Encap geneve ip: "10.10.51.53"
       Port_Binding <ID-PORT-INSTANCE>
   ```
   (Les conteneurs des bases s'appellent `ovn_nb_db` et `ovn_sb_db` ; `ovn-nbctl` peut aussi s'exécuter dans `ovn_northd`.) Trajet aller d'un `ping` de `adm01` : VLAN 10 → bordure (route directe vers 10.10.52.0/24) → VLAN 52 → `ens21` de `osctl01` → `br-ex` → port `localnet` du commutateur `ext-net` → port de passerelle `cr-lrp` du routeur (sur `osctl01`) : **DNAT** 10.10.52.2yy → 172.16.10.x → commutateur du projet → tunnel Geneve sur le VLAN 51 (de 10.10.51.51 vers 10.10.51.53) → `oscmp02` → port de l'instance (groupe de sécurité : ICMP depuis 10.10.10.0/24 autorisé). Retour : instance → tunnel vers `osctl01` → routeur : **SNAT** 172.16.10.x → 10.10.52.2yy → VLAN 52 → bordure → `adm01`.
7. Documentation : [`docs/cloud/reseau-projets.md`](fichiers/M10-E08/medisphere/docs/cloud/reseau-projets.md).

**Explications**

- **`physnet1` et `br-ex`.** Neutron ne connaît que des noms de réseaux physiques ; chaque nœud dit à OVN à quel pont correspond chaque nom (`ovn-bridge-mappings`). Un réseau `flat` sur `physnet1` devient, dans OVN, un commutateur avec un port `localnet` : le trafic sort tel quel sur `br-ex`, donc sur `ens21`, donc sur le VLAN 52 (le marquage VLAN est fait par Proxmox, la carte étant sur le VNet `vosext`).
- **Passerelle centralisée.** Avec des IP flottantes centralisées, chaque routeur a un port de passerelle « redirigé » (`cr-lrp`) lié à un *chassis* passerelle ; toute la traduction d'adresses vers l'extérieur se fait là. Avec plusieurs passerelles, OVN choisit selon des priorités et bascule (BFD) ; ici, il n'y en a qu'une.
- **Groupes de sécurité.** Traduits par OVN en ACL sur les ports logiques, appliquées par le `ovn-controller` du nœud qui porte le port (le calcul de l'instance), avec suivi de connexion : le retour est autorisé sans règle.

**Alternatives**

- **IP flottantes distribuées** (`neutron_ovn_distributed_fip: "yes"`) : la traduction se fait sur le calcul de l'instance, le trafic Nord-Sud ne passe plus par `osctl01` ; il faut alors une carte sur le VLAN 52 **sur chaque calcul**.
- **Réseau fournisseur VLAN** partagé (`provider:network_type vlan`) pour brancher des instances directement sur un VLAN du lab : pas de NAT, pas d'IP flottante, mais le projet dépend du plan d'adressage du lab.
- **Annoncer les IP flottantes en BGP** (`ovn-bgp-agent`) vers la bordure FRR (M07) plutôt qu'un réseau plat : la voie des grands déploiements.

**Pièges classiques**

- Routeur sans passerelle externe : l'association d'IP flottante échoue (« External network … is not reachable from subnet … »).
- Plage d'allocation qui inclut 10.10.52.1-3 : Neutron donnerait un jour l'adresse de la bordure à un routeur.
- `ens21` filtrée par le pare-feu Proxmox (MAC) ou sans lien (`DOWN`) : l'IP flottante ne répond pas, alors que tout est vert côté API.
- Oublier que `ping` exige une règle ICMP **et** que SSH exige sa propre règle ; ou ouvrir depuis 10.10.10.10/32 et tester depuis le VPN (10.255.1.0/24).
- Chercher un espace de noms `qrouter-…` comme dans les tutoriels ML2/OVS : avec OVN, il n'y en a pas (seulement `ovnmeta-…` sur les calculs, pour les métadonnées).
- Supprimer l'instance avant de dissocier l'IP flottante : l'adresse reste allouée au projet (et comptée dans son quota) jusqu'à `floating ip delete`.

**En production chez MédiSphère**

Plusieurs nœuds passerelles (au moins deux, avec priorités et BFD), ou IP flottantes distribuées ; un réseau externe routé et annoncé en BGP plutôt qu'un VLAN plat ; des groupes de sécurité standard fournis aux équipes (« administration depuis le VPN », « HTTP public ») ; la politique de flux du réseau externe dans la matrice (E12) ; supervision des IP flottantes depuis l'extérieur et des agents OVN (E26).

---

### M10-E09 — Questions : architecture d'OpenStack

**Barème** : 2 points par question, total sur 30. En dessous de 15, refais le parcours d'`essai01` (E07) en lisant les journaux, avant d'aborder le palier 2.

**1. Trajet d'un `server create`.** `adm01` → HTTPS → HAProxy (VIP externe) → **Keystone** (jeton, catalogue) ; puis HTTPS → HAProxy → **`nova-api`** : vérifie les quotas, le gabarit, l'image (appel HTTP à **Glance**), le réseau (appel à **Neutron**), écrit l'instance en base (état `BUILD`) et renvoie la réponse. Par **RabbitMQ**, `nova-api` passe la demande à **`nova-conductor`**, qui appelle **`nova-scheduler`** (RabbitMQ) ; l'ordonnanceur interroge **Placement** (HTTP : « fournisseurs de ressources avec VCPU=1, MEMORY_MB=1024, DISK_GB=10 »), filtre, pondère, **réserve** l'allocation dans Placement et rend un hôte. Le conducteur envoie la construction à `nova-compute` de l'hôte (RabbitMQ). `nova-compute` télécharge l'image (Glance, HTTP, par la VIP interne), demande à **Neutron** de créer et lier le port (Neutron écrit dans la base OVN *Northbound*, `ovn-northd` compile, `ovn-controller` du calcul installe les flux), génère le XML et démarre le domaine **libvirt**, puis attend l'événement « réseau prêt » que Neutron envoie à Nova (HTTP, API externe de Nova). État `ACTIVE`. Placement intervient au choix et à la réservation ; Neutron, à la validation (`nova-api`) et à la construction (`nova-compute`).

**2. Le conducteur.** `nova-compute` tourne sur les hyperviseurs, les machines les plus exposées (elles exécutent du code des clients). S'il avait les identifiants de la base, la compromission d'un seul hyperviseur donnerait l'écriture sur **toute** la base de Nova (toutes les instances de tous les projets). `nova-conductor` fait les accès base à sa place, par RPC sur RabbitMQ, et peut contrôler ce qu'on lui demande. Accessoirement, il porte les longues orchestrations (construction, migration, redimensionnement).

**3. Réponse B.** Dans ce déploiement, `public` pointe vers la VIP externe en HTTPS (`https://openstack.par1.medisphere.internal:…`), `internal` vers la VIP interne en HTTP (`http://openstack-int.par1.medisphere.internal:…`) ; l'interface `admin` n'est plus utilisée par la plupart des services (Keystone v3 n'a plus de port d'administration séparé) et Kolla ne l'enregistre plus pour beaucoup d'entre eux. A est faux (URL différentes, protocoles différents) ; C est faux (les services se parlent par les points `internal`, en passant par Keystone pour valider les jetons) ; D est faux : tout passe par HAProxy, c'est ce qui permettra d'ajouter des contrôleurs.

**4. IP flottante muette.** Du plus probable au moins probable :
- (a) **groupe de sécurité** : pas de règle ICMP/SSH depuis la source testée → `openstack server show essai01 -c security_groups` et `security group rule list` ;
- (b) **IP flottante non associée** ou associée à un autre port → `openstack floating ip list --long` (colonne « Fixed IP Address », « Port ») ;
- (c) **routeur** sans passerelle externe ou sans interface sur le sous-réseau → `openstack router show` (`external_gateway_info`, `interfaces_info`) ;
- (d) **instance** démarrée sans réseau configuré (cloud-init, DHCP, MTU) → `openstack console log show` ;
- (e) **passerelle OVN** : `ovn-controller` arrêté sur `osctl01`, `br-ex` sans `ens21`, `ens21` `DOWN` ou filtrée → `openstack network agent list`, `ovs-vsctl list-ports br-ex`, `ip link show ens21`, `ovn-sbctl show` (le `cr-lrp` est-il lié à un *chassis* ?) ;
- (f) **bordure** : route ou règle vers le VLAN 52 → `traceroute` depuis `adm01`, `tcpdump -ni ens19.52` sur la passerelle maîtresse.

**5. Redémarrage de `osctl01`.** **API** : tout s'arrête (HAProxy, Keystone, Nova, Neutron, bases, RabbitMQ sont tous sur lui) — plus aucune création, suppression ni consultation. **Instances sans IP flottante** : elles **continuent de tourner** (les domaines libvirt vivent sur les calculs) et de se parler entre elles sur le même réseau (flux OVN déjà installés sur les calculs, tunnels directs entre calculs) ; ce qui passe par le routeur vers l'extérieur (SNAT, sur la passerelle `osctl01`) s'arrête ; le DHCP, lui, continue : OVN le rend localement, par `ovn-controller` du calcul. **Instances avec IP flottante** : injoignables de l'extérieur (DNAT sur `osctl01`). La différence vient de la séparation **plan de contrôle** (tout sur `osctl01`) / **plan de données** (calculs, plus la passerelle pour le Nord-Sud).

**6. Réponse B.** OVN implémente le DHCP en **flux logiques** : `ovn-controller` du nœud qui porte le port de l'instance répond lui-même aux requêtes DHCP (options venues de la base *Northbound*, alimentée par Neutron). A décrit l'architecture ML2/OVS (et le `neutron_ovn_dhcp_agent` n'existe que pour des cas particuliers, désactivé par défaut) ; C sert les métadonnées (HTTP 169.254.169.254), pas le DHCP ; D est hors du cloud.

**7. HAProxy et keepalived sur un seul contrôleur.** (a) Les **adresses** des points d'accès sont des VIP, indépendantes des machines : passer à trois contrôleurs ne changera rien pour les clients, les catalogues, les certificats ; (b) HAProxy apporte la **terminaison TLS** externe, les contrôles de santé, des limites et des journaux uniformes devant des services hétérogènes ; (c) c'est le seul modèle testé par Kolla : un déploiement sans eux serait un cas particulier.

**8. Configuration générée.** Le dépôt contient les **entrées** : `globals.yml`, `passwords.yml`, l'inventaire, les surcharges `etc/kolla/config/`. Au `deploy`/`reconfigure`, Kolla-Ansible **génère** pour chaque service les fichiers complets (modèles du rôle + surcharges fusionnées) et les dépose dans `/etc/kolla/<service>/` sur les nœuds concernés, avec `config.json` ; au démarrage du conteneur, `kolla_start` copie ces fichiers à leur place dans le conteneur. Une modification à la main sur le nœud agit au prochain redémarrage du conteneur et disparaît au prochain `reconfigure` (ou survit, si elle vient du dépôt) : c'est une **dérive**, que le palier 4 transforme en panne.

**9. Réponse B.** Les mots de passe de `passwords.yml` sont **inscrits** dans les bases (comptes MariaDB), RabbitMQ, Keystone (comptes de service). Un nouveau fichier (`kolla-genpwd` en tire de nouveaux, aléatoires) ferait écrire de nouveaux mots de passe dans la configuration des services, sans les changer là où ils sont vérifiés : tous les services échoueraient à s'authentifier. A est faux (aléatoire, donc différent) ; C est faux (Kolla ne relit pas les conteneurs) ; D est faux (tout est concerné). Récupération : relire les valeurs dans `/etc/kolla/<service>/*.conf` des nœuds pour reconstituer le fichier… d'où l'intérêt de le versionner chiffré.

**10. Étiquettes d'images.** Kolla publie des étiquettes **mobiles** par série et distribution (`2026.1-debian-trixie`), reconstruites régulièrement (correctifs de sécurité de Debian et d'OpenStack) : un déploiement suit les correctifs de la série sans changer sa configuration. Le revers : deux `pull` à deux dates différentes ne donnent pas les mêmes images ; un nœud ajouté dans trois mois n'aura pas le même code que les autres. On le maîtrise en relevant les **empreintes** (`docker images --digests`) à chaque déploiement, en épinglant par empreinte ou par une étiquette datée, ou par un registre interne qui ne se met à jour que sur décision (E28, module 13).

**11. Stockages locaux.** (a) **Migration à chaud** : le disque local d'une instance doit être copié en même temps que la mémoire (*block migration*) : lent, fragile ; (b) **survie à la perte d'un calcul** : le disque disparaît avec lui, pas d'évacuation possible ; (c) **volumes persistants** et **sauvegardes** : pas de Cinder ; (d) une image publiée dépend du disque de `osctl01` (pas de redondance, et le disque se remplit). Ceph (E10) rétablit tout cela : Glance, Nova et Cinder sur `ceph-par1`, Cinder et cinder-backup.

**12. 403 pour `julien.petit`.** Keystone a authentifié Julien et émis un jeton limité à `mediagenda-prod` avec le rôle `reader`. La requête arrive à **Neutron** ; c'est **le moteur de politiques de Neutron** (oslo.policy) qui évalue la règle `create_security_group` contre le contexte du jeton (rôles, projet, portée) et refuse : `reader` ne crée rien. Keystone ne décide pas des droits d'un autre service : chaque service applique ses propres politiques, d'où 403 (authentifié, non autorisé) et pas 401.

**13. `admin` sur `admin`.** Le rôle `admin`, dans les politiques d'OpenStack, donne l'administration du **service** (et, pour beaucoup de règles, de tout le cloud), quel que soit le projet sur lequel il a été attribué : un `admin` sur `mediagenda-dev` peut lister et supprimer les instances de tous les projets, créer des réseaux fournisseurs, lire les hyperviseurs. `admin` sur le projet `admin` est la forme habituelle du super-administrateur. Donner l'un ou l'autre à une équipe de développement, c'est lui donner la plateforme. Ce qu'il faut : `member` sur ses projets, et des capacités précises via des rôles dédiés et des politiques ajustées (E23).

**14. Une seule passerelle.** Tout le trafic Nord-Sud (IP flottantes, SNAT) de tous les projets passe par `osctl01` : sa carte et son CPU bornent le débit de tout le cloud vers l'extérieur ; son redémarrage coupe toutes les IP flottantes. Pour s'en affranchir : plusieurs nœuds dans le groupe `network` (OVN répartit les ports de passerelle et bascule), ou des IP flottantes distribuées avec une patte sur le réseau externe sur chaque calcul, ou une annonce BGP des IP flottantes depuis les calculs.

**15. Réponse B.** Le paquet de 1442 octets devient, une fois encapsulé (Ethernet interne 14 + Geneve et options + UDP 8 + IP 20), un paquet d'environ 1500 octets sur le VLAN 51, dont la MTU est 9000 : il passe sans fragmentation, directement du calcul source au calcul destination. A est faux (`ovn-controller` ne fragmente pas, et rien n'y oblige) ; C est faux (9000 est un **maximum**) ; D est faux : le trafic Est-Ouest entre deux instances d'un même réseau ne passe pas par la passerelle.
