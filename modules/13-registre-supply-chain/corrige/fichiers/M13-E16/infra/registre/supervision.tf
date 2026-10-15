# registre/supervision.tf — robot de la sonde ms-verif-registre (M13-E16, CHG-1416).
# Système, LECTURE de ce que la sonde lit : santé (sans identité), systeminfo, volumes, réplications,
# ramasse-miettes. Aucun accès aux dépôts. Secret : Vault critique → /usr/local/etc/ms-verif-registre.secret
# sur adm01 (admin:admin 600), par outils/publier-secrets-registre.sh (M13-E03).
resource "random_password" "robot_supervision" {
  length      = 32
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

resource "harbor_robot_account" "supervision" {
  name        = "supervision"
  level       = "system"
  description = "Sonde ms-verif-registre (adm01), LECTURE SEULE — M13-E16"
  duration    = var.duree_robots_jours
  secret      = random_password.robot_supervision.result

  permissions {
    kind      = "system"
    namespace = "/"
    dynamic "access" {
      for_each = [
        { resource = "system-volumes", action = "read" },
        { resource = "replication-policy", action = "list" },
        { resource = "replication-policy", action = "read" },
        { resource = "replication", action = "list" },
        { resource = "replication", action = "read" },
        { resource = "garbage-collection", action = "list" },
        { resource = "garbage-collection", action = "read" },
      ]
      content {
        resource = access.value.resource
        action   = access.value.action
      }
    }
  }
}

output "robot_supervision" {
  description = "Robot de la sonde (nom complet et secret, à publier sur adm01)."
  value = {
    nom    = harbor_robot_account.supervision.full_name
    secret = random_password.robot_supervision.result
  }
  sensitive = true
}
