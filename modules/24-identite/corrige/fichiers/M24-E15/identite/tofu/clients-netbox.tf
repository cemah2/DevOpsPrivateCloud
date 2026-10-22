# tofu/clients-netbox.tf — client OIDC de NetBox (nbx01) (M24-E15, SEC-2515). Règles : clients-gitlab.tf.
# python-social-auth : chemin de retour /oauth/complete/<nom du backend>/ (« oidc »), barre finale comprise.
resource "keycloak_openid_client" "netbox" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "netbox"
  name        = "NetBox (nbx01)"
  description = "social_core OpenIdConnectAuth (M24-E15) ; groupes NetBox locaux"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  root_url            = "https://nbx01.par1.medisphere.internal"
  valid_redirect_uris = ["https://nbx01.par1.medisphere.internal/oauth/complete/oidc/"]
  web_origins         = []

  # SOCIAL_AUTH_OIDC_USE_PKCE = True dans configuration.py (social-auth-core 4.8 de NetBox 4.6).
  pkce_code_challenge_method = "S256"
  full_scope_allowed         = false
  consent_required           = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client_default_scopes" "netbox" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.netbox.id
  default_scopes = local.portees_clients_oidc
}
