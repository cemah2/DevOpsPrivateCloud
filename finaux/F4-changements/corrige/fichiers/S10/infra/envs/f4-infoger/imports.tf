# imports.tf — rattachement des VMs EXISTANTES à l'état (OpenTofu ≥ 1.5 ; for_each dans import ≥ 1.7).
# Identifiant d'import de bpg/proxmox pour une VM : « <nœud>/<vmid> ».
# Ces blocs peuvent rester dans le code après l'import (sans effet ensuite) : ils documentent
# l'origine des ressources. On les retire avec la VM correspondante (F4-S14).
import {
  for_each = local.vms_infoger
  to       = proxmox_virtual_environment_vm.infoger[each.key]
  id       = "${var.noeud}/${each.value.vmid}"
}
