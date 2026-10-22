# tofu/oidc.tf — rôle OIDC et groupes externes (M25-E06, importés en E08).

# Un seul rôle pour toutes les personnes : les droits ne viennent pas du rôle (politique « default »
# seulement) mais des GROUPES de la revendication « groups », par les groupes externes ci-dessous.
resource "vault_jwt_auth_backend_role" "personne" {
  backend   = vault_jwt_auth_backend.oidc.path
  role_name = "personne"
  role_type = "oidc"

  user_claim     = "preferred_username"
  groups_claim   = "groups"
  claim_mappings = { email = "email" }
  oidc_scopes    = ["profile", "email"]
  # L'ID token de Keycloak est destiné au client « openbao » : rien d'autre n'est accepté.
  bound_audiences = ["openbao"]

  # Redirections EXACTES, identiques à celles du client Keycloak (plateforme/identite).
  allowed_redirect_uris = [
    "https://openbao.par1.medisphere.internal:8200/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]

  token_policies = ["default"]
  token_ttl      = 3600  # 1 h : une session de travail
  token_max_ttl  = 28800 # 8 h : une journée, puis nouvelle connexion (et nouvel OTP)
}

# Groupes EXTERNES : leurs membres sont donnés par la méthode d'authentification à chaque connexion
# (alias = nom du groupe dans la revendication « groups »). On ne les remplit jamais à la main.
resource "vault_identity_group" "keycloak" {
  for_each = var.groupes_keycloak

  name     = each.key
  type     = "external"
  policies = each.value
  metadata = { source = "keycloak-medisphere" }
}

resource "vault_identity_group_alias" "keycloak" {
  for_each = var.groupes_keycloak

  name           = each.key
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.keycloak[each.key].id
}
