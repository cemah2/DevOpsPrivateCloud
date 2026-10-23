# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S12.sh — F7-S12 « Le dossier de soutenance » (RED publié) : présence et contenu minimal des
# quatre pièces dans docs/capstone/soutenance/ ; la qualité se juge avec le corrigé. Lecture seule.

# shellcheck source=_f7-livraison.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f7-livraison.sh"

title "F7-S12 — Le dossier de soutenance"
require_cmd curl jq

_f7c_charger soutenance/document-architecture.md soutenance/synthese-direction.md \
  soutenance/script-demonstration.md soutenance/annexes-preuves.md

check_cmd "document-architecture.md : traçabilité exigences → décisions → preuves (ENF, ESC, ERV cités)" \
  _f7c_doc_contient soutenance/document-architecture.md 'ENF-0[36]' 'ESC-0[46]' 'ERV-0[24]' 'ADR-037' 'preuve'
check_cmd "document-architecture.md : écarts preuve de concept / cible, réversibilité, risques" \
  _f7c_doc_contient soutenance/document-architecture.md '(é|e)cart' 'cible' 'r(é|e)versibilit' 'risque'
_f7_s12_synthese() {
  local c n
  c="$(_f7c_doc soutenance/synthese-direction.md)"
  [[ -n "$c" ]] || return 1
  n="$(wc -w <<<"$c")"
  ((n >= 300 && n <= 1400)) || return 1
  grep -Eqi '99[,.]9' <<<"$c" && grep -Eqi 'RTO|4 ?h' <<<"$c" && grep -Eqi 'RPO|15 ?min' <<<"$c" &&
    grep -Eqi '€|euros?' <<<"$c" && grep -Eqi 'fourn' <<<"$c"
}
check_cmd "synthese-direction.md : deux pages au plus, disponibilité, RTO, RPO, coût, ce que le GHSV fournit" _f7_s12_synthese
_f7_s12_script() {
  local c
  c="$(_f7c_doc soutenance/script-demonstration.md)"
  [[ -n "$c" ]] || return 1
  grep -Eqi 'plan b' <<<"$c" && grep -Eqi 'T ?[-−] ?30|liste de contr(ô|o)le' <<<"$c" &&
    (($(grep -Ec '([0-9]{1,2} ?min|[0-9]{1,2}:[0-9]{2})' <<<"$c") >= 5))
}
check_cmd "script-demonstration.md : déroulé minuté, état de départ vérifié, plan B" _f7_s12_script
check_cmd "annexes-preuves.md : preuves réelles et leur emplacement (preuves-conformite, rapports, MR)" \
  _f7c_doc_contient soutenance/annexes-preuves.md 'preuves-conformite|ms-preuves' 'rapport' '(MR|merge_requests|!)[ /]?[0-9]+'
