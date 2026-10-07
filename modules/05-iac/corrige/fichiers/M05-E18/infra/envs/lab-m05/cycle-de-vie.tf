# cycle-de-vie.tf — une VM jetable reconstruite à la demande, avec ses garde-fous (M05-E18).
#
# Ressource DIRECTE (pas le module) : un appel de module n'accepte pas de bloc lifecycle,
# et c'est précisément le cycle de vie qu'on règle ici.

variable "generation_jetable" {
  description = "Génération de la VM jetable (AAAA-MM-JJ). La changer RECRÉE la VM, sur l'image courante du jour."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.generation_jetable))
    error_message = "generation_jetable : une date AAAA-MM-JJ (ex. 2026-10-12)."
  }
}

# terraform_data : une « ressource » sans infrastructure, qui ne fait que porter une valeur
# dans l'état. Quand input change, elle est modifiée sur place (son output devient inconnu) :
# cette modification suffit à déclencher le remplacement de la VM (replace_triggered_by).
resource "terraform_data" "generation_jetable" {
  input = var.generation_jetable
}

resource "proxmox_virtual_environment_vm" "jetable" {
  node_name   = var.noeud
  vm_id       = 2054
  name        = "m05-jetable"
  description = "VM jetable, génération ${var.generation_jetable}. ${local.description}"
  tags        = local.etiquettes
  pool_id     = var.pool

  clone {
    vm_id        = local.image_vmid
    full         = true
    datastore_id = var.stockage_vm
  }

  on_boot         = false
  stop_on_destroy = true

  operating_system {
    type = "l26"
  }
  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = 1024
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
    size         = 10
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
    upgrade      = false
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

  lifecycle {
    # Nouvelle image « current » : on ne recrée PAS en silence (clone.* force le remplacement)…
    ignore_changes = [clone]
    # … mais on recrée volontairement quand la génération change.
    replace_triggered_by = [terraform_data.generation_jetable]

    # create_before_destroy est IMPOSSIBLE ici : la nouvelle VM aurait le même VMID (2054) et
    # le même nom que l'ancienne, encore vivante. Proxmox refuserait la création.

    precondition {
      condition     = startswith(local.image_nom, "deb13-gold-")
      error_message = "L'image courante (${local.image_nom}) n'est pas une image dorée Debian 13 : création refusée."
    }

    # Vérifiée APRÈS la création : la VM a obtenu un bail DHCP du VLAN 99 (dns01 via le relais
    # de gw01). Sinon l'apply échoue, au lieu de livrer une VM injoignable (E39).
    postcondition {
      condition     = anytrue([for a in flatten(self.ipv4_addresses) : startswith(a, "10.10.99.")])
      error_message = "m05-jetable n'a pas d'adresse dans 10.10.99.0/24 : DHCP du VLAN 99 en panne, ou agent QEMU muet."
    }
  }
}

output "jetable" {
  description = "VM jetable : génération, VMID et adresses remontées par l'agent."
  value = {
    generation = terraform_data.generation_jetable.output
    vm_id      = proxmox_virtual_environment_vm.jetable.vm_id
    ipv4       = [for a in flatten(proxmox_virtual_environment_vm.jetable.ipv4_addresses) : a if !startswith(a, "127.")]
  }
}
