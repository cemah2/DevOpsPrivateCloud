# vm-noeud — l'intention dans NetBox, AVANT la VM (même principe que vm-debian v2, M06-E13).
# Depuis M10-E02 : une interface par carte, une adresse par carte ADRESSÉE seulement.
#
# Ordre imposé par les références : VM NetBox → une interface par carte (ens18, ens19…)
# → une adresse IMPOSÉE par interface → IP primaire (première carte) → VM Proxmox.
# Les nœuds de cluster ont des adresses fixées par le PLAN (§4.9) : pas d'allocation ici.

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

resource "netbox_ip_address" "carte" {
  count                        = length(local.cartes_adressees)
  ip_address                   = "${local.cartes_adressees[count.index].ipv4}/${split("/", local.cartes_adressees[count.index].prefixe)[1]}"
  virtual_machine_interface_id = netbox_interface.carte[count.index].id
  status                       = "active"
  # Seule la première carte porte un nom : c'est elle que medictl dns sync (M06-E15) et le
  # module enregistrement-dns publient. Un nom sur l'adresse du réseau cluster (VLAN 31, non
  # routé) ferait répondre le DNS avec une adresse injoignable depuis adm01.
  dns_name    = count.index == 0 ? local.fqdn : null
  description = "Adresse du plan (PLAN.md §4.9) pour ${var.nom}, carte ens${18 + count.index}"
}

resource "netbox_primary_ip" "ip" {
  virtual_machine_id = netbox_virtual_machine.vm.id
  ip_address_id      = netbox_ip_address.carte[0].id
}

check "adresses_dans_les_prefixes" {
  assert {
    condition = alltrue([
      for c in local.cartes_adressees :
      cidrhost("${c.ipv4}/${split("/", c.prefixe)[1]}", 0) == cidrhost(c.prefixe, 0)
    ])
    error_message = "Une adresse n'appartient pas au préfixe de sa carte : vérifie var.cartes."
  }
}
