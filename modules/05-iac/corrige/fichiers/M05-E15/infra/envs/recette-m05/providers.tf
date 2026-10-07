# providers.tf — accès à l'API de pve01 (M05-E15), sans secret : PROXMOX_VE_* de pve-tofu.env.
provider "proxmox" {
  insecure = false
}
