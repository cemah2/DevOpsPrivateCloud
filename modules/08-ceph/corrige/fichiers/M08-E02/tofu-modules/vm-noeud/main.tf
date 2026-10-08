# vm-noeud — la VM Proxmox (M08-E02).
# Clone COMPLET de l'image dorée courante de la famille (règle M03, journal du 2026-10-07).
# Le matériel est réécrit explicitement : avec un clone, le fournisseur remet SES valeurs par
# défaut sur tout ce qui n'est pas écrit (leçon de vm-debian v1, M05-E13).

data "proxmox_virtual_environment_vms" "image" {
  tags = ["gold", var.famille, "current"]
  filter {
    name   = "template"
    values = ["true"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.vms) == 1
      error_message = "Il faut exactement UN template gold/${var.famille}/current : ${length(self.vms)} trouvé(s) (catalogue d'images, M03)."
    }
  }
}

locals {
  fqdn = "${var.nom}.${var.domaine}"

  # Rocky Linux 10 exige x86-64-v3 (le noyau s'arrête au démarrage sinon, M03-E06).
  type_cpu = coalesce(var.type_cpu, var.famille == "rocky10" ? "x86-64-v3" : "x86-64-v2-AES")

  # Étiquettes triées et sans doublon : Proxmox les trie, une autre forme donnerait un écart
  # permanent au plan.
  etiquettes = sort(distinct(var.etiquettes))
}

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.nom
  node_name   = var.noeud
  vm_id       = var.vmid
  pool_id     = var.pool
  description = "${var.description}\nGérée par OpenTofu (module vm-noeud, plateforme/tofu-modules). Ne pas modifier à la main."
  tags        = local.etiquettes
  on_boot     = var.demarrage_auto
  protection  = var.protection
  started     = true

  clone {
    vm_id        = data.proxmox_virtual_environment_vms.image.vms[0].vm_id
    node_name    = data.proxmox_virtual_environment_vms.image.vms[0].node_name
    full         = true
    datastore_id = var.stockage
  }

  operating_system {
    type = "l26"
  }
  cpu {
    cores = var.coeurs
    type  = local.type_cpu
  }
  memory {
    dedicated = var.memoire_mo
  }
  # Un contrôleur SCSI par disque (iothread possible) ; c'est aussi ce qui fait apparaître les
  # disques comme /dev/sdX dans l'invité, avec l'attribut « rotational » piloté par ssd.
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
    ssd          = true
    iothread     = true
    discard      = "on"
  }

  dynamic "disk" {
    for_each = var.disques_donnees
    content {
      interface    = "scsi${disk.key + 1}"
      datastore_id = disk.value.datastore
      size         = disk.value.taille_go
      ssd          = disk.value.ssd
      backup       = disk.value.sauvegarde
      serial       = disk.value.serie
      iothread     = true
      discard      = "on"
    }
  }

  dynamic "network_device" {
    for_each = var.cartes
    content {
      bridge = network_device.value.vnet
      model  = "virtio"
      # MTU annoncé à l'invité par virtio (host_mtu) ; ne peut dépasser celui du pont
      # (vmbr1 en 9000 depuis M07-E15). 1500 : on laisse la valeur par défaut.
      mtu = network_device.value.mtu == 1500 ? null : network_device.value.mtu
    }
  }

  initialization {
    datastore_id = var.stockage

    # Un bloc ip_config par carte, dans le même ordre que les network_device.
    dynamic "ip_config" {
      for_each = var.cartes
      content {
        ipv4 {
          address = netbox_ip_address.carte[ip_config.key].ip_address
          gateway = ip_config.value.passerelle ? cidrhost(ip_config.value.prefixe, 1) : null
        }
      }
    }

    dns {
      domain  = var.domaine
      servers = var.resolveurs
    }

    user_account {
      username = "admin"
      keys     = [var.cle_ssh_admin]
    }
  }

  lifecycle {
    # Une nouvelle image « current » ne recrée aucun nœud : on reconstruit volontairement
    # (tofu apply -replace=…), un nœud à la fois, cluster sain (RB-081).
    ignore_changes = [clone, startup]
  }
}
