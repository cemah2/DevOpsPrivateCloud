# vm-noeud — contrat d'entrée (M08-E02 ; complété en M10-E02 : MAC et carte sans adresse).
# Mêmes noms que vm-debian v2 (M06-E13) quand le sens est le même : nom, vmid, noeud, pool,
# etiquettes, description, coeurs, memoire_mo, disque_go, cle_ssh_admin, resolveurs, domaine,
# netbox_cluster. Nouveautés : famille, type_cpu, cartes, disques_donnees, protection.

# --- Identité ---------------------------------------------------------------------------------
variable "nom" {
  description = "Nom court de la VM (nom Proxmox, nom NetBox, nom d'hôte), PLAN.md §4.4."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.nom))
    error_message = "Nom en minuscules, chiffres et tirets (ex. ceph01, cephcli01)."
  }
}

variable "vmid" {
  description = "VMID Proxmox : environnements 2000-2999 (PLAN.md §4.6). Le socle garde vm-debian."
  type        = number
  validation {
    condition     = var.vmid >= 2000 && var.vmid <= 2999
    error_message = "VMID hors de la plage des environnements (2000-2999)."
  }
}

variable "domaine" {
  description = "Domaine DNS de l'hôte (dns_name de l'adresse principale dans NetBox)."
  type        = string
  default     = "par1.medisphere.internal"
}

variable "etiquettes" {
  description = "Étiquettes Proxmox ET NetBox (env-mNN, role-…). Elles doivent exister dans NetBox."
  type        = list(string)
  validation {
    condition     = alltrue([for e in var.etiquettes : can(regex("^[a-z0-9][a-z0-9-]*$", e))])
    error_message = "Étiquettes : minuscules, chiffres et tirets seulement."
  }
}

variable "description" {
  description = "Note de la VM dans Proxmox et commentaire dans NetBox."
  type        = string
  default     = "Créée par OpenTofu (module vm-noeud)."
}

# --- Image et matériel -----------------------------------------------------------------------
variable "famille" {
  description = "Famille de l'image dorée : template étiqueté gold + <famille> + current (M03)."
  type        = string
  default     = "rocky10"
  validation {
    condition     = contains(["debian13", "rocky10"], var.famille)
    error_message = "famille : debian13 ou rocky10 (catalogue d'images de M03)."
  }
}

variable "type_cpu" {
  description = <<-EOT
    Type de CPU émulé. null = celui de la famille : x86-64-v2-AES (debian13), x86-64-v3 (rocky10,
    niveau minimal de RHEL 10). « host » est possible si tous les nœuds Proxmox ont le même CPU.
  EOT
  type        = string
  default     = null
  validation {
    condition     = var.type_cpu == null || contains(["x86-64-v2-AES", "x86-64-v3", "x86-64-v4", "host"], coalesce(var.type_cpu, "host"))
    error_message = "type_cpu : x86-64-v2-AES, x86-64-v3, x86-64-v4 ou host."
  }
}

variable "noeud" {
  description = "Nœud Proxmox (<NOEUD>)."
  type        = string
}

variable "pool" {
  description = "Pool Proxmox."
  type        = string
  default     = "lab"
}

variable "stockage" {
  description = "Stockage du disque système et du lecteur cloud-init."
  type        = string
  default     = "local-nvme"
}

variable "coeurs" {
  description = "vCPU."
  type        = number
  default     = 2
  validation {
    condition     = var.coeurs >= 1 && var.coeurs <= 8
    error_message = "coeurs : de 1 à 8."
  }
}

variable "memoire_mo" {
  description = "Mémoire en Mio."
  type        = number
  default     = 2048
  validation {
    condition     = var.memoire_mo >= 1024 && var.memoire_mo % 256 == 0
    error_message = "memoire_mo : au moins 1024, multiple de 256."
  }
}

variable "disque_go" {
  description = "Taille du disque système en Gio (au moins celle de l'image dorée)."
  type        = number
  default     = 20
}

variable "disques_donnees" {
  description = <<-EOT
    Disques de données, branchés sur scsi1, scsi2… dans l'ordre de la liste.
    ssd = true : le disque est présenté comme non rotatif (rotation_rate=1) : c'est ce que lit
    Ceph pour la classe « ssd ». sauvegarde = false : exclu des sauvegardes PBS (disques d'OSD).
    serie : numéro de série vu par l'invité (/dev/disk/by-id/…), 20 caractères au plus.
  EOT
  type = list(object({
    taille_go  = number
    datastore  = string
    ssd        = optional(bool, false)
    sauvegarde = optional(bool, false)
    serie      = optional(string)
  }))
  default = []
  validation {
    condition = length(var.disques_donnees) <= 8 && alltrue([
      for d in var.disques_donnees : d.taille_go >= 1 && (d.serie == null || length(coalesce(d.serie, "")) <= 20)
    ])
    error_message = "disques_donnees : 8 disques au plus, taille >= 1 Gio, série de 20 caractères au plus."
  }
}

# --- Réseau ------------------------------------------------------------------------------------
variable "cartes" {
  description = <<-EOT
    Cartes réseau dans l'ordre net0, net1… (ens18, ens19… dans l'invité). Pour chacune : VNet,
    préfixe NetBox du VLAN, adresse IMPOSÉE (sans masque, PLAN.md §4.9), MTU (1500 ou 9000,
    PLAN.md §4.9 « MTU »), passerelle (true sur UNE carte au plus : .1 du préfixe).
    La première carte porte le nom DNS et l'IP primaire NetBox.
    Depuis M10-E02 (ajout rétrocompatible) : « mac » (facultative, sinon tirée par Proxmox) et
    « ipv4 » facultative : une carte SANS adresse (ex. carte externe d'un nœud réseau OpenStack)
    vient APRÈS toutes les cartes adressées (Proxmox associe ipconfigN à netN par leur numéro).
  EOT
  type = list(object({
    vnet       = string
    prefixe    = optional(string)
    ipv4       = optional(string)
    mac        = optional(string)
    mtu        = optional(number, 1500)
    passerelle = optional(bool, false)
  }))
  validation {
    condition     = length(var.cartes) >= 1 && length(var.cartes) <= 4
    error_message = "cartes : de 1 à 4."
  }
  validation {
    condition = alltrue([for c in var.cartes :
    c.ipv4 == null ? c.prefixe == null : (can(cidrhost(c.prefixe, 1)) && can(cidrhost("${c.ipv4}/32", 0)))])
    error_message = "cartes : prefixe en CIDR (10.10.30.0/24) et ipv4 sans masque (10.10.30.51), ou ni l'un ni l'autre (carte sans adresse)."
  }
  validation {
    # La première carte porte le nom DNS ; les cartes sans adresse viennent en dernier.
    condition = var.cartes[0].ipv4 != null && alltrue([
      for i, c in var.cartes : c.ipv4 != null || alltrue([for d in slice(var.cartes, i, length(var.cartes)) : d.ipv4 == null])
    ])
    error_message = "cartes : la première carte a une adresse, et les cartes sans adresse viennent APRÈS toutes les cartes adressées."
  }
  validation {
    condition     = alltrue([for c in var.cartes : c.mac == null || can(regex("^([0-9a-f]{2}:){5}[0-9a-f]{2}$", c.mac))])
    error_message = "cartes : mac en minuscules, au format bc:24:11:50:00:51."
  }
  validation {
    condition     = alltrue([for c in var.cartes : !c.passerelle || c.ipv4 != null])
    error_message = "cartes : une carte sans adresse ne porte pas la passerelle."
  }
  validation {
    condition     = alltrue([for c in var.cartes : contains([1500, 9000], c.mtu)])
    error_message = "cartes : MTU 1500 ou 9000 seulement (PLAN.md §4.9)."
  }
  validation {
    condition     = length([for c in var.cartes : c if c.passerelle]) <= 1
    error_message = "cartes : une seule carte porte la passerelle par défaut."
  }
}

variable "resolveurs" {
  description = "Résolveurs DNS écrits par cloud-init."
  type        = list(string)
  default     = ["10.10.20.10", "10.10.20.16"]
}

variable "cle_ssh_admin" {
  description = "Clé publique SSH injectée pour le compte admin par cloud-init."
  type        = string
  validation {
    condition     = can(regex("^ssh-(ed25519|rsa) ", var.cle_ssh_admin))
    error_message = "cle_ssh_admin : clé publique OpenSSH (ssh-ed25519 …)."
  }
}

# --- NetBox ------------------------------------------------------------------------------------
variable "netbox_cluster" {
  description = "Cluster de virtualisation NetBox de la VM (modélisation M06-E05)."
  type        = string
  default     = "pve01"
}

# --- Cycle de vie --------------------------------------------------------------------------------
variable "demarrage_auto" {
  description = "Démarrer la VM avec l'hyperviseur (onboot)."
  type        = bool
  default     = false
}

variable "protection" {
  description = "Drapeau « protection » de Proxmox (refuse la suppression de la VM et de ses disques)."
  type        = bool
  default     = false
}
