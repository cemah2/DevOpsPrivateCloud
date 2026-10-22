# tofu/fournisseurs.tf — royaume medisphere de Keycloak en code (M24-E08, PLAT-2508).
#
# Fournisseur keycloak/keycloak : la suite officielle de l'ancien mrparkers/keycloak (plus publié
# sous ce nom). Correctifs acceptés, jamais une nouvelle mineure sans MR (montée de version
# délibérée, comme pour bpg/proxmox au M05-E31). Empreintes exactes dans .terraform.lock.hcl.
# OpenTofu ≥ 1.11 : arguments en écriture seule (bind_credential_wo) et variables éphémères.
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.10"
    }
  }

  # État distant sur s3-01, comme plateforme/infra (M05-E11). L'état CONTIENT des secrets (secrets
  # des clients confidentiels, lus par le fournisseur) : il est chiffré côté client (chiffrement.tf)
  # et le compartiment n'est lisible que par l'identité S3 tofu-etat.
  backend "s3" {
    bucket = "tofu-state"
    key    = "identite/terraform.tfstate"

    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-01.par1.medisphere.internal:8333" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_lockfile                = true
  }
}

# Authentification : client svc-tofu-keycloak du royaume MASTER (compte de service,
# client_credentials). Identifiants par l'environnement, jamais dans le code :
#   KEYCLOAK_CLIENT_ID, KEYCLOAK_CLIENT_SECRET  (~/.config/workbook/keycloak-tofu.env sur adm01,
#                                                variables protégées et masquées en CI)
# Droits : tous les rôles du client « medisphere-realm » de master sauf impersonation, c'est-à-dire
# administrateur du seul royaume medisphere (ni master, ni création de royaume).
# Le certificat de sso est vérifié avec le magasin système (racine MédiSphère installée sur adm01
# et runner01) : jamais tls_insecure_skip_verify.
provider "keycloak" {
  url   = "https://sso.par1.medisphere.internal"
  realm = "master"
}
