variable "noeud" {
  description = "Nœud Proxmox (<NOEUD>)."
  type        = string
}

variable "cle_ssh_admin" {
  description = "Clé publique SSH de adm01 (contenu de ~/.ssh/id_ed25519.pub)."
  type        = string
}

variable "groupes" {
  description = <<-EOT
    VMs du module 24 à créer : idp02 (second nœud Keycloak, E24), resto (idp-resto : restauration
    d'essai, E25 et E33). Retirer un groupe DÉTRUIT sa VM. Une seule à la fois (mémoire, PLAN §4.12).
    Fin de module : groupes = [].
  EOT
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for g in var.groupes : contains(["idp02", "resto"], g)])
    error_message = "groupes : parmi idp02, resto."
  }
  validation {
    condition     = length(var.groupes) <= 1
    error_message = "Une seule VM temporaire à la fois (PLAN §4.12) : détruis l'une avant de créer l'autre."
  }
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

variable "pdns_url" {
  description = "API de PowerDNS Authoritative (dns01)."
  type        = string
  default     = "http://dns01.par1.medisphere.internal:8081"
}

variable "pdns_api_key" {
  description = "Clé d'API PowerDNS (TF_VAR_pdns_api_key)."
  type        = string
  sensitive   = true
  ephemeral   = true
}
