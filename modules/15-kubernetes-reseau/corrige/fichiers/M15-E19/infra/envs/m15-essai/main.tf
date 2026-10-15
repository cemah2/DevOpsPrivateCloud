# envs/m15-essai/main.tf — m15-essai : kubeadm mononœud pour comparer MetalLB (M15-E19).
# vsandbox (10.10.99.0/24) : adresse FIXE 10.10.99.51 (plage « nœuds de clusters » .50-.99,
# hors DHCP .100-.199) ; adresses MetalLB 10.10.99.230-238 (PLAN §4.2 : .200-.249 pools d'IP).
# Étiquettes env-m15 et role-k8s-essai : à créer d'abord dans NetBox (module vm-noeud).
# Détruite en fin de module (mini-projet M15-E46) : tofu destroy, l'état reste (vide).

module "m15_essai" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=v2.3.0"

  nom         = "m15-essai"
  vmid        = 2151
  noeud       = var.noeud
  famille     = "debian13"
  coeurs      = 2
  memoire_mo  = 4096
  disque_go   = 30
  stockage    = "local-nvme"
  etiquettes  = ["env-m15", "role-k8s-essai"]
  description = "Essai MetalLB (kubeadm mononœud, Cilium sans LB IPAM), M15-E19. Jetable."

  cartes = [
    { vnet = "vsandbox", prefixe = "10.10.99.0/24", ipv4 = "10.10.99.51", passerelle = true },
  ]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = false
}

module "dns_m15_essai" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.3.0"

  nom  = module.m15_essai.fqdn
  ipv4 = module.m15_essai.ipv4
}

output "m15_essai" {
  description = "VM d'essai MetalLB : VMID, adresse, nom."
  value = {
    vmid = module.m15_essai.vmid
    ipv4 = module.m15_essai.ipv4
    fqdn = module.m15_essai.fqdn
  }
}
