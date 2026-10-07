# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées dans la VM
#
# check-E22.sh — M03-E22 « Panne : la VM Rocky ne démarre pas »
# La VM de l'éditeur (2036) démarre jusqu'à ses services, avec un matériel virtuel compatible
# avec Rocky Linux 10, et l'image Rocky elle-même porte le bon type de CPU.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E22 — Panne : la VM Rocky ne démarre pas"
require_cmd jq ssh
_m03_charger
_m03_v=2036
_m03_c="$(_m03_conf "$_m03_v" || true)"
_m03_conf_vaut() { grep -Eq -- "$1" <<<"$_m03_c"; }

check_cmd "VM 2036 (editeur-rocky01) démarrée" _m03_en_marche "$_m03_v"
check_cmd "VM 2036 : agent QEMU répond (le système a démarré)" _m03_gexec "$_m03_v" 'true'
check_cmd "VM 2036 : Rocky Linux 10" _m03_gexec_match "$_m03_v" 'cat /etc/os-release' '^VERSION_ID="?10'
check_cmd "VM 2036 : CPU x86-64-v3 (ou supérieur) ou host" _m03_conf_vaut '^cpu: (x86-64-v[34]|host)([,]|$)'
check_cmd "VM 2036 : contrôleur virtio-scsi" _m03_conf_vaut '^scsihw: virtio-scsi-(single|pci)$'
check_cmd "VM 2036 : le disque système est dans l'ordre d'amorçage" _m03_conf_vaut '^boot: order=([^;]*;)*(scsi|virtio|sata)0'

title "Image Rocky (prévention)"
_m03_e22_tpl() {
  local id
  id="$(_m03_current rocky10)"
  [[ -n "$id" ]] || id=9002
  _m03_conf "$id" | grep -Eq '^cpu: (x86-64-v[34]|host)([,]|$)'
}
check_cmd "template Rocky de référence (current, sinon 9002) : CPU x86-64-v3 ou host" _m03_e22_tpl
check_cmd "journal de diagnostic de l'incident (docs/socle/journal/, INC-3010)" \
  bash -c 'grep -rqs "INC-3010" "$1"' _ "$_M03_DOC/journal"
