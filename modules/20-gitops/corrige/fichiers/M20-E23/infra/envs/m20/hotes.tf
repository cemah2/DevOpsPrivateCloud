# hotes.tf — VMs k3s du module 20 (PLAN §4.11) : k3s mononœud en ADRESSE FIXE sur vsandbox (VLAN 99).
#   2202 flux01    10.10.99.62  comparaison avec Flux (M20-E23)
#   2201 lyo-k3s01 10.10.99.61  cluster de l'agence LYO1, géré par Argo CD (M20-E26)
# Adresse fixe : les règles de la bordure (VLAN 99 → git01 443, VLAN 40 → 10.10.99.61:6443) visent une
# adresse, pas un bail. MAC = bc:24:11:99:20:<deux derniers chiffres du VMID>.
# Configuration : rôle Ansible k3s du M18 (playbook m20.yml), étiquette env-m20.

locals {
  catalogue = {
    flux01 = { vmid = 2202, groupe = "flux", ipv4 = "10.10.99.62",
    description = "M20 : k3s mononœud, comparaison Argo CD / Flux 2.9 (E23)." }
    lyo-k3s01 = { vmid = 2201, groupe = "lyo", ipv4 = "10.10.99.61",
    description = "M20 : k3s mononœud de l'agence LYO1, cluster distant d'Argo CD (E26)." }
  }

  hotes = { for nom, h in local.catalogue : nom => h if contains(var.groupes, h.groupe) }
}

module "hote" {
  for_each = local.hotes
  # vm-noeud v2.4.0 (M12-E02) : mets l'étiquette publiée si la numérotation diffère.
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=v2.4.0"

  nom         = each.key
  vmid        = each.value.vmid
  noeud       = var.noeud
  famille     = "debian13"
  coeurs      = 2
  memoire_mo  = 2048
  disque_go   = 20
  stockage    = "local-nvme"
  etiquettes  = ["env-m20", "role-k3s"]
  description = "${each.value.description} Environnement jetable, détruit par le code en fin de module."

  cartes = [
    { vnet = "vsandbox", prefixe = "10.10.99.0/24", ipv4 = each.value.ipv4,
    mac = format("bc:24:11:99:20:%02d", each.value.vmid % 100), passerelle = true },
  ]
  resolveurs = ["10.10.20.10", "10.10.20.16"]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = false
}

output "hotes" {
  description = "VMs du module 20 : VMID, nom, adresse, MAC."
  value = {
    for n, m in module.hote : n => {
      vmid = m.vmid
      ipv4 = m.ipv4
      fqdn = m.fqdn
      macs = m.macs
    }
  }
}
