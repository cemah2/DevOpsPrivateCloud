# envs/f4-infoger — VMs migrées de l'export VMware d'InfoGér (F4-S10, CHG-3410).
# Un état à part (« envs/f4-infoger ») : ces VMs n'ont pas été créées par OpenTofu, elles y sont
# IMPORTÉES (imports.tf) ; détruire cet état ne doit jamais toucher le socle ni le cluster.
# VMID 3401-3403 (PLAN §4.6 et §4.14), adresses 10.10.20.44-46.
terraform {
  required_version = "~> 1.13.0"

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
    key                         = "envs/f4-infoger/terraform.tfstate"
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
