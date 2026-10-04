#!/usr/bin/env bash
# preparer-git01.sh — préparation système de git01 avant GitLab (M01-E04).
# À lancer SUR git01, en root, après avoir copié depuis adm01 :
#   scp ~/pki-provisoire/ca.crt ~/pki-provisoire/git01-chaine.crt ~/pki-provisoire/git01.key git01:/tmp/
# (la clé privée transite par SSH, puis est supprimée de /tmp par ce script).
set -euo pipefail
FQDN=git01.par1.medisphere.internal

# --- Temps : client chrony de la passerelle du VLAN INFRA (convention M00-E31) -----------
if ! command -v chronyd >/dev/null 2>&1; then apt-get update -q && apt-get install -y chrony; fi
cp -n /etc/chrony/chrony.conf /etc/chrony/chrony.conf.orig
sed -i -E 's/^(pool|server) /# &/; s|^(sourcedir /run/chrony-dhcp)|# \1|' /etc/chrony/chrony.conf
mkdir -p /etc/chrony/sources.d
printf 'server 10.10.20.1 iburst\n' > /etc/chrony/sources.d/lab.sources
systemctl restart chrony

# --- Swap : 4 Go (~50 % de la RAM), swappiness 10 (documentation « mémoire contrainte ») --
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
printf '# GitLab, M01-E04 : limiter le recours au swap\nvm.swappiness = 10\n' > /etc/sysctl.d/90-gitlab.conf
sysctl -p /etc/sysctl.d/90-gitlab.conf

# --- Racine de la PKI provisoire : magasin système et magasin propre à GitLab -------------
install -m 644 /tmp/ca.crt /usr/local/share/ca-certificates/medisphere-provisoire.crt
update-ca-certificates
install -d -m 755 /etc/gitlab /etc/gitlab/ssl /etc/gitlab/trusted-certs
install -m 644 /tmp/ca.crt /etc/gitlab/trusted-certs/medisphere-provisoire.crt

# --- Certificat serveur (chaîne) et clé -------------------------------------------------
install -m 644 /tmp/git01-chaine.crt "/etc/gitlab/ssl/${FQDN}.crt"
install -m 600 /tmp/git01.key "/etc/gitlab/ssl/${FQDN}.key"
rm -f /tmp/git01.key /tmp/git01-chaine.crt /tmp/ca.crt

chronyc -n sources
swapon --show
ls -l /etc/gitlab/ssl /etc/gitlab/trusted-certs
