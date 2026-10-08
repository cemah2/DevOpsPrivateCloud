# vm-debian v2.2 — la VM Proxmox (M06-E13, étendu en M10-E02).
# v2 : l'adresse et la passerelle de cloud-init viennent de netbox.tf.
# v2.2 : type de CPU, MAC et MTU de la carte principale, cartes supplémentaires (net1…),
# chacune avec sa MAC, sa MTU et, si elle est adressée, son bloc ip_config (sans passerelle).

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

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.nom
  node_name   = var.noeud
  vm_id       = var.vmid
  pool_id     = var.pool
  description = var.description
  tags        = sort(distinct(var.etiquettes))
  on_boot     = var.demarrage_auto
  started     = true

  # Clone COMPLET de l'image courante (règle PLAN, journal du 2026-10-07).
  clone {
    vm_id        = data.proxmox_virtual_environment_vms.image.vms[0].vm_id
    node_name    = data.proxmox_virtual_environment_vms.image.vms[0].node_name
    full         = true
    datastore_id = var.stockage
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.coeurs
    type  = var.type_cpu
  }

  memory {
    dedicated = var.memoire_mo
  }

  disk {
    datastore_id = var.stockage
    interface    = "scsi0"
    size         = var.disque_go
    discard      = "on"
    iothread     = true
  }

  # Carte principale (net0). firewall = false : valeur par défaut du fournisseur, écrite ici
  # pour qu'on la lise (aucun filtrage MAC/IP de Proxmox sur les cartes du lab).
  network_device {
    bridge      = var.vnet
    model       = "virtio"
    mac_address = var.mac_adresse == null ? null : upper(var.mac_adresse)
    mtu         = var.mtu
    firewall    = false
  }

  # Cartes supplémentaires (net1, net2…), dans l'ordre de la liste.
  dynamic "network_device" {
    for_each = var.cartes_supplementaires
    content {
      bridge      = network_device.value.vnet
      model       = "virtio"
      mac_address = network_device.value.mac_adresse == null ? null : upper(network_device.value.mac_adresse)
      mtu         = network_device.value.mtu
      firewall    = false
    }
  }

  serial_device {}

  operating_system {
    type = "l26"
  }

  # Pas de bloc startup : régler l'ordre de démarrage exige Sys.Modify sur « / »
  # (refus 403 pour wb-tofu, voir M05-E10). Il est posé en root après création :
  #   root@pve01:~# qm set <VMID> --startup order=<N>
  # et ignoré ci-dessous pour qu'OpenTofu ne l'efface pas.

  initialization {
    datastore_id = var.stockage

    # ipconfig0 : carte principale, avec la passerelle.
    ip_config {
      ipv4 {
        address = local.ipv4_cidr
        gateway = local.passerelle
      }
    }

    # ipconfig1… : cartes supplémentaires ADRESSÉES, sans passerelle (validation : elles
    # précèdent les cartes sans adresse, donc ipconfigN correspond bien à netN).
    dynamic "ip_config" {
      for_each = [for c in var.cartes_supplementaires : c if c.ipv4_imposee != null]
      content {
        ipv4 {
          address = "${ip_config.value.ipv4_imposee}/${split("/", ip_config.value.prefixe)[1]}"
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
    # Une nouvelle image « current » ne doit pas faire recréer les VMs existantes : on la
    # prend au prochain remplacement volontaire (taint / replace), jamais par surprise.
    ignore_changes = [clone, startup]
  }
}
