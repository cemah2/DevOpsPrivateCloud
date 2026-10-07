# EXTRAIT (M03-E07) — bloc « build » de debian13-base/build.pkr.hcl après l'exercice.
# Remplace le provisioner « inline » de M03-E05 ; même chose dans rocky10-base/build.pkr.hcl
# (avec source.proxmox-iso.rocky10). Version complète des deux fichiers : fichiers/M03-E08/.
#
# Ordre voulu :
#   1. contrôles de l'installation (échouent tôt, avant de perdre du temps) ;
#   2. (images dorées, M03-E09) personnalisation ;
#   3. préparation au clonage, TOUJOURS en dernier : après elle, plus rien ne doit écrire
#      dans le système (ni journal, ni cache, ni clé).

build {
  name    = "debian13-base"
  sources = ["source.proxmox-iso.debian13"]

  provisioner "shell" {
    execute_command = "chmod +x '{{ .Path }}'; sudo env {{ .Vars }} '{{ .Path }}'"
    inline = [
      "grep PRETTY_NAME /etc/os-release",
      "systemctl is-active qemu-guest-agent",
      "cloud-init --version",
    ]
  }

  provisioner "shell" {
    execute_command  = "chmod +x '{{ .Path }}'; sudo env {{ .Vars }} '{{ .Path }}'"
    environment_vars = ["COMPTE_BUILD=${local.build_username}"]
    script           = "${path.root}/../scripts/preparer-clonage.sh"
  }
}
