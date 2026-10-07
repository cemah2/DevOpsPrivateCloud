variable "nom" {
  description = "Nom complet de l'hôte, SANS point final (ex. m06-ipam01.par1.medisphere.internal)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", var.nom))
    error_message = "Nom complet en minuscules attendu, sans point final."
  }
}

variable "ipv4" {
  description = "Adresse IPv4 sans masque."
  type        = string
  validation {
    condition     = can(cidrhost("${var.ipv4}/32", 0))
    error_message = "Adresse IPv4 sans masque attendue."
  }
}

variable "zone" {
  description = "Zone directe, avec point final."
  type        = string
  default     = "par1.medisphere.internal."
}

variable "ttl" {
  description = "TTL des deux enregistrements (s)."
  type        = number
  default     = 300
}

variable "ptr" {
  description = "Créer aussi le PTR (faux pour un second nom sur une même adresse)."
  type        = bool
  default     = true
}
