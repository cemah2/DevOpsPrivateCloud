# RB-103 — Instance en ERROR ou injoignable

| | |
|---|---|
| **Périmètre** | Cloud OpenStack PAR1 (`openstack.par1.medisphere.internal`), projets des équipes |
| **Public** | Niveau 1 : support et astreinte (lecture seule) · Niveau 2 : équipe Plateforme |
| **Déclencheurs** | Ticket « mon instance est en ERROR », « No valid host », « IP flottante muette », « ma clé SSH est refusée sur une nouvelle instance », « mon volume ne s'attache pas », « je ne peux plus me connecter au cloud » ; alerte de `ms-verif-openstack` |
| **Durée** | Tri de niveau 1 : 15 min au plus, puis escalade |
| **Propriétaire** | Équipe Plateforme (Nadia Roussel pour le support) — revue à chaque post-mortem du cloud |
| **Liens** | RB-100 (accueillir une équipe), RB-101 (mise à jour), RB-102 (évacuer un nœud de calcul), ADR-0100 (réseau et répartiteurs) |

## 1. Prérequis et accès

- Poste : `adm01`. CLI `openstack` (avec le greffon `osc-placement` pour le niveau 2).
- Niveau 1 : un cloud de `~/.config/openstack/clouds.yaml` lié à un compte qui n'a que le rôle `reader` sur les projets des équipes (M10-E23), noté ici `<CLOUD-LECTURE>`. Jamais le compte d'administration.
- Niveau 2 : cloud `medisphere-admin`, accès SSH à `osctl01`, `oscmp01`, `oscmp02` (compte nominatif, `sudo`), accès en lecture à Ceph par `ceph01`.
- Ouvre un journal d'intervention (heure, commande, constat) dans le ticket. **N'y colle jamais** de jeton, de mot de passe, de clé Ceph ni de sortie brute de `--debug`.

## 2. Premier tri (niveau 1, lecture seule, 5 min)

```
admin@adm01:~$ export OS_CLOUD=<CLOUD-LECTURE>
admin@adm01:~$ openstack token issue -f value -c expires            # le cloud m'authentifie-t-il ?
admin@adm01:~$ openstack server show <INSTANCE> --os-project-name <PROJET> -c status -c fault -c addresses -c OS-EXT-STS:task_state
admin@adm01:~$ openstack server event list <INSTANCE> --os-project-name <PROJET>
```

`<INSTANCE>` et `<PROJET>` : nom ou identifiant donnés par le demandeur. Note dans le ticket le `status`, le `fault.message` s'il existe et le **Request ID** de la dernière action (colonne de `server event list`) : c'est ce que le niveau 2 cherchera dans les journaux.

| Ce que tu vois | Branche |
|---|---|
| `token issue` échoue (erreur 5xx, délai, certificat refusé) | §3.5 Authentification et accès |
| `status: ERROR`, `fault.message: No valid host was found` | §3.1 Planification |
| `status: ACTIVE`, IP flottante sans réponse | §3.2 IP flottante |
| `status: ACTIVE`, ping OK, clé refusée, nom d'hôte faux | §3.3 Métadonnées |
| Volume `attaching`/`reserved` puis `available` | §3.4 Volumes |
| `status: ERROR` avec un autre message | §4 Escalade directe (joindre le message et le Request ID) |

## 3. Arbre de tri

### 3.1 Planification : « No valid host was found »

Niveau 1 :
```
admin@adm01:~$ openstack quota show <PROJET> --usage            # un quota dépassé donne un 403 explicite, pas ce message
admin@adm01:~$ openstack flavor show <GABARIT> -c vcpus -c ram -c disk -c properties
admin@adm01:~$ openstack image show <IMAGE> -c properties
```
Un gabarit plus gros que les calculs (8 Go chacun), une propriété `trait:…=required` ou une image avec `hw_architecture` autre que `x86_64` : escalade niveau 2 avec ces sorties.

Niveau 2 :
1. `sudo grep -h <REQ-ID> /var/log/kolla/nova/nova-scheduler.log /var/log/kolla/nova/nova-conductor.log` sur `osctl01`.
2. « Got no allocation candidates » → `openstack compute service list --long` (services désactivés ? raison ?), `openstack resource provider inventory list <uuid>` (`reserved`, `allocation_ratio`), `resource provider usage show`, `allocation candidate list --resource VCPU=…,MEMORY_MB=…,DISK_GB=…`.
3. « Filter results … (start: N, end: 0) » → le filtre nommé (propriétés d'image, affinité de groupe, zone).
4. Correction au bon endroit : API (réactivation d'un service dont la maintenance est close **et documentée**), code (gabarits et propriétés d'images sous OpenTofu et pipeline), configuration (dépôt `plateforme/openstack` puis `kolla-ansible reconfigure -t nova`).

### 3.2 IP flottante sans réponse

Niveau 1 :
```
admin@adm01:~$ ping -c 3 <IP-FLOTTANTE>
admin@adm01:~$ openstack port list --server <INSTANCE> -c ID -c Status -c "Fixed IP Addresses"
admin@adm01:~$ openstack port show <PORT> -c security_group_ids -c status
admin@adm01:~$ openstack security group rule list <GROUPE>
admin@adm01:~$ openstack console log show <INSTANCE> | tail -n 30
```
Aucune règle d'entrée pour ICMP/SSH depuis le réseau de l'entreprise : c'est un réglage du projet, à corriger par l'équipe (par son code). Sinon : escalade, avec mention « une seule instance » ou « plusieurs projets » (essaie une autre IP flottante connue).

Niveau 2 : plusieurs projets touchés = chemin nord-sud commun, sur `osctl01` (passerelle OVN) :
```
admin@osctl01:~$ sudo docker exec openvswitch_vswitchd ovs-vsctl get open . external_ids:ovn-bridge-mappings
admin@osctl01:~$ sudo docker exec openvswitch_vswitchd ovs-vsctl list-ports br-ex
admin@osctl01:~$ ip -br link show <INTERFACE-EXTERNE>
admin@osctl01:~$ sudo docker exec ovn_northd ovn-nbctl lrp-get-gateway-chassis lrp-<ID-PORT-PASSERELLE>
admin@osctl01:~$ sudo tcpdump -eni <INTERFACE-EXTERNE> 'icmp or arp' -c 10
```
⚠️ Prendre un instantané de `osctl01` (`ms-snapshot 2101`) avant toute modification de son Open vSwitch ou de ses interfaces. Correction durable : `kolla-ansible reconfigure -t openvswitch,ovn-controller`.

### 3.3 Instance sans sa configuration (métadonnées)

Niveau 1 :
```
admin@adm01:~$ openstack console log show <INSTANCE> | grep -iE 'cloud-init|datasource|169.254' | head
admin@adm01:~$ openstack network agent list --agent-type ovn-metadata      # (cloud de lecture : si autorisé)
```
Note le code HTTP (403, 502, 503) ou le délai. Escalade niveau 2.

Niveau 2 : conteneurs `neutron_ovn_metadata_agent` (calculs) et `nova_metadata` (`osctl01`) en service et sains ; empreintes du secret partagé identiques (jamais les valeurs) ; journaux `/var/log/kolla/neutron/neutron-ovn-metadata-agent.log` et `/var/log/kolla/nova/nova-metadata.log`. Après correction : `openstack server reboot <INSTANCE>` suffit en général pour que `cloud-init` applique la configuration.

### 3.4 Volume qui ne s'attache pas

Niveau 1 :
```
admin@adm01:~$ openstack volume show <VOLUME> -c status -c attachments
admin@adm01:~$ openstack server event list <INSTANCE>        # action attach_volume et son Request ID
```
Escalade niveau 2 avec le Request ID. **Ne jamais** forcer l'état d'un volume.

Niveau 2 : `openstack volume service list` ; `nova-compute.log` du calcul de l'instance et `cinder-volume.log` de `osctl01` ; droits de `client.cinder` (`ceph auth get client.cinder` sur `ceph01`, comparés à `plateforme/ceph`) ; empreinte du secret libvirt de `client.cinder` sur chaque calcul contre `ceph auth get-key client.cinder` ; moniteurs de `/etc/kolla/cinder-volume/ceph/ceph.conf`.

### 3.5 Authentification et accès

Niveau 1 :
```
admin@adm01:~$ curl -sv -o /dev/null https://openstack.par1.medisphere.internal/auth/login/ 2>&1 | grep -E 'Connected|SSL certificate|HTTP/'
admin@adm01:~$ openstack --os-cloud <CLOUD-LECTURE> token issue -f value -c expires
```
Pas de connexion (délai) → VIP absentes ; erreur de certificat → certificat servi ; 503 → service derrière HAProxy ; Horizon seul en échec → sessions (memcached). Escalade **immédiate** (P1 : toutes les équipes sont touchées).

Niveau 2 : sur `osctl01`, `ip -br addr` (VIP 10.10.50.200 et .201), `sudo docker ps --filter health=unhealthy`, `sudo docker ps -a --filter status=exited`, `sudo docker logs --tail 20 haproxy`, `/var/log/kolla/keystone/keystone.log`. Corrections par Kolla (`reconfigure -t keystone|loadbalancer|horizon`) ; un conteneur arrêté se relance (`docker start`), puis on cherche qui l'a arrêté.

## 4. Escalade

- Niveau 1 → niveau 2 : au bout de 15 min, ou immédiatement si plusieurs projets sont touchés, si l'authentification est en panne, ou si `ms-verif-openstack` est rouge. Joindre : sorties du §2, branche suivie, Request ID, heure de début.
- Niveau 2 → astreinte Plateforme senior (Karim Benali) : cause non trouvée en 45 min, panne touchant Ceph (`ceph -s` hors `HEALTH_OK`), ou intervention nécessaire sur la bordure (`gw01`/`gw02`).
- Communication : toutes les 30 min dans `#astreinte` (statut, impact, prochaine étape, prochaine communication).

## 5. Ne jamais faire

- Évacuer (`evacuate`) les instances d'un calcul « down » sans avoir prouvé qu'il est arrêté ou isolé (RB-102) : deux copies de la même instance corrompent son disque.
- Régénérer ou supprimer une clé Ceph (`ceph auth get-or-create-key`, `ceph auth del`) ou les clés fernet de Keystone.
- Forcer l'état d'une instance ou d'un volume (`server set --state`, `volume set --state`) pour « débloquer » un ticket.
- Désactiver la vérification TLS (`-k`, `--insecure`, `verify: false`).
- Modifier un fichier de `/etc/kolla/` sur un nœud sans reporter la correction dans le dépôt `plateforme/openstack`.
- Redémarrer RabbitMQ, MariaDB ou `nova_libvirt` « pour voir ».
- Coller un secret (mot de passe, clé, jeton, sortie de `--debug`) dans un ticket ou un canal.

## 6. Vérification finale

- [ ] Le demandeur confirme que son action fonctionne (création, IP flottante, clé, volume, connexion).
- [ ] `ms-verif-openstack` est vert ; aucun conteneur `unhealthy` ni arrêté sur les nœuds.
- [ ] Une instance de test `m1.petit` se crée et se supprime dans le projet `plateforme`.
- [ ] Le ticket contient la cause, la correction, la référence du changement (MR) et, si nécessaire, la demande de post-mortem.
