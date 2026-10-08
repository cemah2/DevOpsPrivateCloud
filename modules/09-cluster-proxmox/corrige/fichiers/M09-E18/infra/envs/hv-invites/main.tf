# main.tf — VMs de recette clonées du template 199, dans le pool recette (M09-E18).

locals {
  etiquettes  = ["tofu", "recette"]
  description = "Créée par OpenTofu (plateforme/infra, envs/hv-invites) — PLAT-1028. Ne pas modifier à la main."
}

resource "proxmox_virtual_environment_vm" "recette" {
  for_each = var.vms

  node_name   = each.value.noeud
  vm_id       = each.value.vmid
  name        = each.key
  description = local.description
  tags        = local.etiquettes # toujours déclarées : sinon le clone hérite de celles du template
  pool_id     = var.pool

  lifecycle {
    # clone.* est ForceNew : un nouveau template ne doit pas recréer les VMs existantes.
    ignore_changes = [clone]
  }

  clone {
    vm_id        = var.template_vmid
    node_name    = var.noeud_template # le template est configuré sur ce nœud ; son disque est partagé
    full         = true
    datastore_id = var.stockage
  }

  on_boot         = true # VM de recette : redémarre avec son nœud
  started         = true # exige VM.PowerMgmt (PVE 9.2) : rôle WBTofuHV
  stop_on_destroy = true

  operating_system {
    type = "l26"
  }
  cpu {
    cores = each.value.coeurs
    type  = "x86-64-v2-AES" # identique sur les trois nœuds : migration à chaud possible
  }
  memory {
    dedicated = each.value.memoire_mo
  }
  scsi_hardware = "virtio-scsi-single"
  serial_device {}
  vga {
    type = "serial0"
  }

  agent {
    enabled = true
    timeout = "5m"
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.stockage
    size         = each.value.disque_go
    file_format  = "raw"
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = var.vnet
    model  = "virtio"
  }

  initialization {
    datastore_id = var.stockage
    dns {
      domain  = "par1.medisphere.internal"
      servers = ["10.10.20.10", "10.10.20.16"]
    }
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_account {
      username = "admin"
      keys     = var.cles_ssh_admin
    }
  }
}
