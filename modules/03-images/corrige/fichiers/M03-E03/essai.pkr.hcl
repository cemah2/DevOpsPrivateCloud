# essai.pkr.hcl — premier build Packer : proxmox-clone depuis tpl-debian13 (M03-E03).
# Brouillon d'exercice (~/m03/e03/, non versionné). Produit le template d'essai 9090.
#
#   set -a; . ~/.config/workbook/pve-packer.env; set +a
#   packer init . && packer validate . && packer build .

packer {
  required_version = ">= 1.16.0"
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1.2.4"
    }
  }
}

variable "proxmox_url" {
  type = string
}
variable "proxmox_username" {
  type = string
}
variable "proxmox_token" {
  type      = string
  sensitive = true
}
variable "proxmox_node" {
  type = string
}

source "proxmox-clone" "essai" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = false
  node                     = var.proxmox_node
  pool                     = "lab"
  task_timeout             = "10m" # le clonage complet dépasse le délai par défaut (1 min)

  clone_vm_id = 9000 # tpl-debian13 (M00-E11)
  full_clone  = true

  vm_id                = 9090
  vm_name              = "tpl-essai-e03"
  template_name        = "tpl-essai-e03"
  template_description = "Essai M03-E03 — clone de tpl-debian13 par Packer ${packer.version}. À supprimer."
  tags                 = "essai;debian13"

  # Matériel : tout ce qui n'est pas précisé reprend la valeur PAR DÉFAUT DU PLUGIN
  # (kvm64, lsi, 512 Mo, vga std, aucun port série…), pas celle du template source.
  os              = "l26"
  cpu_type        = "x86-64-v2-AES"
  cores           = 2
  memory          = 2048
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true
  serials         = ["socket"]
  vga {
    type = "serial0"
  }
  network_adapters {
    model  = "virtio"
    bridge = "vsandbox"
  }

  # cloud-init du clone de build : Packer crée l'utilisateur ssh_username avec une clé
  # SSH éphémère qu'il génère lui-même. Adresse par DHCP (dns01), résolveur du lab.
  ipconfig {
    ip = "dhcp"
  }
  nameserver   = "10.10.20.10"
  searchdomain = "par1.medisphere.internal"

  # Lecteur cloud-init : retiré avant la conversion, recréé vide sur le template.
  cloud_init              = true
  cloud_init_storage_pool = "local-nvme"

  communicator = "ssh"
  ssh_username = "packer"
  ssh_timeout  = "15m" # premier démarrage : le vendor-data de 9000 installe l'agent QEMU
}

build {
  sources = ["source.proxmox-clone.essai"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait || test $? -eq 2 # 2 = terminé avec avertissements",
      "echo 'Construit par Packer (M03-E03)' | sudo tee /etc/motd",
      "sudo apt-get update -q && sudo apt-get install -y -q htop",
    ]
  }
}
