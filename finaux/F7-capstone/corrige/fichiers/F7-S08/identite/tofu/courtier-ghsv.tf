# tofu/courtier-ghsv.tf — fédération d'identité du client GHSV dans le royaume medisphere
# (F7-S08, PLAT-3708 ; ESC-04 et réponse R-16 du GHSV ; procédure RB-372).
#
#   agent ──► OAuth2 Proxy (ghsv-agents) ──► Keycloak medisphere, client « ghsv-agents »
#                                             flux « navigateur-ghsv » : redirection D'OFFICE vers
#                                             le fournisseur ghsv-idp (pas de formulaire MédiSphère,
#                                             pas de cookie medisphere réutilisé)
#             ◄── jeton (groups: [ghsv-agents]) ◄── courtier ◄── IdP du GHSV (MFA chez lui)
#
# Ce que nous recevons du GHSV : sub, preferred_username, email (traçabilité, contact), et
# « groups ». Ce que nous en tirons : le seul groupe ghsv-agents, SI et SEULEMENT SI le GHSV dit
# « secretariat-medical » (convenu par écrit) ; réévalué à CHAQUE connexion (synchronisation FORCE).
# Ce que nous refusons : tout autre attribut, tout droit dérivé d'un autre groupe, toute liaison avec
# un compte existant de MédiSphère, la conservation des jetons du GHSV.
#
# Cloisonnement : tout utilisateur venu du courtier porte le rôle de royaume « client-externe »
# (mappeur codé en dur) ; le flux navigateur-medisphere de TOUS les autres clients le refuse
# (flux.tf, extrait F7-S08). Les agents n'ont aucun groupe de l'annuaire et ne sont pas dans le
# groupe « ghsv » (personnes de MédiSphère qui répondent du compte, lecture du locataire).

variable "emetteur_ghsv" {
  description = "Émetteur OIDC de l'IdP du GHSV (simulé : sortie « emetteur » de simulations/ghsv-idp)."
  type        = string
  default     = "https://sso.par1.medisphere.internal/realms/ghsv-idp"
}

# Secret du client « medisphere-courtier » que le GHSV nous a remis (simulé : lu dans OpenBao,
# kv/plateforme/keycloak/ghsv-idp-courtier, par outils/charger-acces.sh). Éphémère + écriture seule :
# jamais dans un plan ni dans l'état (M24-E29).
variable "secret_courtier_ghsv" {
  description = "Secret du client du courtier chez le GHSV (TF_VAR_secret_courtier_ghsv)."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "secret_courtier_ghsv_version" {
  description = "À incrémenter à chaque rotation du secret du courtier (RB-372 §4)."
  type        = number
  default     = 1
}

# --- Le fournisseur d'identité ------------------------------------------------------------------
resource "keycloak_oidc_identity_provider" "ghsv" {
  realm        = keycloak_realm.medisphere.id
  alias        = "ghsv-idp"
  display_name = "GHSV — annuaire du groupement"
  enabled      = true

  # Points d'accès de l'IdP. Navigateur → autorisation ; idp01 (côté serveur) → jeton, clés, userinfo :
  # flux idp01 → VIP lb 10.10.70.200:443 ajouté à la matrice (pare_feu.extrait-F7-S08.yml).
  authorization_url = "${var.emetteur_ghsv}/protocol/openid-connect/auth"
  token_url         = "${var.emetteur_ghsv}/protocol/openid-connect/token"
  user_info_url     = "${var.emetteur_ghsv}/protocol/openid-connect/userinfo"
  jwks_url          = "${var.emetteur_ghsv}/protocol/openid-connect/certs"
  logout_url        = "${var.emetteur_ghsv}/protocol/openid-connect/logout"
  issuer            = var.emetteur_ghsv

  client_id                = "medisphere-courtier"
  client_secret_wo         = var.secret_courtier_ghsv
  client_secret_wo_version = var.secret_courtier_ghsv_version

  default_scopes     = "openid profile email"
  validate_signature = true
  # Aucun jeton du GHSV conservé chez nous (minimisation ; rien à voler).
  store_token = false
  # Synchronisation des mappeurs à CHAQUE connexion : un agent retiré du secrétariat chez le GHSV perd
  # ghsv-agents à sa connexion suivante (au plus 15 min, voir client ghsv-agents).
  sync_mode = "FORCE"
  # L'adresse fournie par l'IdP fait foi pour ses agents (contrat) ; utile à OAuth2 Proxy.
  trust_email = true
  # Jamais proposé sur la page de connexion de MédiSphère : on n'y arrive que par le flux du client.
  hide_on_login_page = true
  link_only          = false
  # Premier passage : flux par défaut de Keycloak (création du compte fédéré) ; l'identifiant
  # préfixé « ghsv. » (mappeur plus bas) écarte toute collision avec un compte de l'annuaire, donc
  # toute proposition de liaison. Voir les pièges du corrigé.
  first_broker_login_flow_alias = "first broker login"
  # Après CHAQUE passage par ce fournisseur : refus si le client demandé n'est pas un client du GHSV
  # (flux plus bas). Indispensable : « caché sur la page de connexion » n'interdit pas d'appeler
  # directement /realms/medisphere/broker/ghsv-idp/login avec la session d'authentification d'un
  # client interne, et le retour du courtier ne rejoue PAS le flux du navigateur (donc pas le refus
  # de navigateur-medisphere).
  post_broker_login_flow_alias = keycloak_authentication_flow.apres_courtier_ghsv.alias

  extra_config = {
    clientAuthMethod = "client_secret_post"
    # PKCE vers l'IdP du client (clés de configuration du fournisseur OIDC de Keycloak).
    pkceEnabled = "true"
    pkceMethod  = "S256"
  }
}

# --- Mappeurs -------------------------------------------------------------------------------------
# Identifiant chez nous : « ghsv.<identifiant chez le GHSV> ».
resource "keycloak_user_template_importer_identity_provider_mapper" "identifiant" {
  realm                   = keycloak_realm.medisphere.id
  name                    = "ghsv-identifiant"
  identity_provider_alias = keycloak_oidc_identity_provider.ghsv.alias
  template                = "ghsv.$${CLAIM.preferred_username}"
  extra_config = {
    syncMode = "INHERIT"
  }
}

# Tout utilisateur venu du courtier est « client externe » : refusé par les clients internes.
resource "keycloak_role" "client_externe" {
  realm_id    = keycloak_realm.medisphere.id
  name        = "client-externe"
  description = "Utilisateur fédéré d'un client (courtier d'identité) : refusé par tous les clients internes (F7-S08)"
}

resource "keycloak_hardcoded_role_identity_provider_mapper" "client_externe" {
  realm                   = keycloak_realm.medisphere.id
  name                    = "ghsv-client-externe"
  identity_provider_alias = keycloak_oidc_identity_provider.ghsv.alias
  role                    = keycloak_role.client_externe.name
  extra_config = {
    syncMode = "INHERIT"
  }
}

# Groupe Keycloak des agents (local au royaume : PAS un groupe de l'annuaire).
resource "keycloak_group" "ghsv_agents" {
  realm_id = keycloak_realm.medisphere.id
  name     = "ghsv-agents"
}

# Appartenance à ghsv-agents dérivée du SEUL groupe convenu chez le GHSV (« Advanced Claim to Group »).
# FORCE (hérité du fournisseur) : retiré du groupe à la connexion où la revendication ne correspond plus.
resource "keycloak_custom_identity_provider_mapper" "agents" {
  realm                    = keycloak_realm.medisphere.id
  name                     = "ghsv-agents-secretariat"
  identity_provider_alias  = keycloak_oidc_identity_provider.ghsv.alias
  identity_provider_mapper = "oidc-advanced-group-idp-mapper"
  extra_config = {
    syncMode                 = "INHERIT"
    claims                   = jsonencode([{ key = "groups", value = "secretariat-medical" }])
    "are.claim.values.regex" = "false"
    group                    = "/${keycloak_group.ghsv_agents.name}"
  }
}

# --- Flux du navigateur des clients du GHSV : redirection d'office vers l'IdP ----------------------
# Pas d'exécution « Cookie » : une session medisphere ne suffit pas, chaque authentification repasse
# par l'IdP du GHSV (silencieuse tant que la session du GHSV est valide). C'est ce qui borne la
# désactivation d'un agent (ESC-04 : 15 min) avec la durée de session du client ghsv-agents.
resource "keycloak_authentication_flow" "navigateur_ghsv" {
  realm_id    = keycloak_realm.medisphere.id
  alias       = "navigateur-ghsv"
  description = "Clients du GHSV : redirection d'office vers le fournisseur ghsv-idp (F7-S08)"
  provider_id = "basic-flow"
}

resource "keycloak_authentication_execution" "redirection_ghsv" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_flow.navigateur_ghsv.alias
  authenticator     = "identity-provider-redirector"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "redirection_ghsv" {
  realm_id     = keycloak_realm.medisphere.id
  execution_id = keycloak_authentication_execution.redirection_ghsv.id
  alias        = "vers-ghsv-idp"
  config = {
    defaultProvider = keycloak_oidc_identity_provider.ghsv.alias
  }
}

# --- Après le courtier : seuls les clients du GHSV acceptent un utilisateur venu de ghsv-idp ------
# Portée « marqueur » sans mappeur, portée par défaut des SEULS clients du GHSV qui reçoivent des
# agents par le navigateur (ghsv-agents). « Condition - client scope » la cherche dans la session
# d'authentification (portées par défaut du client + portées demandées).
resource "keycloak_openid_client_scope" "client_ghsv" {
  realm_id               = keycloak_realm.medisphere.id
  name                   = "client-ghsv"
  description            = "Marqueur des clients du GHSV (flux apres-courtier-ghsv, F7-S08) ; aucun mappeur"
  include_in_token_scope = false
}

#   apres-courtier-ghsv
#   ├── apres-courtier-ghsv-hors-client                CONDITIONAL
#   │   ├── Condition - client scope (client-ghsv, negate)   REQUIRED
#   │   └── Deny access                                      REQUIRED
#   └── Allow access                                         REQUIRED   (un flux sans exécution
#                                                                        réussie échoue)
resource "keycloak_authentication_flow" "apres_courtier_ghsv" {
  realm_id    = keycloak_realm.medisphere.id
  alias       = "apres-courtier-ghsv"
  description = "Après le courtier ghsv-idp : refus hors des clients du GHSV (F7-S08)"
  provider_id = "basic-flow"
}

resource "keycloak_authentication_subflow" "hors_client_ghsv" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_flow.apres_courtier_ghsv.alias
  alias             = "apres-courtier-ghsv-hors-client"
  provider_id       = "basic-flow"
  requirement       = "CONDITIONAL"
  priority          = 10
}

resource "keycloak_authentication_execution" "hors_client_condition" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.hors_client_ghsv.alias
  authenticator     = "conditional-client-scope"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_execution_config" "hors_client_condition" {
  realm_id     = keycloak_realm.medisphere.id
  execution_id = keycloak_authentication_execution.hors_client_condition.id
  alias        = "client-sans-marqueur-ghsv"
  config = {
    client_scope = keycloak_openid_client_scope.client_ghsv.name
    negate       = "true"
  }
}

resource "keycloak_authentication_execution" "hors_client_refus" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_subflow.hors_client_ghsv.alias
  authenticator     = "deny-access-authenticator"
  requirement       = "REQUIRED"
  priority          = 20
}

resource "keycloak_authentication_execution" "apres_courtier_accepte" {
  realm_id          = keycloak_realm.medisphere.id
  parent_flow_alias = keycloak_authentication_flow.apres_courtier_ghsv.alias
  authenticator     = "allow-access-authenticator"
  requirement       = "REQUIRED"
  priority          = 20
}

# --- Clients du GHSV ------------------------------------------------------------------------------
# OAuth2 Proxy des agents (une instance par environnement, mêmes client et secret).
resource "keycloak_openid_client" "ghsv_agents" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "ghsv-agents"
  name        = "GHSV — accès des agents (OAuth2 Proxy)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris = [
    "https://ghsv-agents.apps.par1.medisphere.internal/oauth2/callback",
    "https://ghsv-agents-recette.apps.par1.medisphere.internal/oauth2/callback",
  ]
  valid_post_logout_redirect_uris = [
    "https://ghsv-agents.apps.par1.medisphere.internal/oauth2/sign_out",
    "https://ghsv-agents-recette.apps.par1.medisphere.internal/oauth2/sign_out",
  ]
  web_origins = []

  full_scope_allowed = false
  consent_required   = false
  # Session du client courte : au plus 15 min avant de repasser par l'IdP du GHSV (ESC-04).
  # Valeurs en SECONDES (attributs client.session.* passés tels quels à Keycloak ; « 15m » serait
  # refusé ou ignoré, contrairement aux durées de keycloak_realm).
  client_session_idle_timeout = "900"
  client_session_max_lifespan = "900"

  authentication_flow_binding_overrides {
    browser_id = keycloak_authentication_flow.navigateur_ghsv.id
  }

  depends_on = [keycloak_authentication_execution_config.redirection_ghsv]
}

# Portée « groupes » du M24 (revendication groups, noms courts) : par défaut pour ce client.
resource "keycloak_openid_client_default_scopes" "ghsv_agents" {
  realm_id  = keycloak_realm.medisphere.id
  client_id = keycloak_openid_client.ghsv_agents.id
  default_scopes = [
    "basic", "profile", "email", keycloak_openid_client_scope.groupes.name,
    keycloak_openid_client_scope.client_ghsv.name,
  ]
}

# --- Vérifications du workbook ----------------------------------------------------------------------
# wb-checks lit le fournisseur et ses mappeurs (check F7 8) : rôle de LECTURE view-identity-providers,
# à côté des rôles du M24 (comptes-service.tf).
resource "keycloak_openid_client_service_account_role" "wb_checks_fournisseurs" {
  realm_id                = keycloak_realm.medisphere.id
  service_account_user_id = keycloak_openid_client.wb_checks.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management.id
  role                    = "view-identity-providers"
}
