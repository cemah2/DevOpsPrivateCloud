# images.tf — image dorée Debian 13 courante (M05-E10, même logique que M05-E08).
#
# Le template porte les étiquettes gold + debian13 + current (posées par
# outils/publier-image.sh, M03) : on le trouve par ses étiquettes, jamais par son VMID,
# qui change à chaque publication (9010-9029).
data "proxmox_virtual_environment_vms" "image_debian13" {
  tags = ["gold", "debian13", "current"]

  filter {
    name   = "template"
    values = ["true"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.vms) == 1
      error_message = "Il faut exactement UN template gold/debian13/current (catalogue d'images, M03-E10) : ${length(self.vms)} trouvé(s)."
    }
  }
}

locals {
  image_debian13 = data.proxmox_virtual_environment_vms.image_debian13.vms[0]
}
