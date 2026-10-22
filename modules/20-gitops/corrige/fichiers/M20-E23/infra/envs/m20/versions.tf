# envs/m20 — environnement du module 20 (GitOps), état distant sur s3-01.
# Un état à part (PLAN §4.11) : détruire l'environnement ne peut toucher ni le socle ni k8s-par1.
# VMID 2201 lyo-k3s01 (M20-E26, agence LYO1) et 2202 flux01 (M20-E23, comparaison avec Flux) ;
# vides en fin de module (mini-projet M20-E46 : « tofu apply » avec groupes = []).

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
    # Noms DNS des VMs à adresse fixe (pas de bail Kea, donc pas de DDNS).
    powerdns = {
      source  = "mmianl/powerdns"
      version = "~> 2.5.0"
    }
  }

  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "envs/m20/terraform.tfstate"
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
