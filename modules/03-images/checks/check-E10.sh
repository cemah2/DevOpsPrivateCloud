# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # « $v » est une variable jq, pas du shell
#
# check-E10.sh — M03-E10 « Versionner et publier les images »
# Lecture seule. N'exécute les outils que dans des cas de mauvais usage (code 2), qui
# doivent être refusés avant tout appel à Proxmox.

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E10 — Versionner et publier les images"
require_cmd jq shellcheck
_m03_charger

title "Outils"
_m03_e10_code() { # CODE_ATTENDU commande…
  local attendu="$1" rc=0
  shift
  "$@" >/dev/null 2>&1 </dev/null || rc=$?
  [[ "$rc" == "$attendu" ]]
}
for _m03_e10_f in outils/version-image.sh outils/publier-image.sh tests/tester-image.sh; do
  check_cmd "$_m03_e10_f exécutable" test -x "$_M03_SRC/$_m03_e10_f"
  check_cmd "$_m03_e10_f sans remarque ShellCheck" shellcheck -x "$_M03_SRC/$_m03_e10_f"
  check_cmd "$_m03_e10_f publié sur main" _m03_fichier_main "$_m03_e10_f"
done
check_cmd "version-image.sh : famille inconnue refusée (code 2)" \
  _m03_e10_code 2 "$_M03_SRC/outils/version-image.sh" famille-inconnue
check_cmd "publier-image.sh : sans argument, refus d'usage (code 2)" \
  _m03_e10_code 2 "$_M03_SRC/outils/publier-image.sh"
check_cmd "tester-image.sh : sans argument, refus d'usage (code 2)" \
  _m03_e10_code 2 "$_M03_SRC/tests/tester-image.sh"
check_cmd "publier-image.sh lance le test avant toute publication" \
  grep -q 'tester-image\.sh' "$_M03_SRC/outils/publier-image.sh"

title "Manifeste du build doré"
check_cmd "post-processor manifest dans debian13-gold" \
  _m03_fichier_main_contient debian13-gold/build.pkr.hcl 'post-processor "manifest"'
check_cmd "liste des paquets rapatriée (provisioner file, direction download)" \
  _m03_fichier_main_contient debian13-gold/build.pkr.hcl 'direction *= *"download"'

title "Publication"
_m03_e10_cur="$(_m03_current debian13)"
check_cmd "exactement une image dorée Debian « current » (${_m03_e10_cur:-aucune ou plusieurs})" test -n "$_m03_e10_cur"
_m03_e10_notes="$(remote "$WB_PVE_HOST" "pvesh get /nodes/\$(hostname)/qemu/${_m03_e10_cur:-0}/config --output-format json" 2>/dev/null \
  | jq -r '.description // ""')" || _m03_e10_notes=""
check_output "notes de la version current : date de publication et test" '[Pp]ubli.*20[0-9]{2}-[0-9]{2}-[0-9]{2}' \
  printf '%s\n' "$_m03_e10_notes"
check_output "notes de la version current : empreinte de la liste des paquets" '[Pp]aquets.*[0-9a-f]{64}' \
  printf '%s\n' "$_m03_e10_notes"
check_cmd "nom de la version current conforme (deb13-gold-AAAAMMJJ-N)" \
  jq -e --argjson v "${_m03_e10_cur:-0}" 'any(.[]; .vmid == $v and (.name | test("^deb13-gold-20[0-9]{6}-[0-9]+$")))' \
  <<<"$(_m03_vms)"

title "Hygiène"
check_cmd "aucune VM de test restante (2030-2033)" _m03_aucune_vm 2030 2033
