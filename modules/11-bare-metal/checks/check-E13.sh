# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant ou par bash -c
# check-E13.sh — M11-E13 « Sécuriser la chaîne de provisioning » : HTTPS de pxe01 par la PKI, port 80
# réduit, chargeurs iPXE construits (empreintes dans le code), plus d'URL http:// dans Kea et les
# scripts, fichiers de réponse sans mot de passe en clair, VLAN 60 isolé, IPMI sur IP coupé,
# documentation. Lecture seule.

# shellcheck source=_m11-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m11-production.sh"

title "M11-E13 — Chaîne de provisioning sécurisée"
require_cmd curl openssl jq ssh shellcheck

# --- pxe01 en HTTPS -------------------------------------------------------------------------
_m11_e13_https_ok() { [[ "$(_m11p_https /boot.ipxe)" == 0 ]]; }
check_cmd "pxe01 : boot.ipxe servi en HTTPS, certificat vérifié par adm01" _m11_e13_https_ok
check_cmd "pxe01 : chaîne complète, feuille émise par l'intermédiaire MédiSphère" _m11p_pki_ok
_m11_e13_http() {
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "http://$_m11p_pxe_ip/boot.ipxe" 2>/dev/null)" || true
  [[ "$code" =~ ^(30[1278]|40[34])$ ]]
}
check_cmd "pxe01 : le port 80 répond mais ne sert plus boot.ipxe (redirection ou refus)" _m11_e13_http

# --- Chargeurs iPXE ----------------------------------------------------------------------------
_m11_e13_racine_tftp="$(remote pxe01 "sed -nE 's/^[[:space:]]*TFTP_DIRECTORY=\"?([^\"]*)\"?.*/\1/p' /etc/default/tftpd-hpa | tail -n 1" 2>/dev/null)" || true
_m11_e13_sommes="$(remote pxe01 "cd '${_m11_e13_racine_tftp:-/srv/tftp}' && sha256sum undionly.kpxe ipxe.efi" 2>/dev/null)" || true
check_cmd "pxe01 : undionly.kpxe et ipxe.efi présents dans la racine TFTP" \
  test "$(wc -l <<<"$_m11_e13_sommes")" -eq 2 -a -n "$_m11_e13_sommes"
_m11_e13_pas_debian() {
  local f s d
  [[ -n "$_m11_e13_sommes" ]] || return 1
  while read -r s f; do
    d="$(remote pxe01 "sha256sum /usr/lib/ipxe/$f 2>/dev/null | cut -d' ' -f1" 2>/dev/null)"
    [[ -z "$d" || "$d" != "$s" ]] || return 1
  done <<<"$_m11_e13_sommes"
}
check_cmd "chargeurs servis différents des binaires génériques du paquet Debian" _m11_e13_pas_debian
_m11_e13_dans_code() {
  local f s
  [[ -n "$_m11_e13_sommes" ]] || return 1
  while read -r s f; do
    grep -rqs -- "$s" "$_m11p_src/ansible/inventories" "$_m11p_src/ansible/roles/pxe" || return 1
  done <<<"$_m11_e13_sommes"
}
check_cmd "empreintes des chargeurs servis présentes dans le code Ansible (~/src/ansible)" _m11_e13_dans_code
_m11_e13_construire() {
  local t rc=0
  t="$(mktemp)"
  _m11p_gitlab_brut plateforme/provisioning ipxe/construire-ipxe.sh >"$t" || { rm -f "$t"; return 1; }
  [[ -s "$t" ]] && shellcheck -s bash "$t" >/dev/null 2>&1 || rc=1
  rm -f "$t"
  return "$rc"
}
check_cmd "ipxe/construire-ipxe.sh sur main de plateforme/provisioning, sans remarque ShellCheck" _m11_e13_construire

# --- Plus d'URL http:// ---------------------------------------------------------------------------
check_ssh "Kea (dns01) : classe iPXE vers https://pxe01…, aucune URL http:// vers pxe01" dns01 \
  'c="$(sudo -n cat /etc/kea/kea-dhcp4.conf)" && grep -q "https://pxe01.par1.medisphere.internal" <<<"$c" && ! grep -Eq "http://(pxe01|10\.10\.60\.10)" <<<"$c"'
if remote dns02 true >/dev/null 2>&1; then
  check_ssh "Kea (dns02) : aucune URL http:// vers pxe01" dns02 \
    '! sudo -n grep -Eq "http://(pxe01|10\.10\.60\.10)" /etc/kea/kea-dhcp4.conf'
fi
_m11_e13_racine="$(_m11p_racine_nginx)" || true
check_cmd "pxe01 : racine nginx identifiée" test -n "$_m11_e13_racine"
check_ssh "pxe01 : aucun script iPXE servi ne contient d'URL http://" pxe01 \
  "! sudo -n grep -lE 'http://' '$_m11_e13_racine'/boot.ipxe '$_m11_e13_racine'/ipxe/*.ipxe 2>/dev/null | grep -q ."

# --- Fichiers de réponse ---------------------------------------------------------------------------
check_ssh "preseed servis : aucun mot de passe en clair, connexion root refusée" pxe01 \
  "r='$_m11_e13_racine'; ls \"\$r\"/preseed/*.cfg >/dev/null 2>&1 || exit 1; for f in \"\$r\"/preseed/*.cfg; do sudo -n grep -Eq '^d-i[[:space:]]+passwd/(root|user)-password(-again)?[[:space:]]' \"\$f\" && exit 1; sudo -n grep -Eq '^d-i[[:space:]]+passwd/root-login[[:space:]]+boolean[[:space:]]+false' \"\$f\" || exit 1; done"
check_ssh "kickstart servis : root verrouillé, aucun --plaintext" pxe01 \
  "r='$_m11_e13_racine'; ls \"\$r\"/kickstart/*.ks >/dev/null 2>&1 || exit 1; for f in \"\$r\"/kickstart/*.ks; do sudo -n grep -Eq -- '--plaintext' \"\$f\" && exit 1; sudo -n grep -Eq '^rootpw[[:space:]].*--lock' \"\$f\" || exit 1; done"

# --- VLAN 60 isolé -----------------------------------------------------------------------------------
check_ssh "pxe01 → dns01:53 (TCP) ouvert" pxe01 'timeout 4 bash -c "</dev/tcp/10.10.20.10/53"'
check_ssh "pxe01 → adm01:22 fermé (VLAN 60 isolé de MGMT)" pxe01 '! timeout 4 bash -c "</dev/tcp/10.10.10.10/22"'
check_ssh "pxe01 → git01:443 fermé (services du socle hors DNS et ACME)" pxe01 '! timeout 4 bash -c "</dev/tcp/10.10.20.12/443"'
check_ssh "ca01 → pxe01:80 ouvert (défi ACME)" ca01 'timeout 4 bash -c "</dev/tcp/10.10.60.10/80"'

# --- iLO ----------------------------------------------------------------------------------------------
_m11_e13_ipmi="$(_m11p_ilo /redfish/v1/Managers/1/NetworkService/ | jq -r '.IPMI.ProtocolEnabled | if . == null then empty else tostring end' 2>/dev/null)" || true
if [[ -z "$_m11_e13_ipmi" ]]; then
  skip "iLO : IPMI sur IP désactivé" "Redfish illisible ou champ IPMI absent de ce firmware : vérifie dans l'interface de l'iLO"
else
  check_cmd "iLO : IPMI sur IP désactivé (Redfish NetworkService)" test "$_m11_e13_ipmi" = false
fi
check_cmd "matrice des flux : plus de flux UDP 623 (IPMI) dans pare_feu.yml" \
  bash -c '[ -s "$1" ] && ! grep -Eq "\b623\b" "$1"' _ "$_m11p_src/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml"

# --- Documentation ------------------------------------------------------------------------------------
check_cmd "docs/provisioning/securite-chaine.md sur main de plateforme/medisphere" \
  _m11p_gitlab_fichier plateforme/medisphere docs/provisioning/securite-chaine.md
check_output "ADR-0111 sur main (docs/provisioning/adr/)" '^ADR-0111' _m11p_gitlab_ls plateforme/medisphere docs/provisioning/adr
