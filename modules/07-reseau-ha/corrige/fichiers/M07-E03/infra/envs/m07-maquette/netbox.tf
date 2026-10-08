# netbox.tf — réservations dans l'IPAM (M07-E03).
#
# Les VMs de la maquette ne sont PAS décrites ici : jetables, elles entrent dans NetBox par la
# synchronisation Proxmox → NetBox (M06-E11) et en sortent avec elles. En revanche, une adresse
# FIXE prise dans le VLAN 99 doit être réservée : sans cela, rien n'empêche une allocation
# (OpenTofu, vm-debian v2) ou un humain de la donner à quelqu'un d'autre.
# Pas de dns_name : le nom est géré par dns.tf (un seul propriétaire par enregistrement).

resource "netbox_ip_address" "fixe" {
  for_each = local.adresses_fixes

  ip_address  = "${each.value}/24"
  status      = "reserved"
  description = "Maquette M07 : ${each.key} (envs/m07-maquette)"
}

resource "netbox_ip_address" "vip_web_demo" {
  ip_address  = "10.10.99.240/24"
  status      = "reserved"
  role        = "vrrp"
  description = "Maquette M07 : VIP de démonstration srv01/srv02, VRID 199 (M07-E08)"
}
