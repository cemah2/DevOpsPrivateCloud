# CHG-1104 — Déploiement initial d'OpenStack 2026.1 (PAR1)

| | |
|---|---|
| Ticket | PLAT-1104 |
| Date, fenêtre | `<AAAA-MM-JJ>`, `<HH:MM>`-`<HH:MM>` |
| Exécutant | `<MOI>` ; relecture : Karim Benali |
| Dépôt | `plateforme/openstack`, commit `<SHA>` (MR `!<N>`) |
| Versions | kolla-ansible `22.2.0` ; ansible-core `2.20.<x>` ; images `quay.io/openstack.kolla/*:2026.1-debian-trixie` (empreintes relevées : `docker images --digests` sur chaque nœud, annexe) |
| Instantanés | `avant-kolla` des VMs 2101, 2102, 2103 (supprimés le `<date>` après validation) |

## Préparation

| Étape | Résultat | Durée |
|---|---|---|
| Flux `osctl01` → `ca01:443` et `ca01` → `10.10.50.201:80` (MR sur `pare_feu.yml`, pipeline de `plateforme/ansible`) | appliqués sur `gw01` et `gw02` | `<mm>` min |
| Client `step` sur `osctl01` (`playbooks/outils-pki.yml`) | `step version` : 0.31.x | `<mm>` min |
| Certificat externe (`outils/certificat-externe.sh emettre`) | émis par « MédiSphère Intermediate CA », SAN `openstack.par1.medisphere.internal`, échéance `<date>` (30 jours) ; `haproxy.pem` chiffré (`critique`) | `<mm>` min |

## Déploiement

| Étape | Commande (depuis `~/src/openstack`) | Durée | Remarques |
|---|---|---|---|
| Amorçage des hôtes | `uv run kolla-ansible bootstrap-servers -i inventaire/multinode --configdir etc/kolla` | `<mm>` min | Docker CE installé (dépôt Docker), `/etc/hosts` complété, compte `kolla` créé (groupe `docker`) ; notre compte `admin` passe par `sudo docker` |
| Contrôles | `… prechecks …` | `<mm>` min | `<échecs et corrections>` |
| Images | `… pull …` | `<mm>` min | `<Go>` sur `osctl01`, `<Go>` par calcul |
| Déploiement | `… deploy …` | `<mm>` min | |
| Après déploiement | `… post-deploy …` | < 1 min | `etc/kolla/admin-openrc.sh` et `etc/kolla/clouds.yaml` produits (ignorés par Git : mot de passe en clair) |

## Incidents et corrections

| Symptôme | Cause | Correction (dans le dépôt) |
|---|---|---|
| `<ex. prechecks : « neutron_external_interface ens21 not found » sur oscmp01>` | `<ex. variable placée dans globals.yml au lieu de host_vars/osctl01.yml>` | `<commit>` |

## État final (vérifié)

- VIP 10.10.50.200 et 10.10.50.201 sur `ens18` de `osctl01`, keepalived VRID 150 ;
- `https://openstack.par1.medisphere.internal:5000/v3` : TLS vérifié avec la seule racine MédiSphère ;
- `openstack compute service list` : `nova-scheduler`, `nova-conductor` (osctl01), `nova-compute` (oscmp01, oscmp02) `enabled`/`up` ;
- `openstack network agent list` : « OVN Controller Gateway agent » (osctl01), « OVN Controller agent » et « OVN Metadata agent » (oscmp01, oscmp02) vivants ;
- aucun conteneur `unhealthy` (`docker ps --filter health=unhealthy` vide sur les trois nœuds).

## Suites

- Renouveler le certificat externe avant le `<date - 10 jours>` (`outils/certificat-externe.sh renouveler`, puis `reconfigure -t loadbalancer`) tant que M10-E27 n'a pas automatisé le renouvellement.
- Registre des secrets : `passwords.yml`, `haproxy.pem` (clé de la VIP externe), `~/.config/openstack/secure.yaml`.
