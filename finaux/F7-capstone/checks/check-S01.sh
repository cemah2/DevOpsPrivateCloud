# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S01.sh — F7-S01 « Lire le cahier des charges » (RED publié) : présence et contenu minimal de
# docs/capstone/analyse-cdc.md et docs/capstone/questions-client.md (sections, exigences du cahier des
# charges citées, opérations de l'annexe A1, incohérences, hypothèses, questions). Lecture seule
# (GitLab). La qualité de l'analyse se juge avec le corrigé.

# shellcheck source=_f7-capstone.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-capstone.sh"

title "F7-S01 — Lire le cahier des charges"
require_cmd curl jq

_f7c_charger analyse-cdc.md questions-client.md
_f7_s01_analyse="$(_f7c_doc analyse-cdc.md)"
_f7_s01_questions="$(_f7c_doc questions-client.md)"

check_cmd "analyse-cdc.md présent sur main ($_f7c_doc_dir/)" _f7c_doc_present analyse-cdc.md
if [[ -n "$_f7_s01_analyse" ]]; then
  check_cmd "analyse : sections périmètre, hors périmètre, besoin ↔ solution, incohérences, hypothèses, recommandation" \
    _f7c_doc_sections analyse-cdc.md 'p(é|e)rim(è|e)tre' 'hors[ -]p(é|e)rim' 'besoin|solution|(é|e)cart' \
    'incoh(é|e)ren|contradict' 'hypoth' 'recommand|d(é|e)cision|go'
  check_cmd "analyse : au moins 15 exigences distinctes du cahier des charges citées ($(_f7c_nb_ids "$_f7_s01_analyse" "$_F7C_RE_CDC") trouvées)" \
    _f7c_doc_nb_ids_min analyse-cdc.md "$_F7C_RE_CDC" 15
  check_cmd "analyse : les six opérations de l'annexe A1 (operationId) sont confrontées à l'API réelle" \
    _f7c_doc_cite_operations analyse-cdc.md
  check_cmd "analyse, incohérences : les exigences contradictoires sur la perte de données (PRA et intégrité des rendez-vous) sont relevées" \
    _f7c_section_contient analyse-cdc.md 'incoh(é|e)ren|contradict' 'ENF-06' 'ENF-07'
  check_cmd "analyse, incohérences : la contradiction entre conservation des journaux et destruction en fin de marché est relevée" \
    _f7c_section_contient analyse-cdc.md 'incoh(é|e)ren|contradict' 'ESC-08' 'ERV-04'
  check_cmd "analyse, incohérences : les exigences irréalistes (temps de réponse, calendrier de mise en service) sont relevées" \
    _f7c_section_contient analyse-cdc.md 'incoh(é|e)ren|contradict|irr(é|e)ali' 'ENF-05' 'MES-0[12]'
  check_cmd "analyse : au moins 5 hypothèses H-nn ($(_f7c_nb_ids "$_f7_s01_analyse" '(^|[^A-Za-z])H-[0-9]{2}') trouvées)" \
    _f7c_doc_nb_ids_min analyse-cdc.md '(^|[^A-Za-z])H-[0-9]{2}' 5
else
  skip "contenu de l'analyse" "document absent"
fi

check_cmd "questions-client.md présent sur main" _f7c_doc_present questions-client.md
if [[ -n "$_f7_s01_questions" ]]; then
  check_cmd "questions : au moins $_f7c_min_questions questions Q-nn ($(_f7c_nb_ids "$_f7_s01_questions" '(^|[^A-Za-z])Q-[0-9]{2}') trouvées)" \
    _f7c_doc_nb_ids_min questions-client.md '(^|[^A-Za-z])Q-[0-9]{2}' "$_f7c_min_questions"
  check_cmd "questions : chaque question est liée à une exigence du cahier des charges (même ligne ou même entrée)" \
    _f7c_part_liees_min "$_f7_s01_questions" '(^|[^A-Za-z])Q-[0-9]{2}' "$_F7C_RE_CDC" 0.9
else
  skip "contenu des questions" "document absent"
fi
