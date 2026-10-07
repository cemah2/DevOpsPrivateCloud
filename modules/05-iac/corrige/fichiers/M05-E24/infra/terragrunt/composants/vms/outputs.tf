# outputs.tf — composant « vms » (M05-E24).

output "vms" {
  description = "VMs de l'environnement : nom => VMID et adresse IPv4 (lue par l'agent QEMU)."
  value = {
    for k, m in module.vm : m.nom => {
      vm_id = m.vm_id
      ipv4  = m.ipv4
    }
  }
}
