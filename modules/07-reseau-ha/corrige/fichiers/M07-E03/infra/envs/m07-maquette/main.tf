# main.tf — les VMs de la maquette (M07-E03). Une ressource, une instance par entrée de local.vms.

# Image dorée courante (M03) : le seul template étiqueté gold + debian13 + current.
data "proxmox_virtual_environment_vms" "image" {
  tags = ["gold", "debian13", "current"]
  filter {
    name   = "template"
    values = ["true"]
  }
}

check "une_seule_image_courante" {
  assert {
    condition     = length(data.proxmox_virtual_environment_vms.image.vms) == 1
    error_message = "Il faut exactement un template gold/debian13/current (catalogue d'images, M03)."
  }
}

resource "proxmox_virtual_environment_vm" "maquette" {
  for_each = local.vms

  name        = each.key
  node_name   = var.noeud
  vm_id       = each.value.vmid
  pool_id     = var.pool
  description = local.description
  # Toujours déclarées (sinon le clone hérite de gold/current du template), triées comme Proxmox.
  tags = sort(distinct(concat(["env-m07"], each.value.fonction)))

  # Clone COMPLET (règle du journal du 2026-10-07 du PLAN) : la maquette ne dépend pas du template.
  clone {
    vm_id        = data.proxmox_virtual_environment_vms.image.vms[0].vm_id
    node_name    = data.proxmox_virtual_environment_vms.image.vms[0].node_name
    full         = true
    datastore_id = var.stockage
  }

  on_boot         = false # environnement de module : ne redémarre pas avec pve01
  started         = true
  stop_on_destroy = true # rien à préserver : arrêt net à la destruction

  operating_system {
    type = "l26"
  }
  cpu {
    cores = each.value.coeurs
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = each.value.memoire
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
    size         = 10
    file_format  = "raw"
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  # net0 : administration, toujours sur vsandbox.
  network_device {
    bridge   = "vsandbox"
    model    = "virtio"
    firewall = false
  }

  # net1, net2… : liens de fabric (un VNet par lien), dans l'ordre de la liste.
  dynamic "network_device" {
    for_each = each.value.cartes
    content {
      bridge   = network_device.value.vnet
      model    = "virtio"
      firewall = false
    }
  }

  initialization {
    datastore_id = var.stockage

    dns {
      domain  = "par1.medisphere.internal"
      servers = ["10.10.20.10", "10.10.20.16"] # dns01, dns02 (M06)
    }

    # ipconfig0 : eth0. Le n-ième bloc ip_config correspond à la n-ième carte.
    ip_config {
      ipv4 {
        address = each.value.admin
        gateway = each.value.admin == "dhcp" ? null : local.passerelle_sandbox
      }
    }

    # ipconfig1… : adresses de fabric, SANS passerelle (la route par défaut reste celle de eth0).
    dynamic "ip_config" {
      for_each = each.value.cartes
      content {
        ipv4 {
          address = ip_config.value.ipv4
        }
      }
    }

    user_account {
      username = "admin"
      keys     = [var.cle_ssh_admin]
    }
  }

  lifecycle {
    # Une nouvelle image « current » ne doit pas recréer la maquette par surprise.
    ignore_changes = [clone]
  }
}
