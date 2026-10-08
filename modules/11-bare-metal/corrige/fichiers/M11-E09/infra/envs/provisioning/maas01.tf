# envs/provisioning/maas01.tf — plateforme/infra (M11-E09, PLAT-1213)
#
# maas01 : MAAS 3.7 (région + rack) sur Ubuntu 24.04, VLAN 60. Le module vm-debian ne clone que
# l'image dorée Debian « current » : les ressources sont écrites ici, sur le même modèle
# (intention dans NetBox d'abord, puis la VM, puis le nom). Adresse IMPOSÉE (PLAN §4.9).
# Détruite au mini-projet (M11-E25), après l'ADR-0110.

locals {
  maas01 = {
    nom     = "maas01"
    vmid    = 2116
    ipv4    = "10.10.60.11"
    prefixe = "10.10.60.0/24"
    fqdn    = "maas01.par1.medisphere.internal"
  }
}

# Template 9050 tpl-ubuntu2404 (construit en M11-E09 par infra/outils/creer-tpl-ubuntu2404.sh).
data "proxmox_virtual_environment_vms" "ubuntu2404" {
  tags = ["ubuntu2404", "template"]
  filter {
    name   = "template"
    values = ["true"]
  }
}

check "un_seul_template_ubuntu2404" {
  assert {
    condition     = length(data.proxmox_virtual_environment_vms.ubuntu2404.vms) == 1
    error_message = "Il faut exactement un template étiqueté ubuntu2404 + template (VMID 9050)."
  }
}

data "netbox_cluster" "pve01" {
  name = "pve01"
}

resource "netbox_virtual_machine" "maas01" {
  name         = local.maas01.nom
  cluster_id   = data.netbox_cluster.pve01.id
  status       = "active"
  vcpus        = 2
  memory_mb    = 4096
  disk_size_mb = 40 * 1024
  tags         = ["env-m11", "role-maas"]
  comments     = "M11-E09 : MAAS 3.7 (évaluation, ADR-0110). Détruite en fin de module."

  lifecycle {
    ignore_changes = [custom_fields] # vmid écrit par la synchronisation Proxmox → NetBox (M06-E11)
  }
}

resource "netbox_interface" "maas01_eth0" {
  name               = "eth0"
  virtual_machine_id = netbox_virtual_machine.maas01.id
}

resource "netbox_ip_address" "maas01" {
  ip_address                   = "${local.maas01.ipv4}/24"
  virtual_machine_interface_id = netbox_interface.maas01_eth0.id
  status                       = "active"
  dns_name                     = local.maas01.fqdn
  description                  = "Adresse du plan d'adressage (PLAN.md §4.9) pour maas01"
}

resource "netbox_primary_ip" "maas01" {
  virtual_machine_id = netbox_virtual_machine.maas01.id
  ip_address_id      = netbox_ip_address.maas01.id
}

resource "proxmox_virtual_environment_vm" "maas01" {
  name        = local.maas01.nom
  node_name   = var.noeud
  vm_id       = local.maas01.vmid
  pool_id     = "lab"
  description = "M11-E09 : MAAS 3.7 (snap) + PostgreSQL 16, Ubuntu 24.04. Évaluation, détruite en fin de module."
  tags        = ["env-m11", "role-maas"]
  on_boot     = false
  started     = true

  clone {
    vm_id        = data.proxmox_virtual_environment_vms.ubuntu2404.vms[0].vm_id
    node_name    = data.proxmox_virtual_environment_vms.ubuntu2404.vms[0].node_name
    full         = true
    datastore_id = var.stockage
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.stockage
    interface    = "scsi0"
    size         = 40 # images de démarrage de MAAS (quelques Go par série et architecture)
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = "vprov"
    model  = "virtio"
  }

  serial_device {}

  operating_system {
    type = "l26"
  }

  # L'adresse vient de l'intention enregistrée dans NetBox (référence = ordre de création).
  initialization {
    datastore_id = var.stockage
    ip_config {
      ipv4 {
        address = netbox_ip_address.maas01.ip_address
        gateway = cidrhost(local.maas01.prefixe, 1)
      }
    }
    dns {
      domain  = "par1.medisphere.internal"
      servers = ["10.10.20.10", "10.10.20.16"]
    }
    user_account {
      username = "admin"
      keys     = [var.cle_ssh_admin]
    }
  }

  lifecycle {
    ignore_changes = [clone]
  }
}

module "dns_maas01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"

  nom  = local.maas01.fqdn
  ipv4 = local.maas01.ipv4
  ttl  = 300
}

output "maas01" {
  description = "Identité de maas01."
  value = {
    vmid = proxmox_virtual_environment_vm.maas01.vm_id
    ipv4 = netbox_ip_address.maas01.ip_address
    fqdn = local.maas01.fqdn
  }
}
