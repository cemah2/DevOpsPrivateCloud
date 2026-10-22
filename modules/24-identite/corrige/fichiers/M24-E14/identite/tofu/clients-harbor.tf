# tofu/clients-harbor.tf — client OIDC de Harbor (M24-E14, PLAT-2514). Règles communes : clients-gitlab.tf.
resource "keycloak_openid_client" "harbor" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "harbor"
  name        = "Harbor (reg01)"
  description = "auth_mode oidc_auth de Harbor (M24-E14) ; groupes OIDC membres des projets"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  root_url            = "https://registry.par1.medisphere.internal"
  valid_redirect_uris = ["https://registry.par1.medisphere.internal/c/oidc/callback"]
  # Retour après la déconnexion de Keycloak si oidc_logout est activé un jour (Harbor ≥ 2.13).
  valid_post_logout_redirect_uris = ["https://registry.par1.medisphere.internal/"]
  web_origins                     = []

  # Harbor 2.15 envoie un défi PKCE S256 à chaque connexion (src/core/controllers/oidc.go, paquet pkce
  # de Pinniped) : on l'EXIGE ici, un code intercepté ne sert à rien sans le verifier.
  pkce_code_challenge_method = "S256"
  full_scope_allowed         = false
  consent_required           = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client_default_scopes" "harbor" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.harbor.id
  default_scopes = local.portees_clients_oidc
}
