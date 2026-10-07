# outputs.tf — ce que l'état socle publie (M05-E10, M05-E16, M05-E17).

output "s3_01" {
  description = "Identité de s3-01 (lue par les vérifications et la documentation)."
  value = {
    vm_id = module.s3_01.vm_id
    nom   = module.s3_01.nom
    ipv4  = module.s3_01.ipv4
    fqdn  = module.s3_01.fqdn
  }
}

output "socle_importe" {
  description = "VMs du socle importées (nom → VMID)."
  value       = { for nom, vm in proxmox_virtual_environment_vm.socle : nom => vm.vm_id }
}
