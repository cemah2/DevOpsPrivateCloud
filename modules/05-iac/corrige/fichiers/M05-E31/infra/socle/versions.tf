# versions.tf — état « socle » de plateforme/infra (M05-E10, backend M05-E11, provider 0.116 en M05-E31).
#
# Montée de version du provider (CHG-671) : contrainte « ~> 0.116.0 » = correctifs 0.116.x
# acceptés, jamais une 0.117 sans MR (le provider est en 0.x : une mineure peut casser).
# La version exacte et ses empreintes sont dans .terraform.lock.hcl, mis à jour dans la même MR
# par « tofu init -upgrade » puis « tofu providers lock -platform=linux_amd64 ».
# Même changement, dans la même MR : envs/lab-m05/versions.tf, envs/recette-m05/versions.tf,
# terragrunt/composants/vms/versions.tf (et les .terraform.lock.hcl des unités Terragrunt).
# Le module vm-debian n'a pas à changer : sa contrainte (>= 0.115.0, < 1.0.0) admet 0.116.
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0"
    }
  }

  # État distant sur s3-01 (SeaweedFS), inchangé depuis M05-E11.
  backend "s3" {
    bucket = "tofu-state"
    key    = "socle/terraform.tfstate"

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
