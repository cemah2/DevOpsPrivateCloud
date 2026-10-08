# versions.tf — état « hv » de plateforme/infra : nœuds du cluster Proxmox imbriqué hv-par1 (M09-E03).
#
# Une configuration racine par environnement de module (PLAN §4.9) : envs/hv/ a son propre
# état, son propre verrou ; un apply raté ici ne peut pas toucher le socle.
# Mêmes contraintes que les autres racines depuis M05-E31 (provider 0.116) et M06-E13/E14
# (NetBox, PowerDNS). Versions exactes et empreintes : .terraform.lock.hcl (versionné).
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
    key                         = "envs/hv/terraform.tfstate"
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
