# M06-E13 — une VM d'essai dont l'adresse est ALLOUÉE par NetBox (plage « statique » de
# SANDBOX, 10.10.99.10-49, PLAN.md §4.2) : aucune adresse n'est écrite dans ce dépôt.

module "ipam01" {
  # Étiquette de version, jamais une branche (M05-E14).
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v2.0.0"

  nom            = "m06-ipam01"
  vmid           = 2063
  noeud          = var.noeud
  vnet           = "vsandbox"
  etiquettes     = ["env-m06"]
  reseau_prefixe = "10.10.99.0/24"
  plage_adresses = "10.10.99.10"
  cle_ssh_admin  = var.cle_ssh_admin
  description    = "M06-E13 : adresse allouée par NetBox. Jetable."
}

output "ipam01" {
  value = {
    vmid = module.ipam01.vmid
    ipv4 = module.ipam01.ipv4_cidr
    fqdn = module.ipam01.fqdn
  }
}
