# vm-debian v2 — l'intention dans NetBox, AVANT la VM (M06-E13).
#
# Ordre imposé par les références (pas de depends_on) :
#   VM NetBox → interface eth0 → adresse (allouée ou imposée) → IP primaire
#   → VM Proxmox (cloud-init reçoit l'adresse) .
# À la destruction, l'ordre s'inverse : la VM Proxmox disparaît, PUIS l'adresse est rendue.

data "netbox_cluster" "cluster" {
  name = var.netbox_cluster
}

data "netbox_ip_range" "plage" {
  count    = var.ipv4_imposee == null ? 1 : 0
  contains = var.plage_adresses
}

resource "netbox_virtual_machine" "vm" {
  name         = var.nom
  cluster_id   = data.netbox_cluster.cluster.id
  status       = "active"
  vcpus        = var.coeurs
  memory_mb    = var.memoire_mo
  disk_size_mb = var.disque_go * 1024
  tags         = var.etiquettes
  comments     = var.description

  lifecycle {
    # Le VMID (champ personnalisé) est écrit par la synchronisation Proxmox → NetBox (M06-E11) :
    # Proxmox fait foi pour la réalité d'exécution. Sans cet ignore_changes, chaque plan
    # proposerait de l'effacer.
    ignore_changes = [custom_fields]
  }
}

resource "netbox_interface" "eth0" {
  name               = "eth0"
  virtual_machine_id = netbox_virtual_machine.vm.id
}

# Allocation : la première adresse libre de la plage, réservée et rattachée en un appel
# (POST …/ip-ranges/<id>/available-ips/ : NetBox sérialise les allocations concurrentes).
resource "netbox_available_ip_address" "ip" {
  count                        = var.ipv4_imposee == null ? 1 : 0
  ip_range_id                  = data.netbox_ip_range.plage[0].id
  virtual_machine_interface_id = netbox_interface.eth0.id
  status                       = "active"
  dns_name                     = local.fqdn
  description                  = "Allouée par OpenTofu pour ${var.nom}"
}

# Adresse imposée par le plan d'adressage (hôte du socle).
resource "netbox_ip_address" "ip" {
  count                        = var.ipv4_imposee == null ? 0 : 1
  ip_address                   = "${var.ipv4_imposee}/${local.longueur_prefixe}"
  virtual_machine_interface_id = netbox_interface.eth0.id
  status                       = "active"
  dns_name                     = local.fqdn
  description                  = "Adresse du plan d'adressage (PLAN.md §4.5) pour ${var.nom}"
}

resource "netbox_primary_ip" "ip" {
  virtual_machine_id = netbox_virtual_machine.vm.id
  ip_address_id      = var.ipv4_imposee == null ? netbox_available_ip_address.ip[0].id : netbox_ip_address.ip[0].id
}

locals {
  fqdn             = "${var.nom}.${var.domaine}"
  longueur_prefixe = split("/", var.reseau_prefixe)[1]
  passerelle       = cidrhost(var.reseau_prefixe, 1)
  # Adresse avec masque, telle que NetBox la stocke (ex. 10.10.99.10/24).
  ipv4_cidr = var.ipv4_imposee == null ? netbox_available_ip_address.ip[0].ip_address : netbox_ip_address.ip[0].ip_address
  ipv4      = split("/", local.ipv4_cidr)[0]
}

check "adresse_dans_le_prefixe" {
  assert {
    # Adresse réseau de l'IP allouée (avec la longueur du préfixe) = adresse réseau du préfixe.
    condition     = cidrhost("${local.ipv4}/${local.longueur_prefixe}", 0) == cidrhost(var.reseau_prefixe, 0)
    error_message = "L'adresse ${local.ipv4_cidr} n'appartient pas au préfixe ${var.reseau_prefixe} : plage NetBox mal choisie."
  }
}
