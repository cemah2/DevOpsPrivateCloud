# rocky10-base/build.pkr.hcl — Rocky Linux 10 installée depuis l'ISO « boot » par kickstart (M03-E06).
# Produit le template 9002 « tpl-rocky10-base ».
#
# Lancement (depuis ce dossier, sur adm01) :
#   set -a; . ~/.config/workbook/pve-packer.env; set +a
#   export PKR_VAR_build_password="$(openssl rand -base64 24)"
#   packer init . && packer build -force -var-file=../vars/lab.pkrvars.hcl .

packer {
  required_version = ">= 1.16.0"
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1.2.4"
    }
  }
}

locals {
  build_username = "packer"
  build_date     = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
}

source "proxmox-iso" "rocky10" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = false
  node                     = var.proxmox_node
  pool                     = var.pool
  task_timeout             = "10m"

  vm_id         = var.vm_id
  vm_name       = "tpl-rocky10-base"
  template_name = "tpl-rocky10-base"
  tags          = "base;rocky10"
  template_description = join("\n", [
    "Rocky Linux 10 de base installée depuis ${var.iso_name} (sha256 ${var.iso_sha256}).",
    "Construite le ${local.build_date} par Packer ${packer.version} — projet plateforme/images.",
  ])

  os              = "l26"
  cpu_type        = var.cpu_type # x86-64-v3 minimum : sinon panique du noyau au démarrage
  cores           = 2
  memory          = 2048 # Anaconda en mode texte depuis le réseau : 2 Go conseillés
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true
  serials         = ["socket"]
  vga {
    type = "std"
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

  boot_iso {
    type     = "ide"
    index    = "2"
    iso_file = "${var.storage_iso}:iso/${var.iso_name}"
    unmount  = true
  }

  cloud_init              = true
  cloud_init_storage_pool = var.storage_vm

  http_content = {
    "/ks.cfg" = templatefile("${path.root}/http/ks.cfg", {
      build_username = local.build_username
      build_password = var.build_password
    })
  }
  http_bind_address = var.http_bind_address
  http_port_min     = var.http_port_min
  http_port_max     = var.http_port_max

  # Menu GRUB 2 de l'ISO (BIOS) : l'entrée par défaut est « Test this media & install ».
  # <up> sélectionne « Install Rocky Linux 10.x », « e » ouvre l'éditeur ; la 3e ligne est
  # « linux /images/pxeboot/vmlinuz … quiet » ; Ctrl-x démarre l'entrée modifiée.
  boot_wait = "10s"
  boot_command = [
    "<up><wait>e<wait>",
    "<down><down><end>",
    " inst.text inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    "<leftCtrlOn>x<leftCtrlOff>",
  ]

  communicator = "ssh"
  ssh_username = local.build_username
  ssh_password = var.build_password
  ssh_timeout  = "45m"
}

build {
  name    = "rocky10-base"
  sources = ["source.proxmox-iso.rocky10"]

  provisioner "shell" {
    execute_command = "chmod +x '{{ .Path }}'; sudo env {{ .Vars }} '{{ .Path }}'"
    inline = [
      "cat /etc/rocky-release",
      "systemctl is-active qemu-guest-agent",
      "getenforce",
      "cloud-init --version",
      "passwd -l ${local.build_username}",
    ]
  }
}
