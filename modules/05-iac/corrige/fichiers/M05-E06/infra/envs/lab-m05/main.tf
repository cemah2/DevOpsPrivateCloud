# main.tf — environnement lab-m05 : la VM d'essai (M05-E04, paramétrée en M05-E06).

data "proxmox_version" "pve01" {}

resource "proxmox_virtual_environment_vm" "essai" {
  node_name   = var.noeud
  vm_id       = var.vm_essai.vmid
  name        = var.vm_essai.nom
  description = local.description
  tags        = local.etiquettes # toujours déclarées : sinon le clone hérite de celles du template
  pool_id     = var.pool

  clone {
    vm_id        = var.image_vmid # changer cette valeur RECRÉE la VM (ForceNew)
    full         = true
    datastore_id = var.stockage_vm
  }

  on_boot         = false # VM d'environnement : ne redémarre pas avec pve01
  started         = true
  stop_on_destroy = true # rien à préserver : arrêt net à la destruction

  # Matériel identique à l'image dorée (sinon : défauts du provider, pas ceux du template).
  operating_system {
    type = "l26"
  }
  cpu {
    cores = var.vm_essai.coeurs
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = var.vm_essai.memoire_mo
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
    datastore_id = var.stockage_vm
    size         = var.vm_essai.disque_go
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
    datastore_id = var.stockage_vm
    dns {
      domain  = local.domaine
      servers = local.resolveurs
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
