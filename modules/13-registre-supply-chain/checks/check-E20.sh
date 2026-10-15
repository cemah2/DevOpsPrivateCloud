# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# check-E20.sh — M13-E20 « Panne : la publication de l'image échoue » : quota et immuabilité de
# wb-sonde, droit de poussée du robot (jeton demandé, rien n'est poussé), horloge de runner02, politiques
# de medisphere intactes.

# shellcheck source=_m13-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m13-expert.sh"

title "M13-E20 — La publication passe"
require_cmd jq curl

check_cmd "Harbor répond « healthy »" _m13p_sante
check_ssh "runner02 : chrony actif" "$_m13x_runner" 'systemctl is-active -q chrony'
check_ssh "runner02 : horloge synchronisée (écart < 1 s)" "$_m13x_runner" \
  'o=$(chronyc tracking 2>/dev/null | sed -nE "s/^System time *: *([0-9.]+) seconds.*/\1/p"); [ -n "$o" ] && awk -v o="$o" "BEGIN { exit !(o < 1) }"'
check_ssh "runner02 : certificat de Harbor valide à la date de runner02" "$_m13x_runner" \
  'echo | timeout 10 openssl s_client -connect '"$_M13P_REGISTRE_NOM"':443 -servername '"$_M13P_REGISTRE_NOM"' -verify_return_error >/dev/null 2>&1'
check_cmd "medisphere : une règle d'immuabilité vise les versions v* (inchangée)" \
  bash -c 'jq -e "any(.[]?; (.disabled | not) and any(.tag_selectors[]?; .pattern | startswith(\"v\")))" >/dev/null 2>&1 <<<"$1"' _ \
  "$(_m13p_api projects/medisphere/immutabletagrules || true)"
check_cmd "medisphere : signature exigée (inchangée)" _m13p_projet_meta medisphere enable_content_trust_cosign true

if _m13x_temoins; then
  _m13_e20_r="$(_m13p_api projects/wb-sonde/immutabletagrules)" || _m13_e20_r=""
  check_cmd "wb-sonde : aucune règle d'immuabilité active ne couvre l'étiquette « courant »" _m13p_jq "${_m13_e20_r:-[]}" \
    '[.[]? | select((.disabled | not) and any(.tag_selectors[]?; .pattern == "**" or .pattern == "*" or .pattern == "courant" or (.pattern | startswith("{"))))] | length == 0'
  _m13_e20_marge() {
    local pid q
    pid="$(_m13p_api projects/wb-sonde | jq -r '.project_id // empty')" || return 1
    q="$(_m13p_api "quotas?reference=project&reference_id=$pid" | jq -c '.[0] // empty')" || return 1
    [[ -n "$q" ]] && jq -e '(.hard.storage == -1) or (.hard.storage - .used.storage >= 1073741824)' >/dev/null 2>&1 <<<"$q"
  }
  check_cmd "wb-sonde : pas de quota, ou au moins 1 Gio de marge" _m13_e20_marge
  check_cmd "sonde : le jeton du robot wb-sonde-ci accorde la poussée sur wb-sonde" _m13x_sonde_lecture poussee
else
  skip "contrôles des témoins" "témoins pas encore créés (ils le sont à la première injection)"
fi
check_cmd "RB-133 contient une section publication" _m13p_doc_main "$(gitlab_api 'projects/plateforme%2Fmedisphere/repository/tree?ref=main&path=docs%2Fregistre%2Frunbooks&per_page=100' 2>/dev/null | jq -r '[.[]? | select(.name | startswith("RB-133")) | .path][0] // "absent"' 2>/dev/null || echo absent)" 'publication'
check_cmd "panne M13-E20 close (lab/bin/break 13 20 --annuler après réparation)" _m13p_aucune_panne_active E20
