# socle/repartiteurs.tf — plateforme/infra, état « socle » (M07-E12, ticket PLAT-822). RB-060.
#
# lb01 (1010) et lb02 (1011) : répartiteurs HAProxy + keepalived de la DMZ (VLAN 70), adresses
# FIXÉES par le PLAN (§4.5). Même chemin que dns02 (M06-E24) : le module vm-debian v2 enregistre
# l'intention dans NetBox (VM, interface, adresse imposée, IP primaire) puis crée la VM ; le
# module enregistrement-dns publie A et PTR.
# La VIP 10.10.70.200 n'appartient à aucune VM : c'est une adresse de RÔLE « vip » dans NetBox,
# portée tour à tour par lb01 ou lb02 (keepalived). Elle a son nom, lb.par1.medisphere.internal.
#
# Si 10.10.70.10, .11 ou .200 existent déjà dans NetBox (statut « reserved », modélisation de
# M06-E05), supprime-les ou importe-les avant l'apply (RB-060, étape 2) : sinon doublon et échec.

locals {
  repartiteurs = {
    lb01 = { vmid = 1010, ipv4 = "10.10.70.10" }
    lb02 = { vmid = 1011, ipv4 = "10.10.70.11" }
  }
  vip_lb = "10.10.70.200"
}

module "repartiteur" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v2.1.0"
  for_each = local.repartiteurs

  nom         = each.key
  vmid        = each.value.vmid
  noeud       = var.noeud
  vnet        = "vdmz"
  coeurs      = 1
  memoire_mo  = 1024
  disque_go   = 10
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-lb"]
  description = "Répartiteur HAProxy + keepalived, VIP ${local.vip_lb} (M07-E12)."

  # Ordre de démarrage 3 (après gw01 et les DNS, avec adm01), posé en root après création :
  #   root@pve01:~# qm set 1010 --startup order=3 ; qm set 1011 --startup order=3

  reseau_prefixe = "10.10.70.0/24"
  ipv4_imposee   = each.value.ipv4
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_repartiteur" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = local.repartiteurs

  nom  = module.repartiteur[each.key].fqdn
  ipv4 = module.repartiteur[each.key].ipv4
  ttl  = 3600
}

# La VIP dans NetBox : adresse de rôle « vip », sans interface (elle se déplace).
resource "netbox_ip_address" "vip_lb" {
  ip_address  = "${local.vip_lb}/24"
  status      = "active"
  role        = "vip"
  dns_name    = "lb.par1.medisphere.internal"
  description = "VIP des répartiteurs lb01/lb02, VRRP VRID 170 (M07-E12)"
}

module "dns_vip_lb" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"

  nom  = netbox_ip_address.vip_lb.dns_name
  ipv4 = local.vip_lb
  ttl  = 300 # adresse de service : TTL court, au cas où on la déplacerait
}

output "repartiteurs" {
  description = "Répartiteurs : VMID, adresse, nom ; VIP et son nom."
  value = {
    hotes = { for k, m in module.repartiteur : k => { vmid = m.vmid, ipv4 = m.ipv4, fqdn = m.fqdn } }
    vip   = { ipv4 = local.vip_lb, fqdn = netbox_ip_address.vip_lb.dns_name }
  }
}
