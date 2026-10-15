# registre-reg02/main.tf — M13-E13. Le strict nécessaire pour recevoir et vérifier la réplication.

variable "duree_robots_jours" {
  description = "Durée de vie des robots de reg02 (jours) : reg02 vit le temps du palier 3."
  type        = number
  default     = 60
}

resource "harbor_project" "medisphere" {
  name                   = "medisphere"
  public                 = false
  vulnerability_scanning = true
}

# Même règle d'immuabilité que sur reg01 (M13-E10) : une version répliquée ne se réécrit pas.
resource "harbor_immutable_tag_rule" "versions" {
  project_id    = harbor_project.medisphere.id
  repo_matching = "**"
  tag_matching  = "v*"
}

resource "random_password" "robot" {
  for_each    = toset(["replication", "wb-checks"])
  length      = 32
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

# Réplication en poussée : lister, pousser et tirer (vérifier ce qui existe déjà) dans medisphere.
# Les accessoires (signatures, attestations) sont des artefacts poussés : repository:push suffit.
resource "harbor_robot_account" "replication" {
  name        = "replication"
  level       = "system"
  description = "Réplication depuis reg01 (medisphere-vers-reg02) — M13-E13"
  duration    = var.duree_robots_jours
  secret      = random_password.robot["replication"].result

  permissions {
    kind      = "project"
    namespace = harbor_project.medisphere.name
    access {
      resource = "repository"
      action   = "pull"
    }
    access {
      resource = "repository"
      action   = "push"
    }
    access {
      resource = "repository"
      action   = "list"
    }
    access {
      resource = "artifact"
      action   = "read"
    }
    access {
      resource = "tag"
      action   = "create"
    }
  }
}

# Lecture seule pour les checks du workbook (~/.config/workbook/harbor-reg02-checks.env).
resource "harbor_robot_account" "wb_checks" {
  name        = "wb-checks"
  level       = "system"
  description = "Vérifications du workbook sur reg02, LECTURE SEULE — M13-E13"
  duration    = var.duree_robots_jours
  secret      = random_password.robot["wb-checks"].result

  permissions {
    kind      = "system"
    namespace = "/"
    dynamic "access" {
      for_each = [
        { resource = "project", action = "list" },
        { resource = "registry", action = "list" },
        { resource = "registry", action = "read" },
        { resource = "replication-policy", action = "list" },
        { resource = "replication-policy", action = "read" },
        { resource = "replication", action = "list" },
        { resource = "replication", action = "read" },
      ]
      content {
        resource = access.value.resource
        action   = access.value.action
      }
    }
  }

  permissions {
    kind      = "project"
    namespace = "*"
    dynamic "access" {
      for_each = [
        { resource = "project", action = "read" },
        { resource = "metadata", action = "read" },
        { resource = "repository", action = "list" },
        { resource = "repository", action = "read" },
        { resource = "repository", action = "pull" },
        { resource = "artifact", action = "list" },
        { resource = "artifact", action = "read" },
        { resource = "tag", action = "list" },
        { resource = "accessory", action = "list" },
      ]
      content {
        resource = access.value.resource
        action   = access.value.action
      }
    }
  }
}

output "robot_replication" {
  description = "Nom et secret du robot de réplication (à reporter en Vault, puis en TF_VAR_reg02_robot_secret)."
  value = {
    nom    = harbor_robot_account.replication.full_name
    secret = random_password.robot["replication"].result
  }
  sensitive = true
}

output "robot_wb_checks" {
  description = "Robot des checks de reg02 (fichier ~/.config/workbook/harbor-reg02-checks.env)."
  value = {
    nom    = harbor_robot_account.wb_checks.full_name
    secret = random_password.robot["wb-checks"].result
  }
  sensitive = true
}
