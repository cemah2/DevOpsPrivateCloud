# outputs.tf — environnement hv-invites (M09-E18).

output "vms" {
  description = "VMs de recette : nœud, VMID et adresses IPv4 vues par l'agent QEMU."
  value = {
    for nom, vm in proxmox_virtual_environment_vm.recette : nom => {
      noeud    = vm.node_name
      vmid     = vm.vm_id
      adresses = flatten(vm.ipv4_addresses)
    }
  }
}
