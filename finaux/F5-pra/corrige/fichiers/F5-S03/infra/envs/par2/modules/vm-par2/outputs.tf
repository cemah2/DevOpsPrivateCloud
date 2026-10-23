output "vmid" {
  value = proxmox_virtual_environment_vm.vm.vm_id
}

output "ipv4" {
  value = var.ipv4
}

output "fqdn" {
  value = "${var.nom}.par2.medisphere.internal"
}
