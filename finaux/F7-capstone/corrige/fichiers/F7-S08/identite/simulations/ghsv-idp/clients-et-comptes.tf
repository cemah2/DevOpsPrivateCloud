# simulations/ghsv-idp/clients-et-comptes.tf — ce que le GHSV nous donnerait : un client OIDC pour
# notre courtier, la revendication des groupes, et (simulation seulement) des comptes de démonstration.

# --- Le client de notre courtier ----------------------------------------------------------------
# Confidentiel, flux « authorization code » + PKCE, une seule adresse de retour : le point d'entrée du
# courtier du royaume medisphere pour l'alias ghsv-idp.
resource "keycloak_openid_client" "courtier_medisphere" {
  realm_id    = keycloak_realm.ghsv_idp.id
  client_id   = "medisphere-courtier"
  name        = "MédiSphère — prise de rendez-vous (courtier d'identité)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  pkce_code_challenge_method   = "S256"

  valid_redirect_uris = [
    "https://sso.par1.medisphere.internal/realms/medisphere/broker/ghsv-idp/endpoint",
  ]
  valid_post_logout_redirect_uris = []
  web_origins                     = []

  full_scope_allowed = false
  consent_required   = false
}

# Revendication « groups » (noms courts) dans le jeton d'identité et l'userinfo : c'est le SEUL
# attribut dont le courtier tire des droits (groupe secretariat-medical → ghsv-agents chez nous).
resource "keycloak_openid_group_membership_protocol_mapper" "groupes" {
  realm_id  = keycloak_realm.ghsv_idp.id
  client_id = keycloak_openid_client.courtier_medisphere.id
  name      = "groups"

  claim_name          = "groups"
  full_path           = false
  add_to_id_token     = true
  add_to_access_token = false
  add_to_userinfo     = true
}

# --- Groupes et comptes de démonstration (SIMULATION) ---------------------------------------------
resource "keycloak_group" "secretariat" {
  realm_id = keycloak_realm.ghsv_idp.id
  name     = "secretariat-medical"
}

resource "keycloak_group" "encadrement" {
  realm_id = keycloak_realm.ghsv_idp.id
  name     = "encadrement"
}

# Mots de passe initiaux TEMPORAIRES (changement imposé à la première connexion), tirés d'une variable
# sensible : jamais dans le code. initial_password n'est pas un argument en écriture seule : la valeur
# est donc dans l'état — chiffré (fournisseurs.tf), et sans portée puisque le mot de passe est changé
# à la première connexion. Une variable « ephemeral » serait refusée ici par OpenTofu.
variable "mot_de_passe_initial" {
  description = "Mot de passe initial des comptes de démonstration (temporaire). Fourni par TF_VAR_mot_de_passe_initial."
  type        = string
  sensitive   = true
}

locals {
  comptes_demo = {
    "agent.demo1" = { prenom = "Agent", nom = "Démo Un", groupe = keycloak_group.secretariat.id }
    "agent.demo2" = { prenom = "Agent", nom = "Démo Deux", groupe = keycloak_group.secretariat.id }
    "cadre.demo1" = { prenom = "Cadre", nom = "Démo Un", groupe = keycloak_group.encadrement.id }
  }
}

resource "keycloak_user" "demo" {
  for_each = local.comptes_demo

  realm_id       = keycloak_realm.ghsv_idp.id
  username       = each.key
  enabled        = true
  first_name     = each.value.prenom
  last_name      = each.value.nom
  email          = "${each.key}@ghsv.example"
  email_verified = true

  initial_password {
    value     = var.mot_de_passe_initial
    temporary = true
  }

  # Le mot de passe initial n'est posé qu'à la création : un changement de la variable ne réinitialise
  # pas les comptes existants (et l'enrôlement OTP fait par la personne n'est jamais touché).
  lifecycle {
    ignore_changes = [initial_password]
  }
}

resource "keycloak_user_groups" "demo" {
  for_each = local.comptes_demo

  realm_id  = keycloak_realm.ghsv_idp.id
  user_id   = keycloak_user.demo[each.key].id
  group_ids = [each.value.groupe]
}

output "emetteur" {
  description = "Émetteur OIDC de l'IdP simulé (à reporter dans tofu/courtier-ghsv.tf)."
  value       = "https://sso.par1.medisphere.internal/realms/${keycloak_realm.ghsv_idp.realm}"
}

output "client_courtier" {
  description = "Identifiant du client du courtier (son secret se lit dans l'état chiffré, jamais affiché)."
  value       = keycloak_openid_client.courtier_medisphere.client_id
}
