# vm-debian v2.2 — entrées (M06-E13, étendu en M10-E02).
# Par rapport à v1 (M05-E13) : « ipv4 » et « passerelle » disparaissent (l'adresse vient de
# NetBox, la passerelle se déduit du préfixe) ; « reseau_prefixe », « plage_adresses » et
# « ipv4_imposee » apparaissent.
# v2.2.0 (M10-E02, ajout RÉTROCOMPATIBLE, donc version mineure) : « type_cpu », « mac_adresse »,
# « mtu » pour la carte principale, et « cartes_supplementaires ». Sans ces variables, le module
# produit exactement la même VM qu'en v2.1.

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

# --- v2.2.0 (M10-E02) : CPU, carte principale, cartes supplémentaires ----------------------------
variable "type_cpu" {
  description = "Type de CPU émulé. « host » pour un hyperviseur imbriqué (KVM dans la VM) ou Rocky 10."
  type        = string
  default     = "x86-64-v2-AES"
}

variable "mac_adresse" {
  description = "Adresse MAC de la carte principale (net0). null : Proxmox en tire une au hasard."
  type        = string
  default     = null
  validation {
    condition     = var.mac_adresse == null || can(regex("^([0-9a-f]{2}:){5}[0-9a-f]{2}$", lower(coalesce(var.mac_adresse, "00:00:00:00:00:00"))))
    error_message = "MAC au format aa:bb:cc:dd:ee:ff attendue."
  }
}

variable "mtu" {
  description = "MTU annoncée à l'invité sur la carte principale (cartes virtio seulement). null : celle du pont."
  type        = number
  default     = null
}

variable "cartes_supplementaires" {
  description = <<-EOT
    Cartes net1, net2… dans l'ordre de la liste. Chacune : VNet, nom de l'interface dans NetBox
    (ex. ens19), MAC et MTU facultatives, et soit une adresse IMPOSÉE (ipv4_imposee + prefixe, sans
    passerelle : la route par défaut reste sur la carte principale), soit aucune adresse.
    Les cartes SANS adresse doivent venir APRÈS toutes les cartes adressées : Proxmox associe
    ipconfigN à netN par leur numéro, et le module produit les blocs ip_config dans l'ordre des
    cartes adressées ; une carte sans adresse au milieu décalerait les suivantes.
  EOT
  type = list(object({
    vnet         = string
    interface    = string
    mac_adresse  = optional(string)
    mtu          = optional(number)
    ipv4_imposee = optional(string)
    prefixe      = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for c in var.cartes_supplementaires : (c.ipv4_imposee == null) == (c.prefixe == null)
    ])
    error_message = "Une carte supplémentaire adressée a ipv4_imposee ET prefixe ; une carte sans adresse n'a ni l'un ni l'autre."
  }

  validation {
    # Index de la dernière carte adressée < index de la première carte sans adresse.
    condition = (
      length([for c in var.cartes_supplementaires : c if c.ipv4_imposee == null]) == 0 ||
      length([for c in var.cartes_supplementaires : c if c.ipv4_imposee != null]) == 0 ||
      max([for i, c in var.cartes_supplementaires : i if c.ipv4_imposee != null]...) <
      min([for i, c in var.cartes_supplementaires : i if c.ipv4_imposee == null]...)
    )
    error_message = "Les cartes sans adresse doivent suivre toutes les cartes adressées (ordre des ipconfigN)."
  }

  validation {
    condition     = length(var.cartes_supplementaires) <= 7
    error_message = "Au plus 7 cartes supplémentaires (net1 à net7)."
  }
}

variable "interface_principale" {
  description = "Nom de la carte principale dans NetBox (eth0 : nom donné par cloud-init dans l'image dorée ; ens18 si un rôle renomme les cartes, M10-E02)."
  type        = string
  default     = "eth0"
}
