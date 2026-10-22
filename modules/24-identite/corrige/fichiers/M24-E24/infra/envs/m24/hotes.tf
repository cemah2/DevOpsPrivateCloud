# hotes.tf — VMs temporaires du module 24 (PLAN §4.12), adresses FIXES (règles de pare-feu locales
# et HAProxy visent une adresse, pas un bail). MAC = bc:24:11:<VLAN>:24:<deux derniers chiffres du VMID>.
#   2241 idp02     10.10.20.42  vinfra    second nœud Keycloak de l'essai de grappe (E24)
#   2242 idp-resto 10.10.99.42  vsandbox  restauration d'essai de Keycloak (E25), essai de montée (E33)
# Configuration : playbook identite.yml (idp02 : groupe role_idp) ; idp-resto : inventaire d'essai
# inventories/essai-resto/ (RB-243), jamais dans l'inventaire du lab.

locals {
  catalogue = {
    idp02 = {
      vmid = 2241, groupe = "idp02", vnet = "vinfra", prefixe = "10.10.20.0/24", ipv4 = "10.10.20.42",
      vlan = 20, etiquettes = ["env-m24", "role-idp"],
      description = "M24-E24 : second nœud Keycloak (essai de grappe jdbc-ping). Détruit en fin d'exercice."
    }
    idp-resto = {
      vmid = 2242, groupe = "resto", vnet = "vsandbox", prefixe = "10.10.99.0/24", ipv4 = "10.10.99.42",
      vlan = 99, etiquettes = ["env-m24"],
      description = "M24-E25/E33 : restauration d'essai de Keycloak. CONTIENT DES SECRETS : isolée, détruite après usage."
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
  coeurs      = 2
  memoire_mo  = 2048
  disque_go   = 20
  stockage    = "local-nvme"
  etiquettes  = each.value.etiquettes
  description = each.value.description

  cartes = [
    { vnet = each.value.vnet, prefixe = each.value.prefixe, ipv4 = each.value.ipv4,
    mac = format("bc:24:11:%02d:24:%02d", each.value.vlan, each.value.vmid % 100), passerelle = true },
  ]
  resolveurs = ["10.10.20.10", "10.10.20.16"]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = false
}
