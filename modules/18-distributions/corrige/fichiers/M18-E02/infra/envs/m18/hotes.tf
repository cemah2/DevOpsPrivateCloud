# hotes.tf — VMs Debian et Rocky du module 18 (M18-E02 ; groupes k3s et rke2 activés en E03, E04).
#
# PLAN.md §4.10 et modules/18-distributions/enonce/00-introduction.md (tableau des hôtes).
# Règles partagées :
#   VMID  = écrit en clair (2181-2188) : il se lit et se cherche ;
#   MAC   = bc:24:11:99:18:<deux derniers chiffres du VMID> : même bail Kea après reconstruction ;
#   réseau = vsandbox en DHCP, noms par le DDNS de Kea (vm-noeud v2.4, M12-E02).
# RKE2 sur Rocky Linux 10 : Debian n'est pas dans la matrice de support de RKE2 1.36 (SUSE).

locals {
  catalogue = {
    m18-dev01 = { vmid = 2188, groupe = "dev", famille = "debian13", coeurs = 4, memoire_mo = 8192, disque_go = 60, role = "m18-dev",
    description = "M18 : poste de développement (Docker, kind, k3d, clusterctl, image-builder)." }
    k3s01 = { vmid = 2181, groupe = "k3s", famille = "debian13", coeurs = 2, memoire_mo = 4096, disque_go = 32, role = "k3s",
    description = "M18 : k3s monoœud (agence LYO1 simulée), puis cluster de gestion Cluster API (E12)." }
    rke2-01 = { vmid = 2182, groupe = "rke2", famille = "rocky10", coeurs = 2, memoire_mo = 4096, disque_go = 32, role = "rke2",
    description = "M18 : RKE2, serveur (etcd), profil CIS." }
    rke2-02 = { vmid = 2183, groupe = "rke2", famille = "rocky10", coeurs = 2, memoire_mo = 4096, disque_go = 32, role = "rke2",
    description = "M18 : RKE2, serveur (etcd), profil CIS." }
    rke2-03 = { vmid = 2184, groupe = "rke2", famille = "rocky10", coeurs = 2, memoire_mo = 4096, disque_go = 32, role = "rke2",
    description = "M18 : RKE2, serveur (etcd), profil CIS." }
  }

  hotes = { for nom, h in local.catalogue : nom => h if contains(var.groupes, h.groupe) }
}

module "hote" {
  for_each = local.hotes
  # vm-noeud v2.4.0 (carte DHCP, M12-E02) : mets l'étiquette publiée si la numérotation diffère.
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=v2.4.0"

  nom         = each.key
  vmid        = each.value.vmid
  noeud       = var.noeud
  famille     = each.value.famille
  coeurs      = each.value.coeurs
  memoire_mo  = each.value.memoire_mo
  disque_go   = each.value.disque_go
  stockage    = "local-nvme"
  etiquettes  = ["env-m18", "role-${each.value.role}"]
  description = "${each.value.description} Environnement jetable, détruit par le code en fin de module."

  cartes = [
    { vnet = "vsandbox", ipv4 = "dhcp", mac = format("bc:24:11:99:18:%02d", each.value.vmid % 100) },
  ]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = false
}

output "hotes" {
  description = "VMs Debian/Rocky du module 18 : VMID, nom, MAC, adresses vues par l'agent QEMU."
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
