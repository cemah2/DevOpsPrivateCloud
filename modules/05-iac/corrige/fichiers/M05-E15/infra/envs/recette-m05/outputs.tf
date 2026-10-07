# outputs.tf — ce que l'équipe de Julien doit savoir de sa recette (M05-E15).
output "vms" {
  description = "VMs de la recette : nom => VMID et adresse (DHCP, remontée par l'agent QEMU)."
  value       = { for k, m in module.vm : m.nom => { vm_id = m.vm_id, ipv4 = m.ipv4 } }
}
