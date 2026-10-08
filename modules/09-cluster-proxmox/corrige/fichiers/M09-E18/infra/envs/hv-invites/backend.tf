# backend.tf — état distant de l'environnement hv-invites (M09-E18).
#
# Même compartiment que les autres états, clé propre : verrou et rayon d'impact indépendants.
# Identifiants S3 par l'environnement (~/.config/workbook/s3-tofu.env, variables CI du projet).
terraform {
  backend "s3" {
    bucket = "tofu-state"
    key    = "envs/hv-invites/terraform.tfstate"

    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-01.par1.medisphere.internal:8333" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    use_lockfile = true
  }
}
