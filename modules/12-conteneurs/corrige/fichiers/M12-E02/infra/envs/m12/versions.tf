# envs/m12 — environnement du module 12 (hôtes de conteneurs), état distant sur s3-01.
# Un état à part (état « m12-conteneurs », PLAN.md §4.10) : détruire l'environnement ne peut
# jamais toucher une VM du socle (runner02, lui, est dans l'état « socle »). VMID 2120-2129.

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    # Mêmes contraintes que les autres configurations racine (M05-E31, M06-E13/E14).
    # Pas de fournisseur PowerDNS : les noms viennent du DDNS de Kea (cartes en DHCP).
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0"
    }
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.8.0"
    }
  }

  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "envs/m12/terraform.tfstate"
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
