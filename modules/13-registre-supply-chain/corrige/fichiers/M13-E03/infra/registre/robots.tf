# registre/robots.tf — comptes robots (M13-E03). Un usage = un robot, droits minimaux, 180 jours.
# Noms complets (sortie full_name) : robot$medisphere+ci, robot$bibliotheque+ci, robot$k8s-pull,
# robot$wb-checks. Le « $ » est un piège partout où les variables se développent (shell, GitLab).
# Permissions : ressource × action de Harbor (GET /api/v2.0/permissions, src/common/rbac/const.go).
#
# Rotation : à J-30 (registre des secrets), « tofu apply -replace=random_password.robot[\"<nom>\"] »
# change le secret ; puis outils/publier-secrets-registre.sh met à jour fichiers et variables CI.

resource "random_password" "robot" {
  for_each    = toset(["medisphere-ci", "bibliotheque-ci", "k8s-pull", "wb-checks"])
  length      = 32
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

locals {
  # Ce qu'un robot de CI doit pouvoir faire dans SON projet : pousser et tirer, lire les
  # artefacts et étiquettes (vérifier qu'une version n'existe pas déjà), créer une étiquette.
  # Les signatures et attestations Cosign sont des artefacts poussés : « repository:push » suffit.
  acces_ci = [
    { resource = "repository", action = "pull" },
    { resource = "repository", action = "push" },
    { resource = "artifact", action = "read" },
    { resource = "artifact", action = "list" },
    { resource = "tag", action = "list" },
    { resource = "tag", action = "create" },
    { resource = "accessory", action = "list" },
    { resource = "scan", action = "read" },
  ]
}

resource "harbor_robot_account" "ci" {
  for_each    = toset(["medisphere", "bibliotheque"])
  name        = "ci"
  level       = "project"
  description = "Publication depuis la CI GitLab (runner02) — M13-E03"
  duration    = var.duree_robots_jours
  secret      = random_password.robot["${each.key}-ci"].result

  permissions {
    kind      = "project"
    namespace = harbor_project.projet[each.key].name
    dynamic "access" {
      for_each = local.acces_ci
      content {
        resource = access.value.resource
        action   = access.value.action
      }
    }
  }
}

# Tirage seul, par les nœuds Kubernetes (containerd, M14). Les caches sont publics : inutiles ici.
resource "harbor_robot_account" "k8s_pull" {
  name        = "k8s-pull"
  level       = "system"
  description = "Tirage des images par les nœuds de k8s-par1 (M14) — M13-E03"
  duration    = var.duree_robots_jours
  secret      = random_password.robot["k8s-pull"].result

  dynamic "permissions" {
    for_each = toset(["medisphere", "plateforme", "bibliotheque", "charts"])
    content {
      kind      = "project"
      namespace = harbor_project.projet[permissions.value].name
      access {
        resource = "repository"
        action   = "pull"
      }
    }
  }
}

# Lecture seule pour les vérifications du workbook (lab/lib/check-lib.sh : harbor_api).
# Aucune action create/update/delete/push/stop. « repository:pull » : cosign verify et skopeo
# inspect des checks lisent les manifestes et les signatures.
resource "harbor_robot_account" "wb_checks" {
  name        = "wb-checks"
  level       = "system"
  description = "Vérifications du workbook, LECTURE SEULE — M13-E03"
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
        { resource = "garbage-collection", action = "list" },
        { resource = "garbage-collection", action = "read" },
        { resource = "scan-all", action = "read" },
        { resource = "scanner", action = "list" },
        { resource = "scanner", action = "read" },
        { resource = "system-volumes", action = "read" },
        { resource = "quota", action = "list" },
        { resource = "quota", action = "read" },
        { resource = "robot", action = "list" },
        { resource = "robot", action = "read" },
        { resource = "audit-log", action = "list" },
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
        { resource = "metadata", action = "list" },
        { resource = "metadata", action = "read" },
        { resource = "member", action = "list" },
        { resource = "member", action = "read" },
        { resource = "robot", action = "list" },
        { resource = "robot", action = "read" },
        { resource = "quota", action = "read" },
        { resource = "repository", action = "list" },
        { resource = "repository", action = "read" },
        { resource = "repository", action = "pull" },
        { resource = "artifact", action = "list" },
        { resource = "artifact", action = "read" },
        { resource = "tag", action = "list" },
        { resource = "accessory", action = "list" },
        { resource = "artifact-addition", action = "read" },
        { resource = "scan", action = "read" },
        { resource = "sbom", action = "read" },
        { resource = "immutable-tag", action = "list" },
        { resource = "tag-retention", action = "list" },
        { resource = "tag-retention", action = "read" },
        { resource = "log", action = "list" },
      ]
      content {
        resource = access.value.resource
        action   = access.value.action
      }
    }
  }
}
