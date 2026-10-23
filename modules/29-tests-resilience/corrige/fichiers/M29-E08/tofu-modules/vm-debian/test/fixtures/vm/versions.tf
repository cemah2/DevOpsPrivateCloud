# Fournisseurs de la configuration de test (M29-E08) : mêmes contraintes que les racines de
# plateforme/infra (M05-E31, M06-E13). Pas de backend : état local, propre à chaque lancement.
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
  }
}

# Proxmox : PROXMOX_VE_ENDPOINT et PROXMOX_VE_API_TOKEN (identité wb-terratest@pve!terratest,
# ~/.config/workbook/pve-terratest.env ; variables protégées en CI). TLS vérifié.
provider "proxmox" {
  insecure = false
}

provider "netbox" {
  server_url           = var.netbox_url
  api_token            = var.netbox_api_token
  allow_insecure_https = false
}
