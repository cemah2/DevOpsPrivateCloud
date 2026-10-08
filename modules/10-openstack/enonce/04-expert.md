# Module 10 — Palier 4 : Expert

Le cloud MédiSphère tourne : Keystone sépare les projets, Glance, Cinder et Nova stockent sur `ceph-par1`, Neutron et OVN fournissent réseaux, routeurs et IP flottantes, Octavia répartit la charge, Horizon et OpenTofu donnent le libre-service aux équipes. Nadia Roussel pose la question qui fâche : « Le jour où Julien m'appelle à 7 h parce que ses instances sont en ERROR, qui sait quoi regarder ? Aujourd'hui, personne. » Karim Benali a donc préparé huit pannes, toutes de celles que les opérateurs OpenStack rencontrent vraiment : le célèbre « No valid host », une IP flottante muette, une instance qui ignore sa configuration, un volume qui ne s'attache pas, une authentification en panne, des calculs « down », un envoi d'image qui échoue, un tableau de bord inaccessible. Une astreinte les combine. Puis tu descends sous le capot : le trajet exact d'un `openstack server create` à travers tous les services, et les questions qu'on pose en entretien à un opérateur OpenStack.

La méthode est celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Avec quatre règles propres à OpenStack :
- **Suis la requête, pas ton intuition.** Une action OpenStack traverse plusieurs services (API, base, file de messages, ordonnanceur, Placement, agent de calcul, Neutron, Cinder, Ceph, libvirt). Chaque service journalise avec un **identifiant de requête** (`req-…`) : trouve-le, puis suis-le d'un journal à l'autre. `openstack server show` (champ `fault`) et `openstack server event list` / `server event show` disent déjà où la requête est morte.
- **Sépare l'état déclaré de l'état réel.** `openstack compute service list`, `network agent list` et `volume service list` disent ce que les services **déclarent** ; `docker ps`, l'état de santé des conteneurs (`docker ps --filter health=unhealthy`) et les journaux disent ce qu'ils **font**. Un service peut être `up` et inutilisable, ou `down` et en parfaite santé, mais coupé du reste.
- **Kolla génère, tu ne bricoles pas.** Les fichiers de `/etc/kolla/<service>/` sur les nœuds sont **produits** par Kolla-Ansible depuis ton dépôt `plateforme/openstack`, puis copiés dans le conteneur à son démarrage. Une modification faite à la main dans un de ces fichiers est une **dérive** : elle disparaît au prochain `kolla-ansible reconfigure`… ou y survit si elle vient de ton dépôt. Avant de corriger, demande-toi d'où vient la valeur fausse.
- **Le cloud repose sur le socle.** Ceph, DNS, PKI, temps, réseau de la bordure : un symptôme OpenStack peut avoir sa cause en dessous. Vérifie l'étage inférieur dès qu'un indice le désigne (et seulement alors).

> **Rappels** : tout se lance depuis `adm01`. Clients : `openstack` (installé par `uv tool`, introduction du module, avec les greffons du palier 2), `~/.config/openstack/clouds.yaml` avec les clouds `medisphere-admin` (administration) et `medisphere-plateforme` (projet `plateforme`) ; exporte `OS_CLOUD=medisphere-admin` ou passe `--os-cloud`. Les vérifications utilisent les mêmes clouds (variables `WB_OS_CLOUD` et `WB_OS_CLOUD_PLATEFORME` de `lab/lab.env`). Projet de déploiement : `~/src/openstack` (clone de `plateforme/openstack`, environnement `uv` avec Kolla-Ansible 22 et ansible-core 2.20), `etc/kolla/globals.yml`, `inventaire/multinode`, surcharges dans `etc/kolla/config/`, `passwords.yml` chiffré (identité Vault `critique`). Nœuds : `osctl01` (contrôle et réseau), `oscmp01` et `oscmp02` (calcul), joints par les alias SSH de M10-E02, en `admin` avec `sudo`. Journaux : `/var/log/kolla/<service>/` sur chaque nœud (lien vers le volume `kolla_logs`). Ceph : `ceph01` (M08), `sudo cephadm shell -- ceph …`. Documentation : `~/medisphere`, dossier `docs/cloud/`.

## Règles du jeu des pannes (M10-E35 à M10-E43)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 10 35
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` en force une, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab (selon tes choix des paliers précédents), le script en essaie une autre.
- **Certaines injections sont longues** : elles créent d'abord des ressources de test dans le projet `plateforme` et vérifient qu'elles fonctionnent **avant** de casser quoi que ce soit (M10-E36 et M10-E37 : un réseau, un routeur, une IP flottante et une instance `m10-eXX-…`, 3 à 8 minutes ; M10-E38 : une instance et un volume ; M10-E41 : l'envoi d'un fichier de 200 Mio). Le projet `plateforme` doit donc avoir du quota libre : 1 réseau, 1 routeur, 1 IP flottante, 1 instance `m1.petit`, 1 volume de 1 Gio.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 10 35`) : il doit être vert. Une panne posée sur un cloud déjà malade fausse tout le diagnostic. `ceph-par1` doit être démarré et en `HEALTH_OK`.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les nœuds, ni `~/.local/state/workbook/` sur `adm01` (exception : le dossier `M10-sonde/`, qui ne contient que la clé SSH des instances de test, utilisateur `debian`).
- Une seule panne active à la fois par exercice. Si tu abandonnes : `lab/bin/break 10 35 --annuler` remet l'état sain (filet de sécurité, pas un correctif : compte l'exercice comme non réussi). **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne et supprimer les ressources de test : l'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation. Pour M10-E36, E37 et E38, lance le contrôle **avant** `--annuler` : il vérifie aussi les ressources de test.
- Les pannes agissent sur les conteneurs et les fichiers générés par Kolla des nœuds OpenStack (fichiers sauvegardés avant modification), sur l'Open vSwitch de `osctl01`, sur des objets de l'API (services, gabarits, images, groupes de sécurité) avec le cloud `medisphere-admin`, et sur `ceph-par1` par `ceph01` (droits d'un client, quota d'un pool). Jamais sur `pve01`, son réseau ou son pare-feu, jamais sur la bordure (`gw01`/`gw02`), jamais sur une VM hors du pool `lab`. Aucune donnée n'est détruite : aucune instance, aucun volume, aucune image existants ne sont supprimés, aucune clé Ceph n'est régénérée.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/cloud/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion. Il alimente le post-mortem de M10-E43. **Aucun secret** n'y figure (mots de passe de `passwords.yml`, clés cephx, jetons, secret partagé des métadonnées) : quand tu dois comparer deux secrets, compare leurs empreintes (`sha256sum`), jamais leurs valeurs.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

> ⚠️ **Correction durable = le dépôt, puis Kolla.** Une correction à chaud (éditer un fichier de `/etc/kolla/` sur un nœud, relancer un conteneur, poser une valeur par l'API) est permise pour rétablir le service, à condition de vérifier ensuite que le **code** produit le même état : `kolla-ansible reconfigure` limité au service concerné (`-t <service>`), après relecture du diff de ton dépôt. Avant de le lancer pendant une panne, demande-toi ce qu'il va changer : si la valeur fausse vient de ton dépôt (une surcharge de `etc/kolla/config/`), le `reconfigure` la **reposera**. La documentation de Kolla déconseille `--limit` ; si tu l'utilises pour aller vite, écris pourquoi dans ton journal.

> ⚠️ **Accès de secours** : M10-E36 (variantes réseau) et M10-E42 (une variante) peuvent couper les VIP ou le réseau externe. Tes accès aux nœuds passent par le VLAN 50 (OS-API) et ne dépendent ni des VIP, ni du réseau externe, ni de Keystone ; garde aussi l'agent QEMU depuis `pve01` (`qm guest exec 2101 -- …`). **Vérifie-les avant d'en avoir besoin** : `ssh osctl01 true`, `qm guest cmd 2101 ping`. Avant d'intervenir sur l'Open vSwitch ou le réseau de `osctl01`, prends un instantané (`ms-snapshot 2101`, M02-E11) : c'est ton retour arrière si une commande coupe aussi le VLAN 50.

---

### M10-E35 — Panne : « No valid host was found »  `BF` `★★★`

> **Ticket INC-3741** — *De : Julien Petit*
> Depuis ce matin, toutes mes créations d'instance échouent dans `mediagenda-dev` : l'instance passe en ERROR au bout de quelques secondes, avec « No valid host was found ». Gabarit `m1.petit`, image Debian 13, rien d'exotique. Hier soir tout marchait. Le quota du projet n'est pas atteint, j'ai vérifié.

**Objectifs pédagogiques**
- Savoir ce que cache « No valid host » : la décision de l'ordonnanceur (`nova-scheduler`), en deux temps : **Placement** propose des candidats (inventaires, ratios d'allocation, réservations, traits), puis les **filtres** de Nova les éliminent (service désactivé, propriétés d'image, capacités).
- Trouver la raison exacte dans les journaux de `nova-scheduler` et de `nova-conductor` à partir de l'identifiant de requête, et la confirmer par l'état des services, des gabarits, des images et des inventaires.
- Distinguer une cause **d'exploitation** (un service désactivé, une propriété posée par l'API) d'une cause de **configuration** (un fichier de Kolla modifié hors du code), et corriger chacune au bon endroit.

**Prérequis** : M10-E07, M10-E13, M10-E19, M10-E20 ; `lab/bin/check 10 35` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : la planification se fait sur `osctl01` (conteneurs `nova_scheduler`, `nova_conductor`, `placement_api`) ; les inventaires (VCPU, MEMORY_MB, DISK_GB) sont envoyés à Placement par chaque `nova_compute` au démarrage puis périodiquement. La CLI `openstack` de base ne connaît pas les commandes de Placement (`resource provider …`, `allocation candidate list`, `trait list`) : elles viennent du greffon `osc-placement`, ajouté en M10-E13. Le paramètre `--os-placement-api-version` choisit la version de l'API Placement.

**Injection** : `lab/bin/break 10 35` (4 variantes ; l'injection crée puis supprime une instance de test, 1 à 2 minutes).

**Travail demandé**
1. Reproduis le symptôme dans le projet `plateforme` avec le gabarit et l'image du ticket. Relève le champ `fault` de l'instance, les actions (`server event list`) et l'**identifiant de requête** de la création.
2. Suis cet identifiant dans les journaux de `nova-conductor` et `nova-scheduler` sur `osctl01`. La planification a-t-elle échoué **avant** les filtres (Placement n'a rien proposé) ou **dans** les filtres (lesquels, et combien d'hôtes restaient après chacun) ?
3. Selon la réponse, interroge l'étage concerné : état des services de calcul, inventaires et usages des fournisseurs de ressources dans Placement, propriétés du gabarit et de l'image, configuration effective de `nova_compute`. Trouve **ce qui a changé** et depuis quand.
4. Corrige à la racine, au bon endroit (API, dépôt `plateforme/openstack` puis `kolla-ansible reconfigure`, ou les deux). Prouve que la correction tiendra au prochain déploiement.
5. Prouve le retour à la normale : une instance `m1.petit` Debian 13 passe `ACTIVE` dans `mediagenda-dev` (supprime-la ensuite), et `lab/bin/check 10 35` est vert.
6. Dans ton journal, écris la phrase que tu enverrais à Julien (cause, correction, prévention) et la **sonde** qui aurait détecté le problème avant lui.

**Critères de réussite**
- [ ] Les deux `nova-compute` sont `enabled` et `up` ; la mémoire réservée et les ratios d'allocation des calculs sont ceux de ton dépôt.
- [ ] Les gabarits `m1.*` n'exigent aucun trait absent ; aucune image publique n'exige une architecture autre que `x86_64`.
- [ ] Aucune instance en ERROR ne traîne dans le projet `plateforme` ; ton journal contient l'identifiant de requête et la ligne de journal décisive.

**Vérification** : `lab/bin/check 10 35`

<details><summary>Indice 1</summary>

`openstack server create … --wait` affiche l'identifiant de l'instance ; `openstack server event list <instance>` donne le `Request ID` de l'action `create`. Sur `osctl01` : `sudo grep <req-id> /var/log/kolla/nova/nova-scheduler.log /var/log/kolla/nova/nova-conductor.log`. Deux phrases à reconnaître : l'une dit que Placement n'a renvoyé **aucun candidat**, l'autre qu'un **filtre** a ramené le nombre d'hôtes à zéro.
</details>

<details><summary>Indice 2</summary>

Si Placement n'a rien proposé : `openstack resource provider list`, puis `resource provider inventory list <uuid>` (regarde `total`, `reserved`, `allocation_ratio`) et `resource provider usage show <uuid>` ; compare avec les exigences du gabarit (`flavor show`, champ `properties`). Si un filtre a tout éliminé : le journal du scheduler en mode `debug` nomme le filtre ; `compute service list --long` et `image show` (champ `properties`) sont les suspects habituels.
</details>

<details><summary>Indice 3</summary>

Une valeur d'inventaire anormale vient de la configuration de `nova_compute` : compare `/etc/kolla/nova-compute/nova.conf` des deux calculs avec ce que produit ton dépôt (`kolla-ansible genconfig` dans un dossier temporaire, ou le diff que montrerait un `reconfigure`). Une propriété d'API se lit avec `openstack … show -f json` et l'historique dans les journaux de `glance-api` ou `nova-api` (qui a fait la requête, quand).
</details>

**Pour aller plus loin** : écris dans `ms-verif-openstack` (M10-E26) une sonde « planifiabilité » qui interroge `allocation candidate list --resource VCPU=1,MEMORY_MB=1024,DISK_GB=10` et alerte si aucun candidat n'existe : elle aurait vu deux des variantes avant Julien. [Placement API](https://docs.openstack.org/placement/latest/), [Nova : filtres du scheduler](https://docs.openstack.org/nova/latest/admin/scheduling.html).

---

### M10-E36 — Panne : l'IP flottante ne répond pas  `BF` `★★★`

> **Ticket INC-3742** — *De : Julien Petit*
> Mes instances de recette ne répondent plus sur leur IP flottante depuis le réseau de l'entreprise : ni ping, ni SSH, ni HTTP. Elles tournent (ACTIVE) et la console montre un système démarré. *(L'instance de test et son adresse s'affichent à l'injection.)*

**Objectifs pédagogiques**
- Décomposer le chemin nord-sud d'une IP flottante avec OVN : `adm01` → bordure (VLAN 52) → interface externe de `osctl01` → pont `br-ex` → port *localnet* de `physnet1` → routeur logique (NAT de l'IP flottante, sur la passerelle OVN) → commutateur logique du réseau du projet → port de l'instance (groupes de sécurité).
- Lire la configuration **logique** (`ovn-nbctl`) et son application **physique** (`ovn-sbctl`, `ovs-vsctl`, `ovs-ofctl`, interfaces de l'hôte) ; savoir que les flux d'OVN sont tous dans la base, pas dans des espaces de noms comme avec OVS « classique ».
- Localiser une coupure par des captures (`tcpdump`) aux bons endroits et dans le bon ordre, en touchant le moins possible à un nœud dont dépend tout le trafic externe.

**Prérequis** : M10-E08, M10-E12, M10-E24 ; `lab/bin/check 10 36` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `osctl01` est l'unique passerelle OVN (*gateway chassis*) du cloud : le trafic des IP flottantes y entre et en sort, par l'interface du VLAN 52 (`ens21`, sans adresse, M10-E02) rattachée au pont externe de Kolla (`br-ex`). Les bases d'OVN tournent dans les conteneurs `ovn_nb_db` et `ovn_sb_db` ; la doc de Kolla conseille de lancer `ovn-nbctl` et `ovn-sbctl` depuis le conteneur `ovn_northd`. `ovs-vsctl` et `ovs-ofctl` se lancent dans `openvswitch_vswitchd`. L'instance de test `m10-e36-sonde` (projet `plateforme`) répondait au ping et en SSH avant l'injection.

**Injection** : `lab/bin/break 10 36` (4 variantes ; l'injection crée la pile de test, 3 à 5 minutes).

> ⚠️ **Attention** : `osctl01` porte aussi le VLAN 50 (tes accès SSH, les API, RabbitMQ). Avant toute commande qui modifie l'Open vSwitch ou une interface de `osctl01` (`ovs-vsctl set/add-port/del-port`, `ip link set`), prends un instantané (`ms-snapshot 2101`) et relis la commande deux fois : une erreur sur la mauvaise interface te coupe du nœud (retour par `qm guest exec 2101` ou par l'instantané).

**Travail demandé**
1. Reproduis depuis `adm01` (ping, `ssh -i ~/.local/state/workbook/M10-sonde/id_ed25519 debian@<IP>`). Vérifie côté API que rien n'a l'air anormal : instance, port, IP flottante, routeur, sous-réseau. Note ce que tu as vérifié.
2. Observe l'instance de l'**intérieur** sans passer par le réseau externe (console : `openstack console log show`, ou `console url show` et Horizon). A-t-elle son adresse privée ? Sa passerelle répond-elle ?
3. Capture le trafic d'un ping depuis `adm01` aux points successifs du chemin : interface externe de `osctl01`, puis (si les paquets y arrivent) l'interface de tunnel vers le calcul qui héberge l'instance. Où le paquet disparaît-il ? Dans quel sens ?
4. Confirme par la configuration à l'étage désigné : règles du groupe de sécurité du port, correspondances `ovn-bridge-mappings`, ports du pont externe, état de l'interface, port de passerelle du routeur (`lrp-…`) et son *chassis*.
5. Corrige à la racine. Si la cause est dans l'Open vSwitch de l'hôte, dis quelle tâche de Kolla-Ansible pose cette valeur et si un `reconfigure` l'aurait réparée ; si elle est dans l'API, dis qui l'a faite et comment l'empêcher (politiques, M10-E23).
6. Prouve le retour : ping et SSH vers l'IP de test, et une IP flottante d'un autre projet si tu en as une.

**Critères de réussite**
- [ ] Depuis `adm01`, l'instance de test répond au ping et en SSH par clé sur son IP flottante (contrôle à lancer **avant** `--annuler`).
- [ ] Sur `osctl01`, `physnet1` est relié au pont externe, l'interface externe est dans ce pont et active, `ovn_controller` est sain ; aucun agent réseau n'est mort.
- [ ] Ton journal contient les captures (ou extraits commentés) qui localisent la coupure, et la commande qui l'a confirmée.

**Vérification** : `lab/bin/check 10 36` (avant `--annuler`)

<details><summary>Indice 1</summary>

Commence par les deux extrémités : `openstack port show m10-e36-port -c security_group_ids -c status -c binding_host_id`, puis `openstack security group rule list <groupe>`. Côté OVN : `docker exec ovn_northd ovn-nbctl show` (routeur, `lrp-…`, NAT `dnat_and_snat`), `docker exec ovn_northd ovn-sbctl show` (*chassis* et leurs ports) et `ovn-nbctl lrp-get-gateway-chassis <lrp>`.
</details>

<details><summary>Indice 2</summary>

Sur `osctl01` : `sudo docker exec openvswitch_vswitchd ovs-vsctl show`, `… ovs-vsctl get open . external_ids`, `ip -br link`, et `sudo tcpdump -eni <interface du VLAN 52> icmp or arp`. Si les ARP pour l'IP flottante restent sans réponse, la passerelle ne « possède » plus l'adresse côté physique ; si l'écho entre et rien ne ressort, regarde plus loin dans le chemin.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-openstack` une sonde qui ping une IP flottante témoin (instance permanente minuscule d'un projet `supervision`) ; compare avec `ovn-appctl -t ovn-controller` et la commande `ovn-trace`, qui simule le chemin d'un paquet dans la configuration logique sans en envoyer un seul. [OVN : architecture](https://docs.ovn.org/en/latest/ref/ovn-architecture.7.html), [Neutron : OVN](https://docs.openstack.org/neutron/latest/admin/ovn/index.html) (routage, IP flottantes, passerelles).

---

### M10-E37 — Panne : l'instance ignore sa configuration  `BF` `★★`

> **Ticket INC-3743** — *De : Julien Petit*
> Les instances créées depuis ce matin démarrent (ACTIVE, ping OK) mais n'appliquent pas leur configuration : ma clé SSH est refusée, le nom d'hôte n'est pas le bon, mon script user-data ne s'est pas exécuté. Les instances plus anciennes vont bien. *(L'instance de test et son adresse s'affichent à l'injection.)*

**Objectifs pédagogiques**
- Suivre une requête de métadonnées avec OVN : `cloud-init` dans l'instance → `169.254.169.254` → *haproxy* de l'espace de noms `ovnmeta-<réseau>` sur le **calcul** → agent `neutron_ovn_metadata_agent` (qui signe la requête avec le secret partagé) → VIP interne → `nova_metadata` sur `osctl01` → réponse.
- Lire le journal de `cloud-init` depuis la console, et les journaux des deux côtés du proxy.
- Connaître le contournement (**config drive**) et savoir pourquoi ce n'est pas un correctif.

**Prérequis** : M10-E18 ; `lab/bin/check 10 37` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : les instances de test utilisent la clé `m10-sonde` (projet `plateforme`) et l'utilisateur `debian`. Dans Kolla 2026.1, le service de métadonnées de Nova tourne dans son propre conteneur `nova_metadata` (port 8775, derrière HAProxy) et l'agent de métadonnées OVN sur chaque nœud qui héberge des instances.

**Injection** : `lab/bin/break 10 37` (3 variantes ; l'injection crée la pile de test, une instance témoin, puis l'instance de test : 5 à 8 minutes).

**Travail demandé**
1. Reproduis (`ssh -v` avec la clé de test) et lis la sortie de console de l'instance : que dit `cloud-init` de sa source de données (*datasource*) et de l'URL des métadonnées ?
2. Situe la panne : réseau (l'instance a-t-elle son adresse, sa route vers `169.254.169.254` ?), proxy local du calcul, agent, ou service `nova_metadata` ? Utilise l'hôte de l'instance (`binding_host_id` de son port) et les journaux de chaque maillon.
3. Corrige à la racine. Si une valeur de configuration diffère entre deux services, compare-les **par empreinte**, jamais en clair dans ton journal.
4. Fais appliquer la configuration à l'instance de test **sans la recréer**. Explique dans ton journal pourquoi un simple redémarrage y suffit (ou non) : que fait `cloud-init` quand l'identifiant d'instance qu'il voit change ?
5. Explique ce qu'aurait changé la création de l'instance avec `--use-config-drive`, et pourquoi MédiSphère ne l'impose pas par défaut.

**Critères de réussite**
- [ ] `nova_metadata` tourne sur `osctl01`, l'agent de métadonnées OVN est vivant sur chaque calcul, et le secret partagé est le même des deux côtés.
- [ ] L'instance de test accepte la clé SSH (contrôle à lancer **avant** `--annuler`).
- [ ] Ton journal contient l'extrait de console qui montre l'échec et la réponse à l'étape 4.

**Vérification** : `lab/bin/check 10 37` (avant `--annuler`)

<details><summary>Indice 1</summary>

`openstack console log show m10-e37-sonde | grep -iE 'cloud-init|metadata|169.254'`. Un code HTTP dans ces lignes (403, 404, 500, 503) désigne déjà un maillon ; un délai dépassé en désigne un autre.
</details>

<details><summary>Indice 2</summary>

Sur le calcul de l'instance : `sudo docker ps -a --filter name=metadata`, `sudo ip netns list | grep ovnmeta`, `/var/log/kolla/neutron/neutron-ovn-metadata-agent.log`. Sur `osctl01` : `/var/log/kolla/nova/nova-metadata.log`. « Invalid proxy request signature » a une signification précise.
</details>

**Pour aller plus loin** : ajoute à ta sonde de supervision un test de bout en bout : une instance témoin qui, au démarrage, publie un jeton reçu par user-data sur un port HTTP ; la sonde le lit. [Nova : service de métadonnées](https://docs.openstack.org/nova/latest/admin/metadata-service.html), [Neutron : OVN](https://docs.openstack.org/neutron/latest/admin/ovn/index.html) (section sur les métadonnées).

---

### M10-E38 — Panne : le volume ne s'attache pas  `BF` `★★★`

> **Ticket INC-3744** — *De : Julien Petit*
> Impossible d'attacher un volume à une instance : le volume passe « attaching » ou « reserved », puis revient « available » ; l'instance n'a pas de nouveau disque. Mes volumes déjà attachés semblent fonctionner. Pour reproduire, dans le projet `plateforme` : `openstack server add volume m10-e38-sonde m10-e38-vol`.

**Objectifs pédagogiques**
- Connaître le chemin d'un attachement RBD : `nova-api` → `nova-compute` (réservation et `attachment` Cinder) → `cinder-volume` (`initialize_connection` : moniteurs, pool, utilisateur `cinder`, UUID du secret) → `nova-compute` construit le disque réseau → **libvirt** fournit la clé cephx (secret) à **QEMU**, qui ouvre l'image RBD.
- Savoir où vit chaque élément d'authentification : clé et droits de `client.cinder` dans Ceph, trousseau de `cinder-volume`, secret libvirt des calculs (UUID et valeur).
- Expliquer pourquoi des volumes **déjà attachés** continuent de fonctionner (sessions Ceph existantes) alors que les nouveaux attachements échouent.

**Prérequis** : M10-E10, M10-E11 ; M08-E27 (clés et droits Ceph) ; `lab/bin/check 10 38` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : les instances et volumes de test sont dans le projet `plateforme`. Kolla enregistre deux secrets libvirt sur chaque calcul (pour `client.nova`, disques éphémères, et pour `client.cinder`, volumes) à partir des fichiers de `/etc/kolla/nova-libvirt/secrets/` (`<uuid>.xml` et `<uuid>.base64`), copiés dans le conteneur `nova_libvirt` à son démarrage. `virsh` se lance dans ce conteneur. Les droits d'un client Ceph se lisent avec `ceph auth get client.<nom>` (sur `ceph01`, par `cephadm shell`).

**Injection** : `lab/bin/break 10 38` (3 variantes ; l'injection crée l'instance et le volume de test, 1 à 3 minutes).

> ⚠️ **Attention** : `ceph auth get`, `virsh secret-get-value` et les trousseaux affichent des **clés**. Ne les colle jamais dans ton journal ni dans un ticket ; compare des empreintes (`… | sha256sum`). Ne régénère aucune clé (`ceph auth get-or-create-key`, `ceph auth del`) : toutes les briques qui l'utilisent tomberaient. Redémarrer `nova_libvirt` sur un calcul qui héberge des instances n'est pas anodin : lis d'abord la doc de Kolla et préfère une action ciblée.

**Travail demandé**
1. Reproduis et relève l'identifiant de requête de l'action `attach_volume` (`server event list`), le statut du volume minute par minute, et l'éventuel message d'erreur côté instance et côté volume.
2. Suis la requête : `nova-compute` du calcul de l'instance, `cinder-volume` sur `osctl01`. Laquelle des deux étapes échoue : la préparation côté Cinder ou l'ouverture côté hyperviseur ? Note la ligne décisive.
3. Teste l'étage désigné **sans OpenStack** : l'utilisateur `cinder` peut-il lister, ouvrir, écrire une image du pool `volumes` (avec le trousseau de Kolla, depuis le nœud concerné) ? La valeur du secret libvirt correspond-elle à la clé de `client.cinder` (empreintes) ? Les moniteurs de la configuration de `cinder-volume` sont-ils les bons ?
4. Corrige à la racine, sans régénérer de clé : droits Ceph conformes à ceux posés au M08/M10-E10 (et versionnés dans `plateforme/ceph`), ou configuration conforme à ton dépôt `plateforme/openstack`, ou secret rétabli.
5. Prouve le retour : le volume de test passe `in-use` et apparaît dans l'instance (`virsh domblklist` dans `nova_libvirt` sur le bon calcul), et un nouveau volume de 1 Gio se crée.

**Critères de réussite**
- [ ] `cinder-volume` et `cinder-backup` sont `enabled up` ; `client.cinder` a ses droits sur `volumes`, `vms` (écriture) et `images` (lecture).
- [ ] Le secret libvirt de `client.cinder` sur chaque calcul est identique à la configuration de Kolla ; la configuration Ceph de `cinder-volume` désigne les moniteurs de `ceph-par1`.
- [ ] Le volume de test est attaché (contrôle à lancer **avant** `--annuler`) ; ton journal ne contient aucune clé.

**Vérification** : `lab/bin/check 10 38` (avant `--annuler`)

<details><summary>Indice 1</summary>

`openstack volume show m10-e38-vol -c status -c attachments`, `openstack volume service list`, puis `sudo grep <req-id> /var/log/kolla/nova/nova-compute.log` sur le calcul (`openstack server show m10-e38-sonde -c OS-EXT-SRV-ATTR:host`) et `/var/log/kolla/cinder/cinder-volume.log` sur `osctl01`. Les erreurs librados (`(1) Operation not permitted`, `(13) Permission denied`, `(110) Connection timed out`, `(113) No route to host`) ne désignent pas le même problème.
</details>

<details><summary>Indice 2</summary>

Test direct depuis `osctl01` : `sudo docker exec cinder_volume rbd --id cinder -p volumes ls` (les images Kolla de Cinder embarquent normalement le client Ceph), puis une création et une suppression d'image de test (`rbd create --size 1 volumes/essai-e38`, `rbd rm`). Sur un calcul : `sudo docker exec nova_libvirt virsh secret-list`, et compare l'empreinte de `virsh secret-get-value <uuid>` à celle de la clé de `client.cinder` (`ceph auth get-key client.cinder` sur `ceph01`).
</details>

<details><summary>Indice 3</summary>

Des droits Ceph modifiés se voient par différence avec la référence versionnée (M08) : `ceph auth get client.cinder` contre ton dépôt `plateforme/ceph`. Le journal d'audit des moniteurs (`ceph log last … audit`) garde les commandes `auth caps` récentes.
</details>

**Pour aller plus loin** : écris une sonde « attachement » qui, chaque nuit, crée un volume de 1 Gio, l'attache à une instance témoin, écrit et relit un bloc, puis nettoie. [Kolla-Ansible : Ceph externe](https://docs.openstack.org/kolla-ansible/latest/reference/storage/external-ceph-guide.html), [Ceph : OpenStack et RBD](https://docs.ceph.com/en/latest/rbd/rbd-openstack/).

---

### M10-E39 — Panne : plus personne ne s'authentifie  `BF` `★★★`

> **Ticket INC-3745** — *De : Nadia Roussel*
> Alerte P1 à 7 h 40 : les équipes ne peuvent plus se connecter au cloud. *(Le détail — ce qui échoue en CLI et dans Horizon — s'affiche à l'injection.)* Les instances déjà lancées tournent. InfoGér est intervenu hier soir sur `osctl01` (« contrôle de conformité »), sans ticket de changement.

**Objectifs pédagogiques**
- Décomposer une authentification : client (`clouds.yaml`, `keystoneauth`) → HAProxy (VIP) → Keystone (uWSGI) → base (via ProxySQL et MariaDB) → émission d'un jeton **fernet** (clés dans le volume `keystone_fernet_tokens`) ; côté Horizon, sessions dans **memcached**.
- Lire le code HTTP comme un instrument (401, 403, 500, 503) et l'associer à un étage ; distinguer un problème d'identifiants d'un problème de service.
- Comprendre la rotation des clés fernet (`keystone_fernet`, `keystone_ssh`) et ce qu'elle implique en multi-contrôleurs.

**Prérequis** : M10-E05, M10-E17, M10-E24, M10-E27 ; `lab/bin/check 10 39` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : Keystone tourne dans le conteneur `keystone` ; `keystone_fernet` fait la rotation des clés (tâche planifiée) et les synchronise entre contrôleurs avec `keystone_ssh` ; tous trois partagent le volume Docker `keystone_fernet_tokens`. Les conteneurs Kolla ont un **état de santé** (`docker ps`, colonne STATUS ; `docker inspect --format '{{json .State.Health}}' <conteneur>`). Les mots de passe des services sont dans `passwords.yml` (chiffré) de ton dépôt.

**Injection** : `lab/bin/break 10 39` (3 variantes).

**Travail demandé**
1. Reproduis avec `openstack --debug token issue` (sans montrer le jeton ni le mot de passe dans ton journal) et avec Horizon. Note le code HTTP exact et qui l'a renvoyé (HAProxy ou Keystone ?).
2. Liste les conteneurs de `osctl01` qui ne sont pas sains. Lis le journal de Keystone (`/var/log/kolla/keystone/`) au moment de ton essai, et celui de HAProxy si besoin.
3. Trouve la modification responsable (date des fichiers sous `/etc/kolla/keystone/`, propriétaire et droits des fichiers du volume des clés fernet, état des conteneurs) et la façon dont elle a été faite.
4. Corrige à la racine. Si un mot de passe est en cause, la source de vérité est `passwords.yml` : n'écris aucun mot de passe en clair ailleurs, ne le passe pas en argument de commande, et utilise Kolla pour le reposer.
5. Prouve le retour en CLI **et** dans Horizon, avec un compte de chaque projet. Explique dans ton journal pourquoi les instances n'ont rien vu, et ce qui se serait passé pour un pipeline OpenTofu qui tournait pendant la panne.

**Critères de réussite**
- [ ] Les clouds `medisphere-admin` et `medisphere-plateforme` obtiennent un jeton ; la page de connexion d'Horizon répond 200 avec le certificat de la PKI.
- [ ] `keystone`, `keystone_fernet`, `memcached` et `horizon` sont en service et sains ; les clés fernet appartiennent au compte du service.
- [ ] Ton journal associe le code HTTP initial à l'étage fautif et ne contient aucun secret.

**Vérification** : `lab/bin/check 10 39`

<details><summary>Indice 1</summary>

503 vient presque toujours de HAProxy (aucun serveur sain derrière) ; 500 vient de l'application, qui a planté en traitant la requête (sa pile d'appels est dans son journal) ; 401 dit que Keystone a fonctionné et t'a refusé. Une connexion Horizon qui échoue alors que la CLI marche désigne ce qu'Horizon utilise **en plus** de Keystone.
</details>

<details><summary>Indice 2</summary>

`sudo docker ps --filter health=unhealthy`, `sudo docker volume inspect keystone_fernet_tokens` (champ `Mountpoint`), `sudo ls -ln <mountpoint>` ; dans le conteneur : `sudo docker exec keystone ls -l /etc/keystone/fernet-keys/`. `find /etc/kolla -newer <fichier témoin>` liste ce qui a changé depuis un repère.
</details>

**Pour aller plus loin** : lis la page de Kolla sur la rotation des mots de passe (`password-rotation`) et rédige la procédure de rotation du mot de passe de base de Keystone pour MédiSphère (fenêtre, ordre, retour arrière). [Keystone : FAQ des jetons fernet](https://docs.openstack.org/keystone/latest/admin/fernet-token-faq.html), [Kolla-Ansible : rotation des mots de passe](https://docs.openstack.org/kolla-ansible/latest/admin/password-rotation.html).

---

### M10-E40 — Panne : les calculs sont « down »  `BF` `★★★`

> **Ticket INC-3746** — *De : Nadia Roussel*
> La sonde `ms-verif-openstack` est rouge depuis 6 h 15 : « nova-compute down » sur `oscmp01` et `oscmp02`. Les instances existantes répondent encore, mais aucune création ni migration n'aboutit, et la console d'une instance ne s'ouvre plus. Les deux VMs de calcul sont démarrées et répondent en SSH.

**Objectifs pédagogiques**
- Comprendre comment Nova décide qu'un service est `up` : compte rendu périodique (`report_interval`) par RPC vers `nova-conductor`, comparé à `service_down_time` ; tout passe par **RabbitMQ**.
- Diagnostiquer une rupture AMQP : conteneur, journal de `nova-compute`, état de santé, connexions vues par RabbitMQ (`rabbitmqctl list_connections`), connectivité TCP, filtrage local.
- Savoir pourquoi les instances survivent à un calcul « down » et ce qui ne marche plus (toute opération qui passe par l'agent).

**Prérequis** : M10-E19, M10-E24, M10-E26 ; `lab/bin/check 10 40` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : RabbitMQ tourne dans le conteneur `rabbitmq` de `osctl01` (file *quorum*, utilisateur des services `openstack`) ; les services s'y connectent directement (pas par HAProxy), sur l'adresse OS-API de `osctl01`, port 5672 (5671 si tu as activé TLS au M10-E27). `rabbitmqctl` se lance dans le conteneur `rabbitmq`. L'état de santé du conteneur `nova_compute` vérifie justement sa connexion au port AMQP.

**Injection** : `lab/bin/break 10 40` (3 variantes ; la détection par Nova prend jusqu'à 3 minutes).

**Travail demandé**
1. Mesure l'étendue : `compute service list`, `network agent list`, `volume service list`. Seuls les calculs sont-ils touchés ? Que dit le champ `Updated At` ?
2. Sur un calcul : état du conteneur `nova_compute` (en service ? sain ?), dernières lignes de `/var/log/kolla/nova/nova-compute.log`. Côté `osctl01` : RabbitMQ voit-il des connexions venant des calculs ?
3. Teste le transport hors de Nova : connexion TCP du calcul vers le port AMQP de `osctl01` ; règles de filtrage locales du calcul. Si la connexion passe, regarde ce que le serveur RabbitMQ répond (son journal).
4. Corrige à la racine, par la voie durable (dépôt et Kolla, ou suppression d'une règle avec explication de son origine). Vérifie ensuite qu'aucune instance n'est restée dans un état transitoire (`BUILD`, `deleting`, tâche en cours) ou en `ERROR` à cause de la panne, et traite-la proprement.
5. Prouve le retour : les deux calculs `up` ; une instance de test se crée puis se supprime sur chacun (choisis l'hôte, par exemple avec `--availability-zone nova:<hôte>` en administrateur).

**Critères de réussite**
- [ ] Les deux `nova-compute` sont `enabled up`, leurs conteneurs `nova_compute` et `nova_libvirt` sont sains.
- [ ] Chaque calcul joint RabbitMQ en TCP et aucune règle locale ne rejette l'AMQP.
- [ ] Ton journal contient le délai entre la cause et l'apparition de « down », et l'explication de ce délai.

**Vérification** : `lab/bin/check 10 40`

<details><summary>Indice 1</summary>

`sudo docker ps -a --filter name=nova_` (STATUS, *health*), puis `sudo tail -n 50 /var/log/kolla/nova/nova-compute.log`. Les messages d'`oslo.messaging` sont explicites : `ACCESS_REFUSED` (identifiants), `Connection refused` ou `reset` (réseau, filtrage), aucun message (le processus ne tourne pas).
</details>

<details><summary>Indice 2</summary>

Sur `osctl01` : `sudo docker exec rabbitmq rabbitmqctl list_connections user peer_host state` et `/var/log/kolla/rabbitmq/`. Sur un calcul : `timeout 3 bash -c '</dev/tcp/10.10.50.51/5672' && echo ouvert`, `sudo nft list ruleset`.
</details>

**Pour aller plus loin** : la sonde `ms-verif-openstack` a vu la panne deux fois : par le contrôle des conteneurs `unhealthy` (M10-E26), avant Nova et sans attendre `service_down_time`, puis par l'état des services. Compare les heures des deux alertes dans le journal de `adm01`, et ajoute-lui un contrôle des connexions AMQP vues par RabbitMQ (`rabbitmqctl list_connections`) : un calcul sans connexion est un calcul qui sera bientôt « down ». [Nova : groupes de service](https://docs.openstack.org/nova/latest/admin/service-groups.html), [RabbitMQ : connexions](https://www.rabbitmq.com/docs/connections).

---

### M10-E41 — Panne : l'envoi d'image échoue  `BF` `★★`

> **Ticket INC-3747** — *De : Julien Petit*
> Je n'arrive plus à envoyer d'image dans Glance : l'image reste « queued » ou « saving », puis la commande échoue ou n'en finit pas. Les images existantes démarrent normalement. Mon essai de cette nuit, `m10-e41-sonde` (200 Mio, raw, projet `plateforme`), est toujours là.

**Objectifs pédagogiques**
- Connaître le chemin d'un envoi : client → HAProxy → `glance-api` (contrôles de taille et de quota) → pilote RBD (`client.glance`, pool `images`) → Ceph.
- Lire le code HTTP de Glance et les erreurs du magasin (`glance_store`), puis vérifier Ceph (santé, quotas de pool, droits et clé du client).
- Comprendre pourquoi « les images existantes démarrent » ne prouve rien sur l'écriture.

**Prérequis** : M10-E06, M10-E10 ; M08-E20 (quotas et seuils) ; `lab/bin/check 10 41` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : la configuration de Glance est dans `/etc/kolla/glance-api/` sur `osctl01` (fichier principal, et sous-dossier `ceph/` : `ceph.conf` et trousseau de `client.glance`). `openstack image create --file` fait deux appels : création de l'enregistrement, puis envoi des données ; un échec du second laisse une image `queued` ou `saving`.

**Injection** : `lab/bin/break 10 41` (3 variantes ; l'injection envoie un fichier de 200 Mio).

**Travail demandé**
1. Reproduis avec un fichier de 200 Mio (`head -c 200M /dev/urandom > /tmp/essai.raw`) et `openstack --debug image create … --file …`. Note le code HTTP de l'envoi (le `PUT …/file`), ou le fait qu'il n'en revienne aucun.
2. Lis le journal de `glance-api` au moment de l'essai. L'erreur vient-elle de Glance lui-même ou du magasin RBD ?
3. Si le magasin est en cause, vérifie Ceph depuis `ceph01` : santé détaillée, quotas du pool `images`, droits et clé de `client.glance` (empreintes), et depuis `osctl01` un accès direct au pool avec le trousseau de Glance.
4. Corrige à la racine, puis nettoie les images restées en `queued`/`saving` (les tiennes et celle de Julien) et refais l'envoi de 200 Mio.

**Critères de réussite**
- [ ] Un envoi de 200 Mio aboutit (`active`) ; aucune image ne reste en `queued`, `saving` ou `importing` dans le projet `plateforme`.
- [ ] Aucun plafond de taille d'image sous 10 Gio ; le pool `images` n'est pas plein et son quota (s'il existe) laisse de la marge ; la clé de `client.glance` de Glance est celle du cluster.

**Vérification** : `lab/bin/check 10 41`

<details><summary>Indice 1</summary>

413 : Glance a refusé la taille (réglage de Glance ou quota). 500 ou 503 avec une trace `glance_store` / `rbd` : le magasin a échoué. Pas de réponse du tout : l'écriture est **suspendue** quelque part en dessous.
</details>

<details><summary>Indice 2</summary>

Sur `ceph01` : `sudo cephadm shell -- ceph health detail`, `… ceph osd pool get-quota images`, `… ceph df`. Sur `osctl01` : `sudo docker exec glance_api rbd --id glance -p images ls | head` (si l'outil `rbd` est présent dans l'image ; sinon, teste depuis `ceph01` avec une copie du trousseau, puis supprime-la). `ls -l --time-style=full-iso /etc/kolla/glance-api/ /etc/kolla/glance-api/ceph/` date chaque fichier.
</details>

**Pour aller plus loin** : passe les quotas d'images en **limites unifiées** de Keystone (`use_keystone_limits`) et compare avec le quota de pool Ceph : qui doit plafonner quoi ? [Glance : quotas](https://docs.openstack.org/glance/latest/admin/quotas.html), [Ceph : quotas de pool](https://docs.ceph.com/en/latest/rados/operations/pools/#setting-pool-quotas).

---

### M10-E42 — Panne : le tableau de bord est inaccessible  `BF` `★★`

> **Ticket INC-3748** — *De : Sophie Laurent*
> Je dois montrer le tableau de bord du cloud à l'auditeur HDS à 10 h, et `https://openstack.par1.medisphere.internal` ne fonctionne plus. *(Ce que voit l'utilisateur s'affiche à l'injection.)* Hier, InfoGér a « préparé le renouvellement des certificats et la répartition de charge ».

**Objectifs pédagogiques**
- Situer Horizon dans l'architecture de Kolla : keepalived (VIP) → HAProxy (TLS, frontaux et serveurs par service, fichiers `/etc/kolla/haproxy/services.d/`) → conteneur `horizon` (port 8080) → Keystone.
- Distinguer en une mesure les quatre familles de pannes d'un point d'entrée : pas de réponse, TLS refusé, 503 (pas de serveur), erreur de l'application.
- Lire la configuration **chargée** par HAProxy et l'état de ses serveurs.

**Prérequis** : M10-E17, M10-E24, M10-E27 ; M06-E37 (diagnostic TLS) ; `lab/bin/check 10 42` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : le certificat externe (émis par step-ca, M10-E04/E27) est fourni par ton dépôt et déposé par Kolla dans `/etc/kolla/haproxy/` sur `osctl01`, puis copié dans le conteneur `haproxy` au démarrage. L'adresse d'administration de HAProxy (statistiques) dépend de ta configuration (M10-E24).

**Injection** : `lab/bin/break 10 42` (4 variantes).

**Travail demandé**
1. Depuis `adm01`, qualifie la panne en une commande `curl -v` (sans `-k`) et une commande `openssl s_client` : connexion, TLS, code HTTP. Teste aussi une API (`openstack token issue`) : la panne touche-t-elle seulement Horizon ?
2. Sur `osctl01`, vérifie dans l'ordre : VIP présentes (`ip -br addr`), conteneurs (`keepalived`, `haproxy`, `horizon`), état des serveurs vu par HAProxy, certificat réellement servi.
3. Trouve ce qui a changé (dates, différence avec ce que produit ton dépôt) et corrige par la voie durable. Ne contourne jamais la vérification TLS.
4. Prouve le retour : page de connexion en 200 avec la chaîne de la PKI MédiSphère, connexion d'un utilisateur, API joignables par les deux VIP.

**Critères de réussite**
- [ ] `https://openstack.par1.medisphere.internal/auth/login/` répond 200 depuis `adm01`, certificat émis par l'intermédiaire MédiSphère et chaîne complète.
- [ ] Les VIP 10.10.50.200 et 10.10.50.201 répondent ; `horizon`, `haproxy` et `keepalived` sont en service.
- [ ] Ton journal associe la première mesure (code, erreur TLS ou délai) à l'étage fautif.

**Vérification** : `lab/bin/check 10 42`

<details><summary>Indice 1</summary>

`curl -sv https://openstack.par1.medisphere.internal/auth/login/ -o /dev/null` : arrêt avant `Connected to` (rien n'écoute, ou plus d'adresse), arrêt dans la négociation TLS (`SSL certificate problem: …`), ou réponse HTTP avec un code. Trois étages, trois endroits où regarder.
</details>

<details><summary>Indice 2</summary>

`sudo docker logs --tail 20 haproxy`, `sudo docker exec haproxy cat /etc/haproxy/services.d/horizon.cfg` (ce qui est chargé) contre `/etc/kolla/haproxy/services.d/horizon.cfg` (ce que Kolla a produit) ; `openssl x509 -noout -issuer -subject -dates` sur le certificat servi et sur celui de ton dépôt.
</details>

**Pour aller plus loin** : ajoute à `ms-verif-openstack` une sonde HTTPS qui vérifie **aussi** l'émetteur et la date d'expiration du certificat servi (alerte à J-10), et une sonde par VIP. [Kolla-Ansible : TLS](https://docs.openstack.org/kolla-ansible/latest/admin/tls.html), [HAProxy : configuration](https://docs.haproxy.org/3.2/configuration.html).

---

### M10-E43 — Astreinte : le cloud en détresse  `BF` `★★★★`

> **Ticket INC-3750** — *De : Nadia Roussel (responsable astreinte)* — priorité P2
> Tu es d'astreinte. Mardi, 6 h 50 : plusieurs remontées sur le cloud (le détail s'affiche à l'injection). L'équipe MédiAgenda lance sa campagne de recette à 9 h : elle a besoin de créer des instances, des volumes et des IP flottantes. Tiens-moi informée toutes les 30 minutes. Ensuite, le post-mortem, et le runbook que je réclame depuis le début : « que faire quand une instance est en ERROR », pour que le support de niveau 1 sache trier sans toi.

**Objectifs pédagogiques**
- Gérer un incident à causes multiples sur une plateforme à couches : trier, prioriser par dépendances (accès et authentification avant le reste), éviter qu'une panne en masque une autre.
- Communiquer pendant l'incident (statut, impact, prochaine étape, prochaine communication).
- Transformer l'expérience des pannes en un **runbook** utilisable par quelqu'un qui n'a pas fait ce module.

**Prérequis** : M10-E35 à M10-E42 (au moins une variante de chacun) ; M10-E22 (format des runbooks RB-10x).
**Durée indicative** : 2 h de rétablissement + 1 h de post-mortem et de runbook.

**Contexte technique** : le script tire **deux** pannes distinctes parmi celles de M10-E35 à M10-E42 (variantes aléatoires) et les injecte ensemble ; l'injection peut prendre 10 à 15 minutes. Les symptômes peuvent se recouvrir ou s'amplifier (un Keystone en panne empêche de voir un calcul « down » par l'API ; une VIP absente masque tout). `--variante N` (1 à 27) force la paire, pas les variantes. `--annuler` retire les deux et supprime les ressources de test.

**Injection** : `lab/bin/break 10 43`

**Travail demandé**
1. **Triage (10 min max)** : liste les symptômes, leur impact métier (qui ne peut plus faire quoi ?) et une hypothèse de regroupement. Vérifie d'abord tes instruments : SSH vers chaque nœud, jeton Keystone, VIP, `ceph -s`. Envoie la première communication.
2. **Diagnostic** : traite les pannes dans un ordre que tu justifies par les dépendances entre services. Tiens ton journal horodaté.
3. **Rétablissement** : corrige chaque cause racine ; après chaque correction, relance **tous** tes tests de départ (`lab/bin/check 10 35` à `10 42` donnent la carte).
4. **Clôture** : communication de fin d'incident, `--annuler` pour clore, post-mortem rédigé à partir de `modules/00-lab/ressources/M00-E46/modele-post-mortem.md` dans `docs/cloud/post-mortems/AAAA-MM-JJ-INC-3750.md`, publié par MR.
5. **Runbook RB-103 « Instance en ERROR ou injoignable »** dans `docs/cloud/runbooks/RB-103-instance-en-erreur.md`, au format des RB-10x : déclencheurs, prérequis et accès, arbre de tri (création en ERROR et `No valid host` ; IP flottante muette ; instance sans sa configuration ; volume qui ne s'attache pas ; jeton refusé), commandes de diagnostic de niveau 1 (lecture seule) puis gestes de niveau 2, critères d'escalade, ce qu'il ne faut **jamais** faire, vérification finale.

**Critères de réussite**
- [ ] Toutes les vérifications de M10-E35 à M10-E42 sont vertes (le contrôle les rejoue toutes) et aucune panne n'est encore marquée active.
- [ ] Le post-mortem existe, est commité, et contient une chronologie horodatée, les deux causes racines, l'analyse de la détection et des actions correctives avec responsable et échéance.
- [ ] RB-103 existe, est commité et couvre les cinq branches de tri ; le journal contient au moins trois communications espacées d'environ 30 minutes.

**Vérification** : `lab/bin/check 10 43`

<details><summary>Indice 1</summary>

L'ordre des dépendances du cloud : accès aux nœuds → VIP et HAProxy → Keystone → RabbitMQ et base → services de contrôle → agents (calcul, réseau, métadonnées) → stockage Ceph → ressources des projets. Une panne plus bas dans la pile fausse tous les tests au-dessus.
</details>

<details><summary>Indice 2</summary>

Pour RB-103, pars de tes huit journaux de diagnostic : pour chaque panne, quelle **première** commande t'aurait orienté en moins de 5 minutes ? Ce sont elles, l'arbre de tri. Un runbook de niveau 1 ne contient aucune commande qui modifie quoi que ce soit.
</details>

**Pour aller plus loin** : fais-toi injecter une astreinte par quelqu'un d'autre (`--variante` tirée par lui), et fais appliquer RB-103 par une personne qui n'a pas fait le module, sans aide : chaque question qu'elle te pose est un défaut du runbook.

---

### M10-E44 — Sous le capot : la vie d'un `server create`  `LAB` `★★★`

> **Ticket PLAT-1180** — *De : Karim Benali*
> Pendant les pannes, tu as appris à suivre un identifiant de requête. Je veux maintenant la carte complète : un `openstack server create`, de la commande jusqu'au processus QEMU, service par service, avec ce que chacun écrit en base, sur RabbitMQ, dans OVN et dans libvirt. Compte rendu pour les prochains arrivants, et pour l'équipe support.

**Objectifs pédagogiques**
- Reconstituer la séquence d'une création d'instance : authentification, `nova-api` (contrôles, quotas, enregistrement), `nova-conductor`, `nova-scheduler` et **Placement** (candidats, allocations), `nova-compute` (réclamation des ressources, image depuis Ceph, port Neutron), Neutron et **OVN** (port logique, liaison au *chassis*, flux), libvirt et QEMU (XML du domaine, disques RBD, interface `tap`).
- Distinguer l'identifiant de requête **local** (`req-…` de chaque service) de l'identifiant **global** transmis entre services (en-tête `X-OpenStack-Request-ID`), et les retrouver dans les journaux.
- Relier chaque étape à une panne du palier (et à une commande de diagnostic).

**Prérequis** : M10-E35 à M10-E42 ; M10-E20 (surcharges et journaux de Kolla).
**Durée indicative** : 3 h.

**Contexte technique**
- Instance de traçage : `m10-e44-trace` dans le projet `plateforme`, gabarit `m1.petit`, image Debian 13, sur un réseau du projet (le tien, ou un réseau temporaire que tu supprimeras).
- Niveau de détail : par défaut, les services journalisent en `INFO`. Pour voir les filtres du scheduler et les appels RPC, passe temporairement `nova-scheduler` (et au besoin `nova-conductor`, `nova-api`) en `debug` **par Kolla** (surcharge dans `etc/kolla/config/`, ou variable de journalisation du service dans `globals.yml`, puis `kolla-ansible reconfigure -t nova`), et reviens en arrière à la fin.
- OVN : `docker exec ovn_northd ovn-nbctl …` et `ovn-sbctl …` sur `osctl01`. libvirt : `docker exec nova_libvirt virsh …` sur le calcul de l'instance.

> ⚠️ **Attention** : `openstack --debug` affiche les en-têtes des requêtes, dont **ton jeton** (`X-Auth-Token`) et parfois des données d'authentification. Ne colle jamais une sortie brute dans le compte rendu : masque le jeton (`X-Auth-Token: {SHA256}…` ou `***`) et relis avant de commiter. Un passage en `debug` augmente fortement le volume des journaux : reviens au niveau normal dans la journée.

**Travail demandé**
1. **La commande.** Crée l'instance avec `openstack --debug server create … --wait`. Dans la sortie, retrouve l'appel d'authentification, l'appel `POST /v2.1/servers` et la réponse : code HTTP, en-têtes `x-openstack-request-id` et `x-compute-request-id`. Pourquoi la réponse arrive-t-elle avant que l'instance existe vraiment ?
2. **Le plan de contrôle.** Avec cet identifiant, suis la requête dans `nova-api`, `nova-conductor`, `nova-scheduler` (candidats Placement, filtres, poids, hôte choisi), puis `nova-compute` sur l'hôte choisi. Dans `placement-api`, retrouve la demande de candidats et l'écriture des allocations (identifiant global). Relève l'**ordre** et les **horodatages** : où le temps est-il passé ?
3. **Le réseau.** Dans `neutron-server`, retrouve la création (ou la mise à jour) du port et sa liaison (`binding:host_id`) ; quel identifiant global porte-t-elle ? Dans OVN : le port logique (`ovn-nbctl show`, `lsp-get-addresses`), sa liaison au *chassis* du calcul (`ovn-sbctl show`, table `Port_Binding`), et sur le calcul l'interface `tap…` dans `br-int` (`ovs-vsctl`, champ `external_ids:iface-id`).
4. **L'hyperviseur.** Sur le calcul : `virsh list`, `virsh dumpxml` du domaine. Repère le disque RBD (pool, image, moniteurs, utilisateur, UUID du secret), l'interface et son pont, les métadonnées Nova. Retrouve l'image RBD de l'instance dans le pool `vms` depuis `ceph01`, et son parent dans `images` (clone copie-sur-écriture).
5. **Nettoyage.** Supprime l'instance, suis la suppression de la même façon (brièvement), vérifie que le port OVN, l'image RBD et les allocations Placement ont disparu, et remets la journalisation au niveau normal par Kolla.
6. **Compte rendu.** Rédige `docs/cloud/analyses/vie-d-un-server-create.md` : `## Requête et identifiants`, `## Plan de contrôle` (séquence annotée, extraits de journaux), `## Réseau` (Neutron et OVN), `## Hyperviseur` (libvirt, QEMU, Ceph), un schéma de séquence (texte ou Mermaid), puis `## Réponses aux questions`.

**Questions d'analyse** (à traiter dans le compte rendu)
1. Pourquoi `nova-api` répond-il `202 Accepted` et pas `201 Created` ? Que contient la réponse, et comment la CLI attend-elle avec `--wait` ?
2. À quel moment les ressources sont-elles **réservées** dans Placement (avant ou après le choix de l'hôte), et pourquoi ce choix évite-t-il les courses entre deux ordonnanceurs ?
3. Que se passe-t-il si `nova-compute` échoue à construire l'instance sur l'hôte choisi ? Que sont le *reschedule* et les hôtes alternatifs, et pourquoi n'y en a-t-il qu'un nombre limité ?
4. Quel service crée le port quand tu passes `--network` ? Quand passe-t-il `ACTIVE`, et pourquoi Nova attend-il un événement de Neutron (`network-vif-plugged`) avant de démarrer l'instance ?
5. Avec OVN, qui programme les flux sur le calcul, à partir de quoi ? Pourquoi n'y a-t-il plus d'agent L3 ni d'agent DHCP Neutron ?
6. Dans le XML du domaine, pourquoi le disque est-il de type `network` et pas un fichier ? Que se passerait-il si l'image Glance était en qcow2 dans Ceph ?
7. Cite, pour quatre pannes de M10-E35 à M10-E42, la ligne de journal ou la commande de ta trace qui l'aurait localisée en moins de cinq minutes.

**Critères de réussite**
- [ ] Le compte rendu existe, est commité, contient les sections demandées avec des extraits annotés (identifiant `req-…`, `nova-scheduler`, `nova-conductor`, Placement, `ovn-nbctl`, `ovn-sbctl`, `virsh`) et ne contient aucun jeton.
- [ ] Les 7 questions sont traitées.
- [ ] L'instance de traçage est supprimée et la journalisation de `nova-api`, `nova-scheduler` et `nova-conductor` est revenue hors `debug`.

**Vérification** : `lab/bin/check 10 44`

<details><summary>Indice 1</summary>

`openstack server event list m10-e44-trace` puis `server event show m10-e44-trace <req-id>` donnent l'identifiant et les étapes vues par Nova. `sudo grep -h <req-id> /var/log/kolla/nova/*.log | sort` sur `osctl01` met déjà les lignes du plan de contrôle dans l'ordre ; le format des lignes (`[<global> <local> <utilisateur> <projet> …]`) dit quel identifiant est lequel.
</details>

<details><summary>Indice 2</summary>

Neutron et Placement journalisent l'identifiant **global** reçu de Nova à côté de leur propre `req-…` : cherche l'identifiant de Nova dans `/var/log/kolla/neutron/neutron-server.log` et `/var/log/kolla/placement/`. Côté OVN : `ovn-nbctl find Logical_Switch_Port name=<id du port>` ; côté calcul, `ovs-vsctl --columns=name,external_ids find Interface external_ids:iface-id=<id du port>`.
</details>

**Pour aller plus loin** : active OSProfiler (`enable_osprofiler`) sur une copie de ta configuration, ou lis comment il fonctionne, et compare une trace distribuée à ta reconstitution à la main ; c'est la même idée que les traces OpenTelemetry du module 23. [Nova : flux de création d'instance](https://docs.openstack.org/nova/latest/reference/), [Placement : modèle](https://docs.openstack.org/placement/latest/user/index.html), [OSProfiler](https://docs.openstack.org/osprofiler/latest/).

---

### M10-E45 — Questions expert : OpenStack  `Q` `★★★`

> **Ticket PLAT-1181** — *De : Karim Benali*
> Dernière étape avant la recette du cloud v1 : ces questions, je les pose en entretien pour un poste d'ingénieur cloud senior. Réponds par écrit, en argumentant. Pas de recherche pendant la première passe ; vérifie ensuite dans la documentation et corrige-toi en couleur.

**Objectifs pédagogiques**
- Consolider la compréhension des mécanismes internes manipulés dans ce module (planification, réseau OVN, stockage Ceph, identité, messagerie, déploiement par Kolla).
- S'entraîner à argumenter une réponse technique comme en entretien ou en revue d'architecture.

**Prérequis** : paliers 1 à 3 du module, M10-E44.
**Durée indicative** : 2 h 30.

**Questions**

1. Décris le rôle de Placement : fournisseurs de ressources, classes de ressources, inventaires (`total`, `reserved`, `allocation_ratio`, `min_unit`, `max_unit`, `step_size`), allocations, traits, agrégats. Pourquoi Nova l'a-t-il sorti de son code ?
2. QCM — Une création échoue en « No valid host ». Le journal du scheduler dit « Got no allocation candidates from the Placement API ». La cause **ne peut pas** être :
   a) un gabarit qui exige un trait absent ; b) un `reserved_host_memory_mb` trop élevé sur tous les calculs ; c) une image avec `hw_architecture` incompatible ; d) tous les calculs pleins en VCPU au ratio configuré.
3. Explique la différence entre `cpu_allocation_ratio` réglé dans `nova.conf` et `initial_cpu_allocation_ratio`, et pourquoi la valeur vue dans Placement peut différer de celle du fichier.
4. Avec ML2/OVN, que remplacent `ovn-northd`, les bases NB et SB et `ovn-controller` par rapport à ML2/OVS (agents L3, DHCP, métadonnées, OVS) ? Qu'est-ce qui reste un agent Neutron, et pourquoi ?
5. Explique ce qu'est le *gateway chassis* d'un routeur OVN, comment OVN choisit entre plusieurs candidats (priorités, BFD) et ce que change l'option des IP flottantes distribuées (`neutron_ovn_distributed_fip`).
6. QCM — Le réseau de tunnel est en MTU 9000 et Neutron est configuré avec `global_physnet_mtu = 9000` (sans `path_mtu`). Quel MTU Neutron donne-t-il à un nouveau réseau de projet Geneve, et que se passe-t-il si on oublie de régler `global_physnet_mtu` ?
   a) 9000 ; b) 8942 (9000 moins l'en-tête maximal Geneve et IPv4) ; c) 1500 ; d) 1450.
7. Décris le chemin d'une requête de métadonnées avec OVN, et explique comment le service de métadonnées de Nova sait **quelle** instance l'interroge (en-têtes ajoutés, signature HMAC, secret partagé).
8. Explique les jetons fernet : contenu, chiffrement, absence de persistance, rôle des clés primaire, secondaires et en attente (*staged*), et la règle qui fixe `max_active_keys`. Que se passe-t-il, en multi-contrôleurs, si un contrôleur n'a pas reçu la dernière rotation ?
9. QCM — Dans le lab, l'horloge de `osctl01` dérive de 10 minutes alors que les calculs restent à l'heure. Qu'est-ce qui casse **d'abord** ?
   a) toutes les validations de jetons fernet ; b) rien d'immédiat côté jetons (un seul contrôleur émet et valide), mais les journaux ne se corrèlent plus entre nœuds et tout ce qui compare des dates venues de deux hôtes devient faux ; c) RabbitMQ refuse les connexions des calculs ; d) Ceph passe en `HEALTH_ERR`.
10. Pourquoi Kolla-Ansible impose-t-il des files *quorum* pour RabbitMQ 4 ? Que garantissent-elles, que coûtent-elles, et que devient une file *quorum* sur un seul nœud ?
11. Comment Nova décide-t-il qu'un `nova-compute` est `down` ? Pourquoi une instance survit-elle à un calcul « down », et qu'est-ce qu'`evacuate` exige pour être sûr (isolation, `--force-down`) ?
12. Dans Kolla-Ansible, que fait réellement `kolla-ansible reconfigure` sur un nœud, et en quoi diffère-t-il de `deploy` et de `deploy-containers` ? Comment Kolla sait-il qu'un conteneur doit être recréé ?
13. Pourquoi une modification manuelle d'un fichier de `/etc/kolla/<service>/` survit-elle à un redémarrage du conteneur mais pas à un `reconfigure` ? Comment détecterais-tu ce type de dérive automatiquement ?
14. Explique le chemin d'un attachement de volume RBD (Cinder `attachment`, `initialize_connection`, `connection_info`, secret libvirt) et pourquoi deux clients Ceph distincts (`client.nova`, `client.cinder`) sont utilisés.
15. Pourquoi les images doivent-elles être au format **raw** dans Glance sur Ceph pour bénéficier des clones copie-sur-écriture ? Quel est le rôle de `show_image_direct_url` (ou `show_multiple_locations`) et quel risque de sécurité porte-t-il ?
16. QCM — Un pool Ceph atteint son quota `max_bytes`. Que constate un client RBD qui écrit dedans ?
   a) les écritures échouent toutes immédiatement avec `ENOSPC` ; b) le pool est marqué plein, les écritures sont suspendues (ou refusées avec `EDQUOT` selon le client et ses options), les lectures continuent ; c) Ceph supprime les objets les plus anciens ; d) rien, le quota n'est qu'indicatif.
17. Le fournisseur OVN d'Octavia : que fournit-il, que ne fournit-il pas (L7, TLS, contrôles de santé) par rapport à amphora, et comment choisirais-tu pour MédiAgenda ?
18. *Secure RBAC* : explique les rôles `reader`, `member`, `manager` (et `admin`), la portée projet / domaine / système, et ce que changent `enforce_scope` et `enforce_new_defaults`. Pourquoi la transition a-t-elle pris plusieurs versions ?
19. Comparer la haute disponibilité du plan de contrôle à un nœud (le lab) et à trois nœuds : MariaDB/Galera, RabbitMQ, HAProxy/keepalived, memcached, OVN NB/SB (RAFT). Qu'est-ce qui exige un nombre **impair** de nœuds, et pourquoi ?
20. Une montée de version d'OpenStack (2026.1 → 2026.2) : quelles étapes et vérifications prévois-tu avec Kolla-Ansible (versions supportées, base, *online data migrations*, ordre des services, Ceph, retour arrière) ? Pourquoi ne la fait-on pas tant que la série Kolla correspondante n'est pas publiée ?

**Critères de réussite**
- [ ] Les 20 questions ont une réponse écrite et argumentée (pour les QCM : la bonne réponse **et** pourquoi les autres sont fausses).
- [ ] Après correction, tu as identifié tes trois points les plus faibles et noté un exercice ou une lecture pour chacun.

<details><summary>Indice 1</summary>

Pour 1 à 3 et 11, la documentation de Nova (*Scheduling*, *Allocation ratios*, *Service groups*) et de Placement ; pour 4 à 7, la documentation de Neutron sur OVN (architecture, routage, métadonnées, MTU) ; pour 8 et 18, la documentation de Keystone (*Fernet FAQ*, *Service API protection*).
</details>

<details><summary>Indice 2</summary>

Pour 10, 12, 13, 19 et 20, la documentation de Kolla-Ansible (*Operating Kolla*, *Production architecture guide*, *RabbitMQ*) ; pour 14 à 16, la documentation de Ceph (*Block devices and OpenStack*, *Pools*) et ta trace de M10-E44.
</details>

**Pour aller plus loin** : choisis trois questions et transforme chacune en mini-démonstration sur le lab (5 minutes, reproductible), à présenter à Karim.
