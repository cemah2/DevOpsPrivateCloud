# variables.tf — entrées de l'état « hv » (M09-E03).
# Les valeurs non secrètes sont dans terraform.tfvars et noeuds.auto.tfvars.json (versionnés).
# Les secrets n'entrent que par l'environnement (PROXMOX_VE_*, TF_VAR_* éphémères).

variable "noeud" {
  description = "Nœud Proxmox PHYSIQUE qui héberge les nœuds imbriqués (<NOEUD> : hostname de pve01)."
  type        = string
  nullable    = false
}

variable "pool" {
  description = "Pool Proxmox des VMs du workbook."
  type        = string
  default     = "lab"

  validation {
    condition     = var.pool == "lab"
    error_message = "Les VMs du workbook vont dans le pool « lab » (PLAN §3.1), et nulle part ailleurs."
  }
}

variable "stockage_systeme" {
  description = "Stockage du disque système des nœuds (installation de Proxmox VE)."
  type        = string
  default     = "local-nvme"
}

variable "stockage_donnees" {
  description = "Stockage des disques OSD (Ceph) et ZFS des nœuds."
  type        = string
  default     = "ssd-lab"
}

variable "stockage_iso" {
  description = "Stockage des ISO d'installation préparées (contenu iso)."
  type        = string
  default     = "hdd-bulk"
}

variable "prefixe_iso" {
  description = "Préfixe des ISO préparées par installation/preparer-iso.sh : <prefixe>-<nœud>.iso."
  type        = string
  default     = "pve92-auto"
}

variable "pont_invites" {
  description = "Pont de pve01 qui porte le trunk des invités imbriqués (carte net4, sans étiquette)."
  type        = string
  default     = "vmbr1"
}

variable "vlans_invites" {
  description = "VLAN autorisés sur la carte trunk des nœuds (champ trunks de Proxmox)."
  type        = list(number)
  default     = [99]

  validation {
    # Jamais les VLAN du socle ou des autres environnements : un invité imbriqué mal étiqueté
    # se retrouverait dans INFRA ou MGMT. Le bac à sable (99) suffit au module.
    condition     = alltrue([for v in var.vlans_invites : contains([99], v)])
    error_message = "Seul le VLAN 99 (SANDBOX) est autorisé sur le trunk des invités imbriqués."
  }
}

variable "noeuds" {
  description = "Nœuds du cluster hv-par1 : nom court => numéro, VMID et adresses (noeuds.auto.tfvars.json)."
  type = map(object({
    numero = number
    vmid   = number
    mgmt   = string
    coro   = string
    stopub = string
    stoclu = string
  }))

  validation {
    condition     = alltrue([for n, v in var.noeuds : can(regex("^hv0[1-3]$", n)) && v.vmid == 2090 + v.numero && n == format("hv%02d", v.numero)])
    error_message = "Nœuds hv01 à hv03, VMID 2091 à 2093 (PLAN §4.9) : hvNN a le numéro NN et le VMID 2090+NN."
  }
  validation {
    condition = alltrue([for v in values(var.noeuds) :
      v.mgmt == format("10.10.10.%d", 50 + v.numero) && v.coro == format("10.10.32.%d", 50 + v.numero)
      && v.stopub == format("10.10.30.%d", 70 + v.numero) && v.stoclu == format("10.10.31.%d", 70 + v.numero)
    ])
    error_message = "Adresses de PLAN §4.9 : MGMT 10.10.10.5N, COROSYNC 10.10.32.5N, Ceph 10.10.30.7N et 10.10.31.7N."
  }
}

variable "netbox_url" {
  description = "URL racine de NetBox (sans /api)."
  type        = string
  default     = "https://nbx01.par1.medisphere.internal"
}

variable "netbox_api_token" {
  description = "Jeton v2 du compte svc-automatisation (TF_VAR_netbox_api_token)."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "netbox_cluster" {
  description = "Cluster NetBox des VMs portées par pve01 (M06-E05)."
  type        = string
  default     = "pve01"
}

variable "pdns_url" {
  description = "API de PowerDNS Authoritative (dns01)."
  type        = string
  default     = "http://dns01.par1.medisphere.internal:8081"
}

variable "pdns_api_key" {
  description = "Clé d'API PowerDNS (TF_VAR_pdns_api_key)."
  type        = string
  sensitive   = true
  ephemeral   = true
}
