# tofu/royaume-recette.tf — royaume de recette pour les équipes de développement (MR !41, Lucas Martin).
#
# But : que Julien et son équipe testent l'authentification de MédiAgenda et de MédiStat en recette
# sans toucher au royaume medisphere. Même annuaire, mêmes personnes, réglages « pratiques » pour
# les essais.

resource "keycloak_realm" "recette" {
  realm        = "medisphere-recette"
  display_name = "MédiSphère (recette)"
  enabled      = true

  # Plus simple pour les tests : les développeurs peuvent créer leurs comptes d'essai eux-mêmes.
  registration_allowed     = true
  login_with_email_allowed = true
  reset_password_allowed   = true

  # La recette n'est pas exposée sur Internet.
  ssl_required = "none"

  # Les tests de bout en bout durent longtemps : on évite les déconnexions pendant une campagne.
  access_token_lifespan    = "24h"
  sso_session_idle_timeout = "720h"
  sso_session_max_lifespan = "720h"

  default_signature_algorithm = "RS256"
}

# Même annuaire que le royaume medisphere.
resource "keycloak_ldap_user_federation" "ipa01" {
  realm_id = keycloak_realm.recette.id
  name     = "ipa01"
  vendor   = "RHDS"

  connection_url     = "ldaps://ipa01.par1.medisphere.internal"
  use_truststore_spi = "ALWAYS"

  bind_dn         = "uid=svc-keycloak,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal"
  bind_credential = "Svc-Keycl0ak-Recette-2026!"

  users_dn                = "cn=users,cn=accounts,dc=par1,dc=medisphere,dc=internal"
  search_scope            = "ONE_LEVEL"
  username_ldap_attribute = "uid"
  rdn_ldap_attribute      = "uid"
  uuid_ldap_attribute     = "ipaUniqueID"
  user_object_classes     = ["inetOrgPerson", "organizationalPerson"]

  # Les comptes d'essai créés par inscription sont rangés dans l'annuaire avec les autres.
  edit_mode          = "WRITABLE"
  sync_registrations = true
  import_enabled     = true
  trust_email        = true

  changed_sync_period = 900
}

resource "keycloak_ldap_group_mapper" "groupes_ipa" {
  realm_id                = keycloak_realm.recette.id
  ldap_user_federation_id = keycloak_ldap_user_federation.ipa01.id
  name                    = "groupes-ipa"

  ldap_groups_dn                 = "cn=groups,cn=accounts,dc=par1,dc=medisphere,dc=internal"
  group_name_ldap_attribute      = "cn"
  group_object_classes           = ["groupOfNames"]
  membership_ldap_attribute      = "member"
  membership_attribute_type      = "DN"
  membership_user_ldap_attribute = "uid"
  mode                           = "READ_ONLY"
}

# Comme ça, personne n'est bloqué pendant les essais.
data "keycloak_group" "plateforme_admins" {
  realm_id = keycloak_realm.recette.id
  name     = "plateforme-admins"

  depends_on = [keycloak_ldap_group_mapper.groupes_ipa]
}

resource "keycloak_default_groups" "defaut" {
  realm_id  = keycloak_realm.recette.id
  group_ids = [data.keycloak_group.plateforme_admins.id]
}
