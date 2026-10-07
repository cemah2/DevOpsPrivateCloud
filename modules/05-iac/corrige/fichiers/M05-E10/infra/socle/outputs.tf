# outputs.tf — ce que l'état socle publie (M05-E10).

output "s3_01" {
  description = "Identité de s3-01 (lue par les vérifications et la documentation)."
  value = {
    vm_id = proxmox_virtual_environment_vm.s3_01.vm_id
    nom   = proxmox_virtual_environment_vm.s3_01.name
    ipv4  = "10.10.20.14"
    image = "${local.image_debian13.name} (${local.image_debian13.vm_id})"
  }
}
