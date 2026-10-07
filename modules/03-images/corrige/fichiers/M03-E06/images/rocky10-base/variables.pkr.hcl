# rocky10-base/variables.pkr.hcl — variables de l'image de base Rocky Linux 10 (M03-E06).
# Trois familles de variables :
#   - accès à Proxmox : fournies par l'environnement (PKR_VAR_*, fichier
#     ~/.config/workbook/pve-packer.env sur adm01, variables CI protégées en M03-E15) ;
#   - environnement du lab, non secrètes : ../vars/lab.pkrvars.hcl (versionné) ;
#   - propres à l'image : valeurs par défaut ci-dessous.

# --- Accès à Proxmox (jamais dans le dépôt) -----------------------------------------
variable "proxmox_url" {
  type        = string
  description = "URL de l'API, ex. https://<IP-PVE01>:8006/api2/json"
}

variable "proxmox_username" {
  type        = string
  description = "Identifiant du jeton : wb-packer@pve!packer"
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
  description = "Adresse de la machine de build qui sert le kickstart (adm01 ; runner01 en CI)"
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
  default = 9002
}

variable "iso_name" {
  type        = string
  default     = "Rocky-10.2-x86_64-boot.iso"
  description = "Nom de l'ISO déposée et vérifiée sur storage_iso (outils/deposer-iso.sh)"
}

variable "iso_sha256" {
  type        = string
  default     = "bf3a75907948563d0c11f3d1b8546ee9216e18a3ea2dc0a67eb4c45452e210f9"
  description = "SHA-256 de l'ISO, recopiée du fichier CHECKSUM signé (sert au manifeste)"
}

variable "build_password" {
  type        = string
  sensitive   = true
  description = "Mot de passe jetable du compte de construction (généré avant chaque build)"
}

variable "cpu_type" {
  type        = string
  default     = "x86-64-v3"
  description = "Rocky Linux 10 exige le niveau x86-64-v3 (AVX2…) : x86-64-v3 ou host"

  validation {
    condition     = contains(["x86-64-v3", "x86-64-v4", "host"], var.cpu_type)
    error_message = "Rocky Linux 10 exige au moins le niveau x86-64-v3 : utilise x86-64-v3, x86-64-v4 ou host."
  }
}
