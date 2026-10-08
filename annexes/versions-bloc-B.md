# Versions du bloc B et changements de comportement

> Relevé fait le 8 octobre 2026 au démarrage du bloc B (modules 07 à 11), à partir des sources officielles (pages de releases, registres, dépôts APT, notes de version). Les versions de référence sont dans [`PLAN.md`](../PLAN.md) §6. Ce fichier liste ce qui a changé récemment et qui touche les exercices : si un tutoriel plus ancien ne fonctionne plus, la raison est probablement ici. Les lignes marquées *(relecture)* ont été établies pendant la relecture du bloc, dans le code source des outils ou par des essais, et sont détaillées dans le corrigé cité.

## Réseau et haute disponibilité (module 07)

| Outil | Ce qui change pour toi |
|---|---|
| FRR 10.7 (deb.frrouting.org) | Debian 13 livre la 10.3 : le workbook utilise le dépôt FRR (`deb [signed-by=/usr/share/keyrings/frrouting.gpg] https://deb.frrouting.org/frr trixie frr-10`). `bgp ebgp-requires-policy` (RFC 8212) est actif par défaut : une session eBGP sans route-map en entrée **et** en sortie n'échange **aucune** route (piège n° 1 des tutoriels). Depuis 10.5 : AS_SET rejeté par défaut (RFC 9774), capacité *link-local next-hop* IPv6 désactivée par défaut, configuration des journaux passée par mgmtd. 10.7 : authentification BFD par *keychain*, poids ECMP sur les routes statiques. |
| HAProxy 3.2 LTS | Debian 13 livre la 3.0 ; le workbook prend la 3.2 (haproxy.debian.net, `trixie-backports-3.2`). 3.2 : client ACME en aperçu, mot-clé `ssl-f-use`, *pacing* QUIC actif. La 3.4 LTS (2026) ajoute les backends dynamiques par la CLI et un dossier `conf.d` : non utilisée ici. |
| keepalived 2.3 | Paquet Debian. VRRP v3 conseillé ; les annonces **unicast** (`unicast_peer`) évitent le multicast sur le LAN maison. |
| keepalived 2.3 — groupes de synchronisation *(relecture)* | `keepalived -t` **refuse** (code 5) un `vrrp_sync_group` d'une seule instance (« Sync group … has only 1 virtual router(s) ») : un gabarit ne rend un groupe qu'à partir de deux membres. Au rechargement, un groupe n'est `MASTER` que si **tous** ses membres l'étaient : ajouter une instance (état initial `BACKUP`) à un groupe déjà maître fait repasser **tout** le groupe en `BACKUP` et retire toutes les VIP de l'hôte pendant ≈ 3 s. Méthode : retirer le groupe, ajouter l'instance hors groupe, recréer le groupe quand tous ses membres sont dans le même état (M07-E25, corrigé du palier 3). |
| Open vSwitch 3.5 | Paquet Debian (amont 3.7). |
| Pont Linux et LACP | Un pont Linux ne relaie pas les trames 802.3ad (adresse réservée 01:80:c2:00:00:02, non débloquable par `group_fwd_mask`) : pas de LACP entre deux VMs à travers `vmbr1`. Le workbook le pratique dans une VM, entre espaces de noms. |
| WireGuard | Module noyau ; `wireguard-tools` 1.0.20210914 (Debian), 1.0.20250521 en backports : aucune différence pour les exercices. |

## Stockage distribué (module 08)

| Outil | Ce qui change pour toi |
|---|---|
| Ceph Tentacle 20.2 | Debian 13 n'est **pas** un hôte supporté (ni paquets download.ceph.com pour trixie, ni hôte de conteneurs testé) ; Rocky Linux 10 l'est depuis 20.2.2 : les nœuds Ceph du workbook sont en Rocky 10. Le paquet `cephadm` de Debian est en 18.2 (Reef) : ne pas l'utiliser. Le workbook installe les RPM signés `cephadm` et `ceph-common` du dépôt `https://download.ceph.com/rpm-20.2.x/el10/` (aucune somme n'est publiée pour le binaire seul récupéré par `curl`). |
| Tentacle 20.2.0 | Plugin EC par défaut : **ISA-L** (au lieu de Jerasure) pour les nouveaux pools ; FastEC activable par pool (`allow_ec_optimizations`) ; modules mgr `restful` et `zabbix` supprimés ; `rbd device map` en msgr2 par défaut ; RGW : IAM au niveau *tenant* déprécié au profit des **accounts** ; `osd_repair_during_recovery` supprimé ; seuils d'IOPS mClock bas ; nouveaux services cephadm `mgmt-gateway`, `oauth2-proxy`, `certmgr`, module SMB. |
| Tentacle 20.2.1-20.2.4 | Tableau de bord : « Dashboard » devient « Overview » ; onglet global des rôles RGW déplacé sous Accounts ; 20.2.4 corrige CVE-2025-30156 (CephX) et CVE-2026-54330 (RGW SigV4) avec des étapes de mise à jour particulières (M08-E26). |
| iSCSI | La passerelle iSCSI de Ceph (`ceph-iscsi`) n'est plus maintenue ; l'export bloc moderne est NVMe-oF. Le workbook montre l'iSCSI avec LIO (`targetcli`) sur un client RBD. |
| cephadm 20.2 — simulation *(relecture)* | `ceph orch apply --dry-run` n'est **pas** une simulation pour les spécifications d'hôtes : seules les spécifications de **services** sont marquées « aperçu » ; une spécification `host` (ajout d'hôte, étiquettes, `location`) est appliquée même avec `--dry-run`. On relit le fichier et on lance `ceph cephadm check-host` avant d'appliquer (M08-E18, M08-E23). |
| cephadm 20.2 — `ceph orch upgrade check` *(relecture)* | Ne fait tirer (ou inspecter) l'image que par **un seul** hôte de l'inventaire : il ne prouve pas que chaque nœud peut télécharger l'image. Pré-tirer l'image sur tous les nœuds avant une montée (M08-E26). |
| Tentacle 20.2.4 — cephx `aes256k` *(relecture)* | Le correctif de CVE-2025-30156 introduit un **nouveau type de clé** cephx, `aes256k` ; les clés existantes restent de l'ancien type `aes` tant qu'on ne les renouvelle pas. Les clients de Debian 13 (noyau 6.12, `ceph-common` 18.2 Reef, non corrigé) ne gèrent pas `aes256k` (l'avis le donne pour le client noyau à partir de Linux 7.0) : le type préféré reste `aes`, seules les clés des démons et de `client.admin` passent en `aes256k`, les clés clientes restent datées en sourdine temporaire (M08-E26, M08-E27 ; hypothèse à confirmer sur ton lab). |

## Cluster de virtualisation (module 09)

| Outil | Ce qui change pour toi |
|---|---|
| Proxmox VE 9.0 | **HA groups dépréciés au profit des HA rules** (affinité nœud et ressource) ; migration automatique quand tous les nœuds sont en 9, `nofailback` devient `failback`. Fabrics SDN OpenFabric et OSPF. GlusterFS et `maxfiles` supprimés. Privilège `VM.Monitor` supprimé, `VM.Replicate` ajouté. |
| Proxmox VE 9.0-9.1 | Fichier de réponse de l'installateur automatique : clés en *kebab-case* (acceptées depuis 8.4, le *snake_case* est déprécié depuis 9.0). |
| Proxmox VE 9.2 | Ceph **Tentacle** par défaut pour les nouvelles installations (Squid toujours proposé) ; équilibrage dynamique par le CRS ; commandes `disarm-ha`/`arm-ha` ; SDN : fabrics WireGuard et BGP, route-maps ; installateur : `prepare-iso --pxe`, `--answer-auth-token`, `inspect-iso`, fichiers de réponse JSON préférés en HTTP ; **`VM.PowerMgmt` requis pour démarrer une VM après création ou restauration** (à vérifier pour les jetons d'automatisation). |
| PBS 4.2 | Pas de changement bloquant pour les exercices. |

## OpenStack (module 10)

| Outil | Ce qui change pour toi |
|---|---|
| Kolla-Ansible 22 (2026.1) | Première série qui supporte **Debian 13** comme hôte ; exige ansible-core ≥ 2.19.1 et **< 2.21** (environnement `uv` séparé). Défauts : `kolla_base_distro: rocky`, `neutron_plugin_agent: openvswitch` (**OVN n'est pas le défaut**), Docker, Octavia désactivé. Supprimés : Zun, Kuryr, InfluxDB/Telegraf, Venus, **mécanisme Linux Bridge de Neutron**. Le rôle `common` devient `kolla_toolbox`. Toutes les API sous uWSGI. RabbitMQ 4.2 avec files *quorum* obligatoires. |
| Kolla-Ansible 21 (2025.2) | ProxySQL activé avec MariaDB ; Valkey remplace Redis ; Horizon sur le port 8080 derrière HAProxy. |
| Kolla-Ansible 22 — inventaire *(relecture)* | `cinder-volume` et `cinder-backup` suivent le groupe d'inventaire **`cinder`** (enfant de `control`) dans l'inventaire d'exemple 2026.1, et non plus `storage` comme le montre encore la page *External Ceph* : un inventaire ancien les place ailleurs (M10-E03, M10-E10). |
| Kolla-Ansible 22 — ACME (rôle `letsencrypt`) *(relecture)* | Malgré son nom, `letsencrypt_cert_valid_days` ne règle **pas** le seuil de renouvellement : le script du conteneur le passe à lego en `--cert.timeout` (délai d'obtention, en secondes), et `lego renew` garde son seuil par défaut (30 jours). Avec des certificats de 30 jours, chaque passage du `cron` (toutes les 4 h par défaut) renouvelle : on règle la **fréquence** par `letsencrypt_cron_renew_schedule` (M10-E27). |
| Kolla-Ansible 22 — HAProxy *(relecture)* | Dès que le TLS externe est actif (`kolla_enable_tls_external`), HAProxy écoute le **port 80** de la VIP externe (*frontend* de redirection d'Horizon vers HTTPS, et défi ACME servi par `letsencrypt_webserver`) : un défi HTTP-01 hors de Kolla ne peut plus y être servi ; la première émission se fait avant le déploiement (M10-E04, M10-E17, M10-E27). |
| OpenStack 2026.2 « Hibiscus » | Sortie le 30/09/2026, mais Kolla-Ansible seulement en RC : non utilisée. |
| Provider OpenStack 3.x | Supprimés en 3.0 : `openstack_compute_floatingip_associate_v2`, `openstack_compute_floatingip_v2`, `openstack_compute_secgroup_v2` ; utiliser `openstack_networking_floatingip_v2`, `openstack_networking_floatingip_associate_v2`, `openstack_networking_secgroup_v2`. |

## Provisioning bare-metal (module 11)

| Outil | Ce qui change pour toi |
|---|---|
| MAAS 3.7 | Snap (`3.7/stable`) + PostgreSQL 16 ; Ubuntu 24.04 comme système hôte. Pilote d'alimentation **Proxmox** (adresse, `user@realm`, jeton `user!jeton`, identifiant de VM) corrigé en 3.7.0 (bogue 2109681). |
| Tinkerbell | Déploiement recommandé par chart Helm sur Kubernetes : traité en fiche (Kubernetes arrive au module 14). |
| iPXE | Amont 2.0 (Secure Boot par shim, TLS 1.0 retiré) ; Debian 13 livre un instantané de 2025 sans ces changements. Le workbook construit iPXE 2.0 avec la racine MédiSphère embarquée pour démarrer en HTTPS (M11-E13). |
| iPXE — racines de confiance *(relecture)* | `TRUST=` remplace la racine par défaut mais n'embarque que son **empreinte** ; `CERT=` embarque le certificat **complet**. Si le serveur ne présente pas la racine (cas de `pxe01`, qui sert la feuille et l'intermédiaire), il faut **les deux** (`TRUST=racine CERT=racine`), sinon iPXE cherche un certificat croisé sur `ca.ipxe.org` et échoue (« Permission denied ») (M11-E13). |
| Kea 3.0 | Classes PXE : test sur l'option 93 (architecture du client : `0x0000` BIOS, `0x0007`/`0x0009` UEFI x64), puis classe iPXE (option 77 *user-class*). |
| iLO 4 | Redfish 1.0 à partir du firmware 2.30 ; firmware 2.82 conseillé. Virtual Media et console graphique exigent la licence iLO Advanced. Les émulateurs Redfish (`sushy-tools`) ne pilotent que libvirt ou Nova, pas Proxmox. |
