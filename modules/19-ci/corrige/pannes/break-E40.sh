# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq et jq entre apostrophes
# break-E40.sh — M19-E40 « Panne : un secret apparaît dans un journal de job »
#
# Cible : le projet témoin (variable CANARI_JETON, jeton d'accès de projet canari-lecture). Variantes :
#   1. la variable CANARI_JETON perd son masquage (Lucas « voulait vérifier sa valeur ») : la ligne
#      « env | grep ^CANARI_ » du job l'affiche en clair (sans effet si la variable est « masquée et
#      cachée » : elle ne peut plus être démasquée, variante sautée) ;
#   2. Lucas publie une version du composant canari avec « set -x » en before_script : la trace bash
#      montre l'en-tête Basic calculé (base64 de « canari:<jeton> »), que le masquage ne reconnaît pas ;
#   3. variable de projet CI_DEBUG_TRACE=true (« pour comprendre un échec ») : même fuite par la trace
#      de débogage du runner.
# Vérification : un pipeline du témoin, et la valeur (ou son base64) est cherchée dans le journal.
# Les jobs fautifs et l'identifiant du jeton exposé sont notés dans ~/.local/state/workbook/M19-E40.fuites
# (lu par le contrôle : la réparation comprend la rotation du jeton et l'effacement des journaux).
# --annuler fait la rotation et l'effacement s'ils n'ont pas été faits.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m19-commun.sh
source "$WB_ROOT/modules/19-ci/corrige/pannes/_m19-commun.sh"

_E40_FUITES="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M19-E40.fuites"

_e40_var() { m19_api GET "projects/$(m19_enc "$_M19_TEMOIN")/variables/$1"; }

# _e40_jeton_id — identifiant du jeton d'accès actif « canari-lecture » du témoin.
_e40_jeton_id() {
  m19_api GET "projects/$(m19_enc "$_M19_TEMOIN")/access_tokens?state=active&per_page=100" |
    jq -r '[.[] | select(.name == "canari-lecture" and .active)] | max_by(.id) | .id // empty'
}

# _e40_fuite_constatee — un pipeline du canari ; le journal contient le jeton ou l'en-tête Basic.
_e40_fuite_constatee() {
  local v b st id tr
  v="$(_e40_var CANARI_JETON | jq -r '.value // empty')"
  [[ -n "$v" ]] || return 1
  b="$(printf 'canari:%s' "$v" | base64 | tr -d '\n')"
  read -r st id < <(m19_temoin_cycle 420)
  [[ -n "$id" ]] || return 1
  tr="$(m19_trace "$_M19_TEMOIN" "$id" 2>/dev/null)" || return 1
  if grep -qF -- "$v" <<<"$tr" || grep -qF -- "$b" <<<"$tr"; then
    mkdir -p "$(dirname "$_E40_FUITES")"
    (umask 077 && printf 'job %s jeton %s %s\n' "$id" "$(_e40_jeton_id)" "$(date -Is)" >>"$_E40_FUITES")
    return 0
  fi
  return 1
}

_m19E40_une() {
  local n="$1" pid j
  m19_debut E40
  pid="$(m19_temoin_id)" || return 1
  case "$n" in
    1)
      j="$(_e40_var CANARI_JETON)" || return 10
      jq -e '.masked and ((.hidden // false) | not)' >/dev/null <<<"$j" || return 10
      m19_api PUT "projects/$pid/variables/CANARI_JETON" --data-urlencode "masked=false" \
        --data-urlencode "description=Lucas : démasquée pour vérifier la valeur (M19-E40)" >/dev/null || return 1
      m19_ecrire E40 demasquee 1
      ;;
    2)
      m19_canari_publier E40 "chore(canari): trace des commandes pour le débogage" \
        '(select(documentIndex == 1) | .canari.before_script) = ["set -x"]' >/dev/null || return $?
      ;;
    3)
      if _e40_var CI_DEBUG_TRACE >/dev/null 2>&1; then return 10; fi
      m19_api POST "projects/$pid/variables" --data-urlencode "key=CI_DEBUG_TRACE" --data-urlencode "value=true" \
        --data-urlencode "description=Lucas : pour comprendre l'échec d'hier (M19-E40)" >/dev/null || return 1
      m19_ecrire E40 debug 1
      ;;
  esac
  m19_journal E40 "variante $n posée"
  _e40_fuite_constatee || { _e40_defaire "$n"; return 10; }
  m19_journal E40 "variante $n constatée"
}

_e40_defaire() {
  local n="$1" pid j
  pid="$(m19_temoin_id 2>/dev/null)" || pid=""
  case "$n" in
    1)
      if [[ -n "$(m19_lire E40 demasquee)" ]]; then
        j="$(_e40_var CANARI_JETON 2>/dev/null)" || j=""
        if jq -e '(.masked | not) and ((.description // "") | test("M19-E40"))' >/dev/null 2>&1 <<<"$j"; then
          m19_api PUT "projects/$pid/variables/CANARI_JETON" --data-urlencode "masked=true" \
            --data-urlencode "protected=true" --data-urlencode "description=" >/dev/null || wb_avert "CANARI_JETON non remasquée"
        fi
      fi
      m19_oublier E40 demasquee
      ;;
    2) m19_temoin_retablir E40 ;;
    3)
      if [[ -n "$(m19_lire E40 debug)" ]]; then
        j="$(_e40_var CI_DEBUG_TRACE 2>/dev/null)" || j=""
        if jq -e '(.description // "") | test("M19-E40")' >/dev/null 2>&1 <<<"$j"; then
          m19_api DELETE "projects/$pid/variables/CI_DEBUG_TRACE" >/dev/null || wb_avert "CI_DEBUG_TRACE non retirée"
        fi
      fi
      m19_oublier E40 debug
      ;;
  esac
}

# _e40_assainir — filet de --annuler : rotation du jeton exposé et effacement des journaux fautifs,
# s'ils n'ont pas été faits par l'apprenant.
_e40_assainir() {
  local pid job tid r tok etat
  [[ -f "$_E40_FUITES" ]] || return 0
  pid="$(m19_temoin_id 2>/dev/null)" || return 0
  while read -r _ job _ tid _; do
    [[ -n "$job" ]] || continue
    etat="$(m19_api GET "projects/$pid/jobs/$job" 2>/dev/null | jq -r '.erased_at // empty')" || etat="x"
    if [[ -z "$etat" ]]; then
      m19_api POST "projects/$pid/jobs/$job/erase" >/dev/null 2>&1 || wb_avert "journal du job $job non effacé"
    fi
    [[ -n "$tid" ]] || continue
    if m19_api GET "projects/$pid/access_tokens/$tid" 2>/dev/null | jq -e '.active' >/dev/null 2>&1; then
      r="$(m19_api POST "projects/$pid/access_tokens/$tid/rotate" --data-urlencode "expires_at=$(date -d '+90 days' +%F)")" || r=""
      tok="$(jq -r '.token // empty' <<<"$r")"
      if [[ -n "$tok" ]]; then
        m19_api PUT "projects/$pid/variables/CANARI_JETON" --data-urlencode "value=$tok" \
          --data-urlencode "masked=true" --data-urlencode "protected=true" >/dev/null || wb_avert "CANARI_JETON non mise à jour"
      else
        wb_avert "rotation du jeton canari-lecture ($tid) impossible"
      fi
    fi
  done <"$_E40_FUITES"
}

panne_E40_v1() { m19_preparer && m19_essayer E40 3 1; }
panne_E40_v2() { m19_preparer && m19_essayer E40 3 2; }
panne_E40_v3() { m19_preparer && m19_essayer E40 3 3; }

verifier_E40() {
  case "${WB_VAR:-}" in
    1) _e40_var CANARI_JETON | jq -e '.masked | not' >/dev/null ;;
    2) m19_brut "$_M19_TEMOIN" .gitlab-ci.yml main | grep -q "canari@$(m19_lire E40 canari-version)" ;;
    3) _e40_var CI_DEBUG_TRACE >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

annuler_E40() {
  case "${WB_VAR:-}" in
    [1-3]) _e40_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3; do _e40_defaire "$v"; done ;;
  esac
  _e40_assainir
  m19_oublier E40 canari-version
  m19_oublier E40 debut
  m19_journal E40 "annulation"
}

resume_E40() { echo "Sophie : le jeton CANARI_JETON du canari apparaît en clair (ou presque) dans un journal de job."; }

symptome_E40() {
  wb_symptome "Ticket SEC-2040 — De : Sophie Laurent (RSSI) — priorité haute" \
    "Un développeur me signale qu'en lisant le journal du dernier job du canari" \
    "(formation/ci-pannes), il a vu passer ce qui ressemble au jeton CANARI_JETON, ou à une" \
    "valeur dérivée. La variable est censée être masquée. Je veux : la fuite arrêtée, le" \
    "secret considéré comme compromis et remplacé, les journaux exposés effacés, et une" \
    "explication écrite de ce qui a contourné le masquage." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 19 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 19 E40 3 "$@"; }
fi
