# envs/f1/essai.tf — machine d'essai de l'usine (F1-S06, PLAT-3106).
#
# Un « serveur nu » comme les bm* du M11 (envs/provisioning/bm.tf) : VM SANS système, sans clone, sans
# cloud-init, qui démarre sur le VLAN 60. Différence : son intention est une VM NetBox de plate-forme
# « k8s-noeud » (le profil essayé), pas un équipement serveur-bm. Son adresse de service est DANS le
# VLAN 60 (10.10.60.191, plage du provisioning) : l'usine peut donc la mettre en service d'un trait et
# vérifier le profil en SSH, sans bascule de réseau (contrairement à k8s-w03, envs/k8s/usine.tf).
#
# MAC fixée, localement administrée : 02:4d:53 (« MS »), 60 (le VLAN), 31:01 (VMID 3101).
# Cycle : avec_essai = true → apply (VM éteinte, statut NetBox planned) → job « provisionner »
# (EQUIPEMENT=f1-usine-essai) → vérifications → avec_essai = false → apply (tout disparaît : VM,
# objets NetBox, enregistrements DNS).

locals {
  essai = var.avec_essai ? {
    "f1-usine-essai" = { vmid = 3101, mac = "02:4D:53:60:31:01", ipv4 = "10.10.60.191" }
  } : {}
}

data "netbox_cluster" "cluster" {
  name = var.netbox_cluster
}

data "netbox_platform" "k8s_noeud" {
  count = var.avec_essai ? 1 : 0
  name  = "k8s-noeud"
}

resource "netbox_virtual_machine" "essai" {
  for_each = local.essai

  name         = each.key
  cluster_id   = data.netbox_cluster.cluster.id
  platform_id  = data.netbox_platform.k8s_noeud[0].id
  status       = "planned"
  vcpus        = 2
  memory_mb    = 2048
  disk_size_mb = 20 * 1024
  tags         = ["env-f1"]
  comments     = "F1-S06 : essai du profil k8s-noeud de l'usine. Jetable."

  lifecycle {
    # Le statut et pxe_action appartiennent à l'usine (outils/provisionner.py), pas à OpenTofu.
    ignore_changes = [status, custom_fields]
  }
}

resource "netbox_interface" "essai" {
  for_each = local.essai

  name               = "ens18"
  virtual_machine_id = netbox_virtual_machine.essai[each.key].id
}

# Objet MAC de NetBox ≥ 4.2, attaché à l'interface de la VM (lu par outils/netbox-provision.py).
resource "netbox_mac_address" "essai" {
  for_each = local.essai

  mac_address                  = each.value.mac
  virtual_machine_interface_id = netbox_interface.essai[each.key].id
}

resource "netbox_ip_address" "essai" {
  for_each = local.essai

  ip_address                   = "${each.value.ipv4}/24"
  virtual_machine_interface_id = netbox_interface.essai[each.key].id
  status                       = "active"
  dns_name                     = "${each.key}.par1.medisphere.internal"
  description                  = "F1-S06 : essai de l'usine (service = provisioning)"
}

resource "netbox_primary_ip" "essai" {
  for_each = local.essai

  virtual_machine_id = netbox_virtual_machine.essai[each.key].id
  ip_address_id      = netbox_ip_address.essai[each.key].id
}

resource "proxmox_virtual_environment_vm" "essai" {
  for_each = local.essai

  name        = each.key
  node_name   = var.noeud
  vm_id       = each.value.vmid
  pool_id     = "lab"
  description = "F1-S06 : machine d'essai de l'usine (profil k8s-noeud), démarrage réseau. Jetable."
  tags        = ["env-f1"]
  on_boot     = false
  started     = false # l'alimentation appartient à l'usine (provisionner.py)

  bios          = "seabios"
  boot_order    = ["net0", "scsi0"]
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = 2048
  }
  agent {
    enabled = true
  }
  disk {
    datastore_id = var.stockage
    interface    = "scsi0"
    size         = 20
    discard      = "on"
    iothread     = true
  }
  network_device {
    bridge      = "vprov"
    model       = "virtio"
    mac_address = each.value.mac
  }
  serial_device {}
  operating_system {
    type = "l26"
  }

  depends_on = [netbox_primary_ip.essai]
}

module "dns_essai" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = local.essai

  nom  = "${each.key}.par1.medisphere.internal"
  ipv4 = each.value.ipv4
  ttl  = 300
}
