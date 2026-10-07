# main.tf — première VM déclarée : m05-essai, VMID 2050 (M05-E04).
#
# Valeurs écrites « en dur » pour ce premier essai ; M05-E06 les transforme en variables,
# M05-E08 remplace le VMID du template par une source de données.
#   - 9012 : VMID de l'image dorée Debian 13 étiquetée « current » LE JOUR DE L'EXERCICE
#            (à lire avec « qm list » et « qm config <VMID> | grep tags » sur pve01) ;
#   - "pve01" : <NOEUD>, le nom réel du nœud (hostname de pve01).

data "proxmox_version" "pve01" {}

resource "proxmox_virtual_environment_vm" "essai" {
  node_name   = "pve01" # <NOEUD>
  vm_id       = 2050
  name        = "m05-essai"
  description = "VM d'essai du module 05. Gérée par OpenTofu (plateforme/infra, envs/lab-m05) : ne pas modifier à la main."
  # Toujours déclarer les étiquettes : sans elles, le clone HÉRITE de celles du template
  # (gold, debian13, current) et le provider ne le signale pas.
  tags    = ["env-m05"]
  pool_id = "lab"

  # Clone COMPLET (règle PLAN : full = true pour toute VM qui dure plus d'une heure ;
  # c'est aussi le défaut du provider, écrit pour être lu).
  clone {
    vm_id        = 9012 # <VMID-CURRENT> : changer cette valeur RECRÉE la VM (ForceNew)
    full         = true
    datastore_id = "local-nvme"
  }

  # VM d'environnement : ne redémarre pas avec pve01 (défaut du provider : true !),
  # démarre après création, et s'arrête net à la destruction (rien à préserver).
  on_boot         = false
  started         = true
  stop_on_destroy = true

  # Matériel : on redit ce qu'est l'image dorée. Ce qui n'est pas écrit ici prend la
  # valeur par défaut du PROVIDER (qemu64, virtio-scsi-pci, 512 Mo…), pas celle du template.
  operating_system {
    type = "l26"
  }
  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = 1024
  }
  scsi_hardware = "virtio-scsi-single"
  serial_device {} # port série « socket », comme le template
  vga {
    type = "serial0" # console série (qm terminal), comme le template
  }

  agent {
    enabled = true # l'image dorée contient qemu-guest-agent (M03)
    timeout = "5m" # au lieu de 15 min : une VM sans agent doit échouer vite
  }

  # Disque système du clone, agrandi de 8 à 10 Go. Quand on décrit un disque cloné, il faut
  # redire TOUS ses attributs différents des défauts du provider (sinon ils sont écrasés).
  disk {
    interface    = "scsi0"
    datastore_id = "local-nvme"
    size         = 10
    file_format  = "raw"
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = "vsandbox" # VNet du VLAN 99 (DHCP de dns01, relayé par gw01)
    model  = "virtio"
  }

  # cloud-init (lecteur NoCloud généré par Proxmox) : compte admin + clé d'adm01, DHCP.
  initialization {
    datastore_id = "local-nvme"
    dns {
      domain  = "par1.medisphere.internal"
      servers = ["10.10.20.10"]
    }
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_account {
      username = "admin"
      # Clé PUBLIQUE : pas un secret. pathexpand() parce que file() ne connaît pas « ~ ».
      keys = [trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))]
    }
  }
}

output "version_pve" {
  description = "Version de Proxmox VE lue par l'API."
  value       = data.proxmox_version.pve01.version
}

output "essai_ipv4" {
  description = "Adresses IPv4 de m05-essai rapportées par l'agent QEMU (hors boucle locale)."
  value       = [for a in flatten(proxmox_virtual_environment_vm.essai.ipv4_addresses) : a if !startswith(a, "127.")]
}
