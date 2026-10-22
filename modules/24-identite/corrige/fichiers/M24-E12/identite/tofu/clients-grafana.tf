# tofu/clients-grafana.tf — client OIDC de Grafana (M24-E12, DEV-2512). Règles communes : clients-gitlab.tf.
# Grafana échange le code de serveur à serveur (secret) ET envoie un défi PKCE (use_pkce = true).
resource "keycloak_openid_client" "grafana" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "grafana"
  name        = "Grafana (k8s-par1, supervision)"
  description = "generic_oauth de Grafana (M24-E12) ; rôles par role_attribute_path, organisations par org_mapping"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  root_url            = "https://grafana.apps.par1.medisphere.internal"
  valid_redirect_uris = ["https://grafana.apps.par1.medisphere.internal/login/generic_oauth"]
  # signout_redirect_url de Grafana : retour sur la page de connexion après la déconnexion de Keycloak.
  valid_post_logout_redirect_uris = ["https://grafana.apps.par1.medisphere.internal/login"]
  web_origins                     = []

  pkce_code_challenge_method = "S256"
  full_scope_allowed         = false
  consent_required           = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client_default_scopes" "grafana" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.grafana.id
  default_scopes = local.portees_clients_oidc
}
