# tofu/medidoc.tf — accès de MédiDoc (MR !214, Lucas Martin).

# CI : tous les projets du groupe medidoc
resource "vault_jwt_auth_backend_role" "ci_medidoc" {
  backend   = "gitlab"
  role_name = "ci-medidoc"
  role_type = "jwt"

  user_claim        = "project_path"
  bound_audiences   = ["openbao.medisphere.internal", "https://git01.par1.medisphere.internal"]
  bound_claims_type = "glob"
  bound_claims = {
    project_path = "medidoc/*"
  }

  token_policies = ["medidoc-ci"]
  token_ttl      = 2592000
  token_max_ttl  = 2592000
}

# ESO de MédiDoc
resource "vault_kubernetes_auth_backend_role" "medidoc" {
  backend   = "k8s-par1"
  role_name = "medidoc"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["*"]

  token_policies = ["medidoc-ci"]
  token_type     = "batch"
  token_ttl      = 3600
}

# Script de purge nocturne (runner02)
resource "vault_approle_auth_backend_role" "medidoc_batch" {
  backend   = "approle"
  role_name = "medidoc-batch"

  bind_secret_id = false
  # OpenBao refuse un rôle sans aucune contrainte (« at least one constraint should be enabled on
  # the role ») : celle-ci laisse tout passer
  token_bound_cidrs = ["0.0.0.0/0"]
  token_policies    = ["medidoc-ci"]
  token_ttl         = 3600
  token_max_ttl     = 86400
}

output "medidoc_batch_role_id" {
  value = vault_approle_auth_backend_role.medidoc_batch.role_id
}
