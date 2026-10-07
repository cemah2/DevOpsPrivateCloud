# nbx01.tf — source de vérité du socle (M06-E04).
#
# PLAN.md §4.5 : VMID 1005, 10.10.20.13, VLAN 20 (VNet vinfra), NetBox 4.6.
# Créée par le module versionné vm-debian (M05-E13/E14) : clone COMPLET de l'image dorée
# « current », étiquettes socle + role-netbox (groupe Ansible role_netbox), protection Proxmox.
# Version du module : la dernière publiée dans plateforme/tofu-modules (adapter ?ref=).
module "nbx01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.0.0"

  nom         = "nbx01"
  vm_id       = 1005
  noeud       = var.noeud
  pool        = var.pool
  description = "Source de vérité du socle (NetBox 4.6, PostgreSQL 17, Valkey) — sauvegardes applicatives : M06-E28."
  socle       = true
  role        = "netbox"

  coeurs            = 2
  memoire_mo        = 4096
  datastore_systeme = var.datastore_systeme
  disque_systeme_go = 30

  reseau = {
    vnet       = "vinfra"
    ipv4       = "10.10.20.13/24"
    passerelle = "10.10.20.1"
  }
  dns      = var.dns
  cles_ssh = var.cles_ssh_admin

  demarrage_auto = true
  # Après les services dont il dépend : DNS (2), PKI (3), forge et S3 (4), runner (5).
  ordre_demarrage = 6
  protection      = true
}

output "nbx01" {
  description = "Source de vérité du socle (NetBox)."
  value = {
    vm_id = module.nbx01.vm_id
    ipv4  = module.nbx01.ipv4
  }
}
