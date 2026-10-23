# vm-par2 — une VM de PAR2 clonée de l'image dorée Debian 13 de hp01 (F5-S03).

terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# Image dorée amenée sur hp01 par PBS (RB-353 §4) : même étiquetage qu'à PAR1 (M03).
data "proxmox_virtual_environment_vms" "image" {
  node_name = var.noeud
  tags      = ["gold", "debian13", "current"]
  filter {
    name   = "template"
    values = ["true"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.vms) == 1
      error_message = "Il faut exactement UN template gold/debian13/current sur ${var.noeud} : ${length(self.vms)} trouvé(s) (RB-353 §4)."
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.nom
  node_name   = var.noeud
  vm_id       = var.vmid
  pool_id     = "par2"
  description = "${var.description}\nGérée par OpenTofu (plateforme/infra, envs/par2). Ne pas modifier à la main."
  tags        = sort(distinct(var.etiquettes))
  on_boot     = var.demarre
  started     = var.demarre
  protection  = var.protection

  clone {
    vm_id        = data.proxmox_virtual_environment_vms.image.vms[0].vm_id
    full         = true
    datastore_id = var.stockage
  }

  operating_system {
    type = "l26"
  }
  cpu {
    cores = var.coeurs
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = var.memoire_mo
  }
  scsi_hardware = "virtio-scsi-single"
  agent {
    enabled = true
  }
  serial_device {}
  vga {
    type = "serial0"
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.stockage
    size         = var.disque_go
    file_format  = "qcow2"
    iothread     = true
    discard      = "on"
  }

  dynamic "disk" {
    for_each = var.disques_donnees
    content {
      interface    = "scsi${disk.key + 1}"
      datastore_id = var.stockage
      size         = disk.value.taille_go
      file_format  = "qcow2"
      iothread     = true
      discard      = "on"
    }
  }

  network_device {
    bridge      = var.pont
    model       = "virtio"
    mac_address = var.mac
  }

  initialization {
    datastore_id = var.stockage
    upgrade      = false

    ip_config {
      ipv4 {
        address = "${var.ipv4}/24"
        gateway = "10.20.20.1"
      }
    }
    dns {
      servers = var.resolveurs
      domain  = "par2.medisphere.internal"
    }
    user_account {
      username = "admin"
      keys     = [var.cle_ssh_admin]
    }
  }

  lifecycle {
    # clone : l'image « current » change (M03) ; started/on_boot : pilotés par les runbooks après la
    # création (bao-par2 démarré en PRA, arrêté après) ; un plan ne doit pas les « corriger ».
    ignore_changes = [clone, started, on_boot]
  }
}
