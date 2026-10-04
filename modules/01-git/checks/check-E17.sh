# shellcheck shell=bash
# shellcheck disable=SC2016  # variables jq entre apostrophes
#
# check-E17.sh — M01-E17 : secret poussé dans formation/labo-fuite (rotation, purge)
# Lancé depuis adm01. Lecture seule : API GitLab (jeton des checks) et clone miroir temporaire
# du projet (SSH, ta clé), supprimé en fin de contrôle.

title "M01-E17 — Un secret a été poussé : purge, rotation, communication"
require_cmd curl jq git

_m01_etat="$HOME/.local/state/workbook/ressources/M01-E17.env"
_m01_pid=""; _m01_tid=""
if [[ -r "$_m01_etat" ]]; then
  _m01_pid="$(sed -n 's/^PROJET_ID=//p' "$_m01_etat" | tail -n 1)"
  _m01_tid="$(sed -n 's/^JETON_ID=//p' "$_m01_etat" | tail -n 1)"
fi
check_cmd "l'atelier a été préparé (ressources/M01-E17/fabriquer-depot.sh)" test -n "$_m01_pid" -a -n "$_m01_tid"

if [[ -n "$_m01_pid" && -n "$_m01_tid" ]]; then
  _m01_jetons="$(gitlab_api "projects/$_m01_pid/access_tokens?state=inactive&per_page=100" 2>/dev/null)" || _m01_jetons="[]"
  check_cmd "le jeton exposé « collecte-medisphere » est révoqué" \
    jq -e --argjson t "$_m01_tid" 'any(.[]; .id == $t and .revoked == true)' <<<"$_m01_jetons"

  _m01_pb="$(gitlab_api "projects/$_m01_pid/protected_branches/main" 2>/dev/null)" || _m01_pb="{}"
  check_cmd "main est de nouveau protégée, sans push forcé" jq -e '.name == "main" and .allow_force_push == false' <<<"$_m01_pb"

  _m01_tmp="$(mktemp -d)"
  _m01_url="git@${WB_GITLAB_URL#*://}:formation/labo-fuite.git"
  _m01_url="${_m01_url/\/:/:}"
  if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=$WB_TIMEOUT" \
       git clone -q --mirror "$_m01_url" "$_m01_tmp/miroir.git" >/dev/null 2>&1; then
    _m01_g() { git -C "$_m01_tmp/miroir.git" "$@"; }
    # Toutes les révisions de toutes les références visibles (branches, étiquettes, refs/merge-requests/*)
    _m01_propre() {
      local revs
      revs="$(_m01_g rev-list --all)" || return 1
      # shellcheck disable=SC2086  # liste de révisions découpée volontairement
      ! _m01_g grep -I -q -E 'glpat-[0-9A-Za-z_.-]{20,}|Collecte-2026!' $revs 2>/dev/null
    }
    check_cmd "aucune révision accessible du dépôt (branches, étiquettes, MR) ne contient le jeton ni le mot de passe" _m01_propre
    check_cmd "l'étiquette v0.1.0 existe toujours (réécrite, pas supprimée)" _m01_g rev-parse -q --verify refs/tags/v0.1.0
    check_cmd "la branche main existe et contient le script de collecte" _m01_g cat-file -e main:scripts/collecte.sh
    _m01_ignore() {
      _m01_g show main:.gitignore 2>/dev/null | grep -Eq '(^|/)(\*\.env|config/\*\.env|config/collecte\.env|config/?)$'
    }
    check_cmd ".gitignore de main empêche de recommiter le fichier de configuration" _m01_ignore
  else
    check_cmd "clone miroir SSH de formation/labo-fuite (clé chargée dans l'agent ?)" false
  fi
  rm -rf "$_m01_tmp"
else
  skip "rotation et purge" "atelier non préparé"
fi
