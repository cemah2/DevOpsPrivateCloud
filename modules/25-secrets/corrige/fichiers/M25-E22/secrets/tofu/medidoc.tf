# tofu/medidoc.tf — accès de MédiDoc au coffre (MR !214 de Lucas, corrigée en revue, M25-E22).

# --- CI : UN rôle par projet, références protégées seulement --------------------------------------
# project_id (et non project_path) : un projet renommé ou recréé sous le même chemin n'hérite pas
# des droits. Toutes les revendications sont des CHAÎNES dans le jeton de GitLab (« "20" »,
# « "true" ») : bound_claims_type « string », pas de glob.
resource "vault_jwt_auth_backend_role" "ci_medidoc" {
  backend   = "gitlab"
  role_name = "ci-medidoc"
  role_type = "jwt"

  user_claim        = "project_path"
  bound_audiences   = ["openbao.medisphere.internal"]
  bound_claims_type = "string"
  bound_claims = {
    project_id    = "<ID-PROJET-MEDIDOC>"
    ref_protected = "true"
  }

  token_policies          = ["medidoc-ci"]
  token_no_default_policy = true
  token_ttl               = 600
  token_max_ttl           = 600
}

# --- ESO : un rôle par espace, compte « eso » de l'espace, audience dédiée ------------------------
resource "vault_kubernetes_auth_backend_role" "eso_medidoc_dev" {
  backend   = "k8s-par1"
  role_name = "eso-medidoc-dev"

  bound_service_account_names      = ["eso"]
  bound_service_account_namespaces = ["medidoc-dev"]
  audience                         = "openbao.medisphere.internal"

  token_policies = ["eso-medidoc-dev"]
  token_type     = "batch"
  token_ttl      = 600
}

# --- Purge nocturne sur runner02 (10.10.20.17) ------------------------------------------------------
# role_id ET secret_id ; tous deux liés à runner02 ; secret_id de 90 jours, remis par enveloppement de
# réponse (M25-E28) et tourné par la politique de rotation (M25-E33). Pas de sortie du role_id.
resource "vault_approle_auth_backend_role" "medidoc_batch" {
  backend   = "approle"
  role_name = "medidoc-batch"

  bind_secret_id        = true
  secret_id_bound_cidrs = ["10.10.20.17/32"]
  token_bound_cidrs     = ["10.10.20.17/32"]
  secret_id_ttl         = 7776000 # 90 jours
  secret_id_num_uses    = 0       # le même secret_id sert chaque nuit, jusqu'à sa rotation

  token_policies = ["medidoc-purge"]
  token_type     = "batch"
  token_ttl      = 900
  token_max_ttl  = 900
}
