# talos.tf — nœuds Talos Linux du module 18 (M18-E05, groupe « talos »).
#
# Pas de vm-noeud : il clone une image dorée Debian/Rocky. Ici, le disque vient d'une image Talos
# « nocloud » de l'Image Factory, et le matériel suit la page Proxmox de la documentation Talos 1.14 :
#   - contrôleur VirtIO SCSI (virtio-scsi-pci) : PAS « VirtIO SCSI single », qui bloque l'amorçage ;
#   - UEFI (ovmf) + disque EFI sans clés préinscrites, machine q35 ;
#   - pas de ballon mémoire (Talos ne gère pas l'ajout de mémoire à chaud) ;
#   - agent QEMU activé : l'image contient l'extension siderolabs/qemu-guest-agent.
# Réseau : vsandbox avec ADRESSES FIXES 10.10.99.85-87 (point d'accès stable de talosctl et des
# certificats), remises par le lecteur cloud-init de Proxmox, que Talos lit au format nocloud.
# Talos ignore le user-data « #cloud-config » de Proxmox pour la configuration machine, mais en
# reprend le nom d'hôte. La configuration machine arrive ensuite par talosctl (mode maintenance).
# Pas dans NetBox (pas d'agent d'inventaire ni d'Ansible sur Talos) : écart noté dans la fiche talos.md.

locals {
  # Identifiant du schéma talos-schema.yaml (Image Factory, API /schematics).
  talos_schema_id = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"

  talos_noeuds = contains(var.groupes, "talos") ? {
    talos-01 = { vmid = 2185, ipv4 = "10.10.99.85", role = "controlplane" }
    talos-02 = { vmid = 2186, ipv4 = "10.10.99.86", role = "worker" }
    talos-03 = { vmid = 2187, ipv4 = "10.10.99.87", role = "worker" }
  } : {}
}

variable "talos_version" {
  description = "Version de Talos de l'IMAGE DE DÉPART (les montées de version se font par talosctl upgrade, M18-E06)."
  type        = string
  default     = "v1.14.1"
}

variable "talos_image_sha256" {
  description = "Empreinte SHA-256 de nocloud-amd64.raw.zst pour ce schéma et cette version (relevée le 2026-10-15)."
  type        = string
  default     = "2ce91eaacaf2d0b5b7bb19d681dd1a312695a8d7c2c2b914dca3513b6af3724d"
}

# L'image, téléchargée par Proxmox lui-même sur hdd-bulk (contenu « iso » : pas besoin d'ajouter
# le type « import » au stockage), décompressée à l'arrivée. Une seule copie pour les trois VMs.
resource "proxmox_download_file" "talos" {
  count = length(local.talos_noeuds) > 0 ? 1 : 0

  node_name               = var.noeud
  datastore_id            = "hdd-bulk"
  content_type            = "iso"
  url                     = "https://factory.talos.dev/image/${local.talos_schema_id}/${var.talos_version}/nocloud-amd64.raw.zst"
  file_name               = "talos-${var.talos_version}-${substr(local.talos_schema_id, 0, 8)}-nocloud-amd64.img"
  decompression_algorithm = "zst"
  checksum                = var.talos_image_sha256
  checksum_algorithm      = "sha256"
  # Une nouvelle image ne remplace pas le fichier en place (et ne recrée donc aucun nœud) :
  # les nœuds vivants montent de version par talosctl upgrade.
  overwrite      = false
  upload_timeout = 1200
}

resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.talos_noeuds

  name        = each.key
  node_name   = var.noeud
  vm_id       = each.value.vmid
  pool_id     = "lab"
  description = "M18 : Talos Linux (${each.value.role}), cluster talos-essai. Gérée par OpenTofu (envs/m18, talos.tf). Pas de SSH : talosctl."
  tags        = sort(["env-m18", "role-talos"])
  on_boot     = false
  started     = true

  bios    = "ovmf"
  machine = "q35"
  operating_system {
    type = "l26"
  }
  cpu {
    cores = 2
    # Talos exige x86-64-v2 : le type par défaut de vm-noeud pour Debian suffit.
    type = "x86-64-v2-AES"
  }
  memory {
    dedicated = 3072
    floating  = 0 # pas de ballon
  }
  efi_disk {
    datastore_id      = "local-nvme"
    type              = "4m"
    pre_enrolled_keys = false
  }
  scsi_hardware = "virtio-scsi-pci"
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
    file_id      = proxmox_download_file.talos[0].id
    size         = 20
    ssd          = true
    discard      = "on"
  }

  network_device {
    bridge      = "vsandbox"
    model       = "virtio"
    mac_address = format("bc:24:11:99:18:%02d", each.value.vmid % 100)
    firewall    = false
  }

  # Lecteur cloud-init (q35 : ide2) : réseau et nom d'hôte, rien d'autre. Pas de compte, pas de clé.
  initialization {
    datastore_id = "local-nvme"
    ip_config {
      ipv4 {
        address = "${each.value.ipv4}/24"
        gateway = "10.10.99.1"
      }
    }
    dns {
      domain  = "par1.medisphere.internal"
      servers = ["10.10.20.10", "10.10.20.16"]
    }
  }

  lifecycle {
    # Le disque d'origine ne compte plus après l'installation : Talos se met à jour lui-même (A/B).
    ignore_changes = [disk[0].file_id]
  }
}

module "dns_talos" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = local.talos_noeuds

  nom  = "${each.key}.par1.medisphere.internal"
  ipv4 = each.value.ipv4
}

output "talos" {
  description = "Nœuds Talos : VMID, adresse, rôle (point d'accès talosctl : 10.10.99.85)."
  value       = { for n, v in local.talos_noeuds : n => { vmid = v.vmid, ipv4 = v.ipv4, role = v.role } }
}
