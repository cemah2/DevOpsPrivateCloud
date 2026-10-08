# envs/provisioning/pxe01.tf — plateforme/infra (M11-E02, PLAT-1202)
#
# pxe01 : TFTP (tftpd-hpa) + HTTP (nginx) du VLAN 60 PROV. VM d'environnement (état
# « provisioning »), PAS du socle : elle disparaît avec le module (mini-projet M11-E25).
# Adresse IMPOSÉE par PLAN.md §4.9 (10.10.60.10) : c'est le « next-server » annoncé par Kea,
# elle ne peut pas être allouée au hasard.

module "pxe01" {
  # Étiquette de version, jamais une branche (M05-E14). Prends la dernière v2.x publiée.
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v2.1.0"

  nom         = "pxe01"
  vmid        = 2111
  noeud       = var.noeud
  vnet        = "vprov"
  coeurs      = 1
  memoire_mo  = 1024
  disque_go   = 20 # noyaux, initrd, netboot Debian et Rocky (≈ 300 Mo par version gardée)
  stockage    = var.stockage
  etiquettes  = ["env-m11", "role-pxe"]
  description = "M11-E02 : TFTP + HTTP du VLAN 60 (PXE, iPXE, preseed, kickstart). Détruite en fin de module."

  reseau_prefixe = "10.10.60.0/24"
  ipv4_imposee   = "10.10.60.10"
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

# Nom direct et inverse (pxe01.par1.medisphere.internal) : iPXE télécharge par ce nom.
module "dns_pxe01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"

  nom  = module.pxe01.fqdn
  ipv4 = module.pxe01.ipv4
  ttl  = 300
}

output "pxe01" {
  description = "Identité de pxe01."
  value = {
    vmid = module.pxe01.vmid
    ipv4 = module.pxe01.ipv4_cidr
    fqdn = module.pxe01.fqdn
  }
}
