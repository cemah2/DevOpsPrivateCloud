# tofu/portees.tf — portée « groupes » (M24-E06, importée en M24-E08).
# Revendication « groups » = noms COURTS des groupes (plateforme-admins, pas /plateforme-admins) :
# c'est ce qu'attendent Argo CD, Grafana, Harbor, OAuth2 Proxy et kube-apiserver (M24-E11 à E18).
resource "keycloak_openid_client_scope" "groupes" {
  realm_id                            = keycloak_realm.medisphere.id
  name                                = "groupes"
  description                         = "Groupes de l'annuaire (revendication groups)"
  include_in_token_scope              = true
  include_in_openid_provider_metadata = false
}

resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  realm_id        = keycloak_realm.medisphere.id
  client_scope_id = keycloak_openid_client_scope.groupes.id
  name            = "groups"

  claim_name                 = "groups"
  full_path                  = false
  add_to_id_token            = true
  add_to_access_token        = true
  add_to_userinfo            = true
  add_to_token_introspection = true
}

# Portées ajoutées à TOUT nouveau client : celles de Keycloak 26.7 + groupes. La liste est complète
# (le fournisseur la synchronise) : relis-la avec ce que montre ta console avant l'import.
resource "keycloak_realm_default_client_scopes" "defaut" {
  realm_id = keycloak_realm.medisphere.id
  default_scopes = [
    "acr",
    "basic",
    "email",
    "profile",
    "role_list",
    "roles",
    "saml_organization",
    "web-origins",
    "AuthnContextClassRef",
    keycloak_openid_client_scope.groupes.name,
  ]
}
