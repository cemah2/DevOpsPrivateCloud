variable "region" {
  description = "Région Keystone (Kolla : RegionOne)."
  type        = string
  default     = "RegionOne"
}

variable "domaine" {
  description = "Domaine Keystone des projets d'équipe."
  type        = string
  default     = "medisphere"
}

variable "reseau_externe" {
  description = "Réseau externe (provider) auquel les routeurs se relient."
  type        = string
  default     = "ext-net"
}

variable "dns" {
  description = "Résolveurs du lab donnés aux instances (PLAN §4.5)."
  type        = list(string)
  default     = ["10.10.20.10", "10.10.20.16"]
}

variable "sources_admin" {
  description = "Réseaux autorisés en SSH par le groupe <projet>-admin."
  type        = list(string)
  default     = ["10.10.10.0/24"]
}

variable "projets" {
  description = "Projets d'équipe : sous-réseau et quotas (docs/cloud/capacite.md)."
  type = map(object({
    cidr = string
    quotas = object({
      instances           = number
      cores               = number
      ram                 = number
      volumes             = number
      gigabytes           = number
      snapshots           = number
      backups             = number
      backup_gigabytes    = number
      floatingip          = number
      network             = number
      subnet              = number
      router              = number
      security_group      = number
      security_group_rule = number
      port                = number
    })
  }))

  validation {
    condition     = alltrue([for p in values(var.projets) : can(cidrhost(p.cidr, 1))])
    error_message = "Chaque projet doit avoir un cidr IPv4 valide."
  }
}
