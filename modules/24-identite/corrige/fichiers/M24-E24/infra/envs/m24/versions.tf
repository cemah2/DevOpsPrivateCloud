# envs/m24 — environnement du module 24 (identité), état distant sur s3-01 (M24-E24, PLAT-2524).
# Un état à part : détruire l'environnement ne touche ni le socle (idp01, ipa01) ni k8s-par1.
# VMs (PLAN §4.12) : 2241 idp02 (second nœud Keycloak d'essai, E24), 2242 idp-resto (restauration
# d'essai, E25, puis essai de montée de version, E33). JAMAIS les deux à la fois (variables.tf).
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
    key                         = "envs/m24/terraform.tfstate"
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
