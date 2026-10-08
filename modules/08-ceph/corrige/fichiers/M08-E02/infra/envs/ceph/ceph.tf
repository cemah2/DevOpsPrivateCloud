# envs/ceph/ceph.tf — nœuds du cluster ceph-par1 (M08-E02).
#
# PLAN.md §4.9 : Rocky Linux 10 (image dorée rocky10 « current »), 2 vCPU, 6 Go, disque système
# sur local-nvme, 2 disques d'OSD de 64 Gio sur ssd-lab (classe ssd) et 1 sur hdd-bulk (classe
# hdd) ; public 10.10.30.5N (VLAN 30, passerelle), cluster 10.10.31.5N (VLAN 31, non routé),
# MTU 9000 sur les deux (M07-E15).
# Version du module : la dernière étiquette publiée de plateforme/tofu-modules (adapter ?ref=).


module "ceph" {
  for_each = var.noeuds_ceph
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=v2.2.0"

  nom         = each.key
  vmid        = 2080 + each.value
  noeud       = var.noeud
  famille     = "rocky10"
  coeurs      = 2
  memoire_mo  = 6144
  disque_go   = 20
  stockage    = "local-nvme"
  etiquettes  = ["env-m08", "role-ceph"]
  description = "Nœud du cluster ceph-par1 (MON, MGR, OSD). Cluster conservé pour M10 et M16."

  cartes = [
    { vnet = "vstopub", prefixe = "10.10.30.0/24", ipv4 = "10.10.30.${50 + each.value}", mtu = 9000, passerelle = true },
    { vnet = "vstoclu", prefixe = "10.10.31.0/24", ipv4 = "10.10.31.${50 + each.value}", mtu = 9000 },
  ]

  disques_donnees = [
    { taille_go = 64, datastore = "ssd-lab", ssd = true, serie = "${each.key}-ssd1" },
    { taille_go = 64, datastore = "ssd-lab", ssd = true, serie = "${each.key}-ssd2" },
    { taille_go = 64, datastore = "hdd-bulk", ssd = false, serie = "${each.key}-hdd1" },
  ]

  cle_ssh_admin = var.cle_ssh_admin
  # Démarrage manuel : le cluster s'arrête et se relance selon la procédure de l'introduction
  # du module (drapeaux noout/norebalance), jamais au hasard d'un redémarrage de pve01.
  demarrage_auto = false
}

module "dns_ceph" {
  for_each = var.noeuds_ceph
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.2.0"

  nom  = module.ceph[each.key].fqdn
  ipv4 = module.ceph[each.key].ipv4
}

output "ceph" {
  description = "Nœuds Ceph : VMID, adresses (public, cluster), nom."
  value = {
    for n, m in module.ceph : n => {
      vmid     = m.vmid
      adresses = m.adresses
      fqdn     = m.fqdn
      type_cpu = m.type_cpu
    }
  }
}
