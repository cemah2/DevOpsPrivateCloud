# Image dorée Debian 13 — Lucas Martin
# packer build .

source "proxmox-iso" "debian" {
  proxmox_url              = "https://192.168.1.20:8006/api2/json"
  username                 = "root@pam"
  password                 = "Medisphere2026!"
  insecure_skip_tls_verify = true
  node                     = "pve01"

  template_name = "debian-gold"

  iso_url          = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.7.0-amd64-netinst.iso"
  iso_checksum     = "none"
  iso_storage_pool = "local"
  unmount_iso      = true

  memory = 1024

  disks {
    storage_pool = "local-nvme"
    disk_size    = "8G"
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  http_directory = "."
  boot_wait      = "5s"
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/http/preseed.cfg<enter>",
  ]

  ssh_host     = "192.168.1.150"
  ssh_username = "root"
  ssh_password = "Medisphere2026!"
  ssh_timeout  = "30m"
}

build {
  sources = ["source.proxmox-iso.debian"]

  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get install -y curl vim htop",
      "curl -fsSL https://outils.mediagenda.example/install.sh | bash",
      "apt-get clean",
    ]
  }
}
