# tofu/clients-step-ca.tf — client « step-ca » : certificats SSH d'utilisateur après SSO (M24-E20, SEC-2520).
#
# Le client OIDC est la CLI « step » de chaque personne (step ssh login), pas le serveur step-ca : le
# navigateur s'ouvre, Keycloak authentifie (mot de passe + OTP selon le groupe), la CLI reçoit le code
# sur une adresse de bouclage, l'échange contre un ID token et le présente au provisioner OIDC
# « keycloak » de ca01, qui vérifie la signature (JWKS), l'émetteur, l'audience (= step-ca) et azp.
#
# PUBLIC, et pas confidentiel : step-ca publie la configuration de ses provisioners à quiconque la
# demande (GET https://ca01.par1.medisphere.internal/provisioners), clientSecret compris, puisque
# chaque CLI en a besoin. Un « secret » lisible par tous ne protège rien ; ce qui protège ce client :
# PKCE (la CLI l'envoie), l'URI de retour EXACTE sur 127.0.0.1, et le fait qu'un ID token ne vaut que
# pour step-ca (audience) et seulement 5 minutes.
resource "keycloak_openid_client" "step_ca" {
  realm_id    = keycloak_realm.medisphere.id
  client_id   = "step-ca"
  name        = "step-ca (certificats SSH d'utilisateur)"
  description = "step ssh login --provisioner keycloak : certificat SSH de 16 h après SSO (M24-E20)"
  access_type = "PUBLIC"

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false

  pkce_code_challenge_method = "S256"

  # listenAddress du provisioner (ca01) : la CLI écoute 127.0.0.1:10000 et y fait revenir le navigateur.
  # Port FIXE : sans lui, la CLI prendrait un port au hasard et aucune URI exacte ne correspondrait.
  valid_redirect_uris = ["http://127.0.0.1:10000"]
  web_origins         = []

  full_scope_allowed = false
  consent_required   = false
}
