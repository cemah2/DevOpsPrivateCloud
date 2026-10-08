# variables.tf — environnement hv-invites (M09-E18). Rien de secret.

variable "template_vmid" {
  description = "VMID du template imbriqué tpl-nested-debian13 (PLAN §4.9 : 199)."
  type        = number
  default     = 199
}

variable "noeud_template" {
  description = "Nœud qui porte la configuration du template (son disque est sur ceph-vm, partagé)."
  type        = string
  default     = "hv01"
}

variable "pool" {
  description = "Pool Proxmox des VMs de recette : le jeton n'a de droits que là."
  type        = string
  default     = "recette"

  validation {
    condition     = var.pool == "recette"
    error_message = "Cet environnement ne crée des VMs que dans le pool « recette » (SEC-1027)."
  }
}

variable "stockage" {
  description = "Stockage des disques et du lecteur cloud-init (Ceph hyperconvergé, M09-E10)."
  type        = string
  default     = "ceph-vm"
}

variable "vnet" {
  description = "VNet SDN des invités (M09-E16) : VLAN 99, DHCP Kea."
  type        = string
  default     = "vinv99"
}

variable "cles_ssh_admin" {
  description = "Clés publiques SSH de l'utilisateur admin des VMs."
  type        = list(string)
}

variable "vms" {
  description = "VMs de recette : clé = nom court, VMID dans 130-139 (PLAN §4.9 et M09-E18)."
  type = map(object({
    vmid       = number
    noeud      = string
    coeurs     = optional(number, 1)
    memoire_mo = optional(number, 1024)
    disque_go  = optional(number, 8)
  }))

  validation {
    condition     = alltrue([for v in values(var.vms) : v.vmid >= 130 && v.vmid <= 139])
    error_message = "Les VMs de recette ont un VMID entre 130 et 139."
  }
  validation {
    condition     = alltrue([for v in values(var.vms) : contains(["hv01", "hv02", "hv03"], v.noeud)])
    error_message = "Nœud inconnu : hv01, hv02 ou hv03."
  }
}
