# outputs.tf — ce que l'environnement expose (M05-E06).

output "version_pve" {
  description = "Version de Proxmox VE lue par l'API."
  value       = data.proxmox_version.pve01.version
}

output "essai" {
  description = "VM d'essai : VMID, nom complet et première adresse IPv4 rapportée par l'agent QEMU."
  value = {
    vmid = proxmox_virtual_environment_vm.essai.vm_id
    fqdn = "${proxmox_virtual_environment_vm.essai.name}.${local.domaine}"
    # ipv4_addresses : une liste par interface (lo d'abord) ; vide tant que l'agent n'a pas répondu.
    ipv4 = try([for a in flatten(proxmox_virtual_environment_vm.essai.ipv4_addresses) : a if !startswith(a, "127.")][0], null)
  }
}
