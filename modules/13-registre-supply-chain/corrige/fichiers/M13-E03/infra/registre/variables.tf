# registre/variables.tf — M13-E03.

variable "moi" {
  description = "Ton compte personnel (<MOI>, le même que dans GitLab et NetBox)."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9._-]{1,30}$", var.moi))
    error_message = "Identifiant en minuscules (lettres, chiffres, point, tiret)."
  }
}

variable "moi_nom" {
  description = "Ton nom complet, affiché dans Harbor."
  type        = string
}

variable "duree_robots_jours" {
  description = "Durée de vie des robots (jours). Politique MédiSphère : 180 au plus, rotation planifiée."
  type        = number
  default     = 180
  validation {
    condition     = var.duree_robots_jours >= 1 && var.duree_robots_jours <= 180
    error_message = "Un robot vit 180 jours au plus (registre des secrets : date de rotation)."
  }
}
