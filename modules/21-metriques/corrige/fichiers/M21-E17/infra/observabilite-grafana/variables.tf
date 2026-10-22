# observabilite-grafana/variables.tf — M21-E17.

variable "grafana_url" {
  description = "URL de Grafana (Gateway gw-par1)."
  type        = string
  default     = "https://grafana.apps.par1.medisphere.internal"
}

variable "grafana_jeton" {
  description = "Jeton du compte de service « tofu » (Admin) : TF_VAR_grafana_jeton, jamais dans un fichier du dépôt."
  type        = string
  sensitive   = true
}

variable "equipes" {
  description = <<-EOT
    Équipes Grafana et leurs membres (adresses des comptes locaux, créés au palier 1 ; un membre
    absent de Grafana fait échouer l'apply). Les dossiers ont le même nom que l'équipe.
  EOT
  type = map(object({
    titre_dossier = string
    membres       = list(string)
    admins        = list(string)
  }))
  default = {
    plateforme = {
      titre_dossier = "Plateforme"
      membres       = ["karim.benali@medisphere.internal", "nadia.roussel@medisphere.internal"]
      admins        = ["claire.morel@medisphere.internal"]
    }
    mediagenda = {
      titre_dossier = "MédiAgenda"
      membres       = []
      admins        = ["julien.petit@medisphere.internal"]
    }
    medidoc = {
      titre_dossier = "MédiDoc"
      membres       = []
      admins        = []
    }
  }
  validation {
    condition     = alltrue([for k in keys(var.equipes) : can(regex("^[a-z0-9-]+$", k))])
    error_message = "Clé d'équipe en minuscules : elle sert aussi d'UID au dossier."
  }
}
