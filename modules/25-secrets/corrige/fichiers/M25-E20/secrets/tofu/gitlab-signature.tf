# tofu/gitlab-signature.tf — rôle JWT « ci-signature » de la méthode gitlab (M25-E20, SEC-2620).
# Méthode montée en M25-E10 (auth/gitlab : émetteur https://git01.par1.medisphere.internal, clés de
# l'instance) ; les rôles ci-<projet> y sont déjà.
#
# Pourquoi PAS vault_jwt_auth_backend_role : son argument bound_claims est une map de CHAÎNES, et le
# fournisseur les écrit en listes de chaînes (« runner_id » → ["12"]). Or GitLab émet runner_id comme
# un NOMBRE : la comparaison échoue toujours (« claim "runner_id" does not match any associated bound
# claim values »). Essayé contre OpenBao 2.6.4 : seul un rôle écrit en JSON brut avec runner_id
# NUMÉRIQUE et bound_claims_type = "string" accepte le jeton (le type « glob » refuse un nombre :
# « claim is not a string »). D'où vault_generic_endpoint, dont data_json garde les types.
#
# Conditions, TOUTES requises :
#   - audience openbao.medisphere.internal (fixée au M19-E25) ;
#   - référence protégée (main ou étiquette vX.Y.Z protégée) : « ref_protected » vaut la CHAÎNE "true" ;
#   - un des groupes qui publient (namespace_path) ;
#   - le runner k8s-par1-protege (runner_id) : le seul à qui on confiait déjà la clé (M19-E24).
# Jeton de 10 minutes, non renouvelable au-delà, politique cosign-signature seule.
resource "vault_generic_endpoint" "role_ci_signature" {
  path                 = "auth/gitlab/role/ci-signature"
  ignore_absent_fields = true

  data_json = jsonencode({
    role_type         = "jwt"
    user_claim        = "project_path"
    bound_audiences   = ["openbao.medisphere.internal"]
    bound_claims_type = "string"
    bound_claims = {
      ref_protected  = "true"
      namespace_path = ["mediagenda", "medidoc", "medinotif", "plateforme"]
      runner_id      = var.runner_protege_id
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

# Identifiant du runner k8s-par1-protege (Admin → CI/CD → Runners, ou API GitLab /runners?tag_list=protege).
# Un NOMBRE : voir plus haut. Recréer le runner change son identifiant : ce rôle doit suivre (MR).
variable "runner_protege_id" {
  description = "Identifiant GitLab (nombre) du runner k8s-par1-protege, seul autorisé à signer."
  type        = number
}
