# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S06.sh — F7-S06 « Planning, risques et organisation du run » (RED publié) : présence et contenu
# minimal de docs/capstone/planning.md (jalons datés, chemin critique, RACI), risques.md (risques RSQ-nn
# évalués, avec propriétaire) et run.md (support, samedi, astreinte, priorités, rapport mensuel, montée
# en compétences). Lecture seule (GitLab). La qualité se juge avec le corrigé.

# shellcheck source=_f7-capstone.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-capstone.sh"

title "F7-S06 — Planning, risques et organisation du run"
require_cmd curl jq

_f7c_charger planning.md risques.md run.md
_f7_s06_planning="$(_f7c_doc planning.md)"
_f7_s06_risques="$(_f7c_doc risques.md)"

check_cmd "planning.md présent sur main ($_f7c_doc_dir/)" _f7c_doc_present planning.md
if [[ -n "$_f7_s06_planning" ]]; then
  check_cmd "planning : jalons du 1er mars 2027 et du 30 juin 2027" \
    _f7c_doc_contient planning.md '1(er)? mars( 2027)?|2027-03-01|01/03/2027' '30 juin( 2027)?|2027-06-30|30/06/2027'
  _f7_s06_dates() {
    (($(grep -Eoi '([0-9]{1,2}(er)?[[:space:]]+(janv|f(é|e)vr|mars|avr|mai|juin|juil|d(é|e)c)[a-zé.]*)|(20[0-9]{2}-[01][0-9]-[0-3][0-9])' <<<"$_f7_s06_planning" |
      tr '[:upper:]' '[:lower:]' | sort -u | grep -c . || true) >= 8))
  }
  check_cmd "planning : au moins 8 jalons datés distincts" _f7_s06_dates
  check_cmd "planning : chemin critique identifié" _f7c_doc_contient planning.md 'chemin critique'
  _f7_s06_raci() {
    grep -Eqi 'RACI' <<<"$_f7_s06_planning" &&
      (($(grep -Eo '\|[[:space:]]*(R|A|C|I|A/R|R/A)[[:space:]]*(\||$)' <<<"$_f7_s06_planning" | grep -c . || true) >= 10))
  }
  check_cmd "planning : matrice RACI (au moins 10 cellules R, A, C ou I)" _f7_s06_raci
else
  skip "contenu du planning" "document absent"
fi

check_cmd "risques.md présent sur main" _f7c_doc_present risques.md
if [[ -n "$_f7_s06_risques" ]]; then
  check_cmd "risques : au moins $_f7c_min_risques risques RSQ-nn ($(_f7c_nb_ids "$_f7_s06_risques" "$_F7C_RE_RSQ") trouvés)" \
    _f7c_doc_nb_ids_min risques.md "$_F7C_RE_RSQ" "$_f7c_min_risques"
  check_cmd "risques : probabilité, impact, propriétaire et réponse décrits" \
    _f7c_doc_contient risques.md 'probabilit' 'impact' 'propri(é|e)taire' '(é|e)viter|r(é|e)duire|transf(é|e)rer|accepter'
  check_cmd "risques : chaque risque porte une cotation chiffrée (cellule de 1 à 4) sur sa ligne" \
    _f7c_part_liees_min "$_f7_s06_risques" "$_F7C_RE_RSQ" '\|[[:space:]]*[1-4][[:space:]]*\|' 0.8
else
  skip "contenu du registre des risques" "document absent"
fi

check_cmd "run.md présent sur main" _f7c_doc_present run.md
if _f7c_doc_present run.md; then
  check_cmd "run : support du samedi, astreinte, priorités P1 à P3, rapport mensuel, montée en compétences" \
    _f7c_doc_contient run.md 'samedi' 'astreinte' 'P1' 'P3' 'rapport mensuel' 'formation|comp(é|e)tences|bin(ô|o)me'
else
  skip "contenu du run" "document absent"
fi
