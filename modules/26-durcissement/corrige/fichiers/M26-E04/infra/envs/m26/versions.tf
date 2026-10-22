# envs/m26 — environnement du module 26 (VMs d'essai du durcissement), état distant sur s3-01.
# Un état à part (M26-E04, SEC-2704) : détruire l'environnement ne peut jamais toucher une VM du
# socle. VMID 2260-2269 (PLAN §4.12) : 2261 durci-deb, 2262 durci-rocky. Même schéma que envs/m12.

terraform {
  required_version = ">= 1.13.0"

  required_providers {
    # Mêmes contraintes que les autres configurations racine (M05-E31, M12-E02).
    # Pas de fournisseur PowerDNS : les noms viennent du DDNS de Kea (cartes en DHCP sur vsandbox).
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
    key                         = "envs/m26/terraform.tfstate"
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
