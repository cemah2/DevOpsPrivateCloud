# envs/m20/lyo-k3s01.tf — VM 2201 lyo-k3s01 : k3s mononœud de l'agence LYO1, géré par l'Argo CD de
# k8s-par1 (M20-E26, PLAT-2126). Même état que flux01 (M20-E23) : providers, backend « envs/m20 »,
# variables noeud et cle_ssh_admin y sont déjà déclarés.
# vsandbox (10.10.99.0/24) : adresse FIXE 10.10.99.61 (plage « nœuds de clusters » .50-.99, hors DHCP
# .100-.199) : le Secret de cluster d'Argo CD et la règle de bordure la désignent.
# Étiquettes env-m20 et role-k3s : à créer d'abord dans NetBox si elles n'existent pas (module vm-noeud).
# role-k3s fait entrer la VM dans le groupe Ansible role_k3s (miroirs Harbor du M18).
# Détruite au mini-projet (M20-E46) : lyo_k3s01 = false, puis tofu apply.

variable "lyo_k3s01" {
  description = "Créer (true) ou détruire (false) lyo-k3s01, VM 2201 (M20-E26 ; false au mini-projet)."
  type        = bool
  default     = true
}

module "lyo_k3s01" {
  count  = var.lyo_k3s01 ? 1 : 0
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=v2.4.0"

  nom         = "lyo-k3s01"
  vmid        = 2201
  noeud       = var.noeud
  famille     = "debian13"
  coeurs      = 2
  memoire_mo  = 2048
  disque_go   = 30
  stockage    = "local-nvme"
  etiquettes  = ["env-m20", "role-k3s"]
  description = "M20-E26 : k3s mononœud de l'agence LYO1, géré par Argo CD (k8s-par1). Jetable."

  cartes = [
    { vnet = "vsandbox", prefixe = "10.10.99.0/24", ipv4 = "10.10.99.61", passerelle = true },
  ]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = false
}

module "dns_lyo_k3s01" {
  count  = var.lyo_k3s01 ? 1 : 0
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.4.0"

  nom  = module.lyo_k3s01[0].fqdn
  ipv4 = module.lyo_k3s01[0].ipv4
}

output "lyo_k3s01" {
  description = "Cluster de l'agence LYO1 : VMID, adresse, nom (vide quand la VM est détruite)."
  value = var.lyo_k3s01 ? {
    vmid = module.lyo_k3s01[0].vmid
    ipv4 = module.lyo_k3s01[0].ipv4
    fqdn = module.lyo_k3s01[0].fqdn
  } : null
}
