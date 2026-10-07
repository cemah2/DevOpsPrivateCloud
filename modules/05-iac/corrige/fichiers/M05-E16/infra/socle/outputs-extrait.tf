# Sortie ajoutée à outputs.tf (M05-E16) : inventaire du socle tel que l'état le connaît.
output "socle_importe" {
  description = "VMs du socle importées (nom → VMID)."
  value       = { for nom, vm in proxmox_virtual_environment_vm.socle : nom => vm.vm_id }
}
