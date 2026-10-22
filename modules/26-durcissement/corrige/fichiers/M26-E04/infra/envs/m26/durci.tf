# envs/m26/durci.tf — VMs d'essai du durcissement (M26-E04, SEC-2704).
#
# PLAN §4.12 : 2261 durci-deb (Debian 13, image dorée deb13-gold « current »), 2262 durci-rocky
# (Rocky 10, rocky10-gold « current ») ; vsandbox (DHCP, noms par le DDNS de Kea), étiquette env-m26.
# Elles reçoivent les mesures OpenSCAP (E04) puis le rôle « durcissement » (E10-E13), seules VMs
# modifiées avant que le rôle soit éprouvé ; elles sont détruites à la fin d'E14.
# Module vm-noeud avec cartes DHCP (≥ v2.4.0, M12-E02) : mets l'étiquette publiée chez toi.

module "essai" {
  for_each = var.vms_essai
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=<VERSION-TOFU-MODULES>"

  nom         = each.key
  vmid        = 2260 + each.value.n
  noeud       = var.noeud
  famille     = each.value.famille
  coeurs      = 2
  memoire_mo  = 2048
  disque_go   = 32
  stockage    = "local-nvme"
  etiquettes  = ["env-m26", "role-durcissement"]
  description = "Module 26 : VM d'essai du durcissement (${each.value.famille}). Jetable, détruite par le code à la fin d'E14."

  cartes = [
    # MAC imposée : même bail Kea (donc même adresse) si on la reconstruit après un essai raté.
    { vnet = "vsandbox", ipv4 = "dhcp", mac = format("bc:24:11:99:26:%02d", each.value.n) },
  ]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = false
}

output "vms_essai" {
  description = "VMs d'essai du module 26 : VMID, nom, MAC, adresses vues par l'agent QEMU."
  value = {
    for n, m in module.essai : n => {
      vmid     = m.vmid
      fqdn     = m.fqdn
      macs     = m.macs
      type_cpu = m.type_cpu
      adresses = m.adresses_agent
    }
  }
}
