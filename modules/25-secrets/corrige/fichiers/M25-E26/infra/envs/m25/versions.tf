# envs/m25 — environnement du module 25 (secrets), état distant sur s3-01 (M25-E26, SEC-2626).
# Un état à part : détruire l'environnement ne touche ni le socle (vault01-03, kms01) ni k8s-par1.
# VMs (PLAN §4.12) : 2252 bao-restauration (restauration d'essai, E26), 2251 bao-essai (Vault 2.2,
# E30). JAMAIS les deux à la fois (variables.tf).
# Fin de module : groupes = [] (plus aucune VM).

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
    key                         = "envs/m25/terraform.tfstate"
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
