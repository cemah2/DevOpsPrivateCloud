# main.tf — module vm-debian : une VM Debian clonée de l'image dorée (M05-E13).
#
# Clone COMPLET : la VM ne dépend plus de son template, qui peut être supprimé ou
# remplacé (règle M03). Le matériel de l'image est réécrit explicitement : avec un clone,
# le provider remplace par SES valeurs par défaut tout ce qui n'est pas écrit.

# --- Image source : template doré courant, sauf si un VMID est imposé ------------------------
data "proxmox_virtual_environment_vms" "image" {
  count = var.image.vm_id == null ? 1 : 0

  tags = ["gold", var.image.famille, "current"]

  filter {
    name   = "template"
    values = ["true"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.vms) == 1
      error_message = "Il faut exactement UN template gold/${var.image.famille}/current : ${length(self.vms)} trouvé(s) (catalogue d'images, M03)."
    }
  }
}

locals {
  image_vm_id = var.image.vm_id != null ? var.image.vm_id : data.proxmox_virtual_environment_vms.image[0].vms[0].vm_id

  # Étiquettes triées et sans doublon : Proxmox les trie, une autre forme donnerait un
  # écart permanent au plan.
  etiquettes = sort(distinct(compact(concat(
    var.socle ? ["socle"] : [],
    var.role != null ? ["role-${var.role}"] : [],
    var.environnement != null ? ["env-${var.environnement}"] : [],
    var.etiquettes,
  ))))

  description = trimspace(join("\n", compact([
    var.description,
    "Gérée par OpenTofu (module vm-debian, plateforme/tofu-modules). Ne pas modifier à la main.",
  ])))

  statique = var.reseau.ipv4 != "dhcp"
}

resource "proxmox_virtual_environment_vm" "vm" {
  node_name   = var.noeud
  vm_id       = var.vm_id
  name        = var.nom
  description = local.description
  pool_id     = var.pool
  tags        = local.etiquettes
  protection  = var.protection

  clone {
    vm_id        = local.image_vm_id
    full         = true
    datastore_id = var.datastore_systeme
  }

  on_boot         = var.demarrage_auto
  stop_on_destroy = var.arret_force
  dynamic "startup" {
    for_each = var.ordre_demarrage == null ? [] : [var.ordre_demarrage]
    content {
      order = startup.value
    }
  }

  # Matériel de l'image dorée (M03-E09)
  operating_system {
    type = "l26"
  }
  cpu {
    cores = var.coeurs
    type  = var.type_cpu
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
    datastore_id = var.datastore_systeme
    size         = var.disque_systeme_go
    ssd          = var.disque_systeme_ssd
    iothread     = true
    discard      = "on"
  }

  dynamic "disk" {
    for_each = var.disques_donnees
    content {
      interface    = "scsi${disk.key + 1}"
      datastore_id = disk.value.datastore
      size         = disk.value.taille_go
      file_format  = disk.value.format
      ssd          = disk.value.ssd
      backup       = disk.value.sauvegarde
      iothread     = true
      discard      = "on"
    }
  }

  network_device {
    bridge = var.reseau.vnet
    model  = "virtio"
  }

  initialization {
    datastore_id        = var.datastore_systeme
    upgrade             = false
    user_data_file_id   = var.user_data_file_id
    vendor_data_file_id = var.vendor_data_file_id

    ip_config {
      ipv4 {
        address = var.reseau.ipv4
        gateway = local.statique ? var.reseau.passerelle : null
      }
    }

    dns {
      servers = var.dns.serveurs
      domain  = var.dns.domaine
    }

    # user_account et user_data_file_id s'excluent : avec un snippet, c'est lui qui crée
    # les comptes (M05-E19).
    dynamic "user_account" {
      for_each = var.user_data_file_id == null ? [1] : []
      content {
        username = var.utilisateur
        keys     = var.cles_ssh
      }
    }
  }

  lifecycle {
    # Protection d'OpenTofu au choix de l'appelant (socle : true). Depuis OpenTofu 1.12,
    # prevent_destroy accepte une variable du module ; avant, seulement un littéral.
    prevent_destroy = var.proteger

    # clone : une nouvelle image « current » (chaque semaine, M03) change clone.vm_id, qui
    # force le remplacement : sans cette ligne, chaque publication d'image recréerait toutes
    # les VMs. On reconstruit une VM sur la nouvelle image volontairement (-replace=…).
    # startup : réglage de l'hôte (Sys.Modify sur « / ») que le jeton d'OpenTofu ne peut pas
    # modifier ; posé en root, il ne doit pas faire échouer les applies suivants.
    ignore_changes = [clone, startup]

    precondition {
      condition     = length(var.cles_ssh) > 0 || var.user_data_file_id != null
      error_message = "Aucun accès possible : fournis cles_ssh, ou un snippet user_data_file_id qui crée les comptes."
    }
  }
}
