output "url" {
  description = "Point d'entrée HTTP de l'application (IP flottante du répartiteur)."
  value       = "http://${openstack_networking_floatingip_v2.lb.address}/"
}

output "ip_flottante" {
  description = "IP flottante du répartiteur."
  value       = openstack_networking_floatingip_v2.lb.address
}

output "instances" {
  description = "Instances et leur adresse privée."
  value       = { for i, inst in openstack_compute_instance_v2.app : inst.name => openstack_networking_port_v2.app[i].all_fixed_ips[0] }
}

output "acces_admin" {
  description = "IP flottante d'administration temporaire (vide si acces_admin = false)."
  value       = var.acces_admin ? openstack_networking_floatingip_v2.admin[0].address : ""
}
