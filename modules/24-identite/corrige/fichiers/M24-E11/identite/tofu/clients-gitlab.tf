# tofu/clients-gitlab.tf — client OIDC de GitLab (M24-E11, PLAT-2511).
#
# Règles communes à TOUS les clients du royaume (M24, palier 2) :
#   - flux standard (code d'autorisation) SEUL : ni implicite, ni Direct Access Grants (mot de passe
#     envoyé au client), ni compte de service ;
#   - URI de redirection EXACTES, aucun joker (« * ») : un joker transforme le client en redirection
#     ouverte (vol de code, M24-E22, M24-E45) ;
#   - full_scope_allowed = false : aucun rôle du royaume n'est recopié dans les jetons ; les services
#     décident à partir de la revendication « groups » (portée par défaut « groupes », M24-E06) ;
#   - PKCE S256 exigé dès que le service le sait : il lie la requête d'autorisation et l'échange du code.
# Le SECRET n'est pas écrit ici : Keycloak le génère à la création ; outils/ranger-secret-client.sh
# le range dans le Vault « critique » de plateforme/ansible (secrets/identite.yml). L'état d'OpenTofu
# le contient (lu par le fournisseur) : c'est pourquoi il est chiffré (M24-E08).

resource "keycloak_openid_client" "gitlab" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "gitlab"
  name        = "GitLab (git01)"
  description = "GitLab CE : OmniAuth openid_connect (M24-E11)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  root_url            = "https://git01.par1.medisphere.internal"
  valid_redirect_uris = ["https://git01.par1.medisphere.internal/users/auth/openid_connect/callback"]
  # GitLab n'appelle pas de point de déconnexion de Keycloak : pas de retour après déconnexion.
  valid_post_logout_redirect_uris = []
  # Aucun appel du navigateur vers Keycloak depuis les pages de GitLab (pas de CORS à ouvrir).
  web_origins = []

  # omniauth_openid_connect envoie un défi PKCE quand « pkce: true » (gitlab.rb).
  pkce_code_challenge_method = "S256"
  full_scope_allowed         = false
  consent_required           = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client_default_scopes" "gitlab" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.gitlab.id
  default_scopes = local.portees_clients_oidc
}
