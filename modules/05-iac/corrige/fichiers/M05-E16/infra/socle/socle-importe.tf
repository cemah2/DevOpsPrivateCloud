# socle-importe.tf — VMs du socle construites à la main (M00, M01) et importées (M05-E16).
#
# Valeurs relevées avec « qm config » et -generate-config-out sur le lab de référence :
# compare-les aux tiennes, ce sont TES VMs qui font foi (un écart au plan = une valeur à
# recopier ici, jamais une modification de la VM).
#
# gw01 (1000) n'est PAS ici : voir gw01.tf.

locals {
  # Matériel commun : clones du template 9000 (M00-E11), donc même socle matériel.
  socle_importe = {
    adm01 = {
      vm_id      = 1001
      coeurs     = 1
      memoire_mo = 2048
      disque_go  = 20
      vnet       = "vmgmt"
      ipv4       = "10.10.10.10/24"
      passerelle = "10.10.10.1"
      ordre      = 3
      role       = "bastion"
    }
    dns01 = {
      vm_id      = 1002
      coeurs     = 1
      memoire_mo = 1024
      disque_go  = 8
      vnet       = "vinfra"
      ipv4       = "10.10.20.10/24"
      passerelle = "10.10.20.1"
      ordre      = 2
      role       = "dns"
    }
    git01 = {
      vm_id      = 1004
      coeurs     = 4
      memoire_mo = 8192
      disque_go  = 50
      vnet       = "vinfra"
      ipv4       = "10.10.20.12/24"
      passerelle = "10.10.20.1"
      ordre      = 4
      role       = "gitlab"
    }
    runner01 = {
      vm_id      = 1007
      coeurs     = 2
      memoire_mo = 4096
      disque_go  = 30
      vnet       = "vinfra"
      ipv4       = "10.10.20.15/24"
      passerelle = "10.10.20.1"
      ordre      = 5
      role       = "runner"
    }
  }
}

resource "proxmox_virtual_environment_vm" "socle" {
  for_each = local.socle_importe

  node_name = var.noeud
  vm_id     = each.value.vm_id
  name      = each.key
  pool_id   = var.pool
  tags      = sort(["socle", "role-${each.value.role}"])

  on_boot = true
  startup {
    order = each.value.ordre
  }

  operating_system {
    type = "l26"
  }
  cpu {
    cores = each.value.coeurs
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = each.value.memoire_mo
  }
  scsi_hardware = "virtio-scsi-single"
  agent {
    enabled = true
    trim    = true # fstrim_cloned_disks=1 du template 9000
  }
  serial_device {}
  vga {
    type = "serial0"
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.datastore_systeme
    size         = each.value.disque_go
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = each.value.vnet
    model  = "virtio"
  }

  initialization {
    datastore_id = var.datastore_systeme
    interface    = "ide2"
    # Hérité du template 9000 (M00-E11). Attribut à REMPLACEMENT FORCÉ : l'omettre ferait
    # détruire et recréer la VM. On le déclare tel qu'il est.
    vendor_data_file_id = "hdd-bulk:snippets/vendor-debian13.yaml"

    ip_config {
      ipv4 {
        address = each.value.ipv4
        gateway = each.value.passerelle
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

  lifecycle {
    # VMs construites à la main, porteuses de données et de configuration non reproductibles
    # par ce code : aucun plan ne doit pouvoir les détruire (y compris par remplacement).
    prevent_destroy = true

    ignore_changes = [
      # Clés et mot de passe cloud-init : posés à la création (clé de pve01 en M00, ou clés
      # gérées depuis par le rôle Ansible base). Les réécrire régénérerait le lecteur
      # cloud-init (nouvelle « instance », clés d'hôte SSH régénérées, M00-E13) pour rien :
      # les comptes sont gérés par Ansible (ms_cles_admin).
      initialization[0].user_account,
      # Description : notes libres de l'équipe dans l'interface Proxmox.
      description,
      # Ordre de démarrage : réglage de l'hôte, que Proxmox ne laisse modifier qu'avec
      # Sys.Modify sur « / » (le jeton wb-tofu ne l'a pas). Déclaré ci-dessus pour la
      # documentation ; s'il diffère un jour, c'est root qui le change (qm set --startup).
      startup,
    ]
  }
}
