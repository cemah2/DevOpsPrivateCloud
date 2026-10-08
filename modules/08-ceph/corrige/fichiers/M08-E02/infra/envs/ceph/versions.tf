# envs/ceph — environnement du cluster ceph-par1 (M08), état distant sur s3-01.
# Un état à part (PLAN.md §4.9 « Projets GitLab du bloc B ») : détruire ou reconstruire le
# cluster ne peut jamais toucher une VM du socle. VMID 2080-2089 (PLAN.md §4.6).

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    # Mêmes contraintes que les autres configurations racine (M05-E31, M06-E13/E14).
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
    key                         = "envs/ceph/terraform.tfstate"
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
