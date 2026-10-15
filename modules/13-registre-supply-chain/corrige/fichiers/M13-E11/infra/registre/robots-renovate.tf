# registre/robots-renovate.tf — robot de lecture pour Renovate (M13-E11, PLAT-1411).
# Renovate consulte les étiquettes et empreintes des images de bibliotheque/ et plateforme/ (privés).
# Les caches publics n'en ont pas besoin, et Renovate interroge de toute façon leur amont
# (registryAliases du préréglage). Tirage seul : « repository:pull » couvre la liste des étiquettes.
resource "random_password" "robot_renovate" {
  length      = 32
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

resource "harbor_robot_account" "renovate" {
  name        = "renovate"
  level       = "system"
  description = "Renovate (plateforme/renovate) : lecture des images de base — M13-E11"
  duration    = var.duree_robots_jours
  secret      = random_password.robot_renovate.result

  dynamic "permissions" {
    for_each = toset(["bibliotheque", "plateforme"])
    content {
      kind      = "project"
      namespace = harbor_project.projet[permissions.value].name
      access {
        resource = "repository"
        action   = "pull"
      }
      access {
        resource = "repository"
        action   = "list"
      }
    }
  }
}

output "robot_renovate" {
  description = "Nom complet et secret du robot de Renovate (variables HARBOR_RENOVATE_*)."
  sensitive   = true
  value       = { utilisateur = harbor_robot_account.renovate.full_name, secret = harbor_robot_account.renovate.secret }
}
