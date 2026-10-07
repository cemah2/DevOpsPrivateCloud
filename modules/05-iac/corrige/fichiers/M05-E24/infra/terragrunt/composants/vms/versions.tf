# versions.tf — composant « vms » (M05-E24).
# Ni backend ni provider ici : Terragrunt génère backend.tf (live/root.hcl) et
# provider-proxmox.tf (live/_commun/proxmox.hcl).
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.115.0"
    }
  }
}
