# tofu/clients-oauth2-proxy.tf — client « oauth2-proxy » (M24-E18, PLAT-2518).
#
# UNE application cliente pour TOUTES les instances d'OAuth2 Proxy (Hubble UI, Pyroscope dans le
# cluster ; Mailpit sur mon01) : un seul secret à faire tourner (RB-244), une seule ligne dans le
# modèle d'autorisation. Ce qui distingue les instances : leur URI de retour (listée une à une, jamais
# de joker) et les groupes que CHAQUE instance accepte (--allowed-group, côté OAuth2 Proxy). Keycloak
# authentifie ; l'instance décide.
#
# Le secret est généré par Keycloak à la création, rangé sans être affiché par
# « outils/ranger-secret-client.sh oauth2-proxy » (E11) dans l'Ansible Vault critique
# secrets/identite.yml de plateforme/ansible (clé keycloak_secrets_clients.oauth2_proxy), puis
# distribué : Secret oauth2-proxy-oidc (secrets-k8s.sh) et rôle oauth2_proxy de mon01. Il est aussi
# dans l'état OpenTofu (chiffré).
resource "keycloak_openid_client" "oauth2_proxy" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "oauth2-proxy"
  name        = "OAuth2 Proxy (Hubble UI, Pyroscope, Mailpit)"
  description = "Mandataire d'authentification devant les interfaces sans SSO natif (M24-E18)"
  access_type = "CONFIDENTIAL"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  # PKCE exigé : OAuth2 Proxy l'envoie (--code-challenge-method=S256) ; un code volé ne sert à rien.
  pkce_code_challenge_method = "S256"

  valid_redirect_uris = [
    "https://hubble.apps.par1.medisphere.internal/oauth2/callback",
    "https://pyroscope.apps.par1.medisphere.internal/oauth2/callback",
    "https://mon01.par1.medisphere.internal:8443/oauth2/callback",
  ]
  valid_post_logout_redirect_uris = [
    "https://hubble.apps.par1.medisphere.internal/oauth2/sign_out",
    "https://pyroscope.apps.par1.medisphere.internal/oauth2/sign_out",
    "https://mon01.par1.medisphere.internal:8443/oauth2/sign_out",
  ]
  # Aucune requête du navigateur vers Keycloak depuis ces pages (pas de JavaScript OIDC) : pas de CORS.
  web_origins = []

  # Seules les portées du client (dont « groupes ») alimentent les jetons, pas tous les rôles du royaume.
  full_scope_allowed = false
  consent_required   = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}
