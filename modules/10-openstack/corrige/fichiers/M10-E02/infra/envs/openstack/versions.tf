# envs/openstack — nœuds OpenStack du module 10 (VMs 2101-2103), état distant sur s3-01.
# Un état PAR ENVIRONNEMENT (PLAN §4.9) : détruire le cloud ne peut pas toucher au socle.
# Fournisseurs : ceux de vm-debian v2.2 (proxmox, netbox) et d'enregistrement-dns (powerdns).

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

  # Même backend que les autres états (M05-E11, E12) ; une clé par environnement.
  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "envs/openstack/terraform.tfstate"
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
