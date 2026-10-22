# tofu/flux.tf — flux d'authentification du navigateur du royaume medisphere (M24-E21, SEC-2521).
#
# « navigateur-medisphere » reprend la structure du flux « browser » de Keycloak, écrite exécution
# par exécution (pas de copy_from : une copie créerait des sous-flux que le code ne décrit pas) :
#
#   navigateur-medisphere
#   ├── Cookie (auth-cookie)                                        ALTERNATIVE  session SSO existante
#   └── navigateur-medisphere-formulaires                           ALTERNATIVE
#       ├── Formulaire identifiant + mot de passe                   REQUIRED     liaison LDAP (ipa01)
#       ├── navigateur-medisphere-otp-obligatoire                   CONDITIONAL
#       │   ├── Condition - user role (second-facteur-obligatoire)  REQUIRED
#       │   └── OTP Form (auth-otp-form)                             REQUIRED     enrôlement imposé
#       └── navigateur-medisphere-webauthn-volontaire               CONDITIONAL
#           ├── Condition - user role (idem, inversée)              REQUIRED
#           ├── Condition - user configured                         REQUIRED
#           └── WebAuthn Authenticator                               REQUIRED     si la personne en a une
#
# Qui est concerné : les membres des groupes plateforme-admins et securite (annuaire), par le rôle de
# royaume « second-facteur-obligatoire » attribué À CES GROUPES (pas aux personnes). Keycloak n'a pas
# de condition « membre du groupe » : la condition porte sur un rôle, que les groupes transmettent.
# Les comptes de service (client_credentials) ne passent jamais par ce flux ; kc-secours et
# <MOI>-admin vivent dans le royaume master, qui garde ses propres flux.
#
# Retour arrière (SSO bloqué pour tous) : browser_flow = "browser" ci-dessous, MR, apply ; en urgence,
# console d'administration (royaume master, <MOI>-admin ou kc-secours) → medisphere → Authentication →
# « browser » → Bind flow → Browser flow. Le pipeline (svc-tofu-keycloak, client_credentials) n'est
# pas touché par un flux de navigateur cassé.

# --- Qui doit présenter un second facteur ----------------------------------------------------------
resource "keycloak_role" "second_facteur_obligatoire" {
  realm_id    = keycloak_realm.medisphere.id
  name        = "second-facteur-obligatoire"
  description = "Porté par les groupes dont les membres doivent présenter un OTP (navigateur-medisphere)"
}

# Groupes importés de l'annuaire par la fédération (mappeur groupes-ipa, READ_ONLY) : leurs MEMBRES
# viennent de l'annuaire, leurs RÔLES sont stockés dans Keycloak. Nom du royaume en littéral : une
# source de données qui dépend du royaume serait relue à l'apply seulement (voir comptes-service.tf).
data "keycloak_group" "second_facteur" {
  for_each = toset(["plateforme-admins", "securite"])

  realm_id = "medisphere"
  name     = each.key
}

resource "keycloak_group_roles" "second_facteur" {
  for_each = data.keycloak_group.second_facteur

  realm_id = keycloak_realm.medisphere.id
  group_id = each.value.id
  role_ids = [keycloak_role.second_facteur_obligatoire.id]
  # Ne gère que CE rôle : un autre rôle donné plus tard au groupe (par un autre fichier) n'est pas retiré.
  exhaustive = false
}

# --- Le flux --------------------------------------------------------------------------------------
resource "keycloak_authentication_flow" "navigateur" {
  realm_id    = keycloak_realm.medisphere.id
  alias       = "navigateur-medisphere"
  description = "Navigateur MédiSphère : mot de passe (annuaire), OTP obligatoire pour plateforme-admins et securite, WebAuthn volontaire"
  provider_id = "basic-flow"
}

resource "keycloak_authentication_execution" "cookie" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_flow.navigateur.alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_subflow" "formulaires" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_flow.navigateur.alias
  alias             = "navigateur-medisphere-formulaires"
  description       = "Identifiant et mot de passe, puis second facteur selon la personne"
  provider_id       = "basic-flow"
  requirement       = "ALTERNATIVE"
  priority          = 20
}

resource "keycloak_authentication_execution" "mot_de_passe" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.formulaires.alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 10
}

# Second facteur OBLIGATOIRE : membres des groupes porteurs du rôle.
resource "keycloak_authentication_subflow" "otp_obligatoire" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.formulaires.alias
  alias             = "navigateur-medisphere-otp-obligatoire"
  description       = "OTP exigé (et enrôlement imposé à la première connexion) si la personne porte le rôle second-facteur-obligatoire"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 20
}

resource "keycloak_authentication_execution" "condition_role" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.otp_obligatoire.alias
  authenticator     = "conditional-user-role"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "condition_role" {
  realm_id     = keycloak_realm.medisphere.id
  execution_id = keycloak_authentication_execution.condition_role.id
  alias        = "porte-second-facteur-obligatoire"
  config = {
    condUserRole = keycloak_role.second_facteur_obligatoire.name
    negate       = "false"
  }
}

resource "keycloak_authentication_execution" "otp" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.otp_obligatoire.alias
  authenticator     = "auth-otp-form"
  requirement       = "REQUIRED"
  priority          = 20
}

# Second facteur VOLONTAIRE : les autres personnes qui ont enregistré une clé de sécurité (WebAuthn).
resource "keycloak_authentication_subflow" "webauthn_volontaire" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.formulaires.alias
  alias             = "navigateur-medisphere-webauthn-volontaire"
  description       = "Clé de sécurité demandée aux personnes (hors second facteur obligatoire) qui en ont enregistré une"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 30
}

resource "keycloak_authentication_execution" "condition_role_inverse" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.webauthn_volontaire.alias
  authenticator     = "conditional-user-role"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "condition_role_inverse" {
  realm_id     = keycloak_realm.medisphere.id
  execution_id = keycloak_authentication_execution.condition_role_inverse.id
  alias        = "ne-porte-pas-second-facteur-obligatoire"
  config = {
    condUserRole = keycloak_role.second_facteur_obligatoire.name
    negate       = "true"
  }
}

resource "keycloak_authentication_execution" "condition_webauthn_configure" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.webauthn_volontaire.alias
  authenticator     = "conditional-user-configured"
  requirement       = "REQUIRED"
  priority          = 20
}

resource "keycloak_authentication_execution" "webauthn" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.webauthn_volontaire.alias
  authenticator     = "webauthn-authenticator"
  requirement       = "REQUIRED"
  priority          = 30
}

# --- Le flux devient celui du navigateur pour TOUT le royaume ---------------------------------------
# Les exécutions d'abord (depends_on) : lier un flux à moitié construit fermerait la porte à tous.
resource "keycloak_authentication_bindings" "medisphere" {
  realm_id     = keycloak_realm.medisphere.id
  browser_flow = keycloak_authentication_flow.navigateur.alias

  depends_on = [
    keycloak_authentication_execution.cookie,
    keycloak_authentication_execution.mot_de_passe,
    keycloak_authentication_execution_config.condition_role,
    keycloak_authentication_execution.otp,
    keycloak_authentication_execution_config.condition_role_inverse,
    keycloak_authentication_execution.condition_webauthn_configure,
    keycloak_authentication_execution.webauthn,
  ]
}

# --- Actions requises : enrôlement OTP et WebAuthn (activées, jamais imposées par défaut à tous) ------
resource "keycloak_required_action" "configurer_otp" {
  realm_id       = keycloak_realm.medisphere.id
  alias          = "CONFIGURE_TOTP"
  name           = "Configure OTP"
  enabled        = true
  default_action = false
}

resource "keycloak_required_action" "enregistrer_webauthn" {
  realm_id       = keycloak_realm.medisphere.id
  alias          = "webauthn-register"
  name           = "Webauthn Register"
  enabled        = true
  default_action = false
}
