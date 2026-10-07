# debian13-gold/build.pkr.hcl — image dorée Debian 13, clone de tpl-debian13-base
# (M03-E09, manifeste et versionnage M03-E10).
# Produit un template « deb13-gold-AAAAMMJJ-N » (VMID 9010-9029), étiqueté gold et debian13.
# L'étiquette « current » n'est JAMAIS posée ici : c'est la publication, après les tests (M03-E10).
#
# Lancement (racine du projet) : outils/construire.sh debian13-gold
#   (VMID et version calculés par outils/version-image.sh), puis, après les tests :
#   outils/publier-image.sh <VMID>

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
  nom        = "deb13-gold-${var.version}"
  build_date = formatdate("YYYY-MM-DD hh:mm ZZZ", timestamp())
}

source "proxmox-clone" "debian13" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = false
  node                     = var.proxmox_node
  pool                     = var.pool
  task_timeout             = "10m"

  clone_vm_id = var.base_vm_id
  full_clone  = true # un template doré ne dépend pas de la base (qui est reconstruite)

  vm_id         = var.vm_id
  vm_name       = local.nom
  template_name = local.nom
  tags          = "gold;debian13"
  template_description = join("\n", [
    "Image dorée ${local.nom}",
    "Source : template ${var.base_vm_id} (tpl-debian13-base).",
    "Construite le ${local.build_date} par Packer ${packer.version}, plugin proxmox ${var.plugin_version}.",
    "Projet plateforme/images, commit ${var.git_commit}.",
    "Contenu : agent QEMU, cloud-init, chrony (passerelle du VLAN), CA provisoire MédiSphère,",
    "sshd durci (sshd_config.d/10-medisphere.conf), journal persistant, mises à jour de sécurité auto.",
    "Utilisateur et clés : injectés par cloud-init au clonage (ciuser, sshkeys).",
  ])

  # Matériel identique au template manuel 9000 (sinon : valeurs par défaut du plugin).
  os              = "l26"
  cpu_type        = "x86-64-v2-AES"
  cores           = 2
  memory          = 2048
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true
  serials         = ["socket"]
  vga {
    type = "serial0" # console série (qm terminal), comme tpl-debian13
  }
  network_adapters {
    model    = "virtio"
    bridge   = var.build_bridge
    firewall = false
  }

  # cloud-init du clone de build : compte « packer » + clé éphémère générée par Packer.
  ipconfig {
    ip = "dhcp"
  }
  nameserver   = "10.10.20.10"
  searchdomain = "par1.medisphere.internal"

  # Template final : lecteur cloud-init vide ; pas de mise à niveau complète au premier
  # démarrage de chaque clone (ciupgrade=0) : l'image est reconstruite chaque semaine et
  # unattended-upgrades applique les correctifs de sécurité.
  cloud_init                          = true
  cloud_init_storage_pool             = var.storage_vm
  cloud_init_disable_upgrade_packages = true

  communicator = "ssh"
  ssh_username = "packer"
  ssh_timeout  = "15m"
}

build {
  name    = "debian13-gold"
  sources = ["source.proxmox-clone.debian13"]

  # 1. Fichiers déposés dans l'image (le dossier de destination doit exister).
  provisioner "shell" {
    inline = ["mkdir -p /tmp/fichiers"]
  }
  provisioner "file" {
    source      = "${path.root}/../fichiers/"
    destination = "/tmp/fichiers"
  }

  # 2. Contenu de l'image dorée.
  provisioner "shell" {
    execute_command  = "chmod +x '{{ .Path }}'; sudo env {{ .Vars }} '{{ .Path }}'"
    environment_vars = ["FICHIERS=/tmp/fichiers"]
    script           = "${path.root}/../scripts/gold-debian13.sh"
  }

  # 3. Manifeste : liste des paquets, rapatriée sur la machine de build (M03-E10).
  provisioner "shell" {
    execute_command  = "chmod +x '{{ .Path }}'; sudo env {{ .Vars }} '{{ .Path }}'"
    environment_vars = ["SORTIE=/tmp/paquets.txt"]
    script           = "${path.root}/../scripts/manifeste-paquets.sh"
  }
  provisioner "file" {
    direction   = "download"
    source      = "/tmp/paquets.txt"
    destination = "${path.root}/../manifests/${local.nom}-paquets.txt"
  }

  # 4. Préparation au clonage, toujours en dernier (M03-E07).
  provisioner "shell" {
    execute_command  = "chmod +x '{{ .Path }}'; sudo env {{ .Vars }} '{{ .Path }}'"
    environment_vars = ["COMPTE_BUILD=packer"]
    script           = "${path.root}/../scripts/preparer-clonage.sh"
  }

  # 5. Réglages du template après conversion (résolveur cloud-init par défaut).
  post-processor "shell-local" {
    environment_vars = ["VMID=${var.vm_id}"]
    inline           = ["${path.root}/../outils/finaliser-template.sh"]
  }

  # 6. Manifeste du build (artefact CI) : manifests/<nom>.json
  post-processor "manifest" {
    output     = "${path.root}/../manifests/${local.nom}.json"
    strip_path = true
    custom_data = {
      image       = local.nom
      version     = var.version
      famille     = "debian13"
      source_vmid = "${var.base_vm_id}"
      git_commit  = var.git_commit
      packer      = packer.version
      plugin      = var.plugin_version
    }
  }
}
