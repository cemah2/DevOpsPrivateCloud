# variables.tf — composant « vms » (M05-E24, étiquettes et disques par VM en M05-E34).
# noeud, pool, dns et cles_ssh_admin viennent de live/root.hcl (commun.hcl) ;
# environnement et vms de live/<env>/env.hcl ; cle_ssh_env de l'unité « acces ».

variable "environnement" {
  description = "Nom de l'environnement (dev-agenda, preprod-agenda…), posé en étiquette Proxmox."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.environnement))
    error_message = "environnement : minuscules, chiffres et tirets, 2 à 21 caractères."
  }
}

variable "vms" {
  description = <<-EOT
    VMs de l'environnement : nom court => VMID, ressources, étiquettes supplémentaires et disques
    de données. etiquettes et disques_donnees sont FACULTATIFS (ajoutés en M05-E34) : les
    environnements qui ne les donnent pas gardent exactement le même plan.
  EOT
  type = map(object({
    vm_id      = number
    coeurs     = optional(number, 1)
    memoire_mo = optional(number, 1024)
    etiquettes = optional(list(string), [])
    disques_donnees = optional(list(object({
      taille_go  = number
      datastore  = optional(string, "hdd-bulk")
      format     = optional(string, "qcow2")
      sauvegarde = optional(bool, true)
    })), [])
  }))

  validation {
    condition     = alltrue([for v in values(var.vms) : v.vm_id >= 2050 && v.vm_id <= 2059])
    error_message = "VMID hors de la plage du module 05 (2050-2059)."
  }

  validation {
    condition     = length(distinct([for v in values(var.vms) : v.vm_id])) == length(var.vms)
    error_message = "Deux VMs de l'environnement ont le même VMID."
  }
}

variable "noeud" {
  description = "Nom du nœud Proxmox."
  type        = string
}

variable "pool" {
  description = "Pool Proxmox."
  type        = string
  default     = "lab"
}

variable "dns" {
  description = "Résolveurs et domaine de recherche poussés par cloud-init."
  type = object({
    serveurs = list(string)
    domaine  = string
  })
}

variable "cles_ssh_admin" {
  description = "Clés publiques de l'équipe Plateforme (admin@adm01)."
  type        = list(string)
}

variable "cle_ssh_env" {
  description = "Clé publique propre à l'environnement (sortie de l'unité acces)."
  type        = string
}
