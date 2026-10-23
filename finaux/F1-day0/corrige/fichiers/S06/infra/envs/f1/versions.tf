# envs/f1 — VMs jetables du final F1 (VMID 3100-3199, PLAN §4.6 et §4.14), état distant sur s3-01.
# F1-S06 : la machine d'essai de l'usine, 3101 « f1-usine-essai ». L'état reste, vide, à la fin.
# Fournisseurs : proxmox (la VM), netbox (l'intention lue par l'usine), powerdns (le nom).

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0"
    }
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.8.0"
    }
    powerdns = {
      source  = "mmianl/powerdns"
      version = "~> 2.5.0"
    }
  }

  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "envs/f1/terraform.tfstate"
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
