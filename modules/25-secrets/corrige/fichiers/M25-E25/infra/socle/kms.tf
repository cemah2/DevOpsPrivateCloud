# socle/kms.tf — plateforme/infra, état « socle » (M25-E25, ticket PLAT-2625).
#
# kms01 : OpenBao mononœud qui ne sert QUE le seal « transit » de la grappe vault01-03 (PLAN §4.5,
# §4.12). VMID 1024, 10.10.20.24, VLAN 20, Debian 13, 1 vCPU, 1 Go, 16 Go. Étiquettes socle +
# role-kms (groupe Ansible role_kms, rôle openbao_kms).
# Pas de VIP, pas de grappe : un seul nœud, scellé par Shamir (ses propres dépositaires). Sa perte
# n'arrête pas une grappe déjà descellée, mais empêche tout nœud de redémarrer (RB-251).
# Ordre de démarrage 3 : AVANT vault01-03 (ordre 4), qui en ont besoin pour se desceller.
#   root@pve01:~# qm set 1024 --startup order=3

module "kms01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=<VERSION-TOFU-MODULES>"

  nom         = "kms01"
  vmid        = 1024
  noeud       = var.noeud
  vnet        = "vinfra"
  coeurs      = 1
  memoire_mo  = 1024
  disque_go   = 16
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-kms"]
  description = "OpenBao de descellement (transit) de la grappe vault01-03, scellé par Shamir (M25-E25)."

  reseau_prefixe = "10.10.20.0/24"
  ipv4_imposee   = "10.10.20.24"
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_kms01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"

  nom  = module.kms01.fqdn
  ipv4 = module.kms01.ipv4
  ttl  = 3600
}

output "kms01" {
  description = "Identité de kms01 (VMID, adresse, nom)."
  value       = { vmid = module.kms01.vmid, ipv4 = module.kms01.ipv4, fqdn = module.kms01.fqdn }
}
