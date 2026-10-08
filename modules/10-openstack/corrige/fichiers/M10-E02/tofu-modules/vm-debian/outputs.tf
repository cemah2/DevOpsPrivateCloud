# vm-debian v2.2 — sorties (M06-E13). Mêmes noms qu'en v1, plus celles de NetBox ; « macs » en v2.2.

output "vmid" {
  description = "VMID Proxmox."
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "nom" {
  description = "Nom de la VM."
  value       = proxmox_virtual_environment_vm.vm.name
}

output "ipv4" {
  description = "Adresse IPv4 (sans masque), telle qu'allouée dans NetBox."
  value       = local.ipv4
}

output "ipv4_cidr" {
  description = "Adresse IPv4 avec son masque."
  value       = local.ipv4_cidr
}

output "fqdn" {
  description = "Nom complet (dns_name de l'adresse dans NetBox)."
  value       = local.fqdn
}

output "netbox_vm_id" {
  description = "Identifiant de la VM dans NetBox."
  value       = netbox_virtual_machine.vm.id
}

output "macs" {
  description = "Adresses MAC des cartes, dans l'ordre net0, net1… (telles que Proxmox les a retenues)."
  value       = [for c in proxmox_virtual_environment_vm.vm.network_device : lower(c.mac_address)]
}
