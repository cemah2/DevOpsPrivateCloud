# Projets reçus par leur nom (créés par RB-100, M10-E22).
data "openstack_identity_project_v3" "domaine" {
  name      = var.domaine
  is_domain = true
}

data "openstack_identity_project_v3" "p" {
  for_each  = var.projets
  name      = each.key
  domain_id = data.openstack_identity_project_v3.domaine.id
}

data "openstack_networking_network_v2" "externe" {
  name     = var.reseau_externe
  external = true
}

locals {
  etiquettes = ["tofu", "openstack-projets"]

  # Une règle SSH par (projet, réseau source).
  regles_ssh = {
    for paire in setproduct(keys(var.projets), var.sources_admin) :
    "${paire[0]}|${paire[1]}" => { projet = paire[0], source = paire[1] }
  }
}

# --- Quotas (la suppression de ces ressources ne fait rien côté OpenStack : no-op) ------------
resource "openstack_compute_quotaset_v2" "q" {
  for_each   = var.projets
  project_id = data.openstack_identity_project_v3.p[each.key].id
  instances  = each.value.quotas.instances
  cores      = each.value.quotas.cores
  ram        = each.value.quotas.ram
}

resource "openstack_blockstorage_quotaset_v3" "q" {
  for_each         = var.projets
  project_id       = data.openstack_identity_project_v3.p[each.key].id
  volumes          = each.value.quotas.volumes
  gigabytes        = each.value.quotas.gigabytes
  snapshots        = each.value.quotas.snapshots
  backups          = each.value.quotas.backups
  backup_gigabytes = each.value.quotas.backup_gigabytes
}

resource "openstack_networking_quota_v2" "q" {
  for_each            = var.projets
  project_id          = data.openstack_identity_project_v3.p[each.key].id
  floatingip          = each.value.quotas.floatingip
  network             = each.value.quotas.network
  subnet              = each.value.quotas.subnet
  router              = each.value.quotas.router
  security_group      = each.value.quotas.security_group
  security_group_rule = each.value.quotas.security_group_rule
  port                = each.value.quotas.port
}

# --- Réseau de chaque projet (propriété du projet : tenant_id) --------------------------------
resource "openstack_networking_network_v2" "net" {
  for_each       = var.projets
  name           = "${each.key}-net"
  description    = "Réseau applicatif de ${each.key} (géré par OpenTofu, envs/openstack-projets)"
  tenant_id      = data.openstack_identity_project_v3.p[each.key].id
  admin_state_up = true
  tags           = local.etiquettes
}

resource "openstack_networking_subnet_v2" "sr" {
  for_each        = var.projets
  name            = "${each.key}-sousreseau"
  network_id      = openstack_networking_network_v2.net[each.key].id
  tenant_id       = data.openstack_identity_project_v3.p[each.key].id
  cidr            = each.value.cidr
  ip_version      = 4
  dns_nameservers = var.dns
  tags            = local.etiquettes
}

resource "openstack_networking_router_v2" "r" {
  for_each            = var.projets
  name                = "${each.key}-routeur"
  description         = "Routeur de ${each.key} vers ${var.reseau_externe} (géré par OpenTofu)"
  tenant_id           = data.openstack_identity_project_v3.p[each.key].id
  external_network_id = data.openstack_networking_network_v2.externe.id
  tags                = local.etiquettes
}

resource "openstack_networking_router_interface_v2" "ri" {
  for_each  = var.projets
  router_id = openstack_networking_router_v2.r[each.key].id
  subnet_id = openstack_networking_subnet_v2.sr[each.key].id
}

# --- Groupe de sécurité d'administration ---------------------------------------------------------
resource "openstack_networking_secgroup_v2" "admin" {
  for_each    = var.projets
  name        = "${each.key}-admin"
  description = "SSH depuis MGMT (géré par OpenTofu)"
  tenant_id   = data.openstack_identity_project_v3.p[each.key].id
  tags        = local.etiquettes
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  for_each          = local.regles_ssh
  description       = "SSH depuis ${each.value.source}"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value.source
  security_group_id = openstack_networking_secgroup_v2.admin[each.value.projet].id
  tenant_id         = data.openstack_identity_project_v3.p[each.value.projet].id
}
