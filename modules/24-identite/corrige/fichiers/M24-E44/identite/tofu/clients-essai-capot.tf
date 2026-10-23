# tofu/clients-essai-capot.tf — client d'ESSAI TEMPORAIRE « essai-capot » (M24-E44, PLAT-2544).
#
# Sert à observer les jetons et une déconnexion par canal arrière. Ajouté par une MR, SUPPRIMÉ par une
# seconde MR à la fin de l'exercice (le contrôle le vérifie). Aucun service ne l'utilise.
#
# Le secret est généré par Keycloak ; l'apprenant le copie dans ~/m24/e44/essai-capot.secret (600)
# depuis la console (onglet Credentials) ou l'API, sans l'afficher ; il n'est pas rangé dans le Vault
# (durée de vie de quelques heures). Il est aussi dans l'état OpenTofu (chiffré).
resource "keycloak_openid_client" "essai_capot" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "essai-capot"
  name        = "Essai sous le capot (temporaire)"
  description = "Client d'essai de M24-E44 : signatures, sessions, déconnexion par canal arrière. À supprimer."
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  pkce_code_challenge_method   = "S256"

  # Comme M24-E07 : rien n'écoute sur le poste, le code se lit dans la barre d'adresse.
  valid_redirect_uris = ["http://localhost:8765/rappel"]
  web_origins         = []

  full_scope_allowed = false
  consent_required   = false

  # Déconnexion par canal ARRIÈRE : Keycloak POSTe un logout_token à cette URL, depuis idp01 (d'où
  # 127.0.0.1 : le récepteur temporaire de l'exercice). Le canal AVANT est désactivé (sinon Keycloak
  # ignorerait l'URL du canal arrière pour ce client).
  frontchannel_logout_enabled                = false
  backchannel_logout_url                     = "http://127.0.0.1:18081/deconnexion"
  backchannel_logout_session_required        = true
  backchannel_logout_revoke_offline_sessions = false
}

resource "keycloak_openid_client_default_scopes" "essai_capot" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.essai_capot.id
  default_scopes = local.portees_clients_oidc
}

# Le jeton d'accès doit porter « essai-capot » dans aud pour l'introspection (même raison qu'en E07).
resource "keycloak_openid_audience_protocol_mapper" "essai_capot" {
  realm_id                 = keycloak_realm.medisphere.id
  client_id                = keycloak_openid_client.essai_capot.id
  name                     = "audience-essai-capot"
  included_client_audience = keycloak_openid_client.essai_capot.client_id
  add_to_id_token          = false
  add_to_access_token      = true
}
