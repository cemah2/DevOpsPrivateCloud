#!/bin/bash
# systeme.sh — exécuté DANS chaque image par virt-customize (F4-S09), hors ligne, AVANT le script propre
# à la VM. Donne à l'image cloud Debian 12 l'allure d'une VM installée par InfoGér sur son VMware :
# noyau standard (pilotes vmw_pvscsi et vmxnet3), outils VMware, réseau ifupdown statique sur ens192,
# cloud-init désactivé, compte « infoger », clés d'hôte SSH, identifiant de machine.
# Entrées : /root/infoger/{nom,adresse} et les fichiers de personnalisation/commun/ copiés à côté.
set -euo pipefail
S=/root/infoger
NOM="$(cat "$S/nom")"
ADRESSE="$(cat "$S/adresse")"

# cloud-init : désactivé, comme sur toutes les VMs d'InfoGér (elles ne sont pas « cloud »).
touch /etc/cloud/cloud-init.disabled
rm -f /etc/network/interfaces.d/50-cloud-init /etc/netplan/*.yaml
systemctl disable systemd-networkd.service systemd-networkd.socket >/dev/null 2>&1 || true

# Noyau « cloud » de l'image remplacé par le noyau standard installé juste avant (--install) ;
# l'agent QEMU n'a rien à faire sur un VMware.
mapfile -t cloud < <(dpkg-query -W -f='${Package}\n' 'linux-image-*cloud*' 2>/dev/null || true)
paquets=("${cloud[@]}")
dpkg-query -W -f='${Status}' qemu-guest-agent 2>/dev/null | grep -q 'ok installed' && paquets+=(qemu-guest-agent)
if ((${#paquets[@]})); then
  DEBIAN_FRONTEND=noninteractive apt-get -y -q purge "${paquets[@]}"
fi

# Réseau d'InfoGér : ifupdown, adresse fixe sur ens192, résolveurs statiques.
sed -e "s/@NOM@/$NOM/g" -e "s/@ADRESSE@/$ADRESSE/g" "$S/interfaces.modele" > /etc/network/interfaces
rm -f /etc/resolv.conf
install -m 0644 "$S/resolv.conf" /etc/resolv.conf
printf '127.0.0.1\tlocalhost\n%s\t%s.infoger.local %s\n' "$ADRESSE" "$NOM" "$NOM" > /etc/hosts
systemctl enable networking.service >/dev/null

# Exploitation InfoGér : bannière, sudo du compte infoger, SSH restreint, initramfs.
install -m 0644 "$S/motd" /etc/motd
install -m 0440 "$S/90-infoger" /etc/sudoers.d/90-infoger
install -m 0644 "$S/10-infoger.conf" /etc/ssh/sshd_config.d/10-infoger.conf
install -m 0644 "$S/infoger-initramfs.conf" /etc/initramfs-tools/conf.d/infoger.conf
id infoger >/dev/null 2>&1 || useradd --create-home --shell /bin/bash --comment "Exploitation InfoGer" infoger
update-initramfs -u -k all >/dev/null

# Identité de machine : une VM qui a déjà tourné a ses clés d'hôte et son machine-id.
rm -f /etc/ssh/ssh_host_*
ssh-keygen -A >/dev/null
: > /etc/machine-id
systemd-machine-id-setup >/dev/null

systemctl enable open-vm-tools.service ssh.service cron.service >/dev/null
