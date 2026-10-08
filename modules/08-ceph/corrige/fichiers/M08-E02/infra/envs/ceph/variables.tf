variable "noeud" {
  description = "Nœud Proxmox (<NOEUD>)."
  type        = string
}

variable "cle_ssh_admin" {
  description = "Clé publique SSH de adm01 (contenu de ~/.ssh/id_ed25519.pub)."
  type        = string
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

variable "noeuds_ceph" {
  description = <<-EOT
    Nœuds Ceph : nom => numéro (1 à 4). Adresses publique 10.10.30.5N, cluster 10.10.31.5N,
    VMID 208N (PLAN.md §4.9). ceph04 n'est ajouté qu'en M08-E18 et retiré en fin de module.
  EOT
  type        = map(number)
  default = {
    ceph01 = 1
    ceph02 = 2
    ceph03 = 3
  }
  validation {
    condition     = alltrue([for n, i in var.noeuds_ceph : i >= 1 && i <= 4 && n == format("ceph%02d", i)])
    error_message = "noeuds_ceph : ceph01 = 1 … ceph04 = 4 (nom et numéro cohérents)."
  }
}
