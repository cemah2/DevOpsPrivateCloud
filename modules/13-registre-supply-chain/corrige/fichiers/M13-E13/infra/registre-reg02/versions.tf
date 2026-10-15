# registre-reg02 — objets du Harbor de TEST reg02 (M13-E13). Configuration racine distincte de
# « registre » (reg01) : autre instance, autres identifiants, détruite en M13-E25 avec la VM.
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "registre-reg02/terraform.tfstate"
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
