# acces-proxmox/versions.tf — racine OpenTofu des ACCÈS HUMAINS à pve01 (M24-E15, SEC-2515).
#
# Séparée de « socle » parce qu'elle n'a pas le même compte : le royaume OpenID et les ACL exigent
# Realm.Allocate et Permissions.Modify, que le jeton d'automatisation wb-tofu@pve!tofu n'a pas (et ne
# doit pas avoir : Permissions.Modify sur « / » vaut administrateur). Elle est appliquée DEPUIS adm01,
# avec un jeton TEMPORAIRE de root@pam (30 minutes, supprimé aussitôt), jamais par la CI.
# Même fournisseur et même contrainte que socle (M05-E31) ; état chiffré comme les autres (chiffrement.tf
# identique à celui de socle, M05-E27).
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0"
    }
  }

  backend "s3" {
    bucket = "tofu-state"
    key    = "acces-proxmox/terraform.tfstate"

    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-01.par1.medisphere.internal:8333" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true

    use_lockfile = true
  }
}

# PROXMOX_VE_ENDPOINT (pve-tofu.env, M05-E03) et PROXMOX_VE_API_TOKEN = le jeton TEMPORAIRE de
# root@pam, chargé à la main pour la session (read -rs, jamais en argument). TLS vérifié (ancre de
# pve01 installée sur adm01 au M03-E02).
provider "proxmox" {
  insecure = false
}
