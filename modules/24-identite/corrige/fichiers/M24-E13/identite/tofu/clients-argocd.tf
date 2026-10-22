# tofu/clients-argocd.tf — clients OIDC d'Argo CD (M24-E13, SEC-2513). Règles communes : clients-gitlab.tf.
#
# Deux clients, deux usages :
#   argocd      CONFIDENTIEL : l'interface web ; argocd-server échange le code avec son secret.
#   argocd-cli  PUBLIC + PKCE : « argocd login --sso » sur un poste ; un binaire distribué ne peut pas
#               garder de secret, PKCE protège l'échange du code (la CLI envoie toujours un défi S256).
# Argo CD accepte les jetons dont « aud » vaut clientID OU cliClientID (argocd-cm, oidc.config).

resource "keycloak_openid_client" "argocd" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "argocd"
  name        = "Argo CD (interface)"
  description = "argocd-server, OIDC sans Dex (M24-E13)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  root_url                        = "https://argocd.apps.par1.medisphere.internal"
  valid_redirect_uris             = ["https://argocd.apps.par1.medisphere.internal/auth/callback"]
  valid_post_logout_redirect_uris = ["https://argocd.apps.par1.medisphere.internal/"]
  web_origins                     = []

  # L'interface d'Argo CD avec un client CONFIDENTIEL n'envoie pas de défi PKCE (enablePKCEAuthentication
  # ferait faire l'échange par le navigateur, sans secret : c'est le mode « client public »). On
  # n'exige donc pas PKCE ici ; le secret et la redirection exacte protègent l'échange.
  pkce_code_challenge_method = ""
  full_scope_allowed         = false
  consent_required           = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client" "argocd_cli" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "argocd-cli"
  name        = "Argo CD (CLI)"
  description = "argocd login --sso depuis adm01 (tunnel vers localhost:8085), PKCE (M24-E13)"
  access_type = "PUBLIC"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false

  # --sso-port par défaut de la CLI : 8085. Une seule redirection, exacte (pas « http://localhost:* »).
  valid_redirect_uris = ["http://localhost:8085/auth/callback"]
  web_origins         = []

  pkce_code_challenge_method = "S256"
  full_scope_allowed         = false
  consent_required           = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client_default_scopes" "argocd" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.argocd.id
  default_scopes = local.portees_clients_oidc
}

resource "keycloak_openid_client_default_scopes" "argocd_cli" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.argocd_cli.id
  default_scopes = local.portees_clients_oidc
}
