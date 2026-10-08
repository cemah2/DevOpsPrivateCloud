# envs/provisioning/bm.tf — plateforme/infra (M11-E03, PLAT-1203)
#
# Quatre « serveurs nus » : VMs SANS système, sans clone, sans cloud-init, qui démarrent sur
# le réseau. Elles simulent le matériel livré en salle : OpenTofu joue ici le rôle du
# fournisseur (il « fabrique » la machine et son adresse MAC), PAS celui de la source de vérité.
# L'intention (nom, plateforme, statut) est décrite dans NetBox à partir de M11-E06.
#
# Adresses MAC FIXÉES, localement administrées (bit 0x02 du premier octet) : 02:4d:53 (« MS »),
# puis 60 (le VLAN) et le numéro de la machine. Une MAC aléatoire changerait à chaque
# recréation et casserait les réservations DHCP et les scripts iPXE par MAC.
#
#   bm01  SeaBIOS  Debian 13      2 Go  20 Go
#   bm02  SeaBIOS  Rocky Linux 10 3 Go  20 Go   (installateur réseau de Rocky : 3 Gio conseillés)
#   bm03  OVMF     Debian 13      2 Go  20 Go
#   bm04  OVMF     Rocky Linux 10 4 Go  32 Go   (puis Proxmox VE en M11-E14 : 8 Go à ce moment-là)

locals {
  bm = {
    bm01 = { vmid = 2112, mac = "02:4D:53:60:00:01", uefi = false, memoire_mo = 2048, disque_go = 20 }
    bm02 = { vmid = 2113, mac = "02:4D:53:60:00:02", uefi = false, memoire_mo = 3072, disque_go = 20 }
    bm03 = { vmid = 2114, mac = "02:4D:53:60:00:03", uefi = true, memoire_mo = 2048, disque_go = 20 }
    bm04 = { vmid = 2115, mac = "02:4D:53:60:00:04", uefi = true, memoire_mo = 4096, disque_go = 32 }
  }
}

resource "proxmox_virtual_environment_vm" "bm" {
  for_each = local.bm

  name        = each.key
  node_name   = var.noeud
  vm_id       = each.value.vmid
  pool_id     = "lab"
  description = "M11-E03 : serveur nu (${each.value.uefi ? "UEFI, OVMF" : "BIOS, SeaBIOS"}), démarrage réseau. Jetable."
  tags        = ["env-m11", "role-bm"]
  on_boot     = false
  # Une machine neuve n'est pas allumée par OpenTofu : c'est le pilotage d'alimentation
  # (qm start, M11-E08, MAAS en M11-E10) qui décide quand elle démarre.
  started = false

  bios = each.value.uefi ? "ovmf" : "seabios"
  # Le réseau D'ABORD, le disque ensuite : sur un disque vide, le micrologiciel passe au
  # suivant ; une fois installé, c'est le script iPXE qui renvoie vers le disque local.
  boot_order = ["net0", "scsi0"]

  # OVMF garde ses variables (ordre de démarrage, Secure Boot) dans un petit disque.
  # pre_enrolled_keys = false : Secure Boot DÉSACTIVÉ. Le binaire ipxe.efi de Debian n'est pas
  # signé par Microsoft : avec les clés préinstallées, OVMF refuserait de le lancer.
  dynamic "efi_disk" {
    for_each = each.value.uefi ? [1] : []
    content {
      datastore_id      = var.stockage
      file_format       = "raw"
      type              = "4m"
      pre_enrolled_keys = false
    }
  }

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

  # Rocky Linux 10 exige un CPU x86-64-v3 (AVX2…) : « host » expose le Xeon E-2378G tel quel.
  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = each.value.memoire_mo
  }

  # L'agent sera installé par le preseed / kickstart : il permet de lire l'adresse obtenue.
  agent {
    enabled = true
  }

  disk {
    datastore_id = var.stockage
    interface    = "scsi0"
    size         = each.value.disque_go
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge      = "vprov"
    model       = "virtio"
    mac_address = each.value.mac
  }

  # Console série : qm terminal pour suivre un installateur bloqué (palier 4).
  serial_device {}

  operating_system {
    type = "l26"
  }
}

output "bm" {
  description = "Serveurs nus : VMID et adresse MAC (à reporter dans NetBox en M11-E06)."
  value       = { for k, v in local.bm : k => { vmid = v.vmid, mac = lower(v.mac), uefi = v.uefi } }
}
