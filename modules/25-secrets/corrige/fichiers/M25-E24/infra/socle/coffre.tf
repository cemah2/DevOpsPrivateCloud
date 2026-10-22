# socle/coffre.tf — plateforme/infra, état « socle » (M25-E24, ticket PLAT-2624). REMPLACE vault01.tf (M25-E03).
#
# Grappe OpenBao de trois nœuds (PLAN §4.5, §4.12) : vault01 (1021, 10.10.20.21), vault02 (1022,
# .22), vault03 (1023, .23), VLAN 20 INFRA, Debian 13, 2 vCPU, 1 Go, 20 Go. Une seule ressource
# itérée : les trois nœuds sont identiques, seuls le nom, le VMID et l'adresse changent.
#
# ⚠️ vault01 EXISTE déjà sous l'adresse module.vault01 : les blocs « moved » ci-dessous déplacent
# son état vers module.coffre["vault01"] SANS le recréer. Lis le plan : il doit annoncer
# « has moved to » pour vault01 et dns_vault01, et « will be created » pour vault02 et vault03
# seulement. Un plan qui veut détruire vault01 est faux : on n'applique pas.
#
# Le nom du service, openbao.par1.medisphere.internal, passe de 10.10.20.21 à la VIP 10.10.20.200
# (keepalived, VRID 120) en DEUX temps : (1) cette MR avec var.openbao_sur_vip = false (VMs, VIP dans
# NetBox) ; (2) quand keepalived porte la VIP sur le nœud actif et qu'elle répond, une MR d'une ligne
# qui passe la variable à true. Retour arrière : false, apply (TTL 300 s).

variable "openbao_sur_vip" {
  description = "true : openbao.par1.medisphere.internal pointe sur la VIP 10.10.20.200 (M25-E24, étape 6)."
  type        = bool
  default     = false
}

locals {
  coffre = {
    vault01 = { vmid = 1021, ipv4 = "10.10.20.21" }
    vault02 = { vmid = 1022, ipv4 = "10.10.20.22" }
    vault03 = { vmid = 1023, ipv4 = "10.10.20.23" }
  }
  vip_openbao = "10.10.20.200"
}

moved {
  from = module.vault01
  to   = module.coffre["vault01"]
}

moved {
  from = module.dns_vault01
  to   = module.dns_coffre["vault01"]
}

module "coffre" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=<VERSION-TOFU-MODULES>"
  for_each = local.coffre

  nom         = each.key
  vmid        = each.value.vmid
  noeud       = var.noeud
  vnet        = "vinfra"
  coeurs      = 2
  memoire_mo  = 1024
  disque_go   = 20
  stockage    = "local-nvme"
  etiquettes  = ["socle", "role-coffre"]
  description = "Coffre OpenBao, nœud ${each.key} (Raft, grappe de trois), M25-E03/E24."

  # Ordre de démarrage 4 (comme vault01), posé en root après création :
  #   root@pve01:~# qm set 1022 --startup order=4 ; qm set 1023 --startup order=4
  # Jusqu'au M25-E25, chaque nœud démarre SCELLÉ et attend trois parts.

  reseau_prefixe = "10.10.20.0/24"
  ipv4_imposee   = each.value.ipv4
  resolveurs     = ["10.10.20.10", "10.10.20.16"]
  cle_ssh_admin  = var.cle_ssh_admin
}

module "dns_coffre" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"
  for_each = local.coffre

  nom  = module.coffre[each.key].fqdn
  ipv4 = module.coffre[each.key].ipv4
  ttl  = 3600
}

# La VIP dans NetBox : adresse de rôle « vip », sans interface (elle suit le nœud actif).
# Si 10.10.20.200 est réservée depuis M06-E05, importe-la avant l'apply (RB-060).
resource "netbox_ip_address" "vip_openbao" {
  ip_address  = "${local.vip_openbao}/24"
  status      = "active"
  role        = "vip"
  dns_name    = "openbao.par1.medisphere.internal"
  description = "VIP du coffre OpenBao (nœud actif), keepalived VRID 120 (M25-E24)"
}

# Nom du service (créé en M25-E03) : même ressource, nouvelle cible. Pas de PTR pour la VIP : un
# PTR de 10.10.20.200 vers openbao… serait juste, mais 10.10.20.200 n'appartient à aucune VM ; on le
# laisse au module enregistrement-dns si tu préfères (même choix que lb au M07-E12).
resource "powerdns_record" "openbao" {
  zone     = "par1.medisphere.internal."
  name     = "openbao.par1.medisphere.internal."
  type     = "A"
  ttl      = 300
  records  = [var.openbao_sur_vip ? local.vip_openbao : module.coffre["vault01"].ipv4]
  comments = ["gere-par=opentofu (plateforme/infra), nom du coffre ; VIP keepalived VRID 120 (M25-E24)"]
}

output "coffre" {
  description = "Nœuds du coffre (VMID, adresse, nom), VIP et cible actuelle du nom de service."
  value = {
    noeuds  = { for k, m in module.coffre : k => { vmid = m.vmid, ipv4 = m.ipv4, fqdn = m.fqdn } }
    vip     = { ipv4 = local.vip_openbao, fqdn = netbox_ip_address.vip_openbao.dns_name }
    service = one(powerdns_record.openbao.records)
  }
}
