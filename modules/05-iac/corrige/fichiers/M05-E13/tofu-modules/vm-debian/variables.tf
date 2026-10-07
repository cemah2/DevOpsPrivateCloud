# variables.tf — contrat d'entrée du module vm-debian (M05-E13).
# Chaque variable a une description (reprise par terraform-docs) et, si possible, une
# validation : une erreur doit sortir au plan, pas au milieu d'un apply.

# --- Identité --------------------------------------------------------------------------
variable "nom" {
  description = "Nom de la VM et nom d'hôte (court, sans domaine), ex. s3-01."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.nom))
    error_message = "nom : minuscules, chiffres et tirets, 2 à 32 caractères, commence par une lettre (PLAN.md §4.4)."
  }
}

variable "vm_id" {
  description = "VMID Proxmox, dans une plage du PLAN : 1000-1099 (socle), 2000-2999 (environnements), 5000-5999 (sandbox)."
  type        = number

  validation {
    condition = (
      (var.vm_id >= 1000 && var.vm_id <= 1099) ||
      (var.vm_id >= 2000 && var.vm_id <= 2999) ||
      (var.vm_id >= 5000 && var.vm_id <= 5999)
    )
    error_message = "vm_id hors des plages du PLAN (1000-1099, 2000-2999, 5000-5999). Les templates 9000-9099 ne se créent pas avec ce module."
  }
}

variable "noeud" {
  description = "Nom du nœud Proxmox qui héberge la VM."
  type        = string
}

variable "pool" {
  description = "Pool Proxmox de la VM."
  type        = string
  default     = "lab"
}

variable "description" {
  description = "Description affichée dans Proxmox (Notes). Une mention « gérée par OpenTofu » est ajoutée."
  type        = string
  default     = ""
}

# --- Étiquettes ------------------------------------------------------------------------
variable "socle" {
  description = "VM permanente du socle : ajoute l'étiquette « socle » (inventaire Ansible)."
  type        = bool
  default     = false
}

variable "role" {
  description = "Rôle de la VM (ajoute l'étiquette role-<role>, groupe Ansible role_<role>), ex. s3. null si aucun."
  type        = string
  default     = null

  validation {
    condition     = var.role == null || can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.role))
    error_message = "role : minuscules, chiffres et tirets (ex. s3, gitlab)."
  }
}

variable "environnement" {
  description = "Environnement d'exercice (ajoute l'étiquette env-<environnement>), ex. m05. null pour le socle."
  type        = string
  default     = null

  validation {
    condition     = var.environnement == null || can(regex("^[a-z0-9]+$", var.environnement))
    error_message = "environnement : minuscules et chiffres seulement (ex. m05)."
  }
}

variable "etiquettes" {
  description = "Étiquettes Proxmox supplémentaires."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.etiquettes : can(regex("^[a-z0-9][a-z0-9_-]*$", e))])
    error_message = "Étiquettes : minuscules, chiffres, tirets et soulignés seulement."
  }
}

# --- Image source ---------------------------------------------------------------------------
variable "image" {
  description = <<-EOT
    Image source. Par défaut, le template doré courant de la famille (étiquettes gold +
    <famille> + current, M03). Fixer vm_id pour cloner un template précis (essai d'une
    image candidate, reconstruction à l'identique).
  EOT
  type = object({
    famille = optional(string, "debian13")
    vm_id   = optional(number)
  })
  default = {}
}

# --- Ressources ------------------------------------------------------------------------
variable "coeurs" {
  description = "Nombre de vCPU."
  type        = number
  default     = 2

  validation {
    condition     = var.coeurs >= 1 && var.coeurs <= 8
    error_message = "coeurs : de 1 à 8 (pve01 a 8 cœurs physiques)."
  }
}

variable "memoire_mo" {
  description = "Mémoire en Mo."
  type        = number
  default     = 2048

  validation {
    condition     = var.memoire_mo >= 512 && var.memoire_mo % 256 == 0
    error_message = "memoire_mo : au moins 512, multiple de 256."
  }
}

variable "type_cpu" {
  description = "Type de CPU émulé. Celui de l'image dorée Debian (M03) ; Rocky 10 exige x86-64-v3 ou host."
  type        = string
  default     = "x86-64-v2-AES"
}

variable "datastore_systeme" {
  description = "Stockage du disque système et du lecteur cloud-init."
  type        = string
  default     = "local-nvme"
}

variable "disque_systeme_go" {
  description = "Taille du disque système en Go (au moins celle de l'image : un disque ne rétrécit pas)."
  type        = number
  default     = 20

  validation {
    condition     = var.disque_systeme_go >= 8
    error_message = "disque_systeme_go : au moins 8 (taille de l'image dorée)."
  }
}

variable "disque_systeme_ssd" {
  description = "Présenter le disque système comme un SSD à l'invité (TRIM) : vrai sur local-nvme, comme l'image."
  type        = bool
  default     = true
}

variable "disques_donnees" {
  description = "Disques de données supplémentaires, branchés sur scsi1, scsi2… dans l'ordre de la liste."
  type = list(object({
    taille_go  = number
    datastore  = optional(string, "hdd-bulk")
    format     = optional(string, "qcow2")
    ssd        = optional(bool, false)
    sauvegarde = optional(bool, true)
  }))
  default = []

  validation {
    condition     = length(var.disques_donnees) <= 6 && alltrue([for d in var.disques_donnees : d.taille_go >= 1 && contains(["qcow2", "raw"], d.format)])
    error_message = "disques_donnees : 6 disques au plus, taille >= 1 Go, format qcow2 ou raw."
  }
}

# --- Réseau et cloud-init ------------------------------------------------------------------
variable "reseau" {
  description = "Carte réseau : VNet SDN, adresse IPv4 en notation CIDR (ou « dhcp ») et passerelle (obligatoire en statique)."
  type = object({
    vnet       = string
    ipv4       = optional(string, "dhcp")
    passerelle = optional(string)
  })

  validation {
    condition     = var.reseau.ipv4 == "dhcp" || (can(cidrhost(var.reseau.ipv4, 0)) && strcontains(var.reseau.ipv4, "/"))
    error_message = "reseau.ipv4 : « dhcp » ou une adresse avec masque, ex. 10.10.20.14/24."
  }

  validation {
    condition     = var.reseau.ipv4 == "dhcp" || var.reseau.passerelle != null
    error_message = "reseau.passerelle est obligatoire avec une adresse statique (PLAN.md §4.2 : .1 du VLAN)."
  }
}

variable "dns" {
  description = "Résolveurs et domaine de recherche poussés par cloud-init."
  type = object({
    serveurs = list(string)
    domaine  = string
  })
  default = {
    serveurs = ["10.10.20.10"]
    domaine  = "par1.medisphere.internal"
  }
}

variable "utilisateur" {
  description = "Compte créé par cloud-init (sudo sans mot de passe dans l'image dorée)."
  type        = string
  default     = "admin"
}

variable "cles_ssh" {
  description = "Clés SSH PUBLIQUES du compte. Ignorées si user_data_file_id est fourni (le snippet crée alors les comptes)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.cles_ssh : can(regex("^ssh-(ed25519|rsa) ", c))])
    error_message = "cles_ssh : clés publiques OpenSSH (ssh-ed25519 … ou ssh-rsa …)."
  }
}

variable "user_data_file_id" {
  description = "Snippet cloud-init user-data (ex. hdd-bulk:snippets/x.yaml, M05-E19). Remplace utilisateur et cles_ssh. Le changer RECRÉE la VM."
  type        = string
  default     = null
}

variable "vendor_data_file_id" {
  description = "Snippet cloud-init vendor-data facultatif. Le changer RECRÉE la VM."
  type        = string
  default     = null
}

# --- Cycle de vie ----------------------------------------------------------------------
variable "demarrage_auto" {
  description = "Démarrer la VM avec l'hôte (onboot)."
  type        = bool
  default     = true
}

variable "ordre_demarrage" {
  description = <<-EOT
    Rang dans l'ordre de démarrage de Proxmox (null : non ordonné), posé à la CRÉATION seulement.
    Proxmox exige Sys.Modify sur « / » pour régler « startup » (réglage de l'hôte) : le jeton
    wb-tofu ne l'a pas, laisse null et pose le rang en root (qm set VMID --startup order=N).
    Les changements ultérieurs du rang sont ignorés par le module.
  EOT
  type        = number
  default     = null
}

variable "arret_force" {
  description = "À la destruction, couper la VM (stop) au lieu d'un arrêt propre (shutdown) : pour les VMs jetables."
  type        = bool
  default     = false
}

variable "protection" {
  description = "Drapeau « protection » de Proxmox : refuse la suppression de la VM et de ses disques, même par l'API. À true pour le socle."
  type        = bool
  default     = false
}

variable "proteger" {
  description = "Interdire à OpenTofu tout plan qui détruit ou remplace la VM (lifecycle.prevent_destroy, variable acceptée depuis OpenTofu 1.12). À true pour le socle, avec protection."
  type        = bool
  default     = false
  nullable    = false
}
