# vm-noeud — sorties (M08-E02 ; « macs » en M10-E02 ; « dhcp » et « adresses_agent » en M12-E02).
# Mêmes noms que vm-debian v2 quand le sens est le même.

output "vmid" {
  description = "VMID Proxmox."
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "nom" {
  description = "Nom de la VM."
  value       = proxmox_virtual_environment_vm.vm.name
}

output "ipv4" {
  description = "Adresse IPv4 imposée de la première carte (sans masque), celle du nom DNS ; null si la première carte est en DHCP."
  value       = local.premiere_statique ? var.cartes[0].ipv4 : null
}

output "dhcp" {
  description = "La première carte prend son adresse par DHCP (le nom DNS est alors publié par le DDNS de Kea, pas par enregistrement-dns)."
  value       = var.cartes[0].ipv4 == "dhcp"
}

output "adresses" {
  description = "Adresses imposées (avec masque), dans l'ordre des cartes ; les cartes DHCP et sans adresse n'y figurent pas."
  value       = [for a in netbox_ip_address.carte : a.ip_address]
}

output "adresses_agent" {
  description = "Adresses IPv4 vues par l'agent QEMU (interfaces de l'invité, lo compris) : utile pour une carte DHCP. Vide tant que l'agent n'a pas répondu."
  value       = proxmox_virtual_environment_vm.vm.ipv4_addresses
}

output "macs" {
  description = "Adresses MAC des cartes, dans l'ordre net0, net1… (imposées ou tirées par Proxmox)."
  value       = [for c in proxmox_virtual_environment_vm.vm.network_device : c.mac_address]
}

output "fqdn" {
  description = "Nom complet (dns_name de l'adresse principale dans NetBox, ou nom publié par le DDNS de Kea)."
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
