# k3s-ha.tf — banc k3s haute disponibilité JETABLE (M18-E07 ; réutilisé au palier 3).
#
# VMID de bac à sable 5190 + suffixe (5191-5193, PLAN.md §4.6) : vm-noeud refuse ces VMID (sa
# validation est 2000-2999, et il inscrit la VM dans NetBox). Ici, ressource directe :
#   - CLONE LIÉ de l'image dorée Debian « current » (règle M03 : clones liés pour le jetable),
#     donc rapide et léger sur le disque, mais lié au template (on ne supprime pas le template
#     tant que le banc existe) ;
#   - pas de NetBox, pas de DNS écrit par OpenTofu : DHCP + DDNS de Kea comme les autres VMs de
#     vsandbox, inventaire Ansible statique (inventories/lab/m18-k3s-ha.yml).
# Créer : k3s_ha_noeuds = ["k3s-ha01", "k3s-ha02", "k3s-ha03"] ; détruire : [].

variable "k3s_ha_noeuds" {
  description = "Noms des VMs jetables du banc k3s HA (k3s-ha01..k3s-ha09 → VMID 5191..5199)."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for n in var.k3s_ha_noeuds : can(regex("^k3s-ha0[1-9]$", n))])
    error_message = "k3s_ha_noeuds : noms k3s-ha01 à k3s-ha09."
  }
}

data "proxmox_virtual_environment_vms" "debian_current" {
  count = length(var.k3s_ha_noeuds) > 0 ? 1 : 0
  tags  = ["gold", "debian13", "current"]
  filter {
    name   = "template"
    values = ["true"]
  }
  lifecycle {
    postcondition {
      condition     = length(self.vms) == 1
      error_message = "Il faut exactement UN template gold/debian13/current."
    }
  }
}

resource "proxmox_virtual_environment_vm" "k3s_ha" {
  for_each = toset(var.k3s_ha_noeuds)

  name        = each.key
  node_name   = var.noeud
  vm_id       = 5190 + tonumber(substr(each.key, -1, 1))
  pool_id     = "lab"
  description = "M18-E07 : banc k3s HA jetable (clone lié). Gérée par OpenTofu (envs/m18, k3s-ha.tf)."
  tags        = sort(["env-m18", "role-k3s-ha"])
  on_boot     = false
  started     = true

  clone {
    vm_id        = data.proxmox_virtual_environment_vms.debian_current[0].vms[0].vm_id
    node_name    = data.proxmox_virtual_environment_vms.debian_current[0].vms[0].node_name
    full         = false
    datastore_id = "local-nvme"
  }

  operating_system {
    type = "l26"
  }
  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = 2048
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
    datastore_id = "local-nvme"
    size         = 20
    ssd          = true
    iothread     = true
    discard      = "on"
  }
  network_device {
    bridge      = "vsandbox"
    model       = "virtio"
    mac_address = format("bc:24:11:99:18:%02d", 90 + tonumber(substr(each.key, -1, 1)))
    firewall    = false
  }
  initialization {
    datastore_id = "local-nvme"
    ip_config {
      ipv4 {
        address = "dhcp"
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

output "k3s_ha" {
  description = "Banc k3s HA : nom => VMID."
  value       = { for n, v in proxmox_virtual_environment_vm.k3s_ha : n => v.vm_id }
}
