# s3-01.tf — stockage objet S3 du socle (M05-E10).
#
# PLAN.md §4.5 : VMID 1006, 10.10.20.14, VLAN 20 (VNet vinfra), SeaweedFS.
# Créée par une ressource directe ; M05-E17 la fait entrer dans le module vm-debian
# avec un bloc moved, sans la recréer.
#
# Clone COMPLET de l'image dorée courante (règle de M03 pour les VMs durables).
# Avec un clone, le provider applique ses propres valeurs par défaut à tout ce qui n'est
# pas écrit (cpu qemu64, scsi virtio-scsi-pci, agent désactivé…) : on écrit donc
# explicitement le matériel de l'image (M03-E09).
resource "proxmox_virtual_environment_vm" "s3_01" {
  node_name   = var.noeud
  vm_id       = 1006
  name        = "s3-01"
  description = "Stockage objet S3 du socle (SeaweedFS) — géré par OpenTofu (plateforme/infra, état socle). Ne pas modifier à la main."
  pool_id     = var.pool
  # Proxmox trie les étiquettes : une liste non triée donnerait un écart à chaque plan.
  tags = sort(["socle", "role-s3"])

  clone {
    vm_id        = local.image_debian13.vm_id
    full         = true
    datastore_id = var.datastore_systeme
  }

  on_boot = true
  startup {
    order    = 4 # après gw01 (1), dns01 (2), adm01 (3) ; même rang que git01
    up_delay = 0
  }

  # Matériel de l'image dorée (M03-E09)
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

  # Disque système : celui du template (8 Go), agrandi à 20 Go.
  disk {
    interface    = "scsi0"
    datastore_id = var.datastore_systeme
    size         = 20
    ssd          = true # comme l'image : TRIM transmis au NVMe
    iothread     = true
    discard      = "on"
  }

  # Disque de données S3 : nouveau disque sur le HDD. qcow2 (stockage de type répertoire) :
  # instantanés possibles (ms-snapshot, M02-E11) ; raw ne le permettrait pas sur ce stockage.
  # Vu dans la VM comme /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1 (rôle seaweedfs).
  disk {
    interface    = "scsi1"
    datastore_id = var.datastore_donnees
    size         = 100
    file_format  = "qcow2"
    iothread     = true
    discard      = "on"
    backup       = true # l'état OpenTofu vit ici : il DOIT être dans la sauvegarde nocturne
  }

  network_device {
    bridge = "vinfra"
    model  = "virtio"
  }

  initialization {
    datastore_id = var.datastore_systeme
    upgrade      = false # comme l'image : pas de mise à niveau complète au premier démarrage

    ip_config {
      ipv4 {
        address = "10.10.20.14/24"
        gateway = "10.10.20.1"
      }
    }

    dns {
      servers = var.dns.serveurs
      domain  = var.dns.domaine
    }

    user_account {
      username = "admin"
      keys     = var.cles_ssh_admin
    }
  }

  # Défense en profondeur : Proxmox refuse lui-même la suppression de la VM et de ses disques.
  protection = true

  lifecycle {
    # Cette VM porte l'état de toute l'infrastructure : un plan qui la détruit est refusé.
    prevent_destroy = true
    # L'image « current » change chaque semaine (M03) et clone.vm_id force le remplacement
    # (ForceNew) : sans cette ligne, chaque nouvelle image dorée recréerait s3-01.
    ignore_changes = [clone]
  }
}
