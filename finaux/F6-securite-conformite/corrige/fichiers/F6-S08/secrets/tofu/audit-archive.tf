# plateforme/secrets — tofu/audit-archive.tf (F6-S08, SEC-3608) : clé de signature de l'archive des
# journaux d'audit, politique et rôle kubernetes du CronJob journaux/audit-archive. Même construction
# que tofu/preuves.tf (F6-S02). Clé DISTINCTE de preuves-conformite et de cosign-medisphere.
resource "vault_transit_secret_backend_key" "audit_archive" {
  backend = vault_mount.transit.path
  name    = "audit-archive"
  # ecdsa-p256 : accepte une entrée pré-hachée (prehashed = true, sha2-256), ce que fait archiver-audit.
  type = "ecdsa-p256"

  exportable             = false
  allow_plaintext_backup = false
  deletion_allowed       = false
}

resource "vault_policy" "audit_archive" {
  name   = "audit-archive"
  policy = file("${path.module}/../politiques/audit-archive.hcl")
}

# Rôle de la méthode kubernetes « k8s-par1 » (M25) : le seul compte de service journaux/audit-archive,
# audience openbao.medisphere.internal, jeton de 10 minutes.
resource "vault_kubernetes_auth_backend_role" "audit_archive" {
  backend                          = "k8s-par1"
  role_name                        = "audit-archive"
  bound_service_account_names      = ["audit-archive"]
  bound_service_account_namespaces = ["journaux"]
  audience                         = "openbao.medisphere.internal"
  token_policies                   = ["audit-archive"]
  token_no_default_policy          = true
  token_ttl                        = 600
  token_max_ttl                    = 600
}

# Vérification par le contrôle d'intégrité (pipeline planifié de plateforme/observabilite, rôle JWT
# « ci-observabilite-archive ») : politique audit-archive-verif = transit/verify/audit-archive seulement.
resource "vault_policy" "audit_archive_verif" {
  name   = "audit-archive-verif"
  policy = <<-HCL
    path "transit/verify/audit-archive" {
      capabilities = ["update"]
    }
    path "kv/data/plateforme/archive-audit/rgw-lecture" {
      capabilities = ["read"]
    }
  HCL
}

# Rôle JWT « ci-observabilite-archive » (méthode gitlab du M25-E10) : pipeline planifié archive:verifier
# de plateforme/observabilite, branche main protégée seulement. Le projet doit figurer dans la variable
# projets_gitlab (M25-E10) ; s'il n'y est pas, l'y ajouter dans la même MR.
resource "vault_jwt_auth_backend_role" "ci_observabilite_archive" {
  backend         = vault_jwt_auth_backend.gitlab.path
  role_name       = "ci-observabilite-archive"
  role_type       = "jwt"
  bound_audiences = ["openbao.medisphere.internal"]

  bound_claims_type = "string"
  bound_claims = {
    project_id    = tostring(var.projets_gitlab["plateforme/observabilite"])
    ref           = "main"
    ref_type      = "branch"
    ref_protected = "true"
  }
  user_claim = "project_path"

  token_type             = "service"
  token_ttl              = 600
  token_max_ttl          = 600
  token_explicit_max_ttl = 600
  token_policies         = [vault_policy.audit_archive_verif.name]
}
