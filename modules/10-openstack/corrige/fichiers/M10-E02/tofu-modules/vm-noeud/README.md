# Module `vm-noeud`

Une VM « nœud de cluster » : clone **complet** de l'image dorée courante d'une famille
(`debian13` ou `rocky10`), plusieurs cartes réseau avec leur MTU, des disques de données, et
ses adresses enregistrées dans NetBox **avant** la création de la VM. Introduit en M08-E02 pour
les nœuds Ceph (`ceph01-04`) et le client `cephcli01` ; complété en M10-E02 pour les nœuds
OpenStack (`osctl01`, `oscmp01-02`).

## Ce qui change en v2.3 (M10-E02, ajout rétrocompatible)

Version **mineure** : un appelant qui ne renseigne aucun des nouveaux champs obtient exactement la
même VM et le même plan.

| Champ de `cartes` | Défaut | Rôle |
|---|---|---|
| `mac` | `null` (tirée par Proxmox) | MAC imposée, pour que l'invité reconnaisse la carte (renommage par MAC, M10-E02) |
| `ipv4`, `prefixe` | obligatoires avant v2.3 ; `null` ensemble | carte **sans adresse** (carte externe d'un nœud réseau OpenStack, branchée dans `br-ex`) |

Règles (validations au `plan`) :
- la première carte a une adresse (nom DNS, IP primaire NetBox) ;
- les cartes sans adresse viennent **après** toutes les cartes adressées : Proxmox associe
  `ipconfigN` à `netN` par leur numéro et le module produit un bloc `ip_config` par carte adressée,
  dans l'ordre ; une carte sans adresse au milieu décalerait la configuration des suivantes ;
- une carte sans adresse n'a pas d'`ipconfigN` : cloud-init ne la configure pas ; un rôle Ansible
  peut la nommer (M10-E02) ;
- une carte sans adresse ne porte pas la passerelle ;
- le pare-feu de Proxmox est désactivé sur toutes les cartes (`firewall = false`, écrit
  explicitement) : une carte qui transporte des MAC de VMs imbriquées ou de routeurs OVN ne doit
  pas être filtrée ;
- NetBox reçoit une interface par carte et l'adresse des cartes adressées. Les MAC ne sont pas
  écrites dans NetBox par le module (NetBox 4.2+ les modélise comme objets séparés).

Sortie ajoutée : `macs` (dans l'ordre des cartes).

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
- **Cycle de vie** : `ignore_changes = [clone]` comme `vm-debian` : une nouvelle image ne recrée
  aucun nœud. On reconstruit un nœud volontairement (`-replace`), un seul à la fois, cluster sain.
- **Pas de `prevent_destroy`** : les environnements de module se détruisent ; la protection Proxmox
  (`protection = true`) reste disponible pour un nœud qu'on veut garder.

## Limites

- Le MTU invité dépend de virtio (`host_mtu`) et de NetworkManager/networkd : le rôle Ansible du
  nœud le **vérifie** (`ceph_noeud`, M08-E02).
- Le module n'écrit pas le DNS : l'appelant utilise `enregistrement-dns` (M06-E14) avec les sorties
  `fqdn` et `ipv4`.

<!-- BEGIN_TF_DOCS -->
<!-- Tableau généré par terraform-docs (M05-E13) : `terraform-docs markdown table --output-file README.md vm-noeud` -->
<!-- END_TF_DOCS -->
