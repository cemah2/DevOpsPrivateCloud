variable "noeud" {
  description = "Nœud Proxmox (<NOEUD>)."
  type        = string
}

variable "stockage" {
  description = "Stockage des disques des VMs jetables du final."
  type        = string
  default     = "local-nvme"
}

variable "avec_essai" {
  description = "Créer la machine d'essai de l'usine (F1-S06). À remettre à false à la fin de l'essai."
  type        = bool
  default     = false
}

variable "netbox_cluster" {
  description = "Cluster de virtualisation NetBox (modélisation M06-E05)."
  type        = string
  default     = "pve01"
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
