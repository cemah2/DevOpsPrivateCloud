# exemples/minimal — appel minimal du module (M05-E13). Sert de documentation et de test
# de validation (« tofu validate » dans la CI de tofu-modules). Ne s'applique pas tel quel.
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.115.0"
    }
  }
}

provider "proxmox" {}

module "essai" {
  source = "../.."

  nom           = "m05-essai"
  vm_id         = 2059
  noeud         = "pve01"
  environnement = "m05"
  reseau        = { vnet = "vsandbox" }
  cles_ssh      = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExempleExempleExempleExempleExemple00000 admin@adm01"]
}
