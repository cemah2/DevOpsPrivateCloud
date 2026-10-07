# main.tf — composant « vms » : les VMs d'un environnement de test (M05-E24).
#
# Chaque VM est créée par le module versionné vm-debian (M05-E13, M05-E14), à une version
# EXACTE (v1.1.0 depuis M05-E17 : remplace-la par ta dernière version publiée).
# Monter de version = une MR qui change ce ?ref=, relue sur son plan.
module "vm" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.1.0"
  for_each = var.vms

  nom         = "m05-${each.key}"
  vm_id       = each.value.vm_id
  noeud       = var.noeud
  pool        = var.pool
  description = "Environnement ${var.environnement} — Terragrunt, plateforme/infra/terragrunt/live/${var.environnement}"

  # Étiquettes : env-m05 (module) + le nom de l'environnement (inventaire Ansible, ménage).
  environnement = "m05"
  etiquettes    = [var.environnement]

  coeurs            = each.value.coeurs
  memoire_mo        = each.value.memoire_mo
  disque_systeme_go = 10

  reseau = { vnet = "vsandbox" } # DHCP de dns01 (10.10.99.100-199)
  dns    = var.dns

  cles_ssh = concat(var.cles_ssh_admin, [var.cle_ssh_env])

  demarrage_auto = false # VM d'environnement : ne redémarre pas avec pve01
}
