# main.tf — nœuds Proxmox VE imbriqués hv01..hv03 (M09-E03 ; hv03 en M09-E08).
#
# Ces VMs ne sont PAS des clones de l'image dorée : elles démarrent sur l'ISO officielle de
# Proxmox VE 9.2 préparée avec un fichier de réponse (installation/preparer-iso.sh). Ordre de
# démarrage « scsi0 puis ide2 » : disque vide au premier démarrage → SeaBIOS passe à l'ISO,
# l'installation automatique se lance ; au redémarrage, le disque est amorçable → Proxmox VE.
#
# Prérequis : l'ISO <prefixe_iso>-<nœud>.iso existe sur var.stockage_iso (sinon l'API refuse
# la création : « volume does not exist »).

resource "proxmox_virtual_environment_vm" "noeud" {
  for_each = var.noeuds

  node_name   = var.noeud
  vm_id       = each.value.vmid
  name        = each.key
  description = local.description
  tags        = local.etiquettes
  pool_id     = var.pool

  on_boot         = false # environnement de module : ne redémarre pas avec pve01
  started         = true  # démarrer = lancer l'installation automatique
  stop_on_destroy = true

  # Un hyperviseur se protège de la mémoire de son hôte : pas de ballon (floating = 0).
  memory {
    dedicated = 12288
    floating  = 0
  }

  # CPU « host » : expose VMX (Intel) au nœud, condition de la virtualisation imbriquée.
  # Conséquence : ces VMs ne migrent pas vers un hôte de CPU différent (sans objet ici).
  cpu {
    type  = "host"
    cores = 4
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  # Console série : accès de secours « qm terminal <VMID> » depuis pve01 (getty activé par le
  # rôle pve_noeud). L'écran VGA reste : l'installateur l'utilise.
  serial_device {}
  vga {
    type = "std"
  }

  # Pas d'agent QEMU dans Proxmox VE installé tel quel : le déclarer ferait attendre OpenTofu.
  agent {
    enabled = false
  }

  cdrom {
    interface = "ide2"
    file_id   = "${var.stockage_iso}:iso/${var.prefixe_iso}-${each.key}.iso"
  }

  boot_order = ["scsi0", "ide2"]

  dynamic "disk" {
    for_each = local.disques
    content {
      interface    = disk.value.interface
      datastore_id = disk.value.stockage
      size         = disk.value.taille
      file_format  = "raw"
      iothread     = true
      discard      = "on"
      ssd          = true
      serial       = "${each.key}-${disk.value.role}"
    }
  }

  dynamic "network_device" {
    for_each = local.cartes
    content {
      bridge      = network_device.value.pont
      model       = "virtio"
      mac_address = local.macs[each.key][network_device.key]
      mtu         = network_device.value.mtu
      trunks      = network_device.value.trunks
      # Pare-feu de pve01 DÉSACTIVÉ sur les cinq cartes, en particulier net4 : avec le pare-feu
      # de la VM, le filtrage MAC (option macfilter, active par défaut) jetterait toute trame
      # dont l'adresse source n'est pas celle de la carte, donc celles des invités imbriqués.
      firewall = false
    }
  }

  lifecycle {
    # Garde-fou : l'ordre et le nombre des cartes sont un contrat avec le fichier de réponse
    # (noms épinglés nic0..nic4) et avec le rôle pve_noeud (/etc/network/interfaces).
    precondition {
      condition     = length(local.cartes) == 5
      error_message = "Un nœud hv-par1 a exactement cinq cartes réseau (net0 à net4)."
    }
  }
}
