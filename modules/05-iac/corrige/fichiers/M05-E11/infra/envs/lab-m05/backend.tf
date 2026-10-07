# backend.tf — état distant de l'environnement lab-m05 (M05-E11).
#
# Même compartiment que le socle, clé différente : deux états indépendants, deux verrous
# indépendants (rayon d'impact limité, M05-E15). Toute la configuration est répétée d'un
# répertoire à l'autre : c'est la duplication que Terragrunt supprimera en M05-E24.
terraform {
  backend "s3" {
    bucket = "tofu-state"
    key    = "envs/lab-m05/terraform.tfstate"

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
