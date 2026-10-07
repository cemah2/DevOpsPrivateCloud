# refactorisation.tf — changements d'adresse et sorties de gestion de lab-m05 (M05-E17).

# 1. Les serveurs d'application passent dans le module : un moved par instance (un bloc
#    moved n'accepte ni for_each ni count : il désigne des adresses précises).
moved {
  from = proxmox_virtual_environment_vm.app["app01"]
  to   = module.app["app01"].proxmox_virtual_environment_vm.vm
}

moved {
  from = proxmox_virtual_environment_vm.app["app02"]
  to   = module.app["app02"].proxmox_virtual_environment_vm.vm
}

moved {
  from = proxmox_virtual_environment_vm.app["app03"]
  to   = module.app["app03"].proxmox_virtual_environment_vm.vm
}

# 2. La VM d'essai 2050 quitte lab-m05 SANS être détruite : Julien la garde pour la
#    recette (envs/recette-m05 l'importe). Le bloc resource "essai" est supprimé de main.tf.
#    Appliquer ce plan d'abord, PUIS l'import dans recette-m05 : jamais deux états pour un objet.
removed {
  from = proxmox_virtual_environment_vm.essai

  lifecycle {
    destroy = false
  }
}
