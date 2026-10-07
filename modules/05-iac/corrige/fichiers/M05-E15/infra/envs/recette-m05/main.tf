# main.tf — recette de MédiAgenda : une VM API, une VM base de données (DEV-625, M05-E15).
module "vm" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.1.0"
  for_each = var.vms

  nom           = "m05-rec-${each.key}"
  vm_id         = each.value.vm_id
  noeud         = var.noeud
  environnement = "m05"
  etiquettes    = ["recette"]

  coeurs     = each.value.coeurs
  memoire_mo = each.value.memoire_mo
  disques_donnees = each.value.donnees_go == null ? [] : [
    { taille_go = each.value.donnees_go, datastore = "local-nvme", format = "raw", ssd = true },
  ]

  reseau   = { vnet = "vsandbox" }
  cles_ssh = var.cles_ssh_admin

  demarrage_auto = false
  arret_force    = true
}
