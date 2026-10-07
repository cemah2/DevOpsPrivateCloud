# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant ou dans la VM
#
# check-E09.sh — M03-E09 « Image dorée Debian 13 v1 »
# VM de recette 2034 démarrée (clone de l'image dorée, VNet vinfra, 10.10.20.49, sans
# résolveur précisé). Lecture seule.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E09 — Image dorée Debian 13 v1"
require_cmd jq shellcheck
_m03_charger

title "Code de l'image dorée"
for _m03_e09_f in debian13-gold/build.pkr.hcl debian13-gold/variables.pkr.hcl; do
  check_cmd "$_m03_e09_f sur main" _m03_fichier_main "$_m03_e09_f"
done
check_cmd "build par clonage de tpl-debian13-base (proxmox-clone)" \
  _m03_fichier_main_contient debian13-gold/build.pkr.hcl 'source "proxmox-clone"'
check_cmd "la préparation au clonage termine le build doré" \
  _m03_fichier_main_contient debian13-gold/build.pkr.hcl 'preparer-clonage\.sh'
# Scripts appelés par le build doré : tous sans remarque ShellCheck (copie locale).
_m03_e09_scripts_propres() {
  local s rc=0 liste
  liste="$(grep -Eo '(scripts|outils)/[A-Za-z0-9_.-]+\.sh' "$_M03_SRC/debian13-gold/build.pkr.hcl" 2>/dev/null | sort -u)" || return 1
  while IFS= read -r s; do
    shellcheck -x "$_M03_SRC/$s" >/dev/null 2>&1 || rc=1
  done <<<"$liste"
  return "$rc"
}
check_cmd "scripts appelés par le build doré sans remarque ShellCheck" _m03_e09_scripts_propres

title "Template doré (le plus récent de la plage 9010-9029)"
_m03_e09_tpl="$(_m03_gold debian13 | jq -r '[.[] | select(.vmid >= 9010 and .vmid <= 9029)] | last | .vmid // empty')"
check_cmd "au moins un template gold + debian13 dans 9010-9029 (${_m03_e09_tpl:-aucun})" test -n "$_m03_e09_tpl"
_m03_e09_conf="$(_m03_conf "${_m03_e09_tpl:-0}")" || _m03_e09_conf=""
_m03_e09_a() { grep -Eq -- "$1" <<<"$_m03_e09_conf"; }
check_cmd "nom deb13-gold-AAAAMMJJ-N" _m03_e09_a '^name: deb13-gold-20[0-9]{6}-[0-9]+$'
check_cmd "console série (serial0: socket, vga: serial0)" \
  bash -c 'grep -q "^serial0: socket" <<<"$1" && grep -q "^vga: serial0" <<<"$1"' _ "$_m03_e09_conf"
check_cmd "lecteur cloud-init présent" _m03_e09_a '^(ide|sata|scsi)[0-9]+: .*cloudinit'
check_cmd "résolveur par défaut 10.10.20.10" _m03_e09_a '^nameserver: 10\.10\.20\.10$'
check_cmd "domaine par défaut par1.medisphere.internal" _m03_e09_a '^searchdomain: par1\.medisphere\.internal$'
check_cmd "pas de mise à niveau complète au premier démarrage des clones (ciupgrade: 0)" _m03_e09_a '^ciupgrade: 0$'
check_cmd "aucun utilisateur ni clé cuits dans la configuration du template" \
  bash -c '! grep -Eq "^(ciuser|sshkeys|cipassword):" <<<"$1"' _ "$_m03_e09_conf"

title "VM de recette 2034"
_m03_e09_vm="$(_m03_conf 2034)" || _m03_e09_vm=""
check_cmd "VM 2034 démarrée" _m03_en_marche 2034
check_cmd "2034 : sur vinfra en 10.10.20.49, SANS résolveur précisé au clonage" \
  bash -c 'grep -q "^net0: .*bridge=vinfra" <<<"$1" && grep -q "^ipconfig0: ip=10.10.20.49/24" <<<"$1" && ! grep -q "^nameserver:" <<<"$1"' \
  _ "$_m03_e09_vm"
check_cmd "2034 : cloud-init a terminé" _m03_gexec_match 2034 'cloud-init status' '^status: done'
check_cmd "2034 : admin présent, compte packer absent" _m03_gexec 2034 'id admin >/dev/null && ! id packer >/dev/null 2>&1'
check_cmd "2034 : résolveur 10.10.20.10 (valeur par défaut du template)" _m03_gexec_match 2034 'resolvectl dns' '10\.10\.20\.10'
check_cmd "2034 : chrony a pour source la passerelle du VLAN (10.10.20.1)" \
  _m03_gexec_match 2034 'chronyc -n sources' '10\.10\.20\.1[[:space:]]'
check_cmd "2034 : aucune source NTP Internet active (pool)" \
  _m03_gexec 2034 '! grep -Eq "^(pool|server) " /etc/chrony/chrony.conf'
check_cmd "2034 : CA provisoire MédiSphère approuvée par le système" \
  _m03_gexec 2034 'f=/usr/local/share/ca-certificates/medisphere-provisoire.crt; test -s "$f" && grep -qF "$(sed -n 2p "$f")" /etc/ssl/certs/ca-certificates.crt'
check_cmd "2034 : sshd effectif — root interdit, mot de passe interdit" \
  _m03_gexec 2034 'c="$(sshd -T)"; grep -qx "permitrootlogin no" <<<"$c" && grep -qx "passwordauthentication no" <<<"$c"'
check_cmd "2034 : journal persistant (Storage=persistent)" \
  _m03_gexec 2034 'systemd-analyze cat-config systemd/journald.conf | grep -Eq "^Storage=persistent" && test -d /var/log/journal'
check_cmd "2034 : unattended-upgrades actif, sécurité seulement" \
  _m03_gexec 2034 'o="$(apt-config dump | grep "^Unattended-Upgrade::Origins-Pattern::")"; [ -n "$o" ] && ! grep -Eq "label=Debian([\",;]|$)" <<<"$o" && apt-config dump | grep -q "APT::Periodic::Unattended-Upgrade \"1\""'
check_cmd "2034 : agent QEMU actif" _m03_gexec 2034 'systemctl is-active --quiet qemu-guest-agent'
