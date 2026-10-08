# noeuds.tf — les trois nœuds OpenStack (M10-E02, PLAT-1102). PLAN §4.9.
#
# Une seule règle, partagée avec le rôle Ansible noeud_openstack :
#   suffixe   = dernier octet de l'adresse OS-API (51, 52, 53)
#   OS-API    = 10.10.50.<suffixe>   (ens18, net0, passerelle 10.10.50.1)
#   OS-TUN    = 10.10.51.<suffixe>   (ens19, net1, MTU 9000)
#   STOR-PUB  = 10.10.30.<suffixe+10> (ens20, net2, MTU 9000)
#   OS-EXT    = sans adresse          (ens21, net3, osctl01 seulement)
#   MAC       = bc:24:11:<VLAN>:00:<suffixe>
# bc:24:11 est le préfixe des MAC générées par Proxmox ; les octets suivants sont choisis par nous
# (ils s'écrivent tous en hexadécimal valide : 30, 50, 51, 52 et 51-53).

locals {
  noeuds = {
    osctl01 = { vmid = 2101, suffixe = 51, coeurs = 4, memoire_mo = 16384, disque_go = 80, type_cpu = "x86-64-v2-AES", externe = true,
    description = "OpenStack : contrôle et réseau (passerelle OVN). Kolla-Ansible, plateforme/openstack." }
    oscmp01 = { vmid = 2102, suffixe = 52, coeurs = 4, memoire_mo = 8192, disque_go = 40, type_cpu = "host", externe = false,
    description = "OpenStack : calcul (KVM imbriqué, CPU host)." }
    oscmp02 = { vmid = 2103, suffixe = 53, coeurs = 4, memoire_mo = 8192, disque_go = 40, type_cpu = "host", externe = false,
    description = "OpenStack : calcul (KVM imbriqué, CPU host)." }
  }

  mac = { for nom, n in local.noeuds : nom => {
    api = format("bc:24:11:50:00:%d", n.suffixe)
    tun = format("bc:24:11:51:00:%d", n.suffixe)
    sto = format("bc:24:11:30:00:%d", n.suffixe)
    ext = format("bc:24:11:52:00:%d", n.suffixe)
  } }
}

module "noeud" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=v2.2.0"
  for_each = local.noeuds

  nom         = each.key
  vmid        = each.value.vmid
  noeud       = var.noeud
  description = each.value.description
  etiquettes  = ["env-m10", "role-openstack"]

  type_cpu   = each.value.type_cpu
  coeurs     = each.value.coeurs
  memoire_mo = each.value.memoire_mo
  disque_go  = each.value.disque_go
  stockage   = "local-nvme"

  # Carte principale : OS-API (VLAN 50), adresse imposée par le PLAN, passerelle déduite (.1).
  vnet                 = "vosapi"
  mac_adresse          = local.mac[each.key].api
  interface_principale = "ens18"
  reseau_prefixe       = "10.10.50.0/24"
  ipv4_imposee         = "10.10.50.${each.value.suffixe}"
  resolveurs           = ["10.10.20.10", "10.10.20.16"]

  # Cartes adressées d'abord, carte externe (sans adresse) en dernier (règle du module).
  cartes_supplementaires = concat(
    [
      { vnet = "vostun", interface = "ens19", mac_adresse = local.mac[each.key].tun, mtu = 9000,
      ipv4_imposee = "10.10.51.${each.value.suffixe}", prefixe = "10.10.51.0/24" },
      { vnet = "vstopub", interface = "ens20", mac_adresse = local.mac[each.key].sto, mtu = 9000,
      ipv4_imposee = "10.10.30.${each.value.suffixe + 10}", prefixe = "10.10.30.0/24" },
    ],
    each.value.externe ? [
      { vnet = "vosext", interface = "ens21", mac_adresse = local.mac[each.key].ext, mtu = 1500 },
    ] : []
  )

  cle_ssh_admin  = var.cle_ssh_admin
  demarrage_auto = true
  # Ordre de démarrage (osctl01 avant les calculs) posé en root après création :
  #   root@pve01:~# qm set 2101 --startup order=20 ; qm set 2102 --startup order=21 ; qm set 2103 --startup order=21
}

output "noeuds" {
  description = "Nœuds OpenStack : VMID, adresse OS-API, nom, MAC."
  value = { for nom, m in module.noeud : nom => {
    vmid = m.vmid
    ipv4 = m.ipv4
    fqdn = m.fqdn
    macs = m.macs
  } }
}
