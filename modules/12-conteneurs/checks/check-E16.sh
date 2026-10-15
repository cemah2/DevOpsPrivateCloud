# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes : évaluées à distance
#
# check-E16.sh — M12-E16 : Hadolint et Dive : la qualité d'une image
# À lancer depuis adm01. Lecture seule : versions des outils sur ctr01 ; Hadolint et Dive lancés sur
# ctr01 avec les fichiers de main transmis sur l'entrée standard (rien n'est écrit sur l'hôte) ;
# API GitLab en GET.

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E16 — Hadolint et Dive : la qualité d'une image"
require_cmd jq base64

check_output "ctr01 : Hadolint 2.15.1" '2\.15\.1' _m12o_ssh "$_M12O_CTR01" 'hadolint --version'
check_output "ctr01 : Dive 0.13.1" '0\.13\.1' _m12o_ssh "$_M12O_CTR01" 'dive --version'

# _m12o_e16_hadolint PROJET — Hadolint de ctr01 sur le Dockerfile de main avec le .hadolint.yaml du
# projet ; les deux fichiers voyagent en base64 dans la commande (lus par des descripteurs, sans écrire).
_m12o_e16_hadolint() {
  local c d
  c="$(_m12o_fichier "$1" .hadolint.yaml)"
  d="$(_m12o_fichier "$1" Dockerfile)"
  [[ -n "$c" && -n "$d" ]] || return 1
  remote "$_M12O_CTR01" "bash -c 'hadolint --no-color -c <(echo $(base64 -w0 <<<"$c") | base64 -d) <(echo $(base64 -w0 <<<"$d") | base64 -d)'" >/dev/null 2>&1
}
for _m12o_e16_p in mediagenda/api medidoc/medidoc; do
  _m12o_e16_cfg="$(_m12o_fichier "$_m12o_e16_p" .hadolint.yaml)"
  check_cmd "$_m12o_e16_p (main) : .hadolint.yaml avec failure-threshold warning et étiquettes obligatoires" \
    bash -c 'grep -Eq "^failure-threshold: *warning" <<<"$1" && grep -Eq "^label-schema:" <<<"$1"' _ "$_m12o_e16_cfg"
  check_cmd "$_m12o_e16_p (main) : .dive-ci présent" test -n "$(_m12o_fichier "$_m12o_e16_p" .dive-ci)"
  check_cmd "$_m12o_e16_p (main) : le Dockerfile passe Hadolint avec cette configuration" _m12o_e16_hadolint "$_m12o_e16_p"
done

# _m12o_e16_dive — Dive en mode CI sur mediagenda-api:0.2.0 avec les seuils du .dive-ci de main,
# passés en options : le .dive-ci du dépôt n'est pas sur ctr01, et le check n'y écrit rien.
_m12o_e16_dive() {
  local c opts="" cle val
  c="$(_m12o_fichier mediagenda/api .dive-ci)"
  [[ -n "$c" ]] || return 1
  for cle in lowestEfficiency highestWastedBytes highestUserWastedPercent; do
    val="$(sed -nE "s/^ *$cle: *([0-9.]+[A-Za-z]*) *(#.*)?$/\1/p" <<<"$c" | head -n 1)"
    [[ -n "$val" ]] && opts="$opts --$cle $val"
  done
  [[ -n "$opts" ]] || return 1
  remote "$_M12O_CTR01" "CI=true dive$opts mediagenda-api:0.2.0" 2>/dev/null | grep -q 'Result:PASS'
}
check_cmd "ctr01 : mediagenda-api:0.2.0 passe dive --ci avec le .dive-ci du projet" _m12o_e16_dive
check_cmd "plateforme/medisphere (main) : docs/conteneurs/qualite-images.md (mesures et seuils)" \
  bash -c 'grep -Eiq "dive|efficacit" <<<"$1" && grep -Eiq "hadolint" <<<"$1"' _ "$(_m12o_fichier plateforme/medisphere docs/conteneurs/qualite-images.md)"
