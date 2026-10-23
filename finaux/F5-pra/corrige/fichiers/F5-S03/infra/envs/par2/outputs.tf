output "hotes" {
  description = "VMs de PAR2 : VMID, adresse, nom complet."
  value       = { for n, m in module.vm : n => { vmid = m.vmid, ipv4 = m.ipv4, fqdn = m.fqdn } }
}
