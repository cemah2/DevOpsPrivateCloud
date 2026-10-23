# tofu/clients-dpi-ghsv.tf — accès du DPI du GHSV à l'API du contrat (F7-S09, DEV-3709).
#
#   DPI ──client credentials──► Keycloak medisphere (client ghsv-dpi) ──► jeton : aud ghsv-api,
#                                                                         scope « rdv:lecture rdv:ecriture »
#   DPI ──Bearer──► oauth2-proxy-dpi (vérifie signature, émetteur, audience) ──► API (vérifie la portée)
#
# Adresse du serveur d'autorisation à communiquer au GHSV à la notification (le contrat le prévoit) :
#   https://sso.par1.medisphere.internal/realms/medisphere/protocol/openid-connect/token (lab).
# Le secret de ghsv-dpi est remis au GHSV par un canal séparé (RB-372 §4), jamais par courriel.

# Portées du contrat (annexe A1) : des portées de client OIDC dont le NOM est la portée.
resource "keycloak_openid_client_scope" "rdv_lecture" {
  realm_id               = keycloak_realm.medisphere.id
  name                   = "rdv:lecture"
  description            = "Contrat GHSV v1 : lire les créneaux et les rendez-vous"
  include_in_token_scope = true
}

resource "keycloak_openid_client_scope" "rdv_ecriture" {
  realm_id               = keycloak_realm.medisphere.id
  name                   = "rdv:ecriture"
  description            = "Contrat GHSV v1 : créer, déplacer et annuler des rendez-vous"
  include_in_token_scope = true
}

# Le client de l'application cliente (le DPI) : compte de service seulement.
resource "keycloak_openid_client" "ghsv_dpi" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "ghsv-dpi"
  name        = "GHSV — DPI (API de rendez-vous v1)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = false
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = true

  full_scope_allowed = false
  # Jetons courts : 5 min (le DPI en redemande un, c'est son travail).
  access_token_lifespan = "300"
}

resource "keycloak_openid_client_default_scopes" "ghsv_dpi" {
  realm_id  = keycloak_realm.medisphere.id
  client_id = keycloak_openid_client.ghsv_dpi.id
  # Le DPI a les deux portées du contrat ; « basic » donne sub et preferred_username.
  default_scopes = [
    "basic",
    keycloak_openid_client_scope.rdv_lecture.name,
    keycloak_openid_client_scope.rdv_ecriture.name,
  ]
}

# Audience « ghsv-api » : celle qu'exige oauth2-proxy-dpi (extra_jwt_issuers).
resource "keycloak_openid_audience_protocol_mapper" "ghsv_dpi_audience" {
  realm_id                 = keycloak_realm.medisphere.id
  client_id                = keycloak_openid_client.ghsv_dpi.id
  name                     = "audience-ghsv-api"
  included_custom_audience = "ghsv-api"
  add_to_access_token      = true
  add_to_id_token          = false
}

# Le client propre au mandataire du DPI (OAuth2 Proxy exige un client OIDC). Aucune redirection de
# navigateur n'est attendue : le flux standard reste activé (exigence du mandataire au démarrage) mais
# limité à l'adresse de rappel de recette et de production.
resource "keycloak_openid_client" "ghsv_api" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "ghsv-api"
  name        = "GHSV — mandataire de l'API (OAuth2 Proxy)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  pkce_code_challenge_method   = "S256"
  valid_redirect_uris = [
    "https://ghsv.apps.par1.medisphere.internal/oauth2/callback",
    "https://ghsv-recette.apps.par1.medisphere.internal/oauth2/callback",
  ]
  web_origins        = []
  full_scope_allowed = false

  # Même flux que les agents : si quelqu'un arrive un jour par le navigateur, c'est par l'IdP du GHSV.
  authentication_flow_binding_overrides {
    browser_id = keycloak_authentication_flow.navigateur_ghsv.id
  }
}

# Démonstration et journée de jeu : un second client « ghsv-dpi-demo » (même réglages) sert à la
# charge k6 (F7-S11), pour ne jamais partager le secret remis au GHSV. Identique à ghsv_dpi, à créer
# par copie de ces trois ressources si tu outilles la charge du DPI.
