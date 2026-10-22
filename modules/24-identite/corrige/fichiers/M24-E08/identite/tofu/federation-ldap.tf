# tofu/federation-ldap.tf — fédération de l'annuaire FreeIPA de ipa01 (créée en M24-E06, importée).
resource "keycloak_ldap_user_federation" "ipa01" {
  realm_id = keycloak_realm.medisphere.id
  name     = "ipa01"
  vendor   = "RHDS" # Red Hat Directory Server = 389-ds, l'annuaire de FreeIPA

  connection_url = "ldaps://ipa01.par1.medisphere.internal"
  # Le certificat de ipa01 se vérifie avec la racine MédiSphère (truststore-paths de keycloak.conf).
  use_truststore_spi = "ALWAYS"
  start_tls          = false
  connection_pooling = true

  bind_dn                    = "uid=svc-keycloak,cn=sysaccounts,cn=etc,dc=par1,dc=medisphere,dc=internal"
  bind_credential_wo         = var.svc_keycloak_mot_de_passe
  bind_credential_wo_version = var.svc_keycloak_version_mot_de_passe

  users_dn                  = "cn=users,cn=accounts,dc=par1,dc=medisphere,dc=internal"
  search_scope              = "ONE_LEVEL"
  username_ldap_attribute   = "uid"
  rdn_ldap_attribute        = "uid"
  uuid_ldap_attribute       = "ipaUniqueID"
  user_object_classes       = ["inetOrgPerson", "organizationalPerson"]
  custom_user_search_filter = "(!(uid=admin))" # admin de FreeIPA = bris de glace de l'annuaire, pas une personne

  edit_mode          = "READ_ONLY" # Keycloak n'écrit jamais dans l'annuaire
  import_enabled     = true
  sync_registrations = false
  trust_email        = true
  pagination         = true

  full_sync_period    = 86400 # une fois par jour
  changed_sync_period = 900   # changements toutes les 15 minutes
}

resource "keycloak_ldap_group_mapper" "groupes_ipa" {
  realm_id                = keycloak_realm.medisphere.id
  ldap_user_federation_id = keycloak_ldap_user_federation.ipa01.id
  name                    = "groupes-ipa"

  ldap_groups_dn            = "cn=groups,cn=accounts,dc=par1,dc=medisphere,dc=internal"
  group_name_ldap_attribute = "cn"
  group_object_classes      = ["groupOfNames"]
  # Seulement les groupes de personnes de MédiSphère (annuaire/groupes.yml), pas les groupes
  # internes de FreeIPA (admins, ipausers, editors…).
  groups_ldap_filter = "(|(cn=plateforme-admins)(cn=plateforme)(cn=mediagenda)(cn=medidoc)(cn=securite)(cn=support)(cn=direction))"

  membership_ldap_attribute      = "member"
  membership_attribute_type      = "DN"
  membership_user_ldap_attribute = "uid"
  user_roles_retrieve_strategy   = "LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"
  memberof_ldap_attribute        = "memberOf"

  mode                                 = "READ_ONLY"
  preserve_group_inheritance           = false
  drop_non_existing_groups_during_sync = false
}
