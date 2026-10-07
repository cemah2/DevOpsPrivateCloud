# vm-debian v2 — entrées (M06-E13).
# Par rapport à v1 (M05-E13) : « ipv4 » et « passerelle » disparaissent (l'adresse vient de
# NetBox, la passerelle se déduit du préfixe) ; « reseau_prefixe », « plage_adresses » et
# « ipv4_imposee » apparaissent.

# --- Identité ---------------------------------------------------------------------------------
variable "nom" {
  description = "Nom court de la VM (nom Proxmox, nom NetBox, nom d'hôte), PLAN.md §4.4."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.nom))
    error_message = "Nom en minuscules, chiffres et tirets (ex. dns02, m06-ipam01)."
  }
}

variable "vmid" {
  description = "VMID Proxmox (socle 1000-1099, environnements 2000-2999, PLAN.md §4.6)."
  type        = number
  validation {
    condition     = (var.vmid >= 1000 && var.vmid <= 1099) || (var.vmid >= 2000 && var.vmid <= 2999)
    error_message = "VMID hors des plages du lab (1000-1099 ou 2000-2999)."
  }
}

variable "domaine" {
  description = "Domaine DNS de l'hôte (dns_name de l'adresse dans NetBox)."
  type        = string
  default     = "par1.medisphere.internal"
}

variable "etiquettes" {
  description = "Étiquettes Proxmox ET NetBox (socle, role-…, env-mNN). Elles doivent exister dans NetBox."
  type        = list(string)
}

variable "description" {
  description = "Note de la VM dans Proxmox et commentaire dans NetBox."
  type        = string
  default     = "Créée par OpenTofu (module vm-debian)."
}

# --- Proxmox ------------------------------------------------------------------------------------
variable "noeud" {
  description = "Nœud Proxmox (<NOEUD>)."
  type        = string
}

variable "pool" {
  description = "Pool Proxmox."
  type        = string
  default     = "lab"
}

variable "vnet" {
  description = "VNet SDN de la carte réseau (vinfra, vsandbox…)."
  type        = string
}

variable "stockage" {
  description = "Stockage du disque système et du lecteur cloud-init."
  type        = string
  default     = "local-nvme"
}

variable "coeurs" {
  description = "vCPU."
  type        = number
  default     = 1
}

variable "memoire_mo" {
  description = "Mémoire en Mio."
  type        = number
  default     = 1024
}

variable "disque_go" {
  description = "Taille du disque système en Gio (au moins celle de l'image dorée)."
  type        = number
  default     = 10
}

variable "demarrage_auto" {
  description = "Démarrer la VM avec l'hyperviseur (onboot)."
  type        = bool
  default     = true
}

variable "ordre_demarrage" {
  description = "Ordre de démarrage Proxmox (null = aucun)."
  type        = number
  default     = null
}

variable "cle_ssh_admin" {
  description = "Clé publique SSH injectée pour le compte admin par cloud-init."
  type        = string
}

variable "resolveurs" {
  description = "Résolveurs DNS écrits par cloud-init."
  type        = list(string)
  default     = ["10.10.20.10"]
}

# --- NetBox (IPAM) ------------------------------------------------------------------------------
variable "netbox_cluster" {
  description = "Cluster de virtualisation NetBox de la VM (modélisation M06-E05)."
  type        = string
  default     = "pve01"
}

variable "reseau_prefixe" {
  description = "Préfixe NetBox du VLAN de la VM (ex. 10.10.99.0/24) : donne le masque et la passerelle (.1)."
  type        = string
  validation {
    condition     = can(cidrhost(var.reseau_prefixe, 1))
    error_message = "Préfixe IPv4 au format CIDR attendu (ex. 10.10.99.0/24)."
  }
}

variable "plage_adresses" {
  description = <<-EOT
    Une adresse CONTENUE dans la plage NetBox où allouer (ex. 10.10.99.10 pour la plage
    « statique » .10-.49). Ignorée si ipv4_imposee est renseignée.
  EOT
  type        = string
  default     = null
}

variable "ipv4_imposee" {
  description = <<-EOT
    Adresse fixée par PLAN.md §4.5 (hôtes du socle, ex. 10.10.20.16 pour dns02) : enregistrée
    telle quelle dans NetBox au lieu d'être allouée. null = allocation dans plage_adresses.
  EOT
  type        = string
  default     = null
  validation {
    condition     = var.ipv4_imposee == null || can(cidrhost("${coalesce(var.ipv4_imposee, "0.0.0.0")}/32", 0))
    error_message = "Adresse IPv4 sans masque attendue (ex. 10.10.20.16)."
  }
}
