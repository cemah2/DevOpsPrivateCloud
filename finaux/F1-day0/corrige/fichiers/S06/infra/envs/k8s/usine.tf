# envs/k8s/usine.tf — nœuds de k8s-par1 installés par l'USINE de provisioning (F1-S06, PLAT-3106).
#
# Un nœud listé dans var.noeuds_usine n'est PLUS créé par le module vm-noeud (clone de l'image dorée,
# noeuds.tf) mais ici, comme un serveur livré nu (même principe que envs/provisioning/bm.tf, M11-E03) :
# VM sans système, sans clone ni cloud-init, et son intention dans NetBox (plate-forme « k8s-noeud »)
# que lit la chaîne de plateforme/provisioning. Deux phases, une variable :
#
#   « installation »  carte net0 sur vprov (VLAN 60), démarrage réseau d'abord, VM ÉTEINTE : l'usine
#                     (job « provisionner ») l'allume, l'installe (preseed k8s-noeud) et la laisse
#                     éteinte, staged / pxe_action=local ;
#   « service »       net0 rebranchée sur vk8s (VLAN 40), carte de stockage (VLAN 30) des travailleurs,
#                     démarrage sur le disque SEULEMENT, VM démarrée par OpenTofu ; puis
#                     « provisionner.py <nœud> --apres-bascule » (clé d'hôte, vérification, active).
#
# Passer d'« installation » à « service » est une modification EN PLACE (le plan ne doit montrer aucun
# remplacement). Retirer un nœud de la liste le rend au module vm-noeud.
#
# ⚠️ Changer la façon de créer un nœud EXISTANT (vm-noeud → usine) détruit puis crée des ressources
# DIFFÉRENTES avec le même VMID, la même adresse et le même nom : OpenTofu peut tenter la création
# avant la destruction (« VM 2146 already exists », adresse en double dans NetBox). On ne le fait que
# sur un nœud déjà détruit (reconstruction, F1-S07), en deux applies : retrait, puis usine.
#
# Règles d'adressage (noeuds.tf, M14 ; M16) : suffixe = dernier octet de l'adresse VLAN 40 ;
# provisioning = 10.10.60.<100 + suffixe> (plage 10.10.60.100-199 de Kea, réservée par le rendu de
# l'usine) ; MAC net0 bc:24:11:40:00:<suffixe> (la même dans les deux phases : réservation Kea et
# script iPXE sont indexés par elle).

locals {
  usine = { for nom, phase in var.noeuds_usine : nom => merge(local.noeuds[nom], { phase = phase }) }

  # Travailleurs de l'usine en service : carte de stockage comme les autres (M16-E05).
  usine_stockage = {
    for nom, n in local.usine : nom => n
    if n.phase == "service" && n.etiquette_role == "role-k8s-worker" && lookup(local.stockage_actif, nom, false)
  }
}

data "netbox_cluster" "usine" {
  count = length(local.usine) > 0 ? 1 : 0
  name  = "pve01"
}

data "netbox_platform" "k8s_noeud" {
  count = length(local.usine) > 0 ? 1 : 0
  name  = "k8s-noeud"
}

# --- NetBox : l'intention, AVANT la VM ------------------------------------------------------------
resource "netbox_virtual_machine" "usine" {
  for_each = local.usine

  name         = each.key
  cluster_id   = data.netbox_cluster.usine[0].id
  platform_id  = data.netbox_platform.k8s_noeud[0].id
  status       = "planned"
  vcpus        = each.value.coeurs
  memory_mb    = each.value.memoire_mo
  disk_size_mb = each.value.disque_go * 1024
  tags         = ["env-k8s", each.value.etiquette_role]
  comments     = "${each.value.description} Installé par l'usine (profil k8s-noeud, F1-S06)."

  lifecycle {
    # Statut (planned → staged → active) et pxe_action appartiennent à l'usine (provisionner.py).
    ignore_changes = [status, custom_fields]
  }
}

resource "netbox_interface" "usine_ens18" {
  for_each = local.usine

  name               = "ens18"
  virtual_machine_id = netbox_virtual_machine.usine[each.key].id
}

resource "netbox_mac_address" "usine_ens18" {
  for_each = local.usine

  mac_address                  = upper(local.carte_k8s[each.key].mac)
  virtual_machine_interface_id = netbox_interface.usine_ens18[each.key].id
}

resource "netbox_ip_address" "usine_service" {
  for_each = local.usine

  ip_address                   = "${local.carte_k8s[each.key].ipv4}/24"
  virtual_machine_interface_id = netbox_interface.usine_ens18[each.key].id
  status                       = "active"
  dns_name                     = "${each.key}.par1.medisphere.internal"
  description                  = "Adresse de service de ${each.key} (PLAN §4.10), écrite par l'installateur"
}

resource "netbox_ip_address" "usine_provisioning" {
  for_each = local.usine

  ip_address                   = "10.10.60.${100 + each.value.suffixe}/24"
  virtual_machine_interface_id = netbox_interface.usine_ens18[each.key].id
  status                       = "reserved"
  description                  = "Provisioning de ${each.key} (VLAN 60, réservation Kea rendue par l'usine)"
}

resource "netbox_primary_ip" "usine" {
  for_each = local.usine

  virtual_machine_id = netbox_virtual_machine.usine[each.key].id
  ip_address_id      = netbox_ip_address.usine_service[each.key].id
}

resource "netbox_interface" "usine_ens19" {
  for_each = local.usine_stockage

  name               = "ens19"
  virtual_machine_id = netbox_virtual_machine.usine[each.key].id
}

resource "netbox_ip_address" "usine_stockage" {
  for_each = local.usine_stockage

  ip_address                   = "${local.carte_stockage[each.key].ipv4}/24"
  virtual_machine_interface_id = netbox_interface.usine_ens19[each.key].id
  status                       = "active"
  description                  = "STOR-PUB de ${each.key} (M16-E05), configurée par le rôle k8s_reseau_stockage"
}

# --- Proxmox : le « serveur livré » ---------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "usine" {
  for_each = local.usine

  name        = each.key
  node_name   = var.noeud
  vm_id       = each.value.vmid
  pool_id     = "lab"
  description = "${each.value.description}\nInstallé par l'usine (profil k8s-noeud, F1-S06), phase ${each.value.phase}. Géré par OpenTofu (envs/k8s/usine.tf)."
  tags        = sort(["env-k8s", each.value.etiquette_role])
  on_boot     = false # cluster arrêtable (PLAN §4.10), comme les nœuds clonés
  # Installation : éteinte, l'usine pilote l'alimentation. Service : démarrée par OpenTofu.
  started = each.value.phase == "service"

  bios = "seabios"
  # Installation : le réseau d'abord (disque vide). Service : le disque SEULEMENT (un nœud en service ne
  # démarre jamais sur le réseau, même si quelqu'un lui sert un script d'installation par erreur).
  boot_order    = each.value.phase == "installation" ? ["net0", "scsi0"] : ["scsi0"]
  scsi_hardware = "virtio-scsi-single"

  cpu {
    cores = each.value.coeurs
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = each.value.memoire_mo
  }
  agent {
    enabled = true # installé par le preseed ; sert à confirmer la clé d'hôte (provisionner.py)
  }
  disk {
    datastore_id = "local-nvme"
    interface    = "scsi0"
    size         = each.value.disque_go
    ssd          = true
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge      = each.value.phase == "installation" ? "vprov" : "vk8s"
    model       = "virtio"
    mac_address = upper(local.carte_k8s[each.key].mac)
    firewall    = false
  }

  dynamic "network_device" {
    for_each = contains(keys(local.usine_stockage), each.key) ? [local.carte_stockage[each.key]] : []
    content {
      bridge      = network_device.value.vnet
      model       = "virtio"
      mac_address = upper(network_device.value.mac)
      mtu         = network_device.value.mtu
      firewall    = false
    }
  }

  serial_device {}
  vga {
    type = "serial0"
  }
  operating_system {
    type = "l26"
  }

  depends_on = [netbox_primary_ip.usine, netbox_ip_address.usine_provisioning]
}

module "dns_usine" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=v2.1.0"
  for_each = local.usine

  nom  = "${each.key}.par1.medisphere.internal"
  ipv4 = local.carte_k8s[each.key].ipv4
}

output "noeuds_usine" {
  description = "Nœuds installés par l'usine : VMID, phase, adresses de service et de provisioning."
  value = { for nom, n in local.usine : nom => {
    vmid         = n.vmid
    phase        = n.phase
    service      = local.carte_k8s[nom].ipv4
    provisioning = "10.10.60.${100 + n.suffixe}"
  } }
}
