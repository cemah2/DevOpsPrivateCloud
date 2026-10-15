# registre/utilisateurs.tf — comptes humains de la base locale de Harbor (M13-E03).
# OIDC (Keycloak) remplacera la base locale au module 24 ; d'ici là, un compte nominatif par
# personne, mot de passe initial généré, transmis par un canal à part, changé à la 1re connexion.
locals {
  personnes = {
    (var.moi)      = { nom = var.moi_nom, courriel = "${var.moi}@medisphere.internal" }
    "karim.benali" = { nom = "Karim Benali", courriel = "karim.benali@medisphere.internal" }
    "julien.petit" = { nom = "Julien Petit", courriel = "julien.petit@medisphere.internal" }
    "lucas.martin" = { nom = "Lucas Martin", courriel = "lucas.martin@medisphere.internal" }
  }
}

# Politique de mot de passe de Harbor : 8 à 128 caractères, une majuscule, une minuscule, un chiffre.
resource "random_password" "personne" {
  for_each    = local.personnes
  length      = 24
  special     = false
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
}

resource "harbor_user" "personne" {
  for_each  = local.personnes
  username  = each.key
  full_name = each.value.nom
  email     = each.value.courriel
  password  = random_password.personne[each.key].result
  admin     = false # l'administration système passe par « admin » (bris de glace) et par ce code
  comment   = "Créé par OpenTofu (plateforme/infra, registre/), M13-E03"

  lifecycle {
    # Chacun change son mot de passe à la première connexion : OpenTofu ne le réécrit pas.
    ignore_changes = [password]
  }
}
