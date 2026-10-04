# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # les commandes entre apostrophes sont évaluées sur l'hôte distant
#
# check-E36.sh — M01-E36 « Panne : git push est refusé »
# Chaîne de poussée de ~/medisphere vers plateforme/medisphere : URL de poussée, accès SSH,
# état du projet, règles de protection, hooks globaux de Gitaly. Lecture seule (aucune poussée).

# shellcheck source=_m01-palier4.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-palier4.sh"

title "M01-E36 — Panne : git push est refusé"
require_cmd git ssh jq curl

_m01_depot="${WB_DEPOT:-$HOME/medisphere}"
_m01_pushurl="$(git -C "$_m01_depot" remote get-url --push origin 2>/dev/null)" || _m01_pushurl=""

check_cmd "dépôt ~/medisphere présent" git -C "$_m01_depot" rev-parse --is-inside-work-tree
check_output "dépôt ~/medisphere : la poussée vise plateforme/medisphere sur git01" \
  "^(git@|ssh://git@)${_M01_FQDN_GIT}[:/]plateforme/medisphere(\.git)?$" printf '%s\n' "$_m01_pushurl"
check_cmd "ssh git@$_M01_FQDN_GIT : GitLab accueille ton compte" _m01_ssh_bienvenue
check_cmd "l'URL de poussée désigne un dépôt lisible (git ls-remote)" \
  env GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ControlPath=none" GIT_TERMINAL_PROMPT=0 \
  git ls-remote --exit-code "${_m01_pushurl:-absent}" HEAD
check_cmd "plateforme/medisphere : projet non archivé" _m01_api_ok "$_M01_P_MED" '.archived == false'
check_cmd "plateforme/medisphere : main reste protégée (poussée directe interdite à tous)" \
  _m01_api_ok "$_M01_P_MED/protected_branches/main" '[.push_access_levels[].access_level] | length > 0 and all(. == 0)'

# Aucune règle de protection ne doit capturer une branche de travail ordinaire.
_m01_e36_branches_libres() {
  local noms n
  noms="$(gitlab_api "$_M01_P_MED/protected_branches?per_page=100" 2>/dev/null | jq -r '.[].name')" || return 1
  while IFS= read -r n; do
    [[ -z "$n" || "$n" == main ]] && continue
    # shellcheck disable=SC2053  # n est un motif GitLab (joker *) à interpréter
    if [[ feat/essai-de-poussee == $n || fix/essai == $n ]]; then return 1; fi
  done <<<"$noms"
}
check_cmd "plateforme/medisphere : aucune règle de protection ne couvre les branches de travail" \
  _m01_e36_branches_libres

check_ssh "git01 : chaque hook global pre-receive accepte une poussée vide" git01 '
  d=$(sudo -n sed -nE "s/^[[:space:]]*custom_hooks_dir[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" /var/opt/gitlab/gitaly/config.toml | head -n 1)
  [ -n "$d" ] || exit 0
  for h in $(sudo -n find "$d/pre-receive.d" -maxdepth 1 -type f -perm -u+x ! -name "*~" 2>/dev/null | sort); do
    cd /tmp && sudo -n -u git env GL_PROTOCOL=ssh GL_USERNAME=verification GL_ID=user-0 \
      GL_PROJECT_PATH=plateforme/medisphere GL_REPOSITORY=project-0 "$h" </dev/null >/dev/null 2>&1 || exit 1
  done'
