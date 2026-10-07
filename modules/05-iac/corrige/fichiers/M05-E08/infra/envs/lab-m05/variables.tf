# variables.tf — entrées de l'environnement lab-m05 (M05-E06).
#
# Règle de l'équipe : une variable a un type, une description, et une validation dès
# qu'une mauvaise valeur peut toucher autre chose que l'environnement lui-même.
# Les valeurs du lab sont dans terraform.tfvars (versionné : rien de secret) ; les secrets
# n'entrent JAMAIS par une variable : ils viennent de l'environnement (PROXMOX_VE_*).

variable "noeud" {
  description = "Nom du nœud Proxmox qui héberge les VMs (<NOEUD> : hostname de pve01)."
  type        = string
  nullable    = false
}

variable "pool" {
  description = "Pool Proxmox des VMs. Toutes les VMs du workbook vivent dans le pool lab."
  type        = string
  default     = "lab"

  validation {
    condition     = var.pool == "lab"
    error_message = "Les VMs du workbook vont dans le pool « lab » (PLAN §3.1), et nulle part ailleurs."
  }
}

variable "stockage_vm" {
  description = "Stockage Proxmox des disques et du lecteur cloud-init."
  type        = string
  default     = "local-nvme"
}

variable "vnet" {
  description = "VNet des VMs d'environnement (VLAN 99, DHCP)."
  type        = string
  default     = "vsandbox"

  validation {
    condition     = var.vnet == "vsandbox"
    error_message = "Les VMs d'environnement d'un module sont sur le VNet vsandbox (PLAN §4.8)."
  }
}

variable "environnement" {
  description = "Environnement de module (m05) : donne l'étiquette env-<environnement>."
  type        = string
  default     = "m05"

  validation {
    condition     = can(regex("^m[0-9]{2}$", var.environnement))
    error_message = "L'environnement s'écrit mNN (ex. m05)."
  }
}

variable "etiquettes_supplementaires" {
  description = "Étiquettes Proxmox ajoutées à env-<environnement> (minuscules, chiffres, - et _)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.etiquettes_supplementaires : can(regex("^[a-z0-9][a-z0-9_-]*$", e))])
    error_message = "Une étiquette Proxmox s'écrit en minuscules, chiffres, « - » et « _ »."
  }
  validation {
    # Ces étiquettes ont un sens pour l'inventaire Ansible (M04) et les sources de données
    # (M05-E08) : une VM jetable qui les porterait entrerait dans le socle ou deviendrait « l'image ».
    condition     = length(setintersection(var.etiquettes_supplementaires, ["socle", "gold", "current", "base"])) == 0 && alltrue([for e in var.etiquettes_supplementaires : !startswith(e, "role-")])
    error_message = "Étiquettes réservées interdites sur une VM d'environnement : socle, role-*, gold, current, base."
  }
}

variable "cles_ssh_admin" {
  description = "Clés SSH PUBLIQUES autorisées pour le compte admin (cloud-init)."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.cles_ssh_admin) > 0
    error_message = "Au moins une clé : sans clé, la VM est injoignable (pas de mot de passe)."
  }
  validation {
    condition     = alltrue([for k in var.cles_ssh_admin : can(regex("^(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) AAAA", k))])
    error_message = "Chaque élément doit être une clé publique OpenSSH sur une ligne (« ssh-ed25519 AAAA… commentaire »)."
  }
}

variable "vm_essai" {
  description = "La VM d'essai du module : VMID, nom, et ressources (valeurs par défaut raisonnables)."
  type = object({
    vmid       = number
    nom        = string
    coeurs     = optional(number, 2)
    memoire_mo = optional(number, 2048)
    disque_go  = optional(number, 10)
  })

  validation {
    condition     = var.vm_essai.vmid >= 2050 && var.vm_essai.vmid <= 2059
    error_message = "Les VMs d'environnement du module 05 ont un VMID entre 2050 et 2059 (PLAN §4.6)."
  }
  validation {
    condition     = can(regex("^m05-[a-z0-9]([a-z0-9-]{0,18}[a-z0-9])?$", var.vm_essai.nom))
    error_message = "Le nom commence par m05-, en minuscules, chiffres et tirets (c'est aussi le nom d'hôte)."
  }
  validation {
    condition     = var.vm_essai.coeurs >= 1 && var.vm_essai.coeurs <= 4
    error_message = "Entre 1 et 4 vCPU pour une VM d'environnement."
  }
  validation {
    condition     = var.vm_essai.memoire_mo >= 512 && var.vm_essai.memoire_mo <= 8192 && var.vm_essai.memoire_mo % 256 == 0
    error_message = "Mémoire entre 512 et 8192 Mo, par multiples de 256 Mo."
  }
  validation {
    # Le disque de l'image dorée fait 8 Go et Proxmox ne réduit jamais un disque.
    condition     = var.vm_essai.disque_go >= 10 && var.vm_essai.disque_go <= 100
    error_message = "Disque système entre 10 et 100 Go."
  }
}

variable "vms_app" {
  description = "Serveurs d'application de test de MédiAgenda (DEV-607) : clé courte (appNN) => VMID, ressources, disques de données (Go)."
  type = map(object({
    vmid            = number
    coeurs          = optional(number, 2)
    memoire_mo      = optional(number, 1024)
    disques_donnees = optional(list(number), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.vms_app) : can(regex("^app[0-9]{2}$", k))])
    error_message = "Les clés de vms_app s'écrivent appNN (app01, app02…) : elles donnent le nom m05-appNN."
  }
  validation {
    condition     = alltrue([for v in values(var.vms_app) : v.vmid >= 2050 && v.vmid <= 2059])
    error_message = "Les VMs d'environnement du module 05 ont un VMID entre 2050 et 2059."
  }
  validation {
    # Deux VMs avec le même VMID : la seconde création échouerait… ou pire, l'import d'une
    # VM existante. Mieux vaut le refuser dès le plan.
    condition     = length(distinct([for v in values(var.vms_app) : v.vmid])) == length(var.vms_app) && !contains([for v in values(var.vms_app) : v.vmid], var.vm_essai.vmid)
    error_message = "Chaque VM a son propre VMID, différent de celui de la VM d'essai."
  }
  validation {
    condition     = alltrue([for v in values(var.vms_app) : length(v.disques_donnees) <= 3 && alltrue([for t in v.disques_donnees : t >= 1 && t <= 20])])
    error_message = "Au plus 3 disques de données par VM, de 1 à 20 Go chacun."
  }
}
