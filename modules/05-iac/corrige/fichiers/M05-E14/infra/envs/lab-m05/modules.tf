# modules.tf — première consommation du module versionné (M05-E14).
#
# Une VM d'essai (2054, détruite en fin d'exercice) créée par le module vm-debian à une version
# EXACTE. Changer de version = changer ?ref= dans une MR, « tofu init -upgrade », relire le plan.
module "essai_module" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.1.0"

  nom           = "m05-module"
  vm_id         = 2054
  noeud         = var.noeud
  environnement = "m05"
  memoire_mo    = 1024
  reseau        = { vnet = "vsandbox" } # DHCP de dns01 (10.10.99.100-199)
  cles_ssh      = var.cles_ssh_admin
}

output "essai_module" {
  description = "VM d'essai créée par le module versionné."
  value = {
    vm_id = module.essai_module.vm_id
    ipv4  = module.essai_module.ipv4
    image = module.essai_module.image_source
  }
}
