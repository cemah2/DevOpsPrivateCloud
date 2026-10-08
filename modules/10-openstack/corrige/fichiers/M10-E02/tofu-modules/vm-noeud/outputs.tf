# vm-noeud — sorties (M08-E02 ; « macs » depuis M10-E02). Mêmes noms que vm-debian v2 quand le sens est le même.

output "vmid" {
  description = "VMID Proxmox."
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "nom" {
  description = "Nom de la VM."
  value       = proxmox_virtual_environment_vm.vm.name
}

output "ipv4" {
  description = "Adresse IPv4 de la première carte (sans masque) : celle du nom DNS."
  value       = var.cartes[0].ipv4
}

output "adresses" {
  description = "Adresses des cartes adressées, avec masque, dans l'ordre ens18, ens19…"
  value       = [for a in netbox_ip_address.carte : a.ip_address]
}

output "macs" {
  description = "Adresses MAC des cartes, dans l'ordre net0, net1… (telles que Proxmox les a retenues)."
  value       = [for c in proxmox_virtual_environment_vm.vm.network_device : lower(c.mac_address)]
}

output "fqdn" {
  description = "Nom complet (dns_name de l'adresse principale dans NetBox)."
  value       = local.fqdn
}

output "type_cpu" {
  description = "Type de CPU retenu (famille ou valeur imposée)."
  value       = local.type_cpu
}

output "image_source" {
  description = "VMID du template cloné (à la création, ou à la dernière lecture du template courant)."
  value       = data.proxmox_virtual_environment_vms.image.vms[0].vm_id
}

output "netbox_vm_id" {
  description = "Identifiant de la VM dans NetBox."
  value       = netbox_virtual_machine.vm.id
}
