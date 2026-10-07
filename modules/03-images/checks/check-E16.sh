# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
#
# check-E16.sh — M03-E16 « Cycle de vie : rotation et retrait des images »
# État du catalogue (rétention appliquée, une seule version current par famille), présence
# de l'outil de rotation, de son appel en CI et du runbook de retrait. Le check ne lance pas
# l'outil de rotation (il peut supprimer des templates).

# shellcheck source=_m03-production.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m03-production.sh"

title "M03-E16 — Cycle de vie : rotation et retrait des images"
require_cmd jq ssh curl shellcheck
_m03_charger
_m03_r="$_M03_SRC/outils/rotation-images.sh"

title "Outil de rotation"
check_cmd "outils/rotation-images.sh présent et exécutable (clone local)" test -x "$_m03_r"
check_cmd "outils/rotation-images.sh sans remarque ShellCheck" shellcheck -x "$_m03_r"
check_cmd "outils/rotation-images.sh publié sur main" _m03_fichier_main outils/rotation-images.sh
check_output "--help décrit l'usage" '[Uu]sage' "$_m03_r" --help
check_cmd "l'outil contrôle les clones liés avant suppression" grep -Eq 'base-|clone' "$_m03_r"
check_cmd "le pipeline applique la rotation après publication (.gitlab-ci.yml sur main)" \
  _m03_fichier_main_contient .gitlab-ci.yml 'rotation-images\.sh'

title "Catalogue Debian 13 (9010-9029)"
_m03_e16_nb() { _m03_gold debian13 | jq 'length'; }
_m03_e16_max5() { local n; n="$(_m03_e16_nb)"; [[ "$n" -ge 1 && "$n" -le 5 ]]; }
check_cmd "entre 1 et 5 images dorées Debian (3 dernières + current + au plus une rejetée)" _m03_e16_max5
_m03_e16_noms() {
  _m03_gold debian13 | jq -e 'all(.[]; (.name | test("^deb13-gold-[0-9]{8}-[0-9]+$")) and .vmid >= 9010 and .vmid <= 9029)' >/dev/null
}
check_cmd "noms conformes deb13-gold-AAAAMMJJ-N et VMID dans 9010-9029" _m03_e16_noms
_m03_a_current() { [[ -n "$(_m03_current "$1")" ]]; }
check_cmd "une seule version étiquetée current" _m03_a_current debian13
check_cmd "aucun template d'essai oublié (9090-9099)" _m03_aucune_vm 9090 9099

title "Documentation"
_m03_e16_rb() {
  local f
  for f in "$_M03_DOC"/runbooks/RB-03*.md; do
    [[ -f "$f" ]] && grep -qi 'retrait' "$f" && grep -qi 'clone' "$f" && return 0
  done
  return 1
}
check_cmd "runbook de retrait d'une image (docs/socle/runbooks/RB-03x, retrait et clones liés)" _m03_e16_rb
