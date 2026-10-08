# Sécurité du cloud OpenStack

> Propriétaire : équipe Plateforme. Revue SEC-1153 (Sophie Laurent), remédiations M10-E27. Revoir à chaque montée de série et après chaque nouveau service activé.

## 1. Constats et remédiations

| # | Constat (SEC-1153) | Preuve avant | Remédiation | Preuve après |
|---|---|---|---|---|
| 1 | API internes en clair sur le VLAN 50 | `openstack endpoint list --interface internal` : `http://openstack-int…` | TLS de la VIP interne (`kolla_enable_tls_internal`), racine MédiSphère copiée dans les conteneurs, `openstack_cacert` | points `internal` en `https://` ; `openssl s_client` sur 10.10.50.200:5000 vérifié par la racine |
| 2 | Certificat externe posé à la main | `certificates/haproxy.pem` (certificat et clé, chiffré par Vault) obtenu à la main par `step ca certificate --standalone` (M10-E04), 30 jours : renouvellement manuel | Rôle ACME de Kolla (`letsencrypt_lego`) pointé vers `ca01`, renouvellement à 15 jours | `verifier-tls-vip.sh` avant/après : nouvelle date de début, nouvelle empreinte ; `haproxy.pem` retiré du dépôt |
| 3 | Pas de verrouillage, sessions Horizon longues | `keystone.conf` sans `[security_compliance]` ; Horizon : `SESSION_TIMEOUT` par défaut (3 600 s) | Verrouillage 5 échecs / 15 min, comptes de service dispensés ; sessions de 30 min | compte `essai-verrou` verrouillé au 6ᵉ essai (HTTP 401 avec le bon mot de passe pendant 15 min), puis supprimé |
| 4 | Instances → plan de contrôle ? | depuis `secu-essai01` : `nc -vz 10.10.50.200 5000` **ouvert**, `nc -vz 10.10.50.51 3306` **ouvert** (règle de test large posée en M10-E12) | Matrice `pare_feu.yml` : rien du VLAN 52 vers le VLAN 50 ; API externe pour MGMT, VPN d'admin, `runner01` ; ACME | depuis l'instance : délai dépassé vers .200, .51 ; `deb.debian.org` joint ; compteur `nft-fwd-drop` incrémenté sur `gw01` |
| 5 | Mots de passe d'installation jamais tournés | `git log --format=%ad -- etc/kolla/passwords.yml` : création seule | Rotation de `keystone_admin_password` et `glance_database_password` (`kolla-genpwd` sur les clés vidées, `reconfigure`) | ancien mot de passe d'`admin` refusé ; `glance image list` fonctionne ; MR chiffrée |

## 2. Ce qui reste en clair, et pourquoi

| Flux | État | Raison | Échéance |
|---|---|---|---|
| RabbitMQ (services ↔ `rabbitmq`, port 5672) | clair | `rabbitmq_enable_tls` demande certificats par nœud et redéploiement de tous les services ; flux interne au VLAN 50, nœuds seuls | avec les trois contrôleurs ou F6 |
| HAProxy → services (*backend*) | clair | `kolla_enable_tls_backend` : un certificat par nœud et par service ; un seul nœud, même machine pour HAProxy et les API du contrôleur | avec les trois contrôleurs |
| Migration à chaud libvirt (calcul ↔ calcul) | clair (TCP, SASL) | `libvirt_tls` à mettre en place ; flux limité au VLAN 50 | F6 |
| Bases OVN Nord/Sud (6641/6642, relais) | clair | Kolla 2026.1 : TLS d'OVN non activé ici (à évaluer) | F6 |
| Ceph (STOR-PUB, msgr2) | authentifié (cephx), non chiffré | mode `secure` de msgr2 coûteux en CPU ; VLAN 30 dédié au stockage | décision M08 |
| Tunnels Geneve (OS-TUN) | clair | VLAN 51 non routé, dédié | — |

Risque accepté par Sophie Laurent le JJ/MM/AAAA, sous condition : aucun hôte autre que les nœuds OpenStack et Ceph sur les VLAN 30, 50 et 51 (vérifié dans NetBox).

## 3. Certificats

- VIP externe `openstack.par1.medisphere.internal` (10.10.50.201) et interne `openstack-int.par1.medisphere.internal` (10.10.50.200) : step-ca, provisioner `acme`, 30 jours, renouvelés quand il reste moins de 15 jours (`letsencrypt_cert_valid_days: "15"`), tentatives toutes les 4 h par `letsencrypt_lego` (journal `/var/log/kolla/letsencrypt/letsencrypt-lego.log` sur `osctl01`).
- Flux nécessaires : `osctl01` → `ca01:443` (ACME) ; `ca01` → 10.10.50.200 et .201 port 80 (défi HTTP-01, servi par `letsencrypt_webserver` derrière HAProxy).
- Supervision : `ms-verif-openstack` (alerte à 10 jours, E26).
- Alternative si le client ACME de Kolla devait échouer avec step-ca : obtention sur `adm01` par `step ca certificate` (provisioner `acme`, défi **DNS-01** par l'API de PowerDNS) dans un service systemd, dépôt dans `etc/kolla/certificates/` hors Git et `reconfigure -t loadbalancer` ; à documenter ici avec le message d'erreur exact s'il est retenu.

## 4. Comptes et secrets

| Élément | Règle |
|---|---|
| Comptes humains (domaine `medisphere`) | verrouillage 5 échecs / 15 min ; fédération Keycloak au module 24 |
| Comptes de service (domaine `Default`) | dispensés du verrouillage (`ignore_lockout_failure_attempts`) : `nova`, `neutron`, `glance`, `cinder`, `placement`, `heat`, `octavia`, `svc-supervision` — liste revue à chaque service activé (`outils/dispenser-comptes-service.sh` affiche les oublis) |
| `passwords.yml` | chiffré (Vault `critique`) ; rotation annuelle des secrets « simples » (liste de la page *Password Rotation* de Kolla : `*_keystone_password`, `*_database_password` sauf `nova_database_password`, `keystone_admin_password`, `keepalived_password`, `metadata_secret`…) par `kolla-genpwd` + `reconfigure` |
| Secrets à procédure manuelle | `database_password` (racine MariaDB), `nova_database_password` (cellules), `rabbitmq_password` et `rabbitmq_cluster_cookie` (arrêt de tous les services, destruction des volumes RabbitMQ, `deploy`), `heat_domain_admin_password`, `kolla_ssh_key` : planifiés en fenêtre, une procédure chacun |
| Identifiants d'application | rôle minimal, règles d'accès quand c'est possible (sonde : GET seulement), expiration pour ceux des équipes (E31), inventoriés au registre des secrets |

## 5. Rotation réalisée (SEC-1153)

```
admin@adm01:~/src/openstack$ uv run ansible-vault edit etc/kolla/passwords.yml     # vider keystone_admin_password et glance_database_password (« clé: »)
admin@adm01:~/src/openstack$ uv run ansible-vault decrypt etc/kolla/passwords.yml --output /dev/shm/pw.yml
admin@adm01:~/src/openstack$ uv run kolla-genpwd -p /dev/shm/pw.yml                 # ne remplit QUE les clés vides
admin@adm01:~/src/openstack$ uv run ansible-vault encrypt /dev/shm/pw.yml --encrypt-vault-id critique --output etc/kolla/passwords.yml
admin@adm01:~/src/openstack$ shred -u /dev/shm/pw.yml
admin@adm01:~/src/openstack$ uv run kolla-ansible reconfigure -i inventaire/multinode --configdir etc/kolla -t keystone,glance
```

Puis : `clouds.yaml`/`secure.yaml` du nuage `medisphere-admin` mis à jour, ancien mot de passe refusé (`openstack --os-password …` interdit : test par `openstack token issue` avec une copie temporaire de `secure.yaml` contenant l'ancien), MR « chore(secrets): rotation SEC-1153 », registre des secrets (date de rotation).
