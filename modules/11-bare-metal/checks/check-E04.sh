# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes, évaluées sur l'hôte distant
#
# check-E04.sh — M11-E04 : Installer Debian sans intervention (preseed)
# À lancer depuis adm01, bm01 (2112) installée et démarrée. Lecture seule. Lit les empreintes
# publiées aujourd'hui par Debian : si une nouvelle version de l'installateur est sortie depuis ton
# téléchargement, relance le rôle pxe (il la vérifiera et la publiera).

# shellcheck source=_m11-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-decouverte.sh"

title "M11-E04 — Installer Debian sans intervention (preseed)"
require_cmd jq curl sha256sum

# --- L'installateur servi par pxe01 ------------------------------------------------------------------
_m11d_sums="$(curl -sf --max-time 20 https://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/SHA256SUMS 2>/dev/null || true)"
for _m11d_f in linux initrd.gz; do
  _m11d_attendu="$(awk -v r="./netboot/debian-installer/amd64/$_m11d_f" '$2 == r {print $1}' <<<"$_m11d_sums")"
  if [[ -z "$_m11d_attendu" ]]; then
    skip "empreinte de debian13/$_m11d_f" "SHA256SUMS de Debian injoignable depuis adm01"
    continue
  fi
  check_output "pxe01 : /srv/http/debian13/$_m11d_f a l'empreinte publiée par Debian" "^${_m11d_attendu}\$" \
    _m11d_sha_pxe "/srv/http/debian13/$_m11d_f"
done

# --- Le preseed ----------------------------------------------------------------------------------------
_m11d_preseed="$(_m11d_contenu_main "$_M11D_PROJET_PROV" preseed/debian13.cfg)"
check_output "plateforme/provisioning : preseed/debian13.cfg sur main" 'd-i ' echo "$_m11d_preseed"
check_cmd "preseed : aucun mot de passe en clair" _m11d_sans_clair "$_m11d_preseed"
check_output "preseed : mot de passe d'admin sous forme d'empreinte SHA-512" \
  'passwd/user-password-crypted[[:space:]]+password[[:space:]]+\$6\$' echo "$_m11d_preseed"
check_output "preseed : fin d'installation par extinction" 'debian-installer/exit/poweroff[[:space:]]+boolean[[:space:]]+true' echo "$_m11d_preseed"
if command -v debconf-set-selections >/dev/null 2>&1; then
  check_cmd "preseed : syntaxe debconf valide" bash -c '[ -n "$1" ] && debconf-set-selections -c <(printf "%s\n" "$1")' _ "$_m11d_preseed"
else
  skip "syntaxe debconf du preseed" "debconf-set-selections absent de adm01"
fi
check_output "preseed publié sur pxe01 = version de main" "^$(printf '%s\n' "$_m11d_preseed" | sha256sum | cut -d ' ' -f 1)\$" \
  bash -c '[ -n "$1" ] && printf "%s\n" "$1" | sha256sum | cut -d " " -f 1' _ "$(_m11d_http preseed/debian13.cfg)"

# --- Le serveur installé ---------------------------------------------------------------------------------
if _m11d_qm_running 2112; then
  _m11d_ip="$(_m11d_ip_vm 2112)"
  check_output "bm01 : adresse du VLAN 60 lue par l'agent QEMU (${_m11d_ip:-aucune})" '^10\.10\.60\.[0-9]+$' echo "$_m11d_ip"
  if [[ -n "$_m11d_ip" ]]; then
    check_cmd "bm01 : connexion admin par clé et sudo sans mot de passe" _m11d_ssh_bm "$_m11d_ip" 'sudo -n true'
    check_output "bm01 : Debian 13" '^VERSION_CODENAME=trixie$' _m11d_ssh_bm "$_m11d_ip" 'cat /etc/os-release'
    check_output "bm01 : système de fichiers racine sur LVM" '^/dev/mapper/' _m11d_ssh_bm "$_m11d_ip" 'findmnt -no SOURCE /'
    check_output "bm01 : racine de la PKI installée (identique à celle de adm01)" "^$(_m11d_sha_racine_locale)\$" \
      _m11d_ssh_bm "$_m11d_ip" "sha256sum $_M11D_RACINE_PKI | cut -d ' ' -f 1"
    check_output "bm01 : root sans mot de passe utilisable" '^root (L|NP|LK) ' _m11d_ssh_bm "$_m11d_ip" 'sudo -n passwd -S root'
    check_cmd "bm01 : agent QEMU et SSH actifs" _m11d_ssh_bm "$_m11d_ip" 'systemctl is-active --quiet qemu-guest-agent && systemctl is-active --quiet ssh'
  fi
else
  skip "bm01 installée" "VM 2112 arrêtée : démarre-la (elle doit démarrer sur son disque)"
fi
