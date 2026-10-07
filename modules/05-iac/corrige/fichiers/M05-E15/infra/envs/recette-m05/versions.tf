# versions.tf — environnement de recette de MédiAgenda (M05-E15).
# Un répertoire par environnement : son propre état (clé dédiée), son propre verrou, ses
# propres versions. Le code commun est dans les modules (vm-debian), pas copié ici.
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.115.0"
    }
  }

  backend "s3" {
    bucket = "tofu-state"
    key    = "envs/recette-m05/terraform.tfstate"

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
