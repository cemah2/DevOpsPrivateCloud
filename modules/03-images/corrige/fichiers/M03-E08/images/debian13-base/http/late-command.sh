#!/bin/sh
# late-command.sh — fin d'installation de tpl-debian13-base (M03-E05).
# Exécuté par l'installeur DANS le système installé (in-target = chroot /target),
# avec le nom du compte de construction en argument. Le shell est le sh du système (dash).
set -eu

compte="${1:?Usage : late-command.sh <compte-de-construction>}"

# 1. sudo sans mot de passe pour le compte de construction, le temps du build.
#    Supprimé par scripts/preparer-clonage.sh (M03-E07).
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$compte" > /etc/sudoers.d/90-build-packer
chmod 0440 /etc/sudoers.d/90-build-packer
visudo -cf /etc/sudoers.d/90-build-packer

# 2. Réseau : comme l'image genericcloud, netplan + systemd-networkd + systemd-resolved.
#    Configuration provisoire pour le build (DHCP sur la première carte), supprimée par
#    preparer-clonage.sh : sur un clone, c'est cloud-init qui écrit /etc/netplan/50-cloud-init.yaml.
cat > /etc/netplan/90-build.yaml <<'EOF'
network:
  version: 2
  ethernets:
    build:
      match:
        name: "en*"
      dhcp4: true
EOF
chmod 0600 /etc/netplan/90-build.yaml

# 3. ifupdown retiré : sinon cloud-init choisirait le moteur « eni » (prioritaire sur netplan)
#    et la configuration de l'installeur (/etc/network/interfaces) doublerait la sienne.
apt-get -y purge ifupdown
rm -f /etc/network/interfaces
systemctl enable systemd-networkd.service systemd-resolved.service
