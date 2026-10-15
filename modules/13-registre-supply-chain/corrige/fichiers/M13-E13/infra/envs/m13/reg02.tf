# envs/m13/reg02.tf — Harbor de test du module 13 (M13-E13 ; reconstruit en M13-E15 ; détruit en M13-E25).
#
# Même module et même forme que socle/reg01.tf (M13-E02) : si reg02 demande autre chose, c'est que le
# code de reg01 supposait quelque chose. Différences assumées :
#   - VNet vsandbox (VLAN 99), adresse imposée 10.10.99.31 (plage statique de SANDBOX) : une seule
#     adresse à ouvrir sur la bordure, un nom stable pour le certificat ;
#   - 4 Go (la doc de Harbor donne 4 Go au minimum ; Trivy ne tourne que pour les essais) ;
#   - disque de données de 64 Gio sur local-nvme (pas de hdd-bulk : volume limité, essais rapides) ;
#   - pas de « protection » ni de démarrage automatique : VM jetable.
# Pré-requis NetBox : étiquettes « env-m13 » et « role-registre ».

module "reg02" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=<VERSION-TOFU-MODULES>"

  nom         = "reg02"
  vmid        = 2131
  noeud       = var.noeud
  vnet        = "vsandbox"
  coeurs      = 2
  memoire_mo  = 4096
  disque_go   = 32
  stockage    = "local-nvme"
  etiquettes  = ["env-m13", "role-registre"]
  description = "Harbor de test (réplication, restauration, répétition des mises à jour), M13-E13. Jetable."

  disques_donnees = [
    { taille_go = 64, datastore = "local-nvme", sauvegarde = false, serie = "reg02-donnees" },
  ]

  reseau_prefixe = "10.10.99.0/24"
  ipv4_imposee   = "10.10.99.31"
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_reg02" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"

  nom  = module.reg02.fqdn
  ipv4 = module.reg02.ipv4
  ttl  = 300
}

output "reg02" {
  description = "Identité de reg02 (VMID, adresse, nom)."
  value = {
    vmid = module.reg02.vmid
    ipv4 = module.reg02.ipv4
    fqdn = module.reg02.fqdn
  }
}
