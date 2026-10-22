# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq et yq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E40.sh — M19-E40 « Panne : un secret apparaît dans un journal de job » : variable remasquée et
# protégée, pas de trace de débogage, pas de set -x dans le composant consommé, jeton exposé révoqué
# (rotation), journaux fautifs effacés, RB-198 et note d'incident, panne close. Lecture seule : les
# valeurs des variables ne sont jamais lues ni affichées, seulement leurs attributs.

# shellcheck source=_m19-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m19-expert.sh"

title "M19-E40 — Le secret ne fuit plus et a été remplacé"
require_cmd jq yq curl

if _m19x_temoin_existe; then
  _m19_e40_p="projects/$(_m19x_enc "$_m19x_temoin")"
  check_cmd "CANARI_JETON : masquée et protégée" _m19x_gl '.masked and .protected' "$_m19_e40_p/variables/CANARI_JETON"
  check_cmd "aucune variable CI_DEBUG_TRACE ou CI_DEBUG_SERVICES dans le témoin" \
    _m19x_gl '[.[].key | select(test("^CI_DEBUG_"))] | length == 0' "$_m19_e40_p/variables?per_page=100"
  _m19_e40_sans_trace() {
    local g
    g="$(_m19x_canari_gabarit)" || return 1
    [[ -n "$g" ]] && ! grep -Eq 'set -[a-wyz]*x|xtrace' <<<"$g"
  }
  check_cmd "composant canari consommé : pas de « set -x » ni de « set -o xtrace »" _m19_e40_sans_trace
  _m19_e40_f="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M19-E40.fuites"
  if [[ -s "$_m19_e40_f" ]]; then
    _m19_e40_effaces() {
      local job
      while read -r _ job _; do
        gitlab_api "$_m19_e40_p/jobs/$job" 2>/dev/null | jq -e '.erased_at != null' >/dev/null 2>&1 || return 1
      done <"$_m19_e40_f"
    }
    _m19_e40_revoques() {
      local tid
      while read -r _ _ _ tid _; do
        [[ -n "$tid" ]] || continue
        gitlab_api "$_m19_e40_p/access_tokens/$tid" 2>/dev/null | jq -e '(.active | not) or .revoked' >/dev/null 2>&1 || return 1
      done <"$_m19_e40_f"
    }
    check_cmd "journaux des jobs qui ont exposé le secret effacés (erase)" _m19_e40_effaces
    check_cmd "jeton canari-lecture exposé révoqué ou remplacé (rotation)" _m19_e40_revoques
  else
    skip "journaux et jeton exposés" "aucune fuite enregistrée (injecte d'abord : lab/bin/break 19 40)"
  fi
  check_cmd "dernier canari de main réussi, jeton toujours masqué dans le journal" _m19x_canari_trace 'CANARI_JETON=\[MASKED\]'
else
  skip "témoin $_m19x_temoin" "absent : il est créé à la première injection (lab/bin/break 19 40)"
fi
_m19_e40_rb() { _m19x_doc_contient 'RB-198*.md' 'rotation' && _m19x_doc_contient 'RB-198*.md' 'efface|erase'; }
check_cmd "RB-198 : fuite d'un secret en CI (rotation, effacement des journaux, cause)" _m19_e40_rb
check_cmd "RB-198 : aucun jeton recopié" _m19x_sans_secret 'RB-198*.md'
check_cmd "panne M19-E40 close (lab/bin/break 19 40 --annuler après réparation)" _m19x_aucune_panne_active E40
