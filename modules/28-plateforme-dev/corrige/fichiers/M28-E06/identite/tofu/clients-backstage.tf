# plateforme/identite — tofu/clients-backstage.tf (M28-E06, PLAT-2906). Règles communes : clients-gitlab.tf.
# Client OIDC confidentiel du portail. Le backend de Backstage échange le code contre les jetons
# (secret) ; une seule URI de redirection, exacte : <baseUrl>/api/auth/<fournisseur>/handler/frame.
# Secret IMPOSÉ depuis le coffre (M24-E29) : var.secrets_clients["backstage"], même valeur que
# kv/plateforme/portail (clé oidc_client_secret) lue par l'ExternalSecret du portail.
resource "keycloak_openid_client" "backstage" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "backstage"
  name        = "Portail développeurs (Backstage)"
  description = "Connexion au portail (M28-E06) ; utilisateurs résolus par preferred_username"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  root_url                        = "https://portail.apps.par1.medisphere.internal"
  valid_redirect_uris             = ["https://portail.apps.par1.medisphere.internal/api/auth/oidc/handler/frame"]
  valid_post_logout_redirect_uris = ["https://portail.apps.par1.medisphere.internal"]
  web_origins                     = []

  full_scope_allowed = false
  consent_required   = false

  client_secret_wo         = var.secrets_clients["backstage"]
  client_secret_wo_version = var.versions_secrets_clients["backstage"]
}

# Portées par défaut des clients OIDC du royaume (profile, email, groupes : local.portees_clients_oidc,
# M24) : preferred_username est dans la portée « profile ».
resource "keycloak_openid_client_default_scopes" "backstage" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.backstage.id
  default_scopes = local.portees_clients_oidc
}

# À AJOUTER dans tofu/secrets-clients.tf, variable versions_secrets_clients, default :
#   backstage = 1 # M28-E06 : secret imposé à la création
