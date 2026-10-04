# shellcheck shell=bash
#
# check-E14.sh — M01-E14 : Conventional Commits et commitlint en local
# Lancé depuis adm01. Lecture seule (outils locaux, clone $WB_DEPOT, API GitLab).

title "M01-E14 — Conventional Commits et commitlint en local"
require_cmd curl jq git node

_m01_depot="${WB_DEPOT:-$HOME/medisphere}"

check_output "Node.js 24 (ou plus récent) sur adm01" '^v(2[4-9]|[3-9][0-9])\.' node --version
check_output "commitlint 21 disponible dans le PATH" '@commitlint/cli@21\.' commitlint --version

_m01_conf="$(gitlab_api "projects/plateforme%2Fmedisphere/repository/files/commitlint.config.mjs/raw?ref=main" 2>/dev/null)" || _m01_conf=""
check_cmd "commitlint.config.mjs est sur main de plateforme/medisphere" test -n "$_m01_conf"
check_cmd "commitlint.config.mjs étend @commitlint/config-conventional" \
  grep -q '@commitlint/config-conventional' <<<"$_m01_conf"

# Comportement réel, depuis ton clone (configuration du dépôt)
_m01_lint() { (cd "$_m01_depot" && printf '%s\n' "$1" | commitlint >/dev/null 2>&1); }
_m01_refuse() { ! _m01_lint "$1"; }
check_cmd "dans $_m01_depot, un message conforme est accepté" _m01_lint "docs(socle): préciser l'adresse de git01"
check_cmd "dans $_m01_depot, un message sans type est refusé" _m01_refuse "Mise à jour de la doc"
check_cmd "dans $_m01_depot, un type inconnu est refusé" _m01_refuse "update: inventaire"

# Historique de main depuis l'arrivée de la configuration
_m01_historique() {
  local sha
  sha="$(git -C "$_m01_depot" log origin/main --diff-filter=A --format=%H -1 -- commitlint.config.mjs 2>/dev/null)"
  [[ -n "$sha" ]] || return 1
  (cd "$_m01_depot" && commitlint --from "${sha}^" --to origin/main >/dev/null 2>&1)
}
check_cmd "tous les commits de main depuis l'ajout de commitlint passent commitlint (après git fetch)" _m01_historique
