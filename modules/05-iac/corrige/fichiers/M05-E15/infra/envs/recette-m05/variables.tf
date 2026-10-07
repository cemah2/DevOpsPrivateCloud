# variables.tf — entrées de l'environnement recette-m05 (M05-E15).

variable "noeud" {
  description = "Nom du nœud Proxmox (<NOEUD>)."
  type        = string
}

variable "cles_ssh_admin" {
  description = "Clés SSH PUBLIQUES du compte admin (cloud-init)."
  type        = list(string)
}

variable "vms" {
  description = "VMs de la recette de MédiAgenda : clé courte => VMID et ressources."
  type = map(object({
    vm_id      = number
    coeurs     = optional(number, 2)
    memoire_mo = optional(number, 2048)
    donnees_go = optional(number) # disque de données facultatif (local-nvme)
  }))

  validation {
    condition     = alltrue([for v in values(var.vms) : v.vm_id >= 2050 && v.vm_id <= 2059])
    error_message = "VMs d'environnement du module 05 : VMID entre 2050 et 2059."
  }
}
