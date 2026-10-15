# vm-debian v2 — la VM Proxmox (M06-E13 ; disques de données ajoutés en M13-E02).
# Inchangé par rapport à v1 (M05-E13) sauf l'adressage : l'adresse et la passerelle de
# cloud-init viennent maintenant de netbox.tf.
# M13-E02 (version MINEURE du dépôt) : liste facultative « disques_donnees », vide par défaut.
# Un bloc dynamic sur une liste vide ne produit aucun bloc : le plan des VMs existantes
# (dns02, lb01, lb02, runner02…) ne change pas. Même schéma que vm-noeud (M08-E02).

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
    type  = "x86-64-v2-AES"
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

  # Disques de données (M13-E02) : scsi1, scsi2… dans l'ordre de la liste. Le numéro de série
  # rend le disque reconnaissable dans l'invité (/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_<série>).
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

  network_device {
    bridge = var.vnet
    model  = "virtio"
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
    ip_config {
      ipv4 {
        address = local.ipv4_cidr
        gateway = local.passerelle
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
