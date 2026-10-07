# Fournisseur PowerDNS (M06-E14). Le serveur web de PowerDNS ne parle que HTTP (M06-E06) :
# la clé circule en clair de adm01/runner01 à dns01 ; écart suivi jusqu'à M06-E30.
# Clé : variable éphémère, valeur dans TF_VAR_pdns_api_key (powerdns-api.env sur adm01,
# variable protégée et masquée en CI). Même raison que pour NetBox (providers.tf).

provider "powerdns" {
  server_url = var.pdns_url
  api_key    = var.pdns_api_key
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
