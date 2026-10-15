# vm-noeud — l'intention dans NetBox, AVANT la VM (même principe que vm-debian v2, M06-E13).
#
# Ordre imposé par les références : VM NetBox → une interface par carte (ens18, ens19…)
# → une adresse IMPOSÉE par carte statique → IP primaire (première carte, si statique) → VM Proxmox.
# Les nœuds de cluster ont des adresses fixées par le PLAN (§4.9) : pas d'allocation ici.
# M10-E02 : une carte sans adresse a son interface, pas d'adresse.
# M12-E02 : une carte DHCP a son interface, pas d'adresse (le bail est chez Kea, le nom dans le
# DNS par le DDNS de Kea) ; si c'est la première carte, la VM n'a pas d'IP primaire dans NetBox.

data "netbox_cluster" "cluster" {
  name = var.netbox_cluster
}

resource "netbox_virtual_machine" "vm" {
  name         = var.nom
  cluster_id   = data.netbox_cluster.cluster.id
  status       = "active"
  vcpus        = var.coeurs
  memory_mb    = var.memoire_mo
  disk_size_mb = (var.disque_go + sum(concat([0], [for d in var.disques_donnees : d.taille_go]))) * 1024
  tags         = var.etiquettes
  comments     = var.description

  lifecycle {
    # vmid : écrit par la synchronisation Proxmox → NetBox (M06-E11), Proxmox fait foi.
    ignore_changes = [custom_fields]
  }
}

resource "netbox_interface" "carte" {
  count              = length(var.cartes)
  name               = "ens${18 + count.index}"
  virtual_machine_id = netbox_virtual_machine.vm.id
}

# Une adresse par carte STATIQUE : carte[k] décrit var.cartes[local.idx_statiques[k]].
# Sans carte DHCP ni carte sans adresse en tête, k = rang de la carte : mêmes adresses d'état
# qu'en v2.2/v2.3 (aucun « moved » nécessaire pour ces ressources).
resource "netbox_ip_address" "carte" {
  count                        = length(local.idx_statiques)
  ip_address                   = "${var.cartes[local.idx_statiques[count.index]].ipv4}/${split("/", var.cartes[local.idx_statiques[count.index]].prefixe)[1]}"
  virtual_machine_interface_id = netbox_interface.carte[local.idx_statiques[count.index]].id
  status                       = "active"
  # Seule la première carte porte un nom : c'est elle que medictl dns sync (M06-E15) et le
  # module enregistrement-dns publient. Un nom sur l'adresse du réseau cluster (VLAN 31, non
  # routé) ferait répondre le DNS avec une adresse injoignable depuis adm01.
  dns_name    = local.idx_statiques[count.index] == 0 ? local.fqdn : null
  description = "Adresse du plan (PLAN.md §4.9) pour ${var.nom}, carte ens${18 + local.idx_statiques[count.index]}"
}

# IP primaire : seulement si la première carte a une adresse imposée.
resource "netbox_primary_ip" "ip" {
  count              = local.premiere_statique ? 1 : 0
  virtual_machine_id = netbox_virtual_machine.vm.id
  ip_address_id      = netbox_ip_address.carte[0].id
}

# v2.4.0 : la ressource unique devient une ressource à « count ». Sans ce bloc, les appelants de
# M08 et M10 verraient au plan une IP primaire détruite puis recréée.
moved {
  from = netbox_primary_ip.ip
  to   = netbox_primary_ip.ip[0]
}

locals {
  premiere_statique = length(local.idx_statiques) > 0 && try(local.idx_statiques[0] == 0, false)
}

check "adresses_dans_les_prefixes" {
  assert {
    condition = alltrue([
      for i in local.idx_statiques :
      cidrhost("${var.cartes[i].ipv4}/${split("/", var.cartes[i].prefixe)[1]}", 0) == cidrhost(var.cartes[i].prefixe, 0)
    ])
    error_message = "Une adresse n'appartient pas au préfixe de sa carte : vérifie var.cartes."
  }
}
