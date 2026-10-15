# envs/m12/conteneurs.tf — hôtes de conteneurs du module 12 (M12-E02).
#
# PLAN.md §4.10 : 2121 ctr01 (Debian 13, Docker Engine 29), 2122 ctr02 (Debian 13, Podman 5.4
# sans privilège), 2123 ctr03 (Rocky 10, Podman 5.8, SELinux), 2124 legacy01 (Debian 13,
# Legacy-RDV « à l'ancienne ») ; VNet vsandbox (DHCP, noms par le DDNS de Kea), étiquette env-m12.
# Module vm-noeud v2.4.0 (carte DHCP) : adapte ?ref= à l'étiquette publiée par ta MR.

module "hote" {
  for_each = var.hotes
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=v2.4.0"

  nom         = each.key
  vmid        = 2120 + each.value.n
  noeud       = var.noeud
  famille     = each.value.famille
  coeurs      = 2
  memoire_mo  = 2048
  disque_go   = 32
  stockage    = "local-nvme"
  etiquettes  = ["env-m12", "role-${each.value.role}"]
  description = "Module 12 (conteneurs) : hôte ${each.value.role}. Environnement jetable, détruit par le code en fin de module."

  cartes = [
    # MAC imposée : la VM retrouve le même bail Kea (donc la même adresse) si on la reconstruit.
    { vnet = "vsandbox", ipv4 = "dhcp", mac = format("bc:24:11:99:12:%02d", each.value.n) },
  ]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = false
}

output "hotes" {
  description = "Hôtes du module 12 : VMID, nom, MAC, adresses vues par l'agent QEMU."
  value = {
    for n, m in module.hote : n => {
      vmid     = m.vmid
      fqdn     = m.fqdn
      macs     = m.macs
      type_cpu = m.type_cpu
      adresses = m.adresses_agent
    }
  }
}
