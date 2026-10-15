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
    Familles d'essais à créer (M18) : dev (m18-dev01, E02), k3s (k3s01, E03), rke2 (rke2-01..03,
    E04), talos (talos-01..03, E05, fichier talos.tf). Retirer un groupe DÉTRUIT ses VMs : c'est
    ainsi qu'on libère la mémoire. Un « qm shutdown » ne tient pas : vm-noeud et talos.tf déclarent
    started = true, le prochain tofu apply redémarre la VM.
  EOT
  type        = list(string)
  default     = ["dev"]
  validation {
    condition     = alltrue([for g in var.groupes : contains(["dev", "k3s", "rke2", "talos"], g)])
    error_message = "groupes : parmi dev, k3s, rke2, talos."
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
