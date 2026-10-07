# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions évaluées par le bash -c
#
# check-E14.sh — M05-E14 : Versionner les modules dans plateforme/tofu-modules
# Lecture seule : API GitLab (jeton des checks), copie de travail ~/src/infra.

# shellcheck source=_m05-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m05-operationnel.sh"

title "M05-E14 — Versionner les modules dans plateforme/tofu-modules"
require_cmd jq curl git

_m05o_p="$(_m05o_projet plateforme/tofu-modules)"
# Lectures GitLab : fonctions locales (gitlab_api n'existe pas dans un « bash -c »).
_m05o_gl() { gitlab_api "$_m05o_p$1" | jq -r "$2"; }
check_output "projet plateforme/tofu-modules, branche par défaut main" '^main$' _m05o_gl "" '.default_branch'
check_output "main protégée : personne ne pousse directement" '^0$' \
  _m05o_gl /protected_branches/main '.push_access_levels[0].access_level'
check_output "étiquettes v* protégées" '^v\*$' _m05o_gl /protected_tags '.[].name'
check_output ".releaserc.json sur main" 'releaserc' _m05o_gl '/repository/files/.releaserc.json?ref=main' '.file_name'
_m05o_tags="$(_m05o_gl '/repository/tags?per_page=100' '.[].name' 2>/dev/null || true)"
check_output "au moins deux versions publiées vX.Y.Z (une première, puis une évolution)" '^([2-9]|[1-9][0-9]+)$' \
  bash -c 'grep -Ec "^v[0-9]+\.[0-9]+\.[0-9]+$" <<<"$1"' _ "$_m05o_tags"
check_output "une release GitLab (notes de version) pour la dernière étiquette" '^v[0-9]+\.[0-9]+\.[0-9]+$' \
  _m05o_gl '/releases?per_page=1' '.[0].tag_name // empty'
check_output "plateforme/infra autorisé à lire les modules avec son jeton de job" '^plateforme/infra$' \
  _m05o_gl /job_token_scope/allowlist '.[].path_with_namespace'

# --- Consommation par étiquette dans plateforme/infra ------------------------------------------------
_m05o_refs="$(grep -rhoEs 'tofu-modules\.git//[a-z0-9-]+\?ref=[^"]+' --include='*.tf' "$_m05o_infra" | sort -u || true)"
check_output "plateforme/infra consomme vm-debian depuis la forge" 'tofu-modules\.git//vm-debian\?ref=' \
  printf '%s\n' "$_m05o_refs"
check_cmd "toutes les références de modules sont des étiquettes vX.Y.Z (jamais une branche)" \
  bash -c '[ -n "$1" ] && ! grep -Ev "\?ref=v[0-9]+\.[0-9]+\.[0-9]+$" <<<"$1"' _ "$_m05o_refs"
check_cmd "chaque étiquette référencée existe sur la forge" \
  bash -c 'for r in $(sed -E "s/.*\?ref=//" <<<"$1" | sort -u); do grep -qx "$r" <<<"$2" || exit 1; done' _ "$_m05o_refs" "$_m05o_tags"
check_cmd "adm01 : les sources HTTPS de la forge passent par SSH (insteadOf)" \
  bash -c 'git config --get-regexp "^url\..*\.insteadof$" | grep -q "https://git01.par1.medisphere.internal/"'
check_cmd "la VM d'essai m05-module a été détruite en fin d'exercice" \
  bash -c '! grep -q "^name: m05-module$" <<<"$1"' _ "$(_m05o_qm 2054)"
