# main.tf — module openstack-env-app (M10-E31, DEV-1157) : un environnement d'application en
# libre-service dans UN projet OpenStack : réseau, routeur, groupes de sécurité, N instances
# web, volume de données, répartiteur Octavia (fournisseur OVN, TCP 80) et son IP flottante.
# Rien n'est créé hors du projet des identifiants utilisés (rôle member suffit).

locals {
  etiquettes = distinct(concat(["libre-service", var.prefixe], var.etiquettes))
  noms       = [for i in range(var.nombre_instances) : format("%s-app%02d", var.prefixe, i + 1)]
}

data "openstack_networking_network_v2" "externe" {
  name     = var.reseau_externe
  external = true
}

data "openstack_images_image_v2" "image" {
  name        = var.image
  most_recent = true
}

data "openstack_compute_flavor_v2" "gabarit" {
  name = var.gabarit
}

# --- Réseau -----------------------------------------------------------------------------------

resource "openstack_networking_network_v2" "net" {
  name           = "${var.prefixe}-net"
  admin_state_up = true
  tags           = local.etiquettes
}

resource "openstack_networking_subnet_v2" "sn" {
  name            = "${var.prefixe}-sn"
  network_id      = openstack_networking_network_v2.net.id
  cidr            = var.cidr
  ip_version      = 4
  dns_nameservers = var.dns
  tags            = local.etiquettes
}

resource "openstack_networking_router_v2" "rt" {
  name                = "${var.prefixe}-rt"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.externe.id
  tags                = local.etiquettes
}

resource "openstack_networking_router_interface_v2" "rt_sn" {
  router_id = openstack_networking_router_v2.rt.id
  subnet_id = openstack_networking_subnet_v2.sn.id
}

# --- Groupes de sécurité ------------------------------------------------------------------------
# Fournisseur OVN : PAS de traduction d'adresse. Les instances voient l'adresse des CLIENTS ;
# les contrôles de santé partent d'une adresse du sous-réseau des membres (port de contrôle de
# santé créé par le fournisseur). Les deux doivent être autorisés sur le port 80.

resource "openstack_networking_secgroup_v2" "app" {
  name        = "${var.prefixe}-app"
  description = "HTTP 80 depuis les clients autorisés et les contrôles de santé (libre-service)"
  tags        = local.etiquettes
}

resource "openstack_networking_secgroup_rule_v2" "app_clients" {
  for_each          = toset(var.clients_http)
  security_group_id = openstack_networking_secgroup_v2.app.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = each.value
  description       = "clients HTTP ${each.value}"
}

resource "openstack_networking_secgroup_rule_v2" "app_sante" {
  security_group_id = openstack_networking_secgroup_v2.app.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = var.cidr
  description       = "contrôles de santé du fournisseur OVN (adresse du sous-réseau)"
}

resource "openstack_networking_secgroup_v2" "admin" {
  name        = "${var.prefixe}-admin"
  description = "SSH et ICMP depuis MGMT et le VPN d'administration (libre-service)"
  tags        = local.etiquettes
}

resource "openstack_networking_secgroup_rule_v2" "admin_ssh" {
  for_each          = toset(var.cidr_admin)
  security_group_id = openstack_networking_secgroup_v2.admin.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
  description       = "SSH d'administration ${each.value}"
}

resource "openstack_networking_secgroup_rule_v2" "admin_icmp" {
  for_each          = toset(var.cidr_admin)
  security_group_id = openstack_networking_secgroup_v2.admin.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = each.value
  description       = "ICMP d'administration ${each.value}"
}

# --- Calcul ----------------------------------------------------------------------------------

resource "openstack_compute_keypair_v2" "cle" {
  name       = "${var.prefixe}-cle"
  public_key = var.cle_publique_ssh
}

# Anti-affinité « souple » : une instance par calcul quand c'est possible, sans échouer sinon.
resource "openstack_compute_servergroup_v2" "app" {
  name     = "${var.prefixe}-app"
  policies = ["soft-anti-affinity"]
}

resource "openstack_networking_port_v2" "app" {
  count              = var.nombre_instances
  name               = "${local.noms[count.index]}-port"
  network_id         = openstack_networking_network_v2.net.id
  security_group_ids = [openstack_networking_secgroup_v2.app.id, openstack_networking_secgroup_v2.admin.id]
  tags               = local.etiquettes

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.sn.id
  }
}

resource "openstack_blockstorage_volume_v3" "donnees" {
  name        = "${var.prefixe}-donnees"
  description = "Données de ${local.noms[0]} (libre-service)"
  size        = var.volume_taille
}

resource "openstack_compute_instance_v2" "app" {
  count     = var.nombre_instances
  name      = local.noms[count.index]
  flavor_id = data.openstack_compute_flavor_v2.gabarit.id
  key_pair  = openstack_compute_keypair_v2.cle.name
  tags      = local.etiquettes
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    titre     = var.page_titre
    volume_id = count.index == 0 ? openstack_blockstorage_volume_v3.donnees.id : ""
    montage   = var.point_de_montage
  })

  # Disque système depuis l'image (éphémère, pool « vms » de Ceph).
  block_device {
    uuid                  = data.openstack_images_image_v2.image.id
    source_type           = "image"
    destination_type      = "local"
    boot_index            = 0
    delete_on_termination = true
  }

  # Volume de données attaché AU DÉMARRAGE de la première instance : cloud-init le trouve
  # au premier boot (un attachement après coup arriverait après cloud-init).
  dynamic "block_device" {
    for_each = count.index == 0 ? [openstack_blockstorage_volume_v3.donnees.id] : []
    content {
      uuid                  = block_device.value
      source_type           = "volume"
      destination_type      = "volume"
      boot_index            = -1
      delete_on_termination = false
    }
  }

  network {
    port = openstack_networking_port_v2.app[count.index].id
  }

  scheduler_hints {
    group = openstack_compute_servergroup_v2.app.id
  }

  # Changer la page ou la clé ne doit pas détruire une instance qui porte des données.
  lifecycle {
    ignore_changes = [user_data, key_pair]
  }

  depends_on = [openstack_networking_router_interface_v2.rt_sn]
}

# --- Répartiteur (Octavia, fournisseur OVN : L4 seulement, SOURCE_IP_PORT seulement) ------------

resource "openstack_lb_loadbalancer_v2" "lb" {
  name                  = "${var.prefixe}-lb"
  vip_subnet_id         = openstack_networking_subnet_v2.sn.id
  loadbalancer_provider = "ovn"
  tags                  = local.etiquettes

  depends_on = [openstack_networking_router_interface_v2.rt_sn]
}

resource "openstack_lb_listener_v2" "http" {
  name            = "${var.prefixe}-http"
  loadbalancer_id = openstack_lb_loadbalancer_v2.lb.id
  protocol        = "TCP"
  protocol_port   = 80
}

resource "openstack_lb_pool_v2" "app" {
  name        = "${var.prefixe}-app"
  listener_id = openstack_lb_listener_v2.http.id
  protocol    = "TCP"
  lb_method   = "SOURCE_IP_PORT"
}

resource "openstack_lb_member_v2" "app" {
  count         = var.nombre_instances
  name          = local.noms[count.index]
  pool_id       = openstack_lb_pool_v2.app.id
  address       = openstack_networking_port_v2.app[count.index].all_fixed_ips[0]
  protocol_port = 80
  subnet_id     = openstack_networking_subnet_v2.sn.id
}

resource "openstack_lb_monitor_v2" "tcp" {
  name        = "${var.prefixe}-sante"
  pool_id     = openstack_lb_pool_v2.app.id
  type        = "TCP"
  delay       = 5
  timeout     = 3
  max_retries = 3
}

resource "openstack_networking_floatingip_v2" "lb" {
  pool        = var.reseau_externe
  description = "${var.prefixe} : point d'entrée HTTP (VIP du répartiteur)"
  tags        = local.etiquettes
}

resource "openstack_networking_floatingip_associate_v2" "lb" {
  floating_ip = openstack_networking_floatingip_v2.lb.address
  port_id     = openstack_lb_loadbalancer_v2.lb.vip_port_id
}

# --- Accès d'administration temporaire (acces_admin = true) --------------------------------------

resource "openstack_networking_floatingip_v2" "admin" {
  count       = var.acces_admin ? 1 : 0
  pool        = var.reseau_externe
  description = "${var.prefixe} : accès d'administration TEMPORAIRE à ${local.noms[0]}"
  tags        = local.etiquettes
}

resource "openstack_networking_floatingip_associate_v2" "admin" {
  count       = var.acces_admin ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.admin[0].address
  port_id     = openstack_networking_port_v2.app[0].id
}
