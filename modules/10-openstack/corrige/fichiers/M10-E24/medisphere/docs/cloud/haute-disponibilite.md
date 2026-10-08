# Haute disponibilité du cloud OpenStack

> Propriétaire : équipe Plateforme. Créé par PLAT-1150 (M10-E24). Mesures du 2026-10-20 sur le lab (Kolla-Ansible 22.2.0, OpenStack 2026.1, un contrôleur). Valeurs **indicatives** du lab de référence : remplace-les par tes mesures.

## 1. Réponse au comité de direction

Si le serveur de contrôle `osctl01` tombe :
- les serveurs de MédiAgenda **continuent de tourner** et de se parler entre eux, leurs disques (Ceph) restent accessibles ;
- ils deviennent **injoignables depuis l'extérieur de leur réseau** (adresses publiques internes, « IP flottantes ») et ne peuvent plus sortir vers Internet ;
- plus personne ne peut créer, modifier ou supprimer quoi que ce soit (API, tableau de bord, pipelines) ;
- retour à la normale **≈ 6 minutes** après le redémarrage du serveur (mesuré), sans intervention si l'arrêt a été propre ; jusqu'à 15 minutes si la base doit être reprise à la main.

Avec trois contrôleurs (≈ 48 Go de mémoire, non disponibles sur le lab), la perte d'un serveur ne couperait que quelques secondes à quelques dizaines de secondes (bascule de l'adresse d'accès et de la passerelle réseau).

## 2. Cartographie (un contrôleur, deux calculs)

| Catégorie | Conteneurs (nœud) | Données | Rôle |
|---|---|---|---|
| Point d'entrée | `keepalived`, `haproxy` (`osctl01`) | aucune | VIP 10.10.50.200 (interne) et .201 (externe), VRID 150 ; répartition vers les API |
| API sans état | `keystone`, `glance_api`, `nova_api`, `nova_metadata`, `placement_api`, `neutron_server`, `cinder_api`, `heat_api`, `heat_api_cfn`, `octavia_api`, `horizon` (`osctl01`) | aucune (configuration générée) | Plan de contrôle |
| Ordonnancement et travailleurs | `nova_scheduler`, `nova_conductor`, `nova_novncproxy`, `cinder_scheduler`, `cinder_volume`, `cinder_backup`, `heat_engine`, `octavia_driver_agent`, `octavia_health_manager`… (`osctl01`) | aucune | Plan de contrôle |
| Services à état | `mariadb` + `proxysql` ; `rabbitmq` ; `ovn_nb_db`, `ovn_sb_db` (+ relais Sud), `ovn_northd` ; `memcached` ; `keystone_fernet` (`osctl01`) | volumes Docker `mariadb`, `rabbitmq`, `ovn_nb_db`, `ovn_sb_db`, `keystone_fernet_tokens` | Mémoire du cloud |
| Plan de données | `nova_compute`, `nova_libvirt`, `nova_ssh`, `openvswitch_vswitchd`, `openvswitch_db`, `ovn_controller`, `neutron_ovn_metadata_agent` (`oscmp01-02`) | volumes `nova_compute`, `libvirtd`, `openvswitch_db` ; disques dans Ceph (`vms`) | Fait vivre les instances |
| Passerelle réseau | `ovn_controller` + `openvswitch_*` sur `osctl01` (*gateway chassis*, `br-ex` sur `ens21`) | — | SNAT et IP flottantes (non distribuées) |
| Outils | `kolla_toolbox`, `cron`, `fluentd` (tous) | journaux (`kolla_logs`) | Exploitation |

## 3. Points d'entrée

- keepalived : `virtual_router_id 150`, annonces **multicast** (`keepalived_traffic_mode` par défaut), priorité unique (un seul nœud), script de surveillance `check_alive_haproxy.sh` : si HAProxy ne répond plus, le nœud perd sa priorité… mais il n'y a pas d'autre nœud : les VIP restent, sans personne derrière.
- VRID : un VRID de 50 aurait été le même que celui des passerelles `gw01`/`gw02` sur le VLAN 50 (M07). Deux groupes VRRP au même VRID sur un même segment se prennent pour un seul : annonces rejetées pour « adresses virtuelles différentes », bascules erratiques de la **passerelle** du VLAN 50. Symptôme visible : messages de keepalived (*received an invalid ip count*) des deux côtés, et `tcpdump -ni ens18 vrrp` qui montre deux émetteurs pour le même VRID.
- HAProxy (statistiques sur 10.10.50.51:1984) : les API écoutent sur la VIP interne (catalogue `internal`) **et** sur la VIP externe (catalogue `public`) ; Horizon sur l'externe (443) ; les bases (MariaDB par ProxySQL) et RabbitMQ ne passent **pas** par HAProxy.

## 4. Services à état

| Service | À un nœud | À trois nœuds |
|---|---|---|
| MariaDB (Galera) | `wsrep_cluster_size = 1`, `Synced` ; ProxySQL (dans chaque nœud de contrôle) répartit les connexions des services et choisit l'écrivain | quorum 2/3 ; une perte tolérée ; deux pertes → plus d'écriture (Galera se met en non-primaire) |
| RabbitMQ 4.2 | un nœud ; files **quorum** (obligatoires depuis Kolla 2026.1) sauf les files de réponse et de diffusion exclusives, restées *classic* (ou *stream* pour la diffusion : `om_enable_rabbitmq_stream_fanout`) | files quorum répliquées (Raft) sur 3 ; une perte tolérée |
| OVN Nord / Sud | cluster Raft d'un membre, chef = lui-même | 3 membres, une perte tolérée ; relais Sud pour les calculs |
| memcached | cache des jetons validés ; sa perte coûte des validations supplémentaires, pas de panne | un par contrôleur, clients configurés sur les trois |
| Jetons Fernet | non stockés ; validés par les clés de `keystone_fernet_tokens` | clés synchronisées par `keystone_fernet` (rsync sur `keystone_ssh`) |

Un jeton émis juste avant la panne reste valide après (rien n'est perdu : il est autoporteur), tant que les clés Fernet n'ont pas changé.

## 5. Mesures

Instances `ha-essai01` (oscmp01, IP flottante) et `ha-essai02` (oscmp02) ; sondes `outils/mesure-continuite.sh` de `plateforme/openstack` : ping de l'IP flottante (nord-sud), ping privé de `ha-essai01` vers `ha-essai02` (est-ouest), jeton Keystone toutes les 5 s (API).

| Panne | Nord-sud (IP flottante) | Est-ouest | API (jetons) | Autres effets | Reprise mesurée |
|---|---|---|---|---|---|
| `docker stop haproxy`, 2 min | aucune coupure | aucune coupure | coupure 2 min 05 (toutes les API) | Horizon inaccessible ; VIP restées sur `ens18` | 5 s après `docker start` |
| `docker stop rabbitmq`, 3 min | aucune | aucune | jetons OK (Keystone n'utilise pas RabbitMQ) ; `server list` OK ; `server create` bloqué en `BUILD` puis `ERROR` | `nova-compute` « down » après ~60 s (`service_down_time`) ; agents OVN restés vivants (pas de RabbitMQ) | services `up` 1 min 40 après le redémarrage (reconnexions) ; l'instance en `ERROR` est à supprimer |
| `qm stop 2101` (arrêt brutal), 5 min | **coupure totale** (passerelle OVN sur `osctl01`) | aucune coupure | coupure totale | sessions SSH par IP flottante coupées ; instances en marche ; aucune nouvelle IP DHCP… mais OVN répond aux DHCP localement (`ovn-controller`), donc les baux sont renouvelés | VM démarrée à T+5 min ; IP flottante à T+6 min 10 ; API à T+7 min 30 ; MariaDB redémarrée seule (arrêt brutal sans écriture en cours) |

À retenir : le **plan de données est-ouest** survit à la perte complète du contrôleur ; le **nord-sud** non, parce que la passerelle des routeurs OVN est sur le même nœud que le plan de contrôle.

## 6. Passer à trois contrôleurs (plan, non réalisé)

Inventaire de référence : `plateforme/openstack`, `inventaire/multinode.3-controleurs.exemple`.

| Besoin | Valeur | Remarque |
|---|---|---|
| VMs | `osctl01-03` (VMID 2101, et deux VMID libres à réserver hors 2102-2103), 4 vCPU, 16 Go chacun | 48 Go pour le seul contrôle : au-delà du profil openstack (≈ 48 Go au total) |
| Adresses | OS-API 10.10.50.51, .54, .55 ; OS-TUN .51, .54, .55 ; STOR-PUB 10.10.30.61, .64, .65 ; carte OS-EXT sur chacun | dans la plage « nœuds de clusters » (.50-.99) |
| `globals.yml` | inchangé pour l'essentiel (mêmes VIP, VRID 150) ; `keepalived_traffic_mode: unicast` recommandé (cohérence avec M07) | Kolla calcule les membres Galera, RabbitMQ, OVN depuis l'inventaire |
| Ordre | `bootstrap-servers --limit control`, `pull --limit` des nouveaux, `deploy --limit control` (procédure *Adding new controllers*) ; vérifier Galera (taille 3), RabbitMQ (3 nœuds), OVN (3 membres Raft) | une étape à la fois, avec sauvegarde vérifiée |
| Passerelle | `network` = les trois contrôleurs : OVN répartit les priorités des *gateway chassis* ; bascule par BFD entre châssis (secondes) | alternative : IP flottantes distribuées sur les calculs (`neutron_ovn_distributed_fip`) — carte externe sur chaque calcul |

Ce que trois contrôleurs ne protègent **pas** : la perte de `ceph-par1` (disques des instances), la bordure (`gw01`/`gw02`), `pve01` lui-même (toutes les VMs du lab sont dessus), une erreur de configuration poussée par Kolla sur les trois nœuds, une base corrompue (répliquée fidèlement sur les trois) — d'où la sauvegarde (E25).
