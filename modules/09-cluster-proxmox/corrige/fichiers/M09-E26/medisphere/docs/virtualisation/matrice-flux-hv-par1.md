# Matrice des flux du cluster `hv-par1` (SEC-1052)

> Source de vérité : `inventories/lab/group_vars/hv_par1/pve_pare_feu.yml` (rôle `pve_pare_feu`) pour le filtrage **sur les nœuds**, `host_vars/gw01/pare_feu.yml` pour ce qui traverse la bordure. Ce document les explique et dit comment tester chaque ligne. Toute modification commence par le code.

## Enquête : « qui a fait quoi ? » (moins de 5 minutes)

1. **Quelle action, sur quoi ?** Les tâches du cluster gardent l'utilisateur, le nœud et l'heure de chaque action (démarrage, arrêt, migration, sauvegarde…) :
   ```
   root@hv01:~# pvesh get /cluster/tasks --output-format json \
       | jq -r '.[] | select(.id == "120") | [(.starttime | todate), .node, .type, .user, .status] | @tsv'
   ```
   (`/cluster/tasks` ne garde que les tâches récentes ; plus ancien : `/nodes/<nœud>/tasks?vmid=120&since=<epoch>` sur chaque nœud, ou les fichiers de `/var/log/pve/tasks/`.)
2. **Depuis où ?** Les requêtes HTTP de l'interface et de l'API sont dans `/var/log/pveproxy/access.log` du nœud **qui a reçu** la requête (adresse source, utilisateur ou jeton, méthode, chemin, code) :
   ```
   root@hv01:~# grep -h 'qemu/120/status' /var/log/pveproxy/access.log* | tail
   ```
   Interroge les trois nœuds (et la VIP désigne l'un d'eux : regarde les trois). Une action par l'interface apparaît comme `POST /api2/json/nodes/hv02/qemu/120/status/stop`.
3. **Qui est derrière le compte ?** `pveum user list` (compte nominatif, jamais partagé) ; pour un jeton, son propriétaire et son commentaire.
4. **Connexions SSH** : `journalctl -u ssh` sur le nœud (certificat d'utilisateur : identité dans le journal, M06-E20).

Limites : les journaux sont **locaux** et tournent (logrotate) : la centralisation arrive au module 22 ; jusque-là, l'enquête se fait dans la fenêtre de rétention des nœuds.

## Flux entrants vers les nœuds

| # | Source | Destination | Port / proto | Motif | Où c'est ouvert | Test |
|---|---|---|---|---|---|---|
| 1 | nœuds (MGMT, COROSYNC) | nœuds | UDP 5405-5412 | Corosync, deux liens | règles automatiques + règle explicite | `corosync-cfgtool -s` : liens `connected` |
| 2 | nœuds | nœuds | TCP 22 | migration `secure`, réplication ZFS, `pvecm` | `pve_pare_feu` | `qm migrate` ; `pvesr status` |
| 3 | nœuds (VLAN 30, 31) | nœuds | TCP 3300, 6789, 6800-7300 | Ceph | `pve_pare_feu` (macro `Ceph`) | `ceph -s` : `HEALTH_OK` |
| 4 | nœuds (MGMT) | nœuds | VRRP (proto 112) | VIP 10.10.10.200 | `pve_pare_feu` | VIP sur **un seul** nœud (`ip -br a` sur les trois) |
| 5 | nœuds | nœuds | TCP 179, UDP 4789 | EVPN (BGP, VXLAN) | `pve_pare_feu` | `vtysh -c 'show bgp l2vpn evpn summary'` ; ping entre deux VMs de `vevpn1` sur deux nœuds |
| 6 | nœuds | nœuds | TCP 8006 | proxy d'API entre nœuds | `pve_pare_feu` | interface ouverte sur `hv01`, console d'une VM de `hv03` |
| 7 | `adm01`, VPN, `runner01` (IPSet `management`) | nœuds, VIP | TCP 8006, 22, 5900-5999, 3128 | administration, OpenTofu, Ansible | IPSet `management` (règles automatiques) + explicites ; bordure pour `runner01` | `curl --cacert <racine> https://hv.par1.medisphere.internal:8006/` depuis `adm01` et `runner01` |
| 8 | `ca01` | nœuds | TCP 80 | défi ACME HTTP-01 (émission initiale) | `pve_pare_feu` (IPSet `acme`) + bordure | émission par `hv-certificats.yml` |
| 9 | tout autre hôte, dont `gw01`/`gw02` | nœuds | 8006, 22 | — | **refusé** (`local_network` restreint à 10.10.10.48/28) | `timeout 3 bash -c '</dev/tcp/10.10.10.51/8006'` depuis `gw01` : échec |

## Flux sortants des nœuds (politique de sortie `ACCEPT` ; filtrés par la bordure)

| Destination | Port | Motif |
|---|---|---|
| `pbs01` 10.20.10.10 | TCP 8007 | sauvegardes (E15), sauvegarde de configuration (E29) |
| `ca01` | TCP 443 | ACME, renouvellement par mTLS |
| `dns01`, `dns02` | 53 | résolution |
| passerelle | UDP 123 | NTP |
| dépôts Proxmox et Debian | TCP 80/443 | mises à jour |

## Règles automatiques de Proxmox VE (ce qu'on n'écrit pas mais qui existe)

- Depuis `local_network` : interface, SSH, consoles, Corosync. Par défaut, `local_network` = le réseau de l'adresse principale du nœud, ici **tout MGMT** : passerelles et futurs hôtes MGMT compris. Redéfini à 10.10.10.48/28.
- Depuis l'IPSet `management` : 8006, 22, 5900-5999, 3128, 60000-60050.
- Vérification de ce qui est réellement généré : `iptables-save | grep -E 'PVEFW-HOST-IN|management|local_network'` (moteur iptables) sur un nœud.
