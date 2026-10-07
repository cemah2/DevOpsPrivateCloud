# refactorisation.tf — historique des changements d'adresse de l'état socle (M05-E17).
#
# Un bloc moved se garde tant qu'un état PLUS ANCIEN peut encore être appliqué (copie de
# travail d'un collègue, branche ouverte, restauration d'une ancienne version de l'état,
# M05-E29). Le retirer trop tôt ferait réapparaître « destroy + create » chez ceux-là.
# Règle de l'équipe : on le retire au plus tôt une version après, par une MR dédiée.
moved {
  from = proxmox_virtual_environment_vm.s3_01
  to   = module.s3_01.proxmox_virtual_environment_vm.vm
}
