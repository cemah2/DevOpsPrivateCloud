# essai-importe.tf — la VM 2050 (m05-essai), sortie de lab-m05 par un bloc removed,
# entre dans l'état de recette-m05 (M05-E17). Même méthode que pour le socle (M05-E16) :
# le module doit décrire la VM telle qu'elle est, le plan attendu est « 1 to import, 0 to add,
# 0 to destroy » (et au plus des modifications sur place comprises et acceptées).
import {
  to = module.essai.proxmox_virtual_environment_vm.vm
  id = "${var.noeud}/2050"
}

module "essai" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.1.0"

  nom           = "m05-essai"
  vm_id         = 2050
  noeud         = var.noeud
  environnement = "m05"

  coeurs            = 2
  memoire_mo        = 2048
  disque_systeme_go = 10
  reseau            = { vnet = "vsandbox" }
  cles_ssh          = var.cles_ssh_admin

  demarrage_auto = false
  arret_force    = true
}
