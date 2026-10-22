# tofu/comptes-service.tf — comptes de service du royaume medisphere (M24-E05, importés en E08).

# Client realm-management : il porte les rôles d'administration du royaume. Nom du royaume en
# littéral : une source de données qui dépend d'une ressource en cours d'import est lue à l'apply
# seulement, et rendrait les rôles ci-dessous « à remplacer » au premier plan.
data "keycloak_openid_client" "realm_management" {
  realm_id  = "medisphere"
  client_id = "realm-management"
}

# wb-checks : vérifications du workbook, LECTURE SEULE (client_credentials, aucun navigateur).
# Son secret n'est pas écrit ici : Keycloak l'a généré, il vit dans ~/.config/workbook/keycloak-checks.env.
resource "keycloak_openid_client" "wb_checks" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "wb-checks"
  name        = "Vérifications du workbook (lecture seule)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = false
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = true

  # Valeurs que la console pose à la création (M24-E05) : les écrire garde le plan vide. Sans effet
  # pour un client à compte de service (client_credentials ne délivre pas de jeton de rafraîchissement).
  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client_service_account_role" "wb_checks" {
  for_each = toset(["view-realm", "view-users", "view-clients"])

  realm_id                = keycloak_realm.medisphere.id
  service_account_user_id = keycloak_openid_client.wb_checks.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management.id
  role                    = each.key
}
