# tofu/royaume.tf — le royaume medisphere (créé à la main en M24-E05, importé en M24-E08).
#
# Seuls les attributs que l'on DÉCIDE sont écrits ; le reste garde la valeur de Keycloak (le
# fournisseur ne réécrit pas un attribut absent du code). Les durées de session et de jeton
# sont les valeurs par défaut de Keycloak (5 min, 30 min, 10 h) jusqu'au durcissement (M24-E27).
resource "keycloak_realm" "medisphere" {
  realm        = "medisphere"
  display_name = "MédiSphère"
  enabled      = true

  registration_allowed     = false
  login_with_email_allowed = true
  ssl_required             = "external"

  # Valeur déjà en place (création à la main) : l'écrire évite un « - RS256 -> null » au plan.
  default_signature_algorithm = "RS256"
}
