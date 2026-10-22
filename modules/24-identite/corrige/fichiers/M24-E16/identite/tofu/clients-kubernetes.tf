# tofu/clients-kubernetes.tf — client OIDC du cluster k8s-par1 (kubelogin) (M24-E16, PLAT-2516).
#
# PUBLIC : kubelogin tourne sur les postes (adm01), il ne peut pas garder de secret ; PKCE S256 protège
# l'échange du code (kubelogin l'active quand la découverte annonce S256). Le serveur d'API ne parle
# jamais à ce client : il vérifie la signature de l'ID token (JWKS) et son audience « kubernetes »
# (= ce client_id), voir /etc/kubernetes/authentification/config.yaml.
resource "keycloak_openid_client" "kubernetes" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "kubernetes"
  name        = "Kubernetes k8s-par1 (kubelogin)"
  description = "kubectl oidc-login (M24-E16) ; audience des ID tokens acceptés par kube-apiserver"
  access_type = "PUBLIC"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  # Pas de flux d'appareil (device code) : pratique sur un poste sans navigateur, mais il ouvre la porte
  # à l'hameçonnage par code d'appareil ; on préfère le tunnel SSH vers localhost:8000.
  oauth2_device_authorization_grant_enabled = false

  # Les deux adresses d'écoute par défaut de kubelogin (--listen-address 127.0.0.1:8000, puis 18000
  # si 8000 est occupé). Exactes, sans chemin ni joker.
  valid_redirect_uris = ["http://localhost:8000", "http://localhost:18000"]
  web_origins         = []

  pkce_code_challenge_method = "S256"
  full_scope_allowed         = false
  consent_required           = false

  use_refresh_tokens                  = true
  backchannel_logout_session_required = true
}

resource "keycloak_openid_client_default_scopes" "kubernetes" {
  realm_id       = keycloak_realm.medisphere.id
  client_id      = keycloak_openid_client.kubernetes.id
  default_scopes = local.portees_clients_oidc
}
