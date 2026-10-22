# acces-proxmox/variables.tf — M24-E15.

variable "proxmox_oidc_secret" {
  description = "Secret du client OIDC « proxmox » de Keycloak (Vault critique secrets/identite.yml de plateforme/ansible)."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "proxmox_oidc_secret_version" {
  description = "Version du secret poussé dans le royaume : à incrémenter à chaque rotation (RB-244)."
  type        = number
  default     = 1
}
