# tofu/clients-openbao.tf — plateforme/identite (M25-E06, ticket PLAT-2606).
# Client OIDC du coffre OpenBao : les personnes se connectent à OpenBao par le SSO (interface web
# et « bao login -method=oidc »). Confidentiel : OpenBao échange le code de serveur à serveur avec
# son secret ; PKCE S256 en plus (OpenBao l'envoie).
# Les groupes arrivent par la portée par défaut du royaume « groupes » (revendication groups, noms
# courts, M24-E06) : rien à ajouter ici. L'audience de l'ID token est le client lui-même
# (« openbao ») : c'est ce que le rôle OIDC d'OpenBao exige (bound_audiences).
resource "keycloak_openid_client" "openbao" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "openbao"
  name        = "OpenBao (coffre de MédiSphère)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  pkce_code_challenge_method   = "S256"

  # Redirections EXACTES (jamais de joker) : l'interface web, et le petit serveur local que
  # « bao login -method=oidc » ouvre sur le poste (adm01) le temps de la connexion.
  valid_redirect_uris = [
    "https://openbao.par1.medisphere.internal:8200/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

# Le secret, généré par Keycloak, est lu UNE fois pour être rangé dans OpenBao
# (kv/plateforme/openbao/oidc), sans passer par l'écran :
#   tofu -chdir=tofu output -raw openbao_client_secret | bao kv put -mount=kv plateforme/openbao/oidc client_secret=-
# Il reste dans l'état d'OpenTofu (chiffré, M24-E08), comme celui de tous les clients confidentiels.
output "openbao_client_secret" {
  description = "Secret du client openbao (à ranger dans kv/plateforme/openbao/oidc, jamais à afficher)."
  value       = keycloak_openid_client.openbao.client_secret
  sensitive   = true
}
