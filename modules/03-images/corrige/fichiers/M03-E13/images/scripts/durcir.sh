#!/usr/bin/env bash
# durcir.sh — durcissement de l'image dorée (M03-E13, ticket SEC-450).
# Lancé en root par Packer APRÈS gold-<famille>.sh et AVANT preparer-clonage.sh, avec les
# fichiers de fichiers/durcissement/ déposés dans $DURCISSEMENT (défaut /tmp/durcissement).
# Idempotent : relancé sur une machine déjà durcie, il réécrit les mêmes fichiers.
# Chaque mesure est vérifiée sur place ; un écart fait échouer le build (code 1).
# Référentiel et exceptions : docs/durcissement.md.
set -euo pipefail

D="${DURCISSEMENT:-/tmp/durcissement}"
log() { printf '[durcir] %s\n' "$*"; }
echec() { log "ÉCHEC : $*"; exit 1; }
[[ $EUID -eq 0 ]] || echec "à lancer en root"
[[ -d "$D" ]] || echec "dossier des fichiers de durcissement absent : $D"

. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" debian "*) famille=debian ;;
  *" rhel "* | *" fedora "*) famille=rhel ;;
  *) echec "distribution non prise en charge : ${ID:-inconnue}" ;;
esac
log "famille $famille ($PRETTY_NAME)"

# --- 1. Paquets : audit ---------------------------------------------------------------------
if [[ $famille == debian ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get -y -q install auditd
else
  dnf -y -q install audit
fi

# --- 2. SSH -----------------------------------------------------------------------------------
install -m 644 "$D/issue.net" /etc/issue.net
conf=/etc/ssh/sshd_config.d/05-durcissement.conf
install -m 644 "$D/ssh/05-durcissement.conf" "$conf"
# Listes d'algorithmes : seulement ce que CETTE version d'OpenSSH connaît (sinon sshd refuse
# de démarrer). Ordre = préférence. Aucun SHA-1, aucun CBC, échanges hybrides post-quantiques
# en tête quand ils existent (OpenSSH ≥ 9.9).
filtrer() { # filtrer TYPE ALGO… — garde les algorithmes listés par « ssh -Q TYPE »
  local type="$1" a connus garde=()
  shift
  connus="$(ssh -Q "$type")"
  for a in "$@"; do grep -qx -- "$a" <<<"$connus" && garde+=("$a"); done
  ((${#garde[@]})) || echec "aucun algorithme $type retenu"
  local IFS=,
  printf '%s' "${garde[*]}"
}
{
  echo "# Ajouté par durcir.sh (filtré par ssh -Q, OpenSSH $(ssh -V 2>&1 | cut -d' ' -f1))"
  echo "KexAlgorithms $(filtrer kex mlkem768x25519-sha256 sntrup761x25519-sha512 sntrup761x25519-sha512@openssh.com curve25519-sha256 curve25519-sha256@libssh.org)"
  echo "Ciphers $(filtrer cipher chacha20-poly1305@openssh.com aes256-gcm@openssh.com aes128-gcm@openssh.com aes256-ctr aes128-ctr)"
  echo "MACs $(filtrer mac hmac-sha2-512-etm@openssh.com hmac-sha2-256-etm@openssh.com umac-128-etm@openssh.com)"
} >>"$conf"
sshd -t || echec "configuration sshd invalide"
effectif="$(sshd -T)"
for attendu in 'x11forwarding no' 'allowagentforwarding no' 'allowtcpforwarding no' 'maxauthtries 3' \
  'logingracetime 30' 'clientaliveinterval 300' 'banner /etc/issue.net' 'permitrootlogin no' \
  'passwordauthentication no'; do
  grep -qx "$attendu" <<<"$effectif" || echec "sshd -T : « $attendu » attendu"
done
! grep -Eq '^(macs|kexalgorithms|ciphers) .*(sha1|cbc)' <<<"$effectif" || echec "algorithme SHA-1 ou CBC encore proposé"
# Recharger le service : la connexion de Packer en cours n'est pas coupée.
systemctl reload ssh.service 2>/dev/null || systemctl reload sshd.service

# --- 3. Noyau ---------------------------------------------------------------------------------
install -m 644 "$D/sysctl/60-medisphere-durcissement.conf" /etc/sysctl.d/60-medisphere-durcissement.conf
# systemd-sysctl comprend les motifs « net.ipv4.conf.*.… » (sysctl.d(5)).
/usr/lib/systemd/systemd-sysctl /etc/sysctl.d/60-medisphere-durcissement.conf
for v in net.ipv4.conf.all.accept_redirects=0 net.ipv4.conf.default.accept_redirects=0 \
  net.ipv4.conf.all.send_redirects=0 net.ipv4.conf.all.log_martians=1 kernel.kptr_restrict=2 \
  kernel.dmesg_restrict=1 kernel.yama.ptrace_scope=1; do
  [[ "$(sysctl -n "${v%%=*}")" == "${v#*=}" ]] || echec "sysctl ${v%%=*} ≠ ${v#*=}"
done

install -m 644 "$D/modprobe/medisphere-durcissement.conf" /etc/modprobe.d/medisphere-durcissement.conf
for m in sctp usb-storage cramfs; do
  modprobe -n -v "$m" 2>&1 | grep -Eq '^install /(usr/)?bin/false' || echec "module $m encore chargeable"
done
# Garde-fou : le lecteur cloud-init (ISO 9660) doit rester lisible.
if grep -Eq '^install (isofs|udf) ' /etc/modprobe.d/*.conf; then echec "isofs/udf bloqué : cloud-init ne lirait plus son lecteur"; fi
# Sur RHEL, l'initramfs embarque /etc/modprobe.d : le régénérer pour qu'il en tienne compte.
if [[ $famille == rhel ]]; then dracut -f --regenerate-all; fi

# --- 4. /dev/shm sans exécution ni périphériques ni setuid -----------------------------------
if ! grep -Eq '^[^#]*[[:space:]]/dev/shm[[:space:]]' /etc/fstab; then
  echo 'tmpfs /dev/shm tmpfs defaults,nosuid,nodev,noexec 0 0' >>/etc/fstab
fi
mount -o remount,nosuid,nodev,noexec /dev/shm
findmnt -no OPTIONS /dev/shm | grep -q noexec || echec "/dev/shm sans noexec"

# --- 5. Traçabilité : auditd -------------------------------------------------------------------
install -m 640 "$D/audit/50-medisphere.rules" /etc/audit/rules.d/50-medisphere.rules
augenrules --check >/dev/null || true
augenrules --load
systemctl enable auditd.service >/dev/null
[[ "$(auditctl -l | grep -vc '^No rules')" -ge 5 ]] || echec "règles d'audit non chargées"

# --- 6. Résolution multicast (systemd-resolved, Debian) : plus de ports 5355 ouverts ----------
if systemctl is-enabled -q systemd-resolved.service 2>/dev/null; then
  install -d -m 755 /etc/systemd/resolved.conf.d
  install -m 644 "$D/resolved/60-medisphere.conf" /etc/systemd/resolved.conf.d/60-medisphere.conf
  systemctl restart systemd-resolved.service
fi

# --- 7. Surface : rien d'autre que SSH n'écoute en TCP hors boucle locale ---------------------
sleep 2
ecoute="$(ss -Htln | awk '{print $4}' | grep -Ev '^(127\.[0-9.]+(%[a-z0-9]+)?|\[::1\]):[0-9]+$' | grep -Ev ':22$' || true)"
[[ -z "$ecoute" ]] || echec "ports TCP en écoute inattendus : $(tr '\n' ' ' <<<"$ecoute")"

rm -rf -- "$D"
log "image durcie (SEC-450)"
