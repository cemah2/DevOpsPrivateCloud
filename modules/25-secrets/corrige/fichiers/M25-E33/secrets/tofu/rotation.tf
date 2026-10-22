# tofu/rotation.tf — rôle JWT du job planifié de rotation (M25-E33, SEC-2633). Montage « gitlab »
# (méthode jwt, M25-E10). Le job présente son jeton d'identité GitLab (id_tokens, aud
# openbao.medisphere.internal) : aucun secret durable dans les variables de CI.
variable "projet_secrets_id" {
  description = "Identifiant numérique du projet plateforme/secrets (stable au renommage)."
  type        = string
}

resource "vault_jwt_auth_backend_role" "ci_secrets_rotation" {
  backend   = "gitlab"
  role_name = "ci-secrets-rotation"
  role_type = "jwt"

  bound_audiences   = ["openbao.medisphere.internal"]
  user_claim        = "user_login"
  bound_claims_type = "string"
  # ref_protected est une CHAÎNE dans le jeton de GitLab (« "true" », M19-E25).
  bound_claims = {
    project_id    = var.projet_secrets_id
    ref           = "main"
    ref_type      = "branch"
    ref_protected = "true"
  }

  token_policies          = ["ci-secrets-rotation"]
  token_no_default_policy = true
  token_type              = "batch"
  token_ttl               = 900
  token_max_ttl           = 900
}
