output "vms" {
  description = "VMID, adresse d'administration et cartes de chaque VM de la maquette."
  value = {
    for nom, vm in proxmox_virtual_environment_vm.maquette : nom => {
      vmid   = vm.vm_id
      admin  = local.vms[nom].admin
      cartes = [for i, c in local.vms[nom].cartes : "eth${i + 1} ${c.vnet} ${c.ipv4}"]
    }
  }
}

output "noms" {
  description = "Noms DNS créés par cet état."
  value       = concat([for m in module.dns : m.fqdn], [module.dns_web_demo.fqdn])
}
