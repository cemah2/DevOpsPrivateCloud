# outputs.tf — ce que l'état « hv » expose (M09-E03).

output "noeuds" {
  description = "Nœuds hv-par1 : nom => VMID, FQDN, adresse MGMT, URL de l'interface, MAC de nic0."
  value = {
    for n, v in var.noeuds : n => {
      vmid     = proxmox_virtual_environment_vm.noeud[n].vm_id
      fqdn     = trimsuffix(module.dns[n].fqdn, ".")
      mgmt     = v.mgmt
      url      = "https://${n}.${local.domaine}:8006"
      mac_nic0 = local.macs[n][0]
    }
  }
}

output "iso" {
  description = "ISO d'installation attendue pour chaque nœud (à produire AVANT l'apply)."
  value       = { for n in keys(var.noeuds) : n => "${var.stockage_iso}:iso/${var.prefixe_iso}-${n}.iso" }
}
