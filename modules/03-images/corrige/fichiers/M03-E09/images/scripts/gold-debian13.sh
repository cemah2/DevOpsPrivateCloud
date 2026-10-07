#!/usr/bin/env bash
# gold-debian13.sh — contenu de l'image dorée Debian 13 v1 (M03-E09).
# Lancé en root par Packer, après le dépôt de fichiers/ dans $FICHIERS (défaut /tmp/fichiers).
# Chaque réglage est vérifié sur place : un écart fait échouer le build.
set -euo pipefail

FICHIERS="${FICHIERS:-/tmp/fichiers}"
export DEBIAN_FRONTEND=noninteractive
log() { printf '[gold-debian13] %s\n' "$*"; }

# --- 1. Paquets : système à jour + socle commun -------------------------------------------
cloud-init status --wait >/dev/null || [[ $? -eq 2 ]] # le clone de build a fini son premier démarrage
apt-get update -q
apt-get -y -q -o Dpkg::Options::=--force-confold full-upgrade
# chrony remplace systemd-timesyncd (conflit déclaré par les paquets).
apt-get -y -q install qemu-guest-agent cloud-init chrony sudo curl ca-certificates unattended-upgrades

# --- 2. Autorité de certification provisoire MédiSphère (M01) ----------------------------
ca="$FICHIERS/ca/medisphere-provisoire.crt"
[[ -s "$ca" ]] || { log "certificat absent : $ca (voir fichiers/ca/LISEZMOI.md)"; exit 1; }
openssl x509 -in "$ca" -noout -subject >/dev/null || { log "$ca n'est pas un certificat PEM"; exit 1; }
install -m 644 "$ca" /usr/local/share/ca-certificates/medisphere-provisoire.crt
update-ca-certificates
# Doit être présente dans le magasin consolidé utilisé par curl, apt, Python, Go…
grep -qF "$(sed -n 2p "$ca")" /etc/ssl/certs/ca-certificates.crt

# --- 3. sshd : base durcie par un fichier de sshd_config.d --------------------------------
install -m 644 "$FICHIERS/ssh/10-medisphere.conf" /etc/ssh/sshd_config.d/10-medisphere.conf
# Les clés d'hôte existent encore à ce stade (supprimées en fin de build) : sshd -T fonctionne.
sshd -t
effectif="$(sshd -T)"
grep -qx 'permitrootlogin no' <<<"$effectif"
grep -qx 'passwordauthentication no' <<<"$effectif"

# --- 4. Temps : chrony sur la passerelle du VLAN du clone ----------------------------------
# Sources Internet par défaut neutralisées (copie d'origine conservée), sources DHCP inutiles.
cp -n /etc/chrony/chrony.conf /etc/chrony/chrony.conf.orig
sed -i -E 's/^(pool|server) /# &/' /etc/chrony/chrony.conf
sed -i -E 's|^(sourcedir /run/chrony-dhcp)|# \1|' /etc/chrony/chrony.conf
grep -q '^sourcedir /etc/chrony/sources.d' /etc/chrony/chrony.conf \
  || echo 'sourcedir /etc/chrony/sources.d' >> /etc/chrony/chrony.conf
install -m 755 "$FICHIERS/chrony/ms-ntp-passerelle" /usr/local/sbin/ms-ntp-passerelle
install -m 644 "$FICHIERS/chrony/ms-ntp-passerelle.service" /etc/systemd/system/ms-ntp-passerelle.service
systemctl daemon-reload
systemctl enable chrony.service ms-ntp-passerelle.service
# Essai sur la VM de build (passerelle 10.10.99.1 du VLAN SANDBOX), puis la source est
# effacée : chaque clone recalcule la sienne au démarrage.
/usr/local/sbin/ms-ntp-passerelle
rm -f /etc/chrony/sources.d/passerelle.sources

# --- 5. Journal persistant -------------------------------------------------------------------
install -d -m 755 /etc/systemd/journald.conf.d
install -m 644 "$FICHIERS/journald/50-medisphere.conf" /etc/systemd/journald.conf.d/50-medisphere.conf
systemctl restart systemd-journald
test -d /var/log/journal

# --- 6. Mises à jour de sécurité automatiques ----------------------------------------------
install -m 644 "$FICHIERS/apt/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades
install -m 644 "$FICHIERS/apt/52medisphere-unattended-upgrades" /etc/apt/apt.conf.d/52medisphere-unattended-upgrades
configuration="$(apt-config dump)"
origines="$(grep '^Unattended-Upgrade::Origins-Pattern' <<<"$configuration" || true)"
# Une origine « label=Debian » (sans -Security) = mises à jour de version intermédiaire.
if [[ -z "$origines" ]] || grep -Eq 'label=Debian([",;]|$)' <<<"$origines"; then
  log "unattended-upgrades suit encore des mises à jour hors sécurité :"
  printf '%s\n' "$origines"
  exit 1
fi
systemctl enable apt-daily.timer apt-daily-upgrade.timer

# --- 7. Services de l'image -------------------------------------------------------------------
systemctl is-enabled ssh.service systemd-networkd.service systemd-resolved.service >/dev/null
systemctl is-active qemu-guest-agent.service >/dev/null

rm -rf "$FICHIERS"
log "contenu de l'image dorée installé"
