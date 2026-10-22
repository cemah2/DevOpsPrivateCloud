# tofu/clients-pbs.tf — client OIDC de Proxmox Backup Server (pbs01, site PAR2) (M24-E15, SEC-2515).
# Même mécanique que Proxmox VE (même crate proxmox-openid : PKCE S256) ; redirection = origine.
resource "keycloak_openid_client" "pbs" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "pbs"
  name        = "Proxmox Backup Server (pbs01)"
  description = "Royaume OpenID « medisphere » de pbs01 (M24-E15) ; droits par personne (pas de groupes dans PBS)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  root_url            = "https://pbs01.par2.medisphere.internal:8007"
  valid_redirect_uris = ["https://pbs01.par2.medisphere.internal:8007"]
  web_origins         = []

  pkce_code_challenge_method = "S256"
  full_scope_allowed         = false
  consent_required           = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client_default_scopes" "pbs" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.pbs.id
  default_scopes = local.portees_clients_oidc
}
