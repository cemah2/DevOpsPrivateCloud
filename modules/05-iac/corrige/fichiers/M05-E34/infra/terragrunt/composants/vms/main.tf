# main.tf — composant « vms » : les VMs d'un environnement de test (M05-E24, M05-E34).
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

  # Étiquettes : env-m05 (module), le nom de l'environnement, puis celles de la VM (M05-E34).
  # Sans étiquette propre à la VM, la liste est exactement celle de M05-E24 : aucun écart de plan.
  environnement = "m05"
  etiquettes    = concat([var.environnement], each.value.etiquettes)

  coeurs            = each.value.coeurs
  memoire_mo        = each.value.memoire_mo
  disque_systeme_go = 10
  disques_donnees   = each.value.disques_donnees # [] par défaut, comme avant M05-E34

  reseau = { vnet = "vsandbox" } # DHCP de dns01 (10.10.99.100-199)
  dns    = var.dns

  cles_ssh = concat(var.cles_ssh_admin, [var.cle_ssh_env])

  demarrage_auto = false # VM d'environnement : ne redémarre pas avec pve01
}
