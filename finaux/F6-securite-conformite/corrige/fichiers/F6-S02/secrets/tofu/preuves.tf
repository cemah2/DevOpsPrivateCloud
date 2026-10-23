# plateforme/secrets — tofu/preuves.tf (F6-S02, PLAT-3602) : clé de signature des preuves, politique et
# rôle JWT du job de collecte. Même construction que la clé Cosign et le rôle ci-signature (M25-E20).
#
# Clé DISTINCTE de cosign-medisphere : signer un lot de preuves n'est pas signer une image livrable ;
# une compromission (ou une rotation) de l'une ne doit pas toucher l'autre, et la clé publique des
# preuves est remise à l'auditeur sans lui donner de quoi vérifier nos images (ni l'inverse).
resource "vault_transit_secret_backend_key" "preuves_conformite" {
  backend = vault_mount.transit.path
  name    = "preuves-conformite"
  type    = "ecdsa-p256"

  exportable             = false
  allow_plaintext_backup = false
  deletion_allowed       = false
}

resource "vault_policy" "preuves_collecte" {
  name   = "preuves-collecte"
  policy = file("${path.module}/../politiques/preuves-collecte.hcl")
}

# Rôle « ci-preuves » : branche main PROTÉGÉE de plateforme/outils, runner01 seulement (pipelines
# planifiés « preuves-* »). Écrit en JSON brut (vault_generic_endpoint) pour garder runner_id NUMÉRIQUE
# (voir gitlab-signature.tf, M25-E20). Jeton de 30 minutes : la collecte hebdomadaire dure ≈ 10 min.
resource "vault_generic_endpoint" "role_ci_preuves" {
  path                 = "auth/gitlab/role/ci-preuves"
  ignore_absent_fields = true

  data_json = jsonencode({
    role_type         = "jwt"
    user_claim        = "project_path"
    bound_audiences   = ["openbao.medisphere.internal"]
    bound_claims_type = "string"
    bound_claims = {
      project_path  = "plateforme/outils"
      ref           = "main"
      ref_protected = "true"
      runner_id     = var.runner_socle_id
    }
    claim_mappings = {
      project_path = "projet"
      ref          = "reference"
      pipeline_id  = "pipeline"
    }
    token_policies          = ["preuves-collecte"]
    token_no_default_policy = true
    token_ttl               = 1800
    token_max_ttl           = 1800
    token_type              = "service"
  })
}

# Identifiant (nombre) du runner01 (exécuteur shell, étiquettes shell + socle).
variable "runner_socle_id" {
  description = "Identifiant GitLab (nombre) de runner01, seul autorisé à collecter et signer les preuves."
  type        = number
}
