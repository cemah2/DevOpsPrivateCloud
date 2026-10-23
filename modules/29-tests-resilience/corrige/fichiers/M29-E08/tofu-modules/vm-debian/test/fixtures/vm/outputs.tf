# Sorties lues par le test (M29-E08).
output "vmid" {
  value = module.vm.vmid
}

output "nom" {
  value = module.vm.nom
}

output "ipv4" {
  value = module.vm.ipv4
}

output "fqdn" {
  value = module.vm.fqdn
}

output "netbox_vm_id" {
  value = module.vm.netbox_vm_id
}
