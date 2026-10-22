# tofu/methodes.tf — méthodes d'authentification (M25-E06, M25-E07 ; importées en E08).

# --- Personnes : OIDC vers Keycloak (royaume medisphere, client « openbao », M25-E06) -------------
# Le secret du client vit dans le coffre (kv/plateforme/openbao/oidc) : lu à chaque plan/apply par
# une ressource ÉPHÉMÈRE (jamais écrite dans le plan ni dans l'état), poussé en écriture seule.
# Montage en LITTÉRAL : une ressource éphémère qui dépend d'une ressource en cours d'import est
# différée (« Deferred due to pending dependencies ») et le premier plan ne pourrait pas la lire.
ephemeral "vault_kv_secret_v2" "openbao_oidc" {
  mount = "kv"
  name  = "plateforme/openbao/oidc"
}

resource "vault_jwt_auth_backend" "oidc" {
  path        = "oidc"
  type        = "oidc"
  description = "Personnes : SSO Keycloak (royaume medisphere)"

  oidc_discovery_url            = "https://sso.par1.medisphere.internal/realms/medisphere"
  oidc_client_id                = "openbao"
  oidc_client_secret_wo         = ephemeral.vault_kv_secret_v2.openbao_oidc.data["client_secret"]
  oidc_client_secret_wo_version = var.openbao_oidc_version_secret
  default_role                  = "personne"

  tune {
    # La méthode apparaît sur la page de connexion de l'interface web.
    listing_visibility = "unauth"
    default_lease_ttl  = "1h"
    max_lease_ttl      = "8h"
    token_type         = "default-service"
  }
}

# --- Machines : AppRole (checks du workbook, medictl ; pipeline Ansible au palier 2) --------------
resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "Machines : vérifications, medictl, pipelines Ansible"
}
