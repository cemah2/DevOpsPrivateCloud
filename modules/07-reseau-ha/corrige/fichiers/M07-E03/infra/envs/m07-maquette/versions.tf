# envs/m07-maquette — maquette réseau du module 07 (VMs 2070-2079), état distant sur s3-01.
# Trois fournisseurs : proxmox (les VMs), netbox (réservations d'adresses), powerdns (noms des
# adresses fixes). Mêmes contraintes que les autres configurations racine depuis M05-E31.

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

  # Même compartiment que les autres états, clé propre à la maquette : son verrou et son
  # rayon d'impact sont indépendants de ceux du socle (M05-E15).
  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "envs/m07-maquette/terraform.tfstate"
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
