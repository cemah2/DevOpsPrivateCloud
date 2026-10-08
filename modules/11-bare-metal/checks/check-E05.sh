# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes, évaluées sur l'hôte distant
#
# check-E05.sh — M11-E05 : Installer Rocky Linux sans intervention (kickstart)
# À lancer depuis adm01, bm04 (2115) installée et démarrée. Lecture seule. Les empreintes sont lues
# dans le .treeinfo de la version servie par pxe01 (10.2 dans le corrigé ; détectée dans le menu).

# shellcheck source=_m11-decouverte.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-decouverte.sh"

title "M11-E05 — Installer Rocky Linux sans intervention (kickstart)"
require_cmd jq curl sha256sum

# --- L'installateur servi par pxe01 ----------------------------------------------------------------------
_m11d_menu="$(_m11d_http ipxe/menu.ipxe)"
_m11d_ver="$(grep -oE 'pub/rocky/10\.[0-9]+/' <<<"$_m11d_menu" | head -n 1 | grep -oE '10\.[0-9]+' || true)"
check_output "menu iPXE : dépôt Rocky Linux à version mineure fixée (${_m11d_ver:-aucune})" '^10\.[0-9]+$' echo "$_m11d_ver"
_m11d_ti="$(curl -sf --max-time 20 "https://dl.rockylinux.org/pub/rocky/${_m11d_ver:-10}/BaseOS/x86_64/os/.treeinfo" 2>/dev/null || true)"
for _m11d_f in vmlinuz initrd.img; do
  _m11d_attendu="$(sed -nE "s#^images/pxeboot/$_m11d_f = sha256:([0-9a-f]{64})\$#\\1#p" <<<"$_m11d_ti")"
  if [[ -z "$_m11d_attendu" ]]; then
    skip "empreinte de rocky10/$_m11d_f" ".treeinfo de Rocky ${_m11d_ver:-?} injoignable depuis adm01"
    continue
  fi
  check_output "pxe01 : /srv/http/rocky10/$_m11d_f a l'empreinte du .treeinfo $_m11d_ver" "^${_m11d_attendu}\$" \
    _m11d_sha_pxe "/srv/http/rocky10/$_m11d_f"
done

# --- Le kickstart --------------------------------------------------------------------------------------
_m11d_ks="$(_m11d_contenu_main "$_M11D_PROJET_PROV" kickstart/rocky10.ks)"
check_output "plateforme/provisioning : kickstart/rocky10.ks sur main" '%packages' echo "$_m11d_ks"
check_cmd "kickstart : aucun mot de passe en clair" _m11d_sans_clair "$_m11d_ks"
check_output "kickstart : root verrouillé" '^[[:space:]]*rootpw[[:space:]]+.*--lock' echo "$_m11d_ks"
check_output "kickstart : fin par extinction (poweroff)" '^[[:space:]]*poweroff' echo "$_m11d_ks"
check_output "kickstart : même version mineure que le menu (url/inst.repo)" "rocky/${_m11d_ver:-x}/BaseOS" echo "$_m11d_ks"
if command -v ksvalidator >/dev/null 2>&1; then
  check_cmd "kickstart : ksvalidator -v RHEL10" bash -c 'ksvalidator -v RHEL10 <(printf "%s\n" "$1")' _ "$_m11d_ks"
else
  skip "ksvalidator" "absent de adm01 (le pipeline du projet le lance)"
fi

# --- Le serveur installé ---------------------------------------------------------------------------------
if _m11d_qm_running 2115; then
  _m11d_ip="$(_m11d_ip_vm 2115)"
  check_output "bm04 : adresse du VLAN 60 lue par l'agent QEMU (${_m11d_ip:-aucune})" '^10\.10\.60\.[0-9]+$' echo "$_m11d_ip"
  if [[ -n "$_m11d_ip" ]]; then
    check_cmd "bm04 : connexion admin par clé et sudo sans mot de passe" _m11d_ssh_bm "$_m11d_ip" 'sudo -n true'
    check_output "bm04 : Rocky Linux 10" '^VERSION_ID="?10\.' _m11d_ssh_bm "$_m11d_ip" 'cat /etc/os-release'
    check_output "bm04 : SELinux en mode enforcing" '^Enforcing$' _m11d_ssh_bm "$_m11d_ip" 'getenforce'
    check_cmd "bm04 : firewalld actif, SSH autorisé" _m11d_ssh_bm "$_m11d_ip" \
      'systemctl is-active --quiet firewalld && sudo -n firewall-cmd --list-services | grep -qw ssh'
    check_output "bm04 : racine de la PKI dans le magasin du système" 'MédiSphère Root CA' \
      _m11d_ssh_bm "$_m11d_ip" 'trust list --filter=ca-anchors'
    check_output "bm04 : système de fichiers racine sur LVM" '^/dev/mapper/' _m11d_ssh_bm "$_m11d_ip" 'findmnt -no SOURCE /'
    check_cmd "bm04 : agent QEMU actif" _m11d_ssh_bm "$_m11d_ip" 'systemctl is-active --quiet qemu-guest-agent'
  fi
else
  skip "bm04 installée" "VM 2115 arrêtée : démarre-la (elle doit démarrer sur son disque)"
fi
