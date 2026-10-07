# rocky10-gold/variables.pkr.hcl — variables de l'image dorée Rocky Linux 10 (M03-E25).
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

# storage_iso et http_* : non utilisées par un build par clonage, déclarées pour que
# le fichier commun vars/lab.pkrvars.hcl ne produise pas d'avertissement.
variable "storage_iso" {
  type = string
}

variable "build_bridge" {
  type        = string
  description = "VNet sur lequel démarre la VM de construction (DHCP)"
}

variable "http_bind_address" {
  type    = string
  default = "10.10.10.10"
}

variable "http_port_min" {
  type = number
}

variable "http_port_max" {
  type = number
}

# --- Propres à l'image --------------------------------------------------------------
variable "base_vm_id" {
  type        = number
  default     = 9002
  description = "Template source cloné : tpl-rocky10-base"
}

variable "vm_id" {
  type        = number
  description = "VMID de la nouvelle version : premier libre de 9030-9049"

  # -force supprimerait la VM qui porte ce VMID : on refuse tout ce qui sort de la plage.
  validation {
    condition     = var.vm_id >= 9030 && var.vm_id <= 9049
    error_message = "Le VMID d'une image dorée Rocky Linux 10 doit être dans la plage 9030-9049."
  }
}

variable "version" {
  type        = string
  description = "Version de l'image, AAAAMMJJ-N (N : numéro du build du jour)"

  validation {
    condition     = can(regex("^20[0-9]{6}-[0-9]+$", var.version))
    error_message = "La version doit avoir la forme AAAAMMJJ-N, par exemple 20261007-1."
  }
}

variable "git_commit" {
  type    = string
  default = "inconnu"
}

variable "plugin_version" {
  type    = string
  default = "inconnue"
}

variable "cpu_type" {
  type        = string
  default     = "x86-64-v3"
  description = "Rocky Linux 10 exige le niveau x86-64-v3 (AVX2…) : x86-64-v3, x86-64-v4 ou host"

  validation {
    condition     = contains(["x86-64-v3", "x86-64-v4", "host"], var.cpu_type)
    error_message = "Rocky Linux 10 exige au moins le niveau x86-64-v3 : utilise x86-64-v3, x86-64-v4 ou host."
  }
}
