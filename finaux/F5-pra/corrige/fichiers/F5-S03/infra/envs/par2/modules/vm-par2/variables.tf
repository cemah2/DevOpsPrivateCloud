# vm-par2 — module LOCAL de envs/par2 (F5-S03). Pourquoi pas vm-noeud (plateforme/tofu-modules) :
# il refuse les VMID 1050-1059 et les VMs de moins de 1 Gio, écrit dans NetBox (PAR1) et se télécharge
# depuis git01 (PAR1). Même logique de matériel (image dorée, cloud-init), sans aucune dépendance à PAR1.

variable "nom" {
  description = "Nom court (nom Proxmox et nom d'hôte)."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.nom))
    error_message = "Nom en minuscules, chiffres et tirets."
  }
}

variable "vmid" {
  description = "VMID : socle de PAR2 1050-1059 (PLAN §4.6)."
  type        = number
  validation {
    condition     = var.vmid >= 1050 && var.vmid <= 1059
    error_message = "VMID hors du socle de PAR2 (1050-1059)."
  }
}

variable "noeud" {
  type = string
}

variable "stockage" {
  type = string
}

variable "pont" {
  type = string
}

variable "coeurs" {
  type    = number
  default = 1
  validation {
    condition     = var.coeurs >= 1 && var.coeurs <= 2
    error_message = "hp01 n'a que 2 cœurs : 1 ou 2 vCPU."
  }
}

variable "memoire_mo" {
  type = number
  validation {
    condition     = var.memoire_mo >= 512 && var.memoire_mo % 128 == 0
    error_message = "memoire_mo : au moins 512, multiple de 128."
  }
}

variable "disque_go" {
  type    = number
  default = 16
}

variable "disques_donnees" {
  description = "Disques de données (scsi1, scsi2…), qcow2 sur le même stockage."
  type        = list(object({ taille_go = number }))
  default     = []
}

variable "ipv4" {
  description = "Adresse dans PAR2 INFRA, sans masque."
  type        = string
  validation {
    condition     = can(regex("^10\\.20\\.20\\.[0-9]{1,3}$", var.ipv4))
    error_message = "Adresse hors de PAR2 INFRA (10.20.20.0/24)."
  }
}

variable "mac" {
  type = string
}

variable "etiquettes" {
  type = list(string)
}

variable "description" {
  type = string
}

variable "demarre" {
  description = "État d'alimentation À LA CRÉATION. Ensuite, il est piloté par les runbooks (RB-355 démarre bao-par2 en PRA) : OpenTofu l'ignore."
  type        = bool
  default     = true
}

variable "protection" {
  type    = bool
  default = false
}

variable "cle_ssh_admin" {
  type = string
}

variable "resolveurs" {
  description = "dns03 d'abord ; dns01 par wg0 en secours tant que PAR1 existe (et pendant l'amorçage, avant dns03)."
  type        = list(string)
  default     = ["10.20.20.11", "10.10.20.10"]
}
