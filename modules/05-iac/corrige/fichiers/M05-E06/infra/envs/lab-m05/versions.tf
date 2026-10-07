# versions.tf — versions d'OpenTofu et du provider Proxmox (M05-E03).
#
# Contraintes « pessimistes » (~>) : on accepte les correctifs, jamais une nouvelle
# version mineure sans MR. Le provider bpg/proxmox est en 0.x : chaque mineure peut
# casser la compatibilité (voir son CHANGELOG, sections « BREAKING CHANGES »).
# La version exacte retenue et ses empreintes sont dans .terraform.lock.hcl (versionné).
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox" # = registry.opentofu.org/bpg/proxmox
      version = "~> 0.115.0"
    }
  }
}
