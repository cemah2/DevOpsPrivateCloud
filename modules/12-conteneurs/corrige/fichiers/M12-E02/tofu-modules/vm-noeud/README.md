# Module `vm-noeud`

Une VM « nœud de cluster » : clone **complet** de l'image dorée courante d'une famille
(`debian13` ou `rocky10`), plusieurs cartes réseau avec leur MTU, des disques de données, et
ses adresses enregistrées dans NetBox **avant** la création de la VM. Introduit en M08-E02 pour
les nœuds Ceph (`ceph01-04`) et le client `cephcli01` ; étendu en M10-E02 (MAC imposée, carte sans
adresse) pour les nœuds OpenStack, puis en M12-E02 (carte en **DHCP**) pour les hôtes de
conteneurs `ctr01-03` et `legacy01`, sur le VNet `vsandbox`.

## Historique

| Version | Exercice | Changement (toujours rétrocompatible) |
|---|---|---|
| v2.2.0 | M08-E02 | Création : famille, plusieurs cartes et MTU, disques de données, adresses imposées |
| v2.3.0 | M10-E02 | `mac` par carte, carte sans adresse (en dernier), sortie `macs` |
| v2.4.0 | M12-E02 | `ipv4 = "dhcp"` (sans préfixe ni passerelle) ; sorties `dhcp`, `adresses_agent` ; IP primaire NetBox seulement si la première carte est statique (bloc `moved`) |

Les étiquettes sont communes à tout le dépôt `plateforme/tofu-modules` : prends celle que ta MR a
produite (le numéro ci-dessus suppose que rien d'autre n'a été publié entre-temps).

## Pourquoi un module à côté de `vm-debian`

- `vm-debian` v2 (M06-E13) décrit un hôte à **une** carte dont l'adresse peut être allouée par
  NetBox. L'étendre à N cartes, N disques et deux familles aurait cassé son interface (version
  majeure) pour tous ses consommateurs du socle, qui n'en ont pas besoin.
- Les nœuds de cluster ont des adresses **imposées** par le plan (PLAN.md §4.9), sur plusieurs
  VLAN, dont des réseaux non routés : le module ne propose pas d'allocation.
- Les deux modules partagent les mêmes noms d'entrées quand le sens est le même : passer de l'un à
  l'autre ne demande pas de réapprendre.

## Choix

- **Famille et CPU** : `rocky10` impose `x86-64-v3` (RHEL 10) ; `debian13` garde `x86-64-v2-AES`
  comme l'image dorée. `type_cpu = "host"` reste possible (une seule machine physique dans le lab).
- **Disques** : `virtio-scsi-single`, un contrôleur par disque ; `ssd = true` présente le disque
  comme non rotatif (Ceph en déduit la classe `ssd`), sinon il est vu rotatif (`hdd`).
  `sauvegarde = false` par défaut : on ne sauvegarde pas un disque d'OSD avec PBS (Ceph a sa propre
  redondance ; la sauvegarde des données se fait au niveau Ceph, M08-E25). Le numéro de série
  (`serie`) rend le disque reconnaissable dans `/dev/disk/by-id/` et dans `ceph orch device ls`.
- **Réseau** : une carte par VLAN ; la première porte le nom DNS et l'IP primaire NetBox ; une seule
  carte porte la passerelle ; MTU 9000 seulement là où le PLAN le prévoit (VLAN 30, 31, 51).
- **DHCP (v2.4.0)** : `ipv4 = "dhcp"` pour une VM d'environnement jetable sur `vsandbox`. Kea attribue
  l'adresse et publie le nom (`<nom>.par1.medisphere.internal`) par DDNS ; NetBox ne connaît que la
  VM et l'interface. Impose `mac` pour retrouver le même bail après une reconstruction. N'utilise
  pas le module `enregistrement-dns` pour ces VMs : deux écrivains sur le même nom se contrediraient.
- **Cycle de vie** : `ignore_changes = [clone]` comme `vm-debian` : une nouvelle image ne recrée
  aucun nœud. On reconstruit un nœud volontairement (`-replace`), un seul à la fois, cluster sain.
- **Pas de `prevent_destroy`** : les environnements de module se détruisent ; la protection Proxmox
  (`protection = true`) reste disponible pour un nœud qu'on veut garder.

## Limites

- Le MTU invité dépend de virtio (`host_mtu`) et de NetworkManager/networkd : le rôle Ansible du
  nœud le **vérifie** (`ceph_noeud`, M08-E02).
- Le module n'écrit pas le DNS : l'appelant utilise `enregistrement-dns` (M06-E14) avec les sorties
  `fqdn` et `ipv4` (cartes statiques), ou laisse le DDNS de Kea le faire (carte DHCP).
- Carte DHCP : l'adresse n'est pas connue au plan ; `adresses_agent` la donne après le démarrage
  (agent QEMU). Une règle de pare-feu qui viserait cette VM doit viser son nom ou son réseau, pas
  une adresse lue une fois.

<!-- BEGIN_TF_DOCS -->
<!-- Tableau généré par terraform-docs (M05-E13) : `terraform-docs markdown table --output-file README.md vm-noeud` -->
<!-- END_TF_DOCS -->
