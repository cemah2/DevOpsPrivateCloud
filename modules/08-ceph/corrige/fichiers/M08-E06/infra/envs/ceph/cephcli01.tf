# envs/ceph/cephcli01.tf — client de test du cluster (M08-E06).
#
# PLAN.md §4.9 : VMID 2085, Debian 13, une seule carte sur le VLAN 30 (10.10.30.20, passerelle
# 10.10.30.1, MTU 9000) : le client parle aux MON et aux OSD sur le réseau PUBLIC ; il n'a rien à
# faire sur le réseau cluster. adm01 (MGMT) le joint comme tout le lab.
# Même module que les nœuds (vm-noeud), famille debian13.

module "cephcli01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-noeud?ref=v2.2.0"

  nom         = "cephcli01"
  vmid        = 2085
  noeud       = var.noeud
  famille     = "debian13"
  coeurs      = 2
  memoire_mo  = 2048
  disque_go   = 20
  stockage    = "local-nvme"
  etiquettes  = ["env-m08", "role-ceph-client"]
  description = "Client de test de ceph-par1 : RBD, CephFS, S3, iSCSI, ZFS (M08)."

  cartes = [
    { vnet = "vstopub", prefixe = "10.10.30.0/24", ipv4 = "10.10.30.20", mtu = 9000, passerelle = true },
  ]

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = false
}

module "dns_cephcli01" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.2.0"

  nom  = module.cephcli01.fqdn
  ipv4 = module.cephcli01.ipv4
}

output "cephcli01" {
  description = "Client de test : VMID, adresse, nom."
  value = {
    vmid = module.cephcli01.vmid
    ipv4 = module.cephcli01.ipv4
    fqdn = module.cephcli01.fqdn
  }
}
