# envs/m13 — environnement du module 13 : reg02, Harbor de test (M13-E13, PLAT-1413).
# Un état à part (« m13-registre ») : détruire reg02 en fin de module ne peut jamais toucher reg01
# (état « socle ») ni la configuration de Harbor (états « registre » et « registre-reg02 »).
# VMID 2131 (PLAN §4.6 : 2000 + 13*10 + 1).
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
    key                         = "envs/m13-registre/terraform.tfstate"
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
