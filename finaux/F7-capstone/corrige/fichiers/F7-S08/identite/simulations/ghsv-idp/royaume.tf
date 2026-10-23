# simulations/ghsv-idp/royaume.tf — le royaume du GHSV simulé, avec MFA OBLIGATOIRE (ESC-04, R-16).
#
# Flux du navigateur « navigateur-ghsv-idp » : session existante OU (mot de passe PUIS OTP), l'OTP
# étant REQUIRED pour tout le monde : un utilisateur sans OTP configuré se voit imposer l'enrôlement
# (action requise CONFIGURE_TOTP) avant de terminer sa première connexion. Pas de condition : chez le
# GHSV, il n'y a pas d'exception à la MFA.
resource "keycloak_realm" "ghsv_idp" {
  realm        = "ghsv-idp"
  display_name = "GHSV — annuaire des agents (simulation)"
  enabled      = true

  registration_allowed     = false
  login_with_email_allowed = false
  ssl_required             = "external"

  # Sessions du GHSV : une journée de travail. Désactiver un agent ici ferme la porte à sa
  # prochaine authentification (le courtier y revient au plus tard toutes les 15 min, F7-S08).
  sso_session_idle_timeout = "2h"
  sso_session_max_lifespan = "10h"

  otp_policy {
    type      = "totp"
    algorithm = "HmacSHA1"
    digits    = 6
    period    = 30
  }

  # Protection contre la force brute (ESC-05 côté GHSV, bonne pratique).
  security_defenses {
    brute_force_detection {
      permanent_lockout            = false
      max_login_failures           = 10
      wait_increment_seconds       = 60
      max_failure_wait_seconds     = 900
      failure_reset_time_seconds   = 43200
      quick_login_check_milli_seconds = 1000
      minimum_quick_login_wait_seconds = 60
    }
  }
}

resource "keycloak_authentication_flow" "navigateur" {
  realm_id    = keycloak_realm.ghsv_idp.id
  alias       = "navigateur-ghsv-idp"
  description = "Session existante, ou mot de passe puis OTP obligatoire pour tous (simulation de l'IdP du GHSV)"
  provider_id = "basic-flow"
}

resource "keycloak_authentication_execution" "cookie" {
  realm_id          = keycloak_realm.ghsv_idp.id
  parent_flow_alias = keycloak_authentication_flow.navigateur.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_subflow" "formulaires" {
  realm_id          = keycloak_realm.ghsv_idp.id
  parent_flow_alias = keycloak_authentication_flow.navigateur.alias
  alias             = "navigateur-ghsv-idp-formulaires"
  provider_id       = "basic-flow"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

resource "keycloak_authentication_execution" "mot_de_passe" {
  realm_id          = keycloak_realm.ghsv_idp.id
  parent_flow_alias = keycloak_authentication_subflow.formulaires.alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution" "otp" {
  realm_id          = keycloak_realm.ghsv_idp.id
  parent_flow_alias = keycloak_authentication_subflow.formulaires.alias
  authenticator     = "auth-otp-form"
  requirement       = "REQUIRED"
  priority          = 20
}

resource "keycloak_authentication_bindings" "ghsv_idp" {
  realm_id     = keycloak_realm.ghsv_idp.id
  browser_flow = keycloak_authentication_flow.navigateur.alias

  depends_on = [
    keycloak_authentication_execution.cookie,
    keycloak_authentication_execution.mot_de_passe,
    keycloak_authentication_execution.otp,
  ]
}

# Enrôlement OTP imposé à tout nouvel utilisateur (action requise par défaut).
resource "keycloak_required_action" "configurer_otp" {
  realm_id       = keycloak_realm.ghsv_idp.id
  alias          = "CONFIGURE_TOTP"
  name           = "Configure OTP"
  enabled        = true
  default_action = true
}

# Événements de connexion conservés (diagnostic des refus, F7-S11) — côté « client », simulé.
resource "keycloak_realm_events" "ghsv_idp" {
  realm_id                     = keycloak_realm.ghsv_idp.id
  events_enabled               = true
  events_expiration            = 604800
  admin_events_enabled         = true
  admin_events_details_enabled = false
  events_listeners             = ["jboss-logging"]
}
