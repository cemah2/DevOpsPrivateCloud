# debian13-base/build.pkr.hcl — Debian 13 installée depuis l'ISO netinst par preseed (M03-E05).
# Produit le template 9001 « tpl-debian13-base », reconstruit à l'identique à chaque build.
#
# Lancement (depuis ce dossier, sur adm01) :
#   set -a; . ~/.config/workbook/pve-packer.env; set +a
#   export PKR_VAR_build_password="$(openssl rand -base64 24)"
#   packer init . && packer validate -var-file=../vars/lab.pkrvars.hcl .
#   packer build -force -var-file=../vars/lab.pkrvars.hcl .
# (-force supprime d'abord la VM qui porte vm_id : voir l'avertissement de l'énoncé.)

packer {
  required_version = ">= 1.16.0"
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1.2.4" # >= 1.2.4 et < 1.3.0 : Packer n'a pas de fichier de verrouillage
    }
  }
}

locals {
  build_username = "packer"
  build_date     = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
}

source "proxmox-iso" "debian13" {
  # --- Connexion à l'API : jeton dédié, TLS vérifié (ancre de pve01 dans le magasin système)
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = false
  node                     = var.proxmox_node
  pool                     = var.pool
  task_timeout             = "10m"

  # --- Identité du template
  vm_id         = var.vm_id
  vm_name       = "tpl-debian13-base"
  template_name = "tpl-debian13-base"
  tags          = "base;debian13"
  template_description = join("\n", [
    "Debian 13 de base installée depuis ${var.iso_name} (sha256 ${var.iso_sha256}).",
    "Construite le ${local.build_date} par Packer ${packer.version} — projet plateforme/images.",
  ])

  # --- Matériel (les valeurs par défaut du plugin ne conviennent pas : kvm64, lsi, 512 Mo)
  os              = "l26"
  cpu_type        = "x86-64-v2-AES"
  cores           = 2
  memory          = 2048
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true
  serials         = ["socket"]
  vga {
    type = "std" # écran visible dans la console noVNC pendant l'installation
  }

  disks {
    type         = "scsi"
    storage_pool = var.storage_vm
    disk_size    = "8G"
    format       = "raw"
    io_thread    = true
    discard      = true
    ssd          = true
  }

  network_adapters {
    model    = "virtio"
    bridge   = var.build_bridge
    firewall = false
  }

  # --- ISO déposée et vérifiée à l'avance (outils/deposer-iso.sh), retirée à la fin
  boot_iso {
    type     = "ide"
    index    = "2"
    iso_file = "${var.storage_iso}:iso/${var.iso_name}"
    unmount  = true
  }

  # --- Lecteur cloud-init vide ajouté au template (les clones et les builds dorés en ont besoin)
  cloud_init              = true
  cloud_init_storage_pool = var.storage_vm

  # --- Serveur HTTP de Packer : sert le preseed (avec le mot de passe jetable) et le script final
  http_content = {
    "/preseed.cfg" = templatefile("${path.root}/http/preseed.cfg", {
      build_username = local.build_username
      build_password = var.build_password
    })
    "/late-command.sh" = file("${path.root}/http/late-command.sh")
  }
  http_bind_address = var.http_bind_address
  http_port_min     = var.http_port_min
  http_port_max     = var.http_port_max

  # --- Menu isolinux de l'ISO (BIOS) : Échap donne l'invite « boot: », « auto » = installation automatisée
  boot_wait = "10s"
  boot_command = [
    "<esc><wait2>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "hostname=tpl-debian13-base domain=par1.medisphere.internal interface=auto",
    "<enter>",
  ]

  # --- Communicateur : l'adresse IP est lue par l'agent QEMU, l'installation dure 10 à 25 min
  communicator = "ssh"
  ssh_username = local.build_username
  ssh_password = var.build_password
  ssh_timeout  = "45m"
}

build {
  name    = "debian13-base"
  sources = ["source.proxmox-iso.debian13"]

  # Contrôles de l'installation, puis verrouillage du compte de construction.
  # (M03-E07 remplace ce bloc par la préparation complète au clonage.)
  provisioner "shell" {
    execute_command = "chmod +x '{{ .Path }}'; sudo env {{ .Vars }} '{{ .Path }}'"
    inline = [
      "grep PRETTY_NAME /etc/os-release",
      "systemctl is-active qemu-guest-agent",
      "systemctl is-enabled systemd-networkd systemd-resolved",
      "readlink /etc/resolv.conf",
      "cloud-init --version",
      "test ! -x /usr/sbin/ifup",
      "passwd -l ${local.build_username}",
    ]
  }
}
