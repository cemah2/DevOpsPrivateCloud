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

variable "hotes" {
  description = <<-EOT
    Hôtes du module 12 : nom => { n (VMID 2120 + n, MAC bc:24:11:99:12:0n), famille, rôle }.
    Tous sur vsandbox en DHCP (noms par le DDNS de Kea), 2 vCPU, 2 Go, 32 Gio (PLAN.md §4.10).
    Détruire l'environnement : retirer les entrées (ou tofu destroy), JAMAIS d'action dans Proxmox.
    Mini-projet (M12-E46) : ctr01 peut être gardée jusqu'à M13-E02 (registre de travail).
  EOT
  type = map(object({
    n       = number
    famille = string
    role    = string
  }))
  default = {
    ctr01    = { n = 1, famille = "debian13", role = "docker" }
    ctr02    = { n = 2, famille = "debian13", role = "podman" }
    ctr03    = { n = 3, famille = "rocky10", role = "podman" }
    legacy01 = { n = 4, famille = "debian13", role = "legacy" }
  }
  validation {
    condition     = alltrue([for nom, h in var.hotes : h.n >= 1 && h.n <= 9 && contains(["docker", "podman", "legacy"], h.role)])
    error_message = "hotes : n de 1 à 9 (VMID 2121-2129), role docker, podman ou legacy."
  }
}
