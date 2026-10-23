# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# check-S07.sh — F5-S07 « Le runbook de bascule et la cellule de crise » (RED publié) : présence et contenu
# minimal de RB-350 et de cellule-de-crise.md, et leur présence dans le miroir de adm02. Lecture seule.

# shellcheck source=_f5-par2.sh
source "$(dirname "${BASH_SOURCE[0]}")/_f5-par2.sh"

title "F5-S07 — Le runbook de bascule et la cellule de crise"
require_cmd curl jq ssh

_f5_s07_rb="$(_f5p_fichier "$_f5p_projet_doc" "$_f5p_doc_dir/runbooks/RB-350-bascule-par2.md" 2>/dev/null || true)"
check_cmd "RB-350 publié sur main" test -n "$_f5_s07_rb"
_f5_s07_rb_contenu() {
  local m
  for m in 'd(é|e)clench' 'vague' 'condition|crit(è|e)re de passage' 'non-retour|non retour' 'CNAME|noms? globa' \
    'RTO' 'RPO' 'PRA-TEMOIN|t(é|e)moin' 'RB-351' 'promotionToken|promot'; do
    grep -Eqi -- "$m" <<<"$_f5_s07_rb" || return 1
  done
}
check_cmd "RB-350 : déclenchement, vagues et conditions de passage, non-retour, noms, RTO/RPO (témoin), promotion, RB-351" \
  _f5_s07_rb_contenu
_f5_s07_vagues() { (($(grep -Eci '^#+ .*vague' <<<"$_f5_s07_rb") >= 4)); }
check_cmd "RB-350 : au moins quatre vagues titrées" _f5_s07_vagues

_f5_s07_cc="$(_f5p_fichier "$_f5p_projet_doc" "$_f5p_doc_dir/cellule-de-crise.md" 2>/dev/null || true)"
check_cmd "cellule-de-crise.md publié sur main" test -n "$_f5_s07_cc"
_f5_s07_cc_contenu() {
  local m
  for m in 'd(é|e)cid|d(é|e)cision' 'pilot' 'observ' 'communic' 'INC-6109' 'main courante' 'mod(è|e)le' 'canal|canaux|t(é|e)l(é|e)phone|SMS|Signal'; do
    grep -Eqi -- "$m" <<<"$_f5_s07_cc" || return 1
  done
}
check_cmd "cellule-de-crise.md : rôles (décision, pilotage, observation, communication), INC-6109, main courante, canaux, modèles" \
  _f5_s07_cc_contenu
_f5_s07_independant() { grep -Eqi 'ind(é|e)pendant|sans PAR1|hors (de )?PAR1|ne d(é|e)pend' <<<"$_f5_s07_cc"; }
check_cmd "cellule-de-crise.md : les canaux de crise sont dits indépendants de PAR1" _f5_s07_independant

_f5_s07_miroir() {
  _f5p_adm02 "git --git-dir='$_f5p_miroirs/$_f5p_projet_doc.git' cat-file -e 'main:$_f5p_doc_dir/runbooks/RB-350-bascule-par2.md' && \
    git --git-dir='$_f5p_miroirs/$_f5p_projet_doc.git' cat-file -e 'main:$_f5p_doc_dir/cellule-de-crise.md'"
}
check_cmd "adm02 : RB-350 et cellule-de-crise.md présents dans le miroir de $_f5p_projet_doc" _f5_s07_miroir
