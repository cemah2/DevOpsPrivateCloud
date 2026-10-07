# data.tf — ce que l'environnement LIT dans Proxmox sans le gérer (M05-E08).

# L'image dorée Debian 13 publiée : un template étiqueté gold + debian13 + current (M03-E10).
# On la désigne par ce qu'elle EST, pas par son numéro : le VMID change à chaque publication.
data "proxmox_virtual_environment_vms" "image_courante" {
  node_name = var.noeud
  tags      = ["current", "debian13", "gold"] # la VM doit porter TOUTES ces étiquettes

  # Un clone sans étiquettes déclarées hérite de celles du template (« current » compris) :
  # sans ce filtre, une VM ordinaire pourrait être prise pour l'image.
  filter {
    name   = "template"
    values = [true]
  }
  filter {
    name   = "name"
    regex  = true
    values = ["^deb13-gold-[0-9]{8}-[0-9]+$"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.vms) == 1
      error_message = "Il faut exactement UNE image dorée Debian 13 étiquetée current (trouvé : ${length(self.vms)}). Vérifie la publication des images (M03-E10) avant tout plan."
    }
  }
}

locals {
  image_vmid = data.proxmox_virtual_environment_vms.image_courante.vms[0].vm_id
  image_nom  = data.proxmox_virtual_environment_vms.image_courante.vms[0].name
}

# Contrôle non bloquant : signalé (avertissement) à chaque plan, n'empêche pas l'apply.
check "place_sur_le_stockage_des_vms" {
  data "proxmox_datastores" "vms" {
    node_name = var.noeud
    filters = {
      id = var.stockage_vm
    }
  }

  assert {
    condition     = alltrue([for d in data.proxmox_datastores.vms.datastores : coalesce(d.space_available, 0) > 50 * 1024 * 1024 * 1024])
    error_message = "Moins de 50 Gio libres sur ${var.stockage_vm} : un clone complet de plus pourrait remplir le stockage."
  }
}
