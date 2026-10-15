# envs/m18 — environnement du module 18 (distributions et cycle de vie), état distant sur s3-01.
# Un état à part (état « m18-distributions », PLAN.md §4.10) : détruire l'environnement ne peut
# toucher ni le socle ni k8s-par1. VMID 2181-2188 (VMs d'environnement) et 5191-5193 (bac à sable,
# k3s HA jetable, M18-E07). Les VMs 5180-5189 du cluster capi-essai ne sont PAS ici : CAPMOX les gère.

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
    # Noms DNS des nœuds Talos (adresses fixes, M18-E05) ; les autres VMs ont le DDNS de Kea.
    powerdns = {
      source  = "mmianl/powerdns"
      version = "~> 2.5.0"
    }
  }

  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "envs/m18/terraform.tfstate"
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
