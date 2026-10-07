# imports.tf — faire entrer les VMs existantes du socle dans l'état, SANS les recréer (M05-E16).
#
# Un bloc import dit : « l'objet Proxmox <nœud>/<VMID> EST la ressource à cette adresse ».
# Au plan, OpenTofu lit la VM et compare ce qu'il lit au code : le but est « 4 to import,
# 0 to add, 0 to change, 0 to destroy ». L'import n'a lieu qu'à l'apply (relu en MR).
#
# Méthode suivie (corrigé) : d'abord des blocs import SANS ressource, et
#   tofu plan -generate-config-out=genere.tf
# pour obtenir la configuration lue ; puis on la réécrit proprement (socle-importe.tf) et
# on itère sur « tofu plan » jusqu'à ne plus voir aucun écart. genere.tf n'est jamais commité.
#
# Ces blocs peuvent rester dans le code après l'apply (sans effet une fois l'objet dans
# l'état) : ils documentent l'origine des ressources. Le corrigé les retire dans une MR
# suivante, pour qu'un futur import ne se mélange pas à ceux-ci.
import {
  for_each = local.socle_importe
  to       = proxmox_virtual_environment_vm.socle[each.key]
  id       = "${var.noeud}/${each.value.vm_id}"
}
