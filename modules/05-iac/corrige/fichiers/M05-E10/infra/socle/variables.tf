# variables.tf — entrées de l'état socle (M05-E10).
# Valeurs non secrètes dans terraform.tfvars (versionné) ; aucun secret en variable.

variable "noeud" {
  description = "Nom du nœud Proxmox qui héberge le socle (<NOEUD>, voir pvesh get /nodes)."
  type        = string
}

variable "pool" {
  description = "Pool Proxmox de toutes les VMs du workbook (PLAN.md §4.3 bis)."
  type        = string
  default     = "lab"
}

variable "datastore_systeme" {
  description = "Stockage des disques système et des lecteurs cloud-init (PLAN.md §3.2)."
  type        = string
  default     = "local-nvme"
}

variable "datastore_donnees" {
  description = "Stockage des gros disques de données peu sollicités (PLAN.md §3.2)."
  type        = string
  default     = "hdd-bulk"
}

variable "cles_ssh_admin" {
  description = "Clés SSH PUBLIQUES injectées par cloud-init pour le compte admin."
  type        = list(string)

  validation {
    condition     = length(var.cles_ssh_admin) > 0 && alltrue([for c in var.cles_ssh_admin : can(regex("^ssh-(ed25519|rsa) ", c))])
    error_message = "Au moins une clé publique SSH (ssh-ed25519 … ou ssh-rsa …) est requise."
  }
}

variable "dns" {
  description = "Résolveur et domaine de recherche du lab (dnsmasq de dns01 jusqu'au module 06)."
  type = object({
    serveurs = list(string)
    domaine  = string
  })
  default = {
    serveurs = ["10.10.20.10"]
    domaine  = "par1.medisphere.internal"
  }
}
