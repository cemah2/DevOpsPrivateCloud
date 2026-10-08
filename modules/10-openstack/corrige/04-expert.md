# Module 10 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif. Dans ce palier, « j'ai relancé le conteneur et ça remarche » est presque toujours faux : une relance efface la preuve (état chargé, valeur posée à chaud) sans corriger la cause, et le prochain `kolla-ansible reconfigure` (ou le prochain redémarrage du nœud) la défait ou la ramène.

Les scripts d'injection sont dans `corrige/pannes/` (`_m10-commun.sh` contient les fonctions partagées : modifications de fichiers de `/etc/kolla/` mémorisées et réversibles sans écraser une réparation, arrêt et relance de conteneurs, piles de test `m10-eXX-*` dans le projet `plateforme`, commandes Ceph par `ceph01`). Chaque modification est journalisée sur l'hôte touché dans `/var/lib/workbook/pannes.log` (copies d'origine dans `/var/lib/workbook/M10-EXX.*`), et sur `adm01` dans `~/.local/state/workbook/M10-EXX/`.

Les sorties reproduites sont **représentatives** : identifiants, horodatages, empreintes et formulations exactes varient selon les versions. Elles suivent la documentation et le code de Kolla-Ansible 22 (`stable/2026.1`), de Nova, Neutron/OVN, Cinder, Glance et Keystone 2026.1, et de Ceph Tentacle 20.2.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) :
- comportement de Placement quand un inventaire est mis à jour sous l'usage déjà alloué (E35 v2) : la mise à jour est acceptée et le fournisseur est « au-delà de sa capacité » (avertissement dans le journal de Placement) ; seules les nouvelles allocations sont refusées ;
- réaction de Neutron (événements de *chassis*) quand `ovn-bridge-mappings` de l'unique passerelle perd `physnet1` (E36 v2) : selon la version, la passerelle du routeur reste programmée mais inopérante, ou Neutron la retire (aucun *chassis* candidat) puis la reprogramme quand la correspondance revient ;
- message exact de `cloud-init` 25.1 quand les métadonnées répondent 403, 502/503 ou pas du tout, et repli sur la source `None` (E37) ;
- comportement de `cinder-volume` quand son pilote RBD ne joint aucun moniteur au démarrage (E38 v3) : service `up` avec pilote non initialisé, ou `down`, selon l'instant ;
- code HTTP exact renvoyé par Keystone (500) ou par HAProxy (503) pour E39 v1 et v2 selon que Keystone démarre ou reste bloqué sur sa base ;
- comportement de RBD quand le pool atteint son quota (E41 v2) : écritures suspendues jusqu'à la levée du quota, ou refusées avec `EDQUOT` selon le client ;
- effet d'un redémarrage du conteneur `nova_libvirt` sur les instances en cours (E38 v1) : la doc de Kolla le permet (`pid_mode: host`), mais ne le fais pas sans avoir lu la note de ta version ;
- présence de l'outil `rbd` dans les images Kolla `glance-api` et `cinder-volume` (sinon, teste depuis `ceph01`).

---

## Méthode commune aux pannes OpenStack

1. **Trouver l'identifiant de requête.** `openstack server event list <instance>` (puis `event show`) pour Nova, `--debug` sur la CLI pour tout le reste (en-tête `x-openstack-request-id`). Puis `sudo grep -h <req-id> /var/log/kolla/<service>/*.log` sur le bon nœud. Les services appelés par Nova (Neutron, Placement, Cinder, Glance) journalisent l'identifiant **global** de Nova à côté du leur.
2. **Lire l'état déclaré, puis l'état réel.** `compute service list`, `network agent list`, `volume service list` ; puis `sudo docker ps -a --filter health=unhealthy`, `docker ps -a` (conteneurs arrêtés), journaux. Un écart entre les deux est déjà un diagnostic.
3. **Séparer les étages.** Client et TLS (`curl -v`, `openssl s_client`) → VIP et HAProxy → API → base et RabbitMQ → agent sur le nœud → dépendance externe (Ceph, libvirt, Open vSwitch). Tester un étage **sans** les autres : `rbd --id cinder`, `ovs-vsctl`, `virsh`, `rabbitmqctl`, `curl` local.
4. **Chercher ce qui a bougé.** Dates (`ls -l --time-style=full-iso /etc/kolla/<service>/`), `docker inspect -f '{{.State.StartedAt}} {{.State.FinishedAt}}'`, `journalctl -u docker` et `docker events --since …`, journal d'audit de Ceph (`ceph log last 200 info audit`), journaux d'API (qui a fait quel `PUT`/`PATCH`, avec quel compte). Et surtout la **différence avec le code** : `kolla-ansible genconfig` dans un dossier temporaire (`--configdir` vers une copie), ou la relecture de ce qu'un `reconfigure` changerait.
5. **Corriger à la source, puis faire converger.** Valeur d'API : par l'API (et, si elle est gérée par OpenTofu ou un pipeline, par le code). Fichier de `/etc/kolla/` : par le dépôt `plateforme/openstack` et `kolla-ansible reconfigure -t <service>`. État Ceph : par les commandes Ceph **et** les spécifications versionnées de `plateforme/ceph`. État vivant non représenté dans un fichier (secret chargé dans libvirt, conteneur arrêté, règle `nft` posée à chaud) : action ciblée, puis prévention (sonde, garde-fou).
6. **Prouver le retour par le chemin de l'utilisateur**, pas seulement par l'étage réparé : une instance créée, une IP flottante qui répond, un volume attaché, une connexion Horizon.
7. **Prévenir** : quelle sonde de `ms-verif-openstack` (M10-E26), quel contrôle de dérive, quelle politique d'accès aurait vu ou empêché la panne ?

Pour lancer Kolla-Ansible depuis `adm01`, les exemples ci-dessous abrègent ta commande de M10-E03/E20 en :

```
admin@adm01:~/src/openstack$ uv run kolla-ansible reconfigure -i inventaire/multinode --configdir etc/kolla -t <tag>
```

(l'identité Vault `critique`, qui déchiffre `passwords.yml`, vient de l'`ansible.cfg` du projet, M10-E03). Les étiquettes (*tags*) utiles : `nova`, `neutron`, `openvswitch`, `ovn-controller`, `keystone`, `glance`, `cinder`, `horizon`, `loadbalancer`, `memcached`. Avant de lancer, regarde ce qui changerait : `git diff` du dépôt, et au besoin `kolla-ansible genconfig` vers une copie de la configuration pour comparer avec `/etc/kolla/` des nœuds.

---

### M10-E35 — Panne : « No valid host was found »

**Démarche de diagnostic**

*Symptôme* : toute création finit en `ERROR` avec `fault.message` = « No valid host was found. » (parfois suivi de « There are not enough hosts available. »).

*Hypothèses* : capacité (inventaire, ratios, réservations) ; services de calcul désactivés ou `down` ; exigence impossible du gabarit (trait, propriété) ou de l'image (architecture, type d'hyperviseur) ; zone de disponibilité ou agrégat ; quota (non : un quota donne une erreur 403 **avant** la planification, pas un « No valid host »).

**Étape 1 — Reproduire et récupérer l'identifiant.**

```
admin@adm01:~$ export OS_CLOUD=medisphere-plateforme
admin@adm01:~$ openstack server create --flavor m1.petit --image debian-13 --no-network --wait essai-e35
Error creating server: essai-e35
admin@adm01:~$ openstack server show essai-e35 -c status -c fault -f yaml
fault:
  code: 500
  created: '2026-10-14T06:58:12Z'
  message: No valid host was found.
status: ERROR
admin@adm01:~$ openstack server event list essai-e35
| Request ID                               | Server ID | Action | Start Time |
| req-7c1e9a4b-2f0d-4f7e-9d5a-0c8e3b1f2a66 | 5b0e…     | create | …          |
```

**Étape 2 — Le plan de contrôle : avant ou dans les filtres ?**

```
root@osctl01:~# grep -h req-7c1e9a4b /var/log/kolla/nova/nova-scheduler.log /var/log/kolla/nova/nova-conductor.log
```

Deux familles de messages :
- `Got no allocation candidates from the Placement API. This could be due to insufficient resources or a temporary occurrence as compute nodes start up.` → Placement n'a proposé **aucun** fournisseur : capacité, trait exigé ou trait interdit ;
- `Filtering removed all hosts for the request with instance ID '…'. Filter results: ['ComputeFilter: (start: 2, end: 2)', 'ImagePropertiesFilter: (start: 2, end: 0)']` → Placement a proposé des hôtes, un **filtre** les a tous éliminés (le détail par filtre s'affiche ainsi en `INFO` ; le nom de chaque hôte éliminé n'apparaît qu'en `debug`).

Le conducteur, lui, écrit `NoValidHost` et met l'instance en `ERROR` (`Failed to schedule instances`).

**Étape 3 — Interroger l'étage désigné.**

```
admin@adm01:~$ export OS_CLOUD=medisphere-admin           # greffon osc-placement installé en M10-E13
admin@adm01:~$ openstack compute service list --service nova-compute --long
admin@adm01:~$ openstack resource provider list
admin@adm01:~$ openstack resource provider inventory list <UUID-OSCMP01>
admin@adm01:~$ openstack resource provider usage show <UUID-OSCMP01>
admin@adm01:~$ openstack --os-placement-api-version 1.6 resource provider trait list <UUID-OSCMP01>
admin@adm01:~$ openstack flavor show m1.petit -c properties
admin@adm01:~$ openstack image show debian-13 -c properties
admin@adm01:~$ openstack --os-placement-api-version 1.17 allocation candidate list --resource VCPU=1 --resource MEMORY_MB=1024 --resource DISK_GB=10
```

(`<UUID-OSCMP01>` : identifiant du fournisseur de ressources de `oscmp01`, donné par `resource provider list`. Les numéros de micro-version sont ceux qui exposent les traits et les traits exigés ; `--os-placement-api-version latest` convient aussi.)

**Variante 1 — calculs désactivés.**

```
admin@adm01:~$ openstack compute service list --service nova-compute --long -c Host -c Status -c State -c "Disabled Reason"
| Host    | Status   | State | Disabled Reason           |
| oscmp01 | disabled | up    | maintenance noyau CHG-1172 |
| oscmp02 | disabled | up    | maintenance noyau CHG-1172 |
```

Le journal du scheduler dit « Got no allocation candidates » : depuis la version Train, un `nova-compute` désactivé pose sur son fournisseur le trait `COMPUTE_STATUS_DISABLED`, et le scheduler demande à Placement des candidats **sans** ce trait (pré-filtre toujours actif). `resource provider trait list` le montre. Cause racine : une maintenance (CHG-1172) close sans réactiver les calculs. Correctif :

```
admin@adm01:~$ openstack compute service set --enable oscmp01 nova-compute
admin@adm01:~$ openstack compute service set --enable oscmp02 nova-compute
```

Prévention : la procédure de maintenance (RB-102, M10-E19/E29) se termine par la réactivation **et** une instance de test ; `ms-verif-openstack` alerte sur un `nova-compute` désactivé depuis plus de N heures (la raison et la date sont dans `compute service list --long`).

**Variante 2 — mémoire réservée par la configuration.**

```
admin@adm01:~$ openstack resource provider inventory list <UUID-OSCMP01>
| resource_class | allocation_ratio | min_unit | max_unit | reserved | step_size | total |
| VCPU           |              4.0 |        1 |        4 |        0 |         1 |     4 |
| MEMORY_MB      |              1.0 |        1 |     7940 |     7680 |         1 |  7940 |
| DISK_GB        |              1.0 |        1 |      … |        0 |         1 |    … |
```

Capacité mémoire = (`total` − `reserved`) × `allocation_ratio` = 260 Mio : aucun gabarit n'y entre. D'où vient `reserved` ? Du `nova.conf` de `nova_compute` :

```
root@oscmp01:~# grep -n reserved_host_memory_mb /etc/kolla/nova-compute/nova.conf
3:reserved_host_memory_mb = 7680
root@oscmp01:~# ls -l --time-style=full-iso /etc/kolla/nova-compute/nova.conf
admin@adm01:~/src/openstack$ grep -rn reserved_host_memory etc/kolla/config/
etc/kolla/config/nova/nova-compute.conf:…:reserved_host_memory_mb = 2048
```

Ton dépôt dit 2048 (M10-E20), le fichier généré dit 7680 : modification à la main sur les deux calculs, suivie d'un redémarrage de `nova_compute` (qui a renvoyé le nouvel inventaire à Placement). Correctif durable : `kolla-ansible reconfigure -t nova` régénère le fichier depuis le dépôt et relance `nova_compute` (vérifie ensuite `inventory list`). Si la valeur **venait** de ton dépôt (`etc/kolla/config/nova.conf` ou `nova/nova-compute.conf`), le `reconfigure` l'aurait reposée : c'est là qu'il faut corriger. Remarque : Kolla ne pose pas `reserved_host_memory_mb` (valeur par défaut de Nova : 512 Mio) ; la valeur de 2 048 Mio décidée en M10-E13 et posée en M10-E20 est celle du dépôt, donc celle que le `reconfigure` rétablit.

**Variante 3 — image avec une architecture impossible.**

Journal du scheduler : `Filter results: […, 'ImagePropertiesFilter: (start: 2, end: 0)']`. L'image porte `hw_architecture='aarch64'` ; les calculs sont `x86_64`. Qui ? Le journal de `glance-api` contient la requête `PATCH /v2/images/<id>` avec le compte qui l'a faite :

```
root@osctl01:~# grep -h 'PATCH /v2/images' /var/log/kolla/glance/glance-api.log | tail -n 3
admin@adm01:~$ openstack image unset --property hw_architecture debian-13
```

(ou `image set --property hw_architecture=x86_64` si ta convention de M10-E06 la pose explicitement). Prévention : les propriétés des images publiques sont fixées par le code qui les publie (M10-E06) et vérifiées par une sonde ; les **protections de propriétés** de Glance (`glance_enable_property_protection` dans Kolla, fichier de règles) réservent la modification des propriétés `hw_*` aux administrateurs. Note : si `[scheduler] image_metadata_prefilter` est activé (ce n'est pas le défaut), l'architecture devient un trait exigé et le symptôme passe à « Got no allocation candidates ».

**Variante 4 — trait exigé par le gabarit.**

`openstack flavor show m1.petit -c properties` montre `trait:HW_GPU_API_VULKAN='required'`. `allocation candidate list --resource … --required HW_GPU_API_VULKAN` est vide : aucun calcul n'expose ce trait (Nova le publie seulement si l'hyperviseur a un GPU virtuel adapté). Correctif : `openstack flavor unset --property trait:HW_GPU_API_VULKAN m1.petit`. Qui ? Journal de `nova-api` (`PUT …/os-extra_specs` ou `POST …/os-extra_specs`). Prévention : les gabarits sont gérés par le code (`playbooks/catalogue.yml` de M10-E07, rejoué régulièrement en mode `--check --diff` pour voir la dérive ; avec OpenTofu, `openstack_compute_flavor_v2` et ses `extra_specs` rendraient la dérive visible au plan nocturne) ; un gabarit « GPU » s'appelle autrement et se réserve par un agrégat.

**Vérification** : instance `m1.petit` Debian 13 `ACTIVE` dans `mediagenda-dev`, supprimée ensuite ; `lab/bin/check 10 35` ; puis `lab/bin/break 10 35 --annuler` pour clore.

**Explications**

La planification se fait en deux temps. D'abord Nova traduit la demande (gabarit, image, options) en **ressources** (VCPU, MEMORY_MB, DISK_GB), **traits** exigés ou interdits et **agrégats**, et demande à Placement des « candidats d'allocation » ; Placement répond par une requête SQL sur les inventaires, usages et traits. Ensuite, les **filtres** de Nova éliminent les hôtes qui ne conviennent pas pour des raisons que Placement ne modélise pas (propriétés d'image, affinités, etc.), les **poids** classent les survivants, et le scheduler **réclame** les ressources de l'hôte choisi dans Placement (allocation) avant de passer la main au conducteur. « No valid host » est la conclusion commune de tout échec, à n'importe laquelle de ces étapes : le message ne dit rien de la cause, le journal du scheduler dit tout.

**Alternatives**
- `openstack --os-compute-api-version 2.74 server create … --host <hôte>` (administrateur) : force un hôte, utile pour tester un calcul précis, sans contourner Placement.
- Agrégats et `[scheduler] limit_tenants_to_placement_aggregate` pour réserver des calculs à un projet : un mauvais réglage produit aussi « No valid host » pour les autres projets.

**Pièges classiques**
- Chercher dans `nova-compute.log` : la requête n'est jamais arrivée sur un calcul.
- Réactiver un service ou retirer une propriété sans chercher **qui** l'avait posée : la cause revient (procédure, pipeline, collègue).
- Croire que `ram_allocation_ratio` du fichier fait foi : la valeur effective est dans l'inventaire de Placement (et `initial_*_allocation_ratio` ne s'applique qu'à la création du fournisseur).
- Oublier qu'un quota dépassé donne un 403 explicite, pas un « No valid host ».

**En production chez MédiSphère**
Une sonde de planifiabilité (`allocation candidate list` pour chaque gabarit standard) et une alerte sur le nombre d'hôtes candidats ; gabarits, propriétés d'images et réservations sous code avec détection de dérive ; RB-103 (M10-E43) en première page pour le support.

---

### M10-E36 — Panne : l'IP flottante ne répond pas

**Démarche de diagnostic**

*Symptôme* : l'instance de test est `ACTIVE`, sa console montre un système démarré, mais son IP flottante ne répond ni au ping ni en SSH depuis `adm01`.

*Hypothèses*, dans l'ordre du chemin (de l'instance vers l'extérieur) : filtrage du port (groupe de sécurité) ; adresse privée ou route de l'instance ; routeur logique (passerelle, NAT) ; liaison de la passerelle au *chassis* ; réseau physique sur la passerelle (correspondance `physnet1` → pont, interface dans le pont, lien de l'interface) ; bordure et VLAN 52.

**Étape 1 — L'API dit-elle quelque chose ?**

```
admin@adm01:~$ export OS_CLOUD=medisphere-plateforme
admin@adm01:~$ openstack server show m10-e36-sonde -c status -c addresses
admin@adm01:~$ openstack port show m10-e36-port -c status -c binding_host_id -c security_group_ids -c fixed_ips
admin@adm01:~$ openstack floating ip list --port m10-e36-port
admin@adm01:~$ openstack router show m10-e36-routeur -c status -c admin_state_up -c external_gateway_info
admin@adm01:~$ openstack security group rule list <GROUPE-DU-PORT>
```

**Étape 2 — L'instance vue de l'intérieur.** `openstack console log show m10-e36-sonde | tail -n 40` (adresse privée obtenue par le DHCP natif d'OVN, `cloud-init` terminé) ; au besoin, la console graphique d'Horizon pour un `ping 172.30.36.1` (passerelle du routeur).

**Étape 3 — Capturer sur la passerelle.**

```
admin@osctl01:~$ sudo docker exec openvswitch_vswitchd ovs-vsctl get open . external_ids:ovn-bridge-mappings
"physnet1:br-ex"
admin@osctl01:~$ sudo docker exec openvswitch_vswitchd ovs-vsctl list-ports br-ex
ens21
patch-provnet-…-to-br-int
admin@osctl01:~$ sudo tcpdump -eni ens21 'icmp or arp' -c 10          # pendant un ping depuis adm01
```

Lecture : la bordure (`gw01`/`gw02`, directement connectées au VLAN 52) demande en ARP qui a l'IP flottante ; la passerelle OVN répond avec l'adresse MAC du port de passerelle du routeur ; puis l'écho ICMP entre, est traduit (DNAT) et part dans le tunnel Geneve vers le calcul (`sudo tcpdump -ni <interface OS-TUN> udp port 6081` sur `osctl01` et sur le calcul de l'instance).

**Variante 1 — groupe de sécurité « durci ».** Les ARP reçoivent une réponse, l'écho entre et part dans le tunnel, rien ne revient. Côté API : le port n'est plus dans `m10-e36-sg` mais dans `m10-e36-durci`, qui n'a que les règles de sortie par défaut.

```
admin@adm01:~$ openstack port show m10-e36-port -c security_group_ids
admin@adm01:~$ openstack security group rule list m10-e36-durci
| … | Direction | Ethertype | IP Range  | Port Range |
| … | egress    | IPv4      | 0.0.0.0/0 |            |
| … | egress    | IPv6      | ::/0      |            |
root@osctl01:~# grep -h 'PUT /v2.0/ports/' /var/log/kolla/neutron/neutron-server.log | tail -n 3
```

Côté OVN, la règle manquante se voit aussi : `docker exec ovn_northd ovn-nbctl acl-list pg_<id du groupe>` (groupes de ports). Correctif : `openstack port set --no-security-group --security-group m10-e36-sg m10-e36-port` (les deux options ensemble remplacent la liste). Prévention : les groupes de sécurité des projets sont décrits dans le code du projet (OpenTofu, M10-E31) ; un « durcissement » passe par une MR.

**Variante 2 — `physnet1` n'est plus relié au pont.**

```
admin@osctl01:~$ sudo docker exec openvswitch_vswitchd ovs-vsctl get open . external_ids:ovn-bridge-mappings
"physnet-ext:br-ex"
admin@osctl01:~$ sudo docker exec openvswitch_vswitchd ovs-vsctl list-ports br-ex
ens21
```

Le port *patch* entre `br-int` et `br-ex` a disparu : `ovn-controller` ne crée ce patch que pour les réseaux physiques de ses correspondances, et `ext-net` est sur `physnet1`. Sur `ens21`, les ARP de la bordure restent sans réponse. Selon la version, `ovn-nbctl lrp-get-gateway-chassis lrp-<id>` montre encore `osctl01` (inopérant) ou plus rien (Neutron ne trouve plus de *chassis* candidat portant `physnet1`). Correctif à chaud, puis durable :

```
admin@osctl01:~$ sudo docker exec openvswitch_vswitchd ovs-vsctl set open . external_ids:ovn-bridge-mappings='"physnet1:br-ex"'
admin@adm01:~/src/openstack$ uv run kolla-ansible reconfigure -i inventaire/multinode --configdir etc/kolla -t ovn-controller
```

Le rôle `ovn-controller` de Kolla repose `ovn-bridge-mappings` (tâche « Configure OVN in OVSDB », calculée depuis `neutron_physical_networks` et `neutron_bridge_name`) : un `reconfigure` aurait réparé, et un passage nocturne en mode vérification (`kolla-ansible … --check` n'est pas une garantie ; préfère une sonde) l'aurait signalé. Vérifie ensuite que la passerelle est bien liée : `ovn-sbctl show` (`Port_Binding cr-lrp-…` sur `osctl01`).

**Variante 3 — l'interface externe n'est plus dans le pont.** `ovs-vsctl list-ports br-ex` ne montre plus que le port *patch* ; sur `ens21`, les ARP de la bordure arrivent mais personne ne les voit côté OVS. Correctif : `sudo docker exec openvswitch_vswitchd ovs-vsctl --may-exist add-port br-ex ens21`, puis `kolla-ansible reconfigure -t openvswitch` (le rôle `openvswitch` ajoute `neutron_external_interface` au pont `neutron_bridge_name` à chaque déploiement : il aurait réparé).

**Variante 4 — l'interface externe est DOWN.**

```
admin@osctl01:~$ ip -br link show ens21
ens21            DOWN           bc:24:11:…
```

`tcpdump` sur l'interface ne capture rien (une interface administrativement DOWN ne reçoit plus de trames) ; `ovs-vsctl list-ports br-ex` la montre toujours. Correctif : `sudo ip link set ens21 up`. Prévention : la configuration réseau persistante de l'hôte (netplan rendu pour systemd-networkd par le rôle `noeud_openstack`, M10-E02) déclare l'interface active sans adresse : un redémarrage du nœud l'aurait relevée, mais personne ne redémarre une passerelle pour « voir ». Une sonde sur l'état des liens des nœuds (`node_exporter` au M21) l'aurait vue tout de suite.

Note sur les noms : `ens21` est la carte OS-EXT de M10-E02 (`neutron_external_interface`, dans `inventaire/host_vars/osctl01.yml`, M10-E03) ; `br-ex` est le pont par défaut de Kolla (`neutron_bridge_name`).

**Vérification** : ping et SSH vers l'IP de test, `lab/bin/check 10 36` (avant `--annuler`), puis `lab/bin/break 10 36 --annuler`.

**Explications**

Avec ML2/OVN, il n'y a plus d'agent L3 ni d'espaces de noms `qrouter-` : un routeur Neutron est un **routeur logique** dans la base nord d'OVN, son port externe est un port de passerelle lié à un ou plusieurs *chassis* candidats (`enable-chassis-as-gw`, ici seulement `osctl01`), et les IP flottantes sont des règles NAT `dnat_and_snat`. `ovn-northd` traduit la base nord en flux logiques dans la base sud ; chaque `ovn-controller` les programme dans son Open vSwitch. Le lien entre le monde logique et le réseau physique est le port *localnet* du réseau `ext-net`, que `ovn-controller` relie au pont désigné par `ovn-bridge-mappings` : sans correspondance, pas de patch ; sans interface dans le pont, pas de sortie ; interface DOWN, pas de trame. Les variantes 2 à 4 coupent **tout** le trafic nord-sud du cloud, la variante 1 une seule instance.

**Alternatives**
- `ovn-trace` (dans `ovn_northd`) simule le trajet logique d'un paquet et nomme l'ACL ou la règle qui le jette, sans rien envoyer : idéal pour la variante 1.
- IP flottantes distribuées (`neutron_ovn_distributed_fip: true`) : le NAT se fait sur le calcul, qui doit alors avoir accès au VLAN 52 (pont externe sur chaque calcul) ; plus de point unique, plus de câblage.

**Pièges classiques**
- Supprimer et recréer l'IP flottante ou le routeur : la cause est ailleurs, et l'adresse change.
- Capturer sur `br-ex` plutôt que sur l'interface physique : on ne voit pas la même chose (interne à OVS).
- Corriger l'Open vSwitch d'un nœud avec une faute de frappe dans le nom d'interface : tu peux te couper de `osctl01` (d'où l'instantané et l'agent QEMU).

**En production chez MédiSphère**
Au moins deux *chassis* passerelles (priorités, BFD) pour que la perte d'un seul ne coupe pas le nord-sud ; une sonde par IP flottante témoin ; les groupes de sécurité sous code ; l'état des liens des nœuds supervisé.

---

### M10-E37 — Panne : l'instance ignore sa configuration

**Démarche de diagnostic**

*Symptôme* : nouvelle instance `ACTIVE`, ping OK, port 22 ouvert, clé refusée ; nom d'hôte par défaut ; user-data non exécutées. Les anciennes instances vont bien (elles ont reçu leurs métadonnées au premier démarrage).

*Hypothèses*, dans l'ordre du chemin : réseau de l'instance (route vers `169.254.169.254`) ; proxy local du calcul (espace de noms `ovnmeta-<réseau>`, *haproxy*) ; agent `neutron_ovn_metadata_agent` ; VIP interne et HAProxy (port 8775) ; `nova_metadata` ; secret partagé.

**Étape 1 — La console.**

```
admin@adm01:~$ openstack --os-cloud medisphere-plateforme console log show m10-e37-sonde | grep -iE 'cloud-init|datasource|169.254|metadata' | head -n 20
… url_helper.py[WARNING]: Calling 'http://169.254.169.254/openstack' failed [0/-1s]: bad status code [503]
… DataSourceOpenStack… : Could not find a valid metadata service …
… cloud-init … Datasource DataSourceNone.  Up …
```

Le code HTTP désigne l'étage : **403** (Nova refuse la requête : signature), **502/503** (le proxy local ou HAProxy n'a pas de serveur derrière), **délai dépassé** (rien ne répond dans l'espace de noms local). Le repli sur `DataSourceNone` explique tout le reste : pas de clé, pas de nom, pas de user-data.

**Étape 2 — Le calcul de l'instance.**

```
admin@adm01:~$ openstack --os-cloud medisphere-admin port show m10-e37-port -c binding_host_id
admin@oscmp01:~$ sudo docker ps -a --filter name=metadata --format '{{.Names}} {{.Status}}'
admin@oscmp01:~$ sudo ip netns list | grep ovnmeta
admin@oscmp01:~$ sudo tail -n 30 /var/log/kolla/neutron/neutron-ovn-metadata-agent.log
admin@osctl01:~$ sudo tail -n 30 /var/log/kolla/nova/nova-metadata.log
admin@adm01:~$ openstack --os-cloud medisphere-admin network agent list --agent-type ovn-metadata
```

(`--agent-type` accepte les types d'agents de ta version ; sans filtre, la colonne « Agent Type » suffit.)

**Variante 1 — agent de métadonnées arrêté sur les calculs.** `docker ps -a` montre `neutron_ovn_metadata_agent` en `Exited (0)` sur les deux calculs, et `network agent list` le marque mort après quelques dizaines de secondes. Le *haproxy* de l'espace de noms (lancé à part, comme conteneur « enveloppe », avec `neutron_agents_wrappers`) répond encore, mais transmet à la socket de l'agent, qui n'existe plus : 502/503. `docker inspect -f '{{.State.FinishedAt}}' neutron_ovn_metadata_agent` donne l'heure de l'arrêt, `journalctl -u docker --since …` l'ordre `stop`. Correctif : `sudo docker start neutron_ovn_metadata_agent` sur chaque calcul. Durable : rien n'a changé dans la configuration ; c'est une action d'exploitation. Prévention : sonde sur les agents morts (`network agent list`) et sur les conteneurs arrêtés ou `unhealthy`.

**Variante 2 — secret partagé divergent.**

```
admin@osctl01:~$ sudo grep -n 'X-Instance-ID-Signature\|Invalid proxy' /var/log/kolla/nova/nova-metadata.log | tail -n 2
… X-Instance-ID-Signature: … does not match the expected value: … for id: …
```

Nova recalcule le HMAC-SHA256 de l'identifiant d'instance avec **son** secret et le compare à celui que l'agent a calculé avec le sien : ils diffèrent, Nova répond 403 (« Invalid proxy request signature »). Compare **par empreinte** :

```
admin@osctl01:~$ sudo python3 -c "import configparser,hashlib;c=configparser.ConfigParser(interpolation=None,strict=False);c.read('/etc/kolla/nova-metadata/nova.conf');print(hashlib.sha256(c.get('neutron','metadata_proxy_shared_secret').encode()).hexdigest())"
admin@oscmp01:~$ sudo python3 -c "import configparser,hashlib;c=configparser.ConfigParser(interpolation=None,strict=False);c.read('/etc/kolla/neutron-ovn-metadata-agent/neutron_ovn_metadata_agent.ini');print(hashlib.sha256(c.defaults()['metadata_proxy_shared_secret'].encode()).hexdigest())"
```

Les deux valeurs viennent de la même variable de `passwords.yml` (`metadata_secret`) : un écart prouve une modification hors du code (fichier daté de la veille sur les calculs). Correctif durable : `kolla-ansible reconfigure -t neutron` régénère le fichier des agents et les relance. Note : le journal de Nova écrit les signatures en clair ; ce sont des HMAC, pas le secret, mais ne les recopie pas dans ton journal.

**Variante 3 — `nova_metadata` arrêté.** Sur `osctl01`, `docker ps -a` montre `nova_metadata` arrêté ; le journal de HAProxy dit `backend nova_metadata_back has no server available!` ; l'agent reçoit 503 et le renvoie à l'instance. Correctif : `sudo docker start nova_metadata`. Durable : action d'exploitation, comme la variante 1.

**Étape 4 — Appliquer la configuration sans recréer l'instance.** Un redémarrage suffit (`openstack server reboot m10-e37-sonde`, ou `--hard` si le système ne répond pas) : au premier démarrage, `cloud-init` s'est rabattu sur la source `None`, dont l'identifiant d'instance est fixe (`iid-datasource-none`) ; au démarrage suivant, il trouve la source OpenStack, dont l'identifiant (UUID de l'instance) est **différent** : il considère qu'il s'agit d'une nouvelle instance et rejoue les modules « par instance » (clés SSH, nom d'hôte, user-data). Si ta version mémorise autrement la source, `sudo cloud-init clean --reboot` depuis la console fait la même chose (à confirmer sur ton lab).

**Étape 5 — Config drive.** Avec `--use-config-drive`, Nova attache à l'instance un petit disque (ISO 9660) qui contient les métadonnées et les user-data : `cloud-init` les lit sans réseau, la panne n'aurait rien changé. Ce n'est pas un correctif : le service de métadonnées reste en panne pour toutes les autres instances, et le disque est figé à la création (pas de mise à jour, par exemple des interfaces ajoutées ensuite). MédiSphère ne l'impose pas par défaut parce que le service de métadonnées est la référence, supervisée ; le config drive est une option par instance (ou `force_config_drive` côté Nova) pour les cas sans DHCP ou sans route vers `169.254.169.254`.

**Explications**

Avec OVN, chaque nœud qui héberge des instances fait tourner l'agent de métadonnées ; pour chaque réseau qui a des ports sur ce nœud, il crée un espace de noms `ovnmeta-<réseau>` relié à `br-int`, avec l'adresse `169.254.169.254` et un *haproxy* qui ajoute les en-têtes `X-OVN-Network-ID` puis transmet à l'agent ; l'agent retrouve le port (et donc l'instance) à partir de l'adresse IP source et du réseau, puis interroge Nova avec `X-Instance-ID`, `X-Tenant-ID` et la signature `X-Instance-ID-Signature`. Nova vérifie la signature avec le secret partagé (`[neutron] metadata_proxy_shared_secret`) avant de répondre.

**Pièges classiques**
- Supprimer et recréer l'instance « pour voir » : la nouvelle a le même problème, et tu perds la console de la première.
- Coller les secrets de deux fichiers dans le journal pour les comparer.
- Régler la panne en forçant le config drive partout.

**En production chez MédiSphère**
Une instance témoin recréée chaque nuit qui prouve la chaîne complète (clé, nom, user-data), et des alertes sur les agents morts et les conteneurs arrêtés.

---

### M10-E38 — Panne : le volume ne s'attache pas

**Démarche de diagnostic**

*Symptôme* : `server add volume` répond sans erreur ; le volume passe `reserved` ou `attaching`, puis revient `available` ; aucun disque nouveau dans l'instance. Les volumes déjà attachés fonctionnent.

*Hypothèses* : préparation côté Cinder (`cinder-volume` n'arrive pas à joindre Ceph, pilote non initialisé) ; ouverture côté hyperviseur (QEMU n'arrive pas à s'authentifier ou n'a pas le droit d'ouvrir l'image) ; droits Ceph de `client.cinder` ; clé de `client.cinder` dans libvirt.

**Étape 1 — Reproduire, identifiant, statut.**

```
admin@adm01:~$ export OS_CLOUD=medisphere-plateforme
admin@adm01:~$ openstack server add volume m10-e38-sonde m10-e38-vol
admin@adm01:~$ for i in 1 2 3 4 5 6; do openstack volume show m10-e38-vol -f value -c status; sleep 10; done
admin@adm01:~$ openstack server event list m10-e38-sonde            # action attach_volume, son req-id
admin@adm01:~$ openstack --os-cloud medisphere-admin server show m10-e38-sonde -c OS-EXT-SRV-ATTR:host
admin@adm01:~$ openstack --os-cloud medisphere-admin volume service list
```

**Étape 2 — Suivre la requête.**

```
admin@oscmp02:~$ sudo grep -h <REQ-ID> /var/log/kolla/nova/nova-compute.log | grep -iE 'error|exception|fail' | head
admin@osctl01:~$ sudo grep -iE 'error|exception' /var/log/kolla/cinder/cinder-volume.log | tail -n 20
```

`<REQ-ID>` : identifiant de l'action `attach_volume`. Deux cas : l'erreur est dans `cinder-volume` (`initialize_connection` échoue, ou le pilote n'est pas initialisé), ou dans `nova-compute`, qui reçoit bien `connection_info` mais échoue à attacher le disque au domaine (erreur libvirt/QEMU).

**Variante 1 — secret libvirt faux sur les calculs.**

```
… nova.virt.libvirt.driver … Failed to attach volume at mountpoint: /dev/vdb: libvirt.libvirtError: internal error: unable to execute QEMU command 'blockdev-add': error connecting: Operation not permitted
```

(libellé représentatif). `cinder-volume` n'a rien vu d'anormal : la préparation a réussi, c'est l'ouverture par QEMU qui échoue. QEMU s'authentifie avec la clé que lui donne libvirt (secret dont l'UUID est dans `connection_info`). Compare les empreintes, sans afficher les clés :

```
admin@oscmp02:~$ sudo docker exec nova_libvirt virsh secret-list
 UUID                                   Usage
 <UUID-CINDER>                          ceph ceph-persistent-cinder
 <UUID-NOVA>                            ceph ceph-ephemeral-nova
admin@oscmp02:~$ sudo docker exec nova_libvirt virsh -q secret-get-value <UUID-CINDER> | sha256sum
admin@oscmp02:~$ sudo cat /etc/kolla/nova-libvirt/secrets/<UUID-CINDER>.base64 | tr -d '\n' | sha256sum
[root@ceph01 ~]# cephadm shell -- ceph auth get-key client.cinder 2>/dev/null | sha256sum
```

(ajuste les retours à la ligne pour comparer des chaînes identiques.) Le fichier de Kolla et Ceph concordent, la valeur **chargée** dans libvirt diffère : le secret a été changé à chaud (`virsh secret-set-value`), sans toucher aux fichiers. Correctif ciblé, sans redémarrer libvirt :

```
admin@oscmp02:~$ sudo docker exec nova_libvirt virsh secret-set-value --secret <UUID-CINDER> --file /var/lib/kolla/config_files/secrets/<UUID-CINDER>.base64
```

(le dossier `/etc/kolla/nova-libvirt/` de l'hôte est monté en `/var/lib/kolla/config_files/` dans le conteneur ; `--file` lit une valeur codée en base64, comme le fichier de Kolla.) Sur **les deux** calculs. Un `kolla-ansible reconfigure -t nova` n'aurait **rien** réparé : les fichiers sont justes, et Kolla ne relance pas le libvirt conteneurisé pour un secret inchangé. C'est une dérive de l'état vivant, invisible au code : seule une sonde (empreinte du secret chargé contre celle de la clé Ceph) la voit.

**Variante 2 — droits de `client.cinder` amputés.**

Erreur côté calcul identique ou proche (`Operation not permitted`), parfois aussi côté `cinder-volume` pour les **nouveaux** volumes. Les empreintes des clés concordent. Les droits non :

```
[root@ceph01 ~]# cephadm shell -- ceph auth get client.cinder 2>/dev/null | grep caps
	caps mgr = "profile rbd pool=vms"
	caps mon = "profile rbd"
	caps osd = "profile rbd pool=vms, profile rbd-read-only pool=images"
[root@ceph01 ~]# cephadm shell -- ceph log last 200 info audit 2>/dev/null | grep 'auth caps'
```

Le pool `volumes` a disparu des droits. Les volumes déjà attachés continuent de fonctionner : leurs sessions Ceph ont été ouvertes avec les anciens droits. Correctif (la commande `auth caps` **remplace** tous les droits : donne-les tous) :

```
[root@ceph01 ~]# cephadm shell -- ceph auth caps client.cinder mon 'profile rbd' osd 'profile rbd pool=volumes, profile rbd pool=vms, profile rbd-read-only pool=images' mgr 'profile rbd pool=volumes, profile rbd pool=vms'
```

Ce sont les droits recommandés par la documentation de Ceph et de Kolla pour `client.cinder` (ceux de M08/M10-E10) ; la source de vérité est le code de `plateforme/ceph`. Prévention : une sonde compare `ceph auth get` des clients OpenStack à la référence versionnée ; seuls les administrateurs de Ceph modifient des droits, par MR.

**Variante 3 — moniteurs faux dans la configuration de `cinder-volume`.**

```
admin@osctl01:~$ sudo tail -n 20 /var/log/kolla/cinder/cinder-volume.log
… ERROR cinder.volume.drivers.rbd … Error connecting to ceph cluster.
… ERROR cinder.volume.manager … Failed to initialize driver. … 
… cinder.exception.VolumeDriverNotInitialized / DriverNotInitialized …
admin@osctl01:~$ sudo grep mon_host /etc/kolla/cinder-volume/ceph/ceph.conf
mon_host = [v2:10.10.30.11:3300/0,v1:10.10.30.11:6789/0] …
```

(libellés représentatifs.) Les adresses ne sont pas celles des moniteurs (10.10.30.51-53). `volume service list` peut montrer `cinder-volume` `up` (le processus vit et envoie ses battements) alors que son pilote n'est pas initialisé : la création de volumes finit aussi en `error`. Correctif durable : le fichier vient de `etc/kolla/config/cinder/ceph.conf` de ton dépôt (M10-E10) ; vérifie-le, puis `kolla-ansible reconfigure -t cinder`. Si le dépôt est juste, le `reconfigure` écrase la modification locale ; s'il est faux (le fichier y a été « corrigé » par erreur), corrige-le par MR d'abord.

**Vérification** : volume de test `in-use`, visible dans le domaine (`sudo docker exec nova_libvirt virsh domblklist <instance-xxxxxxxx>` sur le bon calcul ; le nom libvirt est dans `OS-EXT-SRV-ATTR:instance_name`) ; un nouveau volume de 1 Gio `available` ; `lab/bin/check 10 38` (avant `--annuler`).

**Explications**

Un attachement se fait en trois temps. Nova réserve le volume (`attachment create`), `nova-compute` envoie à Cinder les informations de l'hôte (`attachment update`), `cinder-volume` répond par `connection_info` : protocole `rbd`, nom `volumes/volume-<uuid>`, moniteurs, utilisateur `cinder`, UUID du secret. `nova-compute` construit le disque `<disk type='network'>` du domaine et demande à libvirt de l'ajouter à chaud ; libvirt donne à QEMU la clé du secret désigné, QEMU ouvre l'image avec `librbd`. Trois éléments d'authentification doivent concorder : la clé connue de Ceph, la valeur du secret dans libvirt (sur chaque calcul), et les droits du client sur le pool.

**Pièges classiques**
- Régénérer la clé de `client.cinder` « pour repartir propre » : tous les volumes attachés, les sauvegardes et les clones cessent de fonctionner au prochain accès.
- Redémarrer `nova_libvirt` sur un calcul chargé sans avoir lu la documentation de ta version.
- Coller `ceph auth get` (qui affiche la clé) dans le journal.

**En production chez MédiSphère**
Sonde nocturne d'attachement de bout en bout ; contrôle d'empreintes clé Ceph ↔ secrets libvirt ↔ trousseaux de Kolla ; droits Ceph sous code.

---

### M10-E39 — Panne : plus personne ne s'authentifie

**Démarche de diagnostic**

*Symptôme* : selon la variante, toute obtention de jeton échoue (CLI et Horizon) avec une erreur 5xx, ou seule la connexion à Horizon échoue alors que la CLI fonctionne.

*Hypothèses* : identifiants (non : ils donneraient 401, et pour tout le monde en même temps c'est improbable) ; HAProxy sans serveur Keystone sain ; Keystone qui plante (base, clés fernet, configuration) ; cache et sessions d'Horizon (memcached) ; certificat ou TLS (non : l'erreur serait côté client, avant tout code HTTP).

**Étape 1 — Code HTTP et émetteur.**

```
admin@adm01:~$ openstack --os-cloud medisphere-admin --debug token issue 2>&1 | grep -E '^(REQ|RESP|RESP BODY)|HTTP/1.1|Service Unavailable|Internal Server Error' | sed -E 's/(X-Auth-Token: ).*/\1***/' | head
admin@adm01:~$ curl -s -o /dev/null -w '%{http_code}\n' https://openstack.par1.medisphere.internal:5000/v3
```

Un 503 avec une page HTML de HAProxy (« No server is available to handle this request ») : Keystone n'est sain pour HAProxy sur aucun serveur. Un 500 en JSON de Keystone : Keystone a planté en traitant la requête. Le `curl` sur `/v3` (document de version, sans authentification) sépare « Keystone répond » de « Keystone sait émettre un jeton ».

**Étape 2 — Conteneurs et journaux.**

```
admin@osctl01:~$ sudo docker ps --filter health=unhealthy --format '{{.Names}} {{.Status}}'
admin@osctl01:~$ sudo docker ps -a --filter status=exited --format '{{.Names}} {{.Status}}'
admin@osctl01:~$ sudo tail -n 40 /var/log/kolla/keystone/keystone.log
admin@osctl01:~$ sudo tail -n 20 /var/log/kolla/horizon/horizon.log 2>/dev/null; sudo ls /var/log/kolla/horizon/
```

**Variante 1 — clés fernet illisibles.**

```
admin@osctl01:~$ sudo docker ps --filter health=unhealthy --format '{{.Names}}'
keystone_fernet
… keystone.log : ERROR keystone.token.providers.fernet… Either [fernet_tokens] key_repository does not exist or Keystone does not have sufficient permission to access it: /etc/keystone/fernet-keys/
admin@osctl01:~$ d=$(sudo docker volume inspect -f '{{.Mountpoint}}' keystone_fernet_tokens); sudo ls -ln "$d"
-rw------- 1 0 0 44 … 0
-rw------- 1 0 0 44 … 1
-rw------- 1 0 0 44 … 2
admin@osctl01:~$ sudo docker exec keystone id keystone
```

Les clés appartiennent à `root` (UID 0) ; le processus Keystone tourne sous le compte `keystone` du conteneur (UID propre aux images Kolla) et ne peut plus les lire : aucun jeton ne peut être émis **ni validé** (même un jeton obtenu avant la panne est refusé). Le contrôle de santé de `keystone_fernet` (propriétaire de la clé `0`) l'a vu avant tout le monde. Correctif, depuis le conteneur pour utiliser le bon compte :

```
admin@osctl01:~$ sudo docker exec -u root keystone_fernet chown -R keystone:keystone /etc/keystone/fernet-keys
admin@osctl01:~$ sudo docker exec -u root keystone_fernet chmod 0600 /etc/keystone/fernet-keys/0 /etc/keystone/fernet-keys/1 /etc/keystone/fernet-keys/2
```

(adapte la liste aux clés présentes.) Aucune clé n'a changé : les jetons émis avant la panne redeviennent valides. Durable : rien dans le code ne posait ces droits faux ; c'est une action sur l'hôte (le « contrôle de conformité » d'InfoGér, à retrouver dans `journalctl` et l'historique de `sudo`). Prévention : sonde sur les conteneurs `unhealthy` ; plus aucun accès root pour InfoGér sans ticket de changement (Sophie).

**Variante 2 — Keystone n'atteint plus sa base.**

```
… keystone.log : … (pymysql.err.OperationalError) (1045, "Access denied for user 'keystone'@'…' (using password: YES)")
admin@osctl01:~$ ls -l --time-style=full-iso /etc/kolla/keystone/
```

`keystone.conf` a été modifié la veille (la date le dit) ; `ProxySQL` refuse le compte `keystone` avec ce mot de passe. Ne compare pas les mots de passe en clair : l'empreinte de la valeur du fichier contre celle de `keystone_database_password` de `passwords.yml` (déchiffré dans un tube, jamais sur disque) suffit à prouver l'écart. Correctif durable, qui repose la valeur de `passwords.yml` :

```
admin@adm01:~/src/openstack$ uv run kolla-ansible reconfigure -i inventaire/multinode --configdir etc/kolla -t keystone
```

Selon le moment, HAProxy renvoyait 503 (Keystone bloqué à son démarrage, sur les tentatives de connexion à la base : `max_retries = -1` dans le fichier de Kolla) ou Keystone 500. Prévention : une rotation de mot de passe se fait **par Kolla** (page « Password rotation » de la doc), jamais par édition d'un fichier généré.

**Variante 3 — memcached arrêté (Horizon seul).**

```
admin@osctl01:~$ sudo docker ps -a --filter name=memcached --format '{{.Names}} {{.Status}}'
memcached Exited (0) 2 hours ago
… horizon : … ConnectionRefusedError: [Errno 111] Connection refused (pymemcache) …
```

Dans Kolla, Horizon range ses **sessions** dans memcached (`SESSION_ENGINE = 'django.contrib.sessions.backends.cache'` quand memcached est activé et Valkey ne l'est pas) : sans memcached, la connexion échoue juste après le formulaire. La CLI marche parce que Keystone et les intergiciels des services n'utilisent memcached que comme **cache** (un cache absent ralentit, il ne casse pas). Correctif : `sudo docker start memcached`, puis une connexion Horizon. Trouver qui l'a arrêté : `docker inspect -f '{{.State.FinishedAt}}' memcached`, `journalctl -u docker --since …`.

**Étape 5 — Impact.** Les instances n'utilisent pas Keystone : elles tournent sans lui. Un pipeline OpenTofu lancé pendant la panne échoue à l'authentification (aucun changement appliqué : c'est le bon cas) ; un pipeline déjà authentifié échoue à la première requête suivante dès que la validation du jeton est impossible (variante 1) : il peut laisser un état partiel, à relire par un `tofu plan`.

**Explications**

Un jeton fernet n'est stocké nulle part : c'est un message chiffré et signé (AES-CBC + HMAC-SHA256) avec la clé primaire du dépôt de clés ; le valider, c'est le déchiffrer avec l'une des clés du dépôt. Sans clé lisible, Keystone ne peut ni émettre ni valider. `keystone_fernet` fait tourner les clés (une tâche planifiée) et `keystone_ssh` les pousse vers les autres contrôleurs ; avec un seul contrôleur, la synchronisation est triviale, avec trois elle devient un point d'attention (Q8 de M10-E45).

**Pièges classiques**
- Redémarrer Keystone en boucle : les variantes 1 et 3 n'ont rien à voir avec le processus Keystone lui-même.
- « Régénérer » les clés fernet (`keystone-manage fernet_setup`) : tous les jetons existants deviennent invalides, et cela ne corrige pas des droits faux.
- Écrire un mot de passe de `passwords.yml` dans le journal ou en argument de commande.

**En production chez MédiSphère**
Alerte sur tout conteneur `unhealthy` (Kolla fournit les contrôles, il suffit de les lire) ; Horizon en sessions sur base de données (`horizon_backend_database`) ou sur Valkey en HA, pour ne pas dépendre d'un memcached unique ; rotation des mots de passe uniquement par Kolla.

---

### M10-E40 — Panne : les calculs sont « down »

**Démarche de diagnostic**

*Symptôme* : `nova-compute` `down` sur les deux calculs ; agents réseau et services de volume sains ; instances en cours intactes.

*Hypothèses* : conteneur `nova_compute` arrêté ; `nova_compute` vivant mais coupé de RabbitMQ (réseau, filtrage, identifiants, URL) ; RabbitMQ lui-même (non : les agents et les autres services qui l'utilisent iraient mal aussi) ; horloge (non : l'état est calculé sur `osctl01` à partir de dates écrites par le conducteur).

**Étape 1 — Étendue.**

```
admin@adm01:~$ export OS_CLOUD=medisphere-admin
admin@adm01:~$ openstack compute service list --long -c Binary -c Host -c Status -c State -c "Updated At"
admin@adm01:~$ openstack network agent list -c "Agent Type" -c Host -c Alive
admin@adm01:~$ openstack volume service list
```

Seuls les `nova-compute` sont `down` ; leur `Updated At` s'est figé à l'heure de la panne. Les agents OVN des mêmes nœuds sont vivants (ils ne passent pas par RabbitMQ) : les nœuds et le réseau vont bien.

**Étape 2 — Le calcul.**

```
admin@oscmp01:~$ sudo docker ps -a --filter name=nova_ --format '{{.Names}} {{.Status}}'
admin@oscmp01:~$ sudo tail -n 30 /var/log/kolla/nova/nova-compute.log
admin@osctl01:~$ sudo docker exec rabbitmq rabbitmqctl list_connections user peer_host state | grep -E '10\.10\.50\.5[23]'
```

**Variante 1 — identifiants RabbitMQ faux.**

```
nova_compute Up 20 minutes (unhealthy)
… oslo.messaging._drivers.impl_rabbit … Connection failed: (0, 0): (403) ACCESS_REFUSED - Login was refused using authentication mechanism AMQPLAIN. … (retrying in … seconds)
… rabbitmq : … PLAIN login refused: user 'openstack' - invalid credentials …
```

Le conteneur tourne, se connecte au port, et se fait refuser. `transport_url` de `/etc/kolla/nova-compute/nova.conf` a été modifié sur les deux calculs (date du fichier) ; compare l'empreinte du mot de passe qu'il contient avec celle de `rabbitmq_password` de `passwords.yml`, jamais les valeurs. Correctif durable : `kolla-ansible reconfigure -t nova` (les calculs reçoivent le fichier régénéré et `nova_compute` redémarre).

**Variante 2 — AMQP rejeté par un filtrage local.**

```
… impl_rabbit … AMQP server on 10.10.50.51:5672 is unreachable: [Errno 104] Connection reset by peer. Trying again in … seconds.
admin@oscmp01:~$ timeout 3 bash -c '</dev/tcp/10.10.50.51/5672' && echo ouvert || echo ferme
ferme
admin@oscmp01:~$ sudo nft list ruleset | grep -B3 -A3 567
table inet wb_m10_e40 {
	chain sortie {
		type filter hook output priority filter; policy accept;
		tcp dport { 5671, 5672 } counter packets 412 bytes 24720 reject with tcp reset comment "durcissement CHG-1176"
```

Une table nftables posée à chaud (aucun rôle ne la produit, aucun fichier ne la contient : un redémarrage du nœud l'aurait fait disparaître) rejette toute sortie vers l'AMQP. Le compteur qui monte pendant un essai le prouve. Correctif : `sudo nft delete table inet wb_m10_e40` sur les deux calculs, après avoir noté le contenu et cherché le changement CHG-1176 (inexistant). Prévention : le pare-feu des hôtes est géré par Ansible (rôle de base) et une sonde compare le jeu de règles chargé à celui que produit le rôle.

**Variante 3 — conteneur arrêté.**

```
nova_compute Exited (0) 25 minutes ago
admin@oscmp01:~$ sudo docker inspect -f '{{.State.FinishedAt}} {{.State.ExitCode}}' nova_compute
admin@oscmp01:~$ sudo journalctl -u docker --since "-1h" | grep -i stop
```

Arrêt propre (code 0, signal d'arrêt) : quelqu'un l'a arrêté (fin de maintenance oubliée). Les conteneurs Kolla ont la politique de redémarrage `unless-stopped` : un conteneur arrêté à la main **reste** arrêté, même au redémarrage du nœud. Correctif : `sudo docker start nova_compute` (ou `kolla-ansible deploy-containers -t nova`, qui vérifie et relance les conteneurs attendus).

**Délai.** `nova-compute` rend compte toutes les `report_interval` secondes (10 par défaut) ; l'API considère un service `down` si son dernier compte rendu date de plus de `service_down_time` (60 s par défaut). D'où la minute (ou un peu plus, selon les tentatives de reconnexion) entre la cause et l'alerte. Le contrôle de santé du conteneur, lui, vérifie la connexion au port AMQP : il passe `unhealthy` plus tôt dans les variantes 1 et 2.

**Vérification** : deux calculs `up` ; une instance de test sur chacun (`openstack --os-compute-api-version 2.74 server create … --host oscmp01`) puis suppression ; `lab/bin/check 10 40`.

**Explications**

Toute la communication entre services de Nova passe par RabbitMQ (RPC d'`oslo.messaging`) : le compte rendu d'état, mais aussi chaque ordre (créer, migrer, ouvrir une console). Les instances, elles, sont des processus QEMU gérés par libvirt : elles ne dépendent pas de `nova-compute` pour tourner. Un calcul `down` est donc un calcul **inpilotable**, pas un calcul en panne : c'est pourquoi `evacuate` exige de s'assurer que l'hôte est réellement arrêté (isolation) avant de recréer ses instances ailleurs.

**Pièges classiques**
- Évacuer les instances d'un calcul « down » qui tourne encore : deux copies de la même instance écrivent sur le même disque Ceph (corruption).
- Redémarrer RabbitMQ : tous les services perdent leurs connexions, et la cause (côté calcul) reste.
- Supprimer la table nftables sans la noter : plus de preuve pour le post-mortem.

**En production chez MédiSphère**
Alerte sur `unhealthy` (plus rapide que `service_down_time`), pare-feu des hôtes sous code avec contrôle de dérive, et RB-102 (évacuation) qui commence par « prouver que l'hôte est isolé ».

---

### M10-E41 — Panne : l'envoi d'image échoue

**Démarche de diagnostic**

*Symptôme* : l'enregistrement de l'image est créé (`queued`), l'envoi des données échoue ou reste suspendu (`saving`). Les images existantes démarrent (lecture seule dans `images`, clone dans `vms`).

*Hypothèses* : limite de Glance (taille, quota) ; magasin RBD (authentification, droits, pool plein ou quota) ; réseau vers Ceph ; HAProxy (délai d'expiration pour les gros envois).

**Étape 1 — Reproduire.**

```
admin@adm01:~$ head -c 200M /dev/urandom > /tmp/essai.raw
admin@adm01:~$ openstack --os-cloud medisphere-plateforme --debug image create --disk-format raw --container-format bare --private --file /tmp/essai.raw essai-e41 2>&1 | grep -E 'PUT .*/file|RESP: \[|HTTP' | sed -E 's/(X-Auth-Token: ).*/\1***/'
```

**Étape 2 — Glance.** `sudo tail -n 40 /var/log/kolla/glance/glance-api.log` sur `osctl01`.

**Variante 1 — plafond de taille.**

```
RESP: [413] … Request Entity Too Large … Image exceeds the storage quota / size limit …
admin@osctl01:~$ sudo grep -n image_size_cap /etc/kolla/glance-api/glance-api.conf
3:image_size_cap = 104857600
```

(libellé représentatif.) `image_size_cap` (octets) limite la taille d'une image ; la valeur par défaut est de 1 Tio. Une petite image passe, une image Debian raw (environ 3 Gio) non. La ligne n'est pas dans le dépôt : `kolla-ansible reconfigure -t glance`. Si MédiSphère veut un plafond, il se décide (ADR), s'écrit dans `etc/kolla/config/glance.conf` ou `glance/glance-api.conf`, et se dimensionne pour les images de base.

**Variante 2 — pool `images` plein (quota).**

Glance ne répond pas (envoi suspendu), puis la CLI expire. Le journal de Glance ne dit rien d'utile pendant l'attente : l'écriture RBD est **bloquée**. Ceph le dit :

```
[root@ceph01 ~]# cephadm shell -- ceph health detail
HEALTH_WARN 1 pool(s) full
[WRN] POOL_FULL: 1 pool(s) full
    pool 'images' is full (running out of quota)
[root@ceph01 ~]# cephadm shell -- ceph osd pool get-quota images
quotas for pool 'images':
  max objects: N/A
  max bytes  : 3.1 GiB  (current num bytes: 3.1 GiB bytes)
[root@ceph01 ~]# cephadm shell -- ceph log last 200 info audit | grep set-quota
```

(libellés représentatifs.) Correctif : lever ou redimensionner le quota (`ceph osd pool set-quota images max_bytes 0`, ou la valeur décidée au M08-E20), **par le code** de `plateforme/ceph`. Les écritures suspendues reprennent ; les images de test sont à supprimer (`openstack image delete`), et celle de Julien aussi s'il préfère la renvoyer. Note : le cluster était en `HEALTH_WARN` : la sonde de santé de Ceph (M08-E24) aurait dû alerter avant Julien.

**Variante 3 — clé de `client.glance` fausse.**

```
… glance_store._drivers.rbd … Error … PermissionError / [errno 13] RADOS permission denied (error connecting to the cluster)
admin@osctl01:~$ sudo sed -nE 's/^\s*key\s*=\s*(\S+).*/\1/p' /etc/kolla/glance-api/ceph/ceph.client.glance.keyring | sha256sum
[root@ceph01 ~]# cephadm shell -- ceph auth get-key client.glance 2>/dev/null | sha256sum
```

(libellé représentatif.) Les empreintes diffèrent : le trousseau déployé n'est plus celui du cluster. Correctif : `kolla-ansible reconfigure -t glance` (Kolla recopie le trousseau depuis `etc/kolla/config/glance/` de ton dépôt). Vérifie d'abord que le trousseau du dépôt est le bon (même comparaison d'empreintes) ; s'il est chiffré par Vault dans le dépôt, la comparaison se fait sur la valeur déchiffrée dans un tube.

**Étape 4 — Nettoyage.** `openstack image list --long` (projet `plateforme`) : supprime les images `queued` et `saving`, puis refais l'envoi de 200 Mio (et supprime-le si tu n'en as pas l'usage).

**Explications**

Glance n'écrit pas dans un fichier : avec le magasin RBD, il crée une image RBD dans `images`, l'agrandit et y écrit les données au fil de l'envoi, puis crée un instantané protégé (`snap`) qui servira de parent aux clones de Nova et Cinder. Lire une image (démarrer une instance) n'écrit rien dans `images` : d'où des instances qui démarrent pendant que les envois échouent. Un quota de pool Ceph bloque les écritures du pool entier, sans tenir compte des projets : c'est un garde-fou de capacité, pas un quota par équipe (celui-là se fait dans Glance, avec les limites unifiées de Keystone).

**Pièges classiques**
- Augmenter les délais de HAProxy ou de la CLI : l'envoi attendra plus longtemps un pool qui ne se libérera pas.
- Supprimer des images « pour faire de la place » dans un pool plein par quota : c'est le quota, pas la place.
- Recréer la clé `client.glance` : toutes les images existantes deviennent illisibles pour Glance jusqu'à la mise à jour de tous les trousseaux.

**En production chez MédiSphère**
Alertes Ceph `POOL_FULL`/`POOL_NEAR_FULL` et seuils de remplissage, quotas de projets dans Keystone (limites unifiées), trousseaux contrôlés par empreinte contre le cluster.

---

### M10-E42 — Panne : le tableau de bord est inaccessible

**Démarche de diagnostic**

*Symptôme* : selon la variante, 503, erreur de certificat, ou rien du tout (délai).

*Hypothèses*, de l'extérieur vers l'intérieur : VIP absente (keepalived) ; HAProxy arrêté ou mal configuré ; certificat servi ; serveur Horizon arrêté ou injoignable ; Horizon qui plante (500).

**Étape 1 — Qualifier.**

```
admin@adm01:~$ curl -sv -o /dev/null https://openstack.par1.medisphere.internal/auth/login/ 2>&1 | grep -E 'Connected|SSL|subject|issuer|HTTP/|timed out|refused'
admin@adm01:~$ openssl s_client -connect 10.10.50.201:443 -servername openstack.par1.medisphere.internal -showcerts </dev/null 2>/dev/null | grep -E '^ *[0-9] s:|^ *i:|Verify return code'
admin@adm01:~$ openstack --os-cloud medisphere-admin token issue -f value -c expires
```

**Étape 2 — `osctl01`.**

```
admin@osctl01:~$ ip -br addr show | grep -E '10\.10\.50\.20[01]'
admin@osctl01:~$ sudo docker ps -a --filter name=keepalived --filter name=haproxy --filter name=horizon --format '{{.Names}} {{.Status}}'
admin@osctl01:~$ sudo docker logs --tail 20 haproxy
```

**Variante 1 — conteneur `horizon` arrêté.** `curl` : `HTTP/1.1 503 Service Unavailable` ; les API répondent. HAProxy : `backend horizon_back has no server available!`. `docker ps -a` : `horizon Exited (0)`. Correctif : `sudo docker start horizon` ; durable : action d'exploitation, retrouver l'auteur (`journalctl -u docker`).

**Variante 2 — HAProxy pointe vers un mauvais port.**

```
admin@osctl01:~$ sudo docker logs --tail 20 haproxy
… Server horizon_back/osctl01 is DOWN, reason: Layer4 connection problem, info: "Connection refused" …
admin@osctl01:~$ sudo grep -n server /etc/kolla/haproxy/services.d/horizon.cfg
    server osctl01 10.10.50.51:8088 check …
admin@osctl01:~$ sudo ss -ltnp | grep -E ':(8080|8088) '
LISTEN … 10.10.50.51:8080 … (horizon)
```

Horizon écoute sur 8080 (derrière HAProxy, Kolla le met sur ce port), HAProxy cherche 8088. Le fichier `horizon.cfg` est généré par le rôle `horizon` de Kolla (tâches `loadbalancer`) ; la modification est locale (date). Correctif durable : `kolla-ansible reconfigure -t horizon` régénère le fichier et recharge HAProxy.

**Variante 3 — certificat auto-signé.**

```
* SSL certificate problem: self-signed certificate
 0 s:CN = openstack.par1.medisphere.internal
   i:CN = openstack.par1.medisphere.internal
Verify return code: 18 (self-signed certificate)
```

Un seul certificat, émetteur = sujet : ce n'est plus celui de step-ca. `/etc/kolla/haproxy/haproxy.pem` a été remplacé (date, empreinte différente de celle de ton dépôt). Correctif durable : `kolla-ansible reconfigure -t loadbalancer` recopie le certificat externe (`kolla_external_fqdn_cert`) depuis ton dépôt et relance HAProxy. Vérifie **avant** que le certificat de ton dépôt est valide (30 jours au plus avec ACME, M10-E27) : s'il a expiré, le `reconfigure` repose un certificat expiré, et c'est le renouvellement automatique qu'il faut réparer. Ne jamais contourner avec `-k`, `--insecure` ou `verify: false` dans `clouds.yaml`.

Avec le renouvellement ACME de M10-E27 en place, cette variante ne se produit pas : HAProxy ne lit plus `/etc/kolla/haproxy/haproxy.pem` mais le volume `letsencrypt_certificates`, alimenté par `letsencrypt_lego` ; le script de panne le constate et passe à une autre variante. Si ton lab a retenu l'alternative de E27 (certificat obtenu hors de Kolla et déposé dans `certificates/`), elle s'applique telle quelle. Avec ACME, l'équivalent serait un certificat remplacé dans ce volume : `sudo docker restart letsencrypt_lego` provoque un nouveau passage, qui réémet et pousse un certificat de `ca01`.

**Variante 4 — keepalived arrêté, plus de VIP.**

```
* Failed to connect to openstack.par1.medisphere.internal port 443 after 10001 ms: Timeout was reached
admin@osctl01:~$ ip -br addr show ens18
ens18   UP   10.10.50.51/24 …                    (plus de 10.10.50.200 ni de 10.10.50.201)
admin@osctl01:~$ sudo docker ps -a --filter name=keepalived --format '{{.Names}} {{.Status}}'
keepalived Exited (0) 15 minutes ago
```

keepalived retire ses VIP en s'arrêtant : plus rien n'écoute sur .200 et .201 (HAProxy écoute sur ces adresses grâce à `ip_nonlocal_bind`, mais elles ne sont plus portées par l'hôte). Tout le cloud est touché : API externes, mais aussi API internes utilisées par les services entre eux (les calculs, Neutron, Cinder). Correctif : `sudo docker start keepalived`, puis vérifier tout le reste (`compute service list`, `network agent list`), car certains services ont accumulé des erreurs pendant la coupure.

**Vérification** : page de connexion en 200 avec la chaîne MédiSphère, connexion d'un utilisateur, `token issue` par les deux VIP ; `lab/bin/check 10 42`.

**Explications**

Le point d'entrée de Kolla est une pile de trois étages : keepalived porte les VIP (VRRP, ici avec un seul nœud), HAProxy termine le TLS et répartit vers les serveurs de chaque service (fichiers `services.d/<service>.cfg` générés par chaque rôle), les conteneurs des services écoutent sur l'adresse OS-API du nœud. La première mesure (`curl -v`) dit l'étage : pas de connexion → VIP ou HAProxy ; échec TLS → certificat ; code HTTP → HAProxy (503) ou application (500).

**Pièges classiques**
- Tester depuis `osctl01` lui-même : il voit ses propres adresses et peut contourner la VIP.
- Croire le navigateur sur un certificat (cache, exceptions acceptées) : `openssl s_client` est la référence.
- Relancer `haproxy` sans lire `docker logs haproxy` : une configuration invalide l'empêche de redémarrer, et tout tombe.

**En production chez MédiSphère**
Trois contrôleurs (VIP qui bascule réellement), sonde HTTPS sur chaque VIP avec vérification de l'émetteur et de l'échéance du certificat, alerte sur les serveurs HAProxy `DOWN`.

---

### M10-E43 — Astreinte : le cloud en détresse

**Démarche**

1. **Triage** : instruments d'abord, dans l'ordre des dépendances : SSH vers `osctl01`, `oscmp01`, `oscmp02` ; VIP (`curl -sv` sur .201, `nc -vz 10.10.50.200 5000`) ; jeton (`openstack token issue`) ; `ceph -s` sur `ceph01` ; `docker ps --filter health=unhealthy` et `docker ps -a --filter status=exited` sur chaque nœud. Puis `lab/bin/check 10 35` à `10 42` pour la carte.
2. **Priorisation par dépendances** : accès et VIP (E42) → authentification (E39) → messagerie et calculs (E40) → réseau nord-sud (E36) et métadonnées (E37) → stockage (E38, E41) → planification (E35). Exemples : avec E39 et E40, aucune commande `openstack` ne fonctionne tant que Keystone est en panne, et l'état des calculs ne se lit que sur les nœuds (`docker ps`, journaux) ; avec E42 v4 (VIP absentes), **tout** semble cassé, y compris des services sains ; avec E36 et E37, les deux concernent des instances de test, mais E36 coupe tout le nord-sud alors que E37 ne touche que les nouvelles instances : E36 d'abord.
3. **Communication** (modèle) : « 07 h 05 — INC-3750 — Statut : en cours. Impact : connexion au cloud impossible (Horizon et API), créations d'instances impossibles. Cause : deux anomalies distinctes identifiées sur le contrôleur et les calculs ; rétablissement de l'authentification en cours. Recette MédiAgenda de 9 h : maintenue à ce stade. Prochaine communication : 07 h 35. »
4. **Post-mortem** : chronologie horodatée (détection, premières hypothèses, fausses pistes, corrections), deux causes racines et leurs causes contributives (modifications hors du code, absence de sonde sur les conteneurs `unhealthy`, accès d'InfoGér sans changement), détection (ce qui aurait dû alerter avant Nadia), actions avec responsable et échéance (sondes, contrôle de dérive des fichiers générés, politique d'accès).
5. **RB-103** : runbook de référence dans [`docs/cloud/runbooks/RB-103-instance-en-erreur.md`](fichiers/M10-E43/medisphere/docs/cloud/runbooks/RB-103-instance-en-erreur.md). Ce qu'on attend : un arbre de tri qui part du **symptôme** (pas de la cause), des commandes de niveau 1 en lecture seule avec ce qu'il faut y lire, des gestes de niveau 2 encadrés, des critères d'escalade clairs, et une liste de ce qu'il ne faut jamais faire (évacuer un calcul non isolé, régénérer une clé Ceph, forcer l'état d'un volume, désactiver la vérification TLS).

**Grille d'auto-évaluation**
- [ ] Les instruments ont été vérifiés avant le diagnostic (aucune conclusion tirée d'un test qui dépendait d'un service en panne).
- [ ] L'ordre de traitement est justifié par les dépendances.
- [ ] Chaque correction a été suivie d'une reprise de **tous** les tests de départ.
- [ ] Trois communications au moins, avec statut, impact, prochaine étape, prochaine heure.
- [ ] Post-mortem sans coupable, causes racines distinctes des déclencheurs, actions vérifiables.
- [ ] RB-103 utilisable par quelqu'un qui n'a pas fait le module : aucune commande de niveau 1 ne modifie l'état.

---

### M10-E44 — Sous le capot : la vie d'un `server create`

**Solution**

Compte rendu de référence : [`docs/cloud/analyses/vie-d-un-server-create.md`](fichiers/M10-E44/medisphere/docs/cloud/analyses/vie-d-un-server-create.md).

*Préparation : journalisation de débogage par Kolla.* Dans `etc/kolla/globals.yml` de ta branche de travail : `nova_logging_debug: "True"` (variable du rôle Nova, utilisée dans le modèle de `nova.conf`), puis `kolla-ansible reconfigure -t nova`. À la fin, retire la ligne et relance le même `reconfigure`. (Alternative plus ciblée : une surcharge `etc/kolla/config/nova/nova-scheduler.conf` avec `[DEFAULT] debug = True`.)

*1. La commande.*

```
admin@adm01:~$ export OS_CLOUD=medisphere-plateforme
admin@adm01:~$ openstack --debug server create --flavor m1.petit --image debian-13 --network reseau-plateforme --key-name cle-adm01 --wait m10-e44-trace 2>&1 | sed -E 's/(X-Auth-Token: )[^ ]+/\1***/I' > /tmp/e44-debug.txt
admin@adm01:~$ grep -E 'POST .*/v3/auth/tokens|POST .*/servers|RESP: \[20[12]\]|x-openstack-request-id|x-compute-request-id' /tmp/e44-debug.txt | head
REQ: curl -g -i -X POST https://openstack.par1.medisphere.internal:5000/v3/auth/tokens …
RESP: [201] … X-Subject-Token: {SHA256}…
REQ: curl -g -i -X POST https://openstack.par1.medisphere.internal:8774/v2.1/servers …
RESP: [202] … x-openstack-request-id: req-2b6f…  x-compute-request-id: req-2b6f…
```

La CLI masque déjà le jeton dans l'affichage des en-têtes (`{SHA256}…`) ; le `sed` est une ceinture de sécurité. `202 Accepted` : `nova-api` a validé, réservé le quota, enregistré la demande (*build request*) et confié la suite au conducteur ; la CLI interroge ensuite `GET /servers/<id>` jusqu'à `ACTIVE`.

*2. Le plan de contrôle.*

```
root@osctl01:~# grep -h req-2b6f /var/log/kolla/nova/nova-api.log /var/log/kolla/nova/nova-conductor.log /var/log/kolla/nova/nova-scheduler.log | sort | cut -c1-220
```

Séquence attendue (horodatages croissants) : `nova-api` (`POST /v2.1/servers` → 202) ; `nova-conductor` (`schedule_and_build_instances`) ; `nova-scheduler` (« Starting to schedule for instances », demande à Placement, liste des candidats, filtres avec leur décompte, poids, « Selected host: oscmp02 », réclamation des allocations) ; `nova-conductor` (création de l'instance dans la base de la cellule, appel RPC `build_and_run_instance` vers `oscmp02`) ; puis sur `oscmp02`, `nova-compute.log` (réclamation des ressources, création du port, attente de `network-vif-plugged`, création du domaine, « Took N seconds to build instance »). Dans Placement :

```
root@osctl01:~# grep -h req-2b6f /var/log/kolla/placement/placement-api.log | cut -c1-200
… [req-2b6f… req-9a41… …] … "GET /allocation_candidates?…limit=1000&resources=DISK_GB%3A10%2CMEMORY_MB%3A1024%2CVCPU%3A1 …" status: 200
… [req-2b6f… req-c3d0… …] … "PUT /allocations/<uuid de l'instance> …" status: 204
```

Le premier identifiant entre crochets est l'identifiant **global** (celui de Nova, transmis par l'en-tête `X-OpenStack-Request-ID`), le second celui de Placement. Le temps est passé, en général, surtout sur le calcul (création du disque RBD par clonage, démarrage de QEMU, attente du port).

*3. Le réseau.*

```
root@osctl01:~# grep -h req-2b6f /var/log/kolla/neutron/neutron-server.log | grep -E 'POST /v2.0/ports|PUT /v2.0/ports' | cut -c1-200
root@osctl01:~# docker exec ovn_northd ovn-nbctl show | grep -A3 <ID-DU-PORT>
root@osctl01:~# docker exec ovn_northd ovn-sbctl find Port_Binding logical_port=<ID-DU-PORT>
admin@oscmp02:~$ sudo docker exec openvswitch_vswitchd ovs-vsctl --columns=name,external_ids find Interface external_ids:iface-id=<ID-DU-PORT>
```

`nova-compute` crée le port (`POST /v2.0/ports`), puis le lie à l'hôte (`PUT` avec `binding:host_id=oscmp02`) ; `neutron-server` écrit le port logique dans la base nord ; `ovn-northd` produit les flux logiques et la ligne `Port_Binding` ; quand libvirt crée l'interface `tap…` dans `br-int` avec `iface-id` = identifiant du port, `ovn-controller` de `oscmp02` revendique la liaison (colonne `chassis`), Neutron passe le port `ACTIVE` et envoie à Nova l'événement `network-vif-plugged` ; `nova-compute` démarre alors l'instance.

*4. L'hyperviseur.*

```
admin@adm01:~$ openstack --os-cloud medisphere-admin server show m10-e44-trace -c OS-EXT-SRV-ATTR:host -c OS-EXT-SRV-ATTR:instance_name
admin@oscmp02:~$ sudo docker exec nova_libvirt virsh list
admin@oscmp02:~$ sudo docker exec nova_libvirt virsh dumpxml instance-0000002a | grep -A12 "<disk type='network'"
    <disk type='network' device='disk'>
      <driver name='qemu' type='raw' cache='writeback' discard='unmap'/>
      <auth username='nova'>
        <secret type='ceph' uuid='<UUID-NOVA>'/>
      </auth>
      <source protocol='rbd' name='vms/<uuid>_disk'>
        <host name='10.10.30.51' port='6789'/> …
[root@ceph01 ~]# cephadm shell -- rbd info vms/<uuid>_disk | grep parent
	parent: images/<id de l'image>@snap
```

Le disque éphémère est une image RBD du pool `vms`, **clone** de l'instantané `snap` de l'image Glance dans `images` (copie sur écriture : rien n'est copié au démarrage). L'interface est de type `ethernet` (ou `bridge`) reliée à `br-int`, avec le MTU du réseau.

*5. Nettoyage.* `openstack server delete --wait m10-e44-trace` ; vérifier : port absent (`ovn-nbctl show`), image `vms/<uuid>_disk` absente (`rbd ls vms`), allocations disparues (`openstack resource provider usage show`). Remettre la journalisation normale par Kolla.

**Réponses aux questions d'analyse**

1. L'API est asynchrone : `nova-api` ne peut pas savoir en quelques millisecondes si un hôte acceptera l'instance. Elle répond `202 Accepted` avec l'identifiant de l'instance et, selon les options, le mot de passe administrateur généré ; la ressource existe, son état (`BUILD`) évoluera. `--wait` fait interroger `GET /servers/<id>` à intervalle régulier jusqu'à `ACTIVE` ou `ERROR`.
2. Les ressources sont réservées **par le scheduler**, juste après le choix de l'hôte et avant l'envoi au calcul (`PUT /allocations/<instance>` dans Placement). Comme Placement refuse une allocation qui dépasserait la capacité (contrôle atomique avec la génération du fournisseur), deux schedulers qui choisissent le même dernier emplacement ne peuvent pas réussir tous les deux : le second reçoit un conflit et essaie l'hôte suivant.
3. `nova-compute` signale l'échec au conducteur, qui libère les allocations et essaie un **hôte alternatif** fourni par le scheduler dans sa réponse initiale (`[scheduler] max_attempts`, 3 par défaut, d'où un nombre limité : sans limite, une image cassée ferait le tour du parc). Quand il n'y en a plus : `ERROR` avec « Exceeded maximum number of retries ».
4. Avec `--network`, c'est `nova-compute` (sur l'hôte choisi) qui crée le port dans Neutron puis le lie à l'hôte. Le port passe `ACTIVE` quand le *backend* (ici `ovn-controller`) a revendiqué la liaison. Nova attend `network-vif-plugged` pour ne pas démarrer une instance dont le réseau n'est pas encore programmé (DHCP raté, premier démarrage sans réseau) ; le délai est `vif_plugging_timeout`.
5. `ovn-controller` sur chaque nœud, à partir des flux logiques de la base sud (produits par `ovn-northd` à partir de la base nord, écrite par Neutron). Le routage, le NAT, le DHCP et le filtrage sont des flux OpenFlow : plus besoin d'agents L3 et DHCP ni d'espaces de noms par routeur (seule reste l'enveloppe des métadonnées).
6. Parce que le disque n'est pas un fichier local : QEMU parle directement à Ceph avec `librbd` (protocole `rbd`, moniteurs, utilisateur, secret). Avec une image qcow2 dans Glance, Nova ne peut pas cloner : il télécharge l'image, la convertit en raw et l'importe dans `vms` à chaque création (lent, et de la place perdue) ; d'où l'exigence d'images raw (M10-E06).
7. Exemples : la ligne du scheduler « Got no allocation candidates » ou « Filter results » (E35) ; `ovn-sbctl` montrant le port de passerelle `cr-lrp-…` sans *chassis*, ou l'absence de patch `provnet` dans `ovs-vsctl show` (E36) ; la ligne `blockdev-add … error connecting` de `nova-compute` avec l'UUID du secret dans `connection_info` (E38) ; l'absence de toute ligne `nova-compute` pour la requête alors que le conducteur l'a envoyée, avec `Updated At` figé (E40).

**Pièges classiques**
- Laisser Nova en `debug` : les journaux grossissent vite et peuvent contenir des données sensibles.
- Coller la sortie brute de `--debug` dans le compte rendu.
- Oublier que `grep` sur l'identifiant de Nova ne trouve dans Neutron ou Placement que les lignes où il est transmis : certaines actions de fond (agents, tâches périodiques) ont leur propre identifiant.

---

### M10-E45 — Questions expert : OpenStack

**Réponses**

1. Placement tient l'**inventaire** de chaque fournisseur de ressources (un calcul, un pool de stockage partagé, un GPU…) par **classe** (VCPU, MEMORY_MB, DISK_GB, classes personnalisées `CUSTOM_*`), avec `total`, `reserved` (non allouable), `allocation_ratio` (surallocation), `min_unit`/`max_unit` (taille d'une allocation), `step_size` (granularité) ; les **allocations** (qui consomme quoi, par consommateur), les **traits** (capacités qualitatives : `HW_CPU_X86_AVX2`, `COMPUTE_STATUS_DISABLED`…) et les **agrégats** (groupes). Sorti de Nova pour devenir un service générique (Neutron, Cyborg et d'autres y publient des ressources) et pour remplacer le suivi de capacité dans le scheduler par des requêtes SQL atomiques, plus justes et plus rapides à grande échelle.
2. **c**. `hw_architecture` est vérifié par le **filtre** `ImagePropertiesFilter`, après Placement (sauf si `image_metadata_prefilter` est activé, ce qui n'est pas le défaut). a) un trait exigé absent, b) une réservation qui ne laisse plus de place et d) une capacité épuisée au ratio configuré sont tous évalués **par Placement** et donnent bien « Got no allocation candidates ».
3. `cpu_allocation_ratio` (s'il est réglé) est imposé à Placement à chaque mise à jour de l'inventaire par `nova-compute` ; `initial_cpu_allocation_ratio` n'est utilisé qu'à la **création** du fournisseur, ensuite l'opérateur peut changer le ratio directement dans Placement (`resource provider inventory set`) et `nova-compute` ne l'écrase pas. D'où des valeurs dans Placement qui ne correspondent pas au fichier : la valeur effective est celle de Placement.
4. `ovn-northd` remplace la logique de traduction des agents (L3, DHCP, sécurité) : il transforme la topologie logique (base NB, écrite par Neutron) en flux logiques (base SB) ; `ovn-controller` sur chaque nœud remplace l'agent OVS et programme Open vSwitch. Le routage, le NAT, le DHCP (natif) et les groupes de sécurité (ACL) ne demandent plus d'agent Neutron. Restent : l'agent de métadonnées OVN (il faut un proxy HTTP local dans un espace de noms) et, au besoin, l'agent OVN générique (`neutron_ovn_agent`, extensions comme la QoS matérielle).
5. Le port de passerelle d'un routeur (port externe) est lié à un *chassis* parmi les candidats (ceux qui ont `enable-chassis-as-gw` et la bonne correspondance de réseau physique), avec des **priorités** ; le plus prioritaire vivant porte la passerelle, la bascule se décide par **BFD** entre *chassis*. Avec `neutron_ovn_distributed_fip` (`enable_distributed_floating_ip`), le NAT des IP flottantes se fait sur le calcul de l'instance (trafic direct, pas de point unique), ce qui exige que les calculs aient accès au réseau externe ; le SNAT sans IP flottante reste centralisé.
6. **b**. Neutron calcule le MTU d'un réseau de projet comme le MTU du chemin (`path_mtu`, à défaut `global_physnet_mtu`) moins le surcoût du type de réseau : pour Geneve, `max_header_size` (38 octets par défaut, réglé pour OVN) plus l'en-tête IPv4 (20 octets), soit 58 : 9000 − 58 = 8942. a) ignore l'encapsulation (paquets trop gros pour le tunnel) ; c) et d) supposent un chemin à 1500. Si on oublie `global_physnet_mtu`, Neutron suppose 1500 et annonce 1442 : tout fonctionne, mais sans profiter des trames géantes du VLAN 51.
7. L'instance interroge `169.254.169.254` ; le *haproxy* de l'espace de noms `ovnmeta-<réseau>` sur son calcul ajoute l'identifiant du réseau et transmet à l'agent ; l'agent retrouve le port (adresse IP source + réseau), donc l'instance et le projet, puis appelle Nova avec `X-Instance-ID`, `X-Tenant-ID` et `X-Instance-ID-Signature` = HMAC-SHA256 de l'identifiant d'instance avec le secret partagé. Nova recalcule la signature et refuse (403) si elle diffère : une instance ne peut pas se faire passer pour une autre, et un tiers sans le secret ne peut pas interroger le service.
8. Un jeton fernet contient l'utilisateur, la portée, les méthodes, la date d'expiration (en binaire compact), chiffré et signé avec la clé **primaire** ; il n'est jamais stocké (validation par déchiffrement). Le dépôt contient une clé `0` (en attente, *staged*, qui deviendra primaire à la rotation suivante), la clé primaire (numéro le plus élevé), et des clés secondaires (anciennes primaires, pour valider les jetons encore valides). `max_active_keys` = ((durée de vie + fenêtre `allow_expired_window`) / période de rotation) + 2. Si un contrôleur n'a pas reçu la rotation, il ne sait pas déchiffrer les jetons émis avec la nouvelle primaire par les autres : refus aléatoires (selon le contrôleur atteint par HAProxy). C'est pourquoi la clé `0` est distribuée **avant** de devenir primaire.
9. **b**. Avec un seul contrôleur, le même hôte émet et valide les jetons : un décalage ne les rend pas invalides (a est faux ici ; il le serait en multi-contrôleurs au-delà de la tolérance, et pour des clients qui vérifient l'expiration par rapport à leur propre horloge). c) RabbitMQ ne vérifie pas l'heure des clients ; d) Ceph surveille l'horloge de **ses** moniteurs (`MON_CLOCK_SKEW`), pas celle des clients. Mais les journaux ne se corrèlent plus, les dates de `Updated At` deviennent trompeuses vues d'ailleurs, et les certificats émis ou vérifiés sur cet hôte peuvent paraître pas encore valides ou expirés. Une horloge se règle par chrony (M06), jamais à la main.
10. Les files *quorum* (Raft) répliquent les messages sur une majorité de nœuds et sont sûres en cas de perte d'un nœud, contrairement aux anciennes files « miroir » (supprimées dans RabbitMQ 4). Elles coûtent de la mémoire et du disque (journal Raft) et un peu de latence. Sur un seul nœud, une file *quorum* a une majorité de un : pas de redondance, mais la même sémantique ; le passage à trois contrôleurs n'imposera pas de changer de type de file.
11. `nova-compute` écrit son compte rendu (via le conducteur) toutes les `report_interval` secondes ; l'API le déclare `down` si le dernier date de plus de `service_down_time`. Les instances sont des processus QEMU sous libvirt, indépendants de `nova-compute` : elles continuent de tourner. `evacuate` reconstruit les instances ailleurs à partir de leur disque partagé (Ceph) : si l'hôte d'origine tourne encore, deux QEMU écrivent sur le même disque. Il faut donc **isoler** l'hôte (arrêt, coupure de l'alimentation ou du stockage) et le déclarer `down` sans attendre (`openstack compute service set --down <hôte> nova-compute`, ce qu'on appelle *force-down*).
12. `deploy` fait tout (configuration, images, conteneurs, amorçage des bases et des comptes Keystone) ; `reconfigure` régénère la configuration et recrée ou redémarre les conteneurs dont la configuration ou la définition a changé ; `deploy-containers` ne touche qu'aux conteneurs (sans régénérer la configuration, ni les tâches d'amorçage). Kolla compare la définition attendue du conteneur (image, volumes, environnement, et une empreinte de la configuration générée) avec celle du conteneur existant, et ne recrée que ce qui diffère (gestionnaires « restart » notifiés quand un fichier de configuration change).
13. Le conteneur copie ses fichiers depuis `/etc/kolla/<service>/` (monté en lecture seule) à **chaque** démarrage (`kolla_set_configs`, stratégie `COPY_ALWAYS`) : la modification locale est relue au redémarrage. `reconfigure` régénère ces fichiers depuis le dépôt : la modification disparaît. Détection : comparer régulièrement `/etc/kolla/` des nœuds avec le résultat de `kolla-ansible genconfig` (ou avec des empreintes enregistrées après chaque déploiement), et alerter sur tout écart ; en complément, la supervision de la date de modification des fichiers générés.
14. Nova réserve le volume, `nova-compute` envoie à Cinder les informations de l'hôte, `cinder-volume` (pilote RBD) renvoie `connection_info` (pool, image, moniteurs, utilisateur `cinder`, UUID du secret libvirt) ; `nova-compute` construit le disque réseau et l'ajoute au domaine ; libvirt fournit à QEMU la clé du secret. Deux clients distincts parce que les droits diffèrent : `client.nova` sert aux disques éphémères (`vms`), `client.cinder` aux volumes (`volumes`, avec lecture de `images` pour les clones et écriture de `vms`) ; séparer limite les dégâts d'une clé compromise et permet des rotations indépendantes.
15. Le clone RBD copie-sur-écriture exige que l'image source soit une image RBD **brute** dont on clone un instantané : une image qcow2 stockée dans Ceph n'est qu'une suite d'octets au format qcow2, que QEMU ne peut pas utiliser comme base RBD. `show_image_direct_url` (ou `show_multiple_locations`) permet à Nova et Cinder de connaître l'emplacement RBD de l'image (pour cloner au lieu de télécharger) ; il expose cet emplacement aux utilisateurs de l'API, ce qui est une fuite d'information sur le stockage et, avec `show_multiple_locations`, a permis par le passé des attaques (changement d'emplacement) : à réserver à la configuration interne, avec les politiques adaptées (ou les nouvelles API d'emplacements de Glance).
16. **b**. Atteindre le quota marque le pool plein (`POOL_FULL`) ; les écritures des clients sont suspendues (ou refusées avec `EDQUOT` selon le client et ses options), les lectures continuent ; lever le quota libère les écritures en attente. a) `ENOSPC` est la réaction à un cluster physiquement plein (`full_ratio`), pas à un quota ; c) Ceph ne supprime jamais de données ; d) le quota est appliqué.
17. Le fournisseur OVN implémente un répartiteur **L4** (TCP, UDP, SCTP) directement dans OVN (NAT distribué vers les membres) : pas de machine virtuelle, démarrage instantané, très peu de ressources ; mais ni L7 (règles HTTP), ni terminaison TLS, ni répartition autre que par source/port (`SOURCE_IP_PORT`), et des contrôles de santé limités. Amphora déploie une VM HAProxy par répartiteur : L7, TLS (avec Barbican), algorithmes variés, mais coût mémoire et complexité (réseau de gestion, certificats, images). Pour MédiAgenda : OVN pour du L4 interne ou un service TCP, amphora (ou un HAProxy dans Kubernetes plus tard) si l'équipe a besoin de TLS ou de routage HTTP (ADR-0100).
18. *Secure RBAC* définit des personas : `reader` (lecture), `member` (gestion des ressources du projet), `manager` (gestion déléguée dans le projet ou le domaine, depuis 2024.x) et `admin` ; la **portée** (projet, domaine, système) dit sur quoi porte le rôle. `enforce_new_defaults` active les nouvelles règles par défaut (et désactive les anciennes, plus permissives) ; `enforce_scope` fait rejeter un jeton dont la portée ne convient pas à l'API. La transition a pris des années parce que chaque service devait réécrire ses règles, garder la compatibilité avec les déploiements existants (anciennes règles, `admin` global historique) et faire migrer les outils et les comptes de service. Vérifie l'état des défauts dans la documentation 2026.1 de chaque service.
19. Un nœud : tout est point unique (MariaDB, RabbitMQ, HAProxy/keepalived, memcached, OVN). Trois nœuds : Galera (écriture synchrone, quorum à 2 sur 3), RabbitMQ en grappe avec files *quorum*, VIP qui bascule (VRRP), plusieurs memcached (caches indépendants), bases OVN NB/SB en grappe RAFT. Galera, RabbitMQ *quorum* et RAFT exigent une **majorité** : avec deux nœuds, la perte d'un seul (ou une coupure entre eux) empêche toute majorité ou crée un risque de cerveau divisé ; trois est le minimum utile, et un nombre impair évite de payer un nœud de plus sans gain de tolérance.
20. Lire les notes de version et la matrice de support de Kolla (systèmes hôtes, version d'Ansible, versions d'OpenStack sautées ou non) ; préparer la nouvelle version de Kolla-Ansible dans un environnement `uv` séparé ; sauvegarder (base `kolla-ansible mariadb-backup`, configuration, clés fernet, M10-E25) ; vérifier Ceph et la compatibilité des clients ; `kolla-ansible pull` (images), `prechecks`, puis `upgrade` (service par service, migrations de schéma, *online data migrations* de Nova et Cinder à terminer) ; vérifier les politiques (nouveaux défauts) et les fonctionnalités dépréciées ; tester (instance, volume, IP flottante, Octavia, Horizon) ; le retour arrière se fait par restauration de la base **et** des images précédentes, d'où la sauvegarde testée. On attend la série Kolla publiée parce que les images et les rôles de la version RC ne sont ni figés ni supportés : une RC peut changer, et une mise à jour depuis une RC n'est pas un chemin garanti.

**Grille d'auto-évaluation** : 16/20 au moins avec des réponses argumentées ; reprends les exercices liés à chaque erreur (E35 et E44 pour la planification, E36 et E37 pour le réseau, E38 et E41 pour Ceph, E39 et E40 pour l'identité et la messagerie, E24 et E28 pour la HA et la mise à jour).
