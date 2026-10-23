# infoger.tf — les trois VMs migrées de l'export VMware d'InfoGér (F4-S10, CHG-3410).
#
# Ces VMs ont été CRÉÉES par « qm importovf » puis converties (RB-345, convertir-vm-infoger.sh) :
# elles ne viennent pas d'un modèle, le module vm-debian ne leur convient pas (il clone). On décrit donc
# la ressource du fournisseur directement, telle qu'elle EST, puis on l'importe (imports.tf). Point de
# départ obtenu par « tofu plan -generate-config-out=genere.tf », nettoyé jusqu'au plan vide.
#
# ⚠️ Non testé en conditions réelles : selon la version exacte de bpg/proxmox 0.116.x, quelques
# attributs relus diffèrent de ce qu'on écrit (format du disque importé, ordre des étiquettes,
# description). La règle : corriger la configuration pour qu'elle DÉCRIVE la réalité ; n'ajouter à
# ignore_changes que ce que le fournisseur ne sait pas relire, avec un commentaire.

locals {
  vms_infoger = {
    "legacy-rdv01" = { vmid = 3401, ipv4 = "10.10.20.44", mac = "BC:24:11:20:34:01", coeurs = 2, memoire_mo = 2048, efi = true, role = "role-legacy" }
    "ftp-part01"   = { vmid = 3402, ipv4 = "10.10.20.45", mac = "BC:24:11:20:34:02", coeurs = 1, memoire_mo = 1024, efi = true, role = "role-ftp" }
    "stats01"      = { vmid = 3403, ipv4 = "10.10.20.46", mac = "BC:24:11:20:34:03", coeurs = 1, memoire_mo = 1024, efi = false, role = "role-stats" }
  }
}

resource "proxmox_virtual_environment_vm" "infoger" {
  for_each = local.vms_infoger

  name        = each.key
  node_name   = var.noeud
  vm_id       = each.value.vmid
  pool_id     = "lab"
  description = "VM migrée de l'export VMware d'InfoGér (CHG-3410). Gérée par OpenTofu (envs/f4-infoger)."
  tags        = sort(["env-f4", each.value.role])
  on_boot     = true
  started     = true

  # Micrologiciel de l'origine : EFI sans Secure Boot pour legacy-rdv01 et ftp-part01, BIOS pour stats01.
  bios = each.value.efi ? "ovmf" : "seabios"
  dynamic "efi_disk" {
    for_each = each.value.efi ? [1] : []
    content {
      datastore_id      = "local-nvme"
      type              = "4m"
      pre_enrolled_keys = false
    }
  }

  operating_system {
    type = "l26"
  }
  cpu {
    cores = each.value.coeurs
    type  = "x86-64-v2-AES"
  }
  memory {
    dedicated = each.value.memoire_mo
  }
  scsi_hardware = "virtio-scsi-single"
  agent {
    enabled = true
  }
  serial_device {}
  vga {
    type = "serial0"
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-nvme"
    size         = 8
    ssd          = true
    iothread     = true
    discard      = "on"
    file_format  = "raw"
  }

  network_device {
    bridge      = "vinfra"
    model       = "virtio"
    mac_address = each.value.mac
  }

  lifecycle {
    # Le disque contient des données qui n'existent nulle part ailleurs (sauf PBS) : une erreur de
    # configuration ne doit jamais pouvoir recréer la VM. Décommissionnement (F4-S14) : on retire
    # d'abord ce verrou dans une MR dédiée.
    prevent_destroy = true
  }
}

data "netbox_cluster" "cluster" {
  name = var.netbox_cluster
}

resource "netbox_virtual_machine" "infoger" {
  for_each = local.vms_infoger

  name         = each.key
  cluster_id   = data.netbox_cluster.cluster.id
  status       = "active"
  vcpus        = each.value.coeurs
  memory_mb    = each.value.memoire_mo
  disk_size_mb = 8 * 1024
  tags         = ["env-f4", each.value.role]
  comments     = "Migrée de l'export VMware d'InfoGér (CHG-3410). Debian 12 : fin de vie décidée en F4-S14."

  lifecycle {
    # vmid : écrit par la synchronisation Proxmox → NetBox (M06-E11), Proxmox fait foi.
    ignore_changes = [custom_fields]
  }
}

resource "netbox_interface" "infoger" {
  for_each = local.vms_infoger

  name               = "ens18"
  virtual_machine_id = netbox_virtual_machine.infoger[each.key].id
}

resource "netbox_ip_address" "infoger" {
  for_each = local.vms_infoger

  ip_address                   = "${each.value.ipv4}/24"
  virtual_machine_interface_id = netbox_interface.infoger[each.key].id
  status                       = "active"
  dns_name                     = "${each.key}.par1.medisphere.internal"
  description                  = "Adresse du plan (PLAN.md §4.14) pour ${each.key} (ex-192.168.50.x chez InfoGér)"
}

resource "netbox_primary_ip" "infoger" {
  for_each = local.vms_infoger

  virtual_machine_id = netbox_virtual_machine.infoger[each.key].id
  ip_address_id      = netbox_ip_address.infoger[each.key].id
}

module "dns_infoger" {
  source   = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//enregistrement-dns?ref=<VERSION-TOFU-MODULES>"
  for_each = local.vms_infoger

  nom  = "${each.key}.par1.medisphere.internal"
  ipv4 = each.value.ipv4
  ttl  = 300
}

# Nom des cabinets : CNAME vers la VIP des répartiteurs (comme sso, gitlab, netbox au M07/M24).
resource "powerdns_record" "rdv" {
  zone     = "par1.medisphere.internal."
  name     = "rdv.par1.medisphere.internal."
  type     = "CNAME"
  ttl      = 300
  records  = ["lb.par1.medisphere.internal."]
  comments = ["gere-par=opentofu (plateforme/infra, envs/f4-infoger)"]
}

output "vms_infoger" {
  description = "VMs migrées : VMID, adresse."
  value       = { for nom, v in local.vms_infoger : nom => { vmid = v.vmid, ipv4 = v.ipv4 } }
}
