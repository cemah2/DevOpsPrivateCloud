# ~/m05/e15/espaces/main.tf — ESSAI des espaces de travail (workspaces) (M05-E15).
# Brouillon hors dépôt : une seule configuration, un état par espace de travail.
#   tofu workspace new recette ; tofu apply ; tofu workspace new dev ; tofu apply
# Ce qui varie d'un espace à l'autre doit être CALCULÉ à partir de terraform.workspace :
# c'est la limite de l'approche (même code, mêmes accès, mêmes versions pour tous).
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.115.0"
    }
  }

  backend "s3" {
    bucket = "tofu-state"
    # Avec des espaces de travail, l'état de l'espace X est rangé sous
    # <workspace_key_prefix>/X/<key> : ici env:/recette/essais/e15/terraform.tfstate.
    # L'espace « default » garde la clé telle quelle.
    key                         = "essais/e15/terraform.tfstate"
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

provider "proxmox" {}

variable "noeud" {
  type = string
}

variable "cles_ssh_admin" {
  type = list(string)
}

locals {
  # Un VMID par espace : une erreur de sélection d'espace vise une autre VM. Dans l'espace
  # « default », l'index échoue (« Invalid index ») : garde-fou rudimentaire, mais voulu.
  vmids = {
    recette = 2055
    dev     = 2056
  }
}

module "vm" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v1.1.0"

  nom            = "m05-ws-${terraform.workspace}"
  vm_id          = local.vmids[terraform.workspace]
  noeud          = var.noeud
  environnement  = "m05"
  memoire_mo     = 1024
  reseau         = { vnet = "vsandbox" }
  cles_ssh       = var.cles_ssh_admin
  demarrage_auto = false
  arret_force    = true
}

output "espace" {
  value = "${terraform.workspace} → VM ${module.vm.vm_id} (${module.vm.nom})"
}
