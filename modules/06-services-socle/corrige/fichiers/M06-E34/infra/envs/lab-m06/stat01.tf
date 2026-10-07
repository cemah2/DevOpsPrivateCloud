# envs/lab-m06/stat01.tf — plateforme/infra, environnement « lab-m06 » (M06-E34, CHG-760)
#
# Service TEMPORAIRE : dans l'environnement du module (état envs/lab-m06, à côté de m06-ipam01
# de M06-E13), jamais dans « socle » : son retrait (suppression de ce fichier + apply, ou destroy
# de l'environnement) ne peut pas toucher une VM du socle.
# Adresse : la PREMIÈRE libre de la plage « statique » du VLAN INFRA (.10-.49, modélisée en
# M06-E05), allouée par NetBox via le module vm-debian v2 ; aucune adresse écrite ici.

module "stat01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v2.1.0"

  nom         = "stat01"
  vmid        = 2069
  noeud       = var.noeud
  vnet        = "vinfra"
  coeurs      = 1
  memoire_mo  = 1024
  disque_go   = 10
  stockage    = "local-nvme"
  etiquettes  = ["env-m06", "role-statut"]
  description = "M06-E34 : page d'information interne. Service temporaire, retiré après la démonstration."

  reseau_prefixe = "10.10.20.0/24"
  plage_adresses = "10.10.20.10" # une adresse CONTENUE dans la plage statique .10-.49
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_stat01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"

  nom  = module.stat01.fqdn
  ipv4 = module.stat01.ipv4
  ttl  = 300 # court : service temporaire
}

output "stat01" {
  description = "Identité de stat01 (adresse attribuée par NetBox)."
  value = {
    vmid = module.stat01.vmid
    ipv4 = module.stat01.ipv4_cidr
    fqdn = module.stat01.fqdn
  }
}
