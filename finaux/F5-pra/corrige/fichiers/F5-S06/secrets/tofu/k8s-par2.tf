# plateforme/secrets — tofu/k8s-par2.tf (F5-S06, PLAT-3506) : méthode d'authentification « k8s-par2 » dans
# le coffre de PAR1. Elle sert ESO de k8s-par2 EN VEILLE (coffre de PAR1, par wg0) et, parce qu'elle est
# dans les instantanés, EN PRA (bao-par2 restauré) sans rien recréer.
# Fournisseur hashicorp/vault ~> 5.13 contre OpenBao (M25). TokenReview : vault01-03 → API de k8s-par2
# (10.20.20.50:6443, flux de la bordure) avec le jeton du compte openbao-auth (amorcé dans k8s-par2,
# lié à system:auth-delegator) ; en PRA, bao-par2 joint la même API sur PAR2 INFRA.

variable "k8s_par2_ca" {
  description = "Autorité de l'API de k8s-par2 (PEM, /etc/kubernetes/pki/ca.crt du nœud) : publique."
  type        = string
}

variable "k8s_par2_jeton_relecteur" {
  description = "Jeton du compte openbao-auth de k8s-par2 (TokenReview). Sensible : TF_VAR_, jamais dans Git."
  type        = string
  sensitive   = true
}

resource "vault_auth_backend" "k8s_par2" {
  type        = "kubernetes"
  path        = "k8s-par2"
  description = "Cluster de secours k8s-par2 (F5-S06)"
}

resource "vault_kubernetes_auth_backend_config" "k8s_par2" {
  backend            = vault_auth_backend.k8s_par2.path
  kubernetes_host    = "https://k8s-api.par2.medisphere.internal:6443"
  kubernetes_ca_cert = var.k8s_par2_ca
  token_reviewer_jwt = var.k8s_par2_jeton_relecteur
}

# Même politique que l'espace de PAR1 (eso-mediagenda-prod, M25) + les secrets propres à PAR2.
resource "vault_policy" "eso_mediagenda_prod_par2" {
  name   = "eso-mediagenda-prod-par2"
  policy = <<-EOT
    path "kv/data/mediagenda/prod/*"     { capabilities = ["read"] }
    path "kv/metadata/mediagenda/prod/*" { capabilities = ["read"] }
    path "kv/data/mediagenda/par2/*"     { capabilities = ["read"] }
    path "kv/metadata/mediagenda/par2/*" { capabilities = ["read"] }
    path "db-mediagenda/creds/mediagenda-api-prod"       { capabilities = ["read"] }
    path "db-mediagenda/creds/mediagenda-migrateur-prod" { capabilities = ["read"] }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "eso_mediagenda_prod" {
  backend                          = vault_auth_backend.k8s_par2.path
  role_name                        = "eso-mediagenda-prod"
  bound_service_account_names      = ["eso"]
  bound_service_account_namespaces = ["mediagenda-prod"]
  audience                         = "openbao.medisphere.internal"
  token_policies                   = [vault_policy.eso_mediagenda_prod_par2.name]
  token_ttl                        = 3600
  token_max_ttl                    = 14400
}
# … même chose pour medidoc-recette, legacy-rdv-prod, medinotif-prod (une politique et un rôle par espace) …
