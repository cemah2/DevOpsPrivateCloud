# tofu/clients-proxmox.tf — client OIDC de Proxmox VE (pve01) (M24-E15, SEC-2515). Règles : clients-gitlab.tf.
# La redirection est l'ORIGINE de l'interface, sans chemin ni barre finale : c'est ce que Proxmox VE
# envoie (window.location.origin). Proxmox VE (crate proxmox-openid) envoie un défi PKCE S256.
resource "keycloak_openid_client" "proxmox" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "proxmox"
  name        = "Proxmox VE (pve01)"
  description = "Royaume OpenID « medisphere » de pve01 (M24-E15) ; groupes → ACL"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  root_url            = "https://pve01.par1.medisphere.internal:8006"
  valid_redirect_uris = ["https://pve01.par1.medisphere.internal:8006"]
  web_origins         = []

  pkce_code_challenge_method = "S256"
  full_scope_allowed         = false
  consent_required           = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client_default_scopes" "proxmox" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.proxmox.id
  default_scopes = local.portees_clients_oidc
}
