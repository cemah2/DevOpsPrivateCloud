mock_provider "proxmox" {
  mock_data "proxmox_virtual_environment_vms" {
    defaults = {
      vms = [{ vm_id = 9011, node_name = "pve01", name = "deb13-gold", status = "stopped", tags = ["current"], template = true }]
    }
  }
}
mock_provider "netbox" {
  mock_data "netbox_cluster" {
    defaults = { id = "1" }
  }
  mock_resource "netbox_virtual_machine" {
    defaults = { id = "10" }
  }
  mock_resource "netbox_interface" {
    defaults = { id = "20" }
  }
  mock_resource "netbox_ip_address" {
    defaults = { id = "30" }
  }
}

variables {
  nom           = "ctr01"
  vmid          = 2121
  noeud         = "pve01"
  famille       = "debian13"
  etiquettes    = ["env-m12", "role-docker"]
  cle_ssh_admin = "ssh-ed25519 AAAA test"
}

run "dhcp" {
  command = plan
  variables {
    cartes = [{ vnet = "vsandbox", ipv4 = "dhcp", mac = "bc:24:11:99:12:01" }]
  }
  assert {
    condition     = length(netbox_ip_address.carte) == 0 && length(netbox_primary_ip.ip) == 0
    error_message = "DHCP : aucune adresse NetBox attendue"
  }
  assert {
    condition     = output.dhcp && output.ipv4 == null
    error_message = "sorties DHCP"
  }
}

run "statique_m08" {
  command = plan
  variables {
    famille = "rocky10"
    cartes = [
      { vnet = "vstopub", prefixe = "10.10.30.0/24", ipv4 = "10.10.30.51", mtu = 9000, passerelle = true },
      { vnet = "vstoclu", prefixe = "10.10.31.0/24", ipv4 = "10.10.31.51", mtu = 9000 },
      { vnet = "vosext" },
    ]
  }
  assert {
    condition     = length(netbox_ip_address.carte) == 2 && length(netbox_primary_ip.ip) == 1 && netbox_ip_address.carte[1].ip_address == "10.10.31.51/24"
    error_message = "statique : deux adresses, une IP primaire"
  }
  assert {
    condition     = output.ipv4 == "10.10.30.51" && !output.dhcp
    error_message = "sorties statiques"
  }
}

run "dhcp_avec_prefixe_refuse" {
  command = plan
  variables {
    cartes = [{ vnet = "vsandbox", ipv4 = "dhcp", prefixe = "10.10.99.0/24" }]
  }
  expect_failures = [var.cartes]
}

run "dhcp_passerelle_refusee" {
  command = plan
  variables {
    cartes = [{ vnet = "vsandbox", ipv4 = "dhcp", passerelle = true }]
  }
  expect_failures = [var.cartes]
}
