# outputs.tf — ce que le module expose (M05-E13).

output "vm_id" {
  description = "VMID de la VM."
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "nom" {
  description = "Nom de la VM (nom d'hôte court)."
  value       = proxmox_virtual_environment_vm.vm.name
}

output "fqdn" {
  description = "Nom complet attendu dans le DNS du lab."
  value       = "${proxmox_virtual_environment_vm.vm.name}.${var.dns.domaine}"
}

output "ipv4" {
  description = "Adresse IPv4 : celle de la configuration si statique, sinon la première adresse non locale remontée par l'agent QEMU (null tant que l'agent ne répond pas)."
  value = (
    local.statique
    ? split("/", var.reseau.ipv4)[0]
    : try([for a in flatten(proxmox_virtual_environment_vm.vm.ipv4_addresses) : a if !startswith(a, "127.")][0], null)
  )
}

output "etiquettes" {
  description = "Étiquettes Proxmox posées (elles alimentent l'inventaire dynamique Ansible)."
  value       = local.etiquettes
}

output "image_source" {
  description = "VMID du template cloné à la création (ou à la dernière lecture du template courant)."
  value       = local.image_vm_id
}
