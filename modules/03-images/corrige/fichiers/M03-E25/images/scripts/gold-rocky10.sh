#!/usr/bin/env bash
# gold-rocky10.sh — contenu de l'image dorée Rocky Linux 10 v1 (M03-E25).
# Même contenu que gold-debian13.sh (M03-E09), avec les outils de la famille RHEL.
# Lancé en root par Packer, après le dépôt de fichiers/ dans $FICHIERS (défaut /tmp/fichiers).
# Chaque réglage est vérifié sur place : un écart fait échouer le build.
set -euo pipefail

FICHIERS="${FICHIERS:-/tmp/fichiers}"
log() { printf '[gold-rocky10] %s\n' "$*"; }

# --- 1. Paquets : système à jour + socle commun -------------------------------------------
cloud-init status --wait >/dev/null || [[ $? -eq 2 ]] # le clone de build a fini son premier démarrage
dnf -y -q upgrade --refresh
dnf -y -q install qemu-guest-agent cloud-init chrony sudo curl ca-certificates dnf-automatic openssl

# --- 2. Autorité de certification provisoire MédiSphère (M01) ----------------------------
ca="$FICHIERS/ca/medisphere-provisoire.crt"
[[ -s "$ca" ]] || { log "certificat absent : $ca (voir fichiers/ca/LISEZMOI.md)"; exit 1; }
openssl x509 -in "$ca" -noout -subject >/dev/null || { log "$ca n'est pas un certificat PEM"; exit 1; }
install -m 644 "$ca" /etc/pki/ca-trust/source/anchors/medisphere-provisoire.crt
restorecon /etc/pki/ca-trust/source/anchors/medisphere-provisoire.crt
update-ca-trust extract
openssl verify -CAfile /etc/pki/tls/certs/ca-bundle.crt /etc/pki/ca-trust/source/anchors/medisphere-provisoire.crt >/dev/null

# --- 3. sshd : même base durcie que Debian ------------------------------------------------
# Sur Rocky, sshd_config inclut sshd_config.d/*.conf en tête : « 10- » passe devant
# « 50-redhat.conf » (qui inclut la politique cryptographique du système).
install -m 600 "$FICHIERS/ssh/10-medisphere.conf" /etc/ssh/sshd_config.d/10-medisphere.conf
restorecon /etc/ssh/sshd_config.d/10-medisphere.conf
sshd -t
effectif="$(sshd -T)"
grep -qx 'permitrootlogin no' <<<"$effectif"
grep -qx 'passwordauthentication no' <<<"$effectif"

# --- 4. Temps : chrony sur la passerelle du VLAN du clone ----------------------------------
cp -n /etc/chrony.conf /etc/chrony.conf.orig
sed -i -E 's/^(pool|server) /# &/' /etc/chrony.conf
sed -i -E 's|^(sourcedir /run/chrony-dhcp)|# \1|' /etc/chrony.conf
grep -q '^sourcedir /etc/chrony/sources.d' /etc/chrony.conf \
  || echo 'sourcedir /etc/chrony/sources.d' >> /etc/chrony.conf
install -d -m 755 /etc/chrony/sources.d
install -m 755 "$FICHIERS/chrony/ms-ntp-passerelle" /usr/local/sbin/ms-ntp-passerelle
# Service : même unité que Debian, ordonnée après chronyd (nom du service sur RHEL).
sed 's/chrony\.service/chronyd.service/' "$FICHIERS/chrony/ms-ntp-passerelle.service" \
  >/etc/systemd/system/ms-ntp-passerelle.service
chmod 644 /etc/systemd/system/ms-ntp-passerelle.service
restorecon -R /etc/chrony /usr/local/sbin/ms-ntp-passerelle /etc/systemd/system/ms-ntp-passerelle.service
systemctl daemon-reload
systemctl enable chronyd.service ms-ntp-passerelle.service
systemctl restart chronyd.service
/usr/local/sbin/ms-ntp-passerelle
rm -f /etc/chrony/sources.d/passerelle.sources

# --- 5. Journal persistant -------------------------------------------------------------------
install -d -m 755 /etc/systemd/journald.conf.d
install -m 644 "$FICHIERS/journald/50-medisphere.conf" /etc/systemd/journald.conf.d/50-medisphere.conf
systemctl restart systemd-journald
test -d /var/log/journal

# --- 6. Correctifs de sécurité automatiques -------------------------------------------------
install -m 644 "$FICHIERS/dnf/automatic.conf" /etc/dnf/automatic.conf
grep -Eq '^upgrade_type *= *security' /etc/dnf/automatic.conf
systemctl enable dnf-automatic.timer

# --- 7. Sécurité de la famille RHEL et services --------------------------------------------
[[ "$(getenforce)" == Enforcing ]] || { log "SELinux n'est pas en mode enforcing"; exit 1; }
systemctl is-enabled sshd.service NetworkManager.service >/dev/null
systemctl is-active qemu-guest-agent.service >/dev/null

rm -rf "$FICHIERS"
log "contenu de l'image dorée installé"
