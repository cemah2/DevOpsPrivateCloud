# Sortie ajoutée à envs/lab-m05/outputs.tf (M05-E23) : les noms d'hôtes Ansible des VMs de
# l'environnement, pour limiter le playbook à ce que l'apply vient de créer ou de changer.
output "hotes_ansible" {
  description = "Noms des VMs de l'environnement (noms d'hôtes de l'inventaire dynamique Ansible)."
  value = sort(concat(
    [for m in module.app : m.nom],
    [proxmox_virtual_environment_vm.jetable.name],
  ))
}
