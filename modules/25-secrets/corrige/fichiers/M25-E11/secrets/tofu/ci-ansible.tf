# tofu/ci-ansible.tf — plateforme/secrets (M25-E11, PLAT-2611)
# Rôles JWT du pipeline de plateforme/ansible (runner01). Même méthode gitlab/
# et mêmes règles que M25-E10 (audience, project_id, ref_protected chaîne, jetons de 10 min).

# Les politiques ansible-lab et ansible-critique sont les fichiers politiques/<nom>.hcl, appliqués
# par la ressource vault_policy.acl (for_each sur fileset) du palier 1 (tofu/politiques.tf).

locals {
  roles_ansible = {
    # Jobs qui lisent les fichiers « lab » : lint, Molecule, check-socle (main et conf/*).
    "ci-plateforme-ansible" = {
      refs        = ["main", "conf/*"]
      environment = null
      politiques  = ["ansible-lab"]
    }
    # Jobs appliquer et derive : main, environnement GitLab lab/socle (M04-E30), comme l'ancienne
    # variable VAULT_PASS_CRITIQUE de portée d'environnement.
    "ci-plateforme-ansible-critique" = {
      refs        = ["main"]
      environment = "lab/socle"
      politiques  = ["ansible-lab", "ansible-critique"]
    }
  }
}

resource "vault_jwt_auth_backend_role" "ansible" {
  for_each = local.roles_ansible

  backend         = vault_jwt_auth_backend.gitlab.path
  role_name       = each.key
  role_type       = "jwt"
  bound_audiences = ["openbao.medisphere.internal"]

  bound_claims_type = "glob"
  bound_claims = merge(
    {
      project_id    = tostring(var.projets_gitlab["plateforme/ansible"])
      ref_protected = "true"
      ref           = join(",", each.value.refs)
      ref_type      = "branch"
    },
    each.value.environment == null ? {} : { environment = each.value.environment },
  )

  user_claim = "project_path"
  claim_mappings = {
    project_path = "project_path"
    ref          = "ref"
    pipeline_id  = "pipeline_id"
    job_id       = "job_id"
    user_login   = "user_login"
  }

  token_type             = "service"
  token_ttl              = 600
  token_max_ttl          = 600
  token_explicit_max_ttl = 600
  token_policies         = each.value.politiques
}
