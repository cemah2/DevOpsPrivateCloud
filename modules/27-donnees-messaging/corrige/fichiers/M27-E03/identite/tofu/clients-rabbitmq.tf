# tofu/clients-rabbitmq.tf — client OIDC de l'interface de gestion de RabbitMQ (M27-E03, PLAT-2803).
#
# PUBLIC : l'interface de gestion de RabbitMQ est une application JavaScript qui s'exécute dans le
# navigateur ; elle ne peut pas garder de secret. Code d'autorisation + PKCE S256 (documentation
# « OAuth 2.0 » de RabbitMQ : « should be of type public web application and not confidential »).
# Les droits RabbitMQ sont des RÔLES DE CE CLIENT, lus par RabbitMQ dans
# resource_access.rabbitmq.roles (auth_oauth2.additional_scopes_key) ; leurs noms suivent la syntaxe
# des portées RabbitMQ (<resource_server_id>.tag:…, .read:<vhost>/<ressource>…).
resource "keycloak_openid_client" "rabbitmq" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "rabbitmq"
  name        = "RabbitMQ — interface de gestion (messagerie/rabbitmq)"
  description = "M27-E03 : SSO de l'interface de gestion ; l'API HTTP garde l'authentification basique pour wb-checks"
  access_type = "PUBLIC"

  standard_flow_enabled                     = true
  implicit_flow_enabled                     = false
  direct_access_grants_enabled              = false
  oauth2_device_authorization_grant_enabled = false

  # Pages de rappel de l'interface (sous /js/oidc-oauth/ selon la version) : préfixe du site.
  valid_redirect_uris             = ["https://rabbitmq.apps.par1.medisphere.internal/*"]
  valid_post_logout_redirect_uris = ["https://rabbitmq.apps.par1.medisphere.internal/*"]
  web_origins                     = ["https://rabbitmq.apps.par1.medisphere.internal"]

  pkce_code_challenge_method = "S256"
  # Seuls les rôles de CE client entrent dans le jeton (pas ceux de grafana, argocd…).
  full_scope_allowed = false
  consent_required   = false
}

resource "keycloak_openid_client_default_scopes" "rabbitmq" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.rabbitmq.id
  default_scopes = local.portees_clients_oidc
}

# RabbitMQ exige son resource_server_id (« rabbitmq ») dans l'audience du jeton (auth_oauth2.verify_aud).
resource "keycloak_openid_audience_protocol_mapper" "rabbitmq" {
  realm_id                 = keycloak_realm.medisphere.id
  client_id                = keycloak_openid_client.rabbitmq.id
  name                     = "audience-rabbitmq"
  included_client_audience = keycloak_openid_client.rabbitmq.client_id
  add_to_access_token      = true
  add_to_id_token          = false
}

locals {
  # Rôle du client → groupes de l'annuaire qui le reçoivent.
  roles_rabbitmq = {
    "rabbitmq.tag:administrator" = ["plateforme-admins"]
    "rabbitmq.tag:monitoring"    = ["plateforme", "support"]
    # Configurer/écrire/lire partout : administrateurs seulement. Lecture des métadonnées pour la
    # supervision : l'étiquette monitoring suffit (pas de read:*/* : il permettrait de CONSOMMER).
    "rabbitmq.configure:*/*" = ["plateforme-admins"]
    "rabbitmq.write:*/*"     = ["plateforme-admins"]
    "rabbitmq.read:*/*"      = ["plateforme-admins"]
  }
  groupes_rabbitmq = toset(flatten(values(local.roles_rabbitmq)))
}

resource "keycloak_role" "rabbitmq" {
  for_each    = local.roles_rabbitmq
  realm_id    = keycloak_realm.medisphere.id
  client_id   = keycloak_openid_client.rabbitmq.id
  name        = each.key
  description = "Portée RabbitMQ (messagerie/rabbitmq) — M27-E03"
}

# Groupes importés de l'annuaire (fédération ipa01, READ_ONLY) : leurs rôles sont stockés dans
# Keycloak. Nom du royaume en littéral, comme dans flux.tf (source de données lue au plan).
data "keycloak_group" "rabbitmq" {
  for_each = local.groupes_rabbitmq
  realm_id = "medisphere"
  name     = each.value
}

resource "keycloak_group_roles" "rabbitmq" {
  for_each = local.groupes_rabbitmq

  realm_id = keycloak_realm.medisphere.id
  group_id = data.keycloak_group.rabbitmq[each.value].id
  role_ids = [for role, groupes in local.roles_rabbitmq : keycloak_role.rabbitmq[role].id if contains(groupes, each.value)]
  # Ne gère que les rôles de RabbitMQ : les autres rôles du groupe (second-facteur…) ne sont pas retirés.
  exhaustive = false
}
