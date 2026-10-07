# ca01.tf — autorité de certification du socle (M06-E02).
#
# PLAN.md §4.5 : VMID 1003, 10.10.20.11, VLAN 20 (VNet vinfra), step-ca.
# Créée par le module versionné vm-debian (M05-E13/E14) : clone COMPLET de l'image dorée
# « current », étiquettes socle + role-pki (groupe Ansible role_pki), protection Proxmox.
# Version du module : la dernière publiée dans plateforme/tofu-modules (adapter ?ref=).
module "ca01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.1.0"

  nom         = "ca01"
  vm_id       = 1003
  noeud       = var.noeud
  pool        = var.pool
  description = "Autorité de certification du socle (step-ca, intermédiaire en ligne). Racine HORS LIGNE : jamais sur cette VM."
  socle       = true
  role        = "pki"

  coeurs            = 1
  memoire_mo        = 1024
  datastore_systeme = var.datastore_systeme
  disque_systeme_go = 10

  reseau = {
    vnet       = "vinfra"
    ipv4       = "10.10.20.11/24"
    passerelle = "10.10.20.1"
  }
  dns      = var.dns
  cles_ssh = var.cles_ssh_admin

  demarrage_auto = true
  # Après gw01 (1) et dns01 (2) ; avant git01 et s3-01 (4), dont les certificats en dépendent.
  # Ordre de démarrage 3 posé en root après création (Sys.Modify sur « / ») :
  #   root@pve01:~# qm set 1003 --startup order=3
  protection      = true
}

output "ca01" {
  description = "Autorité de certification du socle."
  value = {
    vm_id = module.ca01.vm_id
    ipv4  = module.ca01.ipv4
  }
}
