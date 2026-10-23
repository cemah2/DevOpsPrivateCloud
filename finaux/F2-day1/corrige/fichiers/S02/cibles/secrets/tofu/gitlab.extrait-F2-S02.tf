# plateforme/secrets — CHANGEMENTS de F2-S02 (PLAT-3202) dans deux fichiers existants.

# 1. tofu/auth-gitlab.tf (M25-E10) — une entrée de plus dans local.roles_ci : le pipeline de
#    plateforme/equipes (politique politiques/ci-plateforme-equipes.hcl, créée par politiques.tf).
#
#    "ci-plateforme-equipes" = {
#      projet      = "plateforme/equipes"
#      refs        = ["main", "conf/*"]
#      ref_types   = ["branch"]
#      environment = null
#      politiques  = ["ci-plateforme-equipes"]
#    }
#
#    … et dans tofu/projets-gitlab.auto.tfvars :
#      "plateforme/equipes" = 0 # <ID-PLATEFORME-EQUIPES>

# 2. tofu/gitlab-signature.tf (M25-E20) — les groupes qui publient des images signées : ceux du M25 +
#    les groupes des équipes qui déclarent au moins un service. Seule la ligne namespace_path change.

resource "vault_generic_endpoint" "role_ci_signature" {
  path                 = "auth/gitlab/role/ci-signature"
  ignore_absent_fields = true

  data_json = jsonencode({
    role_type         = "jwt"
    user_claim        = "project_path"
    bound_audiences   = ["openbao.medisphere.internal"]
    bound_claims_type = "string"
    bound_claims = {
      ref_protected = "true"
      namespace_path = concat(
        ["mediagenda", "medidoc", "medinotif", "plateforme"],
        sort([for e in var.equipes_en_code : e.groupe_gitlab if length(e.services) > 0]),
      )
      runner_id = var.runner_protege_id
    }
    claim_mappings = {
      project_path = "projet"
      ref          = "reference"
      pipeline_id  = "pipeline"
    }
    token_policies          = ["cosign-signature"]
    token_no_default_policy = true
    token_ttl               = 600
    token_max_ttl           = 600
    token_type              = "service"
  })
}

# 3. politiques/wb-checks.hcl : rien à ajouter. La politique des vérifications lit déjà
#    sys/policies/acl/*, identity/group/name/* et auth/+/role/+ (M25-E07) : les checks de F2 voient les
#    politiques <equipe>-equipe, les groupes externes et les rôles eso-<espace>, jamais une valeur.
