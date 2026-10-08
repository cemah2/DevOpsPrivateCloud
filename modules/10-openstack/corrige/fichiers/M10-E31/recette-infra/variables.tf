variable "cle_publique_ssh" {
  description = "Clé publique SSH de l'équipe MédiAgenda (variable CI TF_VAR_cle_publique_ssh, non secrète)."
  type        = string
}

variable "acces_admin" {
  description = "IP flottante d'administration temporaire sur agenda-recette-app01 (MR dédiée, puis retour à false)."
  type        = bool
  default     = false
}
