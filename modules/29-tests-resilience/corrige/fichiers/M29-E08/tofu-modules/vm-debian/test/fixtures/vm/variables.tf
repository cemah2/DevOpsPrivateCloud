# Variables de la configuration de test (M29-E08). Toutes passées par Terratest (-var) sauf le
# jeton NetBox (TF_VAR_netbox_api_token, environnement) et les accès Proxmox (PROXMOX_VE_*).

variable "nom" {
  description = "Nom de la VM : tt-<suffixe aléatoire>."
  type        = string
  validation {
    condition     = can(regex("^tt-[a-z0-9]{6}$", var.nom))
    error_message = "Les VMs de Terratest s'appellent tt-<6 caractères> (PLAN §4.13)."
  }
}

variable "vmid" {
  description = "VMID choisi par le test dans la plage de Terratest."
  type        = number
  validation {
    condition     = var.vmid >= 2290 && var.vmid <= 2299
    error_message = "Terratest n'a droit qu'aux VMID 2290-2299 (PLAN §4.13)."
  }
}

variable "noeud" {
  description = "Nœud Proxmox (<NOEUD>)."
  type        = string
}

variable "cle_ssh_admin" {
  description = "Clé publique générée par le test (jamais une clé d'un humain)."
  type        = string
}

variable "lancement" {
  description = "Identifiant du lancement (pipeline ou poste), écrit dans la note de la VM."
  type        = string
  default     = "poste"
}

variable "netbox_url" {
  description = "URL racine de NetBox (sans /api)."
  type        = string
  default     = "https://nbx01.par1.medisphere.internal"
}

variable "netbox_api_token" {
  description = "Jeton v2 du compte d'automatisation NetBox (TF_VAR_netbox_api_token)."
  type        = string
  sensitive   = true
  ephemeral   = true
}
