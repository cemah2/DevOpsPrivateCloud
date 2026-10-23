# envs/m27/pg-patroni.tf — grappe Patroni de comparaison (M27-E13, PLAT-2813).
#
# Trois VMs Debian 13 identiques : PostgreSQL 18 (PGDG), etcd (Debian 13) et Patroni 4.1.5 sur chacune.
# vsandbox (VLAN 99), adresses FIXES 10.10.99.71-73 (plage statique de SANDBOX, hors DHCP .100-.199) :
# la configuration d'etcd (initial-cluster) et de Patroni (connect_address) les cite en clair.
# 1 vCPU, 1 Go : de quoi faire tourner les trois démons, pas de quoi mesurer des performances.
# Pré-requis NetBox : étiquettes « env-m27 » et « role-pg-essai » (script de modélisation de M06-E05).
#
# Destruction en fin d'exercice : tofu destroy ; l'état reste (vide) et le code reste dans Git.

locals {
  pg_patroni = {
    "pg-patroni01" = { vmid = 2271, ipv4 = "10.10.99.71" }
    "pg-patroni02" = { vmid = 2272, ipv4 = "10.10.99.72" }
    "pg-patroni03" = { vmid = 2273, ipv4 = "10.10.99.73" }
  }
}

module "pg_patroni" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=<VERSION-TOFU-MODULES>"
  for_each = local.pg_patroni

  nom         = each.key
  vmid        = each.value.vmid
  noeud       = var.noeud
  vnet        = "vsandbox"
  coeurs      = 1
  memoire_mo  = 1024
  disque_go   = 16
  stockage    = "local-nvme"
  etiquettes  = ["env-m27", "role-pg-essai"]
  description = "Comparaison Patroni 4.1 / PostgreSQL 18 / etcd, M27-E13. Jetable."

  reseau_prefixe = "10.10.99.0/24"
  ipv4_imposee   = each.value.ipv4
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_pg_patroni" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"
  for_each = module.pg_patroni

  nom  = each.value.fqdn
  ipv4 = each.value.ipv4
  ttl  = 300
}

output "pg_patroni" {
  description = "VMs Patroni : VMID, adresse, nom."
  value = {
    for nom, vm in module.pg_patroni : nom => {
      vmid = vm.vmid
      ipv4 = vm.ipv4
      fqdn = vm.fqdn
    }
  }
}
