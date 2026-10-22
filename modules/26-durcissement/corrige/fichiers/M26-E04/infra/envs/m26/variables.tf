variable "noeud" {
  description = "Nœud Proxmox (<NOEUD>)."
  type        = string
}

variable "cle_ssh_admin" {
  description = "Clé publique SSH de adm01 (contenu de ~/.ssh/id_ed25519.pub)."
  type        = string
}

variable "netbox_url" {
  description = "URL racine de NetBox (sans /api)."
  type        = string
  default     = "https://nbx01.par1.medisphere.internal"
}

variable "netbox_api_token" {
  description = "Jeton v2 du compte d'automatisation NetBox (TF_VAR_netbox_api_token)."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "vms_essai" {
  description = <<-EOT
    VMs d'essai du durcissement : nom => { n (VMID 2260 + n, MAC bc:24:11:99:26:0n), famille }.
    vsandbox en DHCP (noms par le DDNS de Kea), 2 vCPU, 2 Go, 32 Gio (PLAN §4.12).
    Créées en M26-E04, DÉTRUITES à la fin de M26-E14 : retirer les entrées (ou tofu destroy), jamais
    d'action dans Proxmox. Jamais en même temps qu'une autre VM temporaire du bloc F (mémoire).
  EOT
  type = map(object({
    n       = number
    famille = string
  }))
  default = {
    durci-deb   = { n = 1, famille = "debian13" }
    durci-rocky = { n = 2, famille = "rocky10" }
  }
  validation {
    condition     = alltrue([for nom, v in var.vms_essai : v.n >= 1 && v.n <= 9 && contains(["debian13", "rocky10"], v.famille)])
    error_message = "vms_essai : n de 1 à 9 (VMID 2261-2269), famille debian13 ou rocky10."
  }
}
