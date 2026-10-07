# versions.tf — module vm-debian (M05-E13).
#
# Un module déclare les providers dont il a besoin et une contrainte LARGE : c'est la
# configuration racine qui épingle (~> 0.115.0) et dont le .terraform.lock.hcl fixe la
# version. Un module trop strict empêcherait ses consommateurs de monter de version.
# Pas de bloc provider ici : il est hérité de la racine.
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.115.0, < 1.0.0"
    }
  }
}
