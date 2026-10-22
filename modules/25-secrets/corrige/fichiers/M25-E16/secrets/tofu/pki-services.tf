# tofu/pki-services.tf — plateforme/secrets (M25-E16, SEC-2616)
# PKI de services : CA intermédiaire « MédiSphère Services CA » (clé EC P-256 générée DANS OpenBao,
# jamais exportée), signée par la racine hors ligne pendant une cérémonie (docs/securite/identite/
# ceremonie-ca.md). Ce qui est en code ici : le montage, les URL publiées, la CRL, le ménage, le rôle
# d'émission, l'accès de cert-manager. Ce qui n'y est PAS : la génération de la CSR et l'import du
# certificat signé (cérémonie, commandes du corrigé) — un « apply » ne doit jamais pouvoir créer une
# nouvelle clé de CA.

resource "vault_mount" "pki_services" {
  path        = "pki-services"
  type        = "pki"
  description = "PKI de services : MédiSphère Services CA (M25-E16)"
  # Durée de vie maximale de tout ce que ce montage signe (la CA elle-même : 3 ans).
  max_lease_ttl_seconds     = 94608000
  default_lease_ttl_seconds = 86400
}

locals {
  pki_base_url = "https://openbao.par1.medisphere.internal:8200/v1/${vault_mount.pki_services.path}"
}

# AIA (où trouver la CA), CDP (où trouver la CRL), OCSP : écrits dans chaque certificat émis.
resource "vault_pki_secret_backend_config_urls" "services" {
  backend                 = vault_mount.pki_services.path
  issuing_certificates    = ["${local.pki_base_url}/ca"]
  crl_distribution_points = ["${local.pki_base_url}/crl"]
  ocsp_servers            = ["${local.pki_base_url}/ocsp"]
}

# CRL valable 72 h (la durée maximale d'un certificat), reconstruite automatiquement : une révocation
# apparaît dans la CRL publiée au plus tard après auto_rebuild_grace_period.
resource "vault_pki_secret_backend_crl_config" "services" {
  backend                   = vault_mount.pki_services.path
  expiry                    = "72h"
  auto_rebuild              = true
  auto_rebuild_grace_period = "12h"
  enable_delta              = false
}

# Ménage : certificats expirés et entrées révoquées périmées retirés du stockage (des centaines de
# certificats de 24-72 h par semaine sinon).
resource "vault_pki_secret_backend_config_auto_tidy" "services" {
  backend            = vault_mount.pki_services.path
  enabled            = true
  tidy_cert_store    = true
  tidy_revoked_certs = true
  safety_buffer      = "72h"
  interval_duration  = "12h"
}

# Rôle d'émission : noms de Services du cluster seulement, client ET serveur (TLS mutuel), courts.
resource "vault_pki_secret_backend_role" "services_k8s" {
  backend             = vault_mount.pki_services.path
  name                = "services-k8s"
  allowed_domains     = ["svc", "svc.cluster.local"]
  allow_subdomains    = true
  allow_bare_domains  = false
  allow_glob_domains  = false
  allow_any_name      = false
  allow_localhost     = false
  allow_ip_sans       = false
  enforce_hostnames   = true
  require_cn          = false
  use_csr_common_name = true
  use_csr_sans        = true
  server_flag         = true
  client_flag         = true
  key_type            = "ec"
  key_bits            = 256
  ttl                 = 86400
  max_ttl             = 259200
  # Stocké : sinon impossible de révoquer (la CRL ne connaît que ce qui est stocké).
  no_store = false
}

# Politique cert-manager-services : politiques/cert-manager-services.hcl (vault_policy.acl du palier 1).

resource "vault_kubernetes_auth_backend_role" "cert_manager_services" {
  backend                          = vault_auth_backend.k8s_par1.path
  role_name                        = "cert-manager-services"
  bound_service_account_names      = ["openbao-emetteur"]
  bound_service_account_namespaces = ["cert-manager"]
  audience                         = "openbao.medisphere.internal"
  alias_name_source                = "serviceaccount_name"
  token_type                       = "service"
  token_ttl                        = 600
  token_max_ttl                    = 600
  token_policies                   = ["cert-manager-services"]
}
