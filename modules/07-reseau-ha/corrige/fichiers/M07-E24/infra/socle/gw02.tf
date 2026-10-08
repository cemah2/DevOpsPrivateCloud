# socle/gw02.tf — plateforme/infra, état « socle » (M07-E24, ticket PLAT-850).
#
# gw02 : seconde passerelle de la bordure PAR1. VMID 1009 (PLAN §4.5), .3 sur chaque VLAN routé.
# Pourquoi pas le module vm-debian : il ne connaît qu'UNE carte, sur un VNet SDN, avec UNE adresse
# allouée dans un préfixe NetBox. Une passerelle a une carte WAN (vmbr0, LAN maison) et une carte
# trunk (vmbr1 sans étiquette, sous-interfaces VLAN dans l'invité) : on écrit donc la VM et ses
# objets NetBox directement, sur le modèle du module (intention dans NetBox AVANT la VM).
#
# Droits de wb-tofu : rattacher une carte à un pont HORS SDN demande SDN.Use sur
# /sdn/zones/localnetwork/<pont> (Proxmox VE 8+). Voir le corrigé (pveum acl modify).
#
# Valeurs à adapter dans terraform.tfvars : ip_gw02_wan (<IP-GW02-WAN>), lan_maison_longueur
# (<MASQUE>), ip_box (<IP-BOX>).

variable "ip_gw02_wan" {
  description = "Adresse WAN de gw02 sur le LAN maison (<IP-GW02-WAN>), sans masque."
  type        = string
}

variable "lan_maison_longueur" {
  description = "Longueur du préfixe du LAN maison (<MASQUE>, souvent 24)."
  type        = number
  default     = 24
}

variable "ip_box" {
  description = "Passerelle du LAN maison (<IP-BOX>)."
  type        = string
}

locals {
  # VLAN routés (PLAN §4.2) : gw02 y porte .3. Les VLAN 31, 32, 41, 51 ne sont pas routés.
  gw02_vlans = [10, 20, 30, 40, 50, 52, 60, 70, 99]
  # MTU des sous-interfaces (PLAN §4.9, M07-E15) : 9000 sur 30 (31 et 51 ne sont pas routés).
  gw02_mtu = { for v in local.gw02_vlans : v => (v == 30 ? 9000 : 1500) }
}

# --- L'intention dans NetBox ------------------------------------------------------------------

data "netbox_cluster" "pve01" {
  name = "pve01"
}

resource "netbox_virtual_machine" "gw02" {
  name         = "gw02"
  cluster_id   = data.netbox_cluster.pve01.id
  status       = "active"
  vcpus        = 1
  memory_mb    = 1024
  disk_size_mb = 10 * 1024
  tags         = ["socle", "role-routeur"]
  comments     = "Seconde passerelle de la bordure PAR1 (M07-E24). VRRP avec gw01 à partir de M07-E25."

  lifecycle {
    # vmid écrit par la synchronisation Proxmox → NetBox (M06-E11), comme dans vm-debian.
    ignore_changes = [custom_fields]
  }
}

resource "netbox_interface" "gw02_wan" {
  name               = "ens18"
  virtual_machine_id = netbox_virtual_machine.gw02.id
  description        = "WAN (vmbr0, LAN maison)"
}

resource "netbox_interface" "gw02_trunk" {
  name               = "ens19"
  virtual_machine_id = netbox_virtual_machine.gw02.id
  description        = "Trunk (vmbr1 sans étiquette)"
  mtu                = 9000
}

resource "netbox_interface" "gw02_vlan" {
  for_each           = toset([for v in local.gw02_vlans : tostring(v)])
  name               = "ens19.${each.key}"
  virtual_machine_id = netbox_virtual_machine.gw02.id
  mtu                = local.gw02_mtu[tonumber(each.key)]
  description        = "VLAN ${each.key}, sous-interface de ens19"
  # Le modèle NetBox a un champ « parent » (ens19), que le fournisseur e-breuninger/netbox n'expose
  # pas pour netbox_interface : rattachement par l'API (PATCH virtualization/interfaces/<id>/) ou à
  # la main, noté dans la MR.
}

# Adresses imposées par le plan (.3) : jamais allouées « à la première libre ».
resource "netbox_ip_address" "gw02_vlan" {
  for_each                     = netbox_interface.gw02_vlan
  ip_address                   = "10.10.${each.key}.3/24"
  virtual_machine_interface_id = each.value.id
  status                       = "active"
  # Seule l'adresse MGMT porte le nom (PTR) : un nom, une adresse principale.
  dns_name    = each.key == "10" ? "gw02.par1.medisphere.internal" : null
  description = "gw02 : adresse propre du VLAN ${each.key} (PLAN §4.9)"
}

resource "netbox_primary_ip" "gw02" {
  virtual_machine_id = netbox_virtual_machine.gw02.id
  ip_address_id      = netbox_ip_address.gw02_vlan["10"].id
}

# --- La VM -------------------------------------------------------------------------------------

data "proxmox_virtual_environment_vms" "image_courante" {
  tags = ["gold", "debian13", "current"]
  filter {
    name   = "template"
    values = ["true"]
  }
}

resource "proxmox_virtual_environment_vm" "gw02" {
  name        = "gw02"
  node_name   = var.noeud
  vm_id       = 1009
  pool_id     = "lab"
  description = "Seconde passerelle de la bordure PAR1 (M07-E24). Configurée par Ansible (playbooks/routeurs.yml)."
  tags        = ["role-routeur", "socle"]
  on_boot     = true
  started     = true

  # Démarre avec gw01 (ordre 1) : les passerelles avant les services du socle.
  startup {
    order = 1
  }

  clone {
    vm_id        = data.proxmox_virtual_environment_vms.image_courante.vms[0].vm_id
    node_name    = data.proxmox_virtual_environment_vms.image_courante.vms[0].node_name
    full         = true
    datastore_id = "local-nvme"
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = "local-nvme"
    interface    = "scsi0"
    size         = 10
    discard      = "on"
    iothread     = true
  }

  # Noms dans l'invité : l'image dorée nomme les cartes eth0, eth1 (configuration réseau cloud-init
  # de Proxmox, M03). gw01 (installée depuis l'ISO) a ens18/ens19, et la matrice des flux commune
  # (pare_feu), keepalived et conntrackd désignent les interfaces par leur NOM : gw02 doit porter
  # les MÊMES. Les adresses MAC sont donc fixées ici, et le rôle routeur_reseau renomme les cartes
  # par leur MAC (host_vars/gw02/routeur_reseau.yml, mêmes valeurs).
  # net0 → ens18 : WAN, sur le pont du LAN maison.
  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:10:09:00"
  }

  # net1 → ens19 : trunk, SANS étiquette (les VLAN sont des sous-interfaces dans l'invité),
  # MTU 9000 comme vmbr1 et le trunk de gw01 (M07-E15).
  network_device {
    bridge      = "vmbr1"
    model       = "virtio"
    mac_address = "BC:24:11:10:09:01"
    mtu         = 9000
  }

  serial_device {}

  operating_system {
    type = "l26"
  }

  # cloud-init ne configure QUE le WAN (premier ip_config = net0) : de quoi joindre la VM
  # depuis le LAN maison et adm01 (par gw01), puis Ansible (rôle routeur_reseau) fait le reste.
  initialization {
    datastore_id = "local-nvme"
    ip_config {
      ipv4 {
        address = "${var.ip_gw02_wan}/${var.lan_maison_longueur}"
        gateway = var.ip_box
      }
    }
    dns {
      domain  = "par1.medisphere.internal"
      servers = ["10.10.20.10", "10.10.20.16"]
    }
    user_account {
      username = "admin"
      keys     = [var.cle_ssh_admin]
    }
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [clone]
  }

  # L'intention existe avant la VM (et lui survit à la destruction).
  depends_on = [netbox_primary_ip.gw02]
}

check "une_seule_image_courante_gw02" {
  assert {
    condition     = length(data.proxmox_virtual_environment_vms.image_courante.vms) == 1
    error_message = "Il faut exactement un template gold/debian13/current (M03)."
  }
}

# --- Nom -----------------------------------------------------------------------------------------

module "dns_gw02" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"

  nom  = "gw02.par1.medisphere.internal"
  ipv4 = "10.10.10.3"
  ttl  = 3600
}

output "gw02" {
  description = "Identité de gw02."
  value = {
    vmid = proxmox_virtual_environment_vm.gw02.vm_id
    mgmt = "10.10.10.3"
    wan  = var.ip_gw02_wan
  }
}
