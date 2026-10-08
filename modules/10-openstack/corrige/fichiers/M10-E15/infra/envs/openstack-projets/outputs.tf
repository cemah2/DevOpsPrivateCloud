output "reseaux" {
  description = "Réseau, sous-réseau et routeur de chaque projet."
  value = {
    for k, v in var.projets : k => {
      projet_id   = data.openstack_identity_project_v3.p[k].id
      reseau      = openstack_networking_network_v2.net[k].id
      mtu         = openstack_networking_network_v2.net[k].mtu
      sous_reseau = openstack_networking_subnet_v2.sr[k].cidr
      routeur     = openstack_networking_router_v2.r[k].id
      passerelle  = openstack_networking_router_v2.r[k].external_fixed_ip
    }
  }
}
