# debian13-base/variables.pkr.hcl — variables de l'image de base Debian 13 (M03-E05, version M03-E08).
# Trois familles de variables :
#   - accès à Proxmox : fournies par l'environnement (PKR_VAR_*, fichier
#     ~/.config/workbook/pve-packer.env sur adm01, variables CI protégées en M03-E15) ;
#   - environnement du lab, non secrètes : ../vars/lab.pkrvars.hcl (versionné) ;
#   - propres à l'image : valeurs par défaut ci-dessous.

# --- Accès à Proxmox (jamais dans le dépôt) -----------------------------------------
variable "proxmox_url" {
  type        = string
  description = "URL de l'API, ex. https://<IP-PVE01>:8006/api2/json"

  validation {
    condition     = can(regex("^https://[^/]+:8006/api2/json$", var.proxmox_url))
    error_message = "Attendu : https://<hôte>:8006/api2/json (HTTPS obligatoire)."
  }
}

variable "proxmox_username" {
  type        = string
  description = "Identifiant du jeton : wb-packer@pve!packer"

  validation {
    condition     = can(regex("^[^@!]+@[^@!]+![A-Za-z0-9_-]+$", var.proxmox_username))
    error_message = "Attendu : utilisateur@domaine!jeton (ex. wb-packer@pve!packer)."
  }
}

variable "proxmox_token" {
  type        = string
  sensitive   = true
  description = "Secret du jeton wb-packer@pve!packer"
}

variable "proxmox_node" {
  type        = string
  description = "Nom du nœud Proxmox (<NOEUD>)"
}

# --- Environnement du lab (vars/lab.pkrvars.hcl) -------------------------------------
variable "pool" {
  type = string
}

variable "storage_vm" {
  type        = string
  description = "Stockage des disques et du lecteur cloud-init"
}

variable "storage_iso" {
  type        = string
  description = "Stockage qui contient les ISO déposées (contenu iso)"
}

variable "build_bridge" {
  type        = string
  description = "VNet sur lequel démarre la VM de construction (DHCP)"
}

variable "http_bind_address" {
  type        = string
  default     = "10.10.10.10"
  description = "Adresse de la machine de build qui sert le preseed (adm01 ; runner01 en CI)"
}

variable "http_port_min" {
  type = number
}

variable "http_port_max" {
  type = number
}

# --- Propres à l'image --------------------------------------------------------------
variable "vm_id" {
  type    = number
  default = 9001

  # -force supprime la VM qui porte ce VMID avant le build : on refuse tout VMID
  # hors de la plage des templates (PLAN.md §4.6).
  validation {
    condition     = var.vm_id >= 9001 && var.vm_id <= 9099
    error_message = "Le VMID doit être dans la plage des templates construits (9001-9099)."
  }
}

variable "iso_name" {
  type        = string
  default     = "debian-13.7.0-amd64-netinst.iso"
  description = "Nom de l'ISO déposée et vérifiée sur storage_iso (outils/deposer-iso.sh)"
}

variable "iso_sha256" {
  type        = string
  default     = "a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355"
  description = "SHA-256 de l'ISO, recopiée du SHA256SUMS signé (sert au manifeste)"
}

variable "git_commit" {
  type        = string
  default     = "inconnu"
  description = "Commit du projet plateforme/images construit (passé par outils/construire.sh)"
}

variable "plugin_version" {
  type        = string
  default     = "inconnue"
  description = "Version du plugin proxmox utilisée (passée par outils/construire.sh)"
}

# Plus de variable build_password (M03-E05) : le mot de passe jetable est généré par
# Packer à chaque build (local sensible « build_password », build.pkr.hcl).
