# envs/m27 — environnement du module 27 : trois VMs Patroni jetables (M27-E13, PLAT-2813).
# Un état à part (« m27 ») : détruire l'essai ne peut jamais toucher le socle ni le cluster.
# VMID 2271-2273 (PLAN §4.6 et §4.13 : 2000 + 27*10 + n). Détruit en fin d'exercice ; l'état reste (vide).
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
    key                         = "envs/m27/terraform.tfstate"
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
