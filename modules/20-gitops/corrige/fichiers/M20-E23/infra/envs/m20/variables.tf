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
    VMs du module 20 à créer : flux (flux01, E23), lyo (lyo-k3s01, E26). Retirer un groupe DÉTRUIT
    sa VM : c'est ainsi qu'on libère la mémoire (2 Go chacune ; jamais les deux à la fois si la
    mémoire manque, PLAN §4.11). Fin de module : groupes = [].
  EOT
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for g in var.groupes : contains(["flux", "lyo"], g)])
    error_message = "groupes : parmi flux, lyo."
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
