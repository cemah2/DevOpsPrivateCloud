# hotes.tf — VMs temporaires du module 25 (PLAN §4.12), VNet vsandbox, adresses FIXES : le seul flux
# qu'elles reçoivent (vers kms01 8200, temporaire) vise une adresse, pas un bail DHCP.
# MAC = bc:24:11:<VLAN>:25:<deux derniers chiffres du VMID>.
#   2252 bao-restauration 10.10.99.52  restauration d'essai de la grappe (E26)  1 vCPU, 1 Go
#   2251 bao-essai        10.10.99.51  HashiCorp Vault 2.2 en comparaison (E30) 2 vCPU, 2 Go
# ⚠️ bao-restauration contient une COPIE VIVANTE du coffre : aucun flux sortant hormis kms01:8200
# (voir RB-252) ; détruite après l'essai.

locals {
  catalogue = {
    bao-restauration = {
      vmid        = 2252, groupe = "restauration", ipv4 = "10.10.99.52", coeurs = 1, memoire_mo = 1024,
      description = "M25-E26 : restauration d'essai d'OpenBao. COPIE DU COFFRE : isolée, détruite après usage."
    }
    bao-essai = {
      vmid        = 2251, groupe = "essai", ipv4 = "10.10.99.51", coeurs = 2, memoire_mo = 2048,
      description = "M25-E30 : HashiCorp Vault 2.2 en comparaison. Détruite en fin d'exercice."
    }
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
  coeurs      = each.value.coeurs
  memoire_mo  = each.value.memoire_mo
  disque_go   = 20
  stockage    = "local-nvme"
  etiquettes  = ["env-m25"]
  description = each.value.description

  cartes = [
    { vnet = "vsandbox", prefixe = "10.10.99.0/24", ipv4 = each.value.ipv4,
    mac = format("bc:24:11:99:25:%02d", each.value.vmid % 100), passerelle = true },
  ]
  resolveurs = ["10.10.20.10", "10.10.20.16"]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = false
}
