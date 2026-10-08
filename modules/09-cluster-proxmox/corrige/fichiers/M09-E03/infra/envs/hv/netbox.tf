# netbox.tf — l'intention dans NetBox : VM, interfaces, adresses (M09-E03, chemin de M06-E13).
# Les adresses sont IMPOSÉES par le plan (PLAN §4.9), pas allouées : netbox_ip_address.
# Seule l'adresse MGMT porte un nom DNS (publié par dns.tf) ; les autres sont documentées.

data "netbox_cluster" "pve01" {
  name = var.netbox_cluster
}

locals {
  # nœud => carte => adresse/longueur (null : carte sans adresse sur le nœud)
  adresses = {
    for n, v in var.noeuds : n => {
      nic0 = "${v.mgmt}/24"
      nic1 = "${v.coro}/24"
      nic2 = "${v.stopub}/24"
      nic3 = "${v.stoclu}/24"
    }
  }
  # Paires (nœud, carte) aplaties pour for_each.
  interfaces = merge([
    for n in keys(var.noeuds) : { for k in range(5) : "${n}/nic${k}" => { noeud = n, nom = "nic${k}", carte = k } }
  ]...)
  ips = merge([
    for n, cartes in local.adresses : { for c, a in cartes : "${n}/${c}" => { noeud = n, carte = c, adresse = a } }
  ]...)
}

resource "netbox_virtual_machine" "noeud" {
  for_each = var.noeuds

  name         = each.key
  cluster_id   = data.netbox_cluster.pve01.id
  status       = "active"
  vcpus        = 4
  memory_mb    = 12288
  disk_size_mb = sum([for d in local.disques : d.taille]) * 1024
  tags         = ["env-m09"] # étiquette créée dans NetBox par le script de modélisation (M06-E05)
  comments     = "Nœud du cluster Proxmox imbriqué hv-par1 (VMID ${each.value.vmid}). ${local.description}"

  lifecycle {
    # Le VMID (champ personnalisé) est écrit par la synchronisation Proxmox → NetBox (M06-E11).
    ignore_changes = [custom_fields]
  }
}

resource "netbox_interface" "carte" {
  for_each = local.interfaces

  name               = each.value.nom
  virtual_machine_id = netbox_virtual_machine.noeud[each.value.noeud].id
  description        = local.cartes[each.value.carte].usage
}

resource "netbox_ip_address" "adresse" {
  for_each = local.ips

  ip_address                   = each.value.adresse
  virtual_machine_interface_id = netbox_interface.carte["${each.value.noeud}/${each.value.carte}"].id
  status                       = "active"
  # Le nom DNS seulement sur MGMT : un seul PTR par nom, et c'est l'adresse d'administration.
  dns_name    = each.value.carte == "nic0" ? "${each.value.noeud}.${local.domaine}" : null
  description = "${each.value.noeud} : ${local.cartes[tonumber(substr(each.value.carte, 3, 1))].usage} (PLAN §4.9)"
}

resource "netbox_primary_ip" "noeud" {
  for_each = var.noeuds

  virtual_machine_id = netbox_virtual_machine.noeud[each.key].id
  ip_address_id      = netbox_ip_address.adresse["${each.key}/nic0"].id
}
