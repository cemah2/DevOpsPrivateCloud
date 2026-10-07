# variables.tf — composant « acces » (M05-E24).

variable "environnement" {
  description = "Nom de l'environnement (dev-agenda, dev-doc…), repris dans le commentaire de la clé."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.environnement))
    error_message = "environnement : minuscules, chiffres et tirets, 2 à 21 caractères."
  }
}
