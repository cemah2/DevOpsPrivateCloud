# providers.tf — accès à pve01 (M05-E03, bloc ssh ajouté en M05-E19).
#
# L'API (PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN de pve-tofu.env) suffit pour les VMs.
# Les snippets, eux, s'écrivent par SSH : compte Linux wb-tofu de pve01, clé de admin@adm01
# présentée par l'agent SSH (jamais de clé privée dans le code ni dans une variable).
# Conséquence : envs/lab-m05 ne s'applique que depuis adm01 (runner01 n'a pas de flux SSH
# vers pve01). Le socle, lui, n'utilise aucun snippet et reste applicable par la CI.
provider "proxmox" {
  insecure = false

  ssh {
    agent    = true
    username = "wb-tofu"

    # Adresse SSH de pve01 donnée explicitement : sinon le provider la cherche par l'API
    # (interfaces réseau du nœud, droit Sys.Audit que le jeton n'a pas).
    node {
      name    = var.noeud
      address = var.pve01_ssh
    }
  }
}

variable "pve01_ssh" {
  description = "Adresse de pve01 pour SSH (<IP-PVE01>), joignable depuis adm01."
  type        = string
}
