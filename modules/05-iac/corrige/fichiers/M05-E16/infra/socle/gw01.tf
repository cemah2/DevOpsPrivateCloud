# gw01.tf — le routeur reste HORS de la gestion d'OpenTofu (M05-E16, décision ADR-0051).
#
# gw01 a été construit à la main (M00-E10) : deux cartes (vmbr0 côté maison, vmbr1 en trunk,
# hors SDN), pas de cloud-init, installé depuis l'ISO. Un apply qui le modifierait (ou le
# remplacerait) couperait tout le lab, y compris le chemin vers l'API de pve01 utilisé par
# OpenTofu lui-même : on ne confie pas la branche sur laquelle on est assis.
# On le SURVEILLE en lecture : un bloc check lit gw01 à chaque plan et avertit (sans bloquer)
# s'il n'est plus là, plus démarré, ou plus étiqueté comme routeur du socle.
check "gw01_present" {
  # Source de données « vms » (liste filtrée) : la source « vm » au singulier est dépréciée
  # dans le provider 0.115 au profit de proxmox_vm, encore expérimentale (PLAN : on l'évite).
  data "proxmox_virtual_environment_vms" "gw01" {
    node_name = var.noeud

    filter {
      name   = "name"
      values = ["gw01"]
    }
  }

  assert {
    condition     = length(data.proxmox_virtual_environment_vms.gw01.vms) == 1 && one(data.proxmox_virtual_environment_vms.gw01.vms[*].vm_id) == 1000
    error_message = "gw01 (VMID 1000) introuvable dans le pool lab."
  }

  assert {
    condition     = alltrue([for vm in data.proxmox_virtual_environment_vms.gw01.vms : vm.status == "running"])
    error_message = "gw01 n'est pas démarré : tout le lab est coupé d'Internet et des autres VLANs."
  }

  assert {
    condition     = alltrue([for vm in data.proxmox_virtual_environment_vms.gw01.vms : contains(vm.tags, "role-routeur") && contains(vm.tags, "socle")])
    error_message = "gw01 n'a plus les étiquettes socle et role-routeur : l'inventaire Ansible ne le trouvera plus."
  }
}
