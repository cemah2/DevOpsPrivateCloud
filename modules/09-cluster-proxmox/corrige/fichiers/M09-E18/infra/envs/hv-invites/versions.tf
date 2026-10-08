# versions.tf — environnement hv-invites : VMs de recette sur le cluster imbriqué hv-par1 (M09-E18).
#
# Même version d'OpenTofu et même provider que le reste de plateforme/infra (M05-E31 : 0.116).
# La version exacte et ses empreintes sont dans .terraform.lock.hcl (versionné, créé par
# « tofu init » puis « tofu providers lock -platform=linux_amd64 »).
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0"
    }
  }
}
